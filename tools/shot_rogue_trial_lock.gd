extends Node
## 试炼之路入口前置解锁的视觉对照（窗口模式）
## 出两张：未解锁（按钮禁用 + 条件提示）/ 已解锁（正常踏入按钮）
## 用法：godot --path . --resolution 1600x900 res://tools/shot_rogue_trial_lock.tscn -- --no-save

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	var dp: Dictionary = CharacterData.domain_progress.duplicate(true)
	var runs := CharacterData.rogue_runs
	var best := CharacterData.rogue_best_floor

	# 全新档：没打过虎妖、没玩过试炼
	CharacterData.domain_progress = {}
	CharacterData.rogue_runs = 0
	CharacterData.rogue_best_floor = 0
	var p := TowerPanel.new()
	get_tree().root.add_child.call_deferred(p)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	p.open()
	await get_tree().process_frame
	# 页签仍可点进去，才能看到「踏入试炼」被禁用和那行条件
	p.call("_switch_tab", 1)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/tower_trial_locked.png")
	print("SHOT output/tower_trial_locked.png")

	# 击败虎妖 → 解锁
	CharacterData.domain_progress[RogueDB.TRIAL_UNLOCK_DOMAIN] = {
		"unlocked": true, "cleared_bosses": [RogueDB.TRIAL_UNLOCK_BOSS]}
	p.call("_refresh_trial_lock")
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/tower_trial_unlocked.png")
	print("SHOT output/tower_trial_unlocked.png")

	CharacterData.domain_progress = dp
	CharacterData.rogue_runs = runs
	CharacterData.rogue_best_floor = best
	p.close()
	get_tree().quit(0)
