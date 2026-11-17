class_name DomainBoss04C
extends BossBase
## 照影界第 3 位 · 叠纸 —— 空间连通 · 折影为径（2026-11-02）
##
## 战场是一张纸。地上那条**折痕**把相距很远的两块纸面贴在一起，
## 所以它每一击都同时判定两处：本体位置 与 目标关于折痕的对位落点。
## 镜像那一半只在「目标与它分处痕的两侧、且目标到痕的垂直距离 ≤ 贴合带」时成立 ——
## ⇒ 离折痕比贴合带更远，就绝对打不到你。**这是空手也能用的解法，不需要任何叠纸功法。**
##
## 二阶段专属机制层「折两次」：落第二条**平行**痕，场被切成三个互通区；
## 它由此拿到三区落点的终局招「三重落纸」，同时贴合带收窄（300 → 260），
## 强度不白送 —— 规则要自洽：纸叠了两层，能贴住的范围反而更小。
##
## 没有势条 / 资源条 / 叠层引爆。读数只有三个可见量：痕在哪、离痕多远、圆牌在哪。
## 弱点与反逃课成对：站远 → 押痕把痕压到你与我正中间 / 碎痕沿痕炸直线；
## 贴脸 → 循痕顺痕滑开；蹲点不动 → 碎痕；碎痕之后 4 秒全场没有镜像，是唯一的免费窗口。

const F_PRESS := "form_fold_press"
const F_TRACE := "form_fold_trace"
const F_STRIDE := "form_fold_stride"
const F_PRESSMARK := "form_fold_pressmark"
const F_SHROUD := "form_fold_shroud"
const F_TEAR := "form_fold_tear"
const F_TWIN := "form_fold_twin"
const F_TRIPLE := "form_fold_triple"

const FIELD_SCRIPT := preload("res://scripts/combat/fold_field.gd")

## 弹反物理招 → 纸面折回来割它自己（按这一招系数 × 0.85 反噬，走真伤）
const PARRY_REFLECT_RATIO := 0.85
## 玩家原地站到这么久 → 判定为「蹲点」，出碎痕
const STILL_TIME := 2.2
## 押痕时痕的长度：要能横在两者中间
const PRESSMARK_LEN := 360.0
## 跨缝的落点必须离人这么近才允许出招（不许空放）
const STRIDE_LAND := 190.0
## 双屏要求玩家站在这条痕的「炮台射程」内
const TWIN_BAND := 220.0
## 受击计数：挨打够密就抬护身纸
## 主动重折的节奏上限：最快这么久请求一次，避免痕变成"常驻跳动"。
## 3.2 秒是按「玩家绕一圈的速度」定的：250px/s 绕 300 半径转，3.2 秒走过约 800px 弧、
## 方向变化 26° —— 再慢痕就对不上新方向，再快就成了每帧跳。
const REFOLD_REQUEST := 3.2
const SHROUD_HITS := 5
## 追对位落点：离得太远就不追了（那是痕该重折，不是靠走位能补的）
const IMAGE_FOLLOW_MAX := 620.0
const SHROUD_WINDOW := 2.6
## 血线节点：过一次触发一次叠掩
const HP_NODES: Array = [0.75, 0.35]

var _phase_two: bool = false
var _field: Node2D = null
var _cools: Dictionary = {}
var _recent: Array = []
var _decide_wait: float = 0.0
var _current_skill: String = ""
var _shroud_left: float = 0.0
var _shroud_guard_used: bool = false
var _hits: Array = []                 ## 最近受击的时间戳（秒）
var _nodes_done: Array = []
var _still_left: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO
var _triple_plan: Array = []
var _triple_left: float = 0.0
var _triple_dmg: float = 0.0
var _hit_once: Dictionary = {}        ## 本次施法已结算过的单位 id（一次招每人最多吃一下）
var _field_pending: bool = false
var _gate_blocked: int = 0     ## 起手前被几何闸拦下的次数（探针读它）
var _was_previewing: bool = false      ## 上一帧压痕预告是否亮着（用来抓"开始预告"那一帧锁意图）
var _refold_ask: float = 0.0           ## 主动重折的节奏上限计时
var _direct_landings: int = 0  ## 结算在实体位置上的次数
var _fold_landings: int = 0    ## 只能靠镜像落点才结算到的次数（站远时必须是 0）
var _fold_windows: int = 0     ## 结算时镜像面**可用**的次数（站远时必须为 0，站痕里时必须 >0）
var _begin_snapshot: Dictionary = {}


func _setup() -> void:
	boss_id = "boss_04_c"
	_phase_two = false
	_cools.clear()
	_recent.clear()
	_decide_wait = 0.0
	_current_skill = ""
	_shroud_left = 0.0
	_shroud_guard_used = false
	_hits.clear()
	_nodes_done.clear()
	_still_left = 0.0
	_triple_plan = []
	_triple_left = 0.0
	_hit_once.clear()
	_last_pos = global_position
	_gate_blocked = 0
	_direct_landings = 0
	_fold_landings = 0
	_fold_windows = 0
	_begin_snapshot = {}
	_field_pending = true


# ===================== 折痕场 =====================

## 同场只有一条场内痕（召唤叠纸助战时复用敌方那条），没有就自己立一条
func _ensure_field() -> void:
	if _field != null and is_instance_valid(_field):
		return
	var host := get_parent()
	if host == null:
		return
	var found: Node = FIELD_SCRIPT.find(host)
	if found != null:
		_field = found
		return
	_field = FIELD_SCRIPT.new()
	_field.name = "FoldField"
	host.add_child(_field)
	_field.owner_unit = self
	_field.open_arena(arena_center, arena_half_extents, arena_margin, _anchor_pos())
	## 开场那条痕就得参与这场架：先按意图折一次（折不动时 rebuild_aimed 自己退回随机折）。
	## 旧版开场只有一条随机痕，玩家绕 300~400 就是绝对安全，前 15 秒机制完全不参与。
	_field.set_aim(global_position, _lead_pos(_focus(), FoldLaw.PREVIEW_TIME))
	_field.rebuild_aimed()


func _anchor_pos() -> Vector2:
	var p := _focus()
	if p != null:
		return p.global_position
	return global_position


