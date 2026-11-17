class_name FoldField
extends Node2D
## 折痕场的持有者（2026-11-02）—— 叠纸「空间连通」机制的运行时唯一实例源
##
## 它管四件事：痕在哪（含 P2 的第二条）、多久重折一次、两端圆牌踩进去怎么换位置、
## 以及给 BOSS 与玩家同一套查询接口（fold_dist / mirror_hit_span / seam_exit_near）。
## 几何公式本身全在 FoldLaw，这里只做「持有 + 计时 + 渲染 + 穿缝结算」。
##
## 两种来源共用一个类：
##   场内痕（personal = false）：由叠纸持有，全场玩家侧单位都可穿缝；到点重折。
##   个人痕（personal = true）：由玩家的「裁痕」持有，
##     只对持有者本人的落点生效，到期消失 —— 所以出照影界照样能用。

const VISUAL_SCRIPT := preload("res://scripts/combat/fold_visual.gd")
const SEAM_SCRIPT := preload("res://scripts/combat/fold_seam.gd")

var personal: bool = false
var owner_unit: Node2D = null          ## personal 时的唯一有效方
## 场内痕重折时围绕谁布（玩家位置；痕必须参与这场架，不能只跟着 BOSS 走）
var anchor_pos: Vector2 = Vector2.ZERO
## 意图折的锁定值：由 BOSS 在**压痕预告开始那一瞬间**写入，不是每帧跟。
## ⚠ 每帧跟就等于痕永远折向玩家"现在"的位置，1.2 秒预告变成纯装饰；
##   锁在预告开始那一刻，玩家才真的有时间"看见预告 → 走出中垂线窗口 → 这一折落空"。
var aim_from: Vector2 = Vector2.ZERO
var aim_to: Vector2 = Vector2.ZERO
var _aim_ready := false
var _aim_along := false    ## 这一折要「顺折」（痕顺着 BOSS→玩家）而不是「横折」
var arena_center: Vector2 = Vector2.ZERO
var arena_half: Vector2 = Vector2.ZERO
var arena_margin: float = 60.0

var phase: int = 1
var spans: Array = []                  ## [{a: Vector2, b: Vector2}]
var life_left: float = 0.0             ## personal 用；非 personal 不限时

var _visuals: Array = []
var _seams: Array = []
var _refold_left: float = FoldLaw.REFOLD_P1
var _preview_left: float = 0.0
var _down_left: float = 0.0
var _re_cd: Dictionary = {}            ## 单位 id -> 剩余重触发间隔
var _exit_guard: Dictionary = {}       ## 单位 id -> 出牌后的短暂保护


# ===================== 构建 =====================

## 场内痕：由 BOSS 开场调用
func open_arena(center: Vector2, half: Vector2, margin: float, at: Vector2) -> void:
	arena_center = center
	arena_half = half
	arena_margin = margin
	phase = 1
	_refold_left = FoldLaw.refold_for(phase)
	rebuild_near(at)


func set_phase(p: int) -> void:
	if p == phase:
		return
	phase = p
	_refold_left = FoldLaw.refold_for(phase)
	_preview_left = 0.0
	rebuild_near(global_owner_pos())


## 玩家裁痕：立一条只属于自己的痕
func build_personal(owner: Node2D, from: Vector2, toward: Vector2,
		length: float, life: float) -> void:
	personal = true
	owner_unit = owner
	var d := toward.normalized()
	if d.length_squared() < 0.01:
		d = Vector2.RIGHT
	# 痕与「朝哪打」垂直：你面向谁，镜像就落在谁那一侧
	var n := Vector2(-d.y, d.x)
	var c := from + d * FoldLaw.PLAYER_SEAM_OFFSET
	spans = [{"a": c - n * length * 0.5, "b": c + n * length * 0.5}]
	life_left = life
	_refold_left = 1.0e9
	_rebuild_nodes()


func rebuild_near(at: Vector2) -> void:
	spans = [_span_near(at)]
	if phase >= 2:
		# 二折取**平行**偏移：两条平行折痕把场切成三区，复合映射是平移 —— 三区的说法才站得住
		spans.append(_parallel_span(spans[0], at))
	_rebuild_nodes()


