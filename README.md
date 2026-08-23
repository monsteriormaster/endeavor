# Endeavor（奋进）

基于 **Godot 4.7** 开发的分支叙事养成类视觉小说游戏。

> 出身显赫贵族家庭的年轻男子，自幼热爱艺术。家庭变故后不得不放弃梦想继承家业。在治理领地、招募伙伴、探索世界的过程中，玩家的每一个选择都将书写不同的命运。

---

## 技术栈

- **引擎**：Godot 4.7（GL Compatibility 渲染模式）
- **语言**：GDScript
- **分辨率**：1920 × 1080（横屏）
- **插件**：YAFSM（Yet Another Finite State Machine）状态机编辑器
- **数据格式**：JSON

---

## 快速开始

1. 用 Godot 4.7 打开项目根目录
2. 主场景已配置为 `scene/loading.tscn`
3. 按 `F5` 运行游戏

---

## 项目结构

```
endeavor/
├── scene/                     # 游戏场景（loading / 角色创建 / 引导 / 主城 / 监狱）
├── components/                # UI 组件（对话框 / 角色面板 / 触发器弹窗 / 卡牌区 / 卡槽 / 触发器点）
├── script/                    # 纯代码类（玩家数据 / 剧情引擎 / 存档系统 / 事件总线 / 卡牌 / 触发器）
├── resoures/                  # JSON 数据文件
│   ├── plot/                  #    剧情文本内容
│   ├── configs/               #    NPC 交互配置（条件 / 限制 / 优先级）
│   ├── triggers/              #    触发器配置（trigger.json，schema v6）
│   ├── characters.json        #    角色属性定义
│   ├── tags.json              #    标签系统定义
│   ├── spots.json             #    场景传送点
│   ├── equipment.json         #    装备 / 道具卡数据
│   ├── gifts_begin.json       #    初始天赋选择
│   └── checks/                #    鉴定配置
├── art/                       # 美术资源（角色立绘、场景图标）
├── map/                       # 地图子场景（被 scene/ 调用）
├── addons/                    # 插件（YAFSM 状态机）
├── debug/                     # 调试场景（已清空，需要时再建；仅本地验证用，不进主线）
└── project.godot               # 引擎配置文件
```

---

## 核心系统

### 8 个自动加载单例（Autoload）

> 顺序即 `project.godot` 中的加载顺序；`TriggerManager` 依赖 `TriggerLoader`、`Player`，故列于其后。

| 单例 | 文件 | 职责 |
|------|------|------|
| `Player` | `script/player.gd` | 游戏运行时全部数据（属性、标签、金钱、物品、装备等） |
| `PlotImporter` | `script/plot_importer.gd` | 加载并执行 JSON 定义的对话剧情 |
| `SaveLoader` | `script/save_loader.gd` | 存档 / 读档（`user://endeavoursavegame.json`） |
| `EventSignal` | `script/event_signal.gd` | 全局事件信号总线 |
| `CheckProcessor` | `script/check_processor.gd` | 鉴定（加权骰子 / 比大小），`run_check` 即时结算 |
| `CardRegistry` | `script/card_registry.gd` | 卡牌注册表（启动加载 characters.json + equipment.json，按 id / 类型 / tag 查询） |
| `TriggerLoader` | `script/trigger_loader.gd` | 触发器加载器（取数据、默认值合成、校验、display 选择、回合路由） |
| `TriggerManager` | `script/trigger_manager.gd` | 触发器全局管理（效果落地、流程 tag 字典、便捷打开弹窗） |

> **设计原则**：Autoload 只放「无状态查询服务 / 真正的全局状态」，不放 gameplay 逻辑。
> `TriggerLoader` 是纯查询服务（无状态变更），`TriggerManager` 只做效果落地与流程字典管理，
> 真正的路由 / 结算逻辑在 `TriggerPopup`（UI 组件）中。

### 属性系统

角色属性（初始 20 点可分配）：
- **魅力（app）** — 影响社交互动
- **智力（int）** — 影响知识分析
- **教育（edu）** — 教育背景
- **体魄（bod）** — 身体能力
- **力量（str）** — 战斗体力相关

### 标签系统

标签用于条件判断和剧情分支，定义在 `resoures/tags.json`：

| 标签 | 类型 | 说明 |
|------|------|------|
| 悸动 | 关系 | 爱情 / 热情 |
| 忠诚 | 关系 | 誓死追随 |
| 侠义 | 性格 | 重诺轻生死 |
| 羁绊 | 关系 | 灵魂绑定 |
| 神偷 | 技能 | 偷窃技巧 |
| 神速 | 技能 | 超乎常人速度 |
| 灵感 | 超凡 | 能看见世界的真相 |
| 灾厄 | 命运 | 灾厄之钥匙 |
| 学习 | 性格 | 好学 |

