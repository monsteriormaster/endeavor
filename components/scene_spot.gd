"""
场景点 - 地图中用于跳转地图的区块
使用方法：
在检查器中设定spot_name,按需求设定max_size,min_size,ordinary

本版（v0.2 范围，D-S1/D-S3/D-S4/D-S6）一次性落地：
- D-S1：spots.json 缺 icon/path 或加载失败 → 降级隐藏 + push_warning，不崩溃。
- D-S3：press 先写 Player.path（回档锚点），对齐 selection/main_ui 既有约定。
- D-S4：切场景后发 EventSignal.scene_entered（自由探索也广播进入事件）。
- D-S6：visible_if / visible_if_method / locked / locked_description 门控，
        由 Player.player_tags 派生，随剧情解锁/锁定。
"""

extends Button

const SPOTS = "res://resoures/spots.json" 

var info := {}
var icon_texture: Texture2D

@export var spot_name: String
@export var max_size: Vector2 = Vector2(100, 100)  # 最大宽高
@export var min_size: Vector2 = Vector2(50, 50)    # 最小宽高
@export var ordinary := Vector2(120, 120)
## 是否投 M-SUN1 动态影子（见下方常量的整段说明）。
##
## 主城十个点从 2026-10-20 起**一律关掉**：那天图标改成「印象图上原封不动的一块」
## （`design/build_city_patch.py`），画面里已经带了原稿作者画的影子、地面淡涂和水色。
## 再让引擎按 alpha 剪影投一层，就是**同一栋楼两个影子**，而且第二个是整块地皮的形状。
## 关掉之后太阳那一套（`SunClock` / `_update_shadow`）仍然完整可用 ——
## 将来若做「无地面」的图标（例如盖房子、换季），把 `cast_shadow` 打开即可。
@export var cast_shadow := true

@onready var sprite = $Sprite2D
@onready var container = $PanelContainer
@onready var label = $PanelContainer/Label

## 门控结果缓存，供调试/测试读取（D-S6）
var is_locked: bool = false
var is_hidden_by_gate: bool = false

## 「锁着但点得动」的提示剧情（spots.json 的 `locked_plot`，2026-10-23）：
## 非空时点击**不换场景**，只播这一段剧情 —— 用于「教程期间返回主城」这类
## 「必须拦住，但要让玩家知道为什么」的点。
## 空字典 = 常规锁（disabled，点了没反应，只靠悬浮提示板说明）。
var _locked_plot: Dictionary = {}

## 未实装（敬请期待）标记：可见、悬浮显示说明、点击无效（D-COMING）
var is_future: bool = false

## 测试用 seam：为 true 时 _go_to_scene 只写 path + 发 scene_entered，
## 不真正切场景（便于 headless/编辑器内安全验证 D-S3/D-S4，默认 false 零影响）。
var _test_no_swap: bool = false


# ============================================================
#  M-ANI1 悬浮动画 / 待机呼吸（v3「铅笔圈注」）
# ============================================================
## ▍v1 为什么被否（「不好看，动画要符合我的游戏的风格，自然不突兀」）
##   ① 径向暖白光晕是纯数字产物：本作是彩铅画在纸上，纸上不会发光。
##   ② 平滑连续插值（sin 呼吸 + BACK 过冲）是 CG 的特征。手绘动画的灵魂恰好相反 ——
##      它是「按拍」的：每 2 帧换一张重画的线稿，线条因此一直在极轻微地抖（line boil）。
##      少了这一层，动效立刻读作「电脑在动」。
##   ③ 过冲缩放读作「UI 弹跳」，不是「纸上有个东西被圈了出来」。
##
## ▍v2：把「这里能点」翻译成纸上的一个动作 —— **拿铅笔把它圈一圈**
##   悬浮：从图标左下方起笔，绕建筑轮廓画一圈**不完全闭合**的圈，收笔微甩；
##         圈画到八成，标注（文字面板）才浮出来。先在纸上圈，再在旁边写字。
##   离开：圈不从末端缩回去（那是倒放），而是像橡皮**顺着笔迹从头擦过**，
##         前端一点点消失。
##   待机：8fps 阶梯的「按拍」呼吸 + 4 帧微偏移循环（line boil 的近似）。
##
##   圈的几何按**图标实测内容框**生成（见 `_icon_content_rect`）：实测
##   `art/city_icons/*.png` 十张都是 512 方画布，但内容一律贴底、横向留白 14%~39%
##   各不相同 —— 按 512 画布画圈会飘在半空，必须按真实内容框量。
##
## ▍v3：悬浮**不再动图标本体**。
##   用户原话：「变大太突兀了，这样用铅笔画一圈然后文字出现在上方」。
##   放大 + 上浮 + 提亮三件事叠在一起，读作「这块 UI 被选中了」—— 那是屏幕在动，
##   不是纸上发生了什么事。三条一起归零后，悬浮反馈只剩两个**同一材质**的动作：
##   铅笔圈一圈 + 旁边写字。
##   图标本体全程只受「待机呼吸 + line boil」影响 —— 那一层负责的是
##   「这东西是活的」，与「鼠标在不在这里」无关，所以不受本次改动影响。
##
## ▍v4（本轮修订）：提示文字**去底去框**，改成写在纸上的墨。
##   用户原话：「不要显示边框，文字自然一点」。详见 `_apply_panel_style()` /
##   `_apply_label_style()` 与 TEXT_COLOR 一段的注释。
## ▍v4.2（2026-09-30，用户「强调」）：**图标本体全程完全静止 —— 一个缩放都不许有。**
##   用户原话：「不要变大变小，只需要一个铅笔画一圈的特效就可以了」。
##
##   ⚠️ 用户这句「强调」戳中的不是一个审美问题，是一个**真实 bug**（藏了 v2 / v3 / v4 三轮）：
##   `_apply_visual()` 里原来写的是 `b = BOIL_FRAMES[i] * BOIL_IDLE(0.40)`，然后
##   `sprite.scale = _base_scale * (… * (1.0 + (b.z - 1.0)))` —— 那个 `0.40` 把表里的
##   **「1.000 = 不缩放」这个基准值本身**也一起乘掉了：待机时 `b.z = 0.402`，
##   于是**六个可交互图标平时被画成四成大小**，鼠标一上去 `_hyper > 0.5` 换用
##   `BOIL_HOVER(1.0)` → `b.z ≈ 1.005`，图标**当场弹到 2.5 倍**。
##   实测（`debug/_spot_probe.gd --body`，改前）：
##     · 待机：可交互的 6 个 `缩放比 = 0.387~0.413`（极差 0.024）；不可交互的 4 个 `= 1.0000`
##       → **同一张地图上同时存在两种图标尺寸，相差 2.5 倍**
##     · 悬浮：被悬浮的那个跳到 `0.972~1.023`，其余仍是 0.39
##     · 按下：被按的那个 `0.922~0.977`（又缩了一次）
##   **为什么三轮都没被发现**：v2~v4 的验收**只量了悬浮态**（记的是 `本体缩放比=0.9984`，
##   那正好是 hover 分支的值）—— 待机态从来没被量过。**只量一个状态的验收等于没验收。**
##
##   修法两层：
##   ① **修 bug**：抖动表一律只缩「增量」不缩基准 —— `1.0 + (f.z - 1.0) * k`，
##      中性值是 `Vector3(0, 0, 1)`。这样即使把 BOIL_ON 打开，缩放也不会再跑飞。
##   ② **按用户要求全关**：呼吸、抖动、按下回缩、按下下压**一律归零**。
##      于是全屏唯一会动的东西 = 那支**铅笔圈**（画出来 / 擦掉）+ 说明文字的淡入淡出。
##
##   ⚠️ 下面几个常量**不是死代码，是闸门**：想恢复任何一项只改它的数值，
##      `_apply_visual()` 的分支一行都不用动。都关着时 8fps 时钟也不启动（见 `_start_tick()`）。
##
## ── v4.4（2026-09-30，用户「有点单调，稍微变大会不会好一点」）：只放开**缩放**这一个通道 ──
## 用户看过 v4.3 的笔圈后说效果很好但偏单调，问「稍微变大会不会好一点」。
## 结论是**合理**，且与 v3/v4.2 那次「不要变大变小」并不冲突 —— 当初被否的是两件事：
##   ① 一个真 bug：图标平时被画成 0.39 倍、一悬浮跳到 1.005（**2.5 倍**）；
##   ② **三个通道同时上**（放大 5.5% + 上浮 3.5px + 提亮 8%），叠加读作「这块 UI 被选中了」。
## 现在基准是干净的 1.0000，+4% 与那个 2.5 倍不是一回事；行业里 hover 放大 3~5% 是标准做法，
## 而「单调」的根因确实存在：悬浮时图标本体对鼠标**没有任何回应**。
##
## 为什么是 **4%** 而不是 6%：圈是 `Sprite2D` 子节点、跟着一起放大，圈顶会再上抬一次
## （Δ ≈ 4~7px），而 v4.2 好不容易把「圈↔文字净空」做到 7~8px —— 6% 基本会把它吃光，
## 还会让「医院」被 `_layout_panel()` 的退路逻辑顶掉（它上方只剩 112px）。
## 4% 是「感觉得到但说不出」的量级，正好治单调而不制造突兀。
##
## ⚠️ **只放开这一个**：`HOVER_LIFT` / `HOVER_BRIGHT` 保持 0（这就是①的教训），
##    按下也不叠第二个动作（`PRESS_SQUASH` / `PRESS_NUDGE` 保持 0）。
const HOVER_SCALE := 1.04
const HOVER_LIFT := 0.0
## 按下回缩比例。**v4.2 起 = 0（不缩）** —— 它也是「变小」，用户要的是「一个缩放都不要」。
## 原本的用意是「一压一弹，给点击一个吃上力的手感」；想恢复只改这一个数。
const PRESS_SQUASH := 0.0
## 按下时整块往下挪多少像素。**v4.2 起 = 0。**
## 刻意与 `PRESS_SQUASH` 分成两个常量：**位移不是「变大变小」**，将来只想留一个
## 「按下去一点点」的手感、但不要缩小，改这一个就行，不必动缩放那条。
const PRESS_NUDGE := 0.0
## 悬浮提亮幅度（0 = 不提亮）
const HOVER_BRIGHT := 0.0
## 手绘节奏：8fps。手绘动画的线一般画在「二拍」上（16fps 播放时每张停 2 帧，
## 即每秒换 8 张），所以呼吸与抖动一律按 125ms 一步跳，**绝不连续插值**。
## ⚠️ v4.2 起呼吸与抖动都关了，这个时钟默认**不启动**（见 `_start_tick()`）；
##    常量与 `_tick()` 都留着 —— 恢复任何一项动画时它自动跟着回来。
const TICK := 0.125
## 一轮呼吸的步数：19 步 × 125ms ≈ 2.4s
const BREATH_STEPS := 19
## 呼吸幅度（缩放的 ±比例）。**v4.2 起 = 0（不呼吸）** —— 十个图标同屏一起 ±2.8%，
## 读起来仍然是「整张地图在呼吸」，也就是用户说的「变大变小」。见上方「v4.2」段。
const BREATH_AMP := 0.0
## line boil 近似：4 帧「重画」的微偏移表（x 像素, y 像素, 缩放系数）。
## 真手绘动画靠每拍重画线稿让线条落点略偏；我们只有单张 PNG，于是用 4 个固定
## 微偏移循环 —— 同样满足「每拍必有变化、但幅度极小」。
## ⚠️ 第三项（缩放系数）**是「增量系数」不是「绝对值」** —— 用法见 `_apply_visual()`：
##    写 `f.z * k` 会把「1.000 = 不缩放」这个基准一起乘掉（0.402，v2~v4 的真实 bug）。
##    表里保留 1.005 / 0.996 这些原值只为留住设计记录。
const BOIL_FRAMES: Array[Vector3] = [
	Vector3(0.0, 0.0, 1.000),
	Vector3(0.7, -0.5, 1.005),
	Vector3(-0.6, 0.4, 0.996),
	Vector3(0.4, 0.7, 1.003),
]
## 抖动强度系数：待机只用 40%（十个图标同时抖会读成整屏渲染故障），悬浮时给足。
const BOIL_IDLE := 0.40
const BOIL_HOVER := 1.0
## 抖动总闸。**v4.2 起 = false（完全不动）**，连那 ≤0.7px 的落点偏移也一起去掉。
## 「只需要一个铅笔画一圈的特效」是按**观感**说的：≤0.7px 单看读不出在动，但十个图标
## 各抖各的、8fps 一起跳，整张地图会有一层细微的「沙沙」感 —— 半开着不如全关，
## 省得多一层要解释的例外。要让图标「活着」，改这一个布尔即可。
const BOIL_ON := false

