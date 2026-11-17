class_name DomainBoss04
extends BossBase
## 照影界第 1 位 · 镜主「观澜」—— 镜身 · 照影（2026-11-01）
##
## 场上只有一名真身 + 2（P2 3）名镜像。真身脚下有倒影，镜像没有。
## 镜像 1 击碎、会周期性斩向玩家；换镜后真身暴露 1.2 秒（受伤 +20%）。
## 没有势条 / 资源条 / 叠层兑现：破法是看倒影、打真身、碎镜像、躲镜返与水镜环。
## 首战空手可破：任意物理 / 术法命中都能打碎镜像或打真身，不需要本关功法。

const F_SLASH := "form_mirror_slash"
const F_THRUST := "form_mirror_thrust"
const F_BLOOM := "form_mirror_bloom"
const F_SHATTER := "form_mirror_shatter"
const F_SWAP := "form_mirror_swap"
const F_RETURN := "form_mirror_return"
const F_RING := "form_mirror_ring"
const F_MYRIAD := "form_mirror_myriad"

const SCORED: Array = [F_SLASH, F_THRUST, F_RING]

const EXPOSE_TIME := 1.2
const RETURN_TIME := 1.2
const MAX_IMAGES_P1 := 2
const MAX_IMAGES_P2 := 3
const RIG_SCRIPT := "res://scripts/visual/boss_rig_guanying.gd"
const RIG_DATA := "res://assets/characters/boss/guanying_rig/rig.tres"

var _phase_two: bool = false
var _cools: Dictionary = {}
var _recent: Array = []
var _decide_wait: float = 0.0
var _current_skill: String = ""
var _images: Array = []
var _exposed_left: float = 0.0
var _return_left: float = 0.0
var _reflection: Sprite2D = null
var _waterline: Sprite2D = null
var _ring: MirrorRingField = null


func _setup() -> void:
	boss_id = "boss_04"
	_phase_two = false
	_cools.clear()
	_recent.clear()
	_images.clear()
	_exposed_left = 0.0
	_return_left = 0.0
	_decide_wait = 0.0
	_ring = null
	_build_reflection()


func _set_facing(dir: Vector2) -> void:
	super._set_facing(dir)
	# 倒影是独立 Sprite2D，不跟 Visual.scale 翻转；手动跟朝向，否则真身掉头后倒影还是反的
	if _reflection != null and is_instance_valid(_reflection):
		_reflection.flip_h = dir.x < 0.0


func _build_reflection() -> void:
	var vid := "boss_guanying"
	if skin != null and String(skin.visual_id) != "":
		vid = String(skin.visual_id)
	var cfg := ArtDB.get_visual(vid)
	var tex: Texture2D = null
	var sc := Vector2(0.25, 0.25)
	if not cfg.is_empty():
		var tp := String(cfg.get("texture", ""))
		if tp != "" and ResourceLoader.exists(tp):
			tex = load(tp)
		var raw = cfg.get("scale", Vector2(0.25, 0.25))
		if raw is Vector2:
			sc = raw
	if tex == null and skin != null:
		tex = skin.current_texture()
	if tex == null:
		return
	_reflection = Sprite2D.new()
	_reflection.name = "GroundReflection"
	_reflection.texture = tex
	_reflection.centered = true
	_reflection.flip_v = true
	_reflection.scale = sc
	_reflection.position = Vector2(0.0, tex.get_height() * sc.y * 0.5)
	_reflection.modulate = Color(0.70, 0.88, 1.0, 0.32)
	_reflection.z_index = -1
	add_child(_reflection)
	# 脚下的一道水光：把「这是水面倒影」和「镜像没有倒影」分开
	var water := Sprite2D.new()
	water.name = "ReflectionWaterline"
	water.texture = SkillFx.dot_texture()
	water.centered = true
	water.material = SkillFx.additive_material()
	water.scale = Vector2(2.6, 0.12)
	water.position = Vector2(0.0, 1.0)
	water.modulate = Color(0.58, 0.86, 1.0, 0.30)
	water.z_index = -1
	_waterline = water
	add_child(water)


func _physics_process(delta: float) -> void:
	if state == BossState.DEAD:
		return
	_prune_images()
	_tick_reflection(delta)
	super._physics_process(delta)


