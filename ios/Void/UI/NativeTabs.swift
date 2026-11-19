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
        let settingsDestination: ProjectSettingsDestination?
        let openSettings: (ProjectSettingsDestination) -> Void

        var body: some View {
            let collectionID = settingsDestination == .management ? tab.firstCollectionID : nil
            VStack(alignment: .leading) {
                ForEach(tab.children) { NativeNodeView(node: $0, revision: revision, page: page, managementCollectionID: collectionID) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                if settingsDestination == .management && collectionID == nil {
                    ProjectManagementButton().padding(.horizontal)
                } else if settingsDestination == .settings {
                    ProjectSettingsButton().padding(.horizontal)
                }
            }
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
        private var hasSettingsItem = false
        private var openSettings: ((ProjectSettingsDestination) -> Void)?
        private let settingsController: UIViewController = {
            let controller = UIViewController()
            controller.tabBarItem = UITabBarItem(title: "设置", image: UIImage(systemName: "gearshape"), tag: 0)
            controller.tabBarItem.accessibilityIdentifier = "project.settings"
            return controller
        }()

        fileprivate func update(_ controller: UITabBarController, node: NativeNode, revision: Int, page: ProjectPage,
                                palette: NativePalette, openSettings: @escaping (ProjectSettingsDestination) -> Void) {
            self.openSettings = openSettings
            if self.revision == revision && lastPalette == palette { return }
            self.page = page
            nodeID = node.id
            self.revision = revision
            let ids = node.children.map { $0.text("id") }
            let settingsID = node.settingsTabID
            let addSettingsItem = settingsID == nil && ids.count < 5
            let appearanceChanged = lastPalette != palette
            if appearanceChanged {
                controller.overrideUserInterfaceStyle = palette.dark ? .dark : .light
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
                // Projects using all five tabs keep every tab in its original position.
                let destination: ProjectSettingsDestination?
                if let settingsID { destination = id == settingsID ? .management : nil }
                else { destination = addSettingsItem ? nil : .settings }
                let content = Content(tab: tab, revision: revision, page: page, palette: palette,
                                      settingsDestination: destination, openSettings: openSettings)
                if let host = pages[id] {
                    if host.rootView.tab.text("title") != tab.text("title") { host.tabBarItem.title = tab.text("title") }
                    if host.rootView.tab.text("systemName") != tab.text("systemName") { host.tabBarItem.image = NativeSymbol.image(tab.text("systemName")) }
                    host.rootView = content
                } else {
                    let host = UIHostingController(rootView: content)
                    host.tabBarItem = UITabBarItem(title: tab.text("title"), image: NativeSymbol.image(tab.text("systemName")), tag: 0)
                    pages[id] = host
                }
                pages[id]?.tabBarItem.accessibilityIdentifier = id == settingsID ? "project.settings" : nil
            }
            if ids != order || hasSettingsItem != addSettingsItem {
                pages = pages.filter { ids.contains($0.key) }
                var controllers: [UIViewController] = ids.compactMap { pages[$0] }
                if addSettingsItem { controllers.append(settingsController) }
                controller.setViewControllers(controllers, animated: false)
                controller.customizableViewControllers = []
                order = ids
                hasSettingsItem = addSettingsItem
            }

            if page.acknowledged >= pendingSequence || pages[selection] == nil {
                let confirmed = node.text("selection")
                // A controlled tab may decline a tap. Keep project settings reachable in that case.
                if pendingSequence > 0, selection == settingsID, selection != confirmed {
                    Task { @MainActor [weak controller] in
                        if controller?.viewIfLoaded?.window != nil { openSettings(.settings) }
                    }
                }
                selection = confirmed
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
            if viewController === settingsController {
                openSettings?(.settings)
                return false
            }
            return true
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            if viewController === settingsController {
                if let current = pages[selection] { tabBarController.selectedViewController = current }
                openSettings?(.settings)
                return
            }
            guard let page, let id = pages.first(where: { $0.value === viewController })?.key, id != selection else { return }
            let sequence = page.event(nodeID, name: "onChange", value: id, displayedRevision: revision)
            guard sequence > 0 else {
                if let current = pages[selection] { tabBarController.selectedViewController = current }
                if pages[id]?.rootView.settingsDestination == .management { openSettings?(.settings) }
                return
            }
            selection = id
            pendingSequence = sequence
        }
    }
}

private extension NativeNode {
    var settingsTabID: String? {
        let tab = children.first { $0.text("id") == "settings" } ?? children.first {
            ["设置", "settings"].contains($0.text("title").lowercased())
        }
        return tab?.text("id")
    }

    var firstCollectionID: String? {
        if type == "Form" || type == "List" { return id }
        for child in children {
            if let found = child.firstCollectionID { return found }
        }
        return nil
    }
}
