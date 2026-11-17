class_name CraftStage
extends SystemPanel
## 炼丹炉 / 制符台共用的全屏舞台基类（2026-10-28 推到重做）
##
## 取代旧的「方卷列表页 + 900×500 弹窗炼制层」（CraftPanel + CraftBench）：
##   旧版要先把方子选出来、再把 3 份材料拖满固定炉位，玩家其实只想把药丢进炉子。
##   新版按用户的口径：**一味料 = 一颗成品**，一次只放一味，放几株就最多出几颗，
##   实出数由玩法（控火 / 走笔）决定。
##
## 舞台照锻造台那一套做：SystemPanel 只当 CanvasLayer 壳，内容是一张 1280×720 的画，
## 交互落点写在画上的矩形里（`stage_*_rect()` 由子类给），装饰层一律 MOUSE_FILTER_IGNORE。
##
## 三条硬规则（改代码时别破）：
##   1. **开工前绝不扣料** —— 炉里的株数只是界面状态，只有点「开炉 / 执笔」才 consume_materials
##   2. 拖入别的味 = 整批退回（不消耗），换新的那一味重来；不会出现「拖错就丢材料」
##   3. ESC 先关抽屉 / 先退玩法，玩法进行中不许离炉（材料已经进了炉子）

const VIEW := Vector2(1280.0, 720.0)
const TOP_H := 46.0
## 一炉最多投多少株（炉腹只画这么多枚，再多会挤爆画面）
const MAX_DOSE := 12
## 每成一颗成品累加的熟练度（旧口径是每次成功 +0.05，改按颗数计才不会被批量炼白捡）
const PROF_PER_UNIT := 0.02

const PHASE_LOAD := "load"
const PHASE_PLAY := "play"
const PHASE_DONE := "done"

var _phase := PHASE_LOAD
var _mid: String = ""
var _doses := 0
var _last_mid: String = ""
var _last_doses := 0

var _stage: Control
var _overlay: Control
var _bg: TextureRect
var _glow: Control
var _mouth: Control = null
var _shelf_box: VBoxContainer
var _dose_box: HBoxContainer
var _dose_more: Label
var _dish_icon: TextureRect
var _dish_count: Label
var _title_lbl: Label
var _state_lbl: Label
var _prof_lbl: Label
var _prof_bar: ProgressBar
var _action_btn: Button
var _clear_btn: Button
var _hint_lbl: Label
var _toast: Label
var _toast_tween: Tween
var _drawer: Control = null
var _book_btn: Button = null
var _follow: TextureRect = null
var _follow_name := ""
var _play_layer: Control

var _pending_learn := false


# ===================== 子类覆写 =====================

## "pill" / "talisman"：决定读哪张配方表与哪个熟练度库
func craft_kind() -> String:
	return "pill"


## 舞台底图路径（1792×1008 = 1280×720 × 1.4，按锻造台口径）
func stage_texture() -> String:
	return ""


## 投料口（拖放目标）
func stage_mouth_rect() -> Rect2:
	return Rect2(520.0, 190.0, 240.0, 130.0)


## 药筐 / 皮架（可投材料的来源区）
func stage_shelf_rect() -> Rect2:
	return Rect2(940.0, 150.0, 290.0, 340.0)


## 已投株数的排面中心（炉腹 / 案前）
func stage_dose_center() -> Vector2:
	return Vector2(640.0, 420.0)


## 成品落盘（出丹 / 出符后停在这里）
func stage_dish_rect() -> Rect2:
	return Rect2(150.0, 470.0, 250.0, 150.0)


## 玩法区（火候轨 / 符案画布）
func stage_play_rect() -> Rect2:
	return Rect2(300.0, 500.0, 680.0, 80.0)


## 玩法控件（子类自己 new，基类塞进 stage_play_rect 并管理显隐）
func _build_play() -> Control:
	return null


## 单株的用料量（配方表里那味料的数量，现在是 1）
func dose_cost() -> int:
	return 1


## 一炉投料的候选材料（key = 材料 id）
func shelf_ids() -> Dictionary:
	return ItemDB.usable_material_ids(craft_kind())


## 成品条目（n 颗合一次入包）
func product_payload(_recipe: Dictionary, _n: int) -> Dictionary:
	return {}


