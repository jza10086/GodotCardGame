# GP_cards（纸牌会客厅）Tabletop 风格牌桌架构（0.1.0）

本文档记录 `GP_cards` 首版的运行边界与接口契约，由架构师维护。玩法和键位见[使用说明](GP_cards_guide.md)，阶段验证见[开发记录](GP_cards_development.md)。

## 1. 产品目标与首版边界

- **核心定位**：面向 **1–8 人（以 8 人为设计基准）** 的Tabletop 风格联机 3D 纸牌沙盒，无硬编码玩法规则，允许玩家自由抓牌、摆桌、堆叠、洗牌、发牌与持手牌。
- **首版范围**：
  - 仅支持 **卡牌（Card）** 与 **牌堆（Deck）** 两类可互转实体。
  - **不需要观战者系统**（首版专注 1–8 名参赛者；若框架传入无本机参赛席位的观战状态，仅保持只读镜头不报错即可，不制作观战专用 UI）。
  - **物理与手感**：轻量运动学平面拖拽 + 高度叠层 + 平滑 Tween/插值动画（不使用刚体 `RigidBody3D`）。
  - **手牌系统**：支持将牌拖入手牌区；手牌挂载在玩家相机视口底部（3D 同世界浮空手牌），随视角转动始终跟随眼前；他人仅可见其桌边席位的背面手牌数表现。
  - **内置牌组预设**：**标准扑克（54 张：52 张常规 + 大小王）** 与 **UNO（108 张）**，均由数据驱动加载。
  - **结束与结算**：首版由房主点击「结束本局」触发 `unranked` 协议结算返回大厅；`CardTableRuleHook` 支持注入自定义规则和有排名的自动结算。
- **硬性规范约束**（继承根 `AGENTS.md`）：
  - 全程显式类型声明，**禁止使用 `:=`**。
  - **未经用户明确要求，不在 UI 上添加任何说明文字**（仅保留简洁动词按钮、数字与必要菜单项）。
  - 避开框架保留快捷键：`Esc`（共享菜单）、`Tab`（玩家/延迟面板）、`F3`（总排名）。
  - 严格遵守 `doc/api/networking.md`：禁止周期性广播全量世界快照，禁止向无权限客户端下发秘密牌面 ID。
  - 所有视觉与 HUD 以 `1920×1080` 为基准，HUD 位于 `CanvasLayer`（layer < 32，低于协议页 32 和框架 UI 64）。

---

## 2. 目录结构与模块边界

```text
games/minigame/GP_cards/
├── manifest.json                 # id=GP_cards, package_version=0.1.0, framework_version=0.6.0, 依赖 GP_default_protocol(~0.3.0) 与 GP_default_ui(~0.2.0)
├── definition.gd                 # 轻量目录声明：player_counts=[1..8]
├── adapters/
│   └── GP_default_protocol.gd    # standard 模式校验与结果透传
├── game.tscn / game.gd           # 正式小游戏入口：PartyAPI 生命周期、协议页、画质/音频目标、F6 本地预览兜底
├── table/
│   ├── table_stage.tscn / .gd    # 3D 正八角牌桌、8 席位锚点/名牌/背面手牌座、射线拾取与落点计算
│   ├── table_camera_rig.gd       # 座位初始机位、右键环绕、中键/WASD 平移、滚轮缩放、复位/俯视切换
│   └── remote_cursor_3d.tscn/.gd # 3D 玩家彩色指针与名字标记
├── cards/
│   ├── deck_catalog.gd           # 数据驱动牌组定义（poker / uno）与纹理缓存
│   ├── card_entity.tscn / .gd    # 3D 单张卡牌：圆角薄片、正反双面材质、悬停/选中高亮、运动学插值与翻面动画
│   ├── deck_entity.tscn / .gd    # 3D 牌堆：厚度随张数变化、顶牌正反显示、张数角标、双牌包切牌动画
│   └── floating_hand_3d.gd       # 挂载于相机底部的 3D 浮空手牌扇区：随视角移动、悬停弹出、拖出/拖入/重排
├── state/
│   ├── tabletop_state.gd         # 房主权威纯数据模型（卡牌、牌堆、手牌、抓锁、可见性脱敏投影）
│   ├── tabletop_net.gd           # PartyNet 网络边界（可靠离散动作/脱敏事件 + 25Hz 不可靠光标/持牌位姿）
│   ├── rules_script_hook.gd      # CardTableRuleHook，规则和结算脚本基类
│   └── sandbox_rule_hook.gd      # 默认沙盒规则
├── ui/
│   ├── round_pages.tscn          # 协议准备页与结算页（CanvasLayer 32）
│   ├── briefing.tscn
│   ├── settlement.tscn
│   ├── table_hud.tscn / .gd      # 极简贴边 HUD（房主牌组/重置/结束按钮 + 相机快捷按钮 + Alt 放大看牌浮层）
│   └── context_menu.tscn / .gd   # 卡牌与牌堆的右键菜单
├── assets/decks/
│   ├── poker/                    # 52 张 PNG + back.png + joker_small.svg + joker_big.svg
│   ├── uno/                      # 54 种 PNG + back.png
│   └── common/                   # question.svg（牌面资源查找的兜底图）
├── authoring/tools/              # 离线牌面生成脚本（不随运行包发布）
├── i18n/zh_Hans.po
└── doc/
```

