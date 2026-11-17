class_name MatchArena
extends Node2D
## 卡片召唤自走棋 · 对局场景（第一版可玩切片）
##
## 职责边界：`MatchState` 是规则的唯一真相，这里只做三件事 ——
##   ① 把玩家点击/按钮翻译成 `apply_command()`（**绝不直接改状态字段**，
##      那是联机接缝能活下来的前提）；
##   ② 消费 `events` 把真 BOSS 棋子放进场，并用 `MatchLiveCombat` 把真血量读回规则层；
##   ③ 把 `time_scale()` 推给 `GameState.set_time_flow_base()`。
##
## 美术按用户要求先放：棋盘是运行时生成的贴图，卡面直接用图鉴原画，牌背是纯色块。

const PLAYER_TEAM := 0
const AI_TEAM := 1

## 玩家侧各阶段的思考上限。规则层对选牌/锁定/布阵**没有计时**（那些阶段没有
## "双方同时暗选"的语义），所以超时得由场景兜住 —— 否则鼠标一停整局就冻在那儿。
## 冒烟测试时可用 `st=3` 压短，否则无头跑一局要十几分钟
var player_stage_timeout := 45.0
const AI_ACT_DELAY := 0.55

## 手牌卡面的尺寸（宽 = 高 × 2/3，跟图鉴原画同比例，不拉伸）
const HAND_H := 172.0
const HAND_W := HAND_H * 2.0 / 3.0
## 竖排手牌列的宽度：两列卡面 + 列间距 + 面板内边距
const HAND_COL_W := HAND_W * 2.0 + 10.0 + 12.0
## 屏幕四周留的缝隙
const GUTTER := 10.0
## 顶部读数带高度（倒计时 + 阶段提示）。棋盘要让出这条带，文字才不是"压在卡上"。
const TOP_BAND := 96.0
## 底部操作带高度（回执 + 按钮）
const BOTTOM_BAND := 84.0
## 棋盘上下各再让出这一条：归属签从牌顶探出 13px、呼吸灯外圈比牌再大 13px，
## 顶行/底行不留余量就会被带子啃掉一口（1280×720 实机截图里最上一行的牌和棋子都是缺的）。
const BOARD_OVERHANG := 30.0
## 世界层叠顺序，一处定死（2026-11-04 用户报「场上的卡牌遮挡激活的 boss」）：
## 地面 < 空格呼吸框 < 卡片 < 棋子（含招式特效、飘字、血条，都在 Pieces 子树里一起抬）。
const Z_GROUND := -10
const Z_CELL_HINT := 0
const Z_TOKEN := 1
const Z_PIECE := 2
## 选卡聚光（2026-11-10 用户：等待激活时整个棋盘压暗，只有能点的牌亮着）。
## ⚠ 只压**棋盘底图**，不许盖到卡片上：第一版把遮罩放到绝对 z=8、再把可选牌
##   提到 z=9，实测（染红诊断）92% 的棋盘连可选牌一起被盖住 —— Godot 里子节点
##   的绝对 z 争不过父 _tokens 容器的分组，穿透不可靠。
##   改成：遮罩绝对 z=-5（在 ground -10 之上、_tokens 1 / _pieces 2 之下），
##   卡片自己按 Avail 压暗 / 提亮（见 MatchCardToken.set_avail），不依赖任何层级技巧。
const Z_PICK_DIM := -5
## 遮罩不透明度：压得住格子但还留得下轮廓
const PICK_DIM_ALPHA := 0.62

## 拖拽布阵（2026-11-04 用户：「定阵时可以拖动卡牌上场，拖动时卡牌半透明跟随鼠标」）：
## 按下后走够这么远才算"开始拖"，否则仍按原来的"点选"处理 ——
## 阈值太小会让普通点击莫名变成拖牌。
const DRAG_START_PX := 14.0
## 手里那张半透明牌的不透明度：要看得出是"我正拿着的牌"，又不能挡住底下的格子
const DRAG_ALPHA := 0.55
## 拖起来之后源牌压暗到多少（"牌被我拿起来了"的回执）
const DRAG_SOURCE_DIM := 0.42

var _drag_card := -1          ## 正在被拖的那张手牌（-1 = 没在拖）
var _drag_active := false
var _drag_btn: Button = null
var _drag_from := Vector2.ZERO
var _drag_ghost: Control = null
var _drag_cell := Vector2i(-1, -1)

var _state: MatchState
var _live := MatchLiveCombat.new()
var _pieces: Node2D
var _tokens: Node2D
var _cell_hint: MatchCellHint
## 等待激活时盖在整块棋盘上的暗纱；visible 由 _refresh_token_avail() 每帧同步
var _pick_dim: ColorRect = null
## 上一次算空格提示用的签名（阶段 + 是否已选手牌 + 该谁布阵）；变了才重枚举 36 格
var _hint_sig := -1
var _cam: Camera2D

var _pool: Array = []
## 本局是哪一关。由棋谱长卷写进 `GameState.match_context`；
## 直接进场景（探针 / 旧入口）没写时，退回「已通关的最高关 + 1」。
var _level := 1
var _quick := false      ## 本局走快速模式日程（票 003）。开局读一次，中途不再改。
var _picked: Array = []
var _sel_card := -1                 # 布阵/对战时选中的卡下标
var _lock_down := -1
var _lock_up := -1
var _stage_timer := 0.0
var _last_phase := -1                 # 用来识别"刚进新阶段"，见 _refresh_stage
var _ai_timer := 0.0
var _finished := false
## 快速模式「开战」的待落场棋子（见 `_drain` 末尾与 `_flush_spawn_queue`）。
## 规则层已经把这 12 只同时激活了，这里只摊开**节点**的创建。
var _spawn_queue: Array = []
## 落场队列没清空 ⇒ 阶段计时不走（`_spawn_hold` 在点「开战」那一刻先落下，
## 因为 tick 里 advance 排在 drain 前面，晚一帧设就多算一帧）。
var _spawn_hold := false
## 为预载多等的帧数（上限见 QUICK_SPAWN_WARM_CAP）
var _spawn_wait := 0
## 战报快照：card → { "boss_id": String, "team": int, "rows": {行名: 减免后掉血} }
## ⚠ 必须在棋子**离场那一刻**就抄一份：尸体淡出完就 free，台账跟着节点一起没了，
##   等结算再回头读会只剩活着的几只（表现就是"我明明看它打了很多，表上是 0"）。
var _report: Dictionary = {}
var _report_view: MatchReportView = null
## 一帧只花这么多微秒在「落场」上（帧预算 16.7ms 的一半）。
## 按**时间**摊而不是按只数摊：单只成本随机型与是否首战浮动很大（实测 35–80ms），
## 写死 2 只/帧在慢机器上照样一次干掉 150ms。取整只落完才检查，不做中途打断。
const QUICK_SPAWN_FRAME_BUDGET_US := 8000
## 等预载排空的上限帧数。超了就照旧落场 —— 宁可卡一帧，也不能因为一次加载失败
## 把「开战」永远按不下去。
const QUICK_SPAWN_WARM_CAP := 120
## 当前是不是处于时停（`get_tree().paused` + `BossBase.world_frozen` 的镜像）
var _frozen := false
var _tree: SceneTree

var _prompt: Label
var _timer_label: Label
## 左上「第 N 关」：关卡制之后玩家随时要知道自己在哪一局
var _level_label: Label
var _score_label: Label
## 右上次要读数：注额 / 可选张数
var _note_label: Label
var _notice: Label
var _top_band: PanelContainer
## 两条带里真正装东西的 VBox。阶段提示要在它们之间搬（快速档顶带只剩一行），
## 所以必须存下引用，不能靠 get_child(0) 猜顺序。
var _top_box: VBoxContainer
var _bottom_box: VBoxContainer
var _bottom_band: PanelContainer
var _hand: GridContainer
var _hand_scroll: ScrollContainer
var _hud_root: Control
var _buttons: Dictionary = {}
var _result: PanelContainer
var _kind_btn: Button = null
## 底部操作栏（卡面档 + 四颗阶段按钮）。
## ⚠ 所有子按钮都 visible=false 时它仍占 28px 高 —— 快速档底带只有 52px，
## 这 28px 会把整条带顶出屏幕下沿，所以这一档要连栏本身一起收掉。
var _action_bar: HBoxContainer = null
var _result_label: Label
var _result_deck: HBoxContainer


func _ready() -> void:
	# 对局里只有点牌/拖牌，不需要虚拟键
	VirtualPad.set_context("none")
	_tree = get_tree()
	# 时停的分层（2026-11-03 用户 B 案）：本场景**保持默认 INHERIT**，于是整棵
	# 对局树跟着 `get_tree().paused` 一起冻 —— 棋子、卡片、弹体、Tween、粒子、
	# 按 delta 走的 buff/debuff 一个都不落。只有"必须活着"的两支显式写 ALWAYS：
	# HUD（按钮与倒计时）和 Driver（帧驱动把手，见 MatchDriver）。
	# ⚠ 别改成"给场景根写 ALWAYS、再把棋子那支退回 PAUSABLE"：第一版就是这么写的，
	#   实测窗口里棋子照跑（点燃照跳、延迟伤害照落地），冻不住。现在这个写法只用到
	#   "显式 ALWAYS 的分支在暂停里照跑"这一条，最小复现见 tools/diag_pause_topology.tscn，
	#   行为由 probe_match_freeze 的 42 项盯着（含两条负面测试）。
	for raw in OS.get_cmdline_user_args():
		var t := String(raw)
		if t.begins_with("st="):
			player_stage_timeout = maxf(0.5, float(t.trim_prefix("st=")))
	_build_world()
	_build_hud()
	_build_driver()
	_start_match()


## 时停期间唯一还在跑的帧驱动：_process 与棋盘点击都搬到这里（父节点是场景根，
## 场景根必须是 INHERIT 才冻得住棋子，所以驱动只能待在叶子节点上写 ALWAYS）。
func _build_driver() -> void:
	var d := MatchDriver.new()
	d.name = "Driver"
	d.arena = self
	add_child(d)


# ===================== 搭建 =====================

func _build_world() -> void:
	var ground := Node2D.new()
	ground.name = "Ground"
	ground.z_index = Z_GROUND
	add_child(ground)
	var board := Sprite2D.new()
	board.texture = _make_board_texture()
	ground.add_child(board)

	_tokens = Node2D.new()
	_tokens.name = "Tokens"
	_tokens.z_index = Z_TOKEN
	add_child(_tokens)
	# 布阵可落格子的呼吸提示：画在牌底下，不挡卡面
	_cell_hint = MatchCellHint.new()
	_cell_hint.name = "CellHint"
	_cell_hint.z_index = Z_CELL_HINT
	add_child(_cell_hint)
	_pieces = Node2D.new()
	_pieces.name = "Pieces"
	# ⚠ 棋子必须在卡片**之上**：卡片激活之后只是"这格出过谁"的记号，
	#   而 BOSS 是玩家要盯着打的主体。原来 token 写死 z=2、Pieces 没设（默认 0），
	#   于是牌整个压在 BOSS 身上，用户报「场上的卡牌遮挡激活的 boss」（2026-11-04）。
	_pieces.z_index = Z_PIECE
	add_child(_pieces)

	# 选卡聚光：等待激活的时停窗口里把**棋盘底图**压暗（卡片各按自己的 Avail 状态亮/暗）。
	# ⚠ ColorRect 挂在 Node2D 树下，position/size 就是世界坐标（棋盘 Sprite 默认居中，
	#   所以范围是 -half..+half）；mouse_filter 必须 IGNORE，否则 36 格的点击全被吃掉。
	var half := Vector2(MatchDB.BOARD_COLS, MatchDB.BOARD_ROWS) * MatchDB.CELL_PX * 0.5
	_pick_dim = ColorRect.new()
	_pick_dim.name = "PickDim"
	_pick_dim.position = -half
	_pick_dim.size = half * 2.0
	_pick_dim.color = Color(0.008, 0.012, 0.026, PICK_DIM_ALPHA)
	_pick_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pick_dim.z_index = Z_PICK_DIM
	_pick_dim.z_as_relative = false
	_pick_dim.visible = false
	add_child(_pick_dim)

	_cam = Camera2D.new()
	# 相机是叶子节点，写 ALWAYS 不会传染给棋子；窗口里视口尺寸变了也要立刻重算取景，
	# 否则手机上转屏那一下棋盘会歪着停住。
	_cam.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_cam)
	_fit_camera()


## 一屏看全棋盘并**放到能放的最大**：自走棋读不到全局就没法决策。
## ⚠ 棋盘是 1560×1560 的正方形，横屏里由**高度**封顶 ——
##   `min(视口宽/棋盘宽, 视口高/棋盘高)` 就是"能放多大放多大、四边都不出屏"。
##   按宽度放会把上下两排推出屏幕（1280 宽对应 1280 高 > 720），所以只能取小值。
##   推论：右侧那条手牌列占掉的宽度**本来就用不上**，棋盘大小和它在不在没关系。
##
## 档位（2026-11-10 用户改口径，见 _camera_mode）：
##   常规档 = 选牌 / 锁定 / 布阵 / 结算 —— 让出完整上下带，棋盘贴左、右侧竖排手牌。
##   看盘档 = 普通模式**整个 BATTLE** —— 手牌列收掉、棋盘居中放大，
##     激活只靠点棋盘上的卡片。尺度本身就在说"现在该看盘"。
##   ⚠ 放大能拿到的只有"带子省出来的那点"（1280×720 下 z 从 0.308 到 0.364，
##   约 +18%），因为封顶的是高度不是宽度 —— 别指望它翻倍。
## 每帧按当前视口重算：`_ready` 时窗口尺寸可能还是项目默认值，
## 实机 1280×720 / 全屏 / 手机横屏会算出三个不同的缩放。
var _cam_vs := Vector2.ZERO
var _cam_vs_set := false
var _hand_side := true
var _cam_mode := CAM_NORMAL         ## 当前相机档位（CAM_NORMAL / CAM_WATCH / CAM_QUICK）
var _want_zoom := 1.0               ## 目标缩放（每帧插值过去）
var _want_pos := Vector2.ZERO
## 卡面按钮的宽：竖排时按右侧剩余空间铺满（宽屏下能到 250，比底部横条大一倍多），
## 退回横条时用 HAND_H 的固定比例。由 _layout_hand 算，_add_card_button 读。
var _card_w := HAND_W


