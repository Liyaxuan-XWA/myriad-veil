class_name ZhujiCoreStag
extends WorldEnemy
## 云隐谷核心首领「云隐苍角」（2026-10-29）
##
## 机制：三片苔甲悬在角侧 → 甲在时受伤 -42%；三片各吃三次攻击，弹反角撞/角扫也能碎甲。
## 三片尽碎后护甲消失并短暂踉跄。
## 血量过半进入二阶段：每 12 秒雾隐一次 —— 真身藏在三团雾影里，只有角尖冷蓝光可认；
## 命中真身（任意伤害）会立刻识破，未识破 2.4 秒后谷心雾爆。
## 八式：角撞/踏地/雾吐/古根/落石/角扫（一阶段）+ 雾步/鹿鸣（二阶段）。

const PLATE_COUNT := 3
## 三片分别挂在左肩、右肩、胸前——都落在鹿角轮廓之外，不会藏进角枝里
const PLATE_ANCHORS: Array[Vector2] = [
	Vector2(-112.0, -100.0), Vector2(112.0, -100.0), Vector2(0.0, -24.0),
]
const ARMOR_REDUCTION := 0.58
const MIST_DURATION := 2.4
const MIST_COOLDOWN := 12.0
const MIST_BURST_RADIUS := 260.0
const MIST_BURST_COEF := 0.80

var _plates: Array = []
var _plate_time := 0.0
var _armor_broken := false
var _mist_hidden := false
var _mist_left := 0.0
var _mist_cd := 0.0
var _mist_echoes: Array = []
var _mist_marker: Sprite2D = null


func _ready() -> void:
	super()
	_spawn_plates()


func _physics_process(delta: float) -> void:
	if phase == 2 and not _mist_hidden:
		_mist_cd = maxf(0.0, _mist_cd - delta)
	if _mist_hidden:
		_mist_left -= delta
		if _mist_left <= 0.0:
			_burst_mist()
	elif phase == 2 and _mist_cd <= 0.0 \
			and (state == BossState.IDLE or state == BossState.CHASE):
		_begin_mist()
	super(delta)
	_update_plates(delta)


func _tick_state(delta: float) -> void:
	if _mist_hidden:
		velocity = Vector2.ZERO
		return
	super(delta)


func _enter_phase_two() -> void:
	super()
	_mist_cd = 5.0
	_show_enemy_float("雾隐·真形", Color(0.62, 0.90, 1.0))


func _die() -> void:
	_clear_mist_fx()
	for p in _plates:
		if is_instance_valid(p):
			(p as Node).queue_free()
	_plates.clear()
	super._die()


func _exit_tree() -> void:
	_clear_mist_fx()


# ===================== 苔甲 =====================

## 受击球沿身体横向铺开、并压到脚底平面：
## 贴图是侧视的，脚底原点才是俯视碰撞面；球留在 -100 以上会让侧面平A打空。
func hit_spheres() -> Array:
	return [
		Vector3(-52.0, 0.0, 52.0),
		Vector3(0.0, 0.0, 58.0),
		Vector3(52.0, 0.0, 52.0),
	]


func _spawn_plates() -> void:
	for i in PLATE_COUNT:
		var plate := StagPlate.new()
		plate.top_level = true
		plate.slot = i
		plate.setup()
		add_child(plate)
		plate.broken.connect(_on_plate_broken)
		_plates.append(plate)
	_update_plates(0.0)


func _update_plates(delta: float) -> void:
	_plate_time += delta
	for p in _plates:
		if not is_instance_valid(p):
			continue
		var slot: int = clampi(p.slot, 0, PLATE_ANCHORS.size() - 1)
		var bob := sin(_plate_time * 1.5 + float(slot) * 2.1) * 3.5
		p.global_position = global_position + PLATE_ANCHORS[slot] + Vector2(0.0, bob)


func _on_plate_broken(plate: StagPlate) -> void:
	_plates.erase(plate)
	StagFx.play_plate_break(get_parent(), plate.global_position)
	if _plates.is_empty() and not _armor_broken:
		_armor_broken = true
		stag_break_armor()


func stag_break_armor() -> void:
	_show_enemy_float("苔甲尽碎·护甲崩解", Color(0.62, 0.94, 0.62))
	stagger_for(0.8)


