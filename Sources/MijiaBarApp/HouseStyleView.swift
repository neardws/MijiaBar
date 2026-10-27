import SwiftUI
import MijiaCore

/// 编辑模式「风格」标签：内置温馨木屋 + 浅木白墙 / 胡桃木调色板子变体。
struct HouseStyleView: View {
    @EnvironmentObject var m: AppModel
    @StateObject private var decorDrag = HouseDecorDrag()
    @ObservedObject private var packs = HouseStylePackStore.shared
    @State private var pendingSelection: String?
    var date = Date()

    var body: some View {
        HStack(spacing: 0) {
            HouseDecorEditor(drag: decorDrag, date: date)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            panel.frame(width: 356)
        }
        .background(Theme.bg)
    }

    private var panel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("小屋风格", "House style"))
                    .font(.system(size: 15, weight: .semibold))
                Text(L("调色板子变体只换墙面和地板颜色，灯具位和设备位置不变。",
                       "Palette variants only recolor walls and floors; fixture slots stay the same."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if !packs.isAvailable(m.houseSelectedStyle) {
                    Text(L("此风格尚未下载，暂时显示温馨木屋。", "This style is not downloaded. Showing Cozy wood for now."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    ForEach(HouseStyles.all) { st in
                        styleCard(st)
                    }
                }
                Divider()
                Toggle(L("显示装饰", "Show decorations"), isOn: preference(seasonal: false))
                Toggle(L("节日装饰自动出现", "Holiday decorations"), isOn: preference(seasonal: true))
                Text(L("春节 / 中秋 / 万圣节 / 圣诞，±7 天", "Spring Festival / Mid-Autumn / Halloween / Christmas, ±7 days"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Divider()
                HouseDecorPanel(drag: decorDrag)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
        .onDrop(of: [.plainText], delegate: HouseDecorPanelDrop(drag: decorDrag, remove: removeDecor))
    }

    private func preference(seasonal: Bool) -> Binding<Bool> {
        Binding(get: {
            let prefs = m.house.homes[m.houseHomeKey]?.decorPrefs ?? .init()
            return seasonal ? prefs.seasonal : prefs.enabled
        }, set: { value in
            m.houseEdit(seasonal ? L("节日装饰自动出现", "Holiday decorations") : L("显示装饰", "Show decorations")) {
                $0.setDecorPrefs(home: m.houseHomeKey, enabled: seasonal ? nil : value, seasonal: seasonal ? value : nil)
            }
        })
    }

    private func removeDecor(_ key: String) {
        m.houseEdit(L("不放", "None")) {
            if key.hasPrefix("free:") { $0.setFreeDecor(home: m.houseHomeKey, key: String(key.dropFirst(5)), item: nil, cell: []) }
            else { $0.setDecor(home: m.houseHomeKey, key: key, item: "none") }
        }
    }

    private func styleCard(_ st: HouseStyleInfo) -> some View {
        HouseStylePackCard(style: st, status: packs.status(st.id), selected: m.houseSelectedStyle == st.id,
                           removalError: packs.removalErrors[st.id],
                           select: { choose(st.id) }, remove: { Task { await packs.remove(st.id) } })
    }

    private func choose(_ id: String) {
        pendingSelection = id
        let home = m.houseHomeKey
        let previous = m.houseSelectedStyle
        if packs.isAvailable(id) { select(id, home: home); return }
        Task {
            if await packs.download(id), pendingSelection == id, m.houseHomeKey == home, m.houseSelectedStyle == previous {
                select(id, home: home)
            }
        }
    }

    private func select(_ id: String, home: String) {
        m.houseEdit(L("风格 ", "Style ") + HouseStyles.displayName(id, zh: L("是", "no") == "是")) {
            $0.setStyle(home: home, style: id == HouseStyles.defaultStyle ? nil : id)
        }
        HouseModuleAssets.clearCache()
        HouseAssets.clearImageCache()
    }
}