## BOSS 在压痕预告开始时锁定这一折的意图（之后 1.2 秒不再更新）
## along = true 要的是「顺折」：痕顺着 BOSS→玩家铺，不产生镜像落点，
##   换来的是循痕能贴着这条线滑过去割（两式各有各的几何，见 _span_along）。
func set_aim(from: Vector2, to: Vector2, along: bool = false) -> void:
	aim_from = from
	aim_to = to
	_aim_along = along
	_aim_ready = not FoldLaw.aim_window(from.distance_to(to), FoldLaw.reach_for(phase)).is_empty() \
			or along


## BOSS 主动要求"现在就重折一次"：痕已经被自己穿过去 / 被碎痕摊平之后，
## 不必干等下一次周期折。仍然走 1.2 秒预告 —— 玩家永远有可读的前置信息，
## 这不是偷偷改场地。
func request_refold() -> bool:
	if personal or _down_left > 0.0 or _preview_left > 0.0:
		return false
	_preview_left = FoldLaw.PREVIEW_TIME
	_sync_state()
	return true


## 意图折：痕摆成「玩家折过来就落在 BOSS 面前」。窗口算不出来（离得太远）就退回随机折。
func rebuild_aimed() -> void:
	var sp := _span_along(aim_from, aim_to) if _aim_along else {}
	if sp.is_empty():
		## 顺折摆不下（贴边被拽歪 / 离得太近）→ 自动退回横折，不白折一次
		sp = _span_aimed(aim_from, aim_to)
	if sp.is_empty():
		## 带抖动的意图折被场地边界卡住时，再照押痕那一套摆一次（不抖、不偏置、逐档收短）。
		## 直接跳到随机折就是用户报的"乱放" —— 明明还有一折是可以照着人摆的。
		sp = _bisect_span(aim_from, aim_to, 420.0)
	if sp.is_empty():
		rebuild_near(global_owner_pos())
		return
	spans = [sp]
	if phase >= 2:
		spans.append(_parallel_span(sp, aim_to))
	_rebuild_nodes()


## 顺折：痕的方向顺着 BOSS→玩家。两者都落在痕线上，侧向符号是 0，
## `mirror_valid` 按"必须异侧"直接回绝 —— 所以这一折**不产生镜像落点**，
## 它换来的是「循痕」能贴着这条线滑过去割。
## ⚠ 为什么需要它：意图折默认是横折（垂直于连线），而循痕的走廊是"沿痕方向的一条带"，
##   横折的痕与连线垂直 ⇒ 玩家到那条带的垂直距离等于整个 BOSS↔玩家距离（300+），
##   永远超出 66 的半宽 —— 实测三段模拟里循痕一次都没出场，等于从招式表里抹掉了一门。
func _span_along(from: Vector2, to: Vector2) -> Dictionary:
	var d := from.distance_to(to)
	if d < 200.0 or d > 380.0:
		return {}
	var u := (to - from) / d
	var mid := from + u * (d * 0.5)
	var half := clampf(d * 0.5, 170.0, 430.0)
	for trim in [1.0, 0.8, 0.6, 0.4]:
		var sp := _span_at(mid, u, half * trim)
		var a := sp.get("a", Vector2.ZERO) as Vector2
		var b := sp.get("b", Vector2.ZERO) as Vector2
		## 被场地边界横向拽歪就不算：循痕的走廊要的是"贴着这条线"，线一挪这一式就空放
		if FoldLaw._perp_len(a, b, to) <= 46.0 and FoldLaw._perp_len(a, b, from) <= 46.0:
			return sp
	return {}


