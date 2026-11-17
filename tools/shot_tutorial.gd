extends Node
## 新手指引 · 截图验收（2026-11-10）
## 出三张：主城清单 + 聚光指向万界秘境 / 暂停喂招卡 / 面板兜底聚光
## 用法：godot --path . --resolution 1280x720 res://tools/shot_tutorial.tscn -- --no-save

const REALM_SCENE := "res://scenes/main/primordial_realm.tscn"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	CharacterData.tutorial_data = {"done": {}}

	var realm := (load(REALM_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(realm)
	await get_tree().process_frame
	await get_tree().process_frame
	for i in 20:
		await get_tree().process_frame

	print("引导章=", Tutorial.active_chapter, " 步=", Tutorial.active_step.get("id", ""))
	# 走到第 2 步（聚光指向「万界秘境」），这才是这套引导的主视觉
	Tutorial.start_chapter("c1")
	Tutorial.skip_step()
	for i in 4:
		await get_tree().process_frame
	print("聚光步=", Tutorial.active_step.get("id", ""))
	var ov: Node = Tutorial.get("_overlay") as Node
	print("has_target=", ov.get("_has_target"), " rect=", ov.get("_target_rect"),
		" spot=", (ov.get("_spot") as Control).size, " vp=", get_viewport().get_visible_rect().size)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/tut_realm.png")
	print("SHOT output/tut_realm.png")

	# 暂停喂招卡（战斗教学的样子）
	Tutorial.pause_prompt("它抬手了 —— 按右键弹开")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/tut_pause.png")
	print("SHOT output/tut_pause.png")
	Tutorial.resume()

	# 第 3 章：打开锻造台，验证「面板兜底聚光」
	Tutorial.start_chapter("c3")
	var panel: Node = (load("res://scripts/ui/panels/forge_panel.gd") as GDScript).new()
	get_tree().root.add_child.call_deferred(panel)
	await get_tree().process_frame
	for i in 6:
		await get_tree().process_frame
	panel.call("open")
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/tut_forge.png")
	print("SHOT output/tut_forge.png")

	# 红点 + 吐司（设计案验收第 2 条）
	panel.queue_free()
	Tutorial.start_chapter("c1")
	Tutorial.skip_step()
	for i in 6:
		await get_tree().process_frame
	var badge_btn: Control = ov.call("_find_meta", get_tree().root, "hud.achievement", 0)
	print("红点挂在=", badge_btn)
	ov.call("set_badge", badge_btn, 2)
	ov.call("push_toast", "炼丹有新方子可领 · 回春丹", "alchemy")
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/tut_badge.png")
	print("SHOT output/tut_badge.png")

	# 首杀「虎妖」回原初位面 → 聚光指到万界塔（2026-11-10 用户要求）
	# 走真入口：把第 1 章标完 + c5 的锻造段标完（否则链路停在战斗里的「捡晶石」，
	# 聚光会指向掉落物而不是塔）+ 置虎妖首杀记录，重建主城让它自己判定
	for raw in (TutorialDB.get_chapter("c1").get("steps", []) as Array):
		(CharacterData.tutorial_data["done"] as Dictionary)[
			String((raw as Dictionary).get("id", ""))] = true
	for sid in ["c5_crystal", "c5_return", "c5_forge", "c5_place", "c5_hammer",
			"c5_enhance", "c5_take", "c5_equip"]:
		(CharacterData.tutorial_data["done"] as Dictionary)[sid] = true
	CharacterData.boss_progress = {"boss_huyao": {"killed": true, "first_kill": true}}
	# 前面红点那段手动开过 c1，回城前先收干净（真实流程里 c1 做完自然就空了）
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	Tutorial.set("_queued_chapter", "")
	realm.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	realm = (load(REALM_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(realm)
	await get_tree().process_frame
	for i in 20:
		await get_tree().process_frame
	print("回城引导章=", Tutorial.active_chapter, " 步=", Tutorial.active_step.get("id", ""),
		" has_target=", ov.get("_has_target"), " rect=", ov.get("_target_rect"))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/tut_tower.png")
	print("SHOT output/tut_tower.png")
	CharacterData.boss_progress = {}

	CharacterData.tutorial_data = {}
	get_tree().quit(0)
