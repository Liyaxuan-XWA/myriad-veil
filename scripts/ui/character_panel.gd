extends CanvasLayer
## 角色信息面板 —— Tab 键随时开关（C 已让给战斗内重开）
## 演武场训练模式会额外监听 panel_closed，在关闭后刷新战斗角色的属性缓存。
## 左半：基础数值 / 境界 / 装备 / 功法
## 右半：随身背包（分类筛选 + 点击查看详情）
##
## 设计要点：
## 1. 作为 autoload 常驻 root，任何场景（原初位面 / 战斗）都能打开，无需改场景树
## 2. 打开时暂停游戏（get_tree().paused），避免战斗中查看时继续挨打；
##    面板自身 process_mode 设为 ALWAYS，否则暂停后收不到按键、关不掉
## 3. 用 _input 而非 _unhandled_input：autoload 节点先于场景节点收到 _input，
##    才能在暂停时抢先吃掉 ESC（战斗里 ESC 是"返回原初位面"，否则会同时触发）
## 4. UI 全部代码构建，不依赖 tscn

const VIEW_W := 1280.0
const VIEW_H := 720.0
const PANEL_W := 1160.0
const PANEL_H := 660.0

## 自身脚本引用：内部类（BagSlot / EquipSlot）需要调用本文件定义的静态工具函数，
## 而本文件没有 class_name，只能靠这个常量拿到脚本对象。
const SELF := preload("res://scripts/ui/character_panel.gd")

const GRID_COLS := 6
const MIN_BAG_SLOTS := 24

## 关闭时通知外部（演武场用来刷新战斗角色的装备属性与法宝栏）
signal panel_closed

# 统一取 UIKit，换皮时与其余面板一起生效
const ACCENT := UIKit.C_ACCENT
const DIM_TEXT := UIKit.C_TEXT_DIM

var _visible := false
## 是否已登记进 GameState 的模态计数（_show → true，_hide → false）
## ⚠ 顺序任务面板靠这个计数决定藏不藏，漏登记它就浮在背包上层
var _modal_counted := false
## 当前分背包页签（丹药 / 材料 / 装备 / 法宝）；「全部」已按 2026-11-02 用户要求去掉
var _filter: String = CharacterData.ITEM_PILL
var _selected_index := -1

var _dim: ColorRect
var _root: PanelContainer

var _realm_label: Label
var _realm_bar: ProgressBar
## 卷首副标题：随境界刷新
var _header_sub: Label
var _realm_note: Label
## 境界 / 突破入口：修为圆满时做呼吸式提醒（2026-10-24 用户定）
var _realm_btn: Button
## 属性区容器：每个分类一个独立网格，避免分组标题挤占网格单元格
var _stats_box: VBoxContainer
var _equip_box: GridContainer
var _skill_box: VBoxContainer
var _bag_count: Label
var _bag_grid: GridContainer
var _sort_btn: Button
## 详情区固定高度 + 内部滚动：内容再长也不挤压上方背包网格
var _detail_scroll: ScrollContainer
var _detail: Label
var _detail_actions: HBoxContainer
var _filter_buttons: Array = []

## ===== 一键丢弃（多选批量）=====
## 点「一键丢弃」进入多选模式 → 点击背包装备切换选中 → 再点一次执行批量丢弃
## 选中存**字典引用**（不是下标），背包重组后不会张冠李戴
var _discard_mode := false
var _discard_sel: Array = []
var _discard_btn: Button
## 战斗轮盘装配条（六个格子按钮）
var _wheel_row: HBoxContainer
## 试炼之路的「不许开」提示（复用同一个 Label，连按 Tab 不会堆一屏）
## 试炼里 Tab 打开的局内行囊（只读写 RogueRun，不碰局外档）
var _rogue_gear_panel: RogueGearPanel = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_build_ui()
	_set_root_visible(false)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# Tab 在 Godot 里默认用于 UI 焦点切换，必须先消费事件再处理，否则焦点会被移走
	if event.physical_keycode == KEY_TAB:
		get_viewport().set_input_as_handled()
		# BOSS 入场卡期间不打开角色面板：面板关闭时会无条件解除暂停
		if get_tree().get_first_node_in_group("boss_intro") != null:
			return
		# 试炼之路：Tab 打开「试炼行囊」（局内装备/境界），不是局外角色面板
		if RogueRun.active:
			_open_rogue_gear()
			return
		_toggle()
	elif _visible and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_hide()


## 修为圆满时给「境界 / 突破」按钮做呼吸提醒；未圆满时恢复常态
func _process(_delta: float) -> void:
	if _realm_btn == null:
		return
	if not _visible or not CharacterData.has_breakthrough_pending():
		_realm_btn.modulate = Color.WHITE
		_realm_btn.scale = Vector2.ONE
		return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
	_realm_btn.modulate = Color.WHITE.lerp(Color(1.0, 0.48, 0.32, 1.0), 0.45 + 0.35 * pulse)
	_realm_btn.pivot_offset = _realm_btn.size * 0.5
	_realm_btn.scale = Vector2.ONE * (1.0 + 0.02 * pulse)


## 公开入口：触屏 HUD 的「背包」图标等外部调用（内部逻辑仍走 _toggle）
## ⚠ 别在外部直接改 _visible：_show/_hide 还要处理暂停、刷新、多选态清理
func toggle_panel() -> void:
	if RogueRun.active:
		_open_rogue_gear()
		return
	_toggle()


func open_panel() -> void:
	if _visible:
		return
	# ⚠ 外部调用（HUD 背包图标 / 演武场按钮）也要走同一条路，
	#   否则只拦 Tab 会留一个能碰到局外档的后门
	if RogueRun.active:
		_open_rogue_gear()
		return
	_show()


## ===== 试炼之路：Tab → 局内行囊 =====
## ⚠ 局外角色面板在试炼里**仍然锁住**（rogue_lock 也拦着数据层接口），
##   Tab 改为打开 RogueGearPanel —— 它只读写 RogueRun 的局内容器，
##   装备/境界都不会带出局外，也不影响局外的穿戴与修为。
func _open_rogue_gear() -> void:
	if _rogue_gear_panel != null and is_instance_valid(_rogue_gear_panel):
		return
	var panel := RogueGearPanel.new()
	_rogue_gear_panel = panel
	panel.closed.connect(func(): _rogue_gear_panel = null)
	get_tree().root.add_child(panel)
	panel.open()


func close_panel() -> void:
	if _visible:
		_hide()


func is_open() -> bool:
	return _visible


func _toggle() -> void:
	if _visible:
		_hide()
	else:
		_show()


func _show() -> void:
	# 轮盘开着时先收轮盘：两者都改 get_tree().paused，叠在一起会互相顶掉暂停状态
	if BattleWheel.is_open():
		BattleWheel._close()
	_visible = true
	# 每次打开面板都退出多选模式（避免上次残留的选中态）
	_discard_mode = false
	_discard_sel.clear()
	_update_discard_btn()
	_refresh()
	_set_root_visible(true)
	get_tree().paused = true
	# 模态计数：任务面板(118)比角色面板(100)高，不登记就会浮在背包上面
	if not _modal_counted:
		_modal_counted = true
		GameState.push_modal_ui(self)
	# 新手指引：背包算「已看过」，红点清零 + 推进 c1_bag
	Tutorial.mark_seen("bag")
	Tutorial.note("bag_opened")


func _hide() -> void:
	if not _visible:
		return
	_visible = false
	_set_root_visible(false)
	get_tree().paused = false
	if _modal_counted:
		_modal_counted = false
		GameState.pop_modal_ui(self)
	panel_closed.emit()


## 打开境界面板：先自行关闭（恢复暂停），再交由 SystemPanel 接管
func _on_open_realm() -> void:
	_hide()
	var script = load("res://scripts/ui/panels/realm_panel.gd")
	if script == null:
		return
	var panel := script.new() as SystemPanel
	if panel == null:
		return
	get_tree().root.add_child(panel)
	panel.open()


func _set_root_visible(v: bool) -> void:
	_root.visible = v
	_dim.visible = v


# ===================== UI 构建 =====================

