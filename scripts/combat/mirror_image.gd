class_name MirrorImage
extends Node2D
## 照影界「镜身」共享镜像（2026-11-01）
##
## 双方共用，但两边走的是两套复读：
##   · BOSS 镜像 —— `mimic_skill()`：观澜出招时同帧复读同一式，伤害 ×0.5，不消散；
##     另外每 2.4 秒向玩家补一记镜影斩。
##   · 玩家镜像 —— `cast_echo()`：玩家每放一次功法（镜花 / 万镜除外），场上**所有**镜像
##     同时跟着使出同一招（以镜像自己的位置算命中、伤害为本体一半），放完立刻消散 ——
##     不看有没有打中。
## 镜像只有 1 点血，任何物理命中即碎（BOSS 侧镜像免疫法术）；它们**没有脚下倒影**，
## 真身有 —— 这是唯一辨识依据。
## 不是势条，不叠层，不攒伤害引爆：镜像只是一次性的场压/诱饵。

const BOSS_ECHO_INTERVAL := 2.4
const BOSS_ECHO_RANGE := 165.0

## 镜像「亲自放招」要生成的玩家投射物（与 player.gd 同一份场景）
const PLAYER_PROJECTILE_SCENE := "res://scenes/combat/player_projectile.tscn"
## 弹体 / 特效的出手点：镜像自己的身体中心
const ECHO_CENTER := Vector2(0.0, -34.0)
## 万剑归宗的飞剑：侧向出鞘角与弧线转向速度（与 player.gd 的同名常量同值）
const MYRIAD_SIDE_ANGLE := 65.0
const MYRIAD_TURN_SPEED := 200.0

## 玩家侧共享数值（功法库文案直接读这些常量，改一处两边一起变）
const MAX_IMAGES := 2
## 被动「照影」额外抬高的镜像上限
const PASSIVE_EXTRA_IMAGES := 1
const IMAGE_LIFE := 10.0
## 镜像复读的伤害倍率：本体这招的一半
const ECHO_RATIO := 0.5
const RETURN_TIME := 1.2
## 镜返（玩家侧）：挡下**法术**并按原伤害 100% 反弹（2026-11-01 用户改版）
const RETURN_RATIO := 1.0
const SWAP_IFRAMES := 0.6
const SHATTER_RADIUS := 110.0
const SLOW_TIME := 2.0
const RING_RADIUS := 150.0
const RING_DURATION := 4.0
const PASSIVE_CD := 8.0

## 镜像复读本体招式时的动画 / 特效映射；伤害统一 ×0.5
const MIMIC_DAMAGE := 0.5
const MIMIC_ANIM := {
	"form_mirror_slash": "slash",
	"form_mirror_thrust": "thrust",
	"form_mirror_shatter": "shatter",
	"form_mirror_ring": "ring",
	"form_mirror_myriad": "myriad",
}
const MIMIC_FX := {
	"form_mirror_slash": "skill_mirror_slash",
	"form_mirror_thrust": "skill_mirror_thrust",
	"form_mirror_shatter": "skill_mirror_shatter",
	"form_mirror_ring": "skill_mirror_ring",
	"form_mirror_myriad": "skill_mirror_myriad",
}

var owner_unit: Node2D = null
## 战报台账用的两个字段（MirrorImage 不是 BossBase，所以要自己声明一份；
## 读侧 `BossBase._report_field()` 先认脚本属性、再看 meta，两种写法都接得住）。
## report_owner 非空 ⇒ 这一笔钱并进主人名下；report_tag 非空 ⇒ 记在哪一行。
var report_owner: Node = null
var report_tag: String = ""
## 玩家投射物场景的静态缓存（所有镜像共用一次 load）
static var _proj_scene: PackedScene = null
var faction: String = "boss"          # boss / player / ally_boss
var is_ally: bool = false             # 玩家侧/召唤 BOSS 的镜像进 ally_summon，供敌方 AoE 扫到
## 队伍号：从本体继承。棋局里镜像必须和真身同队，否则 `_team_enemy_units()`
## 永远选不到它 —— 对方棋子既打不碎镜像，镜像也认不出该打谁。
var team_id: int = -1
var max_hp: float = 1.0
var hp: float = 1.0
var lifetime: float = 8.0
var echo_ratio: float = 0.5
var tint: Color = Color(0.72, 0.84, 1.0, 0.58)
var echo_kind: String = "physical_melee"
var echo_element: String = "water"

