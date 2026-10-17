import sys, json, numpy as np
from PIL import Image, ImageDraw
import sys; sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
import pipeline as pl
from geom import *
mid, fw = sys.argv[1], int(sys.argv[2])
import os
raw = os.environ.get('HOUSE_RAW', str(__import__('pathlib').Path(__file__).resolve().parents[2] / 'assets/house/modules/src'))
full = np.asarray(Image.open(f'{raw}/{mid}-day-full.jpg').convert('RGB'))
c = pl.detect_corners(full)
try:
    c.update(json.load(open(f'{raw}/{mid}-corners.json')))
except FileNotFoundError: pass
print(json.dumps({k: (np.round(v).astype(int).tolist() if isinstance(v, list) else round(v, 1)) for k, v in c.items()}))
im = Image.fromarray(full).convert('RGB'); d = ImageDraw.Draw(im)
P = pl.planes_src(c)
for k, col in (('floor', (0,255,0)), ('nw', (255,0,0)), ('ne', (0,128,255)), ('sw', (255,255,0)), ('se', (255,0,255))):
    q = [tuple(p) for p in P[k]]; d.line(q + [q[0]], fill=col, width=2)
im.save(f'/tmp/fit-{mid}-overlay.png')
g = module_geom(fw)
outs = []
for cut in (False, True):
    src = np.asarray(Image.open(f'{raw}/{mid}-day-{"cut" if cut else "full"}.jpg').convert('RGB'))
    cc = c
    if cut:
        cc = pl.cut_corners(full, src, c, g)
        print('cut low wall', round(cc['_low'], 1))
    outs.append(pl.pixelize_rgba(pl.warp_to_canonical(src, cc, g, cut=cut)))
s = Image.new('RGBA', (outs[0].width * 2 + 10, outs[0].height), (40, 44, 60, 255))
s.alpha_composite(outs[0], (0, 0)); s.alpha_composite(outs[1], (outs[0].width + 10, 0))
dd = ImageDraw.Draw(s)
T = g['T']
for x0 in (0, outs[0].width + 10):
    dd.line([(x0 + T[0] - 4, T[1] - CUT_H), (x0 + T[0] + 4, T[1] - CUT_H)], fill=(255, 0, 0))
s.resize((s.width * 2, s.height * 2), Image.NEAREST).save(f'/tmp/fit-{mid}.png')
