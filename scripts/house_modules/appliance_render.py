"""小家电的 3D 渲染（numpy 光线步进 SDF），给模块美术画洗衣机 / 热水器用。

相机和模块美术一致：正交投影，屏幕 1x 坐标 P(u,v,z) = T + ((u-v)·W/2, (u+v)·FH/2 - z)。
世界坐标（1x 屏幕像素单位）：X = u·S, Y = v·S, Z = z / cosθ，S = 160/cos45°，sinθ = FH/W。
在 2x 规范图上超采样渲染（圆角、AO、柔和阴影、高光），之后和其他家具一样走 pixelize。
"""
from __future__ import annotations
import numpy as np

S = 160 / np.cos(np.pi / 4)                 # 1 格地板在世界里的长度
SIN_T = 132 / 320; COS_T = np.sqrt(1 - SIN_T ** 2)
CZ = 1 / COS_T                              # 屏幕 z px → 世界 Z
R_W = np.array([np.sqrt(.5), -np.sqrt(.5), 0.])                    # 屏幕 +x 对应的世界向量
F_W = np.array([1., 1., 2 * np.sqrt(.5) * SIN_T / COS_T]); F_W /= np.linalg.norm(F_W)   # 朝向镜头
def _screen_dy(v): return (v[0] + v[1]) * np.sqrt(.5) * SIN_T - v[2] * COS_T
def _screen_dx(v): return (v[0] - v[1]) * np.sqrt(.5)
_A = np.array([[np.sqrt(.5), -np.sqrt(.5), 0], [np.sqrt(.5) * SIN_T, np.sqrt(.5) * SIN_T, -COS_T], F_W])
DN_W = np.linalg.solve(_A, np.array([0., 1., 0.]))
# DN_W：屏幕 +y 1px 对应的世界向量（与 F_W、R_W 正交）

def world(u, v, z): return np.array([u * S, v * S, z * CZ])
def proj(p, T):
    """世界点 → 1x 屏幕坐标"""
    X, Y, Z = p
    return [T[0] + (X - Y) * np.sqrt(.5), T[1] + (X + Y) * np.sqrt(.5) * SIN_T - Z * COS_T]

# ---------- SDF 基本体（p: (N,3)） ----------
def sd_box(p, c, h, r=0.):
    q = np.abs(p - c) - (np.asarray(h) - r)
    return np.linalg.norm(np.maximum(q, 0), axis=1) + np.minimum(q.max(1), 0) - r
def sd_cyl_x(p, c, rad, hx, r=0.):
    """轴沿 X 的圆柱（盘），半径 rad，半长 hx，圆角 r"""
    q = p - c
    d = np.stack([np.hypot(q[:, 1], q[:, 2]) - rad + r, np.abs(q[:, 0]) - hx + r], 1)
    return np.minimum(d.max(1), 0) + np.linalg.norm(np.maximum(d, 0), axis=1) - r
def sd_cyl_y(p, c, rad, hy, r=0.):
    q = (p - c)[:, [1, 0, 2]]
    return sd_cyl_x(q + np.array([0, 0, 0.]), np.zeros(3), rad, hy, r)
def sd_cyl_z(p, c, rad, hz, r=0.):
    q = (p - c)[:, [2, 1, 0]]
    return sd_cyl_x(q, np.zeros(3), rad, hz, r)
def sd_torus_x(p, c, R, r):
    q = p - c
    return np.hypot(np.hypot(q[:, 1], q[:, 2]) - R, q[:, 0]) - r
def sd_ellip_x(p, c, ry, rz, hx, r=0.):
    """轴沿 X、截面为椭圆（Y 半轴 ry、Z 半轴 rz）的盘"""
    q = (p - c) * np.array([1, 1, ry / rz])
    return sd_cyl_x(q, np.zeros(3), ry, hx, r)