func _physics_process(delta: float) -> void:
	if state == BossState.DEAD:
		return
	if _field_pending:
		_field_pending = false
		_ensure_field()
	super._physics_process(delta)
	if _field != null and is_instance_valid(_field):
		_anchor_player_for_field()
		_keep_fold_aimed(delta)
	_stance_on_fold()
	_track_stillness(delta)
	_tick_triple(delta)


## 场地维护：痕现在帮不到我，就主动要求重折一次（仍走 1.2 秒预告，玩家看得见前置信息）。
## ⚠ 必须放在 _physics_process 而不是 _choose：选招只在 IDLE/CHASE 里跑，
##   而实测 40 秒里 BOSS 有约 34 秒处在起手/判定/收招中 —— 放在选招里它几乎没机会执行，
##   痕一旦失效就一直失效到下一次 15 秒周期折。
## ⚠ 也不能无脑重折：那会退化成"预告常驻、痕每 1.2 秒跳一次"（就是用户说的乱放）。
##   所以加了 REFOLD_REQUEST 的节奏上限，并且要求痕确实帮不到人。
func _keep_fold_aimed(delta: float) -> void:
	if _refold_ask > 0.0:
		_refold_ask = maxf(0.0, _refold_ask - delta)
		return
	var p := _focus()
	if p == null or _field == null or not is_instance_valid(_field):
		return
	var d := global_position.distance_to(p.global_position)
	if d <= _press_range() + FoldLaw.HIT_MARGIN:
		return                 # 本体扇形就够到，不需要放大器
	if _fold_covers_press(p):
		return                 # 痕正在帮忙
	if not FoldLaw.aim_feasible(d, _reach()):
		return                 # 折不动：这一档交给碎痕 / 追击
	if _field.request_refold():
		_refold_ask = REFOLD_REQUEST


## 压痕预告开始的**那一帧**把这一折的意图交给折痕场，之后 1.2 秒不再更新。
## ⚠ 旧版在这里每帧写 `anchor_pos = 玩家位置`：痕永远折向玩家"现在"站的地方，
##   预告就成了纯装饰，玩家没有任何可执行的躲避动作。
##   锁在预告开始那一刻，「看见痕开始压 → 走出中垂线窗口」才真的能拆掉这一折。
func _anchor_player_for_field() -> void:
	var p := _focus()
	if p == null:
		return
	_field.anchor_pos = p.global_position
	## ⚠ `_field` 是无类型字段（同场复用别人那条痕时它是 Node），
	##   `:=` 推不出 is_previewing() 的返回类型会直接 parse error
	var pre: bool = _field.is_previewing()
	if pre and not _was_previewing:
		## 提前量 = 预告时长 + 一次按纸的前摇：痕落下时人大概正好走到那儿
		## 风格选择：镜像面此刻已经盖得到人 → 维持横折（别把刚建好的射程自己拆了）；
		##   盖不到、而循痕正好转好 → 这一折改顺折，给那一式铺出一条真的能滑过去的线。
		## 不加随机、由循痕自己的 CD 节流：循痕一出手 CD 就转起来，下一折自动回到横折，
		## 所以顺折只在"循痕等着上场"时出现，不会和按纸抢射程（实测加 34% 概率时
		## 三段模拟里有一整段一次顺折都没抽到，等于那一式从招式表里消失）。
		var along := not _fold_covers_press(p) and _ready_cd(F_TRACE)
		_field.set_aim(global_position,
			_lead_pos(p, FoldLaw.PREVIEW_TIME + _lead_time(F_PRESS)), along)
	_was_previewing = pre


## 玩家原地不动的计时 —— 碎痕的出场条件（蹲点必须有代价）
func _track_stillness(delta: float) -> void:
	var p := _focus()
	if p == null:
		_still_left = 0.0
		return
	var moved := p.global_position.distance_to(_last_pos)
	_last_pos = p.global_position
	if moved < 1.6:
		_still_left += delta
	else:
		_still_left = maxf(0.0, _still_left - delta * 2.0)


func _reach() -> float:
	return FoldLaw.reach_for(phase)


## 按纸扇形的本体半径（选招与闸口都要用它判断"不用放大器够不够"）
func _press_range() -> float:
	return float(MoveDB.resolve_boss(F_PRESS).get("range", 178.0))


## 押痕此刻压不压得出"折过来就在我脚下"：与 FoldField 真正执行的那一句同一个函数。
## 痕长读表，不在这里抄一遍（抄了就出现"闸口按 360 判、落帧按 520 摆"这种两套口径）。
func _pressmark_lays(p: Node2D) -> bool:
	if not _field_valid() or p == null or not is_instance_valid(p):
		return false
	var b := MoveDB.resolve_boss(F_PRESSMARK)
	return bool(_field.can_bisect(global_position, p.global_position,
		float(b.get("pressmark_length", PRESSMARK_LEN))))


## 预判落点：痕要折向玩家**将要踩到**的那块纸，不是她按下选招那一瞬的位置。
## ⚠ 这是镜像面从"能成立"变成"打得到"的关键一环：折痕是按当下位置摆的，
##   而命中落在前摇之后（按纸 0.7 秒、押痕自己那一刀也在 windup 之后），
##   玩家以 250px/s 直线走位就走出 175px —— 比 AIM_LANDING 的容差还大，
##   于是实测镜像面 28% 的时间"成立"、40 秒里却只落到 1 次。
##   提前量按秒给，最大只外推 LEAD_MAX px：会突然变向的玩家照样能骗过这一折。
const LEAD_MAX := 190.0


func _lead_pos(p: Node2D, sec: float) -> Vector2:
	if p == null or not is_instance_valid(p):
		return global_position
	var v: Vector2 = p.velocity if p.get("velocity") is Vector2 else Vector2.ZERO
	var off := v * sec
	if off.length() > LEAD_MAX:
		off = off.normalized() * LEAD_MAX
	return _clamp_point(p.global_position + off)


## 某一式从起手到命中之间要等多久（预判提前量就按这个算）
func _lead_time(sid: String) -> float:
	return maxf(0.2, float(MoveDB.resolve_boss(sid).get("windup", 0.7))) \
			* (float(MoveDB.resolve_boss(sid).get("windup_mult_p2", 1.0)) if phase >= 2 else 1.0)


