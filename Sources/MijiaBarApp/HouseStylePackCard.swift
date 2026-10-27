import SwiftUI
import MijiaCore

struct HouseStylePackCard: View {
    let style: HouseStyleInfo
    let status: HouseStylePackStatus
    let selected: Bool
    var removalError: String? = nil
    var select: () -> Void
    var remove: () -> Void

    private var name: String { HouseStyles.displayName(style.id, zh: L("是", "no") == "是") }
    private var disabled: Bool {
        switch status { case .downloading, .unavailable: return true; default: return false }
    }
    private var preview: NSImage? {
        guard let url = HouseModuleAssets.resourceURL("module-living-day-unlit", "png", style: style.id, fallbackToDefault: false) else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: select) {
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        if let image = preview {
                            Image(nsImage: image).resizable().interpolation(.none).aspectRatio(contentMode: .fit)
                        } else {
                            Image(systemName: "arrow.down.circle").font(.system(size: 24)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 52).frame(maxWidth: .infinity).background(Theme.bg2)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    HStack {
                        Text(name).font(.system(size: 11, weight: .semibold))
                        Spacer()
                        if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(disabled)
            .accessibilityLabel(name)
            .accessibilityValue(selected ? L("已选择", "Selected") : L("未选择", "Not selected"))
            controls.font(.system(size: 11))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(selected ? Color.accentColor.opacity(0.12) : Theme.tile, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : Theme.stroke))
    }

    @ViewBuilder private var controls: some View {
        switch status {
        case .bundled:
            Text(L("已内置", "Bundled")).foregroundStyle(.secondary)
        case .installed:
            HStack {
                Text(L("已下载", "Downloaded")).foregroundStyle(.secondary)
                Button(L("移除", "Remove"), action: remove).accessibilityLabel(L("移除", "Remove") + " · " + name)
            }
            if let removalError { Text(removalError).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        case .available(let size):
            Button(L("下载", "Download") + " " + String(format: "%.1f MB", Double(size) / 1_000_000), action: select)
                .accessibilityLabel(name + " · " + L("下载", "Download") + " " + String(format: "%.1f MB", Double(size) / 1_000_000))
        case .downloading(let progress):
            ProgressView(value: progress).accessibilityLabel(name + " · " + L("下载中", "Downloading"))
                .accessibilityValue("\(Int(progress * 100))%")
            Text(L("下载中", "Downloading") + " \(Int(progress * 100))%").foregroundStyle(.secondary)
        case .failed(let reason):
            Text(reason).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(L("重试", "Retry"), action: select).accessibilityLabel(L("重试", "Retry") + " · " + name)
        case .unavailable:
            Text(L("暂不可用", "Unavailable")).foregroundStyle(.secondary)
        }
    }
}
