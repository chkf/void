# 项目实施任务：Agent-Native iOS Runtime

## 一、项目目标

开发一个面向个人使用的、以 Agent 为核心开发者的 iOS 本地应用运行平台。

项目暂定名称：**OpenRuntime**

它不是传统意义上的白板 App，也不是简单的 WKWebView 网页容器，而是一个完整的、可扩展的 iOS 应用运行时。

核心理念：

**IPA 只负责提供稳定的 iOS 原生运行环境和系统能力，所有具体应用、界面、业务逻辑和功能都由 Agent 在用户可访问的项目文件夹中开发。**

用户不需要每增加一个功能就重新编译、签名或安装 IPA。

Agent 可以直接修改项目文件，Runtime 自动检测变化、构建、加载和调试。

本项目优先考虑个人使用的功能上限，不以 App Store 上架兼容性作为首要约束，但必须遵守 iOS 系统安全机制、代码签名机制和实际 API 使用限制。

**本任务要求一次性完成整个项目，不采用分阶段交付，不只实现 MVP，不允许以模拟接口、空实现或占位代码代替真实功能。**

可以按照合理的内部开发顺序实施，但必须以完整项目为最终交付目标。

---

# 二、开始实施前的要求

首先检查当前开发环境和已有仓库。

如果存在已有项目：

- 检查现有目录结构、技术栈、入口、依赖、配置和构建方式。
- 保留有价值的已有实现。
- 不要未经检查直接推倒重写。
- 识别已经实现的功能，避免重复开发。

如果是空项目，则建立完整工程。

实施过程中：

1. 自主确定合理的技术细节，不要频繁询问用户已经明确的需求。
2. 不要仅生成设计文档或原型，必须实际编写代码。
3. 不要在某个阶段完成后停止并等待用户确认。
4. 不要将核心功能留给用户手动实现。
5. 不要为了减少工作量而删减已经明确要求的功能。
6. 不允许通过虚假的成功返回、模拟设备数据或空函数声称功能完成。
7. 对无法实现的能力，必须说明具体的 iOS 限制和原因，并提供最接近的真实实现。
8. 遇到系统权限、签名或硬件条件限制时，尽可能完成代码和配置，并明确标注需要真机验证的部分。

---

# 三、整体技术架构

采用原生 iOS + Web Runtime 混合架构。

## 3.1 技术栈

| 模块 | 技术 |
|---|---|
| iOS 外壳 | Swift + SwiftUI |
| 原生系统能力 | Apple Native Frameworks |
| 网页运行环境 | WKWebView |
| 动态开发语言 | TypeScript |
| UI 框架 | React |
| 样式 | CSS |
| 原生通信 | Swift Native Bridge + Typed RPC |
| 本地数据库 | SQLite |
| 配置文件 | JSON |
| 动态计算 | JavaScript / WebAssembly |
| 图形能力 | Canvas / WebGL |
| 构建工具 | 预置 TypeScript 编译及模块打包工具 |
| 日志 | 统一 Runtime Logging |
| 项目存储 | 用户授权的 iOS 文件目录 |

具体依赖版本应选择稳定且相互兼容的版本，并固定版本号。

## 3.2 架构原则

必须将以下部分严格分离：

1. Runtime Core：负责应用生命周期和运行环境。
2. Project Manager：负责项目发现、管理和加载。
3. Web Runtime：执行动态应用代码。
4. Native SDK：提供原生系统能力。
5. Bridge：负责 JavaScript 与 Swift 通信。
6. Permission Manager：统一管理权限。
7. Module Manager：管理项目依赖和模块。
8. Build Engine：负责动态项目构建。
9. Debug Engine：负责日志、异常和调试。
10. Data Manager：管理项目数据和持久化。
11. Task Manager：管理前台和系统允许的后台任务。
12. Recovery Manager：管理快照、回滚和故障恢复。

不得将所有功能堆积在一个 Swift 文件或一个巨大的 JavaScript 文件中。

---

# 四、项目文件夹管理

## 4.1 文件夹授权

使用 UIDocumentPickerViewController 支持用户选择整个项目文件夹。

要求：