func _build_ui() -> void:
	# 全屏遮罩：半透明 + 拦截点击，避免穿透点到场景里的设施/角色
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.0, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_root = PanelContainer.new()
	_root.position = Vector2((VIEW_W - PANEL_W) * 0.5, (VIEW_H - PANEL_H) * 0.5)
	_root.size = Vector2(PANEL_W, PANEL_H)
	add_child(_root)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.11, 0.97)
	style.border_color = Color(0.42, 0.35, 0.22, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	_root.add_theme_stylebox_override("panel", style)
	UIKit.apply_panel_frame(_root)

	# 低透明度大字水印：不占布局、不吃鼠标
	var wm_layer := Control.new()
	wm_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wm_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(wm_layer)
	var wm := UIKit.label("侠", 230, Color(0.95, 0.82, 0.45, 0.035))
	wm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wm.anchor_left = 1.0
	wm.anchor_top = 1.0
	wm.anchor_right = 1.0
	wm.anchor_bottom = 1.0
	wm.offset_left = -300.0
	wm.offset_top = -300.0
	wm.offset_right = -20.0
	wm.offset_bottom = -6.0
	wm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wm.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	wm_layer.add_child(wm)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_root.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	vbox.add_child(_build_header())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

	body.add_child(_build_left_column())

	var sep := VSeparator.new()
	body.add_child(sep)

	body.add_child(_build_right_column())


func _build_header() -> Control:
	var banner := Control.new()
	banner.custom_minimum_size = Vector2(0, 46)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := TextureRect.new()
	bg.texture = UIKit.horizontal_gradient(
		Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.22),
		Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.0))
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(bg)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_bottom = -1
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(row)

	row.add_child(UIKit.facility_disc({"accent": ACCENT, "glyph": "侠"}, 34))

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(titles)
	var title := UIKit.label("角色玉简", 20, Color(0.98, 0.94, 0.84))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_child(title)
	_header_sub = UIKit.label("一身所学 · 尽在此卷", 10,
		Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.82))
	_header_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_child(_header_sub)

	row.add_child(UIKit.spacer())

	var hint := UIKit.label("Tab 键开关 · ESC 关闭", 10,
		Color(0.68, 0.70, 0.76, 0.92))
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hint)
	var close_btn := UIKit.button("关闭", Vector2(72, 30))
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(_hide)
	row.add_child(close_btn)

	return banner


func _build_left_column() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.custom_minimum_size = Vector2(430, 0)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 6)
	scroll.add_child(inner)

	# --- 境界 ---
	_add_section(inner, "境界")
	_realm_label = Label.new()
	_realm_label.add_theme_font_size_override("font_size", 15)
	inner.add_child(_realm_label)

	_realm_bar = ProgressBar.new()
	_realm_bar.min_value = 0.0
	_realm_bar.max_value = 100.0
	_realm_bar.show_percentage = false
	_realm_bar.custom_minimum_size = Vector2(0, 14)
	inner.add_child(_realm_bar)

	_realm_note = Label.new()
	UIKit.set_readable_font(_realm_note, 12)
	_realm_note.add_theme_color_override("font_color", DIM_TEXT)
	inner.add_child(_realm_note)

	# 境界系统入口：先关角色面板再开境界面板，避免两个面板叠加导致暂停状态混乱
	_realm_btn = UIKit.button("境界 / 突破", Vector2(150, 32))
	_realm_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UIKit.set_click_sfx(_realm_btn, "ui_confirm")
	_realm_btn.pressed.connect(_on_open_realm)
	inner.add_child(_realm_btn)

	# --- 装备（穿戴槽位）---
	# 放在属性上方：玩家点开面板最先关心「我穿了什么」，再看数值
	_add_section(inner, "穿戴装备")
	var slot_note := Label.new()
	slot_note.text = "把背包中的装备拖到对应部位格子即可穿戴（也可点选后按「穿戴」）"
	UIKit.set_readable_font(slot_note, 11)
	slot_note.add_theme_color_override("font_color", DIM_TEXT)
	slot_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(slot_note)

	# 六个部位格子：武器 / 护甲 / 鞋子 / 饰品×3
	# 左栏宽度有限，用 3 列两行，避免 6 个格子横排放不下
	_equip_box = GridContainer.new()
	_equip_box.columns = 3
	_equip_box.add_theme_constant_override("h_separation", 8)
	_equip_box.add_theme_constant_override("v_separation", 8)
	inner.add_child(_equip_box)

	# --- 属性 ---
	_add_section(inner, "属性")
	_stats_box = VBoxContainer.new()
	_stats_box.add_theme_constant_override("separation", 4)
	inner.add_child(_stats_box)

	var note := Label.new()
	note.text = "（力量→物理攻击力，法强→法术攻击力；最终伤害 = 攻击力 × 技能系数 × 增益/削弱 × 敌方抗性）"
	UIKit.set_readable_font(note, 11)
	note.add_theme_color_override("font_color", DIM_TEXT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(note)

	# --- 功法 ---
	_add_section(inner, "功法")
	_skill_box = VBoxContainer.new()
	_skill_box.add_theme_constant_override("separation", 3)
	inner.add_child(_skill_box)

	return col


func _build_right_column() -> Control:
	var col := VBoxContainer.new()
	# 6px：给背包网格多留一行高度（详情区固定后会吃掉一部分竖向空间）
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.custom_minimum_size = Vector2(600, 0)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)

	var seal_tex := UIKit.ui_texture(UIKit.TEX_SEAL_MARK)
	if seal_tex != null:
		var seal := TextureRect.new()
		seal.texture = seal_tex
		seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		seal.custom_minimum_size = Vector2(15, 15)
		seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		seal.modulate = Color(1, 1, 1, 0.9)
		seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(seal)
	var title := UIKit.label("随身背包", 18, Color(0.97, 0.93, 0.84))
	head.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)

	_bag_count = Label.new()
	_bag_count.add_theme_font_size_override("font_size", 13)
	_bag_count.add_theme_color_override("font_color", DIM_TEXT)
	head.add_child(_bag_count)

	# 「一键整理」：装备 → 丹药 → 材料，同类品质高在前
	_sort_btn = UIKit.button("一键整理", Vector2(96, 26))
	_sort_btn.tooltip_text = "按装备 / 法宝 / 丹药 / 材料归类，同类品质高的排在前面"
	_sort_btn.pressed.connect(_on_sort_bag_pressed)
	head.add_child(_sort_btn)

	# 「一键丢弃」并入标题行：独立一行会白占 27px，把背包网格挤掉半行
	_discard_btn = UIKit.danger_button("一键丢弃", Vector2(96, 26))
	_discard_btn.tooltip_text = "第一次点击进入多选，第二次点击丢弃选中的物品（突破材料除外）"
	_discard_btn.pressed.connect(_on_discard_mode_pressed)
	head.add_child(_discard_btn)

	# 分类筛选
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 6)
	col.add_child(filter_row)

	# 四个分背包各算各的格子，不再提供「全部」混排视图（2026-11-02 用户定）
	var filters := [
		["丹药", CharacterData.ITEM_PILL],
		["材料", CharacterData.ITEM_MATERIAL],
		["装备", CharacterData.ITEM_EQUIPMENT],
		["法宝", CharacterData.ITEM_TREASURE],
	]
	for f in filters:
		var btn := UIKit.tab_button(f[0], Vector2(64, 28))
		UIKit.set_click_sfx(btn, "ui_tab")
		UIKit.set_tab_selected(btn, f[1] == _filter)
		btn.pressed.connect(_on_filter_pressed.bind(f[1], btn))
		filter_row.add_child(btn)
		_filter_buttons.append([btn, f[1]])

	# 战斗轮盘装配条（2026-10-24）：丹药 3 格 + 符箓 3 格，点格子卸下
	# 装配入口在物品详情里（选中丹药/符箓 →「装入轮盘」）
	var wheel_head := HBoxContainer.new()
	wheel_head.add_theme_constant_override("separation", 6)
	col.add_child(wheel_head)
	var wheel_title := Label.new()
	wheel_title.text = "战斗轮盘（战斗中按 G）"
	UIKit.set_readable_font(wheel_title, 12)
	wheel_title.add_theme_color_override("font_color", ACCENT)
	wheel_head.add_child(wheel_title)
	var wheel_spacer := Control.new()
	wheel_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wheel_head.add_child(wheel_spacer)
	var wheel_hint := Label.new()
	wheel_hint.text = "点格子卸下"
	UIKit.set_readable_font(wheel_hint, 11)
	wheel_hint.add_theme_color_override("font_color", DIM_TEXT)
	wheel_head.add_child(wheel_hint)

	_wheel_row = HBoxContainer.new()
	_wheel_row.add_theme_constant_override("separation", 6)
	col.add_child(_wheel_row)

	# 背包网格
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	_bag_grid = GridContainer.new()
	_bag_grid.columns = GRID_COLS
	_bag_grid.add_theme_constant_override("h_separation", 6)
	_bag_grid.add_theme_constant_override("v_separation", 6)
	_bag_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_bag_grid)

	# 详情：**固定高度 + 内部滚动**（用户 2026-10-24 报：点装备详情会把背包格子压扁）
	# 装备详情有 10+ 行，如果让 Label 自己撑高，上方网格会从 4 行缩到 2 行；
	# 固定在 150px 后无论点什么，背包可视区都不再变化。
	# 省出的竖向空间来自：「一键丢弃」并入标题行 + 取消独立的「详情」小节标题。
	var detail_box := PanelContainer.new()
	detail_box.custom_minimum_size = Vector2(0, 146)
	detail_box.add_theme_stylebox_override("panel",
		UIKit.accent_card_style(ACCENT, 0.52, 0.22, 6))
	col.add_child(detail_box)

	var detail_margin := MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", 6)
	detail_margin.add_theme_constant_override("margin_right", 6)
	detail_margin.add_theme_constant_override("margin_top", 4)
	detail_margin.add_theme_constant_override("margin_bottom", 4)
	detail_box.add_child(detail_margin)

	_detail_scroll = ScrollContainer.new()
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_margin.add_child(_detail_scroll)

	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", 13)
	UIKit.make_readable(_detail)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 新手指引：材料详情里有「合成指引」，锚点挂在这个详情框上
	_detail.set_meta("tut", "forge.material")
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.text = "点击物品查看详情"
	_detail.add_theme_color_override("font_color", DIM_TEXT)
	_detail_scroll.add_child(_detail)

	# 详情操作区固定 30px：按钮出现/消失不再改变整体高度
	_detail_actions = HBoxContainer.new()
	_detail_actions.add_theme_constant_override("separation", 8)
	_detail_actions.custom_minimum_size = Vector2(0, 30)
	col.add_child(_detail_actions)

	return col


