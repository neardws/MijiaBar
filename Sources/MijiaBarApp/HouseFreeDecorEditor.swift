import SwiftUI
import MijiaCore

struct HouseFreeDecorPreview {
    let room: String
    let cell: [Int]
    let points: [CGPoint]
    let reason: HouseFreeDecor.Reason?
}

struct HouseFreeDecorCanvas {
    let grids: [HouseFreeDecor.Grid]
    let layout: [HouseLayoutCell]
    let origin: [Double]
    let config: HomeHouse
    let items: HouseDecorCatalog
    let fixed: [HouseDecorPlacement]
    var roomNames: [String: String] = [:]
    func offset(_ grid: HouseFreeDecor.Grid) -> CGPoint {
        guard let placed = layout.first(where: { HouseDecor.roomKey($0) == grid.room }) else { return .zero }
        let tip = HouseGrid.tip(col: placed.col, row: placed.row)
        return CGPoint(x: Double(tip.x - grid.tip[0]) - origin[0], y: Double(tip.y - grid.tip[1] - HouseLevels.elevation(placed)) - origin[1])
    }
    func point(grid: HouseFreeDecor.Grid, cell: HouseFreeDecor.Cell, size: String = "S") -> CGPoint {
        let offset = offset(grid), point = grid.px(for: cell, size: size)
        return CGPoint(x: offset.x + point.x, y: offset.y + point.y)
    }
    func reason(room: String, item: String, cell: [Int], source: String?) -> HouseFreeDecor.Reason? {
        HouseFreeDecor.validate(room: room, item: item, cell: cell, grids: grids, items: items,
                                entries: config.freeDecor ?? [:], excluding: source, fixed: fixed)
    }
    func preview(at point: CGPoint, item: HouseDecorCatalog.Item, source: String?) -> HouseFreeDecorPreview? {
        guard item.surface == "floor" else { return nil }
        for grid in grids.reversed() {
            let offset = offset(grid), local = HousePetPoint(x: point.x - offset.x, y: point.y - offset.y)
            let horizontal = (local.x - Double(grid.tip[0])) / 160, vertical = (local.y - Double(grid.tip[1])) / 66
            let col = (horizontal + vertical) / 2 * Double(grid.scale), row = (vertical - horizontal) / 2 * Double(grid.scale)
            guard col >= 0, row >= 0, row < Double(grid.walk.count), col < Double(grid.walk.first?.count ?? 0), let cell = grid.snap(point: local) else { continue }
            let center = self.point(grid: grid, cell: cell, size: item.size), side = item.size == "L" ? 2.0 : 1.0
            let width = 160 * side / Double(grid.scale), height = 66 * side / Double(grid.scale)
            let points = [CGPoint(x: center.x, y: center.y - height), CGPoint(x: center.x + width, y: center.y),
                          CGPoint(x: center.x, y: center.y + height), CGPoint(x: center.x - width, y: center.y)]
            return .init(room: grid.room, cell: cell.array, points: points, reason: reason(room: grid.room, item: item.id, cell: cell.array, source: source))
        }
        return nil
    }
}

struct HouseFreeDecorNumericPanel: View {
    let context: HouseFreeDecorCanvas
    let key: String
    let save: (String, String, [Int]) -> Void
    let remove: () -> Void
    @State var room: String
    @State var item: String
    @State var col: Int
    @State var row: Int
    private var reason: HouseFreeDecor.Reason? { context.reason(room: room, item: item, cell: [col, row], source: key) }
    private var count: Int { (context.config.freeDecor ?? [:]).filter { HouseFreeDecor.room(of: $0.key) == room && $0.value.item != nil }.count }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("自由摆放", "Free placement")).font(.headline)
            Picker(L("装饰", "Decoration"), selection: $item) {
                ForEach(context.items.items.filter { $0.surface == "floor" }, id: \.id) { Text(HouseDecorNames.item($0)).tag($0.id) }
            }
            Picker(L("房间", "Room"), selection: $room) {
                ForEach(context.grids, id: \.room) { Text(context.roomNames[$0.room] ?? $0.room).tag($0.room) }
            }
            Stepper(value: $col, in: 0...127) { Text(LF("第 %@ 列", "Column %@", String(col))) }
            Stepper(value: $row, in: 0...127) { Text(LF("第 %@ 行", "Row %@", String(row))) }
            Text("\(count) / \(HouseFreeDecor.maxPerRoom)")
                .accessibilityLabel(L("自由装饰数量", "Free decor count"))
                .accessibilityValue("\(count) / \(HouseFreeDecor.maxPerRoom)")
            if let reason { Text(reason.message).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button(L("移除", "Remove"), role: .destructive, action: remove)
                Spacer()
                Button(L("应用", "Apply")) { save(room, item, [col, row]) }.disabled(reason != nil)
            }
        }.padding(14).frame(width: 300)
    }
}
