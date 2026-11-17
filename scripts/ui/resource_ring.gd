class_name ResourceRing
extends Control
## 三才灵环 —— 气血 / 灵力 / 精力 的随身读数（2026-11-12 定稿）
##
## 三轮迭代的失败原因各不相同，全部记下来，别再往回改：
##   v1 竖玉简：高饱和色铺在大面积上 = 三个色块叠在黑胶囊里（「方框堆叠」），
##      而且简比人物本体还高 → 用户：「像板块、突兀、硬边」
##   v2 降饱和 + 缩行程 → 用户：「还没有原来的清晰可见」（方向完全错）
##   v3 同心双弧 + 上面一排点 → 实机截图暴露：点阵压在灵弧上糊成一团，
##      而且构图读起来是一张笑脸
##   v4 左右分侧单节点、整环 z=6 → 用户：「**圆环尾部没有被玩家遮住，像贴图一样**」
##      —— 整条环画在一个 z 上，远侧（后半场）本该被身体挡住，却盖过头顶画在前面。
##
## 定稿构图：**一个环 + 前后两层深度**
##   血 = 左半（90°→270°）｜灵 = 右半（−90°→90°）｜精 = 环内底前一排光点
##   都从脚下往头顶填充，掉的时候从头顶那头排空；上下各留 8° 缺口，
##   让左右两半读作「两段弧」而不是一个整圈（闭合正圆最易读成判定范围）。
##   ⚠ **近侧画在人物之前、远侧画在人物之后**（`RingHalf.front`），
##     这样环才真的「抱住」人，而不是贴在人身上的贴纸。远侧另压暗 28% 加强纵深。
##
## 四条硬要求逐条落实：
##   ① 没有外壳：不画 Panel / ColorRect / 圆角矩形 / 描边 / 投影
##   ② 没有硬边：只用 `draw_arc(..., true)` 真抗锯齿 + 宽淡光晕垫底 + 端点柔光收口。
##      ⚠ 4.7 没有 `draw_set_antialiased()`，折线近似必然硬边；椭圆靠
##      `draw_set_transform` 的非等比缩放把正圆压扁（`draw_arc` 只能画正圆）。
##      ⚠ `draw_set_transform()` 零参复位在本机是解析错误（Too few arguments），必须给全三个参数。
##   ③ 三种通道不同形：左弧 / 右弧 / 点阵，靠分侧与形状区分，不只靠颜色
##   ④ 清晰度只准升：每半环弧长 ≈84px，是旧横条 38px 的 2.2 倍；
##      颜色一律用 `UIKit.C_HUD_*` 原色**不降饱和**
##
## 状态回执（屏幕上不常驻文字，用户定）：
##   · 掉血 → 血弧提亮 0.18s ｜ 灵力回升 → 亮点沿右弧爬动
##   · 力竭 → 一道余烬色光扫过点阵（技能栏上方那行文字已撤）
##   · 低血 → 屏幕暗角保留（唯一二级通道）
##
## v5（2026-11-12 用户）：「气血/灵力过于朴素而且是硬边」「精力原点改金色 + 轻微闪光，
## 一格都没有就闪红」。改法只动笔触、不动构图：
##   · 弧从「一层 2.4px 芯」改成 **5 层由宽到窄的柔光**（ARC_LAYERS），芯收到 1.3px ——
##     单层线在任何底色上都是一条硬边，叠层才有由外向内衰减的边。
##   · 已填充段加一道**头尾收窄的流光**（_streak）+ 填充头的一团柔光（_head_bloom），
##     让「剩多少」之外还有「在流动」的时间层次。
##   · 精力原点：金色 + 每颗错相位的呼吸高光与小金环（stamina_dot_twinkle），
##     **一格都没有时整排转告急红并呼吸**（stamina_dot_color 是唯一判据）。

