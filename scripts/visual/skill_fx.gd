class_name SkillFx
extends Node2D
## 玩家功法的新表现层（2026-10-25）。
##
## 设计目标：让「横斩 / 沉步竖斩 / 虎爪裂空 / 猛虎踏地 / 封路刀域 / 万剑归宗」等
## 一眼能看出是什么招，而不是共用一团扇形。所有主体都由程序化 shader、柔光 Sprite
## 与 CPUParticles2D 组成，不使用 draw_line / draw_polyline 拼线条。
##
## 数据在 ArtDB.SKILL_FAMILIES / SKILL_FX（族默认 + 单招覆盖）；本脚本只负责按时序
## 在「前摇结束、判定生效」的那一刻把招式演出来，并同步武器挥砍与震屏。
## 施法聚能挂在施法者身上；命中层挂在战场根节点，不会跟着角色漂走。

const SLASH_SHADER := "res://assets/shaders/skill_slash.gdshader"

static var _tex_cache: Dictionary = {}
static var _asset_cache: Dictionary = {}
static var _add_material_cache: CanvasItemMaterial

var _caster: Node2D
var _cfg: Dictionary = {}
var _form: Dictionary = {}
var _dir := Vector2.RIGHT
var _skill_id := ""
var _struck := false
## 调用方是否指定了出生点（风场这类点状招）：指定了就**不许**再被拉回施法者脚下
var _has_origin := false
## 落点锁定：符箓这类「已经飞到目标点再炸」的表现，中心必须留在传入的点
var _origin_locked := false


# ===================== 静态入口 =====================

## 玩家施放功法时调用（在 _spawn_skill_visual 里）
static func play(caster: Node2D, skill_id: String, form: Dictionary, dir: Vector2) -> void:
	if not is_instance_valid(caster):
		return
	var cfg := ArtDB.get_skill_fx(skill_id)
	if cfg.is_empty():
		return
	var host := caster.get_parent()
	if host == null:
		return
	var fx := SkillFx.new()
	fx._caster = caster
	fx._cfg = cfg
	fx._form = form.duplicate(true)
	fx._skill_id = skill_id
	fx._dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	host.add_child(fx)
	fx.global_position = caster.global_position
	fx._play_cast_aura()
	fx._run()


## 非玩家施法者（BOSS / 野修 / 召唤物）在**已经到达出手帧**时调用。
## 这类调用方没有自己的技能状态机，_play_skill_visual 已经在命中帧，
## 所以直接播命中层，不再等一遍 windup。
static func play_at_strike(caster: Node2D, skill_id: String, form: Dictionary,
		dir: Vector2, origin: Variant = null) -> SkillFx:
	if not is_instance_valid(caster):
		return null
	var cfg := ArtDB.get_skill_fx(skill_id)
	if cfg.is_empty():
		return null
	var host := caster.get_parent()
	if host == null:
		return null
	var fx := SkillFx.new()
	fx._caster = caster
	fx._cfg = cfg
	fx._form = form.duplicate(true)
	fx._skill_id = skill_id
	fx._dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	host.add_child(fx)
	# origin 只该由「点状出生」的招式传（嘴 / 爪尖 / 刀尖）；
	# 扇形与圆形 AOE 必须留在施法者原点，否则刀光比实际判定远出去一截。
	fx._has_origin = origin != null
	fx.global_position = caster.global_position if origin == null else Vector2(origin)
	if String(cfg.get("motif", "")) == "summon":
		fx._spawn_summon_gate()
	fx._strike()
	fx._free_after(float(cfg.get("lifetime", 0.4)) + 0.95)
	return fx


## 直接在指定世界坐标播放命中层（符卡飞到位、投射物落点等）。
## 与 play_at_strike 的区别：非地面招也不会再被拉回 caster 身上。
static func play_at_point(host: Node, skill_id: String, form: Dictionary,
		dir: Vector2, point: Vector2, caster: Node2D = null) -> SkillFx:
	if host == null or not host.is_inside_tree():
		return null
	var cfg := ArtDB.get_skill_fx(skill_id)
	if cfg.is_empty():
		return null
	var fx := SkillFx.new()
	fx._caster = caster
	fx._cfg = cfg
	fx._form = form.duplicate(true)
	fx._skill_id = skill_id
	fx._dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	fx._has_origin = true
	fx._origin_locked = true
	host.add_child(fx)
	fx.global_position = point
	fx._strike()
	fx._free_after(float(cfg.get("lifetime", 0.4)) + 0.95)
	return fx


## 按 form_id 找对应的玩家功法表现；找到并播放成功返回 true。
## 一剑开天由 SwordHeavenFx 专门驱动，这里返回 false 交给调用方的特殊分支。
static func play_form_at_strike(caster: Node2D, form_id: String, form: Dictionary,
		dir: Vector2, origin: Variant = null) -> bool:
	if form_id == "" or bool(form.get("fx_heaven", false)):
		return false
	var skill_id := SkillDB.get_skill_id_by_form(form_id)
	if skill_id == "" or ArtDB.get_skill_fx(skill_id).is_empty():
		return false
	return play_at_strike(caster, skill_id, form, dir, origin) != null


## 没有 SKILL_FX 条目的招式：回退到 ArtDB.EFFECTS 的 visual_id，并按形状给尺寸。
## 玩家本体（host = 自己、center = 局部身体中心）与镜像分身（host = 场景、center = 世界坐标）
## 共用这一份，保证「镜像放出来的招」和「本体放出来的招」看着是同一招。
static func play_form_fallback(host: Node, center: Vector2, form: Dictionary,
		dir: Vector2) -> void:
	if host == null or form.is_empty():
		return
	var visual_id := String(form.get("visual_id", ""))
	if visual_id == "":
		return
	var params := {}
	# 竖直光柱类：不跟着朝向旋转（保持屏幕竖直），落点在身前 fx_forward 处
	if bool(form.get("fx_vertical", false)):
		params["position"] = center + dir * float(form.get("fx_forward", 0.0))
		FxPlayer.spawn(host, visual_id, params)
		return
	params["position"] = center
	params["rotation"] = dir.angle()
	params["lifetime"] = maxf(0.12, float(form.get("active", 0.12)) + 0.1)
	# 扇形 / 圆形 / 矩形：特效尺寸跟随招式范围，「看到多大就打多大」
	var shape := String(form.get("hit_shape", ""))
	if shape == MoveDB.SHAPE_FAN or shape == MoveDB.SHAPE_CIRCLE:
		params["radius"] = float(form.get("range", 60.0)) * 0.85
		params["sweep_deg"] = float(form.get("angle", 60.0))
	elif shape == MoveDB.SHAPE_RECT:
		params["rect_size"] = Vector2(float(form.get("range", 1000.0)),
			float(form.get("width", 160.0)))
	FxPlayer.spawn(host, visual_id, params)


## 纳势反击的蓄力护势（常驻，由玩家每帧喂蓄力进度）
static func play_counter_ward(caster: Node2D, skill_id: String, form: Dictionary) -> CounterWardFx:
	if not is_instance_valid(caster):
		return null
	var cfg := ArtDB.get_skill_fx(skill_id)
	if cfg.is_empty():
		return null
	var ward := CounterWardFx.new()
	ward.caster = caster
	ward.cfg = cfg
	caster.add_child(ward)
	ward.setup(form)
	return ward


## 刀痕被激活时的爆裂（BladeScar 调用；刀痕本体马上销毁，所以挂到它的父节点）
static func scar_burst(host: Node, world_pos: Vector2, dir: Vector2) -> void:
	if host == null or not host.is_inside_tree():
		return
	var fx := SkillFx.new()
	fx._cfg = ArtDB.get_skill_fx("skill_blade_scar")
	fx._form = {"range": 96.0}
	fx._dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	host.add_child(fx)
	fx.global_position = world_pos
	fx.rotation = fx._dir.angle()
	fx._build_scar_burst()
	fx._free_after(0.85)


## 投射物命中：一点星火 + 碎光，让每一次命中都有落点
static func projectile_impact(host: Node, world_pos: Vector2, color: Color) -> void:
	if host == null or not host.is_inside_tree():
		return
	var holder := Node2D.new()
	holder.z_index = 4
	host.add_child(holder)
	holder.global_position = world_pos
	var flash := Sprite2D.new()
	flash.texture = star_texture()
	flash.centered = true
	flash.material = additive_material()
	flash.modulate = Color(color.r, color.g, color.b, 0.9)
	flash.scale = Vector2(0.22, 0.22)
	holder.add_child(flash)
	var tw := holder.create_tween().set_parallel(true)
	tw.tween_property(flash, "scale", Vector2(0.85, 0.85), 0.18) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "modulate:a", 0.0, 0.22)
	var p := make_particles(dot_texture(), 12, 0.32, 3, true)
	p.one_shot = true
	p.explosiveness = 1.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 8.0
	p.direction = Vector2.RIGHT
	p.spread = 180.0
	p.initial_velocity_min = 70.0
	p.initial_velocity_max = 230.0
	p.damping_min = 40.0
	p.damping_max = 100.0
	p.scale_amount_min = 0.08
	p.scale_amount_max = 0.18
	p.scale_amount_curve = make_curve([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])
	p.color_ramp = make_gradient(
		PackedFloat32Array([0.0, 0.1, 0.7, 1.0]),
		PackedColorArray([
			Color(color.r, color.g, color.b, 0.0),
			Color(color.r, color.g, color.b, 0.95),
			Color(color.r, color.g, color.b, 0.35),
			Color(color.r, color.g, color.b, 0.0),
		]))
	holder.add_child(p)
	p.restart()
	p.emitting = true
	holder.get_tree().create_timer(0.5).timeout.connect(holder.queue_free)


## 玩家弹反成功：金铁迸溅。三档（auto / normal / perfect）共用同一套合成，
## 只差碎星数量与尺寸（2026-10-26 简化：环、烟、月牙全部取消），参数在 ArtDB.EFFECTS 的 fx_parry_*。
## world_pos 由调用方算好（身体中心沿「玩家→攻击源」推出身位），dir = 弹开方向。
static func play_parry(host: Node, world_pos: Vector2, dir: Vector2, entry_key: String) -> void:
	var cfg: Dictionary = ArtDB.EFFECTS.get(entry_key, {})
	if cfg.is_empty():
		return
	var fx := _make_burst(host, world_pos, dir, cfg)
	if fx == null:
		return
	if fx._try_pixelfx():
		fx._free_after(float(cfg.get("lifetime", 0.42)) + 1.3)
		return
	fx._build_parry_burst()
	fx._free_after(float(cfg.get("lifetime", 0.42)) + 1.3)


## 极限闪避：冷蓝光带。闪避全程没有任何兵刃接触，所以这一套不喷碎星、不放星芒
static func play_dodge_slip(host: Node, world_pos: Vector2, dir: Vector2,
		entry_key: String) -> void:
	var cfg: Dictionary = ArtDB.EFFECTS.get(entry_key, {})
	if cfg.is_empty():
		return
	var fx := _make_burst(host, world_pos, dir, cfg)
	if fx == null:
		return
	fx._build_dodge_slip()
	fx._free_after(float(cfg.get("lifetime", 0.34)) + 1.3)


## 在战场某个世界坐标上立一个一次性特效节点，局部 +X 已经对齐 dir
static func _make_burst(host: Node, world_pos: Vector2, dir: Vector2,
		cfg: Dictionary) -> SkillFx:
	if host == null or not host.is_inside_tree():
		return null
	var fx := SkillFx.new()
	fx._cfg = cfg
	fx._dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	host.add_child(fx)
	fx.global_position = world_pos
	fx.rotation = fx._dir.angle()
	return fx


## 一剑开天落地：在裂纹贴图之上再补尘、碎石和震屏
## shake_override：>= 0 时覆盖条目里的震屏强度（0 = 本层不震，交给调用方自己震）
static func heaven_impact(host: Node, world_pos: Vector2, caster: Node2D, skill_id: String,
		shake_override: float = -1.0) -> void:
	if host == null or not host.is_inside_tree():
		return
	var cfg := ArtDB.get_skill_fx(skill_id)
	var holder := Node2D.new()
	holder.z_index = 4
	host.add_child(holder)
	holder.global_position = world_pos
	var flash := Sprite2D.new()
	flash.texture = star_texture()
	flash.centered = true
	flash.material = additive_material()
	flash.modulate = Color(0.86, 0.98, 1.0, 0.9)
	flash.scale = Vector2(0.6, 0.6)
	holder.add_child(flash)
	var tw := holder.create_tween().set_parallel(true)
	tw.tween_property(flash, "scale", Vector2(2.4, 2.4), 0.32) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "modulate:a", 0.0, 0.36)
	# 尘与碎石
	var dust := make_particles(smoke_texture(), 26, 1.0, -1, false)
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 26.0
	dust.direction = Vector2.RIGHT
	dust.spread = 180.0
	dust.initial_velocity_min = 30.0
	dust.initial_velocity_max = 140.0
	dust.gravity = Vector2(0.0, -28.0)
	dust.damping_min = 20.0
	dust.damping_max = 60.0
	dust.scale_amount_min = 0.35
	dust.scale_amount_max = 0.8
	dust.scale_amount_curve = make_curve([Vector2(0.0, 0.5), Vector2(0.3, 1.2), Vector2(1.0, 0.4)])
	dust.color_ramp = make_gradient(
		PackedFloat32Array([0.0, 0.15, 1.0]),
		PackedColorArray([
			Color(0.35, 0.30, 0.24, 0.0),
			Color(0.40, 0.34, 0.27, 0.28),
			Color(0.25, 0.22, 0.18, 0.0),
		]))
	dust.one_shot = true
	dust.explosiveness = 0.8
	holder.add_child(dust)
	dust.restart()
	dust.emitting = true
	var rocks := make_particles(rock_texture(), 14, 0.8, 2, false)
	rocks.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	rocks.emission_sphere_radius = 18.0
	rocks.direction = Vector2.RIGHT
	rocks.spread = 180.0
	rocks.initial_velocity_min = 100.0
	rocks.initial_velocity_max = 300.0
	rocks.gravity = Vector2(0.0, 420.0)
	rocks.angular_velocity_min = -260.0
	rocks.angular_velocity_max = 260.0
	rocks.scale_amount_min = 0.10
	rocks.scale_amount_max = 0.22
	rocks.color_ramp = make_gradient(
		PackedFloat32Array([0.0, 1.0]),
		PackedColorArray([Color(1.0, 0.82, 0.55, 0.85), Color(0.8, 0.6, 0.4, 0.0)]))
	rocks.one_shot = true
	rocks.explosiveness = 1.0
	holder.add_child(rocks)
	rocks.restart()
	rocks.emitting = true
	if is_instance_valid(caster) and caster.has_method("_screen_shake"):
		var shake := float(cfg.get("shake", 6.0)) if shake_override < 0.0 else shake_override
		if shake > 0.0:
			caster.call("_screen_shake", shake, 0.10 + shake * 0.012)
	holder.get_tree().create_timer(1.4).timeout.connect(holder.queue_free)


# ===================== 生命周期 =====================

func _run() -> void:
	var motif := String(_cfg.get("motif", "slash"))
	if motif == "summon":
		_spawn_summon_gate()
	var windup := maxf(float(_form.get("windup", 0.0)), 0.0)
	if windup > 0.0:
		await get_tree().create_timer(windup, true, false, true).timeout
	if not is_instance_valid(_caster):
		queue_free()
		return
	_strike()
	_free_after(float(_cfg.get("lifetime", 0.4)) + 0.95)


func _free_after(seconds: float) -> void:
	if not is_inside_tree():
		return
	get_tree().create_timer(seconds).timeout.connect(queue_free)


func _strike() -> void:
	if _struck:
		return
	_struck = true
	var motif := String(_cfg.get("motif", "slash"))
	var sun_mode := String(_cfg.get("sun_mode", ""))
	var ground := motif == "stomp" or motif == "field" or motif == "qi_cloud" \
		or (motif == "mirror" and bool(_cfg.get("mirror_ground", false))) \
		or (motif == "thunder" and bool(_cfg.get("thunder_ground", false))) \
		or (motif == "sun" and sun_mode in ["wheel", "eclipse", "meteor", "throw"]) 		or (motif == "calamity" and String(_cfg.get("calamity_mode", "")) in
			["fire_seal", "fire_field", "thunder_strike", "thunder_pool", "final"])
	var center := global_position
	if not _origin_locked and is_instance_valid(_caster):
		if ground:
			# 地面招：给了 origin 就用 origin（风场必须落在目标点、与判定圆重合），
			# 没给才贴施法者脚下。旧版无条件拉回施法者 → 风场圈画在 BOSS 脚底
			if not _has_origin:
				center = _caster.global_position
		else:
			center = _caster.global_position + _body_center(_caster)
	global_position = center
	# 有实际判定的近战形态必须正对 hit 方向；配置里的 rotation 只服务于起手演出，
	# 不能把「看到的扇形」转离「打得到的扇形」。
	var shape := String(_form.get("hit_shape", ""))
	var exact_melee := shape == MoveDB.SHAPE_FAN or shape == MoveDB.SHAPE_CIRCLE \
		or shape == MoveDB.SHAPE_LINE
	var extra_rot := 0.0 if exact_melee else deg_to_rad(float(_cfg.get("rotation", 0.0)))
	rotation = 0.0 if ground else _dir.angle() + extra_rot
	_swing_weapon()
	_shake()
	match motif:
		"pixel":
			_build_pixel_fx()
		"stomp":
			_build_stomp()
		"field":
			_build_field()
		"summon":
			_build_summon_burst()
		"thrust", "pierce":
			_build_thrust()
		"volley", "orb":
			_build_cast_burst()
		"ward":
			_build_ward_release()
		"qi_cloud":
			_build_qi_cloud()
		"thunder":
			_build_thunder()
		"sun":
			_build_sun()
		"calamity":
			_build_calamity()
		"mirror":
			_build_mirror()
		"shadow":
			_build_shadow()
		"fold":
			_build_fold()
		"peak":
			_build_peak()
		_:
			_build_slash()
	# 太极环：两仪转 / 太极崩 / 破盾这类「翻面」事件的共同语言
	if bool(_cfg.get("taiji", false)):
		_spawn_taiji_ring(_radius() * 2.0)
	# 八卦环：两仪一族所有招式的共同签名（大小由招式自己定，阴招反转）
	if bool(_cfg.get("bagua", false)):
		_spawn_bagua_ring(_radius() * 2.0 * float(_cfg.get("bagua_mult", 1.15)),
				float(_cfg.get("bagua_spin", 1.2)))
	# 专属印记：光看形状就能认出是哪一招
	var sigil := String(_cfg.get("sigil", ""))
	if sigil != "":
		_spawn_sigil(sigil)


## 像素通道（2026-11-04，pixelfx 烘焙表）。
## 两处来源，优先级从高到低：
##   1) assets/fx/pixelfx/bindings.json —— 特效工坊面板直接读写的绑定表；
##   2) ArtDB.SKILL_FX 条目里手写的 pixelfx_* 键。
## 都没写、或那张表还没烘出来，就退回原来的演出 —— 绝不能出现「放了个空招」。
## 震屏 / 命中停顿 / 挥武器仍然由本节点负责，所以只换「画出来的那一层」。
func _pixelfx_opts() -> Dictionary:
	var from_table: Dictionary = PixelFxLib.binding_for(_skill_id)
	if not from_table.is_empty():
		return from_table
	if String(_cfg.get("pixelfx", "")) != "":
		return _cfg
	return {}


func _try_pixelfx() -> bool:
	var opts_cfg := _pixelfx_opts()
	var id := String(opts_cfg.get("pixelfx", ""))
	if id == "":
		return false
	var host := get_parent()
	if host == null:
		return false
	var fx := PixelFxFx.spawn(host, global_position, id, {
		"variant": String(opts_cfg.get("pixelfx_variant", "default")),
		"scale": float(opts_cfg.get("pixelfx_scale", 1.0)),
		"additive": bool(opts_cfg.get("pixelfx_additive", false)),
		"flip": bool(opts_cfg.get("pixelfx_flip", false)),
		"flip_by_dir": bool(opts_cfg.get("pixelfx_flip_by_dir", true)),
		"speed": float(opts_cfg.get("pixelfx_speed", 1.0)),
		"back": bool(opts_cfg.get("pixelfx_back", false)),
		"z": float(opts_cfg.get("pixelfx_z", 4.0)),
	})
	if fx == null:
		push_warning("SkillFx: 像素特效 %s 还没烘焙，退回默认演出" % id)
		return false
	if bool(opts_cfg.get("pixelfx_fit_radius", false)):
		fx.fit_to_radius(_radius())
	return true


func _build_pixel_fx() -> void:
	if _try_pixelfx():
		return
	_build_slash()


## 八卦环：一圈八组卦象。两仪八式共用，这就是「同一只 BOSS 的语言」。
## dia 是环的外径；spin 是这环转过的弧度（负值 = 逆向，阴招用）。
func _spawn_bagua_ring(dia: float, spin: float = 1.2, alpha: float = 0.52) -> void:
	var tex := skill_texture("bagua")
	if tex == null:
		return
	var ring := Sprite2D.new()
	ring.texture = tex
	ring.centered = true
	ring.material = additive_material()
	var col: Color = _cfg.get("core", Color.WHITE)
	ring.modulate = Color(col.r, col.g, col.b, 0.0)
	ring.scale = Vector2.ONE * (clampf(dia, 110.0, 640.0) / 512.0)
	ring.rotation = randf_range(-0.25, 0.25)
	ring.z_index = 2
	add_child(ring)
	var tw := ring.create_tween()
	tw.tween_property(ring, "modulate:a", alpha, 0.09)
	tw.tween_property(ring, "modulate:a", 0.0, 0.40)
	tw.parallel().tween_property(ring, "rotation", ring.rotation + spin, 0.52)


## 专属印记（每张图都是一眼能认的形状）
const SIGIL_BASE_W := {"bagua": 512.0, "taiji": 512.0, "palm_seal": 512.0, "bar": 256.0}

## 影族三张墨迹贴图的**墨迹实际跨度**（画布四周那圈纸不能算进长度 ——
## 按画布尺寸换算会让影长比判定长一成多，「范围=判定」当场不成立）。
## ShadowVisual 也读这三个数：走廊与招式特效必须同一套换算。
const INK_STROKE_BASE := Vector2(684.0, 122.0)   ## 笔触：起笔浓墨在左、收笔飞白在右
const INK_BLOB_BASE := Vector2(425.0, 470.0)     ## 泼墨团
const INK_FLAME_BASE := Vector2(33.0, 115.0)     ## 灯芯火苗


func _sigil_sprite(key: String, dia: float) -> Sprite2D:
	var tex := skill_texture(key)
	if tex == null:
		return null
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	s.material = additive_material()
	var col: Color = _cfg.get("core", Color.WHITE)
	s.modulate = Color(col.r, col.g, col.b, 0.0)
	var base := float(SIGIL_BASE_W.get(key, 512.0))
	s.scale = Vector2.ONE * (dia / base)
	s.z_index = 4
	add_child(s)
	return s


func _spawn_sigil(kind: String) -> void:
	var radius := _radius()
	match kind:
		"palm":
			# 焚脉掌：一枚掌印盖在扇形中段，前推 + 胀开 —— 与刀客的刀光完全两种形状
			var seal := _sigil_sprite("palm_seal", radius * 1.05)
			if seal == null:
				return
			seal.position = Vector2(radius * 0.52, 0.0)
			var tw := seal.create_tween()
			tw.tween_property(seal, "modulate:a", 0.78, 0.06)
			tw.tween_property(seal, "modulate:a", 0.0, 0.34)
			tw.parallel().tween_property(seal, "scale", seal.scale * 1.14, 0.40)
			tw.parallel().tween_property(seal, "position", Vector2(radius * 0.62, 0.0), 0.40)
		"taiji":
			# 两仪转：中心太极印先收后放，转 270°
			var disc := _sigil_sprite("taiji", 150.0)
			if disc == null:
				return
			var tw := disc.create_tween()
			tw.tween_property(disc, "scale", disc.scale * 1.55, 0.12).from(disc.scale * 0.66)
			tw.parallel().tween_property(disc, "modulate:a", 0.9, 0.05)
			tw.tween_property(disc, "modulate:a", 0.0, 0.30)
			tw.parallel().tween_property(disc, "rotation", PI * 1.5, 0.46)
		"bars":
			# 阳关三叠：第几段盖几条卦爻（1 → 2 → 3），三踏叠齐正好是乾卦 ☰
			var bars := clampi(int(_form.get("sigil_bars", 3)), 1, 3)
			for i in bars:
				var b := _sigil_sprite("bar", radius * 1.10)
				if b == null:
					return
				b.position = Vector2(radius * 0.30, -(float(bars) - 1.0) * 7.5 + float(i) * 15.0)
				var tw := b.create_tween()
				tw.tween_interval(0.035 * float(i))
				tw.tween_property(b, "modulate:a", 0.92, 0.04)
				tw.tween_property(b, "modulate:a", 0.0, 0.26)
		"beads":
			# 玄冥指：直线上的三枚太极珠，越远越小 —— 和剑客的霜青剑光是两种东西
			for i in 3:
				var d := _sigil_sprite("taiji", radius * (0.34 - 0.06 * float(i)))
				if d == null:
					return
				d.position = Vector2(radius * (0.38 + 0.26 * float(i)), 0.0)
				var tw := d.create_tween()
				tw.tween_interval(0.045 * float(i))
				tw.tween_property(d, "modulate:a", 0.82, 0.05)
				tw.tween_property(d, "modulate:a", 0.0, 0.30)


