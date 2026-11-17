extends Control
## 万界秘境 · 苍澜大陆
## 左侧是行前告示，右侧是区域风物插画，底部是区域切换。
## 只负责展示与选择；真正切场景由 DomainPanel 处理。

signal enter_world_requested(region_id: String)

const ACCENT := Color(0.56, 0.90, 0.62)
const MAP_ART := "res://assets/ui/facilities/herb_garden_cutout.png"

var _regions: Array = []
var _selected_id := ""
var _buttons: Dictionary = {}
var _built := false

var _map_bg: TextureRect
var _map_tint: ColorRect
var _hero: PanelContainer
var _kicker: Label
var _name: Label
var _state_row: HBoxContainer
var _realm: Label
var _desc: Label
var _stats: VBoxContainer
var _rule: Label
var _enter: Button
var _art_holder: Control
var _selector: HBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_build()
	_built = true
	_layout()
	_refresh_region()


func setup(regions: Array, selected_id: String = "") -> void:
	_regions = regions.duplicate(true)
	_selected_id = selected_id
	if _built:
		_rebuild_selector()
		_layout()
		_refresh_region()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _built:
		_layout()
		if _selected_id != "":
			var r := SecretWorldDB.get_region(_selected_id)
			if not r.is_empty():
				_refresh_art(r, SecretWorldDB.is_region_open(r))


func _build() -> void:
	var bg := TextureRect.new()
	bg.texture = UIKit.vertical_gradient(Color(0.02, 0.055, 0.045, 1.0), Color(0.008, 0.025, 0.032, 1.0))
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_map_tint = ColorRect.new()
	_map_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_map_tint)

	_map_bg = TextureRect.new()
	_map_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_map_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_bg.modulate = Color(0.70, 0.85, 0.72, 0.34)
	_map_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_map_bg)

	var bottom_shade := TextureRect.new()
	bottom_shade.texture = UIKit.vertical_gradient(Color(0.005, 0.02, 0.025, 0.0), Color(0.005, 0.02, 0.025, 0.90))
	bottom_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bottom_shade.stretch_mode = TextureRect.STRETCH_SCALE
	bottom_shade.anchor_top = 1.0
	bottom_shade.anchor_right = 1.0
	bottom_shade.anchor_bottom = 1.0
	bottom_shade.offset_top = -150.0
	bottom_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_shade)

	_build_hero()
	_build_art_holder()
	_build_selector()


func _build_hero() -> void:
	_hero = PanelContainer.new()
	_hero.add_theme_stylebox_override("panel",
		UIKit.accent_card_style(ACCENT, 0.90, 0.30, 8))
	add_child(_hero)

	var col := UIKit.vbox(6)
	_hero.add_child(col)

	_kicker = UIKit.label("苍澜大陆 · 大世界", 11, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.80))
	col.add_child(_kicker)

	var title_row := UIKit.hbox(10)
	col.add_child(title_row)
	_name = UIKit.label("", 30, Color(0.97, 0.95, 0.88))
	title_row.add_child(_name)
	_state_row = UIKit.hbox(6)
	_state_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_child(_state_row)

	_realm = UIKit.label("", 11, Color(0.72, 0.82, 0.74, 0.94))
	col.add_child(_realm)

	_desc = UIKit.readable_label("", 13, Color(0.80, 0.86, 0.82, 0.94))
	_desc.custom_minimum_size = Vector2(0, 24)
	_desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_desc.clip_text = true
	col.add_child(_desc)

	_stats = UIKit.vbox(3)
	col.add_child(_stats)

	_rule = UIKit.readable_label("", 10, Color(0.66, 0.74, 0.70, 0.90))
	_rule.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_rule.clip_text = true
	col.add_child(_rule)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	var action := UIKit.hbox(10)
	col.add_child(action)
	_enter = UIKit.primary_button("踏入此地", Vector2(176, 40), ACCENT)
	_enter.add_theme_font_size_override("font_size", UIKit.F_BODY)
	UIKit.set_click_sfx(_enter, "ui_confirm")
	_enter.pressed.connect(_on_enter_pressed)
	action.add_child(_enter)
	action.add_child(UIKit.readable_label("从入口传送门撤离才带回战利品", 10, UIKit.C_TEXT_DIM))