func _tick_cooldowns(delta: float) -> void:
	for sid in _cools.keys():
		if float(_cools[sid]) > 0.0:
			_cools[sid] = maxf(0.0, float(_cools[sid]) - delta)
	if _decide_wait > 0.0:
		_decide_wait = maxf(0.0, _decide_wait - delta)
	if _exposed_left > 0.0:
		_exposed_left = maxf(0.0, _exposed_left - delta)
	if _return_left > 0.0:
		_return_left = maxf(0.0, _return_left - delta)
	if _ring != null and not is_instance_valid(_ring):
		_ring = null


func _tick_reflection(delta: float) -> void:
	if _reflection == null or not is_instance_valid(_reflection):
		return
	var pulse := 0.22 + 0.10 * sin(Time.get_ticks_msec() * 0.006)
	if _exposed_left > 0.0:
		pulse = 0.48 + 0.18 * sin(Time.get_ticks_msec() * 0.02)
	_reflection.modulate = Color(0.64, 0.82, 1.0, pulse)


func damage_taken_multiplier(_damage_kind: String) -> float:
	return 1.20 if _exposed_left > 0.0 else 1.0


func _max_images() -> int:
	return MAX_IMAGES_P2 if phase >= 2 else MAX_IMAGES_P1


func _on_chase_reached(_dist: float) -> void:
	_choose()


func _choose() -> void:
	if state != BossState.IDLE and state != BossState.CHASE:
		return
	if _decide_wait > 0.0:
		return
	_decide_wait = 0.28
	_prune_images()
	var p := target
	if p == null or BossBase.is_unit_dead(p):
		return
	var d := _dist()

	if _images.size() < _max_images() and _ready_cd(F_BLOOM):
		_begin(F_BLOOM)
		return
	if phase >= 2 and _images.size() >= 2 and _ready_cd(F_MYRIAD) and d <= 520.0:
		_begin(F_MYRIAD)
		return
	if not _images.is_empty() and _ready_cd(F_SWAP) \
			and (d > 330.0 or current_hp < max_hp * 0.3):
		_begin(F_SWAP)
		return
	var attacking = p.get("is_attacking")
	if d <= 200.0 and _ready_cd(F_RETURN) and attacking is bool and attacking:
		_begin(F_RETURN)
		return
	if d <= 240.0 and _ready_cd(F_RING):
		_begin(F_RING)
		return
	var pool := SCORED.duplicate()
	if not _images.is_empty():
		pool.append(F_SHATTER)
		pool.append(F_SWAP)
	var best := ""
	var best_score := -999.0
	for sid in pool:
		if not _ready_cd(String(sid)) or not _in_reach(String(sid)):
			continue
		var sc := _score(String(sid)) + randf() - _repeat_penalty(String(sid))
		if sc > best_score:
			best_score = sc
			best = String(sid)
	if best == "":
		state = BossState.CHASE
		return
	_begin(best)


func _ready_cd(sid: String) -> bool:
	return float(_cools.get(sid, 0.0)) <= 0.0


func _in_reach(sid: String) -> bool:
	_prune_images()
	var d := _dist()
	match sid:
		F_SLASH: return d <= 220.0
		F_THRUST: return d >= 90.0 and d <= 380.0
		F_SHATTER: return not _images.is_empty() and d <= 380.0
		F_RING: return d <= 280.0
		F_MYRIAD: return d <= 520.0
	return true


func _score(sid: String) -> float:
	var d := _dist()
	match sid:
		F_SLASH: return 3.0 - absf(d - 110.0) / 180.0
		F_THRUST: return 2.5 - absf(d - 260.0) / 260.0
		F_SHATTER: return 2.0 - absf(d - 200.0) / 260.0
		F_RING: return 2.2 - absf(d - 150.0) / 220.0
		F_MYRIAD: return 3.0
	return 0.5


func _repeat_penalty(sid: String) -> float:
	if _recent.size() >= 2 and String(_recent[0]) == sid and String(_recent[1]) == sid:
		return 99.0
	if not _recent.is_empty() and String(_recent[0]) == sid:
		return 2.0
	return 0.0


func _record(sid: String) -> void:
	if sid == "":
		return
	_recent.push_front(sid)
	if _recent.size() > 3:
		_recent.resize(3)
	var b := MoveDB.resolve_boss(sid)
	var cd := float(b.get("cooldown_p1", 8.0))
	if phase >= 2:
		cd = float(b.get("cooldown_p2", cd))
	_cools[sid] = cd


