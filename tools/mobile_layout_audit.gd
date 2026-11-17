extends SceneTree
## 手机比例下的 UI 布局自检。
##
## 为什么要有这一份：工程是 stretch=canvas_items + aspect=expand，1280×720 只是**下限**。
## 20:9 的手机（2400×1080）逻辑视口 = 1600×720，横边多出 320px；4:3 平板横屏 = 1280×960，
## 竖边多出 240px。凡是拿 1280/720 常量算居中的东西，在非 16:9 的设备上就不落在正中。
## 这个脚本量真实矩形、和「视口正中」做差，出像素数，不靠肉眼猜。
##
## 用法（窗口尺寸就当成手机逻辑尺寸，三种比例各跑一遍）：
##     godot --path . --resolution 1600x720 --script tools/mobile_layout_audit.gd   # 20:9 主流手机
##     godot --path . --resolution 1280x720 --script tools/mobile_layout_audit.gd   # 16:9 基准，偏差应为 0
##     godot --path . --resolution 1280x960 --script tools/mobile_layout_audit.gd   # 4:3 平板横屏

const SETTLE := 5
const PANELS := [
	"forge_panel", "warehouse_panel", "tower_panel", "codex_panel", "guide_panel",
	"skill_panel", "domain_panel", "memory_panel", "realm_panel", "alchemy_panel",
	"talisman_panel", "craft_panel", "insight_panel", "farm_seed_panel", "settings_panel",
]
## 一步一个对象：先主城 HUD，再逐个面板，最后战斗/大世界/标题
var STEPS: Array[String] = []

var _step := -1
var _frame := 0
var _vp := Vector2.ZERO
var _panel = null
var _scene: Node = null
var _done := false
## 截图延后几拍：刚 set 完 enabled 的那一帧 CanvasLayer 还没画，
## 当场截出来是一张没有虚拟键的空景（看着像没生效）
var _snap_later := ""
var _snap_wait := 0


func _initialize() -> void:
	STEPS.append("scene:main/primordial_realm.tscn")
	for p in PANELS:
		STEPS.append("panel:" + p)
	STEPS.append("scene:combat/combat_arena.tscn")
	STEPS.append("scene:world/secret_world.tscn")
	STEPS.append("scene:ui/title_screen.tscn")
	print("\n########## 手机比例 UI 自检 ##########")


func _process(_d: float) -> bool:
	if _done:
		return true
	_frame += 1
	if _snap_wait > 0:
		_snap_wait -= 1
		if _snap_wait == 0:
			_snap(_snap_later)
	if _vp == Vector2.ZERO:
		if _frame < 12:
			return false
		_vp = root.get_visible_rect().size
		print("逻辑视口 = ", _vp, "   相对 16:9 基准：横多 %.0fpx、竖多 %.0fpx"
			% [_vp.x - 1280.0, _vp.y - 720.0])
		_next_step()
		return false
	if _frame % (SETTLE + 5) != 0:
		return false
	if _step >= 0:
		_measure(STEPS[_step])
	_next_step()
	return false


func _next_step() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.close()
		_panel = null
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
		_scene = null
	_step += 1
	if _step >= STEPS.size():
		print("################ 完毕 ################")
		_done = true
		return
	var tag := STEPS[_step]
	if tag.begins_with("panel:"):
		var id := tag.get_slice(":", 1)
		var path := "res://scripts/ui/panels/%s.gd" % id
		if not ResourceLoader.exists(path):
			path = "res://scripts/ui/%s.gd" % id
		if not ResourceLoader.exists(path):
			push_warning("缺文件 " + path)
			return
		var sc = load(path)
		var p = sc.new()
		root.add_child(p)
		_panel = p
		p.open()
		# open() 会暂停整棵树；立刻恢复，这里量的是布局不是玩法
		paused = false
	elif tag.begins_with("scene:"):
		var s = load("res://scenes/" + tag.get_slice(":", 1))
		_scene = s.instantiate()
		root.add_child(_scene)


func _measure(tag: String) -> void:
	# 虚拟键体检放在 HUD 收集之前：headless 下场景 HUD 可能一个都没抓到，
	# 那条 return 会把按键这段一起跳过（跑过一次才发现日志里根本没有 PAD 行）
	if tag.contains("primordial_realm"):
		_audit_pad("realm")
	elif tag.contains("combat_arena"):
		_audit_pad("combat")
	if tag.begins_with("panel:"):
		if _panel == null or not is_instance_valid(_panel):
			return
		var r: Control = _panel._root
		if r == null:
			return
		var rc := r.get_global_rect()
		var des: Vector2 = _panel.panel_size()
		var want_x := (_vp.x - des.x) * 0.5
		var want_y := (_vp.y - des.y) * 0.5
		print("  %-20s 设计 %s  实得 x=%.0f y=%.0f  真居中 x=%.0f y=%.0f  → 偏 (%+.0f, %+.0f)px"
			% [tag, des, rc.position.x, rc.position.y, want_x, want_y,
				rc.position.x - want_x, rc.position.y - want_y])
		_defer_snap(tag)
		return
	var boxes := _hud_boxes()
	if boxes.is_empty():
		print("[%s] 没抓到 HUD 控件" % tag)
		_defer_snap(tag)
		return
	var u: Rect2 = boxes[0]["rect"]
	for it in boxes:
		u = u.merge(it["rect"])
	print("[%s] %d 个 HUD 可交互控件并集 = %s" % [tag, boxes.size(), u])
	print("      四边空隙 左 %.0f 上 %.0f 右 %.0f 下 %.0f" % [u.position.x, u.position.y, _vp.x - u.end.x, _vp.y - u.end.y])
	# 逐个列贴边元素：这些是靠常量摆到「假右边缘」的，手机上会离右边空一截
	for it in boxes:
		var rc: Rect2 = it["rect"]
		if rc.size.x <= 1.0 or rc.size.y <= 1.0:
			continue
		if rc.end.x > 1150.0 or rc.end.y > 620.0:
			print("        %-26s %s  距真实右/下边 %.0f / %.0f px"
				% [it["node"], rc, _vp.x - rc.end.x, _vp.y - rc.end.y])
	_defer_snap(tag)


