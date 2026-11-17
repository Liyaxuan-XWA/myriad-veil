extends Node
## 首实例那 240-420ms 是脚本 _ready 的活，还是引擎侧的纹理上传/首次绘制？
##
## 这决定预热方案能不能成立：
##   若是脚本 _ready → 只有"真的建一只"才能暖它，预热必须付全额
##   若是纹理上传/首次绘制 → 可以先**不可见**挂上去暖，玩家完全看不出
## 对照三组：
##   A 正常 add_child（会画）
##   B add_child 前先 visible=false（进树但不绘制）
##   C 只 load + instantiate（不进树）
## 每组都用一个**此前没建过**的 boss，避免热态污染。
func _ready() -> void:
	print("\n########## 首实例成本：脚本 vs 上传 ##########")
	# 用没在别的实验里进过树的卡：40 关与 23 关的卡组
	var cold_a := _fresh_ids(40, 3)
	var cold_b := _fresh_ids(23, 3)
	var cold_c := _fresh_ids(11, 3)

	print("\n── A 正常进树（会绘制）──")
	await _run(cold_a, 0)
	print("\n── B 进树但 visible=false（不绘制）──")
	await _run(cold_b, 1)
	print("\n── C 只 load+instantiate（不进树）──")
	await _run(cold_c, 2)
	get_tree().quit(0)


func _ms(a: int, b: int) -> float:
	return float(b - a) / 1000.0


func _fresh_ids(level: int, want: int) -> Array:
	var out: Array = []
	for id in MatchLevelDeck.deck_for(level):
		out.append(String(id))
		if out.size() >= want:
			break
	return out


func _run(ids: Array, mode: int) -> void:
	var nodes: Array = []
	for id in ids:
		var a := Time.get_ticks_usec()
		var packed := load(WorldDB.get_boss_scene(id)) as PackedScene
		var b := Time.get_ticks_usec()
		var n := packed.instantiate() as Node2D
		var c := Time.get_ticks_usec()
		var d := c
		if mode != 2:
			if mode == 1:
				n.visible = false
			add_child(n)
			nodes.append(n)
			d = Time.get_ticks_usec()
		await get_tree().process_frame
		var e := Time.get_ticks_usec()
		print("  %-20s load=%7.1f inst=%6.1f add=%7.1f 首帧=%7.1f" % [
			id, _ms(a, b), _ms(b, c), _ms(c, d), _ms(d, e)])
		for n2 in nodes:
			if is_instance_valid(n2):
				n2.queue_free()
		nodes.clear()
		await get_tree().process_frame
		await get_tree().process_frame
