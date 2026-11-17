class_name RealmPanel
extends SystemPanel
## 境界（阶段2-A）—— 从角色信息面板的「修炼突破」进入
##
## 硬约束（§2.5 / §6.1）：
##   - 境界顺序固定：练气 → 筑基 → 结丹 → 元婴 → 化神，不得增删
##   - 原始位面最高境界为元婴，化神是万界位面专属突破境界，也是第一篇章终点
##
## 2026-10-24 用户定：每个大境界分「前期 / 中期 / 后期」三个小阶段。
## 2026-11-01 用户定：练气到元婴保留三小阶段；化神改为单阶段终境，修为上限 99,999。
##   - 修为只能靠吸灵气团 / 打怪获得（不再有手动「修炼」按钮）
##   - 前期 / 中期修为满 → 小突破：基础六项 +10%，灵力回复 +0.1（不需要材料）
##   - 后期修为满 → 只能击败本境界大陆核心首领拿天才地宝，再回本面板大突破：
##     基础六项 +50%，灵力回复 +0.3
##   面板会先播一段突破演出，演出中途才真正改数值，避免玩家看到「点完没反应」。

const VIEW_SIZE := Vector2(1280.0, 720.0)

var _hero_realm: Label
var _hero_stage: Label
var _stage_row: HBoxContainer
var _bar: ProgressBar
var _exp_label: Label
var _stat_grid: GridContainer
var _status_note: Label
## 突破按钮：修为圆满时做呼吸提醒（2026-10-24 用户定）
var _break_btn: Button
## 突破演出期间禁止关闭面板 / 重复点突破
var _advancing := false


func _init() -> void:
	panel_title = "境界修炼"
	panel_hint = "ESC 关闭"


func facility_visual() -> Dictionary:
	return UIKit.facility_style("realm")


func panel_size() -> Vector2:
	return Vector2(860.0, 660.0)


func can_close() -> bool:
	return not _advancing


func _build_content() -> void:
	var accent: Color = UIKit.facility_style("realm").get("accent", UIKit.C_ACCENT)

	# 境界主卡：大境界名 + 三小阶段 + 修为进度
	var hero := PanelContainer.new()
	hero.add_theme_stylebox_override("panel", UIKit.accent_card_style(accent, 0.88, 0.34, 10))
	content.add_child(hero)
	var hero_row := UIKit.hbox(14)
	hero_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(hero_row)

	var hero_left := UIKit.vbox(3)
	hero_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_row.add_child(hero_left)
	var kicker := UIKit.label("当前境界", 10, Color(accent.r, accent.g, accent.b, 0.80))
	hero_left.add_child(kicker)
	var name_row := UIKit.hbox(10)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_left.add_child(name_row)
	_hero_realm = UIKit.label("", 34, Color(0.98, 0.95, 0.88))
	name_row.add_child(_hero_realm)
	_hero_stage = UIKit.label("", 12, Color(accent.r, accent.g, accent.b, 0.92))
	_hero_stage.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(_hero_stage)

	_stage_row = UIKit.hbox(6)
	_stage_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_left.add_child(_stage_row)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.show_percentage = true
	_bar.custom_minimum_size = Vector2(0, 18)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.045, 0.055, 0.085, 0.95)
	bar_bg.border_color = Color(accent.r, accent.g, accent.b, 0.22)
	bar_bg.set_border_width_all(1)
	bar_bg.set_corner_radius_all(9)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(accent.r, accent.g, accent.b, 0.88)
	bar_fill.set_corner_radius_all(9)
	_bar.add_theme_stylebox_override("background", bar_bg)
	_bar.add_theme_stylebox_override("fill", bar_fill)
	UIKit.set_readable_font(_bar, 10)
	hero_left.add_child(_bar)
	_exp_label = UIKit.label("", 10, Color(0.70, 0.74, 0.84, 0.92))
	hero_left.add_child(_exp_label)

	hero_row.add_child(_make_realm_seal(accent))

	content.add_child(UIKit.section("修行概览", accent))
	_stat_grid = GridContainer.new()
	_stat_grid.columns = 3
	_stat_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stat_grid.add_theme_constant_override("h_separation", 8)
	_stat_grid.add_theme_constant_override("v_separation", 8)
	content.add_child(_stat_grid)

	content.add_child(UIKit.section("突破", accent))
	var break_card := PanelContainer.new()
	break_card.add_theme_stylebox_override("panel", UIKit.accent_card_style(accent, 0.62, 0.22, 8))
	content.add_child(break_card)
	var break_row := UIKit.hbox(12)
	break_card.add_child(break_row)
	_status_note = UIKit.readable_label("", 11, UIKit.C_TEXT_DIM)
	_status_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	break_row.add_child(_status_note)
	_break_btn = UIKit.primary_button("突破", Vector2(140, 42), accent)
	_break_btn.add_theme_font_size_override("font_size", UIKit.F_BODY)
	_break_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIKit.set_click_sfx(_break_btn, "ui_confirm")
	_break_btn.pressed.connect(_on_breakthrough)
	break_row.add_child(_break_btn)

	var rule := UIKit.readable_label(
		"修为来源：吸收灵气团、击败敌人。每突破一次，下一阶段所需修为 +1,000。小突破：基础属性 +10%、灵力回复 +0.1；大突破：需本境界大陆核心首领的天才地宝，基础属性 +50%、灵力回复 +0.3。化神例外 —— 要把化神底髓与化神天髓在锻造台熔铸成化神破境晶，再带它到幽冥灵墟中心的九天门开门，进九天之上登坛突破。化神为终境，修为上限 99,999，无法继续突破。",
		10, Color(0.62, 0.66, 0.74, 0.90))
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(rule)


