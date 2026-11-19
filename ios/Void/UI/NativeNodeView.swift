import SwiftUI

struct NativeNodeView: View {
    let node: NativeNode
    let revision: Int
    let page: ProjectPage
    @Environment(\.nativePalette) private var palette

    private var children: some View {
        ForEach(node.children) { NativeNodeView(node: $0, revision: revision, page: page) }
    }

    private var horizontal: HorizontalAlignment {
        switch node.text("alignment") {
        case "trailing": .trailing
        case "center": .center
        default: .leading
        }
    }
    private var vertical: VerticalAlignment {
        switch node.text("alignment") {
        case "top": .top
        case "bottom": .bottom
        case "firstTextBaseline": .firstTextBaseline
        case "lastTextBaseline": .lastTextBaseline
        default: .center
        }
    }

    private func change(_ value: Any) {
        page.event(node.id, name: "onChange", value: value, displayedRevision: revision)
    }

    private func points(_ key: String) -> CGFloat? { node.number(key).map { CGFloat($0) } }

    @ViewBuilder var body: some View {
        switch node.type {
        case "TabView":
            NativeTabs(node: node, revision: revision, page: page)
                .ignoresSafeArea(.container, edges: .bottom)
        case "Screen":
            VStack(alignment: .leading, spacing: 0) {
                if !node.text("title").isEmpty {
                    Text(verbatim: node.text("title")).font(.title.bold()).accessibilityAddTraits(.isHeader)
                        .padding(.horizontal).padding(.vertical, 6)
                }
                VStack(alignment: .leading) { children }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        case "ScrollView":
            ScrollView(.vertical) {
                VStack(alignment: .leading) { children }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollDismissesKeyboard(.interactively)
        case "Card":
            let shape = RoundedRectangle(cornerRadius: node.number("cornerRadius") ?? 12)
            VStack(alignment: .leading) { children }
                .padding(node.number("padding") ?? 12)
                .background(palette.color(named: node.text("background")) ?? palette.color(.surface), in: shape)
                .overlay {
                    if let border = palette.color(named: node.text("border")) {
                        shape.strokeBorder(border, lineWidth: node.number("borderWidth") ?? 1).allowsHitTesting(false)
                    }
                }
        case "Spacer": Spacer(minLength: points("minLength"))
        case "VStack": VStack(alignment: horizontal, spacing: points("spacing")) { children }
        case "HStack": HStack(alignment: vertical, spacing: points("spacing")) { children }
        case "Form", "List": collection
        case "Section": Section(node.text("title")) { children }
        case "Text": NativeText(node: node)
        case "Image":
            if page.uiVersion == 1 {
                Image(systemName: node.text("systemName")).accessibilityLabel(node.text("label"))
            } else {
                NativeImage(node: node)
            }
        case "Button": NativeButton(node: node, revision: revision, page: page)
        case "TextField": NativeInput(node: node, revision: revision, page: page)
        case "Toggle":
            Toggle(node.text("label"), isOn: Binding(get: { node.flag }, set: { change($0) }))
                .frame(minHeight: page.uiVersion == 2 ? 44 : nil)
        case "Picker":
            Picker(node.text("label"), selection: Binding(get: { node.text("value") }, set: { change($0) })) {
                ForEach(node.options, id: \.self) { Text(verbatim: $0).tag($0) }
            }.frame(minHeight: page.uiVersion == 2 ? 44 : nil)
        case "ProgressView":
            ProgressView(value: node.number("value"), total: node.number("total") ?? 1) {
                if node.props["label"] != nil { Text(verbatim: node.text("label")) }
            }
        default: EmptyView() // Theme and Tab are consumed by their owning containers after validation.
        }
    }

    private var themedRows: Bool {
        node.text("appearance") == "themed" || (node.props["appearance"] == nil && palette.themed)
    }
    @ViewBuilder private var collection: some View {
        if themedRows {
            if node.type == "Form" {
                Form { children.listRowBackground(palette.color(.surface)) }
                    .scrollContentBackground(.hidden).background(palette.color(.background))
            } else {
                List { children.listRowBackground(palette.color(.surface)) }
                    .scrollContentBackground(.hidden).background(palette.color(.background))
            }
        } else if node.type == "Form" { Form { children } }
        else { List { children } }
    }
}

private struct NativeText: View {
    let node: NativeNode
    @Environment(\.nativePalette) private var palette
    private static let fonts: [String: Font] = [
        "largeTitle": .largeTitle, "title": .title, "title2": .title2, "title3": .title3, "headline": .headline,
        "subheadline": .subheadline, "body": .body, "callout": .callout, "footnote": .footnote, "caption": .caption, "caption2": .caption2]
    private static let weights: [String: Font.Weight] = [
        "light": .light, "regular": .regular, "medium": .medium, "semibold": .semibold, "bold": .bold, "heavy": .heavy]

    var body: some View {
        let text = Text(verbatim: node.text("value"))
        let alignment = node.text("alignment")
        let styled = (node.bool("monospacedDigits") ? text.monospacedDigit() : text)
            .font(Self.fonts[node.text("font")]).fontWeight(Self.weights[node.text("weight")])
            .foregroundColor(palette.color(named: node.text("color")))
        if node.props["alignment"] != nil {
            styled.multilineTextAlignment(alignment == "center" ? .center : alignment == "trailing" ? .trailing : .leading)
                .frame(maxWidth: .infinity, alignment: alignment == "center" ? .center : alignment == "trailing" ? .trailing : .leading)
        } else { styled }
    }
}

private struct NativeImage: View {
    let node: NativeNode
    @Environment(\.nativePalette) private var palette
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    var body: some View {
        Image(uiImage: NativeSymbol.image(node.text("systemName"))).renderingMode(.template)
            .font(node.number("size").map { .system(size: $0 * scale) })
            .foregroundColor(palette.color(named: node.text("color")))
            .accessibilityLabel(Text(verbatim: node.text("label")))
    }
}

private struct NativeButton: View {
    let node: NativeNode
    let revision: Int
    let page: ProjectPage
    @Environment(\.nativePalette) private var palette

    private func press() { page.event(node.id, name: "onPress", value: NSNull(), displayedRevision: revision) }

    private var button: some View {
        Button(role: node.text("variant") == "destructive" ? .destructive : nil, action: press) {
            HStack {
                if node.props["icon"] != nil {
                    Image(uiImage: NativeSymbol.image(node.text("icon"))).renderingMode(.template).accessibilityHidden(true)
                }
                Text(verbatim: node.text("label"))
            }
            .frame(minWidth: 44, maxWidth: node.bool("fullWidth") ? .infinity : nil, minHeight: 44)
            .foregroundColor(node.text("variant") == "primary" ? palette.color(.onAccent) : nil)
            .contentShape(Rectangle())
        }.disabled(node.bool("disabled"))
    }
    @ViewBuilder var body: some View {
        if page.uiVersion == 1 { Button(node.text("label"), action: press) }
        else {
            switch node.text("variant") {
            case "primary": button.buttonStyle(.borderedProminent).tint(palette.color(.accent)).foregroundStyle(palette.color(.onAccent))
            case "secondary": button.buttonStyle(.bordered)
            case "plain": button.buttonStyle(.plain)
            case "destructive": button.buttonStyle(.bordered).tint(palette.color(.error))
            default: button
            }
        }
    }
}

private struct NativeInput: View {
    let node: NativeNode
    let revision: Int
    let page: ProjectPage
    @State private var draft: String
    @State private var sent = 0

    init(node: NativeNode, revision: Int, page: ProjectPage) {
        self.node = node
        self.revision = revision
        self.page = page
        _draft = State(initialValue: node.text("value"))
    }

    var body: some View {
        TextField(node.text("label"), text: Binding(get: { draft }, set: { value in
            draft = value
            sent = page.event(node.id, name: "onChange", value: value, displayedRevision: revision)
        }))
        .frame(minHeight: page.uiVersion == 2 ? 44 : nil)
        .onChange(of: revision) {
            let value = node.text("value")
            if page.acknowledged >= sent && draft != value { draft = value }
        }
    }
}
