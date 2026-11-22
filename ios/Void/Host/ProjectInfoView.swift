import SwiftUI

struct ProjectInfoView: View {
    let id: UUID
    let model: HostModel
    @Environment(\.dismiss) private var dismiss
    @State private var record: ProjectRecord?
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                if let record {
                    LabeledContent("项目名称", value: record.name)
                    LabeledContent("版本", value: record.version)
                    if let source = record.github {
                        LabeledContent("GitHub 仓库", value: source.address)
                            .textSelection(.enabled)
                    }
                } else if let problem {
                    Text(verbatim: problem)
                } else { ProgressView("正在读取项目详情") }
            }
            .navigationTitle("项目详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { dismiss() } }
            .task(id: id) {
                do { record = try await model.details(id) }
                catch { if !Task.isCancelled { problem = error.localizedDescription } }
            }
        }
    }
}

struct GitHubImportView: View {
    let submit: (GitHubRepository) -> Void
    @State private var input = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://github.com/owner/repo", text: $input)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("github.address")
                } header: { Text("公开仓库地址") } footer: {
                    Text("仓库根目录需包含 app/manifest.json 和项目入口文件。")
                }
                let repository = try? GitHubRepository(input)
                Button("克隆并运行") { if let repository { submit(repository) } }
                    .disabled(repository == nil)
                    .accessibilityIdentifier("github.clone")
            }
            .navigationTitle("从 GitHub 导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}