const RX := 38.0             ## 环横半径
const RY := 19.0             ## 环纵半径（透视压扁）
const RX_SP := 26.0          ## 精力点阵内椭圆（必须明显小于环，否则压在弧上）
const RY_SP := 11.0
const CENTER_Y := -18.0      ## 环心压在小腹：围周身，不是站地上
const GAP_DEG := 8.0         ## 上下两个缺口，把整圈切成左右两半
const HALO_W := 10.0         ## 最外层光雾的宽度（也是整块画布的半宽，别让柔光被算小了）
const CORE_W := 1.6          ## 灯芯：1px 上下就是一条线，1.6 才读得出「光」
## 柔边的做法：**同一条弧叠 6 层**，由外向内「越宽越淡、越窄越亮」。
## ⚠ 单层 2px 线在深色地面上就是一条硬边（用户 2026-11-12 的原话），再多颜色也没用；
##   但最外两层也不能太淡 —— 实机是 1× 不是放大图，雾太薄等于没有。
const ARC_LAYERS := [
	[10.0, 0.035],
	[7.0, 0.065],
	[4.6, 0.140],
	[3.0, 0.330],
	[1.9, 0.720],
	[0.9, 1.000],
]
const STREAK_PERIOD := 3.4   ## 已填充弧上流过一道光的周期（秒）
const STREAK_SPAN_DEG := 16.0
const SP_DOT := 2.2
const SP_SPAN_DEG := 74.0    ## 点阵在底部占的总角度
const SEG_DEG := 5.0         ## 弧的分段密度（只用来算段数）
const BACK_DIM := 0.72       ## 远侧整层压暗，加强「绕到身后」的纵深

var _hp_ratio := 1.0
var _mp_ratio := 1.0
var _stamina := 0
var _stamina_max := 5
var _exhaust_left := 0.0
var _exhaust_total := 1.0
var _t := 0.0
var _hit_flash := 0.0
var _mana_flow := 0.0
## 前后两层：近侧盖过身体、远侧藏到身体后面
var _back: RingHalf = null
var _front: RingHalf = null


## 一层环。`front=true` 画在人物之前（近侧），`false` 画在人物之后（远侧）。
class RingHalf:
	extends Control
	var front := true
	var host: ResourceRing = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _process(_delta: float) -> void:
		# ⚠ is_visible_in_tree() 不是 visible：父级隐藏时子节点自己的 visible 仍为 true
		if host != null and is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		if host != null:
			host._paint_half(self, front)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var half := RX + HALO_W
	size = Vector2(half * 2.0, (RY + HALO_W) * 2.0)
	custom_minimum_size = size
	pivot_offset = size * 0.5
	position = Vector2(-size.x * 0.5, CENTER_Y - size.y * 0.5)


func _ready() -> void:
	# 远侧压到 Visual 之后（-2），近侧提到人物之前（+6）——
	# 只给一层 z 就是 v4 的 bug：整条环都盖在人身上，看着像贴纸
	_back = RingHalf.new()
	_back.name = "Back"
	_back.front = false
	_back.host = self
	_back.z_index = -2
	add_child(_back)
	_front = RingHalf.new()
	_front.name = "Front"
	_front.front = true
	_front.host = self
	_front.z_index = 6
	add_child(_front)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	_hit_flash = maxf(0.0, _hit_flash - delta / 0.18)
	_mana_flow = maxf(0.0, _mana_flow - delta / 0.45)


## 唯一写入口。接口与前几版一致，player 的三个 _update_*_bar 都汇到这里。
func set_state(hp_ratio: float, mp_ratio: float, stamina: int, stamina_max: int) -> void:
	var hurt := hp_ratio < _hp_ratio - 0.0005
	_hp_ratio = clampf(hp_ratio, 0.0, 1.0)
	if mp_ratio > _mp_ratio + 0.0005:
		_mana_flow = 1.0
	_mp_ratio = clampf(mp_ratio, 0.0, 1.0)
	_stamina = stamina
	_stamina_max = clampi(stamina_max, 1, 8)
	if hurt:
		flash()


func flash() -> void:
	_hit_flash = 1.0


func set_exhaust(left: float, total: float) -> void:
	_exhaust_left = maxf(0.0, left)
	_exhaust_total = maxf(0.001, total)


