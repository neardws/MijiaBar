<h1 align="center">MijiaBar</h1>
<p align="center">Управляйте устройствами Xiaomi Mi Home из строки меню macOS — или доверьте это AI-агентам.</p>

<p align="center">
  <a href="https://github.com/neardws/MijiaBar/releases/latest"><img src="https://img.shields.io/github/v/release/neardws/MijiaBar?label=release&color=blue" alt="Release"></a>
  <a href="https://github.com/neardws/MijiaBar/releases"><img src="https://img.shields.io/github/downloads/neardws/MijiaBar/total?color=brightgreen" alt="Downloads"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/neardws/MijiaBar" alt="License"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/Apple-notarized-success?logo=apple" alt="Notarized">
  <a href="https://github.com/neardws/MijiaBar/actions/workflows/build.yml"><img src="https://img.shields.io/github/actions/workflow/status/neardws/MijiaBar/build.yml?branch=main&label=build" alt="Build"></a>
  <a href="https://github.com/neardws/MijiaBar/stargazers"><img src="https://img.shields.io/github/stars/neardws/MijiaBar?style=social" alt="Stars"></a>
</p>

<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <b>Русский</b> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a></p>

> Неофициальный проект, не связан с Xiaomi. Использует то же облачное API, что и приложение Mi Home, а также локальный протокол miIO.

<p align="center"><img src="docs/screenshots/demo.gif" width="300" alt="demo"></p>

