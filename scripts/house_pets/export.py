"""Render all cat frames -> rig sheets (per pattern) + rig json + golden vectors.
python3 export.py OUTDIR [ss]"""
import sys, json, pickle, time, numpy as np
from pathlib import Path
from PIL import Image
from frames import render_frame, cells
import paint as PA, patterns as PT
from cat import ACTIONS

out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
ss = int(sys.argv[2]) if len(sys.argv) > 2 else 5
cache = out / 'frames.pkl'
BBOX = (-54, -70, 54, 24)
if cache.exists() and '--rerender' not in sys.argv:
    FR = pickle.load(open(cache, 'rb'))
else:
    FR = []
    t = time.time()
    for facing in ('SE', 'NE'):
        for name, A in ACTIONS.items():
            for k, P in enumerate(A['poses']()):
                F = render_frame(P, facing, bbox=BBOX, ss=ss)
                FR.append((name, facing, k, F))
        print(facing, time.time() - t, flush=True)
    pickle.dump(FR, open(cache, 'wb'))

enc = {}
for pat in PT.PATTERNS:
    L = []
    for name, facing, k, F in FR:
        C = cells(F, pat); C['region'] = PA.stamp_eyes(F, C)
        L.append(PA.encode(F, C))
    enc[pat] = L
# union bbox over all frames (alpha or shadow)
anyA = np.zeros(enc['solid'][0]['alpha'].shape, bool)
for E in enc['solid']: anyA |= (E['alpha'] > 0) | (E['sha'] > 0)
ys, xs = np.nonzero(anyA); y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
Hc, Wc = y1 - y0, x1 - x0
# anchor (world origin) in padded cell coords: origin at module px (0,0): cell coord = (0 - bbox0)/CELL + 1 (pad)
ax = (0 - BBOX[0]) / 2 + 1 - x0; ay = (0 - BBOX[1]) / 2 + 1 - y0
cols = 8
n = len(FR); rows = (n + cols - 1) // cols
def pack(E):
    r = E['region'][y0:y1, x0:x1].astype(int) + 16 * E['outline'][y0:y1, x0:x1].astype(int)
    g = np.round(E['shade'][y0:y1, x0:x1] / 2 * 255)
    b = np.round(E['spec'][y0:y1, x0:x1] * 255)
    a = np.where(E['alpha'][y0:y1, x0:x1] > 0, 255, np.round(E['sha'][y0:y1, x0:x1] * 255))
    return np.stack([r, g, b, a], -1).clip(0, 255).astype(np.uint8)
sheets = {}
for pat in PT.PATTERNS:
    S = np.zeros((rows * Hc, cols * Wc, 4), np.uint8)
    for i, E in enumerate(enc[pat]):
        r_, c_ = divmod(i, cols); S[r_ * Hc:(r_ + 1) * Hc, c_ * Wc:(c_ + 1) * Wc] = pack(E)
    fn = f'cat-short-{pat}.png'; Image.fromarray(S, 'RGBA').save(out / fn, optimize=True); sheets[pat] = fn
actions = {}
for i, (name, facing, k, F) in enumerate(FR):
    A = actions.setdefault(name, dict(fps=ACTIONS[name]['fps'], loop=ACTIONS[name]['loop'], frames={}))
    A['frames'].setdefault(facing, []).append(i)
rig = dict(schema=1, id='cat-short', species='cat', cellPx=2, frameSize=[int(Wc), int(Hc)], anchor=[float(ax), float(ay)], columns=cols,
           frameCount=n, patterns=PT.PATTERNS, sheets=sheets, actions=actions, mirror={'SW': 'SE', 'NW': 'NE'},
           regions=dict(none=0, base=1, second=2, white=3, under=4, pink=5, iris=6, pupil=7, highlight=8, closed=9, shadow=10, mouth=11),
           encoding='R = region + 16*outline; G = shade*127.5 (shade 0..2); B = spec*255; A = 255 body / ground-shadow alpha (region 10)',
           jumpNote='jump frames are drawn in place (no vertical travel); the renderer adds the arc offset')
(out / 'cat-short.json').write_text(json.dumps(rig, indent=1))
print('frame', Wc, Hc, 'anchor', ax, ay, 'frames', n)
