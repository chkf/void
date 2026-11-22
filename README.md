# void

void 是一个面向个人的 iPhone 项目宿主。新建项目使用 React / TSX，由 SwiftUI 绘制原生控件。打开「创建项目」，输入名称并选择保存位置，即可进入工作区。你或 Agent 可以在「文件」中的项目目录编辑 `app/src/main.tsx`，回到 void 点「预览项目」即可在手机上运行。[项目管理与使用](docs/RUNTIME.md)

宿主也能打开已有的 SwiftUI 项目和 HTML 项目。Native SDK 1.1.0 为脚本提供 18 组原生能力，包括文件、SQLite、媒体、系统服务和硬件接口。[SDK 方法与权限](docs/SDK_REFERENCE.md) · [项目格式](docs/PROJECT_FORMAT.md)

## 开发与构建

开发子应用时，将「项目管理」放进应用自己的设置列表，例如「我的 → 设置」。点按后回到「所有项目」，长按项目可查看版本或重命名。公开 GitHub 仓库可以从主页「从 GitHub 导入」克隆并运行，之后长按项目即可「拉取并运行」。[项目导入与设置接入](docs/RUNTIME.md) · [下载已发布的 IPA 和示例](https://github.com/chkf/void/releases)

构建 11 为 TSX 项目提供 `@runtime/ui@1.1.0`。开发者可配置原生标签栏、浅色和深色主题、文本、卡片及滚动布局。独立示例包含两页和可开关的第三页，所有输入仅保存在内存。原依赖 `1.0.0` 继续可用。[构建 11 的 IPA 与示例 ZIP](https://github.com/chkf/void/actions/runs/44515969381/artifacts/14527390642) · [原生 UI 接口与版本规则](docs/NATIVE_UI.md) · [签名与安装](docs/BUILD.md) · [验证记录](docs/LIMITATIONS.md)

构建号 10 修复了预览时首次弹出项目权限提示会导致 Void 闪退的问题。适用于 iOS 17 及以上的 iPhone，原生 SDK 为 1.1.0。沿用已安装版本的签名团队和实际 Bundle ID 覆盖安装，再从「最近项目」进入原项目预览。[下载 dev.10 IPA](https://github.com/chkf/void/releases/download/v0.1.0-dev.10/void-unsigned.ipa) · [验证记录](docs/LIMITATIONS.md) · [全部版本](https://github.com/chkf/void/releases)

推送代码后，GitHub Actions 用 Xcode 27.2 构建 iPhone Release，在 iOS 27.2 模拟器上测试。推送 `v` 开头的版本标签会将安装包发布到 Releases。[Xcode 工程](ios/Void.xcodeproj) · [构建记录](https://github.com/chkf/void/actions/workflows/ios.yml) · [构建与签名](docs/BUILD.md)

在 Windows 或 macOS 上运行 `npm ci` 和 `npm test` 可构建离线工具链，检查 TSX、React 事件和 HTML 项目打包。应用运行、系统控件和文件夹授权在 iOS 上验证。

## 项目规格

当前实施的变更为 `build-void-runtime`。原计划中的名称是 OpenRuntime，本项目采用小写 void。

- [首版提案与范围](openspec/changes/build-void-runtime/proposal.md)
- [iPhone 上的界面与技术设计](openspec/changes/build-void-runtime/design.md)
- [React / TSX 原生页面的验收场景](openspec/changes/build-void-runtime/specs/native-project-ui/spec.md)
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
