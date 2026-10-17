#!/usr/bin/env python3
"""本地预览 night/off 叠光（无 macOS Swift 时用）。输出到 docs/house-pilot/。"""
from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "Sources/MijiaBarApp/Resources/House/living-room-base.png"
ANCHORS = ROOT / "Sources/MijiaBarApp/Resources/House/living-room-anchors.json"
OUT = ROOT / "docs/house-pilot"


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


def compose(lighting: str) -> Image.Image:
    base = Image.open(BASE).convert("RGBA")
    w, h = base.size
    a = json.loads(ANCHORS.read_text())
    lamp = a["lamp"]
    tv = a["tvScreen"]
    win = a["window"]
    cozy = 1.0 if lighting == "night" else 0.1
    lamp_k = 1.0 if lighting == "night" else 0.0
    tv_k = 1.0 if lighting == "night" else 0.0

    out = base.copy()
    # moon
    wx = (win["x"] + win["w"] / 2) * w
    wy = (win["y"] + win["h"] / 2) * h
    moon = radial(w, h, wx, wy, win["w"] * w * 0.55, (140, 185, 220, int(90 * (0.35 + cozy * 0.25))))
    out = Image.alpha_composite(out, moon)
    if tv_k:
        tx, ty = tv["x"] * w, tv["y"] * h
        tw, th = tv["w"] * w, tv["h"] * h
        screen = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(screen)
        d.rectangle((tx, ty, tx + tw, ty + th), fill=(40, 120, 210, 200))
        out = ImageChops.screen(out, screen)
        glow = radial(w, h, tx + tw / 2, ty + th / 2, tw * 0.9, (80, 160, 255, 140))
        out = Image.alpha_composite(out, glow)
    if lamp_k:
        lx, ly = lamp["x"] * w, lamp["y"] * h
        for r, col in [(70, (255, 190, 110, 160)), (130, (255, 220, 160, 90))]:
            out = Image.alpha_composite(out, radial(w, h, lx, ly, r, col))
    # dim off
    dim = Image.new("RGBA", (w, h), (0, 0, 0, int(255 * (1 - cozy) * 0.72)))
    out = ImageChops.multiply(out, Image.alpha_composite(Image.new("RGBA", (w, h), (255, 255, 255, 255)), dim))
    return out


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name in ("living-room-night", "living-room-off"):
        compose("night" if name.endswith("night") else "off").save(OUT / f"{name}.png", optimize=True)
        print(f"wrote {OUT / f'{name}.png'}")


if __name__ == "__main__":
    main()
