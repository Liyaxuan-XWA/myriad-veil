extends Node
## 导出「项目内容树」给特效工坊面板用（2026-11-04）。
##
## 面板是编辑器 @tool 脚本，不能直接调 SkillDB / MoveDB / ArtDB（那些脚本不是 @tool，
## 在编辑器里调用同一类风险），所以这里在真实运行环境里跑一遍，把
## BOSS → 招式 → 当前演出 motif / 五行属性 拍成 JSON 给面板读。
##
## 用法：godot --headless --path . tools/dump_content_map.tscn -- --no-save
## 改了招式表 / 新增 BOSS 后重跑一次即可。

const OUT := "res://assets/fx/pixelfx/content_map.json"


func _ready() -> void:
	var bosses: Array = []
	for raw in SkillDB.get_library_groups():
		var g: Dictionary = raw
		var bid := String(g.get("boss_id", ""))
		var skills: Array = []
		for sraw in (g.get("skills", []) as Array):
			var sk: Dictionary = sraw
			var sid := String(sk.get("skill_id", ""))
			var fid := String(sk.get("form_id", ""))
			var form := MoveDB.get_form(fid)
			var fx := ArtDB.get_skill_fx(sid)
			skills.append({
				"skill_id": sid,
				"skill_name": String(sk.get("skill_name", "?")),
				"form_id": fid,
				"form_name": String(MoveDB.get_form_name(fid)),
				"damage_element": String(form.get("damage_element", "")),
				"motif": String(fx.get("motif", "")),
				"family": String(fx.get("family", "")),
				"passive": String(sk.get("skill_type", "")) == "passive",
				"desc": String(sk.get("desc", "")),
			})
		if skills.is_empty():
			continue
		bosses.append({
			"boss_id": bid,
			"group_name": String(g.get("group_name", "")),
			"boss_name": String(WorldDB.get_boss_name(bid)) if bid != "" else "杂类",
			"skills": skills,
		})
	var doc := {
		"generated": Time.get_datetime_string_from_system(false, true),
		"count": skills_total(bosses),
		"bosses": bosses,
	}
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		print("OPEN_FAIL ", OUT)
		get_tree().quit(1)
		return
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()
	print("content_map bosses=", bosses.size(), " skills=", doc["count"], " -> ", OUT)
	get_tree().quit(0)


func skills_total(bosses: Array) -> int:
	var n := 0
	for b in bosses:
		n += ((b as Dictionary).get("skills", []) as Array).size()
	return n
