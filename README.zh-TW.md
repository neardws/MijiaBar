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

<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <b>繁體中文</b> · <a href="README.ru.md">Русский</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a></p>

> 非小米官方專案。使用與米家 App 相同的雲端介面和區域網路 miIO 協定。

<p align="center"><img src="docs/screenshots/demo.gif" width="300" alt="demo"></p>

[功能](#功能) · [截圖](#截圖) · [安裝](#安裝) · [登入](#登入) · [Agent / MCP](#agent--mcp) · [從原始碼建置](#從原始碼建置) · [致謝](#致謝)

## 功能

- **掃碼登入**：用米家 App 掃一掃，免密碼。預設中國大陸伺服器，也可切換歐洲、美國、俄羅斯、新加坡、印度。憑證只存在 macOS 鑰匙圈。
- **自動取得裝置**：載入所有家庭、房間和共享裝置及上線狀態；離線和久未使用的裝置預設隱藏。
- **每類裝置單獨設計**：冷氣、電風扇、燈、插座、電視、音箱、攝影機、印表機、廚房電器、淨水器、暖氣機、除濕機、感測器，各有擬物插圖。
- **克制的動態效果**：無回彈的快速彈簧（< 300ms）；風扇依風速轉動、電視螢幕發光、暖氣機熱浪；電源鍵漣漪；滑桿 1:1 跟手、放開吸附、跨檔觸控板輕觸。遵循「減少動態效果」。
- **鍵盤優先**：`↑/↓` 選擇、`↩` 開啟、`空白鍵` 開關、`←/→` 調整主滑桿、`/` 搜尋、`Esc` 返回、`⌘Q` 結束。
- **淺色 / 深色**：使用系統語意色彩，自動跟隨外觀。
- **9 種介面語言**：简体中文、繁體中文、English、Deutsch、Français、Español、Italiano、Русский、日本語，依地區建議預設語言。
- **Agent 介面**：`mijiabar` 命令列和 stdio MCP 伺服器，預設唯讀，可選白名單 / 全部權限，寫入操作可跳窗確認。
- **雙通道控制**：小米雲 MIoT RPC，失敗時退回區域網路 miIO；空調伴侶（`lumi.acpartner.*`）使用舊版區域網路指令。

## 截圖

<p align="center">
  <img src="docs/screenshots/list-light.png" width="260" alt="">
  <img src="docs/screenshots/ac-cool-light.png" width="260" alt="">
  <img src="docs/screenshots/fan-light.png" width="260" alt="">
</p>
<p align="center"><b>深色模式</b><br>
  <img src="docs/screenshots/list-dark.png" width="260" alt="">
  <img src="docs/screenshots/ac-heat-dark.png" width="260" alt="">
  <img src="docs/screenshots/light-dark.png" width="260" alt="">
</p>
<p align="center">
  <img src="docs/screenshots/plug-light.png" width="260" alt="">
  <img src="docs/screenshots/agent-light.png" width="260" alt="">
  <img src="docs/screenshots/login-light.png" width="260" alt="">
</p>

## 安裝

1. 從 [Releases](https://github.com/neardws/MijiaBar/releases/latest) 下載 `MijiaBar-x.y.z.dmg`，把 MijiaBar 拖進「應用程式」後開啟。正式版已用 Developer ID 簽署並通過 Apple 公證。
2. 第一次控制裝置時，請允許「本機網路」權限（區域網路直連需要）。

> CI 建置的 `*-unsigned.dmg` 和自行本機打包的版本為 ad-hoc 簽署，首次開啟前執行 `xattr -dr com.apple.quarantine /Applications/MijiaBar.app`。

系統需求：macOS 14 以上，支援 Apple 晶片和 Intel。

## 登入

1. 點選單列的 🏠 圖示，會顯示 QR 碼。
2. 選擇伺服器地區（預設中國大陸）。
3. 開啟手機 **米家 App** →「+」→「掃一掃」，掃碼並在手機上確認，裝置會自動載入。

## Agent / MCP

開啟 **設定 → Agent 介面**，點 **複製安裝說明**，貼給 Claude Code、Codex、Cursor 等 Agent。Agent 會自己找到內建 CLI、在自己的設定裡註冊 MCP 伺服器，並列出裝置完成驗證。`mijiabar setup-prompt` 會輸出同樣的內容（路徑已填好）：

```text
請幫我把 MijiaBar（macOS 菜單欄米家控制應用）接入為你的 MCP 工具，按以下步驟自己完成：

1. 找到命令行工具：它在應用包內 /Applications/MijiaBar.app/Contents/Resources/bin/mijiabar。運行 "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" --help 確認可用。如需在終端直接使用，可建立鏈接：mkdir -p ~/.local/bin && ln -sf "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" ~/.local/bin/mijiabar
2. 用你自己的配置註冊一個名為 mijia 的 stdio MCP 服務器，命令為 "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar"，參數為 mcp：
   - Claude Code: claude mcp add --scope user mijia -- "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" mcp
   - Codex: codex mcp add mijia -- "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" mcp
     (~/.codex/config.toml:
      [mcp_servers.mijia]
      command = "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar"
      args = ["mcp"])
   - Cursor (~/.cursor/mcp.json), Claude Desktop, …:
     {"mcpServers": {"mijia": {"command": "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar", "args": ["mcp"]}}}
   註冊後按需重新加載 MCP。
3. 可用工具：list_devices、get_device_state、set_property、run_action。權限由我在 MijiaBar → 設置 → Agent 接口 中控制：默認「只讀」（寫操作會被拒絕）；「白名單」只允許控制選中的設備；「全部」允許控制所有設備。開啓「每次寫操作彈窗確認」時，每次寫操作都會在 Mac 上彈窗，需要我點允許。沒有我的明確要求，不要改變任何設備的狀態。
4. 驗證：運行 "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" list（或調用 list_devices），把設備列表給我看。如果提示未登錄，請讓我先在 MijiaBar 里掃碼登錄。
```

### 權限

| | |
| --- | --- |
| 關閉 | Agent 什麼都不能做 |
| 唯讀（預設） | 只能列出裝置、讀取狀態 |
| 白名單 | 只能控制你勾選的裝置 |
| 全部 | 可以控制所有裝置 |

開啟 **每次寫入操作跳窗確認** 後，Agent 的每次控制都會跳出系統對話框，需要你點「允許」。

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

## 致謝

動態效果設計由 [@skyswordw](https://github.com/skyswordw) 貢獻（[#1](https://github.com/neardws/MijiaBar/pull/1)）。協定細節參考 [python-miio](https://github.com/rytilahti/python-miio)、[Xiaomi-cloud-tokens-extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) 和 [ha_xiaomi_home](https://github.com/XiaoMi/ha_xiaomi_home)。介面靈感來自 [@the_mcnaveen](https://x.com/the_mcnaveen) 的冷氣選單列應用程式。

MIT 授權。