## 不可交互（未实装 / 锁定）图标的悬浮反馈：**只出文字说明，既不画圈也不放大**。
## 笔圈等于「点得动」的承诺，给不可点的图标画圈等于骗玩家（同 v1「不出光晕」的规矩）。
## v3 跟着 HOVER_SCALE 一起归零：留着 1.03 会让「能点的」（1.0）反而比「不能点的」
## （1.03）更小，读起来完全颠倒。
const NB_SCALE := 1.0

## ── 悬浮笔圈（Line2D）──
## 石墨褐，不用纯黑：纯黑在彩铅画面上立刻出「数码味」。
const RING_COLOR := Color(0.361, 0.271, 0.204, 1.0)
const RING_WIDTH := 3.0
## 圈画在实测内容框外多少屏幕像素
const RING_PAD := 6.0
## 把内容框往正圆拉多少（0 = 完全贴合内容框，1 = 正圆）。
## 剧院这类高瘦框 / 医院这类扁宽框，纯贴合会画出一只很怪的窄椭圆，不像「随手圈的」。
const RING_ROUND := 0.35
const RING_SEGMENTS := 80
## 一圈画完 / 擦完的时间
const RING_DRAW_TIME := 0.30
const RING_ERASE_TIME := 0.20

## ▍v4（本轮修订）：提示文字**不要底、不要框**，改成「写在纸上的墨」。
##   用户原话：「不要显示边框，文字自然一点」。
##   ① 那块半透明近黑方块（`Color(0.1,0.1,0.1,0.6)`）整个拿掉 —— 它是整块提示里唯一
##      「像 UI」的东西。纸上不会凭空出现一个深色矩形；玩家看到的是一个方块的硬边，
##      那就是他说的「边框」（`StyleBoxFlat` 本来 border_width=0，框感全来自方块的边）。
##   ② 文字改用墨褐、字号 16→18、行距 4。主题里 `Label/colors/font_color` 是**纯黑**，
##      纯黑压在彩铅画上出数码味（同 RING_COLOR 的规矩）。
##   可读性改由「墨色本身够深」保证：主城彩铅底实测均亮度 207，墨色对比度见
##   `TEXT_COLOR` 的注释。若将来某个 spot 的底太花，再单独给那一处加字形描边（不是方块）。

## ▍v4.1（本轮修订）：提示面板**不再被别的二级图标遮挡**。
##   ① **画层序**：面板是 Button 的子节点，同一个 CanvasLayer 内默认按**树序**画 ——
##      排在后面的图标会直接盖住前面图标的提示（实测确实发生）。给面板一个高的
##      `z_index`，它从此永远在所有图标之上。
##      注：`z_index` 只在同一个 CanvasLayer 内部排序；`OverlayRoot` 的弹窗是独立的
##      CanvasLayer（layer 50 / 100），照旧盖住提示 —— 这正是想要的。
##   ② **位置避让**：默认位置是「图标正上方」，但上面如果压着别的图标就必然重叠。
##      改为在 上/下/右/左 四个槽位里挑第一个「不与任何图标可见内容相交」的；
##      四个都被占（地图很挤时）就取重叠面积最小的那个 —— 再配合 ①，最坏也是「压着别人」，
##      绝不会是「自己被压住」。
##   ③ **主 UI 禁入区**（做完 ② 之后才发现的第二个坑）：避开了图标，却不代表落在空处。
##      实测「交通运输站」正上方被商业区+医院占着 → 退到下方，而下方 63px 正好压在
##      **手牌卡槽**（`main_ui.tscn` 的 CardArea，y 822 起）上；「剧院」上方槽位则有
##      75px 伸进**「进行中行动」板**。这两块都是深色实底，墨字压上去直接读不出来。
##      → 避让的代价里一并计入「主 UI 常驻控件的占据面积」，矩形由 `main_ui` 自己报
##      （见 `_ui_forbidden_rects()`），本文件不写死任何屏幕坐标。
##
## ── 悬浮说明面板 ──
## 宽度（2026-10-25）：**按文本自然宽度收紧**，PANEL_WIDTH 只是上限。
##
## 原先写死 330：减去左右内边距只剩 306 内容宽，20px 的中文一行只放 15 个字，
## 实测「你继承的家族产业，亦是每日归来的地方。」被断成「……每日归来的地 / 方。」——
## 一个孤零零的「方。」挂在第二行，读起来像排版事故。
##
## 但直接改成写死 460 会**反噬布局**：实测（`debug/_panel_layout_probe`）10 个点里
## 5 个因此压到邻居图标或主 UI 禁入区 —— 描述短的点（「贵族的社交场所，身份的象征。」）
## 根本用不到那么宽，宽出来的部分是白白多占的地盘，把槽位避让逼进死角。
##
## 现在：宽度 = min(文本自然宽 + 内边距, PANEL_WIDTH)，下限 PANEL_MIN_WIDTH。
## 面板没有可见的底，宽度只决定**换行点**与水平居中的宽度，屏幕上看不出来 ——
## 所以每个点各宽各的，不会显得不齐。
const PANEL_WIDTH := 380.0
## 下限。太窄会把「尽早离去吧」这种短句也挤成一个细条，与图标并排时读起来像竖排。
const PANEL_MIN_WIDTH := 180.0
## 面板内边距（屏幕像素）。**必须显式给**，两个理由：
##   ① Godot 默认主题的 `Panel` 内边距是 **0**（v3 那次踩过：面板高度一收紧到内容高度，
##      文字就直接贴死在边框上，实测左右上下各 1px）；
##   ② v4 换成 `StyleBoxEmpty` 之后更危险 —— 它的 `content_margin_*` 默认是 **-1**
##      （表示「用主题默认值」，也就是 0），只 `StyleBoxEmpty.new()` 不赋值就会立刻退回贴边。
## 面板没有可见的底了，但留白仍然决定「文字离图标多远」「夹屏时有多从容」。
const PANEL_PAD := 12.0
const PANEL_PAD_V := 8.0
## 面板底边与图标**可见内容**顶边的间距（屏幕像素）。
## 给 8 而不是 .tscn 里那套 48：48px 在 1920x1080 上读作「屏幕另一头还有块 UI」，
## 8px 才读作「就写在它头上」—— 也就是用户要的「文字出现在上方」。
## ⚠️ v4.2 起它只是**下限**：真正的上槽位间距还要让开笔圈（见 `RING_TEXT_CLEAR`）。
const PANEL_GAP := 8.0
## 提示面板底边与**笔圈可见上沿**之间的净空（屏幕像素）。这是 v4.2 新增的约束。
##
## 面板本来只按「图标内容框顶边 + `PANEL_GAP`」摆（v3 的规矩）。但 v4.2 把图标本体改回满尺寸之后，
## 笔圈也回到了设计尺寸 —— 而笔圈**比内容框还高**：`RING_PAD` 外扩 6px、再向正圆拉 0.35、
## 再乘最高 1.085 的谐波，实测上弧比内容框顶边高 **15~27px**。
## 于是「只按内容框摆」的结果就是**圈顶拱到最后一行的字上**。
##
## 实测（v4.2 修掉大小 bug 之后、加这条约束之前）：「商业区」圈顶中心线 y=449、字形下沿 y=446
## —— 净空只剩 **1.5px**，放大看圈和字是缠在一起的（行剖面：y 446/447/448 全空，圈从 449 起）。
##
## 所以上槽位的基准改成「**让开笔圈**」：`面板底边 ≥ 圈可见上沿 + RING_TEXT_CLEAR`。
## 含义上更顺：字是写在**圈**上面的，不是写在图标上面的。
## ⚠️ 这一条**不按「可交互 / 不可交互」分叉**：不可交互的图标虽然不画圈，但它将来可能被解锁、
##    届时面板位置不该跳。一律按圈算，规则只有一条。
## ⚠️ 但它只是**软**约束：`_layout_panel()` 里会比一次代价 —— 让圈若反而把面板顶进
##    「主 UI 禁入区 / 别的图标」，就退回 v3 的 `PANEL_GAP`。硬约束（别压别人）优先。
##    实测「医院」正是这种情形（上方只剩 112px，让圈就伸进行动板）。
const RING_TEXT_CLEAR := 6.0
## 浮出时从下方滑入的距离
const PANEL_RISE := 6.0
## 提示面板的画层序（v4.1）。60 只是「比同层所有图标高」，不需要精确；
## 它不会盖住 `OverlayRoot` 的弹窗 —— 那些在独立的 CanvasLayer（50 / 100）上，
## CanvasLayer 的排序永远压过同一层内的 z_index。
const PANEL_Z := 60

