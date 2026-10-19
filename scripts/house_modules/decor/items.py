"""Decor item SDF models (world units; floor items centred at (C,C,0); wall items on NW wall X=0 centred at Y=C)."""
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from sdf import *
C = 120.0
Z = lambda h: h * CZ                      # screen px height -> world Z
rng = np.random.default_rng(7)

def noise(p, f=0.35, seed=0):
    q = p * f + seed * 17.13
    return (np.sin(q[:, 0] * 1.7 + np.sin(q[:, 1] * 1.3)) * np.sin(q[:, 1] * 2.1 + q[:, 2] * 0.7) * np.sin(q[:, 2] * 1.9 + q[:, 0] * 0.9)) * 0.5 + 0.5
def vary(base, amt=0.12, f=0.35, seed=0):
    base = np.asarray(base, float)
    return lambda p, n: np.clip(base * (1 - amt + 2 * amt * noise(p, f, seed))[:, None], 0, 1)

TERRA = (0.72, 0.38, 0.22); CREAM = (0.92, 0.88, 0.80); WOOD = (0.52, 0.32, 0.17); DWOOD = (0.32, 0.19, 0.10)
LEAF = (0.20, 0.48, 0.18); SOIL = (0.22, 0.14, 0.09); GOLD = (0.85, 0.66, 0.25); RED = (0.78, 0.12, 0.10)

def pot(s, r, h, col=TERRA, rim=True, z0=0.0):
    s.mat('pot', vary(col, 0.06, 0.5)); s.mat('soil', vary(SOIL, 0.2, 0.9))
    c = V(C, C, z0)
    s.add(lambda p: np.maximum(sd_cone_z(p, c, r * 0.78, r, Z(h)), -sd_cyl_z(p, c + V(0, 0, Z(h)), r - 1.4, 1.2)), 'pot')
    if rim: s.add(lambda p: sd_torus_z(p, c + V(0, 0, Z(h) - 0.6), r - 0.2, 1.3), 'pot')
    s.add(lambda p: sd_cyl_z(p, c + V(0, 0, Z(h) - 1.6), r - 1.2, 0.6), 'soil')
    return z0 + Z(h)

def monstera():
    s = Scene(); top = pot(s, 7, 11, col=(0.86, 0.84, 0.78))
    s.mat('leaf', vary(LEAF, 0.18, 0.25, 1)); s.mat('stem', (0.30, 0.45, 0.16))
    leaves = []
    for i in range(11):
        a = i * 2.39996 + 0.3; el = 0.55 + 0.35 * ((i * 7) % 5) / 4; L = 16 + 5 * ((i * 3) % 4) / 3
        d = V(np.cos(a) * np.cos(el), np.sin(a) * np.cos(el), np.sin(el))
        base = V(C, C, top); tip = base + d * L * 1.15
        leaves.append((base, tip, d, a))
    for base, tip, d, a in leaves:
        s.add(lambda p, b=base, t=tip: sd_capsule(p, b, b + (t - b) * 0.7, 0.55), 'stem')
        dd = d * V(1, 1, 0.3); dd /= np.linalg.norm(dd)
        def leaf(p, t=tip, dd=dd):
            e = sd_ellip_dir(p, t, dd + V(0, 0, -0.25), (8.0, 5.8, 0.9), roll=V(0, 0, 1))
            q = (p - t) @ frame(dd + V(0, 0, -0.25)).T
            slit = np.abs(np.sin(np.arctan2(q[:, 1], q[:, 0] + 6) * 7)) < 0.12
            return np.where(slit & (np.abs(q[:, 1]) > 2.8), np.maximum(e, 0.6), e)
        s.add(leaf, 'leaf')
    return s

def spider_plant():
    s = Scene()
    s.mat('wood', vary(WOOD, 0.1, 0.6, 2))
    s.add(lambda p: sd_cyl_z(p, V(C, C, Z(15)), 9.5, 1.0, 0.4), 'wood')
    for dx, dy in ((-5, -5), (5, -5), (-5, 5), (5, 5)):
        s.add(lambda p, dx=dx, dy=dy: sd_capsule(p, V(C + dx, C + dy, 0.5), V(C + dx * 1.2, C + dy * 1.2, Z(15)), 0.9), 'wood')
    top = pot(s, 7, 10, col=(0.93, 0.92, 0.88), z0=Z(16))
    s.mat('leafg', vary((0.42, 0.66, 0.22), 0.15, 0.4, 3)); s.mat('leafw', vary((0.86, 0.90, 0.70), 0.06, 0.4, 3))
    for i in range(22):
        a = i * 2.39996; L = 13 + (i * 5 % 7)
        out = V(np.cos(a), np.sin(a), 0)
        b = V(C, C, top - 1); m = b + out * L * 0.55 + V(0, 0, Z(7 + (i % 4))); e = b + out * L * 1.05 + V(0, 0, Z(2 - (i % 3) * 3))
        s.add(lambda p, b=b, m=m: sd_capsule(p, b, m, 0.75), 'leafg' if i % 3 else 'leafw')
        s.add(lambda p, m=m, e=e: sd_capsule(p, m, e, 0.65), 'leafg' if i % 3 else 'leafw')
    return s