func _pt(rx: float, ry: float, theta: float) -> Vector2:
	return Vector2(cos(theta) * rx, sin(theta) * ry) + size * 0.5


## 把角度区间按「近侧 [0,PI] / 远侧 [PI,TAU]」切开。
## 跨度 <TAU 时最多穿越一条边界，但这里写成通用的逐段扫描，
## 免得以后把缺口调大或改成整圈时又要重写。
func _clip_half(from: float, to: float, want_front: bool) -> Array:
	var res: Array = []
	var cur := fposmod(from, TAU)
	var end := cur + maxf(0.0, to - from)
	while cur < end - 0.0005:
		var is_front := fposmod(cur, TAU) < PI
		var next_bound := (floorf(cur / PI) + 1.0) * PI
		var part_to := minf(next_bound, end)
		if is_front == want_front:
			res.append([cur, part_to])
		cur = part_to
	return res


## 椭圆弧：`draw_arc` 只能画正圆，所以用非等比缩放把正圆压扁，仍走真抗锯齿。
func _arc(ci: CanvasItem, rx: float, ry: float, from: float, to: float,
		col: Color, w: float) -> void:
	if to - from <= 0.002:
		return
	var k := ry / rx
	var seg := maxi(10, int(rad_to_deg(to - from) / SEG_DEG))
	ci.draw_set_transform(size * 0.5, 0.0, Vector2(1.0, k))
	ci.draw_arc(Vector2.ZERO, rx, from, to, seg, col, w, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 一段柔光弧（按层切分后逐段画）。
## **柔边全在这 5 层里**：外层宽而淡、内层窄而亮，边上就不会出现「一条线」的硬边。
func _glow_arc(ci: CanvasItem, rx: float, ry: float, from: float, to: float,
		col: Color, want_front: bool, dim: float) -> void:
	if to - from <= 0.004:
		return
	for seg in _clip_half(from, to, want_front):
		for layer in ARC_LAYERS:
			_arc(ci, rx, ry, seg[0], seg[1],
					Color(col.r, col.g, col.b, float(layer[1]) * dim), float(layer[0]))
	# 端点收口：也是三层，别在弧头留一个硬圆点
	for th in [from, to]:
		if (fposmod(th, TAU) < PI) != want_front:
			continue
		var p := _pt(rx, ry, th)
		ci.draw_circle(p, 4.8, Color(col.r, col.g, col.b, 0.07 * dim))
		ci.draw_circle(p, 2.4, Color(col.r, col.g, col.b, 0.16 * dim))
		ci.draw_circle(p, 0.9, Color(col.r, col.g, col.b, 0.42 * dim))


## 填充头的一团柔光：让这一截弧读作「倒到这里」，而不是断在一根线头上。
func _head_bloom(ci: CanvasItem, rx: float, ry: float, th: float, col: Color,
		want_front: bool, dim: float) -> void:
	if (fposmod(th, TAU) < PI) != want_front:
		return
	var p := _pt(rx, ry, th)
	ci.draw_circle(p, 6.4, Color(col.r, col.g, col.b, 0.055 * dim))
	ci.draw_circle(p, 3.4, Color(col.r, col.g, col.b, 0.14 * dim))
	ci.draw_circle(p, 1.5, Color(col.r, col.g, col.b, 0.38 * dim))


## 已填充弧上缓慢流过的一道柔光（时间层次）。
## ⚠ 头尾各分 5 片、alpha 按正弦收窄 —— 直接画一段弧会在两端留两个硬切口。
func _streak(ci: CanvasItem, rx: float, ry: float, from: float, to: float,
		col: Color, want_front: bool, phase: float, dim: float) -> void:
	var span := deg_to_rad(STREAK_SPAN_DEG)
	if to - from <= span * 1.05:
		return
	var mid := lerpf(from + span * 0.5, to - span * 0.5, fposmod(phase, 1.0))
	var tint := col.lerp(Color(1.0, 1.0, 1.0, 1.0), 0.55)
	var slices := 5
	for k in slices:
		var a := sin(PI * (float(k) + 0.5) / float(slices))
		var s0 := mid - span * 0.5 + span * float(k) / float(slices)
		var s1 := mid - span * 0.5 + span * float(k + 1) / float(slices)
		for seg in _clip_half(s0, s1, want_front):
			_arc(ci, rx, ry, seg[0], seg[1],
					Color(tint.r, tint.g, tint.b, 0.09 * a * dim), 4.6)
			_arc(ci, rx, ry, seg[0], seg[1],
					Color(tint.r, tint.g, tint.b, 0.30 * a * dim), 1.5)


## 一层的全部绘制
func _paint_half(ci: CanvasItem, want_front: bool) -> void:
	var g := deg_to_rad(GAP_DEG)
	var span := PI - g * 2.0
	var dim := 1.0 if want_front else BACK_DIM
	# 空槽：交代满值有多长，不然短弧会被误读成「环本来就这么短」。
	# 同样走多层，避免未填满的那一截比已填的还「硬」。
	for seg in _clip_half(PI * 0.5 + g, PI * 1.5 - g, want_front):
		_arc(ci, RX, RY, seg[0], seg[1], Color(0.88, 0.92, 0.88, 0.050 * dim), 4.6)
		_arc(ci, RX, RY, seg[0], seg[1], Color(0.88, 0.92, 0.88, 0.100 * dim), 1.4)
	for seg in _clip_half(-PI * 0.5 + g, PI * 0.5 - g, want_front):
		_arc(ci, RX, RY, seg[0], seg[1], Color(0.88, 0.92, 0.88, 0.042 * dim), 4.6)
		_arc(ci, RX, RY, seg[0], seg[1], Color(0.88, 0.92, 0.88, 0.090 * dim), 1.4)

	# 血 = 左半，从脚下往头顶填充（头在 to 那头）
	var hp_col := UIKit.C_HUD_HP if _hp_ratio >= 0.3 else UIKit.C_ALERT
	var hp_head := PI * 0.5 + g + span * _hp_ratio
	_glow_arc(ci, RX, RY, PI * 0.5 + g, hp_head, hp_col, want_front, dim)
	_streak(ci, RX, RY, PI * 0.5 + g, hp_head, hp_col, want_front, _t / STREAK_PERIOD, dim)
	_head_bloom(ci, RX, RY, hp_head, hp_col, want_front, dim)
	# 灵 = 右半，同样从脚下往头顶填充（头在 from 那头）
	var mp_col := UIKit.C_HUD_MANA if _mp_ratio >= 0.5 else UIKit.C_HUD_MANA_LOW
	var mp_head := PI * 0.5 - g - span * _mp_ratio
	_glow_arc(ci, RX, RY, mp_head, PI * 0.5 - g, mp_col, want_front, dim)
	_streak(ci, RX, RY, mp_head, PI * 0.5 - g, mp_col, want_front,
			_t / STREAK_PERIOD + 0.5, dim)
	_head_bloom(ci, RX, RY, mp_head, mp_col, want_front, dim)

	# 精力点阵只在底前（近侧），远侧层不画
	if want_front:
		_stamina_dots(ci)

	# 灵力回升亮点：按它当前落在哪一侧，画在那一层
	if _mana_flow > 0.0:
		var th := lerpf(PI * 0.5 - g, PI * 0.5 - g - span * _mp_ratio, 1.0 - _mana_flow)
		if (fposmod(th, TAU) < PI) == want_front:
			var p := _pt(RX, RY, th)
			ci.draw_circle(p, 5.0, Color(0.62, 0.80, 1.0, 0.18 * _mana_flow * dim))
			ci.draw_circle(p, 2.0, Color(0.80, 0.92, 1.0, 0.78 * _mana_flow * dim))
	# 掉血回执：血弧提亮
	if _hit_flash > 0.0:
		for seg in _clip_half(PI * 0.5 + g, hp_head, want_front):
			_arc(ci, RX, RY, seg[0], seg[1],
					Color(1.0, 0.97, 0.90, 0.55 * _hit_flash * dim), CORE_W + 1.2)


## 精力见底时的呼吸相位（0..1）。颜色与体积**共用这一拍**，不然点和雾各走各的、
## 看着像在抖。周期 4.2rad/s ≈ 0.67Hz：一眼能看出在催，但不至于频闪。
func stamina_panic() -> float:
	return 0.5 + 0.5 * sin(_t * 4.2)


## 第 i 个精力原点此刻该是什么色 —— **绘制与探针共用这一处判据**。
##   · 一格都没有 → 告急红 + 呼吸（「没体力了」的即时回执）
##   · 有这格     → 金色
##   · 空格       → 极淡灰白（交代上限）
func stamina_dot_color(i: int) -> Color:
	if _stamina <= 0:
		var c := UIKit.C_ALERT
		# 谷底也要看得出是红：0.35 起跳，峰顶 0.95
		return Color(c.r, c.g, c.b, 0.35 + 0.60 * stamina_panic())
	if i >= _stamina:
		return Color(0.90, 0.93, 0.92, 0.15)
	var gold := UIKit.C_HUD_STAMINA_ON
	return Color(gold.r, gold.g, gold.b, 0.94)


## 闪光强度 0..1：每颗错开相位，慢慢起伏 —— 要的是「有点活气」，不是整排一起闪
func stamina_dot_twinkle(i: int) -> float:
	return 0.5 + 0.5 * sin(_t * 1.9 + float(i) * 1.7)


## 精力点阵：环内底前一排原点（近侧）。半径压到 RX_SP 才不叠在弧上。
## 金色原点 + 轻微闪光；**一格都没有时整排闪红**（与力竭倒计时那道光扫并存）。
func _stamina_dots(ci: CanvasItem) -> void:
	var n := _stamina_max
	var span := deg_to_rad(SP_SPAN_DEG)
	var start := PI * 0.5 + span * 0.5
	for i in range(n):
		var f := 0.5 if n == 1 else float(i) / float(n - 1)
		var p := _pt(RX_SP, RY_SP, start - span * f)
		var tw := stamina_dot_twinkle(i)
		var col := stamina_dot_color(i)
		if _stamina <= 0:
			# 见底：红雾随呼吸涨落，点本身也跟着大一点点。
			# ⚠ 雾半径要收着 —— 5 颗相距才 10 来像素，铺大开就糊成一团暖色斑，读不出「几格」。
			var pan := stamina_panic()
			ci.draw_circle(p, SP_DOT + 2.2 + 1.4 * pan,
					Color(col.r, col.g, col.b, 0.10 + 0.16 * pan))
			ci.draw_circle(p, SP_DOT * (1.0 + 0.16 * pan), col)
		elif i < _stamina:
			ci.draw_circle(p, SP_DOT + 3.0, Color(col.r, col.g, col.b, 0.09 + 0.09 * tw))
			ci.draw_circle(p, SP_DOT * (1.0 + 0.06 * tw), col)
			ci.draw_circle(p, SP_DOT * 0.45,
					Color(1.0, 0.98, 0.88, 0.50 + 0.40 * tw))
			# 闪光：一圈往外散开的金环，只在波峰附近看得见
			var spark := pow(tw, 3.0)
			ci.draw_arc(p, SP_DOT + 1.2 + 2.6 * spark, 0.0, TAU, 14,
					Color(1.0, 0.94, 0.72, 0.38 * spark), 0.9, true)
		else:
			ci.draw_circle(p, SP_DOT * 0.8, col)
	# 力竭倒计时：一道余烬色光扫过点阵（和红闪同族色，不抢戏）
	if _exhaust_left > 0.0:
		var k := 1.0 - clampf(_exhaust_left / _exhaust_total, 0.0, 1.0)
		var q := _pt(RX_SP, RY_SP, start - span * k)
		ci.draw_circle(q, 5.5, Color(1.0, 0.55, 0.42, 0.12))
		ci.draw_circle(q, 2.0, Color(1.0, 0.72, 0.58, 0.62))
