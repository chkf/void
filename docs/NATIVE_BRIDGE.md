# 原生桥接

项目从 `@runtime/sdk` 调用已注册的方法。SDK 生成请求 UUID，通过 WebKit 的带响应消息处理器交给 Swift。Dispatcher 校验原生持有的 WebView、主框架和当前回环资源地址，再检查协议版本、标识、方法和参数。各个 Promise 收到自己请求的返回值。

| 协议方法 | 参数 | 效果 |
| --- | --- | --- |
| system.info | 空对象 | 返回 UIDevice 的 name、version 和 model 对应的系统信息 |
| ui.commit | revision、eventSequence、nodes | 校验并提交 SwiftUI 控件树 |
| runtime.ready | 空对象 | 通知宿主 Web 入口已加载 |
| runtime.error | message | 将页面错误通知宿主管理界面 |

`INVALID_SESSION` 表示来源或界面模式无效，`UNSUPPORTED_VERSION` 表示协议不兼容，`UNKNOWN_METHOD` 表示方法尚未注册。`INVALID_PARAMS` 和 `INVALID_TREE` 分别指向请求格式与控件树错误。离开宿主调用 SDK 返回 `NO_SESSION`，投递过程中会话关闭返回 `SESSION_CLOSED`。

控件事件按会话和单调递增的序号分发给 React 回调。项目切换时宿主移除消息处理器并关闭旧会话的回环资源服务。当前公开的业务 API 见 [SDK 参考](SDK_REFERENCE.md)。
