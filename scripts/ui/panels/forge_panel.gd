class_name ForgePanel
extends SystemPanel
## 锻造工坊 · 墨夜炉火（2026-10-25 用户定稿）
##
## 全屏 1280×720，不套设施面板金框；木梁顶栏 + 铁砧近景 + 右侧兵器架。
## 保留全部原有规则：放装备→拿锤→点砧强化；晶石自动扣；80/5/20；磨损 10 破损；
## 满 +10 进阶；境界锁；熔铸两套配方共用三个投入口，按内容自动识别、不看顺序：
##   元魂 + 同源破损装备 → 召唤法宝；三件同位面材料 → 位面法宝；
##   一档破境的地髓 + 天髓 → 完整破境晶（产物是材料，走 _run_pojing_synthesis）。
##
## 本面板只改执行层：一次敲击拆成 抬起→挥锤→命中→结算→回位，
## 命中帧才调用 CharacterData.enhance_item()，最多缓存一锤；不改任何数值与存档格式。

const VIEW := Vector2(1280.0, 720.0)
const TOP_H := 92.0
const RAIL_W := 320.0
const SPINE_W := 38.0
const RAIL_Y := TOP_H
const FURNACE_CENTER := Vector2(300.0, 380.0) # camera pivot
const FURNACE_RECT := Rect2(120.0, 190.0, 300.0, 330.0)
const FURNACE_FIRE := Vector2(266.0, 432.0)
const ANVIL_HIT := Rect2(496.0, 128.0, 344.0, 224.0)
const EQUIP_CENTER := Vector2(664.0, 214.0)
const EQUIP_SIZE := 104.0
const HAMMER_HOME := Vector2(884.0, 300.0)
const HAMMER_SIZE := Vector2(206.0, 110.0)
const HAMMER_HEAD_PIVOT := Vector2(0.20, 0.54)
## 石台与墨墙的交界斜率 0.46（≈25°），锤子歇在石面上要顺着这条线，不能水平摆。
const HAMMER_REST_DEG := 22.0
const HAMMER_HELD_DEG := -18.0
const PLAQUE_POS := Vector2(26.0, 492.0)
const PLAQUE_SIZE := Vector2(376.0, 188.0)
const DISH_POS := Vector2(416.0, 492.0)
const TOAST_POS := Vector2(380.0, 634.0)
const CFG_PATH := "user://forge_ui.cfg"
const MODE_FORGE := "forge"
const MODE_MELT := "melt"
## 熔铸页两套配方共用三个投入口：召唤法宝（元魂 + 同源破损装备）/
## 位面法宝（三件同位面材料）/ 破境残晶（地髓 + 天髓）。按投入内容自动识别，不看顺序，不再切模式。
const SYNTH_KIND_PLANE := "plane"
const SYNTH_KIND_SOUL := "soul"
const SYNTH_KIND_EQUIP := "equip"
## 破境残晶（地髓 / 天髓）：两枚一地上两天，熔成完整破境晶，不产出法宝
const SYNTH_KIND_POJING := "pojing"
const STRIKE_IDLE := 0
const STRIKE_WINDUP := 1
const STRIKE_SWING := 2
const STRIKE_IMPACT := 3
const STRIKE_RECOVER := 4
## 铸神 / 补天落锤时的装备光色（用户 2026-11-13 定：两种操作不同光芒）
const SPECIAL_DIVINE_COLOR := Color(1.0, 0.80, 0.38, 1.0)
const SPECIAL_MEND_COLOR := Color(0.52, 0.92, 0.66, 1.0)
## 蕴仙髓的青玉光，和补天的草绿分开
const SPECIAL_YUNXIAN_COLOR := Color(0.58, 0.88, 1.0, 1.0)

const FORGE_WOOD_BEAM := "res://assets/ui/forge/wood_beam_9p.png"
const FORGE_WOOD_PLAQUE := "res://assets/ui/forge/wood_plaque_9p.png"
const FORGE_WOOD_BUTTON := "res://assets/ui/forge/button_wood_9p.png"
const FORGE_PAPER_TAG := "res://assets/ui/forge/paper_tag_9p.png"
const FORGE_BRASS_PLAQUE := "res://assets/ui/forge/brass_plaque_9p.png"
const FORGE_PAPER_SCROLL := "res://assets/ui/forge/paper_scroll_9p.png"
const FORGE_CRYSTAL_DISH := "res://assets/ui/forge/crystal_dish.png"
const FORGE_HAMMER := "res://assets/ui/forge/hammer_stage.png"
const FORGE_HAMMER_SHADOW := "res://assets/ui/forge/hammer_shadow.png"
const FORGE_SOCKET := "res://assets/ui/forge/socket_bronze_9p.png"
const FORGE_RAIL_SPINE := "res://assets/ui/forge/rail_spine_9p.png"
const FORGE_MELT_TRAY := "res://assets/ui/forge/melt_tray_9p.png"
const FORGE_TOAST := "res://assets/ui/forge/toast_paper_9p.png"
const FORGE_STAGE := "res://assets/ui/forge/stage_night.png"

var _stage: Control
var _world: Control
var _forge_layer: Control
var _topbar: Control
var _rail: Control
var _rail_content: Control
var _rail_spine: Control
var _rail_handle: ForgeButton
var _rail_spine_icon: TextureRect
var _rail_spine_label: Label
var _melt_layer: Control
var _overlay_layer: Control
## 左上角「锻造说明」小木牌 + 点开的说明层（2026-11-13 用户定）
var _help_sign: ForgeButton
var _help_layer: Control = null
var _float_layer: Control

var _bg: TextureRect
var _furnace_glow: TextureRect
var _anvil_glow: TextureRect
var _hammer: TextureRect
var _hammer_shadow: TextureRect
var _fx: ForgeFx

var _equip_display: Control
var _equip_icon: Control
var _equip_name: Label
var _equip_empty: Label
var _anvil_drop: Control
var _take_btn: ForgeButton
var _dismantle_btn: ForgeButton
## 铸神（仙器满 +10 + 铸神晶）/ 补天（补天石清普通磨损）/ 蕴仙（仙器淬炼）
## 2026-11-13 用户定：三枚动作挪到顶栏晶石数量旁，点一下自动落料 + 敲击
var _divine_btn: ForgeButton
var _mend_btn: ForgeButton
var _yunxian_btn: ForgeButton
var _mat_row: HBoxContainer
## 材料落料 → 自动落锤演出（2026-11-13 用户定）
var _special_busy := false
var _special_icon: TextureRect = null
var _glow_tw: Tween = null
## 探针用：最近一次特殊演出的装备光色
var _last_special_flash := Color.WHITE
var _plaque: PanelContainer
var _plaque_name: Label
var _plaque_meta: Label
## 强化词条 + 单次增强区间（2026-11-13 用户定：铭牌上要能看见「会随机拔高哪条、涨多少」）
var _plaque_affix: Label
var _plaque_cost: Label
var _plaque_pips: HBoxContainer
var _plaque_pip_caption: Label
var _plaque_pip_nodes: Array[ColorRect] = []
var _plaque_hint: Label
var _crystal_dish: TextureRect
var _dish_label: Label
var _top_crystal_icon: TextureRect
var _top_crystal_label: Label
var _forge_hint: Label
var _auto_btn: ForgeButton
var _auto_stop_btn: ForgeButton
var _auto_tip: Label
var _auto_forge := false
var _auto_waiting := false
var _auto_token := 0
var _toast_card: PanelContainer
var _toast_label: Label

var _forge_tab: ForgeButton
var _melt_tab: ForgeButton

var _equipped_grid: GridContainer
var _bag_grid: GridContainer
var _bag_scroll: ScrollContainer
var _bag_count: Label
var _rail_tween: Tween
var _rail_hover_timer: SceneTreeTimer
var _rail_open := true
var _rail_busy := false

var _anvil_item: Dictionary = {}
## 拖拽跟随图标（自己画在最上层：引擎 drag preview 在 CanvasLayer 面板下会被遮住）
var _drag_icon: Control = null
var _drag_icon_key := ""
var _hammer_held := false
var _hammer_following := true
var _strike_state := STRIKE_IDLE
var _strike_seq := 0
var _queued_strike := false
var _queued_target := Vector2.ZERO
var _strike_target := Vector2.ZERO
var _swing_tw: Tween
var _last_mouse := Vector2.ZERO

var _mode := MODE_FORGE
var _melting := false
var _camera_tw: Tween
var _melt_sockets: Array[Control] = []
var _melt_socket_labels: Array[Label] = []
var _melt_hint: Label
var _melt_result: Label
var _melt_button: ForgeButton
var _synth_slot_data: Array = [{}, {}, {}]
var _synth_selected_slot := -1
var _candidate_layer: Control
var _candidate_title: Label
var _candidate_box: VBoxContainer
var _treasure_layer: Control

var _detail_layer: Control
var _tutorial_layer: Control
var _tutorial_check: CheckBox
var _settings_hidden := false
var _intro_played := false
var _config := ConfigFile.new()
var _tutorial_seen := false
var _tooltip: Label


func _init() -> void:
	panel_title = "锻造工坊"
	panel_hint = "ESC 关闭 · 点/拖装备上砧 · 拿锤敲击 · 可自动锻造"


func facility_visual() -> Dictionary:
	return UIKit.facility_style("forge")


func facility_header_compact() -> bool:
	return true


func panel_size() -> Vector2:
	return VIEW


# ===================== 生命周期 =====================

func _build_shell() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.014, 0.018, 1.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_root = PanelContainer.new()
	_root.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_root.position = Vector2.ZERO
	_root.size = VIEW
	add_child(_root)

	_stage = Control.new()
	_stage.name = "ForgeStage"
	_stage.size = VIEW
	_stage.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(_stage)

	content = UIKit.vbox(0)
	content.visible = false
	_stage.add_child(content)
	_build_world()
	_build_topbar()
	_build_rail()
	_build_melt_layer()
	_build_toast()
	_overlay_layer = Control.new()
	_overlay_layer.name = "ForgeOverlays"
	_overlay_layer.size = VIEW
	_overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 舞台里的锤/火星/飘字最高到 z 25，弹窗必须压过它们
	_overlay_layer.z_index = 40
	_stage.add_child(_overlay_layer)


func open() -> void:
	if _visible:
		return
	super.open()
	SettingsUI.set_entry_visible(false)
	_settings_hidden = true
	_play_fire_intro()
	_load_config()
	call_deferred("_maybe_show_tutorial")


func _exit_tree() -> void:
	super._exit_tree()          # ⚠ 基类靠它返还模态计数，漏了任务面板会永久不显示
	_auto_forge = false
	_auto_waiting = false
	_auto_token += 1
	_queued_strike = false
	if _settings_hidden:
		SettingsUI.set_entry_visible(true)
	# 砧上那份此刻只活在这个面板变量里（不在背包、不在槽位、也不在存档）。
	# 关面板 / 回登录 / 切场景都会走到这里，必须归还，且**放不下也要强制入包** ——
	# 2026-11-02 用户报的「退出锻造界面装备就消失」就是原来只 push_warning 把字典丢了
	if not _anvil_item.is_empty():
		var a := _anvil_item
		_anvil_item = {}
		CharacterData.return_item_or_force(a)


func _input(event: InputEvent) -> void:
	if not _visible:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _close_top_overlay():
			return
		if _mode == MODE_MELT:
			_switch_mode(MODE_FORGE)
			return
		if can_close():
			close()
		return
	if event is InputEventMouseMotion:
		_last_mouse = get_viewport().get_mouse_position()
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		# 用事件自带坐标：触屏模拟出的点击不一定同步 viewport 的鼠标位置
		_last_mouse = event.global_position
		_handle_left_click(_last_mouse)
		return
	super(event)


func can_close() -> bool:
	if _melting:
		show_toast("熔炉正旺 —— 等法宝出炉再离开", UIKit.C_WARN)
		return false
	return true


# ===================== 全屏舞台 =====================

func _build_world() -> void:
	_world = Control.new()
	_world.name = "World"
	_world.size = VIEW
	_world.mouse_filter = Control.MOUSE_FILTER_PASS
	_stage.add_child(_world)

	_bg = TextureRect.new()
	_bg.texture = UIKit.ui_texture(FORGE_STAGE)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.size = VIEW
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(_bg)

	_furnace_glow = UIKit.glow_node(Vector2(430, 430), Color(1.0, 0.52, 0.18), 0.42)
	_furnace_glow.position = FURNACE_FIRE - Vector2(215, 235)
	_world.add_child(_furnace_glow)

	_anvil_glow = UIKit.glow_node(Vector2(470, 320), Color(1.0, 0.72, 0.38), 0.16)
	_anvil_glow.position = Vector2(430, 120)
	_world.add_child(_anvil_glow)

	_forge_layer = Control.new()
	_forge_layer.name = "ForgeLayer"
	_forge_layer.size = VIEW
	_forge_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	_world.add_child(_forge_layer)
	_build_plaque()
	_build_equipment_display()
	_build_anvil_drop()
	_build_take_and_dismantle()
	_build_crystal_dish()
	_build_hammer()
	_build_forge_hint()
	_build_auto_forge()

	_fx = ForgeFx.new()
	_fx.size = VIEW
	_fx.furnace_pos = FURNACE_FIRE
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 锤子 z_index 是 20，火星和飘字要压在它上面，不然挥锤会把特效挡掉
	_fx.z_index = 24
	_world.add_child(_fx)

	_float_layer = Control.new()
	_float_layer.name = "ForgeFloat"
	_float_layer.size = VIEW
	_float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_float_layer.z_index = 25
	_world.add_child(_float_layer)


func _build_topbar() -> void:
	_topbar = Control.new()
	_topbar.name = "TopBar"
	_topbar.size = Vector2(VIEW.x, TOP_H)
	_topbar.mouse_filter = Control.MOUSE_FILTER_PASS
	_stage.add_child(_topbar)
	# 舞台里的锤子抬到 z 20，抬头要仍然压得住它
	_topbar.z_index = 40

	var beam := TextureRect.new()
	beam.texture = UIKit.ui_texture(FORGE_WOOD_BEAM)
	beam.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	beam.stretch_mode = TextureRect.STRETCH_SCALE
	beam.size = Vector2(VIEW.x, TOP_H)
	beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_topbar.add_child(beam)

	var shade := TextureRect.new()
	shade.texture = UIKit.vertical_gradient(Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.55))
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.position = Vector2(0, TOP_H - 20)
	shade.size = Vector2(VIEW.x, 20)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_topbar.add_child(shade)

	var plaque := PanelContainer.new()
	plaque.position = Vector2(24, 8)
	plaque.custom_minimum_size = Vector2(300, 76)
	plaque.size = Vector2(300, 76)
	plaque.add_theme_stylebox_override("panel", _tex_style(FORGE_WOOD_PLAQUE, 28, 20, 12, 6))
	plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_topbar.add_child(plaque)
	var pv := UIKit.vbox(0)
	plaque.add_child(pv)
	var title := UIKit.label("锻造工坊", 25, Color(0.98, 0.93, 0.80))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(title)
	var sub := UIKit.label("百炼成钢 · 一锤一器", 9, Color(0.71, 0.58, 0.38))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(sub)

	_forge_tab = ForgeButton.new()
	_forge_tab.text = "锻打"
	_forge_tab.setup(ForgeButton.TONE_TAB)
	_forge_tab.position = Vector2(352, 23)
	_forge_tab.size = Vector2(128, 46)
	_forge_tab.custom_minimum_size = Vector2(128, 46)
	_forge_tab.add_theme_font_size_override("font_size", 16)
	_forge_tab.pressed.connect(_switch_mode.bind(MODE_FORGE))
	_forge_tab.set_selected(true)
	UIKit.attach_click_sfx(_forge_tab, "ui_tab")
	_topbar.add_child(_forge_tab)

	_melt_tab = ForgeButton.new()
	_melt_tab.text = "熔铸"
	_melt_tab.setup(ForgeButton.TONE_TAB)
	_melt_tab.position = Vector2(490, 23)
	_melt_tab.size = Vector2(128, 46)
	_melt_tab.custom_minimum_size = Vector2(128, 46)
	_melt_tab.add_theme_font_size_override("font_size", 16)
	_melt_tab.pressed.connect(_switch_mode.bind(MODE_MELT))
	UIKit.attach_click_sfx(_melt_tab, "ui_tab")
	_topbar.add_child(_melt_tab)
	_melt_tab.set_meta("tut", "forge.tab_synth")

	# 晶石读数 + 三枚材料动作并排（2026-11-13 用户定：都挪到上面晶石数量旁边）
	_mat_row = UIKit.hbox(8)
	_mat_row.name = "ForgeMaterials"
	_mat_row.position = Vector2(628, 26)
	_mat_row.size = Vector2(VIEW.x - 628 - 128, 38)
	_mat_row.alignment = BoxContainer.ALIGNMENT_END
	_mat_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_topbar.add_child(_mat_row)
	var crystal_chip := PanelContainer.new()
	crystal_chip.custom_minimum_size = Vector2(0, 38)
	crystal_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crystal_chip.add_theme_stylebox_override("panel",
		_tex_style(FORGE_WOOD_BUTTON, 14, 14, 10, 10, 7, 2, 2))
	_mat_row.add_child(crystal_chip)
	var crystal_inner := UIKit.hbox(4)
	crystal_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crystal_chip.add_child(crystal_inner)
	_top_crystal_icon = TextureRect.new()
	_top_crystal_icon.texture = UIKit.ui_texture("res://assets/ui/icon/mat_duanzaojingshi.png")
	_top_crystal_icon.custom_minimum_size = Vector2(18, 18)
	_top_crystal_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_top_crystal_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_top_crystal_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_top_crystal_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crystal_inner.add_child(_top_crystal_icon)
	_top_crystal_label = UIKit.label("晶石 ×0", 14, Color(0.84, 0.88, 0.90))
	_top_crystal_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	crystal_inner.add_child(_top_crystal_label)

	# 补天在左、铸神在右（沿用上一版防误触的顺序），蕴仙接在后面
	_mend_btn = _mat_action("res://assets/ui/icon/mat_butianshi.png",
		"消耗补天石 ×1，清掉普通失败留下的磨损；进阶失败的磨损清不掉")
	_mend_btn.pressed.connect(_on_mend_pressed)
	_mat_row.add_child(_mend_btn)
	_dress_mat_chip(_mend_btn)
	_divine_btn = _mat_action("res://assets/ui/icon/mat_zhushenjing.png",
		"把满 +10 的仙器铸成神器（消耗铸神晶 ×1）；神器没有强化等级")
	_divine_btn.pressed.connect(_on_divine_pressed)
	_mat_row.add_child(_divine_btn)
	_dress_mat_chip(_divine_btn)
	_yunxian_btn = _mat_action("res://assets/ui/icon/mat_yunxiansui.png",
		"仙器只能点这里淬炼：每点一次消耗蕴仙髓 ×1；满 +10 后才能用铸神晶铸神")
	_yunxian_btn.pressed.connect(_on_yunxian_pressed)
	_mat_row.add_child(_yunxian_btn)
	_dress_mat_chip(_yunxian_btn)

	var close_btn := ForgeButton.new()
	close_btn.text = "关闭"
	close_btn.setup(ForgeButton.TONE_WOOD)
	close_btn.position = Vector2(1160, 24)
	close_btn.size = Vector2(92, 40)
	close_btn.custom_minimum_size = Vector2(92, 40)
	close_btn.add_theme_font_size_override("font_size", 13)
	close_btn.pressed.connect(close)
	_topbar.add_child(close_btn)
	var esc := UIKit.label("ESC", 9, Color(0.58, 0.50, 0.38))
	esc.position = Vector2(1196, 68)
	esc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_topbar.add_child(esc)

	# 左上角小木牌「锻造说明」（2026-11-13 用户定）：挂在木梁左下方，点开看完整规则。
	# 样式复用工坊自己的木牌控件，不另画一套皮肤。
	_help_sign = ForgeButton.new()
	_help_sign.name = "ForgeHelpSign"
	_help_sign.text = "锻造说明"
	_help_sign.setup(ForgeButton.TONE_WOOD)
	_help_sign.position = Vector2(24.0, TOP_H + 12.0)
	_help_sign.size = Vector2(112.0, 34.0)
	_help_sign.custom_minimum_size = Vector2(112.0, 34.0)
	_help_sign.add_theme_font_size_override("font_size", 13)
	_help_sign.tooltip_text = "强化 / 进阶 / 破损的完整规则"
	_help_sign.z_index = 30
	_help_sign.pressed.connect(_show_forge_help)
	_stage.add_child(_help_sign)


