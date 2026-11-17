class_name FxPlayer
extends Node2D
## 特效播放器 —— 特效美术替换的唯一接入点
##
## 用途：播放一次性特效（刀光、冲击、爆发等），播完自动销毁。
## 与 SkinVisual 的分工：
##   - SkinVisual  → 常驻的「实体形象」（有碰撞体、血条、需翻转朝向）
##   - FxPlayer    → 一次性的「特效表现」（无碰撞、需旋转/缩放/淡出，播完即走）
##
## 美术替换方式：
##   在 ArtDB.EFFECTS 里给对应特效 id 填 texture（序列帧图集或 SpriteFrames 资源）。
##   未填贴图时，自动回退到 fallback_kind 指定的程序化绘制，保证开发期外观不变。
##
## 用法：
##   FxPlayer.spawn(self, "slash_normal", {"rotation": attack_dir.angle(), "swing_back": false})
##   FxPlayer.spawn(self, "slash_finisher", {"rotation": r, "sweep_deg": 90.0})

## 程序化回退绘制类型（未接入贴图时使用）
const FALLBACK_NONE := "none"
const FALLBACK_SLASH_ARC := "slash_arc"   ## 渐变月牙刀光（多层弧线 + 边缘高亮）
const FALLBACK_FLASH := "flash"           ## 实心方块闪光
const FALLBACK_RING := "ring"             ## 冲击环（空心圆扩散）
const FALLBACK_RECT_BEAM := "rect_beam"   ## 矩形长条光束（原点向前：外层淡光+本体+亮核）
const FALLBACK_SPARK_BURST := "spark_burst"   ## 径向迸发粒子簇（弹反火花，参数 particle_*）
const FALLBACK_GATHER_ORBS := "gather_orbs"   ## 向心聚集能量球（转阶段聚能，参数 gather_radius）
const FALLBACK_LIGHT_PILLAR := "light_pillar" ## 竖直光柱（一剑开天：从天劈落，参数 fallback_rect_size）
const FALLBACK_SOFT_BEAM := "soft_beam"       ## 柔边光柱（传送登场：底部亮、顶部渐隐）
const FALLBACK_RECT_PLANE := "rect_plane"     ## 矩形地面劈痕（一剑开天落地，尺寸 = 判定矩形）
const FALLBACK_FAN_PLANE := "fan_plane"       ## 扇形地面劈痕（一剑开天落地，尺寸 = 判定扇形）

## 生成一个特效并挂到 parent 下（最常用入口）
## parent      挂载目标（通常是施法者或场景根）
## effect_id   ArtDB.EFFECTS 里的键
## params      可选覆盖，见下方 _apply_params 支持的键：
##             rotation        初始旋转（弧度），通常传攻击方向 angle()
##             position        局部位置（默认取配置的 spawn_offset）
##             global_position 若提供则用全局坐标定位
##             swing_back      刀光是否反向挥动（true = 从另一侧挥回）
##             sweep_deg       覆盖扫过角度（度）
##             no_spin         地面扇形/矩形劈痕用：只把 sweep_deg 当绘制张角，不让整块特效旋转
##             radius          覆盖回退绘制半径
##             color           覆盖回退绘制颜色
##             lifetime        覆盖播放时长
##             scale_mult      整体缩放倍率（乘在配置的 scale_from/to 上）
##             particle_count  覆盖粒子数量（spark_burst / gather_orbs）
##             particle_size   覆盖单颗粒粒尺寸（spark_burst / gather_orbs）
##             spark_dist_min  火花最近飞距（spark_burst）
##             spark_dist_max  火花最远飞距（spark_burst）
##             gather_radius   能量球起始聚集半径（gather_orbs）
##             hold_time       停留多久才开始淡出（秒，0 = 从头淡到尾）
##             fall_from       竖直光柱从落点上方多高处劈落（light_pillar）
##             fall_time       劈落耗时（秒）
static func spawn(parent: Node, effect_id: String, params: Dictionary = {}) -> FxPlayer:
	var fx := FxPlayer.new()
	fx.effect_id = effect_id
	parent.add_child(fx)
	fx._setup(params)
	return fx


