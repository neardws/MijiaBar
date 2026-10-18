"""一次性修图：卫生间壁挂热水器、阳台洗衣机（产物已提交，不要重复运行）。

  python3 scripts/house_modules/add_appliances.py canon        # 卫生间 / 阳台源图 → 2x 规范图（和 build.py 的 warp 完全一样）
  LAMA=/path/big-lama.pt python3 scripts/house_modules/add_appliances.py paint   # 画热水器、洗衣机（之后跑 build.py）

热水器：卫生间 NW 墙、窗右侧绿植上方（u≈0 墙面，v 0.07..0.21，z 54..90），白色箱体 + 底部水管，正面圆形显示窗
（显示 / 加热火光由 App 动态画，见 fixtures.py water_heater）。墙被切（CUT_H=40）时看不见 → App 在 alt 地面点显示徽章。
洗衣机：阳台 NW 墙根，替换左侧两盆绿植（LaMa 补墙 / 地板），滚筒门 + 顶部控制面板（运行灯 / 滚筒转动由 App 动态画）。
造型按 iso 网格程序化绘制（geom 的 P(u,v,z)），在 2x 规范图上画，再走 pixelize，和其他家具同样的像素格。
"""
import os, sys, json
from pathlib import Path
import numpy as np, cv2
from PIL import Image, ImageDraw
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
from geom import *
import pipeline as pl
from fixtures import spec
MSRC = ROOT / 'assets/house/modules/src'
LAMA = os.environ.get('LAMA', 'big-lama.pt')

def canon(mid):
    fw, g, sp = spec(mid)
    full = np.asarray(Image.open(MSRC / f'{mid}-day-full.jpg').convert('RGB'))
    corners = pl.detect_corners(full)
    cj = MSRC / f'{mid}-corners.json'
    if cj.exists(): corners.update(json.loads(cj.read_text()))
    full_canon = None
    for cut in (False, True):
        v = 'cut' if cut else 'full'
        src = np.asarray(Image.open(MSRC / f'{mid}-day-{v}.jpg').convert('RGB'))
        cc = pl.cut_corners(full, src, corners, g) if cut else corners
        w2 = pl.warp_to_canonical(src, cc, g, cut=cut, full_rgb=full_canon)
        if not cut: full_canon = np.asarray(w2)[..., :3]
        w2.save(MSRC / f'{mid}-day-{v}-canon.png')

if __name__ == '__main__':
    if sys.argv[1] == 'canon':
        for m in ('bathroom', 'balcony'): canon(m)


# ---------- 程序化 iso 家电（1x 坐标里按 2px 像素格画，再 ×2 贴进 2x 规范图） ----------
TOP = np.array([210, 202, 188.]); FRONT = np.array([198, 190, 176.]); SIDE = np.array([158, 150, 140.])
LINE = np.array([72, 58, 48.])
CHROME = np.array([226, 224, 220.]); GLASS = np.array([44, 54, 66.]); DARK = np.array([58, 56, 56.])

class Box:
    """u∈[0,d]（离墙 / 离 NW 墙的深度）, v∈[v0,v1], z∈[z0,z1] 的箱体；可见面：顶、前（u=d，朝右下）、侧（v=v1，朝左下）。"""
    def __init__(s, g, d, v0, v1, z0, z1):
        s.T = g['T']; s.d, s.v0, s.v1, s.z0, s.z1 = d, v0, v1, z0, z1
    def hit(s, x, y):
        Tx, Ty = s.T; hw, hh = W / 2, FH / 2
        # 顶
        a = (x - Tx) / hw; b = (y + s.z1 - Ty) / hh
        u, v = (a + b) / 2, (b - a) / 2
        if 0 <= u <= s.d and s.v0 <= v <= s.v1: return 'top', u / s.d, (v - s.v0) / (s.v1 - s.v0)
        # 前
        v = s.d - (x - Tx) / hw; z = Ty + (s.d + v) * hh - y
        if s.v0 <= v <= s.v1 and s.z0 <= z <= s.z1: return 'front', (s.v1 - v) / (s.v1 - s.v0), (z - s.z0) / (s.z1 - s.z0)
        # 侧
        u = s.v1 + (x - Tx) / hw; z = Ty + (u + s.v1) * hh - y
        if 0 <= u <= s.d and s.z0 <= z <= s.z1: return 'side', u / s.d, (z - s.z0) / (s.z1 - s.z0)
        return None
    def bbox(s):
        P = lambda u, v, z: (s.T[0] + (u - v) * W / 2, s.T[1] + (u + v) * FH / 2 - z)
        pts = [P(u, v, z) for u in (0, s.d) for v in (s.v0, s.v1) for z in (s.z0, s.z1)]
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        return int(min(xs)) // 2 * 2 - 4, int(min(ys)) // 2 * 2 - 4, int(max(xs)) // 2 * 2 + 6, int(max(ys)) // 2 * 2 + 6
    def fw(s): return (s.v1 - s.v0) * W / 2      # 前面宽（px，沿墙）
    def fh(s): return s.z1 - s.z0