# ===================== 刷新 =====================

func _refresh() -> void:
	_refresh_realm()
	_refresh_stats()
	_refresh_equipment()
	_refresh_skills()
	_refresh_wheel_row()
	_refresh_bag()
	# 每次打开清空详情操作区，避免上次遗留的按钮指向已失效的背包下标
	_rebuild_detail_actions({}, -1, false)


func _refresh_realm() -> void:
	var d := CharacterData
	var stage_suffix := "" if d.is_huashen() else " " + d.get_realm_stage_name()
	_realm_label.text = "%s · %s%s" % [d.character_name, d.current_realm, stage_suffix]
	if _header_sub != null:
		_header_sub.text = "%s · %s%s" % [d.character_name, d.current_realm,
			"" if d.is_huashen() else d.get_realm_stage_name()]
	_realm_bar.value = d.get_stage_exp_ratio() * 100.0
	if d.is_huashen():
		_realm_note.text = "已至化神 · 修为上限 %d，无法继续突破" % d.HUASHEN_EXP_CAP
		return
	var next := d.get_next_stage_name() if not d.is_final_stage() else d.get_next_realm()
	var note := "%s：%s　修为：%d / %d" % [
		"下一阶段" if not d.is_final_stage() else "下一境界",
		next if next != "" else "—",
		d.realm_exp, d.get_stage_exp_required(),
	]
	note += "　位面境界上限：%s" % d.current_world_realm_limit
	if d.is_realm_capped():
		note += "（已达当前位面上限）"
	_realm_note.text = note


## 属性区：按 AttributeDB 的分类逐项展示
## 每项显示「基础/装备/法宝/临时」四层来源的合成结果，
## 有额外来源时在括号里标出，方便判断装备是否生效。
func _refresh_stats() -> void:
	_clear_children(_stats_box)
	var d := CharacterData

	for cat in AttributeDB.CATEGORIES:
		_add_stats_header(String(cat.get("name", "")))
		var grid := _new_stats_grid()
		for id in AttributeDB.ids_in_category(String(cat.get("id", ""))):
			_add_attribute_row(grid, String(id))

	# ---- 派生战斗数值（由属性推导，不是独立属性）----
	_add_stats_header("派生数值")
	var g2 := _new_stats_grid()
	_add_stat_row(g2, "物理攻击力", "%.1f" % d.physical_attack())
	_add_stat_row(g2, "法术攻击力", "%.1f" % d.spell_attack())
	_add_stat_row(g2, "普攻间隔", "%.2f s" % d.attack_interval())
	_add_stat_row(g2, "普攻伤害", "≈ %.1f" % d.calc_physical_damage(false, false, false))
	_add_stat_row(g2, "终结技伤害", "≈ %.1f" % d.calc_physical_damage(true, false, false))
	_add_stat_row(g2, "闪避速度", "%.0f" % d.base_dodge_speed)
	_add_stat_row(g2, "闪避冷却", "%.2f s" % d.dodge_cooldown)
	_add_stat_row(g2, "弹刀窗口", "%.2f s" % d.parry_window)


## 新建一组属性网格：4 列 =「名称 数值 名称 数值」，一行放两条，纵向省一半
## 每个分类单独一个网格 —— 旧实现把分组标题也塞进网格，会把后续行挤错位
func _new_stats_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)
	_stats_box.add_child(grid)
	return grid


## 分类小标题（整行，不参与网格布局）
func _add_stats_header(text: String) -> void:
	if text == "":
		return
	var row := UIKit.hbox(6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := ColorRect.new()
	bar.color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.75)
	bar.custom_minimum_size = Vector2(2, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	row.add_child(UIKit.label(text, 11, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.94)))
	var line := TextureRect.new()
	line.texture = UIKit.horizontal_gradient(
		Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.18),
		Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.0))
	line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	line.stretch_mode = TextureRect.STRETCH_SCALE
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	_stats_box.add_child(row)


## 单条属性：紧凑显示总值 + 外部加成合计数，完整来源拆解放进 tooltip
## （避免长文案把 4 列网格撑爆）
func _add_attribute_row(grid: GridContainer, attr_id: String) -> void:
	var d := CharacterData
	var bd := d.attribute_breakdown(attr_id)
	var total := float(bd.get("total", 0.0))
	var base := float(bd.get("base", 0.0))
	var realm := float(bd.get("realm", 0.0))
	var eq := float(bd.get("equipment", 0.0))
	var tr := float(bd.get("treasure", 0.0))
	var flat := float(bd.get("mod_flat", 0.0))
	var base_add := float(bd.get("mod_base", 0.0))
	var mult := float(bd.get("mod_mult", 1.0))

	var text := AttributeDB.format_value(attr_id, total)
	# 抗性额外标出实际减免率（递减公式，玩家更关心减了多少）
	if attr_id.begins_with("resist_"):
		text += "（减 %.0f%%）" % (AttributeDB.resist_reduction(total) * 100.0)
	# 有外部加成时给个简短标记，具体来源看 tooltip
	# ⚠ 百分比词条行（_pct）不加标记：值本身带 %，再加 " +1" 会变成 "+1.0% +1" 很怪
	var ext := realm + eq + tr + flat + base_add
	if not is_zero_approx(ext) and not AttributeDB.is_percent(attr_id):
		text += " %+d" % int(round(ext))

	var tip := "基础 %s" % AttributeDB.format_value(attr_id, base)
	if not is_zero_approx(realm):
		tip += "　境界 %s" % AttributeDB.format_value(attr_id, realm)
	if not is_zero_approx(eq):
		tip += "　装备 %s" % AttributeDB.format_value(attr_id, eq)
	if not is_zero_approx(tr):
		tip += "　法宝 %s" % AttributeDB.format_value(attr_id, tr)
	if not is_zero_approx(flat):
		tip += "　临时 %s" % AttributeDB.format_value(attr_id, flat)
	if not is_zero_approx(base_add):
		tip += "　本体加成 %s" % AttributeDB.format_value(attr_id, base_add)
	if not is_zero_approx(mult - 1.0):
		tip += "　倍率 ×%.2f" % mult
	# 百分比增幅词条（_pct）在基础属性上的乘区，写进基础属性行的 tooltip
	var pct := float(bd.get("pct_total", 0.0))
	if not is_zero_approx(pct):
		tip += "　增幅 %s" % AttributeDB.format_value(attr_id + "_pct", pct)

	_add_stat_row(grid, AttributeDB.attr_name(attr_id), text, tip)


## 属性表格的一格：名称 + 数值（各占两列，两对拼成一行）
func _add_stat_row(grid: GridContainer, key: String, value: String, tip: String = "") -> void:
	var k := Label.new()
	k.text = key
	UIKit.set_readable_font(k, 12)
	k.add_theme_color_override("font_color", DIM_TEXT)
	k.custom_minimum_size = Vector2(62, 0)
	if tip != "":
		k.tooltip_text = tip
	grid.add_child(k)

	var v := Label.new()
	v.text = value
	UIKit.set_readable_font(v, 12)
	v.custom_minimum_size = Vector2(104, 0)
	if tip != "":
		v.tooltip_text = tip
	grid.add_child(v)


