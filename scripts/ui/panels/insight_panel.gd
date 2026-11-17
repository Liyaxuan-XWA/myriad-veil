class_name InsightPanel
extends SystemPanel
## 功法感悟面板 —— 万界塔首杀投影后「就地感悟」
##
## 设计（用户确认）：
##   - **不在击杀瞬间自动发放**。BOSS 倒下 → 战斗内弹出本面板 → 玩家点「确认收下」才入册。
##   - 概率完全沿用原先设计：必得 1 门 / 30% 得 2 门 / 5% 得全部（见 WorldDB.roll_floor_reward_skills）。
##   - 玩家**不能自选**：结果由概率决定，本面板只负责展示与确认。
##   - ESC 等同「确认收下」，不存在「误关掉就白打一场」的坑。
##
## 数据来源：BattleResolver.resolve_victory() 返回的 insight 列表
## （首杀标记与写入 learned_skills 都在 BattleResolver.confirm_tower_rewards() 里做）
##
## 美术接入（长期约定）：
##   - 功法图标走 UIKit.icon_node → 在 skill_db.gd 的 SKILLS[].icon 填路径即可换成贴图
##   - 卡片底图 / 按钮 / 配色全部来自 ui_kit.gd（换皮只改样式工厂与 C_* 常量）
##   - 卡片登场动画目前是纯 UI 淡入；将来要做正式感悟演出，可在 art_db.gd 的 EFFECTS
##     登记一个 "insight_glow" 条目，用 FxPlayer.spawn() 替换这一段

var floor_no: int = 0
var skill_ids: Array = []

var _cards_box: VBoxContainer


func _init() -> void:
	panel_title = "功法感悟"
	panel_hint = "ESC = 确认收下"

func facility_visual() -> Dictionary:
	return UIKit.facility_style("insight")



## 必须在 add_child（触发 _ready）之前调用
func setup(floor: int, ids: Array) -> void:
	floor_no = floor
	skill_ids = ids.duplicate()


func panel_size() -> Vector2:
	return Vector2(880.0, 560.0)


func _input(event: InputEvent) -> void:
	# 本面板不允许「跳过奖励」：ESC 直接等同确认，避免误关导致白打
	if not _visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_confirm()
			return
	super(event)


func _build_content() -> void:
	var accent: Color = UIKit.facility_style("insight").get("accent", UIKit.C_ACCENT)
	content.add_child(UIKit.note_card(
		"万界塔第 %d 层首杀，按该层规则随机感悟：必得 1 门，约三成得 2 门，极小概率得全部。" % floor_no,
		accent))
	content.add_child(UIKit.note_card(
		"感悟到的就是投影 BOSS 正在施展的那些招式 —— 同一份形态数据，但消耗、冷却与伤害都按你自己的属性计算。",
		accent))

	_cards_box = UIKit.vbox(8)
	content.add_child(_cards_box)

	var btn_row := UIKit.hbox(10)
	content.add_child(btn_row)
	btn_row.add_child(UIKit.spacer())
	var confirm := UIKit.primary_button("确认收下", Vector2(180, 44),
		UIKit.facility_style("insight").get("accent", UIKit.C_ACCENT))
	confirm.add_theme_font_size_override("font_size", UIKit.F_SUBTITLE)
	confirm.pressed.connect(_on_confirm)
	# 新手指引锚点：c5 首通感悟教玩家点「确认收下」（面板是击杀后才弹的，
	# 聚光靠 overlay 的锚点重试补扫）
	confirm.set_meta("tut", "insight.confirm")
	btn_row.add_child(confirm)


func _refresh_content() -> void:
	UIKit.clear_children(_cards_box)
	if skill_ids.is_empty():
		_cards_box.add_child(UIKit.label("本次没有可感悟的功法", UIKit.F_BODY, UIKit.C_WARN))
		return
	for sid in skill_ids:
		_cards_box.add_child(_make_card(String(sid)))

	# 卡片依次淡入（只动 modulate —— 容器会接管 position/size，位移类动画会被布局覆盖）
	var i := 0
	for c in _cards_box.get_children():
		var ctrl := c as Control
		if ctrl == null:
			continue
		ctrl.modulate.a = 0.0
		var t := ctrl.create_tween()
		t.tween_interval(0.08 * float(i))
		t.tween_property(ctrl, "modulate:a", 1.0, 0.22)
		i += 1


## 单门功法卡片：图标 + 名称 + 风味文案 + 效果说明（效果由招式数据现算）
func _make_card(sid: String) -> Control:
	var skill := SkillDB.get_skill(sid)
	var is_active := String(skill.get("skill_type", "")) == SkillDB.TYPE_ACTIVE
	var accent: Color = UIKit.facility_style("insight").get("accent", UIKit.C_ACCENT)
	var skill_name := String(skill.get("skill_name", ""))

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		UIKit.accent_card_style(accent, 0.58, 0.28, 7))

	var hb := UIKit.hbox(12)
	card.add_child(hb)
	hb.add_child(UIKit.facility_disc(
		{"accent": accent, "glyph": skill_name.substr(0, 1)}, 50))

	var info := UIKit.vbox(3)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(info)

	var type_text := "主动功法" if is_active else "被动功法"
	var head := UIKit.hbox(8)
	head.add_child(UIKit.label(skill_name, 16, Color(0.97, 0.92, 0.82)))
	head.add_child(UIKit.chip(type_text, accent, 10))
	head.add_child(UIKit.chip("新", UIKit.C_DANGER, 10))
	info.add_child(head)
	# 效果说明只走 SkillDB（功法库、格子 tooltip、这里三处共用一套），别手写数值
	for item in SkillDB.get_effect_lines(sid):
		info.add_child(UIKit.label(String(item.get("text", "")), UIKit.F_SMALL,
			UIKit.C_ACCENT if bool(item.get("accent", false)) else UIKit.C_TEXT_DIM))
	return card


## 确认收下：写入 learned_skills + 标记塔层首杀（真正的入册只发生在这里）
func _on_confirm() -> void:
	var learned := BattleResolver.confirm_tower_rewards()
	if learned.is_empty():
		set_status("没有新增功法（该层功法你已全部掌握）", UIKit.C_WARN)
	else:
		var names: Array[String] = []
		for sid in learned:
			names.append(SkillDB.get_skill_name(String(sid)))
		set_status("已习得：%s" % "、".join(names))
	close()
