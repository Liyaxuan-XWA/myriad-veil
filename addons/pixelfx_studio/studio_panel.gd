@tool
extends Control
## 特效工坊面板（pixelfx，2026-11-04）。
##
## 三步走：**选形态 → 选颜色 → 调大小**，其余收进「高级」折叠。
## 面板只读 assets/fx/pixelfx/catalog.json 与已烘焙的表，不碰 JS；
## 烘焙是同步调 node 跑 tools/pixelfx/bake.mjs（单个特效 1~3 秒）。

const ELEMENT_TO_RAMP := {
	"金": "metal", "木": "wood", "水": "water", "火": "fire",
	"土": "earth", "风": "smoke", "雷": "volt",
	"冰": "ice", "毒": "poison", "圣": "holy", "暗": "shadow", "血": "blood",
}
## 特效库自己的 21 个分类 → 中文
const CAT_CN := {
	"arcane": "法术", "critters": "灵兽", "explosions": "爆炸", "fire": "火",
	"holy": "圣光", "ice": "冰", "impacts": "受击", "lightning": "雷",
	"melee": "近战", "moves": "连招", "nature": "自然", "pickups": "拾取",
	"projectiles": "投射物", "scifi": "科幻", "shadow": "暗影", "spawn": "生灭",
	"status": "状态", "transitions": "转场", "ui": "界面", "water": "水",
	"weather": "天候",
}
## 五行属性 → 该找哪些关键词（catalog 的 tags / id / desc 里出现即计分）
const ELEMENT_TERMS := {
	"metal": ["slash", "sword", "melee", "cut", "blade", "pierce", "thrust", "spark", "metal"],
	"wood": ["leaf", "nature", "wood", "vine", "bloom", "growth", "poison", "spore"],
	"water": ["water", "wave", "bubble", "ripple", "splash", "flow", "heal", "frost"],
	"fire": ["fire", "flame", "ember", "lava", "burn", "blaze", "explosion", "meteor"],
	"earth": ["earth", "rock", "stone", "dust", "stomp", "quake", "boulder", "spike"],
	"wind": ["wind", "gust", "tornado", "air", "dash", "slip", "leaf", "swirl"],
	"thunder": ["lightning", "electric", "volt", "spark", "strike", "chain", "plasma"],
}
const ELEMENT_CN := {"metal": "金", "wood": "木", "water": "水", "fire": "火",
	"earth": "土", "wind": "风", "thunder": "雷"}
## 现有演出的 motif → 该找哪些关键词（覆盖 content_map 里出现的全部 motif）
const MOTIF_TERMS := {
	"slash": ["slash", "sword", "melee", "cut", "cleave"],
	"thrust": ["thrust", "spear", "lance", "pierce"],
	"pierce": ["thrust", "lance", "spear", "pierce"],
	"claw": ["claw", "slash", "swipe", "melee", "bite"],
	"spin": ["spin", "slash", "whirl", "tornado"],
	"dash": ["dash", "slip", "streak", "after-image", "wind"],
	"heaven": ["slash", "meteor", "beam", "light", "impact"],
	"peak": ["slash", "sword", "meteor", "impact"],
	"stomp": ["stomp", "quake", "dust", "shockwave", "earth", "spike"],
	"field": ["field", "aura", "zone", "cloud", "mist", "nova"],
	"cloud": ["cloud", "mist", "smoke", "vapor", "aura"],
	"qi": ["qi", "cloud", "aura", "nova", "swirl", "ring"],
	"qi_cloud": ["cloud", "mist", "smoke", "aura", "nova", "swirl"],
	"volley": ["missile", "projectile", "arrow", "bolt", "flurry"],
	"orb": ["orb", "ball", "plasma", "sphere", "core"],
	"ward": ["shield", "barrier", "ward", "halo", "blessing", "force field"],
	"rune": ["sigil", "circle", "rune", "glyph", "magic circle"],
	"box": ["chest", "pickup", "loot", "poof", "spawn"],
	"cord": ["chain", "link", "whip", "tether"],
	"pillars": ["pillar", "spike", "beam", "earth", "summon"],
	"summon": ["portal", "spawn", "summon", "gate", "magic circle"],
	"thunder": ["lightning", "volt", "electric", "strike", "chain"],
	"sun": ["fire", "flare", "light", "burn", "corona", "meteor"],
	"calamity": ["tornado", "explosion", "fire", "storm", "disaster"],
	"mirror": ["ice", "crystal", "shard", "reflect", "glitch"],
	"shadow": ["shadow", "dark", "hex", "curse", "eclipse", "void"],
	"fold": ["paper", "cut", "wipe", "glitch", "slash"],
}
const STAGE_BG := Color(0.10, 0.10, 0.13)
const SWATCH_H := 12.0

## 宿主插件（EditorPlugin）。这里刻意不加类型标注：
## 探针/截图脚本用鸭子类型的替身对象就能把面板跑起来看版式。
var plugin

var _effects: Array = []
var _rows: Array = []
var _current: Dictionary = {}
var _ramps: Dictionary = {}

var _variant := "default"
var _chosen_ramp := ""
var _custom_hex := ""
var _scale := 1.0
var _flip := false
var _additive := false
var _speed := 1.0
var _seed_touched := false
var _fps_touched := false

var _frames: Array = []
var _times: PackedFloat64Array = PackedFloat64Array()
var _pivot := Vector2.ZERO
var _total := 0.0
var _index := -1
var _elapsed := 0.0
var _playing := false
var _busy := false