func _mat_action(icon_path: String, tip: String) -> ForgeButton:
	var b := ForgeButton.new()
	b.setup(ForgeButton.TONE_WOOD)
	# Button 没有 icon_max_width，先把 256² 图标缩成 18² 再挂上去
	var src := UIKit.ui_texture(icon_path)
	if src != null:
		var img := src.get_image()
		if img != null:
			img.resize(18, 18, Image.INTERPOLATE_LANCZOS)
			b.icon = ImageTexture.create_from_image(img)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_constant_override("h_separation", 4)
	b.custom_minimum_size = Vector2(0, 36)
	b.tooltip_text = tip
	return b


## 顶栏材料钮的紧凑皮肤：默认木牌两侧留 28px 花纹，四枚并排放不下
func _dress_mat_chip(b: ForgeButton) -> void:
	# ForgeButton 默认 clip_text + 省略号，按钮最小宽度不算文字 → 并排时会被压成一条
	b.clip_text = false
	b.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	b.add_theme_stylebox_override("normal",
		_tex_style(FORGE_WOOD_PLAQUE, 14, 14, 10, 10, 7, 2, 2))
	b.add_theme_stylebox_override("hover",
		_tex_style_tint(FORGE_WOOD_PLAQUE, Color(1.10, 1.05, 0.96), 14, 14, 10, 10, 7, 2, 2))
	b.add_theme_stylebox_override("pressed",
		_tex_style_tint(FORGE_WOOD_PLAQUE, Color(0.80, 0.77, 0.72), 14, 14, 10, 10, 7, 2, 2))
	b.add_theme_stylebox_override("disabled",
		_tex_style_tint(FORGE_WOOD_PLAQUE, Color(1, 1, 1, 0.42), 14, 14, 10, 10, 7, 2, 2))
	b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.55))
	# 禁用时数量也要看得清（界面必须让玩家看见现有资源）
	b.add_theme_color_override("font_disabled_color", Color(0.80, 0.76, 0.68, 1.0))


func _build_rail() -> void:
	_rail = Control.new()
	_rail.name = "WeaponRail"
	_rail.position = Vector2(VIEW.x - RAIL_W, RAIL_Y)
	_rail.size = Vector2(RAIL_W, VIEW.y - RAIL_Y)
	_rail.clip_contents = true
	_stage.add_child(_rail)
	# 兵器架是前景家具，挥起来的锤子不能盖在它上面
	_rail.z_index = 30

	var back := PanelContainer.new()
	back.position = Vector2.ZERO
	back.size = _rail.size
	back.add_theme_stylebox_override("panel", _tex_style(FORGE_WOOD_PLAQUE, 26, 18, 12, 6))
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	# 整块背包底板都能接收「身上/砧上」的装备；挂签自己也带转发
	back.set_drag_forwarding(Callable(), _can_drop_on_bag_at, _drop_on_bag_at)
	_rail.add_child(back)

	# 收回到右缘时留下的窄木脊
	_rail_spine = Control.new()
	_rail_spine.position = Vector2.ZERO
	_rail_spine.size = Vector2(SPINE_W, _rail.size.y)
	_rail_spine.mouse_filter = Control.MOUSE_FILTER_PASS
	_rail.add_child(_rail_spine)
	var spine_tex := TextureRect.new()
	spine_tex.texture = UIKit.ui_texture(FORGE_RAIL_SPINE)
	spine_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spine_tex.stretch_mode = TextureRect.STRETCH_SCALE
	spine_tex.size = _rail_spine.size
	spine_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail_spine.add_child(spine_tex)
	_rail_handle = ForgeButton.new()
	_rail_handle.text = "›"
	_rail_handle.setup(ForgeButton.TONE_WOOD)
	_rail_handle.position = Vector2(4, 10)
	_rail_handle.size = Vector2(30, 34)
	_rail_handle.add_theme_font_size_override("font_size", 20)
	_rail_handle.pressed.connect(_toggle_rail)
	_rail_spine.add_child(_rail_handle)
	_rail_spine_icon = TextureRect.new()
	_rail_spine_icon.position = Vector2(4, 62)
	_rail_spine_icon.size = Vector2(30, 30)
	_rail_spine_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rail_spine_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rail_spine_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail_spine.add_child(_rail_spine_icon)
	var spine_label := UIKit.label("兵\n器\n架", 12, Color(0.62, 0.51, 0.35))
	spine_label.position = Vector2(-2, 132)
	spine_label.size = Vector2(42, 70)
	spine_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spine_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail_spine.add_child(spine_label)
	_rail_spine_label = spine_label
	_rail_spine.mouse_entered.connect(_on_spine_hover)

	_rail_content = Control.new()
	_rail_content.position = Vector2(SPINE_W, 0)
	_rail_content.size = Vector2(RAIL_W - SPINE_W, _rail.size.y)
	_rail_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_rail.add_child(_rail_content)

	var margin := MarginContainer.new()
	margin.position = Vector2(8, 10)
	margin.size = Vector2(RAIL_W - SPINE_W - 16, _rail.size.y - 20)
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 6)
	_rail_content.add_child(margin)
	var col := UIKit.vbox(6)
	margin.add_child(col)

	var head := UIKit.hbox(6)
	col.add_child(head)
	var rail_title := UIKit.label("兵器架", 18, Color(0.97, 0.92, 0.80))
	head.add_child(rail_title)
	head.add_child(UIKit.spacer())
	var rail_hint := UIKit.label("点上砧 · 拖换装", 10, Color(0.72, 0.62, 0.44))
	rail_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(rail_hint)

	var eq_head := UIKit.hbox(6)
	col.add_child(eq_head)
	eq_head.add_child(UIKit.label("已穿戴", 11, Color(0.74, 0.63, 0.44)))
	eq_head.add_child(UIKit.spacer())
	eq_head.add_child(UIKit.label("3×3", 10, Color(0.56, 0.49, 0.37)))

	_equipped_grid = GridContainer.new()
	_equipped_grid.columns = 3
	_equipped_grid.add_theme_constant_override("h_separation", 5)
	_equipped_grid.add_theme_constant_override("v_separation", 5)
	_equipped_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equipped_grid.set_drag_forwarding(Callable(), _can_drop_on_bag_at, _drop_on_bag_at)
	# 新手指引锚点：c5 上砧（点身上的挂签）与拖回穿戴（拖到武器格）都聚光这块 3×3
	_equipped_grid.set_meta("tut", "forge.worn")
	col.add_child(_equipped_grid)

	var bag_head := UIKit.hbox(6)
	col.add_child(bag_head)
	bag_head.add_child(UIKit.label("背包装备", 11, Color(0.74, 0.63, 0.44)))
	bag_head.add_child(UIKit.spacer())
	_bag_count = UIKit.label("", 10, Color(0.56, 0.49, 0.37))
	bag_head.add_child(_bag_count)

	_bag_scroll = ScrollContainer.new()
	_bag_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bag_scroll.custom_minimum_size = Vector2(0, 196)
	_bag_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_bag_scroll.set_drag_forwarding(Callable(), _can_drop_on_bag_at, _drop_on_bag_at)
	col.add_child(_bag_scroll)
	_bag_grid = GridContainer.new()
	_bag_grid.columns = 3
	_bag_grid.add_theme_constant_override("h_separation", 5)
	_bag_grid.add_theme_constant_override("v_separation", 5)
	_bag_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bag_grid.set_drag_forwarding(Callable(), _can_drop_on_bag_at, _drop_on_bag_at)
	_bag_scroll.add_child(_bag_grid)

	# 拖装备回背包：右架左缘一条投放带（底板 / 挂签也接受，见 _build_rail）
	var drop_back := Control.new()
	drop_back.set_script(load("res://scripts/ui/panels/forge_drop_area.gd"))
	drop_back.set("panel", self)
	drop_back.position = Vector2(0, 48)
	drop_back.size = Vector2(SPINE_W, _rail.size.y - 48)
	drop_back.tooltip_text = "把身上或砧上的装备拖到这里"
	_rail.add_child(drop_back)


func _build_melt_layer() -> void:
	_melt_layer = Control.new()
	_melt_layer.name = "MeltLayer"
	_melt_layer.size = VIEW
	_melt_layer.visible = false
	# IGNORE：整层不拦截鼠标，顶栏的「锻打 / 熔铸」在熔铸页仍然可点
	_melt_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_melt_layer)
	_melt_layer.z_index = 30

	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.012, 0.012, 0.28)
	dim.size = VIEW
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_melt_layer.add_child(dim)

	var title := UIKit.label("熔 铸", 32, Color(0.98, 0.86, 0.62))
	title.position = Vector2(92, 132)
	UIKit.soft_text_shadow(title, 1)
	_melt_layer.add_child(title)
	var sub := UIKit.readable_label("元魂 + 同源破损装备，或三件同位面材料，或地髓 + 天髓，投入炉膛，熔成法宝 / 破境晶", 11,
		Color(0.78, 0.68, 0.52))
	sub.position = Vector2(96, 174)
	_melt_layer.add_child(sub)
	var order_hint := UIKit.readable_label("投入口不分顺序，配方成立即可合成", 10,
		Color(0.72, 0.64, 0.50))
	order_hint.position = Vector2(96, 202)
	order_hint.size = Vector2(500, 24)
	order_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_melt_layer.add_child(order_hint)

	# 熔铸托盘：三个投入口落在铁盘上，不再是悬空的方框
	var tray := TextureRect.new()
	tray.texture = UIKit.ui_texture(FORGE_MELT_TRAY)
	tray.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tray.stretch_mode = TextureRect.STRETCH_SCALE
	tray.position = Vector2(206, 330)
	tray.size = Vector2(596, 232)
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_melt_layer.add_child(tray)

	for i in 3:
		var socket := _make_melt_socket(i)
		socket.position = Vector2(240 + i * 178, 360)
		_melt_layer.add_child(socket)
		_melt_sockets.append(socket)

	_melt_hint = UIKit.readable_label("点击投入口选材料：三件同位面材料、元魂+破损装备、或一档破境的地髓+天髓，不分顺序。",
		11, Color(0.88, 0.80, 0.64))
	_melt_hint.position = Vector2(240, 570)
	_melt_hint.size = Vector2(500, 30)
	UIKit.soft_text_shadow(_melt_hint, 1)
	_melt_layer.add_child(_melt_hint)

	_melt_button = ForgeButton.new()
	_melt_button.text = "熔铸"
	_melt_button.setup(ForgeButton.TONE_SEAL)
	_melt_button.position = Vector2(240, 604)
	_melt_button.size = Vector2(170, 52)
	_melt_button.add_theme_font_size_override("font_size", 18)
	_melt_button.disabled = true
	_melt_button.pressed.connect(_try_synthesize)
	UIKit.attach_click_sfx(_melt_button, "ui_confirm")
	_melt_layer.add_child(_melt_button)

	_melt_result = UIKit.readable_label("", 11, UIKit.C_WARN)
	_melt_result.position = Vector2(430, 612)
	_melt_result.size = Vector2(340, 40)
	UIKit.soft_text_shadow(_melt_result, 1)
	_melt_layer.add_child(_melt_result)


func _make_melt_socket(index: int) -> Control:
	var socket := Button.new()
	socket.custom_minimum_size = Vector2(150, 150)
	socket.size = Vector2(150, 150)
	socket.focus_mode = Control.FOCUS_NONE
	socket.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	socket.add_theme_stylebox_override("normal", _tex_style(FORGE_SOCKET, 30, 30, 16, 12))
	socket.add_theme_stylebox_override("hover", _tex_style_tint(FORGE_SOCKET, Color(1.12, 1.06, 0.94), 30, 30, 16, 12))
	socket.add_theme_stylebox_override("pressed", _tex_style_tint(FORGE_SOCKET, Color(0.82, 0.78, 0.72), 30, 30, 16, 12))
	socket.add_theme_stylebox_override("disabled", _tex_style_tint(FORGE_SOCKET, Color(1, 1, 1, 0.55), 30, 30, 16, 12))
	socket.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var v := UIKit.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	socket.add_child(v)
	var icon_holder := CenterContainer.new()
	icon_holder.custom_minimum_size = Vector2(38, 38)
	icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(icon_holder)
	var name_lbl := UIKit.label("空", 12, Color(0.88, 0.81, 0.66))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_lbl)
	var hint_lbl := UIKit.label("材料", 9, Color(0.58, 0.50, 0.38))
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(hint_lbl)
	socket.set_meta("icon_holder", icon_holder)
	socket.set_meta("name_label", name_lbl)
	socket.set_meta("hint_label", hint_lbl)
	socket.pressed.connect(_on_synth_socket_pressed.bind(index))
	UIKit.attach_click_sfx(socket, "ui_click")
	return socket


func _build_toast() -> void:
	_toast_card = PanelContainer.new()
	_toast_card.position = TOAST_POS
	_toast_card.custom_minimum_size = Vector2(520, 46)
	_toast_card.size = Vector2(520, 46)
	_toast_card.add_theme_stylebox_override("panel",
		_tex_style(FORGE_TOAST, 30, 30, 16, 12, 18))
	_toast_card.visible = false
	_toast_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_toast_card)
	_toast_card.z_index = 30
	_toast_label = UIKit.readable_label("", 12, Color(0.20, 0.15, 0.09))
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_card.add_child(_toast_label)

# ===================== 样式工具 =====================

func _tex_style(path: String, ml: int, mr: int, mt: int, mb: int,
		content := 10, ct := 4, cb := 4) -> StyleBoxTexture:
	return _tex_style_tint(path, Color.WHITE, ml, mr, mt, mb, content, ct, cb)


func _tex_style_tint(path: String, tint: Color, ml: int, mr: int, mt: int, mb: int,
		content := 10, ct := 4, cb := 4) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = UIKit.ui_texture(path)
	sb.texture_margin_left = ml
	sb.texture_margin_right = mr
	sb.texture_margin_top = mt
	sb.texture_margin_bottom = mb
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.modulate_color = tint
	sb.content_margin_left = content
	sb.content_margin_right = content
	sb.content_margin_top = ct
	sb.content_margin_bottom = cb
	return sb


func _paper_scroll_style() -> StyleBoxTexture:
	return _tex_style(FORGE_PAPER_SCROLL, 42, 42, 36, 36, 26)


func _make_label(parent: Node, text: String, size: int, color: Color,
		centered := false) -> Label:
	var l := UIKit.label(text, size, color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


# ===================== 铭牌 / 装备 / 晶石 / 锤子 =====================

func _build_plaque() -> void:
	_plaque = PanelContainer.new()
	_plaque.position = PLAQUE_POS
	_plaque.custom_minimum_size = PLAQUE_SIZE
	_plaque.size = PLAQUE_SIZE
	# 铜牌四角有铆钉、边缘有暗圈，内容不给到 16 以上就会压在铆钉上
	_plaque.add_theme_stylebox_override("panel",
		_tex_style(FORGE_BRASS_PLAQUE, 42, 42, 34, 34, 22, 16, 12))
	_plaque.mouse_filter = Control.MOUSE_FILTER_STOP
	_plaque.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_plaque.gui_input.connect(_on_plaque_input)
	_forge_layer.add_child(_plaque)
	var v := UIKit.vbox(4)
	_plaque.add_child(v)
	# 旧黄铜底是暗的，刻字要提亮；再刷深墨就糊进铜锈里了
	_make_label(v, "锻 打 铭 牌", 10, Color(0.66, 0.55, 0.33))
	_plaque_name = _make_label(v, "空砧", 22, Color(0.99, 0.94, 0.80))
	_plaque_meta = UIKit.readable_label("把装备放上铁砧", 11, Color(0.72, 0.62, 0.40))
	_plaque_meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_plaque_meta)

	var pip_row := UIKit.hbox(5)
	pip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pip_row)
	_plaque_pip_caption = _make_label(pip_row, "磨损", 10, Color(0.66, 0.55, 0.33))
	_plaque_pip_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_plaque_pips = pip_row
	for i in 10:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(12, 6)
		# 不给 SIZE_FILL 的话 HBox 会把刻度拉满整行，铜牌上就成了一条条形码
		pip.size_flags_horizontal = Control.SIZE_FILL
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.color = _pip_empty_color()
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip_row.add_child(pip)
		_plaque_pip_nodes.append(pip)
	# 可强化词条池 + 每次成功涨幅区间：铜牌宽度只有 356，三条以上词条时自动换行
	# ⚠ 340 会把铜牌撑宽 8px（内容 340 + 左右边距 44 = 384）；按设计宽度 376 反推，
	#   换行宽度取 332，铜牌保持原尺寸。
	_plaque_affix = UIKit.readable_label("", 10, Color(0.86, 0.76, 0.50))
	_plaque_affix.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plaque_affix.custom_minimum_size = Vector2(332.0, 0.0)
	_plaque_affix.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_plaque_affix)
	_plaque_cost = UIKit.readable_label("", 11, Color(0.78, 0.68, 0.45))
	_plaque_cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_plaque_cost)
	_plaque_hint = UIKit.readable_label("点铭牌 · 展开器谱", 10, Color(0.58, 0.49, 0.30))
	_plaque_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_plaque_hint)


