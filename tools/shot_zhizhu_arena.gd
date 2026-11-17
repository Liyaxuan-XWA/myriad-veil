extends Node
## 执烛 · 照影界灯台石坪真实箱庭截图（2026-11-02）
## 看的是「玩家可见面」：战场地面 / 界灯 / 影身走廊与影尖亮点 / 八式特效是否互不相同 /
## 二阶段夺灯后玩家脚下的反照影带 / 玩家侧灯笼拖尾读数。
## 用法：godot --path . --resolution 1280x720 res://tools/shot_zhizhu_arena.tscn -- --no-save

## 第三列 = 起手到截图的间隔：必须落在特效 lifetime 之内（影族 lifetime 0.4~0.9s）
const FORMS := [
	["form_shadow_cut", "cut", 0.16],
	["form_shadow_reach", "reach", 0.18],
	["form_shadow_bind", "bind", 0.30],
	["form_shadow_step", "step", 0.16],
	["form_shadow_dim", "dim", 0.30],
	["form_shadow_beam", "beam", 0.16],
	["form_shadow_split", "split", 0.34],
]


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


## 诊断用：把场上「细长条」形状的 CanvasItem 打出来。
## 截图里出现来历不明的亮色细条时，靠这个定位是哪个节点画的，别靠猜。
func _dump_bars(host: Node) -> void:
	for n in host.find_children("*", "CanvasItem", true, false):
		var ci := n as CanvasItem
		if ci == null or not ci.is_visible_in_tree():
			continue
		var spr := n as Sprite2D
		if spr == null or spr.texture == null:
			continue
		var w := float(spr.texture.get_width()) * absf(spr.global_transform.x.x)
		var h := float(spr.texture.get_height()) * absf(spr.global_transform.y.y)
		var long_side := maxf(w, h)
		var short_side := minf(w, h)
		if long_side > 90.0 and short_side < 40.0 and long_side / maxf(short_side, 1.0) > 4.0:
			print("  BAR  %-46s  %.0fx%.0f  a=%.2f  pos=%s  parent=%s" % [
				String(n.get_path()), w, h, spr.modulate.a, str(spr.global_position),
				String(n.get_parent().name)])


func _ready() -> void:
	CharacterData.current_realm = "元婴"
	CharacterData.realm_stage = 1
	for sid in ["skill_shadow_reach", "skill_shadow_cut", "skill_shadow_beam",
			"skill_shadow_bind", "skill_shadow_dim", "skill_shadow_split",
			"skill_shadow_longnight", "skill_shadow_lamp"]:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	CharacterData.active_skill_loadout = ["skill_shadow_reach", "skill_shadow_cut",
		"skill_shadow_beam", "skill_shadow_bind"]
	CharacterData.passive_skill_loadout = ["skill_shadow_lamp"]
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_04",
		"boss_id": "boss_04_b",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.9).timeout
	var boss: Node2D = arena.boss
	var player: Node2D = arena.player
	if boss == null:
		get_tree().quit(1)
		return
	if player != null:
		player.invincible_timer = 999.0
		player._apply_attributes_to_runtime(true)
	# 1) idle：战场地面 + 界灯 + 本体影身
	boss.set_physics_process(false)
	boss.set_process(false)
	var lamp: Vector2 = boss._light_pos()
	var away: Vector2 = (boss.global_position - lamp).normalized()
	if player != null:
		player.global_position = boss.global_position + away * 220.0
	boss.target = player
	boss._set_facing(away)
	boss._update_shadow()
	await get_tree().create_timer(0.5).timeout
	await _shot("zhizhu_arena_idle.png")

	# 2) 八式逐招：每招一张，检查特效形状 / 时机 / 可辨识度
	for row in FORMS:
		var fid := String(row[0])
		var tag := String(row[1])
		boss._current_skill = fid
		boss._anchor = {}
		boss._split_left = 0.0
		boss._dim_left = 0.0
		boss.call("_play_form_anim", fid, 0.9)
		boss.call("_cast_" + tag, MoveDB.resolve_boss(fid))
		boss._update_shadow()
		await get_tree().create_timer(float(row[2])).timeout
		await _shot("zhizhu_fx_" + tag + ".png")
		await get_tree().create_timer(0.45).timeout

	# 3) 二阶段：夺灯后本体无影、玩家脚下出现反照影带
	boss.set_physics_process(true)
	boss.set_process(true)
	boss.current_hp = boss.max_hp * 0.42
	boss.take_damage(1.0, player, "physical", "")
	await get_tree().create_timer(1.6).timeout
	if player != null:
		player.global_position = boss.global_position + Vector2(0.0, 300.0)
	await get_tree().create_timer(0.5).timeout
	boss._update_shadow()
	print("  P2 检查 phase=%d lamp_owned=%s split_left=%.2f band=%s chan=%s" % [
		boss.phase, str(boss._lamp_owned), boss._split_left,
		str(boss._band_v != null and is_instance_valid(boss._band_v)),
		str(boss._channel())])
	print("  BOSS 在 %s · 玩家在 %s · 本体影身 %s" % [
		str(boss.global_position), str(player.global_position),
		str(boss._shadow.global_position) if boss._shadow != null else "无"])
	await _shot("zhizhu_arena_phase2.png")
	boss._current_skill = "form_shadow_longnight"
	boss._anchor = boss._anchor_at(player.global_position)
	boss.call("_play_form_anim", "form_shadow_longnight", 1.5)
	boss._cast_longnight(MoveDB.resolve_boss("form_shadow_longnight"))
	boss._update_shadow()
	await get_tree().create_timer(0.30).timeout
	await _shot("zhizhu_fx_longnight.png")

	# 4) 玩家侧读数：灯笼拖尾 + 前方影带（跑动后影长拉满）
	boss.set_physics_process(false)
	boss.set_process(false)
	if player != null:
		player.velocity = Vector2(240.0, 0.0)
		player.attack_dir = Vector2.RIGHT
		player._lantern_pos = player.global_position + Vector2(-250.0, 0.0)
		for i in 8:
			player._tick_shadow(0.05)
		await get_tree().create_timer(0.25).timeout
		print("  —— 细长条清单 ——")
		_dump_bars(arena)
		await _shot("zhizhu_player_band.png")
		player._shadow_precast("skill_shadow_reach", Vector2.RIGHT)
		player._shadow_cast_reach(Vector2.RIGHT)
		await get_tree().create_timer(0.2).timeout
		await _shot("zhizhu_player_reach.png")
		player._shadow_reset()
	get_tree().quit(0)
