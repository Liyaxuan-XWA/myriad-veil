class_name YoumingCoreShihou
extends WorldEnemy
## 幽冥灵墟核心首领「镇墟石犼」（2026-10-31 用户实装）
##
## 核心机制「闻声」：它看不见，只追最后一声响的位置。
## 玩家跑动每 0.45s 留脚步点、出手/施法/闪避留大声点；停下 0.35s 就跟丢。
## 它的扑、撞、吐息都打旧点；墓庭六根石碣可以被引撞 —— 撞碑自硬直 2s、受伤 +25% 5s。
## 二阶段「破封·听风」：封眼石带裂开，震塌两根石碣，听觉过敏 + 回声定位；
## 每次长吼后自聋 2s，是玩家自由换位的窗口。
## 没有势条 / 资源 / 层数；读数全在场上：石碣裂缝、声点、封眼石带。

const STEP_P1 := 0.45
const STEP_P2 := 0.30
const LOUD_WINDOW := 0.35
const DEAF_BREATH := 2.5
const DEAF_PHASE2 := 2.0

const STELE_RADIUS := 320.0
const STELE_SCALE := 0.58
const STELE_HITS := 2
const STELE_HIT_RADIUS := 100.0
const STELE_STAGGER := 2.0
const STELE_VULN_TIME := 5.0
const STELE_VULN_MULT := 1.25
const STELE_COUNT := 6

const ECHO_INTERVAL := 6.0
const ECHO_COLOR := Color(0.54, 0.86, 0.94, 0.88)
const WARN_COLOR := Color(0.46, 0.78, 0.86, 0.78)

const STELE_TEX := preload("res://assets/scenes/youming_stele.png")
const STELE_TEX_CRACKED := preload("res://assets/scenes/youming_stele_cracked.png")

var _prey: Node2D = null
var _noise_marker: Node2D = null
var _last_noise := Vector2.ZERO
var _last_noise_seq := -1
var _silent_time := 0.0
var _step_timer := 0.0
var _deaf_left := 0.0

var _steles: Array = []
var _dash_left := 0.0
var _dash_dir := Vector2.ZERO
var _dash_speed := 0.0
var _dash_dmg := 0.0
var _dash_kind := ""
var _dash_radius := 0.0
var _dash_hit_player := false

var _vuln_left := 0.0
var _p2_started := false
var _echo_cd := 0.0
var _search_cd := 0.0
## 招式使用记录（探针 / 平衡观察用，不影响战斗）
var skill_usage: Dictionary = {}


func _ready() -> void:
	super()
	# spawn_home 在 configure 里由核心数据写入；场景摆位后以当前点为准更稳
	if global_position != Vector2.ZERO:
		spawn_home = global_position
	_last_noise = spawn_home
	_noise_marker = Node2D.new()
	_noise_marker.name = "NoiseMarker"
	add_child(_noise_marker)
	_noise_marker.global_position = _last_noise
	_prey = _find_prey()
	_build_steles()


func _exit_tree() -> void:
	for raw in _steles:
		var st: Dictionary = raw
		if is_instance_valid(st.get("node", null)):
			(st["node"] as Node).queue_free()
	_steles.clear()


func _find_prey() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D


## 侧视四足：受击球沿朝向铺开、压到脚底平面
func hit_spheres() -> Array:
	return [
		Vector3(-62.0, 0.0, 56.0),
		Vector3(0.0, 0.0, 66.0),
		Vector3(62.0, 0.0, 56.0),
	]


func head_top_y() -> float:
	return -300.0


# ===================== 闻声：目标 = 最后声点 =====================
func _physics_process(delta: float) -> void:
	_tick_noise(delta)
	_tick_echo(delta)
	_tick_search(delta)
	if _vuln_left > 0.0:
		_vuln_left = maxf(0.0, _vuln_left - delta)
	super(delta)
	if _dash_left > 0.0:
		_tick_dash(delta)
	if state != BossState.DEAD and _engaged and is_instance_valid(_noise_marker):
		target = _noise_marker