func _build_art_holder() -> void:
	_art_holder = Control.new()
	_art_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_holder.clip_contents = true
	add_child(_art_holder)


func _build_selector() -> void:
	_selector = UIKit.hbox(8)
	_selector.anchor_left = 0.0
	_selector.anchor_top = 1.0
	_selector.anchor_right = 1.0
	_selector.anchor_bottom = 1.0
	_selector.offset_left = 20.0
	_selector.offset_right = -20.0
	_selector.offset_top = -56.0
	_selector.offset_bottom = -14.0
	_selector.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_selector)
	var tag := UIKit.label("区域", 10, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.72))
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_selector.add_child(tag)
	_rebuild_selector()


func _rebuild_selector() -> void:
	if _selector == null:
		return
	for c in _selector.get_children():
		if c is Button:
			c.queue_free()
	_buttons.clear()
	if _selected_id == "":
		for r in _regions:
			if SecretWorldDB.is_region_open(r):
				_selected_id = String(r.get("region_id", ""))
				break
	for r in _regions:
		var rid := String(r.get("region_id", ""))
		var b := UIKit.button("%s · %s" % [String(r.get("name", rid)), String(r.get("realm", ""))],
			Vector2(152, 34))
		b.add_theme_font_size_override("font_size", UIKit.readable_size(UIKit.F_SMALL))
		b.tooltip_text = String(r.get("desc", ""))
		UIKit.set_click_sfx(b, "ui_tab")
		b.pressed.connect(_on_region_pressed.bind(rid))
		_selector.add_child(b)
		_buttons[rid] = b


func _layout() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	_hero.position = Vector2(18.0, 14.0)
	_hero.size = Vector2(minf(572.0, size.x * 0.55), minf(430.0, size.y - 112.0))
	_art_holder.position = Vector2(620.0, 8.0)
	_art_holder.size = Vector2(maxf(120.0, size.x - 636.0), size.y - 80.0)


func _on_region_pressed(region_id: String) -> void:
	_selected_id = region_id
	_refresh_region()


func _refresh_region() -> void:
	var r := SecretWorldDB.get_region(_selected_id)
	if r.is_empty():
		return
	var rid := String(r.get("region_id", ""))
	var unlocked := SecretWorldDB.is_region_open(r)
	var core_killed := bool(CharacterData.secret_world.get("core_kills", {}).get(rid, false))
	var accent := ACCENT if unlocked else Color(0.55, 0.60, 0.62)

	_hero.add_theme_stylebox_override("panel", UIKit.accent_card_style(accent, 0.90, 0.30, 8))
	_kicker.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.82))
	_name.text = String(r.get("name", rid))
	_realm.text = "对应境界 · %s" % String(r.get("realm", ""))

	UIKit.clear_children(_state_row)
	if not unlocked:
		_state_row.add_child(UIKit.chip("尚未开放", UIKit.C_DISABLE))
	elif core_killed:
		_state_row.add_child(UIKit.chip("核心首领已击杀", UIKit.C_OK))
	else:
		_state_row.add_child(UIKit.chip("可探索", accent))

	_desc.text = String(r.get("desc", ""))
	UIKit.clear_children(_stats)
	var has_core := String(r.get("core_boss_id", "")) != ""
	if has_core:
		var core_name := String(SecretWorldDB.get_core_boss(rid).get("name", "核心首领"))
		var core_state := "已击杀" if core_killed else "未击杀"
		_stats.add_child(_stat_line("核心首领", "%s（%s）" % [core_name, core_state] if unlocked else core_name,
			UIKit.C_OK if core_killed else UIKit.C_ACCENT))
	if unlocked:
		_stats.add_child(_stat_line("风物", "药材采集 / 灵兽狩猎 / 野外修士", Color(0.82, 0.88, 0.84)))
		_stats.add_child(_stat_line("局内背包", "B 随时打开 · 拾取先入局内", Color(0.82, 0.88, 0.84)))
		_stats.add_child(_stat_line("撤离规则", "死亡清空 · 从入口传送门带回", UIKit.C_WARN))
		_rule.text = ("药材、灵兽与野修会定期刷新；核心首领只能击杀一次，给出对应境界的突破材料。"
			if has_core else "药材、灵兽与野修会定期刷新；相邻区域可步行往返。")
		_enter.text = "踏入%s" % String(r.get("name", "此地"))
		_enter.disabled = false
		_enter.tooltip_text = "进入苍澜大陆 · %s" % String(r.get("name", ""))
	else:
		_stats.add_child(_stat_line("风物", "待设计", UIKit.C_DISABLE))
		_stats.add_child(_stat_line("局内背包", "开放后可用", UIKit.C_DISABLE))
		if String(r.get("region_id", "")) == SecretWorldDB.REGION_HUASHEN:
			# 钥匙名从突破表现算，改了数据表这里不会留旧文案
			var gate_names: Array[String] = []
			for k in CharacterData.huashen_gate_requirements():
				gate_names.append(String(ItemDB.get_material(String(k)).get("name", String(k))))
			_stats.add_child(_stat_line("入口", "幽冥灵墟中心 · 九天门", UIKit.C_ACCENT))
			_rule.text = "化神之路不在此处：把化神底髓与化神天髓在锻造台熔铸成「" \
				+ "、".join(gate_names) \
				+ "」，修为到元婴后期圆满后，到幽冥灵墟中心、镇墟石犼身后的九天门按 F 开门；进门后上中央的化神坛才真正突破。"
			_enter.text = "先在九天门开门"
			_enter.disabled = true
			_enter.tooltip_text = "底髓出自幽冥灵墟首领镇墟石犼，天髓出自照影界第三位 BOSS，两枚熔铸成完整晶"
		else:
			_rule.text = "该区域等待对应位面的首领与资源设计完成后再开放。"
			_enter.text = "尚未开放"
			_enter.disabled = true
			_enter.tooltip_text = "该区域尚未开放"

	_refresh_map(r)
	_refresh_art(r, unlocked)
	_refresh_selector()


