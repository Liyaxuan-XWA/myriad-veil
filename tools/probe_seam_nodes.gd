extends Node

var _world: Node

func _ready() -> void:
	SecretWorldDB.pending_spawn_region = SecretWorldDB.REGION_YUANYING
	var s := load("res://scenes/world/secret_world.tscn") as PackedScene
	_world = s.instantiate()
	add_child(_world)

func _process(_d: float) -> void:
	if Engine.get_process_frames() < 8:
		return
	var p := _world.get_node_or_null("Player") as Node2D
	var cam := p.get_node_or_null("Camera2D") as Camera2D if p else null
	print("player=", p.global_position if p else "?", " cam=", cam.global_position if cam else "?", " zoom=", cam.zoom if cam else "?")
	var g := _world.get_node_or_null("Ground")
	for c in g.get_children():
		var cr := c as ColorRect
		if cr == null:
			continue
		if not ("Seam" in cr.name or "Terrain" in cr.name):
			continue
		var tex := ""
		var mat := cr.material as ShaderMaterial
		if mat != null:
			var t = mat.get_shader_parameter("band_tex")
			if t is Texture2D:
				tex = (t as Texture2D).resource_path
			var rc = mat.get_shader_parameter("repeat_count")
			print(cr.name, " pos=", cr.position, " size=", cr.size, " z=", cr.z_index,
				" tex=", tex.get_file(), " rep=", rc,
				" fades=", mat.get_shader_parameter("end_fade_low"), ",", mat.get_shader_parameter("end_fade_high"),
				" carve=", mat.get_shader_parameter("carve_low"), ",", mat.get_shader_parameter("carve_high"))
	get_tree().quit(0)
