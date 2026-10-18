"""一次性修图：给没有空调位的模块画上壁挂空调（产物已提交，不要重复运行——会再贴一台）。

  LAMA=/path/big-lama.pt python3 scripts/house_modules/add_ac.py classic   # 经典整图：客厅、书房
  python3 scripts/house_modules/add_ac.py modules                         # Phase 2 模块：客厅、书房（之后跑 build.py）

经典整图：客厅空调替换 NW 墙上的大幅油画（LaMa 补墙），书房在 NE 墙窗左侧；改 assets/house/house-cutaway-{day,night}-base.png，
再增量更新 Resources 里的 unlit / lit（unlit 按 gen-house-baked-lighting 的公式重算；lit 用旧 lit/旧 unlit 的光场比值保留原有灯光，
再只叠加新空调的冷光和指示灯；送风由 App 动态画——gen-house-baked-lighting 现在重跑和仓库里的 lit 对不上，所以不整张重烘）。
模块：空调本体取自卧室模块（卧室源图按 build.py 同样的 warp 得到 2x 规范图），客厅原位平移（三个模块 tip 相同），
书房绕 tip 竖线镜像到 NE 墙（P(0,v,z) ↔ P(u=v,0,z)），缩短后沿墙挪到窗右侧。灯具位定义在 fixtures.py（ac_nw / ac_ne）。
"""
import os, sys, json, importlib.util, numpy as np, cv2
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import acsprite as A
from acsprite import paint_led
from geom import *
import pipeline as pl
from fixtures import spec, P
RES = ROOT / 'Sources/MijiaBarApp/Resources/House'
SRC = {p: ROOT / f'assets/house/house-cutaway-{p}-base.png' for p in ('day', 'night')}
LAMA = os.environ.get('LAMA', 'big-lama.pt')
_s = importlib.util.spec_from_file_location('bake', ROOT / 'scripts/gen-house-baked-lighting.py'); B = importlib.util.module_from_spec(_s); _s.loader.exec_module(B)

# 放置：(x, y) = 精灵包围盒左上角；n = 缩短列数；flip = NE 墙
SLOTS = {
    'living': dict(x=54, y=209, n=12, flip=False, gainbox=(56, 236, 76, 262)),
    'study': dict(x=623, y=50, n=20, flip=True, gainbox=(630, 85, 680, 120)),
}
PAINTING = [(78, 236), (132, 218), (135, 276), (80, 294)]   # 客厅大幅油画（被空调替换）

def inpaint(rgb, mask):
    import torch
    m = torch.jit.load(LAMA, map_location='cpu'); m.eval()
    y0, y1 = max(0, np.nonzero(mask)[0].min() - 48), np.nonzero(mask)[0].max() + 48
    x0, x1 = max(0, np.nonzero(mask)[1].min() - 48), np.nonzero(mask)[1].max() + 48
    y1 = y0 + (y1 - y0 + 7) // 8 * 8; x1 = x0 + (x1 - x0 + 7) // 8 * 8
    im = rgb[y0:y1, x0:x1].astype(np.float32) / 255; mk = mask[y0:y1, x0:x1].astype(np.float32)
    with torch.no_grad():
        out = m(torch.from_numpy(im).permute(2, 0, 1)[None], torch.from_numpy(mk)[None, None])[0].permute(1, 2, 0).numpy()
    out = np.clip(out * 255 if out.max() <= 1.5 else out, 0, 255).astype(np.uint8)
    res = rgb.copy(); sub = res[y0:y1, x0:x1]; sub[mk > 0] = out[mk > 0]
    # 像素格：2x2 取左上（底图是半分辨率 NEAREST 放大）
    blk = res[y0:y1, x0:x1][::2, ::2].repeat(2, 0).repeat(2, 1)[:y1 - y0, :x1 - x0]
    sub[mk > 0] = blk[mk > 0]
    return res

