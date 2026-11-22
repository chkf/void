# 项目格式

从「项目 → 创建项目」新建的子应用都使用 React / TSX。宿主复制模板，生成独立的 `runtime.json` 项目标识，并建立 `assets/`、`modules/`、`data/` 和 `logs/`。[项目模板](../ios/TSXProject)

`runtime.json` 使用 `formatVersion: 1` 和非空字符串 `id`。复制项目用作独立应用时，需更换 id。重命名在 `app/manifest.json` 修改 name，与数据身份独立。

| app/manifest.json 字段 | 约定 |
| --- | --- |
| name、version | 展示名称与项目版本 |
| uiMode | 新项目使用 `native` 渲染 React / TSX 控件树。已有 SwiftUI 项目使用 `swiftui`。HTML 项目可指定 `web`，也可省略模式。 |
| entry | 相对 `app/` 的路径。新项目使用 `src/main.tsx`。已有 SwiftUI 项目使用 `SwiftUI/ProjectContentView.swift`，HTML 项目通常使用 `index.html`。 |
| permissions | 项目希望申请的能力名称数组 |
| networkHosts | 允许通过原生网络接口连接的精确域名数组。网络请求另需在 permissions 中声明 network。 |

React / TSX 模板在 `app/package.json` 中锁定 React 18.3.1、@runtime/ui 1.0.0 和 @runtime/sdk 1.1.0，随项目提供完整类型和离线接口参考。[SDK 参考](SDK_REFERENCE.md)

使用项目标签栏和主题的 TSX 源码须把 `@runtime/ui` 精确声明为 `1.1.0`。目录格式仍为 1。[组件属性与示例](NATIVE_UI.md)

已有 SwiftUI 项目通过清单和 `app/SwiftUI/` 中的 Swift 源码匹配 IPA 编译的视图。修改这些源码后，将整个目录同步到仓库并构建、安装新包。已有 HTML 项目至少包含 `app/manifest.json` 与一个有效的 HTML 入口。

子应用应在自己的设置页提供「项目管理」。SwiftUI 和 TSX 使用 `ProjectManagementButton`，Web 设置列表使用 `void://project/management` 链接。[三种项目的接入示例](RUNTIME.md#在子应用自己的设置里接入项目管理)

`app/` 存源码，`assets/` 存资源，`modules/` 存本地模块。私有登记、已运行的产物、共享数据与日志分别按[文件边界](FILESYSTEM.md)处理。
