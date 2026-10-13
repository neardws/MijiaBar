import Foundation

/// 设置 → Agent 接口里「复制安装说明」的内容。用户把它粘贴给 Claude Code / Codex / Cursor 等 Agent，
/// Agent 按步骤自行完成：找到 CLI → 注册 MCP → 了解权限 → 列出设备验证。{CLI} 会替换为实际路径。
public func agentSetupPrompt(cli: String) -> String {
    let t: String
    switch currentLang {
    case .zhHans: t = zhPrompt
    case .zhHant: t = zhHantPrompt
    case .de: t = dePrompt
    case .fr: t = frPrompt
    case .es: t = esPrompt
    case .it: t = itPrompt
    case .ru: t = ruPrompt
    case .ja: t = jaPrompt
    case .en: t = enPrompt
    }
    return t.replacingOccurrences(of: "{CLI}", with: cli)
}

private let configBlock = """
   - Claude Code: claude mcp add --scope user mijia -- "{CLI}" mcp
   - Codex: codex mcp add mijia -- "{CLI}" mcp
     (~/.codex/config.toml:
      [mcp_servers.mijia]
      command = "{CLI}"
      args = ["mcp"])
   - Cursor (~/.cursor/mcp.json), Claude Desktop, …:
     {"mcpServers": {"mijia": {"command": "{CLI}", "args": ["mcp"]}}}
"""

private let zhPrompt = """
请帮我把 MijiaBar（macOS 菜单栏米家控制应用）接入为你的 MCP 工具，按以下步骤自己完成：

1. 找到命令行工具：它在应用包内 {CLI}。运行 "{CLI}" --help 确认可用。如需在终端直接使用，可建立链接：mkdir -p ~/.local/bin && ln -sf "{CLI}" ~/.local/bin/mijiabar
2. 用你自己的配置注册一个名为 mijia 的 stdio MCP 服务器，命令为 "{CLI}"，参数为 mcp：
\(configBlock)
   注册后按需重新加载 MCP。
3. 可用工具：list_devices、get_device_state、set_property、run_action。权限由我在 MijiaBar → 设置 → Agent 接口 中控制：默认「只读」（写操作会被拒绝）；「白名单」只允许控制选中的设备；「全部」允许控制所有设备。开启「每次写操作弹窗确认」时，每次写操作都会在 Mac 上弹窗，需要我点允许。没有我的明确要求，不要改变任何设备的状态。
4. 验证：运行 "{CLI}" list（或调用 list_devices），把设备列表给我看。如果提示未登录，请让我先在 MijiaBar 里扫码登录。
"""

private let zhHantPrompt = """
請幫我把 MijiaBar（macOS 選單列米家控制 App）設定為你的 MCP 工具，按以下步驟自己完成：

1. 找到命令列工具：它在 App 套件內 {CLI}。執行 "{CLI}" --help 確認可用。如需在終端機直接使用，可建立連結：mkdir -p ~/.local/bin && ln -sf "{CLI}" ~/.local/bin/mijiabar
2. 用你自己的設定註冊一個名為 mijia 的 stdio MCP 伺服器，指令為 "{CLI}"，參數為 mcp：
\(configBlock)
   註冊後視需要重新載入 MCP。
3. 可用工具：list_devices、get_device_state、set_property、run_action。權限由我在 MijiaBar → 設定 → Agent 介面 中控制：預設「唯讀」（寫入操作會被拒絕）；「白名單」只允許控制勾選的裝置；「全部」允許控制所有裝置。開啟「每次寫入操作跳出視窗確認」時，每次寫入操作都會在 Mac 上跳出視窗，需要我按「允許」。沒有我的明確要求，不要改變任何裝置的狀態。
4. 驗證：執行 "{CLI}" list（或呼叫 list_devices），把裝置清單給我看。如果顯示未登入，請讓我先在 MijiaBar 裡掃碼登入。
"""

private let enPrompt = """
Please set up MijiaBar (a macOS menu bar app for Xiaomi Mi Home devices) as an MCP tool for yourself. Do it yourself, step by step:

1. Find the CLI. It ships inside the app bundle at {CLI}. Run "{CLI}" --help to check it works. To use it from a terminal, link it: mkdir -p ~/.local/bin && ln -sf "{CLI}" ~/.local/bin/mijiabar
2. Register a stdio MCP server named mijia, command "{CLI}", argument mcp, in your own config:
\(configBlock)
   Reload MCP servers afterwards if needed.
3. Tools: list_devices, get_device_state, set_property, run_action. I control access in MijiaBar → Settings → Agent interface: "Read" is the default (writes are refused); "Allowlist" allows only the devices I pick; "Full" allows every device. When "Confirm every write" is on, each write shows a dialog on the Mac that I have to approve. Never change a device's state unless I ask you to.
4. Verify: run "{CLI}" list (or call list_devices) and show me the device list. If it says I'm not signed in, ask me to sign in with the QR code in MijiaBar first.
"""

