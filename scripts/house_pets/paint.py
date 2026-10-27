"""Cell maps -> encoded rig cells (region/outline/shade/spec) and reference recolor."""
import numpy as np
import patterns as PT
from sdfcat import project, CELL
from appliance_render import F_W

SHADE_STEPS = 14
TONE = (0.40, 0.70)

def stamp_eyes(F, C, style=None):
    reg = C['region']; obj = C['obj']; dep = C['depth']; H, W = reg.shape
    x0, y0 = F['bbox'][0], F['bbox'][1]
    f = F['feat']; eyes = F['eyes']
    hc = f['head_c']
    vis = []
    for k in ('eyeL', 'eyeR'):
        p = f[k]; dirv = (p - hc) / np.linalg.norm(p - hc)
        fac = dirv @ F_W
        sx, sy = project(p)
        cx, cy = (sx - x0) / CELL, (sy - y0) / CELL
        vis.append((k, fac, cx, cy, p @ F_W))
    for k, fac, cx, cy, d in vis:
        if fac < 0.05: continue
        i, j = int(np.floor(cy)), int(np.floor(cx))
        if not (0 <= i < H and 0 <= j < W and obj[i, j]): continue
        if abs(np.nan_to_num(dep[i, j], nan=-99) - d) > 4.5: continue
        far = fac < 0.45
        cellset = []
        if eyes == 'open':
            if far:
                cellset = [(i - 1, j, PT.PUPIL), (i, j, PT.IRIS)]
            else:
                cellset = [(i - 1, j - 1, PT.IRIS), (i - 1, j, PT.HILITE), (i, j - 1, PT.PUPIL), (i, j, PT.IRIS)]
        elif eyes == 'half':
            cellset = [(i, j - (0 if far else 1), PT.PUPIL)] + ([] if far else [(i, j, PT.IRIS)])
        else:   # closed: soft arc
            cellset = [(i, j, PT.CLOSED)] + ([] if far else [(i, j - 1, PT.CLOSED)])
        for (a, b, r) in cellset:
            if 0 <= a < H and 0 <= b < W and obj[a, b]: reg[a, b] = r
    # nose
    p = f['nose']; dirv = (p - hc) / np.linalg.norm(p - hc)
    if dirv @ F_W > 0.1:
        sx, sy = project(p); i, j = int(np.floor((sy - y0) / CELL)), int(np.floor((sx - x0) / CELL))
        if 0 <= i < H and 0 <= j < W and obj[i, j] and abs(np.nan_to_num(dep[i, j], nan=-99) - p @ F_W) < 4:
            reg[i, j] = PT.PUPIL if style == 'dog' else PT.PINK
            if style == 'dog' and j > 0 and obj[i, j - 1]: reg[i, j - 1] = PT.PUPIL
    return reg

def cleanup(reg, obj):
    H, W = reg.shape; out = reg.copy()
    for i in range(H):
        for j in range(W):
            r = reg[i, j]
            if not obj[i, j] or r not in (1, 2, 3, 4): continue
            nb = [reg[a, b] for a, b in ((i-1, j), (i+1, j), (i, j-1), (i, j+1)) if 0 <= a < H and 0 <= b < W and obj[a, b]]
            if nb and r not in nb:
                vals = [v for v in nb if v in (1, 2, 3, 4)]
                if vals: out[i, j] = max(set(vals), key=vals.count)
    return out

