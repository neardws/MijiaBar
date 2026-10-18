"""Material index maps for style themes (palette-swap variants).

mat-<module>[-cut].png: 8-bit grey, value = material id
  0 other (furniture, outline, windows, ...)   1 wallpaper (upper wall)
  2 wainscot / wall wood                        3 wood floor
  4 tile / light floor
Zones come from the canonical module geometry; inside a zone a pixel is the material only if its colour fits
that zone's colour model (k-means clusters of the zone itself), so furniture standing in front of a wall or on
the floor keeps id 0.
"""
import json, sys, os
import numpy as np, cv2
from PIL import Image

W, FH, WALL_H, CUT_H = 320, 132, 104, 40

def P(tip, u, v, z):
    return (tip[0] + (u - v) * W / 2, tip[1] + (u + v) * FH / 2 - z)

def poly_mask(shape, pts):
    m = np.zeros(shape, np.uint8)
    cv2.fillPoly(m, [np.round(np.array(pts)).astype(np.int32)], 255)
    return m > 0

def zones(shape, tip, fw, fh, cut):
    top = CUT_H if cut else WALL_H - 3
    z_split = 44
    nw_hi = poly_mask(shape, [P(tip, 0, 0, z_split), P(tip, 0, fh, z_split), P(tip, 0, fh, top), P(tip, 0, 0, top)]) if not cut else None
    ne_hi = poly_mask(shape, [P(tip, 0, 0, z_split), P(tip, fw, 0, z_split), P(tip, fw, 0, top), P(tip, 0, 0, top)]) if not cut else None
    lo_top = min(top, 40)
    nw_lo = poly_mask(shape, [P(tip, 0, 0, 1), P(tip, 0, fh, 1), P(tip, 0, fh, lo_top), P(tip, 0, 0, lo_top)])
    ne_lo = poly_mask(shape, [P(tip, 0, 0, 1), P(tip, fw, 0, 1), P(tip, fw, 0, lo_top), P(tip, 0, 0, lo_top)])
    floor = poly_mask(shape, [P(tip, 0, 0, 0), P(tip, fw, 0, 0), P(tip, fw, fh, 0), P(tip, 0, fh, 0)])
    wall_hi = (nw_hi | ne_hi) if not cut else np.zeros(shape, bool)
    wall_lo = (nw_lo | ne_lo)
    floor &= ~(wall_hi | wall_lo)
    return wall_hi, wall_lo, floor

def lab(img):
    return cv2.cvtColor(img, cv2.COLOR_RGB2LAB).astype(np.float32)

