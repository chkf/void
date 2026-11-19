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
        XCTAssertEqual(page.nodes.first?.children.first?.text("selection"), "appearance")
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
        try await until { page.nodes.first?.children.first?.text("selection") == "appearance" }
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
