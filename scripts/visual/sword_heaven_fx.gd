class_name SwordHeavenFx
extends Node2D
## 一剑开天的四段表现：**蓄力 → 劈落 → 撞击 → 地面劈痕**
##
## 1. 蓄力：头顶上方生成巨型光效，能量持续涌动，尺寸随时间增大
## 2. 劈砍：蓄力结束，该光效沿直线向下（落回施法者身位）运动，沿途留拖尾
## 3. 撞击：抵达落点瞬间，在场上生成地面劈痕（满剑意=矩形 / 非满剑意=扇形）
##    ⚠ 劈痕尺寸直接取判定形状的尺寸 —— 「看到的区域就是打得到的区域」
## 4. 时长：劈痕固定存活 2 秒，之后透明度插值渐隐，alpha 归零后销毁
##
## 为什么要单独一个节点：这套表现有「位移 + 沿途拖尾 + 落地换成另一种特效」的行为，
## 单个 FxPlayer 表达不了（它只会旋转/缩放/淡出）。
## 玩法代码只调 play()，所有外观/尺寸/时长都在 ArtDB.EFFECTS 与 move_db 形态表里。

## 蓄力光效（头顶；兼作劈落时的飞行体，跟着本节点一起位移）
const ID_CHARGE := "fx_sword_heaven_charge"
## 劈落沿途留下的拖尾（生成后留在原地自行渐隐，不跟随移动）
const ID_TRAIL := "fx_sword_heaven_trail"
## 地面劈痕：满剑意走矩形，非满剑意走扇形
const ID_PLANE_RECT := "fx_sword_heaven_plane"
const ID_PLANE_FAN := "fx_sword_heaven_fan"
## 拖尾生成间隔（秒）—— 太小了会刷一堆节点，太大了拖尾会断成珠子
const TRAIL_INTERVAL := 0.03
## 满剑意「一剑开天」巨剑与蓄力暗角（参数在 ArtDB.HEAVEN_CINEMATIC）
const GIANT_SWORD_SHADER := "res://assets/shaders/heaven_giant_sword.gdshader"
const GIANT_GLOW_SHADER := "res://assets/shaders/heaven_giant_sword_glow.gdshader"
const ARC_SHADER := "res://assets/shaders/heaven_sword_arc.gdshader"
const CRACK_ENERGY_SHADER := "res://assets/shaders/heaven_crack_energy.gdshader"
const VIGNETTE_SHADER := "res://assets/shaders/heaven_vignette.gdshader"

var _form: Dictionary = {}
var _dir: Vector2 = Vector2.RIGHT
## 施法者（用于落地震屏；BOSS 侧没有 Camera2D，会安全跳过）
var _caster: Node2D = null
## 玩家侧功法 id（skill_sword_heaven / _full），用于取震屏强度与配色；BOSS 侧留空
var _skill_id: String = ""
## 表现宿主 = 施法者的父节点（战场根）。
## ⚠ 拖尾与落地劈痕必须挂这里，不能挂 get_parent()（那是施法者本身，
##   挂上去会跟着角色一起移动，拖尾不留在原地、劈痕会随角色跑）
var _host: Node = null
## 落点（施法者局部坐标 = 原点，与判定起点同源）
var _origin := Vector2.ZERO
var _windup: float = 0.34
var _release_time: float = 0.12
## 蓄力 / 劈落光柱的横向宽度倍率（满剑意更粗；只改视觉，不改判定宽度）
var _beam_width_mult: float = 1.0
var _releasing: bool = false
var _trail_acc: float = 0.0
## 已生成的拖尾数量（调试 / 验证用：拖尾本身存活很短，不适合事后在场上找）
var trail_count: int = 0
## 落地回调：**劈到地面那一刻**才触发。玩法侧的伤害必须挂在这里，
## 不能在外面「播完特效顺手结算」——那会变成先掉血、剑过一会儿才落地。
var on_land := Callable()
## 是否接管镜头与压暗（镜像分身复读这一招时传 false：几具镜像一起放会把镜头拽来拽去）
var _cinematic: bool = true
## 蓄力时长覆写（< 0 = 用形态表里的 windup）。
## BOSS 自己已经播过前摇，蓄力必须等于它那一段，否则会多蓄一遍。
var _charge_override: float = -1.0
## 巨剑（满剑意专属）：剑柄轴心挂在施法者身上，从竖直向上劈落
var _giant_pivot: Node2D = null
var _giant_sword: ColorRect = null
## 巨剑的加法光层：与本体同尺寸、同轴心，叠在本体上
var _giant_glow: ColorRect = null
## 扇形弧光：与巨剑同轴、自身不旋转，随劈落角推进
var _giant_arc: ColorRect = null
var _giant_arc_mat: ShaderMaterial = null
## 蓄力压暗暗角（挂在 HUD 层 z=-50，只压战场不压 HUD）
var _vignette: ColorRect = null
var _vignette_mat: ShaderMaterial = null
## 镜头拉远的宿主（玩家）；BOSS 释放时找场上的玩家
var _cinematic_player: Node = null