## 太极环：金色阳半环 + 青色阴半环反向旋转，让「阴阳易位」一眼读得出来。
## dia 是环的外径：圆形判定招直接取 2×判定半径，所以环圈 = 挨打圈。
func _spawn_taiji_ring(dia: float) -> void:
	var tex := ring_texture()
	if tex == null:
		return
	var d := clampf(dia, 170.0, 540.0)
	for i in 2:
		var ring := Sprite2D.new()
		ring.texture = tex
		ring.centered = true
		ring.material = additive_material()
		var col: Color = _cfg.get("core", Color.WHITE) if i == 0 else _cfg.get("spark", Color.CYAN)
		ring.modulate = Color(col.r, col.g, col.b, 0.0)
		ring.scale = Vector2(d / 256.0, d / 256.0)
		ring.rotation = float(i) * PI
		ring.z_index = 3
		add_child(ring)
		var tw := ring.create_tween()
		tw.tween_property(ring, "modulate:a", 0.42 if i == 0 else 0.30, 0.07)
		tw.tween_property(ring, "modulate:a", 0.0, 0.45)
		tw.parallel().tween_property(ring, "rotation",
			ring.rotation + (2.2 if i == 0 else -2.2), 0.55)


# ===================== 施法聚能 =====================

func _play_cast_aura() -> void:
	if not is_instance_valid(_caster):
		return
	var strength := float(_cfg.get("cast_glow", 0.0))
	if strength <= 0.01:
		return
	var body := _body_center(_caster)
	var aura := Node2D.new()
	aura.z_index = -1
	aura.position = body
	_caster.add_child(aura)
	var glow := Sprite2D.new()
	glow.texture = dot_texture()
	glow.centered = true
	glow.material = additive_material()
	glow.scale = Vector2(0.75 + strength * 0.45, 0.75 + strength * 0.45)
	glow.modulate = Color(_cfg.get("glow", Color.ORANGE).r, _cfg.get("glow", Color.ORANGE).g,
		_cfg.get("glow", Color.ORANGE).b, 0.0)
	aura.add_child(glow)
	var tw := aura.create_tween()
	tw.tween_property(glow, "modulate:a", 0.28 * strength + 0.10, 0.14)
	tw.tween_interval(0.12)
	tw.tween_property(glow, "modulate:a", 0.0, 0.28)
	var p := make_particles(dot_texture(), 16 + int(strength * 14.0), 0.42, 2, true)
	p.one_shot = true
	p.explosiveness = 0.95
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 46.0
	p.direction = Vector2.RIGHT
	p.spread = 180.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 36.0
	p.radial_accel_min = -260.0
	p.radial_accel_max = -170.0
	p.tangential_accel_min = 44.0
	p.tangential_accel_max = 110.0
	p.damping_min = 10.0
	p.damping_max = 26.0
	p.scale_amount_min = 0.07
	p.scale_amount_max = 0.16
	p.scale_amount_curve = make_curve([Vector2(0.0, 0.4), Vector2(0.2, 1.0), Vector2(1.0, 0.0)])
	p.color_ramp = make_gradient(
		PackedFloat32Array([0.0, 0.12, 0.65, 1.0]),
		PackedColorArray([
			Color(_cfg.get("glow", Color.ORANGE).r, _cfg.get("glow", Color.ORANGE).g,
				_cfg.get("glow", Color.ORANGE).b, 0.0),
			Color(_cfg.get("spark", Color.WHITE).r, _cfg.get("spark", Color.WHITE).g,
				_cfg.get("spark", Color.WHITE).b, 0.8),
			Color(_cfg.get("glow", Color.ORANGE).r, _cfg.get("glow", Color.ORANGE).g,
				_cfg.get("glow", Color.ORANGE).b, 0.25),
			Color(_cfg.get("glow", Color.ORANGE).r, _cfg.get("glow", Color.ORANGE).g,
				_cfg.get("glow", Color.ORANGE).b, 0.0),
		]))
	p.position = body
	p.z_index = 2
	_caster.add_child(p)
	p.restart()
	p.emitting = true
	get_tree().create_timer(0.75).timeout.connect(aura.queue_free)
	get_tree().create_timer(0.75).timeout.connect(p.queue_free)


# ===================== 通用斩击层 =====================

func _build_slash() -> void:
	var motif := String(_cfg.get("motif", "slash"))
	var radius := _radius()
	var thickness := clampf(float(_cfg.get("thickness", 0.3)), 0.12, 0.55)
	var arc := float(_cfg.get("arc", 120.0))
	# 扇形近战：视觉张角直接取判定张角，避免「看起来 74°、实际打 110°」
	if String(_form.get("hit_shape", "")) == MoveDB.SHAPE_FAN:
		arc = float(_form.get("angle", arc))
	var layers := clampi(int(_cfg.get("layers", 1)), 1, 3)
	var seed_base := randf() * 12.0
	# 云 / 刀气追击 / 满势断岳：只去掉扇形刀光，挥剑、聚能与起手粒子保留
	var draw_slash := not bool(_cfg.get("no_slash", false))
	if motif == "claw":
		if draw_slash:
			for i in 3:
				var offset := -22.0 + 22.0 * float(i)
				_spawn_arc(radius * (0.94 + 0.06 * float(i)), deg_to_rad(arc * 0.12),
					thickness * 0.90, offset, 0.95 if i == 1 else 0.72, seed_base + i * 2.3)
			var haze := Sprite2D.new()
			haze.texture = dot_texture()
			haze.centered = true
			haze.material = additive_material()
			haze.modulate = Color(_cfg.get("glow", Color.ORANGE).r, _cfg.get("glow", Color.ORANGE).g,
				_cfg.get("glow", Color.ORANGE).b, 0.24)
			haze.position = Vector2(radius * 0.4, 0.0)
			haze.scale = Vector2(1.35, 0.95)
			haze.z_index = 1
			add_child(haze)
	else:
		if draw_slash:
			for i in layers:
				var offset := 0.0
				var rad_mul := 1.0
				var alpha := 1.0
				if i == 1:
					offset = 5.0
					rad_mul = 1.035
					alpha = 0.46
				elif i == 2:
					offset = -6.0
					rad_mul = 0.97
					alpha = 0.32
				_spawn_arc(radius * rad_mul, deg_to_rad(arc * 0.5),
					thickness * (1.0 - 0.07 * float(i)), offset, alpha, seed_base + i * 3.1)
	_spawn_sparks(radius, deg_to_rad(clampf(arc * 0.9, 18.0, 220.0)))
	_spawn_dust(0.0)
	_spawn_flash(Vector2(radius * 0.48, 0.0), 0.9)
	if int(_cfg.get("dash_streaks", 0)) > 0:
		_spawn_dash_streaks(int(_cfg.get("dash_streaks", 6)))
	if motif == "spin":
		_spawn_spin_wind(radius)


# ===================== 观澜 · 镜水一族 =====================
## 镜面的读法只有三件东西：**薄银镜片、冷蓝水光、碎镜棱**。
## 不用刀光的暖色月牙、不用云烟、不用雷弧 —— 和前面九只 BOSS 的质感分开。
func _build_mirror() -> void:
	var mode := String(_cfg.get("mirror_mode", "slash"))
	var radius := _radius()
	var core: Color = _cfg.get("core", Color(0.92, 0.99, 1.0))
	var glow: Color = _cfg.get("glow", Color(0.26, 0.58, 0.84))
	var spark: Color = _cfg.get("spark", Color(0.72, 0.94, 1.0))
	match mode:
		"slash":
			var arc := float(_cfg.get("arc", 110.0))
			if String(_form.get("hit_shape", "")) == MoveDB.SHAPE_FAN:
				arc = float(_form.get("angle", arc))
			for i in 3:
				_spawn_arc(radius * (0.94 + 0.055 * float(i)),
					deg_to_rad(arc * 0.5), 0.12 + 0.025 * float(i),
					-6.0 + 6.0 * float(i), 0.95 - 0.24 * float(i), 1.7 + float(i) * 2.9)
			# 贴地的宽弧：只亮身前这一扇，告诉玩家「打到哪」
			_spawn_arc(radius * 0.98, deg_to_rad(arc * 0.5), 0.34, 0.0, 0.16, 6.2)
			_mirror_shards(radius * 0.78, 9, core, spark)
		"thrust":
			var length := maxf(float(_form.get("range", radius)), 80.0)
			var bar := _stretch_bar(Vector2(length * 0.48, 0.0), 0.0, length, 9.0,
				Color(core.r, core.g, core.b, 0.88))
			var tw := bar.create_tween()
			tw.tween_property(bar, "scale:y", 0.6, 0.10)
			tw.parallel().tween_property(bar, "modulate:a", 0.0, 0.30)
			_stretch_bar(Vector2(length * 0.48, 0.0), 0.0, length, 26.0,
				Color(glow.r, glow.g, glow.b, 0.10))
			_mirror_band(38.0, core, glow, 0.24)
			_mirror_shards(length * 0.72, 8, core, spark)
		"bloom":
			for i in 5:
				var ang := -PI * 0.5 + TAU * float(i) / 5.0
				_mirror_panel(Vector2(cos(ang), sin(ang)) * (radius * 0.28),
					Vector2(18.0, 92.0), ang + PI * 0.5, core, glow, 0.55)
			_mirror_band(radius * 0.55, core, glow, 0.34)
		"shatter":
			_mirror_band(radius * 0.92, core, glow, 0.48)
			_mirror_shards(radius * 1.02, 16, core, spark, 1.35)
			_spawn_flash(Vector2.ZERO, 1.2)
		"swap":
			_mirror_panel(Vector2(-38.0, -34.0), Vector2(20.0, 96.0), 0.0, core, glow, 0.55)
			_mirror_panel(Vector2(38.0, -34.0), Vector2(20.0, 96.0), 0.0, core, glow, 0.55)
			_mirror_band(radius * 0.30, core, glow, 0.24)
		"return":
			_mirror_panel(Vector2(30.0, -30.0), Vector2(26.0, 130.0), 0.0, core, glow, 0.78)
			_spawn_arc(radius * 0.62, deg_to_rad(54.0), 0.16, 0.0, 0.34, 3.4)
			_mirror_shards(radius * 0.50, 6, core, spark, 0.65)
		"ring":
			_mirror_band(radius * 0.98, core, glow, 0.46)
			_mirror_band(radius * 0.62, core, glow, 0.20)
			for i in 8:
				var ang2 := TAU * float(i) / 8.0
				_mirror_panel(Vector2(cos(ang2), sin(ang2)) * radius * 0.92,
					Vector2(10.0, 34.0), ang2 + PI * 0.5, core, glow, 0.30)
		"myriad":
			var arc2 := float(_form.get("angle", 130.0))
			for i in 4:
				_spawn_arc(radius * (0.88 + 0.075 * float(i)),
					deg_to_rad(arc2 * 0.5), 0.10 + 0.025 * float(i),
					-12.0 + 8.0 * float(i), 0.92 - 0.18 * float(i), 2.1 + float(i) * 3.4)
			_spawn_arc(radius * 1.02, deg_to_rad(arc2 * 0.5), 0.40, 0.0, 0.14, 8.1)
			for i in 4:
				var ang3 := -PI * 0.5 + TAU * float(i) / 4.0
				_mirror_panel(Vector2(cos(ang3), sin(ang3)) * radius * 0.55,
					Vector2(16.0, 104.0), ang3 + PI * 0.5, core, glow, 0.42)
			_mirror_shards(radius * 0.95, 13, core, spark, 1.15)
		_:
			_mirror_band(radius * 0.70, core, glow, 0.30)


## 一片立在空中的薄镜：外层冷光 + 内层银面 + 一条斜裂。
func _mirror_panel(local_pos: Vector2, size: Vector2, rot: float,
		core: Color, glow: Color, alpha: float) -> void:
	var glow_bar := Sprite2D.new()
	glow_bar.texture = white_texture()
	glow_bar.centered = true
	glow_bar.material = additive_material()
	glow_bar.position = local_pos
	glow_bar.rotation = rot
	glow_bar.scale = Vector2(size.x * 1.8 / 4.0, size.y * 1.06 / 4.0)
	glow_bar.modulate = Color(glow.r, glow.g, glow.b, alpha * 0.28)
	glow_bar.z_index = 2
	add_child(glow_bar)
	var face := Sprite2D.new()
	face.texture = white_texture()
	face.centered = true
	face.material = additive_material()
	face.position = local_pos
	face.rotation = rot
	face.scale = Vector2(size.x / 4.0, size.y / 4.0)
	face.modulate = Color(core.r, core.g, core.b, alpha)
	face.z_index = 3
	add_child(face)
	var crack := _stretch_bar(local_pos + Vector2(0.0, size.y * 0.05),
		rot + 0.62, size.y * 0.52, 1.4, Color(glow.r, glow.g, glow.b, alpha * 0.75))
	crack.z_index = 4
	var tw := create_tween()
	tw.tween_property(face, "modulate:a", 0.0, 0.34)
	tw.parallel().tween_property(glow_bar, "modulate:a", 0.0, 0.38)
	tw.parallel().tween_property(crack, "modulate:a", 0.0, 0.30)
	tw.parallel().tween_property(face, "scale:y", face.scale.y * 1.08, 0.34) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## 一圈贴着地面的冷蓝水光（不用硬边圆环：软环 + 内外两道）
func _mirror_band(radius: float, core: Color, glow: Color, alpha: float) -> void:
	var ring := Sprite2D.new()
	ring.texture = ring_texture()
	ring.centered = true
	ring.material = additive_material()
	ring.scale = Vector2.ONE * clampf(radius / 97.3, 0.35, 8.0)
	ring.modulate = Color(glow.r, glow.g, glow.b, 0.0)
	ring.z_index = 1
	add_child(ring)
	var tw := ring.create_tween()
	tw.tween_property(ring, "modulate:a", alpha, 0.08)
	tw.tween_property(ring, "modulate:a", 0.0, 0.42)
	tw.parallel().tween_property(ring, "scale", ring.scale * 1.10, 0.46) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var disc := Sprite2D.new()
	disc.texture = dot_texture()
	disc.centered = true
	disc.material = additive_material()
	disc.scale = Vector2.ONE * (clampf(radius * 2.0, 60.0, 720.0) / 128.0 * 0.55)
	disc.modulate = Color(core.r, core.g, core.b, alpha * 0.16)
	disc.z_index = 0
	add_child(disc)
	var tw2 := disc.create_tween()
	tw2.tween_property(disc, "modulate:a", 0.0, 0.40)


## 碎镜棱：从中心向外散开的细长银片（每片随机角度、长短、旋转）
func _mirror_shards(radius: float, count: int, core: Color, spark: Color,
		power: float = 1.0) -> void:
	var shard_tex := mirror_shard_texture()
	for i in count:
		var ang := randf() * TAU
		var dist := randf_range(12.0, maxf(radius * 0.55, 20.0))
		var shard := Sprite2D.new()
		shard.texture = shard_tex
		shard.centered = true
		shard.material = additive_material()
		shard.position = Vector2(cos(ang), sin(ang)) * dist
		shard.rotation = ang - PI * 0.5
		var length := randf_range(22.0, 58.0) * power
		var width := randf_range(7.0, 15.0)
		shard.scale = Vector2(width / 128.0, length / 128.0)
		shard.modulate = Color(core.r, core.g, core.b, randf_range(0.55, 0.95))
		shard.z_index = randi_range(3, 5)
		add_child(shard)
		var tw := shard.create_tween().set_parallel(true)
		tw.tween_property(shard, "position",
			shard.position + Vector2(cos(ang), sin(ang)) * randf_range(50.0, 150.0) * power,
			0.40).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_property(shard, "rotation", shard.rotation + randf_range(-1.8, 1.8), 0.40)
		tw.tween_property(shard, "modulate:a", 0.0, 0.44)
	var p := make_particles(star_texture(), maxi(8, count * 2), 0.42, 4, true)
	p.one_shot = true
	p.explosiveness = 1.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = maxf(8.0, radius * 0.10)
	p.direction = Vector2.RIGHT
	p.spread = 180.0
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 290.0 * power
	p.gravity = Vector2.ZERO
	p.damping_min = 30.0
	p.damping_max = 90.0
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.13
	p.color = Color(spark.r, spark.g, spark.b, 0.85)
	add_child(p)
	p.emitting = true


## 一个月牙/爪痕面片。radius 是外缘像素半径；arc_half 是单侧张角（弧度）。
func _spawn_arc(radius: float, arc_half: float, thickness: float,
		rotation_deg: float, alpha: float, seed: float) -> void:
	var quad := Sprite2D.new()
	quad.texture = white_texture()
	quad.centered = true
	var side := radius * 2.25
	quad.scale = Vector2(side / 4.0, side / 4.0)
	quad.rotation = deg_to_rad(rotation_deg)
	quad.z_index = 2
	var mat := ShaderMaterial.new()
	mat.shader = load(SLASH_SHADER)
	mat.set_shader_parameter("arc_half", clampf(arc_half, 0.08, 3.15))
	mat.set_shader_parameter("inner", clampf(1.0 - thickness, 0.0, 0.95))
	mat.set_shader_parameter("outer", 1.0)
	mat.set_shader_parameter("core_color", _color_vec(_cfg.get("core", Color.WHITE)))
	mat.set_shader_parameter("glow_color", _color_vec(_cfg.get("glow", Color.ORANGE)))
	mat.set_shader_parameter("noise_amount", float(_cfg.get("noise_amount", 0.65)))
	mat.set_shader_parameter("seed", seed)
	mat.set_shader_parameter("heat", 0.45 if String(_cfg.get("family", "")) != "sword" else 0.2)
	mat.set_shader_parameter("opacity", alpha)
	quad.material = mat
	add_child(quad)

	var sweep := maxf(float(_cfg.get("sweep", 0.12)), 0.05)
	var life := maxf(float(_cfg.get("lifetime", 0.4)), 0.2)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("progress", v),
		0.0, 1.0, sweep)
	var fade := create_tween()
	fade.tween_interval(life * 0.35)
	fade.tween_method(func(v: float) -> void: mat.set_shader_parameter("opacity", v),
		alpha, 0.0, maxf(life * 0.65, 0.08))
	var grow := create_tween()
	grow.tween_property(quad, "scale", quad.scale * 1.045, life) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _spawn_sparks(radius: float, spread_rad: float) -> void:
	var p := make_particles(star_texture(), int(_cfg.get("sparks", 22)), 0.48, 3, true)
	p.one_shot = true
	p.explosiveness = 1.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = maxf(10.0, radius * 0.12)
	p.direction = Vector2.RIGHT
	p.spread = rad_to_deg(clampf(spread_rad, 0.3, PI))
	p.initial_velocity_min = 150.0
	p.initial_velocity_max = 430.0
	p.gravity = Vector2.ZERO
	p.damping_min = 30.0
	p.damping_max = 100.0
	p.scale_amount_min = 0.07
	p.scale_amount_max = 0.18
	p.scale_amount_curve = make_curve([Vector2(0.0, 1.0), Vector2(0.55, 0.7), Vector2(1.0, 0.0)])
	p.color_ramp = make_gradient(
		PackedFloat32Array([0.0, 0.08, 0.62, 1.0]),
		PackedColorArray([
			Color(_cfg.get("glow", Color.ORANGE).r, _cfg.get("glow", Color.ORANGE).g,
				_cfg.get("glow", Color.ORANGE).b, 0.0),
			Color(_cfg.get("spark", Color.WHITE).r, _cfg.get("spark", Color.WHITE).g,
				_cfg.get("spark", Color.WHITE).b, 0.95),
			Color(_cfg.get("glow", Color.ORANGE).r, _cfg.get("glow", Color.ORANGE).g,
				_cfg.get("glow", Color.ORANGE).b, 0.45),
			Color(_cfg.get("glow", Color.ORANGE).r, _cfg.get("glow", Color.ORANGE).g,
				_cfg.get("glow", Color.ORANGE).b, 0.0),
		]))
	p.position = Vector2(0.0, -6.0)
	add_child(p)
	p.restart()
	p.emitting = true


func _spawn_dust(offset_y: float) -> void:
	var amount := int(_cfg.get("dust", 10))
	var smoke_amount := int(_cfg.get("smoke_count", 8))
	if amount > 0:
		var d := make_particles(smoke_texture(), amount, 0.9, -1, false)
		d.one_shot = true
		d.explosiveness = 0.75
		d.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		d.emission_sphere_radius = 24.0
		d.direction = Vector2.RIGHT
		d.spread = 180.0
		d.initial_velocity_min = 18.0
		d.initial_velocity_max = 95.0
		d.gravity = Vector2(0.0, -18.0)
		d.damping_min = 30.0
		d.damping_max = 70.0
		d.scale_amount_min = 0.28
		d.scale_amount_max = 0.62
		d.scale_amount_curve = make_curve([Vector2(0.0, 0.45), Vector2(0.3, 1.15), Vector2(1.0, 0.5)])
		d.color_ramp = make_gradient(
			PackedFloat32Array([0.0, 0.14, 1.0]),
			PackedColorArray([
				Color(_cfg.get("smoke", Color.DIM_GRAY).r, _cfg.get("smoke", Color.DIM_GRAY).g,
					_cfg.get("smoke", Color.DIM_GRAY).b, 0.0),
				Color(_cfg.get("smoke", Color.DIM_GRAY).r, _cfg.get("smoke", Color.DIM_GRAY).g,
					_cfg.get("smoke", Color.DIM_GRAY).b, 0.24),
				Color(_cfg.get("smoke", Color.DIM_GRAY).r, _cfg.get("smoke", Color.DIM_GRAY).g,
					_cfg.get("smoke", Color.DIM_GRAY).b, 0.0),
			]))
		d.position = Vector2(0.0, offset_y)
		add_child(d)
		d.restart()
		d.emitting = true
	if smoke_amount > 0 and String(_cfg.get("family", "")) == "tiger":
		var s := make_particles(smoke_texture(), smoke_amount, 1.1, -1, false)
		s.one_shot = true
		s.explosiveness = 0.65
		s.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		s.emission_sphere_radius = 30.0
		s.direction = Vector2.RIGHT
		s.spread = 180.0
		s.initial_velocity_min = 8.0
		s.initial_velocity_max = 50.0
		s.gravity = Vector2(0.0, -10.0)
		s.damping_min = 20.0
		s.damping_max = 50.0
		s.scale_amount_min = 0.4
		s.scale_amount_max = 0.8
		s.scale_amount_curve = make_curve([Vector2(0.0, 0.5), Vector2(0.35, 1.2), Vector2(1.0, 0.4)])
		s.color_ramp = make_gradient(
			PackedFloat32Array([0.0, 0.18, 1.0]),
			PackedColorArray([
				Color(0.16, 0.09, 0.05, 0.0),
				Color(0.16, 0.09, 0.05, 0.30),
				Color(0.10, 0.06, 0.03, 0.0),
			]))
		s.position = Vector2(0.0, offset_y - 8.0)
		add_child(s)
		s.restart()
		s.emitting = true


func _spawn_flash(local_pos: Vector2, size_mult: float) -> void:
	var flash := Sprite2D.new()
	flash.texture = star_texture()
	flash.centered = true
	flash.material = additive_material()
	var fa := clampf(float(_cfg.get("flash_alpha", 1.0)), 0.0, 1.5)
	flash.modulate = Color(_cfg.get("hot", Color.WHITE).r, _cfg.get("hot", Color.WHITE).g,
		_cfg.get("hot", Color.WHITE).b, 0.9 * fa)
	flash.position = local_pos
	flash.scale = Vector2(0.18, 0.18) * size_mult
	flash.z_index = 4
	add_child(flash)
	var tw := flash.create_tween().set_parallel(true)
	tw.tween_property(flash, "scale", Vector2(0.8, 0.8) * size_mult, 0.2) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "modulate:a", 0.0, 0.24)


