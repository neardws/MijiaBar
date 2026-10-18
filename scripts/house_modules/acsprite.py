"""壁挂空调：抠图精灵（从现有美术里的空调抠出来，可缩短 / 水平翻转 / 按目标墙面亮度调色后贴到别的墙上）+ 开机送风。

用在 add_ac.py（一次性修图，产物已提交）和 pipeline.paint_ac（每次 build 烘焙 lit 里的指示灯）。"""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

POLY = [(287, 49), (300, 44), (330, 36), (352, 33), (361, 34), (362, 63), (340, 70), (312, 81), (300, 86), (286, 86)]
BOX = (284, 30, 364, 88)

def lab(rgb):
    import cv2  # 只有抠图要 cv2
    return cv2.cvtColor(rgb.astype(np.uint8), cv2.COLOR_RGB2LAB).astype(np.float32)

def extract(img: np.ndarray, poly=POLY, box=BOX):
    """img: HxWx3 uint8。返回 (sprite RGBA uint8, wall_ref RGB mean)。"""
    h, w, _ = img.shape
    m = Image.new('L', (w, h), 0); ImageDraw.Draw(m).polygon(poly, fill=255)
    inside = np.asarray(m) > 0
    ring = np.asarray(Image.fromarray(inside.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(9))) > 0
    ring &= ~inside
    ys, xs = np.mgrid[0:h, 0:w]
    ring &= (ys > 40)   # 不要上沿木线
    L = lab(img)
    ref = np.median(L[ring], 0)
    d = np.sqrt((((L - ref) * np.array([0.6, 1.4, 1.4])) ** 2).sum(-1))
    a = (d > 14) & inside
    # 闭运算补洞，再收一圈软边（像素画：硬 alpha）
    ai = Image.fromarray(a.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
    a = (np.asarray(ai) > 0) & inside
    x0, y0, x1, y1 = box
    spr = np.zeros((y1 - y0, x1 - x0, 4), np.uint8)
    spr[..., :3] = img[y0:y1, x0:x1]
    spr[..., 3] = a[y0:y1, x0:x1] * 255
    wall = img[ring].astype(np.float32).mean(0)
    return spr, wall

last_sh = {}

def shorten(spr, n, slope=0.27, at=None):
    """删掉中间 n 列；右半段整体上移 round(slope*n)（机身是斜的长条）。"""
    if n <= 0: return spr
    h, w, _ = spr.shape
    c = at if at is not None else w // 2
    left, right = spr[:, :c], spr[:, c + n:]
    # 右半段往左挪 n 列 → 沿机身斜率往下 sh 行；sh 在斜率附近搜索，使接缝两侧列最吻合
    def cost(k):
        a = spr[:, c - 1].astype(np.float32); b = np.concatenate([np.zeros((k, 4)), spr[:h - k, c + n]], 0).astype(np.float32)
        return np.abs(a - b).sum()
    sh = min(range(max(0, int(slope * n) - 3), int(slope * n) + 4), key=cost)
    last_sh[n] = sh
    right = np.concatenate([np.zeros((sh, right.shape[1], 4), np.uint8), right[:right.shape[0] - sh]], 0)
    return np.concatenate([left, right], 1)

def place(dst: np.ndarray, spr: np.ndarray, x, y, flip=False, gain=None):
    """把精灵 alpha 合成进 dst（float 0..1 或 uint8 都行，原地）。返回贴图区域 mask（与 dst 同大小）。"""
    s = spr[:, ::-1] if flip else spr
    h, w, _ = s.shape
    rgb = s[..., :3].astype(np.float32) / 255
    if gain is not None: rgb = np.clip(rgb * gain, 0, 1)
    a = (s[..., 3:] > 127).astype(np.float32)
    region = dst[y:y + h, x:x + w]
    scale = 255.0 if dst.dtype == np.uint8 else 1.0
    out = region.astype(np.float32) / scale * (1 - a) + rgb * a
    dst[y:y + h, x:x + w] = (out * scale + (0.5 if scale > 1 else 0)).astype(dst.dtype)
    mask = np.zeros(dst.shape[:2], bool); mask[y:y + h, x:x + w] = a[..., 0] > 0
    return mask


# ---------- 开机：指示灯（烘焙进 lit）；送风在 App 里动态画（HouseAirflow），不烘焙 ----------
def paint_led(img, led):
    lx, ly = led
    img[ly:ly + PX, lx:lx + PX] = [0.45, 1.0, 0.75]


# 预览用：和 App 里 HouseAirflow 大致一样的一帧送风（不进素材）
PX = 2
def paint_airflow(img, vent, led, sx, phase, seed=7):
    """img float HxWx3 原地；vent=[[x0,y0],[x1,y1]] 出风口下沿；sx=+1 往右下飘（NW 墙），-1 往左下（NE 墙）。"""
    (x0, y0), (x1, y1) = vent
    rng = np.random.default_rng(seed)
    col = np.array([0.70, 0.92, 1.0])
    h, w, _ = img.shape
    def dot(x, y, a):
        x = int(x) // PX * PX; y = int(y) // PX * PX
        if 0 <= x < w - PX and 0 <= y < h - PX:
            img[y:y + PX, x:x + PX] = img[y:y + PX, x:x + PX] * (1 - a) + col * a
    peak = 0.85 if phase == 'night' else 0.7
    n = 4
    for i in range(n):                     # 风线
        t = (i + 0.5) / n
        bx, by = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
        L = 9 + int(rng.integers(0, 3))
        ph = rng.random() * 6.28
        for k in range(1, L):
            if k % 3 == 2: continue        # 虚线感
            x = bx + sx * (k * 2.2) + np.sin(ph + k * 0.7) * 1.5
            y = by + k * 2.6
            dot(x, y, peak * (1 - k / L) + 0.1)
    for i in range(22):                    # 粒子
        t = rng.random(); k = rng.integers(2, 9)
        bx, by = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
        dot(bx + sx * k * 2.4 + rng.integers(-2, 3), by + k * 3 + rng.integers(-2, 3), 0.6 - k * 0.05)
    lx, ly = led
    img[ly:ly + PX, lx:lx + PX] = [0.45, 1.0, 0.75]
