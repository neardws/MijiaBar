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
    pts = c[:, 0, :].astype(np.float32)
    # 左右两条竖边：最靠边的一列像素里取最高 / 最低点（比多边形近似稳）
    xmin, xmax = pts[:, 0].min(), pts[:, 0].max()
    lp = pts[pts[:, 0] <= xmin + 8]; rp = pts[pts[:, 0] >= xmax - 8]
    lt = lp[np.argmin(lp[:, 1])]; lb = lp[np.argmax(lp[:, 1])]
    rt = rp[np.argmin(rp[:, 1])]; rb = rp[np.argmax(rp[:, 1])]
    bottom = pts[np.argmax(pts[:, 1])]
    top = pts[np.argmin(pts[:, 1])]
    # 后墙角顶点：用上沿轮廓拟合左右两条墙顶线再求交（吊灯线、挂件不干扰）
    mo = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((7, 7), np.uint8))
    cols = np.arange(mo.shape[1])
    has = mo.max(0) > 0
    topy = np.where(has, np.argmax(mo > 0, axis=0), -1)
    def fit(x0, x1):
        xs = cols[int(x0):int(x1)]; ys = topy[int(x0):int(x1)]
        ok = ys >= 0
        a, b = np.polyfit(xs[ok], ys[ok], 1)
        return a, b
    span = rt[0] - lt[0]
    mid = top[0]
    a1, b1 = fit(lt[0] + 0.08 * span, mid - 0.12 * span)
    a2, b2 = fit(mid + 0.12 * span, rt[0] - 0.08 * span)
    tx = (b2 - b1) / (a1 - a2)
    top = np.array([tx, a1 * tx + b1], dtype=np.float32)
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

def _inv_map(Hm, w, h):
    """目标像素 → 源坐标（单应逆变换）。"""
    Hi = np.linalg.inv(Hm)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    v = Hi @ np.stack([xs.ravel(), ys.ravel(), np.ones(w * h, np.float32)])
    return (v[0] / v[2]).reshape(h, w).astype(np.float32), (v[1] / v[2]).reshape(h, w).astype(np.float32)

CUT_BG_LUM = 9  # 剖面版：墙区里和外部连通、比这更暗的像素算背景
BLEND = 36  # 墙区靠近地板后沿的一条带里，坐标场从“地面”平滑过渡到“墙面”，挡在墙前的家具不会在后沿处折断

def _extrude(floor_map, edge_row, h):
    """地板映射在后沿以上的“竖直延伸”：每一列取后沿那一点的源坐标，往上按地板映射在该点的竖直比例直走。
    （直接外推地板单应在源图有透视 / 两侧不对称时会让竖线歪斜——护墙板、电视、书架会斜。）"""
    fx, fy = floor_map
    w = fx.shape[1]
    cols = np.arange(w)
    ye = np.clip(np.round(edge_row).astype(int), 1, h - 2)
    x0 = fx[ye, cols]; y0 = fy[ye, cols]
    vs = fy[ye + 1, cols] - fy[ye - 1, cols]
    vs = vs / 2
    ys = np.arange(h, dtype=np.float32)[:, None]
    ex = np.broadcast_to(x0[None, :], (h, w)).astype(np.float32)
    ey = (y0[None, :] + (ys - edge_row[None, :]) * vs[None, :]).astype(np.float32)
    return ex, ey

def warp_to_canonical(img: np.ndarray, corners: dict, g, cut=False, s=2, border=cv2.BORDER_REPLICATE, full_rgb=None) -> Image.Image:
    src = planes_src(corners); dst = planes_dst(g, s); masks = region_masks(g, s)
    w, h = g['size'][0] * s, g['size'][1] * s
    maps = {k: _inv_map(cv2.getPerspectiveTransform(np.float32(src[k]), np.float32(dst[k])), w, h) for k in src}
    mx = np.zeros((h, w), np.float32); my = np.zeros((h, w), np.float32)
    T, R, L = [np.array(p, np.float32) * s for p in (g['T'], g['R'], g['L'])]
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    for k in ('floor', 'sw', 'se'):
        mx[masks[k]] = maps[k][0][masks[k]]; my[masks[k]] = maps[k][1][masks[k]]
    for k, a, b in (('nw', L, T), ('ne', T, R)):
        # 当前像素在地板后沿线上方多少
        t = np.clip((xs - a[0]) / (b[0] - a[0]), 0, 1)
        edge_y = a[1] + (b[1] - a[1]) * t
        wgt = np.clip((edge_y - ys) / (BLEND * s), 0, 1)
        fx, fy = _extrude(maps['floor'], edge_y[0], h)
        # 墙面映射的横向位置改用地板映射在后沿上的位置：两个单应在后沿上的参数化不一致（源图透视 / 房间不对称时
        # 能差几十像素），混合带里会把家具和护墙板拉斜。墙面纵向仍按墙的单应（保持竖直）。
        wx0, wy0 = maps[k]
        ye = np.clip(np.round(edge_y[0]).astype(int), 0, h - 1); cols = np.arange(w)
        wx = fx
        wy = (fy[ye, cols][None, :] + (wy0 - wy0[ye, cols][None, :])).astype(np.float32)
        mk = masks[k]
        mx[mk] = ((1 - wgt) * fx + wgt * wx)[mk]; my[mk] = ((1 - wgt) * fy + wgt * wy)[mk]
    out = cv2.remap(img.astype(np.float32), mx, my, interpolation=cv2.INTER_CUBIC, borderMode=border)
    alpha = cut_alpha(out, g, s, full_rgb) if cut else silhouette_mask(g, s, cut=False)
    rgba = np.dstack([np.clip(out, 0, 255).astype(np.uint8), (alpha * 255).astype(np.uint8)])
    return Image.fromarray(rgba, 'RGBA')

