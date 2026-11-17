extends Node
## 卡面成品盘点：逐位 BOSS 检查四种卡的配置与贴图是否齐全（只读，不改存档）。

func _check_file(path: String, missing: Array) -> void:
	if path == "" or not ResourceLoader.exists(path):
		missing.append(path if path != "" else "(空路径)")

## 华彩三层的结构守卫 —— 这两条都是实机踩出来的，肉眼在图鉴里很难发现：
## 1) 角色层不透明 → shader 里 `base*(1-ch.a)` 恒为 0，背景层永远不显示，
##    卡1 与卡3 退化成同一张图（执烛 / 叠纸 实测 MAD 只有 4.5 / 5.1，标准是 16+）。
## 2) 线条层的遮罩放在 alpha 而 RGB 是纯白 → shader 读的是 `.r`，整卡都被当成蚀刻线，
##    legacy bloom 一路积到饱和（观澜卡3 过曝 17.8%，同档其他卡 ≤0.7%）。
func _guard_layers(boss_id: String, art_path: String, lines_path: String, bad: Array) -> void:
	for pair in [["art", art_path], ["lines", lines_path]]:
		var role := String(pair[0])
		var path := String(pair[1])
		if path == "":
			continue
		## globalize 之后再用 load_from_file：直接喂 res:// 会每张图片刷一条
		## "Loaded resource as image file" 警告，把探针输出淹掉。
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img == null:
			bad.append("%s %s 读不出像素" % [boss_id, role])
			continue
		var w := img.get_width()
		var h := img.get_height()
		var lo := 1.0
		var hi := 0.0
		var a_lo := 1.0
		var a_hi := 0.0
		var y := 0
		while y < h:
			var x := 0
			while x < w:
				var c := img.get_pixel(x, y)
				lo = minf(lo, c.r)
				hi = maxf(hi, c.r)
				a_lo = minf(a_lo, c.a)
				a_hi = maxf(a_hi, c.a)
				x += 16
			y += 16
		if role == "art":
			if a_lo > 0.9:
				bad.append("%s 角色层完全不透明(alpha_min=%.2f) → 背景层永不显示，卡1==卡3" % [boss_id, a_lo])
		elif hi - lo < 0.02 and a_hi - a_lo > 0.2:
			bad.append("%s 线条层遮罩在 alpha 通道而 RGB 恒为 %.2f → shader 读 .r 会把整卡当蚀刻线" % [boss_id, hi])

func _ready() -> void:
	print("\n########## 卡面成品盘点 ##########")
	var entries := CodexDB.card_entries()
	var total_expected := 0
	var total_ready := 0
	var lacking: Array = []
	var layer_bad: Array = []
	for raw in entries:
		var e := raw as Dictionary
		var boss_id := String(e.get("id", ""))
		var variants: Array = e.get("card_variants", [])
		var missing: Array = []
		var labels := PackedStringArray()
		for vraw in variants:
			var v := vraw as Dictionary
			labels.append(String(v.get("id", "")))
			if String(v.get("id", "")) == "portrait":
				_check_file(String(v.get("art", "")), missing)
			elif String(v.get("id", "")) == "scene":
				_check_file(String(v.get("art", "")), missing)
				_check_file(String(v.get("bg", "")), missing)
				_check_file(String(v.get("lines", "")), missing)
			elif String(v.get("id", "")) == "plain":
				_check_file(String(v.get("art", "")), missing)
				_check_file(String(v.get("lines", "")), missing)
				_check_file(String(v.get("bg", "")), missing)
			elif String(v.get("id", "")) == "ink":
				for key in ["art", "reveal", "flow_tex", "guard_tex"]:
					_check_file(String(v.get(key, "")), missing)
			else:
				for key in ["art", "bg", "lines", "flow", "guard"]:
					if String(v.get(key, "")) != "":
						_check_file(String(v.get(key, "")), missing)
		var has_all := variants.size() >= 4
		var ready := has_all and missing.is_empty()
		if ready:
			total_ready += 1
		else:
			lacking.append("%s（%s）：%d 张 %s%s" % [
				String(e.get("name", boss_id)), boss_id, variants.size(),
				",".join(labels),
				"" if missing.is_empty() else " 缺文件 " + ",".join(missing),
			])
		total_expected += 4 if has_all else variants.size()
		print("%s  %-18s %d 张  %s%s" % [
			"OK " if ready else "缺 ",
			String(e.get("name", boss_id)),
			variants.size(),
			",".join(labels),
			"" if missing.is_empty() else "  缺 " + str(missing),
		])
	print("\n汇总：%d / %d 位 BOSS 四张齐；共 %d 张卡" % [
		total_ready, entries.size(), CodexDB.card_total()])
	## 分层结构要覆盖全部华彩卡，不看解锁状态 —— 未通关的存档里 scene 卡根本不在
	## variants 里，只靠上面那个循环会整批漏检。
	for boss_id in CodexDB.HOLO_CARDS.keys():
		var cfg: Dictionary = CodexDB.HOLO_CARDS[boss_id]
		var scene: Dictionary = cfg.get("scene", {}) if cfg.get("scene", {}) is Dictionary else {}
		_guard_layers(String(boss_id), String(scene.get("art", cfg.get("art", ""))),
				String(scene.get("lines", cfg.get("lines", ""))), layer_bad)
	if layer_bad.is_empty():
		print("分层结构：%d 位华彩卡的角色层有真透明、线条层遮罩在 R 通道" % CodexDB.HOLO_CARDS.size())
	else:
		print("分层结构不合格：")
		for s in layer_bad:
			print("  ! ", s)
	if not lacking.is_empty():
		print("未齐：")
		for s in lacking:
			print("  - ", s)
	get_tree().quit(0)
