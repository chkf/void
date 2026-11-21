import SwiftUI

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

struct HostView: View {
    @ObservedObject var model: HostModel
    @ObservedObject var folders: FolderRequests
    init(model: HostModel) { self.model = model; self.folders = model.folders }
    @Environment(\.scenePhase) private var phase
    @State private var panel: Panel?
    @State private var projectName = ""
    @State private var template = ProjectTemplate.swiftUI
    @State private var projectPath: [UUID] = []
    @State private var previewProblemDismissed = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            if hostOwnsScreen {
                NavigationStack(path: Binding(get: { projectPath }, set: navigate)) {
                    library
                        .navigationDestination(for: UUID.self) { id in
                            if let record = model.current, record.id == id {
                                projectDetails(record)
                            }
                        }
                }
            }
            if let record = model.current, case .swiftUI(let id) = model.screen {
                ProjectContentView(projectName: record.name).id(id)
            }
            ForEach(mountedPages, id: \.id) { page in
                let visible = page === (model.presentingPage ?? model.page)
                RunningPage(page: page, visible: visible, topControlsVisible: showsPreviewFeedback)
                    .zIndex(visible ? 1 : -1)
                    .allowsHitTesting(visible)
                    .accessibilityHidden(!visible)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let compiler = model.compiler {
                // WebKit needs a window and a nonempty viewport while it prepares the next page.
                ProjectSurface(compiler: compiler).id(ObjectIdentifier(compiler))
                    .frame(width: 4, height: 4).clipped().allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if showsPreviewFeedback { previewFeedback }
        }
        .background { nativeProjectBackground }
        .environment(\.openProjectSettings, { [id = model.current?.id] destination in
            guard panel == nil, let id, model.current?.id == id else { return }
            panel = destination == .management ? .manage : .settings(id)
        })
        .onChange(of: model.current?.id, initial: true) { _, id in
            projectPath = id.map { [$0] } ?? []
            previewProblemDismissed = false
        }
        .onChange(of: model.busy ? nil : model.problem) { previewProblemDismissed = false }
        .background { FolderPickerPresenter(flow: folders).frame(width: 0, height: 0) }
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
                    }
                    .navigationTitle("创建项目")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { panel = nil } } }
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
        .alert(model.notice == nil ? "目录操作失败" : "项目操作失败", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { dismissAlert() } }
        ), presenting: alertMessage) { _ in
            Button("好", role: .cancel) {}
        } message: { Text(verbatim: $0) }
    }

    private var management: some View {
        ManagementView(model: model, folders: folders, close: { panel = nil }, reconnect: {
            if let id = model.current?.id { begin(.reconnect(id), afterSheet: true) }
        })
    }

    private var library: some View {
        List {
            if let message = model.recoveryMessage {
                Section("上次操作中断") {
                    Text(verbatim: message).accessibilityIdentifier("preview.interrupted")
                    if let request = model.interruptedRequestID {
                        Button("上次预览诊断") { panel = .diagnostics(request) }
                            .accessibilityIdentifier("preview.interruptedDetails")
                    }
                }
            }
            Section {
                Group {
                    Button { projectName = ""; template = .swiftUI; panel = .create } label: {
                        Label("创建项目", systemImage: "plus")
                    }.accessibilityIdentifier("host.create")
                    Button { begin(.importFolder) } label: { Label("导入文件夹", systemImage: "folder") }
                        .accessibilityIdentifier("host.import")
                        #if DEBUG && targetEnvironment(simulator)
                        .accessibilityValue(model.simulatorFixtureReady ? "fixture-ready" : "")
                        #endif
                    Button { begin(.local) } label: { Label("扫描本机项目", systemImage: "iphone") }
                        .accessibilityIdentifier("host.local")
                }
                .disabled(folders.active)
                if let request = processingFolder { folderProgress(request) }
                Button { panel = .diagnostics(nil) } label: {
                    Label("目录诊断", systemImage: "list.bullet.rectangle")
                }
            } footer: {
                if folders.phase == .succeeded, folders.request?.origin == nil, model.current == nil {
                    Text(verbatim: folders.message).accessibilityIdentifier("folder.status")
                }
            }
            if !model.records.isEmpty {
                Section("最近项目") {
                    ForEach(model.records) { record in
                        NavigationLink(value: record.id) {
                            VStack(alignment: .leading) {
                                Text(verbatim: record.name)
                                if let template = record.pendingTemplate {
                                    Text(template.title + " · 待预览").font(.caption).foregroundStyle(.secondary)
                                } else if let date = record.opened {
                                    Text(date, style: .relative).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("recent." + record.name)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { Task { await model.removeRecent(record.id) } } label: {
                                Label("移除记录", systemImage: "trash")
                            }.accessibilityIdentifier("recent.remove")
                        }
                    }
                }
            }
        }
        .navigationTitle("项目")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { panel = .settings(nil) } label: { Label("设置", systemImage: "gearshape") }
                    .accessibilityIdentifier("host.settings")
            }
        }
    }

    private func navigate(_ path: [UUID]) {
        guard hostOwnsScreen, projectPath != path else { return }
        projectPath = path
        Task {
            guard projectPath == path, path.last != model.current?.id else { return }
            if let id = path.last, let record = model.records.first(where: { $0.id == id }) {
                await model.selectRecent(record)
            } else if path.isEmpty {
                await model.showLibrary()
            }
            if projectPath == path { projectPath = model.current.map { [$0.id] } ?? [] }
        }
    }

    private func projectDetails(_ record: ProjectRecord) -> some View {
        List {
            if let template = record.pendingTemplate {
                Section {
                    LabeledContent("项目模板", value: template.title)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("编辑这个入口文件")
                        Text(verbatim: template.entry).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    previewAction(remember: false)
                } header: { Text("开始开发") } footer: {
                    Text("用编辑器打开项目文件夹。保存页面后，点「预览项目」查看效果。")
                }
            } else {
                Section {
                    LabeledContent("版本", value: record.version)
                    previewAction(remember: true)
                }
            }
            if let request = processingFolder { folderProgress(request) }
            if let entry = model.waitingEntry, !model.busy {
                Section("等待第一个页面") {
                    Text("请在项目文件夹中创建 " + entry + (model.shouldMonitor ? "。保存后会自动打开。" : "，然后点「重新检查」。"))
                        .textSelection(.enabled)
                }
            } else if let problem = model.problem, !model.busy {
                Section(model.screen == nil ? "项目未能打开" : "预览提示") {
                    Text(verbatim: problem).textSelection(.enabled).accessibilityIdentifier("preview.error")
                }
            }
        }
        .navigationTitle(record.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ProjectSettingsButton() }
        }
    }

    @ViewBuilder private func previewAction(remember: Bool) -> some View {
        if model.busy {
            previewProgress
        } else {
            Button { model.refresh(force: true, remember: remember) } label: {
                if model.waitingEntry == nil { Label("预览项目", systemImage: "play.fill") }
                else { Label("重新检查", systemImage: "arrow.clockwise") }
            }.accessibilityIdentifier("project.preview")
        }
    }

    private var alertMessage: String? {
        if let notice = model.notice { return notice }
        guard panel == nil, let request = folders.request, request.origin == model.current?.id else { return nil }
        return folders.failureMessage
    }

    private func dismissAlert() {
        if model.notice != nil { model.notice = nil }
        else if folders.failureMessage != nil { folders.clearResult() }
    }

    private var hostOwnsScreen: Bool {
        if case .swiftUI = model.screen { return false }
        return model.page == nil && model.presentingPage == nil
    }

    private var processingFolder: FolderRequest? {
        guard folders.phase == .processing, let request = folders.request, request.origin == model.current?.id else { return nil }
        return request
    }

    private var visiblePreviewProblem: String? {
        model.busy || previewProblemDismissed ? nil : model.problem
    }

    private var showsPreviewFeedback: Bool {
        !hostOwnsScreen && (model.busy || processingFolder != nil || visiblePreviewProblem != nil)
    }

    @ViewBuilder private var nativeProjectBackground: some View {
        if let page = model.presentingPage ?? model.page, page.product.mode == .native {
            NativeProjectBackground(page: page).ignoresSafeArea(.container, edges: .top)
        }
    }

    private var previewFeedback: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let request = processingFolder { folderProgress(request) }
            else if model.busy { previewProgress }
            if let problem = visiblePreviewProblem {
                HStack {
                    Text(verbatim: problem).font(.subheadline).lineLimit(2).accessibilityIdentifier("preview.error")
                    Spacer(minLength: 4)
                    Menu {
                        Button { panel = .manage } label: { ProjectManagementLabel() }
                        Button("收起提示") { previewProblemDismissed = true }
                    } label: {
                        Label("预览选项", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                }
            }
        }
        .padding(.horizontal)
        .background {
            if (model.presentingPage ?? model.page)?.product.mode == .native { nativeProjectBackground }
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

    private var previewProgress: some View {
        progressRow(model.scanStatus ?? "正在准备预览", statusID: "preview.stage", cancelID: "scan.cancel", cancel: model.cancelScan)
    }

    private func folderProgress(_ request: FolderRequest) -> some View {
        progressRow(folders.message, statusID: "folder.status", cancelID: "folder.cancel") { folders.cancel(request.id) }
    }

    private func progressRow(_ message: String, statusID: String, cancelID: String, cancel: @escaping () -> Void) -> some View {
        HStack {
            ProgressView().accessibilityHidden(true)
            Text(verbatim: message).font(.subheadline).accessibilityIdentifier(statusID)
            Spacer(minLength: 4)
            Button(action: cancel) { Text("取消").frame(minWidth: 44, minHeight: 44) }
                .fixedSize(horizontal: true, vertical: false).buttonStyle(.borderless)
                .accessibilityIdentifier(cancelID)
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
    let topControlsVisible: Bool
    init(page: ProjectPage, visible: Bool, topControlsVisible: Bool) {
        self.page = page
        self.sdk = page.sdk
        self.visible = visible
        self.topControlsVisible = topControlsVisible
    }
    @ViewBuilder var body: some View {
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
            // UIKit must own the system top inset for a tab's scroll view to draw through it.
            // A visible host toolbar, camera preview or canvas owns its space first.
            let tabEdges: Edge.Set = topControlsVisible || sdk.preview != nil || sdk.canvasHeight > 0 ? .bottom : .vertical
            NativeProjectTree(nodes: page.nodes, revision: page.revision, page: page, visible: visible, tabEdges: tabEdges) {
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
    @ObservedObject var folders: FolderRequests
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
        Button("重新授权文件夹", action: reconnect)
            .disabled(folders.active).accessibilityIdentifier("host.reconnect")
        if let id = model.current?.id, folders.request?.purpose == .reconnect(id), folders.phase == .succeeded {
            Text(verbatim: folders.message).font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("folder.reconnectResult")
        }
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