### 对话条件与分支

每个对话条目可配置条件（conditions）和限制（limits），支持：

- 属性比较（金钱、年龄、时间等）
- 玩家标签判断（AND / OR 模式）
- 可堆叠标签值区间
- NPC 标签和属性条件
- 自定义属性判断（如 `time == 2`）

条件不满足的选项会以灰色文字显示原因。

---

### 卡牌系统

> 核心动词是「分配槽位」（密教模拟器式）：玩家把卡拖进触发器弹窗的卡槽，实时看到成功率变化，
> 再点执行。卡牌分为**人物卡**与**道具卡**两类，统一用 `CardData` 资源描述。

**数据模型 `CardData`（`script/card_data.gd`，`extends Resource`）**

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | JSON 顶层键（如 `"Falayee"` / `"多功能军刀"`） |
| `card_type` | `String` | `"character"` 或 `"item"` |
| `display_name` | `String` | 中文显示名 |
| `attrs` | `Dictionary` | `{int, app, str, bod}`（人物卡） |
| `bonus` | `Dictionary` | `{attr: +n}`（道具卡加成） |
| `tags` | `Array[String]` | 描述性标签（如 `神偷/潜行`） |
| `consumable` | `bool` | 道具卡是否分配时消耗 |
| `icon_path` | `String` | 贴图 `res://` 路径 |
| `description` | `String` | 说明文字 |

主要方法：`from_character()` / `from_item()`（工厂）、`has_tags(want, method)`、`get_bonus(attr)`、
`static weighted_x(attrs, weights)`（加权平均骰面，**与 CheckProcessor 单一来源**）。

**卡牌来源**
- `resoures/characters.json` → 人物卡
- `resoures/equipment.json` → 道具卡
- `CardRegistry` 在 `_ready` 时自动加载并缓存为 `CardData`；业务代码通过 `CardRegistry.get_card(id)` /
  `list_by_type(type)` / `list_by_tag(want)` / `list_all()` 查询，**不直接 new**。

**UI 组件**

| 组件 | 文件 | 说明 |
|------|------|------|
| `CardChip` | `components/card_chip.gd` | 可拖拽迷你卡（`_get_drag_data` 返回 `{"card", "origin"}`，`drop_target` 转发放置事件） |
| `CardArea` | `components/card_area.gd` | 玩家「手牌区」：展示已获卡、作为拖拽来源；同时也是放置目标（从卡槽取回）。`add_card`/`remove_card`/`clear`，信号 `card_clicked`/`changed`/`card_rejected`/`cards_returned` |
| `CardSlot` | `components/card_slot.gd` | 卡槽：拖放目标，从卡牌区拖卡进入；右击清空、执行前可拖出取回。`setup(name, accept, required, hint)`、`set_card`/`get_card`/`clear_card`，信号 `card_changed(slot_name, card)` |
| `CardDetailPopup` | `components/card_detail_popup.gd` | 卡牌详情弹窗（`open(card)` 静态调用，全代码构建遮罩 + Panel） |

> **拖放契约**：拖拽载荷统一为 `{"card": CardData, "origin": CardArea|CardSlot}`。
> - 来源 `CardArea`：放置成功后从手牌移除该卡（进入卡槽）。
> - 来源 `CardSlot`：放置成功后清空来源卡槽（卡槽间移动，不回手牌）。
> - 卡牌区默认每张卡只出现一次；带 `可堆叠` tag 的卡可重复添加（`CardArea.add_card` 拒绝重复）。

---

### 触发器系统

> 玩家点击地图上的**触发器**，把**卡片**放进**卡槽**确认执行。核心稀缺资源是 **时间（回合）**。
> 设计文档见 `design/核心玩法-触发器与回合系统.md`（schema v6）。

**三类交互**
1. **特殊交互（即时）**：点击地图上「特殊」spot → 直接弹对话，不进回合结算。
2. **普通触发器（槽位 + 文本）**：点击普通 spot → 弹窗（左 = 卡槽，右 = 文本），放卡后右侧文本实时变化；执行按钮分流到对话或延迟任务。
3. **延迟任务领取**：延迟行动在地图上留下待办，到回合后玩家主动回来领取结果与收获。

**数据 schema v6（`resoures/triggers/trigger.json`）**