func _build_equipment_display() -> void:
	_equip_display = Control.new()
	_equip_display.size = Vector2(EQUIP_SIZE + 30, EQUIP_SIZE + 92)
	_equip_display.position = EQUIP_CENTER - Vector2(EQUIP_SIZE * 0.5, EQUIP_SIZE * 0.5)
	_equip_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_forge_layer.add_child(_equip_display)
	_equip_display.set_meta("tut", "forge.slot")

	var glow := UIKit.glow_node(Vector2(EQUIP_SIZE + 150, EQUIP_SIZE + 140),
		Color(1.0, 0.72, 0.38), 0.2)
	glow.position = Vector2(-60, -64)
	glow.name = "EquipGlow"
	_equip_display.add_child(glow)

	# 砧面对比度由舞台美术里那道烧黑使用痕迹负责，不再叠方框皮垫
	_equip_icon = Control.new()
	_equip_icon.name = "EquipIcon"
	_equip_icon.size = Vector2(EQUIP_SIZE, EQUIP_SIZE)
	_equip_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_equip_display.add_child(_equip_icon)

	_equip_name = UIKit.label("", 16, Color(0.98, 0.93, 0.80))
	_equip_name.position = Vector2(-15, EQUIP_SIZE + 24)
	_equip_name.size = Vector2(EQUIP_SIZE + 30, 26)
	_equip_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.soft_text_shadow(_equip_name, 1)
	_equip_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_equip_display.add_child(_equip_name)

	_equip_empty = UIKit.label("把装备放上铁砧", 15, Color(0.86, 0.80, 0.66))
	_equip_empty.position = Vector2(-15, EQUIP_SIZE * 0.42)
	_equip_empty.size = Vector2(EQUIP_SIZE + 30, 28)
	_equip_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.soft_text_shadow(_equip_empty, 1)
	_equip_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_equip_display.add_child(_equip_empty)


func _set_equip_icon(item: Dictionary) -> void:
	UIKit.clear_children(_equip_icon)
	if item.is_empty():
		return
	var icon := UIKit.equip_icon(item, Vector2(EQUIP_SIZE, EQUIP_SIZE))
	icon.position = Vector2.ZERO
	icon.size = Vector2(EQUIP_SIZE, EQUIP_SIZE)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_equip_icon.add_child(icon)


func _build_anvil_drop() -> void:
	_anvil_drop = Control.new()
	_anvil_drop.set_script(load("res://scripts/ui/panels/forge_anvil_area.gd"))
	_anvil_drop.set("panel", self)
	_anvil_drop.position = ANVIL_HIT.position
	_anvil_drop.size = ANVIL_HIT.size
	_anvil_drop.tooltip_text = "点兵器架纸签，或把装备拖到这里"
	_forge_layer.add_child(_anvil_drop)
	# 新手指引：强化 / 进阶都是「点砧面」，两步共用这一个锚点
	_anvil_drop.set_meta("tut", "forge.enhance")


func _build_take_and_dismantle() -> void:
	_take_btn = ForgeButton.new()
	_take_btn.text = "取下"
	_take_btn.setup(ForgeButton.TONE_PAPER)
	_take_btn.position = Vector2(602, 556)
	_take_btn.size = Vector2(96, 40)
	_take_btn.custom_minimum_size = Vector2(96, 40)
	_take_btn.add_theme_font_size_override("font_size", 14)
	_take_btn.pressed.connect(_on_take_from_anvil)
	# 新手指引锚点：c5 强化完教玩家点「取下」收回背包
	_take_btn.set_meta("tut", "forge.take")
	_forge_layer.add_child(_take_btn)

	_dismantle_btn = ForgeButton.new()
	_dismantle_btn.text = "分解"
	_dismantle_btn.setup(ForgeButton.TONE_PAPER)
	_dismantle_btn.position = Vector2(708, 556)
	_dismantle_btn.size = Vector2(96, 40)
	_dismantle_btn.custom_minimum_size = Vector2(96, 40)
	_dismantle_btn.add_theme_font_size_override("font_size", 14)
	_dismantle_btn.pressed.connect(_on_dismantle_ask)
	_forge_layer.add_child(_dismantle_btn)


func _build_crystal_dish() -> void:
	_crystal_dish = TextureRect.new()
	_crystal_dish.texture = UIKit.ui_texture(FORGE_CRYSTAL_DISH)
	_crystal_dish.position = DISH_POS
	_crystal_dish.size = Vector2(170, 108)
	_crystal_dish.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_crystal_dish.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_crystal_dish.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_forge_layer.add_child(_crystal_dish)
	_dish_label = UIKit.label("×0", 14, Color(0.86, 0.94, 0.96))
	_dish_label.position = DISH_POS + Vector2(56, 50)
	_dish_label.size = Vector2(92, 24)
	_dish_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.soft_text_shadow(_dish_label, 1)
	_dish_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_forge_layer.add_child(_dish_label)
	var dish_hint := UIKit.label("锻造晶石", 10, Color(0.80, 0.72, 0.56))
	dish_hint.position = DISH_POS + Vector2(52, 78)
	dish_hint.size = Vector2(100, 18)
	dish_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.soft_text_shadow(dish_hint, 1)
	dish_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_forge_layer.add_child(dish_hint)


func _build_hammer() -> void:
	_hammer_shadow = TextureRect.new()
	_hammer_shadow.texture = UIKit.ui_texture(FORGE_HAMMER_SHADOW)
	_hammer_shadow.position = HAMMER_HOME + Vector2(-22.0, 44.0)
	_hammer_shadow.size = Vector2(238, 82)
	_hammer_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hammer_shadow.stretch_mode = TextureRect.STRETCH_SCALE
	_hammer_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hammer_shadow.z_index = 19
	_forge_layer.add_child(_hammer_shadow)

	_hammer = TextureRect.new()
	_hammer.texture = UIKit.ui_texture(FORGE_HAMMER)
	_hammer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hammer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hammer.size = HAMMER_SIZE
	_hammer.position = HAMMER_HOME
	_hammer.pivot_offset = HAMMER_SIZE * HAMMER_HEAD_PIVOT
	_hammer.rotation = deg_to_rad(HAMMER_REST_DEG)
	_hammer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hammer.z_index = 20
	# 新手指引锚点：c5 教「拿起锤子」聚光在这里（锤子本体不吃鼠标，点击由
	# 面板按 HAMMER_HOME 矩形接管 —— meta 只承担定位，不影响输入）
	_hammer.set_meta("tut", "forge.hammer")
	_forge_layer.add_child(_hammer)


func _build_forge_hint() -> void:
	_forge_hint = UIKit.label("从右侧兵器架点一件装备上砧", 14, Color(0.88, 0.82, 0.68))
	_forge_hint.position = Vector2(440, 404)
	_forge_hint.size = Vector2(440, 26)
	_forge_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.soft_text_shadow(_forge_hint, 1)
	_forge_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_forge_layer.add_child(_forge_hint)


func _build_auto_forge() -> void:
	_auto_btn = ForgeButton.new()
	_auto_btn.text = "自动锻造"
	_auto_btn.setup(ForgeButton.TONE_PAPER)
	_auto_btn.position = Vector2(438, 432)
	_auto_btn.size = Vector2(130, 38)
	_auto_btn.custom_minimum_size = Vector2(130, 38)
	_auto_btn.add_theme_font_size_override("font_size", 13)
	_auto_btn.tooltip_text = "连续锻造，直到满阶 / 破损 / 晶石不足 / 境界锁"
	_auto_btn.pressed.connect(_on_auto_pressed)
	UIKit.attach_click_sfx(_auto_btn, "ui_confirm")
	_forge_layer.add_child(_auto_btn)

	_auto_stop_btn = ForgeButton.new()
	_auto_stop_btn.text = "中止"
	_auto_stop_btn.setup(ForgeButton.TONE_SEAL)
	_auto_stop_btn.position = Vector2(574, 432)
	_auto_stop_btn.size = Vector2(82, 38)
	_auto_stop_btn.custom_minimum_size = Vector2(82, 38)
	_auto_stop_btn.add_theme_font_size_override("font_size", 13)
	_auto_stop_btn.tooltip_text = "中止自动锻造（当前这一锤会挥完）"
	_auto_stop_btn.visible = false
	_auto_stop_btn.pressed.connect(_on_auto_stop_pressed)
	UIKit.attach_click_sfx(_auto_stop_btn, "ui_deny")
	_forge_layer.add_child(_auto_stop_btn)

	_auto_tip = UIKit.label("自动：满阶 / 破损 / 晶石不足即停", 10, Color(0.84, 0.74, 0.56))
	_auto_tip.position = Vector2(438, 470)
	_auto_tip.size = Vector2(300, 16)
	_auto_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_forge_layer.add_child(_auto_tip)


func _refresh_auto_buttons() -> void:
	if _auto_btn == null:
		return
	# 仙器只能点顶栏「蕴仙」一锤一锤淬炼 → 自动锻造键直接禁用（2026-11-13 用户定）
	var yunxian_only := not _anvil_item.is_empty() \
		and CharacterData.enhance_currency(_anvil_item) == CharacterData.YUNXIAN_MATERIAL
	_auto_btn.text = "自动锻造中" if _auto_forge else "自动锻造"
	_auto_btn.disabled = _auto_forge or yunxian_only
	_auto_btn.tooltip_text = "仙器不能自动锻造 —— 点上方「蕴仙」一锤一锤淬炼" if yunxian_only \
		else "连续锻造，直到满阶 / 破损 / 晶石不足 / 境界锁"
	_auto_stop_btn.visible = _auto_forge


func _on_auto_pressed() -> void:
	if _mode != MODE_FORGE:
		return
	if _anvil_item.is_empty():
		show_toast("先把装备放上铁砧", UIKit.C_WARN)
		return
	var reason := _forge_block_reason()
	if reason != "":
		GameState.play_ui("ui_deny")
		show_toast(reason, UIKit.C_DANGER)
		return
	if not _hammer_held:
		_pick_hammer()
	_auto_forge = true
	_auto_waiting = false
	_auto_token += 1
	_queued_strike = false
	_refresh_auto_buttons()
	show_toast("自动锻造开始 —— 点「中止」停止", UIKit.C_OK)
	_schedule_auto_strike()


func _on_auto_stop_pressed() -> void:
	_stop_auto(true)


func _stop_auto(show_msg: bool, reason: String = "") -> void:
	var was := _auto_forge
	_auto_forge = false
	_auto_waiting = false
	_auto_token += 1
	_queued_strike = false
	_refresh_auto_buttons()
	if not show_msg or not was:
		return
	if reason != "":
		GameState.play_ui("ui_deny")
		show_toast("自动锻造停止：%s" % reason, UIKit.C_WARN)
	else:
		show_toast("已中止自动锻造", UIKit.C_TEXT_DIM)


func _schedule_auto_strike() -> void:
	if not _auto_forge or _auto_waiting or not is_inside_tree():
		return
	_auto_waiting = true
	var token := _auto_token
	await get_tree().create_timer(0.08, true, false, true).timeout
	_auto_waiting = false
	if not is_inside_tree() or token != _auto_token or not _auto_forge:
		return
	if _mode != MODE_FORGE:
		_stop_auto(false)
		return
	if _strike_state != STRIKE_IDLE:
		return
	var reason := _forge_block_reason()
	if reason != "":
		_stop_auto(true, reason)
		return
	if not _hammer_held:
		_pick_hammer()
		if not _hammer_held:
			_stop_auto(true, "锤子没有拿起")
			return
	_begin_strike(EQUIP_CENTER)


func _on_plaque_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if not _anvil_item.is_empty():
			GameState.play_ui("ui_click")
			_show_anvil_manual()
		else:
			show_toast("先把装备放上铁砧", UIKit.C_WARN)


# ===================== 刷新 =====================

func _refresh_content() -> void:
	if not is_inside_tree():
		return
	_refresh_forge()
	_refresh_rail()
	_refresh_synth()
	_refresh_mode_ui()
	# 新手指引镜像：砧上有没有东西，教学 cond 轮询读它（见 GameState 注释）
	GameState.forge_anvil_id = String(_anvil_item.get("id", "")) \
		if not _anvil_item.is_empty() else ""


func _refresh_forge() -> void:
	if _plaque == null:
		return
	var item := _anvil_item
	var empty := item.is_empty()
	var crystals := CharacterData.count_material(CharacterData.ENHANCE_MATERIAL)
	_top_crystal_label.text = "晶石 ×%d" % crystals
	_dish_label.text = "×%d" % crystals
	# 三枚材料动作始终带持有数（空砧 / 禁用时也能看见资源）
	var divine_have := CharacterData.count_material(CharacterData.DIVINE_MATERIAL)
	var mend_have := CharacterData.count_material(CharacterData.MEND_MATERIAL)
	var yunxian_have := CharacterData.count_material(CharacterData.YUNXIAN_MATERIAL)
	_divine_btn.text = "铸神 ×%d" % divine_have
	_mend_btn.text = "补天 ×%d" % mend_have
	_yunxian_btn.text = "蕴仙 ×%d" % yunxian_have
	_refresh_auto_buttons()

	if empty:
		_set_equip_icon({})
		_equip_empty.visible = true
		_equip_empty.text = "把装备放上铁砧"
		_equip_name.text = ""
		_equip_name.add_theme_color_override("font_color", Color(0.98, 0.93, 0.80))
		_plaque_name.text = "空砧"
		_plaque_name.add_theme_color_override("font_color", Color(0.99, 0.94, 0.80))
		_plaque_meta.text = "把装备放上铁砧"
		_plaque_cost.text = "待放置装备"
		if _plaque_affix != null:
			_plaque_affix.text = ""
			_plaque_affix.visible = false
		_plaque_cost.add_theme_color_override("font_color", Color(0.55, 0.47, 0.30))
		_plaque_hint.text = "点铭牌 · 展开器谱"
		if _plaque_pips != null:
			_plaque_pips.visible = true
		_take_btn.disabled = true
		_dismantle_btn.disabled = true
		_divine_btn.disabled = true
		_mend_btn.disabled = true
		_yunxian_btn.disabled = true
		_forge_hint.text = "从右侧兵器架点一件装备上砧"
		_forge_hint.add_theme_color_override("font_color", Color(0.88, 0.82, 0.68))
		if _plaque_pip_caption != null:
			_plaque_pip_caption.text = "磨损"
		_set_pips([])
		_update_equip_glow(Color(0.65, 0.55, 0.38), 0.10)
		return

	_set_equip_icon(item)
	_equip_empty.visible = false
	var enh := maxi(0, int(item.get("enhancement_level", 0)))
	var is_treasure := String(item.get("equipment_type", "")) == "treasure"
	_equip_name.text = ItemDB.equipped_display_name(item)
	var grade := String(item.get("equipment_grade", ""))
	# 砧上装备名与铭牌名都按品阶着色，和装备格 / 器谱标题同一套七色环
	var name_color := UIKit.grade_color(grade) if grade != "" else Color(0.98, 0.93, 0.80)
	_equip_name.add_theme_color_override("font_color", name_color)
	var broken := bool(item.get("is_broken", false))
	# 神器 = 最高品阶（非法宝）：没有强化等级、没有磨损、不能再锻造（2026-11-13）
	var is_divine := (not is_treasure) and ItemDB.is_max_grade(grade)
	# 满 +10 仙器：普通敲击不再进阶，唯一出口是铸神
	var divine_ready := (not is_treasure) and not is_divine and not broken \
		and grade == "仙器" and enh >= ItemDB.MAX_ENHANCE
	var cost_id := CharacterData.enhance_currency(item)
	var cost_n := CharacterData.enhance_currency_cost(item)
	var cost_have := CharacterData.count_material(cost_id)
	var cost_name := ItemDB.get_material_name(cost_id)
	# 磨损流水（2026-11-13 用户定）：普通/进阶按发生顺序排；进阶格记失败当时品阶色
	# 神器也保留旧痕（铸神已不再清零），只是之后不会再加新磨损
	var wear_seq: Array = [] if is_treasure else CharacterData.ensure_wear_seq(item)
	var normal_wear := 0
	for e in wear_seq:
		if e is Dictionary and String((e as Dictionary).get("k", "")) == "n":
			normal_wear += 1
	if _plaque_pip_caption != null:
		_plaque_pip_caption.text = "磨损"
	_plaque_name.text = ItemDB.equipped_display_name(item)
	_plaque_name.add_theme_color_override("font_color", name_color)
	if is_treasure:
		# 法宝不带词条，没有 +N 强化与磨损；品阶就是进阶次数
		_plaque_meta.text = "%s · 法宝 · 可进阶" % (grade if grade != "" else "无品阶")
		if _plaque_pips != null:
			_plaque_pips.visible = false
	elif is_divine:
		# 神器没有强化数，但旧痕要看得见（2026-11-13 用户定）；数量放到磨损刻度行首
		_plaque_meta.text = "%s · 已铸神 · 不可强化" % grade
		if _plaque_pip_caption != null:
			_plaque_pip_caption.text = ItemDB.wear_text(item)
		if _plaque_pips != null:
			_plaque_pips.visible = true
	else:
		_plaque_meta.text = "%s · 强化 %s · %s" % [
			grade if grade != "" else "无品阶", ItemDB.enhance_text(item), ItemDB.wear_text(item)]
		if _plaque_pips != null:
			_plaque_pips.visible = true
	# 强化词条池 + 每次成功的涨幅区间（法宝 / 神器 / 不可强化返回空 → 整行收起）
	if _plaque_affix != null:
		_plaque_affix.text = "" if (is_treasure or is_divine) else ItemDB.enhance_affix_line(item)
		_plaque_affix.visible = _plaque_affix.text != ""
	if is_divine:
		_plaque_cost.text = "神兵已成 · 无需晶石"
		_plaque_cost.add_theme_color_override("font_color", Color(0.72, 0.62, 0.40))
	elif divine_ready:
		_plaque_cost.text = "铸神晶 ×1　持有 %d" % divine_have
		_plaque_cost.add_theme_color_override("font_color",
			Color(0.98, 0.48, 0.34) if divine_have < 1 else Color(0.78, 0.68, 0.45))
	elif is_treasure:
		_plaque_cost.text = "进阶晶石 ×%d　持有 %d" % [cost_n, cost_have]
		_plaque_cost.add_theme_color_override("font_color",
			Color(0.98, 0.48, 0.34) if cost_have < cost_n else Color(0.78, 0.68, 0.45))
	else:
		# 仙器 = 蕴仙髓 ×1；其余 = 锻造晶石 ×品阶数（2026-11-13）
		_plaque_cost.text = "%s ×%d　持有 %d" % [cost_name, cost_n, cost_have]
		_plaque_cost.add_theme_color_override("font_color",
			Color(0.98, 0.48, 0.34) if cost_have < cost_n else Color(0.78, 0.68, 0.45))
	_take_btn.disabled = false
	# ⚠ 禁令装备（彩蛋装 问天剑）：按钮**不隐藏**，改成「不可分解」并禁用 ——
	#   凭空少一个按钮会让人怀疑面板坏了；写清原因才算回执（同背包里突破材料的口径）。
	var can_smelt := CharacterData.can_dismantle_item(item)
	_dismantle_btn.disabled = not can_smelt
	_dismantle_btn.text = "分解" if can_smelt else "不可分解"
	_dismantle_btn.tooltip_text = "" if can_smelt else "传家之物 —— 这件装备不能分解"
	if is_treasure:
		_set_pips([])
	else:
		_set_pips(wear_seq)
	# 铸神 / 补天 / 蕴仙动作（数量在上面已刷新）
	_divine_btn.disabled = not divine_ready or divine_have < 1
	_mend_btn.disabled = is_treasure or is_divine or normal_wear <= 0 or mend_have < 1
	# 蕴仙：只有仙器（非法宝）用它淬炼；破损 / 境界锁 / 满 +10 / 髓不足都禁用
	_yunxian_btn.disabled = is_treasure or is_divine \
		or cost_id != CharacterData.YUNXIAN_MATERIAL or _forge_block_reason(true) != ""
	var lock_msg := ItemDB.realm_lock_message(grade, CharacterData.current_realm)
	# 化神期仙器（非法宝）例外：用蕴仙髓继续淬炼，不走境界锁提示
	var xian_at_huashen := (not is_treasure) and grade == "仙器" and CharacterData.is_huashen()
	if is_divine:
		_plaque_hint.text = "神器 · 没有强化等级"
		_forge_hint.text = "神器已成 —— 无法再强化"
		_forge_hint.add_theme_color_override("font_color", UIKit.C_ASCEND)
	elif divine_ready:
		_plaque_hint.text = "满 +10 · 用铸神晶铸神"
		_forge_hint.text = "点「铸神」把它铸成神器" if divine_have >= 1 \
			else "铸神晶不足 —— 去大世界的铸神祭坛取"
		_forge_hint.add_theme_color_override("font_color",
			UIKit.C_ASCEND if divine_have >= 1 else UIKit.C_WARN)
	elif ItemDB.has_equipment_flag(item, "cannot_enhance"):
		# 传家之物：境界再高也不解锁，所以别写成「突破后解锁」误导人
		_plaque_hint.text = "传家之物 · 不可强化"
		_forge_hint.text = "这件装备是传家之物 —— 敲不动，也别分解"
		_forge_hint.add_theme_color_override("font_color", UIKit.C_DANGER)
	elif broken:
		# 破损但普通磨损还能补：别写成「只能分解」把补天这条活路藏掉
		if normal_wear > 0:
			_plaque_hint.text = "已破损 · 可用补天石补回"
			_forge_hint.text = "点「补天」清掉普通磨损" if mend_have > 0 else "补天石不足 —— 化神后祭坛可再取"
			_forge_hint.add_theme_color_override("font_color",
				UIKit.C_OK if mend_have > 0 else UIKit.C_WARN)
		else:
			_plaque_hint.text = "已破损 · 进阶失败磨损占满"
			_forge_hint.text = "装备已破损 —— 只能分解或取下"
			_forge_hint.add_theme_color_override("font_color", UIKit.C_DANGER)
	elif lock_msg != "" and not xian_at_huashen:
		_plaque_hint.text = "境界锁 · 突破后解锁"
		_forge_hint.text = "境界不足，暂时敲不动"
		_forge_hint.add_theme_color_override("font_color", UIKit.C_WARN)
	elif cost_have < cost_n:
		_plaque_hint.text = "仙器 · 只认顶栏「蕴仙」" \
			if cost_id == CharacterData.YUNXIAN_MATERIAL else "强化 · 锻造晶石"
		_forge_hint.text = "%s不足" % cost_name
		_forge_hint.add_theme_color_override("font_color", UIKit.C_WARN)
	elif is_treasure:
		_plaque_hint.text = "法宝 · 进阶增强主动效果"
		_forge_hint.text = "点击砧面进阶" if _hammer_held else "先点石台上的锤子拿起锤子"
		_forge_hint.add_theme_color_override("font_color", Color(0.88, 0.82, 0.68))
	elif cost_id == CharacterData.YUNXIAN_MATERIAL:
		_plaque_hint.text = "仙器 · 只认顶栏「蕴仙」"
		_forge_hint.text = "仙器只能点上方「蕴仙」—— 一锤一锤淬炼"
		_forge_hint.add_theme_color_override("font_color", Color(0.88, 0.82, 0.68))
	else:
		_plaque_hint.text = "强化 · 锻造晶石"
		_forge_hint.text = "点击砧面锻造" if _hammer_held else "先点石台上的锤子拿起锤子"
		_forge_hint.add_theme_color_override("font_color", Color(0.88, 0.82, 0.68))
	_update_equip_glow(UIKit.grade_color(grade) if grade != "" else Color(0.85, 0.72, 0.42), 0.22)


