import SwiftUI
import UniformTypeIdentifiers

private enum Panel: String, Identifiable {
    case create, manage, settings, diagnostics
    var id: String { rawValue }
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
    @State private var diagnosticsRequest: UUID?
    @State private var projectName = ""
    @State private var template = ProjectTemplate.swiftUI

    var body: some View {
        ZStack {
            if let record = model.current {
                ZStack {
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
                    if let page = model.presentingPage ?? model.page {
                        RunningPage(page:page).id(page.id).background(Color(uiColor:.systemBackground))
                    }
                }
                .background {
                    // Keep the staging web view attached to the foreground window while its worker
                    // or first native render is running. The native page covers the staging surface.
                    Group {
                        if let compiler = model.compiler { ProjectSurface(compiler:compiler).id(ObjectIdentifier(compiler)) }
                        else if let candidate = model.candidate, candidate !== model.presentingPage, candidate !== model.page {
                            ProjectSurface(page:candidate).id(candidate.id)
                        }
                    }
                    .frame(width:4,height:4).overlay(Color(uiColor:.systemBackground))
                    .clipped().allowsHitTesting(false).accessibilityHidden(true)
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment:.leading,spacing:4) {
                    if let problem = model.problem, model.page != nil || model.mode == .swiftui && model.workspaceTemplate == nil {
                        Text(verbatim:problem).font(.caption).lineLimit(3).textSelection(.enabled)
                            .accessibilityIdentifier("preview.error")
                    }
                    HStack {
                        if model.busy {
                            ProgressView()
                            Text(model.scanStatus ?? "正在准备预览").font(.caption).accessibilityIdentifier("preview.stage")
                            Button("取消") { model.cancelScan() }.accessibilityIdentifier("scan.cancel")
                        } else if let status = model.scanStatus { Text(status).font(.caption) }
                        if model.problem != nil && model.screen != nil && model.workspaceTemplate == nil && !model.showingOverview {
                            Label(model.mode == .swiftui ? "查看构建说明" : "更新失败", systemImage: "exclamationmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        if model.workspaceTemplate != nil || model.showingOverview {
                            Button { Task { await model.showLibrary() } } label: { Label("项目列表", systemImage: "list.bullet") }
                                .accessibilityIdentifier("project.library")
                        }
                        Spacer()
                        Button { panel = .manage } label: { Label("管理", systemImage: "slider.horizontal.3") }
                            .accessibilityIdentifier("host.manage")
                            #if DEBUG && targetEnvironment(simulator)
                            .accessibilityValue(model.simulatorFixtureReady ? "fixture-ready" : "")
                            #endif
                    }
                    }.padding(.horizontal).padding(.vertical, 8).background(.bar)
                }
            } else {
                NavigationStack {
                    List {
                        if let recoveryMessage = model.recoveryMessage {
                            Section("上次操作中断") {
                                Text(verbatim:recoveryMessage).accessibilityIdentifier("preview.interrupted")
                                if let request = model.interruptedRequestID {
                                    Button("上次预览诊断") { diagnosticsRequest = request; panel = .diagnostics }
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
                            Button { diagnosticsRequest = nil; panel = .diagnostics } label: { Label("目录诊断",systemImage:"list.bullet.rectangle") }
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
                    .toolbar { Button { panel = .settings } label: { Label("设置", systemImage: "gearshape") } }
                }
            }
        }
        .background { FolderPickerPresenter(flow:folders).frame(width:0,height:0) }
        .safeAreaInset(edge:.bottom) {
            if folders.phase != .idle {
                HStack {
                    if folders.phase == .processing { ProgressView() }
                    Text(verbatim:folders.message).font(.footnote).accessibilityIdentifier("folder.status")
                    Spacer()
                    if let request = folders.request, folders.active {
                        Button("取消") { folders.cancel(request.id) }.accessibilityIdentifier("folder.cancel")
                    } else {
                        Button("关闭") { folders.clearResult() }.accessibilityIdentifier("folder.clear")
                    }
                }.padding(.horizontal).padding(.vertical,6).background(.bar)
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
            case .diagnostics: NavigationStack { DirectoryDiagnosticView(request:diagnosticsRequest).toolbar { Button("完成") { panel = nil } } }
            case .settings: NavigationStack { SettingsView().toolbar { Button("完成") { panel = nil } } }
            case .manage: ManagementView(model:model,close:{ panel = nil },reconnect:{
                if let id = model.current?.id { begin(.reconnect(id),afterSheet:true) }
            })
            }
        }
        .alert("项目操作失败", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("好") { model.notice = nil }
        } message: { Text(verbatim: model.notice ?? "") }
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
    init(page: ProjectPage) { self.page = page; self.sdk = page.sdk }
    var body: some View {
        VStack(spacing: 0) {
            NativeMediaPreview(sdk: page.sdk)
            content
        }
        .background { PageDisplayProbe(page:page).allowsHitTesting(false).accessibilityHidden(true) }
    }
    @ViewBuilder private var content: some View {
        if page.product.mode == .web { ProjectSurface(page: page) }
        else {
            VStack(spacing: 0) {
                ProjectSurface(page: page).frame(height:max(1,sdk.canvasHeight))
                    .clipped().allowsHitTesting(sdk.canvasHeight > 0).accessibilityHidden(sdk.canvasHeight == 0)
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
                        ProjectPermissionView(model: model)
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
                    Button("重新扫描并预览") { close(); model.refresh(force:true,remember:true) }
                        .accessibilityIdentifier("host.rescan")
                    Button("重新授权文件夹",action:reconnect).accessibilityIdentifier("host.reconnect")
                    NavigationLink("目录诊断") { DirectoryDiagnosticView() }
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
            LabeledContent("SDK 版本", value: "1.1.0")
            Section("SDK 能力") {
                ForEach(SDKSession.methods.keys.sorted(), id: \.self) { group in
                    NavigationLink(group) {
                        List((SDKSession.methods[group] ?? [:]).keys.sorted(), id: \.self) { Text(verbatim: $0) }.navigationTitle(group)
                    }
                }
            }
        }.navigationTitle("设置")
    }
}