## 覆写大世界仇恨：进战判定看玩家，追击目标永远是「最后声点」。
func _tick_threat(delta: float) -> void:
	if state == BossState.DEAD:
		return
	# 对局棋子：闻声机制的猎物是「会发出声音的玩家」，棋盘上没有玩家，
	# 走下面这条路会每帧清 target、四顾无声便回家 —— 实测 0 输出。
	# 交给父类，父类已经把 team_id >= 0 的分支接到基类仇恨表（按队伍号选目标）。
	if team_id >= 0:
		super._tick_threat(delta)
		return
	var p := _prey
	if p == null or not is_instance_valid(p):
		p = _find_prey()
		_prey = p
	var player_dead := p == null or bool(p.get("is_dead"))
	if player_dead:
		target = null
		threat_target = null
		_threat.clear()
		if not _returning and global_position.distance_to(spawn_home) > _home_limit():
			_start_return_home()
		return
	if _returning:
		target = null
		threat_target = null
		return
	var dist := global_position.distance_to(p.global_position)
	var home_dist := global_position.distance_to(spawn_home)
	if not _engaged:
		if (dist <= _aggro_range or _provoked()) and dist <= _leash_range \
				and home_dist <= _leash_range:
			_engaged = true
			_last_noise = p.global_position
			# 把玩家已有的噪声序号对上，避免下一帧把初始 (0,0) 当成新声点
			_last_noise_seq = int(p.get("noise_ping_seq"))
			_noise_marker.global_position = _last_noise
			_silent_time = 0.0
			_step_timer = 0.0
			target = _noise_marker
			threat_target = p
		else:
			target = null
			threat_target = null
			if home_dist > _home_limit():
				_start_return_home()
			return
	if dist > _leash_range or home_dist > _leash_range:
		_disengage()
		return
	# 让基类维护仇恨表 / 召唤物目标，再把追击目标换回声点
	super._tick_threat(delta)
	_noise_marker.global_position = _last_noise
	target = _noise_marker
	threat_target = p


func _step_interval() -> float:
	return STEP_P2 if _p2_started else STEP_P1


func _tick_noise(delta: float) -> void:
	if _prey == null or not is_instance_valid(_prey):
		_prey = _find_prey()
	if _prey == null:
		return
	_silent_time += delta
	if _step_timer > 0.0:
		_step_timer = maxf(0.0, _step_timer - delta)
	if _deaf_left > 0.0:
		_deaf_left = maxf(0.0, _deaf_left - delta)
		return
	if not _engaged:
		return
	# 出手 / 施法 / 闪避的大声点（玩家侧 emit_noise）
	var seq := int(_prey.get("noise_ping_seq"))
	if seq != _last_noise_seq:
		_last_noise_seq = seq
		_last_noise = Vector2(_prey.get("noise_ping_pos"))
		_ping_noise(true)
		return
	# 跑动脚步点：停下就不再有新声点
	var v = _prey.get("velocity")
	var speed := (v as Vector2).length() if v is Vector2 else 0.0
	if speed > 25.0 and _step_timer <= 0.0:
		_last_noise = _prey.global_position
		_ping_noise(false)
		_step_timer = _step_interval()


func _ping_noise(loud: bool) -> void:
	_silent_time = 0.0
	_step_timer = _step_interval()
	if _noise_marker != null and is_instance_valid(_noise_marker):
		_noise_marker.global_position = _last_noise
	if loud:
		# 大声点给一圈很淡的声纹，让玩家知道「它听见的是这里」
		SkillFx.tri_ring_pulse(get_parent(), _last_noise, 96.0,
			Color(0.50, 0.82, 0.92, 0.55))


func _tick_search(delta: float) -> void:
	if _search_cd > 0.0:
		_search_cd = maxf(0.0, _search_cd - delta)
	if not _engaged or state == BossState.DEAD:
		return
	if _deaf_left > 0.0 or _silent_time < 1.5 or _search_cd > 0.0:
		return
	if state != BossState.IDLE and state != BossState.CHASE:
		return
	_search_cd = 3.0
	_show_enemy_float("搜地", Color(0.80, 0.88, 0.94))
	SkillFx.play_at_strike(self, "skill_shihou_slam",
		{"range": 240.0, "angle": 360.0}, facing)
	_hit_circle(240.0, attack_power * 0.45 * _damage_multiplier(),
		"physical_melee", "")


# ===================== 二阶段：回声定位 =====================
func _tick_echo(delta: float) -> void:
	if not _p2_started or not _engaged or state == BossState.DEAD:
		return
	_echo_cd = maxf(0.0, _echo_cd - delta)
	if _echo_cd > 0.0:
		return
	_echo_cd = ECHO_INTERVAL
	for i in 3:
		var timer := get_tree().create_timer(0.55 + 0.60 * float(i), true)
		timer.timeout.connect(_echo_pulse.bind(i))