## 战斗阶段「看盘」档的上下带。
## 2026-11-10 用户改口径：普通模式**布阵一结束就恒定放大**，后续玩家只在棋盘上
## 点卡片激活棋子，不再靠底部手牌列；所以放大档从"轮到对方才用"变成"整个 BATTLE 都用"。
## 比常规档窄，因为这时候没有手牌列要点，屏幕中央应该只剩棋盘。
const FOCUS_TOP_BAND := 58.0
const FOCUS_BOTTOM_BAND := 50.0
const FOCUS_OVERHANG := 22.0
## 相机插值的时间常数（秒）。用 exp 衰减而不是固定比例，缩放才和帧率无关。
const CAM_TAU := 0.12

## 三档相机。判据见 _camera_mode()：普通模式看「有没有进入对战」，
## 快速模式才看「轮到谁」。
const CAM_NORMAL := 0     ## 选牌 / 锁定 / 布阵 / 结算 ⇒ 让出完整上下带 + 右侧手牌列
const CAM_WATCH := 1      ## 普通模式整个 BATTLE（或快速模式对方轮）⇒ 手牌收掉、棋盘放大居中
const CAM_QUICK := 2      ## 快速模式整个终局 ⇒ 带子再压、提示搬到操作带、倒计时让位右侧

## 第三档（快速档）的屏幕预算。要 616px 就得 usable_y = 616 ⇒ 上下各留 52px，
## 而 52 = 带高 34 + overhang 18（归属签探出牌顶 13px、呼吸环再外 13px，
## 牌在 260 格里有 10.4px 内缩，所以 18 还留得下）。
## ⚠ 顶带压到 52px 之后**装不下两行**（读数行 40 + 阶段提示 24），
## 所以快速档必须把阶段提示搬到操作带 —— 那不是审美选择，是算术。
const QUICK_TOP_BAND := 34.0
const QUICK_BOTTOM_BAND := 34.0
const QUICK_OVERHANG := 18.0

func _fit_camera() -> void:
	# ⚠ 这里**不能**用 `get_viewport_rect()`：本节点是 Node2D，那个 API 返回的是
	#   「视口矩形在本节点局部坐标系里的大小」= 屏幕尺寸 ÷ 当前缩放。拿它去算缩放
	#   就是自我循环，实机表现为棋盘莫名又小一圈（第一版 0.27 算出来只有 0.21）。
	#   要屏幕真实像素，必须走 viewport.visible_rect。
	var vp := get_viewport()
	var vs := Vector2.ZERO if vp == null else vp.get_visible_rect().size
	if _cam == null or vs.x <= 0.0 or vs.y <= 0.0:
		return
	var want := _camera_mode()
	if not _cam_vs_set:
		# 第一帧直接落位，不许从 1.0 慢慢推过去（开局会看到棋盘自己长大）
		_cam_vs_set = true
		_cam_mode = want
		_resolve_camera(vs)
		_apply_camera_now()
	elif want != _cam_mode or vs != _cam_vs:
		_cam_mode = want
		_resolve_camera(vs)
	_cam_vs = vs


## 现在该用哪一档。
## · 快速档 = 快速模式的整个终局 —— 12 只已经全上场，玩家只能等结果。
## · 看盘档 = **普通模式的整个 BATTLE**（2026-11-10 用户定）+ 快速模式的对方轮。
##   ⚠ 原来按 `round_index % 2` 判：己方轮缩回 480 给手牌列、对方轮放到 568，
##     六轮来回跳 480↔568（面积差 39%），这就是用户报的「棋盘缩放有问题」。
##     现在激活改成**只点棋盘上的卡片**（手牌列收掉），不需要再给手牌让位，
##     于是普通模式 BATTLE 六轮一把恒定在放大档，不再有任何缩放跳变。
##   ⚠ 快速模式仍保持原判据：它的 BATTLE 己方轮还留着手牌列，别一起改。
## · 其余一律常规档（选牌 / 锁定 / 布阵 / 终局残局 / 结算）。
##   FINAL/OVER 在普通模式仍是常规档：结算面板要盖在棋盘上，棋盘不该突然变大。
func _camera_mode() -> int:
	if _state == null or _finished:
		return CAM_NORMAL
	if _quick and _state.phase == MatchState.Phase.FINAL:
		return CAM_QUICK
	if _state.phase == MatchState.Phase.BATTLE:
		# not _quick ⇒ 整个 BATTLE 恒定放大；快速模式只在对方轮放大
		if not _quick or not _state.is_own_round():
			return CAM_WATCH
	return CAM_NORMAL


## 三档各算一次落位，再按当前档取。手牌面板的尺寸**永远按常规档排**：
## 不然每换一次档 _card_w 就变一次，_layout_hand 会连着重建整排按钮。
func _resolve_camera(vs: Vector2) -> void:
	var board_px := Vector2(MatchDB.BOARD_COLS, MatchDB.BOARD_ROWS) * MatchDB.CELL_PX
	var normal := _camera_fit(vs, board_px, TOP_BAND, BOTTOM_BAND, BOARD_OVERHANG, true)
	var watch := _camera_fit(vs, board_px, FOCUS_TOP_BAND, FOCUS_BOTTOM_BAND, FOCUS_OVERHANG, false)
	var quick := _camera_fit(vs, board_px, QUICK_TOP_BAND, QUICK_BOTTOM_BAND, QUICK_OVERHANG, false)
	var board_w := float(normal["board_w"])
	# 右侧够不够放一列手牌（两列卡 + 边距）；不够就退回底部横条
	_hand_side = vs.x - board_w >= HAND_COL_W + GUTTER * 3.0
	_layout_hand(vs, board_w)
	var t: Dictionary = normal
	if _cam_mode == CAM_WATCH:
		t = watch
	elif _cam_mode == CAM_QUICK:
		t = quick
	_want_zoom = float(t["z"])
	_want_pos = t["pos"] as Vector2
	_apply_hand_visibility()
	_apply_band_layout()


## 立刻落位（第一帧和探针用），不等插值。
func _apply_camera_now() -> void:
	if _cam == null:
		return
	_cam.zoom = Vector2.ONE * _want_zoom
	_cam.position = _want_pos


## 两条 HUD 带的高度 + 阶段提示住哪条带 + 倒计时住正中还是右侧。
## 快速档把提示搬到操作带、倒计时让位到右侧，才换来了那 616px。
func _apply_band_layout() -> void:
	var qb := _cam_mode == CAM_QUICK
	if _top_band != null:
		# 顶带是 TOP_WIDE（anchor top=bottom=0）⇒ offset_bottom 就是绝对 y，可以直接写正数。
		_top_band.offset_bottom = (QUICK_TOP_BAND + QUICK_OVERHANG) if qb else TOP_BAND
	if _bottom_band != null:
		# ⚠ 底带是 BOTTOM_WIDE（anchor top=bottom=1）⇒ offset_top 是**相对锚点的负偏移**。
		#   写成 vs.y - h 会把整条带推到屏幕外面 636px，确认/锁牌/跳过全部点不到
		#   （probe_match_clicks 一次红 12 项，且"两条带占高正确"那条自己也算成 1356/720）。
		_bottom_band.offset_top = -((QUICK_BOTTOM_BAND + QUICK_OVERHANG) if qb else BOTTOM_BAND)
	# 快速档底带只有 52px，而 PanelContainer 会**撑到子节点的最小高度**：
	# 实测内容是 66px（阶段提示 24 + 操作栏 28 + 间距与内边距），
	# 于是整条带连按钮被顶出屏幕下沿 10px。
	# 等待期玩家没有任何操作可做 ⇒ 回执行、卡面档、整条操作栏一起收掉，
	# 让"现在该干什么"那行独占底带。
	# ⚠ 操作栏必须连**栏本身**一起收：里面按钮全 hidden 之后它仍占 28px。
	# ⚠ 「卡面」不在 _buttons 表里，阶段刷新的 hide-all 循环管不到它。
	if _notice != null:
		_notice.visible = not qb
	if _kind_btn != null:
		_kind_btn.visible = not qb
	if _action_bar != null:
		_action_bar.visible = not qb
	_move_prompt(qb)
	_place_timer(qb)


## 搬的是**同一个 Label**，不是复制一份：两处文案迟早会漂，
## 而"现在该干什么"只可能有一句话。
func _move_prompt(to_bottom: bool) -> void:
	if _prompt == null or _top_box == null or _bottom_box == null:
		return
	var target: Container = _bottom_box if to_bottom else _top_box
	if _prompt.get_parent() == target:
		return
	# ⚠ 必须 reparent，不能 target.add_child(_prompt)：节点已有父节点时
	#   add_child 直接报错，提示就永远搬不动（实机表现为顶带还是两行、棋盘没长大）。
	# 顶带里提示排在读数行之后；搬到底带就排最前（先说该干什么，再说刚发生了什么）
	_prompt.reparent(target, false)
	target.move_child(_prompt, 0 if to_bottom else target.get_child_count() - 1)


func _place_timer(right: bool) -> void:
	if _timer_label == null:
		return
	if right:
		# 右槽本来住「可选 N」，快速终局里那行是空的 ⇒ 让给倒计时。
		# -104 是和右上角 settings_ui（x=vs-90…vs-6）的既有契约，不能贴边。
		_timer_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		_timer_label.offset_left = -344.0
		_timer_label.offset_right = -104.0
		_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	else:
		_timer_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_timer_label.offset_left = -240.0
		_timer_label.offset_right = 240.0
		_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## 看盘档和快速档都必须把手牌列**收掉**（普通模式 BATTLE 期间一直收着，
## 玩家点棋盘上的卡片激活，不需要第二排按钮），不能淡出：CardFace 的图是 ShaderMaterial 画的
## （card_face.gd 里 `face.material = _still_mat`），那条 shader 不乘 COLOR，
## 父节点 modulate.a 压到 0.01 卡面照样全不透明 —— 实测截图里面板"淡不掉"。
## 相机本身有插值，面板硬切不会显得跳。
## 顺带撤掉 mouse_filter：看不见但仍 STOP 的面板会在棋盘右侧吃掉一整条点击。
func _apply_hand_visibility() -> void:
	if _hand_scroll == null:
		return
	var show := _cam_mode == CAM_NORMAL
	_hand_scroll.visible = show
	_hand_scroll.mouse_filter = Control.MOUSE_FILTER_PASS \
			if show else Control.MOUSE_FILTER_IGNORE


## 一种档位下棋盘能拿到的缩放与相机位置。
## ⚠ z 的分子必须是**整个屏幕宽**，不能先扣掉手牌列：绑死棋盘的是高度不是宽度
##   （1280×1040 下宽给 0.82、高只给 0.667），一扣就把棋盘缩成 0.64，
##   probe_match_entry 那条「棋盘已经放到不越界的上限」当场红。
## side=true 时棋盘左边缘钉在 GUTTER（给右侧让位），false 时水平居中。
func _camera_fit(vs: Vector2, board_px: Vector2, top: float, bottom: float,
		overhang: float, side: bool) -> Dictionary:
	var band_top := top + overhang
	var band_bot := maxf(vs.y - bottom - overhang, band_top + 160.0)
	var usable_y := band_bot - band_top
	var z := maxf(minf(vs.x / board_px.x, usable_y / board_px.y), 0.01)
	var y_off := band_top + usable_y * 0.5 - vs.y * 0.5
	var pos := Vector2(0.0, -y_off / z)
	if side:
		pos.x = (vs.x * 0.5 - GUTTER) / z - board_px.x * 0.5
	return {"z": z, "pos": pos, "board_w": board_px.x * z}


## 相机走插值，面板跟着档位硬切：棋盘长大的同时手牌列收掉。
func _tween_camera(delta: float) -> void:
	if _cam == null:
		return
	var k := 1.0 - exp(-maxf(delta, 0.0) / CAM_TAU)
	_cam.zoom = _cam.zoom.lerp(Vector2.ONE * _want_zoom, k)
	_cam.position = _cam.position.lerp(_want_pos, k)


