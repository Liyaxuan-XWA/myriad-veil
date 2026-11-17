class_name DomainBoss04B
extends BossBase
## 照影界第 2 位 · 执烛 —— 投影 · 身外之影（2026-11-02）
##
## 场上只有一处光源（界灯）。它自己几乎不打人，**地上那条影身才是判定**：
## 影身从它脚下沿「本体 − 光源」方向铺出去，长度只由它离灯有多远决定 ——
## 影长就是它的射程，所以「把 BOSS 逼到灯下」是真的在拆它的招，不是数值减免。
##
## 二阶段专属机制层「夺灯 · 反照」：它把界灯提进自己手里 ——
## 从此它没有影子，**玩家的影子**成了它的交付通道（起手时锚定在玩家脚下、朝背离它的方向）。
##
## 没有势条 / 资源条 / 叠层引爆。读数只有三个可见量：灯在哪、影子属于谁、影长多少。
## 首战空手可破：任意物理 / 术法命中都能打它本体，影身招式是物理可弹反、
## 术法招可走位；不需要任何执烛功法。

const F_CUT := "form_shadow_cut"
const F_REACH := "form_shadow_reach"
const F_BIND := "form_shadow_bind"
const F_STEP := "form_shadow_step"
const F_DIM := "form_shadow_dim"
const F_BEAM := "form_shadow_beam"
const F_SPLIT := "form_shadow_split"
const F_LONGNIGHT := "form_shadow_longnight"

## 参与「按距离与影长评分选招」的招（其余是条件招）
const SCORED: Array = [F_CUT, F_REACH, F_BEAM]

const RIG_SCRIPT := "res://scripts/visual/boss_rig_zhizhu.gd"
const RIG_DATA := "res://assets/characters/boss/zhizhu_rig/rig.tres"
## ⚠ preload 而不是类名：新建 class_name 还没进编辑器的全局类缓存，
##   直接写 ShadowSweeper 会让本脚本解析失败
const SWEEPER_SCRIPT := preload("res://scripts/combat/shadow_sweeper.gd")
## 站起来的影身剪影：影根那一具人形（分影脱手后也用它，读得出「是影子在打人」）
const SHADOW_ROOT_TEX := preload("res://assets/effects/skills/zhizhu_shadow.png")
const SHADOW_ROOT_SCALE := 0.34

## 弹反影身招 → 影子折回来砍它自己（按这一招本体的伤害系数 × 0.9 反噬，走真伤）
const PARRY_REFLECT_RATIO := 0.9
## 缚影：起手时玩家速度低于这个值才算「按住了」
const BIND_CATCH_SPEED := 46.0
const BIND_T := 0.62          ## 锚点落在影身的这一比例处
const BAND_EPS := 26.0        ## 走廊判定的端点余量

var _phase_two: bool = false
var _lamp_owned: bool = false
var _lamp: ShadowLamp = null
var _shadow: ShadowVisual = null
var _band_v: ShadowVisual = null          ## P2 画在玩家脚下的锚定影带
var _sweeper: Node2D = null
var _cools: Dictionary = {}
var _recent: Array = []
var _decide_wait: float = 0.0
var _current_skill: String = ""
var _dim_left: float = 0.0
var _split_left: float = 0.0
var _bind_anchor: Dictionary = {}
var _bind_left: float = 0.0
var _bind_caught: bool = false
var _anchor: Dictionary = {}               ## 起手时锚定的交付通道（P2 用）
var _lamp_pending: bool = false
var _lamp_glow: Sprite2D = null
var _lamp_pool: Sprite2D = null      ## 夺灯后跟在本体脚底的地面光池


func _setup() -> void:
	boss_id = "boss_04_b"
	_phase_two = false
	_lamp_owned = false
	_cools.clear()
	_recent.clear()
	_decide_wait = 0.0
	_current_skill = ""
	_dim_left = 0.0
	_split_left = 0.0
	_bind_left = 0.0
	_bind_anchor = {}
	_anchor = {}
	_sweeper = null
	_band_v = null
	_build_shadow()
	_lamp_pending = true


# ===================== 光源与影身几何 =====================

## 界灯：同场只有一盏（召唤执烛助战时复用敌方那盏），没有就自己立一盏
func _ensure_lamp() -> void:
	if _lamp != null and is_instance_valid(_lamp):
		return
	var host := get_parent()
	if host == null:
		return
	_lamp = ShadowLamp.find(host, self)
	if _lamp == null:
		_lamp = ShadowLamp.new()
		_lamp.name = "RealmLamp"
		_lamp.owner_unit = self
		host.add_child(_lamp)
		_lamp.global_position = _lamp_home()