## 六个部位格子（武器 / 护甲 / 鞋子 / 饰品×3）
## 空格子显示部位名 + 淡边框；有装备显示品阶色块 + 名称 + 属性加成
## 格子本身是拖放目标（见 EquipSlot 内部类）
func _refresh_equipment() -> void:
	_clear_children(_equip_box)
	var d := CharacterData
	# 装备 6 槽 + 法宝 3 槽统一显示（法宝已并入装备体系）
	for slot in d.WORN_SLOT_ORDER:
		var cell := EquipSlot.new()
		cell.setup(slot, self)
		_equip_box.add_child(cell)


## 由 EquipSlot 拖放完成后回调：刷新整块面板
func on_slot_changed(message: String, ok: bool) -> void:
	# 穿脱会重组背包 → 退出多选模式，避免选中集合混入已穿上的装备
	_discard_mode = false
	_discard_sel.clear()
	_update_discard_btn()
	_refresh_equipment()
	_refresh_stats()
	_refresh_bag()
	_selected_index = -1
	_detail.text = message
	_detail.add_theme_color_override("font_color", UIKit.C_OK if ok else UIKit.C_WARN)
	_clear_children(_detail_actions)


func _refresh_skills() -> void:
	_clear_children(_skill_box)
	var d := CharacterData
	_add_skill_line("主动功法", d.active_skill_loadout)
	_add_skill_line("被动功法", d.passive_skill_loadout)
	if d.learned_skills.is_empty():
		var empty := Label.new()
		empty.text = "已习得：0（开局零功法，唯一来源为万界塔首杀感悟）"
		UIKit.set_readable_font(empty, 11)
		empty.add_theme_color_override("font_color", DIM_TEXT)
		_skill_box.add_child(empty)


func _add_skill_line(title: String, loadout: Array) -> void:
	var line := Label.new()
	line.add_theme_font_size_override("font_size", 13)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if loadout.is_empty():
		line.text = "%s：——" % title
		line.add_theme_color_override("font_color", DIM_TEXT)
	else:
		var names: Array[String] = []
		for sid in loadout:
			if String(sid) == "":
				continue
			names.append(SkillDB.get_skill_name(String(sid)))
		line.text = "%s：%s" % [title, "、".join(names)] if not names.is_empty() else "%s：——" % title
		line.add_theme_color_override("font_color", ACCENT)
	_skill_box.add_child(line)


# ===================== 战斗轮盘装配 =====================

const QUICK_SLOT_LABELS: Dictionary = {
	"pill_1": "药 1", "pill_2": "药 2", "pill_3": "药 3",
}


## 装配条：丹药 3 格 + 符箓 3 格，已装的直接显示道具名
func _refresh_wheel_row() -> void:
	if _wheel_row == null:
		return
	_clear_children(_wheel_row)
	for raw in CharacterData.QUICK_SLOT_ORDER:
		var sid := String(raw)
		var iid := CharacterData.quick_item_id(sid)
		var text := String(QUICK_SLOT_LABELS.get(sid, sid))
		if iid != "":
			text += " " + _consumable_name(iid)
		var btn := UIKit.button(text, Vector2(93, 26))
		UIKit.set_readable_font(btn, 10)
		btn.disabled = iid == ""
		if iid != "":
			# 轮盘装配格也标品质（格子是按钮皮肤，用文字色表达，不另画边框）
			btn.add_theme_color_override("font_color",
				ItemDB.rarity_color(String(ItemDB.get_consumable(iid).get("rarity", "common"))))
		btn.tooltip_text = "点一下从轮盘卸下" if iid != "" else "选中丹药 / 符箓后点「装入轮盘」"
		btn.pressed.connect(_on_wheel_slot_pressed.bind(sid))
		_wheel_row.add_child(btn)


func _on_wheel_slot_pressed(slot_id: String) -> void:
	var iid := CharacterData.quick_item_id(slot_id)
	if iid == "":
		return
	CharacterData.clear_quick_slot(slot_id)
	_refresh_wheel_row()
	_detail.text = "已从轮盘卸下「%s」" % _consumable_name(iid)
	_detail.add_theme_color_override("font_color", UIKit.C_WARN)


func _on_wheel_assign_pressed(item: Dictionary, slot_id: String) -> void:
	var iid := String(item.get("id", ""))
	if not CharacterData.set_quick_slot(slot_id, iid):
		_detail.text = "装不进去：轮盘这一格放不了「%s」" % _consumable_name(iid)
		_detail.add_theme_color_override("font_color", UIKit.C_WARN)
		return
	_refresh_wheel_row()
	_detail.text = "已把「%s」装到轮盘 %s" % [
		_consumable_name(iid), String(QUICK_SLOT_LABELS.get(slot_id, slot_id))
	]
	_detail.add_theme_color_override("font_color", UIKit.C_OK)
	_rebuild_detail_actions(item, _inventory_index_of(item), false)


## 详情操作区：丹药的「装入 / 卸下轮盘」
func _rebuild_wheel_actions(item: Dictionary) -> void:
	var iid := String(item.get("id", ""))
	var itype := String(item.get("type", ""))
	var assigned := CharacterData.quick_slot_of(iid)
	var btn: Button
	if assigned != "":
		btn = UIKit.quiet_button("从轮盘卸下（%s）" % String(QUICK_SLOT_LABELS.get(assigned, assigned)),
			Vector2(160, 30), ACCENT)
		btn.pressed.connect(_on_wheel_slot_pressed.bind(assigned))
	else:
		var free := CharacterData.first_free_quick_slot(itype)
		if free == "":
			btn = UIKit.primary_button("轮盘已满（3 格）", Vector2(160, 30), ACCENT)
			btn.disabled = true
		else:
			btn = UIKit.primary_button("装入轮盘（%s）" % String(QUICK_SLOT_LABELS.get(free, free)),
				Vector2(160, 30), ACCENT)
			btn.pressed.connect(_on_wheel_assign_pressed.bind(item, free))
	_detail_actions.add_child(btn)


func _consumable_name(item_id: String) -> String:
	var def := ItemDB.get_consumable(item_id)
	if def.is_empty():
		return item_id
	return String(def.get("pill_name", def.get("talisman_name", item_id)))


# ===================== 背包 =====================

func _refresh_bag() -> void:
	_clear_children(_bag_grid)
	var d := CharacterData
	var items := d.get_items_by_type(_filter)

	# 占用按当前分背包算：法宝满了不影响丹药
	_bag_count.text = "%s占用 %d / %d 格" % [
		String(d.ITEM_TYPE_DISPLAY.get(_filter, "背包")),
		d.bag_count_for(_filter), d.bag_cap_for(_filter)]
	if _sort_btn != null:
		_sort_btn.disabled = d.inventory.is_empty()

	# 至少渲染 MIN_BAG_SLOTS 个格子，空位显示暗槽，便于看清网格布局
	var slots := maxi(MIN_BAG_SLOTS, ceili(items.size() / float(GRID_COLS)) * GRID_COLS)
	slots = mini(slots, d.bag_cap_for(_filter))

	for i in range(slots):
		if i < items.size():
			_bag_grid.add_child(_make_item_slot(items[i]))
		else:
			_bag_grid.add_child(_make_empty_slot())

	if items.is_empty():
		_detail.text = "背包空空如也"
		_detail.add_theme_color_override("font_color", DIM_TEXT)
		_selected_index = -1
		_clear_children(_detail_actions)
		_reset_detail_scroll()


## 背包格：用内部类 BagSlot（自带拖拽三件套）
## ⚠ 传入的是**背包真实下标**，不能用筛选后的显示下标，否则会穿错物品
func _make_item_slot(item: Dictionary) -> Control:
	var slot := BagSlot.new()
	# 背包格是按钮子类：点击音效统一挂（拖拽不会触发 pressed，只有真点才响）
	UIKit.attach_click_sfx(slot)
	slot.setup(item, _inventory_index_of(item), self)
	# 多选模式下恢复选中态（刷新背包后选中标记不能丢）
	slot.set_discard_selected(_is_discard_picked(item))
	return slot


## 该物品是否已在"一键丢弃"的选中集合里（按引用判定）
func _is_discard_picked(item: Dictionary) -> bool:
	for it in _discard_sel:
		if is_same(it, item):
			return true
	return false


## 按引用在背包里反查真实下标（筛选状态下标与背包下标不一致）
func _inventory_index_of(target: Dictionary) -> int:
	for i in range(CharacterData.inventory.size()):
		var it = CharacterData.inventory[i]
		if it is Dictionary and is_same(it, target):
			return i
	return -1


