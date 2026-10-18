"""Auto walk grids from material maps (floor ids 3/4) + manual overrides -> pet-spots data, overlays."""
import json, sys, numpy as np, cv2
from PIL import Image, ImageDraw
from pathlib import Path
R = Path(__file__).resolve().parents[2]
DIRS = {'cozy': R / 'Sources/MijiaBarApp/Resources/House/modules', 'japanese': R / 'assets/house/styles/japanese/modules', 'modern': R / 'assets/house/styles/modern/modules'}
N = 8
def px(tip, u, v, z=0): return (tip[0] + 160 * (u - v), tip[1] + 66 * (u + v) - z)
def grid(st, mid, art, ovr):
    m = np.asarray(Image.open(f'/tmp/house-pets-mat/{st}/mat-{mid}.png'))
    fu, fv = art['footprint']; tip = art['tip']
    W, H = fu * N, fv * N
    frac = np.zeros((H, W))
    for i in range(H):
        for j in range(W):
            ok = 0; tot = 0
            for a in np.linspace(0.1, 0.9, 5):
                for b in np.linspace(0.1, 0.9, 5):
                    x, y = px(tip, (j + a) / N, (i + b) / N); xi, yi = int(x), int(y)
                    tot += 1
                    if 0 <= yi < m.shape[0] and 0 <= xi < m.shape[1] and m[yi, xi] in (3, 4): ok += 1
            frac[i, j] = ok / tot
    open_ = frac >= 0.7
    # keep 1 cell margin from back walls (u=0 col, v=0 row) — cat body would clip into wall
    open_[:, 0] = False; open_[0, :] = False
    for (j, i) in ovr.get('block', []): open_[i, j] = False
    for (j, i) in ovr.get('open', []): open_[i, j] = True
    for r in ovr.get('blockRect', []):
        j0, i0, j1, i1 = r; open_[i0:i1, j0:j1] = False
    # largest component
    n, lab = cv2.connectedComponents(open_.astype(np.uint8), connectivity=4)
    if n > 1:
        sizes = [(lab == k).sum() for k in range(1, n)]; keep = 1 + int(np.argmax(sizes)); open_ = lab == keep
    return open_, frac

def overlay(st, mid, art, open_, spots, path):
    img = Image.open(DIRS[st] / f'module-{mid}-day-unlit.png').convert('RGBA')
    ov = Image.new('RGBA', img.size, (0, 0, 0, 0)); d = ImageDraw.Draw(ov)
    tip = art['tip']; H, W = open_.shape
    for i in range(H):
        for j in range(W):
            q = [px(tip, j / N, i / N), px(tip, (j + 1) / N, i / N), px(tip, (j + 1) / N, (i + 1) / N), px(tip, j / N, (i + 1) / N)]
            d.polygon(q, fill=(60, 255, 90, 70) if open_[i, j] else (255, 40, 40, 50), outline=(0, 0, 0, 60))
    for s in spots:
        x, y = px(tip, *s['at'], s.get('z', 0)); d.ellipse((x - 5, y - 5, x + 5, y + 5), fill=(40, 120, 255, 230)); d.text((x + 6, y - 6), s['id'], fill=(0, 0, 0, 255))
    img.alpha_composite(ov); img = img.resize((img.width * 2, img.height * 2), Image.NEAREST); img.save(path)