---

## 3. 权威状态模型与真隐私契约 (`state/tabletop_state.gd`)

### 3.1 实体与守恒不变量
- 每张物理牌拥有唯一递增整数 `card_uid: int`（>= 1），不可变属性：`deck_type: StringName`（`&"poker"` / `&"uno"`）、`back_id: StringName`、以及牌面 `face_id: StringName`。房主保存完整映射，其他玩家只接收当前有权查看的牌面。
- 任意时刻，每张 `card_uid` 必须且只能归属以下三种容器之一：
  1. **桌面散牌（`TabletopState.CARD`）**：`{uid, pos: Vector2, yaw_deg: float, y_order: int, face_up: bool, locked_by: String, rev: int}`
  2. **桌面牌堆（`TabletopState.DECK`）**：与散牌共享位姿和锁字段，使用 `deck_uid` 及自底向顶排列的 `card_uids: Array[int]`。
     - 约束：牌堆张数必须 >= 2；当抽牌使牌堆仅剩 1 张时，原子拆解为 1 张散牌；抽空时移除牌堆。单牌或牌堆落入合堆半径时原子合并为牌堆（落入者叠在顶部）。
  3. **玩家手牌**：`hands[player_id] -> Array[int]`（有序 `card_uid` 列表）。

### 3.2 逐接收者牌面投影
房主提供唯一判定函数 `can_player_see_face(viewer_id: String, card_uid: int) -> bool`：
- 散牌：仅当 `face_up == true` 时可见。
- 牌堆：仅当 `face_up == true` 且 `card_uid` 为该堆顶牌（`card_uids[-1]`）时可见。
- 手牌：仅当 `viewer_id == owner_player_id` 时可见。
- 其余一切情况返回 `false`。

网络序列化（初始同步与每条增量事件）均按接收者 `viewer_id` 单独投影：
- 可见的牌面携带 `face_id`，隐藏的桌面牌面为 `""`。牌堆下发顶牌投影与张数；其他玩家手牌仅下发张数，没有手牌 UID 或牌面。
- 当一张原本可见的牌被翻回背面或移入他人手牌时，客户端必须立即清除该 `card_uid` 的本地 `face_id` 缓存。

---

## 4. 8 人牌桌、镜头与运动学交互

### 4.1 8 人正八角牌桌 (`table/table_stage.tscn`)
- 正八角桌台，内桌面边心距约 `12.0` 单位，木质外框 + 绒面桌布 + 8 席外缘彩色席位条与昵称标签。
- 1–8 人均匀分配到固定物理席位 `0..7`：`seat_idx = int(floor(8.0 * float(i) / float(n) + 0.5)) % 8`。
- 每个已入座席位在桌边展示一组紧凑的 3D 背面手牌模型（扇区最多 12 张，配实际总张数），让同桌 8 人直观看到彼此手牌余量。