## 目标借哪条痕折到我这一侧来；不成立时返回 Vector2.INF
func _fold_image_of(u: Node2D) -> Vector2:
	if u == null or not is_instance_valid(u):
		return Vector2.INF
	return _fold_image_at(u.global_position, _unit_marked(u))


## 同上，但落点位置由调用方给（预判就用这个）
func _fold_image_at(tgt_pos: Vector2, has_mark: bool) -> Vector2:
	var pair := _fold_pair_for(tgt_pos, has_mark)
	return pair[1] if pair.size() == 2 else Vector2.INF


## 目标此刻借哪条痕折过来：返回 [痕, 对位落点]；没有可用折面时返回空数组。
## 拆开给两处用 —— 命中层只要落点，走位层还要那条痕（判断"我这一步会不会穿过去"）。
func _fold_pair_for(tgt_pos: Vector2, has_mark: bool) -> Array:
	if _field == null or not is_instance_valid(_field):
		return []
	## ⚠ 压痕预告期间**照旧用当前这条痕**打人。旧版在这里直接判空，
	##   等于每折一次自己把放大器没收 1.2 秒 —— 实测 40 秒里 23% 的时间因此没有镜像，
	##   而设定写得明白：碎痕之后折痕作废 4 秒是「全场唯一的免费窗口」。
	##   预告的意思是「这条痕要被换掉了」，不是「这条痕此刻不存在」；
	##   玩家该读的是当前这条痕的贴合带，看见压痕就走出去，而不是躲进一个几何上还在的折面。
	var sp: Dictionary = _field.mirror_hit_span(global_position, tgt_pos,
		_reach(), has_mark)
	if sp.is_empty():
		return []
	return [sp, FoldField.mirror_across(sp, tgt_pos)]


func _unit_marked(u: Node2D) -> bool:
	if u == null or not is_instance_valid(u) or not u.has_method("has_debuff"):
		return false
	return bool(u.call("has_debuff", "fold_mark"))


## 玩家侧查这条：叠掩期间它没有被折过来的那一面（镜像借不走）
func mirror_shielded() -> bool:
	return _shroud_left > 0.0


# ===================== 计时与受伤 =====================

func _tick_cooldowns(delta: float) -> void:
	for sid in _cools.keys():
		if float(_cools[sid]) > 0.0:
			_cools[sid] = maxf(0.0, float(_cools[sid]) - delta)
	if _decide_wait > 0.0:
		_decide_wait = maxf(0.0, _decide_wait - delta)
	if _shroud_left > 0.0:
		_shroud_left = maxf(0.0, _shroud_left - delta)
		if _shroud_left <= 0.0:
			_shroud_guard_used = false


func after_damage_taken(_amount: float) -> void:
	var now := float(Time.get_ticks_msec()) / 1000.0
	_hits.append(now)
	while not _hits.is_empty() and now - float(_hits[0]) > SHROUD_WINDOW:
		_hits.pop_front()
	if _shroud_left > 0.0:
		_shroud_guard_used = true


## 护身纸：首次受击 −60%（一次性，扣完等下次叠掩）
func damage_taken_multiplier(_damage_kind: String) -> float:
	if _shroud_left > 0.0 and not _shroud_guard_used:
		return 1.0 - float(MoveDB.resolve_boss(F_SHROUD).get("shroud_guard", 0.6))
	return 1.0


## 弹反物理招 → 纸面折回来割它自己
## ⚠ 这一记的目标是**自己**，不是 `source`。图鉴文案（codex_db 叠纸卡）写的就是
##   「弹反成功，纸面折回来割它自己」，而原来这行写成 `deal_damage_to(source, …)`：
##   玩家弹掉了按纸（那一下已被免伤窗口抵消），紧接着又被这记"折返"打上 85% 伤害
##   —— 等于弹反成功反而挨第二刀，实测 223 → 弹后仍掉 176（2026-11-05 用户报）。
##   弹反是这套机制给玩家的正解，绝不能把它做成惩罚。
func on_parried(source: Node) -> void:
	super.on_parried(source)
	var b := MoveDB.resolve_boss(_current_skill)
	if b.is_empty():
		return
	if String(b.get("attack_kind", "")) != "physical_melee":
		return
	var dmg := MoveDB.boss_damage(_current_skill, attack_power, phase) * PARRY_REFLECT_RATIO
	deal_damage_to(self, dmg, "physical", "water")
	show_windup_line("纸面折返", 0.55, 17, 210.0, Color(0.92, 0.90, 0.80), -184.0)


# ===================== 选招 =====================

## 站位跟着「玩家被折过来的那一头」走 —— 这才是这套机制的射程逻辑：
## 痕把两块纸贴在一起，按纸打在折过来的那面上，人绕到哪儿都还在它刀口里。
## ⚠ 必须放在 _physics_process、而且放在 super 之后：
##   ① 通用 _chase_target 只在 CHASE 里跑，而实测 40 秒里 BOSS 绝大多数时间在
##      待机/起手/收招（条件招一合格就出，压根进不到 CHASE）—— 挂在追击里等于不执行；
##   ② super 已经按"朝玩家本人挤"设过一遍 velocity，这里覆盖掉才有意义。
## 走法本身不会把痕穿掉：对位点按定义在痕的**我这一侧**，朝它走只会越来越靠近那一面。
func _stance_on_fold() -> void:
	if state != BossState.IDLE and state != BossState.CHASE:
		return
	if is_skill_locked():
		return        ## 开场/过场锁招期间站住 —— 这条是通用契约，走位层也该遵守
	var p := _focus()
	if p == null:
		return
	var player_dir: Vector2 = (p.global_position - global_position).normalized()
	if _fold_covers_press(p) or _direct_covers_press(p):
		## 本体扇形或镜像面已经够得到就站住。
		## ⚠ 只判镜像会出这种事：玩家贴到脸上（本体明明一刀一个），
		##   它却为了去追一个更远的对位落点转身走开 —— 实测探针里玩家摆 110 px 就复现。
		velocity = Vector2.ZERO
		_set_facing(player_dir)
		return
	var pair := _fold_pair_for(_lead_pos(p, _lead_time(F_PRESS)), _unit_marked(p))
	if pair.size() != 2:
		return                         ## 没有可借的折面：交回通用走位
	var img: Vector2 = _clamp_point(pair[1] as Vector2)
	var to_img: Vector2 = img - global_position
	var dist := to_img.length()
	if dist > IMAGE_FOLLOW_MAX:
		return                         ## 太远：那是痕该重折，不靠腿补
	if dist > 1.0 and player_dir.dot(to_img / dist) < cos(deg_to_rad(_press_angle() * 0.5)):
		return                         ## 落点在扇面角度之外：同上，不许绕到背后去打
	velocity = to_img / maxf(dist, 1.0) * _move_speed()
	_set_facing(player_dir)


