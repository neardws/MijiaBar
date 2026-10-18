import Foundation

/// 设备属性 → 小屋状态（窗帘位置、热水器 / 洗衣机是否在工作），以及窗帘贴片露出的范围
public enum HouseDeviceState {
    /// 0（全关）..1（全开）；没有位置属性 → nil（App 按开关当全开 / 全关）
    public static func curtainPosition(_ st: DeviceState?) -> Double? {
        guard let st, let spec = st.spec,
              let p = spec.prop(named: "current-position") ?? spec.prop(named: "target-position"),
              let v = st.values[p.key]?.doubleValue else { return nil }
        let hi = p.range.flatMap { $0.count >= 2 ? $0[1] : nil } ?? 100
        let lo = p.range.flatMap { $0.first } ?? 0
        guard hi > lo else { return nil }
        return min(1, max(0, (v - lo) / (hi - lo)))
    }

    public static let busyWords = ["busy", "wash", "rins", "spin", "dry", "run", "work", "heat"]
    /// status 属性的当前选项描述里有「工作中」的词 → true；没有 status 属性 / 读不到 → otherwise
    public static func busy(_ st: DeviceState?, otherwise: Bool) -> Bool {
        guard let st, let spec = st.spec, let p = spec.prop(named: "status"), let opts = p.options,
              let v = st.values[p.key]?.doubleValue else { return otherwise }
        guard let o = opts.first(where: { Double($0.value) == v }) else { return otherwise }
        let d = o.description.lowercased()
        return busyWords.contains { d.contains($0) }
    }

    /// 关上的窗帘贴片露出哪几段 x（左右两片从窗外沿往中线 mid 拉，2px 对齐）；closed 0 = 全开（不画），1 = 全关
    public static func curtainVisibleRanges(x0: Double, x1: Double, mid: Double, closed: Double) -> [ClosedRange<Double>] {
        let c = min(1, max(0, closed))
        guard c > 0.005 else { return [] }
        func snap(_ v: Double) -> Double { (v / 2).rounded() * 2 }
        let l = snap(x0 + (mid - x0) * c), r = snap(x1 - (x1 - mid) * c)
        if l >= r { return [x0...x1] }
        return [x0...max(x0, l), min(x1, r)...x1]
    }
}
