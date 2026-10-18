"""Reference for the runtime theme recolor (Swift: HouseRecolor). out = D * Sat(s) * in, per material,
where D is chosen so the material's base mean colour maps exactly onto the theme colour."""
import numpy as np, json, sys
from PIL import Image
LUM = np.array([0.299, 0.587, 0.114])
def hexc(h): h = h.lstrip('#'); return np.array([int(h[i:i+2], 16) for i in (0, 2, 4)], float) / 255
def matrix(base, tone):
    s = tone.get('saturation', 1.0)
    S = s * np.eye(3) + (1 - s) * np.tile(LUM, (3, 1))
    sb = S @ base
    D = np.diag(hexc(tone['color']) / np.maximum(sb, 1e-3))
    return D @ S
def recolor(rgba, mat, bases, theme):
    out = rgba.astype(float).copy()
    rgb = out[..., :3] / 255
    for mid, tone in theme.items():
        m = mat == int(mid)
        if not m.any() or mid not in bases: continue
        M = matrix(np.array(bases[mid]), tone)
        rgb[m] = np.clip(rgb[m] @ M.T, 0, 1)
    out[..., :3] = rgb * 255
    return out.round().astype(np.uint8)
def bases_of(pairs):
    acc = {}
    for rgba, mat in pairs:
        a = rgba[..., 3] > 250
        for v in (1, 2, 3, 4):
            sel = (mat == v) & a
            if sel.any(): acc.setdefault(str(v), []).append(rgba[sel][:, :3] / 255)
    return {k: np.concatenate(v).mean(0).round(4).tolist() for k, v in acc.items()}
THEMES = {
  "light-wood": {"1": {"color": "#E6E0D4", "saturation": 0.35}, "2": {"color": "#C49A6C", "saturation": 0.8},
                 "3": {"color": "#C79B6B", "saturation": 0.8}, "4": {"color": "#E4E2DC", "saturation": 0.6}},
  "walnut":     {"1": {"color": "#A9B39A", "saturation": 0.45}, "2": {"color": "#4E3324", "saturation": 0.9},
                 "3": {"color": "#5C3B28", "saturation": 0.9}, "4": {"color": "#CFD3C8", "saturation": 0.6}},
}