var _age: float = 0.0
var _echo_timer: float = 0.9
var _dead: bool = false
var _spr: Sprite2D = null
var _rig: Node2D = null
var _visual_h: float = 180.0
var _base_offset: Vector2 = Vector2.ZERO
var _base_scale: Vector2 = Vector2.ONE
var _move_target: Vector2 = Vector2.INF
var _wander_left: float = 0.0
var _moving: bool = false
var _face_left: bool = false
var _bob_phase: float = 0.0
var _anim_name: String = ""
## >0 = 这一剑已经出手但还在空中（一剑开天的巨剑挂在本节点身上，必须活到落地）
var _echo_hold_left: float = 0.0
var _fake_fill: ColorRect = null
var _skill_anim_left: float = 0.0
var _immune_cd: float = 0.0
var _base_tint: Color = Color.WHITE
var _phase_red: bool = false
const FAKE_BAR_W := 64.0


func setup(p_owner: Node2D, p_faction: String, pos: Vector2, tex: Texture2D,
		p_scale: Vector2, p_offset: Vector2, p_tint: Color, p_echo_ratio: float,
		p_lifetime: float = 8.0, p_flip_h: bool = false,
		p_rig_script: String = "", p_rig_data: String = "") -> void:
	owner_unit = p_owner
	# 战报：镜像的钱并进主人名下（用户拍定「召唤物不单独列」）。
	# 行名不写在这里 —— 每一次复读在 cast_echo 里按**那一招**的名字单独盖戳，
	# 所以表上出现的是「观澜 · 剑意斩」这种真实读数，而不是一个笼统的"镜像"。
	report_owner = p_owner
	faction = p_faction
	global_position = pos
	tint = p_tint
	echo_ratio = p_echo_ratio
	lifetime = maxf(0.5, p_lifetime)
	is_ally = faction == "player" or faction == "ally_boss"
	team_id = BossBase.unit_team(p_owner)
	_base_scale = p_scale
	_base_offset = p_offset
	_base_tint = p_tint
	_face_left = p_flip_h
	_bob_phase = randf() * TAU
	# BOSS 镜像优先用真身的骨骼 + 两张分件，保证和本体同姿势、同体型；
	# 拿不到 rig 才退回定妆图，至少不会静悄悄变回一张平面图。
	if not _build_rig(p_rig_script, p_rig_data, p_scale, p_offset, p_tint, p_flip_h):
		_build_sprite(tex, p_scale, p_offset, p_tint, p_flip_h)
	if faction == "boss" or faction == "ally_boss":
		_build_fake_hp_bar()
	_sync_phase_tint(true)
	add_to_group("mirror_image")
	add_to_group("ally_summon" if is_ally else "boss")
	# 棋局身份：只有带队伍号才入 match_piece，单打的镜像不该被当成棋子
	if team_id >= 0:
		add_to_group(BossBase.MATCH_PIECE_GROUP)


func _build_sprite(tex: Texture2D, p_scale: Vector2, p_offset: Vector2,
		p_tint: Color, p_flip_h: bool) -> void:
	_spr = Sprite2D.new()
	_spr.centered = true
	_spr.texture = tex
	_spr.scale = p_scale
	_spr.position = p_offset
	_spr.flip_h = p_flip_h
	_spr.modulate = p_tint
	_spr.z_index = 5
	add_child(_spr)
	if tex != null:
		_visual_h = float(tex.get_height()) * absf(p_scale.y)
	var rim := Sprite2D.new()
	rim.centered = true
	rim.texture = TreasureFx.soft_ring_texture()
	rim.scale = Vector2(0.22, 0.22)
	rim.position = Vector2(0.0, -36.0)
	rim.modulate = Color(0.62, 0.86, 1.0, 0.10)
	rim.z_index = -1
	add_child(rim)


func _build_rig(script_path: String, data_path: String, p_scale: Vector2,
		p_offset: Vector2, p_tint: Color, p_flip_h: bool) -> bool:
	if script_path == "" or data_path == "" or not ResourceLoader.exists(script_path) \
			or not ResourceLoader.exists(data_path):
		return false
	var script := load(script_path) as Script
	if script == null:
		return false
	var node := script.new() as Node2D
	if node == null or not node.has_method("setup_from_path"):
		if node != null:
			node.free()
		return false
	if not bool(node.call("setup_from_path", data_path)):
		node.free()
		return false
	node.scale = p_scale
	node.position = p_offset
	node.modulate = p_tint
	add_child(node)
	_rig = node
	_visual_h = 720.0 * absf(p_scale.y)
	_face_left = p_flip_h
	_apply_visual_facing()
	if _rig.has_method("play_loop"):
		_rig.call("play_loop", "idle")
		_anim_name = "idle"
		# 三具镜像同时起步会像复制粘贴；把待机相位打散
		var ap := _rig.get_node_or_null("Anim") as AnimationPlayer
		if ap != null:
			ap.seek(randf() * 2.5, true)
	return true