## 普通失败磨损：亮灰（2026-11-13 用户定，替代原来的近黑）
const NORMAL_WEAR_COLOR := Color(0.72, 0.74, 0.78, 1.0)


## 磨损刻度：按发生顺序逐格上色（最旧在左，新磨损往右接）：
##   普通失败 = 亮灰；进阶失败 = 失败当时的品阶色（记录在流水里，不会随进阶变色）。
func _set_pips(seq: Array) -> void:
	for i in _plaque_pip_nodes.size():
		var pip := _plaque_pip_nodes[i]
		if i >= seq.size():
			pip.color = _pip_empty_color()
			continue
		var e = seq[i]
		var kind := String((e as Dictionary).get("k", "")) if e is Dictionary else "n"
		if kind == "a":
			var g := String((e as Dictionary).get("g", ""))
			pip.color = UIKit.grade_color(g) if g != "" else Color(0.85, 0.72, 0.42)
		else:
			pip.color = NORMAL_WEAR_COLOR


func _pip_empty_color() -> Color:
	return Color(0.13, 0.10, 0.05, 0.85)


func _update_equip_glow(color: Color, alpha: float) -> void:
	var glow := _equip_display.get_node_or_null("EquipGlow") as TextureRect
	if glow == null:
		return
	glow.modulate = Color(color.r, color.g, color.b, alpha)


func _refresh_rail() -> void:
	if _equipped_grid == null:
		return
	UIKit.clear_children(_equipped_grid)
	for slot in CharacterData.WORN_SLOT_ORDER:
		var slot_id := String(slot)
		var it := CharacterData.get_equipped(slot_id)
		var tag := ForgeTagSlot.new()
		tag.setup(it, self, "worn", -1, slot_id, true)
		_equipped_grid.add_child(tag)
	UIKit.clear_children(_bag_grid)
	var bag_items: Array = []
	for raw in CharacterData.inventory:
		var it: Dictionary = raw
		if String(it.get("type", "")) == CharacterData.ITEM_EQUIPMENT:
			bag_items.append(it)
	for i in bag_items.size():
		var it: Dictionary = bag_items[i]
		var idx := _inventory_index_of(it)
		var tag := ForgeTagSlot.new()
		tag.setup(it, self, "bag", idx, "", false)
		_bag_grid.add_child(tag)
	if bag_items.is_empty():
		var none := UIKit.label("背包里没有装备", 10, Color(0.52, 0.46, 0.35))
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_bag_grid.add_child(none)
	_bag_count.text = "%d 件" % bag_items.size()
	_refresh_spine_icon()


func _inventory_index_of(item: Dictionary) -> int:
	for i in CharacterData.inventory.size():
		if is_same(CharacterData.inventory[i], item):
			return i
	return -1


func _refresh_spine_icon() -> void:
	if _rail_spine_icon == null:
		return
	var weapon := CharacterData.get_equipped("weapon")
	if weapon.is_empty():
		_rail_spine_icon.texture = null
	else:
		var icon_path := String(weapon.get("icon", ""))
		_rail_spine_icon.texture = UIKit.ui_texture(icon_path)


func _refresh_mode_ui() -> void:
	if _forge_tab == null:
		return
	_forge_tab.set_selected(_mode == MODE_FORGE)
	_melt_tab.set_selected(_mode == MODE_MELT)
	_forge_layer.visible = _mode == MODE_FORGE
	_hammer.visible = _mode == MODE_FORGE
	_melt_layer.visible = _mode == MODE_MELT
	# 熔铸页没有铁砧动作：材料钮收起（晶石读数留着，熔铸也用得上）
	_mend_btn.visible = _mode == MODE_FORGE
	_divine_btn.visible = _mode == MODE_FORGE
	_yunxian_btn.visible = _mode == MODE_FORGE
	# 熔铸的三口全靠自己点选候选，兵器架在这页是死控件，留着只会挡镜头
	_rail.visible = _mode == MODE_FORGE


# ===================== 兵器架开合 =====================

func _set_rail_open(open: bool, instant := false) -> void:
	_rail_open = open
	if _rail_handle != null:
		_rail_handle.text = "›" if open else "‹"
	# 展开后兵器架自己就写着「拖上砧」，窄脊上的图标和竖排名字反而和架顶重复
	if _rail_spine_icon != null:
		_rail_spine_icon.visible = not open
	if _rail_spine_label != null:
		_rail_spine_label.visible = not open
	var target_x := VIEW.x - RAIL_W if open else VIEW.x - SPINE_W
	if instant:
		_rail.position.x = target_x
		return
	if _rail_tween != null and _rail_tween.is_valid():
		_rail_tween.kill()
	_rail_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_rail_tween.tween_property(_rail, "position:x", target_x, 0.32) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _toggle_rail() -> void:
	_set_rail_open(not _rail_open)


func _on_spine_hover() -> void:
	if _rail_open:
		return
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(0.22, true).timeout
	if is_inside_tree() and not _rail_open and _rail_spine.get_global_rect().has_point(
			get_viewport().get_mouse_position()):
		_set_rail_open(true)


# ===================== 开场 / Toast / 配置 =====================

func _play_fire_intro() -> void:
	if _intro_played:
		return
	_intro_played = true
	_furnace_glow.modulate.a = 0.0
	_fx.fire_level = 0.2
	_fx.fire_enabled = true
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_furnace_glow, "modulate:a", 0.42, 0.65) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(_set_fire_level, 0.2, 1.0, 0.65)


func _set_fire_level(v: float) -> void:
	if _fx != null:
		_fx.fire_level = v


func show_toast(text: String, color: Color = UIKit.C_OK) -> void:
	if _toast_card == null:
		return
	_toast_label.text = text
	_toast_label.add_theme_color_override("font_color", _toast_ink(color))
	_toast_card.visible = true
	_toast_card.modulate.a = 1.0
	if _toast_card.has_meta("tw"):
		var old: Tween = _toast_card.get_meta("tw")
		if old != null and old.is_valid():
			old.kill()
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(1.9)
	tw.tween_property(_toast_card, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func() -> void: _toast_card.visible = false)
	_toast_card.set_meta("tw", tw)


## 提示条是浅色羊皮纸，语义色要压暗成墨色才读得清
func _toast_ink(c: Color) -> Color:
	return Color(c.r * 0.42 + 0.04, c.g * 0.40 + 0.03, c.b * 0.36 + 0.02, 1.0)


func _hide_toast() -> void:
	if _toast_card == null:
		return
	if _toast_card.has_meta("tw"):
		var old: Tween = _toast_card.get_meta("tw")
		if old != null and old.is_valid():
			old.kill()
	_toast_card.visible = false


func set_status(text: String, color: Color = UIKit.C_OK) -> void:
	show_toast(text, color)


func _load_config() -> void:
	var err := _config.load(CFG_PATH)
	if err == OK:
		_tutorial_seen = bool(_config.get_value("ui", "forge_tutorial_seen", false))
	else:
		_tutorial_seen = false


func _save_tutorial_seen() -> void:
	_config.set_value("ui", "forge_tutorial_seen", true)
	_config.save(CFG_PATH)


# ===================== 主循环 / 点击 =====================

var _time := 0.0
var _intro_t := 0.0


func _process(delta: float) -> void:
	_time += delta
	_intro_t += delta
	if _intro_t > 0.75 and _furnace_glow != null:
		_furnace_glow.modulate.a = 0.38 + 0.05 * sin(_time * 3.1)
	if _mode == MODE_FORGE and _hammer_held and not _special_busy \
			and _strike_state == STRIKE_IDLE and _hammer != null:
		var m := _world.get_local_mouse_position()
		_hammer.position = m - _hammer.pivot_offset
		_hammer.rotation = deg_to_rad(HAMMER_HELD_DEG)
	if not _rail_open and get_viewport() != null and get_viewport().gui_is_dragging():
		var mouse := get_viewport().get_mouse_position()
		if mouse.x > VIEW.x - 100.0:
			_set_rail_open(true)
	_tick_drag_icon()


func _handle_left_click(mouse: Vector2) -> void:
	if _special_busy:
		return
	if _detail_layer != null or _tutorial_layer != null or _candidate_layer != null \
			or _treasure_layer != null:
		return
	if _mode == MODE_MELT:
		if ANVIL_HIT.has_point(mouse):
			_switch_mode(MODE_FORGE)
		return
	# 兵器架盖住的区域不抢点击：用它真实的左缘，而不是写死的整条 RAIL_W
	var world := Rect2(0.0, TOP_H, _rail.position.x, VIEW.y - TOP_H)
	if not world.has_point(mouse):
		return
	# 锤子优先判定：收起兵器架后整条右缘是死区，别把石台上的锤子挡在后面
	if _hammer_home_rect().has_point(mouse):
		if _hammer_held:
			_drop_hammer()
		else:
			_pick_hammer()
		return
	if FURNACE_RECT.has_point(mouse) and not _hammer_held:
		_switch_mode(MODE_MELT)
		return
	if _hammer_held:
		if ANVIL_HIT.has_point(mouse):
			_try_strike(mouse)
		return
	if ANVIL_HIT.has_point(mouse):
		if _anvil_item.is_empty():
			show_toast("先把装备放上铁砧", UIKit.C_WARN)
		else:
			GameState.play_ui("ui_click")
			_show_anvil_manual()


func _hammer_home_rect() -> Rect2:
	return Rect2(HAMMER_HOME - Vector2(24, 36), HAMMER_SIZE + Vector2(54, 76))


func _pick_hammer() -> void:
	_hammer_held = true
	_hammer_shadow.visible = false
	# 新手指引镜像 + 事件：c5「拿起锤子」步（cond 兜底读 GameState，见其注释）
	GameState.forge_hammer_held = true
	Tutorial.note("forge_hammer")
	GameState.play_ui("forge_hammer_pick")
	show_toast("锤子已拿起 —— 点击砧面开始锻造", UIKit.C_ACCENT)
	_refresh_forge()


func _drop_hammer() -> void:
	if _strike_state != STRIKE_IDLE:
		return
	_hammer_held = false
	GameState.forge_hammer_held = false
	_hammer.position = HAMMER_HOME
	_hammer.rotation = deg_to_rad(HAMMER_REST_DEG)
	_hammer_shadow.visible = true
	GameState.play_ui("forge_hammer_down")
	show_toast("锤子已放回石台")
	_refresh_forge()


# ===================== 锻造状态机 =====================

## via_yunxian=true 只给顶栏「蕴仙」专用通道；常规敲砧 / 自动锻造一律走 false
func _forge_block_reason(via_yunxian := false) -> String:
	if _anvil_item.is_empty():
		return "铁砧上还没有装备。"
	if bool(_anvil_item.get("is_broken", false)):
		return "装备已破损，无法继续强化（可分解）。"
	var grade := String(_anvil_item.get("equipment_grade", ""))
	var is_treasure := String(_anvil_item.get("equipment_type", "")) == "treasure"
	var enh := maxi(0, int(_anvil_item.get("enhancement_level", 0)))
	# 神器没有强化等级（2026-11-13 用户定）
	if ItemDB.is_max_grade(grade):
		return "已达最高品阶（%s），无法再进阶" % grade if is_treasure \
			else "神器已成，无法再强化（没有强化等级）"
	# 仙器满 +10：普通敲击不再进阶，只能铸神
	if (not is_treasure) and enh >= ItemDB.MAX_ENHANCE \
			and ItemDB.is_max_grade(ItemDB.next_grade(grade)):
		return "仙器已满 +10：点「铸神」铸成神器（普通敲击不再进阶）"
	var lock_msg := ItemDB.realm_lock_message(grade, CharacterData.current_realm)
	if lock_msg != "" and not ((not is_treasure) and grade == "仙器" and CharacterData.is_huashen()):
		return lock_msg
	var cost_id := CharacterData.enhance_currency(_anvil_item)
	# 仙器只认顶栏「蕴仙」：常规敲砧与自动锻造都不能动用蕴仙髓（2026-11-13 用户定）
	if cost_id == CharacterData.YUNXIAN_MATERIAL and not via_yunxian:
		return "仙器只能点上方「蕴仙」淬炼 —— 常规锻造与自动锻造不可用"
	var cost_n := CharacterData.enhance_currency_cost(_anvil_item)
	var have := CharacterData.count_material(cost_id)
	if have < cost_n:
		return "%s不足：本次需要 %d 枚（当前 %d 枚）。" % [
			ItemDB.get_material_name(cost_id), cost_n, have]
	return ""


func _try_strike(target: Vector2) -> void:
	if _special_busy:
		return
	if not _hammer_held or _anvil_item.is_empty():
		return
	var reason := _forge_block_reason()
	if reason != "":
		GameState.play_ui("ui_deny")
		show_toast(reason, UIKit.C_DANGER)
		_fx.spawn_strike(target, Color(0.85, 0.35, 0.22, 0.8), 8, 0.35)
		return
	if _strike_state != STRIKE_IDLE:
		if not _queued_strike:
			_queued_strike = true
			_queued_target = target
		return
	_begin_strike(target)


