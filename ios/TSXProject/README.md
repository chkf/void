# TSX 项目

在 Files 的 app/src/main.tsx 中编辑 React 页面。保存后回到 void，宿主在设备上编译 TSX，将控件树交给 SwiftUI。共享数据放在 data/，应用源码放在 app/，项目依赖声明在 app/package.json。

项目自己的「设置」里应有一行「项目管理」。从 `@runtime/ui` 导入 `ProjectManagementButton`，在现有表单中使用 `<Section title="设置"><ProjectManagementButton /></Section>`。例如有「我的」标签时，可把这个分组放进「我的」页面。模板已提供可运行的示例。Web 应用可在自己的设置页使用 `<a href="void://project/management">项目管理</a>`。

这个项目可从 @runtime/sdk 导入 ios。文件读写使用 ios.fs.readFile 和 ios.fs.writeFile，默认模板已声明 files.read 和 files.write。各接口的参数、权限与返回值见当前目录的 [SDK 参考](SDK_REFERENCE.md) 和 [TypeScript 定义](types/runtime-sdk.d.ts)。
