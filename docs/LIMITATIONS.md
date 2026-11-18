# 验证范围

## v0.1.0-dev.6 本机扫描、旧记录与显式预览

原 iPhone 的用户报告，dev.5 点本机扫描和旧记录都会退出。源码确认，本机发现原先为每个目录建立完整源码快照，仅发现一个项目时还会立即打开它。旧记录同样自动启动预览。缺少该次系统退出报告，尚无法确定手机上的具体终止原因。

本机发现现在只协调读取清单和目录身份。已预览过的最近记录先打开项目页，点「预览项目」才读源码、启动编译器或挂载项目页面。完整性核对分块计算摘要，每次读取至多 256 KiB。单份配置上限为 1 MiB，单次源码快照上限为 96 MiB 和 24,000 个可见条目。超出上限会在项目页显示原因。iOS 提供崩溃或卡顿报告时，诊断页在本机记录异常类别、信号或卡顿时长。[目录读取](../ios/Void/Projects/ProjectSourceReader.swift) · [Apple 系统诊断的交付条件](https://developer.apple.com/documentation/metrickit/mxmetricmanager)

## v0.1.0-dev.5 预览卡住与中断恢复

公开 arm64 IPA 共 6,043,439 字节，SHA-256 为 `a40f49f11772fa2eccada0b664cbe3aafc9e8966caa581ff1ab0d9d014868d8a`。首轮通过 32 项原生测试和 5 项界面测试，包括真正的 Files Open 和预览时结束进程再重开。另一项界面测试在 XCTest 读取系统选择器抓手时超时。[模拟器记录](https://github.com/chkf/void/actions/runs/44381000775/job/135072887562)

dev.4 在模拟器上曾完成目录扫描，随后在等待 TSX 首屏时超时。另可在源码确认，旧版编译时在主界面线程将整份快照编码为 Base64，等待编译器的 WebKit 回调时没有截止时间。原 iPhone 只观察到「准备预览」后卡住或退出，尚无系统崩溃报告可供归因。[dev.4 首屏超时记录](https://github.com/chkf/void/actions/runs/44373037031/job/135044703003)

新版用独立 Worker 运行 TypeScript 和 Wasm 编译器，按文件读取经核验的快照。以真实 Chromium 载入同一份离线编译工具，取消一次任务后立即重新编译，中文及空格命名的相对依赖通过。3 MiB 的原样资源通过文件键返回，编译结果中无需再带这份资源的 Base64 文本。7 项离线工具链测试也已通过。[编译器调度](../runtime/compiler-client.js) · [工具链回归](../tests/compiler.test.mjs)

等待新预览期间，宿主把请求、宿主项目 UUID 和当前阶段写入自己的恢复文件。遇到异常结束会先显示原项目列表。成功或主动取消后只清理本次恢复标记，过期任务不能清理新请求的记录。内存警告和 WebKit 进程终止有独立的诊断行。[恢复逻辑](../ios/Void/Recovery/PreviewRecovery.swift) · [回归测试](../ios/VoidTests/PreviewRecoveryTests.swift)

## v0.1.0-dev.4 原生目录打开

已从公开 Release 下载并校验构建号 4 的 arm64 IPA。文件大小为 5,998,639 字节，SHA-256 为 `2813fed0e3953bc3102999a5fa9781fbdd5a651485709a2078382f6df4e0e238`。包内标识 `app.chkf.void` 与 dev.3 一致，最低 iOS 17.0，使用 Xcode 27.2（27B52）及 iOS 27.2 SDK 构建。原位更新需沿用旧版的实际签名和应用标识。[发布附件](https://github.com/chkf/void/releases/tag/v0.1.0-dev.4) · [源码提交](https://github.com/chkf/void/commit/c3aef51cd5dfd05822a5eea10451ce4f49905832)

标签提交通过 29 项原生单元与运行时测试、6 项离线工具链测试，以及本机文稿扫描导入 TSX、手动重新扫描和 SwiftUI 冷启动界面测试。该轮另有两项界面失败。一次 XCTest 点击系统取消超时，另一次 Files 实际返回 Documents 上级目录，宿主发现 3 个项目，测试预期的单项目断言失败。[标签模拟器与 Xcode 报告](https://github.com/chkf/void/actions/runs/44372208847/job/135041747351) · [工具链与 iPhone 构建](https://github.com/chkf/void/actions/runs/44372208847/job/135041746964)

本版直接检查同一授权目录里的 `app/manifest.json` 和实际入口。模拟器上的真实目录复现了一个 dev.3 缺陷。把带隐藏属性的点号临时文件原子替换为正常文件名后，旧枚举漏掉了清单。新版同时读到了清单、TSX 入口和相对依赖。只读、读取拒绝、缺失、JSON 损坏、符号链接和路径别名分别有回归。提供商漏列条目、未给出文件类型、尚未下载和暂时不可用通过可控输入验证。[目录测试源码](../ios/VoidTests/DirectoryTests.swift)

模拟器验证了原登记 UUID、runtime ID、权限选择、构建文件和原 SQLite 数值在目录重新登记后均可读回。真实文件协调器被另一项协调操作占用时，取消或超时会结束当前请求，延迟回调不能提交过期结果。[目录身份测试](../ios/VoidTests/DirectoryTests.swift) · [取消与协调测试](../ios/VoidTests/FolderRequestTests.swift)

本次没有可访问的已配对 iPhone。原「健身记录」上的 Open 停点、原项目预览和训练保存仍待真机验证。安装后可直接点原最近项目，或在「管理」点「重新扫描并预览」。需要定位时从「目录诊断」查看同一请求的选择、关闭、授权、扫描和结果。[目录诊断说明](FILESYSTEM.md)

在 iPhone 模拟器的系统 Files 中实际按下 Open，从列表导入尚未登记的目录。选择回调只出现一次，136 毫秒后记录到关闭，随后读到 TSX 首屏。「管理」重新选择同一目录时也只回调一次，58 毫秒后记录到关闭，原项目身份核验成功。同一次运行中，另一个取消用例在 XCTest 读取系统界面时超时。[系统 Open、回调与 TSX 首屏实测](https://github.com/chkf/void/actions/runs/44371016095/job/135037483162)

同一套宿主代码在后续模拟器回归中通过列表取消、管理取消以及在选择器显示期间结束进程再启动的测试，两条取消路径均留下各自的请求结果。该轮外部文稿测试实际选到了系统服务商的根目录，宿主关闭选择器并给出“此目录没有可识别的项目”。另一次本机目录已经扫描成功，随后等待 TSX 页面启动超时。[取消、外部授权与中断恢复记录](https://github.com/chkf/void/actions/runs/44373037031/job/135044703003)

在独立模拟器的本地 File Provider 中，后续回归实际选中外部项目目录，使用系统返回的书签完成 TSX 预览，管理入口第二次 Open 更新了原授权。本机扫描、两入口取消和选择器中结束进程后重开也通过。另一项本机 Open 已经返回正确项目并完成扫描，dev.4 在等待首屏时超时。[外部 File Provider 书签、首屏与重授权记录](https://github.com/chkf/void/actions/runs/44377566398/job/135060699982)

## 较早版本

已重新下载并校验 `v0.1.0-dev.3` 的未签名 arm64 IPA。附件为 5,857,892 字节，SHA-256 为 `7dcbf919cea7ede902814f9b3b3f21073242ff3aa20db62b2787d742ab45b3f3`。包内记录为 Xcode 27.2（27B52）、iOS 27.2 SDK、最低 iOS 17.0、构建号 3。归档内包含 SwiftUI 和 TSX 模板、18 组 156 个注册方法、类型定义及离线开发手册。[Release 附件](https://github.com/chkf/void/releases/tag/v0.1.0-dev.3) · [发布构建](https://github.com/chkf/void/actions/runs/44338862849)

`v0.1.0-dev.3` 的同一提交在 iPhone 17、iOS 27.2 模拟器通过 15 项单元与运行时测试及 1 项界面测试。测试从 TSX 写入中文文件，关闭项目后读回原值，并检查文件隔离、权限拒绝、SQLite 事务回滚、Keychain 存取、加密解密和 HTTP 下载。测试在临时模拟器上增删改了联系人、日历事件和提醒，保存并回读照片，还取得了预设的位置。音视频和图像测试使用生成的媒体文件。界面测试覆盖新建后手动预览、重启和滑动移除最近记录。[模拟器测试记录](https://github.com/chkf/void/actions/runs/44335111783/job/134909575787)

`v0.1.0-dev.2` 的默认项目使用 SwiftUI 源码。已从 Release 重新下载 IPA 并校验归档、arm64 可执行文件、SwiftUI 源文件和 TSX 兼容模板。包内记录为 Xcode 27.2（27B52）、iOS 27.2 SDK、最低 iOS 17.0、构建号 2。5,385,735 字节的附件 SHA-256 为 `e795af0f8c574591d23aa707bd1f889d1ca99a74db86761cb0d306ffa9303927`。[SwiftUI 版下载](https://github.com/chkf/void/releases/tag/v0.1.0-dev.2) · [构建和测试](https://github.com/chkf/void/actions/runs/44318674826)

同一提交在 iPhone 17、iOS 27.2 模拟器上通过 7 项单元与运行时测试及 1 项界面测试。界面测试从默认模板创建项目，操作开关并输入名字，结束进程后重新打开原项目，再进入管理面板。运行时测试覆盖 Swift 源码不匹配提示、TSX 控件事件和失败后保留页面。[模拟器测试记录](https://github.com/chkf/void/actions/runs/44318674826/job/134851477091)

较早的 `v0.1.0-dev.1` 由 Xcode 16.4 编译，默认项目用 TSX 编写。已从公开下载地址取得 IPA 并校验 SHA-256、arm64 可执行文件、iOS 17.0 最低版本和归档完整性。[早期版本](https://github.com/chkf/void/releases/tag/v0.1.0-dev.1)

Windows 上可运行 `npm test` 验证真实 TypeScript 类型检查、Wasm 打包、React 控件树及事件、HTML/CSS 构建和共享目录隔离。iPhone Release、iOS 单元测试和界面测试由 [GitHub Actions](https://github.com/chkf/void/actions/workflows/ios.yml) 执行。具体提交的结论和产物以相应运行记录为准。

一个 IPA 含一套编译好的 SwiftUI 项目视图。Swift 源码变更后，需要构建、签名并安装匹配的 IPA。React/TSX 和 HTML 项目在设备上重新构建与替换页面。

Native SDK 1.1.0 已接入项目计划中的十八组能力。TSX 项目可以读写本项目文件、使用私有 SQLite、调用已注册的系统服务。项目清单、按项目保存的选择、系统授权及签名共同决定可用性。[接口与权限](SDK_REFERENCE.md)

模拟器可以检查项目管理、脚本与真实宿主的文件往返、持久化、隔离及部分系统框架。摄像头采集、麦克风实录、蓝牙 GATT、NFC 标签读写、生物识别、人身健康数据与实体家庭配件的实测需要对应硬件、签名及授权。完整热替换、持久诊断日志和后台任务另见原计划。

真机验收需要可签名的 App ID、配置描述文件和已配对的 iPhone。还需分别在本地与 iCloud 或其他 File Provider 实测授权、撤销、重新选择、延迟下载及外部编辑。当前没有真机验收记录。
