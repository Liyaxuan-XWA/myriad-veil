extends Node
## 首实例的贵成本是"每只各自一次"还是"全局一次"？
##
## 如果是全局一次（比如某个共享的图集/字体/特效目录第一次构建），
## 那么只要**任意一只**先付过，后面 11 只都便宜 ⇒ 预热方案极小。
## 如果是每只各自一次（各自的贴图扫描），就得逐只预热 ⇒ 必须找不卡的地方付。
## 做法：按固定顺序把 12 只**第一次**全部进树，把每一只的 add_child 打出来。
func _ready() -> void:
	print("\n########## 首实例成本：全局一次 or 每只一次 ##########")
	var ids := _twelve()
	print("  顺序：%s" % str(ids))
	var nodes: Array = []
	var t_all := Time.get_ticks_usec()
	for i in ids.size():
		var a := Time.get_ticks_usec()
		var packed := load(WorldDB.get_boss_scene(ids[i])) as PackedScene
		var b := Time.get_ticks_usec()
		var n := packed.instantiate() as Node2D
		add_child(n)
		nodes.append(n)
		var c := Time.get_ticks_usec()
		print("  #%2d %-20s load=%7.1f  add_child(首)=%7.1f" % [
			i, ids[i], _ms(a, b), _ms(b, c)])
	var d := Time.get_ticks_usec()
	await get_tree().process_frame
	var e := Time.get_ticks_usec()
	print("  12 只首实例合计 %.1f ms（load+进树 %.1f，首帧 %.1f）" % [
		_ms(t_all, e), _ms(t_all, d), _ms(d, e)])

	# 现在全部暖过了：拆掉再建同样 12 只，看还剩多少
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	nodes.clear()
	await get_tree().process_frame
	await get_tree().process_frame

	print("\n── 全暖之后的第二次 ──")
	var t2 := Time.get_ticks_usec()
	for i in ids.size():
		var n2 := (load(WorldDB.get_boss_scene(ids[i])) as PackedScene).instantiate() as Node2D
		add_child(n2)
		nodes.append(n2)
	var t3 := Time.get_ticks_usec()
	await get_tree().process_frame
	var t4 := Time.get_ticks_usec()
	print("  12 只热实例合计 %.1f ms（进树 %.1f，首帧 %.1f）⇒ 一帧 %.1f ms" % [
		_ms(t2, t4), _ms(t2, t3), _ms(t3, t4), _ms(t2, t3)])
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	get_tree().quit(0)


func _ms(a: int, b: int) -> float:
	return float(b - a) / 1000.0


func _twelve() -> Array:
	var out: Array = []
	for id in MatchLevelDeck.deck_for(2):
		out.append(String(id))
	for id in MatchLevelDeck.deck_for(9):
		out.append(String(id))
	return out