func _begin(sid: String) -> void:
	if is_skill_locked():
		return
	_current_skill = sid
	state = BossState.WINDUP
	var b := MoveDB.resolve_boss(sid)
	var windup := maxf(0.2, float(b.get("windup", 0.7)))
	if phase >= 2:
		windup *= float(b.get("windup_mult_p2", 1.0))
	state_timer = windup
	# 面向仇恨目标：正常战斗是玩家，召唤法宝召来的观澜是敌方 BOSS
	var focus := target
	if focus == null or not is_instance_valid(focus):
		focus = _player_node()
	if focus != null:
		_set_facing(((focus as Node2D).global_position - global_position).normalized())
	_play_form_anim(sid, state_timer + 0.15)
	show_skill_line(String(b.get("form_name", "")), windup + 0.1, 18, 250.0,
		BossBase.skill_name_color(String(b.get("attack_kind", ""))), -190.0)


func _fire_attack() -> void:
	state = BossState.ATTACK
	state_timer = 0.15
	var b := MoveDB.resolve_boss(_current_skill)
	if b.is_empty():
		_finish_skill()
		return
	match _current_skill:
		F_SLASH: _cast_slash(b)
		F_THRUST: _cast_thrust(b)
		F_BLOOM: _cast_bloom(b)
		F_SHATTER: _cast_shatter(b)
		F_SWAP: _cast_swap(b)
		F_RETURN: _cast_return(b)
		F_RING: _cast_ring(b)
		F_MYRIAD: _cast_myriad(b)
		_: _finish_skill()


func _finish_skill() -> void:
	_record(_current_skill)
	_current_skill = ""
	state = BossState.RECOVER
	state_timer = 0.45


func _cast_slash(b: Dictionary) -> void:
	var dmg := MoveDB.boss_damage(F_SLASH, attack_power, phase)
	SkillFx.play_at_strike(self, "skill_mirror_slash", b, facing)
	_deal_cone(float(b.get("range", 150.0)), float(b.get("angle", 110.0)),
		dmg, String(b.get("attack_kind", "physical_melee")), "")
	_mimic_images(F_SLASH, dmg)
	_finish_skill()


func _cast_thrust(b: Dictionary) -> void:
	var dmg := MoveDB.boss_damage(F_THRUST, attack_power, phase)
	SkillFx.play_at_strike(self, "skill_mirror_thrust", b, facing)
	_deal_line(float(b.get("range", 280.0)), float(b.get("width", 54.0)),
		dmg, String(b.get("attack_kind", "physical_melee")), "")
	_mimic_images(F_THRUST, dmg)
	_finish_skill()


func _cast_bloom(b: Dictionary) -> void:
	_prune_images()
	var need := _max_images() - _images.size()
	for i in maxi(0, need):
		_spawn_image(i)
	SkillFx.play_at_strike(self, "skill_mirror_bloom", b, facing)
	show_windup_line("镜花 · %d 影" % _images.size(), 0.8, 18, 220.0,
		Color(0.64, 0.86, 1.0), -186.0)
	_finish_skill()


func _cast_shatter(b: Dictionary) -> void:
	var img := _pick_image()
	if img == null:
		_finish_skill()
		return
	var pos: Vector2 = img.global_position
	img.call("take_damage", 0.0)
	var dmg := MoveDB.boss_damage(F_SHATTER, attack_power, phase)
	SkillFx.play_at_point(get_parent(), "skill_mirror_shatter", b, facing, pos, self)
	_deal_circle(pos, 110.0, dmg, "elemental", "water", "mirror_slow", 2.0)
	_mimic_images(F_SHATTER, dmg)
	_finish_skill()


func _cast_swap(b: Dictionary) -> void:
	var img := _pick_image()
	if img == null:
		_finish_skill()
		return
	var old := global_position
	var target_pos: Vector2 = img.global_position
	global_position = _clamp_point(target_pos)
	img.global_position = old
	_exposed_left = EXPOSE_TIME
	TreasureFx.play_swap(get_parent(), old, target_pos)
	show_windup_line("换镜 · 镜身暴露", 0.9, 18, 220.0,
		Color(0.72, 0.90, 1.0), -186.0)
	_finish_skill()


