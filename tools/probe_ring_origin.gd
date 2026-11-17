extends Node

func _ready() -> void:
	SecretWorldDB.pending_spawn_region = SecretWorldDB.REGION_JIEDAN
	var w = (load("res://scenes/world/secret_world.tscn") as PackedScene).instantiate()
	add_child(w)
	await get_tree().create_timer(1.2, true, false, true).timeout
	print("player ", w.player.global_position)
	_dump(w, w.player.global_position, w)
	get_tree().quit()

func _dump(n: Node, p: Vector2, w: Node) -> void:
	if n is Node2D and n.is_visible_in_tree():
		var gp: Vector2 = (n as Node2D).global_position
		var dist := gp.distance_to(p)
		if dist < 520.0 and n != w.player:
			var scr := ""
			var s = n.get_script()
			if s != null:
				scr = s.resource_path
			if scr != "" or n is FxPlayer or String(n.name).contains("Fx"):
				print("NODE ", n.get_path(), " script=", scr, " pos=", gp, " dist=", int(dist))
	for c in n.get_children():
		_dump(c, p, w)
