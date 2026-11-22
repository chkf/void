# 构建与签名

GitHub Actions 在 `xcode-27` 运行器上选择正式版 Xcode 27.2 和 iOS 27.2 SDK，生成 arm64 iPhone 安装包，并在 iOS 27.2 模拟器上测试。最低安装版本设为 iOS 17。Node.js 22.20.0 负责打包 TSX/HTML 项目使用的离线工具链。[构建记录](https://github.com/chkf/void/actions/workflows/ios.yml) · [GitHub 镜像](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md) · [Apple 版本说明](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes)

| Actions 产物 | 用途 |
| --- | --- |
| void-unsigned-iphone | 包含需签名的 arm64 Release 安装包 void-unsigned.ipa、原生组件示例 native-ui-example.zip，以及独立安全区测试项目 safe-area-sample.zip。 |
| void-simulator | 解压内层 ZIP 后可用 `xcrun simctl install booted VoidHost.app` 安装到兼容的 iPhone 模拟器。 |
| void-tests | 解压后用 Xcode 打开 xcresult，查看各用例、失败截图及运行设备。 |
| void-native-ui-compact、void-native-ui-ipad | 独立模拟器的原生导航测试报告与导出的截图附件，含深浅色、横屏和辅助功能字号。 |
| void-release-preview-screenshots | Release 配置的模拟器预览截图，含安全区首帧与完整显示器截图。 |

安装设备包后，可在项目列表右上角的「设置」核对 void 的应用版本。在深色和浅色下分别点首页的创建与导入，核对文字颜色。将项目放入 void 文稿，回到列表后点开自动出现的项目，核对转场中的导航标题。[宿主操作说明](RUNTIME.md)

真机待验。将同一发布中的 `safe-area-sample.zip` 解压并导入 `safe-area` 文件夹。把系统外观设为深色，打开 Sample，比较时间两侧空白和页面背景（`#204858`）。切到系统浅色应同步变为 `#C8E8E0`。在 Settings 中点 Light、Dark 或 Change palette，切回 Sample 检查滚动位置和 Draft 中已输入的文字。展开、收起键盘，横竖屏各转一次，再返回前台。在样例本地副本的 `app/src/` 添加一个含类型错误的测试文件，回到预览检查错误提示出现时从状态栏到标题的背景，再移除该测试文件。留存完整屏幕截图，并记录设备型号、系统版本和宿主构建号。[最小项目](../tests/fixtures/safe-area)

模拟器可用 `VOID_LAYOUT_PROFILE=compact bash scripts/ios-build.sh native-layout` 或 `VOID_LAYOUT_PROFILE=ipad bash scripts/ios-build.sh native-layout`。首帧探针在显示刷新时采样宿主窗口，并记录标签容器、选中页面和 WebKit 在窗口中的实际位置。界面测试使用完整显示器截图，采样时转换到 sRGB，每通道容差为 8。

在 iPhone 上把 Sample 拉回顶端，观察完整的大标题。慢慢上滑，标题会收为导航栏中央的小标题。然后在 Settings 点 Scroll title，返回 Sample 并拉到顶端。再慢慢上滑，观察「Scroll heading」从状态栏后方经过，回到顶端时首行再次完整。真机验收使用系统截图，保留时间、电池和页面内容。

在 iOS 27.2 的 iPhone 17e 上，构建 12 的深色稳定帧从纯黑状态栏过渡到一行 1 pt 的白色 WebKit，再到主题内容。同一窗口只将 WebKit 设为透明，白线随即消失。构建 13 的稳定帧已连续，但在深色首帧，宿主顶部提示仍把第 47 至 91 pt 绘为纯黑。构建 14 的相同采样点与内容均为 `#204858`，浅色回归也通过。原生宿主测试还在后台候选页已提交另一套主题时核对了前台像素。[构建 12 图层对照](https://github.com/chkf/void/actions/runs/44714418882) · [构建 13 双机型基线](https://github.com/chkf/void/actions/runs/44713105819) · [构建 14 的 iPhone 17e 原图](https://github.com/chkf/void/actions/runs/44713663812/artifacts/14620521214)

VoiceOver 手势与实际朗读在签名设备上验收。在系统「设置 → 辅助功能」启用 VoiceOver，打开独立示例，左右轻扫可听到当前标签、图标标签、输入框和进度。双点示例里的「设置」标签，确认能找到并打开「项目管理」。输入后切走再回来，核对文本与滚动位置。模拟器测试覆盖辅助功能树、对比度和大字体。[Apple 的辅助技术测试说明](https://developer.apple.com/documentation/accessibility/performing-accessibility-testing-for-your-app)

向仓库推送 `v` 开头的版本标签会触发发布。发布任务核对 arm64 安装包和 GitHub 附件的 SHA-256。稳定版还需通过模拟器测试。`-dev.` 开发包在发布页注明同一提交的模拟器结果，便于原位验证真机问题。[版本下载](https://github.com/chkf/void/releases)

原位更新请沿用旧版的签名团队、实际 Bundle ID 和已有应用标识配置，覆盖安装以保留原有数据容器。安装后在「所有项目」点原记录，再点「预览项目」。

Xcode 首次构建时通过 Swift Package Manager 获取工程中固定提交的 libgit2 1.9.2。Git 克隆与拉取使用该库提供的 HTTPS 传输。[依赖源码](https://github.com/ibrahimcetin/libgit2/tree/52287b0914f300f916b58fec80e13d8dd8f6824f)

在装有对应 Xcode 的 Mac 上，为测试准备一个独立的 iPhone 模拟器。项目列表测试在 void 文稿中准备随机命名的 TSX 项目，检查它能自动出现并打开预览。系统选择器测试在模拟器的「我的 iPhone」中准备另一个 TSX 项目。通过 Files 选择外部目录并按 Open，测试检查本地副本、TSX 首屏和重开结果。可从仓库根目录执行以下命令复现工作流。

```sh
export DEVELOPER_DIR=/Applications/Xcode_27.2.app/Contents/Developer
export VOID_IOS_SDK=27.2
npm ci
npm run openspec -- validate --all --strict
npm test
bash scripts/ios-build.sh device
bash scripts/ios-build.sh release-preview
VOID_SIMULATOR_FIXTURES=1 bash scripts/ios-build.sh test
```

Xcode 将 `ios/TSXProject/` 作为资源打入 IPA，供宿主创建 React / TSX 项目。为了运行已有的 SwiftUI 项目，Xcode 也将 `ios/StarterProject/app/SwiftUI/` 下的 Swift 文件编译进 VoidHost，并随包附上同一份源码供核对。这些项目使用入口 `ProjectContentView(projectName:)`。开发时运行 `npm run prepare:ios` 生成工具链，在 Xcode 中打开 `ios/Void.xcodeproj` 并选择 **Void**。构建脚本将产物写入 `.build/ios`。

要安装到自己的 iPhone，在 Xcode 的 VoidHost target → Signing & Capabilities 中选择有权限的 Team 和可用的 Bundle Identifier，然后选择已配对的设备运行。CI 的默认构建无需 Apple 签名凭据。[Apple 设备运行说明](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)

要在真机使用 HealthKit、HomeKit 或 NFC，在 Apple Developer 的 App ID 中启用实际需要的能力，并重新生成匹配的 provisioning profile。Xcode 真机目标使用仓库中的授权文件。给未签名 IPA 签名时，选用配置描述文件支持的授权项；个人账号与团队能启用的能力取决于 Apple 的签名配置。相机、麦克风、图库、定位、通讯录及其他隐私服务还会在首次需要时请求系统授权。[工程授权文件](../ios/VoidHost.entitlements) · [HealthKit](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.healthkit) · [HomeKit](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.homekit) · [NFC 标签读取](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.nfc.readersession.formats)
