#!/usr/bin/env python3
"""整栋连通剖面小屋：day/night cutaway PNG；锚点见 assets/house/module-lights.json"""
from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SRC_NIGHT = ROOT / "assets/house/house-cutaway-base-src.jpg"
SRC_DAY = ROOT / "assets/house/house-cutaway-day-src.jpg"
OUT_DIR = ROOT / "Sources/MijiaBarApp/Resources/House"
TARGET_W = 960


def pixelize(im: Image.Image, width: int, *, brightness: float = 0.9, contrast: float = 1.08) -> Image.Image:
    ratio = width / im.width
    height = max(1, int(im.height * ratio))
    mid = im.resize((width // 2, height // 2), Image.Resampling.LANCZOS)
    mid = ImageEnhance.Brightness(mid).enhance(brightness)
    mid = ImageEnhance.Contrast(mid).enhance(contrast)
    return mid.resize((width, height), Image.Resampling.NEAREST).filter(ImageFilter.SHARPEN)


def load_cutaway(src: Path, *, brightness: float, contrast: float) -> Image.Image:
    if not src.is_file():
        raise SystemExit(f"missing {src}")
    m = 0.015
    im = Image.open(src).convert("RGBA")
    im = im.crop((int(im.width * m), int(im.height * m), int(im.width * (1 - m)), int(im.height * (1 - m))))
    return pixelize(im, TARGET_W, brightness=brightness, contrast=contrast)


def main() -> None:
    night = load_cutaway(SRC_NIGHT, brightness=0.9, contrast=1.08)
    day = load_cutaway(SRC_DAY, brightness=0.96, contrast=1.05)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    night.save(OUT_DIR / "house-cutaway-night-base.png", optimize=True)
    day.save(OUT_DIR / "house-cutaway-day-base.png", optimize=True)
    shutil.copyfile(OUT_DIR / "house-cutaway-night-base.png", OUT_DIR / "house-cutaway-base.png")
    subprocess.run([str(ROOT / "scripts/sync-house-lights.py")], check=True)
    print(f"cutaway night {night.width}x{night.height}")
    print(f"cutaway day {day.width}x{day.height}")


if __name__ == "__main__":
    main()