var _stage: Control
var _stage_bg: ColorRect
var _ground_line: ColorRect
var _pivot_mark: ColorRect
var _sprite: Sprite2D
var _list: ItemList
var _cat: OptionButton
var _search: LineEdit
var _note: Label
var _crumb: Label
var _boss_pick: OptionButton
var _mode_skill_btn: Button
var _mode_fx_btn: Button
## 0 = 按 BOSS/招式，1 = 按特效分类
var _mode := 0
## 左栏当前装的是什么："skill" / "effect"
var _list_kind := "skill"
var _groups: Array = []
var _skill_rows: Array = []
var _picked_skill: Dictionary = {}
var _timeline: HSlider
var _play_btn: Button
var _status: Label
var _info: Label
var _swatch_row: HBoxContainer
var _ramp_grid: GridContainer
var _custom_edit: LineEdit
var _scale_val: Label
var _seed_spin: SpinBox
var _fps_spin: SpinBox
var _reach_spin: SpinBox
var _reach_row: HBoxContainer
var _actor_chk: CheckBox
var _bake_btn: Button
var _preview_btn: Button
var _bind_btn: Button
var _unbind_btn: Button
var _back_btn: Button
var _add_mat: CanvasItemMaterial


func _ready() -> void:
	custom_minimum_size = Vector2(0, 430)
	_build_ui()
	reload_catalog()