## 按纸扇形的张角（走位与选招共用同一份口径）
func _press_angle() -> float:
	return float(MoveDB.resolve_boss(F_PRESS).get("angle", 104.0))


func _on_chase_reached(_dist: float) -> void:
	_choose()


## 每一式的出场条件都写成「这一招现在打得到人」，不许空放：
## · 按纸    = 扇形盖到人 或 人的对位落点盖在扇形里
## · 循痕    = 沿痕滑过去的走廊盖到人
## · 跨缝    = 圆牌另一头出口离人 ≤ 150
## · 押痕    = 人确实在贴合带外，且两者距离 ≤ 2×贴合带（否则痕压到中间也折不到）
## · 双屏    = 人在痕的 ±220 带内（圆牌才射得到）
## · 碎痕    = 直接沿痕炸，不依赖镜像；但撕完自己 4 秒没镜像，所以只在「本来就没镜像可用」或「人蹲住」时出
## · 三重落纸 = 二阶段限定，三区至少有一区盖得住人
## 镜像那一面此刻是不是**真的盖得到人**。
## ⚠ 这是本次修改的核心一条：旧版闸口只判 `mirror_valid`（异侧 + 在贴合带内）就当镜像可用，
##   可命中层测的是「玩家的对位点落不落进扇形」—— 闸口比几何宽，
##   于是大量出手在选招与起手两道都"合格"、落帧却必然打不到人（实测押痕放到 720，
##   而真实可行上限只有 636；三段 40 秒里镜像落点 0 次）。
##   起手时人会转向目标，所以轴向按目标方向复算，和 _hit_fan 落帧时同一份口径。
func _fold_covers_press(p: Node2D) -> bool:
	if p == null or not is_instance_valid(p):
		return false
	# 预判到命中那一帧：痕是提前摆好的，判定也必须按届时玩家会在的位置算
	var lead := _lead_pos(p, _lead_time(F_PRESS))
	var img := _fold_image_at(lead, _unit_marked(p))
	if img == Vector2.INF:
		return false
	return _press_fan_covers(img, lead)


## 本体扇形直接盖不盖得住（不借痕）。和"借痕盖得住"分开算，
## 才知道这一刀到底是"射程本来就够了"还是"全靠折痕接上来的"。
func _direct_covers_press(p: Node2D) -> bool:
	if p == null or not is_instance_valid(p):
		return false
	var lead := _lead_pos(p, _lead_time(F_PRESS))
	return _press_fan_covers(lead, lead)


## 按纸的扇形盖不盖得住 at 这个点；axis 用「起手时会转向的那个方向」，
## 所以 ref 必须是命中那一刻玩家（或其对位点）所在的位置。
func _press_fan_covers(at: Vector2, ref_pos: Vector2) -> bool:
	var gap := ref_pos - global_position
	var axis := gap.normalized() if gap.length_squared() > 1.0 else facing.normalized()
	return _in_fan(at, global_position, axis, _press_range(),
			cos(deg_to_rad(_press_angle() * 0.5)))


func _choose() -> void:
	if state != BossState.IDLE and state != BossState.CHASE:
		return
	if _decide_wait > 0.0:
		return
	_decide_wait = 0.26
	var p := _focus()
	if p == null:
		return
	var d := global_position.distance_to(p.global_position)
	var fd := FoldLaw.FAR_EPS
	if _field_valid():
		fd = float(_field.call(&"fold_dist", p.global_position))
	## 镜像成不成立只看一件事：能不能取到人的对位落点（异侧 + 在贴合带内 + 痕没作废）
	## 而「这一折有没有威胁」要多问一层：对位点是不是真在按纸的扇形里 —— 用后者驱动选招，
	## 痕才真的参与进攻，而不是画得漂亮却永远落空。
	var fold_ready := _fold_covers_press(p)
	var direct_ready := _direct_covers_press(p)
	## 「够不着」= 本体扇形和镜像面都盖不住。旧版只比镜像一面，
	## 结果是贴脸时也算"够不着"，押痕/碎痕白占出手位（实测 d=77 还去压痕）。
	var far := not (fold_ready or direct_ready)

	## 折痕把这一刀接得到的那一刻，先兑现它。
	## 只有在「本体够不着、而镜像面够得着」时插队：这正是这套机制的 payoff 瞬间。
	## 不插队的话条件招（押痕/双屏/跨缝）会把这段窗口整个吃掉 —— 实测按纸 40 秒只出 0~3 次，
	## BOSS 明明已经把射程接到玩家脚下了，却转身去用别的招打空。
	## （顺折那一边不用在这里操心：镜像面在顺折下必然不成立，这一插队自己就不会触发，
	##   而评分池里按纸判"用不了"、循痕判"盖得住"，那一式自然接手。）
	if fold_ready and not direct_ready and _ready_cd(F_PRESS):
		_begin(F_PRESS)
		return

	# —— 条件招（优先级从高到低，每条都是「别的招此刻打不到人」的补位）——
	if phase >= 2 and _ready_cd(F_TRIPLE) and _triple_covers(p):
		_begin(F_TRIPLE)
		return
	## 押痕 = 主动造几何：痕现在帮不到我，我就把它压到能帮到我的位置上，下一招折到你脚下。
	## 窗口用 aim_feasible（和 FoldField 意图折同一份算法），不再放一个必然落空的距离档。
	## ⚠ 还要加一条「本体扇形也盖不到」：贴脸时按纸直接就能打，
	##   旧版押痕却在 d=77 这种距离上白白消耗掉一次重折。
	## ⚠ 顺折（痕顺着连线铺）期间要让给循痕：押痕只问"折得动折不动"、不看痕是怎么摆的，
	##   它一出手就把刚铺好的顺折改回横折 —— 实测三段模拟里循痕整场零出场，
	##   等于从招式表里抹掉一门（用户定：每一式都得有出场场景）。
	if _ready_cd(F_PRESSMARK) and far and d > _press_range() + FoldLaw.HIT_MARGIN \
			and _pressmark_lays(p) \
			and not (_ready_cd(F_TRACE) and _trace_covers(p)):
		_begin(F_PRESSMARK)
		return
	## 碎痕不再当"痕帮不到我"的补位：它自己会把痕摊平 4 秒，
	## 于是 far → 撕 → 更 far → 再撕，实测 40 秒里 26% 的时间场地是废的，
	## 而这套设计的射程全靠那条痕。现在它只回答两件事：
	##   ① 玩家蹲住不动（蹲点必须有代价）
	##   ② 玩家骑在贴合带里、而痕已经没救了（距离远到折不动）
	if _ready_cd(F_TEAR) and d <= 620.0 \
			and (_still_left >= STILL_TIME
					or (far and not FoldLaw.aim_feasible(d, _reach()))):
		_begin(F_TEAR)
		return
	if _ready_cd(F_SHROUD) and (_hits.size() >= SHROUD_HITS or _node_crossed(p)):
		_begin(F_SHROUD)
		return
	## 中距这一格两招都能出：双屏排在跨缝前面。
	## 跨缝的落点改成「挑出口离人最近的那一对」之后几乎永远满足，
	## 让它先判就会把双屏的出场空间整段吃掉 —— 每一式都得有场景是硬约束。
	if _ready_cd(F_TWIN) and fd <= TWIN_BAND and d >= 200.0 and d <= 480.0:
		_begin(F_TWIN)
		return
	if _ready_cd(F_STRIDE) and d >= 170.0 and _stride_landing(p).distance_to(p.global_position) \
			<= STRIDE_LAND:
		_begin(F_STRIDE)
		return

	# —— 评分招 ——
	var pool: Array = [F_PRESS, F_TRACE]
	var best := ""
	var best_score := -999.0
	for sid in pool:
		if not _ready_cd(String(sid)) or not _usable(String(sid), p, d, fold_ready):
			continue
		var sc := _score(String(sid), d, fd, fold_ready) + randf() * 0.9 - _repeat_penalty(String(sid))
		if sc > best_score:
			best_score = sc
			best = String(sid)
	if best == "":
		state = BossState.CHASE
		return
	_begin(best)


