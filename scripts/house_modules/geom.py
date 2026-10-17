"""Phase 2 网格几何（v2）：所有模块都按同一套规范几何生成。

屏幕坐标：tip(col,row) = ((col-row)*W/2, (col+row)*FH/2)，row 增大朝前（屏幕下方），col 增大朝右。
每个模块 = 自己的地板 + 两面后墙（NW 左后墙、NE 右后墙）+ 前沿地台厚度。
共享墙只有一个主人：前/右侧的格子（它的后墙）。后方格子从不画前墙（剖面朝镜头敞开）。
绘制顺序：(row, col) 从小到大 = 从后到前。
"""
from __future__ import annotations

W, FH, WALL_H, SLAB, PAD = 320, 132, 104, 14, 16
PX = 2
CUT_H = 40          # 内墙（共享墙）切到护墙板高度，露出后方房间
CAP_NW = (-10, -4)   # 墙顶厚度方向（朝墙后）
CAP_NE = (10, -4)


def tip(col: int, row: int) -> tuple[int, int]:
    return ((col - row) * W // 2, (col + row) * FH // 2)


def module_geom(fw: int = 1) -> dict:
    T = (W // 2 + PAD + 10, WALL_H + PAD + 4)
    R = (T[0] + fw * W // 2, T[1] + fw * FH // 2)
    F = (T[0] + (fw - 1) * W // 2, T[1] + (fw + 1) * FH // 2)
    L = (T[0] - W // 2, T[1] + FH // 2)
    up = lambda p: (p[0], p[1] - WALL_H)
    dn = lambda p: (p[0], p[1] + SLAB)
    size = (R[0] + PAD + 10, F[1] + SLAB + PAD)
    return dict(T=T, R=R, F=F, L=L, size=size, fw=fw,
                floor=[T, R, F, L],
                wall_nw=[up(T), up(L), L, T],
                wall_ne=[up(T), up(R), R, T],
                slab_sw=[L, F, dn(F), dn(L)],
                slab_se=[F, R, dn(R), dn(F)],
                silhouette=[up(T), up(R), R, dn(R), dn(F), dn(L), L, up(L)])