func _begin_strike(target: Vector2) -> void:
	_strike_state = STRIKE_WINDUP
	_strike_target = _anvil_hit_point(target)
	_strike_seq += 1
	var seq := _strike_seq
	GameState.play_ui("forge_swing")
	_swing_tw = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_swing_tw.tween_property(_hammer, "position",
		_strike_target - _hammer.pivot_offset + Vector2(70, -150), 0.10) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_swing_tw.parallel().tween_property(_hammer, "rotation", deg_to_rad(-34.0), 0.10)
	_swing_tw.tween_property(_hammer, "position", _strike_target - _hammer.pivot_offset, 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_swing_tw.parallel().tween_property(_hammer, "rotation", deg_to_rad(28.0), 0.12)
	_swing_tw.tween_callback(_on_hammer_impact.bind(seq))


## 砧上有装备时，锤要落在装备上；空砧才落在玩家点的地方
func _anvil_hit_point(clicked: Vector2) -> Vector2:
	if _anvil_item.is_empty():
		return clicked
	return EQUIP_CENTER


func _on_hammer_impact(seq: int) -> void:
	if seq != _strike_seq or not is_inside_tree():
		return
	_strike_state = STRIKE_IMPACT
	_commit_forge()
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(0.055)
	tw.tween_callback(_recover_hammer)


func _commit_forge(via_yunxian := false) -> void:
	var reason := _forge_block_reason(via_yunxian)
	if reason != "":
		GameState.play_ui("ui_deny")
		show_toast(reason, UIKit.C_DANGER)
		return
	var cost := ItemDB.enhance_crystal_cost(_anvil_item) 		if CharacterData.enhance_currency(_anvil_item) == CharacterData.ENHANCE_MATERIAL else 0
	var target := _strike_target
	var res: Dictionary = CharacterData.enhance_item(_anvil_item)
	if not bool(res.get("ok", false)):
		GameState.play_ui("ui_deny")
		show_toast(String(res.get("message", "无法强化")), UIKit.C_DANGER)
		if _auto_forge:
			_stop_auto(false)
		_refresh_forge()
		return
	GameState.play_ui("forge_hammer")
	# 新手指引：成功敲成一锤 = 强化过一次（进阶也算在同一锤里，由下面单独报）
	Tutorial.note("forge_enhance")
	if String(res.get("result", "")) == ItemDB.ENHANCE_RESULT_ASCEND:
		Tutorial.note("forge_advance")
	_play_enhance_result_sfx(String(res.get("result", "")))
	var great := String(res.get("result", "")) == ItemDB.ENHANCE_RESULT_GREAT \
		or String(res.get("result", "")) == ItemDB.ENHANCE_RESULT_ASCEND
	_shake_world(7.0 if great else 4.0)
	_fx.spawn_strike(target, Color(1.0, 0.66, 0.24, 1.0), 34 if great else 24,
		1.35 if great else 1.0)
	if cost > 0:
		_fx.spawn_crystal_trail(Vector2(DISH_POS.x + 82, DISH_POS.y + 48), target)
	_show_result_float(res)
	show_toast(String(res.get("message", "")), _result_color(String(res.get("result", ""))))
	_refresh_forge()


func _recover_hammer() -> void:
	_strike_state = STRIKE_RECOVER
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var home := HAMMER_HOME
	if _hammer_held:
		home = _world.get_local_mouse_position() - _hammer.pivot_offset
	tw.tween_property(_hammer, "position", home, 0.10) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_hammer, "rotation", deg_to_rad(HAMMER_HELD_DEG), 0.10)
	tw.tween_callback(_finish_recover)


func _finish_recover() -> void:
	_strike_state = STRIKE_IDLE
	if _queued_strike:
		_queued_strike = false
		var reason := _forge_block_reason()
		if reason != "":
			GameState.play_ui("ui_deny")
			show_toast(reason, UIKit.C_DANGER)
			return
		_begin_strike(_queued_target)
		return
	if _auto_forge:
		_schedule_auto_strike()


func _play_enhance_result_sfx(result: String) -> void:
	var sfx := "forge_success"
	match result:
		ItemDB.ENHANCE_RESULT_GREAT, ItemDB.ENHANCE_RESULT_ASCEND:
			sfx = "forge_great"
		ItemDB.ENHANCE_RESULT_FAIL, ItemDB.ENHANCE_RESULT_ASCEND_FAIL, ItemDB.ENHANCE_RESULT_BROKEN:
			sfx = "forge_fail"
	GameState.play_ui_delayed(sfx, 0.09)


func _result_color(result: String) -> Color:
	match result:
		ItemDB.ENHANCE_RESULT_GREAT:
			return UIKit.C_GREAT
		ItemDB.ENHANCE_RESULT_SUCCESS:
			return UIKit.C_OK
		ItemDB.ENHANCE_RESULT_ASCEND:
			return UIKit.C_ASCEND
		ItemDB.ENHANCE_RESULT_ASCEND_FAIL:
			return UIKit.C_WARN
		ItemDB.ENHANCE_RESULT_BROKEN:
			return UIKit.C_DANGER
		_:
			return UIKit.C_WARN


func _shake_world(strength: float) -> void:
	if _mode != MODE_FORGE:
		return
	var base := _world.position
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	for i in 3:
		tw.tween_property(_world, "position", base + Vector2(strength, 0), 0.025)
		tw.tween_property(_world, "position", base - Vector2(strength, 0), 0.025)
	tw.tween_property(_world, "position", base, 0.04)


func _show_result_float(res: Dictionary) -> void:
	var result := String(res.get("result", ""))
	var head := "强化成功"
	var color := UIKit.C_OK
	match result:
		ItemDB.ENHANCE_RESULT_GREAT:
			head = "大成功"
			color = UIKit.C_GREAT
		ItemDB.ENHANCE_RESULT_ASCEND:
			head = "进阶成功"
			color = UIKit.C_ASCEND
		ItemDB.ENHANCE_RESULT_ASCEND_FAIL:
			head = "进阶失败"
			color = UIKit.C_WARN
		ItemDB.ENHANCE_RESULT_FAIL:
			head = "强化失败"
			color = UIKit.C_WARN
		ItemDB.ENHANCE_RESULT_BROKEN:
			head = "装备破损"
			color = UIKit.C_DANGER
	var main := UIKit.label(head, 30, color)
	main.position = Vector2(410, 318)
	main.size = Vector2(480, 46)
	main.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.soft_text_shadow(main, 1)
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_float_layer.add_child(main)

	var lines: Array[String] = []
	var gains: Array = res.get("attr_gains", [])
	var gain_text := ItemDB.enhance_gain_text(gains)
	if gain_text != "":
		lines.append(gain_text)
	var extra := String(res.get("extra_gain_text", ""))
	if extra != "":
		lines.append(extra)
	if result == ItemDB.ENHANCE_RESULT_FAIL:
		lines.append("磨损 +1（等级与属性未变）")
	elif result == ItemDB.ENHANCE_RESULT_ASCEND_FAIL:
		lines.append("品阶不变（法宝不会掉阶）" if bool(res.get("is_treasure", false))
			else "等级清零，品阶与属性保留；磨损 +1")
	elif result == ItemDB.ENHANCE_RESULT_BROKEN:
		lines.append("磨损 10 / 10，强化永久停止")
	var sub: Label = null
	if not lines.is_empty():
		sub = UIKit.readable_label("　".join(lines), 12, color.lightened(0.18))
		sub.position = Vector2(410, 364)
		sub.size = Vector2(480, 44)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UIKit.soft_text_shadow(sub, 1)
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_float_layer.add_child(sub)

	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(main, "position:y", 292.0, 0.75) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(main, "modulate:a", 0.0, 0.75).set_delay(0.18)
	if sub != null:
		tw.parallel().tween_property(sub, "position:y", 338.0, 0.75) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(sub, "modulate:a", 0.0, 0.75).set_delay(0.18)
	tw.tween_callback(main.queue_free)
	if sub != null:
		tw.tween_callback(sub.queue_free)

	if result == ItemDB.ENHANCE_RESULT_GREAT or result == ItemDB.ENHANCE_RESULT_ASCEND:
		var seal := PanelContainer.new()
		seal.position = Vector2(766, 300)
		seal.custom_minimum_size = Vector2(82, 82)
		seal.size = Vector2(82, 82)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.58, 0.16, 0.12, 0.94)
		sb.border_color = Color(0.92, 0.72, 0.40, 0.9)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		seal.add_theme_stylebox_override("panel", sb)
		seal.rotation = deg_to_rad(-9.0)
		seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sl := UIKit.label("大成" if result == ItemDB.ENHANCE_RESULT_GREAT else "进阶",
			20, Color(0.98, 0.91, 0.76))
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seal.add_child(sl)
		_float_layer.add_child(seal)
		var st := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		st.tween_property(seal, "scale", Vector2.ONE, 0.22).from(Vector2(1.7, 1.7)) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		st.tween_interval(0.55)
		st.tween_property(seal, "modulate:a", 0.0, 0.3)
		st.tween_callback(seal.queue_free)


# ===================== 装备上砧 / 取下 / 拖拽 =====================

## 背包挂签单击：自动放上铁砧（2026-10-27 用户要求）。
## 砧上已有装备时走与拖拽相同的安全交换：旧装备回背包。
func _on_bag_clicked(index: int) -> void:
	if index < 0 or index >= CharacterData.inventory.size():
		show_toast("这件装备已不在背包里。", UIKit.C_DANGER)
		_refresh_content()
		return
	var item: Dictionary = CharacterData.inventory[index]
	if String(item.get("type", "")) != CharacterData.ITEM_EQUIPMENT:
		return
	_move_bag_to_anvil(index)


func _on_take_from_anvil() -> void:
	_stop_auto(false)
	if _anvil_item.is_empty():
		show_toast("砧上没有装备。", UIKit.C_WARN)
		return
	var name := ItemDB.equipped_display_name(_anvil_item)
	if not CharacterData.return_from_forge(_anvil_item):
		show_toast("背包已满，放不下「%s」。" % name, UIKit.C_DANGER)
		return
	_anvil_item = {}
	_set_rail_open(true)
	GameState.play_ui("ui_equip")
	# 新手指引：c5「点取下收回背包」听这个事件
	Tutorial.note("forge_take")
	show_toast("已把 %s 取回背包" % name, UIKit.C_OK)
	_refresh_content()


## 拖拽跟随：缩小的半透明装备图标（兵器架 / 铁砧共用）
func _make_item_drag_preview(item: Dictionary) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.modulate = Color(1.0, 1.0, 1.0, 0.72)
	var icon_size := Vector2(48.0, 48.0)
	# 直接用 TextureRect 画裁边贴图：容器类（CenterContainer）在拖拽层里可能拿不到布局
	var icon := TextureRect.new()
	icon.texture = ForgeTagSlot._trimmed_texture(String(item.get("icon", "")))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = icon_size
	icon.position = -icon_size * 0.5
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(icon)
	return root


## 每帧：拖拽中把图标画在 _overlay_layer（z 高于兵器架），并跟随鼠标。
## 引擎的 drag preview 会被锻造面板这个 CanvasLayer 盖住，所以不用它。
func _tick_drag_icon() -> void:
	if _mode != MODE_FORGE or not is_inside_tree():
		if _drag_icon != null:
			_drag_icon.visible = false
		return
	if not get_viewport().gui_is_dragging():
		if _drag_icon != null:
			_drag_icon.visible = false
		_drag_icon_key = ""
		return
	var data: Variant = get_viewport().gui_get_drag_data()
	if not (data is Dictionary) or String((data as Dictionary).get("kind", "")) != "forge_drag":
		if _drag_icon != null:
			_drag_icon.visible = false
		return
	var item := _item_from_drag(data)
	if item.is_empty():
		if _drag_icon != null:
			_drag_icon.visible = false
		return
	var key := "%s:%s:%s" % [String((data as Dictionary).get("from", "")),
		int((data as Dictionary).get("index", -1)),
		String((data as Dictionary).get("slot", ""))]
	if _drag_icon == null or key != _drag_icon_key:
		if _drag_icon != null and is_instance_valid(_drag_icon):
			_drag_icon.queue_free()
		_drag_icon = _make_item_drag_preview(item)
		_overlay_layer.add_child(_drag_icon)
		_drag_icon.z_index = 200
		_drag_icon_key = key
	_drag_icon.visible = true
	_drag_icon.position = _overlay_layer.get_local_mouse_position()


## 拖拽一律「非破坏」：拖动时只携带来源标识，装备留在原处；
## 只有成功放下才真的移动。失败/取消 → 什么都不变，杜绝装备消失。
func _make_anvil_drag() -> Variant:
	if _anvil_item.is_empty():
		return null
	return {"kind": "forge_drag", "from": "anvil",
		"name": String(_anvil_item.get("name", ""))}


func _item_from_drag(d: Dictionary) -> Dictionary:
	match String(d.get("from", "")):
		"bag":
			var idx := int(d.get("index", -1))
			if idx < 0 or idx >= CharacterData.inventory.size():
				return {}
			var it: Dictionary = CharacterData.inventory[idx]
			if String(it.get("type", "")) != CharacterData.ITEM_EQUIPMENT:
				return {}
			return it
		"worn":
			return CharacterData.get_equipped(String(d.get("slot", "")))
		"anvil":
			return _anvil_item
	return {}