def encode(F, C):
    """returns (H+2, W+2) arrays with 1-cell outline ring: region, outline, shade(q), spec, alpha, shadow alpha"""
    reg = cleanup(C['region'], C['obj']); obj = C['obj']
    H, W = reg.shape
    pad = lambda a, v=0: np.pad(a, 1, constant_values=v)
    reg, obj = pad(reg), pad(obj, False)
    shade = pad(C['shade'], 0.0); spec = pad(C['spec'], 0.0); dep = pad(np.nan_to_num(C['depth'], nan=-1e9), -1e9); gsh = pad(C['gsh'], 0.0)
    outl = np.zeros_like(obj)
    # outer ring: empty cells 4-adjacent to object -> outline, take neighbour region
    ring_reg = np.zeros_like(reg)
    for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nb = np.roll(np.roll(obj, di, 0), dj, 1); nr = np.roll(np.roll(reg, di, 0), dj, 1)
        m = ~obj & nb & (ring_reg == 0); ring_reg[m] = nr[m]
    ring = ring_reg > 0
    # inner depth-discontinuity lines: object cell whose neighbour is much nearer (larger depth along F_W = nearer camera)
    inner = np.zeros_like(obj)
    for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nd = np.roll(np.roll(dep, di, 0), dj, 1); nobj = np.roll(np.roll(obj, di, 0), dj, 1)
        inner |= obj & nobj & (nd - dep > 9.0)
    eyes = np.isin(reg, [PT.IRIS, PT.PUPIL, PT.HILITE, PT.CLOSED])
    inner &= ~eyes
    region = np.where(ring, ring_reg, reg)
    outline = ring | inner
    shade = np.clip(TONE[0] + TONE[1] * shade, 0.45, 1.35)
    wht = (reg == PT.WHITE)
    shade = np.where(wht, np.clip(0.30 + 0.80 * shade, 0.62, 1.12), shade)
    shade_ring = np.where(ring, 0.5, shade)
    q = np.clip(np.round(shade_ring / 2 * SHADE_STEPS * 2) / (SHADE_STEPS * 2) * 2, 0, 2)
    alpha = np.where(obj | ring, 1.0, 0.0)
    sha = np.where(~(obj | ring), np.clip(gsh, 0, 0.6), 0.0)
    sha = np.round(sha * 10) / 10
    region = np.where(sha > 0, PT.SHADOW, region)
    return dict(region=region, outline=outline, shade=q, spec=np.round(spec * 20) / 20, alpha=alpha, sha=sha)

def hexrgb(h): h = h.lstrip('#'); return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], float) / 255

def derived(pal):
    base, second, white, eye = (hexrgb(pal[k]) for k in ('base', 'second', 'white', 'eye'))
    under = base * 0.7 + np.array([1.0, 0.95, 0.88]) * 0.3
    pink = np.array([0.93, 0.60, 0.64]); pupil = np.array([0.09, 0.07, 0.09]); hil = np.array([1.0, 1.0, 1.0])
    closed = base * 0.30 + np.array([0.08, 0.05, 0.06]) * 0.7; mouth = closed
    tbl = np.zeros((16, 3)); tbl[PT.BASE] = base; tbl[PT.SECOND] = second; tbl[PT.WHITE] = white; tbl[PT.UNDER] = under
    tbl[PT.PINK] = pink; tbl[PT.IRIS] = eye; tbl[PT.PUPIL] = pupil; tbl[PT.HILITE] = hil; tbl[PT.CLOSED] = closed; tbl[PT.MOUTH] = mouth
    return tbl

FLAT = (6, 7, 8, 9)   # eye regions: not shaded

def recolor(E, pal):
    tbl = derived(pal)
    r = E['region']; s = E['shade'][..., None]; k = E['spec'][..., None]
    c = tbl[r]
    t_sh = np.clip((0.85 - s) / 0.6, 0, 1); t_hi = np.clip((s - 1.0) / 0.4, 0, 1)
    tint = 1 + t_sh * (np.array([0.86, 0.89, 1.10]) - 1) * 0.7 + t_hi * (np.array([1.05, 1.02, 0.95]) - 1)
    col = c * s * tint + k * np.array([1.0, 0.97, 0.92])
    flat = np.isin(r, FLAT)[..., None]
    col = np.where(flat, c, col)
    ol = E['outline'][..., None]
    olc = c * 0.42 * np.array([0.92, 0.88, 0.95]) + np.array([0.07, 0.04, 0.05])
    col = np.where(ol, olc * 0.75, col)
    col = np.clip(col, 0, 1)
    a = np.maximum(E['alpha'], E['sha'])
    col = np.where((E['sha'] > 0)[..., None], np.array([0.12, 0.08, 0.07]), col)
    return np.concatenate([col, a[..., None]], -1)
