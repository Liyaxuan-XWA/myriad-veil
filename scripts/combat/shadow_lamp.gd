class_name ShadowLamp
extends Node2D
## 照影界战场的**界灯** —— 全场唯一光源（2026-11-02，执烛战）
##
## 它没有伤害、没有血量、不能被攻击：它只是「灯在哪儿」这件事的实体。
## 执烛的一切判定都以它为原点；二阶段它被执烛提走，本节点淡出（光源转交本体）。
## 同场只该有一盏：BOSS 侧先按组查找，已存在就不再创建（召唤执烛助战时复用同一盏）。

const GLOW_R := 130.0   ## 灯头自带的小光晕（地上那圈才是主读数，见 POOL_W）
## 界灯贴图实测（`assets/effects/skills/lamp_post.png`，画布 448×832）：
## 灯头在 (240, 280)、石座底边在 y=827。这两个数决定「灯头离地多高」与
## 「光晕挂在哪」——按画布中心摆会把一整盏灯埋进地里。
const LAMP_CANVAS := Vector2(448.0, 832.0)
const LAMP_HEAD := Vector2(240.0, 280.0)
const LAMP_BASE_Y := 827.0
const POST_H := 150.0       ## 灯头离地（屏幕像素）：再高就顶出战斗画面了
## 地面光池半径 —— 影子是从**这个点**放射的，所以光必须落在光源的 ground 投影上，
## 而不是落在灯头上：俯视角里「灯在哪儿」的读数就是地上这圈光。
const POOL_W := 700.0   ## 地面光池在屏幕上的横向宽度

var lit: float = 1.0      ## 1.0 明亮 / 0.35 被捻暗（明灭）
## 立灯的那只执烛。单打时「同场只有一盏」是设计（召唤执烛助战复用敌方那盏），
## 所以这里只记录归属、不改复用规则；棋局里两队执烛各立各的，见 find()。
var owner_unit: Node2D = null
var _glow: Sprite2D = null
var _core: Sprite2D = null
var _sprite: Sprite2D = null
var _base: Sprite2D = null
var _tween: Tween = null
var _head := Vector2.ZERO
var _core_base_scale := 0.5
var _pool_base_scale := 1.0


func _ready() -> void:
	add_to_group("shadow_lamp")
	# 战报行名：界灯造成的伤害自己成一行，归属仍走 owner_unit（执烛那只棋子）
	set_meta("report_tag", "界灯")
	z_index = -1
	var tex := SkillFx.dot_texture()
	var k := POST_H / (LAMP_BASE_Y - LAMP_HEAD.y)
	_head = Vector2((LAMP_HEAD.x - LAMP_CANVAS.x * 0.5) * k, -POST_H)

	## 地面光池：影子从这个点放射，所以「灯在哪儿」的读数是地上这圈光，
	## 不是灯头 —— 俯视角下灯头离它自己的 ground 投影有 150px 远。
	## 贴图自带椭圆与柔衰减（`lamp_pool.png`），所以不再用通用柔边圆拉伸。
	var pool: Texture2D = SkillFx.skill_texture("lamp_pool")
	_base = Sprite2D.new()
	_base.texture = pool if pool != null else tex
	_base.centered = true
	_pool_base_scale = POOL_W / float(pool.get_width()) if pool != null else POOL_W / 64.0
	_base.scale = Vector2.ONE * _pool_base_scale
	_base.modulate = Color(0.86, 0.94, 1.0, 0.0)
	_base.material = SkillFx.additive_material()
	add_child(_base)

	## 灯杆 + 石座 + 六角铜灯是一整张贴图，石座底边贴地
	var post: Texture2D = SkillFx.skill_texture("lamp_post")
	if post != null:
		_sprite = Sprite2D.new()
		_sprite.texture = post
		_sprite.centered = true
		_sprite.scale = Vector2.ONE * k
		_sprite.position = Vector2(0.0, -(LAMP_BASE_Y - LAMP_CANVAS.y * 0.5) * k)
		_sprite.z_index = 1
		add_child(_sprite)

	_glow = Sprite2D.new()
	_glow.texture = tex
	_glow.centered = true
	_glow.position = _head
	_glow.scale = Vector2(GLOW_R / 64.0, GLOW_R / 64.0 * 0.92)
	_glow.modulate = Color(0.78, 0.92, 1.0, 0.30)
	_glow.material = SkillFx.additive_material()
	_glow.z_index = 2
	add_child(_glow)

	_core = Sprite2D.new()
	var flame: Texture2D = SkillFx.skill_texture("lamp_flame")
	_core.texture = flame if flame != null else SkillFx.star_texture()
	_core.centered = true
	_core.position = _head + Vector2(0.0, (6.0 if flame != null else 0.0))
	_core_base_scale = 0.5 if flame == null else 96.0 / 115.0
	_core.scale = Vector2.ONE * _core_base_scale
	_core.modulate = Color(0.92, 0.98, 1.0, 0.85)
	_core.material = SkillFx.additive_material()
	_core.z_index = 3
	add_child(_core)
	_apply()


