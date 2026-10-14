# MijiaBar · Agent / MCP setup

[English](AGENT_SETUP.md) · [简体中文](AGENT_SETUP.zh-CN.md) · **繁體中文**

請幫我把 MijiaBar（macOS 選單列米家控制 App）設定為你的 MCP 工具，按以下步驟自己完成：

1. 找到命令列工具：它在 App 套件內 /Applications/MijiaBar.app/Contents/Resources/bin/mijiabar。執行 "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" --help 確認可用。如需在終端機直接使用，可建立連結：mkdir -p ~/.local/bin && ln -sf "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" ~/.local/bin/mijiabar
2. 用你自己的設定註冊一個名為 mijia 的 stdio MCP 伺服器，指令為 "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar"，參數為 mcp：

```bash
# Claude Code
claude mcp add --scope user mijia -- "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" mcp
# Codex
codex mcp add mijia -- "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" mcp
```

```toml
# Codex: ~/.codex/config.toml
[mcp_servers.mijia]
command = "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar"
args = ["mcp"]
```

```json
// Cursor: ~/.cursor/mcp.json
// Claude Desktop: ~/Library/Application Support/Claude/claude_desktop_config.json
// other MCP clients: their "mcpServers" JSON
{"mcpServers": {"mijia": {"command": "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar", "args": ["mcp"]}}}
```

註冊後視需要重新載入 MCP。

3. 可用工具：list_devices、get_device_state、set_property、run_action。權限由我在 MijiaBar → 設定 → Agent 介面 中控制：預設「唯讀」（寫入操作會被拒絕）；「白名單」只允許控制勾選的裝置；「全部」允許控制所有裝置。開啟「每次寫入操作跳出視窗確認」時，每次寫入操作都會在 Mac 上跳出視窗，需要我按「允許」。沒有我的明確要求，不要改變任何裝置的狀態。
4. 驗證：執行 "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" list（或呼叫 list_devices），把裝置清單給我看。如果顯示未登入，請讓我先在 MijiaBar 裡掃碼登入。

---

CLI default path: `/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar` · MCP tools: `list_devices`, `get_device_state`, `set_property`, `run_action` · Repository: https://github.com/neardws/MijiaBar