func _stat_line(key: String, value: String, color: Color) -> Control:
	var row := UIKit.hbox(10)
	var k := UIKit.label(key, 11, Color(0.62, 0.70, 0.66, 0.92))
	k.custom_minimum_size = Vector2(72, 0)
	row.add_child(k)
	var v := UIKit.readable_label(value, 11, color)
	row.add_child(v)
	return row


func _refresh_map(r: Dictionary) -> void:
	var tex_path := String(r.get("map_image", ""))
	var tex := UIKit.ui_texture(tex_path)
	if tex != null:
		_map_bg.texture = tex
		_map_bg.visible = true
		# 练气偏青绿，云隐谷偏冷蓝，丹霞偏赤金；总览图本身已经按区域调过色，这里只补氛围
		var rid := String(r.get("region_id", ""))
		var tint := Color(0.70, 0.85, 0.72, 1.0)
		if rid == SecretWorldDB.REGION_ZHUJI:
			tint = Color(0.78, 0.86, 0.96, 1.0)
		elif rid == SecretWorldDB.REGION_JIEDAN:
			tint = Color(1.0, 0.84, 0.66, 1.0)
		elif rid == SecretWorldDB.REGION_YUANYING:
			tint = Color(0.76, 0.68, 0.98, 1.0)
		tint.a = 0.38 if SecretWorldDB.is_region_open(r) else 0.12
		_map_bg.modulate = tint
	else:
		_map_bg.texture = null
		_map_bg.visible = false
	var gc: Color = r.get("ground_color", Color(0.10, 0.15, 0.13))
	var bc: Color = r.get("border_color", ACCENT)
	_map_tint.color = Color(gc.r, gc.g, gc.b, 0.76)
	_hero.add_theme_stylebox_override("panel", UIKit.accent_card_style(bc if SecretWorldDB.is_region_open(r) else Color(0.55, 0.60, 0.62), 0.90, 0.30, 8))


