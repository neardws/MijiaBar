<h1 align="center">MijiaBar</h1>
<p align="center">在 macOS 菜单栏控制米家设备，也可以交给 AI Agent 来控制。</p>

<p align="center">
  <a href="https://github.com/neardws/MijiaBar/releases/latest"><img src="https://img.shields.io/github/v/release/neardws/MijiaBar?label=release&color=blue" alt="Release"></a>
  <a href="https://github.com/neardws/MijiaBar/releases"><img src="https://img.shields.io/github/downloads/neardws/MijiaBar/total?color=brightgreen" alt="Downloads"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/neardws/MijiaBar" alt="License"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/Apple-notarized-success?logo=apple" alt="Notarized">
  <a href="https://github.com/neardws/MijiaBar/actions/workflows/build.yml"><img src="https://img.shields.io/github/actions/workflow/status/neardws/MijiaBar/build.yml?branch=main&label=build" alt="Build"></a>
  <a href="https://github.com/neardws/MijiaBar/stargazers"><img src="https://img.shields.io/github/stars/neardws/MijiaBar?style=social" alt="Stars"></a>
</p>

<p align="center"><a href="README.md">English</a> · <b>简体中文</b> · <a href="README.zh-TW.md">繁體中文</a></p>

> 非小米官方项目。使用与米家 App 相同的云端接口和局域网 miIO 协议。

<p align="center"><img src="https://files.neardws.com/mijiabar/readme/demo.gif" width="300" alt="demo"></p>

