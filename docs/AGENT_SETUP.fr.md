# MijiaBar · Agent / MCP setup

[English](AGENT_SETUP.md) · [简体中文](AGENT_SETUP.zh-CN.md) · [繁體中文](AGENT_SETUP.zh-TW.md) · [Deutsch](AGENT_SETUP.de.md) · **Français** · [Español](AGENT_SETUP.es.md) · [Italiano](AGENT_SETUP.it.md) · [Русский](AGENT_SETUP.ru.md) · [日本語](AGENT_SETUP.ja.md)

Configure MijiaBar (une app de barre des menus macOS pour les appareils Xiaomi Mi Home) comme outil MCP pour toi-même. Fais-le toi-même, étape par étape :

1. Trouve la CLI. Elle est fournie dans l’app : /Applications/MijiaBar.app/Contents/Resources/bin/mijiabar. Lance "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" --help pour vérifier qu’elle fonctionne. Pour l’utiliser dans un terminal, crée un lien : mkdir -p ~/.local/bin && ln -sf "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" ~/.local/bin/mijiabar
2. Enregistre dans ta propre configuration un serveur MCP stdio nommé mijia, commande "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar", argument mcp :

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

Recharge ensuite les serveurs MCP si nécessaire.

3. Outils : list_devices, get_device_state, set_property, run_action. Je contrôle l’accès dans MijiaBar → Réglages → Interface agent : « Lecture » par défaut (les écritures sont refusées) ; « Liste autorisée » n’autorise que les appareils choisis ; « Complet » autorise tous les appareils. Si « Confirmer chaque écriture » est activé, chaque écriture affiche sur le Mac une fenêtre que je dois approuver. Ne modifie jamais l’état d’un appareil sans que je te le demande.
4. Vérifie : lance "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" list (ou appelle list_devices) et montre-moi la liste des appareils. Si je ne suis pas connecté, demande-moi d’abord de me connecter par QR code dans MijiaBar.

---

CLI default path: `/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar` · MCP tools: `list_devices`, `get_device_state`, `set_property`, `run_action` · Repository: https://github.com/neardws/MijiaBar
