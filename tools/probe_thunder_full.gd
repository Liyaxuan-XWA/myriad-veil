extends Node
## 满雷势：攻速 +30% + 每次平A协同雷击（2026-10-30）
## 用法：godot --headless --path . tools/probe_thunder_full.tscn -- --no-save

class CoopBoss extends Node2D:
	var hits: Array = []
	var kinds: Array = []
	var elems: Array = []
	var stuns: Array = []
	var dead := false

	func take_damage(amount: float, _source: Node = null, kind: String = "physical",
			elem: String = "", _from_projectile: bool = false) -> void:
		hits.append(amount)
		kinds.append(kind)
		elems.append(elem)

	func hit_spheres() -> Array:
		return [Vector3(0.0, 0.0, 20.0)]

	func is_dead() -> bool:
		return dead

	func head_top_y() -> float:
		return -100.0

	func stun_for(seconds: float) -> void:
		stuns.append(seconds)


var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _reset_attack(p: Node) -> void:
	p.is_attacking = false
	p.attack_timer = 0.0
	p._attack_hit_timer = -1.0
	p.attack_cancel_available = false


func _make_boss(pos: Vector2) -> CoopBoss:
	var b := CoopBoss.new()
	b.add_to_group("boss")
	b.global_position = pos
	add_child(b)
	return b


func _ready() -> void:
	print("\n########## 满雷势 · 攻速与协同雷击 ##########")
	CharacterData.learned_skills.clear()
	CharacterData.active_skill_loadout.clear()
	CharacterData.passive_skill_loadout.clear()
	CharacterData.clear_all_attribute_mods()
	CharacterData.learned_skills.append("skill_thunder_verdict")
	CharacterData.active_skill_loadout = ["skill_thunder_verdict"]

	var player: Node2D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector2.ZERO
	await get_tree().process_frame
	player.set_physics_process(false)
	player.set_process(false)
	player._refresh_thunder_unlock()
	_check(player._thunder_unlocked, "雷系功法已装备 / 雷势系统解锁")
	player.lei_shi = 2
	player._add_lei(1)
	_check(player.lei_shi == 3 and player._thunder_full_active(),
		"第 3 层雷势进入满雷势")
	player.lei_shi = 0

	# ---- 攻速 ----
	var base_interval: float = CharacterData.attack_interval()
	player.lei_shi = 0
	player.attack_combo = 0
	player._start_attack()
	var normal_time: float = player.attack_time
	_reset_attack(player)
	_check(is_equal_approx(normal_time, base_interval), "未满雷势：普攻间隔 = 基础",
		"%.4f / %.4f" % [normal_time, base_interval])

	player.lei_shi = 3
	player.attack_combo = 0
	player._start_attack()
	var full_time: float = player.attack_time
	var expected := base_interval / 1.3
	_reset_attack(player)
	_check(absf(full_time - expected) < 0.002, "满雷势：普攻间隔 ÷1.3（攻速 +30%）",
		"%.4f / %.4f" % [full_time, expected])

	player.lei_shi = 3
	player.attack_combo = 2
	player._start_attack()
	var finisher_time: float = player.attack_timer
	var expected_finisher: float = float(player.FINISHER_TIME) / 1.3
	_reset_attack(player)
	_check(absf(finisher_time - expected_finisher) < 0.002, "满雷势：终结段同样加速",
		"%.4f / %.4f" % [finisher_time, expected_finisher])

	player.lei_shi = 3
	player._spend_lei(1)
	player.attack_combo = 0
	player._start_attack()
	var after_spend: float = player.attack_time
	_reset_attack(player)
	_check(is_equal_approx(after_spend, base_interval), "消耗雷势后攻速恢复",
		"%.4f / %.4f" % [after_spend, base_interval])

	# ---- 协同雷击 ----
	var cfg := ArtDB.get_skill_fx("fx_thunder_coop")
	_check(not cfg.is_empty() and String(cfg.get("thunder_mode", "")) == "coop",
		"协同雷击特效已登记")
	player.lei_shi = 3
	player.attack_dir = Vector2.RIGHT
	var fx: SkillFx = SkillFx.play_at_strike(player, "fx_thunder_coop",
		{"range": 62.0, "hit_shape": MoveDB.SHAPE_CIRCLE}, Vector2.RIGHT, Vector2.ZERO)
	_check(fx != null, "协同雷击特效可播放")
	if fx != null:
		fx.queue_free()

	var front := _make_boss(Vector2(52.0, 0.0))
	player.lei_shi = 2
	player.attack_dir = Vector2.RIGHT
	front.hits.clear()
	front.kinds.clear()
	player._perform_attack_hit()
	_check(front.hits.size() == 1 and String(front.kinds[0]) == "physical",
		"未满雷势：平A只结算本体", "hits=%d %s" % [front.hits.size(), str(front.kinds)])

	player.lei_shi = 3
	player.attack_dir = Vector2.RIGHT
	front.hits.clear()
	front.kinds.clear()
	front.elems.clear()
	player._perform_attack_hit()
	var spell_dmg: float = CharacterData.spell_attack() * float(player.THUNDER_COOP_COEF)
	var hit_coop := front.hits.size() == 2 \
		and String(front.kinds[1]) == "elemental" \
		and String(front.elems[1]) == "thunder"
	_check(hit_coop, "满雷势：平A命中后追加一次协同雷击",
		"hits=%d %s %s" % [front.hits.size(), str(front.kinds), str(front.elems)])
	_check(front.hits.size() == 2 and absf(float(front.hits[1]) - spell_dmg) < 0.01,
		"协同雷击伤害 = 法术 ×0.5",
		"%.2f / %.2f" % [float(front.hits[1]) if front.hits.size() > 1 else -1.0, spell_dmg])
	front.queue_free()
	await get_tree().process_frame

	# 背后目标不应被“身前协同雷”命中
	var back := _make_boss(Vector2(-60.0, 0.0))
	player.lei_shi = 3
	player.attack_dir = Vector2.RIGHT
	back.hits.clear()
	player._perform_attack_hit()
	_check(back.hits.is_empty(), "协同雷击只打身前目标，不误伤背后",
		"hits=%d" % back.hits.size())
	back.queue_free()
	await get_tree().process_frame

	# ---- 协同雷击计入雷积·震魂 ----
	CharacterData.learned_skills.append("skill_thunder_accum")
	CharacterData.passive_skill_loadout = ["skill_thunder_accum"]
	player._refresh_thunder_unlock()
	var target := _make_boss(Vector2(52.0, 0.0))
	player.lei_shi = 3
	player.attack_dir = Vector2.RIGHT
	var need: int = SkillDB.THUNDER_ACCUM_REQUIRED
	for i in need:
		player._perform_attack_hit()
	_check(target.stuns.size() == 1 and is_equal_approx(float(target.stuns[0]), 0.5),
		"%d 次平A协同雷击触发雷积眩晕" % need, str(target.stuns))

	target.queue_free()
	CharacterData.passive_skill_loadout.clear()
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