[Возможности](#возможности) · [Скриншоты](#скриншоты) · [Установка](#установка) · [Вход](#вход) · [Агенты / MCP](#агенты--mcp) · [Сборка из исходников](#сборка-из-исходников) · [Благодарности](#благодарности)

## Возможности

- **Вход по QR-коду** — отсканируйте в приложении Mi Home, без пароля. По умолчанию сервер «Материковый Китай»; Европа, США, Россия, Сингапур и Индия — в один клик. Данные входа хранятся в связке ключей macOS.
- **Автоматический список устройств** — все дома, комнаты и общие устройства со статусом сети. Устройства не в сети и давно не используемые скрыты по умолчанию.
- **Отдельная страница для каждого типа** — кондиционер, вентилятор, свет, розетка, телевизор, колонка, камера, принтер, кухонная техника, фильтр для воды, обогреватель, осушитель и датчики, у каждого своя скевоморфная иллюстрация.
- **Сдержанная анимация** — быстрые пружины без отскока (< 300 мс); лопасти вентилятора крутятся по скорости, экран ТВ светится, обогреватель излучает тепло; кнопка питания даёт волну; ползунки следуют за курсором, примагничиваются и дают отклик трекпада. Учитывается «Уменьшение движения».
- **Клавиатура** — `↑/↓` выбор, `↩` открыть, `Пробел` питание, `←/→` основной ползунок, `/` поиск, `Esc` назад, `⌘Q` выход.
- **Светлая и тёмная темы** — семантические цвета системы.
- **9 языков интерфейса** — 简体中文, 繁體中文, English, Deutsch, Français, Español, Italiano, Русский, 日本語; язык по умолчанию зависит от региона.
- **Интерфейс для агентов** — CLI `mijiabar` и stdio MCP-сервер; по умолчанию только чтение, есть белый список / полный доступ и диалоги подтверждения.
- **Два канала управления** — облачный MIoT RPC с запасным локальным miIO; AC partner (`lumi.acpartner.*`) управляется устаревшими локальными командами.

## Скриншоты

<p align="center">
  <img src="docs/screenshots/list-light.png" width="260" alt="">
  <img src="docs/screenshots/ac-cool-light.png" width="260" alt="">
  <img src="docs/screenshots/fan-light.png" width="260" alt="">
</p>
<p align="center"><b>Тёмная тема</b><br>
  <img src="docs/screenshots/list-dark.png" width="260" alt="">
  <img src="docs/screenshots/ac-heat-dark.png" width="260" alt="">
  <img src="docs/screenshots/light-dark.png" width="260" alt="">
</p>
<p align="center">
  <img src="docs/screenshots/plug-light.png" width="260" alt="">
  <img src="docs/screenshots/agent-light.png" width="260" alt="">
  <img src="docs/screenshots/login-light.png" width="260" alt="">
</p>

## Установка

1. Скачайте `MijiaBar-x.y.z.dmg` из [Releases](https://github.com/neardws/MijiaBar/releases/latest), перетащите MijiaBar в «Программы» и откройте. Релизные DMG подписаны Developer ID и нотаризованы Apple.
2. При первом управлении устройством разрешите доступ к **локальной сети** (нужно для управления по LAN).

> Сборки CI `*-unsigned.dmg` и локальные сборки подписаны ad-hoc; перед первым запуском выполните `xattr -dr com.apple.quarantine /Applications/MijiaBar.app`.

Требуется macOS 14 или новее, Apple silicon или Intel.

## Вход

1. Нажмите значок 🏠 в строке меню — появится QR-код.
2. Выберите регион сервера (по умолчанию «Материковый Китай»).
3. В приложении **Mi Home** нажмите **+ → Сканировать**, отсканируйте код и подтвердите на телефоне. Устройства загрузятся автоматически.

## Агенты / MCP

Откройте **Настройки → Интерфейс агента**, нажмите **Копировать инструкцию** и вставьте текст в Claude Code, Codex, Cursor или другой агент. Агент сам найдёт встроенный CLI, зарегистрирует MCP-сервер в своей конфигурации и проверит работу, получив список устройств. Тот же текст (с подставленным путём) выводит `mijiabar setup-prompt`:

```text
Пожалуйста, подключи MijiaBar (приложение в строке меню macOS для устройств Xiaomi Mi Home) как свой MCP-инструмент. Сделай это сам, по шагам:

1. Найди CLI. Он находится внутри приложения: /Applications/MijiaBar.app/Contents/Resources/bin/mijiabar. Выполни "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" --help, чтобы проверить его. Для работы из терминала создай ссылку: mkdir -p ~/.local/bin && ln -sf "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" ~/.local/bin/mijiabar
2. Зарегистрируй в своей конфигурации stdio MCP-сервер с именем mijia, командой "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" и аргументом mcp:
   - Claude Code: claude mcp add --scope user mijia -- "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" mcp
   - Codex: codex mcp add mijia -- "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" mcp
     (~/.codex/config.toml:
      [mcp_servers.mijia]
      command = "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar"
      args = ["mcp"])
   - Cursor (~/.cursor/mcp.json), Claude Desktop, …:
     {"mcpServers": {"mijia": {"command": "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar", "args": ["mcp"]}}}
   При необходимости перезагрузи MCP-серверы.
3. Инструменты: list_devices, get_device_state, set_property, run_action. Доступом управляю я в MijiaBar → Настройки → Интерфейс агента: по умолчанию «Чтение» (запись запрещена); «Белый список» разрешает только выбранные устройства; «Полный» разрешает все устройства. Если включено «Подтверждать каждую запись», каждая запись показывает на Mac окно, которое я должен одобрить. Никогда не меняй состояние устройства без моей просьбы.
4. Проверка: выполни "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" list (или вызови list_devices) и покажи мне список устройств. Если я не вошёл в аккаунт, попроси меня сначала войти по QR-коду в MijiaBar.
```

### Права доступа

| | |
| --- | --- |
| Выкл. | Агенты ничего не могут |
| Чтение (по умолчанию) | Только список устройств и чтение состояния |
| Белый список | Управление только отмеченными устройствами |
| Полный | Управление всеми устройствами |

Если включено **Подтверждать каждую запись**, каждое изменение агента показывает диалог macOS, который нужно одобрить.

### CLI

```bash
mijiabar list                     # list devices (--all, --refresh)
mijiabar get <device>             # read state as JSON
mijiabar set <device> <prop> <value>
mijiabar action <device> <action> [JSON array]
mijiabar mcp                      # stdio MCP server
mijiabar setup-prompt             # print the agent setup instructions
```

MCP-инструменты: `list_devices`, `get_device_state`, `set_property`, `run_action`.

## Сборка из исходников

```bash
git clone https://github.com/neardws/MijiaBar && cd MijiaBar
swift build
.build/debug/MijiaBarApp --snapshot docs/screenshots   # demo-data screenshots
scripts/package.sh   # dist/MijiaBar.app + DMG (signs & notarizes when a Developer ID is available)
# env: VERSION, SIGN_IDENTITY ("-" = ad-hoc), NOTARY_PROFILE (default MijiaBar-notary)
```

Структура: `Sources/MijiaCore` (облачное API, вход по QR, miIO, спецификации MIoT), `Sources/MijiaBarApp` (приложение SwiftUI), `Sources/mijiabar` (CLI + MCP). Переводы — в `i18n/*.tsv`; после правки запустите `scripts/gen-i18n.py`.

## Благодарности

Дизайн анимации — [@skyswordw](https://github.com/skyswordw) ([#1](https://github.com/neardws/MijiaBar/pull/1)). Детали протоколов — из [python-miio](https://github.com/rytilahti/python-miio), [Xiaomi-cloud-tokens-extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) и [ha_xiaomi_home](https://github.com/XiaoMi/ha_xiaomi_home). Интерфейс вдохновлён приложением для кондиционера от [@the_mcnaveen](https://x.com/the_mcnaveen).

Лицензия MIT.
