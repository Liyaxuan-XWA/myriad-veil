extends Node
## 只读：用当前元婴后期存档实测观澜 TTK（--no-save，不写盘）

func _ready() -> void:
	SaveManager.load_latest_auto()
	for sid in ["skill_mirror_slash", "skill_mirror_bloom", "skill_mirror_shatter",
			"skill_mirror_ring", "skill_mirror_echo"]:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	CharacterData.active_skill_loadout = ["skill_mirror_slash", "skill_mirror_bloom",
		"skill_mirror_shatter", "skill_mirror_ring"]
	CharacterData.passive_skill_loadout = ["skill_mirror_echo"]
	print("LIVE HP %.0f 物攻 %.0f 法攻 %.0f 间隔 %.3f 法技x%.2f" % [
		CharacterData.max_hp(), CharacterData.physical_attack(),
		CharacterData.spell_attack(), CharacterData.attack_interval(),
		CharacterData.spell_skill_damage_mult()])
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_04",
		"boss_id": "boss_04",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node2D = arena.player
	var boss: Node2D = arena.boss
	player.invincible_timer = 999.0
	var t := 0.0
	var attack_tick := 0.0
	var skill_tick := 0.0
	var phase2 := -1.0
	var killed := -1.0
	while t < 120.0:
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
		if boss.phase == 2 and phase2 < 0.0:
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
		if int(t * 10.0) % 100 == 0:
			print("  t=%.0fs BOSS %.0f/%.0f phase=%d" % [
				t, boss.current_hp, boss.max_hp, boss.phase])
	print("RESULT phase2=%.1f kill=%.1f  boss=%.0f/%.0f" % [
		phase2, killed, boss.current_hp if is_instance_valid(boss) else 0.0,
		boss.max_hp if is_instance_valid(boss) else 0.0])
	get_tree().quit(0)
