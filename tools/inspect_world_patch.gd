extends Node2D
## 临时排查：练气东缘 (4867..5321, 1500..1680) 那块硬边棕色矩形是谁画的。
## 用法：godot --headless --path . tools/inspect_world_patch.tscn

const TARGET := Vector2(5100.0, 1600.0)


func _ready() -> void:
	SecretWorldDB.pending_spawn_region = SecretWorldDB.REGION_LIANQI
	var s := load("res://scenes/world/secret_world.tscn") as PackedScene
	var world := s.instantiate()
	add_child(world)
	for i in range(12):
		await get_tree().process_frame

	_walk(world, world)
	print("=== 大贴图节点 ===")
	_walk_big(world, world)
	get_tree().quit(0)


func _describe(n: Node) -> String:
	var parts: Array = [String(n.name), n.get_class()]
	if n is Node2D:
		parts.append("pos=" + str((n as Node2D).global_position))
	if n is CanvasItem:
		parts.append("z=" + str((n as CanvasItem).z_index) + " vis=" + str((n as CanvasItem).visible))
	if n is Sprite2D:
		var sp := n as Sprite2D
		var t := sp.texture
		parts.append("tex=" + (t.resource_path if t != null else "null"))
		parts.append("centered=" + str(sp.centered) + " scale=" + str(sp.scale))
		if t != null:
			parts.append("size=" + str(t.get_size()) + " off=" + str(sp.offset))
	if n is ColorRect:
		var cr := n as ColorRect
		parts.append("rect=" + str(cr.position) + " " + str(cr.size))
	return "  ".join(parts)


func _walk(n: Node, world: Node) -> void:
	if n is Node2D:
		var p := (n as Node2D).global_position
		if p.distance_to(TARGET) < 900.0 and n != world:
			print(_describe(n))
	for c in n.get_children():
		_walk(c, world)


func _walk_big(n: Node, world: Node) -> void:
	if n is Sprite2D:
		var sp := n as Sprite2D
		if sp.texture != null:
			var sz := sp.texture.get_size() * sp.scale.abs()
			if sz.x > 220.0 or sz.y > 220.0:
				print(_describe(n), "  world=", sp.get_global_transform().origin)
	for c in n.get_children():
		_walk_big(c, world)
