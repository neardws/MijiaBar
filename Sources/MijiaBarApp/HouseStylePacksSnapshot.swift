import SwiftUI
import AppKit
import MijiaCore

extension Snapshot {
    static func houseStylePacks(dir: String) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: dir)
        do { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        catch { fputs("style packs snapshot: \(error)\n", stderr); exit(1) }
        let store = HouseStylePackStore(mockStatuses: [
            "cozy-wood": .bundled, "light-wood": .available(size: 9_563_089),
            "walnut": .downloading(progress: 0.4), "japanese": .failed(reason: HouseStylePackError.hashMismatch.localizedDescription),
            "modern": .installed(version: 1),
        ])
        let picker = VStack(alignment: .leading, spacing: 16) {
            Text(L("小屋风格", "House style")).font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: 3), alignment: .leading, spacing: 16) {
                ForEach(HouseStyles.all) { style in
                    HouseStylePackCard(style: style, status: store.status(style.id), selected: style.id == "cozy-wood", select: {}, remove: {})
                }
            }
            Spacer()
        }.padding(20).background(Theme.bg)
        for (suffix, appearanceName) in [("", NSAppearance.Name.aqua), ("-dark", NSAppearance.Name.darkAqua)] {
            appearance = NSAppearance(named: appearanceName)
            render(picker, output.appendingPathComponent("style-packs-picker\(suffix).png"), size: CGSize(width: 720, height: 460))
        }
        exit(0)
    }
}
