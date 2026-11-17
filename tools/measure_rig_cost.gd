extends Node
## 棋子 _ready 里的 200-420ms 到底是不是 rig 动画构建
##
## 上一轮量到：刀客每次实例化都要 200ms、石犼 420ms（预热无效 ⇒ 每实例的活）。
## 两只的共同点是都用 BossRig（骨骼），而 BossRig._build_animations() 是
## **每个实例重新造一遍 Animation 资源**。如果这就是大头，
## 修法是把 Animation 资源按 rig 数据路径缓存复用，而不是每只重造。
##
## 这里单独把 rig 的三段量出来：setup(data) / _build_nodes / _build_animations。
func _ready() -> void:
	print("\n########## BossRig 每实例构建成本 ##########")
	var cases := [
		["刀客 daoke", "res://assets/characters/boss/daoke_rig/rig.tres"],
		["石犼 shihou", "res://assets/characters/boss/shihou_rig/rig.tres"],
		["剑客 jianke", "res://assets/characters/boss/jianke_rig/rig.tres"],
	]
	for c in cases:
		var path := String(c[1])
		if not ResourceLoader.exists(path):
			print("  %-18s 找不到 %s（跳过）" % [c[0], path])
			continue
		var packed := load(path) as BossRigData
		var a := Time.get_ticks_usec()
		var rig := BossRig.new()
		add_child(rig)
		var ok := rig.setup(packed)
		var b := Time.get_ticks_usec()
		print("  %-18s setup(含建节点+动画) = %7.1f ms  ok=%s" % [c[0], _ms(a, b), str(ok)])
		# 第二次用同一份 data 再建一只
		var rig2 := BossRig.new()
		add_child(rig2)
		var c2 := Time.get_ticks_usec()
		rig2.setup(packed)
		var d := Time.get_ticks_usec()
		print("  %-18s 第二次同数据 = %7.1f ms" % ["", _ms(c2, d)])
		rig.free()
		rig2.free()
		await get_tree().process_frame

	print("\n── 整只棋子的 _ready 拆开：有无 rig ──")
	for id in ["boss_01", "world_core_shihou", "boss_02_b"]:
		var e := Time.get_ticks_usec()
		var n := (load(WorldDB.get_boss_scene(id)) as PackedScene).instantiate() as Node2D
		add_child(n)
		var f := Time.get_ticks_usec()
		var skin = n.get("skin") if "skin" in n else null
		var has_rig := false
		if skin != null and is_instance_valid(skin):
			has_rig = (skin.get("render_node") as Object) is BossRig
		print("  %-20s 进树=%7.1f ms  用 rig=%s" % [id, _ms(e, f), str(has_rig)])
		n.free()
		await get_tree().process_frame
	get_tree().quit(0)


func _ms(a: int, b: int) -> float:
	return float(b - a) / 1000.0
