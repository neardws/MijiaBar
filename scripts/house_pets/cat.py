"""Short-hair cat: pose -> SDF parts + feature points; region patterns."""
import numpy as np
from sdfcat import Part, ellip_part, cone_part, chain, rotz, roty, rotx, nrm, sd_round_cone, sd_ellip

V = lambda *a: np.array(a, float)

def frame_from(fwd, up):
    f = nrm(fwd); u = np.asarray(up, float); u = nrm(u - f * (u @ f)); s = np.cross(u, f)
    return np.stack([f, s, u], 1)   # columns: local x,y,z in world

def spine_parts(pts, radii, up):
    """chain with local (along t, side, up) coords"""
    pts = [np.asarray(x, float) for x in pts]
    segL = [np.linalg.norm(pts[i + 1] - pts[i]) for i in range(len(pts) - 1)]
    L = np.cumsum([0] + segL); L = L / L[-1]
    out = []
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]; r1, r2 = radii[i], radii[i + 1]
        ax = nrm(b - a); u = nrm(np.asarray(up, float) - ax * (ax @ up)); sd = np.cross(u, ax)
        def fn(p, a=a, b=b, r1=r1, r2=r2, ax=ax, u=u, sd=sd, t0=L[i], t1=L[i + 1]):
            d, t = sd_round_cone(p, a, b, r1, r2)
            q = p - a; radial = q - (q @ ax)[:, None] * ax
            rr = r1 + (r2 - r1) * t
            loc = np.stack([t0 + (t1 - t0) * t, (radial @ sd) / rr, (radial @ u) / rr], 1)
            return d, loc, None
        out.append(fn)
    return out

class Cat:
    def __init__(s): s.parts = []; s.feat = {}
    def add(s, name, fn, k=3.0): s.parts.append(Part(name, fn, k))
    def ellip(s, name, c, R, rad, k=3.0):
        c = np.asarray(c, float); rad = np.asarray(rad, float)
        def fn(p):
            q = (p - c) @ R
            return sd_ellip(q, rad), q / rad, None
        s.add(name, fn, k)
    def spine(s, name, pts, radii, up, k=2.5):
        for i, fn in enumerate(spine_parts(pts, radii, up)): s.add(name, fn, k)
    def ear(s, name, base, tip, fwd, r1=4.6, r2=0.5, flat=2.1, k=1.6):
        base = np.asarray(base, float); tip = np.asarray(tip, float)
        ax = nrm(tip - base); f = nrm(np.asarray(fwd, float) - ax * (ax @ fwd)); sd = np.cross(ax, f)
        R = np.stack([f, sd, ax], 1)
        def fn(p):
            q = (p - base) @ R
            qs = q * np.array([flat, 1.0, 1.0])
            d, t = sd_round_cone(qs, V(0, 0, 0), V(0, 0, np.linalg.norm(tip - base)), r1, r2)
            return d / flat ** 0.5, np.stack([q[:, 0], q[:, 1] / (r1 * (1 - t) + r2 * t + 1e-3), t], 1), None
        s.add(name, fn, k)
    def limb(s, name, pts, radii, k=1.8):
        for i in range(len(pts) - 1):
            a, b = np.asarray(pts[i], float), np.asarray(pts[i + 1], float)
            def fn(p, a=a, b=b, r1=radii[i], r2=radii[i + 1], t0=i / (len(pts) - 1), t1=(i + 1) / (len(pts) - 1)):
                d, t = sd_round_cone(p, a, b, r1, r2)
                return d, np.stack([t0 + (t1 - t0) * t, p[:, 2], np.zeros(len(p))], 1), None
            s.add(name, fn, k)

