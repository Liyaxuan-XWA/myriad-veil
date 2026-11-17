extends Node
## 界内指引 · 截图验收（2026-11-12）
## 出四张：
##   ① 原初位面、背包关着 —— 合成指引不露脸（不许浮在城里）
##   ② 打开背包 —— 指引出现，聚光指着材料详情
##   ③ 关掉背包 —— 指引整块暂时消失
##   ④ 再打开背包 —— 出现条件再次满足，指引回来
## 用法：godot --path . --resolution 1280x720 res://tools/shot_guide_scope.tscn -- --no-save

const REALM_SCENE := "res://scenes/main/primordial_realm.tscn"


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/%s.png" % name)
	print("SHOT output/%s.png" % name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	CharacterData.tutorial_data = {"done": {}}
	var realm = (load(REALM_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(realm)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = realm
	await _frames(4)
	# 主城 _ready 会做存档初始化，覆盖进度 → 之后再把合成指引章摆出来
	CharacterData.tutorial_data = {"done": {}}
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	Tutorial.start_chapter("c3b")
	await _frames(6)
	print("step=", Tutorial.active_step.get("id", ""), " bag_open=", CharacterPanel.is_open())

	# ① 城里：不露脸
	await _shot("guide_scope_city")

	# ② 打开背包：露脸
	CharacterPanel.open_panel()
	await _frames(6)
	await _shot("guide_scope_bag")

	# ③ 关掉：暂时消失
	CharacterPanel.close_panel()
	await _frames(6)
	await _shot("guide_scope_closed")

	# ④ 再打开：回来
	CharacterPanel.open_panel()
	await _frames(6)
	await _shot("guide_scope_reopen")
	CharacterPanel.close_panel()
	await _frames(3)
	get_tree().paused = false
	get_tree().quit(0)