func _lamp_home() -> Vector2:
	if arena_half_extents != Vector2.ZERO:
		var lim_y := maxf(60.0, arena_half_extents.y - arena_margin - 40.0)
		return arena_center + Vector2(0.0, -minf(ShadowLaw.LAMP_FORWARD, lim_y))
	return global_position + Vector2(0.0, -ShadowLaw.LAMP_FORWARD)


func _physics_process(delta: float) -> void:
	if state == BossState.DEAD:
		return
	if _lamp_pending:
		_lamp_pending = false
		_ensure_lamp()
	super._physics_process(delta)
	_update_shadow()


func _light_pos() -> Vector2:
	if _lamp_owned:
		return global_position
	if _lamp != null and is_instance_valid(_lamp):
		return _lamp.global_position
	return global_position + Vector2(0.0, -ShadowLaw.LAMP_FORWARD)


## 本体离光源越远影越长；暗场期间整体收缩
## （夺灯前压的是**自己的**影，P1 的远程射程直接掉一档；夺灯后压的是玩家的影带，
##   只收到 0.72 —— 否则暗场反而把玩家的退路清空，读不出规则）
func _shadow_length_at(pos: Vector2) -> float:
	var raw := ShadowLaw.shadow_len(pos.distance_to(_light_pos()))
	if _dim_left <= 0.0:
		return raw
	return raw * (ShadowLaw.DIM_MULT if not _lamp_owned else 0.72)


func _shadow_dir_of(pos: Vector2) -> Vector2:
	return ShadowLaw.shadow_dir(pos, _light_pos(), facing)


## 交付通道：P1 = 本体的影身；P2 = 玩家被锚定的影带
## {origin: Vector2, dir: Vector2, length: float, anchored: bool}
func _channel() -> Dictionary:
	if not _lamp_owned:
		return {"origin": feet_position(), "dir": _shadow_dir_of(global_position),
			"length": _shadow_length_at(global_position), "anchored": false}
	if not _anchor.is_empty():
		return _anchor
	var p := _focus()
	if p == null:
		return {}
	return _anchor_at(p.global_position)


func _anchor_at(pos: Vector2) -> Dictionary:
	## 夺灯后：光源是本体，玩家脚下的影带朝背离它的方向铺出去
	return {"origin": pos, "dir": _shadow_dir_of(pos),
		"length": _shadow_length_at(pos), "anchored": true}


func _build_shadow() -> void:
	if _shadow != null and is_instance_valid(_shadow):
		_shadow.queue_free()
	_shadow = ShadowVisual.new()
	_shadow.name = "BodyShadow"
	## 影根用专门的一张「站起来的影子」，不用本体立绘：
	## 本体是彩色的，直接压暗当影子会连衣服轮廓一起抄，读起来像残影而不是影子。
	_shadow.set_root(SHADOW_ROOT_TEX, true, SHADOW_ROOT_SCALE)
	_shadow.ink = Color(0.02, 0.03, 0.06)
	_shadow.tip_color = Color(0.70, 0.92, 1.0)
	add_child(_shadow)
	_shadow.position = Vector2(0.0, feet_offset())


func _update_shadow() -> void:
	if _shadow == null or not is_instance_valid(_shadow):
		return
	if _split_left > 0.0:
		## 影子已经脱手，本体脚下只剩一团
		_shadow.set_stub(0.5)
	elif _lamp_owned:
		## 它自己就是光源 —— 本体不再有影
		_shadow.set_stub(0.0)
	else:
		_shadow.set_shape(_shadow_dir_of(global_position), _shadow_length_at(global_position),
			ShadowLaw.WIDTH_TIP, 1.0)
	_update_band_readout()


## P2：把「你的影子归它用」这条规则画在玩家脚下
## 画出来的带子必须与实际判定同长同向（范围=判定），起手锚定后就不再把视觉拖回玩家身上
func _update_band_readout() -> void:
	if not _lamp_owned:
		if _band_v != null and is_instance_valid(_band_v):
			_band_v.fade_out(0.25)
			_band_v = null
		return
	if _band_v == null or not is_instance_valid(_band_v):
		var host := get_parent()
		if host == null:
			return
		_band_v = ShadowVisual.new()
		_band_v.name = "PlayerBand"
		_band_v.ink = Color(0.10, 0.06, 0.16)
		_band_v.tip_color = Color(0.86, 0.78, 1.0)
		host.add_child(_band_v)
	var chan := _channel()
	if chan.is_empty():
		return
	_band_v.global_position = chan.get("origin", Vector2.ZERO) as Vector2
	_band_v.set_shape(chan.get("dir", Vector2.DOWN) as Vector2,
		float(chan.get("length", 0.0)), ShadowLaw.WIDTH_TIP,
		0.95 if _windup_active() else 0.42)


