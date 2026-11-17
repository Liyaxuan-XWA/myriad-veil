extends Node
## 首杀虎妖成长链 · 截图验收（2026-11-10）
## 出两张：
##   ① 战斗内「捡晶石」步 —— 聚光指向地上晶石（验证 drop.item 锚点 + overlay 重试补扫）
##   ② 锻造「强化」步 —— 聚光指向砧面（教学必成提示卡）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_tutorial_huyao.tscn -- --no-save

const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"
const CRYSTAL := "mat_duanzaojingshi"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	CharacterData.tutorial_data = {"done": {}}
	# c1/c2 预先标完：不然进战斗会先弹「战斗基础」章（真实流程确实如此），
	# c5 只能排队，这张截图就拍不到「捡晶石」步了
	for ch_id in ["c1", "c2"]:
		for raw in (TutorialDB.get_chapter(ch_id).get("steps", []) as Array):
			(CharacterData.tutorial_data["done"] as Dictionary)[
				String((raw as Dictionary).get("id", ""))] = true
	CharacterData.boss_progress = {"boss_huyao": {"killed": true, "first_kill": true}}
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	Tutorial.set("_queued_chapter", "")

	# ===== ① 战斗内捡晶石（锚点是本步开始后才生成的掉落物 → 靠 overlay 重试补扫） =====
	GameState.battle_context = {"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_01", "boss_id": "boss_huyao", "first_kill": true}
	BattleResolver.skip_next_intro = true
	var arena = (load(ARENA_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	Tutorial.request_chapter_by_trigger("after_huyao")
	arena.call("_spawn_drops", "boss_huyao")
	var player: Node2D = arena.get("player")
	var t0 := Time.get_ticks_msec()
	while bool(player.get("is_teleporting")) and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	for i in 8:
		await get_tree().process_frame
	print("步=", Tutorial.active_step.get("id", ""))
	var ov: Node = Tutorial.get("_overlay") as Node
	# 聚光目标还没建好 → 等重试补扫扫到（0.5 秒一拍，最多等 3 秒）
	var t1 := Time.get_ticks_msec()
	while not bool(ov.get("_has_target")) and Time.get_ticks_msec() - t1 < 3000:
		await get_tree().process_frame
	print("has_target=", ov.get("_has_target"), " rect=", ov.get("_target_rect"))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/tut_huyao_crystal.png")
	print("SHOT output/tut_huyao_crystal.png")

	# ===== ② 锻造强化步（必成） =====
	for sid in ["c5_crystal", "c5_return", "c5_forge", "c5_place", "c5_hammer"]:
		(CharacterData.tutorial_data["done"] as Dictionary)[sid] = true
	Tutorial.start_chapter("c5")
	_check_step("c5_enhance")
	arena.queue_free()
	await get_tree().process_frame
	GameState.battle_context = {}
	var panel: Node = (load("res://scripts/ui/panels/forge_panel.gd") as GDScript).new()
	get_tree().root.add_child.call_deferred(panel)
	await get_tree().process_frame
	for i in 6:
		await get_tree().process_frame
	panel.call("open")
	# 铁剑上砧 + 拿锤，摆出教学现场的静态画面
	CharacterData.ensure_starting_equipment()
	for _i in 5:
		CharacterData.add_item(
			(ItemDB.make_material_drop(CRYSTAL) as Dictionary).get("item", {}))
	panel.call("_move_worn_to_anvil", "weapon")
	await get_tree().process_frame
	panel.call("_pick_hammer")
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/tut_huyao_forge.png")
	print("SHOT output/tut_huyao_forge.png")

	panel.queue_free()
	CharacterData.force_enhance_success = false
	GameState.forge_hammer_held = false
	GameState.forge_anvil_id = ""
	BattleResolver.clear()
	GameState.battle_context = {}
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	Tutorial.set("_queued_chapter", "")
	get_tree().quit(0)


func _check_step(want: String) -> void:
	var got := String(Tutorial.active_step.get("id", ""))
	if got != want:
		push_warning("教学步不在 %s（实际 %s）" % [want, got])
	print("步=", got)