def succulent():
    s = Scene(); s.mat('pot', vary((0.62, 0.62, 0.60), 0.08, 0.7))
    s.mat('soil', vary(SOIL, 0.2, 0.9))
    s.add(lambda p: np.maximum(sd_box(p, V(C, C, Z(4)), (6, 6, Z(4)), 0.8), -sd_box(p, V(C, C, Z(8)), (4.8, 4.8, 1.5))), 'pot')
    s.add(lambda p: sd_box(p, V(C, C, Z(7.3)), (4.9, 4.9, 0.4)), 'soil')
    s.mat('suc', lambda p, n: np.clip(np.array([0.45, 0.66, 0.50]) + np.array([0.35, 0.05, 0.1]) * np.clip((np.hypot(p[:, 0] - C, p[:, 1] - C) - 3) / 5, 0, 1)[:, None], 0, 1))
    for ring, (k, R, el, sz) in enumerate(((8, 4.6, 0.35, 3.4), (6, 2.8, 0.8, 2.8), (4, 1.0, 1.2, 2.2))):
        for i in range(k):
            a = i * 2 * np.pi / k + ring * 0.5
            d = V(np.cos(a) * np.cos(el), np.sin(a) * np.cos(el), np.sin(el))
            c = V(C, C, Z(8)) + d * R + V(0, 0, 1.2)
            s.add(lambda p, c=c, d=d, sz=sz: sd_ellip_dir(p, c, d, (sz, sz * 0.62, sz * 0.38)), 'suc')
    return s

def bonsai():
    s = Scene(); s.mat('pot', vary((0.22, 0.38, 0.55), 0.06, 0.6)); s.mat('soil', vary((0.30, 0.42, 0.20), 0.25, 1.2))
    s.add(lambda p: np.maximum(sd_box(p, V(C, C, Z(2.8)), (11, 7, Z(2.8)), 1.0), -sd_box(p, V(C, C, Z(5.6)), (9.8, 5.8, 1.2))), 'pot')
    s.add(lambda p: sd_box(p, V(C, C, Z(5.0)), (9.9, 5.9, 0.4)), 'soil')
    s.mat('bark', vary((0.36, 0.25, 0.17), 0.18, 0.9, 4)); s.mat('fol', vary((0.22, 0.42, 0.16), 0.22, 0.45, 5))
    pts = [V(C - 2, C, Z(5)), V(C + 2, C - 1, Z(11)), V(C - 3, C + 1, Z(16)), V(C + 1, C, Z(21))]
    for a, b, r in zip(pts, pts[1:], (1.9, 1.5, 1.1)):
        s.add(lambda p, a=a, b=b, r=r: sd_capsule(p, a, b, r), 'bark')
    s.add(lambda p: sd_capsule(p, pts[1], V(C + 8, C - 2, Z(13)), 0.9), 'bark')
    pads = [(V(C + 9, C - 2, Z(14.5)), (6, 5, 2.6)), (V(C - 6, C + 2, Z(18)), (6.5, 5.5, 2.8)), (V(C + 1, C, Z(23.5)), (6, 5, 3.0))]
    def fol(p):
        d = 1e9
        for c, r in pads:
            d = smin(d, sd_ellip(p, c, np.array(r, float)), 1.5)
        return d + (noise(p, 0.9, 3) - 0.5) * 0.9
    s.add(fol, 'fol')
    return s

