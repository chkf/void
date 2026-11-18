import Foundation
import SwiftUI

enum NativeValue: Decodable {
    case text(String), flag(Bool), options([String])
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let text = try? value.decode(String.self) { self = .text(text) }
        else if let flag = try? value.decode(Bool.self) { self = .flag(flag) }
        else { self = .options(try value.decode([String].self)) }
    }
}

struct NativeNode: Decodable, Identifiable {
    let id: String
    let type: String
    let props: [String: NativeValue]
    let children: [NativeNode]

    func text(_ key: String) -> String {
        if case let .text(value) = props[key] { return value }
        return ""
    }
    var flag: Bool {
        if case let .flag(value) = props["value"] { return value }
        return false
    }
    var options: [String] {
        if case let .options(value) = props["options"] { return value }
        return []
    }
}

struct NativeCommit: Decodable {
    let revision: Int
    let eventSequence: Int
    let nodes: [NativeNode]

    func validate() throws {
        var seen = Set<String>()
        let containers = ["HStack", "VStack", "Form", "List", "Section"]
        let required = ["Text": ["value"], "Image": ["systemName", "label"], "Button": ["label"],
                        "TextField": ["label", "value"], "Toggle": ["label", "value"], "Picker": ["label", "value", "options"],
                        "Section": ["title"], "HStack": [], "VStack": [], "List": [], "Form": []]
        func check(_ node: NativeNode, depth: Int) throws {
            guard depth <= 128, !node.id.isEmpty, seen.insert(node.id).inserted,
                  let keys = required[node.type], Set(keys) == Set(node.props.keys),
                  node.children.isEmpty || containers.contains(node.type) else {
                throw RuntimeIssue("无效的原生控件或属性 · " + node.type + " #" + node.id)
            }
            for key in keys {
                switch (node.type, key, node.props[key]) {
                case ("Toggle", "value", .flag), ("Picker", "options", .options): break
                case ("Toggle", "value", _), ("Picker", "options", _): throw RuntimeIssue("属性类型错误 · " + node.type + "." + key)
                case (_, _, .text): break
                default: throw RuntimeIssue("属性类型错误 · " + node.type + "." + key)
                }
            }
            for child in node.children { try check(child, depth: depth + 1) }
        }
        guard revision > 0, eventSequence >= 0 else { throw RuntimeIssue("原生界面修订号无效") }
        for node in nodes { try check(node, depth: 0) }
    }
}

struct NativeNodeView: View {
    let node: NativeNode
    @ObservedObject var page: ProjectPage

    private var children: some View {
        ForEach(node.children) { child in NativeNodeView(node: child, page: page) }
    }

    @ViewBuilder var body: some View {
        switch node.type {
        case "VStack": VStack(alignment: .leading) { children }
        case "HStack": HStack { children }
        case "Form": Form { children }
        case "List": List { children }
        case "Section": Section(node.text("title")) { children }
        case "Text": Text(verbatim: node.text("value"))
        case "Image": Image(systemName: node.text("systemName")).accessibilityLabel(node.text("label"))
        case "Button": Button(node.text("label")) { page.event(node.id, name: "onPress", value: NSNull()) }
        case "TextField": NativeInput(node: node, page: page)
        case "Toggle":
            Toggle(node.text("label"), isOn: Binding(get: { node.flag }, set: { page.event(node.id, name: "onChange", value: $0) }))
        case "Picker":
            Picker(node.text("label"), selection: Binding(get: { node.text("value") }, set: { page.event(node.id, name: "onChange", value: $0) })) {
                ForEach(node.options, id: \.self) { Text(verbatim: $0).tag($0) }
            }
        default: EmptyView()
        }
    }
}

private struct NativeInput: View {
    let node: NativeNode
    @ObservedObject var page: ProjectPage
    @State private var draft: String
    @State private var sent = 0

    init(node: NativeNode, page: ProjectPage) {
        self.node = node
        self.page = page
        _draft = State(initialValue: node.text("value"))
    }

    var body: some View {
        TextField(node.text("label"), text: Binding(get: { draft }, set: { value in
            draft = value
            sent = page.event(node.id, name: "onChange", value: value)
        }))
        .onChange(of: page.revision) {
            let value = node.text("value")
            if page.acknowledged >= sent && draft != value { draft = value }
        }
    }
}