## 假血条配色：棋局只认队伍号，不认 faction。
## ⚠ faction 由 is_ally 派生，而我方棋子的 is_ally 恒为 false ⇒ faction="boss"，
##   旧写法按它判色会让我方观澜的分身顶着敌方红（2026-11-07 用户报「我方的分身也显示红色」）。
##   棋子本体的血条走 BossBase.TEAM_HP_*，这里复用同一对常量，别另立一套色值。
##   team_id < 0（单打 / 塔 / 演武场 / 法宝召唤）沿用原来的 boss 红 / 友军绿，PvE 观感不变。
func _hp_bar_color() -> Color:
	var c: Color
	if team_id >= 0:
		c = BossBase.TEAM_HP_GREEN if team_id == 0 else BossBase.TEAM_HP_RED
	else:
		c = Color(0.86, 0.22, 0.22, 0.95) if faction == "boss" else Color(0.35, 0.92, 0.50, 0.95)
	c.a = 0.95
	return c


## 假血条：只靠倒影识真，不能让「头顶有没有血条」把真身卖了
func _build_fake_hp_bar() -> void:
	var bar := Control.new()
	bar.name = "FakeHPBar"
	bar.position = Vector2(-FAKE_BAR_W * 0.5, -_visual_h * 0.5 - 24.0)
	bar.size = Vector2(FAKE_BAR_W, 8.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.z_index = 20
	var bg := ColorRect.new()
	bg.size = Vector2(FAKE_BAR_W, 8.0)
	bg.color = Color(0.08, 0.08, 0.10, 0.82)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bg)
	_fake_fill = ColorRect.new()
	_fake_fill.size = Vector2(FAKE_BAR_W, 8.0)
	_fake_fill.color = _hp_bar_color()
	_fake_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_fake_fill)
	add_child(bar)


func _tick_fake_hp_bar() -> void:
	if _fake_fill == null or not is_instance_valid(_fake_fill):
		return
	# ⚠ 与 BossBase._update_head_hp_bar() 同口径：每帧重申队伍色，后续有人改色也能自愈
	_fake_fill.color = _hp_bar_color()
	if owner_unit == null or not is_instance_valid(owner_unit):
		return
	var cur = owner_unit.get("current_hp")
	var mx = owner_unit.get("max_hp")
	if cur == null or mx == null or float(mx) <= 0.0:
		return
	_fake_fill.size.x = FAKE_BAR_W * clampf(float(cur) / float(mx), 0.0, 1.0)


## 二阶段本体整身转红；镜像必须同步，否则红/白一眼分真假
func _sync_phase_tint(force: bool = false) -> void:
	if faction != "boss" and faction != "ally_boss":
		return
	if owner_unit == null or not is_instance_valid(owner_unit):
		return
	var red := int(owner_unit.get("phase")) >= 2
	if not force and red == _phase_red:
		return
	_phase_red = red
	var c := Color(1.0, 0.40, 0.40, _base_tint.a) if red else _base_tint
	if _rig != null and is_instance_valid(_rig):
		_rig.modulate = c
	elif _spr != null and is_instance_valid(_spr):
		_spr.modulate = c


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if _dead:
		return
	_immune_cd = maxf(0.0, _immune_cd - delta)
	_age += delta
	# 已经出手的这一剑优先：巨剑挂在本节点身上，先到期碎掉会把劈落中的剑一起带走
	if _echo_hold_left > 0.0:
		_echo_hold_left -= delta
		if _echo_hold_left <= 0.0:
			_shatter(true)
		return
	if _age >= lifetime:
		_shatter(false)
		return
	if owner_unit == null or not is_instance_valid(owner_unit):
		_shatter(false)
		return
	# ⚠ BossBase.is_dead 是方法，Player.is_dead 是变量；不能直接 Object.get 后 bool()
	var owner_dead := false
	if owner_unit.has_method("is_dead"):
		owner_dead = bool(owner_unit.call("is_dead"))
	else:
		var raw_dead = owner_unit.get("is_dead")
		if raw_dead is bool:
			owner_dead = raw_dead
	if owner_dead:
		_shatter(false)
		return
	_tick_motion(delta)
	if faction == "boss":
		_echo_timer -= delta
		if _echo_timer <= 0.0:
			_echo_timer = BOSS_ECHO_INTERVAL
			_boss_echo()
	elif faction == "ally_boss":
		_echo_timer -= delta
		if _echo_timer <= 0.0:
			_echo_timer = BOSS_ECHO_INTERVAL
			_ally_boss_echo()


