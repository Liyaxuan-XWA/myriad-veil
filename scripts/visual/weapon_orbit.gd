@tool
class_name WeaponOrbit
extends Node2D

## 御剑式武器：平时悬浮在角色身旁缓慢摆动，攻击时绕角色扫过一道弧再收回。
##
## 与 FxPlayer 的区别：FxPlayer 是「播完即毁」的一次性特效；
## 本节点是**常驻**的，跟在角色身边。
##
## 结构：
##   Player
##   └── WeaponOrbit（本节点，负责「绕角色转」）
##       └── SkinVisual（负责「武器长什么样」，走 ArtDB 换图）
##
## 为什么用 SkinVisual 当子节点：贴图加载 / SpriteFrames / 缩放逻辑全部复用，
## 换美术只改 ArtDB 的 player_weapon 条目，本脚本不用动。
##
## 所有可调参数都在 ArtDB.VISUALS["player_weapon"] 里（见该条目注释）。

## ArtDB.VISUALS 的条目 id
@export var weapon_id: String = "player_weapon"

## 角色当前朝向（由控制器每帧设置），决定武器扫向哪一侧
var facing_dir: Vector2 = Vector2.RIGHT

var _cfg: Dictionary = {}
var _skin: SkinVisual = null
var _has_weapon := false

## 当前角度（度，相对朝向）。待机时在 idle_base_deg 附近摆动，攻击时扫过 sweep 区间
var _angle_deg := 0.0
var _idle_phase := 0.0
var _sweeping := false
var _tween: Tween = null

## 待机时的上下浮动量（像素）与剑身微倾角（度）—— 让悬浮「活」起来
var _bob_y := 0.0
var _tilt_deg := 0.0
## 攻击时的自旋角（度）—— 飞剑感的关键，扫弧的同时剑自身在转
var _spin_deg := 0.0
## 攻击时的「伸出倍数」：> 1 表示往攻击方向捅出去（前刺用），1 = 正常半径
var _reach_mult := 1.0
## 一段扫完之后先停这么久再回位；期间若来下一段，回位被取消，保证连段连贯
const COMBO_HOLD_TIME := 0.18
## 平滑后的「基准朝向角」（弧度，0 = 右侧 / PI = 左侧）
## 转身时它逐帧转过去，于是剑会**飘**到另一边，而不是瞬移镜像
var _face_angle := PI

# ===== 挥击刀光拖尾（2026-10-27 替换分身式残影）=====
## 连着剑尖的一条细弧带；参数在 ArtDB.WEAPON_TRAIL，颜色取武器条目的 trail_color
var _trail: WeaponTrail = null
var _trail_on := false
var _trail_tween: Tween = null


func _ready() -> void:
	refresh()


## 重新读取配置并重建形象（美术换图后调用）
func refresh() -> void:
	_cfg = ArtDB.get_visual(weapon_id)
	# 武器没单独指定显示长度 → 注入全局统一基准
	# （这样换任何武器都自动等大，不用每把都填 target_length）
	if float(_cfg.get("target_length", 0.0)) <= 0.0:
		_cfg["target_length"] = ArtDB.WEAPON_DEFAULT_LENGTH
	_angle_deg = float(_cfg.get("idle_base_deg", -60.0))

	if _skin != null and is_instance_valid(_skin):
		_skin.queue_free()
		_skin = null

	# 没配贴图就不显示武器 —— 不影响任何现有表现
	_has_weapon = String(_cfg.get("texture", "")) != "" \
		or String(_cfg.get("sprite_frames", "")) != ""
	if not _has_weapon:
		visible = false
		if _trail != null and is_instance_valid(_trail):
			_trail.queue_free()
			_trail = null
		return

	visible = true
	_skin = SkinVisual.new()
	_skin.visual_id = weapon_id
	# ⚠ scale_override / offset_override 是「最高优先级」的手动覆盖。
	#   武器条目启用了 target_length（自动换算）时**绝不能设它们** ——
	#   否则 auto_fit 算出的 scale 会被这里的值覆盖回 1，武器直接撑满屏幕。
	#   只有条目明确不用自动换算（target_length <= 0）时，才把手工 scale/offset 传下去。
	if float(_cfg.get("target_length", 0.0)) <= 0.0:
		_skin.scale_override = _cfg.get("scale", Vector2.ONE)
		_skin.offset_override = _cfg.get("offset", Vector2.ZERO)
	add_child(_skin)
	_place()
	_setup_trail()


