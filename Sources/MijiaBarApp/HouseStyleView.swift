import SwiftUI
import MijiaCore

/// 编辑模式「风格」标签：内置温馨木屋 + 浅木白墙 / 胡桃木调色板子变体。
struct HouseStyleView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("小屋风格", "House style"))
                    .font(.system(size: 15, weight: .semibold))
                Text(L("调色板子变体只换墙面和地板颜色，灯具位和设备位置不变。",
                       "Palette variants only recolor walls and floors; fixture slots stay the same."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    ForEach(HouseStyles.all) { st in
                        styleCard(st)
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
    }

    @ViewBuilder
    private func styleCard(_ st: HouseStyleInfo) -> some View {
        let selected = m.houseStyle == st.id
        Button {
            m.houseEdit(L("风格 ", "Style ") + HouseStyles.displayName(st.id, zh: L("是","no")=="是")) { file in
                file.setStyle(home: m.houseHomeKey, style: st.id == HouseStyles.defaultStyle ? nil : st.id)
            }
            HouseModuleAssets.clearCache()
            HouseAssets.clearImageCache()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // 预览：客厅模块 day-unlit
                if let img = preview(st.id) {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.tile).frame(height: 100)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(HouseStyles.displayName(st.id, zh: L("是","no")=="是")).font(.system(size: 13, weight: .semibold))
                        Text(st.kind == .palette
                             ? L("调色板 · 基于温馨木屋", "Palette · based on Cozy wood")
                             : L("默认", "Default"))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                    }
                }
            }
            .padding(10)
            .background(selected ? Color.accentColor.opacity(0.12) : Theme.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selected ? Color.accentColor : Theme.stroke))
        }
        .buttonStyle(.plain)
    }

    private func preview(_ styleId: String) -> NSImage? {
        let name = "module-living-day-unlit"
        guard let url = HouseModuleAssets.resourceURL(name, "png", style: styleId) else { return nil }
        return NSImage(contentsOf: url)
    }
}