func _make_realm_seal(accent: Color) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(112, 112)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_END
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow := UIKit.glow_node(Vector2(170, 170), accent, 0.30)
	glow.position = Vector2(-29, -29)
	holder.add_child(glow)
	var ring := UIKit.glow_node(Vector2(126, 126), accent, 0.46, UIKit.TEX_RING_SOFT)
	ring.position = Vector2(-7, -7)
	holder.add_child(ring)
	var disc := PanelContainer.new()
	disc.position = Vector2(6, 6)
	disc.custom_minimum_size = Vector2(100, 100)
	disc.size = Vector2(100, 100)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.04, 0.075, 0.88)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.40)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(50)
	disc.add_theme_stylebox_override("panel", sb)
	holder.add_child(disc)
	var glyph := UIKit.label("境", 38, Color(accent.r, accent.g, accent.b, 0.92))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_child(glyph)
	return holder


func _refresh_content() -> void:
	var d := CharacterData
	var accent: Color = UIKit.facility_style("realm").get("accent", UIKit.C_ACCENT)

	var huashen := d.is_huashen()
	_hero_realm.text = d.current_realm
	if huashen:
		_hero_stage.text = "终境 · 修为上限 %d" % d.HUASHEN_EXP_CAP
	else:
		_hero_stage.text = "%s · 第 %d / %d 段" % [d.get_realm_stage_name(), d.realm_stage + 1, d.REALM_STAGES.size()]

	UIKit.clear_children(_stage_row)
	if huashen:
		_stage_row.add_child(UIKit.chip("化神 · 当前", accent))
	else:
		for i in range(d.REALM_STAGES.size()):
			var label := String(d.REALM_STAGES[i])
			var state_color := UIKit.C_DISABLE
			if i < d.realm_stage:
				state_color = UIKit.C_OK
			elif i == d.realm_stage:
				state_color = accent
			_stage_row.add_child(UIKit.chip(label + (" · 当前" if i == d.realm_stage else ""), state_color))

	_bar.value = d.get_stage_exp_ratio() * 100.0
	var exp_req := d.get_stage_exp_required()
	if huashen:
		_exp_label.text = "化神修为 %d / %d（上限）" % [d.realm_exp, exp_req]
	else:
		_exp_label.text = "本阶段修为 %d / %d　·　%s" % [
			d.realm_exp, exp_req,
			"修为圆满" if d.is_stage_full() else "还需 %d 点" % maxi(0, exp_req - d.realm_exp),
		]

	UIKit.clear_children(_stat_grid)
	var next_text := ""
	var next_color := UIKit.C_TEXT
	if huashen:
		next_text = "已至顶点"
	elif not d.is_final_stage():
		next_text = "%s（小突破）" % d.get_next_stage_name()
	else:
		var next := d.get_next_realm()
		next_text = "%s（大突破）" % next if next != "" else "已至顶点"
		if next != "":
			next_color = _requirement_color(next)
	var stage_value := "化神（无小阶段）" if huashen \
		else "%s（第 %d / %d 段）" % [d.get_realm_stage_name(), d.realm_stage + 1, d.REALM_STAGES.size()]
	_stat_grid.add_child(_stat_card("当前阶段", stage_value, accent))
	_stat_grid.add_child(_stat_card("下一阶段", next_text, next_color))
	_stat_grid.add_child(_stat_card("万界本源", "%.0f" % d.origin_energy, UIKit.C_ACCENT))
	_stat_grid.add_child(_stat_card("位面境界上限", d.current_world_realm_limit, UIKit.C_TEXT))
	_stat_grid.add_child(_stat_card("原始位面上限", d.original_world_max_realm, UIKit.C_TEXT_DIM))
	_stat_grid.add_child(_stat_card("当前成长", "基础属性 ×%.2f　灵力回复 +%.1f" % [d.realm_stat_multiplier(), d.realm_mana_regen_bonus()], UIKit.C_OK))
	if huashen:
		_stat_grid.add_child(_stat_card("突破所需", "—", UIKit.C_TEXT_DIM))
	elif not d.is_final_stage():
		_stat_grid.add_child(_stat_card("突破所需", "修为圆满即可", UIKit.C_TEXT_DIM))
	else:
		var next := d.get_next_realm()
		_stat_grid.add_child(_stat_card("突破所需", _requirement_text(next) if next != "" else "—",
			_requirement_color(next) if next != "" else UIKit.C_TEXT_DIM))
	_stat_grid.add_child(_stat_card("本阶段修为", "%d / %d" % [d.realm_exp, exp_req], _status_color()))
	var remain := maxi(0, exp_req - d.realm_exp)
	var remain_text := "已至顶点" if huashen else ("修为圆满" if remain == 0 else "还需 %d 点" % remain)
	_stat_grid.add_child(_stat_card("距下一阶段", remain_text,
		UIKit.C_OK if remain == 0 else UIKit.C_TEXT_DIM))

	_status_note.add_theme_color_override("font_color", _status_color())
	_status_note.text = _status_text()
	_break_btn.text = "已至顶点" if huashen else ("小突破" if not d.is_final_stage() else "大突破")
	if d.is_realm_capped() and d.get_realm_index() >= d.REALM_ORDER.size() - 1:
		_break_btn.text = "已至顶点"
	_break_btn.disabled = huashen


