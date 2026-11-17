class_name MemoryPanel
extends SystemPanel
## 记忆幻像碑（阶段2-H）
##
## 任务书 §5.7：万界本源积累 → 记忆碎片逐步解锁 → 主城回放
## 当前实现：按剧情进度解锁碎片，解锁后可回放（文本形式，正式演出待美术/剧情定稿）
##
## 2026-10-25 视觉升级：碎片做成碑刻条目，回放区做成碑文纸卡；逻辑不变。

var _list_box: VBoxContainer
var _playback: Label


func _init() -> void:
	panel_title = "记忆幻像碑"
	panel_hint = "ESC 关闭"


func facility_visual() -> Dictionary:
	return UIKit.facility_style("memory")


func _accent() -> Color:
	return UIKit.facility_style("memory").get("accent", UIKit.C_ACCENT)


func _build_content() -> void:
	var accent := _accent()
	content.add_child(UIKit.note_card(
		"随着万界本源积累与剧情推进，记忆碎片逐步解锁，可在主城回放。", accent))
	content.add_child(UIKit.section("碑上残影", accent))
	_list_box = UIKit.vbox(7)
	content.add_child(_list_box)

	content.add_child(UIKit.section("回放", accent))
	var playback_card := PanelContainer.new()
	playback_card.add_theme_stylebox_override("panel",
		UIKit.accent_card_style(accent, 0.58, 0.24, 7))
	content.add_child(playback_card)
	var pv := UIKit.vbox(4)
	playback_card.add_child(pv)
	pv.add_child(UIKit.label("碑文", 10, Color(accent.r, accent.g, accent.b, 0.82)))
	_playback = UIKit.readable_note("选择一枚已解锁的记忆碎片进行回放。")
	_playback.custom_minimum_size = Vector2(0, 72)
	pv.add_child(_playback)


func _refresh_content() -> void:
	UIKit.clear_children(_list_box)
	for m in WorldDB.MEMORY_FRAGMENTS:
		_list_box.add_child(_make_fragment_row(m))


func _make_fragment_row(m: Dictionary) -> Control:
	var fid := String(m.get("memory_fragment_id", ""))
	var unlocked := CharacterData.is_memory_unlocked(fid)
	var requirement := int(m.get("story_progress_requirement", 0))
	var req_ok := CharacterData.story_progress >= requirement
	var accent := _accent()

	var row := PanelContainer.new()
	var sb := UIKit.accent_card_style(accent if unlocked else UIKit.C_SLOT_BORDER,
		0.62 if unlocked else 0.42, 0.32 if unlocked else 0.14, 7)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", sb)

	var hbox := UIKit.hbox(12)
	row.add_child(hbox)

	var mark := UIKit.facility_disc({"accent": accent, "glyph": "忆"}, 42)
	hbox.add_child(mark)

	var info := UIKit.vbox(3)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)
	var head := UIKit.hbox(8)
	head.add_child(UIKit.label(String(m.get("title", "")), 16,
		Color(0.97, 0.92, 0.82) if unlocked else Color(0.72, 0.72, 0.76)))
	head.add_child(UIKit.chip(String(m.get("memory_type", "")), accent, 10))
	if unlocked:
		head.add_child(UIKit.chip("可回放", UIKit.C_OK, 10))
	info.add_child(head)
	info.add_child(UIKit.readable_label("解锁条件：%s" % String(m.get("unlock_requirement", "")),
		10, UIKit.C_TEXT_DIM))

	hbox.add_child(UIKit.spacer())

	if unlocked:
		var state := CharacterData.get_memory_playback_state(fid)
		hbox.add_child(UIKit.chip(state, UIKit.C_OK if state == "已回放" else UIKit.C_TEXT_DIM, 10))
		var btn := UIKit.button("回放", Vector2(80, 32), "default", accent)
		btn.pressed.connect(_on_play.bind(m))
		hbox.add_child(btn)
	elif req_ok:
		hbox.add_child(UIKit.chip("可解锁", accent, 10))
		var btn := UIKit.primary_button("解锁", Vector2(86, 34), accent)
		btn.pressed.connect(_on_unlock.bind(fid))
		hbox.add_child(btn)
	else:
		hbox.add_child(UIKit.chip("剧情进度不足", UIKit.C_DISABLE, 10))
	return row


func _on_unlock(fid: String) -> void:
	CharacterData.unlock_memory(fid)
	set_status("已解锁记忆碎片：%s" % String(WorldDB.get_fragment(fid).get("title", fid)))
	_refresh_content()


func _on_play(m: Dictionary) -> void:
	var fid := String(m.get("memory_fragment_id", ""))
	if not CharacterData.is_memory_unlocked(fid):
		set_status("该碎片尚未解锁", UIKit.C_WARN)
		return
	CharacterData.mark_memory_played(fid)
	_playback.text = "【%s】%s\n\n%s" % [
		String(m.get("memory_type", "")),
		String(m.get("title", "")),
		String(m.get("desc", "")),
	]
	_playback.add_theme_color_override("font_color", UIKit.C_TEXT)
	set_status("回放完成：%s" % String(m.get("title", "")))
	_refresh_content()
