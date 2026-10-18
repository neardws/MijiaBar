"""Region codes per pattern from (part name, local coords)."""
import numpy as np
BASE, SECOND, WHITE, UNDER, PINK, IRIS, PUPIL, HILITE, CLOSED, SHADOW, MOUTH = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
PATTERNS = ['solid', 'tabby', 'tabbyWhite', 'bicolor', 'calico', 'colorpoint']

def noise3(a, b, c, seed=0):
    v = (np.sin(a * 1.7 + 0.3 + seed) * np.cos(b * 2.3 - 1.1 + seed * 0.7) + np.sin(c * 1.9 + a * 0.8 + 2.0 + seed * 1.3)
         + 0.6 * np.sin(a * 3.1 - b * 2.2 + c * 1.4 + seed))
    return v

def regions(names, loc, pattern):
    """names: array of part names (str) per sample; loc: (N,3)"""
    n = len(names); r = np.full(n, BASE)
    a, b, c = loc[:, 0], loc[:, 1], loc[:, 2]
    isn = lambda *ks: np.isin(names, ks)
    body, neck, head = isn('body'), isn('neck'), isn('head')
    cheek, muzzle, chin = isn('cheek'), isn('muzzle'), isn('chin')
    ear = isn('earL', 'earR')
    legs = isn('FL', 'FR', 'HL', 'HR'); paws = isn('FLpaw', 'FRpaw', 'HLpaw', 'HRpaw'); thigh = isn('thighL', 'thighR')
    tail = isn('tail')
    # inner ear pink: front face of ear, inside
    inner = ear & (a > 0.25) & (np.abs(b) < 0.62) & (c < 0.78) & (c > 0.08)
    # underside
    belly = (body & (c < -0.45)) | (neck & (c < -0.35))
    chest = (body & (a > 0.72) & (c < 0.05)) | (neck & (c < 0.1))
    face_low = (muzzle | chin) | (cheek & (c < -0.05)) | (head & (a > 0.62) & (c < -0.2))
    socks = paws | (legs & (a > 0.72))
    white_tw = face_low | chest | belly | paws          # tabby & white
    white_bi = white_tw | (legs & (a > 0.5)) | (head & (a > 0.6) & (np.abs(b) < 0.22) & (c < 0.5)) | (body & (c < -0.15) & (a > 0.45))
    if pattern in ('solid',):
        pass
    if pattern in ('tabby', 'tabbyWhite'):
        wob = 0.08 * np.sin(b * 3.0)
        st = body & (np.sin(2 * np.pi * (a * 4.6 + 0.10 * np.abs(b) - 0.12 * c)) > 0.35) & (c > -0.30)
        dors = body & (np.abs(b) < 0.28) & (c > 0.72)
        nk = neck & (np.sin(2 * np.pi * a * 2.0) > 0.5) & (c > -0.2)
        hm = head & (c > 0.52) & (a > 0.0) & ((np.abs(b) < 0.07) | ((np.abs(np.abs(b) - 0.34) < 0.07) & (c > 0.58)))
        chk = (cheek | head) & (np.abs(b) > 0.62) & (np.abs(c + 0.05) < 0.10) & (a < 0.55)
        lg = (legs | thigh) & (np.sin(2 * np.pi * ((a if True else 0) * 3.0)) > 0.45) & ~socks
        th = thigh & (np.sin(2 * np.pi * (c * 1.6 + a * 0.6)) > 0.4)
        tl = tail & ((np.sin(2 * np.pi * a * 5.0) > 0.15) | (a > 0.9))
        r[st | dors | nk | hm | chk | lg | th | tl] = SECOND
        r[belly & (pattern == 'tabby')] = UNDER
        if pattern == 'tabby':
            r[(muzzle | chin) ] = UNDER
    if pattern == 'tabbyWhite':
        r[white_tw | socks] = WHITE
    if pattern == 'bicolor':
        r[white_bi] = WHITE
    if pattern == 'calico':
        r[:] = WHITE
        bodyish = body | neck | head | cheek | thigh | ear | tail | (legs & (a < 0.5))
        nz = noise3(a * 5.0 + b * 1.0, b * 1.5, c * 1.4 + a * 2, seed=1.3)
        patch = bodyish & ~white_bi
        r[patch & (nz > 0.25)] = BASE
        r[patch & (nz <= 0.25) & (nz > -0.9)] = SECOND
        hd = head | cheek | ear
        r[hd & ~white_bi & (b > 0.0)] = BASE
        r[hd & ~white_bi & (b <= 0.0)] = SECOND
        r[tail] = np.where(np.sin(2 * np.pi * a[tail] * 2.0) > 0, BASE, SECOND)
    if pattern == 'colorpoint':
        pts = ear | muzzle | chin | (cheek & (a > 0.0)) | (head & (a > 0.4) & (c < 0.45)) | tail & (a > 0.25) | paws | (legs & (a > 0.45))
        r[pts] = SECOND
        r[belly] = UNDER
    if pattern == 'parts':
        r[:] = BASE
        r[head | cheek | muzzle | chin] = WHITE; r[ear] = PINK; r[tail] = SECOND; r[legs | paws] = IRIS; r[thigh] = UNDER
        return r
    r[inner] = PINK
    return r
