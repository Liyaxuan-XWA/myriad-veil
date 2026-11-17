extends Control
## 开始界面（游戏启动场景）
##
## 美术接入（2026-10-25）：背景与主角立绘来自用户美术包。
## 背景图自带「万界秘境」标题与三个漩涡下的按钮文案，因此不再绘制文字标题/传统按钮。
## 交互热点是三个透明 Button，位置对应背景中的大/小漩涡；hover / 键盘聚焦时高亮漩涡。
##
## 主角动态：Sprite2D 呼吸浮动 + 衣摆/发丝 UV 摆动 shader；
## 点击「开始旅程」后停用待机动态，改为被大漩涡牵引 → 光丝溶解 → 粒子收束 / 白闪 → 进入原初位面。

const BG_PATH := "res://assets/ui/title/bg.png"
const PLAYER_PATH := "res://assets/ui/title/player.png"
const PLAYER_SHADER := "res://assets/shaders/title_player_sway.gdshader"
const REALM_SCENE := "res://scenes/main/primordial_realm.tscn"
## 登录界面 BGM（Suno 生成 → tools/loop_title_bgm.py 裁切 + 无缝循环 + 压 32kHz）
## 换曲只改这一条路径；素材缺失时 BgmPlayer 只警告、界面照常运行
const BGM_TITLE := "res://assets/audio/bgm/title_veil.wav"

## 主角立绘的目标高度（屏高占比）与中心点（底部留出呼吸/浮动空间）
const PLAYER_HEIGHT_RATIO := 0.70
const PLAYER_CENTER := Vector2(0.39, 0.63)

## 三个漩涡的透明点击区：center / size 都是屏幕归一化坐标
const HOTSPOTS: Array = [
	{"id": "start", "center": Vector2(0.500, 0.440), "size": Vector2(0.280, 0.400),
		"glow": 1.25, "tooltip": "开始旅程"},
	{"id": "settings", "center": Vector2(0.287, 0.525), "size": Vector2(0.140, 0.220),
		"glow": 1.65, "tooltip": "设置"},
	{"id": "quit", "center": Vector2(0.775, 0.665), "size": Vector2(0.170, 0.240),
		"glow": 1.55, "tooltip": "退出游戏"},
]

var _bg: TextureRect
var _dim: ColorRect
var _vignette: TextureRect
var _player: Sprite2D
var _player_tex: Texture2D
var _player_mat: ShaderMaterial
var _player_aura: Sprite2D
var _aura_tween: Tween
var _cam_tween: Tween
var _absorb_fx: TitleAbsorbFx
var _bgm: BgmPlayer = null
var _hotspot_nodes: Array = []
var _glow_tex: Texture2D
var _flash_tex: Texture2D
var _btn_start: Button
var _start_center := Vector2(640.0, 317.0)
var _start_size := Vector2(358.0, 288.0)
var _starting := false
var _player_base_pos := Vector2.ZERO
var _player_base_scale := Vector2.ONE
var _idle_time := 0.0


func _ready() -> void:
	# 开始界面不需要虚拟键（autoload 会跨场景活着，必须显式收起来）
	VirtualPad.set_context("none")
	_build()
	_start_bgm()
	SettingsUI.set_entry_visible(false)
	if _btn_start != null:
		_btn_start.grab_focus()
	# 轻微淡入，避免一帧硬切
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.35)


# ===================== 构建 =====================

## 登录界面 BGM：氛围铺底，比主城再轻 1dB（主城是 AMBIENT_VOLUME_DB）
## ⚠ 播放器挂在场景自己身上：按下「开始旅程」后由 `_on_dissolve_begin()` 淡出，
##   切换场景时随节点一起销毁 —— 不需要跨场景托管，主城会用自己的 BgmPlayer 接上
func _start_bgm() -> void:
	_bgm = BgmPlayer.new()
	_bgm.name = "TitleBgm"
	add_child(_bgm)
	_bgm.play_loop(BGM_TITLE, BgmPlayer.AMBIENT_VOLUME_DB - 1.0, 2.4)

func _build() -> void:
	_build_background()
	_build_focus()
	_build_player()
	_build_hotspots()
	_build_new_game_button()
	resized.connect(_layout)
	_layout()


func _build_background() -> void:
	_bg = TextureRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.z_index = -10
	if ResourceLoader.exists(BG_PATH):
		_bg.texture = load(BG_PATH)
	else:
		# 美术缺失时的兜底渐变，保证界面仍能运行
		var grad := Gradient.new()
		grad.colors = PackedColorArray([
			UIKit.C_PANEL_BG,
			UIKit.C_PANEL_BG.darkened(0.55),
		])
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.fill_from = Vector2(0.5, 0.0)
		gt.fill_to = Vector2(0.5, 1.0)
		_bg.texture = gt
	add_child(_bg)


