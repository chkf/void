# TSX 项目

在 Files 的 app/src/main.tsx 中编辑 React 页面。保存后回到 void，宿主在设备上编译 TSX，将控件树交给 SwiftUI。共享数据放在 data/，应用源码放在 app/，项目依赖声明在 app/package.json。

这个项目可从 @runtime/sdk 导入 ios。文件读写使用 ios.fs.readFile 和 ios.fs.writeFile，默认模板已声明 files.read 和 files.write。各接口的参数、权限与返回值见当前目录的 [SDK 参考](SDK_REFERENCE.md) 和 [TypeScript 定义](types/runtime-sdk.d.ts)。