## 弹反角撞/角扫：震碎离玩家最近的一片苔甲（不按剩余次数）
func on_parried(source: Node) -> void:
	if state == BossState.DEAD:
		return
	super(source)
	if not has_plates():
		return
	var best: StagPlate = null
	var best_d := INF
	for raw in _plates:
		var p := raw as StagPlate
		if p == null or not is_instance_valid(p):
			continue
		var d := INF
		if source != null and is_instance_valid(source) and source is Node2D:
			d = p.global_position.distance_squared_to((source as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = p
	if best != null:
		best.shatter()


func has_plates() -> bool:
	return not _armor_broken and not _plates.is_empty()


func damage_taken_multiplier(_damage_kind: String) -> float:
	var m := super(_damage_kind)
	if has_plates():
		m *= ARMOR_REDUCTION
	return m


# ===================== 雾隐 =====================

func _begin_mist() -> void:
	if _mist_hidden or phase != 2:
		return
	_mist_hidden = true
	_mist_left = MIST_DURATION
	_mist_cd = MIST_COOLDOWN
	state = BossState.IDLE
	state_timer = 0.3
	velocity = Vector2.ZERO
	anim.modulate = Color(1.0, 1.0, 1.0, 0.42)
	StagFx.play_mist_enter(get_parent(), global_position)
	_show_enemy_float("雾隐·寻真", Color(0.62, 0.90, 1.0))
	_spawn_mist_echoes()


func _spawn_mist_echoes() -> void:
	_clear_mist_fx()
	var render := skin.render_node as Sprite2D if skin != null else null
	if render != null and render.texture != null:
		# 朝向只写在 Visual.scale.x 上，影子要跟着本体翻，否则「朝左的本体 + 朝右的雾影」会一眼露馅
		var face_x := signf(anim.scale.x) if anim != null and absf(anim.scale.x) > 0.001 else 1.0
		var fog_mat := ShaderMaterial.new()
		fog_mat.shader = load("res://assets/shaders/mist_silhouette.gdshader")
		for i in 3:
			var echo := Sprite2D.new()
			echo.texture = render.texture
			echo.centered = render.centered
			echo.flip_h = render.flip_h
			echo.scale = Vector2(
				render.scale.x * skin.scale.x * face_x, render.scale.y * skin.scale.y)
			echo.material = fog_mat
			echo.z_index = z_index - 1
			get_parent().add_child(echo)
			echo.global_position = global_position + Vector2(
				(float(i) - 1.0) * 150.0, -34.0 + float(i % 2) * 22.0)
			_mist_echoes.append(echo)
	# 真身角尖冷蓝光：贴在头顶上方，跟随 BOSS
	_mist_marker = Sprite2D.new()
	_mist_marker.texture = SkillFx.dot_texture()
	_mist_marker.centered = true
	_mist_marker.material = SkillFx.additive_material()
	_mist_marker.scale = Vector2(0.42, 0.42)
	_mist_marker.modulate = Color(0.55, 0.92, 1.0, 0.95)
	_mist_marker.z_index = z_index + 2
	get_parent().add_child(_mist_marker)
	_mist_marker.global_position = global_position + Vector2(0.0, -178.0)


func _clear_mist_fx() -> void:
	for e in _mist_echoes:
		if is_instance_valid(e):
			(e as Node).queue_free()
	_mist_echoes.clear()
	if _mist_marker != null and is_instance_valid(_mist_marker):
		_mist_marker.queue_free()
	_mist_marker = null


func _burst_mist() -> void:
	_reveal_mist(false)


func _reveal_mist(by_hit: bool) -> void:
	if not _mist_hidden:
		return
	_mist_hidden = false
	_mist_left = 0.0
	_mist_cd = MIST_COOLDOWN
	anim.modulate = Color.WHITE
	_clear_mist_fx()
	if by_hit:
		_show_enemy_float("识破雾隐", Color(0.62, 0.92, 1.0))
	else:
		StagFx.play_mist_burst(get_parent(), global_position, MIST_BURST_RADIUS)
		for u in attack_units():
			if u is Node2D and (u as Node2D).global_position.distance_to(global_position) <= MIST_BURST_RADIUS:
				deal_damage_to(u, attack_power * MIST_BURST_COEF, "elemental", "water")
				if u.has_method("apply_debuff"):
					u.call("apply_debuff", "lock_step", 1.5)
		_show_enemy_float("谷心雾爆", Color(0.62, 0.90, 1.0))


## 雾隐时被任何伤害命中：这次伤害作废，但会立刻识破
func take_damage(amount: float, source: Node = null, damage_kind: String = "physical",
		element: String = "", from_projectile: bool = false) -> void:
	if _mist_hidden:
		_reveal_mist(true)
		return
	super.take_damage(amount, source, damage_kind, element, from_projectile)


# ===================== 八式 =====================

func _cast_core_skill() -> void:
	var def := _next_core_skill
	if def.is_empty():
		super()
		return
	match String(def.get("id", "")):
		"stag_mist":
			_cast_mist_breath(def)
		"stag_roots":
			_cast_roots(def)
		"stag_miststep":
			_cast_miststep(def)
		"stag_roar":
			_cast_roar(def)
		_:
			super()


func _stag_core_done(def: Dictionary) -> void:
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


func _cast_mist_breath(def: Dictionary) -> void:
	_reset_visual()
	_update_facing_to_target()
	var form := MoveDB.resolve_boss("form_slash_single")
	if form.is_empty():
		_stag_core_done(def)
		return
	var dmg := attack_power * float(def.get("damage_scale", 0.65)) * _damage_multiplier()
	_play_form(form, dmg, "elemental", "water",
		float(def.get("range", 300.0)), float(def.get("angle", 90.0)),
		String(def.get("fx_id", "")))
	# 雾吐覆盖的扇形内挂滞气：灵力停止回复 + 轻减速
	for u in attack_units():
		if not (u is Node2D):
			continue
		var to_u: Vector2 = (u as Node2D).global_position - global_position
		if to_u.length() > 300.0:
			continue
		if to_u.length() > 0.5 and absf(rad_to_deg(wrapf(to_u.angle() - facing.angle(), -PI, PI))) > 49.0:
			continue
		if u.has_method("apply_debuff"):
			u.call("apply_debuff", "qi_stagnation", 3.0)
	_stag_core_done(def)


func _cast_roar(def: Dictionary) -> void:
	_reset_visual()
	_update_facing_to_target()
	var form := MoveDB.resolve_boss("form_smash")
	if form.is_empty():
		_stag_core_done(def)
		return
	var dmg := attack_power * float(def.get("damage_scale", 1.0)) * _damage_multiplier()
	_play_form(form, dmg, "elemental", "wood",
		float(def.get("range", 340.0)), 360.0, String(def.get("fx_id", "")))
	StagFx.play_roar(get_parent(), global_position, float(def.get("range", 340.0)))
	for u in attack_units():
		if u is Node2D and (u as Node2D).global_position.distance_to(global_position) <= 340.0:
			if u.has_method("apply_debuff"):
				u.call("apply_debuff", "lock_step", 1.0)
	_stag_core_done(def)


func _cast_roots(def: Dictionary) -> void:
	_reset_visual()
	_update_facing_to_target()
	var pos := global_position + facing * 120.0
	if target != null and is_instance_valid(target):
		pos = (target as Node2D).global_position
	StagFx.play_root_warn(get_parent(), pos, 130.0)
	_stag_core_done(def)
	var tree := get_tree()
	if tree != null:
		tree.create_timer(0.7, true).timeout.connect(
			_roots_land.bind(pos, float(def.get("damage_scale", 0.55))))


func _roots_land(pos: Vector2, scale: float) -> void:
	if not is_inside_tree() or state == BossState.DEAD:
		return
	StagFx.play_root_burst(get_parent(), pos, 130.0)
	for u in attack_units():
		if not (u is Node2D):
			continue
		if (u as Node2D).global_position.distance_to(pos) > 130.0:
			continue
		deal_damage_to(u, attack_power * scale * _damage_multiplier(), "elemental", "wood")
		if u.has_method("apply_debuff"):
			u.call("apply_debuff", "rooted", 1.2)


func _cast_miststep(def: Dictionary) -> void:
	_reset_visual()
	if target == null or not is_instance_valid(target):
		_stag_core_done(def)
		return
	var tp: Vector2 = (target as Node2D).global_position
	var side := facing.orthogonal() * (1.0 if randf() < 0.5 else -1.0)
	var old := global_position
	global_position = tp + side * 150.0
	_clamp_to_arena()
	StagFx.play_miststep(get_parent(), old, global_position)
	_update_facing_to_target()
	var form := MoveDB.resolve_boss("form_blade_dash")
	if not form.is_empty():
		var dmg := attack_power * float(def.get("damage_scale", 0.70)) * _damage_multiplier()
		_play_form(form, dmg, "elemental", "water",
			float(def.get("range", 240.0)), float(def.get("angle", 100.0)),
			String(def.get("fx_id", "")))
	_stag_core_done(def)
