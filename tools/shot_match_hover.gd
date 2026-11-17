extends Node
## 卡面悬停视差 / 切档的**端到端**验证（2026-11-04 用户报「鼠标移动时卡面没有动态效果」）
##
## 结构探针只能证明"标志位对了"（HoloCardView 是 PASS、hover_only 开了），
## 证明不了画面真的动了。这条把鼠标移到卡面左缘拍一张、再移到右缘拍一张，
## 直接量两张图的像素差 —— 视差没跑起来就是 0。
##
## 同时守住另一头：加了悬停之后**点击必须还在**（否则选不了牌），
## 以及切档按钮按下去画面真的换了图。
##
## 用法：godot --path . --resolution 1280x720 res://tools/shot_match_hover.tscn -- --no-save

var _passes := 0
var _fails: Array = []
var _arena: Node


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _motion(at: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	get_viewport().push_input(m)


func _click(at: Vector2) -> void:
	_motion(at)
	# ⚠ motion 与 press 之间必须过一帧：Godot 的拾取在下一轮 _gui_input 分发时
	#   才把控件标记成 under_mouse，同一帧里直接 push 按下会被按钮当"从别处抢到的按下"丢掉。
	#   （第一版就是这里不稳，同一个坐标点两次、只有第二次中。）
	await get_tree().process_frame
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.button_mask = MOUSE_BUTTON_MASK_LEFT
	d.position = at
	d.global_position = at
	get_viewport().push_input(d)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = at
	u.global_position = at
	get_viewport().push_input(u)
	await get_tree().process_frame
	await get_tree().process_frame


## 抓一帧并裁出矩形（屏幕像素）
func _grab_rect(r: Rect2) -> Image:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return null
	var x := clampi(int(r.position.x), 0, img.get_width() - 2)
	var y := clampi(int(r.position.y), 0, img.get_height() - 2)
	var w := mini(int(r.size.x), img.get_width() - x)
	var h := mini(int(r.size.y), img.get_height() - y)
	if w < 8 or h < 8:
		return null
	return img.get_region(Rect2i(x, y, w, h))


## 两张同尺寸图的平均绝对差（**0–255**，与所有阈值同量纲）
func _mad(a: Image, b: Image) -> float:
	if a == null or b == null:
		return -1.0
	if a.get_size() != b.get_size():
		return -2.0
	var s := 0.0
	var n := 0
	var changed := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			var d := absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)
			if d > 0.01:
				changed += 1
			s += d
			n += 1
	_changed_pct = 100.0 * float(changed) / maxf(float(n), 1.0)
	return s * 255.0 / maxf(float(n * 3), 1.0)


var _changed_pct := 0.0


## 把按钮子树的类型与 mouse_filter 逐个打出来（0=STOP 1=IGNORE 2=PASS）
func _dump_tree(n: Node, depth: int) -> void:
	var f := ""
	if n is Control:
		f = " filter=%d" % (n as Control).mouse_filter
	var extra := ""
	if n is CardFace:
		extra = " kind=%s paper=%s" % [n.kind(), n.get("_paper_mode")]
	if n is HoloCardView:
		extra = " view=%s target=%s" % [n.get("_view"), n.get("_target_view")]
	print("      ", " ".repeat(depth), n.get_class(), "(", n.name, ")", f, extra)
	for c in n.get_children():
		_dump_tree(c, depth + 1)


func _first_card_rect() -> Rect2:
	var hand: Control = _arena.get("_hand")
	if hand == null or hand.get_child_count() == 0:
		return Rect2()
	var btn := hand.get_child(0) as Control
	if btn == null:
		return Rect2()
	# 只取卡面本体，避开按钮外面的压暗带与名字（那部分本来就不动）。
	# ⚠ 不能 find_child("CardFace")：控件名是自动生成的，按类型找才靠得住。
	var target: Control = btn
	for c in _all_children(btn):
		if c is CardFace:
			target = c as Control
			break
	var g := target.get_global_transform_with_canvas()
	return g * Rect2(Vector2.ZERO, target.size)


