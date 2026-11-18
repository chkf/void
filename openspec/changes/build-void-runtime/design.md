# Design

## Context

void 从空目录建立。原始计划以 React 页面和 WKWebView 为主要界面。宿主和默认项目现在直接用 Swift 编写 SwiftUI 页面。React/TSX 项目继续使用原生控件渲染器，HTML 项目继续使用 WebKit。原始范围及十八组 SDK 能力见 [项目计划](../../../docs/PROJECT_PLAN.md)。

## Goals / Non-Goals

IPA 包含编译好的 SwiftUI 项目视图、可供脚本组合的原生控件与系统能力。Swift 源码变更通过新版 IPA 交付，脚本项目可在 Files 中增改页面和业务逻辑后直接更新。宿主负责管理、目录授权和恢复。

## Decisions

### 用户在 iPhone 上看到什么

| 入口 | 呈现与操作 |
| --- | --- |
| 首次打开 | SwiftUI「项目」列表，提供创建、导入及系统文件夹选择器。再次打开直接回到上次可用项目。 |
| 日常运行 | 项目占主要屏幕。宿主在安全区域提供可访问的「管理」按钮，与项目自己的导航和工具栏分开。 |
| 管理 | 原生 sheet 中显示当前项目、项目切换、权限、日志、恢复与重启。低频的通用设置、SDK 版本与可用能力放在设置页。 |
| 项目内部 | 默认用原生列表进入详情，表单使用系统输入、选择器和开关。Canvas/WebGL、HTML 和已有网页应用使用有明确入口的 Web 页面。 |

