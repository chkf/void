# 当前原生 SDK

`@runtime/sdk` 版本为 1.0.0。类型定义在 [sdk.d.ts](../runtime/sdk.d.ts)，WebKit 会话中的实现通过 Swift Dispatcher 调用已编译的方法。

## 读取系统信息

在 `app/package.json` 的 dependencies 中加入 `"@runtime/sdk": "1.0.0"`。`ios.system.info()` 从 UIDevice 提供操作系统名、系统版本和设备类别，无需声明系统权限。

```ts
import { ios } from "@runtime/sdk";

const result = await ios.system.info();
if (result.success) {
  console.log(result.data.name, result.data.version, result.data.model);
} else {
  console.error(result.error.code, result.error.message);
}
```

返回值为 `Promise<Result<{ name: string; version: string; model: string }>>`。model 取自系统的设备类别字段，例如 iPhone。协议错误和会话关闭的行为见[原生桥接](NATIVE_BRIDGE.md)。
