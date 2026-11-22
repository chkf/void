import SwiftUI

private enum Panel: Hashable, Identifiable {
    case create
    case details(UUID)
    case settings(UUID?)
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
    @Environment(\.openURL) private var openURL
    @AppStorage(HostLanguage.key) private var language = HostLanguage.chinese
    @State private var panel: Panel?
    @State private var sheetPresented = false
    @State private var projectName = ""
    @State private var showOpenMinisDownload = false
    @State private var previewProblemDismissed = false
    private var watchesProjectList: Bool { phase == .active && model.observesProjectList && !folders.active }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            if hostOwnsScreen {
                NavigationStack {
                    library.safeAreaInset(edge: .top, spacing: 0) {
                        if let record = model.current { launchStatus(record) }
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
            switch destination {
            case .management: returnToLibrary()
            case .settings: panel = .settings(id)
            }
        })
        .onChange(of: model.current?.id) { previewProblemDismissed = false }
        .onChange(of: model.busy ? nil : model.problem) { previewProblemDismissed = false }
        .background { FolderPickerPresenter(flow: folders) }
        .onReceive(NotificationCenter.default.publisher(for:DirectoryJournal.changed)) { _ in folders.updateProgress() }
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.didReceiveMemoryWarningNotification)) { _ in model.memoryWarning() }
        .task { await model.load() }
        .task(id: watchesProjectList) {
            if watchesProjectList { await model.observeLocalProjects() }
        }
        .task(id:ObservedFolder(project:model.current?.id,grant:model.current?.grant,
                                active:phase == .active,monitor:model.shouldMonitor)) {
            if phase == .active && model.shouldMonitor { await model.monitor() }
        }
        .sheet(item:$panel,onDismiss:{ sheetPresented = false; folders.sheetClosed() }) { selection in
            panelContent(selection)
                .onAppear { sheetPresented = true }
                .environment(\.locale, Locale(identifier: language.rawValue))
        }
        .alert(model.notice == nil ? Text("目录操作失败") : Text("项目操作失败"), isPresented: Binding(
            get: { alertMessage != nil && !sheetPresented },
            set: { if !$0 { dismissAlert() } }
        ), presenting: alertMessage) { _ in
            Button("好", role: .cancel) {}
        } message: { Text(verbatim: $0) }
        .environment(\.locale, Locale(identifier: language.rawValue))
    }

    @ViewBuilder private func panelContent(_ selection: Panel) -> some View {
        switch selection {
        case .create:
            NavigationStack {
                Form {
                    Section {
                        TextField("项目名称", text: $projectName).accessibilityIdentifier("project.name")
                        Button("在此 iPhone 创建") {
                            let name = cleanName
                            panel = nil
                            Task { await model.create(name, parent: nil) }
                        }.disabled(cleanName.isEmpty).accessibilityIdentifier("project.createLocal")
                        Button("选择其他文件夹…") {
                            begin(.create(cleanName), afterSheet: true)
                        }.disabled(cleanName.isEmpty)
                    } header: { Text("普通创建") }
                    Section {
                        NavigationLink {
                            GitHubImportView { source in
                                panel = nil
                                Task { await model.cloneAndRun(source) }
                            }
                        } label: { Label("从 GitHub 导入", systemImage: "arrow.down.circle") }
                        .accessibilityIdentifier("host.github")
                    }
                }
                .navigationTitle("创建项目")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { panel = nil } } }
            }
        case .settings(let projectID):
            NavigationStack {
                SettingsView(project: model.current.flatMap { $0.id == projectID ? $0 : nil }, returnToLibrary: returnToLibrary)
                    .navigationTitle("设置")
                    .toolbar { Button("完成") { panel = nil } }
            }
        case .details(let id):
            ProjectInfoView(id: id, model: model)
        }
    }

    private func returnToLibrary() {
        guard let id = model.current?.id else { return }
        panel = nil
        Task {
            guard model.current?.id == id else { return }
            await model.showLibrary()
        }
    }

    private var library: some View {
        List {
            if let message = model.recoveryMessage {
                Section("上次操作中断") {
                    Text(verbatim: message).accessibilityIdentifier("preview.interrupted")
                }
            }
            Section {
                Group {
                    Button {
                        projectName = ""
                        panel = .create
                    } label: {
                        Label("创建项目", systemImage: "plus")
                    }.accessibilityIdentifier("host.create")
                    Button { begin(.importFolder) } label: { Label("导入文件夹", systemImage: "folder") }
                        .accessibilityIdentifier("host.import")
                        #if DEBUG && targetEnvironment(simulator)
                        .accessibilityValue(model.simulatorFixtureReady ? "fixture-ready" : "")
                        #endif
                }
                .foregroundStyle(.primary)
                .tint(.primary)
                .disabled(model.current != nil || folders.active || model.gitActivity != nil)
                if let request = processingFolder { folderProgress(request) }
                if let activity = model.gitActivity { ProgressView(HostLanguage.text(activity)) }
            } footer: {
                if folders.phase == .succeeded, let request = folders.request,
                   request.origin == nil, model.current == nil {
                    Text(verbatim: HostLanguage.text(folders.message)).accessibilityIdentifier("folder.status")
                } else {
                    Text("void 文稿中的项目会自动出现在这里。导入外部文件夹时，会将项目复制到 void 文稿。")
                }
            }
            if !model.records.isEmpty {
                Section {
                    ForEach(model.records) { record in
                        Button { model.requestLaunch(record) } label: {
                            Text(verbatim: record.name).foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("project.row." + record.name)
                        .contextMenu {
                            Button { panel = .details(record.id) } label: { Label("详情", systemImage: "info.circle") }
                            if record.github != nil {
                                Button { Task { await model.pullAndRun(record.id) } } label: {
                                    Label("拉取并运行", systemImage: "arrow.down.circle")
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { Task { await model.removeFromList(record.id) } } label: {
                                Label("从列表移除", systemImage: "minus.circle")
                            }.accessibilityIdentifier("project.row.remove")
                        }
                    }
                }.disabled(model.current != nil || model.gitActivity != nil || folders.active)
            }
        }
        .navigationTitle("所有项目")
        .alert(model.projectPrompt?.kind == .created ? Text("项目已创建") : Text("启动项目？"), isPresented: Binding(
            get: { model.projectPrompt != nil && panel == nil && !sheetPresented },
            set: { if !$0 { model.projectPrompt = nil } }
        ), presenting: model.projectPrompt) { prompt in
            switch prompt.kind {
            case .created:
                Button("打开 OpenMinis", action: openOpenMinis)
                Button("完成", role: .cancel) {}
            case .confirmLaunch:
                Button("启动") { Task { await model.open(prompt.record) } }
                    .accessibilityIdentifier("project.launch")
                Button("取消", role: .cancel) {}
            }
        } message: { Text(verbatim: $0.record.name) }
        .alert("无法打开 OpenMinis", isPresented: $showOpenMinisDownload) {
            Button("前往 App Store") { openURL(URL(string: "https://apps.apple.com/app/id6759188481")!) }
            Button("取消", role: .cancel) {}
        } message: { Text("项目已保存在所选文件夹。你可以安装 OpenMinis 后继续编辑。") }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { panel = .settings(nil) } label: { Label("设置", systemImage: "gearshape") }
                    .disabled(model.current != nil || model.gitActivity != nil)
                    .accessibilityIdentifier("host.settings")
            }
        }
    }

    private func openOpenMinis() {
        openURL(URL(string: "minis://")!) { opened in
            if !opened { showOpenMinisDownload = true }
        }
    }

    private func launchStatus(_ record: ProjectRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: record.name).font(.headline)
            if model.busy || (model.problem == nil && model.scanStatus == nil && model.waitingEntry == nil) {
                progressRow(model.scanStatus ?? "正在准备预览", statusID: "preview.stage", cancelID: "scan.cancel", cancel: returnToLibrary)
            } else {
                if let entry = model.waitingEntry {
                    if model.shouldMonitor { Text("请在项目文件夹中创建 \(entry)。保存后会自动打开。").textSelection(.enabled) }
                    else { Text("请在项目文件夹中创建 \(entry)，然后点「重新检查」。").textSelection(.enabled) }
                } else if let problem = model.problem {
                    Text(verbatim: HostLanguage.text(problem)).textSelection(.enabled).accessibilityIdentifier("preview.error")
                }
                HStack {
                    Button("重新检查") { model.refresh(force: true, remember: true) }.accessibilityIdentifier("project.retry")
                    Spacer()
                    Button("返回项目列表", action: returnToLibrary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
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
                    Text(verbatim: HostLanguage.text(problem)).font(.subheadline).lineLimit(2).accessibilityIdentifier("preview.error")
                    Spacer(minLength: 4)
                    Menu {
                        Button("返回项目列表", action: returnToLibrary)
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
            Text(verbatim: HostLanguage.text(message)).font(.subheadline).accessibilityIdentifier(statusID)
            Spacer(minLength: 4)
            Button(action: cancel) { Text("取消").frame(minWidth: 44, minHeight: 44) }
                .fixedSize(horizontal: true, vertical: false).buttonStyle(.borderless)
                .accessibilityIdentifier(cancelID)
        }
    }

    private func begin(_ purpose: FolderPurpose, afterSheet: Bool = false) {
        let request = folders.begin(purpose, origin: model.current?.id, afterSheet: afterSheet)
        if afterSheet && request.purpose == purpose { panel = nil }
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

private struct SettingsView: View {
    let project: ProjectRecord?
    let returnToLibrary: () -> Void
    @AppStorage(HostLanguage.key) private var language = HostLanguage.chinese
    var body: some View {
        Form {
            if let project {
                Section(project.name) {
                    Button(action: returnToLibrary) { ProjectManagementLabel() }
                        .accessibilityIdentifier("host.manage")
                }
            }
            NavigationLink {
                List(HostLanguage.allCases, id: \.self) { choice in
                    Button {
                        language = choice
                    } label: {
                        HStack {
                            Text(verbatim: choice.displayName).foregroundStyle(.primary)
                            Spacer()
                            if choice == language { Image(systemName: "checkmark") }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(choice == language ? .isSelected : [])
                    .accessibilityIdentifier("language." + choice.rawValue)
                }.navigationTitle("语言")
            } label: { LabeledContent("语言", value: language.displayName) }
            .accessibilityIdentifier("settings.language")
            if project == nil {
                LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            }
        }
    }
}

