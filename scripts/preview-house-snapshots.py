#!/usr/bin/env python3
"""预览连通剖面小屋 night/off → docs/house-pilot/"""
from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "Sources/MijiaBarApp/Resources/House"
OUT = ROOT / "docs/house-pilot"
BASE = RES / "house-cutaway-base.png"
ANCHORS = RES / "house-cutaway-anchors.json"


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


def apply_module(out: Image.Image, mod: dict, mode: str) -> Image.Image:
    w, h = out.size
    cozy = 1.0 if mode == "night" else 0.1
    win = mod.get("window")
    if win:
        wx = (win["x"] + win["w"] / 2) * w
        wy = (win["y"] + win["h"] / 2) * h
        out.alpha_composite(radial(w, h, wx, wy, win["w"] * w * 0.55, (140, 185, 220, int(70 * cozy))))
    if mode != "night":
        return out
    tv = mod.get("tv")
    if tv:
        tx, ty, tw, th = tv["x"] * w, tv["y"] * h, tv["w"] * w, tv["h"] * h
        scr = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ImageDraw.Draw(scr).rectangle((tx, ty, tx + tw, ty + th), fill=(40, 120, 210, 200))
        out = ImageChops.screen(out, scr)
        out.alpha_composite(radial(w, h, tx + tw / 2, ty + th / 2, tw, (80, 160, 255, 120)))
    ac = mod.get("ac")
    if ac:
        ax = (ac["x"] + ac["w"] / 2) * w
        ay = (ac["y"] + ac["h"] / 2) * h
        out.alpha_composite(radial(w, h, ax, ay, 55, (100, 180, 255, 130)))
    for lamp in mod.get("lamps", []):
        out.alpha_composite(radial(w, h, lamp["x"] * w, lamp["y"] * h, 85, (255, 200, 120, 120)))
    return out


def compose(mode: str) -> Image.Image:
    meta = json.loads(ANCHORS.read_text())
    out = Image.open(BASE).convert("RGBA")
    for mod in meta["modules"].values():
        out = apply_module(out, mod, mode)
    cozy = 1.0 if mode == "night" else 0.1
    dim = Image.new("RGBA", out.size, (0, 0, 0, int(255 * (1 - cozy) * 0.72)))
    return ImageChops.multiply(out, Image.alpha_composite(Image.new("RGBA", out.size, (255, 255, 255, 255)), dim))


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name in ("house-night", "house-off"):
        compose("night" if name.endswith("night") else "off").save(OUT / f"{name}.png", optimize=True)
        print(OUT / f"{name}.png")


if __name__ == "__main__":
    main()
