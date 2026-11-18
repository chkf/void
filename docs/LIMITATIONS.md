# 验证范围

`v0.1.0-dev.2` 的默认项目使用 SwiftUI 源码。已从 Release 重新下载 IPA 并校验归档、arm64 可执行文件、SwiftUI 源文件和 TSX 兼容模板。包内记录为 Xcode 27.2（27B52）、iOS 27.2 SDK、最低 iOS 17.0、构建号 2。5,385,735 字节的附件 SHA-256 为 `e795af0f8c574591d23aa707bd1f889d1ca99a74db86761cb0d306ffa9303927`。[SwiftUI 版下载](https://github.com/chkf/void/releases/tag/v0.1.0-dev.2) · [构建和测试](https://github.com/chkf/void/actions/runs/44318674826)

同一提交在 iPhone 17、iOS 27.2 模拟器上通过 7 项单元与运行时测试及 1 项界面测试。界面测试从默认模板创建项目，操作开关并输入名字，结束进程后重新打开原项目，再进入管理面板。运行时测试覆盖 Swift 源码不匹配提示、TSX 控件事件和失败后保留页面。[模拟器测试记录](https://github.com/chkf/void/actions/runs/44318674826/job/134851477091)

较早的 `v0.1.0-dev.1` 由 Xcode 16.4 编译，默认项目用 TSX 编写。已从公开下载地址取得 IPA 并校验 SHA-256、arm64 可执行文件、iOS 17.0 最低版本和归档完整性。[早期版本](https://github.com/chkf/void/releases/tag/v0.1.0-dev.1)

Windows 上可运行 `npm test` 验证真实 TypeScript 类型检查、Wasm 打包、React 控件树及事件、HTML/CSS 构建和共享目录隔离。iPhone Release、iOS 单元测试和界面测试由 [GitHub Actions](https://github.com/chkf/void/actions/workflows/ios.yml) 执行。具体提交的结论和产物以相应运行记录为准。

一个 IPA 含一套编译好的 SwiftUI 项目视图。Swift 源码变更后，需要构建、签名并安装匹配的 IPA。React/TSX 和 HTML 项目在设备上重新构建与替换页面。

Native SDK 1.1.0 已接入项目计划中的十八组能力。TSX 项目可以读写本项目文件、使用私有 SQLite、调用已注册的系统服务。项目清单、按项目保存的选择、系统授权及签名共同决定可用性。[接口与权限](SDK_REFERENCE.md)

模拟器可以检查项目管理、脚本与真实宿主的文件往返、持久化、隔离及部分系统框架。摄像头采集、麦克风实录、蓝牙 GATT、NFC 标签读写、生物识别、人身健康数据与实体家庭配件的实测需要对应硬件、签名及授权。完整热替换、持久诊断日志和后台任务另见原计划。

真机验收需要可签名的 App ID、配置描述文件和已配对的 iPhone。还需分别在本地与 iCloud 或其他 File Provider 实测授权、撤销、重新选择、延迟下载及外部编辑。当前没有真机验收记录。