func _refresh_art(r: Dictionary, unlocked: bool) -> void:
	UIKit.clear_children(_art_holder)
	var bc: Color = r.get("border_color", ACCENT)
	var center := Vector2(_art_holder.size.x * 0.52, _art_holder.size.y * 0.46)
	var glow := UIKit.glow_node(Vector2(460.0, 460.0), bc, 0.24 if unlocked else 0.10)
	glow.position = center - glow.size * 0.5
	_art_holder.add_child(glow)

	var ring := UIKit.glow_node(Vector2(360.0, 360.0), bc, 0.30 if unlocked else 0.12, UIKit.TEX_RING_SOFT)
	ring.position = center - ring.size * 0.5
	_art_holder.add_child(ring)

	var art_w := minf(430.0, _art_holder.size.x - 28.0)
	var art_size := Vector2(art_w, art_w * 0.60)
	if unlocked and String(r.get("region_id", "")) == SecretWorldDB.REGION_LIANQI:
		var tex := UIKit.ui_texture(MAP_ART)
		if tex != null:
			var art := TextureRect.new()
			art.texture = tex
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			art.size = art_size
			art.position = Vector2(center.x - art_size.x * 0.5, center.y - art_size.y * 0.5)
			art.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_art_holder.add_child(art)
		var p := CPUParticles2D.new()
		p.amount = 18
		p.lifetime = 5.0
		p.preprocess = 3.0
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 130.0
		p.direction = Vector2(0, -1)
		p.spread = 42.0
		p.gravity = Vector2.ZERO
		p.initial_velocity_min = 4.0
		p.initial_velocity_max = 12.0
		p.scale_amount_min = 0.06
		p.scale_amount_max = 0.18
		p.color = Color(0.66, 1.0, 0.62, 0.50)
		p.texture = UIKit.ui_texture(UIKit.TEX_DOT_SOFT)
		p.position = center
		_art_holder.add_child(p)
		var cap := UIKit.outlined_label("风物 · 灵药圃", 10, Color(0.80, 0.92, 0.80, 0.82), 3)
		cap.position = Vector2(center.x - 70.0, center.y + art_size.y * 0.5 + 8.0)
		cap.size = Vector2(140.0, 20.0)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_art_holder.add_child(cap)
	else:
		var glyph_text := String(r.get("name", "?" )).substr(0, 1)
		var glyph := UIKit.outlined_label(glyph_text, 92, Color(bc.r, bc.g, bc.b, 0.34 if unlocked else 0.20), 8)
		glyph.position = Vector2(center.x - 100.0, center.y - 80.0)
		glyph.size = Vector2(200.0, 160.0)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_art_holder.add_child(glyph)
		var cap_text := "待探明" if not unlocked else "风物 · 灵兽与药材"
		var cap := UIKit.outlined_label(cap_text, 11,
			Color(0.78, 0.82, 0.84, 0.62) if not unlocked else Color(0.80, 0.92, 0.80, 0.82), 3)
		cap.position = Vector2(center.x - 60.0, center.y + 96.0)
		cap.size = Vector2(120.0, 20.0)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_art_holder.add_child(cap)


func _refresh_selector() -> void:
	for r in _regions:
		var rid := String(r.get("region_id", ""))
		var b: Button = _buttons.get(rid)
		if b == null:
			continue
		var unlocked := SecretWorldDB.is_region_open(r)
		var selected := rid == _selected_id
		var bc: Color = r.get("border_color", ACCENT)
		if not unlocked:
			bc = Color(0.48, 0.52, 0.55)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(bc.r, bc.g, bc.b, 0.30 if selected else 0.10)
		sb.border_color = Color(bc.r, bc.g, bc.b, 0.90 if selected else 0.30)
		sb.set_border_width_all(2 if selected else 1)
		sb.set_corner_radius_all(16)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		for state in ["normal", "disabled"]:
			b.add_theme_stylebox_override(state, sb)
		var hover := sb.duplicate() as StyleBoxFlat
		hover.bg_color = Color(bc.r, bc.g, bc.b, 0.24)
		hover.border_color = Color(bc.r, bc.g, bc.b, 0.80)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", sb)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color",
			Color(0.98, 0.96, 0.90) if selected else (UIKit.C_DISABLE if not unlocked else UIKit.C_TEXT))
		b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		if not unlocked:
			b.text = "%s · %s · 未开" % [String(r.get("name", rid)), String(r.get("realm", ""))]
		else:
			b.text = "%s · %s" % [String(r.get("name", rid)), String(r.get("realm", ""))]


func _on_enter_pressed() -> void:
	if _selected_id == "":
		return
	var r := SecretWorldDB.get_region(_selected_id)
	if r.is_empty() or not SecretWorldDB.is_region_open(r):
		return
	enter_world_requested.emit(_selected_id)
