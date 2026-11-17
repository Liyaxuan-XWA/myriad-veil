class_name MatchLevelScroll
extends Control
## 万界棋坛 · 棋谱长卷（关卡选择全屏舞台）
##
## 一幅从左往右展开的手卷：每一关是卷上的一「局」，画成一枚 6×6 棋盘拓印，
## 对手那 6 张固定卡组**当作落子嵌在格子里**，不是旁边再列一排卡片清单 ——
## 信息本身就是装饰，玩家扫一眼卷面就知道这关摆的是什么阵。
##
## 母题口径见 CONTEXT.md「棋谱长卷」一节；工单 .scratch/棋坛关卡制/tickets/002、004。
## 本文件只做**结构与交互**；绢本底图与拓片质感在 #59（006 长卷美术定稿）补。

const TILE_GAP := 54.0             ## 拓印之间的卷面间距
const PREVIEW_AHEAD := 5           ## 当前关之后还能预览几关（有卡组、看得见、进不去）
const SILHOUETTE_SLOTS := 6        ## 再往右挂几枚剪影：只画轮廓，读作「卷还在往右长」
const STRIP_H := 108.0             ## 底部读数带高度
const TILE_MIN := 150.0            ## 拓印边长下限
const TILE_MAX := 340.0            ## 上限：再大就横着滚不动，且 6 枚落子的脸已经够清
const LABEL_H := 44.0              ## 拓印下方「第 N 关 / 阵眼」两行题签占的高
const HEAD_W := 118.0              ## 卷首题签占的宽度
## 普通模式拓印的卡组清单：3 列 × 2 行。
## 为什么不是"一列 6 张"：方块边长 340 时一列只剩 37px 宽，卡面糊成一团；
## 3×2 每张约 80×121，卡面与名字都还读得清，且整体仍落在原来的方块 footprint 里，
## 长卷的横向节奏与题签位置一个数都不用改。
const LIST_COLS := 3
const LIST_PAD := 0.10             ## 清单四周留白（占方块边长比例）
const LIST_GAP := 0.045            ## 卡与卡的间距（同上）
const TAIL_W := 260.0              ## 卷尾留白：最后一槽之后还留一段空绢

## 舞台底图与它的纸面几何（tools/process_scroll_stage.py 实测出来的分数，不是手估）。
## ⚠ 拓印的纵向落点必须由这两个分数反推，不能另写一套常量：
##   照片里那卷绢就摆在那儿，代码算出的位置偏了，拓印就浮在桌面或压住轴杆。
const STAGE_PATH := "res://assets/ui/match/stage_scroll.png"
const STAGE_SIZE := Vector2(1792.0, 1024.0)
const PAPER_Y := Vector2(0.217, 0.772)
const PAPER_X := Vector2(0.030, 0.955)

## 拓印里 6 枚落子的格子（列, 行）。⚠ 这是**展示约定**，不是预测：
## 真实布阵是开局时 AI 现场决定的，两者无关（CONTEXT.md「拓印」条已写明）。
## 取靠下方（AI 半场）的一串松散弧线，读起来像"一盘已经摆好的开局"。
const STONE_CELLS: Array[Vector2i] = [
	Vector2i(0, 4), Vector2i(2, 3), Vector2i(4, 4),
	Vector2i(1, 5), Vector2i(3, 5), Vector2i(5, 5),
]

signal level_entered(level: int)

var _current := 1
var _focused := 1
## 槽号 → 拓印。槽 i 就是第 i+1 关。
## ⚠ 这里**只装可见范围 ±1 的那几枚**：关卡是无限的，通关几百局要是把每一槽都建成节点，
##   进场就是上千个 CardFace。虚拟化见下面「窗口规则」。
var _tiles_by_slot: Dictionary = {}
## 建完没有。⚠ 调用方常常是 `new()` → 先设锚点/尺寸 → 再 `add_child`，
## 于是 NOTIFICATION_RESIZED 会在 `_ready()` 之前就到，那时 `_strip` / `_cta`
## 还是 null，_layout() 直接空引用（位面星图用同一个闸门防这件事）。
var _built := false
var _strip: Control              ## 卷面（被拖动的那一条）
var _tile := 300.0               ## 当前算出的拓印边长，_slot_x() 要用
var _origin_y := 104.0           ## 卷面在标题带与底部带之间的垂直落点
var _dragging := false
var _drag_base := 0.0
var _drag_focus := false

var _title: Label
var _sub: Label
var _strip_name: Label
var _strip_meta: Label
var _strip_cards: HBoxContainer
var _cta: Button
var _back_btn: Button          ## 卷尾「返回原初位面」
var _quick_btn: Button         ## 「快速模式：开/关」——整屏唯一的模式开关
var _head: Label                 ## 卷首竖排题签
var _head_progress: Label        ## 题签旁的「已推 N 局」


# ===================== 窗口规则（虚拟化） =====================
## 卷上槽位 = 已通关全部 + 当前关 + 往后 PREVIEW_AHEAD 关（这些有卡组、能预览），
## 其后再挂 SILHOUETTE_SLOTS 枚剪影。两条硬约定：
##   · 内容宽度按**槽位数解析算出**，不按已建节点算 —— 否则滚到哪儿卷就有多长；
##   · 节点只建可见范围 ±1，横扫时由 _process 补建，绝不露白。
## 取代了原来"MAX_TILES=40 从尾部保留、把最老的局砍掉"的写法：
## 通关 60 局就看不见第 1 关了，而「回看自己打过的谱」正是这面卷的意义。

func _deck_slot_count() -> int:
	return _current + PREVIEW_AHEAD


func _slot_count() -> int:
	return _deck_slot_count() + SILHOUETTE_SLOTS


func _slot_level(slot: int) -> int:
	return slot + 1


