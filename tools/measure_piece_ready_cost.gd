extends Node
## 每只棋子**独立**的 _ready 成本（排除上一份还没释放造成的累积）
##
## 上一轮量到"全暖之后 12 只仍 785ms"，但那是 queue_free 延迟 + 12 只同时在树里
## 互相扫组的混合结果，不能直接当成 _ready 的单价。
## 这一轮逐个量：建 1 只 → 计时 → **立即 free()**（不是 queue_free）→ 等一帧 → 下一只。
## 三种情形分开：
##   ① 单只独立成本（场上只有它）
##   ② 累积成本（越建越多，看是否非线性）
##   ③ 建完就 free 的净开销（预热一只到底要不要付全程）
func _ready() -> void:
	print("\n########## 棋子 _ready 单价 ##########")
	var ids := _twelve()
	for id in ids:
		load(WorldDB.get_boss_scene(id))  # 先全部预热到内存

	print("\n── ① 单只独立（建→计→立即 free）──")
	var solo: Array = []
	for id in ids:
		var a := Time.get_ticks_usec()
		var n := (load(WorldDB.get_boss_scene(id)) as PackedScene).instantiate() as Node2D
		add_child(n)
		var b := Time.get_ticks_usec()
		solo.append(_ms(a, b))
		n.free()
		await get_tree().process_frame
	for i in ids.size():
		print("  %-20s %7.1f ms" % [ids[i], solo[i]])
	print("  合计 %.1f ms，均值 %.1f ms" % [_sum(solo), _sum(solo) / ids.size()])

	print("\n── ② 累积（12 只同时在树里，逐个计时）──")
	var acc: Array = []
	var nodes: Array = []
	for id in ids:
		var c := Time.get_ticks_usec()
		var m := (load(WorldDB.get_boss_scene(id)) as PackedScene).instantiate() as Node2D
		add_child(m)
		var d := Time.get_ticks_usec()
		acc.append(_ms(c, d))
		nodes.append(m)
	for i in ids.size():
		print("  第 %2d 只 %-20s %7.1f ms" % [i + 1, ids[i], acc[i]])
	print("  合计 %.1f ms" % _sum(acc))
	await get_tree().process_frame
	var peak := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	print("  该帧 process 峰值 = %.1f ms" % peak)
	for n in nodes:
		n.free()
	nodes.clear()
	await get_tree().process_frame

	print("\n── ③ 预热一只再立刻拆掉，要付多少 ──")
	for id in [ids[2], ids[5]]:
		var e := Time.get_ticks_usec()
		var p := (load(WorldDB.get_boss_scene(id)) as PackedScene).instantiate() as Node2D
		add_child(p)
		await get_tree().process_frame
		var f := Time.get_ticks_usec()
		p.free()
		var g := Time.get_ticks_usec()
		print("  %-20s 预热(含一帧)=%7.1f ms  free=%6.1f ms" % [id, _ms(e, f), _ms(f, g)])
		# 预热过之后，真正上场要多少
		var h := Time.get_ticks_usec()
		var q := (load(WorldDB.get_boss_scene(id)) as PackedScene).instantiate() as Node2D
		add_child(q)
		var i := Time.get_ticks_usec()
		print("  %-20s ⇒ 之后真正进树只花 %7.1f ms" % [id, _ms(h, i)])
		q.free()
		await get_tree().process_frame
	get_tree().quit(0)


func _ms(a: int, b: int) -> float:
	return float(b - a) / 1000.0


func _sum(list: Array) -> float:
	var t := 0.0
	for v in list:
		t += float(v)
	return t


func _twelve() -> Array:
	var out: Array = []
	for id in MatchLevelDeck.deck_for(2):
		out.append(String(id))
	for id in MatchLevelDeck.deck_for(9):
		out.append(String(id))
	return out
