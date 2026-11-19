# 验证范围

## 构建 11 的 TSX 原生导航与样式

功能分支 `feat/native-ui-1.1` 基于 dev.10 的 `0d1ef30`。构建提交为 `18dc0ae3eef54f80fde1a524594ccba7e3cf70ce`。Xcode 27.2 生成的 arm64 包使用 `app.chkf.void`、构建号 11、最低 iOS 17.0，设备族包含 iPhone 和 iPad。安装包共 6,215,585 字节，SHA-256 为 `938c0ff880be1264e54fffec0dfa5e2a962922fdb5664f60a27bb7e0d9584d1c`。下载同一份 Actions 附件还可取得独立的 `native-ui-example.zip`。原位安装需要沿用原签名团队、实际 Bundle ID 与对应授权配置。[构建附件](https://github.com/chkf/void/actions/runs/44515969381/artifacts/14527390642) · [签名与安装](BUILD.md) · [与 dev.10 的文件差异](https://github.com/chkf/void/compare/0d1ef306f19ee5f16be548d045fa46bc2fe9039b...18dc0ae3eef54f80fde1a524594ccba7e3cf70ce)

| 实现范围 | 代码入口 |
| --- | --- |
| 应用属性与离线构建 | [1.1.0 类型](../runtime/ui.d.ts)、[1.0.0 类型](../runtime/ui-1.0.d.ts)、[React renderer](../runtime/ui.js)、[库注册](../runtime/libraries.js)、[精确版本匹配](../runtime/compiler.mjs)、[IPA 工具链打包](../scripts/prepare-ios.mjs) |
| Swift 原生界面 | [白名单与资源预算](../ios/Void/UI/NativeTree.swift)、[控件和布局](../ios/Void/UI/NativeNodeView.swift)、[主题与语义色](../ios/Void/UI/NativeAppearance.swift)、[系统标签与页面状态](../ios/Void/UI/NativeTabs.swift) |
| 宿主协调与兼容 | [项目 WebKit 和事件修订](../ios/Void/Bridge/ProjectPage.swift)、[管理、取消与恢复](../ios/Void/Host/HostView.swift)、[dev.10 已确认产物复用](../ios/Void/Recovery/BuildHistory.swift) |

共享模拟器的多项目回归会等待扫描完成，将目标记录滚入可见区域，必要时关闭遮住末行的结果栏，再实际点击预览。已比较 `90e10d7`、`07361da` 和交付提交的设备 IPA，解包后的 44 项逐字节相同，宿主可执行文件的 SHA-256 均为 `762f661313f2b0b663b5791ea29becab54e4727cb76d9528577910e16cc713a6`。[界面测试改动](https://github.com/chkf/void/compare/90e10d76109ead16c88ac8ee389ded9907fa2dae...18dc0ae3eef54f80fde1a524594ccba7e3cf70ce)

`npm test` 的 14 项测试及 `npm run openspec -- validate --all --strict` 通过。已从正式 dev.10 包取出离线库和类型，与构建 11 对照。旧版 11 个组件和新版 19 个组件的 JS 导出均与各自的 TypeScript 声明吻合。两包的 SDK 方法表、SDK 类型和系统权限用途声明逐项一致。独立 ZIP 的项目文件与新 IPA 内的离线示例逐字节相同。[工具链与设备构建日志](https://github.com/chkf/void/actions/runs/44515969381/job/135531931297) · [属性白名单、默认值和示例](NATIVE_UI.md)

`bash scripts/ios-build.sh release-preview` 在 `18dc0ae` 上通过 15 项原生回归和 1 项真实权限弹窗界面回归。测试项目原先没有权限记录，首次预览时在两个真实弹窗中允许数据库、拒绝文件读取，写入测试记录后冷启动读回，仍保留两项权限选择，全程 89.259 秒。手动重建、坏清单恢复和冷启动组合用例用时 25.513 秒。另有用例核对旧版构建记录字节以及已有 SQLite 的原生首屏。[Release 原目录、首次弹窗与恢复回归](https://github.com/chkf/void/actions/runs/44515969381/job/135531930462)

在 iOS / iPadOS 27.2 上分别运行 `VOID_LAYOUT_PROFILE=compact bash scripts/ios-build.sh native-layout` 和 `VOID_LAYOUT_PROFILE=ipad bash scripts/ios-build.sh native-layout`。对交付提交 `18dc0ae`，iPhone 17e 和 iPad mini 各通过 5 项原生测试、1 项完整界面测试。原生控制器连续发出 21 次选中事件，实际经 WebKit 和 React 往返，最终选中值、页面控制器身份和 WebKit 身份均通过断言。界面用例验证两页和三页切换、禁用按钮、保留输入与滚动位置、长列表、软键盘、横屏恢复、最大辅助功能字号。浅色与深色页面的 XCTest 对比度和元素描述审计均通过，默认语义色另有 4.5:1 数值断言。[iPhone 测试](https://github.com/chkf/void/actions/runs/44515969381/job/135531930908) · [iPad 测试](https://github.com/chkf/void/actions/runs/44515969381/job/135531930818)

每种设备留存 7 张全屏原图，包含浅色、深色、三标签长列表、键盘、最大辅助功能字号，以及横屏的项目与宿主恢复面板。实际 VoiceOver 朗读与手势、iOS 17 设备、已签名的真机覆盖安装仍待验证。[iPhone 截图与 xcresult](https://github.com/chkf/void/actions/runs/44515969381/artifacts/14527916169) · [iPad 截图与 xcresult](https://github.com/chkf/void/actions/runs/44515969381/artifacts/14527452148) · [真机验收步骤](BUILD.md)

常规 iPhone 17 Debug 套件依次运行 `bash scripts/ios-build.sh build-tests`、`bash scripts/ios-build.sh start-simulator`、`VOID_SIMULATOR_FIXTURES=1 VOID_SEPARATE_LOCAL_PICKER=1 bash scripts/ios-build.sh run-tests`。交付提交的首轮有 45/46 项原生测试、6/7 项界面测试通过。手动重建用例在编译阶段超时，随后同一用例报状态转换错误。外部 Files 用例实际点了 Open，XCTest 等待选择器消失超时。这轮通过了目录扫描、选择器取消和中断恢复、旧表单冷启动、真实首次权限选择（49.348 秒）及完整原生导航（111.271 秒）。[Debug 首轮日志](https://github.com/chkf/void/actions/runs/44515969381/job/135531930904) · [首轮 xcresult](https://github.com/chkf/void/actions/runs/44515969381/artifacts/14528851812)

同一提交原样重跑后，仍为 45/46 项原生测试、6/7 项界面测试通过。手动重建再次超时，dev.10 的 Debug 也曾在此阶段超时。外部 Files 的实际导入、预览和重新授权这次通过（104.995 秒）。本机扫描用例在启动宿主时未取得进程 ID，尚未执行扫描。真实首次权限选择和原生导航两轮均通过。[Debug 重跑日志](https://github.com/chkf/void/actions/runs/44515969381/job/135557801774) · [重跑 xcresult](https://github.com/chkf/void/actions/runs/44515969381/artifacts/14533036704) · [dev.10 的 Debug 记录](https://github.com/chkf/void/actions/runs/44463713533/job/135356333924)

较早的 `07361da` 上，Release 手动重建曾在编译阶段超时。该提交的小屏界面测试首轮未在 8 秒内看到第三个标签，重跑则在收起键盘并点另一页后仍看到原输入框。同一提交的常规 iPhone 17 通过了完整导航用例，交付提交的小屏和 iPad 验收结果见上。[Release 首轮](https://github.com/chkf/void/actions/runs/44507629621/job/135503266129) · [iPhone 17e 首轮](https://github.com/chkf/void/actions/runs/44507629621/job/135503266381) · [iPhone 17e 重跑](https://github.com/chkf/void/actions/runs/44507629621/job/135530839785) · [常规 iPhone 17](https://github.com/chkf/void/actions/runs/44507629621/job/135503267022)

独立的 `bash scripts/ios-build.sh local-picker` 用例未通过。系统 Files 没有在本机测试目录同时显示 `app` 与 Open，测试止于系统选择操作。dev.10 正式标签也记录过这一结果。[本轮 Files 记录](https://github.com/chkf/void/actions/runs/44515969381/job/135531930845) · [dev.10 对应记录](https://github.com/chkf/void/actions/runs/44466295745/job/135364768906)

## v0.1.0-dev.10 首次项目权限弹窗

原 iPhone 的崩溃报告确认，构建 9 在 iOS 27.2.1 上首次询问项目权限时，`SDKSession.require` 经 `SDKPresenter.confirm` 尝试设置系统提示框的呈现代理。UIKit 在主线程触发断言，VoidHost 以 `SIGABRT` 退出。当时另一条线程正在读取项目目录，所以恢复页显示「首屏内容已就绪，正在复核源码」。较早的 SQLite 首屏回归预先授予了数据库权限，跳过了触发闪退的步骤。

构建 10 通过系统弹窗的「允许」和「不允许」动作接收答复，连续的权限请求等待前一个弹窗关闭。退出项目时取消尚未作答的请求。诊断按预览请求记录权限询问及其结果。原 iPhone 上「健身记录」的预览与训练保存仍待验证。

iOS 27.2 模拟器从 Documents 扫描一个没有授权记录的 TSX 项目，经最近记录预览。界面测试在真实弹窗中允许数据库、拒绝文件读取，收到 `PERMISSION_DENIED`，再从页面写入一条测试记录。冷启动后读回原值，两项权限决定均已保留。Release 用时 91.030 秒，Debug 用时 44.224 秒。另一项 Release 回归在文件协调器占用原目录时关闭待答弹窗，收到了取消结果，随后目录复核完成。[Release 测试](https://github.com/chkf/void/actions/runs/44463713533/job/135356333801) · [Debug 测试](https://github.com/chkf/void/actions/runs/44463713533/job/135356333924)

这轮六项常规界面测试均通过，涵盖外部 Files 导入与重新授权、宿主扫描本机项目、恢复预览和权限选择。组合原生用例在手动重新编译已有页面时超时。单独用系统 Files 进入应用文稿目录的用例也未完成。[常规模拟器](https://github.com/chkf/void/actions/runs/44463713533/job/135356333924) · [独立 Files 模拟器](https://github.com/chkf/void/actions/runs/44463713533/job/135356333636)

正式标签通过全部 10 项 Release 原生回归和 1 项 Release 界面回归。手动重新构建、坏清单恢复及冷启动的组合用例用时 22.892 秒，预置 SQLite 数据的原生首屏用时 8.594 秒，真实弹窗选择与保存后冷启动用时 114.512 秒。[dev.10 标签的 Release 回归](https://github.com/chkf/void/actions/runs/44466295745/job/135364769126)

标签的常规模拟器通过 41 项原生测试及 6 项界面测试中的 5 项。另一项本机扫描界面测试在点扫描前，XCTest 未取得应用进程 ID。同一提交的上一轮通过了这一用例。独立 Files 测试仍未进入应用文稿中的目标文件夹。[标签常规回归](https://github.com/chkf/void/actions/runs/44466295745/job/135364769501) · [标签独立 Files 回归](https://github.com/chkf/void/actions/runs/44466295745/job/135364768906)

已从公开 Release 重新下载 arm64 IPA，文件大小为 6,101,096 字节，SHA-256 与 GitHub 附件摘要一致，为 `e2a22b79f4532aee5e41489ab98842930bf75b9ab74d80d7a4ba089aad01b994`。应用标识为 `app.chkf.void`，构建号为 10，最低系统为 iOS 17.0。可执行文件 UUID 为 `C165F6F6-ED20-32FB-906F-2E344837F290`。已比对构建 9 与 10 的离线工具链及随包模板内容。覆盖安装需要沿用旧版的签名团队和实际应用标识。[公开 IPA](https://github.com/chkf/void/releases/download/v0.1.0-dev.10/void-unsigned.ipa) · [发布记录](https://github.com/chkf/void/actions/runs/44466295745/job/135372019887)

## v0.1.0-dev.9 恢复页和重新构建

dev.8 候选包的界面测试在「正在等待项目首屏」时结束宿主，再从恢复页点「上次预览诊断」。XCTest 的界面记录显示，按钮打开的是标题为「目录诊断」的总记录页。本版把中断请求编号作为所打开页面的标识，并在界面测试中核对弹出的标题和原请求的首屏阶段。保留旧页面重新编译时，编译器使用一个附着于窗口的小视图，手动构建和冷启动也加入了 Release 回归。[出现问题的模拟器记录](https://github.com/chkf/void/actions/runs/44447162435/job/135301991382)

dev.9 提交通过 9 项 Release 回归。真实目录导入、手动重新构建、坏清单保留旧页面、恢复后重启读取同一项目的组合用例耗时 64.535 秒。百行 TSX 表单从旧 SQLite 读到原值并显示，提供方占用目录时可以取消启动中的监听。[Release 配置运行记录](https://github.com/chkf/void/actions/runs/44450775344/job/135313860439)

原 dev.9 标签的五项端到端界面测试均通过，包括强退、打开对应诊断再恢复 TSX。原生组合测试另建了测试窗口，看到首屏即可触发下一次重建。该用例数次出现超时，首次运行的 40 项原生测试中通过 39 项。原标签未自动发布。补验使用应用已有的前台窗口，在预览按钮可用的时间点触发重新构建，同时保留手动请求接管后台扫描、坏清单回退及冷启动断言。相同应用源码在该测试下通过 9 项 Release 回归，完整组合用例用时 19.613 秒。发布复验使用标签 `v0.1.0-dev.9.1`，应用构建号仍为 9。[较早的标签测试](https://github.com/chkf/void/actions/runs/44451941659/job/135317753652) · [原标签复跑](https://github.com/chkf/void/actions/runs/44451941659/job/135325362796) · [使用前台窗口的运行记录](https://github.com/chkf/void/actions/runs/44454586956/job/135326402861)

复验标签的常规模拟器通过全部 40 项原生测试和 5 项界面测试，包括真实外部 Files 导入与重新授权、本机发现后从旧记录预览、首屏强退后打开对应诊断并恢复。修改依赖后的手动重建显示了新内容，并保留同一项目身份。独立的系统 Files 用例仍未选中 App 自己的项目文件夹。另一次 Release 测试在相同手动重建阶段超时，当时编译网页报告可见。其他使用相同应用代码的 Release 运行完成了全部 9 项，用例结果存在差异。[40 项原生与 5 项界面测试](https://github.com/chkf/void/actions/runs/44456466314/job/135332564923) · [手动重建超时记录](https://github.com/chkf/void/actions/runs/44456466314/job/135332564721) · [同一应用代码的 Release 验证](https://github.com/chkf/void/actions/runs/44457595930/job/135336312345) · [本机系统 Files 用例](https://github.com/chkf/void/actions/runs/44456466314/job/135332564808)

标签上的 Release 重跑仍出现手动重建超时。补验运行在同一轮通过 9 项 Release、40 项原生和 5 项界面测试。GitHub Actions 下载了该轮与标签轮的两个设备构建，比对 IPA 内全部 34 项内容，包括可执行文件、资源和离线工具链，全部逐字节相同。核验后发布了标签轮的原始 IPA，未改签。公开附件为 6,096,834 字节，SHA-256 为 `2220a610a7fcc97bf53b3bb926bb4a483eada43df3b44d0dddce36655ffa54a4`。构建号为 9，应用标识为 `app.chkf.void`，最低系统为 iOS 17.0，Xcode 27.2，Mach-O UUID 为 `191EE8B7-A4DD-3ACB-B58A-01594F36FB17`。[Release 安装包](https://github.com/chkf/void/releases/download/v0.1.0-dev.9.1/void-unsigned.ipa) · [逐文件核验与发布](https://github.com/chkf/void/actions/runs/44461245100) · [补验全部原生与界面测试](https://github.com/chkf/void/actions/runs/44457595930/job/135336312799)

原 iPhone 上「正在等待项目首屏」的系统退出原因仍未确定。模拟器用预置的测试记录核验了 SQLite 读取，原「健身记录」的实际首屏与训练保存未做真机验收。

## v0.1.0-dev.8 TSX 首屏与中断定位

原 iPhone 的恢复页显示「健身记录」曾在「正在等待项目首屏」时中断，并显示该项目已经找到。两个提示可以来自不同请求。旧版本在收到 TSX 控件之后，还会复核源码并将全部构建资源编码成一份 JSON，再让 SwiftUI 显示页面。在这些步骤中意外退出，恢复页都可能显示同一条首屏提示。截图没有提供进程被终止的原因。

从公开 dev.7 IPA 取出的界面运行库与用于对照的旧库 SHA-256 相同。在同一 Chromium、同一延迟 16 毫秒的测试桥接下，连续渲染 60 次含 100 行的 React 表单。dev.7 发出了 60 份完整控件树，最多 60 份同时等待回复，共 1,091,581 字节。新版发送首个和最终状态，共 36,317 字节，同时最多等待一份。两版都显示最终标签并触发正确点击回调。这里测量的是桥接消息量。[连续渲染回归](../tests/compiler.test.mjs)

新版在后台直接解析 WebKit 交付的控件数据。单帧容许 16,384 个控件与选项、4 MiB 文本和原有 128 层嵌套。超出时宿主显示错误。首次原生调用的诊断只记录已注册的方法名、是否等待权限以及成功或失败。恢复页可单独查看中断请求，此后扫描其他目录也能找到原记录。[原生控件](../ios/Void/UI/NativeTree.swift) · [首屏和桥接](../ios/Void/Bridge/ProjectPage.swift)

源码复核、正式窗口显示及保存可运行版本现在分别记入恢复文件。宿主等待 SwiftUI 布局和屏幕刷新，并核对项目的 WebKit 页面已附着于同一窗口。发布新构建时逐份保存原始资源，再原子更新版本记录。此前版本的构建和项目身份仍可读取。[构建存储](../ios/Void/Recovery/BuildHistory.swift)

两次发布前模拟器测试都读回了原 SQLite 行、收到了 TSX 控件并复核了源码，接下来等待正式窗口显示时超时。第一次使用小页面，第二次使用 100 行表单。新的实现让每个项目从准备到显示始终持有同一个 WebKit 视图，并由该视图在窗口实际布局及刷新后确认首屏。[小页面超时](https://github.com/chkf/void/actions/runs/44445050881/job/135295047499) · [百行表单超时](https://github.com/chkf/void/actions/runs/44445656252/job/135297025544)

修复后，同一提交在 Xcode 的 Release 配置下通过 8 项回归。模拟器从原登记打开，读回已有 SQLite 行，连续更新 60 次的百行表单共提交两个版本。源码复核完成后，窗口于请求开始后 13.389 秒确认首屏，13.433 秒完成构建保存。用例还核对宿主 UUID 和原 `runtime.json` 的每个字节。另一个用例在提供方占用目录时取消首屏文件监听，于 0.287 秒内完成。[首屏与取消的运行记录](https://github.com/chkf/void/actions/runs/44447162435/job/135301991326)

构建号 8 的公开 IPA 为 6,096,769 字节，下载后 SHA-256 为 `d17a82f4ca86f40283c66675ef5f846e5459575eae96548f5b377f3ed2a5666a`。正式标签通过 8 项 Release 回归。在常规模拟器的 40 项原生测试中有一项重新构建超时，5 项界面测试中有一项打开中断诊断页失败。另一台模拟器在系统 Files 中未进入预置的本机项目目录。后续构建 9 针对重新构建和诊断页做了修正。[dev.8 安装包](https://github.com/chkf/void/releases/tag/v0.1.0-dev.8) · [标签测试](https://github.com/chkf/void/actions/runs/44449206863)

## v0.1.0-dev.7 本机扫描、旧记录预览与中断恢复

dev.6 后续模拟器验证发现，旧项目中断提示可能跨过用户后来创建的工作区，导致重启后回到旧提示。新版在保存创建登记时同时保存选中项。用户选择其他项目后，仅结束已展示的旧恢复标记。原请求的诊断仍可查看。[发现问题的运行记录](https://github.com/chkf/void/actions/runs/44393162887/job/135115935974) · [恢复回归](../ios/VoidTests/PreviewRecoveryTests.swift)

同次运行还记录到本机 Files 已经显示，XCTest 遍历系统文件列表时超时，尚未按下 Open。该用例拆到全新的模拟器，等待测试目录就绪，从屏幕识别系统 Open 并实际点击，再核验真实选择回调、关闭、登记和 TSX 首屏。[系统选择器回归](../ios/VoidUITests/FolderPickerTests.swift)

构建号 7 的公开 IPA 大小为 6,065,265 字节，重新下载后的 SHA-256 为 `7b45fc3db97db7c465b81daa38e26e1d071d937068c418c8200396a66ec12ae6`。已核对 arm64、应用标识 `app.chkf.void`、最低 iOS 17.0 和 Xcode 27.2。VoidHost 的 Mach-O UUID 为 `3C85EA2F-12EE-3C38-B065-177EC9F8EB05`。此包需要用原签名团队和已安装版本的实际应用标识签名后覆盖安装。[下载 dev.7](https://github.com/chkf/void/releases/download/v0.1.0-dev.7/void-unsigned.ipa) · [构建记录](https://github.com/chkf/void/actions/runs/44402903032/job/135150390966)

标签提交通过了四项 Release 模式回归，包括点旧记录后预览 TSX、首屏读回已有 SQLite 行，以及在项目 A 中断后新建项目 B、重启仍回到 B。两条项目登记均保留。8 项离线编译测试、37 项原生回归和常规模拟器的 5 项界面用例均通过。界面测试中，从本机发现项目后可以从原记录预览，外部 Files 的实际导入和管理重授权分别只回调一次，选中后 18 毫秒和 65 毫秒记录到选择器关闭。系统取消及等待首屏时结束进程再启动也通过。[Release 模式记录](https://github.com/chkf/void/actions/runs/44402903032/job/135150389269) · [原生及界面记录](https://github.com/chkf/void/actions/runs/44402903032/job/135150389621)

独立模拟器在标签提交上识别并实际点了 Open，随后选择器关闭。宿主显示「项目列表 · 此目录没有可识别的项目」。该次没有验证成功选中了指定的测试目录。[本机 Files 首轮记录](https://github.com/chkf/void/actions/runs/44402903032/job/135150384810)

随后在独立模拟器中先创建未登记的原目录、退出宿主，再从 Files 导入。系统显示「我的 iPhone」中的 `void` 文件夹，截图和 XCTest 均识别到了该文件夹。实际点击其图标或系统文件夹控件后，Files 仍停在这一级。该请求只有 `picker.present`，尚未送出 `picker.didPick`，也未开始授权或扫描。这个本机 Files 用例仍未通过。从宿主的「扫描本机项目」发现同类目录、点旧记录再预览的界面用例已通过。补验仅调整了测试和脚本，正式 IPA 沿用构建号 7。[系统 Files 截图及运行记录](https://github.com/chkf/void/actions/runs/44408604483/job/135170397204) · [预置原目录后的回调记录](https://github.com/chkf/void/actions/runs/44411689463/job/135181211620)

同次补验的 37 项原生回归、四项 Release 回归和四项目录界面回归通过。第五项 SwiftUI 模板用例已经冷启动并显示原生表单，随后点击「显示问候」，等待「你好」消失的断言在 8 秒后超时。该用例在正式标签上通过，两次结果均保留。[补验原生和界面记录](https://github.com/chkf/void/actions/runs/44411689463/job/135181212855) · [补验 Release 记录](https://github.com/chkf/void/actions/runs/44411689463/job/135181212071)

当前没有可访问的已配对原 iPhone。模拟器使用自己的测试目录和 SQLite 数据库。原「健身记录」的实际退出原因、原目录首屏及训练保存尚待真机验证。

## v0.1.0-dev.6 本机扫描、旧记录与显式预览

原 iPhone 的用户报告，dev.5 点本机扫描和旧记录都会退出。源码确认，本机发现原先为每个目录建立完整源码快照，仅发现一个项目时还会立即打开它。旧记录同样自动启动预览。缺少该次系统退出报告，尚无法确定手机上的具体终止原因。

本机发现现在只协调读取清单和目录身份。已预览过的最近记录先打开项目页，点「预览项目」才读源码、启动编译器或挂载项目页面。完整性核对分块计算摘要，每次读取至多 256 KiB。单份配置上限为 1 MiB，单次源码快照上限为 96 MiB 和 24,000 个可见条目。超出上限会在项目页显示原因。iOS 提供崩溃或卡顿报告时，诊断页在本机记录异常类别、信号或卡顿时长。[目录读取](../ios/Void/Projects/ProjectSourceReader.swift) · [Apple 系统诊断的交付条件](https://developer.apple.com/documentation/metrickit/mxmetricmanager)

用相同的真实浏览器先后运行 dev.5 IPA 内的编译器和新版编译器。两次均能取消后重开，并编译带中文及空格相对导入的 TSX。对于同一个 3 MiB 原样媒体资源，dev.5 从本地服务读取了 1 次，新版读取了 0 次，并返回了正确的资源键。自动化也校验了 CSS 真正引用的二进制文件仍能打包。[编译器回归](../tests/compiler.test.mjs)

标签提交单独以 Release 配置通过了三项 iPhone 模拟器回归。目录里即使有不能读取的源码链接，本机扫描仍能返回原登记并停在列表，点旧记录可打开项目页，主动预览会给出链接错误。分块校验产生的修订与完整快照一致。在真实 SwiftUI 窗口内，另一项测试从旧记录启动 TSX，通过原生桥接读回已有 SQLite 行，检查了首屏、WebKit 挂载窗口、宿主 UUID 和原 runtime.json 字节。[Release 模式回归记录](https://github.com/chkf/void/actions/runs/44388657465/job/135100024522)

已从 GitHub Release 重新下载构建号 6 的 IPA，大小为 6,063,098 字节，SHA-256 为 `398c1c0e17fa8895893d7f6c7ade41f34e590500b23679d71a3185f0af809dd3`。归档及 arm64 二进制均已校验，应用标识为 `app.chkf.void`，最低 iOS 17.0，SDK 为 27.2。可执行文件的 Mach-O UUID 为 `A558D0AC-E15F-3861-94DB-595BC6FCAB54`，可用来核对 iOS 报告中的 VoidHost 映像。[下载 IPA](https://github.com/chkf/void/releases/download/v0.1.0-dev.6/void-unsigned.ipa) · [源码](https://github.com/chkf/void/tree/v0.1.0-dev.6)

标签上的 36 项原生回归与 8 项离线工具链测试通过。6 项界面用例中有 5 项通过，包括本机扫描后打开原记录、等首屏时强制结束再恢复、外部 Files 目录实际 Open 并预览、管理重授权、系统取消以及 SwiftUI 冷启动。剩余一项本机 Files 打开用例在自动化等待 Open 可操作时超时。该请求已记录 `picker.present`，测试尚未按下 Open。另一项外部 Files 用例中实际收到一次选择回调，从登记和原书签分别成功预览。原 iPhone 的退出原因、原项目首屏和训练保存仍待真机验证。[完整界面测试记录](https://github.com/chkf/void/actions/runs/44388657465/job/135100025701) · [离线工具链及 arm64 构建](https://github.com/chkf/void/actions/runs/44388657465/job/135100025250)

## v0.1.0-dev.5 预览卡住与中断恢复

公开 arm64 IPA 共 6,043,439 字节，SHA-256 为 `a40f49f11772fa2eccada0b664cbe3aafc9e8966caa581ff1ab0d9d014868d8a`。首轮通过 32 项原生测试和 5 项界面测试，包括真正的 Files Open 和预览时结束进程再重开。另一项界面测试在 XCTest 读取系统选择器抓手时超时。[模拟器记录](https://github.com/chkf/void/actions/runs/44381000775/job/135072887562) 同一标签的第二轮完整模拟器测试通过，包括系统选择器下拉取消和中断后恢复。原 iPhone 上仍有用户报告闪退。[第二轮测试](https://github.com/chkf/void/actions/runs/44381000775/job/135086197753)

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
