class_name ArrayFlag
extends Node2D
## 阵旗（定阵先生机制 · 双侧共用）
## · BOSS 插的旗属于 "array_flag" + "breakable_sword" 组，玩家打**三次**拔掉（take_hit）；
## · 玩家自己的旗不会被自己拔掉（owner_is_boss=false，玩家攻击循环会跳过）。
## · 双侧的旗都**不会自然消失**（用户 2026-10-28 定）：只有打三次 / 解阵清场 /
##   本体退场（含阵旗令召唤到期）才会消失；其余招式都不撤旗。
## 旗只负责「存在 / 被打次数 / 视觉」，连线与判定在各自的控制方。

## 三色阵旗（2026-10-28）：颜色即作用，插下即定型
##   攻（朱砂）= 自动轰击 / 困（墨）= 锁步 / 守（石青）= 减伤
enum Kind { ATTACK = 0, BIND = 1, GUARD = 2 }

## 玩家旗被敌对打掉时发信号（玩家侧接「破阵反噬」；BOSS 旗不接）
signal destroyed(flag: ArrayFlag, by_enemy: bool, source: Node)

## 困旗的锁步范围（画面上用一圈很淡的墨环标出来，免得玩家不知道边界）
const BIND_RADIUS := 90.0

## 打掉一面旗要**三次攻击**（不是血量，也不看伤害高低）
const HITS_TO_BREAK := 3
## 阵线碰撞层：只挡对手，施法者与友军可穿自己的线。
## 玩家线挡 BOSS/敌人，BOSS 线挡玩家/友军。
const LINE_LAYER_PLAYER := 64
const LINE_LAYER_BOSS := 128
## 玩家旗的命中体层：BOSS 投射物查这一层；不挡任何单位移动
const PLAYER_HIT_LAYER := 256
## 受击范围与贴图对齐：判定点抬到旗面中心，半径按旗面宽度给
const HIT_CENTER := Vector2(0.0, -30.0)
const HIT_RADIUS := 32.0
const SPRITE_SCALE := Vector2(0.28, 0.28)

var hits_left: int = HITS_TO_BREAK
var kind: int = Kind.ATTACK
var owner_is_boss: bool = true
## 是否是「玩家可以打掉的敌方旗」；友军召唤出来的旗仍是三色，但不进可破坏组
var breakable: bool = true
var hit_radius: float = HIT_RADIUS
var _spr: Sprite2D = null
var _dead := false
## 供 BOSS AI 把旗当普通单位读取（不会真的按血量算，三次命中必倒）
var hp: float = float(HITS_TO_BREAK)
var max_hp: float = float(HITS_TO_BREAK)
var is_dead: bool = false
var is_dodging: bool = false
var is_parrying: bool = false
var is_teleporting: bool = false
var _last_hit_by_enemy := false
var _last_hit_source: Node = null


func setup(is_boss: bool, can_break: bool = true, kind_id: int = Kind.ATTACK) -> void:
	owner_is_boss = is_boss
	breakable = can_break
	kind = kind_id


func kind_name() -> String:
	return String(ArtDB.ARRAY_FLAG_KIND_NAMES[kind]) if kind >= 0 and kind < 3 else "?"


func kind_color() -> Color:
	return Color(ArtDB.ARRAY_FLAG_KIND_COLORS.get(kind, Color.WHITE))


