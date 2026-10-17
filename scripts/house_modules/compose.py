"""Python 版合成（与 Swift HouseComposer 同算法），用于离线出图/校验。

模块素材：full（两面后墙全高）+ cut（两面后墙切到 CUT_H）两张对齐图。
每段后墙：有邻居在它后面（共享墙）→ 用 cut；外墙 → full。共享墙只由前/右格子画。
"""
from PIL import Image, ImageDraw
import sys; sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
from geom import *

CAP_TOP = (108, 66, 38, 255)
CAP_EDGE = (38, 20, 11, 255)
END_FACE = (72, 42, 24, 255)
OUTLINE = (12, 8, 6, 235)

def add(p, q): return (p[0] + q[0], p[1] + q[1])



    segs = []
    return segs

def plan(layout, modules):
    cells = {}
    for key, col, row in layout:
        fw = modules[key]['fw']
        for dc in range(fw):
            cells[(col + dc, row)] = key
    out = []
    for key, col, row in layout:
        fw = modules[key]['fw']
        g = module_geom(fw)
        T = g['T']
        segs = []
        # NW 墙：与 (col-1,row) 共享
        h = CUT_H if (col - 1, row) in cells else WALL_H
        segs.append(('nw', T, g['L'], h))
        # NE 墙：逐格，与 (col+i,row-1) 共享
        for i in range(fw):
            a = (T[0] + i * W // 2, T[1] + i * FH // 2)
            b = (a[0] + W // 2, a[1] + FH // 2)
            h = CUT_H if (col + i, row - 1) in cells else WALL_H
            segs.append(('ne', a, b, h))
        out.append(dict(key=key, col=col, row=row, fw=fw, g=g, segs=segs))
    return cells, out

def nw_height(cells, col, row):
    if (col, row) not in cells: return 0
    return CUT_H if (col - 1, row) in cells else WALL_H

def ne_height(cells, col, row):
    if (col, row) not in cells: return 0
    return CUT_H if (col, row - 1) in cells else WALL_H

def module_image(m, mod):
    """按墙段拼 full/cut：每段墙上方的竖条区域取对应版本。"""
    full, cut = mod['full'], mod['cut']
    img = full.copy()
    w, h = img.size
    for name, a, b, hh in m['segs']:
        if hh == WALL_H: continue
        mask = Image.new('L', (w, h), 0)
        # 墙段上方整条（含挡在墙前的家具，两版对齐）
        x0, x1 = sorted((a[0], b[0]))
        ya, yb = (a[1], b[1]) if a[0] <= b[0] else (b[1], a[1])
        ImageDraw.Draw(mask).polygon([(x0, 0), (x1, 0), (x1, yb), (x0, ya)], fill=255)
        img.paste(cut, (0, 0), mask) if False else None
        img = Image.composite(cut, img, mask)
    return img

def compose(layout, modules, pad=24):
    cells, items = plan(layout, modules)
    xs, ys = [], []
    for it in items:
        tx, ty = tip(it['col'], it['row'])
        it['ox'], it['oy'] = tx - it['g']['T'][0], ty - it['g']['T'][1]
        for p in it['g']['silhouette']:
            xs.append(p[0] + it['ox']); ys.append(p[1] + it['oy'])
    minx, miny = min(xs) - pad, min(ys) - pad - 6
    Wc, Hc = max(xs) + pad - minx, max(ys) + pad - miny
    Wc += Wc % 2; Hc += Hc % 2
    canvas = Image.new('RGBA', (Wc, Hc), (0, 0, 0, 0))
    d = ImageDraw.Draw(canvas)
    off = lambda pts, it: [(x + it['ox'] - minx, y + it['oy'] - miny) for x, y in pts]
    for it in items:  # 外轮廓
        g = it['g']
        sil = list(g['silhouette'])
        hn = it['segs'][0][3]
        sil = [(g['T'][0], g['T'][1] - WALL_H), (g['R'][0], g['R'][1] - WALL_H), g['R'], (g['R'][0], g['R'][1] + SLAB),
               (g['F'][0], g['F'][1] + SLAB), (g['L'][0], g['L'][1] + SLAB), g['L'], (g['L'][0], g['L'][1] - hn)]
        pts = off(sil, it)
        d.polygon(pts, fill=OUTLINE)
        d.line(pts + [pts[0]], fill=OUTLINE, width=5)
    items.sort(key=lambda it: (it['row'], it['col']))
    for it in items:
        mod = modules[it['key']]
        # 墙顶 / 端面 / 壁柱在墙面后方，先画；模块图最后盖上（靠墙的高家具挡住它们）
        d = ImageDraw.Draw(canvas)
        col, row, fw, g = it['col'], it['row'], it['fw'], it['g']
        for name, a, b, hh in it['segs']:
            o = CAP_NW if name == 'nw' else CAP_NE
            ua, ub = (a[0], a[1] - hh), (b[0], b[1] - hh)
            d.polygon(off([ua, ub, add(ub, o), add(ua, o)], it), fill=CAP_TOP, outline=CAP_EDGE)
        # 后角
        hn = it['segs'][0][3]; he = it['segs'][1][3]
        T = g['T']
        hc = max(hn, he)
        uT = (T[0], T[1] - hc)
        d.polygon(off([uT, add(uT, CAP_NW), add(add(uT, CAP_NW), CAP_NE), add(uT, CAP_NE)], it), fill=CAP_TOP, outline=CAP_EDGE)
        # 墙端面：本墙比延续墙高的部分露出来
        L, R = g['L'], g['R']
        cont = nw_height(cells, col, row + 1)
        if hn > cont:
            q = [(L[0], L[1] - cont), (L[0], L[1] - hn), add((L[0], L[1] - hn), CAP_NW), add((L[0], L[1] - cont), CAP_NW)]
            d.polygon(off(q, it), fill=END_FACE, outline=CAP_EDGE)
        hlast = it['segs'][-1][3]
        cont = ne_height(cells, col + fw, row)
        if hlast > cont:
            q = [(R[0], R[1] - cont), (R[0], R[1] - hlast), add((R[0], R[1] - hlast), CAP_NE), add((R[0], R[1] - cont), CAP_NE)]
            d.polygon(off(q, it), fill=END_FACE, outline=CAP_EDGE)
        # NE 墙段之间高度变化处（客厅跨两格）
        for s0, s1 in zip(it['segs'][1:], it['segs'][2:]):
            if s0[3] != s1[3]:
                hi, lo = max(s0[3], s1[3]), min(s0[3], s1[3])
                p = s0[2]
                q = [(p[0], p[1] - lo), (p[0], p[1] - hi), add((p[0], p[1] - hi), CAP_NE), add((p[0], p[1] - lo), CAP_NE)]
                if s0[3] > s1[3]:
                    d.polygon(off(q, it), fill=END_FACE, outline=CAP_EDGE)
        # 后方邻居墙在本格后角结束、比本墙高 → 那面墙的端面朝前露出
        for (nc, nr, mine, o) in ((col, row - 1, hn, CAP_NW), (col - 1, row, he, CAP_NE)):
            hb = nw_height(cells, nc, nr) if o is CAP_NW else ne_height(cells, nc, nr)
            if hb > mine:
                q = [(T[0], T[1] - mine), (T[0], T[1] - hb), add((T[0], T[1] - hb), o), add((T[0], T[1] - mine), o)]
                # 端面在邻居墙的末端；朝向与本墙同向
                d.polygon(off(q, it), fill=END_FACE, outline=CAP_EDGE)
        if (col - 1, row) in cells or (col, row - 1) in cells:
            x, y = off([T], it)[0]
            d.rectangle([x - 3, y - hc, x + 2, y], fill=(66, 38, 22, 255), outline=CAP_EDGE)
        canvas.alpha_composite(module_image(it, mod), (it['ox'] - minx, it['oy'] - miny))
    return canvas
