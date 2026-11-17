extends Node
## 全局「按住拖动滚动」自检（2026-11-13 用户要求：所有可滑动界面都能用鼠标拖着滚）
## 用法：godot --headless --path . --quit-after 200000 res://tools/probe_drag_scroll.tscn -- --no-save
##
## ⚠ 引擎本身不吃鼠标拖动，也不用手指拖 ScrollContainer（实测五种 mouse_filter 组合
##   + force_pass_scroll + ScreenDrag 全都不动），所以这套行为完全是 ScrollDrag 提供的。

var _passes := 0
var _fails: Array = []
var _sc: ScrollContainer = null
var _hits := 0
var _hits2 := 0
var _hits3 := 0
var _entered: Array = []
var _pad_was := false
var _spy: MotionSpy = null


## 只数「漏到 _unhandled_input 的**按住不放那一路**鼠标移动」，
## 用来量 ScrollDrag 吞没得干不干净。不带按钮掩码的那发是收尾重算悬停用的，
## 本来就该让 GUI 收到，所以不计。
class MotionSpy extends Node:
	var moves := 0

	func _unhandled_input(event: InputEvent) -> void:
		var mm := event as InputEventMouseMotion
		if mm != null and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
			moves += 1


func _on_row_entered(who: StringName) -> void:
	_entered.append(String(who))


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_spy = MotionSpy.new()
	_spy.name = "MotionSpy"
	add_child(_spy)
	print("\n########## 拖动滚动 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _run() -> void:
	await _frames(2)
	_check(get_tree().root.get_node_or_null("ScrollDrag") != null,
		"ScrollDrag 已注册成 autoload")

	# ===== 1. 最简列表：拖 120px 应该滚起来 =====
	_build_list(Vector2(300, 200), 40, 34.0)
	await _frames(3)
	_check(_sc.get_v_scroll_bar().max_value > 0.0,
		"内容确实超出（有东西可滚）", str(_sc.get_v_scroll_bar().max_value))
	_sc.scroll_vertical = 0
	await _frames(2)
	await _drag(Vector2(150, 100), Vector2(150, -20))
	_check(_sc.scroll_vertical > 60, "鼠标按住往上拖 → 列表跟着滚", str(_sc.scroll_vertical))

	# ===== 2. 阈值之内不算拖 =====
	_sc.scroll_vertical = 0
	await _frames(2)
	await _drag(Vector2(150, 100), Vector2(150, 96))
	_check(_sc.scroll_vertical == 0, "只挪 4px（阈值内）不动滚动条", str(_sc.scroll_vertical))

	# ===== 3. 拖完不要把按钮点着（含「按下外观不残留」）=====
	# ⚠ 必须挑「起拖那一点真正压着的那颗按钮」。原来这里固定取第 5 行，
	#   而起拖点 (150,100) 压的是第 2 行 —— 那两条断言量的根本不是同一颗按钮，
	#   是假绿（M2/M3 变异跑下去完全不红才发现的）。
	_sc.scroll_vertical = 0
	await _frames(3)
	var col := _sc.get_child(0) as VBoxContainer
	_hits = 0
	var row_btn: Button = null
	for c in col.get_children():
		if c is Button and (c as Control).get_global_rect().has_point(Vector2(150, 100)):
			row_btn = c as Button
	_check(row_btn != null, "起拖点确实压在某一行的按钮上")
	row_btn.pressed.connect(func() -> void: _hits += 1)
	await _drag(Vector2(150, 100), Vector2(150, -60))
	_check(_hits == 0, "从按钮上起拖 → 按钮不会被误点", str(_hits))
	# 吞掉 release 后画面会不会还挂着「按下」的样子 —— 这条**不在这里判**：
	# Button.button_pressed 是 toggle 状态位，非 toggle 按钮的绘制根本不读它，
	# 读它只会得到假红。真正的判据是像素：tools/tmp_drag_press_shot.gd 实测
	# 「按住时 vs 干净」99.9% 像素不同（按下态确实画得出来）、
	# 「拖完 vs 干净」0/10200 像素不同（外观完全干净）。
	# 这里只守得住可查询的那一半：hover 必须被重算掉。
	_check(not row_btn.is_hovered(), "拖完重算悬停：那颗按钮不再挂着 hover/按下外观",
		"is_hovered=%s" % row_btn.is_hovered())
	_check(_sc.scroll_vertical > 60, "拖动仍然生效", str(_sc.scroll_vertical))

	# ===== 3b. 拖到边界（内容已经动不了）再松手，仍然不能算点这一行 =====
	# 上面 3 那发松手落在按钮外面，Godot 自己按位置判定就不点 —— 那条不靠 release 吞不吞。
	# 真正吃这条的是「拖到底还想再拖」：内容不动、光标还在同一颗按钮上，
	# 不吞这发 release 就会白点一下。
	_sc.scroll_vertical = 0
	await _frames(3)
	_hits2 = 0
	var edge_btn: Button = col.get_child(1) as Button
	var edge_c := edge_btn.get_global_rect().get_center()
	edge_btn.pressed.connect(func() -> void: _hits2 += 1)
	await _drag(edge_c, edge_c + Vector2(0, 12))
	_check(_sc.scroll_vertical == 0, "边界上往下拖内容动不了（这一发是给 3b 用的前提）",
		str(_sc.scroll_vertical))
	_check(edge_btn.get_global_rect().has_point(edge_c + Vector2(0, 12)),
		"前提：这一发的松手点还在同一颗按钮里",
		str(edge_btn.get_global_rect()))
	_check(_hits2 == 0, "拖到底拖不动了再松手 → 也不算点这一行", str(_hits2))

	# ===== 3c. 拖动这一路不要把经过的行逐亮点起来 =====
	# 中途的 motion 全被吞掉，GUI 不知道光标走过 0~4 行。
	# 允许的那一次是**按下那一拍**：Godot 要先算一次 mouse_over 才知道按在谁身上，
	# 亮的必须是起拖点压着的那一行，别的行一律不许亮。
	_sc.scroll_vertical = 0
	await _frames(3)
	_entered.clear()
	for c in col.get_children():
		if c is Button:
			(c as Button).mouse_entered.connect(_on_row_entered.bind((c as Button).name))
	await _drag(Vector2(150, 100), Vector2(150, -60))
	await _frames(3)
	var bad: Array = _entered.filter(func(n): return n != String(row_btn.name))
	_check(bad.is_empty(), "拖动的这一路：除了起拖那一行，经过的行都没亮",
		"亮了 %s" % str(_entered))

	# ===== 3d. 边界上拖动：内容跟不了手，中间的行也不许一路高亮 =====
	# 3c 那条测不出「吞 motion」：正常拖动时内容 1:1 跟着光标走，
	# 同一行始终在光标底下，吞不吞 hover 都只有一行（M3 就是这么个情况）。
	# 已经在顶部再往下拖，内容动不了、光标却要跨过 2/3 行 —— 这时候
	# 中途那发 motion 没吞掉就会一行一行亮过去。
	# 允许亮的是两个端点：按下那拍 GUI 要先算一次 hover（起拖行），
	# 收尾补的那发无掩码移动落在抬手行上（那是给光标真实位置的正当回执）。
	# ===== 3d. 拖动不漏给 _unhandled_input =====
	# ⚠ 这一条必须用**只有 Label 的列表**量。上一版用按钮行，Button 是 STOP 过滤，
	#   GUI 自己就把 motion 吃掉了 —— ScrollDrag 那发 set_input_as_handled 加不加
	#   都看不出差别（M3 就是这么个不红法）。Label 默认 IGNORE，
	#   这一路根本没有会吃鼠标的控件，能挡住它的只有 ScrollDrag。
	var lbl_sc := ScrollContainer.new()
	lbl_sc.size = Vector2(300, 400)
	lbl_sc.custom_minimum_size = Vector2(300, 400)
	lbl_sc.position = Vector2(700, 100)
	add_child(lbl_sc)
	var lbl_col := VBoxContainer.new()
	lbl_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(40):
		var lb := Label.new()
		lb.text = "纯文本 %d" % i
		lb.custom_minimum_size = Vector2(280, 34)
		lbl_col.add_child(lb)
	lbl_sc.add_child(lbl_col)
	await _frames(4)
	lbl_sc.scroll_vertical = 0
	await _frames(2)
	# 前提：这一路真没有吃鼠标的控件，否则下面那条 0 说明不了任何事
	_check(lbl_col.get_child(0).mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"前提：量具那一区的行是 IGNORE 的纯文本（GUI 不会自己吃掉 motion）",
		str(lbl_col.get_child(0).mouse_filter))
	_spy.moves = 0
	await _drag(Vector2(850, 300), Vector2(850, 180))
	await _frames(3)
	_check(lbl_sc.scroll_vertical > 60, "纯文本列表照拖（量具确实在滚）",
		str(lbl_sc.scroll_vertical))
	_check(_spy.moves == 0, "拖动这一路的 motion 不漏进 _unhandled_input", str(_spy.moves))
	# 对照组：同一套事件在不接管的地方（空白处）必须漏下去，
	# 不然上面那个「0」可能只是量具根本没在数
	_spy.moves = 0
	await _drag(Vector2(1150, 620), Vector2(1150, 500))
	await _frames(3)
	_check(_spy.moves > 0, "对照：不接管的地方 motion 照常进 _unhandled_input（量具是活的）",
		str(_spy.moves))
	lbl_sc.queue_free()
	await _frames(3)

	# ===== 4. 单纯点一下（不拖）仍然要能点着 =====
	# 上一轮已经滚到 162，(150,100) 上早不是那颗按钮了 —— 先复位并现算按钮中心
	_sc.scroll_vertical = 0
	await _frames(3)
	var tap_btn: Button = (_sc.get_child(0) as VBoxContainer).get_child(2) as Button
	# 上一节那颗按钮的回调还挂着（它就是第 2 行），所以要单独数自己的计数
	_hits3 = 0
	tap_btn.pressed.connect(func() -> void: _hits3 += 1)
	_click(tap_btn.get_global_rect().get_center())
	await _frames(3)
	_check(_hits3 == 1, "不动手只点一下 → 按钮照常响应", str(_hits3))

	# ===== 5. 滚动条本体交回引擎：落在滚动条上不接管 =====
	_sc.scroll_vertical = 0
	await _frames(2)
	var bar := _sc.get_v_scroll_bar()
	var bar_c := bar.get_global_rect().get_center()
	_mouse(true, bar_c)
	await get_tree().process_frame
	var sd := get_tree().root.get_node_or_null("ScrollDrag")
	_check(sd != null and sd.get("_target") == null,
		"落在滚动条上 → ScrollDrag 不接管（留给引擎）",
		str(sd.get("_target")) if sd != null else "no node")
	for i in range(4):
		_motion(bar_c - Vector2(0, 20 * (i + 1)))
		await get_tree().process_frame
	_mouse(false, bar_c - Vector2(0, 80))
	await _frames(2)
	_check(_sc.scroll_vertical > 0,
		"滚动条照旧能拖（引擎自己那条路没被堵）", str(_sc.scroll_vertical))

	# ===== 6. 横排列表：左右拖 =====
	_free_all()
	_sc = ScrollContainer.new()
	_sc.size = Vector2(300, 120)
	_sc.custom_minimum_size = Vector2(300, 120)
	_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_sc)
	var row := HBoxContainer.new()
	for i in range(30):
		var b := Button.new()
		b.text = "卡 %d" % i
		b.custom_minimum_size = Vector2(120, 100)
		row.add_child(b)
	_sc.add_child(row)
	await _frames(3)
	_sc.scroll_horizontal = 0
	await _frames(2)
	await _drag(Vector2(150, 60), Vector2(-60, 60))
	_check(_sc.scroll_horizontal > 60, "横向列表跟着左右拖滚动", str(_sc.scroll_horizontal))

	# ===== 7. 嵌套：里层优先 =====
	# ⚠ 里层必须摆在**外层可视区域内**，否则两点都不成立：
	#   原先 40 行标签之后才挂里层，里层落在 y≈1520（外层矩形之外），
	#   `_container_at` 本来就只剩里层一个候选 —— 「里层优先」是假的，
	#   M9（外层抢走）怎么改都绿。现在里层夹在第 2、3 行标签之间。
	_free_all()
	var outer := ScrollContainer.new()
	outer.size = Vector2(600, 400)
	outer.custom_minimum_size = Vector2(600, 400)
	add_child(outer)
	var outer_col := VBoxContainer.new()
	for i in range(2):
		var l0 := Label.new()
		l0.text = "外层 上 %d" % i
		l0.custom_minimum_size = Vector2(560, 34)
		outer_col.add_child(l0)
	outer.add_child(outer_col)
	var inner := ScrollContainer.new()
	inner.custom_minimum_size = Vector2(280, 160)
	outer_col.add_child(inner)
	var inner_col := VBoxContainer.new()
	for i in range(30):
		var b2 := Button.new()
		b2.text = "内层 %d" % i
		b2.custom_minimum_size = Vector2(260, 30)
		inner_col.add_child(b2)
	inner.add_child(inner_col)
	for i in range(38):
		var l1 := Label.new()
		l1.text = "外层 %d" % i
		l1.custom_minimum_size = Vector2(560, 34)
		outer_col.add_child(l1)
	await _frames(4)
	outer.scroll_vertical = 0
	inner.scroll_vertical = 0
	await _frames(2)
	var inner_c := inner.get_global_rect().get_center()
	# 前提：这一点**同时**落在外层和里层的矩形里，两个都是候选，深浅判定才有活干
	_check(outer.get_global_rect().has_point(inner_c)
			and inner.get_global_rect().has_point(inner_c)
			and outer.get_v_scroll_bar().max_value > 0.0,
		"前提：里层确实在外层可视区内，两层都可滚",
		"外 max=%s" % outer.get_v_scroll_bar().max_value)
	# 再把「取到的是哪一个」按身份钉死：光看谁滚了，两层同时能滚时看不出来
	var sd5 = get_tree().root.get_node_or_null("ScrollDrag")
	_check(sd5.call("_container_at", inner_c) == inner,
		"嵌套解析到的是里层那个容器（身份判定）",
		str(sd5.call("_container_at", inner_c)))
	await _drag(inner_c, inner_c - Vector2(0, 60))
	_check(inner.scroll_vertical > 20 and outer.scroll_vertical == 0,
		"嵌套列表：里层优先，外层不跟着乱滚",
		"内=%d 外=%d" % [inner.scroll_vertical, outer.scroll_vertical])

	# ===== 8. 暂停态也要能拖（面板都是 pause 整棵树）=====
	_free_all()
	_build_list(Vector2(300, 200), 40, 34.0)
	await _frames(3)
	get_tree().paused = true
	_sc.scroll_vertical = 0
	await _frames(2)
	await _drag(Vector2(150, 100), Vector2(150, -40))
	_check(_sc.scroll_vertical > 20, "面板暂停态照样能拖", str(_sc.scroll_vertical))
	get_tree().paused = false

	# ===== 9. 后门：meta 关掉就不接管 =====
	_free_all()
	_build_list(Vector2(300, 200), 40, 34.0)
	await _frames(3)
	_sc.set_meta("no_drag_scroll", true)
	_sc.scroll_vertical = 0
	await _frames(2)
	await _drag(Vector2(150, 100), Vector2(150, -60))
	_check(_sc.scroll_vertical == 0,
		"标了 no_drag_scroll 的容器不接管", str(_sc.scroll_vertical))
	_sc.remove_meta("no_drag_scroll")

	# ===== 9a2. 后门也可以只标在「自己吃拖拽的那颗卡」上 =====
	# 华彩卡（HoloCardView）和棋坛手牌就是这种：列表整体要能拖滚，
	# 但不能抢它们自己的「按住拖」。所以容器不标，只标那张卡。
	_free_all()
	_build_list(Vector2(300, 200), 40, 34.0)
	await _frames(3)
	var col9 := _sc.get_child(0) as VBoxContainer
	var marked := col9.get_child(1) as Button
	marked.set_meta("no_drag_scroll", true)
	var sd7 = get_tree().root.get_node_or_null("ScrollDrag")
	_mouse(true, marked.get_global_rect().get_center())
	await get_tree().process_frame
	_check(sd7.get("_target") == null, "标了 no_drag_scroll 的那颗控件自己：不接管",
		str(sd7.get("_target")))
	_mouse(false, marked.get_global_rect().get_center())
	await _frames(2)
	var other := col9.get_child(3) as Button     # 第 5 行在 200px 高的视口外，要挑视口内的
	_mouse(true, other.get_global_rect().get_center())
	await get_tree().process_frame
	_check(sd7.get("_target") == _sc, "同一列表的别处照常接管（后门只对那颗控件生效）",
		str(sd7.get("_target")))
	_mouse(false, other.get_global_rect().get_center())
	await _frames(2)

	# ===== 9b. 拖拽源优先：纸签上砧那类自己实现 _get_drag_data 的控件要让路 =====
	_free_all()
	_sc = ScrollContainer.new()
	_sc.size = Vector2(300, 200)
	_sc.custom_minimum_size = Vector2(300, 200)
	add_child(_sc)
	var dcol := VBoxContainer.new()
	for i in range(40):
		var src := DragSrc.new()
		src.text = "纸签 %d" % i
		src.custom_minimum_size = Vector2(280, 34)
		dcol.add_child(src)
	_sc.add_child(dcol)
	await _frames(4)
	_sc.scroll_vertical = 0
	await _frames(2)
	DragSrc.grab_count = 0
	var sd2 := get_tree().root.get_node_or_null("ScrollDrag")
	_mouse(true, Vector2(150, 100))
	await get_tree().process_frame
	_check(sd2 != null and sd2.get("_target") == null,
		"落在拖拽源上 → ScrollDrag 直接让路",
		str(sd2.get("_target")) if sd2 != null else "no node")
	for i in range(6):
		_motion(Vector2(150, 100) - Vector2(0, 10 * (i + 1)))
		await get_tree().process_frame
	_mouse(false, Vector2(150, 40))
	await _frames(3)
	# 让路判据本身。Godot 到底哪一拍去调 _get_drag_data 是引擎的事，
	# 那条由 probe_match_drag / 锻造拖拽在窗口化下守着，这里不冒充证据
	# 直接拿实例判：脚本覆盖了 _get_drag_data 的算拖拽源，普通按钮不算
	var plain_btn := Button.new()
	add_child(plain_btn)
	await get_tree().process_frame
	var src_first = (dcol.get_child(0) if dcol.get_child_count() > 0 else null)
	_check(bool(sd2.call("_is_drag_source", src_first))
			and not bool(sd2.call("_is_drag_source", plain_btn)),
		"脚本覆盖了 _get_drag_data 的控件被认成拖拽源，普通按钮不算",
		"src=%s plain=%s" % [sd2.call("_is_drag_source", src_first),
			sd2.call("_is_drag_source", plain_btn)])
	plain_btn.queue_free()
	_check(_sc.scroll_vertical == 0, "拖拽源上起拖不接管滚动（锻造台纸签不被抢）",
		str(_sc.scroll_vertical))

	# ===== 9c. 刚好铺满的内容不算「有得滚」：不该接管，更不该吞掉点击 =====
	_free_all()
	_sc = ScrollContainer.new()
	_sc.size = Vector2(300, 120)
	_sc.custom_minimum_size = Vector2(300, 120)
	_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_sc)
	var fit_col := VBoxContainer.new()
	var fit_btn := Button.new()
	fit_btn.text = "唯一一行"
	fit_btn.custom_minimum_size = Vector2(300, 120)
	fit_col.add_child(fit_btn)
	_sc.add_child(fit_col)
	await _frames(4)
	var fit_bar = _sc.get_v_scroll_bar()
	var sd4 = get_tree().root.get_node_or_null("ScrollDrag")
	_mouse(true, Vector2(150, 60))
	await get_tree().process_frame
	_check(fit_bar != null and fit_bar.max_value <= fit_bar.page + 0.5
			and sd4.get("_target") == null,
		"内容刚好铺满（max==page）→ 不接管",
		"max=%s page=%s target=%s" % [fit_bar.max_value, fit_bar.page, sd4.get("_target")])
	_hits = 0
	fit_btn.pressed.connect(func() -> void: _hits += 1)
	_mouse(false, Vector2(150, 60))
	await _frames(3)
	_check(_hits == 1, "铺满的列表里点击照常生效", str(_hits))

	# ===== 10. 真面板：万界塔 20 层列表拖得动 =====
	_free_all()
	await _real_panel()

	# ===== 11. 触屏：摇杆区里的合成鼠标不接管 =====
	# 手机上「推摇杆」合成的那套鼠标事件不能把底下的面板滚走。
	# ⚠ 这里全程不调 VirtualPad.set_enabled()：它会写 user://touch_ui.json，
	#   把玩家的触屏开关改掉（PC 版开机满屏虚拟键）。只改运行时字段，收尾还原。
	_pad_was = bool(VirtualPad.is_touch_enabled())
	VirtualPad.set("_has_touchscreen", true)
	VirtualPad.enabled = true
	VirtualPad.call("_apply_enabled")
	VirtualPad.set_context("realm")
	await _frames(3)
	# 摇杆区按 VirtualPad 自己算出来的矩形取点，别照抄常量：
	# headless 下 _safe_rect() 量到 1280×1280，硬写的 (240,500) 根本不在区里
	var zone: Rect2 = VirtualPad.call("_stick_zone_rect")
	var zone_c := zone.position + zone.size * Vector2(0.35, 0.08)
	_free_all()
	_build_list(Vector2(300, 200), 40, 34.0)
	_sc.position = zone_c - Vector2(150, 100)
	await _frames(4)
	_check(zone.has_point(zone_c) and _sc.get_global_rect().has_point(zone_c),
		"前提：这个点同时在摇杆区和列表里", "区=%s 点=%s 列表=%s" % [
			zone, zone_c, _sc.get_global_rect()])
	var sd6 = get_tree().root.get_node_or_null("ScrollDrag")
	_sc.scroll_vertical = 0
	await _frames(2)
	_mouse(true, zone_c)
	await get_tree().process_frame
	_check(sd6.get("_target") == null, "摇杆区里按下 → ScrollDrag 不接管",
		str(sd6.get("_target")))
	for i in range(6):
		_motion(zone_c - Vector2(0, 12 * (i + 1)))
		await get_tree().process_frame
	_mouse(false, zone_c - Vector2(0, 72))
	await _frames(3)
	_check(_sc.scroll_vertical == 0, "摇杆区里拖 72px：底下的列表一格都没滚",
		str(_sc.scroll_vertical))
	VirtualPad.call("_release_all")
	VirtualPad.set("enabled", _pad_was)
	VirtualPad.set("_has_touchscreen", false)
	VirtualPad.call("_apply_enabled")
	print("  触屏开关已还原为跑之前的 ", _pad_was, "（全程没写 touch_ui.json）")