def rug_tex(kind):
    if kind == 'round':
        def f(p, n):
            r = np.hypot(p[:, 0] - C, p[:, 1] - C) / 38
            a = np.arctan2(p[:, 1] - C, p[:, 0] - C)
            col = np.where((r > 0.88)[:, None], np.array([0.55, 0.12, 0.10]),
                  np.where((r > 0.78)[:, None], np.array([0.90, 0.80, 0.58]),
                  np.where(((r > 0.55) & (np.sin(a * 12) > 0.3))[:, None], np.array([0.20, 0.27, 0.42]),
                  np.where((r > 0.30)[:, None], np.array([0.70, 0.20, 0.14]),
                  np.where((r > 0.18)[:, None], np.array([0.90, 0.80, 0.58]), np.array([0.20, 0.27, 0.42]))))))
            return np.clip(col * (0.9 + 0.2 * noise(p, 1.4, 6))[:, None], 0, 1)
    else:
        def f(p, n):
            u = (p[:, 0] - C) / 42
            v = (p[:, 1] - C) / 27
            band = (np.floor((u + 1) * 7) % 3)
            cols = np.array([[0.30, 0.42, 0.40], [0.88, 0.82, 0.68], [0.74, 0.46, 0.22]])
            col = cols[band.astype(int).clip(0, 2)]
            edge = (np.abs(v) > 0.84) | (np.abs(u) > 0.92)
            col[edge] = [0.25, 0.20, 0.17]
            diamond = (np.abs(np.abs(u * 3 % 1 - 0.5) + np.abs(v) * 0.5 - 0.25) < 0.04)
            col[diamond & ~edge] = [0.92, 0.88, 0.80]
            return np.clip(col * (0.9 + 0.2 * noise(p, 1.4, 7))[:, None], 0, 1)
    return f

def rug_round():
    s = Scene(); s.mat('rug', rug_tex('round'), spec=0.02)
    s.add(lambda p: sd_cyl_z(p, V(C, C, 0.6), 38, 0.6, 0.4), 'rug'); return s
def rug_stripe():
    s = Scene(); s.mat('rug', rug_tex('stripe'), spec=0.02); s.mat('fringe', (0.92, 0.88, 0.78))
    s.add(lambda p: sd_box(p, V(C, C, 0.6), (42, 27, 0.6), 0.3), 'rug')
    for sgn in (-1, 1):
        s.add(lambda p, sgn=sgn: sd_box(p, V(C + sgn * 44, C, 0.3), (2, 25, 0.3)), 'fringe')
    return s

# ---------- wall items (X=0 is the wall, object at X>0) ----------
def tex_sample(img, u, v):
    """img HxWx3 float, u,v in 0..1 (u left->right on screen, v top->bottom)"""
    h, w = img.shape[:2]
    x = np.clip((u * w).astype(int), 0, w - 1); y = np.clip((v * h).astype(int), 0, h - 1)
    return img[y, x]
def landscape_img():
    w, h = 64, 44; im = np.zeros((h, w, 3))
    ys, xs = np.mgrid[0:h, 0:w] / np.array([h, w])[:, None, None]
    im[:] = np.stack([0.55 + 0.35 * ys, 0.70 + 0.2 * ys, 0.92 - 0.1 * ys], -1)
    mt = 0.55 - 0.25 * np.abs(np.sin(xs * 5.5)) * (1 - xs * 0.3)
    im[ys > mt] = [0.36, 0.42, 0.55]; snow = (ys > mt) & (ys < mt + 0.06); im[snow] = [0.95, 0.95, 0.97]
    hill = 0.72 - 0.08 * np.sin(xs * 9 + 1)
    im[ys > hill] = [0.30, 0.52, 0.24]
    im[ys > 0.86] = [0.35, 0.55, 0.70]
    sun = (xs - 0.78) ** 2 + ((ys - 0.2) * 0.69) ** 2 < 0.006; im[sun] = [0.98, 0.86, 0.50]
    return im
def cat_img():
    w, h = 40, 48; im = Image.new('RGB', (w, h), (232, 214, 170)); d = ImageDraw.Draw(im)
    d.ellipse((8, 22, 32, 50), fill=(225, 135, 55)); d.ellipse((10, 8, 30, 28), fill=(225, 135, 55))
    d.polygon([(11, 14), (12, 2), (19, 10)], fill=(225, 135, 55)); d.polygon([(29, 14), (28, 2), (21, 10)], fill=(225, 135, 55))
    d.polygon([(13, 11), (13, 5), (17, 10)], fill=(240, 170, 160)); d.polygon([(27, 11), (27, 5), (23, 10)], fill=(240, 170, 160))
    d.rectangle((14, 15, 16, 18), fill=(40, 60, 30)); d.rectangle((24, 15, 26, 18), fill=(40, 60, 30))
    d.polygon([(19, 20), (21, 20), (20, 22)], fill=(200, 90, 100)); d.ellipse((15, 30, 25, 46), fill=(245, 235, 220))
    for y in (24, 34, 42): d.line((9, y, 14, y + 1), fill=(170, 85, 30), width=2); d.line((31, y, 26, y + 1), fill=(170, 85, 30), width=2)
    return np.asarray(im, float) / 255

