extends CharacterBody2D
## 原初位面内的主角（李青云）简版控制器
## 主城为安全枢纽：无战斗动作（攻击/弹刀），但保留闪避键作为「疾行」赶路手段
## 与战斗闪避的区别（勿混淆）：
##   - 不消耗精力、无冷却资源压力
##   - 无完美闪避判定（主城无敌人，perfect_dodge 语义不存在）
##   - 无音效
## 目的：位面较大（设施跨度超 1000px），纯 200 速度步行赶路体验太拖沓

const MOVE_SPEED := 200.0
const DASH_SPEED := 620.0
const DASH_TIME := 0.22
const DASH_COOLDOWN := 0.5
const GHOST_INTERVAL := 0.045
const GHOST_LIFE := 0.25
## 传送登场：进主城 / 回主城时锁操作并播放大淡入（2026-10-24）
const TELEPORT_ARRIVAL_TIME := 0.75
## 打坐（2026-10-24 用户定）：原地连续站立 60 秒进入，每 2 秒 +1 修为
const MEDITATE_IDLE_TIME := 60.0
const MEDITATE_TICK := 2.0

const BODY_COLOR := Color(0.3, 0.7, 1.0, 1.0)

@onready var anim: Node2D = $Visual
## Visual 下的 SkinVisual 子节点（控制行走动画播放/暂停）
@onready var skin: SkinVisual = get_node_or_null("Visual/Skin") as SkinVisual

var _dash_timer: float = 0.0
var _dash_cooldown: float = 0.0
var _dash_dir: Vector2 = Vector2.ZERO
var _ghost_timer: float = 0.0
var _facing_x: float = 1.0
var is_teleporting: bool = false
var _idle_time: float = 0.0
var _meditating := false
var _meditate_tick_timer := 0.0
var _meditation_aura: Node2D = null
var _meditation_label: Label = null


func _ready() -> void:
	# 加入 "player" 组：设施的靠近检测（facility.gd 的 player_near 信号）等
	# 通用逻辑靠这个组识别玩家，与战斗场景的 player.gd 保持一致。
	# 主城虽无战斗，但进组无害，且能让同一套靠近/交互逻辑在两个场景通用。
	add_to_group("player")
	is_teleporting = true
	TeleportArrival.prepare(anim)
	_create_meditation_visual()
	# 父场景可能在 _ready 里摆玩家（回主城 / 新开局），延迟一帧再播，确保特效落在出生点
	call_deferred("_begin_teleport_arrival")


func _begin_teleport_arrival() -> void:
	# 等两帧：父场景 / 首帧资源加载完成后再播，保证登场演出完整可见
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	TeleportArrival.play(self, anim, Vector2(0.0, -38.0), TELEPORT_ARRIVAL_TIME,
		func() -> void: is_teleporting = false)


func _physics_process(delta: float) -> void:
	if is_teleporting:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_visual(Vector2.ZERO)
		return

	if _dash_cooldown > 0.0:
		_dash_cooldown -= delta

	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	if _dash_timer <= 0.0 and _dash_cooldown <= 0.0 and Input.is_action_just_pressed("dodge"):
		_start_dash(dir)

	if _dash_timer > 0.0:
		_dash_timer -= delta
		velocity = _dash_dir * DASH_SPEED
		_ghost_timer -= delta
		if _ghost_timer <= 0.0:
			_ghost_timer = GHOST_INTERVAL
			_spawn_ghost()
		if _dash_timer <= 0.0:
			_end_dash()
	else:
		velocity = dir * MOVE_SPEED

	move_and_slide()
	_update_visual(dir if _dash_timer <= 0.0 else _dash_dir)
	_tick_meditation(delta, dir.length_squared() > 0.0001 or _dash_timer > 0.0)


## 主城打坐：连续站立 60 秒入定，之后每 2 秒 +1 修为；任何移动 / 疾行都会打断。
## 打坐只影响表现与修为，不锁移动 —— 玩家一动就自然退出状态。
func _tick_meditation(delta: float, moving: bool) -> void:
	if moving:
		_idle_time = 0.0
		_stop_meditating()
		return
	_idle_time += delta
	if not _meditating and _idle_time >= MEDITATE_IDLE_TIME:
		_start_meditating()
	if not _meditating:
		return
	_meditate_tick_timer += delta
	while _meditate_tick_timer >= MEDITATE_TICK:
		_meditate_tick_timer -= MEDITATE_TICK
		var gained := CharacterData.add_realm_exp(1)
		if gained > 0:
			_show_meditation_float("修为 +%d" % gained, UIKit.C_HUD_MANA)
		_update_meditation_label()


