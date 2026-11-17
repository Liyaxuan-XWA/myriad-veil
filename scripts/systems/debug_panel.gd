extends CanvasLayer
## 调试面板：运行时修改 BOSS 数值，方便测试
## F1 开关显示，修改实时生效。UI 全部由代码构建，避免 tscn 层级依赖。

## ★ 发布开关：是否允许 F1 调出调试面板。
##   试玩版 / 正式版保持 false —— 面板**根本不构建**、F1 完全无响应，
##   玩家看不到任何调试痕迹（也少一层 UI 开销）。
##   自己调试有两种开法：① 把这里改成 true；② 代码不动，启动时加用户参数
##   `godot --path . -- --debug-panel`（推荐，发布前不用再改回来）。
const DEBUG_PANEL_ENABLED := false

var boss: Node = null

# 面板可见状态
var _visible := false

# 本次运行是否启用（常量开关 or 命令行参数）
var _enabled := false

# 数值字段定义：{ 标题, boss属性名, 最小值, 最大值, 步长 }
const FLOAT_FIELDS := [
	["最大血量 max_hp", "max_hp", 100.0, 5000.0, 50.0],
	["移动速度(一阶段) MOVE_SPEED_P1", "MOVE_SPEED_P1", 0.0, 500.0, 10.0],
	["移动速度(二阶段) MOVE_SPEED_P2", "MOVE_SPEED_P2", 0.0, 500.0, 10.0],
	["近战范围 MELEE_RANGE", "MELEE_RANGE", 20.0, 400.0, 10.0],
	["近战张角 MELEE_SWEEP_ANGLE", "MELEE_SWEEP_ANGLE", 20.0, 360.0, 10.0],
	["近战伤害 MELEE_DAMAGE", "MELEE_DAMAGE", 1.0, 200.0, 1.0],
	["投掷速度 PROJECTILE_SPEED", "PROJECTILE_SPEED", 50.0, 1500.0, 20.0],
	["投掷伤害 PROJECTILE_DAMAGE", "PROJECTILE_DAMAGE", 1.0, 200.0, 1.0],
	["元素速度 ELEMENTAL_SPEED", "ELEMENTAL_SPEED", 50.0, 1500.0, 20.0],
	["元素伤害 ELEMENTAL_DAMAGE", "ELEMENTAL_DAMAGE", 1.0, 200.0, 1.0],
	["近战距离阈值 MELEE_DISTANCE", "MELEE_DISTANCE", 30.0, 500.0, 10.0],
	["远程距离阈值 RANGED_DISTANCE", "RANGED_DISTANCE", 100.0, 1000.0, 20.0],
	["后撤概率 DASH_BACK_BASE_CHANCE", "DASH_BACK_BASE_CHANCE", 0.0, 1.0, 0.05],
	["后撤速度 DASH_BACK_SPEED", "DASH_BACK_SPEED", 100.0, 2000.0, 50.0],
	["突进概率 DASH_FORWARD_BASE_CHANCE", "DASH_FORWARD_BASE_CHANCE", 0.0, 1.0, 0.05],
	["突进速度 DASH_FORWARD_SPEED", "DASH_FORWARD_SPEED", 100.0, 2000.0, 50.0],
	["砸地范围 SMASH_RANGE", "SMASH_RANGE", 20.0, 500.0, 10.0],
	["砸地伤害 SMASH_DAMAGE", "SMASH_DAMAGE", 1.0, 200.0, 1.0],
]

var panel: PanelContainer
var field_container: VBoxContainer
var _spins: Array = []
var _labels: Array = []


func _ready() -> void:
	_enabled = DEBUG_PANEL_ENABLED or OS.get_cmdline_user_args().has("--debug-panel")
	if not _enabled:
		# 禁用时彻底不参与：不建 UI、不响应 F1，连节点本身都不可见
		visible = false
		set_process_unhandled_input(false)
		return
	_build_ui()
	panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F1:
			_toggle()


