extends Node
## 成就入口探针：原初位面 HUD 的「指引书 / 图鉴 / 成就」三连入口，成就按钮位置不重叠且能开面板。
## 用法：godot --headless --path . tools/probe_achievement_entry.tscn -- --no-save

var _fails := 0
var _passes := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails += 1
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 成就入口探针 ##########")
	var watchdog := get_tree().create_timer(20.0, true, false, true)
	watchdog.timeout.connect(func() -> void:
		print("WATCHDOG timeout")
		get_tree().quit(2))
	var scene := (load("res://scenes/main/primordial_realm.tscn") as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud := scene.get_node_or_null("HUD")
	_check(hud != null, "原初位面 HUD 已建")
	if hud == null:
		get_tree().quit(1)
		return
	var guide := hud.get_node_or_null("GuideBookButton") as Button
	var codex := hud.get_node_or_null("CodexButton") as Button
	var ach := hud.get_node_or_null("AchievementButton") as Button
	_check(guide != null and codex != null and ach != null, "三个入口按钮齐全")
	if ach == null:
		get_tree().quit(1)
		return
	_check(ach.get_global_rect().position.y >= codex.get_global_rect().end.y,
		"成就按钮在图鉴正下方",
		"%.0f / %.0f" % [ach.get_global_rect().position.y, codex.get_global_rect().end.y])
	_check(ach.get_global_rect().position.x == guide.get_global_rect().position.x,
		"三个入口左对齐")
	scene.call("_open_achievement")
	await get_tree().process_frame
	await get_tree().process_frame
	var panel = scene.get("_current_panel")
	_check(panel != null and panel is AchievementPanel, "成就按钮打开成就面板",
		str(panel))
	if panel is AchievementPanel:
		var view: AchievementView = (panel as AchievementPanel)._view
		_check(view != null and view._page == AchievementView.PAGE_PACK, "默认落在成就收藏")
		(panel as AchievementPanel).close()
	await get_tree().process_frame
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
