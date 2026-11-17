extends CanvasLayer
class_name DebugItemPanel
## 道具获取调试面板（2026-10-21 用户专用）
##
## 开关：**F2**。用途：一键拿装备 / 材料 / 元魂 / 法宝 / 修为，快速造「破损装备」「满强化法宝」
## 「修为圆满」，省去反复刷塔的时间；战斗中也能用（不暂停游戏）。
##
## ⚠ 打包后别人用不了：
##   本节点只在 `GameState` 里、且 `OS.has_feature("editor")` 为真时才创建。
##   导出包（debug / release 都一样）里 `has_feature("editor")` 恒为 false，
##   所以面板**根本不会被实例化**，F2 也不会有人监听 —— 不是靠隐藏或密码挡住。

const PANEL_SIZE := Vector2(700, 560)
const LAYER := 90          # 高于 HUD（默认 0）与大多数面板

var _root: PanelContainer
var _bag_label: Label
var _exp_label: Label
## 上一次点修为的回执（只给面板自己看，用来区分「加了」和「到顶没加」）
var _exp_note := ""

## 调试面板给「快捷操作」用的批量数字
const MATERIAL_BATCH := 20
## 修为批量：小值用来一格一格试突破，大值用来快速跨阶段
const EXP_SMALL := 100
const EXP_LARGE := 1000


func _ready() -> void:
	layer = LAYER
	# 暂停时也能操作（战斗里按 ESC 弹确认框之类）
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F2:
			visible = not visible
			if visible:
				_refresh_bag_label()
			get_viewport().set_input_as_handled()


# ===================== 构建 =====================

func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_root = PanelContainer.new()
	_root.custom_minimum_size = PANEL_SIZE
	_root.add_theme_stylebox_override("panel", UIKit.panel_style())
	center.add_child(_root)

	var col := UIKit.vbox(10)
	_root.add_child(col)

	# 标题行：只放标题与背包计数
	# ⚠ 提示文字不能塞进这个 HBox：Label 在 HBox 里没有最小宽度，会被挤成竖排（实测过）
	var head := UIKit.hbox(10)
	head.add_child(UIKit.label("道具获取（调试）", UIKit.F_TITLE, UIKit.C_ACCENT))
	head.add_child(UIKit.spacer())
	_bag_label = UIKit.label("", UIKit.F_SMALL, UIKit.C_TEXT_DIM)
	head.add_child(_bag_label)
	col.add_child(head)
	col.add_child(UIKit.note("F2 关闭 · 仅编辑器内可用，导出包里没有这个面板"))

	# 页签
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(tabs)

	var p_equip := _build_equipment_page()
	p_equip.name = "装备"
	tabs.add_child(p_equip)

	var p_mat := _build_material_page()
	p_mat.name = "材料元魂"
	tabs.add_child(p_mat)

	var p_treasure := _build_treasure_page()
	p_treasure.name = "法宝"
	tabs.add_child(p_treasure)

	var p_quick := _build_quick_page()
	p_quick.name = "快捷"
	tabs.add_child(p_quick)

	_refresh_bag_label()


