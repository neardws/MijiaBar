import Foundation

/// 设置 → Agent 接口里「复制安装说明」的内容：一段简短提示，指向仓库里写给 Agent 的完整说明
/// （docs/AGENT_SETUP*.md，由 scripts/gen-agent-docs.py 从 i18n/agent-setup/*.txt 生成），并带上本机 CLI 路径。
public func agentSetupDocURL(_ lang: AppLang = currentLang) -> String {
    let suffix: String
    switch lang {
    case .en: suffix = ""
    case .zhHans: suffix = ".zh-CN"
    case .zhHant: suffix = ".zh-TW"
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
    }
    return t.replacingOccurrences(of: "{URL}", with: agentSetupDocURL()).replacingOccurrences(of: "{CLI}", with: cli)
}