func _windup_active() -> bool:
	return state == BossState.WINDUP and not _anchor.is_empty()


# ===================== 计时与受伤 =====================

func _tick_cooldowns(delta: float) -> void:
	for sid in _cools.keys():
		if float(_cools[sid]) > 0.0:
			_cools[sid] = maxf(0.0, float(_cools[sid]) - delta)
	if _decide_wait > 0.0:
		_decide_wait = maxf(0.0, _decide_wait - delta)
	if _dim_left > 0.0:
		_dim_left = maxf(0.0, _dim_left - delta)
		if _dim_left <= 0.0:
			_relamp()
	if _split_left > 0.0:
		_split_left = maxf(0.0, _split_left - delta)
	if _bind_left > 0.0:
		_bind_left = maxf(0.0, _bind_left - delta)
		if _bind_left <= 0.0:
			_resolve_bind()
	if _sweeper != null and not is_instance_valid(_sweeper):
		_sweeper = null


func _relamp() -> void:
	if _lamp_owned:
		return
	if _lamp != null and is_instance_valid(_lamp):
		_lamp.set_lit(1.0, 0.5)


func damage_taken_multiplier(damage_kind: String) -> float:
	var m := 1.0
	if _dim_left > 0.0 and damage_kind == "physical":
		m *= ShadowLaw.DIM_PHYS_VULN
	if _split_left > 0.0:
		m *= ShadowLaw.SPLIT_TAKEN_MULT
	return m


## 明灭期间本体攻速上涨：所有状态计时缩短
func _recover_time() -> float:
	var t := super._recover_time()
	return t / ShadowLaw.DIM_SPEED_MULT if _dim_left > 0.0 else t


func _idle_time() -> float:
	var t := super._idle_time()
	return t / ShadowLaw.DIM_SPEED_MULT if _dim_left > 0.0 else t


# ===================== 选招 =====================

func _on_chase_reached(_dist: float) -> void:
	_choose()


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
	var chan := _channel()
	var reach := _channel_covers(chan, p.global_position)

	## 影子够不着你 → 先抢几何（踏灯绕到灯的另一侧），不许原地空放
	if not reach and _ready_cd(F_STEP) and _split_left <= 0.0:
		_begin(F_STEP)
		return
	## 被贴到灯下 / 影子被压短 → 捻灯，换成本体近战节奏
	if _ready_cd(F_DIM) and (d <= 200.0 or (not reach and _dim_left <= 0.0)):
		_begin(F_DIM)
		return
	if _phase_two and _ready_cd(F_LONGNIGHT) and d <= 560.0:
		_begin(F_LONGNIGHT)
		return
	## 缚影看的是「起手瞬间你在不在动」，所以别对贴脸乱走的玩家白甩这一招
	## （也让投晷有出场空间，不至于被缚影长期压制）
	if _ready_cd(F_BIND) and reach and _split_left <= 0.0 \
			and (d >= 260.0 or not _is_moving(p)):
		_begin(F_BIND)
		return
	if _ready_cd(F_SPLIT) and d >= 200.0 and _split_left <= 0.0:
		_begin(F_SPLIT)
		return

	var pool := SCORED.duplicate()
	var best := ""
	var best_score := -999.0
	for sid in pool:
		if not _ready_cd(String(sid)) or not _usable(String(sid), chan, p.global_position, d):
			continue
		var sc := _score(String(sid), d, chan) + randf() * 0.9 - _repeat_penalty(String(sid))
		if sc > best_score:
			best_score = sc
			best = String(sid)
	if best == "":
		state = BossState.CHASE
		return
	_begin(best)


func _ready_cd(sid: String) -> bool:
	return float(_cools.get(sid, 0.0)) <= 0.0


## 影身脱手期间，凡是要用影子的招一律不许出
func _usable(sid: String, chan: Dictionary, player_pos: Vector2, d: float) -> bool:
	if chan.is_empty():
		return sid == F_CUT or sid == F_BEAM
	match sid:
		F_CUT: return d <= 175.0
		F_REACH:
			if _split_left > 0.0 and not _lamp_owned:
				return false
			return _channel_covers(chan, player_pos)
		F_BEAM: return d >= 130.0 and d <= float(MoveDB.resolve_boss(F_BEAM).get("range", 520.0)) + 40.0
	return false