def framed(img, hw, hh, frame_col, cy, depth=1.6, fw=2.0):
    """framed picture on NW wall; hw/hh: half-size in world Y/Z; cy = centre Z"""
    s = Scene(); s.mat('frame', vary(frame_col, 0.08, 0.8, 8), spec=0.3, shin=30)
    s.mat('mat', (0.95, 0.93, 0.88))
    def canvas(p, n):
        u = (p[:, 1] - (C - hw + fw)) / (2 * (hw - fw)); v = 1 - (p[:, 2] - (cy - hh + fw)) / (2 * (hh - fw))
        return tex_sample(img, 1 - u, v)
    s.mat('canvas', canvas, spec=0.05)
    c = V(depth, C, cy)
    s.add(lambda p: np.maximum(sd_box(p, c, (depth, hw, hh), 0.4), -sd_box(p, c + V(depth, 0, 0), (0.8, hw - fw, hh - fw))), 'frame')
    s.add(lambda p: sd_box(p, c + V(0.2, 0, 0), (depth - 0.2, hw - fw + 0.2, hh - fw + 0.2)), 'canvas')
    return s
def painting_landscape(): return framed(landscape_img(), 17, 12, (0.62, 0.45, 0.18), 0)
def painting_cat(): return framed(cat_img(), 8, 10, (0.30, 0.18, 0.10), 0, fw=1.6)
def wall_clock():
    s = Scene(); s.mat('rim', vary(WOOD, 0.1, 0.8), spec=0.35, shin=30); s.mat('face', (0.95, 0.93, 0.86))
    s.mat('tick', (0.12, 0.10, 0.09)); s.mat('hand', (0.10, 0.08, 0.07)); s.mat('brass', GOLD, spec=0.8, shin=40, env=0.4)
    c = V(1.6, C, 0)
    s.add(lambda p: np.maximum(sd_cyl_x(p, c, 11, 1.8, 0.6), -sd_cyl_x(p, c + V(1.8, 0, 0), 9.2, 0.9)), 'rim')
    s.add(lambda p: sd_cyl_x(p, c, 9.3, 1.3), 'face')
    for i in range(12):
        a = i * np.pi / 6; L = 1.6 if i % 3 == 0 else 0.9
        s.add(lambda p, a=a, L=L: sd_box(p, c + V(1.25, 6.3 * np.sin(a), 6.3 * np.cos(a)), (0.15, 0.45 if i % 3 else 0.6, L / 2 + 0.2)) if False else
              sd_capsule(p, c + V(1.3, (8.4 - L) * np.sin(a), (8.4 - L) * np.cos(a)), c + V(1.3, 8.4 * np.sin(a), 8.4 * np.cos(a)), 0.45), 'tick')
    s.add(lambda p: sd_capsule(p, c + V(1.5, 0, 0), c + V(1.5, 3.0, 3.8), 0.5), 'hand')
    s.add(lambda p: sd_capsule(p, c + V(1.5, 0, 0), c + V(1.5, -6.0, 1.2), 0.4), 'hand')
    s.add(lambda p: sd_cyl_x(p, c + V(1.6, 0, 0), 0.9, 0.4), 'brass')
    return s

def book_stack():
    s = Scene()
    cols = [(0.62, 0.16, 0.14), (0.18, 0.32, 0.50), (0.85, 0.72, 0.36), (0.22, 0.42, 0.28), (0.55, 0.30, 0.45)]
    z = 0.0
    for i, (col, (hx, hy, th, rot)) in enumerate(zip(cols, ((11, 8, 3.2, 0.0), (10, 7.5, 2.6, 0.18), (9.5, 7, 3.4, -0.12), (8.5, 6.5, 2.4, 0.3), (8, 6, 2.8, -0.05)))):
        s.mat(f'b{i}', vary(col, 0.06, 0.8, i), spec=0.25, shin=24); s.mat(f'pg{i}', (0.93, 0.90, 0.80))
        ca, sa = np.cos(rot), np.sin(rot); c = V(C, C, z + th / 2)
        def rot_p(p, c=c, ca=ca, sa=sa):
            q = p - c; return np.stack([q[:, 0] * ca + q[:, 1] * sa, -q[:, 0] * sa + q[:, 1] * ca, q[:, 2]], 1)
        s.add(lambda p, r=rot_p, hx=hx, hy=hy, th=th: np.maximum(sd_box(r(p), V(0, 0, 0), (hx, hy, th / 2), 0.3), -sd_box(r(p), V(1.2, 0, 0), (hx, hy - 0.8, th / 2 - 0.5))), f'b{i}')
        s.add(lambda p, r=rot_p, hx=hx, hy=hy, th=th: sd_box(r(p), V(0.4, 0, 0), (hx - 0.6, hy - 0.9, th / 2 - 0.55)), f'pg{i}')
        z += th
    return s