### 4.2 自由相机 (`table/table_camera_rig.gd`)
- 初始自动朝向当前本地玩家的座位方向，略俯视桌心（约 -42°）。
- 交互：右键拖拽环绕、中键拖拽 / `WASD` 在桌界内平移、滚轮缩放、`Space` 复位本席视角、`V` 切换正俯视/本席视角。
- `api.input.input_blocked` 为 `true`（如框架 Esc 菜单打开）时完全忽略镜头与桌面操作输入。

### 4.3 运动学抓放、堆叠与相机贴底手牌
- **抓取逻辑**：
  - 左键拖拽散牌向房主请求抢占锁。收到确认后抬升，移动时以微倾和落点圈反馈。
  - 左键短拖牌堆 → 抽走顶牌（作为新散牌直接进入拖拽状态）。
  - 左键长按（>= 0.28s）后拖拽或 `Shift + 左键拖拽` 牌堆 → 抓起整叠牌堆。
- **操作快捷键**（作用于悬停或抓取中对象）：
  - `F`：翻面（单牌或整堆翻转并倒序）。
  - `Q` / `E`：逆/顺时针旋转 15°（按住 `Shift` 为 45°）。
  - `R`：洗牌（悬停牌堆时触发）。动画将牌堆分成两叠，错层交错后归位；单牌与牌堆翻面按当前旋转计算离桌高度。
  - `Alt`（按住）：若悬停对象为自己有权看见的正面牌，在 HUD 中央偏上、略偏右显示放大牌面，为下方手牌留白。
- **相机贴底 3D 浮空手牌 (`cards/floating_hand_3d.gd`)**：
  - 挂接在活动 `Camera3D` 下（同一 `World3D`），沿视口底边弧形/横向排布，随玩家转头与平移始终留在眼前底部。
  - 发牌、摸牌和收入手牌先由房主提交。本机根据旧投影的牌堆顶或散牌位置播放抛物线，飞入当前手牌槽或远端席位牌背扇区。批量发牌错峰起飞，后续操作可更新落点，重置移除仍在飞行的牌。
  - 在手牌上悬停 → 该卡平滑上浮放大（约 1.18x），左右拖拽可重排手牌顺序，向上拖离底部感应区 → 立即脱手进入 3D 桌面拖拽状态，松手即可落桌或合堆。
- **右键上下文菜单 (`ui/context_menu.tscn`)**：
  - 右键点选卡牌：`翻面`、`收入手牌`、`旋转 90°`。
  - 右键点选牌堆：`洗牌`、`翻面`、`抽 1 张`、`全员发 1 张`、`全员发 5 张`、`全员发 7 张`。

---

## 5. 网络通信协议 (`state/tabletop_net.gd`)

以 `PartyNet` 的同作用域消息传递离散提交和运动采样，遵循[框架联网契约](../../../../doc/api/networking.md)。

| 主题 (`StringName`) | 方向 & 模式 | 内容与职责 |
| --- | --- | --- |
| `&"cards/init"` | Host → 单 Peer（Reliable, ch 0） | 开局按 Peer 一次性下发脱敏快照。清空或切预设走带 `reset` 的增量。 |
| `&"cards/req"` | Client → Host（Reliable, ch 0） | 逻辑动作请求：`grab`、`release_lock`、`draw_top`、`drop_table`、`drop_merge`、`drop_hand`、`take_card`、`play_from_hand`、`reorder_hand`、`flip`、`rotate`、`shuffle`、`take_from_deck`、`deal`、`spawn_preset`、`clear_table`、`end_match`。请求身份取自 `sender.peer_id / player_ids`。 |
| `&"cards/evt"` | Host → 各 Peer（Reliable, ch 0） | 经权威校验后的离散状态变更事件（含递增 `rev: int`），逐目标 Peer 脱敏。拒绝回执只发请求者。 |
| `&"cards/cursor"` | Client → Host → Peers（Unreliable Ordered, ch 1, <=25Hz） | 指针位置超过移动阈值或持牌状态变化时发送：`{x, z, holding}`，驱动远端 3D 彩色光标平滑插值。 |
| `&"cards/drag"` | Holder → Host → Peers（Unreliable Ordered, ch 1, <=25Hz） | 仅在抓取移动中发送：`{rev, kind, uid, x, y, z, yaw}`，静止物体零流量。 |
| `&"cards/result"` | Host → All（Reliable, ch 0） | 最终协议结算结果（一次发布），各端展示协议结算页后由房主调用 `api.finish()`。 |

