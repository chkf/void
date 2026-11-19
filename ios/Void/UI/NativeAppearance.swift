import SwiftUI
import UIKit

struct NativePalette: Equatable {
    let dark: Bool
    let themed: Bool
    let overrides: [String: UInt32]

    private func rgb(_ value: UInt32) -> UIColor {
        UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    func uiColor(_ role: NativeColorRole) -> UIColor {
        if let value = overrides[role.rawValue] { return rgb(value) }
        let color: UIColor
        switch role {
        case .text, .accent: color = .label
        case .background, .onAccent: color = .systemBackground
        case .surface: color = .secondarySystemBackground
        case .secondaryText: return rgb(dark ? 0xB8B8BE : 0x55565A)
        case .success: return rgb(dark ? 0x83D59D : 0x21633A)
        case .warning: return rgb(dark ? 0xF0C674 : 0x784900)
        case .error: return rgb(dark ? 0xFFA5A7 : 0xA32324)
        }
        return color.resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
    }
    func color(_ role: NativeColorRole) -> Color { Color(uiColor: uiColor(role)) }
    func color(named name: String) -> Color? { NativeColorRole(rawValue: name).map(color) }
}

private struct NativePaletteKey: EnvironmentKey {
    static let defaultValue = NativePalette(dark: false, themed: false, overrides: [:])
}
extension EnvironmentValues {
    var nativePalette: NativePalette {
        get { self[NativePaletteKey.self] }
        set { self[NativePaletteKey.self] = newValue }
    }
}

struct NativeProjectTree<Header: View>: View {
    let nodes: [NativeNode]
    let revision: Int
    let page: ProjectPage
    let visible: Bool
    @ViewBuilder var header: Header
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let theme = nodes.first.flatMap { $0.type == "Theme" ? $0 : nil }
        let preferred: ColorScheme? = switch theme?.text("mode") {
        case "light": .light
        case "dark": .dark
        default: nil
        }
        let scheme = preferred ?? systemScheme
        let palette = NativePalette(dark: scheme == .dark, themed: theme != nil,
                                    overrides: theme?.palette(scheme == .dark ? "dark" : "light") ?? [:])
        VStack(spacing: 0) {
            header
            if page.uiVersion == 2 {
                content(theme?.children ?? nodes)
                    .foregroundStyle(palette.color(.text))
                    .tint(palette.color(.accent))
                    .environment(\.nativePalette, palette)
                    .environment(\.colorScheme, scheme)
            } else {
                content(nodes)
            }
        }
        .background { palette.color(.background).ignoresSafeArea(.container) }
        .preferredColorScheme(visible ? preferred : nil)
    }

    private func content(_ rows: [NativeNode]) -> some View {
        VStack(alignment: .leading) {
            ForEach(rows) { NativeNodeView(node: $0, revision: revision, page: page) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum NativeSymbol {
    static func image(_ name: String) -> UIImage {
        UIImage(systemName: name) ?? UIImage(systemName: "questionmark.circle") ?? UIImage()
    }
}
