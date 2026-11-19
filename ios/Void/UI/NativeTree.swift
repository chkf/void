import CoreFoundation
import Foundation

enum NativeColorRole: String, CaseIterable {
    case accent, background, surface, text, secondaryText, onAccent, success, warning, error
}

enum NativeValue {
    case text(String), flag(Bool), options([String]), number(Double), palette([String: UInt32])
}

struct NativeNode: Identifiable {
    let id: String
    let type: String
    let props: [String: NativeValue]
    let children: [NativeNode]

    func text(_ key: String) -> String {
        if case let .text(value) = props[key] { return value }
        return ""
    }
    func bool(_ key: String) -> Bool {
        if case let .flag(value) = props[key] { return value }
        return false
    }
    var flag: Bool { bool("value") }
    func number(_ key: String) -> Double? {
        if case let .number(value) = props[key] { return value }
        return nil
    }
    func palette(_ key: String) -> [String: UInt32] {
        if case let .palette(value) = props[key] { return value }
        return [:]
    }
    var options: [String] {
        if case let .options(value) = props["options"] { return value }
        return []
    }
}

private enum Field {
    case text, identifier, title, symbol, flag, options, palette
    case choice(Set<String>), number(ClosedRange<Double>)

    static let color = choice(Set(NativeColorRole.allCases.map(\.rawValue)))
    static let horizontal = choice(["leading", "center", "trailing"])
}

private struct NodeRule {
    let required: [String: Field]
    let optional: [String: Field]
    let container: Bool
    let since: Int
    init(_ required: [String: Field] = [:], _ optional: [String: Field] = [:], children: Bool = false, since: Int = 1) {
        self.required = required
        self.optional = optional
        self.container = children
        self.since = since
    }

    static let all: [String: NodeRule] = [
        "Text": NodeRule(["value": .text], [
            "font": .choice(["largeTitle","title","title2","title3","headline","subheadline","body","callout","footnote","caption","caption2"]),
            "weight": .choice(["light","regular","medium","semibold","bold","heavy"]),
            "color": .color, "alignment": .horizontal, "monospacedDigits": .flag]),
        "Image": NodeRule(["systemName": .text, "label": .text], ["size": .number(1...128), "color": .color]),
        "Button": NodeRule(["label": .text], ["icon": .symbol, "variant": .choice(["primary","secondary","plain","destructive"]),
                                               "disabled": .flag, "fullWidth": .flag]),
        "TextField": NodeRule(["label": .text, "value": .text]),
        "Toggle": NodeRule(["label": .text, "value": .flag]),
        "Picker": NodeRule(["label": .text, "value": .text, "options": .options]),
        "Form": NodeRule([:], ["appearance": .choice(["system","themed"])], children: true),
        "List": NodeRule([:], ["appearance": .choice(["system","themed"])], children: true),
        "Section": NodeRule(["title": .text], children: true),
        "HStack": NodeRule([:], ["alignment": .choice(["top","center","bottom","firstTextBaseline","lastTextBaseline"]),
                                 "spacing": .number(0...128)], children: true),
        "VStack": NodeRule([:], ["alignment": .horizontal, "spacing": .number(0...128)], children: true),
        "Theme": NodeRule([:], ["mode": .choice(["system","light","dark"]), "light": .palette, "dark": .palette], children: true, since: 2),
        "TabView": NodeRule(["selection": .identifier], children: true, since: 2),
        "Tab": NodeRule(["id": .identifier, "title": .title, "systemName": .symbol], children: true, since: 2),
        "Screen": NodeRule([:], ["title": .text], children: true, since: 2),
        "ScrollView": NodeRule(children: true, since: 2),
        "Card": NodeRule([:], ["background": .color, "border": .color, "borderWidth": .number(0...8),
                               "cornerRadius": .number(0...64), "padding": .number(0...64)], children: true, since: 2),
        "Spacer": NodeRule([:], ["minLength": .number(0...256)], since: 2),
        "ProgressView": NodeRule(["value": .number(0...1_000_000_000)], ["total": .number(0...1_000_000_000), "label": .text], since: 2)
    ]
}