- 使用文件夹选择模式。
- 保存 Security-Scoped Bookmark。
- 应用重启后恢复目录访问。
- 正确调用 startAccessingSecurityScopedResource 和 stopAccessingSecurityScopedResource。
- 处理目录授权失效。
- 支持用户重新授权。
- 支持项目目录位于 Files、本地存储及受支持的 File Provider 中。
- 使用 NSFileCoordinator 处理必要的跨进程文件读写协调。
- 不能假设所有文件夹都支持实时文件监听。
- 实现文件变化检测、版本检查和必要的轮询机制。

用户选择文件夹后，Runtime 应能发现并加载其中的项目。

## 4.2 项目结构

建立标准项目结构：

```text
MyWorkspace/
├── runtime.json
├── app/
│   ├── manifest.json
│   ├── package.json
│   ├── index.html
│   └── src/
│       ├── main.tsx
│       ├── App.tsx
│       ├── components/
│       ├── pages/
│       ├── services/
│       ├── hooks/
│       └── styles/
├── assets/
│   ├── images/
│   ├── fonts/
│   └── media/
├── modules/
├── data/
├── logs/
└── README.md
```

项目必须允许用户和 Agent 自由修改 Source 代码。

用户数据必须与源代码分离，避免 Agent 修改业务逻辑时意外覆盖用户数据。

## 4.3 项目管理

实现：

- 创建项目。
- 导入已有项目。
- 删除项目。
- 重命名项目。
- 项目切换。
- 项目配置检查。
- 项目运行状态管理。
- 项目依赖检查。
- 项目版本管理。
- 最近打开项目。
- 项目损坏恢复。

打开 App 默认进入上次使用的项目。

不需要预设记账、笔记等业务功能。

---

# 五、Web Runtime

使用 WKWebView 构建真正的本地动态应用运行环境。

要求：

- 支持 HTML、CSS、JavaScript。
- 支持 TypeScript 编译。
- 支持 React。
- 支持模块化开发。
- 支持 ES Modules。
- 支持 Promise、Async/Await。
- 支持 Canvas、WebGL。
- 支持 WebAssembly。
- 支持本地资源加载。
- 支持图片、字体、音频、视频。
- 支持本地项目路由。
- 支持 CSS 动画和复杂交互。
- 支持适配不同 iPhone 屏幕。
- 支持深色模式。
- 支持安全的网络请求。
- 支持项目内静态资源缓存。

正确处理 WKWebView 的本地文件加载、Origin、安全策略和资源访问权限。

不要通过扩大文件 URL 的读取范围来解决资源加载问题。

建立明确的 Content Security Policy，防止项目访问未授权的本地文件。

## 5.1 预置构建工具链

必须考虑 Agent 如何在手机上开发 TypeScript 项目。

预置必要的编译和打包能力，使项目不依赖完整 Node.js 环境也能构建。

支持：

- TypeScript 编译。
- JSX / TSX。
- 模块解析。
- 依赖打包。
- CSS 处理。
- 静态资源处理。
- Source Map。
- 增量构建。
- 构建缓存。

预置常用的 JavaScript 依赖。

允许导入纯 JavaScript / TypeScript 依赖。

不支持的 Node.js 原生模块必须明确识别，不能假装可以运行。

---

# 六、Native SDK：尽可能完整的 iOS 系统能力

这是整个项目最重要的部分。

要求将尽可能多的可用 iOS 原生能力预先编译进 IPA。

不要采用动态下载 Swift 插件的设计。

所有 Native API 必须通过统一的 TypeScript SDK 提供给项目。

SDK 必须包含：

- TypeScript 类型定义。
- API 文档。
- 参数校验。
- 返回值定义。
- 错误码。
- 权限要求。
- 使用示例。
- API 版本兼容机制。

## 6.1 Filesystem

实现：

- readFile
- writeFile
- appendFile
- deleteFile
- copyFile
- moveFile
- mkdir
- readdir
- stat
- exists
- watch
- 文件选择器
- 文件导入
- 文件导出
- 文件分享
- 文件元数据读取

明确区分：

- 用户授权的项目目录。
- Runtime 私有目录。
- 项目数据目录。
- 缓存目录。

不得让普通项目代码随意访问 Runtime 私有文件。

## 6.2 Photos

基于 Photos Framework 实现：