func _toggle() -> void:
	_visible = not _visible
	panel.visible = _visible


## 纯代码构建面板 UI
func _build_ui() -> void:
	# 根面板容器
	panel = PanelContainer.new()
	panel.offset_left = 8.0
	panel.offset_top = 8.0
	panel.offset_right = 340.0
	panel.offset_bottom = 700.0
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "BOSS 数值调试面板（F1 开关）"
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	# 恢复默认值按钮
	var reset_btn := Button.new()
	UIKit.attach_click_sfx(reset_btn)
	reset_btn.text = "恢复默认值"
	reset_btn.custom_minimum_size = Vector2(0, 32)
	reset_btn.pressed.connect(_on_reset_defaults)
	vbox.add_child(reset_btn)

	# 可滚动区域
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	field_container = VBoxContainer.new()
	field_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field_container.add_theme_constant_override("separation", 2)
	scroll.add_child(field_container)

	# 逐字段构建标签 + SpinBox
	for f in FLOAT_FIELDS:
		var label := Label.new()
		label.text = f[0]
		label.add_theme_font_size_override("font_size", 12)
		field_container.add_child(label)
		_labels.append(label)

		var spin := SpinBox.new()
		spin.min_value = f[2]
		spin.max_value = f[3]
		spin.step = f[4]
		spin.allow_greater = true
		spin.allow_lesser = true
		spin.custom_minimum_size = Vector2(0, 28)
		spin.value_changed.connect(_on_value_changed.bind(f[1]))
		field_container.add_child(spin)
		_spins.append(spin)


## 把 BOSS 数值同步到面板：优先应用 GameState 里已保存的覆盖值
func refresh() -> void:
	# ⚠ 面板被发布开关关掉时 UI 数组是空的，这里必须提前返回，
	#   否则 combat_arena 的 refresh() 调用会索引越界
	if not _enabled:
		return
	if not boss:
		return
	for i in range(FLOAT_FIELDS.size()):
		var prop_name: String = FLOAT_FIELDS[i][1]
		# 每个 BOSS 的字段不一样（刀客没有元素/砸地，原型没有挥刀/箭矢）。
		# 没有的字段整行隐藏 —— 否则 boss.get() 返回 null，
		# 传给需要 float 的函数会直接报类型转换错误。
		var has := _boss_has_property(prop_name)
		_labels[i].visible = has
		_spins[i].visible = has
		if not has:
			continue
		# 首次捕获脚本默认值（用于"恢复默认"）
		GameState.capture_boss_default(prop_name, boss.get(prop_name))
		# 若有用户覆盖值，则应用回 BOSS（跨 R 重开保留）
		if GameState.has_boss_override(prop_name):
			boss.set(prop_name, GameState.get_boss_override(prop_name))
		# 同步面板显示为 BOSS 当前值
		_spins[i].set_value_no_signal(boss.get(prop_name))

	# 若覆盖了 max_hp，同步把当前血量设为满血（重开后满血重打）
	if GameState.has_boss_override("max_hp"):
		boss.current_hp = boss.max_hp


## BOSS 是否拥有该属性
func _boss_has_property(prop_name: String) -> bool:
	for p in boss.get_property_list():
		if String(p.get("name", "")) == prop_name:
			return true
	return false


func _on_value_changed(value: float, prop_name: String) -> void:
	if boss:
		boss.set(prop_name, value)
		# 持久化用户修改，跨 R 重开保留
		GameState.set_boss_override(prop_name, value)


func _on_reset_defaults() -> void:
	# 清空覆盖值，把 BOSS 恢复到脚本默认值
	GameState.clear_boss_overrides()
	if boss:
		for i in range(FLOAT_FIELDS.size()):
			var prop_name: String = FLOAT_FIELDS[i][1]
			var def = GameState.get_boss_default(prop_name)
			if def != null:
				boss.set(prop_name, def)
		refresh()
