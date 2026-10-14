import SwiftUI

/// 房子轮廓：一条连续的圆角五边形（屋顶 + 墙）
struct HouseGlyph: Shape {
    func path(in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        let pts = [p(0.5, 0.0), p(1.0, 0.40), p(1.0, 1.0), p(0.0, 1.0), p(0.0, 0.40)]
        let radii: [CGFloat] = [0.11, 0.07, 0.11, 0.11, 0.07].map { $0 * r.width }
        var path = Path()
        path.move(to: CGPoint(x: (pts[4].x + pts[0].x) / 2, y: (pts[4].y + pts[0].y) / 2))
        for i in 0..<pts.count { path.addArc(tangent1End: pts[i], tangent2End: pts[(i + 1) % pts.count], radius: radii[i]) }
        path.closeSubpath()
        return path
    }
}

/// 品牌标志（应用图标和登录页共用）：天蓝色单色渐变圆角方块 + 白色房子，门里透出暖光（冷暖都在家里，对应空调制冷/制热）。
/// 只用一种冷色加一点暖色点缀，避免蓝橙直接混合出的灰浊中间色。
struct BrandMark: View {
    let size: CGFloat
    /// 应用图标按 macOS 图标模板自带投影，这里关掉
    var shadow = true
    var body: some View {
        let s = size, shape = RoundedRectangle(cornerRadius: s * 0.2237, style: .continuous)
        let hw = s * 0.50, hh = s * 0.48
        ZStack {
            shape.fill(LinearGradient(colors: [Color(red: 0.42, green: 0.74, blue: 1), Color(red: 0.13, green: 0.40, blue: 0.98)], startPoint: .top, endPoint: .bottom))
            shape.fill(RadialGradient(colors: [.white.opacity(0.28), .white.opacity(0)], center: UnitPoint(x: 0.3, y: 0.08), startRadius: 0, endRadius: s * 0.8))
            shape.stroke(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0)], startPoint: .top, endPoint: .center), lineWidth: max(0.75, s / 64))
            ZStack(alignment: .bottom) {
                HouseGlyph().fill(Color.white)
                    .shadow(color: Color(red: 0.05, green: 0.2, blue: 0.6).opacity(0.25), radius: s * 0.04, y: s * 0.02)
                UnevenRoundedRectangle(topLeadingRadius: hw * 0.12, topTrailingRadius: hw * 0.12, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.80, blue: 0.42), Color(red: 1, green: 0.55, blue: 0.22)], startPoint: .top, endPoint: .bottom))
                    .frame(width: hw * 0.26, height: hh * 0.40)
                    .shadow(color: Color(red: 1, green: 0.6, blue: 0.2).opacity(0.55), radius: s * 0.035)
            }
            .frame(width: hw, height: hh).offset(y: s * 0.03)
        }
        .frame(width: s, height: s)
        .shadow(color: .black.opacity(shadow ? 0.16 : 0), radius: s * 0.1, y: s * 0.05)
    }
}
