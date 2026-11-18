# 文件与访问边界

| 位置 | 内容与访问者 |
| --- | --- |
| Files 中的 app/、assets/、modules/ 和 runtime.json | 用户、获权编辑器和宿主共享。宿主通过协调读取生成构建快照。 |
| 项目 data/、logs/ | 留给用户共享的数据与诊断。修改这些目录不会改变源码修订或进入发布资源表。 |
| 宿主 Application Support/void/projects.json | 目录书签、宿主分配的 UUID、目录身份与最近选择，只供宿主访问。 |
| 宿主 Application Support/void/Builds/ | 按 UUID 存储的已确认产物与恢复指针。 |

Files 选择器返回的目录需要由每个应用独立授权。宿主保存系统书签，在每次协调访问后释放授权。文件服务商撤销访问或书签过期时，从「管理 → 重新授权文件夹」选择原目录。登记按目录身份核对。[Apple 目录授权](https://developer.apple.com/documentation/uikit/providing-access-to-directories)

可用同名副本验证隔离。复制完整目录后，保留原 id 导入会报告身份冲突。将副本的 id 改为新的唯一值并重新导入，两个目录会分别登记。构建扫描拒绝符号链接。回环资源服务只接受当前发布表中的路径。
