import UIKit
import XCTest
@testable import VoidHost

@MainActor
final class NativeScrollViewportTests: XCTestCase {
    func testMovingHeaderInTab() async throws { try await checkScroll(tabs: true, titled: false) }
    func testMovingHeaderWithoutTabs() async throws { try await checkScroll(tabs: false, titled: false) }
    func testDeclaredScrollTitle() async throws { try await checkScroll(tabs: true, titled: true) }

    private func checkScroll(tabs: Bool, titled: Bool) async throws {
        let files = FileManager.default
        let project = FolderGrant.documents.appendingPathComponent(UUID().uuidString)
        let storage = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? files.removeItem(at: project); try? files.removeItem(at: storage) }
        let tools = try XCTUnwrap(Bundle.main.url(forResource: "Toolchain", withExtension: nil))
        try files.copyItem(at: tools.appendingPathComponent("NativeUIDemo"), to: project)
        let title = titled ? #" title="Sample screen""# : ""
        let screen = """
        <Screen\(title)><ScrollView>
          <Card background="surface" cornerRadius={0} padding={12}>
            <HStack><Text value="Scroll heading" font="title" /><Spacer /></HStack>
          </Card>
          <TextField label="Draft" value="" onChange={() => {}} />
          {Array.from({ length: 72 }, (_, i) => <Text key={i} value={"Row " + i} />)}
        </ScrollView></Screen>
        """
        let content = tabs ? """
        <TabView selection="sample" onChange={() => {}}>
          <Tab id="sample" title="Sample" systemName="square">\(screen)</Tab>
          <Tab id="other" title="Other" systemName="circle"><Screen /></Tab>
        </TabView>
        """ : screen
        let source = """
        import { render, Theme, TabView, Tab, Screen, ScrollView, Card, HStack, Text, TextField, Spacer } from "@runtime/ui";
        render(<Theme mode="dark" dark={{background: "#204858", surface: "#509090"}}>\(content)</Theme>);
        """
        try source.write(to: project.appendingPathComponent("app/src/main.tsx"), atomically: true, encoding: .utf8)
        let host = HostModel(storage: storage)
        let preview = try await PreviewTestWindow(host)
        defer { preview.close() }
        await host.importDirectory(project)
        let deadline = ContinuousClock.now + .seconds(100)
        while host.page == nil || host.busy {
            if let problem = host.problem { throw RuntimeIssue(problem) }
            guard ContinuousClock.now < deadline else { throw RuntimeIssue("Waiting for the scroll sample") }
            try await Task.sleep(for: .milliseconds(40))
        }

        let window = preview.window
        window.layoutIfNeeded()
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap { descendants($0) } }
        let views = descendants(window)
        let scroll = try XCTUnwrap(views.compactMap { $0 as? UIScrollView }.first {
            $0.bounds.width > window.bounds.width / 2 && $0.contentSize.height > $0.bounds.height + 100
        })
        let prefix = titled ? "Titled" : (tabs ? "Tabs" : "Plain")
        func capture(_ name: String) throws -> UIImage {
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(data: try XCTUnwrap(image.pngData()), uniformTypeIdentifier: "public.png")
            attachment.name = prefix + "-" + name
            attachment.lifetime = .keepAlways
            add(attachment)
            return image
        }
        let top = window.safeAreaInsets.top
        let rest = scroll.contentOffset
        let atRest = try capture("Rest")
        let phone = window.traitCollection.userInterfaceIdiom == .phone
        let x = window.bounds.width * 0.74
        let statusEdge = CGPoint(x: x, y: top - 6)
        func expect(_ image: UIImage, at point: CGPoint, rgb: [Int], line: UInt = #line) throws {
            let actual = try XCTUnwrap(sampleSRGBPixel(image, at: point))
            XCTAssertTrue(zip(actual, rgb).allSatisfy { abs($0.0 - $0.1) <= 8 }, "\(point) \(actual), expected \(rgb)", line: line)
        }
        if phone && !titled {
            XCTAssertEqual(scroll.convert(scroll.bounds, to: window).minY, 0, accuracy: 1)
            XCTAssertEqual(scroll.adjustedContentInset.top, top, accuracy: 1)
            try expect(atRest, at: statusEdge, rgb: [32, 72, 88])
            try expect(atRest, at: CGPoint(x: x, y: top + 14), rgb: [80, 144, 144])
        }
        let delta = titled ? CGFloat(200) : max(22, top - 12)
        scroll.setContentOffset(CGPoint(x: rest.x, y: rest.y + delta), animated: false)
        try await Task.sleep(for: .milliseconds(450))
        let moved = try capture("Scrolled")
        XCTAssertGreaterThan(scroll.contentOffset.y, rest.y + 12)
        if titled {
            let hasTitleBar = descendants(window).compactMap { $0 as? UINavigationBar }.contains {
                !$0.isHidden && $0.topItem?.title == "Sample screen"
            }
            XCTAssertEqual(hasTitleBar, phone || !tabs)
        } else if phone {
            try expect(moved, at: statusEdge, rgb: [80, 144, 144])
            // The platform blends the passing header near the clock. Its green channel
            // still rises above the resting background even with the native scroll edge.
            let underClock = try XCTUnwrap(sampleSRGBPixel(moved, at: CGPoint(x: x, y: 16)))
            XCTAssertGreaterThan(underClock[1], 84)
        }
        scroll.setContentOffset(rest, animated: false)
        try await Task.sleep(for: .milliseconds(200))
        if phone && !titled { try expect(try capture("Returned"), at: statusEdge, rgb: [32, 72, 88]) }
        await host.showLibrary()
    }
}