## 量词：株 / 张
func unit_word() -> String:
	return "株"


## 容器用词：炉 / 案（提示语要说「炉里 / 案里」，别一律写成炉）
func vessel_word() -> String:
	return "炉"


## 成品名后缀用词：丹 / 符
func product_word() -> String:
	return "丹"


## 玩法收尾：子类算出「成数比例」再回调 settle_ratio()
func _begin_play() -> void:
	settle_ratio(1.0)


func _stop_play() -> void:
	pass


## 玩法阶段底部要不要留按钮（丹炉要「停火」，符台靠走笔自己收尾）
func play_has_action() -> bool:
	return true


## 文案
func verb_start() -> String:
	return "开炉"


func verb_stop() -> String:
	return "停火"


func word_success() -> String:
	return "丹成！"


func word_blocked() -> String:
	return "正到火候，此刻收手材料尽毁 —— 先把这一步做完"


## 玩法进行中的提示
func play_hint() -> String:
	return "看准火候停手"


# ===================== 壳 =====================

func panel_size() -> Vector2:
	return VIEW


func facility_header_compact() -> bool:
	return true


func _build_shell() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.014, 0.013, 0.017, 1.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_root = PanelContainer.new()
	_root.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_root.position = Vector2.ZERO
	_root.size = VIEW
	add_child(_root)

	_stage = Control.new()
	_stage.size = VIEW
	_stage.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(_stage)

	content = UIKit.vbox(0)
	content.visible = false
	_stage.add_child(content)

	# overlay 先建：toast、拖拽跟随图标、药谱抽屉都挂在它上面
	_overlay = Control.new()
	_overlay.size = VIEW
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.z_index = 40
	_stage.add_child(_overlay)

	_build_world()
	_build_topbar()
	_build_dish()
	_build_mouth()
	_build_shelf()
	_build_doses()
	_build_bottom()
	_build_toast()


func _build_world() -> void:
	_bg = TextureRect.new()
	_bg.texture = UIKit.ui_texture(stage_texture())
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.size = VIEW
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_bg)

	var accent := _accent()
	_glow = UIKit.glow_node(Vector2(360, 360), Color(1.0, 0.62, 0.24), 0.34)
	var mouth := stage_mouth_rect()
	_glow.position = mouth.get_center() - Vector2(180, 210)
	_stage.add_child(_glow)
	# 玩法控件常驻舞台上，LOAD 阶段只压暗不隐藏，位置才不会跳
	_play_layer = _build_play()
	if _play_layer != null:
		var pr := stage_play_rect()
		_play_layer.position = pr.position
		_play_layer.size = pr.size
		_play_layer.modulate.a = 0.42
		_stage.add_child(_play_layer)


func _accent() -> Color:
	return UIKit.facility_style("alchemy" if craft_kind() == "pill" else "talisman") \
		.get("accent", UIKit.C_ACCENT)


func _build_topbar() -> void:
	var bar := Control.new()
	bar.size = Vector2(VIEW.x, TOP_H)
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	_stage.add_child(bar)

	var band := TextureRect.new()
	band.texture = UIKit.vertical_gradient(Color(0.0, 0.0, 0.0, 0.86), Color(0.0, 0.0, 0.0, 0.0))
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.size = Vector2(VIEW.x, TOP_H + 26)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(band)

	_title_lbl = UIKit.label("", 17, Color(0.98, 0.94, 0.84))
	_title_lbl.position = Vector2(18, 10)
	_title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_title_lbl)

	_state_lbl = UIKit.readable_label("", UIKit.F_SMALL, UIKit.C_TEXT_DIM)
	_state_lbl.position = Vector2(430, 14)
	_state_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_state_lbl)

	var prof_box := UIKit.vbox(1)
	prof_box.position = Vector2(840, 8)
	prof_box.custom_minimum_size = Vector2(150, 0)
	prof_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prof_lbl = UIKit.label("", UIKit.F_BADGE, UIKit.C_TEXT_DIM)
	prof_box.add_child(_prof_lbl)
	_prof_bar = UIKit.mini_progress(0.0, _accent(), Vector2(150, 6)) as ProgressBar
	prof_box.add_child(_prof_bar)
	bar.add_child(prof_box)

	var book_btn := UIKit.quiet_button("药谱", Vector2(84, 30), _accent())
	book_btn.position = Vector2(1006, 8)
	book_btn.pressed.connect(_toggle_drawer)
	_book_btn = book_btn
	bar.add_child(book_btn)

	var close := UIKit.quiet_button("关闭", Vector2(84, 30), _accent())
	close.position = Vector2(1100, 8)
	close.pressed.connect(_on_close_pressed)
	bar.add_child(close)