func _field_valid() -> bool:
	return _field != null and is_instance_valid(_field)


func _ready_cd(sid: String) -> bool:
	return float(_cools.get(sid, 0.0)) <= 0.0


func _usable(sid: String, p: Node2D, _d: float, fold_ready: bool) -> bool:
	match sid:
		F_PRESS:
			## 本体扇形真的盖得住（角度也算，不再用"d≤196"这种近似），
			## 或者折痕把落点接进扇形 —— 两条都不成立就不许出这一式。
			return _direct_covers_press(p) or fold_ready
		F_TRACE:
			## 只认几何：沿痕滑过去的走廊必须真盖得住人。贴脸的补位交给按纸，
			## 不许用「距离近 + 有镜像」放行 —— 那等于允许它顺一条没人站着的痕空滑。
			return _trace_covers(p)
	return false


func _score(sid: String, d: float, fd: float, fold_ready: bool) -> float:
	match sid:
		F_PRESS:
			## 扇形直接盖住最愿意用；盖不住但镜像面真能盖到人 —— 也给足分。
			## 旧版给镜像掉到一半热度（1.4 + 0.5），结果是它宁可空转也不肯用放大器，
			## 而「60% 伤打得到」永远好过「100% 伤打不到」。
			if d <= _press_range():
				return 3.2 - absf(d - 120.0) / 190.0 + (0.4 if fold_ready else 0.0)
			return 2.6 if fold_ready else 0.0
		F_TRACE:
			## 人贴脸又站在痕上 → 顺痕滑开顺便割，这一档最优先
			return 2.6 - absf(fd - 90.0) / 260.0 - absf(d - 210.0) / 420.0
	return 0.4


func _repeat_penalty(sid: String) -> float:
	if _recent.size() >= 2 and String(_recent[0]) == sid and String(_recent[1]) == sid:
		return 99.0
	if not _recent.is_empty() and String(_recent[0]) == sid:
		return 2.2
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


func _node_crossed(_p: Node2D) -> bool:
	if _shroud_left > 0.0 or max_hp <= 0.0:
		return false
	for n in HP_NODES:
		if float(current_hp) / max_hp <= float(n) and not _nodes_done.has(n):
			_nodes_done.append(n)
			return true
	return false


# ===================== 起手 / 释放 =====================

## 起手前的最后一道几何闸：选招到起手之间人会走位，这里按**起手那一帧**再判一次。
## 收不到人就直接改回追击 —— 「不许空放」必须写在释放路径上，只写在选招里挡不住这一帧的偏差。
## 判定结果留在 _begin_snapshot 里给探针读，探针不必自己复算（复算必然差一帧）。
func _cast_covers(sid: String, p: Node2D) -> bool:
	var b := MoveDB.resolve_boss(sid)
	var d := global_position.distance_to(p.global_position)
	var pp := p.global_position
	match sid:
		F_PRESS:
			## 与选招同一份口径（本体扇形含角度 / 或折痕把落点接进来）：
			## 两道闸用不同算法，就会出现"选招放行、起手被拦"或反过来，
			## 前者白转一次 CD，后者玩家看得见起手却没人挨打。
			return _direct_covers_press(p) or _fold_covers_press(p)
		F_TRACE:
			return _trace_covers(p)
		F_STRIDE:
			var ex := _stride_landing(p)
			return ex != Vector2.INF and ex.distance_to(pp) <= STRIDE_LAND
		F_PRESSMARK:
			## 痕压到两者正中之后，折过来的落点就在它自己脚下：闸口直接问 FoldField
			## "这一折现在摆不摆得出来"，和 `_cast_pressmark` 里真正执行的是同一个函数。
			## 旧版在这里用纯公式 `aim_feasible(d)`（上限 636/786），不看场地边界把痕拽到哪，
			## 于是贴边那一圈照样放行一发对位点偏 188 的空掌印（探针三轮红一轮抓到）。
			return _pressmark_lays(p)
		F_SHROUD:
			return true
		F_TEAR:
			return d <= float(b.get("range", 560.0)) + float(b.get("width", 220.0))
		F_TWIN:
			return _field.fold_dist(pp) <= TWIN_BAND + FoldLaw.HIT_MARGIN
		F_TRIPLE:
			return _triple_covers(p)
	return true


