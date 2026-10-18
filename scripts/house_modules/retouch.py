"""规范图（s=2）的局部修图：LaMa 补背景 + 搬家具。离线一次，产物 src/<id>-day-{full,cut}-canon.png 提交进仓库，
build.py 直接用（build 本身不依赖 torch）。

- living：输入 extend.py 拼好的 $HOUSE_WORK/living-day-{full,cut}-stitched.png。
  1) 接缝带（NE 墙 col 0.85~0.95）用 LaMa 重画，墙纸花纹连续；
  2) 电视柜从 NE 墙根搬到右格中间（Δ = 往前 0.35 格），原位置 LaMa 补墙 / 地板，新位置补接地阴影。
     composed 布局里客厅 NE 墙是切墙，电视贴墙会像站在和卧室 / 书房的分界线上。
- study：书架靠 NW 墙（常是和卧室共享的切墙），2 m 高的书架会高出切墙、像插进隔壁房间。
  改成矮书柜：去掉中间两层，顶板下移，空出来的墙面 LaMa 补。

用法（需要 torch + big-lama.pt，见 docs/HOUSE_MODULES.md）：
  HOUSE_WORK=/tmp/house-work LAMA=/path/big-lama.pt python3 retouch.py living|study
"""
import os, sys, json, numpy as np, cv2, torch
from pathlib import Path
from PIL import Image, ImageDraw
sys.path.insert(0, str(Path(__file__).resolve().parent))
from geom import *
import pipeline as pl

RAW = Path(os.environ.get('HOUSE_RAW', Path(__file__).resolve().parents[2] / 'assets/house/modules/src'))
WORK = Path(os.environ.get('HOUSE_WORK', '/tmp/house-work'))
_m = None

def inpaint(rgb, mask):
    global _m
    if _m is None:
        _m = torch.jit.load(os.environ.get('LAMA', 'big-lama.pt'), map_location='cpu'); _m.eval()
    h, w = mask.shape
    H, W_ = (h + 7) // 8 * 8, (w + 7) // 8 * 8
    im = np.pad(rgb[..., :3], ((0, H - h), (0, W_ - w), (0, 0)), mode='reflect').astype(np.float32) / 255
    mk = np.pad(mask.astype(np.float32), ((0, H - h), (0, W_ - w)))
    with torch.no_grad():
        out = _m(torch.from_numpy(im).permute(2, 0, 1)[None], torch.from_numpy(mk)[None, None])
    out = out[0].permute(1, 2, 0).numpy()[:h, :w]
    out = np.clip(out * 255 if out.max() <= 1.5 else out, 0, 255).astype(np.uint8)
    res = rgb[..., :3].copy(); res[mask] = out[mask]
    return res

def poly_mask(shape, pts, grow=0):
    m = Image.new('L', (shape[1], shape[0]), 0); ImageDraw.Draw(m).polygon([tuple(p) for p in pts], fill=255)
    m = np.asarray(m) > 0
    if grow: m = cv2.dilate(m.astype(np.uint8), np.ones((2 * grow + 1, 2 * grow + 1), np.uint8)) > 0
    return m

def col_z(g, shape, s=2):
    h, w = shape
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    T, R, L = [np.array(p, np.float32) * s for p in (g['T'], g['R'], g['L'])]
    colw = (xs - T[0]) / (W / 2 * s)
    edge = np.where(xs < T[0], T[1] + (xs - T[0]) * (L[1] - T[1]) / (L[0] - T[0]),
                    T[1] + (xs - T[0]) * (R[1] - T[1]) / (R[0] - T[0]))
    return colw, edge - ys

