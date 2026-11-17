class_name SkySword
extends StaticBody2D
## 插地剑 —— 剑客（boss_01_c）的两个转阶段演出共用的「场上剑」实体
##
## 三种模式：
##   FALLING  天剑阵的剑：从高空坠落到目标点，下落途中碰到玩家即造成伤害，落地后转 PLANTED
##   PLANTED  已插地：有碰撞（挡路）、可被玩家攻击一次击碎（加入组 breakable_sword）
##   TRIANGLE 三角封绝的剑：插在玩家身边连成三角形，无碰撞、不可破坏，由 BOSS 定时引爆
##
## 分层：collision_layer = 8（SKY_SWORD_LAYER），玩家 collision_mask 已含这一层
##   —— 不用 BOSS 的 layer 2，避免 BOSS 自己撞上、或与「boss」组的语义混淆
##
## 美术：SkinVisual + ArtDB.VISUALS["sky_sword"]，换图只改表（anchor_bottom 让剑底贴地）

## 天剑阵的剑所在物理层（玩家 collision_mask 需含此位）
const SKY_SWORD_LAYER := 8

enum Mode { FALLING = 0, PLANTED = 1, TRIANGLE = 2 }

## 模式：FALLING / PLANTED / TRIANGLE（默认从天而降）
@export var mode: int = Mode.FALLING

## 命中玩家造成的伤害（FALLING 用）
var damage: float = 20.0
var attack_kind: String = "physical_melee"
## 召唤者的伤害倍率（友军召唤物 = ally_damage_scale，普通 BOSS = 1.0）
## ⚠ 天剑阵是直接调 player.take_damage 的，走不到 BossBase.deal_damage_to()，
##   不乘这个系数的话，友军剑客的天剑吃不到强化加成（2026-10-21 用户报）
var ally_scale: float = 1.0
## 召唤者（剑客 BOSS），用于「只统计自己召唤的剑」
var source: Node = null

## 下落目标点（FALLING 生成时由 BOSS 指定；默认就是出生点）
var target_position: Vector2 = Vector2.ZERO
## 下落初速（像素/秒）—— 天剑阵的压迫感来源，0.5 秒左右落地
var fall_speed: float = 1150.0
## 下落起始高度（生成时把人拉到目标点上方这个高度）
const FALL_START_HEIGHT := 520.0
## 命中玩家的判定半径
const HIT_RADIUS := 30.0

var _landed: bool = false
var _dying: bool = false

@onready var skin: SkinVisual = $Visual/Skin
@onready var shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("sky_sword")
	if mode == Mode.PLANTED:
		add_to_group("breakable_sword")
	skin.visual_id = "sky_sword"
	skin.refresh()

	if mode == Mode.TRIANGLE:
		# 三角剑是纯演出：不挡路、不可打
		collision_layer = 0
		collision_mask = 0
		shape.set_deferred("disabled", true)
		return

	if mode == Mode.FALLING:
		# 还没落地时先关掉碰撞：坠落过程不该挡路（否则会把玩家锁在原地）
		shape.set_deferred("disabled", true)
		target_position = global_position
		global_position = target_position + Vector2(0.0, -FALL_START_HEIGHT)


func _physics_process(delta: float) -> void:
	if mode != Mode.FALLING or _landed:
		return
	# 下落：直线坠向目标点
	var step := fall_speed * delta
	var to_target: Vector2 = target_position - global_position
	if to_target.length() <= step:
		global_position = target_position
		_land()
		return
	global_position += to_target.normalized() * step
	# 下落途中碰到玩家就提前结算（剑还是会落地，只是不再造成第二次伤害）
	if _hit_player():
		_land()


## 下落途中是否碰到「该被打的人」（只判一次，命中后由 _land 收尾）
## 对局棋子放出的剑：棋盘上没有 player 节点，原来那句 `get_first_node_in_group("player")`
## 永远返回 null → 天剑阵整招空放。改成打对方队伍的棋子。
func _hit_player() -> bool:
	if _landed:
		return false
	var team := BossBase.unit_team(source) if is_instance_valid(source) else -1
	var candidates: Array = []
	if team >= 0:
		for raw in get_tree().get_nodes_in_group(BossBase.MATCH_PIECE_GROUP):
			if is_instance_valid(raw) and BossBase.unit_team(raw) != team \
					and not BossBase.is_unit_dead(raw):
				candidates.append(raw)
	else:
		var player := get_tree().get_first_node_in_group("player")
		if player != null and player is Node2D and not BossBase.is_unit_dead(player):
			candidates.append(player)
	for v in candidates:
		var n := v as Node2D
		if n == null or not n.has_method("take_damage"):
			continue
		if n.global_position.distance_to(global_position) > HIT_RADIUS:
			continue
		# 签名不能混：BOSS 版是 (amount, source, damage_kind, element, from_projectile)，
		# 玩家版是 (amount, attack_kind, source)。塞错参数就是类型转换错误并中断战斗。
		if v is BossBase:
			n.take_damage(damage * ally_scale,
					source if is_instance_valid(source) else null,
					"elemental" if attack_kind == "elemental" else "physical", "", true)
		else:
			n.take_damage(damage * ally_scale, attack_kind, self)
		return true
	return false


## 落地：转为「已插地」状态（有碰撞、可被击碎）
func _land() -> void:
	if _landed:
		return
	_landed = true
	mode = Mode.PLANTED
	remove_from_group("breakable_sword")
	add_to_group("breakable_sword")
	collision_layer = SKY_SWORD_LAYER
	if shape != null:
		shape.set_deferred("disabled", false)
	# 落地冲击特效（无贴图时是程序化闪光）
	FxPlayer.spawn(self, "fx_sky_sword_fall", {
		"position": global_position + Vector2(0.0, -8.0),
		"lifetime": 0.3,
	})


## 玩家攻击命中（由 player._damage_bosses_in_shape 调用来）—— 一击即碎
func take_hit(_dmg: float) -> void:
	if _dying or mode == Mode.TRIANGLE:
		return
	_dying = true
	FxPlayer.spawn(self, "fx_sky_sword_break", {
		"position": global_position + Vector2(0.0, -20.0),
		"lifetime": 0.22,
	})
	queue_free()


## 三角封绝引爆 / 天剑阵结算消散：统一消失入口
func dismiss() -> void:
	if _dying:
		return
	_dying = true
	FxPlayer.spawn(self, "fx_sky_sword_break", {
		"position": global_position + Vector2(0.0, -20.0),
		"lifetime": 0.22,
	})
	queue_free()


## 是否已被玩家打掉 / 已消散（BOSS 统计剩余数量时用）
func is_gone() -> bool:
	return _dying or not is_inside_tree()
