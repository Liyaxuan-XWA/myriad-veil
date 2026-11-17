extends Node2D
## 指引箭头：目标在屏幕外时画在**玩家脚边**（2026-11-12 用户定）
## 用法：godot --headless --path . res://tools/probe_tutorial_arrow.tscn -- --no-save
##
## 口径：
##   · 目标跑到屏幕外 ⇒ 箭头几何必须以玩家脚下为基准、朝目标方向、且整支在视口内；
##   · 场上没有玩家 ⇒ 几何为空（调用方退回「贴框边指」的老画法）。
## ⚠ 用真实的 TutorialOverlay + 真实 player.tscn，只把「当前步骤」按步骤表的结构合成出来。

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const FAR_POS := Vector2(2600.0, 2000.0)

var _passes := 0
var _fails: Array = []
var _saved_step: Dictionary = {}
var _ov: Node = null
var _player: Node2D = null


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	print("\n########## 指引箭头 · 玩家脚边 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _run() -> void:
	# 场：玩家在屏幕中央，目标节点在视口外（按 path: 锚点能被 _resolve_anchor 找到）
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Node2D
	add_child(_player)
	_player.global_position = Vector2(640.0, 380.0)
	var far := Node2D.new()
	far.name = "FarTarget"
	add_child(far)
	far.global_position = FAR_POS
	await _frames(6)
	_ov = Tutorial.get_node_or_null("TutorialOverlay")
	_check(_ov != null, "取到指引表现层")
	if _ov == null:
		return
	_saved_step = Tutorial.active_step
	Tutorial.active_step = {"id": "__probe_arrow__", "text": "远方的目标",
		"anchor": "path:FarTarget", "manual": true}
	Tutorial.changed.emit()
	await _frames(4)
	_check(bool(_ov.get("_has_target")), "目标的屏幕矩形算出来了（虽然整块在视口外）")
	var target_rect: Rect2 = _ov.get("_target_rect")
	var vp := get_viewport().get_visible_rect()
	_check(not vp.intersects(target_rect), "现场：目标确实在屏幕外", str(target_rect))
	var geo: Dictionary = _ov.call("_feet_arrow_geometry")
	_check(not geo.is_empty(), "脚边箭头几何算得出来")
	_check(bool(_ov.call("_draw_arrow_at_player")), "屏幕外时确实走「脚边箭头」这条绘制分支")
	if not geo.is_empty():
		var base: Vector2 = geo["base"]
		var tip: Vector2 = geo["tip"]
		var xf := (_player as CanvasItem).get_global_transform_with_canvas()
		var feet: Vector2 = xf.origin
		var pr := Rect2(xf.origin - Vector2(20, 60), Vector2(40, 60))
		_check(base.distance_to(feet) < 60.0, "箭头挂在玩家脚边（不是屏幕边缘）",
				"base=%s feet=%s" % [str(base), str(feet)])
		var want: Vector2 = (target_rect.get_center() - (feet + Vector2(0, -34))).normalized()
		_check(((tip - base).normalized()).dot(want) > 0.9, "朝目标方向指",
				"dot=%.2f" % ((tip - base).normalized()).dot(want))
		var all_in := true
		for k in ["base", "tip", "left", "right"]:
			var pt: Vector2 = geo[k]
			if pt.x < 0.0 or pt.y < 0.0 or pt.x > vp.size.x or pt.y > vp.size.y:
				all_in = false
		_check(all_in, "整支箭头都在视口内（不会画到屏幕外）")
	# 没有玩家 ⇒ 几何为空（退回贴框边）
	_player.queue_free()
	await _frames(3)
	_check((_ov.call("_feet_arrow_geometry") as Dictionary).is_empty(),
			"场上没有玩家时不给脚边箭头（退回贴框边指）")
	# 收尾
	Tutorial.active_step = _saved_step
	Tutorial.changed.emit()
	await _frames(2)
	print("")
