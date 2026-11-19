import SwiftUI
import UIKit

// One retained hosting controller per application Tab.id. UIKit mounts the
// selected view, manages the bar's safe area and excludes offscreen responders.
struct NativeTabs: UIViewControllerRepresentable {
    let node: NativeNode
    let revision: Int
    let page: ProjectPage
    @Environment(\.nativePalette) private var palette
    @Environment(\.openProjectSettings) private var openSettings

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UITabBarController {
        let controller = UITabBarController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UITabBarController, context: Context) {
        context.coordinator.update(controller, node: node, revision: revision, page: page, palette: palette, openSettings: openSettings)
    }

    fileprivate struct Content: View {
        let tab: NativeNode
        let revision: Int
        let page: ProjectPage
        let palette: NativePalette
        let openSettings: (ProjectSettingsDestination) -> Void

        var body: some View {
            VStack(alignment: .leading) {
                ForEach(tab.children) { NativeNodeView(node: $0, revision: revision, page: page) }
                if page.legacyManagementContainerID == tab.id { ProjectManagementButton() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(palette.color(.background))
            .foregroundStyle(palette.color(.text))
            .tint(palette.color(.accent))
            .environment(\.nativePalette, palette)
            .environment(\.openProjectSettings, openSettings)
            .environment(\.colorScheme, palette.dark ? .dark : .light)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITabBarControllerDelegate {
        private var pages = [String: UIHostingController<Content>]()
        private var order = [String]()
        private weak var page: ProjectPage?
        private var revision = 0
        private var nodeID = ""
        private var selection = ""
        private var pendingSequence = 0
        private var lastPalette: NativePalette?

        fileprivate func update(_ controller: UITabBarController, node: NativeNode, revision: Int, page: ProjectPage,
                                palette: NativePalette, openSettings: @escaping (ProjectSettingsDestination) -> Void) {
            if self.revision == revision && lastPalette == palette { return }
            self.page = page
            nodeID = node.id
            self.revision = revision
            let ids = node.children.map { $0.text("id") }
            let appearanceChanged = lastPalette != palette
            if appearanceChanged {
                controller.overrideUserInterfaceStyle = palette.dark ? .dark : .light
                controller.view.backgroundColor = palette.uiColor(.background)
                controller.tabBar.tintColor = palette.uiColor(.accent)
                controller.tabBar.unselectedItemTintColor = palette.uiColor(.secondaryText)
                let appearance = UITabBarAppearance()
                appearance.configureWithDefaultBackground()
                appearance.backgroundColor = palette.uiColor(.background)
                controller.tabBar.standardAppearance = appearance
                controller.tabBar.scrollEdgeAppearance = appearance
                lastPalette = palette
            }

            for tab in node.children {
                let id = tab.text("id")
                let content = Content(tab: tab, revision: revision, page: page, palette: palette,
                                      openSettings: openSettings)
                if let host = pages[id] {
                    if host.rootView.tab.text("title") != tab.text("title") { host.tabBarItem.title = tab.text("title") }
                    if host.rootView.tab.text("systemName") != tab.text("systemName") { host.tabBarItem.image = NativeSymbol.image(tab.text("systemName")) }
                    host.rootView = content
                } else {
                    let host = UIHostingController(rootView: content)
                    host.tabBarItem = UITabBarItem(title: tab.text("title"), image: NativeSymbol.image(tab.text("systemName")), tag: 0)
                    pages[id] = host
                }
                pages[id]?.viewIfLoaded?.backgroundColor = palette.uiColor(.background)
                pages[id]?.tabBarItem.accessibilityIdentifier = id == "settings" || tab.hasSettingsTitle ? "project.settings" : nil
            }
            if ids != order {
                pages = pages.filter { ids.contains($0.key) }
                controller.setViewControllers(ids.compactMap { pages[$0] }, animated: false)
                controller.customizableViewControllers = []
                order = ids
            }

            if page.acknowledged >= pendingSequence || pages[selection] == nil {
                selection = node.text("selection")
                pendingSequence = 0
            }
            if let target = pages[selection], controller.selectedViewController !== target {
                controller.selectedViewController?.viewIfLoaded?.endEditing(true)
                controller.selectedViewController = target
            }
        }

        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            if tabBarController.selectedViewController !== viewController {
                tabBarController.selectedViewController?.viewIfLoaded?.endEditing(true)
            }
            return true
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            guard let page, let id = pages.first(where: { $0.value === viewController })?.key, id != selection else { return }
            let sequence = page.event(nodeID, name: "onChange", value: id, displayedRevision: revision)
            guard sequence > 0 else {
                if let current = pages[selection] { tabBarController.selectedViewController = current }
                return
            }
            selection = id
            pendingSequence = sequence
        }
    }
}
