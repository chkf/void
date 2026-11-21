# 文件与访问边界

| 位置 | 内容与访问者 |
| --- | --- |
| Files 中的 app/、assets/、modules/ 和 runtime.json | 用户、获权编辑器和宿主共享。宿主通过协调读取生成构建快照。 |
| 项目 data/、logs/ | 留给用户共享的数据与诊断。修改这些目录不会改变源码修订或进入发布资源表。 |
| 宿主 Application Support/void/projects.json | 目录书签、宿主分配的 UUID、目录身份与最近选择，只供宿主访问。 |
| 宿主 Application Support/void/Builds/ | 按 UUID 存储的已确认产物与恢复指针。 |

打开既有项目会先恢复原目录。Void 自己的文稿使用相对于本次安装 Documents 的位置，外部目录使用系统授予的书签，可恢复的过期书签会自动更新。宿主核验目录标识和已登记的项目 ID。目录标识发生变化时，只有原位置和 runtime.json 的原 ID 同时匹配才更新登记。已有项目沿用宿主 UUID、权限、构建历史和数据库。[Apple 目录授权](https://developer.apple.com/documentation/uikit/providing-access-to-directories)

宿主在同一次目录协调中直接读取 app/manifest.json 和它声明的入口。其余源码以实际子目录名构成相对键，扫描 app/、assets/ 和 modules/。点号开头的临时项会跳过，普通文件名即使带隐藏属性也会读取。遇到读取拒绝、文件未下载、JSON 损坏或路径含符号链接时，界面会显示对应阶段和原因。

目录诊断由宿主在后台记录。Agent 可在模拟器的统一日志中按子系统和类别查询，也可从导出的应用数据容器读取 `Library/Preferences/<实际 Bundle ID>.plist` 的 `void.directoryDiagnostics.v1`。该键保存最近 180 条事件的 JSON 数据，重启后仍可读取。

```sh
xcrun simctl spawn booted log show --last 15m --info --predicate 'subsystem == "app.chkf.void" AND category == "directory"'
```

按同一请求 ID 查找 `picker.present`、`picker.didPick`、`picker.dismiss`，可依次核对选择器显示、收到选择回调和关闭的时间。随后查看 `grant.begin`、`grant.accessor`、`scan.begin`、`scan.end` 和最终结果。每条记录含耗时，失败时保留系统错误域和代码。选择回调记录数量和目录末级名。[测试脚本的读取示例](../scripts/ios-build.sh)

每次目录读取操作最多等待 20 秒。「取消」和超时都会调用系统文件协调器的取消方法。已经进入服务商读取的工作可以晚些返回，宿主会丢弃过期结果。[Apple 文件协调取消语义](https://developer.apple.com/documentation/foundation/nsfilecoordinator/cancel())

脚本通过 `ios.fs` 访问自己项目的数据。`data/` 对应项目的共享数据，`project/` 对应获准的项目文件夹，`private/` 和 `cache/` 分别对应按项目 UUID 区分的私有文件及缓存。宿主书签、其他项目和钥匙串使用各自独立的存储。SQLite 使用 `ios.graphics.execute/query/transaction`，移除最近记录不影响项目的数据库。[文件 API](SDK_REFERENCE.md#文件)

可用同名副本验证隔离。复制完整目录后，保留原 id 导入会报告身份冲突。将副本的 id 改为新的唯一值并重新导入，两个目录会分别登记。构建扫描拒绝符号链接。回环资源服务只接受当前发布表中的路径。
