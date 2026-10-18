import Foundation

/// Built-in style + palette sub-variants (Phase 3a milestone 1).
/// Full art styles live under Resources/House/styles/<id>/; palette variants share
/// cozy-wood anchors/catalog and swap wall/floor colours via baked PNGs.
public struct HouseStyleInfo: Equatable, Sendable, Identifiable {
    public var id: String
    public var nameZh: String
    public var nameEn: String
    public var kind: Kind
    public var parent: String?
    public enum Kind: String, Sendable { case builtin, palette, art }
    public var hasOwnCatalog: Bool { kind == .art }
    public var hasClassicArt: Bool { kind != .art }
}

public enum HouseStyles {
    public static let defaultStyle = "cozy-wood"

    public static let all: [HouseStyleInfo] = [
        .init(id: "cozy-wood", nameZh: "温馨木屋", nameEn: "Cozy wood", kind: .builtin, parent: nil),
        .init(id: "light-wood", nameZh: "浅木白墙", nameEn: "Light wood", kind: .palette, parent: "cozy-wood"),
        .init(id: "walnut", nameZh: "胡桃木", nameEn: "Walnut", kind: .palette, parent: "cozy-wood"),
        .init(id: "japanese", nameZh: "和风", nameEn: "Japanese", kind: .art, parent: nil),
        .init(id: "modern", nameZh: "现代", nameEn: "Modern", kind: .art, parent: nil),
    ]

    public static func info(_ id: String?) -> HouseStyleInfo {
        let key = resolve(id)
        return all.first { $0.id == key } ?? all[0]
    }

    public static func resolve(_ id: String?) -> String {
        let key = (id?.isEmpty == false) ? id! : defaultStyle
        return all.contains(where: { $0.id == key }) ? key : defaultStyle
    }

    public static func displayName(_ id: String?, zh: Bool) -> String {
        let i = info(id)
        return zh ? i.nameZh : i.nameEn
    }
}