def plaid(base, line, f=0.6):
    base = np.asarray(base); line = np.asarray(line)
    def fn(p, n):
        m = ((np.sin(p[:, 0] * f) > 0.75) | (np.sin(p[:, 1] * f) > 0.75))[:, None]
        return np.clip(np.where(m, line, base) * (0.92 + 0.16 * noise(p, 1.0, 9))[:, None], 0, 1)
    return fn
def cat_bed():
    s = Scene(); s.mat('fab', plaid((0.62, 0.30, 0.22), (0.88, 0.78, 0.60)), spec=0.03); s.mat('cush', vary((0.94, 0.90, 0.82), 0.05, 1.5), spec=0.02)
    c = V(C, C, 0)
    s.add(lambda p: sd_torus_z(p, c + V(0, 0, Z(5)), 10.5, Z(4.2)), 'fab')
    s.add(lambda p: sd_cyl_z(p, c + V(0, 0, Z(1.6)), 13, Z(1.6), 1.2), 'fab')
    s.add(lambda p: sd_ellip(p, c + V(0, 0, Z(3.2)), np.array([9.5, 9.5, Z(2.2)])), 'cush')
    return s
def cat_tree():
    s = Scene(); s.mat('carpet', vary((0.80, 0.74, 0.64), 0.1, 1.2, 10), spec=0.02)
    s.mat('sisal', lambda p, n: np.clip(np.array([0.76, 0.62, 0.40]) * (0.82 + 0.18 * (np.sin(p[:, 2] * 3.2) > 0))[:, None], 0, 1), spec=0.05)
    s.mat('ball', (0.85, 0.20, 0.25)); s.mat('rope', (0.9, 0.85, 0.7))
    s.add(lambda p: sd_box(p, V(C, C, Z(2.5)), (16, 13, Z(2.5)), 1.0), 'carpet')
    for (x, y, h) in ((C - 8, C - 5, 34), (C + 8, C + 5, 52)):
        s.add(lambda p, x=x, y=y, h=h: sd_cyl_z(p, V(x, y, Z(h / 2 + 2)), 3.0, Z(h / 2)), 'sisal')
    s.add(lambda p: sd_box(p, V(C - 6, C - 3, Z(36)), (12, 10, Z(2.2)), 1.0), 'carpet')
    s.add(lambda p: np.maximum(sd_box(p, V(C + 6, C + 3, Z(56)), (11, 10, Z(4.5)), 2.5), -sd_box(p, V(C + 6, C + 3, Z(60)), (8.5, 7.5, Z(3)), 1.5)), 'carpet')
    s.add(lambda p: sd_capsule(p, V(C - 14, C - 8, Z(34)), V(C - 14, C - 8, Z(24)), 0.35), 'rope')
    s.add(lambda p: sd_sphere(p, V(C - 14, C - 8, Z(22)), 2.0), 'ball')
    return s
def food_bowl():
    s = Scene(); s.mat('mat', vary((0.36, 0.58, 0.62), 0.05, 1.0), spec=0.1); s.mat('steel', (0.70, 0.71, 0.73), spec=0.9, shin=50, env=0.6)
    s.mat('cer', (0.95, 0.94, 0.90), spec=0.4, shin=40); s.mat('kib', vary((0.55, 0.32, 0.15), 0.25, 2.5)); s.mat('water', (0.45, 0.65, 0.85), spec=0.9, shin=80, env=0.3)
    s.add(lambda p: sd_box(p, V(C, C, 0.4), (11, 19, 0.4), 2.4), 'mat')
    for dy, mt, fill in ((-9, 'steel', 'kib'), (9, 'cer', 'water')):
        c = V(C, C + dy, 0.8)
        s.add(lambda p, c=c: np.maximum(sd_cone_z(p, c, 5.2, 7.2, Z(5)), -sd_cone_z(p, c + V(0, 0, 1.0), 4.0, 6.2, Z(5))), mt)
        s.add(lambda p, c=c: sd_cyl_z(p, c + V(0, 0, Z(3.6)), 5.8, 0.5) + (noise(p, 2.0, 4) * 0.5 if fill == 'kib' else 0), fill)
    return s