FRINGE_LUM = 24

def cut_alpha(rgb: np.ndarray, g, s=2, full_rgb=None) -> np.ndarray:
    """剖面版的 alpha：墙区里和画布外连通的“背景”去掉。
    背景 = 很暗（< CUT_BG_LUM）；或者（有原图时）矮墙顶以上、原图那里是亮墙纸、剖面版却发暗的灰雾。"""
    sil = silhouette_mask(g, s, cut=False)
    masks = region_masks(g, s)
    lum = rgb.astype(np.float32).mean(-1)
    wallzone = masks['nw'] | masks['ne']
    bg = wallzone & (lum < CUT_BG_LUM)
    if full_rgb is not None:
        h, w = lum.shape
        ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
        T, R, L = [np.array(p, np.float32) * s for p in (g['T'], g['R'], g['L'])]
        edge = np.where(xs < T[0], T[1] + (xs - T[0]) * (L[1] - T[1]) / (L[0] - T[0]),
                        T[1] + (xs - T[0]) * (R[1] - T[1]) / (R[0] - T[0]))
        above = (edge - ys) > (CUT_H + 3) * s
        flum = full_rgb.astype(np.float32).mean(-1)
        # 有原图时：只在矮墙顶以上判背景——原图那里明显更亮（墙纸）而剖面版发暗，才算被切掉的墙；
        # 原图里也暗的（书架侧板、家具阴影）保留
        bg = wallzone & above & (((lum < 60) & (flum - lum > 30)) | (lum < 4))
    n, lab = cv2.connectedComponents((bg | ~sil).astype(np.uint8))
    keep = set(np.unique(lab[0, :])) - {0}
    alpha = sil & ~(np.isin(lab, list(keep)) & bg)
    # 去黑边：生成器剖面版在切口 / 家具剪影外缘常留 1~2px 近黑锯齿（JPEG 背景渗色），叠到别的房间上很显眼。
    # 墙区里贴着透明区的近黑像素剥掉，最多 3 圈（家具自己的描边是深棕，亮度高于阈值，保留）。
    k3 = np.ones((3, 3), np.uint8)
    for _ in range(3):
        edge_px = alpha & (cv2.dilate((~alpha).astype(np.uint8), k3) > 0) & wallzone & (lum < FRINGE_LUM)
        if not edge_px.any(): break
        alpha = alpha & ~edge_px
    return alpha

def align_to(ref: np.ndarray, img: np.ndarray, region: np.ndarray | None = None) -> np.ndarray:
    """生成器的编辑版和原图可能有几像素漂移：ECC 求仿射，返回 2x3 矩阵（img → ref）。"""
    a = cv2.cvtColor(ref, cv2.COLOR_RGB2GRAY).astype(np.float32) / 255
    b = cv2.cvtColor(img, cv2.COLOR_RGB2GRAY).astype(np.float32) / 255
    warp = np.eye(2, 3, dtype=np.float32)
    # 初值：两张图剪影的左右边界 + 底部对齐（编辑版偶尔会整体缩放/平移）
    def box(im):
        m = im.astype(np.float32).mean(-1) > 16
        m = cv2.morphologyEx(m.astype(np.uint8), cv2.MORPH_OPEN, np.ones((5, 5), np.uint8)) > 0
        ys, xs = np.nonzero(m)
        return xs.min(), xs.max(), ys.max()
    try:
        ax0, ax1, ay1 = box(ref); bx0, bx1, by1 = box(img)
        k = (bx1 - bx0) / max(ax1 - ax0, 1)
        if 0.7 < k < 1.4:
            warp = np.float32([[k, 0, bx0 - k * ax0], [0, k, by1 - k * ay1]])
    except ValueError:
        pass
    mask = None if region is None else region.astype(np.uint8)
    try:
        _, warp = cv2.findTransformECC(a, b, warp, cv2.MOTION_AFFINE,
                                       (cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 200, 1e-6), mask, 5)
    except cv2.error:
        pass
    return warp

