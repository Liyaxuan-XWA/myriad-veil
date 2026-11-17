extends Control
## 万界秘境 · 守关者
## BOSS 卡面直接落在美术背景的三个金框里，不额外画边框。

signal back_requested
signal challenge_requested(domain_id: String, boss_id: String)

## 源图 2730×1536 中三个金框的内沿（比例），背景按整块拉伸，卡面用同一套比例对齐
const FRAME_RECTS := [
	Rect2(0.1146, 0.1953, 0.2330, 0.6230),
	Rect2(0.3850, 0.1953, 0.2300, 0.6230),
	Rect2(0.6520, 0.1953, 0.2341, 0.6230),
]
const ORDER_TEXT := ["守关者 · 壹", "守关者 · 贰", "守关者 · 叁"]
const SIGILS := {
	# 凡界三关（2026-10-31）：直接挂 BOSS 640×960 卡面，不再走字印占位
	"boss_huyao": {"glyph": "虎", "color": Color(1.00, 0.56, 0.22),
		"card": "res://assets/ui/codex/card_boss_huyao.png"},
	"boss_01": {"glyph": "刀", "color": Color(1.00, 0.66, 0.30),
		"card": "res://assets/ui/codex/card_boss_daoke.png"},
	"boss_01_c": {"glyph": "剑", "color": Color(0.56, 0.90, 1.00),
		"card": "res://assets/ui/codex/card_boss_jianke.png"},
	# 冲和界三关（2026-10-31）：同上
	"boss_02": {"glyph": "仪", "color": Color(0.94, 0.80, 0.42),
		"card": "res://assets/ui/codex/card_boss_liangyi.png"},
	"boss_02_b": {"glyph": "阵", "color": Color(0.90, 0.42, 0.34),
		"card": "res://assets/ui/codex/card_boss_dingzhen.png"},
	"boss_02_c": {"glyph": "气", "color": Color(0.56, 0.86, 1.00),
		"card": "res://assets/ui/codex/card_boss_qijun.png"},
	# 赤霄界三关（2026-10-31）：直接挂 BOSS 卡面
	"boss_03": {"glyph": "霄", "color": Color(0.96, 0.78, 0.34),
		"card": "res://assets/ui/codex/card_boss_heiliao.png"},
	"boss_03_b": {"glyph": "照", "color": Color(1.00, 0.56, 0.22),
		"card": "res://assets/ui/codex/card_boss_lizhao.png"},
	"boss_03_c": {"glyph": "咎", "color": Color(0.62, 0.86, 0.74),
		"card": "res://assets/ui/codex/card_boss_wujiu.png"},
	# 照影界（2026-11-01 / 11-02）：前两位守关者，卡面直接铺金框
	"boss_04": {"glyph": "镜", "color": Color(0.62, 0.90, 1.00),
		"card": "res://assets/ui/codex/card_boss_guanying.png"},
	"boss_04_b": {"glyph": "烛", "color": Color(0.58, 0.64, 0.92),
		"card": "res://assets/ui/codex/card_boss_zhizhu.png"},
	"boss_04_c": {"glyph": "折", "color": Color(0.86, 0.84, 0.72),
		"card": "res://assets/ui/codex/card_boss_diezhi.png"},
}
const DEFAULT_ACCENT := Color(0.52, 0.84, 1.00)

var _domain: Dictionary = {}
var _cards: Array = []
var _built := false
var _title_label: Label
var _meta_row: HBoxContainer
var _progress_label: Label
var _note: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_build()
	_built = true
	_layout()


func setup(domain: Dictionary) -> void:
	_domain = domain.duplicate(true)
	if _built:
		_rebuild_cards()
		_refresh_header()
		_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _built:
		_layout()


func _build() -> void:
	var bg := TextureRect.new()
	bg.texture = UIKit.ui_texture(UIKit.TEX_BG_BOSS_SELECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.045, 0.10)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	_build_header()
	_build_note()
	_rebuild_cards()


