class_name DomainPanel
extends SystemPanel
## 万界秘境
##
## 硬约束（§2.7）：
##   - 真实位面 BOSS 才产生万界本源（塔投影不产生）
##   - 境界不再阻挡进入，只作困难提示（用户 2026-10-22 确认）
##   - 解锁全自动：首个位面默认开放，通关上一界域自动开放下一界域
##
## 2026-10-25 界面重做：
##   - 位面挑战 = 「三光门星图」→「守关者卡面」两屏，直接使用位面选择 / BOSS 选择美术
##   - 苍澜大陆 = 区域插画 + 行前告示 + 区域切换
##   - 所有解锁 / 挑战 / 进大世界逻辑保持原样

const StarMapScript = preload("res://scripts/ui/facility/domain_star_map.gd")
const BossBoardScript = preload("res://scripts/ui/facility/domain_boss_board.gd")
const WorldBoardScript = preload("res://scripts/ui/facility/world_region_board.gd")

var _tab := "domains"
## 打开时直接落在哪一页（战败提示「去青岚野取剑」用）：开面板前设好，`_build_content` 读
var start_tab := "domains"
## 苍澜大陆页里预选哪个区（空 = 由 region board 自己挑默认值）
var start_region_id := ""
## domains 页内部的两屏："map" = 位面星图；"boss" = 守关者
var _screen := "map"
var _selected_domain_id := ""
var _tab_domains: Button
var _tab_world: Button
var _line_domains: ColorRect
var _line_world: ColorRect
var _tab_meta: HBoxContainer
var _body: VBoxContainer


func _init() -> void:
	panel_title = "万界秘境"
	panel_hint = "ESC 关闭"


func panel_size() -> Vector2:
	return Vector2(1120.0, 700.0)


func facility_visual() -> Dictionary:
	return UIKit.facility_style("gateway")


## 位面选择背景现在由星图自己铺满整块内容区，不再当整面板底色
func panel_bg_path() -> String:
	return ""


func _build_content() -> void:
	# 落页：战败提示带着「去看青岚野」进来时，直接停在苍澜大陆页
	if start_tab == "world":
		_tab = "world"
	# 两屏内容高度固定，外层滚动条只会破坏星图边缘 —— 直接关掉
	var outer := content.get_parent() as ScrollContainer
	if outer != null:
		outer.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var tabs := UIKit.hbox(10)
	content.add_child(tabs)

	var left := UIKit.hbox(4)
	left.add_child(_make_tab("位面星图", "domains"))
	left.add_child(_make_tab("苍澜大陆", "world"))
	tabs.add_child(left)
	tabs.add_child(UIKit.spacer())

	_tab_meta = UIKit.hbox(8)
	_tab_meta.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_child(_tab_meta)

	_body = UIKit.vbox(0)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_body)