func _build_mouth() -> void:
	# 投料口按路径挂脚本，不依赖全局类缓存：编辑器缓存过期时（增删 class_name 后）
	# 曾经因为解析不到 CraftDropZone 而让整条炼制链路编译失败、点设施直接闪退。
	_mouth = Control.new()
	_mouth.set_script(load("res://scripts/ui/panels/craft_slot.gd"))
	_mouth.call("setup", self, stage_mouth_rect(), _mouth_label(), _accent())
	_stage.add_child(_mouth)


## 拖拽悬停预判：药筐里的味料都能投（换味由 add_dose 走「整批退回」，不会丢材料）
func can_accept(material_id: String) -> bool:
	# 只有玩法进行中（火正旺 / 笔正走）不接料；出炉后那一屏照样可以继续投下一炉
	if _phase == PHASE_PLAY or material_id == "":
		return false
	return shelf_ids().has(material_id)


func _mouth_label() -> String:
	return "把药材丢进炉口" if craft_kind() == "pill" else "把兽皮丢进皮匣"


func _build_shelf() -> void:
	var host := Control.new()
	var r := stage_shelf_rect()
	host.position = r.position
	host.size = r.size
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(host)

	var cap := UIKit.readable_label(
		"药筐 · 拖着丢进炉口（也可点一下投一株）" if craft_kind() == "pill"
		else "皮架 · 拖着丢进皮匣（也可点一下投一张）",
		UIKit.F_BADGE, Color(0.80, 0.76, 0.66, 0.85))
	cap.position = Vector2(0, -2)
	cap.size = Vector2(r.size.x, 16)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(cap)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, 18)
	scroll.size = Vector2(r.size.x, r.size.y - 18)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	host.add_child(scroll)

	_shelf_box = UIKit.vbox(6)
	_shelf_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_shelf_box)


func _build_doses() -> void:
	_dose_box = UIKit.hbox(2)
	_dose_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_dose_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_dose_box)
	_dose_more = UIKit.label("", UIKit.F_SMALL, UIKit.C_ACCENT)
	_dose_more.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_dose_more)


func _build_dish() -> void:
	var r := stage_dish_rect()
	var dish := PanelContainer.new()
	dish.position = r.position
	dish.size = r.size
	dish.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 软胶囊而不是方框：出炉盘要像画上的一个台面，不能读成一只控件盒
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.06, 0.42)
	sb.border_color = Color(_accent().r, _accent().g, _accent().b, 0.30)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(r.size.y * 0.5))
	dish.add_theme_stylebox_override("panel", sb)
	_stage.add_child(dish)

	var col := UIKit.vbox(2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	dish.add_child(col)
	_dish_icon = TextureRect.new()
	_dish_icon.custom_minimum_size = Vector2(52, 52)
	_dish_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dish_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_dish_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_dish_icon)
	_dish_count = UIKit.label("", 16, Color(0.97, 0.92, 0.78))
	_dish_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dish_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_dish_count)
	col.add_child(UIKit.readable_label(
		"出炉" if craft_kind() == "pill" else "成符", UIKit.F_BADGE, UIKit.C_TEXT_DIM))