## 把痕摆成垂直于 BOSS→玩家连线、中心落在合法窗口里，并**验证折过来真的能打到人**。
## ⚠ 不能只按公式摆完就算：`_span_at` 会把整条痕平移回场内，贴边时这一拽就是几百 px，
##   痕虽然还"垂直于连线"，几何上却已经把对位点甩出扇形之外了 —— 实测押痕之后
##   玩家离痕仍是 FAR_EPS 就是这个。所以逐档试长度，取第一个验证通过的结果。
## biased = true 时中心取窗口靠玩家那一段（周期性重折用：BOSS 追两步就穿过痕，
##   摆在正中撑不住）；false 时取 d/2 钳进窗口（押痕用：那一式是教科书，
##   玩家要能看到"对位点就在我脚下"）。
func _intent_span(from: Vector2, to: Vector2, jitter_deg: float, biased: bool) -> Dictionary:
	var d := from.distance_to(to)
	var win: Array = FoldLaw.aim_window(d, FoldLaw.reach_for(phase))
	if win.is_empty():
		return {}
	var u := (to - from) / maxf(d, 1.0)
	var t := lerpf(float(win[0]), float(win[1]), clampf(FoldLaw.AIM_T_BIAS
			+ randf_range(-FoldLaw.AIM_SLIDE, FoldLaw.AIM_SLIDE), 0.0, 1.0)) \
			if biased else clampf(d * 0.5, float(win[0]), float(win[1]))
	var n := Vector2(-u.y, u.x).rotated(deg_to_rad(
			randf_range(-jitter_deg, jitter_deg)))
	var c := from + u * t
	var reach := FoldLaw.reach_for(phase)
	for half_len in [260.0, 340.0, 440.0, 560.0, 680.0]:
		var sp := _span_at(c, n, half_len)
		var a: Vector2 = sp.get("a", Vector2.ZERO)
		var b: Vector2 = sp.get("b", Vector2.ZERO)
		if not FoldLaw.mirror_valid(a, b, from, to, reach):
			continue
		# 决定性那一条：玩家折过来的对位点必须真的落在 BOSS 面前
		if FoldLaw.mirror(a, b, to).distance_to(from) > FoldLaw.AIM_LANDING + 60.0:
			continue
		return sp
	return {}


func _span_aimed(from: Vector2, to: Vector2) -> Dictionary:
	return _intent_span(from, to, FoldLaw.AIM_ANGLE_JITTER, true)


func _rebuild_nodes() -> void:
	for v in _visuals:
		if is_instance_valid(v):
			(v as Node2D).queue_free()
	_visuals.clear()
	for s in _seams:
		if is_instance_valid(s):
			(s as Node2D).queue_free()
	_seams.clear()
	var host := get_parent()
	if host == null:
		return
	for i in spans.size():
		var sp: Dictionary = spans[i]
		var a := sp.get("a", Vector2.ZERO) as Vector2
		var b := sp.get("b", Vector2.ZERO) as Vector2
		var v: Node2D = VISUAL_SCRIPT.new()
		v.tag = i + 1
		host.add_child(v)
		v.set_span(a, b)
		_visuals.append(v)
		var ends: Array = [a, b]
		for e in ends.size():
			var disc: Node2D = SEAM_SCRIPT.new()
			disc.tag = i + 1
			host.add_child(disc)
			disc.global_position = ends[e] as Vector2
			disc.set_partner(ends[1 - e] as Vector2)
			_seams.append(disc)
	_sync_state()


# ===================== 生成一条能整条躺在场内的痕 =====================

## 以 c 为中心、沿 d 铺一条半长 half_len 的痕；**整条平移**到场内。
## ⚠ 不能逐端点钳：两端各自被墙拽回去，痕的方向就变了 ——
##   二阶段那条「平行痕」会拧成 20~30° 夹角，三个互通区的前提当场不成立。
func _span_at(c: Vector2, d: Vector2, half_len: float) -> Dictionary:
	var hx := maxf(60.0, arena_half.x - arena_margin)
	var hy := maxf(60.0, arena_half.y - arena_margin)
	var lim_x := maxf(0.0, hx - absf(d.x) * half_len)
	var lim_y := maxf(0.0, hy - absf(d.y) * half_len)
	var rel := c - arena_center
	var cc := arena_center + Vector2(clampf(rel.x, -lim_x, lim_x), clampf(rel.y, -lim_y, lim_y))
	return {"a": cc - d * half_len, "b": cc + d * half_len}


func _span_near(at: Vector2) -> Dictionary:
	var hx := maxf(140.0, arena_half.x - arena_margin)
	var hy := maxf(140.0, arena_half.y - arena_margin)
	var th := randf_range(0.0, PI)
	var d := Vector2(cos(th), sin(th))
	var lim := minf(hx / maxf(0.18, absf(d.x)), hy / maxf(0.18, absf(d.y)))
	var half_len := clampf(minf(lim, randf_range(210.0, 430.0)), 170.0, 620.0)
	# 痕中心往玩家那一半偏：痕必须参与这场架，不能甩在角落让人看不懂
	var room_x := maxf(0.0, (hx - absf(d.x) * half_len) * 0.55)
	var room_y := maxf(0.0, (hy - absf(d.y) * half_len) * 0.55)
	var c := arena_center + Vector2(randf_range(-room_x, room_x), randf_range(-room_y, room_y))
	c += (at - c) * randf_range(0.18, 0.5)
	return _span_at(c, d, half_len)


