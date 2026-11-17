extends Node
## 导出 16 位守关者的**真实**面板，供 MatchDB.PANEL_SNAPSHOT 使用。
##
## 不手抄：塔层 BOSS 从各自场景实例化后读 max_hp / attack_power，
## 四位大陆核心从 SecretWorldDB 的 CORE_BOSS* 表读。
## 数值一改，重跑本工具即可；探针 probe_match_rules 会把快照和现场读数对账，防漂移。
## 用法：godot --headless --path . res://tools/dump_match_panel.tscn -- --no-save

const TOWER := ["boss_huyao", "boss_01", "boss_01_c", "boss_02", "boss_02_b", "boss_02_c",
	"boss_03", "boss_03_b", "boss_03_c", "boss_04", "boss_04_b", "boss_04_c"]

func _ready() -> void:
	print("const PANEL_SNAPSHOT := {")
	for bid in TOWER:
		var scene_path := String(WorldDB.BOSS_SCENES.get(bid, WorldDB.DEFAULT_BOSS_SCENE))
		var res := load(scene_path)
		if res == null:
			print("\t# !! %s 场景读不出来：%s" % [bid, scene_path])
			continue
		var n := (res as PackedScene).instantiate()
		add_child(n)
		var hp := float(n.get("max_hp"))
		var at := float(n.get("attack_power"))
		n.queue_free()
		print("\t\"%s\": {\"hp\": %.0f, \"atk\": %.0f}," % [bid, hp, at])
	for raw in SecretWorldDB.REGIONS:
		var r := raw as Dictionary
		var region := String(r.get("region_id", ""))
		var core_id := String(r.get("core_boss_id", ""))
		if core_id == "":
			continue
		# get_core_boss 收的是 region_id，不是 core_boss_id —— 遍历区域表反查，
		# 免得在这里硬编 CORE_BOSS_YUANYING 这类名字（它和 CodexDB 里的
		# world_core_shihou 就对不上，写死迟早读错人）。
		var table: Dictionary = SecretWorldDB.get_core_boss(region)
		if table.is_empty():
			print("\t# !! %s（区域 %s）取不到核心配置" % [core_id, region])
			continue
		print("\t\"%s\": {\"hp\": %.0f, \"atk\": %.0f},  # 区域 %s" % [
			core_id, float(table.get("max_hp", 0.0)), float(table.get("attack_power", 0.0)), region])
	print("}")
	get_tree().quit(0)