func _build_bottom() -> void:
	var y := 656.0
	_action_btn = UIKit.primary_button(verb_start(), Vector2(168, 44), _accent())
	_action_btn.position = Vector2(640.0 - 84.0, y)
	_action_btn.add_theme_font_size_override("font_size", 17)
	_action_btn.pressed.connect(_on_action)
	_stage.add_child(_action_btn)
	# 新手指引：炼丹「开炉」与制符「执笔」共用这颗按钮，按品类分锚点键
	if craft_kind() == "talisman":
		_action_btn.set_meta("tut", "talisman.draw")
	else:
		_action_btn.set_meta("tut", "alchemy.brew")

	_clear_btn = UIKit.quiet_button("清空炉料", Vector2(118, 34), _accent())
	_clear_btn.position = Vector2(430.0, y + 5)
	_clear_btn.pressed.connect(_on_clear)
	_stage.add_child(_clear_btn)

	_hint_lbl = UIKit.readable_label("", UIKit.F_SMALL, UIKit.C_TEXT_DIM)
	_hint_lbl.position = Vector2(300, y - 30)
	_hint_lbl.size = Vector2(680, 18)
	_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_hint_lbl)


func _build_toast() -> void:
	_toast = UIKit.label("", 16, UIKit.C_OK)
	_toast.position = Vector2(140, 96)
	_toast.size = Vector2(1000, 26)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	_toast.z_index = 41
	_overlay.add_child(_toast)


# ===================== 生命周期 =====================

func open() -> void:
	if _visible:
		return
	super.open()
	_phase = PHASE_LOAD
	_mid = ""
	_doses = 0
	_pending_learn = false
	_close_drawer()
	if _play_layer != null:
		_play_layer.modulate.a = 0.42
	if _mouth != null:
		_mouth.call("set_state", "load")
	_refresh_all()


func can_close() -> bool:
	if _phase == PHASE_PLAY:
		show_toast(word_blocked(), UIKit.C_WARN)
		return false
	return true


func _input(event: InputEvent) -> void:
	if not _visible:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_ESCAPE:
		if _drawer != null and is_instance_valid(_drawer):
			_close_drawer()
			get_viewport().set_input_as_handled()
			return
		if not can_close():
			get_viewport().set_input_as_handled()
			return
	# 拖拽跟随图标要贴着鼠标走，事件里取最新坐标
	if event is InputEventMouseMotion:
		_last_mouse = event.global_position
	super(event)


var _last_mouse := Vector2.ZERO


func _process(delta: float) -> void:
	_tick_follow()
	if _glow != null and is_instance_valid(_glow):
		var k := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0022)
		_glow.modulate.a = (0.60 if _doses > 0 else 0.34) + 0.22 * k
	if _phase == PHASE_PLAY:
		_tick_play(delta)


## 玩法每帧推进（丹炉扫指针 / 符台不必填）—— 基类占了 _process，子类不要再自己写 _process
func _tick_play(_delta: float) -> void:
	pass


## 拖拽中的跟随图标：引擎的 set_drag_preview 画在根 viewport，会被本面板这层 CanvasLayer 盖住
## （锻造台踩过同一个坑），所以自己画在 _overlay 上
func _tick_follow() -> void:
	var vp := get_viewport()
	var dragging := vp != null and vp.gui_is_dragging()
	if not dragging:
		if _follow != null and is_instance_valid(_follow):
			_follow.queue_free()
		_follow = null
		_follow_name = ""
		return
	var data: Variant = vp.gui_get_drag_data()
	var mid := String((data as Dictionary).get("id", "")) if data is Dictionary else ""
	if mid == "":
		return
	if _follow == null or not is_instance_valid(_follow):
		_follow = TextureRect.new()
		_follow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_follow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_follow.custom_minimum_size = Vector2(46, 46)
		_follow.size = Vector2(46, 46)
		_follow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_follow.modulate = Color(1, 1, 1, 0.78)
		_overlay.add_child(_follow)
		_follow.texture = UIKit.ui_texture(String(ItemDB.get_material(mid).get("icon", "")))
		_follow_name = ItemDB.get_material_name(mid)
	_follow.position = _last_mouse - Vector2(23, 23)


# ===================== 投料 =====================

