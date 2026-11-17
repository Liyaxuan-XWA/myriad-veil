extends Node
## 水墨全套探针：16 位 BOSS 都有 4 张卡，水墨资产齐全、尺寸一致、数据图真的在流。
## 用法：godot --headless --path . tools/probe_ink_cards.tscn -- --no-save

var _fails := 0
var _passes := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails += 1
		print("FAIL  ", label, "  ", detail)


func _ink_of(boss_id: String) -> Dictionary:
	var entry := CodexDB.card_entry(boss_id)
	for raw in entry.get("card_variants", []):
		if String((raw as Dictionary).get("id", "")) == "ink":
			return raw as Dictionary
	return {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 水墨全套探针 ##########")
	var entries := CodexDB.card_entries()
	_check(entries.size() == 16, "16 位 BOSS 入册", str(entries.size()))
	var seen_notes := 0
	for raw in entries:
		var e: Dictionary = raw
		var bid := String(e.get("id", ""))
		if CodexDB.INK_NOTES.has(bid):
			seen_notes += 1
		var variants: Array = e.get("card_variants", [])
		_check(variants.size() == 4, "%s 四张卡" % bid, str(variants.size()))
		var ids: Array = []
		var ink: Dictionary = {}
		for vraw in variants:
			var v: Dictionary = vraw
			ids.append(String(v.get("id", "")))
			if String(v.get("id", "")) == "ink":
				ink = v
		_check(ids == ["scene", "portrait", "plain", "ink"], "%s 卡序" % bid, str(ids))
		if ink.is_empty():
			continue
		_check(String(ink.get("label", "")) == "水墨 · 纸本", "%s 水墨 label" % bid)
		_check(String(ink.get("fx", "")) == "paper", "%s 水墨走纸本" % bid)
		_check(String(ink.get("unlock", "")) == "speed", "%s 水墨按速通解锁" % bid)
		_check(String(ink.get("desc", "")).contains(CodexDB.INK_DESC_TAIL),
			"%s 水墨文案完整" % bid)
		for key in ["art", "reveal", "flow_tex", "guard_tex"]:
			var path := String(ink.get(key, ""))
			_check(path != "" and ResourceLoader.exists(path), "%s 资产 %s" % [bid, key], path)
		var art := load(String(ink.get("art", ""))) as Texture2D
		var reveal := load(String(ink.get("reveal", ""))) as Texture2D
		var flow := load(String(ink.get("flow_tex", ""))) as Texture2D
		var guard := load(String(ink.get("guard_tex", ""))) as Texture2D
		if art != null and reveal != null and flow != null and guard != null:
			_check(art.get_size() == Vector2(640, 960), "%s 原画 640×960" % bid, str(art.get_size()))
			_check(reveal.get_size() == Vector2(640, 960), "%s reveal 尺寸" % bid)
			_check(flow.get_size() == Vector2(640, 960), "%s flow 尺寸" % bid)
			_check(guard.get_size() == Vector2(640, 960), "%s guard 尺寸" % bid)
			var flow_img := flow.get_image()
			var guard_img := guard.get_image()
			var reveal_img := reveal.get_image()
			var wmin := 1.0
			var wmax := 0.0
			var gsum := 0.0
			var gmax := 0.0
			var rmin := 1.0
			var rmax := 0.0
			for i in 26:
				for j in 26:
					var x := int((i + 0.5) * 640.0 / 26.0)
					var y := int((j + 0.5) * 960.0 / 26.0)
					var wv := flow_img.get_pixel(x, y).a
					wmin = minf(wmin, wv)
					wmax = maxf(wmax, wv)
					var gv := guard_img.get_pixel(x, y).r
					gsum += gv
					gmax = maxf(gmax, gv)
					var rv := reveal_img.get_pixel(x, y).r
					rmin = minf(rmin, rv)
					rmax = maxf(rmax, rv)
			var gmean := gsum / 676.0
			_check(wmax - wmin > 0.25, "%s 有笔势权重差" % bid,
				"%.2f→%.2f" % [wmin, wmax])
			_check(gmean < 0.35 and gmax > 0.55, "%s 保护有选择" % bid,
				"mean %.2f / max %.2f" % [gmean, gmax])
			_check(rmax - rmin > 0.7, "%s 落墨有先后" % bid,
				"%.2f→%.2f" % [rmin, rmax])
	_check(seen_notes == 16, "16 位都有水墨小传", str(seen_notes))
	_check(CodexDB.card_total() >= 56, "卡池至少 56 张", str(CodexDB.card_total()))

	# 水墨解锁：双倍气血场次 10 秒内（含 10.0 秒）
	CharacterData.tower_progress[1] = {
		"unlocked": true, "first_kill": true, "clear_count": CodexDB.HOLO_CLEAR_REQUIRED,
	}
	CharacterData.tower_best_time[1] = 9.9
	_check(bool(_ink_of("boss_huyao").get("unlocked", false)), "塔层 9.9 秒解锁水墨")
	CharacterData.tower_best_time[1] = 10.1
	_check(not bool(_ink_of("boss_huyao").get("unlocked", false)), "塔层 10.1 秒不解锁水墨")
	CharacterData.tower_best_time[1] = CodexDB.INK_CLEAR_TIME_LIMIT
	_check(bool(_ink_of("boss_huyao").get("unlocked", false)), "塔层 10.0 秒解锁水墨")
	CharacterData.secret_world["core_kills"]["world_lianqi"] = true
	CharacterData.core_replay["world_lianqi"] = {
		"clear_count": CodexDB.HOLO_CLEAR_REQUIRED, "best_time": 9.5,
	}
	_check(bool(_ink_of("world_core_lianqi").get("unlocked", false)), "核心 9.5 秒解锁水墨")
	CharacterData.core_replay["world_lianqi"]["best_time"] = 10.5
	_check(not bool(_ink_of("world_core_lianqi").get("unlocked", false)), "核心 10.5 秒不解锁水墨")
	CharacterData.core_replay["world_lianqi"]["best_time"] = 9.5
	CharacterData.secret_world["core_kills"].erase("world_lianqi")
	_check(not bool(_ink_of("world_core_lianqi").get("unlocked", false)), "未击败核心不解锁水墨")
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