func _make_tab(text: String, key: String) -> Control:
	var wrap := UIKit.vbox(0)
	var b := UIKit.tab_button(text, Vector2(150, 34),
		UIKit.facility_style("gateway").get("accent", UIKit.C_ACCENT))
	b.add_theme_font_size_override("font_size", UIKit.F_BODY)
	UIKit.set_click_sfx(b, "ui_tab")
	b.pressed.connect(_switch_tab.bind(key))
	wrap.add_child(b)
	var line := ColorRect.new()
	line.color = Color(0, 0, 0, 0)
	line.custom_minimum_size = Vector2(0, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(line)
	if key == "domains":
		_tab_domains = b
		_line_domains = line
	else:
		_tab_world = b
		_line_world = line
	return wrap


func _refresh_content() -> void:
	_refresh_tabs()
	UIKit.clear_children(_body)

	if _tab == "world":
		_build_world_tab()
		return
	if _screen == "boss" and _selected_domain_id != "":
		_build_boss_screen()
	else:
		_screen = "map"
		_build_star_map()


func _switch_tab(tab: String) -> void:
	if _tab == tab:
		return
	_tab = tab
	_screen = "map"
	_selected_domain_id = ""
	set_title("万界秘境")
	set_subtitle(String(UIKit.facility_style("gateway").get("subtitle", "")))
	_refresh_content()


func _refresh_tabs() -> void:
	if _tab_domains == null or _tab_world == null:
		return
	var on_domains := _tab == "domains"
	_tab_domains.text = "位面星图"
	_tab_world.text = "苍澜大陆"
	UIKit.set_tab_selected(_tab_domains, on_domains)
	UIKit.set_tab_selected(_tab_world, not on_domains)
	_line_domains.color = Color(0.52, 0.84, 1.0, 0.85) if on_domains else Color(0, 0, 0, 0)
	_line_world.color = Color(0.56, 0.90, 0.62, 0.85) if not on_domains else Color(0, 0, 0, 0)

	UIKit.clear_children(_tab_meta)
	_tab_meta.add_child(UIKit.chip("境界 %s" % CharacterData.current_realm, UIKit.C_ACCENT))
	_tab_meta.add_child(UIKit.chip("万界本源 %d" % int(CharacterData.origin_energy), Color(0.52, 0.84, 1.0)))
	# 图例从星图右上角抬到这一行：星图里 ◆◇ 只在信息栏出现一次，图例就得在视线先经过的地方
	if _tab == "domains" and _screen == "map":
		_tab_meta.add_child(UIKit.chip("◆ 已通关　◇ 未通关", UIKit.C_TEXT_DIM))


func _build_star_map() -> void:
	var map = StarMapScript.new()
	map.custom_minimum_size = Vector2(0, 532)
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.gate_entered.connect(_on_gate_entered)
	map.locked_picked.connect(_on_locked_picked)
	_body.add_child(map)
	map.setup(WorldDB.DOMAINS, _selected_domain_id)


func _build_boss_screen() -> void:
	var d := WorldDB.get_domain(_selected_domain_id)
	if d.is_empty():
		_screen = "map"
		_build_star_map()
		return
	var board = BossBoardScript.new()
	board.custom_minimum_size = Vector2(0, 532)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.back_requested.connect(_show_star_map)
	board.challenge_requested.connect(_on_challenge)
	_body.add_child(board)
	board.setup(d)


func _build_world_tab() -> void:
	var board = WorldBoardScript.new()
	board.custom_minimum_size = Vector2(0, 532)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.enter_world_requested.connect(_on_enter_world)
	_body.add_child(board)
	board.setup(SecretWorldDB.REGIONS, start_region_id)


func _on_gate_entered(domain_id: String) -> void:
	_selected_domain_id = domain_id
	_screen = "boss"
	set_title("万界秘境 · %s" % WorldDB.get_domain_name(domain_id))
	set_subtitle("守关者 · 择敌而战")
	_refresh_content()


func _show_star_map() -> void:
	_screen = "map"
	set_title("万界秘境")
	set_subtitle(String(UIKit.facility_style("gateway").get("subtitle", "")))
	_refresh_content()


func _on_locked_picked(_domain_id: String, _reason: String) -> void:
	GameState.play_ui("ui_deny")


## 守关者界面 ESC = 先回星图，再按一次才关面板
func _input(event: InputEvent) -> void:
	if _visible and _tab == "domains" and _screen == "boss" \
			and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_show_star_map()
		return
	super(event)


## 进入真实战斗：胜利后由 BattleResolver 结算（产出万界本源、推进剧情）
func _on_challenge(domain_id: String, boss_id: String) -> void:
	close()
	BattleResolver.start_domain(domain_id, boss_id)


func _on_enter_world(region_id: String) -> void:
	# 先关面板（恢复暂停并自我销毁），否则切场景后画布层会挡住苍澜大陆 HUD
	close()
	GameState.reset_time_flow()
	BattleResolver.clear()
	# 透传给世界：从区域面板直接进云隐谷时，落点用该区的南口而不是练气传送门
	SecretWorldDB.pending_spawn_region = region_id
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/world/secret_world.tscn")