## 拖 / 点一味的入口：一次只认一味，投别的等于整批换料
func add_dose(material_id: String) -> void:
	if material_id == "":
		return
	if _phase == PHASE_PLAY:
		GameState.play_ui("ui_deny")
		show_toast(word_blocked(), UIKit.C_WARN)
		return
	if _phase == PHASE_DONE:
		# 刚出炉还在收尾屏：投料就等于开下一炉，直接回放料态（按钮变回「开炉」）
		_phase = PHASE_LOAD
	var recipe := ItemDB.recipe_for_material(craft_kind(), material_id)
	if recipe.is_empty():
		GameState.play_ui("ui_deny")
		show_toast("「%s」不入%s谱 —— 这一味炼不出东西，材料未消耗" % [
			ItemDB.get_material_name(material_id), "丹方" if craft_kind() == "pill" else "符方"],
			UIKit.C_WARN)
		return
	if _mid != "" and material_id != _mid:
		var back := _doses
		_mid = material_id
		_doses = 0
		show_toast("炉里换成「%s」，先前的 %d %s已退回（未开工不扣料）" % [
			ItemDB.get_material_name(material_id), back, unit_word()], UIKit.C_ACCENT)
		GameState.play_ui("ui_tab")
	if _mid == "" or _doses == 0:
		_mid = material_id
	if not _learned(recipe):
		CharacterData.learn_recipe(craft_kind(), String(recipe.get("recipe_id", "")))
		_pending_learn = true
	if _doses >= MAX_DOSE:
		GameState.play_ui("ui_deny")
		show_toast("一炉最多投 %d %s，先把手上这一炉做完" % [MAX_DOSE, unit_word()], UIKit.C_WARN)
		return
	if _doses + dose_cost() > CharacterData.count_material(_mid):
		GameState.play_ui("ui_deny")
		show_toast("「%s」只剩 %d %s了 —— 炉里已投 %d %s" % [
			ItemDB.get_material_name(_mid), CharacterData.count_material(_mid), unit_word(),
			_doses, unit_word()], UIKit.C_WARN)
		return
	_doses += 1
	GameState.play_ui("ui_equip")
	_refresh_all()


func _on_clear() -> void:
	if _phase == PHASE_PLAY:
		GameState.play_ui("ui_deny")
		show_toast(word_blocked(), UIKit.C_WARN)
		return
	_phase = PHASE_LOAD
	if _doses == 0:
		_refresh_all()
		return
	var back := _doses
	_mid = ""
	_doses = 0
	GameState.play_ui("ui_tab")
	show_toast("%d %s已退回药筐" % [back, unit_word()], UIKit.C_ACCENT)
	_refresh_all()


func _on_action() -> void:
	match _phase:
		PHASE_LOAD:
			_start()
		PHASE_PLAY:
			_stop_play()
		PHASE_DONE:
			_again()


## 开炉 / 执笔：唯一扣料的地方
func _start() -> void:
	if _doses <= 0:
		GameState.play_ui("ui_deny")
		show_toast("炉子是空的 —— 先丢进一些%s" % ("药材" if craft_kind() == "pill" else "兽皮"),
			UIKit.C_WARN)
		return
	var need := _doses * dose_cost()
	var recipe := ItemDB.recipe_for_material(craft_kind(), _mid)
	var out := _product_def(recipe)
	if not _bag_can_hold(out):
		GameState.play_ui("ui_deny")
		show_toast("背包放不下 %d 颗成品 —— 先清出空位" % _doses, UIKit.C_DANGER)

		return
	if not CharacterData.consume_materials({String(_mid): need}):
		GameState.play_ui("ui_deny")
		show_toast("材料不足，无法开工", UIKit.C_DANGER)
		_refresh_all()
		return
	GameState.play_ui("ui_click")
	_refresh_shelf()
	_last_mid = _mid
	_last_doses = _doses
	if _mastered(recipe):
		settle_ratio(1.0)
		return
	_phase = PHASE_PLAY
	_action_btn.text = verb_stop()
	_action_btn.visible = play_has_action()
	_clear_btn.visible = false
	if _play_layer != null:
		_play_layer.modulate.a = 1.0
	_hint_lbl.text = play_hint()
	_mouth.call("set_state", "play")
	_begin_play()


