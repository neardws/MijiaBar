"""洗衣机 / 热水器的 SDF 模型 + App 动态叠加层的锚点（显示屏、指示灯、滚筒门），都从同一份几何算出来。"""
from __future__ import annotations
import numpy as np
from appliance_render import S, CZ, world, proj, sd_box, sd_cyl_x, sd_cyl_y, sd_cyl_z, sd_torus_x

ENAMEL, CHROME, GLASS, DARK, SCREEN, PLASTIC, PIPE, STRAP = range(8)
MATS = {  # albedo, spec, shininess, env（环境反射强度）
    ENAMEL: ((0.95, 0.93, 0.89), 0.22, 24, 0.06), CHROME: ((0.42, 0.43, 0.45), 0.95, 50, 0.85),
    GLASS: ((0.07, 0.10, 0.15), 0.9, 90, 0.10), DARK: ((0.15, 0.15, 0.17), 0.25, 16, 0.05),
    SCREEN: ((0.05, 0.07, 0.09), 0.7, 70, 0.08), PLASTIC: ((0.82, 0.82, 0.81), 0.3, 24, 0.08),
    PIPE: ((0.55, 0.53, 0.50), 0.8, 40, 0.6), STRAP: ((0.55, 0.55, 0.56), 0.4, 20, 0.1),
}

def material(p, n, ids):
    alb = np.zeros((len(p), 3)); spec = np.zeros(len(p)); shin = np.ones(len(p)); env = np.zeros(len(p))
    for k, (a, s, h, e) in MATS.items():
        m = ids == k; alb[m] = a; spec[m] = s; shin[m] = h; env[m] = e
    return alb, spec, shin, env

def _u(*pairs):
    d = np.full(len(pairs[0][0]), 1e9); ids = np.zeros(len(d), int)
    for dd, i in pairs:
        m = dd < d; d = np.where(m, dd, d); ids = np.where(m, i, ids)
    return d, ids

