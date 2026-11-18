# 验证范围

2026-11-18 的开发预发布已通过 Xcode 16.4 的 iPhone Release 构建。已从公开下载地址重新取得 IPA，核对 SHA-256、arm64 可执行文件、iOS 17.0 最低版本和归档完整性。包内版本为 0.1.0，Bundle ID 为 app.chkf.void，安装前需要签名。[v0.1.0-dev.1 下载及校验值](https://github.com/chkf/void/releases/tag/v0.1.0-dev.1) · [构建任务](https://github.com/chkf/void/actions/runs/44310978579)

Windows 上可运行 `npm test` 验证真实 TypeScript 类型检查、Wasm 打包、React 控件树及事件、HTML/CSS 构建和共享目录隔离。iPhone Release、iOS 单元测试和界面测试由 [GitHub Actions](https://github.com/chkf/void/actions/workflows/ios.yml) 执行。具体提交的结论和产物以相应运行记录为准。

一个 IPA 含一套编译好的 SwiftUI 项目视图。Swift 源码变更后，需要构建、签名并安装匹配的 IPA。React/TSX 和 HTML 项目在设备上重新构建与替换页面。

当前接入的脚本 SDK 方法是 `ios.system.info()`。系统照片、相机、麦克风、定位、蓝牙等能力和对应授权仍在实施清单中。项目私有 SQLite、完整热替换、六类持久日志和后台任务仍待实现。

真机验收需要可签名的 App ID、配置描述文件和已配对的 iPhone。还需分别在本地与 iCloud 或其他 File Provider 实测授权、撤销、重新选择、延迟下载及外部编辑。当前没有真机验收记录。
