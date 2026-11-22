# 我的项目

默认界面在 app/SwiftUI/ProjectContentView.swift 中。可直接使用 SwiftUI 的视图、属性包装器和系统控件。宿主用 ProjectContentView(projectName:) 创建页面。

在应用自己的设置表单中放置 `ProjectManagementButton()`。例如在「我的 → 设置」中使用 `Section("项目") { ProjectManagementButton() }`，点按后即可回到 void 的项目列表。模板中的「设置」已接好这个入口。

将本目录的 app/SwiftUI/ 同步到 GitHub 仓库的 ios/StarterProject/app/SwiftUI/，然后推送版本标签。GitHub Actions 编译 Swift 源码并生成 IPA。签名并安装对应版本后，打开项目即可看到修改。宿主核对目录中的 Swift 源文件与安装包中的源码，若版本不同，预览时会显示重新构建提示。

外部编辑器需要在 Files 中单独选择同一个目录。应用源码放在 app/，可发布的资源放在 assets/，本地依赖放在 modules/。data/ 留给想与编辑器共享的数据，logs/ 保存宿主诊断。只有获准使用该文件夹的应用才能通过 Files 访问它。