## 走廊能不能盖住玩家（P1 是几何门禁；P2 锚定带始终以玩家为根，故起手时必然盖住）
func _channel_covers(chan: Dictionary, player_pos: Vector2) -> bool:
	if chan.is_empty():
		return false
	if bool(chan.get("anchored", false)):
		return true
	var origin := chan.get("origin", Vector2.ZERO) as Vector2
	var dir := chan.get("dir", Vector2.ZERO) as Vector2
	var length := float(chan.get("length", 0.0))
	## 玩家在本体脚边时，影子的根段也算能打到
	var to := player_pos - origin
	if to.length() <= 175.0:
		return true
	return ShadowLaw.corridor_contains(origin + dir * 8.0, dir, length, player_pos, BAND_EPS)


func _score(sid: String, d: float, chan: Dictionary) -> float:
	var length := float(chan.get("length", 0.0))
	match sid:
		F_CUT: return 3.0 - absf(d - 110.0) / 170.0
		F_REACH:
			## 影越长越愿意用这一招（这是它挣位置的动力）
			return 1.2 + length / 260.0 - absf(d - length * 0.7) / 300.0
		F_BEAM: return 2.2 - absf(d - 330.0) / 320.0
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


# ===================== 起手 / 释放 =====================

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
	var focus := _focus()
	if focus != null:
		_set_facing(((focus as Node2D).global_position - global_position).normalized())
	## P2 起手就把交付通道锚在玩家脚下：这条带子从此不动，
	## 玩家要么侧移、要么往它身上压出去 —— 直直后退就会撞进自己的影子里
	_anchor = {} if not _lamp_owned else _anchor_at((focus as Node2D).global_position)
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
		F_CUT: _cast_cut(b)
		F_REACH: _cast_reach(b)
		F_BIND: _cast_bind(b)
		F_STEP: _cast_step(b)
		F_DIM: _cast_dim(b)
		F_BEAM: _cast_beam(b)
		F_SPLIT: _cast_split(b)
		F_LONGNIGHT: _cast_longnight(b)
		_: _finish_skill()


func _finish_skill() -> void:
	_record(_current_skill)
	_current_skill = ""
	_anchor = {}
	state = BossState.RECOVER
	state_timer = 0.45


func _focus() -> Node2D:
	if target != null and is_instance_valid(target) and not BossBase.is_unit_dead(target):
		return target
	var p := focus_node()
	if p != null and is_instance_valid(p) and not BossBase.is_unit_dead(p):
		return p
	return null


## 目标此刻是否在移动 —— 缚影「按住 / 抓空」的唯一判据（玩家侧同一口径）
func _is_moving(u: Node2D) -> bool:
	if u == null or not is_instance_valid(u):
		return false
	var vel: Variant = u.get("velocity")
	return vel is Vector2 and (vel as Vector2).length() > BIND_CATCH_SPEED


# ===================== 八式 =====================

## 削影：本体身前扇形 + 影尖反手补一段
func _cast_cut(b: Dictionary) -> void:
	var dmg := MoveDB.boss_damage(F_CUT, attack_power, phase)
	SkillFx.play_at_strike(self, "skill_shadow_cut", b, facing)
	_deal_cone(float(b.get("range", 150.0)), float(b.get("angle", 92.0)), dmg,
		String(b.get("attack_kind", "physical_melee")), String(b.get("damage_element", "dark")))
	var chan := _channel()
	if not chan.is_empty() and float(chan.get("length", 0.0)) >= SkillDB.SHADOW_CUT_TIP_EXTRA:
		var tip := ShadowLaw.shadow_point(chan.get("origin", Vector2.ZERO) as Vector2,
			chan.get("dir", Vector2.DOWN) as Vector2, float(chan.get("length", 0.0)), 1.0)
		_deal_circle(tip, 74.0, dmg * 0.6, "physical", "", "", 0.0)
	_show_band_flash(chan)
	_finish_skill()


## 投晷：沿影身一整条走廊的长刺，射程 = 影长
func _cast_reach(b: Dictionary) -> void:
	var dmg := MoveDB.boss_damage(F_REACH, attack_power, phase)
	SkillFx.play_at_strike(self, "skill_shadow_reach", b, facing)
	var chan := _channel()
	if chan.is_empty():
		_finish_skill()
		return
	_deal_corridor(chan, dmg, String(b.get("attack_kind", "physical_melee")),
		String(b.get("damage_element", "dark")), "shadow_soak", 2.0)
	_show_band_flash(chan)
	_finish_skill()