func _begin(sid: String) -> void:
	if is_skill_locked():
		return
	var probe := _focus()
	if probe != null and not _cast_covers(sid, probe):
		_gate_blocked += 1
		state = BossState.CHASE
		return
	if probe != null:
		_begin_snapshot = {"form": sid,
			"cover": true,
			"fd": float(_field.fold_dist(probe.global_position)) if _field_valid() else FoldLaw.FAR_EPS,
			"d": global_position.distance_to(probe.global_position)}
	_current_skill = sid
	_hit_once.clear()
	## 起手就把步子收住：这一式的判定按"起手那一刻的几何"算（选招刚验过落点），
	## 前摇里还带着走位速度会滑出几十像素，落点就从扇形里漂出去了。
	velocity = Vector2.ZERO
	state = BossState.WINDUP
	var b := MoveDB.resolve_boss(sid)
	var windup := maxf(0.2, float(b.get("windup", 0.7)))
	if phase >= 2:
		windup *= float(b.get("windup_mult_p2", 1.0))
	state_timer = windup
	var focus := _focus()
	if focus != null:
		_set_facing((focus.global_position - global_position).normalized())
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
		F_PRESS: _cast_press(b)
		F_TRACE: _cast_trace(b)
		F_STRIDE: _cast_stride(b)
		F_PRESSMARK: _cast_pressmark(b)
		F_SHROUD: _cast_shroud(b)
		F_TEAR: _cast_tear(b)
		F_TWIN: _cast_twin(b)
		F_TRIPLE: _cast_triple(b)
		_: _finish_skill()


func _finish_skill() -> void:
	_record(_current_skill)
	_current_skill = ""
	## 三重落纸的三段还在往下掉：那一串共用一份「已结算」表，人不能挨三下
	if _triple_plan.is_empty():
		_hit_once.clear()
	state = BossState.RECOVER
	state_timer = 0.45


func _focus() -> Node2D:
	if target != null and is_instance_valid(target) and not BossBase.is_unit_dead(target):
		return target
	var p := focus_node()
	if p != null and is_instance_valid(p) and not BossBase.is_unit_dead(p):
		return p
	return null


# ===================== 命中层：本体 或 对位落点，一次招每人最多吃一下 =====================

func _in_fan(at: Vector2, origin: Vector2, dir: Vector2, reach: float, cos_half: float) -> bool:
	var to := at - origin
	var dd := to.length()
	if dd > reach + FoldLaw.HIT_MARGIN:
		return false
	if dd > 1.0 and dir.dot(to / dd) < cos_half:
		return false
	return true


func _in_circle(at: Vector2, center: Vector2, radius: float) -> bool:
	return at.distance_to(center) <= radius + FoldLaw.HIT_MARGIN


func _in_corridor(at: Vector2, origin: Vector2, dir: Vector2, length: float,
		width: float) -> bool:
	var to := at - origin
	var forward := to.dot(dir)
	if forward < -12.0 or forward > length + FoldLaw.HIT_MARGIN:
		return false
	return absf(to.cross(dir)) <= width * 0.5 + FoldLaw.HIT_MARGIN


## 三种形状共用一条闸口：实体在形状里 = 全伤；只有对位落点在形状里 = 镜像比例伤
func _apply_shape(u: Node2D, inside: bool, folded: bool, dmg: float, kind: String,
		elem: String, debuff_id: String, debuff_t: float) -> void:
	if u == null or not is_instance_valid(u):
		return
	if not inside and not folded:
		return
	if _hit_once.has(u.get_instance_id()):
		return
	_hit_once[u.get_instance_id()] = true
	if inside:
		_direct_landings += 1
	else:
		_fold_landings += 1
	## 直接盖住 = 全伤；只有对位落点被盖住 = 镜像比例伤（折过来那一面打折）
	deal_damage_to(u, dmg if inside else dmg * FoldLaw.MIRROR_RATIO, kind, elem)
	if debuff_id != "" and u.has_method("apply_debuff"):
		u.call("apply_debuff", debuff_id, debuff_t)


func _hit_fan(reach: float, angle_deg: float, dmg: float, kind: String, elem: String,
		debuff_id: String, debuff_t: float) -> void:
	var dir := facing.normalized()
	var cos_half := cos(deg_to_rad(angle_deg * 0.5))
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		var unit := u as Node2D
		var inside := _in_fan(unit.global_position, global_position, dir, reach, cos_half)
		var img := _fold_image_of(unit)
		if img != Vector2.INF:
			_fold_windows += 1
		var folded := not inside and img != Vector2.INF \
			and _in_fan(img, global_position, dir, reach, cos_half)
		_apply_shape(unit, inside, folded, dmg, kind, elem, debuff_id, debuff_t)


func _hit_circle(center: Vector2, radius: float, dmg: float, kind: String, elem: String,
		debuff_id: String, debuff_t: float) -> void:
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		var unit := u as Node2D
		var inside := _in_circle(unit.global_position, center, radius)
		var img := _fold_image_of(unit)
		if img != Vector2.INF:
			_fold_windows += 1
		var folded := not inside and img != Vector2.INF and _in_circle(img, center, radius)
		_apply_shape(unit, inside, folded, dmg, kind, elem, debuff_id, debuff_t)