enum NativeAction {
    case press(enabled: Bool), change, select(Set<String>)

    func accepts(_ name: String, _ value: Any) -> Bool {
        switch self {
        case .press(let enabled): return enabled && name == "onPress"
        case .change: return name == "onChange"
        case .select(let ids): return name == "onChange" && (value as? String).map(ids.contains) == true
        }
    }
}

struct NativeCommit {
    let uiVersion: Int
    let revision: Int
    let eventSequence: Int
    let nodes: [NativeNode]
    let actions: [String: NativeAction]

    var hasTabs: Bool {
        let root = nodes.first
        return root?.type == "TabView" || (root?.type == "Theme" && root?.children.first?.type == "TabView")
    }

    static func counter(_ value: Any?, minimum: Int) throws -> Int {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let result = value as? Int, result >= minimum else { throw RuntimeIssue("原生界面协议或修订号无效") }
        return result
    }

    init(message: [String: Any]) throws {
        uiVersion = try message["uiVersion"].map { try Self.counter($0, minimum: 1) } ?? 1
        guard uiVersion == 1 || uiVersion == 2 else { throw RuntimeIssue("不支持原生界面协议 \(uiVersion)，请使用匹配的 void 宿主") }
        revision = try Self.counter(message["revision"], minimum: 1)
        eventSequence = try Self.counter(message["eventSequence"], minimum: 0)
        var decoder = TreeDecoder(version: uiVersion)
        nodes = try decoder.read(message["nodes"], parent: nil, depth: 0, scrolling: false)
        actions = decoder.actions
    }
}

// Decode WebKit's Foundation values on the existing background task. No JSON round trip.
private struct TreeDecoder {
    let version: Int
    var seen = Set<String>()
    var actions = [String: NativeAction]()
    var remainingItems = 16_384
    var remainingText = 4 * 1024 * 1024

    mutating func consume(_ count: Int) throws {
        guard count <= remainingItems else { throw RuntimeIssue("单帧原生控件、选项和样式超过 16,384 项") }
        remainingItems -= count
    }

    mutating func string(_ value: Any?, _ path: String) throws -> String {
        guard let value = value as? String else { throw RuntimeIssue("\(path) 需要文本") }
        let bytes = value.utf8.count
        guard bytes <= remainingText else { throw RuntimeIssue("单帧原生界面文本超过 4 MiB") }
        remainingText -= bytes
        return value
    }