## 镜像不能钉在原地当装饰：绕着玩家/主人慢慢换位，走路时播骨骼 walk
func _tick_motion(delta: float) -> void:
	var anchor := _motion_anchor()
	if anchor == null or not is_instance_valid(anchor):
		return
	_tick_fake_hp_bar()
	_sync_phase_tint()
	# 复读招式时站定，把骨骼动画完整放完；移动会打断出招
	if _skill_anim_left > 0.0:
		_skill_anim_left -= delta
		if _spr != null:
			_spr.position = _base_offset + Vector2(0.0,
				sin(Time.get_ticks_msec() * 0.004 + _bob_phase) * 1.1)
		return
	_wander_left -= delta
	if _wander_left <= 0.0 or not is_finite(_move_target.x):
		_wander_left = randf_range(1.0, 2.2)
		var ang := randf() * TAU
		var radius := randf_range(70.0, 135.0) if faction == "boss" else randf_range(52.0, 96.0)
		_move_target = _clamp_to_arena(anchor.global_position + Vector2(cos(ang), sin(ang)) * radius)
	var to := _move_target - global_position
	var moving := to.length() > 10.0
	if moving:
		var speed := 112.0 if faction == "player" else 82.0
		global_position = global_position.move_toward(_move_target, speed * delta)
		_set_visual_facing(to.x < 0.0)
	if _spr != null:
		var bob := sin(Time.get_ticks_msec() * 0.004 + _bob_phase) * (2.4 if moving else 1.1)
		_spr.position = _base_offset + Vector2(0.0, bob)
		_spr.rotation = sin(Time.get_ticks_msec() * 0.003 + _bob_phase) * 0.018
	if _rig != null and _rig.has_method("play_loop"):
		var want := "walk" if moving else "idle"
		if want != _anim_name:
			_rig.call("play_loop", want)
			_anim_name = want


## 镜像该朝谁走、该打谁。
## 棋局里 owner 是带队伍号的棋子 ⇒ 走统一入口按队伍筛；
## 旧写法固定查 `"player"` 组，而棋盘上没有 player 节点 ⇒ 恒 null，
## 结果镜像既不出伤也不走位（2026-11-05 审计发现，不崩、静默失效）。
## 非棋局（单打 / 塔 / 秘境 / 玩家侧）保持原来的组名查法一字不变。
func _focus_target() -> Node2D:
	if team_id >= 0:
		return BossBase.hostile_target(self)
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p != null and is_instance_valid(p):
		return p
	return null

func _motion_anchor() -> Node2D:
	if faction == "boss":
		var p := _focus_target()
		if p != null:
			return p
	if faction == "ally_boss" and owner_unit != null and is_instance_valid(owner_unit):
		var t = owner_unit.get("target")
		if t != null and is_instance_valid(t) and t is Node2D:
			return t as Node2D
	return owner_unit


func _clamp_to_arena(p: Vector2) -> Vector2:
	if get_parent() == null:
		return p
	var half = get_parent().get("arena_half_extents")
	if half is Vector2 and (half as Vector2) != Vector2.ZERO:
		var h := half as Vector2
		return Vector2(clampf(p.x, -h.x + 36.0, h.x - 36.0),
			clampf(p.y, -h.y + 36.0, h.y - 36.0))
	return p


func _set_visual_facing(face_left: bool) -> void:
	if _face_left == face_left:
		return
	_face_left = face_left
	_apply_visual_facing()


func _apply_visual_facing() -> void:
	if _rig != null:
		_rig.scale = Vector2(absf(_base_scale.x) * (-1.0 if _face_left else 1.0),
			absf(_base_scale.y))
	elif _spr != null:
		_spr.flip_h = _face_left


