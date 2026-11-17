extends StaticBody2D
## 演武场木桩：不灭、不反击、记录伤害。
##
## 只在 CombatArena 的训练模式（BattleResolver.SOURCE_ARENA）里替换 BOSS。
## 它实现玩家伤害链路需要的 take_damage 签名，但永远不扣血、不死亡；
## 记录总伤害 / 最近 5 秒 DPS / 最高单次 / 命中次数 / 训练时长，供训练 HUD 读取。
## 木桩本体走 ArtDB.VISUALS["training_dummy"]，换图只改表。

## 兼容字段：部分通用逻辑会以 BossBase 的口径读这些值
var boss_id: String = "training_dummy"
var max_hp: float = 1.0
var current_hp: float = 1.0
var phase: int = 1
var target: Node2D = null

var total_damage: float = 0.0
var max_hit: float = 0.0
var hit_count: int = 0
## 灾痕 / 元素减益：木桩不结算伤害，只保留持续供灾劫连锁与头顶读数使用
var debuffs: Dictionary = {}
## 三灾 / 演武场：固定火灾位，方便测灾位切换、破灾与万劫归一；
## 木桩不参与灾轮 AI，只提供玩家侧 `_calamity_boss()` 需要的读数接口。
var _calamity: String = "fire"
var _momentum: int = 0

var _session_time: float = 0.0
var _first_hit := false
## 最近命中：{ "left": 秒, "amount": 伤害 }，用于 5 秒 DPS
var _recent_hits: Array = []
var _flash_tween: Tween
var _wobble_tween: Tween
var _nudge_tween: Tween

@onready var skin: SkinVisual = $Skin


func _ready() -> void:
	add_to_group("boss")
	current_hp = max_hp
	set_process(true)
	_reset_pose()


func _process(delta: float) -> void:
	_tick_debuffs(delta)
	if not _first_hit:
		return
	# 顿帧 / 慢动作不拖慢训练计时；暂停时本函数不执行
	var real_delta := delta / maxf(Engine.time_scale, 0.0001)
	_session_time += real_delta
	for i in range(_recent_hits.size() - 1, -1, -1):
		_recent_hits[i]["left"] = float(_recent_hits[i].get("left", 0.0)) - real_delta
		if float(_recent_hits[i].get("left", 0.0)) <= 0.0:
			_recent_hits.remove_at(i)


func _tick_debuffs(delta: float) -> void:
	if debuffs.is_empty():
		return
	for id in debuffs.keys():
		var left := float(debuffs[id]) - delta
		if left <= 0.0:
			debuffs.erase(id)
		else:
			debuffs[id] = left


## 灾劫连锁需要在木桩身上挂灾痕；木桩只记持续，不结算持续伤害 / 易伤
func apply_debuff(id: String, duration: float) -> bool:
	if id == "" or duration <= 0.0:
		return false
	if DebuffDB.get_debuff(id).is_empty():
		return false
	debuffs[id] = maxf(float(debuffs.get(id, 0.0)), duration)
	return true


func has_debuff(id: String) -> bool:
	return float(debuffs.get(id, 0.0)) > 0.0


func remove_debuff(id: String) -> void:
	debuffs.erase(id)


## 三灾：让演武场也能看见/积攒玩家灾势（木桩固定火位，可反复破灾）
func calamity_state() -> String:
	return _calamity


func on_calamity_broken(_source: Node) -> bool:
	return true


func gain_calamity_momentum(n: int) -> void:
	_momentum = clampi(_momentum + n, 0, 3)


## 与 BossBase 头顶锚点同口径；灾痕读数挂在头侧
func head_top_y() -> float:
	return -150.0


## 玩家近战 / 法术 / 投射物 / 刀痕全部走这里。
## 不扣 current_hp，也不发 died；木桩永远不灭。
func take_damage(amount: float, source: Node = null, damage_kind: String = "physical",
		_element: String = "", _from_projectile: bool = false) -> void:
	if amount <= 0.0:
		return
	var dmg := float(amount)
	if not _first_hit:
		_first_hit = true
		_session_time = 0.0
	total_damage += dmg
	max_hit = maxf(max_hit, dmg)
	hit_count += 1
	_recent_hits.append({"left": 5.0, "amount": dmg})

	var parent := get_parent()
	if parent != null:
		DamageNumber.spawn(parent, global_position + Vector2(0.0, -150.0), dmg,
			DamageNumber.kind_from_damage_kind(damage_kind))
	_flash_hit()
	_wobble_hit(source)
	GameState.trigger_hit_stop()


