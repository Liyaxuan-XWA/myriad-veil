class_name StagPlate
extends Node2D
## 云隐苍角的苔甲片：悬在角侧的三片苔石护甲。
## 玩家攻击命中三次碎一片；三片尽碎，BOSS 的护甲减伤消失。
## 不进 "boss" 组，只进 "breakable_sword"，所以玩家招式会像打旗一样命中它。

signal broken(plate: StagPlate)

const HITS_TO_BREAK := 3
const PLATE_RADIUS := 34.0
const PLATE_TEXTURE: Texture2D = preload("res://assets/effects/skills/stag_plate.png")

var hits_left: int = HITS_TO_BREAK
var hit_radius: float = PLATE_RADIUS
## 挂点序号：破掉一片后其余片不会跳位
var slot: int = 0
var _dead := false
var _flash: Tween = null
var _base_scale := Vector2.ONE
var _sprite: Sprite2D


func setup() -> void:
	add_to_group("breakable_sword")
	z_index = 5
	# 影
	var shadow := Polygon2D.new()
	shadow.polygon = PackedVector2Array([
		Vector2(-22, 30), Vector2(-12, 24), Vector2(12, 24), Vector2(22, 30),
		Vector2(14, 36), Vector2(-14, 36),
	])
	shadow.color = Color(0.02, 0.04, 0.03, 0.34)
	add_child(shadow)
	# 苔石甲片：生图抠好的竖片，蓝符纹自带冷光
	_sprite = Sprite2D.new()
	_sprite.texture = PLATE_TEXTURE
	_sprite.centered = true
	_sprite.position = Vector2(0, -6)
	_sprite.scale = Vector2.ONE * (88.0 / float(PLATE_TEXTURE.get_height()))
	_sprite.flip_h = slot == 1
	add_child(_sprite)
	_base_scale = scale


func hit_point() -> Vector2:
	return global_position + Vector2(0, -10)


## 弹反震碎：不按剩余次数，直接碎一片（角撞/角扫被弹开时用）
func shatter() -> void:
	if _dead:
		return
	hits_left = 0
	_break()


func take_hit(_dmg: float = 0.0) -> void:
	if _dead:
		return
	hits_left -= 1
	if _flash != null and _flash.is_valid():
		_flash.kill()
	modulate = Color.WHITE
	scale = _base_scale * 1.16
	_flash = create_tween()
	_flash.tween_property(self, "scale", _base_scale, 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if hits_left <= 0:
		_break()


func _break() -> void:
	if _dead:
		return
	_dead = true
	var shots := [
		Vector2(-24, -10), Vector2(8, -22), Vector2(18, 14), Vector2(-8, 20),
	]
	for i in 4:
		var shard := Sprite2D.new()
		shard.texture = PLATE_TEXTURE
		shard.position = Vector2(0, -6)
		shard.scale = _sprite.scale * 0.28
		shard.rotation = randf_range(-0.35, 0.35)
		add_child(shard)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(shard, "position", Vector2(0, -6) + shots[i], 0.22)
		tw.tween_property(shard, "rotation", randf_range(-1.3, 1.3), 0.22)
		tw.tween_property(shard, "modulate:a", 0.0, 0.22)
	broken.emit(self)
	queue_free()
