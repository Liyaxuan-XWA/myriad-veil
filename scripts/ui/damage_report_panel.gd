class_name DamageReportPanel
extends Control
## 打完 BOSS 的「伤害统计」面板（2026-11-12 用户定）
##   · 固定大小、贴屏幕左侧；**不拦鼠标**（玩家还要走过去捡掉落）
##   · 不只是数字：每行一条相对长度的条，一眼看得出谁在划水
##   · 由 CombatArena 在 BOSS 死亡那一刻建：只给真实位面战 / 万界塔

const PANEL_W := 300.0
const ROW_H := 24.0
const HEAD_H := 52.0
const PAD := 12.0
const BAR_W := 112.0


## 建好并挂到 parent（parent 一般是 $HUD）。`rows` 来自 DamageMeter.ranked()。
static func create(rows: Array, total: float, seconds: float) -> DamageReportPanel:
	var p := DamageReportPanel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HEAD_H + ROW_H * float(rows.size()) + PAD
	p.size = Vector2(PANEL_W, h)
	p.position = Vector2(-PANEL_W - 8.0, 150.0)   # 从屏幕外滑进来
	p.custom_minimum_size = p.size
	p._build(rows, total, seconds)
	return p


func _build(rows: Array, total: float, seconds: float) -> void:
	var accent := Color(0.92, 0.79, 0.44)
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_theme_stylebox_override("panel", UIKit.accent_card_style(accent, 0.92, 0.55, 8))
	add_child(card)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", PAD)
	margin.add_theme_constant_override("margin_right", PAD)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)

	var col := UIKit.vbox(4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	# 抬头：标题 + 总计
	var head := UIKit.hbox(8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(UIKit.label("伤害统计", UIKit.F_BODY, Color(0.98, 0.94, 0.82)))
	head.add_child(UIKit.spacer())
	var sum_lbl := UIKit.label(_num(total), UIKit.F_BODY, Color(1.0, 0.90, 0.62))
	sum_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sum_lbl)
	col.add_child(head)

	# 副行：用时 + 每秒
	var dps := 0.0 if seconds <= 0.05 else total / seconds
	var sub := UIKit.label("用时 %s · 每秒 %s" % [CharacterData.format_duration(seconds), _num(dps)],
		UIKit.F_SMALL, Color(0.80, 0.78, 0.70, 0.9))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sub)

	var rule := ColorRect.new()
	rule.color = Color(accent.r, accent.g, accent.b, 0.28)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)

	var top_amount := 0.0
	for r in rows:
		top_amount = maxf(top_amount, float((r as Dictionary).get("amount", 0.0)))

	for i in rows.size():
		var r: Dictionary = rows[i]
		var amount := float(r.get("amount", 0.0))
		var ratio := 0.0 if top_amount <= 0.0 else clampf(amount / top_amount, 0.0, 1.0)
		var pct := 0.0 if total <= 0.0 else amount / total * 100.0
		var rank_color := Color(1.0, 0.90, 0.62) if i == 0 else Color(0.86, 0.82, 0.74)
		col.add_child(_row(String(r.get("tag", "其他")), ratio, amount, pct, rank_color, i == 0))

	# 入场：从左边滑进来 + 淡入（面板在 HUD 下，暂停时也要动 → 用 SCENE 的 tween 由调用方保证不停）
	modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(self, "position:x", 14.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.28)


## 一行：名字 | 条 | 数字 + 占比
func _row(tag: String, ratio: float, amount: float, pct: float,
		text_color: Color, bright: bool) -> Control:
	var row := UIKit.hbox(6)
	row.custom_minimum_size = Vector2(0, ROW_H)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name_l := UIKit.label(tag, UIKit.F_SMALL, text_color)
	name_l.custom_minimum_size = Vector2(92, 0)
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_l)

	var bar := UIKit.mini_progress(ratio, Color(0.92, 0.79, 0.44, 0.95 if bright else 0.62),
		Vector2(BAR_W, 7.0))
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)

	row.add_child(UIKit.spacer())
	var val := UIKit.label("%s  %d%%" % [_num(amount), int(round(pct))],
		UIKit.F_SMALL, text_color)
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(val)
	return row


## 大数字按千位加逗号：DPS / 伤害动辄五位数，不加逗号读不出来
static func _num(v: float) -> String:
	var n := int(round(maxf(v, 0.0)))
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out