func _make_empty_slot() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(92, 56)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.13, 0.17, 0.85)
	style.border_color = Color(0.22, 0.22, 0.27, 1.0)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	return panel


## 一键整理：只重排数组，物品 / 快捷轮盘 / 穿戴槽都不受影响
func _on_sort_bag_pressed() -> void:
	if CharacterData.inventory.is_empty():
		return
	# 整理时退出多选，避免选中的引用与旧下标混淆
	_discard_mode = false
	_discard_sel.clear()
	_update_discard_btn()
	CharacterData.sort_inventory()
	_selected_index = -1
	_refresh_bag()
	_detail.text = "已整理背包：装备 → 法宝 → 丹药 → 材料（同类品质高的在前）"
	_detail.add_theme_color_override("font_color", UIKit.C_OK)
	_clear_children(_detail_actions)
	_reset_detail_scroll()


func _on_filter_pressed(filter: String, _btn: Button) -> void:
	_filter = filter
	for entry in _filter_buttons:
		var other: Button = entry[0]
		UIKit.set_tab_selected(other, String(entry[1]) == filter)
	_selected_index = -1
	# 切换筛选会重组背包 → 清空多选，避免选到看不见的物品
	_discard_mode = false
	_discard_sel.clear()
	_update_discard_btn()
	_detail.text = "点击物品查看详情"
	_detail.add_theme_color_override("font_color", DIM_TEXT)
	_clear_children(_detail_actions)
	_reset_detail_scroll()
	_refresh_bag()


# ===================== 详情 / 穿戴 =====================

func _on_item_selected(item: Dictionary, index: int) -> void:
	# 一键丢弃·多选模式：点击装备只切换选中态，不刷新详情
	if _discard_mode:
		_toggle_discard_pick(item)
		return
	_selected_index = index
	var d := CharacterData
	# 「首次获得」红点：点开详情就算看过了，红点永远熄灭（2026-11-12 用户定：点开才清）
	var new_id := String(item.get("id", ""))
	if d.is_bag_new(new_id):
		d.clear_bag_new(new_id)
		_refresh_bag()
	var lines: Array[String] = []
	var is_equip := String(item.get("type", "")) == d.ITEM_EQUIPMENT
	lines.append("名称：%s" % (ItemDB.equipped_display_name(item) if is_equip else String(item.get("name", "未知物品"))))
	lines.append("类型：%s" % String(d.ITEM_TYPE_DISPLAY.get(String(item.get("type", "")), "未知")))
	var item_realm := ItemDB.item_realm(item)
	if item_realm != "":
		lines.append("境界：%s" % item_realm)
	if not is_equip:
		lines.append("数量：%d" % int(item.get("count", 1)))
		var itype := String(item.get("type", ""))
		if itype == d.ITEM_PILL:
			var wheel_slot := CharacterData.quick_slot_of(String(item.get("id", "")))
			lines.append("战斗轮盘：%s" % (String(QUICK_SLOT_LABELS.get(wheel_slot, wheel_slot))
				if wheel_slot != "" else "未装配"))
	var grade := String(item.get("equipment_grade", ""))
	if grade != "":
		lines.append("品阶：%s" % grade)
	# 装备：显示部位、强化等级与属性/攻击力拆解
	if is_equip:
		var etype := String(item.get("equipment_type", ""))
		lines.append("部位：%s" % String(d.EQUIP_TYPE_DISPLAY.get(etype, etype)))
		var is_divine := ItemDB.is_max_grade(grade) and etype != "treasure"
		if is_divine:
			# 神器没有强化等级（2026-11-13）：不显示 +N/磨损，也不显示境界锁
			lines.append("已铸神 · 神器没有强化等级")
		else:
			lines.append("强化：%s" % ItemDB.enhance_text(item))
			# 境界锁：封顶的装备在详情里直接说明原因；化神仙器例外（用蕴仙髓淬炼）
			var lock_msg := ItemDB.realm_lock_message(grade, CharacterData.current_realm)
			var xian_open := etype != "treasure" and grade == "仙器" 				and CharacterData.is_huashen()
			if lock_msg != "" and not xian_open:
				lines.append(lock_msg)
		if etype == "treasure":
			# 法宝不带属性词条（2026-11-01 用户定）：只显示主动效果与进阶说明
			lines.append("法宝不附带属性词条；进阶只增强主动效果。")
			for ln in ItemDB.treasure_effect_lines(item):
				lines.append(ln)
		else:
			# 属性加成（力量/法强/抗性…）：装备的核心价值
			var attr_text := ItemDB.item_attributes_text(item)
			lines.append("属性加成：%s" % (attr_text if attr_text != "" else "无"))
			var base := float(item.get("attack_bonus_base", 0.0))
			var gi := maxi(0, ItemDB.grade_index(grade))
			var enh := maxi(0, int(item.get("enhancement_level", 0)))
			var atk_txt := ItemDB.attack_bonus_text(item)
			lines.append("攻击加成：%s（基础 %.0f + 品阶 %.0f + 强化 %.0f）" % [
				atk_txt if atk_txt != "" else "无", base,
				float(gi) * ItemDB.GRADE_ATTACK_PER_TIER, float(enh) * ItemDB.ENHANCE_ATTACK_PER_LEVEL,
			])
	var desc := String(item.get("desc", ""))
	# ⚠ etype 是在上面 `if is_equip:` 块里声明的（块作用域），这里要重新取一次
	if is_equip and String(item.get("equipment_type", "")) == "treasure":
		desc = ItemDB.treasure_desc_without_duration(item)
	# 法宝合成材料：告诉玩家去哪合成（2026-11-09 用户要求）。
	# ⚠ 必须排在「描述」**之前**：详情框是固定 146px（用户 2026-10-24 定，防止点装备时
	#   把背包格子压扁），描述本身就有长有短（地髓那条占两行），排后面时指引会被挤出
	#   可见区，只有滚一下才看得到 —— 而那正是玩家最需要看到的一行。
	#   文案由 ItemDB 按配方表现算，不在 desc 里写死。
	var synth_hints := ItemDB.synth_hint_lines(String(item.get("id", "")))
	for hint in synth_hints:
		lines.append(String(hint))
	# 新手指引：这块材料有合成配方，且玩家真的点开看过详情了
	if not synth_hints.is_empty():
		var tut := get_node_or_null("/root/Tutorial")
		if tut != null:
			tut.note("material_inspect")
	lines.append("描述：%s" % (desc if desc != "" else "—"))
	_detail.text = "\n".join(lines)
	_detail.add_theme_color_override("font_color", Color(0.88, 0.88, 0.92, 1.0))
	_rebuild_detail_actions(item, index, is_equip)


## 详情下方操作区：仅装备显示「穿戴」；已穿戴中的装备显示「卸下」
func _rebuild_detail_actions(item: Dictionary, index: int, is_equip: bool) -> void:
	_clear_children(_detail_actions)
	# 详情换了内容就回到顶部，避免上一件装备滚到中段后新内容从中间开始显示
	_reset_detail_scroll()
	var itype := String(item.get("type", ""))
	if itype == CharacterData.ITEM_PILL:
		_rebuild_wheel_actions(item)
		_add_discard_action(item)
		return
	if not is_equip:
		_add_discard_action(item)
		return
	var d := CharacterData
	var etype := String(item.get("equipment_type", ""))
	# 已穿戴 → 定位到它所在的具体槽；未穿戴 → 取该类第一个空槽
	var slot := _slot_of_equipped_item(item)
	if slot == "":
		slot = d.first_free_slot(etype)
	var equipped := d.get_equipped(slot)
	# ⚠ 必须按**对象引用**判定（is_same），不能按 id 比：
	#   装备实例的 id 字段是**模板 id**（同模板多件完全相同），按 id 比会把背包里
	#   同款未穿戴的装备误判成"已穿戴"→ 只显示「卸下」，点下去卸的是身上那件。
	#   （2026-10-19 用户报的 bug，已修）
	var is_this_equipped := (not equipped.is_empty()) and is_same(equipped, item)

	if is_this_equipped:
		var off_btn := UIKit.quiet_button("卸下", Vector2(96, 30), ACCENT)
		off_btn.pressed.connect(_on_unequip_slot.bind(slot))
		_detail_actions.add_child(off_btn)
	else:
		# 行内「穿戴」每行都有，不能全占主按钮权重：降成普通墨签
		var btn := UIKit.button("穿戴", Vector2(96, 30))
		btn.pressed.connect(_on_equip_from_bag.bind(index))
		_detail_actions.add_child(btn)

	# 丢弃：背包内除突破材料外都可丢（装备强化过的会先提示分解可得多少晶石）
	_add_discard_action(item)