func _stat_card(key: String, value: String, color: Color) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UIKit.accent_card_style(Color(0.72, 0.64, 0.92), 0.42, 0.16, 6))
	var col := UIKit.vbox(1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)
	var k := UIKit.label(key, 9, Color(0.58, 0.62, 0.72, 0.92))
	col.add_child(k)
	var v := UIKit.readable_label(value, 11, color)
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.max_lines_visible = 2
	v.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(v)
	return card


## 修为圆满时给「突破」按钮做呼吸提醒；没满或已到终点时不闪
func _process(_delta: float) -> void:
	if _break_btn == null:
		return
	if _advancing or not CharacterData.has_breakthrough_pending():
		_break_btn.modulate = Color.WHITE
		_break_btn.scale = Vector2.ONE
		return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
	_break_btn.modulate = Color.WHITE.lerp(Color(1.0, 0.48, 0.32, 1.0), 0.45 + 0.35 * pulse)
	_break_btn.pivot_offset = _break_btn.size * 0.5
	_break_btn.scale = Vector2.ONE * (1.0 + 0.02 * pulse)


## 突破材料清单：逐项显示「持有 / 所需」，没有登记门槛时显示「无」
func _requirement_text(next: String) -> String:
	var req := ItemDB.get_breakthrough_requirements(next)
	if req.is_empty():
		return "无材料门槛"
	var parts: Array[String] = []
	for mid in req.keys():
		parts.append("%s %d/%d" % [
			ItemDB.get_material_name(String(mid)),
			CharacterData.count_material(String(mid)),
			int(req[mid]),
		])
	return "　".join(parts)


