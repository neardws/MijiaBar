# MijiaBar 设计规范 · Design Guide

这份文档记录界面和动效的约定，改 UI 前请先读一遍。代码里的来源是 [`Motion.swift`](../Sources/MijiaBarApp/Motion.swift)（动效）、[`Theme.swift`](../Sources/MijiaBarApp/Theme.swift)（颜色）和 [`TypeKit.swift`](../Sources/MijiaBarApp/TypeKit.swift)（详情页骨架）。

动效原则参考了 Emil Kowalski 的设计工程理念（[emilkowalski/skill](https://github.com/emilkowalski/skill)，MIT）和 Apple WWDC 2018《Designing Fluid Interfaces》，并按菜单栏应用的使用场景做了取舍。

## 1. 核心原则：克制

MijiaBar 一天会被打开几十次。用得越频繁，动画就越要少、越要快。

**先问「多久看到一次」，再决定要不要动：**

| 频率 | 例子 | 做法 |
| --- | --- | --- |
| 每天上百次 | 键盘 ↑↓ ↩ Esc ← → 空格、搜索输入 | **不做动画**，瞬间响应 |
| 每天几十次 | 悬停、打开菜单栏、列表、开关切换 | 几乎察觉不到：只变亮度/颜色，不位移、不缩放 |
| 偶尔 | 点击进入详情、设置、提示、重命名弹窗 | 标准进出动画 |
| 很少 / 首次 | 登录页 | 可以多一点（依次淡入、扫描线） |

**每个动画都必须说得出理由**，只能是这几种：反馈（按下有回应）、状态（设备在运行、模式变了）、空间关系（页面从哪来回哪去）、避免突兀（内容凭空出现/消失）。「好看」不是理由。

## 2. 动效参数

全部用 `Motion` 里的常量，不要在视图里手写曲线（`.easeInOut(duration:)`、`.snappy` 等）。

| 常量 | 参数 | 用途 |
| --- | --- | --- |
| `Motion.press` | `spring(duration: 0.16, bounce: 0)` | 按压反馈 |
| `Motion.snappy` | `spring(duration: 0.2, bounce: 0)` | 悬停、颜色、小状态 |
| `Motion.smooth` | `spring(duration: 0.3, bounce: 0)` | 设备状态（开关、模式、色调） |
| `Motion.enter` | `spring(duration: 0.28, bounce: 0)` | 进入：页面推入、弹窗、提示 |
| `Motion.exit` | `spring(duration: 0.2, bounce: 0)` | 退出：总比进入快 |
| `Motion.breathe` | `easeOut(duration: 1.4)` 循环 | 「正在进行」的状态指示（直播角标的光圈），不受 300ms 限制 |

规则：

- **不超过 300ms**，**不要回弹**。回弹只属于有惯性的手势（甩、拖拽释放），这个应用里没有。SF Symbols 也不用 `.symbolEffect(.bounce)`；图标换样子用 `.contentTransition(.symbolEffect(.replace))`。
- **退出比进入快**：出现/消失用 `.transition(.pop())`；页面用 `m.open(_:)`（`enter`）和 `m.back()`（`exit`）。
- **键盘操作不做动画**：导航用 `m.open(d, animated: false)` / `m.back(animated: false)`；改状态包在 `withoutAnimation { }` 里。
- **不要从 0 放大**：出现时从 `0.9–0.97` 缩放 + 淡入（`.pop(0.95)`）。
- **按压**：`.buttonStyle(.pressable)`，缩放 0.95–0.97。**悬停**：`.hoverHighlight()` 或换 `Theme.hover` 底色，不放大、不上浮。
- **持续动画只用来表达状态**：空调气流（模式/风速/扫风）、风扇转速、插座电流、播放中的音箱。设备关着就停（`TimelineView(.animation(paused: !on))`）。列表里的图标保持静止。
- **直接操作 1:1 跟手**：拖动滑条时滑块跟着指针走，松手后再吸附（`TempSlider`、`GradientSlider`）；拖动过程中不要给数值加动画。
- **触感反馈**只用在「吸附到档位」这类有意义的时刻，并与视觉变化同一帧。

## 3. 减弱动态效果（Reduce Motion）

系统开启「减弱动态效果」后：页面切换、出现/消失只保留淡入淡出；停掉所有持续动画（气流、风扇、电流、扫描线）；涟漪不显示。新增动画时用 `@Environment(\.accessibilityReduceMotion)` 或 `Motion.reduced` 判断。减弱 ≠ 全部去掉：帮助理解的颜色、透明度变化要保留。

## 4. 颜色与布局

### Chrome 令牌

圆角和常用字号统一由 `Theme.swift` 提供（单位 pt）；只用于界面 chrome，不替换产品插画的几何尺寸。

| Radius | 数值 | 用途 |
| --- | --- | --- |
| `xs` | 7 | 列表悬停块、设备图标底板 |
| `sm` | 9 | 设备行、搜索框（原 8，归并为 9） |
| `md` | 12 | 收藏空调小卡片 |
| `lg` | 14 | 磁贴、整行按钮、音量区域、通用读数区域、设置分组、直播画面 |
| `xl` | 20 | 现有较大的通用详情 chrome |
| `card` | 26 | `TypeShell` 详情卡片 |

| TypeSize | 数值 | 用途 |
| --- | --- | --- |
| `micro` | 10 | 磁贴说明、小号辅助文字 |
| `caption` | 11 | 次要文字、设置分组标题 |
| `body` | 12 | 设置正文、读数 |
| `callout` | 13 | 卡片标题、设备名称、整行按钮 |
| `title` | 15 | 磁贴图标、章节标题 |

同心嵌套使用 `Theme.Radius.inset(outer, by: padding)`，即 `max(0, outer − padding)`；例如 26 − 18 = 8。只有共用同一边界的嵌套形状才需要同心，独立磁贴不由卡片圆角推导。`Readout` 胶囊保留 `Capsule`；`BigValue` 的 40/60pt 是展示数值，不属于 chrome 字号。重命名弹窗 16pt、插画和比例缩放图标保留原尺寸，不为这些特例扩充令牌。

### 颜色与组件

- **只用语义色**：背景、卡片、描边、磁贴都用 `Theme`（`bg`、`card`、`tile`、`hover`、`stroke`），它们基于 `Color.primary` 透明度和系统色，浅色/深色自动适配。不要写死 `Color.white.opacity(…)` 或 `Color.black`（拟物插画里的金属、玻璃材质除外）。
- **设备色**：`DeviceCategory.color`；空调按冷暖用 `Theme.warm(_:)`（沿温度色带取色，制冷固定偏蓝、制热固定偏橙，不会出现灰色中间色）；灯按色温用 `kelvinColor(_:)`。关闭时用 `.secondary`，关机时彩色滑条也要褪色。
- **详情页**：所有设备（包括空调）都用 `TypeShell`（头部状态 + 电源 → 插画 → 内容），宽度固定 `cardWidth`（336），插画高 136。标题说设备在做什么（「制冷中」「已开启」），副标题放读数，不要重复下方按钮里已有的信息。底部按钮用 `PropTile` / `ToggleTile` / `MenuTile` / `ActionTile`，一行最多 4 个；设备不支持的功能直接不显示，不要占一个「不支持」的磁贴。常驻的操作提示（如「← → 微调」）放进 `.help` 提示里。
- **插画**（`Art.swift`）：统一用空调卡片那种「产品渲染」风格，全部用 SwiftUI 形状画：
  - **外形像真实产品**：外壳用 `Shape.appliance(tint, k)`（亮白渐变 + 顶部高光 + 开机时带设备色的投影），不要线稿、卡通表情或多余零件。参考 Apple 的画法：一条连续的轮廓、少量材质（亮面白 `shellFill`、磨砂铝 `aluminum`、黑色玻璃 `darkGlass`）、细边高光代替高光斑。插画里不放 SF Symbols 和文字（读数已在标题和大号数值里）。
  - **状态用光表达**：开机后身后的环境光（`Ambient`）和投影带上设备色；灯泡的光从内部亮起。
  - **能量用设备色粒子表达**：空调出风口铺开的气帘和流线、风扇两侧的气流、插座电线上的电流、锅的蒸汽、取暖器的热，速度和亮度跟随真实读数（风速、功率、档位），统一用 `particles(_:_:tint:)` 画（柔光 + 白色亮芯）。不要用波浪线、火焰这类卡通符号。
  - **开关过渡统一**：用 `PowerTimeline`（开机约 0.9 秒渐入，关机约 0.6 秒渐隐）；有转动部件的要有惯性（风扇加速、滑行）。
  - **不动的东西不加动画**：灯泡、摄像机没有循环动画（摄像机的状态灯常亮，不闪烁；隐私模式是镜头转出玻璃视野，而不是贴一个图标）；状态（开关、档位、色温）要在静止画面里也能看出来。
- **应用图标**：和登录页同一个 `BrandMark`，`scripts/make-icon.sh` 按 macOS 图标模板（1024 画布、824 主体居中、自带投影）生成 `Resources/AppIcon.icns`。改标志时两处一起变。
- **登录页**：顶部用 `BrandMark`（天蓝单色渐变圆角方块 + 白色房子，门里透出一点暖光；不要用蓝橙直接混合的渐变，中间会发灰发浊）；二维码放在白色卡片里（描边、投影同磁贴）；地区选择和设置页一样放进分组卡片；底部操作用 `.pressable` + `.hoverHighlight()` 的次要文字按钮。只有依次淡入和扫描线两种动效，不加循环浮动。
- **没有状态时的详情页**（读取中、离线、读取失败）：同样用 `TypeShell`（`DeviceStatusCard`），插画是该设备关着的样子（`offArt`），读到状态后原地换成正常卡片；不要在页面中央单独放一个图标和一行字。没有专门页面的设备用 `DeviceCardView`，它也是 `TypeShell` + `BigValue` + `Readout` + 磁贴，插画是 `GenericArt`（空气净化器用 `AirPurifierArt`）。插画要一眼认出是什么设备：正面的深色圆形部件会被认成摄像头，只有摄像机才用。
- **设置页**：每组用 `SettingsGroup`（小标题 + 圆角 14 的 `Theme.card`）。行都是「文字在左、控件在右」：取值用 `row`，开关用 `SwitchRow`（系统开关，不用勾选框），操作用 `ActionRow`（整行可点、按压/悬停反馈；退出登录、完全退出这类危险操作用红色）。不要在分组之间放单独的大按钮。
- **语言**：界面只有简体中文、繁體中文（台湾用语，人工校对的 `i18n/zh-Hant.tsv`）和 English 三种。所有文案走 `L("简体", "English")`，繁体用台湾说法（裝置、設定、網路、預設），不用机器直转的大陆词；按小米服务器地区推荐默认语言（中国大陆→简体，台湾/香港→繁体，其余→英文）。README、Agent 说明和网站同样只做这三种。
- **网站**（`site/template.html`，由 `scripts/gen-site.py` 生成英文和简体中文页面）：同一套原则搬到网页上。颜色是 `:root` 里的语义 token，浅色/深色各一套；动效只用无回弹的 `--ease` 曲线，按压缩放 0.97，悬停只变底色；只有首屏依次淡入和各区块第一次进入视野时淡入，没有循环浮动；`prefers-reduced-motion` 时全部去掉。图片只用 App 自己渲染的截图和插画（`--snapshot`、`--art`），跟随系统浅色/深色切换，不另外画。
- **同类不同形**：同一类别里外形差别大的设备按型号区分（`Device.form`），插画和列表图标（`Device.icon`）都跟着换：可视门铃用 `DoorbellArt`，不用摄像机插画；门窗传感器用 `ContactSensorArt`（打开时两块分开、缝隙里透出设备色的光），水浸传感器用 `LeakSensorArt`（浸水时身下一摊水、状态灯和卡片变橙色），都不用温度计。标题同样说设备的状态（「已打开」「检测到浸水」）。**遇到还没有设计过的型号**（落到别的类型的插画或通用卡片上），照这一节的标准补上插画、标题和列表图标，再放进 `ArtGallery` 对照，不要借用外形不同的插画。
- **插画总览**：`--snapshot` 会输出 `art-gallery-*.png`，所有插画开/关并排，改了一个插画后看看它和其他插画是否还是一家人。
- **大号数值**：统一用 `BigValue`（60pt 细体 + 说明文字），在 `TypeShell` 里自动带上色调渐变和光晕（`cardAccent`）；传入 `number` 时数字按增减方向滚动。
- **图标**：磁贴和按钮用线框（outline）SF Symbols；只有播放、停止、上一首、下一首这类媒体控制用实心。
- **直播画面**（`LiveVideo.swift`）：在插画区原地替换（同为 136 高、圆角 14），不另开一块区域。
  - 画面是黑底视频，不随浅色/深色变化；浮在画面上的角标和按钮统一用 `LiveChrome.scrim` 底色、`LiveChrome.size` 高度，左右对齐在同一条线上。
  - 一个操作只放一个入口：开始/停止都用下方的主按钮，画面上只放「弹出窗口」。
  - 主按钮和磁贴同圆角（14）、同描边、同按压/悬停反馈；不能看时（离家、离线）显示同尺寸的禁用态，原因放进 `.help`，不要换成一段长文字让布局跳动。
  - 「直播」角标的红点常亮，只让身后的光圈呼吸；减弱动态效果时完全静止。状态文字（启动中、已暂停、出错）之间淡入淡出。
  - 门铃耗电这类提醒用次要色正文 + 彩色图标，不要整段彩色。

## 5. 实现约束

- **只动 transform 和 opacity**（`offset` / `scaleEffect` / `opacity`），不要动画 `frame` 宽高、padding。需要「变粗」用 `scaleEffect(y:)`。
- **光晕放在 `.background { }` 或 `overlay` 里**，不要放进 `ZStack` 当兄弟视图：ZStack 会用最大的固定尺寸子视图给其他弹性子视图定尺寸，把按钮、圆形撑大。
- **不要用 `.blur` 和 `rotation3DEffect`**：`--snapshot` / `--gif` 走的 `cacheDisplay` 画不出来（模糊变成硬边圆盘，3D 旋转的位置会错），截图会和真机不一致；在 `TimelineView` 里每帧模糊也很耗性能。光晕用 `RadialGradient` / `EllipticalGradient`（或 `Art.swift` 里的 `Glow`），3D 摆动用 `scaleEffect(x:)` 模拟。Canvas 内部的 `addFilter(.blur)` 没问题。
- 依赖 macOS 15 的 API（如 `symbolEffect(.rotate)`）放在 `if #available(macOS 15, *)` 里，并提供 macOS 14 的退路。

## 6. 无障碍

- 详情页的电源、开关/操作磁贴、菜单磁贴及直播/重试整行按钮保留原生 Button/Menu 语义，并在控件本身加入键盘焦点（不在 label 内再造一个 Tab 停靠点）。label 的 `keyboardFocusChrome` 读取 `isFocused`，在轮廓外偏移 3pt 画 2pt 系统强调色环；关闭系统重复焦点效果。焦点环不动画、不响应点击、不加入 VoiceOver，悬停或 Reduce Motion 不影响可见性，禁用态不画环。按钮的 Space/Return 优先执行本控件操作并禁用事务动画，避免冒泡成页面电源快捷键；页面自身聚焦时原有 Space 电源行为不变。菜单保留原生键盘打开/选择行为。
- 只有图标的按钮必须有 `.accessibilityLabel`（`IconButton` 已自动用 `help` 文案）。电源按钮用 `.powerAccessibility(on)`。
- 可点击但不是 `Button` 的视图（设备行、收藏空调卡片）要加 `.accessibilityAddTraits(.isButton)` 和 `.accessibilityAction`。
- 有状态的控件要给 `.accessibilityValue`（开/关、当前模式、温度）。`MiniSwitch` 传入设备名作为 `label`。
- 滑条支持 VoiceOver 上下调节：`GradientSlider` 传 `a11yLabel`。
- 菜单里的单选项用 `OptionPicker`（系统画勾选，VoiceOver 能读出选中项），不要手写「✓」。
- 错误提示（`showToast(_:error: true)`）带橙色警示图标、停留 5 秒（成功提示 3 秒），并且只有它会通过 `AccessibilityNotification.Announcement` 播报；「已复制」「已执行」这类成功提示只显示，不打断 VoiceOver。
- 纯装饰的图形（插画、列表图标）加 `.accessibilityHidden(true)`。插画区里有可操作内容时（直播画面），给 `TypeShell` 传 `artInteractive: true`，由插画自己隐藏装饰部分，否则画面上的按钮 VoiceOver 读不到。

## 7. UI polish 进度与边界

- **已实现：圆角和字号 token**。§4 的令牌覆盖详情外壳、磁贴、整行按钮、设置分组、直播画面、列表与收藏空调卡片；常用 chrome 字号迁移到 `TypeSize`，同心计算与常量有单元测试。
- **已实现：详情控件焦点样式**。电源、ToggleTile、ActionTile、MenuTile、直播/重试按钮共享静态焦点环。快照入口与测试已加入；真实 Tab 顺序、菜单激活及浅/深色视觉验收仍需执行器检查，编译与强制焦点图不等于真实键盘验收。
- **明确延期**：`Art.swift` 圆角属于产品几何；House 编辑器、宠物与像素排列界面不做字号/圆角扫荡；Motion/Theme 色彩重设计、网站 CSS 令牌、详情磁贴与电源范围之外的全应用焦点审计另开任务，避免混入不同设计范围。

## 8. 改完怎么检查

```bash
swift build
.build/debug/MijiaBarApp --ui-polish-snapshot /tmp/ui-polish -AppleLanguages "(zh-Hans)" # 演示灯详情 + 焦点环；只由执行器运行
.build/debug/MijiaBarApp --snapshot /tmp/shots -AppleLanguages "(zh-Hans)"   # 每个页面的浅色/深色截图（*-light.png / *-dark.png）
.build/debug/MijiaBarApp --gif /tmp/demo.gif -AppleLanguages "(zh-Hans)"     # 录一段空调卡片动效
```

`--ui-polish-snapshot` 只使用 `AppModel(mock: true)`，即使附带 `--real` 也不读取真实家庭。输出 `ui-polish-detail-light.png` / `ui-polish-detail-dark.png`、`ui-polish-focus-power.png` / `ui-polish-focus-tile.png` 及两张对应的 `-dark.png`。内部 `forceFocusChrome` 环境值默认 false，只在这组焦点快照设置 true；不改变真实焦点或正常 UI。焦点样张同时展示多个焦点仅用于对照，包含禁用对照。快照不能证明 Tab 可达：执行器另验 Tab/Shift-Tab、Space/Return、菜单打开/关闭、禁用控件跳过以及页面 Space 快捷键；有焦点的非电源控件不能误触电源。在系统开启/关闭 Reduce Motion 后分别检查焦点环，它本身始终没有动画。

逐帧看 GIF（例如 `ffmpeg -i demo.gif -vf fps=4,tile=6x3 sheet.png`）：颜色过渡是否干净、有没有突然停住、多个属性是否同步。浅色和深色都要看。隔天再看一遍，常能发现当时没注意到的问题。

**提交前自查：**

- [ ] 这个动画说得出理由吗？频率表允许吗？
- [ ] 键盘触发的路径没有动画？
- [ ] 用的是 `Motion` 常量、无回弹、≤ 300ms、退出更快？
- [ ] 没有从 0 放大、没有悬停放大？
- [ ] Reduce Motion 下只剩淡入淡出，持续动画停了？
- [ ] 只用了 `Theme` 语义色，浅色/深色都清楚？
- [ ] 新控件有无障碍标签和值？
- [ ] 没用 `.blur` / `rotation3DEffect`，`--snapshot` 截图和真机一致？
