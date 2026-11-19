import SwiftUI
import XCTest
@testable import VoidHost

@MainActor
final class NativeTabEventTests: XCTestCase {
    private func until(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(100)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw RuntimeIssue("等待原生导航状态超时") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func tabs(in controller: UIViewController?) -> UITabBarController? {
        if let tabBar = controller as? UITabBarController { return tabBar }
        for child in controller?.children ?? [] {
            if let tabBar = tabs(in: child) { return tabBar }
        }
        return nil
    }

    func testOnlyProjectTabsAppearAndDeclinedSelectionStaysInProject() async throws {
        let files = FileManager.default
        let folder = FolderGrant.documents.appendingPathComponent("VoidSettings-" + UUID().uuidString)
        let storage = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? files.removeItem(at: folder); try? files.removeItem(at: storage) }
        let tools = try XCTUnwrap(Bundle.main.url(forResource: "Toolchain", withExtension: nil))
        try files.copyItem(at: tools.appendingPathComponent("NativeUIDemo"), to: folder)
        let source = """
        import { useState } from "react";
        import { render, TabView, Tab, Button, Form, Section, ProjectManagementButton } from "@runtime/ui";
        function App() {
          const [layout, setLayout] = useState(0);
          const ids = layout === 0 ? ["a","b"] : ["a","b","c","d","e"];
          return <TabView selection="a" onChange={() => {}}>{ids.map(id =>
            <Tab key={id} id={id} title={id === "e" ? "我的" : id} systemName="circle">
              <Button label="切换布局" onPress={() => setLayout(n => (n + 1) % 3)} />
              {layout === 2 && id === "e" && <Form><Section title="设置"><ProjectManagementButton /></Section></Form>}
            </Tab>)}</TabView>;
        }
        render(<App />);
        """
        try Data(source.utf8).write(to: folder.appendingPathComponent("app/src/main.tsx"))
        let host = HostModel(storage: storage)
        let window = try await PreviewTestWindow(host)
        defer { window.close() }
        await host.importDirectory(folder)
        try await until { host.page != nil || host.problem != nil || host.notice != nil }
        let page = try XCTUnwrap(host.page, host.problem ?? host.notice ?? "")
        try await until { self.tabs(in: window.window.rootViewController)?.viewControllers?.count == 2 }
        let controller = try XCTUnwrap(tabs(in: window.window.rootViewController))
        let first = try XCTUnwrap(controller.selectedViewController)
        func nextLayout() throws {
            let button = try XCTUnwrap(page.nodes.first?.children.first?.children.first)
            XCTAssertGreaterThan(page.event(button.id, name: "onPress", value: NSNull()), 0)
        }

        XCTAssertEqual(controller.viewControllers?.compactMap { $0.tabBarItem.title }, ["a", "b"])
        XCTAssertNil(page.legacyManagementContainerID)
        try nextLayout()
        try await until { controller.viewControllers?.count == 5 }
        XCTAssertEqual(controller.viewControllers?.compactMap { $0.tabBarItem.title }, ["a", "b", "c", "d", "我的"])
        XCTAssertNil(page.legacyManagementContainerID)
        try nextLayout()
        try await until { page.nodes.first?.children.last?.first { $0.type == "ProjectManagementButton" } != nil }
        XCTAssertEqual(controller.viewControllers?.count, 5)
        XCTAssertNil(page.legacyManagementContainerID)
        let profile = try XCTUnwrap(controller.viewControllers?.last)
        let acknowledged = page.acknowledged
        XCTAssertEqual(controller.delegate?.tabBarController?(controller, shouldSelect: profile), true)
        controller.selectedViewController = profile
        controller.delegate?.tabBarController?(controller, didSelect: profile)
        try await until { page.acknowledged > acknowledged && controller.selectedViewController === first }
        XCTAssertNil(window.window.rootViewController?.presentedViewController)
        try nextLayout()
        try await until { controller.viewControllers?.count == 2 }
        XCTAssertTrue(controller.selectedViewController === first)
        XCTAssertTrue(host.page === page)
        await host.showLibrary()
    }

    func testRapidSystemSelectionsUseOneWebKitAndRetainControllers() async throws {
        let files = FileManager.default
        let folder = FolderGrant.documents.appendingPathComponent("VoidTabs-" + UUID().uuidString)
        let storage = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? files.removeItem(at: folder); try? files.removeItem(at: storage) }
        let tools = try XCTUnwrap(Bundle.main.url(forResource: "Toolchain", withExtension: nil))
        try files.copyItem(at: tools.appendingPathComponent("NativeUIDemo"), to: folder)
        let host = HostModel(storage: storage)
        let window = try await PreviewTestWindow(host)
        defer { window.close() }
        await host.importDirectory(folder)
        try await until { host.page != nil || host.problem != nil || host.notice != nil }
        let page = try XCTUnwrap(host.page, host.problem ?? host.notice ?? "")
        try await until { self.tabs(in: window.window.rootViewController) != nil }
        let controller = try XCTUnwrap(tabs(in: window.window.rootViewController))
        let original = try XCTUnwrap(controller.viewControllers)
        XCTAssertEqual(original.count, 2)
        let surface = page.view
        let first = page.revision
        let nav = try XCTUnwrap(page.nodes.first?.children.first)
        func find(_ node: NativeNode, _ predicate: (NativeNode) -> Bool) -> NativeNode? {
            if predicate(node) { return node }
            for child in node.children {
                if let found = find(child, predicate) { return found }
            }
            return nil
        }
        let disabled = try XCTUnwrap(find(nav) { $0.text("label") == "复位" })
        XCTAssertEqual(page.event(disabled.id, name: "onPress", value: NSNull()), 0)
        // Simulate the system delegate's sequence in one main-thread turn so
        // intermediate WebKit ACKs cannot catch up between selections.
        for i in 0..<21 {
            let target = original[i.isMultiple(of: 2) ? 1 : 0]
            controller.selectedViewController = target
            controller.delegate?.tabBarController?(controller, didSelect: target)
        }
        try await until { page.acknowledged == 21 || host.problem != nil }
        XCTAssertNil(host.problem)
        XCTAssertEqual(page.nodes.first?.children.first?.text("selection"), "settings")
        XCTAssertTrue(controller.selectedViewController === original[1])
        controller.selectedViewController = original[0]
        controller.delegate?.tabBarController?(controller, didSelect: original[0])
        try await until { page.acknowledged == 22 }
        let input = try XCTUnwrap(find(nav) { $0.type == "TextField" })
        let seq = page.event(input.id, name: "onChange", value: "draft")
        try await until { page.acknowledged == seq }
        XCTAssertEqual(page.event(nav.id, name: "onChange", value: "components", displayedRevision: first), 0)
        controller.selectedViewController = original[1]
        controller.delegate?.tabBarController?(controller, didSelect: original[1])
        try await until { page.nodes.first?.children.first?.text("selection") == "settings" }
        controller.selectedViewController = original[0]
        controller.delegate?.tabBarController?(controller, didSelect: original[0])
        try await until { page.nodes.first?.children.first?.text("selection") == "components" }
        XCTAssertEqual(find(try XCTUnwrap(page.nodes.first)) { $0.type == "TextField" }?.text("value"), "draft")
        XCTAssertTrue(host.page === page && page.view === surface && surface.window === window.window)
        XCTAssertTrue(controller.viewControllers?[0] === original[0])
        XCTAssertTrue(controller.viewControllers?[1] === original[1])
        await host.showLibrary()
    }
}
