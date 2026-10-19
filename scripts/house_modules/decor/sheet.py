import sys, json
from PIL import Image, ImageDraw
from pathlib import Path
d = Path(sys.argv[1]); out = sys.argv[2]; scale = 3
names = list(json.loads((d / 'anchors.json').read_text()))
cells = []
for n in names:
    fs = sorted(d.glob(f'decor-{n}-*.png'))
    fs = [f for f in fs if 'day' in f.name] + [f for f in fs if 'night' in f.name]
    cells.append((n, [Image.open(f) for f in fs]))
cw = max(sum(i.width for i in ims) + 10 * len(ims) for _, ims in cells) * scale
ch = max(max(i.height for i in ims) for _, ims in cells) * scale + 20
cols = 3; rows = (len(cells) + cols - 1) // cols
sheet = Image.new('RGBA', (cw * cols, ch * rows), (128, 122, 112, 255)); dr = ImageDraw.Draw(sheet)
for k, (n, ims) in enumerate(cells):
    x = (k % cols) * cw + 6; y = (k // cols) * ch + 4
    for im in ims:
        big = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
        sheet.alpha_composite(big, (x, y)); x += big.width + 10 * scale // 2
    dr.text(((k % cols) * cw + 6, (k // cols) * ch + ch - 16), n, fill=(255, 255, 255, 255))
sheet.save(out)
