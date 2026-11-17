extends Node
## 大世界 · 死亡掉落提示（2026-11-13 用户定）
## 用法：godot --headless --path . --quit-after 30000 res://tools/probe_world_death_warn.tscn -- --no-save
##
## 用户原话：「给屏幕正上方右边显示红色括号文字，（死亡掉落局内背包（B）的所有道具材料）」
## 判据：
##   · 文案逐字一致、红色（C_DANGER）、右对齐；
##   · 位置在屏幕正上方右侧（与核心状态同一行 y=42，右边界 16px 内）；
##   · 不和标题 / 设置按钮 / 传送门方向 / 核心状态文字打架（用真实文本宽度算）。

const WORLD_SCENE := "res://scenes/world/secret_world.tscn"
const TEXT := "（死亡掉落局内背包（B）的所有道具材料）"
const VIEW_W := 1280.0

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	print("\n########## 大世界 · 死亡掉落提示 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _run() -> void:
	GameState.battle_context = {}
	var w: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	add_child(w)
	await _frames(8)
	var warn := w.get("_death_warn") as Label
	_check(warn != null, "大世界 HUD 建出了死亡提示")
	if warn == null:
		w.queue_free()
		return
	await _frames(2)
	_check(warn.text == TEXT, "文案逐字一致", warn.text)
	_check(warn.visible, "提示是常驻可见的")
	_check(warn.get_theme_color("font_color") == UIKit.C_DANGER, "颜色是红色 C_DANGER",
		str(warn.get_theme_color("font_color")))
	_check(warn.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT, "右对齐")
	_check(warn.size.x >= warn.get_minimum_size().x, "宽度放得下整句（不裁字）",
		"%s / %s" % [warn.size.x, warn.get_minimum_size().x])

	var r := warn.get_global_rect()
	_check(absf(r.end.x - (VIEW_W - 16.0)) < 1.0, "右边界贴到右边距 1264", str(r))
	_check(absf(r.position.y - 42.0) < 1.0, "与核心状态同一行（y=42，在设置按钮 38 之下）",
		str(r.position.y))

	# 设置按钮（autoload，右上角 6~38）
	var btn := SettingsUI.get("_btn") as Control
	_check(btn != null, "取到右上角设置按钮")
	if btn != null:
		_check(not r.intersects(btn.get_global_rect()), "不压设置按钮",
			"%s vs %s" % [r, btn.get_global_rect()])
	# 标题（y=8~42，居中）
	var title := w.get("_title") as Control
	_check(title != null and not r.intersects(title.get_global_rect()), "不压标题",
		"%s vs %s" % [r, title.get_global_rect()] if title != null else "无标题")
	# 传送门方向（y=70，右对齐）
	var compass := w.get("_compass_portal") as Control
	_check(compass != null and not r.intersects(compass.get_global_rect()), "不压传送门方向",
		"%s vs %s" % [r, compass.get_global_rect()] if compass != null else "无方向")
	# 核心状态那一行是 900 宽的居中 Label：按真实文本宽度算，文字不能末端压到提示
	var core := w.get("_core_status") as Label
	_check(core != null, "取到核心状态行")
	if core != null:
		var cr := core.get_global_rect()
		var tw := core.get_minimum_size().x
		var text_end := cr.position.x + (cr.size.x - tw) * 0.5 + tw
		_check(r.position.x > text_end + 8.0, "核心状态的文字末端离提示还有 ≥8px",
			"text_end=%.0f warn_x=%.0f" % [text_end, r.position.x])
	w.queue_free()
	await _frames(2)
	print("")