def render(box, shade_fn, extra=None):
    """返回 {(x,y) 格左上角(1x): rgb}；shade_fn(face, s, t, edge) -> rgb"""
    x0, y0, x1, y1 = box.bbox()
    cells = {}
    for y in range(y0, y1, 2):
        for x in range(x0, x1, 2):
            h = box.hit(x + 1, y + 1)
            if h: cells[(x, y)] = h
    out = {}
    for (x, y), (f, s, t) in cells.items():
        # 轮廓：上下左右有一格不在箱体里
        edge = any((x + dx, y + dy) not in cells for dx, dy in ((2, 0), (-2, 0), (0, 2), (0, -2)))
        # 面交界：邻格是另一个面
        seam = any((x + dx, y + dy) in cells and cells[(x + dx, y + dy)][0] != f for dx, dy in ((2, 0), (-2, 0), (0, 2), (0, -2)))
        out[(x, y)] = shade_fn(f, s, t, edge, seam)
    if extra: extra(out)
    return out

def base_shade(f, s, t, edge, seam):
    c = {'top': TOP, 'front': FRONT, 'side': SIDE}[f].copy()
    if f == 'front': c = c * (0.9 + 0.12 * t)                   # 前面：上亮下暗
    if f == 'side': c = c * (0.9 + 0.1 * t)
    if f == 'top': c = c * (0.97 + 0.05 * s)                     # 顶面：靠前更亮
    if seam: c = c * (1.06 if f in ('top', 'front') else 0.92)  # 棱上的高光 / 侧面背光棱
    if edge: c = LINE * 0.55 + c * 0.45
    return c

def water_heater_shade(box):
    fw, fh = box.fw(), box.fh()
    def f(face, s, t, edge, seam):
        c = base_shade(face, s, t, edge, seam)
        if face == 'front' and not edge:
            dx, dy = (s - 0.5) * fw, (t - 0.62) * fh
            r = max(abs(dx) * 1.05, abs(dy) * 0.95) * 0.7 + np.hypot(dx, dy) * 0.3   # 圆角方窗
            if r < 4.0: c = GLASS * (1.0 + 0.04 * dy)                   # 显示窗（App 动态点亮）
            elif r < 5.6: c = CHROME * (0.95 if dy > -1 else 0.76)      # 金属框
            if t < 0.1: c = c * 0.84                                    # 底盖
            if 0.86 < t < 0.92 and 0.3 < s < 0.7: c = CHROME * 0.82     # 铭牌条
            if 0.24 < t < 0.31 and 0.62 < s < 0.8: c = DARK * 1.4       # 指示灯座
            if 0.24 < t < 0.31 and 0.2 < s < 0.38: c = CHROME * 0.8     # 旋钮
        return c
    return f

def washer_shade(box):
    fw, fh = box.fw(), box.fh()
    def f(face, s, t, edge, seam):
        c = base_shade(face, s, t, edge, seam)
        if face == 'front' and not edge:
            if t > 0.8:
                c = c * 0.93                                               # 控制面板
                if t < 0.84: c = c * 0.86                                  # 面板下缝
                elif 0.56 < s < 0.86: c = GLASS                             # 显示屏（运行时亮）
                elif 0.08 < s < 0.34: c = c * 0.9                           # 洗涤剂盒
                elif 0.38 < s < 0.5: c = CHROME * 0.86                      # 旋钮
            elif t > 0.07:
                dx, dy = (s - 0.5) * fw, (t - 0.43) * fh
                r = np.hypot(dx, dy)
                if r < 5.6:
                    k = 1.0 + 0.35 * np.clip((-dx + dy) / 9, -1, 1)          # 玻璃：左上亮右下暗
                    c = GLASS * k
                    ang = np.degrees(np.arctan2(dy, dx))
                    if 2.4 < r < 4.8 and 100 < ang < 170: c = np.array([128, 150, 168.])   # 反光弧
                elif r < 6.8: c = DARK                                       # 内圈
                elif r < 9.4:
                    k = 1.0 if (dy - dx) > 0 else 0.78                       # 门圈：左上亮
                    c = CHROME * k
                    if 7.4 < r < 9.4 and dx > 6.5 and abs(dy) < 3: c = DARK * 1.6              # 门把手
            else:
                c = c * 0.8                                                  # 踢脚板
        if face == 'top' and not edge and s < 0.18: c = c * 0.92            # 顶面后沿
        return c
    return f

def paste_cells(img2x, cells, gain=1.0):
    for (x, y), c in cells.items():
        img2x[2 * y:2 * y + 4, 2 * x:2 * x + 4, :3] = np.clip(c * gain, 0, 255)

