import os
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import subprocess
import sys
import re
files={'en':'README.md','zh-Hans':'README.zh-CN.md','zh-Hant':'README.zh-TW.md'}
names={'en':'English','zh-Hans':'简体中文','zh-Hant':'繁體中文'}
R='neardws/MijiaBar'
badges=f'''<p align="center">
  <a href="https://github.com/{R}/releases/latest"><img src="https://img.shields.io/github/v/release/{R}?label=release&color=blue" alt="Release"></a>
  <a href="https://github.com/{R}/releases"><img src="https://img.shields.io/github/downloads/{R}/total?color=brightgreen" alt="Downloads"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/{R}" alt="License"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/Apple-notarized-success?logo=apple" alt="Notarized">
  <a href="https://github.com/{R}/actions/workflows/build.yml"><img src="https://img.shields.io/github/actions/workflow/status/{R}/build.yml?branch=main&label=build" alt="Build"></a>
  <a href="https://github.com/{R}/stargazers"><img src="https://img.shields.io/github/stars/{R}?style=social" alt="Stars"></a>
</p>'''
T={}
T['en']=dict(tag="Control your Xiaomi Mi Home devices from the macOS menu bar — and let AI agents do it too.",
note="Unofficial project, not affiliated with Xiaomi. It uses the same cloud API as the Mi Home app plus the LAN miIO protocol.",
toc=["Features","Screenshots","Install","Sign in","Agent / MCP","Build from source","Credits"],
dark="Dark mode",
feat=["**QR sign-in** — scan with the Mi Home app, no password. Mainland China server by default; Europe, US, Russia, Singapore and India are one click away. Credentials stay in the macOS Keychain.",
"**Automatic device list** — all homes, rooms and shared devices with online state. Offline and long-unused devices are hidden by default.",
"**House cutaway** — pixel-art isometric home at the top of the list: tap fixtures (lights, TV or monitor, air conditioner, entry light) to toggle matched devices, with per-fixture lighting instead of lighting the whole room. Separate day and night art follows local time (~6:00–17:59); **Enlarge** opens a dedicated House window.",
"**House pets** — up to three customizable pixel cats; choose a palette or generate one from a photo analyzed only on your Mac.",
"**A page designed for each device type** — air conditioner, fan, light, plug, TV, speaker, camera, printer, kitchen appliances, water purifier, heater, dehumidifier and sensors, each with its own skeuomorphic illustration.",
"**Restrained motion** — fast, non-bouncy springs (< 300 ms); fan blades spin with speed, the TV screen glows, heaters radiate; the power button ripples; sliders track 1:1, snap and tick the trackpad. Reduce Motion is respected.",
"**Keyboard first** — `↑/↓` select, `↩` open, `Space` power, `←/→` adjust the main slider, `/` search, `Esc` back, `⌘Q` quit.",
"**Light & dark** — follows the system appearance using semantic colors.",
"**3 UI languages** — English, 简体中文, 繁體中文 (Taiwan wording); region-aware defaults.",
"**Agent interface** — `mijiabar` CLI and a stdio MCP server, read-only by default, with allowlist / full access and optional confirmation dialogs.",
"**Two control paths** — Xiaomi cloud MIoT RPC with LAN miIO fallback; AC partners (`lumi.acpartner.*`) use legacy LAN commands."],
inst=["Download `MijiaBar-x.y.z.dmg` from [Releases](https://github.com/neardws/MijiaBar/releases/latest), drag MijiaBar into Applications and open it. Release DMGs are Developer ID signed and notarized by Apple.",
"The first time you control a device, allow the **Local Network** permission (needed for LAN control)."],
inst_note="CI `*-unsigned.dmg` builds and your own local builds are ad-hoc signed; run `xattr -dr com.apple.quarantine /Applications/MijiaBar.app` before first launch.",
req="Requires macOS 14 or later, Apple silicon or Intel.",
login=["Click the 🏠 icon in the menu bar; a QR code appears.","Pick your server region (Mainland China by default).","In the **Mi Home** app tap **+ → Scan**, scan the code and confirm on the phone. Devices load automatically."],
agent_intro="Open **Settings → Agent interface**, click **Copy setup instructions** and paste the text into Claude Code, Codex, Cursor or any other agent. The agent finds the bundled CLI, registers the MCP server in its own config and verifies by listing your devices. The same text (with the path filled in) is printed by `mijiabar setup-prompt`:",
perm_h="Permissions", perm=[("Off","Agents can do nothing"),("Read (default)","List devices and read state only"),("Allowlist","Control only the devices you tick"),("Full","Control every device")],
confirm="With **Confirm every write** on, every change an agent makes shows a macOS dialog that you must approve.",
cli_h="CLI", tools="MCP tools: `list_devices`, `get_device_state`, `set_property`, `run_action`.",
build_note="Project layout: `Sources/MijiaCore` (cloud API, QR login, miIO, MIoT spec), `Sources/MijiaBarApp` (SwiftUI app), `Sources/mijiabar` (CLI + MCP). Translations live in `i18n/*.tsv`; run `scripts/gen-i18n.py` after editing.",
credits="Motion design contributed by [@skyswordw](https://github.com/skyswordw) ([#1](https://github.com/neardws/MijiaBar/pull/1)). Protocol details from [python-miio](https://github.com/rytilahti/python-miio), [Xiaomi-cloud-tokens-extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) and [ha_xiaomi_home](https://github.com/XiaoMi/ha_xiaomi_home). UI inspired by [@the_mcnaveen](https://x.com/the_mcnaveen)'s AC menu bar app.",
lic="MIT License.")
T['zh-Hans']=dict(tag="在 macOS 菜单栏控制米家设备，也可以交给 AI Agent 来控制。",
note="非小米官方项目。使用与米家 App 相同的云端接口和局域网 miIO 协议。",
toc=["功能","截图","安装","登录","Agent / MCP","从源码构建","致谢"],dark="深色模式",
feat=["**扫码登录**：用米家 App 扫一扫，无需密码。默认中国大陆服务器，也可切换欧洲、美国、俄罗斯、新加坡、印度。凭据只存在 macOS 钥匙串。",
"**自动获取设备**：拉取所有家庭、房间和共享设备及在线状态；离线和久未使用的设备默认隐藏。",
"**小屋剖面图**：设备列表顶部的像素风等距小屋，点场景里的灯具、电视/显示器、空调、玄关灯等即可开关对应设备，每个点位单独亮灯，不会整间屋一起亮。按本地时间切换白天/夜晚底图（约 6:00–17:59）；点 **放大** 可打开独立小屋窗口。",
"**小屋宠物**：最多三只可定制的像素猫，可手选配色，或从仅在本机分析的照片生成。",
"**每类设备单独设计**：空调、风扇、灯、插座、电视、音箱、摄像机、打印机、厨房电器、净水器、取暖器、除湿机、传感器，各有拟物插画。",
"**克制的动效**：无回弹的快速弹簧（< 300ms）；风扇按风速转动、电视屏幕发光、取暖器热浪；电源键涟漪；滑条 1:1 跟手、松手吸附、跨档触控板轻触。遵循「减弱动态效果」。",
"**键盘优先**：`↑/↓` 选择、`↩` 打开、`空格` 开关、`←/→` 调节主滑条、`/` 搜索、`Esc` 返回、`⌘Q` 退出。",
"**浅色 / 深色**：使用系统语义色，自动跟随外观。",
"**支持三种界面语言**：简体中文、繁體中文（台湾用语）、English，按地区推荐默认语言。",
"**Agent 接口**：`mijiabar` 命令行和 stdio MCP 服务器，默认只读，可选白名单 / 全部权限，写操作可弹窗确认。",
"**双通道控制**：小米云 MIoT RPC，失败时回落局域网 miIO；空调伴侣（`lumi.acpartner.*`）使用旧版局域网命令。"],
inst=["从 [Releases](https://github.com/neardws/MijiaBar/releases/latest) 下载 `MijiaBar-x.y.z.dmg`，把 MijiaBar 拖进「应用程序」后打开。正式版已用 Developer ID 签名并通过 Apple 公证。","第一次控制设备时，请允许「本地网络」权限（局域网直连需要）。"],
inst_note="CI 构建的 `*-unsigned.dmg` 和自己本地打包的版本为 ad-hoc 签名，首次打开前执行 `xattr -dr com.apple.quarantine /Applications/MijiaBar.app`。",
req="系统要求：macOS 14 及以上，支持 Apple 芯片和 Intel。",
login=["点菜单栏的 🏠 图标，会显示二维码。","选择服务器地区（默认中国大陆）。","打开手机 **米家 App** →「+」→「扫一扫」，扫码并在手机上确认，设备会自动加载。"],
agent_intro="打开 **设置 → Agent 接口**，点 **复制安装说明**，粘贴给 Claude Code、Codex、Cursor 等 Agent。Agent 会自己找到内置 CLI、在自己的配置里注册 MCP 服务器，并列出设备完成验证。`mijiabar setup-prompt` 会输出同样的内容（路径已填好）：",
perm_h="权限", perm=[("关闭","Agent 什么都不能做"),("只读（默认）","只能列设备、读状态"),("白名单","只能控制你勾选的设备"),("全部","可以控制所有设备")],
confirm="开启 **每次写操作弹窗确认** 后，Agent 的每次控制都会弹出系统对话框，需要你点「允许」。",
cli_h="命令行", tools="MCP 工具：`list_devices`、`get_device_state`、`set_property`、`run_action`。",
build_note="项目结构：`Sources/MijiaCore`（云端 API、扫码登录、miIO、MIoT 规格）、`Sources/MijiaBarApp`（SwiftUI 应用）、`Sources/mijiabar`（CLI + MCP）。翻译在 `i18n/*.tsv`，修改后运行 `scripts/gen-i18n.py`。",
credits="动效设计由 [@skyswordw](https://github.com/skyswordw) 贡献（[#1](https://github.com/neardws/MijiaBar/pull/1)）。协议细节参考 [python-miio](https://github.com/rytilahti/python-miio)、[Xiaomi-cloud-tokens-extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) 和 [ha_xiaomi_home](https://github.com/XiaoMi/ha_xiaomi_home)。界面灵感来自 [@the_mcnaveen](https://x.com/the_mcnaveen) 的空调菜单栏应用。",
lic="MIT 许可证。")
T['zh-Hant']=dict(tag="在 macOS 選單列控制米家裝置，也可以交給 AI Agent 來控制。",
note="非小米官方專案。使用與米家 App 相同的雲端介面和區域網路 miIO 協定。",
toc=["功能","截圖","安裝","登入","Agent / MCP","從原始碼建置","致謝"],dark="深色模式",
feat=["**掃碼登入**：用米家 App 掃一掃，免密碼。預設中國大陸伺服器，也可切換歐洲、美國、俄羅斯、新加坡、印度。憑證只存在 macOS 鑰匙圈。",
"**自動取得裝置**：載入所有家庭、房間和共享裝置及上線狀態；離線和久未使用的裝置預設隱藏。",
"**小屋剖面圖**：裝置清單頂部的像素風等距小屋，點場景裡的燈具、電視/螢幕、冷氣、玄關燈等即可開關對應裝置，每個點位單獨亮燈，不會整間房一起亮。依本機時間切換白天/夜晚底圖（約 6:00–17:59）；點 **放大** 可開啟獨立小屋視窗。",
"**每類裝置單獨設計**：冷氣、電風扇、燈、插座、電視、音箱、攝影機、印表機、廚房電器、淨水器、電暖器、除濕機、感測器，各有擬物插圖。",
"**克制的動態效果**：無回彈的快速彈簧（< 300ms）；風扇依風速轉動、電視螢幕發光、電暖器熱浪；電源鍵漣漪；滑桿 1:1 跟手、放開吸附、跨檔觸控板輕觸。遵循「減少動態效果」。",
"**鍵盤優先**：`↑/↓` 選擇、`↩` 開啟、`空白鍵` 開關、`←/→` 調整主滑桿、`/` 搜尋、`Esc` 返回、`⌘Q` 結束。",
"**淺色 / 深色**：使用系統語意色彩，自動跟隨外觀。",
"**支援三種介面語言**：繁體中文（台灣用語）、简体中文、English，依地區建議預設語言。",
"**Agent 介面**：`mijiabar` 命令列和 stdio MCP 伺服器，預設唯讀，可選白名單 / 全部權限，寫入操作可跳出視窗確認。",
"**雙通道控制**：小米雲端 MIoT RPC，失敗時退回區域網路 miIO；空調夥伴（`lumi.acpartner.*`）使用舊版區域網路指令。"],
inst=["從 [Releases](https://github.com/neardws/MijiaBar/releases/latest) 下載 `MijiaBar-x.y.z.dmg`，把 MijiaBar 拖進「應用程式」後開啟。正式版已用 Developer ID 簽署並通過 Apple 公證。","第一次控制裝置時，請允許「本機網路」權限（區域網路直連需要）。"],
inst_note="CI 建置的 `*-unsigned.dmg` 和自行本機打包的版本為 ad-hoc 簽署，首次開啟前執行 `xattr -dr com.apple.quarantine /Applications/MijiaBar.app`。",
req="系統需求：macOS 14 以上，支援 Apple 晶片和 Intel。",
login=["點選單列的 🏠 圖示，會顯示 QR 碼。","選擇伺服器地區（預設為中國大陸）。","開啟手機 **米家 App** →「+」→「掃一掃」，掃描 QR 碼並在手機上確認，裝置會自動載入。"],
agent_intro="開啟 **設定 → Agent 介面**，點 **複製安裝說明**，貼給 Claude Code、Codex、Cursor 等 Agent。Agent 會自己找到內建 CLI、在自己的設定裡註冊 MCP 伺服器，並列出裝置完成驗證。`mijiabar setup-prompt` 會輸出同樣的內容（路徑已填好）：",
perm_h="權限", perm=[("關閉","Agent 什麼都不能做"),("唯讀（預設）","只能列出裝置、讀取狀態"),("白名單","只能控制你勾選的裝置"),("全部","可以控制所有裝置")],
confirm="開啟 **每次寫入操作跳出視窗確認** 後，Agent 的每次控制都會跳出系統對話框，需要你點「允許」。",
cli_h="命令列", tools="MCP 工具：`list_devices`、`get_device_state`、`set_property`、`run_action`。",
build_note="專案結構：`Sources/MijiaCore`（雲端 API、掃碼登入、miIO、MIoT 規格）、`Sources/MijiaBarApp`（SwiftUI 應用程式）、`Sources/mijiabar`（CLI + MCP）。翻譯在 `i18n/*.tsv`，修改後執行 `scripts/gen-i18n.py`。",
credits="動態效果設計由 [@skyswordw](https://github.com/skyswordw) 貢獻（[#1](https://github.com/neardws/MijiaBar/pull/1)）。協定細節參考 [python-miio](https://github.com/rytilahti/python-miio)、[Xiaomi-cloud-tokens-extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) 和 [ha_xiaomi_home](https://github.com/XiaoMi/ha_xiaomi_home)。介面靈感來自 [@the_mcnaveen](https://x.com/the_mcnaveen) 的冷氣選單列 App。",
lic="MIT 授權。")
import re
S="~/Library/Application Support/MijiaBar/"
X={
'en':("Auto-hidden devices",["A device is collapsed to the bottom of the list by default when either is true:","the cloud reports it offline (`isOnline = false`);","the cloud returns a last-online time (`last_online` / `lastOnline` / `last_online_time`) older than 30 days.","Click the eye button or **Show** to reveal them, or turn on **Settings → Devices → Show hidden devices**. Right-click a device to hide / unhide it manually — a manual choice always overrides the automatic rule."],
 "Where data is stored",["Sign-in session: macOS Keychain, service `com.neardws.MijiaBar` (account `session`). Signing out deletes it.",f"Device cache `devices.json`, preferences `prefs.json` (favorites, aliases, hidden flags, region), agent policy `agent.json`, and MIoT spec cache `spec-index.json` + `specs/<model>.json` — all in `{S}`, written with file mode 600.","UI language: `MijiaBarLang` in UserDefaults (shared by the app and CLI; `MIJIABAR_LANG` overrides it).","Nothing is sent anywhere except Xiaomi's servers, your devices on the LAN, and miot-spec.org (public spec downloads)."]),
'zh-Hans':("默认隐藏规则",["满足任一条件的设备默认收起到列表底部：","云端报告离线（`isOnline = false`）；","云端返回了最后在线时间（`last_online` / `lastOnline` / `last_online_time`），且超过 30 天。","点眼睛按钮或「显示」可以展开，也可以在 **设置 → 设备管理 → 显示已隐藏的设备** 中打开。右键设备可以手动「隐藏 / 取消隐藏」，手动设置始终优先于自动规则。"],
 "数据存放",["登录凭据：macOS 钥匙串，服务名 `com.neardws.MijiaBar`（账户 `session`），退出登录即删除。",f"设备缓存 `devices.json`、偏好 `prefs.json`（收藏、别名、隐藏、地区）、Agent 权限 `agent.json`、MIoT 规格缓存 `spec-index.json` 和 `specs/<型号>.json`，都在 `{S}`，文件权限 600。","界面语言：UserDefaults 的 `MijiaBarLang`（App 和 CLI 共用，环境变量 `MIJIABAR_LANG` 可覆盖）。","除了小米服务器、局域网内的设备和 miot-spec.org（下载公开规格）之外，不向任何地方发送数据。"]),
'zh-Hant':("預設隱藏規則",["符合任一條件的裝置預設收合到清單底部：","雲端回報離線（`isOnline = false`）；","雲端回傳了最後上線時間（`last_online` / `lastOnline` / `last_online_time`），且超過 30 天。","按眼睛按鈕或「顯示」可以展開，也可以在 **設定 → 裝置管理 → 顯示已隱藏的裝置** 中開啟。在裝置上按右鍵可以手動「隱藏 / 取消隱藏」，手動設定一律優先於自動規則。"],
 "資料存放位置",["登入憑證：macOS 鑰匙圈，服務名稱 `com.neardws.MijiaBar`（帳號 `session`），登出即刪除。",f"裝置快取 `devices.json`、偏好設定 `prefs.json`（收藏、別名、隱藏、地區）、Agent 權限 `agent.json`、MIoT 規格快取 `spec-index.json` 和 `specs/<型號>.json`，都在 `{S}`，檔案權限 600。","介面語言：UserDefaults 的 `MijiaBarLang`（App 與 CLI 共用，環境變數 `MIJIABAR_LANG` 可覆寫）。","除了小米伺服器、區域網路內的裝置和 miot-spec.org（下載公開規格）之外，不會將資料傳送到任何地方。"]),
}
LV={
'en':("Live video (cameras)",["Camera and doorbell detail cards have a **Watch live** button: the video plays inline in the card, and the enlarge button pops it out into a resizable window.","It uses the bundled [go2rtc](https://github.com/AlexxIT/go2rtc) (MIT, official release, SHA-256 verified at build time) as a helper that only runs while you watch: it listens on `127.0.0.1` on a random port, has RTSP / WebRTC / HomeKit (mDNS) disabled, exposes only the player and `/api/ws`, stops 20 s after the player closes and is killed when MijiaBar quits.","Sign-in reuses the QR session: MijiaBar keeps the `passToken` returned by the QR login in the Keychain and hands it to go2rtc via a temporary `go2rtc.yaml` (mode 600, deleted as soon as go2rtc has read it). Sessions from before v0.1.8 need one more QR scan (**Settings → Camera live view**).","Stream keys come from the Xiaomi cloud on every connect; video comes from the camera over Xiaomi's P2P. Nothing is recorded. Battery doorbells are woken up and drain faster, so keep it short. Agents / MCP have no camera access.","Each device's detail header (and, subtly, its list row) shows which path the last read/control used: **LAN** (direct miIO), **Cloud** (fallback) or **BLE gateway**.","Away-from-home detection: MijiaBar compares the Mac's network subnets with the devices' local IPs (re-checked on every network change, nothing stored). When you're away it skips LAN attempts and goes straight to the cloud, and camera cards say live view is only available at home."]),
'zh-Hans':("摄像头直播",["摄像机和门铃的详情卡片里有 **看直播** 按钮：画面直接在卡片里播放，点放大按钮可以弹出可调整大小的独立窗口。","播放由内置的 [go2rtc](https://github.com/AlexxIT/go2rtc)（MIT，官方发布包，构建时校验 SHA-256）完成，只在观看时运行：只监听 `127.0.0.1` 的随机端口，关闭 RTSP / WebRTC / HomeKit（mDNS），只开放播放器和 `/api/ws`；关闭画面 20 秒后停止，完全退出 MijiaBar 时结束。","登录复用扫码会话：MijiaBar 把扫码登录返回的 `passToken` 存在钥匙串，通过临时的 `go2rtc.yaml`（权限 600，go2rtc 读入后立即删除）交给 go2rtc。v0.1.8 之前的登录需要再扫一次码（**设置 → 摄像头直播**）。","每次连接都会向小米云获取密钥，视频经小米 P2P 从摄像头传来，不做任何录制。电池门铃会被唤醒、耗电更快，请尽量短时间观看。Agent / MCP 无法访问摄像头。","设备详情页标题（以及列表行上的小图标）显示最近一次读取/控制走的通道：**局域网**（miIO 直连）、**云端**（回退）或 **蓝牙网关**。","离家检测：比较 Mac 当前网卡子网和设备的局域网 IP（网络变化时重新判断，不保存任何网络信息）。不在家时跳过局域网直接走云端，摄像头卡片提示只能在家里看直播。"]),
'zh-Hant':("攝影機直播",["攝影機和門鈴的詳細卡片裡有 **看直播** 按鈕：畫面直接在卡片裡播放，按放大按鈕可以彈出可調整大小的獨立視窗。","播放由內建的 [go2rtc](https://github.com/AlexxIT/go2rtc)（MIT，官方發佈套件，建置時驗證 SHA-256）完成，只在觀看時執行：只監聽 `127.0.0.1` 的隨機埠，關閉 RTSP / WebRTC / HomeKit（mDNS），只開放播放器和 `/api/ws`；關閉畫面 20 秒後停止，完全結束 MijiaBar 時終止。","登入沿用掃碼工作階段：MijiaBar 把掃碼登入回傳的 `passToken` 存在鑰匙圈，透過暫時的 `go2rtc.yaml`（權限 600，go2rtc 讀入後立即刪除）交給 go2rtc。v0.1.8 之前的登入需要再掃一次碼（**設定 → 攝影機直播**）。","每次連線都會向小米雲端取得金鑰，影像經小米 P2P 從攝影機傳來，不做任何錄影。電池門鈴會被喚醒、耗電更快，請盡量短時間觀看。Agent / MCP 無法存取攝影機。","裝置詳細頁標題（以及清單列上的小圖示）顯示最近一次讀取/控制走的通道：**區域網路**（miIO 直連）、**雲端**（備援）或 **藍牙閘道**。","離家偵測：比較 Mac 目前網卡子網路和裝置的區域網路 IP（網路變化時重新判斷，不保存任何網路資訊）。不在家時略過區域網路直接走雲端，攝影機卡片提示只能在家裡看直播。"]),
}

