"""一次性修图：卫生间壁挂热水器、阳台洗衣机（产物已提交，不要重复运行）。

  python3 scripts/house_modules/add_appliances.py canon        # 卫生间 / 阳台源图 → 2x 规范图（和 build.py 的 warp 完全一样）
  LAMA=/path/big-lama.pt python3 scripts/house_modules/add_appliances.py paint   # 画热水器、洗衣机（之后跑 build.py）

热水器：卫生间 NW 墙、窗右侧绿植上方，横置储水式电热水器（白色搪瓷罐 + 端盖 + 挂墙带 + 圆形表盘 + 两根进出水管），
表盘 / 指示灯由 App 动态画（锚点 appliance_models.Heater.anchors）。墙被切（CUT_H=40）时看不见 → App 在 alt 地面点显示徽章。
洗衣机：阳台 NW 墙根，替换左侧两盆绿植（LaMa 补墙 / 地板），滚筒门（镀铬门圈 + 深色玻璃）+ 顶部面板（洗涤剂盒、旋钮、显示屏），
运行灯 / 滚筒转动由 App 动态画（锚点 appliance_models.Washer.anchors）。
两件都是 SDF 3D 模型（appliance_models.py），用和模块美术同一个正交相机渲染（appliance_render.py：圆角、AO、软阴影、
高光、环境反射），超采样贴进 2x 规范图，再和其他家具一样走 pixelize。
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


# ---------- 家电：SDF 3D 渲染（appliance_models / appliance_render），同一相机，贴进 2x 规范图 ----------
import appliance_render as AR, appliance_models as AM
WARM = np.array([1.03, 0.95, 0.82])     # 房间暖光：白色搪瓷在暖光下的色偏

def paint_model(img, g, model):
    bb = model.bbox(g['T'])
    rgb, a, sh = AR.render(model.scene, model.material if hasattr(model, 'material') else AM.material, g['T'], bb)
    AR.composite(img, rgb, a, sh, bb, WARM)

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

PLANTS = [(36, 140), (106, 140), (108, 186), (100, 200), (40, 200), (34, 170)]   # 阳台左侧两盆绿植（1x）

def paint():
    fw, g, sp = spec('bathroom')
    p = MSRC / 'bathroom-day-full-canon.png'
    img = np.asarray(Image.open(p).convert('RGBA')).copy()
    paint_model(img, g, AM.Heater())
    Image.fromarray(img).save(p)
    fw, g, sp = spec('balcony')
    for cut in (False, True):
        p = MSRC / f'balcony-day-{"cut" if cut else "full"}-canon.png'
        img = np.asarray(Image.open(p).convert('RGBA')).copy()
        m = Image.new('L', (img.shape[1], img.shape[0]), 0)
        ImageDraw.Draw(m).polygon([(2 * x, 2 * y) for x, y in PLANTS], fill=255)
        mask = (np.asarray(m) > 0) & (img[..., 3] > 0)
        img[..., :3] = inpaint(img[..., :3], mask)
        paint_model(img, g, AM.Washer())
        Image.fromarray(img).save(p)

if __name__ == '__main__' and sys.argv[1] == 'paint':
    paint()
