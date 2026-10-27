import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MijiaCore

enum HouseDecorNames {
    static func item(_ item: HouseDecorCatalog.Item) -> String { L(item.name["zh"] ?? item.id, item.name["en"] ?? item.id) }
    static func slot(_ id: String) -> String {
        switch id {
        case "corner": return L("墙角", "Corner")
        case "rug": return L("地毯位", "Rug")
        case "window": return L("窗边", "Window")
        case "sofa_side": return L("沙发旁", "Sofa side")
        case "wall_nw": return L("左墙", "Left wall")
        case "wall_ne": return L("右墙", "Right wall")
        case "foot": return L("床尾", "Bed foot")
        case "dresser": return L("柜旁", "Dresser")
        case "shelf": return L("书架旁", "Shelf")
        case "desk": return L("书桌旁", "Desk")
        case "door": return L("门边", "Door")
        case "counter": return L("台边", "Counter")
        case "tub": return L("浴缸旁", "Bathtub")
        case "chair": return L("椅旁", "Chair")
        case "washer": return L("洗衣机旁", "Washer")
        default: return id
        }
    }
}

@MainActor final class HouseDecorDrag: ObservableObject {
    @Published var item: HouseDecorCatalog.Item?
    @Published var source: String?
    @Published var preview: HouseFreeDecorPreview?
    weak var sceneView: NSView?
    var remove: ((String) -> Void)?
    var payload: String? { item.map { "mijiabar-house-decor:" + $0.id } }
    func clear() { item = nil; source = nil; preview = nil }
    func end(at point: NSPoint, operation: NSDragOperation, cancelled: Bool) {
        defer { clear() }
        guard !cancelled, operation.isEmpty, let source, let view = sceneView, let window = view.window else { return }
        let bounds = window.convertToScreen(view.convert(view.bounds, to: nil))
        if !bounds.contains(point) { remove?(source) }
    }
}

struct HouseDecorPanel: View {
    @ObservedObject var drag: HouseDecorDrag
    private var categories: [(String, String)] {
        [("plant", L("绿植", "Plants")), ("rug", L("地毯", "Rugs")), ("wall", L("挂饰", "Wall decor")),
         ("book", L("书", "Books")), ("pet", L("宠物", "Pets")), ("holiday", L("节日", "Holidays"))]
    }
    var body: some View {
        ForEach(categories, id: \.0) { category, title in
            Text(title).font(.system(size: 12, weight: .semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82))], spacing: 8) {
                ForEach(HouseModuleAssets.decorCatalog?.items.filter { $0.category == category } ?? [], id: \.id) { item in
                    VStack(spacing: 4) {
                        if let file = item.sprites["day"]?.file(wall: item.surface == "wall" ? "nw" : nil),
                           let image = HouseModuleAssets.decorImage(file) {
                            Image(decorative: image, scale: 1).resizable().interpolation(.none).scaledToFit().frame(height: 42)
                        }
                        Text(HouseDecorNames.item(item)).font(.system(size: 10)).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity).frame(height: 72)
                    .background(Theme.tile, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(HouseDecorDragSource(item: item, source: nil, drag: drag, click: {}))
                    .accessibilityElement(children: .ignore).accessibilityLabel(HouseDecorNames.item(item))
                }
            }
        }
    }
}

