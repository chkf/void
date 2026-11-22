# 原生宿主架构

| 源码 | 当前职责 |
| --- | --- |
| ios/Void/Host | SwiftUI 项目列表、启动确认、详情中的重命名和语言设置。子应用的管理入口返回项目列表。宿主持有当前页面与正在启动的候选页面。 |
| ios/Void/Projects | 目录授权、协调读写、项目登记、目录身份校验、修订扫描和变更通知。 |
| ios/TSXProject | 新建项目的 React / TSX 模板，包含页面入口、依赖声明和项目清单。 |
| ios/StarterProject/app/SwiftUI | 既有 SwiftUI 项目的原生视图。Xcode 将它编译进宿主，打开项目时核对 Swift 源码并呈现视图。 |
| ios/Void/Build 与 runtime/compiler.mjs | 独立的 WebKit 构建会话运行 IPA 自带的 TypeScript 和 esbuild-wasm。构建输入取自一次目录快照。 |
| runtime/ui.js 与 ios/Void/UI | React 自定义渲染器提交带稳定标识的控件树。Swift 在提交时校验整棵树，再交给 SwiftUI。 |
| ios/Void/Bridge 与 runtime/bridge.js | 以原生 WebKit 会话、主框架和回环来源确定请求身份，处理控件提交、页面状态及 Native SDK 的请求、响应、取消和事件。 |
| ios/Void/SDK、runtime/sdk-api.json 与 runtime/sdk.d.ts | 按当前项目检查清单与授权，再由实现模块调用系统框架。原生层和 JS 使用同一份方法与权限注册表；静态类型随离线工具链分发。 |
| ios/Void/Web | 每份不可变产物拥有单独的回环端口和随机路径，只响应清单中的资源，支持 GET、HEAD 和媒体字节范围。 |
| ios/Void/Recovery | 按宿主登记的项目 UUID 保存确认运行过的产物，原子写入当前与上一版本指针。 |

十八组系统能力、权限审计、后台工作和完整数据管理的范围与验收路径见 [OpenSpec 实施任务](../openspec/changes/build-void-runtime/tasks.md)。