- 选择照片。
- 选择视频。
- 多选媒体。
- 读取媒体信息。
- 获取缩略图。
- 保存图片。
- 保存视频。
- 媒体权限检查。
- 有限照片访问处理。
- 照片资源读取。

尽可能利用系统原生选择器，避免不必要地申请完整照片库权限。

## 6.3 Camera

基于 AVFoundation 实现：

- 拍照。
- 录像。
- 前后摄像头切换。
- 闪光灯。
- 焦点控制。
- 曝光控制。
- 相机预览。
- 相机权限检查。
- 拍摄结果保存。

相机预览应支持原生视图与 Web Runtime 的混合显示。

## 6.4 Audio

实现：

- 音频录制。
- 音频播放。
- 暂停与恢复。
- 音频会话管理。
- 音频格式信息。
- 音量控制。
- 录音权限。
- 音频文件导入导出。
- 系统音频路由变化监听。

遵守 iOS 音频后台模式的使用条件。

## 6.5 Video

实现：

- 本地视频播放。
- 视频信息读取。
- 视频缩略图。
- 视频导入导出。
- 视频转码。
- 视频截图。
- 播放进度。
- 播放控制。

合理使用 AVPlayer、AVAsset 和 AVFoundation。

## 6.6 Location

基于 CoreLocation 实现：

- 获取当前位置。
- 持续位置监听。
- 定位精度设置。
- 地理编码。
- 逆地理编码。
- 航向信息。
- 定位权限检查。
- 定位事件订阅。

后台定位只能在符合 iOS 后台定位规则时启用。

## 6.7 Calendar

基于 EventKit 实现：

- 查询日历。
- 查询事件。
- 创建事件。
- 修改事件。
- 删除事件。
- 日历列表。
- 日期范围查询。
- 权限状态检查。

兼容 iOS 当前版本的日历访问授权方式。

## 6.8 Reminders

实现：

- 查询提醒事项。
- 创建提醒。
- 修改提醒。
- 删除提醒。
- 完成状态修改。
- 到期时间设置。
- 列表管理。

## 6.9 Contacts

基于 Contacts Framework 实现：

- 联系人查询。
- 联系人搜索。
- 联系人详情。
- 新建联系人。
- 修改联系人。
- 删除联系人。
- 联系人权限管理。

## 6.10 Notifications

实现：

- 本地通知创建。
- 定时通知。
- 重复通知。
- 通知取消。
- 通知权限。
- 通知类别。
- 通知点击事件。
- 通知状态管理。

区分系统通知触发与 App 自身后台执行，不要承诺 App 被终止后仍能执行任意代码。

## 6.11 Bluetooth

基于 CoreBluetooth 实现：

- 蓝牙状态。
- 扫描设备。
- 连接设备。
- 断开设备。
- 服务发现。
- Characteristic 发现。
- 读取数据。
- 写入数据。
- 订阅通知。
- 连接状态事件。
- 错误处理。

完整封装 GATT 通信。

## 6.12 NFC

在系统和设备支持范围内实现 CoreNFC：

- NFC 标签读取。
- NDEF 读取。
- 支持的标签交互。
- 会话状态。
- 错误处理。

不能声称支持系统未开放的任意 NFC 功能。

## 6.13 HealthKit

在具备相应签名和授权条件时实现：

- 健康数据查询。
- 步数。
- 心率。
- 睡眠。
- 活动数据。
- 运动记录。
- 允许的数据写入。
- 数据类型检查。
- 授权状态检查。

遵循 HealthKit 的隐私和权限要求。

## 6.14 HomeKit

在具备对应条件时实现：

- 家庭列表。
- 配件列表。
- 配件状态读取。
- 支持的特征值修改。
- 场景查询。
- 场景执行。
- 配件状态变化监听。

## 6.15 Security

实现：

- Keychain。
- Face ID。
- Touch ID。
- LocalAuthentication。
- 安全随机数。
- 数据加密。
- 哈希计算。
- 安全凭证存储。

敏感信息不能明文写入普通项目文件。

## 6.16 System

实现系统能力封装：

- 剪贴板读取与写入。
- 系统分享面板。
- URL Scheme。
- Universal Links。
- 震动反馈。
- 屏幕亮度。
- 设备信息。
- 电池状态。
- 系统版本。
- 深色模式。
- 屏幕方向（在系统允许范围内）。
- 文档预览。
- 打开系统设置页面（系统允许的入口）。
- 网络状态。