func _echo_pulse(index: int) -> void:
	if not is_inside_tree() or state == BossState.DEAD or not _p2_started:
		return
	var radius := 300.0 + 300.0 * float(index)
	var from := global_position
	SkillFx.tri_ring_pulse(get_parent(), from, radius, ECHO_COLOR)
	if _prey == null or not is_instance_valid(_prey):
		return
	# 只在声波扫到玩家时判定；原地不动 = 不被听见
	if _prey.global_position.distance_to(from) > radius:
		return
	var moving := false
	var v = _prey.get("velocity")
	if v is Vector2 and (v as Vector2).length() > 25.0:
		moving = true
	if bool(_prey.get("is_attacking")) or bool(_prey.get("is_dodging")) \
			or bool(_prey.get("is_casting_talisman")):
		moving = true
	if not moving:
		return
	_last_noise = _prey.global_position
	_noise_marker.global_position = _last_noise
	_silent_time = 0.0
	_show_enemy_float("被听见了", ECHO_COLOR)
	_core_skill_cds["shihou_pounce"] = 0.0
	_core_skill_cds["shihou_charge"] = 0.0
	_core_attack_cd = minf(_core_attack_cd, 0.05)


## 二阶段封眼石带的裂纹：贴在头部高度的世界层裂纹，闪一下再淡出
func _spawn_eye_crack() -> void:
	var tex := SkillFx.skill_texture("ape_crack")
	if tex == null:
		return
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = true
	spr.material = SkillFx.additive_material()
	spr.modulate = Color(0.46, 0.94, 1.0, 0.0)
	spr.scale = Vector2.ONE * 0.85
	spr.z_index = 30
	get_parent().add_child(spr)
	spr.global_position = global_position + Vector2(0.0, -235.0)
	var tw := spr.create_tween()
	tw.tween_property(spr, "modulate:a", 0.85, 0.12)
	tw.tween_interval(0.65)
	tw.tween_property(spr, "modulate:a", 0.0, 1.20)
	tw.tween_callback(spr.queue_free)


func _on_phase_two() -> void:
	_p2_started = true
	_deaf_left = DEAF_PHASE2
	_echo_cd = 1.0
	_show_enemy_float("封眼石带裂开 · 听风", ECHO_COLOR)
	_spawn_eye_crack()
	if skin != null:
		skin.play_one_shot("phase2", 1.30)
	SkillFx.tri_ring_pulse(get_parent(), global_position, 520.0,
		Color(0.46, 0.80, 0.90, 0.85))
	_collapse_random_steles(2)


func _disengage() -> void:
	super._disengage()
	_p2_started = false
	_echo_cd = 0.0
	_deaf_left = 0.0
	_dash_left = 0.0
	_dash_kind = ""
	_vuln_left = 0.0
	_search_cd = 0.0
	_silent_time = 0.0
	_step_timer = 0.0
	_last_noise_seq = -1
	# 脱战重置石碣，下一次接战是完整墓庭
	for raw in _steles:
		var st: Dictionary = raw
		if is_instance_valid(st.get("node", null)):
			(st["node"] as Node).queue_free()
	_steles.clear()
	_build_steles()


# ===================== 石碣 =====================
func _build_steles() -> void:
	_steles.clear()
	var parent := get_parent()
	if parent == null:
		return
	for i in STELE_COUNT:
		var a := TAU * float(i) / float(STELE_COUNT) + 0.12
		var pos := spawn_home + Vector2.RIGHT.rotated(a) * STELE_RADIUS
		var spr := Sprite2D.new()
		spr.name = "ShihouStele%d" % i
		spr.texture = STELE_TEX
		spr.centered = true
		spr.offset = Vector2(0.0, -170.0 * STELE_SCALE)
		spr.scale = Vector2.ONE * STELE_SCALE
		spr.z_index = 2
		parent.add_child(spr)
		spr.global_position = pos
		_steles.append({
			"node": spr, "pos": pos, "hp": STELE_HITS, "alive": true,
		})


func _collapse_random_steles(count: int) -> void:
	var alive: Array = []
	for i in _steles.size():
		var st: Dictionary = _steles[i]
		if bool(st.get("alive", false)):
			alive.append(i)
	alive.shuffle()
	for i in mini(count, alive.size()):
		_collapse_stele(int(alive[i]))


func _collapse_stele(index: int) -> void:
	if index < 0 or index >= _steles.size():
		return
	var st: Dictionary = _steles[index]
	if not bool(st.get("alive", false)):
		return
	st["alive"] = false
	var spr := st.get("node") as Sprite2D
	if spr == null or not is_instance_valid(spr):
		return
	var tw := spr.create_tween()
	tw.tween_property(spr, "rotation", 0.22, 0.35)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, 0.45)
	tw.tween_callback(spr.queue_free)