func _is_silhouette(level: int) -> bool:
	return level > _deck_slot_count()


func _step() -> float:
	return _tile + TILE_GAP


func _slot_x(slot: int) -> float:
	return HEAD_W + TILE_GAP + float(slot) * _step()


func _content_width() -> float:
	return HEAD_W + float(_slot_count()) * _step() + TAIL_W


## 卷首题签：竖排一行字钉在绢面前段，说明这卷是什么、现在推到第几局。
## 卷尾留白：最后一槽之后还要留一段空白绢，否则卷像是被硬截断的。
func _build_head_slip() -> void:
	_head = Label.new()
	_head.text = "万界棋坛对局长卷"
	_head.add_theme_font_size_override("font_size", UIKit.F_SECTION)
	_head.add_theme_color_override("font_color", Color(0.72, 0.62, 0.40, 0.80))
	_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head.rotation_degrees = 90.0
	_head.pivot_offset = Vector2(0, 14)
	_strip.add_child(_head)
	_head_progress = UIKit.note("")
	_head_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(_head_progress)


## 照片里那段绢面在当前窗口上的真实矩形。
## 底图用 KEEP_ASPECT_COVERED 铺，所以映射方式和它必须一致：
## 取覆盖比例 → 算出被裁掉的边 → 平移。标题带、卷面落点全都从这一个函数派生，
## 换一张底图只改分数常量，不会再出现"代码算的位置和画上的纸对不上"。
func _paper_rect() -> Rect2:
	var s := maxf(size.x / STAGE_SIZE.x, size.y / STAGE_SIZE.y)
	var off := (size - STAGE_SIZE * s) * 0.5
	var x0 := off.x + PAPER_X.x * STAGE_SIZE.x * s
	var x1 := off.x + PAPER_X.y * STAGE_SIZE.x * s
	var y0 := off.y + PAPER_Y.x * STAGE_SIZE.y * s
	var y1 := off.y + PAPER_Y.y * STAGE_SIZE.y * s
	return Rect2(x0, y0, x1 - x0, y1 - y0)


## 标题带的高度 = 纸面上沿往上的那段暗桌
func _header_h() -> float:
	return clampf(_paper_rect().position.y - 10.0, 64.0, 150.0)


## 当前横向可见（左右各留一格缓冲）的槽号
func _visible_slots() -> Array[int]:
	var out: Array[int] = []
	if _step() <= 0.0 or _strip == null:
		return out
	var left := -_strip.position.x
	var first := int(floor(left / _step())) - 1
	var last := int(ceil((left + size.x) / _step())) + 1
	for s in range(maxi(first, 0), mini(last, _slot_count() - 1) + 1):
		out.append(s)
	return out


func _sync_tiles() -> void:
	var want := {}
	for s in _visible_slots():
		want[s] = true
	var stale: Array[int] = []
	for s in _tiles_by_slot.keys():
		if not want.has(int(s)):
			stale.append(int(s))
	for s in stale:
		var t: Dictionary = _tiles_by_slot[s]
		(t["root"] as Control).queue_free()
		_tiles_by_slot.erase(s)
	var added := false
	for s in want.keys():
		if _tiles_by_slot.has(int(s)):
			continue
		var tile := _make_tile(int(s))
		_tiles_by_slot[int(s)] = tile
		_position_one(int(s), tile)
		added = true
	if added:
		_refresh_tile_states()


func _process(_delta: float) -> void:
	if not _built:
		return
	# 拖动 / 滚轮 / 触屏划都在改 _strip.position.x，统一在这里收口重算可见范围
	_sync_tiles()
	# 只有"正在划卷"时才让焦点跟着画面中心走。
	# 不能无条件做：点某一关是"我要看这关"，下一帧就被中心吸附拽回隔壁那关，点了个寂寞。
	if _dragging:
		_focus_center_slot()


## 把画面正中间那一槽交给底部读数带 —— 玩家滚到哪儿，读数就该讲到哪儿。
func _focus_center_slot() -> void:
	var best := _focused
	var best_d := INF
	for slot in _tiles_by_slot.keys():
		var c: Control = _tiles_by_slot[int(slot)]["root"]
		var d := absf(c.position.x + _strip.position.x + c.size.x * 0.5 - size.x * 0.5)
		if d < best_d:
			best_d = d
			best = int(slot)
	_focus(_slot_level(best))


# ===================== 生命周期 =====================

func _ready() -> void:
	# 棋坛卷面不需要虚拟键：这里没有走位/战斗操作
	VirtualPad.set_context("none")
	clip_contents = true
	_current = maxi(CharacterData.match_level_cleared + 1, 1)
	_focused = _current
	_build_backdrop()
	_build_header()
	_build_strip()
	# 底部带必须先于拓印：_layout() 会走 _refresh_strip()，
	# 那时 _strip_cards / _cta 还不存在就会拿 null 调 get_children()。
	_build_info_strip()
	_build_head_slip()
	# ⚠ 出口键必须排在卷面之后：`_strip` 是 MOUSE_FILTER_STOP 且铺满整屏高度，
	#   鼠标拾取给"最后画的那个"，排在它前面就点不动（右上角那颗「设置」之所以没事，
	#   是因为它挂在 layer 90 的 CanvasLayer 上，不跟场景内控件排队）。
	_build_top_exit()
	_layout()
	_built = true
	set_process(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _built:
		_layout()


# ===================== 底与标题 =====================

func _build_backdrop() -> void:
	# 旧绢长卷的舞台底图（vibe_images/match_scroll_stage_tall_*.png 图生图，
	# 再经 tools/process_scroll_stage.py 压暗降饱和到和其他设施同一档）。
	var stage := TextureRect.new()
	stage.texture = UIKit.ui_texture(STAGE_PATH)
	stage.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stage.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)

	# 顶部再压一层，保证左上角的标题在纸面反光上仍然读得清
	var vign := TextureRect.new()
	vign.texture = UIKit.vertical_gradient(Color(0.01, 0.008, 0.006, 0.72), Color(0.0, 0.0, 0.0, 0.0))
	vign.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vign.stretch_mode = TextureRect.STRETCH_SCALE
	vign.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	vign.offset_bottom = _header_h() + 46.0
	vign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vign)