## 图标「实测着色范围」的占据格边长（格数）。见 `_build_footprint()`。
## ⚠️ 判「面板有没有压到别人」**不能直接拿内容框 bbox 相交**：bbox 是个矩形，
## 而图标 bbox 的角上常常是空的（尖顶、屋檐下面）。实测差得非常离谱 ——
##   · 交通运输站 / 教会：bbox 说压住 4528 / 2191 px²，**真实着色重合 13529 / 18020 px**（确实要挪）
##   · 孤儿院 / 商业区：bbox 说压住 189 / 209 px²，**真实着色重合 0**（根本不用挪）
## 用 bbox 一视同仁会把后两者无谓地从「正上方」赶走，破坏 v3 定下的「文字写在图标正上方」。
const FOOT_GRID := 16
## 每格内的采样点数（2 → 每格 2×2 个采样点），避免单点采样漏掉细楼角
const FOOT_SAMPLES := 2

## ── 说明文字（v4：墨色，无底无框）──
## 墨褐。比铅笔圈（石墨褐 0.361,0.271,0.204）更实一档 —— 字是「写清楚的信息」，
## 圈是「随手划的标记」，两者不该一个浓度。**绝不用纯黑**：主题默认 font_color 是纯黑，
## 压在彩铅底上是典型数码味。
## 对比度（对主城彩铅底实测均亮度 207）：约 8.8:1，高于 WCAG AA 的 4.5:1 ——
## 所以**不需要**再垫方块或描边；垫了反而把「浮在画上」变成「贴在补丁上」。
const TEXT_COLOR := Color(0.220, 0.161, 0.118, 1.0)
## 字号（Godot 默认主题是 16）。地图上这句说明是**唯一的**建筑介绍，比 UI 正文看得更远。
## ⚠️ 2026-10-25 **没有**加大字号（试过 20，又退回 18）：
##    18→20 让每句话宽了 11%，把悬浮面板逼成 460px 宽，实测 10 个点里
##    「交通运输站」的遮挡从 0 涨到 5603 px²（探针 debug/_panel_layout_probe）。
##    清晰度靠**加粗**（见 MAP_FONT_PATH）拿到，不靠放大 —— 放大是拿布局换清楚，不划算。
const TEXT_SIZE := 18
## 行距。中文多行挤在一起会糊成一团，默认 3 不够；18px 字用 5 才透气。
const TEXT_LINE_SPACING := 5
## 地图墨字字体：全局字族就地加粗 0.8px，见 `theme/font_map_ink.tres`。
## 与 TriggerSpot 的名字标签同一份资源 —— 地图上所有字一个厚度。
const MAP_FONT_PATH := "res://theme/font_map_ink.tres"

# ============================================================
#  M-SUN1 建筑投影（2026-10-17）
# ============================================================
## ▍为什么不是「画个椭圆糊上去」
##   常见的偷懒做法是在图标底下垫一个椭圆径向渐变。本作是**彩铅画在纸上**
##   （见文件头 M-ANI1：「纸上不会发光」），椭圆阴影是 CG 的产物：它没有理由、
##   没有方向，也不会随时间变。
##   这里改成**建筑自己的剪影倒在纸上**：轮廓从图标 alpha 里抽出来，
##   倾倒的方向和长度由 `SunClock` 给定 —— 它是「这一刻的太阳照出来的」，
##   而不是一个贴上去的装饰。
##
## ▍几何：以**内容框底边中点**为锚，整个图形向反太阳方向倾倒 + 压扁
##   Transform2D(x_axis, y_axis, origin)：
##     x_axis = (sx, 0)                      横向原样
##     y_axis = (skew * sx, squash * sy)     y 方向压缩 + 横向斜切（倾倒）
##   顶点相对锚点是 y = -H，所以横向会平移 -skew*sx*H ——
##   也就是说 **skew = 顶点横向位移 ÷ 建筑高度**，与图标实际尺寸无关，换图不必重调。
##
## ▍为什么影子节点要排在 Sprite2D **前面**，而且**不许给 z_index**
##   Godot 同层按树序绘制，先画的在下，影子必须在自己的建筑之下。
##   但不能用 z_index：主城地图背景站在 z=0，影子一旦降到 -1 就被整张地图盖掉了。
##
## 影子颜色：暖褐。纯黑压在彩铅纸上是数码味，冷灰又跟本作暖棕的底色打架。
## 浓度上限压在 0.28（正午），早晚被拉长会自行摊薄到 0.12。
const SHADOW_COLOR := Color(0.286, 0.227, 0.169, 1.0)
## 抽取剪影时的小图边长。原图 512，先 resize 到 96 再放大回去：
##   ① 遍历量从 26 万像素降到 9216（十张图加起来也感觉不到）；
##   ② resize 本身就是一次平滑，再让 GPU 线性插值放大回去，边缘自动变柔，
##      比自己写高斯模糊便宜得多。
const SHADOW_IMG_SIZE := 96
## 低于这个 alpha 的一律抹平（原图铅笔晕开的那些淡像素，会把影子弄脏）。
##
## ▍2026-10-20 第二轮：主城十个点已整体关掉投影（`cast_shadow = false`）
##   上一版图标是「从纸上剪下来的建筑」，剪掉地面后必须靠引擎补一层影子，否则楼是悬空的；
##   这一版图标是**印象图上原封不动的一块**，连地面淡涂和作者画的影子一起带回来了
##   （`design/build_city_patch.py`）。再投一层就是「一栋楼两个影子」，
##   而且第二个是整块地皮的形状（alpha 全满 ⇒ 剪影 = 整块矩形）。
##   所以主城的 `cast_shadow` 全部为 false；这一整套仍原样保留，
##   将来做「不带地面的图标」（换季 / 改建 / 纯剪影 UI）时打开即可。
##
## ▍历史：0.16 → 0.45 那一次（保留记录，别再踩）
##   0.16 的门槛把 alpha≈0.4 的淡地面算进剪影 → 影子是「一块地皮」而不是「一栋房子」，
##   而且是**原地倾倒**（锚点就在内容底边中点），影子正好盖在自己脚下。
const SHADOW_ALPHA_FLOOR := 0.45
## 影子更新间隔（秒）。太阳一周要 10 分钟，没必要每帧重算；
## 0.25s 一跳已经远快过肉眼能分辨的程度。
const SHADOW_TICK := 0.25
## 太阳越低影子越长 —— `SunClock.shadow_len()` 已经给了 0.25..1.0 的系数，
## 这两个常量只负责把它换算成实际的倾倒量与压扁量。
const SHADOW_SKEW_MAX := 0.95
const SHADOW_SQUASH_MAX := 0.42

## 动画基准值。sprite.scale / sprite.position 由 fit_icon_to_constraints() 写定，
## 之后所有动画一律写成 `_base_scale * 系数`，绝不直接改 sprite.scale —— 否则会把
## 图标适配尺寸冲掉。
var _base_scale := Vector2.ONE
var _base_pos := Vector2.ZERO
var _base_modulate := Color.WHITE
var _fitted := false
var _panel_base_pos := Vector2.ZERO
## 本图标「可见内容」的矩形，**按钮局部坐标**（= 贴图像素空间 × `_base_scale` + `_base_pos`）。
## `fit_icon_to_constraints()` 里算一次就缓存 —— 布局避让要读**所有**邻居的这个值，
## 每次都去 `Image.get_used_rect()` 等于把 9 张贴图各解一次（不便宜），悬浮时会掉帧。
var _content_local := Rect2()
var _content_ready := false
## 本图标「实测着色范围」的占据格（`FOOT_GRID²` 个 0/1），贴图坐标。供邻居判「面板压没压到我」。
var _footprint := PackedByteArray()
var _has_footprint := false
## 本帧实际选中的槽位（0=上 1=下 2=右 3=左），供调试/测试读取
var _panel_slot: int = 0
var _hyper: float = 0.0  # 悬浮进度 0..1
var _press: float = 0.0  # 按下进度 0..1
## 8fps 步进的拍数。呼吸按它取正弦（`_step % BREATH_STEPS`），
## 所以呼吸是「按拍跳」的阶梯，不是连续曲线。
var _step: int = 0
## BOIL_FRAMES 的当前帧
var _boil_i: int = 0
var _tick_timer: Timer = null
## 悬浮笔圈的折线（Sprite2D 局部坐标 = 贴图像素空间）
var _ring: Line2D = null
var _ring_pts := PackedVector2Array()
## 笔迹可见段 = 折线的 [tail, head] 区间：head 是画到哪，tail 是被擦到哪。
var _ring_head: float = 0.0
var _ring_tail: float = 1.0
var _tween: Tween = null
var _press_tween: Tween = null
var _panel_tween: Tween = null
## 显示序号：Label 的 autowrap 高度要等 2 帧，这期间鼠标可能已经移开 ——
## 用序号作废那次还没落地的显示，否则面板会在鼠标离开后「诈尸」。
var _panel_seq: int = 0
var _ring_head_tween: Tween = null
var _ring_tail_tween: Tween = null
## ── M-SUN1 投影 ──
## 影子本体（挂在 Sprite2D **之前**，不设 z_index）。
var _shadow: Sprite2D = null
## 影子节点的 driver。太阳一周 10 分钟，0.25s 一跳足够，不必每帧。
var _shadow_timer: Timer = null
## 锚点：**Button 局部坐标里内容框的底边中点**（`fit_icon_to_constraints()` 里算一次）。
## 影子以此点为轴倾倒，绝不跟着 `_apply_visual()` 的 hover / press 走 ——
## 那是 UI 层的反馈，太阳不该跟着鼠标动。
var _shadow_anchor := Vector2.ZERO
## 缩略图相对于原图的比例（= SHADOW_IMG_SIZE / 贴图边长），更新 transform 时要乘回去。
var _shadow_zoom := 1.0
## Sprite2D.offset：让「内容框底边中点」落在节点原点（倾斜前）。
var _shadow_offset := Vector2.ZERO


func _ready():
	# 初值 = .tscn 里那套写死的偏移；真正的槽位由 fit_icon_to_constraints()
	# 末尾的 _layout_panel() 按实测内容框重算（走不到 fit 的降级分支才用得上这个初值）。
	_panel_base_pos = container.position
	_apply_panel_style()
	_apply_label_style()
	# v4.1：提示要画在所有二级图标之上（同层内按 z_index 排序，默认是树序 → 会被后面的图标盖住）
	container.z_index = PANEL_Z
	_make_ring()
	setup()
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	_start_tick()


