import SwiftUI
import MijiaCore

/// 编辑模式「风格」标签：内置温馨木屋 + 浅木白墙 / 胡桃木调色板子变体。
struct HouseStyleView: View {
    @EnvironmentObject var m: AppModel
    @StateObject private var decorDrag = HouseDecorDrag()
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
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
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
        m.houseEdit(L("不放", "None")) { $0.setDecor(home: m.houseHomeKey, key: key, item: "none") }
    }

    @ViewBuilder
    private func styleCard(_ st: HouseStyleInfo) -> some View {
        let selected = m.houseStyle == st.id
        let image = preview(st.id)
        Button {
            m.houseEdit(L("风格 ", "Style ") + HouseStyles.displayName(st.id, zh: L("是","no")=="是")) { file in
                file.setStyle(home: m.houseHomeKey, style: st.id == HouseStyles.defaultStyle ? nil : st.id)
            }
            HouseModuleAssets.clearCache()
            HouseAssets.clearImageCache()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // 预览：客厅模块 day-unlit
                if let img = image {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 44)
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.tile).frame(height: 100)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(HouseStyles.displayName(st.id, zh: L("是","no")=="是")).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        Text(image == nil ? L("美术制作中", "Art in progress") : st.kind == .art ? L("完整重绘", "Full redraw") : st.kind == .palette
                             ? L("调色板 · 基于温馨木屋", "Palette · based on Cozy wood")
                             : L("默认", "Default"))
                            .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                    }
                }
            }
            .padding(8)
            .background(selected ? Color.accentColor.opacity(0.12) : Theme.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selected ? Color.accentColor : Theme.stroke))
        }
        .buttonStyle(.plain)
        .disabled(image == nil)
    }

    private func preview(_ styleId: String) -> NSImage? {
        let name = "module-living-day-unlit"
        guard let url = HouseModuleAssets.resourceURL(name, "png", style: styleId, fallbackToDefault: false) else { return nil }
        return NSImage(contentsOf: url)
    }
}
