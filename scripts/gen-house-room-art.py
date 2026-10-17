#!/usr/bin/env python3
"""处理各房间模块源图 → Resources/House/*-base.png + *-anchors.json"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets/house"
OUT_DIR = ROOT / "Sources/MijiaBarApp/Resources/House"
TARGET_W = 640

# 归一化锚点（换构图后在此改）
ANCHORS: dict[str, dict] = {
    "living-room": {
        "lamps": [{"x": 0.178, "y": 0.31}],
        "tv": {"x": 0.628, "y": 0.295, "w": 0.21, "h": 0.245},
        "window": {"x": 0.43, "y": 0.038, "w": 0.26, "h": 0.31},
    },
    "bedroom": {
        "lamps": [{"x": 0.22, "y": 0.34}, {"x": 0.72, "y": 0.42}],
        "ac": {"x": 0.52, "y": 0.12, "w": 0.18, "h": 0.12},
        "window": {"x": 0.08, "y": 0.05, "w": 0.22, "h": 0.28},
    },
    "study": {
        "lamps": [{"x": 0.62, "y": 0.38}],
        "tv": {"x": 0.38, "y": 0.32, "w": 0.22, "h": 0.18},
        "window": {"x": 0.72, "y": 0.06, "w": 0.22, "h": 0.26},
    },
    "generic": {
        "lamps": [{"x": 0.55, "y": 0.28}],
        "window": {"x": 0.78, "y": 0.1, "w": 0.14, "h": 0.22},
    },
}

ROOMS = [
    ("living-room", "living-room-base-src.jpg"),
    ("bedroom", "bedroom-base-src.jpg"),
    ("study", "study-base-src.jpg"),
    ("generic", "generic-base-src.jpg"),
]


def load_source(path: Path) -> Image.Image:
    im = Image.open(path).convert("RGBA")
    m = 0.02
    return im.crop((int(im.width * m), int(im.height * m), int(im.width * (1 - m)), int(im.height * (1 - m))))


def pixelize(im: Image.Image, width: int) -> Image.Image:
    ratio = width / im.width
    height = max(1, int(im.height * ratio))
    mid = im.resize((width // 2, height // 2), Image.Resampling.LANCZOS)
    mid = ImageEnhance.Brightness(mid).enhance(0.92)
    mid = ImageEnhance.Contrast(mid).enhance(1.06)
    return mid.resize((width, height), Image.Resampling.NEAREST).filter(ImageFilter.SHARPEN)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for prefix, src_name in ROOMS:
        src = ASSETS / src_name
        if not src.is_file():
            raise SystemExit(f"missing {src}")
        im = pixelize(load_source(src), TARGET_W)
        im.save(OUT_DIR / f"{prefix}-base.png", optimize=True)
        meta = {"size": [im.width, im.height], **ANCHORS[prefix]}
        (OUT_DIR / f"{prefix}-anchors.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
        print(f"{prefix}: {im.width}x{im.height}")


if __name__ == "__main__":
    main()
