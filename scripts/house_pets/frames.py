"""Render cat frames to cell maps."""
import numpy as np, sys
from sdfcat import render, project, Part, CELL, rotz
from appliance_render import F_W
import patterns as PT
from cat import build

HEAD = {'SE': 0.0, 'NE': -np.pi / 2}

def worldize(cat, yaw):
    R = rotz(yaw)
    parts = [Part(p.name, (lambda f: (lambda q: f(q @ R)))(p.fn), p.k) for p in cat.parts]
    feat = {k: R @ v for k, v in cat.feat.items()}
    return parts, feat

def render_frame(pose, facing='SE', bbox=(-36, -64, 36, 12), ss=6):
    cat = build(pose)
    parts, feat = worldize(cat, HEAD[facing])
    R = render(parts, bbox, ss=ss)
    W, H = R['W'], R['H']
    hit = R['hit']; N = hit.size
    # local coords for patterns: re-evaluate nearest part at hit points
    P = R['P']; hi = np.nonzero(hit.ravel())[0]
    names = np.full(N, '', dtype=object); loc = np.zeros((N, 3))
    best = np.full(len(hi), 1e9)
    for pt in parts:
        d, l, _ = pt.fn(P[hi]); m = d < best; best = np.where(m, d, best)
        names[hi[m]] = pt.name; loc[hi[m]] = l[m]
    depth = np.full(N, np.nan); depth[hi] = P[hi] @ F_W
    out = dict(W=W, H=H, ss=ss, hit=hit, names=names.reshape(hit.shape), loc=loc.reshape(hit.shape + (3,)),
               shade=R['shade'].reshape(hit.shape), spec=R['spec'].reshape(hit.shape), depth=depth.reshape(hit.shape),
               gsh=R['gsh'], feat=feat, eyes=cat.eyes, bbox=bbox, facing=facing)
    return out

def cells(F, pattern):
    W, H, ss = F['W'], F['H'], F['ss']
    hit = F['hit']
    reg = np.zeros(hit.shape, int)
    hm = hit
    reg[hm] = PT.regions(F['names'][hm], F['loc'][hm], pattern)
    blk = lambda a: a.reshape(H, ss, W, ss).swapaxes(1, 2).reshape(H, W, ss * ss)
    hb = blk(hit.astype(float)); cov = hb.mean(-1)
    obj = cov >= 0.45
    rb = blk(reg); counts = np.stack([(rb == k).sum(-1) for k in range(16)], -1); counts[..., 0] = 0
    region = counts.argmax(-1)
    w = hb.sum(-1) + 1e-6
    shade = (blk(np.where(hit, F['shade'], 0)).sum(-1)) / w
    spec = (blk(np.where(hit, F['spec'], 0)).sum(-1)) / w
    dep = np.nanmean(np.where(blk(hit) > 0, blk(np.nan_to_num(F['depth'], nan=0.0)), np.nan), -1) if True else None
    gsh = blk(F['gsh']).mean(-1)
    region[~obj] = 0
    return dict(obj=obj, region=region, shade=shade, spec=spec, depth=dep, gsh=gsh)