func _all_children(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_all_children(c))
	return out


## 分清"事件没到卡面"和"到了但没画"：直接读华彩卡内部的视差状态
func _diag_holo(tag: String) -> void:
	var hand: Control = _arena.get("_hand")
	if hand == null or hand.get_child_count() == 0:
		print("   DIAG[", tag, "] 手牌空")
		return
	var hv := _find_holo(hand.get_child(0))
	if hv == null:
		print("   DIAG[", tag, "] 第一张牌里没有 HoloCardView")
		return
	print("   DIAG[", tag, "] holo filter=", (hv as Control).mouse_filter,
			" _hovered=", hv.get("_hovered"),
			" _target_view=", hv.get("_target_view"),
			" _view=", hv.get("_view"),
			" visible=", hv.visible, " size=", hv.size,
			" global=", hv.global_position,
			" canvas=", hv.get_global_transform_with_canvas().origin)
	# 0=STOP 1=IGNORE 2=PASS
	var btn := _arena.get("_hand").get_child(0) as Control
	print("        按钮 filter=", btn.mouse_filter, " flat=", btn.flat,
			" rect=", btn.get_global_rect(),
			" CardFace filter=", (hv.get_parent() as Control).mouse_filter)
	var vp := get_viewport()
	var img := vp.get_texture().get_image()
	print("        抓取图尺寸=", img.get_size(), " 视口可见矩形=", vp.get_visible_rect(),
			" final_transform=", vp.get_final_transform())
	var mat: ShaderMaterial = hv.get("mat") if hv.get("mat") != null else null
	if mat != null:
		print("        shader view=", mat.get_shader_parameter("view"),
				" art_tex=", mat.get_shader_parameter("art_tex") != null,
				" bg_tex=", mat.get_shader_parameter("bg_tex") != null)
	_dump_tree(btn, 8)


func _find_holo(n: Node) -> Node:
	if n is HoloCardView:
		return n
	for c in n.get_children():
		var r := _find_holo(c)
		if r != null:
			return r
	return null


## 抓到的区域到底有没有内容（全黑就是坐标算错了，别把"抓错地方"当成"没动"）
func _mean_lum(img: Image) -> float:
	if img == null:
		return -1.0
	var s := 0.0
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			s += c.r + c.g + c.b
			n += 3
	return s / maxf(float(n), 1.0)


