"""Render decor sprites: python3 build.py OUT [ids...]"""
import sys, json, numpy as np
from pathlib import Path
from PIL import Image, ImageFilter, ImageEnhance
import cv2
from sdf import render, proj, V
import items as I
sys.path.insert(0, str(__import__('pathlib').Path(__file__).resolve().parents[1]))
import pipeline as pl
LUT = pl.night_lut(None, None)
WARM = np.array([1.03, 0.95, 0.82])
# per item: (half width, up, down) screen px around anchor
BOX = dict(monstera=(28, 60, 14), spider_plant=(26, 50, 12), succulent=(12, 20, 10), bonsai=(20, 32, 10), rug_round=(44, 22, 22), rug_stripe=(58, 26, 26),
           book_stack=(16, 20, 12), cat_bed=(18, 14, 12), cat_tree=(26, 72, 16), food_bowl=(24, 12, 14), dog_bed=(30, 18, 20),
           rabbit_lamp=(20, 34, 12), pumpkin=(14, 22, 12), xmas_tree=(26, 70, 16), snowman=(20, 50, 14),
           painting_landscape=(22, 26, 26), painting_cat=(12, 18, 18), wall_clock=(14, 18, 18), lantern=(20, 24, 30), fu=(18, 24, 24))

def sprite(name, sc, wall):
    anchor = proj(V(0, I.C, 0) if wall else V(I.C, I.C, 0), (0, 0))
    hw, up, dn = BOX[name]
    ax, ay = round(anchor[0]), round(anchor[1])
    bb = (ax - hw, ay - up, ax + hw, ay + dn)
    rgb, a, sh, em = render(sc, bb, ss=3, wall_plane=wall, shadow_tmax=120 if wall else 22)
    obj = np.clip(rgb * WARM, 0, 1)
    # dark outline ring like appliance composite
    hitm = (a > 0.5).astype(np.uint8)
    ring = np.clip(cv2.dilate(hitm, np.ones((3, 3), np.uint8)).astype(np.float32) - hitm, 0, 1)
    out_rgb = obj * a[..., None] + np.array([40, 28, 20.]) / 255 * (1 - a[..., None])
    alpha_obj = np.maximum(a, ring * 0.55 * 0 + 0)
    shadow = sh * (1 - a)
    ringa = ring * 0.55
    # to 1x pixel grid (PX=2): 2x -> /4 then nearest x2
    H, W = a.shape
    def down(x): return cv2.resize(x.astype(np.float32), (W // 4, H // 4), interpolation=cv2.INTER_AREA)
    c4 = Image.fromarray((np.clip(out_rgb, 0, 1) * 255).astype(np.uint8)).resize((W // 4, H // 4), Image.Resampling.LANCZOS)
    c4 = ImageEnhance.Contrast(ImageEnhance.Brightness(c4).enhance(0.98)).enhance(1.06)
    c4 = np.asarray(c4, np.float32) / 255
    a4 = down(a); r4 = down(ringa); s4 = down(shadow); e4 = down(em)
    obj4 = a4 >= 0.45
    # outline: 1-cell ring at 1/4 scale around object, darker
    ring4 = (cv2.dilate(obj4.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0) & ~obj4
    col = c4.copy(); alpha = np.zeros_like(a4)
    alpha[obj4] = 1
    col[ring4] = np.array([40, 28, 20]) / 255; alpha[ring4] = np.maximum(0.5, np.round(s4[ring4] * 10) / 10)
    sm = ~obj4 & ~ring4
    alpha[sm] = np.round(np.clip(s4[sm], 0, 0.7) * 10) / 10; col[sm] = 0
    emis = np.where(obj4, e4 / np.maximum(a4, 1e-3), 0)
    up2 = lambda x: np.repeat(np.repeat(x, 2, 0), 2, 1)
    col, alpha, emis = up2(col), up2(alpha), up2(emis)
    # anchor in 1x sprite coords
    anc = [ax - bb[0], ay - bb[1]]
    return col, alpha, emis, anc

def night(col, emis):
    n = pl.apply_night(col, LUT, night_sky=col)
    glow = np.clip(col * np.array([1.08, 1.0, 0.86]) * 1.05, 0, 1)
    return n * (1 - emis[..., None]) + glow * emis[..., None]

def crop(col, alpha, emis, anc):
    ys, xs = np.nonzero(alpha > 0)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    y0 -= y0 % 2; x0 -= x0 % 2; y1 += y1 % 2; x1 += x1 % 2
    return col[y0:y1, x0:x1], alpha[y0:y1, x0:x1], emis[y0:y1, x0:x1], [anc[0] - x0, anc[1] - y0]

def save(path, col, alpha):
    a = np.concatenate([np.clip(col, 0, 1), alpha[..., None]], -1)
    Image.fromarray((a * 255 + 0.5).astype(np.uint8), 'RGBA').save(path, optimize=True)

def main():
    out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
    want = sys.argv[2:]
    anchors = json.loads((out / 'anchors.json').read_text()) if (out / 'anchors.json').exists() else {}
    for name, fn in list(I.FLOOR.items()) + list(I.WALL.items()):
        if want and name not in want: continue
        wall = name in I.WALL
        col, alpha, emis, anc = crop(*sprite(name, fn(), wall))
        if not wall:
            save(out / f'decor-{name}-day.png', col, alpha); save(out / f'decor-{name}-night.png', night(col, emis), alpha)
        else:
            save(out / f'decor-{name}-day-nw.png', col, alpha); save(out / f'decor-{name}-night-nw.png', night(col, emis), alpha)
            if name == 'fu':
                c2, a2, e2, _ = crop(*sprite(name, I.fu(mirror=True), True))
                col, alpha, emis = c2[:, ::-1], a2[:, ::-1], e2[:, ::-1]
            else:
                col, alpha, emis = col[:, ::-1], alpha[:, ::-1], emis[:, ::-1]
            save(out / f'decor-{name}-day-ne.png', col, alpha); save(out / f'decor-{name}-night-ne.png', night(col, emis), alpha)
        anchors[name] = [int(anc[0]), int(anc[1])]
        (out / "anchors.json").write_text(json.dumps(anchors, indent=1))
        print(name, col.shape[1], col.shape[0], anc, flush=True)
    (out / 'anchors.json').write_text(json.dumps(anchors, indent=1))

if __name__ == '__main__':
    main()