- **掉线处理**：监听 `api.player_disconnected`，若断线玩家持有抓取锁，房主立即释放该锁并将对象安全落回桌面并广播事件。

---

## 6. 规则脚本与自动结算 (`state/rules_script_hook.gd`)

```gdscript
class_name CardTableRuleHook
extends RefCounted

func setup(_state: TabletopState, _players: Array[Dictionary], _config: Dictionary) -> void:
	pass

func get_initial_preset_id() -> StringName:
	return &"poker"

func validate_action(_player_id: String, _action: Dictionary) -> Dictionary:
	return {"ok": true, "reason": ""}

func on_state_event(_event: Dictionary) -> void:
	pass

func can_host_end_manually() -> bool:
	return true

func evaluate_settlement(_players: Array[Dictionary], _request: Dictionary) -> Dictionary:
	# 返回 {should_finish: bool, result: Dictionary}
	return {"should_finish": false, "result": {}}

func build_manual_settlement(players: Array[Dictionary], request: Dictionary) -> Dictionary:
	# 默认返回符合 GP_default_protocol 的 unranked / withdrawn 结果
	...
```

- 开局前可给 `game.rule_hook_factory` 赋值 `MyRule.new`，每局由房主创建新规则实例。独立预览也通过同一工厂。默认 `SandboxRuleHook` 允许沙盒操作和手动未排名结算。
- 房主先用 `validate_action()` 判断动作，再交给权威模型。持有者始终可释放自己的锁。规则在成功提交后通过 `on_state_event()` 读取权威事件；通过 `can_host_end_manually()` 决定房主是否可手动结算。
- 初始状态发出后，以及每次成功发布增量后，房主调用 `evaluate_settlement()`。当 `should_finish` 为 `true`，房主用原版 `protocol.gd` 校验并发布结果。各端挂载协议结算页，准备屏障和倒计时结束后房主调用一次 `api.finish()`。

---

## 7. 里程碑

1. **阶段 1：清理与正式骨架接入**
   - 迁移可复用牌面至 `assets/decks/{poker,uno,common}`、脚本至 `authoring/tools/`，移除 `prototype/` 与旧占位入口，更新 `ASSET_LICENSES.md`、`manifest.json`、`definition.gd`、`adapters/GP_default_protocol.gd`、`i18n/zh_Hans.po`。
   - 搭建 `game.tscn`/`game.gd`（含 F6 本地单人预览与正式 PartyAPI 接入）、协议准备/结算页、`table_stage.tscn`（8 人正八角牌桌、8 席位标识与座位相机）。
2. **阶段 2：本地完整卡牌沙盒闭环**
   - 实现 `deck_catalog.gd`（扑克 54 + UNO 108）、`card_entity.tscn/.gd`、`deck_entity.tscn/.gd`、`floating_hand_3d.gd`、`tabletop_state.gd`、`context_menu.tscn/.gd`、`table_hud.tscn/.gd`、`rules_script_hook.gd`。
   - 在 F6 下完整跑通：拖拽/合堆/抽顶牌/整堆拖动/翻面/旋转/洗牌/发牌/拖入手牌/手牌悬停弹出与重排/拖出桌面/`Alt` 放大看牌/切换扑克与 UNO 预设。
3. **阶段 3：房主权威联机同步、3D 光标与真隐私**
   - 实现 `tabletop_net.gd` 与 `remote_cursor_3d.tscn/.gd`，将阶段 2 的所有交互切换为“本地请求 → 房主权威校验与脱敏广播 → 全端表现”。
   - 实现抢占锁、25Hz 持牌/光标平滑插值、他人桌边手牌背面计数、断线释放与房主结算提交。
4. **阶段 4：收尾、动画打磨与验证**
   - 完善双视角飞牌、翻面、切牌交错与 1920×1080 HUD，验证可替换的规则工厂和协议自动结算，升版至 `0.1.0`。
   - 在线编辑器通过 MCP 刷新并静态检查；运行状态、四端通信、扩展规则与有窗口视觉回归。