func _build_header() -> void:
	var bar := Control.new()
	bar.anchor_right = 1.0
	bar.offset_bottom = 58.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	var back := UIKit.quiet_button("← 位面星图", Vector2(118, 32))
	back.position = Vector2(14, 12)
	back.size = Vector2(118, 32)
	back.add_theme_font_size_override("font_size", UIKit.readable_size(UIKit.F_SMALL))
	UIKit.set_click_sfx(back, "ui_tab")
	back.pressed.connect(func() -> void: back_requested.emit())
	bar.add_child(back)

	_title_label = UIKit.outlined_label("", 22, Color(0.98, 0.95, 0.86), 6)
	_title_label.position = Vector2(148, 10)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_title_label)

	_meta_row = UIKit.hbox(8)
	_meta_row.position = Vector2(150, 34)
	_meta_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_meta_row)

	_progress_label = UIKit.outlined_label("", 11, Color(0.80, 0.86, 0.95, 0.85), 3)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_progress_label.anchor_left = 1.0
	_progress_label.anchor_right = 1.0
	_progress_label.offset_left = -300.0
	_progress_label.offset_right = -16.0
	_progress_label.offset_top = 20.0
	_progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_progress_label)


func _build_note() -> void:
	_note = UIKit.outlined_label("", 10, Color(0.78, 0.84, 0.94, 0.74), 3)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.anchor_left = 0.0
	_note.anchor_top = 1.0
	_note.anchor_right = 1.0
	_note.anchor_bottom = 1.0
	_note.offset_left = 16.0
	_note.offset_right = -16.0
	_note.offset_top = -34.0
	_note.offset_bottom = -12.0
	_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_note)


func _rebuild_cards() -> void:
	for c in _cards:
		if is_instance_valid(c.root):
			c.root.queue_free()
	_cards.clear()
	var boss_ids: Array = _domain.get("boss_ids", [])
	for i in range(boss_ids.size()):
		_cards.append(_make_card(String(boss_ids[i]), i))
	_refresh_header()


## 「需先击败 X」里的 X：本界**当前该打的那一位**（第一个还没斩的守关者）。
## 名字查不到（占位关）时退回一句通用说法，不让按钮写成「需先击败 BOSS 04-C」。
func _gate_name(did: String) -> String:
	var nid := CharacterData.domain_next_boss(did)
	var nm := WorldDB.get_boss_name(nid) if nid != "" else ""
	return nm if nm != "" and not nm.begins_with("BOSS") else "前一位守关者"