def build(P):
    """P: pose dict in cat-local coords (x fwd, y left, z up)."""
    c = Cat()
    up = P.get('back_up', V(0, 0, 1))
    c.spine('body', P['spine'], P['spine_r'], up, k=3.0)
    c.spine('neck', P['neck'], P['neck_r'], P.get('neck_up', up), k=3.5)
    H = P['head_R']; hc = P['head_c']
    HS = P.get('head_scale', 1.2)
    hp = lambda v: hc + H @ (np.asarray(v, float) * HS)
    c.ellip('head', hc, H, V(10.0, 11.6, 10.0) * HS, k=3.5)
    for sy in (1, -1):
        c.ellip('cheek', hp((3.2, 6.0 * sy, -3.6)), H, V(6.0, 5.4, 5.0) * HS, k=3.0)
    c.ellip('muzzle', hp((8.0, 0, -3.8)), H, V(4.4, 6.2, 4.0) * HS, k=2.2)
    c.ellip('chin', hp((6.6, 0, -6.6)), H, V(3.6, 4.0, 2.6) * HS, k=2.0)
    ea = P.get('ear_spread', 0.0)
    for sy, nm in ((1, 'earL'), (-1, 'earR')):
        base = hp((-0.6, 6.0 * sy, 7.2)); tip = hp((-1.4, (9.2 + ea) * sy, 16.5 - ea * 0.6))
        c.ear(nm, base, tip, H @ V(1, 0, 0), r1=4.6 * HS, r2=0.5 * HS)
    for nm, pts, rr in P['legs']:
        c.limb(nm, pts, rr)
        pw = np.asarray(pts[-1], float)
        pd = nrm(P.get('paw_dir', {}).get(nm, V(1, 0, 0)))
        c.ellip(nm + 'paw', pw + pd * 1.0 + V(0, 0, -0.3), frame_from(pd, V(0, 0, 1)), V(4.2, 3.4, 2.4), k=1.5)
    for nm, ell in P.get('thighs', []):
        cc, R, rad = ell; c.ellip(nm, cc, R, rad, k=3.5)
    c.spine('tail', P['tail'], P['tail_r'], P.get('tail_up', V(0, 0, 1)), k=1.4)
    # features (cat-local)
    c.feat = dict(eyeL=hp((8.6, 4.5, 1.0)), eyeR=hp((8.6, -4.5, 1.0)), nose=hp((11.6, 0, -1.6)), head_c=hc, head_fwd=H @ V(1, 0, 0),
                  head_up=H @ V(0, 0, 1), mouth=hp((11.0, 0, -4.4)))
    c.eyes = P.get('eyes', 'open')
    return c

def head_R(yaw=0.0, pitch=0.0, roll=0.0):
    return rotz(yaw) @ roty(pitch) @ rotx(roll)

def stand(t=0.0, phase=None, breath=0.0, tail=0.0, head_yaw=0.35, head_pitch=0.0, eyes='open', walk=None):
    """t ∈[0,1): walk cycle phase if walk else idle"""
    bob = 0.0; legs_off = dict(FL=(0, 0), FR=(0, 0), HL=(0, 0), HR=(0, 0))
    if walk is not None:
        ph = walk * 2 * np.pi
        bob = 0.6 * np.cos(2 * ph)
        # lateral sequence: HL, FL, HR, FR offsets of 1/4
        offs = dict(HL=0.0, FL=0.25, HR=0.5, FR=0.75)
        legs_off = {}
        for k, o in offs.items():
            q = (walk + o) % 1.0
            if q < 0.62:   # stance: paw moves back
                x = 5.5 - 11.0 * (q / 0.62); z = 0.0
            else:          # swing
                u = (q - 0.62) / 0.38; x = -5.5 + 11.0 * (0.5 - 0.5 * np.cos(np.pi * u)); z = 3.6 * np.sin(np.pi * u)
            legs_off[k] = (x, z)
    zb = 22.5 + bob + breath * 0.4
    spine = [V(-16.5, 0, zb - 0.2), V(-6, 0, zb + 0.5 + breath * 0.2), V(5, 0, zb + 0.6), V(12, 0, zb + 1.6)]
    spine_r = [9.6, 10.4 + breath * 0.25, 10.0, 9.0]
    neck = [V(13, 0, zb + 3), V(18.5, 0, zb + 10)]
    hc = V(22.5, 0, zb + 17.0 + bob * 0.4)
    H = head_R(head_yaw, head_pitch)
    legs = []
    for side, sy in (('L', 1), ('R', -1)):
        x, z = legs_off['F' + side]
        sh = V(11, 5.4 * sy, zb - 3.5); paw = V(12.5 + x, 5.3 * sy, 2.6 + z)
        el = (sh + paw) / 2 + V(-0.8 - 0.2 * z, 0, 0)
        legs.append(('F' + side, [sh, el, paw], [4.4, 3.7, 3.4]))
        x, z = legs_off['H' + side]
        hip = V(-14, 6.0 * sy, zb - 6.5); paw = V(-15.5 + x, 5.8 * sy, 2.6 + z)
        knee = hip + V(3.0, 0, -4.5); hock = V(paw[0] - 3.6, 5.9 * sy, paw[2] + 7.0)
        legs.append(('H' + side, [knee, hock, paw], [4.8, 3.6, 3.3]))
    thighs = [(f'thigh{s}', (V(-13.5, 6.0 * sy, zb - 3.5), roty(-0.5), V(7.6, 4.3, 8.4))) for s, sy in (('L', 1), ('R', -1))]
    sw = tail
    tail_pts = [V(-24, 0, zb + 2.5), V(-29.5, 1.5 * sw, zb + 7), V(-32.5, 3.5 * sw, zb + 14), V(-32.5, 5.0 * sw, zb + 21), V(-29.6, 5.5 * sw, zb + 26.5)]
    return dict(spine=spine, spine_r=spine_r, neck=neck, neck_r=[7.6, 6.8], head_c=hc, head_R=H, legs=legs, thighs=thighs,
                tail=tail_pts, tail_r=[3.7, 3.3, 3.1, 3.0, 2.8], tail_up=V(1, 0, 0.3), eyes=eyes)