func _build_focus() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.004, 0.008, 0.018, 0.0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.z_index = 0
	add_child(_dim)

	_vignette = TextureRect.new()
	_vignette.texture = _make_vignette_texture()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.z_index = 0
	_vignette.modulate = Color(1, 1, 1, 0)
	add_child(_vignette)


func _build_player() -> void:
	if not ResourceLoader.exists(PLAYER_PATH):
		return
	_player_tex = load(PLAYER_PATH) as Texture2D
	if _player_tex == null:
		return
	_player = Sprite2D.new()
	_player.texture = _player_tex
	_player.centered = true
	_player.z_index = 2
	if ResourceLoader.exists(PLAYER_SHADER):
		var sh := load(PLAYER_SHADER) as Shader
		if sh != null:
			_player_mat = ShaderMaterial.new()
			_player_mat.shader = sh
			_player.material = _player_mat
	add_child(_player)

	# 背部柔光：吸入时亮起，给身形加一层体积感
	_player_aura = Sprite2D.new()
	_player_aura.texture = _make_glow_texture(Color(0.42, 0.88, 1.0, 1.0))
	_player_aura.centered = true
	_player_aura.z_index = -1
	_player_aura.scale = Vector2(4.8, 11.2)
	_player_aura.modulate = Color(0.9, 0.98, 1.0, 0.0)
	var aura_mat := CanvasItemMaterial.new()
	aura_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_player_aura.material = aura_mat
	_player.add_child(_player_aura)


func _build_hotspots() -> void:
	_glow_tex = _make_glow_texture(Color(0.58, 0.95, 1.0, 1.0))
	_flash_tex = _make_glow_texture(Color(1.0, 1.0, 1.0, 1.0))

	for raw in HOTSPOTS:
		var spec: Dictionary = raw
		var id := String(spec.get("id", ""))
		var glow := TextureRect.new()
		glow.texture = _glow_tex
		glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow.modulate = Color(1, 1, 1, 0)
		glow.z_index = 4
		add_child(glow)

		var btn := Button.new()
		btn.text = ""
		btn.flat = true
		btn.focus_mode = Control.FOCUS_ALL
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.tooltip_text = String(spec.get("tooltip", ""))
		btn.z_index = 10
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		btn.pressed.connect(_on_hotspot_pressed.bind(id))
		btn.mouse_entered.connect(_on_hotspot_hover.bind(glow))
		btn.mouse_exited.connect(_set_glow.bind(glow, false))
		# ⚠ 键盘聚焦只亮不响：`_ready()` 里的 `_btn_start.grab_focus()` 会立刻触发一次
		#   focus_entered，接上提示音就会在刚进界面时莫名其妙响一声
		btn.focus_entered.connect(_set_glow.bind(glow, true))
		btn.focus_exited.connect(_set_glow.bind(glow, false))
		add_child(btn)
		_hotspot_nodes.append({"button": btn, "glow": glow, "spec": spec})
		if id == "start":
			_btn_start = btn


func _layout() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		vp = Vector2(1280.0, 720.0)

	if _player != null and _player_tex != null:
		var target_h := vp.y * PLAYER_HEIGHT_RATIO
		var s := target_h / float(_player_tex.get_height())
		_player_base_scale = Vector2(s, s)
		_player_base_pos = Vector2(vp.x * PLAYER_CENTER.x, vp.y * PLAYER_CENTER.y)
		if not _starting:
			_player.scale = _player_base_scale
			_player.position = _player_base_pos

	for raw in _hotspot_nodes:
		var e: Dictionary = raw
		var spec: Dictionary = e.get("spec", {})
		var center: Vector2 = Vector2(spec.get("center", Vector2(0.5, 0.5))) * vp
		var sz: Vector2 = Vector2(spec.get("size", Vector2(0.2, 0.2))) * vp
		var btn: Button = e.get("button")
		btn.position = center - sz * 0.5
		btn.size = sz

		var glow: TextureRect = e.get("glow")
		var gsz := sz * float(spec.get("glow", 1.4))
		glow.position = center - gsz * 0.5
		glow.size = gsz

		if String(spec.get("id", "")) == "start":
			_start_center = center
			_start_size = sz