func _start_meditating() -> void:
	if _meditating:
		return
	_meditating = true
	_meditate_tick_timer = 0.0
	_update_meditation_label()
	if _meditation_aura != null:
		_meditation_aura.visible = true
	if _meditation_label != null:
		_meditation_label.visible = true
	_show_meditation_float("入定", Color(0.62, 0.9, 1.0))


func _stop_meditating() -> void:
	if not _meditating:
		return
	_meditating = false
	_meditate_tick_timer = 0.0
	if _meditation_aura != null:
		_meditation_aura.visible = false
	if _meditation_label != null:
		_meditation_label.visible = false


func _update_meditation_label() -> void:
	if _meditation_label == null:
		return
	_meditation_label.text = "打坐中 · 修为已满，需突破" if CharacterData.is_stage_full() \
		else "打坐中 · 每 2 秒 +1 修为"


func _create_meditation_visual() -> void:
	if _meditation_aura == null:
		_meditation_aura = MeditationAura.new()
		_meditation_aura.name = "MeditationAura"
		_meditation_aura.z_index = 1
		_meditation_aura.visible = false
		add_child(_meditation_aura)
	if _meditation_label == null:
		_meditation_label = UIKit.readable_label("", UIKit.F_SMALL, Color(0.68, 0.92, 1.0))
		_meditation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_meditation_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_meditation_label.position = Vector2(-100.0, -122.0)
		_meditation_label.size = Vector2(200.0, 22.0)
		_meditation_label.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.08, 0.9))
		_meditation_label.add_theme_constant_override("outline_size", 3)
		_meditation_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_meditation_label.z_index = 10
		_meditation_label.visible = false
		add_child(_meditation_label)


func _show_meditation_float(text: String, color: Color) -> void:
	var label := UIKit.readable_label(text, 18, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector2(-60.0, -98.0)
	label.size = Vector2(120.0, 24.0)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.08, 0.9))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 11
	add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y - 28.0, 0.9)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.9)
	tween.tween_callback(label.queue_free)


## 打坐光环：脚下一圈缓慢呼吸的水蓝光环（不新增美术资源）
class MeditationAura extends Node2D:
	var _t := 0.0

	func _process(delta: float) -> void:
		if not visible:
			return
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var center := Vector2(0.0, 8.0)
		for i in 2:
			var radius := 34.0 + float(i) * 13.0 + sin(_t * 1.7 + float(i)) * 3.0
			draw_set_transform(center, 0.0, Vector2(1.0, 0.45))
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48,
				Color(0.55, 0.9, 1.0, 0.30 - 0.10 * float(i)), 2.0, true)


func _start_dash(dir: Vector2) -> void:
	# 有方向输入就朝输入方向，否则朝当前面向前冲
	_dash_dir = dir.normalized() if dir.length_squared() > 0.0 else Vector2(_facing_x, 0.0)
	_dash_timer = DASH_TIME
	_dash_cooldown = DASH_COOLDOWN
	_ghost_timer = 0.0
	anim.modulate = Color(1.6, 1.6, 1.6, 1.0)
	_stop_meditating()
	_idle_time = 0.0


func _end_dash() -> void:
	anim.modulate = Color(1.0, 1.0, 1.0, 1.0)


## 冲刺残影：**快照本体当前那帧贴图**，做成纯 Sprite2D（无脚本/无动画/无 process → 百分百静止）
## 与 player.gd 的闪避残影同一口径（2026-10-19 推倒重做：不再复制 Visual 树，避免"残影自己跑"）
func _spawn_ghost() -> void:
	if not is_instance_valid(anim) or skin == null:
		return
	var tex: Texture2D = skin.current_texture()
	if tex == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = tex
	ghost.modulate = Color(1.0, 1.0, 1.0, 0.4)
	get_parent().add_child(ghost)
	# 入树后继承本体渲染节点的世界变换（未入树时 global_* 不生效）
	if skin.render_node is Node2D:
		var rn: Node2D = skin.render_node as Node2D
		ghost.global_position = rn.global_position
		ghost.global_scale = rn.global_scale
		ghost.global_rotation = rn.global_rotation
	else:
		ghost.global_position = anim.global_position
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, GHOST_LIFE)
	tw.tween_callback(ghost.queue_free)


func _update_visual(dir: Vector2) -> void:
	# 行走动画：只有真的在移动才播；静止时停在 idle_frame
	if skin != null:
		skin.set_moving(dir.length_squared() > 0.0)
		skin.set_facing(dir)
	if dir.length_squared() > 0.0 and absf(dir.x) > 0.1:
		_facing_x = 1.0 if dir.x > 0.0 else -1.0
		anim.scale.x = _facing_x