## 每页统一用「滚动容器 + 竖排列表」
func _make_list() -> Array:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var list := UIKit.vbox(4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return [scroll, list]


func _build_equipment_page() -> Control:
	var box := UIKit.vbox(6)
	var parts := _make_list()
	box.add_child(parts[0])
	var list: VBoxContainer = parts[1]

	for tpl in ItemDB.EQUIPMENT_TEMPLATES:
		var row := UIKit.hbox(8)
		var name := "%s（%s）" % [
			String(tpl.get("equipment_name", "?")), String(tpl.get("equipment_grade", ""))]
		var name_label := UIKit.label(name, UIKit.F_BODY)
		name_label.custom_minimum_size = Vector2(300, 0)
		row.add_child(name_label)

		var b1 := UIKit.button("获取", Vector2(90, 28))
		b1.pressed.connect(_grant_equipment.bind(tpl, false))
		row.add_child(b1)

		var b2 := UIKit.button("破损版", Vector2(90, 28))
		b2.tooltip_text = "直接生成「已破损、磨损满」的实例，用来测合成台"
		b2.pressed.connect(_grant_equipment.bind(tpl, true))
		row.add_child(b2)

		row.add_child(UIKit.spacer())
		list.add_child(row)
	return box


func _build_material_page() -> Control:
	var box := UIKit.vbox(6)
	var parts := _make_list()
	box.add_child(parts[0])
	var list: VBoxContainer = parts[1]

	for mat in ItemDB.MATERIALS:
		var row := UIKit.hbox(8)
		var mid := String(mat.get("id", ""))
		var label_text := String(mat.get("name", mid))
		if String(mat.get("rarity", "")) == "epic":
			label_text += "（紫色）"
		var name_label := UIKit.label(label_text, UIKit.F_BODY,
			ItemDB.rarity_color(String(mat.get("rarity", ""))))
		name_label.custom_minimum_size = Vector2(300, 0)
		row.add_child(name_label)

		var b1 := UIKit.button("+%d" % MATERIAL_BATCH, Vector2(90, 28))
		b1.pressed.connect(_grant_material.bind(mid, MATERIAL_BATCH))
		row.add_child(b1)

		var b2 := UIKit.button("+99", Vector2(90, 28))
		b2.pressed.connect(_grant_material.bind(mid, 99))
		row.add_child(b2)

		row.add_child(UIKit.spacer())
		list.add_child(row)
	return box


func _build_treasure_page() -> Control:
	var box := UIKit.vbox(6)
	var parts := _make_list()
	box.add_child(parts[0])
	var list: VBoxContainer = parts[1]

	for tpl in ItemDB.get_treasure_templates():
		var row := UIKit.hbox(8)
		var name_label := UIKit.label(String(tpl.get("treasure_name", "?")), UIKit.F_BODY,
			UIKit.C_ASCEND)
		name_label.custom_minimum_size = Vector2(300, 0)
		row.add_child(name_label)

		var b1 := UIKit.button("获取", Vector2(90, 28))
		b1.pressed.connect(_grant_treasure.bind(tpl, false))
		row.add_child(b1)

		var b2 := UIKit.button("满强化", Vector2(90, 28))
		b2.tooltip_text = "直接给一件强化 10 级、已进阶 2 次的法宝（测召唤强度/时长）"
		b2.pressed.connect(_grant_treasure.bind(tpl, true))
		row.add_child(b2)

		row.add_child(UIKit.spacer())
		list.add_child(row)
	return box


func _build_quick_page() -> Control:
	var box := UIKit.vbox(10)
	box.add_child(UIKit.note("常用组合，省去反复刷塔"))

	var b1 := UIKit.button("锻造晶石 +100", Vector2(240, 34))
	b1.pressed.connect(_grant_material.bind(CharacterData.ENHANCE_MATERIAL, 100))
	box.add_child(b1)

	var b2 := UIKit.button("所有元魂各 +1", Vector2(240, 34))
	b2.pressed.connect(_grant_all_souls)
	box.add_child(b2)

	var b3 := UIKit.button("所有法宝各 +1（满强化）", Vector2(240, 34))
	b3.pressed.connect(_grant_all_treasures)
	box.add_child(b3)

	var b4 := UIKit.button("所有装备各 +1（破损版）", Vector2(240, 34))
	b4.pressed.connect(_grant_all_broken_equipment)
	box.add_child(b4)

	# ---- 修为 ----
	# ⚠ 只加**本阶段**的修为：`add_realm_exp` 到上限就返回 0，不会替你突破。
	#   这是刻意的 —— 突破要材料/境界门槛（属内容定稿范围），面板一键跨境界
	#   会把「修为满 → 去突破」这条正要测的链路跳过去。到顶了点「补满」也一样，
	#   回执会写清楚为什么不涨。
	box.add_child(UIKit.note("修为（本阶段上限内，不代做突破）"))
	var e1 := UIKit.button("修为 +%d" % EXP_SMALL, Vector2(240, 34))
	e1.pressed.connect(_grant_exp.bind(EXP_SMALL))
	box.add_child(e1)

	var e2 := UIKit.button("修为 +%d" % EXP_LARGE, Vector2(240, 34))
	e2.pressed.connect(_grant_exp.bind(EXP_LARGE))
	box.add_child(e2)

	var e3 := UIKit.button("补满本阶段修为", Vector2(240, 34))
	e3.tooltip_text = "一次加到当前小阶段上限，用来测突破提醒 / 灰化按钮"
	e3.pressed.connect(_fill_exp)
	box.add_child(e3)

	_exp_label = UIKit.label("", UIKit.F_SMALL, UIKit.C_TEXT_DIM)
	_exp_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_exp_label)
	_refresh_exp_label()

	return box