## 待机动态：轻微上下浮动 + 呼吸缩放；衣摆/发丝摆动由 shader 的 TIME 驱动
func _process(delta: float) -> void:
	if _starting or _player == null or not is_instance_valid(_player):
		return
	_idle_time += delta
	var sway_x := sin(_idle_time * 0.9) * 1.2
	var bob := sin(_idle_time * 1.55) * 2.6
	var breath := sin(_idle_time * 1.85 + 0.6) * 0.0022
	_player.position = _player_base_pos + Vector2(sway_x, bob)
	_player.scale = Vector2(
		_player_base_scale.x * (1.0 - breath * 0.35),
		_player_base_scale.y * (1.0 + breath),
	)


func _make_glow_texture(tint: Color) -> Texture2D:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size * 0.5 - 0.5, size * 0.5 - 0.5)
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(c) / (size * 0.5)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 2.2)
			img.set_pixel(x, y, Color(tint.r, tint.g, tint.b, a))
	return ImageTexture.create_from_image(img)


## 暗角：吸入时压暗四周，把视线收到漩涡与主角身上
func _make_vignette_texture() -> Texture2D:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			var a := smoothstep(0.42, 0.98, d) * 0.75
			img.set_pixel(x, y, Color(0.004, 0.008, 0.018, a))
	return ImageTexture.create_from_image(img)


func _set_glow(glow: TextureRect, on: bool) -> void:
	if glow == null or not is_instance_valid(glow):
		return
	var old = glow.get_meta("tw") if glow.has_meta("tw") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var tw := create_tween()
	tw.tween_property(glow, "modulate:a", 0.48 if on else 0.0, 0.18)
	glow.set_meta("tw", tw)


## 鼠标移入漩涡：亮起来 + 一点极轻的提示音（音量只有点击的 46%，连扫三个也不吵）
func _on_hotspot_hover(glow: TextureRect) -> void:
	if _starting:
		return
	_set_glow(glow, true)
	GameState.play_ui("ui_hover")


# ===================== 交互 =====================

func _on_hotspot_pressed(id: String) -> void:
	if _starting:
		return
	match id:
		"start":
			_on_start_pressed()
		"settings":
			GameState.play_ui("ui_click")
			_on_settings_pressed()
		"quit":
			GameState.play_ui("ui_click")
			_on_quit_pressed()


