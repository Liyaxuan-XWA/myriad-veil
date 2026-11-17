extends Node
## 棋坛关卡 #55 的两块可见面：棋谱长卷 + 对局 HUD 的「第 N 关」读数
## 用法：godot --path . --windowed --resolution 1280x720 tools/shot_match_scroll.tscn -- --no-save

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	# 全套要跑几分钟；`-- --only-board` 只跑战斗两档那两张，方便反复调缩放。
	if OS.get_cmdline_user_args().has("--only-board"):
		await _grab_board(3, "board_zoom")
		get_tree().quit(0)
		return
	if OS.get_cmdline_user_args().has("--only-scroll"):
		await _grab(0, "scroll_new.png")
		await _grab(3, "scroll_cleared3.png")
		get_tree().quit(0)
		return
	if OS.get_cmdline_user_args().has("--only-quick"):
		await _grab(3, "scroll_quick_on.png", -1, "", true)
		await _grab(3, "scroll_quick_off.png", -1, "", false)
		await _grab_quick()
		get_tree().quit(0)
		return
	# 票 009 ②：窄屏底栏。窗口尺寸由命令行的 --resolution 决定，
	# 所以同一张图能分别在 1280×720 与 800×480 各拍一次做对照。
	if OS.get_cmdline_user_args().has("--only-narrow"):
		await _grab(3, "scroll_narrow.png", -1, "", true)
		get_tree().quit(0)
		return
	# 票 009 ③：结算页第二行必须是中文
	if OS.get_cmdline_user_args().has("--only-settle-cn"):
		await _grab_settle(3, 0, "settle_reason_cn.png")
		get_tree().quit(0)
		return
	await _grab(0, "scroll_new.png")
	await _grab(3, "scroll_cleared3.png")
	await _grab(11, "scroll_deep.png")
	# 新档往右滚到底：第 7 关起应当只剩轮廓（剪影），且没有卡组
	await _grab(0, "scroll_silhouette.png", 11)
	await _grab_arena(9, "arena_hud_level9.png")
	await _grab_settle(3, 0, "settle_first_clear.png")
	await _grab_settle(7, 0, "settle_replay.png", 5)
	await _grab_settle(4, 1, "settle_loss.png")
	await _grab_settings_in_match("settings_in_match.png")
	await _grab_settings_in_city("settings_in_city.png")
	# 敌方卡面固定原版（2026-11-05 用户定）：把玩家偏好改成水墨再拍一张长卷，
	# 卷上 6 枚落子应当**一张都没变** —— 变了就说明还在读玩家卡包。
	await _grab(3, "scroll_player_ink.png", -1, "ink")
	await _grab_board(3, "board_zoom")
	get_tree().quit(0)