func _requirements_met(next: String) -> bool:
	return CharacterData.has_materials(ItemDB.get_breakthrough_requirements(next))


func _requirement_color(next: String) -> Color:
	var req := ItemDB.get_breakthrough_requirements(next)
	if req.is_empty():
		return UIKit.C_TEXT_DIM
	return UIKit.C_OK if CharacterData.has_materials(req) else UIKit.C_DANGER


func _status_text() -> String:
	var d := CharacterData
	if d.is_huashen():
		return "已至化神（终境），修为上限 %d，无法继续突破。" % d.HUASHEN_EXP_CAP
	var req := d.get_stage_exp_required()
	if not d.is_stage_full():
		if d.is_final_stage():
			return "本阶段（后期）修为 %d / %d。修满后需击败本境界大陆核心首领取得天才地宝，方可大突破。" % [d.realm_exp, req]
		return "本阶段修为 %d / %d。修满后可小突破至 %s。" % [d.realm_exp, req, d.get_next_stage_name()]
	if not d.is_final_stage():
		return "修为圆满，可小突破至 %s：基础属性 +10%%，灵力回复 +0.1。" % d.get_next_stage_name()
	# 后期修为满 → 大突破
	if d.is_realm_capped():
		if d.get_realm_index() >= d.REALM_ORDER.size() - 1:
			return "已至境界顶点（化神终境），第一篇章的修行到此为止。"
		return "已达当前位面境界上限（%s）。化神为万界位面专属突破境界，需进入万界位面后方可继续。" % d.current_world_realm_limit
	var next := d.get_next_realm()
	if next == "":
		return "已至境界顶点。"
	var mat_req := ItemDB.get_breakthrough_requirements(next)
	if next == CharacterData.REALM_HUASHEN:
		# 化神走山门，不走这个按钮（见 _on_breakthrough 的同名分支）
		if not _requirements_met(next):
			return "元婴后期已圆满。化神需在幽冥灵墟中心的「九天门」开门，还缺：%s" \
				% ItemDB.materials_text(mat_req)
		return "化神破境晶在手 · 到幽冥灵墟中心的九天门开门，进九天之上后在化神坛突破。"
	if mat_req.is_empty():
		return "修为圆满，可大突破至 %s（本境界突破材料尚未登记）：基础属性 +50%%，灵力回复 +0.3。" % next
	if not _requirements_met(next):
		return "修为圆满，但突破材料不足：需要 %s" % ItemDB.materials_text(mat_req)
	return "修为圆满，材料齐备。大突破至 %s：基础属性 +50%%，灵力回复 +0.3。" % next


func _status_color() -> Color:
	var d := CharacterData
	if d.is_huashen():
		return UIKit.C_OK if d.is_stage_full() else UIKit.C_TEXT_DIM
	if not d.is_stage_full():
		return UIKit.C_TEXT_DIM
	if d.is_final_stage() and (d.is_realm_capped() or not _requirements_met(d.get_next_realm())):
		return UIKit.C_WARN
	return UIKit.C_OK