func _can_drop_on_anvil(data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var d: Dictionary = data
	if String(d.get("kind", "")) != "forge_drag":
		return false
	if String(d.get("from", "")) == "anvil":
		return false
	return not _item_from_drag(d).is_empty()


func _can_drop_on_bag(data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var d: Dictionary = data
	if String(d.get("kind", "")) != "forge_drag":
		return false
	match String(d.get("from", "")):
		"anvil":
			return not _anvil_item.is_empty()
		"worn":
			return not CharacterData.get_equipped(String(d.get("slot", ""))).is_empty()
	return false


## 挂签/兵器架底板拖放转发用（带 at 参数）
func _can_drop_on_bag_at(_at: Vector2, data: Variant) -> bool:
	return _can_drop_on_bag(data)


func _drop_on_bag_at(_at: Vector2, data: Variant) -> void:
	if data is Dictionary:
		_on_forge_drop_to_bag(data)


func _on_forge_drop_on_anvil(data: Dictionary) -> void:
	match String(data.get("from", "")):
		"bag":
			_move_bag_to_anvil(int(data.get("index", -1)))
		"worn":
			_move_worn_to_anvil(String(data.get("slot", "")))


func _on_forge_drop_to_bag(data: Dictionary) -> void:
	match String(data.get("from", "")):
		"worn":
			var slot := String(data.get("slot", ""))
			var item := CharacterData.get_equipped(slot)
			if item.is_empty():
				_forge_deny("这件装备已不在身上。")
				_refresh_content()
				return
			if not CharacterData.unequip_to_inventory(slot):
				_forge_deny("背包已满，无法卸下。")
				return
			GameState.play_ui("ui_equip")
			show_toast("已卸下 %s" % ItemDB.equipped_display_name(item))
			_set_rail_open(true)
			_refresh_content()
		"anvil":
			if _anvil_item.is_empty():
				return
			var item := _anvil_item
			if not CharacterData.return_from_forge(item):
				_forge_deny("背包已满，放不下「%s」。" % ItemDB.equipped_display_name(item))
				return
			_anvil_item = {}
			GameState.play_ui("ui_equip")
			show_toast("已把 %s 放回背包" % ItemDB.equipped_display_name(item))
			_refresh_content()


func _forge_deny(text: String) -> void:
	GameState.play_ui("ui_deny")
	show_toast(text, UIKit.C_WARN)


## 背包 → 铁砧：砧上有装备则交换（旧装备回背包）
func _move_bag_to_anvil(index: int) -> void:
	_stop_auto(false)
	var r: Dictionary = CharacterData.take_for_forge(index)
	var item: Dictionary = r.get("item", {})
	if item.is_empty():
		_forge_deny(String(r.get("reason", "这件装备取不出来。")))
		_refresh_content()
		return
	var old := _anvil_item
	if not old.is_empty():
		# 刚腾出一个背包格，旧砧上装备一定能放回去；仍失败则回滚
		if not CharacterData.return_from_forge(old):
			_anvil_item = old
			CharacterData.return_item_or_force(item)
			_forge_deny("背包已满，无法更换铁砧上的装备。")
			_refresh_content()
			return
	_anvil_item = item
	_set_rail_open(false)
	GameState.play_ui("ui_equip")
	# 新手指引：c5「把铁剑拖到铁砧上」听这个事件（单击挂签与拖拽两条路都汇到这）
	Tutorial.note("forge_place")
	if old.is_empty():
		show_toast("已把 %s 放上铁砧" % ItemDB.equipped_display_name(item), UIKit.C_OK)
	else:
		show_toast("已换上 %s，%s 已回背包" % [ItemDB.equipped_display_name(item),
			ItemDB.equipped_display_name(old)], UIKit.C_OK)
	_refresh_content()


## 身上 → 铁砧：砧上有装备则先放回背包（背包满则整次操作作废）
func _move_worn_to_anvil(slot: String) -> void:
	_stop_auto(false)
	var worn := CharacterData.get_equipped(slot)
	if worn.is_empty():
		_forge_deny("这个槽位没有装备。")
		_refresh_content()
		return
	var old := _anvil_item
	if not old.is_empty() and not CharacterData.bag_has_room(old):
		_forge_deny("背包已满，无法更换铁砧上的装备。")
		return
	var r: Dictionary = CharacterData.take_for_forge(-1, slot)
	var item: Dictionary = r.get("item", {})
	if item.is_empty():
		_forge_deny(String(r.get("reason", "这件装备取不下来。")))
		_refresh_content()
		return
	if not old.is_empty() and not CharacterData.return_from_forge(old):
		# 理论上不会发生（空间已预检），兜底把装备穿回去
		CharacterData.equip(slot, item)
		if not CharacterData.is_held_by_slot(item):
			CharacterData.return_item_or_force(item)
		_forge_deny("背包已满，无法更换铁砧上的装备。")
		_refresh_content()
		return
	_anvil_item = item
	GameState.play_ui("ui_equip")
	# 新手指引：c5 上砧步的事件（身上 → 铁砧这条拖拽路）
	Tutorial.note("forge_place")
	show_toast("已把 %s 从身上放上铁砧" % ItemDB.equipped_display_name(item), UIKit.C_OK)
	_refresh_content()


## 铁砧 → 身上：槽里有装备则交换，旧装备留在铁砧上
func _move_anvil_to_worn(slot: String) -> void:
	_stop_auto(false)
	if _anvil_item.is_empty():
		return
	var a := _anvil_item
	if not CharacterData.slot_accepts(slot, String(a.get("equipment_type", ""))):
		_forge_deny("这件装备放不进【%s】" % CharacterData.slot_display_name(slot))
		return
	var dup := CharacterData.equip_dup_slot(a, slot)
	if dup != "":
		_forge_deny("「%s」已经戴在【%s】了。" % [String(a.get("name", "")),
			CharacterData.slot_display_name(dup)])
		return
	var b := CharacterData.get_equipped(slot)
	CharacterData.unequip(slot)
	CharacterData.equip(slot, a)
	if not CharacterData.is_held_by_slot(a):
		# 穿戴失败：砧上装备保持原样，槽里原装备放回去
		if not b.is_empty():
			CharacterData.equip(slot, b)
			if not CharacterData.is_held_by_slot(b):
				CharacterData.return_item_or_force(b)
		_forge_deny("穿戴失败，已保持原样。")
		_refresh_content()
		return
	_anvil_item = b if not b.is_empty() else {}
	GameState.play_ui("ui_equip")
	if b.is_empty():
		show_toast("已穿戴 %s" % ItemDB.equipped_display_name(a))
	else:
		show_toast("已穿戴 %s，%s 放上铁砧" % [ItemDB.equipped_display_name(a),
			ItemDB.equipped_display_name(b)])
	_refresh_content()


## 身上 → 另一个槽：两槽互换（类型都匹配才允许）
func _move_worn_to_worn(src: String, dst: String) -> void:
	if src == dst:
		return
	var a := CharacterData.get_equipped(src)
	var b := CharacterData.get_equipped(dst)
	if a.is_empty():
		_forge_deny("这件装备已不在身上。")
		_refresh_content()
		return
	if not CharacterData.slot_accepts(dst, String(a.get("equipment_type", ""))):
		_forge_deny("这件装备放不进【%s】" % CharacterData.slot_display_name(dst))
		return
	if not b.is_empty():
		if not CharacterData.slot_accepts(src, String(b.get("equipment_type", ""))):
			_forge_deny("【%s】的装备换不回【%s】" % [
				CharacterData.slot_display_name(dst), CharacterData.slot_display_name(src)])
			return
		var dup_a := CharacterData.equip_dup_slot(a, dst)
		var dup_b := CharacterData.equip_dup_slot(b, src)
		if (dup_a != "" and dup_a != src) or (dup_b != "" and dup_b != dst):
			var blocker := b if (dup_b != "" and dup_b != dst) else a
			_forge_deny("同种%s不能重复佩戴。" % String(CharacterData.EQUIP_TYPE_DISPLAY.get(
				String(blocker.get("equipment_type", "")), "装备")))
			return
	CharacterData.unequip(src)
	CharacterData.unequip(dst)
	CharacterData.equip(dst, a)
	var ok_a := CharacterData.is_held_by_slot(a)
	if not b.is_empty():
		CharacterData.equip(src, b)
	var ok_b := b.is_empty() or CharacterData.is_held_by_slot(b)
	if not ok_a or not ok_b:
		# 回滚到原来的两个槽；极端情况下兜底进背包，绝不消失
		CharacterData.unequip(src)
		CharacterData.unequip(dst)
		CharacterData.equip(src, a)
		if not CharacterData.is_held_by_slot(a):
			CharacterData.return_item_or_force(a)
		if not b.is_empty():
			CharacterData.equip(dst, b)
			if not CharacterData.is_held_by_slot(b):
				CharacterData.return_item_or_force(b)
		_forge_deny("换位失败，已恢复原样。")
		_refresh_content()
		return
	GameState.play_ui("ui_equip")
	if b.is_empty():
		show_toast("已把 %s 换到【%s】" % [ItemDB.equipped_display_name(a),
			CharacterData.slot_display_name(dst)])
	else:
		show_toast("已互换 %s ↔ %s" % [ItemDB.equipped_display_name(a),
			ItemDB.equipped_display_name(b)])
	_refresh_content()


func _on_equip(index: int, prefer_slot := "") -> void:
	if index < 0 or index >= CharacterData.inventory.size():
		show_toast("装备已不在背包里。", UIKit.C_DANGER)
		_refresh_content()
		return
	var item: Dictionary = CharacterData.inventory[index]
	var name := ItemDB.equipped_display_name(item)
	var target := prefer_slot
	if target == "":
		target = CharacterData.first_free_slot(String(item.get("equipment_type", "")))
	var dup := CharacterData.equip_dup_slot(item, target)
	if dup != "":
		GameState.play_ui("ui_deny")
		show_toast("「%s」已经戴在【%s】了。" % [name,
			CharacterData.slot_display_name(dup)], UIKit.C_WARN)
		return
	var old := CharacterData.equip_from_inventory(index, prefer_slot)
	if CharacterData.is_held_by_slot(item):
		GameState.play_ui("ui_equip")
		show_toast("已穿戴：%s" % name)
	else:
		GameState.play_ui("ui_deny")
		show_toast("穿戴失败。", UIKit.C_DANGER)
	if not old.is_empty():
		show_toast("已穿戴 %s，换下 %s（已回背包）" % [
			name, ItemDB.equipped_display_name(old)])
	_refresh_content()


func _can_drop_on_worn(_at: Vector2, data: Variant, slot: String) -> bool:
	if not (data is Dictionary):
		return false
	var d: Dictionary = data
	if String(d.get("kind", "")) != "forge_drag":
		return false
	var from := String(d.get("from", ""))
	if from == "worn" and String(d.get("slot", "")) == slot:
		return false
	var item := _item_from_drag(d)
	if item.is_empty():
		return false
	if not CharacterData.slot_accepts(slot, String(item.get("equipment_type", ""))):
		return false
	# 从另一个槽换过来时，源槽会清空，不算重复
	var src_slot := String(d.get("slot", "")) if from == "worn" else ""
	var dup := CharacterData.equip_dup_slot(item, slot)
	if dup != "" and dup != src_slot:
		return false
	if from == "worn":
		var target_item := CharacterData.get_equipped(slot)
		if not target_item.is_empty():
			if not CharacterData.slot_accepts(src_slot,
					String(target_item.get("equipment_type", ""))):
				return false
			var dup_back := CharacterData.equip_dup_slot(target_item, src_slot)
			if dup_back != "" and dup_back != slot:
				return false
	return true


func _drop_on_worn(_at: Vector2, data: Variant, slot: String) -> void:
	if not (data is Dictionary):
		return
	var d: Dictionary = data
	if not _can_drop_on_worn(_at, d, slot):
		GameState.play_ui("ui_deny")
		var item := _item_from_drag(d)
		var src_slot := String(d.get("slot", "")) if String(d.get("from", "")) == "worn" else ""
		var dup := CharacterData.equip_dup_slot(item, slot)
		if not item.is_empty() and dup != "" and dup != src_slot:
			show_toast("「%s」已经戴在【%s】了。" % [ItemDB.equipped_display_name(item),
				CharacterData.slot_display_name(dup)], UIKit.C_WARN)
		else:
			show_toast("这件装备放不进【%s】" % CharacterData.slot_display_name(slot),
				UIKit.C_WARN)
		return
	match String(d.get("from", "")):
		"bag":
			_on_equip(int(d.get("index", -1)), slot)
		"worn":
			_move_worn_to_worn(String(d.get("slot", "")), slot)
		"anvil":
			_move_anvil_to_worn(slot)


func _on_unequip(slot: String) -> void:
	if not CharacterData.unequip_to_inventory(slot):
		GameState.play_ui("ui_deny")
		show_toast("背包已满，无法卸下。", UIKit.C_WARN)
		return
	GameState.play_ui("ui_equip")
	show_toast("已卸下 %s" % CharacterData.slot_display_name(slot))
	_refresh_content()


## 铸神：满 +10 仙器 + 铸神晶 ×1 → 神器（2026-11-13 用户定）
func _on_divine_pressed() -> void:
	_begin_special("divine")


## 补天：补天石 ×1 清掉普通失败磨损，进阶失败的磨损保留（2026-11-13 用户定）
func _on_mend_pressed() -> void:
	_begin_special("mend")


## 蕴仙：仙器每敲一锤消耗蕴仙髓 ×1（2026-11-13 用户定）
func _on_yunxian_pressed() -> void:
	_begin_special("yunxian")


func _special_button(kind: String) -> ForgeButton:
	match kind:
		"divine":
			return _divine_btn
		"mend":
			return _mend_btn
		"yunxian":
			return _yunxian_btn
	return null


func _special_icon_path(kind: String) -> String:
	match kind:
		"divine":
			return "res://assets/ui/icon/mat_zhushenjing.png"
		"mend":
			return "res://assets/ui/icon/mat_butianshi.png"
		"yunxian":
			return "res://assets/ui/icon/mat_yunxiansui.png"
	return ""


## 材料动作的完整演出：材料从顶栏飞上装备 → 锤子自动落一下 → 装备亮起对应光色。
## 数据在**落锤那一拍**才结算（材料没落上去就关面板 = 不消耗）。
func _begin_special(kind: String) -> void:
	if _special_busy or _anvil_item.is_empty() or _mode != MODE_FORGE:
		return
	var src_btn := _special_button(kind)
	if src_btn == null or src_btn.disabled:
		return
	_stop_auto(false)
	_special_busy = true
	_take_btn.disabled = true
	_dismantle_btn.disabled = true
	_divine_btn.disabled = true
	_mend_btn.disabled = true
	_yunxian_btn.disabled = true
	var icon := TextureRect.new()
	icon.texture = UIKit.ui_texture(_special_icon_path(kind))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = Vector2(48, 48)
	icon.pivot_offset = Vector2(24, 24)
	var src_center := _forge_layer.get_global_transform().affine_inverse() \
		* src_btn.get_global_rect().get_center()
	icon.position = src_center - icon.size * 0.5
	icon.z_index = 26
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_forge_layer.add_child(icon)
	_special_icon = icon
	GameState.play_ui("pickup")
	var target := EQUIP_CENTER - icon.size * 0.5 + Vector2(0, -18)
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(icon, "position", target, 0.34) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(icon, "rotation", deg_to_rad(16.0), 0.34)
	tw.tween_interval(0.06)
	tw.tween_property(icon, "scale", Vector2(0.65, 0.65), 0.12)
	tw.parallel().tween_property(icon, "modulate:a", 0.0, 0.12)
	tw.tween_callback(_special_swing.bind(kind))


func _special_swing(kind: String) -> void:
	if not is_inside_tree():
		return
	GameState.play_ui("forge_swing")
	var target := _anvil_hit_point(EQUIP_CENTER)
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_hammer, "position",
		target - _hammer.pivot_offset + Vector2(70, -150), 0.10) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_hammer, "rotation", deg_to_rad(-34.0), 0.10)
	tw.tween_property(_hammer, "position", target - _hammer.pivot_offset, 0.12) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_hammer, "rotation", deg_to_rad(28.0), 0.12)
	tw.tween_callback(_special_impact.bind(kind))


func _special_impact(kind: String) -> void:
	if not is_inside_tree():
		return
	if _special_icon != null and is_instance_valid(_special_icon):
		_special_icon.queue_free()
	_special_icon = null
	if kind == "yunxian":
		# 蕴仙 = 普通一锤：扣 1 枚髓后走原强化链路（结果 / 磨损 / 进阶都不另算）
		_strike_target = EQUIP_CENTER
		_commit_forge(true)
		_flash_equip_glow(SPECIAL_YUNXIAN_COLOR, 0.60)
		_finish_special()
		return
	var is_divine := kind == "divine"
	var res: Dictionary
	if is_divine:
		res = CharacterData.forge_divine(_anvil_item)
	else:
		res = CharacterData.mend_item(_anvil_item)
	if not bool(res.get("ok", false)):
		GameState.play_ui("ui_deny")
		show_toast(String(res.get("message", "无法完成")), UIKit.C_DANGER)
		_refresh_content()
		_finish_special()
		return
	var color := SPECIAL_DIVINE_COLOR if is_divine else SPECIAL_MEND_COLOR
	GameState.play_ui("forge_hammer")
	GameState.play_ui_delayed("forge_great" if is_divine else "forge_success", 0.09)
	_fx.spawn_strike(EQUIP_CENTER, color, 40 if is_divine else 18, 1.6 if is_divine else 1.0)
	_shake_world(7.0 if is_divine else 4.0)
	show_toast(String(res.get("message", "")),
		UIKit.C_ASCEND if is_divine else UIKit.C_OK)
	_refresh_content()
	_flash_equip_glow(color, 0.85 if is_divine else 0.65)
	_finish_special()


## 装备亮起：先按操作色冲到峰值，再缓缓落回该装备品阶色（不同操作不同光芒）
func _flash_equip_glow(color: Color, peak: float) -> void:
	_last_special_flash = color
	var glow := _equip_display.get_node_or_null("EquipGlow") as TextureRect
	if glow == null:
		return
	if _glow_tw != null and _glow_tw.is_valid():
		_glow_tw.kill()
	glow.modulate = Color(color.r, color.g, color.b, peak)
	var grade := String(_anvil_item.get("equipment_grade", ""))
	var base := UIKit.grade_color(grade) if grade != "" else Color(0.85, 0.72, 0.42)
	_glow_tw = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_glow_tw.tween_property(glow, "modulate",
		Color(base.r, base.g, base.b, 0.22), 0.90) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _finish_special() -> void:
	_special_busy = false
	if not is_inside_tree():
		return
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var home := HAMMER_HOME
	if _hammer_held:
		home = _world.get_local_mouse_position() - _hammer.pivot_offset
	else:
		_hammer_shadow.visible = true
	tw.tween_property(_hammer, "position", home, 0.12) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_hammer, "rotation",
		deg_to_rad(HAMMER_HELD_DEG if _hammer_held else HAMMER_REST_DEG), 0.12)


func _on_dismantle_ask() -> void:
	_stop_auto(false)
	if _anvil_item.is_empty():
		show_toast("砧上没有装备可分解。", UIKit.C_WARN)
		return
	# 禁令装备：连确认框都不该弹（按钮已禁用，这里是别的路径调进来时的兜底）
	if not CharacterData.can_dismantle_item(_anvil_item):
		show_toast("「%s」是传家之物，不可分解。" % String(_anvil_item.get("name", "这件装备")),
			UIKit.C_WARN)
		return
	var name := String(_anvil_item.get("name", "装备"))
	var refund := ItemDB.dismantle_refund(_anvil_item)
	var extra := "分解后返还锻造晶石 ×%d。" % refund if refund > 0 else "这件装备没有消耗过晶石，无返还。"
	var msg := "确定分解「%s」吗？\n已强化的属性会一并消失，无法恢复。\n%s" % [name, extra]
	ConfirmDialog.ask("分解装备", msg, "分解", "取消", _do_dismantle, true)


func _do_dismantle() -> void:
	_stop_auto(false)
	if _anvil_item.is_empty():
		return
	# ⚠ 拒绝时**绝不能清空 _anvil_item**：砧上的装备已经脱离背包，
	#   一清就是一件装备凭空消失。必须留在砧上，让玩家自己「取下」。
	if not CharacterData.can_dismantle_item(_anvil_item):
		show_toast("「%s」是传家之物，不可分解。" % String(_anvil_item.get("name", "这件装备")),
			UIKit.C_WARN)
		return
	var name := String(_anvil_item.get("name", "装备"))
	var refund := CharacterData.dismantle_item(_anvil_item)
	_anvil_item = {}
	_set_rail_open(true)
	if refund > 0:
		show_toast("已分解「%s」，返还锻造晶石 ×%d" % [name, refund])
	else:
		show_toast("已分解「%s」" % name, UIKit.C_TEXT_DIM)
	_refresh_content()


# ===================== 锻造说明（左上角木牌）=====================

## 点左上角「锻造说明」木牌：用纸卷盖一层说明层，内容直接读 GuideDB 的「装备强化」章
## （单一母本：改 guide_db 一处，指引书与工坊木牌同时更新）。
func _show_forge_help() -> void:
	if _help_layer != null and is_instance_valid(_help_layer):
		return
	_help_layer = Control.new()
	_help_layer.name = "ForgeHelp"
	_help_layer.size = VIEW
	_help_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_layer.add_child(_help_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.58)
	dim.size = VIEW
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_close_forge_help())
	_help_layer.add_child(dim)

	var box := PanelContainer.new()
	box.position = Vector2(250.0, 96.0)
	box.size = Vector2(780.0, 548.0)
	box.add_theme_stylebox_override("panel", _paper_scroll_style())
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	_help_layer.add_child(box)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	box.add_child(margin)
	var v := UIKit.vbox(6)
	margin.add_child(v)
	var head := UIKit.hbox(10)
	v.add_child(head)
	head.add_child(UIKit.label("锻 造 说 明", 19, Color(0.22, 0.16, 0.10)))
	head.add_child(UIKit.label("装备强化 · 进阶 · 破损", 11, Color(0.47, 0.38, 0.26)))
	head.add_child(UIKit.spacer())
	var close_btn := ForgeButton.new()
	close_btn.text = "收起"
	close_btn.setup(ForgeButton.TONE_PAPER)
	close_btn.custom_minimum_size = Vector2(72, 30)
	UIKit.set_readable_font(close_btn, 11)
	close_btn.pressed.connect(_close_forge_help)
	head.add_child(close_btn)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var body := UIKit.vbox(5)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	for raw in GuideDB.chapter_blocks(GuideDB.chapter_index_by_id("enhance")):
		var b: Dictionary = raw
		var node := _help_block(String(b.get("t", "p")), String(b.get("x", "")))
		if node != null:
			body.add_child(node)
	body.add_child(UIKit.readable_label("点空白处或「收起」关闭。",
		9, Color(0.44, 0.37, 0.26)))


## 说明页的单条排版：与指引书同一套层级（小节 / 强调 / 要点 / 提示）
func _help_block(kind: String, text: String) -> Control:
	if text == "":
		return null
	match kind:
		"s":
			var sec := UIKit.readable_label(text, UIKit.F_SUBTITLE, Color(0.45, 0.30, 0.11))
			sec.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var wrap := MarginContainer.new()
			wrap.add_theme_constant_override("margin_top", 8)
			wrap.add_child(sec)
			return wrap
		"k":
			return _help_line("▸ " + text, UIKit.F_BODY, Color(0.22, 0.15, 0.08))
		"b":
			return _help_line("· " + text, UIKit.F_BODY, Color(0.33, 0.26, 0.17))
		"tip":
			return _help_line("提示：" + text, UIKit.F_SMALL, Color(0.47, 0.40, 0.28))
		_:
			return _help_line(text, UIKit.F_BODY, Color(0.36, 0.29, 0.20))


func _help_line(text: String, size: int, color: Color) -> Label:
	var l := UIKit.readable_label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _close_forge_help() -> void:
	if _help_layer != null and is_instance_valid(_help_layer):
		_help_layer.queue_free()
	_help_layer = null


# ===================== 器谱 / 详情 =====================

func _show_anvil_manual() -> void:
	if _anvil_item.is_empty():
		return
	_show_item_detail(_anvil_item, "砧上装备")


