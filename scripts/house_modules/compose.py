"""把模块瓦片按格子叠成整屋 unlit/lit（画家算法）。"""
from __future__ import annotations

import json
import time
from pathlib import Path

from PIL import Image, ImageDraw

from .grid import FLOOR_H, W, WALL_H, cell_origin, layout_canvas, painter_key, snap

ROOT = Path(__file__).resolve().parents[2]
MOD = ROOT / "assets/house/modules"


def load_catalog() -> dict:
    return json.loads((MOD / "catalog.json").read_text())


def compose(layout: list[dict], phase: str, lit: bool, catalog: dict | None = None) -> tuple[Image.Image, dict, float]:
    """layout: [{module, col, row, key?}]。返回 (图, 场景 JSON, 耗时 ms)。"""
    cat = catalog or load_catalog()
    cells = []
    for c in layout:
        m = cat["modules"][c["module"]]
        fw, fh = m["footprint"] if isinstance(m["footprint"], list) else (m["footprint"], 1)
        if isinstance(fw, (list, tuple)):
            fw, fh = fw[0], fw[1] if len(fw) > 1 else 1
        cells.append((c["col"], c["row"], int(fw), int(fh)))
    width, height, ox, oy = layout_canvas(cells)
    t0 = time.perf_counter()
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))

    # 外轮廓底色（夜空 / 昼空）只画一次在背后
    bg = Image.new("RGBA", (width, height), (18, 22, 40, 255) if phase == "night" else (120, 175, 220, 255))
    canvas.alpha_composite(bg)

    ordered = sorted(enumerate(layout), key=lambda iv: painter_key(iv[1]["col"], iv[1]["row"]))
    scene_modules = {}
    for _, cell in ordered:
        mid = cell["module"]
        m = cat["modules"][mid]
        fw, fh = m["footprint"] if not isinstance(m["footprint"][0] if isinstance(m["footprint"], list) else m["footprint"], list) else (1, 1)
        if isinstance(m["footprint"], list):
            fw, fh = int(m["footprint"][0]), int(m["footprint"][1]) if len(m["footprint"]) > 1 else 1
        else:
            fw, fh = int(m["footprint"]), 1
        variant = m["variants"][f"{phase}-{'lit' if lit else 'unlit'}"]
        tile = Image.open(MOD / variant).convert("RGBA")
        tip_world = cell_origin(cell["col"], cell["row"])
        tip_local = m["tip"]
        # 模块 PNG 左上角世界坐标
        paste_x = tip_world[0] - tip_local[0] - ox
        paste_y = tip_world[1] - tip_local[1] - oy
        canvas.alpha_composite(tile, (snap(paste_x), snap(paste_y)))

        # 锚点转到全局
        def tx(pt):
            return [int(pt[0] - tip_local[0] + tip_world[0] - ox), int(pt[1] - tip_local[1] + tip_world[1] - oy)]

        key = cell.get("key", mid)
        lights = []
        for L in m["lights"]:
            L2 = dict(L)
            if L2.get("reveal"):
                r = L2["reveal"]
                L2["reveal"] = [r[0] - tip_local[0] + tip_world[0] - ox, r[1] - tip_local[1] + tip_world[1] - oy, r[2], r[3]]
            for poly_key in ("shade", "screen", "core"):
                if L2.get(poly_key):
                    L2[poly_key] = [tx(p) for p in L2[poly_key]]
            lights.append(L2)
        scene_modules[key] = {
            "module": mid,
            "label": tx(m["label"]),
            "region": [tx(p) for p in m["region"]],
            "badges": [tx(p) for p in m["badges"]],
            "lights": lights,
            "col": cell["col"], "row": cell["row"],
        }

    # 接缝件：简单的地基描边（spike）
    draw = ImageDraw.Draw(canvas)
    # 底部阴影线
    draw.rectangle([0, height - 8, width, height], fill=(0, 0, 0, 80))

    ms = (time.perf_counter() - t0) * 1000
    scene = {"size": [width, height], "origin": [ox, oy], "phase": phase, "lit": lit, "modules": scene_modules}
    return canvas, scene, ms


# 三种 spike 布局
LAYOUTS = {
    "living-bed": [
        {"module": "living", "col": 0, "row": 0, "key": "living"},
        {"module": "bedroom", "col": 2, "row": 0, "key": "bedroom"},
    ],
    "three": [
        {"module": "bedroom", "col": 0, "row": 0, "key": "bedroom"},
        {"module": "study", "col": 1, "row": 0, "key": "study"},
        {"module": "living", "col": 0, "row": 1, "key": "living"},
    ],
    "classic4": [
        {"module": "bedroom", "col": 0, "row": 0, "key": "bedroom"},
        {"module": "study", "col": 1, "row": 0, "key": "study"},
        {"module": "living", "col": 0, "row": 1, "key": "living"},
        {"module": "generic", "col": 2, "row": 1, "key": "generic"},
    ],
}


def main():
    # 不重画经典房间（extract_classic 的产物）；只合成
    out = ROOT / "assets/house/spike"
    out.mkdir(parents=True, exist_ok=True)
    cat = load_catalog()
    times = []
    for name, layout in LAYOUTS.items():
        for phase in ("day", "night"):
            for lit in (False, True):
                im, scene, ms = compose(layout, phase, lit, cat)
                times.append(ms)
                tag = f"{name}-{phase}-{'lit' if lit else 'unlit'}"
                im.save(out / f"{tag}.png", optimize=True)
                if lit and phase == "night":
                    (out / f"{name}-scene.json").write_text(json.dumps(scene, indent=2), encoding="utf-8")
                print(f"{tag}: {im.size[0]}x{im.size[1]} in {ms:.1f} ms")
    print(f"compose ms: min={min(times):.1f} median={sorted(times)[len(times)//2]:.1f} max={max(times):.1f}")


if __name__ == "__main__":
    main()
