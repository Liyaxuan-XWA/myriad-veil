extends Node
## 复现「踏入大陆」入口：区域表 → 区域面板 → 世界页 → 踏入按钮的连接与启用状态。

func _ready() -> void:
	print("\n########## 进入大陆入口探针 ##########")
	var loaded := SaveManager.load_latest_auto()
	print("SAVE loaded=", loaded, " realm=", CharacterData.current_realm,
		" secret_world_keys=", CharacterData.secret_world.keys())
	for r in SecretWorldDB.REGIONS:
		print("REGION %-22s unlocked=%s" % [String(r.get("region_id", "")),
			str(bool(r.get("unlocked", false)))])

	var panel := DomainPanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel._tab = "world"
	panel._refresh_content()
	await get_tree().process_frame
	await get_tree().process_frame

	var board: Node = null
	for c in panel._body.get_children():
		if c.get_script() == load("res://scripts/ui/facility/world_region_board.gd"):
			board = c
	print("BOARD built=", board != null)
	if board == null:
		get_tree().quit(1)
		return
	var enter: Button = board._enter
	print("SELECTED=", board._selected_id)
	print("ENTER text=", enter.text, " disabled=", enter.disabled)
	print("SIGNAL connections=", board.get_signal_connection_list("enter_world_requested").size())
	print("DETAIL tooltip=", enter.tooltip_text)

	# 逐个区域点选，确认每个区域都能解锁并给出有效 region_id
	var all_ok := true
	for r in SecretWorldDB.REGIONS:
		var rid := String(r.get("region_id", ""))
		board._on_region_pressed(rid)
		await get_tree().process_frame
		var want_enabled := bool(r.get("unlocked", false))
		var has := enter.text.begins_with("踏入")
		var ok := (enter.disabled != want_enabled) and (has == want_enabled)
		if not ok:
			all_ok = false
		print("  %-22s selected=%-22s enter='%s' disabled=%s %s" % [rid,
			board._selected_id, enter.text, str(enter.disabled), "OK" if ok else "MISMATCH"])
	print("ALL_OK=", all_ok)
	# 真走一次踏入：检查器挂 root，切场景后仍存活
	var keeper := Node.new()
	keeper.set_script(load("res://tools/enter_world_checker.gd"))
	get_tree().root.add_child(keeper)
	panel._on_enter_world("world_lianqi")