func _make_card(boss_id: String, index: int) -> Dictionary:
	var did := String(_domain.get("domain_id", ""))
	var killed := CharacterData.is_boss_cleared(did, boss_id)
	var unlocked := CharacterData.is_domain_unlocked(did)
	# 界开了 ≠ 这只轮到：守关者按序挑战（2026-11-12 用户定），见 CharacterData.is_boss_challengeable
	var can_fight := CharacterData.is_boss_challengeable(did, boss_id)
	var sigil: Dictionary = SIGILS.get(boss_id, {})
	var accent: Color = sigil.get("color", Color(0.62, 0.68, 0.78))
	var card_path := String(sigil.get("card", ""))
	if card_path != "" and ResourceLoader.exists(card_path):
		return _make_portrait_card(boss_id, index, did, killed, unlocked, can_fight,
			sigil, accent, card_path)

	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root)

	var glow := UIKit.glow_node(Vector2(10, 10), accent, 0.10)
	root.add_child(glow)

	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.015, 0.03, 0.06, 0.28)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.0)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", sb)
	root.add_child(card)

	var col := UIKit.vbox(6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(col)

	var order := UIKit.label(ORDER_TEXT[index % ORDER_TEXT.size()], 10,
		Color(accent.r, accent.g, accent.b, 0.86))
	order.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(order)

	var sigil_holder := Control.new()
	sigil_holder.custom_minimum_size = Vector2(120.0, 120.0)
	sigil_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sigil_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sigil_holder)

	var sig_glow := UIKit.glow_node(Vector2(160.0, 160.0), accent, 0.28)
	sig_glow.position = Vector2(-20.0, -20.0)
	sigil_holder.add_child(sig_glow)

	var ring := UIKit.glow_node(Vector2(118.0, 118.0), accent, 0.42, UIKit.TEX_RING_SOFT)
	ring.position = Vector2(1.0, 1.0)
	sigil_holder.add_child(ring)

	var energy_path := String(sigil.get("tex", ""))
	if energy_path != "":
		var energy_tex := UIKit.ui_texture(energy_path)
		if energy_tex != null:
			var energy := TextureRect.new()
			energy.texture = energy_tex
			energy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			energy.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			energy.position = Vector2(12.0, 12.0)
			energy.size = Vector2(96.0, 96.0)
			energy.modulate = Color(accent.r, accent.g, accent.b, 0.62)
			energy.material = UIKit.additive_material()
			energy.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sigil_holder.add_child(energy)

	var glyph_text := String(sigil.get("glyph", "影"))
	var glyph := UIKit.outlined_label(glyph_text, 46, Color(0.98, 0.96, 0.90), 8)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sigil_holder.add_child(glyph)

	var name_l := UIKit.label(WorldDB.get_boss_name(boss_id), 18, Color(0.96, 0.94, 0.88))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_l)

	var state_row := UIKit.hbox(6)
	state_row.alignment = BoxContainer.ALIGNMENT_CENTER
	state_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(state_row)
	if killed:
		state_row.add_child(UIKit.chip("已击杀", UIKit.C_DANGER))
	elif not unlocked:
		state_row.add_child(UIKit.chip("未开放", UIKit.C_DISABLE))
	elif not can_fight:
		state_row.add_child(UIKit.chip("未轮到", UIKit.C_DISABLE))
	elif not CharacterData.is_domain_realm_ok(did):
		state_row.add_child(UIKit.chip("境界不足 · 可硬闯", UIKit.C_WARN))
	else:
		state_row.add_child(UIKit.chip("可挑战", accent))

	var deaths := CharacterData.get_boss_death(did, boss_id)
	var death_text := ""
	var death_color := UIKit.C_OK
	if killed:
		var first := CharacterData.get_boss_first_clear_deaths(did, boss_id)
		if first <= 0:
			death_text = "首通无死亡"
		else:
			death_text = "首通死亡 %d 次" % first
			death_color = UIKit.C_DANGER
		if deaths > first:
			death_text += " · 累计 %d 次" % deaths
	elif deaths > 0:
		death_text = "累计死亡 %d 次" % deaths
		death_color = UIKit.C_DANGER
	if death_text != "":
		var death_lbl := UIKit.label(death_text, 10, death_color)
		death_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		death_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(death_lbl)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	if killed:
		var done := UIKit.label("已斩 · 可在万界塔再战", 10, Color(0.72, 0.78, 0.86, 0.72))
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(done)
		var stamp := _make_glyph_medallion("斩", UIKit.C_DANGER, 56.0)
		stamp.position = Vector2(8.0, 6.0)
		root.add_child(stamp)
	else:
		var btn := UIKit.primary_button("挑战", Vector2(0, 38), accent)
		btn.set_meta("tut", "domain.enter")
		btn.add_theme_font_size_override("font_size", UIKit.F_BODY)
		btn.disabled = not can_fight
		if not unlocked:
			btn.text = "未开放"
			btn.tooltip_text = CharacterData.domain_lock_reason(did)
		elif not can_fight:
			# 按钮自己把「该打谁」写出来：置灰不等于讲清机制
			btn.text = "需先击败 %s" % _gate_name(did)
			btn.set_meta("gate", CharacterData.domain_next_boss(did))
			btn.tooltip_text = CharacterData.boss_lock_reason(did, boss_id)
		else:
			UIKit.set_click_sfx(btn, "ui_confirm")
			btn.pressed.connect(func() -> void: challenge_requested.emit(did, boss_id))
		col.add_child(btn)

	card.mouse_entered.connect(_on_card_hover.bind(root, glow, card, accent, true))
	card.mouse_exited.connect(_on_card_hover.bind(root, glow, card, accent, false))

	return {
		"root": root, "card": card, "glow": glow, "accent": accent,
	}