## 本体出招 → 镜像复读同一式：动画、镜水 FX、命中几何都用同一份 MoveDB 数据，
## 只有伤害是本体的一半；镜像血量仍然 1 击必碎。
func mimic_skill(form_id: String, source_damage: float) -> void:
	if _dead or _skill_anim_left > 0.0:
		return
	if faction != "boss" and faction != "ally_boss":
		return
	var target := _mimic_target()
	if target == null:
		return
	var form := MoveDB.resolve_boss(form_id)
	if form.is_empty():
		return
	var to := target.global_position - global_position
	var dir := to.normalized() if to.length_squared() > 0.0001 else Vector2.RIGHT
	_set_visual_facing(dir.x < 0.0)
	var anim := String(MIMIC_ANIM.get(form_id, ""))
	var dur := maxf(0.3, float(form.get("windup", 0.5)) 		+ float(form.get("active", 0.12)) + float(form.get("recover", 0.3)))
	if anim != "" and _rig != null and _rig.has_method("play_one_shot"):
		_rig.call("play_one_shot", anim, dur)
		_skill_anim_left = dur + 0.05
		_anim_name = "skill"
	var fx := String(MIMIC_FX.get(form_id, ""))
	if fx != "":
		if String(form.get("hit_shape", "")) == MoveDB.SHAPE_CIRCLE:
			SkillFx.play_at_point(get_parent(), fx, form, dir, global_position, self)
		else:
			SkillFx.play_at_strike(self, fx, form, dir)
	if form_id == "form_mirror_ring":
		_mimic_ring(source_damage)
		return
	var shape := String(form.get("hit_shape", ""))
	if shape == MoveDB.SHAPE_SELF:
		return
	var reach := float(form.get("range", 0.0))
	var dd := to.length()
	if shape == MoveDB.SHAPE_FAN:
		var half := deg_to_rad(float(form.get("angle", 60.0)) * 0.5)
		if dd > reach + 18.0 or (dd > 1.0 and dir.dot(to / dd) < cos(half)):
			return
	elif shape == MoveDB.SHAPE_LINE or shape == MoveDB.SHAPE_RECT:
		var forward := to.dot(dir)
		var lateral := absf(to.cross(dir))
		if forward < -12.0 or forward > reach + 18.0 				or lateral > float(form.get("width", 40.0)) * 0.5 + 18.0:
			return
	elif shape == MoveDB.SHAPE_CIRCLE:
		if dd > reach + 18.0:
			return
	else:
		return
	_deal_mimic_damage(target, source_damage * MIMIC_DAMAGE,
		String(form.get("attack_kind", "physical_melee")),
		String(form.get("damage_element", "")))


func _mimic_ring(source_damage: float) -> void:
	var field := MirrorRingField.new()
	field.setup(global_position, faction == "ally_boss", 150.0, 2.0,
		source_damage * MIMIC_DAMAGE, self, tint)
	get_parent().add_child(field)


func _mimic_target() -> Node2D:
	if faction == "boss":
		var p := _focus_target()
		if p != null:
			return p
	elif owner_unit != null and is_instance_valid(owner_unit):
		var t = owner_unit.get("target")
		if t != null and is_instance_valid(t) and t is Node2D:
			return t as Node2D
	return null


func _deal_mimic_damage(target: Node2D, dmg: float, kind: String, elem: String) -> void:
	if target == null or not is_instance_valid(target) or not target.has_method("take_damage"):
		return
	if target.is_in_group("player"):
		target.call("take_damage", dmg, kind, self, elem)
	else:
		target.call("take_damage", dmg, self, kind, elem, false)


## BOSS 镜像：向玩家打一记镜影斩（物理近战，可弹反；弹反会碎掉镜像）
func _boss_echo() -> void:
	if not is_inside_tree():
		return
	var p := _focus_target()
	if p == null:
		return
	var d := p.global_position - global_position
	if d.length() > BOSS_ECHO_RANGE:
		return
	var owner_attack := 40.0
	if owner_unit is BossBase:
		owner_attack = (owner_unit as BossBase).attack_power
	var dmg := owner_attack * echo_ratio
	var dir := d.normalized() if d.length_squared() > 0.0001 else Vector2.RIGHT
	SkillFx.play_at_strike(self, "skill_mirror_slash",
		MoveDB.resolve_boss("form_mirror_slash"), dir)
	# ⚠ 必须走 _deal_mimic_damage()，不能直接按玩家签名 p.take_damage(dmg, kind, self)。
	#   上一轮把 _focus_target() 改成"棋局里返回对方棋子"之后，这里拿到的已经是棋子了，
	#   而 BossBase 的签名是 (amount, source, damage_kind, element, from_projectile) ——
	#   第 3 参塞进 echo_kind(String) 就是
	#   "Cannot convert argument 3 from String to Object"，实机每帧刷 124 条。
	#   教训：**改了取目标，就必须把"打到目标"那条也跑一遍**，只验列表非空不算验通。
	_deal_mimic_damage(p, dmg, echo_kind, echo_element)


