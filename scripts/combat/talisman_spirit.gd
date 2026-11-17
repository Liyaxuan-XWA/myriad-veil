class_name TalismanSpirit
extends Node2D
## 符灵（2026-11-10）：木缚符变体「符灵·青藤」召出来的小符纸精灵。
##
## 职责很窄：每 `interval` 秒找最近的敌人，束缚 `root` 秒并打一记法术伤害。
## 不移动、不挡弹幕、不会被打死 —— 现阶段它就是一个「持续输出 + 控制」的图腾，
## 避免把召唤物做成第二套 AI（那会让这张卡的强度失控，也拖慢战斗结算）。
##
## ⚠ 2026-11-10 换成**真符纸**：原来 `_draw` 画的是「绿框 + 三道横线」，
##   截图里读成 UI 占位框，完全不像召唤物。现在直接画 ArtDB 的卡面贴图
##   （按元素取，十张都有），仍然是程序合成的外晕 + 呼吸，正式美术替换只改 ArtDB。

var _player: Node = null
var _left := 12.0
var _life := 12.0
var _interval := 2.0
var _acc := 0.0
var _coeff := 0.5
var _mult := 1.0
var _root := 1.0
var _element := "wood"
var _color := Color(0.56, 0.86, 0.58, 1.0)
var _bob := 0.0
var _card: Texture2D = null


## ⚠ 挂进 `talisman_spirit` 组：退出试炼 / 换层时一次性清场用（见 player._run_tal_clear_summons）
func _ready() -> void:
	add_to_group("talisman_spirit")


func setup(player: Node, at: Vector2, cfg: Dictionary, mult: float, color: Color) -> void:
	_player = player
	global_position = at
	_left = float(cfg.get("time", 12.0))
	_life = _left
	_interval = maxf(0.4, float(cfg.get("interval", 2.0)))
	_coeff = float(cfg.get("coeff", 0.5))
	_mult = mult
	_root = float(cfg.get("root", 1.0))
	_element = String(cfg.get("element", "wood"))
	_color = color
	var card_path := ArtDB.element_card(_element)
	if card_path != "":
		_card = load(card_path) as Texture2D
	queue_redraw()


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		queue_free()
		return
	_left -= delta
	if _left <= 0.0:
		queue_free()
		return
	_bob += delta
	_acc += delta
	while _acc >= _interval:
		_acc -= _interval
		_strike()
	queue_redraw()


func _strike() -> void:
	var best: Node = null
	var best_d := 460.0
	for raw in _player.call("_run_tal_enemies_near", global_position, 460.0):
		var d := (raw as Node2D).global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = raw
	if best == null:
		return
	if best.has_method("apply_debuff"):
		best.call("apply_debuff", "rooted", _root)
	var dmg := float(_player.call("_run_tal_spell_attack")) * _coeff * _mult
	_player.call("_run_tal_hit", best, dmg, _element, 0.0)


func _draw() -> void:
	var fade := clampf(_left / maxf(_life, 0.01), 0.0, 1.0)
	var bob := sin(_bob * 3.0) * 3.0
	# 外晕：先铺一圈软光，符纸才不会糊在暗色地砖上看不见
	draw_circle(Vector2(0.0, bob), 26.0 + 2.0 * sin(_bob * 2.0),
		Color(_color.r, _color.g, _color.b, 0.10 + 0.06 * fade))
	draw_circle(Vector2(0.0, bob), 17.0,
		Color(_color.r, _color.g, _color.b, 0.12 + 0.08 * fade))
	# 符纸本体：32×48 与卡面 640×960 同为 2:3，不会被拉扁
	var rect := Rect2(Vector2(-16.0, -24.0 + bob), Vector2(32.0, 48.0))
	if _card != null:
		# 轻轻左右摇，像悬在半空被风吹着；draw_set_transform 用完必须复位，
		# 否则后面的弧线会跟着一起转（这函数影响后续所有 draw_* 调用）。
		draw_set_transform(Vector2(0.0, bob), sin(_bob * 1.7) * 0.09, Vector2.ONE)
		draw_texture_rect(_card, Rect2(Vector2(-16.0, -24.0), Vector2(32.0, 48.0)), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		# 贴图缺失时的兜底：一张素符纸轮廓，保证游戏不空白也不报错
		draw_rect(rect, Color(_color.r, _color.g, _color.b, 0.34 + 0.20 * fade))
		draw_rect(rect, Color(_color.r, _color.g, _color.b, 0.92), false, 2.0)
		for i in 3:
			var y := rect.position.y + 9.0 + float(i) * 10.0
			draw_line(Vector2(rect.position.x + 6.0, y), Vector2(rect.end.x - 6.0, y),
				Color(_color.r, _color.g, _color.b, 0.85), 1.5)
	draw_arc(Vector2(0.0, bob), 28.0 + 2.0 * sin(_bob * 2.0), 0.0, TAU, 24,
		Color(_color.r, _color.g, _color.b, 0.30), 1.5, true)