func _spawn_dash_streaks(count: int) -> void:
	for i in count:
		var streak := Sprite2D.new()
		streak.texture = streak_texture()
		streak.centered = true
		streak.material = additive_material()
		streak.modulate = Color(_cfg.get("spark", Color.WHITE).r, _cfg.get("spark", Color.WHITE).g,
			_cfg.get("spark", Color.WHITE).b, 0.20)
		streak.position = Vector2(-randf_range(26.0, 150.0), randf_range(-24.0, 24.0))
		streak.rotation = -PI * 0.5
		streak.scale = Vector2(randf_range(0.35, 0.55), randf_range(0.4, 0.9))
		streak.z_index = 1
		add_child(streak)
		var tw := streak.create_tween().set_parallel(true)
		tw.tween_property(streak, "modulate:a", 0.0, 0.28)
		tw.tween_property(streak, "scale:x", streak.scale.x * 1.8, 0.28)


func _spawn_spin_wind(radius: float) -> void:
	var ring := Sprite2D.new()
	ring.texture = ring_texture()
	ring.centered = true
	ring.material = additive_material()
	ring.modulate = Color(_cfg.get("spark", Color.WHITE).r, _cfg.get("spark", Color.WHITE).g,
		_cfg.get("spark", Color.WHITE).b, 0.0)
	ring.scale = Vector2(radius * 1.7 / 256.0, radius * 1.7 / 256.0)
	ring.z_index = -1
	add_child(ring)
	var tw := ring.create_tween()
	tw.tween_property(ring, "modulate:a", 0.28, 0.07)
	tw.tween_property(ring, "modulate:a", 0.0, 0.34)
	tw.parallel().tween_property(ring, "scale", ring.scale * 1.5, 0.4)


# ===================== 执烛 · 影族（2026-11-02）=====================
## 这一族的读法只有三件东西：**墨黑的柔边影带、影尖那枚冷银亮点、灯焰的明暗**。
## 不用刀光月牙、不用云烟、不用雷弧、不用镜面银 —— 与观澜的镜水一族刻意分开：
## 观澜亮在**镜片**（加色银白 + 碎棱），执烛亮在**暗部**（墨黑 + 只在影尖漏一点冷光）。
## 走廊的持续显示由 ShadowVisual 负责，这里只做「这一拍落了」的瞬时层。
func _build_shadow() -> void:
	var mode := String(_cfg.get("shadow_mode", "cut"))
	var radius := _radius()
	var ink: Color = _cfg.get("ink", Color(0.03, 0.04, 0.07))
	var core: Color = _cfg.get("core", Color(0.80, 0.92, 1.0))
	var glow: Color = _cfg.get("glow", Color(0.22, 0.34, 0.56))
	## 影身真实长度：BOSS / 玩家侧把当前影长塞进 form.range 再调过来
	var span := maxf(float(_form.get("range", radius)), 60.0)
	match mode:
		"cut":
			## 身前一道墨弧 + 影尖补的那一段：弧是暗的，只有边缘漏冷银
			_ink_arc(radius * 0.96, 0.34, 1.00)
			_ink_arc(radius * 0.78, 0.20, 0.86)
			## 墨弧在暗地面上必须靠亮边读形：沿弧线补一道**细**冷银刃口
			## ⚠ 只能当描边用（≤5px）。第一版给到 9px / 0.62，实机截图里整条影子
			##   变成一根白色光剑，把「这是影子」的设定直接讲反了。
			_soft_bar(Vector2(radius * 0.52, 0.0), 0.0, radius * 0.96, 6.0,
				Color(core.r, core.g, core.b, 0.55)).z_index = 4
			_spawn_flash(Vector2(radius * 0.62, 0.0), 0.7)
		"reach":
			## 一整个影长铺成一条墨带，末端炸一枚冷银尖 —— 看到亮点就该知道打得有多远
			_ink_bar(Vector2(span * 0.5, 0.0), 0.0, span, 34.0, 0.92)
			_ink_bar(Vector2(span * 0.5, 0.0), 0.0, span * 0.82, 15.0, 1.00)
			_ink_wisp(span, 5)
			var tip := _spawn_tip(Vector2(span, 0.0), core)
			tip.z_index = 5
			_soft_bar(Vector2(span * 0.5, 0.0), 0.0, span, 6.0,
				Color(core.r, core.g, core.b, 0.52)).z_index = 4
		"bind":
			## 地上按出一团墨 + 三根收拢的墨指：0.7 秒后这里生效
			_ink_blob(Vector2.ZERO, 0.9)
			for i in 3:
				var ang := -0.7 + 0.7 * float(i)
				_ink_bar(Vector2(cos(ang) * 26.0, sin(ang) * 26.0), ang,
					58.0, 11.0, 0.95)
			_spawn_flash(Vector2.ZERO, 0.55)
		"step":
			## 掠过去的走廊：三段错位墨带 + 一道拉长的影刃
			for i in 4:
				_ink_bar(Vector2(span * (0.22 + 0.2 * float(i)), -14.0 + 10.0 * float(i)),
					0.05 * float(i), span * 0.34, 20.0 - 3.0 * float(i), 0.88 - 0.10 * float(i))
			_ink_bar(Vector2(span * 0.5, 0.0), 0.0, span, 12.0, 1.00)
			_soft_bar(Vector2(span * 0.5, 0.0), 0.0, span, 6.0,
				Color(core.r, core.g, core.b, 0.50)).z_index = 4
			_spawn_dash_streaks(7)
		"dim":
			## 灯被捻暗：一圈向内收的墨环 + 中心一点残焰
			_ink_blob(Vector2.ZERO, 1.6)
			_ink_blob(Vector2.ZERO, 1.05)
			var mote := _spawn_tip(Vector2.ZERO, Color(0.98, 0.86, 0.58))
			mote.z_index = 5
		"beam":
			## 照骨是光不是影：冷白芯 + 外面一层水蓝辉光，宽度取判定 width
			var w := float(_form.get("width", 62.0))
			_soft_bar(Vector2(span * 0.5, 0.0), 0.0, span, w * 0.30,
				Color(glow.r, glow.g, glow.b, 0.34))
			_soft_bar(Vector2(span * 0.5, 0.0), 0.0, span, w * 0.16,
				Color(core.r, core.g, core.b, 0.82))
			_soft_bar(Vector2(span * 0.5, 0.0), 0.0, span, w * 0.075,
				Color(1.0, 1.0, 1.0, 0.95))
			_spawn_flash(Vector2(span * 0.06, 0.0), 0.9)
		"split":
			## 影子被整片撕下来：几张错开的墨片甩向影尖方向
			for i in 5:
				var off := Vector2(span * (0.12 + 0.16 * float(i)),
					randf_range(-30.0, 30.0))
				var sh := _ink_bar(off, randf_range(-0.5, 0.5),
					span * 0.28, 40.0 - 4.0 * float(i), 0.95 - 0.10 * float(i))
				var tw2 := sh.create_tween()
				tw2.tween_property(sh, "rotation", sh.rotation + 0.9, 0.5)
			_ink_blob(Vector2.ZERO, 1.2)
			_soft_bar(Vector2(span * 0.42, 0.0), 0.0, span * 0.8, 6.0,
				Color(core.r, core.g, core.b, 0.45)).z_index = 3
		"longnight":
			## 反照：八方墨带同时向圆心收拢，收拢到位才是判定
			for i in 8:
				var ang2 := TAU * float(i) / 8.0
				var unit := Vector2(cos(ang2), sin(ang2))
				_ink_bar(unit * (span * 0.55), ang2, span * 0.75, 26.0, 0.90)
			_ink_blob(Vector2.ZERO, 2.1)
			for i in 4:
				var ang3 := TAU * float(i) / 4.0 + PI * 0.25
				var unit3 := Vector2(cos(ang3), sin(ang3))
				_soft_bar(unit3 * (span * 0.42), ang3, span * 0.6, 6.0,
					Color(core.r, core.g, core.b, 0.50)).z_index = 3
			_spawn_flash(Vector2.ZERO, 1.5)
			_spawn_flash(Vector2(span * 0.5, 0.0), 0.9)
		_:
			_ink_bar(Vector2(span * 0.4, 0.0), 0.0, span * 0.8, 24.0, 0.90)


# ===================== 叠纸 · 折族（2026-11-02）=====================
## 这一族的读法：**纸的硬折吃光成棱 + 一一片片翻面的白纸**，不是墨、不是水、不是雷。
## 刻意与同位面前两位分开 ——
##   观澜亮在镜片（加色银白 + 碎棱），执烛亮在暗部（墨黑 + 影尖漏一点冷光），
##   叠纸亮在**棱线**（月白硬芯 + 迅速羽化 + 纸片翻面），并永远在落点旁留一道墨影说明「这是折过来的」。
## 折痕本体由 FoldVisual 持续显示，这里只做「这一拍落了」的瞬时层。
const FOLD_RIDGE_BASE := Vector2(512.0, 64.0)   ## 折棱贴图原生尺寸
const FOLD_DISC_BASE := 256.0                   ## 对位圆牌贴图原生直径
const FOLD_SHEET_BASE := 512.0                  ## 纸片贴图原生边长（外部生图）
## 生图纸片相对白色四边形必须收一档：它带卷边和明暗，玩家会当成一件**实物**去读尺度，
## 而白色四边形只被读成「一亮块」。原来那套 w=radius*1.5 是按亮块调的，
## 直接套上去实机截图里纸片比 BOSS 还大一圈，读成地上摊了一床凉席（2026-11-03 抓到）。
## 收小之后补一点不透明度，免得小片子在平均 62 的素纸地面上整个看不见。
const FOLD_SHEET_SHRINK := 0.42
const FOLD_PAPER := Color(0.90, 0.93, 0.98)     ## 月白：纸的本色
const FOLD_PAPER_WARM := Color(0.96, 0.89, 0.70) ## 淡金：第二条痕与它的纸影

func _build_fold() -> void:
	var mode := String(_cfg.get("fold_mode", "press"))
	var radius := _radius()
	var span := maxf(float(_form.get("range", radius)), 60.0)
	var tint: Color = _cfg.get("paper", FOLD_PAPER)
	match mode:
		"press":
			## 一掌按下：掌心的纸面塌成一片多边形纸片，边缘翘起处亮一条棱
			_fold_sheet(Vector2.ZERO, 0.0, radius * 1.5, radius * 1.2, 0.72)
			_fold_ridge(Vector2(radius * 0.42, 0.0), 0.0, radius * 1.06, 0.86)
			_fold_shadow(Vector2(0.0, 14.0), 0.0, radius * 0.92, 0.34)
			_spawn_flash(Vector2(radius * 0.3, 0.0), 0.8)
		"trace":
			## 贴着痕滑出去：一路被掀起的纸片 + 棱线上跑得飞快的光
			for i in 5:
				_fold_sheet(Vector2(span * (0.14 + 0.18 * float(i)),
					randf_range(-24.0, 24.0)), randf_range(-0.5, 0.5),
					span * 0.2, 46.0 - 5.0 * float(i), 0.60 - 0.07 * float(i))
			_fold_ridge(Vector2(span * 0.5, 0.0), 0.0, span, 0.92)
			_spawn_dash_streaks(6)
		"stride":
			## 跨缝：这头的纸面**合上**、那头的纸面**展开** —— 两枚圆牌之间拉一条短棱
			_fold_sheet(Vector2.ZERO, 0.42, radius * 1.1, radius * 1.1, 0.80)
			_fold_sheet(Vector2.ZERO, -0.30, radius * 0.74, radius * 0.74, 0.62)
			_fold_ridge(Vector2.ZERO, 0.0, radius * 1.3, 0.9)
			_spawn_flash(Vector2.ZERO, 1.15)
		"pressmark":
			## 押痕：一条痕被整条压过来 —— 两道平行棱 + 落点一枚纸印。
			## 第一版给三道、间距 46，实机是五条横着的激光（月白硬条在亮地面上连成一片）。
			for i in 2:
				_fold_ridge(Vector2(0.0, -34.0 + 68.0 * float(i)), 0.0,
					span * 1.05, 0.40 - 0.10 * float(i))
			_fold_sheet(Vector2(span * 0.5, 0.0), 0.0, radius * 1.4, radius * 1.2, 0.66)
			_spawn_flash(Vector2(span * 0.5, 0.0), 1.0)
		"shroud":
			## 叠掩：三层纸错着盖上来，最外层的棱最亮 —— 读得出「合上了一面」
			for i in 3:
				_fold_sheet(Vector2(randf_range(-16.0, 16.0), -10.0 * float(i)),
					randf_range(-0.22, 0.22), radius * (1.5 - 0.22 * float(i)),
					radius * (1.5 - 0.22 * float(i)), 0.30 + 0.16 * float(i))
			_fold_ridge(Vector2.ZERO, PI * 0.5, radius * 1.6, 0.56)
		"tear":
			## 碎痕：沿痕撕开 —— 棱线在中段断口，纸屑被撕力甩向两侧
			_fold_ridge(Vector2(span * 0.5, 0.0), 0.0, span, 1.0)
			for i in 7:
				var t := float(i) / 6.0
				var side := 1.0 if i % 2 == 0 else -1.0
				_fold_sheet(Vector2(span * t, side * randf_range(26.0, 92.0)),
					randf_range(-1.1, 1.1), randf_range(30.0, 62.0),
					randf_range(20.0, 40.0), 0.62)
			var w := float(_form.get("width", 220.0))
			_stretch_bar(Vector2(span * 0.5, 0.0), 0.0, span, w * 0.34,
				Color(tint.r, tint.g, tint.b, 0.16))
		"twin":
			## 双屏：两具纸影各自从圆牌里立起来，各带一条棱
			for i in 2:
				var off := Vector2(span * 0.34, (1.0 - 2.0 * float(i)) * radius * 0.5)
				_fold_sheet(off, 0.0, radius * 0.9, radius * 1.5, 0.66)
				_fold_ridge(off + Vector2(span * 0.3, 0.0), 0.0, span * 0.62, 0.8)
			_spawn_flash(Vector2.ZERO, 0.7)
		"triple":
			## 三重落纸：三个区各塌一片纸面，各区中心一条棱先亮再落 —— 一眼数得出三下
			for i in 3:
				var ang := TAU * float(i) / 3.0 - PI * 0.5
				var unit := Vector2(cos(ang), sin(ang))
				var at := unit * (span * 0.52)
				_fold_sheet(at, ang, radius * 1.25, radius * 1.05, 0.74)
				_fold_ridge(at, ang + PI * 0.5, radius * 1.1, 0.88)
				_fold_shadow(at + unit * 12.0, ang + PI * 0.5, radius * 0.9, 0.28)
			_spawn_flash(Vector2.ZERO, 1.4)
		_:
			_fold_ridge(Vector2(span * 0.5, 0.0), 0.0, span, 0.8)


## 一条折棱：月白硬芯 + 加色辉光（不加色读不出「纸吃光」）。
## ⚠ 芯可以硬，外圈必须羽化 —— 整族不许出现激光线似的一根硬条。
func _fold_ridge(center: Vector2, rot: float, length: float, alpha: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = fold_ridge_texture()
	s.centered = true
	s.position = center
	s.rotation = rot
	s.scale = Vector2(maxf(length, 1.0) / FOLD_RIDGE_BASE.x, 1.0)
	s.modulate = Color(FOLD_PAPER.r, FOLD_PAPER.g, FOLD_PAPER.b, alpha)
	s.material = additive_material()
	s.z_index = 4
	add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 0.0, 0.34)
	tw.parallel().tween_property(s, "scale", s.scale * Vector2(1.06, 1.5), 0.34)
	tw.tween_callback(s.queue_free)
	return s


## 一片翻面的纸：外部生图是一张真纸（一面月白一面青灰、带毛边与一道撕裂缺口），
## 比 white_texture() 那块纯色矩形多出的正是「翻面」这件事本身 —— 卷起来的那一
## 侧自带明暗，压扁动画 (1.14, 0.28) 才读得出纸在转。生图缺失时退回纯色四边形。
func _fold_sheet(center: Vector2, rot: float, w: float, h: float,
		alpha: float) -> Sprite2D:
	var s := Sprite2D.new()
	var sheet := skill_texture("fold_sheet")
	s.texture = sheet if sheet != null else white_texture()
	var base := FOLD_SHEET_BASE if sheet != null else 78.0
	if sheet != null:
		w *= FOLD_SHEET_SHRINK
		h *= FOLD_SHEET_SHRINK
	s.centered = true
	s.position = center
	s.rotation = rot
	s.scale = Vector2(maxf(w, 1.0) / base, maxf(h, 1.0) / base)
	s.modulate = Color(FOLD_PAPER.r, FOLD_PAPER.g, FOLD_PAPER.b,
			alpha * (0.62 if sheet != null else 0.52))
	s.z_index = 3
	add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 0.0, 0.4)
	tw.parallel().tween_property(s, "rotation", rot + 0.55, 0.4)
	tw.parallel().tween_property(s, "scale", s.scale * Vector2(1.14, 0.28), 0.4)
	tw.tween_callback(s.queue_free)
	return s


## 棱下那道墨影：折起来那半张纸压在下半张上的影子（普通混合、偏黑、短命）
func _fold_shadow(center: Vector2, rot: float, length: float, alpha: float) -> Sprite2D:
	var s := _stretch_bar(center, rot, length, 12.0, Color(0.04, 0.05, 0.07, alpha))
	s.z_index = 2
	return s


## 穿缝反馈：从这头到那头拉一条短棱 + 两头各立一片纸（FoldField 每帧结算里调）
static func play_fold_cross(host: Node, from: Vector2, to: Vector2, tag_no: int) -> void:
	if host == null or not host.is_inside_tree():
		return
	var tint := FOLD_PAPER if tag_no <= 1 else FOLD_PAPER_WARM
	for at in [from, to]:
		var spr := Sprite2D.new()
		spr.texture = fold_ridge_texture()
		spr.centered = true
		spr.material = additive_material()
		spr.global_position = at as Vector2
		spr.rotation = (to - (from as Vector2)).angle()
		spr.scale = Vector2(0.5, 1.0)
		spr.modulate = Color(tint, 0.82)
		spr.z_index = 5
		host.add_child(spr)
		var tw: Tween = spr.create_tween()
		tw.tween_property(spr, "modulate:a", 0.0, 0.3)
		tw.parallel().tween_property(spr, "scale", Vector2(1.3, 2.2), 0.3)
		tw.tween_callback(spr.queue_free)


## 折棱贴图（程序生成）。
## ⚠ 外部生图那批给过一张 fold_ridge.png，2026-11-03 用 tools/ab_fold_fx_textures.py
##   按实机显示尺寸对量后**没有采用**：它的羽化总厚只有 11px（这里 42px），
##   而且 RGB 中位只有 146 —— 三层叠完芯亮度 78，反而**低于**平均 77 的素纸地面，
##   等于把这套机制唯一的读数抹平。FoldVisual._lip 还要复用同一张当墨影，
##   硬细线只会画出一条细黑道，读不出「半张纸压在半张纸上」。
static var _fold_ridge_tex: ImageTexture = null


static func fold_ridge_texture() -> Texture2D:
	if _fold_ridge_tex != null:
		return _fold_ridge_tex
	var w := int(FOLD_RIDGE_BASE.x)
	var h := int(FOLD_RIDGE_BASE.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var mid := (h - 1) * 0.5
	for y in h:
		var dy := absf(float(y) - mid)
		## 芯收到 1.5px、外圈放宽到 17px：第一版给的是 1.9 / 12 + 加色叠层，
		## 实机截图里那是一条横贯屏幕的激光，完全不像「纸吃光的棱」。
		var core := exp(-pow(dy / 1.5, 2.0))
		var halo := exp(-pow(dy / 17.0, 2.0)) * 0.20
		var a := clampf(core + halo, 0.0, 1.0)
		for x in w:
			# 沿痕方向带一点纸纤维起伏，避免读成一把尺子
			var jitter := 1.0 + 0.14 * sin(float(x) * 0.121) + 0.09 * sin(float(x) * 0.031 + 1.7)
			## 两端收掉：痕的端点是圆牌，硬收口会和圆牌的光糊成一团白球
			var u := float(x) / float(w - 1)
			var taper := smoothstep(0.0, 0.12, u) * smoothstep(0.0, 0.12, 1.0 - u)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(a * jitter * taper, 0.0, 1.0)))
	_fold_ridge_tex = ImageTexture.create_from_image(img)
	return _fold_ridge_tex


## 对位圆牌贴图：玉佩式柔边圆盘，中心透亮、边缘化开，没有描边硬圈
## ⚠ 同批外部生图 fold_seam_disc.png 也没采用：它是个空心环（>=50% 峰值只出现在
##   半径 0.44~0.79，牌心 alpha 0.02），而 FoldSeam 把编号点画在牌心 ——
##   牌心空了，点数就飘在裸地面上，配对读数反而丢了。
static var _fold_disc_tex: ImageTexture = null


static func fold_disc_texture() -> Texture2D:
	if _fold_disc_tex != null:
		return _fold_disc_tex
	var s := int(FOLD_DISC_BASE)
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := float(s - 1) * 0.5
	for y in s:
		for x in s:
			var r := Vector2(float(x) - c, float(y) - c).length() / c
			var body := clampf(1.0 - smoothstep(0.44, 0.98, r), 0.0, 1.0)
			var inner := clampf(1.0 - smoothstep(0.0, 0.52, r), 0.0, 1.0) * 0.55
			## 外缘一圈压暗：亮盘直接落在亮地面上（或棱的端点光里）会整个化开，
			## 加一道暗环才读得出「这是一枚牌」而不是「这里在发光」
			var rim := exp(-pow((r - 0.70) / 0.085, 2.0)) * 0.55
			var lum := clampf(body * 0.62 + inner * body, 0.0, 1.0) * (1.0 - rim * 0.8)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, maxf(lum, rim * body * 0.42)))
	_fold_disc_tex = ImageTexture.create_from_image(img)
	return _fold_disc_tex


## 一段墨带：**真笔触贴图**拉伸 + 普通混合（不加色 —— 影是「减光」，不是「发光」）。## 起笔浓墨落在 center 侧、收笔飞白朝影尖，所以短段（缚影的墨指、分影的碎块）
## 也不会像柔边椭圆那样糊成一坨。
func _ink_bar(center: Vector2, rot: float, length: float, thickness: float,
		alpha: float) -> Sprite2D:
	var stroke: Texture2D = skill_texture("ink_stroke")
	var s := Sprite2D.new()
	s.texture = stroke if stroke != null else dot_texture()
	s.centered = true
	s.position = center
	s.rotation = rot
	var base := INK_STROKE_BASE if stroke != null else Vector2(78.0, 78.0)
	s.scale = Vector2(maxf(length, 1.0) / base.x, maxf(thickness, 1.0) / base.y)
	var ink: Color = _cfg.get("ink", Color(0.03, 0.04, 0.07))
	s.modulate = Color(ink.r, ink.g, ink.b, clampf(alpha, 0.0, 1.0))
	s.z_index = -1
	add_child(s)
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "modulate:a", 0.0, float(_cfg.get("lifetime", 0.4)) + 0.30)
	tw.tween_property(s, "scale:x", s.scale.x * 1.12, float(_cfg.get("lifetime", 0.4)) + 0.30)
	return s


## 一团地上的墨（影子的根部 / 落印点）—— 湿墨自然晕开的边缘，不是规则圆
func _ink_blob(center: Vector2, size_mult: float) -> Sprite2D:
	var blob: Texture2D = skill_texture("ink_blob")
	var s := Sprite2D.new()
	s.texture = blob if blob != null else dot_texture()
	s.centered = true
	s.position = center
	var ink: Color = _cfg.get("ink", Color(0.03, 0.04, 0.07))
	s.modulate = Color(ink.r, ink.g, ink.b, 0.55)
	if blob != null:
		s.scale = Vector2.ONE * size_mult
	else:
		s.scale = Vector2(0.9, 0.42) * size_mult
	s.z_index = -1
	add_child(s)
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "modulate:a", 0.0, float(_cfg.get("lifetime", 0.4)) + 0.35)
	var shrink := (Vector2(0.4, 0.19) * size_mult if blob == null
			else Vector2.ONE * size_mult * 0.45)
	tw.tween_property(s, "scale", shrink,
		float(_cfg.get("lifetime", 0.4)) + 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return s


## 身前那道墨弧：用软环贴图压扁，只取朝向前的一段（不是完整硬边圆环）
func _ink_arc(radius: float, thickness_mult: float, alpha: float) -> void:
	var s := Sprite2D.new()
	s.texture = ring_texture()
	s.centered = true
	s.position = Vector2(radius * 0.18, 0.0)
	s.scale = Vector2.ONE * clampf(radius / 97.3, 0.35, 7.0)
	var ink: Color = _cfg.get("ink", Color(0.03, 0.04, 0.07))
	s.modulate = Color(ink.r * 1.6, ink.g * 1.7, ink.b * 2.0, alpha)
	s.z_index = 2
	add_child(s)
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "modulate:a", 0.0, 0.34)
	tw.tween_property(s, "scale", s.scale * (1.0 + thickness_mult), 0.34) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


