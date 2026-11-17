extends Node
## 大世界里「一剑开天 / 万剑归宗」特效诊断（临时）
## godot --headless --path . res://tools/probe_world_skill_fx.tscn -- --no-save

const WORLD := "res://scenes/world/secret_world.tscn"

func _ready() -> void:
	var w: Node = (load(WORLD) as PackedScene).instantiate()
	add_child(w)
	for i in 8:
		await get_tree().process_frame
	var p: Node2D = w.get("player")
	p.set_physics_process(false)
	p.set("sword_intent", p.call("_sword_intent_max"))
	print("intent=", p.get("sword_intent"), "/", p.call("_sword_intent_max"),
		" player_z=", p.z_index, " parent=", p.get_parent().name, " parent_z=", (p.get_parent() as Node2D).z_index)
	print("content_z=", (w.get_node("Content") as Node2D).z_index,
		" ground_z=", (w.get_node("Ground") as Node2D).z_index)
	p.call("_cast_skill", "skill_sword_heaven")
	for i in 4:
		await get_tree().process_frame
	var names: Array = []
	for n in p.get_children():
		names.append("%s(%s z=%d vis=%s)" % [n.name, n.get_class(),
			(n.get("z_index") if n.get("z_index") != null else -999),
			(n as CanvasItem).visible if n is CanvasItem else "?"])
	print("施法后 player 子节点: ", names)
	var fx: Node = null
	for n in p.get_children():
		if n is SwordHeavenFx:
			fx = n
	if fx != null:
		print("heaven fx pos=", fx.position, " visible=", fx.visible,
			" children=", fx.get_child_count())
	for i in 20:
		await get_tree().process_frame
	print("20 帧后 heaven 还在吗=", fx != null and is_instance_valid(fx))
	p.call("_cast_skill", "skill_sword_myriad")
	for i in 3:
		await get_tree().process_frame
	var projs := 0
	for n in p.get_children():
		if n.get("skill_id") != null:
			projs += 1
	print("myriad 投射物=", projs)
	get_tree().quit(0)
