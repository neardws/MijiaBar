#!/usr/bin/env python3
"""预览连通剖面小屋 day/night × on/off（与 Swift HouseRoomLightLayer 相同的蒙版合成）→ docs/house-pilot/"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "Sources/MijiaBarApp/Resources/House"
OUT = ROOT / "docs/house-pilot"


def load(name: str) -> np.ndarray:
    return np.asarray(Image.open(RES / f"{name}.png").convert("RGB"), dtype=np.float32)


def poly(size, pts) -> np.ndarray:
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).polygon([tuple(p) for p in pts], fill=255)
    return np.asarray(m, dtype=np.float32)[..., None] / 255.0


def reveal(light: dict, size) -> np.ndarray | float:
    r = light.get("reveal", "room")
    if r == "room":
        return 1.0
    cx, cy, rx, ry = r
    w, h = size
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt(((xs + 0.5 - cx) / rx) ** 2 + ((ys + 0.5 - cy) / ry) ** 2)
    return np.clip((1 - d) / 0.45, 0, 1)[..., None]


def compose(phase: str, on: bool, scene: dict) -> Image.Image:
    unlit, lit = load(f"house-cutaway-{phase}-unlit"), load(f"house-cutaway-{phase}-lit")
    h, w, _ = unlit.shape
    out = unlit.copy()
    k = 1.0 if on else 0.0
    for name, mod in scene["modules"].items():
        room = poly((w, h), mod["region"])
        for light in mod["lights"]:
            kk = 0.0 if (light["role"] == "ac" and name != "bedroom") else k
            a = room * reveal(light, (w, h)) * kk
            out = out * (1 - a) + lit * a
        for light in mod["lights"]:
            core = light.get("core") or light.get("screen") or light.get("shade")
            kk = 0.0 if (light["role"] == "ac" and name != "bedroom") else k
            if core:
                a = poly((w, h), core) * (1 - kk)
                out = out * (1 - a) + unlit * a
    return Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8), "RGB")


def main() -> None:
    scene = json.loads((RES / "house-cutaway.json").read_text())
    OUT.mkdir(parents=True, exist_ok=True)
    for phase in ("day", "night"):
        for on in (True, False):
            p = OUT / f"house-{phase}-{'on' if on else 'off'}.png"
            compose(phase, on, scene).save(p, optimize=True)
            print(p)


if __name__ == "__main__":
    main()