func _build_list(size: Vector2, rows: int, h: float) -> void:
	_sc = ScrollContainer.new()
	_sc.size = size
	_sc.custom_minimum_size = size
	_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_sc)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(rows):
		var b := Button.new()
		b.name = "行 %d" % i
		b.text = "行 %d" % i
		b.custom_minimum_size = Vector2(size.x - 20, h)
		col.add_child(b)
	_sc.add_child(col)


func _free_all() -> void:
	for c in get_children():
		if c == _spy:
			continue     # 量具不能被自己清掉
		c.queue_free()
	_sc = null
	for i in range(6):
		await get_tree().process_frame


func _mouse(pressed: bool, pos: Vector2) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.position = pos
	mb.global_position = pos
	get_viewport().push_input(mb, true)


func _motion(pos: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(mm, true)


func _drag(from: Vector2, to: Vector2) -> void:
	_mouse(true, from)
	await get_tree().process_frame
	var steps := 6
	for i in range(steps):
		_motion(from.lerp(to, float(i + 1) / steps))
		await get_tree().process_frame
	_mouse(false, to)
	await get_tree().process_frame
	await get_tree().process_frame


func _click(at: Vector2) -> void:
	_motion(at)
	_mouse(true, at)
	await get_tree().process_frame
	_mouse(false, at)
	await get_tree().process_frame


## 真面板：万界图鉴左列 + 内容区都该拖得动
func _real_panel() -> void:
	# 显式标注类型：`.new()` 返回 Variant，用 := 推断会被本项目的编译设置当错误
	var panel: Node = (load("res://scripts/ui/panels/tower_panel.gd") as GDScript).new()
	add_child(panel)
	await _frames(4)
	panel.call("open")
	await _frames(8)
	var scrollers: Array = []
	_collect_scrollers(panel, scrollers)
	_check(not scrollers.is_empty(), "万界塔面板里找到滚动区", str(scrollers.size()))
	# 「有得滚」= max_value（内容长）> page（可视长）。只看 max_value>0 会把
	# 刚好铺满的内容误判成可滚（指引书面板就是这么假绿的）
	var scrollable_n := 0
	for sc in scrollers:
		var vb = sc.get_v_scroll_bar()
		if vb != null and vb.max_value > vb.page + 0.5:
			scrollable_n += 1
	_check(scrollable_n > 0, "面板里确实有超出可视高度的列表（有东西可滚）", str(scrollable_n))
	var scrolled_any := 0
	for sc in scrollers:
		if sc.get_v_scroll_bar().max_value <= 0.0:
			continue
		var before: int = sc.scroll_vertical
		var c: Vector2 = sc.get_global_rect().position 			+ Vector2(sc.size.x * 0.5, sc.size.y * 0.6)
		var sd3 = get_tree().root.get_node_or_null("ScrollDrag")
		var resolved = sd3.call("_container_at", c)
		print("  DIAG 区=", sc.get_global_rect(), " max=", sc.get_v_scroll_bar().max_value,
			" 点=", c, " 解析=", resolved, " 挡路=", sd3.call("_blocks_drag", c))
		await _drag(c, c - Vector2(0, 90))
		if sc.scroll_vertical != before:
			scrolled_any += 1
	_check(scrolled_any > 0, "真面板（万界塔 20 层列表）拖得动",
		"%d 个可滚区里 %d 个动了" % [scrollers.size(), scrolled_any])
	panel.call("close")
	await _frames(4)


## 一个最小的拖拽源：脚本里覆盖了 _get_drag_data，ScrollDrag 就该让路给它
class DragSrc extends Button:
	static var grab_count := 0

	func _get_drag_data(_at: Vector2) -> Variant:
		DragSrc.grab_count += 1
		return null


func _collect_scrollers(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is ScrollContainer:
			out.append(c)
		_collect_scrollers(c, out)