- 顶层是 `{id: trigger}` 字典；`_` 开头的键被引擎忽略。
- 抽象层级：**回合(turn) = 时间档 + 一次插卡**；**phase = 回合内可选状态**（`require` 决定激活）；**display = 右侧文字 + 卡槽**（v5 起在 display 级）。
- 每个触发器可带 `repeatable`（省略 → `false`）：`true` = 用后仍可再次触发；`false` = 全流程完成后该点消耗（按钮禁用）。
- **四项可选字段**（省略取默认 / 写入覆盖）：
  1. `卡牌情况`：省略 → 引擎按 `len(slots)` 合成 `[[]]*N`（每槽无条件约束）；0 槽 → `[]`。
  2. `check.type`：省略 → `"compare"`（比大小，用 `performer` 槽占用者 attrs 加权算 `x` 直接比 `needs`，**不掷骰**）；写 `"dice"` 才随机 `1dx vs needs`。
  3. `suc` 分支 `effect`：省略 → 默认 suc1..sucN 自动获得**当前 phase 名** tag，suc0 自动获得 `fail_state` 值（默认 `"失败"`）tag；写入 `effect` 覆盖默认。
  4. `fail_state`（顶层，可选）：省略 → `"失败"`；用于语义化失败态（如 `"惊动"`）。
- `performer` 省略 → `"执行者"`。
- `require` 为 AND 语义（tag 全满足）。`ending`（phase 级）：进入即终止（走 `harvest` / `fail_harvest`）。

**核心 Autoload / 组件职责**

| 模块 | 职责 |
|------|------|
| `TriggerLoader` | `get_trigger(id)` / `is_repeatable(id)` / `expand(raw)`（默认值合成） / `validate(t)`（§5 校验 1–7）/ `select_display(phase, placed, world_tags)`（卡牌情况子集匹配 + require + 特异性）/ `find_next_turn(expanded, current_turn_id, world_tags)`（扫描后续 turn，选首个 require 满足的 phase） |
| `TriggerManager` | `apply_effect(effect)`（效果落地；`tags` 进流程字典，不直接写 `player_tags`）/ `begin_flow()` / `cancel_flow()` / `complete_flow(id)`（提交流程字典 tag 到 `player_tags` 并清空，返回 `repeatable`）/ `get_routing_tags()`（持久 tag + 本流程 tag）/ `open_trigger(id)`（便捷打开弹窗） |
| `TriggerPopup` | 浮动小窗（≈560×460，无全屏遮罩以免遮挡卡牌区）；`setup(trigger_id)` 加载；从卡牌区拖卡进槽 → 重选 display → 重建槽位（保留同名已放卡）→ 更新文本（`{槽位}` 替换 + `x/needs/verdict`）；执行 → 内联 compare → 应用 effect → 路由下一 turn/phase。信号 `flow_completed(trigger_id, repeatable, success)` / `cards_returned(cards)`；长按标题栏(>350ms)或拖动移动 |
| `TriggerSpot` | 地图交互点（`extends Button`）；`@export trigger_id` / `hover_hint`（默认 `"这是一个触发器"`，避开 Button 原生 `tooltip_text`）/ `label_text`；点击打开 `TriggerPopup`，`flow_completed` 回调中非 repeatable 则 `disabled = true` 消耗自身。信号 `popup_opened(popup)` |

> **Tag 隔离机制（重要）**：流程中获得的 tag 只存 `TriggerManager._flow_tags` 字典，
> **不直接写 `Player.player_tags`**——避免可重复触发器重复累加 tag，以及流程中途异常退出残留 tag。
> `complete_flow()` 时才把字典提交进 `player_tags` 并清空；中途关闭（`close`）则 `cancel_flow()` 丢弃。

> **卡牌归属**：卡从卡牌区拖入卡槽时即从手牌移除；全流程结束（`_finish_flow`）或关闭（`close`）时通过 `cards_returned` 信号归还手牌。

---

### 游戏流程

```
主菜单（loading.tscn）
  │
  ├─ 开始游戏 → 角色创建（selection.tscn）
  │                命名 + 分配属性 + 选择天赋
  │                ↓
  │             新手引导（guide.tscn）
  │                管家斯库奇引导 + 主线对话串
  │                ↓
  │             主城（main.tscn）
  │                ├─ 监狱（prison.tscn）
  │                │  ├─ 狱卒 — 贿赂与交涉
  │                │  ├─ 法拉叶 — 招募 / 虐待 / 恋爱线
  │                │  └─ 衫斯 — 解救协商
  │                └─ 更多场景开发中...
  │
  └─ 退出游戏
```

---

## 关键组件

