extends Node
## 刀客「命中附带效果」跨单位类型分派自检（2026-11-09）
##
## 事故现场：玩家被刀客「沉步竖斩」命中，整局崩在
##   Invalid type in function 'apply_debuff' in base 'CharacterBody2D (player.gd)'
##   Cannot convert argument 3 from Object to bool
## 根因：同名接口两边第三参语义相反
##   Player.apply_debuff(id, duration, quiet: bool)
##   BossBase.apply_debuff(id, duration, from_unit: Node)
##   刀客统一传 self → 打到玩家身上就是 Object → bool。
## 同类隐患：apply_slow 前两参顺序也相反（duration/ratio vs mult/seconds）。
##
## 用法：godot --headless --path . res://tools/probe_boss_debuff_target.tscn -- --no-save

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _spawn_boss(pos: Vector2) -> Node2D:
	var b: Node2D = (load("res://scenes/boss/domain_boss_01.tscn") as PackedScene).instantiate()
	add_child(b)
	b.global_position = pos
	# 探针只手动调函数，不让 AI / 刀痕系统自己跑起来干扰断言
	b.set_physics_process(false)
	b.set_process(false)
	return b


func _ready() -> void:
	print("\n########## 刀客命中附带效果 · 跨类型分派 ##########")
	CharacterData.learned_skills.clear()
	CharacterData.passive_skill_loadout.clear()

	var player: Node2D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector2.ZERO
	var boss := _spawn_boss(Vector2(220.0, 0.0))
	var boss2 := _spawn_boss(Vector2(-220.0, 0.0))
	await get_tree().process_frame
	await get_tree().physics_frame

	# 真实招式数据（沉步竖斩），不手搓字典
	var form: Dictionary = MoveDB.resolve_boss("form_blade_heavy")
	_check(String(form.get("debuff_on_hit", "")) == "wounded",
		"沉步竖斩带 debuff_on_hit=wounded", String(form.get("debuff_on_hit", "")))

	# ===== 1. 对玩家：旧代码在这里抛类型错整局崩 =====
	boss.set("target", player)
	boss.call("_apply_hit_side_effects", form)
	_check(player.has_debuff("wounded"), "刀客对玩家挂上「重伤」且没崩",
		str(player.debuffs))

	# 重复命中只刷新时长、不叠层
	var left_first := float(player.debuffs.get("wounded", 0.0))
	boss.call("_apply_hit_side_effects", form)
	_check(left_first > 0.0
		and absf(float(player.debuffs.get("wounded", 0.0)) - left_first) < 0.01,
		"重复命中不叠加（取剩余较长者）", "%.2f → %.2f" % [left_first, float(player.debuffs.get("wounded", 0.0))])

	# ===== 2. 对 BOSS：第三参必须仍然传得进去（战报认归属）=====
	boss.set("target", boss2)
	boss.call("_apply_hit_side_effects", form)
	_check(boss2.has_debuff("wounded"), "刀客对 BOSS 目标也能挂上",
		str(boss2.debuffs))
	var by: Dictionary = boss2.get("_debuff_by")
	_check(by.get("wounded") == boss, "跳伤归属记到刀客名下（第三参没丢）",
		str(by.get("wounded")))

	# ===== 3. 小减速：两边前两参顺序相反，按类型分派后各自正确 =====
	var slow_b: Dictionary = {"slow_on_hit": true, "slow_time": 0.9, "slow_ratio": 0.4}
	boss.set("target", player)
	player.call("clear_debuff", "wounded")
	player._slow_timer = 0.0
	player._slow_ratio = 0.0
	boss.call("_apply_hit_side_effects", slow_b)
	_check(absf(player._slow_timer - 0.9) < 0.01, "玩家减速时长 = slow_time",
		"%.2f" % player._slow_timer)
	_check(absf(player._slow_ratio - 0.4) < 0.01, "玩家减速比例 = slow_ratio",
		"%.2f" % player._slow_ratio)

	boss.set("target", boss2)
	boss2.set("_cc_slow_left", 0.0)
	boss2.set("_cc_slow_mult", 1.0)
	boss.call("_apply_hit_side_effects", slow_b)
	_check(absf(float(boss2.get("_cc_slow_mult")) - 0.4) < 0.01, "BOSS 减速乘区 = slow_ratio",
		"%.2f" % float(boss2.get("_cc_slow_mult")))
	_check(absf(float(boss2.get("_cc_slow_left")) - 0.9) < 0.01, "BOSS 减速时长 = slow_time",
		"%.2f" % float(boss2.get("_cc_slow_left")))

	# ===== 4. 玩家侧第三参仍是 quiet(bool)，没被这次分派改坏 =====
	var ok_quiet: bool = player.apply_debuff("wounded", 1.5, true)
	_check(ok_quiet or player.has_debuff("wounded"), "玩家 apply_debuff(..., true) 仍可调用",
		str(player.debuffs))

	# ===== 5. 玩家招式命中附带 debuff 的钩子真的会执行 =====
	# 2026-11-09 事故：_apply_player_skill_debuff() 最后两行被多缩进一级，
	# 落在 `if debuff_id == "": return` 之后成了死代码 ——
	# 全项目 25 个玩家招式的 debuff（阴蚀/日灼/风蚀/劫火/感电/影浸/折印…）从来没挂上过。
	# 数据没问题（resolve_player 会合并 player{} 子表），纯粹是缩进。
	var slash_form := SkillDB.get_skill_form("skill_calamity_slash")
	_check(String(slash_form.get("debuff_on_hit", "")) == "feng_shi",
		"player{} 子表里的 debuff_on_hit 能被 resolve 读到",
		String(slash_form.get("debuff_on_hit", "")))
	boss2.set("debuffs", {})
	player.call("_apply_player_skill_debuff", boss2, "skill_calamity_slash")
	_check(boss2.has_debuff("feng_shi"), "玩家招式命中真的挂上 debuff（缩进死代码回归锁）",
		str(boss2.debuffs))

	player.queue_free()
	boss.queue_free()
	boss2.queue_free()
	await get_tree().process_frame

	CharacterData.passive_skill_loadout.clear()
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
