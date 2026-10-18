"""窗帘关合贴片（运行时叠加，不烘焙）：每扇有窗帘的窗一张「全关」贴片 × day/night × unlit/lit。

贴片覆盖窗框 + 两侧窗帘（竖直左右边、上下沿是斜线，跟墙面透视），左右两半从外侧往中间拉；
App 按开合度只露出外侧的一部分（窗帘位置 0..100，100 = 全开 → 不画贴片，露出底图里系起来的窗帘和窗外光）。
布料：从原窗帘取 4 级色（k-means），竖褶纹 + 帘头 + 波浪底边；day/night/lit 的色偏取自底图同一位置的比值。
窗前的家具（书房显示器、绿植）用遮挡多边形扣掉，贴片不会盖住它们。

  python3 scripts/house_modules/curtains.py preview OUT_DIR     # 画框线检查
  python3 scripts/house_modules/curtains.py build [OUT_DIR]       # 写 Resources/House[/modules]/curtain-*.png，打印 json 定义
"""
import os, sys, json
sys.path.insert(0, str(__import__('pathlib').Path(__file__).resolve().parent))
from pathlib import Path
import numpy as np, cv2
from PIL import Image, ImageDraw
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RES = ROOT / 'Sources/MijiaBarApp/Resources/House'
MOD = ROOT / 'assets/house/modules'

def L(k, x): return k[0] * x + k[1]
# target -> (图像前缀, [x0, x1, top0, top1, bot0, bot1], 遮挡多边形)：x0/x1 = 左右竖边，top/bot = 两条竖边处的上下沿 y
WINDOWS = {
    'classic/bedroom': ('classic', [446, 564, L((.2126, -68.5), 446), L((.2126, -68.5), 564), L((.207, 12.3), 446), L((.207, 12.3), 564)], []),
    'classic/study':   ('classic', [696, 800, L((.2226, -75.4), 696), L((.2226, -75.4), 800), L((.31, -59.8), 696), L((.31, -59.8), 800)],
                        [[(650, 139), (700, 144), (712, 147), (721, 151), (722, 210), (650, 210)]]),   # 显示器在窗前
    'classic/living':  ('classic', [292, 390, L((.3129, 89.9), 292), L((.3129, 89.9), 390), L((.273, 180.4), 292), L((.273, 180.4), 390)], []),
    'living':  ('module-living',  [234, 296, 60.2, 85.8, 113.4, 139], []),
    'bedroom': ('module-bedroom', [258, 322, 66.2, 92.6, 112.6, 139], []),
    'study':   ('module-study',   [232, 296, 58.2, 84.6, 105.6, 132],
                [[(232, 107), (250, 107), (263, 112), (264, 145), (232, 145)], [(266, 126), (288, 126), (288, 145), (266, 145)]]),   # 显示器、绿植
    'kitchen': ('module-kitchen', [46, 106, 96.8, 72, 141.8, 117], []),
}
VARIANTS = ['day-unlit', 'day-lit', 'night-unlit', 'night-lit']

def img_path(prefix, var):
    if prefix == 'classic': return RES / f'house-cutaway-{var}.png'
    return MOD / f'{prefix}-{var}.png'

def load(prefix, var): return np.asarray(Image.open(img_path(prefix, var)).convert('RGB')).astype(np.float32) / 255

def quad_pts(q):
    x0, x1, t0, t1, b0, b1 = q
    return [(x0, t0), (x1, t1), (x1, b1), (x0, b0)]

def preview(out):
    out = Path(out); out.mkdir(parents=True, exist_ok=True)
    for name, (prefix, q, excl) in WINDOWS.items():
        a = Image.open(img_path(prefix, 'day-unlit')).convert('RGB')
        x0, x1 = int(q[0]) - 16, int(q[1]) + 16
        y0, y1 = int(min(q[2], q[3])) - 16, int(max(q[4], q[5])) + 16
        c = a.crop((x0, y0, x1, y1)).resize(((x1 - x0) * 4, (y1 - y0) * 4), Image.NEAREST)
        d = ImageDraw.Draw(c)
        for poly, col in [(quad_pts(q), (255, 0, 255))] + [(e, (0, 255, 0)) for e in excl]:
            d.polygon([((x - x0) * 4, (y - y0) * 4) for x, y in poly], outline=col)
        c.save(out / f"q-{name.replace('/', '-')}.png")

