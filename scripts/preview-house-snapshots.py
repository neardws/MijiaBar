#!/usr/bin/env python3
"""预览连通剖面小屋 night/off → docs/house-pilot/（近似 Swift 叠光强度）"""
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
                a = int(color[3] * (1 - d) ** 2.2)
                px[x, y] = (color[0], color[1], color[2], a)
    return layer.filter(ImageFilter.GaussianBlur(3))


def window_glow(out: Image.Image, win: dict, strength: float) -> Image.Image:
    w, h = out.size
    x0, y0 = int(win["x"] * w), int(win["y"] * h)
    x1, y1 = int((win["x"] + win["w"]) * w), int((win["y"] + win["h"]) * h)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(layer).rectangle((x0, y0, x1, y1), fill=(158, 198, 228, int(38 * strength)))
    return Image.alpha_composite(out, layer.filter(ImageFilter.GaussianBlur(2)))


def screen_bloom(out: Image.Image, rect: dict, alpha: int) -> Image.Image:
    w, h = out.size
    x0, y0 = int(rect["x"] * w), int(rect["y"] * h)
    x1, y1 = int((rect["x"] + rect["w"]) * w), int((rect["y"] + rect["h"]) * h)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle((x0, y0, x1, y1), radius=4, fill=(90, 155, 220, alpha))
    return ImageChops.screen(out, layer.filter(ImageFilter.GaussianBlur(1)))


def apply_module(out: Image.Image, mod: dict, mode: str) -> Image.Image:
    if mode != "night":
        return out
    active = 1.0
    if mod.get("window") and active > 0:
        out = window_glow(out, mod["window"], min(0.22, 0.06 + active * 0.14))
    tv = mod.get("tv")
    if tv:
        out = screen_bloom(out, tv, 72)
    ac = mod.get("ac")
    if ac:
        out = screen_bloom(out, ac, 48)
    for lamp in mod.get("lamps", []):
        w, h = out.size
        out.alpha_composite(radial(w, h, lamp["x"] * w, lamp["y"] * h, 62, (255, 205, 140, 75)))
        out.alpha_composite(radial(w, h, lamp["x"] * w, lamp["y"] * h, 110, (255, 225, 170, 35)))
    return out


def compose(mode: str) -> Image.Image:
    meta = json.loads(ANCHORS.read_text())
    out = Image.open(BASE).convert("RGBA")
    if mode == "night":
        for mod in meta["modules"].values():
            out = apply_module(out, mod, mode)
    cozy = 1.0 if mode == "night" else 0.1
    dim = Image.new("RGBA", out.size, (0, 0, 0, int(255 * (1 - cozy) * 0.8)))
    return ImageChops.multiply(out, Image.alpha_composite(Image.new("RGBA", out.size, (255, 255, 255, 255)), dim))


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name in ("house-night", "house-off"):
        compose("night" if name.endswith("night") else "off").save(OUT / f"{name}.png", optimize=True)
        print(OUT / f"{name}.png")


if __name__ == "__main__":
    main()