## 特效 id（ArtDB.EFFECTS 的键）
var effect_id: String = ""

## 当前是否使用了真实贴图
var using_texture: bool = false

## 配置缓存
var _cfg: Dictionary = {}
## 播放总时长
var _life: float = 0.3
## 旋转补间目标（内部用）
var _sweep_rad: float = 0.0
var _base_rotation: float = 0.0
## 落点高度（竖直光柱：劈落终点）
var _base_y: float = 0.0
## 缩放补间目标
var _target_scale: Vector2 = Vector2.ONE
## 回退绘制节点
var _fallback: Node2D = null
## 贴图节点（序列帧用 AnimatedSprite2D，单帧用 Sprite2D）
var _sprite: Node2D = null


func _setup(params: Dictionary) -> void:
	_cfg = ArtDB.get_effect(effect_id)

	# ---- 定位 ----
	if params.has("global_position"):
		global_position = params["global_position"]
	elif params.has("position"):
		position = params["position"]
	else:
		position = _cfg.get("spawn_offset", Vector2.ZERO)
	# 落点高度（竖直光柱劈落的终点）
	_base_y = position.y

	# ---- 旋转：基础角度 + 挥动扫角 ----
	_base_rotation = float(params.get("rotation", 0.0))
	rotation = _base_rotation
	var sweep_deg := float(params.get("sweep_deg", _cfg.get("sweep_angle_deg", 0.0)))
	_sweep_rad = 0.0 if bool(params.get("no_spin", false)) else deg_to_rad(sweep_deg)
	# swing_back：从另一侧挥回（先反向偏移，再扫回来）
	if bool(params.get("swing_back", false)):
		rotation -= _sweep_rad

	# ---- 时长 ----
	var fps := maxf(1.0, float(_cfg.get("fps", 12.0)))
	var frames := maxi(1, int(_cfg.get("frames", 1)))
	_life = float(params.get("lifetime", _cfg.get("lifetime", 0.3)))
	# 有贴图且多帧时，时长按序列帧实际播放时间（避免画面被提前截断）
	_life = maxf(_life, float(frames) / fps)

	# ---- 渲染 ----
	var tex_path := String(_cfg.get("texture", ""))
	using_texture = false
	if tex_path != "" and ResourceLoader.exists(tex_path):
		if frames > 1:
			using_texture = _build_animated(tex_path, frames, fps)
		else:
			using_texture = _build_sprite(tex_path)
	if not using_texture:
		_build_fallback(params)

	# 旋转半径：让贴图偏离旋转中心，视觉上就是「绕父级原点（角色）扫过」
	# 0 时不做事 —— 刀光等既有特效行为完全不变
	var pivot: Vector2 = _cfg.get("pivot_offset", Vector2.ZERO)
	if pivot != Vector2.ZERO and _sprite != null:
		_sprite.position = pivot
	# 贴图自身朝向（武器图可能是竖的，绕角色扫时要摆正）
	var sprite_deg := float(_cfg.get("sprite_rotation_deg", 0.0))
	if sprite_deg != 0.0 and _sprite != null:
		_sprite.rotation = deg_to_rad(sprite_deg)

	_apply_scale(params)
	_play_timeline(params)


## 多帧序列帧：AnimatedSprite2D 播一遍后自毁
func _build_animated(tex_path: String, frames: int, fps: float) -> bool:
	var frame_size: Vector2 = _cfg.get("frame_size", Vector2.ZERO)
	var sf: SpriteFrames
	if tex_path.ends_with(".tres") or tex_path.ends_with(".res"):
		sf = load(tex_path)
	else:
		sf = ArtDB.build_sprite_frames(tex_path, frame_size, fps)
	if sf == null or sf.get_animation_names().is_empty():
		return false
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = sf
	_sprite.animation = ArtDB.ANIM_IDLE
	# 特效不循环：播完一遍即结束
	sf.set_animation_loop(ArtDB.ANIM_IDLE, false)
	if _cfg.get("blend_add", false):
		_sprite.material = _make_add_material()
	add_child(_sprite)
	_sprite.play()
	return true


