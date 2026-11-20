# TSX 原生界面

构建 11 在 iOS / iPadOS 17 及以上提供两个精确的 UI 依赖版本。应用在 `app/package.json` 声明 React 18.3.1 和所需的 `@runtime/ui` 版本，入口使用 `render(<App />)`。离线构建器按声明选择类型和渲染协议。项目模板继续演示 1.0.0。[完整类型](../runtime/ui.d.ts) · [1.0.0 类型](../runtime/ui-1.0.d.ts) · [可直接导入的示例目录](../examples/native-ui)

| 依赖 | 宿主行为 |
| --- | --- |
| `1.0.0` | 原组件、原属性、系统外观，使用协议 1。新版宿主也支持在表单中放置 `ProjectManagementButton`。旧产物缺省协议号按 1 解码。原目录、项目登记和授权继续使用。 |
| `1.1.0` | 使用下表的属性和协议 2。dev.10 从源码构建会报缺少锁定依赖 `@runtime/ui@1.1.0`。已编译的新版 renderer 在旧宿主调用 render 时报告需要升级宿主。 |
| 其他版本、范围、标签 | 编译器报告不兼容。SDK 的精确版本规则独立于 UI。 |

## 从两个标签开始

```tsx
import { useState } from "react";
import { render, Theme, TabView, Tab, Screen, ScrollView, Card, Text } from "@runtime/ui";

function App() {
  const [tab, setTab] = useState("sample");
  return <Theme mode="system" light={{ accent: "#304C68" }} dark={{ accent: "#B8D5EF" }}>
    <TabView selection={tab} onChange={setTab}>
      <Tab id="sample" title="示例" systemName="square.grid.2x2">
        <Screen title="示例"><ScrollView><Card><Text value="内容" font="headline" /></Card></ScrollView></Screen>
      </Tab>
      <Tab id="other" title="其他" systemName="circle">
        <Screen title="其他"><Text value="另一页" /></Screen>
      </Tab>
    </TabView>
  </Theme>;
}
render(<App />);
```

独立示例可在「导入文件夹」中选择整个 `native-ui` 目录。示例包含两个初始页，在「设置」中可添加第三页、切换主题或打开「项目管理」。输入框、计数和选择仅保存在 React 内存中。示例未声明权限，也没有 SDK 调用。IPA 内同时附带 `Toolchain/NativeUIDemo`、`Toolchain/ui.d.ts` 和 `Toolchain/native-ui.md`。

## 组件契约

下表列出全部公开属性。容器另接受 React `children`。事件处理函数留在 JS 会话内。所有尺寸单位为 pt，数值必须有限。省略可选属性或传 `undefined` 会采用默认值。

| 组件 | 必填 | 可选与默认 |
| --- | --- | --- |
| Theme | — | `mode` 为 system（默认）、light、dark。`light`、`dark` 各为一层语义色表，缺项回落到对应模式的默认值。Theme 只可作为唯一根节点。 |
| TabView | `selection: string`、`onChange(id)` | 作为唯一根节点，或 Theme 的唯一直接子节点。只接受 2～5 个直接 Tab，可用数组、Fragment 和条件组合。 |
| Tab | `id`、`title`、`systemName` 均为字符串，至少一个内容节点 | id 唯一，selection 必须存在。id 和图标名最多 128 个 UTF-8 字节，标题最多 256 个，均须非空且无控制字符。 |
| ProjectManagementButton | — | 项目设置中的「项目管理」行，点按后打开宿主面板。支持 UI 1.0.0 和 1.1.0。 |
| Screen | — | 页面根 Screen 的唯一直接子节点为 ScrollView、List 或 Form 时，iPhone 竖屏在顶端展示系统大标题，上滑时收为居中的小标题。省略 `title` 可由滚动内容自行排版标题。iPad 标签页保留页面内标题和系统标签栏。其他布局的标题随动态字号排在内容上方。 |
| ScrollView | — | 原生纵向滚动，可交互式收起键盘。协议 2 拒绝 ScrollView、Form 和 List 互相嵌套或嵌入自身。 |
| Card | — | `background` 默认 surface。`border` 默认无边框，指定颜色后 `borderWidth` 默认 1（0～8）。`cornerRadius`、`padding` 均默认 12（0～64）。 |
| VStack | — | `alignment` 为 leading（默认）、center、trailing。`spacing` 为 0～128，省略使用系统间距。 |
| HStack | — | `alignment` 为 top、center（默认）、bottom、firstTextBaseline、lastTextBaseline。`spacing` 同 VStack。 |
| Spacer | — | 沿栈主轴伸展。`minLength` 为 0～256，默认系统最小间距。 |
| Text | `value: string` | `font` 可选 largeTitle、title、title2、title3、headline、subheadline、body、callout、footnote、caption、caption2。`weight` 可选 light、regular、medium、semibold、bold、heavy。缺省继承系统字体与字重。`color` 继承当前文字色。`alignment` 支持 leading、center、trailing，显式设置会占用可用行宽。`monospacedDigits` 默认 false。 |
| Image | `systemName`、`label` | SF Symbol 不可用时显示 questionmark.circle。协议 2 的名称上限 128 字节，朗读标签必填且上限 256 字节。`size` 为 1～128，随 Dynamic Type 缩放，缺省跟随环境字体。`color` 为语义色。 |
| Button | `label: string`、`onPress()` | `icon` 为可选 SF Symbol（上限 128 字节，同一回退图标），朗读使用按钮文字。`variant` 为 primary、secondary、plain、destructive，省略使用原生自动样式。`disabled`、`fullWidth` 默认 false。 |
| ProgressView | `value: number` | `total` 默认 1，须满足 0 ≤ value ≤ total ≤ 10⁹ 且 total > 0。`label` 为可选文字。 |
| Form、List | — | `appearance` 为 system 或 themed。显式 Theme 下默认 themed，使用 background 和 surface。其余情况默认系统列表外观。 |
| Section | `title: string` | 使用原生分组标题。 |
| TextField | `label: string`、`value: string`、`onChange(value: string)` | 原生受控输入，宿主跟踪待确认的输入。 |
| Toggle | `label: string`、`value: boolean`、`onChange(value: boolean)` | 原生开关。 |
| Picker | `label: string`、`options: string[]`、`value: string`、`onChange(value: string)` | 使用系统选择器。 |