# ---------------- other actions ----------------
def _tail_wrap(base, side=1, z=3.0, flick=0.0):
    pts = [base, V(-14, 4 * side, z + 0.5), V(-9, 11 * side, z), V(0, 12.5 * side, z), V(7, 9.5 * side, z + 0.2 + flick * 1.5), V(10.5 + flick, (4.5 - flick * 2) * side, z + 0.6 + flick * 3)]
    return pts

def sit(breath=0.0, flick=0.0, eyes='open', head_yaw=0.45, head_pitch=0.0, head_roll=0.0, paw=None, ears=0.0):
    b = breath
    spine = [V(-8.5, 0, 10.5), V(-5.5, 0, 17 + b * 0.3), V(-1.5, 0, 23.5 + b * 0.4), V(1.5, 0, 28 + b * 0.4)]
    spine_r = [11.2, 10.6 + b * 0.25, 10.0, 9.2]
    neck = [V(2.5, 0, 29.5 + b * 0.4), V(5.0, 0, 34.5 + b * 0.4)]
    hc = V(8.0, 0, 40.5 + b * 0.4)
    H = head_R(head_yaw, head_pitch, head_roll)
    legs = []
    for side, sy in (('L', 1), ('R', -1)):
        sh = V(3.0, 5.0 * sy, 25.0); paw_ = V(6.8, 5.8 * sy, 2.6); el = V(5.2, 5.6 * sy, 13.0)
        if paw is not None and side == 'L':
            el, paw_ = paw
        legs.append(('F' + side, [sh, el, paw_], [3.8, 3.1, 3.0]))
        legs.append(('H' + side, [V(-4.0, 7.6 * sy, 6.5), V(-0.5, 7.9 * sy, 3.6), V(2.5, 7.6 * sy, 2.5)], [4.2, 3.4, 3.2]))
    thighs = [(f'thigh{s}', (V(-6.5, 6.6 * sy, 9.0), roty(-0.2) @ rotz(0.15 * sy), V(9.2, 4.8, 7.4))) for s, sy in (('L', 1), ('R', -1))]
    tail = _tail_wrap(V(-16.5, 0, 4.0), 1, 2.6, flick)
    return dict(spine=spine, spine_r=spine_r, neck=neck, neck_r=[7.4, 6.6], head_c=hc, head_R=H, legs=legs, thighs=thighs, back_up=V(-0.95, 0, 0.3),
                neck_up=V(-0.6, 0, 0.8), tail=tail, tail_r=[3.5, 3.2, 3.0, 2.9, 2.8, 2.6], tail_up=V(0, 0, 1), eyes=eyes,
                paw_dir={'HL': V(1, 0.1, 0), 'HR': V(1, -0.1, 0)})

def groom(k):
    """k: 0 raise, 1 lick a, 2 lick b, 3 rub"""
    paws = [(V(7.0, 5.0, 17.0), V(9.5, 3.5, 24.0)), (V(8.0, 5.0, 20.0), V(10.5, 2.5, 30.5)), (V(8.0, 5.0, 20.5), V(10.5, 2.5, 31.5)), (V(7.0, 5.5, 22.0), V(8.0, 4.0, 37.0))]
    hp = [0.15, 0.40, 0.25, 0.10]; hy = [0.5, 0.75, 0.7, 0.85]; hr = [0.0, -0.15, -0.1, -0.35]
    eyes = ['half', 'closed', 'closed', 'closed']
    return sit(eyes=eyes[k], head_yaw=hy[k], head_pitch=hp[k], head_roll=hr[k], paw=paws[k])

def lookup(k):
    return sit(eyes='open', head_yaw=0.35, head_pitch=-0.45 - 0.05 * k, ears=0.6, breath=k * 0.5)