## 手牌面板跟着相机一起排：它压在 CanvasLayer 上，offset 就是屏幕像素。
## 卡面尺寸也在这里定 —— 宽屏时棋盘右侧那条空白本来就有 500 多像素，
## 让几列卡面把它铺满，玩家才真的"一眼看清是谁"（横条布局下只能给到 115）。
func _layout_hand(vs: Vector2, board_w: float) -> void:
	if _hand_scroll == null:
		return
	var old_w := _card_w
	# 提示与回执现在各占一条通宽的带（顶带/底带），不再被手牌面板截断；
	# autowrap 必须有明确宽度才生效，所以两者一起在这里给。
	var info_w := vs.x - GUTTER * 2.0
	if _hand_side:
		var left := GUTTER + board_w + 12.0
		# 面板内边距 6×2 + 列间距
		var avail := vs.x - left - GUTTER - 12.0
		# 列数按"每列至少 150 宽"往上加：1280 屏下右侧有 500 多像素 → 三～四列，
		# 一屏能同时看到 8～9 张卡面。写死两列的话卡是大了，但选 6 张要翻好几屏。
		var cols := 2
		if avail >= 3.0 * 150.0 + 20.0:
			cols = 3
		if avail >= 4.0 * 150.0 + 30.0:
			cols = 4
		_hand.columns = cols
		_card_w = clampf((avail - float(cols - 1) * 10.0) / float(cols), 120.0, 250.0)
		_hand_scroll.offset_left = left
		_hand_scroll.offset_right = vs.x - GUTTER
		# 顶边让开顶部读数带（里面是倒计时与阶段提示，第一版让手牌压住了它）
		_hand_scroll.offset_top = TOP_BAND + 6.0
		_hand_scroll.offset_bottom = vs.y - BOTTOM_BAND - 4.0
	else:
		_hand.columns = 99
		_card_w = HAND_W
		_hand_scroll.offset_left = GUTTER
		_hand_scroll.offset_right = vs.x - GUTTER
		_hand_scroll.offset_top = vs.y - BOTTOM_BAND - (HAND_H + 16.0)
		_hand_scroll.offset_bottom = vs.y - BOTTOM_BAND - 6.0
	if _prompt != null:
		_prompt.custom_minimum_size = Vector2(info_w, 24)
	if _notice != null:
		_notice.custom_minimum_size = Vector2(info_w, 0)
	if absf(_card_w - old_w) > 0.5 and _state != null:
		_refresh_stage()   # 卡面尺寸变了，已经铺出来的按钮要按新尺寸重做


## 运行时生成棋盘贴图：底色 + 36 格描边。省掉 36 个节点，也省一张待生成的美术。
func _make_board_texture() -> ImageTexture:
	var w := int(MatchDB.BOARD_COLS * MatchDB.CELL_PX)
	var h := int(MatchDB.BOARD_ROWS * MatchDB.CELL_PX)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var base := Color(0.075, 0.082, 0.105)
	var line := Color(0.30, 0.36, 0.44, 0.85)
	var fill := Color(0.10, 0.11, 0.14)
	for y in h:
		for x in w:
			var c := base
			if int(x / MatchDB.CELL_PX) % 2 != int(y / MatchDB.CELL_PX) % 2:
				c = fill
			var mx := fmod(float(x), MatchDB.CELL_PX)
			var my := fmod(float(y), MatchDB.CELL_PX)
			if mx < 2.0 or my < 2.0:
				c = line
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## 两条 HUD 带的底板：暗底 + 一条金色细线分界。
## top=false 时亮边在下沿（顶带），true 时在上沿（底带）—— 线永远朝棋盘那一侧。
func _band_style(is_bottom: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.032, 0.028, 0.82)
	sb.border_color = Color(0.62, 0.50, 0.28, 0.55)
	sb.set_border_width_all(0)
	if is_bottom:
		sb.border_width_top = 1
	else:
		sb.border_width_bottom = 1
	sb.content_margin_left = GUTTER
	sb.content_margin_right = GUTTER
	sb.content_margin_top = 6.0 if not is_bottom else 4.0
	sb.content_margin_bottom = 4.0 if not is_bottom else 6.0
	return sb


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	# 时停期间 HUD 必须活着（选牌按钮、倒计时、回执都在这支下面），
	# 显式 ALWAYS 会顺带传给它全部子节点 —— 这正是我们要的，和 battle_wheel /
	# settings_ui 在暂停菜单里的做法同一套。
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var root := Control.new()
	root.name = "Root"
	layer.add_child(root)
	# ⚠ Control 直接挂在 CanvasLayer 下时，父矩形取的是 viewport.visible_rect，
	#   必须用 set_anchors_and_offsets_**preset**（本项目 boss_intro_card / battle_wheel 同一写法）。
	#   只 set_anchors_preset 不改 offsets → size 仍是 (0,0)。
	# 根节点这里**不能用 Container**：手牌面板的位置/尺寸要按棋盘实际占的屏幕宽度算
	# （见 _layout_hand），而 Container 会接管并覆写它每个子节点的矩形。
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# ⚠ 整屏浮层的 mouse_filter 只能是 PASS。实测真值表（tools/diag_gui_filter.tscn）：
	#   STOP（裸 Control 的默认值）→ 子按钮仍收得到，但**浮层空处底下的世界收不到**，
	#     于是棋盘格子全部点不动；原来用 VBoxContainer 之所以没事，是 Container 默认 PASS。
	#   IGNORE → 按钮也收得到、世界也收得到，可用；但语义上"这一层不存在"，
	#     以后想给浮层加悬停/拖拽就没了，所以统一用 PASS。
	#   （两条反直觉的纠正：父节点 STOP 不挡自己的孩子；IGNORE 也不屏蔽子树。）
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	_hud_root = root

	# ============ 顶部读数带（2026-11-04 用户：一堆文字堆在左上角，锁不住有效信息）============
	# 倒计时放正中间、最大字号；阶段提示紧跟其下一行；存活/注额压到两侧当次要读数。
	# ⚠ 棋盘必须让出这两条带（见 _fit_camera 的 usable_y），
	#   以前文字是直接压在棋盘与卡面上的 —— 那才是"读不出来"的真正原因。
	_top_band = PanelContainer.new()
	_top_band.name = "TopBand"
	_top_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_band.add_theme_stylebox_override("panel", _band_style(false))
	root.add_child(_top_band)
	_top_band.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top_band.offset_bottom = TOP_BAND

	var top := VBoxContainer.new()
	_top_box = top
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 2)
	_top_band.add_child(top)

	# 一行三块：左存活 / 中倒计时 / 右注额。用锚点分栏而不是 Container ——
	# Container 会把中间的计时挤成左对齐，"正中间上方"就没了。
	var row := Control.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(0, 40)
	top.add_child(row)

	# 左槽两行：上面「第 N 关」是标题级（我这局是谁的局），下面存活是数字级。
	# 用 VBox 而不是各自打锚点 —— 两行叠在 40px 的 row 里，锚点会算错行距。
	var left_col := VBoxContainer.new()
	left_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_theme_constant_override("separation", 0)
	row.add_child(left_col)
	left_col.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	left_col.offset_left = GUTTER
	left_col.offset_top = -20
	left_col.offset_bottom = 20

	_level_label = UIKit.label("", UIKit.F_TITLE, UIKit.C_TITLE)
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	left_col.add_child(_level_label)
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_score_label = UIKit.num_label("", UIKit.F_BODY, Color(0.78, 0.84, 0.94))
	_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	left_col.add_child(_score_label)

	_timer_label = Label.new()
	_timer_label.text = ""
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 30)
	_timer_label.add_theme_color_override("font_color", Color(0.99, 0.90, 0.62))
	_timer_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.92))
	_timer_label.add_theme_constant_override("shadow_offset_x", 3)
	_timer_label.add_theme_constant_override("shadow_offset_y", 3)
	row.add_child(_timer_label)
	_timer_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_timer_label.offset_left = -240
	_timer_label.offset_right = 240
	_timer_label.offset_top = -20
	_timer_label.offset_bottom = 20

	_note_label = UIKit.outlined_label("", UIKit.F_BODY, Color(0.86, 0.78, 0.56), 3)
	_note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_note_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_note_label)
	_note_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	# ⚠ 右边界必须让开右上角那颗「设置」（settings_ui 占 x=vs-90 … vs-6，
	#   与战斗 HUD 的 TimeLabel 同一套契约 -104）。写 -GUTTER 的实机结果是
	#   "注额 50（有效 50）　可选 4" 的后半截整个钻到按钮底下，玩家看不到可选数。
	_note_label.offset_right = -104.0
	_note_label.offset_left = -344.0
	_note_label.offset_top = -20
	_note_label.offset_bottom = 20

	# 阶段提示：这一行只说"现在该干什么"，次要数字一律不进来
	_prompt = Label.new()
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # 换行宽度见 _layout_hand
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 17)
	_prompt.add_theme_color_override("font_color", Color(0.96, 0.86, 0.55))
	top.add_child(_prompt)
	for lab in [_score_label, _timer_label, _note_label, _prompt]:
		(lab as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ============ 底部操作带：回执 + 按钮 ============
	_bottom_band = PanelContainer.new()
	_bottom_band.name = "BottomBand"
	_bottom_band.mouse_filter = Control.MOUSE_FILTER_PASS
	_bottom_band.add_theme_stylebox_override("panel", _band_style(true))
	root.add_child(_bottom_band)
	_bottom_band.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom_band.offset_top = -BOTTOM_BAND

	var bottom := VBoxContainer.new()
	bottom.name = "Bottom"
	_bottom_box = bottom
	bottom.mouse_filter = Control.MOUSE_FILTER_PASS
	bottom.add_theme_constant_override("separation", 4)
	_bottom_band.add_child(bottom)

	# 每次操作的一句话回执。没有它，"点了没反应"和"反应成功了"长得一模一样。
	_notice = Label.new()
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_theme_color_override("font_color", Color(0.99, 0.82, 0.42))
	_notice.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_notice.add_theme_constant_override("shadow_offset_x", 2)
	_notice.add_theme_constant_override("shadow_offset_y", 2)
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(_notice)

	var bar := HBoxContainer.new()
	bar.name = "Actions"
	_action_bar = bar
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 10)
	bottom.add_child(bar)
	# 卡面种类切换：默认「跟随卡包」= 你在收藏册里当封面展示的那一张（同一份 card_order）。
	# 放在这条操作栏里而不是每张牌上：布阵/选牌靠的就是点牌，牌上再挂一个按钮会误触。
	_kind_btn = Button.new()
	_kind_btn.name = "card_kind"
	_kind_btn.pressed.connect(_on_card_kind)
	bar.add_child(_kind_btn)
	_refresh_kind_label()
	for spec in [["confirm", "确认选牌"], ["lock_down", "锁反面"], ["lock_up", "锁正面"],
			["fight", "开战"], ["skip", "跳过（按策略代打）"]]:
		var b := Button.new()
		b.name = String(spec[0])
		b.text = String(spec[1])
		b.visible = false
		b.pressed.connect(_on_button.bind(String(spec[0])))
		bar.add_child(b)
		_buttons[String(spec[0])] = b

	# 手牌：宽屏时竖排在棋盘右侧（一格都不挡），放不下才退回底部横条。
	# 位置全部由 _layout_hand 按当前视口写 offset，所以这里不设 anchors 之外的东西。
	_hand_scroll = ScrollContainer.new()
	_hand_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_hand_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	# 底板半透明：万一退回到"压在棋盘上"的横条布局，也别把底下的格子糊成一团。
	var hand_bg := StyleBoxFlat.new()
	hand_bg.bg_color = Color(0.05, 0.045, 0.04, 0.62)
	hand_bg.border_color = Color(0.62, 0.50, 0.28, 0.35)
	hand_bg.border_width_top = 1
	hand_bg.set_content_margin_all(6.0)
	_hand_scroll.add_theme_stylebox_override("panel", hand_bg)
	# PASS 而不是 STOP：退回底部横条布局时，横条盖在最下排上面，
	# STOP 会让那 6 个格子点不动（真值表见上面 _build_hud 的注释）。
	_hand_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	# 手牌区里「按住拖动」是**出牌**（拖到棋盘落子），不是滚列表：
	# 不标这一句，ScrollDrag 会先一步把拖动吃掉（2026-11-13 probe_match_drag 8 条红）。
	_hand_scroll.set_meta("no_drag_scroll", true)
	root.add_child(_hand_scroll)
	# GridContainer 而不是 HBox：竖排时按列数铺开，横条时 columns 给很大值摊成一行，
	# 一套节点两种排法，不必按布局重建。
	_hand = GridContainer.new()
	_hand.columns = 2
	_hand.mouse_filter = Control.MOUSE_FILTER_PASS
	_hand.add_theme_constant_override("h_separation", 10)
	_hand.add_theme_constant_override("v_separation", 10)
	_hand_scroll.add_child(_hand)

	_result = PanelContainer.new()
	_result.visible = false
	layer.add_child(_result)
	# 默认主题的面板底板是半透明的 9-slice，压在棋盘上根本读不动字。
	# 结算页是全模式唯一必须看清文字的地方，这里直接换一块不透明底。
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.055, 0.05, 0.94)
	bg.border_color = Color(0.62, 0.50, 0.28, 0.9)
	bg.set_border_width_all(2)
	bg.set_content_margin_all(16.0)
	bg.corner_radius_top_left = 6
	bg.corner_radius_top_right = 6
	bg.corner_radius_bottom_left = 6
	bg.corner_radius_bottom_right = 6
	_result.add_theme_stylebox_override("panel", bg)
	# PanelContainer 只允许一个子节点，所以标题与按钮一起塞进 VBox
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 250)
	box.add_theme_constant_override("separation", 12)
	_result.add_child(box)
	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_label)
	# 结算页也要铺卡面：玩家复盘「我这局带的到底是谁、谁倒在哪」，
	# 只给一行「结束方式」等于没结算。
	_result_deck = HBoxContainer.new()
	_result_deck.alignment = BoxContainer.ALIGNMENT_CENTER
	_result_deck.add_theme_constant_override("separation", 6)
	box.add_child(_result_deck)
	var back := Button.new()
	back.text = "返回长卷"
	back.pressed.connect(_return_to_scroll)
	box.add_child(back)
	# 战报入口：结算页那一行只回答"算不算过"，玩家复盘时真正想问的是"谁打出来的"。
	var report := Button.new()
	report.text = "战报"
	report.pressed.connect(open_report)
	box.add_child(report)
	_center_result_panel()
	# 手牌面板是这一步才存在的，而 _build_world 里那次 _fit_camera 时它还是 null
	# （_layout_hand 直接早退了）→ 强制重算一次，否则卡面尺寸停在默认值。
	_cam_vs = Vector2.ZERO
	_fit_camera()


