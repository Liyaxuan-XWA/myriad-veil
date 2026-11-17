extends Node
## 法宝召唤友军自检（2026-11-02 用户报三条）
##   1) 劫主令召出的晏无咎一直对着玩家打
##   2) 镜主令召出的观澜，镜湖水场能打到玩家
##   3) 火正令召出的离照一直对着玩家打，而且捡不起天火种
## 共同根因：友军召唤物入的是 "ally_summon" 组，而这几处代码把「对手」写死成玩家组。
## 用法：godot --headless --path . tools/probe_ally_summons.tscn -- --no-save

## 敌方（被挑战的）BOSS：刀客，会玩火的它当靶子
const ENEMY_SCENE := "res://scenes/boss/domain_boss_03.tscn"
## [名字, 令模板 id]
const SUMMONS: Array = [
	["晏无咎", "tr_jiezhu_ling"],
	["离照", "tr_huozheng_ling"],
	["观澜", "tr_guanying_ling"],
]

var _passes := 0
var _fails: Array = []
var _p: Node2D
var _enemy: Node2D
## 走到哪一步了：卡住时看门狗会把它打出来
var _step := "init"


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 法宝召唤友军探针 ##########")
	# 看门狗：真机 BOSS 脚本一挂就查不到原因，先把卡在哪一步打出来
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("WATCHDOG 卡在：", _step)
		get_tree().quit(2))
	await get_tree().process_frame

	_p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_p)
	await get_tree().process_frame
	await get_tree().process_frame
	_p.set_physics_process(false)
	_p.set_process(false)
	_p.global_position = Vector2.ZERO

	for s in SUMMONS:
		await _run_summon(String(s[0]), String(s[1]))

	await _test_seed_rules()

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _make_enemy() -> void:
	_step = "spawn enemy " + ENEMY_SCENE
	_enemy = (load(ENEMY_SCENE) as PackedScene).instantiate() as Node2D
	add_child(_enemy)
	await get_tree().process_frame
	_enemy.set_physics_process(false)
	_enemy.global_position = Vector2(300.0, 0.0)


func _run_summon(name: String, tpl_id: String) -> void:
	print("\n-- ", name, "（", tpl_id, "）--")
	_step = "enemy for " + name
	await _make_enemy()
	_check(_enemy.is_in_group("boss"), "敌方 BOSS 在 boss 组")

	var tpl := ItemDB.get_treasure_template(tpl_id)
	_check(not tpl.is_empty() and String(tpl.get("summon_boss_id", "")) != "",
		"%s 模板带 summon_boss_id" % tpl_id)
	_step = "summon " + name
	_check(_p._summon_ally_boss(tpl), "召唤成功")

	var ally: Node2D = null
	for c in get_children():
		if c == _p or c == _enemy or not (c is Node2D):
			continue
		# 用 is_ally_unit 而不是 bool(get(...))：普通 Node 上取不到该属性会拿到 null，
		# 再 bool() 就踩「Nonexistent 'bool' constructor」（BossBase 里专门记过这条）
		if BossBase.is_ally_unit(c as Node) and (c as Node).get("summon_life") != null:
			ally = c as Node2D
	_check(ally != null, "%s 已作为友军入场" % name)
	if ally == null:
		return

	_check(ally.is_in_group("ally_summon") and not ally.is_in_group("boss"),
		"%s 入 ally_summon 组（不是 boss 组）" % name)
	_check(is_same(ally.get("target"), _enemy), "%s 的 target 是敌方 BOSS" % name)
	# 核心：所有「打谁 / 朝谁走」的读数都不能返回玩家
	var opp = ally.call("_player_node") if ally.has_method("_player_node") \
		else ally.call("opponent_node")
	_check(opp != null and is_same(opp, _enemy),
		"%s 的对手读数是敌方 BOSS，不是玩家" % name, str(opp))
	_check(not is_same(opp, _p), "%s 不会把召唤者当对手" % name)

	# 伤害分派：友军的一击只结算到 target
	var units: Array = ally.call("attack_units")
	_check(units.size() == 1 and is_same(units[0], _enemy),
		"%s 的攻击列表里只有敌方 BOSS" % name, str(units))
	var foes: Array = ally.call("enemy_units")
	_check(not foes.has(_p), "%s 的 enemy_units 不含玩家" % name, str(foes.size()))

	_step = "ring " + name
	await _test_ring_faction(ally)
	_step = "seed " + name
	await _test_fire_seed(ally, name)

	ally.queue_free()
	_enemy.queue_free()
	await get_tree().process_frame


## 镜湖：水场必须按施放者阵营结算，友军的场子不能泡到玩家
func _test_ring_faction(ally: Node2D) -> void:
	if not ally.has_method("_cast_ring"):
		return
	var before := _count_rings()
	_step = "cast ring"
	ally.call("_cast_ring", {})
	await get_tree().process_frame
	var field: Node = null
	for c in get_children():
		if c is MirrorRingField and get_child_count() > before:
			field = c
	if field == null:
		for c in get_children():
			if c is MirrorRingField:
				field = c
	_check(field != null, "观澜友军能铺出镜湖")
	if field == null:
		return
	_check(String(field.get("faction")) == "player",
		"友军镜湖按玩家阵营结算（原来写死 boss 会打到玩家）",
		str(field.get("faction")))
	var targets: Array = field.call("_targets")
	_check(not targets.has(_p), "友军镜湖的目标里没有玩家", str(targets.size()))


func _count_rings() -> int:
	var n := 0
	for c in get_children():
		if c is MirrorRingField:
			n += 1
	return n


## 天火种：会玩火的友军要捡得起；不会玩火的召唤物仍然捡不起
func _test_fire_seed(ally: Node2D, name: String) -> void:
	if not ally.has_method("uses_sun_seed") or not bool(ally.call("uses_sun_seed")):
		return
	for c in get_children():
		if c is SunSeed:
			c.queue_free()
	await get_tree().process_frame
	_step = "spawn seed"
	ally.call("_spawn_seed")
	await get_tree().process_frame
	var seed: SunSeed = null
	for raw in get_tree().get_nodes_in_group("sun_seed"):
		if raw is SunSeed:
			seed = raw as SunSeed
	_check(seed != null, "%s 场上落下了天火种" % name)
	if seed == null:
		return
	seed.call("pickup", ally)
	_check(bool(seed.call("is_held_by", ally)), "%s 友军捡起了天火种" % name)
	seed.call("drop", seed.global_position)
	await get_tree().process_frame


func _test_seed_rules() -> void:
	print("\n-- 火种归属规则 --")
	_step = "seed rules"
	for raw in get_tree().get_nodes_in_group("sun_seed"):
		(raw as Node).queue_free()
	await get_tree().process_frame
	var seed := SunSeed.new()
	add_child(seed)
	seed.global_position = Vector2(120.0, 0.0)
	await get_tree().process_frame
	_check(seed.is_in_group("sun_seed") and int(seed.get("state")) == 0,
		"自建火种落在场上且是自由态")
	_check(bool(seed.call("_can_hold", _p)), "玩家能拿火种")
	var tiger := DummyAlly.new()
	add_child(tiger)
	await get_tree().process_frame
	_check(not bool(seed.call("_can_hold", tiger)), "不会玩火的友军召唤物拿不到火种")
	tiger.queue_free()
	seed.queue_free()


## 只会砍人的友军召唤物（虎妖 / 刀客那一类）：在 ally_summon 组里但不玩火
class DummyAlly extends CharacterBody2D:
	var is_ally := true

	func _ready() -> void:
		collision_layer = 0
		add_to_group("ally_summon")
