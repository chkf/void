import SwiftUI
import UniformTypeIdentifiers

private enum Panel: Hashable, Identifiable {
    case create, manage
    case settings(UUID?)
    case diagnostics(UUID?)
    var id: Self { self }
}

private struct ObservedFolder: Equatable {
    let project: UUID?
    let grant: FolderGrant?
    let active: Bool
    let monitor: Bool
}

private struct ProjectTabsKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

struct HostView: View {
    @ObservedObject var model: HostModel
    @ObservedObject var folders: FolderRequests
    init(model: HostModel) { self.model = model; self.folders = model.folders }
    @Environment(\.scenePhase) private var phase
    @State private var panel: Panel?
    @State private var projectName = ""
    @State private var template = ProjectTemplate.swiftUI
    @State private var projectTabs = false

    var body: some View {
        ZStack {
            if let record = model.current {
                ZStack {
                    Color(uiColor:.systemBackground)
                    switch model.screen {
                    case .overview:
                        NavigationStack {
                            List {
                                LabeledContent("版本",value:record.version)
                                Button {
                                    model.refresh(force:true,remember:true)
                                } label: {
                                    Label("预览项目",systemImage:"play.fill")
                                }.disabled(model.busy).accessibilityIdentifier("project.preview")
                                if let problem = model.problem {
                                    Section("预览提示") { Text(verbatim:problem).textSelection(.enabled) }
                                }
                            }.navigationTitle(record.name)
                        }
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
                                    Text("用编辑器打开项目文件夹。保存页面后，点「预览项目」查看效果。")
                                }
                                if let problem = model.problem {
                                    Section("预览提示") { Text(verbatim: problem).textSelection(.enabled) }
                                }
                            }
                            .navigationTitle(record.name)
                        }
                    case .swiftUI(let id): ProjectContentView(projectName: record.name).id(id)
                    case .script: Color.clear
                    case nil:
                        if let entry = model.waitingEntry {
                            NavigationStack {
                                ContentUnavailableView {
                                    Label("等待第一个页面", systemImage:"doc.badge.plus")
                                } description: {
                                    Text("请在项目文件夹中创建 " + entry + "。保存后会自动打开。")
                                } actions: {
                                    Button("重新检查") { model.refresh(force:true) }
                                }.navigationTitle(record.name)
                            }
                        } else if let problem = model.problem {
                            ContentUnavailableView("项目未能打开", systemImage: "folder.badge.questionmark", description: Text(verbatim: problem))
                        } else { ProgressView("正在打开" + record.name) }
                    }
                    ForEach(mountedPages, id:\.id) { page in
                        let visible = page === (model.presentingPage ?? model.page)
                        RunningPage(page:page, visible:visible)
                            .zIndex(visible ? 1 : -1)
                            .allowsHitTesting(visible)
                            .accessibilityHidden(!visible)
                    }
                }
                .overlay(alignment:.bottomTrailing) {
                    if let compiler = model.compiler {
                        // A rebuild starts its worker while the previous page is on screen.
                        // Keep the compiler attached with a visible viewport until it replies.
                        ProjectSurface(compiler:compiler).id(ObjectIdentifier(compiler))
                            .frame(width:4,height:4).clipped().allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .safeAreaInset(edge: projectTabs ? .top : .bottom, spacing: 0) {
                    if hostOwnsScreen || model.busy || model.scanStatus != nil || model.problem != nil || (projectTabs && folders.phase != .idle) {
                        projectControls
                    }
                }
                .background { nativeProjectBackground }
                .environment(\.openProjectSettings, { destination in
                    guard panel == nil, model.current?.id == record.id else { return }
                    panel = destination == .management ? .manage : .settings(record.id)
                })
            } else {
                NavigationStack {
                    List {
                        if let recoveryMessage = model.recoveryMessage {
                            Section("上次操作中断") {
                                Text(verbatim:recoveryMessage).accessibilityIdentifier("preview.interrupted")
                                if let request = model.interruptedRequestID {
                                    Button("上次预览诊断") { panel = .diagnostics(request) }
                                        .accessibilityIdentifier("preview.interruptedDetails")
                                }
                            }
                        }
                        Section {
                            Button { projectName = ""; template = .swiftUI; panel = .create } label: { Label("创建项目", systemImage: "plus") }
                                .accessibilityIdentifier("host.create")
                            Button { begin(.importFolder) } label: { Label("导入文件夹", systemImage:"folder") }
                                .accessibilityIdentifier("host.import")
                                #if DEBUG && targetEnvironment(simulator)
                                .accessibilityValue(model.simulatorFixtureReady ? "fixture-ready" : "")
                                #endif
                            Button { begin(.local) } label: { Label("扫描本机项目",systemImage:"iphone") }
                                .accessibilityIdentifier("host.local")
                            Button { panel = .diagnostics(nil) } label: { Label("目录诊断",systemImage:"list.bullet.rectangle") }
                        }
                        if !model.records.isEmpty {
                            Section("最近项目") { ForEach(model.records) { record in
                                Button { Task { await model.selectRecent(record) } } label: {
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
                    .toolbar {
                        Button { panel = .settings(nil) } label: { Label("设置", systemImage: "gearshape") }
                            .accessibilityIdentifier("host.settings")
                    }
                }
            }
        }
        .onPreferenceChange(ProjectTabsKey.self) { projectTabs = $0 }
        .background { FolderPickerPresenter(flow:folders).frame(width:0,height:0) }
        .safeAreaInset(edge:.bottom, spacing: 0) {
            if folders.phase != .idle && (!projectTabs || model.current == nil) {
                folderFeedback.padding(.horizontal).padding(.vertical,6).background(.bar)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for:DirectoryJournal.changed)) { _ in folders.updateProgress() }
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.didReceiveMemoryWarningNotification)) { _ in model.memoryWarning() }
        .task { await model.load() }
        .task(id:ObservedFolder(project:model.current?.id,grant:model.current?.grant,
                                active:phase == .active,monitor:model.shouldMonitor)) {
            if phase == .active && model.shouldMonitor { await model.monitor() }
        }
        .sheet(item:$panel,onDismiss:{ folders.sheetClosed() }) { selection in
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
                            Button("选择其他文件夹…") { begin(.create(cleanName,template),afterSheet:true) }
                        }.disabled(cleanName.isEmpty)
                    }.navigationTitle("创建项目").toolbar { Button("取消") { panel = nil } }
                }
            case .diagnostics(let request): NavigationStack { DirectoryDiagnosticView(request:request).toolbar { Button("完成") { panel = nil } } }
            case .settings(let projectID):
                NavigationStack {
                    Group {
                        if let record = model.current, record.id == projectID {
                            Form {
                                Section(record.name) {
                                    NavigationLink { management } label: { ProjectManagementLabel() }
                                        .accessibilityIdentifier("host.manage")
                                    LabeledContent("项目版本", value: record.version)
                                }
                            }.navigationTitle("设置")
                        } else { SettingsView().navigationTitle("设置") }
                    }.toolbar { Button("完成") { panel = nil } }
                }
            case .manage: NavigationStack { management }
            }
        }
        .alert("项目操作失败", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("好") { model.notice = nil }
        } message: { Text(verbatim: model.notice ?? "") }
    }

    private var management: some View {
        ManagementView(model: model, close: { panel = nil }, reconnect: {
            if let id = model.current?.id { begin(.reconnect(id), afterSheet: true) }
        })
    }

    private var hostOwnsScreen: Bool {
        if case .swiftUI = model.screen { return false }
        return model.page == nil && model.presentingPage == nil
    }

    @ViewBuilder private var nativeProjectBackground: some View {
        if let page = model.presentingPage ?? model.page, page.product.mode == .native {
            NativeProjectBackground(page: page).ignoresSafeArea(.container, edges: .top)
        }
    }

    private var projectControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let problem = model.problem, model.page != nil || model.mode == .swiftui && model.workspaceTemplate == nil {
                Text(verbatim: problem).font(.caption).lineLimit(projectTabs ? 1 : 3).textSelection(.enabled)
                    .accessibilityIdentifier("preview.error")
            }
            if projectTabs && folders.phase != .idle && (!model.busy || folders.active) {
                folderFeedback
            }
            HStack {
                if model.busy {
                    ProgressView()
                    Text(model.scanStatus ?? "正在准备预览").font(.caption).lineLimit(2).accessibilityIdentifier("preview.stage")
                    Button { model.cancelScan() } label: { Text("取消").frame(minWidth: 44, minHeight: 44) }
                        .fixedSize(horizontal: true, vertical: false).accessibilityIdentifier("scan.cancel")
                } else if let status = model.scanStatus { Text(status).font(.caption) }
                if model.problem != nil && model.screen != nil && model.workspaceTemplate == nil && !model.showingOverview {
                    Label(model.mode == .swiftui ? "查看构建说明" : "更新失败", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                }
                if model.workspaceTemplate != nil || model.showingOverview {
                    Button { Task { await model.showLibrary() } } label: { Label("项目列表", systemImage: "list.bullet") }
                        .accessibilityIdentifier("project.library")
                }
                Spacer(minLength: 0)
                if hostOwnsScreen || model.problem != nil {
                    ProjectSettingsButton()
                }
            }
        }
        .padding(.horizontal).padding(.vertical, projectTabs ? 0 : 4)
        .background {
            if projectTabs { nativeProjectBackground }
            else { Rectangle().fill(.bar) }
        }
    }

    // Keep one SwiftUI identity and one WebKit surface while a candidate is
    // prepared, displayed, and finally recorded as the current page.
    private var mountedPages: [ProjectPage] {
        var pages = [ProjectPage]()
        if let current = model.page { pages.append(current) }
        if let next = model.candidate, next !== model.page { pages.append(next) }
        return pages
    }

    private var folderFeedback: some View {
        HStack {
            if folders.phase == .processing { ProgressView() }
            Text(verbatim: folders.message).font(.footnote).lineLimit(projectTabs ? 2 : nil).accessibilityIdentifier("folder.status")
            Spacer(minLength: 0)
            if let request = folders.request, folders.active {
                Button { folders.cancel(request.id) } label: { Text("取消").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityIdentifier("folder.cancel")
            } else {
                Button { folders.clearResult() } label: { Text("关闭").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityIdentifier("folder.clear")
            }
        }
    }

    private func begin(_ purpose: FolderPurpose, afterSheet: Bool = false) {
        _ = folders.begin(purpose,origin:model.current?.id,afterSheet:afterSheet)
        if afterSheet { panel = nil }
    }
    private var cleanName: String { projectName.trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct RunningPage: View {
    @ObservedObject var page: ProjectPage
    @ObservedObject private var sdk: SDKSession
    @Environment(\.openProjectSettings) private var openSettings
    @State private var webBackground = UIColor.systemBackground
    let visible: Bool
    init(page: ProjectPage, visible: Bool) { self.page = page; self.sdk = page.sdk; self.visible = visible }
    var body: some View {
        content.preference(key: ProjectTabsKey.self, value: visible && page.hasTabNavigation)
    }
    @ViewBuilder private var content: some View {
        if page.product.mode == .web {
            VStack(spacing: 0) {
                NativeMediaPreview(sdk: sdk)
                ProjectSurface(page: page, visible: visible)
            }
            .background { Color(uiColor: webBackground).ignoresSafeArea(.container) }
            .onReceive(page.view.publisher(for: \.underPageBackgroundColor)) { webBackground = $0 ?? .systemBackground }
            .onChange(of: visible, initial: true) {
                page.onOpenManagement = visible ? { [openSettings] in openSettings(.management) } : nil
            }
            .onDisappear { page.onOpenManagement = nil }
        } else {
            NativeProjectTree(nodes: page.nodes, revision: page.revision, page: page, visible: visible) {
                NativeMediaPreview(sdk: sdk)
                // WebKit still needs a window and nonempty bounds to confirm the first frame.
                // Only an explicitly requested canvas occupies space in the project layout.
                ProjectSurface(page: page, visible: visible)
                    .frame(height: max(1, sdk.canvasHeight))
                    .frame(height: sdk.canvasHeight).clipped()
                    .allowsHitTesting(sdk.canvasHeight > 0).accessibilityHidden(sdk.canvasHeight == 0)
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
        List {
            Section(model.current?.name ?? "项目") {
                Button("切换项目") { close(); Task { await model.showLibrary() } }.accessibilityIdentifier("host.switch")
                Button("重命名") { name = model.current?.name ?? ""; rename = true }
                NavigationLink("权限声明") {
                    ProjectPermissionView(model: model)
                }
                NavigationLink("运行日志") {
                    List(Array(model.log.enumerated()), id: \.offset) { Text(verbatim: $0.element) }.navigationTitle("运行日志")
                }
            }
            if model.page?.hasTabNavigation != true {
                Section("恢复") {
                    if let message = model.problem { Text(verbatim: message).textSelection(.enabled) }
                    recoveryControls
                }
            }
            NavigationLink("宿主信息") { SettingsView().navigationTitle("宿主信息") }
        }
        .navigationTitle("项目管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.page?.hasTabNavigation == true {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink("恢复") {
                        List {
                            recoveryControls
                            if let message = model.problem { Section("错误详情") { Text(verbatim: message).textSelection(.enabled) } }
                        }
                        .navigationTitle("预览与恢复")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成", action: close).accessibilityIdentifier("host.recoveryDone") } }
                    }.accessibilityIdentifier("host.recovery")
                }
            }
            ToolbarItem(placement: .topBarTrailing) { Button("完成", action: close) }
        }
        .alert("重命名项目", isPresented: $rename) {
            TextField("名称", text: $name)
            Button("保存") { Task { await model.rename(name) } }
            Button("取消", role: .cancel) {}
        }
    }

    @ViewBuilder private var recoveryControls: some View {
        if model.busy {
            Button("取消当前构建") { model.cancelScan() }.accessibilityIdentifier("host.cancelBuild")
        }
        Button(model.mode == .swiftui ? "重新打开 SwiftUI 页面" : "重新构建并打开") {
            close(); model.refresh(force: true)
        }.disabled(model.busy)
        if model.mode != .swiftui && model.workspaceTemplate == nil {
            Button("恢复上一可运行版本") { close(); model.refresh(force: true, previous: true) }
                .disabled(model.busy).accessibilityIdentifier("host.restore")
        }
        Button("重新扫描并预览") { close(); model.refresh(force: true, remember: true) }
            .accessibilityIdentifier("host.rescan")
        Button("重新授权文件夹", action: reconnect).accessibilityIdentifier("host.reconnect")
        NavigationLink("目录诊断") { DirectoryDiagnosticView() }
    }
}

private struct SettingsView: View {
    var body: some View {
        Form {
            LabeledContent("宿主版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
            LabeledContent("构建号", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
            LabeledContent("原生控件协议", value: "1 / 2（UI 1.1.0）")
            LabeledContent("SDK 版本", value: "1.1.0")
            Section("SDK 能力") {
                ForEach(SDKSession.methods.keys.sorted(), id: \.self) { group in
                    NavigationLink(group) {
                        List((SDKSession.methods[group] ?? [:]).keys.sorted(), id: \.self) { Text(verbatim: $0) }.navigationTitle(group)
                    }
                }
            }
        }
    }
}

