"""Reference recolor from the encoded sheet (exact spec for Swift) + golden vectors."""
import json, sys, numpy as np
from PIL import Image
from pathlib import Path
SHADOW_RGB = np.array([0.12, 0.08, 0.07])
def derived(pal):
    h = lambda s: np.array([int(s.lstrip('#')[i:i + 2], 16) for i in (0, 2, 4)], float) / 255
    base, second, white, eye = h(pal['base']), h(pal['second']), h(pal['white']), h(pal['eye'])
    t = np.zeros((16, 3))
    t[1] = base; t[2] = second; t[3] = white; t[4] = base * 0.7 + np.array([1.0, 0.95, 0.88]) * 0.3
    t[5] = [0.93, 0.60, 0.64]; t[6] = eye; t[7] = [0.09, 0.07, 0.09]; t[8] = [1, 1, 1]
    t[9] = base * 0.30 + np.array([0.08, 0.05, 0.06]) * 0.7; t[11] = t[9]
    return t
def recolor_px(rgba, pal, light=None):
    """rgba: (...,4) uint8 encoded. returns float rgba 0..1 (straight alpha)"""
    R, G, B, A = [rgba[..., i].astype(float) for i in range(4)]
    tbl = derived(pal)
    region = (R.astype(int) & 15); outline = (R.astype(int) >> 4) & 1
    s = G / 127.5; k = B / 255; a = A / 255
    c = tbl[region]
    tsh = np.clip((0.85 - s) / 0.6, 0, 1)[..., None]; thi = np.clip((s - 1.0) / 0.4, 0, 1)[..., None]
    tint = 1 + tsh * (np.array([0.86, 0.89, 1.10]) - 1) * 0.7 + thi * (np.array([1.05, 1.02, 0.95]) - 1)
    body = c * s[..., None] * tint + k[..., None] * np.array([1.0, 0.97, 0.92])
    flat = np.isin(region, [6, 7, 8, 9])[..., None]
    col = np.where(flat, c, body)
    olc = (c * 0.42 * np.array([0.92, 0.88, 0.95]) + np.array([0.07, 0.04, 0.05])) * 0.75
    col = np.where(outline[..., None] == 1, olc, col)
    col = np.clip(col, 0, 1)
    shadow = (A > 0) & (A < 255)
    col = np.where(shadow[..., None], SHADOW_RGB, col)
    if light is not None:
        mul = np.array(light['mul']); add = np.array(light['add'])
        col = np.where(shadow[..., None], col, np.clip(col * mul + add, 0, 1))
    col = np.where((A == 0)[..., None], 0, col)
    return np.concatenate([col, a[..., None]], -1)
if __name__ == '__main__':
    d = Path(sys.argv[1]); rig_id = sys.argv[2] if len(sys.argv) > 2 else 'cat-short'
    rig = json.loads((d / f'{rig_id}.json').read_text())
    pals = [dict(base='#E8973F', second='#B3561C', white='#F4EEE4', eye='#9CC43E'), dict(base='#2E2B30', second='#1C1A1E', white='#F2F0EC', eye='#E9C24A')]
    rng = np.random.default_rng(7); out = []
    for pat in ('tabby', 'calico'):
        S = np.asarray(Image.open(d / rig['sheets'][pat]).convert('RGBA'))
        ys, xs = np.nonzero(S[..., 3] > 0)
        for n in rng.choice(len(ys), 24, replace=False):
            y, x = int(ys[n]), int(xs[n])
            for pi, pal in enumerate(pals):
                for ln in ('day', 'night'):
                    L = rig['lighting'][ln]
                    v = recolor_px(S[y, x], pal, L)
                    out.append(dict(pattern=pat, x=x, y=y, palette=pal, lighting=ln, encoded=S[y, x].tolist(), rgba=[int(round(c * 255)) for c in v]))
    (d / f'{rig_id}-golden.json').write_text(json.dumps(dict(note='expected straight-alpha RGBA 0..255; tolerance ±2', samples=out), indent=0))
    print(len(out))