func _build_header() -> void:
	var head := UIKit.vbox(2)
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	head.offset_left = 22.0
	head.offset_top = 14.0
	head.offset_bottom = _header_h()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)

	_title = UIKit.title("棋谱长卷")
	head.add_child(_title)
	_sub = UIKit.subtitle("万界棋坛 · 一局一谱　对手卡组已摊开，怎么破自己看")
	head.add_child(_sub)


## 出口键：贴在右上角那颗常驻「设置」的**左边**（用户 2026-11-05 要求，原来在底栏 CTA 那一排）。
## ⚠ 位置必须跟着右边缘走，不能写死 x：`SettingsUI` 的按钮自己是 PRESET_TOP_RIGHT + (-90, 6)，
##   宽屏（20:9 逻辑视口 1600 宽）下写死坐标会浮进屏幕内侧和它错开 —— 那条坑就写在它的注释里。
##   所以这里同样锚右上，偏移量从它的右边界往回推：-90 是设置的左边，再留 8 间距、退一个身位。
const EXIT_W := 132.0
const EXIT_H := 32.0               ## 与「设置」同高，两颗并排才像一组
const SETTINGS_LEFT := -90.0       ## SettingsUI 按钮的左边界（相对右边缘）
const EXIT_GAP := 8.0


func _build_top_exit() -> void:
	_back_btn = UIKit.quiet_button("返回原初位面", Vector2(EXIT_W, EXIT_H))
	_back_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	## 四个 offset 全写死，不用 `position = …` 那一招：
	## 只设 position 的话 offset_right 还停在 0，宽度会变成 230 而不是 132
	## （SettingsUI 那颗按钮就是这么"歪打正着"成 90 宽的，这里不照着抄）。
	_back_btn.offset_left = SETTINGS_LEFT - EXIT_GAP - EXIT_W
	_back_btn.offset_right = SETTINGS_LEFT - EXIT_GAP
	_back_btn.offset_top = 6.0
	_back_btn.offset_bottom = 6.0 + EXIT_H
	_back_btn.tooltip_text = "退出长卷回主城，不改任何进度。\n也可以按 ESC。"
	_back_btn.pressed.connect(_on_back_pressed)
	add_child(_back_btn)


## ESC = 点右上角那颗「返回原初位面」。
## ⚠ 三条边界，少一条就会变成"看起来能用、其实互相抢键"：
##   ① 设置面板用 `_input` + `set_input_as_handled()` 抢先吃掉 ESC（关面板），
##      这里走 `_unhandled_input`，所以面板开着时按 ESC 只会关面板，不会连着一块回主城；
##   ② 触屏那颗虚拟键面上写着「设置」，它注入的也是 ESC —— 不区分的话触屏玩家点设置就变成退出，
##      所以虚拟 ESC 归 `SettingsUI`，真人键盘 ESC 才归退出；
##   ③ 主城那条 ESC 是「返回登录界面」，与「返回原初位面」是两条路（CONTEXT.md 已写明），
##      长卷是独立场景，不共用主城的处理。
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed \
			or (event as InputEventKey).echo:
		return
	if int(event.physical_keycode) != KEY_ESCAPE:
		return
	if VirtualPad.is_virtual_key(KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		SettingsUI.open_panel()
		return
	get_viewport().set_input_as_handled()
	_on_back_pressed()


# ===================== 卷面与拓印 =====================

func _build_strip() -> void:
	_strip = Control.new()
	_strip.name = "Scroll"
	_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	_strip.gui_input.connect(_on_strip_input)
	add_child(_strip)


## 一枚拓印 = 6×6 网格 + 6 枚落子 + 卷侧题签。
## 剪影槽走另一条路：**不调 deck_for**、不放卡面、不吃点击 ——
## 既守住"未来的关还没算"，也让无限长卷在视觉上真的没有尽头。
func _make_tile(slot: int) -> Dictionary:
	var level := _slot_level(slot)
	var sil := _is_silhouette(level)
	var deck: Array = [] if sil else MatchLevelDeck.deck_for(level)

	var root := Control.new()
	root.name = "L%d" % level
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE if sil else Control.MOUSE_FILTER_PASS
	if not sil:
		root.gui_input.connect(_on_tile_input.bind(level))
	_strip.add_child(root)

	# 2026-11-05 用户拍定：**普通模式不再把 6 张牌嵌进 6×6 格子**。
	# 普通模式的真实布阵是进关那一刻才随机决定的（ADR-0004），画在格子里就是
	# 拿一个不存在的事实骗人 —— 玩家只会读成"这就是我要打的阵"，然后发现对不上。
	# 只有快速模式（摆位由关卡号派生、进关前已定死）才配得上格子。
	var list_mode := not sil and not CharacterData.match_quick_mode

	var board := Rubbing.new()
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.silhouette = sil
	board.grid = not list_mode
	root.add_child(board)

	var hosts: Array[Control] = []
	if not sil:
		var place := _stone_placement(level, deck)
		for i in deck.size():
			var host := _make_stone(String(deck[i]), bool(place["faces"][i]))
			root.add_child(host)
			hosts.append(host)
			# 清单模式没有"落点"可言，set_stone 一调就等于又把假阵型画回去了
			if not list_mode:
				board.set_stone(i, place["cells"][i])
	# 面纱只在"朝向真的未知"时盖。快速模式已经逐张画了牌背，
	# 再盖一层就是两套语言同时说同一件事。
	# 清单模式仍要盖：6 张身份是公开的，正反面要到进关才定。
	board.veil = sil or list_mode

	var tag := UIKit.label("第 %d 关" % level, UIKit.F_BODY, UIKit.C_NUM)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tag)
	var lord := UIKit.label(_lord_name(deck, sil), UIKit.F_SMALL, UIKit.C_TEXT_DIM)
	lord.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lord)

	return {"slot": slot, "level": level, "root": root, "board": board,
		"tag": tag, "lord": lord, "deck": deck, "hosts": hosts,
		"silhouette": sil, "list": list_mode}