def geometry(name):
    """贴片位置（不读图）：rect = [x, y, w, h]（偶数对齐，像素格 2px），mid = 两半分界的 x，quad = 四个角。"""
    q = WINDOWS[name][1]
    x0, x1 = q[0], q[1]
    X0, X1 = int(x0) // 2 * 2, -(-int(np.ceil(x1)) // 2) * 2
    Y0 = int(min(q[2], q[3])) // 2 * 2; Y1 = -(-int(np.ceil(max(q[4], q[5]))) // 2) * 2
    r1 = lambda z: round(float(z), 1)
    return dict(patch='curtain-' + name.replace('/', '-'), rect=[X0, Y0, X1 - X0, Y1 - Y0], mid=r1((x0 + x1) / 2),
                quad=[[r1(x), r1(y)] for x, y in quad_pts(q)])

def is_sky(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    return ((b > .59) & (b > r + .12) & (b > g + .02)) | ((r > .78) & (g > .78) & (b > .78) & (b >= r))

def poly_mask(shape, polys, off):
    m = Image.new('L', (shape[1], shape[0]), 0); d = ImageDraw.Draw(m)
    for pts in polys: d.polygon([(x - off[0], y - off[1]) for x, y in pts], fill=255)
    return np.asarray(m) > 0

# 褶纹：每半边从外侧往中间数格（格 = 2px）；数字 = 色阶（0 最暗 .. 3 最亮）
FOLD = [1, 2, 3, 3, 2, 1, 0, 1, 2, 3, 2, 1]

def patch(name):
    prefix, q, excl = WINDOWS[name]
    x0, x1 = q[0], q[1]
    X0, X1 = int(x0) // 2 * 2, -(-int(np.ceil(x1)) // 2) * 2
    Y0 = int(min(q[2], q[3])) // 2 * 2; Y1 = -(-int(np.ceil(max(q[4], q[5]))) // 2) * 2
    w, h = X1 - X0, Y1 - Y0
    imgs = {v: load(prefix, v)[Y0:Y1, X0:X1] for v in VARIANTS}
    day = imgs['day-unlit']
    ys, xs = np.mgrid[0:h, 0:w]
    cx = X0 + (xs // 2) * 2 + 1.0; cy = Y0 + (ys // 2) * 2 + 1.0
    s = (cx - x0) / (x1 - x0)
    top = q[2] + (q[3] - q[2]) * s; bot = q[4] + (q[5] - q[4]) * s
    inside = (cx >= x0) & (cx <= x1) & (cy >= top) & (cy <= bot)
    if excl: inside &= ~poly_mask((h, w), excl, (X0, Y0))
    t = (cy - top) / np.maximum(1, bot - top)
    side = inside & (((cx >= x0 + 1) & (cx <= x0 + 10)) | ((cx >= x1 - 10) & (cx <= x1 - 1))) & ~is_sky(day) & (t > .15) & (t < .85)
    X = (day[side] * 255).astype(np.float32)
    crit = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 40, .5)
    cv2.setRNGSeed(7)
    _, lbl, cen = cv2.kmeans(X, 4, None, crit, 4, cv2.KMEANS_PP_CENTERS)
    cen_raw = cen.copy()
    cen = cen[np.argsort(cen @ np.array([.3, .59, .11]))] / 255
    pal = np.stack([cen[0] * .78, cen[1], cen[2], cen[3]])
    mid = (x0 + x1) / 2
    col = xs // 2
    cmid = int((mid - X0) // 2)
    left = cx < mid
    k = np.where(left, col - (int(x0) - X0) // 2, cmid * 2 - col)
    lvl = np.array(FOLD)[np.abs(k) % len(FOLD)]
    valley = lvl <= 1
    lvl[np.abs(cx - mid) < 2.5] = 1
    lvl[(cx < x0 + 2.5) | (cx > x1 - 2.5)] = 1
    trow = ((cy - top) / 2).astype(int)
    brow = ((bot - cy) / 2).astype(int)
    lsel = side & (cx < mid); rsel = side & (cx >= mid)
    def side_ratio(a, b):
        rl = a[lsel].mean(0) / np.maximum(b[lsel].mean(0), 1e-3)
        rr = a[rsel].mean(0) / np.maximum(b[rsel].mean(0), 1e-3)
        return rl[None, None] * (1 - s[..., None]) + rr[None, None] * s[..., None]
    flat = pal[lvl]
    lab = lbl.ravel()
    order = np.argsort(np.argsort(cen_raw @ np.array([.3, .59, .11])))   # k-means 标签 → 亮度级
    def level_colors(im):
        # lit：同一批侧帘像素在 lit 图里每个亮度级的平均色（左右两侧分开，按 s 插值）——直接取底图颜色，不会过曝
        px = im[side]; L = order[lab]; sl = cx[side] < mid
        def side_pal(sel):
            p = np.stack([px[sel & (L == i)].mean(0) if (sel & (L == i)).any() else px[L == i].mean(0) for i in range(4)])
            p[0] *= .78
            return p
        pl_, pr_ = side_pal(sl), side_pal(~sl)
        return pl_[lvl] * (1 - s[..., None]) + pr_[lvl] * s[..., None]
    night_flat = None
    if prefix != 'classic':
        # 模块：夜景按同一张冻结的昼→夜 LUT 映射（和 build.py 一致）；lit 直接取 lit 底图里侧帘每个亮度级的平均色
        import pipeline as pl
        night_flat = pl.apply_night(flat.astype(np.float32), pl.night_lut(None, None))
    lumw = np.array([.3, .59, .11])
    body = inside & (t > .15) & (t < .85)
    def match(rgb, im):
        # 整片帘子的平均亮度对齐同一张图里原侧帘的平均亮度（褶纹里亮级占比比原侧帘多，不对齐就像背光）
        g = float((im[side] @ lumw).mean() / max(1e-3, (rgb[body] @ lumw).mean()))
        if os.environ.get('CURTAIN_STATS'): print(name, 'gain', round(g, 3), file=sys.stderr)
        return rgb * min(1.0, g)
    out = {}
    for v in VARIANTS:
        im = imgs[v]
        phase, kind = v.split('-')
        if night_flat is not None:
            rgb = (flat if phase == 'day' else night_flat).copy()
            if kind == 'lit': rgb = level_colors(im)
        else:
            rgb = flat * side_ratio(im, day)
        rgb = match(rgb, im)
        rgb[trow == 0] *= .62
        rgb[trow == 1] *= 1.06
        rgb[brow == 0] *= .8
        a = np.zeros((h, w, 4), np.uint8)
        a[..., :3] = (np.clip(rgb, 0, 1) * 255 + .5).astype(np.uint8)
        a[..., 3] = (inside & ~(valley & (brow == 0))) * 255
        out[v] = a
    r1 = lambda z: round(float(z), 1)
    return dict(rect=[X0, Y0, w, h], mid=r1(mid), quad=[[r1(x), r1(y)] for x, y in quad_pts(q)]), out

def build(dest=None):
    defs = {}
    for name in WINDOWS:
        d, imgs = patch(name)
        prefix = WINDOWS[name][0]
        base = 'curtain-' + name.replace('/', '-')
        for v, a in imgs.items():
            if dest:
                Image.fromarray(a).save(Path(dest) / f'{base}-{v}.png')
            elif prefix == 'classic':
                Image.fromarray(a).save(RES / f'{base}-{v}.png', optimize=True)
            else:
                for D in (MOD, RES / 'modules'):
                    Image.fromarray(a).save(D / f'{base}-{v}.png', optimize=True)
        defs[name] = dict(patch=base, **d)
    print(json.dumps(defs))
    return defs

if __name__ == '__main__':
    if sys.argv[1] == 'preview': preview(sys.argv[2])
    elif sys.argv[1] == 'build': build(sys.argv[2] if len(sys.argv) > 2 else None)