## 单帧贴图：Sprite2D
func _build_sprite(tex_path: String) -> bool:
	var tex: Texture2D = load(tex_path)
	if tex == null:
		return false
	var spr := Sprite2D.new()
	spr.texture = tex
	if _cfg.get("blend_add", false):
		spr.material = _make_add_material()
	add_child(spr)
	_sprite = spr
	return true


## 程序化回退绘制（未接入贴图时维持现有外观）
func _build_fallback(params: Dictionary) -> void:
	var kind := String(_cfg.get("fallback_kind", FALLBACK_NONE))
	if kind == FALLBACK_NONE:
		return
	var color: Color = params.get("color", _cfg.get("fallback_color", Color.WHITE))
	var radius := float(params.get("radius", _cfg.get("fallback_radius", 40.0)))

	var draw := _FallbackDraw.new()
	draw.kind = kind
	draw.fx_color = color
	draw.radius = radius
	# 扇形张角：招式形态的 angle 直接传进来，保证「看到多大就打多大」
	draw.sweep_deg = float(params.get("sweep_deg", _cfg.get("fallback_sweep_deg", 55.0)))
	# 后端调用方（如 BOSS 砸地）可直接给出绘制尺寸
	draw.rect_size = params.get("rect_size", _cfg.get("fallback_rect_size", Vector2.ZERO))
	# 粒子类回退（spark_burst / gather_orbs）参数
	draw.particle_count = int(params.get("particle_count", _cfg.get("particle_count", 8)))
	draw.particle_size = params.get("particle_size", _cfg.get("particle_size", Vector2(4.0, 4.0)))
	draw.spark_dist_min = float(params.get("spark_dist_min", _cfg.get("spark_dist_min", 12.0)))
	draw.spark_dist_max = float(params.get("spark_dist_max", _cfg.get("spark_dist_max", 30.0)))
	draw.gather_radius = float(params.get("gather_radius", _cfg.get("gather_radius", 90.0)))
	# 粒子运动时长 = 本特效生命周期（父节点释放时子节点随之销毁，无需各自管理）
	draw.motion_life = _life
	add_child(draw)
	_fallback = draw


## 缩放：补间开头结尾
func _apply_scale(params: Dictionary) -> void:
	var mult: Vector2 = params.get("scale_mult", Vector2.ONE)
	var from: Vector2 = _cfg.get("scale_from", Vector2.ONE) * mult
	var to: Vector2 = _cfg.get("scale_to", Vector2.ONE) * mult
	scale = from
	# 保存终点，交给时间线补间
	_target_scale = to


## 时间线：旋转扫角 + 缩放 + 淡出 → 播完自毁
func _play_timeline(_params: Dictionary) -> void:
	var fade_to := float(_cfg.get("fade_to", 1.0))
	## 停留时长：先保持 hold_time 秒再淡出（一剑开天劈痕要在场上停 2 秒）
	var hold := float(_cfg.get("hold_time", 0.0))
	## 劈落：从落点上方 fall_from 处砸下来
	var fall_from := float(_cfg.get("fall_from", 0.0))
	var fall_time := float(_cfg.get("fall_time", 0.15))
	# ⚠ 每个动效各用一条**独立 tween**，销毁另用真实计时器。
	#   以前是把旋转/缩放/淡出塞进同一条 tween 再用末尾 callback 销毁，
	#   但 `tween.parallel()` 在没有前置步骤时边界行为不可靠 —— 会让末尾的
	#   queue_free 立刻触发，表现是「特效刚生成就没了」（落地劈痕踩过）。
	if not is_zero_approx(_sweep_rad):
		create_tween().tween_property(self, "rotation", _base_rotation + _sweep_rad, _life)
	if scale != _target_scale:
		create_tween().tween_property(self, "scale", _target_scale, _life)
	if fall_from > 0.0:
		position.y = _base_y - fall_from
		create_tween().tween_property(self, "position:y", _base_y, maxf(0.02, fall_time))
	if fade_to < 1.0:
		var fade := create_tween()
		if hold > 0.0:
			fade.tween_interval(hold)   # 先停留
		fade.tween_property(self, "modulate:a", fade_to, maxf(0.05, _life - hold))
	# 销毁：按生命周期真实计时，完全不依赖 tween 链
	get_tree().create_timer(_life, true, false, true).timeout.connect(queue_free)