func _on_start_pressed() -> void:
	if _starting:
		return
	_starting = true
	for raw in _hotspot_nodes:
		var entry: Dictionary = raw
		var btn: Button = entry.get("button")
		btn.disabled = true
		var glow: TextureRect = entry.get("glow")
		if glow != null:
			glow.visible = false

	_begin_cinematic()
	_play_absorb_fx()

	if _player == null or _player_tex == null:
		await get_tree().create_timer(0.35).timeout
		if _absorb_fx != null:
			_absorb_fx.collapse()
		_play_vortex_flash()
		await get_tree().create_timer(0.35).timeout
		_enter_game()
		return

	# 第一段：向后轻仰，像被气流先托住
	var pull_pos := _player.position + Vector2(-12.0, -6.0)
	var prep := create_tween().set_parallel(true)
	prep.tween_property(_player, "position", pull_pos, 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	prep.tween_property(_player, "scale", _player.scale * 1.02, 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await prep.finished
	GameState.play_ui("title_pull")
	if _absorb_fx != null:
		_absorb_fx.begin_pull()

	# 第二段：弧线牵引 + 缩小 + 轻微旋转；残影立即出现，溶解在后半段
	var p0 := _player.position
	var s0 := _player.scale
	var r0 := _player.rotation
	# 终点偏到漩涡左上臂：避开中心白核，溶解时轮廓更清楚
	var p3 := _start_center + Vector2(-52.0, -34.0)
	var s3 := _player_base_scale * 0.23
	_spawn_player_trail(0.98)

	var move_tw := create_tween()
	move_tw.tween_method(
		_update_absorb_pose.bind(p0, p3, s0, s3, r0),
		0.0, 1.0, 0.92
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	# 溶解刻意压后：先完整地被卷到漩涡口，再散成光丝
	var dissolve_tw := create_tween()
	dissolve_tw.tween_interval(0.52)
	dissolve_tw.tween_method(_set_player_dissolve, 0.0, 1.0, 0.40)

	var beat_tw := create_tween()
	beat_tw.tween_interval(0.52)
	beat_tw.tween_callback(_on_dissolve_begin)

	await move_tw.finished
	await get_tree().create_timer(0.04).timeout
	if _absorb_fx != null:
		_absorb_fx.collapse()
	_play_vortex_flash()
	await get_tree().create_timer(0.32).timeout
	_enter_game()


## 吸入前的镜头推近与压暗，把注意力收束到漩涡和主角身上
func _begin_cinematic() -> void:
	GameState.play_ui("title_charge")
	pivot_offset = _start_center
	_cam_tween = create_tween()
	_cam_tween.tween_property(self, "scale", Vector2(1.045, 1.045), 1.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var focus_tw := create_tween().set_parallel(true)
	focus_tw.tween_property(_dim, "color", Color(0.004, 0.008, 0.018, 0.20), 0.45)
	focus_tw.tween_property(_vignette, "modulate:a", 1.0, 0.6)

	if _player_aura != null:
		_aura_tween = create_tween()
		_aura_tween.tween_property(_player_aura, "modulate:a", 0.42, 0.6) \
			.set_trans(Tween.TRANS_SINE)
		var aura_scale := create_tween()
		aura_scale.tween_property(_player_aura, "scale", Vector2(5.3, 12.2), 1.0) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var charge_tw := create_tween()
	charge_tw.tween_method(_set_player_charge, 0.0, 0.95, 0.8) \
		.set_trans(Tween.TRANS_SINE)

	var wind_tw := create_tween()
	wind_tw.tween_method(_set_player_wind, 0.0, 1.0, 0.9)


## 溶解开始：漩涡冲击波 + 主角体内灵光再抬一档
func _on_dissolve_begin() -> void:
	GameState.play_ui("title_dissolve")
	# 此刻约 0.68s，淡出 0.7s → 1.38s 收干净，场景在 1.44s 切换
	if _bgm != null and is_instance_valid(_bgm):
		_bgm.fade_out(0.7)
	if _absorb_fx != null:
		_absorb_fx.begin_dissolve()
	_set_player_charge(1.25)
	if _player_aura != null:
		if _aura_tween != null and _aura_tween.is_valid():
			_aura_tween.kill()
		_aura_tween = create_tween()
		_aura_tween.tween_property(_player_aura, "modulate:a", 0.0, 0.35)


## 大漩涡能量场 + 星尘 + 牵引拖尾
func _play_absorb_fx() -> void:
	_absorb_fx = TitleAbsorbFx.new()
	_absorb_fx.radius = maxf(150.0, _start_size.x * 0.55)
	_absorb_fx.position = _start_center
	_absorb_fx.source = _player
	add_child(_absorb_fx)


func _set_player_charge(v: float) -> void:
	if _player_mat != null:
		_player_mat.set_shader_parameter("charge", v)


## 0 = 待机风摆，1 = 吸入时的强风
func _set_player_wind(v: float) -> void:
	if _player_mat == null:
		return
	_player_mat.set_shader_parameter("hair_strength", lerpf(0.013, 0.026, v))
	_player_mat.set_shader_parameter("cloth_strength", lerpf(0.0085, 0.018, v))


func _set_player_dissolve(v: float) -> void:
	if _player_mat != null:
		_player_mat.set_shader_parameter("dissolve_amount", pow(v, 1.45))


## 多次贝塞尔曲线：先向左上扬起，再盘旋进漩涡，避免直线拖拽
func _update_absorb_pose(t: float, p0: Vector2, p3: Vector2,
		s0: Vector2, s3: Vector2, r0: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var p1 := p0 + Vector2(-26.0, -96.0)
	var p2 := p3 + Vector2(-130.0, 58.0)
	_player.position = _cubic_bezier(p0, p1, p2, p3, t)
	# 前段保持身形完整，接近漩涡口才急剧缩小，让溶解光丝看得清
	var shrink := clampf((t - 0.35) / 0.65, 0.0, 1.0)
	_player.scale = s0.lerp(s3, shrink * shrink * shrink)
	_player.rotation = r0 + sin(t * PI) * 0.07 + t * t * 0.36


func _cubic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return p0 * (u * u * u) + p1 * (3.0 * u * u * t) \
		+ p2 * (3.0 * u * t * t) + p3 * (t * t * t)


func _spawn_player_trail(duration: float) -> void:
	var left := duration
	while left > 0.0 and _starting:
		_spawn_player_ghost()
		await get_tree().create_timer(0.075).timeout
		left -= 0.075


## 青色残影：复制当前立绘帧，留在原地渐隐
func _spawn_player_ghost() -> void:
	if _player == null or _player_tex == null or not is_instance_valid(_player):
		return
	var ghost := Sprite2D.new()
	ghost.texture = _player_tex
	ghost.position = _player.position
	ghost.scale = _player.scale
	ghost.rotation = _player.rotation
	ghost.modulate = Color(0.45, 0.88, 1.0, 0.24)
	ghost.z_index = 1
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	ghost.material = mat
	add_child(ghost)
	get_tree().create_timer(0.40).timeout.connect(ghost.queue_free)
	var tw := ghost.create_tween().set_parallel(true)
	tw.tween_property(ghost, "modulate:a", 0.0, 0.40) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ghost, "scale", ghost.scale * 0.90, 0.40)


func _play_vortex_flash() -> void:
	# 收束 + 白闪合成一发：0.85 秒的下潜 boom 盖住场景切换的空档
	# （走 GameState 的 autoload 播放器，切场景时尾音不会被连根拔掉）
	GameState.play_ui("title_collapse")
	# 收束瞬间再补一下镜头推近
	if _cam_tween != null and _cam_tween.is_valid():
		_cam_tween.kill()
	var punch := create_tween()
	punch.tween_property(self, "scale", Vector2(1.07, 1.07), 0.10) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	# 全屏柔光罩：短暂洗亮屏幕，与局部漩涡闪光叠出层次
	var veil := ColorRect.new()
	veil.color = Color(0.60, 0.92, 1.0, 1.0)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.z_index = 21
	veil.modulate = Color(1, 1, 1, 0)
	add_child(veil)
	get_tree().create_timer(0.5).timeout.connect(veil.queue_free)
	var veil_tw := create_tween()
	veil_tw.tween_property(veil, "modulate:a", 0.36, 0.05)
	veil_tw.tween_property(veil, "modulate:a", 0.0, 0.32)

	# 局部青色能量光
	var aura := TextureRect.new()
	aura.texture = _glow_tex
	aura.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	aura.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aura.z_index = 19
	aura.size = _start_size * 1.5
	aura.position = _start_center - aura.size * 0.5
	aura.pivot_offset = aura.size * 0.5
	aura.modulate = Color(0.45, 0.88, 1.0, 0.48)
	add_child(aura)
	get_tree().create_timer(0.48).timeout.connect(aura.queue_free)
	var aura_tw := create_tween().set_parallel(true)
	aura_tw.tween_property(aura, "scale", Vector2(1.55, 1.55), 0.44)
	aura_tw.tween_property(aura, "modulate:a", 0.0, 0.44)

	# 白色核心闪光
	var flash := TextureRect.new()
	flash.texture = _flash_tex
	flash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flash.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 20
	flash.size = _start_size * 1.15
	flash.position = _start_center - flash.size * 0.5
	flash.pivot_offset = flash.size * 0.5
	flash.modulate = Color(0.92, 1.0, 1.0, 0.85)
	add_child(flash)
	get_tree().create_timer(0.38).timeout.connect(flash.queue_free)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(flash, "scale", Vector2(1.5, 1.5), 0.34)
	tw.tween_property(flash, "modulate:a", 0.0, 0.34)


## 「新的旅程」入口：背景美术只有三个漩涡（开始 / 设置 / 退出），不再往画上硬塞第四个，
## 改成左下角一枚水墨令签。走确认框 —— 它会清空 5 个存档槽，误点代价太大。
func _build_new_game_button() -> void:
	var btn := UIKit.button("新的旅程", Vector2(150.0, 40.0))
	btn.name = "NewGameButton"
	btn.tooltip_text = "清空现有存档，从练气前期重新开始"
	btn.add_theme_font_size_override("font_size", 17)
	btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	btn.offset_left = 26.0
	btn.offset_right = 176.0
	btn.offset_top = -58.0
	btn.offset_bottom = -18.0
	btn.pressed.connect(_on_new_game_pressed)
	add_child(btn)


func _on_new_game_pressed() -> void:
	ConfirmDialog.ask(
		"新的旅程",
		"将从练气前期重新开始。\n现有 5 个存档槽会各自留一份 .bak 备份后清空。",
		"重开",
		"取消",
		func() -> void:
			SaveManager.new_game()
			GameState.reset_time_flow()
			_enter_game(),
		true)


func _on_settings_pressed() -> void:
	SettingsUI.open_panel(true)


## 与窗口 × 同一个入口：先弹确认框，玩家点确认才结束进程
func _on_quit_pressed() -> void:
	GameState.ask_quit()


## 进入主城；离开前恢复右上角常驻设置按钮（其余场景都依赖它）
func _enter_game() -> void:
	SettingsUI.set_entry_visible(true)
	# ⚠ 进主城前必须读最近的存档。标题界面只有一个「开始旅程」入口，不读档就会拿
	#   内存里的新开局进主城 —— 表现就是「每次进游戏都是新存档」。
	#   没有可用存档时 load_latest_auto() 返回 false，此时保持新开局（正常）。
	SaveManager.load_latest_auto()
	get_tree().change_scene_to_file(REALM_SCENE)
