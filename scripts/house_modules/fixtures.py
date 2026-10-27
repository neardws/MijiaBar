"""每个模块的灯具槽 / 徽章 / 标签（模块内 1x 坐标由地面参数换算）。

位置用地面参数表示：u 沿 NE 墙（0..fw），v 沿 NW 墙（0..1），z = 离地高度（px）。
灯具 id 沿用 Phase 1（living: floor_lamp/sconce/tv/ac；bedroom: bedside/ac；study: ceiling/monitor/ac；generic: entry_light），
新模块：kitchen: pendant；bathroom: ceiling；balcony: wall_lamp。
"""
import sys; sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
from geom import W, FH, module_geom

def P(g, u, v, z=0):
    T = g['T']
    return [round(T[0] + u * W / 2 - v * W / 2), round(T[1] + u * FH / 2 + v * FH / 2 - z)]

def quad(g, u, v, z, w, h):
    c = P(g, u, v, z)
    return [[c[0] - w // 2, c[1] - h // 2], [c[0] + w // 2, c[1] - h // 2], [c[0] + w // 2 + 2, c[1] + h // 2], [c[0] - w // 2 - 2, c[1] + h // 2]]

def ell(g, u, v, rx, ry):
    c = P(g, u, v)
    return [c[0], c[1], rx, ry]

def lamp(g, id, u, v, z, slot=0, wall=None, kind='lamp'):
    src = P(g, u, v, z)
    d = {"id": id, "kind": kind, "role": "light", "slot": slot, "source": src, "radius": 110,
         "pool": ell(g, u + 0.12, v + 0.22, 110, 44), "shade": quad(g, u, v, z, 16, 22),
         "reveal": [src[0], src[1] + 30, 140, 92]}
    if wall:
        # 墙挂灯：anchor = 灯具本体所在点（合成器据此判断它在哪一段墙上、那段墙是否被切）；
        # 调用处再给 alt（地面点）：墙被切时 App 把灯具位 / 设备徽章挪到这里，光池照旧
        d["wall"] = wall; d["anchor"] = src
    return d

def ceiling(g, id, u, v, slot=0):
    # alt = 编辑模式里灯具位的落点：光斑中心往上一点（“天花板上”），不和地板中部的徽章位叠在一起
    return {"id": id, "kind": "ceiling", "role": "light", "slot": slot,
            "pool": ell(g, u, v, 120, 48), "reveal": ell(g, u, v, 160, 80), "alt": P(g, u, v, 40)}

def flow_reveal(g, u, v, sx):
    """空调的 reveal：出风口正下方的送风区（送风粒子 + 冷光都在这），不是地板中间。"""
    x, y = P(g, u, v, 72)
    return [x + 10 * sx, y + 20, 44, 34]

def ac_nw(g, alt=(0.28, 0.42), alt2=None):
    """NW 墙壁挂空调（卧室源图里画的那台；客厅用 module_ac 同位置贴了一台）。
    所在墙被切掉时：空调本体不可见，App 在地上 alt 点显示一个空调徽章代替。"""
    d = {"id": "ac", "kind": "ac", "role": "ac", "slot": 0, "wall": "nw",
         "vent": [P(g, 0.02, 0.6, 72), P(g, 0.02, 0.38, 72)], "led": P(g, 0.02, 0.34, 84),
         "core": quad(g, 0.02, 0.46, 81, 50, 22), "reveal": flow_reveal(g, 0.02, 0.49, 1),
         "anchor": P(g, 0.02, 0.46, 81), "alt": P(g, *alt)}
    if alt2: d["alt2"] = P(g, *alt2)
    return d

def ac_ne(g, u0, u1, alt, alt2=None):
    """NE 墙壁挂空调（卧室那台镜像过来、缩短，见 scripts/house_modules/add_ac.py）：u0..u1 = 出风口沿墙的范围。"""
    um = (u0 + u1) / 2
    d = {"id": "ac", "kind": "ac", "role": "ac", "slot": 0, "wall": "ne",
         "vent": [P(g, u0, 0.02, 72), P(g, u1, 0.02, 72)], "led": P(g, u0 + 0.05, 0.02, 85),
         "core": quad(g, um + 0.03, 0.02, 81, 40, 22), "reveal": flow_reveal(g, um, 0.02, -1),
         "anchor": P(g, um, 0.02, 80), "alt": P(g, *alt)}
    if alt2: d["alt2"] = P(g, *alt2)
    return d

def curtain(g, name, wall, alt, alt2=None):
    """窗帘位：贴片（scripts/house_modules/curtains.py）在运行时叠在窗上，按开合度露出两侧的一部分；
    anchor = 窗中心（判断所在墙段是否被切），墙被切时 App 在 alt 地面点显示窗帘徽章。"""
    from curtains import geometry
    d = geometry(name)
    q = d['quad']
    cx = round((q[0][0] + q[1][0]) / 2); cy = round((q[0][1] + q[1][1] + q[2][1] + q[3][1]) / 4)
    return {"id": "curtain", "kind": "curtain", "role": "curtain", "slot": 0, "wall": wall, **d,
            "anchor": [cx, cy], "alt": P(g, *alt), **({"alt2": P(g, *alt2)} if alt2 else {})}

def face_quad(g, u, v0, v1, z0, z1):
    """NW 墙前（u = 离墙深度）一块竖直面：v0..v1 × z0..z1 的四个角（左上、右上、右下、左下）"""
    return [P(g, u, v1, z1), P(g, u, v0, z1), P(g, u, v0, z0), P(g, u, v1, z0)]

def water_heater(g):
    """卫生间 NW 墙横置电热水器（appliance_models.Heater，add_appliances.py 渲染进美术）。
    display = 正面圆形表盘（App 动态画：待机蓝、加热时火光闪），led = 指示灯，body = 点击区域。"""
    from appliance_models import Heater
    a = Heater().anchors(g['T'])
    return {"id": "water_heater", "kind": "water-heater", "role": "water-heater", "slot": 0, "wall": "nw",
            "display": a['display'], "led": a['led'], "body": a['body'],
            "anchor": a['anchor'], "alt": P(g, 0.47, 0.4)}   # alt = 绿植前方、浴缸和洗手台之间的空地

def washer(g):
    """阳台洗衣机（appliance_models.Washer，NW 墙根）：door = 滚筒门 {c 圆心, s / t 门面上每 1px 宽 / 高的屏幕位移,
    r / ry 玻璃水平 / 竖直半径}（App 在门里画转动的衣物）；display = 面板显示屏，led = 运行灯。"""
    from appliance_models import Washer
    a = Washer().anchors(g['T'])
    return {"id": "washer", "kind": "washer", "role": "washer", "slot": 0,
            "door": a['door'], "display": a['display'], "led": a['led'], "body": a['body']}

def fridge():
    """厨房冰箱（源图里本来就有）：上门右侧一块显示屏，App 按在线 / 开关点亮。"""
    return {"id": "fridge", "kind": "fridge", "role": "fridge", "slot": 0,
            "display": [[144, 132], [150, 130], [150, 134], [144, 136]],
            "body": [[130, 128], [160, 118], [160, 152], [130, 162]]}

# 1x1 模块的徽章位：地板中心周围三点（左、右、前），彼此 ≥ 60px，离相邻房间的徽章位也够远
SPREAD = [(0.28, 0.66), (0.66, 0.28), (0.74, 0.74)]

def spec(module):
    fw = 2 if module == 'living' else 1
    g = module_geom(fw)
    b = lambda pts: [P(g, u, v) for u, v in pts]
    # 房间名标签：NW 墙上沿。客厅 / 卧室的 NW 墙中段挂着空调，标签挪到空调左边（靠墙的外端）
    lab = P(g, 0.08, 0.9 if module in ('living', 'bedroom') else 0.62, 98)
    floor_label = None
    if module == 'living':
        lights = [dict(lamp(g, 'floor_lamp', 0.07, 0.09, 63), pool=ell(g, 0.3, 0.3, 110, 44)),
                  dict(lamp(g, 'sconce', 0.81, 0.02, 71, slot=1, wall='ne', kind='sconce'), radius=75, strength=0.85, pool=ell(g, 0.85, 0.25, 90, 36),
                       alt=P(g, 0.88, 0.08)),   # 墙被切时的徽章位：电视左边、NE 墙根的空地
                  {"id": "tv", "kind": "screen", "role": "tv", "slot": 0, "style": "tv",
                   # 电视柜在右格正中（约 u=1.45, v=0.5，retouch.py 从 NE 墙根往前搬了 0.35 格）；
                   # 屏幕平行于 NE 墙，按规范图实测的平行四边形
                   "screen": [[316, 176], [363, 196], [363, 232], [316, 213]], "throw": [-40, 40], "radius": 85,
                   "reveal": ell(g, 1.35, 0.9, 120, 75)},
                  ac_nw(g, alt=(0.25, 0.1)),   # 沙发上方的 NW 外墙（composed 布局里客厅在最左列时这面墙完整）；alt = 落地灯右边、后墙角的地板
                  curtain(g, 'living', 'ne', (0.62, 0.1))]   # alt = 窗下 NE 墙根的空地
        badges = b([(0.5, 0.75), (0.95, 0.62), (1.4, 0.9), (1.8, 0.75)])   # 电视柜挪到右格中间后重新排开
        floor_label = P(g, 0.35, 0.3, 0)   # 两面后墙都被切时：沙发前的空地（避开徽章位）
    elif module == 'bedroom':
        lights = [dict(lamp(g, 'bedside', 0.07, 0.09, 44), pool=ell(g, 0.2, 0.3, 100, 40)),
                  ac_nw(g, alt=(0.12, 0.4)),                     # alt = 床头柜和斗柜之间、NW 墙根的地板
                  # alt = 床右侧、右前沿的地板；右边邻格不比卧室低时这里会被前墙挡住要往里挪（会挪到床上）→ 改用
                  # alt2 = 床尾和地毯之间的地板（只有前排有房间时才需要挪）。composer 选挪动少的那个
                  curtain(g, 'bedroom', 'ne', (0.99, 0.34), alt2=(0.82, 0.82))]
        badges = b([(0.55, 0.8), (0.8, 0.55), (0.3, 0.85)])   # b3 挪到地毯左边（原位置和 b1 挨着、离空调 alt 太近）
        floor_label = P(g, 0.65, 0.95, 0)   # 两面后墙都被切时：地毯右侧、床尾前的空地（不压枕头）
    elif module == 'study':
        lights = [ceiling(g, 'ceiling', 0.55, 0.55),
                  {"id": "monitor", "kind": "screen", "role": "tv", "slot": 0, "style": "monitor",
                   "screen": quad(g, 0.48, 0.12, 46, 24, 20), "throw": [-8, 35], "radius": 60,
                   "reveal": ell(g, 0.5, 0.35, 85, 65)},
                  # alt = 书桌右侧、NE 墙根；右边邻格同高时会被右前沿推到书桌前 → alt2 = 地毯前的空地
                  ac_ne(g, 0.71, 0.93, alt=(0.82, 0.27), alt2=(0.95, 0.5)),  # alt2 = 书桌右前方空地（右邻同高时用）
                  curtain(g, 'study', 'ne', (0.38, 0.4))]    # alt = 书桌前的空地（不落在椅子上）
        badges = b([(0.55, 0.85), (0.9, 0.75), (0.3, 0.7)])   # b1 挪开，给空调 alt2 腾空地
        floor_label = P(g, 0.45, 0.9, 0)   # 两面后墙都被切时：地毯左侧空地
    elif module == 'generic':
        lights = [ceiling(g, 'entry_light', 0.5, 0.55)]
        badges = b([(0.55, 0.85), (0.9, 0.75), (0.3, 0.7)])
        floor_label = P(g, 0.5, 0.55, 0)
    elif module == 'kitchen':
        # 吊灯本体不画（剖面里吊在半空，切墙时会被竖条切成半个）：按看不见灯具的吸顶灯处理，光池落在餐桌上
        lights = [ceiling(g, 'pendant', 0.37, 0.37), fridge(), curtain(g, 'kitchen', 'nw', (0.1, 0.85))]   # alt = 窗下 NW 墙根
        # 徽章位分散在地板中部一圈（原来挤在前沿两个角，编辑模式里和前面房间的徽章位叠在一起）
        badges = b(SPREAD)
        floor_label = P(g, 0.84, 0.5, 0)   # 两面后墙都被切时标签放这（右侧空地，避开餐桌）
    elif module == 'bathroom':
        lights = [ceiling(g, 'ceiling', 0.5, 0.5), water_heater(g)]
        badges = b(SPREAD)
        floor_label = P(g, 0.55, 0.9, 0)   # 两面后墙都被切时：浴缸前的空地
    elif module == 'balcony':
        lights = [dict(lamp(g, 'wall_lamp', 0.02, 0.69, 72, wall='nw', kind='sconce'), radius=80, pool=ell(g, 0.3, 0.7, 100, 40),
                     alt=P(g, 0.4, 0.97)), washer(g)]   # alt = 洗衣机左前方的空地（墙根被洗衣机和藤椅占了）
        badges = b(SPREAD)
        floor_label = P(g, 0.55, 0.55, 0)   # 两面后墙都被切时：阳台地板中央
    else:
        raise KeyError(module)
    floor_anchors = {
        'living': {'fan': (176, 252), 'dehumidifier': (248, 258), 'heater': (308, 288), 'air_purifier': (388, 272), 'humidifier': (212, 272), 'vacuum': (132, 272)},
        'bedroom': {'fan': (96, 212), 'dehumidifier': (155, 232), 'heater': (198, 218), 'air_purifier': (236, 222), 'humidifier': (274, 202), 'vacuum': (120, 240)},
        'study': {'fan': (118, 222), 'heater': (218, 232)},
        'bathroom': {'dehumidifier': (200, 202)},
    }
    floor_sizes = {'fan': (26, 38), 'dehumidifier': (22, 30), 'heater': (22, 32), 'air_purifier': (16, 42), 'humidifier': (26, 38), 'vacuum': (36, 26)}
    for fixture_id, (anchor_x, anchor_y) in floor_anchors.get(module, {}).items():
        width, height = floor_sizes[fixture_id]
        half_width = width // 2
        role = fixture_id.replace('_', '-')
        lights.append(dict(id=fixture_id, kind=role, role=role, slot=0, anchor=[anchor_x, anchor_y], body=[
            [anchor_x - half_width, anchor_y - height], [anchor_x + half_width, anchor_y - height],
            [anchor_x + half_width, anchor_y], [anchor_x - half_width, anchor_y],
        ]))
    d = dict(label=lab, badges=badges, lights=lights)
    if floor_label: d['floorLabel'] = floor_label
    return fw, g, d

MODULES = ['living', 'bedroom', 'study', 'generic', 'kitchen', 'bathroom', 'balcony']