func _on_breakthrough() -> void:
	if _advancing:
		return
	var d := CharacterData
	if d.is_huashen():
		set_status("已至化神（终境），无法继续突破", UIKit.C_WARN)
		return
	if not d.is_stage_full():
		set_status("修为不足，需修满 %d（当前 %d）" % [d.get_stage_exp_required(), d.realm_exp], UIKit.C_WARN)
		return
	if d.can_break_stage():
		var target := "%s · %s" % [d.current_realm, d.get_next_stage_name()]
		_play_breakthrough("小境界突破", target, "基础属性 +10%　灵力回复 +0.1", func() -> void:
			d.break_stage()
			# 任务面板（2026-11-11）：埋在面板真实操作回调里——探针直调 break_stage 不算数
			Tutorial.note("realm_breakthrough")
			set_status("突破成功：%s" % target, UIKit.C_OK)
		)
		return
	# 后期圆满 → 大境界突破
	if d.is_realm_capped():
		set_status("已达当前位面境界上限，需进入万界位面才能继续突破", UIKit.C_WARN)
		return
	var next := d.get_next_realm()
	if next == "":
		set_status("已至境界顶点", UIKit.C_WARN)
		return
	## 化神不在面板里点（2026-11-02 用户定）：完整的化神破境晶要交到幽冥灵墟中心、
	## 由元婴区首领镇墟石犼镇守的九天门上，进门后在化神坛才真正突破。
	## 这里若允许就地突破，晶会被面板吃掉、门就永远开不了，所以只指路、不动账。
	if next == CharacterData.REALM_HUASHEN:
		set_status("化神需到幽冥灵墟中心的「九天门」开门：带上熔铸好的化神破境晶，站到首领身后的门前按 F",
			UIKit.C_WARN)
		return
	# 突破材料由对应区域的核心首领产出（练气→筑基：筑基破境晶）
	# 先检查、演出中途再真正扣除：演出刚开始就退出游戏也不会白丢材料
	var req := ItemDB.get_breakthrough_requirements(next)
	if not d.has_materials(req):
		set_status("突破材料不足：需要 %s" % ItemDB.materials_text(req), UIKit.C_DANGER)
		return
	# 化神是单阶段终境，不再显示「· 前期」
	var target_label := next if next == CharacterData.REALM_HUASHEN else "%s · 前期" % next
	_play_breakthrough("大境界突破", target_label, "基础属性 +50%　灵力回复 +0.3", func() -> void:
		if not req.is_empty() and not d.consume_materials(req):
			return
		d.break_realm(next)
		# 任务面板（2026-11-11）：大突破同样埋在真实回调里
		Tutorial.note("realm_breakthrough")
		# 位面境界上限随所在位面推进而提升（正式规则：解锁下一界域后提升）
		if next == CharacterData.REALM_HUASHEN:
			d.current_world_realm_limit = CharacterData.REALM_HUASHEN
		set_status("突破成功：%s" % target_label, UIKit.C_OK)
	)


## 突破演出：压暗 → 金光 → 境界名放大浮现 → 中途真正进阶 → 淡出
## ⚠ 面板打开时 tree.paused = true，补间必须显式设成「暂停也运行」
func _play_breakthrough(kicker: String, headline: String, bonus: String, on_advance: Callable) -> void:
	_advancing = true
	var layer := Control.new()
	layer.size = VIEW_SIZE
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.0)
	shade.size = VIEW_SIZE
	layer.add_child(shade)

	var glow := ColorRect.new()
	glow.color = Color(1.0, 0.8, 0.42, 0.0)
	glow.size = VIEW_SIZE
	layer.add_child(glow)

	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.size = VIEW_SIZE
	center.pivot_offset = VIEW_SIZE * 0.5
	center.modulate.a = 0.0
	layer.add_child(center)

	var kicker_label := UIKit.label(kicker, UIKit.F_SMALL, UIKit.C_TEXT_DIM)
	kicker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(kicker_label)

	var title_label := Label.new()
	title_label.text = headline
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 42)
	title_label.add_theme_color_override("font_color", UIKit.C_ACCENT)
	center.add_child(title_label)

	var bonus_label := UIKit.label(bonus, UIKit.F_BODY, UIKit.C_OK)
	bonus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(bonus_label)

	GameState.play_ui_delayed("forge_great", 0.12)

	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(shade, "color:a", 0.94, 0.22)
	tw.parallel().tween_property(center, "modulate:a", 1.0, 0.22)
	tw.parallel().tween_property(glow, "color:a", 0.36, 0.12)
	tw.parallel().tween_property(center, "scale", Vector2.ONE, 0.45).from(Vector2(0.82, 0.82))
	tw.tween_property(glow, "color:a", 0.06, 0.4)
	tw.tween_interval(0.55)
	tw.tween_callback(on_advance)
	tw.tween_interval(0.35)
	tw.tween_property(shade, "color:a", 0.0, 0.35)
	tw.parallel().tween_property(glow, "color:a", 0.0, 0.35)
	tw.parallel().tween_property(center, "modulate:a", 0.0, 0.3)
	tw.tween_callback(_finish_breakthrough.bind(layer))


func _finish_breakthrough(layer: Control) -> void:
	_advancing = false
	if is_instance_valid(layer):
		layer.queue_free()
	_refresh_content()
