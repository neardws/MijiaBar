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
WORK = os.environ.get('HOUSE_WORK', '/tmp/house-work'); os.makedirs(WORK, exist_ok=True)
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

def fix_top_edge(rgb, g, col, s=2, depth=28):
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

def fix_rail(rgb, g, col, masks, zlo=54, zhi=86, s=2):
    """护墙板顶木线：右格源图的木线比左格低 ~6px、颜色也偏黄。用左格 col∈[0.62,0.84]（窗帘和壁灯之间）的
    “离墙根高度 → 颜色”中位数剖面重画 col>0.9 的这一条（0.86~0.94 羽化），保留一点横向纹理。"""
    z = np.round(wall_z(g, rgb.shape[:2], s)).astype(int)
    import PIL.ImageDraw as D
    pm = Image.new('L', (rgb.shape[1], rgb.shape[0]), 0)
    D.Draw(pm).polygon(PROTECT[0], fill=255)     # 只护电视（绿植在木线以下）
    zone = masks['ne'] & (z >= zlo) & (z < zhi) & ~(np.asarray(pm) > 0)
    ref = zone & (col > 0.62) & (col < 0.84)
    paint = rgb.astype(np.float32).copy()
    for k in range(zlo, zhi):
        m = ref & (z == k)
        if m.any(): paint[zone & (z == k)] = np.median(rgb[m].reshape(-1, 3), 0)
    blur = cv2.GaussianBlur(rgb.astype(np.float32), (0, 0), 2)
    paint = paint + 0.35 * (rgb.astype(np.float32) - blur)
    wgt = (np.clip((col - 0.86) / 0.08, 0, 1) * zone)[..., None]
    return rgb * (1 - wgt) + paint * wgt

# 右格源图里不参与分区调色的家具（s=2 规范坐标多边形）：只做亮度增益，免得电视 / 绿植被墙纸增益染色
PROTECT = [[(735, 294), (752, 294), (849, 336), (849, 420), (865, 428), (865, 477), (822, 501), (806, 501), (707, 449), (707, 392), (733, 380)],
           [(922, 426), (984, 426), (984, 514), (922, 514)]]

def wall_z(g, shape, s=2):
    """NE 墙区每个像素离墙根的高度（s=2 像素）"""
    h, w = shape
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    T, R = np.array(g['T'], np.float32) * s, np.array(g['R'], np.float32) * s
    return T[1] + (xs - T[0]) * (R[1] - T[1]) / (R[0] - T[0]) - ys

def match_zones(A, Bm, g, col, masks, s=2):
    """右格分区调色：NE 墙的墙纸带 / 护墙板带 / 地板各自按“接缝左侧一条 vs 右侧一条”的逐通道中位数求增益，
    分区之间按高度羽化。只比亮度会留下墙纸的冷暖差（左格偏灰、右格偏粉），这里逐通道对齐。"""
    import PIL.ImageDraw as D
    z = wall_z(g, A.shape[:2], s)
    ok = (A[..., 3] > 0) & (Bm[..., 3] > 0)
    Bf = Bm[..., :3].astype(np.float32)
    left = (col > 0.8) & (col < 0.92); right = (col > SEAM1) & (col < 1.1)
    ne = masks['ne']
    zones = dict(paper=ne & (z >= 80) & (z < 182), wains=ne & (z >= 6) & (z < 68), floor=masks['floor'])
    gains = {}
    for k, m in zones.items():
        if (m & ok & left).sum() < 50 or (m & ok & right).sum() < 50:
            gains[k] = np.ones(3); continue
        a = np.median(A[..., :3][m & ok & left].reshape(-1, 3), 0)
        b = np.median(Bf[m & ok & right].reshape(-1, 3), 0)
        gains[k] = np.clip(a / np.maximum(b, 1), 0.6, 1.4)
        print('  zone', k, np.round(gains[k], 3))
    # 羽化的分区权重（墙上按高度，墙纸 / 护墙板之间的木线 68..80 用两者平均）
    def ramp(x, a, b): return np.clip((x - a) / (b - a), 0, 1)
    wp = ne * ramp(z, 70, 78)
    ww = ne * (1 - ramp(z, 70, 78))
    wf = (~ne).astype(np.float32)
    gain = wp[..., None] * gains['paper'] + ww[..., None] * gains['wains'] + wf[..., None] * gains['floor']
    # 墙顶压条（z>=182）由 fix_top_edge 重画；家具多边形里只用地板亮度增益
    lum = float(np.dot(gains['floor'], [0.3, 0.59, 0.11]))
    pm = Image.new('L', (A.shape[1], A.shape[0]), 0)
    for poly in PROTECT: D.Draw(pm).polygon(poly, fill=255)
    # 只护家具本身：护墙板木线 / 墙纸带（z>=66）照常调色，不然家具外围留一圈没调色的亮边
    pm = (np.asarray(pm) > 0) & ~(ne & (z >= 66))
    pm = cv2.GaussianBlur(pm.astype(np.float32), (0, 0), 1)[..., None]
    gain = gain * (1 - pm) + lum * pm
    return np.clip(Bf * gain, 0, 255)

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
        Bm = np.dstack([match_zones(A, Bm, g, col, masks), Bm[..., 3:]])
        wgt = np.clip((col - SEAM0) / (SEAM1 - SEAM0), 0, 1)[..., None]
        wgt = wgt * wgt * (3 - 2 * wgt)
        rgb = A[..., :3] * (1 - wgt) + Bm[..., :3] * wgt
        rgb = fix_front_edge(rgb, g, col)
        if v == 'full':
            rgb = fix_top_edge(rgb, g, col)
            rgb = fix_rail(rgb, g, col, masks)
        sil = pl.silhouette_mask(g, 2, cut=False)
        alpha = sil.copy()
        if v == 'cut':
            alpha = pl.cut_alpha(rgb, g, 2, full_canon)
        else:
            full_canon = rgb.copy()
        out = np.dstack([np.clip(rgb, 0, 255).astype(np.uint8), (alpha * 255).astype(np.uint8)])
        Image.fromarray(out, 'RGBA').save(f'{WORK}/{mid}-day-{v}-stitched.png')
        print(v, 'ok')

if __name__ == '__main__':
    {'pair': stage_pair}[sys.argv[1]](sys.argv[2], 2, *sys.argv[3:])