def sleep(breath=0.0, ear_twitch=0.0):
    b = breath; R0 = 11.0
    ang = np.radians([-150, -105, -60, -15])
    spine = [V(R0 * np.cos(a), R0 * np.sin(a), 8.5 + b * 0.5) for a in ang]
    spine_r = [11.0, 11.8 + b * 0.4, 11.2, 10.0]
    na = np.radians([5, 28])
    neck = [V(R0 * 0.9 * np.cos(a), R0 * 0.9 * np.sin(a), 8.0) for a in na]
    ha = np.radians(42)
    hc = V(12.5 * np.cos(ha) + 1.0, 12.5 * np.sin(ha), 10.5 + b * 0.3)
    # head lies on its chin, facing outward-front (toward +x+y), slightly toward camera
    H = head_R(0.80, 0.30, 0.25)
    legs = [('FL', [V(12, 3, 5), V(17, 5, 3.4), V(20.5, 8.0, 2.6)], [3.8, 3.4, 3.2]),
            ('FR', [V(13, 0, 4.5), V(18, 1.5, 3.2), V(21.5, 3.5, 2.5)], [3.6, 3.3, 3.1])]
    thighs = [('thighL', (V(-6.5, -8.5, 9.0), rotz(np.radians(-130)), V(9.4, 5.8, 8.0)))]
    ta = np.radians([-160, -125, -85, -45, -5, 25, 48])
    tail = [V(21.5 * np.cos(a) + 0.5, 21.5 * np.sin(a), 3.6) for a in ta]
    tail[0] = V(R0 * np.cos(np.radians(-160)) - 1, R0 * np.sin(np.radians(-160)) - 1, 6.0)
    return dict(spine=spine, spine_r=spine_r, neck=neck, neck_r=[8.0, 7.4], head_c=hc, head_R=H, legs=legs, thighs=thighs,
                back_up=V(0, 0, 1), tail=tail, tail_r=[3.6, 3.5, 3.4, 3.3, 3.1, 3.0, 2.8], tail_up=V(0, 0, 1), eyes='closed',
                paw_dir={'FL': V(0.6, -0.6, 0), 'FR': V(0.6, -0.6, 0)}, head_scale=1.2)

def stretch(k):
    """play bow: k in 0..1 amount, yawn eyes"""
    a = k
    zr = 22.5 + 2.0 * a; zc = 22.5 - 9.5 * a
    spine = [V(-16.5 + 1.5 * a, 0, zr), V(-6, 0, (zr * 0.62 + zc * 0.38) + 0.5), V(5 + 1.5 * a, 0, zc * 0.8 + zr * 0.2 + 0.6), V(12 + 3 * a, 0, zc + 1.6)]
    neck = [V(13 + 3 * a, 0, zc + 3), V(18.5 + 3.5 * a, 0, zc + 9.5 - 1.5 * a)]
    hc = V(22.5 + 4.5 * a, 0, zc + 16.0 - 3.0 * a)
    H = head_R(0.35, -0.15 * a)
    legs = []
    for side, sy in (('L', 1), ('R', -1)):
        sh = V(11 + 3 * a, 5.4 * sy, zc - 3.0); paw = V(12.5 + 11 * a, 5.3 * sy, 2.6); el = V(14 + 7 * a, 5.4 * sy, 2.6 + 6 * (1 - a) + 2.5 * a)
        legs.append(('F' + side, [sh, el, paw], [4.4, 3.7, 3.4]))
        hip = V(-14 + 1.5 * a, 6.0 * sy, zr - 6.5); paw = V(-15.5, 5.8 * sy, 2.6)
        knee = hip + V(3.0, 0, -4.5 - 2 * a); hock = V(paw[0] - 3.6, 5.9 * sy, paw[2] + 7.0 + 2 * a)
        legs.append(('H' + side, [knee, hock, paw], [4.8, 3.6, 3.3]))
    thighs = [(f'thigh{s}', (V(-13.5 + 1.5 * a, 6.0 * sy, zr - 3.5), roty(-0.5), V(7.6, 4.3, 8.4))) for s, sy in (('L', 1), ('R', -1))]
    zb = zr
    tail = [V(-24 + 1.5 * a, 0, zb + 2.5), V(-28, 0.8, zb + 8 + 2 * a), V(-30, 1.6, zb + 15 + 3 * a), V(-29, 2.4, zb + 22 + 3 * a), V(-25.5, 2.6, zb + 27 + 2 * a)]
    eyes = 'closed' if a > 0.8 else 'open'
    return dict(spine=spine, spine_r=[9.6, 10.0, 9.8, 9.0], neck=neck, neck_r=[7.6, 6.8], head_c=hc, head_R=H, legs=legs, thighs=thighs,
                tail=tail, tail_r=[3.7, 3.3, 3.1, 3.0, 2.8], tail_up=V(1, 0, 0.3), eyes=eyes)

