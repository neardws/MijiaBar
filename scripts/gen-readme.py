import os
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import subprocess
files={'en':'README.md','zh-Hans':'README.zh-CN.md','zh-Hant':'README.zh-TW.md','ru':'README.ru.md','de':'README.de.md','fr':'README.fr.md'}
names={'en':'English','zh-Hans':'简体中文','zh-Hant':'繁體中文','ru':'Русский','de':'Deutsch','fr':'Français'}
R='neardws/MijiaBar'
badges=f'''<p align="center">
  <a href="https://github.com/{R}/releases/latest"><img src="https://img.shields.io/github/v/release/{R}?label=release&color=blue" alt="Release"></a>
  <a href="https://github.com/{R}/releases"><img src="https://img.shields.io/github/downloads/{R}/total?color=brightgreen" alt="Downloads"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/{R}" alt="License"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/Apple-notarized-success?logo=apple" alt="Notarized">
  <a href="https://github.com/{R}/actions/workflows/build.yml"><img src="https://img.shields.io/github/actions/workflow/status/{R}/build.yml?branch=main&label=build" alt="Build"></a>
  <a href="https://github.com/{R}/stargazers"><img src="https://img.shields.io/github/stars/{R}?style=social" alt="Stars"></a>
</p>'''
T={}
T['en']=dict(tag="Control your Xiaomi Mi Home devices from the macOS menu bar — and let AI agents do it too.",
note="Unofficial project, not affiliated with Xiaomi. It uses the same cloud API as the Mi Home app plus the LAN miIO protocol.",
toc=["Features","Screenshots","Install","Sign in","Agent / MCP","Build from source","Credits"],
dark="Dark mode",
feat=["**QR sign-in** — scan with the Mi Home app, no password. Mainland China server by default; Europe, US, Russia, Singapore and India are one click away. Credentials stay in the macOS Keychain.",
"**Automatic device list** — all homes, rooms and shared devices with online state. Offline and long-unused devices are hidden by default.",
"**A page designed for each device type** — air conditioner, fan, light, plug, TV, speaker, camera, printer, kitchen appliances, water purifier, heater, dehumidifier and sensors, each with its own skeuomorphic illustration.",
"**Restrained motion** — fast, non-bouncy springs (< 300 ms); fan blades spin with speed, the TV screen glows, heaters radiate; the power button ripples; sliders track 1:1, snap and tick the trackpad. Reduce Motion is respected.",
"**Keyboard first** — `↑/↓` select, `↩` open, `Space` power, `←/→` adjust the main slider, `/` search, `Esc` back, `⌘Q` quit.",
"**Light & dark** — follows the system appearance using semantic colors.",
"**9 UI languages** — 简体中文, 繁體中文, English, Deutsch, Français, Español, Italiano, Русский, 日本語; region-aware defaults.",
"**Agent interface** — `mijiabar` CLI and a stdio MCP server, read-only by default, with allowlist / full access and optional confirmation dialogs.",
"**Two control paths** — Xiaomi cloud MIoT RPC with LAN miIO fallback; AC partners (`lumi.acpartner.*`) use legacy LAN commands."],
inst=["Download `MijiaBar-x.y.z.dmg` from [Releases](https://github.com/neardws/MijiaBar/releases/latest), drag MijiaBar into Applications and open it. Release DMGs are Developer ID signed and notarized by Apple.",
"The first time you control a device, allow the **Local Network** permission (needed for LAN control)."],
inst_note="CI `*-unsigned.dmg` builds and your own local builds are ad-hoc signed; run `xattr -dr com.apple.quarantine /Applications/MijiaBar.app` before first launch.",
req="Requires macOS 14 or later, Apple silicon or Intel.",
login=["Click the 🏠 icon in the menu bar; a QR code appears.","Pick your server region (Mainland China by default).","In the **Mi Home** app tap **+ → Scan**, scan the code and confirm on the phone. Devices load automatically."],
agent_intro="Open **Settings → Agent interface**, click **Copy setup instructions** and paste the text into Claude Code, Codex, Cursor or any other agent. The agent finds the bundled CLI, registers the MCP server in its own config and verifies by listing your devices. The same text (with the path filled in) is printed by `mijiabar setup-prompt`:",
perm_h="Permissions", perm=[("Off","Agents can do nothing"),("Read (default)","List devices and read state only"),("Allowlist","Control only the devices you tick"),("Full","Control every device")],
confirm="With **Confirm every write** on, every change an agent makes shows a macOS dialog that you must approve.",
cli_h="CLI", tools="MCP tools: `list_devices`, `get_device_state`, `set_property`, `run_action`.",
build_note="Project layout: `Sources/MijiaCore` (cloud API, QR login, miIO, MIoT spec), `Sources/MijiaBarApp` (SwiftUI app), `Sources/mijiabar` (CLI + MCP). Translations live in `i18n/*.tsv`; run `scripts/gen-i18n.py` after editing.",
credits="Motion design contributed by [@skyswordw](https://github.com/skyswordw) ([#1](https://github.com/neardws/MijiaBar/pull/1)). Protocol details from [python-miio](https://github.com/rytilahti/python-miio), [Xiaomi-cloud-tokens-extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) and [ha_xiaomi_home](https://github.com/XiaoMi/ha_xiaomi_home). UI inspired by [@the_mcnaveen](https://x.com/the_mcnaveen)'s AC menu bar app.",
lic="MIT License.")
T['zh-Hans']=dict(tag="在 macOS 菜单栏控制米家设备，也可以交给 AI Agent 来控制。",
note="非小米官方项目。使用与米家 App 相同的云端接口和局域网 miIO 协议。",
toc=["功能","截图","安装","登录","Agent / MCP","从源码构建","致谢"],dark="深色模式",
feat=["**扫码登录**：用米家 App 扫一扫，无需密码。默认中国大陆服务器，也可切换欧洲、美国、俄罗斯、新加坡、印度。凭据只存在 macOS 钥匙串。",
"**自动获取设备**：拉取所有家庭、房间和共享设备及在线状态；离线和久未使用的设备默认隐藏。",
"**每类设备单独设计**：空调、风扇、灯、插座、电视、音箱、摄像机、打印机、厨房电器、净水器、取暖器、除湿机、传感器，各有拟物插画。",
"**克制的动效**：无回弹的快速弹簧（< 300ms）；风扇按风速转动、电视屏幕发光、取暖器热浪；电源键涟漪；滑条 1:1 跟手、松手吸附、跨档触控板轻触。遵循「减弱动态效果」。",
"**键盘优先**：`↑/↓` 选择、`↩` 打开、`空格` 开关、`←/→` 调节主滑条、`/` 搜索、`Esc` 返回、`⌘Q` 退出。",
"**浅色 / 深色**：使用系统语义色，自动跟随外观。",
"**9 种界面语言**：简体中文、繁體中文、English、Deutsch、Français、Español、Italiano、Русский、日本語，按地区推荐默认语言。",
"**Agent 接口**：`mijiabar` 命令行和 stdio MCP 服务器，默认只读，可选白名单 / 全部权限，写操作可弹窗确认。",
"**双通道控制**：小米云 MIoT RPC，失败时回落局域网 miIO；空调伴侣（`lumi.acpartner.*`）使用旧版局域网命令。"],
inst=["从 [Releases](https://github.com/neardws/MijiaBar/releases/latest) 下载 `MijiaBar-x.y.z.dmg`，把 MijiaBar 拖进「应用程序」后打开。正式版已用 Developer ID 签名并通过 Apple 公证。","第一次控制设备时，请允许「本地网络」权限（局域网直连需要）。"],
inst_note="CI 构建的 `*-unsigned.dmg` 和自己本地打包的版本为 ad-hoc 签名，首次打开前执行 `xattr -dr com.apple.quarantine /Applications/MijiaBar.app`。",
req="系统要求：macOS 14 及以上，支持 Apple 芯片和 Intel。",
login=["点菜单栏的 🏠 图标，会显示二维码。","选择服务器地区（默认中国大陆）。","打开手机 **米家 App** →「+」→「扫一扫」，扫码并在手机上确认，设备会自动加载。"],
agent_intro="打开 **设置 → Agent 接口**，点 **复制安装说明**，粘贴给 Claude Code、Codex、Cursor 等 Agent。Agent 会自己找到内置 CLI、在自己的配置里注册 MCP 服务器，并列出设备完成验证。`mijiabar setup-prompt` 会输出同样的内容（路径已填好）：",
perm_h="权限", perm=[("关闭","Agent 什么都不能做"),("只读（默认）","只能列设备、读状态"),("白名单","只能控制你勾选的设备"),("全部","可以控制所有设备")],
confirm="开启 **每次写操作弹窗确认** 后，Agent 的每次控制都会弹出系统对话框，需要你点「允许」。",
cli_h="命令行", tools="MCP 工具：`list_devices`、`get_device_state`、`set_property`、`run_action`。",
build_note="项目结构：`Sources/MijiaCore`（云端 API、扫码登录、miIO、MIoT 规格）、`Sources/MijiaBarApp`（SwiftUI 应用）、`Sources/mijiabar`（CLI + MCP）。翻译在 `i18n/*.tsv`，修改后运行 `scripts/gen-i18n.py`。",
credits="动效设计由 [@skyswordw](https://github.com/skyswordw) 贡献（[#1](https://github.com/neardws/MijiaBar/pull/1)）。协议细节参考 [python-miio](https://github.com/rytilahti/python-miio)、[Xiaomi-cloud-tokens-extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) 和 [ha_xiaomi_home](https://github.com/XiaoMi/ha_xiaomi_home)。界面灵感来自 [@the_mcnaveen](https://x.com/the_mcnaveen) 的空调菜单栏应用。",
lic="MIT 许可证。")
T['zh-Hant']=dict(tag="在 macOS 選單列控制米家裝置，也可以交給 AI Agent 來控制。",
note="非小米官方專案。使用與米家 App 相同的雲端介面和區域網路 miIO 協定。",
toc=["功能","截圖","安裝","登入","Agent / MCP","從原始碼建置","致謝"],dark="深色模式",
feat=["**掃碼登入**：用米家 App 掃一掃，免密碼。預設中國大陸伺服器，也可切換歐洲、美國、俄羅斯、新加坡、印度。憑證只存在 macOS 鑰匙圈。",
"**自動取得裝置**：載入所有家庭、房間和共享裝置及上線狀態；離線和久未使用的裝置預設隱藏。",
"**每類裝置單獨設計**：冷氣、電風扇、燈、插座、電視、音箱、攝影機、印表機、廚房電器、淨水器、電暖器、除濕機、感測器，各有擬物插圖。",
"**克制的動態效果**：無回彈的快速彈簧（< 300ms）；風扇依風速轉動、電視螢幕發光、電暖器熱浪；電源鍵漣漪；滑桿 1:1 跟手、放開吸附、跨檔觸控板輕觸。遵循「減少動態效果」。",
"**鍵盤優先**：`↑/↓` 選擇、`↩` 開啟、`空白鍵` 開關、`←/→` 調整主滑桿、`/` 搜尋、`Esc` 返回、`⌘Q` 結束。",
"**淺色 / 深色**：使用系統語意色彩，自動跟隨外觀。",
"**9 種介面語言**：简体中文、繁體中文、English、Deutsch、Français、Español、Italiano、Русский、日本語，依地區建議預設語言。",
"**Agent 介面**：`mijiabar` 命令列和 stdio MCP 伺服器，預設唯讀，可選白名單 / 全部權限，寫入操作可跳出視窗確認。",
"**雙通道控制**：小米雲端 MIoT RPC，失敗時退回區域網路 miIO；空調夥伴（`lumi.acpartner.*`）使用舊版區域網路指令。"],
inst=["從 [Releases](https://github.com/neardws/MijiaBar/releases/latest) 下載 `MijiaBar-x.y.z.dmg`，把 MijiaBar 拖進「應用程式」後開啟。正式版已用 Developer ID 簽署並通過 Apple 公證。","第一次控制裝置時，請允許「本機網路」權限（區域網路直連需要）。"],
inst_note="CI 建置的 `*-unsigned.dmg` 和自行本機打包的版本為 ad-hoc 簽署，首次開啟前執行 `xattr -dr com.apple.quarantine /Applications/MijiaBar.app`。",
req="系統需求：macOS 14 以上，支援 Apple 晶片和 Intel。",
login=["點選單列的 🏠 圖示，會顯示 QR 碼。","選擇伺服器地區（預設為中國大陸）。","開啟手機 **米家 App** →「+」→「掃一掃」，掃描 QR 碼並在手機上確認，裝置會自動載入。"],
agent_intro="開啟 **設定 → Agent 介面**，點 **複製安裝說明**，貼給 Claude Code、Codex、Cursor 等 Agent。Agent 會自己找到內建 CLI、在自己的設定裡註冊 MCP 伺服器，並列出裝置完成驗證。`mijiabar setup-prompt` 會輸出同樣的內容（路徑已填好）：",
perm_h="權限", perm=[("關閉","Agent 什麼都不能做"),("唯讀（預設）","只能列出裝置、讀取狀態"),("白名單","只能控制你勾選的裝置"),("全部","可以控制所有裝置")],
confirm="開啟 **每次寫入操作跳出視窗確認** 後，Agent 的每次控制都會跳出系統對話框，需要你點「允許」。",
cli_h="命令列", tools="MCP 工具：`list_devices`、`get_device_state`、`set_property`、`run_action`。",
build_note="專案結構：`Sources/MijiaCore`（雲端 API、掃碼登入、miIO、MIoT 規格）、`Sources/MijiaBarApp`（SwiftUI 應用程式）、`Sources/mijiabar`（CLI + MCP）。翻譯在 `i18n/*.tsv`，修改後執行 `scripts/gen-i18n.py`。",
credits="動態效果設計由 [@skyswordw](https://github.com/skyswordw) 貢獻（[#1](https://github.com/neardws/MijiaBar/pull/1)）。協定細節參考 [python-miio](https://github.com/rytilahti/python-miio)、[Xiaomi-cloud-tokens-extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) 和 [ha_xiaomi_home](https://github.com/XiaoMi/ha_xiaomi_home)。介面靈感來自 [@the_mcnaveen](https://x.com/the_mcnaveen) 的冷氣選單列 App。",
lic="MIT 授權。")
T['ru']=dict(tag="Управляйте устройствами Xiaomi Mi Home из строки меню macOS — или доверьте это AI-агентам.",
note="Неофициальный проект, не связан с Xiaomi. Использует то же облачное API, что и приложение Mi Home, а также локальный протокол miIO.",
toc=["Возможности","Скриншоты","Установка","Вход","Агенты / MCP","Сборка из исходников","Благодарности"],dark="Тёмная тема",
feat=["**Вход по QR-коду** — отсканируйте в приложении Mi Home, без пароля. По умолчанию сервер «Материковый Китай»; Европа, США, Россия, Сингапур и Индия — в один клик. Данные входа хранятся в связке ключей macOS.",
"**Автоматический список устройств** — все дома, комнаты и общие устройства со статусом сети. Устройства не в сети и давно не используемые скрыты по умолчанию.",
"**Отдельная страница для каждого типа** — кондиционер, вентилятор, свет, розетка, телевизор, колонка, камера, принтер, кухонная техника, фильтр для воды, обогреватель, осушитель и датчики, у каждого своя скевоморфная иллюстрация.",
"**Сдержанная анимация** — быстрые пружины без отскока (< 300 мс); лопасти вентилятора крутятся по скорости, экран ТВ светится, обогреватель излучает тепло; кнопка питания даёт волну; ползунки следуют за курсором, примагничиваются и дают отклик трекпада. Учитывается «Уменьшение движения».",
"**Клавиатура** — `↑/↓` выбор, `↩` открыть, `Пробел` питание, `←/→` основной ползунок, `/` поиск, `Esc` назад, `⌘Q` выход.",
"**Светлая и тёмная темы** — семантические цвета системы.",
"**9 языков интерфейса** — 简体中文, 繁體中文, English, Deutsch, Français, Español, Italiano, Русский, 日本語; язык по умолчанию зависит от региона.",
"**Интерфейс для агентов** — CLI `mijiabar` и stdio MCP-сервер; по умолчанию только чтение, есть белый список / полный доступ и диалоги подтверждения.",
"**Два канала управления** — облачный MIoT RPC с запасным локальным miIO; AC partner (`lumi.acpartner.*`) управляется устаревшими локальными командами."],
inst=["Скачайте `MijiaBar-x.y.z.dmg` из [Releases](https://github.com/neardws/MijiaBar/releases/latest), перетащите MijiaBar в «Программы» и откройте. Релизные DMG подписаны Developer ID и нотаризованы Apple.","При первом управлении устройством разрешите доступ к **локальной сети** (нужно для управления по LAN)."],
inst_note="Сборки CI `*-unsigned.dmg` и локальные сборки подписаны ad-hoc; перед первым запуском выполните `xattr -dr com.apple.quarantine /Applications/MijiaBar.app`.",
req="Требуется macOS 14 или новее, Apple silicon или Intel.",
login=["Нажмите значок 🏠 в строке меню — появится QR-код.","Выберите регион сервера (по умолчанию «Материковый Китай»).","В приложении **Mi Home** нажмите **+ → Сканировать**, отсканируйте код и подтвердите на телефоне. Устройства загрузятся автоматически."],
agent_intro="Откройте **Настройки → Интерфейс агента**, нажмите **Копировать инструкцию** и вставьте текст в Claude Code, Codex, Cursor или другой агент. Агент сам найдёт встроенный CLI, зарегистрирует MCP-сервер в своей конфигурации и проверит работу, получив список устройств. Тот же текст (с подставленным путём) выводит `mijiabar setup-prompt`:",
perm_h="Права доступа", perm=[("Выкл.","Агенты ничего не могут"),("Чтение (по умолчанию)","Только список устройств и чтение состояния"),("Белый список","Управление только отмеченными устройствами"),("Полный","Управление всеми устройствами")],
confirm="Если включено **Подтверждать каждую запись**, каждое изменение агента показывает диалог macOS, который нужно одобрить.",
cli_h="CLI", tools="MCP-инструменты: `list_devices`, `get_device_state`, `set_property`, `run_action`.",
build_note="Структура: `Sources/MijiaCore` (облачное API, вход по QR, miIO, спецификации MIoT), `Sources/MijiaBarApp` (приложение SwiftUI), `Sources/mijiabar` (CLI + MCP). Переводы — в `i18n/*.tsv`; после правки запустите `scripts/gen-i18n.py`.",
credits="Дизайн анимации — [@skyswordw](https://github.com/skyswordw) ([#1](https://github.com/neardws/MijiaBar/pull/1)). Детали протоколов — из [python-miio](https://github.com/rytilahti/python-miio), [Xiaomi-cloud-tokens-extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) и [ha_xiaomi_home](https://github.com/XiaoMi/ha_xiaomi_home). Интерфейс вдохновлён приложением для кондиционера от [@the_mcnaveen](https://x.com/the_mcnaveen).",
lic="Лицензия MIT.")
T['de']=dict(tag="Steuere deine Xiaomi-Mi-Home-Geräte über die macOS-Menüleiste – oder lass es KI-Agents erledigen.",
note="Inoffizielles Projekt ohne Verbindung zu Xiaomi. Es nutzt dieselbe Cloud-API wie die Mi-Home-App sowie das LAN-Protokoll miIO.",
toc=["Funktionen","Screenshots","Installation","Anmeldung","Agents / MCP","Aus dem Quellcode bauen","Danksagung"],dark="Dunkelmodus",
feat=["**QR-Anmeldung** – mit der Mi-Home-App scannen, kein Passwort. Standardmäßig Server Festlandchina; Europa, USA, Russland, Singapur und Indien sind einen Klick entfernt. Zugangsdaten bleiben im macOS-Schlüsselbund.",
"**Automatische Geräteliste** – alle Zuhause, Räume und geteilten Geräte mit Online-Status. Offline- und lange ungenutzte Geräte sind standardmäßig ausgeblendet.",
"**Eigene Seite pro Gerätetyp** – Klimaanlage, Ventilator, Licht, Steckdose, TV, Lautsprecher, Kamera, Drucker, Küchengeräte, Wasserfilter, Heizgerät, Luftentfeuchter und Sensoren, jeweils mit skeuomorpher Illustration.",
"**Zurückhaltende Animationen** – schnelle Federn ohne Nachschwingen (< 300 ms); Ventilatorflügel drehen sich je nach Stufe, der TV-Bildschirm leuchtet, Heizgeräte strahlen; der Ein/Aus-Knopf zieht eine Welle; Schieberegler folgen 1:1, rasten ein und geben haptisches Feedback. „Bewegung reduzieren“ wird respektiert.",
"**Tastatur zuerst** – `↑/↓` auswählen, `↩` öffnen, `Leertaste` Ein/Aus, `←/→` Hauptregler, `/` suchen, `Esc` zurück, `⌘Q` beenden.",
"**Hell & dunkel** – folgt dem Systemerscheinungsbild mit semantischen Farben.",
"**9 Sprachen** – 简体中文, 繁體中文, English, Deutsch, Français, Español, Italiano, Русский, 日本語; Standard je nach Region.",
"**Agent-Schnittstelle** – `mijiabar`-CLI und stdio-MCP-Server, standardmäßig nur lesend, mit Positivliste / Vollzugriff und optionalen Bestätigungsdialogen.",
"**Zwei Steuerwege** – Xiaomi-Cloud-MIoT-RPC mit LAN-miIO als Rückfall; AC-Partner (`lumi.acpartner.*`) nutzen ältere LAN-Befehle."],
inst=["Lade `MijiaBar-x.y.z.dmg` unter [Releases](https://github.com/neardws/MijiaBar/releases/latest) herunter, ziehe MijiaBar in „Programme“ und öffne es. Release-DMGs sind mit Developer ID signiert und von Apple notarisiert.","Erlaube beim ersten Steuern eines Geräts den Zugriff auf das **lokale Netzwerk** (für die LAN-Steuerung nötig)."],
inst_note="CI-Builds `*-unsigned.dmg` und eigene lokale Builds sind ad-hoc signiert; vor dem ersten Start `xattr -dr com.apple.quarantine /Applications/MijiaBar.app` ausführen.",
req="Benötigt macOS 14 oder neuer, Apple Silicon oder Intel.",
login=["Klicke auf das 🏠-Symbol in der Menüleiste; ein QR-Code erscheint.","Wähle die Serverregion (Standard: Festlandchina).","Tippe in der **Mi-Home**-App auf **+ → Scannen**, scanne den Code und bestätige am Telefon. Die Geräte werden automatisch geladen."],
agent_intro="Öffne **Einstellungen → Agent-Schnittstelle**, klicke auf **Einrichtungsanleitung kopieren** und füge den Text in Claude Code, Codex, Cursor oder einen anderen Agent ein. Der Agent findet das mitgelieferte CLI, registriert den MCP-Server in seiner eigenen Konfiguration und prüft das Ergebnis, indem er deine Geräte auflistet. Denselben Text (mit eingesetztem Pfad) gibt `mijiabar setup-prompt` aus:",
perm_h="Berechtigungen", perm=[("Aus","Agents können nichts tun"),("Lesen (Standard)","Nur Geräte auflisten und Status lesen"),("Positivliste","Nur die angehakten Geräte steuern"),("Voll","Alle Geräte steuern")],
confirm="Ist **Jeden Schreibvorgang bestätigen** aktiv, zeigt jede Änderung eines Agents einen macOS-Dialog, den du bestätigen musst.",
cli_h="CLI", tools="MCP-Werkzeuge: `list_devices`, `get_device_state`, `set_property`, `run_action`.",
build_note="Aufbau: `Sources/MijiaCore` (Cloud-API, QR-Anmeldung, miIO, MIoT-Spezifikationen), `Sources/MijiaBarApp` (SwiftUI-App), `Sources/mijiabar` (CLI + MCP). Übersetzungen liegen in `i18n/*.tsv`; danach `scripts/gen-i18n.py` ausführen.",
credits="Animationsdesign von [@skyswordw](https://github.com/skyswordw) ([#1](https://github.com/neardws/MijiaBar/pull/1)). Protokolldetails aus [python-miio](https://github.com/rytilahti/python-miio), [Xiaomi-cloud-tokens-extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) und [ha_xiaomi_home](https://github.com/XiaoMi/ha_xiaomi_home). UI inspiriert von der Klimaanlagen-Menüleisten-App von [@the_mcnaveen](https://x.com/the_mcnaveen).",
lic="MIT-Lizenz.")
T['fr']=dict(tag="Contrôle tes appareils Xiaomi Mi Home depuis la barre des menus macOS — ou confie-les à des agents IA.",
note="Projet non officiel, sans lien avec Xiaomi. Il utilise la même API cloud que l’app Mi Home ainsi que le protocole LAN miIO.",
toc=["Fonctionnalités","Captures","Installation","Connexion","Agents / MCP","Compiler depuis les sources","Remerciements"],dark="Mode sombre",
feat=["**Connexion par QR code** — scanne avec l’app Mi Home, sans mot de passe. Serveur Chine continentale par défaut ; Europe, États-Unis, Russie, Singapour et Inde en un clic. Les identifiants restent dans le trousseau macOS.",
"**Liste d’appareils automatique** — toutes les maisons, pièces et appareils partagés avec leur état. Les appareils hors ligne ou inutilisés depuis longtemps sont masqués par défaut.",
"**Une page conçue pour chaque type** — climatiseur, ventilateur, lumière, prise, TV, enceinte, caméra, imprimante, cuisine, purificateur d’eau, radiateur, déshumidificateur et capteurs, chacun avec son illustration skeuomorphe.",
"**Animations sobres** — ressorts rapides sans rebond (< 300 ms) ; les pales tournent selon la vitesse, l’écran TV s’illumine, le radiateur rayonne ; le bouton d’alimentation fait une onde ; les curseurs suivent 1:1, s’aimantent et donnent un retour haptique. « Réduire les animations » est respecté.",
"**Clavier d’abord** — `↑/↓` choisir, `↩` ouvrir, `Espace` marche/arrêt, `←/→` curseur principal, `/` rechercher, `Esc` retour, `⌘Q` quitter.",
"**Clair et sombre** — suit l’apparence du système avec des couleurs sémantiques.",
"**9 langues** — 简体中文, 繁體中文, English, Deutsch, Français, Español, Italiano, Русский, 日本語 ; langue par défaut selon la région.",
"**Interface agent** — CLI `mijiabar` et serveur MCP stdio, en lecture seule par défaut, avec liste autorisée / accès complet et confirmations facultatives.",
"**Deux canaux de contrôle** — MIoT RPC via le cloud Xiaomi avec repli LAN miIO ; les AC partner (`lumi.acpartner.*`) utilisent les anciennes commandes LAN."],
inst=["Télécharge `MijiaBar-x.y.z.dmg` depuis les [Releases](https://github.com/neardws/MijiaBar/releases/latest), glisse MijiaBar dans Applications et ouvre-le. Les DMG publiés sont signés Developer ID et notarisés par Apple.","La première fois que tu contrôles un appareil, autorise l’accès au **réseau local** (nécessaire pour le contrôle LAN)."],
inst_note="Les builds CI `*-unsigned.dmg` et tes builds locaux sont signés ad hoc ; exécute `xattr -dr com.apple.quarantine /Applications/MijiaBar.app` avant le premier lancement.",
req="Nécessite macOS 14 ou ultérieur, Apple silicon ou Intel.",
login=["Clique sur l’icône 🏠 dans la barre des menus ; un QR code s’affiche.","Choisis la région du serveur (Chine continentale par défaut).","Dans l’app **Mi Home**, touche **+ → Scanner**, scanne le code et confirme sur le téléphone. Les appareils se chargent automatiquement."],
agent_intro="Ouvre **Réglages → Interface agent**, clique sur **Copier les instructions** et colle le texte dans Claude Code, Codex, Cursor ou tout autre agent. L’agent trouve la CLI intégrée, enregistre le serveur MCP dans sa propre configuration et vérifie en listant tes appareils. Le même texte (chemin renseigné) est affiché par `mijiabar setup-prompt` :",
perm_h="Autorisations", perm=[("Éteint","Les agents ne peuvent rien faire"),("Lecture (par défaut)","Lister les appareils et lire l’état uniquement"),("Liste autorisée","Contrôler uniquement les appareils cochés"),("Complet","Contrôler tous les appareils")],
confirm="Avec **Confirmer chaque écriture**, chaque modification d’un agent affiche une fenêtre macOS que tu dois approuver.",
cli_h="CLI", tools="Outils MCP : `list_devices`, `get_device_state`, `set_property`, `run_action`.",
build_note="Structure : `Sources/MijiaCore` (API cloud, connexion QR, miIO, spécifications MIoT), `Sources/MijiaBarApp` (app SwiftUI), `Sources/mijiabar` (CLI + MCP). Les traductions sont dans `i18n/*.tsv` ; lance `scripts/gen-i18n.py` après modification.",
credits="Design des animations par [@skyswordw](https://github.com/skyswordw) ([#1](https://github.com/neardws/MijiaBar/pull/1)). Détails des protocoles issus de [python-miio](https://github.com/rytilahti/python-miio), [Xiaomi-cloud-tokens-extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) et [ha_xiaomi_home](https://github.com/XiaoMi/ha_xiaomi_home). Interface inspirée de l’app de climatisation de [@the_mcnaveen](https://x.com/the_mcnaveen).",
lic="Licence MIT.")
import re
S="~/Library/Application Support/MijiaBar/"
X={
'en':("Auto-hidden devices",["A device is collapsed to the bottom of the list by default when either is true:","the cloud reports it offline (`isOnline = false`);","the cloud returns a last-online time (`last_online` / `lastOnline` / `last_online_time`) older than 30 days.","Click the eye button or **Show** to reveal them, or turn on **Settings → Devices → Show hidden devices**. Right-click a device to hide / unhide it manually — a manual choice always overrides the automatic rule."],
 "Where data is stored",["Sign-in session: macOS Keychain, service `com.neardws.MijiaBar` (account `session`). Signing out deletes it.",f"Device cache `devices.json`, preferences `prefs.json` (favorites, aliases, hidden flags, region), agent policy `agent.json`, and MIoT spec cache `spec-index.json` + `specs/<model>.json` — all in `{S}`, written with file mode 600.","UI language: `MijiaBarLang` in UserDefaults (shared by the app and CLI; `MIJIABAR_LANG` overrides it).","Nothing is sent anywhere except Xiaomi's servers, your devices on the LAN, and miot-spec.org (public spec downloads)."]),
'zh-Hans':("默认隐藏规则",["满足任一条件的设备默认收起到列表底部：","云端报告离线（`isOnline = false`）；","云端返回了最后在线时间（`last_online` / `lastOnline` / `last_online_time`），且超过 30 天。","点眼睛按钮或「显示」可以展开，也可以在 **设置 → 设备管理 → 显示已隐藏的设备** 中打开。右键设备可以手动「隐藏 / 取消隐藏」，手动设置始终优先于自动规则。"],
 "数据存放",["登录凭据：macOS 钥匙串，服务名 `com.neardws.MijiaBar`（账户 `session`），退出登录即删除。",f"设备缓存 `devices.json`、偏好 `prefs.json`（收藏、别名、隐藏、地区）、Agent 权限 `agent.json`、MIoT 规格缓存 `spec-index.json` 和 `specs/<型号>.json`，都在 `{S}`，文件权限 600。","界面语言：UserDefaults 的 `MijiaBarLang`（App 和 CLI 共用，环境变量 `MIJIABAR_LANG` 可覆盖）。","除了小米服务器、局域网内的设备和 miot-spec.org（下载公开规格）之外，不向任何地方发送数据。"]),
'zh-Hant':("預設隱藏規則",["符合任一條件的裝置預設收合到清單底部：","雲端回報離線（`isOnline = false`）；","雲端回傳了最後上線時間（`last_online` / `lastOnline` / `last_online_time`），且超過 30 天。","按眼睛按鈕或「顯示」可以展開，也可以在 **設定 → 裝置管理 → 顯示已隱藏的裝置** 中開啟。在裝置上按右鍵可以手動「隱藏 / 取消隱藏」，手動設定一律優先於自動規則。"],
 "資料存放位置",["登入憑證：macOS 鑰匙圈，服務名稱 `com.neardws.MijiaBar`（帳號 `session`），登出即刪除。",f"裝置快取 `devices.json`、偏好設定 `prefs.json`（收藏、別名、隱藏、地區）、Agent 權限 `agent.json`、MIoT 規格快取 `spec-index.json` 和 `specs/<型號>.json`，都在 `{S}`，檔案權限 600。","介面語言：UserDefaults 的 `MijiaBarLang`（App 與 CLI 共用，環境變數 `MIJIABAR_LANG` 可覆寫）。","除了小米伺服器、區域網路內的裝置和 miot-spec.org（下載公開規格）之外，不會將資料傳送到任何地方。"]),
'ru':("Автоматически скрытые устройства",["Устройство по умолчанию сворачивается в конец списка, если выполняется любое условие:","облако сообщает, что оно не в сети (`isOnline = false`);","облако возвращает время последнего подключения (`last_online` / `lastOnline` / `last_online_time`) старше 30 дней.","Нажмите кнопку с глазом или **Показать**, либо включите **Настройки → Устройства → Показывать скрытые устройства**. Правый клик по устройству позволяет скрыть или показать его вручную — ручной выбор всегда важнее автоматического правила."],
 "Где хранятся данные",["Сессия входа: связка ключей macOS, служба `com.neardws.MijiaBar` (учётная запись `session`). Удаляется при выходе.",f"Кэш устройств `devices.json`, настройки `prefs.json` (избранное, псевдонимы, скрытие, регион), политика агента `agent.json` и кэш спецификаций MIoT `spec-index.json` + `specs/<model>.json` — всё в `{S}`, права доступа 600.","Язык интерфейса: `MijiaBarLang` в UserDefaults (общий для приложения и CLI; переменная `MIJIABAR_LANG` имеет приоритет).","Данные отправляются только на серверы Xiaomi, на ваши устройства в локальной сети и на miot-spec.org (загрузка публичных спецификаций)."]),
'de':("Automatisch ausgeblendete Geräte",["Ein Gerät wird standardmäßig ans Listenende eingeklappt, wenn eine Bedingung zutrifft:","die Cloud meldet es als offline (`isOnline = false`);","die Cloud liefert einen letzten Online-Zeitpunkt (`last_online` / `lastOnline` / `last_online_time`), der über 30 Tage zurückliegt.","Über das Augen-Symbol oder **Anzeigen** einblenden, oder **Einstellungen → Geräte → Ausgeblendete Geräte anzeigen** aktivieren. Per Rechtsklick lässt sich ein Gerät manuell aus- oder einblenden – die manuelle Wahl hat immer Vorrang vor der Automatik."],
 "Wo Daten gespeichert werden",["Anmeldesitzung: macOS-Schlüsselbund, Dienst `com.neardws.MijiaBar` (Account `session`). Wird beim Abmelden gelöscht.",f"Gerätecache `devices.json`, Einstellungen `prefs.json` (Favoriten, Aliasse, Ausblendungen, Region), Agent-Richtlinie `agent.json` und MIoT-Spezifikationscache `spec-index.json` + `specs/<Modell>.json` – alles in `{S}`, mit Dateirechten 600.","UI-Sprache: `MijiaBarLang` in den UserDefaults (von App und CLI gemeinsam genutzt; `MIJIABAR_LANG` überschreibt sie).","Daten gehen nur an Xiaomi-Server, an deine Geräte im LAN und an miot-spec.org (öffentliche Spezifikationen)."]),
'fr':("Appareils masqués automatiquement",["Un appareil est replié en bas de la liste par défaut si l’une de ces conditions est vraie :","le cloud le signale hors ligne (`isOnline = false`) ;","le cloud renvoie une dernière connexion (`last_online` / `lastOnline` / `last_online_time`) de plus de 30 jours.","Clique sur l’œil ou **Afficher**, ou active **Réglages → Appareils → Afficher les appareils masqués**. Un clic droit sur un appareil permet de le masquer ou l’afficher manuellement — le choix manuel l’emporte toujours sur la règle automatique."],
 "Où sont stockées les données",["Session de connexion : trousseau macOS, service `com.neardws.MijiaBar` (compte `session`). Supprimée à la déconnexion.",f"Cache des appareils `devices.json`, préférences `prefs.json` (favoris, alias, masquage, région), politique agent `agent.json` et cache des spécifications MIoT `spec-index.json` + `specs/<modèle>.json` — tout dans `{S}`, avec les droits 600.","Langue de l’interface : `MijiaBarLang` dans les UserDefaults (partagée par l’app et la CLI ; `MIJIABAR_LANG` a priorité).","Aucune donnée n’est envoyée ailleurs qu’aux serveurs Xiaomi, à tes appareils sur le réseau local et à miot-spec.org (spécifications publiques)."]),
}

