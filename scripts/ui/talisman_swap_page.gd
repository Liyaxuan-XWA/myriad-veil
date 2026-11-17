extends CanvasLayer
## 换符页（2026-11-10）：每层开始时免费把符囊里的符换进主槽。
##
## 只做一件事：点符囊里的一张 → 再点一个主槽 → 两张对调。
## ⚠ 打开时暂停整棵树（与三选一同一套）：否则换符时会被小怪打断。
## ⚠ 不写存档：换符是局内状态，退出试炼即还原。
##
## ⚠ 必须是 **CanvasLayer**，不能是裸 Control（2026-11-10 用户报「面板固定在地上」）：
##   实机里战斗场景是 Node2D + Camera2D，裸 Control 挂 `get_tree().root` 与世界同处
##   layer 0，会跟着相机平移；写死的 1280×720 遮罩在相机位移后也盖不住屏幕，
##   红色地面从四周露出来。SystemPanel / ConfirmDialog / tutorial_overlay 全都是
##   CanvasLayer + 高 layer + PROCESS_MODE_ALWAYS，这里是同一套约定。
##   ⚠ 工具截图（`shot_run_talisman.gd` ② 阶段）当时还没实例化战斗场景，树里没有
##     Camera2D，裸 Control 看起来也居中 —— 所以那张截图一直没暴露这个问题。

signal closed

## 与 SystemPanel(101) / ConfirmDialog(110) / 新手引导(120) 同一档位体系；
## 必须高于战斗 HUD 的 CanvasLayer(layer=8)。
const SWAP_LAYER := 105
const PANEL_W := 720.0
## 面板高度**按行数算**，不再写死：
## ⚠ 写死 430 时，符囊只有两张的层下面会空出 100px 左右（截图验证过，很空）；
##   而符囊集齐十张时又必须能撑高。这里按 max(主槽, 符囊) 行数插值再夹住。
const ROW_PITCH := 43.0
const H_BASE := 168.0

var _selected_bag := -1
var _main_box: VBoxContainer
var _bag_box: VBoxContainer
var _hint: Label
var _panel: PanelContainer


func _ready() -> void:
	# ⚠ 暂停后自己还得活着，否则「继续」和符卡按钮收不到输入、面板直接卡死。
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = SWAP_LAYER
	_build()


func open() -> void:
	get_tree().paused = true
	visible = true


func close() -> void:
	visible = false
	get_tree().paused = false
	closed.emit()
	queue_free()


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.01, 0.01, 0.02, 0.72)
	# CanvasLayer 直属 Control 的 anchor 基准是**视口**，PRESET_FULL_RECT 才真的铺满
	# （SystemPanel._build_shell / UIKit.dim_rect 同一写法）。
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var root := PanelContainer.new()
	_panel = root
	root.offset_left = (1280.0 - PANEL_W) * 0.5
	root.offset_right = root.offset_left + PANEL_W
	_fit_panel()
	root.add_theme_stylebox_override("panel", UIKit.accent_card_style(
		Color(0.72, 0.58, 0.34), 0.68, 0.40, 10))
	add_child(root)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	root.add_child(box)
	box.add_child(UIKit.label("换符 · 每层一次", UIKit.F_TITLE, UIKit.C_ACCENT))
	box.add_child(UIKit.label("点符囊里的一张，再点主槽，两张对调", 12, UIKit.C_TEXT_DIM))

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(cols)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(320.0, 0.0)
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)
	left.add_child(UIKit.label("主符（Q/E/R/T）", 12, UIKit.C_TEXT_DIM))
	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 6)
	left.add_child(_main_box)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(320.0, 0.0)
	right.add_theme_constant_override("separation", 6)
	cols.add_child(right)
	right.add_child(UIKit.label("符囊（只参与连携）", 12, UIKit.C_TEXT_DIM))
	_bag_box = VBoxContainer.new()
	_bag_box.add_theme_constant_override("separation", 6)
	right.add_child(_bag_box)

	_hint = UIKit.readable_label("", 11, UIKit.C_WARN)
	box.add_child(_hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UIKit.spacer())
	var done := UIKit.button("继续", Vector2(130.0, 34.0), "primary")
	done.pressed.connect(close)
	row.add_child(done)
	box.add_child(row)
	_refresh()