func _parallel_span(base: Dictionary, at: Vector2) -> Dictionary:
	var a := base.get("a", Vector2.ZERO) as Vector2
	var b := base.get("b", Vector2.ZERO) as Vector2
	var d := FoldLaw.crease_dir(a, b)
	var n := Vector2(-d.y, d.x)
	var mid := (a + b) * 0.5
	var reach := maxf(320.0, minf(arena_half.x, arena_half.y) * 0.82)
	var sgn := signf((at - mid).dot(n))
	if sgn == 0.0:
		sgn = 1.0
	var off := clampf(randf_range(0.55, 0.9) * reach, 260.0, reach)
	return _span_at(mid + n * sgn * off, d, a.distance_to(mid) * 0.72)


func _clamp(p: Vector2) -> Vector2:
	if arena_half == Vector2.ZERO:
		return p
	var lim := arena_half - Vector2(arena_margin, arena_margin)
	return arena_center + Vector2(clampf(p.x - arena_center.x, -lim.x, lim.x),
		clampf(p.y - arena_center.y, -lim.y, lim.y))


func global_owner_pos() -> Vector2:
	if anchor_pos != Vector2.ZERO:
		return anchor_pos
	if owner_unit != null and is_instance_valid(owner_unit):
		return owner_unit.global_position
	return Vector2.ZERO


## 战场根节点上找现成的场内痕（召唤叠纸助战时复用敌方那条，不另起一条）
static func find(host: Node) -> FoldField:
	if host == null:
		return null
	for c in host.get_children():
		if c is FoldField and not (c as FoldField).personal:
			return c
	return null


# ===================== 查询（BOSS 与玩家同一口径）=====================

func active() -> bool:
	if _down_left > 0.0 or spans.is_empty():
		return false
	if personal and life_left <= 0.0:
		return false
	return true


## 离 p 最近的那条痕；没有可用痕时返回空字典
func nearest(p: Vector2) -> Dictionary:
	if not active():
		return {}
	var best := {}
	var best_d := FoldLaw.FAR_EPS
	for sp in spans:
		var d := FoldLaw.fold_dist(sp.get("a", Vector2.ZERO) as Vector2,
			sp.get("b", Vector2.ZERO) as Vector2, p)
		if d < best_d:
			best_d = d
			best = sp
	return best


func fold_dist(p: Vector2) -> float:
	var sp := nearest(p)
	if sp.is_empty():
		return FoldLaw.FAR_EPS
	return FoldLaw.fold_dist(sp.get("a", Vector2.ZERO) as Vector2,
		sp.get("b", Vector2.ZERO) as Vector2, p)


## 按指定那条痕折（mirror_hit_span 选出来的痕必须用它自己那条，不能退回最近那条）
static func mirror_across(span: Dictionary, p: Vector2) -> Vector2:
	return FoldLaw.mirror(span.get("a", Vector2.ZERO) as Vector2,
		span.get("b", Vector2.ZERO) as Vector2, p)


## 押痕的正解：把痕立在「让玩家折过来正好落在 BOSS 面前」的位置，且垂直于两者连线。
## ⚠ 不能死取几何中点：中垂线的合法 t 是 `aim_window` 那段区间，
##   d > 2×贴合带时中点 d/2 落在窗口**外面**（垂距 d/2 已经超出 reach），
##   痕压得再正，玩家也不在折过来的那部分纸上 —— 实测 d=742 那一发就是这么落空的。
## ⚠ 也不能"验证没过就退回中点硬写"：`_span_at` 会把整条痕平移回场内，贴边时这一拽
##   能把对位点甩到 188px 开外，而押痕的掌印圆只有 150 —— 写下去就是一发必然落空的出手
##   （2026-11-05 探针抓到：同一份夹具三轮红一轮）。摆不出就返回空，让押痕自己别出。
func _bisect_span(attacker: Vector2, target: Vector2, length: float) -> Dictionary:
	if spans.is_empty():
		return {}
	var d := attacker.distance_to(target)
	if d < 64.0:
		return {}
	# 与意图折同一套构造，只是不给抖动、不取偏置
	var sp := _intent_span(attacker, target, 0.0, false)
	if not sp.is_empty():
		return sp
	var u := (target - attacker) / d
	var win: Array = FoldLaw.aim_window(d, FoldLaw.reach_for(phase))
	var t := d * 0.5
	if not win.is_empty():
		t = clampf(d * 0.5, float(win[0]), float(win[1]))
	var half0 := maxf(length, d * 0.7) * 0.5
	for trim in [1.0, 0.72, 0.5, 0.34]:
		var cand := _span_at(attacker + u * t, Vector2(-u.y, u.x), half0 * trim)
		var a := cand.get("a", Vector2.ZERO) as Vector2
		var b := cand.get("b", Vector2.ZERO) as Vector2
		if not FoldLaw.mirror_valid(a, b, attacker, target, FoldLaw.reach_for(phase)):
			continue
		if FoldLaw.mirror(a, b, target).distance_to(attacker) > FoldLaw.AIM_LANDING:
			continue
		return cand
	return {}


