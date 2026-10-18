"""2x1 客厅：生成器画不出 2:1 的长房间（总是 ~1.5:1，硬拉伸会把家具拉歪）。
做法：两张源图拼接——左格 = living（1x1：沙发、落地灯、窗、壁灯），右格 = livingR（同风格的长房间，约 1.45:1，
只有离墙摆放的电视柜和绿植）。右格是长房间时按 1:1 取它右端 2-SEAM0 格（不拉伸）；源图只有 1x1 时退回
列 [S0, 1] → [SEAM0, 2] 的拉伸映射。接缝处平滑过渡并按地板亮度对齐色调，左前沿（地台）和 NE 墙顶压条
用左格的剖面重画，盖住两张图的厚度 / 压条差。
产物 src/living-day-{full,cut}-canon.png（s=2 规范 RGBA），build.py 直接使用。
用法：python3 scripts/house_modules/extend.py pair living livingR
"""
import sys, json, numpy as np, cv2
from PIL import Image
import sys; sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
import pipeline as pl
from geom import *

import os
RAW = os.environ.get('HOUSE_RAW', str(__import__('pathlib').Path(__file__).resolve().parents[2] / 'assets/house/modules/src'))

def load(p): return np.asarray(Image.open(p).convert('RGB'))

def col_field(g, s=2):
    w, h = g['size'][0] * s, g['size'][1] * s
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    Tx, Ty = g['T'][0] * s, g['T'][1] * s
    colf = ((xs - Tx) / (W / 2 * s) + (ys - Ty) / (FH / 2 * s)) / 2
    roww = ((ys - Ty) / (FH / 2 * s) - (xs - Tx) / (W / 2 * s)) / 2
    colw = (xs - Tx) / (W / 2 * s)
    above = roww < 0  # 地板后沿以上（NE 墙区）
    return np.where(above & (xs > Tx), colw, colf)

def fix_front_edge(rgb, g, col, s=2, rim=10):
    """左前沿（地板前沿一条 + SW 地台）：用左格 col∈[0.15,0.75] 的“到前沿的竖直距离 → 颜色”中位数剖面
    重画 col>0.75 的部分（0.6~0.8 羽化），盖住两张源图在前沿的厚度/亮度差，不会出台阶。"""
    h, w = rgb.shape[:2]
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    L, F = np.array(g['L'], np.float32) * s, np.array(g['F'], np.float32) * s
    edge_y = L[1] + (xs - L[0]) * (F[1] - L[1]) / (F[0] - L[0])
    d = np.round(ys - edge_y).astype(int)
    inx = (xs >= L[0]) & (xs <= F[0])
    zone = inx & (d >= -rim) & (d <= SLAB * s)
    prof = {}
    ref = zone & (col > 0.15) & (col < 0.75)
    for k in range(-rim, SLAB * s + 1):
        m = ref & (d == k)
        if m.any(): prof[k] = np.median(rgb[m].reshape(-1, 3), 0)
    paint = np.zeros_like(rgb, dtype=np.float32)
    for k, c in prof.items(): paint[zone & (d == k)] = c
    # 保留一点原有的横向纹理（高频），避免完全平涂
    blur = cv2.GaussianBlur(rgb.astype(np.float32), (0, 0), 3)
    paint = paint + 0.6 * (rgb.astype(np.float32) - blur)
    wgt = (np.clip((col - 0.6) / 0.2, 0, 1) * zone)[..., None]
    return rgb * (1 - wgt) + paint * wgt

def fix_top_edge(rgb, g, col, s=2, depth=16):
    """NE 墙顶的压条：右格源图的墙顶压条和左格不一样（或者被裁掉），用左格 col∈[0.2,0.75] 的
    “到墙顶的竖直距离 → 颜色”中位数剖面重画 col>0.75 的墙顶一条（0.6~0.85 羽化）。"""
    h, w = rgb.shape[:2]
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    T, R = np.array(g['T'], np.float32) * s, np.array(g['R'], np.float32) * s
    top_y = (T[1] - WALL_H * s) + (xs - T[0]) * (R[1] - T[1]) / (R[0] - T[0])
    d = np.round(ys - top_y).astype(int)
    zone = (xs >= T[0]) & (xs <= R[0]) & (d >= 0) & (d < depth)
    prof = {}
    ref = zone & (col > 0.2) & (col < 0.75)
    for k in range(depth):
        m = ref & (d == k)
        if m.any(): prof[k] = np.median(rgb[m].reshape(-1, 3), 0)
    paint = rgb.astype(np.float32).copy()
    for k, c in prof.items(): paint[zone & (d == k)] = c
    blur = cv2.GaussianBlur(rgb.astype(np.float32), (0, 0), 2)
    paint = paint + 0.4 * (rgb.astype(np.float32) - blur)
    wgt = (np.clip((col - 0.6) / 0.25, 0, 1) * zone)[..., None]
    return rgb * (1 - wgt) + paint * wgt

SEAM0, SEAM1, S0 = 0.84, 0.94, 0.14

