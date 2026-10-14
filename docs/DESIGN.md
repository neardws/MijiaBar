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

- **只用语义色**：背景、卡片、描边、磁贴都用 `Theme`（`bg`、`card`、`tile`、`hover`、`stroke`），它们基于 `Color.primary` 透明度和系统色，浅色/深色自动适配。不要写死 `Color.white.opacity(…)` 或 `Color.black`（拟物插画里的金属、玻璃材质除外）。
- **设备色**：`DeviceCategory.color`；空调按冷暖用 `Theme.warm(_:)`（沿温度色带取色，制冷固定偏蓝、制热固定偏橙，不会出现灰色中间色）；灯按色温用 `kelvinColor(_:)`。关闭时用 `.secondary`，关机时彩色滑条也要褪色。
- **详情页**：所有设备（包括空调）都用 `TypeShell`（头部状态 + 电源 → 插画 → 内容），宽度固定 `cardWidth`（336），插画高 136。标题说设备在做什么（「制冷中」「已开启」），副标题放读数，不要重复下方按钮里已有的信息。底部按钮用 `PropTile` / `ToggleTile` / `MenuTile` / `ActionTile`，一行最多 4 个；设备不支持的功能直接不显示，不要占一个「不支持」的磁贴。常驻的操作提示（如「← → 微调」）放进 `.help` 提示里。
- **插画**（`Art.swift`）：统一用空调卡片那种「产品渲染」风格，全部用 SwiftUI 形状画：
  - **外形像真实产品**：外壳用 `Shape.appliance(tint, k)`（亮白渐变 + 顶部高光 + 开机时带设备色的投影），不要线稿、卡通表情或多余零件。参考 Apple 的画法：一条连续的轮廓、少量材质（亮面白 `shellFill`、磨砂铝 `aluminum`、黑色玻璃 `darkGlass`）、细边高光代替高光斑。插画里不放 SF Symbols 和文字（读数已在标题和大号数值里）。
  - **状态用光表达**：开机后身后的环境光（`Ambient`）和投影带上设备色；灯泡的光从内部亮起。
  - **能量用设备色粒子表达**：空调出风口铺开的气帘和流线、风扇两侧的气流、插座电线上的电流、锅的蒸汽、取暖器的热，速度和亮度跟随真实读数（风速、功率、档位），统一用 `particles(_:_:tint:)` 画（柔光 + 白色亮芯）。不要用波浪线、火焰这类卡通符号。
  - **开关过渡统一**：用 `PowerTimeline`（开机约 0.9 秒渐入，关机约 0.6 秒渐隐）；有转动部件的要有惯性（风扇加速、滑行）。
  - **不动的东西不加动画**：灯泡、摄像机没有循环动画（摄像机的状态灯常亮，不闪烁；隐私模式是镜头转出玻璃视野，而不是贴一个图标）；状态（开关、档位、色温）要在静止画面里也能看出来。
- **登录页**：顶部用 `AppMark`（和应用图标同一份图形，不另画一个图标）；二维码放在白色卡片里（描边、投影同磁贴）；地区选择和设置页一样放进分组卡片；底部操作用 `.pressable` + `.hoverHighlight()` 的次要文字按钮。只有依次淡入和扫描线两种动效，不加循环浮动。
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

- 只有图标的按钮必须有 `.accessibilityLabel`（`IconButton` 已自动用 `help` 文案）。电源按钮用 `.powerAccessibility(on)`。
- 可点击但不是 `Button` 的视图（设备行、收藏空调卡片）要加 `.accessibilityAddTraits(.isButton)` 和 `.accessibilityAction`。
- 有状态的控件要给 `.accessibilityValue`（开/关、当前模式、温度）。`MiniSwitch` 传入设备名作为 `label`。
- 滑条支持 VoiceOver 上下调节：`GradientSlider` 传 `a11yLabel`。
- 菜单里的单选项用 `OptionPicker`（系统画勾选，VoiceOver 能读出选中项），不要手写「✓」。
- 错误提示（`showToast(_:error: true)`）带橙色警示图标、停留 5 秒（成功提示 3 秒），并且只有它会通过 `AccessibilityNotification.Announcement` 播报；「已复制」「已执行」这类成功提示只显示，不打断 VoiceOver。
- 纯装饰的图形（插画、列表图标）加 `.accessibilityHidden(true)`。插画区里有可操作内容时（直播画面），给 `TypeShell` 传 `artInteractive: true`，由插画自己隐藏装饰部分，否则画面上的按钮 VoiceOver 读不到。

## 7. 待改进（欢迎 PR）

- **圆角和字号做成 token**：现在圆角有 7/9/12/14/20/26 等多种、字号约 10 种散落各处。嵌套圆角应同心：内圆角 = 外圆角 − 内边距。
- **键盘可达**：详情页的磁贴和电源按钮需要可见的焦点样式。

## 8. 改完怎么检查

```bash
swift build
.build/debug/MijiaBarApp --snapshot /tmp/shots -AppleLanguages "(zh-Hans)"   # 每个页面的浅色/深色截图（*-light.png / *-dark.png）
.build/debug/MijiaBarApp --gif /tmp/demo.gif -AppleLanguages "(zh-Hans)"     # 录一段空调卡片动效
```

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
