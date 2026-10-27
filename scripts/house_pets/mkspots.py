"""blocks.json + spots_src.json -> pet-spots.json (walk grids per art set/module)."""
from pathlib import Path
import json, numpy as np
from walkgrid import DIRS, N, R
from occluders import populate
blocks = json.load(open(str(Path(__file__).with_name('blocks.json'))))
spots = json.load(open(str(Path(__file__).with_name('spots_src.json'))))
out = dict(schema=1, cellsPerGrid=N, artSets={'cozy-wood': 'cozy', 'light-wood': 'cozy', 'walnut': 'cozy', 'japanese': 'japanese', 'modern': 'modern'},
           note="walk[row v][col u]: '.' walkable floor, '#' blocked. Cell centre uv = ((col+0.5)/8, (row+0.5)/8) in module floor grid units; "
                "module px = tip + (160*(u-v), 66*(u+v) - z). Spots: at=[u,v] floor units, z = px above floor (perches), from=[col,row] walk cell to jump from.",
           sets={})
for st in ('cozy', 'japanese', 'modern'):
    cat = json.load(open(DIRS[st] / 'catalog.json')); S = {}
    for mid, art in cat['modules'].items():
        fu, fv = art['footprint']; W, H = fu * N, fv * N
        open_ = np.ones((H, W), bool); open_[:, 0] = False; open_[0, :] = False
        bl = blocks.get(st, {}).get(mid)
        if bl is None: bl = blocks.get('cozy', {}).get(mid, [])
        for r in bl:
            j0, i0, j1, i1 = r; open_[i0:i1, j0:j1] = False
        sp = spots.get(st, {}).get(mid) or spots.get('cozy', {}).get(mid, [])
        S[mid] = dict(grid=[W, H], walk=[''.join('.' if open_[i, j] else '#' for j in range(W)) for i in range(H)], spots=sp)
    out['sets'][st] = S
populate(out)
json.dump(out, open(R / 'Sources/MijiaBarApp/Resources/House/pets/pet-spots.json', 'w'), indent=1)
print('ok')
