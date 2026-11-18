# 项目格式

新建项目以随 IPA 分发的 [StarterProject](../ios/StarterProject) 为模板。创建时宿主生成独立的 `runtime.json` 项目标识，并建立 `assets/`、`modules/`、`data/` 和 `logs/`。可从「项目 → 创建项目」完成同样的操作。

`runtime.json` 使用 `formatVersion: 1` 和非空字符串 `id`。复制项目用作独立应用时，需更换 id。重命名在 `app/manifest.json` 修改 name，与数据身份独立。

| app/manifest.json 字段 | 约定 |
| --- | --- |
| name、version | 展示名称与项目版本 |
| uiMode | 新项目为 native。已有 HTML 项目可指定 web，或省略此字段。 |
| entry | 相对 app/ 的入口，如 src/main.tsx 或 index.html |
| permissions | 项目希望申请的能力名称数组 |

`app/package.json` 的 dependencies 使用确切版本。模板使用 React 18.3.1 与 @runtime/ui 1.0.0。现有 HTML 项目至少包含 `app/manifest.json` 与其有效的 HTML 入口。

`app/` 存源码，`assets/` 存资源，`modules/` 存本地模块。私有登记、已运行的产物、共享数据与日志分别按[文件边界](FILESYSTEM.md)处理。
