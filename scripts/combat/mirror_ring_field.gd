class_name MirrorRingField
extends Node2D
## 照影界「水镜环 / 镜湖」共享水场（2026-11-01）
##
## 铺一圈镜水，每 0.8 秒结算一次水伤并挂减速；走出圈就结束。
## 只影响施放者的敌对目标；圈是死的，不带势条、不叠层。

const TICK := 0.8

var faction: String = "boss"        # boss / player
var radius: float = 150.0
var duration: float = 3.0
var damage: float = 0.0
var source_unit: Node2D = null
var tint: Color = Color(0.62, 0.86, 1.0, 1.0)

var _spawn_pos := Vector2.ZERO
var _age: float = 0.0
var _tick: float = 0.15
var _ring: Sprite2D = null
var _fill: Sprite2D = null
var _scale := 1.0


func setup(pos: Vector2, by_player: bool, p_radius: float, p_duration: float,
		p_damage: float, p_source: Node2D, p_tint: Color) -> void:
	_spawn_pos = pos
	faction = "player" if by_player else "boss"
	radius = maxf(40.0, p_radius)
	duration = maxf(0.5, p_duration)
	source_unit = p_source
	tint = p_tint
	## 棋局按「整场结算」归一化：一枚环从头到尾的总伤害 = 它名义那一击的伤害。
	## ⚠ 为什么只在棋局做：`damage_coeff`（水镜环 0.5）是 PvE 口径，设计案写明「走出环即可」——
	##   那 0.5 本来就假设目标只吃 1~2 拍。棋子站桩对拼、不会走出这块 AoE ⇒ 3 秒 4 拍全中。
	##   实测（tools/diag_match_ring.tscn，观澜 vs 两仪 22 秒）：一次施放连镜像铺的那枚
	##   共 2 枚环 7 拍，raw ≈ 24000 = 对面棋子 76% 血；战报里「水镜环」一行占它总输出 37.5%，
	##   和出手约三次的照影刺（38.6%）齐平。
	##   PvE 一个字不动：玩家真走得出圈，那一档是设计好的压力，不是 bug。
	##   归一化放在这里而不是各铺场点：本体环、镜像环、以后任何复用这条场的招式都自动跟上。
	damage = maxf(0.0, p_damage) / _match_tick_share()
	# 战报：镜环场自己成一行，钱并到铺它的那只棋子名下
	set_meta("report_tag", "镜环场")


## 这枚环该被摊成几拍：来源是带队伍号的棋子（棋局）⇒ 拍数；
## 玩家本人 / 秘境里法宝召唤的观澜（team_id 为 -1 或压根没这个字段）⇒ 1.0，原样。
## 拍数是 ceil(duration / TICK) 不是 floor：第一次 tick 落在 0.15 秒（`_tick` 的初值），
## 所以 3.0 秒的环实际拍 4 下（0.15 / 0.95 / 1.75 / 2.55），镜像那枚 2.0 秒拍 3 下。
func _match_tick_share() -> float:
	if source_unit == null or not is_instance_valid(source_unit):
		return 1.0
	var tid = source_unit.get("team_id")
	if tid == null or int(tid) < 0:
		return 1.0
	return maxf(1.0, ceilf(duration / TICK))


func _ready() -> void:
	global_position = _spawn_pos
	z_index = 2
	_scale = radius / TreasureFx.SOFT_RING_RADIUS_PX
	_fill = Sprite2D.new()
	_fill.texture = TreasureFx.soft_disc_texture()
	_fill.centered = true
	_fill.scale = Vector2(_scale, _scale)
	_fill.modulate = Color(tint.r, tint.g, tint.b, 0.10)
	_fill.z_index = -1
	add_child(_fill)
	_ring = Sprite2D.new()
	_ring.texture = TreasureFx.soft_ring_texture()
	_ring.centered = true
	_ring.scale = Vector2(_scale, _scale)
	_ring.modulate = Color(tint.r, tint.g, tint.b, 0.52)
	add_child(_ring)


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	_age += delta
	if _age >= duration:
		_fade_and_free()
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK
		_pulse()
	var left := duration - _age
	if left < 0.35:
		var fade := clampf(left / 0.35, 0.0, 1.0)
		if _ring != null:
			_ring.modulate.a = 0.52 * fade
		if _fill != null:
			_fill.modulate.a = 0.10 * fade
	else:
		var pulse := 0.5 + 0.5 * sin(_age * 4.0)
		if _ring != null:
			_ring.modulate.a = 0.48 + 0.10 * pulse


func _pulse() -> void:
	# 镜像死后它留下的环还会走完 duration；source 可能已经释放，传 null 让伤害照常结算
	var src: Node2D = source_unit if is_instance_valid(source_unit) else null
	for raw in _targets():
		var u := raw as Node
		if not u.has_method("take_damage"):
			continue
		if u.is_in_group("player"):
			u.call("take_damage", damage, "elemental", src, "water")
		else:
			u.call("take_damage", damage, src, "elemental", "water")
		if u.has_method("apply_debuff"):
			u.call("apply_debuff", "mirror_slow", 1.0)


func _targets() -> Array:
	var out: Array = []
	# 棋局：施法者是带队伍号的棋子 ⇒ 按队伍筛。
	# 旧写法按 faction 去扫 player / ally_summon 组，棋盘上两个都空
	# ⇒ 镜环场在棋局里圈不住任何东西（不崩，静默失效）。
	var src_team := -1
	if source_unit != null and is_instance_valid(source_unit):
		src_team = BossBase.unit_team(source_unit)
	if src_team >= 0:
		return BossBase.hostile_units(source_unit)
	if faction == "player":
		for raw in get_tree().get_nodes_in_group("boss"):
			if not is_instance_valid(raw) or not raw is Node2D:
				continue
			var u := raw as Node2D
			if BossBase.is_ally_unit(u):
				continue
			if u.has_method("is_dead") and bool(u.call("is_dead")):
				continue
			if u.global_position.distance_to(global_position) <= radius + 18.0:
				out.append(u)
	else:
		for group in ["player", "ally_summon"]:
			for raw in get_tree().get_nodes_in_group(group):
				if not is_instance_valid(raw) or not raw is Node2D:
					continue
				var u := raw as Node2D
				if u.has_method("is_dead") and bool(u.call("is_dead")):
					continue
				if u.global_position.distance_to(global_position) <= radius + 18.0:
					out.append(u)
	return out


func _fade_and_free() -> void:
	set_process(false)
	var tw := create_tween()
	if _ring != null:
		tw.tween_property(_ring, "modulate:a", 0.0, 0.25)
	if _fill != null:
		tw.parallel().tween_property(_fill, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)