| 组件 | 路径 | 说明 |
|------|------|------|
| `dialogue_ui` | `components/dialogue_ui.tscn` | 对话界面，支持打字机效果、分支选项、效果触发 |
| `character` | `components/character.tscn` | 地图中可交互 NPC 按钮，条件驱动对话匹配 |
| `character_panel` | `components/character_panel.tscn` | 角色详情弹窗（属性 / 标签 / 装备） |
| `main_ui` | `components/main_ui.tscn` | 主界面 HUD（金钱 / 贵族等级 / 天数 / 角色入口） |
| `confirmdialog` | `components/confirmdialog.tscn` | 通用确认弹窗 |
| `scene_spot` | `components/scene_spot.tscn` | 场景传送点 |
| `check_ui` | `components/check_ui.tscn` | 鉴定 UI |
| `card_chip` | `components/card_chip.tscn` | 可拖拽迷你卡（手牌 / 卡槽内通用） |
| `card_area` | `components/card_area.gd` | 玩家手牌区（拖拽来源 + 放置目标） |
| `card_slot` | `components/card_slot.gd` | 卡槽（拖放目标，执行前可取回） |
| `card_detail_popup` | `components/card_detail_popup.gd` | 卡牌详情弹窗 |
| `trigger_popup` | `components/trigger_popup.gd` | 触发器弹窗（左槽右文 + 即时 / 延迟标识 + 回合路由） |
| `trigger_spot` | `components/trigger_spot.gd` | 地图触发器交互点（悬浮提示 + 点击弹窗） |

---

## 添加新内容

### 添加角色
1. 将立绘放入 `art/`
2. 在 `resoures/characters.json` 添加角色条目
3. 在场景中实例化 `components/character.tscn`，设置 `charcter_name` 和 `config_path`
4. 在 `resoures/configs/` 创建 NPC 对话配置 JSON
5. 在 `resoures/plot/` 编写剧情 JSON

### 添加剧情对话
在 `resoures/plot/` 中按以下格式创建 JSON：

```json
{
  "剧情名": {
    "0th": {
      "name": "角色名",
      "text": "对话内容",
      "next": 1,
      "is_option": false,
      "effect": {
        "tags": ["标签名"],
        "money": {"value": 5, "operate": -1}
      }
    },
    "1th": {
      "name": "角色名",
      "text": "",
      "is_option": true,
      "options": [
        {
          "text": "选项文字",
          "next": 2,
          "effect": {},
          "condition": {
            "description": "条件不满足时的提示文字",
            "money": {"left": 1, "right": 9999999},
            "tags": ["需要的标签"]
          }
        }
      ]
    }
  }
}
```

然后通过 PlotImporter 调用：

```gdscript
PlotImporter.add_plot("res://resoures/plot/your_file.json", "剧情名")
```

### 添加场景
1. 在 `scene/` 创建新场景
2. 在 `resoures/spots.json` 添加传送点定义
3. 在地图 `.tscn` 中添加 `scene_spot` 实例并配置 `spot_name`

### 添加标签
在 `resoures/tags.json` 中添加条目，即可在条件判断和剧情效果中使用。

### 添加卡牌
**人物卡**：在 `resoures/characters.json` 添加条目（`name` / `int` / `app` / `str` / `bod` / `tags` / `image` / `description`）—— `CardRegistry` 启动自动加载为人物卡。
**道具卡**：在 `resoures/equipment.json` 添加条目（`bonus` 为 `{attr: +n}` 结构、`tags` / `consumable` / `icon` / `description`）。
> 启动后通过 `CardRegistry.get_card(id)` 取卡喂给 `CardArea`；无需改代码。

### 添加触发器
1. 在 `resoures/triggers/trigger.json` 顶层加一项 `{ "id": "...", "title": "...", "repeatable": false, "turns": {...} }`。
2. 按 v6 schema 写 `turns` / `phases` / `displays`（`slots` + `check` + `branches`）；四项可选字段省略即取默认。
3. 在场景放一个 `TriggerSpot`，设 `@export trigger_id` 为上面 id、`hover_hint`、`label_text`。
4. 运行前可用 `TriggerLoader.validate(TriggerLoader.expand(raw))` 检查配置（返回错误数组，空 = 通过）。
5. 完整示例见 `resoures/triggers/trigger.json`（已含 `盗窃贵族宅邸` 三阶段路由 + `晨练` 单阶段 harvest）。

---

## 当前角色

| 角色 | 立绘 | 说明 |
|------|------|------|
| Hero（主角） | `hero.png` | 出身贵族，玩家自定义属性 |
| 法拉叶（Falayee） | `falayee.png` | 身陷囹圄的侠义之士 |
| 衫斯（Sansi） | `sansi.png` | 被囚禁的学者 |
| 狱卒（Jailer） | `jailer.png` | 监狱看守 |
| 斯库奇（Sicourge） | `sicourge.png` | 管家，新手引导 NPC |