## 结算面板居中：**必须等子节点全挂完**再算。
## ⚠ 两次踩坑都在这行附近：
##   ① `set_anchors_preset` 只改锚点不改 offset → 矩形还是 (0,0,0,0)；
##   ② `set_anchors_and_offsets_preset(PRESET_CENTER)` 用**当时的** combined_minimum_size
##      算 offset，而那一刻 VBox 还没挂上去 → 最小尺寸 0 → 等于"左上角钉在屏幕中心"，
##      面板整块长到右下（实机截图看到的就是这个）。
## 所以显式按最小尺寸摆 offset，锚点保持 0.5 就与视口大小无关。
func _center_result_panel() -> void:
	_result.set_anchors_preset(Control.PRESET_CENTER)
	var ms := _result.get_combined_minimum_size()
	_result.offset_left = -ms.x * 0.5
	_result.offset_top = -ms.y * 0.5
	_result.offset_right = ms.x * 0.5
	_result.offset_bottom = ms.y * 0.5


# ===================== 开局 =====================

func _start_match() -> void:
	_level = _resolve_level()
	_quick = CharacterData.match_quick_mode
	# 重开一局（C 键）时上一局的落场队列必须清零，否则新局一上来就被计时闸按住
	_spawn_queue.clear()
	_spawn_hold = false
	_spawn_wait = 0
	_report.clear()
	_report_view = null
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var seed_v := rng.randi()
	_pool = _read_player_pool(seed_v)
	# 关卡制下没有注额了（ADR-0001）：进关不扣钱、输了不罚，只在首通发一笔固定 8 颗。
	# MatchDB.bet_matched / BET_MIN / BET_MAX 仍留在表里给以后的真人对局，这里不再取用。
	_state = MatchState.new()
	_state.combat = _live
	# 对手卡组 = 关卡号算出来的固定 6 张，与玩家解锁了什么无关（ADR-0002）。
	# 传 6 张而不是"池"：`decide_deck` 面对刚好 6 张的池会全取，
	# 于是 AI 提交的那副 == 长卷上预告的那副，玩家照着预告针对才成立。
	var ai_deck: Array = MatchLevelDeck.deck_for(_level)
	_state.start([_pool, ai_deck], seed_v, 0)
	if _quick:
		# 快速模式分叉点：对方当场建好摆好（票 003）。
		# ⚠ 布局只准来自 MatchQuickSetup.layout_for —— 长卷拓印画的就是同一份。
		# 本局种子**保持随机**：只有对方布局按关卡号固定。玩家卡池的补发不能跟着
		# 关卡号走，否则同一关每次发给玩家的 6 张可选牌也被钉死了（那不是本次要的）。
		_state.quick_open(AI_TEAM, ai_deck, MatchQuickSetup.layout_for(_level))
	else:
		_state.apply_command({"t": "pick", "team": AI_TEAM,
				"ids": MatchPolicy.decide_deck(_state.legal_pool(AI_TEAM))})
	_refresh_stage()


## 本局是哪一关：长卷写进来的优先，没写就按存档进度算。
func _resolve_level() -> int:
	var raw: Variant = GameState.match_context.get("level", null)
	if raw is int or raw is float or (raw is String and String(raw).is_valid_int()):
		return maxi(int(raw), 1)
	return maxi(CharacterData.match_level_cleared + 1, 1)


## 玩家卡池 = 已解锁的 BOSS 卡；不足 6 张由 fill_pool 随机补满。
## 补发要吃**本局种子**：原来写死 20261102，注释说"走对局种子"但其实是每局同一手，
## 而且联机时两端必须能由同一串命令复现出同样的池子。
func _read_player_pool(seed_v: int) -> Array:
	var unlocked: Array = []
	for id in MatchDB.CARD_POOL:
		if CodexDB.is_boss_unlocked(String(id)):
			unlocked.append(String(id))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	return MatchDB.fill_pool(unlocked, rng)


# ===================== 帧驱动 =====================

## 由 MatchDriver 调用（不叫 `_process`：场景根必须保持可暂停，见那个脚本的说明）。
func tick(delta: float) -> void:
	# 预载队列的取货点：没排队时只是一次空字典判断。
	SkinWarm.poll()
	_fit_camera()
	_tween_camera(delta)
	if _finished:
		# 结束后不再推进模拟，但结算面板必须还能弹出来：
		# `_finished` 与 `phase == OVER` 是同一帧在 `_drain()` 里落地的，
		# 早退如果挡在 _settle() 前面，面板就永远不显示（只剩一张"对局结束"的棋盘）。
		if _state != null and _state.phase == MatchState.Phase.OVER:
			_settle()
		return
	var awaiting := _awaiting_player()
	if awaiting:
		# 拖到一半不许被"到点代选"抢走：牌正在玩家手里，计时先停住。
		# （不拦的话常见结果是拖出去的那张已经被策略替玩家布到别处，松手落空。）
		if _drag_active:
			_stage_timer = maxf(_stage_timer, 1.0)
		else:
			_stage_timer -= delta
			if _stage_timer <= 0.0:
				_player_timeout()
	else:
		_stage_timer = player_stage_timeout

	if _state.phase == MatchState.Phase.BATTLE or _state.phase == MatchState.Phase.FINAL:
		# 开战的 12 只还在分批落地 ⇒ 阶段计时先不开始：
		# 否则最后两只一进场就发现自己白丢了 0.1 秒的终局窗口。
		if not _spawn_hold and _spawn_queue.is_empty():
			_state.advance(delta)
	GameState.set_time_flow_base(_state.time_scale())
	_drain()
	_flush_spawn_queue()
	_ai_tick(delta)
	# 可点呼吸灯 / 空格提示每帧都推一次。
	# ⚠ 必须放在 advance + drain + ai 之后：这三步都可能改 phase、round_index、
	#   fighting()，放前面就会亮着上一轮的牌等下一帧才改（实机看到的是
	#   「开打后金边还挂在己方牌上」「换轮到对方了灯还指着自己这边」）。
	#   set_avail / set_cells 内部按值去重，每帧调不是开销。
	_refresh_token_avail()
	# 空格提示要枚举 36 格、每帧分配一个数组，只在"该不该显示"真的变了时重算
	var mine := 2 if _state.deploy_turn == PLAYER_TEAM else 0
	var sig := (int(_state.phase) << 8) | (1 if _sel_card >= 0 else 0) | mine
	if sig != _hint_sig:
		_hint_sig = sig
		_refresh_cell_hint()
	# 放在 advance / drain / ai 之后：这几步都可能让「打不打」翻转，
	# 放前面就会晚一帧才冻上或松开（16ms，但选牌窗口恰好是逐帧看得见的地方）。
	_set_frozen(_state.time_stopped())
	_update_hud()
	if _state.phase == MatchState.Phase.OVER:
		_settle()


## 时停（2026-11-03 用户 B 案）：选牌 / 锁定 / 布阵 / 战斗窗口未开打的这段时间，
## 场面要**真的**停下来 —— 不是"看着像停了"，而是棋子不动、招式的延迟落地不生效、
## buff/debuff 的剩余时间也不走。两层闸门：
## ① `get_tree().paused`：一把冻住物理积分、Tween、粒子、动画，以及全部按 delta
##    计时的东西（招式状态机、冷却、`_tick_debuffs`）。冻的范围就是整棵对局场景 ——
##    场景根保持默认 INHERIT 才会被冻到；要活的只有 HUD 与 Driver 两支（MatchDriver）。
## ② `BossBase.world_frozen`：`get_tree().create_timer()` 的 `process_always`
##    默认 true，树冻了它照样触发回调（赫连霄的雷、火麟的陨、石犼的爪都靠它排
##    落地时刻，probe_match_freeze 实测到回调在窗口里确实跑了）—— 所以招式的
##    **后果**（掉血 / 挂 debuff / 飘字幕）在 BOSS 基类里再拦一道。
##    这条对 PvE 完全无感：秘境 / 塔 / 演武场从不拨这个开关。
## 必须幂等：tick() 每帧都调，两边都要能安全重入。
## ⚠ 用 `_tree` 而不是 `get_tree()`：`_exit_tree` 时节点已经出树，
##   `get_tree()` 返回 null，兜底解冻正好发生在那一刻。
func _set_frozen(v: bool) -> void:
	if _frozen == v:
		return
	_frozen = v
	BossBase.world_frozen = v
	if _tree != null:
		_tree.paused = v


## 兜底：任何离开对局的路（换场景 / queue_free）都不许把 `paused` 留给下一个场景 ——
## 主城若是在暂停态里加载，玩家连路都走不动。
func _exit_tree() -> void:
	_set_frozen(false)
	# 押住的招式图集在这里放开，显存还给系统（一张大表实测 100–200MB）。
	# ⚠ 只有棋局会点名预载，所以别处不受影响；放开之后下一场会重新解码一遍，
	#   但那是**工作线程**上的事，点开战不再卡主线程。
	_spawn_queue.clear()
	SkinWarm.clear()


## 当前是否在等玩家手动操作（等的时候规则层不会自己推进这些阶段）
func _awaiting_player() -> bool:
	match _state.phase:
		MatchState.Phase.PICK:
			return true
		MatchState.Phase.LOCK:
			return true
		MatchState.Phase.DEPLOY:
			return _state.deploy_turn == PLAYER_TEAM
		MatchState.Phase.BATTLE:
			return not _state.fighting() and int(_state.pending[PLAYER_TEAM]) == -1
	return false


## AI 侧：延迟一点再提交，否则三秒内整局就演完了，人根本看不清发生了什么。
func _ai_tick(delta: float) -> void:
	_ai_timer -= delta
	if _ai_timer > 0.0:
		return
	_ai_timer = AI_ACT_DELAY
	match _state.phase:
		MatchState.Phase.LOCK:
			var lk: Dictionary = MatchPolicy.decide_lock(_state, AI_TEAM)
			if not lk.is_empty():
				_state.apply_command({"t": "lock", "team": AI_TEAM,
						"down": int(lk["down"]), "up": int(lk["up"])})
		MatchState.Phase.DEPLOY:
			if _state.deploy_turn == AI_TEAM:
				var mv: Dictionary = MatchPolicy.decide_deploy(_state, AI_TEAM, _state.rng)
				if not mv.is_empty():
					_state.apply_command({"t": "deploy", "team": AI_TEAM,
							"card": int(mv["card"]), "cell": mv["cell"]})
		MatchState.Phase.BATTLE:
			if not _state.fighting() and int(_state.pending[AI_TEAM]) == -1:
				var pick := MatchPolicy.decide(_state, AI_TEAM)
				if pick >= 0:
					_state.apply_command({"t": "activate", "team": AI_TEAM, "card": pick})
		_:
			pass


## 玩家在某阶段超时 → 用同一份 MatchPolicy 替他提交（与 AI 完全同源）
func _player_timeout() -> void:
	_stage_timer = player_stage_timeout
	match _state.phase:
		MatchState.Phase.PICK:
			_picked = MatchPolicy.decide_deck(_state.legal_pool(PLAYER_TEAM))
			_state.apply_command({"t": "pick", "team": PLAYER_TEAM, "ids": _picked})
			_refresh_stage()
		MatchState.Phase.LOCK:
			var lk: Dictionary = MatchPolicy.decide_lock(_state, PLAYER_TEAM)
			if not lk.is_empty():
				_state.apply_command({"t": "lock", "team": PLAYER_TEAM,
						"down": int(lk["down"]), "up": int(lk["up"])})
			_refresh_stage()
		MatchState.Phase.DEPLOY:
			# 快速模式没有交替回合，一次点击只落一子的话，玩家连点六下、
			# 每下都只是手里少一张 —— 这就是本项目报过最多的一类「点了没反应」。
			# 「按策略代打」在这里的语义必须是一次把 6 张摆完。
			if _quick:
				var placed := 0
				while true:
					var qmv: Dictionary = MatchPolicy.decide_deploy(_state, PLAYER_TEAM, _state.rng)
					if qmv.is_empty():
						break
					_state.apply_command({"t": "deploy", "team": PLAYER_TEAM,
							"card": int(qmv["card"]), "cell": qmv["cell"]})
					placed += 1
				_set_notice("已替你摆好 %d 张，点「开战」全员上场" % placed
						if placed > 0 else "六张都在盘上了，点「开战」全员上场")
				_refresh_stage()
				return
			var mv: Dictionary = MatchPolicy.decide_deploy(_state, PLAYER_TEAM, _state.rng)
			if not mv.is_empty():
				_state.apply_command({"t": "deploy", "team": PLAYER_TEAM,
						"card": int(mv["card"]), "cell": mv["cell"]})
		MatchState.Phase.BATTLE:
			var pick := MatchPolicy.decide(_state, PLAYER_TEAM)
			if pick >= 0:
				_state.apply_command({"t": "activate", "team": PLAYER_TEAM, "card": pick})


# ===================== 事件 → 真棋子 =====================

