# Spec Delta

## Purpose

SwiftUI 项目由 GitHub Actions 的 Xcode 编译并发布为 IPA。脚本项目在 iPhone 上构建和报告源码错误，通过锁文件记录依赖并复现离线构建。

## ADDED Requirements

### Requirement: 设备端编译与打包

构建引擎 SHALL 在设备上完成 TypeScript、JSX/TSX、ES 模块、CSS 和静态资源的解析、编译及打包，输出入口、资源清单与 Source Map。工具和模板依赖随 IPA 提供，正常构建无需完整 Node.js 运行环境。

#### Scenario: 首次离线构建模板

- **WHEN** 新安装的宿主在飞行模式下分别构建原生 TSX 模板，以及引用图片和 CSS 的 React Web 项目
- **THEN** 设备生成包含所需依赖的完整版本，对原生入口加载 SwiftUI 组件描述，对 Web 入口打包 DOM、样式和资源，生成的映射可定位到对应 TSX 文件。

### Requirement: 依赖版本及完整性

模块管理器 SHALL 支持预置库、本地模块及导入的纯 JS/TS 包，处理声明、锁定、冲突检查、完整性校验、缓存、移除和构建。预置库涵盖 React、React DOM、原生组件 SDK、状态管理、日期、图表、Markdown、图标、数据处理、SQLite SDK 与 UI 工具。

#### Scenario: 按锁文件离线重建

- **WHEN** 项目已导入所需模块并生成锁文件，用户清理构建缓存后断网重建
- **THEN** 项目从预置库和已导入的模块源解析到相同版本，输出一致的应用内容。

#### Scenario: 依赖无法用于设备

- **WHEN** 包依赖未提供的 Node 内置接口或原生扩展，出现不可满足的版本冲突、加载失败或锁定内容摘要不匹配
- **THEN** 构建失败并指出包名、导入链和原因，保留最后成功发布的版本。

### Requirement: 可失效的增量缓存

构建引擎 SHALL 追踪源文件及其依赖关系，以输入内容、锁文件和工具链版本判断缓存能否复用。

#### Scenario: 切换编译器或修改共享模块

- **WHEN** 用户修改被多个入口引用的模块或升级工具链
- **THEN** 所有受影响的输出重新生成，其内容与同一组输入的全量构建一致。