## 战斗阶段的两档相机（2026-11-05 用户定）：
##   轮到自己 = 要点激活卡 → 常规档（棋盘贴左、右侧手牌列亮着）
##   轮到对方 = 无事可做 → 看盘档（手牌淡出、棋盘放大居中）
##
## ⚠ 前三个阶段的超时必须保持很短（否则整局卡在选牌，根本到不了战斗），
##   等到真的进了"战斗·轮到自己"再把超时抬到 60 并重置计时 ——
##   不然"到点代玩家选"会在拍摄中途把轮次推走，两张图拍到的是同一档。
func _grab_board(cleared: int, name: String) -> void:
	CharacterData.match_level_cleared = cleared
	CharacterData.match_card_kind = ""
	GameState.match_context = {"level": cleared + 1}
	var arena: Node = (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	arena.set("player_stage_timeout", 0.2)
	add_child(arena)
	if not await _wait_battle(arena, true):
		print("  board 没等到战斗·自己那轮")
	else:
		arena.set("player_stage_timeout", 60.0)
		arena.set("_stage_timer", 60.0)
		await _shoot_cam(arena, "%s_own.png" % name)
		var st = arena.get("_state")
		var legal: Array = st.legal_activate(0)
		if legal.is_empty():
			print("  board 没有可激活的牌，拍不了对方那轮")
		else:
			arena.call("_activate_card", int(legal[0]))
			if not await _wait_battle(arena, false):
				print("  board 没等到战斗·对方那轮")
			else:
				await _shoot_cam(arena, "%s_focus.png" % name)
	arena.queue_free()
	await get_tree().process_frame


func _wait_battle(arena: Node, want_own: bool) -> bool:
	for i in 1200:
		var st = arena.get("_state")
		if st != null and st.phase == MatchState.Phase.BATTLE and st.is_own_round() == want_own:
			return true
		await get_tree().physics_frame
	return false


## 相机是 exp 插值到位的，先让它落定再拍，然后把两个数打出来当证据。
func _shoot_cam(arena: Node, name: String) -> void:
	for i in 30:
		await get_tree().physics_frame
	await _shot(name)
	var cam: Camera2D = arena.get("_cam")
	var hs: Control = arena.get("_hand_scroll")
	var z := float(cam.zoom.x)
	print("  board %s z=%.4f 棋盘=%.0fpx 手牌可见=%s 档位=%d" % [
		name, z, MatchDB.BOARD_COLS * MatchDB.CELL_PX * z, hs.visible, int(arena.get("_cam_mode"))])
	# 面板到底藏没藏住：把第一个卡面按钮的屏幕位置也打出来。
	var hand: Control = arena.get("_hand")
	var first: Control = null
	if hand.get_child_count() > 0:
		first = hand.get_child(0) as Control
	if first != null:
		print("    手牌数=%d 第一张屏幕x=%.0f 宽=%.0f" % [
			hand.get_child_count(), first.get_global_rect().position.x, first.size.x])


## #58 的可见面：棋局里该有「返回原初位面」，主城里不该有
func _grab_settings_in_match(name: String) -> void:
	CharacterData.match_level_cleared = 4
	GameState.match_context = {"level": 5}
	var arena: Node = (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	arena.set("player_stage_timeout", 1.0)
	get_tree().root.add_child.call_deferred(arena)
	for i in 14:
		await get_tree().process_frame
	get_tree().current_scene = arena
	await _settle_frames(8)
	await _open_settings_and_shoot(name)
	arena.queue_free()
	await get_tree().process_frame


func _grab_settings_in_city(name: String) -> void:
	GameState.match_context = {}
	# ⚠ 不要 change_scene_to_file：本工具自己就是 current_scene，切场景等于把自己 free 掉
	#   （#55 已经栽过一次）。这里只要把 current_scene 换成"不是棋局"的节点就够了。
	var stand_in := Node.new()
	stand_in.name = "PrimordialRealm"
	get_tree().root.add_child.call_deferred(stand_in)
	await _settle_frames(4)
	get_tree().current_scene = stand_in
	await _settle_frames(4)
	await _open_settings_and_shoot(name)
	stand_in.queue_free()
	await get_tree().process_frame


## 快速模式三张可见面：进关即见对方摆好 → 布阵中（还差几张）→ 开战后第三档。
func _grab_quick() -> void:
	CharacterData.match_quick_mode = true
	CharacterData.match_level_cleared = 4
	CharacterData.match_card_kind = ""
	GameState.match_context = {"level": 5}
	var arena: Node = (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	arena.set("player_stage_timeout", 60.0)
	add_child(arena)
	await _settle_frames(24)
	var st = arena.get("_state")
	await _shot("quick_entry.png")
	print("  quick_entry 档=%s 对方已摆=%d 阶段=%s" % [
		_cam_name(arena), int(st.deployed_count()), str(st.phase)])

	var ids: Array = []
	for i in MatchDB.DECK_SIZE:
		ids.append(String((st.legal_pool(0) as Array)[i]))
	st.apply_command({"t": "pick", "team": 0, "ids": ids})
	for n in 4:
		var legal: Array = st.legal_deploy(0)
		var cells: Array = MatchState.free_cells(st.occupied_cells())
		st.apply_command({"t": "deploy", "team": 0, "card": int(legal[0]), "cell": cells[0]})
	arena.call("_refresh_stage")
	await _settle_frames(6)
	await _shot("quick_deploy.png")
	var fight: Button = (arena.get("_buttons") as Dictionary).get("fight")
	print("  quick_deploy 钮=「%s」 禁用=%s 已摆=%d" % [
		fight.text, str(fight.disabled), int(st.deployed_count())])

	for n in 2:
		var legal: Array = st.legal_deploy(0)
		var cells: Array = MatchState.free_cells(st.occupied_cells())
		st.apply_command({"t": "deploy", "team": 0, "card": int(legal[0]), "cell": cells[0]})
	fight.pressed.emit()
	await _settle_frames(40)
	await _shot("quick_final.png")
	var cam: Camera2D = arena.get("_cam")
	print("  quick_final 档=%s z=%.4f 棋盘=%.0fpx 阶段=%s" % [
		_cam_name(arena), float(cam.zoom.x), MatchDB.BOARD_COLS * MatchDB.CELL_PX * float(cam.zoom.x),
		str(st.phase)])
	# 量**全局矩形**，不读 offset_top：BOTTOM_WIDE 的锚点在底边，
	# offset_top 是负偏移，直接打印它会把"推到屏幕外"显示成一个正常数字。
	for k in ["_top_band", "_bottom_band"]:
		var c: Control = arena.get(k)
		var gr := c.get_global_rect()
		print("    %s 屏幕y %.0f~%.0f（视口高=%.0f）" % [k, gr.position.y, gr.end.y,
			get_tree().root.get_visible_rect().size.y])
	var fb: Button = (arena.get("_buttons") as Dictionary).get("fight")
	print("    按钮条在屏上=%s（点得到吗）" % str(
		fb.get_global_rect().end.y <= get_tree().root.get_visible_rect().size.y + 1.0))
	# 结算页：等价 ⇒ 数字一样，档位只能靠这一行标出来
	st.winner = 0
	st.end_reason = "clear_field"
	st.phase = MatchState.Phase.OVER
	arena.call("_settle")
	await _settle_frames(10)
	await _shot("quick_settle.png")
	print("    结算文案=%s" % String(arena.get("_result_label").text).split("\n")[0])
	arena.queue_free()
	await get_tree().process_frame
	CharacterData.match_quick_mode = false
	GameState.match_context = {}


func _cam_name(a: Node) -> String:
	match int(a.get("_cam_mode")):
		MatchArena.CAM_WATCH:
			return "看盘"
		MatchArena.CAM_QUICK:
			return "快速"
		_:
			return "常规"


func _settle_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## 面板内容超过一屏，「系统」那节在折线以下。
## 截图前把内容滚到底，否则用户看不到这次新加的按钮，会以为没做。
func _open_settings_and_shoot(name: String) -> void:
	var p: Node = load("res://scripts/ui/settings_panel.gd").new()
	p.set("from_title", false)
	get_tree().root.add_child.call_deferred(p)
	await _settle_frames(4)
	p.open()
	await _settle_frames(12)
	var abandon: Button = null
	for c in _walk(p):
		if c is Button and String((c as Button).text).contains("返回原初位面"):
			abandon = c as Button
	var scroll := _scroll_ancestor(abandon)
	if scroll != null:
		scroll.scroll_vertical = 999999
		await _settle_frames(6)
	await _shot(name)
	print("  %s 场景=%s 有弃局按钮=%s" % [
		name, String(get_tree().current_scene.name), abandon != null
	])
	if abandon != null:
		var top := abandon.get_global_rect().position.y
		var limit := 0.0
		if scroll != null:
			limit = scroll.get_global_rect().end.y
		print(
			"    按钮顶边 y=%.0f｜滚动区底边 y=%.0f｜在视野内=%s"
			% [top, limit, top < limit]
		)
	# ⚠ 必须收掉：面板挂在 root 上，不 free 就会糊在后续每一张截图上
	#   （board_enemy_original.png 第一版拍出来是一整屏设置面板）。
	p.queue_free()
	await _settle_frames(6)


func _scroll_ancestor(c: Control) -> ScrollContainer:
	var p := c.get_parent() if c != null else null
	while p != null:
		if p is ScrollContainer:
			return p as ScrollContainer
		p = p.get_parent()
	return null


func _walk(node: Node, acc: Array[Control] = []) -> Array[Control]:
	for ch in node.get_children():
		if ch is Control:
			acc.append(ch as Control)
		_walk(ch, acc)
	return acc


## 结算面板的三种读数（#56）：胜=0 是我方，负=1 是对方
## ⚠ level 要单独给：重打那一屏必须是 **level ≤ cleared**，
##   固定写 cleared+1 拍出来的"重打"其实还是首通，等于没拍。
func _grab_settle(cleared: int, outcome: int, name: String, level: int = -1) -> void:
	CharacterData.match_level_cleared = cleared
	CharacterData.inventory = []
	GameState.match_context = {"level": cleared + 1 if level < 0 else level}
	var arena: Node = (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	arena.set("player_stage_timeout", 1.0)
	add_child(arena)
	for i in 12:
		await get_tree().physics_frame
	var st = arena.get("_state")
	st.winner = outcome
	st.end_reason = "clear_field"
	st.phase = MatchState.Phase.OVER
	arena.call("_settle")
	for i in 10:
		await get_tree().process_frame
	await _shot(name)
	var lines: PackedStringArray = String(arena.get("_result_label").text).split("\n")
	print("  settle cleared=%d outcome=%d 钱包=%d 文案=%s / %s" % [
		cleared, outcome, int(CharacterData.count_material("mat_duanzaojingshi")),
		lines[0], lines[1] if lines.size() > 1 else "<没有第二行>"])
	arena.queue_free()
	await get_tree().process_frame


## 对局 HUD：走真实入口（长卷 → 按主按钮），别手搓 match_context
func _grab_arena(cleared: int, name: String) -> void:
	CharacterData.match_level_cleared = cleared
	GameState.match_context = {"level": cleared + 1}
	var arena: Node = (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	arena.set("player_stage_timeout", 1.0)
	add_child(arena)
	for i in 24:
		await get_tree().process_frame
	await _shot(name)
	print("  arena level=%d 对手=%s" % [int(arena.get("_level")),
			str((arena.get("_state").pools as Array)[1])])
	arena.queue_free()
	await get_tree().process_frame


## 滚到 to_slot 那一槽再截图（用来肉眼确认剪影与虚拟化）
func _grab(cleared: int, name: String, to_slot: int = -1, kind: String = "", quick: bool = false) -> void:
	CharacterData.match_level_cleared = cleared
	CharacterData.match_card_kind = kind
	CharacterData.match_quick_mode = quick
	GameState.match_context = {}
	var s: Control = MatchLevelScroll.new()
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child.call_deferred(s)
	for i in 14:
		await get_tree().process_frame
	if to_slot >= 0:
		s._scroll_to_slot(to_slot)
		for i in 10:
			await get_tree().process_frame
	await _shot(name)
	# #57 之后是虚拟化：槽位数与"已建节点数"是两回事，两个都要打出来
	print("  cleared=%d current=%d 槽=%d(有卡组%d) 已建=%d 焦点=%d" % [
		cleared, int(s._current), int(s._slot_count()), int(s._deck_slot_count()),
		s._tiles_by_slot.size(), int(s._focused)])
	s.queue_free()
	await get_tree().process_frame
