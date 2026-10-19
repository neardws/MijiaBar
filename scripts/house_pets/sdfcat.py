"""Short-hair cat rig: parametric SDF cat, posed per frame, rendered in the house iso camera at cell resolution.
Output per cell: alpha, region code (per pattern), shade, spec. Cell = 2 module px."""
import sys, numpy as np
sys.path.insert(0, str(__import__('pathlib').Path(__file__).resolve().parent.parent / 'house_modules'))
from appliance_render import R_W, DN_W, F_W, SIN_T, COS_T

CELL = 2.0  # module px per cell

def nrm(v): v = np.asarray(v, float); return v / np.linalg.norm(v)
def rotz(a):
    c, s = np.cos(a), np.sin(a); return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1.]])
def roty(a):
    c, s = np.cos(a), np.sin(a); return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
def rotx(a):
    c, s = np.cos(a), np.sin(a); return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])

def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)

def sd_ellip(q, rad):
    rad = np.asarray(rad, float)
    k0 = np.linalg.norm(q / rad, axis=1); k1 = np.linalg.norm(q / (rad * rad), axis=1)
    return k0 * (k0 - 1) / (k1 + 1e-9)

def sd_round_cone(p, a, b, r1, r2):
    """capsule with radius r1 at a, r2 at b; returns d, t along"""
    ba = b - a; l2 = ba @ ba; rr = r1 - r2; a2 = l2 - rr * rr; il2 = 1.0 / l2
    pa = p - a; y = pa @ ba; z = y - l2
    x = pa * l2 - y[:, None] * ba; x2 = (x * x).sum(1); y2 = y * y * l2; z2 = z * z * l2
    k = np.sign(rr) * rr * rr * x2
    d = np.where(np.sign(z) * a2 * z2 > k, np.sqrt(x2 + z2) * il2 - r2,
         np.where(np.sign(y) * a2 * y2 < k, np.sqrt(x2 + y2) * il2 - r1,
                  (np.sqrt(x2 * a2 * il2) + y * rr) * il2 - r1))
    return d, np.clip(y * il2, 0, 1)

class Part:
    """name, sdf fn(p)->(d, local q (N,3), t), blend k"""
    def __init__(s, name, fn, k=3.0, group=None):
        s.name, s.fn, s.k = name, fn, k; s.group = group or name

def ellip_part(name, c, R, rad, k=3.0, group=None):
    c = np.asarray(c, float); R = np.asarray(R, float)
    def fn(p):
        q = (p - c) @ R          # world->local (R columns = local axes in world)
        return sd_ellip(q, rad), q / np.asarray(rad), None
    return Part(name, fn, k, group)

def cone_part(name, a, b, r1, r2, k=3.0, group=None, t0=0.0, t1=1.0):
    a = np.asarray(a, float); b = np.asarray(b, float)
    def fn(p):
        d, t = sd_round_cone(p, a, b, r1, r2)
        return d, p - a, t0 + (t1 - t0) * t
    return Part(name, fn, k, group)

def chain(name, pts, radii, k=2.0, group=None):
    """polyline of round cones, t = normalized arc length"""
    pts = [np.asarray(x, float) for x in pts]
    L = np.cumsum([0] + [np.linalg.norm(pts[i + 1] - pts[i]) for i in range(len(pts) - 1)]); L = L / L[-1]
    return [cone_part(f'{name}{i}', pts[i], pts[i + 1], radii[i], radii[i + 1], k, group or name, L[i], L[i + 1]) for i in range(len(pts) - 1)]

def scene_eval(parts, p, need_info=False):
    d = None; best = np.full(len(p), 1e9); pid = np.zeros(len(p), int)
    for i, pt in enumerate(parts):
        dd, _, _ = pt.fn(p)
        if d is None: d = dd
        else: d = smin(d, dd, pt.k)
        m = dd < best; best = np.where(m, dd, best); pid = np.where(m, i, pid)
    return d, pid

