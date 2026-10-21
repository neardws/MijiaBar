import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import MijiaCore

extension AppModel {
    @discardableResult
    func houseSavePet(_ pet: HousePet, label: String) -> Bool {
        var failure: Error?
        let saved = houseEdit(label) { file in
            var pet = pet; pet.updatedAt = Date()
            do { try file.setPet(home: houseHomeKey, pet: pet) } catch { failure = error }
        }
        if let failure { showToast(failure.localizedDescription, error: true); return false }
        return saved
    }

    func houseChangePet(_ id: String, _ change: (inout HousePet) -> Void) {
        houseEdit(L("宠物", "Pets")) { file in
            guard var pet = file.homes[houseHomeKey]?.pets?[id], !pet.deleted else { return }
            change(&pet); pet.updatedAt = Date()
            do { try file.setPet(home: houseHomeKey, pet: pet) }
            catch { showToast(error.localizedDescription, error: true) }
        }
    }
}

enum HousePetPatterns {
    static func name(_ pattern: String) -> String {
        switch pattern {
        case "tabby": return L("虎斑", "Tabby")
        case "tabbyWhite": return L("虎斑加白", "Tabby & white")
        case "bicolor": return L("双色", "Bicolor")
        case "calico": return L("三花", "Calico")
        case "colorpoint": return L("重点色", "Colorpoint")
        default: return L("纯色", "Solid")
        }
    }
}

@MainActor
private final class HousePetPreviewCache {
    static let shared = HousePetPreviewCache()
    private struct Key: Hashable {
        let directory: URL
        let rig: String
        let pattern: String
        let palette: [String]
        let animated: Bool
    }
    private var cache: [Key: [Int: CGImage]] = [:]

    func frames(pet: HousePet, painter: HousePetPainter, animated: Bool) -> [Int: CGImage]? {
        guard let rig = painter.rig, let directory = painter.directory else { return nil }
        let key = Key(directory: directory, rig: rig.id, pattern: pet.pattern,
                      palette: [pet.palette.base, pet.palette.second, pet.palette.white, pet.palette.eye], animated: animated)
        if let frames = cache[key] { return frames }
        guard let frames = try? painter.cache.frames(pet: pet, rig: rig, directory: directory, phase: "day") else { return nil }
        let indices = HousePetPreviewGeometry.frameIndices(rig: rig, animated: animated)
        guard indices.allSatisfy({ frames.indices.contains($0) }),
              let pixels = try? indices.map({ try HousePetSheet.decode(frames[$0]).rgba }) else { return nil }
        let bounds = HousePetPreviewGeometry.unionBounds(frames: pixels, width: rig.frameSize[0], height: rig.frameSize[1])
        let rect = bounds.map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        let cropped = Dictionary(uniqueKeysWithValues: indices.map { index in
            (index, rect.flatMap { frames[index].cropping(to: $0) } ?? frames[index])
        })
        if cache.count >= 32 { cache.removeAll() }
        cache[key] = cropped
        return cropped
    }
}

struct HousePetPreview: View {
    let pet: HousePet
    var size: CGFloat = 140
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var backingScale
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var visible = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 8, paused: !animated || reduceMotion || lowPower || !visible)) { tick in
            let time = animated && !reduceMotion && !lowPower ? tick.date.timeIntervalSinceReferenceDate : 0
            if let rig = HousePetPainter.shared.rig,
               let frames = HousePetPreviewCache.shared.frames(pet: pet, painter: HousePetPainter.shared, animated: animated) {
                let action = Int(time / 6) % 2 == 0 ? "sit" : "idle"
                let index = rig.frame(action: action, facing: "SE", elapsed: time).index
                if let image = frames[index] {
                    let scale = HousePetPreviewGeometry.displayScale(width: image.width, height: image.height,
                                                                    boxWidth: size, boxHeight: size, backingScale: backingScale)
                    Image(decorative: image, scale: 1).resizable().interpolation(.none)
                        .frame(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                        .frame(width: size, height: size, alignment: .bottom)
                }
            }
        }
        .frame(width: size, height: size).accessibilityHidden(true)
        .background(HousePetVisibilityProbe(visible: $visible))
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
    }
}