    mutating func field(_ kind: Field, value: Any, path: String) throws -> NativeValue {
        switch kind {
        case .flag:
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw RuntimeIssue("\(path) 需要布尔值") }
            return .flag(number.boolValue)
        case .number(let range):
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, range.contains(number.doubleValue) else { throw RuntimeIssue("\(path) 需要范围 \(range) 内的有限数值") }
            return .number(number.doubleValue)
        case .options:
            guard let values = value as? [Any] else { throw RuntimeIssue("\(path) 需要文本列表") }
            try consume(values.count)
            return .options(try values.map { try string($0, path) })
        case .palette:
            guard let pairs = value as? [String: Any], pairs.count <= NativeColorRole.allCases.count else { throw RuntimeIssue("\(path) 需要语义色表") }
            try consume(pairs.count)
            var colors = [String: UInt32]()
            for (role, raw) in pairs {
                guard NativeColorRole(rawValue: role) != nil else { throw RuntimeIssue("\(path) 含未知语义色") }
                _ = try string(role, path)
                let hex = try string(raw, path)
                let digits = hex.utf8.dropFirst()
                guard hex.hasPrefix("#"), digits.count == 6,
                      digits.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
                      let rgb = UInt32(hex.dropFirst(), radix: 16) else { throw RuntimeIssue("\(path).\(role) 需要 #RRGGBB") }
                colors[role] = rgb
            }
            return .palette(colors)
        case .choice(let choices):
            let name = try string(value, path)
            guard choices.contains(name) else { throw RuntimeIssue("\(path) 不是支持的选项") }
            return .text(name)
        case .text: return .text(try string(value, path))
        case .title, .identifier, .symbol:
            let text = try string(value, path)
            let limit: Int
            if case .title = kind { limit = 256 } else { limit = 128 }
            guard text.utf8.count <= limit, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw RuntimeIssue("\(path) 需要非空短文本（最多 \(limit) 字节）") }
            return .text(text)
        }
    }

    mutating func read(_ value: Any?, parent: String?, depth: Int, scrolling: Bool) throws -> [NativeNode] {
        guard let rows = value as? [Any] else { throw RuntimeIssue("原生控件列表无效") }
        try consume(rows.count)
        return try rows.map { raw in
            try Task.checkCancellation()
            guard depth <= 128, let row = raw as? [String: Any], let type = row["type"] as? String,
                  let rule = NodeRule.all[type], rule.since <= version else { throw RuntimeIssue("原生控件类型或深度超出协议 \(version) 支持范围") }
            guard let props = row["props"] as? [String: Any], let children = row["children"] as? [Any],
                  rule.container || children.isEmpty else { throw RuntimeIssue("\(type) 属性或子内容无效") }
            if type == "Theme" && (parent != nil || rows.count != 1) { throw RuntimeIssue("Theme 必须是唯一根节点") }
            if type == "TabView" && (rows.count != 1 || (parent != nil && parent != "Theme") || !(2...5).contains(children.count)) {
                throw RuntimeIssue("TabView 需要作为唯一页面容器并包含 2～5 个 Tab")
            }
            if (type == "Tab") != (parent == "TabView") { throw RuntimeIssue("Tab 只能作为 TabView 的直接子项") }
            let scrolls = type == "ScrollView" || type == "Form" || type == "List"
            if version == 2 && scrolling && scrolls { throw RuntimeIssue("\(type) 不能嵌入另一纵向滚动容器") }
            let id = try string(row["id"], "\(type).id")
            guard !id.isEmpty, seen.insert(id).inserted else { throw RuntimeIssue("原生控件标识无效或重复") }
            guard rule.required.keys.allSatisfy({ props[$0] != nil }), props.count <= rule.required.count + rule.optional.count else {
                throw RuntimeIssue("\(type) 缺少必填属性或含未知属性")
            }
            var decoded = [String: NativeValue]()
            if version == 2 { try consume(props.count) }
            for (key, rawValue) in props {
                guard var kind = rule.required[key] ?? (version == 2 ? rule.optional[key] : nil) else { throw RuntimeIssue("\(type) 含未知属性") }
                if version == 2 {
                    _ = try string(key, type)
                    if type == "Image" && key == "label" { kind = .title }
                    if type == "Image" && key == "systemName" { kind = .symbol }
                }
                decoded[key] = try field(kind, value: rawValue, path: "\(type).\(key)")
            }
            let nested = try read(children, parent: type, depth: depth + 1, scrolling: scrolling || scrolls)
            let node = NativeNode(id: id, type: type, props: decoded, children: nested)
            switch type {
            case "TabView":
                let ids = Set(nested.map { $0.text("id") })
                guard ids.count == nested.count, ids.contains(node.text("selection")) else { throw RuntimeIssue("Tab.id 必须唯一且 TabView.selection 必须存在") }
                actions[id] = .select(ids)
            case "Button": actions[id] = .press(enabled: !node.bool("disabled"))
            case "TextField", "Toggle", "Picker": actions[id] = .change
            case "ProgressView":
                let total = node.number("total") ?? 1
                guard total > 0, let value = node.number("value"), value <= total else { throw RuntimeIssue("ProgressView 需要 0 ≤ value ≤ total 且 total > 0") }
            default: break
            }
            return node
        }
    }
}
