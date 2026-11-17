extends Node
## 执烛剪影量测（2026-11-02 换外部美术之后）
##
## 受击球 / 碰撞体贴的是**屏幕坐标下的人形**，而 rig 画布中心 ≠ BOSS 原点：
## 换一张图，画布中心到脚底的距离就变了，球会整批偏掉。所以这里把三件事打出来：
##   ① Visual 的实际矩形（相对 BOSS 原点）② head_top_y / feet_offset ③ 每颗受击球
## 用法：godot --headless --path . res://tools/measure_zhizhu_visual.tscn -- --no-save

const BOSS_SCENE := "res://scenes/boss/domain_boss_04_b.tscn"


func _ready() -> void:
	CharacterData.current_realm = "元婴"
	CharacterData.realm_stage = 1
	await get_tree().process_frame
	var boss: Node2D = (load(BOSS_SCENE) as PackedScene).instantiate()
	add_child(boss)
	for i in range(6):
		await get_tree().process_frame
	var skin: Node = boss.get_node_or_null("Visual/Skin")
	var rect: Rect2 = skin.get("visual_rect") if skin != null else Rect2()
	print("visual_rect  x %.1f..%.1f   y %.1f..%.1f" % [rect.position.x, rect.end.x,
			rect.position.y, rect.end.y])
	print("feet_offset  %.1f" % boss.call("feet_offset"))
	print("head_top_y   %.1f" % boss.call("head_top_y"))
	print("height       %.1f" % (float(boss.call("feet_offset")) - float(boss.call("head_top_y"))))
	## 逐个数一下 Visual 下的 CanvasItem：head_top_y 取的是「贴图满高的一半」，
	## 画布上任何一圈透明留白都会被它算成身体的一部分，血条因此飘在头顶外面。
	var root: Node = boss.get_node_or_null("Visual")
	for n in root.find_children("*", "CanvasItem", true, false):
		var ci := n as CanvasItem
		if ci == null or not ci.is_visible_in_tree():
			continue
		var half := 0.0
		var spr := n as Sprite2D
		if spr != null and spr.texture != null:
			half = float(spr.texture.get_height()) * 0.5
		else:
			continue
		var p := boss.to_local((n as Node2D).to_global(Vector2(0.0, -half)))
		print("  canvas-item %-24s top %7.1f  (贴图高 %d)" % [
			String(n.get_path()), p.y, int(spr.texture.get_height())])
	for s in boss.call("hit_spheres"):
		print("  sphere  x %6.1f  y %6.1f  r %5.1f   -> 纵向 %.1f..%.1f" % [
			s.x, s.y, s.z, s.y - s.z, s.y + s.z])
	get_tree().quit()
