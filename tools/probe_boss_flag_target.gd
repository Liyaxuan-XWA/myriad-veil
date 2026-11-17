extends Node
## 玩家阵旗实体化 / BOSS 正常索敌打旗（2026-10-29）：
##   五旗围住 BOSS → target 变成最近玩家旗；旗有 Area2D 命中体；BOSS 投射物/招式命中各算一刀；
##   三刀后旗消失，BOSS 目标回到玩家。没有特殊「破阵」自动攻击。
## 用法：godot --headless --path . res://tools/probe_boss_flag_target.tscn

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
	print("\n########## BOSS 打玩家旗自检 ##########")
	for sid in ["skill_array_plant"]:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	var p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	p.global_position = Vector2.ZERO
	p.set_physics_process(false)
	p.set_process(false)
	p.is_teleporting = false
	p.invincible_timer = 0.0
	p._refresh_array_unlock()
	p._clear_array_flags()
	for i in 5:
		var ang := -PI * 0.5 + TAU * float(i) / 5.0
		p._plant_array_flag(Vector2(cos(ang), sin(ang)) * 200.0, ArrayFlag.Kind.ATTACK)
	var flags: Array = p.array_flags
	_check(flags.size() == 5, "玩家五旗已插", "flags=%d" % flags.size())

	# 每面玩家旗都有实体命中体
	var hitbox_ok := true
	for raw in flags:
		var f: Node = raw
		var hb := f.get_node_or_null("Hitbox") as Area2D
		if hb == null or hb.collision_layer != ArrayFlag.PLAYER_HIT_LAYER:
			hitbox_ok = false
			break
	_check(hitbox_ok, "玩家旗有实体命中体（层 256）")

	var boss = (load("res://scenes/boss/domain_boss_02_b.tscn") as PackedScene).instantiate()
	add_child(boss)
	await get_tree().process_frame
	await get_tree().process_frame
	boss.set_physics_process(false)
	boss.set_process(false)
	boss.set("target", p)
	boss.global_position = Vector2.ZERO
	boss.set("state", BossBase.BossState.IDLE)

	boss.call("_tick_threat", 0.016)
	var tgt = boss.get("target")
	_check(tgt is ArrayFlag, "被围住时 BOSS 正常索敌到玩家旗",
		str((tgt as Node).name if tgt is Node else tgt))
	_check(not boss.has_method("_tick_player_array_break"), "特殊破阵自动攻击已移除")

	var units: Array = boss.call("enemy_units")
	var flag_count := 0
	for u in units:
		if u is ArrayFlag:
			flag_count += 1
	_check(flag_count == 5, "围住时五面旗进入普通攻击单位列表", "n=%d" % flag_count)

	var flag: Node = tgt
	var hitbox := flag.get_node_or_null("Hitbox") as Area2D
	# 用 BOSS 真正发射路径生成投射物：场景默认 mask 带 256 不代表运行时没被覆盖
	var proj := boss.call("_spawn_projectile", "physical_projectile") as Area2D
	_check(proj != null, "BOSS 能生成远程投射物")
	if proj != null:
		proj.set_physics_process(false)
		_check((proj.collision_mask & ArrayFlag.PLAYER_HIT_LAYER) != 0,
			"BOSS 运行时投射物会检测玩家旗层", "mask=%d" % proj.collision_mask)
		proj.call("_on_area_entered", hitbox)
		_check(int(flag.get("hits_left")) == 2, "投射物命中算一刀",
			"hits=%d" % int(flag.get("hits_left")))
		proj.queue_free()

	# 真实物理帧：投射物压住旗的命中体，必须触发 area_entered（不是只测 mask / 手动调回调）
	var live_proj := boss.call("_spawn_projectile", "physical_projectile") as Area2D
	_check(live_proj != null, "真实投射物已生成")
	if live_proj != null:
		live_proj.global_position = hitbox.global_position
		live_proj.set_physics_process(false)
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(int(flag.get("hits_left")) == 1, "真实投射物撞旗算一刀",
			"hits=%d" % int(flag.get("hits_left")))

	# 普通招式命中再一刀 → 消失
	flag.call("take_damage", 10.0, boss, "physical", "", false)
	_check(bool(flag.get("_dead")) and bool(flag.get("is_dead")), "三次伤害后旗消失")

	boss.call("_tick_threat", 0.016)
	var tgt2 = boss.get("target")
	_check(not (tgt2 is ArrayFlag) and tgt2 == p, "旗破后 BOSS 目标回到玩家",
		str((tgt2 as Node).name if tgt2 is Node else tgt2))
	_check(boss.call("_player_array_trap_flag") == null, "环破后不再把旗当围困")

	# 雷落这类爆发打掉 BOSS 当前目标后，target 是 previously freed；
	# 不能再直接 `target is ArrayFlag`（2026-10-29 实机闪退）
	var gone := Node2D.new()
	add_child(gone)
	boss.set("target", gone)
	boss.set("threat_target", gone)
	gone.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	boss.call("_tick_player_array_trap_override")
	_check(boss.get("target") == null and boss.get("threat_target") == null,
		"目标被释放后安全清空")

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("FAILED  ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