## 一枚落子。`face_up=false` 只在快速模式出现（那时朝向是已知的），画全局牌背。
func _make_stone(boss_id: String, face_up: bool = true) -> Panel:
	var host := Panel.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not face_up:
		host.add_child(_stone_back())
		# ⚠ 反面绝不写名字：细化后的「预告」口径是"6 张身份全摊开，
		#   但反面卡的格子对应关系不摊开"。tooltip 一写名字，牌背就白盖了。
		host.tooltip_text = "反面　进关才知道这一格是哪一只"
		return host
	var face := CardFace.new()
	var style := MatchCard.opponent_style(boss_id)
	if not style.is_empty() and face.configure(style, Vector2(_stone_w(), _stone_h()),
			MatchCard.accent(boss_id), false):
		face.set_idle_motion(false)
		face.set_input_enabled(false)
		host.add_child(face)
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		host.add_child(_stone_fallback())
	host.tooltip_text = "%s　原始面板第 %d 档" % [_boss_name(boss_id), MatchLevelDeck.raw_rank(boss_id)]
	return host


## 牌背复用 MatchCard.back_texture() —— 全局统一一张，代码注释里明写
## "不许带任何单卡元素"。拓印自己再画一种背纹，一屏就会出现两套"盖着"的画法。
func _stone_back() -> TextureRect:
	var back := TextureRect.new()
	back.texture = MatchCard.back_texture()
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	back.clip_contents = true
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return back


func _stone_fallback() -> TextureRect:
	var tex := TextureRect.new()
	tex.texture = _fallback_portrait()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.clip_contents = true
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return tex


## 拓印上 6 枚落子的格子与正反面。
## · 普通模式：**不画 6×6 格子**（2026-11-05 改版，见设计案 §2g），所以这里不返回落点。
##   那时真实布阵要到进关那一刻才由 AI 随机决定（ADR-0004），
##   画在格子里等于陈述一个不存在的事实；旧版那套"装饰落点 + 展示约定"就是这么骗人的。
##   正反面一律 true，朝向未知由整枚面纱表达。
## · 快速模式：格子与正反面全部来自 MatchQuickSetup.layout_for(level)，
##   也就是对局开局真正摆的那一份（同源硬约束）。
##   layout_for 返回的是**落子先后序**，所以要先建 boss_id → 条目 的映射再按卡组回填。
func _stone_placement(level: int, deck: Array) -> Dictionary:
	var cells: Array[Vector2i] = []
	var faces: Array = []
	cells.resize(deck.size())
	for i in deck.size():
		faces.append(true)
	if deck.is_empty() or not CharacterData.match_quick_mode:
		# 清单模式没有落点可言：返回空 cells，调用方（_make_tile）本来就不会读它
		return {"cells": cells, "faces": faces}
	var by_id := {}
	for x in MatchQuickSetup.layout_for(level):
		by_id[String((x as Dictionary)["boss_id"])] = x
	for i in deck.size():
		var e: Dictionary = by_id.get(String(deck[i]), {})
		if e.is_empty():
			# 卡组与布局对不上 = 同源漂了。宁可退回装饰落点并喊出来，
			# 也不要静悄悄画一张对局里不存在的格子。
			push_warning("棋谱长卷：第 %d 关的 %s 不在 layout_for 里" % [level, String(deck[i])])
			cells[i] = STONE_CELLS[i % STONE_CELLS.size()]
		else:
			cells[i] = e["cell"]
			faces[i] = bool(e["face_up"])
	return {"cells": cells, "faces": faces}


## 快速模式下 layout_for 万一漏了某张卡（同源漂了）的兜底落点。
## ⚠ 这只在快速分支里用；普通模式已经不画格子了，别再往回加"装饰阵型"。


func _stone_w() -> float:
	return _tile / float(MatchDB.BOARD_COLS) * 0.92


func _stone_h() -> float:
	return _stone_w() * 1.5


# ===================== 底部读数带 =====================

func _build_info_strip() -> void:
	var band := PanelContainer.new()
	band.mouse_filter = Control.MOUSE_FILTER_STOP
	band.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	band.offset_top = -STRIP_H
	add_child(band)
	_adopt_strip_style(band)

	var row := UIKit.hbox(18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(row)

	var info := UIKit.vbox(3)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	_strip_name = UIKit.title("第 1 关")
	info.add_child(_strip_name)
	_strip_meta = UIKit.note("")
	info.add_child(_strip_meta)

	_strip_cards = UIKit.hbox(6)
	_strip_cards.alignment = BoxContainer.ALIGNMENT_END
	_strip_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_strip_cards)

	var action := UIKit.hbox(10)
	action.alignment = BoxContainer.ALIGNMENT_CENTER
	action.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(action)
	# 全屏幕只有「进入此关」一个主按钮，模式开关走 quiet 档。
	# 「返回原初位面」原来也在这排，2026-11-05 按用户要求挪到右上角贴着「设置」（见 _build_top_exit）。
	_quick_btn = UIKit.quiet_button(_quick_label(), Vector2(146, 42))
	_quick_btn.tooltip_text = "快速模式：进关即见对方六张已摆好，你只摆自己六张，点开战直接全员上场。\n"\
			+ "胜负与奖励和普通模式完全一样（同样 +8 首通晶石、同样推进关卡）。"
	_quick_btn.pressed.connect(_on_quick_pressed)
	action.add_child(_quick_btn)
	_cta = UIKit.primary_button("进入此关", Vector2(158, 42))
	UIKit.set_click_sfx(_cta, "ui_confirm")
	_cta.pressed.connect(_on_cta)
	action.add_child(_cta)