struct HouseDecorEditor: View {
    @EnvironmentObject var m: AppModel
    @ObservedObject var drag: HouseDecorDrag
    var date = Date()
    @State private var selected: String?
    private var config: HomeHouse { m.house.homes[m.houseHomeKey] ?? .init() }
    private var layout: [HouseLayoutCell] {
        m.houseLayoutCells ?? HouseLayoutSolver.classicFour.map { cell in
            HouseLayoutCell(room: m.houseRooms.first { $0.module.rawValue == cell.module }?.key ?? cell.module,
                            module: cell.module, col: cell.col, row: cell.row)
        }
    }
    var body: some View {
        VStack(spacing: 12) {
            if let source = HouseModuleAssets.composedScene(layout: layout, phase: .from(date: date), style: m.houseStyle, config: config, date: date) {
                GeometryReader { geometry in
                    let size = source.artSize
                    let scale = min(geometry.size.width / size.width, geometry.size.height / size.height)
                    let slots = (source.scene.decorSlots ?? []).filter { $0.hidden == nil }
                    let freeContext = freeCanvas(origin: source.scene.origin ?? [0, 0])
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: HousePhase.from(date: date) == .day ? source.unlit : source.lit).resizable().interpolation(.none)
                        ForEach(slots, id: \.key) { slot in slotButton(slot, scale: scale) }
                        if let freeContext {
                            ForEach(source.scene.freeDecor ?? [], id: \.key) { entry in freeButton(entry, scale: scale, context: freeContext) }
                        }
                        if let preview = drag.preview {
                            Path { path in
                                path.addLines(preview.points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }); path.closeSubpath()
                            }.fill((preview.reason == nil ? Color.green : Color.red).opacity(0.5))
                                .help(preview.reason?.message ?? L("自由摆放", "Free placement"))
                                .accessibilityLabel(preview.reason?.message ?? L("自由摆放", "Free placement")).allowsHitTesting(false)
                        }
                    }
                    .frame(width: size.width * scale, height: size.height * scale)
                    .background(HouseDecorSceneProbe(drag: drag))
                    .onDrop(of: [.plainText], delegate: HouseDecorSceneDrop(drag: drag, slots: slots, scale: scale, place: move, freeContext: freeContext, freePlace: freePlace))
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
            ForEach(layout, id: \.room) { cell in
                let room = HouseDecor.roomKey(cell)
                Text((m.houseRooms.first { $0.key == room }?.title ?? room) + " · " + L("自由摆放", "Free placement") + " \((config.freeDecor ?? [:]).filter { HouseFreeDecor.room(of: $0.key) == room && $0.value.item != nil }.count) / \(HouseFreeDecor.maxPerRoom)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(drag.preview?.reason?.message ?? " ").font(.caption).foregroundStyle(.red).frame(height: 16)
                .accessibilityHidden(drag.preview?.reason == nil)
            Text(L("拖动装饰到合适的位置；拖回面板或屋外移除。点位置可选择装饰，⌘Z 撤销。",
                   "Drag decor onto a fitting slot; drag back to the panel or outside the house to remove. Click a slot to choose; ⌘Z undoes."))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .onAppear { drag.remove = { place($0, "none") } }
        .onDisappear { drag.clear(); drag.remove = nil }
    }
    private func place(_ key: String, _ item: String?) {
        m.houseEdit(L("装饰", "Decoration")) { file in
            if key.hasPrefix("free:") { file.setFreeDecor(home: m.houseHomeKey, key: String(key.dropFirst(5)), item: nil, cell: []) }
            else { file.setDecor(home: m.houseHomeKey, key: key, item: item) }
        }
    }
    private func move(_ key: String, _ item: String?, _ origin: String?) {
        m.houseEdit(L("装饰", "Decoration")) {
            if let origin, origin != key {
                if origin.hasPrefix("free:") { $0.setFreeDecor(home: m.houseHomeKey, key: String(origin.dropFirst(5)), item: nil, cell: []) }
                else { $0.setDecor(home: m.houseHomeKey, key: origin, item: "none") }
            }
            $0.setDecor(home: m.houseHomeKey, key: key, item: item)
        }
    }
    private func freeCanvas(origin: [Double], current: HomeHouse? = nil) -> HouseFreeDecorCanvas? {
        let config = current ?? self.config, layout = config.layout ?? self.layout
        guard let (catalog, _) = HouseModuleAssets.load(phase: .day, style: config.style), let items = HouseModuleAssets.decorCatalog else { return nil }
        return .init(grids: HouseModuleAssets.freeGrids(layout: layout, catalog: catalog, style: config.style), layout: layout, origin: origin,
                     config: config, items: items, fixed: HouseDecor.resolve(layout: layout, catalog: catalog, overrides: config.decor ?? [:], prefs: .init(seasonal: config.decorPrefs?.seasonal ?? true), date: date, items: items),
                     roomNames: Dictionary(m.houseRooms.map { ($0.key, $0.title) }, uniquingKeysWith: { first, _ in first }))
    }
    private func freePlace(_ room: String, _ item: String, _ cell: [Int], _ source: String?) {
        let original = source.flatMap { $0.hasPrefix("free:") ? String($0.dropFirst(5)) : nil }
        guard let context = freeCanvas(origin: [0, 0]), context.reason(room: room, item: item, cell: cell, source: original) == nil else { return }
        m.houseEdit(L("自由摆放", "Free placement")) { file in
            guard let current = freeCanvas(origin: [0, 0], current: file.homes[m.houseHomeKey] ?? HomeHouse()),
                  current.reason(room: room, item: item, cell: cell, source: original) == nil else { return }
            let entries = file.homes[m.houseHomeKey]?.freeDecor ?? [:]
            let key = original.flatMap { HouseFreeDecor.room(of: $0) == room ? $0 : nil }
                ?? room + "/" + HouseFreeDecor.nextID(room: room, entries: entries)
            if let original, original != key { file.setFreeDecor(home: m.houseHomeKey, key: original, item: nil, cell: []) }
            if let source, original == nil { file.setDecor(home: m.houseHomeKey, key: source, item: "none") }
            file.setFreeDecor(home: m.houseHomeKey, key: key, item: item, cell: cell)
        }
        selected = nil
    }
    private func freeButton(_ entry: HouseFreeDecorSceneItem, scale: CGFloat, context: HouseFreeDecorCanvas) -> some View {
        let item = context.items.items.first { $0.id == entry.item }
        let room = m.houseRooms.first { $0.key == entry.room }?.title ?? entry.room
        return Button { selected = "free:" + entry.key } label: {
            RoundedRectangle(cornerRadius: 5).strokeBorder(Color.yellow, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
        }.buttonStyle(.plain)
            .frame(width: max(20, entry.rect[2] * scale), height: max(20, entry.rect[3] * scale))
            .overlay { if let item { HouseDecorDragSource(item: item, source: "free:" + entry.key, drag: drag, click: { selected = "free:" + entry.key }) } }
            .accessibilityLabel(room + " · " + L("自由摆放", "Free placement") + " · " + (item.map(HouseDecorNames.item) ?? entry.item) + " · " + LF("第 %@ 列 第 %@ 行", "Column %@ row %@", String(entry.cell[0]), String(entry.cell[1])))
            .accessibilityValue(LF("第 %@ 列 第 %@ 行", "Column %@ row %@", String(entry.cell[0]), String(entry.cell[1])))
            .popover(isPresented: Binding(get: { selected == "free:" + entry.key }, set: { if !$0 { selected = nil } })) {
                HouseFreeDecorNumericPanel(context: context, key: entry.key,
                                           save: { freePlace($0, $1, $2, "free:" + entry.key) },
                                           remove: { place("free:" + entry.key, nil); selected = nil },
                                           room: entry.room, item: entry.item, col: entry.cell[0], row: entry.cell[1])
            }
            .position(x: (entry.rect[0] + entry.rect[2] / 2) * scale, y: (entry.rect[1] + entry.rect[3] / 2) * scale)
    }
    private func slotButton(_ slot: HouseDecorSceneSlot, scale: CGFloat) -> some View {
        let item = HouseModuleAssets.decorCatalog?.items.first { $0.id == slot.item }
        let compatible = drag.item?.fits(slot.decorSlot) == true
        let color: Color = compatible ? .green : item == nil ? .white : Color(red: 1, green: 0.84, blue: 0.4)
        let width = max(24, slot.rect[2] * scale), height = max(24, slot.rect[3] * scale)
        return Button { selected = slot.key } label: {
            RoundedRectangle(cornerRadius: 7).fill(color.opacity(compatible ? 0.28 : 0.10))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: item == nil ? [7, 5] : [])))
                .overlay { if item == nil { Image(systemName: "plus").foregroundStyle(color).font(.system(size: 14, weight: .bold)) } }
        }
        .buttonStyle(.plain)
        .frame(width: width, height: height)
        .overlay {
            if let item { HouseDecorDragSource(item: item, source: slot.key, drag: drag, click: { selected = slot.key }) }
        }
        .opacity(drag.item != nil && !compatible ? 0.35 : 1)
        .accessibilityLabel(accessibilityLabel(slot, item: item))
        .accessibilityValue(item.map(HouseDecorNames.item) ?? L("空", "empty"))
        .popover(isPresented: Binding(get: { selected == slot.key }, set: { if !$0 { selected = nil } })) {
            slotMenu(slot).padding(12)
        }
        .position(x: (slot.rect[0] + slot.rect[2] / 2) * scale, y: (slot.rect[1] + slot.rect[3] / 2) * scale)
    }
    private func accessibilityLabel(_ slot: HouseDecorSceneSlot, item: HouseDecorCatalog.Item?) -> String {
        let room = m.houseRooms.first { $0.key == slot.room }?.title ?? slot.room
        return room + " · " + HouseDecorNames.slot(slot.slot) + L("装饰位", " decor slot") + " · "
            + (item.map { L("已放：", "") + HouseDecorNames.item($0) } ?? L("空", "empty"))
    }
    private func slotMenu(_ slot: HouseDecorSceneSlot) -> some View {
        let selection = Binding<String>(get: { config.decor?[slot.key]?.item ?? "auto" }, set: { place(slot.key, $0); selected = nil })
        return Picker(HouseDecorNames.slot(slot.slot), selection: selection) {
            Text(L("自动", "Automatic")).tag("auto")
            Text(L("不放", "None")).tag("none")
            ForEach(HouseModuleAssets.decorCatalog?.items.filter { $0.fits(slot.decorSlot) } ?? [], id: \.id) { item in
                Text(HouseDecorNames.item(item)).tag(item.id)
            }
        }.pickerStyle(.inline).frame(minWidth: 180)
    }
}

