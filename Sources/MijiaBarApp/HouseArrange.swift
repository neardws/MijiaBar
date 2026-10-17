import AppKit
import MijiaCore
import SwiftUI

/// HouseWindow「房间布局」标签：3×2 格子 + 实时预览（合成模块）。
struct HouseArrangeView: View {
    @EnvironmentObject var m: AppModel
    @State private var selected: String?
    @State private var preview: NSImage?
    @State private var previewMs: Double = 0
    @State private var phase: HousePhase = .from()

    static let cellW: CGFloat = 112
    static let cellH: CGFloat = 76
    static let gap: CGFloat = 8
    /// 3 格 + 间距 + 两侧 16 内边距；HouseWindow.editSize 宽 1041 时预览仍有 ~640
    static let panelWidth: CGFloat = 3 * cellW + 2 * gap + 32

    private var home: String { m.houseHomeKey }
    private var layout: [HouseLayoutCell] {
        m.house.homes[home]?.layout ?? HouseLayoutSolver.classicFour.enumerated().map { i, c in
            // bind classic geometry to current resolved rooms by module
            let rooms = m.houseResolved.rooms
            let match = rooms.first { $0.module.rawValue == c.module }
            return HouseLayoutCell(room: match?.key ?? "slot\(i)", module: c.module, col: c.col, row: c.row)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                toolbar
                grid
                Text(L("拖动房间卡片交换位置；客厅占两格。最多 3×2。经典四室走整图，自定义布局才拼模块。",
                       "Drag room cards to swap. Living room takes two cells. Max 3×2. Classic four uses the single cutaway; custom layouts stitch modules."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: Self.panelWidth, alignment: .topLeading)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L("预览", "Preview")).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Picker("", selection: $phase) {
                        Text(L("白天", "Day")).tag(HousePhase.day)
                        Text(L("夜间", "Night")).tag(HousePhase.night)
                    }.pickerStyle(.segmented).frame(width: 140)
                    if previewMs > 0 {
                        Text(String(format: "%.1f ms", previewMs)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                    }
                }
                if let preview {
                    Image(nsImage: preview).resizable().interpolation(.none).aspectRatio(contentMode: .fit)
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.bg2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { refreshPreview() }
        .onChange(of: m.house) { _, _ in refreshPreview() }
        .onChange(of: phase) { _, _ in refreshPreview() }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text(L("房间布局", "Room layout")).font(.system(size: 15, weight: .semibold))
            Spacer()
            Button(L("经典四室", "Classic four")) {
                m.houseEdit(L("经典四室", "Classic four")) { $0.setLayout(home: home, layout: nil) }
            }.buttonStyle(.bordered).controlSize(.small)
            Button(L("自动填满", "Auto-fill")) {
                let r = m.houseResolved
                let rooms = r.rooms.map { (key: $0.key, module: $0.module, score: $0.devices.count) }
                    + r.excluded.filter { $0.reason != .excluded }.map { (key: $0.key, module: $0.module, score: $0.deviceCount) }
                let layout = HouseLayoutSolver.autolayout(rooms: rooms)
                m.houseEdit(L("自动布局", "Auto layout")) { $0.setLayout(home: home, layout: layout) }
            }.buttonStyle(.bordered).controlSize(.small)
        }
    }

    private var grid: some View {
        let occ = occupancy()
        return VStack(alignment: .leading, spacing: Self.gap) {
            ForEach(0..<HouseLayoutSolver.maxRows, id: \.self) { row in
                HStack(spacing: Self.gap) {
                    // 被客厅第二格覆盖的格子不单独占位（否则这一行比别的行宽，整列被挤出左边）
                    ForEach(0..<HouseLayoutSolver.maxCols, id: \.self) { col in
                        if let c = occ[SIMD2(col, row)], !(c.col == col && c.row == row) {
                            EmptyView()
                        } else {
                            cellView(col: col, row: row, occ: occ)
                        }
                    }
                }
            }
        }
        .frame(width: 3 * Self.cellW + 2 * Self.gap, alignment: .leading)
    }

    private func occupancy() -> [SIMD2<Int>: HouseLayoutCell] {
        var map: [SIMD2<Int>: HouseLayoutCell] = [:]
        for c in layout {
            let (fw, fh) = HouseLayoutSolver.defaultFootprint(c.module)
            for dc in 0..<fw {
                for dr in 0..<fh {
                    let p = SIMD2(c.col + dc, c.row + dr)
                    // only mark origin for living's second cell as continuation
                    if dc == 0 && dr == 0 { map[p] = c }
                    else if map[p] == nil { map[p] = c }
                }
            }
        }
        return map
    }

    @ViewBuilder
    private func cellView(col: Int, row: Int, occ: [SIMD2<Int>: HouseLayoutCell]) -> some View {
        let p = SIMD2(col, row)
        if let c = occ[p], c.col == col && c.row == row {
            let (fw, _) = HouseLayoutSolver.defaultFootprint(c.module)
            roomCard(c)
                .frame(width: CGFloat(fw) * Self.cellW + CGFloat(fw - 1) * Self.gap, height: Self.cellH)
                .onDrag {
                    selected = c.room
                    return NSItemProvider(object: c.room as NSString)
                }
                .onDrop(of: [.plainText], isTargeted: nil) { providers in
                    HouseDropPayload.load(providers) { payload in
                        guard let from = payload else { return }
                        swap(from, to: c)
                    }
                    return true
                }
        } else if occ[p] != nil {
            EmptyView() // covered by living
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(.secondary.opacity(0.5))
                .background(Theme.tile.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(Image(systemName: "plus").foregroundStyle(.secondary))
                .frame(width: Self.cellW, height: Self.cellH)
                .onDrop(of: [.plainText], isTargeted: nil) { providers in
                    HouseDropPayload.load(providers) { payload in
                        guard let from = payload, let src = layout.first(where: { $0.room == from }) else { return }
                        move(src, toCol: col, toRow: row)
                    }
                    return true
                }
        }
    }

    private func roomCard(_ c: HouseLayoutCell) -> some View {
        let title = roomTitle(c)
        return VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            if moduleTitle(c.module) != title {
                Text(moduleTitle(c.module)).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text("(\(c.col),\(c.row))").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(selected == c.room ? Color.accentColor.opacity(0.18) : Theme.tile, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(selected == c.room ? Color.accentColor : Theme.stroke))
    }

    /// 房间名：已解析的房间 → 旧式 "name:<房间名>" key → 模块名（本地化）
    private func roomTitle(_ c: HouseLayoutCell) -> String {
        if let t = m.houseResolved.rooms.first(where: { $0.key == c.room })?.title
            ?? m.houseResolved.excluded.first(where: { $0.key == c.room })?.title { return t }
        if c.room.hasPrefix("name:"), c.room.count > 5 { return String(c.room.dropFirst(5)) }
        return moduleTitle(c.module)
    }

    private func moduleTitle(_ raw: String) -> String {
        HouseModule(rawValue: raw)?.title ?? raw
    }

    private func swap(_ fromRoom: String, to: HouseLayoutCell) {
        var next = layout
        guard let i = next.firstIndex(where: { $0.room == fromRoom }),
              let j = next.firstIndex(where: { $0.room == to.room }), i != j else { return }
        let a = next[i], b = next[j]
        next[i] = HouseLayoutCell(room: a.room, module: a.module, col: b.col, row: b.row)
        next[j] = HouseLayoutCell(room: b.room, module: b.module, col: a.col, row: a.row)
        guard HouseLayoutSolver.validate(next).isEmpty else {
            m.houseFlash(L("这样会重叠或越界", "That would overlap or go out of bounds"))
            return
        }
        m.houseEdit(L("交换房间", "Swap rooms")) { $0.setLayout(home: home, layout: next) }
    }

    private func move(_ src: HouseLayoutCell, toCol: Int, toRow: Int) {
        var next = layout.filter { $0.room != src.room }
        next.append(HouseLayoutCell(room: src.room, module: src.module, col: toCol, row: toRow))
        guard HouseLayoutSolver.validate(next).isEmpty else {
            m.houseFlash(L("这样会重叠或越界", "That would overlap or go out of bounds"))
            return
        }
        m.houseEdit(L("移动房间", "Move room")) { $0.setLayout(home: home, layout: next) }
    }

    private func refreshPreview() {
        // 同步合成：截图 CLI 的 RunLoop 等待很短，异步 Task 来不及
        if let result = HouseModuleAssets.compose(layout: layout, phase: phase) {
            previewMs = result.ms
            preview = result.image
        } else {
            previewMs = 0
            preview = nil
        }
    }
}

enum HouseModuleAssets {
    /// SPM .process 可能把 House/modules/ 摊平；和 HouseAssets 一样两处都找
    static func resourceURL(_ name: String, _ ext: String) -> URL? {
        if let u = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "House/modules")
            ?? Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "modules")
            ?? Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "House")
            ?? Bundle.module.url(forResource: name, withExtension: ext) {
            return u
        }
        // 开发目录回退（swift build 跑 snapshot 时 bundle 里偶发缺文件）
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("assets/house/modules/\(name).\(ext)")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }

