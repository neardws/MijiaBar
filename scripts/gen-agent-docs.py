#!/usr/bin/env python3
"""i18n/agent-setup/<lang>.txt → docs/AGENT_SETUP*.md（写给 AI Agent 照着做的完整接入说明）"""
import os
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
CLI = '/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar'
LANGS = [('en', '', 'English'), ('zh-Hans', '.zh-CN', '简体中文'), ('zh-Hant', '.zh-TW', '繁體中文')]
CODE = f'''```bash
# Claude Code
claude mcp add --scope user mijia -- "{CLI}" mcp
# Codex
codex mcp add mijia -- "{CLI}" mcp
```

```toml
# Codex: ~/.codex/config.toml
[mcp_servers.mijia]
command = "{CLI}"
args = ["mcp"]
```

```json
// Cursor: ~/.cursor/mcp.json
// Claude Desktop: ~/Library/Application Support/Claude/claude_desktop_config.json
// other MCP clients: their "mcpServers" JSON
{{"mcpServers": {{"mijia": {{"command": "{CLI}", "args": ["mcp"]}}}}}}
```'''
for lang, suf, name in LANGS:
    L = open(f'i18n/agent-setup/{lang}.txt', encoding='utf-8').read().replace('{CLI}', CLI).rstrip().split('\n')
    # 行：0 引言，2 步骤 1，3 步骤 2，4–11 配置示例（改成代码块），12 重新加载，13 步骤 3，14 步骤 4
    body = [L[0], '', L[2], L[3], '', CODE, '', L[12].strip(), '', L[13], L[14]]
    sw = ' · '.join(f'**{n}**' if l == lang else f'[{n}](AGENT_SETUP{s}.md)' for l, s, n in LANGS)
    md = ['# MijiaBar · Agent / MCP setup', '', sw, '', *body, '', '---', '',
          f'CLI default path: `{CLI}` · MCP tools: `list_devices`, `get_device_state`, `set_property`, `run_action` · '
          'Repository: https://github.com/neardws/MijiaBar', '']
    open(f'docs/AGENT_SETUP{suf}.md', 'w', encoding='utf-8').write('\n'.join(md))
print('✅ docs/AGENT_SETUP*.md:', len(LANGS))