## 提示面板的底：**没有底**。
## 用户原话：「不要显示边框，文字自然一点」。之前那版用的是默认主题的 `Panel`
## （半透明近黑方块）—— 那个方块就是玩家说的「边框」，也是整块提示里唯一「像 UI」的东西。
## 这里换成 `StyleBoxEmpty`：不画底、不画边，**只留下内边距**。
##
## ⚠️ 内边距必须保留，不能一起清掉：
##   · Godot 默认 `Panel` 的 content_margin 是 **0**，一旦面板高度收紧到内容高度
##     文字就贴死在控件边界上（v3 已踩过一次）；
##   · `_layout_panel()` 的夹屏计算也按 `container.size` 走，留白让贴边图标的位置更从容。
func _apply_panel_style() -> void:
	if container == null:
		return
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = PANEL_PAD
	sb.content_margin_right = PANEL_PAD
	sb.content_margin_top = PANEL_PAD_V
	sb.content_margin_bottom = PANEL_PAD_V
	container.add_theme_stylebox_override("panel", sb)


## 说明文字 = 写在纸上的墨，不是系统提示框里的字。四处一起改：
##   ① 颜色 → 墨褐（主题默认是纯黑，见 TEXT_COLOR 注释）
##   ② 字号 16 → 20（地图标注要比 UI 正文看得远）
##   ③ 字重：全局 Light 太细，换成加粗 0.8px 的地图墨字（见 MAP_FONT_PATH）
##   ④ 行距 6（中文多行要透气）
## 用 override 而不是改 `theme/default_theme.tres`：那套主题是全局的，
## 为了一个提示框去动全局字色会连带影响所有界面。
func _apply_label_style() -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.add_theme_font_size_override("font_size", TEXT_SIZE)
	label.add_theme_constant_override("line_spacing", TEXT_LINE_SPACING)
	var map_font: Font = load(MAP_FONT_PATH)
	if map_font != null:
		label.add_theme_font_override("font", map_font)


## 悬浮笔圈。挂在 Sprite2D 底下当子节点 → 自动继承悬浮的缩放 / 上浮 / 按压变换，
## 圈和图标天然是同一个整体，不需要各自同步。
func _make_ring() -> void:
	_ring = Line2D.new()
	_ring.name = "HoverRing"
	# width 不在这里定：Line2D 的 width 会被父 Sprite2D 的缩放（512→180）一起缩掉，
	# 真正该写的值 = RING_WIDTH / _base_scale，只有 fit_icon_to_constraints() 之后才知道。
	_ring.default_color = RING_COLOR
	# 工程全局 NEAREST，笔画这类带软边的矢量必须自己开抗锯齿，否则斜线是台阶
	_ring.antialiased = true
	_ring.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_ring.end_cap_mode = Line2D.LINE_CAP_ROUND
	_ring.joint_mode = Line2D.LINE_JOINT_ROUND
	_ring.width_curve = _make_ring_width_curve()
	_ring.visible = false
	sprite.add_child(_ring)


## 笔压曲线：起笔轻 → 中段实 → 收笔细。Line2D 的 width 会乘这条曲线的 y 值，
## x 是沿折线的归一化位置。
func _make_ring_width_curve() -> Curve:
	var cu := Curve.new()
	cu.add_point(Vector2(0.00, 0.22))
	cu.add_point(Vector2(0.05, 1.00))
	cu.add_point(Vector2(0.86, 0.92))
	cu.add_point(Vector2(0.96, 0.55))
	cu.add_point(Vector2(1.00, 0.10))
	return cu


## 生成一条「手画圈」的折线。
##   · 起点比整圈多绕 9% → 首尾交叠出头，手画的圈从不闭合
##   · 半径叠两条谐波 → 不是正圆
##   · 收笔最后 12% 渐渐离开原轨迹（甩笔）
func _build_ring_points() -> PackedVector2Array:
	if sprite == null or sprite.texture == null:
		return PackedVector2Array()
	# sprite 是弱类型（@onready var sprite = $Sprite2D），链式返回值推断不出来，
	# 这几处必须显式标注类型，否则整个脚本 parse error。
	var tex_size: Vector2 = sprite.texture.get_size()
	var used: Rect2 = _icon_content_rect()
	var half := used.size * 0.5
	var m := maxf(half.x, half.y)
	half = half.lerp(Vector2(m, m), RING_ROUND)
	# 内容框中心相对画布中心的偏移：图标贴底 → 这个 y 是负的，圈要跟着往下沉
	var c: Vector2 = used.position + used.size * 0.5 - tex_size * 0.5
	var pad := RING_PAD / maxf(_base_scale.x, 0.0001)
	half += Vector2(pad, pad)

	var pts := PackedVector2Array()
	var start := -PI * 0.66
	var span := TAU * 1.09
	for i in range(RING_SEGMENTS + 1):
		var u := float(i) / float(RING_SEGMENTS)
		var a := start + span * u
		var w := 1.0 + 0.055 * sin(a * 3.0 + 0.9) + 0.030 * sin(a * 5.0 - 2.1)
		var tail := clampf((u - 0.88) / 0.12, 0.0, 1.0)
		var rr := Vector2(half.x * w, half.y * w) * (1.0 + 0.09 * tail * tail)
		pts.append(c + Vector2(cos(a) * rr.x, sin(a) * rr.y))
	return pts


## 笔圈的**几何最高点**比「图标可见内容顶边」还高出多少（**屏幕 px**，>0 = 圈探到内容框之上）。
##
## 为什么非要单独算这一条：圈不是按内容框画的，是**以内容框为心往外扩** `RING_PAD`、
## 再往正圆拉 `RING_ROUND`、再乘最高 1.085 的谐波 —— 三件事都只加不减，所以圈顶**永远高于**内容顶。
## 实测（图标本体恢复满尺寸之后）：十张里高出 15~27px。上槽位的提示面板要是还按
## v3 的「离内容框 8px」摆，最后一行字正好落在圈的上弧里（见 `RING_TEXT_CLEAR` 的实测数据）。
##
## ⚠️ 坐标系：`_ring_pts` 是**贴图像素空间**（`_build_ring_points` 里以贴图中心为原点），
##    `_content_local` 是**按钮局部空间**。两者差一个 `× _base_scale + _base_pos`，
##    不换算直接比会得到一个荒唐的数（贴图是 512 见方、按钮只有 180）。
## ⚠️ 不要改用「解析式推最大谐波 1.085」—— 谐波相位随角度走，最高点落在哪一段取决于
##    图标的长宽比，猜不准；`_ring_pts` 是已经烘好的真实折线，扫一遍最省事也最准。
##
## `k` = 悬浮**峰值**的缩放系数（v4.4 起）。圈的 `_base_scale` 是「适配基准」，而圈是 `Sprite2D`
## 的子节点、`sprite.scale` 里还有一个悬浮放大 —— 布局必须按**放大到位后的最坏情况**算，
## 否则圈顶会随放大再上抬一次，把净空吃掉（`k = 1.0` 拿到的就是 v4.2~v4.3 的老答案）。
func _ring_top_overshoot(k: float = 1.0) -> float:
	if _ring_pts.size() < 2:
		return 0.0
	var top := INF
	for i in range(_ring_pts.size()):
		var py: float = _ring_pts[i].y
		if py < top:
			top = py
	if not is_finite(top):
		return 0.0
	# 贴图空间 → 按钮局部空间（原点 = 贴图中心 = 缩放原点，所以 × k 就是放大后的位置）
	var ring_top_local: float = top * _base_scale.y * k + _base_pos.y
	return _content_local.position.y - ring_top_local


## 贴图里**真的有画**的那块（贴图像素坐标）。
## 2026-10-20 起 `art/city_icons/*.png` 不再是统一 512 方画布，而是
## **印象图上原封不动的一块矩形**（`design/build_city_patch.py`，尺寸各不相同、贴着建筑外沿），
## 所以 bbox 基本就是整张贴图 —— 但这条通路必须留着：将来若换成带留白的方形画布
## （比如同一栋楼的多张状态图共用一张画布），笔圈与提示面板要按真实内容框摆，
## 否则会飘在半空。取不到图像数据 / 全透明时退回整张画布，不影响主流程。
func _icon_content_rect() -> Rect2:
	var full := Rect2(Vector2.ZERO, sprite.texture.get_size())
	var img: Image = sprite.texture.get_image()
	if img == null:
		return full
	var used: Rect2 = img.get_used_rect()
	if used.size.x <= 0.0 or used.size.y <= 0.0:
		return full
	return used


## 8fps 步进：呼吸与抖动都只在这一拍上更新，中间帧一动不动。
## 这正是手绘感的来源 —— 连续插值 = 电脑在动，按拍跳 = 有人在画。
##
## ⚠️ v4.2 起呼吸与抖动都关了（用户「不要变大变小，只需要一个铅笔画一圈」），
## 时钟**不再启动**：十个图标 × 8Hz 空转不出任何变化，没必要。
## 闸门只用下面这两个常量判断 —— `PRESS_*` 是事件驱动的，不需要常驻时钟。
func _start_tick() -> void:
	if BREATH_AMP <= 0.0 and not BOIL_ON:
		return
	_tick_timer = Timer.new()
	_tick_timer.name = "BoilTick"
	_tick_timer.wait_time = TICK
	add_child(_tick_timer)
	_tick_timer.timeout.connect(_tick)
	# 相位错开：十个图标同拍跳动会读成整屏渲染故障，错开才像「每张都是手画的」。
	# 用 instance_id 而不是 randf()，保证同一次运行内可复现、便于回归测试。
	var seed_i := int(get_instance_id())
	_step = seed_i % BREATH_STEPS
	_boil_i = int(seed_i / 3) % BOIL_FRAMES.size()
	_tick_timer.start(randf_range(0.02, TICK))


func _tick() -> void:
	# Timer.start(t) 会把 wait_time 改成 t，首拍要打散相位，之后必须拉回 8fps
	if not is_equal_approx(_tick_timer.wait_time, TICK):
		_tick_timer.wait_time = TICK
	if not _is_interactive():
		return
	_step = (_step + 1) % BREATH_STEPS
	_boil_i = (_boil_i + 1) % BOIL_FRAMES.size()
	_apply_visual()


## 每次重结算 spot 时把动画态清干净（重进地图不该带着上一次的悬浮 / 按下残留）。
func _reset_anim() -> void:
	_hyper = 0.0
	_press = 0.0
	_base_modulate = Color.WHITE
	# 缓存的内容框作废：重新结算时可能走「降级隐藏 / 锁定」分支而**不再**跑 fit，
	# 留着旧值会让邻居按一个已经不存在的图标做避让。
	_content_ready = false
	_has_footprint = false
	# 作废还在等 autowrap 结算的那次显示（见 _show_panel）。只靠 container.visible
	# 也能挡住，但显式加一次序号更稳：将来若有人改动 _show_panel 的顺序就不会漏。
	_panel_seq += 1
	for tw in [_tween, _press_tween, _panel_tween, _ring_head_tween, _ring_tail_tween]:
		if tw != null and tw.is_valid():
			tw.kill()
	_ring_head_tween = null
	_ring_tail_tween = null
	# 笔迹归零：head=0 / tail=1 → 可见区间为空
	_ring_head = 0.0
	_ring_tail = 1.0
	if _ring != null:
		_ring.visible = false
	if sprite != null:
		# 未实装且无 icon 的分支会把 sprite 藏起来，重结算时要还回来
		sprite.visible = true
	if container != null:
		container.visible = false
		container.modulate.a = 1.0
		container.position = _panel_base_pos