## 召唤法宝召来的观澜：镜像替他斩最近的敌方 BOSS，而不是打玩家
func _ally_boss_echo() -> void:
	if not is_inside_tree():
		return
	var target_boss: Node2D = null
	var best := 999999.0
	for raw in get_tree().get_nodes_in_group("boss"):
		if raw == null or not is_instance_valid(raw) or raw is not Node2D:
			continue
		var n := raw as Node2D
		if n == owner_unit or n is MirrorImage or not n.is_visible_in_tree():
			continue
		if n.has_method("is_dead") and bool(n.call("is_dead")):
			continue
		var dd := n.global_position.distance_to(global_position)
		if dd < best:
			best = dd
			target_boss = n
	if target_boss == null or best > BOSS_ECHO_RANGE:
		return
	var owner_attack := 40.0
	if owner_unit is BossBase:
		owner_attack = (owner_unit as BossBase).attack_power
	var dir := (target_boss.global_position - global_position).normalized()
	SkillFx.play_at_strike(self, "skill_mirror_slash",
		MoveDB.resolve_boss("form_mirror_slash"), dir)
	target_boss.call("take_damage", owner_attack * echo_ratio, owner_unit,
		"physical", "", false)


## BOSS 出招时让所有镜像同帧补斩（观澜的镜水斩 / 照影刺 / 万镜归一）
func force_echo() -> void:
	if _dead:
		return
	if faction == "ally_boss":
		_echo_timer = BOSS_ECHO_INTERVAL
		_ally_boss_echo()
		return
	if faction != "boss":
		return
	_echo_timer = BOSS_ECHO_INTERVAL
	_boss_echo()


## 玩家镜像的复读：玩家每放一次功法（镜花 / 万镜除外），**场上所有镜像同时**跟着使出同一招。
## 「使出」是真的放一遍：同一份表现（SKILL_FX，没有就回退 ArtDB.EFFECTS 的 visual_id）、
## 同一类投递方式 —— 投射物型生成真弹体（万剑归宗 → 飞剑追着目标飞）、镜湖生成真水场、
## 其余按形状以镜像自己为原点结算命中。伤害为本体的 50%，放完立刻消散，不看有没有打中。
## 返回 false = 这具镜像不接这一手（已死 / 阵营不对 / 没有伤害）。
func cast_echo(skill_id: String, form: Dictionary, damage: float,
		kind: String, elem: String) -> bool:
	if _dead or faction != "player" or form.is_empty() or damage <= 0.0:
		return false
	var target := _echo_target()
	var dir := _echo_dir(target)
	_set_visual_facing(dir.x < 0.0)
	# 战报行名：这一具镜像复读的是**哪一招**，就记在哪一招那一行上（归属仍是主人）。
	# 名称优先取 form 上的 form_name，退到 SkillDB 的功法名 —— 与招名飘字同源，不另立表。
	var echo_name := String(form.get("form_name", ""))
	if echo_name == "":
		echo_name = SkillDB.get_skill_name(skill_id)
	if echo_name != "":
		report_tag = echo_name
	var dmg := damage * echo_ratio
	var shape := String(form.get("hit_shape", MoveDB.SHAPE_FAN))
	if bool(form.get("fx_heaven", false)):
		# 一剑开天：整套「蓄力 → 巨剑劈落 → 撞击 → 地面劈痕」由 SwordHeavenFx 播，
		# 出伤对齐剑落地那一刻（与本体同一规则）；镜头拉远与压暗只归本体那一份，
		# 几具镜像一起复读会把镜头拽来拽去。镜像要活到落地，所以这套放完才碎。
		var hold := float(form.get("windup", 0.34)) \
				+ maxf(float(form.get("fx_release_time", 0.12)), 0.0) + 0.05
		SwordHeavenFx.play(self, form, dir, skill_id,
			func() -> void: _deal_echo_shape(form, dir, dmg, kind, elem), -1.0, false)
		_echo_hold_left = hold
		return true
	# 通用表现：有 SKILL_FX 放这一招自己的分族演出，没有就回退招式自己的 visual_id
	_play_echo_visual(skill_id, form, dir)
	if shape == MoveDB.SHAPE_SELF:
		pass
	elif skill_id == "skill_mirror_ring":
		_echo_ring(dmg)
	elif shape == MoveDB.SHAPE_PROJECTILE:
		_echo_projectiles(skill_id, form, dir, dmg, kind, elem, target)
	else:
		_deal_echo_shape(form, dir, dmg, kind, elem)
	_shatter(true)
	return true