## 有专属卡面的 BOSS：整张立绘铺满金框，底部压暗放名字 / 状态，左上盖字印。
func _make_portrait_card(boss_id: String, index: int, did: String, killed: bool,
		unlocked: bool, can_fight: bool, sigil: Dictionary, accent: Color,
		card_path: String) -> Dictionary:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root)

	var glow := UIKit.glow_node(Vector2(10, 10), accent, 0.12)
	root.add_child(glow)

	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.015, 0.03, 0.06, 0.12)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.0)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	card.add_theme_stylebox_override("panel", sb)
	root.add_child(card)

	var art := TextureRect.new()
	art.texture = load(card_path)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(art)

	# 上/下压暗，让守关者序号与底部信息压得住立绘
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.16, 0.40, 0.66, 1.0])
	grad.colors = PackedColorArray([
		Color(0.005, 0.008, 0.02, 0.72),
		Color(0.005, 0.008, 0.02, 0.16),
		Color(0.0, 0.0, 0.0, 0.0),
		Color(0.005, 0.008, 0.02, 0.50),
		Color(0.005, 0.008, 0.02, 0.94),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.0, 0.0)
	gt.fill_to = Vector2(0.0, 1.0)
	var scrim := TextureRect.new()
	scrim.texture = gt
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(scrim)

	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(overlay)

	var seal := _make_glyph_medallion(String(sigil.get("glyph", "影")), accent, 60.0)
	seal.position = Vector2(8.0, 6.0)
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(seal)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(col)

	var order := UIKit.outlined_label(ORDER_TEXT[index % ORDER_TEXT.size()], 10,
		Color(accent.r, accent.g, accent.b, 0.92), 3)
	order.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	order.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(order)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	var name_l := UIKit.outlined_label(WorldDB.get_boss_name(boss_id), 22,
		Color(0.98, 0.94, 0.86), 6)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_l)

	var state_row := UIKit.hbox(6)
	state_row.alignment = BoxContainer.ALIGNMENT_CENTER
	state_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(state_row)
	if killed:
		state_row.add_child(UIKit.chip("已击杀", UIKit.C_DANGER))
	elif not unlocked:
		state_row.add_child(UIKit.chip("未开放", UIKit.C_DISABLE))
	elif not can_fight:
		state_row.add_child(UIKit.chip("未轮到", UIKit.C_DISABLE))
	elif not CharacterData.is_domain_realm_ok(did):
		state_row.add_child(UIKit.chip("境界不足 · 可硬闯", UIKit.C_WARN))
	else:
		state_row.add_child(UIKit.chip("可挑战", accent))

	var deaths := CharacterData.get_boss_death(did, boss_id)
	var death_text := ""
	var death_color := UIKit.C_OK
	if killed:
		var first := CharacterData.get_boss_first_clear_deaths(did, boss_id)
		if first <= 0:
			death_text = "首通无死亡"
		else:
			death_text = "首通死亡 %d 次" % first
			death_color = UIKit.C_DANGER
		if deaths > first:
			death_text += " · 累计 %d 次" % deaths
	elif deaths > 0:
		death_text = "累计死亡 %d 次" % deaths
		death_color = UIKit.C_DANGER
	if death_text != "":
		var death_lbl := UIKit.label(death_text, 10, death_color)
		death_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		death_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(death_lbl)

	if killed:
		var done := UIKit.label("已斩 · 可在万界塔再战", 10, Color(0.78, 0.82, 0.88, 0.82))
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		done.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(done)
		var stamp := UIKit.outlined_label("已 斩", 26, UIKit.C_DANGER, 7)
		stamp.anchor_left = 1.0
		stamp.anchor_right = 1.0
		stamp.offset_left = -104.0
		stamp.offset_right = -14.0
		stamp.offset_top = 46.0
		stamp.offset_bottom = 90.0
		stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stamp.rotation_degrees = -12.0
		stamp.modulate.a = 0.94
		stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(stamp)
	else:
		var btn := UIKit.primary_button("挑战", Vector2(0, 38), accent)
		btn.set_meta("tut", "domain.enter")
		btn.add_theme_font_size_override("font_size", UIKit.F_BODY)
		btn.disabled = not can_fight
		if not unlocked:
			btn.text = "未开放"
			btn.tooltip_text = CharacterData.domain_lock_reason(did)
		elif not can_fight:
			# 按钮自己把「该打谁」写出来：置灰不等于讲清机制
			btn.text = "需先击败 %s" % _gate_name(did)
			btn.set_meta("gate", CharacterData.domain_next_boss(did))
			btn.tooltip_text = CharacterData.boss_lock_reason(did, boss_id)
		else:
			UIKit.set_click_sfx(btn, "ui_confirm")
			btn.pressed.connect(func() -> void: challenge_requested.emit(did, boss_id))
		col.add_child(btn)

	card.mouse_entered.connect(_on_card_hover.bind(root, glow, card, accent, true))
	card.mouse_exited.connect(_on_card_hover.bind(root, glow, card, accent, false))
	return {"root": root, "card": card, "glow": glow, "accent": accent}