struct HousePetAppearanceFields: View {
    @Binding var pet: HousePet
    var body: some View {
        TextField(L("名字", "Name"), text: $pet.name).textFieldStyle(.roundedBorder)
            .accessibilityLabel(L("宠物名字", "Pet name"))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 6) {
            ForEach(HousePetRig.patterns, id: \.self) { pattern in
                Button { pet.pattern = pattern } label: {
                    VStack(spacing: 2) {
                        HousePetPreview(pet: patterned(pattern), size: 52, animated: false)
                        Text(HousePetPatterns.name(pattern)).font(.system(size: 10))
                    }.frame(maxWidth: .infinity).padding(4)
                        .background(pet.pattern == pattern ? Color.accentColor.opacity(0.15) : Theme.tile, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).accessibilityLabel(HousePetPatterns.name(pattern))
                    .accessibilityValue(pet.pattern == pattern ? L("已选择", "Selected") : L("未选择", "Not selected"))
            }
        }
        HStack {
            well(L("主色", "Base"), \.base)
            well(L("副色", "Second"), \.second)
            well(L("白色", "White"), \.white)
            well(L("眼睛", "Eyes"), \.eye)
        }
    }

    private func patterned(_ pattern: String) -> HousePet { var value = pet; value.pattern = pattern; return value }
    private func well(_ title: String, _ key: WritableKeyPath<HousePetPalette, String>) -> some View {
        ColorPicker(title, selection: Binding(get: { Self.color(pet.palette[keyPath: key]) }, set: { pet.palette[keyPath: key] = Self.hex($0) }), supportsOpacity: false)
            .font(.system(size: 10)).accessibilityLabel(title).accessibilityValue(pet.palette[keyPath: key])
    }
    static func color(_ hex: String) -> Color {
        let number = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return Color(red: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255)
    }
    static func hex(_ color: Color) -> String {
        guard let value = NSColor(color).usingColorSpace(.sRGB) else { return "#000000" }
        func channel(_ component: CGFloat) -> Int { Int((min(1, max(0, component)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channel(value.redComponent), channel(value.greenComponent), channel(value.blueComponent))
    }
}

struct HousePetsEditor: View {
    @EnvironmentObject var m: AppModel
    var date: Date? = nil
    @State private var photo: HousePetPhotoDraft?
    @State private var analyzing = false
    @State private var request: Task<Void, Never>?
    private var pets: [HousePet] { (m.house.homes[m.houseHomeKey]?.pets ?? [:]).values.filter { !$0.deleted }.sorted { $0.id < $1.id } }
    private var full: Bool { pets.count >= HouseFile.petLimit }

    var body: some View {
        HStack(spacing: 0) {
            HouseCutawaySceneView(rooms: m.houseRooms, phase: .from(date: date ?? Date()), fitWidth: 470,
                                  layout: m.houseLayoutCells, style: m.houseStyle, decorConfig: m.house.homes[m.houseHomeKey] ?? HomeHouse(), petDate: date)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(L("显示宠物", "Show pets"), isOn: Binding(get: { m.house.homes[m.houseHomeKey]?.petPrefs?.enabled ?? true }, set: { value in
                        m.houseEdit(L("显示宠物", "Show pets")) { $0.setPetPrefs(home: m.houseHomeKey, enabled: value) }
                    }))
                    ForEach(pets, id: \.id) { pet in card(pet) }
                    Menu {
                        Button(L("从照片生成…", "Generate from photo…"), action: choosePhoto)
                        Button(L("手动选择", "Choose manually")) {
                            _ = m.houseSavePet(HousePet(name: L("橘子", "Orange"), pattern: "tabbyWhite"), label: L("添加宠物", "Add pet"))
                        }
                    } label: { Label(L("添加宠物", "Add pet"), systemImage: "plus") }
                    .disabled(full || analyzing)
                    if full { Text(L("最多添加 3 只宠物，请先移除一只", "At most 3 pets are allowed; remove one first")).font(.caption).foregroundStyle(.secondary) }
                    if analyzing { ProgressView(L("正在本机分析…", "Analyzing on this Mac…")) }
                    Text(L("照片只在本机分析，不会保存或上传", "Photos are analyzed on this Mac only, never saved or uploaded"))
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(18)
            }.frame(width: 540)
        }.background(Theme.bg)
        .sheet(item: $photo) { draft in
            HousePetPhotoSheet(draft: draft) { pet in
                if m.houseSavePet(pet, label: L("添加宠物", "Add pet")) { photo = nil }
            } cancel: { photo = nil }
        }
        .onDisappear { request?.cancel(); request = nil; photo = nil; analyzing = false }
        .onChange(of: m.houseHomeKey) { _, _ in photo = nil }
    }

    private func card(_ pet: HousePet) -> some View {
        HStack(alignment: .top, spacing: 10) {
            HousePetPreview(pet: pet, size: 110, animated: date == nil)
            VStack(alignment: .leading, spacing: 8) {
                HousePetAppearanceFields(pet: binding(pet))
                Picker(L("房间", "Room"), selection: Binding(get: { pet.homeRoom ?? "" }, set: { value in m.houseChangePet(pet.id) { $0.homeRoom = value.isEmpty ? nil : value } })) {
                    Text(L("自由活动", "Roam freely")).tag("")
                    ForEach(m.houseRooms) { room in Text(room.title).tag(room.key) }
                }.accessibilityLabel(L("宠物活动房间", "Pet room"))
                HStack {
                    Toggle(L("启用", "Enabled"), isOn: Binding(get: { pet.enabled }, set: { value in m.houseChangePet(pet.id) { $0.enabled = value } }))
                    Spacer()
                    Button(L("移除", "Remove"), role: .destructive) { m.houseChangePet(pet.id) { $0.deleted = true } }
                }
            }
        }.padding(12).background(Theme.tile, in: RoundedRectangle(cornerRadius: 12))
    }

    private func binding(_ pet: HousePet) -> Binding<HousePet> {
        Binding(get: { m.house.homes[m.houseHomeKey]?.pets?[pet.id] ?? pet }, set: { value in
            m.houseChangePet(pet.id) { current in
                if value.name != pet.name { current.name = value.name }
                if value.pattern != pet.pattern { current.pattern = value.pattern }
                for key in [\HousePetPalette.base, \.second, \.white, \.eye] where value.palette[keyPath: key] != pet.palette[keyPath: key] {
                    current.palette[keyPath: key] = value.palette[keyPath: key]
                }
            }
        })
    }

    private func choosePhoto() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            let home = m.houseHomeKey
            analyzing = true
            request = Task { @MainActor in
                defer { analyzing = false; request = nil }
                do {
                    let draft = try await Task.detached(priority: .userInitiated) { try HousePetPhotoDraft.load(url) }.value
                    guard !Task.isCancelled, m.houseHomeKey == home else { return }
                    photo = draft
                } catch { if !Task.isCancelled { m.showToast(error.localizedDescription, error: true) } }
            }
        }
    }
}