## 表现挂在场景里而不是镜像身上：镜像当场碎掉不会把刚放出的特效一起带走
func _play_echo_visual(skill_id: String, form: Dictionary, dir: Vector2) -> void:
	if not ArtDB.get_skill_fx(skill_id).is_empty():
		SkillFx.play_at_strike(self, skill_id, form, dir)
		return
	SkillFx.play_form_fallback(get_parent(), global_position + ECHO_CENTER, form, dir)


## 镜湖：镜像亲自在自己脚下铺一圈水镜（半伤、同样挂镜滞）
func _echo_ring(dmg: float) -> void:
	var field := MirrorRingField.new()
	field.setup(global_position, true, RING_RADIUS, RING_DURATION, dmg, self, tint)
	get_parent().add_child(field)


## 投射物型：镜像真的把弹体放出去，而不是「原地瞬间结算」。
## 万剑归宗（带 intent_count_scale）额外走本体的飞剑形象 + 侧向散射 + 弧线追踪。
func _echo_projectiles(skill_id: String, form: Dictionary, dir: Vector2, dmg: float,
		kind: String, elem: String, target: Node2D) -> void:
	var packed := _projectile_scene()
	if packed == null:
		return
	var sfx := ArtDB.get_skill_fx(skill_id)
	var ics: Dictionary = form.get("intent_count_scale", {})
	var count := maxi(1, int(form.get("count", 1)))
	var spread := deg_to_rad(float(form.get("spread", 0.0)))
	if not ics.is_empty():
		spread = deg_to_rad(MYRIAD_SIDE_ANGLE * 2.0)
	var base_angle := dir.angle()
	for i in range(count):
		var angle := base_angle
		if count > 1:
			var t := float(i) / float(count - 1)
			angle = base_angle - spread * 0.5 + spread * t
		var proj: Node2D = packed.instantiate()
		proj.skill_id = skill_id
		# 来源记这具镜像：命中追溯、以及「BOSS 镜返不该算到玩家头上」都靠它
		proj.source = self
		proj.damage = dmg
		proj.damage_kind = kind
		proj.element = elem
		proj.speed = float(form.get("speed", 600.0))
		proj.max_distance = float(form.get("range", 600.0))
		proj.direction = Vector2.RIGHT.rotated(angle)
		var pv := String(sfx.get("projectile_visual", ""))
		if pv != "":
			proj.visual_id = pv
		proj.align_visual = bool(sfx.get("projectile_align", false))
		if not ics.is_empty():
			# 与本体同一把飞剑：竖直剑图、刃尖跟着飞行方向
			proj.visual_id = "boss_sword_projectile"
			proj.align_visual = true
			proj.turn_speed_deg = MYRIAD_TURN_SPEED
			proj.homing_target = target
			proj.launch_side = -1.0 if i % 2 == 0 else 1.0
		get_parent().add_child(proj)
		proj.global_position = global_position + ECHO_CENTER \
				+ proj.direction * (26.0 if not ics.is_empty() else 0.0)


## 玩家投射物场景（与 player.gd 同一份，静态缓存一次）
static func _projectile_scene() -> PackedScene:
	if _proj_scene == null:
		_proj_scene = load(PLAYER_PROJECTILE_SCENE) as PackedScene
	return _proj_scene


## 复读的目标：离镜像最近的敌方单位（含敌方镜像 —— 镜像本来就该互碎）
func _echo_target() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for raw in get_tree().get_nodes_in_group("boss"):
		var u := _echo_enemy(raw)
		if u == null:
			continue
		var d := u.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = u
	return best


func _echo_enemy(raw: Object) -> Node2D:
	if raw == null or not is_instance_valid(raw) or not (raw is Node2D):
		return null
	if raw == self or BossBase.is_ally_unit(raw):
		return null
	var u := raw as Node2D
	if u.has_method("is_dead") and bool(u.call("is_dead")):
		return null
	return u


## 没有敌人时朝主人的出招方向放，至少演出与朝向不穿帮
func _echo_dir(target: Node2D) -> Vector2:
	if target != null:
		var to := target.global_position - global_position
		if to.length_squared() > 1.0:
			return to.normalized()
	if owner_unit != null and is_instance_valid(owner_unit):
		var raw = owner_unit.get("attack_dir")
		if raw is Vector2 and (raw as Vector2).length_squared() > 0.0001:
			return (raw as Vector2).normalized()
	return Vector2.RIGHT


