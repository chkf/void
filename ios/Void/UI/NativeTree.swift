import Foundation
import SwiftUI

enum NativeValue {
    case text(String), flag(Bool), options([String])
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
    var flag: Bool {
        if case let .flag(value) = props["value"] { return value }
        return false
    }
    var options: [String] {
        if case let .options(value) = props["options"] { return value }
        return []
    }
}

struct NativeCommit {
    let revision: Int
    let eventSequence: Int
    let nodes: [NativeNode]

    static func counter(_ value: Any?, minimum: Int) throws -> Int {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let result = value as? Int, result >= minimum else { throw RuntimeIssue("原生界面修订号无效") }
        return result
    }

    // WebKit already provides Foundation values. Decode them directly without making
    // a JSON copy of the entire screen. Stop before allocating oversized subtrees.
    init(message: [String: Any]) throws {
        revision = try Self.counter(message["revision"],minimum:1)
        eventSequence = try Self.counter(message["eventSequence"],minimum:0)
        let required = ["Text":["value"], "Image":["systemName","label"], "Button":["label"],
                        "TextField":["label","value"], "Toggle":["label","value"], "Picker":["label","value","options"],
                        "Section":["title"], "HStack":[], "VStack":[], "List":[], "Form":[]]
        let containers = ["HStack","VStack","Form","List","Section"]
        var seen = Set<String>(), remainingItems = 16_384, remainingText = 4 * 1024 * 1024
        func consumeItems(_ count: Int) throws {
            guard count <= remainingItems else { throw RuntimeIssue("单帧原生控件和选项超过 16,384 项") }
            remainingItems -= count
        }
        func text(_ value: Any?) throws -> String {
            guard let string = value as? String else { throw RuntimeIssue("原生控件需要文本属性") }
            let bytes = string.utf8.count
            guard bytes <= remainingText else { throw RuntimeIssue("单帧原生界面文本超过 4 MiB") }
            remainingText -= bytes
            return string
        }
        func read(_ value: Any?, depth: Int) throws -> [NativeNode] {
            guard let rows = value as? [Any] else { throw RuntimeIssue("原生控件列表无效") }
            try consumeItems(rows.count)
            return try rows.map { row in
                try Task.checkCancellation()
                guard depth <= 128, let item = row as? [String:Any], let type = item["type"] as? String,
                      let keys = required[type], let props = item["props"] as? [String:Any], keys.count == props.count,
                      let children = item["children"] as? [Any], children.isEmpty || containers.contains(type) else {
                    throw RuntimeIssue("原生控件的类型、层级或属性无效")
                }
                let id = try text(item["id"])
                guard !id.isEmpty, seen.insert(id).inserted else { throw RuntimeIssue("原生控件标识无效或重复") }
                var decoded: [String:NativeValue] = [:]
                for key in keys {
                    switch (type,key) {
                    case ("Toggle","value"):
                        guard let flag = props[key] as? NSNumber, CFGetTypeID(flag) == CFBooleanGetTypeID()
                        else { throw RuntimeIssue("Toggle.value 需要布尔值") }
                        decoded[key] = .flag(flag.boolValue)
                    case ("Picker","options"):
                        guard let values = props[key] as? [Any] else { throw RuntimeIssue("Picker.options 需要文本列表") }
                        try consumeItems(values.count)
                        decoded[key] = .options(try values.map { try text($0) })
                    default: decoded[key] = .text(try text(props[key]))
                    }
                }
                return NativeNode(id:id,type:type,props:decoded,children:try read(children,depth:depth + 1))
            }
        }
        nodes = try read(message["nodes"],depth:0)
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
