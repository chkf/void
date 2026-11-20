# iPhone 顶部的滚动内容与系统导航标题

void `0.1.0 (15)` 已作为 `v0.1.0-dev.15` 预发布。源码提交为 `f51f93931a16055ae4c76d9b289cd52c04877fc0`，公开 IPA 的 SHA-256 为 `9ce421acdff46123f9cbb4540db827951891881be67f01e6e440f0ff6a56dfec`。重新下载后核对了 arm64、`app.chkf.void`、最低 iOS 17.0、iPhone 和 iPad 设备族，并对照标签源码核实了独立样例中的四个文件。[下载未签名 IPA](https://github.com/chkf/void/releases/download/v0.1.0-dev.15/void-unsigned.ipa) · [下载最小样例](https://github.com/chkf/void/releases/download/v0.1.0-dev.15/safe-area-sample.zip) · [发布记录](https://github.com/chkf/void/releases/tag/v0.1.0-dev.15)

深色场景由 iPhone 17 模拟器的 `simctl io screenshot` 截取，包含系统状态栏。设备运行 iOS 27.2，画面为 402 × 874 pt、1206 × 2622 px，窗口顶部安全区为 62 pt。各图保留原始尺寸与颜色配置。

项目只使用现有的 Theme、两个普通 Tab、Screen、ScrollView、文本和输入框。深色页面为 `#204858`，滚动标题的背景标记为 `#509090`。自绘标题场景从静止位置上移 50 pt，声明了 Screen.title 的场景上移 200 pt。

| 完整显示器截图 | 构建 14 | 构建 15 |
| --- | --- | --- |
| 自绘标题在顶端 | [原图](14-Tabs-Rest.png) | [原图](15-Tabs-Rest.png) |
| 自绘标题经过状态栏 | [原图](14-Tabs-Scrolled.png) | [原图](15-Tabs-Scrolled.png) |
| Screen.title 在顶端 | [原图](14-Titled-Rest.png) | [原图](15-Titled-Rest.png) |
| Screen.title 在上滑后 | [原图](14-Titled-Scrolled.png) | [原图](15-Titled-Scrolled.png) |
| 浅色主题的首屏（iPhone 17e） | [原图](14-Light-Opened.png) | [原图](15-Light-Opened.png) |

构建 14 的标签控制器、选中页和滚动视图都从窗口 y=62 pt 开始。滚动视图和系统标签容器都在这里裁剪，孩子收到的顶部安全区为 0。去掉 TabView，同一滚动视图的窗口起点为 y=0，顶部内容内距为 62 pt，标题能经过时间后方。[无标签对照原图](14-Plain-Scrolled.png) · [构建 14 图层与动作记录](https://github.com/chkf/void/actions/runs/44731898024/job/136273517184)

早期构建 12 还测到一条 1 pt 亮线。在同一窗口只改变隐藏 WKWebView 的透明度就能改变线的颜色，构建 13 已把未请求的画布裁剪至零布局高度。本轮在构建 14 复现了同色区域截断滚动内容。用户照片中的宿主构建号仍须从「宿主信息」核对。[早期细线的单变量实验和原图](https://github.com/chkf/void/blob/0238c500116aa53f70053ca857d8632e3acb658a/docs/safe-area-evidence/README.md)

`HostView.swift` 的 `RunningPage` 判断顶部是否已有宿主控件、相机或画布。`NativeAppearance.swift` 把可用边缘传给根原生节点。`NativeNodeView.swift` 让根标签控制器接管系统顶部内距，为支持的整页滚动布局接入系统导航标题。`NativeTabs.swift` 保留每个 Tab 对应的 hosting controller，iPad 标签页使用原有的页面内标题。项目传入的主题、节点 ID 和输入仍由原运行时管理。[宿主与原生视图改动](https://github.com/chkf/void/compare/v0.1.0-dev.14...v0.1.0-dev.15)

| 自绘标题上移 50 pt 后的 sRGB 背景样本 | x=297.5、y=16 pt | x=297.5、y=56 pt |
| --- | --- | --- |
| 构建 14，有 Tab | `#204858` | `#204858` |
| 构建 14，无 Tab | `#376B73` | `#4F8F90` |
| 构建 15，有 Tab | `#376B73` | `#4F8F90` |

构建 15 的滚动视图从窗口 y=0 开始，顶部内容内距仍为 62 pt。自绘标题上移时，采样点的颜色经过系统边缘效果混合。拉回顶端后，两处都恢复 `#204858`。[回到顶端的原图](15-Tabs-Returned.png) · [iPhone 17 真实手势的 Release 整屏截图](15-Scroll-Gesture.png)

声明 `Screen.title` 的页面在构建 14 中，滚动前后标题字形都在 x=17…207 pt。构建 15 在顶端时标题字形左边为 17.3 pt，高 29.6 pt。收起时字形高 15 pt，中点在 x=200.5 pt，屏幕中心为 201 pt。系统导航栏收为 54 pt 高。[构建 15 图层与动作记录](https://github.com/chkf/void/actions/runs/44741422162/job/136305742222) · [原始附件](https://github.com/chkf/void/actions/runs/44741422162/artifacts/14632344940)

系统导航标题使用现有 `Screen.title`。项目自己画在滚动内容里的标题保留原文、图标和排列。可用同一发布里的 `safe-area-sample.zip`，分别检查 Sample 和 Settings → Scroll title 两种模式。

浅色对照使用发布样例的 Sample 页，取自 iPhone 17e 的 `XCUIScreen.main.screenshot()`，尺寸均为 1170 × 2532 px。两版在 (281, 24) px 和 (25, 160) px 的 sRGB 都是主题浅色 `#C8E8E0`。[构建 14 原附件](https://github.com/chkf/void/actions/runs/44718077036/artifacts/14621687678) · [构建 15 原附件](https://github.com/chkf/void/actions/runs/44749070323/artifacts/14636667662)

深色对照使用构建 14 的宿主提交 `92d93bb` 和构建 15 的 `f51f939`。对应的截图测试提交为 `ebcc085` 和 `18ca70b`，两次都用 `git diff --exit-code` 核对了 `ios/Void` 与 Xcode 工程文件。对照使用同一份 TSX、设备、滚动距离和坐标。图片包含系统时钟、状态图标和屏幕底部标签栏。在 Mac 的对应诊断提交，运行 `npm ci`、`npm run prepare:ios`、`bash scripts/scroll-edge-probe.sh` 可重做测量。构建 14 的标签页会触发滚动内容进不了安全区的断言。[构建 14 诊断源码](https://github.com/chkf/void/commit/ebcc0856b577bb4246d14d20f0b29153a36b5cc8) · [构建 15 诊断源码](https://github.com/chkf/void/commit/18ca70ba3f8b06b3ceb6869d584fd4cfed233ad2) · [Release 手势附件](https://github.com/chkf/void/actions/runs/44749070323/artifacts/14639712096)

## 测试环境和命令

本地 Windows 的 `npm test` 通过 14 项，`npm run openspec -- validate --all --strict` 通过 1 项。GitHub macOS 运行器使用 Xcode 27.2 和 iOS 27.2。`bash scripts/ios-build.sh device` 生成 arm64 包，`bash scripts/ios-build.sh release-preview` 在 iPhone 17 的发布复测中通过 23 项宿主测试和 3 项界面测试，包括深浅首帧、动态主题、前后台、键盘、无标签、无 Theme、恢复和项目切换。[设备构建](https://github.com/chkf/void/actions/runs/44749070323/job/136331908188) · [Release 模拟器结果](https://github.com/chkf/void/actions/runs/44749070323/job/136358643043) · [跟随系统切到深色的整屏原图](15-System-Dark.png)

正式标签的 `VOID_LAYOUT_PROFILE=compact bash scripts/ios-build.sh native-layout` 和 `VOID_LAYOUT_PROFILE=ipad bash scripts/ios-build.sh native-layout` 各通过 13 项宿主测试和 4 项界面测试。两台模拟器都验证了保留输入和滚动锚点、增减标签、切换主题、横屏打开管理面板以及回前台。iPad 的系统标签位于顶部。嵌套的大标题栏曾在重新选中标签时展开，影响锚点，修复保留 iPad 标签页原有标题布局。[iPhone 17e 结果](https://github.com/chkf/void/actions/runs/44749070323/job/136331908118) · [iPad mini 结果](https://github.com/chkf/void/actions/runs/44749070323/job/136331908216)

iPhone 17 的一次 Release 检查在系统命令返回约 1.6 秒后拍到了原来的浅色，顶部和内容区同色。在相同宿主源码上，另一次独立检查保持页面可见，依次切到深、浅、深。第一次切换在 2.80 秒采到顶部和内容区都为 RGB (81, 119, 128)，3.41 秒两处都到达主题深色 (32, 72, 88)。后两次分别在 0.23 秒和 0.99 秒采到目标色。上述时间包含截图耗时，三次都没有操作页面。[首次检查](https://github.com/chkf/void/actions/runs/44749070323/job/136331908160) · [连续三次系统切换的采样记录](https://github.com/chkf/void/actions/runs/44752489665/job/136343650924) · [系统切换帧](https://github.com/chkf/void/actions/runs/44752489665/artifacts/14637257047)

正式标签的通用 Debug 先运行 `bash scripts/ios-build.sh build-tests` 和 `bash scripts/ios-build.sh start-simulator`，再运行 `VOID_SIMULATOR_FIXTURES=1 VOID_SEPARATE_LOCAL_PICKER=1 bash scripts/ios-build.sh run-tests`。54 个宿主用例中 53 项通过，目录恢复用例报告 `InvalidTransition`。10 个界面用例中 1 项通过，9 项失败，涉及本机扫描、测试项目定位和首次打开。另一台模拟器运行 `bash scripts/ios-build.sh local-picker`，系统 Files 未在预设目录同时显示 app 和 Open。构建 14 的通用检查也曾报告目录恢复失败和系统文件选择问题。本次记录保留各自的结果。[Debug 全量日志](https://github.com/chkf/void/actions/runs/44749070323/job/136331908604) · [独立 Files 日志](https://github.com/chkf/void/actions/runs/44749070323/job/136331907779) · [构建 14 记录](https://github.com/chkf/void/actions/runs/44718077036/job/136247959109)

## 真机待验

1. 沿用已安装版本的签名团队和实际 Bundle ID，覆盖安装新的 void IPA。在「项目管理 → 宿主信息」记下版本、构建号、设备及 iOS 版本，从最近项目打开原登记。
2. 在独立样例的 Sample 页输入 Draft。停在页首时大标题应完整。缓慢上推，观察标题是否收为居中小标题、列表能否在导航栏后方滚动。再拉回顶端。
3. 在 Settings 点 Scroll title，回到 Sample。缓慢推动自绘标题，确认文字进入时间旁的区域，并确认停在顶端时首行仍完整。对这两个位置各截取整张设备屏幕。
4. 在 Settings 切换标签、主题和外观，返回 Sample 查看 Draft。收放键盘、转为横屏、回到前台，再检查输入和可见状态栏。用本人原项目时，只需安装宿主并重新打开原登记。
