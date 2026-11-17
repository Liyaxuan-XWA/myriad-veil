extends Node
## 两仪真人「阴阳双鱼」表现自检（2026-10-29）：
##   两枚弹必须各自带金/青鱼形外观、按飞行方向转头、并且能打玩家旗。
## 用法：godot --headless --path . res://tools/probe_liangyi_fish.tscn

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	print("\n########## 两仪双鱼表现自检 ##########")
	for vis_id in ["liangyi_fish_yang", "liangyi_fish_yin"]:
		var cfg := ArtDB.get_visual(vis_id)
		var tex_path := String(cfg.get("texture", ""))
		_check(tex_path != "" and ResourceLoader.exists(tex_path),
			"%s 贴图已登记" % vis_id, tex_path)
	var fx := ArtDB.get_skill_fx("fx_yinyang_fish")
	_check(not fx.is_empty(), "BOSS 双鱼特效条目存在")
	_check(String(fx.get("motif", "")) == "volley", "双鱼特效是 volley 型",
		String(fx.get("motif", "")))

	var boss = (load("res://scenes/boss/domain_boss_02.tscn") as PackedScene).instantiate()
	add_child(boss)
	await get_tree().process_frame
	await get_tree().process_frame
	boss.set_physics_process(false)
	boss.set_process(false)
	var form := MoveDB.resolve_boss("form_yinyang_fish")
	boss.call("_launch_fish", Vector2.LEFT, "physical_projectile", 10.0, 0.0, form)
	boss.call("_launch_fish", Vector2.LEFT, "elemental", 10.0, PI, form)
	await get_tree().process_frame

	var ids: Array = []
	var flags_ok := true
	for raw in get_children():
		# 第二枚重名时 Godot 会给 @Area2D@xxx 这种自动名，不能按节点名筛选
		if raw is Area2D and raw.get("attack_kind") != null:
			var vis = raw.get("visual")
			if vis != null:
				ids.append(String(vis.visual_id))
			if not bool(raw.get("align_visual")) or not bool(raw.get("align_visual_right")):
				flags_ok = false
			if (int(raw.get("collision_mask")) & ArrayFlag.PLAYER_HIT_LAYER) == 0:
				flags_ok = false
	ids.sort()
	_check(ids.has("liangyi_fish_yang") and ids.has("liangyi_fish_yin"),
		"双鱼分别是金/青鱼形", str(ids))
	_check(flags_ok, "双鱼按飞行方向转头并能打旗")

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("FAILED  ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
