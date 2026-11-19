import SwiftUI

struct ProjectContentView: View {
    let projectName: String
    @State private var name = ""
    @State private var showsGreeting = true

    var body: some View {
        NavigationStack {
            Form {
                Section("问候") {
                    TextField("你的名字", text: $name)
                        .textContentType(.givenName)
                    Toggle("显示问候", isOn: $showsGreeting)
                    if showsGreeting {
                        Text(verbatim: name.isEmpty ? "你好" : "你好，" + name)
                    }
                }
                Section {
                    NavigationLink("设置") {
                        Form { ProjectManagementButton() }.navigationTitle("设置")
                    }
                }
            }
            .navigationTitle(projectName)
        }
    }
}