## 影尖亮点 / 残焰：整个族唯一的「发光」件，位置就是射程
func _spawn_tip(local_pos: Vector2, col: Color) -> Sprite2D:
	var flame: Texture2D = skill_texture("lamp_flame")
	var s := Sprite2D.new()
	s.texture = flame if flame != null else star_texture()
	s.centered = true
	s.material = additive_material()
	s.position = local_pos
	## 火苗不跟着本特效节点一起转：横躺的火焰读起来像弹道尾焰，
	## 竖着才像「影子的尽头烧着一盏灯」。
	s.rotation = -rotation
	var k := (62.0 / INK_FLAME_BASE.y) if flame != null else 0.72
	s.modulate = Color(col.r, col.g, col.b, 0.85)
	s.scale = Vector2.ONE * (k * 0.34)
	add_child(s)
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "scale", Vector2.ONE * k, 0.20) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "modulate:a", 0.0, 0.34)
	return s


## 墨带边上飘的几点碎影（数量由 SKILL_FX 的 sparks 控制）
func _ink_wisp(span: float, count: int) -> void:
	for i in count:
		var t := float(i + 1) / float(maxi(count, 1))
		var s := Sprite2D.new()
		s.texture = dot_texture()
		s.centered = true
		s.position = Vector2(span * t, randf_range(-16.0, 16.0))
		var ink: Color = _cfg.get("ink", Color(0.03, 0.04, 0.07))
		s.modulate = Color(ink.r, ink.g, ink.b, 0.50)
		s.scale = Vector2.ONE * randf_range(0.16, 0.34)
		s.z_index = 1
		add_child(s)
		var tw := s.create_tween().set_parallel(true)
		tw.tween_property(s, "position:y", s.position.y + randf_range(-26.0, 26.0), 0.4)
		tw.tween_property(s, "modulate:a", 0.0, 0.42)


# ===================== 突刺 =====================

func _build_thrust() -> void:
	var radius := _radius()
	var sword_cfg := ArtDB.get_visual("skill_sword_light")
	var tex_path := String(sword_cfg.get("texture", ""))
	var tex: Texture2D = load(tex_path) if tex_path != "" and ResourceLoader.exists(tex_path) else null
	var beams := 1
	if String(_cfg.get("motif", "")) == "pierce":
		beams = 3
	for i in beams:
		var beam := Sprite2D.new()
		if tex != null:
			beam.texture = tex
		else:
			beam.texture = streak_texture()
		beam.centered = true
		beam.material = additive_material()
		beam.modulate = Color(0.9, 1.0, 1.0, 0.98 if i == 0 else 0.24)
		beam.rotation = -PI * 0.5
		var length := radius * (1.0 if i == 0 else 0.72)
		beam.position = Vector2(radius * 0.5 - 58.0 * float(i if String(_cfg.get("motif", "")) == "pierce" else 0), 0.0)
		beam.scale = Vector2(0.80, length / 384.0)
		beam.z_index = 3
		add_child(beam)
		var tw := beam.create_tween().set_parallel(true)
		tw.tween_property(beam, "scale:y", length / 384.0 * 1.08, 0.16) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_property(beam, "modulate:a", 0.0, 0.24)
	# 剑光外面再铺一层更宽的冷光，让“突刺”不是一根细线
	var glow_beam := Sprite2D.new()
	if tex != null:
		glow_beam.texture = tex
	else:
		glow_beam.texture = streak_texture()
	glow_beam.centered = true
	glow_beam.material = additive_material()
	glow_beam.modulate = Color(0.45, 0.82, 1.0, 0.20)
	glow_beam.rotation = -PI * 0.5
	glow_beam.position = Vector2(radius * 0.5, 0.0)
	glow_beam.scale = Vector2(1.35, radius / 384.0 * 1.04)
	glow_beam.z_index = 2
	add_child(glow_beam)
	var glow_tw := glow_beam.create_tween().set_parallel(true)
	glow_tw.tween_property(glow_beam, "scale:y", radius / 384.0 * 1.12, 0.18)
	glow_tw.tween_property(glow_beam, "modulate:a", 0.0, 0.24)
	_spawn_flash(Vector2(radius, 0.0), 1.4)
	_spawn_sparks(radius * 0.5, deg_to_rad(26.0))
	_spawn_dust(0.0)
	if int(_cfg.get("dash_streaks", 0)) > 0:
		_spawn_dash_streaks(int(_cfg.get("dash_streaks", 6)))


# ===================== 投射物起手 / 地面招式 =====================

func _build_cast_burst() -> void:
	_spawn_flash(Vector2(0.0, -4.0), 0.8)
	_spawn_sparks(80.0, PI)
	_spawn_dust(0.0)
	var glow := Sprite2D.new()
	glow.texture = dot_texture()
	glow.centered = true
	glow.material = additive_material()
	glow.modulate = Color(_cfg.get("glow", Color.ORANGE).r, _cfg.get("glow", Color.ORANGE).g,
		_cfg.get("glow", Color.ORANGE).b, 0.26)
	glow.scale = Vector2(1.1, 1.1)
	glow.z_index = 1
	add_child(glow)
	var tw := glow.create_tween().set_parallel(true)
	tw.tween_property(glow, "scale", Vector2(1.8, 1.8), 0.35)
	tw.tween_property(glow, "modulate:a", 0.0, 0.35)


func _build_stomp() -> void:
	# 视觉半径 = 圆形判定半径（旧版多乘 1.15，冲击波与裂纹明显大于实际命中圈）
	var radius := maxf(60.0, float(_form.get("range", 120.0)))
	var ring_alpha := clampf(float(_cfg.get("ring_alpha", 1.0)), 0.2, 1.5)
	_spawn_shockwave(radius * 0.95, 0.24 * ring_alpha)
	var tw_delay := create_tween()
	tw_delay.tween_interval(0.07)
	tw_delay.tween_callback(func() -> void: _spawn_shockwave(radius * 0.72, 0.18 * ring_alpha))
	# 地面裂纹：使用程序化裂痕贴图，中心对齐脚下
	var crack := Sprite2D.new()
	crack.texture = skill_texture(String(_cfg.get("crack_texture", "stomp_crack")))
	crack.centered = true
	crack.modulate = Color(1.0, 0.92, 0.78, 0.0)
	# 暖化一剑开天的冷色裂纹，让它读作虎煞踏地
	crack.self_modulate = _cfg.get("crack_tint", Color(1.0, 0.62, 0.32, 1.0))
	if crack.texture != null:
		crack.scale = Vector2.ONE * (radius * 2.1 / 512.0)
	crack.rotation = randf_range(0.0, TAU)
	crack.z_index = -1
	add_child(crack)
	var ctw := crack.create_tween()
	ctw.tween_property(crack, "modulate:a", 0.72, 0.08)
	ctw.tween_property(crack, "modulate:a", 0.0, 0.9)
	# 尘、碎石、火花
	var dust := make_particles(smoke_texture(), int(_cfg.get("dust", 40)), 1.15, -1, false)
	dust.one_shot = true
	dust.explosiveness = 0.9
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 34.0
	dust.direction = Vector2.RIGHT
	dust.spread = 180.0
	dust.initial_velocity_min = 55.0
	dust.initial_velocity_max = 220.0
	dust.gravity = Vector2(0.0, -34.0)
	dust.damping_min = 25.0
	dust.damping_max = 70.0
	dust.scale_amount_min = 0.35
	dust.scale_amount_max = 0.85
	dust.scale_amount_curve = make_curve([Vector2(0.0, 0.5), Vector2(0.3, 1.25), Vector2(1.0, 0.3)])
	dust.color_ramp = make_gradient(
		PackedFloat32Array([0.0, 0.16, 1.0]),
		PackedColorArray([
			Color(0.34, 0.25, 0.16, 0.0),
			Color(0.40, 0.29, 0.18, 0.42),
			Color(0.22, 0.16, 0.10, 0.0),
		]))
	dust.z_index = -1
	add_child(dust)
	dust.restart()
	dust.emitting = true
	var rocks := make_particles(rock_texture(), 18, 0.85, 2, false)
	rocks.one_shot = true
	rocks.explosiveness = 1.0
	rocks.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	rocks.emission_sphere_radius = 24.0
	rocks.direction = Vector2.RIGHT
	rocks.spread = 180.0
	rocks.initial_velocity_min = 120.0
	rocks.initial_velocity_max = 330.0
	rocks.gravity = Vector2(0.0, 440.0)
	rocks.angular_velocity_min = -300.0
	rocks.angular_velocity_max = 300.0
	rocks.scale_amount_min = 0.10
	rocks.scale_amount_max = 0.24
	rocks.color_ramp = make_gradient(
		PackedFloat32Array([0.0, 1.0]),
		PackedColorArray([Color(1.0, 0.78, 0.48, 0.9), Color(0.75, 0.52, 0.30, 0.0)]))
	rocks.z_index = 2
	add_child(rocks)
	rocks.restart()
	rocks.emitting = true
	_spawn_sparks(radius * 0.6, PI)
	_spawn_flash(Vector2.ZERO, 1.2)


func _build_field() -> void:
	var radius := _radius()
	var field := Sprite2D.new()
	field.texture = skill_texture("field")
	field.centered = true
	field.modulate = Color(1.0, 0.86, 0.68, 0.0)
	if field.texture != null:
		field.scale = Vector2.ONE * (radius * 2.25 / 512.0)
	field.material = additive_material()
	field.z_index = -2
	add_child(field)
	var ft := field.create_tween()
	ft.tween_property(field, "modulate:a", 0.50, 0.16)
	ft.tween_property(field, "modulate:a", 0.0, 0.8)
	ft.parallel().tween_property(field, "rotation", 0.55, 1.0)
	ft.parallel().tween_property(field, "scale", field.scale * 1.06, 1.0)
	var dome := Sprite2D.new()
	dome.texture = dot_texture()
	dome.centered = true
	dome.material = additive_material()
	dome.modulate = Color(0.9, 0.55, 0.18, 0.12)
	dome.scale = Vector2(radius * 2.3 / 128.0, radius * 2.3 / 128.0)
	dome.z_index = -1
	add_child(dome)
	# 悬在界内的刀气，向心收拢
	var blade_tex := skill_texture("blade_qi")
	for i in 6:
		var ang := TAU * float(i) / 8.0 + randf_range(-0.12, 0.12)
		var rr := radius * randf_range(0.62, 0.92)
		var blade := Sprite2D.new()
		blade.texture = blade_tex
		blade.centered = true
		blade.material = additive_material()
		blade.modulate = Color(1.0, 0.82, 0.55, 0.28)
		blade.scale = Vector2(0.22, 0.22)
		blade.position = Vector2(cos(ang), sin(ang)) * rr
		blade.rotation = ang + PI * 0.5
		blade.z_index = 1
		add_child(blade)
		var bt := blade.create_tween().set_parallel(true)
		bt.tween_property(blade, "position", Vector2(cos(ang), sin(ang)) * rr * 0.35, 0.55) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		bt.tween_property(blade, "modulate:a", 0.0, 0.55)
	var p := make_particles(star_texture(), int(_cfg.get("sparks", 30)), 0.7, 2, true)
	p.one_shot = true
	p.explosiveness = 0.2
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RING
	p.emission_ring_radius = radius * 0.9
	p.emission_ring_inner_radius = radius * 0.55
	p.direction = Vector2.RIGHT
	p.spread = 180.0
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 80.0
	p.radial_accel_min = -140.0
	p.radial_accel_max = -80.0
	p.tangential_accel_min = 40.0
	p.tangential_accel_max = 110.0
	p.gravity = Vector2.ZERO
	p.damping_min = 10.0
	p.damping_max = 30.0
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.14
	p.color_ramp = make_gradient(
		PackedFloat32Array([0.0, 0.15, 1.0]),
		PackedColorArray([
			Color(1.0, 0.8, 0.4, 0.0), Color(1.0, 0.92, 0.68, 0.85), Color(1.0, 0.55, 0.2, 0.0)]))
	add_child(p)
	p.restart()
	p.emitting = true
	_spawn_flash(Vector2.ZERO, 1.4)
	# 多跳领域（阴风蚀骨）：每跳在圈上闪一道八卦环 —— 玩家能数出「这是第几跳」，
	# 而不是一闪而过看不出跳数
	var pulses := int(_cfg.get("field_pulses", 1))
	if pulses > 1:
		var gap := float(_cfg.get("field_pulse_gap", 0.45))
		for i in pulses:
			var tw := create_tween()
			tw.tween_interval(gap * float(i))
			tw.tween_callback(func() -> void:
				if is_instance_valid(self):
					_spawn_bagua_ring(radius * 1.9, -1.4, 0.62))


func _spawn_shockwave(radius: float, alpha: float) -> void:
	var ring := Sprite2D.new()
	ring.texture = ring_texture()
	ring.centered = true
	ring.material = additive_material()
	var ring_col: Color = _cfg.get("ring", Color(1.0, 0.64, 0.26))
	ring.modulate = Color(ring_col.r, ring_col.g, ring_col.b, 0.0)
	ring.scale = Vector2(radius * 2.0 / 256.0, radius * 2.0 / 256.0) * 0.2
	ring.z_index = -1
	add_child(ring)
	var target := Vector2(radius * 2.0 / 256.0, radius * 2.0 / 256.0)
	var tw := ring.create_tween()
	tw.tween_property(ring, "modulate:a", alpha, 0.06)
	tw.parallel().tween_property(ring, "scale", target * 1.25, 0.5) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.36)


# ===================== 万剑归宗 =====================

func _spawn_summon_gate() -> void:
	if not is_instance_valid(_caster):
		return
	var host := get_parent()
	if host == null:
		return
	var gate := Node2D.new()
	gate.z_index = 1
	host.add_child(gate)
	var body := _body_center(_caster)
	gate.global_position = _caster.global_position + body
	var glow := Sprite2D.new()
	glow.texture = dot_texture()
	glow.centered = true
	glow.material = additive_material()
	glow.modulate = Color(0.35, 0.8, 1.0, 0.0)
	glow.scale = Vector2(1.5, 1.5)
	glow.z_index = -1
	gate.add_child(glow)
	var gtw := glow.create_tween()
	gtw.tween_property(glow, "modulate:a", 0.30, 0.25)
	gtw.tween_property(glow, "modulate:a", 0.0, 0.7)
	var sword_cfg := ArtDB.get_visual("boss_sword_projectile")
	var sword_tex: Texture2D = null
	var sp := String(sword_cfg.get("texture", ""))
	if sp != "" and ResourceLoader.exists(sp):
		sword_tex = load(sp)
	for i in 10:
		var ang := TAU * float(i) / 10.0 + randf_range(-0.09, 0.09)
		var rr := 88.0 + randf_range(-12.0, 16.0)
		var inward := -Vector2(cos(ang), sin(ang))
		var sword := Sprite2D.new()
		sword.texture = sword_tex
		if sword_tex == null:
			sword.texture = streak_texture()
		sword.centered = true
		sword.material = additive_material()
		sword.modulate = Color(0.68, 0.94, 1.0, 0.0)
		sword.position = Vector2(cos(ang), sin(ang)) * rr
		sword.rotation = atan2(inward.y, inward.x) - PI * 0.5 + randf_range(-0.10, 0.10)
		var s := (48.0 + randf_range(-6.0, 10.0)) / maxf(float(sword.texture.get_height()), 1.0) if sword_tex != null else 0.5
		sword.scale = Vector2(s, s)
		sword.z_index = 1
		gate.add_child(sword)
		var tw := sword.create_tween()
		tw.tween_interval(0.06 * float(i))
		tw.tween_property(sword, "modulate:a", 0.8, 0.16)
		tw.tween_interval(0.22)
		tw.tween_property(sword, "modulate:a", 0.0, 0.3)
		var spark := Sprite2D.new()
		spark.texture = dot_texture()
		spark.centered = true
		spark.material = additive_material()
		spark.modulate = Color(0.55, 0.9, 1.0, 0.0)
		spark.scale = Vector2(0.28, 0.28)
		spark.position = sword.position
		spark.z_index = 0
		gate.add_child(spark)
		var st := spark.create_tween()
		st.tween_interval(0.06 * float(i))
		st.tween_property(spark, "modulate:a", 0.35, 0.2)
		st.tween_property(spark, "modulate:a", 0.0, 0.4)
	var tw2 := gate.create_tween().set_parallel(true)
	tw2.tween_property(gate, "rotation", 0.5, 0.95).set_trans(Tween.TRANS_SINE)
	tw2.tween_property(gate, "scale", Vector2(1.06, 1.06), 0.95)
	gate.get_tree().create_timer(1.1).timeout.connect(gate.queue_free)


func _build_summon_burst() -> void:
	_spawn_flash(Vector2.ZERO, 1.2)
	_spawn_sparks(120.0, PI)
	_spawn_dust(0.0)
	for i in 10:
		var ang := TAU * float(i) / 10.0
		var streak := Sprite2D.new()
		streak.texture = streak_texture()
		streak.centered = true
		streak.material = additive_material()
		streak.modulate = Color(0.55, 0.9, 1.0, 0.55)
		streak.position = Vector2(cos(ang), sin(ang)) * 30.0
		streak.rotation = ang - PI * 0.5
		streak.scale = Vector2(0.16, 0.35)
		streak.z_index = 3
		add_child(streak)
		var tw := streak.create_tween().set_parallel(true)
		tw.tween_property(streak, "position", Vector2(cos(ang), sin(ang)) * 170.0, 0.3) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_property(streak, "modulate:a", 0.0, 0.32)


# ===================== 纳势反击 =====================

func _build_ward_release() -> void:
	_build_slash()
	# 护势碎成金光，而不是留一圈硬环
	var burst := Sprite2D.new()
	burst.texture = dot_texture()
	burst.centered = true
	burst.material = additive_material()
	burst.modulate = Color(1.0, 0.82, 0.46, 0.46)
	burst.scale = Vector2(0.85, 0.85)
	burst.z_index = 2
	add_child(burst)
	var tw := burst.create_tween().set_parallel(true)
	tw.tween_property(burst, "scale", Vector2(2.4, 2.4), 0.34) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(burst, "modulate:a", 0.0, 0.38)


# ===================== 满势断岳 =====================

func _build_peak() -> void:
	_build_slash()
	_build_peak_extras(_radius())


func _build_peak_extras(radius: float) -> void:
	var crack := Sprite2D.new()
	crack.texture = skill_texture("stomp_crack")
	crack.centered = true
	crack.modulate = Color(1.0, 0.85, 0.6, 0.0)
	crack.scale = Vector2.ONE * (radius * 1.8 / 512.0)
	crack.rotation = randf_range(-0.3, 0.3)
	crack.position = Vector2(radius * 0.25, 0.0)
	crack.z_index = -1
	add_child(crack)
	var tw := crack.create_tween()
	tw.tween_property(crack, "modulate:a", 0.7, 0.08)
	tw.tween_property(crack, "modulate:a", 0.0, 0.9)
	var rocks := make_particles(rock_texture(), 20, 0.9, 2, false)
	rocks.one_shot = true
	rocks.explosiveness = 1.0
	rocks.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	rocks.emission_sphere_radius = 28.0
	rocks.direction = Vector2.RIGHT
	rocks.spread = 120.0
	rocks.initial_velocity_min = 130.0
	rocks.initial_velocity_max = 360.0
	rocks.gravity = Vector2(0.0, 460.0)
	rocks.angular_velocity_min = -320.0
	rocks.angular_velocity_max = 320.0
	rocks.scale_amount_min = 0.12
	rocks.scale_amount_max = 0.28
	rocks.color_ramp = make_gradient(
		PackedFloat32Array([0.0, 1.0]),
		PackedColorArray([Color(1.0, 0.82, 0.55, 0.95), Color(0.8, 0.58, 0.34, 0.0)]))
	add_child(rocks)
	rocks.restart()
	rocks.emitting = true
	_spawn_flash(Vector2(radius * 0.55, 0.0), 1.8)


# ===================== 刀痕 =====================

func _build_scar_burst() -> void:
	_spawn_arc(96.0, deg_to_rad(62.0), 0.35, 0.0, 1.0, randf() * 10.0)
	_spawn_arc(76.0, deg_to_rad(48.0), 0.28, 150.0, 0.7, randf() * 10.0)
	_spawn_sparks(90.0, PI)
	_spawn_dust(0.0)
	_spawn_flash(Vector2.ZERO, 1.0)


# ===================== 弹反 / 极限闪避（2026-10-25 改版）=====================

## 一个加色柔光 Sprite：贴图居中、初始全透明，撑开与淡出由调用方排
func _soft_sprite(tex: Texture2D, color: Color, z: int) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = true
	spr.material = additive_material()
	spr.modulate = Color(color.r, color.g, color.b, 0.0)
	spr.z_index = z
	return spr


## 弹反接触点：一颗白点 + 一枚小星芒 + 零星几点碎星，就这些。
## 柔光冲击环 / 散烟 / 完美专属月牙在 2026-10-26 按用户要求整体取消：
## 弹反是高频动作，一屏可能连弹四五次，华丽特效只会糊住战场。
func _build_parry_burst() -> void:
	var life := float(_cfg.get("lifetime", 0.20))
	_spawn_parry_flash(float(_cfg.get("core_diameter", 24.0)),
		float(_cfg.get("flare_diameter", 54.0)), life)
	_spawn_parry_sparks(life)


## 接触点两层：白点定"打在哪"，星芒给"磕开了"的形状。
## ⚠ 第一帧就必须是满亮度 —— 旧版那 0.03 秒淡入 + 0.05 秒延迟起的外圈，
##   会让特效比玩家的动作慢半拍，而弹反读的就是那一下接触。
##   爆开感全部交给缩放（TRANS_EXPO 起手即最快），亮度只减不加。
func _spawn_parry_flash(core_diameter: float, flare_diameter: float, life: float) -> void:
	var hot: Color = _cfg.get("hot", Color(1.0, 0.98, 0.88))
	var s := core_diameter / 128.0
	var dot := _soft_sprite(dot_texture(), hot, 4)
	dot.modulate.a = 0.95
	dot.scale = Vector2(s, s) * 0.55
	add_child(dot)
	var tw := dot.create_tween()
	tw.tween_property(dot, "scale", Vector2(s, s), life * 0.35) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(dot, "modulate:a", 0.0, life)
	# 星芒随机转一个角度：否则每次弹反都是同一个正十字，看三次就穿帮了
	var fs := flare_diameter / 96.0
	var star := _soft_sprite(star_texture(), hot, 5)
	star.modulate.a = 0.9
	star.rotation = randf() * TAU
	star.scale = Vector2(fs, fs) * 0.62
	add_child(star)
	var stw := star.create_tween()
	stw.tween_property(star, "scale", Vector2(fs, fs), life * 0.45) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	stw.parallel().tween_property(star, "modulate:a", 0.0, life)