func _cast_return(b: Dictionary) -> void:
	_return_left = RETURN_TIME
	SkillFx.play_at_strike(self, "skill_mirror_return", b, facing)
	show_windup_line("镜返 · 近战止步", 0.8, 18, 220.0,
		Color(0.72, 0.90, 1.0), -186.0)
	_finish_skill()


func _cast_ring(b: Dictionary) -> void:
	var ring_dmg := MoveDB.boss_damage(F_RING, attack_power, phase)
	var field := MirrorRingField.new()
	# 水场按「施放者的阵营」结算：法宝召唤出来的观澜是友军，
	# 再写死 false 就会让玩家自己被自家镜湖泡着掉血（2026-11-02 用户报）
	field.setup(global_position, is_ally, 150.0, 3.0, ring_dmg, self,
		Color(0.64, 0.86, 1.0, 1.0))
	get_parent().add_child(field)
	_ring = field
	SkillFx.play_at_strike(self, "skill_mirror_ring", b, facing)
	_mimic_images(F_RING, ring_dmg)
	_finish_skill()


func _cast_myriad(b: Dictionary) -> void:
	var dmg := MoveDB.boss_damage(F_MYRIAD, attack_power, phase)
	SkillFx.play_at_strike(self, "skill_mirror_myriad", b, facing)
	_deal_cone(float(b.get("range", 180.0)), float(b.get("angle", 130.0)),
		dmg, String(b.get("attack_kind", "physical_melee")), "")
	_mimic_images(F_MYRIAD, dmg)
	_finish_skill()


func _spawn_image(index: int) -> MirrorImage:
	var cfg := ArtDB.get_visual("boss_guanying")
	var tex: Texture2D = null
	var sc := Vector2(0.25, 0.25)
	var off := Vector2(0.0, 5.0)
	if not cfg.is_empty():
		var tp := String(cfg.get("texture", ""))
		if tp != "" and ResourceLoader.exists(tp):
			tex = load(tp)
		var raw_sc = cfg.get("scale", sc)
		if raw_sc is Vector2:
			sc = raw_sc
		var raw_off = cfg.get("offset", off)
		if raw_off is Vector2:
			off = raw_off
	if tex == null and skin != null:
		tex = skin.current_texture()
	# 镜像从玩家四周站起，而不是围着本体：目的是逼玩家在近身范围里分辨真假
	var anchor := _player_actor()
	if anchor == null:
		anchor = self
	var total := float(maxi(_max_images(), 1))
	var ang := -PI * 0.5 + float(index) * TAU / total + randf_range(-0.26, 0.26)
	var radius := randf_range(96.0, 136.0)
	var pos := _clamp_point(anchor.global_position + Vector2(cos(ang), sin(ang)) * radius)
	var img := MirrorImage.new()
	var flip := (anchor.global_position.x - pos.x) < 0.0
	var faction := "ally_boss" if is_ally else "boss"
	# 敌方镜像必须像真身：用同一套 rig、几乎不透明的冷白调；唯一破绽是没有脚下倒影
	var tint := Color(0.76, 1.0, 0.84, 0.94) if is_ally else Color(0.96, 0.99, 1.0, 0.98)
	img.setup(self, faction, pos, tex, sc, off, tint, 0.50, 8.0, flip,
		RIG_SCRIPT, RIG_DATA)
	get_parent().add_child(img)
	img.global_position = pos
	_images.append(img)
	SkillFx.play_at_point(get_parent(), "skill_mirror_bloom",
		MoveDB.resolve_boss(F_BLOOM), Vector2.RIGHT, pos, self)
	return img


func _player_actor() -> Node2D:
	if team_id >= 0:
		return focus_node()
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p != null and is_instance_valid(p):
		return p
	return _player_node()


## 本体出招后，场上镜像跟着复读同一式；镜像自己的伤害在 MirrorImage 里按 50% 结算
func _mimic_images(sid: String, source_damage: float) -> void:
	_prune_images()
	for raw in _images:
		if is_instance_valid(raw):
			raw.call("mimic_skill", sid, source_damage)


func _pick_image() -> MirrorImage:
	_prune_images()
	if _images.is_empty():
		return null
	return _images[0] as MirrorImage


func _prune_images() -> void:
	var keep: Array = []
	for raw in _images:
		if is_instance_valid(raw) and raw is MirrorImage and not bool(raw.call("is_dead")):
			keep.append(raw)
	_images = keep


