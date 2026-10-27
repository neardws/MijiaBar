"""生成空灯具位的家具贴片：python3 scripts/house_modules/absent_variants.py。

保留贴片边缘的原始背景，在 2px 网格上绘制透视书柜和山景画框。
同时更新开发素材与打包目录的 catalog；不改烘焙底图。
"""
import json
import re
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / "Sources/MijiaBarApp/Resources/House"
MODULES = ROOT / "assets/house/modules"
TARGETS = {
    "living-tv": ("bookshelf", [(306, 166), (372, 192), (372, 246), (306, 220)]),
    "living-ac": ("painting", [(80, 74), (144, 48), (144, 88), (80, 114)]),
    "bedroom-ac": ("painting", [(80, 74), (144, 48), (144, 88), (80, 114)]),
    "study-monitor": ("bookshelf", [(224, 98), (266, 116), (266, 152), (224, 134)]),
    "classic-living-tv": ("bookshelf", [(426, 256), (506, 282), (506, 348), (426, 322)]),
    "classic-living-ac": ("painting", [(52, 226), (128, 204), (128, 254), (52, 278)]),
    "classic-bedroom-ac": ("painting", [(284, 44), (370, 18), (370, 86), (284, 112)]),
    "classic-study-monitor": ("bookshelf", [(660, 136), (724, 154), (724, 208), (660, 190)]),
}
PALETTE = {
    "shadow": (48, 34, 25), "edge": (67, 42, 26), "wood": (125, 82, 43),
    "highlight": (174, 128, 71), "back": (57, 42, 29), "paper": (198, 177, 125),
    "red": (142, 72, 49), "sage": (106, 119, 72), "blue": (78, 104, 111),
    "sky": (161, 175, 158), "mountain": (96, 124, 111), "hill": (70, 94, 69),
    "sun": (218, 185, 112),
}


def geometry(quad):
    left = min(point[0] for point in quad) - 2
    top = min(point[1] for point in quad) - 2
    right = max(point[0] for point in quad) + 6
    bottom = max(point[1] for point in quad) + 6
    return [left, top, right - left, bottom - top]


def artwork(kind, quad, rect, phase, lit):
    image = Image.new("RGBA", (rect[2] // 2, rect[3] // 2))
    draw = ImageDraw.Draw(image)

    def color(name):
        base = PALETTE[name]
        factors = (0.48, 0.56, 0.70) if phase == "night" else (1, 1, 1)
        lift = 1.15 if lit else 1
        return tuple(min(255, round(channel * factor * lift)) for channel, factor in zip(base, factors)) + (255,)

    def point(horizontal, vertical):
        top = tuple(quad[0][axis] * (1 - horizontal) + quad[1][axis] * horizontal for axis in (0, 1))
        bottom = tuple(quad[3][axis] * (1 - horizontal) + quad[2][axis] * horizontal for axis in (0, 1))
        return tuple(round((top[axis] * (1 - vertical) + bottom[axis] * vertical - rect[axis]) / 2) for axis in (0, 1))

    def polygon(points, name):
        draw.polygon([point(*position) for position in points], fill=color(name))

    def panel(left, top, right, bottom, name):
        polygon([(left, top), (right, top), (right, bottom), (left, bottom)], name)

    panel(0.04, 0.05, 1.05, 1.06, "shadow")
    panel(0, 0, 1, 1, "edge")
    panel(0.03, 0.03, 0.96, 0.96, "wood")
    panel(0.03, 0.03, 0.96, 0.08, "highlight")
    if kind == "painting":
        panel(0.10, 0.14, 0.89, 0.85, "paper")
        panel(0.15, 0.20, 0.84, 0.78, "sky")
        panel(0.65, 0.28, 0.73, 0.40, "sun")
        polygon([(0.15, 0.63), (0.35, 0.32), (0.57, 0.59), (0.70, 0.45), (0.84, 0.65), (0.84, 0.78), (0.15, 0.78)], "mountain")
        polygon([(0.15, 0.72), (0.43, 0.56), (0.65, 0.69), (0.84, 0.59), (0.84, 0.78), (0.15, 0.78)], "hill")
    else:
        panel(0.08, 0.12, 0.90, 0.92, "back")
        for shelf in range(2):
            bottom = 0.47 + shelf * 0.42
            for book in range(7):
                left = 0.12 + book * 0.105
                top = bottom - (0.20 + (book % 3) * 0.035)
                panel(left, top, left + 0.075, bottom, ["sage", "red", "paper", "blue"][book % 4])
                panel(left, top + 0.04, left + 0.075, top + 0.065, "paper")
            panel(0.06, bottom, 0.92, bottom + 0.045, "highlight")
            panel(0.06, bottom + 0.045, 0.92, bottom + 0.085, "wood")
    return image.resize((rect[2], rect[3]), Image.Resampling.NEAREST)


def build():
    paths = [RES / "modules/catalog.json", MODULES / "catalog.json", RES / "house-cutaway.json"]
    catalogs = {path: path.read_text() for path in paths}
    for name, (kind, quad) in TARGETS.items():
        classic = name.startswith("classic-")
        room, fixture = name.removeprefix("classic-").split("-")
        rect = geometry(quad)
        patch = f"absent-{name}"
        for phase in ("day", "night"):
            for lit in (False, True):
                variant = f"{phase}-{'lit' if lit else 'unlit'}"
                source = RES / f"house-cutaway-{variant}.png" if classic else RES / f"modules/module-{room}-{variant}.png"
                background = Image.open(source).convert("RGBA").crop((rect[0], rect[1], rect[0] + rect[2], rect[1] + rect[3]))
                background.alpha_composite(artwork(kind, quad, rect, phase, lit))
                for directory in (RES / "modules", MODULES):
                    background.save(directory / f"{patch}-{variant}.png", optimize=True)
        for path, text in catalogs.items():
            if (path.name == "house-cutaway.json") == classic:
                room_start = text.index(f'"{room}":')
                id_start = text.index(f'"id": "{fixture}"', room_start)
                start = text.rfind("{", room_start, id_start)
                _, length = json.JSONDecoder().raw_decode(text[start:])
                original = text[start:start + length]
                field = json.dumps({"patch": patch, "rect": rect})
                if '"absentVariant"' in original:
                    updated = re.sub(r'("absentVariant":\s*)\{[^{}]*\}', lambda match: match[1] + field, original)
                else:
                    indent = "         " if classic else "     "
                    updated = original[:-1].rstrip() + ',\n' + indent + '"absentVariant": ' + field + "}"
                catalogs[path] = text[:start] + updated + text[start + length:]
    for path, text in catalogs.items():
        path.write_text(text)


if __name__ == "__main__":
    build()
