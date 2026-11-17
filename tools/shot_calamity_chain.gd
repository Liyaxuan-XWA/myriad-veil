extends Node
## 灾劫连锁实景截图（未装备「三灾·灾身」）：
## 三痕读数、风助火势、雷火交击、风雷引。
## 用法：godot --path . --windowed --resolution 1280x720 tools/shot_calamity_chain.tscn -- --no-save

const IDS: Array[String] = [
	"skill_calamity_step", "skill_calamity_slash",
	"skill_calamity_fire_seal", "skill_calamity_fire_field",
	"skill_calamity_thunder_strike", "skill_calamity_thunder_pool",
	"skill_calamity_turn", "skill_calamity_final",
]


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _ready() -> void:
	for sid in IDS:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	CharacterData.active_skill_loadout = IDS.duplicate()
	CharacterData.passive_skill_loadout = []
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_03",
		"boss_id": "boss_03_c",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node2D = arena.player
	var boss: Node2D = arena.boss
	player.set_physics_process(false)
	boss.set_physics_process(false)
	boss.state = 0
	boss.state_timer = 0.0
	boss._current_skill = ""
	if boss.skin != null:
		boss.skin.cancel_one_shot()
	boss.anim.modulate = Color.WHITE
	player.global_position = Vector2(0.0, 210.0)
	boss.global_position = Vector2(0.0, 20.0)
	boss.target = player
	player._refresh_calamity_unlock()
	# 等 BOSS 入场卡收完，否则大字会盖住灾痕与反应
	await _wait(4.0)

	# 1) 三痕读数：目标带劫火
	boss.apply_debuff("jie_huo", 4.0)
	player._attach_calamity_marks_if_needed(boss, "jie_huo")
	await _wait(0.25)
	await _shot("calamity_chain_marks.png")

	# 2) 风助火势：风技引爆劫火，留下一段火龙卷
	player._cast_calamity_slash(SkillDB.get_skill_form("skill_calamity_slash"), Vector2.UP)
	await _wait(0.55)
	await _shot("calamity_chain_wind_fire.png")
	# 等火龙卷完全收掉，别把残留带进下一张
	await _wait(2.6)

	# 3) 雷火交击：火技引爆感电
	boss.apply_debuff("gan_dian", 3.0)
	player._attach_calamity_marks_if_needed(boss, "gan_dian")
	player._cast_calamity_fire_seal(SkillDB.get_skill_form("skill_calamity_fire_seal"),
		Vector2.UP)
	await _wait(0.31)
	await _shot("calamity_chain_fire_thunder.png")
	await _wait(0.7)

	# 4) 风雷引：雷技引爆风蚀，留下风雷涡
	boss.apply_debuff("feng_shi", 4.0)
	player._attach_calamity_marks_if_needed(boss, "feng_shi")
	player._cast_calamity_thunder_strike(
		SkillDB.get_skill_form("skill_calamity_thunder_strike"), Vector2.UP)
	await _wait(0.70)
	await _shot("calamity_chain_thunder_wind.png")
	await _wait(0.5)
	get_tree().quit()
