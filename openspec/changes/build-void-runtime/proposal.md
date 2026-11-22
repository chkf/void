# Proposal

## Why

void 让用户安装一次原生宿主，就能让 Agent 在 iPhone 的 Files 项目目录中持续开发应用。为此，宿主需要在设备上把一次源码修改变成可运行的版本，并让业务代码在用户授权的范围内调用真实的 iOS 能力。

## What Changes

- 建立 SwiftUI 宿主，支持创建、授权、恢复和切换项目。外部编辑器独立获得同一目录的访问权后即可参与开发。
- 所有新建项目使用 React/TSX 编写页面，在设备上编译并通过 SwiftUI 渲染系统控件。已有 SwiftUI 项目运行随 IPA 编译的视图。WKWebView 支持独立 Web 页面、Canvas、WebGL、Wasm 和已有 HTML 项目。
- 随宿主交付离线工具链，通过热更新、诊断和回滚完成从编辑到修复的循环。
- 通过统一、可取消且带版本的 Typed RPC 暴露预编译的原生能力。项目身份、用户同意、系统权限、设备和签名共同决定调用结果。
- 为每个项目提供独立的数据、备份和系统调度的后台工作。交付物包括完整工程、SDK、Agent 指南、构建与签名说明及分环境验证记录。

## Capabilities

### New Capabilities

- `project-workspaces`：SwiftUI 宿主管理界面、Files 目录授权、项目格式、外部编辑与版本识别。
- `native-project-ui` 支持用 React/TSX 编写原生导航、表单和交互，兼容已有 SwiftUI 项目。
- `web-runtime`：Web 项目的页面生命周期、本地资源和内容隔离。
- `project-builds`：设备上的 TSX、CSS、资源编译与打包，锁定依赖、校验完整性及复用缓存。
- `live-updates`：四种更新方式、完整版本发布、状态保留和失败回退。
- `native-bridge`：类型化请求、错误、事件、取消、兼容性和跨项目隔离。
- `project-permissions`：项目声明、用户同意、iOS 授权、硬件和签名条件的检查与记录。
- `native-sdk`：原计划第 6.1 至 6.18 节所列的十八组系统与计算接口。
- `data-recovery`：项目 SQLite、私有文件、备份、迁移、回滚及按类别删除。
- `diagnostics`：Agent 可读的日志、源码定位、性能记录和故障恢复操作。
- `background-tasks`：前台工作、系统调度、后台传输与任务结果交接。

### Modified Capabilities

## Impact

本变更覆盖首个完整版本。验收以同一份工程和同一条端到端路径为准，细分任务用于安排开发顺序。原始计划逐字保存在 [项目计划](../../../docs/PROJECT_PLAN.md) 中。各项 iOS 限制、设计取舍和具体验证条件见 [技术设计](design.md)，实现进度见 [任务清单](tasks.md)。