## 明灭：把灯捻暗一点（影长跟着缩短，具体倍率在 ShadowLaw / BOSS 侧结算）
func set_lit(level: float, seconds: float = 0.35) -> void:
	var target := clampf(level, 0.12, 1.0)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_apply_animated, lit, target, maxf(0.05, seconds))
	_apply()


func _apply_animated(v: float) -> void:
	lit = v
	_apply()


func _apply() -> void:
	if _glow == null:
		return
	var pulse := 0.92 + 0.08 * sin(Time.get_ticks_msec() * 0.0022)
	_glow.modulate.a = 0.34 * lit * pulse
	_core.modulate.a = 0.85 * lit
	_base.modulate.a = 0.62 * lit * pulse
	var k := 0.55 + 0.45 * lit
	_glow.scale = Vector2(GLOW_R / 64.0 * k, GLOW_R / 64.0 * 0.92 * k)
	## 捻暗时光池一起收：贴图自带椭圆与衰减，这里只做等比缩放
	_base.scale = Vector2.ONE * _pool_base_scale * (0.74 + 0.26 * lit)
	## 捻暗时火苗本身也缩下去：「灯小了一圈」要在灯上看得见，不能只有光晕变暗
	if _core != null:
		_core.scale = Vector2.ONE * _core_base_scale * (0.62 + 0.38 * lit)


## 灯被提走：淡出并销毁（光源交给执烛本体）
func extinguish(seconds: float = 0.9) -> void:
	set_process(false)
	var tw := create_tween()
	tw.set_parallel(true)
	for s in [_glow, _core, _base, _sprite]:
		if s != null and is_instance_valid(s):
			tw.tween_property(s, "modulate:a", 0.0, seconds)
	tw.chain().tween_callback(queue_free)


## 场上已存在的界灯（没有返回 null）
static func find(world: Node, owner: Node2D = null) -> ShadowLamp:
	if world == null:
		return null
	# 只有棋局（发起者带队伍号）才按队伍筛：对方那盏不是自己能复用的灯，
	# 于是这只执烛会自己立一盏，而不是在别人那盏下跑 _lamp_owned=false 的全套减益。
	# 单打 / 塔 / 秘境里 owner 没有队伍号 ⇒ 条件恒假 ⇒ 复用规则一字不变。
	var want_team := -1 if owner == null else BossBase.unit_team(owner)
	for raw in world.get_tree().get_nodes_in_group("shadow_lamp"):
		if not is_instance_valid(raw) or not (raw is ShadowLamp):
			continue
		var lamp := raw as ShadowLamp
		if want_team >= 0 and lamp.owner_unit != null:
			if BossBase.unit_team(lamp.owner_unit) != want_team:
				continue
		return lamp
	return null
