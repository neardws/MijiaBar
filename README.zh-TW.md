<h1 align="center">MijiaBar</h1>
<p align="center">在 macOS 選單列控制米家裝置，也可以交給 AI Agent 來控制。</p>

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

<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <b>繁體中文</b></p>

> 非小米官方專案。使用與米家 App 相同的雲端介面和區域網路 miIO 協定。

<p align="center"><img src="https://files.neardws.com/mijiabar/readme/demo.gif" width="300" alt="demo"></p>

[功能](#功能) · [截圖](#截圖) · [安裝](#安裝) · [登入](#登入) · [預設隱藏規則](#預設隱藏規則) · [攝影機直播](#攝影機直播) · [Agent / MCP](#agent--mcp) · [從原始碼建置](#從原始碼建置) · [資料存放位置](#資料存放位置) · [致謝](#致謝)

## 功能

- **掃碼登入**：用米家 App 掃一掃，免密碼。預設中國大陸伺服器，也可切換歐洲、美國、俄羅斯、新加坡、印度。憑證只存在 macOS 鑰匙圈。
- **自動取得裝置**：載入所有家庭、房間和共享裝置及上線狀態；離線和久未使用的裝置預設隱藏。
- **小屋剖面圖**：裝置清單頂部的像素風等距小屋，點場景裡的燈具、電視/螢幕、冷氣、玄關燈等即可開關對應裝置，每個點位單獨亮燈，不會整間房一起亮。依本機時間切換白天/夜晚底圖（約 6:00–17:59）；點 **放大** 可開啟獨立小屋視窗。
- **每類裝置單獨設計**：冷氣、電風扇、燈、插座、電視、音箱、攝影機、印表機、廚房電器、淨水器、電暖器、除濕機、感測器，各有擬物插圖。
- **克制的動態效果**：無回彈的快速彈簧（< 300ms）；風扇依風速轉動、電視螢幕發光、電暖器熱浪；電源鍵漣漪；滑桿 1:1 跟手、放開吸附、跨檔觸控板輕觸。遵循「減少動態效果」。
- **鍵盤優先**：`↑/↓` 選擇、`↩` 開啟、`空白鍵` 開關、`←/→` 調整主滑桿、`/` 搜尋、`Esc` 返回、`⌘Q` 結束。
- **淺色 / 深色**：使用系統語意色彩，自動跟隨外觀。
- **支援三種介面語言**：繁體中文（台灣用語）、简体中文、English，依地區建議預設語言。
- **Agent 介面**：`mijiabar` 命令列和 stdio MCP 伺服器，預設唯讀，可選白名單 / 全部權限，寫入操作可跳出視窗確認。
- **雙通道控制**：小米雲端 MIoT RPC，失敗時退回區域網路 miIO；空調夥伴（`lumi.acpartner.*`）使用舊版區域網路指令。

## 截圖

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

## 安裝

1. 從 [Releases](https://github.com/neardws/MijiaBar/releases/latest) 下載 `MijiaBar-x.y.z.dmg`，把 MijiaBar 拖進「應用程式」後開啟。正式版已用 Developer ID 簽署並通過 Apple 公證。
2. 第一次控制裝置時，請允許「本機網路」權限（區域網路直連需要）。

> CI 建置的 `*-unsigned.dmg` 和自行本機打包的版本為 ad-hoc 簽署，首次開啟前執行 `xattr -dr com.apple.quarantine /Applications/MijiaBar.app`。

系統需求：macOS 14 以上，支援 Apple 晶片和 Intel。

## 登入

1. 點選單列的 🏠 圖示，會顯示 QR 碼。
2. 選擇伺服器地區（預設為中國大陸）。
3. 開啟手機 **米家 App** →「+」→「掃一掃」，掃描 QR 碼並在手機上確認，裝置會自動載入。

## 預設隱藏規則

符合任一條件的裝置預設收合到清單底部：

- 雲端回報離線（`isOnline = false`）；
- 雲端回傳了最後上線時間（`last_online` / `lastOnline` / `last_online_time`），且超過 30 天。

按眼睛按鈕或「顯示」可以展開，也可以在 **設定 → 裝置管理 → 顯示已隱藏的裝置** 中開啟。在裝置上按右鍵可以手動「隱藏 / 取消隱藏」，手動設定一律優先於自動規則。

## 攝影機直播

- 攝影機和門鈴的詳細卡片裡有 **看直播** 按鈕：畫面直接在卡片裡播放，按放大按鈕可以彈出可調整大小的獨立視窗。
- 播放由內建的 [go2rtc](https://github.com/AlexxIT/go2rtc)（MIT，官方發佈套件，建置時驗證 SHA-256）完成，只在觀看時執行：只監聽 `127.0.0.1` 的隨機埠，關閉 RTSP / WebRTC / HomeKit（mDNS），只開放播放器和 `/api/ws`；關閉畫面 20 秒後停止，完全結束 MijiaBar 時終止。
- 登入沿用掃碼工作階段：MijiaBar 把掃碼登入回傳的 `passToken` 存在鑰匙圈，透過暫時的 `go2rtc.yaml`（權限 600，go2rtc 讀入後立即刪除）交給 go2rtc。v0.1.8 之前的登入需要再掃一次碼（**設定 → 攝影機直播**）。
- 每次連線都會向小米雲端取得金鑰，影像經小米 P2P 從攝影機傳來，不做任何錄影。電池門鈴會被喚醒、耗電更快，請盡量短時間觀看。Agent / MCP 無法存取攝影機。
- 裝置詳細頁標題（以及清單列上的小圖示）顯示最近一次讀取/控制走的通道：**區域網路**（miIO 直連）、**雲端**（備援）或 **藍牙閘道**。
- 離家偵測：比較 Mac 目前網卡子網路和裝置的區域網路 IP（網路變化時重新判斷，不保存任何網路資訊）。不在家時略過區域網路直接走雲端，攝影機卡片提示只能在家裡看直播。

<p align="center">
  <img src="https://files.neardws.com/mijiabar/readme/camera-live-light.webp" width="260" alt="">
  <img src="https://files.neardws.com/mijiabar/readme/doorbell-live-dark.webp" width="260" alt="">
</p>

## Agent / MCP

開啟 **設定 → Agent 介面**，點 **複製安裝說明**，貼給 Claude Code、Codex、Cursor 等 Agent。Agent 會自己找到內建 CLI、在自己的設定裡註冊 MCP 伺服器，並列出裝置完成驗證。`mijiabar setup-prompt` 會輸出同樣的內容（路徑已填好）：

```text
請閱讀 https://raw.githubusercontent.com/neardws/MijiaBar/main/docs/AGENT_SETUP.zh-TW.md ，依照其中的步驟把 MijiaBar 設定為你的 MCP 工具。
CLI 路徑：/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar
未經我同意，不要改變任何裝置的狀態。
```

寫給 Agent 的完整步驟： [docs/AGENT_SETUP.zh-TW.md](docs/AGENT_SETUP.zh-TW.md)

### 權限

| | |
| --- | --- |
| 關閉 | Agent 什麼都不能做 |
| 唯讀（預設） | 只能列出裝置、讀取狀態 |
| 白名單 | 只能控制你勾選的裝置 |
| 全部 | 可以控制所有裝置 |

開啟 **每次寫入操作跳出視窗確認** 後，Agent 的每次控制都會跳出系統對話框，需要你點「允許」。

### 命令列

```bash
mijiabar list                     # list devices (--all, --refresh)
mijiabar get <device>             # read state as JSON
mijiabar set <device> <prop> <value>
mijiabar action <device> <action> [JSON array]
mijiabar mcp                      # stdio MCP server
mijiabar setup-prompt             # print the agent setup instructions
```

MCP 工具：`list_devices`、`get_device_state`、`set_property`、`run_action`。

## 從原始碼建置

```bash
git clone https://github.com/neardws/MijiaBar && cd MijiaBar
swift build
.build/debug/MijiaBarApp --snapshot docs/screenshots   # demo-data screenshots
scripts/package.sh   # dist/MijiaBar.app + DMG (signs & notarizes when a Developer ID is available)
# env: VERSION, SIGN_IDENTITY ("-" = ad-hoc), NOTARY_PROFILE (default MijiaBar-notary)
```

專案結構：`Sources/MijiaCore`（雲端 API、掃碼登入、miIO、MIoT 規格）、`Sources/MijiaBarApp`（SwiftUI 應用程式）、`Sources/mijiabar`（CLI + MCP）。翻譯在 `i18n/*.tsv`，修改後執行 `scripts/gen-i18n.py`。

## 資料存放位置

- 登入憑證：macOS 鑰匙圈，服務名稱 `com.neardws.MijiaBar`（帳號 `session`），登出即刪除。
- 裝置快取 `devices.json`、偏好設定 `prefs.json`（收藏、別名、隱藏、地區）、Agent 權限 `agent.json`、MIoT 規格快取 `spec-index.json` 和 `specs/<型號>.json`，都在 `~/Library/Application Support/MijiaBar/`，檔案權限 600。
- 介面語言：UserDefaults 的 `MijiaBarLang`（App 與 CLI 共用，環境變數 `MIJIABAR_LANG` 可覆寫）。
- 除了小米伺服器、區域網路內的裝置和 miot-spec.org（下載公開規格）之外，不會將資料傳送到任何地方。

## 致謝

動態效果設計由 [@skyswordw](https://github.com/skyswordw) 貢獻（[#1](https://github.com/neardws/MijiaBar/pull/1)）。協定細節參考 [python-miio](https://github.com/rytilahti/python-miio)、[Xiaomi-cloud-tokens-extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) 和 [ha_xiaomi_home](https://github.com/XiaoMi/ha_xiaomi_home)。介面靈感來自 [@the_mcnaveen](https://x.com/the_mcnaveen) 的冷氣選單列 App。

MIT 授權。
