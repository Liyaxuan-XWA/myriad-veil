extends Node
## 水墨全套截图：13 张卡面实机着色 + 收藏册 / 四张展开 / 单卡落墨。
## 用法：godot --path . --windowed --resolution 1440x1200 tools/shot_ink_set.tscn -- --no-save

const CARD := Vector2(224.0, 336.0)
const COLS := 5
const GAP := Vector2(34.0, 26.0)
const ORIGIN := Vector2(48.0, 44.0)

var _fails := 0
var _passes := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails += 1
		print("FAIL  ", label, "  ", detail)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _unlock_all() -> void:
	CharacterData.tower_progress.clear()
	CharacterData.tower_no_hit_double.clear()
	CharacterData.secret_world["core_kills"] = {}
	CharacterData.core_replay.clear()
	for raw in CodexDB.card_entries():
		var e: Dictionary = raw
		var floor_no := int(e.get("floor", 0))
		var region := String(e.get("world_region", ""))
		if floor_no > 0:
			CharacterData.tower_progress[floor_no] = {
				"unlocked": true, "first_kill": true,
				"clear_count": CodexDB.HOLO_CLEAR_REQUIRED,
			}
			CharacterData.tower_no_hit_double[floor_no] = true
		else:
			CharacterData.secret_world["core_kills"][region] = true
			CharacterData.core_replay[region] = {
				"clear_count": CodexDB.HOLO_CLEAR_REQUIRED,
				"no_hit_double": true,
			}


func _ink_style(boss_id: String) -> Dictionary:
	for raw in (CodexDB.card_entry(boss_id).get("card_variants", []) as Array):
		var v: Dictionary = raw
		if String(v.get("id", "")) == "ink":
			return v
	return {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 水墨全套截图 ##########")
	get_tree().create_timer(60.0, true, false, true).timeout.connect(func() -> void:
		print("SHOT TIMEOUT")
		get_tree().quit(2))
	_unlock_all()

	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.05, 0.045)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var ids: Array = []
	var row := 0
	for raw in CodexDB.card_entries():
		var e: Dictionary = raw
		var bid := String(e.get("id", ""))
		var ink := _ink_style(bid)
		if ink.is_empty():
			_check(false, "%s 有水墨卡" % bid)
			continue
		var face := CardFace.new()
		if not face.configure(ink, CARD, Color(0.86, 0.72, 0.42)):
			_check(false, "%s 卡面可建" % bid)
			continue
		var i := ids.size()
		face.position = ORIGIN + Vector2(
			(i % COLS) * (CARD.x + GAP.x), (i / COLS) * (CARD.y + GAP.y + 22.0))
		add_child(face)
		face.set_paper_reveal_immediate(1.0)
		face.set_paper_interactive(false)
		var num := UIKit.label("%02d" % (i + 1), 13, Color(0.86, 0.78, 0.62))
		num.position = face.position + Vector2(6.0, CARD.y + 4.0)
		add_child(num)
		ids.append(bid)
		_check(face.is_paper(), "%s 走纸本" % bid)
	_check(ids.size() == 13, "13 张水墨卡面已铺", str(ids.size()))
	await get_tree().create_timer(0.6, true, false, true).timeout
	await _shot("output/ink_set_faces.png")

	# 收藏册：看四张一格的计数与封面
	var panel := AchievementPanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var view: AchievementView = panel._view
	await get_tree().create_timer(0.5, true, false, true).timeout
	await _shot("output/ink_set_collection.png")

	# 四张展开：看扇面是否挤 / 墨卡放哪
	view.open_boss("boss_01")
	await get_tree().create_timer(1.2, true, false, true).timeout
	await _shot("output/ink_set_spread.png")
	_check(view.find_children("CardSlot*", "Control", true, false).size() == 4,
		"展开页四张卡")

	# 单卡落墨：真开着色器，抓 0.45 / 1.0 两帧
	var owned := CodexDB.ordered_variants(CodexDB.card_entry("boss_01"))
	var ink_index := -1
	for i in owned.size():
		if String((owned[i] as Dictionary).get("id", "")) == "ink":
			ink_index = i
	_check(ink_index >= 0, "刀客水墨在已收藏里", str(ink_index))
	if ink_index >= 0:
		view.open_card(ink_index)
		await get_tree().create_timer(0.45, true, false, true).timeout
		var face := view.find_child("CardSingle", true, false) as CardFace
		_check(face != null and face.is_paper(), "单卡是纸本")
		if face != null:
			face.set_paper_reveal_immediate(0.45)
			face.set_paper_interactive(false)
			await get_tree().create_timer(0.1, true, false, true).timeout
			await _shot("output/ink_set_single_half.png")
			face.set_paper_reveal_immediate(1.0)
			await get_tree().create_timer(0.1, true, false, true).timeout
			await _shot("output/ink_set_single.png")
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
