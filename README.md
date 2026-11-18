# void

用 TypeScript 开发原生 iOS 界面。void 是一个面向个人的 iPhone 应用运行时。用户授权一个 Files 文件夹，Agent 就能在其中编辑项目。设计目标是让已安装的宿主直接构建和加载这些更改。

宿主和新项目的常用界面使用真实 SwiftUI 控件。项目用 React/TSX 组合列表、表单和导航，也可以打开使用 HTML、Canvas 或 WebGL 的 Web 页面。原生能力由已签名宿主通过类型化 SDK 提供。

## 开发与构建

原生工程在 [Void.xcodeproj](ios/Void.xcodeproj)。最低部署版本为 iOS 17。首次打开后可创建项目或导入 Files 目录。模板使用 SwiftUI 表单、输入框和开关，入口源码在 [main.tsx](ios/StarterProject/app/src/main.tsx)。

推送代码后，GitHub Actions 用 Xcode 构建 iPhone Release，运行模拟器测试，并保存未签名的 IPA、模拟器应用和测试报告。也可从工作流页面手动运行。[原生构建工作流](https://github.com/chkf/void/actions/workflows/ios.yml) · [构建与签名说明](docs/BUILD.md)

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