## 命中几何与玩家本体同一套口径（扇形/直线用 angle，矩形用 width，圆形用 range）
## 投射物型不实体放弹：按同一射程的窄扇面结算，读作「镜像替你把手挥了出去」。
func _deal_echo_shape(form: Dictionary, dir: Vector2, dmg: float,
		kind: String, elem: String) -> void:
	var shape := String(form.get("hit_shape", MoveDB.SHAPE_FAN))
	if shape == MoveDB.SHAPE_SELF:
		return
	var reach := float(form.get("range", 0.0))
	var half_angle := deg_to_rad(maxf(40.0, float(form.get("angle", 60.0))) * 0.5)
	var half_w := float(form.get("width", 54.0)) * 0.5
	for raw in get_tree().get_nodes_in_group("boss"):
		var u := _echo_enemy(raw)
		if u == null:
			continue
		var spheres: Array = [Vector3(0.0, 0.0, 30.0)]
		if u.has_method("hit_spheres"):
			spheres = u.call("hit_spheres")
		var hit := false
		for sp in spheres:
			var sv: Vector3 = sp
			if sv.z <= 0.0:
				continue
			var to: Vector2 = u.global_position + Vector2(sv.x, sv.y) - global_position
			var dd := to.length()
			if shape == MoveDB.SHAPE_CIRCLE:
				if dd <= reach + sv.z:
					hit = true
			elif shape == MoveDB.SHAPE_RECT:
				var fwd := to.dot(dir)
				var lateral := absf(to.cross(dir))
				if fwd >= -sv.z and fwd <= reach + sv.z and lateral <= half_w + sv.z:
					hit = true
			else:
				# 扇形 / 直线：与玩家本体一样按 angle 张角结算
				# 投射物型（angle=0）不实体放弹，用 40° 窄扇面顶替
				if dd <= reach + sv.z and (dd <= 1.0 or dir.dot(to / dd) >= cos(half_angle)):
					hit = true
			if hit:
				break
		if hit and u.has_method("take_damage"):
			u.call("take_damage", dmg, self, kind, elem)


## 任何物理命中 / 弹反 / 玩家碎镜都走这里。
## BOSS 侧镜像对法术免疫：法术只能穿过镜面，必须用物理命中才能打碎。
func take_damage(_amount: float, _a: Variant = null, _b: Variant = null,
		_c: Variant = null, _d: Variant = null) -> void:
	if faction == "boss" or faction == "ally_boss":
		var kind := ""
		if _b is String:
			kind = String(_b)
		elif _a is String:
			kind = String(_a)
		if kind == "elemental":
			_show_magic_immune()
			return
	_shatter(true)


func _show_magic_immune() -> void:
	if _immune_cd > 0.0 or not is_inside_tree():
		return
	_immune_cd = 0.35
	var lab := Label.new()
	lab.text = "法免"
	lab.add_theme_font_size_override("font_size", 15)
	lab.add_theme_color_override("font_color", Color(0.66, 0.90, 1.0))
	lab.add_theme_constant_override("outline_size", 3)
	lab.add_theme_color_override("font_outline_color", Color(0.04, 0.06, 0.10, 0.95))
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.position = Vector2(-30.0, -_visual_h * 0.5 - 52.0)
	lab.size = Vector2(60.0, 20.0)
	lab.z_index = 30
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lab)
	var tw := lab.create_tween()
	tw.tween_property(lab, "position:y", lab.position.y - 20.0, 0.45)
	tw.parallel().tween_property(lab, "modulate:a", 0.0, 0.45)
	tw.tween_callback(lab.queue_free)


func take_true_damage(_amount: float, _source: Node = null) -> void:
	_shatter(true)


func on_parried(_source: Node = null) -> void:
	_shatter(true)


func hit_radius() -> float:
	return 30.0


## 镜像的受击球：按贴图实际高度换算，别让玩家只能打到脚底
func hit_spheres() -> Array:
	var h := maxf(24.0, _visual_h)
	var top := -h * 0.47
	return [
		Vector3(0.0, top + h * 0.28, maxf(10.0, h * 0.16)),
		Vector3(0.0, top + h * 0.55, maxf(10.0, h * 0.20)),
		Vector3(0.0, top + h * 0.82, maxf(6.0, h * 0.10)),
	]


func unit_hp() -> float:
	return hp


func is_dead() -> bool:
	return _dead


func apply_debuff(_id: String, _duration: float) -> bool:
	return false


func has_debuff(_id: String) -> bool:
	return false


func _shatter(play_fx: bool) -> void:
	if _dead:
		return
	_dead = true
	hp = 0.0
	if play_fx and is_inside_tree():
		SkillFx.play_at_point(get_parent(), "skill_mirror_shatter",
			MoveDB.resolve_boss("form_mirror_shatter"), Vector2.RIGHT,
			global_position, null)
	queue_free()
