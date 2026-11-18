# void

void 是一个面向个人的 iPhone 项目宿主。应用本身和默认项目页面都用 SwiftUI 编写。创建后先显示项目工作区，准备好再点「预览项目」；最近记录可左滑移除。[项目管理与使用](docs/RUNTIME.md)

在仓库中修改 `ios/StarterProject/app/SwiftUI/`，再用 GitHub Actions 构建、签名并安装新版 IPA，即可运行修改后的 SwiftUI 页面。在 iPhone 的「文件」中编辑过同一项目的 Swift 源码时，需先将它同步回仓库。每个 IPA 包含一套已编译的项目视图。

创建时也可选择 React / TSX 模板，在手机上加载脚本修改，由 SwiftUI 绘制控件。导入的 HTML 项目使用 WKWebView。Native SDK 1.1.0 为脚本提供 18 组原生能力，包括文件、SQLite、媒体、系统服务和硬件接口。[SDK 方法与权限](docs/SDK_REFERENCE.md) · [项目格式](docs/PROJECT_FORMAT.md)

## 开发与构建

v0.1.0-dev.7 面向 iOS 17 及以上的 iPhone。使用原签名团队和实际 Bundle ID 覆盖安装后，点「最近项目」里的原记录，再点「预览项目」。本机扫描只读取清单，完成后停在列表。预览中断后选择其他工作区，重启会恢复新选择。原生 SDK 版本为 1.1.0。[下载 dev.7 IPA](https://github.com/chkf/void/releases/download/v0.1.0-dev.7/void-unsigned.ipa) · [验证记录](docs/LIMITATIONS.md) · [全部版本](https://github.com/chkf/void/releases)

推送代码后，GitHub Actions 用 Xcode 27.2 构建 iPhone Release，在 iOS 27.2 模拟器上测试。推送 `v` 开头的版本标签会将安装包发布到 Releases。[Xcode 工程](ios/Void.xcodeproj) · [构建记录](https://github.com/chkf/void/actions/workflows/ios.yml) · [构建与签名](docs/BUILD.md)

在 Windows 或 macOS 上运行 `npm ci` 和 `npm test` 可构建离线工具链，检查 TSX、React 事件和 HTML 项目打包。应用运行、系统控件和文件夹授权在 iOS 上验证。

## 项目规格

当前实施的变更为 `build-void-runtime`。原计划中的名称是 OpenRuntime，本项目采用小写 void。

- [首版提案与范围](openspec/changes/build-void-runtime/proposal.md)
- [iPhone 上的界面与技术设计](openspec/changes/build-void-runtime/design.md)
- [SwiftUI 项目页面的验收场景](openspec/changes/build-void-runtime/specs/native-project-ui/spec.md)
- [实施与验证任务](openspec/changes/build-void-runtime/tasks.md)
- [原始项目计划](docs/PROJECT_PLAN.md)

## 在本地使用 OpenSpec

需要 Node.js 22.20.0 或更高版本。在仓库根目录运行以下命令可安装锁定的 OpenSpec 2.1.0、查看提案状态并严格校验所有规格。

```sh
npm ci
npm run openspec -- status --change build-void-runtime
npm run openspec -- validate --all --strict
```

根目录的锁文件固定规格工具和随 IPA 打包的 JavaScript 工具链。实施覆盖和验证条件见[当前限制](docs/LIMITATIONS.md)。
