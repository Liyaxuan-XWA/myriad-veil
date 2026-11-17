extends Node
## 位面星图「旋转木马」改版验收（2026-11-06）
## 口径变了：底图不再有门，门是 4 张独立 sprite 挂在槽位上；
## 前排 3 格可点、深处 1 格压暗不可点，转一格要吸附、回滑要镜像得回来。
## 用法：godot --headless --path . tools/probe_domain_star_map.tscn -- --no-save

const MapScript = preload("res://scripts/ui/facility/domain_star_map.gd")

const SLOT_C := 0
const SLOT_L := 1
const SLOT_D := 2
const SLOT_R := 3

var _passes := 0
var _fails := 0


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  %s  %s" % [what, detail])
	else:
		_fails += 1
		print("FAIL  %s  %s" % [what, detail])


func _print_row(what: String, bad: Array) -> void:
	_check(bad.is_empty(), what, str(bad.slice(0, 6)))


## 底图某个圆环位置的亮度（annulus = 半径 r 的 0.82~1.18 倍那一圈）
## 用 0.299/0.587/0.114 的亮度而不是最大通道：最大通道会把紫蓝星云本身读得很亮，
## 实测同一位置亮度 0.293 / 最大通道 0.489 —— 阈值就没法两边通用。
func _ring_luma(img: Image, c: Vector2, r: float) -> float:
	var sum := 0.0
	var n := 0
	for s in 180:
		var a := TAU * float(s) / 180.0
		for k in 5:
			var rr := r * (0.92 + 0.02 * float(k))
			var x := int(c.x + cos(a) * rr)
			var y := int(c.y + sin(a) * rr)
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var col := img.get_pixel(x, y)
			sum += col.r * 0.299 + col.g * 0.587 + col.b * 0.114
			n += 1
	return sum / float(maxi(n, 1))


func _rects_overlap(a: Rect2, b: Rect2) -> bool:
	if not a.intersects(b):
		return false
	var w: float = minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
	var h: float = minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
	return w * h > 4.0


func _color_dist(a: Color, b: Color) -> float:
	return sqrt((a.r - b.r) * (a.r - b.r) + (a.g - b.g) * (a.g - b.g) + (a.b - b.b) * (a.b - b.b))


## 取某个门当前所在的整数槽位
func _slot_of(map: Control, g: Dictionary) -> int:
	return int(round(map._slot_pos(g))) % maxi(map._gates.size(), 1)