func _hit_corridor(origin: Vector2, dir: Vector2, length: float, width: float,
		dmg: float, kind: String, elem: String, debuff_id: String, debuff_t: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		var unit := u as Node2D
		var inside := _in_corridor(unit.global_position, origin, dir, length, width)
		var img := _fold_image_of(unit)
		if img != Vector2.INF:
			_fold_windows += 1
		var folded := not inside and img != Vector2.INF \
			and _in_corridor(img, origin, dir, length, width)
		_apply_shape(unit, inside, folded, dmg, kind, elem, debuff_id, debuff_t)


# ===================== 八式 =====================

## 按纸：身前扇形 + 对侧镜像同帧落掌印
func _cast_press(b: Dictionary) -> void:
	var dmg := MoveDB.boss_damage(F_PRESS, attack_power, phase)
	SkillFx.play_at_strike(self, "skill_fold_press", b, facing)
	_hit_fan(float(b.get("range", 178.0)), float(b.get("angle", 104.0)), dmg,
		String(b.get("attack_kind", "physical_melee")), String(b.get("damage_element", "water")),
		"fold_mark", float(b.get("debuff_time", 4.0)))
	_finish_skill()


## 循痕：沿折痕方向突进，掠过的走廊上两面一起割
func _cast_trace(b: Dictionary) -> void:
	if not _field_valid():
		_finish_skill()
		return
	var sp: Dictionary = _field.nearest(global_position)
	if sp.is_empty():
		_finish_skill()
		return
	var dir := FoldLaw.crease_dir(sp.get("a", Vector2.ZERO) as Vector2,
		sp.get("b", Vector2.ZERO) as Vector2)
	var p := _focus()
	if p != null and dir.dot(p.global_position - global_position) < 0.0:
		dir = -dir
	var span := float(b.get("range", 380.0))
	var old := global_position
	var land := _clamp_point(old + dir * span)
	global_position = land
	_set_facing(dir)
	SkillFx.play_at_strike(self, "skill_fold_trace", b, dir)
	TreasureFx.play_swap(get_parent(), old, land)
	var dmg := MoveDB.boss_damage(F_TRACE, attack_power, phase)
	_hit_corridor(old, dir, old.distance_to(land), float(b.get("width", 132.0)), dmg,
		String(b.get("attack_kind", "physical_melee")), String(b.get("damage_element", "wind")),
		"fold_mark", float(b.get("debuff_time", 2.6)))
	_finish_skill()


## 跨缝：从这头的圆牌钻进去，从那头的圆牌出来并落斩
func _cast_stride(b: Dictionary) -> void:
	var p := _focus()
	if p == null or not _field_valid():
		_finish_skill()
		return
	var land := _stride_landing(p)
	if land == Vector2.INF or land.distance_to(p.global_position) > STRIDE_LAND:
		_finish_skill()
		return
	var old := global_position
	global_position = _clamp_point(land)
	_set_facing((p.global_position - global_position).normalized())
	SkillFx.play_at_strike(self, "skill_fold_stride", b, facing)
	TreasureFx.play_swap(get_parent(), old, global_position)
	var dmg := MoveDB.boss_damage(F_STRIDE, attack_power, phase)
	_hit_circle(global_position, float(b.get("range", 132.0)), dmg,
		String(b.get("attack_kind", "physical_melee")), String(b.get("damage_element", "water")),
		"", 0.0)
	_finish_skill()


## 圆牌另一头里离人最近的那个落点
func _stride_landing(p: Node2D) -> Vector2:
	if not _field_valid() or p == null:
		return Vector2.INF
	## 挑「出口离玩家最近」的那一对：跨过去就等于绕到人身边落斩
	return _field.seam_exit_near(p.global_position)


## 押痕：把折痕立到你与我**正中间**且垂直于连线 —— 折过来之后你的对位点就在我脚下。
## 这一式是整个机制的教科书：玩家看到「离痕远」不再安全的那一刻，规则才真的讲完。
func _cast_pressmark(b: Dictionary) -> void:
	var p := _focus()
	if p == null or not _field_valid():
		_finish_skill()
		return
	var dmg := MoveDB.boss_damage(F_PRESSMARK, attack_power, phase)
	## ⚠ 这里**不能**加预判提前量：bisect 是在落帧执行的（_fire_attack 已经走完前摇），
	##   此刻玩家位置就是命中位置 —— 再加提前量等于把对位点自己算歪，
	##   押痕那一记 150 的圆反而打空（第一版就栽在这儿）。
	##   需要提前量的是**周期性重折**：那是 1.2 秒前就摆好的痕，见 _anchor_player_for_field。
	## ⚠ 压不出这一折就只落 FX、不打掌印：掌印圆只有 150，硬拍在一折对位点偏 188 的痕上
	##   就是玩家看得见起手却没人挨打（起手闸口已经挡掉绝大多数，这里兜住玩家临场变向那一下）。
	if not _field.bisect(global_position, p.global_position,
			float(b.get("pressmark_length", PRESSMARK_LEN))):
		SkillFx.play_at_strike(self, "skill_fold_seam", b, facing)
		_finish_skill()
		return
	SkillFx.play_at_strike(self, "skill_fold_seam", b, facing)
	## 掌印落在它自己脚下（那正是玩家被折过来的位置）；伤害照到真人
	_hit_circle(global_position, float(b.get("range", 150.0)), dmg,
		String(b.get("attack_kind", "elemental")), String(b.get("damage_element", "water")),
		"fold_mark", float(b.get("debuff_time", 4.0)))
	_finish_skill()


## 叠掩：折一层纸护身 —— 首次受击大减，且这段时间它的对位面不存在（玩家借不走）
func _cast_shroud(b: Dictionary) -> void:
	_shroud_left = float(b.get("shroud_time", 3.2))
	_shroud_guard_used = false
	SkillFx.play_at_strike(self, "skill_fold_shroud", b, facing)
	_finish_skill()


## 碎痕：沿痕撕一条宽直线（不依赖镜像），代价是自己 4 秒没有镜像可用
func _cast_tear(b: Dictionary) -> void:
	var dmg := MoveDB.boss_damage(F_TEAR, attack_power, phase)
	var dir := facing.normalized()
	if _field_valid():
		var sp: Dictionary = _field.nearest(global_position)
		if not sp.is_empty():
			var cd := FoldLaw.crease_dir(sp.get("a", Vector2.ZERO) as Vector2,
				sp.get("b", Vector2.ZERO) as Vector2)
			var p := _focus()
			if p != null and cd.dot(p.global_position - global_position) < 0.0:
				cd = -cd
			dir = cd
	SkillFx.play_at_strike(self, "skill_fold_tear", b, dir)
	_hit_corridor(global_position + dir * 8.0, dir, float(b.get("range", 560.0)),
		float(b.get("width", 220.0)), dmg,
		String(b.get("attack_kind", "elemental")), String(b.get("damage_element", "thunder")),
		"fold_mark", float(b.get("debuff_time", 3.0)))
	## 撕完这块纸就摊平了：全场痕作废 4 秒，玩家的镜像落点同时也没有
	var down := float(b.get("tear_disable_time", FoldLaw.TEAR_DOWN_TIME))
	if _field_valid():
		_field.disable_for(down)
	## 只报「痕被摊平了多久」这条新状态 —— 招名已由 show_skill_line 报过，不许再拼一遍
	## -214：招名占的是 -190 那一行，状态字再写 -184 会和它叠成一坨
	show_windup_line("痕已摊平 %.0f 秒" % down, 0.9, 17, 240.0,
		Color(0.86, 0.92, 0.98), -214.0)
	_finish_skill()


## 双屏：折痕两端的圆牌各立一具纸影，两道线同时朝人合过来
func _cast_twin(b: Dictionary) -> void:
	if not _field_valid():
		_finish_skill()
		return
	var sp: Dictionary = _field.nearest(global_position)
	if sp.is_empty():
		_finish_skill()
		return
	var p := _focus()
	if p == null:
		_finish_skill()
		return
	var dmg := MoveDB.boss_damage(F_TWIN, attack_power, phase) * float(b.get("twin_ratio", 0.45))
	var a := sp.get("a", Vector2.ZERO) as Vector2
	var bb := sp.get("b", Vector2.ZERO) as Vector2
	var reach := float(b.get("range", 460.0))
	for end in [a, bb]:
		var dir := ((p.global_position - (end as Vector2)).normalized())
		SkillFx.play_at_point(get_parent(), "skill_fold_twin", b, dir, end as Vector2, self)
		## 两道线各自一次结算：站在两条线夹住的位置上就会挨两下（各 45%）
		_hit_once.clear()
		_hit_corridor(end as Vector2, dir, reach, float(b.get("width", 96.0)), dmg,
			String(b.get("attack_kind", "elemental")), String(b.get("damage_element", "water")),
			"", 0.0)
	_finish_skill()


## 三重落纸：三个互通区依次落掌 —— 二阶段专属机制层的交付
func _cast_triple(b: Dictionary) -> void:
	var p := _focus()
	if p == null or not _field_valid():
		_finish_skill()
		return
	_triple_dmg = MoveDB.boss_damage(F_TRIPLE, attack_power, phase)
	_triple_plan = _triple_zones(p.global_position)
	if _triple_plan.is_empty():
		_finish_skill()
		return
	_triple_left = 0.0
	SkillFx.play_at_strike(self, "skill_fold_triple", b, facing)
	_finish_skill()


## 三区落点：人所在的那块、借痕①折过来的那块、借痕②折过来的那块
func _triple_zones(player_pos: Vector2) -> Array:
	var out: Array = [player_pos]
	var sps: Array = _field.spans
	for i in mini(2, sps.size()):
		var sp: Dictionary = sps[i]
		out.append(FoldField.mirror_across(sp, player_pos))
	if out.size() < 3 and sps.size() >= 2:
		## 两条痕的复合（夹层）：P2 才存在的第三个区
		out.append(FoldLaw.mirror_twice(
			(sps[0] as Dictionary).get("a", Vector2.ZERO) as Vector2,
			(sps[0] as Dictionary).get("b", Vector2.ZERO) as Vector2,
			(sps[1] as Dictionary).get("a", Vector2.ZERO) as Vector2,
			(sps[1] as Dictionary).get("b", Vector2.ZERO) as Vector2,
			player_pos))
	return out


func _triple_covers(p: Node2D) -> bool:
	if not _field_valid() or p == null:
		return false
	var img := _fold_image_of(p)
	for z in _triple_zones(p.global_position):
		if _in_circle(p.global_position, z as Vector2, 168.0):
			return true
		if img != Vector2.INF and _in_circle(img, z as Vector2, 168.0):
			return true
	return false


func _tick_triple(delta: float) -> void:
	if _triple_plan.is_empty():
		return
	_triple_left -= delta
	if _triple_left > 0.0:
		return
	var b := MoveDB.resolve_boss(F_TRIPLE)
	var radius := float(b.get("range", 168.0))
	var zone: Vector2 = _triple_plan.pop_front()
	_triple_left = float(b.get("interval", 0.34))
	SkillFx.play_at_point(get_parent(), "skill_fold_triple", b, facing, zone, self)
	_hit_circle(zone, radius, _triple_dmg,
		String(b.get("attack_kind", "elemental")), String(b.get("damage_element", "water")),
		"fold_mark", 3.0)


# ===================== 阶段与终局 =====================

func _on_phase_two() -> void:
	_phase_two = true
	if _field_valid():
		_field.set_phase(2)


func _die() -> void:
	_triple_plan = []
	if _field != null and is_instance_valid(_field):
		## 它死了，这张纸就摊回去：痕与圆牌一起收掉，不留残余判定
		_field.disable_for(999.0)
	_field = null
	super._die()

## 布点不能落到墙外（与执烛同一口径）
func _clamp_point(pos: Vector2) -> Vector2:
	if arena_half_extents == Vector2.ZERO:
		return pos
	return Vector2(
		clampf(pos.x, arena_center.x - arena_half_extents.x + arena_margin,
			arena_center.x + arena_half_extents.x - arena_margin),
		clampf(pos.y, arena_center.y - arena_half_extents.y + arena_margin,
			arena_center.y + arena_half_extents.y - arena_margin))


## 循痕现在打不打得到人：沿痕方向（朝人那一头）滑过去的走廊盖不盖得住
func _trace_covers(p: Node2D) -> bool:
	if not _field_valid() or p == null:
		return false
	var sp: Dictionary = _field.nearest(global_position)
	if sp.is_empty():
		return false
	var b := MoveDB.resolve_boss(F_TRACE)
	var dir := FoldLaw.crease_dir(sp.get("a", Vector2.ZERO) as Vector2,
			sp.get("b", Vector2.ZERO) as Vector2)
	if dir.dot(p.global_position - global_position) < 0.0:
		dir = -dir
	return _in_corridor(p.global_position, global_position, dir,
			float(b.get("range", 380.0)), float(b.get("width", 132.0)))
