import UIKit
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
            guard let body = self.pixel(frame, at: CGPoint(x: window.bounds.width * 0.85, y: window.bounds.midY)),
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
            let status = self.pixel(frame, at: CGPoint(x: window.bounds.width * 0.24, y: 8))
            XCTAssertEqual(status?.count, 3)
            XCTAssertTrue(zip(status ?? [], rgb).allSatisfy { abs($0.0 - $0.1) <= 8 },
                          "First displayed status \(String(describing: status)), content \(body)")
            first.fulfill()
        }
        link.add(to: .main, forMode: .common)
        await host.importDirectory(FolderGrant.documents.appendingPathComponent(name))
        await fulfillment(of: [first], timeout: 110)
        await host.showLibrary()
    }

    private func pixel(_ image: UIImage, at point: CGPoint) -> [Int]? {
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
}