DOCL={'en':('Full step-by-step instructions for agents:',''),'zh-Hans':('写给 Agent 的完整步骤：','.zh-CN'),'zh-Hant':('寫給 Agent 的完整步驟：','.zh-TW')}
def anchor(h): return re.sub(r'[^\w\- ]','',h.lower()).strip().replace(' ','-')
cli='''```bash
mijiabar list                     # list devices (--all, --refresh)
mijiabar get <device>             # read state as JSON
mijiabar set <device> <prop> <value>
mijiabar action <device> <action> [JSON array]
mijiabar mcp                      # stdio MCP server
mijiabar setup-prompt             # print the agent setup instructions
```'''
build='''```bash
git clone https://github.com/neardws/MijiaBar && cd MijiaBar
swift build
.build/debug/MijiaBarApp --snapshot docs/screenshots   # demo-data screenshots
scripts/package.sh   # dist/MijiaBar.app + DMG (signs & notarizes when a Developer ID is available)
# env: VERSION, SIGN_IDENTITY ("-" = ad-hoc), NOTARY_PROFILE (default MijiaBar-notary)
```'''
for lang,fn in files.items():
    t=T[lang]
    sw=' · '.join(f'<b>{names[l]}</b>' if l==lang else f'<a href="{f}">{names[l]}</a>' for l,f in files.items())
    hh,hl,dh,dl=X[lang]
    lvh,lvl=LV[lang]
    toc=t['toc'][:4]+[hh,lvh]+t['toc'][4:6]+[dh]+t['toc'][6:]
    if '--reuse-prompts' in sys.argv:
        prompt=re.search(r'```text\n(.*?)\n```',open(fn).read(),re.S).group(1)
    else:
        prompt=subprocess.run(['.build/debug/mijiabar','setup-prompt'],env={**os.environ,'MIJIABAR_LANG':lang},capture_output=True,text=True).stdout.rstrip()
    o=[f'<p align="center"><img src="Resources/AppIcon.png" width="96" alt="MijiaBar"></p>' if os.path.exists('Resources/AppIcon.png') else '',
       '<h1 align="center">MijiaBar</h1>',f'<p align="center">{t["tag"]}</p>','',badges,'',f'<p align="center">{sw}</p>','',
       f'> {t["note"]}','',
       '<p align="center"><img src="https://files.neardws.com/mijiabar/readme/demo.gif" width="300" alt="demo"></p>','',
       ' · '.join(f'[{h}](#{anchor(h)})' for h in toc),'',
       f'## {toc[0]}','']+[f'- {x}' for x in t['feat']]+['',
       f'## {toc[1]}','',
       '<p align="center">\n  <img src="https://files.neardws.com/mijiabar/readme/list-light.webp" width="260" alt="">\n  <img src="https://files.neardws.com/mijiabar/readme/ac-cool-light.webp" width="260" alt="">\n  <img src="https://files.neardws.com/mijiabar/readme/fan-light.webp" width="260" alt="">\n</p>',
       f'<p align="center"><b>{t["dark"]}</b><br>\n  <img src="https://files.neardws.com/mijiabar/readme/list-dark.webp" width="260" alt="">\n  <img src="https://files.neardws.com/mijiabar/readme/ac-heat-dark.webp" width="260" alt="">\n  <img src="https://files.neardws.com/mijiabar/readme/light-dark.webp" width="260" alt="">\n</p>',
       '<p align="center">\n  <img src="https://files.neardws.com/mijiabar/readme/plug-light.webp" width="260" alt="">\n  <img src="https://files.neardws.com/mijiabar/readme/agent-light.webp" width="260" alt="">\n  <img src="https://files.neardws.com/mijiabar/readme/login-light.webp" width="260" alt="">\n</p>','',
       f'## {toc[2]}','']+[f'{i+1}. {x}' for i,x in enumerate(t['inst'])]+['',f'> {t["inst_note"]}','',t['req'],'',
       f'## {toc[3]}','']+[f'{i+1}. {x}' for i,x in enumerate(t['login'])]+['',
       f'## {hh}','',hl[0],'']+[f'- {x}' for x in hl[1:3]]+['',hl[3],'',
       f'## {lvh}','']+[f'- {x}' for x in lvl]+['','<p align="center">\n  <img src="https://files.neardws.com/mijiabar/readme/camera-live-light.webp" width="260" alt="">\n  <img src="https://files.neardws.com/mijiabar/readme/doorbell-live-dark.webp" width="260" alt="">\n</p>','',
       f'## {toc[6]}','',t['agent_intro'],'','```text',prompt,'```','',f'{DOCL[lang][0]} [docs/AGENT_SETUP{DOCL[lang][1]}.md](docs/AGENT_SETUP{DOCL[lang][1]}.md)','',
       f'### {t["perm_h"]}','','| | |','| --- | --- |']+[f'| {a} | {b} |' for a,b in t['perm']]+['',t['confirm'],'',
       f'### {t["cli_h"]}','',cli,'',t['tools'],'',
       f'## {toc[7]}','',build,'',t['build_note'],'',
       f'## {dh}','']+[f'- {x}' for x in dl]+['',
       f'## {toc[9]}','',t['credits'],'',t['lic'],'']
    open(fn,'w').write('\n'.join(x for x in o if x is not None).lstrip('\n'))
print('ok')