    static func compose(layout: [HouseLayoutCell], phase: HousePhase) -> (image: NSImage, ms: Double)? {
        guard let url = resourceURL("catalog", "json") else {
            fputs("HouseModuleAssets: catalog.json not found\n", stderr); return nil
        }
        let cat: HouseModuleCatalog
        do { cat = try HouseComposer.loadCatalog(from: url) }
        catch { fputs("HouseModuleAssets: catalog decode \(error)\n", stderr); return nil }
        var images: [String: HouseModuleImages] = [:]
        let tag = phase == .day ? "day" : "night"
        func load(_ variants: [String: String], _ key: String) -> CGImage? {
            guard let name = variants[key] else { return nil }
            let base = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
            return resourceURL(base, "png").flatMap(HouseComposer.loadCGImage(from:))
        }
        for (id, art) in cat.modules {
            guard let v = art.variants, let ui = load(v, "\(tag)-unlit"), let li = load(v, "\(tag)-lit") else {
                fputs("HouseModuleAssets: missing png for \(id)\n", stderr); continue
            }
            images[id] = HouseModuleImages(unlit: ui, lit: li, unlitCut: load(v, "\(tag)-unlit-cut"), litCut: load(v, "\(tag)-lit-cut"))
        }
        guard !images.isEmpty else { fputs("HouseModuleAssets: no images\n", stderr); return nil }
        let r = HouseComposer.compose(.init(layout: layout, catalog: cat, images: images, night: phase == .night))
        // 预览：白天看关灯底图，夜间看开灯（暖光）版
        guard let img = phase == .day ? r.unlit : r.lit else { fputs("HouseModuleAssets: compose produced nil\n", stderr); return nil }
        let ns = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
        return (ns, r.milliseconds)
    }
}