## 颜色与继承

色表只接受下列九个键，值为不透明 sRGB `#RRGGBB`，十六进制字母大小写均可。组件颜色属性引用语义键名。Theme 的环境只传给当前项目的原生内容。宿主管理工具和权限弹窗使用宿主环境。

| 角色 | 浅色默认 | 深色默认 |
| --- | --- | --- |
| accent、text | 系统 label | 系统 label |
| background、onAccent | 系统 systemBackground | 系统 systemBackground |
| surface | 系统 secondarySystemBackground | 系统 secondarySystemBackground |
| secondaryText | #55565A | #B8B8BE |
| success | #21633A | #83D59D |
| warning | #784900 | #F0C674 |
| error | #A32324 | #FFA5A7 |

原生测试计算默认正文、次要文字、语义色与两种背景的 WCAG 对比度，以及 onAccent 与 accent 的对比度，阈值 4.5:1。自定义色表的对比度取决于应用所选的颜色组合。图标可沿用这些文字角色。

## 标签生命周期与宿主布局

React 首次提交时挂载全部 Tab 的子树，原生为每个稳定 id 持有一个 UIHostingController。子视图的具体装载时机由 UIKit 和 SwiftUI 决定，系统标签栏控制器呈现当前页。离开页保留控制器、SwiftUI 状态与滚动视图，切换时结束离开页的编辑并移出其辅助功能遍历。标签自身的直接子内容可使用自定义 React 组件。动态调整顺序保留相同 id 的状态；实际移除 id 会卸载该页，再加回时重新初始化。删除当前页时，在同一次 React 提交中给出有效的新 selection。应用根组件和项目 WKWebView 的生命周期跨标签共享。

系统点击先更新当前页，并携带显示修订和递增序列发往 React。宿主等对应的 React 确认后再采用受控值，应用可以拒绝选择。程序设置 selection 不会再触发 onChange。桥上最多一份 ui.commit 在途，忙时合并，保留当前和前一修订的回调。禁用按钮同时受原生控件与事件分发校验。

iPhone 使用系统底部标签栏。iPad 上的位置与形态由当前 iPadOS 和窗口尺寸决定。项目内容遵循原生安全区、键盘和旋转布局。构建时可在进度旁取消。[Apple 标签栏控制器](https://developer.apple.com/documentation/uikit/uitabbarcontroller) · [iPad 标签栏](https://developer.apple.com/documentation/uikit/elevating-your-ipad-app-with-a-tab-bar-and-sidebar)

在应用自己的设置页中，从 `@runtime/ui` 导入 `ProjectManagementButton`，然后在已有分组中写入 `<ProjectManagementButton />`。例如五标签应用可将它放入「我的 → 设置」。标签栏完全按项目声明呈现。旧项目已有的「设置」分组或设置标签也可继续承载管理行。项目的 `Theme` 背景色延伸至状态栏后方，标题和控件保留系统安全间距。[完整设置示例](../examples/native-ui/app/src/main.tsx)

单帧根深度为 0，最大深度 128。保留 16,384 项及 4 MiB UTF-8 文本的上限。协议 2 的属性、色表条目、控件和 Picker 选项均计入项数，属性名、色表键值、节点 ID 和字符串值计入文本预算。宿主直接在后台解码 WebKit 的 Foundation 值。非法树会显示诊断，已有可运行版本沿用原恢复流程。