def stage_pair(mid, fw=2, mid2=None):
    """左格 = <mid> 源图（1x1 房间），右格 = <mid2> 源图（同一房间的编辑版，1x1）的 NE 墙 + 地板。"""
    g = module_geom(fw); g1 = module_geom(1)
    col = col_field(g)
    for v in ('full', 'cut'):
        cells = []
        for m in (mid, mid2):
            full = load(f'{RAW}/{m}-day-full.jpg'); src = load(f'{RAW}/{m}-day-{v}.jpg')
            c = pl.detect_corners(full)
            cj = f'{RAW}/{m}-corners.json'
            import os
            if os.path.exists(cj): c.update(json.load(open(cj)))
            if v == 'cut':
                c = pl.cut_corners(full, src, c, g1); print(m, 'low wall', round(c['_low'], 1))
            if m == mid:
                cells.append(np.asarray(pl.warp_to_canonical(src, c, g1, cut=(v == 'cut'), border=cv2.BORDER_CONSTANT)))
            else:
                # 右格：源图的列 [S0, 1] → 2x1 的列 [SEAM0, 2]（避开源图左后墙根部），沿列方向轻微拉伸
                k = (1 - S0) / (2 - SEAM0); c0 = S0 - SEAM0 * k   # 2x1 列 0 对应的源列
                a2 = float(np.linalg.norm(np.subtract(c['R'], c['B'])) / np.linalg.norm(np.subtract(c['L'], c['B'])))
                if a2 >= 2 - SEAM0 + 0.1:
                    # 右格源图本身是长房间（a2 格宽）：按 1:1 取它右端 2-SEAM0 格，不拉伸
                    c0 = 1 - 2 / a2
                print(m, 'a2', round(a2, 3), 'c0', round(c0, 3))
                vc = dict(c)
                for a_, b_ in (('B', 'R'), ('top', 'rt'), ('L', 'F'), ('lb', 'bottom')):
                    pa, pb = np.array(c[a_]), np.array(c[b_])
                    vc[a_] = (pa + (pb - pa) * c0).tolist()
                vc['lt'] = (np.array(vc['top']) + np.array(c['lt']) - np.array(c['top'])).tolist()
                cells.append(np.asarray(pl.warp_to_canonical(src, vc, g, cut=(v == 'cut'), border=cv2.BORDER_CONSTANT)))
        h, w = g['size'][1] * 2, g['size'][0] * 2
        A = np.zeros((h, w, 4), np.uint8); A[:cells[0].shape[0], :cells[0].shape[1]] = cells[0]
        Bm = cells[1]
        # 接缝：左格到 SEAM0 为止（右端墙头/地台角的痕迹在 0.96 以后），右格从 SEAM1 起
        # 右格整体色调对齐左格：比较接缝两侧同一条地板带的均值
        masks = pl.region_masks(g, 2)
        fl = masks['floor'] & (A[..., 3] > 0) & (Bm[..., 3] > 0)
        band = fl & (col > SEAM0 - 0.1) & (col < SEAM1)
        wb = (masks['ne']) & (A[..., 3] > 0) & (Bm[..., 3] > 0) & (col > SEAM0 - 0.04) & (col < SEAM1)
        Bf = Bm[..., :3].astype(np.float32)
        gf = A[..., :3][band].reshape(-1, 3).mean(0) / np.maximum(Bf[band].reshape(-1, 3).mean(0), 1)
        gw = A[..., :3][wb].reshape(-1, 3).mean(0) / np.maximum(Bf[wb].reshape(-1, 3).mean(0), 1)
        print(v, 'gain floor', np.round(gf, 3), 'wall', np.round(gw, 3))
        # 只做亮度增益 + 有限的通道修正，避免电视等家具被染色
        lum_g = float(np.mean(gf * [0.3, 0.59, 0.11]) / 0.3333)
        lum_g = float((A[..., :3][band].reshape(-1, 3) @ [0.3, 0.59, 0.11]).mean() / max((Bf[band].reshape(-1, 3) @ [0.3, 0.59, 0.11]).mean(), 1))
        ch = np.clip(gf / lum_g, 0.93, 1.07)
        Bf = Bf * lum_g * ch
        Bm = np.dstack([np.clip(Bf, 0, 255), Bm[..., 3:]])
        wgt = np.clip((col - SEAM0) / (SEAM1 - SEAM0), 0, 1)[..., None]
        wgt = wgt * wgt * (3 - 2 * wgt)
        rgb = A[..., :3] * (1 - wgt) + Bm[..., :3] * wgt
        rgb = fix_front_edge(rgb, g, col)
        if v == 'full':
            rgb = fix_top_edge(rgb, g, col)
        sil = pl.silhouette_mask(g, 2, cut=False)
        alpha = sil.copy()
        if v == 'cut':
            alpha = pl.cut_alpha(rgb, g, 2, full_canon)
        else:
            full_canon = rgb.copy()
        out = np.dstack([np.clip(rgb, 0, 255).astype(np.uint8), (alpha * 255).astype(np.uint8)])
        Image.fromarray(out, 'RGBA').save(f'{RAW}/{mid}-day-{v}-canon.png')
        print(v, 'ok')

if __name__ == '__main__':
    {'pair': stage_pair}[sys.argv[1]](sys.argv[2], 2, *sys.argv[3:])