## 起手闸口问的就是这句：押痕现在压不压得出"折过来就在我脚下"。
## 押痕原来只问 `aim_feasible`（纯公式），不看场地边界把痕拽到哪 —— 那 84px 的差就是空放。
func can_bisect(attacker: Vector2, target: Vector2, length: float) -> bool:
	return not _bisect_span(attacker, target, length).is_empty()


func bisect(attacker: Vector2, target: Vector2, length: float) -> bool:
	var sp := _bisect_span(attacker, target, length)
	if sp.is_empty():
		return false
	spans[0] = sp
	## 押痕本身就是一次**主动重折**：把排队中的周期折作废、重新上表。
	## 不清这两样的话，痕刚被压好就被下一跳随机折抹掉，
	## 而且预告还挂着的时候这一式自己那一刀也落空。
	_preview_left = 0.0
	_aim_ready = false
	_refold_left = FoldLaw.refold_for(phase)
	_rebuild_nodes()
	return true


## 找一条「src 这一击能借来折到 tgt」的痕；返回空 = 镜像落点不成立。
## personal 痕只认持有者那一端 —— 别人的攻击借不走你的痕（在 _usable_for 里挡）。
## ⚠ 二阶段场上有两条痕，两条都可能"成立"，必须挑**折过来的落点离出手者最近**的那条，
##   不是数组里第一条。旧口径下押痕刚压好的那条会被另一条平行痕抢走：
##   玩家看到的是"痕明明压在我脚下，掌印却拍到别处"（实测对位点偏 153 px）。
func mirror_hit_span(src_pos: Vector2, tgt_pos: Vector2, reach: float,
		has_mark: bool) -> Dictionary:
	if not active():
		return {}
	var best := {}
	var best_d := 1.0e18
	for sp in spans:
		var a := sp.get("a", Vector2.ZERO) as Vector2
		var b := sp.get("b", Vector2.ZERO) as Vector2
		if not FoldLaw.mirror_valid(a, b, src_pos, tgt_pos, reach, has_mark):
			continue
		var dd := FoldLaw.mirror(a, b, tgt_pos).distance_to(src_pos)
		if dd < best_d:
			best_d = dd
			best = sp
	return best


## personal 痕的归属闸口：只有持有者本人能用它算镜像
func usable_by(src: Node2D) -> bool:
	return not personal or (src != null and is_instance_valid(src) and src == owner_unit)


## 碎痕：全场折痕作废 sec 秒（唯一的免费窗口，不叠加）
func disable_for(sec: float) -> void:
	_down_left = maxf(_down_left, sec)
	_sync_state()


## 跨缝到目标那一头：在所有圆牌里挑「出口离 target 最近」的那一对。
## 只挑离自己最近的那枚会经常把人留在原地 —— 那一式就永远没有出场场景。
func seam_exit_near(target: Vector2) -> Vector2:
	var out := Vector2.INF
	var best_d := 1.0e9
	for s in _seams:
		if not is_instance_valid(s):
			continue
		var disc := s as FoldSeam
		if disc.partner.x < -1.0e18:
			continue
		var dd := disc.partner.distance_to(target)
		if dd < best_d:
			best_d = dd
			out = disc.partner
	return out


## BOSS 的跨缝：找离 from 最近的圆牌，返回它那一头的出口
func seam_exit_for(from: Vector2) -> Vector2:
	var out := Vector2.INF
	var best_d := 1.0e9
	for s in _seams:
		if not is_instance_valid(s):
			continue
		var disc := s as FoldSeam
		var dd := from.distance_to(disc.global_position)
		if dd < best_d:
			best_d = dd
			out = disc.partner
	return out


func is_previewing() -> bool:
	return _preview_left > 0.0


# ===================== 每帧 =====================

