"""几何校验用的“空房间”壳（不是最终美术）：墙纸/护墙板/木地板，按规范几何画。"""
import numpy as np
from PIL import Image, ImageDraw
import sys; sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
from geom import *

def lerp(a, b, t): return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)

def render_shell(fw, tint=(196, 164, 118), cut=False):
    g = module_geom(fw)
    w, h = g['size']
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    hw = CUT_H if cut else WALL_H
    for key, shade in (('wall_nw', 1.0), ('wall_ne', 0.86)):
        _, _, bot1, bot0 = g[key]
        top0 = (bot0[0], bot0[1] - hw); top1 = (bot1[0], bot1[1] - hw)
        d.polygon([top0, top1, bot1, bot0], fill=tuple(int(c * shade) for c in tint) + (255,))
        a0 = (bot0[0], bot0[1] - 40); a1 = (bot1[0], bot1[1] - 40)
        d.polygon([a0, a1, bot1, bot0], fill=tuple(int(c * shade) for c in (92, 54, 30)) + (255,))
        d.line([a0, a1], fill=(60, 34, 18, 255), width=3)
        n = 10 * (fw if key == 'wall_ne' else 1)
        for i in range(1, n):
            t = i / n
            d.line([lerp(bot0, bot1, t), lerp(a0, a1, t)], fill=(70, 40, 22, 255), width=1)
    T, R, F, L = g['T'], g['R'], g['F'], g['L']
    d.polygon([T, R, F, L], fill=(112, 68, 38, 255))
    n = 12 * fw
    for i in range(1, n):
        t = i / n
        d.line([lerp(T, R, t), lerp(L, F, t)], fill=(86, 50, 27, 255), width=1)
    d.polygon(g['slab_sw'], fill=(58, 32, 18, 255))
    d.polygon(g['slab_se'], fill=(44, 24, 14, 255))
    return im
