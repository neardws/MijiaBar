"""Composite encoded cat frames into a module image for previews (mirrors the Swift renderer)."""
import json, numpy as np
from PIL import Image
from golden import recolor_px
def frame_img(sheet, rig, idx, pal, light, mirror=False):
    W, H = rig['frameSize']; c = rig['columns']; r_, c_ = divmod(idx, c)
    enc = sheet[r_ * H:(r_ + 1) * H, c_ * W:(c_ + 1) * W]
    rgba = recolor_px(enc, pal, light)
    im = Image.fromarray((rgba * 255 + .5).astype(np.uint8), 'RGBA')
    if mirror: im = im.transpose(Image.FLIP_LEFT_RIGHT)
    k = rig['cellPx']
    return im.resize((W * k, H * k), Image.NEAREST)
def place(base, im, rig, x, y, mirror=False):
    k = rig['cellPx']; ax, ay = rig['anchor']; W = rig['frameSize'][0]
    if mirror: ax = W - ax
    base.alpha_composite(im, (int(round(x - ax * k)), int(round(y - ay * k))))