func _check_stele_hit(radius: float) -> bool:
	for i in _steles.size():
		var st: Dictionary = _steles[i]
		if not bool(st.get("alive", false)):
			continue
		var pos: Vector2 = st.get("pos", Vector2.ZERO)
		if global_position.distance_to(pos) > radius + STELE_HIT_RADIUS:
			continue
		st["hp"] = int(st.get("hp", STELE_HITS)) - 1
		var spr := st.get("node") as Sprite2D
		if int(st["hp"]) > 0:
			if spr != null and is_instance_valid(spr):
				spr.texture = STELE_TEX_CRACKED
		else:
			_collapse_stele(i)
		stagger_for(STELE_STAGGER)
		_vuln_left = STELE_VULN_TIME
		_show_enemy_float("撞碑 · 失聪", Color(0.92, 0.92, 0.78))
		return true
	return false


# ===================== 出招 =====================
func _start_core_skill(def: Dictionary) -> void:
	super(def)
	var id := String(def.get("id", ""))
	if id != "":
		skill_usage[id] = int(skill_usage.get(id, 0)) + 1
	if id == "shihou_pounce" or id == "shihou_charge":
		SkillFx.calamity_warn_at(get_parent(), _last_noise,
			170.0 if id == "shihou_pounce" else 240.0,
			float(def.get("windup", 0.8)), WARN_COLOR)


func _cast_core_skill() -> void:
	var def := _next_core_skill
	if def.is_empty():
		super()
		return
	match String(def.get("id", "")):
		"shihou_pounce":
			_cast_dash_skill(def, "pounce", 160.0)
		"shihou_charge":
			_cast_dash_skill(def, "charge", 140.0)
		"shihou_claw":
			_cast_claw(def)
		"shihou_slam":
			_cast_slam(def)
		"shihou_breath":
			_cast_breath(def)
		"shihou_tail":
			_cast_tail(def)
		_:
			super()


func _shihou_core_done(def: Dictionary) -> void:
	var id := String(def.get("id", ""))
	if id != "":
		var cd := float(def.get("cooldown", 5.0))
		if phase == 2:
			cd *= 0.8
		_core_skill_cds[id] = cd
	_last_core_skill = id
	_core_attack_cd = 0.35 if phase == 2 else 0.55
	_next_core_skill = {}
	_pending_windup = -1.0


## 盲扑 / 崩山撞：沿最后声点冲刺，路上撞碑会自己硬直
func _cast_dash_skill(def: Dictionary, kind: String, radius: float) -> void:
	_reset_visual()
	_update_facing_to_target()
	var scale := float(def.get("damage_scale", 0.9))
	_dash_dmg = attack_power * scale * _damage_multiplier()
	_dash_kind = kind
	_dash_radius = radius
	_dash_dir = _last_noise - global_position
	var max_dist := float(def.get("dash", 420.0))
	if _dash_dir.length() < 1.0:
		_dash_dir = facing
	var dist := minf(max_dist, _dash_dir.length())
	_dash_dir = _dash_dir.normalized()
	_dash_speed = dist / (0.24 if kind == "pounce" else 0.38)
	_dash_left = 0.24 if kind == "pounce" else 0.38
	_dash_hit_player = false
	SkillFx.play_at_strike(self, String(def.get("fx_id", "")),
		{"range": radius * 2.0, "angle": 360.0}, facing, global_position)
	_show_enemy_float("盲扑" if kind == "pounce" else "崩山撞",
		Color(0.86, 0.94, 1.0))
	_shihou_core_done(def)


func _tick_dash(delta: float) -> void:
	var step := _dash_speed * delta
	global_position += _dash_dir * step
	_dash_left -= delta
	# 撞碑优先：一碰就停、硬直
	if _check_stele_hit(90.0):
		_dash_left = 0.0
		_clamp_to_arena()
		return
	# 崩山撞：冲锋途中蹭到玩家，每段只结算一次；盲扑只在落点结算
	if _dash_kind == "charge" and not _dash_hit_player:
		for u in attack_units():
			if u == null or not is_instance_valid(u) or not (u is Node2D):
				continue
			if (u as Node2D).global_position.distance_to(global_position) <= _dash_radius * 0.75:
				deal_damage_to(u, _dash_dmg * 0.8, "physical_melee")
				_dash_hit_player = true
	_clamp_to_arena()
	if _dash_left <= 0.0:
		_dash_end()


func _dash_end() -> void:
	_dash_left = 0.0
	if _dash_kind == "pounce":
		SkillFx.play_at_strike(self, "skill_shihou_pounce",
			{"range": 160.0, "angle": 360.0}, facing, global_position)
		_hit_circle(_dash_radius, _dash_dmg, "physical_melee", "")
	_dash_kind = ""