def dog_bed():
    s = Scene(); s.mat('fab', vary((0.40, 0.36, 0.48), 0.08, 0.7, 11), spec=0.04); s.mat('cush', plaid((0.90, 0.86, 0.78), (0.70, 0.62, 0.55), 0.8), spec=0.02)
    s.mat('bone', (0.95, 0.92, 0.84))
    c = V(C, C, 0)
    def ring(p):
        outer = sd_box(p, c + V(0, 0, Z(5)), (16, 21, Z(5)), Z(4.5))
        inner = sd_box(p, c + V(0, 0, Z(8)), (11, 16, Z(5)), 3.0)
        return np.maximum(outer, -inner)
    s.add(ring, 'fab')
    s.add(lambda p: sd_box(p, c + V(0, 0, Z(3.4)), (11.5, 16.5, Z(1.6)), 1.6), 'cush')
    s.add(lambda p: smin(sd_capsule(p, V(C + 4, C - 4, Z(5.6)), V(C + 1, C + 4, Z(5.6)), 0.9), np.minimum.reduce([sd_sphere(p, V(C + 4 + a, C - 4 + b, Z(5.6)), 1.2) for a, b in ((0.8, -0.6), (-0.6, -0.8))] + [sd_sphere(p, V(C + 1 + a, C + 4 + b, Z(5.6)), 1.2) for a, b in ((0.8, 0.6), (-0.6, 0.8))]), 0.5), 'bone')
    return s

def lantern():
    s = Scene()
    s.mat('red', lambda p, n: np.clip(np.array([0.86, 0.12, 0.08]) * (0.85 + 0.15 * (np.cos(np.arctan2(p[:, 1] - C, p[:, 0] - 10) * 10) > -0.6))[:, None], 0, 1), spec=0.3, shin=20, emis=0.45)
    s.mat('gold', GOLD, spec=0.8, shin=40, env=0.4); s.mat('tassel', (0.90, 0.10, 0.08)); s.mat('cord', (0.85, 0.65, 0.2))
    c = V(10, C, 0)
    s.add(lambda p: sd_ellip(p, c, np.array([8.5, 8.5, Z(7.5)])), 'red')
    s.add(lambda p: sd_cyl_z(p, c + V(0, 0, Z(7)), 4.5, Z(1.2), 0.5), 'gold')
    s.add(lambda p: sd_cyl_z(p, c - V(0, 0, Z(7)), 4.5, Z(1.2), 0.5), 'gold')
    s.add(lambda p: sd_cone_z(p, c - V(0, 0, Z(17)), 2.2, 1.0, Z(8.5)), 'tassel')
    s.add(lambda p: sd_capsule(p, c + V(0, 0, Z(8)), V(0.5, C, Z(14)), 0.35), 'cord')
    s.add(lambda p: sd_cyl_x(p, V(0.3, C, Z(14)), 1.2, 0.6), 'gold')
    return s
def fu_img(mirror=False):
    w = 64; im = Image.new('RGB', (w, w), (200, 25, 20)); d = ImageDraw.Draw(im)
    f = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc', 40)
    d.text((w / 2, w / 2 + 1), '福', font=f, fill=(250, 205, 70), anchor='mm')
    a = np.asarray(im, float) / 255
    return a[:, ::-1] if mirror else a
def fu(mirror=False):
    """diamond paper; texture is in diamond-local coords"""
    s = Scene(); img = fu_img(mirror)
    def tex(p, n):
        u = ((p[:, 1] - C) / 15.5 + 1) / 2; v = 1 - ((p[:, 2]) / 15.5 + 1) / 2
        return tex_sample(img, 1 - u, v)
    s.mat('paper', tex, spec=0.15, shin=20)
    def dia(p):
        q = p - V(0.6, C, 0)
        return np.maximum(np.abs(q[:, 1]) + np.abs(q[:, 2]) - 15.5, np.abs(q[:, 0]) - 0.6)
    s.add(dia, 'paper'); return s

