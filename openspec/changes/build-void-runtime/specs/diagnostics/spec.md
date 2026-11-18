# Spec Delta

## Purpose

外部 Agent 仅取得项目目录的访问权，也应能够找到一次构建或调用失败的原因。诊断把用户看到的版本与源码、错误、耗时及恢复结果对应起来，协助完成下一次修改。

## ADDED Requirements

### Requirement: 提供项目可读的日志

宿主 SHALL 在每个项目的 `logs/` 提供 `console.log`、`javascript-errors.json`、`native-errors.json`、`runtime-events.json`、`build-errors.json` 和 `performance.json`。记录含适用的时间、项目、构建、严重性、文件位置和请求 ID，并对敏感内容脱敏。

#### Scenario: 外部 Agent 定位两次不同版本的异常

- **WHEN** 两个版本的同一页面先后抛出 JavaScript 异常并有一次原生请求失败
- **THEN** Agent 直接读取项目日志即可区分版本，按各自 Source Map 取得源文件、行列和堆栈，并按请求 ID 找到原生错误。日志读写不触发业务重建。

### Requirement: 查询状态、性能与恢复操作

宿主 SHALL 提供项目和 Runtime 状态、页面信息、最近日志、构建与原生及 JS 错误、RPC 跟踪、加载耗时和可测内存指标的查询，并支持刷新、重启及恢复上个可运行版本。

#### Scenario: 页面无法完成启动

- **WHEN** 新页面在启动过程中终止，Agent 或用户从宿主查询错误并选择恢复
- **THEN** 宿主返回失效版本、可取得的错误和加载阶段，恢复操作的结果及恢复后的活动版本均可查询。