# ---------------- 洗衣机（阳台 NW 墙根，u 0..0.15, v 0.70..0.86） ----------------
class Washer:
    X0, X1 = 1.5, 0.15 * S
    Y0, Y1 = 0.70 * S, 0.86 * S
    H = 38 * CZ
    def __init__(s):
        s.Xc = (s.X0 + s.X1) / 2; s.Yc = (s.Y0 + s.Y1) / 2
        s.F = s.X1                     # 正面 X
        s.Zd = 0.42 * s.H              # 门中心高度
        s.Rg = 8.6                     # 玻璃半径
        s.Rr = 10.9                    # 门圈半径
    def scene(s, p):
        F, Yc, H = s.F, s.Yc, s.H
        body = sd_box(p, np.array([s.Xc, Yc, H / 2]), (s.X1 - s.Xc, (s.Y1 - s.Y0) / 2, H / 2), 2.0)
        # 槽：面板下沿、踢脚板、顶盖前沿
        for z, hh in ((H - 7.6, 0.35), (3.0, 0.3)):
            body = np.maximum(body, -sd_box(p, np.array([F, Yc, z]), (0.7, 20, hh)))
        body = np.maximum(body, -sd_box(p, np.array([s.Xc, Yc, H]), (s.X1 - s.Xc - 3.2, 20, 0.25)))
        # 显示屏凹槽 + 门洞
        disp_c = np.array([F, s.Y0 + 7.0, H - 4.2]); disp_h = (0.5, 4.4, 1.8)
        body = np.maximum(body, -sd_box(p, disp_c, disp_h, 0.3))
        body = np.maximum(body, -sd_cyl_x(p, np.array([F, Yc, s.Zd]), s.Rg + 0.6, 1.2))
        screen = sd_box(p, disp_c - np.array([0.35, 0, 0]), (0.15, 4.3, 1.7))
        drawer = sd_box(p, np.array([F + 0.15, s.Y1 - 6.4, H - 4.0]), (0.35, 4.6, 2.2), 0.3)
        dial = sd_cyl_x(p, np.array([F + 0.9, Yc + 0.2, H - 4.0]), 2.2, 0.9, 0.5)
        dial_cap = sd_cyl_x(p, np.array([F + 1.6, Yc + 0.2, H - 4.0]), 1.1, 0.3, 0.2)
        bezel = np.maximum(sd_cyl_x(p, np.array([F + 0.2, Yc, s.Zd]), s.Rr + 1.8, 0.35, 0.3), -sd_cyl_x(p, np.array([F, Yc, s.Zd]), s.Rr - 0.4, 2.0))
        ring = sd_torus_x(p, np.array([F + 0.9, Yc, s.Zd]), s.Rr, 1.25)
        gasket = sd_torus_x(p, np.array([F + 0.3, Yc, s.Zd]), s.Rg + 0.7, 0.8)
        glass = sd_cyl_x(p, np.array([F - 0.2, Yc, s.Zd]), s.Rg, 0.7, 0.6)
        handle = sd_box(p, np.array([F + 1.4, Yc - s.Rr - 0.6, s.Zd]), (0.9, 0.9, 2.6), 0.5)
        return _u((body, ENAMEL), (screen, SCREEN), (drawer, PLASTIC), (dial, CHROME), (dial_cap, DARK),
                  (bezel, PLASTIC), (ring, CHROME), (gasket, DARK), (glass, GLASS), (handle, CHROME))
    def material(s, p, n, ids):
        alb, spec, shin, env = material(p, n, ids)
        g = ids == GLASS
        if g.any():
            dy, dz = (s.Yc - p[g, 1]) / s.Rg, (p[g, 2] - s.Zd) / s.Rg        # dy>0 = 屏幕右
            r = np.hypot(dy, dz)
            base = np.array([0.06, 0.09, 0.14]) + np.array([0.07, 0.10, 0.14]) * np.clip(dz * 0.5 + 0.5, 0, 1)[:, None]
            base = base * (1 - 0.45 * np.clip((r - 0.7) / 0.3, 0, 1))[:, None]           # 边缘一圈更暗（滚筒深处）
            streak = np.exp(-((-dy * 0.7 + dz * 0.7) - 0.38) ** 2 / 0.012) * (r < 0.85)
            alb[g] = base + np.array([0.55, 0.62, 0.68]) * (streak * 0.55)[:, None]
        return alb, spec, shin, env
    def bbox(s, T):
        pts = [proj(world(0, 0, 0) + np.array([x, y, z]), T) for x in (0, s.F + 2) for y in (s.Y0, s.Y1) for z in (0, s.H)]
        xs, ys = [q[0] for q in pts], [q[1] for q in pts]
        return int(min(xs)) - 8, int(min(ys)) - 6, int(max(xs)) + 14, int(max(ys)) + 10
    def anchors(s, T):
        F, H = s.F, s.H
        P = lambda y, z, x=F: [round(float(c), 1) for c in proj(np.array([x, y, z]), T)]
        c = P(s.Yc, s.Zd, F + 0.6)
        r = s.Rg * np.sqrt(.5) - 0.6; ry = s.Rg * (1 / CZ) - 0.6
        y0, y1 = s.Y0 + 7.0 - 4.1, s.Y0 + 7.0 + 4.1
        disp = [P(y1, H - 2.7), P(y0, H - 2.7), P(y0, H - 5.7), P(y1, H - 5.7)]
        led = P(s.Y0 + 2.0, H - 4.2)
        body = [P(s.Y1, H), P(s.Y0, H), P(s.Y0, 0), P(s.Y1, 0)]
        return dict(door={"c": c, "s": [1, round(-132 / 320, 4)], "t": [0, -1], "r": round(float(r), 2), "ry": round(float(ry), 2)},
                    display=disp, led=led, body=body)

