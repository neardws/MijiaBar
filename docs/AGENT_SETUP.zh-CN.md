# MijiaBar · Agent / MCP setup

[English](AGENT_SETUP.md) · **简体中文** · [繁體中文](AGENT_SETUP.zh-TW.md) · [Deutsch](AGENT_SETUP.de.md) · [Français](AGENT_SETUP.fr.md) · [Español](AGENT_SETUP.es.md) · [Italiano](AGENT_SETUP.it.md) · [Русский](AGENT_SETUP.ru.md) · [日本語](AGENT_SETUP.ja.md)

请帮我把 MijiaBar（macOS 菜单栏米家控制应用）接入为你的 MCP 工具，按以下步骤自己完成：

1. 找到命令行工具：它在应用包内 /Applications/MijiaBar.app/Contents/Resources/bin/mijiabar。运行 "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" --help 确认可用。如需在终端直接使用，可建立链接：mkdir -p ~/.local/bin && ln -sf "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" ~/.local/bin/mijiabar
2. 用你自己的配置注册一个名为 mijia 的 stdio MCP 服务器，命令为 "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar"，参数为 mcp：

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

注册后按需重新加载 MCP。

3. 可用工具：list_devices、get_device_state、set_property、run_action。权限由我在 MijiaBar → 设置 → Agent 接口 中控制：默认「只读」（写操作会被拒绝）；「白名单」只允许控制选中的设备；「全部」允许控制所有设备。开启「每次写操作弹窗确认」时，每次写操作都会在 Mac 上弹窗，需要我点允许。没有我的明确要求，不要改变任何设备的状态。
4. 验证：运行 "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" list（或调用 list_devices），把设备列表给我看。如果提示未登录，请让我先在 MijiaBar 里扫码登录。

---

CLI default path: `/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar` · MCP tools: `list_devices`, `get_device_state`, `set_property`, `run_action` · Repository: https://github.com/neardws/MijiaBar