## 拖尾节点挂在角色身上（不是武器上）：武器会旋转，历史采样不能被二次旋转。
func _setup_trail() -> void:
	if _trail != null and is_instance_valid(_trail):
		_trail.queue_free()
		_trail = null
	var parent := get_parent()
	if parent == null:
		return
	_trail = WeaponTrail.new()
	_trail.name = "WeaponTrail"
	parent.add_child(_trail)
	_apply_trail_config(false)


func _apply_trail_config(finisher: bool) -> void:
	if _trail == null or not is_instance_valid(_trail):
		return
	var tcfg := ArtDB.weapon_trail()
	var color: Color = tcfg["color"]
	if _cfg.has("trail_color"):
		color = _cfg["trail_color"]
	var alpha := float(tcfg["finisher_alpha"] if finisher else tcfg["alpha"])
	var life := float(tcfg["finisher_life"] if finisher else tcfg["life"])
	var width := float(tcfg["finisher_width"] if finisher else tcfg["width"])
	_trail.configure(color, alpha, life, width)


func _trail_begin() -> void:
	_trail_on = true


func _trail_end() -> void:
	_trail_on = false


## 每帧：待机摆动（攻击期间由 tween 接管，这里不动）
func _process(delta: float) -> void:
	if not _has_weapon or _sweeping:
		return
	var speed := float(_cfg.get("idle_speed", 2.0))
	var swing := float(_cfg.get("idle_swing_deg", 12.0))
	var base := float(_cfg.get("idle_base_deg", -60.0))
	_idle_phase += delta * speed

	# 三个不同频率的正弦叠加：轨迹不会简单重复，像被法术托着不规则飘动
	var t := _idle_phase
	var wob := sin(t) * 0.62 + sin(t * 2.31 + 1.1) * 0.26 + sin(t * 4.73 + 2.4) * 0.12

	_angle_deg = base + wob * swing
	_bob_y = sin(t * 1.73 + 0.6) * float(_cfg.get("idle_bob_amp", 3.0))
	_tilt_deg = wob * float(_cfg.get("idle_tilt_deg", 4.0))

	# 平滑转向：基准角朝「角色当前水平朝向」逐帧靠拢
	# 这样转身时剑是「飘」过去的，而不是整帧瞬移镜像
	_update_face_angle(delta)

	_place()


## 触发一次挥砍：从 sweep_from_deg 扫到 sweep_to_deg，再缓慢收回待机位
## aim_dir：攻击方向（决定武器在哪一侧扫）
## 触发一次攻击挥砍
## aim_dir  攻击方向
## seg      本段的轨迹配置（来自 ArtDB 的 combo_sweeps[段号]），可留空用默认
##   from_deg / to_deg   本段起止角（相对朝向；-90=屏幕上方, +90=下方）
##   sweep_time          本段扫击时长（秒）
##   reach_mult          伸出倍数（前刺用，>1 会往攻击方向捅出去）
##   spin_turns          本段自旋圈数（负数 = 反向转）
##   windup              是否先做「蓄力后撤」（只有连段第 1 段需要）
##
## 连段连贯性：每段扫完会先停 COMBO_HOLD_TIME 再回位；若期间来了下一段，
## 旧 tween 被 kill，新段从**当前位置**接着走，所以不会出现回位再出发的断续感。
## 本段刀锋「扫到正前方」的时刻（秒，自 sweep() 起算）= 起手后撤 + 扫击进度。
## 只服务表现时序：普攻出伤挂在这个点，才和玩家看到的刀光对得上。
## hit_at 写在 ArtDB 的 combo_sweeps 段配置里（0.2~0.95，默认 0.55）。
func strike_delay(seg: Dictionary = {}) -> float:
	var sweep_time := float(seg.get("sweep_time", _cfg.get("sweep_time", 0.18)))
	var ratio := clampf(float(seg.get("hit_at", 0.55)), 0.2, 0.95)
	var delay := sweep_time * ratio
	if bool(seg.get("windup", false)):
		delay += float(_cfg.get("windup_time", 0.09))
	return delay


