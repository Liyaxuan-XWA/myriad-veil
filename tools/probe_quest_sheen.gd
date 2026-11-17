extends Node
## 任务卡「斜向流光」不许越出卡面（2026-11-12 用户报：流光超出面板右边）
## 用法：godot --headless --path . res://tools/probe_quest_sheen.tscn -- --no-save
##
## 判据：把光带每条线的两端 x 在 40 个扫掠相位 × 14 条线上全量扫一遍，
## 必须都落在 [CARD_R, w-CARD_R] 之间；同时用**旧公式**跑同一组相位做对照 ——
## 旧公式必须越界，否则这条断言就是恒真的假绿。

const PANEL_SCRIPT := "res://scripts/tutorial/quest_panel.gd"
const W := 300.0

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	print("\n########## 任务卡流光不出界 ##########")
	var qp = load(PANEL_SCRIPT)
	var deco = qp.QuestCardDeco
	var lo := float(qp.CARD_R)
	var hi := W - lo
	var span := float(qp.SHEEN_SPAN)
	var bad := 0
	var old_bad := 0
	for step in 40:
		var cx := lerpf(-0.30 * W, 1.30 * W, float(step) / 39.0)
		for k in 14:
			var kk := float(k) / 13.0
			var seg: Vector2 = deco.sheen_segment(cx, kk, W)
			if seg.x < lo - 0.01 or seg.x > hi + 0.01 \
					or seg.y < lo - 0.01 or seg.y > hi + 0.01:
				bad += 1
			# 旧公式（直接按 cx 画、不夹）用来证明对照组确实会越界
			var old_top := cx + kk * span
			if old_top > hi + 0.01 or old_top < lo - span - 0.01:
				old_bad += 1
	_check(bad == 0, "新公式：40 个相位 × 14 条线的两端都在卡内", "%d 条越界" % bad)
	_check(old_bad > 0, "旧公式在同一组相位确实会越界（断言不是恒真）", "%d 条" % old_bad)
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())
