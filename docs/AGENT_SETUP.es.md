# MijiaBar · Agent / MCP setup

[English](AGENT_SETUP.md) · [简体中文](AGENT_SETUP.zh-CN.md) · [繁體中文](AGENT_SETUP.zh-TW.md) · [Deutsch](AGENT_SETUP.de.md) · [Français](AGENT_SETUP.fr.md) · **Español** · [Italiano](AGENT_SETUP.it.md) · [Русский](AGENT_SETUP.ru.md) · [日本語](AGENT_SETUP.ja.md)

Configura MijiaBar (una app de barra de menús de macOS para dispositivos Xiaomi Mi Home) como herramienta MCP para ti. Hazlo tú mismo, paso a paso:

1. Localiza la CLI. Viene dentro de la app: /Applications/MijiaBar.app/Contents/Resources/bin/mijiabar. Ejecuta "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" --help para comprobar que funciona. Para usarla en el terminal, crea un enlace: mkdir -p ~/.local/bin && ln -sf "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" ~/.local/bin/mijiabar
2. Registra en tu propia configuración un servidor MCP stdio llamado mijia, comando "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar", argumento mcp:

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

Después recarga los servidores MCP si hace falta.

3. Herramientas: list_devices, get_device_state, set_property, run_action. Yo controlo el acceso en MijiaBar → Ajustes → Interfaz de agente: «Lectura» por defecto (se rechazan las escrituras); «Lista permitida» solo permite los dispositivos que elija; «Completo» permite todos. Con «Confirmar cada escritura» activado, cada escritura muestra un diálogo en el Mac que debo aprobar. Nunca cambies el estado de un dispositivo sin que te lo pida.
4. Verifica: ejecuta "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" list (o llama a list_devices) y muéstrame la lista de dispositivos. Si indica que no he iniciado sesión, pídeme que primero inicie sesión con el código QR en MijiaBar.

---

CLI default path: `/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar` · MCP tools: `list_devices`, `get_device_state`, `set_property`, `run_action` · Repository: https://github.com/neardws/MijiaBar