func _show_item_detail(item: Dictionary, source: String) -> void:
	if item.is_empty():
		return
	_close_item_detail()
	_detail_layer = Control.new()
	_detail_layer.name = "ForgeManual"
	_detail_layer.size = VIEW
	_detail_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_layer.add_child(_detail_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.58)
	dim.size = VIEW
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_close_item_detail()
	)
	_detail_layer.add_child(dim)
	var box := PanelContainer.new()
	box.position = Vector2(380, 112)
	box.size = Vector2(620, 500)
	box.add_theme_stylebox_override("panel", _paper_scroll_style())
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	_detail_layer.add_child(box)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	box.add_child(margin)
	var v := UIKit.vbox(6)
	margin.add_child(v)
	var head := UIKit.hbox(8)
	v.add_child(head)
	head.add_child(UIKit.label("器谱 · %s" % source, 11, Color(0.43, 0.35, 0.23)))
	head.add_child(UIKit.label(ItemDB.equipped_display_name(item), 20,
		UIKit.grade_color(String(item.get("equipment_grade", "")))))
	head.add_child(UIKit.spacer())
	var close_btn := ForgeButton.new()
	close_btn.text = "收起"
	close_btn.setup(ForgeButton.TONE_PAPER)
	close_btn.custom_minimum_size = Vector2(72, 32)
	UIKit.set_readable_font(close_btn, 11)
	close_btn.pressed.connect(_close_item_detail)
	head.add_child(close_btn)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var body := UIKit.vbox(4)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	for entry in _detail_lines(item, source):
		var color: Color = entry.get("color", UIKit.C_TEXT)
		var lbl := UIKit.readable_label(String(entry.get("text", "")),
			int(entry.get("size", UIKit.F_SMALL)), color)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(lbl)
	var foot := UIKit.readable_label("点空白处或「收起」关闭。右键背包/已穿戴装备也能打开器谱。",
		9, Color(0.44, 0.37, 0.26))
	body.add_child(foot)


func _close_item_detail() -> void:
	if _detail_layer != null and is_instance_valid(_detail_layer):
		_detail_layer.queue_free()
	_detail_layer = null


func _detail_lines(item: Dictionary, source: String) -> Array:
	var out: Array = []
	var grade := String(item.get("equipment_grade", ""))
	# 法宝：不显示属性/强化/磨损，只显示主动效果与进阶预览（2026-11-01 用户定）
	if String(item.get("equipment_type", "")) == "treasure":
		out.append({
			"text": "%s · 法宝（无属性词条）" % (grade if grade != "" else "无品阶"),
			"size": UIKit.F_SMALL, "color": Color(0.42, 0.35, 0.24),
		})
		out.append({"text": "法宝不附带属性词条；进阶只增强主动效果。",
			"size": UIKit.F_SMALL, "color": Color(0.36, 0.42, 0.26)})
		var lock_msg_t := ItemDB.realm_lock_message(grade, CharacterData.current_realm)
		if lock_msg_t != "":
			out.append({"text": lock_msg_t, "size": UIKit.F_SMALL, "color": Color(0.62, 0.38, 0.12)})
		out.append({"text": "—— 当前主动 ——", "size": UIKit.F_SMALL,
			"color": Color(0.53, 0.39, 0.19)})
		for line in ItemDB.treasure_effect_lines(item):
			out.append({"text": line, "size": UIKit.F_SMALL, "color": Color(0.28, 0.40, 0.22)})
		var next_grade := ItemDB.next_grade(grade)
		if next_grade != grade:
			out.append({"text": "—— 进阶后 ——", "size": UIKit.F_SMALL,
				"color": Color(0.53, 0.39, 0.19)})
			var preview := item.duplicate(true)
			preview["equipment_grade"] = next_grade
			# 召唤令的成长写在实例字段里，不按品阶现算；预览要手动加一次进阶收益
			var tr_tpl := ItemDB.get_treasure_template(String(item.get("id", "")))
			if String(tr_tpl.get("summon_boss_id", "")) != "":
				preview["summon_duration_bonus"] = int(item.get("summon_duration_bonus", 0)) + 1
				preview["summon_ascend_boost_pct"] = float(item.get("summon_ascend_boost_pct", 0.0)) \
					+ CharacterData.SUMMON_ASCEND_BOOST_PER_GRADE
			for line in ItemDB.treasure_effect_lines(preview):
				out.append({"text": line, "size": UIKit.F_SMALL, "color": Color(0.34, 0.46, 0.26)})
		else:
			out.append({"text": "已达最高品阶。", "size": UIKit.F_SMALL,
				"color": Color(0.55, 0.45, 0.28)})
		out.append({"text": "进阶消耗：锻造晶石 ×%d" % ItemDB.enhance_crystal_cost(item),
			"size": UIKit.F_SMALL, "color": Color(0.50, 0.36, 0.18)})
		var tdesc := String(item.get("desc", ""))
		if tdesc != "":
			out.append({"text": "—— 说明 ——", "size": UIKit.F_SMALL, "color": Color(0.53, 0.39, 0.19)})
			out.append({"text": tdesc, "size": UIKit.F_SMALL, "color": Color(0.40, 0.35, 0.27)})
		if source.begins_with("已穿戴"):
			out.append({"text": "已穿戴：战斗中按对应法宝键使用",
				"size": UIKit.F_SMALL, "color": Color(0.28, 0.40, 0.22)})
		return out
	var is_divine_detail := ItemDB.is_max_grade(grade) and String(item.get("equipment_type", "")) != "treasure"
	if is_divine_detail:
		# 神器没有强化等级（2026-11-13）：不显示 +N / 磨损 / 境界锁
		out.append({
			"text": "%s · 已铸神 · 不可强化" % (grade if grade != "" else "无品阶"),
			"size": UIKit.F_SMALL, "color": Color(0.42, 0.35, 0.24),
		})
	else:
		out.append({
			"text": "%s · 强化 %s · %s" % [
				grade if grade != "" else "无品阶", ItemDB.enhance_text(item),
				ItemDB.wear_text(item)],
			"size": UIKit.F_SMALL, "color": Color(0.42, 0.35, 0.24),
		})
		if bool(item.get("is_broken", false)):
			out.append({"text": "已破损：无法继续强化（仍可穿戴 / 召唤）",
				"size": UIKit.F_SMALL, "color": Color(0.62, 0.20, 0.14)})
		var lock_msg := ItemDB.realm_lock_message(grade, CharacterData.current_realm)
		var xian_open := String(item.get("equipment_type", "")) != "treasure" 			and grade == "仙器" and CharacterData.is_huashen()
		if lock_msg != "" and not xian_open:
			out.append({"text": lock_msg, "size": UIKit.F_SMALL, "color": Color(0.62, 0.38, 0.12)})
	out.append({"text": "—— 属性加成 ——", "size": UIKit.F_SMALL, "color": Color(0.53, 0.39, 0.19)})
	var attr_txt := ItemDB.item_attributes_with_gain_text(item)
	out.append({"text": attr_txt if attr_txt != "" else "（这件装备没有属性词条）",
		"size": UIKit.F_BODY, "color": Color(0.18, 0.14, 0.10)})
	var base = item.get("attributes_base", {})
	var attrs_now := ItemDB.item_attributes(item)
	var has_gain := false
	if base is Dictionary:
		for id in (base as Dictionary).keys():
			if absf(float(attrs_now.get(String(id), 0.0)) - float((base as Dictionary)[id])) >= 0.005:
				has_gain = true
				break
	if has_gain:
		var parts: Array[String] = []
		for id in (base as Dictionary).keys():
			parts.append("%s %s" % [AttributeDB.attr_name(String(id)),
				ItemDB._signed_value(String(id), float((base as Dictionary)[id]))])
		out.append({"text": "强化前：" + "、".join(parts),
			"size": UIKit.F_SMALL, "color": Color(0.46, 0.40, 0.31)})
	var atk := ItemDB.attack_bonus_text(item)
	if atk != "":
		out.append({"text": "攻击加成：%s" % atk, "size": UIKit.F_SMALL, "color": Color(0.24, 0.17, 0.09)})
	for line in ItemDB.treasure_effect_lines(item):
		out.append({"text": line, "size": UIKit.F_SMALL, "color": Color(0.28, 0.40, 0.22)})
	var desc := String(item.get("desc", ""))
	if desc != "":
		out.append({"text": "—— 说明 ——", "size": UIKit.F_SMALL, "color": Color(0.53, 0.39, 0.19)})
		out.append({"text": desc, "size": UIKit.F_SMALL, "color": Color(0.40, 0.35, 0.27)})
	if source.begins_with("已穿戴"):
		out.append({"text": "已穿戴：以上数值已计入角色属性面板",
			"size": UIKit.F_SMALL, "color": Color(0.28, 0.40, 0.22)})
	return out


func _close_top_overlay() -> bool:
	if _help_layer != null:
		_close_forge_help()
		return true
	if _detail_layer != null:
		_close_item_detail()
		return true
	if _candidate_layer != null:
		_close_candidates()
		return true
	if _treasure_layer != null:
		_close_treasure()
		return true
	if _tutorial_layer != null:
		_close_tutorial(true)
		return true
	return false

# ===================== 模式切换 / 炉膛镜头 =====================

func _switch_mode(new_mode: String) -> void:
	if _special_busy or _melting or new_mode == _mode:
		return
	_stop_auto(false)
	_close_top_overlay()
	_hide_toast()
	if new_mode == MODE_MELT and _hammer_held:
		_hammer_held = false
		_hammer.position = HAMMER_HOME
		_hammer.rotation = deg_to_rad(HAMMER_REST_DEG)
	_hammer_shadow.visible = not _hammer_held
	_mode = new_mode
	GameState.play_ui("ui_tab")
	_refresh_mode_ui()
	if _mode == MODE_MELT:
		_set_rail_open(false)
		_refresh_synth()
		_melt_layer.modulate.a = 0.0
		if _camera_tw != null and _camera_tw.is_valid():
			_camera_tw.kill()
		_world.pivot_offset = FURNACE_CENTER
		_camera_tw = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_camera_tw.set_parallel(true)
		_camera_tw.tween_property(_world, "scale", Vector2(1.32, 1.32), 0.45) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_camera_tw.tween_property(_world, "position",
			Vector2(440, 398) - FURNACE_CENTER * 1.32, 0.45) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_camera_tw.tween_property(_melt_layer, "modulate:a", 1.0, 0.3).set_delay(0.18)
		if _fx != null:
			_fx.fire_level = 1.45
	else:
		if _camera_tw != null and _camera_tw.is_valid():
			_camera_tw.kill()
		_camera_tw = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_camera_tw.set_parallel(true)
		_camera_tw.tween_property(_world, "scale", Vector2.ONE, 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_camera_tw.tween_property(_world, "position", Vector2.ZERO, 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_camera_tw.tween_property(_melt_layer, "modulate:a", 0.0, 0.18)
		_camera_tw.chain().tween_callback(func() -> void:
			if is_inside_tree():
				_melt_layer.visible = false
				_world.pivot_offset = Vector2.ZERO
				_refresh_forge()
		)
		if _fx != null:
			_fx.fire_level = 1.0
		if _anvil_item.is_empty():
			_set_rail_open(true)


# ===================== 熔铸（点击选格，配方自动识别） =====================

## 当前已投入的项（保持放入顺序；配方判断一律按内容集合，不看槽位）
func _synth_filled() -> Array:
	var out: Array = []
	for d in _synth_slot_data:
		if not (d as Dictionary).is_empty():
			out.append(d)
	return out


## 三格是否正好凑齐某条位面配方（三件各 1、不重复、不看顺序）
func _matched_plane_recipe() -> Dictionary:
	var filled := _synth_filled()
	if filled.size() != 3:
		return {}
	var ids: Array = []
	for d in filled:
		ids.append(String((d as Dictionary).get("id", "")))
	if ids[0] == ids[1] or ids[0] == ids[2] or ids[1] == ids[2]:
		return {}
	for raw in ItemDB.PLANE_TREASURE_RECIPES:
		var r := raw as Dictionary
		var mats: Array = r.get("material_ids", [])
		if mats.size() != 3:
			continue
		var ok := true
		for mid in mats:
			if not (String(mid) in ids):
				ok = false
				break
		if ok:
			return r
	return {}


## 两格是否正好是同一档的「地髓 + 天髓」（顺序不限）
func _matched_pojing_recipe() -> Dictionary:
	var filled := _synth_filled()
	if filled.size() != 2:
		return {}
	var ids: Array = []
	for d in filled:
		if String((d as Dictionary).get("kind", "")) != SYNTH_KIND_POJING:
			return {}
		ids.append(String((d as Dictionary).get("id", "")))
	return ItemDB.find_pojing_recipe(String(ids[0]), String(ids[1]))


## 两格是否组成「元魂 + 同源破损装备」（顺序不限）
func _summon_pair() -> Dictionary:
	var filled := _synth_filled()
	if filled.size() != 2:
		return {}
	var soul: Dictionary = {}
	var equip: Dictionary = {}
	for d in filled:
		var kind := String((d as Dictionary).get("kind", ""))
		if kind == SYNTH_KIND_SOUL and soul.is_empty():
			soul = d
		elif kind == SYNTH_KIND_EQUIP and equip.is_empty():
			equip = d
	if soul.is_empty() or equip.is_empty():
		return {}
	var recipe := ItemDB.get_synth_recipe_by_soul(String(soul.get("id", "")))
	if recipe.is_empty():
		return {}
	var boss_ids := ItemDB.get_boss_equipment_ids(String(recipe.get("boss_id", "")))
	if not (String(equip.get("id", "")) in boss_ids):
		return {}
	return {"soul": soul, "equip": equip, "recipe": recipe}


func _on_synth_socket_pressed(index: int) -> void:
	if _melting:
		return
	_synth_selected_slot = index
	_show_candidates(index)
	_refresh_synth()


func _refresh_synth() -> void:
	if _melt_sockets.is_empty():
		return
	for i in 3:
		var socket := _melt_sockets[i]
		var holder := socket.get_meta("icon_holder") as CenterContainer
		var label := socket.get_meta("name_label") as Label
		var hint := socket.get_meta("hint_label") as Label
		if holder == null or label == null:
			continue
		UIKit.clear_children(holder)
		var d: Dictionary = _synth_slot_data[i]
		if d.is_empty():
			label.text = "空"
			hint.text = "点击 · 选材料"
		else:
			label.text = String(d.get("name", "?"))
			hint.text = "点击更换"
			var icon := UIKit.icon_node(String(d.get("icon", "")), String(d.get("name", "?")),
				"equipment" if String(d.get("kind", "")) == SYNTH_KIND_EQUIP else "material",
				Vector2(38, 38))
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(icon)
		socket.disabled = _melting
	var plane := _matched_plane_recipe()
	var reason := _synth_block_reason()
	# 按钮跟着识别结果走：残晶合璧出来的是一枚材料，不叫「法宝」
	_melt_button.text = "合成法宝" if not plane.is_empty() 		else ("合璧破境晶" if not _matched_pojing_recipe().is_empty() else "熔铸")
	_melt_button.disabled = reason != "" or _melting
	if _melting:
		_melt_result.text = "炉膛正旺……"
		_melt_result.add_theme_color_override("font_color", Color(0.86, 0.58, 0.26))
	elif reason != "":
		_melt_result.text = reason
		_melt_result.add_theme_color_override("font_color", Color(0.96, 0.55, 0.42))
	else:
		_melt_result.text = "三件材料齐备 · 可以合成" if not plane.is_empty() \
			else "配对完成 · 可以熔铸"
		_melt_result.add_theme_color_override("font_color", Color(0.70, 0.92, 0.52))


func _show_candidates(index: int) -> void:
	_close_candidates()
	var candidates := _synth_candidates()
	_candidate_layer = Control.new()
	_candidate_layer.size = VIEW
	_candidate_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_layer.add_child(_candidate_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.42)
	dim.size = VIEW
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_close_candidates()
	)
	_candidate_layer.add_child(dim)
	var box := PanelContainer.new()
	box.position = Vector2(720, 128)
	box.size = Vector2(500, 452)
	box.add_theme_stylebox_override("panel", _paper_scroll_style())
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	_candidate_layer.add_child(box)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	box.add_child(margin)
	var v := UIKit.vbox(6)
	margin.add_child(v)
	var head := UIKit.hbox(8)
	v.add_child(head)
	_candidate_title = UIKit.label("选择投入材料", 18, Color(0.20, 0.15, 0.10))
	head.add_child(_candidate_title)
	head.add_child(UIKit.spacer())
	if index >= 0 and index < _synth_slot_data.size() \
			and not (_synth_slot_data[index] as Dictionary).is_empty():
		var clear_btn := ForgeButton.new()
		clear_btn.text = "取出"
		clear_btn.setup(ForgeButton.TONE_PAPER)
		clear_btn.custom_minimum_size = Vector2(64, 30)
		UIKit.set_readable_font(clear_btn, 11)
		clear_btn.pressed.connect(func() -> void:
			_synth_slot_data[index] = {}
			_synth_selected_slot = -1
			_close_candidates()
			_refresh_synth()
			GameState.play_ui("ui_click"))
		head.add_child(clear_btn)
	var close_btn := ForgeButton.new()
	close_btn.text = "收起"
	close_btn.setup(ForgeButton.TONE_PAPER)
	close_btn.custom_minimum_size = Vector2(72, 30)
	UIKit.set_readable_font(close_btn, 11)
	close_btn.pressed.connect(_close_candidates)
	head.add_child(close_btn)
	var note := UIKit.readable_label(
		"任意顺序放入：三件同位面专属材料，或 元魂 + 同源破损装备，或 一档破境的地髓 + 天髓。",
		9, Color(0.43, 0.36, 0.26))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_candidate_box = UIKit.vbox(6)
	_candidate_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_candidate_box)
	if candidates.is_empty():
		_candidate_box.add_child(UIKit.readable_label(
			"背包里没有可投入的材料。\n位面材料来自位面 BOSS；元魂来自万界塔投影 BOSS；破损装备来自强化失败累计 10 次；\n破境地髓出自各境界大陆区域核心首领首杀，破境天髓出自对应位面第三位 BOSS 首杀。",
			10, Color(0.45, 0.38, 0.28)))
	else:
		for raw in candidates:
			var entry: Dictionary = raw
			_candidate_box.add_child(_make_candidate_row(index, entry))
	# 没料的时候别摊开一张 452 高的空白纸卷，按条数收一下高度。
	# 必须 deferred：本帧里 ScrollContainer 还没量过内容，最小高度虚高到 500+，
	# 容器只会把纸卷撑大不会缩回来，等一帧再设才收得住。
	var body := 150.0 if candidates.is_empty() else 150.0 + candidates.size() * 60.0
	var h := clampf(body, 190.0, 452.0)
	box.position = Vector2(720, maxf(112.0, (VIEW.y - h) * 0.5))
	box.set_deferred("size", Vector2(500, clampf(body, 190.0, 452.0)))