DOCL={'en':('Full step-by-step instructions for agents:',''),'zh-Hans':('写给 Agent 的完整步骤：','.zh-CN'),'zh-Hant':('寫給 Agent 的完整步驟：','.zh-TW'),
      'ru':('Полная пошаговая инструкция для агентов:','.ru'),'de':('Vollständige Schritt-für-Schritt-Anleitung für Agents:','.de'),'fr':('Instructions complètes pour les agents :','.fr')}
def anchor(h): return re.sub(r'[^\w\- ]','',h.lower()).strip().replace(' ','-')
cli='''```bash
mijiabar list                     # list devices (--all, --refresh)
mijiabar get <device>             # read state as JSON
mijiabar set <device> <prop> <value>
mijiabar action <device> <action> [JSON array]
mijiabar mcp                      # stdio MCP server
mijiabar setup-prompt             # print the agent setup instructions
```'''
build='''```bash
git clone https://github.com/neardws/MijiaBar && cd MijiaBar
swift build
.build/debug/MijiaBarApp --snapshot docs/screenshots   # demo-data screenshots
scripts/package.sh   # dist/MijiaBar.app + DMG (signs & notarizes when a Developer ID is available)
# env: VERSION, SIGN_IDENTITY ("-" = ad-hoc), NOTARY_PROFILE (default MijiaBar-notary)
```'''
for lang,fn in files.items():
    t=T[lang]
    sw=' · '.join(f'<b>{names[l]}</b>' if l==lang else f'<a href="{f}">{names[l]}</a>' for l,f in files.items())
    hh,hl,dh,dl=X[lang]
    toc=t['toc'][:4]+[hh]+t['toc'][4:6]+[dh]+t['toc'][6:]
    prompt=subprocess.run(['.build/debug/mijiabar','setup-prompt'],env={**os.environ,'MIJIABAR_LANG':lang},capture_output=True,text=True).stdout.rstrip()
    o=[f'<p align="center"><img src="Resources/AppIcon.png" width="96" alt="MijiaBar"></p>' if os.path.exists('Resources/AppIcon.png') else '',
       '<h1 align="center">MijiaBar</h1>',f'<p align="center">{t["tag"]}</p>','',badges,'',f'<p align="center">{sw}</p>','',
       f'> {t["note"]}','',
       '<p align="center"><img src="docs/screenshots/demo.gif" width="300" alt="demo"></p>','',
       ' · '.join(f'[{h}](#{anchor(h)})' for h in toc),'',
       f'## {toc[0]}','']+[f'- {x}' for x in t['feat']]+['',
       f'## {toc[1]}','',
       '<p align="center">\n  <img src="docs/screenshots/list-light.png" width="260" alt="">\n  <img src="docs/screenshots/ac-cool-light.png" width="260" alt="">\n  <img src="docs/screenshots/fan-light.png" width="260" alt="">\n</p>',
       f'<p align="center"><b>{t["dark"]}</b><br>\n  <img src="docs/screenshots/list-dark.png" width="260" alt="">\n  <img src="docs/screenshots/ac-heat-dark.png" width="260" alt="">\n  <img src="docs/screenshots/light-dark.png" width="260" alt="">\n</p>',
       '<p align="center">\n  <img src="docs/screenshots/plug-light.png" width="260" alt="">\n  <img src="docs/screenshots/agent-light.png" width="260" alt="">\n  <img src="docs/screenshots/login-light.png" width="260" alt="">\n</p>','',
       f'## {toc[2]}','']+[f'{i+1}. {x}' for i,x in enumerate(t['inst'])]+['',f'> {t["inst_note"]}','',t['req'],'',
       f'## {toc[3]}','']+[f'{i+1}. {x}' for i,x in enumerate(t['login'])]+['',
       f'## {hh}','',hl[0],'']+[f'- {x}' for x in hl[1:3]]+['',hl[3],'',
       f'## {toc[5]}','',t['agent_intro'],'','```text',prompt,'```','',f'{DOCL[lang][0]} [docs/AGENT_SETUP{DOCL[lang][1]}.md](docs/AGENT_SETUP{DOCL[lang][1]}.md)','',
       f'### {t["perm_h"]}','','| | |','| --- | --- |']+[f'| {a} | {b} |' for a,b in t['perm']]+['',t['confirm'],'',
       f'### {t["cli_h"]}','',cli,'',t['tools'],'',
       f'## {toc[6]}','',build,'',t['build_note'],'',
       f'## {dh}','']+[f'- {x}' for x in dl]+['',
       f'## {toc[8]}','',t['credits'],'',t['lic'],'']
    open(fn,'w').write('\n'.join(x for x in o if x is not None).lstrip('\n'))
print('ok')
