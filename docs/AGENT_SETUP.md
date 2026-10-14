# MijiaBar · Agent / MCP setup

**English** · [简体中文](AGENT_SETUP.zh-CN.md) · [繁體中文](AGENT_SETUP.zh-TW.md)

Please set up MijiaBar (a macOS menu bar app for Xiaomi Mi Home devices) as an MCP tool for yourself. Do it yourself, step by step:

1. Find the CLI. It ships inside the app bundle at /Applications/MijiaBar.app/Contents/Resources/bin/mijiabar. Run "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" --help to check it works. To use it from a terminal, link it: mkdir -p ~/.local/bin && ln -sf "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" ~/.local/bin/mijiabar
2. Register a stdio MCP server named mijia, command "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar", argument mcp, in your own config:

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

Reload MCP servers afterwards if needed.

3. Tools: list_devices, get_device_state, set_property, run_action. I control access in MijiaBar → Settings → Agent interface: "Read" is the default (writes are refused); "Allowlist" allows only the devices I pick; "Full" allows every device. When "Confirm every write" is on, each write shows a dialog on the Mac that I have to approve. Never change a device's state unless I ask you to.
4. Verify: run "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" list (or call list_devices) and show me the device list. If it says I'm not signed in, ask me to sign in with the QR code in MijiaBar first.

---

CLI default path: `/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar` · MCP tools: `list_devices`, `get_device_state`, `set_property`, `run_action` · Repository: https://github.com/neardws/MijiaBar
