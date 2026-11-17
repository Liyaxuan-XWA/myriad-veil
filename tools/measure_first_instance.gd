extends Node
## 第一次实例化贵在哪：instantiate / _ready / 首帧上屏 三段拆开
##
## 上一轮量到"每只场景第一次 instantiate 后 add_child 要 200-250ms，第二次只要 3ms"。
## 三种可能的成本位置，修法完全不同：
##   在 instantiate ⇒ 节点树复制本身贵（场景太大）→ 只能预建或减节点
##   在 add_child(_ready) ⇒ 脚本在搭 rig / 特效池 / 血条 → 可以延后或懒建
##   在首帧 ⇒ 纹理上传 / 着色器编译 → 只能预热，或走线程加载
func _ready() -> void:
	print("\n########## 首实例成本落在哪一段 ##########")
	var ids: Array = ["boss_01", "boss_01_c", "boss_02_b", "world_core_shihou", "boss_04_c"]
	print("%-22s %10s %10s %10s %10s" % ["boss", "instantiate", "add_child", "1st frame", "2nd 全套"])
	for id in ids:
		var packed := load(WorldDB.get_boss_scene(id)) as PackedScene
		var a := Time.get_ticks_usec()
		var n := packed.instantiate() as Node2D
		var b := Time.get_ticks_usec()
		add_child(n)
		var c := Time.get_ticks_usec()
		await get_tree().process_frame
		var d := Time.get_ticks_usec()
		# 第二次：同场景再建一只，看还剩多少
		var e0 := Time.get_ticks_usec()
		var n2 := packed.instantiate() as Node2D
		add_child(n2)
		var e := Time.get_ticks_usec()
		await get_tree().process_frame
		var f := Time.get_ticks_usec()
		print("%-22s %10.1f %10.1f %10.1f %10.1f" % [
			id, _ms(a, b), _ms(b, c), _ms(c, d), _ms(e0, f)])
		n.queue_free()
		n2.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame

	# 纹理是不是已经进内存了？如果 load 阶段纹理就在，首帧那笔就是上传/编译
	print("\n── 场景里到底挂了多少纹理 ──")
	for id in ids:
		var packed2 := load(WorldDB.get_boss_scene(id)) as PackedScene
		print("  %-22s 状态里的节点数=%d" % [id, _count_nodes(packed2)])
	print("\n── 单独量一次「纹理首次上传」──")
	var p := load(WorldDB.get_boss_scene("boss_01")) as PackedScene
	var n3 := p.instantiate() as Node2D
	add_child(n3)
	await get_tree().process_frame
	var g := Time.get_ticks_usec()
	# 已经热了：再建一只只测 add_child + 首帧
	var n4 := p.instantiate() as Node2D
	var h := Time.get_ticks_usec()
	add_child(n4)
	var i := Time.get_ticks_usec()
	await get_tree().process_frame
	var j := Time.get_ticks_usec()
	print("  热态 instantiate=%.1f add_child=%.1f 首帧=%.1f" % [
		_ms(g, h), _ms(h, i), _ms(i, j)])
	get_tree().quit(0)


func _ms(a: int, b: int) -> float:
	return float(b - a) / 1000.0


func _count_nodes(packed: PackedScene) -> int:
	var s := packed.get_state()
	return s.get_node_count()
