#!/usr/bin/env python3
"""小屋徽章：没有专属灯具的设备（风扇、插座、净化器、传感器……）放在地上的 12×12 像素小图标。

输出 Sources/MijiaBarApp/Resources/House/badge-<kind>-{on,off}.png（1x，App 里按 2 倍、最近邻放大，和底图像素格一致）。
off 版去饱和、压暗，对应设备关着；开着时 App 再在脚下画一圈对应颜色的光。
"""
from pathlib import Path
from PIL import Image, ImageEnhance

OUT = Path(__file__).resolve().parents[1] / "Sources/MijiaBarApp/Resources/House"
PAL = {
    "k": (42, 31, 26), "w": (242, 239, 230), "g": (169, 165, 156), "d": (93, 89, 83), "s": (207, 211, 214),
    "y": (255, 215, 94), "o": (242, 155, 56), "b": (110, 198, 255), "B": (58, 123, 213), "r": (224, 90, 71),
    "G": (108, 192, 112), "c": (127, 224, 224), "n": (138, 90, 59),
}
SPRITES = {
    "humidifier": """
.....c......
....c.c.....
.....c......
...kkkkkk...
..kwwwwwwk..
..kwgssgwk..
..kwgccgwk..
..kwgccgwk..
..kwwwwwwk..
..kwwccwwk..
...kddddk...
....kkkk....""",
    "vacuum": """
....kkkk....
...kwwwwk...
...kwddwk...
...kkkkkk...
..kkkkkkkk..
.kwwwwwwwwk.
kwwwsswwwwwk
kwwwsswwwwwk
kgwwwwwwwwgk
.kgwccccwgk.
..kggggggk..
...kkkkkk...""",
    "fan": """
....kkkk....
...kssssk...
..ksbb..sk..
.ks.bb.bbsk.
.ks..kk..sk.
.ksbbkkbbsk.
.ksb..bb.sk.
..ks..bbsk..
...kssssk...
....kddk....
...kddddk...
..kkkkkkkk..""",
    "plug": """
............
..kkkkkkkk..
..kwwwwwwk..
..kwkwwkwk..
..kwkwwkwk..
..kwwwwwwk..
..kwwGGwwk..
..kwwwwwwk..
..kkkkkkkk..
.....kk.....
.....kk.....
....kkkk....""",
    "ac": """
............
kkkkkkkkkkkk
kwwwwwwwwwwk
kwwwwwwwwGwk
kwwwwwwwwwwk
kssssssssssk
kkkkkkkkkkkk
..b..b..b...
.b..b..b....
..b..b..b...
............
............""",
    "tv": """
............
kkkkkkkkkkkk
kBBBBBBBBBBk
kBbbBBBBBBBk
kBBBBBBBBBBk
kBBBBBBGGBBk
kBBBBBGGGGBk
kkkkkkkkkkkk
.....kk.....
...kkkkkk...
............
............""",
    "light": """
....kkkk....
...kyyyyk...
..kyywyyyk..
..kyywyyyk..
..kyyyyyyk..
..kyyyyyyk..
...kyyyyk...
....kook....
....kssk....
....kddk....
.....kk.....
............""",
    "heater": """
............
.kkkkkkkkkk.
.kokokokook.
.kokokokook.
.kokokokook.
.kokokokook.
.kokokokook.
.kkkkkkkkkk.
.kd......dk.
............
............
............""",
    "dehumidifier": """
..kkkkkkkk..
..kwwwwwwk..
..kwddddwk..
..kwwwwwwk..
..kwwbbwwk..
..kwbbbbwk..
..kwbbbbwk..
..kwwbbwwk..
..kwwwwwwk..
..kwwwwwwk..
..kkkkkkkk..
...k....k...""",
    "sensor": """
.....kk.....
....kwwk....
....kwwk....
....kwrk....
....kwrk....
....kwrk....
...kwrrwk...
..krrrrrrk..
..krrrrrrk..
...krrrrk...
....kkkk....
............""",
    "camera": """
............
...kkkkkk...
..kwwwwwwk..
.kwwkkkkwwk.
.kwkBBbBkwk.
.kwkBBBBkwk.
.kwwkkkkwwk.
..kwwwrwwk..
...kkkkkk...
....kddk....
...kddddk...
...kkkkkk...""",
    "speaker": """
...kkkkkk...
...kddddk...
...kdggdk...
...kddddk...
...kdkkdk...
...kkggkk...
...kgddgk...
...kkggkk...
...kdkkdk...
...kddddk...
...kkkkkk...
............""",
    "kitchen": """
............
.....kk.....
...kkkkkk...
..kssssssk..
kkkkkkkkkkkk
.kssssssssk.
.kssssssssk.
.kssssssssk.
.kssssssssk.
..kkkkkkkk..
..kooooook..
............""",
    "printer": """
............
...kkkkkk...
...kwwwwk...
.kkkkkkkkkk.
.kssssssssk.
.kssssssGsk.
.kddddddddk.
.kdkwwwwkdk.
.kkkwwwwkkk.
....kkkk....
............
............""",
    "air-purifier": """
...kkkkkk...
..kwwwwwwk..
..kwkkkkwk..
..kwwwwwwk..
..kwgwgwwk..
..kwwgwgwk..
..kwgwgwwk..
..kwwgwgwk..
..kwwwwwwk..
..kwwccwwk..
..kkkkkkkk..
............""",
    "purifier": """
...kkkkkk...
..kwwwwwwk..
..kwwbbwwk..
..kwbbbbwk..
..kwbbbbwk..
..kwwbbwwk..
..kwwwwwwk..
..kwddddwk..
..kwwwwwwk..
..kwwGwwwk..
..kkkkkkkk..
............""",
    "curtain": """
kkkkkkkkkkkk
knnnkbbknnnk
knonkbbknonk
knnnkbbknnnk
knonkbwknonk
knnnkbbknnnk
knonkbbknonk
knnnkbbknnnk
knonkkkknonk
knnnk..knnnk
kkkkk..kkkkk
............""",
    "fridge": """
..kkkkkkkk..
..kwwwwwwk..
..kwwwwkwk..
..kwwwwkwk..
..kwwwwwwk..
..kkkkkkkk..
..kwwwwwwk..
..kwwwwkwk..
..kwwwwkwk..
..kwwwwkwk..
..kwwwwwwk..
..kkkkkkkk..""",
    "water-heater": """
..kkkkkkkk..
..kwwwwwwk..
..kwkkkkwk..
..kwkookwk..
..kwkkkkwk..
..kwwwwwwk..
..kwwwwrwk..
..kwwwwwwk..
..kkkkkkkk..
....dk.dk...
....dk.dk...
............""",
    "washer": """
.kkkkkkkkkk.
.kwwwwwGGwk.
.kkkkkkkkkk.
.kwwkkkkwwk.
.kwkbbbbkwk.
.kwkbBBbkwk.
.kwkbBBbkwk.
.kwkbbbbkwk.
.kwwkkkkwwk.
.kwwwwwwwwk.
.kkkkkkkkkk.
............""",

}


def draw(rows: list[str]) -> Image.Image:
    im = Image.new("RGBA", (12, 12), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        assert len(row) == 12, (row, len(row))
        for x, ch in enumerate(row):
            if ch != ".":
                im.putpixel((x, y), PAL[ch] + (255,))
    return im


def main() -> None:
    for name, art in SPRITES.items():
        rows = [r for r in art.strip("\n").split("\n")]
        assert len(rows) == 12, (name, len(rows))
        on = draw(rows)
        rgb = on.convert("RGB")
        off = ImageEnhance.Brightness(ImageEnhance.Color(rgb).enhance(0.25)).enhance(0.72).convert("RGBA")
        off.putalpha(on.getchannel("A"))
        on.save(OUT / f"badge-{name}-on.png")
        off.save(OUT / f"badge-{name}-off.png")
    print(f"{len(SPRITES)} badges → {OUT}")


if __name__ == "__main__":
    main()
