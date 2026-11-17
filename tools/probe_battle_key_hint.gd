extends Node2D
## 战斗左上角「基础操作」竖排块（2026-11-12 用户定）
## 用法：godot --headless --path . --quit-after 30000 res://tools/probe_battle_key_hint.tscn -- --no-save
##
## 口径：
##   · 位置在左上角、**竖着**排（高 > 宽）、不跟 BOSS 血条 / 技能栏 / 顶栏重叠；
##   · 鼠标穿透（不能挡住点设置）；战斗中常驻；打完 / 死了就藏；
##   · 试炼里 Tab 那行写「行囊」而不是「角色」。

const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	print("\n########## 战斗 · 左上角操作键竖排 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _arena(source: String) -> Node:
	if source == BattleResolver.SOURCE_ROGUE:
		GameState.battle_context = {"source": source, "floor": 1}
		RogueRun.start_run("sword")
	else:
		GameState.battle_context = {
			"source": source, "domain_id": "domain_01", "boss_id": "boss_01",
		}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	for i in 4:
		await get_tree().process_frame
	return arena


func _hint(arena: Node) -> Control:
	return arena.get_node_or_null("HUD/KeyHint") as Control


func _labels(root: Node) -> Array:
	var out: Array = []
	for n in root.find_children("*", "Label", true, false):
		out.append(String((n as Label).text))
	return out


func _run() -> void:
	# ===== 1. 位面战：左上角竖排、不重叠、鼠标穿透 =====
	var a1 = await _arena(BattleResolver.SOURCE_DOMAIN)
	var hint := _hint(a1)
	_check(hint != null, "战斗里出现了「基础操作」块")
	if hint != null:
		_check(hint.position.x < 40.0 and hint.position.y < 40.0, "贴在左上角", str(hint.position))
		_check(hint.size.y > hint.size.x, "竖着排（高 > 宽）", "%.0f×%.0f" % [hint.size.x, hint.size.y])
		_check(hint.mouse_filter == Control.MOUSE_FILTER_IGNORE, "鼠标穿透，不挡其它按钮")
		var texts := _labels(hint)
		_check(texts.has("移动") and texts.has("WASD") and texts.has("返回") and texts.has("ESC"),
				"基础操作都在（移动 / 攻击 / … / 返回）", str(texts))
		_check(texts.has("角色"), "试炼外 Tab 那行写「角色」")
		# 不和顶部血条 / 战斗标题 / 时间 / 技能栏重叠
		var r := hint.get_global_rect()
		var others := ["HUD/BossHealthBar", "HUD/BattleTitleLabel", "HUD/TimeLabel"]
		for path in others:
			var n := a1.get_node_or_null(path) as Control
			if n == null:
				continue
			_check(not r.intersects(n.get_global_rect()), "不和 %s 重叠" % path.get_file(), str(n.get_global_rect()))
		var slots: Array = a1.get("_skill_slots")
		if not slots.is_empty():
			var box: Control = (slots[0] as Dictionary).get("box")
			_check(not r.intersects(box.get_global_rect()), "不和技能栏重叠")
		_check(hint.visible, "战斗中常驻显示")
		# 打完就藏
		a1.set("_cleared", true)
		a1.call("_update_key_hint")
		_check(not hint.visible, "通关后自动隐藏")
		a1.set("_cleared", false)
		a1.call("_update_key_hint")
		var p: Node = a1.get("player")
		p.set("is_dead", true)
		a1.call("_update_key_hint")
		_check(not hint.visible, "死亡后也隐藏")
		p.set("is_dead", false)
		a1.call("_update_key_hint")
		_check(hint.visible, "活着又显示（状态是实时判的）")
	a1.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# ===== 2. 试炼：整块不建（塔层 HUD 占着左上角，两叠会互相压字） =====
	var a2 = await _arena(BattleResolver.SOURCE_ROGUE)
	var hint2 := _hint(a2)
	_check(hint2 == null, "试炼之路**不显示**左上角操作表",
			"" if hint2 == null else str(hint2.get_global_rect().size))
	a2.queue_free()
	await get_tree().process_frame
	RogueRun.finish_run(true)
	await get_tree().process_frame
	print("")
