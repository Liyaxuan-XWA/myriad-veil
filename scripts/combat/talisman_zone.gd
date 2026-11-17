class_name TalismanZone
extends Node2D
## 符箓地面区（2026-11-10）：雷狱 / 潮汐 / 石阵 / 聚光 / 噬灵阵共用同一个节点。
##
## 为什么做成独立节点而不是 player 里的计时器：
##   区域要**留在原地**（玩家会走开），而且同时可能有两三个并存；
##   挂在 player 上就必须自己维护一组坐标 + 剩余时间，反而更容易泄漏。
##
## ⚠ 伤害一律回调 player 的 `_run_tal_hit`（走两仪 / 肉鸽全局乘区那条钩子链），
##   本节点只负责「谁在范围内」与「多久跳一次」。
## ⚠ 视觉仍是程序合成的（圆圈 + 两圈弧 + 六枚元素字），没有专用贴图；
##   颜色一律从 ArtDB.element_color() 传进来，别在本文件写死颜色。
##   换正式美术时只要把 `_draw()` 里那几笔换成 draw_texture_rect 即可，接口不用动。

var _player: Node = null
var _radius := 140.0
var _left := 4.0
var _tick := 1.0
var _acc := 0.0
var _coeff := 0.0
var _mult := 1.0
var _element := ""
var _tag := "damage"
var _slow := 0.0
var _heal_pct := 0.0
var _debuff := ""
var _debuff_chance := 0.0
var _debuff_time := 1.0
var _color := Color(0.82, 0.76, 0.64, 1.0)
var _life := 0.0
## 阵沿上的元素字（雷狱 = 「雷」）：⚠ 之前这里是六个裸矩形，
## 在截图里读成「UI 占位框」，完全不像符阵。
var _rune := ""
var _rune_font: Font = null


## ⚠ 挂进 `talisman_zone` 组：换层 / 退出试炼时靠它一次性清场，
##   否则玩家走出去以后地上还留着上一层的雷狱（节点挂在场景上，不会跟着 player 走）。
func _ready() -> void:
	add_to_group("talisman_zone")


func setup(player: Node, at: Vector2, cfg: Dictionary, mult: float, color: Color) -> void:
	_player = player
	global_position = at
	_radius = float(cfg.get("radius", 140.0))
	_left = float(cfg.get("time", 4.0))
	_life = _left
	_tick = maxf(0.15, float(cfg.get("tick", 1.0)))
	_coeff = float(cfg.get("coeff", 0.0))
	_mult = mult
	_element = String(cfg.get("element", ""))
	_tag = String(cfg.get("tag", "damage"))
	_slow = float(cfg.get("slow", 0.0))
	_heal_pct = float(cfg.get("heal_pct", 0.0))
	_debuff = String(cfg.get("debuff", ""))
	_debuff_chance = float(cfg.get("debuff_chance", 0.0))
	_debuff_time = float(cfg.get("debuff_time", 1.0))
	_color = color
	_rune = String(AttributeDB.ELEMENT_NAMES.get(_element, ""))
	if _rune == "无":
		_rune = ""
	if _rune != "":
		_rune_font = UIKit.readable_font()
	z_index = -1
	queue_redraw()


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		queue_free()
		return
	_left -= delta
	if _left <= 0.0:
		queue_free()
		return
	_acc += delta
	while _acc >= _tick:
		_acc -= _tick
		_tick_once()
	queue_redraw()


func _tick_once() -> void:
	var hits: Array = _player.call("_run_tal_enemies_near", global_position, _radius)
	# 潮汐：自己站在水里才回血（不是全图回）
	if _tag == "regen":
		if global_position.distance_to((_player as Node2D).global_position) <= _radius:
			var max_hp := float(_player.get("max_hp"))
			_player.call("restore_health", max_hp * _heal_pct / 100.0)
	# 石阵：吸收飞进来的敌方弹幕
	if _tag == "absorb":
		for raw in get_tree().get_nodes_in_group("boss_projectile"):
			var p := raw as Node2D
			if p == null or not is_instance_valid(p):
				continue
			if bool(p.get("source_is_ally")):
				continue
			if p.global_position.distance_to(global_position) <= _radius:
				p.queue_free()
	for raw in hits:
		var node: Node = raw
		if _coeff > 0.0:
			var dmg := float(_player.call("_run_tal_spell_attack")) * _coeff * _mult
			_player.call("_run_tal_hit", node, dmg, _element, 0.0)
		if _slow > 0.0 and node.has_method("apply_debuff"):
			node.call("apply_debuff", "array_slow", _tick + 0.5)
		if _debuff != "" and _debuff_chance > 0.0 and randf() <= _debuff_chance:
			if node.has_method("apply_debuff"):
				node.call("apply_debuff", _debuff, _debuff_time)
	# 噬灵阵：阵内每个目标给自己回一点
	if _tag == "drain" and _heal_pct > 0.0 and not hits.is_empty():
		var max_hp := float(_player.get("max_hp"))
		_player.call("restore_health", max_hp * _heal_pct / 100.0 * float(hits.size()))


func _draw() -> void:
	var fade := clampf(_left / maxf(_life, 0.01), 0.0, 1.0)
	# ⚠ 填充不能太淡：地砖是冷灰蓝，0.10 的透明度在截图里几乎看不见（已踩过一次）
	var fill := Color(_color.r, _color.g, _color.b, 0.14 + 0.08 * fade)
	draw_circle(Vector2.ZERO, _radius, fill)
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 48,
		Color(_color.r, _color.g, _color.b, 0.80), 2.5, true)
	draw_arc(Vector2.ZERO, _radius * 0.62, 0.0, TAU, 32,
		Color(_color.r, _color.g, _color.b, 0.42), 1.5, true)
	# 六枚符角：⚠ 原来是「8×14 实心矩形 + 1px 亮边」，实机读成 UI 占位框，
	#   一点不像符纸（截图验证过）。改成元素汉字 + 一圈同色小光晕：
	#   字号 14、贴在阵沿内侧，随剩余时间一起淡出，视觉语言与绕身符文 / 技能栏图标一致。
	if _rune != "" and _rune_font != null:
		var size := 14
		var w := _rune_font.get_string_size(_rune, HORIZONTAL_ALIGNMENT_LEFT,
			-1, size).x
		var ink := Color(1.0, 0.97, 0.88, 0.35 + 0.55 * fade)
		var halo := Color(_color.r, _color.g, _color.b, 0.16 + 0.24 * fade)
		for i in 6:
			var a := TAU * float(i) / 6.0 + _left * 0.6
			var at := Vector2(cos(a), sin(a)) * (_radius - 13.0)
			draw_circle(at, 11.0, halo)
			# draw_string 的 pos 是基线；往上抬 0.35em 才是以 at 为中心
			draw_string(_rune_font, at + Vector2(-w * 0.5, 5.0), _rune,
				HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)
