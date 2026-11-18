import SwiftUI
import UniformTypeIdentifiers

private enum Panel: String, Identifiable {
    case create, selectParent, importFolder, manage, settings, reconnect
    var id: String { rawValue }
}

struct HostView: View {
    @ObservedObject var model: HostModel
    @Environment(\.scenePhase) private var phase
    @State private var panel: Panel?
    @State private var projectName = ""
    @State private var template = ProjectTemplate.swiftUI

    var body: some View {
        Group {
            if let record = model.current {
                ZStack {
                    switch model.screen {
                    case .workspace(let template):
                        NavigationStack {
                            List {
                                Section {
                                    LabeledContent("项目模板", value: template.title)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("编辑这个入口文件")
                                        Text(verbatim: template.entry).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                                    }
                                    Button { model.refresh(force: true) } label: {
                                        Label(model.busy ? "正在预览" : "预览项目", systemImage: "play.fill")
                                    }.disabled(model.busy).accessibilityIdentifier("project.preview")
                                } header: { Text("开始开发") } footer: {
                                    Text("项目文件夹已准备好。可以先用编辑器写页面，也可以预览自带的示例。")
                                }
                                if let problem = model.problem {
                                    Section("预览提示") { Text(verbatim: problem).textSelection(.enabled) }
                                }
                            }
                            .navigationTitle(record.name)
                        }
                    case .swiftUI(let id): ProjectContentView(projectName: record.name).id(id)
                    case .script(let page): RunningPage(page: page).id(page.id)
                    case nil:
                        if let problem = model.problem {
                            ContentUnavailableView("项目未能打开", systemImage: "folder.badge.questionmark", description: Text(verbatim: problem))
                        } else { ProgressView("正在打开" + record.name) }
                    }
                    if let candidate = model.candidate {
                        ProjectSurface(page: candidate).id(candidate.id).frame(width: 1, height: 1).opacity(0).accessibilityHidden(true)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        if model.busy { ProgressView().accessibilityLabel("正在构建") }
                        if model.problem != nil && model.screen != nil && model.workspaceTemplate == nil {
                            Label(model.mode == .swiftui ? "查看构建说明" : "更新失败", systemImage: "exclamationmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        if model.workspaceTemplate != nil {
                            Button { Task { await model.showLibrary() } } label: { Label("项目列表", systemImage: "list.bullet") }
                                .accessibilityIdentifier("project.library")
                        }
                        Spacer()
                        Button { panel = .manage } label: { Label("管理", systemImage: "slider.horizontal.3") }
                            .accessibilityIdentifier("host.manage")
                    }.padding(.horizontal).padding(.vertical, 8).background(.bar)
                }
            } else {
                NavigationStack {
                    List {
                        Section {
                            Button { projectName = ""; template = .swiftUI; panel = .create } label: { Label("创建项目", systemImage: "plus") }
                                .accessibilityIdentifier("host.create")
                            Button { panel = .importFolder } label: { Label("导入文件夹", systemImage: "folder") }
                        }
                        if !model.records.isEmpty {
                            Section("最近项目") { ForEach(model.records) { record in
                                Button { Task { await model.open(record) } } label: {
                                    VStack(alignment: .leading) {
                                        Text(verbatim: record.name)
                                        if let template = record.pendingTemplate {
                                            Text(template.title + " · 待预览").font(.caption).foregroundStyle(.secondary)
                                        } else if let date = record.opened {
                                            Text(date, style: .relative).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }.accessibilityIdentifier("recent." + record.name)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) { Task { await model.removeRecent(record.id) } } label: {
                                            Label("移除记录", systemImage: "trash")
                                        }.accessibilityIdentifier("recent.remove")
                                    }
                            } }
                        }
                    }
                    .navigationTitle("项目")
                    .toolbar { Button { panel = .settings } label: { Label("设置", systemImage: "gearshape") } }
                }
            }
        }
        .task { await model.load() }
        .task(id: (model.current?.id.uuidString ?? "") + (phase == .active ? "/active" : "/inactive") + (model.workspaceTemplate == nil ? "" : "/workspace")) {
            if phase == .active { await model.monitor() }
        }
        .sheet(item: $panel) { selection in
            switch selection {
            case .create:
                NavigationStack {
                    Form {
                        TextField("项目名称", text: $projectName).accessibilityIdentifier("project.name")
                        Picker("界面", selection: $template) {
                            Text("SwiftUI").tag(ProjectTemplate.swiftUI)
                            Text("React / TSX").tag(ProjectTemplate.tsx)
                        }
                        Section {
                            Button("在此 iPhone 创建") {
                                panel = nil
                                Task { await model.create(cleanName, parent: nil, template: template) }
                            }.accessibilityIdentifier("project.createLocal")
                            Button("选择其他文件夹…") { panel = .selectParent }
                        }.disabled(cleanName.isEmpty)
                    }.navigationTitle("创建项目").toolbar { Button("取消") { panel = nil } }
                }
            case .selectParent, .importFolder, .reconnect:
                FolderPicker { url in
                    panel = nil
                    guard let url else { return }
                    Task {
                        switch selection {
                        case .selectParent: await model.create(cleanName, parent: url, template: template)
                        case .reconnect: await model.reconnect(url)
                        default: await model.importDirectory(url)
                        }
                    }
                }
            case .settings: NavigationStack { SettingsView().toolbar { Button("完成") { panel = nil } } }
            case .manage: ManagementView(model: model, close: { panel = nil }, reconnect: { panel = .reconnect })
            }
        }
        .alert("项目操作失败", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("好") { model.notice = nil }
        } message: { Text(verbatim: model.notice ?? "") }
    }

