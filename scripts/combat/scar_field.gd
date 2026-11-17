class_name ScarField
extends Node2D
## 刀痕场地管理器 —— **刀客功法流派专属的玩法组件，不是基础系统**
##
## 定位说明（重要）：
##   刀痕不是「人人都有的场景机制」，它只是众多功法流派中的一套自成体系的玩法，
##   供玩家构筑 build 用。因此：
##     - 不常驻任何战斗场景，**没人用带 scar_effect 的招式时它根本不存在**
##     - 由第一个使用刀痕类招式的一方（BOSS 或玩家）按需创建（ensure()）
##     - 双方共用同一份实例与上限，所以玩家学会刀客招式后能和 BOSS 打同一套刀痕博弈
##
## 职责（2026-10-18 改版：激活 = 瞬间斩击，不再是持续灼烧）：
##   - 生成普通刀痕（上限 4，超出时替换「剩余时间最短」的一处）
##   - 按路径 / 半径 / 全场激活：**一次激活多道时，本次斩击伤害系数 = 激活数量**，
##     激活的刀痕在造成斩击后立即消失
##
## 使用：
##   读 —— ScarField.get_active()（没有就返回 null，调用方自行按 0 处理）
##   写 —— ScarField.ensure()（没有就现建一个挂到当前场景）

const MAX_NORMAL := 4
const SCAR_SCENE := "res://scenes/combat/blade_scar.tscn"

## 场上全部刀痕（激活即消失，所以只有普通刀痕）
var _scars: Array = []


## 刀痕上限：肉鸽爬塔「刀痕上限 +N」「残血翻倍」改这里；主模式恒等于 MAX_NORMAL
func _max_normal() -> int:
	if not RogueRun.active:
		return MAX_NORMAL
	var cap := RogueRun.cap("scar_max")
	# 血怒：气血低于 30% 时上限翻倍（本局内最痛的一刀往往就在这个区间）
	if RogueRun.has_flag("scar_cap_low_double"):
		var player := player_unit()
		if player != null and "max_hp" in player and float(player.get("max_hp")) > 0.0:
			if float(player.get("hp")) / float(player.get("max_hp")) <= 0.30:
				cap *= 2
	return cap


## 取玩家节点（只读；没有就返回 null）
## ⚠ 只在肉鸽分支调用；主模式下刀痕场上的 owner 可能是 BOSS，别拿它当玩家
static func player_unit() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group("player")


func _ready() -> void:
	add_to_group("scar_field")


## 查找现有的刀痕管理器（没有返回 null）—— 只读查询用
static func get_active() -> ScarField:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var node := tree.get_first_node_in_group("scar_field")
	return node as ScarField


## 取或现建刀痕管理器 —— 只有真正要生成/激活刀痕时才调用
## 这样「不使用刀痕流派」的战斗完全不会多出这个节点
static func ensure() -> ScarField:
	var existing := get_active()
	if existing != null:
		return existing
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var scene := tree.current_scene
	if scene == null:
		return null
	var field := ScarField.new()
	field.name = "ScarField"
	scene.add_child(field)
	return field


# ===================== 生成 =====================

## 生成普通刀痕
## pos         世界坐标
## side        BladeScar.SIDE_BOSS / SIDE_PLAYER（归属方，只伤对方）
## power       伤害强度（BOSS 传 attack_power；玩家传法术攻击 × 法技增伤）
## coeff       伤害系数的基础值（默认 1.0；实际系数 = 本值 × 本次激活数量）
## avoid       避免生成在其中心附近的位置（通常是玩家，防止贴脸刷）
## damage_kind 伤害类型，跟留痕技能一致（physical / elemental）
## caster      留痕者本体。⚠ 棋局里两只刀客分属两队、side 完全相同，
##             不传本体就没法分清是谁的痕（取敌与点燃都会串队）。
func spawn_scar(pos: Vector2, side: String, power: float, coeff: float = 1.0,
		avoid: Node2D = null, damage_kind: String = "elemental",
		caster: Node = null) -> BladeScar:
	_cleanup()
	# 不能直接生成在目标身上：稍微推开，保证有反应时间
	var spawn_pos := pos
	if avoid != null and is_instance_valid(avoid):
		var away: Vector2 = spawn_pos - avoid.global_position
		if away.length() < 40.0:
			spawn_pos = avoid.global_position + (away.normalized() * 40.0 if away.length() > 0.01 else Vector2.RIGHT * 40.0)

	# 普通刀痕达上限：替换剩余时间最短的一处
	var normals := _normal_scars()
	if normals.size() >= _max_normal():
		var victim := _shortest_life(normals)
		if victim != null:
			_remove_scar(victim)

	var scar := _instantiate_scar()
	if scar == null:
		return null
	scar.global_position = spawn_pos
	scar.owner_side = side
	scar.owner_unit = caster
	# 战报行名：刀痕的接触伤与引爆都走这一颗 scar，归到「刀痕」一行。
	# 归属本来就走得通（记账侧认 owner_unit），这里只补玩家看得懂的名字。
	scar.set_meta("report_tag", "刀痕")
	scar.damage_power = power
	scar.damage_coeff = coeff
	scar.damage_kind = damage_kind
	# 肉鸽「留存 +N 秒」：主模式 stat 恒为 0
	if RogueRun.active:
		scar.life = BladeScar.SCAR_LIFE + RogueRun.stat("scar_life")
	add_child(scar)
	_scars.append(scar)
	return scar