func _settle(map: Control) -> void:
	for _i in 90:
		await get_tree().process_frame
		if map._at_rest():
			break
	for _i in 3:
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	var map: Control = MapScript.new()
	map.size = Vector2(1082, 532)
	add_child(map)
	for i in 6:
		await get_tree().process_frame
	map.setup(WorldDB.DOMAINS)
	await _settle(map)

	# ---------- ① 位面数和门数一致，一个都不能静默丢掉 ----------
	_check(map._gates.size() == WorldDB.DOMAINS.size(),
		"① 位面数和门数一致", "%d 界 / %d 门" % [WorldDB.DOMAINS.size(), map._gates.size()])

	# ---------- ② 底图必须已经没有画死的门（反向判据，防的是「新底图没落盘」）----------
	var tex: Texture2D = UIKit.ui_texture(UIKit.TEX_BG_REALM_SELECT)
	_check(tex != null, "② 能读到底图纹理", String(UIKit.TEX_BG_REALM_SELECT))
	if tex == null:
		_done()
		return
	var img := tex.get_image()
	_check(img != null and not img.is_empty(), "② 底图像素可读",
		"%dx%d" % [img.get_width(), img.get_height()])
	if img == null or img.is_empty():
		_done()
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	# 判据：环带亮度必须远低于「画着门」的水位。实测四个槽位
	#   新底图（纯星云） 0.293 / 0.270 / 0.197 / 0.214
	#   旧底图（画死门） 0.586 / 0.719 / 0.661 / 0.653
	# 中间隔着一条 0.45 的空档，所以用绝对水位而不是「环上比环外亮」：
	# 中央那格的位置正好压在旋臂的内环上，星云自己就会亮出一圈落差，
	# 拿落差当判据会把干净的底图误判成「门还没抠掉」。
	var still_painted: Array[String] = []
	for s in map.SLOTS:
		var c: Vector2 = s.center
		var r := float(s.radius)
		var on_ring := _ring_luma(img, c, r)
		if on_ring > 0.45:
			still_painted.append("%s 环上 %.3f > 0.45（像是画死的门）" % [str(c), on_ring])
	_print_row("② 四扇门不再画死在底图里（否则代码环会和它重影）", still_painted)

	# ---------- ③ 每扇门都要真的挂上自己的 sprite ----------
	var no_tex: Array[String] = []
	for g in map._gates:
		var sprite: TextureRect = g.sprite
		if sprite.texture == null:
			no_tex.append(String(g.domain_id))
	_print_row("③ 四张光门 sprite 都加载到了（缺图不能静默变成空心环）", no_tex)

	# ---------- ④ 前排三格 + 深处一格 ----------
	var depth_ids: Array[String] = []
	var slots_here: Array[int] = []
	for g in map._gates:
		slots_here.append(_slot_of(map, g))
		if bool(g.in_depth):
			depth_ids.append(String(g.domain_id))
	_check(depth_ids.size() == 1, "④ 恰好一格在深处（前排三格）", str(depth_ids))
	_check(slots_here.size() == 4 and slots_here.has(SLOT_C) and slots_here.has(SLOT_L)
		and slots_here.has(SLOT_R), "④ 前排中央/左/右都有门", str(slots_here))

	# ---------- ⑤ 深处那格不可点，也不进选中态 ----------
	var clickable_depth: Array[String] = []
	for g in map._gates:
		if bool(g.in_depth):
			var hit: Button = g.hit
			if hit.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				clickable_depth.append(String(g.domain_id))
			_check(String(g.domain_id) != map._selected_id,
				"⑤ 深处那格不占选中态（信息栏跟着前排走）", String(g.domain_id))
	_print_row("⑤ 深处那格的命中圈是 IGNORE（点了没反应，不是点了报错）", clickable_depth)

	# ---------- ⑥ 开局排布仍等于画师原来那张：凡界中央、冲和左、赤霄右、照影深处 ----------
	var expect := {"domain_01": SLOT_C, "domain_02": SLOT_L, "domain_03": SLOT_R, "domain_04": SLOT_D}
	var wrong: Array[String] = []
	for g in map._gates:
		var did := String(g.domain_id)
		if expect.has(did) and _slot_of(map, g) != int(expect[did]):
			wrong.append("%s 在 %d 格，应在 %d 格" % [did, _slot_of(map, g), int(expect[did])])
	_print_row("⑥ 转 0 格时的排布和改版前一致", wrong)

	# ---------- ⑦ 转一格：最左旋进深处、深处旋出到最右，且吸附不留半格 ----------
	var before := {}
	for g in map._gates:
		before[String(g.domain_id)] = _slot_of(map, g)
	var leftmost := ""
	var deepest := ""
	for g in map._gates:
		if _slot_of(map, g) == SLOT_L:
			leftmost = String(g.domain_id)
		if _slot_of(map, g) == SLOT_D:
			deepest = String(g.domain_id)
	map._turn(1)
	await _settle(map)
	_check(map._at_rest(), "⑦ 转完一定吸附到整格（不许停在半路）",
		"rot=%.4f target=%d" % [map._rot, map._rot_target])
	var moved_left := ""
	var moved_deep := ""
	for g in map._gates:
		if _slot_of(map, g) == SLOT_D:
			moved_deep = String(g.domain_id)
		if _slot_of(map, g) == SLOT_R:
			moved_left = String(g.domain_id)
	_check(moved_deep == leftmost, "⑦ 原来最左那格旋进了深处",
		"%s -> %s" % [leftmost, moved_deep])
	_check(moved_left == deepest, "⑦ 原来深处那格旋出到最右",
		"%s -> %s" % [deepest, moved_left])

	# ---------- ⑧ 转一格后选中态仍在前排 ----------
	var sel_in_depth := false
	for g in map._gates:
		if String(g.domain_id) == map._selected_id and bool(g.in_depth):
			sel_in_depth = true
	_check(not sel_in_depth, "⑧ 转一格后选中态仍落在前排三格", String(map._selected_id))

	# ---------- ⑨ 回滑镜像：+1 再 -1 必须回到原来那套排布 ----------
	map._turn(-1)
	await _settle(map)
	var back_ok := true
	var back_detail: Array[String] = []
	for g in map._gates:
		var did := String(g.domain_id)
		if _slot_of(map, g) != int(before[did]):
			back_ok = false
			back_detail.append("%s %d->%d" % [did, int(before[did]), _slot_of(map, g)])
	_check(back_ok, "⑨ 回滑一格能镜像回到原排布（不许只能单向）", str(back_detail))

	# ---------- ⑩ 铭牌：一律在自家环的正下方，互不叠、不压别人的门 ----------
	var clash: Array[String] = []
	var plate_ctls: Array[Rect2] = []
	for g in map._gates:
		plate_ctls.append(Rect2(g.plaque.global_position, g.plaque.size))
	for i in range(plate_ctls.size()):
		for j in range(i + 1, plate_ctls.size()):
			if _rects_overlap(plate_ctls[i], plate_ctls[j]):
				clash.append("铭牌 %d 与 %d 叠住" % [i, j])
	for i in range(map._gates.size()):
		var gg: Dictionary = map._gates[i]
		var pc: Vector2 = gg.plaque.global_position + gg.plaque.size * 0.5
		if pc.y < (gg.center as Vector2).y:
			clash.append("铭牌 %d 没挂在环下方" % i)
		for j in range(map._gates.size()):
			if i == j:
				continue
			var og: Dictionary = map._gates[j]
			var d: float = (og.center as Vector2).distance_to(pc)
			if d < float(og.radius) * 0.92:
				clash.append("铭牌 %d 压进了门 %d 的环内 (%.0f < %.0f)" % [i, j, d, float(og.radius) * 0.92])
	_print_row("⑩ 铭牌统一挂环正下方、互不叠、不压别人的门", clash)

	# ---------- ⑩b 铭牌只剩两行字：不许再有底板、不许再有红印 ----------
	# 2026-11-06 用户「不要下面的框和红色方块」。那枚印还有第二重代价：
	# TextureRect 默认 EXPAND_KEEP_SIZE，96² 的图会把 PanelContainer 顶到 96 高，
	# 框就跟着铭牌一起变大 —— 所以这条判据同时守"铭牌没被顶高"。
	var plate_bad: Array[String] = []
	for i in range(map._gates.size()):
		var pg: Dictionary = map._gates[i]
		var pp: PanelContainer = pg.plaque
		if pp.get_child_count() != 1:
			plate_bad.append("铭牌 %d 有 %d 个子节点（只该有一个 vbox）" % [i, pp.get_child_count()])
		var sb := pp.get_theme_stylebox("panel")
		if sb != null and not (sb is StyleBoxEmpty):
			plate_bad.append("铭牌 %d 又长出底板（%s）" % [i, sb.get_class()])
		if pp.size.y > 60.0:
			plate_bad.append("铭牌 %d 高 %.0f（被什么撑大了？）" % [i, pp.size.y])
	_print_row("⑩b 铭牌只有描边文字：无底板、无红印、没被撑高", plate_bad)

	# ---------- ⑪ 四扇门主题色要彼此分得开 ----------
	var dup: Array[String] = []
	for i in range(map._gates.size()):
		for j in range(i + 1, map._gates.size()):
			var dd := _color_dist(map._gates[i].accent, map._gates[j].accent)
			if dd < 0.16:
				dup.append("%d↔%d 距离 %.3f" % [i, j, dd])
	_print_row("⑪ 四扇门主题色互不重复", dup)

	# ---------- ⑫ 前排命中圈要盖住门；sprite 边长按实测环半径折算 ----------
	var miss: Array[String] = []
	for g in map._gates:
		if bool(g.in_depth):
			continue
		var hit: Button = g.hit
		var hr := hit.size.x * 0.5
		if hr < float(g.radius) * 0.86:
			miss.append("%s 命中 %.0f < 门 %.0f" % [g.domain_id, hr, float(g.radius)])
		var side: float = map._sprite_side(g, float(g.radius))
		var ring_px := float(MapScript.GATE_RING_PX.get(String(g.domain_id), 0.0))
		if ring_px <= 0.0:
			miss.append("%s 没有实测环半径，走的是兜底值" % g.domain_id)
		elif absf(side * ring_px / MapScript.GATE_SPRITE_PX - float(g.radius)) > 1.0:
			miss.append("%s 折算后环半径偏 %.1f px" % [g.domain_id, side * ring_px / MapScript.GATE_SPRITE_PX - float(g.radius)])
	_print_row("⑫ 前排点击范围盖住门，且 sprite 环半径按实测值折算", miss)

	# ---------- ⑬ 第 5 个位面出现时不许没有门 ----------
	var fake: Array = WorldDB.DOMAINS.duplicate()
	fake.append({"domain_id": "domain_05", "name": "试界", "boss_ids": []})
	map.setup(fake)
	await _settle(map)
	_check(map._gates.size() == 5, "⑬ 位面再多也不会静默掉门", "%d 门" % map._gates.size())
	var depth5 := 0
	var seen: Array[int] = []
	for g in map._gates:
		if bool(g.in_depth):
			depth5 += 1
		seen.append(_slot_of(map, g))
	_check(depth5 == 1, "⑬ 五格时仍然只有一格在深处", "%d 格深处 槽位=%s" % [depth5, str(seen)])
	var spread := 0.0
	for g in map._gates:
		spread += (g.center as Vector2).length()
	_check(spread > 0.0, "⑬ 超出登记槽位的那格真的排开了", "%.0f" % spread)

	_done()


func _done() -> void:
	print("RESULT passes=%d fails=%d" % [_passes, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