# ===================== 界面 =====================

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# ---- 顶部：库状态 / 搜索 / 刷新 ----
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	top.add_child(_label("pixelfx", 13, Color(0.78, 0.66, 0.42)))
	_status = _label("初始化…", 12, Color(0.44, 0.52, 0.40))
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_status)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索特效：中文名 / 原名 / 描述 / 标签都能搜"
	_search.custom_minimum_size = Vector2(320, 0)
	_search.text_changed.connect(func(_t: String) -> void: _refresh_left())
	top.add_child(_search)
	var refresh := Button.new()
	refresh.text = "重读目录表"
	refresh.tooltip_text = "库更新后先跑 node tools/pixelfx/dump_meta.mjs，再按这个刷新"
	refresh.pressed.connect(reload_catalog)
	top.add_child(refresh)

	# ---- 主体三栏 ----
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(302, 0)
	body.add_child(left)
	# 两种浏览方式：按项目的 BOSS → 招式（默认，看得懂的那条），或按特效库自己的分类
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 4)
	left.add_child(modes)
	_mode_skill_btn = Button.new()
	_mode_skill_btn.text = "按 BOSS / 招式"
	_mode_skill_btn.tooltip_text = "先选 BOSS，再选它的招式，然后给你这一招的候选特效"
	_mode_skill_btn.toggle_mode = true
	_mode_skill_btn.button_pressed = true
	_mode_skill_btn.pressed.connect(func() -> void: _set_mode(0))
	modes.add_child(_mode_skill_btn)
	_mode_fx_btn = Button.new()
	_mode_fx_btn.text = "按特效分类"
	_mode_fx_btn.tooltip_text = "直接翻 pixelfx 自己的 21 个特效大类"
	_mode_fx_btn.toggle_mode = true
	_mode_fx_btn.pressed.connect(func() -> void: _set_mode(1))
	modes.add_child(_mode_fx_btn)
	_boss_pick = OptionButton.new()
	_boss_pick.item_selected.connect(func(_i: int) -> void: _on_boss_selected())
	left.add_child(_boss_pick)
	_cat = OptionButton.new()
	_cat.item_selected.connect(func(_i: int) -> void: _refresh_left())
	_cat.visible = false
	left.add_child(_cat)
	var crumb_row := HBoxContainer.new()
	crumb_row.add_theme_constant_override("separation", 4)
	left.add_child(crumb_row)
	_crumb = _label("先选一只 BOSS", 11, Color(0.66, 0.58, 0.40))
	_crumb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_crumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crumb_row.add_child(_crumb)
	_back_btn = Button.new()
	_back_btn.text = "← 招式"
	_back_btn.visible = false
	_back_btn.tooltip_text = "回到这一只 BOSS 的招式列表"
	_back_btn.pressed.connect(_back_to_skills)
	crumb_row.add_child(_back_btn)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.allow_reselect = true
	left.add_child(_list)
	_list.item_selected.connect(_on_pick)
	_note = _label("", 10, Color(0.50, 0.45, 0.34))
	_note.custom_minimum_size = Vector2(300, 0)
	left.add_child(_note)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(mid)
	_stage = Control.new()
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.clip_contents = true
	mid.add_child(_stage)
	_stage_bg = ColorRect.new()
	_stage_bg.color = STAGE_BG
	_stage_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_stage_bg)
	_ground_line = ColorRect.new()
	_ground_line.color = Color(0.34, 0.30, 0.22, 0.55)
	_ground_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_ground_line)
	_pivot_mark = ColorRect.new()
	_pivot_mark.color = Color(0.90, 0.45, 0.30, 0.75)
	_pivot_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_pivot_mark)
	_sprite = Sprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_stage.add_child(_sprite)

	var ctrl := HBoxContainer.new()
	ctrl.add_theme_constant_override("separation", 8)
	mid.add_child(ctrl)
	_play_btn = Button.new()
	_play_btn.text = "▶ 播放"
	_play_btn.toggle_mode = true
	_play_btn.button_pressed = true
	_play_btn.toggled.connect(_on_play_toggled)
	ctrl.add_child(_play_btn)
	var step_btn := Button.new()
	step_btn.text = "⏭ 单帧"
	step_btn.pressed.connect(_step_frame)
	ctrl.add_child(step_btn)
	_timeline = HSlider.new()
	_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline.step = 1
	_timeline.value_changed.connect(func(v: float) -> void:
		if not _playing:
			_elapsed = _times[clampi(int(v), 0, maxi(0, _times.size() - 1))]
			_show_index(int(v)))
	ctrl.add_child(_timeline)
	ctrl.add_child(_label("速度", 11, Color(0.60, 0.54, 0.40)))
	var speed := HSlider.new()
	speed.min_value = 0.15
	speed.max_value = 2.0
	speed.step = 0.05
	speed.value = 1.0
	speed.custom_minimum_size = Vector2(84, 0)
	speed.value_changed.connect(func(v: float) -> void: _speed = v)
	ctrl.add_child(speed)
	_info = _label("左边选一个特效", 11, Color(0.55, 0.50, 0.38))
	mid.add_child(_info)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(316, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	scroll.add_child(right)

	right.add_child(_label("① 颜色（改色要重烘，1~3 秒）", 12, Color(0.72, 0.62, 0.42)))
	_swatch_row = HBoxContainer.new()
	_swatch_row.custom_minimum_size = Vector2(0, SWATCH_H)
	right.add_child(_swatch_row)
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 3)
	right.add_child(quick)
	for key in ELEMENT_TO_RAMP.keys():
		var b := Button.new()
		b.text = String(key)
		b.tooltip_text = "用 %s 色带重烘" % String(ELEMENT_TO_RAMP[key])
		b.pressed.connect(_pick_ramp.bind(String(ELEMENT_TO_RAMP[key])))
		quick.add_child(b)
	_ramp_grid = GridContainer.new()
	_ramp_grid.columns = 2
	_ramp_grid.add_theme_constant_override("h_separation", 4)
	_ramp_grid.add_theme_constant_override("v_separation", 2)
	right.add_child(_ramp_grid)
	var custom_row := HBoxContainer.new()
	right.add_child(custom_row)
	_custom_edit = LineEdit.new()
	_custom_edit.placeholder_text = "自定义：#102,#215,#43a,#8cf,#cff,#fff"
	_custom_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_row.add_child(_custom_edit)
	var apply_custom := Button.new()
	apply_custom.text = "用这套"
	apply_custom.pressed.connect(_apply_custom_ramp)
	custom_row.add_child(apply_custom)

	right.add_child(_label("② 大小 / 朝向", 12, Color(0.72, 0.62, 0.42)))
	var scale_row := HBoxContainer.new()
	right.add_child(scale_row)
	var scale_slider := HSlider.new()
	scale_slider.min_value = 0.25
	scale_slider.max_value = 4.0
	scale_slider.step = 0.05
	scale_slider.value = 1.0
	scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_slider.value_changed.connect(_on_scale)
	scale_row.add_child(scale_slider)
	_scale_val = _label("×1.00", 11, Color(0.62, 0.56, 0.42))
	scale_row.add_child(_scale_val)
	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 4)
	right.add_child(toggles)
	var flip_btn := Button.new()
	flip_btn.text = "翻转"
	flip_btn.toggle_mode = true
	flip_btn.toggled.connect(func(on: bool) -> void:
		_flip = on
		_sprite.flip_h = on)
	toggles.add_child(flip_btn)
	var add_btn := Button.new()
	add_btn.text = "加法混合"
	add_btn.tooltip_text = "叠在画面上加亮（发光类常用）；关掉就是普通叠加"
	add_btn.toggle_mode = true
	add_btn.toggled.connect(func(on: bool) -> void:
		_additive = on
		# 不借 SkillFx 的静态材质：那是非 @tool 脚本，编辑器里调用同一类风险
		_sprite.material = _add_material() if on else null)
	toggles.add_child(add_btn)
	var fit_btn := Button.new()
	fit_btn.text = "半径 200px"
	fit_btn.tooltip_text = "把特效半宽缩到 200px，方便和判定圈对齐"
	fit_btn.pressed.connect(_fit_to_radius)
	toggles.add_child(fit_btn)

	var adv := VBoxContainer.new()
	adv.add_theme_constant_override("separation", 4)
	adv.visible = false
	var adv_toggle := Button.new()
	adv_toggle.text = "▸ 高级（种子 / 帧率 / 特效自己的旋钮 / 含角色）"
	adv_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	adv_toggle.toggle_mode = true
	adv_toggle.toggled.connect(func(on: bool) -> void:
		adv.visible = on
		adv_toggle.text = ("▾ " if on else "▸ ") + "高级（种子 / 帧率 / 特效自己的旋钮 / 含角色）")
	right.add_child(adv_toggle)
	right.add_child(adv)
	var seed_row := HBoxContainer.new()
	adv.add_child(seed_row)
	seed_row.add_child(_label("随机种子", 11, Color(0.60, 0.54, 0.40)))
	_seed_spin = SpinBox.new()
	_seed_spin.min_value = 0
	_seed_spin.max_value = 99999
	_seed_spin.value = 4
	_seed_spin.custom_minimum_size = Vector2(104, 0)
	_seed_spin.value_changed.connect(func(_v: float) -> void: _seed_touched = true)
	seed_row.add_child(_seed_spin)
	seed_row.add_child(_label("改了会重排粒子", 10, Color(0.50, 0.46, 0.36)))
	var fps_row := HBoxContainer.new()
	adv.add_child(fps_row)
	fps_row.add_child(_label("帧率", 11, Color(0.60, 0.54, 0.40)))
	_fps_spin = SpinBox.new()
	_fps_spin.min_value = 6
	_fps_spin.max_value = 60
	_fps_spin.step = 1
	_fps_spin.value = 30
	_fps_spin.custom_minimum_size = Vector2(104, 0)
	_fps_spin.value_changed.connect(func(_v: float) -> void: _fps_touched = true)
	fps_row.add_child(_fps_spin)
	fps_row.add_child(_label("默认用特效自带", 10, Color(0.50, 0.46, 0.36)))
	_reach_row = HBoxContainer.new()
	adv.add_child(_reach_row)
	_reach_row.add_child(_label("范围 reach", 11, Color(0.60, 0.54, 0.40)))
	_reach_spin = SpinBox.new()
	_reach_spin.min_value = 0
	_reach_spin.max_value = 999
	_reach_spin.value = 0
	_reach_spin.custom_minimum_size = Vector2(104, 0)
	_reach_row.add_child(_reach_spin)
	_reach_row.add_child(_label("只有支持该旋钮的特效出现", 10, Color(0.50, 0.46, 0.36)))
	_actor_chk = CheckBox.new()
	_actor_chk.text = "烘焙时带上替身小人（默认不带）"
	adv.add_child(_actor_chk)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	root.add_child(bottom)
	# 先「只烘来看」：产物落 user:// 预览区，不进 assets/、不导入、不会被提交或打包
	_preview_btn = Button.new()
	_preview_btn.text = "烘焙预览（不进游戏）"
	_preview_btn.tooltip_text = "烘到 user://pixelfx_preview，面板里实时播；项目素材完全不受影响"
	_preview_btn.pressed.connect(func() -> void: _do_bake(false))
	bottom.add_child(_preview_btn)
	_bake_btn = Button.new()
	_bake_btn.text = "烘焙并导入"
	_bake_btn.tooltip_text = "满意后再点：产物落 assets/fx/pixelfx/，成为正式素材，才能被绑定和打包"
	_bake_btn.pressed.connect(func() -> void: _do_bake(true))
	bottom.add_child(_bake_btn)
	var clear_btn := Button.new()
	clear_btn.text = "清空预览缓存"
	clear_btn.tooltip_text = "只删 user://pixelfx_preview，不碰 assets/fx/pixelfx 里的正式素材"
	clear_btn.pressed.connect(_clear_preview)
	bottom.add_child(clear_btn)
	var attach_btn := Button.new()
	attach_btn.text = "挂到选中节点"
	attach_btn.tooltip_text = "给场景里选中的 Node2D 加一个 PixelFxFx 子节点（可撤销，之后 Ctrl+S 保存场景）"
	attach_btn.pressed.connect(_attach_to_selection)
	bottom.add_child(attach_btn)
	_bind_btn = Button.new()
	_bind_btn.text = "绑定到这一招"
	_bind_btn.tooltip_text = "把「当前特效 + 当前变体 + 大小」写进 assets/fx/pixelfx/bindings.json"
	_bind_btn.disabled = true
	_bind_btn.pressed.connect(_bind_to_skill)
	bottom.add_child(_bind_btn)
	_unbind_btn = Button.new()
	_unbind_btn.text = "解除绑定"
	_unbind_btn.tooltip_text = "从绑定表里删掉这一招，立刻回到原来的云烟演出"
	_unbind_btn.disabled = true
	_unbind_btn.pressed.connect(_unbind_skill)
	bottom.add_child(_unbind_btn)
	var open_btn := Button.new()
	open_btn.text = "打开输出目录"
	open_btn.pressed.connect(func() -> void:
		OS.shell_open(ProjectSettings.globalize_path(plugin.get_output_dir())))
	bottom.add_child(open_btn)


