# Native SDK 1.1.0

在 TSX 中从 `@runtime/sdk` 导入 `ios`。新项目已经声明依赖。旧项目在 `app/package.json` 的 `dependencies` 中加入 `"@runtime/sdk": "1.1.0"`。每项方法的参数与返回类型见 [TypeScript 定义](../runtime/sdk.d.ts)。新建的 TSX 项目也随附 `SDK_REFERENCE.md` 和 `types/runtime-sdk.d.ts`。

## 调用与权限

调用返回 Promise。`success: true` 时读取 `data`，失败时读取 `error.code` 和 `error.message`。项目将所需权限写入 `app/manifest.json` 的 `permissions` 数组，宿主会在首次使用时询问，系统按需另行授权。用户可在「管理 → 权限声明」中更改选择。需要网络的项目另填 `networkHosts`，使用精确域名。

```tsx
import { ios } from "@runtime/sdk";

export async function saveNote() {
  const path = "data/note.txt";
  const saved = await ios.fs.writeFile({ path, data: "下次打开还在" });
  if (saved.success) {
    const note = await ios.fs.readFile({ path });
    if (note.success) console.log(note.data);
  }
}
```

以上调用需要 `files.read` 和 `files.write`。`data/` 对应「文件」中的项目共享数据，`project/` 对应该项目的获准根目录，`private/` 和 `cache/` 分别对应该项目的宿主私有存储与可清理缓存。移除最近记录后，重新导入原目录仍使用同一项目身份。

绝大多数调用的第二个参数接受 `{ signal, timeoutMs }`。常规请求默认两分钟超时。长时间的选择或转码可以显式调整时限。`ios.onEvent(fn)` 监听本页面的 `{ id, type, data }`，返回本地退订函数。`ios.stop(id)` 停止原生订阅，关闭项目会释放所属会话。日期范围用带时区的 ISO 8601 字符串。

常见错误包括 `INVALID_PARAMS`、`NOT_DECLARED`、`PERMISSION_DENIED`、`NOT_FOUND`、`UNAVAILABLE`、`BUSY`、`TOO_LARGE`、`TIMEOUT` 和 `CANCELLED`。系统授权、硬件或签名未满足时，保留原生错误说明。

## 文件

文件名按 UTF-8 处理。readFile 和 writeFile 的默认编码为 utf8，二进制可用 base64。较大文件用 readChunk、writeChunk 的 offset 和 length 分块，每次最多 4 MiB。列表和 stat 的 modified 是 Unix 秒。pick 与 importFile 通过系统文件选择器把副本存入项目。watch 返回订阅标识。

调用形式为 `ios.fs.readFile({ path: "data/note.txt" })`。

| 权限 | `ios.fs` 方法 |
| --- | --- |
| `files.read` | `readFile`、`readChunk`、`readdir`、`stat`、`exists`、`watch` |
| `files.write` | `writeFile`、`appendFile`、`writeChunk`、`deleteFile`、`copyFile`、`moveFile`、`mkdir` |
| `files.pick` | `pick`、`importFile` |
| `files.share` | `exportFile`、`share` |

## 照片与视频图库

pick 使用系统照片选择器，所选媒体复制到 data/Media。asset 可读取元数据，并可用 to 导出当前可见资源。图库读取、仅添加和有限图库访问分别按系统状态处理。

调用形式为 `ios.photos.pick({ mediaTypes: ["image"], multiple: true })`。

| 权限 | `ios.photos` 方法 |
| --- | --- |
| 项目基础能力 | `authorization` |
| `photos.pick` | `pick` |
| `photos.read` | `requestAccess`、`asset`、`thumbnail` |
| `photos.write` | `save` |

## 相机

open 在项目顶部显示 AVFoundation 实时预览。前后摄像头、闪光、归一化对焦点和曝光偏移按设备检查。录像默认无声，需要声音时传 microphone 并声明 audio.record。保存路径从 capturePhoto 或 stopRecording 返回。

调用形式为 `ios.camera.open({ position: "back" })`。

| 权限 | `ios.camera` 方法 |
| --- | --- |
| 项目基础能力 | `authorization`、`available` |
| `camera` | `open`、`switchCamera`、`configure`、`capturePhoto`、`startRecording`、`stopRecording`、`close` |

## 音频

使用 AVAudioSession、AVAudioRecorder 与 AVAudioPlayer。录音写入 AAC/M4A。pause 和 resume 可指定 playback 或 recording。volume 控制项目播放器音量，watchRoute 在音频路由变化时发送事件。

