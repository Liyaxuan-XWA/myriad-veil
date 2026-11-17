extends Node
## 眩晕头顶星自检（2026-10-30）
## 覆盖：玩家 stun debuff / BOSS stun_for / BOSS stun debuff / 雷积被动触发击。
## 用法：godot --headless --path . tools/probe_stun_fx.tscn -- --no-save

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _stun_fx_count(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		if child is StunFx:
			n += 1
	return n


func _spawn_boss(pos: Vector2) -> Node:
	var boss: Node = (load("res://scenes/boss/boss.tscn") as PackedScene).instantiate()
	add_child(boss)
	boss.global_position = pos
	boss.target = null
	return boss


func _ready() -> void:
	print("\n########## 眩晕头顶星探针 ##########")
	CharacterData.learned_skills.clear()
	CharacterData.passive_skill_loadout.clear()

	var player: Node2D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector2.ZERO
	await get_tree().process_frame
	await get_tree().physics_frame

	# ---- 玩家 stun debuff ----
	player.apply_debuff("stun", 0.45)
	_check(player.is_stunned(), "玩家 stun 后 is_stunned")
	var pfx := player.get_node_or_null("StunFx")
	_check(pfx != null and pfx is StunFx, "玩家头顶生成 StunFx")
	_check(_stun_fx_count(player) == 1, "玩家只有一套星",
		str(_stun_fx_count(player)))
	_check(pfx != null and pfx.get_child_count() == 4, "三颗星 + 一圈光晕",
		str(pfx.get_child_count()) if pfx != null else "null")
	_check(pfx != null and pfx.z_index >= 60, "星环在 HUD 之上",
		str(pfx.z_index) if pfx != null else "null")
	var p_anchor: float = player.stun_fx_anchor_y()
	_check(p_anchor < -80.0 and p_anchor > -200.0, "玩家锚点在头顶",
		str(p_anchor))
	_check(pfx != null and absf(pfx.position.y - p_anchor) < 0.5,
		"星环锚定玩家头顶", "%.1f / %.1f" % [pfx.position.y, p_anchor] if pfx != null else "")

	player.apply_debuff("stun", 0.45)
	_check(_stun_fx_count(player) == 1, "重复眩晕不叠第二套星",
		str(_stun_fx_count(player)))
	# 手动推进 0.5 秒：debuff 与星环一起到期（无头环境不依赖真实帧率）
	player._tick_debuffs(0.5)
	if pfx != null and is_instance_valid(pfx):
		pfx._process(0.02)
	await get_tree().process_frame
	_check(not player.is_stunned(), "眩晕到时自动解除")
	_check(player.get_node_or_null("StunFx") == null, "眩晕解除后星环消失")

	# ---- BOSS stun_for（被动 / 真眩晕入口）----
	var boss := _spawn_boss(Vector2(400.0, 0.0))
	boss.set_physics_process(false)
	boss.stun_for(0.6)
	_check(boss.is_stunned() and boss.state == BossBase.BossState.STAGGER,
		"BOSS stun_for 进入硬直")
	var bfx := boss.get_node_or_null("StunFx")
	_check(bfx != null and bfx is StunFx, "BOSS 头顶生成 StunFx")
	var b_anchor: float = boss.stun_fx_anchor_y()
	_check(bfx != null and absf(bfx.position.y - b_anchor) < 0.5,
		"星环锚定 BOSS 头顶", "%.1f / %.1f" % [bfx.position.y, b_anchor] if bfx != null else "")
	boss.stun_for(0.3)
	_check(_stun_fx_count(boss) == 1, "BOSS 重复眩晕不叠星",
		str(_stun_fx_count(boss)))
	bfx._process(0.8)
	await get_tree().process_frame
	_check(boss.get_node_or_null("StunFx") == null, "BOSS 眩晕到点星环消失")
	_check(not is_instance_valid(bfx), "BOSS 星环节点已释放")

	# ---- BOSS 走通用 stun debuff 也要有星 ----
	boss.state = BossBase.BossState.IDLE
	boss.state_timer = 0.0
	boss.apply_debuff("stun", 0.35)
	_check(boss.is_stunned(), "BOSS stun debuff 视为眩晕")
	var dfx := boss.get_node_or_null("StunFx")
	_check(dfx != null and dfx is StunFx, "BOSS stun debuff 生成星环")
	boss._tick_debuffs(0.4)
	if dfx != null and is_instance_valid(dfx):
		dfx._process(0.02)
	await get_tree().process_frame
	_check(not boss.has_debuff("stun"), "BOSS stun debuff 到时解除")
	_check(boss.get_node_or_null("StunFx") == null, "BOSS debuff 解除后星环消失")
	boss.queue_free()

	# ---- 雷积·震魂触发击走真实 BossBase.stun_for ----
	CharacterData.learned_skills.append("skill_thunder_accum")
	CharacterData.passive_skill_loadout = ["skill_thunder_accum"]
	var target := _spawn_boss(Vector2(0.0, 260.0))
	target.set_physics_process(false)
	var need: int = SkillDB.THUNDER_ACCUM_REQUIRED
	for i in need - 1:
		player._note_thunder_skill_hit(target, "skill_thunder_drum", "")
	_check(target.get_node_or_null("StunFx") == null, "雷积 %d 击不眩晕" % (need - 1))
	player._note_thunder_skill_hit(target, "skill_thunder_verdict", "thunder")
	_check(target.state == BossBase.BossState.STAGGER, "雷积第 %d 击进入眩晕" % need)
	_check(target.get_node_or_null("StunFx") != null, "雷积第 %d 击生成头顶星" % need)

	# ---- 目标被移除时表现跟着走，不留下孤儿节点 ----
	var tfx := target.get_node_or_null("StunFx")
	target.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not is_instance_valid(tfx), "目标释放后不残留星环")

	CharacterData.passive_skill_loadout.clear()
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
