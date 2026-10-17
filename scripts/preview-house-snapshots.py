#!/usr/bin/env python3
"""预览连通剖面小屋 day/night × on/off → docs/house-pilot/（近似 Swift 叠光强度）"""
from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "Sources/MijiaBarApp/Resources/House"
OUT = ROOT / "docs/house-pilot"
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


def window_day(out: Image.Image, win: dict, strength: float) -> Image.Image:
    w, h = out.size
    x0, y0 = int(win["x"] * w), int(win["y"] * h)
    x1, y1 = int((win["x"] + win["w"]) * w), int((win["y"] + win["h"]) * h)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(layer).rectangle((x0, y0, x1, y1), fill=(210, 232, 255, int(95 * strength)))
    return Image.alpha_composite(out, layer.filter(ImageFilter.GaussianBlur(2)))


def window_night(out: Image.Image, win: dict, strength: float) -> Image.Image:
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


def apply_module(out: Image.Image, mod: dict, phase: str, devices_on: bool) -> Image.Image:
    active = 1.0 if devices_on else 0.0
    win = mod.get("window")
    if win:
        if phase == "day":
            out = window_day(out, win, 0.42 + active * 0.18)
        elif active > 0:
            out = window_night(out, win, min(0.22, 0.06 + active * 0.14))
    if not devices_on:
        return out
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


def compose(phase: str, devices_on: bool) -> Image.Image:
    meta = json.loads(ANCHORS.read_text())
    base_name = "house-cutaway-day-base.png" if phase == "day" else "house-cutaway-night-base.png"
    out = Image.open(RES / base_name).convert("RGBA")
    for mod in meta["modules"].values():
        out = apply_module(out, mod, phase, devices_on)
    device_cozy = 1.0 if devices_on else 0.0
    floor = 0.64 if phase == "day" else 0.38
    ambient = min(1.0, max(device_cozy, floor))
    dim_strength = 0.38 if phase == "day" else 0.52
    dim = Image.new("RGBA", out.size, (0, 0, 0, int(255 * (1 - ambient) * dim_strength)))
    return ImageChops.multiply(out, Image.alpha_composite(Image.new("RGBA", out.size, (255, 255, 255, 255)), dim))


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    jobs = [
        ("house-day-on", "day", True),
        ("house-day-off", "day", False),
        ("house-night-on", "night", True),
        ("house-night-off", "night", False),
        ("house-night", "night", True),
        ("house-off", "night", False),
    ]
    for name, phase, on in jobs:
        path = OUT / f"{name}.png"
        compose(phase, on).save(path, optimize=True)
        print(path)


if __name__ == "__main__":
    main()
