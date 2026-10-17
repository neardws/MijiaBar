#!/usr/bin/env python3
"""本地预览整栋小屋 night/off（近似 Swift 叠光）。输出 docs/house-pilot/。"""
from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "Sources/MijiaBarApp/Resources/House"
OUT = ROOT / "docs/house-pilot"
MODULES = ["bedroom", "living-room", "study", "generic"]
TILE_W, TILE_H = 320, 180


def load_anchors(prefix: str) -> dict:
    return json.loads((RES / f"{prefix}-anchors.json").read_text())


def radial(w: int, h: int, cx: float, cy: float, r: float, color: tuple[int, int, int, int]) -> Image.Image:
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = layer.load()
    for y in range(h):
        for x in range(w):
            d = math.hypot(x - cx, y - cy) / r
            if d < 1:
                a = int(color[3] * (1 - d) ** 1.8)
                px[x, y] = (color[0], color[1], color[2], a)
    return layer.filter(ImageFilter.GaussianBlur(2))


def tile(prefix: str, mode: str) -> Image.Image:
    base = Image.open(RES / f"{prefix}-base.png").convert("RGBA")
    base = base.resize((TILE_W, TILE_H), Image.Resampling.NEAREST)
    w, h = base.size
    a = load_anchors(prefix)
    cozy = 1.0 if mode == "night" else 0.1
    out = base.copy()
    win = a.get("window")
    if win:
        wx = (win["x"] + win["w"] / 2) * w
        wy = (win["y"] + win["h"] / 2) * h
        out = Image.alpha_composite(out, radial(w, h, wx, wy, win["w"] * w * 0.55, (140, 185, 220, int(70 * cozy))))
    if mode == "night":
        tv = a.get("tv")
        if tv:
            tx, ty, tw, th = tv["x"] * w, tv["y"] * h, tv["w"] * w, tv["h"] * h
            scr = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            ImageDraw.Draw(scr).rectangle((tx, ty, tx + tw, ty + th), fill=(40, 120, 210, 200))
            out = ImageChops.screen(out, scr)
        for lamp in a.get("lamps", []):
            lx, ly = lamp["x"] * w, lamp["y"] * h
            out = Image.alpha_composite(out, radial(w, h, lx, ly, 90, (255, 200, 120, 120)))
        ac = a.get("ac")
        if ac:
            ax = (ac["x"] + ac["w"] / 2) * w
            ay = (ac["y"] + ac["h"] / 2) * h
            out = Image.alpha_composite(out, radial(w, h, ax, ay, 60, (100, 180, 255, 130)))
    dim = Image.new("RGBA", (w, h), (0, 0, 0, int(255 * (1 - cozy) * 0.72)))
    out = ImageChops.multiply(out, Image.alpha_composite(Image.new("RGBA", (w, h), (255, 255, 255, 255)), dim))
    return out


def compose(mode: str) -> Image.Image:
    order = ["bedroom", "study", "living-room", "generic"]
    tiles = [tile(p, mode) for p in order]
    cols, rows = 2, 2
    canvas = Image.new("RGBA", (cols * TILE_W - 12, rows * TILE_H - 10), (16, 18, 28, 255))
    for i, t in enumerate(tiles):
        col, row = i % 2, i // 2
        canvas.alpha_composite(t, (col * (TILE_W - 12) + (4 if row else 0), row * (TILE_H - 10)))
    return canvas


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name in ("house-night", "house-off"):
        compose("night" if name.endswith("night") else "off").save(OUT / f"{name}.png", optimize=True)
        print(OUT / f"{name}.png")
    for prefix, name in [("living-room", "living-room-night"), ("living-room", "living-room-off")]:
        tile(prefix, "night" if "night" in name else "off").save(OUT / f"{name}.png", optimize=True)


if __name__ == "__main__":
    main()