## 图标当前是否「点得动」。不可点的图标不做缩放 / 光晕 / 呼吸。
func _is_interactive() -> bool:
	return visible and not is_future and not is_locked and not disabled


## 唯一的写入口：把呼吸、线抖、悬浮、按下四个系数合起来算成 sprite 的 transform。
## 只动 sprite 的 scale / position / modulate —— Button 自身的 size / position
## （也就是命中框）全程不变，所以动画不会让点击判定晃。
func _apply_visual() -> void:
	if not _fitted or sprite == null:
		return
	var inter := _is_interactive()
	# 待机呼吸：19 步/轮的阶梯正弦。取整到拍上 → 中间帧真的不动。
	# v4.2：BREATH_AMP = 0 → 恒等 1.0（分支留着，改常量即恢复）。
	var breath := 1.0
	if inter and BREATH_AMP > 0.0:
		breath = 1.0 + BREATH_AMP * sin(TAU * float(_step) / float(BREATH_STEPS))
	var target := HOVER_SCALE if inter else NB_SCALE
	var hit := _hover_factor(target)
	# line boil：4 帧微偏移循环。中性值必须是 **(0, 0, 1)** —— 缩放那一项 1.0 表示不缩放。
	# ⚠️ 这里曾经写成 `b = BOIL_FRAMES[i] * k`，把「1.000 = 不缩放」的基准一起乘成 0.402 了
	#    （待机时图标被画成四成大小，见文件头「v4.2」段）。**乘的必须是增量 `(f.z - 1.0)`。**
	var b := Vector3(0.0, 0.0, 1.0)
	if BOIL_ON and inter:
		var f := BOIL_FRAMES[_boil_i]
		var k := BOIL_HOVER if _hyper > 0.5 else BOIL_IDLE
		b = Vector3(f.x * k, f.y * k, 1.0 + (f.z - 1.0) * k)
	sprite.scale = _base_scale * (breath * hit * b.z)
	sprite.position = _base_pos \
		- Vector2(0.0, HOVER_LIFT * _hyper) \
		+ Vector2(0.0, PRESS_NUDGE * _press) \
		+ Vector2(b.x, b.y)
	var bright := 1.0 + HOVER_BRIGHT * _hyper
	sprite.modulate = Color(
		_base_modulate.r * bright,
		_base_modulate.g * bright,
		_base_modulate.b * bright,
		_base_modulate.a)


## 悬浮 + 按下合成的缩放系数（不含呼吸）。
func _hover_factor(target: float) -> float:
	var f := 1.0 + (target - 1.0) * _hyper
	return f * (1.0 - PRESS_SQUASH * _press)


func setup():
	# 每次重进地图都要从当前 Player 状态重新结算，先复位门控态
	visible = true
	disabled = false
	is_locked = false
	is_hidden_by_gate = false
	_locked_plot = {}

	var file := FileAccess.open(SPOTS, FileAccess.READ)
	if file == null:
		push_warning("SceneSpot[%s]: 无法打开 %s，隐藏该点" % [spot_name, SPOTS])
		visible = false
		return
	var all_info: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (all_info is Dictionary) or not all_info.has(spot_name):
		push_warning("SceneSpot[%s]: %s 中无此 spot，隐藏" % [spot_name, SPOTS])
		visible = false
		return
	_apply_spot(all_info.get(spot_name, {}))


## 把单个 spot 配置落地为可视状态（D-S1 / D-S6 全在此）。
## 抽出为独立方法，便于测试用合成 dict 直接驱动（绕过 spots.json 读取）。
## 注意：本方法自含门控态复位，单独调用也能得到正确视觉（不依赖 setup 的复位）。
func _apply_spot(spot: Dictionary) -> void:
	# 每次重结算先复位门控态（setup 也会复位，这里自含以保证独立可测）
	visible = true
	disabled = false
	is_locked = false
	is_hidden_by_gate = false
	is_future = false
	_locked_plot = {}
	info = spot
	_reset_anim()

	# 未实装区域（敬请期待）：可见但不可点击，悬浮显示说明文字。
	# 即便缺 icon/path 也不隐藏，保证玩家能在地图上看到该区域占位。
	if bool(spot.get("future", false)):
		is_future = true
		var icon_path := String(spot.get("icon", ""))
		if not icon_path.is_empty():
			var tex: Variant = load(icon_path)
			if tex != null:
				sprite.texture = tex
				fit_icon_to_constraints()
			else:
				push_warning("SceneSpot[%s]: future 区域 icon 加载失败 (%s)" % [spot_name, icon_path])
		else:
			sprite.visible = false
		# 「尚未开放」的表示：**淡成一张没画实的铅笔稿**。
		##
		# ⚠️ 原来写的是 `Color(0.66, 0.66, 0.66)`（UI 里「置灰」的常规做法）。
		#    图标改成「印象图上原封不动的一块」之后，贴图里**连纸一起**都在
		#    （`design/build_city_patch.py`），相乘就把那块纸也压暗了 ——
		#    实拍上直接**多出一个灰方块**（2026-10-20 亲眼看到），一眼读作 bug。
		#    换成只降 alpha：纸和底图同色，淡下去看不出来；楼变虚，读作「这里还没画实」，
		#    比灰色更贴合「彩铅画在纸上」这套语言（同 M-ANI1 的规矩：纸上不长 UI）。
		_base_modulate = Color(1.0, 1.0, 1.0, 0.52)
		container.visible = false
		label.text = String(spot.get("description", ""))
		_apply_visual()
		return

	# D-S1：缺 icon / path → 降级隐藏 + 告警，不崩溃
	if not _is_valid_spot(info):
		push_warning("SceneSpot[%s]: 缺 icon 或 path 字段，隐藏该点（D-S1）" % spot_name)
		visible = false
		return

	# D-S1：图标加载失败也降级，不崩
	var tex: Variant = load(info["icon"])
	if tex == null:
		push_warning("SceneSpot[%s]: icon 加载失败 (%s)，隐藏该点（D-S1）" % [spot_name, String(info["icon"])])
		visible = false
		return
	sprite.texture = tex
	# 适配必须在门控判断**之前**做：locked / locked_when 分支会提前 return，
	# 若把 fit 留在最后，锁定中的图标就一直是原始 512px（远大于 max_size）。
	fit_icon_to_constraints()

	# D-S6：visible_if 门控（随剧情解锁/隐藏）
	var gate: String = _eval_gate(info)
	if gate == "hidden":
		is_hidden_by_gate = true
		visible = false
		return
	if gate == "locked" or gate == "locked_when":
		is_locked = true
		# locked_plot（2026-10-23）：锁着，但点得动 —— 点击只播这段提示剧情、不换场景。
		# 用户口径：「教程期间点『离开』要有对应的文本，并阻止行动」。
		# 没配 locked_plot 的锁点保持旧行为：disabled，点了没反应，只靠悬浮提示板说明。
		var lp: Variant = info.get("locked_plot", null)
		if lp is Dictionary and String((lp as Dictionary).get("name", "")) != "":
			_locked_plot = lp
			disabled = false
		else:
			disabled = true
		container.visible = false
		label.text = String(info.get("locked_description", ""))
		_apply_visual()
		return

	container.visible = false
	label.text = String(info.get("description", ""))


func _on_pressed():
	if is_future:
		# 未实装区域：点击无效，仅作占位展示
		return
	# 锁着但配了 locked_plot：播提示剧情，**不换场景**（阻止行动 + 给出理由）。
	if not _locked_plot.is_empty():
		var pp := String(_locked_plot.get("path", ""))
		var pn := String(_locked_plot.get("name", ""))
		if pp != "" and pn != "":
			print("[SceneSpot] %s 被门控锁住 → 播「%s」" % [spot_name, pn])
			PlotImporter.add_plot(pp, pn)
		return
	if info.is_empty() or String(info.get("path", "")).is_empty():
		push_warning("SceneSpot[%s]: 缺 path，忽略点击（D-S1）" % spot_name)
		return
	_go_to_scene(String(info["path"]))


## 导航到目标场景。契约（GDD §5 press / D-S3 / D-S4）：
##   先写 Player.path（回档锚点）→ 切场景 → 发 scene_entered。
##   「切场景 + 发 scene_entered」这两步在 M-ANI2 之后收进了 SceneTransition
##   （它是不随场景销毁的 autoload，幕布才不会卡在合着的状态），顺序与契约不变。
func _go_to_scene(target_path: String) -> void:
	# D-S3：回档锚点先写，保证后面任何路径（读档/过天）都落对场景
	Player.path = target_path

	if _test_no_swap:
		# 测试 seam：跳过真实切场景与过场，只验证 path + 信号契约
		if ResourceLoader.exists(target_path):
			EventSignal.scene_entered.emit(target_path)
		return

	# 纸面过场的起点 = 本图标在屏幕上的中心点。玩家点的是「这里」，
	# 纸就从这里铺开 —— 换场因此有空间因果，而不是画面闪一下。
	# S-C：同城导航零成本即时，不扣任何资源。
	SceneTransition.change_scene(target_path, focus_point())


## 本图标中心在视口内的归一化坐标（0..1），与 CanvasLayer 的 UV 对齐。
## 用视口尺寸而非写死 1920x1080：视口被拉伸 / 缩放时依然是正确比例。
func focus_point() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2(0.5, 0.5)
	var vp_size := vp.get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return Vector2(0.5, 0.5)
	var c := get_global_rect().get_center()
	return Vector2(
		clampf(c.x / vp_size.x, 0.0, 1.0),
		clampf(c.y / vp_size.y, 0.0, 1.0))


# ============================================================
#  D-S1 / D-S6 纯逻辑（可单测，无需依赖真实 spots.json）
# ============================================================

## 校验 spot 基础字段是否齐全（D-S1）。icon 与 path 任一为空即视为非法。
func _is_valid_spot(spot: Dictionary) -> bool:
	return String(spot.get("icon", "")).is_empty() == false \
		and String(spot.get("path", "")).is_empty() == false