## 玩法收尾后统一走这里：ratio = 这一炉炼成了几成，reason = 失败原因（偏文 / 偏武 / 墨尽）
func settle_ratio(ratio: float, reason: String = "") -> void:
	_phase = PHASE_DONE
	if _play_layer != null:
		_play_layer.modulate.a = 0.42
	_clear_btn.visible = true
	var recipe := ItemDB.recipe_for_material(craft_kind(), _mid)
	var lost := _doses
	var made := int(round(float(lost) * ratio))
	if made <= 0:
		GameState.play_ui("forge_fail")
		_mouth.call("set_state", "load")
		_doses = 0
		_mid = ""
		_refresh_all()
		show_toast("%s —— %d %s尽毁，一颗没成" % [
			reason if reason != "" else "火候失手", lost, unit_word()], UIKit.C_DANGER)
		return
	var out := _product_def(recipe)
	out["count"] = made
	var is_talisman := String(out.get("type", "")) == CharacterData.ITEM_TALISMAN
	if not CharacterData.add_item(out):
		GameState.play_ui("forge_fail")
		show_toast("符匣已满，成品未能收入" if is_talisman else "背包已满，成品未能入包",
			UIKit.C_DANGER)
		_refresh_all()
		return
	CharacterData.add_proficiency(craft_kind(), String(recipe.get("recipe_id", "")),
		PROF_PER_UNIT * made)
	_dish_icon.texture = UIKit.ui_texture(String(out.get("icon", "")))
	_dish_count.text = "×%d" % made
	_fly_to_dish(made)
	GameState.play_ui("forge_success")
	# 新手指引：炼丹 / 制符共用这一条成功路径，用 craft_kind() 区分
	Tutorial.note("craft_done:" + craft_kind())
	_mouth.call("set_state", "load")
	if _pending_learn:
		_pending_learn = false
		_refresh_shelf()
	show_toast("%s　%d / %d %s%s" % [word_success(), made, _doses, unit_word(),
		"入匣" if is_talisman else "入包"],
		UIKit.C_GREAT if made == _doses else UIKit.C_OK)
	_doses = 0
	_mid = ""
	_refresh_all()
	_action_btn.text = "再来一炉"


## 熟练度满 = 免玩法，直接全成
func _mastered(recipe: Dictionary) -> bool:
	return CharacterData.get_proficiency(craft_kind(),
		String(recipe.get("recipe_id", ""))) >= 1.0


func _learned(recipe: Dictionary) -> bool:
	return CharacterData.is_recipe_known(craft_kind(), String(recipe.get("recipe_id", "")))


## 再来一炉：材料还够就按上一炉的株数自动摆好（依旧不扣料）
func _again() -> void:
	if _last_mid == "" or _last_doses <= 0:
		_phase = PHASE_LOAD
		_refresh_all()
		return
	var need := _last_doses * dose_cost()
	if not CharacterData.has_materials({String(_last_mid): need}):
		show_toast("「%s」不够再来一炉（要 %d %s）—— 重新投料或去采" % [
			ItemDB.get_material_name(_last_mid), need, unit_word()], UIKit.C_WARN)
		_phase = PHASE_LOAD
		_refresh_all()
		return
	_mid = _last_mid
	_doses = _last_doses
	_phase = PHASE_LOAD
	GameState.play_ui("ui_tab")
	show_toast("下一炉材料已就位：%d %s（未开工不扣料）" % [_doses, unit_word()], UIKit.C_OK)
	_refresh_all()


# ===================== 刷新 =====================

func _refresh_all() -> void:
	_refresh_title()
	_refresh_shelf()
	_refresh_doses()
	_refresh_prof()
	_refresh_action()


func _product_def(recipe: Dictionary) -> Dictionary:
	return product_payload(recipe, 1)


func _refresh_title() -> void:
	var head := "丹炉" if craft_kind() == "pill" else "符台"
	_title_lbl.text = head
	if _mid == "":
		_state_lbl.text = "还没投料 —— 一炉只炼一味"
	else:
		var recipe := ItemDB.recipe_for_material(craft_kind(), _mid)
		_state_lbl.text = "%s ×%d %s　→　%s" % [
			ItemDB.get_material_name(_mid), _doses, unit_word(),
			String(recipe.get("pill_name", recipe.get("talisman_name", "?")))]