def map_pt(p, slot, w):
    """精灵源坐标（经典图卧室空调处）→ 目标坐标"""
    x, y = p[0] - A.BOX[0], p[1] - A.BOX[1]
    c, n = w // 2, slot['n']
    if x >= c + n: x -= n; y += A.last_sh.get(n, int(round(0.27 * n)))
    ww = w - n
    if slot['flip']: x = ww - 1 - x
    return [slot['x'] + x, slot['y'] + y]

def light_def(slot, w):
    m = lambda p: map_pt(p, slot, w)
    vent = [m((301, 80)), m((359, 58))]
    if slot['flip']: vent = vent[::-1]
    led = m((352, 62))
    xs = [v[0] for v in vent]; ys = [v[1] for v in vent]
    cx, cy = (xs[0] + xs[1]) // 2, (ys[0] + ys[1]) // 2
    return {"id": "ac", "kind": "ac", "role": "ac", "slot": 0, "vent": vent, "led": led,
            "core": [m((287, 49)), m((361, 34)), m((362, 63)), m((300, 86)), m((286, 86))],
            "reveal": [cx + (8 if not slot['flip'] else -8), cy + 14, 62, 44], "flow": 1 if not slot['flip'] else -1}

def classic():
    day = np.asarray(Image.open(SRC['day']).convert('RGB')).copy()
    spr_d, wall_d = A.extract(day)
    nb = np.asarray(Image.open(SRC['night']).convert('RGB')).copy()
    spr_n, wall_n = A.extract(nb)
    spr_n[..., 3] = spr_d[..., 3]   # 夜景用白天的抠图形状（夜景底图暗，阈值会吃进墙上的暗斑）
    scene = json.loads((RES / 'house-cutaway.json').read_text())
    w = spr_d.shape[1]
    new = {}
    for phase, base, spr, wall in (('day', day, spr_d, wall_d), ('night', nb, spr_n, wall_n)):
        from PIL import ImageDraw
        mi = Image.new('L', (base.shape[1], base.shape[0]), 0); ImageDraw.Draw(mi).polygon(PAINTING, fill=255)
        mask = np.asarray(mi) > 0
        import cv2
        mask = cv2.dilate(mask.astype(np.uint8), np.ones((7, 7), np.uint8)) > 0
        if phase == 'day':
            base = inpaint(base, mask); day_filled = base.copy()
        else:
            # 夜景不单独 LaMa（会补出暗斑）：用白天补好的墙纸 × 周围一圈的夜/昼色比
            ring = (cv2.dilate(mask.astype(np.uint8), np.ones((15, 15), np.uint8)) > 0) & ~mask
            k = base[ring].astype(np.float32).mean(0) / np.maximum(1, day[ring].astype(np.float32).mean(0))
            base = base.copy(); base[mask] = np.clip(day_filled[mask].astype(np.float32) * k, 0, 255).astype(np.uint8)
        for mod, slot in SLOTS.items():
            x0, y0, x1, y1 = slot['gainbox']
            g = base[y0:y1, x0:x1].reshape(-1, 3).astype(np.float32).mean(0) / wall
            g = np.clip(g.mean() * 0.6 + g * 0.4, 0.5, 1.5)
            s = A.shorten(spr, slot['n'])
            A.place(base, s, slot['x'], slot['y'], flip=slot['flip'], gain=g)
        new[phase] = base
        Image.fromarray(base).save(SRC[phase])
    for mod, slot in SLOTS.items():
        L = light_def(slot, w)
        lights = [l for l in scene['modules'][mod]['lights'] if l['id'] != 'ac'] + [L]
        scene['modules'][mod]['lights'] = lights
    # house-cutaway.json 是手排的紧凑格式：这里只打印新灯具，手工贴进去（已贴好）
    for mod in SLOTS: print(mod, json.dumps(next(l for l in scene['modules'][mod]['lights'] if l['id'] == 'ac')))
    for phase in ('day', 'night'):
        b = new[phase].astype(np.float32) / 255
        unlit = np.clip(b * np.array([0.80, 0.82, 0.92]) + np.array([0.0, 0.004, 0.018]), 0, 1) if phase == 'night' else b
        old_u = np.asarray(Image.open(RES / f'house-cutaway-{phase}-unlit.png').convert('RGB')).astype(np.float32) / 255
        old_l = np.asarray(Image.open(RES / f'house-cutaway-{phase}-lit.png').convert('RGB')).astype(np.float32) / 255
        changed = np.abs(np.round(unlit * 255) - np.round(old_u * 255)).max(-1) > 0
        import cv2 as _cv
        bl = lambda a: _cv.GaussianBlur(a, (0, 0), 3)
        ratio = np.clip((bl(old_l) + 0.01) / (bl(old_u) + 0.01), 0.2, 6)   # 只取光场，不取纹理（不然旧油画的高光会留下来）
        lit = old_l.copy()
        lit[changed] = np.clip(unlit * ratio, 0, 1)[changed]
        h, wd, _ = lit.shape
        X, Y = B.grid(wd, h)
        for mod in SLOTS:
            L = next(l for l in scene['modules'][mod]['lights'] if l['id'] == 'ac')
            room = B.poly_mask((wd, h), scene['modules'][mod]['region'], feather=1.0)
            f = B.band(np.clip(B.light_field(L, X, Y), 0, 1), 7) * room * B.reveal_mask(L, (wd, h))
            gg = 0.9 if phase == 'night' else 0.35
            lit = lit * (1 + f[..., None] * gg * B.COOL) + (f ** 2)[..., None] * B.COOL * (0.38 if phase == 'night' else 0.12)
            lit = np.clip(lit, 0, 1)
            paint_led(lit, L['led'])
        # 卧室空调：旧版 bake 把送风点烘焙进了 lit（床头灯一开，空调关着也露出来）。去掉高频的点、保留光场，再补指示灯
        bed = next(l for l in scene['modules']['bedroom']['lights'] if l['id'] == 'ac')
        reg = np.zeros(lit.shape[:2], bool); reg[56:106, 292:362] = True
        reg &= B.poly_mask((wd, h), next(l for l in scene['modules']['bedroom']['lights'] if l['id'] == 'bedside')['shade']) < 0.01
        smooth = np.clip(unlit * np.clip((bl(lit) + 0.01) / (bl(unlit) + 0.01), 0.2, 6), 0, 1)
        lit[reg] = smooth[reg]
        paint_led(lit, bed['led'])
        to = lambda a: Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGB')
        to(unlit).save(RES / f'house-cutaway-{phase}-unlit.png', optimize=True)
        to(lit).save(RES / f'house-cutaway-{phase}-lit.png', optimize=True)
        print(phase, 'changed px', int(changed.sum()))


