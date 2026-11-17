class_name ShadowSweeper
extends Node2D
## 执烛「分影」脱手的影身（2026-11-02）
##
## 影子被撕下来之后自己找人：每一拍先向 `channel_provider` 要一条走廊（几何全部留在
## BOSS 侧，这里只管表现与结算），把墨带**亮 0.45 秒预兆**，再沿这条带子结算一次物理斩。
## 所以它不是自动锁 —— 看见地上那条黑刃转向你脚边，侧移或往前压就能让这一拍扫空。

const TELEGRAPH := 0.45

var damage: float = 0.0
var life: float = 5.2
var gap: float = 0.9
var caster: Node2D = null
var channel_provider: Callable = Callable()
## 影兽这一拍是什么元素：由施法者的 form 传进来（玩家分影 / BOSS 分影同一份口径）。
## 写死会让暗「蚀」在脱手影身上静默失效，而探针只查得见表里那一行。
var element: String = "dark"

var _age: float = 0.0
var _tick: float = 0.30
var _armed: float = 0.0
var _band: ShadowVisual = null
var _pending: Dictionary = {}


func setup(p_caster: Node2D, p_damage: float, p_life: float, p_gap: float,
		p_provider: Callable, p_element: String = "dark") -> void:
	caster = p_caster
	damage = maxf(0.0, p_damage)
	life = maxf(1.0, p_life)
	gap = maxf(0.35, p_gap)
	channel_provider = p_provider
	element = p_element
	# 战报：分影扫击自己成一行（归属走 caster）
	set_meta("report_tag", "分影")


## 影根那具站起来的剪影 —— 撕下来的影子得看得出「是个人形」，不然只是一条会转的黑带
func set_root_silhouette(tex: Texture2D, s: float = 0.3) -> void:
	if _band != null and is_instance_valid(_band):
		_band.set_root(tex, true, s)


func _ready() -> void:
	z_index = -1
	_band = ShadowVisual.new()
	_band.name = "SweeperBand"
	_band.ink = Color(0.03, 0.04, 0.08)
	_band.tip_color = Color(0.66, 0.88, 1.0)
	add_child(_band)


func _physics_process(delta: float) -> void:
	if caster == null or not is_instance_valid(caster):
		detach_and_free()
		return
	_age += delta
	if _age >= life:
		detach_and_free()
		return
	if _armed > 0.0:
		_armed -= delta
		var k := clampf(1.0 - maxf(0.0, _armed) / TELEGRAPH, 0.0, 1.0)
		_paint(_pending, 0.55 + 0.35 * k)
		if _armed <= 0.0:
			_strike()
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = gap
		_aim_now()


func _aim_now() -> void:
	if not channel_provider.is_valid():
		return
	var chan: Dictionary = channel_provider.call()
	if chan.is_empty():
		return
	global_position = chan.get("origin", global_position) as Vector2
	_pending = chan
	_armed = TELEGRAPH
	_paint(chan, 0.55)


func _paint(chan: Dictionary, alpha: float) -> void:
	if _band == null or chan.is_empty():
		return
	_band.set_shape(chan.get("dir", Vector2.RIGHT) as Vector2,
		float(chan.get("length", 200.0)), ShadowLaw.WIDTH_TIP, alpha)


func _strike() -> void:
	var chan := _pending
	_pending = {}
	if chan.is_empty():
		return
	var dir := chan.get("dir", Vector2.RIGHT) as Vector2
	var length := float(chan.get("length", 200.0))
	for raw in _enemies():
		var u := raw as Node2D
		if u == null or not is_instance_valid(u):
			continue
		if not ShadowLaw.corridor_contains(global_position + dir * 8.0, dir, length,
				u.global_position, 22.0):
			continue
		if not u.has_method("take_damage"):
			continue
		## 玩家与 BOSS 的 take_damage 参数顺序不同（玩家是 amount, kind, source, element）
		if u.is_in_group("player"):
			u.call("take_damage", damage, "physical", caster, element)
		else:
			u.call("take_damage", damage, caster, "physical", element)
		if u.has_method("apply_debuff"):
			u.call("apply_debuff", "shadow_soak", 1.4)
	_paint(chan, 0.95)


func _enemies() -> Array:
	var out: Array = []
	# 棋局：施法者是带队伍号的棋子 ⇒ 按队伍筛。
	# 旧写法在这里会去扫 player / ally_summon 两个组，棋盘上都是空的
	# ⇒ 分影扫击谁也扫不到（不崩，静默失效）。
	if caster != null and is_instance_valid(caster) and BossBase.unit_team(caster) >= 0:
		return BossBase.hostile_units(caster)
	## 玩家自己的分影打 BOSS；敌方执烛的分影打玩家与友军召唤物
	var hit_bosses: bool = caster != null and (caster.is_in_group("player") \
			or caster.is_in_group("ally_summon") or caster.get("is_ally") == true)
	if hit_bosses:
		for raw in get_tree().get_nodes_in_group("boss"):
			if is_instance_valid(raw) and raw is Node2D \
					and not BossBase.is_ally_unit(raw as Node2D):
				out.append(raw)
		return out
	for group in ["player", "ally_summon"]:
		for raw in get_tree().get_nodes_in_group(group):
			if is_instance_valid(raw) and raw is Node2D:
				out.append(raw)
	return out


func detach_and_free() -> void:
	set_process(false)
	if _band != null and is_instance_valid(_band):
		_band.fade_out(0.22)
	queue_free()
