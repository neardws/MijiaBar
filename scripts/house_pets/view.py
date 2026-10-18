"""python3 view.py pkl pattern palname out idx..."""
import sys, pickle, numpy as np
from PIL import Image
from frames import cells
import paint as PA
PALS = dict(orange=dict(base='#E8973F', second='#B3561C', white='#F4EEE4', eye='#9CC43E'),
            grey=dict(base='#8C8E98', second='#55565F', white='#ECECEE', eye='#E6B640'),
            black=dict(base='#2E2B30', second='#1C1A1E', white='#F2F0EC', eye='#E9C24A'),
            calico=dict(base='#E59A45', second='#2F2A2C', white='#F5F0E8', eye='#7DB2C8'),
            dbg=dict(base='#808080', second='#E03030', white='#F0F0F0', eye='#3080F0'),
            siam=dict(base='#EFE2CC', second='#5A4234', white='#F5F0E8', eye='#4E8FE0'))
if __name__ == "__main__":
    FR = pickle.load(open(sys.argv[1], 'rb')); pat = sys.argv[2]; pal = PALS[sys.argv[3]]; out = sys.argv[4]
    idx = [int(a) for a in sys.argv[5:]]
    Z = int(__import__('os').environ.get('Z', 8))
    tiles = []
    for i in idx:
        F = FR[i][3]; C = cells(F, pat); C['region'] = PA.stamp_eyes(F, C); E = PA.encode(F, C)
        tiles.append((np.clip(PA.recolor(E, pal), 0, 1) * 255).astype(np.uint8))
    h, w = tiles[0].shape[:2]
    sheet = Image.new('RGBA', (len(tiles) * (w + 1) + 1, h + 2), (176, 128, 84, 255))
    for j, t in enumerate(tiles): sheet.alpha_composite(Image.fromarray(t, 'RGBA'), (1 + j * (w + 1), 1))
    sheet.resize((sheet.width * Z, sheet.height * Z), Image.NEAREST).save(out)
    