def fit(L, zone, k, spread=0.55):
    """k clusters of the zone; keep clusters that occur all over the zone (present in >= `spread` of the zone's
    grid tiles). A rug, a sofa or a curtain is a big cluster too, but only in one place."""
    ys, xs = np.nonzero(zone)
    if len(xs) < 50: return None
    X = L[ys, xs].reshape(-1, 3)
    crit = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 40, 0.5)
    _, lbl, cen = cv2.kmeans(X, k, None, crit, 3, cv2.KMEANS_PP_CENTERS)
    lbl = lbl.ravel()
    T = 16
    tiles = (ys // T) * 10000 + (xs // T)
    ut, ti = np.unique(tiles, return_inverse=True)
    big = np.bincount(ti) >= T * T * 0.3
    wt = np.array([1.0, 2.0, 2.0], np.float32)
    out = []
    for i in range(k):
        sel = lbl == i
        if sel.sum() < 0.04 * len(X): continue
        cnt = np.bincount(ti[sel], minlength=len(ut))
        pres = ((cnt >= 3) & big).sum() / max(1, big.sum())
        if pres < spread: continue
        sd = np.sqrt((((X[sel] - cen[i]) * wt) ** 2).sum(1).mean())
        out.append((cen[i], max(6.0, sd)))
    if not out: return None
    return {"keep": out, "all": [c for c in cen]}

def classify(L, zone, model, tol=1.9):
    out = np.zeros(zone.shape, bool)
    if model is None: return out
    wt = np.array([1.0, 2.0, 2.0], np.float32)
    dall = np.stack([np.sqrt((((L - c) * wt) ** 2).sum(-1)) for c in model["all"]]).min(0)
    for c, s in model["keep"]:
        d = np.sqrt((((L - c) * wt) ** 2).sum(-1))
        out |= (d < tol * s) & (d <= dall + 1e-3)
    return out & zone

def excl_lights(shape, art):
    """Exclude fixture bodies / screens / shade / door glass so they stay id 0 (furniture), not wall/floor."""
    m = np.zeros(shape, bool)
    for l in art.get("lights", []):
        for k in ("shade", "screen", "core", "body", "vent", "quad", "display"):
            pts = l.get(k)
            if not pts: continue
            if isinstance(pts, list) and pts and isinstance(pts[0], list) and len(pts[0]) >= 2:
                m |= poly_mask(shape, pts)
        if isinstance(l.get("door"), dict):
            c = l["door"].get("c"); r = float(l["door"].get("r") or 0)
            ry = float(l["door"].get("ry") or r)
            if c and len(c) >= 2 and r > 0:
                yy, xx = np.ogrid[:shape[0], :shape[1]]
                m |= ((xx - c[0]) / (r + 2)) ** 2 + ((yy - c[1]) / (ry + 2)) ** 2 <= 1
    return cv2.dilate(m.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0

def close_in(b, zone, k=3):
    c = cv2.morphologyEx(b.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((k, k), np.uint8)) > 0
    return c & zone

def module_mask(rgba, tip, fw, fh, cut, art=None):
    rgb = rgba[..., :3]; a = rgba[..., 3] > 250
    if art is not None: a &= ~excl_lights(a.shape, art)
    L = lab(rgb)
    wall_hi, wall_lo, floor = zones(a.shape, tip, fw, fh, cut)
    wall_hi &= a; wall_lo &= a; floor &= a
    m = np.zeros(a.shape, np.uint8)
    if wall_hi.any():
        m[close_in(classify(L, wall_hi, fit(L, wall_hi, 5, spread=0.5), tol=1.7), wall_hi)] = 1
    m[close_in(classify(L, wall_lo, fit(L, wall_lo, 5, spread=0.5), tol=1.7), wall_lo)] = 2
    fm = fit(L, floor, 6)
    flo = close_in(classify(L, floor, fm, tol=1.6) & (L[..., 0] > 40), floor)
    # drop high-chroma / very dark pixels (rugs, chair legs, pots) even if a broad cluster matched
    if flo.any():
        ch = np.hypot(L[..., 1] - 128, L[..., 2] - 128)
        flo &= (ch < 32) | (L[..., 0] > 175)
        flo &= L[..., 0] > 60
        # green / blue furniture and plants on the floor plane
        flo &= ~((L[..., 1] < 120) & (ch > 18) & (L[..., 0] < 140))  # greenish
        flo &= ~((L[..., 2] < 120) & (L[..., 1] > 135) & (ch > 20))  # reddish rugs kept if woodlike; drop saturated reds

    mean = L[flo].mean(0) if flo.any() else np.array([0, 128, 128])
    chroma = np.hypot(mean[1] - 128, mean[2] - 128)
    m[flo] = 4 if (mean[0] > 150 and chroma < 22) else 3
    # small clean-up: drop isolated specks
    for v in (1, 2, 3, 4):
        b = (m == v).astype(np.uint8)
        b2 = cv2.morphologyEx(b, cv2.MORPH_OPEN, np.ones((2, 2), np.uint8))
        m[(b == 1) & (b2 == 0)] = 0
    return m

def overlay(rgba, m):
    cols = {1: (255, 60, 200), 2: (60, 200, 255), 3: (255, 200, 0), 4: (120, 255, 120)}
    o = rgba[..., :3].copy().astype(np.float32)
    for v, c in cols.items():
        o[m == v] = o[m == v] * 0.35 + np.array(c) * 0.65
    return o.astype(np.uint8)

if __name__ == "__main__":
    mod_dir, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    cat = json.load(open(os.path.join(mod_dir, "catalog.json")))
    for mid, art in cat["modules"].items():
        fw, fh = art["footprint"]
        for cut in (False, True):
            key = "day-unlit-cut" if cut else "day-unlit"
            f = os.path.join(mod_dir, os.path.basename(art["variants"][key]))
            rgba = np.array(Image.open(f).convert("RGBA"))
            m = module_mask(rgba, art["tip"], fw, fh, cut, art)
            name = f"mat-{mid}{'-cut' if cut else ''}.png"
            Image.fromarray(m).save(os.path.join(out_dir, name), optimize=True)
            Image.fromarray(overlay(rgba, m)).save(os.path.join(out_dir, "ov-" + name))
            print(name, {v: int((m == v).sum()) for v in range(5)})