private let dePrompt = """
Bitte richte MijiaBar (eine macOS-Menüleisten-App für Xiaomi-Mi-Home-Geräte) als MCP-Tool für dich ein. Erledige das selbst, Schritt für Schritt:

1. Finde das CLI. Es liegt im App-Bundle unter {CLI}. Führe "{CLI}" --help aus, um es zu prüfen. Für die Nutzung im Terminal verlinken: mkdir -p ~/.local/bin && ln -sf "{CLI}" ~/.local/bin/mijiabar
2. Registriere in deiner eigenen Konfiguration einen stdio-MCP-Server namens mijia mit dem Befehl "{CLI}" und dem Argument mcp:
\(configBlock)
   Lade die MCP-Server danach bei Bedarf neu.
3. Werkzeuge: list_devices, get_device_state, set_property, run_action. Den Zugriff steuere ich in MijiaBar → Einstellungen → Agent-Schnittstelle: Standard ist „Lesen“ (Schreibzugriffe werden abgelehnt); „Positivliste“ erlaubt nur ausgewählte Geräte; „Voll“ erlaubt alle Geräte. Ist „Jeden Schreibvorgang bestätigen“ aktiv, erscheint auf dem Mac für jeden Schreibvorgang ein Dialog, den ich bestätigen muss. Ändere niemals den Zustand eines Geräts, ohne dass ich dich darum bitte.
4. Prüfen: Führe "{CLI}" list aus (oder rufe list_devices auf) und zeig mir die Geräteliste. Falls ich nicht angemeldet bin, bitte mich, mich zuerst in MijiaBar per QR-Code anzumelden.
"""

private let frPrompt = """
Configure MijiaBar (une app de barre des menus macOS pour les appareils Xiaomi Mi Home) comme outil MCP pour toi-même. Fais-le toi-même, étape par étape :

1. Trouve la CLI. Elle est fournie dans l’app : {CLI}. Lance "{CLI}" --help pour vérifier qu’elle fonctionne. Pour l’utiliser dans un terminal, crée un lien : mkdir -p ~/.local/bin && ln -sf "{CLI}" ~/.local/bin/mijiabar
2. Enregistre dans ta propre configuration un serveur MCP stdio nommé mijia, commande "{CLI}", argument mcp :
\(configBlock)
   Recharge ensuite les serveurs MCP si nécessaire.
3. Outils : list_devices, get_device_state, set_property, run_action. Je contrôle l’accès dans MijiaBar → Réglages → Interface agent : « Lecture » par défaut (les écritures sont refusées) ; « Liste autorisée » n’autorise que les appareils choisis ; « Complet » autorise tous les appareils. Si « Confirmer chaque écriture » est activé, chaque écriture affiche sur le Mac une fenêtre que je dois approuver. Ne modifie jamais l’état d’un appareil sans que je te le demande.
4. Vérifie : lance "{CLI}" list (ou appelle list_devices) et montre-moi la liste des appareils. Si je ne suis pas connecté, demande-moi d’abord de me connecter par QR code dans MijiaBar.
"""

private let esPrompt = """
Configura MijiaBar (una app de barra de menús de macOS para dispositivos Xiaomi Mi Home) como herramienta MCP para ti. Hazlo tú mismo, paso a paso:

1. Localiza la CLI. Viene dentro de la app: {CLI}. Ejecuta "{CLI}" --help para comprobar que funciona. Para usarla en el terminal, crea un enlace: mkdir -p ~/.local/bin && ln -sf "{CLI}" ~/.local/bin/mijiabar
2. Registra en tu propia configuración un servidor MCP stdio llamado mijia, comando "{CLI}", argumento mcp:
\(configBlock)
   Después recarga los servidores MCP si hace falta.
3. Herramientas: list_devices, get_device_state, set_property, run_action. Yo controlo el acceso en MijiaBar → Ajustes → Interfaz de agente: «Lectura» por defecto (se rechazan las escrituras); «Lista permitida» solo permite los dispositivos que elija; «Completo» permite todos. Con «Confirmar cada escritura» activado, cada escritura muestra un diálogo en el Mac que debo aprobar. Nunca cambies el estado de un dispositivo sin que te lo pida.
4. Verifica: ejecuta "{CLI}" list (o llama a list_devices) y muéstrame la lista de dispositivos. Si indica que no he iniciado sesión, pídeme que primero inicie sesión con el código QR en MijiaBar.
"""

