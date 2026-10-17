#!/usr/bin/env python3
"""处理各房间模块源图 → Resources/House/*-base.png + *-anchors.json"""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets/house"
OUT_DIR = ROOT / "Sources/MijiaBarApp/Resources/House"
TARGET_W = 640

# 锚点由 assets/house/module-lights.json + scripts/sync-house-lights.py 维护

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
        print(f"{prefix}: {im.width}x{im.height}")
    subprocess.run([str(ROOT / "scripts/sync-house-lights.py")], check=True)


if __name__ == "__main__":
    main()