func sweep(aim_dir: Vector2, seg: Dictionary = {}, finisher := false) -> void:
	if not _has_weapon:
		return
	if aim_dir.length_squared() > 0.0001:
		facing_dir = aim_dir.normalized()
		# 攻击立即在正确一侧展开，不等待待机那套平滑转向
		if not is_zero_approx(facing_dir.x):
			_face_angle = 0.0 if facing_dir.x > 0.0 else PI

	if _tween != null and _tween.is_valid():
		_tween.kill()

	_sweeping = true

	var from_deg := float(seg.get("from_deg", _cfg.get("sweep_from_deg", -70.0)))
	var to_deg := float(seg.get("to_deg", _cfg.get("sweep_to_deg", 70.0)))
	var sweep_time := float(seg.get("sweep_time", _cfg.get("sweep_time", 0.18)))
	var back_time := float(_cfg.get("return_time", 0.3))
	var idle_base := float(_cfg.get("idle_base_deg", 180.0))
	var reach := float(seg.get("reach_mult", 1.0))
	var spins := float(seg.get("spin_turns", _cfg.get("spin_turns", 0.25))) * 360.0
	var do_windup := bool(seg.get("windup", false))
	var windup_deg := float(_cfg.get("windup_deg", -115.0))
	var windup_time := float(_cfg.get("windup_time", 0.09))

	# 进入攻击：清掉待机浮动，否则位置会歪
	_bob_y = 0.0
	_tilt_deg = 0.0
	_spin_deg = 0.0

	_tween = create_tween()

	# ① 起手
	if do_windup:
		# 首段：先往后撤（收势），再甩到本段起点
		_tween.tween_method(_set_angle, _angle_deg, windup_deg, windup_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_tween.tween_method(_set_angle, windup_deg, from_deg, 0.06) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	else:
		# 后续段：本段起点就是上一段终点，几乎零位移，短过渡即可
		_tween.tween_method(_set_angle, _angle_deg, from_deg, 0.05) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# ② 出击：爆发式扫过 + 自旋 + （前刺时）伸出
	_tween.tween_method(_set_angle, from_deg, to_deg, sweep_time) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_method(_set_spin, 0.0, spins, sweep_time + back_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if not is_equal_approx(reach, 1.0):
		_tween.parallel().tween_method(_set_reach, 1.0, reach, sweep_time * 0.8) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 刀光拖尾：起手结束才开始采样，扫完立刻停；采样窗口与武器扫弧同一套时间
	_trail_on = false
	if _trail != null and is_instance_valid(_trail):
		_trail.clear()
	_apply_trail_config(finisher)
	if _trail_tween != null and _trail_tween.is_valid():
		_trail_tween.kill()
	_trail_tween = create_tween()
	_trail_tween.tween_interval((windup_time + 0.06) if do_windup else 0.05)
	_trail_tween.tween_callback(_trail_begin)
	_trail_tween.tween_interval(sweep_time)
	_trail_tween.tween_callback(_trail_end)

	# ③ 停顿窗口：给下一段留出「不回位」的时间
	_tween.tween_interval(COMBO_HOLD_TIME)

	# ④ 回位：飘回背后（前刺的话同时把伸出的距离收回）
	_tween.tween_method(_set_angle, to_deg, idle_base, back_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if not is_equal_approx(reach, 1.0):
		_tween.parallel().tween_method(_set_reach, reach, 1.0, back_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(func() -> void:
		_sweeping = false
		_spin_deg = 0.0
		_idle_phase = 0.0
	)


## 设置伸出倍数（前刺途中会从 1 涨到 reach，再收回 1）
func _set_reach(mult: float) -> void:
	_reach_mult = mult
	_place()


## 攻击自旋角（度）。叠加在正常朝向之上，所以「扫」和「转」可以同时发生
func _set_spin(deg: float) -> void:
	_spin_deg = deg
	_place()


func _set_angle(deg: float) -> void:
	_angle_deg = deg
	_place()


## 把「相对朝向的角度」换算成实际位置与自身朝向
## 让基准朝向角平滑地转向角色当前水平朝向
##
## 几何说明：剑的位置角 a = _face_angle + idle_base_deg(180°)。
## 所以 _face_angle: PI(左) → 0(右) 的过程中，a 会经过 PI/2 —— 那是**屏幕上方**
## （Godot 里 y 向下，角度增大是顺时针，PI/2 指向下…所以这里要反过来）：
##   _face_angle 递减：PI → PI/2 → 0  ⇒  a = PI+PI → PI/2+PI → 0+PI
##   sin(PI*1.5) = -1 → y 最负 = 屏幕上方 ✓
## 结论：让 _face_angle 在两个值之间**线性递减/递增**即可自然经过头顶，
## 关键是别把方向算反（反了会从角色身前绕过去，挡脸）。
func _update_face_angle(delta: float) -> void:
	var h := signf(facing_dir.x)
	if is_zero_approx(h):
		return   # 朝正上/正下：保持当前侧面，不来回跳
	var target := 0.0 if h > 0.0 else PI
	# 用 wrapf 取最短角差，避免 _face_angle 归一化后绕远路
	var diff := wrapf(target - _face_angle, -PI, PI)
	var speed := deg_to_rad(float(_cfg.get("turn_speed_deg", 520.0)))
	_face_angle += signf(diff) * minf(absf(diff), speed * delta)
	_face_angle = fposmod(_face_angle, TAU)


func _place() -> void:
	if _skin == null:
		return
	# orbit_radius < 0 表示自动：目标长度的一半 + 6px，让剑柄刚好露在角色体外
	var radius := float(_cfg.get("orbit_radius", -1.0))
	if radius < 0.0:
		radius = float(_cfg.get("target_length", 70.0)) * 0.5 + 6.0
	radius *= _reach_mult   # 前刺时从这里捅出去
	var height := float(_cfg.get("orbit_height", -30.0))
	# 「背后」始终只按**水平**朝向判定：角色朝右 → 剑在左，朝左 → 剑在右。
	# ⚠ 这里不能加 `not _sweeping` 条件：
	#   旧写法在攻击/回位期间用完整朝向，若角色朝上/下，剑会往身前回，
	#   等 _sweeping 结束再瞬间跳到侧面 —— 表现为「剑不跟着左右转向切换」。
	#   统一用水平分量后，转向在任何阶段都立即生效，且回位终点与待机位一致。
	# 基准方向：横向模式用「平滑朝向角」（转身时飘过去）；
	# 非横向模式退回完整朝向（含上下）
	var base_angle: float = _face_angle
	if not bool(_cfg.get("idle_horizontal_only", true)):
		base_angle = facing_dir.angle()

	var a: float = base_angle + deg_to_rad(_angle_deg)

	# 极坐标定位：以角色为圆心
	position = Vector2(cos(a), sin(a)) * radius + Vector2(0.0, height + _bob_y)

	# 刀光拖尾采样：轴心 = 角色局部 (0, height)，半径取到剑尖
	if _trail_on and _trail != null and is_instance_valid(_trail):
		var half_len := float(_cfg.get("target_length", ArtDB.WEAPON_DEFAULT_LENGTH)) * 0.5
		_trail.push_sample(Vector2(0.0, height + _bob_y), a, radius + half_len)

	# 待机可固定为「竖立」（不随位置转）；攻击时才按径向摆正，做出挥砍感
	var rot_deg: float = rad_to_deg(a) + float(_cfg.get("sprite_rotation_deg", 0.0))
	if not _sweeping:
		var idle_rot := float(_cfg.get("idle_rotation_deg", -999.0))
		if idle_rot > -900.0:
			rot_deg = idle_rot
	rotation = deg_to_rad(rot_deg + _tilt_deg + _spin_deg)


## 本段攻击的**视觉最大触达距离**（角色中心 → 剑尖）
## 供命中判定对齐「看到多远就打多远」：
##   触达 = 悬浮半径 × 伸出倍数 + 半把剑长
func seg_reach(seg: Dictionary = {}) -> float:
	var radius := float(_cfg.get("orbit_radius", -1.0))
	if radius < 0.0:
		radius = float(_cfg.get("target_length", 70.0)) * 0.5 + 6.0
	var reach := float(seg.get("reach_mult", 1.0))
	var half_len := float(_cfg.get("target_length", 70.0)) * 0.5
	return radius * reach + half_len


## 切换武器外观（装备不同武器时调用）
## 传入的 id 若在 ArtDB.VISUALS 里没有配贴图，会自动隐藏武器，不会报错
func set_weapon(id: String) -> void:
	if id == weapon_id:
		return
	weapon_id = id
	refresh()


## 是否已配置武器贴图（未配置时 controller 不必调用 sweep）
func has_weapon() -> bool:
	return _has_weapon