def object_mask(orig, bg, region, thr=34):
    """region 里和 LaMa 背景差别明显的像素 = 家具本体（去噪、补洞）"""
    d = np.abs(orig[..., :3].astype(np.int32) - bg.astype(np.int32)).sum(-1)
    lum = orig[..., :3].astype(np.float32).mean(-1)
    m = (d > thr) & region & (lum < 115)   # 家具都偏暗；亮的是墙纸（拼接调色留下的亮边），不算本体
    m = cv2.morphologyEx(m.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(m)
    keep = np.zeros_like(m, bool)
    for i in range(1, n):
        if st[i, cv2.CC_STAT_AREA] > 400: keep |= lab == i
    # 补洞（屏幕里的暗块和背景差别小时会漏）
    ff = keep.astype(np.uint8).copy(); hh, ww = ff.shape
    cv2.floodFill(ff, np.zeros((hh + 2, ww + 2), np.uint8), (0, 0), 2)
    m = keep | (ff == 0)
    # 外缘亮像素（旧墙纸的抗锯齿边）剥掉两圈
    for _ in range(2):
        edge = m & (cv2.dilate((~m).astype(np.uint8), np.ones((3, 3), np.uint8)) > 0) & (lum > 95)
        m &= ~edge
    return m

def hole_alpha(alpha, hole, g, rgb=None, depth=10):
    """剖面版里搬走家具后的 alpha：洞里按旁边切墙的实际墙顶高度补墙，墙顶以上透明。
    直接用规范剪影（正好 CUT_H）会和生成图实际画的墙顶差几个像素，出台阶。
    墙顶高度取洞左右各 40 列的中位数里较低的那个（靠墙角的列会混进另一面墙）。
    给了 rgb 时，顺便用旁边墙顶下 depth 像素的“离墙顶距离 → 颜色”剖面重画洞里的墙顶压条。"""
    _, z = col_z(g, alpha.shape)
    masks = pl.region_masks(g, 2)
    wall = masks['nw'] | masks['ne']
    h, w = alpha.shape
    cols = np.nonzero(hole.any(0))[0]
    x0, x1 = cols.min(), cols.max()
    def tops(xs):
        v = []
        for x in xs:
            if 0 <= x < w:
                m = alpha[:, x] & wall[:, x]
                if m.any(): v.append(z[m, x].max())
        return v
    L, R = tops(range(x0 - 40, x0)), tops(range(x1 + 1, x1 + 41))
    t = min([np.median(v) for v in (L, R) if v] or [CUT_H * 2])
    sil = pl.silhouette_mask(g, 2, cut=True)
    out = alpha.copy()
    out[hole] = (sil & ((z <= t) | ~wall))[hole]
    if rgb is not None:
        ref = [x for x in range(x0 - 40, x0) if 0 <= x < w] or [x for x in range(x1 + 1, x1 + 41) if x < w]
        prof = {}
        for d in range(depth):
            px = [rgb[int(np.argmin(np.abs(z[:, x] - (t - d)) + 1e6 * ~wall[:, x])), x] for x in ref]
            prof[d] = np.median(np.array(px), 0)
        for x in cols:
            for d in range(depth):
                ys = np.nonzero(hole[:, x] & wall[:, x] & (np.abs(z[:, x] - (t - d)) < 0.5))[0]
                rgb[ys, x] = prof[d]
    return out

def shift(a, dx, dy):
    out = np.zeros_like(a)
    h, w = a.shape[:2]
    ys0, ys1 = max(0, dy), min(h, h + dy); xs0, xs1 = max(0, dx), min(w, w + dx)
    out[ys0:ys1, xs0:xs1] = a[ys0 - dy:ys1 - dy, xs0 - dx:xs1 - dx]
    return out

def save(rgb, alpha, name):
    Image.fromarray(np.dstack([rgb.astype(np.uint8), (alpha > 0).astype(np.uint8) * 255]), 'RGBA').save(RAW / name)
    print('wrote', RAW / name)

# ---------------- living ----------------
TV = [(735, 294), (752, 294), (849, 336), (849, 420), (865, 428), (865, 477), (822, 501), (806, 501), (707, 449), (707, 392), (733, 380)]
TV_TIGHT = [(737, 297), (745, 296), (846, 337), (846, 424), (862, 429), (862, 472), (822, 497), (808, 497), (710, 446), (710, 394), (737, 383)]
TV_FOOT = [(711, 444), (812, 497), (860, 472), (762, 420)]   # 电视柜底面（地板上）
TV_D = (-112, 46)                                            # 往前 0.35 格（v 方向，s=2）

def living():
    g = module_geom(2)
    F = np.asarray(Image.open(WORK / 'living-day-full-stitched.png').convert('RGBA'))
    C = np.asarray(Image.open(WORK / 'living-day-cut-stitched.png').convert('RGBA'))
    colw, z = col_z(g, F.shape[:2])
    masks = pl.region_masks(g, 2)
    tv = poly_mask(F.shape, TV, grow=5)
    out = {}
    for v, A in (('full', F), ('cut', C)):
        rgb = A[..., :3].copy(); alpha = A[..., 3] > 0
        top = 182 if v == 'full' else CUT_H * 2 - 6
        seam = masks['ne'] & (colw > 0.85) & (colw < 0.96) & (z > 3) & (z < top)
        rgb = inpaint(rgb, seam)
        hole = tv & ((z < CUT_H * 2 + 6) | (v == 'full'))
        bg = inpaint(rgb, hole)
        if v == 'full':
            obj = object_mask(F, bg, poly_mask(F.shape, TV_TIGHT, grow=1))
            # 屏幕边框是深灰：上半截（电视本体）外缘再剥三圈偏亮的抗锯齿点
            lumF = F[..., :3].astype(np.float32).mean(-1)
            for _ in range(3):
                e = obj & (cv2.dilate((~obj).astype(np.uint8), np.ones((3, 3), np.uint8)) > 0) & (lumF > 70)
                e[384:] = False
                obj &= ~e
            sprite = F[..., :3].copy()
        out[v] = (bg, alpha)
    # 新位置：接地阴影 + 电视
    dx, dy = TV_D
    objs = shift(obj.astype(np.uint8), dx, dy) > 0
    spr = shift(sprite, dx, dy)
    foot = poly_mask(F.shape, [(x + dx, y + dy) for x, y in TV_FOOT], grow=4).astype(np.float32)
    sh = cv2.GaussianBlur(foot, (0, 0), 5) * 0.55
    for v in ('full', 'cut'):
        bg, alpha = out[v]
        rgb = bg.astype(np.float32) * (1 - sh[..., None])
        rgb[objs] = spr[objs]
        if v == 'cut':
            # 原电视位：切墙以上透明，以下（墙 / 地板）照剖面剪影；新电视整块不透明
            alpha = hole_alpha(alpha, tv & ~objs, g, rgb) | objs
        save(np.clip(rgb, 0, 255), alpha, f'living-day-{v}-canon.png')

# ---------------- study ----------------
SHELF = [(141, 168), (250, 126), (300, 132), (302, 306), (190, 364), (141, 347)]
SHELF_SHADOW = [(100, 150), (205, 106), (255, 116), (255, 210), (150, 262), (100, 290)]   # 原书架投在墙上的影子
SHELF_BASE = (188, 358)       # 书架前下角（地面）；前面板沿 NW 墙方向、侧面板沿 NE 方向，斜率都是 ±FH/W
SHELF_Z = (56, 167)           # 删掉的 z 段（s=2）：中间三层书，顶板落到第一层上面 → 矮书柜顶 ≈ 37px（s=1），低于切墙 40

def warped(mid, g):
    """源图 → s=2 规范 RGBA（和 build.py 的 warp 一样，不做像素化），full / cut"""
    full = np.asarray(Image.open(RAW / f'{mid}-day-full.jpg').convert('RGB'))
    corners = pl.detect_corners(full)
    cj = RAW / f'{mid}-corners.json'
    if cj.exists(): corners.update(json.loads(cj.read_text()))
    out, full_canon = [], None
    for cut in (False, True):
        src = np.asarray(Image.open(RAW / f'{mid}-day-{"cut" if cut else "full"}.jpg').convert('RGB'))
        cc = pl.cut_corners(full, src, corners, g) if cut else corners
        w2 = pl.warp_to_canonical(src, cc, g, cut=cut, full_rgb=full_canon)
        if not cut: full_canon = np.asarray(w2)[..., :3]
        out.append(np.asarray(w2.convert('RGBA')))
    return out

def study():
    g = module_geom(1)
    F, C = warped('study', g)
    shelf = poly_mask(F.shape, SHELF, grow=5)
    _, z = col_z(g, F.shape[:2])
    res = {}
    for v, A in (('full', F), ('cut', C)):
        rgb = A[..., :3].copy(); alpha = A[..., 3] > 0
        hole = shelf & ((z < CUT_H * 2 + 6) | (v == 'full'))
        if v == 'full':
            hole = hole | (poly_mask(F.shape, SHELF_SHADOW) & (z > 0))
        bg = inpaint(rgb, hole)
        if v == 'full':
            obj = object_mask(F, bg, poly_mask(F.shape, SHELF, grow=1))
        res[v] = (bg, alpha)
    h, w = obj.shape
    k = FH / W
    z0, z1 = SHELF_Z; dz = z1 - z0
    bx, by = SHELF_BASE
    new = np.zeros_like(obj); px = np.zeros_like(F[..., :3])
    for x in range(w):
        if not obj[:, x].any(): continue
        yb = by - abs(x - bx) * k                    # 这一列书架底边
        ya, yc = int(round(yb - z1)), int(round(yb - z0))
        col = obj[:, x]
        # 下段原样
        lo = col.copy(); lo[:yc] = False
        new[lo, x] = True; px[lo, x] = F[lo, x, :3]
        # 上段（ya 以上）整体下移 dz
        lumc = F[:, x, :3].astype(np.float32).mean(-1)
        for y in np.nonzero(col[:ya])[0]:
            if y + dz < h and lumc[y] < 95:     # 顶板是深木色；亮的是顶板后沿漏进来的墙纸
                new[y + dz, x] = True; px[y + dz, x] = F[y, x, :3]
    for v in ('full', 'cut'):
        bg, alpha = res[v]
        o = bg.copy()
        a = alpha
        if v == 'cut':
            a = hole_alpha(alpha, shelf, g, o)
        o[new] = px[new]
        if v == 'cut':
            a = a | new
        save(o, a, f'study-day-{v}-canon.png')

if __name__ == '__main__':
    {'living': living, 'study': study}[sys.argv[1]]()