def render(parts, bbox, ss=6, light=(0.50, 0.25, 0.83), steps=110):
    """bbox in module px (x0,y0,x1,y1) relative to foot anchor at world origin. returns per-sample arrays (H*ss, W*ss)"""
    x0, y0, x1, y1 = bbox
    W = int(round((x1 - x0) / CELL)); H = int(round((y1 - y0) / CELL))
    ys, xs = np.mgrid[0:H * ss, 0:W * ss]
    sx = x0 + (xs + .5) * CELL / ss; sy = y0 + (ys + .5) * CELL / ss
    O = sx.reshape(-1, 1) * R_W + sy.reshape(-1, 1) * DN_W + 400 * F_W
    D = -F_W
    # bounding: skip rays far from parts by coarse test
    t = np.zeros(len(O)); hit = np.zeros(len(O), bool); alive = np.ones(len(O), bool)
    for _ in range(steps):
        idx = np.nonzero(alive)[0]
        if not len(idx): break
        dd, _ = scene_eval(parts, O[idx] + t[idx, None] * D)
        t[idx] += np.maximum(dd * 0.9, 0.05)
        h = dd < 0.05; hit[idx[h]] = True; alive[idx[h]] = False
        alive[idx[t[idx] > 800]] = False
    P = O + t[:, None] * D
    N = len(O)
    shade = np.zeros(N); spec = np.zeros(N); pid = np.full(N, -1); nz = np.zeros(N); facing = np.zeros(N)
    L = nrm(light)
    hi = np.nonzero(hit)[0]
    if len(hi):
        p = P[hi]; e = 0.08
        f = lambda q: scene_eval(parts, q)[0]
        n = np.stack([f(p + v * e) - f(p - v * e) for v in np.eye(3)], 1)
        n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-9
        _, ids = scene_eval(parts, p)
        ao = np.ones(len(p))
        for k, h in enumerate((0.6, 1.5, 3.0, 5.0)):
            ao -= (h - np.minimum(f(p + n * h), h)) / h * (0.5 ** k) * 0.36
        ao = np.clip(ao, 0.3, 1)
        # self shadow
        sh = np.ones(len(p)); tt = np.full(len(p), 0.6)
        for _ in range(30):
            act = tt < 60
            if not act.any(): break
            dq = f(p[act] + n[act] * 0.2 + tt[act, None] * L)
            sh[act] = np.minimum(sh[act], np.clip(6 * dq / tt[act], 0, 1)); tt[act] += np.clip(dq, 0.3, 5)
        sh = np.clip(sh, 0, 1)
        dif = np.clip(n @ L, 0, 1)
        dif = (dif * 0.8 + 0.2 * np.clip(n @ L * 0.5 + 0.5, 0, 1) ** 2) * (0.55 + 0.45 * sh)   # wrapped (soft fur)
        hemi = 0.72 + 0.28 * n[:, 2]
        V = F_W
        rim = np.clip(1 - n @ V, 0, 1) ** 3 * np.clip(n[:, 2] * 0.5 + 0.6, 0, 1)
        s = 0.52 * hemi * (0.4 + 0.6 * ao) + 0.70 * dif * (0.6 + 0.4 * ao) + 0.14 * rim
        H_ = nrm(L + V); sp = np.clip(n @ H_, 0, 1) ** 24 * sh * 0.10
        shade[hi] = s; spec[hi] = sp; pid[hi] = ids; nz[hi] = n[:, 2]; facing[hi] = n @ V
    # ground contact shadow
    mi = np.nonzero(~hit)[0]
    gsh = np.zeros(N)
    if len(mi):
        o = O[mi]; tf = -o[:, 2] / D[2]; q = o + tf[:, None] * D
        f = lambda qq: scene_eval(parts, qq)[0]
        Ls = nrm((0.25, 0.12, 1.0))
        s_ = np.ones(len(q)); tt = np.full(len(q), 0.5)
        for _ in range(24):
            act = tt < 70
            if not act.any(): break
            dq = f(q[act] + tt[act, None] * Ls)
            s_[act] = np.minimum(s_[act], np.clip(4 * dq / tt[act], 0, 1)); tt[act] += np.clip(dq, 0.4, 6)
        dq = f(q)
        cao = np.clip(1 - dq / 7, 0, 1) ** 2
        gsh[mi] = np.clip((1 - s_) * 0.42 + cao * 0.35, 0, 0.6)
    return dict(W=W, H=H, ss=ss, hit=hit.reshape(H * ss, W * ss), P=P, pid=pid, shade=shade, spec=spec, nz=nz, facing=facing, gsh=gsh.reshape(H * ss, W * ss))

def project(p):
    """world -> module px relative to origin"""
    X, Y, Z = p
    return np.array([(X - Y) * np.sqrt(.5), (X + Y) * np.sqrt(.5) * SIN_T - Z * COS_T])