func _process(delta: float) -> void:
	if personal and life_left > 0.0:
		life_left -= delta
		if life_left <= 0.0:
			dismiss()
			return
	if _down_left > 0.0:
		_down_left = maxf(0.0, _down_left - delta)
	for k in _re_cd.keys():
		_re_cd[k] = maxf(0.0, float(_re_cd[k]) - delta)
	for k in _exit_guard.keys():
		_exit_guard[k] = maxf(0.0, float(_exit_guard[k]) - delta)
	if not personal:
		_tick_refold(delta)
	_tick_travel()
	for v in _visuals:
		if is_instance_valid(v):
			(v as FoldVisual).fade(delta, 6.0)


## 换痕节奏：到点先亮 1.2 秒压痕预告，预告走完才真的换。
## ⚠ 旧版在这里走进死循环：`_refold_left` 只在 `elif _refold_left <= 0.0` 那一支重新上表，
##   可第一支的条件是 `<= PREVIEW_TIME` —— 0 也算满足，于是每次折完下一帧立刻又点亮预告，
##   痕每 1.2 秒跳一次（用户看到的「叠痕总是乱放」），而 `is_previewing()` 常驻为真
##   让 `_fold_image_of()` 永远返回 INF —— 镜像那一面从此再也打不到人（实测 0 次）。
##   修法：折完那一刻就重新上表，第一支不再有机会连排。
func _tick_refold(delta: float) -> void:
	if _preview_left > 0.0:
		_preview_left -= delta
		if _preview_left <= 0.0:
			_preview_left = 0.0
			# 有锁好的意图就意图折，没有（距离太远 / BOSS 没给）才退回随机折
			if _aim_ready:
				rebuild_aimed()
			else:
				rebuild_near(global_owner_pos())
			_aim_ready = false
			_refold_left = FoldLaw.refold_for(phase)
		return
	_refold_left -= delta
	if _refold_left <= FoldLaw.PREVIEW_TIME:
		_preview_left = FoldLaw.PREVIEW_TIME
		_sync_state()


func _sync_state() -> void:
	var preview := _preview_left > 0.0
	for i in _visuals.size():
		if i >= spans.size() or not is_instance_valid(_visuals[i]):
			continue
		var v := _visuals[i] as FoldVisual
		var sp: Dictionary = spans[i]
		v.set_span(sp.get("a", Vector2.ZERO) as Vector2, sp.get("b", Vector2.ZERO) as Vector2)
		v.set_preview(preview)
		v.set_dimmed(_down_left > 0.0)
	for s in _seams:
		if is_instance_valid(s):
			(s as CanvasItem).visible = _down_left <= 0.0


## 穿缝结算：只有「单位」走这块（投射物的对侧落点由各功法的双落点交付）
func _tick_travel() -> void:
	if not active() or personal:
		return
	for raw in get_tree().get_nodes_in_group("player"):
		_try_travel(raw)
	for raw in get_tree().get_nodes_in_group("ally_summon"):
		_try_travel(raw)


func _try_travel(raw: Variant) -> void:
	if raw == null or not (raw is Node2D) or not is_instance_valid(raw):
		return
	var u := raw as Node2D
	var id := u.get_instance_id()
	if _exit_guard.has(id) or _re_cd.has(id):
		return
	if u.has_method("is_dead") and bool(u.call("is_dead")):
		return
	for s in _seams:
		if not is_instance_valid(s):
			continue
		var disc := s as FoldSeam
		if disc.partner.x < -1.0e18:
			continue
		if u.global_position.distance_to(disc.global_position) > FoldLaw.SEAM_R:
			continue
		u.global_position = disc.partner
		## 通知被送出来的人：被动「量折」吃这一次穿缝（没有该方法的单位自动忽略）
		if u.has_method("on_fold_crossed"):
			u.call("on_fold_crossed")
		_re_cd[id] = FoldLaw.SEAM_CD
		_exit_guard[id] = FoldLaw.SEAM_EXIT_GUARD
		SkillFx.play_fold_cross(get_tree().root, disc.global_position, disc.partner, disc.tag)
		return


func dismiss() -> void:
	_sync_state()
	for v in _visuals:
		if is_instance_valid(v):
			(v as FoldVisual).set_dimmed(true)
	for s in _seams:
		if is_instance_valid(s):
			(s as Node2D).queue_free()
	_seams.clear()
	spans = []
	_visuals.clear()
	queue_free()
