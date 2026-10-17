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
        # 墙挂灯：anchor = 灯具本体所在点（合成器据此判断它在哪一段墙上、那段墙是否被切）
        d["wall"] = wall; d["anchor"] = src
    return d

def ceiling(g, id, u, v, slot=0):
    return {"id": id, "kind": "ceiling", "role": "light", "slot": slot,
            "pool": ell(g, u, v, 120, 48), "reveal": ell(g, u, v, 160, 80)}

def spec(module):
    fw = 2 if module == 'living' else 1
    g = module_geom(fw)
    b = lambda pts: [P(g, u, v) for u, v in pts]
    lab = P(g, 0.08, 0.62, 98)
    if module == 'living':
        lights = [dict(lamp(g, 'floor_lamp', 0.07, 0.09, 63), pool=ell(g, 0.3, 0.3, 110, 44)),
                  dict(lamp(g, 'sconce', 0.81, 0.02, 71, slot=1, wall='ne', kind='sconce'), radius=75, strength=0.85, pool=ell(g, 0.85, 0.25, 90, 36)),
                  {"id": "tv", "kind": "screen", "role": "tv", "slot": 0, "style": "tv",
                   "screen": quad(g, 1.37, 0.12, 54, 58, 30), "throw": [-40, 40], "radius": 85,
                   "reveal": ell(g, 1.4, 0.45, 120, 85)}]
        badges = b([(0.5, 0.75), (1.0, 0.8), (1.5, 0.75), (1.2, 0.5)])
    elif module == 'bedroom':
        lights = [dict(lamp(g, 'bedside', 0.07, 0.09, 44), pool=ell(g, 0.2, 0.3, 100, 40)),
                  {"id": "ac", "kind": "ac", "role": "ac", "slot": 0, "wall": "nw",
                   "vent": [P(g, 0.02, 0.58, 72), P(g, 0.02, 0.32, 72)], "led": P(g, 0.02, 0.34, 84),
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
        badges = b([(0.6, 0.88), (0.88, 0.62), (0.3, 0.75)])
    elif module == 'bathroom':
        lights = [ceiling(g, 'ceiling', 0.5, 0.5)]
        badges = b([(0.6, 0.88), (0.88, 0.62), (0.3, 0.75)])
    elif module == 'balcony':
        lights = [dict(lamp(g, 'wall_lamp', 0.02, 0.69, 72, wall='nw', kind='sconce'), radius=80, pool=ell(g, 0.3, 0.7, 100, 40))]
        badges = b([(0.6, 0.88), (0.88, 0.62), (0.3, 0.75)])
    else:
        raise KeyError(module)
    return fw, g, dict(label=lab, badges=badges, lights=lights)

MODULES = ['living', 'bedroom', 'study', 'generic', 'kitchen', 'bathroom', 'balcony']