## 高度跟着行数走，并保持垂直居中
func _fit_panel() -> void:
	if _panel == null:
		return
	var rows := maxi(RogueRun.tal_main.size(), maxi(RogueRun.tal_bag.size(), 1))
	var h := clampf(H_BASE + float(rows) * ROW_PITCH, 340.0, 640.0)
	var top := (720.0 - h) * 0.5
	_panel.offset_top = top
	_panel.offset_bottom = top + h


## 一行符：元素色左竖条 + 32px 符图标 + 键位 + 名字 + 右侧元素名。
## ⚠ 之前这里是纯文字按钮，十个符长得一模一样 —— 换符时只能靠读字，实机很费劲。
func _make_row(key: String, base_id: String, highlight: bool) -> Button:
	var pal: Color = ArtDB.element_color(TalismanDB.element_of(base_id))
	var elem := TalismanDB.element_of(base_id)
	var elem_name := String(AttributeDB.ELEMENT_NAMES.get(elem, elem))
	# ⚠ 用 UIKit.button（ink_button）而不是裸 Button.new()：
	#   裸 Button 会丢掉全局笔触底纹与字号，实机里那一排字只有 9px，根本读不清。
	var head := "%s   " % key if key != "" else ""
	var btn := UIKit.button("  %s%s   ·  %s" % [head,
		TalismanDB.display_name(base_id), elem_name],
		Vector2(0.0, 40.0), "primary" if highlight else "default", pal)
	var icon_path := ArtDB.talisman_icon(base_id)
	if icon_path != "" and ResourceLoader.exists(icon_path):
		btn.icon = load(icon_path) as Texture2D
		btn.expand_icon = false
		# Button 的 icon 默认按原图（256px）画，必须限宽，否则一行撑成两行高
		btn.add_theme_constant_override("icon_max_width", 26)
	return btn


func _refresh() -> void:
	for c in _main_box.get_children():
		c.queue_free()
	for c in _bag_box.get_children():
		c.queue_free()
	var keys: Array[String] = ["Q", "E", "R", "T"]
	for i in RogueRun.tal_main.size():
		var base_id := String(RogueRun.tal_main[i])
		var btn := _make_row("%s" % [keys[i] if i < 4 else "·"], base_id, false)
		btn.pressed.connect(_on_main_pressed.bind(i))
		_main_box.add_child(btn)
	for i in RogueRun.tal_bag.size():
		var base_id := String(RogueRun.tal_bag[i])
		# ⚠ 未选中的行不要补占位符：之前写的是 "·"，实机每行开头挂一个孤立圆点，
		#   像排版出错（截图验证过）。选中态靠 ▶ + 高亮底色区分就够了。
		var btn := _make_row("▶" if _selected_bag == i else "", base_id,
			_selected_bag == i)
		btn.pressed.connect(_on_bag_pressed.bind(i))
		_bag_box.add_child(btn)
	if RogueRun.tal_bag.is_empty():
		_bag_box.add_child(UIKit.label("（空）局内用符方获得的符会进这里", 11, UIKit.C_TEXT_FAINT))
	_fit_panel()


func _on_bag_pressed(index: int) -> void:
	_selected_bag = -1 if _selected_bag == index else index
	_hint.text = "" if _selected_bag < 0 else "已选中，点左侧任意主槽对调"
	_refresh()


func _on_main_pressed(index: int) -> void:
	if _selected_bag < 0:
		_hint.text = "先在右侧点一张符囊里的符"
		return
	if RogueRun.talisman_swap(index, _selected_bag):
		_selected_bag = -1
		_hint.text = "已对调"
	_refresh()
