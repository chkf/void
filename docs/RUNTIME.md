# 在 iPhone 上运行

首次启动进入「项目」。点击「创建项目」，输入名称，可选择「在此 iPhone 创建」或系统文件夹。导入时可选择一个项目，也可选择含多个项目的父目录。登记与上次打开的项目保存在宿主私有目录。

创建时默认选择 SwiftUI。页面中的名字输入框绑定到 Swift 的 `@State`，开关可以隐藏或显示问候。要修改页面，编辑 `ios/StarterProject/app/SwiftUI/ProjectContentView.swift` 并通过 GitHub Actions 编译。签名并安装新版 IPA 后，用新版模板创建项目，或将既有项目的 `app/SwiftUI/` 同步到相同版本。如果先在「文件」中编辑了项目源码，宿主会提示将改动同步回仓库。[SwiftUI 入口](../ios/StarterProject/app/SwiftUI/ProjectContentView.swift) · [构建与签名](BUILD.md)

选择 React / TSX 模板时，可在「文件」中编辑 `app/src/main.tsx`。回到宿主后，编译成功的脚本会提交新的 SwiftUI 控件树。Web 项目在 HTML 入口加载确认后成为当前版本。

屏幕底部的「管理」可切换项目、重命名、查看权限声明与本次会话日志、重新打开页面和重新授权。脚本项目已运行过两个不同版本时，可恢复前一可运行版本。用户共享数据保存在原目录。
