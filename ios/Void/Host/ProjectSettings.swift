import SwiftUI

enum ProjectSettingsDestination: Equatable {
    case settings, management
}

private struct OpenProjectSettingsKey: EnvironmentKey {
    static let defaultValue: (ProjectSettingsDestination) -> Void = { _ in }
}

extension EnvironmentValues {
    var openProjectSettings: (ProjectSettingsDestination) -> Void {
        get { self[OpenProjectSettingsKey.self] }
        set { self[OpenProjectSettingsKey.self] = newValue }
    }
}

struct ProjectSettingsButton: View {
    @Environment(\.openProjectSettings) private var openSettings

    var body: some View {
        Button { openSettings(.settings) } label: {
            Label("设置", systemImage: "gearshape")
                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("project.settings")
    }
}

struct ProjectManagementLabel: View {
    var body: some View { Label("项目管理", systemImage: "slider.horizontal.3") }
}

struct ProjectManagementButton: View {
    @Environment(\.openProjectSettings) private var openSettings

    var body: some View {
        Button { openSettings(.management) } label: {
            ProjectManagementLabel().frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("host.manage")
    }
}