## 面板自己的加法混合材质（不借 SkillFx 的静态材质）
func _add_material() -> CanvasItemMaterial:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


# ===================== 数据 =====================

func refresh_settings() -> void:
	reload_catalog()


func reload_catalog() -> void:
	PixelFxLib.invalidate()
	_effects = PixelFxLib.effects()
	_ramps = PixelFxLib.palettes()
	if _effects.is_empty():
		_set_status("目录表是空的：先跑 node tools/pixelfx/dump_meta.mjs", Color(0.62, 0.22, 0.16))
		return
	_cat.clear()
	_cat.add_item("全部分类")
	_cat.set_item_metadata(0, "")
	var cats := PixelFxLib.categories()
	for i in cats.size():
		var key := String(cats[i])
		_cat.add_item("%s（%s）" % [String(CAT_CN.get(key, key)), key])
		_cat.set_item_metadata(i + 1, key)
	_build_ramp_buttons()
	_fill_bosses()
	_refresh_left()
	var lib: String = plugin.get_library_path()
	var lib_ok := DirAccess.open(lib) != null
	_set_status("%d 个特效　库 %s" % [_effects.size(),
		("已就位：" + lib) if lib_ok else ("缺失：" + lib)],
		Color(0.44, 0.52, 0.40) if lib_ok else Color(0.62, 0.40, 0.16))


func _build_ramp_buttons() -> void:
	for c in _ramp_grid.get_children():
		_ramp_grid.remove_child(c)
		c.queue_free()
	_ramp_grid.add_child(_ramp_button("", "特效自带色带"))
	var names: Array = _ramps.keys()
	names.sort()
	for n in names:
		_ramp_grid.add_child(_ramp_button(String(n), String(n)))


