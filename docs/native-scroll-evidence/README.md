# iPhone 顶部的滚动内容与系统导航标题

深色场景由 iPhone 17 模拟器的 `simctl io screenshot` 截取，包含系统状态栏。设备运行 iOS 27.2，画面为 402 × 874 pt、1206 × 2622 px，窗口顶部安全区为 62 pt。各图保留原始尺寸与颜色配置。

项目只使用现有的 Theme、两个普通 Tab、Screen、ScrollView、文本和输入框。深色页面为 `#204858`，滚动标题的背景标记为 `#509090`。自绘标题场景从静止位置上移 50 pt，声明了 Screen.title 的场景上移 200 pt。

| 完整显示器截图 | 构建 14 | 构建 15 |
| --- | --- | --- |
| 自绘标题在顶端 | [原图](14-Tabs-Rest.png) | [原图](15-Tabs-Rest.png) |
| 自绘标题经过状态栏 | [原图](14-Tabs-Scrolled.png) | [原图](15-Tabs-Scrolled.png) |
| Screen.title 在顶端 | [原图](14-Titled-Rest.png) | [原图](15-Titled-Rest.png) |
| Screen.title 在上滑后 | [原图](14-Titled-Scrolled.png) | [原图](15-Titled-Scrolled.png) |
| 浅色主题的首屏（iPhone 17e） | [原图](14-Light-Opened.png) | [原图](15-Light-Opened.png) |

构建 14 的标签控制器、选中页和滚动视图都从窗口 y=62 pt 开始。滚动视图和系统标签容器都在这里裁剪，孩子收到的顶部安全区为 0。去掉 TabView，同一滚动视图的窗口起点为 y=0，顶部内容内距为 62 pt，标题能经过时间后方。[无标签对照原图](14-Plain-Scrolled.png) · [构建 14 图层与动作记录](https://github.com/chkf/void/actions/runs/44731898024/job/136273517184)

| 自绘标题上移 50 pt 后的 sRGB 背景样本 | x=297.5、y=16 pt | x=297.5、y=56 pt |
| --- | --- | --- |
| 构建 14，有 Tab | `#204858` | `#204858` |
| 构建 14，无 Tab | `#376B73` | `#4F8F90` |
| 构建 15，有 Tab | `#376B73` | `#4F8F90` |

构建 15 的滚动视图从窗口 y=0 开始，顶部内容内距仍为 62 pt。自绘标题上移时，采样点的颜色经过系统边缘效果混合。拉回顶端后，两处都恢复 `#204858`。[回到顶端的原图](15-Tabs-Returned.png) · [iPhone 17 真实手势的 Release 整屏截图](15-Scroll-Gesture.png)

声明 `Screen.title` 的页面在构建 14 中，滚动前后标题字形都在 x=17…207 pt。构建 15 在顶端时标题字形左边为 17.3 pt，高 29.6 pt。收起时字形高 15 pt，中点在 x=200.5 pt，屏幕中心为 201 pt。系统导航栏收为 54 pt 高。[构建 15 图层与动作记录](https://github.com/chkf/void/actions/runs/44738151381/job/136294685783) · [原始附件](https://github.com/chkf/void/actions/runs/44738151381/artifacts/14630542346)

系统导航标题使用现有 `Screen.title`。项目自己画在滚动内容里的标题保留原文、图标和排列。可用同一发布里的 `safe-area-sample.zip`，分别检查 Sample 和 Settings → Scroll title 两种模式。

浅色对照使用发布样例的 Sample 页，取自 iPhone 17e 的 `XCUIScreen.main.screenshot()`，尺寸均为 1170 × 2532 px。两版在 (281, 24) px 和 (25, 160) px 的 sRGB 都是主题浅色 `#C8E8E0`。[构建 14 原附件](https://github.com/chkf/void/actions/runs/44718077036/artifacts/14621687678) · [构建 15 原附件](https://github.com/chkf/void/actions/runs/44735642890/artifacts/14629996050)

深色对照使用构建 14 的宿主提交 `92d93bb` 和构建 15 的 `5c20999`。对应的截图测试提交为 `ebcc085` 和 `9a925c7`。两组对照都用相同 TSX、设备、滚动距离和坐标。图片包含系统时钟、状态图标和屏幕底部标签栏。在 Mac 的对应诊断提交，运行 `npm ci`、`npm run prepare:ios`、`bash scripts/scroll-edge-probe.sh` 可重做测量。[构建 14 诊断源码](https://github.com/chkf/void/commit/ebcc0856b577bb4246d14d20f0b29153a36b5cc8) · [构建 15 诊断源码](https://github.com/chkf/void/commit/9a925c703328e91c16bf55dc6381662a20263bdc)

## 真机待验

1. 沿用已安装版本的签名团队和实际 Bundle ID，覆盖安装新的 void IPA。在「项目管理 → 宿主信息」记下版本、构建号、设备及 iOS 版本，从最近项目打开原登记。
2. 在独立样例的 Sample 页输入 Draft。停在页首时大标题应完整。缓慢上推，观察标题是否收为居中小标题、列表能否在导航栏后方滚动。再拉回顶端。
3. 在 Settings 点 Scroll title，回到 Sample。缓慢推动自绘标题，确认文字进入时间旁的区域，并确认停在顶端时首行仍完整。对这两个位置各截取整张设备屏幕。
4. 在 Settings 切换标签、主题和外观，返回 Sample 查看 Draft。收放键盘、转为横屏、回到前台，再检查输入和可见状态栏。用本人原项目时，只需安装宿主并重新打开原登记。