extension HouseDecorSceneSlot {
    var key: String { room + "/" + slot }
    var decorSlot: HouseDecorSlot { .init(id: slot, surface: surface, sizes: sizes, at: [x, y], wall: wall) }
}

struct HouseDecorSceneDrop: DropDelegate {
    let drag: HouseDecorDrag
    let slots: [HouseDecorSceneSlot]
    let scale: CGFloat
    let place: (String, String?, String?) -> Void
    var freeContext: HouseFreeDecorCanvas? = nil
    var freePlace: ((String, String, [Int], String?) -> Void)? = nil
    private func target(_ point: CGPoint) -> HouseDecorSceneSlot? {
        slots.first { slot in
            guard drag.item?.surface != "floor" || drag.item?.fits(slot.decorSlot) == true else { return false }
            return CGRect(x: slot.rect[0] * scale, y: slot.rect[1] * scale, width: slot.rect[2] * scale, height: slot.rect[3] * scale)
                .insetBy(dx: -6, dy: -6).contains(point)
        }
    }
    func validateDrop(info: DropInfo) -> Bool { drag.item != nil && info.hasItemsConforming(to: [.plainText]) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        drag.preview = target(info.location) == nil ? preview(info.location) : nil
        if let target = target(info.location) { return DropProposal(operation: drag.item?.fits(target.decorSlot) == true ? .move : .forbidden) }
        if let preview = drag.preview { return DropProposal(operation: preview.reason == nil ? .move : .forbidden) }
        return DropProposal(operation: drag.source == nil ? .forbidden : .move)
    }
    private func preview(_ point: CGPoint) -> HouseFreeDecorPreview? {
        guard let item = drag.item, scale > 0 else { return nil }
        return freeContext?.preview(at: CGPoint(x: point.x / scale, y: point.y / scale), item: item,
                                    source: drag.source.flatMap { $0.hasPrefix("free:") ? String($0.dropFirst(5)) : nil })
    }
    func dropExited(info: DropInfo) { drag.preview = nil }
    func performDrop(info: DropInfo) -> Bool {
        guard let item = drag.item else { return false }
        let target = target(info.location), origin = drag.source, payload = drag.payload
        let free = target == nil ? preview(info.location) : nil
        if free?.reason != nil { return false }
        if target == nil && free == nil && origin?.hasPrefix("free:") == true { return false }
        guard target == nil || target.map({ item.fits($0.decorSlot) }) == true else { return false }
        HouseDropPayload.load(info.itemProviders(for: [.plainText])) { value in
            guard value == payload else { return }
            if let target { place(target.key, item.id, origin) }
            else if let free { freePlace?(free.room, item.id, free.cell, origin) }
            else if let origin { place(origin, "none", nil) }
        }
        return true
    }
}

