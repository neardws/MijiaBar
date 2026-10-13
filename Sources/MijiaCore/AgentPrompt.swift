import Foundation

/// 设置 → Agent 接口里「复制安装说明」的内容：一段简短提示，指向仓库里写给 Agent 的完整说明
/// （docs/AGENT_SETUP*.md，由 scripts/gen-agent-docs.py 从 i18n/agent-setup/*.txt 生成），并带上本机 CLI 路径。
public func agentSetupDocURL(_ lang: AppLang = currentLang) -> String {
    let suffix: String
    switch lang {
    case .en: suffix = ""
    case .zhHans: suffix = ".zh-CN"
    case .zhHant: suffix = ".zh-TW"
    default: suffix = "." + lang.rawValue
    }
    // raw 链接：Agent 直接拿到纯 Markdown，不用解析 GitHub 页面
    return "https://raw.githubusercontent.com/neardws/MijiaBar/main/docs/AGENT_SETUP\(suffix).md"
}

public func agentSetupPrompt(cli: String) -> String {
    let t: String
    switch currentLang {
    case .zhHans: t = "请阅读 {URL} ，按其中的步骤把 MijiaBar 接入为你的 MCP 工具。\nCLI 路径：{CLI}\n未经我同意，不要改变任何设备的状态。"
    case .zhHant: t = "請閱讀 {URL} ，依照其中的步驟把 MijiaBar 設定為你的 MCP 工具。\nCLI 路徑：{CLI}\n未經我同意，不要改變任何裝置的狀態。"
    case .en: t = "Read {URL} and follow it to set up MijiaBar as your MCP tool.\nCLI path: {CLI}\nDon't change any device's state without my consent."
    case .de: t = "Lies {URL} und richte MijiaBar danach als dein MCP-Tool ein.\nCLI-Pfad: {CLI}\nÄndere ohne meine Zustimmung keinen Gerätezustand."
    case .fr: t = "Lis {URL} et suis ces étapes pour configurer MijiaBar comme outil MCP.\nChemin de la CLI : {CLI}\nNe modifie l’état d’aucun appareil sans mon accord."
    case .es: t = "Lee {URL} y sigue sus pasos para configurar MijiaBar como tu herramienta MCP.\nRuta de la CLI: {CLI}\nNo cambies el estado de ningún dispositivo sin mi permiso."
    case .it: t = "Leggi {URL} e segui i passaggi per configurare MijiaBar come tuo strumento MCP.\nPercorso della CLI: {CLI}\nNon cambiare lo stato di alcun dispositivo senza il mio consenso."
    case .ru: t = "Прочитай {URL} и по этой инструкции подключи MijiaBar как свой MCP-инструмент.\nПуть к CLI: {CLI}\nНе меняй состояние устройств без моего согласия."
    case .ja: t = "{URL} を読み、その手順に従って MijiaBar をあなたの MCP ツールとして設定してください。\nCLI のパス：{CLI}\n私の同意なしにデバイスの状態を変更しないでください。"
    }
    return t.replacingOccurrences(of: "{URL}", with: agentSetupDocURL()).replacingOccurrences(of: "{CLI}", with: cli)
}