## 开关文案从字段现算，不写死：写死过一次之后，"点了没反应"就再也测不出来。
func _quick_label() -> String:
	return "快速模式：开" if CharacterData.match_quick_mode else "快速模式：关"


func _on_quick_pressed() -> void:
	CharacterData.match_quick_mode = not CharacterData.match_quick_mode
	_quick_btn.text = _quick_label()
	_quick_btn.queue_redraw()


## 卷尾退出：这屏不改任何进度，直接回主城即可。
## 顺手清掉 match_context —— 它是给对局场景读的"这局打第几关"，
## 没进关就退出时留着旧值没意义，将来别处直连对局场景会读到脏关卡。
func _on_back_pressed() -> void:
	GameState.match_context = {}
	GameState.play_ui("ui_back")
	get_tree().change_scene_to_file("res://scenes/main/primordial_realm.tscn")


func _adopt_strip_style(band: PanelContainer) -> void:
	var sb := UIKit.panel_style()
	sb.bg_color = Color(0.035, 0.030, 0.022, 0.90)
	# 不给内容边距的话「第 4 关」会贴着屏幕左边缘，像没排完
	sb.content_margin_left = 18.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	band.add_theme_stylebox_override("panel", sb)


## 这一关能不能进：已封卷的（比当前关小）与当前关都可以，只有还没打到的将来关不行。
## ⚠ 按钮态与点击判定必须共用这一条：同一规则写两处，迟早一处放行一处 deny
##   （这次"打过的关卡无法重打"就是两处都只认 `_focused == _current`）。
func _cta_playable(level: int) -> bool:
	return level <= _current


## 底部带里那排缩略：把选中那一关的 6 张原样再摆一次。
## 拓印里的落子只有 ~50px，玩家要确认"我看到的和卷上画的是同一批牌"。
func _refresh_strip() -> void:
	for ch in _strip_cards.get_children():
		ch.queue_free()
	_strip_name.text = "第 %d 关" % _focused
	_strip_name.add_theme_color_override("font_color", _current_tint())
	_rebuild_focus_reading()

	var tile := _tile_for(_focused)
	if not tile.is_empty():
		var deck: Array = tile["deck"]
		for id in deck:
			var host := Panel.new()
			host.mouse_filter = Control.MOUSE_FILTER_IGNORE
			host.custom_minimum_size = Vector2(40, 60)
			host.tooltip_text = _boss_name(String(id))
			_strip_cards.add_child(host)
			var face := CardFace.new()
			var style := MatchCard.opponent_style(String(id))
			if not style.is_empty() and face.configure(style, Vector2(40, 60),
					MatchCard.accent(String(id)), false):
				face.set_idle_motion(false)
				face.set_input_enabled(false)
				host.add_child(face)
				face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 整屏只有一个主按钮：焦点在哪一关，它就用那一关的语气。
	# ⚠ 「打过的」和「没解锁的」不是一类东西 —— 原来这里写死 `_focused == _current`，
	#   等于把已封卷的关也判成未解锁，玩家想复盘第 3 关的阵眼怎么破，钮却是灰的。
	#   关卡制的口径是**重打不给钱但必须能进**（§2c / ADR-0001）。
	var playable := _cta_playable(_focused)
	if _focused > _current:
		_cta.text = "尚未解锁"
	elif _focused < _current:
		_cta.text = "重打此关"
	else:
		_cta.text = "进入此关"
	_cta.disabled = not playable
	# 禁用态不能还是主按钮那档红：一屏的视觉重心只能有一个，
	# 焦点跑到未解锁的关上时这枚钮要一起退到次要层级，否则玩家以为它仍可点。
	_cta.tone = "primary" if playable else "quiet"
	_cta.queue_redraw()


## 读数带第二行：阵眼 + 状态 +（开着快速模式时）真布局标注。
## 单独封一个函数，不塞进 _refresh_strip：拨一下开关就要立刻重算这一行，
## 而整条带重建会把 6 张小卡也 free 掉一遍，白白闪一下。
func _rebuild_focus_reading() -> void:
	var tile := _tile_for(_focused)
	var deck: Array = tile.get("deck", [])
	var txt := _state_text(_focused)
	if not deck.is_empty():
		txt = "%s　%s" % [_lord_name(deck, false), _state_text(_focused)]
		# 拓印的落点含义按模式分（CONTEXT.md「拓印」），所以这话必须跟着开关走
		if CharacterData.match_quick_mode:
			txt += "　阵型已固定 · 拓印即真实落位"
	_strip_meta.text = txt


func _current_tint() -> Color:
	return UIKit.C_TITLE if _focused == _current else Color(0.62, 0.60, 0.55)


func _state_text(level: int) -> String:
	if level < _current:
		return "已封卷 · 可重打"
	if level == _current:
		return "当前局 · 可挑战"
	if _is_silhouette(level):
		return "卷外 · 尚未展开"
	return "预告 · 通过第 %d 关后开放" % (level - 1)


# ===================== 交互 =====================

