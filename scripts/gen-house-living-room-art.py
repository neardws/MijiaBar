#!/usr/bin/env python3
"""将 HD-2D 等距客厅源图处理为 `living-room-base.png`（像素对齐 + 可选锚点自检）。

默认读取仓库内 `assets/house/living-room-base-src.jpg`（可由设计稿或 AI 导出后放入）。
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/house/living-room-base-src.jpg"
OUT = ROOT / "Sources/MijiaBarApp/Resources/House/living-room-base.png"
META = ROOT / "Sources/MijiaBarApp/Resources/House/living-room-anchors.json"
TARGET_W = 640


def load_source(path: Path) -> Image.Image:
    if not path.is_file():
        raise SystemExit(f"missing source image: {path}\nPlace isometric living-room art at assets/house/living-room-base-src.jpg")
    im = Image.open(path).convert("RGBA")
    # 去掉生成图常见的暗角边框（约 2%）
    m = 0.02
    x0, y0 = int(im.width * m), int(im.height * m)
    x1, y1 = int(im.width * (1 - m)), int(im.height * (1 - m))
    return im.crop((x0, y0, x1, y1))


def pixelize(im: Image.Image, width: int) -> Image.Image:
    """先缩到一半做细节，再最近邻放大 — 保持 HD-2D 像素颗粒感。"""
    ratio = width / im.width
    height = max(1, int(im.height * ratio))
    mid = im.resize((width // 2, height // 2), Image.Resampling.LANCZOS)
    # 略压高光，方便叠光层区分 night / off
    mid = ImageEnhance.Brightness(mid).enhance(0.92)
    mid = ImageEnhance.Contrast(mid).enhance(1.06)
    out = mid.resize((width, height), Image.Resampling.NEAREST)
    return out.filter(ImageFilter.SHARPEN)


def write_anchors(w: int, h: int) -> None:
    """与当前底图构图对齐的归一化锚点（手工标定，换图后请同步改这里）。"""
    anchors = {
        "size": [w, h],
        "lamp": {"x": 0.178, "y": 0.31},
        "tvScreen": {"x": 0.628, "y": 0.295, "w": 0.21, "h": 0.245},
        "window": {"x": 0.43, "y": 0.038, "w": 0.26, "h": 0.31},
    }
    META.write_text(json.dumps(anchors, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {META}")


def main() -> None:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else SRC
    im = pixelize(load_source(src), TARGET_W)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    im.save(OUT, optimize=True)
    write_anchors(im.width, im.height)
    print(f"wrote {OUT} ({im.width}x{im.height})")


if __name__ == "__main__":
    main()
