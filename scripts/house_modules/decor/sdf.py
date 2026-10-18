"""Decor SDF primitives + renderer wrapper (same camera as scripts/house_modules/appliance_render.py)."""
import sys, numpy as np
sys.path.insert(0, str(__import__('pathlib').Path(__file__).resolve().parents[1]))
import appliance_render as AR
from appliance_render import CZ, R_W, DN_W, F_W, proj, soft_shadow, sd_box, sd_cyl_x, sd_cyl_y, sd_cyl_z, sd_torus_x

def V(*a): return np.array(a, float)
def sd_sphere(p, c, r): return np.linalg.norm(p - c, axis=1) - r
def sd_ellip(p, c, rad):
    q = (p - c) / rad
    k0 = np.linalg.norm(q, axis=1); k1 = np.linalg.norm(q / rad, axis=1)
    return k0 * (k0 - 1) / (k1 + 1e-9)
def frame(d):
    d = np.asarray(d, float); d = d / np.linalg.norm(d)
    up = V(0, 0, 1) if abs(d[2]) < 0.9 else V(1, 0, 0)
    a = np.cross(up, d); a /= np.linalg.norm(a); b = np.cross(d, a)
    return np.stack([d, a, b])          # rows: local x(d), y(a), z(b)
def sd_ellip_dir(p, c, d, rad, roll=None):
    """ellipsoid with local x along d; rad = (along, side, thickness). roll: second axis hint"""
    M = frame(d)
    if roll is not None:
        a = np.cross(np.asarray(roll, float), M[0]); 
        if np.linalg.norm(a) > 1e-6:
            a /= np.linalg.norm(a); b = np.cross(M[0], a); M = np.stack([M[0], b, a])
    q = (p - c) @ M.T
    return sd_ellip(q, V(0, 0, 0), np.asarray(rad, float))
def sd_capsule(p, a, b, r):
    a = np.asarray(a, float); b = np.asarray(b, float)
    pa = p - a; ba = b - a
    h = np.clip((pa @ ba) / (ba @ ba), 0, 1)
    return np.linalg.norm(pa - h[:, None] * ba, axis=1) - r
def sd_cone_z(p, c, r1, r2, h):
    """capped cone along z, base at c (radius r1), top at c+h (radius r2)"""
    q = p - c - V(0, 0, h / 2); hh = h / 2
    qx = np.hypot(q[:, 0], q[:, 1]); qy = q[:, 2]
    k1 = np.array([r2, hh]); k2 = np.array([r2 - r1, 2 * hh])
    cax = qx - np.minimum(qx, np.where(qy < 0, r1, r2)); cay = np.abs(qy) - hh
    t = np.clip(((k1[0] - qx) * k2[0] + (k1[1] - qy) * k2[1]) / (k2 @ k2), 0, 1)
    cbx = qx - k1[0] + k2[0] * t; cby = qy - k1[1] + k2[1] * t
    s = np.where((cbx < 0) & (cay < 0), -1, 1)
    return s * np.sqrt(np.minimum(cax ** 2 + cay ** 2, cbx ** 2 + cby ** 2))
def sd_torus_z(p, c, R, r):
    q = p - c
    return np.hypot(np.hypot(q[:, 0], q[:, 1]) - R, q[:, 2]) - r
def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)

class Scene:
    """parts: list of (fn(p)->d, mat). mats: id -> dict(alb=(r,g,b) or fn(p,n)->(N,3), spec, shin, env, emis)"""
    def __init__(s): s.parts = []; s.mats = {}
    def mat(s, name, alb, spec=0.15, shin=16, env=0.03, emis=0.0):
        s.mats[name] = dict(id=len(s.mats), alb=alb, spec=spec, shin=shin, env=env, emis=emis); return name
    def add(s, fn, mat): s.parts.append((fn, s.mats[mat]['id']))
    def scene(s, p):
        d = np.full(len(p), 1e9); ids = np.zeros(len(p), int)
        for fn, i in s.parts:
            dd = fn(p); m = dd < d; d = np.where(m, dd, d); ids = np.where(m, i, ids)
        return d, ids
    def material(s, p, n, ids):
        alb = np.zeros((len(p), 3)); spec = np.zeros(len(p)); shin = np.ones(len(p)); env = np.zeros(len(p))
        for m in s.mats.values():
            k = ids == m['id']
            if not k.any(): continue
            a = m['alb']
            alb[k] = a(p[k], n[k]) if callable(a) else a
            spec[k] = m['spec']; shin[k] = m['shin']; env[k] = m['env']
        return alb, spec, shin, env
    def emis(s, ids):
        e = np.zeros(len(ids))
        for m in s.mats.values(): e[ids == m['id']] = m['emis']
        return e