func _instantiate_scar() -> BladeScar:
	var packed := load(SCAR_SCENE) as PackedScene
	if packed == null:
		push_warning("刀痕场景缺失：" + SCAR_SCENE)
		return null
	return packed.instantiate() as BladeScar


# ===================== 激活：瞬间斩击 =====================
## ⚠ 2026-10-18 改版：激活不再是「变成持续灼烧的强化刀痕」，
##   而是**当场化为一次斩击**，命中后刀痕立即消失。
##   伤害系数 = 本次激活的刀痕数量（每多激活一个 +1），由 _slash_list 统一算。

## 激活半径内的普通刀痕（最多 max_count 处），返回实际激活数量
## side 为空表示不限归属方
func ignite_in_radius(center: Vector2, radius: float, max_count: int = 2,
		side: String = "", igniter: Node = null) -> int:
	_cleanup()
	var in_range: Array = []
	for s in _normal_scars():
		if not _mine(s, side, igniter):
			continue
		if (s as BladeScar).global_position.distance_to(center) <= radius:
			in_range.append(s)
	return _slash_list(in_range, max_count)


## 激活一条线段路径上的普通刀痕（刀气穿过刀痕）
func ignite_in_path(from: Vector2, to: Vector2, max_count: int = 1,
		side: String = "", igniter: Node = null) -> int:
	_cleanup()
	var in_path: Array = []
	for s in _normal_scars():
		if not _mine(s, side, igniter):
			continue
		var p: Vector2 = (s as BladeScar).global_position
		# 点到线段的距离
		var ab := to - from
		var t := 0.0
		if ab.length_squared() > 0.0001:
			t = clampf((p - from).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var closest := from + ab * t
		if p.distance_to(closest) <= 44.0:
			in_path.append(s)
	return _slash_list(in_path, max_count)


## 激活全部普通刀痕（供「封路刀域」这类范围法术使用）
## max_count <= 0 表示「按当前上限」（肉鸽可以把上限抬高）
func ignite_all(side: String = "", max_count: int = 0, igniter: Node = null) -> int:
	_cleanup()
	if max_count <= 0:
		max_count = _max_normal()
	var filtered: Array = []
	for s in _normal_scars():
		if not _mine(s, side, igniter):
			continue
		filtered.append(s)
	return _slash_list(filtered, max_count)


## 批量斩击：先确定本次激活几处，再把同一个数量传给每一道刀痕
## （这样「激活 N 个 → 每道斩击系数都是 N」，正是用户要的连携奖励）
func _slash_list(candidates: Array, max_count: int) -> int:
	var count := mini(max_count, candidates.size())
	if count <= 0:
		return 0

	var done := 0
	for s in candidates:
		if done >= count:
			break
		var scar := s as BladeScar
		if not is_instance_valid(scar):
			continue
		# ⚠ 传的是本次激活总数 count，不是序号 —— 每一道斩击都吃到完整连携加成
		scar.slash(count)
		done += 1
	return done


# ===================== 查询 =====================

func normal_count() -> int:
	_cleanup()
	return _normal_scars().size()


func total_count() -> int:
	_cleanup()
	return _scars.size()


## 取某位置附近最近的刀痕（供评分：玩家是否待在刀痕区）
func nearest_scar_distance(pos: Vector2, side: String = "", igniter: Node = null) -> float:
	_cleanup()
	var best := 999999.0
	for s in _scars:
		if not is_instance_valid(s):
			continue
		if not _mine(s, side, igniter):
			continue
		best = minf(best, (s as BladeScar).global_position.distance_to(pos))
	return best


func clear_all() -> void:
	for s in _scars.duplicate():
		if is_instance_valid(s):
			(s as Node).queue_free()
	_scars.clear()


# ===================== 内部 =====================

## 这一道痕是不是"你"的。
## 给了 igniter 就按**本体**认 —— 棋局里两队刀客的 side 都是 SIDE_BOSS，
## 只按 side 筛就会点燃对手的痕、然后劈到自己人；
## 没给就退回旧的 side 筛，保证既有调用点行为一字不变。
func _mine(scar: Node, side: String, igniter: Node) -> bool:
	if igniter != null:
		return is_instance_valid(scar) and (scar as BladeScar).owner_unit == igniter
	if side != "":
		return (scar as BladeScar).owner_side == side
	return true



func _normal_scars() -> Array:
	var out: Array = []
	for s in _scars:
		if is_instance_valid(s):
			out.append(s)
	return out


func _shortest_life(list: Array) -> BladeScar:
	var victim: BladeScar = null
	var best := 999999.0
	for s in list:
		if not is_instance_valid(s):
			continue
		var scar := s as BladeScar
		if scar.life < best:
			best = scar.life
			victim = scar
	return victim


func _remove_scar(scar: BladeScar) -> void:
	_scars.erase(scar)
	if is_instance_valid(scar):
		scar.queue_free()


## 清理已销毁的引用（刀痕到期自行 queue_free）
func _cleanup() -> void:
	var alive: Array = []
	for s in _scars:
		if is_instance_valid(s) and not (s as Node).is_queued_for_deletion():
			alive.append(s)
	_scars = alive
