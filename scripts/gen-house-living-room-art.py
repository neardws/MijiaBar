#!/usr/bin/env python3
"""生成客厅小屋试点用的像素底图（living-room-base.png）。nearest-neighbor 放大友好。"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

W, H = 360, 220
OUT = Path(__file__).resolve().parents[1] / "Sources/MijiaBarApp/Resources/House/living-room-base.png"


def rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


# 夜景暖色室内 palette
C = {
    "bg": rgb("#0c1018"),
    "wall": rgb("#2a2430"),
    "wall_hi": rgb("#3d3544"),
    "floor": rgb("#3a2a22"),
    "floor_hi": rgb("#4d382c"),
    "plank": rgb("#2f221c"),
    "trim": rgb("#5c4a3a"),
    "sofa": rgb("#8a6a4a"),
    "sofa_hi": rgb("#a8845e"),
    "sofa_shadow": rgb("#5a4030"),
    "pillow": rgb("#3d6a52"),
    "wood": rgb("#6b4f38"),
    "wood_hi": rgb("#8a6848"),
    "tv_frame": rgb("#1a1a22"),
    "tv_off": rgb("#121820"),
    "tv_stand": rgb("#4a3828"),
    "lamp_shade": rgb("#d8c8a0"),
    "lamp_off": rgb("#8a8070"),
    "lamp_pole": rgb("#5a5a62"),
    "plant": rgb("#3d7a48"),
    "pot": rgb("#6a5040"),
    "window": rgb("#1a2838"),
    "window_glass": rgb("#2a4058"),
    "moon": rgb("#8ab0c8"),
    "rug": rgb("#5a4038"),
    "rug_pat": rgb("#6a5048"),
}


def px(draw: ImageDraw.ImageDraw, x: int, y: int, c: tuple[int, int, int], w: int = 1, h: int = 1) -> None:
    draw.rectangle((x, y, x + w - 1, y + h - 1), fill=c)


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    im = Image.new("RGBA", (W, H), C["bg"])
    d = ImageDraw.Draw(im)

    # 后墙 + 侧墙（简单透视）
    d.polygon([(0, 0), (W, 0), (W, 88), (0, 72)], fill=C["wall"])
    d.polygon([(0, 72), (W, 88), (W, H), (0, H)], fill=C["floor"])
    for y in range(88, H, 6):
        d.line([(0, y), (W, y + 4)], fill=C["plank"], width=1)
    for x in range(0, W, 28):
        d.line([(x, 92), (x + 8, H)], fill=C["floor_hi"], width=1)

    # 踢脚线
    d.rectangle((0, 84, W, 90), fill=C["trim"])

    # 窗户（月光，设备关时仍可见）
    wx, wy, ww, wh = 118, 18, 124, 52
    d.rectangle((wx, wy, wx + ww, wy + wh), fill=C["window"])
    d.rectangle((wx + 6, wy + 6, wx + ww - 6, wy + wh - 6), fill=C["window_glass"])
    d.line([(wx + ww // 2, wy + 4), (wx + ww // 2, wy + wh - 4)], fill=C["window"], width=2)
    d.line([(wx + 4, wy + wh // 2), (wx + ww - 4, wy + wh // 2)], fill=C["window"], width=2)
    # 月光斑（很弱，开灯时会被暖光盖过）
    d.ellipse((wx + 20, wy + 8, wx + 90, wy + 40), fill=(*C["moon"], 35))

    # 地毯
    d.rectangle((72, 128, 248, 198), fill=C["rug"])
    for i in range(6):
        d.rectangle((80 + i * 26, 136, 98 + i * 26, 190), outline=C["rug_pat"])

    # 沙发（左下）
    d.rectangle((24, 118, 148, 168), fill=C["sofa_shadow"])
    d.rectangle((28, 112, 152, 162), fill=C["sofa"])
    d.rectangle((32, 108, 156, 118), fill=C["sofa_hi"])
    d.rectangle((40, 120, 72, 148), fill=C["pillow"])
    d.rectangle((88, 122, 118, 150), fill=C["pillow"])
    d.rectangle((28, 162, 152, 172), fill=C["sofa_shadow"])

    # 茶几
    d.rectangle((98, 148, 168, 158), fill=C["wood"])
    d.rectangle((100, 150, 166, 156), fill=C["wood_hi"])
    d.rectangle((108, 158, 112, 172), fill=C["wood"])
    d.rectangle((154, 158, 158, 172), fill=C["wood"])

    # 落地灯（灯罩未自发光 — 由 Swift 叠光）
    lx, ly = 34, 52
    d.rectangle((lx + 10, ly, lx + 34, ly + 22), fill=C["lamp_off"])
    d.rectangle((lx + 14, ly + 2, lx + 30, ly + 18), fill=C["lamp_shade"])
    for y in range(ly + 22, 168, 4):
        d.rectangle((lx + 20, y, lx + 24, y + 2), fill=C["lamp_pole"])

    # 绿植
    d.rectangle((268, 132, 312, 198), fill=C["pot"])
    d.ellipse((260, 100, 320, 150), fill=C["plant"])
    d.ellipse((272, 108, 308, 138), fill=rgb("#4f9a5a"))

    # TV + 电视柜（屏幕默认关）
    d.rectangle((248, 72, 342, 138), fill=C["tv_frame"])
    d.rectangle((254, 78, 336, 128), fill=C["tv_off"])
    d.rectangle((240, 138, 348, 158), fill=C["tv_stand"])
    d.rectangle((242, 140, 346, 154), fill=C["wood_hi"])

    # 墙角暗角（底图偏暗，开灯叠层提亮）
    for i in range(24):
        a = int(90 * (1 - i / 24))
        d.rectangle((0, H - 1 - i, W, H - i), fill=(0, 0, 0, a))
    d.rectangle((0, 0, 18, H), fill=(0, 0, 0, 70))
    d.rectangle((W - 18, 0, W, H), fill=(0, 0, 0, 70))

    # 轻微噪点纹理
    import random

    random.seed(42)
    px_data = im.load()
    for _ in range(1800):
        x, y = random.randint(0, W - 1), random.randint(0, H - 1)
        r, g, b, a = px_data[x, y]
        n = random.randint(-6, 6)
        px_data[x, y] = (max(0, min(255, r + n)), max(0, min(255, g + n)), max(0, min(255, b + n)), a)

    im.save(OUT, optimize=True)
    print(f"wrote {OUT} ({W}x{H})")


if __name__ == "__main__":
    main()