func _ready() -> void:
	print("\n########## 卡面悬停视差 · 端到端 ##########")
	_arena = (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	_arena.set("player_stage_timeout", 30.0)
	add_child(_arena)

	# 等到选牌阶段真的铺出卡面
	var rect := Rect2()
	for guard in 240:
		await get_tree().process_frame
		rect = _first_card_rect()
		if rect.size.x > 40.0:
			break
	_check(rect.size.x > 40.0, "选牌阶段铺出了卡面", str(rect.size))
	if rect.size.x <= 40.0:
		_finish()
		return

	# 悬停前：鼠标离卡面远远的，让 _view 回到 0
	print("   枚举对照：STOP=%d IGNORE=%d PASS=%d" % [
			Control.MOUSE_FILTER_STOP, Control.MOUSE_FILTER_IGNORE, Control.MOUSE_FILTER_PASS])
	_motion(Vector2(20.0, 700.0))
	for k in 30:
		await get_tree().process_frame
	var idle := _grab_rect(rect)

	# 左缘 → 右缘，各留 0.5 秒给视差插值（lerp 速率 7.5/s）
	_motion(rect.position + Vector2(rect.size.x * 0.10, rect.size.y * 0.35))
	for k in 32:
		await get_tree().process_frame
	var left := _grab_rect(rect)
	_motion(rect.position + Vector2(rect.size.x * 0.90, rect.size.y * 0.65))
	for k in 32:
		await get_tree().process_frame
	var right := _grab_rect(rect)

	var mad_lr := _mad(left, right)
	var mad_idle := _mad(idle, right)
	# 主判据：**事件到底有没有抵达华彩卡**。
	# 只看像素差会被 idle motion 的回弹尾巴骗过去（第一版就是这么假绿的），
	# 所以直接读 _target_view —— 它只有 _gui_input 收到 motion 才会被写。
	var tv_after: Vector2 = _find_holo(_arena.get("_hand").get_child(0)).get("_target_view")
	print("   移右缘之后 _target_view=", tv_after, "（只有鼠标事件真的抵达才会非零）")
	_check(absf(tv_after.x) > 0.3, "鼠标横向移动写进了华彩卡的视差目标（事件抵达）",
			"_target_view=%s" % tv_after)
	print("   卡面矩形 ", rect, "  左缘vs右缘 MAD=%.1f/255  静止vs右缘 MAD=%.1f/255  变化像素 %.1f%%"
			% [mad_lr, mad_idle, _changed_pct])
	print("   抓到的画面亮度（0–255）：静止 %.1f / 左缘 %.1f / 右缘 %.1f"
			% [_mean_lum(idle) * 255.0, _mean_lum(left) * 255.0, _mean_lum(right) * 255.0])
	_diag_holo("移右缘之后")
	_check(mad_lr > 3.0, "鼠标在卡面上横向移动 → 画面真的跟着动（视差在跑）",
			"MAD %.2f（阈值 3.0）" % mad_lr)
	_check(mad_idle > 3.0, "移开再移回来也有差（不是同一帧缓存）", "MAD %.2f" % mad_idle)
	left.save_png("output/hover_left.png")
	right.save_png("output/hover_right.png")
	get_viewport().get_texture().get_image().save_png("output/hover_fullframe.png")
	print("   整帧已存 output/hover_fullframe.png（用它判断是画面没渲染还是裁错了区域）")

	# 点击仍然要落在按钮上：悬停转发不许干扰按下与松开。
	# _toggle_pick 是**切换**，所以点两下应该 1 → 0；两下都没反应才是坏了。
	var hand0: Control = (_arena.get("_hand") as Node).get_child(0) as Control
	var btn_center := hand0.get_global_rect().get_center()
	print("   对照：卡面中心 ", rect.get_center(), " / 按钮中心 ", btn_center)
	await _click(rect.get_center())
	var after_face := (_arena.get("_picked") as Array).size()
	await _click(btn_center)
	var after_btn := (_arena.get("_picked") as Array).size()
	var st_now = _arena.get("_state")
	print("   点卡面中心后已选 ", after_face, " 再点按钮中心后已选 ", after_btn,
			" 阶段=", String(MatchState.PHASE_NAME.get(int(st_now.phase), "?")))
	_check(after_face == 1, "悬停转发打开后点卡面选得中", "已选 %d" % after_face)
	_check(after_btn == 0, "再点同一张取消选中（toggle 仍然成立）", "已选 %d" % after_btn)

	# 切档：按一次「卡面」按钮，同一张牌的画面必须变
	var kind_btn: Button = _arena.get("_kind_btn")
	_check(kind_btn != null, "有切档按钮")
	if kind_btn != null:
		var before_label := kind_btn.text
		var before_img := _grab_rect(rect)
		kind_btn.pressed.emit()
		for k in 24:
			await get_tree().process_frame
		var after_img := _grab_rect(rect)
		var mad_kind := _mad(before_img, after_img)
		print("   ", before_label, " → ", kind_btn.text, "  MAD=%.2f" % mad_kind)
		_check(kind_btn.text != before_label, "按钮文案跟着档位走",
				"%s → %s" % [before_label, kind_btn.text])
		_check(mad_kind > 1.0, "切档之后这张牌画面上变了（不是只改文字）",
				"MAD %.2f" % mad_kind)
		after_img.save_png("output/hover_kind_next.png")

	_finish()


func _finish() -> void:
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  FAIL ", f)
	get_tree().quit(1 if _fails.size() > 0 else 0)
