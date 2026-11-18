# 构建与签名

GitHub Actions 在 `xcode-27` 运行器上选择正式版 Xcode 27.2 和 iOS 27.2 SDK，生成 arm64 iPhone 安装包，并在 iOS 27.2 模拟器上测试。最低安装版本设为 iOS 17。Node.js 22.20.0 负责打包 TSX/HTML 项目使用的离线工具链。[构建记录](https://github.com/chkf/void/actions/workflows/ios.yml) · [GitHub 镜像](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md) · [Apple 版本说明](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes)

| Actions 产物 | 用途 |
| --- | --- |
| void-unsigned-iphone | 解压后包含 void-unsigned.ipa，内含 arm64 Release 应用。安装到 iPhone 需要有效签名和配置描述文件。 |
| void-simulator | 解压内层 ZIP 后可用 `xcrun simctl install booted VoidHost.app` 安装到兼容的 iPhone 模拟器。 |
| void-tests | 解压后用 Xcode 打开 xcresult，查看各用例、失败截图及运行设备。 |

向仓库推送 `v` 开头的版本标签会触发发布。打包任务校验 arm64 架构、最低系统版本、工具链和模板，发布任务再对照 GitHub 返回的 SHA-256 公开下载。模拟器任务独立报告每项测试的结果。含连字符的标签会发布为预发布版本，例如 `v0.1.0-dev.1`。[版本下载](https://github.com/chkf/void/releases)

在装有对应 Xcode 和 iOS Simulator 的 Mac 上，从仓库根目录执行以下命令可复现工作流。

```sh
export DEVELOPER_DIR=/Applications/Xcode_27.2.app/Contents/Developer
export VOID_IOS_SDK=27.2
npm ci
npm run openspec -- validate --all --strict
npm test
bash scripts/ios-build.sh device
bash scripts/ios-build.sh test
```

Xcode 将 `ios/StarterProject/app/SwiftUI/` 下的 Swift 文件直接编译进 VoidHost，并将同一份模板源码复制进安装包，供创建和核对项目。可在该目录添加其他 Swift 文件。保留入口 `ProjectContentView(projectName:)` 即可。开发时运行 `npm run prepare:ios` 生成工具链，在 Xcode 中打开 `ios/Void.xcodeproj` 并选择 **Void**。构建脚本将产物写入 `.build/ios`。

要安装到自己的 iPhone，在 Xcode 的 VoidHost target → Signing & Capabilities 中选择有权限的 Team 和可用的 Bundle Identifier，然后选择已配对的设备运行。CI 的默认构建无需 Apple 签名凭据。[Apple 设备运行说明](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)

要在真机使用 HealthKit、HomeKit 或 NFC，在 Apple Developer 的 App ID 中启用实际需要的能力，并重新生成匹配的 provisioning profile。Xcode 真机目标使用仓库中的授权文件。给未签名 IPA 签名时，选用配置描述文件支持的授权项；个人账号与团队能启用的能力取决于 Apple 的签名配置。相机、麦克风、图库、定位、通讯录及其他隐私服务还会在首次需要时请求系统授权。[工程授权文件](../ios/VoidHost.entitlements) · [HealthKit](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.healthkit) · [HomeKit](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.homekit) · [NFC 标签读取](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.nfc.readersession.formats)
