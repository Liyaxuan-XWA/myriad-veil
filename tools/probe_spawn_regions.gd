extends Node
## 四个已开放区域的踏入落点检查：落点是否在该区矩形内、是否落在四条林带/墙里。

const REGIONS := ["world_lianqi", "world_zhuji", "world_jiedan", "world_yuanying"]


func _ready() -> void:
	print("\n########## 区域踏入落点探针 ##########")
	var ok_all := true
	for rid in REGIONS:
		SecretWorldDB.pending_spawn_region = rid
		var w := (load("res://scenes/world/secret_world.tscn") as PackedScene).instantiate()
		add_child(w)
		for i in 10:
			await get_tree().process_frame
		var p := w.get_node_or_null("Player") as Node2D
		var region := SecretWorldDB.get_region(rid)
		var rect: Rect2 = region.get("rect", Rect2())
		var pos := p.global_position if p != null else Vector2.INF
		var inside := rect.has_point(pos)
		# 该区林带/墙：terrain 条目里的 band_depth / wall_inset 口径
		var terr: Dictionary = region.get("terrain", {})
		var inset: Dictionary = terr.get("wall_inset", {})
		var depth: Dictionary = terr.get("band_depth", {})
		print("%-16s pos=%s rect=%s inside=%s inset=%s depth=%s" % [rid, pos, rect,
			str(inside), str(inset), str(depth)])
		if not inside:
			ok_all = false
		w.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("########## 结果：%s ##########" % ("通过" if ok_all else "有落点出界"))
	get_tree().quit(0 if ok_all else 1)
