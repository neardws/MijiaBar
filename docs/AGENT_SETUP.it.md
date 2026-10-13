# MijiaBar · Agent / MCP setup

[English](AGENT_SETUP.md) · [简体中文](AGENT_SETUP.zh-CN.md) · [繁體中文](AGENT_SETUP.zh-TW.md) · [Deutsch](AGENT_SETUP.de.md) · [Français](AGENT_SETUP.fr.md) · [Español](AGENT_SETUP.es.md) · **Italiano** · [Русский](AGENT_SETUP.ru.md) · [日本語](AGENT_SETUP.ja.md)

Configura MijiaBar (un’app della barra dei menu di macOS per i dispositivi Xiaomi Mi Home) come strumento MCP per te. Fallo da solo, passo per passo:

1. Trova la CLI. È inclusa nell’app: /Applications/MijiaBar.app/Contents/Resources/bin/mijiabar. Esegui "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" --help per verificare che funzioni. Per usarla dal terminale, crea un link: mkdir -p ~/.local/bin && ln -sf "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" ~/.local/bin/mijiabar
2. Registra nella tua configurazione un server MCP stdio chiamato mijia, comando "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar", argomento mcp:

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

Poi ricarica i server MCP se necessario.

3. Strumenti: list_devices, get_device_state, set_property, run_action. Controllo io l’accesso in MijiaBar → Impostazioni → Interfaccia agente: «Lettura» è il predefinito (le scritture vengono rifiutate); «Lista consentita» permette solo i dispositivi scelti; «Completo» permette tutti i dispositivi. Con «Conferma ogni scrittura» attivo, ogni scrittura mostra sul Mac una finestra che devo approvare. Non cambiare mai lo stato di un dispositivo senza che te lo chieda.
4. Verifica: esegui "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" list (o chiama list_devices) e mostrami l’elenco dei dispositivi. Se risulta che non ho effettuato l’accesso, chiedimi prima di accedere con il codice QR in MijiaBar.

---

CLI default path: `/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar` · MCP tools: `list_devices`, `get_device_state`, `set_property`, `run_action` · Repository: https://github.com/neardws/MijiaBar