不得使用私有 API。

## 6.17 Network

实现：

- HTTP / HTTPS。
- GET / POST / PUT / PATCH / DELETE。
- WebSocket。
- 文件下载。
- 文件上传。
- 请求超时。
- 请求取消。
- 下载进度。
- 上传进度。
- 网络状态。
- 证书错误处理。

合理处理 ATS、跨域、安全凭证和网络权限。

## 6.18 Graphics & Compute

提供：

- Canvas。
- WebGL。
- WebAssembly。
- 图片处理。
- 二维图形。
- 三维图形。
- 动画。
- 数据可视化。
- SQLite。
- 大文件处理接口。
- 原生媒体处理接口。

对性能敏感的操作可以通过已经编译的原生能力执行。

---

# 七、Native Bridge

统一采用 Typed RPC，不允许每个模块自行设计通信方式。

建议接口：

```typescript
import { ios } from "@runtime/sdk";

const photos = await ios.photos.pick({
  mediaTypes: ["image", "video"],
  multiple: true
});

const location = await ios.location.current();

await ios.calendar.createEvent({
  title: "Meeting",
  startDate: "2026-11-20T10:00:00",
  endDate: "2026-11-20T11:00:00"
});
```

统一定义：

```typescript
type Result<T> =
  | {
      success: true;
      data: T;
    }
  | {
      success: false;
      error: {
        code: string;
        message: string;
      };
    };
```

必须支持：

- 请求 ID。
- 异步 Promise。
- 事件订阅。
- 事件取消。
- 请求超时。
- 操作取消。
- 参数校验。
- 权限检查。
- 资源释放。
- 错误映射。
- 项目身份校验。

原生事件必须正确映射到对应项目，不能出现不同项目之间的事件串流。

所有 API 调用都必须经过统一 Dispatcher。

---

# 八、权限管理

建立统一 Permission Manager。

要求：

1. 项目声明需要的权限。
2. Runtime 检查系统授权状态。
3. 必要时通过系统原生授权界面申请。
4. 用户拒绝后返回明确错误。
5. 支持查询权限状态。
6. 支持永久拒绝状态识别。
7. 支持跳转系统设置。
8. 记录项目的权限使用情况。
9. 区分项目声明权限和实际系统权限。
10. 不允许项目绕过原生权限检查。

项目权限配置示例：

```json
{
  "permissions": [
    "photos.read",
    "camera",
    "location.whenInUse",
    "calendar.write",
    "notifications"
  ]
}
```

注意：配置文件本身不能授予 iOS Entitlement。

必须提前在 IPA 中配置所需的合法 Entitlements、Info.plist 隐私用途描述及相关能力。

对于需要特殊签名权限的能力，应完成能完成的全部配置，并在交付说明中指出哪些需要 Apple 授权、开发者账号配置或额外签名支持。

---

# 九、Module Manager

建立项目级模块管理器。

支持：

- 项目依赖声明。
- 依赖版本锁定。
- 本地依赖。
- 纯 JS / TS 模块导入。
- 模块缓存。
- 模块删除。
- 依赖冲突检测。
- 依赖完整性检查。
- 依赖构建。
- 模块加载错误。

预置常用库：

- React。
- React DOM。
- 状态管理库。
- 日期处理库。
- 图表库。
- Markdown 解析器。
- 图标库。
- 数据处理工具。
- SQLite SDK。
- 常用 UI 工具。

模块依赖不得允许任意代码突破 Runtime 的文件和权限边界。

---

# 十、热更新系统

必须实现真正的动态开发体验。

支持四种更新机制：

1. HMR：CSS 和支持热替换的模块尽可能无刷新更新。
2. Hot Reload：业务逻辑发生变化时重新加载模块。
3. Full Reload：入口、依赖或项目配置变化时重建 Web Runtime。
4. Runtime Restart：运行环境异常时重建执行环境。

具体要求：

- 文件变化监听。
- 增量构建。
- 构建缓存。
- 模块依赖追踪。
- 更新失败恢复。
- 更新前快照。
- 更新成功标记。
- 更新失败自动回滚。
- 尽可能保留用户状态。
- 不允许在构建未完成时加载半成品文件。