[功能](#功能) · [截图](#截图) · [安装](#安装) · [登录](#登录) · [默认隐藏规则](#默认隐藏规则) · [摄像头直播](#摄像头直播) · [Agent / MCP](#agent--mcp) · [从源码构建](#从源码构建) · [数据存放](#数据存放) · [致谢](#致谢)

## 功能

- **扫码登录**：用米家 App 扫一扫，无需密码。默认中国大陆服务器，也可切换欧洲、美国、俄罗斯、新加坡、印度。凭据只存在 macOS 钥匙串。
- **自动获取设备**：拉取所有家庭、房间和共享设备及在线状态；离线和久未使用的设备默认隐藏。
- **小屋剖面图**：设备列表顶部的像素风等距小屋，组合布局呈现房间里的灯具与家电，点击即可开关已匹配的设备。灯光逐点呈现，昼夜随本地时间切换；点 **放大** 可打开独立小屋窗口。
- **小屋宠物**：最多三只可定制的像素猫狗，可手选配色，或从仅在本机分析的照片生成。
- **每类设备单独设计**：空调、风扇、灯、插座、电视、音箱、摄像机、打印机、厨房电器、净水器、取暖器、除湿机、传感器，各有拟物插画。
- **克制的动效**：无回弹的快速弹簧（< 300ms）；风扇按风速转动、电视屏幕发光、取暖器热浪；电源键涟漪；滑条 1:1 跟手、松手吸附、跨档触控板轻触。遵循「减弱动态效果」。
- **键盘优先**：`↑/↓` 选择、`↩` 打开、`空格` 开关、`←/→` 调节主滑条、`/` 搜索、`Esc` 返回、`⌘Q` 退出。
- **浅色 / 深色**：使用系统语义色，自动跟随外观。
- **支持三种界面语言**：简体中文、繁體中文（台湾用语）、English，按地区推荐默认语言。
- **Agent 接口**：`mijiabar` 命令行和 stdio MCP 服务器，默认只读，可选白名单 / 全部权限，写操作可弹窗确认。
- **双通道控制**：小米云 MIoT RPC，失败时回落局域网 miIO；空调伴侣（`lumi.acpartner.*`）使用旧版局域网命令。

## 截图

<p align="center">
  <img src="https://files.neardws.com/mijiabar/readme/list-light.webp" width="260" alt="">
  <img src="https://files.neardws.com/mijiabar/readme/ac-cool-light.webp" width="260" alt="">
  <img src="https://files.neardws.com/mijiabar/readme/fan-light.webp" width="260" alt="">
</p>
<p align="center"><b>深色模式</b><br>
  <img src="https://files.neardws.com/mijiabar/readme/list-dark.webp" width="260" alt="">
  <img src="https://files.neardws.com/mijiabar/readme/ac-heat-dark.webp" width="260" alt="">
  <img src="https://files.neardws.com/mijiabar/readme/light-dark.webp" width="260" alt="">
</p>
<p align="center">
  <img src="https://files.neardws.com/mijiabar/readme/plug-light.webp" width="260" alt="">
  <img src="https://files.neardws.com/mijiabar/readme/agent-light.webp" width="260" alt="">
  <img src="https://files.neardws.com/mijiabar/readme/login-light.webp" width="260" alt="">
</p>

## 安装

1. 从 [Releases](https://github.com/neardws/MijiaBar/releases/latest) 下载 `MijiaBar-x.y.z.dmg`，把 MijiaBar 拖进「应用程序」后打开。正式版已用 Developer ID 签名并通过 Apple 公证。
2. 第一次控制设备时，请允许「本地网络」权限（局域网直连需要）。

> CI 构建的 `*-unsigned.dmg` 和自己本地打包的版本为 ad-hoc 签名，首次打开前执行 `xattr -dr com.apple.quarantine /Applications/MijiaBar.app`。

系统要求：macOS 14 及以上，支持 Apple 芯片和 Intel。

## 登录

1. 点菜单栏的 🏠 图标，会显示二维码。
2. 选择服务器地区（默认中国大陆）。
3. 打开手机 **米家 App** →「+」→「扫一扫」，扫码并在手机上确认，设备会自动加载。

## 默认隐藏规则

满足任一条件的设备默认收起到列表底部：

- 云端报告离线（`isOnline = false`）；
- 云端返回了最后在线时间（`last_online` / `lastOnline` / `last_online_time`），且超过 30 天。

点眼睛按钮或「显示」可以展开，也可以在 **设置 → 设备管理 → 显示已隐藏的设备** 中打开。右键设备可以手动「隐藏 / 取消隐藏」，手动设置始终优先于自动规则。

## 摄像头直播

- 摄像机和门铃的详情卡片里有 **看直播** 按钮：画面直接在卡片里播放，点放大按钮可以弹出可调整大小的独立窗口。
- 播放由内置的 [go2rtc](https://github.com/AlexxIT/go2rtc)（MIT，官方发布包，构建时校验 SHA-256）完成，只在观看时运行：只监听 `127.0.0.1` 的随机端口，关闭 RTSP / WebRTC / HomeKit（mDNS），只开放播放器和 `/api/ws`；关闭画面 20 秒后停止，完全退出 MijiaBar 时结束。
- 登录复用扫码会话：MijiaBar 把扫码登录返回的 `passToken` 存在钥匙串，通过临时的 `go2rtc.yaml`（权限 600，go2rtc 读入后立即删除）交给 go2rtc。v0.1.8 之前的登录需要再扫一次码（**设置 → 摄像头直播**）。
- 每次连接都会向小米云获取密钥，视频经小米 P2P 从摄像头传来，不做任何录制。电池门铃会被唤醒、耗电更快，请尽量短时间观看。Agent / MCP 无法访问摄像头。
- 设备详情页标题（以及列表行上的小图标）显示最近一次读取/控制走的通道：**局域网**（miIO 直连）、**云端**（回退）或 **蓝牙网关**。
- 离家检测：比较 Mac 当前网卡子网和设备的局域网 IP（网络变化时重新判断，不保存任何网络信息）。不在家时跳过局域网直接走云端，摄像头卡片提示只能在家里看直播。

<p align="center">
  <img src="https://files.neardws.com/mijiabar/readme/camera-live-light.webp" width="260" alt="">
  <img src="https://files.neardws.com/mijiabar/readme/doorbell-live-dark.webp" width="260" alt="">
</p>

## Agent / MCP

打开 **设置 → Agent 接口**，点 **复制安装说明**，粘贴给 Claude Code、Codex、Cursor 等 Agent。Agent 会自己找到内置 CLI、在自己的配置里注册 MCP 服务器，并列出设备完成验证。`mijiabar setup-prompt` 会输出同样的内容（路径已填好）：

```text
请阅读 https://raw.githubusercontent.com/neardws/MijiaBar/main/docs/AGENT_SETUP.zh-CN.md ，按其中的步骤把 MijiaBar 接入为你的 MCP 工具。
CLI 路径：/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar
未经我同意，不要改变任何设备的状态。
```

写给 Agent 的完整步骤： [docs/AGENT_SETUP.zh-CN.md](docs/AGENT_SETUP.zh-CN.md)

### 权限

| | |
| --- | --- |
| 关闭 | Agent 什么都不能做 |
| 只读（默认） | 只能列设备、读状态 |
| 白名单 | 只能控制你勾选的设备 |
| 全部 | 可以控制所有设备 |

开启 **每次写操作弹窗确认** 后，Agent 的每次控制都会弹出系统对话框，需要你点「允许」。

### 命令行

```bash
mijiabar list                     # list devices (--all, --refresh)
mijiabar get <device>             # read state as JSON
mijiabar set <device> <prop> <value>
mijiabar action <device> <action> [JSON array]
mijiabar mcp                      # stdio MCP server
mijiabar setup-prompt             # print the agent setup instructions
```

MCP 工具：`list_devices`、`get_device_state`、`set_property`、`run_action`。

## 从源码构建

```bash
git clone https://github.com/neardws/MijiaBar && cd MijiaBar
swift build
.build/debug/MijiaBarApp --snapshot docs/screenshots   # demo-data screenshots
scripts/package.sh   # dist/MijiaBar.app + DMG (signs & notarizes when a Developer ID is available)
# env: VERSION, SIGN_IDENTITY ("-" = ad-hoc), NOTARY_PROFILE (default MijiaBar-notary)
```

项目结构：`Sources/MijiaCore`（云端 API、扫码登录、miIO、MIoT 规格）、`Sources/MijiaBarApp`（SwiftUI 应用）、`Sources/mijiabar`（CLI + MCP）。翻译在 `i18n/*.tsv`，修改后运行 `scripts/gen-i18n.py`。

## 数据存放

- 登录凭据：macOS 钥匙串，服务名 `com.neardws.MijiaBar`（账户 `session`），退出登录即删除。
- 设备缓存 `devices.json`、偏好 `prefs.json`（收藏、别名、隐藏、地区）、Agent 权限 `agent.json`、MIoT 规格缓存 `spec-index.json` 和 `specs/<型号>.json`，都在 `~/Library/Application Support/MijiaBar/`，文件权限 600。
- 界面语言：UserDefaults 的 `MijiaBarLang`（App 和 CLI 共用，环境变量 `MIJIABAR_LANG` 可覆盖）。
- 除了小米服务器、局域网内的设备和 miot-spec.org（下载公开规格）之外，不向任何地方发送数据。

## 致谢

动效设计由 [@skyswordw](https://github.com/skyswordw) 贡献（[#1](https://github.com/neardws/MijiaBar/pull/1)）。协议细节参考 [python-miio](https://github.com/rytilahti/python-miio)、[Xiaomi-cloud-tokens-extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) 和 [ha_xiaomi_home](https://github.com/XiaoMi/ha_xiaomi_home)。界面灵感来自 [@the_mcnaveen](https://x.com/the_mcnaveen) 的空调菜单栏应用。

MIT 许可证。
