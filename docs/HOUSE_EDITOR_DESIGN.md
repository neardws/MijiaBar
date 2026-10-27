# MijiaBar 小屋可编辑化：总体设计（草案）

> 状态：Neil 已批准（2026-10-17），5 个待定问题都按推荐执行；第 2.4 节（配置文件 / 同步 / CLI）按批准意见更新。Phase 1 实现见 PR。
> 原状态：设计稿。基于 `main@128a41e`（0.1.12 + 官网 #29）。
> 配图（设备编辑 / 房间布局 / 风格与装饰的示意图）见 Phase 1 PR 说明。

> 当前默认布局规则见 [HOUSE.md](HOUSE.md#automatic-layout)：无保存布局且厨房、卫生间或阳台有在线可见设备时自动合成 3×2；否则保留经典四室。下文 Phase 1 的四室限制是历史阶段说明，不再代表全部模块的素材范围。布局标签的「自动」清除保存布局，「经典四室」保存显式经典几何。

沿用已定的方向：
- 预渲染像素底图，灯光烘焙成白天/夜晚 × 亮/暗（lit/unlit）几张底图
- 每个放进小屋的设备都有自己的局部亮光
- 灯光锚点按房间模块存
- 房间模块固定、按米家房间名自动匹配，用户不用画户型
- 连通的剖面图，嵌在设备列表顶部；「放大」打开 HouseWindow；点灯具就能开关
- 不再用 SpriteKit / SceneKit / Metal

---

## 1. 现状与差距

### 1.1 现在是怎么做的

| 环节 | 实现 | 位置 |
|---|---|---|
| 底图 | **一整张** 960×540 连通剖面，4 个房间位置固定：客厅（左下）、卧室（左上）、书房（右上）、玄关（右下）。共 4 张 PNG：`house-cutaway-{day,night}-{lit,unlit}.png` | `Resources/House/` |
| 锚点 | `house-cutaway.json`：每个模块有 `region` 多边形和 `lights[]`（`id`/`role`/`slot`/`reveal` 椭圆/`shade`/`screen`/`core`） | 同上 |
| 房间识别 | `HouseModule.from(roomName:)`：只认 living / bedroom / study，其余算 generic；generic 里只有「玄关/门口/走廊」进小屋，其他房间直接丢掉 | `MijiaCore/HouseLayout.swift` |
| 设备放进位置 | `HouseLayout.assign`：按列表顺序，只认 `light / ac / tv` 三类，按 `capacity(module, kind)` 依次占 `slot 0,1…`，放不下的算 overflow（**只计数，界面上不显示**） | 同上 |
| 设备 ↔ 灯具 | `HouseLightSpec.matchedDevice`：用 `(kind, slot 序号)` 对应 JSON 里的灯 | `HouseView.swift` |
| 渲染 | 先铺 unlit；每个房间每盏灯用「房间多边形 ∩ 羽化椭圆」露出 lit；关着的灯具本体用 unlit 盖回去 | `HouseRoomLightLayer` |
| 持久化 | 没有小屋专属配置；只复用 `prefs.json` 里的房间/设备排序（`HomeOrder`）和 `DevicePrefs.hidden` | `Store.swift`、`Order.swift` |

### 1.2 为什么和真实的家对不上

1. **画面是固定的四室一厅。** 不管家里有什么，都画同样 4 个房间、同样的家具：没有电视也画电视，客厅总有落地灯和壁灯，卧室总有空调。设备只决定「哪盏灯亮」，不决定「画了什么」。
2. **房间多了或少了都处理不好。**
   - 两个卧室都会映射到同一个 `bedroom` 区域：灯光叠在一起，标签也叠在一起。`ForEach(rooms)` 里按 module 取区域，没有去重。
   - 厨房、卫生间、阳台、餐厅、儿童房（不含「卧」字）都识别不出来，直接不显示。
   - 「未分配房间」（`roomName == nil`）也被丢掉。
3. **设备类型太少。** 只有 light / ac / tv 有位置。风扇、插座、净化器、除湿机、音箱、摄像机、传感器、门铃都进 overflow，界面上看不到。
4. **位置和画面对不上。**
   - `capacity` 和 JSON 不一致：客厅允许 1 台空调，但客厅画里没有空调，于是客厅空调占了位置，却既不亮也点不到（演示数据 `loadMock()` 里的「客厅空调」就是这样）。
   - 卧室允许 1 台电视，但画里没有电视。
   - 书房的 `tv` 位实际画的是显示器，一台真电视会被放到书桌上。
   - generic 模块只有一盏玄关灯。
5. **分配不可控，也不稳定。**
   - 按列表顺序取前 N 台，用户在列表里拖一下排序，小屋里的灯就换了。
   - 「床头灯」可能被放进落地灯位。
   - 没法指定哪台设备放哪个位置，也没法让某台设备不进小屋。
6. **隐藏设备也会进小屋。** `houseRooms` 用的是全部 `inHome` 设备，没有过滤 `DevicePrefs.hidden`；而列表里已经隐藏的设备，用户通常不想在小屋里看到。
7. **房间顺序不影响画面。** 格子位置由模块类型决定，`HouseLayout.cell()` 定义了却没用上，用户没法调整房间怎么组合。

---

## 2. 数据模型

原则：
- **自动是默认，用户只存覆盖项（稀疏 diff）。** 新设备、新房间照样自动放；「恢复自动」就是删掉覆盖项。
- **用稳定 id，不用序号。** 灯具位用 JSON 里的 `id`（如 `living.floor_lamp`）；房间优先用米家 `Room.id`。
- **素材和配置分开。** 模块目录（随 App / 风格包发布）是只读的；用户配置只引用目录里的 id。

### 2.1 模块目录（只读，随素材发布）

```jsonc
// Resources/House/catalog.json（Phase 1 可以直接扩展 house-cutaway.json）
{
  "schema": 2,
  "style": "cozy-wood",
  "modules": {
    "living": {
      "footprint": [2, 1],            // Phase 2 起：占几格（等距格子单位）
      "fixtures": [                   // 带烘焙局部光的灯具位
        {"id": "floor_lamp", "accepts": ["light"], "hints": ["落地", "floor"], "kind": "lamp", "reveal": [...], "shade": [...]},
        {"id": "sconce",     "accepts": ["light"], "hints": ["壁灯", "wall"], ...},
        {"id": "ceiling",    "accepts": ["light"], "hints": ["吸顶", "主灯", "ceiling"], ...},   // 新增
        {"id": "tv",         "accepts": ["tv"], ...},
        {"id": "ac",         "accepts": ["ac"], ...}                                           // 新增：客厅补一台空调
      ],
      "badges": [                     // 徽章位：给没有专属灯具的设备放像素小图标
        {"id": "b1", "at": [118, 440]}, {"id": "b2", "at": [160, 470]}, {"id": "b3", "at": [300, 455]}
      ],
      "decor": [{"id": "d_plant", "at": [...], "default": "monstera"}],   // Phase 3
      "region": [...], "label": [...]
    }
    // bedroom / study / kitchen / bathroom / balcony / generic 同样结构
  }
}
```

- `accepts` 列的是 `DeviceCategory`；也可以写成设备型号的子类型，例如 `light:desk`，以后再细分。
- 每个灯具位都要有烘焙光（lit 底图里画好的那块）。徽章位**不**烘焙，用小精灵图 + 开机小动效/亮点（见 §4.3）。

### 2.2 用户的小屋配置（每个家庭一份）

```swift
public struct HouseConfig: Codable, Equatable, Sendable {
    public var schema = 1
    public var style: String?                       // nil = 默认风格
    public var layout: [HouseCell]?                 // nil = 自动布局（Phase 2 起生效）
    public var rooms: [String: RoomOverride]?       // key = 米家 roomId（没有 id 时用 "name:<房间名>"）
    public var devices: [String: DeviceOverride]?   // key = did
    public var decor: [String: String]?             // "living.d_plant" -> "cat"（Phase 3）
}
public struct RoomOverride: Codable, Equatable, Sendable {
    public var module: HouseModule?                 // 手动指定模块类型（如 儿童房 → bedroom）
    public var included: Bool?                      // false = 不进小屋；true = 强制放进（generic）
}
public struct HouseCell: Codable, Equatable, Sendable {
    public var room: String                         // roomId
    public var col: Int, row: Int                   // 等距格子坐标，后排 row 小
}
public struct DeviceOverride: Codable, Equatable, Sendable {
    public var visible: Bool?                       // false = 小屋里不显示（列表照常显示）
    public var place: Placement?                    // nil = 自动
    public enum Placement: Codable, Equatable, Sendable {
        case fixture(String)                        // "floor_lamp"（在设备所在房间的模块里）
        case badge                                  // 只用徽章
        case none                                   // 不进画面，只在 chips 里出现
    }
}
```

- **存放位置、同步、CLI：** 见下面 §2.4（已按 Neil 的意见改成独立的 `house.json`，不放进 `prefs.json`）。
- **迁移和默认值：** 没有 `house.json` 时完全自动（比今天更贴近真实设备）；设备 key 用 did，房间 key 用米家 roomId（旧缓存里没有 id 时用 `name:<房间名>`，拿到 id 后读取时兼容旧 key）；指定的位置在当前模块里不存在 / 不接受这类设备时自动退回「自动」。
- **和现有隐藏的关系：** `DevicePrefs.hidden`（包括离线 / 久未使用的自动隐藏）默认也不进小屋；`visible` 只影响小屋。

### 2.4 配置文件、多 Mac 同步与 Agent Native（已定）

**文件：** 独立的 `house.json`（schema 1，格式和 JSON Schema 见仓库 `docs/HOUSE.md`，`mijiabar house schema` 可打印）。每个家庭一组覆盖项：
`rooms[roomKey] = {module, updatedAt}`、`devices[did] = {visible, place, updatedAt}`；`place` 用字符串 `fixture:<id>` / `badge` / `none`，方便人和 Agent 直接写。未知字段忽略，以后加 `layout` / `style` / `decor` 不破坏旧版本。

**同步方案选择（App 是 Developer ID 签名、非沙盒、非 App Store）：**

| 方案 | 可行性 | 结论 |
|---|---|---|
| `NSUbiquitousKeyValueStore` | 需要 `ubiquity-kvstore-identifier` 权限，Developer ID 不支持；1 MB 上限；CLI / Agent 读不到 | 不用 |
| CloudKit / iCloud Documents 容器 | Developer ID 可以用，但要 Xcode 管理的描述文件嵌进 App；现在是 SPM + `codesign` 打包，CLI（`com.neardws.MijiaBar.cli`）要单独的描述文件才能进同一个容器；Agent 读不到 | 太重，不用 |
| **iCloud Drive 里的普通文件**（`~/Library/Mobile Documents/com~apple~CloudDocs/MijiaBar/house.json`） | 非沙盒 App 直接读写，不需要任何权限；CLI、Agent、人都能直接看和改；在 Neil 的 Mac（macOS 27）上实测可读写、没有弹窗 | **采用，默认** |
| 用户选的文件夹（Dropbox / Syncthing / NAS） | 同上 | 作为选项 |
| 本机 `Application Support/MijiaBar/house.json` | — | 没开 iCloud Drive 时的默认 |

位置是每台 Mac 自己的设置（`Application Support/MijiaBar/house-location.json`），`mijiabar house sync icloud|local|<文件夹>` 切换（切换时合并内容、不删旧文件）；环境变量 `MIJIABAR_HOUSE_FILE` 优先（测试 / 脚本）。

**并发：**
- 同一台 Mac：App、CLI、MCP 都走 `HouseStore.update`，在 `NSFileCoordinator` 下「读最新 → 改 → 原子写回」，不会互相覆盖。
- 多台 Mac：每条覆盖项带 `updatedAt`，按条目「后写入的赢」合并；iCloud 生成的冲突副本（`house 2.json` 等）和未解决的 `NSFileVersion` 冲突版本在读取时合并、下次写入时清掉。
- 恢复自动写的是「空条目（墓碑）」而不是直接删除，这样恢复也能同步出去；墓碑 30 天后清理。
- App 用 `DispatchSource` 监视文件所在目录（原子写入会替换文件本身），防抖 0.3 秒后重新读取；另外每 60 秒兜底检查一次。
- 已知限制：两台 Mac 时钟差太大时，「后写入的赢」可能判断错；iCloud 开了「优化 Mac 储存空间」时文件可能被移出本地，读取时会自动下载，离线时沿用内存里上一次的结果。

**Agent Native（沿用现有 CLI 的约定：`mijiabar <命令>`，`--json` 输出，修改类命令总是输出 JSON；MCP 工具同名同参）：**

```
mijiabar house show [--home H] [--json]        # 解析后的小屋：房间、每台设备的位置（fixture:<id> / badge:<id> / null）、没进小屋的房间及原因、隐藏设备
mijiabar house slots [--json]                  # 模块目录：灯具位 id、接受的设备类型、名字提示词、徽章数
mijiabar house hide|unhide <设备>
mijiabar house assign <设备> <灯具位|badge|none|auto>   # 校验：只能放进设备所在房间模块里、接受该类型的灯具位，否则报错并列出可用位置
mijiabar house set <设备> [--visible true|false|auto] [--place …]
mijiabar house room <房间> <living|bedroom|study|generic|none|auto>
mijiabar house reset [<设备> | --room <房间>] [--home H]
mijiabar house sync [icloud|local|<文件夹>]
mijiabar house schema
```

MCP：`get_house`、`get_house_slots`、`set_house_device`、`set_house_room`、`reset_house`。权限：只改布局、不控制设备，所以除了 Agent 模式「已关闭」以外都允许，不弹确认框。house 命令只读本地设备缓存，不读钥匙串（顺手把 CLI 的登录信息改成用到时才读，避免无谓的钥匙串弹窗）。

### 2.3 运行时派生结构（不持久化）

```swift
struct ResolvedHouse {               // 每次设备 / 状态 / 配置变化时重算，纯函数，放 MijiaCore 便于测试
    let style: String
    let cells: [ResolvedCell]        // 每格：模块、米家房间、标题
    let placements: [String: ResolvedPlacement]   // did -> (cell, fixtureId | badgeId)
    let chipsOnly: [Device]          // 可见但没进画面的设备
    let excludedRooms: [String]      // 没进小屋的米家房间（编辑面板里显示）
}
```

`HouseRoom.lighting` 不再用 `lampLevels[2] / tv / ac`，改成 `[fixtureId: Double]`，`strength()` 直接查表。这样一个模块想要几盏灯都可以，也不需要 `capacity()` 了。

---

## 3. 自动默认算法

在 `MijiaCore` 里做成纯函数 `HouseResolver.resolve(devices, rooms, prefs, catalog) -> ResolvedHouse`，用单元测试覆盖。

1. **房间 → 模块**（按关键词打分，简繁英都认）：
   - 客厅 / 起居 / living / lounge / 餐厅（可选）→ `living`
   - 卧 / 臥 / 儿童房 / 次卧 / 主卧 / 睡房 / bedroom / kids → `bedroom`
   - 书房 / 办公 / 工作室 / study / office → `study`
   - 厨房 / 廚房 / kitchen → `kitchen`
   - 卫生间 / 洗手间 / 浴室 / 衛浴 / bath / toilet → `bathroom`
   - 阳台 / 陽台 / balcony / 露台 → `balcony`
   - 玄关 / 门口 / 走廊 / entry / hall → `generic`（玄关样式）
   - 其他 → `generic`（通用小房间），**默认放进小屋**，但如果房间里一台可显示的设备都没有就跳过
   - 名字没认出来时，用设备构成兜底：有厨房电器 → kitchen；有水浸传感器 + 浴霸 → bathroom
   - 用户的 `RoomOverride.module` 优先级最高
2. **选房间、定格子：**
   - 格子数量上限 N（建议 6）。超出的房间按「可显示设备数」从多到少排，排不下的进 `excludedRooms`。
   - **自动布局（Phase 2）：** 客厅放前排左边（占 2 格），卧室和书房放后排，厨房 / 卫浴 / 阳台填剩下的格子，玄关放前排右边。遵守模块的 `footprint`，并保证外轮廓是凸的（2×2、3×2 这种）。
   - 有 `layout` 覆盖时，直接用它；里面已经不存在的房间去掉，新出现的房间补到空格里。
   - Phase 1 只有固定的 4 个房间位，「布局」退化为：每种房间位放一个米家房间。多出来的同类房间（第二个卧室）进 `excludedRooms`，用户可以手动和第一个调换。
3. **设备 → 位置**（每个房间单独算）：
   - 设备过滤：可见（没有隐藏且 `visible != false`）、`category != other`。离线设备照样放，但画成灰的、不亮。
   - 先处理用户覆盖：`fixture(id)` 直接占位；如果冲突，以后改的那个为准，被挤掉的设备回到自动。
   - 剩下的设备按「名字关键词命中灯具位 `hints`」的优先级放进 `accepts` 包含它类别的空灯具位：先放命中关键词的，再按列表顺序放。
     - 例：「床头灯」→ bedside；「显示器 / 屏幕灯」→ monitor；「吸顶灯 / 主灯」→ ceiling。
   - 灯具位不够，或者设备类别没有专属灯具（风扇、插座、净化器、除湿机、音箱、摄像机、门铃、传感器……），就放进**徽章位**，按类别图标显示。
   - 徽章位也满了 → 只在 chips 里出现，房间标签上显示「+N」。
4. **结果要稳定：** 输入相同，输出一定相同。这样改列表排序不会导致小屋里的灯乱跳：用 did 排序作为最后的比较依据，而不是依赖列表顺序。这一点要和现在的行为区分开。

---

## 4. 素材怎么适配任意房间组合（最大技术风险）

### 4.1 难点

- 现在的底图是一整张画（源 JPG 像素化后再烘焙）。房间形状不规则，墙是共用的，光已经烘焙进去，没法直接拆开重新拼。
- 要支持「任意组合」，需要同时满足：
  - 每个模块能单独出图，并有自己的 lit/unlit 版本
  - 拼起来像一栋连通的房子（墙、地板厚度、外轮廓都对得上）
  - 每个灯具的局部光仍然只露出 lit 层
- 风格包会让工作量翻倍：模块数 × 2 个时段 × lit/unlit × 风格数。

### 4.2 方案对比

| 方案 | 做法 | 优点 | 缺点 |
|---|---|---|---|
| **A. 整屋预设库** | 预先画好若干整张房子：3 室、4 室、5 室、6 室，每种 1–2 个户型，每个都有自己的 JSON。用户只能选预设，再把米家房间放进预设里的房间位 | 质量最高、没有接缝；完全沿用现在的管线 | 组合有限；每个户型 × 风格都要整张重画，素材量爆炸；房间位类型被锁死（比如没有「两卧 + 厨房」这种预设就做不到） |
| **B. 等距模块瓦片**（推荐，作为 Phase 2 目标） | 固定等距格子（比如 1 格 = 240×140 的菱形占地，墙高固定）。每个模块按 `footprint`（1×1 / 2×1）画成**独立的剖面房间**：只画后墙（左后、右后两面）、地板和地板厚度，没有前墙。拼的时候按画家算法（row 小、col 小的先画）叠放；相邻房间之间的隔墙由**后面那个房间的后墙**充当，所以不会重复。外轮廓、地基边、墙顶封边用一组「接缝件」（edge tiles）补齐 | 组合自由；一个模块画一次就能用在各种户型里；灯光仍按模块烘焙（光本来就被 region 限制在房间里，不会穿墙）；风格包按模块增加，成本是线性的 | 要重画素材（现在的整图不在格子上）；接缝和墙角需要细心设计；跨房间的门洞透光要么放弃，要么做专门的门洞件 |
| **C. 模块 + 运行时合成一张缓存图** | 在 B 的基础上，布局一变就把当前布局离屏合成成两张整图（该时段的 unlit/lit），之后的渲染完全沿用现在的 `HouseCutawaySceneView`（一张 unlit + 按灯具露出 lit） | 运行时的渲染代码几乎不用改；内存和绘制开销跟现在一样 | 合成本身要几毫秒到几十毫秒，只在布局 / 风格 / 时段变化时做一次，可以接受 |

**推荐：B 的素材规范 + C 的渲染方式**。同时把现在这张整图保留成「经典四室」预设（就是一个 A 方案的布局），作为默认值，也作为 Phase 2 素材出问题时的退路。

### 4.3 B/C 的具体规范（Phase 2 开工前先做一个 spike 验证）

- **格子：** 等距 2:1。单格占地菱形宽 W=240、高 120（像素格 PX=2）。墙高 H=150。地板厚度 12。画布按格子数动态计算大小。
- **每个模块交付：**
  - `module-<id>-{day,night}-{unlit,lit}.png`：透明背景，左上锚点对齐格子原点
  - `module-<id>.json`：
    - 在模块局部坐标下的 `region`、`fixtures`、`badges`、`decor`
    - `doorways`（左墙 / 右墙门洞，可选）
    - `wallMask`（后墙区域，用来在拼接时盖住前一个房间画出界的部分）
- **接缝件：** `edge-front-left`、`edge-front-right`、`corner`、`wallcap`、`foundation`，也都有 day/night 版本；外墙不需要 lit 版本。
- **烘焙：** `gen-house-baked-lighting.py` 改成按模块跑。光池的 pool / reveal 只在本模块 region 内。
- **合成（C）：**
  - 在 MijiaCore 里根据布局和 catalog 算出每个模块的屏幕偏移
  - App 端用 `CGContext` 画进一张 `CGImage`：先 unlit 合成一张，lit 合成一张
  - 锚点按模块偏移转成全局坐标后交给现有的 `HouseRoomLightLayer`
  - 缓存 key = (style, layout hash, phase)
- **布局约束：**
  - 最多 3 列 × 2 行；客厅可以是 2×1，其他都是 1×1
  - 外轮廓必须是矩形或 L 形，不允许有洞，这样接缝件的种类有限
  - 违反约束时，编辑器里不让放下
- **关着的灯具、空位：**
  - 未配置替代贴片的灯具位没有设备时，家具照常画（暗的）、不能点。这是最省素材的兜底做法，也符合「默认布局可以」的要求。
  - Phase 3 已实现灯具位的可选 `absentVariant`：没有电视就换成书柜，用一小块贴片覆盖。经典整图和 cozy 模块已提供客厅电视、客厅 / 卧室空调、书房显示器示例；有设备（包括关机 / 离线）或墙被切掉时不画替代贴片。
- **徽章精灵：** 每个设备类别一张 32×32 的像素图标，各有 off / on 两帧（on 可以加一点亮点或 2–4 帧动效，例如风扇转动），day/night 共用。约 12 类 × 2 帧，体积很小。徽章不做烘焙光，开着的时候在图标脚下画一个小光点就够了。

### 4.4 Spike 验收标准（Phase 2 的第一个 PR）

- 用两个模块（living 2×1 + bedroom 1×1）加接缝件，拼出 3 种布局，day/night × 全开/全关的截图。
- 对比现在的整图，看：墙角接缝不露缝、透明边缘没有毛边、局部光不越过隔墙、像素格对齐（PX=2）。
- 合成耗时 < 30 ms（M1，debug 构建），合成后的常驻内存 ≤ 现在的 2 倍。

---

## 5. 编辑交互（只在 HouseWindow 里）

菜单栏里嵌入的小屋保持只读：点灯具开关、点「放大」开窗口。编辑只在窗口里进行，避免误触，也不挤占菜单栏面板的空间。

- **进入方式：** 窗口标题栏的「编辑」按钮。进入编辑模式后，顶部有三个标签：**设备 / 房间布局 / 风格与装饰**，右上角是「恢复自动」和「完成」。
- **设备标签**（`mockup-edit.png`）：
  - **画面上：**
    - 灯具位画成虚线轮廓，标签写着设备名，或者「空」
    - 徽章位是小方块，空的那些显示「＋」
    - 点一个位置会弹出菜单，列出这个房间里 `accepts` 匹配的设备，以及「留空」
  - **右侧面板：**
    - 按米家房间分组列出设备，每行有图标、名称、当前放在哪个位置、眼睛开关（只控制在小屋里显示与否）
    - 最下面一组是「未放进小屋」，带原因（离线 / 房间没有对应模块 / 位置满了）
  - **拖动：**
    - 把设备从面板拖到灯具位或徽章位
    - 拖到房间外，或者拖回面板 = 改回自动 / 不放
    - 拖到别的房间的灯具位：**不会改米家里的房间**，只会提示「这台设备在米家属于 X 房间」。默认不允许跨房间放置，避免和米家数据冲突（见待定问题）
  - 编辑时灯光照常预览，点灯具**不会**开关设备（编辑模式下点击 = 选中位置）。
- **房间布局标签**（`mockup-arrange.png`）：
  - 俯视格子，房间卡片可以拖动交换位置，客厅占 2 格
  - 空格子里有「＋ 添加模块」，可以把「没放进小屋」的米家房间放进来，或者改某个房间的模块类型
  - 右侧是米家房间 ↔ 模块的对照表
  - 下方实时预览拼好的剖面
  - Phase 1 的简化版：只有对照表，没有格子；只能在 4 个固定房间位之间换房间、给房间改模块类型、把房间排除出小屋
- **风格与装饰标签**（`mockup-style.png`）：
  - 风格卡片；没下载的风格显示体积，点了才下载
  - 右侧按模块列出装饰位，每个位置几个选项加「不放」
- **撤销：** 编辑过程中的改动先存在内存里的 `draft: HouseConfig`，点「完成」才写入 `prefs.json`。支持 ⌘Z；Esc 等于放弃改动。
- **辅助功能：** 每个位置都有 VoiceOver 标签，例如「客厅 · 落地灯位 · 已放：落地灯」。不能用拖动的用户可以用弹出菜单完成所有操作。

---

## 6. 风格与装饰

**v1 已实现（风格包按需下载）：** 温馨木屋始终内置；其余四种风格支持内置或下载，选择器显示体积、进度、
失败重试与本地移除。内置签名索引固定 SHA-256 / 大小，解包前验证路径，完成后原子安装；缺包或缺模块回退温馨木屋。
R2 上传是维护者手动步骤，尚未上传前打包默认保持 `HOUSE_STYLE_BUNDLE=all`。实现与格式见 `HOUSE.md`，上传流程见
`UPDATING.md`。新增 mock 状态截图入口供执行器验证；本实现阶段不启动 GUI、不生成快照。

- **风格包：**
  - 包含：`manifest.json`（id、名称、版本、需要的最低 App 版本、模块列表）+ 每个模块的 4 张底图 + 模块 JSON + 接缝件 + 缩略图
  - **约定：所有风格的同一个模块，灯具位 id 集合相同**（不同风格可以多出一些可选位置）。所以换风格时设备的位置不用变；新风格里没有的位置，对应设备退回自动。
  - 内置一个默认风格（现在的温馨木屋）。其他风格放在 R2（`files.neardws.com/mijiabar/house/styles/<id>/<ver>.zip`），按需下载到 `Application Support/MijiaBar/House/styles/`，下载后校验 sha256。
  - 风格包缺少某个模块时，回退到默认风格的这个模块。这样可以先只出 3–4 个常用模块。
- **装饰：**
  - 装饰位是模块 JSON 里的 `decor[]`，每个位置有允许的装饰类别（植物 / 宠物 / 墙饰 / 地毯……）
  - 装饰是小精灵图：day/night 各一张，不参与烘焙光，画在 unlit 层之上
  - 夜晚装饰只给一个统一的暗化系数；如果装饰正好在某盏灯的光池里，可以乘上那盏灯的 strength 稍微提亮，算小优化
  - 节日装饰包只包含装饰精灵和默认选择，不换底图
- **素材管线：** 沿用 `scripts/gen-house-*.py`，按模块和风格参数化：`gen-house-module.py --style cozy-wood --module living`。这个脚本同时输出 `preview-house-snapshots.py` 用的预览图。

---

## 7. 性能与内存（菜单栏 App）

- **现在：**
  - 960×540 的 RGBA 图解码后约 2 MB 一张
  - `HouseAssets` 会缓存已经加载过的每张图，跨过白天 / 夜晚交替后，4 张都会常驻（约 8 MB）
  - 每盏灯一个 SwiftUI mask 层，加起来大约十几层
- **目标：**
  - 只缓存当前时段的 unlit + lit 两张合成图（约 4 MB）。时段切换或布局改变时释放旧图。
  - 模块原图只在合成时加载，合成完就释放。或者用 `NSCache`，内存紧张时自动回收。
  - 6 个房间的布局，画布大约 1440×720，两张图约 8 MB，可以接受。
  - 菜单栏嵌入时按显示宽度（约 330 pt × 2x）**预缩放**一份更小的缓存。小屋窗口用原尺寸。
  - 灯具 mask：灯具很多（>20）时，把所有亮着的灯的 reveal 预先合成成一张 mask 图，按状态 hash 缓存，避免层数线性增长。
  - `houseRooms` 改成 `ResolvedHouse`，只在设备列表、状态、配置变化时重算，不在每次 body 刷新时算。`TimelineView` 每 60 秒刷新一次只用来判断时段。
  - 风格包放在磁盘上，不随 App 打包。默认风格的模块素材比现在的整图多出约 1–2 MB（因为多了 kitchen / bathroom / balcony），用 PNG 量化 / WebP 控制体积。

---

## 8. 分阶段计划

### Phase 1：显示真实设备 + 显示 / 隐藏（素材基本不动）

范围：
- 新增 `HouseResolver`（MijiaCore，纯函数）和 `HouseConfig`，存到 `Prefs.house`；`Device.roomId`。
- 灯具位改用 JSON 的 `id`，`lighting` 改成 `[fixtureId: Double]`，删掉 `capacity()`。修正 capacity 和画面不一致的问题（客厅空调、卧室电视、书房显示器）。
- 修正多房间映射：每种房间位只放一个米家房间，其余进「未放进小屋」。
- 不显示隐藏设备；支持小屋专属的 visible。
- 徽章精灵：先做约 10 个类别 × on/off；每个现有模块加 2–3 个徽章位。
- HouseWindow 编辑模式：只有「设备」标签（位置菜单 / 拖动 / 眼睛开关 / 恢复自动），加上简化版的「房间」对照表（改模块类型 / 排除房间 / 和同类房间调换）。
- 小幅补素材（可选）：客厅加一台空调、书房加一盏吸顶灯；需要重新烘焙。

PR 拆分：
1. `HouseResolver` + `HouseConfig` + `Device.roomId` + 单元测试。行为等价：没有配置时 = 现在的自动逻辑加上 bug 修复。
2. 渲染改成按 fixture id；`house-cutaway.json` 加 `accepts` / `hints` / `badges`；修正位置和画面的错配。
3. 徽章精灵素材 + 渲染 + 点徽章开关设备。
4. HouseWindow 编辑模式（设备标签 + 房间对照表），草稿 / 完成 / 撤销。
5. CLI / MCP：`mijiabar house show|set|reset`（可选，方便 agent 操作；配置本来就在 prefs.json 里）。

测试和截图：
- `swift test`：覆盖房间名匹配、关键词匹配灯具位、覆盖冲突、稳定性（打乱列表顺序结果不变）、迁移（旧 prefs 没有 house 字段）。
- `--house-snapshot` 新增 mock 家庭：两个卧室、带厨房、有隐藏设备、有风扇和插座。
- 新增 `--house-edit-snapshot`，截编辑模式的界面。
- README / 官网截图用 `scripts/site-shots.sh` 重新生成。

### Phase 2：房间布局（模块化素材）

范围：先做 §4.4 的 spike；然后重画所有模块（living 2×1、bedroom、study、kitchen、bathroom、balcony、generic），加上接缝件；在 MijiaCore 里实现布局求解和合成偏移；App 端合成缓存；编辑器的「房间布局」标签（格子、拖动、添加 / 移除模块）。「经典四室」保留为一个预设。

PR 拆分：
1. Spike：两个模块 + 接缝件 + 合成器 + 截图。验收通过后才继续。
2. 素材管线按模块参数化（生成 + 烘焙 + 预览脚本），交付 7 个模块的默认风格。
3. 布局求解（自动布局、约束校验）+ 合成缓存 + 现有渲染改成接收合成图。
4. 编辑器「房间布局」标签。
5. 性能：菜单栏用的预缩放缓存、mask 合并；Instruments 内存截图记进 PR。

测试：
- 布局求解单元测试（约束、新房间补位、删房间）
- `--house-snapshot --layout <preset>` 批量截 1–6 室的各种布局
- 像素级回归：经典四室预设的合成结果和旧整图逐像素一致（或差异低于阈值）

### Phase 3：风格与装饰

范围：风格包格式、下载 / 校验 / 缓存，风格选择器；装饰位、装饰精灵、装饰面板；`absentVariant`（没有设备时换成别的家具）；节日装饰包。先出 1–2 个新风格。

其中 `absentVariant` 已实现嵌套 patch / rect、模块坐标平移和 day/night × unlit/lit 贴片；沿用窗帘叠图路径，不引入新渲染器。独立风格的坐标适配、其他空灯具位尚未覆盖。验收入口为 `--house-absent-variant-snapshot <dir>`，实际 GUI 前后对照需在允许启动应用的环境中运行。

PR 拆分：
1. 风格包格式、加载、回退（本地目录）
2. R2 托管 + 下载 + 校验 + 设置界面
3. 装饰系统 + 第一批装饰
   - **自由落地装饰 v1 已实现（源代码与单元测试）**：使用宠物 walk 网格，S/M 一格、L 2×2，每房间最多 4 件。
     保护固定宠物睡眠/栖息入口、固定落地装饰位，BFS 校验房间剩余通道连通。
     拖放优先兼容固定槽，其余地面吸附网格；红绿占地预览、拖动移动/移除、房间与列行数值编辑、撤销/重做。
     schema 1 新增独立时间戳 `freeDecor`；CLI/MCP、合成场景、菜单栏和宠物障碍共用解析结果。
     实现细节和命令见 `HOUSE.md` 的 “Free floor decor”。此前等待宠物行走数据的依赖现已满足。
   - **v1 边界/验收偏差**：不做像素级自由坐标，不校验跨房间门口；经典手绘整图不显示自由装饰。
     冲突/风格变化后无效项隐藏但不自动改位置。数值编辑使用 Apply 确认（无效时禁用），而非每次步进立即写入。
     `--house-free-decor-snapshot` 的编辑器图为独立数值面板，宠物图为节点/边与绕行路径调试图；不捕获实时弹出框。
     GUI 快照由执行器在沙箱外运行，尚需视觉和真实拖放验收；这里的实现标记不代表视觉验收完成。
4. 新风格素材 × 1–2

测试：风格切换后位置保留和回退的单元测试；每个风格 × 每个模块的 day/night × on/off 截图拼成一张对照图（类似 `--art` 的画廊）。

---

## 9. 待 Neil 决定的问题

1. **Phase 2 重画素材：** 要支持任意组合，必须按等距格子重画所有模块，画风会和现在这张整图略有不同。你接受「新模块素材 + 保留经典四室作为一个预设」这种做法吗？还是坚持只用整屋预设（方案 A，组合有限，但画面最精致）？
2. **没有专属灯具的设备**（风扇、插座、净化器、音箱、摄像机、传感器……）：用房间里的像素小徽章显示可以吗？还是只放在 chips 里、不进画面？
3. **能不能把设备放进别的房间：** 比如米家里属于「客厅」的灯，在小屋里放进卧室。建议默认不允许，跟米家保持一致。你觉得有没有这个需求？
4. **房间数量上限：** 建议最多 6 格（3×2）。房间更多的家庭，多出来的房间只能在编辑器里手动换进来。可以接受吗？
5. ~~**配置要不要让 CLI / MCP 也能改**~~（已定：独立 house.json + iCloud Drive 同步 + CLI/MCP，见 §2.4）（agent 帮忙摆小屋），以及要不要在多台 Mac 之间同步？这两项会影响配置是继续放在 `prefs.json`，还是单独拆成 `house.json`。