调用形式为 `ios.audio.play({ path: "data/voice.m4a" })`。

| 权限 | `ios.audio` 方法 |
| --- | --- |
| 项目基础能力 | `authorization` |
| `audio.record` | `record`、`stopRecording` |
| `audio.play` | `play`、`pause`、`resume`、`stop`、`volume`、`info`、`session`、`route`、`watchRoute` |
| `files.pick` | `importFile` |
| `files.share` | `exportFile` |

## 视频

AVPlayer 在项目内显示原生播放器。play 返回进度订阅标识，seek 单位为秒。thumbnail 按时间截帧，transcode 导出 MP4，导入和导出使用系统文件面板。

调用形式为 `ios.video.info({ path: "data/clip.mov" })`。

| 权限 | `ios.video` 方法 |
| --- | --- |
| `video` | `play`、`pause`、`resume`、`seek`、`stop`、`info`、`thumbnail`、`transcode` |
| `files.pick` | `importFile` |
| `files.share` | `exportFile` |

## 位置与航向

current 返回坐标、精度、时间等，watch 和 heading 返回订阅标识。accuracy 根据设备及系统选择的精确或大致位置生效。项目在前台使用位置服务，地理编码由系统处理。

调用形式为 `ios.location.current({ accuracy: "hundredMeters" })`。

| 权限 | `ios.location` 方法 |
| --- | --- |
| 项目基础能力 | `authorization` |
| `location.whenInUse` | `current`、`watch`、`heading`、`geocode`、`reverseGeocode` |

## 日历

日期使用带时区的 ISO 8601 字符串。创建事件可申请系统的仅写入权限。查询、按 ID 更新和删除已有事件需要完整系统访问；更新和删除还需声明 calendar.read。

调用形式为 `ios.calendar.listCalendars()`。

| 权限 | `ios.calendar` 方法 |
| --- | --- |
| 项目基础能力 | `authorization` |
| `calendar.read` | `listCalendars`、`events` |
| `calendar.write` | `createEvent`、`updateEvent`、`deleteEvent` |

## 提醒事项

可查询和管理列表、创建和更新提醒、设置完成状态和到期时间。dueDate 传 null 可清空日期。读取设备上当前能访问的提醒列表。

调用形式为 `ios.reminders.list({ limit: 20 })`。

| 权限 | `ios.reminders` 方法 |
| --- | --- |
| 项目基础能力 | `authorization` |
| `reminders` | `lists`、`list`、`create`、`update`、`remove`、`createList`、`updateList`、`deleteList` |

## 联系人

按姓名搜索或按 ID 取详情，可读写名字、组织、电话、邮件。设备仅允许访问部分联系人时，接口返回系统可见的记录。

调用形式为 `ios.contacts.search({ name: "陈", limit: 20 })`。

| 权限 | `ios.contacts` 方法 |
| --- | --- |
| 项目基础能力 | `authorization` |
| `contacts.read` | `search`、`get` |
| `contacts.write` | `create`、`update`、`remove` |

## 本地通知

schedule 支持立即、延迟和指定时间。重复间隔至少 60 秒，at 与 repeats 组合为每日重复。类别、待发送通知、取消和点击结果按项目隔离。responses 在项目重新打开后取得此前点击；默认读后清除。

调用形式为 `ios.notifications.pending()`。

| 权限 | `ios.notifications` 方法 |
| --- | --- |
| 项目基础能力 | `authorization` |
| `notifications` | `request`、`schedule`、`cancel`、`pending`、`categories`、`setCategories`、`responses` |

## 蓝牙 GATT

扫描返回订阅标识，bluetooth.device 事件给出设备 ID。连接后按服务、特征逐层发现，再读写或订阅。特征值以 base64 表示。停止订阅或断开连接可释放资源。需要蓝牙开启和对应外设。

调用形式为 `ios.bluetooth.scan({ services: ["180F"] })`。

| 权限 | `ios.bluetooth` 方法 |
| --- | --- |
| 项目基础能力 | `authorization` |
| `bluetooth` | `state`、`scan`、`connect`、`disconnect`、`services`、`characteristics`、`read`、`write`、`subscribe` |

## NFC

在支持的 iPhone 上由系统显示近场会话。可读取 NDEF 记录、容量和可写状态，并可向可写 NDEF 标签写入文本、URI 或 NDEF 数据。用户可从系统面板取消。

调用形式为 `ios.nfc.read()`。