func _drain() -> void:
	var spawns: Array = []
	for e in _state.drain_events():
		var t := String(e.get("t", ""))
		match t:
			"spawn":
				if _quick:
					spawns.append(e)
				else:
					_spawn_piece(int(e["card"]), String(e["boss_id"]), int(e["team"]), e["cell"])
			"deploy":
				_add_token(int(e["card"]), e["cell"], bool(e["reveal"]))
				# 每次落子都重铺手牌：`legal_deploy` 少了一张、该谁落子也换了。
				# 原来只有玩家**下一次点牌**时（_select_hand_card → _refresh_stage）才重建，
				# 于是拖完一张之后手上会短暂出现"刚拖走的那张还在"，
				# 而 AI 落完轮到玩家时没人重建 → 直接面对一张空手牌（2026-11-04 拖拽实测抓到）。
				_refresh_hand_if_idle()
				# 落子就是"这只一定会上场"的最早信号 ⇒ 趁还有空档把它的场景与招式表
				# 排进线程预载。开战时那一帧卡的不是建模，是主线程解码招式图集
				# （石犼 455ms / 刀客 190ms），实测见 tools/measure_threaded_warm.gd。
				MatchAdapter.warm_boss(String(_state.cards[int(e["card"])]["boss_id"]))
			"phase":
				print("[对局] 阶段 → ", String(e.get("phase", "")), "  棋子数=", _pieces.get_child_count())
				# 选择的清理交给 _refresh_stage（它才知道"阶段真的换了"），
				# 这里再清一次等于把玩家刚点中的牌抹掉 —— phase 事件比 st.phase 晚到一帧
				_refresh_stage()
			"round":
				_refresh_stage()
			"end":
				_finished = true
	# 快速模式的「开战」一次点出 12 只：同帧建完实测 645ms（预算 16.7ms），
	# 所以在这里收下、交给 `_flush_spawn_queue` 摊帧。
	# ⚠ 事件顺序是"对方 6 只在前"，直接排队等于送对面半秒先手 ⇒ 必须两边交替入队。
	if spawns.is_empty():
		return
	if spawns.size() == 1:
		_spawn_piece(int(spawns[0]["card"]), String(spawns[0]["boss_id"]),
				int(spawns[0]["team"]), spawns[0]["cell"])
		return
	_spawn_queue.append_array(_interleaved(spawns))
	_spawn_hold = true


## 把同一批 spawn 事件按队伍交错：玩家、对方、玩家、对方……
## 分批落场这件事本身已经给了先手窗口，交错至少让它落在**双方各自**头上，
## 而不是整边都晚。
func _interleaved(evs: Array) -> Array:
	var mine: Array = []
	var theirs: Array = []
	for e in evs:
		if int(e["team"]) == PLAYER_TEAM:
			mine.append(e)
		else:
			theirs.append(e)
	var out: Array = []
	var i := 0
	while i < mine.size() or i < theirs.size():
		if i < mine.size():
			out.append(mine[i])
		if i < theirs.size():
			out.append(theirs[i])
		i += 1
	return out


## 每帧落 QUICK_SPAWN_PER_FRAME 只。落完之前终局计时不走（见 tick 里那道闸）。
## ⚠ 预载还在路上时**先不落**：`SkinWarm.resource()` 撞上在途的请求会同步等它，
##   实测「摆完立刻点开战」那一帧因此涨到 1610ms —— 比优化前还糟。
##   让落场等一手工作线程，主线程这段时间照常出帧，玩家看到的是棋子陆续站起来。
func _flush_spawn_queue() -> void:
	if _spawn_queue.is_empty():
		return
	if SkinWarm.is_busy() and _spawn_wait < QUICK_SPAWN_WARM_CAP:
		_spawn_wait += 1
		return
	_spawn_wait = 0
	var t0 := Time.get_ticks_usec()
	while not _spawn_queue.is_empty():
		var e: Dictionary = _spawn_queue.pop_front()
		_spawn_piece(int(e["card"]), String(e["boss_id"]), int(e["team"]), e["cell"])
		# 一只落完才检查：中途打断没有意义（节点要么建好要么不建）
		if Time.get_ticks_usec() - t0 > QUICK_SPAWN_FRAME_BUDGET_US:
			break
	if _spawn_queue.is_empty():
		_spawn_hold = false


func _spawn_piece(card: int, boss_id: String, team: int, cell: Vector2i) -> void:
	# 每只棋子一个 host：它自己 `get_parent().add_child(...)` 出来的召唤物
	# 会落进同一个 host，于是能在这里认出"这是谁召的"并借到颜色。
	# host 没有位移与缩放，所以棋子内部所有世界坐标照旧成立。
	var host := Node2D.new()
	host.name = "PieceHost%d" % card
	host.set_meta("team", team)
	_pieces.add_child(host)
	host.child_entered_tree.connect(_on_piece_child_entered)
	host.child_exiting_tree.connect(_on_piece_child_exited)
	var p := MatchAdapter.spawn_piece(host, boss_id, team, cell)
	if p == null:
		host.queue_free()
		return
	_live.pieces[card] = p
	# 战报：给这只棋子立一户，并把"它是几号牌"钉在它自己身上 ——
	# 死的时候 child_exiting_tree 只给节点，不查卡片就不知道该往哪一户回写。
	_report[card] = {"boss_id": boss_id, "team": team, "rows": {}, "taken": {}}
	p.set_meta("report_card", card)
	_snapshot_report(card, p)
	# ⚠ 收账的**主**时机是死亡信号，不是离场信号：
	#   BossBase 的死亡只做缩小渐隐、不 free 节点，节点后来是被谁释放的并不一定
	#   经过 host 的 child_exiting_tree（实测三张非核心卡的离场快照压根没触发，
	#   整本账随节点一起没了 —— 战报上那一侧全是 0）。
	#   `died` 在血量归零那一刻发，此刻账一定齐。
	if p.has_signal("died"):
		p.died.connect(_on_piece_died_report.bind(card, p))
	# 棋子压过卡片：出生之后那块牌只是"已出"的记号。
	# 暗牌在这一步才翻面 —— 玩家第一次看见这张牌是谁，就是它上场的那一刻。
	# ⚠ 整张牌一起压暗（set_dim），不要只压卡面：队伍描边是这块唯一的归属信息。
	var tok := _tokens.get_node_or_null("Token%d" % card) as MatchCardToken
	if tok != null:
		if not tok.is_revealed():
			tok.reveal_now()
		var tw := tok.create_tween()
		tw.tween_interval(0.20)
		tw.tween_method(tok.set_dim, 1.0, 0.4, 0.5)


## 棋子死后（淡出动画放完自行 free）host 就空了，不收掉的话
## `_pieces.get_child_count()` 会一直把空壳算成"场上还有棋子"。
func _on_piece_child_exited(node: Node) -> void:
	# 战报：棋子本体离场那一刻是最后一次还能读它台账的机会
	if node is BossBase and (node as BossBase).team_id >= 0 and node.has_meta("report_card"):
		_snapshot_report(int(node.get_meta("report_card")), node)
	# exiting 时该节点仍在树上，所以要数"除了它还剩几个"
	var host: Node = node.get_parent()
	if host == null or not is_instance_valid(host):
		return
	var left := 0
	for ch in host.get_children():
		if ch != node:
			left += 1
	if left == 0:
		host.queue_free()


