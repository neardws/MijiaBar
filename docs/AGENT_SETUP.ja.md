# MijiaBar · Agent / MCP setup

[English](AGENT_SETUP.md) · [简体中文](AGENT_SETUP.zh-CN.md) · [繁體中文](AGENT_SETUP.zh-TW.md) · [Deutsch](AGENT_SETUP.de.md) · [Français](AGENT_SETUP.fr.md) · [Español](AGENT_SETUP.es.md) · [Italiano](AGENT_SETUP.it.md) · [Русский](AGENT_SETUP.ru.md) · **日本語**

MijiaBar（Xiaomi Mi Home デバイス用の macOS メニューバーアプリ）を、あなた自身の MCP ツールとして設定してください。次の手順で自分で行ってください：

1. CLI を見つける：アプリ内の /Applications/MijiaBar.app/Contents/Resources/bin/mijiabar にあります。"/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" --help を実行して動作を確認してください。ターミナルで使う場合はリンクを作成：mkdir -p ~/.local/bin && ln -sf "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" ~/.local/bin/mijiabar
2. あなた自身の設定に、名前 mijia、コマンド "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar"、引数 mcp の stdio MCP サーバーを登録：

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

必要に応じて MCP サーバーを再読み込みしてください。

3. ツール：list_devices、get_device_state、set_property、run_action。アクセス権は私が MijiaBar → 設定 → エージェント連携 で管理します：既定は「読み取り」（書き込みは拒否）、「許可リスト」は選んだデバイスのみ、「すべて」は全デバイスを許可します。「書き込みごとに確認」がオンの場合、書き込みのたびに Mac にダイアログが表示され、私の承認が必要です。私が頼まない限り、デバイスの状態を変更しないでください。
4. 確認："/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" list を実行（または list_devices を呼び出し）して、デバイス一覧を見せてください。未ログインと表示されたら、まず MijiaBar で QR コードからログインするよう私に伝えてください。

---

CLI default path: `/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar` · MCP tools: `list_devices`, `get_device_state`, `set_property`, `run_action` · Repository: https://github.com/neardws/MijiaBar
