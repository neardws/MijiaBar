import SwiftUI
import AppKit
import MijiaCore

enum Theme {
    // 全部使用系统语义色，自动适配浅色/深色外观
    static let bg = Color(nsColor: .windowBackgroundColor)
    static let bg2 = Color(nsColor: .controlBackgroundColor)
    static let card = Color.primary.opacity(0.045)
    static let hover = Color.primary.opacity(0.09)
    static let stroke = Color.primary.opacity(0.08)
    static let tile = Color.primary.opacity(0.06)
    static let cool = Color(red: 0.30, green: 0.62, blue: 1.0)
    static let heat = Color(red: 1.0, green: 0.55, blue: 0.22)
    /// 温度色带：蓝 → 青 → 暖黄 → 橙（滑条和空调色调共用）
    static let warmStops: [(r: Double, g: Double, b: Double)] = [(0.25, 0.55, 1), (0.35, 0.85, 0.95), (1, 0.85, 0.4), (1, 0.5, 0.2)]
    /// 0 = 冷（蓝）… 1 = 热（橙）；沿温度色带取色，中间不会出现灰色
    static func warm(_ t: Double) -> Color {
        let x = max(0, min(1, t)) * Double(warmStops.count - 1)
        let i = min(Int(x), warmStops.count - 2), f = x - Double(i)
        let a = warmStops[i], b = warmStops[i + 1]
        return Color(red: a.r + (b.r - a.r) * f, green: a.g + (b.g - a.g) * f, blue: a.b + (b.b - a.b) * f)
    }
    static let sliderGradient = LinearGradient(colors: warmStops.map { Color(red: $0.r, green: $0.g, blue: $0.b) }, startPoint: .leading, endPoint: .trailing)
}

extension DeviceCategory {
    var icon: String {
        switch self {
        case .ac: return "air.conditioner.horizontal"
        case .plug: return "powerplug"
        case .light: return "lightbulb"
        case .fan: return "fan"
        case .heater: return "heater.vertical"
        case .dehumidifier: return "dehumidifier"
        case .sensor: return "thermometer.medium"
        case .tv: return "tv"
        case .camera: return "video"
        case .speaker: return "hifispeaker"
        case .kitchen: return "frying.pan"
        case .printer: return "printer"
        case .purifier: return "drop"
        case .other: return "square.grid.2x2"
        case .airPurifier: return "air.purifier"
        case .curtain: return "curtains.closed"
        case .fridge: return "refrigerator"
        case .washer: return "washer"
        case .waterHeater: return "drop.degreesign"
        }
    }
    var color: Color {
        switch self {
        case .ac: return Theme.cool
        case .plug: return .green
        case .light: return .yellow
        case .fan: return .teal
        case .heater: return Theme.heat
        case .dehumidifier: return .cyan
        case .sensor: return .mint
        case .tv: return .indigo
        case .camera: return .purple
        case .speaker: return .pink
        case .kitchen: return .orange
        case .printer: return .blue
        case .purifier: return .blue
        case .other: return .indigo
        case .airPurifier: return .cyan
        case .curtain: return .brown
        case .fridge: return .cyan
        case .washer: return .blue
        case .waterHeater: return Theme.heat
        }
    }
}

/// 同一类别里外形不一样的设备：插画和列表图标按型号区分
enum DeviceForm { case doorbell, motion, contact, leak }

extension Device {
    var form: DeviceForm? {
        let m = model.lowercased()
        switch category {
        case .camera: return m.contains(".cateye.") ? .doorbell : nil
        case .sensor:
            if m.contains("magnet") { return .contact }
            if m.contains("flood") || m.contains("wleak") { return .leak }
            return m.contains("motion") ? .motion : nil
        default: return nil
        }
    }
    var icon: String {
        switch form {
        case .doorbell: return "video.doorbell"
        case .motion: return "figure.walk.motion"
        case .contact: return "door.left.hand.closed"
        case .leak: return "drop.triangle"
        case nil: return category.icon
        }
    }
}

/// 常见 MIoT 属性/服务的中文名
func zhName(_ name: String, fallback: String) -> String {
    guard isChinese else {
        return fallback.isEmpty ? name : fallback
    }
    let m = ["on": "开关", "mode": "模式", "brightness": "亮度", "color-temperature": "色温", "color": "颜色", "target-temperature": "目标温度",
             "temperature": "温度", "relative-humidity": "湿度", "fan-level": "风速", "horizontal-swing": "左右摆风", "vertical-swing": "上下摆风",
             "electric-power": "功率", "power-consumption": "耗电量", "target-humidity": "目标湿度", "physical-controls-locked": "童锁",
             "alarm": "提示音", "indicator-light": "指示灯", "battery-level": "电量", "status": "状态", "fault": "故障", "speed-level": "风速档位",
             "countdown-time": "定时", "horizontal-angle": "摆风角度", "sleep-mode": "睡眠模式", "heat-level": "加热档位", "water-level": "水位",
             "switch": "开关", "light": "灯", "fan": "风扇", "air-conditioner": "空调", "heater": "取暖器", "dehumidifier": "除湿机",
             "environment": "环境", "battery": "电池", "fan-control": "风速控制", "power-consumption-service": "电量统计", "toggle": "切换",
             "electric-current": "电流", "default-power-on-state": "上电状态", "horizontal-swing-included-angle": "摆风角度", "brightness-delay": "渐变时长", "night-light": "夜灯", "volume": "音量", "mute": "静音", "power-off-delay-time": "延时关闭", "anion": "负离子", "child-lock": "童锁", "filter-life-level": "滤芯寿命", "dry-after-off": "关机烘干", "fan-percent": "风速", "speed": "转速", "illumination": "光照", "motion-state": "有人移动", "submersion-state": "浸水", "contact-state": "开合", "gas-concentration": "燃气浓度", "voltage": "电压", "temperature-humidity-sensor": "温湿度传感器", "screen": "屏幕", "flow-rate": "流速",
             "pm2.5-density": "PM2.5", "pm10-density": "PM10", "air-quality-index": "空气质量指数", "air-quality": "空气质量", "air-purifier": "空气净化器", "filter": "滤芯"]
    return m[name].map { L($0, $0) } ?? (fallback.isEmpty ? name : fallback)
}