def floor_region_mask(img: np.ndarray, corners: dict) -> np.ndarray:
    import PIL.ImageDraw as D
    m = Image.new('L', (img.shape[1], img.shape[0]), 0)
    D.Draw(m).polygon([tuple(p) for p in (corners['B'], corners['R'], corners['F'], corners['L'])], fill=255)
    return np.asarray(m) > 0

def map_corners(corners: dict, warp: np.ndarray) -> dict:
    """warp 是 ref→img 的仿射（ECC 的约定：img(x') = ref 坐标经 warp）。"""
    out = dict(corners)
    for k, v in corners.items():
        if isinstance(v, list) and len(v) == 2:
            p = warp @ np.array([v[0], v[1], 1.0])
            out[k] = p.tolist()
    return out

# ---------- bake ----------
def bake_module(base_rgb: np.ndarray, phase: str, mod: dict, cut: bool, bodies: bool = True) -> tuple[np.ndarray, np.ndarray]:
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
    for light in (lights if bodies else []):
        if 'shade' in light: bakelib.paint_shade(lit, light['shade'], phase)
        if light['kind'] == 'screen': bakelib.paint_screen(lit, light['screen'], phase, light.get('style', 'tv'))
        if light['kind'] == 'ac': paint_ac(lit, light, phase)
    return unlit, lit

def paint_ac(img: np.ndarray, light: dict, phase: str):
    """空调送风点：和经典版 bakelib.paint_ac 一样的点阵，但按空调所在的墙决定往哪边飘——
    NE 墙（面朝左前）往左下，NW 墙（面朝右前）往右下。"""
    (x0, y0), (x1, y1) = light["vent"]
    sx = 1.2 if light.get("wall") == "nw" else -1.2
    rng = np.random.default_rng(7)
    PX_ = bakelib.PX
    for i in range(18):
        t = (i + 0.5) / 18
        bx, by = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
        for k in range(1, 6):
            if rng.random() < 0.55:
                x = int(bx + k * sx * 2.0 + rng.integers(-1, 2)) // PX_ * PX_
                y = int(by + k * 5 + rng.integers(-1, 2)) // PX_ * PX_
                a = 0.75 - k * 0.11
                img[y:y + PX_, x:x + PX_] = img[y:y + PX_, x:x + PX_] * (1 - a) + np.array([0.62, 0.86, 1.0]) * a
    lx, ly = light["led"]
    img[ly:ly + PX_, lx:lx + PX_] = [0.45, 1.0, 0.75]

def measure_low_wall(cut_img: np.ndarray, cc: dict, g) -> float:
    """剖面版的矮墙在规范图里有多高（中位数；家具冒出来的列会被中位数压掉）。"""
    a = np.asarray(warp_to_canonical(cut_img, cc, g, cut=True, s=1))[..., 3]
    T, R, L = g['T'], g['R'], g['L']
    hs = []
    for p, q in ((L, T), (T, R)):
        for t in np.linspace(0.08, 0.92, 12 * (1 if p is L else g['fw'])):
            x = int(p[0] + (q[0] - p[0]) * t); y = p[1] + (q[1] - p[1]) * t
            ys = np.where(a[:int(y) + 1, x] > 0)[0]
            if len(ys): hs.append(y - ys[0])
    return float(np.median(hs)) if hs else float(CUT_H)

def cut_corners(full: np.ndarray, cut_img: np.ndarray, c: dict, g) -> dict:
    """剖面版：ECC 对齐到原图 → 量矮墙高度 → 把墙面映射纵向缩放，让矮墙顶正好落在 CUT_H。"""
    cc = map_corners(c, align_to(full, cut_img, floor_region_mask(full, c)))
    low = measure_low_wall(cut_img, cc, g)
    f = low / CUT_H
    if abs(f - 1) > 0.03 and 0.6 < f < 1.6:
        cc = dict(cc)
        for top, base in (('top', 'B'), ('lt', 'L'), ('rt', 'R')):
            t, b = np.array(cc[top]), np.array(cc[base])
            cc[top] = (b + (t - b) * f).tolist()
    cc['_low'] = low
    return cc
