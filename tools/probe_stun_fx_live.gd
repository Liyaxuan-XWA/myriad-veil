extends Node
## 眩晕头顶星 · 真实箱庭动态自检（物理开启，靠真实计时收尾）
## 用法：godot --headless --path . tools/probe_stun_fx_live.tscn -- --no-save

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	print("\n########## 眩晕头顶星 · 真实箱庭 ##########")
	CharacterData.learned_skills.clear()
	CharacterData.active_skill_loadout.clear()
	CharacterData.passive_skill_loadout.clear()
	CharacterData.learned_skills.append("skill_thunder_accum")
	CharacterData.passive_skill_loadout = ["skill_thunder_accum"]
	CharacterData.current_realm = "结丹"
	CharacterData.realm_stage = 2
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_03",
		"boss_id": "boss_03",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	for i in 4:
		await get_tree().process_frame
	var player: Node2D = arena.player
	var boss: Node2D = arena.boss
	if player == null or boss == null:
		_fails.append("player/boss 未生成")
		get_tree().quit(1)
		return
	player.invincible_timer = 999.0
	player.hp = player.max_hp
	boss.target = null
	boss.current_hp = boss.max_hp
	await get_tree().process_frame

	var need: int = SkillDB.THUNDER_ACCUM_REQUIRED
	for i in need - 1:
		player._note_thunder_skill_hit(boss, "skill_thunder_drum", "")
	_check(boss.get_node_or_null("StunFx") == null, "真实箱庭：%d 击不眩晕" % (need - 1))
	player._note_thunder_skill_hit(boss, "skill_thunder_drum", "")
	_check(boss.state == BossBase.BossState.STAGGER, "真实箱庭：第 %d 击进入眩晕" % need)
	var bfx := boss.get_node_or_null("StunFx")
	_check(bfx != null and bfx is StunFx, "真实箱庭：BOSS 头顶星出现")
	await get_tree().create_timer(0.2, true, false, true).timeout
	_check(boss.get_node_or_null("StunFx") != null, "真实计时：0.2 秒时星还在")
	await get_tree().create_timer(0.6, true, false, true).timeout
	await get_tree().process_frame
	_check(boss.get_node_or_null("StunFx") == null, "真实计时：眩晕结束星消失")
	_check(boss.state != BossBase.BossState.STAGGER, "真实计时：BOSS 退出硬直")

	player.apply_debuff("stun", 0.45, true)
	_check(player.get_node_or_null("StunFx") != null, "真实箱庭：玩家眩晕星出现")
	await get_tree().create_timer(0.2, true, false, true).timeout
	_check(player.get_node_or_null("StunFx") != null, "真实计时：玩家 0.2 秒时星还在")
	await get_tree().create_timer(0.45, true, false, true).timeout
	await get_tree().process_frame
	_check(not player.is_stunned(), "真实计时：玩家眩晕解除")
	_check(player.get_node_or_null("StunFx") == null, "真实计时：玩家星消失")

	GameState.battle_context = {}
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
