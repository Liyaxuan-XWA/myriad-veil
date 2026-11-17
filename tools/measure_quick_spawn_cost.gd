extends Node
## 快速模式「开战」的耗时拆解
##
## 现象：点开战要一次生成 12 只真 BOSS，明显卡顿。但"卡"可以出在四个不同地方，
## 修法互不相同，所以先分段量：
##   ① 冷 load(scene)   —— 首次加载要读 .import、上传纹理
##   ② instantiate()    —— 节点树复制
##   ③ add_child()      —— 触发 _ready：rig 搭建、特效池、受击球、血条、configure()
##   ④ 首帧             —— 动画求值 + 物理注册 + 纹理首次上屏
## 只报"总共多少毫秒"没法决策。全部走**真实路径** `MatchAdapter.spawn_piece`
## （四位核心是 WorldEnemy，还要多跑一次 `configure()`，不能拿普通 BOSS 代替）。
##
## 用法：godot --headless --path . res://tools/measure_quick_spawn_cost.tscn -- --no-save

var _nodes: Array = []


func _ms(a: int, b: int) -> float:
	return float(b - a) / 1000.0


func _ready() -> void:
	print("\n########## 开战 12 只同帧 · 耗时拆解 ##########")
	await _cold_load()
	await _twelve_in_one_frame()
	await _spread_over_frames()
	await _clear_all()
	get_tree().quit(0)


func _scene_of(boss_id: String) -> String:
	var region := MatchDB.core_region_id(boss_id)
	if region != "":
		var cfg: Dictionary = SecretWorldDB.get_core_boss(region)
		var p := String(cfg.get("scene", ""))
		if p != "" and ResourceLoader.exists(p):
			return p
		return "res://scenes/world/world_enemy.tscn"
	return WorldDB.get_boss_scene(boss_id)


## ① 冷 load：把 16 张卡的场景**第一次**读进内存要花多少
##   这决定"预载"能省掉多少 —— 如果大头在这，进关时就该把资源拉好。
func _cold_load() -> void:
	print("\n── ① 冷 load（每张卡第一次读）──")
	var t0 := Time.get_ticks_usec()
	var per: Array = []
	for id in MatchDB.CARD_POOL:
		var a := Time.get_ticks_usec()
		var packed := load(_scene_of(String(id))) as PackedScene
		var b := Time.get_ticks_usec()
		per.append([String(id), _ms(a, b)])
	var t1 := Time.get_ticks_usec()
	var sum := 0.0
	for r in per:
		sum += float(r[1])
		print("  %-22s %8.1f ms" % [r[0], float(r[1])])
	print("  16 张冷 load 合计 %.1f ms（墙钟 %.1f ms）" % [sum, _ms(t0, t1)])


## ② 12 只同帧：玩家实际感到的那一下（资源此时已经热了）
func _twelve_in_one_frame() -> void:
	await _clear_all()
	print("\n── ② 12 只同帧 spawn_piece（热资源）──")
	var ids := _twelve_ids()
	var t0 := Time.get_ticks_usec()
	for i in ids.size():
		var host := Node2D.new()
		add_child(host)
		_nodes.append(host)
		var a := Time.get_ticks_usec()
		var p := MatchAdapter.spawn_piece(host, ids[i], i % 2, Vector2i(i % 6, int(i / 6)))
		var b := Time.get_ticks_usec()
		if p != null:
			_nodes.append(p)
		print("  #%2d %-20s %7.1f ms" % [i, ids[i], _ms(a, b)])
	var t1 := Time.get_ticks_usec()
	await get_tree().process_frame
	var t2 := Time.get_ticks_usec()
	print("  同步生成 %d 只 = %.1f ms，再加首帧 %.1f ms ⇒ 这一帧共 %.1f ms" % [
		ids.size(), _ms(t0, t1), _ms(t1, t2), _ms(t0, t2)])
	print("  一帧预算 16.7ms ⇒ 超出 %.1f 倍" % (_ms(t0, t2) / 16.7))


## ③ 摊帧：每帧 2 只需要多少帧铺完、单帧峰值多少
func _spread_over_frames() -> void:
	await _clear_all()
	print("\n── ③ 摊帧（每帧 2 只）──")
	var ids := _twelve_ids()
	var peak := 0.0
	var frame := 0
	var i := 0
	var t_all := Time.get_ticks_usec()
	while i < ids.size():
		var a := Time.get_ticks_usec()
		for k in 2:
			if i >= ids.size():
				break
			var host := Node2D.new()
			add_child(host)
			_nodes.append(host)
			var p := MatchAdapter.spawn_piece(host, ids[i], i % 2, Vector2i(i % 6, int(i / 6)))
			if p != null:
				_nodes.append(p)
			i += 1
		var b := Time.get_ticks_usec()
		peak = maxf(peak, _ms(a, b))
		frame += 1
		await get_tree().process_frame
	var t_end := Time.get_ticks_usec()
	print("  %d 帧铺完（墙钟 %.1f ms），单帧峰值 %.1f ms" % [frame, _ms(t_all, t_end), peak])
	print("  ⚠ 摊帧会把「最后一只上场」推迟 %.0f ms，且先上场的多打了几帧 ⇒ 战斗结果会变" % (peak * frame))


func _twelve_ids() -> Array:
	var out: Array = []
	for id in MatchLevelDeck.deck_for(2):
		out.append(String(id))
	for id in MatchLevelDeck.deck_for(2):
		out.append(String(id))
	return out


func _clear_all() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_nodes.clear()
	await get_tree().process_frame
	await get_tree().process_frame