## 金属碎星：星形贴图沿局部 +X（= 弹开方向）扇形喷出，节点本身已按 dir 旋转过
func _spawn_parry_sparks(life: float) -> void:
	var count := int(_cfg.get("spark_count", 0))
	if count <= 0:
		return
	var hot: Color = _cfg.get("hot", Color.WHITE)
	var spark: Color = _cfg.get("spark", Color(1.0, 0.80, 0.30))
	var p := make_particles(star_texture(), count, life * 1.5, 3, true)
	p.one_shot = true
	p.explosiveness = 1.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 4.0
	p.direction = Vector2.RIGHT
	# spark_fan_deg 写的是全张角，CPUParticles2D.spread 是半角
	p.spread = clampf(float(_cfg.get("spark_fan_deg", 62.0)), 20.0, 200.0) * 0.5
	# 飞距换算成初速：碎星要在 life 内飞到 spark_dist，而不是凭空消失
	var t := maxf(life * 1.15, 0.08)
	p.initial_velocity_min = float(_cfg.get("spark_dist_min", 22.0)) / t
	p.initial_velocity_max = float(_cfg.get("spark_dist_max", 62.0)) / t
	# 阻尼给足：碎星是「磕出来的金属屑」，甩出去就该很快停；飘太远又变成烟花
	p.damping_min = 150.0
	p.damping_max = 300.0
	# 本节点被旋转成了弹开方向，局部 (0,1) 不再是"下"，重力得先转回世界坐标
	p.gravity = Vector2(0.0, 34.0).rotated(-rotation)
	p.scale_amount_min = 0.035
	p.scale_amount_max = 0.085
	p.scale_amount_curve = make_curve([Vector2(0.0, 1.0), Vector2(0.40, 0.82), Vector2(1.0, 0.0)])
	p.color_ramp = make_gradient(
		PackedFloat32Array([0.0, 0.05, 0.42, 1.0]),
		PackedColorArray([
			Color(hot.r, hot.g, hot.b, 0.0),
			Color(hot.r, hot.g, hot.b, 1.0),
			Color(spark.r, spark.g, spark.b, 0.80),
			Color(spark.r, spark.g, spark.b, 0.0),
		]))
	p.position = Vector2(0.0, -2.0)
	add_child(p)
	p.restart()
	p.emitting = true


## 柔光冲击环。不用 _spawn_shockwave：它的生长时长写死在技能节奏上（0.5s），
## 弹反要的是 0.1 秒里"啪"地打开，扩散必须跟着档位的 lifetime 走。
func _spawn_soft_ring(radius: float, alpha: float, color: Color, life: float) -> void:
	var ring := _soft_sprite(ring_texture(), color, -1)
	var target := Vector2(radius * 2.0 / 256.0, radius * 2.0 / 256.0)
	ring.scale = target * 0.24
	ring.rotation = randf() * TAU
	add_child(ring)
	var tw := ring.create_tween()
	tw.tween_property(ring, "modulate:a", alpha, 0.05)
	tw.parallel().tween_property(ring, "scale", target, life * 0.55) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, life * 0.80)


## 极限闪避：沿闪避方向拖一道冷蓝光带 + 一圈小柔光环 + 少量飘散光点。
## 刻意没有星芒和碎星 —— 闪避是"穿过去了"，不是"弹开了"。
func _build_dodge_slip() -> void:
	var life := float(_cfg.get("lifetime", 0.34))
	var hot: Color = _cfg.get("hot", Color(0.88, 0.98, 1.0))
	var core: Color = _cfg.get("core", Color(0.46, 0.82, 1.0))
	var glow: Color = _cfg.get("glow", Color(0.22, 0.55, 0.94))
	var length := float(_cfg.get("streak_length", 152.0))
	var width := float(_cfg.get("streak_width", 36.0))
	var layers := clampi(int(_cfg.get("streak_layers", 3)), 1, 4)
	for i in layers:
		# 外层宽而淡、内层窄而亮：光带要有厚度层次，不能读成一根线
		var t := float(i) / float(maxi(layers - 1, 1))
		var streak := _soft_sprite(streak_texture(), glow.lerp(core, t), 2)
		# streak_texture 的长轴是自身 +Y，-90° 才对上父节点的 +X（= 闪避方向）
		streak.rotation_degrees = -90.0
		var sc_x := width * (1.0 - 0.55 * t) / 64.0
		var sc_y := length * (0.72 + 0.28 * t) / 256.0
		streak.scale = Vector2(sc_x, sc_y * 0.35)
		streak.position = Vector2(-length * 0.16 * (1.0 - t), 0.0)
		add_child(streak)
		var tw := streak.create_tween()
		tw.tween_property(streak, "modulate:a", 0.26 + 0.42 * t, 0.04)
		tw.parallel().tween_property(streak, "scale", Vector2(sc_x, sc_y), 0.13) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_property(streak, "modulate:a", 0.0, life)
	var ring_radius := float(_cfg.get("ring_radius", 0.0))
	if ring_radius > 0.0:
		_spawn_soft_ring(ring_radius, float(_cfg.get("ring_alpha", 0.34)), core, life)
	var motes := int(_cfg.get("mote_count", 0))
	if motes > 0:
		var p := make_particles(dot_texture(), motes, life * 1.8, 3, true)
		p.one_shot = true
		p.explosiveness = 0.8
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 24.0
		p.direction = Vector2.RIGHT
		p.spread = 180.0
		p.initial_velocity_min = 6.0
		p.initial_velocity_max = 26.0
		p.gravity = Vector2.ZERO
		p.damping_min = 8.0
		p.damping_max = 24.0
		p.scale_amount_min = 0.05
		p.scale_amount_max = 0.14
		p.scale_amount_curve = make_curve([Vector2(0.0, 0.5), Vector2(0.3, 1.0), Vector2(1.0, 0.0)])
		p.color_ramp = make_gradient(
			PackedFloat32Array([0.0, 0.12, 0.6, 1.0]),
			PackedColorArray([
				Color(core.r, core.g, core.b, 0.0),
				Color(hot.r, hot.g, hot.b, 0.75),
				Color(core.r, core.g, core.b, 0.40),
				Color(core.r, core.g, core.b, 0.0),
			]))
		add_child(p)
		p.restart()
		p.emitting = true


# ===================== 工具 =====================

func _radius() -> float:
	var r := float(_form.get("range", 120.0))
	var shape := String(_form.get("hit_shape", ""))
	# 直线突刺 / 圆形领域：视觉半径直接等于判定半径
	if shape == MoveDB.SHAPE_LINE:
		return clampf(r, 60.0, 520.0)
	if shape == MoveDB.SHAPE_CIRCLE:
		return clampf(r, 60.0, 420.0)
	var motif := String(_cfg.get("motif", "slash"))
	if motif == "qi" or motif == "cloud" or motif == "volley" or motif == "orb":
		r = minf(r, 220.0)
	elif motif == "peak":
		r = minf(r, 320.0)
	# 扇形刀光面片的实际外缘约为 quads 半宽的 1.125 倍，0.85 正好补偿回判定半径
	var mult := float(_cfg.get("radius_mult", 1.0))
	return clampf(r * 0.85 * mult, 70.0, 380.0)


func _body_center(node: Node2D) -> Vector2:
	# 公开的 body_center() 才是准数（BossBase 从骨骼算，玩家同理）；
	# 旧的下划线私有名留着兜底。以前只查私有名 → 查不到就退回 (0,-30)，
	# 于是所有近战特效都比真正躯干中心低一截（两仪这里差 55 px）。
	for m in ["body_center", "_body_center"]:
		if node.has_method(m):
			var v = node.call(m)
			if v is Vector2:
				return v
	return Vector2(0.0, -30.0)


func _swing_weapon() -> void:
	if not is_instance_valid(_caster):
		return
	var style := String(_cfg.get("weapon", "none"))
	if style == "none":
		return
	var weapon = _caster.get("weapon")
	if weapon == null:
		weapon = _caster.get_node_or_null("WeaponOrbit")
	if weapon == null or not weapon.has_method("sweep"):
		return
	var seg := {}
	match style:
		"vertical":
			seg = {"from_deg": -116.0, "to_deg": 30.0, "sweep_time": 0.20, "windup": true}
		"thrust":
			seg = {"from_deg": -10.0, "to_deg": 10.0, "sweep_time": 0.09, "reach_mult": 1.55}
		"spin":
			seg = {"from_deg": -160.0, "to_deg": 200.0, "sweep_time": 0.27, "spin_turns": 1.0}
		"lift":
			seg = {"from_deg": 70.0, "to_deg": -100.0, "sweep_time": 0.18}
		"raise":
			seg = {"from_deg": -40.0, "to_deg": -150.0, "sweep_time": 0.22}
		_:
			seg = {"from_deg": -68.0, "to_deg": 68.0, "sweep_time": 0.16}
	weapon.sweep(_dir, seg)


func _shake() -> void:
	if not is_instance_valid(_caster) or not _caster.has_method("_screen_shake"):
		return
	var strength := float(_cfg.get("shake", 0.0))
	if strength <= 0.0:
		return
	_caster.call("_screen_shake", strength, clampf(0.10 + strength * 0.012, 0.10, 0.22))


