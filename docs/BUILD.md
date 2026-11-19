# 构建与签名

GitHub Actions 在 `xcode-27` 运行器上选择正式版 Xcode 27.2 和 iOS 27.2 SDK，生成 arm64 iPhone 安装包，并在 iOS 27.2 模拟器上测试。最低安装版本设为 iOS 17。Node.js 22.20.0 负责打包 TSX/HTML 项目使用的离线工具链。[构建记录](https://github.com/chkf/void/actions/workflows/ios.yml) · [GitHub 镜像](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md) · [Apple 版本说明](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes)

| Actions 产物 | 用途 |
| --- | --- |
| void-unsigned-iphone | 解压后包含 void-unsigned.ipa 和 native-ui-example.zip。前者是需要签名的 arm64 Release 应用，后者解压后可从「导入文件夹」选择 native-ui。 |
| void-simulator | 解压内层 ZIP 后可用 `xcrun simctl install booted VoidHost.app` 安装到兼容的 iPhone 模拟器。 |
| void-tests | 解压后用 Xcode 打开 xcresult，查看各用例、失败截图及运行设备。 |
| void-native-ui-compact、void-native-ui-ipad | 独立模拟器的原生导航测试报告与导出的截图附件，含深浅色、横屏和辅助功能字号。 |

构建 11 的设备包覆盖 iPhone 与 iPad。下载同一提交工作流中的 `void-unsigned-iphone`，解压取得 `void-unsigned.ipa`。该包内附 `Toolchain/NativeUIDemo`。独立模拟器可用 `VOID_LAYOUT_PROFILE=compact bash scripts/ios-build.sh native-layout` 或 `VOID_LAYOUT_PROFILE=ipad bash scripts/ios-build.sh native-layout` 重现原生导航验收。[组件契约与独立示例](NATIVE_UI.md)

VoiceOver 手势与实际朗读在签名设备上验收。打开独立示例，在「设置 → 辅助功能」启用 VoiceOver，左右轻扫，确认能听到当前标签、图标标签、输入框、进度和宿主管理。双点切换标签，确认朗读顺序进入所选页；输入后切走再回来，核对文本与滚动位置。模拟器测试覆盖辅助功能树、对比度和大字体。[Apple 的辅助技术测试说明](https://developer.apple.com/documentation/accessibility/performing-accessibility-testing-for-your-app)

向仓库推送 `v` 开头的版本标签会触发发布。发布任务核对 arm64 安装包和 GitHub 附件的 SHA-256。稳定版还需通过模拟器测试。`-dev.` 开发包在发布页注明同一提交的模拟器结果，便于原位验证真机问题。[版本下载](https://github.com/chkf/void/releases)

原位更新请沿用旧版的签名团队、实际 Bundle ID 和已有应用标识配置，覆盖安装以保留原有数据容器。安装后点最近项目中的原记录，再点「预览项目」。若先使用「扫描本机项目」，扫描完成后从列表选原记录即可。

在装有对应 Xcode 的 Mac 上，为测试准备一个独立的 iPhone 模拟器。本机扫描测试在 Void 文稿中准备随机命名的未登记 TSX 项目。系统选择器测试在这个模拟器的「我的 iPhone」中准备 Void Files QA 文件夹，里面是仓库已有的 TSX 模板。通过 Files 选择该外部目录并按 Open，测试检查返回的项目名、TSX 首屏和更新原授权的结果。可从仓库根目录执行以下命令复现工作流。

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

Xcode 将 `ios/StarterProject/app/SwiftUI/` 下的 Swift 文件直接编译进 VoidHost，并将同一份模板源码复制进安装包，供创建和核对项目。可在该目录添加其他 Swift 文件。保留入口 `ProjectContentView(projectName:)` 即可。开发时运行 `npm run prepare:ios` 生成工具链，在 Xcode 中打开 `ios/Void.xcodeproj` 并选择 **Void**。构建脚本将产物写入 `.build/ios`。

要安装到自己的 iPhone，在 Xcode 的 VoidHost target → Signing & Capabilities 中选择有权限的 Team 和可用的 Bundle Identifier，然后选择已配对的设备运行。CI 的默认构建无需 Apple 签名凭据。[Apple 设备运行说明](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)

要在真机使用 HealthKit、HomeKit 或 NFC，在 Apple Developer 的 App ID 中启用实际需要的能力，并重新生成匹配的 provisioning profile。Xcode 真机目标使用仓库中的授权文件。给未签名 IPA 签名时，选用配置描述文件支持的授权项；个人账号与团队能启用的能力取决于 Apple 的签名配置。相机、麦克风、图库、定位、通讯录及其他隐私服务还会在首次需要时请求系统授权。[工程授权文件](../ios/VoidHost.entitlements) · [HealthKit](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.healthkit) · [HomeKit](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.homekit) · [NFC 标签读取](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.nfc.readersession.formats)