func _ready() -> void:
	add_to_group("array_flag")
	# 复用玩家的「可破坏物」循环（剑客插地剑那套）：敌方 BOSS 的旗可拔
	# ⚠ 召唤成友军时（阵旗令），它的旗不能被玩家的攻击误拆
	if owner_is_boss and breakable:
		add_to_group("breakable_sword")
	_spr = Sprite2D.new()
	# 双侧共用同一套三色布面（颜色即作用）：玩家旗不再用单色金面，
	# 否则三种旗型在场上读不出区别（2026-10-28 用户要求玩家侧与 BOSS 表现一致）
	_spr.texture = load(ArtDB.array_flag_texture(kind, false))
	_spr.centered = true
	_spr.position = Vector2(0.0, -20.0)
	_spr.scale = SPRITE_SCALE   # 贴图 192×280 → 约 54×78 的画面尺寸
	# 插住后是**静止的**：只给一个固定的倾角，读作"插进地面"而不是贴在屏幕上
	_spr.rotation = deg_to_rad(-4.0)
	_spr.z_index = 2
	add_child(_spr)
	# 杆顶饰：三色靠剪影认（近处）+ 布面色（远处）
	var orn := Sprite2D.new()
	orn.texture = load(String(ArtDB.ARRAY_FLAG_ORNAMENTS.get(kind, "")))
	orn.centered = true
	orn.position = Vector2(-14.6, -54.0)   # 贴图里杆顶金球的位置（192×280 @0.28）
	orn.scale = Vector2(0.26, 0.26)
	orn.rotation = deg_to_rad(-6.0)
	orn.z_index = 3
	add_child(orn)
	# 困旗：地面一圈很淡的墨环，标出 90px 锁步范围（不刷屏，只给边界）
	if kind == Kind.BIND:
		var zone := Sprite2D.new()
		zone.texture = load(ArtDB.ARRAY_FLAG_BIND_TEX)
		zone.centered = true
		zone.position = Vector2(0.0, -4.0)
		zone.scale = Vector2(0.76, 0.76)   # 256 → 约 195px 直径 ≈ 判定 180
		zone.modulate = Color(1.0, 1.0, 1.0, 0.55)
		zone.z_index = 0
		add_child(zone)
	# 落地投影：压扁的暗椭圆，锚住"插在地上"的接触感
	var shadow := Sprite2D.new()
	shadow.texture = _dot_texture()
	shadow.centered = true
	shadow.position = Vector2(2.0, 1.0)
	shadow.scale = Vector2(0.42, 0.14)
	shadow.modulate = Color(0.0, 0.0, 0.0, 0.55)
	shadow.z_index = 1
	add_child(shadow)
	# 归属印：友军（玩家）旗在旗座多一枚很小的金色阵印，布面仍按三色读作用
	if not owner_is_boss:
		var mark := Sprite2D.new()
		mark.texture = _dot_texture()
		mark.centered = true
		mark.position = Vector2(0.0, -5.0)
		mark.scale = Vector2(0.20, 0.10)
		mark.modulate = Color(1.0, 0.82, 0.42, 0.75)
		mark.z_index = 2
		add_child(mark)
		# 玩家旗的实体命中体：BOSS 投射物走 area_entered 打它；不挡移动
		var hit_area := Area2D.new()
		hit_area.name = "Hitbox"
		hit_area.collision_layer = PLAYER_HIT_LAYER
		hit_area.collision_mask = 0
		hit_area.add_to_group("player_array_flag_hitbox")
		var hit_shape := CollisionShape2D.new()
		var hit_rect := RectangleShape2D.new()
		hit_rect.size = Vector2(46.0, 84.0)
		hit_shape.shape = hit_rect
		hit_shape.position = Vector2(0.0, -34.0)
		hit_area.add_child(hit_shape)
		add_child(hit_area)
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.12)


## 玩家攻击判定用的受击点：抬到旗面中心，和贴图对齐（原来按脚下原点算，砍旗面不算中）
func hit_point() -> Vector2:
	return global_position + HIT_CENTER


## 攻击打中一次：**计次数**（3 次打掉），不看伤害。受击时白闪 + 整面旗涨一圈再回弹
## ⚠ 放大只动 `_spr.scale`（等比），不碰根节点 —— 根节点 scale 留给 despawn 的收尾动画
func take_hit(_dmg: float = 0.0) -> void:
	if _dead:
		return
	hits_left -= 1
	hp = maxf(0.0, float(hits_left))
	if _spr != null and is_instance_valid(_spr):
		_spr.modulate = Color(1.8, 1.6, 1.4, 1.0)
		create_tween().tween_property(_spr, "modulate", Color.WHITE, 0.12)
		_spr.scale = SPRITE_SCALE * 1.16
		create_tween().tween_property(_spr, "scale", SPRITE_SCALE, 0.14) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if hits_left <= 0:
		despawn()


## BOSS 普通招式/投射物命中：一次命中算一刀（不看伤害数值），三刀倒。
## 参数不设类型：BOSS 侧有玩家版(amount, attack_kind, source, element)和
## 单位版(amount, source, damage_kind, element, from_projectile)两套调用签名。
func take_damage(_amount: float, _arg2 = null, _arg3 = null, _arg4 = null, _arg5 = null) -> void:
	var src: Node = null
	if _arg2 is Node:
		src = _arg2
	elif _arg3 is Node:
		src = _arg3
	if src != null and is_instance_valid(src):
		if src is BossBase:
			if not (src as BossBase).is_ally:
				_last_hit_by_enemy = true
				_last_hit_source = src
		elif src.is_in_group("boss"):
			_last_hit_by_enemy = true
			_last_hit_source = src
	take_hit()


func take_knockback(_impulse: Vector2) -> void:
	pass


func apply_debuff(_id: String, _duration: float, _quiet: bool = true) -> bool:
	return false


func has_debuff(_id: String) -> bool:
	return false


func remove_debuff(_id: String) -> void:
	pass


func despawn() -> void:
	if _dead:
		return
	# 先发信号再置 _dead：玩家侧要靠“这面旗还在”数出五旗是否完整
	destroyed.emit(self, _last_hit_by_enemy, _last_hit_source)
	_dead = true
	is_dead = true
	remove_from_group("array_flag")
	remove_from_group("breakable_sword")
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(0.2, 0.2), 0.12)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.12)
	tw.tween_callback(queue_free)


## 柔边圆点贴图（投影用），与 SkillFx 的 dot_texture 同一套观感
var _dot_tex: Texture2D = null


func _dot_texture() -> Texture2D:
	if _dot_tex != null:
		return _dot_tex
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			img.set_pixel(x, y, Color(1, 1, 1, clampf(exp(-d * d * 3.2), 0.0, 1.0)))
	_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex
