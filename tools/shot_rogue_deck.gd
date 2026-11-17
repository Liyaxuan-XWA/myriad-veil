extends Node
## 试炼「玉简录」验收截图（窗口模式）
## 出三张：
##   output/rogue_deck_page.png  玉简页第一屏（10 张卡，考验两列排版与长 desc 换行）
##   output/rogue_deck_full.png  玉简页滚到中段（看卡片等高情况）
##   output/rogue_gear_tabs.png  行囊页加了页签后的样子（确认没被挤坏）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_rogue_deck.tscn -- --no-save

const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"

## 故意混长短 desc：长句（背水 / 嗜杀 / 以意御法）用来看换行会不会撑破卡片
const SAMPLE: Array = [
	["g_str", 3], ["g_hp", 2], ["g_desperate", 2], ["g_last_stand", 1],
	["g_bloodlust", 1], ["s_yj_free", 1], ["s_jq_mana", 1], ["s_wj_cap", 1],
	["s_wj_return", 1], ["s_yj_dmg", 1],
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	RogueRun.start_run("sword")
	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 1}
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	var rogue: Node = arena.get("_rogue")
	var player: Node2D = arena.get("player")
	if rogue == null or player == null:
		get_tree().quit(1)
		return
	rogue.set_process(false)
	for raw in (rogue.get("_alive") as Array):
		if is_instance_valid(raw):
			(raw as Node).free()
	(rogue.get("_alive") as Array).clear()
	player.set("invincible_timer", 999.0)

	# 走真实入口叠卡（add_buff 会 rebuild，HUD 也随之刷新）
	for entry in SAMPLE:
		for i in int(entry[1]):
			RogueRun.add_buff(String(entry[0]))
	rogue.call("_update_hud")
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/rogue_deck_hud.png")
	print("SHOT output/rogue_deck_hud.png")

	await _open_panel_via_tab()
	var panel: Node = CharacterPanel.get("_rogue_gear_panel")
	if panel == null or not is_instance_valid(panel):
		print("ERROR 行囊面板没打开")
		get_tree().quit(1)
		return

	# 第一屏：默认行囊页（确认页签没把原布局挤坏）
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/rogue_gear_tabs.png")
	print("SHOT output/rogue_gear_tabs.png")

	# 切到玉简页（按钮信号入口，不做私有调用）
	var tabs: Array = panel.get("_tab_buttons")
	if tabs.size() < 2:
		print("ERROR 页签没建出来")
		get_tree().quit(1)
		return
	(tabs[1] as Button).pressed.emit()
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/rogue_deck_page.png")
	print("SHOT output/rogue_deck_page.png")

	# 滚到中段：看长卡片之间有没有高度错位
	var deck: Node = panel.get("_deck_view")
	var scroll := _find_scroll(panel)
	if deck != null and scroll != null:
		(scroll as ScrollContainer).scroll_vertical = 260
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("output/rogue_deck_full.png")
		print("SHOT output/rogue_deck_full.png")

	panel.call("close")
	RogueRun.restore()
	arena.free()
	get_tree().quit(0)


## 真实按 TAB → CharacterPanel._input → RogueGearPanel（不吃私有入口）
func _open_panel_via_tab() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_TAB
	ev.keycode = KEY_TAB
	ev.pressed = true
	Input.parse_input_event(ev)
	for i in 6:
		await get_tree().process_frame
	var up := InputEventKey.new()
	up.physical_keycode = KEY_TAB
	up.keycode = KEY_TAB
	up.pressed = false
	Input.parse_input_event(up)
	for i in 4:
		await get_tree().process_frame


func _find_scroll(node: Node) -> Node:
	for c in node.get_children():
		if c is ScrollContainer and (c as ScrollContainer).vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			# 玉简页那个滚动容器的子节点里挂着 RogueDeckView
			if _has_deck(c):
				return c
		var got := _find_scroll(c)
		if got != null:
			return got
	return null


func _has_deck(node: Node) -> bool:
	for c in node.get_children():
		if c is RogueDeckView:
			return true
		if _has_deck(c):
			return true
	return false