func _ramp_button(key: String, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.tooltip_text = "用这条色带重烘"
	var list: Array = [] if key == "" else (_ramps.get(key, []) as Array)
	if not list.is_empty():
		b.icon = _ramp_icon(list)
	b.pressed.connect(_pick_ramp.bind(key))
	return b


## 把色带画成一条小色块，一眼比出冷暖
func _ramp_icon(list: Array) -> ImageTexture:
	var n := maxi(1, list.size())
	var img := Image.create(n * 8, int(SWATCH_H), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in list.size():
		var c := Color.from_string(String(list[i]), Color.MAGENTA)
		for x in range(i * 8, i * 8 + 8):
			for y in int(SWATCH_H):
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _pick_ramp(key: String) -> void:
	_chosen_ramp = key
	_custom_hex = ""
	_variant = "default" if key == "" else key
	_paint_swatch(_ramps.get(key, []) as Array)
	_set_status("色带 %s → 变体 %s（点「烘焙并导入」生效）" % [
		"自带" if key == "" else key, _variant], Color(0.50, 0.52, 0.62))


func _apply_custom_ramp() -> void:
	var parts := _custom_edit.text.strip_edges().split(",")
	var clean: Array = []
	for p in parts:
		var s := String(p).strip_edges()
		if s == "":
			continue
		if not s.begins_with("#"):
			s = "#" + s
		clean.append(s)
	if clean.size() < 2:
		_set_status("自定义色带至少要 2 个颜色，用逗号分隔", Color(0.62, 0.22, 0.16))
		return
	_custom_hex = ",".join(clean)
	_chosen_ramp = "custom"
	_variant = "custom_%s" % _custom_hex.md5_text().substr(0, 6)
	_paint_swatch(clean)
	_set_status("自定义 %d 级色带 → 变体 %s" % [clean.size(), _variant], Color(0.50, 0.52, 0.62))


func _paint_swatch(list: Array) -> void:
	for c in _swatch_row.get_children():
		_swatch_row.remove_child(c)
		c.queue_free()
	for raw in list:
		var rect := ColorRect.new()
		rect.color = Color.from_string(String(raw), Color.MAGENTA)
		rect.custom_minimum_size = Vector2(0, SWATCH_H)
		rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_swatch_row.add_child(rect)


## 中文名优先，没登记就退回英文原名
func _fx_display(e: Dictionary) -> String:
	var cn := PixelFxLib.effect_cn(String(e.get("id", "")))
	var nm := String(cn.get("name", ""))
	return nm if nm != "" else String(e.get("name", e.get("id", "?")))


func _fx_tooltip(e: Dictionary) -> String:
	var id := String(e.get("id", ""))
	var cn := PixelFxLib.effect_cn(id)
	var out: Array[String] = []
	var cn_desc := String(cn.get("desc", ""))
	if cn_desc != "":
		out.append(cn_desc)
	out.append("原名：%s　%s" % [String(e.get("name", "")), id])
	var en := String(e.get("desc", ""))
	if en != "":
		out.append(en)
	var matched: Array = e.get("_matched", [])
	if not matched.is_empty():
		out.append("命中关键词：%s" % ", ".join(matched))
	return "
".join(out)


func _refresh_left() -> void:
	if _list == null:
		return
	_list.clear()
	_rows.clear()
	if _mode == 1:
		_list_kind = "effect"
		_fill_effect_list()
		return
	if _picked_skill.is_empty():
		_list_kind = "skill"
		_fill_skill_list()
	else:
		_list_kind = "effect"
		_fill_candidate_list()


## 第一级 = BOSS（顺序沿用功法库那套权威塔层序，由 tools/dump_content_map 导出）
func _fill_bosses() -> void:
	_groups = PixelFxLib.content_bosses()
	_boss_pick.clear()
	for i in _groups.size():
		var g: Dictionary = _groups[i]
		_boss_pick.add_item(String(g.get("boss_name", g.get("group_name", "?"))))
	_boss_pick.selected = 0 if not _groups.is_empty() else -1


func _set_mode(m: int) -> void:
	_mode = m
	_mode_skill_btn.button_pressed = m == 0
	_mode_fx_btn.button_pressed = m == 1
	_boss_pick.visible = m == 0
	_cat.visible = m == 1
	_back_btn.visible = false
	_picked_skill = {}
	_refresh_left()
	_update_bind_buttons()


func _on_boss_selected() -> void:
	_picked_skill = {}
	_back_btn.visible = false
	_refresh_left()
	_update_bind_buttons()


func _skill_terms(skill: Dictionary) -> Array[String]:
	## 这一招该找什么形状的特效：五行属性 + 当前演出的 motif
	var out: Array[String] = []
	var el := String(skill.get("damage_element", ""))
	if ELEMENT_TERMS.has(el):
		for t in ELEMENT_TERMS[el]:
			out.append(String(t))
	var motif := String(skill.get("motif", ""))
	if MOTIF_TERMS.has(motif):
		for t in MOTIF_TERMS[motif]:
			if t not in out:
				out.append(String(t))
	return out


func _skill_label_of(skill: Dictionary) -> String:
	var el := String(skill.get("damage_element", ""))
	var el_cn := String(ELEMENT_CN.get(el, el)) if el != "" and el != "none" else "无属性"
	var motif := String(skill.get("motif", ""))
	return "%s
当前演出：%s　元素：%s　形态：%s
%s" % [
		String(skill.get("skill_id", "")),
		motif if motif != "" else "（没有 SKILL_FX 条目）",
		el_cn, String(skill.get("form_name", "")), String(skill.get("desc", ""))]


func _fill_skill_list() -> void:
	var gi := _boss_pick.selected
	_note.text = "点一招 → 下面列出给它推荐的像素特效（● 已经绑过）"
	if gi < 0 or gi >= _groups.size():
		_crumb.text = "没有可选的 BOSS：先跑 node… 见下方提示" if false else 			"内容树是空的：跑 godot --headless --path . tools/dump_content_map.tscn"
		return
	var g: Dictionary = _groups[gi]
	_skill_rows = g.get("skills", [])
	_crumb.text = "%s　%d 门招式" % [String(g.get("boss_name", "")), _skill_rows.size()]
	for raw in _skill_rows:
		var d: Dictionary = raw
		var bound := not PixelFxLib.binding_for(String(d.get("skill_id", ""))).is_empty()
		_rows.append(d)
		_list.add_item("%s %s%s" % ["●" if bound else "·", String(d.get("skill_name", "?")),
			"（被动）" if bool(d.get("passive", false)) else ""])
		_list.set_item_tooltip(_rows.size() - 1, _skill_label_of(d))


## 给这一招排序候选：命中关键词越多越靠前，一次性特效优先
func _candidates_for(skill: Dictionary) -> Array:
	var terms := _skill_terms(skill)
	var scored: Array = []
	for raw in _effects:
		var e: Dictionary = raw
		var hay := " ".join([String(e.get("id", "")), String(e.get("name", "")),
			String(e.get("category", "")), String(e.get("desc", ""))]
			+ (e.get("tags", []) as Array)).to_lower()
		var score := 0
		var matched: Array[String] = []
		for t in terms:
			if hay.contains(String(t)):
				score += 1
				matched.append(String(t))
		if terms.is_empty():
			score = 1
		elif score <= 0:
			continue
		var row: Dictionary = e.duplicate(true)
		row["_score"] = score
		row["_matched"] = matched
		scored.append(row)
	scored.sort_custom(func(a, b):
		if int(a.get("_score", 0)) != int(b.get("_score", 0)):
			return int(a.get("_score", 0)) > int(b.get("_score", 0))
		if bool(a.get("loop", false)) != bool(b.get("loop", false)):
			return not bool(a.get("loop", false))
		return float(a.get("duration", 0.0)) < float(b.get("duration", 0.0)))
	return scored


func _fill_candidate_list() -> void:
	var boss_name := ""
	var gi := _boss_pick.selected
	if gi >= 0 and gi < _groups.size():
		boss_name = String((_groups[gi] as Dictionary).get("group_name", ""))
	_rows = _candidates_for(_picked_skill)
	_crumb.text = "%s › %s › 候选 %d 个" % [
		boss_name, String(_picked_skill.get("skill_name", "?")), _rows.size()]
	_note.text = "选中即可预览 → 调颜色/大小 → 先「烘焙预览」看效果，满意再「烘焙并导入」+「绑定到这一招」"
	for e in _rows:
		var d: Dictionary = e
		var baked := not PixelFxLib.baked_variants(String(d.get("id", ""))).is_empty()
		var cat_cn := String(CAT_CN.get(String(d.get("category", "")), String(d.get("category", ""))))
		_list.add_item("%s %s（%s）· %s %ss" % [
			"●" if baked else ("◐" if PixelFxLib.is_preview_baked(String(d.get("id", ""))) else "○"),
			_fx_display(d), cat_cn,
			"循环" if bool(d.get("loop", false)) else "一次", str(d.get("duration", 0.0))])
		_list.set_item_tooltip(_rows.size() - 1, _fx_tooltip(d))


func _fill_effect_list() -> void:
	_crumb.text = "特效库全 %d 个：%s" % [_effects.size(),
		String(plugin.get_library_path()) if plugin != null else ""]
	_note.text = "● 已导入游戏　◐ 只有预览版　○ 还没烘（预览随便点，导入才会落 assets/）"
	var want := _search.text.strip_edges().to_lower() if _search != null else ""
	var cat := ""
	if _cat != null and _cat.selected > 0:
		cat = String(_cat.get_item_metadata(_cat.selected))
	for raw in _effects:
		var e: Dictionary = raw
		if cat != "" and String(e.get("category", "")) != cat:
			continue
		var cn := PixelFxLib.effect_cn(String(e.get("id", "")))
		if want != "":
			var hay := " ".join([String(e.get("id", "")), String(e.get("name", "")),
				String(e.get("desc", "")), String(cn.get("name", "")), String(cn.get("desc", ""))]
				+ (e.get("tags", []) as Array)).to_lower()
			if not hay.contains(want):
				continue
		_rows.append(e)
		var baked := not PixelFxLib.baked_variants(String(e.get("id", ""))).is_empty()
		var sz: Array = e.get("size", [0, 0])
		_list.add_item("%s %s · %s %ss · %d×%d" % [
			"●" if baked else ("◐" if PixelFxLib.is_preview_baked(String(e.get("id", ""))) else "○"),
			_fx_display(e),
			"循环" if bool(e.get("loop", false)) else "一次",
			str(e.get("duration", 0.0)), int(sz[0]), int(sz[1])])
		_list.set_item_tooltip(_rows.size() - 1, _fx_tooltip(e))


func _on_pick(i: int) -> void:
	if i < 0 or i >= _rows.size():
		return
	if _list_kind == "skill":
		_picked_skill = _rows[i]
		_back_btn.visible = true
		_refresh_left()
		_update_bind_buttons()
		_set_status("已选招式「%s」：从候选里挑一个特效" % String(_picked_skill.get("skill_name", "")),
			Color(0.50, 0.52, 0.62))
		return
	_pick_effect(_rows[i])


func _back_to_skills() -> void:
	_picked_skill = {}
	_back_btn.visible = false
	_refresh_left()
	_update_bind_buttons()


## 绑定表读写：bindings.json 是面板唯一能改的项目数据，绝不动 art_db.gd 源码
func _update_bind_buttons() -> void:
	var can := _mode == 0 and not _picked_skill.is_empty() and not _current.is_empty()
	if _bind_btn != null:
		_bind_btn.disabled = not can
	if _unbind_btn != null:
		_unbind_btn.disabled = _picked_skill.is_empty()


func _bind_to_skill() -> void:
	if _picked_skill.is_empty() or _current.is_empty():
		_set_status("先选 BOSS → 招式 → 特效", Color(0.62, 0.22, 0.16))
		return
	var sid := String(_picked_skill.get("skill_id", ""))
	var eid := String(_current.get("id", ""))
	if not PixelFxLib.is_baked(eid, _variant):
		# 绑定会写进游戏读的表，所以必须指向已导入的素材；只有预览版时先让他导入
		_set_status("这个是预览版（只在 user://），招式在游戏里读不到。"
			+ "先点「烘焙并导入」再绑定", Color(0.62, 0.40, 0.16))
		return
	var opts := {
		"pixelfx": eid,
		"pixelfx_variant": _variant,
		"pixelfx_scale": roundf(_scale * 100.0) / 100.0,
		"pixelfx_additive": _additive,
		"pixelfx_flip_by_dir": true,
		"note": String(_picked_skill.get("skill_name", "")),
	}
	if not PixelFxLib.set_binding(sid, opts):
		_set_status("绑定表写入失败（检查 assets/fx/pixelfx 是否可写）", Color(0.62, 0.22, 0.16))
		return
	_refresh_left()
	_set_status("已绑定：%s → %s「%s」[%s]（进游戏放这招就是像素版）" % [
		sid, _fx_display(_current), eid, _variant], Color(0.44, 0.52, 0.40))


func _unbind_skill() -> void:
	if _picked_skill.is_empty():
		return
	var sid := String(_picked_skill.get("skill_id", ""))
	PixelFxLib.set_binding(sid, {})
	_refresh_left()
	_set_status("已解绑 %s：回到原来的演出" % sid, Color(0.62, 0.40, 0.16))


func _pick_effect(one: Dictionary) -> void:
	_current = one
	_pivot = Vector2(float((_current.get("origin", [0, 0]) as Array)[0]),
		float((_current.get("origin", [0, 0]) as Array)[1]))
	_sprite.offset = -_pivot
	_sprite.scale = Vector2(_scale, _scale)
	var opts: Dictionary = _current.get("options", {})
	_reach_row.visible = opts.has("reach")
	_reach_spin.value = float(opts.get("reach", 0))
	_fps_spin.value = float(_current.get("fps", 30))
	_fps_touched = false
	_seed_touched = false
	_seed_spin.value = float(opts.get("seed", 4))
	_scale = 1.0
	_scale_val.text = "×1.00"
	_sprite.scale = Vector2.ONE
	var variants := PixelFxLib.baked_variants(String(_current.get("id", "")))
	if variants.is_empty() and PixelFxLib.is_preview_baked(
			String(_current.get("id", "")), _variant):
		# 只有预览版：照样能播，但状态行说清楚它还没进游戏
		_load_preview(String(_current.get("id", "")), _variant)
		_update_info()
		_set_status("这是预览版（user://），还没导入游戏；要用在招式上点「烘焙并导入」",
			Color(0.50, 0.52, 0.62))
		return
	if variants.is_empty():
		_frames = []
		_times = PackedFloat64Array()
		_total = 0.0
		_sprite.texture = null
		_timeline.max_value = 0
		_variant = "default" if _chosen_ramp == "" else _chosen_ramp
		_set_status("还没烘：先点「烘焙预览（不进游戏）」看效果（约 1~3 秒）", Color(0.62, 0.40, 0.16))
		_update_info()
		return
	if not variants.has(_variant):
		_variant = String(variants[0])
	_load_preview(String(_current.get("id", "")), _variant)
	_update_info()
	_update_bind_buttons()


func _load_preview(id: String, variant: String) -> void:
	var sheet := PixelFxLib.sheet_any_for(id, variant)
	if sheet.is_empty():
		_frames = []
		_sprite.texture = null
		_update_info()
		return
	_frames = sheet.get("frames", [])
	_times = PackedFloat64Array()
	_total = float(sheet.get("total_time", 0.0))
	var acc := 0.0
	for d in (sheet.get("durations", []) as Array):
		_times.append(acc)
		acc += float(d) / 1000.0
	_pivot = sheet.get("pivot", _pivot)
	_sprite.offset = -_pivot
	_timeline.max_value = maxi(0, _frames.size() - 1)
	_elapsed = 0.0
	_index = -1
	_show_index(0)
	_playing = true
	_play_btn.set_pressed_no_signal(true)


func _update_info() -> void:
	if _current.is_empty():
		_info.text = "左边选一个特效"
		return
	var hits: Array = _current.get("hits", [])
	var first_t := float(hits[0].get("t", -1.0)) if not hits.is_empty() else -1.0
	_info.text = "%s（%s）[%s]　%d 帧　%.2fs　%s" % [
		_fx_display(_current), String(_current.get("id", "")), _variant,
		_frames.size(), _total,
		("命中帧 t=%.2fs" % first_t) if first_t >= 0.0 else "无命中时序"]


# ===================== 播放 =====================

func _on_play_toggled(on: bool) -> void:
	_playing = on
	if on and _elapsed >= _total - 0.001:
		_elapsed = 0.0


func _process(delta: float) -> void:
	if _stage == null:
		return
	var size := _stage.size
	_stage_bg.size = size
	var center := size * 0.5
	_ground_line.position = Vector2(0, center.y)
	_ground_line.size = Vector2(size.x, 1)
	_pivot_mark.position = Vector2(center.x - 1, center.y - 6)
	_pivot_mark.size = Vector2(2, 12)
	_sprite.position = center
	if _frames.is_empty() or not _playing:
		return
	_elapsed += delta * _speed
	if _elapsed >= _total:
		if bool(_current.get("loop", false)):
			_elapsed = fposmod(_elapsed, maxf(0.001, _total))
		else:
			_elapsed = maxf(0.0, _total - 0.001)
			_playing = false
			_play_btn.set_pressed_no_signal(false)
	_show_index(_frame_at(_elapsed))


func _frame_at(t: float) -> int:
	var lo := 0
	for i in _times.size():
		if _times[i] <= t:
			lo = i
		else:
			break
	return lo


func _show_index(i: int) -> void:
	if _frames.is_empty():
		return
	var idx := clampi(i, 0, _frames.size() - 1)
	if idx == _index:
		return
	_index = idx
	_sprite.texture = _frames[idx] as Texture2D
	_timeline.set_value_no_signal(idx)
	if _info != null and not _current.is_empty():
		_info.text = "%s（%s）　%s　帧 %d/%d　t=%.2fs" % [
			_fx_display(_current), String(_current.get("id", "")), _variant,
			idx + 1, _frames.size(), float(_times[idx])]


func _step_frame() -> void:
	_playing = false
	_play_btn.set_pressed_no_signal(false)
	var next := 0 if _index + 1 >= _frames.size() else _index + 1
	_elapsed = _times[next] if next < _times.size() else 0.0
	_show_index(next)


func _on_scale(v: float) -> void:
	_scale = v
	_sprite.scale = Vector2(v, v)
	_sprite.offset = -_pivot
	if _scale_val != null:
		_scale_val.text = "×%.2f" % v


func _fit_to_radius() -> void:
	var sz: Array = _current.get("size", [1, 1])
	_on_scale(200.0 / maxf(1.0, float(sz[0])))
	_set_status("已按半径 200px 缩放 ×%.2f" % _scale, Color(0.44, 0.52, 0.40))


# ===================== 烘焙 =====================

func _do_bake(to_game: bool) -> void:
	if _current.is_empty():
		_set_status("先在左边选一个特效", Color(0.62, 0.22, 0.16))
		return
	if _busy:
		return
	var id := String(_current.get("id", ""))
	var job := {"id": id, "variant": _variant}
	if _chosen_ramp == "custom":
		job["palette"] = _custom_hex
	elif _chosen_ramp != "":
		job["palette"] = _chosen_ramp
	if _seed_touched:
		job["seed"] = int(_seed_spin.value)
	if _fps_touched:
		job["fps"] = int(_fps_spin.value)
	if bool(_actor_chk.button_pressed):
		job["actor"] = true
	if _reach_row.visible:
		job["set"] = {"reach": int(_reach_spin.value)}
	# 只预览 → 烘到 user:// 预览区（绝对路径，不经 Godot 导入流程，不进 git / 不进导出包）
	# 要导入 → 烘到 res://assets/fx/pixelfx（正式素材）
	var out := PixelFxLib.preview_dir() if not to_game 		else ProjectSettings.globalize_path(plugin.get_output_dir())
	var args := PackedStringArray([
		ProjectSettings.globalize_path("res://tools/pixelfx/bake.mjs"),
		"--jobs", _write_jobs([job]),
		"--lib", plugin.get_library_path(),
		"--out", out,
	])
	_busy = true
	_bake_btn.disabled = true
	_set_status("烘焙 %s [%s] …" % [id, _variant], Color(0.62, 0.50, 0.20))
	await get_tree().process_frame
	var lines: Array[String] = []
	var code := OS.execute(plugin.get_node_path(), args, lines, 120000.0)
	_busy = false
	_bake_btn.disabled = false
	var parsed := _parse_bake_output(lines)
	if parsed.is_empty():
		var why := "没读到回执"
		for l in lines:
			if String(l).contains("BAKE_FAIL") or String(l).contains("BAKE_ERR"):
				why = String(l)
				break
		_set_status("烘焙失败（exit %d）：%s" % [code, why], Color(0.62, 0.22, 0.16))
		return
	var png := String(parsed.get("res_png", ""))
	if to_game:
		EditorInterface.get_resource_filesystem().reimport_files(PackedStringArray([png]))
		EditorInterface.get_resource_filesystem().scan()
		await get_tree().create_timer(0.7).timeout
	PixelFxLib.invalidate()
	_load_preview(id, _variant)
	_refresh_left()
	_update_info()
	_set_status("%s：%s（%d 帧 · pivot %s · %s）%s" % [
		"已导入" if to_game else "仅预览", png, int(parsed.get("frames", 0)),
		str(parsed.get("pivot", Vector2i.ZERO)),
		"循环" if bool(parsed.get("loop", false)) else "一次性",
		"" if to_game else "　· 没进 assets/，想真正用上再点「烘焙并导入」"],
		Color(0.44, 0.52, 0.40) if to_game else Color(0.50, 0.52, 0.62))


## 清预览缓存：只动 user:// 那一坨，正式素材不碰
func _clear_preview() -> void:
	var n := PixelFxLib.clear_preview()
	_frames = []
	_sprite.texture = null
	_refresh_left()
	_set_status("预览缓存已清空（删了 %d 个文件；assets/ 里的正式素材没动）" % n,
		Color(0.50, 0.52, 0.62))


func _write_jobs(jobs: Array) -> String:
	DirAccess.make_dir_recursive_absolute("user://pixelfx")
	var p := "user://pixelfx/job.json"
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(jobs, "  "))
	f.close()
	return ProjectSettings.globalize_path(p)