## 缚影：在影身中段落印，0.7 秒后生效；起手时你在跑动 → 按到的只是空影
func _cast_bind(b: Dictionary) -> void:
	var chan := _channel()
	if chan.is_empty():
		_finish_skill()
		return
	var p := _focus()
	var moving := _is_moving(p)
	var anchor_pos := ShadowLaw.shadow_point(chan.get("origin", Vector2.ZERO) as Vector2,
		chan.get("dir", Vector2.DOWN) as Vector2, float(chan.get("length", 0.0)), BIND_T)
	_bind_anchor = {"pos": anchor_pos, "stationary": not moving,
		"dmg": MoveDB.boss_damage(F_BIND, attack_power, phase)}
	_bind_left = SkillDB.SHADOW_BIND_DELAY
	SkillFx.play_at_point(get_parent(), "skill_shadow_bind", b, facing, anchor_pos, self)
	show_windup_line("缚影 · %s" % ("按住" if not moving else "抓空"), 0.7, 17, 210.0,
		Color(0.58, 0.64, 0.86), -184.0)
	_finish_skill()


func _resolve_bind() -> void:
	if _bind_anchor.is_empty():
		return
	var pos := _bind_anchor.get("pos", Vector2.ZERO) as Vector2
	var dmg := float(_bind_anchor.get("dmg", 0.0))
	var stationary := bool(_bind_anchor.get("stationary", false))
	_bind_anchor = {}
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		if (u as Node2D).global_position.distance_to(pos) > 96.0:
			continue
		# 元素从表里取，不要写死：写死过一次，MoveDB 把影系改成暗时这里没跟着走，
		# 结果暗「蚀」在缚影补斩上整个失效（探针「投晷真的把蚀挂上了 BOSS」抓出来的）
		deal_damage_to(u, (dmg if stationary else dmg * 0.5) * _dmg_scale(), "physical",
			String(MoveDB.resolve_boss("form_shadow_bind").get("damage_element", "dark")))
		if stationary and u.has_method("apply_debuff"):
			u.call("apply_debuff", "shadow_bind", SkillDB.SHADOW_BIND_SECONDS)
		elif u.has_method("apply_debuff"):
			u.call("apply_debuff", "shadow_soak", 1.6)


## 踏灯：绕到灯的另一侧，掠过的走廊上影刃横扫（真的位移）
func _cast_step(b: Dictionary) -> void:
	var p := _focus()
	if p == null:
		_finish_skill()
		return
	var old := global_position
	var light := _light_pos()
	var to_player := p.global_position - light
	if to_player.length_squared() < 16.0:
		to_player = p.global_position - global_position
	var u := to_player.normalized()
	var dist := maxf(p.global_position.distance_to(light), 1.0)
	## 落点要满足「影身够得到人」：影长 = 40 + r×1.15（封顶 620）≥ 玩家距离 − r
	## → 未封顶时 r ≥ (D − 40) / 2.15；影长已经顶到上限时，只能再贴近到 D − 620 以内。
	var need := (dist - ShadowLaw.SHADOW_MIN) / (1.0 + ShadowLaw.SHADOW_SLOPE) + 60.0
	need = maxf(need, dist - ShadowLaw.SHADOW_MAX + 40.0)
	var r := clampf(need, 120.0, maxf(120.0, dist - 110.0))
	var land := _clamp_point(light + u * r)
	global_position = land
	_set_facing((p.global_position - global_position).normalized())
	## 位移后位置由 move_and_slide 之外的直写完成，仍要让动画与特效跟上新位置
	TreasureFx.play_swap(get_parent(), old, land)
	var dmg := MoveDB.boss_damage(F_STEP, attack_power, phase)
	var dir := (land - old)
	var span := dir.length()
	if span > 8.0:
		_deal_corridor({"origin": old, "dir": dir.normalized(), "length": span,
			"anchored": true}, dmg, "physical",
			String(b.get("damage_element", "dark")), "shadow_soak", 1.4)
	show_windup_line("踏灯 · 掠影 %.0f" % span, 0.7, 17, 210.0,
		Color(0.62, 0.72, 0.94), -184.0)
	_finish_skill()


## 明灭：把界灯捻暗 —— 影长塌下去，但本体更凶、也更挨打
func _cast_dim(b: Dictionary) -> void:
	_dim_left = ShadowLaw.DIM_TIME
	if not _lamp_owned and _lamp != null and is_instance_valid(_lamp):
		_lamp.set_lit(0.30, 0.30)
	SkillFx.play_at_strike(self, "skill_shadow_dim", b, facing)
	show_windup_line("执烛 · 明灭" if not _lamp_owned else "执烛 · 挑灯芯", 1.1, 19, 225.0,
		Color(0.66, 0.74, 0.96), -186.0)
	_finish_skill()


