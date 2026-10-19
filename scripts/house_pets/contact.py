"""Contact sheet from exported rig: python3 contact.py RIGDIR out.png pattern pal [lighting] [zoom]"""
import sys, json, numpy as np
from PIL import Image, ImageDraw, ImageFont
from place import frame_img
from view import PALS
d, out, pat, pal = sys.argv[1:5]
ln = sys.argv[5] if len(sys.argv) > 5 else 'day'; Z = int(sys.argv[6]) if len(sys.argv) > 6 else 3
rig = json.load(open(f'{d}/cat-short.json')); sheet = np.asarray(Image.open(f'{d}/{rig["sheets"][pat]}').convert('RGBA'))
W, H = rig['frameSize']; k = rig['cellPx']; fw, fh = W * k * Z, H * k * Z
acts = list(rig['actions']); ncol = max(len(a['frames']['SE']) for a in rig['actions'].values())
font = ImageFont.truetype('/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf', 14 * Z // 3 + 6)
lab = 120
S = Image.new('RGBA', (lab + 2 * ncol * fw + 40, len(acts) * fh + 40), (205, 178, 140, 255) if ln == 'day' else (40, 36, 44, 255))
dr = ImageDraw.Draw(S)
dr.text((lab + 10, 6), f'SE (→SW mirrored)', fill=(30, 20, 10, 255) if ln == 'day' else (230, 230, 230, 255), font=font)
dr.text((lab + ncol * fw + 50, 6), f'NE (→NW mirrored)', fill=(30, 20, 10, 255) if ln == 'day' else (230, 230, 230, 255), font=font)
for r, a in enumerate(acts):
    dr.text((8, 40 + r * fh + fh // 2), a, fill=(30, 20, 10, 255) if ln == 'day' else (230, 230, 230, 255), font=font)
    for b, fac in enumerate(('SE', 'NE')):
        for c, idx in enumerate(rig['actions'][a]['frames'][fac]):
            im = frame_img(sheet, rig, idx, PALS[pal], rig['lighting'][ln])
            im = im.resize((fw, fh), Image.NEAREST)
            S.alpha_composite(im, (lab + b * (ncol * fw + 40) + c * fw, 30 + r * fh))
S.save(out)
