#!/usr/bin/env python3
"""预览连通剖面小屋 day/night × on/off（静态 glow PNG + opacity）"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "Sources/MijiaBarApp/Resources/House"
GLOWS = RES / "glows"
OUT = ROOT / "docs/house-pilot"
SCENE = RES / "house-cutaway.json"


def clip_layer(layer: Image.Image, clip: dict) -> Image.Image:
    w, h = layer.size
    x0, y0 = int(clip["x"] * w), int(clip["y"] * h)
    x1, y1 = int((clip["x"] + clip["w"]) * w), int((clip["y"] + clip["h"]) * h)
    mask = Image.new("L", (w, h), 0)
    from PIL import ImageDraw

    ImageDraw.Draw(mask).rectangle((x0, y0, x1, y1), fill=255)
    out = layer.copy()
    out.putalpha(mask)
    return out


def strength(light: dict, phase: str, devices_on: bool) -> float:
    kind = light["kind"]
    active = 1.0 if devices_on else 0.0
    if kind == "window":
        if phase == "day":
            return 0.58 + active * 0.22
        return min(0.48, 0.14 + active * 0.32) if active > 0 else 0.0
    if not devices_on:
        return 0.0
    return 1.0


def paste_boost(layer: Image.Image, light: dict, phase: str, k: float) -> Image.Image:
    if light["kind"] == "window" or k <= 0.35:
        return layer
    boost = 0.52 if phase == "night" else 0.38
    return paste_light(layer, light, phase, k * boost)


def overlay_name(light: dict, phase: str) -> str | None:
    ov = light.get("overlay") or {}
    if light["kind"] == "window":
        return ov.get("imageDay") if phase == "day" else ov.get("imageNight")
    return ov.get("image")


def paste_light(out: Image.Image, light: dict, phase: str, k: float) -> Image.Image:
    if k <= 0.001:
        return out
    name = overlay_name(light, phase)
    if not name:
        return out
    path = GLOWS / f"{name}.png"
    if not path.is_file():
        return out
    glow = Image.open(path).convert("RGBA")
    w, h = out.size
    if light.get("rect"):
        r = light["rect"]
        x0, y0 = int(r["x"] * w), int(r["y"] * h)
        tw, th = int(r["w"] * w), int(r["h"] * h)
        glow = glow.resize((tw, th), Image.Resampling.NEAREST)
        cx, cy = x0 + tw // 2, y0 + th // 2
    else:
        ov = light.get("overlay") or {}
        tw = int((ov.get("w") or 0.1) * w)
        th = int((ov.get("h") or 0.18) * h)
        glow = glow.resize((tw, th), Image.Resampling.NEAREST)
        p = light["at"]
        cx, cy = int(p["x"] * w), int(p["y"] * h)
    alpha = glow.split()[3].point(lambda a: int(a * k))
    glow.putalpha(alpha)
    layer = Image.new("RGBA", out.size, (0, 0, 0, 0))
    layer.paste(glow, (cx - glow.width // 2, cy - glow.height // 2), glow)
    return ImageChops.screen(out, layer)


def compose(phase: str, devices_on: bool) -> Image.Image:
    meta = json.loads(SCENE.read_text())
    base_name = "house-cutaway-day-base.png" if phase == "day" else "house-cutaway-night-base.png"
    out = Image.open(RES / base_name).convert("RGBA")
    for mod in meta["modules"].values():
        layer = Image.new("RGBA", out.size, (0, 0, 0, 0))
        for light in mod["lights"]:
            k = strength(light, phase, devices_on)
            layer = paste_light(layer, light, phase, k)
            layer = paste_boost(layer, light, phase, k)
        layer = clip_layer(layer, mod["clip"])
        out = Image.alpha_composite(out, layer)
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