func _refresh_shelf() -> void:
	UIKit.clear_children(_shelf_box)
	var allowed := shelf_ids()
	var any := false
	for it in CharacterData.inventory:
		var item: Dictionary = it
		var mid := String(item.get("id", ""))
		if String(item.get("type", "")) != CharacterData.ITEM_MATERIAL or not allowed.has(mid):
			continue
		var have := CharacterData.count_material(mid)
		if have <= 0:
			continue
		any = true
		var chip := PanelContainer.new()
		chip.set_script(load("res://scripts/ui/panels/craft_material_chip.gd"))
		chip.call("setup", mid, String(item.get("name", mid)), have - (_doses if mid == _mid else 0), self)
		chip.custom_minimum_size = Vector2(stage_shelf_rect().size.x - 14, 48)
		_shelf_box.add_child(chip)
	if not any:
		_shelf_box.add_child(UIKit.note(
			"药筐是空的 —— 去苍澜大陆采药、灵田种药" if craft_kind() == "pill"
			else "皮架是空的 —— 去苍澜大陆打妖兽取皮"))


func _refresh_doses() -> void:
	UIKit.clear_children(_dose_box)
	var c := stage_dose_center()
	_dose_box.position = Vector2(c.x - 250.0, c.y - 20.0)
	_dose_box.size = Vector2(500, 40)
	_mouth.call("set_visual", ItemDB.get_material_name(_mid) if _mid != "" else "", _doses)
	if _mid == "":
		_dose_more.text = ""
		return
	var tex := UIKit.ui_texture(String(ItemDB.get_material(_mid).get("icon", "")))
	var shown := mini(_doses, MAX_DOSE)
	for i in shown:
		var g := TextureRect.new()
		g.texture = tex
		g.custom_minimum_size = Vector2(34, 34)
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.modulate = Color(1, 1, 1, 0.92)
		_dose_box.add_child(g)
	_dose_more.text = ""


func _refresh_prof() -> void:
	var recipe := ItemDB.recipe_for_material(craft_kind(), _mid)
	if recipe.is_empty():
		_prof_lbl.text = "熟练度 —— 未定味"
		_prof_bar.value = 0.0
		return
	var prof := CharacterData.get_proficiency(craft_kind(), String(recipe.get("recipe_id", "")))
	_prof_bar.value = clampf(prof, 0.0, 1.0) * 100.0
	if prof >= 1.0:
		_prof_lbl.text = "炉火纯青 · 免玩法必成"
		_prof_lbl.add_theme_color_override("font_color", UIKit.C_GREAT)
	else:
		_prof_lbl.text = "熟练度 %s · 满后免玩法" % UIKit.percent_text(prof)
		_prof_lbl.add_theme_color_override("font_color", UIKit.C_TEXT_DIM)


func _refresh_action() -> void:
	# 玩法进行中不许翻药谱：那几秒该盯着火候
	if _book_btn != null:
		_book_btn.disabled = _phase == PHASE_PLAY
	match _phase:
		PHASE_LOAD:
			_action_btn.text = verb_start()
			_action_btn.visible = true
			_action_btn.disabled = _doses <= 0
			_clear_btn.visible = _doses > 0
			if _doses > 0:
				_hint_lbl.text = "%s里 %d %s —— 点「%s」才真正投料（在此之前不扣任何材料）" % [
					vessel_word(), _doses, unit_word(), verb_start()]
			else:
				_hint_lbl.text = "拖着%s丢进%s口，也可点一下投一株" % [
					"药材" if craft_kind() == "pill" else "兽皮", vessel_word()]
		PHASE_PLAY:
			_action_btn.text = verb_stop()
			_action_btn.disabled = false
			_clear_btn.visible = false
		PHASE_DONE:
			_action_btn.text = "再来一炉"
			_action_btn.visible = true
			_action_btn.disabled = _last_mid == "" \
				or not CharacterData.has_materials(
					{String(_last_mid): _last_doses * dose_cost()})
			_clear_btn.visible = true
			_hint_lbl.text = "点「再来一炉」按上次株数再摆一炉（依旧不扣料）"


func _bag_can_hold(out: Dictionary) -> bool:
	# 符箓进符匣，不吃背包格
	if String(out.get("type", "")) == CharacterData.ITEM_TALISMAN:
		return true
	if CharacterData.bag_has_room(out):
		return true
	var pid := String(out.get("id", ""))
	for it in CharacterData.inventory:
		if String((it as Dictionary).get("id", "")) == pid:
			return true
	return false