def jump(k):
    """0 crouch, 1 launch, 2 tuck (air), 3 land"""
    if k == 0:
        P = stand(head_yaw=0.2); P = _shift_body(P, dz=-4.5, legs_bend=True); return P
    if k == 3:
        P = stand(head_yaw=0.2); P = _shift_body(P, dz=-2.5, legs_bend=True); return P
    P = stretch(0.0)
    pitch = -0.32 if k == 1 else 0.0
    R = roty(pitch)
    c0 = V(-2, 0, 20)
    tr = lambda p: c0 + R @ (np.asarray(p) - c0) + V(0, 0, 6 if k == 1 else 9)
    P['spine'] = [tr(p) for p in P['spine']]; P['neck'] = [tr(p) for p in P['neck']]; P['head_c'] = tr(P['head_c'])
    P['head_R'] = R @ P['head_R']
    legs = []
    for nm, pts, rr in P['legs']:
        pts = [tr(p) for p in pts]
        if k == 1:
            if nm[0] == 'F': pts = [pts[0], pts[0] + V(5, 0, -4), pts[0] + V(10, 0, -5)]
            else: pts = [pts[0], pts[0] + V(-6, 0, -6), pts[0] + V(-12, 0, -9)]
        else:
            if nm[0] == 'F': pts = [pts[0], pts[0] + V(4, 0, -5), pts[0] + V(6, 0, -9)]
            else: pts = [pts[0], pts[0] + V(4, 0, -5), pts[0] + V(1, 0, -9)]
        legs.append((nm, pts, rr))
    P['legs'] = legs
    P['thighs'] = [(nm, (tr(cc), R @ RR, rad)) for nm, (cc, RR, rad) in P['thighs']]
    P['tail'] = [tr(p) for p in P['tail']]
    if k == 1: P['tail'] = [P['tail'][0]] + [P['tail'][0] + V(-5.5 * i, 0, -1.5 * i * (i - 1) * 0.3 + 1.2 * i) for i in range(1, 5)]
    P['paw_dir'] = {'HL': V(-0.6, 0, -0.8), 'HR': V(-0.6, 0, -0.8)} if k == 1 else {}
    P['eyes'] = 'open'
    return P

def _shift_body(P, dz, legs_bend):
    sh = lambda p: np.asarray(p) + V(0, 0, dz)
    P['spine'] = [sh(p) for p in P['spine']]; P['neck'] = [sh(p) for p in P['neck']]; P['head_c'] = sh(P['head_c'])
    P['thighs'] = [(nm, (sh(cc), RR, rad)) for nm, (cc, RR, rad) in P['thighs']]
    P['tail'] = [sh(p) for p in P['tail']]
    legs = []
    for nm, pts, rr in P['legs']:
        a, b, c = pts
        a = sh(a); b = sh(b) + (V(-3, 0, 0) if nm[0] == 'F' else V(-2, 0, 0))
        legs.append((nm, [a, b, c], rr))
    P['legs'] = legs
    return P

ACTIONS = {
    'idle':    dict(fps=4, loop=True,  poses=lambda: [stand(breath=0, tail=-0.5), stand(breath=0.5, tail=0.0), stand(breath=1, tail=0.5, eyes='closed'), stand(breath=0.5, tail=0.0)]),
    'walk':    dict(fps=8, loop=True,  poses=lambda: [stand(walk=i / 6, tail=0.25 * np.sin(2 * np.pi * i / 6), head_yaw=0.2) for i in range(6)]),
    'sit':     dict(fps=3, loop=True,  poses=lambda: [sit(breath=0, flick=0), sit(breath=0.5, flick=0.6), sit(breath=1, flick=1.0, eyes='closed'), sit(breath=0.5, flick=0.4)]),
    'groom':   dict(fps=4, loop=True,  poses=lambda: [groom(0), groom(1), groom(2), groom(1), groom(2), groom(3)]),
    'lookup':  dict(fps=3, loop=True,  poses=lambda: [lookup(0), lookup(1)]),
    'sleep':   dict(fps=2, loop=True,  poses=lambda: [sleep(0), sleep(0.5), sleep(1.0), sleep(0.5)]),
    'stretch': dict(fps=4, loop=False, poses=lambda: [stretch(0.35), stretch(0.8), stretch(1.0), stretch(0.5)]),
    'jump':    dict(fps=8, loop=False, poses=lambda: [jump(0), jump(1), jump(2), jump(3)]),
}
