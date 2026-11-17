class_name FarmSeedPanel
extends SystemPanel
## 灵田播种：给指定地块挑一种种子
## 只列这片区域自己长的灵植（由调用方传 seeds），不出现别的地图的草药

## 跨区存档键（state_base + 本区第几块）；回调原样带回
var plot_index: int = 0
## 面板上写的「第 N 号地块」：本区第几块，从 1 开始
var plot_number: int = 1
var seeds: Array = []
## (plot_index: int, seed_id: String) -> void
var on_plant: Callable = Callable()


func _init() -> void:
	panel_title = "灵田 · 播种"
	panel_hint = "ESC 取消"

func facility_visual() -> Dictionary:
	return UIKit.facility_style("herb_garden")



func panel_size() -> Vector2:
	return Vector2(580.0, 380.0)


func _build_content() -> void:
	var outer := content.get_parent() as ScrollContainer
	if outer != null:
		outer.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var accent: Color = UIKit.facility_style("herb_garden").get("accent", UIKit.C_ACCENT)
	content.add_child(UIKit.note_card(
		"第 %d 号地块。只能种这片土地上长的草药，种下后 %s成熟，可收 2 份。"
		% [plot_number, FarmPlot.grow_text(FarmPlot.GROW_SECONDS)], accent))
	content.add_child(UIKit.section("选种", accent))

	if seeds.is_empty():
		content.add_child(UIKit.readable_note("这片土地暂时没有可种的灵植。"))
		return

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	content.add_child(grid)
	for mid in sorted_seed_ids(seeds):
		grid.add_child(_seed_card(String(mid)))


## 种子目录：品质从高到低（稀有度映射到品阶序列）；同品质按名字排，顺序稳定
static func sorted_seed_ids(ids: Array) -> Array:
	var out := ids.duplicate()
	out.sort_custom(func(a, b):
		var qa := _seed_grade(String(a))
		var qb := _seed_grade(String(b))
		if qa != qb:
			return qa > qb
		return ItemDB.get_material_name(String(a)) < ItemDB.get_material_name(String(b))
	)
	return out


static func _seed_grade(mid: String) -> int:
	return ItemDB.grade_index(String(ItemDB.RARITY_GRADE.get(ItemDB.material_rarity(mid), "")))


func _seed_card(mid: String) -> Control:
	var def := ItemDB.get_material(mid)
	var realm := String(def.get("realm", ""))
	var display := String(def.get("name", mid))
	if realm != "":
		display += "（%s）" % realm

	var accent: Color = UIKit.facility_style("herb_garden").get("accent", UIKit.C_ACCENT)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		UIKit.accent_card_style(ItemDB.material_border_color(mid), 0.66, 0.30, 6))

	var box := UIKit.hbox(10)
	card.add_child(box)
	box.add_child(UIKit.icon_node(String(def.get("icon", "")), display, "material", Vector2(34, 34)))

	var info := UIKit.vbox(1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(info)
	info.add_child(UIKit.label(display, UIKit.F_BODY))
	info.add_child(UIKit.label("%s成熟 · 收 2 份" % FarmPlot.grow_text(FarmPlot.GROW_SECONDS), UIKit.F_SMALL, UIKit.C_TEXT_DIM))

	var btn := UIKit.primary_button("种下", Vector2(74, 32), accent)
	btn.pressed.connect(_choose.bind(mid))
	box.add_child(btn)
	return card


func _choose(mid: String) -> void:
	if on_plant.is_valid():
		on_plant.call(plot_index, mid)
	close()