## 触屏虚拟键命中体检：① 最小命中直径 64 ② 两两不重叠 ③ 都在安全区内
## 摇杆的命中圈按放宽后的半径算，所以它和功法列是「贴边」的高危对。
func _audit_pad(ctx: String) -> void:
	var pad = root.get_node_or_null("/root/VirtualPad")
	if pad == null:
		return
	var consts: Dictionary = pad.get_script().get_script_constant_map()
	var btn_slack: float = float(consts.get("BUTTON_HIT_SLACK", 1.15))
	var stick_slack: float = float(consts.get("STICK_HIT_SLACK", 1.25))
	pad.set("enabled", true)
	pad.call("_apply_enabled")
	pad.call("set_context", ctx)
	pad.call("_apply_layout")
	var safe: Rect2 = pad.call("_safe_rect")
	var items: Array = []
	var btns: Dictionary = pad.get("_buttons")
	for id in btns.keys():
		var b: Control = btns[id]
		if not b.visible:
			continue
		var hr: float = b.radius * btn_slack
		items.append({"n": String(b.get("label")), "c": b.position
				+ Vector2(b.radius, b.radius), "r": hr})
	var st: Control = pad.get("_stick")
	if st.visible:
		var shr: float = st.radius * stick_slack
		items.append({"n": "摇杆", "c": st.position + st.size * 0.5, "r": shr})
	var zone: Rect2 = pad.call("_stick_zone_rect")
	print("      摇杆召唤区 = %s   安全区 = %s" % [zone, safe])
	# 召唤区会吞掉落在里面的鼠标事件（合成触摸的闸门），
	# 所以场景里任何「可点控件」压进这块就是点不到 —— 逐个列出来，不靠肉眼猜
	var eaten: Array = []
	var probed := _hud_boxes()
	for it in probed:
		var rc: Rect2 = it["rect"]
		if rc.size.x <= 1.0 or rc.size.y <= 1.0:
			continue
		if zone.intersects(rc):
			eaten.append(it)
	for it in eaten:
		print("        PAD 吃掉：摇杆区压住可点控件 %s %s" % [it["node"], it["rect"]])
	if probed.is_empty():
		# 主城 / 战斗这两步在本工具里经常一个控件都抓不到（面板那步能抓到）。
		# 抓不到就说抓不到，不能顺势打印一句「没有压到」——那是假证据。
		print("        摇杆区压没压到 UI：本步没抓到场景 HUD（0 个控件），不构成证据")
	elif eaten.is_empty():
		print("        摇杆区没有压到任何可点控件（%d 个控件里）" % probed.size())
	var bad := 0
	for it in items:
		var side: float = float(it["r"]) * 2.0
		if side < 64.0:
			print("        PAD 短：%s 命中直径 %.0f < 64" % [it["n"], side])
			bad += 1
		var c: Vector2 = it["c"]
		var r: float = it["r"]
		var rc := Rect2(c - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
		if not safe.grow(1.0).encloses(rc):
			print("        PAD 越界：%s %s 不在安全区里" % [it["n"], rc])
			bad += 1
	for i in range(items.size()):
		for k in range(i + 1, items.size()):
			var a: Vector2 = items[i]["c"]
			var b2: Vector2 = items[k]["c"]
			var need: float = float(items[i]["r"]) + float(items[k]["r"])
			if a.distance_to(b2) < need:
				print("        PAD 重叠：%s × %s 圆心距 %.0f < %.0f"
					% [items[i]["n"], items[k]["n"], a.distance_to(b2), need])
				bad += 1
	print("      虚拟键命中体检（%s 组）：%d 项，问题 %d" % [ctx, items.size(), bad])


## 截图落在**每一步量完之后**：主城 / 战斗那两步要先等 `_audit_pad` 把虚拟键打开，
## 否则截到的是一张没有按键的空景，等于没审。
func _defer_snap(tag: String) -> void:
	_snap_later = tag
	_snap_wait = SETTLE


func _snap(tag: String) -> void:
	var img := root.get_texture().get_image()
	if img == null:
		return
	img.save_png("res://output/mobile_%s.png" % tag.replace(":", "_").replace("/", "-"))


## HUD = 场景树里所有可见的可交互 Control（世界里的 Node2D 与视口无关，不参与）
func _hud_boxes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_collect(root, out)
	return out


func _collect(n: Node, out: Array[Dictionary]) -> void:
	for c in n.get_children():
		# ⚠ CanvasLayer 不是 CanvasItem：以前这里一句 `not (c is CanvasItem)` 就把整层 HUD
		#   跳过了，主城 / 战斗两步永远报「没抓到 HUD 控件」，量到的其实只有世界空间那些
		#   血条。面板层、战斗 HUD 全在 CanvasLayer 底下，必须跟着往下走。
		if c is CanvasLayer:
			_collect(c, out)
			continue
		if not (c is CanvasItem) or not (c as CanvasItem).visible:
			continue
		if c is Control and (c as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			var owner := String(c.name)
			var p = c.get_parent()
			if p != null:
				owner = String(p.name) + "/" + owner
			out.append({"node": owner, "rect": (c as Control).get_global_rect()})
		_collect(c, out)