## 加修为并把「实际到账」写进回执：只加不显示的话，到顶那一次点下去毫无反应，
## 看着像按钮坏了（本阶段已满时 add_realm_exp 返回 0）。
func _grant_exp(amount: int) -> void:
	var gained := CharacterData.add_realm_exp(amount)
	_exp_note = "+%d → 实际 %d" % [amount, gained]
	if gained <= 0:
		_exp_note = "+%d → 未增加（本阶段已满，先去突破）" % amount
	_refresh_exp_label()


func _fill_exp() -> void:
	var need := CharacterData.get_stage_exp_required() - int(CharacterData.realm_exp)
	var gained := CharacterData.add_realm_exp(need)
	_exp_note = "补满 → 实际 +%d" % gained
	if gained <= 0:
		_exp_note = "补满 → 本来就是满的"
	_refresh_exp_label()


func _refresh_exp_label() -> void:
	if _exp_label == null:
		return
	var req := CharacterData.get_stage_exp_required()
	var stage := "%s%s" % [CharacterData.current_realm, CharacterData.get_realm_stage_name()]
	_exp_label.text = "修为 %d / %d（%s）%s" % [
		int(CharacterData.realm_exp), req, stage,
		"　· 本阶段已满，需突破" if int(CharacterData.realm_exp) >= req else ""]
	if _exp_note != "":
		_exp_label.text += "\n上一次：%s" % _exp_note


# ===================== 操作 =====================

func _grant_equipment(tpl: Dictionary, broken: bool) -> void:
	var item := CharacterData.make_equipment_instance(tpl)
	if broken:
		item["is_broken"] = true
		item["enhance_fail_count"] = ItemDB.ENHANCE_FAIL_LIMIT
	CharacterData.add_item(item)
	_refresh_bag_label()


func _grant_material(material_id: String, count: int) -> void:
	CharacterData.grant_material(material_id, count)
	_refresh_bag_label()


func _grant_treasure(tpl: Dictionary, maxed: bool) -> void:
	var item := CharacterData.make_treasure_instance(tpl)
	if maxed:
		item["enhancement_level"] = ItemDB.MAX_ENHANCE
		item["summon_boost_count"] = 10      # +20% 气血/攻击
		item["summon_duration_bonus"] = 2    # +10 秒
	CharacterData.add_item(item)
	_refresh_bag_label()


func _grant_all_souls() -> void:
	for mat in ItemDB.MATERIALS:
		var mid := String(mat.get("id", ""))
		if ItemDB.is_soul_item(mid):
			CharacterData.grant_material(mid, 1)
	_refresh_bag_label()


func _grant_all_treasures() -> void:
	for tpl in ItemDB.get_treasure_templates():
		_grant_treasure(tpl, true)


func _grant_all_broken_equipment() -> void:
	for tpl in ItemDB.EQUIPMENT_TEMPLATES:
		_grant_equipment(tpl, true)


func _refresh_bag_label() -> void:
	if _bag_label == null:
		return
	_bag_label.text = "背包：%d 件 · 晶石 ×%d" % [
		CharacterData.inventory.size(),
		CharacterData.count_material(CharacterData.ENHANCE_MATERIAL),
	]
	# 任何一次发放都顺带刷修为行：它读的是 CharacterData，别的页也可能间接改到
	_refresh_exp_label()
