extends Node
## 只读：用当前实机存档（元婴后期）实测执烛 TTK（--no-save，不写盘）
## 口径与 probe_guanying_live_play 一致：玩家贴住 BOSS 自动普攻 + 循环功法，
## 量的是「这套养成打这管血要多久」，用来校准 56,000 / 205 这一档。

var _mode := "stand"


## 把想要的前进方向翻译成四个移动键的合成按压：_get_move_dir() 走 Input.get_vector，
## 只有真的按住键 player.velocity 才非零，灯笼才会被甩出去。
func _walk(player: Node2D, want: Vector2) -> void:
	if want.length_squared() < 0.0001:
		return
	var want_dir := want.normalized()
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_up")
	Input.action_release("move_down")
	if want_dir.x > 0.25:
		Input.action_press("move_right")
	elif want_dir.x < -0.25:
		Input.action_press("move_left")
	if want_dir.y > 0.25:
		Input.action_press("move_down")
	elif want_dir.y < -0.25:
		Input.action_press("move_up")


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--mode="):
			_mode = String(a).split("=")[1]
	print("MODE ", _mode, "（stand=贴脸站桩 / kite=绕圈真跑）")
	SaveManager.load_latest_auto()
	for sid in ["skill_shadow_cut", "skill_shadow_reach", "skill_shadow_beam",
			"skill_shadow_bind", "skill_shadow_dim", "skill_shadow_split",
			"skill_shadow_longnight", "skill_shadow_lamp"]:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	CharacterData.active_skill_loadout = ["skill_shadow_reach", "skill_shadow_cut",
		"skill_shadow_beam", "skill_shadow_bind"]
	CharacterData.passive_skill_loadout = ["skill_shadow_lamp"]
	print("LIVE HP %.0f 物攻 %.0f 法攻 %.0f 间隔 %.3f 法技x%.2f" % [
		CharacterData.max_hp(), CharacterData.physical_attack(),
		CharacterData.spell_attack(), CharacterData.attack_interval(),
		CharacterData.spell_skill_damage_mult()])
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
	await get_tree().process_frame
	var player: Node2D = arena.player
	var boss: Node2D = arena.boss
	player.invincible_timer = 999.0
	var t := 0.0
	var attack_tick := 0.0
	var skill_tick := 0.0
	var phase2 := -1.0
	var killed := -1.0
	# 新旧口径对照（同一局、同一面板）：影技在**命中帧**取射程。
	# 新口径取按下那一帧的快照 = player._shadow_len()；
	# 旧口径就是当时的实时值 = player._shadow_len_now()。两个数同帧各读一次，
	# 差值即「这次改动到底把多少发影技从打空救回射程内」，不用另跑一遍旧代码。
	var pend: Array = []
	var hit_snap: Array = []
	var hit_live: Array = []
	# 旧口径的影子灯笼（want 吃**瞬时**速度）跟着同一份速度走一遍：
	# 只读 player.velocity，不改真灯笼，所以量的是「同一局里旧模型会给多少射程」。
	var ghost_lag := 0.0
	var hit_ghost: Array = []
	while t < 160.0:
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
		if _mode == "kite":
			# 绕着 BOSS 真跑：合成移动键，velocity 才非零 —— 直接改 global_position
			# 造出来的是「永远不跑」的假玩家，影长永远是 40，量不到这组的射程机制。
			var dist := player.global_position.distance_to(boss.global_position)
			var to_boss2: Vector2 = boss.global_position - player.global_position
			var ring := 260.0
			var radial := (ring - dist) / maxf(dist, 1.0)
			var tangent := Vector2(-to_boss2.y, to_boss2.x).normalized()
			_walk(player, tangent + to_boss2.normalized() * clampf(radial, -1.2, 1.2))
		else:
			var to_boss: Vector2 = boss.global_position - player.global_position
			if to_boss.length() > 90.0:
				player.global_position = boss.global_position - to_boss.normalized() * 86.0
			for a in ["move_left", "move_right", "move_up", "move_down"]:
				Input.action_release(a)
		# 旧模型：want 直接吃这一帧的速度（平A 定身那 0.13 秒就是 0），灯笼 430px/s 追上来
		ghost_lag = move_toward(ghost_lag,
				clampf(player.velocity.length() * 1.30, 0.0, ShadowLaw.LANTERN_LAG_MAX),
				ShadowLaw.LANTERN_CATCHUP * 0.1)
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
					pend.append({"at": t + float(
						SkillDB.get_skill_form(String(sid)).get("windup", 0.15))})
					break
		while not pend.is_empty() and float(pend[0]["at"]) <= t:
			pend.pop_front()
			hit_snap.append(player._shadow_len())
			hit_live.append(player._shadow_len_now())
			hit_ghost.append(maxf(ghost_lag * ShadowLaw.LANTERN_SLOPE
				* ShadowLaw.PASSIVE_MULT, ShadowLaw.SHADOW_MIN))
		if int(t * 10.0) % 100 == 0:
			print("  t=%.0fs BOSS %.0f/%.0f phase=%d 影长 %.0f" % [
				t, boss.current_hp, boss.max_hp, boss.phase, player._shadow_len()])
	print("RESULT phase2=%.1f kill=%.1f boss=%.0f/%.0f" % [
		phase2, killed, boss.current_hp if is_instance_valid(boss) else 0.0,
		boss.max_hp if is_instance_valid(boss) else 0.0])
	if not hit_snap.is_empty():
		var ms := 0.0
		var ml := 0.0
		var mg := 0.0
		for v in hit_snap:
			ms += float(v)
		for v in hit_live:
			ml += float(v)
		for v in hit_ghost:
			mg += float(v)
		var n := float(hit_snap.size())
		var short_snap := 0
		var short_live := 0
		var short_ghost := 0
		for v in hit_snap:
			if float(v) < SkillDB.SHADOW_CUT_TIP_EXTRA:
				short_snap += 1
		for v in hit_live:
			if float(v) < SkillDB.SHADOW_CUT_TIP_EXTRA:
				short_live += 1
		for v in hit_ghost:
			if float(v) < SkillDB.SHADOW_CUT_TIP_EXTRA:
				short_ghost += 1
		print("命中帧影长 n=%d：新(快照) %.0f / 新但实时 %.0f / 旧模型 %.0f → 对旧 ×%.2f" % [
			int(n), ms / n, ml / n, mg / n, (ms / n) / maxf(mg / n, 1.0)])
		print("其中射程不够 150（打不到人）的比例：新 %d%% / 旧模型 %d%%" % [
			int(round(100.0 * short_snap / n)), int(round(100.0 * short_ghost / n))])
	get_tree().quit(0)
