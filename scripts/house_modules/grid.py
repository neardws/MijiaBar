"""等距格子几何（设计稿 §4.3）。2:1 iso；row 增大朝前（屏幕下方）；col 增大朝右。"""
from __future__ import annotations

W = 240
FLOOR_H = 120
WALL_H = 150
FLOOR_THICK = 12
PX = 2


def snap(v: float) -> int:
    return int(round(v / PX) * PX)


def cell_origin(col: int, row: int) -> tuple[int, int]:
    """格子后墙尖（菱形顶点）的屏幕坐标。"""
    x = (col - row) * (W // 2)
    y = (col + row) * (FLOOR_H // 2)
    return snap(x), snap(y)


def module_canvas_size(fw: int, fh: int = 1) -> tuple[int, int]:
    """模块 PNG 尺寸：内容从 (0,0)=后墙尖 向右下展开。"""
    # 最右格子 tip + W，最前 tip 的 y + WALL_H 不够——墙从 tip 向上画 WALL_H
    # 画布：x 从最左 tip 到最右 tip+W；y 从 tip_y - WALL_H 到 tip_y + FLOOR_H + FLOOR_THICK
    # 约定模块局部：原点 = 后墙尖，墙向上为负 y → 不方便。
    # 改：模块局部原点 = (后墙尖.x - 0, 后墙尖.y - WALL_H)，全部非负。
    return fw * W + (fh - 1) * (W // 2), WALL_H + FLOOR_H + FLOOR_THICK + (fh - 1) * (FLOOR_H // 2)


def tip_in_module(fw: int = 1, fh: int = 1) -> tuple[int, int]:
    """后墙尖在模块 PNG 内的坐标。"""
    return 0 if fw == 1 and fh == 1 else (fh - 1) * (W // 2), WALL_H


def layout_canvas(cells: list[tuple[int, int, int, int]], pad: int = 24) -> tuple[int, int, int, int]:
    """cells: (col, row, fw, fh)。返回 (width, height, world_ox, world_oy)。
    世界坐标 = cell_origin；画布像素 = world - (world_ox, world_oy) + 模块内偏移。
    """
    pts = []
    for col, row, fw, fh in cells:
        for dc in range(fw):
            for dr in range(fh):
                tx, ty = cell_origin(col + dc, row + dr)
                pts.append((tx, ty - WALL_H))
                pts.append((tx + W, ty + FLOOR_H + FLOOR_THICK))
                pts.append((tx - W // 2, ty + FLOOR_H // 2))  # left wall hint
                pts.append((tx + W + W // 2, ty + FLOOR_H // 2))
    minx = min(p[0] for p in pts) - pad
    miny = min(p[1] for p in pts) - pad
    maxx = max(p[0] for p in pts) + pad
    maxy = max(p[1] for p in pts) + pad
    return snap(maxx - minx), snap(maxy - miny), snap(minx), snap(miny)


def painter_key(col: int, row: int, fw: int = 1, fh: int = 1) -> tuple[int, int]:
    """从小到大绘制 = 从后到前。"""
    return (col + row + fw + fh, col)
