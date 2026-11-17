extends Node
## 只读：用当前实机存档实测叠纸（塔 12 层 / 72,000 血 / 238 攻）的 TTK（--no-save，不写盘）
## 口径与 probe_zhizhu_live_play / probe_guanying_live_play 一致：
## 玩家贴住 BOSS 自动普攻 + 循环功法，量的是「这套养成打这管血要多久」，
## 用来校准设计案 §2.2 那一档（目标 90s 上下）。
## 用法：godot --headless --path . res://tools/probe_fold_live_play.tscn -- --no-save

func _ready() -> void:
	SaveManager.load_latest_auto()
	for sid in ["skill_fold_press", "skill_fold_trace", "skill_fold_stride",
			"skill_fold_seam", "skill_fold_shroud", "skill_fold_tear",
			"skill_fold_twin", "skill_fold_triple", "skill_fold_measure"]:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	## 标定档用四门伤害向功法：裁痕 / 叠掩是状态招，占一格会把吞吐压低约 17%，
	## 拿那种轮盘量出来的秒数去定血量会把它定得虚高（执烛当初就是四门伤害向）。
	CharacterData.active_skill_loadout = ["skill_fold_press", "skill_fold_trace",
		"skill_fold_stride", "skill_fold_twin"]
	CharacterData.passive_skill_loadout = ["skill_fold_measure"]
	print("LIVE HP %.0f 物攻 %.0f 法攻 %.0f 间隔 %.3f 法技x%.2f" % [
		CharacterData.max_hp(), CharacterData.physical_attack(),
		CharacterData.spell_attack(), CharacterData.attack_interval(),
		CharacterData.spell_skill_damage_mult()])
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_04",
		"boss_id": "boss_04_c",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	for i in 3:
		await get_tree().process_frame
	var player: Node2D = arena.player
	var boss: Node2D = arena.boss
	if player == null or boss == null:
		print("RESULT 玩家或 BOSS 未生成")
		get_tree().quit(1)
		return
	player.invincible_timer = 999.0
	var t := 0.0
	var attack_tick := 0.0
	var skill_tick := 0.0
	var phase2 := -1.0
	var killed := -1.0
	while t < 170.0:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
		if not is_instance_valid(boss):
			break
		player.invincible_timer = 999.0
		player.hp = player.max_hp
		player.mana = player.max_mana
		player.stamina = player.max_stamina
		if boss.state == BossBase.BossState.DEAD:
			killed = t
			break
		if int(boss.phase) == 2 and phase2 < 0.0:
			phase2 = t
		var to_boss: Vector2 = boss.global_position - player.global_position
		if to_boss.length() > 90.0:
			player.global_position = boss.global_position - to_boss.normalized() * 86.0
		player.attack_dir = (boss.global_position - player.global_position).normalized()
		attack_tick -= 0.1
		if attack_tick <= 0.0:
			attack_tick = CharacterData.attack_interval()
			if not player.is_attacking and not player.is_dead:
				player._start_attack()
		skill_tick -= 0.1
		if skill_tick <= 0.0:
			skill_tick = 0.8
			for sid in CharacterData.active_skill_loadout:
				if player.try_use_skill(String(sid)):
					break
		## 机制参与读数：玩家离最近那条痕有多远（>贴合带 = 这一秒镜像碰不到他）
		if int(t * 10.0) % 200 == 0:
			var fld = boss._field
			var fd: float = float(fld.fold_dist(player.global_position)) if fld != null \
				else -1.0
			print("  t=%.0fs BOSS %.0f/%.0f phase=%d 离痕 %.0f（贴合带 %.0f）痕数 %d" % [
				t, boss.current_hp, boss.max_hp, boss.phase, fd,
				FoldLaw.reach_for(int(boss.phase)),
				(fld.spans as Array).size() if fld != null else 0])
	print("RESULT phase2=%.1f kill=%.1f boss=%.0f/%.0f" % [
		phase2, killed, boss.current_hp if is_instance_valid(boss) else 0.0,
		boss.max_hp if is_instance_valid(boss) else 0.0])
	get_tree().quit(0)