# ---------------- 热水器（卫生间 NW 墙，横置储水式电热水器） ----------------
class Heater:
    Yc = 0.175 * S
    L = 0.15 * S                       # 罐体长度（沿墙）
    R = 11.2
    Xc = 12.5
    Zc = 74 * CZ
    def scene(s, p):
        c = np.array([s.Xc, s.Yc, s.Zc])
        tank = sd_cyl_y(p, c, s.R, s.L / 2, 3.2)
        # 两端装饰圈（浅灰端盖）
        caps = np.maximum(tank - 0.15, -sd_cyl_y(p, c, s.R + 1, s.L / 2 - 3.0))
        # 挂墙支架带
        straps = np.minimum(sd_cyl_y(p, c + np.array([0, s.L / 2 - 8, 0]), s.R + 0.4, 0.9, 0.3),
                            sd_cyl_y(p, c - np.array([0, s.L / 2 - 8, 0]), s.R + 0.4, 0.9, 0.3))
        straps = np.maximum(straps, -(p[:, 0] - 0.0))
        # 正面圆形显示窗（凸起表盘）
        dc = np.array([s.Xc + s.R - 0.2, s.Yc - 3.0, s.Zc + 0.8])
        bezel = np.maximum(sd_cyl_x(p, dc, 5.4, 0.9, 0.5), -sd_cyl_x(p, dc + np.array([1.0, 0, 0]), 4.2, 0.6))
        screen = sd_cyl_x(p, dc + np.array([0.75, 0, 0]), 4.1, 0.25, 0.1)
        knob = sd_cyl_x(p, np.array([s.Xc + s.R - 0.6, s.Yc + 6.5, s.Zc - 1.6]), 1.6, 1.0, 0.4)
        # 下方两根进 / 出水管 + 阀门
        pipes = 1e9
        for dy in (-6.5, 6.5):
            pc = np.array([s.Xc - 1.0, s.Yc + dy, s.Zc - s.R - 6.0])
            pipes = np.minimum(pipes, sd_cyl_z(p, pc, 0.9, 6.5, 0.3))
            pipes = np.minimum(pipes, sd_cyl_z(p, pc - np.array([0, 0, 3.0]), 1.5, 0.9, 0.4))
        bend = np.minimum(sd_cyl_x(p, np.array([s.Xc / 2 - 0.5, s.Yc - 6.5, s.Zc - s.R - 12.0]), 0.9, s.Xc / 2, 0.3),
                          sd_cyl_x(p, np.array([s.Xc / 2 - 0.5, s.Yc + 6.5, s.Zc - s.R - 12.0]), 0.9, s.Xc / 2, 0.3))
        return _u((tank, ENAMEL), (caps, PLASTIC), (straps, STRAP), (bezel, CHROME), (screen, SCREEN),
                  (knob, CHROME), (pipes, PIPE), (bend, PIPE))
    def material(s, p, n, ids):
        # 像素化后只剩 ~11 格高：搪瓷压一点亮度、端盖 / 挂带更深，罐体的圆柱明暗和轮廓才读得出来
        alb, spec, shin, env = material(p, n, ids)
        m = ids == ENAMEL; alb[m] = (0.86, 0.84, 0.80); spec[m] = 0.16; env[m] = 0.03
        alb[ids == PLASTIC] = (0.60, 0.60, 0.60); alb[ids == STRAP] = (0.34, 0.34, 0.36)
        return alb, spec, shin, env
    def bbox(s, T):
        pts = [proj(np.array([x, y, z]), T) for x in (0, s.Xc + s.R + 2) for y in (s.Yc - s.L / 2, s.Yc + s.L / 2)
               for z in (s.Zc - s.R - 14, s.Zc + s.R + 1)]
        xs, ys = [q[0] for q in pts], [q[1] for q in pts]
        return int(min(xs)) - 8, int(min(ys)) - 6, int(max(xs)) + 12, int(max(ys)) + 10
    def anchors(s, T):
        dc = np.array([s.Xc + s.R + 0.8, s.Yc - 3.0, s.Zc + 0.8])
        P = lambda q: [round(float(c), 1) for c in proj(q, T)]
        ring = [P(dc + np.array([0, 3.7 * np.cos(a), 3.7 * np.sin(a)])) for a in np.linspace(0, 2 * np.pi, 8, endpoint=False)]
        led = P(np.array([s.Xc + s.R - 0.4, s.Yc + 2.6, s.Zc - 2.4]))
        c = np.array([s.Xc, s.Yc, s.Zc])
        body = [P(c + np.array([s.R, s.L / 2, s.R])), P(c + np.array([s.R, -s.L / 2, s.R])),
                P(c + np.array([s.R, -s.L / 2, -s.R])), P(c + np.array([s.R, s.L / 2, -s.R]))]
        return dict(display=ring, led=led, body=body, anchor=P(c + np.array([s.R, 0, 0])))
