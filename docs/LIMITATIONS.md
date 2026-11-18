# 验证范围

Windows 上可运行 `npm test` 验证真实 TypeScript 类型检查、Wasm 打包、React 控件树及事件、HTML/CSS 构建和共享目录隔离。iPhone Release、iOS 单元测试和界面测试由 [GitHub Actions](https://github.com/chkf/void/actions/workflows/ios.yml) 执行。具体提交的结论和产物以相应运行记录为准。

当前接入的 SDK 方法是 `ios.system.info()`。系统照片、相机、麦克风、定位、蓝牙等能力和对应授权仍在实施清单中。当前文件修改会触发重建与页面替换。项目私有 SQLite、完整热替换、六类持久日志和后台任务仍待实现。

真机验收需要可签名的 App ID、配置描述文件和已配对的 iPhone。还需分别在本地与 iCloud 或其他 File Provider 实测授权、撤销、重新选择、延迟下载及外部编辑。当前没有真机验收记录。