## 在施法者身上播一整套（施法者必须是 Node2D，劈痕会挂到它的父节点上）
## on_land：落地回调（结算伤害用）；charge：蓄力时长覆写（秒）
## cinematic：false = 只演巨剑，不动镜头、不压暗（镜像分身复读用）
static func play(caster: Node2D, form: Dictionary, dir: Vector2,
		skill_id: String = "", on_land: Callable = Callable(),
		charge: float = -1.0, cinematic: bool = true) -> SwordHeavenFx:
	var fx := SwordHeavenFx.new()
	fx._caster = caster
	fx._skill_id = skill_id
	fx.on_land = on_land
	fx._charge_override = charge
	fx._cinematic = cinematic
	caster.add_child(fx)
	fx._host = caster.get_parent()
	if fx._host == null:
		fx._host = caster
	fx._start(form, dir)
	return fx


func _start(form: Dictionary, dir: Vector2) -> void:
	_form = form
	_dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	_windup = float(form.get("windup", 0.34))
	if _charge_override >= 0.0:
		_windup = _charge_override
	_release_time = float(form.get("fx_release_time", 0.12))
	_beam_width_mult = maxf(float(form.get("fx_beam_width_mult", 1.0)), 0.5)
	var charge_h := float(form.get("fx_charge_height", 150.0))
	_origin = Vector2.ZERO
	# 起点：头顶正上方；蓄力时光效悬在这里，释放时沿直线落回原点
	position = Vector2(0.0, -charge_h)
	# 光效挂在本节点下 → 本节点移动时它跟着走
	# lifetime 覆盖「蓄力 + 劈落」两段，尺寸补间（条目里的 scale_from→to）正好铺满全程
	FxPlayer.spawn(self, ID_CHARGE, {
		"lifetime": _windup + _release_time,
		"scale_mult": Vector2(_beam_width_mult, 1.0),
	})
	# 蓄力时环绕的灵光（粒子留在世界；节点下落时拖出尾迹）
	var motes := CPUParticles2D.new()
	motes.texture = SkillFx.dot_texture()
	motes.amount = 22
	motes.lifetime = 0.55
	motes.lifetime_randomness = 0.3
	motes.randomness = 0.5
	motes.local_coords = true
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RING
	motes.emission_ring_radius = 74.0
	motes.emission_ring_inner_radius = 34.0
	motes.direction = Vector2.RIGHT
	motes.spread = 180.0
	motes.initial_velocity_min = 4.0
	motes.initial_velocity_max = 34.0
	motes.tangential_accel_min = 50.0
	motes.tangential_accel_max = 130.0
	motes.radial_accel_min = -60.0
	motes.radial_accel_max = -20.0
	motes.gravity = Vector2.ZERO
	motes.damping_min = 8.0
	motes.damping_max = 24.0
	motes.scale_amount_min = 0.06
	motes.scale_amount_max = 0.15
	motes.scale_amount_curve = SkillFx.make_curve(
		[Vector2(0.0, 0.3), Vector2(0.25, 1.0), Vector2(1.0, 0.0)])
	motes.color_ramp = SkillFx.make_gradient(
		PackedFloat32Array([0.0, 0.16, 1.0]),
		PackedColorArray([
			Color(0.55, 0.9, 1.0, 0.0),
			Color(0.82, 0.99, 1.0, 0.75),
			Color(0.35, 0.7, 1.0, 0.0),
		]))
	motes.material = SkillFx.additive_material()
	motes.one_shot = false
	motes.emitting = true
	motes.z_index = 1
	add_child(motes)
	motes.restart()
	motes.emitting = true
	# 满剑意：巨剑 + 镜头拉远 + 蓄力压暗（现有四段特效照旧）
	if bool(_form.get("fx_giant_sword", false)):
		_start_cinematic(_cinematic)
	_release()