func _color_vec(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


# ===================== 程序化纹理 / 粒子工具 =====================

static func additive_material() -> CanvasItemMaterial:
	if _add_material_cache == null:
		_add_material_cache = CanvasItemMaterial.new()
		_add_material_cache.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_material_cache


static func white_texture() -> Texture2D:
	if _tex_cache.has("white"):
		return _tex_cache["white"]
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["white"] = tex
	return tex


## 柔光条贴图（2026-11-04 用户报「执灯有些技能特效还是硬边色块」）。
## `_stretch_bar` 用的是一张 4×4 纯白图，拉成任意宽高就是四条硬边 ——
## 照骨那种三层叠色块尤其明显，正对着既有偏好「不用折线/硬边圆环，范围=判定、可读性优先」。
## 这张 256×64：纵向高斯（σ=9.6 → 可见芯约占全高 35%，其余是晕），
## 横向两端各 12% smoothstep 收口（硬边的另一半就是"端头垂直一刀"）。
## ⚠ 别和已有的 `streak_texture()`（64×256 纵向、带 sin 波动，给流丝/拖尾用）混名，
##   两者缓存键也不同（"lightbar" vs "streak"）—— 重名直接是 parse error。
static func lightbar_texture() -> Texture2D:
	if _tex_cache.has("lightbar"):
		return _tex_cache["lightbar"]
	var w := 256
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var mid := (h - 1) * 0.5
	var sig := 9.6
	for y in h:
		var dy := (float(y) - mid) / sig
		var gv := exp(-dy * dy)
		for x in w:
			var t := float(x) / float(w - 1)
			var taper := smoothstep(0.0, 0.12, t) * smoothstep(0.0, 0.12, 1.0 - t)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(gv * taper, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["lightbar"] = tex
	return tex


static func dot_texture() -> Texture2D:
	if _tex_cache.has("dot"):
		return _tex_cache["dot"]
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			var a := exp(-d * d * 5.1) * 0.9 + exp(-d * d * 24.0) * 0.35
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["dot"] = tex
	return tex


static func star_texture() -> Texture2D:
	if _tex_cache.has("star"):
		return _tex_cache["star"]
	var size := 96
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var nx := (x - c) / c
			var ny := (y - c) / c
			var core := exp(-(nx * nx + ny * ny) * 9.0)
			var h := exp(-abs(nx) * 17.0) * exp(-abs(ny) * 3.0)
			var v := exp(-abs(ny) * 17.0) * exp(-abs(nx) * 3.0)
			var a := clampf(core * 0.85 + h * 0.7 + v * 0.7, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["star"] = tex
	return tex


static func smoke_texture() -> Texture2D:
	if _tex_cache.has("smoke"):
		return _tex_cache["smoke"]
	var size := 96
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var nx := (x - c) / c
			var ny := (y - c) / c
			var d := sqrt(nx * nx + ny * ny)
			var lobe := 0.72 + 0.28 * sin(nx * 8.0 + ny * 5.0)
			var a := exp(-d * d * 3.6) * lobe
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["smoke"] = tex
	return tex


static func ring_texture() -> Texture2D:
	if _tex_cache.has("ring"):
		return _tex_cache["ring"]
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			var ang := atan2(y - c, x - c)
			var edge := 0.76 + 0.030 * sin(ang * 5.0 + 1.7) + 0.018 * sin(ang * 11.0 + 0.4)
			var t := (d - edge) / (0.085 + 0.020 * sin(ang * 7.0 + 2.1))
			var a := exp(-t * t) * (0.60 + 0.40 * (0.5 + 0.5 * sin(ang * 6.0 + 0.8)))
			a += exp(-pow((d - edge) / 0.24, 2.0)) * 0.10
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["ring"] = tex
	return tex


## 碎镜棱贴图：不规则五边形银片，边缘亮、中心透。
## 用一张共用纹理 + 每片随机缩放/旋转，比一排白条更像玻璃。
static func mirror_shard_texture() -> Texture2D:
	if _tex_cache.has("mirror_shard"):
		return _tex_cache["mirror_shard"]
	var size := 128
	var poly := PackedVector2Array([
		Vector2(60.0, 3.0), Vector2(99.0, 30.0), Vector2(88.0, 92.0),
		Vector2(55.0, 126.0), Vector2(24.0, 95.0), Vector2(30.0, 28.0),
	])
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var p := Vector2(x, y)
			if not Geometry2D.is_point_in_polygon(p, poly):
				continue
			var d := 999.0
			for i in poly.size():
				d = minf(d, _point_seg_dist(p, poly[i], poly[(i + 1) % poly.size()]))
			var a := 0.16 + 0.84 * exp(-d / 8.0)
			a *= 0.62 + 0.38 * (float(y) / float(size))
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["mirror_shard"] = tex
	return tex


static func streak_texture() -> Texture2D:
	if _tex_cache.has("streak"):
		return _tex_cache["streak"]
	var w := 64
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx := (w - 1) * 0.5
	for y in h:
		var v := float(y) / float(h - 1)
		var long_fade := smoothstep(0.0, 0.2, v) * (1.0 - smoothstep(0.82, 1.0, v))
		for x in w:
			var u := (x - cx) / cx
			var a := exp(-u * u * 12.0) * long_fade * (0.55 + 0.45 * sin(v * 18.0))
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["streak"] = tex
	return tex


static func rock_texture() -> Texture2D:
	if _tex_cache.has("rock"):
		return _tex_cache["rock"]
	var path := "res://assets/effects/skills/tiger_rock.png"
	if ResourceLoader.exists(path):
		_tex_cache["rock"] = load(path)
		return _tex_cache["rock"]
	return dot_texture()


## 雷弧贴图（赫连霄一族）：**软边**的锯齿雷柱，长轴沿 Y。
##
## 为什么不用 draw_polyline：用户 2026-10-26 定过「不用折线 / 硬边图元」——
## 折线在加法混合下会变成一根根塑料棍。这里先把折线烘成「高斯软边」贴图，
## 再用 Sprite2D 拉伸/旋转，既有锯齿的形状，又有电光的柔边。
static func bolt_texture() -> Texture2D:
	if _tex_cache.has("thunder_bolt"):
		return _tex_cache["thunder_bolt"]
	var w := 96
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261029
	# 主雷柱：9 个折点，横向抖动，整体竖直
	var pts: Array = []
	var x := float(w) * 0.5
	for i in range(9):
		var y := float(i) / 8.0 * float(h - 1)
		x = clampf(x + rng.randf_range(-15.0, 15.0), 12.0, float(w) - 12.0)
		pts.append(Vector2(x, y))
	var segs: Array = []
	for i in range(pts.size() - 1):
		segs.append([pts[i], pts[i + 1], 3.4, 1.0])
	# 两条分叉：让轮廓不是一根直棍
	segs.append([pts[2], pts[2] + Vector2(-24.0, 44.0), 1.7, 0.55])
	segs.append([pts[5], pts[5] + Vector2(26.0, 36.0), 1.7, 0.50])
	for raw in segs:
		var s: Array = raw
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var core_w := float(s[2])
		var amp := float(s[3])
		var minx := int(maxf(0.0, floor(minf(a.x, b.x) - core_w * 5.0)))
		var maxx := int(minf(float(w - 1), ceil(maxf(a.x, b.x) + core_w * 5.0)))
		var miny := int(maxf(0.0, floor(minf(a.y, b.y) - core_w * 5.0)))
		var maxy := int(minf(float(h - 1), ceil(maxf(a.y, b.y) + core_w * 5.0)))
		for yy in range(miny, maxy + 1):
			for xx in range(minx, maxx + 1):
				var d := _point_seg_dist(Vector2(xx, yy), a, b)
				var al := exp(-pow(d / core_w, 2.0)) * 0.95 \
					+ exp(-pow(d / (core_w * 3.6), 2.0)) * 0.22
				if al <= 0.002:
					continue
				var prev := img.get_pixel(xx, yy)
				img.set_pixel(xx, yy, Color(1.0, 1.0, 1.0,
					clampf(prev.a + al * amp, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["thunder_bolt"] = tex
	return tex


static func _point_seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func skill_texture(key: String) -> Texture2D:
	if _asset_cache.has(key):
		return _asset_cache[key]
	var path := String(ArtDB.SKILL_TEXTURES.get(key, ""))
	var tex: Texture2D = null
	if path != "" and ResourceLoader.exists(path):
		tex = load(path)
	_asset_cache[key] = tex
	return tex


static func make_particles(tex: Texture2D, amount: int, life: float, z: int,
		additive: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex
	p.amount = amount
	p.lifetime = life
	p.lifetime_randomness = 0.22
	p.randomness = 0.45
	p.local_coords = true
	p.z_index = z
	p.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	p.one_shot = true
	p.explosiveness = 0.9
	if additive:
		p.material = additive_material()
	return p


static func make_curve(points: Array) -> Curve:
	var c := Curve.new()
	for pt in points:
		c.add_point(pt)
	c.bake_resolution = 24
	return c


static func make_gradient(offsets: PackedFloat32Array,
		colors: PackedColorArray) -> Gradient:
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	return g

# ===================== 定阵先生：绷线 / 方框 / 阵柱 =====================
## 统一的小工具：一根拉伸的白光条（长度→x、粗细→y），给「线」类特效复用
func _stretch_bar(center: Vector2, rot: float, length: float, thickness: float,
		color: Color) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = white_texture()
	spr.centered = true
	spr.material = additive_material()
	spr.position = center
	spr.rotation = rot
	spr.scale = Vector2(length / 4.0, thickness / 4.0)
	spr.modulate = color
	spr.z_index = 3
	add_child(spr)
	return spr


## 与 `_stretch_bar` 同签名，但走柔光条贴图：**thickness 指看得见的芯宽**，
## 外晕按贴图比例自己溢出去（芯占 35%）。影族的光带一律用它 ——
## 别的族已经按实机调定过，不跟着改，免得一次动穿全项目。
func _soft_bar(center: Vector2, rot: float, length: float, thickness: float,
		color: Color) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = lightbar_texture()
	spr.centered = true
	spr.material = additive_material()
	spr.position = center
	spr.rotation = rot
	# thickness 指**可见芯宽（FWHM）**：贴图纵向高斯 σ=9.6 → FWHM 占全高 25%，
	# 所以整条画 thickness×4 高，多出来的是两边的晕。按 0.35 折算会把芯算细，
	# 5px 的描边线实际只剩 1.3px 亮芯（第一版就栽在这）。
	spr.scale = Vector2(maxf(length, 1.0) / 256.0, maxf(thickness, 1.0) / 16.0)
	spr.modulate = color
	spr.z_index = 3
	add_child(spr)
	return spr


## 气君 · 云烟一族（2026-10-28 优化）
##
## 之前的问题：ArtDB 给每招声明了 layers / thickness / sweep / field_pulses，
## 但这里只读了 qi_mode 与 glow —— 八式看起来就是「同一团云换个方向」，而且
## 地面压痕与吐纳还写死了颜色。现在：
##   · **每招有自己的剪影**：收拢 / 云墙 / 双旋 / 绷线 / 穹顶 / 外爆 / 升柱 / 起落云
##   · 层数与厚度、脉冲节奏、冲击全部读 cfg（数据表是唯一来源，配色从 glow 派生）
##   · 仍然不用粒子、不用硬边圆环、不做整片过曝：厚度靠多层云叠 + shader 流
func _build_qi_cloud() -> void:
	var mode := String(_cfg.get("qi_mode", "burst"))
	# 气招的几何都是按 +X 画的：节点必须跟着出手方向转，否则朝左出手时特效反向（裂空即此）
	rotation = _dir.angle()
	# ⚠ 尺寸必须等于**实际判定**：boss 脚本 _hit_all_in_form 用 reach = form.range（容差 +18）。
	var reach := clampf(float(_form.get("range", 150.0)), 60.0, 600.0)
	var hit_width := maxf(float(_form.get("width", 50.0)), 24.0)
	var half_angle := deg_to_rad(maxf(float(_form.get("angle", 90.0)), 20.0) * 0.5)
	var col: Color = _cfg.get("glow", Color(0.72, 0.92, 1.0))
	var layers := clampi(int(_cfg.get("layers", 3)), 1, 4)
	var thick := clampf(float(_cfg.get("thickness", 0.30)), 0.12, 0.55)
	var impact := clampf(float(_cfg.get("impact", 0.0)), 0.0, 0.12)
	var thick_tex := skill_texture("qi_cloud_thick")
	var wisp_tex := skill_texture("qi_cloud_wisp")
	var core_col := Color(minf(1.0, col.r + 0.18), minf(1.0, col.g + 0.14), minf(1.0, col.b + 0.10), 1.0)
	var dim_col := Color(col.r * 0.80, col.g * 0.88, col.b * 0.94, 1.0)

	match mode:
		"gather":
			# 引气凝环（SELF）：外圈向环收 → 停一拍 → 慢慢散
			var pulses := maxi(1, int(_cfg.get("field_pulses", 1)))
			var gap := maxf(float(_cfg.get("field_pulse_gap", 0.20)), 0.08)
			var ring_r := reach * 0.42
			for p in pulses:
				var d := gap * float(p)
				for i in 7:
					var ang := TAU * float(i) / 7.0 + float(p) * 0.4 + randf_range(-0.12, 0.12)
					var sp := _qi_puff(wisp_tex,
						Vector2(cos(ang), sin(ang)) * (reach * (0.95 - 0.10 * float(p))),
						0.34, dim_col, 0.55, ang)
					_qi_release(sp, d, 0.0, 0.30,
						Vector2(cos(ang), sin(ang) * 0.55) * ring_r, Vector2(0.20, 0.20), 0.34)
				# 气环本体：压扁一圈，收拢后停 0.18 秒再散
				for k in 10:
					var a2 := TAU * float(k) / 10.0
					var ring := _qi_puff(thick_tex,
						Vector2(cos(a2), sin(a2) * 0.5) * (ring_r * 1.35),
						maxf(0.18, thick * 0.9), col, 0.50, a2)
					ring.scale = Vector2(ring.scale.x * 1.2, ring.scale.y * 0.8)
					_qi_release(ring, d + 0.14, 0.18, 0.34,
						Vector2(cos(a2), sin(a2) * 0.5) * (ring_r * 0.94), null, 0.36)
			if impact > 0.0:
				GameState.trigger_hit_stop(impact)
		"wave":
			# 冲气·裂空（LINE 460 × 宽 50）：0.06 秒铺满 → 停 0.10 秒 → 拖尾散
			var n_wave := 5
			for i in n_wave:
				var t := float(i) / float(n_wave - 1)
				var dist := lerpf(hit_width * 0.6, reach * 0.92, t)
				var sc := maxf(0.18, (hit_width / 210.0) * (1.15 - 0.22 * t))
				var sp := _qi_puff(thick_tex, Vector2(dist, randf_range(-6.0, 6.0)),
					sc, col if i < 2 else dim_col, 0.62 - 0.10 * t, 0.0)
				sp.scale = Vector2(sp.scale.x * 1.9, sp.scale.y * 0.62)
				_qi_release(sp, 0.012 * float(i), 0.10, 0.34,
					Vector2(dist * 1.12, sp.position.y + randf_range(-10.0, 10.0)), null, 0.40)
			# 亮芯：拉长的柔边云（不是硬边矩形）
			var core_line := _qi_puff(wisp_tex, Vector2(reach * 0.46, 0.0),
				hit_width / 300.0, core_col, 0.85, 0.0)
			core_line.scale = Vector2(reach * 0.46 / 128.0, hit_width * 0.55 / 128.0)
			_qi_release(core_line, 0.0, 0.08, 0.30, null, null, 0.40)
			if impact > 0.0:
				GameState.trigger_hit_stop(impact)
		"spin":
			# 御风·回旋（CIRCLE 150）：外沿正好落在 reach
			var rings := 7
			for i in rings:
				var ang := TAU * float(i) / float(rings) + randf_range(-0.08, 0.08)
				var sp := _qi_puff(thick_tex, Vector2(cos(ang), sin(ang)) * (reach * 0.72),
					maxf(0.20, thick * 0.9), col if i % 2 == 0 else dim_col, 0.58, ang)
				sp.scale = Vector2(sp.scale.x * 1.25, sp.scale.y * 0.85)
				_qi_release(sp, 0.0, 0.10, 0.36,
					Vector2(cos(ang), sin(ang)) * (reach * 0.80), null, 0.55)
			if impact > 0.0:
				GameState.trigger_hit_stop(impact)
		"lock":
			# 气锁·缚脉（FAN 200 / 90°）：按扇面铺一层会呼吸的面
			var arc_n := 7
			for i in arc_n:
				var a := lerpf(-half_angle, half_angle, float(i) / float(arc_n - 1))
				var dirv := Vector2(cos(a), sin(a))
				var sp := _qi_puff(thick_tex, dirv * (reach * 0.90), maxf(0.30, thick * 1.45),
					col if i % 2 == 0 else dim_col, 0.52, a)
				sp.scale = Vector2(sp.scale.x * 1.3, sp.scale.y * 0.8)
				_qi_release(sp, 0.010 * float(i), 0.14, 0.38, dirv * (reach * 0.84), null, 0.30)
				var inner := _qi_puff(wisp_tex, dirv * reach * 0.55, maxf(0.26, thick * 1.00),
					dim_col, 0.42, a)
				_qi_release(inner, 0.010 * float(i) + 0.04, 0.12, 0.34, null, null, 0.26)
			if impact > 0.0:
				GameState.trigger_hit_stop(impact)
		"ward":
			# 化劲·卸力（SELF）：半圆穹顶 + 亮边
			var arc_w := maxi(4, layers * 2)
			for i in arc_w:
				var a := PI + PI * float(i) / float(arc_w - 1)
				var sp := _qi_puff(thick_tex, Vector2(cos(a), sin(a)) * reach * 0.62,
					thick, col, 0.62, a)
				sp.scale = Vector2(sp.scale.x * 1.2, sp.scale.y * 1.05)
				_qi_release(sp, 0.0, 0.10, 0.40, null, null, 0.24)
			var cap := _qi_puff(thick_tex, Vector2.ZERO, reach / 150.0, core_col, 0.85, 0.0)
			_qi_release(cap, 0.0, 0.06, 0.34, null, null, 0.46)
			GameState.trigger_hit_stop(maxf(impact, 0.05))
		"burst":
			# 气爆·周天（CIRCLE 240）：壳先收紧 → 炸到 reach → 余波散
			var shell := _qi_puff(thick_tex, Vector2.ZERO, reach / 130.0, core_col, 0.9, 0.0)
			_qi_release(shell, 0.0, 0.06, 0.40, null, null, 0.30)
			for band in maxi(2, layers):
				for i in 10:
					var ang := TAU * float(i) / 10.0 + 0.3 * float(band) + randf_range(-0.08, 0.08)
					var puff := _qi_puff(thick_tex,
						Vector2(cos(ang), sin(ang)) * (reach * (0.55 + 0.05 * float(band))),
						maxf(0.20, thick - 0.04 * float(band)),
						col if band == 0 else dim_col, 0.55 - 0.08 * float(band), ang)
					_qi_release(puff, 0.02 * float(band), 0.12, 0.40,
						Vector2(cos(ang), sin(ang)) * reach, Vector2(0.2, 0.2), 0.36)
			GameState.trigger_hit_stop(maxf(impact, 0.06))
		"breath":
			# 归元·吐纳（SELF）：向上飘
			var pulses2 := maxi(1, int(_cfg.get("field_pulses", 1)))
			var gap2 := maxf(float(_cfg.get("field_pulse_gap", 0.26)), 0.10)
			for p in pulses2:
				for i in 3:
					var side := -1.0 if i % 2 == 0 else 1.0
					var sp := _qi_puff(thick_tex,
						Vector2(side * 10.0, -24.0 - 36.0 * float(i) - 6.0 * float(p)),
						0.46 - 0.07 * float(i), col.lerp(core_col, 0.35), 0.46, 0.0)
					_qi_release(sp, gap2 * float(p), 0.10, 0.50,
						Vector2(side * 30.0, -120.0 - 26.0 * float(i)), null, 0.22)
		"step":
			# 踏罡·缩地（CIRCLE 110）：圈画在脚下（落点结算）
			for i in 7:
				var ang := TAU * float(i) / 7.0 + randf_range(-0.10, 0.10)
				var sp := _qi_puff(thick_tex, Vector2(cos(ang), sin(ang)) * (reach * 0.55),
					maxf(0.18, thick * 0.8), col if i % 2 == 0 else dim_col, 0.55, ang)
				_qi_release(sp, 0.0, 0.08, 0.34,
					Vector2(cos(ang), sin(ang)) * (reach * 0.80), null, 0.38)
			var core_step := _qi_puff(thick_tex, Vector2.ZERO,
				maxf(0.22, reach / 150.0), core_col, 0.7, 0.0)
			_qi_release(core_step, 0.0, 0.06, 0.28, null, null, 0.34)
		_:
			_qi_puff(thick_tex, Vector2.ZERO, reach / 80.0, col, 0.65, 0.0).release(0.0, 0.1, 0.35)


## 一片有生命感的云：随机朝向 / 流量 / 呼吸抖动，出场 → 停留 → 淡出，可选位移与缩放
## 返回精灵本身，调用方可以再改 scale（例如拉成横带）；改完再 release()
func _qi_puff(tex: Texture2D, pos: Vector2, sc: float, color: Color, alpha: float,
		rot: float = 0.0) -> Sprite2D:
	var jitter_sc := sc * randf_range(0.88, 1.14)
	var jitter_rot := rot + randf_range(-0.22, 0.22)
	var flow := randf_range(0.5, 1.5) * (1.0 if randf() < 0.5 else -1.0)
	return _cloud_sprite(tex, pos, jitter_sc, color, alpha * randf_range(1.04, 1.30),
		jitter_rot, flow)


## 出场(hold 秒) → 淡出(fade 秒)；to_pos / to_sc 为空表示原地。
## 停留段会让云缓慢「呼吸」：轻微缩放 + 自转 + 位移，读起来不是一张贴上去的图。
func _qi_release(puff: Sprite2D, delay: float, hold: float, fade: float,
		to_pos, to_sc, spin: float) -> void:
	var tw := puff.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	var start_pos := puff.position
	var start_sc := puff.scale
	if to_pos != null:
		tw.tween_property(puff, "position", to_pos, hold + fade).set_trans(Tween.TRANS_SINE)
	if to_sc != null:
		tw.parallel().tween_property(puff, "scale", to_sc, hold * 0.6).set_trans(Tween.TRANS_SINE)
	else:
		tw.parallel().tween_property(puff, "scale", start_sc * randf_range(1.08, 1.18),
			hold + fade).set_trans(Tween.TRANS_SINE)
	if spin != 0.0:
		tw.parallel().tween_property(puff, "rotation", puff.rotation + spin, hold + fade)
	tw.parallel().tween_property(puff, "modulate:a", 0.0, fade).set_delay(delay + hold)
	if to_pos == null:
		tw.parallel().tween_property(puff, "position",
			start_pos + Vector2(randf_range(-8.0, 8.0), randf_range(-14.0, -4.0)), hold + fade)

func _cloud_sprite(tex: Texture2D, pos: Vector2, sc: float, color: Color, alpha: float,
		rot: float = 0.0, flow: float = 0.6) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = true
	spr.position = pos
	spr.scale = Vector2(sc, sc)
	spr.rotation = rot
	# 云烟流转：噪声域扭曲 shader，让云在动而不是一堆静态贴片
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/qi_cloud.gdshader")
	mat.set_shader_parameter("tint", Color(color.r, color.g, color.b, 1.0))
	mat.set_shader_parameter("density", clampf(alpha * 1.45, 0.30, 0.95))
	mat.set_shader_parameter("flow", flow)
	spr.material = mat
	spr.modulate = Color(1.0, 1.0, 1.0, clampf(0.45 + alpha * 0.8, 0.0, 1.0))
	spr.z_index = 3
	add_child(spr)
	return spr


## ===================== 赫连霄：雷弧一族 =====================
## 统一语言：软边锯齿雷柱 + 雷印环 + 焦尘；颜色只用雷紫 / 赤金 / 焦黑。
## 与刀光、兽爪、太极八卦、绞绳、气云分开 —— 形状是「折 + 闪」，质感是「电光软边」。
## ⚠ 雷柱是烘出来的**软边贴图**（bolt_texture），不是 draw_polyline：
##   折线在加法混合下会变成塑料棍，用户已明确否掉。

const THUNDER_RING_EDGE := 0.76  # ring_texture 的亮环在 0.76 半径处

## 落雷预警印：在目标脚下亮一圈软边雷印，duration 内收拢淡出。
## 判词违律 / 定刑 / 九霄 / 聚雷都用它 —— 玩家看圈就知道「这一下会打在哪」。
static func thunder_mark(host: Node, world_pos: Vector2, radius: float,
		color: Color, duration: float = 0.30) -> void:
	if host == null or not host.is_inside_tree():
		return
	var holder := Node2D.new()
	holder.z_index = 2
	host.add_child(holder)
	holder.global_position = world_pos
	var s := radius / (128.0 * THUNDER_RING_EDGE)
	var ring := Sprite2D.new()
	ring.texture = ring_texture()
	ring.centered = true
	ring.material = additive_material()
	ring.scale = Vector2(s, s)
	ring.modulate = Color(color.r, color.g, color.b, 0.75)
	holder.add_child(ring)
	var inner := Sprite2D.new()
	inner.texture = ring_texture()
	inner.centered = true
	inner.material = additive_material()
	inner.scale = Vector2(s * 0.55, s * 0.55)
	inner.modulate = Color(color.r, color.g, color.b, 0.35)
	holder.add_child(inner)
	var tw := holder.create_tween()
	tw.tween_property(ring, "scale", Vector2(s * 0.55, s * 0.55), duration)
	tw.parallel().tween_property(inner, "scale", Vector2(s * 0.25, s * 0.25), duration)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, duration)
	tw.parallel().tween_property(inner, "modulate:a", 0.0, duration)
	tw.tween_callback(holder.queue_free)


## ===================== 离照：日轮一族 =====================
## 统一语言：柔和金色日核 + 赤红日冕 + 逆飞余烬；形状只用圆 / 放射 / 弧。
## 与雷弧的折线、刀光的斜切、剑气的细长、气云的絮状、阵线的直杆全部分开。

const SUN_RING_EDGE := 0.76


## 日核贴图：白 alpha 软边，实际颜色全部交给 modulate（金 / 赤 / 暗）。
static func sun_orb_texture() -> Texture2D:
	if _tex_cache.has("sun_orb"):
		return _tex_cache["sun_orb"]
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var nx := (x - c) / c
			var ny := (y - c) / c
			var d := sqrt(nx * nx + ny * ny)
			var ang := atan2(ny, nx)
			var core := exp(-d * d * 18.0) * 1.10
			var corona := exp(-d * d * 3.2) * (0.34 + 0.12 * sin(ang * 7.0 + 1.1))
			var rays := pow(maxf(0.0, cos(ang * 10.0 + sin(ang * 3.0) * 0.5)), 14.0) \
				* exp(-d * 4.2) * 0.55
			var a := clampf(core + corona + rays, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["sun_orb"] = tex
	return tex


## 一枚世界层日核（柔和、加法混合、自动淡出）
static func sun_orb_at(host: Node, world_pos: Vector2, radius: float, color: Color,
		life: float = 0.5, alpha: float = 0.9) -> Sprite2D:
	if host == null or not host.is_inside_tree():
		return null
	var spr := Sprite2D.new()
	spr.texture = sun_orb_texture()
	spr.centered = true
	spr.material = additive_material()
	spr.global_position = world_pos
	spr.scale = Vector2.ONE * (radius / 128.0)
	spr.modulate = Color(color.r, color.g, color.b, alpha)
	spr.z_index = 4
	host.add_child(spr)
	spr.global_position = world_pos
	var tw := spr.create_tween()
	tw.tween_property(spr, "scale", spr.scale * 1.22, life * 0.55)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, life)
	tw.tween_callback(spr.queue_free)
	return spr


## 火种爆裂 / 日蚀 / 天火坠共用：日核 + 双环 + 八道柔光，不用硬边多边形
static func sun_burst_at(host: Node, world_pos: Vector2, radius: float,
		alpha: float = 0.8, life: float = 0.55) -> void:
	if host == null or not host.is_inside_tree():
		return
	var holder := Node2D.new()
	holder.z_index = 4
	host.add_child(holder)
	holder.global_position = world_pos
	sun_orb_at(holder, Vector2.ZERO, radius * 0.62, Color(1.0, 0.82, 0.40), life, alpha)
	for i in range(2):
		var ring := Sprite2D.new()
		ring.texture = ring_texture()
		ring.centered = true
		ring.material = additive_material()
		ring.scale = Vector2.ONE * (radius / (128.0 * SUN_RING_EDGE)) * (0.55 + 0.2 * i)
		ring.modulate = Color(1.0, 0.55, 0.20, alpha * (0.85 - 0.3 * i))
		holder.add_child(ring)
		var tw := ring.create_tween()
		tw.tween_property(ring, "scale", ring.scale * 1.65, life)
		tw.parallel().tween_property(ring, "modulate:a", 0.0, life)
		tw.tween_callback(ring.queue_free)
	for i in range(8):
		var ray := Sprite2D.new()
		ray.texture = streak_texture()
		ray.centered = true
		ray.material = additive_material()
		ray.rotation = TAU * float(i) / 8.0 + 0.18
		ray.position = Vector2.RIGHT.rotated(ray.rotation) * radius * 0.30
		ray.scale = Vector2(0.30, radius / 256.0 * 0.9)
		ray.modulate = Color(1.0, 0.66, 0.24, alpha * 0.55)
		holder.add_child(ray)
		var tr := ray.create_tween()
		tr.tween_property(ray, "position", ray.position * 1.9, life)
		tr.parallel().tween_property(ray, "modulate:a", 0.0, life)
		tr.tween_callback(ray.queue_free)
	host.get_tree().create_timer(life + 0.15).timeout.connect(holder.queue_free)


## 日冕满层的体内引燃：小日核 + 内收金环，持续 duration；返回 holder 交给调用方逐帧贴目标
static func sun_ember_mark(host: Node, duration: float = 1.0) -> Node2D:
	if host == null or not host.is_inside_tree():
		return null
	var holder := Node2D.new()
	holder.z_index = 5
	host.add_child(holder)
	var core := Sprite2D.new()
	core.texture = sun_orb_texture()
	core.centered = true
	core.material = additive_material()
	core.scale = Vector2.ONE * 0.26
	core.modulate = Color(1.0, 0.58, 0.20, 0.0)
	holder.add_child(core)
	var ct := core.create_tween()
	ct.tween_property(core, "modulate:a", 0.92, 0.12)
	ct.parallel().tween_property(core, "scale", Vector2.ONE * 0.46, maxf(0.2, duration)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var ring := Sprite2D.new()
	ring.texture = ring_texture()
	ring.centered = true
	ring.material = additive_material()
	var s := 0.38
	ring.scale = Vector2(s, s)
	ring.modulate = Color(1.0, 0.68, 0.26, 0.62)
	holder.add_child(ring)
	var rt := ring.create_tween()
	rt.tween_property(ring, "scale", Vector2(s * 0.20, s * 0.20), maxf(0.2, duration)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	rt.parallel().tween_property(ring, "modulate:a", 0.10, maxf(0.2, duration))
	host.get_tree().create_timer(duration + 0.2).timeout.connect(
		func() -> void:
			if is_instance_valid(holder):
				holder.queue_free())
	return holder


## 一条金色牵引：沿 a→b 放一串由大到小的日核，并整体淡出
static func sun_tether(host: Node, a: Vector2, b: Vector2, color: Color,
		life: float = 0.45) -> void:
	if host == null or not host.is_inside_tree():
		return
	var holder := Node2D.new()
	holder.z_index = 4
	host.add_child(holder)
	var n := 7
	for i in range(n):
		var t := float(i) / float(n - 1)
		var pos: Vector2 = a.lerp(b, t)
		var spr := Sprite2D.new()
		spr.texture = sun_orb_texture()
		spr.centered = true
		spr.material = additive_material()
		spr.position = pos
		spr.scale = Vector2.ONE * (0.10 + 0.12 * (1.0 - t))
		spr.modulate = Color(color.r, color.g, color.b, 0.55)
		holder.add_child(spr)
		var tw := spr.create_tween()
		tw.tween_interval(0.05 * float(i))
		tw.tween_property(spr, "modulate:a", 0.0, life)
		tw.tween_callback(spr.queue_free)
	host.get_tree().create_timer(life + 0.6).timeout.connect(holder.queue_free)


## 日蚀 / 天火坠的落点预警：暗日 + 收拢金环，持续时间与延迟一致
static func sun_warn_at(host: Node, world_pos: Vector2, radius: float,
		duration: float = 0.5) -> void:
	if host == null or not host.is_inside_tree():
		return
	var holder := Node2D.new()
	holder.z_index = 2
	host.add_child(holder)
	holder.global_position = world_pos
	var dark := Sprite2D.new()
	dark.texture = sun_orb_texture()
	dark.centered = true
	dark.material = additive_material()
	dark.scale = Vector2.ONE * (radius * 0.55 / 128.0)
	dark.modulate = Color(0.06, 0.01, 0.00, 0.90)
	holder.add_child(dark)
	var rim := Sprite2D.new()
	rim.texture = sun_orb_texture()
	rim.centered = true
	rim.material = additive_material()
	rim.scale = Vector2.ONE * (radius * 0.62 / 128.0)
	rim.modulate = Color(1.0, 0.52, 0.18, 0.55)
	holder.add_child(rim)
	var ring := Sprite2D.new()
	ring.texture = ring_texture()
	ring.centered = true
	ring.material = additive_material()
	var s := radius / (128.0 * SUN_RING_EDGE)
	ring.scale = Vector2(s, s)
	ring.modulate = Color(1.0, 0.72, 0.30, 0.75)
	holder.add_child(ring)
	# 清晰的地面日轮刻痕：让预警圈不是一团模糊光
	var seal_tex := skill_texture("sun_seal")
	if seal_tex != null:
		var seal := Sprite2D.new()
		seal.texture = seal_tex
		seal.centered = true
		seal.material = additive_material()
		seal.scale = Vector2.ONE * (radius * 2.0 / 512.0)
		seal.modulate = Color(1.0, 0.72, 0.30, 0.42)
		seal.rotation = randf_range(-0.3, 0.3)
		holder.add_child(seal)
		var st := seal.create_tween()
		st.tween_property(seal, "rotation", seal.rotation + 0.55, duration)
	var tw := holder.create_tween()
	tw.tween_property(ring, "scale", Vector2(s * 0.18, s * 0.18), duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, duration)
	tw.tween_callback(holder.queue_free)


## ===================== 晏无咎：三灾一族 =====================
## 统一语言：破碎三环 + 灾印 + 灰烬；风=青灰风带、火=赤金余烬、雷=紫白柔光柱。
## 不用折线、雷弧、日核、阵线。

static func calamity_wheel_at(host: Node, world_pos: Vector2, color: Color) -> void:
	if host == null or not host.is_inside_tree():
		return
	var holder := Node2D.new()
	holder.z_index = 5
	host.add_child(holder)
	holder.global_position = world_pos
	var tex := skill_texture("calamity_wheel")
	if tex == null:
		tex = ring_texture()
	var wheel := Sprite2D.new()
	wheel.texture = tex
	wheel.centered = true
	wheel.material = additive_material()
	wheel.scale = Vector2(0.26, 0.26)
	wheel.modulate = Color(color.r, color.g, color.b, 0.75)
	holder.add_child(wheel)
	var ring := Sprite2D.new()
	ring.texture = ring_texture()
	ring.centered = true
	ring.material = additive_material()
	ring.scale = Vector2(0.42, 0.42)
	ring.modulate = Color(color.r, color.g, color.b, 0.50)
	holder.add_child(ring)
	var tw := holder.create_tween()
	tw.tween_property(wheel, "rotation", TAU * 1.4, 0.75)
	tw.parallel().tween_property(wheel, "scale", Vector2(0.60, 0.60), 0.75)
	tw.parallel().tween_property(wheel, "modulate:a", 0.0, 0.75)
	tw.parallel().tween_property(ring, "scale", Vector2(0.78, 0.78), 0.75)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.75)
	tw.tween_callback(holder.queue_free)


## 三元轮脉冲：按判定半径铺一圈元素色柔环，通用法宝表现
static func tri_ring_pulse(host: Node, world_pos: Vector2, radius: float, color: Color) -> void:
	if host == null or not host.is_inside_tree():
		return
	var holder := Node2D.new()
	holder.z_index = 4
	host.add_child(holder)
	holder.global_position = world_pos
	var ring := Sprite2D.new()
	ring.texture = ring_texture()
	ring.centered = true
	ring.material = additive_material()
	var s := radius / (128.0 * THUNDER_RING_EDGE)
	ring.scale = Vector2(s, s)
	ring.modulate = Color(color.r, color.g, color.b, 0.0)
	holder.add_child(ring)
	var tw := holder.create_tween()
	tw.tween_property(ring, "modulate:a", 0.48, 0.07)
	tw.tween_property(ring, "scale", Vector2(s * 1.16, s * 1.16), 0.30)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.30)
	tw.tween_callback(holder.queue_free)


## 灾劫连锁反应表现（未装备「三灾·灾身」时）：
## 灾劫连锁起手：风助火势 = 火核 + 风环（随后接火龙卷）；雷火交击 = 火核 + 雷印；
## 风雷引 = 风环（随后接风雷涡）。
static func calamity_reaction(host: Node, world_pos: Vector2, kind: String) -> void:
	if host == null or not host.is_inside_tree():
		return
	match kind:
		"wind_fire":
			sun_burst_at(host, world_pos, 110.0, 0.58, 0.46)
			tri_ring_pulse(host, world_pos, 126.0, Color(0.55, 0.92, 0.86, 0.92))
		"fire_thunder":
			sun_burst_at(host, world_pos, 108.0, 0.68, 0.50)
			thunder_mark(host, world_pos, 124.0, Color(0.86, 0.72, 1.0), 0.30)
		"thunder_wind":
			tri_ring_pulse(host, world_pos, 190.0, Color(0.58, 0.86, 1.0, 1.0))


## 风助火势的持续火龙卷：底座暖光 + 三股软焰柱绕轴旋转 + 上升余烬，按 duration 收尾。
## 判定在 player.gd 里逐跳结算；这里只负责可读的持续形体，不画硬边环。
static func calamity_fire_tornado(host: Node, world_pos: Vector2, radius: float,
		duration: float) -> void:
	if host == null or not host.is_inside_tree():
		return
	var holder := Node2D.new()
	holder.z_index = 4
	host.add_child(holder)
	holder.global_position = world_pos
	holder.modulate.a = 0.0

	var base := Sprite2D.new()
	base.texture = dot_texture()
	base.centered = true
	base.material = additive_material()
	base.scale = Vector2.ONE * (radius * 2.8 / 128.0)
	base.modulate = Color(1.0, 0.48, 0.18, 0.55)
	base.z_index = -1
	holder.add_child(base)

	# 软环 = 判定边界，给玩家一个「站进来就会被烧」的读数
	var ring := Sprite2D.new()
	ring.texture = ring_texture()
	ring.centered = true
	ring.material = additive_material()
	ring.scale = Vector2.ONE * (radius * 2.0 / 256.0)
	ring.modulate = Color(1.0, 0.52, 0.20, 0.40)
	holder.add_child(ring)
	var pulse := ring.create_tween()
	pulse.set_loops()
	pulse.tween_property(ring, "scale", ring.scale * 1.08, 0.55)
	pulse.tween_property(ring, "scale", ring.scale, 0.55)

	var swirl := Node2D.new()
	holder.add_child(swirl)
	for i in 4:
		var col := Sprite2D.new()
		col.texture = streak_texture()
		col.centered = true
		col.material = additive_material()
		col.scale = Vector2(radius * 0.34 / 64.0, radius * 2.10 / 256.0)
		col.position = Vector2(0.0, -radius * 0.90) \
			+ Vector2.RIGHT.rotated(TAU * float(i) / 4.0) * radius * 0.50
		col.modulate = Color(1.0, 0.60, 0.22, 0.44 - 0.05 * float(i))
		swirl.add_child(col)
	var core := Sprite2D.new()
	core.texture = streak_texture()
	core.centered = true
	core.material = additive_material()
	core.scale = Vector2(radius * 0.22 / 64.0, radius * 2.40 / 256.0)
	core.position = Vector2(0.0, -radius * 1.10)
	core.modulate = Color(1.0, 0.82, 0.44, 0.52)
	core.z_index = 1
	holder.add_child(core)
	for i in 2:
		var tongue := Sprite2D.new()
		tongue.texture = streak_texture()
		tongue.centered = true
		tongue.material = additive_material()
		tongue.scale = Vector2(radius * 0.12 / 64.0, radius * 1.30 / 256.0)
		tongue.position = Vector2((float(i) - 0.5) * radius * 0.28, -radius * 0.65)
		tongue.modulate = Color(1.0, 0.88, 0.52, 0.50)
		tongue.z_index = 1
		holder.add_child(tongue)

	swirl.create_tween().tween_property(swirl, "rotation", TAU * 3.0,
		maxf(0.4, duration)).set_trans(Tween.TRANS_LINEAR)

	for i in 9:
		var ember := Sprite2D.new()
		ember.texture = dot_texture()
		ember.centered = true
		ember.material = additive_material()
		ember.scale = Vector2.ONE * randf_range(0.18, 0.30)
		ember.modulate = Color(1.0, 0.72, 0.30, 0.0)
		ember.z_index = 1
		ember.position = Vector2.RIGHT.rotated(TAU * float(i) / 9.0) \
			* radius * randf_range(0.20, 0.62)
		holder.add_child(ember)
		var rise := ember.create_tween()
		rise.set_loops()
		rise.tween_interval(randf_range(0.0, 0.5))
		rise.tween_property(ember, "modulate:a", 0.70, 0.14)
		rise.parallel().tween_property(ember, "position:y",
			ember.position.y - radius * randf_range(1.1, 1.8), 0.70) \
			.set_ease(Tween.EASE_OUT)
		rise.tween_property(ember, "modulate:a", 0.0, 0.22)

	var tw := holder.create_tween()
	tw.tween_property(holder, "modulate:a", 1.0, 0.12)
	tw.tween_interval(maxf(0.1, duration - 0.45))
	tw.tween_property(holder, "modulate:a", 0.0, 0.35)
	tw.tween_callback(holder.queue_free)


## 风雷引的持续风雷涡：地面冷光 + 缓转软环 + 一圈向内收的软风条，表示「往中心吸」。
static func calamity_vortex(host: Node, world_pos: Vector2, radius: float,
		duration: float) -> void:
	if host == null or not host.is_inside_tree():
		return
	var holder := Node2D.new()
	holder.z_index = 4
	host.add_child(holder)
	holder.global_position = world_pos
	holder.modulate.a = 0.0

	var aura := Sprite2D.new()
	aura.texture = dot_texture()
	aura.centered = true
	aura.material = additive_material()
	aura.scale = Vector2.ONE * (radius * 2.5 / 128.0)
	aura.modulate = Color(0.56, 0.80, 1.0, 0.34)
	aura.z_index = -1
	holder.add_child(aura)

	var ring := Sprite2D.new()
	ring.texture = ring_texture()
	ring.centered = true
	ring.material = additive_material()
	ring.scale = Vector2.ONE * (radius * 2.2 / 256.0)
	ring.modulate = Color(0.58, 0.84, 1.0, 0.36)
	ring.z_index = 0
	holder.add_child(ring)
	ring.create_tween().tween_property(ring, "rotation", TAU, maxf(0.5, duration)) \
		.set_trans(Tween.TRANS_LINEAR)

	var funnel := Sprite2D.new()
	funnel.texture = smoke_texture()
	funnel.centered = true
	funnel.material = additive_material()
	funnel.scale = Vector2(radius * 1.10 / 96.0, radius * 1.60 / 96.0)
	funnel.position = Vector2(0.0, -radius * 0.45)
	funnel.modulate = Color(0.60, 0.82, 1.0, 0.26)
	funnel.z_index = 0
	holder.add_child(funnel)

	for i in 10:
		var streak := Sprite2D.new()
		streak.texture = streak_texture()
		streak.centered = true
		streak.material = additive_material()
		var ang := TAU * float(i) / 10.0 + 0.20
		var outer := Vector2.RIGHT.rotated(ang) * radius * 0.86
		var inner := Vector2.RIGHT.rotated(ang) * radius * 0.12
		streak.position = outer
		streak.rotation = ang + PI * 0.5
		streak.scale = Vector2(radius * 0.20 / 64.0, radius * 0.65 / 256.0)
		streak.modulate = Color(0.64, 0.88, 1.0, 0.0)
		streak.z_index = 1
		holder.add_child(streak)
		var pull := streak.create_tween()
		pull.set_loops()
		pull.tween_interval(0.10 * float(i))
		pull.tween_property(streak, "position", inner, 0.80) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		pull.parallel().tween_property(streak, "modulate:a", 0.55, 0.20)
		pull.tween_property(streak, "modulate:a", 0.0, 0.35)

	var tw := holder.create_tween()
	tw.tween_property(holder, "modulate:a", 1.0, 0.15)
	tw.tween_interval(maxf(0.1, duration - 0.50))
	tw.tween_property(holder, "modulate:a", 0.0, 0.35)
	tw.tween_callback(holder.queue_free)


## 三灾落点预警：断裂灾环 + 收拢金环；持续与延迟同拍
static func calamity_warn_at(host: Node, world_pos: Vector2, radius: float,
		duration: float, color: Color) -> void:
	if host == null or not host.is_inside_tree():
		return
	var holder := Node2D.new()
	holder.z_index = 2
	host.add_child(holder)
	holder.global_position = world_pos
	var tex := skill_texture("calamity_wheel")
	if tex == null:
		tex = ring_texture()
	var seal := Sprite2D.new()
	seal.texture = tex
	seal.centered = true
	seal.material = additive_material()
	seal.scale = Vector2.ONE * (radius * 2.0 / 512.0)
	seal.modulate = Color(color.r, color.g, color.b, 0.48)
	holder.add_child(seal)
	var ring := Sprite2D.new()
	ring.texture = ring_texture()
	ring.centered = true
	ring.material = additive_material()
	var s := radius / (128.0 * SUN_RING_EDGE)
	ring.scale = Vector2(s, s)
	ring.modulate = Color(color.r, color.g, color.b, 0.72)
	holder.add_child(ring)
	var tw := holder.create_tween()
	tw.tween_property(ring, "scale", Vector2(s * 0.18, s * 0.18), duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, duration)
	tw.parallel().tween_property(seal, "rotation", seal.rotation + 0.8, duration)
	tw.tween_callback(holder.queue_free)


func _build_thunder() -> void:
	var mode := String(_cfg.get("thunder_mode", "execute"))
	var col: Color = _cfg.get("glow", Color(0.70, 0.52, 1.0))
	var core: Color = _cfg.get("core", Color(1.0, 0.92, 0.66))
	var spark_col: Color = _cfg.get("spark", Color(1.0, 0.80, 0.40))
	match mode:
		"verdict":
			_build_thunder_verdict(col, core, spark_col)
		"drum":
			_build_thunder_drum(col, core, spark_col)
		"lock":
			_build_thunder_lock(col, core, spark_col)
		"step":
			_build_thunder_step(col, core, spark_col)
		"gather":
			_build_thunder_gather(col, core, spark_col)
		"prison":
			_build_thunder_prison(col, core, spark_col)
		"coop":
			_build_thunder_coop(col, core, spark_col)
		_:
			_build_thunder_execute(col, core, spark_col)


## 一根软边雷柱：pos 是贴图中心；rot 是贴图长轴（+Y）的朝向；length/width 是像素
func _thunder_bolt(pos: Vector2, rot: float, length: float, width: float,
		color: Color, alpha: float = 0.9, life: float = 0.24) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = bolt_texture()
	spr.centered = true
	spr.position = pos
	spr.rotation = rot
	spr.scale = Vector2(width / 42.0, length / 256.0)
	spr.material = additive_material()
	spr.modulate = Color(color.r, color.g, color.b, alpha)
	spr.z_index = 4
	add_child(spr)
	var tw := spr.create_tween()
	tw.tween_property(spr, "modulate:a", 0.0, life)
	tw.tween_callback(spr.queue_free)
	return spr


## 软边雷印环：半径 = 判定半径（ring_texture 的亮环在 0.76 处，这里补偿掉）
func _thunder_ring(pos: Vector2, radius: float, color: Color, alpha: float,
		life: float = 0.40, grow: float = 1.12) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = ring_texture()
	spr.centered = true
	spr.position = pos
	spr.material = additive_material()
	var s := radius / (128.0 * THUNDER_RING_EDGE)
	spr.scale = Vector2(s, s)
	spr.modulate = Color(color.r, color.g, color.b, alpha)
	spr.z_index = 3
	add_child(spr)
	var tw := spr.create_tween()
	tw.tween_property(spr, "scale", Vector2(s * grow, s * grow), life * 0.7)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, life)
	tw.tween_callback(spr.queue_free)
	return spr


## 地面判词雷印：把 chixiao_seal 铺在落点上，让「定刑 / 九霄 / 雷牢」读作同一套天律
func _thunder_seal(pos: Vector2, radius: float, color: Color, alpha: float,
		life: float = 0.55, spin: float = 0.5) -> void:
	var tex := skill_texture("thunder_seal")
	if tex == null:
		return
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = true
	spr.material = additive_material()
	var s := radius / 232.0
	spr.scale = Vector2(s, s)
	spr.position = pos
	spr.rotation = randf_range(-0.22, 0.22)
	spr.modulate = Color(color.r, color.g, color.b, alpha)
	spr.z_index = 2
	add_child(spr)
	var tw := spr.create_tween()
	tw.tween_property(spr, "rotation", spr.rotation + spin, life)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, life)
	tw.tween_callback(spr.queue_free)


func _thunder_flash(pos: Vector2, color: Color, size: float, alpha: float = 0.9) -> void:
	var spr := Sprite2D.new()
	spr.texture = star_texture()
	spr.centered = true
	spr.position = pos
	spr.material = additive_material()
	spr.modulate = Color(color.r, color.g, color.b, alpha)
	spr.scale = Vector2(size, size)
	spr.z_index = 6
	add_child(spr)
	var tw := spr.create_tween()
	tw.tween_property(spr, "scale", Vector2(size * 2.2, size * 2.2), 0.20)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, 0.24)
	tw.tween_callback(spr.queue_free)


func _thunder_sparks(pos: Vector2, color: Color, count: int) -> void:
	var p := make_particles(dot_texture(), count, 0.38, 5, true)
	p.position = pos
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 18.0
	p.direction = Vector2.RIGHT
	p.spread = 180.0
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 330.0
	p.damping_min = 60.0
	p.damping_max = 170.0
	p.gravity = Vector2(0.0, 160.0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.13
	p.color_ramp = make_gradient(
		PackedFloat32Array([0.0, 0.2, 1.0]),
		PackedColorArray([
			Color(color.r, color.g, color.b, 0.0),
			Color(color.r, color.g, color.b, 0.95),
			Color(color.r, color.g, color.b, 0.0),
		]))
	p.one_shot = true
	p.explosiveness = 1.0
	add_child(p)
	p.restart()
	p.emitting = true


func _thunder_dust(pos: Vector2, count: int) -> void:
	var p := make_particles(smoke_texture(), count, 0.62, 2, false)
	p.position = pos
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 22.0
	p.direction = Vector2.RIGHT
	p.spread = 180.0
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 130.0
	p.gravity = Vector2(0.0, -16.0)
	p.damping_min = 30.0
	p.damping_max = 80.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.0
	p.color_ramp = make_gradient(
		PackedFloat32Array([0.0, 0.15, 1.0]),
		PackedColorArray([
			Color(0.20, 0.16, 0.16, 0.0),
			Color(0.26, 0.20, 0.18, 0.30),
			Color(0.18, 0.14, 0.13, 0.0),
		]))
	p.one_shot = true
	p.explosiveness = 0.85
	add_child(p)
	p.restart()
	p.emitting = true


## 判词：笔锋沿 +X 划出（节点已按 dir 旋转），墨色烟带 + 雷紫笔锋 + 落笔雷印
func _build_thunder_verdict(col: Color, core: Color, spark_col: Color) -> void:
	var reach := clampf(float(_form.get("range", 320.0)), 140.0, 420.0)
	# 墨痕：普通混合的暗紫烟，读作“写下去的一道判词”
	for i in 3:
		var u := 0.28 + 0.28 * float(i)
		var puff := Sprite2D.new()
		puff.texture = smoke_texture()
		puff.centered = true
		puff.position = Vector2(reach * u, 0.0)
		puff.scale = Vector2(0.9, 0.34)
		puff.rotation = -0.06 + 0.04 * float(i)
		puff.modulate = Color(0.07, 0.04, 0.10, 0.46)
		puff.z_index = 1
		add_child(puff)
		var pt := puff.create_tween()
		pt.tween_property(puff, "modulate:a", 0.0, 0.34 + 0.04 * float(i))
		pt.tween_callback(puff.queue_free)
	# 笔锋：一条横着的雷柱 + 一条更细的金色芯
	_thunder_bolt(Vector2(reach * 0.46, 0.0), -PI * 0.5, reach * 0.92, 26.0, col, 0.82, 0.28)
	_thunder_bolt(Vector2(reach * 0.46, 0.0), -PI * 0.5, reach * 0.86, 9.0, core, 0.95, 0.22)
	# 落笔处：雷印 + 金闪 + 火花
	_thunder_ring(Vector2(reach, 0.0), 44.0, core, 0.75, 0.42, 1.24)
	_thunder_flash(Vector2(reach, 0.0), core, 0.30, 0.9)
	_thunder_sparks(Vector2(reach, 0.0), spark_col, 18)


## 定刑：指定落点（origin）一根天雷柱 + 地面雷印 + 焦尘
func _build_thunder_execute(col: Color, core: Color, spark_col: Color) -> void:
	var radius := clampf(float(_form.get("range", 90.0)), 40.0, 160.0)
	_thunder_seal(Vector2.ZERO, radius, col, 0.50, 0.55, 0.55)
	_thunder_ring(Vector2.ZERO, radius, col, 0.42, 0.46, 1.22)
	_thunder_ring(Vector2.ZERO, radius * 0.55, core, 0.55, 0.34, 1.30)
	_thunder_bolt(Vector2(0.0, -190.0), 0.0, 420.0, 38.0, col, 0.88, 0.30)
	_thunder_bolt(Vector2(10.0, -190.0), 0.0, 400.0, 13.0, core, 0.95, 0.24)
	_thunder_flash(Vector2.ZERO, core, 0.36, 0.95)
	_thunder_sparks(Vector2.ZERO, spark_col, 26)
	_thunder_dust(Vector2.ZERO, 18)


## 协同雷击：满雷势平A的短促落雷，判定圈小、雷柱短，连击时不刷屏
func _build_thunder_coop(col: Color, core: Color, spark_col: Color) -> void:
	var radius := clampf(float(_form.get("range", 62.0)), 36.0, 120.0)
	_thunder_ring(Vector2.ZERO, radius, col, 0.42, 0.24, 1.18)
	_thunder_bolt(Vector2(0.0, -75.0), 0.0, 170.0, 14.0, col, 0.82, 0.18)
	_thunder_bolt(Vector2(3.0, -75.0), 0.0, 155.0, 6.0, core, 0.92, 0.14)
	_thunder_flash(Vector2.ZERO, core, 0.20, 0.92)
	_thunder_sparks(Vector2.ZERO, spark_col, 8)
	_thunder_dust(Vector2.ZERO, 3)


## 雷鼓：一圈雷印 + 放射状雷柱 + 鼓面金闪
func _build_thunder_drum(col: Color, core: Color, spark_col: Color) -> void:
	var radius := clampf(float(_form.get("range", 180.0)), 80.0, 300.0)
	_thunder_ring(Vector2.ZERO, radius * 0.55, col, 0.70, 0.42, 1.55)
	_thunder_ring(Vector2.ZERO, radius, core, 0.42, 0.50, 1.16)
	for i in range(12):
		var ang := TAU * float(i) / 12.0 + 0.13
		var dir := Vector2(cos(ang), sin(ang))
		_thunder_bolt(dir * radius * 0.52, ang - PI * 0.5, radius * 0.78, 15.0,
			col if i % 2 == 0 else core, 0.72, 0.26)
	_thunder_flash(Vector2.ZERO, core, 0.48, 0.95)
	_thunder_sparks(Vector2.ZERO, spark_col, 30)
	_thunder_dust(Vector2.ZERO, 26)


## 锁雷：三道并行的雷链 + 末端锁印
func _build_thunder_lock(col: Color, core: Color, spark_col: Color) -> void:
	var reach := clampf(float(_form.get("range", 300.0)), 140.0, 400.0)
	for i in range(3):
		var off := Vector2(0.0, -20.0 + 20.0 * float(i))
		_thunder_bolt(Vector2(reach * 0.45, off.y), -PI * 0.5 + (-0.05 + 0.05 * float(i)),
			reach * 0.88, 12.0, col, 0.72, 0.28)
	_thunder_bolt(Vector2(reach * 0.45, 0.0), -PI * 0.5, reach * 0.90, 7.0, core, 0.9, 0.24)
	_thunder_ring(Vector2(reach * 0.94, 0.0), 34.0, core, 0.72, 0.38, 1.2)
	_thunder_flash(Vector2(reach * 0.94, 0.0), spark_col, 0.24, 0.85)
	_thunder_sparks(Vector2(reach * 0.7, 0.0), spark_col, 14)


## 雷遁：落点雷印 + 身后拖出的三道雷痕
func _build_thunder_step(col: Color, core: Color, spark_col: Color) -> void:
	var radius := clampf(float(_form.get("range", 110.0)), 60.0, 200.0)
	_thunder_ring(Vector2.ZERO, radius, col, 0.66, 0.42, 1.24)
	for i in range(3):
		_thunder_bolt(Vector2(-70.0 - 66.0 * float(i), 0.0), -PI * 0.5 + 0.10 * float(i),
			72.0, 13.0, col, 0.55 - 0.10 * float(i), 0.22)
	_thunder_bolt(Vector2.ZERO, 0.0, 180.0, 20.0, core, 0.78, 0.20)
	_thunder_flash(Vector2.ZERO, core, 0.28, 0.9)
	_thunder_sparks(Vector2.ZERO, spark_col, 18)


## 聚雷：天雷灌顶 + 向心雷弧 + 暗云；持续 lifetime 秒
func _build_thunder_gather(col: Color, core: Color, spark_col: Color) -> void:
	var hold := clampf(float(_cfg.get("lifetime", 1.4)), 0.8, 1.8)
	# 中央雷柱：从天上灌下来
	_thunder_bolt(Vector2(0.0, -150.0), 0.0, 380.0, 44.0, col, 0.85, hold)
	_thunder_bolt(Vector2(0.0, -150.0), 0.0, 360.0, 15.0, core, 0.95, hold)
	_thunder_ring(Vector2.ZERO, 70.0, core, 0.65, hold, 1.6)
	# 向心雷弧：六道从外圈收进来
	for i in range(6):
		var ang := TAU * float(i) / 6.0 + 0.2
		var dir := Vector2(cos(ang), sin(ang))
		_thunder_bolt(dir * 150.0, ang + PI * 0.5, 110.0, 11.0, col, 0.6, hold)
	# 暗云 + 上浮的电点
	var cloud := Sprite2D.new()
	cloud.texture = smoke_texture()
	cloud.centered = true
	cloud.position = Vector2(0.0, -18.0)
	cloud.scale = Vector2(1.5, 0.9)
	cloud.modulate = Color(0.10, 0.07, 0.13, 0.42)
	cloud.z_index = 1
	add_child(cloud)
	var ct := cloud.create_tween()
	ct.tween_property(cloud, "rotation", 0.5, hold)
	ct.parallel().tween_property(cloud, "modulate:a", 0.0, hold)
	ct.tween_callback(cloud.queue_free)
	_thunder_sparks(Vector2.ZERO, spark_col, 24)


## 九霄：单根天雷柱（调用方对每道柱各调一次，位置就是判定圆心）
func _build_thunder_nine(col: Color, core: Color, spark_col: Color) -> void:
	var radius := clampf(float(_form.get("range", 100.0)), 60.0, 160.0)
	_thunder_seal(Vector2.ZERO, radius, col, 0.55, 0.6, -0.45)
	_thunder_ring(Vector2.ZERO, radius, col, 0.42, 0.48, 1.20)
	_thunder_bolt(Vector2(0.0, -210.0), 0.0, 460.0, 42.0, col, 0.90, 0.32)
	_thunder_bolt(Vector2(-12.0, -210.0), 0.0, 440.0, 14.0, core, 0.95, 0.26)
	_thunder_flash(Vector2.ZERO, core, 0.30, 0.78)
	_thunder_sparks(Vector2.ZERO, spark_col, 30)
	_thunder_dust(Vector2.ZERO, 22)


## 雷牢：外圈雷印在 closing_time 内收拢，收拢瞬间爆出雷弧
func _build_thunder_prison(col: Color, core: Color, spark_col: Color) -> void:
	var radius := clampf(float(_form.get("prison_radius", 170.0)), 90.0, 260.0)
	var closing := clampf(float(_form.get("closing_time", 1.2)), 0.6, 2.0)
	var ring := Sprite2D.new()
	ring.texture = ring_texture()
	ring.centered = true
	ring.material = additive_material()
	_thunder_seal(Vector2.ZERO, radius * 0.92, col, 0.42, closing, 0.7)
	var s0 := radius / (128.0 * THUNDER_RING_EDGE)
	ring.scale = Vector2(s0, s0)
	ring.modulate = Color(col.r, col.g, col.b, 0.78)
	ring.z_index = 3
	add_child(ring)
	# 圈上八道短雷弧：读作“牢”
	for i in range(8):
		var ang := TAU * float(i) / 8.0
		var dir := Vector2(cos(ang), sin(ang))
		_thunder_bolt(dir * radius * 0.96, ang - PI * 0.5, 46.0, 8.0, col, 0.55, closing)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector2(s0 * 0.16, s0 * 0.16), closing) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(ring, "rotation", 0.9, closing)
	tw.parallel().tween_property(ring, "modulate:a", 0.95, closing)
	tw.tween_callback(func() -> void:
		if not is_inside_tree():
			return
		_thunder_flash(Vector2.ZERO, core, 0.40, 0.95)
		_thunder_ring(Vector2.ZERO, radius * 0.18, core, 0.85, 0.42, 1.5)
		for i in range(8):
			var ang2 := TAU * float(i) / 8.0 + 0.2
			var dir2 := Vector2(cos(ang2), sin(ang2))
			_thunder_bolt(dir2 * radius * 0.55, ang2 - PI * 0.5, radius * 0.8, 14.0,
				col, 0.7, 0.26)
		_thunder_sparks(Vector2.ZERO, spark_col, 26)
		ring.queue_free())


## ===================== 三灾八式（晏无咎） =====================
func _build_calamity() -> void:
	var mode := String(_cfg.get("calamity_mode", "slash"))
	var col: Color = _cfg.get("glow", Color(0.60, 0.70, 0.78))
	var core: Color = _cfg.get("core", Color(0.92, 0.92, 0.88))
	var spark: Color = _cfg.get("spark", Color(0.88, 0.80, 0.64))
	var radius := _radius()
	match mode:
		"step":
			_calamity_step(col, core, spark, radius)
		"fire_seal":
			_calamity_fire_seal(col, core, spark, radius)
		"fire_field":
			_calamity_fire_field(col, core, spark, radius)
		"thunder_strike":
			_calamity_thunder_strike(col, core, spark, radius)
		"thunder_pool":
			_calamity_thunder_pool(col, core, spark, radius)
		"turn":
			_calamity_turn(col, core, spark, radius)
		"final":
			_calamity_final(col, core, spark, radius)
		_:
			_calamity_slash(col, core, spark, radius)


func _calamity_seal_local(pos: Vector2, radius: float, color: Color,
		alpha: float, life: float, spin: float = 0.5) -> void:
	var tex := skill_texture("calamity_wheel")
	if tex == null:
		tex = ring_texture()
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = true
	spr.material = additive_material()
	spr.position = pos
	spr.scale = Vector2.ONE * (radius * 2.0 / 512.0)
	spr.modulate = Color(color.r, color.g, color.b, alpha)
	spr.z_index = 2
	add_child(spr)
	var tw := spr.create_tween()
	tw.tween_property(spr, "rotation", spr.rotation + spin, life)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, life)
	tw.tween_callback(spr.queue_free)


func _calamity_ray_fan(radius: float, count: int, color: Color, alpha: float,
		life: float, start_angle: float = 0.0) -> void:
	for i in range(count):
		var a := start_angle + TAU * float(i) / float(count)
		_sun_ray_local(Vector2.RIGHT.rotated(a) * radius * 0.32, a,
			radius * 0.85, 22.0, color, alpha, life)


func _calamity_column(height: float, width: float, color: Color, alpha: float,
		life: float) -> void:
	var spr := Sprite2D.new()
	spr.texture = streak_texture()
	spr.centered = true
	spr.material = additive_material()
	spr.position = Vector2(0.0, -height * 0.5)
	spr.scale = Vector2(width / 64.0, height / 256.0)
	spr.modulate = Color(color.r, color.g, color.b, alpha)
	spr.z_index = 4
	add_child(spr)
	var tw := spr.create_tween()
	tw.tween_property(spr, "modulate:a", 0.0, life)
	tw.tween_callback(spr.queue_free)


func _calamity_step(col: Color, core: Color, spark: Color, radius: float) -> void:
	_calamity_seal_local(Vector2.ZERO, radius * 0.72, col, 0.60, 0.36, 1.4)
	for i in 3:
		_sun_ray_local(Vector2(-float(i) * 28.0, 0.0), 0.0,
			radius * 0.8, 20.0, col, 0.36 - 0.07 * float(i), 0.30)
	_sun_ring_local(Vector2.ZERO, radius * 0.5, core, 0.42, 0.30)
	_sun_embers(Vector2.ZERO, spark, 18, radius * 0.3)


func _calamity_slash(col: Color, core: Color, spark: Color, radius: float) -> void:
	_build_slash()
	for i in 2:
		var a := -0.20 + 0.40 * float(i)
		_sun_ray_local(Vector2.ZERO, a, radius * 0.82, 28.0, col, 0.28, 0.34)
	_sun_ring_local(Vector2.ZERO, radius * 0.48, core, 0.42, 0.30)
	_sun_embers(Vector2.ZERO, spark, 18, radius * 0.32)


func _calamity_fire_seal(col: Color, core: Color, spark: Color, radius: float) -> void:
	_calamity_seal_local(Vector2.ZERO, radius * 0.88, col, 0.62, 0.55, 1.1)
	_sun_ring_local(Vector2.ZERO, radius * 0.62, core, 0.45, 0.45)
	_calamity_ray_fan(radius * 1.0, 8, col, 0.30, 0.45, 0.2)
	_sun_orbit(Vector2.ZERO, radius * 0.42, core, 0.85, 0.40)
	_sun_embers(Vector2.ZERO, spark, 28, radius * 0.45)


func _calamity_fire_field(col: Color, core: Color, spark: Color, radius: float) -> void:
	var holder := Node2D.new()
	holder.z_index = 3
	add_child(holder)
	_calamity_seal_local(Vector2.ZERO, radius * 0.95, col, 0.50, 4.5, 1.4)
	for i in 3:
		_sun_ring_local(Vector2.ZERO, radius * (0.45 + 0.18 * float(i)),
			core if i == 0 else col, 0.32, 4.5, 1.05)
	_calamity_ray_fan(radius * 0.95, 10, col, 0.16, 4.5, 0.3)
	var tw := holder.create_tween()
	tw.set_loops()
	tw.tween_property(holder, "rotation", TAU, 7.0)
	_sun_embers(Vector2.ZERO, spark, 30, radius * 0.6)


func _calamity_thunder_strike(col: Color, core: Color, spark: Color, radius: float) -> void:
	_calamity_seal_local(Vector2.ZERO, radius * 0.86, col, 0.62, 0.55, 1.3)
	_calamity_column(radius * 3.2, 64.0, core, 0.72, 0.45)
	for i in 3:
		var y := -radius * (0.3 + 0.28 * float(i))
		_sun_ring_local(Vector2(0.0, y), radius * (0.55 - 0.08 * float(i)),
			col if i > 0 else core, 0.36, 0.42)
	_sun_ring_local(Vector2.ZERO, radius * 1.0, core, 0.45, 0.42)
	_sun_embers(Vector2.ZERO, spark, 26, radius * 0.5)


func _calamity_thunder_pool(col: Color, core: Color, spark: Color, radius: float) -> void:
	_calamity_seal_local(Vector2.ZERO, radius * 1.0, col, 0.48, 4.0, 1.6)
	_calamity_ray_fan(radius * 1.05, 12, col, 0.20, 4.0, 0.1)
	for i in 2:
		_sun_ring_local(Vector2.ZERO, radius * (0.5 + 0.2 * float(i)),
			core if i == 0 else col, 0.30, 4.0, 1.1)
	_sun_orbit(Vector2.ZERO, radius * 0.30, core, 0.55, 4.0)
	_sun_embers(Vector2.ZERO, spark, 30, radius * 0.55)


## 三灾轮转：三色环反向错转，中心只留一圈细线 —— 不要叠成一坨白盘把 BOSS 盖住。
func _calamity_turn(col: Color, core: Color, spark: Color, radius: float) -> void:
	_calamity_seal_local(Vector2.ZERO, radius * 0.86, col, 0.22, 0.70, 2.2)
	var cols := [Color(0.55, 0.84, 0.76), Color(1.0, 0.50, 0.22), Color(0.72, 0.62, 1.0)]
	for i in 3:
		var ring := Sprite2D.new()
		ring.texture = ring_texture()
		ring.centered = true
		ring.material = additive_material()
		ring.scale = Vector2(0.30 + 0.10 * float(i), 0.30 + 0.10 * float(i))
		ring.modulate = Color(cols[i].r, cols[i].g, cols[i].b, 0.30)
		ring.rotation = TAU * float(i) / 3.0
		ring.z_index = 3
		add_child(ring)
		var tw := ring.create_tween()
		tw.tween_property(ring, "rotation", ring.rotation + TAU, 0.70)
		tw.parallel().tween_property(ring, "scale", ring.scale * 1.20, 0.70)
		tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.70)
		tw.tween_callback(ring.queue_free)
	_sun_ring_local(Vector2.ZERO, radius * 0.55, core, 0.22, 0.40)
	_sun_embers(Vector2.ZERO, spark, 18, radius * 0.42)


func _calamity_final(col: Color, core: Color, spark: Color, radius: float) -> void:
	_calamity_seal_local(Vector2.ZERO, radius * 1.05, core, 0.55, 1.0, 1.8)
	for i in 3:
		var off := Vector2.RIGHT.rotated(TAU * float(i) / 3.0) * radius * 0.28
		var cc: Color = [Color(0.55, 0.84, 0.76), Color(1.0, 0.50, 0.22),
			Color(0.72, 0.62, 1.0)][i]
		_calamity_column(radius * 2.6, 42.0, cc, 0.50, 0.65)
		_sun_ring_local(off, radius * 0.55, cc, 0.38, 0.60)
	for i in 3:
		_sun_ring_local(Vector2.ZERO, radius * (0.6 + 0.22 * float(i)),
			core if i == 0 else col, 0.32, 0.65, 1.15)
	_calamity_ray_fan(radius * 1.0, 12, col, 0.20, 0.65, 0.1)
	_sun_embers(Vector2.ZERO, spark, 42, radius * 0.65)


## ===================== 离照：日轮八式 =====================
## 日核 + 日冕环 + 放射柔光 + 逆飞余烬；所有形状都是圆 / 放射 / 弧。
func _build_sun() -> void:
	var mode := String(_cfg.get("sun_mode", "slash"))
	var col: Color = _cfg.get("glow", Color(1.0, 0.42, 0.12))
	var core: Color = _cfg.get("core", Color(1.0, 0.94, 0.72))
	var spark: Color = _cfg.get("spark", Color(1.0, 0.78, 0.32))
	var radius := _radius()
	match mode:
		"step":
			_sun_step(col, core, spark, radius)
		"throw":
			_sun_throw(col, core, spark, radius)
		"pull":
			_sun_pull(col, core, spark, radius)
		"wind":
			_sun_wind(col, core, spark, radius)
		"eclipse":
			_sun_eclipse(col, core, spark, radius)
		"wheel":
			_sun_wheel(col, core, spark, radius)
		"meteor":
			_sun_meteor(col, core, spark, radius)
		_:
			_sun_slash(col, core, spark, radius)


func _sun_ring_local(pos: Vector2, radius: float, color: Color, alpha: float,
		life: float = 0.5, grow: float = 1.25) -> void:
	var spr := Sprite2D.new()
	spr.texture = ring_texture()
	spr.centered = true
	spr.material = additive_material()
	spr.position = pos
	var s := radius / (128.0 * SUN_RING_EDGE)
	spr.scale = Vector2(s, s)
	spr.modulate = Color(color.r, color.g, color.b, alpha)
	spr.z_index = 3
	add_child(spr)
	var tw := spr.create_tween()
	tw.tween_property(spr, "scale", Vector2(s * grow, s * grow), life)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, life)
	tw.tween_callback(spr.queue_free)