# ---------- Phase 2 模块 ----------
MSRC = ROOT / 'assets/house/modules/src'

def bedroom_canon():
    fw, g, sp = spec('bedroom')
    full = np.asarray(Image.open(MSRC / 'bedroom-day-full.jpg').convert('RGB'))
    corners = pl.detect_corners(full)
    cj = MSRC / 'bedroom-corners.json'
    if cj.exists(): corners.update(json.loads(cj.read_text()))
    return np.asarray(pl.warp_to_canonical(full, corners, g, cut=False))[..., :3].copy(), sp

def extract2x(img, poly, ring_ok):
    h, w, _ = img.shape
    m = Image.new('L', (w, h), 0); ImageDraw.Draw(m).polygon(poly, fill=255); inside = np.asarray(m) > 0
    ring = (cv2.dilate(inside.astype(np.uint8), np.ones((17, 17), np.uint8)) > 0) & ~inside & ring_ok
    L = A.lab(img); ref = np.median(L[ring], 0)
    d = np.sqrt((((L - ref) * np.array([0.6, 1.4, 1.4])) ** 2).sum(-1))
    a = (d > 14) & inside
    a = cv2.morphologyEx(a.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8)) > 0
    a = cv2.morphologyEx(a.astype(np.uint8), cv2.MORPH_OPEN, np.ones((3, 3), np.uint8)) > 0
    a &= inside
    ys, xs = np.nonzero(inside); box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    x0, y0, x1, y1 = box
    spr = np.zeros((y1 - y0, x1 - x0, 4), np.uint8); spr[..., :3] = img[y0:y1, x0:x1]; spr[..., 3] = a[y0:y1, x0:x1] * 255
    return spr, img[ring].astype(np.float32).mean(0), box