def shade_region(img2x, poly1x, k):
    m = Image.new('L', (img2x.shape[1], img2x.shape[0]), 0)
    ImageDraw.Draw(m).polygon([(2 * x, 2 * y) for x, y in poly1x], fill=255)
    m = np.asarray(m) > 0
    img2x[m, :3] = img2x[m, :3] * k

def local_gain(img2x, box1x, ref=np.array([188, 160, 120.])):
    x0, y0, x1, y1 = box1x
    m = img2x[2 * y0:2 * y1, 2 * x0:2 * x1, :3].reshape(-1, 3).astype(np.float32).mean(0)
    return float(np.clip((m / ref).mean(), 0.75, 1.15))

def inpaint(rgb, mask):
    import torch
    m = torch.jit.load(LAMA, map_location='cpu'); m.eval()
    ys, xs = np.nonzero(mask)
    y0, y1 = max(0, ys.min() - 48), min(rgb.shape[0], ys.max() + 48)
    x0, x1 = max(0, xs.min() - 48), min(rgb.shape[1], xs.max() + 48)
    y1 = y0 + (y1 - y0) // 8 * 8; x1 = x0 + (x1 - x0) // 8 * 8
    im = rgb[y0:y1, x0:x1].astype(np.float32) / 255; mk = mask[y0:y1, x0:x1].astype(np.float32)
    with torch.no_grad():
        out = m(torch.from_numpy(im).permute(2, 0, 1)[None], torch.from_numpy(mk)[None, None])[0].permute(1, 2, 0).numpy()
    out = np.clip(out * 255 if out.max() <= 1.5 else out, 0, 255).astype(np.uint8)
    res = rgb.copy(); sub = res[y0:y1, x0:x1]; sub[mk > 0] = out[mk > 0]
    return res

def heater_box(g): return Box(g, 0.06, 0.07, 0.21, 54, 90)
def washer_box(g): return Box(g, 0.16, 0.70, 0.86, 0, 34)

def paint_heater(img, g):
    b = heater_box(g)
    P = lambda u, v, z: (b.T[0] + (u - v) * W / 2, b.T[1] + (u + v) * FH / 2 - z)
    gain = local_gain(img, (150, 50, 180, 80))
    # 墙上投影（光从左上来）：箱体右下错开 3px
    sh = [P(0, b.v1 - 0.02, b.z1 - 4), P(0, b.v0 - 0.025, b.z1 - 4), P(0, b.v0 - 0.025, b.z0 - 4), P(0, b.v1 - 0.02, b.z0 - 4)]
    shade_region(img, sh, 0.78)
    # 水管：箱底两根到墙面往下 10px
    for vv in (b.v0 + 0.035, b.v1 - 0.035):
        x, y = P(0.03, vv, b.z0)
        x = int(x) // 2 * 2; y = int(y) // 2 * 2
        for k in range(0, 10, 2):
            img[2 * (y + k):2 * (y + k) + 4, 2 * x:2 * x + 4, :3] = CHROME * 0.7 * gain if k < 8 else CHROME * 0.5 * gain
    paste_cells(img, render(b, water_heater_shade(b)), gain)

def paint_washer(img, g, cut):
    b = washer_box(g)
    P = lambda u, v, z: (b.T[0] + (u - v) * W / 2, b.T[1] + (u + v) * FH / 2 - z)
    gain = local_gain(img, (40, 120, 60, 135), ref=np.array([120, 84, 56.])) if not cut else 0.92
    # 地面投影：右前方
    shade_region(img, [P(b.d, b.v1, 0), P(b.d, b.v0, 0), P(b.d + 0.07, b.v0 - 0.03, 0), P(b.d + 0.07, b.v1 - 0.01, 0)], 0.72)
    paste_cells(img, render(b, washer_shade(b)), gain * np.array([0.95, 0.93, 0.9]))

PLANTS = [(36, 140), (106, 140), (108, 186), (100, 200), (40, 200), (34, 170)]   # 阳台左侧两盆绿植（1x）

def paint():
    fw, g, sp = spec('bathroom')
    p = MSRC / 'bathroom-day-full-canon.png'
    img = np.asarray(Image.open(p).convert('RGBA')).copy()
    paint_heater(img, g)
    Image.fromarray(img).save(p)
    fw, g, sp = spec('balcony')
    for cut in (False, True):
        p = MSRC / f'balcony-day-{"cut" if cut else "full"}-canon.png'
        img = np.asarray(Image.open(p).convert('RGBA')).copy()
        m = Image.new('L', (img.shape[1], img.shape[0]), 0)
        ImageDraw.Draw(m).polygon([(2 * x, 2 * y) for x, y in PLANTS], fill=255)
        mask = (np.asarray(m) > 0) & (img[..., 3] > 0)
        img[..., :3] = inpaint(img[..., :3], mask)
        paint_washer(img, g, cut)
        Image.fromarray(img).save(p)

if __name__ == '__main__' and sys.argv[1] == 'paint':
    paint()