## 训练 HUD 每帧读取；全部为本次「重置」以来的数据
func get_training_stats() -> Dictionary:
	var recent_sum := 0.0
	for e in _recent_hits:
		recent_sum += float(e.get("amount", 0.0))
	var window := maxf(0.5, minf(5.0, _session_time)) if _first_hit else 1.0
	var recent_dps := recent_sum / window if _first_hit else 0.0
	var total_dps := total_damage / maxf(0.5, _session_time) if _first_hit else 0.0
	return {
		"total": total_damage,
		"dps": total_dps,
		"recent_dps": recent_dps,
		"max_hit": max_hit,
		"hits": hit_count,
		"time": _session_time,
		"active": _first_hit,
	}


func reset_training_stats() -> void:
	total_damage = 0.0
	max_hit = 0.0
	hit_count = 0
	_session_time = 0.0
	_first_hit = false
	_recent_hits.clear()
	debuffs.clear()
	if has_meta(CalamityMarkFx.META):
		var fx = get_meta(CalamityMarkFx.META)
		if fx != null and is_instance_valid(fx):
			fx.queue_free()
		remove_meta(CalamityMarkFx.META)
	_reset_pose()


func is_dead() -> bool:
	return false


## 木桩没有抗性，训练读数就是玩家面板上的基础伤害
func attribute(_attr_id: String) -> float:
	return 0.0


## 受击球：与 BossBase.hit_spheres 同一口径（CollisionShape2D → 圆点 / 胶囊沿长轴采样）。
## ⚠ 必须实现：木桩不是 BossBase 子类，玩家判定拿不到受击球时会退回半径 0 的兜底球，
##   而判定循环会跳过半径 ≤ 0 的球 —— 结果就是普攻与扇形功法永远打不到木桩。
func hit_spheres() -> Array:
	var out: Array = []
	for cs in find_children("*", "CollisionShape2D", true, false):
		var c := cs as CollisionShape2D
		if c == null or c.shape == null or c.disabled:
			continue
		if c.shape is CircleShape2D:
			out.append(Vector3(c.position.x, c.position.y, (c.shape as CircleShape2D).radius))
		elif c.shape is CapsuleShape2D:
			var cap := c.shape as CapsuleShape2D
			var r := cap.radius
			var seg := maxf(cap.height * 0.5 - r, 0.0)
			var steps := maxi(1, int(ceil(seg * 2.0 / maxf(r * 0.6, 1.0))))
			for i in range(steps + 1):
				var t := -seg + seg * 2.0 * float(i) / float(steps)
				var p: Vector2 = c.transform * Vector2(0.0, t)
				out.append(Vector3(p.x, p.y, r))
	if out.is_empty():
		# 兜底也给正半径：受击球全空时玩家判定会整只跳过，木桩就又「打不到」了
		out.append(Vector3(0.0, 0.0, 24.0))
	return out


func _flash_hit() -> void:
	if not is_instance_valid(skin):
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	# 闪白（乘到 2 倍提亮）：和 BOSS 同一套受击语言
	skin.modulate = Color(2.0, 2.0, 2.0, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(skin, "modulate", Color.WHITE, 0.10)


func _wobble_hit(source: Node = null) -> void:
	if not is_instance_valid(skin):
		return
	# 回弹：沿「来源→自己」方向顶 2px 再弹回，纯视觉，不动碰撞
	var dir := Vector2.RIGHT
	if source != null and is_instance_valid(source) and source is Node2D:
		var away: Vector2 = global_position - (source as Node2D).global_position
		if away.length_squared() > 0.0001:
			dir = away.normalized()
	if _nudge_tween != null and _nudge_tween.is_valid():
		_nudge_tween.kill()
	skin.position = Vector2.ZERO
	_nudge_tween = create_tween()
	_nudge_tween.tween_property(skin, "position", dir * 2.0, 0.03)
	_nudge_tween.tween_property(skin, "position", Vector2.ZERO, 0.11) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if _wobble_tween != null and _wobble_tween.is_valid():
		_wobble_tween.kill()
	var wobble_dir := 1.0 if randf() > 0.5 else -1.0
	_wobble_tween = create_tween()
	_wobble_tween.tween_property(skin, "rotation", 0.055 * wobble_dir, 0.055) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_wobble_tween.tween_property(skin, "rotation", -0.032 * wobble_dir, 0.10) \
		.set_trans(Tween.TRANS_SINE)
	_wobble_tween.tween_property(skin, "rotation", 0.0, 0.13) \
		.set_trans(Tween.TRANS_SINE)


func _reset_pose() -> void:
	if _wobble_tween != null and _wobble_tween.is_valid():
		_wobble_tween.kill()
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	if _nudge_tween != null and _nudge_tween.is_valid():
		_nudge_tween.kill()
	if is_instance_valid(skin):
		skin.rotation = 0.0
		skin.position = Vector2.ZERO
		skin.modulate = Color.WHITE
