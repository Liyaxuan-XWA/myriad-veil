class_name RogueSettlePanel
extends SystemPanel
## 试炼之路结算卷轴：到达层数 / 击败 BOSS / 晶石 / 解锁提示
##
## 进入前必须先 RogueRun.finish_run()：本面板只读 pending_result，不碰角色数据。

signal again_requested
signal leave_requested

var result: Dictionary = {}

var _box: VBoxContainer


func _init() -> void:
	panel_title = "试炼结算"
	panel_hint = "本次试炼已结束 · 选下一步"


func facility_visual() -> Dictionary:
	return UIKit.facility_style("insight")


func panel_size() -> Vector2:
	# ⚠ 不要改成 content_scrolls()=false：那样 content 会撑开 _root，
	#   面板从 420 长到 655 直接出屏（2026-11-08 实测）。高度就按内容量手调。
	return Vector2(720.0, 420.0)


## 必须在 add_child 之前调用
func setup(p_result: Dictionary) -> void:
	result = p_result.duplicate(true)


func can_close() -> bool:
	return false


## 必须点「再入试炼」或「返回主城」二选一，不给死按钮
func shows_close_button() -> bool:
	return false


func _build_content() -> void:
	var accent: Color = UIKit.facility_style("insight").get("accent", UIKit.C_ACCENT)
	content.add_child(UIKit.note_card("试炼之路的收获已入包，离开后可在锻造处使用。", accent))
	_box = UIKit.vbox(6)
	content.add_child(_box)

	# 不塞伸展 spacer：滚动容器里的 spacer 不会把按钮压到底，只会留一段说不清的死白
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 12.0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(gap)
	var btn_row := UIKit.hbox(12)
	content.add_child(btn_row)
	btn_row.add_child(UIKit.spacer())
	var again := UIKit.primary_button("再入试炼", Vector2(180, 44), accent)
	again.add_theme_font_size_override("font_size", UIKit.F_SUBTITLE)
	again.pressed.connect(_on_again)
	btn_row.add_child(again)
	var leave := UIKit.primary_button("返回主城", Vector2(180, 44), UIKit.C_ACCENT)
	leave.add_theme_font_size_override("font_size", UIKit.F_SUBTITLE)
	leave.pressed.connect(_on_leave)
	btn_row.add_child(leave)


func _refresh_content() -> void:
	if _box == null:
		return
	UIKit.clear_children(_box)
	var reached := int(result.get("floor", 1))
	var lines: Array = [
		["到达层数", "第 %d 层" % reached, UIKit.C_TITLE],
		["击败 BOSS", "%d 只" % int(result.get("boss_kills", 0)), UIKit.C_TEXT],
		["通关关卡", "%d 关 · 过 %d 层" % [int(result.get("stages", 0)),
			int(result.get("floors", 0))], UIKit.C_TEXT],
		["锻造晶石", "+%d" % int(result.get("crystals", 0)), UIKit.C_GREAT],
		["历史最高", "第 %d 层%s" % [int(result.get("best", reached)),
			"　新纪录" if bool(result.get("new_best", false)) else ""], UIKit.C_TEXT],
	]
	if bool(result.get("by_death", false)):
		lines.append(["结局", "第二次倒下，试炼终止", UIKit.C_WARN])
	for raw in lines:
		var row: Array = raw
		var hb := UIKit.hbox(10)
		var key := UIKit.label(String(row[0]), 14, UIKit.C_TEXT_DIM)
		key.custom_minimum_size = Vector2(110.0, 24.0)
		hb.add_child(key)
		hb.add_child(UIKit.label(String(row[1]), 16, row[2]))
		_box.add_child(hb)
	var unlocked: Array = result.get("unlocked", [])
	if not unlocked.is_empty():
		var names: Array[String] = []
		for raw_fam in unlocked:
			names.append(String(RogueDB.FAMILY_NAME.get(String(raw_fam), String(raw_fam))))
		_box.add_child(UIKit.readable_label("解锁流派：%s" % "、".join(names), 14, UIKit.C_ACCENT))


func _on_again() -> void:
	close()
	again_requested.emit()


func _on_leave() -> void:
	close()
	leave_requested.emit()
