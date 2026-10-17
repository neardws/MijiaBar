#!/usr/bin/env python3
"""整栋连通剖面小屋：house-cutaway-base.png + house-cutaway-anchors.json"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/house/house-cutaway-base-src.jpg"
OUT_DIR = ROOT / "Sources/MijiaBarApp/Resources/House"
TARGET_W = 960

# 四室在同一底图上的归一化锚点（左上卧室、右上书房、左下客厅、右下玄关）
CUTAWAY = {
    "size": [TARGET_W, 0],
    "modules": {
        "living": {
            "lamps": [{"x": 0.255, "y": 0.68}, {"x": 0.42, "y": 0.58}],
            "tv": {"x": 0.34, "y": 0.72, "w": 0.12, "h": 0.1},
            "window": {"x": 0.1, "y": 0.52, "w": 0.12, "h": 0.14},
            "label": {"x": 0.06, "y": 0.54},
        },
        "bedroom": {
            "lamps": [{"x": 0.14, "y": 0.3}],
            "ac": {"x": 0.04, "y": 0.08, "w": 0.1, "h": 0.07},
            "window": {"x": 0.18, "y": 0.06, "w": 0.14, "h": 0.12},
            "label": {"x": 0.04, "y": 0.04},
        },
        "study": {
            "lamps": [{"x": 0.58, "y": 0.34}],
            "tv": {"x": 0.6, "y": 0.3, "w": 0.1, "h": 0.08},
            "window": {"x": 0.82, "y": 0.06, "w": 0.12, "h": 0.12},
            "label": {"x": 0.52, "y": 0.04},
        },
        "generic": {
            "lamps": [{"x": 0.78, "y": 0.62}],
            "window": {"x": 0.9, "y": 0.56, "w": 0.06, "h": 0.1},
            "label": {"x": 0.54, "y": 0.54},
        },
    },
}


def pixelize(im: Image.Image, width: int) -> Image.Image:
    ratio = width / im.width
    height = max(1, int(im.height * ratio))
    mid = im.resize((width // 2, height // 2), Image.Resampling.LANCZOS)
    mid = ImageEnhance.Brightness(mid).enhance(0.9)
    mid = ImageEnhance.Contrast(mid).enhance(1.08)
    return mid.resize((width, height), Image.Resampling.NEAREST).filter(ImageFilter.SHARPEN)


def main() -> None:
    if not SRC.is_file():
        raise SystemExit(f"missing {SRC}")
    m = 0.015
    im = Image.open(SRC).convert("RGBA")
    im = im.crop((int(im.width * m), int(im.height * m), int(im.width * (1 - m)), int(im.height * (1 - m))))
    im = pixelize(im, TARGET_W)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    im.save(OUT_DIR / "house-cutaway-base.png", optimize=True)
    meta = dict(CUTAWAY)
    meta["size"] = [im.width, im.height]
    (OUT_DIR / "house-cutaway-anchors.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    print(f"cutaway {im.width}x{im.height}")


if __name__ == "__main__":
    main()