struct HouseDecorPanelDrop: DropDelegate {
    let drag: HouseDecorDrag
    let remove: (String) -> Void
    func validateDrop(info: DropInfo) -> Bool { drag.source != nil && info.hasItemsConforming(to: [.plainText]) }
    func performDrop(info: DropInfo) -> Bool {
        guard let source = drag.source else { return false }
        let payload = drag.payload
        HouseDropPayload.load(info.itemProviders(for: [.plainText])) { if $0 == payload { remove(source) } }
        return true
    }
}

private struct HouseDecorSceneProbe: NSViewRepresentable {
    let drag: HouseDecorDrag
    func makeNSView(context: Context) -> NSView { let view = NSView(); drag.sceneView = view; return view }
    func updateNSView(_ view: NSView, context: Context) {}
}

private struct HouseDecorDragSource: NSViewRepresentable {
    let item: HouseDecorCatalog.Item
    let source: String?
    let drag: HouseDecorDrag
    let click: () -> Void
    func makeNSView(context: Context) -> DragView { let view = DragView(); updateNSView(view, context: context); return view }
    func updateNSView(_ view: DragView, context: Context) { view.item = item; view.source = source; view.drag = drag; view.click = click }

    final class DragView: NSView, NSDraggingSource {
        var item: HouseDecorCatalog.Item?
        var source: String?
        var drag: HouseDecorDrag?
        var click: (() -> Void)?
        private var down: NSEvent?
        private var cancelled = false
        private var monitor: Any?
        override func mouseDown(with event: NSEvent) { down = event }
        override func mouseUp(with event: NSEvent) { if down != nil { down = nil; click?() } }
        override func mouseDragged(with event: NSEvent) {
            guard let down, let item, let drag, hypot(event.locationInWindow.x - down.locationInWindow.x, event.locationInWindow.y - down.locationInWindow.y) > 3 else { return }
            self.down = nil; cancelled = false
            drag.item = item; drag.source = source
            let pasteboard = NSPasteboardItem(); pasteboard.setString(drag.payload ?? "", forType: .string)
            let dragging = NSDraggingItem(pasteboardWriter: pasteboard)
            let image = item.sprites["day"]?.file(wall: item.surface == "wall" ? "nw" : nil).flatMap { HouseModuleAssets.decorURL($0) }.flatMap(NSImage.init(contentsOf:))
                ?? NSImage(size: NSSize(width: 32, height: 32))
            let point = convert(event.locationInWindow, from: nil)
            dragging.setDraggingFrame(CGRect(x: point.x - 24, y: point.y - 24, width: 48, height: 48), contents: image)
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { self?.cancelled = true }; return event
            }
            beginDraggingSession(with: [dragging], event: event, source: self)
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            drag?.end(at: screenPoint, operation: operation, cancelled: cancelled)
        }
    }
}
