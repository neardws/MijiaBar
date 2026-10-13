# MijiaBar · Agent / MCP setup

[English](AGENT_SETUP.md) · [简体中文](AGENT_SETUP.zh-CN.md) · [繁體中文](AGENT_SETUP.zh-TW.md) · [Deutsch](AGENT_SETUP.de.md) · [Français](AGENT_SETUP.fr.md) · [Español](AGENT_SETUP.es.md) · [Italiano](AGENT_SETUP.it.md) · **Русский** · [日本語](AGENT_SETUP.ja.md)

Пожалуйста, подключи MijiaBar (приложение в строке меню macOS для устройств Xiaomi Mi Home) как свой MCP-инструмент. Сделай это сам, по шагам:

1. Найди CLI. Он находится внутри приложения: /Applications/MijiaBar.app/Contents/Resources/bin/mijiabar. Выполни "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" --help, чтобы проверить его. Для работы из терминала создай ссылку: mkdir -p ~/.local/bin && ln -sf "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" ~/.local/bin/mijiabar
2. Зарегистрируй в своей конфигурации stdio MCP-сервер с именем mijia, командой "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" и аргументом mcp:

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

При необходимости перезагрузи MCP-серверы.

3. Инструменты: list_devices, get_device_state, set_property, run_action. Доступом управляю я в MijiaBar → Настройки → Интерфейс агента: по умолчанию «Чтение» (запись запрещена); «Белый список» разрешает только выбранные устройства; «Полный» разрешает все устройства. Если включено «Подтверждать каждую запись», каждая запись показывает на Mac окно, которое я должен одобрить. Никогда не меняй состояние устройства без моей просьбы.
4. Проверка: выполни "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" list (или вызови list_devices) и покажи мне список устройств. Если я не вошёл в аккаунт, попроси меня сначала войти по QR-коду в MijiaBar.

---

CLI default path: `/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar` · MCP tools: `list_devices`, `get_device_state`, `set_property`, `run_action` · Repository: https://github.com/neardws/MijiaBar
