extends Node2D
## 诊断：虎妖在棋盘上"伤害太低"到底是打不到、还是被打折。
## 每秒打一行：它的状态 / 当前招式 / 目标与距离 / 攻击力 / 两边血量，
## 并统计 `deal_damage_to()` 的返回值分布（false=根本没进伤害管线）。
## 用法：godot --headless --path . res://tools/diag_match_huyao.tscn -- --no-save

var a_id := "boss_huyao"
var b_id := "boss_02"
var secs := 20.0


func _ready() -> void:
	var a := MatchAdapter.spawn_piece(self, a_id, 0, Vector2i(1, 4))
	var b := MatchAdapter.spawn_piece(self, b_id, 1, Vector2i(4, 1))
	if a == null or b == null:
		print("DIAG 生成失败")
		get_tree().quit(1)
		return
	await get_tree().physics_frame
	print("DIAG %s atk=%.0f hp=%.0f | %s atk=%.0f hp=%.0f" % [
			a_id, float(a.get("attack_power")), float(a.get("max_hp")),
			b_id, float(b.get("attack_power")), float(b.get("max_hp"))])
	var t := 0.0
	var acc := 0.0
	var hp_a := float(a.get("current_hp"))
	var hp_b := float(b.get("current_hp"))
	var probe: Array = []
	while t < secs:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		acc += dt
		if not is_instance_valid(a) or not is_instance_valid(b):
			print("DIAG t=%.1f 有一只没了（死亡/释放）A=%s B=%s" % [
					t, str(is_instance_valid(a)), str(is_instance_valid(b))])
			break
		if acc < 1.0:
			continue
		acc = 0.0
		var d: Vector2 = a.get("global_position") - b.get("global_position")
		var tgt = a.get("target")
		print("DIAG t=%.0f A血=%.0f(Δ%.0f) B血=%.0f(Δ%.0f) A状态=%s A招=%s 目标=%s 距离=%.0f" % [
				t, float(a.get("current_hp")), float(a.get("current_hp")) - hp_a,
				float(b.get("current_hp")), float(b.get("current_hp")) - hp_b,
				str(a.get("state")), str(a.get("_current_form")),
				"无" if tgt == null else str((tgt as Node).name), d.length()])
		hp_a = float(a.get("current_hp"))
		hp_b = float(b.get("current_hp"))
	# 直接问一次：它现在能不能把伤害打到对面身上
	var ok := bool(a.call("deal_damage_to", b, 1000.0, "physical"))
	print("DIAG 直接调 deal_damage_to(B, 1000, physical) 返回=", ok,
			"  → B 血=", float(b.get("current_hp")))
	for key in ["elemental", "physical_projectile"]:
		print("DIAG 同类调用 %s 返回=" % key, bool(a.call("deal_damage_to", b, 1000.0, key)),
				"  → B 血=", float(b.get("current_hp")))
	# 对面的减免读数
	for prop in ["spell_resist", "physical_resist", "defense", "armor"]:
		if b.get(prop) != null:
			probe.append("%s=%s" % [prop, str(b.get(prop))])
	print("DIAG 对面防御字段：", " ".join(probe))
	print("DIAG A 的招式表：", str(a.get("skill_ids")), " 原型表：", str(a.get("forms")))
	a.queue_free()
	b.queue_free()
	get_tree().quit(0)
