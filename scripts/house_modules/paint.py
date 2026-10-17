"""按格子画独立剖面房间模块（后墙 + 地板，无前墙）。HD-2D 像素风，色板贴近经典温馨木屋。"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from .grid import FLOOR_H, FLOOR_THICK, PX, W, WALL_H, module_canvas_size, snap, tip_in_module

# 色板（从经典 cutaway 取样的温馨木色）
WOOD_DK = (56, 28, 12)
WOOD_MD = (96, 56, 28)
WOOD_LT = (144, 96, 52)
WOOD_HL = (176, 128, 72)
WALL_DK = (72, 40, 20)
WALL_MD = (110, 70, 38)
WALL_LT = (148, 102, 58)
FLOOR_A = (128, 82, 42)
FLOOR_B = (112, 70, 34)
TRIM = (40, 20, 8)
GREEN = (52, 110, 62)
GREEN_DK = (28, 68, 36)
CREAM = (232, 220, 196)
WHITE = (245, 242, 235)
SKY_DAY = (140, 190, 230)
SKY_NIGHT = (28, 36, 72)
WARM_LIT = (255, 200, 120)
SCREEN_LIT = (120, 180, 255)
COOL_LIT = (160, 220, 255)


def quantize(im: Image.Image) -> Image.Image:
    """强制 2×2 像素格。"""
    a = np.asarray(im)
    h, w = a.shape[:2]
    a = a[: h - h % PX, : w - w % PX]
    small = a.reshape(h // PX, PX, w // PX, PX, -1).mean(axis=(1, 3)).astype(np.uint8)
    big = np.repeat(np.repeat(small, PX, 0), PX, 1)
    return Image.fromarray(big, mode=im.mode)


def diamond(cx, cy, rw, rh):
    return [(cx, cy - rh), (cx + rw, cy), (cx, cy + rh), (cx - rw, cy)]


def draw_iso_box(draw, tip, fw, wall_h, floor_h, thick, wall_color, floor_color, thick_color, edge):
    """从 tip（后墙尖）画一个 fw 格宽的房间：左后墙、右后墙、地板、地板厚度。"""
    tw, th = W // 2 * fw, FLOOR_H // 2  # half-extents of floor diamond for fw cells along col
    # For fw=1: diamond rw=W/2, rh=FLOOR_H/2
    # For fw=2: the floor is a larger diamond spanning 2 cells along the col axis
    if fw == 1:
        rw, rh = W // 2, FLOOR_H // 2
        # tip is back; floor center is tip + (0, rh) in screen? 
        # Back tip of diamond at tip; floor points:
        back = tip
        right = (tip[0] + rw, tip[1] + rh)
        front = (tip[0], tip[1] + 2 * rh)
        left = (tip[0] - rw, tip[1] + rh)
    else:
        # 2×1 along col: back tip of left cell = tip; right cell tip = tip+(W/2, FLOOR_H/2)
        # Outer diamond: back-left tip, back-right tip, front-right, front-left
        rw, rh = W // 2, FLOOR_H // 2
        back = tip  # left-back tip of living
        back_r = (tip[0] + W // 2 * (fw - 1) + W // 2, tip[1] + FLOOR_H // 2 * (fw - 1))  # simplified
        # Cleaner: floor is parallelogram
        # left-back tip = tip
        # right-back tip = tip + ((fw)*W/2, (fw-1?)* ...) 
        # For fw cells in a row along +col only (same row):
        # left-back = tip
        # right-back = cell_origin offset for (fw-1, 0) relative = ((fw-1)*W/2, (fw-1)*FLOOR_H/2)
        rb = (tip[0] + (fw - 1) * (W // 2), tip[1] + (fw - 1) * (FLOOR_H // 2))
        # left-front = tip + row forward 1 equivalent within cell: (-W/2, FLOOR_H/2) from left-back... 
        # actually front of left cell: (tip[0], tip[1]+FLOOR_H)
        # right-front = rb + (0, FLOOR_H) relative to rb's back... front of right cell
        left = (tip[0] - W // 2, tip[1] + FLOOR_H // 2)
        right = (rb[0] + W // 2, rb[1] + FLOOR_H // 2)
        front = (tip[0] + (fw - 1) * (W // 2), tip[1] + FLOOR_H + (fw - 1) * (FLOOR_H // 2))
        back = tip
        # For wall: left wall from left-back tip up; right wall from right-back tip
        # Use back spine from tip to rb as the back ridge
        back_r = rb
        # floor polygon
        floor_poly = [back, back_r, right, front, left]
        # Actually for 2-col strip, floor:
        # tips: BL=tip, BR=tip+((fw-1)*(W/2),(fw-1)*(FLOOR_H/2))
        # fronts: FL = tip+(0,FLOOR_H) shifted by left, FR similar
        # Standard: 
        BL = tip
        BR = (tip[0] + fw * (W // 2), tip[1] + (fw - 1) * 0 + 0)  # wrong
        
    # Unified approach: build floor as iso rectangle of fw × 1 cells
    # Cell (0,0) tip at tip; cells (dc,0) for dc in 0..fw-1
    def tip_at(dc, dr):
        return (tip[0] + (dc - dr) * (W // 2), tip[1] + (dc + dr) * (FLOOR_H // 2))

    BL = tip_at(0, 0)
    BR = tip_at(fw, 0)  # tip of cell past the right edge = right point of last cell's back... 
    # Wait tip_at(fw,0) is the back tip of a cell to the right of our footprint.
    # Right point of our floor = midpoint of BR's left and ... 
    # Floor corners of fw×1:
    # back-left tip = tip_at(0,0)
    # back-right tip = tip_at(fw-1, 0) ... no for a continuous floor the back edge goes from tip_at(0,0) to tip_at(fw,0)? 
    # Diamond cells share edges. Outer outline of cells (0..fw-1, 0):
    # - NW tip: tip_at(0,0)
    # - NE tip: tip_at(fw-1, 0) + right offset = tip_at(fw, 0) - actually NE of last cell = tip_at(fw-1,0) + (W/2, FLOOR_H/2) = tip_at(fw, 0) if tip formula matches
    # tip_at(dc,dr) already is tip. Right vertex of cell (fw-1,0) = tip + (W/2, FLOOR_H/2) = tip_at(fw-1,0)+(W/2,FLOOR_H/2)=tip_at(fw,0)
    # Front vertex of cell (fw-1,0) = tip_at(fw-1,0)+(0,FLOOR_H)= tip_at(fw-1,1) relative... tip_at(fw-1,0)+(0,FLOOR_H) = (x, y+FLOOR_H)
    # Left vertex of cell (0,0) = tip_at(0,0)+(-W/2,FLOOR_H/2)=tip_at(-1,0)? tip_at(0,1) no
    # tip_at(dc,dr): x=(dc-dr)*W/2, y=(dc+dr)*FLOOR_H/2 relative to tip
    # left of (0,0): (-W/2, FLOOR_H/2) = tip_at(0,0) + that = same as tip_at(-0.5?) 
    NW = tip_at(0, 0)
    NE = tip_at(fw, 0)  # right tip of last cell along back edge — actually tip_at(fw-1,0)+(W/2,FLOOR_H/2)
    # tip_at(fw, 0) = tip + (fw*W/2, fw*FLOOR_H/2) which for fw=1 is tip+(W/2,FLOOR_H/2)=right vertex. Good for fw=1 NE=right.
    # For fw=2, tip_at(2,0)=tip+(W, FLOOR_H) which is the right vertex of cell 1. Good.
    SE = tip_at(fw, 1)  # front-right: tip_at(fw,0) + forward
    # tip_at(fw,1) = tip + ((fw-1)*W/2, (fw+1)*FLOOR_H/2)
    SW = tip_at(0, 1)  # tip_at(0,1)=tip+(-W/2? (0-1)*W/2, (0+1)*FLOOR_H/2)= tip+(-W/2, FLOOR_H/2) that's LEFT of first cell
    # Front of first cell: tip+(0,FLOOR_H)= tip_at(0,0)+(0,FLOOR_H). tip_at(1,1)=tip+((1-1)*W/2,(1+1)*FLOOR_H/2)=tip+(0,FLOOR_H). 
    # So front-left of footprint ≈ tip_at(0,1) is left, tip_at(1,1) is front of cell0 for fw>=1.
    # Outline: NW, NE, SE(=tip_at(fw,1)?), SW_front
    # For fw=1: NW=tip, NE=tip_at(1,0)=right, SE=tip_at(1,1)=front? tip_at(1,1)=tip+(0,FLOOR_H)=front. SW=tip_at(0,1)=left. Perfect diamond.
    # For fw=2: NW=tip, NE=tip_at(2,0)=tip+(W,FLOOR_H), SE=tip_at(2,1)=tip+(W/2, 1.5*FLOOR_H), SW=tip_at(0,1)=tip+(-W/2,FLOOR_H/2)
    # Missing front-most tip tip_at(1,1)=tip+(0,FLOOR_H). Use pentagon: NW, NE, SE, S, SW where S=tip_at(1,1) for fw=2
    if fw == 1:
        floor = [NW, NE, SE, SW]
    else:
        S = tip_at(fw // 2, 1) if fw == 2 else tip_at(1, 1)
        # For fw=2: tips NW, NE, E-front=tip_at(2,1)? Let's list outer:
        # NW=tip_at(0,0), NE=tip_at(2,0), FR=tip_at(2,1), FL=tip_at(0,1) — FR=tip+(2-1)*W/2,(2+1)*FH/2=tip+(W/2,1.5FH), FL=tip+(-W/2,0.5FH)
        # Front edge needs tip_at(1,1)=tip+(0,FH) in the middle
        floor = [NW, NE, tip_at(fw, 1), tip_at(0, 1)]
        # That skips the front peak for fw=2. Correct outer hull for 2 cells in a row:
        floor = [tip_at(0, 0), tip_at(fw, 0), tip_at(fw, 1), tip_at(0, 1)]
        # tip_at(2,1) and tip_at(0,1) — the front edge is from tip_at(0,1) to tip_at(2,1), and tip_at(1,1) lies on it?
        # tip_at(0,1)=(-W/2, FH/2), tip_at(1,1)=(0,FH), tip_at(2,1)=(W/2, 1.5FH) — not colinear. So use:
        floor = [tip_at(0, 0), tip_at(fw, 0), tip_at(fw, 1), tip_at(1, 1), tip_at(0, 1)] if fw == 2 else [NW, NE, SE, SW]

    # Walls: left back wall (quad from NW up) and right back wall
    wh = wall_h
    left_top = (NW[0], NW[1] - wh)
    # ridge along back: from NW to NE for multi
    # Left wall: NW, SW, SW_up, NW_up — only the left face (NW-SW)
    sw = floor[-1]  # tip_at(0,1)
    sw_up = (sw[0], sw[1] - wh)
    nw_up = (NW[0], NW[1] - wh)
    left_wall = [NW, sw, sw_up, nw_up]

    ne = floor[1]
    # Right wall: for fw=1 NE is right vertex; for fw=2 NE=tip_at(fw,0) is right-back... 
    # Right face from NE to SE (last front-right)
    se = tip_at(fw, 1) if fw >= 1 else SE
    if fw == 1:
        se = SE
        ne = NE
    ne_up = (ne[0], ne[1] - wh)
    se_up = (se[0], se[1] - wh)
    right_wall = [ne, se, se_up, ne_up]

    # Back wall fill (the two faces meeting at ridge) — draw left then right
    # Also fill vertical back from NW to NE along the top of walls
    draw.polygon(left_wall, fill=wall_color)
    draw.polygon(right_wall, fill=tuple(min(255, c + 18) for c in wall_color))

    # Floor
    draw.polygon(floor, fill=floor_color)

    # Floor thickness (front edges)
    thick_pts = []
    front_edge = floor[2:] + [floor[0]]  # messy
    # Drop front vertices by thick
    def drop(p):
        return (p[0], p[1] + thick)

    if fw == 1:
        thick_poly = [SW, SE, drop(SE), drop(SW)]
    else:
        thick_poly = [tip_at(0, 1), tip_at(1, 1), tip_at(fw, 1), drop(tip_at(fw, 1)), drop(tip_at(1, 1)), drop(tip_at(0, 1))]
    draw.polygon(thick_poly, fill=thick_color)

    # Edge outlines
    for poly in (left_wall, right_wall, floor):
        draw.line(poly + [poly[0]], fill=edge, width=PX)

    return {"floor": floor, "left_wall": left_wall, "right_wall": right_wall, "nw": NW, "tip": tip}


def checker_floor(draw, floor_poly, a, b):
    """简单棋盘：在地板包围盒里画小菱形（像素格）。"""
    xs = [p[0] for p in floor_poly]; ys = [p[1] for p in floor_poly]
    # skip — solid floor is fine for spike; stripe with lines
    minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
    for i, x in enumerate(range(minx, maxx, 8 * PX)):
        draw.line([(x, miny), (x - (maxy - miny), maxy)], fill=b if i % 2 == 0 else a, width=PX)


def window(draw, center, w, h, phase):
    x, y = center
    sky = SKY_DAY if phase == "day" else SKY_NIGHT
    draw.rectangle([x - w // 2, y - h // 2, x + w // 2, y + h // 2], fill=sky, outline=TRIM, width=PX)
    draw.line([(x, y - h // 2), (x, y + h // 2)], fill=TRIM, width=PX)
    draw.line([(x - w // 2, y), (x + w // 2, y)], fill=TRIM, width=PX)


def furniture_sofa(draw, at, lit=False):
    x, y = at
    draw.polygon([(x - 36, y), (x + 36, y), (x + 28, y + 18), (x - 28, y + 18)], fill=CREAM, outline=TRIM)
    draw.rectangle([x - 30, y - 14, x + 30, y + 2], fill=GREEN, outline=TRIM)
    draw.rectangle([x - 28, y - 10, x - 8, y], fill=GREEN_DK)
    draw.rectangle([x + 8, y - 10, x + 28, y], fill=GREEN_DK)


def furniture_bed(draw, at):
    x, y = at
    draw.polygon([(x - 40, y), (x + 40, y), (x + 32, y + 22), (x - 32, y + 22)], fill=WOOD_MD, outline=TRIM)
    draw.rectangle([x - 34, y - 8, x + 34, y + 10], fill=GREEN, outline=TRIM)
    draw.rectangle([x - 30, y - 18, x - 10, y - 6], fill=CREAM, outline=TRIM)


def furniture_desk(draw, at):
    x, y = at
    draw.rectangle([x - 40, y - 6, x + 40, y + 14], fill=WOOD_LT, outline=TRIM)
    draw.rectangle([x - 36, y - 28, x - 8, y - 6], fill=(40, 40, 48), outline=TRIM)  # monitor dark
    return (x - 22, y - 18)  # screen center


def furniture_lamp(draw, at, on=False):
    x, y = at
    draw.rectangle([x - 2, y - 40, x + 2, y], fill=TRIM)
    shade = WARM_LIT if on else (200, 180, 140)
    draw.polygon([(x - 14, y - 40), (x + 14, y - 40), (x + 8, y - 28), (x - 8, y - 28)], fill=shade, outline=TRIM)
    return {"id": "floor_lamp", "kind": "lamp", "core": [[x - 14, y - 40], [x + 14, y - 40], [x + 8, y - 28], [x - 8, y - 28]],
            "reveal": [x, y - 10, 70, 50], "shade": [[x - 14, y - 40], [x + 14, y - 40], [x + 8, y - 28], [x - 8, y - 28]]}


def furniture_tv(draw, at, on=False):
    x, y = at
    draw.rectangle([x - 28, y - 4, x + 28, y + 10], fill=WOOD_DK, outline=TRIM)
    screen = SCREEN_LIT if on else (30, 30, 40)
    draw.rectangle([x - 24, y - 36, x + 24, y - 4], fill=screen, outline=TRIM)
    return {"id": "tv", "kind": "screen", "core": [[x - 24, y - 36], [x + 24, y - 36], [x + 24, y - 4], [x - 24, y - 4]],
            "screen": [[x - 24, y - 36], [x + 24, y - 36], [x + 24, y - 4], [x - 24, y - 4]],
            "reveal": [x, y - 20, 60, 40]}


def furniture_ac(draw, at, on=False):
    x, y = at
    body = COOL_LIT if on else (200, 200, 210)
    draw.rounded_rectangle([x - 28, y - 12, x + 28, y + 8], radius=4, fill=body, outline=TRIM)
    return {"id": "ac", "kind": "ac", "core": [[x - 28, y - 12], [x + 28, y - 12], [x + 28, y + 8], [x - 28, y + 8]],
            "reveal": [x, y, 40, 30]}


def furniture_sconce(draw, at, on=False):
    x, y = at
    shade = WARM_LIT if on else (190, 170, 130)
    draw.ellipse([x - 10, y - 10, x + 10, y + 6], fill=shade, outline=TRIM)
    return {"id": "sconce", "kind": "lamp", "core": [[x - 10, y - 10], [x + 10, y - 10], [x + 10, y + 6], [x - 10, y + 6]],
            "reveal": [x, y, 50, 40], "shade": [[x - 10, y - 10], [x + 10, y - 10], [x + 10, y + 6], [x - 10, y + 6]]}


def furniture_ceiling(draw, at, on=False):
    x, y = at
    shade = WARM_LIT if on else (180, 170, 150)
    draw.ellipse([x - 16, y - 8, x + 16, y + 4], fill=shade, outline=TRIM)
    return {"id": "ceiling", "kind": "ceiling", "core": [[x - 16, y - 8], [x + 16, y - 8], [x + 16, y + 4], [x - 16, y + 4]],
            "reveal": [x, y + 20, 80, 50]}


def furniture_bedside(draw, at, on=False):
    return furniture_sconce(draw, at, on) | {"id": "bedside"}  # type: ignore


def furniture_monitor(draw, at, on=False):
    x, y = at
    screen = SCREEN_LIT if on else (30, 30, 40)
    draw.rectangle([x - 20, y - 24, x + 20, y + 2], fill=screen, outline=TRIM)
    return {"id": "monitor", "kind": "screen", "screen": [[x - 20, y - 24], [x + 20, y - 24], [x + 20, y + 2], [x - 20, y + 2]],
            "core": [[x - 20, y - 24], [x + 20, y - 24], [x + 20, y + 2], [x - 20, y + 2]],
            "reveal": [x, y - 10, 45, 35]}


def furniture_entry_light(draw, at, on=False):
    return furniture_ceiling(draw, at, on) | {"id": "entry_light"}


def bake_glow(base: Image.Image, pools: list[tuple], phase: str) -> Image.Image:
    """在 lit 图上叠暖光 / 冷光椭圆。pools: (cx,cy,rx,ry,rgb,strength)"""
    arr = np.asarray(base.convert("RGBA"), dtype=np.float32) / 255.0
    h, w = arr.shape[:2]
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    xs = (xs // PX) * PX + PX / 2
    ys = (ys // PX) * PX + PX / 2
    for cx, cy, rx, ry, rgb, strength in pools:
        d = np.sqrt(((xs - cx) / max(rx, 1)) ** 2 + ((ys - cy) / max(ry, 1)) ** 2)
        fall = np.clip(1 - d, 0, 1) ** 1.6 * strength
        if phase == "night":
            fall *= 1.15
        for i in range(3):
            arr[..., i] = np.clip(arr[..., i] + fall * rgb[i] * (1 - arr[..., i] * 0.3), 0, 1)
    out = (arr * 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


# 每个模块：footprint、家具布局（局部坐标，原点=后墙尖在画布内的位置）
MODULE_SPECS = {
    "living": {
        "fw": 2, "fh": 1,
        "fixtures": [
            ("floor_lamp", furniture_lamp, (120, 200)),
            ("sconce", furniture_sconce, (320, 130)),
            ("tv", furniture_tv, (360, 195)),
        ],
        "extra": ["sofa"],
        "badges": [[80, 240], [200, 250], [300, 230], [160, 265]],
        "window": (200, 90, 56, 40),
    },
    "bedroom": {
        "fw": 1, "fh": 1,
        "fixtures": [
            ("bedside", furniture_bedside, (70, 175)),
            ("ac", furniture_ac, (150, 100)),
        ],
        "extra": ["bed"],
        "badges": [[60, 230], [120, 245], [170, 220]],
        "window": (140, 85, 40, 36),
    },
    "study": {
        "fw": 1, "fh": 1,
        "fixtures": [
            ("ceiling", furniture_ceiling, (120, 95)),
            ("monitor", furniture_monitor, (130, 175)),
        ],
        "extra": ["desk"],
        "badges": [[50, 230], [110, 250], [175, 235]],
        "window": (160, 80, 40, 36),
    },
    "generic": {
        "fw": 1, "fh": 1,
        "fixtures": [("entry_light", furniture_entry_light, (120, 100))],
        "extra": ["door"],
        "badges": [[60, 235], [120, 250], [175, 230]],
        "window": None,
    },
    "kitchen": {
        "fw": 1, "fh": 1,
        "fixtures": [("ceiling", furniture_ceiling, (120, 95))],
        "extra": ["counter"],
        "badges": [[55, 235], [120, 250], [175, 230]],
        "window": (150, 85, 36, 32),
    },
    "bathroom": {
        "fw": 1, "fh": 1,
        "fixtures": [("ceiling", furniture_ceiling, (120, 95))],
        "extra": ["bath"],
        "badges": [[55, 235], [120, 250], [175, 230]],
        "window": (150, 90, 28, 28),
    },
    "balcony": {
        "fw": 1, "fh": 1,
        "fixtures": [("ceiling", furniture_ceiling, (120, 100))],
        "extra": ["rail"],
        "badges": [[55, 235], [120, 250], [175, 230]],
        "window": None,
    },
}


def paint_module(module_id: str, phase: str, lit: bool) -> tuple[Image.Image, dict]:
    spec = MODULE_SPECS[module_id]
    fw, fh = spec["fw"], spec["fh"]
    mw, mh = module_canvas_size(fw, fh)
    tip_local = (0 if fw == 1 else 0, WALL_H)  # tip_in_module
    # For fw=2, tip at left-back; canvas width 480
    tip_local = tip_in_module(fw, fh)
    # Adjust tip_in_module for fw=2: currently returns (0, WALL_H) — good (left-back tip)

    im = Image.new("RGBA", (mw, mh), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)

    wall = WALL_MD if phase == "day" else WALL_DK
    floor = FLOOR_A if phase == "day" else tuple(max(0, c - 30) for c in FLOOR_A)
    thick = WOOD_DK
    edge = TRIM

    geo = draw_iso_box(draw, tip_local, fw, WALL_H, FLOOR_H, FLOOR_THICK, wall, floor, thick, edge)

    # extras
    cx = tip_local[0] + fw * W // 2
    cy = tip_local[1] + FLOOR_H // 2 + 20
    if "sofa" in spec["extra"]:
        furniture_sofa(draw, (tip_local[0] + 140, tip_local[1] + 150))
    if "bed" in spec["extra"]:
        furniture_bed(draw, (tip_local[0] + 110, tip_local[1] + 155))
    if "desk" in spec["extra"]:
        furniture_desk(draw, (tip_local[0] + 120, tip_local[1] + 165))
    if "door" in spec["extra"]:
        x, y = tip_local[0] + 130, tip_local[1] + 40
        draw.rectangle([x - 18, y, x + 18, y + 70], fill=WOOD_MD, outline=TRIM)
    if "counter" in spec["extra"]:
        x, y = tip_local[0] + 90, tip_local[1] + 160
        draw.rectangle([x - 50, y - 10, x + 50, y + 16], fill=(180, 180, 185), outline=TRIM)
        draw.rectangle([x + 20, y - 28, x + 48, y - 10], fill=(60, 60, 70), outline=TRIM)  # range
    if "bath" in spec["extra"]:
        x, y = tip_local[0] + 100, tip_local[1] + 165
        draw.ellipse([x - 36, y - 8, x + 36, y + 22], fill=(200, 210, 220), outline=TRIM)
    if "rail" in spec["extra"]:
        x, y = tip_local[0] + 40, tip_local[1] + 200
        draw.line([(x, y), (x + 160, y - 40)], fill=TRIM, width=PX * 2)

    if spec.get("window"):
        wx, wy, ww, wh = spec["window"]
        window(draw, (tip_local[0] + wx, tip_local[1] + wy - WALL_H // 2), ww, wh, phase)

    fixtures_meta = []
    pools = []
    for fid, painter, (fx, fy) in spec["fixtures"]:
        meta = painter(draw, (tip_local[0] + fx, tip_local[1] + fy), on=lit)
        meta["id"] = fid
        fixtures_meta.append(meta)
        if lit and "reveal" in meta:
            cx, cy, rx, ry = meta["reveal"]
            rgb = WARM_LIT if meta.get("kind") != "screen" and meta.get("kind") != "ac" else (
                SCREEN_LIT if meta.get("kind") == "screen" else COOL_LIT)
            rgb = tuple(c / 255 for c in rgb)
            pools.append((cx, cy, rx, ry, rgb, 0.55 if phase == "night" else 0.35))

    im = quantize(im)
    if lit and pools:
        im = quantize(bake_glow(im, pools, phase))

    # region = floor poly
    region = [[int(p[0]), int(p[1])] for p in geo["floor"]]
    label = [tip_local[0] + 20, tip_local[1] - 20]
    badges = [[tip_local[0] + bx, tip_local[1] + by] for bx, by in spec["badges"]]

    meta = {
        "id": module_id,
        "footprint": [fw, fh],
        "size": [mw, mh],
        "tip": [tip_local[0], tip_local[1]],
        "region": region,
        "label": label,
        "badges": badges,
        "lights": [],
    }
    for m in fixtures_meta:
        light = {"id": m["id"], "kind": m.get("kind", "lamp"), "role": "light",
                 "reveal": m.get("reveal"), "shade": m.get("shade"), "screen": m.get("screen"), "core": m.get("core")}
        meta["lights"].append(light)
    return im, meta


def generate_all(out_dir: Path, modules: list[str] | None = None) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    catalog = {"schema": 2, "style": "cozy-wood", "grid": {"W": W, "FLOOR_H": FLOOR_H, "WALL_H": WALL_H, "FLOOR_THICK": FLOOR_THICK, "PX": PX}, "modules": {}}
    for mid in modules or list(MODULE_SPECS):
        entry = {"footprint": MODULE_SPECS[mid]["fw"], "variants": {}}
        meta = None
        for phase in ("day", "night"):
            for lit_name, lit in (("unlit", False), ("lit", True)):
                im, meta = paint_module(mid, phase, lit)
                name = f"module-{mid}-{phase}-{lit_name}.png"
                im.save(out_dir / name, optimize=True)
                entry["variants"][f"{phase}-{lit_name}"] = name
        assert meta
        entry.update({k: meta[k] for k in ("size", "tip", "region", "label", "badges", "lights", "footprint")})
        entry["footprint"] = MODULE_SPECS[mid]["fw"], 1
        catalog["modules"][mid] = entry
        (out_dir / f"module-{mid}.json").write_text(json.dumps({k: entry[k] for k in entry if k != "variants"}, indent=2), encoding="utf-8")
        print(f"  {mid}: {meta['size']}")
    (out_dir / "catalog.json").write_text(json.dumps(catalog, indent=2), encoding="utf-8")
    return catalog


if __name__ == "__main__":
    generate_all(Path(__file__).resolve().parents[2] / "assets/house/modules")
