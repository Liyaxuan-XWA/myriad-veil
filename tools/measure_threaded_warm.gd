extends Node
## 线程预载能不能把「招式序列帧 .tres 的解码」从主线程挪走
##
## 已定位：开战卡顿的 90% 是 SkinVisual._build_rig 里的 `load(sprite_frames)`，
## 石犼(boss_huyao 皮) 473ms、刀客 217ms，attach 只 0.1ms。
## 这些 .ctex 是 compress/mode=1（有损、非 VRAM），load 时在主线程解成 RGBA8 再上传。
## 本探针回答两件事：
##   ① 阻塞 load 的单价（基线）
##   ② load_threaded_request 期间，主线程每帧还花多少（帧周期该保持 ~16.7ms）
##   ③ 预载完并**持有引用**后，真正上场是否 0ms

const SHEETS: Array = [
	"res://assets/characters/boss/boss_huyao.tres",
	"res://assets/characters/boss/boss_daoke.tres",
]


func _ready() -> void:
	print("\n########## 序列帧资源预载 ##########")
	_mem("开场")
	var held: Dictionary = {}

	print("\n── ① 阻塞 load 单价（每次先丢引用，逼它真读盘）──")
	for p in SHEETS:
		var a := Time.get_ticks_usec()
		var r: Resource = load(p)
		var b := Time.get_ticks_usec()
		print("  %-24s %7.1f ms  (valid=%s)" % [p.get_file(), _ms(a, b), r != null])
		held[p] = r
		await get_tree().process_frame
		held.clear()
		await get_tree().process_frame
		await get_tree().process_frame

	print("\n── ② 线程预载期间的帧周期 ──")
	for _i in 3:
		await get_tree().process_frame
	var b0 := Time.get_ticks_usec()
	for _i in 12:
		await get_tree().process_frame
	var baseline := _ms(b0, Time.get_ticks_usec()) / 12.0
	print("  空闲帧周期 = %.2f ms" % baseline)
	var paths: Array = []
	for p in SHEETS:
		paths.append(p)
		ResourceLoader.load_threaded_request(p)
	var t0 := Time.get_ticks_usec()
	var peak := 0.0
	var spins := 0
	while true:
		var done := true
		for p in paths:
			if ResourceLoader.load_threaded_get_status(p) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				done = false
		if done:
			break
		var f0 := Time.get_ticks_usec()
		await get_tree().process_frame
		peak = maxf(peak, float(Time.get_ticks_usec() - f0) / 1000.0)
		spins += 1
		if spins > 600:
			print("  ⚠ 轮询超过 600 帧，放弃")
			get_tree().quit(1)
			return
	var wall := _ms(t0, Time.get_ticks_usec())
	print("  两张一起线程预载：墙钟 %.1f ms，跑了 %d 帧，主线程峰值帧 %.2f ms（空闲基线 %.2f）"
			% [wall, spins, peak, baseline])
	for p in paths:
		var c := Time.get_ticks_usec()
		var r: Resource = ResourceLoader.load_threaded_get(p)
		var d := Time.get_ticks_usec()
		print("  %-24s take=%5.1f ms  (valid=%s)" % [p.get_file(), _ms(c, d), r != null])
		held[p] = r
	_mem("两张表进内存后")

	print("\n── ③ 持有引用时，真正建一只棋子要多少（同一进程建两次，看残值是不是一次性的）──")
	for pass_i in 2:
		for id in ["world_core_shihou", "boss_01"]:
			var e := Time.get_ticks_usec()
			var n := (load(WorldDB.get_boss_scene(id)) as PackedScene).instantiate() as Node2D
			add_child(n)
			var f := Time.get_ticks_usec()
			print("  第%d趟 %-20s 进树 = %7.1f ms" % [pass_i + 1, id, _ms(e, f)])
			n.free()
			await get_tree().process_frame
	print("  （对照 ① 之前的实测：石犼 485ms / 刀客 245ms）")

	print("\n── ④ 全暖之后一次摆 12 只（= 修好之后的开战帧）──")
	var ids: Array = []
	for id in MatchLevelDeck.deck_for(2):
		ids.append(String(id))
	for id in MatchLevelDeck.deck_for(9):
		ids.append(String(id))
	for id in ids:
		held["scene:" + id] = load(WorldDB.get_boss_scene(id))
	_mem("12 份场景进内存后")
	var alive: Array = []
	var g0 := Time.get_ticks_usec()
	for id in ids:
		var n := (held["scene:" + id] as PackedScene).instantiate() as Node2D
		add_child(n)
		alive.append(n)
	var g1 := Time.get_ticks_usec()
	print("  12 只同帧进树 = %6.1f ms" % _ms(g0, g1))
	await get_tree().process_frame
	print("  首帧后 常驻=%6.1f MB  纹理显存=%6.1f MB" % [
		float(OS.get_static_memory_usage()) / 1048576.0,
		float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) / 1048576.0])
	for n in alive:
		n.free()
	alive.clear()
	held.clear()
	await get_tree().process_frame
	await get_tree().process_frame
	_mem("全部释放后")

	print("\n── ⑤ 连场景一起线程预载，能不能吃掉「同进程第一次」的 130ms 残值 ──")
	# ⚠ 上面 held.clear() 把序列帧表也丢了，这里必须连表一起再预载，
	#    否则量到的是「重新解码」而不是「场景预载」的效果（第一版就踩了这个坑）。
	var sc: Array = [WorldDB.get_boss_scene("world_core_shihou"), WorldDB.get_boss_scene("boss_01")]
	var all: Array = []
	all.append_array(sc)
	all.append_array(SHEETS)
	for p in all:
		ResourceLoader.load_threaded_request(p)
	for p in all:
		while ResourceLoader.load_threaded_get_status(p) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
	var keep: Dictionary = {}
	for p in all:
		keep[p] = ResourceLoader.load_threaded_get(p)
	for id in ["world_core_shihou", "boss_01"]:
		var e := Time.get_ticks_usec()
		var n := (keep[WorldDB.get_boss_scene(id)] as PackedScene).instantiate() as Node2D
		add_child(n)
		print("  %-20s 场景已线程预载 ⇒ 首次进树 = %6.1f ms" % [id, _ms(e, Time.get_ticks_usec())])
		n.free()
		await get_tree().process_frame
	get_tree().quit(0)


func _ms(a: int, b: int) -> float:
	return float(b - a) / 1000.0


## 内存读数：常驻 = Godot 分配器统计（含解码后的纹理 CPU 侧），纹理显存 = RenderingServer 里的纹理字节
func _mem(tag: String) -> void:
	print("  [内存] %-10s 常驻=%6.1f MB  纹理显存=%6.1f MB" % [
		tag,
		float(OS.get_static_memory_usage()) / 1048576.0,
		float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) / 1048576.0])
