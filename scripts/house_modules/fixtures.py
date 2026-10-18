"""每个模块的灯具槽 / 徽章 / 标签（模块内 1x 坐标由地面参数换算）。

位置用地面参数表示：u 沿 NE 墙（0..fw），v 沿 NW 墙（0..1），z = 离地高度（px）。
灯具 id 沿用 Phase 1（living: floor_lamp/sconce/tv；bedroom: bedside/ac；study: ceiling/monitor；generic: entry_light），
新模块：kitchen: pendant；bathroom: ceiling；balcony: wall_lamp。
"""
import sys; sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
from geom import W, FH, module_geom

def P(g, u, v, z=0):
    T = g['T']
    return [round(T[0] + u * W / 2 - v * W / 2), round(T[1] + u * FH / 2 + v * FH / 2 - z)]

def quad(g, u, v, z, w, h):
    c = P(g, u, v, z)
    return [[c[0] - w // 2, c[1] - h // 2], [c[0] + w // 2, c[1] - h // 2], [c[0] + w // 2 + 2, c[1] + h // 2], [c[0] - w // 2 - 2, c[1] + h // 2]]

def ell(g, u, v, rx, ry):
    c = P(g, u, v)
    return [c[0], c[1], rx, ry]

def lamp(g, id, u, v, z, slot=0, wall=None, kind='lamp'):
    src = P(g, u, v, z)
    d = {"id": id, "kind": kind, "role": "light", "slot": slot, "source": src, "radius": 110,
         "pool": ell(g, u + 0.12, v + 0.22, 110, 44), "shade": quad(g, u, v, z, 16, 22),
         "reveal": [src[0], src[1] + 30, 140, 92]}
    if wall:
        # 墙挂灯：anchor = 灯具本体所在点（合成器据此判断它在哪一段墙上、那段墙是否被切）；
        # 调用处再给 alt（地面点）：墙被切时 App 把灯具位 / 设备徽章挪到这里，光池照旧
        d["wall"] = wall; d["anchor"] = src
    return d

def ceiling(g, id, u, v, slot=0):
    # alt = 编辑模式里灯具位的落点：光斑中心往上一点（“天花板上”），不和地板中部的徽章位叠在一起
    return {"id": id, "kind": "ceiling", "role": "light", "slot": slot,
            "pool": ell(g, u, v, 120, 48), "reveal": ell(g, u, v, 160, 80), "alt": P(g, u, v, 40)}

# 1x1 模块的徽章位：地板中心周围三点（左、右、前），彼此 ≥ 60px，离相邻房间的徽章位也够远
SPREAD = [(0.28, 0.66), (0.66, 0.28), (0.74, 0.74)]

def spec(module):
    fw = 2 if module == 'living' else 1
    g = module_geom(fw)
    b = lambda pts: [P(g, u, v) for u, v in pts]
    lab = P(g, 0.08, 0.62, 98)
    floor_label = None
    if module == 'living':
        lights = [dict(lamp(g, 'floor_lamp', 0.07, 0.09, 63), pool=ell(g, 0.3, 0.3, 110, 44)),
                  dict(lamp(g, 'sconce', 0.81, 0.02, 71, slot=1, wall='ne', kind='sconce'), radius=75, strength=0.85, pool=ell(g, 0.85, 0.25, 90, 36),
                       alt=P(g, 0.7, 0.22)),
                  {"id": "tv", "kind": "screen", "role": "tv", "slot": 0, "style": "tv",
                   # 电视柜离墙摆在右格中间（约 u=1.55, v=0.25）；屏幕平行于 NE 墙，按规范图实测的平行四边形
                   "screen": [[372, 153], [419, 173], [419, 209], [372, 190]], "throw": [-40, 40], "radius": 85,
                   "reveal": ell(g, 1.35, 0.6, 120, 85)}]
        badges = b([(0.5, 0.75), (0.95, 0.62), (1.4, 0.9), (1.75, 0.6)])   # 电视柜挪到右格中间后重新排开
        floor_label = P(g, 0.35, 0.3, 0)   # 两面后墙都被切时：沙发前的空地（避开徽章位）
    elif module == 'bedroom':
        lights = [dict(lamp(g, 'bedside', 0.07, 0.09, 44), pool=ell(g, 0.2, 0.3, 100, 40)),
                  {"id": "ac", "kind": "ac", "role": "ac", "slot": 0, "wall": "nw",
                   "vent": [P(g, 0.02, 0.6, 72), P(g, 0.02, 0.38, 72)], "led": P(g, 0.02, 0.34, 84),
                   "core": quad(g, 0.02, 0.46, 81, 50, 22), "reveal": ell(g, 0.2, 0.46, 70, 50),
                   # 所在墙被切掉时：空调本体不可见，App 在地上 alt 点显示一个空调徽章代替
                   "anchor": P(g, 0.02, 0.46, 81), "alt": P(g, 0.28, 0.42)}]
        badges = b([(0.55, 0.8), (0.8, 0.55), (0.35, 0.65)])
    elif module == 'study':
        lights = [ceiling(g, 'ceiling', 0.55, 0.55),
                  {"id": "monitor", "kind": "screen", "role": "tv", "slot": 0, "style": "monitor",
                   "screen": quad(g, 0.48, 0.12, 46, 24, 20), "throw": [-8, 35], "radius": 60,
                   "reveal": ell(g, 0.5, 0.35, 85, 65)}]
        badges = b([(0.55, 0.85), (0.85, 0.6), (0.3, 0.7)])
    elif module == 'generic':
        lights = [ceiling(g, 'entry_light', 0.5, 0.55)]
        badges = b([(0.55, 0.85), (0.85, 0.6), (0.3, 0.7)])
    elif module == 'kitchen':
        # 吊灯本体不画（剖面里吊在半空，切墙时会被竖条切成半个）：按看不见灯具的吸顶灯处理，光池落在餐桌上
        lights = [ceiling(g, 'pendant', 0.37, 0.37)]
        # 徽章位分散在地板中部一圈（原来挤在前沿两个角，编辑模式里和前面房间的徽章位叠在一起）
        badges = b(SPREAD)
        floor_label = P(g, 0.84, 0.5, 0)   # 两面后墙都被切时标签放这（右侧空地，避开餐桌）
    elif module == 'bathroom':
        lights = [ceiling(g, 'ceiling', 0.5, 0.5)]
        badges = b(SPREAD)
    elif module == 'balcony':
        lights = [dict(lamp(g, 'wall_lamp', 0.02, 0.69, 72, wall='nw', kind='sconce'), radius=80, pool=ell(g, 0.3, 0.7, 100, 40),
                     alt=P(g, 0.2, 0.4))]
        badges = b(SPREAD)
    else:
        raise KeyError(module)
    d = dict(label=lab, badges=badges, lights=lights)
    if floor_label: d['floorLabel'] = floor_label
    return fw, g, d

MODULES = ['living', 'bedroom', 'study', 'generic', 'kitchen', 'bathroom', 'balcony']
