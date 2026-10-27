#!/usr/bin/env python3
"""小屋 A2 落地电器精灵：fixture-<kind>-{on,off}.png

与装饰 / 洗衣机同尺度，1:1 画在模块坐标里。开着时有指示灯与气流/热量色。
"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Sources/MijiaBarApp/Resources/House"

K = (42, 31, 26, 255)
W = (248, 244, 236, 255)
WL = (255, 252, 245, 255)
WD = (210, 205, 195, 255)
S = (200, 205, 210, 255)
SD = (140, 145, 150, 255)
D = (85, 80, 75, 255)
BASE = (72, 58, 48, 255)
OFF = (55, 54, 52, 255)
CYAN = (110, 210, 220, 255)
BLUE = (80, 160, 220, 255)
GRN = (100, 200, 110, 255)
ORG = (255, 145, 50, 255)
AMB = (255, 195, 90, 255)


def save(im: Image.Image, name: str, crop: bool = True) -> Image.Image:
    bbox = im.getbbox() if crop else None
    im = im.crop(bbox) if bbox else im
    if im.width % 2:
        n = Image.new("RGBA", (im.width + 1, im.height), (0, 0, 0, 0)); n.paste(im, (0, 0)); im = n
    if im.height % 2:
        n = Image.new("RGBA", (im.width, im.height + 1), (0, 0, 0, 0)); n.paste(im, (0, 0)); im = n
    OUT.mkdir(parents=True, exist_ok=True)
    im.save(OUT / name)
    print((OUT / name).relative_to(ROOT), im.size)
    return im


def fan(on: bool) -> Image.Image:
    im = Image.new("RGBA", (28, 40), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.ellipse([6, 32, 22, 39], fill=BASE, outline=K)
    d.ellipse([8, 33, 20, 37], fill=D)
    d.rectangle([12, 18, 16, 34], fill=K)
    d.rectangle([13, 18, 15, 33], fill=S)
    d.ellipse([2, 2, 26, 26], fill=K)
    d.ellipse([3, 3, 25, 25], fill=WL if on else WD)
    d.ellipse([5, 5, 23, 23], fill=S)
    d.ellipse([9, 9, 19, 19], fill=CYAN if on else SD)
    d.ellipse([11, 11, 17, 17], fill=BLUE if on else D)
    if on:
        d.arc([6, 6, 22, 22], 20, 70, fill=CYAN)
        d.arc([6, 6, 22, 22], 140, 190, fill=CYAN)
        d.arc([6, 6, 22, 22], 260, 310, fill=CYAN)
    else:
        d.line([(14, 6), (14, 22)], fill=D)
        d.line([(6, 14), (22, 14)], fill=D)
        d.line([(8, 8), (20, 20)], fill=D)
        d.line([(20, 8), (8, 20)], fill=D)
    d.ellipse([3, 3, 25, 25], outline=K)
    return save(im, f"fixture-fan-{'on' if on else 'off'}.png")


def purifier(on: bool) -> Image.Image:
    im = Image.new("RGBA", (26, 44), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.polygon([(8, 2), (18, 7), (14, 11), (4, 6)], fill=WL, outline=K)
    d.polygon([(4, 6), (14, 11), (14, 39), (4, 34)], fill=SD, outline=K)
    d.polygon([(18, 7), (14, 11), (14, 39), (18, 35)], fill=W, outline=K)
    for i in range(6):
        y = 14 + i * 3
        d.line([(15, y), (17, y + 1)], fill=D)
    d.rectangle([6, 20, 10, 22], fill=GRN if on else OFF)
    if on:
        d.line([(7, 5), (15, 9)], fill=CYAN)
        d.line([(8, 6), (14, 9)], fill=CYAN)
    d.ellipse([5, 38, 19, 43], fill=BASE, outline=K)
    return save(im, f"fixture-air-purifier-{'on' if on else 'off'}.png")


def dehumidifier(on: bool) -> Image.Image:
    im = Image.new("RGBA", (34, 32), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.polygon([(10, 2), (24, 9), (18, 14), (4, 7)], fill=WL, outline=K)
    d.polygon([(4, 7), (18, 14), (18, 28), (4, 21)], fill=SD, outline=K)
    d.polygon([(24, 9), (18, 14), (18, 28), (24, 23)], fill=W, outline=K)
    d.rectangle([19, 12, 23, 16], fill=BLUE if on else OFF, outline=K)
    if on:
        d.point([(20, 13)], fill=GRN)
    d.rectangle([19, 18, 23, 25], fill=CYAN if on else SD, outline=K)
    if on:
        d.rectangle([20, 22, 22, 24], fill=BLUE)
    d.ellipse([6, 26, 22, 31], fill=BASE, outline=K)
    return save(im, f"fixture-dehumidifier-{'on' if on else 'off'}.png")


def heater(on: bool) -> Image.Image:
    im = Image.new("RGBA", (32, 34), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.polygon([(8, 2), (22, 9), (16, 13), (2, 6)], fill=WL, outline=K)
    d.polygon([(2, 6), (16, 13), (16, 28), (2, 21)], fill=SD, outline=K)
    d.polygon([(22, 9), (16, 13), (16, 28), (22, 24)], fill=W, outline=K)
    for i in range(6):
        x = 17 + i
        col = ORG if on and i % 2 == 0 else (AMB if on else SD)
        d.line([(x, 12), (x - 1, 26)], fill=col)
    d.rectangle([4, 16, 8, 18], fill=ORG if on else OFF)
    d.rectangle([4, 28, 7, 32], fill=D, outline=K)
    d.rectangle([18, 28, 21, 32], fill=D, outline=K)
    return save(im, f"fixture-heater-{'on' if on else 'off'}.png")


def humidifier(on: bool) -> Image.Image:
    im = Image.new("RGBA", (26, 38), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.ellipse([3, 31, 23, 37], fill=BASE, outline=K)
    d.rounded_rectangle([4, 13, 22, 33], radius=4, fill=W, outline=K)
    d.rectangle([5, 17, 9, 29], fill=SD)
    d.rounded_rectangle([10, 17, 19, 27], radius=2, fill=CYAN if on else S, outline=K)
    d.line([(12, 19), (12, 24)], fill=WL)
    d.ellipse([4, 10, 22, 18], fill=WL, outline=K)
    d.ellipse([10, 12, 16, 15], fill=D, outline=K)
    d.rectangle([13, 30, 16, 31], fill=CYAN if on else OFF)
    if on:
        d.arc([8, 3, 16, 9], 100, 280, fill=CYAN)
        d.arc([13, 0, 21, 6], 260, 80, fill=CYAN)
        d.point([(10, 1), (18, 8), (6, 5)], fill=CYAN)
    return save(im, f"fixture-humidifier-{'on' if on else 'off'}.png", crop=False)


def vacuum(on: bool) -> Image.Image:
    im = Image.new("RGBA", (36, 26), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.polygon([(10, 7), (22, 7), (29, 15), (5, 15)], fill=SD, outline=K)
    d.rounded_rectangle([10, 1, 24, 11], radius=2, fill=W, outline=K)
    d.rectangle([13, 4, 21, 9], fill=D)
    d.point([(17, 3)], fill=GRN if on else OFF)
    offset = 3 if on else 0
    d.ellipse([4 + offset, 15, 29 + offset, 25], fill=BASE, outline=K)
    d.ellipse([3 + offset, 10, 29 + offset, 23], fill=SD, outline=K)
    d.ellipse([3 + offset, 8, 29 + offset, 20], fill=WL, outline=K)
    d.arc([5 + offset, 10, 27 + offset, 21], 5, 175, fill=D)
    d.ellipse([12 + offset, 10, 20 + offset, 14], fill=S, outline=K)
    d.line([(13 + offset, 18), (19 + offset, 18)], fill=CYAN if on else OFF)
    if on:
        d.line([(0, 15), (3, 14)], fill=CYAN)
        d.line([(1, 20), (4, 19)], fill=GRN)
    return save(im, f"fixture-vacuum-{'on' if on else 'off'}.png", crop=False)


def main() -> None:
    for on in (True, False):
        fan(on); purifier(on); dehumidifier(on); heater(on); humidifier(on); vacuum(on)


if __name__ == "__main__":
    main()