func _sun_ray_local(pos: Vector2, rot: float, length: float, width: float,
		color: Color, alpha: float, life: float = 0.5) -> void:
	var spr := Sprite2D.new()
	spr.texture = streak_texture()
	spr.centered = true
	spr.material = additive_material()
	spr.position = pos
	spr.rotation = rot
	spr.scale = Vector2(width / 64.0, length / 256.0)
	spr.modulate = Color(color.r, color.g, color.b, alpha)
	spr.z_index = 4
	add_child(spr)
	var tw := spr.create_tween()
	tw.tween_property(spr, "modulate:a", 0.0, life)
	tw.tween_callback(spr.queue_free)


func _sun_orbit(pos: Vector2, radius: float, color: Color, alpha: float,
		life: float) -> void:
	var spr := Sprite2D.new()
	spr.texture = sun_orb_texture()
	spr.centered = true
	spr.material = additive_material()
	spr.position = pos
	spr.scale = Vector2.ONE * (radius / 128.0)
	spr.modulate = Color(color.r, color.g, color.b, alpha)
	spr.z_index = 4
	add_child(spr)
	var tw := spr.create_tween()
	tw.tween_property(spr, "scale", spr.scale * 1.35, life * 0.65)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, life)
	tw.tween_callback(spr.queue_free)


