extends SceneTree
## 虎妖判定框自检：把本体和碰撞圆画在一起拍照，量「圆到底盖没盖住身体」。
##
## 为什么需要：boss.tscn 的受击框**同时**是物理碰撞框，也是玩家所有招式的命中面
## （player.gd 逐个受击球判定）。它比美术大 → 隔着空气也能砍中；比美术小 → 砍到不掉血。
## 只靠读数字容易偏，这里直接出图。
##
## 用法：godot --path . --resolution 1280x720 --script tools/capture_boss_box.gd

const WARMUP := 20
const SHOTS := [
	{"tag": "right", "face": Vector2.RIGHT, "debug": true},
	{"tag": "left", "face": Vector2.LEFT, "debug": true},
	{"tag": "clean", "face": Vector2.RIGHT, "debug": false},
]

var _frame := 0
var _slot := -1
var _boss: Node2D


func _initialize() -> void:
	print("\n########## 虎妖判定框 ##########")


func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 1:
		# 属性在 SceneTree（本脚本自身）上，不在 Window 上
		debug_collisions_hint = true
		var bg := ColorRect.new()
		bg.color = Color(0.10, 0.11, 0.09, 1.0)
		bg.size = Vector2(4000, 4000)
		bg.position = Vector2(-2000, -2000)
		bg.z_index = -100
		root.add_child(bg)
		_boss = (load("res://scenes/boss/boss.tscn") as PackedScene).instantiate()
		_boss.position = Vector2.ZERO
		root.add_child(_boss)
		var cam := Camera2D.new()
		cam.position = Vector2(0, -60)
		cam.zoom = Vector2(2.0, 2.0)
		root.add_child(cam)
		cam.make_current()
		return false
	if _frame < WARMUP:
		return false
	var rel := _frame - WARMUP
	var per := 12
	var idx := rel / per
	if idx >= SHOTS.size():
		print("################ 完毕 ################")
		return true
	var k := rel % per
	if k == 0:
		_slot = idx
		debug_collisions_hint = bool(SHOTS[idx].get("debug", true))
		if _boss.has_method("_set_facing"):
			_boss.call("_set_facing", SHOTS[idx]["face"])
	if k == per - 1:
		var img := root.get_texture().get_image()
		if img != null:
			img.save_png("res://output/boss_box_%s.png" % SHOTS[idx]["tag"])
		if _boss.has_method("hit_spheres"):
			print("%s 朝向 %s  受击球 %s  外接半径 %.1f"
				% [SHOTS[idx]["tag"], SHOTS[idx]["face"], _boss.call("hit_spheres"), _boss.call("hit_radius")])
	return false
