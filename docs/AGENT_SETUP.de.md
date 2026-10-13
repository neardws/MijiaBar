# MijiaBar · Agent / MCP setup

[English](AGENT_SETUP.md) · [简体中文](AGENT_SETUP.zh-CN.md) · [繁體中文](AGENT_SETUP.zh-TW.md) · **Deutsch** · [Français](AGENT_SETUP.fr.md) · [Español](AGENT_SETUP.es.md) · [Italiano](AGENT_SETUP.it.md) · [Русский](AGENT_SETUP.ru.md) · [日本語](AGENT_SETUP.ja.md)

Bitte richte MijiaBar (eine macOS-Menüleisten-App für Xiaomi-Mi-Home-Geräte) als MCP-Tool für dich ein. Erledige das selbst, Schritt für Schritt:

1. Finde das CLI. Es liegt im App-Bundle unter /Applications/MijiaBar.app/Contents/Resources/bin/mijiabar. Führe "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" --help aus, um es zu prüfen. Für die Nutzung im Terminal verlinken: mkdir -p ~/.local/bin && ln -sf "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" ~/.local/bin/mijiabar
2. Registriere in deiner eigenen Konfiguration einen stdio-MCP-Server namens mijia mit dem Befehl "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" und dem Argument mcp:

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

Lade die MCP-Server danach bei Bedarf neu.

3. Werkzeuge: list_devices, get_device_state, set_property, run_action. Den Zugriff steuere ich in MijiaBar → Einstellungen → Agent-Schnittstelle: Standard ist „Lesen“ (Schreibzugriffe werden abgelehnt); „Positivliste“ erlaubt nur ausgewählte Geräte; „Voll“ erlaubt alle Geräte. Ist „Jeden Schreibvorgang bestätigen“ aktiv, erscheint auf dem Mac für jeden Schreibvorgang ein Dialog, den ich bestätigen muss. Ändere niemals den Zustand eines Geräts, ohne dass ich dich darum bitte.
4. Prüfen: Führe "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" list aus (oder rufe list_devices auf) und zeig mir die Geräteliste. Falls ich nicht angemeldet bin, bitte mich, mich zuerst in MijiaBar per QR-Code anzumelden.

---

CLI default path: `/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar` · MCP tools: `list_devices`, `get_device_state`, `set_property`, `run_action` · Repository: https://github.com/neardws/MijiaBar
