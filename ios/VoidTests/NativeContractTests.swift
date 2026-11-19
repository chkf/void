import XCTest
import UIKit
@testable import VoidHost

final class NativeContractTests: XCTestCase {
    typealias Row = [String: Any]

    private func node(_ type: String, _ props: Row = [:], _ children: [Row] = [], id: String = UUID().uuidString) -> Row {
        ["type": type, "props": props, "children": children, "id": id]
    }
    private func tab(_ id: String) -> Row {
        node("Tab", ["id": id, "title": id, "systemName": "circle"], [node("Screen")])
    }
    private func decode(_ rows: [Row], version: Int = 2) throws -> NativeCommit {
        try NativeCommit(message: ["revision": 1, "eventSequence": 0, "uiVersion": version, "nodes": rows])
    }

    func testWhitelistAndHierarchy() throws {
        for count in 2...5 {
            let tabs = (0..<count).map { tab("id-\($0)") }
            let nav = node("TabView", ["selection": "id-0"], tabs, id: "nav")
            let parsed = try decode([node("Theme", ["dark": ["accent": "#aBc123"]], [nav])])
            XCTAssertTrue(parsed.hasTabs)
            XCTAssertEqual(parsed.nodes.first?.palette("dark")["accent"], 0xABC123)
            XCTAssertTrue(parsed.actions["nav"]?.accepts("onChange", "id-1") == true)
            XCTAssertFalse(parsed.actions["nav"]?.accepts("onChange", "gone") == true)
        }
        let nav = node("TabView", ["selection": "a"], [tab("a"), tab("b")])
        let invalid: [[Row]] = [
            [tab("a")], [nav, node("Text", ["value":"outside"])], [node("Card", [:], [nav])],
            [node("TabView", ["selection":"a"], [tab("a")])],
            [node("TabView", ["selection":"a"], ["a","b","c","d","e","f"].map(tab))],
            [node("TabView", ["selection":"a"], [tab("a"),tab("a")])],
            [node("TabView", ["selection":"missing"], [tab("a"),tab("b")])],
            [node("TabView", ["selection":"a"], [tab("a"),node("Text", ["value":"b"])])],
            [node("Theme", [:], [node("Theme")])], [node("ScrollView", [:], [node("Card", [:], [node("Form")])])],
            [node("Button")], [node("Image", ["systemName":"circle", "label":" "])],
            [node("Button", ["label":"x", "disabled":1])], [node("Text", ["value":"x", "weight":"thicker"])],
            [node("Image", ["systemName":"x", "label":"x", "color":"#000000"])],
            [node("HStack", ["alignment":"leading"])], [node("Text", ["value":"x", "fontSize":14])],
            [node("Text", ["value":"x"], [node("Spacer")])], [node("HTML")],
            [node("TabView", ["selection":true], [tab("a"),tab("b")])],
            [node("Theme", ["light":["brand":"#FFFFFF"]])], [node("Theme", ["dark":["text":["color":"#000000"]]])],
            [node("Theme", ["light": ["#ffffff"]])], [node("Spacer", ["minLength":NSNull()])]
        ]
        for rows in invalid { XCTAssertThrowsError(try decode(rows), String(describing: rows)) }
        XCTAssertThrowsError(try decode([nav], version: 1))
        XCTAssertThrowsError(try decode([node("Text", ["value":"x", "font":"body"])], version: 1))
        XCTAssertThrowsError(try decode([], version: 3))
    }

    func testColorNumberAndResourceBounds() throws {
        for color in ["red","#abc","#abcd","#01234567"," #123456","#12z456","＃112233","#+12345","#123456\n"] {
            XCTAssertThrowsError(try decode([node("Theme", ["dark":["text":color]])]), color)
        }
        let badNumbers: [Any] = [true, "5", -1, 129, Double.infinity, -Double.infinity, Double.nan]
        for number in badNumbers { XCTAssertThrowsError(try decode([node("VStack", ["spacing":number])])) }
        for props: Row in [["value":1,"total":0], ["value":2], ["value":-1], ["value":0,"total":1_000_000_001], ["value":true]] {
            XCTAssertThrowsError(try decode([node("ProgressView", props)]))
        }
        XCTAssertNoThrow(try decode([node("ProgressView", ["value":0.25]), node("Card", ["cornerRadius":0, "padding":64])]))
        XCTAssertThrowsError(try decode([node("Card", ["borderWidth":8.1])]))
        let textLimit = String(repeating:"a", count:4 * 1024 * 1024)
        XCTAssertThrowsError(try decode([node("Theme", ["light":["text":textLimit]])]))
        XCTAssertThrowsError(try decode([node("Screen", ["title":textLimit])]))
        var nested = node("Spacer")
        for _ in 0..<129 { nested = node("VStack", [:], [nested]) }
        XCTAssertThrowsError(try decode([nested]))
        let tooManyProperties = (0..<8_193).map { _ in node("Text", ["value":"x"]) }
        XCTAssertThrowsError(try decode(tooManyProperties))
        let disabled = try decode([node("Button", ["label":"x", "disabled":true], id:"b")])
        XCTAssertFalse(disabled.actions["b"]?.accepts("onPress", NSNull()) == true)
    }

    @MainActor
    func testDefaultSemanticContrastAndMissingSymbol() throws {
        func luminance(_ color: UIColor) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            XCTAssertTrue(color.getRed(&r, green:&g, blue:&b, alpha:&a))
            func linear(_ x: CGFloat) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        for dark in [false,true] {
            let palette = NativePalette(dark:dark, themed:true, overrides:[:])
            for background in [NativeColorRole.background, .surface] {
                for role in [NativeColorRole.text, .secondaryText, .accent, .success, .warning, .error] {
                    let a = luminance(palette.uiColor(role)), b = luminance(palette.uiColor(background))
                    XCTAssertGreaterThanOrEqual((max(a,b) + 0.05) / (min(a,b) + 0.05), 4.5, "\(role) / \(background)")
                }
            }
            let a = luminance(palette.uiColor(.onAccent)), b = luminance(palette.uiColor(.accent))
            XCTAssertGreaterThanOrEqual((max(a,b) + 0.05) / (min(a,b) + 0.05), 4.5)
        }
        XCTAssertEqual(NativeSymbol.image("void.nonexistent.symbol").pngData(), UIImage(systemName:"questionmark.circle")?.pngData())
    }

    func testReopeningVerifiedDev10NativeProductPreservesHistoryBytes() async throws {
        let id = UUID(), base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = base.appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(at:dir, withIntermediateDirectories:true)
        let key = "a-8f54b1ef5cb30086abd34dd6bc023b93e37a660ea339c51fe8761ce287056504"
        let product = Product(entry:"index.html", files:["index.html":Data()], mode:.native, revision:"a")
        try JSONEncoder().encode(product).write(to:dir.appendingPathComponent(key + ".json"))
        let original = try JSONEncoder().encode(BuildHistory(current:key, previous:"prior"))
        let history = dir.appendingPathComponent("history.json")
        try original.write(to:history)
        let store = ProductStore(base:base)
        let match = try await store.matching("a", project:id)
        try await store.confirm(try XCTUnwrap(match), project:id)
        XCTAssertEqual(try Data(contentsOf:history), original)
        let changed = try await store.matching("b", project:id)
        XCTAssertNil(changed)
    }
}