## 结算门控（D-S6），返回 "ok" / "hidden" / "locked"。
##   visible_if 不满足                      → "hidden"
##   locked=true（无论 visible_if 是否满足）→ "locked"（锁定优先级更高）
## 由 Player.player_tags 派生，method：1=all 0=any。
func _eval_gate(spot: Dictionary) -> String:
	var visible_if: Variant = spot.get("visible_if", null)
	if visible_if is Array and visible_if.size() > 0:
		var method: int = int(spot.get("visible_if_method", 1))
		if not _player_has_tags(visible_if, method):
			return "hidden"
	if bool(spot.get("locked", false)):
		return "locked"
	# D-教程：locked_when（动态正向锁）——持有这些 tag 中任意其一即锁定，
	# 用于「新手教程进行期间禁止返回主城」这类教程门控。
	# 与 locked_until 语义相反：locked_until 是「缺 tag 才锁」，locked_when 是「有 tag 就锁」。
	# locked_when_not（2026-10-14 负向修饰）：locked_when 命中后，若持本表**任一** tag 则不锁
	# —— 用于「教程进行中、但执行过家业之后放行返回主城」：主锁仍是门控 tag（正向），
	# 解锁条件是进度 tag。method 固定按 any（「持有其一即豁免」），不提供 all 变体。
	var locked_when: Variant = spot.get("locked_when", null)
	var locked_when_not: Variant = spot.get("locked_when_not", null)
	if locked_when is Array and locked_when.size() > 0:
		var lw_method: int = int(spot.get("locked_when_method", 0))
		if _player_has_tags(locked_when, lw_method):
			var exempt: bool = locked_when_not is Array and locked_when_not.size() > 0 \
				and _player_has_tags(locked_when_not, 0)
			if not exempt:
				return "locked_when"
	# D-教程：locked_until（动态反向锁）——未持有这些 tag 时锁定，
	# 用于「管家引导完成前禁止离开家」这类教程门控。
	var locked_until: Variant = spot.get("locked_until", null)
	if locked_until is Array and locked_until.size() > 0:
		var lu_method: int = int(spot.get("locked_until_method", 1))
		if not _player_has_tags(locked_until, lu_method):
			return "locked"
	return "ok"


func _player_has_tags(tags: Array, method: int) -> bool:
	if tags.is_empty():
		return true
	if method == 0:  # any
		for t in tags:
			if Player.player_has_tags([String(t)]):
				return true
		return false
	# all（默认）
	for t in tags:
		if not Player.player_has_tags([String(t)]):
			return false
	return true


func _on_mouse_entered():
	# locked / future 时也显示（此时 label 已被设为 locked_description / description），
	# 让玩家悬浮看到「这是什么 / 为什么不能点」，而不是静默禁用。
	if visible:
		_show_panel(true)
	# 只有真的点得动才画圈：圈是「点得动」的承诺
	if _is_interactive():
		_draw_ring(true)
	_tween_hyper(1.0)


func _on_mouse_exited():
	_show_panel(false)
	_draw_ring(false)
	_tween_hyper(0.0)


func _on_button_down():
	if _is_interactive():
		_tween_press(1.0)


func _on_button_up():
	_tween_press(0.0)