## 召唤物 / 分身没有队伍号，血条会退回场景默认红 → 按 host 的队伍借一个显示色。
## 只写 `display_team`，不写 `team_id`：后者会连带改变索敌与挨打规则。
func _on_piece_child_entered(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var parent: Node = node.get_parent()
	# ① 棋子本体里"没有队伍号"的那一类（法宝召来的友军）借 host 的号把头顶尖条染色。
	#    带 team_id 的棋子本体在这里直接跳过。
	if parent != null and node is BossBase:
		var b := node as BossBase
		if b.team_id < 0 and b.display_team < 0:
			var t := int(parent.get_meta("team", -1))
			if t >= 0:
				b.display_team = t
				b._tint_head_hp_bar()
	# ② 战报台账认人：host 子树里任何**不是棋子本体**的东西（刀痕 / 场地 / 弹体 / 镜像 / 叠纸）
	#    都属于那只棋子。在这里统一盖一个 meta，就不必去每个卫星脚本里补字段 ——
	#    也正好绕开并行会话正在改的 fold_field.gd / domain_boss_04_c.gd。
	_stamp_report_owner(node)


## 给卫星实体盖归属戳。已经自己声明过 report_owner 的不覆盖（镜像那种显式挂主人的在前）。
func _stamp_report_owner(node: Node) -> void:
	if node is BossBase and (node as BossBase).team_id >= 0:
		return
	if node.get("report_owner") != null or node.has_meta("report_owner"):
		return
	var up: Node = node.get_parent()
	var host: Node = null
	while up != null:
		if String(up.name).begins_with("PieceHost"):
			host = up
			break
		up = up.get_parent()
	if host == null:
		return
	var piece := _host_piece_of(host)
	if piece != null:
		node.set_meta("report_owner", piece)


## host 里那只有队伍号的棋子 = 这一格的主人。棋子死后 host 会空掉，所以这里只认还在的。
func _host_piece_of(host: Node) -> BossBase:
	for ch in host.get_children():
		if ch is BossBase and (ch as BossBase).team_id >= 0:
			return ch as BossBase
	return null


func _add_token(card: int, cell: Vector2i, reveal: bool) -> void:
	var c: Dictionary = _state.cards[card]
	var tok := MatchCardToken.new()
	tok.name = "Token%d" % card
	tok.position = MatchDB.cell_to_pos(cell)
	# 层叠由 _tokens 容器统一给（见 Z_TOKEN）：写死在这里会把牌又抬到棋子前面
	_tokens.add_child(tok)
	tok.setup(String(c["boss_id"]), _boss_name(String(c["boss_id"])), reveal,
			int(c["team"]))
	tok.card_index = card
	# 新落的一张要立刻带上正确的可点状态，不能等下一帧（会闪一下无灯的金框）
	_refresh_token_avail()


## 暗牌被激活的那一刻才翻面：牌翻过来、棋子同时从这一格站起来。
func _reveal_token(card: int) -> void:
	var tok := _tokens.get_node_or_null("Token%d" % card) as MatchCardToken
	if tok != null:
		tok.reveal_now()


# ===================== 输入 =====================

## 由 MatchDriver 转发（同理：场景根在时停里收不到输入）。
func on_unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var world := get_canvas_transform().affine_inverse() * mb.global_position
	var cell := _cell_of(world)
	if not MatchDB.in_board(cell):
		return
	match _state.phase:
		MatchState.Phase.DEPLOY:
			if _state.deploy_turn != PLAYER_TEAM or _sel_card < 0:
				return
			if _state.legal_deploy(PLAYER_TEAM).has(_sel_card):
				_state.apply_command({"t": "deploy", "team": PLAYER_TEAM,
						"card": _sel_card, "cell": cell})
				_sel_card = -1
		MatchState.Phase.BATTLE:
			if _state.fighting():
				return
			for i in _state.cards.size():
				if _state.cards[i]["cell"] == cell and _state.legal_activate(PLAYER_TEAM).has(i):
					_state.apply_command({"t": "activate", "team": PLAYER_TEAM, "card": i})
					return


func _cell_of(world: Vector2) -> Vector2i:
	var half := Vector2(MatchDB.BOARD_COLS, MatchDB.BOARD_ROWS) * MatchDB.CELL_PX * 0.5
	var g := (world + half) / MatchDB.CELL_PX
	return Vector2i(int(floorf(g.x)), int(floorf(g.y)))


## 屏幕坐标 → 棋盘格子（拖动时反复算，单独抽出来）
func _cell_at_screen(screen: Vector2) -> Vector2i:
	return _cell_of(get_canvas_transform().affine_inverse() * screen)


## 这张牌现在能不能拖：只在"布阵 + 轮到我 + 它还在合法手里"时成立
func _drag_ok(card: int) -> bool:
	return _state != null and _state.phase == MatchState.Phase.DEPLOY \
			and _state.deploy_turn == PLAYER_TEAM \
			and _state.legal_deploy(PLAYER_TEAM).has(card)


## 手牌按钮的拖拽通道。按下→走够阈值→手里出现半透明牌→松开在空格上就落子。
## ⚠ 按钮在按下后**捕获鼠标**，所以松开在棋盘上时这个回调照样收到，
##   而 Button 的 `pressed` 不会触发（松开点不在按钮里）——
##   于是"拖到棋盘=落子"与"点一下=选中"天然不会打架，不用额外吞事件。
func _on_hand_drag(event: InputEvent, btn: Button, card: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_drag_card = card if _drag_ok(card) else -1
			_drag_active = false
			_drag_btn = btn
			_drag_from = mb.global_position
		else:
			if _drag_active and _drag_card == card:
				_end_drag(mb.global_position)
			_drag_card = -1
			_drag_active = false
	elif event is InputEventMouseMotion and _drag_card == card:
		var mm := event as InputEventMouseMotion
		if not mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_drag_card = -1
			_drag_active = false
			return
		if not _drag_active:
			if _drag_from.distance_to(mm.global_position) < DRAG_START_PX:
				return
			if not _drag_ok(card):
				_drag_card = -1
				return
			_begin_drag(btn, card)
			_drag_active = true
		if _drag_active:
			_move_drag(mm.global_position)


## 这个落点现在算不算合法空格 —— 直接问规则层，不读提示节点那份缓存：
## 提示是按签名延后一帧才重算的，拖动的头一帧可能还是空的，
## 照它判"能不能落"就会闪一下"松手也落不了"的灰牌。
func _drop_ok(card: int, c: Vector2i) -> bool:
	if not _drag_ok(card) or not MatchDB.in_board(c):
		return false
	return not _state.occupied_cells().has(c)


func _begin_drag(btn: Button, card: int) -> void:
	# 拖起来就等于"选中了这张"：空格提示（_refresh_cell_hint 要看 _sel_card）
	# 与原来的点选路径共用同一套高亮，不另开一条状态
	_sel_card = card
	var bid := String(_state.cards[card]["boss_id"])
	var sz := Vector2(_card_w, _card_w * 1.5)
	_drag_ghost = _make_card_ghost(bid, sz)
	_hud_root.add_child(_drag_ghost)
	# 源牌压暗：牌"被拿起来了"，手上那张先别抢视线
	btn.modulate = Color(1, 1, 1, DRAG_SOURCE_DIM)
	_set_notice("%s：拖到发亮的空格松手" % _boss_name(bid))


func _move_drag(screen: Vector2) -> void:
	if _drag_ghost == null:
		return
	_drag_ghost.position = screen - _drag_ghost.size * 0.5
	# 轻微倾斜：拿着的牌不该和摆着的牌一个姿态，动态感从这里来
	_drag_ghost.rotation_degrees = clampf((screen.x - _drag_from.x) * 0.02, -7.0, 7.0)
	var c := _cell_at_screen(screen)
	if c != _drag_cell:
		_drag_cell = c
		if _cell_hint != null:
			_cell_hint.set_hover(c)
		# 落在合法空格上 → 手里的牌提亮；落在别处 → 压暗，一眼知道松手会不会落子
		_drag_ghost.modulate = Color(1, 1, 1, DRAG_ALPHA) if _drop_ok(_drag_card, c) \
				else Color(0.72, 0.74, 0.78, DRAG_ALPHA * 0.72)


func _end_drag(screen: Vector2) -> void:
	var card := _drag_card
	# 先清标记：下面会 _refresh_stage() 重铺手牌，旧按钮 queue_free，
	# 留着 _drag_active 会让"落子事件到 → 重铺手牌"这条链把自己挡住。
	_drag_active = false
	_drag_card = -1
	var bid := String(_state.cards[card]["boss_id"])
	var nm := _boss_name(bid)
	var c := _cell_at_screen(screen)
	var ok := _drop_ok(card, c)
	_end_ghost()
	if ok:
		_state.apply_command({"t": "deploy", "team": PLAYER_TEAM, "card": card, "cell": c})
		_sel_card = -1
		# 必须重建手牌：不然刚拖出去的那张还留在手上
		_refresh_stage()
		_set_notice("%s → 已落到第 %d 行第 %d 列" % [nm, c.y + 1, c.x + 1])
	else:
		# 松在棋盘外 / 已占的格子上：取消落子，但牌留在选中态，点格子还能落
		_refresh_stage()
		_set_notice("%s：松在棋盘外，取消落子（牌已选中，点发亮的空格也能落）" % nm)


## 收掉手里那张牌 + 恢复源牌 + 清目标格高亮
func _end_ghost() -> void:
	if _drag_ghost != null:
		_drag_ghost.queue_free()
		_drag_ghost = null
	if _drag_btn != null and is_instance_valid(_drag_btn):
		_drag_btn.modulate = Color(1, 1, 1, 1)
	_drag_btn = null
	_drag_cell = Vector2i(-1, -1)
	if _cell_hint != null:
		_cell_hint.set_hover(Vector2i(-1, -1))


## 落子事件到了就重铺手牌，但**正在拖的时候不许铺**：
## 重建会把旧按钮 queue_free，而拖拽的事件链就挂在那个按钮上（按下后按钮捕获鼠标），
## 按钮一没，移动/松开全部丢失，屏幕上会留一张永远跟不掉的半透明牌。
## 松手时 _end_drag 自己会补一次重建，所以这里跳过不会漏。
func _refresh_hand_if_idle() -> void:
	if _drag_active:
		return
	_refresh_stage()


## 拖动中跟着鼠标的那张牌：与手牌同一套卡面（框 / 圆角 / 名字），只是半透明。
## 子树全 IGNORE —— 它绝不能吃掉自己的松开事件。
func _make_card_ghost(boss_id: String, sz: Vector2) -> Control:
	var g := Control.new()
	g.name = "DragGhost"
	g.size = sz
	g.pivot_offset = sz * 0.5
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.modulate = Color(1, 1, 1, DRAG_ALPHA)
	var accent := MatchCard.accent(boss_id)
	var style := MatchCard.player_style(boss_id, CharacterData.match_card_kind)
	var face := CardFace.new()
	if not style.is_empty() and face.configure(style, sz, accent, false):
		face.set_input_enabled(false)
		face.set_idle_motion(false)
		g.add_child(face)
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_ignore_subtree(face)
	else:
		var tex := TextureRect.new()
		tex.texture = _fallback_portrait(boss_id)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.clip_contents = true
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.add_child(tex)
		tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.02, 0.035, 0.66)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	shade.offset_top = -sz.y * 0.155
	var nm := UIKit.outlined_label(_boss_name(boss_id), UIKit.F_SECTION, accent, 3)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_child(nm)
	nm.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	nm.offset_top = -sz.y * 0.135
	nm.offset_bottom = -sz.y * 0.055
	return g


func _on_button(which: String) -> void:
	match which:
		"confirm":
			if _picked.size() == MatchDB.DECK_SIZE:
				_state.apply_command({"t": "pick", "team": PLAYER_TEAM, "ids": _picked})
				_refresh_stage()
		"lock_down":
			_apply_lock("down")
		"lock_up":
			_apply_lock("up")
		"skip":
			_player_timeout()
		"fight":
			# 先把计时闸落下，再让规则层激活 12 只。
			# ⚠ 顺序反了就漏一帧：tick 里 `advance()` 在 `drain()` **之前**，
			#   等 drain 把 spawn 事件收进队列时，这一帧的 delta 已经记进终局计时了
			#   （实测探针抓到 0.1457s —— 上一帧正好在做摆牌重铺，delta 特别大）。
			_spawn_hold = true
			_state.quick_start_battle()


## 快速模式那颗「开战」：只在快速模式的布阵阶段出现，摆满 6 张才可点。
## 普通模式永远隐藏 —— 那边是"12 张摆完自动开打"，本来就没有这颗钮。
## 「还差 N 张」从 deployed_count() 现算，不写死：写死过一次之后禁用态就是空文案。
func _sync_fight_btn() -> void:
	var b: Button = _buttons.get("fight")
	if b == null:
		return
	var in_quick_deploy := _quick and _state != null \
			and _state.phase == MatchState.Phase.DEPLOY
	b.visible = in_quick_deploy
	if not in_quick_deploy:
		return
	var left := MatchDB.DECK_SIZE * MatchDB.TEAM_COUNT - _state.deployed_count()
	b.disabled = left > 0
	b.text = "开战" if left <= 0 else "开战（还差 %d 张）" % left


func _try_submit_lock() -> void:
	if _lock_down < 0 or _lock_up < 0 or _lock_down == _lock_up:
		return
	_state.apply_command({"t": "lock", "team": PLAYER_TEAM, "down": _lock_down, "up": _lock_up})
	_refresh_stage()


# ===================== HUD =====================

func _refresh_stage() -> void:
	# ⚠ 两件事都只在**真的换了阶段**时做：
	#   ① 重新上倒计时。`_stage_timer` 初值是 0.0，而 _process 里「等待玩家」分支先减表、
	#      `_drain` 的换阶段在其后 —— 于是开局第一帧就判定超时，
	#      选牌阶段被 MatchPolicy 代打了，玩家根本没得挑（截图才暴露）。
	#   ② 丢掉当前选中的牌。以前这里是**每次重建手牌都无脑清一次**，
	#      而 `phase` 事件比 `st.phase` 晚到一帧（同一帧里 _process 先跑完减表、
	#      才由 _drain 处理换阶段事件）→ 玩家布阵时刚点中的那张牌，
	#      会被紧随其后的这次刷新抹掉，表现就是"布阵时选不了牌"（2026-11-03 用户报，
	#      probe_match_clicks 抓到；无头跑不出来，必须窗口化）。
	var changed := _state != null and _state.phase != _last_phase
	if changed:
		_last_phase = _state.phase
		_stage_timer = player_stage_timeout
		_sel_card = -1
		_set_notice("")   # 上一阶段的操作回执到新阶段没有意义
	for k in _buttons.keys():
		(_buttons[k] as Button).visible = false
	for c in _hand.get_children():
		c.queue_free()
	match _state.phase:
		MatchState.Phase.PICK:
			_buttons["confirm"].visible = true
			# 开局从**整个卡包**里挑 6 张：只显示卡面不够，
			# 还得让玩家看清"这张我选没选、选到第几个"，否则挑完就糊了。
			for id in _state.legal_pool(PLAYER_TEAM):
				var bid := String(id)
				var n := _picked.find(bid)
				_add_card_button(bid, "已选 %d" % (n + 1) if n >= 0 else "", n >= 0,
						_toggle_pick.bind(bid))
			_set_buttons()
		MatchState.Phase.LOCK:
			_buttons["lock_down"].visible = true
			_buttons["lock_up"].visible = true
			for i in _state.team_cards(PLAYER_TEAM):
				var bid2 := String(_state.cards[i]["boss_id"])
				var badge := "你锁反面" if i == _lock_down else ("你锁正面" if i == _lock_up else "待随机")
				# ⚠ 必须走 _select_hand_card（改完立刻重建），不能只写字段：
				#   高亮与徽章都是**建按钮那一刻**算出来的，不重建就是"点了没反应"。
				_add_card_button(bid2, badge, _sel_card == i, _select_hand_card.bind(i, ""))
			_set_buttons()
		MatchState.Phase.DEPLOY:
			_buttons["skip"].visible = true
			for i in _state.legal_deploy(PLAYER_TEAM):
				var bid3 := String(_state.cards[i]["boss_id"])
				# 落子前就要看得见正反面归属，否则布完盘不知道自己藏了哪几张
				var face := "反" if bool(_state.cards[i]["face_up"]) == false else "正"
				_add_card_button(bid3, face, _sel_card == i,
						_select_hand_card.bind(i, "%s：点棋盘上的空格落子" % _boss_name(bid3)),
						true, i)
			_set_buttons()
		MatchState.Phase.BATTLE:
			_buttons["skip"].visible = true
			# 2026-11-10 用户定：普通模式整个 BATTLE 手牌列都收着，
			# 激活**只走棋盘上点卡片**（on_unhandled_input 的 BATTLE 分支）。
			# ⚠ 这里不要再铺一排看不见的 CardFace：手牌列 hidden 之后它们既不显示
			#   也不收输入，每轮换轮却要重建一堆贴图，纯白烧。
			#   skip 仍在底带操作栏里，代打入口没丢。
			_set_buttons()
		_:
			_set_buttons()
	_sync_fight_btn()
	_refresh_token_avail()
	_hint_sig = -1        # 换阶段/换手牌后强制重算一次空格提示
	_refresh_cell_hint()


## 卡面种类按钮的文案：把当前档位直接写在按钮上，按下去才知道切到哪一档了
func _refresh_kind_label() -> void:
	if _kind_btn == null:
		return
	_kind_btn.text = "卡面：%s" % MatchCard.kind_label(CharacterData.match_card_kind)


## 循环切档 → 清缓存 → 手牌与棋盘上的牌全部按新档重画。
## ⚠ MatchCard 的两张缓存（style / rounded_art）都是按「boss_id|种类」和「贴图路径」记的，
##   不清就会一直端出上一档的图。
func _on_card_kind() -> void:
	var ids: Array = []
	for k in MatchCard.KINDS:
		ids.append(String(k["id"]))
	var i := ids.find(CharacterData.match_card_kind)
	CharacterData.match_card_kind = ids[(i + 1) % ids.size()]
	MatchCard.clear_cache()
	_refresh_kind_label()
	_refresh_stage()
	for t in _tokens.get_children():
		if t is MatchCardToken:
			(t as MatchCardToken).restyle()
	_set_notice("卡面切成「%s」—— 这一档没解锁的牌自动用你卡包的封面顶替"
			% MatchCard.kind_label(CharacterData.match_card_kind))


## 把规则层的"现在能点哪张"推到棋盘上（2026-11-04 用户：激活阶段一眼看不出可选牌）。
##
## 三条通道各管一件事，互不混用：
##   归属 = 队伍色卡套边 + 牌顶归属签的**形状**（己方朝上、对方朝下）；
##   可点 = 牌外套一圈暖金呼吸灯；
##   不可点 = 整张压灰（降饱和 + 灰纱）。
## 第四条（2026-11-10 用户）：等待激活时棋盘底图压暗 + 不可选的牌自己压暗，
##   只有可选的牌保持原样并加一圈暖金呼吸灯 —— 把上面三通道的对比度整体拉高，
##   时停那一眼就知道"现在要选一张"。
## ⚠ 可点集合直接取 `legal_activate(PLAYER_TEAM)` —— 轮到对方时它给的就是对方的牌
##   （规则层允许玩家替对方决定进场时机），所以这里**不按队伍猜**，一律问规则层。
func _refresh_token_avail() -> void:
	if _state == null:
		return
	var gating := _state.phase == MatchState.Phase.BATTLE and not _state.fighting()
	var ready: Array = []
	if gating:
		for i in _state.legal_activate(PLAYER_TEAM):
			ready.append(int(i))
	# ⚠ 只有"真的有牌可选"才压暗：玩家已经提交、等 AI 那半秒 ready 会是空的，
	#   此时压暗就成了「整盘全黑一个亮点也没有」，比不压还糟。
	if _pick_dim != null:
		_pick_dim.visible = gating and not ready.is_empty()
	for t in _tokens.get_children():
		if not (t is MatchCardToken):
			continue
		var tk := t as MatchCardToken
		if not gating:
			tk.set_avail(MatchCardToken.Avail.NEUTRAL)
		elif ready.has(tk.card_index):
			tk.set_avail(MatchCardToken.Avail.READY)
		else:
			tk.set_avail(MatchCardToken.Avail.LOCKED)


## 布阵：选中手牌之后才标出可落子的空格（没选就铺 36 个框等于噪声）
func _refresh_cell_hint() -> void:
	if _state == null or _cell_hint == null:
		return
	var spots: Array = []
	if _state.phase == MatchState.Phase.DEPLOY and _state.deploy_turn == PLAYER_TEAM \
			and _sel_card >= 0:
		# 直接用规则层那一份：`occupied_cells()` 看的是 deployed，
		# 自己按 spawned 数会漏掉"已落子但还没出生"的格子 → 提示与真实判定不一致
		spots = MatchState.free_cells(_state.occupied_cells())
	_cell_hint.set_cells(spots)


func _set_buttons() -> void:
	if _state.phase != MatchState.Phase.LOCK:
		return
	# 按完一次就把两个锁键的状态重写：填过的变成"已锁 ✓"并禁用，
	# 玩家才知道还差哪一格、哪一格已经不能动了。
	var need_down := _lock_down < 0
	var need_up := _lock_up < 0
	var bd: Button = _buttons["lock_down"]
	var bu: Button = _buttons["lock_up"]
	bd.disabled = not need_down
	bu.disabled = not need_up
	bd.text = "锁反面（还差 1 张）" if need_down else "反面已锁 ✓"
	bu.text = "锁正面（还差 1 张）" if need_up else "正面已锁 ✓"


func _activate_card(i: int) -> void:
	_state.apply_command({"t": "activate", "team": PLAYER_TEAM, "card": i})
	_set_notice("已激活 %s" % _boss_name(String(_state.cards[i]["boss_id"])))


## 点手牌：改选择 + 立刻重建 + 给一句话回执。
## 以前只 `_sel_card = i` 就完事，而高亮是建按钮时算的 → 看着像没点上
## （2026-11-03 用户报「锁正反面时没有反馈」，布阵选牌其实同病）。
## ⚠ 回执要在 _refresh_stage **之后**写：换阶段时它会清一次回执。
func _select_hand_card(i: int, hint: String) -> void:
	_sel_card = i
	_refresh_stage()
	_set_notice(hint if hint != "" else "已选 %s" % _boss_name(String(_state.cards[i]["boss_id"])))


func _set_notice(t: String) -> void:
	if _notice != null:
		_notice.text = t


## 按锁：先校验再落槽，任何一条不满足都要说清楚为什么没动，
## 否则玩家只会觉得"按钮坏了"。
func _apply_lock(which: String) -> void:
	if _sel_card < 0:
		_set_notice("先点一张牌，再按「%s」" % ("锁反面" if which == "down" else "锁正面"))
		return
	var idx := _sel_card
	var nm := _boss_name(String(_state.cards[idx]["boss_id"]))
	var msg := ""
	if which == "down":
		if _lock_up == idx:
			_set_notice("%s 已经锁成正面了，换一张" % nm)
			return
		_lock_down = idx
		msg = "%s → 已锁反面（藏起来，轮到系统翻）" % nm
	else:
		if _lock_down == idx:
			_set_notice("%s 已经锁成反面了，换一张" % nm)
			return
		_lock_up = idx
		msg = "%s → 已锁正面（开局就亮在棋盘上）" % nm
	_try_submit_lock()
	_refresh_stage()
	_set_notice(msg)   # 必须在刷新之后：换阶段会清回执


func _toggle_pick(boss_id: String) -> void:
	if boss_id in _picked:
		_picked.erase(boss_id)
	elif _picked.size() < MatchDB.DECK_SIZE:
		_picked.append(boss_id)
	_refresh_stage()


## 手牌卡面按钮：**挂 CardFace**（与卡包封面同一支渲染器），名字与状态角标画在牌里。
## 以前这里是一张 TextureRect 平铺原画 + 牌外一行 Label，所以看着"像一张图"而不是"一张卡"。
## ⚠ 子节点一律 MOUSE_FILTER_IGNORE —— CardFace / TextureRect / Label 默认会吃掉点击，
##   那样按钮就只剩边缘一圈能点，看着能选实际点不动（probe_match_clicks 就是抓这个的）。
func _add_card_button(boss_id: String, badge: String, selected: bool, cb: Callable,
		ready: bool = false, drag_card: int = -1) -> void:
	# 尺寸跟着 _layout_hand 算出来的 _card_w 走：宽屏竖排时卡面能到 250 宽，
	# 底部横条时退回 115。写死 HAND_H 的话放大布局就白做了。
	var w := _card_w
	var h := _card_w * 1.5
	var b := Button.new()
	b.flat = true
	b.custom_minimum_size = Vector2(w, h)
	b.tooltip_text = "%s\n%s" % [_boss_name(boss_id), boss_id]
	b.pressed.connect(cb)
	# 布阵阶段才接拖拽（drag_card >= 0）：按下→走够阈值→手里出现半透明牌。
	# ⚠ 这条连接与上面给视差用的 `_forward_hover` **互不影响**，
	#   也必须在按钮入树之后再挂一次才能收到事件 —— gui_input 信号谁都能接，
	#   但只有按钮自己收到按下时才会往外发。
	if drag_card >= 0:
		b.gui_input.connect(_on_hand_drag.bind(b, drag_card))
	_hand.add_child(b)

	var stack := Control.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 同上：按钮不是 Container，子节点不会自动铺满。只设 anchors 不改 offsets
	# 会得到一张 0×0 的列，卡面看着"设置了"其实一个像素都没画。
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE)
	b.add_child(stack)

	var accent := MatchCard.accent(boss_id)
	var style := MatchCard.player_style(boss_id, CharacterData.match_card_kind)
	var face := CardFace.new()
	var built := not style.is_empty() and face.configure(style, Vector2(w, h), accent, false)
	if built:
		# 待机流彩只给**选中那一张**：一屏 16 张全动会掉帧（卡包封面同一处置），
		# 而"点中的那张在发光"正好是最直接的操作回执。
		face.set_idle_motion(selected)
		# 输入全部交给按钮：卡面子树若设成 PASS，按下/松开**不会**传回父按钮
		# （实测牌直接点不动），所以这里让卡面彻底不接输入，再由按钮把 motion 转进来。
		face.set_input_enabled(false)
		stack.add_child(face)
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_ignore_subtree(face)
		b.gui_input.connect(_forward_hover.bind(face))
	else:
		# 没有任何可用卡面（图鉴条目缺图）才退回裸贴图 —— 宁可没框，也不能没牌。
		var tex := TextureRect.new()
		tex.texture = _fallback_portrait(boss_id)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.clip_contents = true
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(tex)
		tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 底部压暗带 + 名字：卡包里名字就在牌上，这里必须一致，否则"牌面"和"图"还是两回事
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.02, 0.035, 0.66)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	shade.offset_top = -h * 0.155
	var nm := UIKit.outlined_label(_boss_name(boss_id), UIKit.F_SECTION, accent, 3)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(nm)
	nm.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	nm.offset_top = -h * 0.135
	nm.offset_bottom = -h * 0.055
	if badge != "":
		# 角标自己画：UIKit.chip 的底板是 accent 14% 透明，压在亮卡面（火麟、气君）上
		# 文字直接化没了。徽章必须落在**任何**卡面上都读得清，所以给一层不透明暗底。
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cs := StyleBoxFlat.new()
		cs.bg_color = Color(0.02, 0.025, 0.04, 0.88)
		cs.border_color = Color(accent.r, accent.g, accent.b, 0.72)
		cs.set_border_width_all(1)
		cs.set_corner_radius_all(9)
		cs.set_content_margin_all(3.0)
		chip.add_theme_stylebox_override("panel", cs)
		var bl := UIKit.outlined_label(badge, UIKit.F_SMALL, accent, 2)
		bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(bl)
		stack.add_child(chip)
		chip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		# 宽度跟着字数走：布阵的角标只有一个「正 / 反」，撑成 44% 卡宽会像一条横幅
		var cw := minf(w * 0.46, 15.0 * float(badge.length()) + 16.0)
		chip.offset_left = -cw - 8.0
		chip.offset_top = 8.0
		chip.offset_right = -8.0
		chip.offset_bottom = 32.0

	# 选中态：提亮 + 圆角金框（跟着卡片圆角，不再是方方正正一圈）。
	# ⚠ 只靠 modulate 提亮不够 —— 卡面本来就有大片高光，1.35 倍几乎看不出来，
	#   玩家照样报"点了没反应"。框是画在一张透明 Panel 上的（flat Button 不画自己的
	#   stylebox），必须等按钮入树后再设锚点。
	if selected:
		b.modulate = Color(1.16, 1.13, 1.03)
		var frame := Panel.new()
		frame.name = "SelectFrame"
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(frame)
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var fs := StyleBoxFlat.new()
		fs.bg_color = Color(0, 0, 0, 0)
		fs.border_color = Color(0.98, 0.82, 0.38)
		fs.set_border_width_all(3)
		fs.set_corner_radius_all(int(MatchCard.corner_radius(w)) + 2)
		frame.add_theme_stylebox_override("panel", fs)
	elif ready:
		# 可点但还没选中的牌：一圈极淡的呼吸金边，和棋盘上"能点的牌在呼吸"同一套语言。
		# ⚠ 只在**可选集合是小子集**的阶段给（布阵 / 激活）。选牌阶段整池 16 张全部可选，
		#   全呼吸等于没有信息，反而更吵。
		var glow := Panel.new()
		glow.name = "ReadyGlow"
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(glow)
		glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var gs := StyleBoxFlat.new()
		gs.bg_color = Color(0, 0, 0, 0)
		gs.border_color = Color(1.0, 0.84, 0.42, 0.55)
		gs.set_border_width_all(2)
		gs.set_corner_radius_all(int(MatchCard.corner_radius(w)) + 2)
		glow.add_theme_stylebox_override("panel", gs)
		var tw := glow.create_tween().set_loops()
		tw.tween_property(glow, "modulate:a", 0.32, 0.85).set_trans(Tween.TRANS_SINE)
		tw.tween_property(glow, "modulate:a", 1.0, 0.85).set_trans(Tween.TRANS_SINE)


