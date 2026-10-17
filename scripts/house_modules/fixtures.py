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
    if wall: d["wall"] = wall
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
        lights = [lamp(g, 'floor_lamp', 0.18, 0.36, 72),
                  dict(lamp(g, 'sconce', 1.15, 0.02, 70, slot=1, wall='ne', kind='sconce'), radius=75, strength=0.85),
                  {"id": "tv", "kind": "screen", "role": "tv", "slot": 0, "style": "tv",
                   "screen": quad(g, 1.55, 0.14, 46, 50, 34), "throw": [-40, 40], "radius": 85,
                   "reveal": ell(g, 1.5, 0.45, 120, 85)}]
        badges = b([(0.5, 0.75), (1.0, 0.8), (1.5, 0.75), (1.2, 0.5)])
    elif module == 'bedroom':
        lights = [lamp(g, 'bedside', 0.16, 0.18, 40),
                  {"id": "ac", "kind": "ac", "role": "ac", "slot": 0, "wall": "ne",
                   "vent": [P(g, 0.36, 0.0, 80), P(g, 0.66, 0.0, 80)], "led": P(g, 0.6, 0.0, 86),
                   "core": quad(g, 0.5, 0.0, 88, 70, 26), "reveal": ell(g, 0.5, 0.2, 70, 50)}]
        badges = b([(0.55, 0.8), (0.8, 0.55), (0.35, 0.65)])
    elif module == 'study':
        lights = [ceiling(g, 'ceiling', 0.55, 0.55),
                  {"id": "monitor", "kind": "screen", "role": "tv", "slot": 0, "style": "monitor",
                   "screen": quad(g, 0.6, 0.12, 44, 36, 24), "throw": [-8, 35], "radius": 60,
                   "reveal": ell(g, 0.6, 0.35, 85, 65)}]
        badges = b([(0.55, 0.85), (0.85, 0.6), (0.3, 0.7)])
    elif module == 'generic':
        lights = [ceiling(g, 'entry_light', 0.5, 0.55)]
        badges = b([(0.55, 0.85), (0.85, 0.6), (0.3, 0.7)])
    elif module == 'kitchen':
        lights = [dict(lamp(g, 'pendant', 0.55, 0.55, 86), pool=ell(g, 0.55, 0.55, 100, 42))]
        badges = b([(0.6, 0.88), (0.88, 0.62), (0.3, 0.75)])
    elif module == 'bathroom':
        lights = [ceiling(g, 'ceiling', 0.5, 0.5)]
        badges = b([(0.6, 0.88), (0.88, 0.62), (0.3, 0.75)])
    elif module == 'balcony':
        lights = [dict(lamp(g, 'wall_lamp', 0.06, 0.5, 70, wall='nw', kind='sconce'), radius=80)]
        badges = b([(0.6, 0.88), (0.88, 0.62), (0.3, 0.75)])
    else:
        raise KeyError(module)
    return fw, g, dict(label=lab, badges=badges, lights=lights)

MODULES = ['living', 'bedroom', 'study', 'generic', 'kitchen', 'bathroom', 'balcony']
