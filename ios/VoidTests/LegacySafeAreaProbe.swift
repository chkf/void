import UIKit
import XCTest
@testable import VoidHost

@MainActor final class LegacySafeAreaProbe: XCTestCase {
    func testInspectVisibleWebKitRow() async throws {
        let name = try XCTUnwrap(ProcessInfo.processInfo.environment["VOID_NATIVE_UI_PROJECT"])
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storage) }
        let model = HostModel(storage: storage)
        let host = try await PreviewTestWindow(model)
        defer { host.close() }
        let window = host.window
        await model.importDirectory(FolderGrant.documents.appendingPathComponent(name))
        let deadline = ContinuousClock.now + .seconds(100)
        while model.page == nil || model.busy {
            guard model.problem == nil && ContinuousClock.now < deadline else { throw RuntimeIssue(model.problem ?? "No frame") }
            try await Task.sleep(for: .milliseconds(50))
        }
        let page = try XCTUnwrap(model.page)
        let wk = page.view
        let original = wk.alpha
        defer { wk.alpha = original }
        print("Build \(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "") viewport \(window.bounds) safe \(window.safeAreaInsets) surface \(wk.convert(wk.bounds, to: window)) canvas \(page.sdk.canvasHeight)")
        func attach(_ name: String) {
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let photo = XCTAttachment(data: image.pngData()!, uniformTypeIdentifier: "public.png")
            photo.name = name
            photo.lifetime = .keepAlways
            add(photo)
        }
        attach("Old-Window")
        wk.alpha = 0
        try await Task.sleep(for: .milliseconds(150))
        attach("Old-Window-WebKitTransparent")
        await model.showLibrary()
    }
}