## 照骨：本体打出的暗寒光束（暗属性），与影长无关 —— 贴灯躲不掉远程压力的那一份
func _cast_beam(b: Dictionary) -> void:
	var dmg := MoveDB.boss_damage(F_BEAM, attack_power, phase)
	SkillFx.play_at_strike(self, "skill_shadow_beam", b, facing)
	var chan := _channel()
	var width := float(b.get("width", 62.0))
	var aligned := false
	if not chan.is_empty():
		var dir := chan.get("dir", Vector2.ZERO) as Vector2
		aligned = dir.dot(facing.normalized()) > 0.86
		if aligned:
			width = float(b.get("shadow_widen", 96.0))
	_deal_line(float(b.get("range", 520.0)), width, dmg,
		String(b.get("attack_kind", "elemental")), String(b.get("damage_element", "dark")),
		"shadow_soak", 2.0)
	if aligned:
		show_windup_line("照骨 · 沿影加宽", 0.5, 16, 200.0, Color(0.72, 0.90, 1.0), -182.0)
	_finish_skill()


## 分影：撕下影身让它自己去找人；本体这段时间少了一层壳
func _cast_split(b: Dictionary) -> void:
	_split_left = ShadowLaw.SPLIT_TIME
	var host := get_parent()
	if host == null:
		_finish_skill()
		return
	var dmg := MoveDB.boss_damage(F_SPLIT, attack_power, phase)
	_sweeper = SWEEPER_SCRIPT.new()
	_sweeper.name = "TornShadow"
	host.add_child(_sweeper)
	_sweeper.call("setup", self, dmg, ShadowLaw.SPLIT_TIME, ShadowLaw.SPLIT_SWEEP_GAP,
		Callable(self, "_torn_channel"))
	_sweeper.call("set_root_silhouette", SHADOW_ROOT_TEX, SHADOW_ROOT_SCALE * 0.88)
	SkillFx.play_at_strike(self, "skill_shadow_split", b, facing)
	show_windup_line("分影 · 影子脱手", 1.0, 19, 225.0, Color(0.56, 0.62, 0.84), -186.0)
	_finish_skill()


## 脱手影身每拍的走廊：P1 从本体脚下指向玩家此刻的位置；P2 反过来钉在玩家脚下、朝背离它的方向
func _torn_channel() -> Dictionary:
	var p := _focus()
	if p == null:
		return {}
	if _lamp_owned:
		return _anchor_at(p.global_position)
	var origin := feet_position()
	var to := p.global_position - origin
	var dir := to.normalized() if to.length_squared() > 36.0 else facing.normalized()
	return {"origin": origin, "dir": dir,
		"length": minf(_shadow_length_at(global_position), 460.0), "anchored": false}


## 长夜 · 一灯（P2 大招）：夺灯后第一次反照，锚定带向本体收拢
func _cast_longnight(b: Dictionary) -> void:
	var dmg := MoveDB.boss_damage(F_LONGNIGHT, attack_power, phase)
	SkillFx.play_at_strike(self, "skill_shadow_longnight", b, facing)
	var chan := _channel()
	if chan.is_empty():
		_finish_skill()
		return
	var origin := chan.get("origin", Vector2.ZERO) as Vector2
	var dir := chan.get("dir", Vector2.DOWN) as Vector2
	var length := float(chan.get("length", 0.0))
	## 整条锚定带一次落斩 + 脚下一个收拢的圆；圆挂 0.8 秒影缚，
	## 但**起手就画在地上了**，玩家往灯侧（朝它）踏出带子就能整个不吃
	_deal_corridor({"origin": origin, "dir": dir, "length": length, "anchored": true}, dmg,
		"physical", String(b.get("damage_element", "dark")), "", 0.0)
	_deal_circle(origin, 150.0, dmg * 0.7, "physical", "", "shadow_bind", 0.8)
	_show_band_flash(chan)
	_finish_skill()


# ===================== 判定 =====================

## 明灭期间的本体伤害乘区（暗场换来的是更狠、也更挨打的本体）
func _dmg_scale() -> float:
	return ShadowLaw.DIM_SELF_ATTACK_MULT if _dim_left > 0.0 else 1.0