func _on_strip_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			# 往左滚 = 翻回更早的局，往右滚 = 看更晚的
			_nudge_scroll(180.0 if mb.button_index == MOUSE_BUTTON_WHEEL_LEFT else -180.0)
			return
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			# 这一屏没有纵向内容，上下滚轮当横滚用
			_nudge_scroll(-40.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 40.0)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed:
				_drag_base = mb.global_position.x - _strip.position.x
				_drag_focus = false
			else:
				_snap_focus()
	elif ev is InputEventMouseMotion and _dragging:
		var rel := absf((ev as InputEventMouseMotion).relative.x)
		_strip.position.x = _clamp_x((ev as InputEventMouseMotion).global_position.x - _drag_base)
		if rel > 2.0:
			_drag_focus = true
	elif ev is InputEventScreenDrag:
		_strip.position.x = _clamp_x(_strip.position.x + (ev as InputEventScreenDrag).relative.x)
		_drag_focus = true


func _on_tile_input(ev: InputEvent, level: int) -> void:
	if not (ev is InputEventMouseButton) or not (ev as InputEventMouseButton).pressed:
		return
	if (ev as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	_focus(level)
	if level == _current:
		_launch(_current)


func _focus(level: int) -> void:
	if level == _focused:
		return
	_focused = level
	_refresh_strip()
	_refresh_tile_states()


func _snap_focus() -> void:
	if not _drag_focus:
		return
	_drag_focus = false
	# 松手后把离屏幕中心最近的那一槽吸到中间，焦点跟着交给它
	var best := maxi(_focused - 1, 0)
	var best_d := INF
	for slot in _tiles_by_slot.keys():
		var c: Control = _tiles_by_slot[int(slot)]["root"]
		var d := absf(c.position.x + _strip.position.x + c.size.x * 0.5 - size.x * 0.5)
		if d < best_d:
			best_d = d
			best = int(slot)
	_scroll_to_slot(best)


func _scroll_to_slot(slot: int) -> void:
	if _strip == null:
		return
	_strip.position.x = _clamp_x(size.x * 0.5 - (_slot_x(slot) + _tile * 0.5))
	_sync_tiles()
	_focus_center_slot()


func _nudge_scroll(dx: float) -> void:
	_strip.position.x = _clamp_x(_strip.position.x + dx)
	_sync_tiles()
	_focus_center_slot()


## 卷面能推到的两个极限。
## ⚠ 右界不是 0：要让第 1 槽落在屏幕**正中间**，卷面必须往右推到正数位置。
##   上一版把右界写成 0，结果开局时第 1 槽被顶到画面左侧、屏幕中心压的是第 2 槽，
##   `_focus_center_slot()` 就把焦点从"当前关"吸附到了隔壁那关 —— 主按钮随之变灰。
func _max_x() -> float:
	return size.x * 0.5 - (_slot_x(0) + _tile * 0.5)


func _min_x() -> float:
	return minf(_max_x(), size.x - _content_width())


func _clamp_x(x: float) -> float:
	return clampf(x, _min_x(), _max_x())


func _on_cta() -> void:
	# 焦点在哪一关就打哪一关：已封卷的关可以重打（不给钱、不推进度），
	# 只有**还没打到的将来关**才拒绝。原来这里连 `_focused < _current` 一起 deny 掉了。
	if not _cta_playable(_focused):
		GameState.play_ui("ui_deny")
		return
	_launch(_focused)


## 决定打哪一局：写上下文 + 发信号，**不切场景**。
## 拆开是因为探针要单独验"选中的是哪一关"，而切场景会 free 掉调用方自己。
func _enter(level: int) -> void:
	GameState.match_context = {"level": level}
	GameState.play_ui("ui_confirm")
	level_entered.emit(level)


## 真正落地一跳。长卷自己就是一个场景，不是谁的面板 —— 只发信号没人接就点不动。
func _launch(level: int) -> void:
	_enter(level)
	get_tree().change_scene_to_file("res://scenes/match/match_arena.tscn")


# ===================== 布局与状态 =====================

func _layout() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	_strip.position = Vector2.ZERO
	_strip.size = Vector2(_content_width(), size.y)

	# 拓印必须落在照片那段绢面**里面**：纸面上沿到下沿就是可用带，
	# 上下再各留一点呼吸。边长取「带高能容下的最大值」和 TILE_MAX 的较小者，
	# 所以换窗口尺寸、换底图都不用改这里的数字（落点同源）。
	var paper := _paper_rect()
	var band_top := paper.position.y + 12.0
	var band_bottom := minf(paper.end.y - 6.0, size.y - STRIP_H - 8.0)
	var avail := maxf(band_bottom - band_top - LABEL_H, TILE_MIN)
	_tile = clampf(avail, TILE_MIN, TILE_MAX)
	# 在纸带里垂直居中，但偏上一线：题签占的下半部分会让整组看起来下沉
	_origin_y = band_top + maxf((band_bottom - band_top - (_tile + LABEL_H)) * 0.46, 0.0)

	# 边长变了 → 已建节点的尺寸与整条卷面宽度全部作废；清空重建最省心，也不容易漏改一处
	for slot in _tiles_by_slot.keys():
		(_tiles_by_slot[int(slot)]["root"] as Control).queue_free()
	_tiles_by_slot.clear()
	# 卷首题签竖排钉在第一槽之前，读起来像卷头上的一方题字
	_head.position = Vector2(HEAD_W * 0.34, _origin_y + 6.0)
	_head_progress.position = Vector2(HEAD_W * 0.34 + 26.0, _origin_y + 6.0)
	_head_progress.text = "已推 %d 局" % maxi(CharacterData.match_level_cleared, 0)
	_sync_tiles()
	_scroll_to_slot(maxi(_focused - 1, 0))
	_refresh_strip()


func _position_one(slot: int, tile: Dictionary) -> void:
	var root: Control = tile["root"]
	var board: Rubbing = tile["board"]
	root.position = Vector2(_slot_x(slot), _origin_y)
	root.size = Vector2(_tile, _tile + LABEL_H)
	board.position = Vector2.ZERO
	board.size = Vector2(_tile, _tile)
	board.cell = _tile / float(MatchDB.BOARD_COLS)
	var hosts: Array = tile["hosts"]
	if bool(tile.get("list", false)):
		# 清单：3 列 × 2 行，在方块里居中。尺寸全部由方块边长推出来，
		# 所以换窗口、换 TILE_MIN/MAX 都不用回来改这里的数字。
		var pad := _tile * LIST_PAD
		var gap := _tile * LIST_GAP
		var usable := _tile - pad * 2.0
		var rows := int(ceil(float(hosts.size()) / float(LIST_COLS)))
		var cw := (usable - gap * float(LIST_COLS - 1)) / float(LIST_COLS)
		var ch := cw * 1.5
		var y0 := pad + maxf((usable - (ch * float(rows) + gap * float(rows - 1))) * 0.5, 0.0)
		for i in hosts.size():
			var host: Control = hosts[i]
			host.size = Vector2(cw, ch)
			host.position = Vector2(pad + float(i % LIST_COLS) * (cw + gap),
					y0 + float(int(i / LIST_COLS)) * (ch + gap))
	else:
		var s := _tile / float(MatchDB.BOARD_COLS)
		var gw := _stone_w()
		var gh := _stone_h()
		for i in hosts.size():
			var host: Control = hosts[i]
			var cell: Vector2i = board.stone_cell(i)
			host.size = Vector2(gw, gh)
			host.position = Vector2(cell.x * s + (s - gw) * 0.5,
					cell.y * s + (s - gh) * 0.5 - s * 0.18)
	var tag: Label = tile["tag"]
	tag.position = Vector2(0, _tile + 4)
	tag.size = Vector2(_tile, 20)
	var lord: Label = tile["lord"]
	lord.position = Vector2(0, _tile + 25)
	lord.size = Vector2(_tile, 16)


## 只有当前关被点亮；已封卷压暗、预告更淡、剪影只剩轮廓。
func _refresh_tile_states() -> void:
	for slot in _tiles_by_slot.keys():
		var t: Dictionary = _tiles_by_slot[int(slot)]
		var lv := int(t["level"])
		var board: Rubbing = t["board"]
		board.cleared = lv < _current
		board.current = lv == _current
		board.preview = lv > _current and not board.silhouette
		board.selected = lv == _focused
		var root: Control = t["root"]
		root.modulate = Color(1, 1, 1, 1.0) if not board.preview else Color(0.74, 0.76, 0.82, 0.72)
		(t["tag"] as Label).add_theme_color_override("font_color",
				UIKit.C_EMPHASIS if lv == _current
				else (UIKit.C_NUM if lv < _current else UIKit.C_TEXT_FAINT))


func _tile_for(level: int) -> Dictionary:
	for slot in _tiles_by_slot.keys():
		if int(_tiles_by_slot[int(slot)]["level"]) == level:
			return _tiles_by_slot[int(slot)]
	return {}


func _lord_name(deck: Array, sil: bool) -> String:
	if sil or deck.is_empty():
		return "尚未展开"
	var best := ""
	var best_rank := -1
	for id in deck:
		var r := MatchLevelDeck.raw_rank(String(id))
		if r > best_rank:
			best_rank = r
			best = _boss_name(String(id))
	return "阵眼 · %s" % best


## 取名口径与对局里那份 `_boss_name` 一致：先 WorldDB，取不到再回图鉴条目。
## 棋坛的卡池含四位大陆核心首领，它们不在 WorldDB.BOSS 表里，只有图鉴有名字。
func _boss_name(boss_id: String) -> String:
	var nm := String(WorldDB.get_boss_name(boss_id))
	if nm != "" and nm != boss_id:
		return nm
	var e: Dictionary = CodexDB.boss_entry(boss_id)
	return String(e.get("name", boss_id))


func _fallback_portrait() -> Texture2D:
	return UIKit.ui_texture("res://assets/ui/facility_ui/dot_soft.png")


# ===================== 拓印本体 =====================
## 6×6 网格 + 墨印底。画在一个自绘 Control 上，不铺 36 个节点：
## 一屏十几枚拓印 × 36 格 = 五百多个只用来画线的节点，不如一次 draw_rect。
class Rubbing extends Control:
	var cell := 50.0
	var stone_cells: Array[Vector2i] = []
	var cleared := false
	var current := false
	var preview := false
	var selected := false
	var silhouette := false
	## 斜纹面纱：表达"这 6 张的正反面你还不知道"。
	## 快速模式下关掉 —— 那时反面已经逐张画成牌背了，两层语言会打架。
	var veil := true
	## 6×6 网格线。**普通模式关掉**（2026-11-05 用户拍定）：
	## 没有格子，6 张牌就不会被读成"阵型"；拓片本体、朱砂印角、卷边都照旧。
	var grid := true

	func set_stone(i: int, c: Vector2i) -> void:
		while stone_cells.size() <= i:
			stone_cells.append(Vector2i(-1, -1))
		stone_cells[i] = c

	func stone_cell(i: int) -> Vector2i:
		return stone_cells[i] if i < stone_cells.size() else Vector2i(0, 0)

	func _draw() -> void:
		if silhouette:
			_draw_rolled()
			return
		_draw_rubbing()

	## 拓片本体：一块压进绢面的墨印。
	## 边缘故意叠三层略微内缩的墨，做出拓石/拓绢那种吃墨不匀的毛边；
	## 投影一律往右下 —— 和 UIKit.LIGHT_FROM 的左上光源对得上。
	func _draw_rubbing() -> void:
		var w := size.x
		var h := size.y
		var sh := Vector2(3.0, 5.0) if current else Vector2(2.0, 3.0)
		var sh_a := 0.42 if current else 0.26
		draw_rect(Rect2(sh + Vector2(5, 5), size - Vector2(10, 10)),
				Color(0.0, 0.0, 0.0, sh_a * 0.35), false, 7.0)
		draw_rect(Rect2(sh, size), Color(0.0, 0.0, 0.0, sh_a * 0.45))

		# 墨色分档：已封卷吃墨最足（冷墨）、当前关最暖最实、预告只上一层淡墨灰
		var ink := Color(0.078, 0.074, 0.066)
		if current:
			ink = Color(0.106, 0.092, 0.068)
		elif preview:
			ink = Color(0.060, 0.062, 0.070)
		draw_rect(Rect2(Vector2.ZERO, size), ink)
		for i in 3:
			var inset := float(i) * 1.7
			draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset * 2.0, inset * 2.0)),
					Color(ink.r + 0.024, ink.g + 0.020, ink.b + 0.014, 0.28 - i * 0.085), false, 2.0)

		if grid:
			_draw_grid(Color(0.80, 0.74, 0.58, 0.13 if not current else 0.26), w, h)
		if veil:
			_draw_orientation_veil(w, h)

		# 卷边：当前关才给一圈暖亮边，其余只是压暗的纸
		if current:
			draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)),
					Color(0.90, 0.80, 0.55, 0.55), false, 1.0)
		else:
			draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2(1, 1)),
					Color(0.60, 0.56, 0.46, 0.18 if not preview else 0.09), false, 1.0)
		# 已封卷压一枚朱砂印角：一眼分得开"打过的"，
		# 又不用往卷上贴一个「已通关」的文字标签
		if cleared:
			_draw_seal(Vector2(w - 24.0, h - 24.0), 20.0)
		if selected:
			draw_rect(Rect2(Vector2(-3, -3), size + Vector2(6, 6)),
					Color(0.94, 0.86, 0.62, 0.34), false, 2.0)

	## 剪影 = 还没展开的那一截卷：一根横卧在绢面上的纸轴。
	## 原来画成一个黑框，玩家读成"这格贴图没加载出来"；
	## 卷起来才符合"卷还在往右长"的母题，也顺带解释了这里为什么没有拓印。
	## ⚠ 圆柱的**长度是恒定的**，只有明暗随截面弯过去 ——
	##   第一版把截面半径同时当成宽用，画出来是一枚正对镜头的黑圆盘。
	func _draw_rolled() -> void:
		var w := size.x
		var h := size.y
		var cx := w * 0.5
		var cy := h * 0.46
		var half_len := w * 0.30          # 轴身半长（横向，恒定）
		var ry := h * 0.20                # 截面半径（纵向，决定这截卷有多粗）
		var rows := 16
		for i in rows:
			var t := float(i) / float(rows - 1)          # 0 上沿 → 1 下沿
			var yy := cy - ry + t * ry * 2.0
			# 左上来的光：最亮带在偏上一点，往下渐暗，下沿回一点点反光
			var lit := clampf(1.0 - absf(t - 0.34) * 2.1, 0.0, 1.0)
			var v := 0.052 + 0.050 * lit
			draw_line(Vector2(cx - half_len, yy), Vector2(cx + half_len, yy),
					Color(v + 0.014, v + 0.011, v * 0.94, 1.0), float(ry * 2.0) / float(rows) + 1.2)
		# 两端轴头：深色木塞，压在轴身上
		for side in [-1.0, 1.0]:
			var hx: float = cx + float(side) * half_len
			draw_rect(Rect2(Vector2(hx - 6.0, cy - ry * 1.10), Vector2(12.0, ry * 2.20)),
					Color(0.050, 0.038, 0.028, 0.96))
			draw_rect(Rect2(Vector2(hx - 6.0, cy - ry * 1.10), Vector2(12.0, ry * 2.20)),
					Color(0.62, 0.50, 0.32, 0.18), false, 1.0)
		# 影子落在绢面上：这截是真的搁在卷上，不是画上去的框
		draw_rect(Rect2(Vector2(cx - half_len + 6.0, cy + ry * 1.06),
				Vector2(half_len * 2.0 - 12.0, 10.0)), Color(0.0, 0.0, 0.0, 0.32))

	func _draw_seal(center: Vector2, r: float) -> void:
		var rect := Rect2(center - Vector2(r, r) * 0.5, Vector2(r, r))
		draw_rect(rect, Color(0.60, 0.15, 0.12, 0.70))
		draw_rect(Rect2(rect.position + Vector2(2, 2), rect.size - Vector2(4, 4)),
				Color(0.86, 0.34, 0.27, 0.30), false, 1.0)

	func _draw_grid(col: Color, w: float, h: float) -> void:
		for i in range(MatchDB.BOARD_COLS + 1):
			var gx := float(i) / float(MatchDB.BOARD_COLS) * w
			draw_line(Vector2(gx, 0), Vector2(gx, h), col, 1.0)
			var gy := float(i) / float(MatchDB.BOARD_ROWS) * h
			draw_line(Vector2(0, gy), Vector2(w, gy), col, 1.0)

	## 朝向未定的记号：一道自左上斜向右下的薄纱。
	## ⚠ 不许写成「朝向未知」这类字 —— 六张牌的身份全都要摊开给玩家看（那是关卡制的
	##   立身之本），未定的只有正/反，所以用一层**统一**的图形面纱表达，
	##   不给任何一张单独加标记（加了就会被读成"这张特别可疑"）。
	func _draw_orientation_veil(w: float, h: float) -> void:
		var a := Color(0.86, 0.88, 0.96, 0.055)
		var b := Color(0.86, 0.88, 0.96, 0.012)
		for i in 3:
			var off := float(i) * h * 0.06
			draw_line(Vector2(off, 0), Vector2(w * 0.5 + off, h * 0.5), a, 1.0)
			draw_line(Vector2(w * 0.5 + off, h * 0.5), Vector2(w + off, h), b, 1.0)