private let itPrompt = """
Configura MijiaBar (un’app della barra dei menu di macOS per i dispositivi Xiaomi Mi Home) come strumento MCP per te. Fallo da solo, passo per passo:

1. Trova la CLI. È inclusa nell’app: {CLI}. Esegui "{CLI}" --help per verificare che funzioni. Per usarla dal terminale, crea un link: mkdir -p ~/.local/bin && ln -sf "{CLI}" ~/.local/bin/mijiabar
2. Registra nella tua configurazione un server MCP stdio chiamato mijia, comando "{CLI}", argomento mcp:
\(configBlock)
   Poi ricarica i server MCP se necessario.
3. Strumenti: list_devices, get_device_state, set_property, run_action. Controllo io l’accesso in MijiaBar → Impostazioni → Interfaccia agente: «Lettura» è il predefinito (le scritture vengono rifiutate); «Lista consentita» permette solo i dispositivi scelti; «Completo» permette tutti i dispositivi. Con «Conferma ogni scrittura» attivo, ogni scrittura mostra sul Mac una finestra che devo approvare. Non cambiare mai lo stato di un dispositivo senza che te lo chieda.
4. Verifica: esegui "{CLI}" list (o chiama list_devices) e mostrami l’elenco dei dispositivi. Se risulta che non ho effettuato l’accesso, chiedimi prima di accedere con il codice QR in MijiaBar.
"""

private let ruPrompt = """
Пожалуйста, подключи MijiaBar (приложение в строке меню macOS для устройств Xiaomi Mi Home) как свой MCP-инструмент. Сделай это сам, по шагам:

1. Найди CLI. Он находится внутри приложения: {CLI}. Выполни "{CLI}" --help, чтобы проверить его. Для работы из терминала создай ссылку: mkdir -p ~/.local/bin && ln -sf "{CLI}" ~/.local/bin/mijiabar
2. Зарегистрируй в своей конфигурации stdio MCP-сервер с именем mijia, командой "{CLI}" и аргументом mcp:
\(configBlock)
   При необходимости перезагрузи MCP-серверы.
3. Инструменты: list_devices, get_device_state, set_property, run_action. Доступом управляю я в MijiaBar → Настройки → Интерфейс агента: по умолчанию «Чтение» (запись запрещена); «Белый список» разрешает только выбранные устройства; «Полный» разрешает все устройства. Если включено «Подтверждать каждую запись», каждая запись показывает на Mac окно, которое я должен одобрить. Никогда не меняй состояние устройства без моей просьбы.
4. Проверка: выполни "{CLI}" list (или вызови list_devices) и покажи мне список устройств. Если я не вошёл в аккаунт, попроси меня сначала войти по QR-коду в MijiaBar.
"""

private let jaPrompt = """
MijiaBar（Xiaomi Mi Home デバイス用の macOS メニューバーアプリ）を、あなた自身の MCP ツールとして設定してください。次の手順で自分で行ってください：

1. CLI を見つける：アプリ内の {CLI} にあります。"{CLI}" --help を実行して動作を確認してください。ターミナルで使う場合はリンクを作成：mkdir -p ~/.local/bin && ln -sf "{CLI}" ~/.local/bin/mijiabar
2. あなた自身の設定に、名前 mijia、コマンド "{CLI}"、引数 mcp の stdio MCP サーバーを登録：
\(configBlock)
   必要に応じて MCP サーバーを再読み込みしてください。
3. ツール：list_devices、get_device_state、set_property、run_action。アクセス権は私が MijiaBar → 設定 → エージェント連携 で管理します：既定は「読み取り」（書き込みは拒否）、「許可リスト」は選んだデバイスのみ、「すべて」は全デバイスを許可します。「書き込みごとに確認」がオンの場合、書き込みのたびに Mac にダイアログが表示され、私の承認が必要です。私が頼まない限り、デバイスの状態を変更しないでください。
4. 確認："{CLI}" list を実行（または list_devices を呼び出し）して、デバイス一覧を見せてください。未ログインと表示されたら、まず MijiaBar で QR コードからログインするよう私に伝えてください。
"""
