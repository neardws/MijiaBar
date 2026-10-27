import Foundation

public enum HouseAutoLayout {
    public static let moduleOrder: [HouseModule] = [.living, .bedroom, .kitchen, .bathroom, .balcony, .study, .generic]

    static func roomOverride(_ key: String, sample: Device?, config: HomeHouse) -> HouseRoomOverride? {
        if let override = config.rooms[key], override.module != nil { return override }
        if let name = sample?.roomName, let override = config.rooms["name:" + name], override.module != nil { return override }
        return nil
    }

    static func mappedModule(_ key: String, sample: Device?, config: HomeHouse) -> HouseModule? {
        let override = roomOverride(key, sample: sample, config: config)
        if override?.module == "none" { return nil }
        if let raw = override?.module, let module = HouseModule(rawValue: raw) { return module }
        guard !key.isEmpty else { return nil }
        let module = HouseModule.from(roomName: sample?.roomName)
        return module != .generic || HouseModule.isEntryFoyer(roomName: sample?.roomName) ? module : nil
    }

    public static func effective(devices: [Device], config: HomeHouse?, isHidden: (Device) -> Bool) -> [HouseLayoutCell]? {
        let config = config ?? HomeHouse()
        if let saved = config.layout { return saved }
        struct Candidate {
            let key: String
            let module: HouseModule
            let pinned: Bool
            let score: Int
            let shownCount: Int
        }
        let groups = Dictionary(grouping: devices.sorted { $0.did < $1.did }, by: HouseResolver.roomKey)
        var candidates: [Candidate] = []
        for (key, devices) in groups {
            guard !key.isEmpty, let module = mappedModule(key, sample: devices.first, config: config) else { continue }
            let shown = devices.filter { $0.isOnline && (config.devices[$0.did]?.visible ?? !isHidden($0)) && HouseCatalog.showable($0.category) }
            let fits = shown.filter { device in HouseCatalog.fixtures(module).contains { $0.accepts(device.category) } }.count
            candidates.append(.init(key: key, module: module,
                                    pinned: roomOverride(key, sample: devices.first, config: config) != nil,
                                    score: fits * 100 + shown.count, shownCount: shown.count))
        }
        guard candidates.contains(where: { $0.shownCount > 0 && [.kitchen, .bathroom, .balcony].contains($0.module) }) else { return nil }
        let winners = moduleOrder.compactMap { module in
            candidates.filter { $0.module == module }.sorted {
                if $0.pinned != $1.pinned { return $0.pinned }
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.key < $1.key
            }.first
        }.sorted {
            let left = moduleOrder.firstIndex(of: $0.module)!, right = moduleOrder.firstIndex(of: $1.module)!
            if left < 2 || right < 2 { return left < right }
            if $0.score != $1.score { return $0.score > $1.score }
            return left != right ? left < right : $0.key < $1.key
        }
        var capacity = HouseLayoutSolver.maxCells
        let selected = winners.filter { candidate in
            let width = HouseLayoutSolver.defaultFootprint(candidate.module.rawValue).0
            guard width <= capacity else { return false }
            capacity -= width
            return true
        }
        let cells = HouseLayoutSolver.autolayout(rooms: selected.map { candidate in
            (key: candidate.key, module: candidate.module, score: moduleOrder.count - moduleOrder.firstIndex(of: candidate.module)!)
        })
        return HouseLayoutSolver.isClassicGeometry(cells) ? nil : cells
    }

    public static func source(config: HomeHouse?, effective: [HouseLayoutCell]?) -> String {
        config?.layout != nil ? "saved" : effective == nil ? "classic" : "auto"
    }

    public static func classic(devices: [Device], config: HomeHouse?, isHidden: (Device) -> Bool) -> [HouseLayoutCell] {
        let resolved = HouseResolver.resolve(devices: devices, config: config, isHidden: isHidden,
                                             name: { $0.name }, layout: HouseLayoutSolver.classicFour)
        return HouseLayoutSolver.classicFour.enumerated().map { index, cell in
            .init(room: resolved.rooms.first { $0.module.rawValue == cell.module }?.key ?? "slot\(index)",
                  module: cell.module, col: cell.col, row: cell.row)
        }
    }
}