def rabbit_lamp():
    s = Scene()
    s.mat('paper', vary((0.98, 0.95, 0.88), 0.03, 1.0), spec=0.1, emis=0.35); s.mat('eye', (0.85, 0.10, 0.12)); s.mat('pink', (0.96, 0.66, 0.68), emis=0.3)
    s.mat('wheel', (0.80, 0.20, 0.16)); s.mat('stick', WOOD)
    c = V(C, C, Z(9))
    s.add(lambda p: sd_ellip(p, c, np.array([9.5, 6.5, Z(6)])), 'paper')
    s.add(lambda p: sd_ellip(p, c + V(7.5, 0, Z(5.5)), np.array([4.8, 4.4, Z(4.2)])), 'paper')
    for dy in (-1.9, 1.9):
        s.add(lambda p, dy=dy: sd_ellip_dir(p, c + V(5.8, dy, Z(15)), V(-0.15, dy * 0.12, 1), (Z(5.5), 1.9, 1.1), roll=V(1, 0, 0)), 'paper')
        s.add(lambda p, dy=dy: sd_ellip_dir(p, c + V(6.6, dy, Z(15)), V(-0.15, dy * 0.12, 1), (Z(4.2), 0.9, 0.6), roll=V(1, 0, 0)), 'pink')
        s.add(lambda p, dy=dy: sd_sphere(p, c + V(11.6, dy * 1.2, Z(6.4)), 0.85), 'eye')
        for dx in (-5, 5):
            s.add(lambda p, dx=dx, dy=dy: sd_cyl_y(p, V(C + dx, C + dy * 3.4, Z(2.6)), 2.6, 0.7), 'wheel')
    s.add(lambda p: sd_sphere(p, c + V(-9.8, 0, Z(1.5)), 2.4), 'paper')
    s.add(lambda p: sd_capsule(p, c + V(-9, 0, Z(5)), c + V(-16, 0, Z(16)), 0.5), 'stick')
    return s
def pumpkin():
    s = Scene()
    def body_col(p, n):
        a = np.arctan2(p[:, 1] - C, p[:, 0] - C); col = np.array([0.92, 0.48, 0.10]) * (0.82 + 0.18 * np.cos(a * 8) ** 2)[:, None]
        # carved face on the camera-facing side (+X+Y)
        q = p - V(C, C, Z(7)); fx = (q[:, 0] - q[:, 1]) * 0.707; fz = q[:, 2] / Z(7); front = (q[:, 0] + q[:, 1]) > 4
        eye = front & (((np.abs(np.abs(fx) - 3.6) < 1.6 - (fz - 0.25) * 3) & (fz > 0.08) & (fz < 0.5)))
        mouth = front & (fz < -0.05) & (fz > -0.45) & (np.abs(fx) < 5.5 - np.abs(fz + 0.25) * 6) & ~((np.abs(fx - 1.5) < 0.8) & (fz > -0.2))
        glow = eye | mouth
        col[glow] = [1.0, 0.82, 0.30]
        return np.clip(col, 0, 1)
    s.mat('pump', body_col, spec=0.35, shin=24, emis=0.22); s.mat('stem', (0.32, 0.36, 0.14))
    def body(p):
        q = p - V(C, C, Z(7)); a = np.arctan2(q[:, 1], q[:, 0])
        return sd_ellip(p, V(C, C, Z(7)), np.array([10, 10, Z(7)])) + 0.5 * np.abs(np.sin(a * 4)) * (np.abs(q[:, 2]) < Z(6))
    s.add(body, 'pump')
    s.add(lambda p: sd_capsule(p, V(C, C, Z(13)), V(C + 1, C - 0.5, Z(17)), 1.2), 'stem')
    return s
def xmas_tree():
    s = Scene(); s.mat('tree', vary((0.10, 0.36, 0.20), 0.22, 0.6, 12), spec=0.05)
    s.mat('trunk', (0.40, 0.26, 0.14)); s.mat('pot', vary((0.70, 0.14, 0.12), 0.05, 0.7)); s.mat('star', (1.0, 0.85, 0.30), spec=0.8, shin=40, emis=0.6)
    s.mat('orn_r', (0.85, 0.12, 0.12), spec=0.9, shin=60, env=0.3); s.mat('orn_g', GOLD, spec=0.9, shin=60, env=0.4)
    s.mat('bulb', (1.0, 0.90, 0.55), emis=0.8); s.mat('gift', vary((0.20, 0.40, 0.70), 0.05, 0.5)); s.mat('ribbon', (0.95, 0.85, 0.40))
    s.add(lambda p: sd_cone_z(p, V(C, C, 0), 7.5, 6.5, Z(8)), 'pot')
    s.add(lambda p: sd_cyl_z(p, V(C, C, Z(10)), 2.0, Z(3)), 'trunk')
    tiers = [(Z(12), 17, Z(18)), (Z(24), 13.5, Z(16)), (Z(35), 10, Z(14)), (Z(45), 6.5, Z(12))]
    def tree(p):
        d = 1e9
        for z0, r, h in tiers:
            d = np.minimum(d, sd_cone_z(p, V(C, C, z0), r, 0.8, h))
        a = np.arctan2(p[:, 1] - C, p[:, 0] - C)
        return d + 0.6 * np.abs(np.sin(a * 9 + p[:, 2] * 0.5))
    s.add(tree, 'tree')
    s.add(lambda p: sd_sphere(p, V(C, C, Z(58)), 2.2), 'star')
    k = 0
    for z0, r, h in tiers:
        for i in range(7):
            a = i * 2 * np.pi / 7 + z0 * 0.1; zz = z0 + h * 0.22; rr = r * 0.78 + 0.4
            c = V(C + rr * np.cos(a), C + rr * np.sin(a), zz)
            s.add(lambda p, c=c: sd_sphere(p, c, 1.35 if k % 2 == 0 else 1.0), ['orn_r', 'bulb', 'orn_g'][k % 3]); k += 1
    s.add(lambda p: sd_box(p, V(C + 14, C + 6, Z(3)), (4, 4, Z(3)), 0.4), 'gift')
    s.add(lambda p: sd_box(p, V(C + 14, C + 6, Z(3)), (4.2, 0.8, Z(3.1))), 'ribbon')
    s.add(lambda p: sd_box(p, V(C + 14, C + 6, Z(3)), (0.8, 4.2, Z(3.1))), 'ribbon')
    return s