## 圈的画与擦。两段各自独立补间，所以中途反向（画到一半就移开鼠标）也接得住：
## 可见段永远是 [tail, head] 这个区间。
func _draw_ring(on: bool) -> void:
	if _ring == null:
		return
	if _ring_head_tween != null and _ring_head_tween.is_valid():
		_ring_head_tween.kill()
	if _ring_tail_tween != null and _ring_tail_tween.is_valid():
		_ring_tail_tween.kill()
	if on:
		# 重新起笔：**头与尾都要归零**，而且补间必须显式从 0.0 起。
		# ⚠️ 这里曾经只把 tail 归零、head 写成「从 `_ring_head` 补间到 1.0」——
		#    而**擦除只动 tail，head 擦完仍停在 1.0** → 第二次悬浮就是 `1.0 → 1.0`，
		#    一个点都不长：圈**整圈瞬间出现**，只剩「离开时擦掉」还有动画。
		#    用户看到的就是这个：「只有鼠标离开后有线消失的动画」。
		#    实测逐帧点数（`--ring` / `--ringshots`，商业区）：
		#      改前 第 1 次 `13,23,31,…,81`（正常）、**第 2 次 `81,81,81,…`（没画）**；
		#      改后 第 1/2 次都是 `21,79,81`（第 2/6/20 帧）—— 两轮一致。
		# ⚠️ 赋值后必须立刻 `_sync_ring()`：`Line2D.points` 不会自己清，
		#    擦除结束时它仍留着上一轮的 81 个点（只是 `visible=false`）——
		#    不刷新的话重新起笔的第一帧会**闪一下整圈**。
		_ring_head = 0.0
		_ring_tail = 0.0
		_ring_tail_tween = null
		_sync_ring()
		if _ring_pts.size() >= 2:
			_ring.visible = true
		_ring_head_tween = create_tween()
		# EXPO/OUT：起笔快、收笔缓 —— 手画一圈的节奏（先果断绕过去，最后在找收笔位置）
		_ring_head_tween.tween_method(_set_ring_head, 0.0, 1.0, RING_DRAW_TIME) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	else:
		_ring_tail_tween = create_tween()
		# QUAD/IN：先慢后快，像橡皮压上去再一路擦过去
		_ring_tail_tween.tween_method(_set_ring_tail, _ring_tail, 1.0, RING_ERASE_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _set_ring_head(v: float) -> void:
	_ring_head = clampf(v, 0.0, 1.0)
	_sync_ring()


func _set_ring_tail(v: float) -> void:
	_ring_tail = clampf(v, 0.0, 1.0)
	_sync_ring()


## 可见段 = 折线上 [tail, head] 这一段。
## 擦除是从**前端**消失、不是把已有的缩短 —— 前者读作「橡皮顺着笔迹擦过去」，
## 后者读作「倒放」，一眼假。
func _sync_ring() -> void:
	if _ring == null or _ring_pts.size() < 2:
		return
	var a := int(round(_ring_tail * float(RING_SEGMENTS)))
	var b := int(round(_ring_head * float(RING_SEGMENTS))) + 1
	if b - a < 2:
		_ring.visible = false
		return
	_ring.visible = true
	_ring.points = _ring_pts.slice(a, mini(b, _ring_pts.size()))


## 悬浮**峰值**的缩放系数 —— 即「鼠标稳稳停在图标上、补间走完」那一刻 `sprite.scale ÷ _base_scale`。
##
## 布局要的是这个「最坏情况」，不是当前的 `_hyper`：面板与放大**同一瞬间起跑**
## （面板淡入 0.12s、放大 0.18s，两者重叠），所以按即时值摆位会在中途撞上。
## 不可交互的图标不放大（`NB_SCALE`，目标恒 1.0），所以对它们返回 1.0 ——
## 这样它们的提示位置与 v4.2/v4.3 完全一致，不被这次改动波及。
func _hover_peak_scale() -> float:
	return HOVER_SCALE if _is_interactive() else NB_SCALE


## 说明文字**不换行**时有多宽（屏幕像素）。取最长的一行 —— 描述里可能有手动换行。
## `_layout_panel()` 用它把面板收到刚好的宽度（见 PANEL_WIDTH 一段）：
## 描述越短、面板越窄、越不容易压到邻居。量不出来就退回上限，行为与旧的定宽一致。
func _text_natural_width() -> float:
	if label == null:
		return PANEL_WIDTH
	var f: Font = label.get_theme_font("font")
	if f == null:
		return PANEL_WIDTH
	var fs: int = label.get_theme_font_size("font_size")
	if fs <= 0:
		return PANEL_WIDTH
	var widest := 0.0
	for line in label.text.split("\n"):
		widest = maxf(widest, f.get_string_size(String(line), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	if widest <= 0.0:
		return PANEL_WIDTH
	return widest


## 把提示面板摆到图标旁边 —— 优先**正上方**，被别的图标占了就改槽位（v4.1）。
##
## 位置一律按「实测内容框」而不是按钮框 / 512 画布框来算：`art/city_icons/*.png` 十张都是
## 512 方画布、内容一律贴底，**上方留白各不相同** —— 按画布框摆，面板会飘在半空，
## 而且十个图标彼此间距对不齐（实测差最多 100+ 屏幕像素）。按内容框摆才叫「写在它头上」。
##
## 槽位优先级 上 → 下 → 右 → 左；判据是**压住了多少别人的东西**（`_overlap_area()`：
## 图标按真实着色面积、主 UI 常驻控件按整块矩形，含自己 —— 夹屏有可能把面板推回来压到自己身上）。
## 第一个代价为 0 的槽位就用它；四个都被占就取代价最小的。**为什么非做不可**：面板是 Button 的
## 子节点，同层内按树序画，排在后面的图标会直接盖住前面图标的提示。现在 z_index（见 `PANEL_Z`）
## 保证了不被盖住，槽位避让则让它**尽量也不需要去盖别人**。
##
## ⚠️ 别改成「内容框 bbox 相交」—— 会把「其实没碰到」当成碰到（见 `FOOT_GRID` 的注释）。
func _layout_panel() -> void:
	if container == null or sprite == null or sprite.texture == null:
		return
	# 宽度按文本自然宽度收紧（上限 PANEL_WIDTH）、高度交给内容：高度先写 0，
	# Control 会把 size 抬到 combined minimum size（也就是文字换行之后的真实高度）
	# —— 一行字就不该占三行的高。宽度见 PANEL_WIDTH 那一段。
	container.size = Vector2(
		clampf(_text_natural_width() + PANEL_PAD * 2.0, PANEL_MIN_WIDTH, PANEL_WIDTH), 0.0)
	var w: float = container.size.x
	var h: float = container.size.y

	# 用缓存的 _content_local（按钮局部坐标），不再每次从贴图重算
	var c := _content_local
	var cx := c.position.x + c.size.x * 0.5
	var cy := c.position.y + c.size.y * 0.5
	# ⚠️ v4.4：悬浮放大了图标本体，所以**两条**约束都要按「放大到位后」算，不能按静态算：
	#   ① v3 那条「面板底边离内容框 PANEL_GAP」—— 内容顶也随放大上抬，所以要先补回抬升量；
	#   ② v4.2 那条「让开笔圈上弧」—— 圈是 `Sprite2D` 子节点，跟着一起放大，圈顶再上抬一次。
	#   按**峰值**（不是当前 `_hyper`）算：面板与放大同一瞬间起跑（淡入 0.12s / 放大 0.18s，
	#   两者重叠），所以「面板摆哪」必须取放大到位后的最坏情况，否则两者会在中途撞上。
	var k := _hover_peak_scale()
	var c_rise := maxf((c.position.y - _base_pos.y) * (1.0 - k), 0.0)
	# 上槽位的底边既要按 v3 的 PANEL_GAP 离内容框，又要**让开笔圈的上弧**（见 RING_TEXT_CLEAR）。
	# 圈的可见上沿 = 圈几何最高点 − 半个笔宽（笔画向上下各溢出 RING_WIDTH/2）。
	# 推导：面板底边 = 内容顶 − gap；文字盒下沿 = 面板底边 − PANEL_PAD_V；
	#      要求「文字盒下沿 ≥ 圈可见上沿 + RING_TEXT_CLEAR」
	#      → gap ≥ over + RING_WIDTH/2 + RING_TEXT_CLEAR − PANEL_PAD_V。
	var gap_up := PANEL_GAP + c_rise
	if _content_ready and _ring_pts.size() >= 2:
		gap_up = maxf(gap_up,
			_ring_top_overshoot(k) + RING_WIDTH * 0.5 + RING_TEXT_CLEAR - PANEL_PAD_V)
	var slots: Array[Vector2] = [
		Vector2(cx - w * 0.5, c.position.y - gap_up - h),
		Vector2(cx - w * 0.5, c.position.y + c.size.y + PANEL_GAP),
		Vector2(c.position.x + c.size.x + PANEL_GAP, cy - h * 0.5),
		Vector2(c.position.x - PANEL_GAP - w, cy - h * 0.5),
	]
	# 「让开笔圈」是**软**约束，「别压到别人」是**硬**约束 —— 软的不许把硬的挤掉。
	# 让圈等于把面板整体再上移 `gap_up - PANEL_GAP` px，而正上方可能正好是主 UI 的一条边：
	# 实测「医院」上方只剩 112px（再上去就是「进行中行动」板的底边 y=450），
	# 让圈后 8+102 → 26.6+102 就伸进板里 5066 px² → 上槽位被判成不可用 →
	# 整块提示被迫掉到**下方**，反倒真压住交通运输站 937 px²（v4.1 本来是干净的 0）。
	# 这不是「选了个更差的槽」，是软约束把硬约束顶掉了。所以这里比一次代价：
	# 让圈之后更差就退回 v3 的「只离内容框」，宁可笔圈擦着字，也不去压别人 / 压主 UI。
	if gap_up > PANEL_GAP:
		var plain_up := Vector2(cx - w * 0.5, c.position.y - PANEL_GAP - h)
		var ring_cost := _overlap_area(_clamp_panel(slots[0], w, h), w, h)
		var plain_cost := _overlap_area(_clamp_panel(plain_up, w, h), w, h)
		if ring_cost > plain_cost:
			slots[0] = plain_up
	var best := slots[0]
	var best_cost := INF
	var best_i := 0
	for i in range(slots.size()):
		var local := _clamp_panel(slots[i], w, h)
		var cost := _overlap_area(local, w, h)
		if cost < best_cost:
			best_cost = cost
			best = local
			best_i = i
		if cost <= 0.0:
			break
	container.position = best
	_panel_base_pos = best
	_panel_slot = best_i


## 把面板夹进视口：地图左右两端的图标水平居中后，会有半截顶出屏幕。
func _clamp_panel(local: Vector2, w: float, h: float) -> Vector2:
	var btn := get_global_rect()
	var vp := get_viewport_rect()
	var out := local
	out.x = clampf(btn.position.x + local.x, vp.position.x, maxf(vp.position.x, vp.end.x - w)) - btn.position.x
	out.y = clampf(btn.position.y + local.y, vp.position.y, maxf(vp.position.y, vp.end.y - h)) - btn.position.y
	return out


## 面板（按钮局部坐标 + 尺寸）压住的**别人的东西**（折算成 px² 的代价）。0 = 完全不压。
## 两把尺子拼起来，因为它们「有画的形状」不一样：
##   · **二级图标** → 逐个问它自己的 `footprint_overlap()`（那张实测着色占据格）。
##     不能拿内容框 bbox 相交代替：图标 bbox 的角上常常是空的（尖顶、屋檐），
##     实测「孤儿院 / 商业区」bbox 说压了 189 / 209 px²，真实着色重合是 0（见 FOOT_GRID 注释）。
##   · **主 UI 常驻控件** → 直接按矩形相交面积算。这些是**实底的方块**（卡槽 / 行动板 / 顶栏纸），
##     没有"角上是空的"这回事；面板伸进去多少，深色墨字就在深色底上待多久。
##     ⚠️ 这一项的数量级远大于图标那项（卡槽是 1880×238），这是**故意的** ——
##     宁可换个槽位，也不能把字写在深色面板上。
func _overlap_area(local: Vector2, w: float, h: float) -> float:
	var me := Rect2(get_global_rect().position + local, Vector2(w, h))
	var total := 0.0
	var p := get_parent()
	if p != null:
		for n in p.get_children():
			if not n.has_method("footprint_overlap"):
				continue
			var v: Variant = n.call("footprint_overlap", me)
			if v is float:
				total += float(v)
	for r in _ui_forbidden_rects():
		var ix := me.intersection(r)
		if ix.size.x > 0.0 and ix.size.y > 0.0:
			total += ix.size.x * ix.size.y
	return total


## 主 UI 常驻控件的「禁入区」（屏幕坐标），由**声明了** `panel_forbidden_rects()` 的顶层节点自己报。
## 当前就是 `main_ui.gd` —— 矩形从它那些控件的 `get_global_rect()` 实读，所以改了
## `main_ui.tscn` 的布局（卡槽挪位置、行动板改大小），这里自动跟着变，不会悄悄写错。
##
## ⚠️ 不在这里写死坐标。写死过一次的代价是：以后谁把卡槽挪高 40px，提示就会重新钻进去，
## 而且没有任何报错 —— 那种错只有玩家能发现。
##
## 找不到（纯剧情场景没有主 UI）就返回空数组，行为退回「只避让二级图标」（本版之前的行为）。
## 调用点在 `_overlap_area()` 里，每次 `_layout_panel()` 最多 4 次 × 每次遍历当前场景的
## 直接子节点（个位数）—— 开销可忽略，不需要缓存（缓存反而会在切场景后过期）。
func _ui_forbidden_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var tree := get_tree()
	if tree == null:
		return out
	var root := tree.current_scene
	if root == null:
		return out
	_collect_ui_rects(root, out)
	for n in root.get_children():
		_collect_ui_rects(n, out)
	return out


func _collect_ui_rects(n: Node, out: Array[Rect2]) -> void:
	if not n.has_method("panel_forbidden_rects"):
		return
	var v: Variant = n.call("panel_forbidden_rects")
	if not (v is Array):
		return
	for r in (v as Array):
		if r is Rect2:
			var rr: Rect2 = r
			if rr.size.x > 0.0 and rr.size.y > 0.0:
				out.append(rr)


## 本图标「实测着色范围」的占据格，以及它在贴图里的排布：
## 格 (gx, gy) 对应的贴图区域 = `used.position + used.size * (gx/FOOT_GRID, gy/FOOT_GRID)` 起的一格。
## 采样 `FOOT_SAMPLES²` 个点，任一不透明即认为该格「有画」。
## 只在 fit 时算一次（每图标 ~1k 次采样，开销可忽略），邻居判重合时读这张表。
func _build_footprint(img: Image, used: Rect2) -> void:
	_footprint = PackedByteArray()
	_has_footprint = false
	if img == null or used.size.x < 1.0 or used.size.y < 1.0:
		return
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	if w <= 0 or h <= 0 or data.size() < w * h * 4:
		return
	var g := FOOT_GRID
	var n := FOOT_SAMPLES
	_footprint.resize(g * g)
	for gy in range(g):
		for gx in range(g):
			var hit := 0
			for sy in range(n):
				for sx in range(n):
					var u := (float(gx) + (float(sx) + 0.5) / float(n)) / float(g)
					var v := (float(gy) + (float(sy) + 0.5) / float(n)) / float(g)
					var tx := clampi(int(used.position.x + used.size.x * u), 0, w - 1)
					var ty := clampi(int(used.position.y + used.size.y * v), 0, h - 1)
					# RGBA8 → alpha 是第 4 个字节
					if data[(ty * w + tx) * 4 + 3] > 128:
						hit = 1
						break
				if hit == 1:
					break
			_footprint[gy * g + gx] = hit
	_has_footprint = true


## 这块屏幕矩形压住本图标多少**真实着色面积**（px²，按占据格 × 格面积折算）。
## 供邻居在做提示面板避让时调用 —— 这就是「面板压到别人的画」的判据。
func footprint_overlap(rect: Rect2) -> float:
	if not _has_footprint or not _content_ready:
		return 0.0
	var r := content_rect_global()
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return 0.0
	var ix := rect.intersection(r)
	if ix.size.x <= 0.0 or ix.size.y <= 0.0:
		return 0.0
	var g := FOOT_GRID
	var cw := r.size.x / float(g)
	var chh := r.size.y / float(g)
	var gx0 := clampi(int((ix.position.x - r.position.x) / cw), 0, g - 1)
	var gy0 := clampi(int((ix.position.y - r.position.y) / chh), 0, g - 1)
	var gx1 := clampi(int(ceil((ix.end.x - r.position.x) / cw)), 0, g)
	var gy1 := clampi(int(ceil((ix.end.y - r.position.y) / chh)), 0, g)
	var cell := cw * chh
	var hits := 0
	for gy in range(gy0, gy1):
		for gx in range(gx0, gx1):
			if _footprint[gy * g + gx] == 1:
				hits += 1
	return float(hits) * cell


## 所有二级图标「可见内容」的屏幕矩形（含自己）。只给调试打表 / 人看，不参与避让判据。
func _all_icon_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var p := get_parent()
	if p == null:
		return out
	for n in p.get_children():
		if not n.has_method("content_rect_global"):
			continue
		var r: Variant = n.call("content_rect_global")
		if r is Rect2:
			var rr: Rect2 = r
			if rr.size.x > 0.0 and rr.size.y > 0.0:
				out.append(rr)
	return out


## 本图标「可见内容」在屏幕（画布）空间的矩形。邻居做布局避让时读它。
## 不在场 / 无贴图 / 图标被隐藏时返回空 Rect2（调用方据此跳过）。
func content_rect_global() -> Rect2:
	if not _content_ready or not visible:
		return Rect2()
	if sprite == null or not sprite.visible or sprite.texture == null:
		return Rect2()
	return Rect2(get_global_rect().position + _content_local.position, _content_local.size)


## 文字面板：先让笔圈画到八成再浮出来 —— 「先在纸上圈，再在旁边写字」。
## 位置每次按 `_layout_panel` 重算（不再吃 .tscn 里那套写死的偏移）。
## 从下方滑入 + 淡入，不用 BACK 过冲（那一下弹跳是「UI 味」，不是「纸味」）。
func _show_panel(on: bool) -> void:
	_panel_seq += 1
	var seq := _panel_seq
	if _panel_tween != null and _panel_tween.is_valid():
		_panel_tween.kill()
	if on:
		container.visible = true
		container.modulate.a = 0.0
		_layout_panel()
		container.position = _panel_base_pos + Vector2(0.0, PANEL_RISE)
		# Label 开了 autowrap：换行后的真实高度要 2 帧才结算（1 帧只能拿到换行前的
		# 高度，面板底边就会按错的值算、直接压到图标上）。等结算完再定最终位置 ——
		# 这两帧里 modulate.a 还是 0，所以看不到这一次「预摆位」。
		await get_tree().process_frame
		# 换场景会把本节点摘出树：鼠标悬停浮出面板 → 点下去换场 → 这两帧还在等 →
		# 醒来 get_tree() 已是 null，每次换场刷一组 ERROR + SCRIPT ERROR（巡游 14 次全中）。
		if not is_inside_tree():
			return
		await get_tree().process_frame
		if seq != _panel_seq or not container.visible:
			return
		_layout_panel()
		container.position = _panel_base_pos + Vector2(0.0, PANEL_RISE)
		_panel_tween = create_tween()
		# 前面等掉的 ~2 帧（≈0.033s）已经替掉了原 0.10s 延时的一部分
		_panel_tween.tween_interval(0.07)
		_panel_tween.tween_property(container, "modulate:a", 1.0, 0.18)
		_panel_tween.parallel().tween_property(container, "position", _panel_base_pos, 0.18) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		if not container.visible:
			return
		_panel_tween = create_tween()
		_panel_tween.tween_property(container, "modulate:a", 0.0, 0.12)
		_panel_tween.tween_callback(func() -> void: container.visible = false)


func _tween_hyper(target: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if is_equal_approx(_hyper, target):
		return
	_tween = create_tween()
	# 进出一律 CUBIC/EASE_OUT，不再过冲：过冲是「UI 弹跳」，
	# 这里要的是「纸上的东西被轻轻抬了一下」。
	_tween.tween_method(_set_hyper, _hyper, target, 0.18 if target > _hyper else 0.20) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _tween_press(target: float) -> void:
	if _press_tween != null and _press_tween.is_valid():
		_press_tween.kill()
	_press_tween = create_tween()
	_press_tween.tween_method(_set_press, _press, target, 0.08 if target > 0.0 else 0.14) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _set_hyper(v: float) -> void:
	_hyper = v
	_apply_visual()


func _set_press(v: float) -> void:
	_press = v
	_apply_visual()


func fit_icon_to_constraints():

	# 工程全局 default_texture_filter=0（NEAREST）。点采样会把铅笔细描边整条吃掉，
	# 这里单独开线性过滤。
	# ⚠️ 主城十张现在是 **1:1**（`max_size` 就直接写贴图原尺寸，见 `design/apply_city_patch.py`），
	#    只有悬浮放大 4% 那一下会重采样 —— 线性过滤仍然必要，别因为「1:1」就去掉。
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	# 获取原始图片尺寸
	var original_size = sprite.texture.get_size()
	# 计算缩放比例（确保不超过最大尺寸，不小于最小尺寸）
	var scale_x = max_size.x / original_size.x
	var scale_y = max_size.y / original_size.y
	var scale_ratio = min(scale_x, scale_y)  # 取较小的比例，避免超出最大尺寸

	# 确保缩放后不小于最小尺寸
	var min_scale_x = min_size.x / original_size.x
	var min_scale_y = min_size.y / original_size.y
	var min_scale_ratio = max(min_scale_x, min_scale_y)
	scale_ratio = max(scale_ratio, min_scale_ratio)  # 不小于最小比例

	# 应用缩放（保持宽高比）
	sprite.scale = Vector2(scale_ratio, scale_ratio)
	var scaled_size = original_size * scale_ratio
	self.size = scaled_size

	self.position = ordinary
	sprite.position = self.size/2

	# M-ANI1：把适配结果记成动画基准。此后所有缩放 / 位移都是
	# `_base_scale * 系数`、`_base_pos ± 偏移`，不再直接写 sprite.scale，
	# 否则悬浮一动就把适配尺寸冲掉了。
	_base_scale = sprite.scale
	_base_pos = sprite.position
	_fitted = true
	# v4.1：缓存「可见内容」的按钮局部矩形，供邻居做提示面板的避让。
	# 必须用 _base_scale / _base_pos（适配基准）而不是 sprite.scale / sprite.position：
	# 后者带着呼吸与 boil 的即时偏移，缓存值会跟着抖。
	var tex_size: Vector2 = sprite.texture.get_size()
	var used_c: Rect2 = _icon_content_rect()
	_content_local = Rect2(
		(used_c.position - tex_size * 0.5) * _base_scale + _base_pos,
		used_c.size * _base_scale)
	_content_ready = true
	# v4.1：同时建「实测着色范围」占据格 —— 邻居判「面板压没压到我」用的是它，不是内容框 bbox
	_build_footprint(sprite.texture.get_image(), used_c)
	# 笔圈的几何由「实测内容框 ÷ 缩放」推出来，适配一变就必须重算，
	# 否则换图标尺寸后圈会错位或大小不对。
	_ring_pts = _build_ring_points()
	# ⚠️ Line2D 挂在 Sprite2D 之下 → 它的 width 走的是**贴图像素局部空间**，
	# 会被 sprite 的缩放（512 → 180，即 0.3516）一起缩掉。想得到屏幕上的 3px，
	# 必须反除缩放；直接写 3.0 的话屏上只有约 1px，等于看不见（已踩）。
	if _ring != null and _base_scale.x > 0.0:
		_ring.width = RING_WIDTH / _base_scale.x
	# 面板槽位也跟着适配结果走：内容框、缩放一变，正上方那个位置就得重算。
	_layout_panel()
	_sync_ring()
	_apply_visual()
	# M-SUN1：影子的一切几何都建立在「适配结果」与「内容框」之上
	# （用到 _base_scale / _content_local），必须排在它们之后。
	_make_shadow()


## ── M-SUN1 建筑投影 ──────────────────────────────────────────
##
## 用**图标自己的 alpha 剪影**做影子，而不是垫一个椭圆渐变。
## 做出来的是「这一刻太阳把建筑照出来的影」，方向、长度、浓度都随时间走，
## 源头在 `script/sun_clock.gd`（一周 = 10 分钟）。
##
## 只碰 `_shadow` 这一棵树枝 —— `_apply_visual()` 里那套 hover / press 是
## UI 反馈，太阳不该跟着鼠标动，两者互不相干。
func _make_shadow() -> void:
	if not cast_shadow:
		# 图标自带原稿的影子（见 cast_shadow 的说明）。这里直接不进投影分支，
		# `_shadow` 保持 null，`_update_shadow()` 自己会在第一行返回。
		return
	if not _fitted or sprite == null or sprite.texture == null or not _content_ready:
		return
	var img: Image = sprite.texture.get_image()
	if img == null:
		return
	var src_w := float(img.get_width())
	var src_h := float(img.get_height())
	if src_w < 1.0 or src_h < 1.0:
		return

	# 缩到小图再放大回去：省钱，而且顺手拿到一次免费平滑（见常量注释）。
	_shadow_zoom = float(SHADOW_IMG_SIZE) / maxf(src_w, src_h)
	var sw := maxi(2, int(round(src_w * _shadow_zoom)))
	var sh := maxi(2, int(round(src_h * _shadow_zoom)))
	var small: Image = img.duplicate() as Image
	if small == null:
		return
	small.resize(sw, sh, Image.INTERPOLATE_LANCZOS)
	small.convert(Image.FORMAT_RGBA8)

	# 只留 alpha（剪影），颜色一律刷成暖褐；低于地板的淡像素抹掉，
	# 否则铅笔晕开的那层会把影子拖成一片脏雾。
	var data := small.get_data()
	var n := sw * sh
	var cr := int(SHADOW_COLOR.r * 255.0)
	var cg := int(SHADOW_COLOR.g * 255.0)
	var cb := int(SHADOW_COLOR.b * 255.0)
	for i in range(n):
		var a := float(data[i * 4 + 3]) / 255.0
		if a <= SHADOW_ALPHA_FLOOR:
			data[i * 4 + 3] = 0
			continue
		a = (a - SHADOW_ALPHA_FLOOR) / (1.0 - SHADOW_ALPHA_FLOOR)
		data[i * 4] = cr
		data[i * 4 + 1] = cg
		data[i * 4 + 2] = cb
		data[i * 4 + 3] = int(round(a * 255.0))
	var small_sil := Image.create_from_data(sw, sh, false, Image.FORMAT_RGBA8, data)

	if _shadow == null:
		_shadow = Sprite2D.new()
		_shadow.name = "Shadow"
		_shadow.centered = true
		_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(_shadow)
		# 树序 = 绘制顺序：影子必须排在图标之前，才能躺在自己建筑底下。
		# ⚠️ 不能用 z_index，会沉到 z=0 的地图背景下面彻底看不见。
		move_child(_shadow, sprite.get_index())

	_shadow.texture = ImageTexture.create_from_image(small_sil)

	# 锚点：Button 局部坐标里内容框的**底边中点**。影子绕着它倾倒。
	_shadow_anchor = Vector2(
		_content_local.position.x + _content_local.size.x * 0.5,
		_content_local.position.y + _content_local.size.y)
	# offset：把小图里「内容底边中点」搬到节点原点，它才是 transform 的不动点。
	var used := _icon_content_rect()
	_shadow_offset = Vector2(
		sw * 0.5 - (used.position.x + used.size.x * 0.5) * _shadow_zoom,
		sh * 0.5 - (used.position.y + used.size.y) * _shadow_zoom)
	_shadow.offset = _shadow_offset

	if _shadow_timer == null:
		_shadow_timer = Timer.new()
		_shadow_timer.name = "ShadowTick"
		add_child(_shadow_timer)
		_shadow_timer.wait_time = SHADOW_TICK
		_shadow_timer.timeout.connect(_update_shadow)
	_update_shadow()


## 按当前太阳位置重摆影子。SunClock 0.25s 被敲一次（M-SUN1 v2：autoload 有状态）。
func _update_shadow() -> void:
	if _shadow == null or not _fitted:
		return
	var ln := SunClock.shadow_len()
	var skew := SunClock.shadow_skew_dir() * SHADOW_SKEW_MAX * ln
	var squash := SHADOW_SQUASH_MAX * ln
	var sx := _base_scale.x * _shadow_zoom
	var sy := _base_scale.y * _shadow_zoom
	_shadow.position = _shadow_anchor
	# x_axis 保持横向；y_axis 既被压扁又被横向斜切 —— 整个剪影就此倒向反太阳一侧。
	_shadow.transform = Transform2D(
		Vector2(sx, 0.0),
		Vector2(skew * sx, squash * sy),
		Vector2.ZERO)
	_shadow.modulate = Color(1.0, 1.0, 1.0, SunClock.shadow_alpha())