## 丢弃按钮：突破材料与「禁令装备」（彩蛋装 问天剑）显示不可丢弃，其余物品可丢
func _add_discard_action(item: Dictionary) -> void:
	var itype := String(item.get("type", ""))
	if not CharacterData.can_discard_item(item):
		var why := CharacterData.discard_lock_reason(item)
		if why == "":
			why = "此物"
		var locked := UIKit.quiet_button("%s · 不可丢弃" % why, Vector2(150, 30),
			UIKit.C_TEXT_DIM)
		UIKit.set_readable_font(locked, 10)
		locked.disabled = true
		_detail_actions.add_child(locked)
		return
	if not CharacterData.can_discard_item(item):
		return
	var drop_btn := UIKit.danger_button("丢弃", Vector2(96, 30))
	drop_btn.pressed.connect(_on_discard_item_pressed.bind(item))
	_detail_actions.add_child(drop_btn)


# ===================== 丢弃（单件 / 批量）=====================

## 单件丢弃的确认文案（拆成纯函数便于验证）
## ⚠ 用户 2026-10-19 定：用晶石强化过的装备要提示"分解可得 N 晶石"，
##   同时强调**丢弃没有任何奖励**（避免玩家误以为能返还晶石）
func _discard_message(item: Dictionary) -> String:
	var name := _item_display_name(item)
	var refund := 0
	if String(item.get("type", "")) == CharacterData.ITEM_EQUIPMENT:
		refund = ItemDB.dismantle_refund(item)
	if refund > 0:
		return "「%s」分解可得【%d】晶石。\n丢弃将无法获得任何奖励，确定丢弃吗？" % [name, refund]
	return "确定丢弃「%s」吗？丢弃后无法找回。" % name


func _on_discard_item_pressed(item: Dictionary) -> void:
	ConfirmDialog.ask("丢弃物品", _discard_message(item), "丢弃", "取消",
		_do_single_discard.bind(item), true)


## 真正删除（按引用反查下标，避免背包变动后下标错位）
func _do_single_discard(item: Dictionary) -> void:
	if not CharacterData.can_discard_item(item):
		return
	var idx := _inventory_index_of(item)
	if idx < 0:
		return
	var name := _item_display_name(item)
	CharacterData.inventory.remove_at(idx)
	_clear_quick_slot_if_empty(item)
	_refresh_bag()
	_selected_index = -1
	_detail.text = "已丢弃「%s」" % name
	_detail.add_theme_color_override("font_color", UIKit.C_WARN)
	_clear_children(_detail_actions)


## 多选模式下点击物品：切换选中态（突破材料不可选）
func _toggle_discard_pick(item: Dictionary) -> void:
	if not CharacterData.can_discard_item(item):
		return
	for i in range(_discard_sel.size()):
		if is_same(_discard_sel[i], item):
			_discard_sel.remove_at(i)
			_refresh_bag()
			_update_discard_btn()
			return
	_discard_sel.append(item)
	_refresh_bag()
	_update_discard_btn()


## 丢掉最后一颗丹药时同步清掉轮盘格，避免轮盘还挂着一个空 id
func _clear_quick_slot_if_empty(item: Dictionary) -> void:
	if String(item.get("type", "")) != CharacterData.ITEM_PILL:
		return
	var iid := String(item.get("id", ""))
	if iid == "" or CharacterData.count_item(iid) > 0:
		return
	var sid := CharacterData.quick_slot_of(iid)
	if sid != "":
		CharacterData.clear_quick_slot(sid)
		_refresh_wheel_row()


func _update_discard_btn() -> void:
	if _discard_btn == null:
		return
	_discard_btn.text = ("丢弃选中（%d）" % _discard_sel.size()) if _discard_mode else "一键丢弃"


## 「一键丢弃」按钮：第一次点进入多选；第二次点（有选中）确认批量丢弃、无选中则退出
func _on_discard_mode_pressed() -> void:
	if not _discard_mode:
		_discard_mode = true
		_discard_sel.clear()
		_update_discard_btn()
		_detail.text = "多选模式：点击背包物品选中，再点「丢弃选中」批量丢弃；突破材料不可选"
		_detail.add_theme_color_override("font_color", DIM_TEXT)
		_clear_children(_detail_actions)
		_refresh_bag()
		return
	if _discard_sel.is_empty():
		_exit_discard_mode()
		return
	# 统计强化过的装备能分解出多少晶石，一并提示（丢弃不给奖励）
	var refund := 0
	var enhanced := 0
	for it in _discard_sel:
		if String((it as Dictionary).get("type", "")) != CharacterData.ITEM_EQUIPMENT:
			continue
		var r := ItemDB.dismantle_refund(it)
		if r > 0:
			refund += r
			enhanced += 1
	var msg := "确定丢弃选中的 %d 件物品吗？丢弃后无法找回。" % _discard_sel.size()
	if enhanced > 0:
		msg += "\n其中 %d 件分解共可得【%d】晶石（丢弃无任何奖励）。" % [enhanced, refund]
	ConfirmDialog.ask("批量丢弃", msg, "丢弃", "取消", _do_batch_discard, true)


func _exit_discard_mode() -> void:
	_discard_mode = false
	_discard_sel.clear()
	_update_discard_btn()
	if _detail != null:
		_detail.text = "点击物品查看详情"
		_detail.add_theme_color_override("font_color", DIM_TEXT)
	_clear_children(_detail_actions)
	_refresh_bag()


## 批量删除选中的装备（按引用逐个反查下标）
func _do_batch_discard() -> void:
	var n := 0
	for it in _discard_sel:
		if not CharacterData.can_discard_item(it):
			continue
		var idx := _inventory_index_of(it)
		if idx >= 0:
			CharacterData.inventory.remove_at(idx)
			_clear_quick_slot_if_empty(it)
			n += 1
	_exit_discard_mode()
	_detail.text = "已丢弃 %d 件物品" % n
	_detail.add_theme_color_override("font_color", UIKit.C_WARN)


## 该装备**对象**当前穿在哪个槽（按引用反查；未穿戴返回空串）
## 饰品有 3 个槽，不能再用 equipment_type 当槽位 id
## ⚠ 不能用 id 比较：装备实例的 id 是模板 id，同模板多件会互相误判（2026-10-19 修）
func _slot_of_equipped_item(item: Dictionary) -> String:
	for slot in CharacterData.WORN_SLOT_ORDER:
		var it := CharacterData.get_equipped(String(slot))
		if not it.is_empty() and is_same(it, item):
			return String(slot)
	return ""


func _on_equip_from_bag(index: int) -> void:
	var d := CharacterData
	if index < 0 or index >= d.inventory.size():
		return
	var item: Dictionary = d.inventory[index]
	var etype := String(item.get("equipment_type", ""))
	# 同种饰品 / 法宝只能戴一件；先按真实目标槽拦，文案里报出占用槽
	var target := d.first_free_slot(etype)
	var dup := d.equip_dup_slot(item, target)
	if dup != "":
		_detail.text = "同种%s已戴在「%s」，不能重复佩戴" % [
			String(d.EQUIP_TYPE_DISPLAY.get(etype, "装备")), d.slot_display_name(dup)]
		_detail.add_theme_color_override("font_color", UIKit.C_WARN)
		return
	var old := d.equip_from_inventory(index)
	_refresh_bag()
	_refresh_equipment()
	_refresh_stats()
	# 穿戴后原选中格已位移，重新定位到被换下的旧装备（若有），否则清空选择
	_selected_index = -1
	if not d.is_held_by_slot(item):
		# 被拒原因由数据层给（多半是「换下的旧装备放不下」），物品仍原样留在背包里
		_detail.text = d.equip_block_reason if d.equip_block_reason != "" else "穿戴失败"
		_detail.add_theme_color_override("font_color", UIKit.C_WARN)
		return
	_detail.text = "已穿戴"
	_detail.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55, 1.0))
	_clear_children(_detail_actions)
	if not old.is_empty():
		_detail.text = "已穿戴，换下：%s（已放回背包）" % String(old.get("name", ""))