# ===================== 反馈 =====================

func show_toast(text: String, color: Color) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


## 出丹 / 出符：成品图标从炉口飞到出炉盘，数量在盘上落定
func _fly_to_dish(n: int) -> void:
	var from := stage_mouth_rect().get_center()
	var to := stage_dish_rect().get_center()
	var icon := String(_product_def(ItemDB.recipe_for_material(craft_kind(), _last_mid)).get("icon", ""))
	for i in mini(n, 5):
		var g := TextureRect.new()
		g.texture = UIKit.ui_texture(icon)
		g.size = Vector2(40, 40)
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.position = from - Vector2(20, 20)
		g.z_index = 42
		_overlay.add_child(g)
		var tw := create_tween()
		tw.tween_property(g, "position", to - Vector2(20, 20), 0.42 + 0.05 * i) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(g, "modulate:a", 0.0, 0.5).set_delay(0.2)
		tw.tween_callback(g.queue_free)


# ===================== 药谱抽屉 =====================

func _toggle_drawer() -> void:
	if _drawer != null and is_instance_valid(_drawer):
		_close_drawer()
		return
	GameState.play_ui("ui_tab")
	var recipes: Array = ItemDB.PILL_RECIPES if craft_kind() == "pill" else ItemDB.all_talisman_recipes()
	var card := PanelContainer.new()
	var accent := _accent()
	card.add_theme_stylebox_override("panel", UIKit.accent_card_style(accent, 0.96, 0.55, 10))
	card.position = Vector2(300, 104)
	# 高度跟着方子条数走：两张符方不该顶出一大截空白
	card.size = Vector2(680, minf(470.0, 122.0 + recipes.size() * 88.0))
	card.z_index = 45
	_overlay.add_child(card)
	_drawer = card

	var col := UIKit.vbox(8)
	card.add_child(col)
	var head := UIKit.hbox(10)
	col.add_child(head)
	head.add_child(UIKit.label("药谱 · 一味成一丹" if craft_kind() == "pill" else "符谱 · 一味成一符",
		17, Color(0.98, 0.94, 0.84)))
	head.add_child(UIKit.spacer())
	var x := UIKit.quiet_button("收起", Vector2(72, 28), accent)
	x.pressed.connect(_close_drawer)
	head.add_child(x)
	col.add_child(UIKit.readable_label(
		"炉子里只认一味：丢几株出几颗（火候失手会少出或全毁）。这一味从没投过会自动记进谱里。",
		UIKit.F_SMALL, UIKit.C_TEXT_DIM))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := UIKit.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for raw in recipes:
		var r: Dictionary = raw
		var mid := ItemDB.recipe_material_id(r)
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel",
			UIKit.accent_card_style(ItemDB.rarity_color(String(r.get("rarity", "common"))),
				0.62, 0.30, 7))
		list.add_child(row)
		var h := UIKit.hbox(10)
		row.add_child(h)
		h.add_child(UIKit.icon_node(String(ItemDB.get_material(mid).get("icon", "")),
			ItemDB.get_material_name(mid), "material", Vector2(34, 34)))
		var arrow := UIKit.label("→", 15, accent)
		h.add_child(arrow)
		h.add_child(UIKit.icon_node(String(r.get("icon", "")),
			String(r.get("pill_name", r.get("talisman_name", ""))),
			"pill" if craft_kind() == "pill" else "talisman", Vector2(34, 34)))
		var info := UIKit.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		info.add_child(UIKit.label("%s ×1 → %s" % [ItemDB.get_material_name(mid),
			String(r.get("pill_name", r.get("talisman_name", "")))], 14, Color(0.96, 0.92, 0.80)))
		info.add_child(UIKit.readable_label("%s　持有 %d %s　%s" % [
			ItemDB.effect_text(r), CharacterData.count_material(mid), unit_word(),
			"熟练 %s" % UIKit.percent_text(
				CharacterData.get_proficiency(craft_kind(), String(r.get("recipe_id", ""))))],
			UIKit.F_BADGE, UIKit.C_TEXT_DIM))


func _close_drawer() -> void:
	if _drawer != null and is_instance_valid(_drawer):
		_drawer.queue_free()
	_drawer = null
