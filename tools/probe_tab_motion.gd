extends Node
## 页签「可按」起伏自检（2026-11-12 用户改口径）
## 用法：godot --headless --path . res://tools/probe_tab_motion.tscn -- --no-save
##
## 口径：**未选中**的页签轻轻起伏（1.00 ↔ 1.02），选中后落定不动；
## 没有闪光/光扫/呼吸那一套。面板打开时整棵树是暂停的，所以这里同样在暂停树里取样 ——
## Tween 不设 PAUSE_PROCESS 的话在面板里是死的。

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
	print("\n########## 页签 · 可按起伏 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	get_tree().paused = false
	get_tree().quit(_fails.size())


func _run() -> void:
	get_tree().paused = true
	var b := UIKit.tab_button("未选中", Vector2(150.0, 34.0))
	add_child(b)
	await get_tree().process_frame
	await get_tree().process_frame
	# ===== 1. 未选中：在起伏（而且只往上抬） =====
	var s0: Vector2 = b.scale
	await get_tree().create_timer(0.5).timeout
	var s1: Vector2 = b.scale
	_check(absf(s1.x - 1.0) > 0.002 and s1.x > 1.0, "未选中的页签在起伏（>1.0，往上抬）",
			"%.3f → %.3f" % [s0.x, s1.x])
	_check(s1.x <= 1.021, "幅度收着（不超过 1.02）", "%.3f" % s1.x)
	_check(not b.has_method("_start_sheen") and b.get("_sheen") == null,
			"旧的闪光/光扫节点已经删干净")
	# ===== 2. 选中：落定不起伏 =====
	UIKit.set_tab_selected(b, true)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(b.scale.is_equal_approx(Vector2.ONE), "选中后立刻复位到 1.0", str(b.scale))
	await get_tree().create_timer(0.4).timeout
	_check(b.scale.is_equal_approx(Vector2.ONE), "选中后不再动", str(b.scale))
	# ===== 3. 切回未选中：又开始起伏 =====
	UIKit.set_tab_selected(b, false)
	await get_tree().create_timer(0.5).timeout
	_check(b.scale.x > 1.0 + 0.002, "取消选中后重新起伏", "%.3f" % b.scale.x)

	# ===== 4. 真实面板里也在动（暂停树 + 面板自己的 tab） =====
	var panel = (load("res://scripts/ui/panels/domain_panel.gd") as GDScript).new()
	get_tree().root.add_child.call_deferred(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	var world_btn: Button = panel.get("_tab_world")
	_check(world_btn != null, "万界秘境页签拿到")
	if world_btn != null:
		UIKit.set_tab_selected(world_btn, false)
		# ⚠ 必须比较「暂停之后两次取样」：只判 >1.0 会在「冻结在抬升中途」时假绿
		await get_tree().create_timer(0.25).timeout
		var m0: float = world_btn.scale.x
		await get_tree().create_timer(0.5).timeout
		var m1: float = world_btn.scale.x
		_check(absf(m1 - m0) > 0.001, "面板（暂停树）里未选中的页签也在起伏",
				"%.3f → %.3f" % [m0, m1])
	panel.close()
	await get_tree().process_frame
	print("")
