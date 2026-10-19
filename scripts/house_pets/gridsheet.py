import json, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from walkgrid import DIRS, px, N
import numpy as np
st = sys.argv[1]; mods = sys.argv[2].split(','); outp = sys.argv[3]
blocked = json.load(open(str(Path(__file__).with_name('blocks.json')))).get(st, {}) if len(sys.argv) > 4 else {}
cat = json.load(open(DIRS[st] / 'catalog.json'))
tiles = []
try: font = ImageFont.truetype('/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf', 15)
except Exception: font = ImageFont.load_default()
for mid in mods:
    art = cat['modules'][mid]; tip = art['tip']; fu, fv = art['footprint']
    img = Image.open(DIRS[st] / f'module-{mid}-day-unlit.png').convert('RGBA')
    Z = int(__import__('os').environ.get('Z', 3)); img = img.resize((img.width * Z, img.height * Z), Image.NEAREST)
    ov = Image.new('RGBA', img.size, (0, 0, 0, 0)); d = ImageDraw.Draw(ov)
    P = lambda u, v: (px(tip, u, v)[0] * Z, px(tip, u, v)[1] * Z)
    B = np.zeros((fv * N, fu * N), bool)
    for r in blocked.get(mid, []):
        j0, i0, j1, i1 = r; B[i0:i1, j0:j1] = True
    for i in range(fv * N):
        for j in range(fu * N):
            if B[i, j]: d.polygon([P(j / N, i / N), P((j + 1) / N, i / N), P((j + 1) / N, (i + 1) / N), P(j / N, (i + 1) / N)], fill=(255, 0, 0, 90))
    for j in range(fu * N + 1):
        d.line([P(j / N, 0), P(j / N, fv)], fill=(0, 255, 255, 200 if j % 4 == 0 else 90), width=2 if j % 4 == 0 else 1)
    for i in range(fv * N + 1):
        d.line([P(0, i / N), P(fu, i / N)], fill=(255, 255, 0, 200 if i % 4 == 0 else 90), width=2 if i % 4 == 0 else 1)
    for j in range(fu * N):
        x, y = P((j + .5) / N, 0); d.text((x - 4, y - 18), str(j), fill=(0, 255, 255, 255), font=font)
        x, y = P((j + .5) / N, fv); d.text((x - 4, y + 6), str(j), fill=(0, 255, 255, 255), font=font)
    for i in range(fv * N):
        x, y = P(0, (i + .5) / N); d.text((x - 20, y - 6), str(i), fill=(255, 255, 0, 255), font=font)
        x, y = P(fu, (i + .5) / N); d.text((x + 8, y - 6), str(i), fill=(255, 255, 0, 255), font=font)
    for i in range(fv * N):
        for j in range(fu * N):
            if (i + j) % 2 == 0 and not B[i, j]:
                d.polygon([P(j / N, i / N), P((j + 1) / N, i / N), P((j + 1) / N, (i + 1) / N), P(j / N, (i + 1) / N)], fill=(255, 255, 255, 28))
    img.alpha_composite(ov)
    ImageDraw.Draw(img).text((8, 8), f'{st}/{mid}', fill=(255, 255, 255, 255), font=font)
    tiles.append(img)
W = sum(t.width for t in tiles); H = max(t.height for t in tiles)
sheet = Image.new('RGBA', (W, H), (20, 20, 20, 255)); x = 0
for t in tiles: sheet.alpha_composite(t, (x, 0)); x += t.width
sheet.save(outp)