func _make_candidate_row(slot_index: int, entry: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(430, 54)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.80, 0.74, 0.60, 0.42)
	sb.border_color = ItemDB.material_border_color(String(entry.get("id", ""))) \
		if String(entry.get("kind", "")) in [SYNTH_KIND_SOUL, SYNTH_KIND_PLANE] \
		else Color(0.45, 0.37, 0.26, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	card.add_theme_stylebox_override("panel", sb)
	var row := UIKit.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	row.add_child(UIKit.icon_node(String(entry.get("icon", "")),
		String(entry.get("name", "?")),
		"material" if String(entry.get("kind", "")) in [SYNTH_KIND_SOUL, SYNTH_KIND_PLANE] \
		else "equipment", Vector2(36, 36)))
	var info := UIKit.vbox(1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	var name_lbl := UIKit.label(String(entry.get("name", "?")), 13, Color(0.20, 0.15, 0.10))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name_lbl)
	var desc := UIKit.readable_label(String(entry.get("desc", "")), 9,
		Color(0.43, 0.36, 0.26))
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(desc)
	var count := int(entry.get("count", 1))
	if count > 1:
		var c := UIKit.label("×%d" % count, 11, Color(0.42, 0.33, 0.20))
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(c)
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_filter = Control.MOUSE_FILTER_STOP
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	hit.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	hit.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	hit.pressed.connect(_on_synth_pick.bind(slot_index, entry))
	UIKit.attach_click_sfx(hit)
	card.add_child(hit)
	return card


func _close_candidates() -> void:
	if _candidate_layer != null and is_instance_valid(_candidate_layer):
		_candidate_layer.queue_free()
	_candidate_layer = null


func _on_synth_pick(slot_index: int, entry: Dictionary) -> void:
	if slot_index < 0 or slot_index >= _synth_slot_data.size():
		return
	for i in _synth_slot_data.size():
		if i != slot_index and String((_synth_slot_data[i] as Dictionary).get("id", "")) == String(entry.get("id", "")):
			_synth_slot_data[i] = {}
	_synth_slot_data[slot_index] = entry
	_synth_selected_slot = -1
	_close_candidates()
	_refresh_synth()
	GameState.play_ui("ui_equip")


## 三个投入口共用候选：位面材料 → 元魂 → 可用破损装备；不看槽位。
func _synth_candidates() -> Array:
	var pojings: Array = []
	var planes: Array = []
	var souls: Array = []
	var equips: Array = []
	var plane_ids: Dictionary = {}
	for raw in ItemDB.PLANE_TREASURE_RECIPES:
		for mid in ((raw as Dictionary).get("material_ids", []) as Array):
			plane_ids[String(mid)] = true
	var fragment_ids: Array = ItemDB.pojing_fragment_ids()
	var used: Dictionary = {}
	for d in _synth_slot_data:
		if not (d as Dictionary).is_empty():
			used[String((d as Dictionary).get("id", ""))] = true
	for i in range(CharacterData.inventory.size()):
		var it: Dictionary = CharacterData.inventory[i]
		var mid := String(it.get("id", ""))
		if used.has(mid):
			continue
		if fragment_ids.has(mid):
			pojings.append({
				"kind": SYNTH_KIND_POJING, "id": mid, "name": String(it.get("name", mid)),
				"count": int(it.get("count", 1)), "desc": String(it.get("desc", "")),
				"icon": String(it.get("icon", ItemDB.get_material(mid).get("icon", ""))),
			})
			continue
		if plane_ids.has(mid):
			planes.append({
				"kind": SYNTH_KIND_PLANE, "id": mid, "name": String(it.get("name", mid)),
				"count": int(it.get("count", 1)), "desc": String(it.get("desc", "")),
				"icon": String(it.get("icon", ItemDB.get_material(mid).get("icon", ""))),
			})
			continue
		if ItemDB.is_soul_item(mid):
			souls.append({
				"kind": SYNTH_KIND_SOUL, "id": mid, "name": String(it.get("name", mid)),
				"count": int(it.get("count", 1)), "desc": String(it.get("desc", "")),
				"icon": String(ItemDB.get_material(mid).get("icon", "")),
			})
			continue
		if String(it.get("type", "")) != CharacterData.ITEM_EQUIPMENT:
			continue
		if not bool(it.get("is_broken", false)):
			continue
		if String(it.get("equipment_type", "")) == "treasure":
			continue
		var tpl_id := String(it.get("equipment_id", it.get("id", "")))
		if ItemDB.get_synth_recipe_for_equipment(tpl_id).is_empty():
			continue
		equips.append({
			"kind": SYNTH_KIND_EQUIP, "id": tpl_id, "name": String(it.get("name", tpl_id)),
			"inv_index": i, "count": 1,
			"desc": "已破损：强化永久停止。合成会把这件装备熔掉。",
			"icon": String(it.get("icon", "")),
		})
	return pojings + planes + souls + equips


func _synth_block_reason() -> String:
	var filled := _synth_filled()
	if filled.is_empty():
		return "任意顺序放入：三件同位面专属材料，或 元魂 + 同源破损装备，或 一档破境的地髓 + 天髓。"
	if not _matched_plane_recipe().is_empty():
		return ""
	if not _matched_pojing_recipe().is_empty():
		return ""
	if not _summon_pair().is_empty():
		return ""
	var has_plane := false
	var has_other := false
	var has_soul := false
	var has_equip := false
	var has_pojing := false
	var ids: Array = []
	for d in filled:
		var kind := String((d as Dictionary).get("kind", ""))
		ids.append(String((d as Dictionary).get("id", "")))
		if kind == SYNTH_KIND_PLANE:
			has_plane = true
		else:
			has_other = true
		if kind == SYNTH_KIND_SOUL:
			has_soul = true
		elif kind == SYNTH_KIND_EQUIP:
			has_equip = true
		elif kind == SYNTH_KIND_POJING:
			has_pojing = true
	if has_pojing and (has_plane or has_soul or has_equip):
		return "破境残晶不与其他料同炉。"
	if has_plane and has_other:
		return "位面材料与元魂/破损装备不能混投。"
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if ids[i] == ids[j]:
				return "同一种材料不能重复投入。"
	if has_pojing:
		if filled.size() == 1:
			return "再放同一档的另一枚残晶（地髓配天髓）。"
		return "这两枚不是同一档的地髓与天髓。"
	if filled.size() == 3:
		if has_plane:
			return "这三件材料不构成同一位面法宝的配方。"
		return "召唤法宝只要 1 枚元魂 + 1 件破损装备；请取出一件。"
	if filled.size() == 2:
		if has_plane:
			return "还差第三件同位面专属材料。"
		if has_soul and has_equip:
			return "元魂与装备必须来自同一个 BOSS。"
		if has_soul:
			return "召唤法宝还需要一件同源 BOSS 的破损装备。"
		if has_equip:
			return "召唤法宝还需要一枚同源 BOSS 的元魂。"
		return "这两件不能合成。"
	if has_plane:
		return "再放另外两件同位面专属材料。"
	if has_soul:
		return "再放一件同源破损装备（召唤法宝）。"
	if has_equip:
		return "再放一枚同源元魂（召唤法宝）。"
	return "继续放入材料。"


func _try_synthesize() -> void:
	if _melting:
		return
	var reason := _synth_block_reason()
	if reason != "":
		GameState.play_ui("ui_deny")
		show_toast(reason, UIKit.C_DANGER)
		_refresh_synth()
		return
	var plane_recipe := _matched_plane_recipe()
	if not plane_recipe.is_empty():
		var tpl_plane := ItemDB.get_treasure_template(String(plane_recipe.get("result_id", "")))
		if tpl_plane.is_empty():
			show_toast("位面法宝产物缺失（数据表未登记）。", UIKit.C_DANGER)
			return
		var need: Dictionary = {}
		for mid in plane_recipe.get("material_ids", []):
			need[String(mid)] = 1
		if not CharacterData.consume_materials(need):
			show_toast("三件专属材料不足，合成已取消。", UIKit.C_DANGER)
			_refresh_synth()
			return
		var plane_treasure: Dictionary = CharacterData.make_treasure_instance(tpl_plane)
		await _run_synthesis(tpl_plane, plane_treasure)
		return
	# 破境残晶：地髓 + 天髓 → 完整破境晶（产物是材料，不是法宝，所以不走 _run_synthesis）
	var pojing := _matched_pojing_recipe()
	if not pojing.is_empty():
		var di := String(pojing.get("di", ""))
		var tian := String(pojing.get("tian", ""))
		if not CharacterData.consume_materials({di: 1, tian: 1}):
			show_toast("两枚残晶不足，熔铸已取消。", UIKit.C_DANGER)
			_refresh_synth()
			return
		await _run_pojing_synthesis(pojing)
		return
	var pair := _summon_pair()
	if pair.is_empty():
		show_toast("当前投入不构成可用的合成配方。", UIKit.C_DANGER)
		return
	var soul: Dictionary = pair.get("soul", {})
	var equip: Dictionary = pair.get("equip", {})
	var recipe: Dictionary = pair.get("recipe", {})
	var tpl := ItemDB.get_treasure_template(String(recipe.get("result_id", "")))
	if tpl.is_empty():
		show_toast("配方产物缺失（数据表未登记）。", UIKit.C_DANGER)
		return
	var inv_index := int(equip.get("inv_index", -1))
	var fused_crystal := 0
	var ok_equip := false
	if inv_index >= 0 and inv_index < CharacterData.inventory.size():
		var it: Dictionary = CharacterData.inventory[inv_index]
		if String(it.get("equipment_id", it.get("id", ""))) == String(equip.get("id", "")) \
				and bool(it.get("is_broken", false)):
			fused_crystal = maxi(0, int(it.get("enhance_crystal_spent", 0)))
			CharacterData.remove_item_at(inv_index, 1)
			ok_equip = true
	if not ok_equip:
		show_toast("背包里的那件破损装备已经变了，请重新放一次。", UIKit.C_DANGER)
		_refresh_synth()
		return
	if not CharacterData.consume_materials({String(soul.get("id", "")): 1}):
		show_toast("元魂不足，熔铸已取消。", UIKit.C_DANGER)
		_refresh_synth()
		return
	var treasure: Dictionary = CharacterData.make_treasure_instance(tpl)
	treasure["synth_crystal_spent"] = fused_crystal
	await _run_synthesis(tpl, treasure)


## 残晶合璧：两枚化一枚完整破境晶。产物是材料不是法宝，所以不走 _run_synthesis
## （那条路会 make_treasure_instance + 弹法宝出炉卡）。
func _run_pojing_synthesis(recipe: Dictionary) -> void:
	_melting = true
	_melt_button.disabled = true
	_melt_result.text = "炉膛正旺，两枚残晶正在合璧……"
	_melt_result.add_theme_color_override("font_color", Color(0.86, 0.58, 0.26))
	GameState.play_ui("forge_melt")
	if _fx != null:
		_fx.spawn_melt(FURNACE_FIRE)
		_fx.fire_level = 2.0
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(1.15, true).timeout
	if not is_inside_tree():
		return
	var result_id := String(recipe.get("result", ""))
	# 必得发放：材料能堆叠，背包满也不会吞（和区域首领首杀同一口径）
	CharacterData.grant_material_guaranteed(result_id, 1)
	_synth_slot_data = [{}, {}, {}]
	_synth_selected_slot = -1
	_melting = false
	_refresh_synth()
	_refresh_rail()
	_refresh_forge()
	_melt_result.text = "已合璧：%s" % String(ItemDB.get_material(result_id).get("name", result_id))
	_melt_result.add_theme_color_override("font_color", Color(0.70, 0.92, 0.52))
	GameState.play_ui("forge_great")
	if _fx != null:
		_fx.spawn_treasure(Vector2(440, 400))


## 合成动画 + 入包 + 出炉展示（召唤法宝 / 位面法宝共用）
func _run_synthesis(tpl: Dictionary, treasure: Dictionary) -> void:
	# ⚠ 材料在调用本函数之前就已扣除：产物必须先入包、再播炉火动画。
	#   旧写法把入包放在 1.15s await 之后，玩家若在动画期间关闭面板 / 切场景，
	#   is_inside_tree() 早退会直接吞掉整张配方（2026-11-07 全链路探针复现）。
	#   位面法宝与「元魂 + 破损装备」两条合成路径共用本函数，一律受保护。
	CharacterData.return_item_or_force(treasure)
	Tutorial.note("forge_synth")
	_melting = true
	_melt_button.disabled = true
	_melt_result.text = "炉膛正旺……"
	_melt_result.add_theme_color_override("font_color", Color(0.86, 0.58, 0.26))
	GameState.play_ui("forge_melt")
	if _fx != null:
		_fx.spawn_melt(FURNACE_FIRE)
		_fx.fire_level = 2.0
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(1.15, true).timeout
	if not is_inside_tree():
		return
	# 产物已在函数开头无条件入包（法宝分背包挤爆就临时超一格），此处只做界面收尾
	_synth_slot_data = [{}, {}, {}]
	_synth_selected_slot = -1
	_melting = false
	_refresh_synth()
	_refresh_rail()
	_refresh_forge()
	_melt_result.text = "法宝已出炉"
	_melt_result.add_theme_color_override("font_color", Color(0.70, 0.92, 0.52))
	GameState.play_ui("forge_great")
	if _fx != null:
		_fx.spawn_treasure(Vector2(440, 400))
	_show_treasure_reveal(tpl, treasure)


func _show_treasure_reveal(tpl: Dictionary, treasure: Dictionary) -> void:
	_close_treasure()
	_treasure_layer = Control.new()
	_treasure_layer.size = VIEW
	_treasure_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_layer.add_child(_treasure_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.35)
	dim.size = VIEW
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_treasure_layer.add_child(dim)
	var box := PanelContainer.new()
	box.position = Vector2(430, 168)
	box.size = Vector2(420, 400)
	box.add_theme_stylebox_override("panel", _paper_scroll_style())
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	_treasure_layer.add_child(box)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	box.add_child(margin)
	var v := UIKit.vbox(6)
	margin.add_child(v)
	var kicker := UIKit.label("炉火吐宝", 10, Color(0.53, 0.38, 0.18))
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(kicker)
	var icon_box := CenterContainer.new()
	icon_box.custom_minimum_size = Vector2(0, 130)
	v.add_child(icon_box)
	icon_box.add_child(UIKit.icon_node(String(treasure.get("icon", "")),
		String(treasure.get("name", "法宝")), "treasure", Vector2(120, 120)))
	var name := UIKit.label(String(treasure.get("name", "法宝")), 24,
		UIKit.grade_color(String(treasure.get("equipment_grade", ""))))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name)
	var meta := UIKit.readable_label("法宝 · 已收入行囊", 10, Color(0.43, 0.36, 0.25))
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(meta)
	for line in ItemDB.treasure_effect_lines(treasure):
		var l := UIKit.readable_label(String(line), 10, Color(0.27, 0.22, 0.15))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	v.add_child(UIKit.spacer())
	var take := ForgeButton.new()
	take.text = "收下"
	take.setup(ForgeButton.TONE_SEAL)
	take.custom_minimum_size = Vector2(150, 44)
	take.add_theme_font_size_override("font_size", 16)
	take.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	take.pressed.connect(_close_treasure)
	v.add_child(take)


func _close_treasure() -> void:
	if _treasure_layer != null and is_instance_valid(_treasure_layer):
		_treasure_layer.queue_free()
	_treasure_layer = null
	_refresh_content()


# ===================== 首次教程 =====================

func _maybe_show_tutorial() -> void:
	if _tutorial_seen or _tutorial_layer != null or not is_inside_tree():
		return
	_tutorial_layer = Control.new()
	_tutorial_layer.size = VIEW
	_tutorial_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_layer.add_child(_tutorial_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.62)
	dim.size = VIEW
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_tutorial_layer.add_child(dim)
	var box := PanelContainer.new()
	box.position = Vector2(330, 106)
	box.size = Vector2(620, 404)
	box.add_theme_stylebox_override("panel", _paper_scroll_style())
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	_tutorial_layer.add_child(box)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	box.add_child(margin)
	var v := UIKit.vbox(8)
	margin.add_child(v)
	var title := UIKit.label("锻造须知", 26, Color(0.20, 0.15, 0.09))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := UIKit.readable_label("放装备 → 拿锤 → 敲砧；火候正旺时，法宝也能在炉膛里熔成。",
		10, Color(0.44, 0.36, 0.24))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var steps := [
		["点一下右侧兵器架的纸签，或直接拖到铁砧上。", "装备上砧"],
		["点石台上的锤子拿起，再点砧面连续敲击。", "拿起锤"],
		["铜牌看品阶、强化与磨损；点铜牌展开器谱。", "看铭牌"],
	]
	for i in steps.size():
		var row := UIKit.hbox(10)
		v.add_child(row)
		var seal := PanelContainer.new()
		seal.custom_minimum_size = Vector2(30, 30)
		seal.size = Vector2(30, 30)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.60, 0.18, 0.12, 0.94)
		sb.border_color = Color(0.90, 0.70, 0.40, 0.8)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		seal.add_theme_stylebox_override("panel", sb)
		var num := UIKit.label(str(i + 1), 13, Color(0.98, 0.91, 0.74))
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		seal.add_child(num)
		row.add_child(seal)
		var col := UIKit.vbox(0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		col.add_child(UIKit.label(String(steps[i][1]), 14, Color(0.25, 0.18, 0.11)))
		var line := UIKit.readable_label(String(steps[i][0]), 10, Color(0.44, 0.36, 0.24))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(line)
	var melt_note := UIKit.readable_label(
		"熔铸：点炉膛或顶部「熔铸」，把元魂与同源破损装备放进三口投入口。第三口留空。",
		9, Color(0.48, 0.38, 0.23))
	melt_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(melt_note)
	_tutorial_check = CheckBox.new()
	_tutorial_check.text = "不再提示"
	UIKit.set_readable_font(_tutorial_check, 10)
	_tutorial_check.add_theme_color_override("font_color", Color(0.40, 0.33, 0.22))
	v.add_child(_tutorial_check)
	v.add_child(UIKit.spacer())
	var start := ForgeButton.new()
	start.text = "开始锻造"
	start.setup(ForgeButton.TONE_SEAL)
	start.custom_minimum_size = Vector2(190, 46)
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start.add_theme_font_size_override("font_size", 16)
	start.pressed.connect(_close_tutorial.bind(true))
	v.add_child(start)


func _close_tutorial(save_if_checked: bool) -> void:
	if _tutorial_layer == null:
		return
	if save_if_checked and _tutorial_check != null and _tutorial_check.button_pressed:
		_tutorial_seen = true
		_save_tutorial_seen()
	if is_instance_valid(_tutorial_layer):
		_tutorial_layer.queue_free()
	_tutorial_layer = null
