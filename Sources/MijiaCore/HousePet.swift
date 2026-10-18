import Foundation

public struct HousePetPalette: Codable, Equatable, Hashable, Sendable {
    public var base: String
    public var second: String
    public var white: String
    public var eye: String
    public init(base: String = "#E8973F", second: String = "#B3561C", white: String = "#F4EEE4", eye: String = "#9CC43E") {
        self.base = base; self.second = second; self.white = white; self.eye = eye
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        base = try values.decodeIfPresent(String.self, forKey: .base) ?? defaults.base
        second = try values.decodeIfPresent(String.self, forKey: .second) ?? defaults.second
        white = try values.decodeIfPresent(String.self, forKey: .white) ?? defaults.white
        eye = try values.decodeIfPresent(String.self, forKey: .eye) ?? defaults.eye
    }
    public var isValid: Bool { [base, second, white, eye].allSatisfy { $0.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil } }
}

public struct HousePet: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var species: String
    public var rig: String
    public var pattern: String
    public var palette: HousePetPalette
    public var enabled: Bool
    public var homeRoom: String?
    public var updatedAt: Date
    public var deleted: Bool
    public init(id: String = "p_" + UUID().uuidString.prefix(6).lowercased(), name: String = "", species: String = "cat",
                rig: String = "cat-short", pattern: String = "solid", palette: HousePetPalette = .init(), enabled: Bool = true,
                homeRoom: String? = nil, updatedAt: Date = Date(), deleted: Bool = false) {
        self.id = id; self.name = name; self.species = species; self.rig = rig; self.pattern = pattern; self.palette = palette
        self.enabled = enabled; self.homeRoom = homeRoom; self.updatedAt = updatedAt; self.deleted = deleted
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        species = try values.decodeIfPresent(String.self, forKey: .species) ?? "cat"
        rig = try values.decodeIfPresent(String.self, forKey: .rig) ?? "cat-short"
        pattern = try values.decodeIfPresent(String.self, forKey: .pattern) ?? "solid"
        palette = try values.decodeIfPresent(HousePetPalette.self, forKey: .palette) ?? .init()
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        homeRoom = try values.decodeIfPresent(String.self, forKey: .homeRoom)
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        deleted = try values.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
    }
}

public struct HousePetPrefs: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var updatedAt: Date
    public init(enabled: Bool = true, updatedAt: Date = .distantPast) { self.enabled = enabled; self.updatedAt = updatedAt }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}

public enum HousePetError: LocalizedError {
    case limit, invalid, resource
    public var errorDescription: String? {
        switch self {
        case .limit: return L("最多添加 3 只宠物，请先移除一只", "At most 3 pets are allowed; remove one first")
        case .invalid: return L("宠物参数无效", "Invalid pet parameters")
        case .resource: return L("宠物资源无效或缺失", "Invalid or missing pet resource")
        }
    }
}

extension HouseFile {
    public static let petLimit = 3
    public mutating func setPet(home: String, pet: HousePet) throws {
        guard pet.id.range(of: "^p_[0-9a-fA-F]{4,6}$", options: .regularExpression) != nil,
              pet.species == "cat", pet.rig == "cat-short", pet.palette.isValid,
              HousePetRig.patterns.contains(pet.pattern) else { throw HousePetError.invalid }
        var config = homes[home] ?? HomeHouse()
        let count = (config.pets ?? [:]).values.filter { !$0.deleted && $0.id != pet.id }.count
        guard pet.deleted || config.pets?[pet.id]?.deleted == false || count < Self.petLimit else { throw HousePetError.limit }
        if config.pets == nil { config.pets = [:] }; config.pets?[pet.id] = pet; homes[home] = config
    }
    public mutating func setPetPrefs(home: String, enabled: Bool, now: Date = Date()) {
        var config = homes[home] ?? HomeHouse(); config.petPrefs = .init(enabled: enabled, updatedAt: now); homes[home] = config
    }
}