## 拖放落点回调：把背包第 index 件装备穿到 slot_id
## 这里再校验一次部位与下标（拖拽期间背包可能已被别处改动），避免穿错槽位
func _equip_index_to_slot(index: int, slot_id: String) -> void:
	var d := CharacterData
	if index < 0 or index >= d.inventory.size():
		on_slot_changed("穿戴失败：物品已不在背包中", false)
		return
	var item: Dictionary = d.inventory[index]
	if String(item.get("type", "")) != d.ITEM_EQUIPMENT:
		on_slot_changed("只能穿戴装备", false)
		return
	var etype := String(item.get("equipment_type", ""))
	if not d.slot_accepts(slot_id, etype):
		var want := String(d.EQUIP_TYPE_DISPLAY.get(etype, "未知"))
		on_slot_changed("%s 属于「%s」，不能放进「%s」" % [
			_item_display_name(item), want, String(d.SLOT_DISPLAY.get(slot_id, slot_id))
		], false)
		return
	var dup := d.equip_dup_slot(item, slot_id)
	if dup != "":
		on_slot_changed("同种%s已戴在「%s」，不能重复佩戴" % [
			String(d.EQUIP_TYPE_DISPLAY.get(etype, "装备")), d.slot_display_name(dup)], false)
		return
	var old := d.equip_from_inventory(index, slot_id)
	if not d.is_held_by_slot(item):
		on_slot_changed(d.equip_block_reason if d.equip_block_reason != "" else "穿戴失败", false)
		return
	var msg := "已穿戴 %s" % _item_display_name(item)
	if not old.is_empty():
		msg += "，换下 %s（已放回背包）" % String(old.get("name", ""))
	on_slot_changed(msg, true)


## 点击已穿戴的格子：把该槽位装备卸回背包
func _on_equip_slot_clicked(slot_id: String) -> void:
	var d := CharacterData
	if d.get_equipped(slot_id).is_empty():
		return
	_on_unequip_slot(slot_id)


func _on_unequip_slot(slot: String) -> void:
	var d := CharacterData
	var item := d.get_equipped(slot)
	if item.is_empty():
		return
	if not d.unequip_to_inventory(slot):
		# 放不下就明确拒绝，绝不出现「卸下了但东西没了」
		_detail.text = d.bag_full_message(item)
		_detail.add_theme_color_override("font_color", UIKit.C_WARN)
		return
	_refresh_bag()
	_refresh_equipment()
	_refresh_stats()
	_selected_index = -1
	_detail.text = "已卸下 %s，放回背包" % String(d.SLOT_DISPLAY.get(slot, slot))
	_detail.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55, 1.0))
	_clear_children(_detail_actions)


# ===================== 工具 =====================

func _add_section(parent: Node, text: String) -> void:
	parent.add_child(UIKit.section(text, ACCENT))


func _clear_children(parent: Node) -> void:
	for c in parent.get_children():
		parent.remove_child(c)
		c.queue_free()


func _reset_detail_scroll() -> void:
	if _detail_scroll != null:
		_detail_scroll.scroll_vertical = 0


## 装备显示名：装备实例（CharacterData.make_equipment_instance）用 "name"，
## 装备模板（ItemDB.EQUIPMENT_TEMPLATES）用 "equipment_name"。两处都可能被渲染，统一取值。
static func _item_display_name(item: Dictionary) -> String:
	var n := String(item.get("name", ""))
	if n == "":
		n = String(item.get("equipment_name", ""))
	return n if n != "" else "未知装备"


# ===================== 内部控件：背包格 / 装备槽 =====================
## 背包格：可点击查看详情，装备类还可被拖到左侧穿戴槽
##
## 拖拽三件套是 Godot 内置的 Control 虚方法：
##   _get_drag_data  —— 按住拖动时被调用，返回值即本次拖拽携带的数据（null 表示不拖）
##   _can_drop_data  —— 悬停在某个 Control 上时被调用，返回能否放下
##   _drop_data      —— 松手放下时被调用，参数就是 _get_drag_data 返回的数据
class BagSlot extends Button:
	## 从 _get_drag_data 传给 _drop_data 的约定结构：
	##   { "kind": "bag_equipment", "index": int, "slot": String, "name": String }
	##   { "kind": "bag_material", "material_id": String, "name": String }
	const DRAG_KIND := "bag_equipment"
	const DRAG_KIND_MATERIAL := "bag_material"

	var item: Dictionary = {}
	var index: int = -1
	var panel: CanvasLayer = null
	## 一键丢弃多选模式下的选中态
	var discard_selected := false

	func setup(p_item: Dictionary, p_index: int, p_panel: CanvasLayer) -> void:
		item = p_item
		index = p_index
		panel = p_panel

		custom_minimum_size = UIKit.SLOT_SIZE
		mouse_filter = Control.MOUSE_FILTER_STOP

		var name_str := String(item.get("name", "未知物品"))
		var itype := String(item.get("type", ""))
		var count := int(item.get("count", 1))
		var is_equip := itype == CharacterData.ITEM_EQUIPMENT
		var grade := String(item.get("equipment_grade", ""))

		# 内容改用子节点（左图标 + 右文字），Button 自带 text 放不下图标和角标
		text = ""
		# 品质框：装备 = 品阶色；材料 / 丹药 / 符箓 = 稀有度色（统一 2px，和装备一样醒目）
		UIKit.apply_slot_style(self, UIKit.slot_style(true, ItemDB.item_border_color(item), 2))

		# 内容装在 slot_padding 里：Button 不自动排布 stylebox 的 margin，
		# 不套这层的话图标/文字会盖住品阶边框
		var mc := UIKit.slot_padding()
		# ⚠ Button **不会自动把子节点撑满**（不像 PanelContainer）。
		#   不铺满的话 MarginContainer 只有内容那么大，右侧文字会被压成 1px 宽。
		mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(mc)

		# 「首次获得」红点（2026-11-12 用户定）：右上角一颗朱点；点开详情才清（见 _on_item_selected）
		if CharacterData.is_bag_new(String(item.get("id", ""))):
			var dot := Label.new()
			dot.name = "NewDot"
			dot.text = "●"
			dot.add_theme_font_size_override("font_size", 11)
			dot.add_theme_color_override("font_color", UIKit.C_DANGER)
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dot.anchor_left = 1.0
			dot.anchor_right = 1.0
			dot.offset_left = -16.0
			dot.offset_right = -3.0
			dot.offset_top = 1.0
			dot.offset_bottom = 15.0
			add_child(dot)

		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 4)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mc.add_child(h)

		if is_equip:
			h.add_child(UIKit.equip_icon(item, UIKit.SLOT_ICON))
		else:
			h.add_child(UIKit.icon_node(String(item.get("icon", "")), name_str, "material", UIKit.SLOT_ICON))

		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 0)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(v)

		# 装备显示「名字 +N」（品阶色），与锻造台 / 装备槽口径一致；
		# 强化等级同时以图标右下角的 +N 角标呈现
		var name_lbl := UIKit.label(
			ItemDB.equipped_display_name(item) if is_equip else name_str,
			UIKit.F_SMALL,
			UIKit.grade_color(grade) if is_equip else UIKit.C_TEXT)
		# 不开 autowrap：宽度未定时 autowrap Label 会把最小高度算得很大，把格子撑高；
		# 名字过长就用省略号（格子本来也只放得下三四个字）
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(name_lbl)

		if not is_equip:
			var cnt := UIKit.label("×%d" % count, UIKit.F_SMALL, UIKit.C_TEXT_DIM)
			cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(cnt)

		UIKit.set_readable_font(self, 12)
		pressed.connect(_on_pressed)

	## 一键丢弃多选模式：选中态 = 红描边 3px（与品质描边区分得开）
	## 未选中时恢复基础样式（品质描边 2px）
	func set_discard_selected(v: bool) -> void:
		discard_selected = v
		if v:
			UIKit.apply_slot_style(self, UIKit.slot_style(true, UIKit.C_DANGER, 3))
		else:
			UIKit.apply_slot_style(self, UIKit.slot_style(true, ItemDB.item_border_color(item), 2))

	func _on_pressed() -> void:
		if panel != null and panel.has_method("_on_item_selected"):
			panel._on_item_selected(item, index)

	## 装备与材料可拖（装备 → 穿戴槽/铁砧装备槽；材料 → 铁砧晶石槽）；
	## 丹药/符箓返回 null，Godot 认为该节点不参与拖拽。
	func _get_drag_data(_at_position: Vector2) -> Variant:
		var itype := String(item.get("type", ""))
		# 材料：只允许拖（锻造台据此装填晶石），角色面板自身不处理材料拖放
		if itype == CharacterData.ITEM_MATERIAL:
			if get_viewport() != null and get_viewport().gui_is_dragging():
				set_drag_preview(_make_preview(String(item.get("name", "材料")), ItemDB.item_border_color(item)))
			return {
				"kind": DRAG_KIND_MATERIAL,
				"material_id": String(item.get("id", "")),
				"name": String(item.get("name", "")),
			}
		if itype != CharacterData.ITEM_EQUIPMENT:
			return null
		var etype := String(item.get("equipment_type", ""))
		if etype == "":
			return null

		# 跟随鼠标的预览：复用格子外观，稍微透明
		# 仅在真实拖拽中设置（set_drag_preview 要求 viewport 处于拖拽态），
		# 否则单元测试里手动调用本函数会报错
		if get_viewport() != null and get_viewport().gui_is_dragging():
			set_drag_preview(_make_preview(
				String(item.get("name", "装备")), UIKit.grade_color(String(item.get("equipment_grade", "")))
			))

		return {
			"kind": DRAG_KIND,
			"index": index,
			# etype 是装备**类别**（accessory），落点槽位再按类别匹配（accessory_1..3）
			"etype": etype,
			"id": String(item.get("id", "")),
			"name": String(item.get("name", "")),
		}

	## 拖拽预览块：与格子保持同一套外观（品阶描边 + 图标角标），松手前就能看清拖的是什么
	func _make_preview(text: String, color: Color) -> Control:
		var preview := PanelContainer.new()
		preview.custom_minimum_size = UIKit.SLOT_SIZE
		var style := UIKit.slot_style(true, color, 2)
		preview.add_theme_stylebox_override("panel", style)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.add_child(h)
		if String(item.get("type", "")) == CharacterData.ITEM_EQUIPMENT:
			h.add_child(UIKit.equip_icon(item, UIKit.SLOT_ICON))
		else:
			h.add_child(UIKit.icon_node(String(item.get("icon", "")), text, "material", UIKit.SLOT_ICON))
		var lbl := UIKit.label(text, UIKit.F_BODY, color)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(lbl)
		return preview


