extends Node
## 技能图标完整性自检（2026-10-30）：
## 所有功法条目必须有 icon、文件存在、256×256；新增技能不能留空图标。
## 用法：godot --headless --path . tools/probe_skill_icons.tscn -- --no-save

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
	print("\n########## 技能图标完整性探针 ##########")
	var all: Array = []
	all.append_array(SkillDB.get_by_type(SkillDB.TYPE_ACTIVE))
	all.append_array(SkillDB.get_by_type(SkillDB.TYPE_PASSIVE))
	var missing: Array = []
	var bad_size: Array = []
	for raw in all:
		var sk := raw as Dictionary
		var sid := String(sk.get("skill_id", ""))
		var path := String(sk.get("icon", ""))
		if path == "" or not ResourceLoader.exists(path):
			missing.append(sid)
			continue
		var tex := load(path) as Texture2D
		if tex == null or tex.get_width() != 256 or tex.get_height() != 256:
			bad_size.append("%s=%dx%d" % [sid,
				tex.get_width() if tex != null else -1,
				tex.get_height() if tex != null else -1])
	# ⚠ 不锁死门数（每加一族都会红一次，白红）：真正要守的是下面两条
	# 「每门都有图标」「尺寸统一」。这里只留一个下界，防功法表被误删。
	# 2026-11-10 符箓五式（落笔/贴符/引爆/符罩/符心）整套退役 → 门数 107 → 102。
	_check(all.size() >= 102, "功法条目 ≥102 门", str(all.size()))
	_check(missing.is_empty(), "所有功法都有图标文件", str(missing))
	_check(bad_size.is_empty(), "图标统一 256×256", str(bad_size))
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