## CardFace 内部会挂 HoloCardView / TextureRect，它们各自的 mouse_filter 不为 IGNORE。
## 按钮要自己吃到点击，所以整棵子树压一遍 —— 逐个控件关不现实（卡种不同子树也不同）。
func _ignore_subtree(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_subtree(c)


## 按钮把鼠标位置转给卡面：视差跟手，但点击/tooltip 一点没让出去。
## 用 bind 而不是 lambda —— GDScript 的 lambda 按值捕获局部变量，以后想回写就踩坑。
func _forward_hover(event: InputEvent, face: CardFace) -> void:
	if face == null or not is_instance_valid(face):
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		# 按钮收到的是全局坐标，卡面要的是自己矩形内的坐标
		face.set_hover_point(face.get_global_transform_with_canvas().affine_inverse() * mm.global_position)
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		var sp := Vector2.ZERO
		if event is InputEventScreenTouch:
			sp = (event as InputEventScreenTouch).position
		else:
			sp = (event as InputEventScreenDrag).position
		face.set_hover_point(face.get_global_transform_with_canvas().affine_inverse() * sp)


func _fallback_portrait(boss_id: String) -> Texture2D:
	var path := String(CodexDB.boss_entry(boss_id).get("portrait", ""))
	if path != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


## 卡面下的名字：⚠ BOSS_CODEX 的条目里**没有 name 键**（只有 subtitle/epithet/portrait…），
## 直接 `BOSS_CODEX[id]["name"]` 恒取不到 → 手牌下面一排 boss_03 / world_core_lianqi。
## 真名走 WorldDB.get_boss_name（塔层表 + 核心表），图鉴条目只当兜底。
func _boss_name(boss_id: String) -> String:
	var nm := String(WorldDB.get_boss_name(boss_id))
	if nm != "" and nm != boss_id:
		return nm
	var e: Dictionary = CodexDB.boss_entry(boss_id)
	return String(e.get("name", boss_id))


func _update_hud() -> void:
	_prompt.text = _stage_prompt()
	var legal := _state.legal_activate(PLAYER_TEAM).size() if _state.phase == MatchState.Phase.BATTLE else 0
	# 倒计时：正中间、最大字号，最后 5 秒转红并加描边宽度 ——
	# 以前它和另外三行小字挤在左上角，玩家要低头找。
	if _state.phase == MatchState.Phase.OVER:
		# 结束后这行不能再写"等待你的操作 0s 后自动代打"—— 那是在催一个已经不存在的操作
		_timer_label.text = "对局已结束"
		_timer_label.add_theme_color_override("font_color", Color(0.72, 0.74, 0.78))
	elif _state.phase == MatchState.Phase.BATTLE or _state.phase == MatchState.Phase.FINAL:
		_timer_label.text = "%.1f" % maxf(_state.timer, 0.0)
		_timer_label.add_theme_color_override("font_color",
				Color(1.0, 0.42, 0.34) if _state.timer <= 5.0 else Color(0.99, 0.90, 0.62))
	elif not _awaiting_player():
		# 轮到对方布阵：这一段没有玩家的计时。摆一个不动的数字（截图里是"0"）
		# 会被读成"卡住了"或"我在超时"；写文字又和下面那行提示重复，所以只留一个破折号。
		_timer_label.text = "—"
		_timer_label.add_theme_color_override("font_color", Color(0.62, 0.64, 0.68))
	else:
		var left := maxf(_stage_timer, 0.0)
		_timer_label.text = "%.0f" % left
		_timer_label.add_theme_color_override("font_color",
				Color(1.0, 0.42, 0.34) if left <= 5.0 else Color(0.99, 0.90, 0.62))
	# 左右两个次要读数：关卡与存活在左、可选张数在右，都不与倒计时抢位置。
	# 右槽原来是「注额 50（有效 50）」，关卡制下押注不再结算，留着就是骗人（ADR-0001）。
	_level_label.text = "第 %d 关" % _level
	_score_label.text = "我方 %d ／ 对方 %d" % [_alive(PLAYER_TEAM), _alive(AI_TEAM)]
	_note_label.text = "可选 %d" % legal if legal > 0 else ""


func _alive(team: int) -> int:
	var n := 0
	for c in _state.cards:
		if int(c["team"]) == team and bool(c["spawned"]) and bool(c["alive"]):
			n += 1
	return n


## 阶段提示：只回答"现在该干什么"，一句话。
## 数字读数一律在两侧与中间倒计时里，不混进这一行（混进去就要玩家读三段）。
func _stage_prompt() -> String:
	match _state.phase:
		MatchState.Phase.PICK:
			return "选牌　从卡包里挑 6 张（已选 %d）" % _picked.size()
		MatchState.Phase.LOCK:
			var done := (1 if _lock_down >= 0 else 0) + (1 if _lock_up >= 0 else 0)
			if done >= 2:
				return "锁定　两张都锁好了，剩下 4 张系统随机 2 正 2 反"
			return "锁定　点一张牌，再按下面的「锁反面」或「锁正面」（已锁 %d/2）" % done
		MatchState.Phase.DEPLOY:
			if _quick:
				# 快速模式没有"对方正在放子"这一说 —— 它开局就摆完了。
				var mine_left := MatchDB.DECK_SIZE * MatchDB.TEAM_COUNT \
						- _state.deployed_count()
				if mine_left <= 0:
					return "布阵　12 只已全部就位，点「开战」直接全员上场"
				return "布阵　对方已摆好　你还差 %d 张（点手牌，再点发亮的空格）" % mine_left
			if _state.deploy_turn == PLAYER_TEAM:
				return "布阵　点手牌选一张，再点棋盘上发亮的空格落子" if _sel_card < 0 \
						else "布阵　已选，点一个发亮的空格"
			return "布阵　对方正在放子…"
		MatchState.Phase.BATTLE:
			if _state.fighting():
				return "第 %d 轮　交战中" % (_state.round_index + 1)
			# ⚠ 这里不许写 **加粗**：Label 不解析 markdown，实机截出来就是两颗星。
			#   要强调就靠"己方/对方"这两个字本身和后面的括号说明。
			# 2026-11-10：BATTLE 手牌列整个收掉了，提示必须**明说点棋盘**，
			#   不然玩家还在找右侧那排按钮（截图里棋盘放大后右侧是空的）。
			return ("第 %d 轮　点棋盘上发光的己方卡片激活" % (_state.round_index + 1)) \
					if _state.is_own_round() \
					else ("第 %d 轮　点棋盘上发光的对方卡片，替它决定进场时机" % (_state.round_index + 1))
		MatchState.Phase.FINAL:
			# 快速模式没有"轮"，读数要直说现在是在等结果
			if _quick:
				return "快速模式　12 只已全员上场，清场定胜负"
			return "终局　全部翻完，清场定胜负"
		MatchState.Phase.OVER:
			return "对局结束"
	return ""


# ===================== 结算 =====================

## 棋子死亡那一刻收账（`died` 带 boss_id，bind 把 card 与节点跟上来）。
## 重复收账是安全的：`_snapshot_report` 是覆盖而不是累加。
func _on_piece_died_report(_boss_id: String, card: int, node: Node) -> void:
	_snapshot_report(card, node)


## 战报收账：把这一格 host 子树里**所有**单位的台账并进卡的快照。
##
## ⚠ 为什么必须按子树而不是只抄本体：观澜死后它的镜像还在打，
##   那些钱记在镜像自己身上，而镜像不是 12 张卡之一 —— 只抄本体时
##   两侧总额差 3.4 万（实测判据「对方打出 == 我方承受」红在这里）。
## ⚠ 为什么是**增量**：每个单位的字典是累计值，收过一遍再收就重复计钱。
##   所以每个单位身上挂一个 meta 记"已经入过多少"，每次只补差额。
func _snapshot_report(card: int, _node: Node = null) -> void:
	var e: Dictionary = _report.get(card, {})
	if e.is_empty():
		return
	for n in _host_units(card):
		_bank_into(e, n)


## 这一格 host 子树里所有带台账的单位（本体 + 镜像 / 召唤物 / 分影…）。
func _host_units(card: int) -> Array:
	var out: Array = []
	var host: Node = _pieces.get_node_or_null("PieceHost%d" % card)
	if host == null:
		return out
	for n in host.find_children("*", "Node", true, false):
		if n is BossBase and (n as BossBase).team_id >= 0:
			out.append(n)
	return out


## 把一个单位的两层台账并入卡的快照，只补差额。
func _bank_into(e: Dictionary, n: Node) -> void:
	var banked: Dictionary = n.get_meta("report_bank") if n.has_meta("report_bank") else {}
	e["rows"] = _merge_delta(e.get("rows", {}), n.get("report_rows"), banked.get("rows"))
	e["taken"] = _merge_taken_delta(e.get("taken", {}), n.get("report_taken"), banked.get("taken"))
	n.set_meta("report_bank", {"rows": (n.get("report_rows") as Dictionary).duplicate(true),
			"taken": (n.get("report_taken") as Dictionary).duplicate(true)})


func _merge_delta(into: Dictionary, cur: Variant, was: Variant) -> Dictionary:
	if not (cur is Dictionary):
		return into
	var prev: Dictionary = was if was is Dictionary else {}
	for k in (cur as Dictionary).keys():
		var delta := float((cur as Dictionary)[k]) - float(prev.get(k, 0.0))
		if delta > 0.0:
			into[k] = float(into.get(k, 0.0)) + delta
	return into


## 承受账是两层（来源 → {招式: 金额}），逐来源做同样的增量合并。
func _merge_taken_delta(into: Dictionary, cur: Variant, was: Variant) -> Dictionary:
	if not (cur is Dictionary):
		return into
	var prev: Dictionary = was if was is Dictionary else {}
	for src in (cur as Dictionary).keys():
		if not into.has(src):
			into[src] = {}
		var bucket: Dictionary = into[src]
		_merge_delta(bucket, (cur as Dictionary)[src], prev.get(src))
		into[src] = bucket
	return into



## 组两栏数据：每侧 6 只，按总输出降序；行内也按金额降序。
## 「未上场」也要有一行 —— 玩家最想知道的答案是"我这第六张为什么没出"。
func _report_sides() -> Array:
	var out: Array = []
	for team in [PLAYER_TEAM, AI_TEAM]:
		var units: Array = []
		for i in _state.team_cards(team):
			var c: Dictionary = _state.cards[i]
			_snapshot_report(i, _live.pieces.get(i) as Node)
			var e: Dictionary = _report.get(i, {})
			var rows: Dictionary = e.get("rows", {})
			var pairs: Array = _sorted_pairs(rows)
			var taken_pairs: Array = _taken_groups(e.get("taken", {}))
			var taken_total := 0.0
			for g in taken_pairs:
				taken_total += float((g as Dictionary).get("total", 0.0))
			units.append({
				"card": i,
				"name": _boss_name(String(c["boss_id"])),
				"total": _rows_sum(pairs),
				"taken_total": taken_total,
				"spawned": bool(c["spawned"]),
				"alive": bool(c["alive"]),
				"rows": pairs,
				"taken": taken_pairs,
			})
		units.sort_custom(func(x, y):
			return float(x["total"]) > float(y["total"]))
		out.append({"title": "我方" if team == PLAYER_TEAM else "对方", "units": units})
	return out


## 字典 → 按金额降序的 [行名, 金额] 数组。
func _sorted_pairs(rows: Dictionary) -> Array:
	var pairs: Array = []
	for k in rows.keys():
		pairs.append([String(k), float(rows[k])])
	pairs.sort_custom(func(x, y):
		return float(x[1]) > float(y[1]))
	return pairs


## 承受账 → 按来源棋子分组：组头是来源名与该来源的合计，组里只列招式。
## 排序按"谁打我打得最多"降序，玩家第一眼看的就是主因。
func _taken_groups(taken: Dictionary) -> Array:
	var groups: Array = []
	for src in taken.keys():
		var bucket: Dictionary = taken[src]
		var pairs := _sorted_pairs(bucket)
		var t := _rows_sum(pairs)
		if t <= 0.0:
			continue
		groups.append({"source": String(src), "total": t, "rows": pairs})
	groups.sort_custom(func(x, y):
		return float(x["total"]) > float(y["total"]))
	return groups


func _rows_sum(pairs: Array) -> float:
	var t := 0.0
	for p in pairs:
		t += float((p as Array)[1])
	return t


## 打开战报页。挂在 HUD 那一支（不随对局冻结），结算面板还在下面看得见。
func open_report() -> void:
	if _report_view != null and is_instance_valid(_report_view):
		return
	var host: Node = _result.get_parent() if _result != null and is_instance_valid(_result) else null
	if host == null and _hud_root != null and is_instance_valid(_hud_root):
		host = _hud_root
	if host == null or _state == null:
		return
	_report_view = MatchReportView.open(host, _report_sides(),
			"第 %d 关　%s" % [_level, _end_reason_text()])


func _settle() -> void:
	if _result.visible:
		return
	# 任务面板（2026-11-11）：「完成一局」不论胜负，真实对局走到结算即算
	Tutorial.note("match_finished")
	GameState.reset_time_flow()
	var won := _state.winner == PLAYER_TEAM
	# 线性推进 ⇒ "首通"就是打通了比已通关最高关更靠后的那一关。
	# 重打已封卷的关卡一分不给：无限关 + 每局都给就成了挂机印钱（ADR-0001）。
	# 押注制在这里整段撤掉 —— 输了不扣、平局不退，因为本来就没押。
	var first_clear := won and _level > CharacterData.match_level_cleared
	var reward := int(MatchDB.LEVEL_FIRST_CLEAR_REWARD) if first_clear else 0
	if first_clear:
		CharacterData.grant_material_guaranteed(CharacterData.ENHANCE_MATERIAL, reward)
		CharacterData.match_level_cleared = _level
	_result_label.text = "%s\n结束方式：%s" % [
			_settle_text(won, first_clear, reward), _end_reason_text()]
	_show_result_deck()
	_result.visible = true


## 内部枚举直接上屏过一回：玩家看到「结束方式：clear_field」只会更糊涂。
## 查不到就原样显示并喊出来 —— 宁可红一条探针，也不要静悄悄漏英文。
func _end_reason_text() -> String:
	var r := String(_state.end_reason)
	if r == "":
		return "未分胜负"
	if not MatchDB.END_REASON_TEXT.has(r):
		push_warning("棋坛：结束方式 %s 没有玩家可读的文案，去 MatchDB.END_REASON_TEXT 补" % r)
		return r
	return String(MatchDB.END_REASON_TEXT[r])


## 结算文案：数额一律从 MatchDB 现算，不把 8 写死在这里；
## 四种结果都要回答玩家此刻真正想知道的那句"这关到底算不算过了"。
## 结算页也要标档位（票 007 拍定"处处标注"）。
## 理由不是好看：两种模式**完全等价**，钱和进度一模一样，
## 玩家事后唯一能分辨"这局我根本没做过逐轮决策"的地方就是这一行。
func _settle_text(won: bool, first_clear: bool, reward: int) -> String:
	var tag := "（快速模式）" if _quick else ""
	if first_clear:
		return "胜　首通第 %d 关　+%d 锻造晶石%s" % [_level, reward, tag]
	if won:
		return "胜　第 %d 关早已封卷，不再产钱%s" % [_level, tag]
	if _state.winner == MatchState.WIN_DRAW:
		return "平　未分胜负，第 %d 关仍算未通过%s" % [_level, tag]
	return "负　本局无损耗，可再来%s" % tag


## 结算页铺自己那 6 张卡面：阵亡的压暗，玩家一眼看清"谁活到了最后"。
## 只有文字结论的话，复盘时根本对不上是哪只先倒的。
func _show_result_deck() -> void:
	for ch in _result_deck.get_children():
		ch.queue_free()
	for i in _state.team_cards(PLAYER_TEAM):
		var c: Dictionary = _state.cards[i]
		var bid := String(c["boss_id"])
		var w := 82.0
		var sz := Vector2(w, w * 1.5)
		# 结算页也走 CardFace：这一页是玩家复盘「我带的到底是谁、谁倒在哪」的地方，
		# 给一排没有框的缩略图，和选牌时看到的就不是同一批牌了。
		var host := Panel.new()
		host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.custom_minimum_size = sz
		var tip := "%s　%s" % [_boss_name(bid),
				"存活" if bool(c["alive"]) else ("未上场" if not bool(c["spawned"]) else "阵亡")]
		host.tooltip_text = tip
		_result_deck.add_child(host)
		var style := MatchCard.player_style(bid, CharacterData.match_card_kind)
		var face := CardFace.new()
		if not style.is_empty() and face.configure(style, sz, MatchCard.accent(bid), false):
			face.set_idle_motion(false)
			face.set_input_enabled(false)
			host.add_child(face)
			face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_ignore_subtree(face)
			# 结算页没有按钮语义，但扫过去也该有视差：让 host 收 motion 再转进去
			host.mouse_filter = Control.MOUSE_FILTER_STOP
			host.gui_input.connect(_forward_hover.bind(face))
		else:
			var tex := TextureRect.new()
			tex.texture = _fallback_portrait(bid)
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tex.clip_contents = true
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			host.add_child(tex)
			tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if not bool(c["alive"]):
			host.modulate = Color(1, 1, 1, 0.42)


## 结算「返回长卷」：回到挑局那一屏，居停在刚打完的这一关（长卷按存档重算当前关）。
## 不回主城 —— 关卡制下玩家要一关接一关地推，每关都重新点一次设施太碎。
## ⚠ 弃局返回（设置面板里那条）是另一个去处，走 #58 单独实现，别复用这条。
func _return_to_scroll() -> void:
	_set_frozen(false)         # 绝不能把 paused 交给下一个场景（_exit_tree 是兜底，这里是明账）
	GameState.reset_time_flow()
	GameState.match_context = {}
	get_tree().change_scene_to_file("res://scenes/match/match_level_scroll.tscn")


## 弃局返回原初位面 —— 设置面板里那条调的就是这里（#58，所以是公开入口）。
## 零代价（ADR-0001）：不扣晶石、不推进度、不限次；本局直接作废、关卡保持未通。
## ⚠ 与结算的 `_return_to_scroll()` 是两条路：结算回长卷接着推，弃局回城。
func abandon_match() -> void:
	_set_frozen(false)
	GameState.reset_time_flow()
	GameState.match_context = {}
	get_tree().change_scene_to_file("res://scenes/main/primordial_realm.tscn")