func _on_card_hover(_root: Control, glow: TextureRect, card: PanelContainer,
		accent: Color, entered: bool) -> void:
	glow.modulate.a = 0.40 if entered else 0.10
	var sb := card.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if sb != null:
		sb.bg_color = Color(0.015, 0.03, 0.06, 0.40 if entered else 0.28)
		sb.border_color = Color(accent.r, accent.g, accent.b, 0.48 if entered else 0.0)
		card.add_theme_stylebox_override("panel", sb)


func _refresh_header() -> void:
	if _title_label == null:
		return
	var did := String(_domain.get("domain_id", ""))
	_title_label.text = "%s · 守关者" % String(_domain.get("name", did))

	UIKit.clear_children(_meta_row)
	var required := String(_domain.get("realm_required", ""))
	var realm_ok := CharacterData.is_domain_realm_ok(did)
	_meta_row.add_child(UIKit.chip("境界 %s%s" % [required, " · 已达标" if realm_ok else " · 未达标"],
		UIKit.C_OK if realm_ok else UIKit.C_WARN))
	if not realm_ok:
		_meta_row.add_child(UIKit.chip("可硬闯", UIKit.C_WARN))

	var boss_ids: Array = _domain.get("boss_ids", [])
	var killed := 0
	var diamonds: Array[String] = []
	for b in boss_ids:
		var down := CharacterData.is_boss_cleared(did, String(b))
		if down:
			killed += 1
		diamonds.append("◆" if down else "◇")
	if _progress_label != null:
		_progress_label.text = "%s　%d/%d 已斩" % [" ".join(diamonds), killed, boss_ids.size()]
	if boss_ids.size() < 3:
		_note.text = "守关者按序现身 · 击败前一位才轮到下一位；此界尚有 %d 位守关者未现身，首杀产出万界本源" % (3 - boss_ids.size())
	elif killed < boss_ids.size():
		_note.text = "守关者按序现身 · 击败前一位才轮到下一位；三名全部击败，此界方算通关（真实位面首杀产出万界本源）"
	else:
		_note.text = "此界守关者已尽数伏诛 · 可随时再战，重复击杀不再产出首杀本源"


## 左上单字字印：环 + 柔光 + 描边大字，沿用旧关卡字图形的观感，不用方块文字。
func _make_glyph_medallion(text: String, accent: Color, side: float) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(side, side)
	wrap.size = Vector2(side, side)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow := UIKit.glow_node(Vector2(side * 1.6, side * 1.6), accent, 0.22)
	glow.position = Vector2(-side * 0.3, -side * 0.3)
	wrap.add_child(glow)
	var ring := UIKit.glow_node(Vector2(side * 0.92, side * 0.92), accent, 0.55,
		UIKit.TEX_RING_SOFT)
	ring.position = Vector2(side * 0.04, side * 0.04)
	wrap.add_child(ring)
	var glyph := UIKit.outlined_label(text, int(round(side * 0.62)),
		Color(0.99, 0.96, 0.88), 9)
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(glyph)
	return wrap


func _layout() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	for i in range(_cards.size()):
		var c: Dictionary = _cards[i]
		# 位面尚未做满三关时把现有守关者摆在中央金框，不让卡面歪在左边
		var frame_index := i
		if _cards.size() == 1:
			frame_index = 1
		elif _cards.size() == 2:
			frame_index = i * 2
		var fr: Rect2 = FRAME_RECTS[frame_index % FRAME_RECTS.size()]
		var rect := Rect2(
			Vector2(fr.position.x * size.x, fr.position.y * size.y),
			Vector2(fr.size.x * size.x, fr.size.y * size.y)
		)
		var pad_x := 12.0
		var pad_y := 16.0
		var card_rect := Rect2(
			rect.position + Vector2(pad_x, pad_y),
			rect.size - Vector2(pad_x * 2.0, pad_y * 2.0)
		)
		var root: Control = c.root
		root.position = rect.position
		root.size = rect.size
		var card: PanelContainer = c.card
		card.position = Vector2(pad_x, pad_y)
		card.size = card_rect.size
		var glow: TextureRect = c.glow
		glow.size = rect.size + Vector2(60.0, 60.0)
		glow.position = Vector2(-30.0, -30.0)
