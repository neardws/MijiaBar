#!/usr/bin/env python3
"""烘焙灯光：从 day/night 剖面底图生成 unlit / lit 两张像素完全对齐的底图。

lit 版与 unlit 版构图一致，只多了「画进去」的灯光（灯罩发光、地面光池、墙面暖光、
屏幕亮起、空调送风）。运行时显示 unlit 底图，再按房间 / 灯具区域蒙版淡入 lit 底图，
所以光永远和家具对齐。

光源与房间多边形定义在 Resources/House/house-cutaway.json（像素坐标 = 960×540 画布）。
输出：Resources/House/house-cutaway-{day,night}-{unlit,lit}.png
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "Sources/MijiaBarApp/Resources/House"
SRC = {"day": ROOT / "assets/house/house-cutaway-day-base.png", "night": ROOT / "assets/house/house-cutaway-night-base.png"}
SCENE = RES / "house-cutaway.json"
PX = 2  # 底图像素格（gen-house-cutaway-art 是半分辨率 NEAREST 放大）

WARM = np.array([1.0, 0.72, 0.40])
WARM_HOT = np.array([1.0, 0.88, 0.62])
SCREEN = np.array([0.55, 0.78, 1.0])
COOL = np.array([0.55, 0.85, 1.0])

BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0


def load(p: Path) -> np.ndarray:
    return np.asarray(Image.open(p).convert("RGB"), dtype=np.float32) / 255.0


def poly_mask(size, pts, feather=0.0) -> np.ndarray:
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).polygon([tuple(p) for p in pts], fill=255)
    if feather:
        m = m.filter(ImageFilter.GaussianBlur(feather))
    return np.asarray(m, dtype=np.float32) / 255.0


def grid(w, h):
    # 光照在像素格中心采样，保持 2×2 块状像素感
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    return (xs // PX) * PX + PX / 2, (ys // PX) * PX + PX / 2


def band(field: np.ndarray, steps: int) -> np.ndarray:
    """像素画式的分级光：有序抖动 + 量化，避免平滑渐变的“贴图感”。"""
    h, w = field.shape
    by = np.tile(BAYER4, (h // (4 * PX) + 2, w // (4 * PX) + 2))
    by = np.repeat(np.repeat(by, PX, 0), PX, 1)[:h, :w]
    return np.clip(np.floor(field * steps + by * 0.7) / steps, 0, 1)


def ellipse_falloff(X, Y, cx, cy, rx, ry, power=1.6):
    d = np.sqrt(((X - cx) / rx) ** 2 + ((Y - cy) / ry) ** 2)
    return np.clip(1 - d, 0, 1) ** power


def radial(X, Y, cx, cy, r, squash=1.0):
    d2 = ((X - cx) / r) ** 2 + ((Y - cy) / (r * squash)) ** 2
    return 1 / (1 + 4 * d2)


def light_field(light: dict, X, Y) -> np.ndarray:
    """单个灯具对画面的照度（0..~1），在房间蒙版之前。"""
    kind = light["kind"]
    if kind in ("lamp", "sconce"):
        sx, sy = light["source"]
        r = light.get("radius", 120)
        f = radial(X, Y, sx, sy, r, squash=0.8) * 0.85
        if "pool" in light:  # 地面光池（等距椭圆）
            px, py, rx, ry = light["pool"]
            f = f + ellipse_falloff(X, Y, px, py, rx, ry, 1.1) * 0.6
        return f
    if kind == "ceiling":  # 看不见灯具的吸顶灯：整屋暖光 + 中央光池
        px, py, rx, ry = light["pool"]
        return ellipse_falloff(X, Y, px, py, rx * 1.9, ry * 1.9, 1.0) * 0.5 + ellipse_falloff(X, Y, px, py, rx, ry, 1.2) * 0.45
    if kind == "screen":
        q = np.array(light["screen"], dtype=np.float32)
        cx, cy = q.mean(0)
        ox, oy = light.get("throw", [-30, 20])
        r = light.get("radius", 70)
        return radial(X, Y, cx + ox, cy + oy, r, 0.7) * 0.75
    if kind == "ac":
        q = np.array(light["vent"], dtype=np.float32)
        cx, cy = q.mean(0)
        return radial(X, Y, cx, cy + 14, 38, 0.6) * 0.5
    return np.zeros_like(X)


def paint_screen(img: np.ndarray, quad, phase: str, style: str):
    """屏幕：像素风画面（电视=夜景山林，显示器=桌面窗口），带边缘暗角。"""
    h, w, _ = img.shape
    q = np.array(quad, dtype=np.float32)
    m = poly_mask((w, h), q)
    X, Y = grid(w, h)
    tl, tr, br, bl = q
    # 双线性参数 u（左→右）v（上→下），近似平行四边形
    ex, ey = tr - tl, bl - tl
    det = ex[0] * ey[1] - ex[1] * ey[0]
    dx, dy = X - tl[0], Y - tl[1]
    u = np.clip((dx * ey[1] - dy * ey[0]) / det, 0, 1)
    v = np.clip((ex[0] * dy - ex[1] * dx) / det, 0, 1)
    if style == "tv":
        sky = np.stack([0.22 + 0.25 * v, 0.42 + 0.3 * v, 0.78 + 0.1 * v], -1)
        hill = 0.62 + 0.12 * np.sin(u * 9.0) + 0.06 * np.sin(u * 23.0)
        trees = (v > hill).astype(np.float32)
        forest = np.stack([0.10 + 0.06 * u, 0.32 + 0.10 * (1 - v), np.full_like(u, 0.30)], -1)
        col = sky * (1 - trees[..., None]) + forest * trees[..., None]
        moon = ((u - 0.75) ** 2 + ((v - 0.25) * 0.7) ** 2) < 0.006
        col[moon] = [0.95, 0.97, 1.0]
    else:
        col = np.stack([0.20 + 0.15 * v, 0.45 + 0.2 * v, 0.85 + 0.0 * v], -1)
        win = (u > 0.12) & (u < 0.62) & (v > 0.18) & (v < 0.62)
        col[win] = [0.86, 0.92, 0.98]
        bar = (u > 0.12) & (u < 0.62) & (v > 0.18) & (v < 0.27)
        col[bar] = [0.35, 0.55, 0.9]
        task = (v > 0.86)
        col[task] = [0.12, 0.18, 0.32]
    edge = np.minimum.reduce([u, 1 - u, v, 1 - v])
    vign = np.clip(0.75 + edge * 3, 0, 1)
    col = col * vign[..., None] * (1.0 if phase == "night" else 0.95)
    # 量化颜色保持像素感
    col = np.round(col * 12) / 12
    img[:] = img * (1 - m[..., None]) + col * m[..., None]


def paint_shade(img: np.ndarray, poly, phase: str):
    """灯罩本身发光：只在灯罩多边形内提亮（保留原有布纹明暗），下沿最亮。"""
    h, w, _ = img.shape
    q = np.array(poly, dtype=np.float32)
    m = poly_mask((w, h), q)[..., None]
    y0, y1 = q[:, 1].min(), q[:, 1].max()
    _, Y = grid(w, h)
    t = np.clip((Y - y0) / max(1, y1 - y0), 0, 1)[..., None]  # 0 顶 → 1 底
    lum = img.mean(-1, keepdims=True)
    hot = np.clip((0.62 + 0.30 * t + lum * 0.35) * WARM_HOT, 0, 1)
    if phase == "day":
        hot = img * 0.35 + hot * 0.65
    hot = np.round(hot * 16) / 16
    img[:] = img * (1 - m) + hot * m


def reveal_mask(light: dict, size) -> np.ndarray | float:
    """与运行时 HouseRoomLightLayer 完全一致的灯具蒙版：
    "room" = 整个房间；[cx,cy,rx,ry] = 椭圆，归一化半径 0–0.55 全开，0.55–1 线性羽化到 0。"""
    r = light.get("reveal", "room")
    if r == "room":
        return 1.0
    cx, cy, rx, ry = r
    w, h = size
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt(((xs + 0.5 - cx) / rx) ** 2 + ((ys + 0.5 - cy) / ry) ** 2)
    return np.clip((1 - d) / 0.45, 0, 1)


def bake(phase: str, scene: dict) -> tuple[Image.Image, Image.Image]:
    base = load(SRC[phase])
    h, w, _ = base.shape
    X, Y = grid(w, h)
    if phase == "night":
        # 关灯夜景：保留可读性，偏冷月光
        unlit = np.clip(base * np.array([0.80, 0.82, 0.92]) + np.array([0.0, 0.004, 0.018]), 0, 1)
    else:
        unlit = base.copy()
    lit = unlit.copy()
    gain = 2.5 if phase == "night" else 1.0
    for mod in scene["modules"].values():
        room = poly_mask((w, h), mod["region"], feather=1.0)
        for light in mod["lights"]:
            f = light_field(light, X, Y) * light.get("strength", 1.0)
            f = band(np.clip(f, 0, 1), 7) * room * reveal_mask(light, (w, h))
            col = SCREEN if light["kind"] == "screen" else COOL if light["kind"] == "ac" else WARM
            if light["kind"] == "ac":
                g = 0.9 if phase == "night" else 0.35
            elif light["kind"] == "screen":
                g = 1.3 if phase == "night" else 0.4
            else:
                g = gain
            # 乘性提亮（照亮物体本色）+ 少量加性暖光（光晕）
            lit = lit * (1 + f[..., None] * g * col) + (f ** 2)[..., None] * col * (0.38 if phase == "night" else 0.12)
    lit = np.clip(lit, 0, 1)
    # 灯具本体（最后画，保证不被光照二次放大）
    for mod in scene["modules"].values():
        for light in mod["lights"]:
            if "shade" in light:
                paint_shade(lit, light["shade"], phase)
            if light["kind"] == "screen":
                paint_screen(lit, light["screen"], phase, light.get("style", "tv"))
            if light["kind"] == "ac":
                paint_ac(lit, light, phase)
    to_img = lambda a: Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")
    return to_img(unlit), to_img(lit)


def paint_ac(img: np.ndarray, light: dict, phase: str):
    """空调送风：出风口下方几列冷色像素点 + 指示灯。"""
    (x0, y0), (x1, y1) = light["vent"]
    rng = np.random.default_rng(7)
    for i in range(18):
        t = (i + 0.5) / 18
        bx, by = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
        for k in range(1, 6):
            if rng.random() < 0.55:
                x = int(bx - k * 1.2 + rng.integers(-1, 2)) // PX * PX
                y = int(by + k * 5 + rng.integers(-1, 2)) // PX * PX
                a = 0.75 - k * 0.11
                img[y:y + PX, x:x + PX] = img[y:y + PX, x:x + PX] * (1 - a) + np.array([0.62, 0.86, 1.0]) * a
    lx, ly = light["led"]
    img[ly:ly + PX, lx:lx + PX] = [0.45, 1.0, 0.75]


def main() -> None:
    scene = json.loads(SCENE.read_text())
    for phase in ("day", "night"):
        unlit, lit = bake(phase, scene)
        unlit.save(RES / f"house-cutaway-{phase}-unlit.png", optimize=True)
        lit.save(RES / f"house-cutaway-{phase}-lit.png", optimize=True)
        print(f"{phase}: unlit + lit {unlit.size}")


if __name__ == "__main__":
    main()