对于文件来自 iCloud 或其他 File Provider 的情况，支持文件协调、延迟同步和必要的轮询检测。

---

# 十一、Debug Engine

必须让 Agent 能够自主完成开发、测试和修复。

实现：

## 11.1 日志

```text
logs/
├── console.log
├── javascript-errors.json
├── native-errors.json
├── runtime-events.json
├── build-errors.json
└── performance.json
```

## 11.2 调试 API

提供：

- 获取当前项目状态。
- 获取 Runtime 状态。
- 获取当前页面信息。
- 获取 JavaScript 错误。
- 获取 Native API 错误。
- 获取构建错误。
- 获取最近运行日志。
- 获取性能信息。
- 主动刷新项目。
- 重启 Runtime。
- 恢复上个可运行版本。

## 11.3 调试能力

支持：

- Source Map。
- JavaScript 堆栈。
- 原生错误记录。
- RPC 调用追踪。
- 性能监控。
- 内存使用监控。
- 加载时间监控。

不能只输出“运行失败”，必须提供足够的上下文供 Agent 修复。

---

# 十二、Task Manager 与后台任务

尽可能提供完整的系统允许的后台任务支持。

实现：

- 前台任务。
- 长时间任务。
- 后台下载。
- 后台上传。
- 后台刷新。
- 后台处理。
- 系统通知调度。
- 合法后台音频。
- 合法后台定位。

使用：

- BGTaskScheduler。
- BGContinuedProcessingTask（适用的系统版本）。
- Background URLSession。
- UserNotifications。
- 对应系统后台模式。

严格遵守系统调度规则。

不得假设 WebView 可以永久在后台运行。

后台任务应由原生层负责调度，不能依赖网页进程一直存活。

---

# 十三、数据管理与恢复

建立独立的数据管理系统。

要求：

- 项目数据库。
- 项目私有文件。
- 用户数据与源码隔离。
- 自动备份。
- 项目快照。
- 更新前备份。
- 失败自动回滚。
- 数据库迁移。
- 缓存清理。
- 项目恢复。

每个项目必须有独立的数据空间。

删除项目时，应明确区分源码、用户数据、缓存和备份，避免误删用户数据。

---

# 十四、Runtime UI

Runtime 自身只提供必要的管理界面，不提供任何具体业务功能。

界面至少包含：

1. 项目运行界面。
2. 项目选择界面。
3. 文件夹授权入口。
4. 项目管理。
5. Runtime 设置。
6. SDK 版本信息。
7. 权限管理。
8. 日志查看。
9. 故障恢复。
10. Runtime 重启。

设计原则：

- 尽量采用 iOS 原生设计。
- 简洁、干净。
- 不要堆积无意义的设置。
- 默认进入项目运行界面。
- 管理功能不应影响正常项目使用。
- 不要让 Runtime 的管理 UI 与项目 UI 混在一起。

项目本身完全控制自己的业务界面。

---

# 十五、外部 Agent 协作

项目必须考虑由独立的 iOS Agent App 或其他开发工具直接修改项目文件的场景。

要求：

- 项目目录在 Files 中可访问。
- 外部 Agent 可以独立授权同一目录。
- 双方共享同一份文件，而不是各自维护副本。
- Runtime 能发现外部修改。
- 处理并发读写。
- 处理构建过程中的文件变化。
- 支持文件版本检查。
- 支持重新加载。

不要假设一个 App 的文件授权可以自动传递给另一个 App。

同时，提供清晰的项目 README 和 SDK 文档，使外部 Agent 无需了解 Runtime 内部实现也能开发。

---

# 十六、开发规范与文档

必须生成并维护以下文档：

```text
docs/
├── ARCHITECTURE.md
├── RUNTIME.md
├── PROJECT_FORMAT.md
├── SDK_REFERENCE.md
├── NATIVE_BRIDGE.md
├── PERMISSIONS.md
├── FILESYSTEM.md
├── MODULES.md
├── HOT_RELOAD.md
├── DEBUGGING.md
├── BACKGROUND_TASKS.md
├── SECURITY.md
├── BUILD.md
└── LIMITATIONS.md
```

SDK_REFERENCE.md 必须覆盖所有实际实现的 API。

为 Agent 提供一份专门的开发指南，至少包含：

