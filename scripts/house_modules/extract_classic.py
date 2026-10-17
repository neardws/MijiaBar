"""从经典整图按 region 蒙版抠出房间，贴到标准等距模块画布上（spike / 经典四室回退用）。"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from .grid import FLOOR_H, PX, W, WALL_H, FLOOR_THICK, module_canvas_size, snap, tip_in_module
from .paint import MODULE_SPECS, quantize

ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / "Sources/MijiaBarApp/Resources/House"
OUT = ROOT / "assets/house/modules"


def load_scene():
    return json.loads((RES / "house-cutaway.json").read_text())


def crop_module(src: Image.Image, region: list, pad: int = 8) -> tuple[Image.Image, tuple[int, int]]:
    """按多边形抠图，返回 RGBA 与原图左上角偏移。"""
    xs = [p[0] for p in region]; ys = [p[1] for p in region]
    minx, maxx = int(min(xs)) - pad, int(max(xs)) + pad
    miny, maxy = int(min(ys)) - pad, int(max(ys)) + pad
    minx, miny = max(0, minx), max(0, miny)
    maxx, maxy = min(src.width, maxx), min(src.height, maxy)
    mask = Image.new("L", src.size, 0)
    ImageDraw.Draw(mask).polygon([tuple(p) for p in region], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(0.6))
    rgba = src.convert("RGBA")
    rgba.putalpha(mask)
    return rgba.crop((minx, miny, maxx, maxy)), (minx, miny)


def place_on_tile(cropped: Image.Image, origin: tuple[int, int], fw: int, tip_src: tuple[int, int]) -> tuple[Image.Image, tuple[int, int]]:
    """把抠出的房间放到模块画布上，使 tip_src 对齐模块 tip。"""
    mw, mh = module_canvas_size(fw, 1)
    tip = tip_in_module(fw, 1)
    # tip_src 在原图坐标；cropped 的 (0,0) = origin
    # 模块上 tip 应对齐 tip_src
    paste_x = tip[0] - (tip_src[0] - origin[0])
    paste_y = tip[1] - (tip_src[1] - origin[1])
    # 可能超出画布：扩画布
    x0, y0 = min(0, paste_x), min(0, paste_y)
    x1 = max(mw, paste_x + cropped.width)
    y1 = max(mh, paste_y + cropped.height)
    canvas = Image.new("RGBA", (snap(x1 - x0), snap(y1 - y0)), (0, 0, 0, 0))
    canvas.alpha_composite(cropped, (snap(paste_x - x0), snap(paste_y - y0)))
    new_tip = (tip[0] - x0, tip[1] - y0)
    return quantize(canvas), (int(new_tip[0]), int(new_tip[1]))


# 经典图里每个模块选一个「后墙尖」参考点（region 最上/最后的顶点附近）
TIP_HINTS = {
    "living": (40, 280),      # 左后
    "bedroom": (280, 40),
    "study": (620, 70),
    "generic": (700, 320),
}


def extract_all():
    scene = load_scene()
    OUT.mkdir(parents=True, exist_ok=True)
    catalog = {"schema": 2, "style": "cozy-wood-classic-extract", "grid": {"W": W, "FLOOR_H": FLOOR_H, "WALL_H": WALL_H, "FLOOR_THICK": FLOOR_THICK, "PX": PX}, "modules": {}}

    for phase in ("day", "night"):
        for lit_name in ("unlit", "lit"):
            src = Image.open(RES / f"house-cutaway-{phase}-{lit_name}.png")
            for mid, mod in scene["modules"].items():
                cropped, origin = crop_module(src, mod["region"])
                fw = 2 if mid == "living" else 1
                tip_src = TIP_HINTS[mid]
                tile, tip = place_on_tile(cropped, origin, fw, tip_src)
                name = f"module-{mid}-{phase}-{lit_name}.png"
                tile.save(OUT / name, optimize=True)

                if phase == "day" and lit_name == "unlit":
                    # 锚点：原坐标 - origin + paste offset → 模块局部
                    # paste put tip_src at tip; so local = global - tip_src + tip
                    def to_local(p):
                        return [int(p[0] - tip_src[0] + tip[0]), int(p[1] - tip_src[1] + tip[1])]

                    lights = []
                    for L in mod["lights"]:
                        L2 = {"id": L["id"], "kind": L.get("kind", "lamp"), "role": L.get("role", "light")}
                        if "reveal" in L and isinstance(L["reveal"], list) and len(L["reveal"]) == 4:
                            r = L["reveal"]
                            L2["reveal"] = [r[0] - tip_src[0] + tip[0], r[1] - tip_src[1] + tip[1], r[2], r[3]]
                        elif L.get("reveal") == "room":
                            L2["reveal"] = "room"
                        for k in ("shade", "screen", "core"):
                            if L.get(k):
                                L2[k] = [to_local(p) for p in L[k]]
                        lights.append(L2)
                    catalog["modules"][mid] = {
                        "footprint": [fw, 1],
                        "size": list(tile.size),
                        "tip": list(tip),
                        "region": [to_local(p) for p in mod["region"]],
                        "label": to_local(mod["label"]),
                        "badges": [to_local(p) for p in mod.get("badges") or []],
                        "lights": lights,
                        "variants": {},
                        "source": "classic-extract",
                    }
                catalog["modules"][mid]["variants"][f"{phase}-{lit_name}"] = name
                print(f"{mid} {phase}-{lit_name} {tile.size}")

    (OUT / "catalog.json").write_text(json.dumps(catalog, indent=2), encoding="utf-8")
    return catalog


if __name__ == "__main__":
    extract_all()