def render(scene, material, T, bbox1x, light=(0.55, 0.30, 0.78), ss=3, bg=None, shadow_k=0.42, steps=160):
    """scene(p) -> (d, id)；material(p, n, id) -> (albedo (N,3) 0..1, spec, shin, env 环境反射强度)
    bbox1x = (x0, y0, x1, y1) 1x 屏幕框。返回 2x 规范图上的 (rgb 0..1, alpha, shadow 0..1 背景暗化系数)。"""
    x0, y0, x1, y1 = bbox1x
    w2, h2 = (x1 - x0) * 2, (y1 - y0) * 2
    n = ss
    ys, xs = np.mgrid[0:h2 * n, 0:w2 * n]
    sx = x0 + (xs + .5) / (2 * n) - T[0]; sy = y0 + (ys + .5) / (2 * n) - T[1]
    O = sx.reshape(-1, 1) * R_W + sy.reshape(-1, 1) * DN_W + 600 * F_W
    D = -F_W
    t = np.zeros(len(O)); hit = np.zeros(len(O), bool); alive = np.ones(len(O), bool)
    for _ in range(steps):
        idx = np.nonzero(alive)[0]
        if not len(idx): break
        d, _ = scene(O[idx] + t[idx, None] * D)
        t[idx] += d * 0.9
        h = d < 0.02; hit[idx[h]] = True; alive[idx[h]] = False
        alive[idx[t[idx] > 1400]] = False
    P = O + t[:, None] * D
    rgb = np.zeros((len(O), 3)); L = np.asarray(light, float); L /= np.linalg.norm(L)
    hidx = np.nonzero(hit)[0]
    if len(hidx):
        p = P[hidx]; e = 0.05
        n_ = np.stack([scene(p + np.array(v) * e)[0] - scene(p - np.array(v) * e)[0] for v in ([1, 0, 0], [0, 1, 0], [0, 0, 1])], 1)
        n_ /= np.linalg.norm(n_, axis=1, keepdims=True) + 1e-9
        _, ids = scene(p)
        alb, spec, shin, envk = material(p, n_, ids)
        # AO：沿法线采样
        ao = np.ones(len(p))
        for k, h in enumerate((0.8, 1.8, 3.2, 5.0)):
            dd, _ = scene(p + n_ * h)
            ao -= (h - np.minimum(dd, h)) / h * (0.5 ** k) * 0.32
        ao = np.clip(ao, 0.25, 1)
        # 对背景平面（墙 X=0、地 Z=0）也算 AO：靠墙 / 地的地方更暗
        cont = np.clip(np.minimum(p[:, 0], p[:, 2]) / 4, 0, 1) * 0.25 + 0.75
        # 自阴影（软）
        sh = soft_shadow(scene, p + n_ * 0.3, L)
        dif = np.clip(n_ @ L, 0, 1) * sh
        hemi = 0.5 + 0.5 * n_[:, 2]
        V = F_W; Hh = (L + V); Hh /= np.linalg.norm(Hh)
        spc = spec * np.clip(n_ @ Hh, 0, 1) ** shin * sh
        # 环境反射（金属 / 玻璃）：上亮下暗的暖色环境
        Rv = 2 * (n_ @ V)[:, None] * n_ - V
        env = np.clip(0.55 + 0.45 * Rv[:, 2], 0, 1)[:, None] * np.array([1.0, 0.95, 0.86])
        lit = alb * (0.36 * hemi[:, None] * ao[:, None] + 0.86 * dif[:, None] * (0.6 + 0.4 * ao[:, None])) * cont[:, None]
        lit = lit + spc[:, None] * np.array([1.0, 0.97, 0.9]) + envk[:, None] * env * ao[:, None]
        rgb[hidx] = lit
    # 背景阴影：没打中物体的光线落在墙 / 地上，往光源方向追
    shadow = np.zeros(len(O))
    midx = np.nonzero(~hit)[0]
    if len(midx):
        o, dvec = O[midx], D
        tw = np.where(np.abs(dvec[0]) > 1e-6, -o[:, 0] / dvec[0], 1e9)        # X=0 墙
        tf = np.where(np.abs(dvec[2]) > 1e-6, -o[:, 2] / dvec[2], 1e9)        # Z=0 地
        tb = np.where((tw > 0) & ((o + tw[:, None] * dvec)[:, 2] >= 0), tw, tf)
        q = o + tb[:, None] * dvec
        s = soft_shadow(scene, q + np.array([0.3, 0, 0.3]), L, k=5)
        # 接触阴影（AO）：离物体很近的墙 / 地
        dq, _ = scene(q)
        cao = np.clip(1 - dq / 6, 0, 1) ** 2 * 0.55
        shadow[midx] = np.clip((1 - s) * shadow_k + cao, 0, 0.75)
    def down(a, c):
        a = a.reshape(h2, n, w2, n, c).mean((1, 3))
        return a
    rgb2 = down(rgb, 3); a2 = down(hit.astype(float)[:, None], 1)[..., 0]; sh2 = down(shadow[:, None], 1)[..., 0]
    return rgb2, a2, sh2

def soft_shadow(scene, p, L, k=8, tmax=120):
    res = np.ones(len(p)); t = np.full(len(p), 0.4)
    for _ in range(48):
        d, _ = scene(p + t[:, None] * L)
        res = np.minimum(res, np.clip(k * d / t, 0, 1))
        t += np.clip(d, 0.3, 6)
        if (t > tmax).all(): break
    return np.clip(res, 0, 1)

def composite(img2x, rgb, a, sh, bbox1x, gain):
    """把渲染贴进 2x 规范图：先按阴影压暗背景，再按覆盖率叠物体（gain：按周围亮度调色）"""
    x0, y0, x1, y1 = bbox1x
    sub = img2x[2 * y0:2 * y1, 2 * x0:2 * x1, :3].astype(np.float32)
    sub = sub * (1 - sh[..., None])
    obj = np.clip(rgb * 255 * gain, 0, 255)
    # 描边：覆盖率的外缘一圈压暗成深棕（和生成家具的暗色轮廓一致）
    import cv2
    ring = np.clip(cv2.dilate((a > 0.5).astype(np.uint8), np.ones((3, 3), np.uint8)).astype(np.float32) - (a > 0.5), 0, 1)
    sub = sub * (1 - 0.55 * ring[..., None]) + np.array([40, 28, 20.]) * 0.55 * ring[..., None]
    sub = sub * (1 - a[..., None]) + obj * a[..., None]
    img2x[2 * y0:2 * y1, 2 * x0:2 * x1, :3] = np.clip(sub, 0, 255).astype(np.uint8)
