# Spec Delta

## Purpose

项目需要一种稳定的方式从 TypeScript 调用宿主并接收原生事件。调用双方能按请求识别结果和错误，及时结束失效的操作，并在项目切换或运行时重建后隔离旧会话。

## ADDED Requirements

### Requirement: 统一的版本化 RPC 契约

`@runtime/sdk` SHALL 通过同一 Dispatcher 派发所有原生方法，携带协议版本、方法名、请求 ID 和已校验的参数。异步调用返回带类型的结果，成功含 `success: true` 与 `data`，失败含 `success: false` 与 `error.code`、`error.message`。

#### Scenario: 同时调用两个方法

- **WHEN** 页面同时调用照片选择和日历写入，原生返回顺序与发起顺序不同
- **THEN** 两个 Promise 各自只得到一次对应请求的最终结果，错误可由 SDK 根据稳定错误码处理。

#### Scenario: 请求不合法

- **WHEN** 方法不存在、协议主版本不兼容或参数类型错误
- **THEN** 调用方得到可区分的协议错误，原生操作尚未执行。

### Requirement: 宿主验证项目和会话

Dispatcher SHALL 从原生持有的页面会话确定调用者及来源，对每次请求验证身份和权限。事件和响应仅投递给当前有效会话的原订阅者。

#### Scenario: A 的订阅在 B 启动后收到迟到事件

- **WHEN** 用户从 A 切换到 B，此时 A 的定位事件或 RPC 响应返回
- **THEN** B 收不到 A 的数据，宿主注销 A 的订阅并丢弃失效响应。

### Requirement: 超时、取消与资源释放

桥接层 SHALL 支持超时、取消单次请求、订阅及退订事件。取消、超时和会话销毁均须终止投递、释放相关资源，并在底层允许时取消原生工作。

#### Scenario: 取消与原生完成同时到达

- **WHEN** 项目取消一个传输请求，底层同时报告完成
- **THEN** 调用只出现一个最终结果，释放回调和临时资源，后续事件不再发送到该请求。
