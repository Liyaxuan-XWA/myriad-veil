extends Node

## 万界棋坛地标接入自检（2026-11-04）
## 只回答一件事：主城每个设施现在是不是**真贴图**，而不是 facility_generic 的色块。
## 顺带核对新地标的显示尺寸落在同类宽矮件的区间里（别过大、别顶穿名字标签）。

const FACILITY_IDS := ["arena", "match", "tower", "domain_gate", "alchemy",
	"talisman", "memory", "equipment", "warehouse"]

var _passes := 0
var _fails: Array[String] = []


func _ready() -> void:
	print("\n########## 主城设施美术自检 ##########")
	await _run()
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _run() -> void:
	var scene: Node = load("res://scenes/main/primordial_realm.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var root := scene.get_node_or_null("Facilities")
	_check(root != null, "场景里有 Facilities 容器")
	if root == null:
		return

	var found := {}
	for f in root.get_children():
		if not (f is Node2D):
			continue
		var fid := String(f.get("facility_id"))
		if fid.is_empty():
			continue
		found[fid] = f
	_check(found.size() == FACILITY_IDS.size(),
		"设施数量 = %d（表里 %d 个 id）" % [found.size(), FACILITY_IDS.size()],
		str(found.keys()))

	for fid in FACILITY_IDS:
		var node: Node = found.get(fid)
		if node == null:
			_fail("场景里找不到设施：%s" % fid)
			continue
		var cfg := ArtDB.get_facility_visual(fid)
		var tex_path := String(cfg.get("texture", ""))
		_check(not tex_path.is_empty(), "%s 有贴图条目（不再回落 generic 色块）" % fid, tex_path)
		if tex_path.is_empty():
			continue
		_check(ResourceLoader.exists(tex_path), "%s 贴图文件存在" % fid, tex_path)
		var tex: Texture2D = load(tex_path) if ResourceLoader.exists(tex_path) else null
		if tex == null:
			continue
		var target := float(cfg.get("target_length", 0.0))
		_check(target > 0.0, "%s 设了 target_length" % fid, str(target))
		if target <= 0.0:
			continue
		var img: Image = tex.get_image()
		var used: Rect2i = img.get_used_rect()
		var s: float = target / float(used.size.y)
		var disp := Vector2(tex.get_width() * s, tex.get_height() * s)
		var disp_w: float = used.size.x * s
		_check(disp_w >= 90.0 and disp_w <= 240.0,
			"%s 显示宽 %dpx（内容高 %dpx）在 90~240 区间" % [fid, int(disp_w), int(target)],
			"%.0fx%.0f" % [disp.x, disp.y])
		# 名字标签由 facility._place_name_below_visual 压在视觉下方，视觉不能是空的
		var vis: Node = node.get_node_or_null("Visual")
		_check(vis != null and vis.get("visual_id") == "facility_" + fid,
			"%s 的 Visual 挂上了正确 visual_id" % fid,
			str(vis.get("visual_id")) if vis != null else "无 Visual")

	# 棋坛专项：内容高占比要和现有 9 张同档（0.56~0.93），否则 target_length 口径会漂
	var cfg2 := ArtDB.get_facility_visual("match")
	var t2: Texture2D = load(String(cfg2.get("texture", "")))
	if t2 != null:
		var u2: Rect2i = t2.get_image().get_used_rect()
		var frac := float(u2.size.y) / float(t2.get_height())
		_check(frac >= 0.5 and frac <= 0.95,
			"棋坛内容高占比 %.2f 与现有设施同档" % frac)
		# 洋红键色残留：可见像素里 r 和 b 同时明显高于 g 的占比
		var a := t2.get_image()
		a.convert(Image.FORMAT_RGBA8)
		var px: PackedByteArray = a.get_data()
		var pink := 0
		var vis_n := 0
		for i in range(0, px.size(), 4):
			if px[i + 3] <= 60:
				continue
			vis_n += 1
			if px[i] > px[i + 1] + 25 and px[i + 2] > px[i + 1] + 15:
				pink += 1
		_check(float(pink) / maxf(float(vis_n), 1.0) < 0.01,
			"棋坛偏粉残留 %.2f%% < 1%%（洋红键色没渗进地标）" % (100.0 * pink / maxf(vis_n, 1.0)))
		# 本体亮度要留在同类区间：光晕配色曾经整图乘增益，把不透明的物件本体也压暗过
		# （中位 49，而现有 9 张是 99~130）→ 地标直接沉进地面里。
		var body := _body_lum(a)
		_check(body["median"] >= 85.0 and body["median"] <= 165.0,
			"棋坛本体亮度中位 %.0f 在同类区间 85~165（现有 9 张 99~130）" % body["median"])
		_check(body["bright_pct"] >= 15.0,
			"棋坛亮像素 %.1f%% >= 15%%（不是灰扑扑一块）" % body["bright_pct"])
		# 光晕（半透明带）不能比本体还亮 —— 发白的淡紫垫子就是这么来的
		var glow := _glow_lum(a)
		_check(glow < body["median"],
			"棋坛光晕亮度 %.0f 低于本体 %.0f（不是发光的垫子）" % [glow, body["median"]])

	# 玩家的登场演出 _begin_teleport_arrival() 里挂了两个 await，
	# 不等它跑完就 free 会在恢复点报「Resumed function after await, but class instance is gone」。
	for i in range(6):
		await get_tree().process_frame
	scene.free()   # 不 free 掉，退出时会留 ObjectDB 泄漏告警（probe_city_layout 同一口径）


## 不透明本体的亮度统计
func _body_lum(img: Image) -> Dictionary:
	img.convert(Image.FORMAT_RGBA8)
	var px: PackedByteArray = img.get_data()
	var n := 0
	var sum := 0.0
	var bright := 0
	var lums: Array[float] = []
	for i in range(0, px.size(), 4):
		if px[i + 3] < 240:
			continue
		var l := 0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2]
		n += 1
		sum += l
		if l > 120.0:
			bright += 1
		if n % 97 == 0:
			lums.append(l)
	if n == 0:
		return {"median": 0.0, "mean": 0.0, "bright_pct": 0.0}
	lums.sort()
	return {"median": lums[lums.size() / 2], "mean": sum / n,
		"bright_pct": 100.0 * bright / n}


## 半透明光晕带的亮度中位
func _glow_lum(img: Image) -> float:
	img.convert(Image.FORMAT_RGBA8)
	var px: PackedByteArray = img.get_data()
	var lums: Array[float] = []
	for i in range(0, px.size(), 4):
		if px[i + 3] <= 8 or px[i + 3] > 120:
			continue
		lums.append(0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2])
	if lums.is_empty():
		return 0.0
	lums.sort()
	return lums[lums.size() / 2]


func _check(cond: bool, label: String, extra := "") -> void:
	if cond:
		_passes += 1
		print("  ok  ", label)
	else:
		_fails.append(label + ("   「" + extra + "」" if not extra.is_empty() else ""))


func _fail(label: String) -> void:
	_fails.append(label)
