#!/usr/bin/env python3
"""从 module-lights.json 生成静态 alpha 光效 PNG → Resources/House/glows/"""
from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/house/module-lights.json"
OUT = ROOT / "Sources/MijiaBarApp/Resources/House/glows"

PREFIX = {"living": "living-room", "bedroom": "bedroom", "study": "study", "generic": "generic"}

# 点光源 overlay 归一化尺寸（相对画布宽/高）
POINT_SIZE = {
    "lamp": (0.125, 0.24),
    "sconce": (0.07, 0.16),
    "entry": (0.09, 0.14),
}


def pixelize(im: Image.Image) -> Image.Image:
    w, h = im.size
    if w < 4 or h < 4:
        return im
    small = im.resize((max(1, w // 2), max(1, h // 2)), Image.Resampling.BILINEAR)
    return small.resize((w, h), Image.Resampling.NEAREST)


def warm_blob(w: int, h: int, *, tight: bool = False) -> Image.Image:
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = im.load()
    cx, cy = w * 0.5, h * (0.42 if not tight else 0.5)
    rx, ry = w * 0.48, h * 0.45
    for y in range(h):
        for x in range(w):
            dx = (x - cx) / rx
            dy = (y - cy) / ry
            d = math.hypot(dx, dy)
            if d < 1:
                t = (1 - d) ** 2.2
                a = int(255 * t * (0.85 if tight else 0.72))
                px[x, y] = (255, 210, 140, a)
    im = im.filter(ImageFilter.GaussianBlur(0.8))
    return pixelize(im)


def cool_screen(w: int, h: int) -> Image.Image:
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    draw.rounded_rectangle((0, 0, w - 1, h - 1), radius=max(2, min(w, h) // 6), fill=(120, 185, 255, 200))
    inner = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ipx = inner.load()
    for y in range(h):
        for x in range(w):
            t = 1 - abs(x - w / 2) / (w / 2) * 0.35
            ipx[x, y] = (200, 230, 255, int(90 * t))
    im = Image.alpha_composite(im, inner)
    return pixelize(im.filter(ImageFilter.GaussianBlur(0.6)))


def ac_wash(w: int, h: int) -> Image.Image:
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = im.load()
    for y in range(h):
        for x in range(w):
            t = (1 - y / h) ** 1.6
            px[x, y] = (140, 210, 255, int(180 * t))
    return pixelize(im)


def window_day(w: int, h: int) -> Image.Image:
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    draw.rectangle((0, 0, w - 1, h - 1), fill=(220, 238, 255, 210))
    draw.rectangle((2, 2, w - 3, h // 2), fill=(245, 252, 255, 120))
    return pixelize(im)


def window_night(w: int, h: int) -> Image.Image:
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = im.load()
    cx, cy = w * 0.55, h * 0.35
    for y in range(h):
        for x in range(w):
            d = math.hypot(x - cx, y - cy) / (min(w, h) * 0.45)
            if d < 1:
                a = int(160 * (1 - d) ** 2)
                px[x, y] = (170, 205, 235, a)
    return pixelize(im)


def render(kind: str, w: int, h: int, variant: str | None = None) -> Image.Image:
    if kind == "window":
        return window_day(w, h) if variant == "day" else window_night(w, h)
    if kind == "screen":
        return cool_screen(w, h)
    if kind == "ac":
        return ac_wash(w, h)
    if kind == "sconce":
        return warm_blob(w, h, tight=True)
    return warm_blob(w, h)


def layout_canvas(layout: dict, cutaway: bool) -> tuple[int, int]:
    if cutaway:
        sz = layout.get("size") or [960, 540]
    else:
        sz = layout.get("size") or [640, 359]
    return int(sz[0]), int(sz[1])


def overlay_name(prefix: str, light_id: str, layout_tag: str, variant: str | None = None) -> str:
    base = f"{prefix}-glow-{light_id}-{layout_tag}"
    return f"{base}-{variant}" if variant else base


def size_for_light(light: dict, cw: int, ch: int) -> tuple[int, int]:
    kind = light["kind"]
    if light.get("rect"):
        r = light["rect"]
        return max(1, int(r["w"] * cw)), max(1, int(r["h"] * ch))
    ow, oh = POINT_SIZE.get(kind, (0.1, 0.18))
    if light.get("overlay") and "w" in light["overlay"]:
        ow, oh = light["overlay"]["w"], light["overlay"]["h"]
    return max(1, int(ow * cw)), max(1, int(oh * ch))


def main() -> None:
    data = json.loads(SRC.read_text(encoding="utf-8"))
    OUT.mkdir(parents=True, exist_ok=True)
    written: set[str] = set()
    for mod, block in data["modules"].items():
        prefix = PREFIX[mod]
        for layout_tag, cutaway in (("tile", False), ("cutaway", True)):
            layout = block[layout_tag]
            cw, ch = layout_canvas(layout, cutaway)
            for light in layout["lights"]:
                kind = light["kind"]
                lid = light["id"]
                w, h = size_for_light(light, cw, ch)
                if kind == "window":
                    for variant in ("day", "night"):
                        name = overlay_name(prefix, lid, layout_tag, variant)
                        path = OUT / f"{name}.png"
                        render(kind, w, h, variant).save(path, optimize=True)
                        written.add(name)
                        light.setdefault("overlay", {})["imageDay" if variant == "day" else "imageNight"] = name
                else:
                    name = overlay_name(prefix, lid, layout_tag)
                    path = OUT / f"{name}.png"
                    render(kind, w, h).save(path, optimize=True)
                    written.add(name)
                    ov = light.setdefault("overlay", {})
                    ov["image"] = name
                    if light.get("at") and "w" not in ov:
                        ow, oh = POINT_SIZE.get(kind, (0.1, 0.18))
                        ov["w"], ov["h"] = ow, oh
    SRC.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {len(written)} glow PNGs → {OUT}")


if __name__ == "__main__":
    main()