func _sun_embers(pos: Vector2, color: Color, count: int, radius: float) -> void:
	var p := make_particles(dot_texture(), count, 0.8, 4, true)
	p.position = pos
	p.one_shot = true
	p.explosiveness = 0.9
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = maxf(12.0, radius)
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2(0.0, -26.0)
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 70.0
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.14
	p.color = Color(color.r, color.g, color.b, 0.85)
	add_child(p)


func _sun_step(col: Color, core: Color, spark: Color, radius: float) -> void:
	# 贴地日影：三道向前的暖金残影 + 落点日轮
	for i in 3:
		var back := -float(i) * 34.0
		_sun_ray_local(Vector2(back, 0.0), 0.0, radius * (0.8 - 0.15 * i),
			22.0 - 4.0 * i, col, 0.42 - 0.08 * i, 0.30 + 0.05 * i)
	_sun_ring_local(Vector2.ZERO, radius * 0.85, core, 0.55, 0.34)
	_sun_orbit(Vector2.ZERO, radius * 0.38, core, 0.65, 0.34)
	_sun_embers(Vector2.ZERO, spark, 16, radius * 0.25)


func _sun_slash(col: Color, core: Color, spark: Color, radius: float) -> void:
	# 先用通用扇面 shader 画「日冕斩」的金红弧，再叠日轮环与日核
	_build_slash()
	for i in 2:
		var a := -0.22 + 0.44 * float(i)
		_sun_ray_local(Vector2.ZERO, a, radius * 0.85, 34.0,
			core if i == 1 else col, 0.26, 0.38)
	_sun_ring_local(Vector2.ZERO, radius * 0.45, core, 0.50, 0.34)
	_sun_orbit(Vector2.ZERO, radius * 0.30, core, 0.62, 0.36)
	_sun_embers(Vector2.ZERO, spark, 22, radius * 0.35)


func _sun_throw(col: Color, core: Color, spark: Color, radius: float) -> void:
	# 命中点：小太阳炸开；飞行段由招式脚本另画
	_sun_orbit(Vector2.ZERO, radius * 0.55, core, 0.90, 0.40)
	_sun_ring_local(Vector2.ZERO, radius * 1.05, col, 0.55, 0.50)
	for i in 6:
		var a := TAU * float(i) / 6.0
		_sun_ray_local(Vector2.RIGHT.rotated(a) * radius * 0.35, a,
			radius * 0.75, 26.0, col, 0.38, 0.42)
	_sun_embers(Vector2.ZERO, spark, 24, radius * 0.45)


func _sun_pull(col: Color, core: Color, spark: Color, radius: float) -> void:
	# 牵引：从远端拉回一串日核（方向由施法朝向决定）
	var reach := clampf(float(_form.get("range", 420.0)), 120.0, 520.0)
	for i in 6:
		var t := float(i) / 5.0
		var pos := -_dir * reach * (0.9 - 0.75 * t)
		_sun_orbit(pos, radius * (0.20 + 0.16 * t), core, 0.55, 0.24)
	_sun_ring_local(Vector2.ZERO, radius * 0.8, col, 0.50, 0.38)
	_sun_embers(Vector2.ZERO, spark, 18, radius * 0.30)


func _sun_wind(col: Color, core: Color, spark: Color, radius: float) -> void:
	var half := deg_to_rad(float(_form.get("angle", 90.0)) * 0.5)
	for i in 5:
		var a := lerpf(-half, half, float(i) / 4.0)
		_sun_ray_local(Vector2.ZERO, a, radius * 0.9, 30.0, col, 0.32, 0.45)
	_sun_ring_local(Vector2.ZERO, radius * 0.55, core, 0.35, 0.38)
	_sun_embers(Vector2.ZERO, spark, 34, radius * 0.55)


func _sun_eclipse(col: Color, core: Color, spark: Color, radius: float) -> void:
	# 先黑日后金爆：黑日用压暗的日核贴图，金环在它外面
	var dark := Sprite2D.new()
	dark.texture = sun_orb_texture()
	dark.centered = true
	dark.material = additive_material()
	dark.scale = Vector2.ONE * (radius * 0.60 / 128.0)
	dark.modulate = Color(0.08, 0.02, 0.01, 0.92)
	dark.z_index = 3
	add_child(dark)
	var tw := dark.create_tween()
	tw.tween_property(dark, "scale", dark.scale * 0.55, 0.30)
	tw.tween_callback(dark.queue_free)
	_sun_ring_local(Vector2.ZERO, radius * 0.92, core, 0.60, 0.35)
	var timer := get_tree().create_timer(0.30)
	timer.timeout.connect(func() -> void:
		if not is_inside_tree():
			return
		_sun_orbit(Vector2.ZERO, radius * 0.55, core, 0.95, 0.35)
		_sun_ring_local(Vector2.ZERO, radius * 1.25, col, 0.55, 0.45)
		for i in 10:
			var a := TAU * float(i) / 10.0
			_sun_ray_local(Vector2.RIGHT.rotated(a) * radius * 0.30, a,
				radius * 0.85, 28.0, col, 0.36, 0.40)
		_sun_embers(Vector2.ZERO, spark, 30, radius * 0.55))


func _sun_wheel(col: Color, core: Color, spark: Color, radius: float) -> void:
	# 持续日轮：8 道柔光扇骨 + 双环 + 缓慢旋转；lifetime 由配置给 4.5 秒
	var holder := Node2D.new()
	holder.z_index = 2
	add_child(holder)
	var ring := Sprite2D.new()
	ring.texture = ring_texture()
	ring.centered = true
	ring.material = additive_material()
	var s := radius / (128.0 * SUN_RING_EDGE)
	ring.scale = Vector2(s, s)
	ring.modulate = Color(core.r, core.g, core.b, 0.55)
	holder.add_child(ring)
	# 日轮刻痕：八道扇骨读得出“轮”，不是一圈模糊光
	var seal_tex := skill_texture("sun_seal")
	if seal_tex != null:
		var seal := Sprite2D.new()
		seal.texture = seal_tex
		seal.centered = true
		seal.material = additive_material()
		seal.scale = Vector2.ONE * (radius * 2.05 / 512.0)
		seal.modulate = Color(1.0, 0.70, 0.28, 0.58)
		holder.add_child(seal)
		var st := holder.create_tween()
		st.set_loops()
		st.tween_property(seal, "rotation", TAU, 9.0)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var ray := Sprite2D.new()
		ray.texture = streak_texture()
		ray.centered = true
		ray.material = additive_material()
		ray.rotation = a
		ray.position = Vector2.RIGHT.rotated(a) * radius * 0.42
		ray.scale = Vector2(0.30, radius * 0.9 / 256.0)
		ray.modulate = Color(col.r, col.g, col.b, 0.34)
		holder.add_child(ray)
	var orb := Sprite2D.new()
	orb.texture = sun_orb_texture()
	orb.centered = true
	orb.material = additive_material()
	orb.scale = Vector2.ONE * (radius * 0.34 / 128.0)
	orb.modulate = Color(core.r, core.g, core.b, 0.55)
	holder.add_child(orb)
	var spin := holder.create_tween()
	spin.set_loops()
	spin.tween_property(holder, "rotation", TAU, 6.0)
	_sun_embers(Vector2.ZERO, spark, 24, radius * 0.45)


func _sun_meteor(col: Color, core: Color, spark: Color, radius: float) -> void:
	# 天上日核落下：飞行段 + 落地爆
	var orb := Sprite2D.new()
	orb.texture = sun_orb_texture()
	orb.centered = true
	orb.material = additive_material()
	orb.position = Vector2(0.0, -380.0)
	orb.scale = Vector2.ONE * (radius * 0.45 / 128.0)
	orb.modulate = Color(core.r, core.g, core.b, 0.95)
	orb.z_index = 5
	add_child(orb)
	var trail := Sprite2D.new()
	trail.texture = streak_texture()
	trail.centered = true
	trail.material = additive_material()
	trail.position = Vector2(0.0, -380.0)
	trail.scale = Vector2(0.9, 3.2)
	trail.rotation = PI
	trail.modulate = Color(col.r, col.g, col.b, 0.45)
	trail.z_index = 4
	add_child(trail)
	var tw := create_tween()
	tw.tween_property(orb, "position", Vector2.ZERO, 0.34) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(trail, "position", Vector2.ZERO, 0.34) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		if not is_inside_tree():
			return
		_sun_ring_local(Vector2.ZERO, radius * 1.35, col, 0.60, 0.55)
		_sun_ring_local(Vector2.ZERO, radius * 0.80, core, 0.70, 0.40)
		for i in 12:
			var a := TAU * float(i) / 12.0
			_sun_ray_local(Vector2.RIGHT.rotated(a) * radius * 0.26, a,
				radius * 0.95, 30.0, col, 0.34, 0.50)
		_sun_embers(Vector2.ZERO, spark, 40, radius * 0.65)
		orb.queue_free()
		trail.queue_free())


## 两点之间绷紧的朱砂线（引阵 / 卷阵）：线长 = 招式射程，出伤帧与绷直同帧
func _build_cord() -> void:
	var length := clampf(float(_form.get("range", 480.0)), 120.0, 620.0)
	var col: Color = _cfg.get("glow", Color(0.86, 0.30, 0.22))
	# 红色流纹能量线（用户 2026-10-28 定）：能量带 + 沿线流动的光点，
	# 保证 520px / 0.35 秒也看得见；判定仍是 22px
	var band := _stretch_bar(Vector2(length * 0.5, 0.0), 0.0, length, 18.0,
			Color(1.0, 1.0, 1.0, 1.0))
	var tex := _cord_texture()
	if tex != null:
		band.texture = tex
		band.material = null
		band.scale = Vector2(length / maxf(1.0, float(tex.get_width())),
				18.0 / maxf(1.0, float(tex.get_height())))
	var glow := _stretch_bar(Vector2(length * 0.5, 0.0), 0.0, length, 46.0,
			Color(col.r, col.g, col.b, 0.22))
	glow.z_index = band.z_index - 1
	# 沿线流动的光点：只做 4 枚，轻量且读得出「能量在流」
	for i in 4:
		var mote := Sprite2D.new()
		mote.texture = dot_texture()
		mote.material = additive_material()
		mote.position = Vector2(0.0, 0.0)
		mote.scale = Vector2(0.16, 0.16)
		mote.modulate = Color(1.0, 0.86, 0.70, 0.85)
		mote.z_index = band.z_index + 1
		add_child(mote)
		var mt := create_tween()
		mt.tween_interval(0.09 * float(i))
		mt.tween_property(mote, "position", Vector2(length, 0.0), 0.26)
		mt.parallel().tween_property(mote, "modulate:a", 0.0, 0.26)
	var core := band
	for x in [0.0, length]:
		var node := Sprite2D.new()
		node.texture = ring_texture()
		node.material = additive_material()
		node.position = Vector2(x, 0.0)
		node.scale = Vector2(0.34, 0.34)
		node.modulate = Color(0.95, 0.82, 0.50, 0.9)
		node.z_index = 4
		add_child(node)
	_spawn_flash(Vector2.ZERO, 0.8)
	_spawn_flash(Vector2(length, 0.0), 0.8)
	var tw := create_tween()
	tw.tween_property(glow, "modulate:a", 0.0, 0.34)
	tw.parallel().tween_property(core, "modulate:a", 0.0, 0.34)


## 四角落下、连成方框（封阵）：框的边长 = 判定半径，看得见的圈就是挨打的圈
func _build_box() -> void:
	# ⚠ 判定是**圆形**（半径 210），所以方框取内接正方形：210 × 0.707 ≈ 148，
	# 否则「看到的框」比「挨打的圈」大一圈（违反"范围 = 判定"）
	var half := clampf(float(_form.get("range", 210.0)) * 0.707, 70.0, 240.0)
	var col: Color = _cfg.get("glow", Color(0.86, 0.30, 0.22))
	var corners: Array = [Vector2(-half, -half), Vector2(half, -half),
			Vector2(half, half), Vector2(-half, half)]
	_spawn_shockwave(half, 0.22)
	# 封阵是 3 跳结算：三下脉冲和判定同拍（0 / 0.45 / 0.9 秒）
	for i in 3:
		var tp := create_tween()
		tp.tween_interval(0.45 * float(i))
		tp.tween_callback(func() -> void:
			if is_instance_valid(self):
				_spawn_flash(Vector2.ZERO, 1.1))
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var edge := _stretch_bar((a + b) * 0.5, (b - a).angle(), (b - a).length(), 3.0,
				Color(1.0, 0.88, 0.76, 0.9))
		var tw := create_tween()
		tw.tween_property(edge, "modulate:a", 0.0, 0.9)
		var node := Sprite2D.new()
		node.texture = ring_texture()
		node.material = additive_material()
		node.position = a
		node.scale = Vector2(0.30, 0.30)
		node.modulate = Color(0.95, 0.82, 0.50, 0.9)
		node.z_index = 4
		add_child(node)


## 插旗：地面先亮一圈阵纹环再落旗（旗本体由 BOSS 脚本生成）——
## 玩家看到环就知道「旗要插在这」，与 0.6 秒前摇的落点一致
func _build_rune() -> void:
	var col: Color = _cfg.get("glow", Color(0.86, 0.30, 0.22))
	var ring := Sprite2D.new()
	ring.texture = ring_texture()
	ring.centered = true
	ring.material = additive_material()
	ring.modulate = Color(col.r, col.g, col.b, 0.0)
	ring.scale = Vector2(0.30, 0.30)
	ring.z_index = 1
	add_child(ring)
	var tw := create_tween()
	tw.tween_property(ring, "modulate:a", 0.75, 0.08)
	tw.parallel().tween_property(ring, "scale", Vector2(0.62, 0.62), 0.32)
	tw.tween_property(ring, "modulate:a", 0.0, 0.22)
	_spawn_dust(0.0)
	_spawn_flash(Vector2.ZERO, 0.9)


## 四面阵柱同时升起再崩开（解阵）：柱高 = 一面旗的分量
func _build_pillars() -> void:
	var col: Color = _cfg.get("glow", Color(0.86, 0.30, 0.22))
	for i in 4:
		var ang := TAU * float(i) / 4.0 + PI * 0.25
		var p := Vector2(cos(ang), sin(ang)) * 130.0 + Vector2(0.0, -90.0)
		var pillar := _stretch_bar(p, PI * 0.5, 180.0, 12.0,
				Color(col.r, col.g, col.b, 0.55))
		var tw := create_tween()
		tw.tween_property(pillar, "scale:y", pillar.scale.y * 1.25, 0.18)
		tw.tween_property(pillar, "modulate:a", 0.0, 0.36)

static func _cord_texture() -> Texture2D:
	if _tex_cache.has("cord"):
		return _tex_cache["cord"]
	var tex: Texture2D = null
	var path := "res://assets/effects/skills/array_line.png"
	if ResourceLoader.exists(path):
		tex = load(path)
	_tex_cache["cord"] = tex
	return tex