struct HousePetPhotoDraft: Identifiable, @unchecked Sendable {
    let id = UUID()
    let image: CGImage
    let mask: [UInt8]
    let result: HousePetPhoto.Result
    static func load(_ url: URL) throws -> Self {
        let analysis = try HousePetPhoto.loadAnalysis(from: url)
        return .init(image: analysis.image, mask: analysis.mask, result: analysis.result)
    }
}

private struct HousePetPhotoSheet: View {
    let draft: HousePetPhotoDraft
    let add: (HousePet) -> Void
    let cancel: () -> Void
    @State private var pet: HousePet
    init(draft: HousePetPhotoDraft, add: @escaping (HousePet) -> Void, cancel: @escaping () -> Void) {
        self.draft = draft; self.add = add; self.cancel = cancel
        _pet = State(initialValue: HousePet(name: L("橘子", "Orange"), pattern: draft.result.pattern, palette: draft.result.palette))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 24) {
                Image(decorative: draft.image, scale: 1).resizable().scaledToFit().frame(width: 250, height: 300)
                VStack {
                    HousePetPreview(pet: pet, size: 180)
                    HousePetAppearanceFields(pet: $pet)
                }.frame(width: 330)
            }
            Text(L("照片只在本机分析，不会保存或上传", "Photos are analyzed on this Mac only, never saved or uploaded")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(L("取消", "Cancel"), action: cancel).keyboardShortcut(.cancelAction)
                Button(L("添加", "Add")) { add(pet) }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).background(Theme.bg)
    }
}