def modules():
    bed, sp = bedroom_canon()
    core = [p for p in sp['lights'] if p['id'] == 'ac'][0]
    # 1x 包围多边形（含下方投影）×2
    poly1 = [(84, 69), (134, 55), (149, 52), (149, 88), (126, 98), (104, 104), (84, 103)]
    poly = [(x * 2, y * 2) for x, y in poly1]
    hh, ww, _ = bed.shape
    ys, xs = np.mgrid[0:hh, 0:ww]
    spr, wall, box = extract2x(bed, poly, ring_ok=(ys > 2 * 70) | (xs > 2 * 150))
    out = {}
    # 客厅：原位
    liv = np.asarray(Image.open(MSRC / 'living-day-full-canon.png').convert('RGBA')).copy()
    g = gain(liv[..., :3], (2 * 70, 2 * 92, 2 * 110, 2 * 104), wall)
    A.place(liv[..., :3], spr, box[0], box[1], gain=g)
    Image.fromarray(liv).save(MSRC / 'living-day-full-canon.png')
    # 书房：镜像到 NE 墙 + 缩短 + 沿墙平移
    stu = np.asarray(Image.open(MSRC / 'study-day-full-canon.png').convert('RGBA')).copy()
    n = NCUT
    s2 = A.shorten(spr, n, slope=SLOPE2)
    sh = A.last_sh[n]
    Tx2 = 2 * 186
    # 源包围盒 [box0, box0+w) 镜像：x' = 2*Tx2 - 1 - x
    w2 = s2.shape[1]
    mx0 = 2 * Tx2 - (box[0] + w2)   # 镜像后左边
    du = DU   # 沿 NE 墙平移（格）
    dx, dy = round(du * W / 2 * 2), round(du * FH / 2 * 2)
    g2 = gain(stu[..., :3], (2 * 300, 2 * 100, 2 * 336, 2 * 125), wall)
    A.place(stu[..., :3], s2, mx0 + dx, box[1] + dy, flip=True, gain=g2)
    Image.fromarray(stu).save(MSRC / 'study-day-full-canon.png')
    # 灯具点变换（1x）
    def tf(p):
        x2, y2 = p[0] * 2, p[1] * 2
        lx = x2 - box[0]
        c = spr.shape[1] // 2
        if lx >= c + n: x2 -= n; y2 += sh
        x2 = 2 * Tx2 - 1 - x2 + 0   # 镜像（以缩短后的图为准：右段已左移）
        x2 += (spr.shape[1] - w2) * 0
        return [round((x2 + dx) / 2), round((y2 + dy) / 2)]
    print('shorten sh', sh, 'mirror x0', mx0, 'dx dy', dx, dy)
    for k in ('vent', 'led', 'core', 'anchor', 'alt'):
        v = core[k]
        print(k, v, '->', [tf(p) for p in v] if isinstance(v[0], list) else tf(v))

def gain(img, box, wall):
    x0, y0, x1, y1 = box
    m = img[y0:y1, x0:x1].reshape(-1, 3).astype(np.float32).mean(0)
    g = m / wall
    return np.clip(g.mean() * 0.6 + g * 0.4, 0.5, 1.6)

NCUT, DU, SLOPE2 = 28, 0.33, 0.25   # 书房：缩短 28 列（2x），沿 NE 墙挪 0.33 格到窗右侧

if __name__ == '__main__':
    {'classic': classic, 'modules': modules}[sys.argv[1]]()