| 权限 | `ios.nfc` 方法 |
| --- | --- |
| 项目基础能力 | `available` |
| `nfc` | `read`、`write` |

## 健康数据

支持步数、心率、睡眠、活动能量、锻炼分钟、运动记录和活动摘要。数据类型名见 HealthType。数量单位分别用 count、count/min、kcal 或 min。系统只公开写入状态，读取授权返回 notDisclosed，查询返回可见样本。需要 HealthKit 签名能力。

调用形式为 `ios.health.query({ type: "steps", startDate, endDate })`。

| 权限 | `ios.health` 方法 |
| --- | --- |
| 项目基础能力 | `available`、`types`、`authorization` |
| `health.read` | `authorizeRead`、`query` |
| `health.write` | `authorizeWrite`、`write` |

## 家庭

先列出获准访问的家庭，再查配件、服务、特征和场景。读取、修改和订阅特征前会检查对应属性。场景由 HomeKit 执行，配件必须可达。需要 HomeKit 签名能力。

调用形式为 `ios.home.homes()`。

| 权限 | `ios.home` 方法 |
| --- | --- |
| `home.read` | `homes`、`accessories`、`read`、`scenes`、`subscribe` |
| `home.write` | `write`、`runScene` |

## 钥匙串、生物识别与加密

凭据按项目 UUID 隔离，密钥由宿主生成并保存在钥匙串。encrypt/decrypt 使用 AES-GCM，hash 为 SHA-256，输入二进制用 base64。random 返回系统安全随机字节。authenticate 展示系统生物识别面板。

调用形式为 `ios.security.random({ length: 32 })`。

| 权限 | `ios.security` 方法 |
| --- | --- |
| 项目基础能力 | `random`、`hash`、`setSecret`、`getSecret`、`deleteSecret`、`encrypt`、`decrypt`、`biometricType` |
| `biometrics` | `authenticate` |

## 系统交互

包含设备与电池、外观、剪贴板、分享、文档预览、触感、亮度、方向、通用链接与公开系统设置入口。屏幕方向受当前窗口和设备支持范围约束。

调用形式为 `ios.system.info()`。

| 权限 | `ios.system` 方法 |
| --- | --- |
| 项目基础能力 | `info`、`appearance`、`battery` |
| `clipboard.read` | `readClipboard` |
| `clipboard.write` | `writeClipboard` |
| `system.share` | `share`、`preview` |
| `system.links` | `openURL`、`openSettings` |
| `system.display` | `brightness`、`setBrightness`、`orientation` |
| `system.haptics` | `haptic` |

## 网络

请求使用 URLSession 和系统 TLS 校验。HTTP(S) 与 WebSocket 的主机必须列入清单的 networkHosts，重定向同样检查。ATS 继续生效。支持 GET、POST、PUT、PATCH、DELETE、HEAD、文件上传下载、超时与取消。可传 progressId 接收进度，较大响应使用 download。

调用形式为 `ios.network.request({ url: "https://api.example.com/status" })`。

| 权限 | `ios.network` 方法 |
| --- | --- |
| 项目基础能力 | `status`、`watchStatus` |
| `network` | `request`、`download`、`upload`、`openSocket`、`sendSocket`、`closeSocket` |

上传项目文件还需 `files.read`，下载到项目还需 `files.write`。

## 图形与计算

可检测 Canvas 2D、WebGL、WebGL 2、WebAssembly 和动画。TSX 可将 HTMLCanvasElement 交给 showCanvas，原生控件继续显示在画布下方。可在项目中绘图、动画和可视化。图片信息与缩放转码使用 Image I/O。SQLite 支持参数化 SQL、分页查询和事务，数据库按项目隔离。大文件使用 fs 的分块方法，原生媒体处理见 audio 与 video。

调用形式为 `ios.graphics.query({ sql: "SELECT 1 AS value" })`。

| 权限 | `ios.graphics` 方法 |
| --- | --- |
| 项目基础能力 | `capabilities`、`showCanvas`、`hideCanvas` |
| `graphics` | `imageInfo`、`processImage` |
| `database` | `execute`、`query`、`transaction` |

## 设备和签名

相机、麦克风、航向、蓝牙、NFC、健康或家庭配件的可用性取决于实际设备、系统设置和授予的权限。HealthKit、HomeKit、NFC 还需要开发团队在 App ID 和配置描述文件中启用相应能力。更多说明见[构建与签名](BUILD.md)和[验证记录](LIMITATIONS.md)。
