import UIKit
import WebKit
import XCTest
@testable import VoidHost

@MainActor
private final class FrameObserver: NSObject {
    var onFrame: () -> Void = {}
    @objc func frame() { onFrame() }
}

@MainActor
final class NativeSafeAreaTests: XCTestCase {
    func testFirstDisplayedDarkFrame() async throws { try await firstFrame(style: .dark, rgb: [32, 72, 88]) }
    func testFirstDisplayedLightFrame() async throws { try await firstFrame(style: .light, rgb: [200, 232, 224]) }

    func testHiddenCandidateAndCompilerKeepTheDisplayedPalette() async throws {
        let files = FileManager.default
        let name = try XCTUnwrap(ProcessInfo.processInfo.environment["VOID_SAFE_AREA_PROJECT"])
        let folder = FolderGrant.documents.appendingPathComponent(UUID().uuidString)
        let storage = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? files.removeItem(at: folder); try? files.removeItem(at: storage) }
        try files.copyItem(at: FolderGrant.documents.appendingPathComponent(name), to: folder)
        let entry = folder.appendingPathComponent("app/src/main.tsx")
        let source = try String(contentsOf: entry, encoding: .utf8)
        let host = HostModel(storage: storage)
        let preview = try await PreviewTestWindow(host)
        let window = preview.window
        let original = window.overrideUserInterfaceStyle
        window.overrideUserInterfaceStyle = .dark
        defer { window.overrideUserInterfaceStyle = original; preview.close() }
        func wait(_ condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now + .seconds(100)
            while !condition() {
                guard ContinuousClock.now < deadline else { throw RuntimeIssue(host.problem ?? "Waiting for test page") }
                try await Task.sleep(for: .milliseconds(25))
            }
        }
        func check(_ expected: [Int], file: StaticString = #filePath, line: UInt = #line) {
            let frame = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            for y in [CGFloat(8), window.bounds.midY] {
                let point = CGPoint(x: window.bounds.width * 0.24, y: y)
                let actual = sampleSRGBPixel(frame, at: point) ?? []
                XCTAssertTrue(actual.count == 3 && zip(actual, expected).allSatisfy { abs($0.0 - $0.1) <= 8 },
                              "\(point) \(actual), expected \(expected)", file: file, line: line)
            }
        }
        await host.importDirectory(folder)
        try await wait { !host.busy && host.page != nil }
        let first = try XCTUnwrap(host.page)
        check([32, 72, 88])
        let replacement = source.replacingOccurrences(of: ">(\"system\")", with: ">(\"light\")")
            .replacingOccurrences(of: "render(<Sample />);", with: """
            document.documentElement.dataset.ready = "yes";
            window.addEventListener("show-sample", () => render(<Sample />), { once: true });
            """)
        try replacement.write(to: entry, atomically: true, encoding: .utf8)
        host.refresh(force: true)
        try await wait { host.compiler != nil }
        check([32, 72, 88])
        try await wait { host.candidate?.view.url != nil && host.candidate?.view.isLoading == false }
        let next = try XCTUnwrap(host.candidate)
        // Hold the real source verification between the candidate's first tree and promotion.
        let held = expectation(description: "Coordinated test directory")
        let release = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt: folder, options: .forReplacing, error: &error) { _ in
                held.fulfill()
                _ = release.wait(timeout: .now() + 10)
            }
        }
        defer { release.signal() }
        await fulfillment(of: [held], timeout: 5)
        let ready = try await next.view.evaluateJavaScript("document.documentElement.dataset.ready")
        XCTAssertEqual(ready as? String, "yes")
        _ = try await next.view.evaluateJavaScript("dispatchEvent(new Event('show-sample'))")
        try await wait { next.revision > 0 }
        XCTAssertTrue(host.page === first && host.presentingPage == nil)
        check([32, 72, 88])
        release.signal()
        try await wait { host.page === next && !host.busy }
        check([200, 232, 224])
        try "invalid TSX (".write(to: entry, atomically: true, encoding: .utf8)
        host.refresh(force: true)
        try await wait { host.problem != nil && !host.busy }
        XCTAssertTrue(host.page === next)
        check([200, 232, 224])
        await host.showLibrary()
    }

    private func firstFrame(style: UIUserInterfaceStyle, rgb: [Int]) async throws {
        let name = try XCTUnwrap(ProcessInfo.processInfo.environment["VOID_SAFE_AREA_PROJECT"])
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storage) }
        let host = HostModel(storage: storage)
        let preview = try await PreviewTestWindow(host)
        let window = preview.window
        let original = window.overrideUserInterfaceStyle
        window.overrideUserInterfaceStyle = style
        defer { window.overrideUserInterfaceStyle = original; preview.close() }

        let first = expectation(description: "First display refresh containing the sample's content background")
        let observer = FrameObserver()
        let link = CADisplayLink(target: observer, selector: #selector(FrameObserver.frame))
        defer { link.invalidate() }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        observer.onFrame = { [weak link] in
            guard let page = host.presentingPage ?? host.page, page.view.window === window else { return }
            let frame = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: false) }
            // The outgoing host overview can still be on the display at the first callback.
            guard let body = sampleSRGBPixel(frame, at: CGPoint(x: window.bounds.width * 0.85, y: window.bounds.midY)),
                  zip(body, rgb).allSatisfy({ abs($0.0 - $0.1) <= 8 }) else { return }
            link?.invalidate()
            let attachment = XCTAttachment(data: frame.pngData()!, uniformTypeIdentifier: "public.png")
            attachment.name = style == .dark ? "First-Dark-Window" : "First-Light-Window"
            attachment.lifetime = .keepAlways
            self.add(attachment)
            func describe(_ label: String, _ view: UIView?) {
                guard let view else { return }
                print("\(label) bounds=\(view.convert(view.bounds, to: window)) safe=\(view.safeAreaInsets) clips=\(view.clipsToBounds) bg=\(String(describing: view.backgroundColor))")
            }
            func findTabs(_ vc: UIViewController?) -> UITabBarController? {
                if let tabs = vc as? UITabBarController { return tabs }
                for child in vc?.children ?? [] {
                    if let tabs = findTabs(child) { return tabs }
                }
                return nil
            }
            let tab = findTabs(window.rootViewController)
            print("Visible page \(page.id) revision=\(page.revision) stage=\(host.scanStatus ?? "idle") window=\(window.bounds) safe=\(window.safeAreaInsets)")
            describe("Host", window.rootViewController?.viewIfLoaded)
            describe("Tabs", tab?.viewIfLoaded)
            describe("Selected", tab?.selectedViewController?.viewIfLoaded)
            describe("WebKit", page.view)
            var samples = [CGPoint(x: window.bounds.width * 0.24, y: 8)]
            if window.traitCollection.userInterfaceIdiom == .phone,
               let tabView = tab?.viewIfLoaded {
                let top = window.safeAreaInsets.top
                let tabY = tabView.convert(tabView.bounds, to: window).minY
                samples += [top - 1, top, max(top, (top + tabY) / 2)].map { CGPoint(x: 8, y: $0) }
            }
            for point in samples {
                let sample = sampleSRGBPixel(frame, at: point)
                XCTAssertEqual(sample?.count, 3)
                XCTAssertTrue(zip(sample ?? [], rgb).allSatisfy { abs($0.0 - $0.1) <= 8 },
                              "First displayed \(point) \(String(describing: sample)), content \(body)")
            }
            first.fulfill()
        }
        link.add(to: .main, forMode: .common)
        await host.importDirectory(FolderGrant.documents.appendingPathComponent(name))
        await fulfillment(of: [first], timeout: 110)
        await host.showLibrary()
    }
}

func sampleSRGBPixel(_ image: UIImage, at point: CGPoint) -> [Int]? {
    let rect = CGRect(x: floor(point.x * image.scale), y: floor(point.y * image.scale), width: 1, height: 1)
    guard let crop = image.cgImage?.cropping(to: rect), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    var rgba = [UInt8](repeating: 0, count: 4)
    let drawn = rgba.withUnsafeMutableBytes { bytes in
        guard let ctx = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                  bytesPerRow: 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return true
    }
    return drawn ? rgba.prefix(3).map(Int.init) : nil
}
