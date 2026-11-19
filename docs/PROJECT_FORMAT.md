# 项目格式

新建项目以随 IPA 分发的 [StarterProject](../ios/StarterProject) 为模板。创建时宿主生成独立的 `runtime.json` 项目标识，并建立 `assets/`、`modules/`、`data/` 和 `logs/`。可从「项目 → 创建项目」完成同样的操作。

`runtime.json` 使用 `formatVersion: 1` 和非空字符串 `id`。复制项目用作独立应用时，需更换 id。重命名在 `app/manifest.json` 修改 name，与数据身份独立。

| app/manifest.json 字段 | 约定 |
| --- | --- |
| name、version | 展示名称与项目版本 |
| uiMode | 新项目默认为 `swiftui`。`native` 用于 React/TSX 控件树。HTML 项目可指定 `web`，也可省略模式。 |
| entry | 相对 `app/` 的路径。三个模板入口分别为 `SwiftUI/ProjectContentView.swift`、`src/main.tsx` 和 `index.html`。 |
| permissions | 项目希望申请的能力名称数组 |
| networkHosts | 允许通过原生网络接口连接的精确域名数组。网络请求另需在 permissions 中声明 network。 |

SwiftUI 项目只需清单和 Swift 源码。每个 IPA 编译一套项目视图，项目副本可分别命名和管理。改变任一视图后，将整个 `app/SwiftUI/` 同步到仓库中模板的对应目录，通过 GitHub Actions 编译并安装新包。启动时会核对目录中所有 Swift 文件，包括新增或删除的文件。

React/TSX 模板在 `app/package.json` 中锁定 React 18.3.1、@runtime/ui 1.0.0 和 @runtime/sdk 1.1.0，随项目提供完整类型和离线接口参考。现有 HTML 项目至少包含 `app/manifest.json` 与一个有效的 HTML 入口。[TSX 模板](../ios/TSXProject) · [SDK 参考](SDK_REFERENCE.md)

使用项目标签栏和主题的 TSX 源码须把 `@runtime/ui` 精确声明为 `1.1.0`。目录格式仍为 1。[组件属性与示例](NATIVE_UI.md)

`app/` 存源码，`assets/` 存资源，`modules/` 存本地模块。私有登记、已运行的产物、共享数据与日志分别按[文件边界](FILESYSTEM.md)处理。
