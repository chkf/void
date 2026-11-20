import UIKit
import XCTest
@testable import VoidHost

@MainActor
final class NativeScrollViewportTests: XCTestCase {
    func testHeaderInTabScrollsBehindStatusBar() async throws {
        try await exercise(tabs: true, titled: false)
    }

    func testHeaderWithoutTabsScrollsBehindStatusBar() async throws {
        try await exercise(tabs: false, titled: false)
    }

    func testDeclaredTitleUsesSystemNavigation() async throws {
        try await exercise(tabs: true, titled: true)
    }

    private func exercise(tabs: Bool, titled: Bool) async throws {
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
          <Tab id="other" title="Other" systemName="circle"><Screen title="Other" /></Tab>
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
        let window = preview.window
        await host.importDirectory(project)
        let deadline = ContinuousClock.now + .seconds(100)
        while host.page == nil || host.busy {
            if let problem = host.problem { throw RuntimeIssue(problem) }
            guard ContinuousClock.now < deadline else { throw RuntimeIssue("Waiting for scroll sample") }
            try await Task.sleep(for: .milliseconds(40))
        }
        func descendants(_ view: UIView) -> [UIView] {
            [view] + view.subviews.flatMap { descendants($0) }
        }
        window.layoutIfNeeded()
        let scroll = try XCTUnwrap(descendants(window).compactMap { $0 as? UIScrollView }.first {
            $0.bounds.width > window.bounds.width / 2 && $0.contentSize.height > $0.bounds.height + 100
        })
        let top = window.safeAreaInsets.top
        let initial = scroll.contentOffset
        let prefix = titled ? "Titled" : (tabs ? "Tabs" : "Plain")
        var ancestor: UIView? = scroll
        while let view = ancestor {
            print("SCROLL \(prefix) \(type(of: view)) frame=\(view.convert(view.bounds, to: window)) safe=\(view.safeAreaInsets) clips=\(view.clipsToBounds)")
            ancestor = view.superview
        }
        print("SCROLL \(prefix) rest=\(initial) inset=\(scroll.adjustedContentInset) size=\(scroll.contentSize)")
        let rest = try await capture(window, prefix + "-Rest")
        let x = window.bounds.width * 0.74
        if !titled {
            try check(rest, x: x, y: top-6, rgb: [32, 72, 88])
            try check(rest, x: x, y: top+14, rgb: [80, 144, 144])
        }
        let delta = titled ? CGFloat(200) : max(top-12, 22)
        scroll.setContentOffset(CGPoint(x: initial.x, y: initial.y + delta), animated: false)
        try await Task.sleep(for: .milliseconds(450))
        print("SCROLL \(prefix) after=\(scroll.contentOffset) inset=\(scroll.adjustedContentInset) top=\(top)")
        let scrolled = try await capture(window, prefix + "-Scrolled")
        if titled {
            let bar = try XCTUnwrap(descendants(window).compactMap { $0 as? UINavigationBar }.first { !$0.isHidden && $0.topItem?.title == "Sample screen" })
            print("SCROLL collapsed navigation frame=\(bar.convert(bar.bounds, to: window))")
        } else {
            try check(scrolled, x: x, y: top-6, rgb: [80, 144, 144])
            // On iOS 27 the system softly blends the moving content near the clock.
            let edge = try sample(scrolled, x: x, y: 16)
            XCTAssertGreaterThan(Int(edge[1]), 72 + 12, "No moving content behind the status bar: \(edge)")
        }
        scroll.setContentOffset(initial, animated: false)
        try await Task.sleep(for: .milliseconds(150))
        if !titled {
            let returned = try await capture(window, prefix + "-Returned")
            try check(returned, x: x, y: top-6, rgb: [32, 72, 88])
        }
        await host.showLibrary()
    }

    private func capture(_ window: UIWindow, _ name: String) async throws -> UIImage {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(data: try XCTUnwrap(image.pngData()), uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if ProcessInfo.processInfo.environment["VOID_SCROLL_SCREENSHOTS"] == "1" {
            let tmp = FileManager.default.temporaryDirectory
            let ack = tmp.appendingPathComponent("void-scroll-done")
            let nameFile = tmp.appendingPathComponent("void-scroll-request")
            try name.write(to: nameFile, atomically: true, encoding: .utf8)
            let deadline = ContinuousClock.now + .seconds(15)
            while (try? String(contentsOf: ack, encoding: .utf8)) != name && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        return image
    }

    private func check(_ image: UIImage, x: CGFloat, y: CGFloat, rgb: [Int], file: StaticString = #filePath, line: UInt = #line) throws {
        let bytes = try sample(image, x: x, y: y)
        XCTAssertTrue(zip(bytes, rgb).allSatisfy { abs(Int($0.0)-$0.1) <= 8 },
                      "Viewport (\(x), \(y)) = \(bytes.prefix(3)), expected \(rgb)", file: file, line: line)
    }

    private func sample(_ image: UIImage, x: CGFloat, y: CGFloat) throws -> [UInt8] {
        let point = CGRect(x: floor(x * image.scale), y: floor(y * image.scale), width: 1, height: 1)
        let crop = try XCTUnwrap(image.cgImage?.cropping(to: point))
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let ctx = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes
    }
}