列表与表单采用系统字型、语义色和标准间距。侧滑返回、取消手势、键盘、动态字体及 VoiceOver 纳入验收。系统导航栈可向业务层同步最终路径。[Apple 导航模型](https://developer.apple.com/documentation/swiftui/understanding-the-navigation-stack) · [SwiftUI 辅助功能](https://developer.apple.com/documentation/swiftui/view-accessibility)

### 默认项目如何运行 SwiftUI

清单的 `uiMode` 为 `swiftui`，入口为 `SwiftUI/ProjectContentView.swift`。Xcode 将模板目录中的 Swift 文件编译进应用，GitHub Actions 将未签名的 arm64 IPA 发布到 Releases。宿主创建项目时复制同一套源码，打开时核对文件名和内容并显示 `ProjectContentView(projectName:)`。直接使用 SwiftUI 的状态绑定和系统导航，无需启动脚本会话。外部编辑的 Swift 源文件需要同步回仓库、重新构建并签名安装；源码与已安装版本不匹配时，宿主显示对应说明。

### 可选的 TypeScript 项目如何驱动 SwiftUI

`@runtime/ui` 提供类型化 React 组件。TSX 模板及旧项目在清单中声明 `uiMode: "native"` 和 TSX 入口。显式 `web` 模式或缺少此字段且有有效 HTML 入口的项目使用 WebKit。原生页面可把某条路由交给 Web Runtime。Web 页面进入和退出原生导航时使用同一项目权限。

原生模式的 JS 逻辑由项目所属的 WebKit 内容会话执行。React 的自定义渲染器只提交可序列化的控件类型、稳定节点 ID、属性、子节点和事件 ID。Swift 侧按注册表校验类型、属性、协议版本与父子关系，在主线程把一次更新完整提交给 SwiftUI。React 和渲染器配套锁定版本。网页入口使用 React DOM 并继续支持 CSS。[React 自定义渲染器接口](https://github.com/react/react/blob/main/packages/react-reconciler/README.md)

原生控件持有输入法组合状态、焦点、滚动位置和交互中的导航。每次提交带会话和修订号，原生事件带节点及事件序号。过期更新不得覆盖正在编辑的文本。系统确认返回后向 TS 交付一次导航变更，用户取消手势时保留当前路径。旧会话、已删除节点和未知控件有可定位的诊断。控件类型改变时显式重建该节点。更新同一列表中其他行时复用稳定身份。

### 模块边界

| 模块 | 职责 |
| --- | --- |
| Runtime Core、Project Manager | 管理项目生命周期、最近项目、目录授权和来源修订号。一次项目会话持有一组可释放的资源。 |
| Web Runtime、原生 UI 渲染器 | 分别负责页面资源与项目 JS 会话、原生控件树。宿主管理窗口独立持有，项目异常后仍可操作。 |
| Bridge、Native SDK、Permission Manager | 同一个 Dispatcher 接收已绑定会话的请求，校验参数与授权后派发到预编译的 Swift 模块，包括原生 UI 提交。 |
| Module Manager、Build Engine | 解析并校验锁定的依赖，在设备上生成完整的不可变构建，保存依赖图和 Source Map。 |
| Debug Engine、Task Manager | 记录各阶段的结果，向原项目交付日志、事件及后台任务完成状态。 |
| Data Manager、Recovery Manager | 隔离项目 SQLite 与文件，管理备份、模式迁移、可运行构建指针和中断恢复。 |

### 工作目录、构建和发布

目录选择器返回的书签存入宿主私有空间。每次协调读取时配对取得及释放访问权，通过文件变化通知、版本扫描和前台轮询兼容本地与 File Provider。目录登记使用宿主管理的项目身份。重复导入其他目录中复制的同一份清单须识别身份冲突，不能取得原项目的私有数据或权限。[Apple 目录访问](https://developer.apple.com/documentation/uikit/providing-access-to-directories)

预置浏览器版 `esbuild-wasm` 和 TypeScript 编译器，在独立构建会话中处理受协调的输入快照。前者负责 TSX、CSS、资源、模块图和 Source Map，后者负责类型诊断。模块解析器只暴露当前快照及校验后的锁定模块。工具链及预置依赖的精确版本与摘要随宿主发布。构建工具和项目代码的执行上下文分开。[esbuild 浏览器 API](https://esbuild.github.io/api/#browser)

脚本项目按源码、工具链、锁文件生成构建标识。候选在独立目录写完并校验后，再核对当前源码修订。在一次原子提交中记录候选指针和上次成功指针。原生 TSX 模式须提交首棵有效控件树，Web 模式须完成入口启动握手，之后才标记可运行。冷启动时若上次候选尚未确认，恢复上个成功版本。首次构建失败则保留诊断，供用户修复或重新导入。

CSS 和声明了热替换边界的模块支持 HMR。逻辑模块按依赖图重载，入口、依赖及配置变化执行完整重载，进程失效时由 Swift 重启会话。构建产物、用户数据与日志不属于源码观察范围，避免更新循环。

### Web 内容、RPC 与权限边界

Web 内容仅从绑定本机回环地址的项目静态资源服务加载。每会话单独分配来源和不可猜测的路径，服务只按当前发布清单响应，校验 Host、路径和媒体范围请求。宿主显式控制 MIME、CSP、导航以及模块与媒体缓存，令 ES Modules、Wasm 和音视频能使用浏览器的正常资源加载路径。页面关闭时释放对应会话，宿主保持 ATS 对外部网络的保护。[Apple 本地网络与 ATS](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)

Dispatcher 从 WebKit 的主框架和宿主持有的会话确定项目身份，验证来源、协议版本、请求 ID、能力及参数。项目原生页面和 Web 页面均使用相同的 `@runtime/sdk`。类型、错误码、所需权限、系统可用性与文档示例由方法注册信息校验。大文件、媒体和数据库结果通过项目范围的文件句柄或分块传输。声明、用户给项目的同意、系统权限、硬件和签名逐层检查。HealthKit 只报告系统公开的授权信息。[Apple 健康数据授权](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)

### 数据、系统任务与恢复

Files 中的 `data/` 可保存用户选择共享的项目数据。项目私有 SQLite、备份及宿主书签分别放在宿主管理的目录中，凭证使用项目隔离的 Keychain。自动回滚首先选取数据模式兼容的构建。迁移在一致性备份后冻结受影响的写入，在事务内完成并记录恢复点。手动还原旧数据时展示受影响版本。外部 Agent 能读取用户授予它的共享目录，其中的文件按共享数据处理。

后台上传下载由系统 URLSession 承担，刷新及处理由 BGTaskScheduler 调度。支持的系统上，用户在前台发起且符合条件的工作可请求 BGContinuedProcessingTask。项目关闭后，原生层按项目存储进度、取消和过期结果，待会话可用时再投递。通知到达与代码执行分别记账。[Apple 后台策略](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app) · [持续处理任务](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask)

## Risks / Trade-offs

| 条件 | 应对与验收证据 |
| --- | --- |
| 原生树跨进程更新可能影响打字、滚动和交互动画 | 按提交批量更新、按节点复用，并在 iPhone 上测试中文输入、侧滑完成与取消、长列表滚动中热更新。 |
| File Provider 可能延迟下载，构建中也可能再次保存 | 对每轮输入做版本核对，在两个不同来源上复现并发编辑，用日志核对最终激活的版本。 |
| 可用性随硬件、系统版本、entitlement 及签名变化 | 能力查询、权限用途说明、签名配置和 SDK 参考同源。可用设备与受限设备分别记录真实结果。 |
| 回环服务、Wasm、媒体 Range 加载和后台调度依赖目标系统 | 在支持范围内的 iPhone 上验证离线资源、系统接管传输和过期回调，记录系统版本及缺失条件。 |

## Migration Plan

新建项目默认选择 SwiftUI。已有原生 TSX 项目保留 `native` 模式、目录和身份，HTML 项目继续从旧清单的入口打开。升级时分别检查项目格式、控件协议、原生 SDK 与数据模式版本，兼容性错误在激活前报告。