## 裂石爪：三次前爪，各自可弹反
func _cast_claw(def: Dictionary) -> void:
	_reset_visual()
	_update_facing_to_target()
	var dmg := attack_power * float(def.get("damage_scale", 0.36)) * _damage_multiplier()
	var hits := maxi(1, int(def.get("hits", 3)))
	for i in hits:
		var timer := get_tree().create_timer(0.01 + 0.18 * float(i), true)
		timer.timeout.connect(_claw_hit.bind(dmg, i))
	_shihou_core_done(def)


func _claw_hit(dmg: float, index: int) -> void:
	if not is_inside_tree() or state == BossState.DEAD:
		return
	_update_facing_to_target()
	SkillFx.play_at_strike(self, "skill_shihou_claw",
		{"range": 230.0, "angle": 120.0}, facing)
	_hit_fan(230.0, 120.0, dmg, "physical_melee", "")


## 震地：360° 震波 + 3 秒裂地
func _cast_slam(def: Dictionary) -> void:
	_reset_visual()
	_update_facing_to_target()
	var dmg := attack_power * float(def.get("damage_scale", 0.85)) * _damage_multiplier()
	SkillFx.play_at_strike(self, "skill_shihou_slam",
		{"range": 270.0, "angle": 360.0}, facing)
	_hit_circle(270.0, dmg, "physical_melee", "")
	var pos := global_position
	for i in 6:
		var timer := get_tree().create_timer(0.5 + 0.5 * float(i), true)
		timer.timeout.connect(_slam_tick.bind(pos, dmg * 0.18))
	_slam_fx(pos)
	_shihou_core_done(def)


func _slam_fx(pos: Vector2) -> void:
	var holder := Node2D.new()
	holder.z_index = 2
	get_parent().add_child(holder)
	holder.global_position = pos
	var spr := Sprite2D.new()
	spr.texture = SkillFx.ring_texture()
	spr.centered = true
	spr.material = SkillFx.additive_material()
	spr.scale = Vector2.ONE * 1.4
	spr.modulate = Color(0.40, 0.76, 0.84, 0.35)
	holder.add_child(spr)
	var tw := spr.create_tween()
	tw.tween_property(spr, "scale", spr.scale * 1.35, 3.0)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, 3.0)
	tw.tween_callback(holder.queue_free)


func _slam_tick(pos: Vector2, dmg: float) -> void:
	if not is_inside_tree() or state == BossState.DEAD:
		return
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		if (u as Node2D).global_position.distance_to(pos) <= 170.0:
			deal_damage_to(u, dmg, "physical_melee", "")


## 闻声吐息：朝最后声点吐尘；放完自聋 2.5 秒
func _cast_breath(def: Dictionary) -> void:
	_reset_visual()
	_update_facing_to_target()
	var dmg := attack_power * float(def.get("damage_scale", 0.80)) * _damage_multiplier()
	SkillFx.play_at_strike(self, "skill_shihou_breath",
		{"range": 560.0, "angle": 60.0}, facing)
	_show_enemy_float("闻声吐息", Color(0.78, 0.92, 1.0))
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		var to_u: Vector2 = (u as Node2D).global_position - global_position
		if to_u.length() > 560.0:
			continue
		if to_u.length() > 1.0:
			var diff := absf(rad_to_deg(wrapf(to_u.angle() - facing.angle(), -PI, PI)))
			if diff > 30.0:
				continue
		deal_damage_to(u, dmg, "elemental", "wind")
	_deaf_left = DEAF_BREATH
	_shihou_core_done(def)


## 石尾扫：贴背时的 360° 扫尾
func _cast_tail(def: Dictionary) -> void:
	_reset_visual()
	_update_facing_to_target()
	var dmg := attack_power * float(def.get("damage_scale", 0.70)) * _damage_multiplier()
	SkillFx.play_at_strike(self, "skill_shihou_tail",
		{"range": 240.0, "angle": 360.0}, facing)
	_hit_circle(240.0, dmg, "physical_melee", "")
	_shihou_core_done(def)


# ===================== 承伤 / 杂项 =====================
func take_damage(amount: float, source: Node = null,
		damage_kind: String = "physical", element: String = "",
		from_projectile: bool = false) -> void:
	if _vuln_left > 0.0:
		amount *= STELE_VULN_MULT
	super(amount, source, damage_kind, element, from_projectile)


func _die() -> void:
	_dash_left = 0.0
	for raw in _steles:
		var st: Dictionary = raw
		if is_instance_valid(st.get("node", null)):
			(st["node"] as Node).queue_free()
	_steles.clear()
	super._die()
