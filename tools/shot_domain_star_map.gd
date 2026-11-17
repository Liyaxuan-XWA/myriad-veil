extends Node
## 位面星图（旋转木马）实机尺寸截图 + 窗口化点击回归
## 用法：godot --path . --windowed --resolution 1280x720 tools/shot_domain_star_map.tscn -- --no-save
## 点击这一段不能挪进无头探针：合成鼠标只有窗口化才走得到真正的 GUI 拾取。

var _entered: Array[String] = []


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _click(at: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	get_viewport().push_input(m)
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.button_mask = MOUSE_BUTTON_MASK_LEFT
	d.position = at
	d.global_position = at
	get_viewport().push_input(d)
	await get_tree().process_frame
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = at
	u.global_position = at
	get_viewport().push_input(u)
	await get_tree().process_frame
	await get_tree().process_frame


func _report(label: String, ok: bool, detail: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + label + "  " + detail)


func _settle(map: Node) -> void:
	for _i in 90:
		await get_tree().process_frame
		if map._at_rest():
			break
	for _i in 4:
		await get_tree().process_frame


func _ready() -> void:
	var p = DomainPanel.new()
	add_child(p)
	for i in 10:
		await get_tree().process_frame
	p.open()
	for i in 14:
		await get_tree().process_frame
	await _shot("star_map_before_select.png")

	var map: Node = _find_star_map(p)
	if map == null:
		print("!! 找不到星图节点")
		get_tree().quit(1)
		return
	print("MAP size=", map.size)
	_dump(map, "第 0 转")

	map._set_focus("domain_01")
	for i in 8:
		await get_tree().process_frame
	await _shot("star_map_domain_01.png")

	map._turn(1)
	await _settle(map)
	_dump(map, "第 1 转")
	await _shot("star_map_turn_1.png")

	map._turn(1)
	await _settle(map)
	_dump(map, "第 2 转")
	await _shot("star_map_turn_2.png")

	map._turn(-2)
	await _settle(map)
	_dump(map, "回滑两格")
	await _shot("star_map_turn_back.png")

	# ---------- 点击回归：门的可点性挪到手动 release 判定上了，必须真点一次 ----------
	# 顺序不能反：点前排门会 emit gate_entered，面板随即换屏、星图节点当场被 free，
	# 再拿 map 去取第二个门就是「Invalid access on a previously freed」。
	map.connect("gate_entered", func(did: String): _entered.append(did))
	var center_gate: Dictionary = {}
	var depth_gate: Dictionary = {}
	for g in map._gates:
		if bool(g.in_depth):
			depth_gate = g
		elif map._slot_pos(g) < 0.5:
			center_gate = g
	if not depth_gate.is_empty():
		var sel_before := String(map._selected_id)
		await _click((depth_gate.center as Vector2) + map.global_position)
		_report("点深处那格不进界、不改选中态、也不报错",
			_entered.is_empty() and String(map._selected_id) == sel_before,
			"entered=%s selected=%s->%s" % [str(_entered), sel_before, map._selected_id])
	if not center_gate.is_empty():
		await _click((center_gate.center as Vector2) + map.global_position)
		_report("点前排中央那格要真的进界", _entered.size() == 1,
			"entered=%s 期望=%s" % [str(_entered), center_gate.domain_id])
	get_tree().quit(0)


func _dump(map: Node, tag: String) -> void:
	print("--- %s ---" % tag)
	for g in map._gates:
		print("  %s slot=%.2f center=%s r=%.1f dim=%.2f depth=%s plaque=%s hit=%s" % [
			g.domain_id, map._slot_pos(g), g.center, g.radius, g.dim,
			g.in_depth, g.plaque.position, g.hit.mouse_filter])


func _find_star_map(node: Node) -> Node:
	if node.get_script() != null and String(node.get_script().resource_path).ends_with("domain_star_map.gd"):
		return node
	for c in node.get_children():
		var r := _find_star_map(c)
		if r != null:
			return r
	return null