## 装备槽：三个部位各一个，既是展示格也是拖放目标
##
## 空格显示部位名（如「兵器」）+ 暗色底；有装备显示品阶边框 + 图标（带 +N 角标）+ 名称 + 加成。
## _can_drop_data 校验「拖来的装备部位 == 本格部位」，不匹配直接拒绝放置。
class EquipSlot extends PanelContainer:
	## ⚠ 高度 96（原 86）不是被内容撑出来的，而是**统一设计值**：
	##   格子内容固定 4 行（部位名/图标/名称/属性）+ 边距，86 放不下，
	##   会让多词条装备把该格撑高、九宫格行列不齐（2026-10-19 修）。
	##   配 30px 图标 + 文本单行截断后，所有格子稳定 126×96。
	const SLOT_SIZE := Vector2(126.0, 96.0)

	var slot_id: String = ""
	var panel: CanvasLayer = null
	var _body: VBoxContainer
	var _hovered := false

	func setup(p_slot: String, p_panel: CanvasLayer) -> void:
		slot_id = p_slot
		panel = p_panel
		custom_minimum_size = SLOT_SIZE
		mouse_filter = Control.MOUSE_FILTER_STOP
		# ⚠ 裁切兜底：多词条装备的属性文本再长也不会把九宫格撑大
		clip_contents = true

		_body = VBoxContainer.new()
		_body.add_theme_constant_override("separation", 2)
		_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_body)
		_rebuild()
		_apply_style()

	## 点一下已穿戴的格子 = 卸下（空格子点了没反应）
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if panel != null and panel.has_method("_on_equip_slot_clicked"):
				panel._on_equip_slot_clicked(slot_id)

	## 依据当前穿戴状态重建格子内容
	func _rebuild() -> void:
		for c in _body.get_children():
			_body.remove_child(c)
			c.queue_free()

		var display := String(CharacterData.SLOT_DISPLAY.get(slot_id, slot_id))
		var item := CharacterData.get_equipped(slot_id)

		# 第一行：部位名（小字，居中）
		var head := UIKit.label(display, UIKit.F_SMALL,
			UIKit.C_TEXT_DIM if item.is_empty() else UIKit.C_ACCENT)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_body.add_child(head)

		if item.is_empty():
			var empty := UIKit.label("空", UIKit.F_SUBTITLE, UIKit.C_DISABLE)
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_body.add_child(empty)
			return

		# 第二行：装备图标（带 +N 角标），与锻造台素材格同一个工厂
		# ⚠ 30px（原 40）：给名称/属性行留出高度余量，保证内容不把格子撑高
		var icon := UIKit.equip_icon(item, Vector2(30, 30))
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_body.add_child(icon)

		# 第三行：装备名 +N（品阶色）。装备实例统一用 name；兼容模板的 equipment_name
		# ⚠ 必须限制单行 + 截断：长名会把整个九宫格列宽撑开（用户 2026-10-19 报的 bug）
		var grade := String(item.get("equipment_grade", ""))
		var nice := UIKit.label(ItemDB.equipped_display_name(item), UIKit.F_BODY, UIKit.grade_color(grade))
		nice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nice.max_lines_visible = 1
		nice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_body.add_child(nice)

		# 第三行：属性加成 / 攻击加成 / 强化
		var tail_parts: Array[String] = []
		# 属性是装备的主要价值（力量/法强/抗性…），优先显示
		var attr_text := ItemDB.item_attributes_text(item)
		if attr_text != "":
			tail_parts.append(attr_text)
		var atk_txt := ItemDB.attack_bonus_text(item)
		if atk_txt != "":
			tail_parts.append(atk_txt)
		var enh := int(item.get("enhancement_level", 0))
		if enh > 0:
			tail_parts.append("强化 +%d" % enh)
		if not tail_parts.is_empty():
			var tail := UIKit.label(" · ".join(tail_parts), UIKit.F_SMALL, UIKit.C_TEXT_DIM)
			tail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			# ⚠ 这里是"撑大九宫格"的元凶：多词条装备（力量 + 攻击 + 强化…）文本很长，
			#   原先没开自动换行 → Label 最小宽度=整行文本宽 → GridContainer 列宽被撑开。
			#   现在强制单行 + 省略号截断，格子尺寸恒定（2026-10-19 修）
			tail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tail.max_lines_visible = 1
			tail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			_body.add_child(tail)

	## 底色：空格暗、有装备按品阶染色；悬停可放置时描边加亮
	## 品阶 additionally 反映在**描边**上（与锻造台素材格一致），底色只做轻微微妙
	func _apply_style() -> void:
		var filled := not CharacterData.get_equipped(slot_id).is_empty()
		var sb := UIKit.slot_style(filled)
		sb.bg_color = UIKit.C_SLOT_BG_FILLED if filled else UIKit.C_SLOT_BG
		if filled:
			var grade := String(CharacterData.get_equipped(slot_id).get("equipment_grade", ""))
			# 描边染成品阶色（2px，比空格更醒目）
			sb.border_color = UIKit.grade_border_color(grade)
			sb.set_border_width_all(2)
			# 底色只掺一点点品阶色，保持面板整体不花
			var tint := UIKit.grade_color(grade)
			tint.a = 0.18
			sb.bg_color = UIKit.C_SLOT_BG_FILLED.blend(tint)
		if _hovered:
			sb.border_color = UIKit.C_ACCENT
			sb.set_border_width_all(2)
		add_theme_stylebox_override("panel", sb)

	## 只接受「部位与本格一致」的背包装备
	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		if not (data is Dictionary):
			return false
		var d: Dictionary = data
		if String(d.get("kind", "")) != BagSlot.DRAG_KIND:
			return false
		var ok := CharacterData.slot_accepts(slot_id, String(d.get("etype", "")))
		# 同种饰品 / 法宝只能戴一件：悬停时就描红，别等松手才拒绝
		if ok:
			var probe := {
				"equipment_type": String(d.get("etype", "")),
				"id": String(d.get("id", "")),
			}
			if CharacterData.equip_dup_slot(probe, slot_id) != "":
				ok = false
		# 悬停高亮：可放置时描金边，不可放置时描红边，给玩家即时反馈
		if _hovered != ok:
			_hovered = ok
		if ok:
			_set_border(UIKit.C_ACCENT, 2)
		else:
			_set_border(UIKit.C_DANGER, 2)
		return ok

	func _set_border(c: Color, w: int) -> void:
		var sb := get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			sb.border_color = c
			sb.set_border_width_all(w)

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if not (data is Dictionary):
			return
		var d: Dictionary = data
		var idx := int(d.get("index", -1))
		_hovered = false
		if panel == null or not panel.has_method("_equip_index_to_slot"):
			return
		panel._equip_index_to_slot(idx, slot_id)

	func _notification(what: int) -> void:
		# 拖拽结束时清掉高亮（拖走了但没放下、或放下到别处）
		if what == NOTIFICATION_DRAG_END:
			_hovered = false
			_apply_style()