- 如何创建项目。
- 如何组织文件。
- 如何编写页面。
- 如何调用原生 API。
- 如何申请系统权限。
- 如何处理错误。
- 如何使用数据库。
- 如何读取运行日志。
- 如何触发热更新。
- 如何调试和恢复项目。

尽可能从 Swift API 实现和 TypeScript 类型定义自动生成 SDK 文档，避免文档与代码脱节。

---

# 十七、测试与验证

不能只通过模拟环境判断项目完成。

必须建立：

## 单元测试

- RPC Dispatcher。
- 参数校验。
- 权限状态。
- 项目配置解析。
- 模块加载。
- 构建系统。
- 文件管理。
- 数据管理。
- 更新回滚。

## 集成测试

- 项目创建和加载。
- 外部文件修改检测。
- TypeScript 编译。
- React 页面运行。
- Native Bridge 通信。
- 数据持久化。
- 热更新。
- 错误捕获。
- Runtime 恢复。

## 真机测试

在支持的 iPhone 上验证：

- 文件夹授权。
- App 重启后目录恢复。
- 页面加载。
- 热更新。
- 相机。
- 相册。
- 麦克风。
- 定位。
- 日历。
- 通知。
- 蓝牙。
- Face ID。
- SQLite。
- 后台下载。
- 设备权限拒绝和重新授权。

对没有对应硬件或授权条件的功能，明确记录无法验证的原因。

不得将模拟器通过测试等同于真机通过测试。

---

# 十八、最终验收标准

以下是整个项目的交付要求，不允许只完成其中一部分就宣称项目完成。

### A. Runtime

- 能正常安装和启动。
- 能选择项目文件夹。
- 能恢复授权。
- 能加载本地项目。
- 能运行 React / TypeScript。
- 能正常访问项目资源。

### B. Agent 开发体验

- Agent 可以修改项目文件。
- Runtime 能检测文件变化。
- 自动构建和刷新。
- 支持 HMR。
- 能读取运行错误。
- 能通过错误日志进行修复。
- 无需重新安装 IPA 就能增加普通业务功能。

### C. Native SDK

- 完成尽可能完整的系统能力封装。
- 所有实现的接口都有真实原生实现。
- 类型定义完整。
- 文档完整。
- 权限机制正确。
- 错误处理统一。

### D. 系统稳定性

- 多项目隔离。
- 数据与源码分离。
- 构建失败回滚。
- Runtime 崩溃恢复。
- 日志记录。
- 资源释放。
- 文件访问安全。

### E. 交付

- 完整源代码。
- 完整工程配置。
- SDK 类型定义。
- Agent 开发文档。
- 测试代码。
- 构建脚本。
- 签名配置说明。
- IPA 构建产物（在当前环境具备构建和签名条件时）。

如果当前环境缺少 macOS、Xcode、证书或真机，完成能够完成的全部开发工作，并提供可直接继续构建的工程及明确的阻塞项，不要伪造 IPA。

---

# 十九、实施时必须遵守的原则

1. 不做分阶段交付，最终目标是完整实现。
2. 不要把本项目缩减成简单 WebView。
3. 不要把所有功能都放到网页层。
4. 不要使用模拟原生 API 代替真实实现。
5. 不要把尚未实现的接口放进 SDK 后宣称支持。
6. 不要随意限制 Agent 对项目源码的开发自由。
7. 不要让项目代码获得不必要的 Runtime 私有权限。
8. 不要破坏用户数据。
9. 不要忽略 iOS 后台执行和代码签名的真实限制。
10. 不要以“后续可以扩展”代替当前要求实现的功能。
11. 对无法实现的系统能力，提供具体原因和替代方案。
12. 遇到问题自主研究、排查并修复，不要频繁中断等待确认。

**最终目标：**

交付一个可以长期使用的个人 iOS Agent Runtime。

用户只需要安装一次 IPA。

之后，无论是开发记账工具、笔记系统、媒体播放器、相册管理器、蓝牙控制器、数据 Dashboard，还是其他复杂应用，都可以由 Agent 在项目文件夹中完成开发。

Runtime 负责提供运行环境、系统能力、权限、数据持久化和调试支持。

**让 Agent 开发应用，而不是让用户不断开发 App。**