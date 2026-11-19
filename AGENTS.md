# OpenSpec

在仓库根目录通过 `npm run openspec -- <命令>` 调用项目锁定的 CLI。OpenSpec 工作流里出现的 `openspec …` 同样使用这个入口。例如，查看当前工作区用 `npm run openspec -- context --json`。首次检出后用 `npm ci` 安装依赖。

# 子应用设置

开发子应用时，将「项目管理」接到应用自己的设置列表，例如「我的 → 设置」。SwiftUI 和原生 TSX 使用 `ProjectManagementButton`，HTML 和 React DOM 使用 `void://project/management` 链接。首页和标签栏由子应用自己布局。[接入示例](docs/RUNTIME.md#在子应用自己的设置里接入项目管理)