## BAKE_OK <id> <variant> <res://….png> <frames> <fps> <w> <h> <cols> <px> <py> <loop|once>
func _parse_bake_output(lines: Array[String]) -> Dictionary:
	var last := ""
	for l in lines:
		if String(l).begins_with("BAKE_OK"):
			last = String(l)
	if last == "":
		return {}
	var f := last.split(" ")
	if f.size() < 12:
		return {}
	return {
		"id": f[1], "variant": f[2], "res_png": f[3], "frames": int(f[4]),
		"fps": int(f[5]), "pivot": Vector2i(int(f[9]), int(f[10])),
		"loop": f[11] == "loop",
	}


# ===================== 落地到项目 =====================

func _attach_to_selection() -> void:
	if _current.is_empty():
		_set_status("先选一个特效", Color(0.62, 0.22, 0.16))
		return
	var id := String(_current.get("id", ""))
	if not PixelFxLib.is_baked(id, _variant):
		_set_status("只有预览版时不能挂进场景（存下来游戏里读不到）；先「烘焙并导入」",
			Color(0.62, 0.40, 0.16))
		return
	var picked: Array = plugin.get_editor_interface().get_selection().get_selected_nodes()
	var scene_root: Node = plugin.get_editor_interface().get_edited_scene_root()
	if picked.is_empty() or scene_root == null:
		_set_status("没选中场景里的 Node2D（或没有打开的场景）", Color(0.62, 0.22, 0.16))
		return
	var n := 0
	for node in picked:
		if not (node is Node2D):
			continue
		var fx := PixelFxFx.new()
		fx.name = "PixelFx_%s" % PixelFxLib.short_name(id)
		fx.effect_id = id
		fx.variant = _variant
		fx.auto_free = false  # 挂在场景里，绝不能播完就自删
		fx.additive = _additive
		# 这版 UndoRedo 收 Callable，不是 (object, 方法名, 参数...)
		var ur: UndoRedo = plugin.get_undo_redo()
		ur.create_action("挂像素特效 %s" % id)
		ur.add_do_method(node.add_child.bind(fx))
		ur.add_do_method(fx.set_owner.bind(scene_root))
		ur.add_do_method(fx.set_scale_mult.bind(_scale))
		ur.add_do_method(fx.set_flip.bind(_flip))
		ur.add_undo_method(fx.queue_free)
		ur.commit_action()
		n += 1
	_set_status("已挂到 %d 个节点（Ctrl+S 保存场景）" % n, Color(0.44, 0.52, 0.40))


## 生成 SKILL_FX 片段：粘进 ArtDB 里那一招的配置，通道自己会切
func _copy_binding_snippet() -> void:
	if _current.is_empty():
		_set_status("先选一个特效", Color(0.62, 0.22, 0.16))
		return
	var snippet := '"motif": "pixel", "pixelfx": "%s", "pixelfx_variant": "%s", ' % [
		String(_current.get("id", "")), _variant]
	snippet += '"pixelfx_scale": %.2f, ' % _scale
	snippet += '"pixelfx_additive": %s, ' % ("true" if _additive else "false")
	snippet += '"pixelfx_flip_by_dir": true, "pixelfx_fit_radius": false'
	DisplayServer.clipboard_set(snippet)
	_set_status("绑定代码已复制到剪贴板（粘进 ArtDB.SKILL_FX 那一条）", Color(0.44, 0.52, 0.40))


func _set_status(text: String, color: Color) -> void:
	if _status == null:
		return
	_status.text = text
	_status.add_theme_color_override("font_color", color)