def render(sc, bbox1x, T=(0, 0), light=(0.55, 0.30, 0.78), ss=3, shadow_k=0.42, steps=180, wall_plane=True, shadow_tmax=120):
    """like AR.render but also returns emissive fraction map. All at 2x."""
    x0, y0, x1, y1 = bbox1x
    w2, h2 = (x1 - x0) * 2, (y1 - y0) * 2; n = ss
    ys, xs = np.mgrid[0:h2 * n, 0:w2 * n]
    sx = x0 + (xs + .5) / (2 * n) - T[0]; sy = y0 + (ys + .5) / (2 * n) - T[1]
    O = sx.reshape(-1, 1) * R_W + sy.reshape(-1, 1) * DN_W + 600 * F_W
    D = -F_W
    t = np.zeros(len(O)); hit = np.zeros(len(O), bool); alive = np.ones(len(O), bool)
    for _ in range(steps):
        idx = np.nonzero(alive)[0]
        if not len(idx): break
        d, _ = sc.scene(O[idx] + t[idx, None] * D)
        t[idx] += d * 0.8
        h = d < 0.02; hit[idx[h]] = True; alive[idx[h]] = False
        alive[idx[t[idx] > 1400]] = False
    P = O + t[:, None] * D
    rgb = np.zeros((len(O), 3)); em = np.zeros(len(O)); L = np.asarray(light, float); L /= np.linalg.norm(L)
    hidx = np.nonzero(hit)[0]
    if len(hidx):
        p = P[hidx]; e = 0.05
        n_ = np.stack([sc.scene(p + np.array(v) * e)[0] - sc.scene(p - np.array(v) * e)[0] for v in ([1, 0, 0], [0, 1, 0], [0, 0, 1])], 1)
        n_ /= np.linalg.norm(n_, axis=1, keepdims=True) + 1e-9
        _, ids = sc.scene(p)
        alb, spec, shin, envk = sc.material(p, n_, ids)
        ao = np.ones(len(p))
        for k, h in enumerate((0.8, 1.8, 3.2, 5.0)):
            dd, _ = sc.scene(p + n_ * h)
            ao -= (h - np.minimum(dd, h)) / h * (0.5 ** k) * 0.32
        ao = np.clip(ao, 0.25, 1)
        cont = np.clip(np.minimum(p[:, 0], p[:, 2]) / 4, 0, 1) * 0.25 + 0.75
        sh = soft_shadow(sc.scene, p + n_ * 0.3, L)
        dif = np.clip(n_ @ L, 0, 1) * sh
        hemi = 0.5 + 0.5 * n_[:, 2]
        Vv = F_W; Hh = (L + Vv); Hh /= np.linalg.norm(Hh)
        spc = spec * np.clip(n_ @ Hh, 0, 1) ** shin * sh
        Rv = 2 * (n_ @ Vv)[:, None] * n_ - Vv
        env = np.clip(0.55 + 0.45 * Rv[:, 2], 0, 1)[:, None] * np.array([1.0, 0.95, 0.86])
        lit = alb * (0.36 * hemi[:, None] * ao[:, None] + 0.86 * dif[:, None] * (0.6 + 0.4 * ao[:, None])) * cont[:, None]
        lit = lit + spc[:, None] * np.array([1.0, 0.97, 0.9]) + envk[:, None] * env * ao[:, None]
        em_ = sc.emis(ids)
        lit = lit * (1 - em_[:, None]) + alb * em_[:, None]
        rgb[hidx] = lit; em[hidx] = em_
    shadow = np.zeros(len(O))
    midx = np.nonzero(~hit)[0]
    if len(midx):
        o, dvec = O[midx], D
        tw = np.where(np.abs(dvec[0]) > 1e-6, -o[:, 0] / dvec[0], 1e9)
        if not wall_plane: tw = np.full(len(o), -1.0)
        tf = np.where(np.abs(dvec[2]) > 1e-6, -o[:, 2] / dvec[2], 1e9)
        tb = np.where((tw > 0) & ((o + tw[:, None] * dvec)[:, 2] >= 0), tw, tf)
        q = o + tb[:, None] * dvec
        s_ = soft_shadow(sc.scene, q + np.array([0.3, 0, 0.3]), L, k=5, tmax=shadow_tmax)
        dq, _ = sc.scene(q)
        cao = np.clip(1 - dq / 6, 0, 1) ** 2 * 0.55
        shadow[midx] = np.clip((1 - s_) * shadow_k + cao, 0, 0.75)
    def down(a, c): return a.reshape(h2, n, w2, n, c).mean((1, 3))
    return (down(rgb, 3), down(hit.astype(float)[:, None], 1)[..., 0], down(shadow[:, None], 1)[..., 0], down(em[:, None], 1)[..., 0])

def soft_shadow(scene, p, L, k=8, tmax=120):
    res = np.ones(len(p)); t = np.full(len(p), 0.4)
    for _ in range(48):
        act = t < tmax
        if not act.any(): break
        d, _ = scene(p[act] + t[act, None] * L)
        res[act] = np.minimum(res[act], np.clip(k * d / t[act], 0, 1))
        t[act] += np.clip(d, 0.3, 6)
    return np.clip(res, 0, 1)