## 蓄力结束后劈落：直线位移到落点，撞到就换地面劈痕
func _release() -> void:
	# ignore_time_scale=true：顿帧期间不拖慢技能节奏（与 player.gd 的技能计时一致）
	await get_tree().create_timer(_windup, true, false, true).timeout
	if not is_instance_valid(self):
		return
	_releasing = true
	var tween := create_tween()
	tween.tween_property(self, "position", _origin, _release_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	if is_instance_valid(self):
		_land()


func _process(delta: float) -> void:
	if not _releasing:
		return
	_trail_acc += delta
	if _trail_acc >= TRAIL_INTERVAL:
		_trail_acc = 0.0
		_spawn_trail()


## 拖尾：落一个就留在场上，由它自己渐隐（挂战场根，不跟着本节点走）
func _spawn_trail() -> void:
	if not is_instance_valid(_host):
		return
	FxPlayer.spawn(_host, ID_TRAIL, {
		"global_position": global_position,
		## 新拖尾是三段竖直光柱贴图，保持屏幕竖直，不跟角色朝向旋转
		"rotation": 0.0,
		"scale_mult": Vector2(_beam_width_mult, 1.0),
	})
	trail_count += 1


## 撞击瞬间：按判定形状生成地面劈痕，尺寸与判定一致
func _land() -> void:
	if not is_instance_valid(_host):
		queue_free()
		return
	var land_global := to_global(_origin)
	var params := {
		"global_position": land_global,
		"rotation": _dir.angle(),
	}
	if String(_form.get("hit_shape", "")) == MoveDB.SHAPE_RECT:
		var rect_size := Vector2(
			float(_form.get("range", 1000.0)), float(_form.get("width", 160.0)))
		params["rect_size"] = rect_size
		# 劈痕贴图按 1000×160 制作；形态表若改尺寸，视觉跟着判定一起缩放
		params["scale_mult"] = Vector2(rect_size.x / 1000.0, rect_size.y / 160.0)
		FxPlayer.spawn(_host, ID_PLANE_RECT, params)
		# 满剑意巨剑：劈痕贴图之上再叠一层流动能量，避免残留特效像一张静止贴图
		if bool(_form.get("fx_giant_sword", false)):
			_spawn_crack_energy(land_global, rect_size, _dir.angle())
	else:
		var fan_range := float(_form.get("range", 220.0))
		params["radius"] = fan_range
		params["sweep_deg"] = float(_form.get("angle", 130.0))
		## sweep_deg 只用于程序化扇形绘制；扇形劈痕本身是固定朝向，不能跟着扫角转
		params["no_spin"] = true
		params["scale_mult"] = Vector2.ONE * (fan_range / 220.0)
		FxPlayer.spawn(_host, ID_PLANE_FAN, params)
	# 裂纹之上再补一层尘 / 碎石 / 星火 + 震屏
	# 巨剑形态的震屏统一走 _shake_cinematic（BOSS 侧也能震到玩家相机），这里不让旧路径重复震
	var giant := bool(_form.get("fx_giant_sword", false))
	SkillFx.heaven_impact(_host, land_global, _caster, _skill_id, 0.0 if giant else -1.0)
	if giant:
		_shake_cinematic()
	# ★ 落地即结算：伤害与劈痕同一帧（2026-10-27 用户要求「出伤要和特效出现时间吻合」）
	if on_land.is_valid():
		on_land.call()
	_absorb_giant_sword()
	_end_cinematic()
	# 劈痕交给 FxPlayer 自己管（存活 2 秒 + 渐隐 + 销毁），本节点功成身退
	queue_free()


# ===================== 满剑意巨剑演出 =====================

## 巨剑 + 镜头拉远 + 蓄力压暗，三件一起在前摇第一帧起手
## camera = false（镜像分身）：只出巨剑，镜头与压暗留给本体那一份，避免多份互相抢
func _start_cinematic(camera: bool = true) -> void:
	var cfg := ArtDB.heaven_cinematic()
	# 玩家侧前摇只有 0.34s：拉远/压暗必须压在前摇里完成，不能拖到劈落之后
	var setup_time := maxf(_windup * 0.9, 0.08)
	var zoom_time := minf(float(cfg["zoom_in_time"]), setup_time)
	var vig_time := minf(float(cfg["vignette_in_time"]), setup_time)
	if camera:
		var player := _camera_owner()
		if player != null and player.has_method("cinematic_zoom_out"):
			_cinematic_player = player
			player.call("cinematic_zoom_out", float(cfg["zoom_out"]), zoom_time)
	_spawn_giant_sword(cfg)
	if camera:
		_spawn_vignette(cfg, vig_time)


## 镜头宿主：玩家自己放技能就是玩家；BOSS 放技能时找场上的玩家
func _camera_owner() -> Node:
	if _caster != null and is_instance_valid(_caster) and _caster.is_in_group("player"):
		return _caster
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("player")


## 巨剑：剑柄挂在施法者手边，剑尖先竖直向上；劈落段绕剑柄扫过 swing_deg。
## 同时铺一层扇形弧光，把「向下劈」的圆弧轨迹画出来。
func _spawn_giant_sword(cfg: Dictionary) -> void:
	if _caster == null or not is_instance_valid(_caster):
		return
	var size: Vector2 = cfg["sword_size"]
	var hilt: Vector2 = cfg["hilt_offset"]
	# 朝向决定顺时针还是逆时针扫；正上/正下时默认顺时针
	var sign_x := 1.0 if _dir.x >= 0.0 else -1.0
	var end_rot := deg_to_rad(float(cfg["swing_deg"])) * sign_x

	var pivot := Node2D.new()
	pivot.name = "GiantSwordPivot"
	pivot.position = hilt
	pivot.z_index = 20
	_caster.add_child(pivot)
	_giant_pivot = pivot

	var rect := ColorRect.new()
	rect.name = "GiantSword"
	rect.size = size
	# 剑柄贴在轴心上，剑身向上（贴图顶边 = 剑尖）
	rect.position = Vector2(-size.x * 0.5, -size.y)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load(GIANT_SWORD_SHADER)
	rect.material = mat
	rect.modulate.a = 0.0
	pivot.add_child(rect)
	_giant_sword = rect

	# 加法光层：叠在本体上，负责刃口 / 中脊 / 尖端 / 流动能量
	var glow := ColorRect.new()
	glow.name = "GiantSwordGlow"
	glow.size = size
	glow.position = Vector2(-size.x * 0.5, -size.y)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gmat := ShaderMaterial.new()
	gmat.shader = load(GIANT_GLOW_SHADER)
	glow.material = gmat
	glow.modulate.a = 0.0
	pivot.add_child(glow)
	_giant_glow = glow

	# 蓄力：两层一起从无到有（玩家侧前摇只有 0.34s，淡入必须压在前摇内）
	var fade := minf(float(cfg["sword_fade_in"]), _windup * 0.8)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_ignore_time_scale(true)
	tw.tween_property(rect, "modulate:a", float(cfg["sword_alpha"]), fade) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(glow, "modulate:a", float(cfg["sword_alpha"]), fade) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# 劈落：前摇保持竖直向上，释放时加速扫向地面
	var swing := create_tween()
	swing.set_ignore_time_scale(true)
	swing.tween_interval(_windup)
	swing.tween_property(pivot, "rotation", end_rot, _release_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# 扇形弧光：同轴、不旋转，head_angle 跟着劈落角走
	var arc_size := size.y * 2.0
	var arc := ColorRect.new()
	arc.name = "GiantSwordArc"
	arc.size = Vector2(arc_size, arc_size)
	arc.position = hilt - Vector2(arc_size, arc_size) * 0.5
	arc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arc.z_index = 18
	var amat := ShaderMaterial.new()
	amat.shader = load(ARC_SHADER)
	amat.set_shader_parameter("head_angle", 0.0)
	amat.set_shader_parameter("tail_span", deg_to_rad(float(cfg["arc_tail_deg"])))
	amat.set_shader_parameter("inner", float(cfg.get("arc_inner", 0.42)))
	amat.set_shader_parameter("alpha", float(cfg["arc_alpha"]))
	arc.material = amat
	_caster.add_child(arc)
	_giant_arc = arc
	_giant_arc_mat = amat
	var arc_tw := create_tween()
	arc_tw.set_ignore_time_scale(true)
	arc_tw.tween_interval(_windup)
	arc_tw.tween_method(func(v: float) -> void:
		amat.set_shader_parameter("head_angle", v),
		0.0, end_rot, _release_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## 蓄力压暗：挂在 HUD 层 z=-50，只压战场；HUD 文字与血条在它上面
func _spawn_vignette(cfg: Dictionary, fade_in: float) -> void:
	if _host == null or not is_instance_valid(_host) or not _host.is_inside_tree():
		return
	var hud := _host.get_node_or_null("HUD")
	if hud == null:
		return
	var rect := ColorRect.new()
	rect.name = "HeavenCinematic"
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = -50
	var mat := ShaderMaterial.new()
	mat.shader = load(VIGNETTE_SHADER)
	mat.set_shader_parameter("strength", 0.0)
	rect.material = mat
	hud.add_child(rect)
	_vignette = rect
	_vignette_mat = mat
	var tw := rect.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_method(func(v: float) -> void:
		mat.set_shader_parameter("strength", v),
		0.0, float(cfg["vignette_strength"]), fade_in)


## 落地震屏：玩家自己放技能时震玩家；BOSS 释放时同样震到玩家相机
## （BOSS 没有 _screen_shake，旧路径会静默跳过）
func _shake_cinematic() -> void:
	var cfg := ArtDB.heaven_cinematic()
	var player := _camera_owner()
	if player != null and player.has_method("_screen_shake"):
		player.call("_screen_shake", float(cfg["shake"]), float(cfg["shake_time"]))


## 地面劈痕的流动能量层：贴着裂纹中线，寿命与劈痕贴图同步
func _spawn_crack_energy(land_global: Vector2, rect_size: Vector2, angle: float) -> void:
	if _host == null or not is_instance_valid(_host):
		return
	var holder := Node2D.new()
	holder.name = "HeavenCrackEnergy"
	holder.z_index = 2
	_host.add_child(holder)
	holder.global_position = land_global
	holder.rotation = angle
	var rect := ColorRect.new()
	rect.size = rect_size
	rect.position = Vector2(0.0, -rect_size.y * 0.5)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load(CRACK_ENERGY_SHADER)
	mat.set_shader_parameter("strength",
		float(ArtDB.heaven_cinematic().get("crack_energy_strength", 0.55)))
	rect.material = mat
	holder.add_child(rect)
	var cfg := ArtDB.get_effect(ID_PLANE_RECT)
	var hold := float(cfg.get("hold_time", 2.0))
	var fade := maxf(float(cfg.get("lifetime", 2.6)) - hold, 0.1)
	var tw := rect.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_interval(hold)
	tw.tween_property(rect, "modulate:a", 0.0, fade) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(holder.queue_free)


## 落地后：弧光先散，巨剑插在原地停一瞬再渐隐（劈痕继续亮着）
func _absorb_giant_sword() -> void:
	var cfg := ArtDB.heaven_cinematic()
	if _giant_arc != null and is_instance_valid(_giant_arc):
		var arc := _giant_arc
		var amat := _giant_arc_mat
		_giant_arc = null
		_giant_arc_mat = null
		if amat != null:
			var from := float(amat.get_shader_parameter("alpha"))
			var atw := arc.create_tween()
			atw.set_ignore_time_scale(true)
			atw.tween_interval(float(cfg.get("arc_hold_after_land", 0.15)))
			atw.tween_method(func(v: float) -> void:
				amat.set_shader_parameter("alpha", v), from, 0.0,
				float(cfg["arc_fade"]))
			atw.tween_callback(arc.queue_free)
		else:
			arc.queue_free()
	if _giant_pivot == null or not is_instance_valid(_giant_pivot):
		_giant_pivot = null
		_giant_sword = null
		_giant_glow = null
		return
	var pivot := _giant_pivot
	var sword := _giant_sword
	var glow := _giant_glow
	_giant_pivot = null
	_giant_sword = null
	_giant_glow = null
	if _host == null or not is_instance_valid(_host):
		pivot.queue_free()
		return
	pivot.reparent(_host)
	if sword == null or not is_instance_valid(sword):
		sword = pivot.get_node_or_null("GiantSword") as ColorRect
	if glow == null or not is_instance_valid(glow):
		glow = pivot.get_node_or_null("GiantSwordGlow") as ColorRect
	if sword == null:
		pivot.queue_free()
		return
	# 落地后先停一拍（压在残留扇面上读姿势），再两层一起渐隐
	var hold := float(cfg.get("sword_hold_after_land", 0.12))
	var fade := float(cfg["sword_fade_out"])
	var tw := sword.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_interval(hold)
	tw.tween_property(sword, "modulate:a", 0.0, fade) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if glow != null:
		tw.parallel().tween_property(glow, "modulate:a", 0.0, fade) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(pivot.queue_free)


## 落地收尾：暗角渐隐；镜头稍等再缓回，让劈痕先亮一下
func _end_cinematic() -> void:
	var cfg := ArtDB.heaven_cinematic()
	if _cinematic_player != null and is_instance_valid(_cinematic_player):
		var player := _cinematic_player
		_cinematic_player = null
		var timer := get_tree().create_timer(
			float(cfg["zoom_hold_after_land"]), true, false, true)
		timer.timeout.connect(func() -> void:
			if is_instance_valid(player) and player.has_method("cinematic_zoom_back"):
				player.call("cinematic_zoom_back", float(cfg["zoom_back_time"])))
	if _vignette != null and is_instance_valid(_vignette):
		var rect := _vignette
		var mat := _vignette_mat
		_vignette = null
		_vignette_mat = null
		var tw := rect.create_tween()
		tw.set_ignore_time_scale(true)
		if mat != null:
			var from := float(mat.get_shader_parameter("strength"))
			tw.tween_method(func(v: float) -> void:
				mat.set_shader_parameter("strength", v), from, 0.0,
				float(cfg["vignette_out_time"]))
		tw.tween_callback(rect.queue_free)


func _exit_tree() -> void:
	# 被弹刀 / 死亡 / 换场景打断：镜头与暗角也要收回来，别把 zoom 留在拉远值
	if _cinematic_player != null and is_instance_valid(_cinematic_player):
		var player := _cinematic_player
		_cinematic_player = null
		if player.has_method("cinematic_zoom_back"):
			player.call("cinematic_zoom_back", 0.2)
	if _vignette != null and is_instance_valid(_vignette):
		_vignette.queue_free()
		_vignette = null
		_vignette_mat = null
	if _giant_arc != null and is_instance_valid(_giant_arc):
		_giant_arc.queue_free()
		_giant_arc = null
		_giant_arc_mat = null
	if _giant_pivot != null and is_instance_valid(_giant_pivot):
		_giant_pivot.queue_free()
		_giant_pivot = null
		_giant_sword = null
		_giant_glow = null
