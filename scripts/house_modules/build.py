"""生成 assets/house/modules/：每个模块 day/night × unlit/lit × full/cut + catalog.json。

用法：python3 build.py OUT_DIR [--raw RAW_DIR] [--classic DIR]
  RAW_DIR 里有 <id>-day-full.jpg / <id>-day-cut.jpg（可选 <id>-night-full.jpg、<id>-corners.json）时用生成图；
  否则用“几何校验壳”（不是最终美术，catalog 的 style 会标成 shell-standin）。
"""
from __future__ import annotations
import argparse, json
from pathlib import Path
import numpy as np
from PIL import Image
import sys; sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
from geom import *
import pipeline as pl
from fixtures import spec, MODULES
from shell import render_shell

TINTS = dict(living=(204, 170, 122), bedroom=(196, 172, 140), study=(186, 166, 128), generic=(196, 164, 118),
             kitchen=(214, 196, 150), bathroom=(170, 186, 190), balcony=(190, 180, 150))

def to_np(im): return np.asarray(im.convert('RGB'), dtype=np.float32) / 255
def from_np(a, alpha):
    rgb = Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGB').convert('RGBA')
    rgb.putalpha(alpha); return rgb

def region_local(g, fw):
    T, R, F, L = g['T'], g['R'], g['F'], g['L']
    return [[L[0], L[1] - WALL_H], [T[0], T[1] - WALL_H], [R[0], R[1] - WALL_H], list(R), [R[0], R[1] + SLAB],
            [F[0], F[1] + SLAB], [L[0], L[1] + SLAB], list(L)]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('out'); ap.add_argument('--raw'); ap.add_argument('--classic', default=str(Path(__file__).resolve().parents[2] / 'assets/house'))
    a = ap.parse_args()
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    lut = pl.night_lut(Path(a.classic) / 'house-cutaway-day-base.png', Path(a.classic) / 'house-cutaway-night-base.png')
    catalog = {"schema": 3, "style": None, "grid": dict(W=W, FH=FH, WALL_H=WALL_H, CUT_H=CUT_H, SLAB=SLAB, PX=PX), "modules": {}}
    styles = set()
    for mid in MODULES:
        fw, g, sp = spec(mid)
        raw = Path(a.raw) if a.raw else None
        variants = {}
        if raw and (raw / f'{mid}-day-full.jpg').exists():
            styles.add('generated')
            imgs = {}
            for cut in (False, True):
                src = np.asarray(Image.open(raw / f'{mid}-day-{"cut" if cut else "full"}.jpg').convert('RGB'))
                cj = raw / f'{mid}-corners.json'
                corners = json.loads(cj.read_text()) if cj.exists() else pl.detect_corners(np.asarray(Image.open(raw / f'{mid}-day-full.jpg').convert('RGB')))
                imgs[cut] = pl.pixelize_rgba(pl.warp_to_canonical(src, corners, g, cut=cut))
        else:
            styles.add('shell-standin')
            imgs = {cut: pl.pixelize_rgba(render_shell(fw, TINTS[mid], cut=cut).resize((g['size'][0] * 2, g['size'][1] * 2), Image.NEAREST))
                    for cut in (False, True)}
        mod = dict(region=region_local(g, fw), **sp)
        for cut in (False, True):
            im = imgs[cut]; alpha = im.getchannel('A'); day = to_np(im)
            night = pl.apply_night(day, lut)
            for phase, base in (('day', day), ('night', night)):
                unlit, lit = pl.bake_module(base, phase, mod, cut)
                for kind, arr in (('unlit', unlit), ('lit', lit)):
                    name = f'module-{mid}-{phase}-{kind}{"-cut" if cut else ""}.png'
                    from_np(arr, alpha).save(out / name, optimize=True)
                    variants[f'{phase}-{kind}{"-cut" if cut else ""}'] = name
        catalog['modules'][mid] = dict(footprint=[fw, 1], size=list(g['size']), tip=list(g['T']),
                                       region=mod['region'], label=sp['label'], badges=sp['badges'],
                                       lights=sp['lights'], variants=variants)
        print(mid, g['size'])
    catalog['style'] = '+'.join(sorted(styles))
    (out / 'catalog.json').write_text(json.dumps(catalog, indent=1, ensure_ascii=False))

if __name__ == '__main__':
    main()