func _deal_cone(reach: float, angle_deg: float, dmg: float, kind: String,
		elem: String) -> void:
	var dir := facing.normalized()
	var half := deg_to_rad(angle_deg * 0.5)
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		var to: Vector2 = (u as Node2D).global_position - global_position
		var d := to.length()
		if d > reach + 18.0:
			continue
		if d > 1.0 and dir.dot(to / d) < cos(half):
			continue
		deal_damage_to(u, dmg, kind, elem)


func _deal_line(reach: float, width: float, dmg: float, kind: String,
		elem: String) -> void:
	var dir := facing.normalized()
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		var to: Vector2 = (u as Node2D).global_position - global_position
		var forward := to.dot(dir)
		if forward < -12.0 or forward > reach + 18.0:
			continue
		var lateral := absf(to.cross(dir))
		if lateral > width * 0.5 + 18.0:
			continue
		deal_damage_to(u, dmg, kind, elem)


func _deal_circle(pos: Vector2, radius: float, dmg: float, kind: String,
		elem: String, debuff_id: String = "", debuff_time: float = 0.0) -> void:
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		if (u as Node2D).global_position.distance_to(pos) > radius + 18.0:
			continue
		deal_damage_to(u, dmg, kind, elem)
		if debuff_id != "" and u.has_method("apply_debuff"):
			u.call("apply_debuff", debuff_id, debuff_time)


func _player_node() -> Node2D:
	if target != null and is_instance_valid(target):
		return target
	return null


func _dist() -> float:
	var p := _player_node()
	return global_position.distance_to(p.global_position) if p != null else 9999.0


func _clamp_point(pos: Vector2) -> Vector2:
	if arena_half_extents == Vector2.ZERO:
		return pos
	return Vector2(
		clampf(pos.x, -arena_half_extents.x + 56.0, arena_half_extents.x - 56.0),
		clampf(pos.y, -arena_half_extents.y + 56.0, arena_half_extents.y - 56.0))


func take_damage(amount: float, source: Node = null, damage_kind: String = "physical",
		element: String = "", from_projectile: bool = false) -> void:
	if state == BossState.DEAD:
		return
	if _return_left > 0.0 and damage_kind == "physical":
		# 玩家的物理投射物把 projectile 当 source 传进来，真正攻击者在它的 source 字段里
		var attacker: Node = source
		if attacker != null and is_instance_valid(attacker):
			var raw = attacker.get("source")
			if is_instance_valid(raw) and raw is Node:
				attacker = raw as Node
		if attacker != null and is_instance_valid(attacker) and attacker is Node2D:
			var victim: Node = null
			if is_ally:
				# 召唤法宝召来的观澜：镜返把敌方 BOSS 的物理伤害弹回去
				if attacker is BossBase and attacker != self and attacker.is_in_group("boss"):
					victim = attacker
			elif attacker.is_in_group("player"):
				victim = attacker
			if victim != null:
				_return_left = 0.0
				if is_ally:
					victim.call("take_damage", amount * 0.35, self, "elemental", "water", false)
				else:
					victim.call("take_damage", amount * 0.35, "elemental", self, "water")
				SkillFx.play_at_strike(self, "skill_mirror_return",
					MoveDB.resolve_boss(F_RETURN), facing)
				show_windup_line("镜返 · 反弹", 0.6, 16, 200.0,
					Color(0.72, 0.90, 1.0), -180.0)
				return
	super.take_damage(amount, source, damage_kind, element, from_projectile)


func _die() -> void:
	# 倒影 / 水光 / 水镜环不在 Visual 下，不能让它们比 BOSS 活得久
	if _ring != null and is_instance_valid(_ring):
		_ring.queue_free()
	_ring = null
	for raw in _images:
		if is_instance_valid(raw):
			raw.queue_free()
	_images.clear()
	for n in [_reflection, _waterline]:
		var sp := n as Sprite2D
		if sp != null and is_instance_valid(sp):
			var tw := create_tween()
			tw.tween_property(sp, "modulate:a", 0.0, 0.5)
	super._die()


func _on_phase_two() -> void:
	_phase_two = true
	_prune_images()
	show_windup_line("镜面碎了，倒影还在", 1.0, 20, 240.0,
		Color(0.72, 0.90, 1.0), -190.0)
	if _images.size() < _max_images():
		_spawn_image(_images.size())
	_cools[F_MYRIAD] = 3.0
