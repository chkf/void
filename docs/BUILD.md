# 构建与签名

GitHub Actions 使用 macOS 15 和 Xcode 16.4 构建 arm64 iPhone 安装包，最低 iOS 17。模拟器测试在 Apple 芯片的 macOS 26 运行器上使用 Xcode 26.5。两者均使用 Node.js 22.20.0。推送、拉取请求或在工作流页面选择 Run workflow 均可构建当前分支。[构建记录](https://github.com/chkf/void/actions/workflows/ios.yml) · [iPhone 构建镜像](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md) · [模拟器镜像](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)

| Actions 产物 | 用途 |
| --- | --- |
| void-unsigned-iphone | 解压后包含 void-unsigned.ipa，内含 arm64 Release 应用。安装到 iPhone 需要有效签名和配置描述文件。 |
| void-simulator | 解压内层 ZIP 后可用 `xcrun simctl install booted VoidHost.app` 安装到兼容的 iPhone 模拟器。 |
| void-tests | 解压后用 Xcode 打开 xcresult，查看各用例、失败截图及运行设备。 |

向仓库推送 `v` 开头的版本标签会触发发布。打包任务校验 arm64 架构、最低系统版本、工具链和模板，发布任务再对照 GitHub 返回的 SHA-256 公开下载。模拟器任务独立报告每项测试的结果。含连字符的标签会发布为预发布版本，例如 `v0.1.0-dev.1`。[版本下载](https://github.com/chkf/void/releases)

在装有对应 Xcode 和 iOS Simulator 的 Mac 上，从仓库根目录执行以下命令可复现工作流。

```sh
export DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer
npm ci
npm run openspec -- validate --all --strict
npm test
bash scripts/ios-build.sh device
export DEVELOPER_DIR=/Applications/Xcode_26.5.app/Contents/Developer
bash scripts/ios-build.sh test
```

`npm test` 根据锁文件生成 `ios/Toolchain` 并运行编译测试。Xcode 通过文件夹引用将工具链及模板复制进应用。开发时可以只运行 `npm run prepare:ios`，然后打开 `ios/Void.xcodeproj`，选择共享 scheme **Void**。构建脚本将产物写在 `.build/ios`。

要安装到自己的 iPhone，在 Xcode 的 VoidHost target → Signing & Capabilities 中选择有权限的 Team 和可用的 Bundle Identifier，然后选择已配对的设备运行。CI 的默认构建无需 Apple 签名凭据。[Apple 设备运行说明](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)