func _deal_corridor(chan: Dictionary, dmg: float, kind: String, elem: String,
		debuff_id: String, debuff_time: float) -> void:
	dmg *= _dmg_scale()
	var origin := chan.get("origin", Vector2.ZERO) as Vector2
	var dir := chan.get("dir", Vector2.ZERO) as Vector2
	var length := float(chan.get("length", 0.0))
	if dir.length_squared() < 0.0001:
		return
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		if not ShadowLaw.corridor_contains(origin + dir * 8.0, dir, length,
				(u as Node2D).global_position, BAND_EPS):
			continue
		deal_damage_to(u, dmg, kind, elem)
		if debuff_id != "" and u.has_method("apply_debuff"):
			u.call("apply_debuff", debuff_id, debuff_time)


func _deal_cone(reach: float, angle_deg: float, dmg: float, kind: String, elem: String) -> void:
	dmg *= _dmg_scale()
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


func _deal_line(reach: float, width: float, dmg: float, kind: String, elem: String,
		debuff_id: String, debuff_time: float) -> void:
	dmg *= _dmg_scale()
	var dir := facing.normalized()
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		var to: Vector2 = (u as Node2D).global_position - global_position
		var forward := to.dot(dir)
		if forward < -12.0 or forward > reach + 18.0:
			continue
		if absf(to.cross(dir)) > width * 0.5 + 18.0:
			continue
		deal_damage_to(u, dmg, kind, elem)
		if debuff_id != "" and u.has_method("apply_debuff"):
			u.call("apply_debuff", debuff_id, debuff_time)


func _deal_circle(pos: Vector2, radius: float, dmg: float, kind: String, elem: String,
		debuff_id: String, debuff_time: float) -> void:
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		if (u as Node2D).global_position.distance_to(pos) > radius + 18.0:
			continue
		deal_damage_to(u, dmg, kind, elem)
		if debuff_id != "" and u.has_method("apply_debuff"):
			u.call("apply_debuff", debuff_id, debuff_time)


## 打出去之后让影尖亮一下（命中反馈，也是「这条带子是真的」的确认）
func _show_band_flash(chan: Dictionary) -> void:
	if chan.is_empty():
		return
	var tip := ShadowLaw.shadow_point(chan.get("origin", Vector2.ZERO) as Vector2,
		chan.get("dir", Vector2.DOWN) as Vector2, float(chan.get("length", 0.0)), 1.0)
	var host := get_parent()
	if host == null:
		return
	var spark := Sprite2D.new()
	spark.texture = SkillFx.dot_texture()
	spark.centered = true
	spark.material = SkillFx.additive_material()
	spark.modulate = Color(0.70, 0.92, 1.0, 0.72)
	spark.scale = Vector2(1.5, 1.5)
	host.add_child(spark)
	spark.global_position = tip
	var tw := spark.create_tween()
	tw.tween_property(spark, "modulate:a", 0.0, 0.32)
	tw.parallel().tween_property(spark, "scale", Vector2(2.6, 2.6), 0.32)
	tw.tween_callback(spark.queue_free)


# ===================== 弹反 / 受击 =====================

## 影身招是物理、可弹反：弹反成功 → 影子折回来砍它自己
## （夺灯之后本体没有影子，这一条自然失效 —— P2 要你改用「离开锚定带」而不是反噬）
func on_parried(source: Node) -> void:
	super.on_parried(source)
	if _current_skill == "" or _lamp_owned:
		return
	var b := MoveDB.resolve_boss(_current_skill)
	if not bool(b.get("parryable", false)):
		return
	var back := attack_power * float(b.get("damage_coeff", 1.0)) * PARRY_REFLECT_RATIO \
		* (ShadowLaw.DIM_SELF_ATTACK_MULT if _dim_left > 0.0 else 1.0) \
		* (1.5 if phase >= 2 else 1.0)
	take_true_damage(back)
	SkillFx.play_at_strike(self, "skill_shadow_reach", b, facing)
	show_windup_line("影反噬身", 0.8, 18, 215.0, Color(0.80, 0.86, 1.0), -186.0)


# ===================== 阶段 / 生命周期 =====================

func _on_phase_two() -> void:
	_phase_two = true
	_lamp_owned = true
	_dim_left = 0.0
	## 夺灯：界灯被提走，光源转交给本体 —— P1 的「站到灯与它之间」当场作废
	if _lamp != null and is_instance_valid(_lamp):
		_lamp.extinguish(1.0)
	_lamp = null
	## 光源转交必须**看得见**：场灯一灭，本体就是全场唯一的光，
	## 不给它挂一圈辉光，玩家看到的是「黑屏里找不到 BOSS」（2026-11-02 截图抓到）
	_attach_carried_lamp()
	show_windup_line("夺灯 · 反照（你的影子归它用）", 1.6, 20, 250.0,
		Color(0.66, 0.72, 0.96), -192.0)
	_cools[F_LONGNIGHT] = 4.0
	_cools[F_REACH] = 1.2