    private var cleanName: String { projectName.trimmingCharacters(in: .whitespacesAndNewlines) }
}

private struct RunningPage: View {
    @ObservedObject var page: ProjectPage
    var body: some View {
        if page.product.mode == .web { ProjectSurface(page: page) }
        else {
            ZStack {
                ProjectSurface(page: page).frame(width: 1, height: 1).allowsHitTesting(false).accessibilityHidden(true)
                VStack(alignment: .leading) {
                    ForEach(page.nodes) { NativeNodeView(node: $0, page: page) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct ManagementView: View {
    @ObservedObject var model: HostModel
    var close: () -> Void
    var reconnect: () -> Void
    @State private var rename = false
    @State private var name = ""

    var body: some View {
        NavigationStack {
            List {
                Section(model.current?.name ?? "项目") {
                    Button("切换项目") { close(); Task { await model.showLibrary() } }.accessibilityIdentifier("host.switch")
                    Button("重命名") { name = model.current?.name ?? ""; rename = true }
                    NavigationLink("权限声明") {
                        List {
                            if model.permissions.isEmpty { Text("此项目没有声明权限") }
                            ForEach(model.permissions, id: \.self) { Text(verbatim: $0) }
                        }.navigationTitle("权限声明")
                    }
                    NavigationLink("运行日志") {
                        List(Array(model.log.enumerated()), id: \.offset) { Text(verbatim: $0.element) }.navigationTitle("运行日志")
                    }
                }
                Section("恢复") {
                    if let message = model.problem { Text(verbatim: message).textSelection(.enabled) }
                    Button(model.mode == .swiftui ? "重新打开 SwiftUI 页面" : "重新构建并打开") {
                        close(); model.refresh(force: true)
                    }.disabled(model.busy)
                    if model.mode != .swiftui && model.workspaceTemplate == nil {
                        Button("恢复上一可运行版本") { close(); model.refresh(force: true, previous: true) }.disabled(model.busy)
                    }
                    Button("重新授权文件夹", action: reconnect)
                }
                NavigationLink("设置") { SettingsView() }
            }
            .navigationTitle("项目管理").toolbar { Button("完成", action: close) }
            .alert("重命名项目", isPresented: $rename) {
                TextField("名称", text: $name)
                Button("保存") { Task { await model.rename(name) } }
                Button("取消", role: .cancel) {}
            }
        }
    }
}

private struct SettingsView: View {
    var body: some View {
        Form {
            LabeledContent("宿主版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
            LabeledContent("构建号", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
            LabeledContent("原生控件协议", value: "1")
            LabeledContent("SDK 版本", value: "1.0.0")
            Section("已接入能力") { Text("SwiftUI 页面"); Text("本地 Web 页面"); Text("系统信息") }
        }.navigationTitle("设置")
    }
}

private struct FolderPicker: UIViewControllerRepresentable {
    let complete: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(complete) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let complete: (URL?) -> Void
        init(_ complete: @escaping (URL?) -> Void) { self.complete = complete }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { complete(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { complete(nil) }
    }
}
