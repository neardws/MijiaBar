"""模块美术流水线（与整图 house-cutaway-* 同一套处理）：

  源图（生成器出的单房间剖面：全高墙版 + 切墙版，可选夜景版）
    → fit：按地板 / 两面后墙 / 地台四个平面做单应变换，贴到规范几何
    → pixelize：半分辨率 LANCZOS + 亮度/对比度 + NEAREST 放大（gen-house-cutaway-art.py 同参数）
    → night：用经典整图 day→night 学到的 3D LUT 调色（像素对齐），窗外换夜空
    → bake：gen-house-baked-lighting.py 的灯光函数烘焙 lit 版
"""
from __future__ import annotations
import importlib.util, json, sys
from pathlib import Path
import numpy as np
import cv2
from PIL import Image, ImageEnhance, ImageFilter
import sys; sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
from geom import *

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location('bakelib', HERE.parent / 'gen-house-baked-lighting.py')
bakelib = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(bakelib)

# ---------- pixelize（与 gen-house-cutaway-art.py 一致） ----------
def pixelize_rgba(im: Image.Image, brightness=0.96, contrast=1.05) -> Image.Image:
    """输入 2x 规范尺寸 RGBA，输出 1x、PX=2 像素格。"""
    w2, h2 = im.size
    w, h = w2 // 2, h2 // 2
    rgb = im.convert('RGB').resize((w // 2, h // 2), Image.Resampling.LANCZOS)
    rgb = ImageEnhance.Brightness(rgb).enhance(brightness)
    rgb = ImageEnhance.Contrast(rgb).enhance(contrast)
    rgb = rgb.resize((w, h), Image.Resampling.NEAREST).filter(ImageFilter.SHARPEN)
    a = im.getchannel('A').resize((w // 2, h // 2), Image.Resampling.BOX)
    a = a.point(lambda v: 255 if v >= 128 else 0).resize((w, h), Image.Resampling.NEAREST)
    out = rgb.convert('RGBA'); out.putalpha(a)
    return out

# ---------- night LUT（经典整图 day-base → night-base） ----------
_LUT = None
def night_lut(day_base: Path, night_base: Path, bins=24):
    global _LUT
    if _LUT is not None: return _LUT
    d = np.asarray(Image.open(day_base).convert('RGB'), dtype=np.float32) / 255
    n = np.asarray(Image.open(night_base).convert('RGB'), dtype=np.float32) / 255
    # 只取房间内的像素（排除黑底），排除窗户天空（蓝）
    lum = d.mean(-1)
    sky = (d[..., 2] > d[..., 0] + 0.12) & (d[..., 2] > 0.45)
    m = (lum > 0.03) & ~sky
    idx = np.clip((d[m] * bins).astype(int), 0, bins - 1)
    flat = idx[:, 0] * bins * bins + idx[:, 1] * bins + idx[:, 2]
    sums = np.zeros((bins ** 3, 3)); cnt = np.zeros(bins ** 3)
    np.add.at(sums, flat, n[m]); np.add.at(cnt, flat, 1)
    lut = np.zeros((bins ** 3, 3), dtype=np.float32)
    have = cnt > 3
    lut[have] = sums[have] / cnt[have][:, None]
    # 空 bin：用全局比例回退（按通道的平均 night/day 增益）
    gain = (n[m].mean(0) + 1e-3) / (d[m].mean(0) + 1e-3)
    centers = (np.stack(np.unravel_index(np.arange(bins ** 3), (bins,) * 3), -1) + 0.5) / bins
    lut[~have] = np.clip(centers[~have] * gain, 0, 1)
    lut = lut.reshape(bins, bins, bins, 3)
    # 平滑一点，避免相邻 bin 跳变
    from scipy.ndimage import uniform_filter
    for c in range(3): lut[..., c] = uniform_filter(lut[..., c], size=3, mode='nearest')
    _LUT = (lut, bins)
    return _LUT

def apply_night(rgb: np.ndarray, lut_bins, night_sky: np.ndarray | None = None) -> np.ndarray:
    lut, bins = lut_bins
    from scipy.ndimage import map_coordinates
    coords = np.clip(rgb * bins - 0.5, 0, bins - 1)
    out = np.stack([map_coordinates(lut[..., c], coords.reshape(-1, 3).T, order=1).reshape(rgb.shape[:2]) for c in range(3)], -1)
    sky = (rgb[..., 2] > rgb[..., 0] + 0.12) & (rgb[..., 2] > 0.45)
    if night_sky is not None:
        out[sky] = night_sky[sky]
    else:
        # 没有生成的夜景版：画一个深蓝夜空 + 稀疏星点
        h, w = rgb.shape[:2]
        ys, xs = np.mgrid[0:h, 0:w]
        base = np.stack([0.06 + 0.04 * (ys / h), 0.09 + 0.05 * (ys / h), 0.24 + 0.08 * (ys / h)], -1)
        star = ((xs // PX * 7 + ys // PX * 13) % 97 == 0)
        base[star] = [0.85, 0.9, 1.0]
        out[sky] = base[sky]
    return np.clip(out, 0, 1)

# ---------- fit：生成图 → 规范几何 ----------
def detect_corners(img: np.ndarray, slab_frac=0.028) -> dict:
    """生成图（黑底单房间）剪影 → 6 个外角 + 推出地板四角。"""
    lum = img.astype(np.float32).mean(-1)
    m = (lum > 16).astype(np.uint8) * 255
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    cs, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    c = max(cs, key=cv2.contourArea)
    hull = cv2.convexHull(c)
    peri = cv2.arcLength(hull, True)
    for eps in np.linspace(0.005, 0.06, 60):
        ap = cv2.approxPolyDP(hull, eps * peri, True)[:, 0, :]
        if len(ap) <= 6: break
    pts = ap.astype(np.float32)
    top = pts[np.argmin(pts[:, 1])]
    bottom = pts[np.argmax(pts[:, 1])]
    left = pts[pts[:, 0] < top[0]]
    right = pts[pts[:, 0] > top[0]]
    lt = left[np.argmin(left[:, 1])]; lb = left[np.argmax(left[:, 1])]
    rt = right[np.argmin(right[:, 1])]; rb = right[np.argmax(right[:, 1])]
    if np.allclose(lb, bottom): lb = left[np.argmin(left[:, 0])]
    if np.allclose(rb, bottom): rb = right[np.argmax(right[:, 0])]
    H = img.shape[0]
    # 地台厚度：从前角往上扫，地台（暗）→ 地板（亮）的最大亮度跳变
    bx, by = int(bottom[0]), int(bottom[1])
    prof = lum[max(0, by - 70):by + 1, max(0, bx - 4):bx + 5].mean(1)[::-1]
    prof = np.convolve(prof, np.ones(3) / 3, mode='same')
    grad = prof[4:] - prof[:-4]
    slab = float(np.argmax(grad[2:60]) + 4) if len(grad) > 62 else slab_frac * H
    Lf = lb - [0, slab]; Rf = rb - [0, slab]; Ff = bottom - [0, slab]
    wall_h = ((Lf[1] - lt[1]) + (Rf[1] - rt[1])) / 2
    B = top + [0, wall_h]
    return dict(top=top.tolist(), lt=lt.tolist(), lb=lb.tolist(), rt=rt.tolist(), rb=rb.tolist(), bottom=bottom.tolist(),
                B=B.tolist(), L=Lf.tolist(), R=Rf.tolist(), F=Ff.tolist(), wall_h=float(wall_h), slab=float(slab))

def planes_src(c):
    top, lt, rt = c['top'], c['lt'], c['rt']
    B, L, R, F = c['B'], c['L'], c['R'], c['F']
    lb, rb, bottom = c['lb'], c['rb'], c['bottom']
    return dict(floor=[B, R, F, L], nw=[top, lt, L, B], ne=[top, rt, R, B],
                sw=[L, F, bottom, lb], se=[F, R, rb, bottom])

def planes_dst(g, s=2):
    T, R, F, L = g['T'], g['R'], g['F'], g['L']
    up = lambda p: (p[0], p[1] - WALL_H); dn = lambda p: (p[0], p[1] + SLAB)
    sc = lambda q: [[x * s, y * s] for x, y in q]
    return dict(floor=sc([T, R, F, L]), nw=sc([up(T), up(L), L, T]), ne=sc([up(T), up(R), R, T]),
                sw=sc([L, F, dn(F), dn(L)]), se=sc([F, R, dn(R), dn(F)]))

def region_masks(g, s=2):
    """目标图里每个像素归哪个平面：墙区 = 地板后沿以上（含挡在墙前的家具）。"""
    w, h = g['size'][0] * s, g['size'][1] * s
    T, R, F, L = [(p[0] * s, p[1] * s) for p in (g['T'], g['R'], g['F'], g['L'])]
    S = SLAB * s
    import PIL.ImageDraw as D
    def poly(pts):
        m = Image.new('L', (w, h), 0); D.Draw(m).polygon([tuple(p) for p in pts], fill=255)
        return np.asarray(m) > 0
    nw = poly([(T[0], 0), (T[0], T[1]), L, (L[0] - 40, L[1]), (L[0] - 40, 0)])
    ne = poly([(T[0], 0), (R[0] + 40, 0), (R[0] + 40, R[1]), R, T])
    floor = poly([T, R, F, L])
    sw = poly([L, F, (F[0], F[1] + S), (L[0], L[1] + S)]) & ~floor
    se = poly([F, R, (R[0], R[1] + S), (F[0], F[1] + S)]) & ~floor
    return dict(nw=nw & ~floor, ne=ne & ~floor & ~nw, floor=floor, sw=sw, se=se)

def silhouette_mask(g, s=2, cut=False):
    import PIL.ImageDraw as D
    w, h = g['size'][0] * s, g['size'][1] * s
    hh = CUT_H if cut else WALL_H
    T, R, F, L = g['T'], g['R'], g['F'], g['L']
    pts = [(T[0], T[1] - hh), (R[0], R[1] - hh), R, (R[0], R[1] + SLAB), (F[0], F[1] + SLAB), (L[0], L[1] + SLAB), L, (L[0], L[1] - hh)]
    m = Image.new('L', (w, h), 0); D.Draw(m).polygon([(x * s, y * s) for x, y in pts], fill=255)
    return np.asarray(m) > 0

def warp_to_canonical(img: np.ndarray, corners: dict, g, cut=False, s=2) -> Image.Image:
    src = planes_src(corners); dst = planes_dst(g, s); masks = region_masks(g, s)
    w, h = g['size'][0] * s, g['size'][1] * s
    out = np.zeros((h, w, 3), np.float32)
    for k in ('floor', 'nw', 'ne', 'sw', 'se'):
        Hm = cv2.getPerspectiveTransform(np.float32(src[k]), np.float32(dst[k]))
        wk = cv2.warpPerspective(img.astype(np.float32), Hm, (w, h), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)
        out[masks[k]] = wk[masks[k]]
    alpha = silhouette_mask(g, s, cut=False)
    if cut:
        # 切墙版：墙区里接近黑色的像素 = 背景（被切掉的墙上方）
        lum = out.mean(-1)
        wallzone = masks['nw'] | masks['ne']
        alpha = alpha & ~(wallzone & (lum < 14))
    rgba = np.dstack([np.clip(out, 0, 255).astype(np.uint8), (alpha * 255).astype(np.uint8)])
    return Image.fromarray(rgba, 'RGBA')

# ---------- bake ----------
def bake_module(base_rgb: np.ndarray, phase: str, mod: dict, cut: bool) -> tuple[np.ndarray, np.ndarray]:
    """与 gen-house-baked-lighting.bake 同参数，只是作用在单个模块上。"""
    h, w, _ = base_rgb.shape
    X, Y = bakelib.grid(w, h)
    if phase == 'night':
        unlit = np.clip(base_rgb * np.array([0.80, 0.82, 0.92]) + np.array([0.0, 0.004, 0.018]), 0, 1)
    else:
        unlit = base_rgb.copy()
    lit = unlit.copy()
    gain = 2.5 if phase == 'night' else 1.0
    room = bakelib.poly_mask((w, h), mod['region'], feather=1.0)
    lights = [L for L in mod['lights'] if not (cut and L.get('wall'))]
    for light in lights:
        f = bakelib.light_field(light, X, Y) * light.get('strength', 1.0)
        f = bakelib.band(np.clip(f, 0, 1), 7) * room * bakelib.reveal_mask(light, (w, h))
        col = bakelib.SCREEN if light['kind'] == 'screen' else bakelib.COOL if light['kind'] == 'ac' else bakelib.WARM
        if light['kind'] == 'ac': gg = 0.9 if phase == 'night' else 0.35
        elif light['kind'] == 'screen': gg = 1.3 if phase == 'night' else 0.4
        else: gg = gain
        lit = lit * (1 + f[..., None] * gg * col) + (f ** 2)[..., None] * col * (0.38 if phase == 'night' else 0.12)
    lit = np.clip(lit, 0, 1)
    for light in lights:
        if 'shade' in light: bakelib.paint_shade(lit, light['shade'], phase)
        if light['kind'] == 'screen': bakelib.paint_screen(lit, light['screen'], phase, light.get('style', 'tv'))
        if light['kind'] == 'ac': bakelib.paint_ac(lit, light, phase)
    return unlit, lit