## 把手里的这盏灯画成真正的光：灯体辉光挂在灯笼件上（跟钟摆晃、跟朝向翻），
## 地面光池挂在脚底 —— 一阶段那盏灯的读数是「地上这圈光」，夺灯后必须一起跟过来，
## 否则玩家只剩一个黑漆漆的场上光源，影子从哪儿来又变得没有因。
func _attach_carried_lamp() -> void:
	if _lamp_glow != null and is_instance_valid(_lamp_glow):
		return
	var host: Node2D = self
	var glow_pos := Vector2(30.0, -50.0)
	var glow_k := 1.0
	if skin != null:
		var rig := skin.render_node as BossRig
		var holder: Node2D = rig.part_node("lantern") if rig != null else null
		if holder != null:
			host = holder
			## 提钩在灯笼件原点，灯体在画布口径下方 106px
			glow_pos = Vector2(0.0, 106.0)
			## ⚠ 灯笼件在 rig 里，rig 整体被 SkinVisual 缩到 0.25：
			##   直接按屏幕像素给 scale 只会得到一圈 47px 的芝麻光，实机等于没挂。
			##   先除以挂点的全局缩放，再按「屏幕上要多大」写数值。
			glow_k = 1.0 / maxf(0.02, absf(holder.global_transform.x.x))
	_lamp_glow = Sprite2D.new()
	_lamp_glow.texture = SkillFx.dot_texture()
	_lamp_glow.centered = true
	_lamp_glow.position = glow_pos
	_lamp_glow.scale = Vector2(210.0 / 64.0, 195.0 / 64.0) * glow_k
	_lamp_glow.modulate = Color(0.96, 0.86, 0.62, 0.0)
	_lamp_glow.material = SkillFx.additive_material()
	_lamp_glow.z_index = 6
	host.add_child(_lamp_glow)
	var tw := _lamp_glow.create_tween()
	tw.tween_property(_lamp_glow, "modulate:a", 0.46, 0.8)
	_attach_carried_pool()


## 脚底那圈光池：跟着本体走，本体就是全场唯一光源
func _attach_carried_pool() -> void:
	if _lamp_pool != null and is_instance_valid(_lamp_pool):
		return
	var pool: Texture2D = SkillFx.skill_texture("lamp_pool")
	if pool == null:
		return
	_lamp_pool = Sprite2D.new()
	_lamp_pool.texture = pool
	_lamp_pool.centered = true
	_lamp_pool.position = Vector2(0.0, feet_offset())
	_lamp_pool.scale = Vector2.ONE * (620.0 / float(pool.get_width()))
	_lamp_pool.modulate = Color(0.94, 0.90, 0.78, 0.0)
	_lamp_pool.material = SkillFx.additive_material()
	_lamp_pool.z_index = -2
	add_child(_lamp_pool)
	var tw := _lamp_pool.create_tween()
	tw.tween_property(_lamp_pool, "modulate:a", 0.50, 0.9)


func _die() -> void:
	if _sweeper != null and is_instance_valid(_sweeper):
		_sweeper.call("detach_and_free")
	_sweeper = null
	if _band_v != null and is_instance_valid(_band_v):
		_band_v.queue_free()
	_band_v = null
	if _shadow != null and is_instance_valid(_shadow):
		_shadow.fade_out(0.5)
	_shadow = null
	if _lamp != null and is_instance_valid(_lamp):
		_lamp.extinguish(0.6)
	_lamp = null
	## 夺灯后挂在本体上的光与光池要一起淡掉，否则尸体上留一盏不灭的灯。
	## ⚠ 循环变量是 Variant，`:=` 推不出 create_tween() 的类型会让整个脚本解析失败
	for s in [_lamp_glow, _lamp_pool]:
		if s != null and is_instance_valid(s):
			var tw: Tween = s.create_tween()
			tw.tween_property(s, "modulate:a", 0.0, 0.6)
			tw.tween_callback(s.queue_free)
	_lamp_glow = null
	_lamp_pool = null
	super._die()


func _clamp_point(pos: Vector2) -> Vector2:
	if arena_half_extents == Vector2.ZERO:
		return pos
	return Vector2(
		clampf(pos.x, arena_center.x - arena_half_extents.x + arena_margin,
			arena_center.x + arena_half_extents.x - arena_margin),
		clampf(pos.y, arena_center.y - arena_half_extents.y + arena_margin,
			arena_center.y + arena_half_extents.y - arena_margin))