## 加法混合材质（发光特效用）
func _make_add_material() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


## ===== 内部类：程序化回退绘制 =====
## 忠实复刻现有各类特效的绘制算法，保证未接入贴图时外观与改造前一致
class _FallbackDraw:
	extends Node2D

	var kind: String = "none"
	var fx_color: Color = Color.WHITE
	var radius: float = 40.0
	## 扇形刀光张角（度）
	var sweep_deg: float = 55.0
	var rect_size: Vector2 = Vector2.ZERO
	## 粒子数量（spark_burst / gather_orbs）
	var particle_count: int = 8
	## 单颗粒粒尺寸（像素，以原点为中心绘制）
	var particle_size: Vector2 = Vector2(4.0, 4.0)
	## 火花飞距范围（spark_burst：从 min 到 max 随机）
	var spark_dist_min: float = 12.0
	var spark_dist_max: float = 30.0
	## 能量球起始半径（gather_orbs：四周均距散布后向心聚集）
	var gather_radius: float = 90.0
	## 粒子运动总时长（由 FxPlayer 生命周期注入）
	var motion_life: float = 0.2
	## 粒子状态：[{ pos, dir, dist, start }]，按 kind 在 _process 里推进
	var particles: Array[Dictionary] = []
	var _elapsed: float = 0.0

	func _ready() -> void:
		match kind:
			"spark_burst":
				_init_sparks()
			"gather_orbs":
				_init_orbs()

	func _process(delta: float) -> void:
		if particles.is_empty():
			return
		_elapsed += delta
		var t := clampf(_elapsed / maxf(motion_life, 0.01), 0.0, 1.0)
		for p in particles:
			if kind == "spark_burst":
				# 径向：从原点沿 dir 飞出 dist（原 Tween 位移动画的程序化等价）
				p["pos"] = p["dir"] * p["dist"] * t
			elif kind == "gather_orbs":
				# 向心：从 start 聚集到原点
				p["pos"] = p["start"] * (1.0 - t)
		queue_redraw()

	## 径向迸发粒子（复刻 boss_projectile._spawn_deflect_sparks 的外观）
	func _init_sparks() -> void:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for i in range(particle_count):
			var dir := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
			var dist := rng.randf_range(spark_dist_min, spark_dist_max)
			particles.append({"pos": Vector2.ZERO, "dir": dir, "dist": dist, "start": Vector2.ZERO})

	## 向心聚集能量球（复刻 boss_base 转阶段 12 球的外观）
	func _init_orbs() -> void:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for i in range(particle_count):
			var angle := rng.randf_range(0.0, TAU)
			var start := Vector2(cos(angle), sin(angle)) * gather_radius
			particles.append({"pos": start, "dir": Vector2.ZERO, "dist": 0.0, "start": start})

	func _draw() -> void:
		match kind:
			"slash_arc":
				_draw_slash_arc()
			"flash":
				_draw_flash()
			"ring":
				_draw_ring()
			"rect_beam":
				_draw_rect_beam()
			"spark_burst", "gather_orbs":
				_draw_particles()
			"light_pillar":
				_draw_light_pillar()
			"soft_beam":
				_draw_soft_beam()
			"rect_plane":
				_draw_rect_plane()
			"fan_plane":
				_draw_fan_plane()

	## 渐变月牙刀光（与旧 SlashDrawer 算法一致：多层弧 + 边缘高亮）
	## 张角由 sweep_deg 控制，默认 55° 与改造前外观一致
	func _draw_slash_arc() -> void:
		var sweep := deg_to_rad(sweep_deg)
		var steps := 24
		var layers := 4
		for layer in range(layers):
			var t := float(layer) / float(layers - 1)
			var layer_color := fx_color
			layer_color.a = fx_color.a * (1.0 - t * 0.7)
			var r := radius * (0.55 + 0.45 * t)
			_draw_arc_fill(layer_color, r, sweep, steps)

		# 月牙边缘高亮
		var edge := PackedVector2Array()
		var edge_steps := 24
		for i in range(edge_steps + 1):
			var a := -sweep / 2.0 + sweep * i / edge_steps
			edge.append(Vector2(cos(a), sin(a)) * radius)
		draw_polyline(edge, Color(1.0, 1.0, 1.0, fx_color.a), 2.0)

	func _draw_arc_fill(color: Color, r: float, sweep: float, steps: int) -> void:
		var points := PackedVector2Array()
		points.append(Vector2.ZERO)
		for i in range(steps + 1):
			var a := -sweep / 2.0 + sweep * i / steps
			points.append(Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(points, color)

	## 实心方块闪光（以原点为中心）
	func _draw_flash() -> void:
		var size := rect_size
		if size == Vector2.ZERO:
			size = Vector2(radius, radius) * 2.0
		var half := size * 0.5
		draw_rect(Rect2(-half, size), fx_color, true)

	## 冲击环（双层空心圆）
	func _draw_ring() -> void:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, fx_color, 3.0, true)
		draw_arc(Vector2.ZERO, radius * 0.8, 0.0, TAU, 64, fx_color, 1.5, true)

	## 矩形长条光束（一剑开天·满层专用）
	## 原点 = 施法者身位，沿局部 +X 向前延伸 length；与 SHAPE_RECT 判定同源
	func _draw_rect_beam() -> void:
		var size := rect_size
		if size == Vector2.ZERO:
			size = Vector2(radius, radius)
		var length := size.x
		var width := size.y
		# 外层淡光（比本体宽 50%，低透明度）
		var glow := fx_color
		glow.a = fx_color.a * 0.25
		var glow_w := width * 1.5
		var glow_rect := Rect2(Vector2.ZERO, Vector2(length, glow_w))
		glow_rect.position.y = -glow_w * 0.5
		draw_rect(glow_rect, glow, true)
		# 本体
		var body := Rect2(Vector2.ZERO, Vector2(length, width))
		body.position.y = -width * 0.5
		draw_rect(body, fx_color, true)
		# 亮核（中缝高亮，剑刃感）
		var core := Color(1.0, 1.0, 1.0, fx_color.a * 0.85)
		var core_w := width * 0.36
		var core_rect := Rect2(Vector2.ZERO, Vector2(length * 0.97, core_w))
		core_rect.position.y = -core_w * 0.5
		draw_rect(core_rect, core, true)
		# 上下缘描线
		var line := Color(1.0, 1.0, 1.0, fx_color.a * 0.55)
		draw_line(Vector2.ZERO, Vector2(length, -width * 0.5), line, 1.5)
		draw_line(Vector2.ZERO, Vector2(length, width * 0.5), line, 1.5)
		# 源头亮斑（出剑口）
		draw_circle(Vector2.ZERO, width * 0.32, Color(1.0, 1.0, 1.0, fx_color.a * 0.9))

	## 粒子簇（spark_burst 径向 / gather_orbs 向心共用绘制）
	## 位置由 _process 按 kind 推进，透明度随生命周期线性淡出
	func _draw_particles() -> void:
		var t := clampf(_elapsed / maxf(motion_life, 0.01), 0.0, 1.0)
		var c := fx_color
		c.a = fx_color.a * (1.0 - t)
		var half: Vector2 = particle_size * 0.5
		for p in particles:
			var pos: Vector2 = p["pos"]
			draw_rect(Rect2(pos - half, particle_size), c, true)

	## 竖直光柱（一剑开天专用）：原点 = 落点（地面），向上延伸 height
	## **上窄下宽**，模拟「从头顶劈到地上」的透视；尺寸读 fallback_rect_size = (宽, 高)
	func _draw_light_pillar() -> void:
		var size := rect_size
		if size == Vector2.ZERO:
			size = Vector2(radius * 0.7, radius * 2.0)
		var width := size.x
		var height := size.y
		# 顶端收窄：越往上越远（俯视里的透视感）
		var top_w := width * 0.42
		# 外层淡光
		var glow := fx_color
		glow.a = fx_color.a * 0.22
		_draw_taper(glow, width * 1.6, top_w * 1.6, height)
		# 本体
		_draw_taper(fx_color, width, top_w, height)
		# 亮核（中缝，剑刃感）
		var core := Color(1.0, 1.0, 1.0, fx_color.a * 0.85)
		_draw_taper(core, width * 0.34, top_w * 0.34, height)
		# 落点冲击：外圈光斑 + 中心亮核
		var ring_c := fx_color
		ring_c.a = fx_color.a * 0.38
		draw_circle(Vector2.ZERO, width * 0.62, ring_c)
		draw_circle(Vector2.ZERO, width * 0.26, core)
		# 两侧刃线
		var line := Color(1.0, 1.0, 1.0, fx_color.a * 0.55)
		draw_line(Vector2(-width * 0.5, 0.0), Vector2(-top_w * 0.5, -height), line, 1.5)
		draw_line(Vector2(width * 0.5, 0.0), Vector2(top_w * 0.5, -height), line, 1.5)

	## 柔边光柱（传送登场）：按列做水平衰减 + 顶部渐隐，没有生硬切边
	func _draw_soft_beam() -> void:
		var size := rect_size
		if size == Vector2.ZERO:
			size = Vector2(radius * 0.7, radius * 2.0)
		var w := size.x
		var h := size.y
		var base := fx_color

		# 地面光斑（扁椭圆，柔化落点）
		var ground := PackedVector2Array()
		for i in 28:
			var a := TAU * float(i) / 28.0
			ground.append(Vector2(cos(a) * w * 0.95, sin(a) * w * 0.24))
		var ground_c := base
		ground_c.a = base.a * 0.22
		draw_colored_polygon(ground, ground_c)

		# 外层柔光 + 内层亮柱：每列 alpha 向两侧衰减，顶部 alpha 归零
		_draw_beam_columns(w * 0.98, h, base, base.a * 0.16, 0.62)
		_draw_beam_columns(w * 0.48, h * 0.94, Color(0.85, 0.97, 1.0, 1.0), base.a * 0.23, 0.56)
		_draw_beam_columns(w * 0.2, h * 0.82, Color(1.0, 1.0, 1.0, 1.0), base.a * 0.34, 0.5)

		# 底部亮核：只留一小团，避免整条光柱像硬塑料
		var core := base
		core.a = base.a * 0.42
		draw_circle(Vector2.ZERO, w * 0.18, core)

	## 一束由竖条拼成的柔光柱：边缘透明、中心亮，顶部渐隐
	func _draw_beam_columns(half_w: float, height: float, tint: Color,
			alpha_scale: float, top_scale: float) -> void:
		var cols := 24
		for i in cols:
			var u0 := -1.0 + 2.0 * float(i) / float(cols)
			var u1 := -1.0 + 2.0 * float(i + 1) / float(cols)
			var edge := pow(1.0 - absf((u0 + u1) * 0.5), 1.7)
			var x0 := u0 * half_w
			var x1 := u1 * half_w
			var top_y := -height * (top_scale + (1.0 - top_scale) * edge)
			var bottom := Color(tint.r, tint.g, tint.b, alpha_scale * edge)
			var top := Color(tint.r, tint.g, tint.b, 0.0)
			var top_shrink := 0.58
			draw_polygon(
				PackedVector2Array([
					Vector2(x0, 0.0), Vector2(x1, 0.0),
					Vector2(x1 * top_shrink, top_y), Vector2(x0 * top_shrink, top_y),
				]),
				PackedColorArray([bottom, bottom, top, top]),
			)

	## 矩形地面劈痕（一剑开天·满剑意）
	## 原点 = 落点（施法者身位），沿局部 +X 向前延伸 length、宽 width
	## **尺寸就是判定矩形的尺寸**，保证「看到多大就打多大」
	## 与 rect_beam 的区别：beam 是带亮核的光束，plane 是被劈开的地面痕迹
	func _draw_rect_plane() -> void:
		var size := rect_size
		if size == Vector2.ZERO:
			size = Vector2(radius * 2.0, radius)
		var length := size.x
		var width := size.y
		var half_w := width * 0.5
		# 主体面片
		draw_rect(Rect2(0.0, -half_w, length, width), fx_color, true)
		# 外缘描线（上下两条 + 远端一条）
		var edge := Color(1.0, 1.0, 1.0, fx_color.a * 0.8)
		draw_line(Vector2(0.0, -half_w), Vector2(length, -half_w), edge, 2.0)
		draw_line(Vector2(0.0, half_w), Vector2(length, half_w), edge, 2.0)
		draw_line(Vector2(length, -half_w), Vector2(length, half_w), edge, 2.0)
		# 中缝高亮（剑痕感）
		var core := Color(1.0, 1.0, 1.0, fx_color.a * 0.55)
		draw_line(Vector2(0.0, 0.0), Vector2(length * 0.98, 0.0), core, 3.0)

	## 扇形地面劈痕（一剑开天·普通形态）
	## 原点 = 顶点（施法者身位），向前张开 sweep_deg、半径 radius
	## **半径与张角就是判定扇形的尺寸**，与 _damage_bosses_in_shape 同源
	func _draw_fan_plane() -> void:
		var sweep := deg_to_rad(sweep_deg)
		var steps := 30
		var r := radius
		if r <= 0.0:
			r = 220.0
		# 主体面片
		var pts := PackedVector2Array()
		pts.append(Vector2.ZERO)
		for i in range(steps + 1):
			var a := -sweep / 2.0 + sweep * float(i) / float(steps)
			pts.append(Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, fx_color)
		# 外缘弧线
		var edge := Color(1.0, 1.0, 1.0, fx_color.a * 0.8)
		var arc := PackedVector2Array()
		for i in range(steps + 1):
			var a := -sweep / 2.0 + sweep * float(i) / float(steps)
			arc.append(Vector2(cos(a), sin(a)) * r)
		draw_polyline(arc, edge, 2.0)
		# 两条侧边
		draw_line(Vector2.ZERO, Vector2(cos(-sweep / 2.0), sin(-sweep / 2.0)) * r, edge, 2.0)
		draw_line(Vector2.ZERO, Vector2(cos(sweep / 2.0), sin(sweep / 2.0)) * r, edge, 2.0)

	## 梯形（下宽上窄）：竖直光柱的三层都用它
	func _draw_taper(color: Color, bot_w: float, top_w: float, height: float) -> void:
		var pts := PackedVector2Array()
		pts.append(Vector2(-bot_w * 0.5, 0.0))
		pts.append(Vector2(bot_w * 0.5, 0.0))
		pts.append(Vector2(top_w * 0.5, -height))
		pts.append(Vector2(-top_w * 0.5, -height))
		draw_colored_polygon(pts, color)
