extends Node
## 大陆两只核心首领的骨骼接入自检（2026-10-29）。
## 用法：godot --headless --path . res://tools/probe_world_boss_rigs.tscn

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
	print("\n########## 大陆核心首领骨骼自检 ##########")
	_probe("world_core_lianqi", SecretWorldDB.CORE_SKILLS, 126.0)
	_probe("world_core_zhuji", SecretWorldDB.CORE_SKILLS_ZHUJI, 260.0)
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("FAILED  ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _probe(visual_id: String, skills: Array, old_len: float) -> void:
	var cfg := ArtDB.get_visual(visual_id)
	var rig_path := String(cfg.get("rig", ""))
	_check(rig_path != "" and ResourceLoader.exists(rig_path), visual_id + " 已登记 rig", rig_path)
	if rig_path == "" or not ResourceLoader.exists(rig_path):
		return
	var data := load(rig_path) as BossRigData
	_check(data != null, visual_id + " rig.tres 可加载")
	if data == null:
		return
	_check(data.validate() == "", visual_id + " rig 数据自检", data.validate())
	var sc_path := data.rig_script
	_check(sc_path != "" and ResourceLoader.exists(sc_path), visual_id + " 有专属动画集", sc_path)
	var sc := load(sc_path) as GDScript
	var rig: BossRig = sc.new() if sc != null and sc.can_instantiate() else BossRig.new()
	add_child(rig)
	_check(rig.setup(data), visual_id + " 骨骼可构建")
	_check(rig.has_animation("idle") and rig.has_animation("walk"), visual_id + " 有 idle / walk")
	_check(rig.has_animation("attack"), visual_id + " 有平A动作")
	var missing: Array = []
	for raw in skills:
		var anim := String((raw as Dictionary).get("anim", ""))
		if anim == "" or not rig.has_animation(anim):
			missing.append(anim)
	_check(missing.is_empty(), visual_id + " 每式都有骨骼动作", str(missing))
	var disp_h := float(data.canvas.y) * float((cfg.get("scale", Vector2.ONE) as Vector2).y)
	_check(absf(disp_h - old_len) <= 24.0, visual_id + " 显示高度接近旧图",
		"%.1f vs %.1f" % [disp_h, old_len])
	rig.queue_free()