def snowman():
    s = Scene(); s.mat('snow', vary((0.95, 0.96, 1.0), 0.03, 0.8), spec=0.25, shin=12); s.mat('coal', (0.08, 0.08, 0.09))
    s.mat('carrot', (0.95, 0.50, 0.12)); s.mat('scarf', plaid((0.80, 0.14, 0.14), (0.95, 0.90, 0.85), 1.2)); s.mat('hat', (0.12, 0.12, 0.14), spec=0.4)
    c = V(C, C, 0)
    body = lambda p: smin(smin(sd_sphere(p, c + V(0, 0, Z(9)), 10), sd_sphere(p, c + V(0, 0, Z(22)), 7.2), 1.5), sd_sphere(p, c + V(0, 0, Z(32)), 5.2), 1.2)
    s.add(body, 'snow')
    s.add(lambda p: sd_torus_z(p, c + V(0, 0, Z(27.5)), 4.6, 1.5), 'scarf')
    s.add(lambda p: sd_capsule(p, c + V(3.5, 3.5, Z(27)), c + V(4.5, 5.5, Z(19)), 1.3), 'scarf')
    head = c + V(0, 0, Z(32))
    s.add(lambda p: sd_cyl_z(p, head + V(0, 0, Z(5.2)), 6.2, 0.6, 0.3), 'hat')
    s.add(lambda p: sd_cyl_z(p, head + V(0, 0, Z(8.5)), 4.0, Z(3.4), 0.4), 'hat')
    fwd = V(0.707, 0.707, 0)
    for side in (-1, 1):
        sv = V(0.707, -0.707, 0) * side * 2.0
        s.add(lambda p, sv=sv: sd_sphere(p, head + fwd * 4.6 + sv + V(0, 0, Z(1.6)), 0.8), 'coal')
    s.add(lambda p: sd_cone_z(p - 0, head + fwd * 4.6, 1.1, 0.2, 1.0) if False else sd_capsule(p, head + fwd * 4.5, head + fwd * 9.5 + V(0, 0, -0.5), 0.8), 'carrot')
    for k in range(3):
        s.add(lambda p, k=k: sd_sphere(p, c + V(0, 0, Z(22 - k * 5.5 + 2)) + fwd * (7.0 if k == 0 else 9.0 - k * 0.3), 0.85), 'coal')
    for side in (-1, 1):
        s.mat('arm', (0.36, 0.24, 0.14))
        sv = V(0.707, -0.707, 0) * side
        s.add(lambda p, sv=sv: sd_capsule(p, c + V(0, 0, Z(23)) + sv * 6, c + V(0, 0, Z(29)) + sv * 14, 0.6), 'arm')
    return s

FLOOR = dict(monstera=monstera, spider_plant=spider_plant, succulent=succulent, bonsai=bonsai, rug_round=rug_round, rug_stripe=rug_stripe,
             book_stack=book_stack, cat_bed=cat_bed, cat_tree=cat_tree, food_bowl=food_bowl, dog_bed=dog_bed,
             rabbit_lamp=rabbit_lamp, pumpkin=pumpkin, xmas_tree=xmas_tree, snowman=snowman)
WALL = dict(painting_landscape=painting_landscape, painting_cat=painting_cat, wall_clock=wall_clock, lantern=lantern, fu=fu)
