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
    wx = (win["x"] + win["w"] / 2) * w
    wy = (win["y"] + win["h"] / 2) * h
    rw = win["w"] * w * 0.42
    return Image.alpha_composite(out, radial(w, h, wx, wy, rw, (158, 198, 228, int(45 * strength))))


def apply_module(out: Image.Image, mod: dict, mode: str) -> Image.Image:
    w, h = out.size
    active = 1.0 if mode == "night" else 0.0
    cozy = 1.0 if mode == "night" else 0.1
    win_s = min(0.32, 0.04 + active * 0.14 + cozy * 0.08)
    if mod.get("window"):
        out = window_glow(out, mod["window"], win_s)
    if mode != "night":
        return out
    tv = mod.get("tv")
    if tv:
        tx, ty, tw, th = tv["x"] * w, tv["y"] * h, tv["w"] * w, tv["h"] * h
        scr = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ImageDraw.Draw(scr).rounded_rectangle((tx, ty, tx + tw, ty + th), radius=3, fill=(70, 140, 210, 95))
        out = ImageChops.screen(out, scr)
        out.alpha_composite(radial(w, h, tx + tw / 2, ty + th / 2, tw * 0.65, (90, 155, 220, 55)))
    ac = mod.get("ac")
    if ac:
        ax, ay, aw, ah = ac["x"] * w, ac["y"] * h, ac["w"] * w, ac["h"] * h
        scr = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ImageDraw.Draw(scr).rounded_rectangle((ax, ay, ax + aw, ay + ah), radius=2, fill=(100, 170, 230, 70))
        out = ImageChops.screen(out, scr)
    for lamp in mod.get("lamps", []):
        out.alpha_composite(radial(w, h, lamp["x"] * w, lamp["y"] * h, 62, (255, 205, 140, 75)))
        out.alpha_composite(radial(w, h, lamp["x"] * w, lamp["y"] * h, 110, (255, 225, 170, 35)))
    return out


def compose(mode: str) -> Image.Image:
    meta = json.loads(ANCHORS.read_text())
    out = Image.open(BASE).convert("RGBA")
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
