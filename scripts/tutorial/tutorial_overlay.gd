extends CanvasLayer
## 新手指引 · 表现层（由 Tutorial 自动创建，不要手动挂到场景里）
##
## 画三样东西：
##   1. 聚光遮罩 + 箭头 + 说明卡（**不拦鼠标**：点别处 = 本步暂缓）
##   2. 暂停喂招卡（战斗教学专用，按右键继续）
##   3. 红点 + 吐司
##
## ⚠ 2026-11-11 用户定：左侧旧「教学清单」已重置成顺序任务面板（quest_panel.gd，
##   由 Quest autoload 自建自管）——教学步骤只靠聚光 + 说明卡带路。
##
## ⚠ 美术后置（用户铁律）：这里的压暗、边框、箭头全是程序绘制的占位，
##   正式素材到位后只需要把 `_draw_*` 里换成 TextureRect，调用点不动。
##   配色只取 UIKit.C_*，🚫 不要写死颜色。

const DIM := Color(0.0, 0.0, 0.0, 0.42)

var _spot: Control = null
var _card: PanelContainer = null
var _card_label: Label = null
var _card_tip: Label = null
var _card_skip: Button = null
var _card_pass_rect := Rect2()
var _card_ok: Button = null

var _pause_box: PanelContainer = null
var _pause_label: Label = null

## 红点：btn 实例 id → Label（"●" 红色，压在按钮右上角）
var _badge_dots: Dictionary = {}
## 吐司：右侧竖排，最多 3 条，点一条直达
var _toast_box: VBoxContainer = null
var _toasts: Array = []

var _target_rect := Rect2()
var _has_target := false
## 当前聚光的目标节点（Control 或 Node2D）。
## ⚠ 必须留引用：世界设施/面板按钮会动，_process 里要按它每帧重取矩形，
##   只存 Rect2 的话目标一动聚光就留在原地。
var _target_node: Node = null
## 锚点重试计时：目标可能在本步开始**之后**才创建（感悟面板击杀后才弹、
## 掉落物结算时才生成）。还没扫到就每 0.5 秒重扫一次，扫到即聚光；
## 扫不到保持「降级出卡片」，绝不卡流程（设计案 3.1 硬要求）。
var _anchor_retry := 0.0
const ANCHOR_RETRY_INTERVAL := 0.5
## 上一次看到的当前场景（SceneTree 无「当前场景变了」信号 → 自己比对引用）
var _seen_scene: Node = null
## 上一次看到的模态界面层数：界面一开一关都要重算「这一屏该不该露脸」
var _seen_modal_depth := -1


func _ready() -> void:
	layer = 120                        # 压在 HUD(默认 0~10) 与系统面板(20+) 之上
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	Tutorial.changed.connect(_refresh_card)
	Tutorial.step_started.connect(_on_step_started)


# ===================== 构建 =====================

func _build() -> void:
	# ⚠ 聚光必须先建（画在最底层）：后建的兄弟节点画在它上面，
	#   否则压暗遮罩会把「新手引导清单」和说明卡一起压黑，字看不清。
	_spot = Control.new()
	_spot.name = "TutSpot"
	_spot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ⚠ CanvasLayer 下的 Control 不能靠 anchor 撑满（会算成 1280×1280），显式给尺寸
	_spot.position = Vector2.ZERO
	_spot.size = get_viewport().get_visible_rect().size
	_spot.draw.connect(_draw_spot)
	add_child(_spot)

	# 聚光画在最底层（见上方注释）；旧「教学清单」已由 quest_panel.gd 接管

	# 说明卡：贴在目标下方；没有目标时固定在屏幕下方
	_card = PanelContainer.new()
	_card.name = "TutCard"
	_card.custom_minimum_size = Vector2(360.0, 0.0)
	var csb := UIKit.accent_card_style(UIKit.C_ACCENT, 0.85, 0.35, 8)
	csb.bg_color = Color(0.070, 0.064, 0.055, 0.96)
	_card.add_theme_stylebox_override("panel", csb)
	_card.visible = false
	add_child(_card)

	var cpad := MarginContainer.new()
	cpad.add_theme_constant_override("margin_left", 14)
	cpad.add_theme_constant_override("margin_right", 12)
	cpad.add_theme_constant_override("margin_top", 10)
	cpad.add_theme_constant_override("margin_bottom", 10)
	_card.add_child(cpad)
	var ccol := UIKit.vbox(6)
	cpad.add_child(ccol)
	_card_label = UIKit.label("", UIKit.F_BODY, UIKit.C_TITLE)
	_card_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_label.custom_minimum_size = Vector2(330.0, 0.0)
	ccol.add_child(_card_label)
	_card_tip = UIKit.label("", UIKit.F_SMALL, UIKit.C_TEXT_DIM)
	_card_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_tip.custom_minimum_size = Vector2(330.0, 0.0)
	ccol.add_child(_card_tip)
	var crow := UIKit.hbox(8)
	ccol.add_child(crow)
	_card_ok = UIKit.paper_button("知道了", Vector2(88.0, 26.0))
	_card_ok.add_theme_font_size_override("font_size", UIKit.F_SMALL)
	_card_ok.pressed.connect(func() -> void: Tutorial.complete_current())
	crow.add_child(_card_ok)
	_card_skip = UIKit.button("跳过此步", Vector2(88.0, 26.0))
	_card_skip.add_theme_font_size_override("font_size", UIKit.F_SMALL)
	_card_skip.pressed.connect(func() -> void: Tutorial.skip_step())
	crow.add_child(_card_skip)

	# 暂停喂招卡：屏幕正中偏上，只留一个提示（按键由 _input 接）
	_pause_box = PanelContainer.new()
	_pause_box.name = "TutPause"
	_pause_box.custom_minimum_size = Vector2(420.0, 0.0)
	var psb := UIKit.accent_card_style(UIKit.C_WARN, 0.95, 0.45, 10)
	psb.bg_color = Color(0.10, 0.055, 0.045, 0.97)
	_pause_box.add_theme_stylebox_override("panel", psb)
	_pause_box.visible = false
	add_child(_pause_box)
	var ppad := MarginContainer.new()
	ppad.add_theme_constant_override("margin_left", 20)
	ppad.add_theme_constant_override("margin_right", 20)
	ppad.add_theme_constant_override("margin_top", 16)
	ppad.add_theme_constant_override("margin_bottom", 16)
	_pause_box.add_child(ppad)
	var pcol := UIKit.vbox(8)
	ppad.add_child(pcol)
	_pause_label = UIKit.label("", UIKit.F_SUBTITLE, UIKit.C_TITLE)
	_pause_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pause_label.custom_minimum_size = Vector2(378.0, 0.0)
	_pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pcol.add_child(_pause_label)
	# 触屏没有右键也没有 ESC：这里必须说手上那颗键，不然玩家照着提示按不出来
	# （2026-11-13 用户报：手游在教学里喊「按右键弹开」，点「弹」没反应卡死那一步）
	var touch_pad := VirtualPad.is_touch_enabled()
	var phint := UIKit.label(
		"点「弹」键弹刀 · 点「返回」跳过此步" if touch_pad else "右键弹刀 · ESC 跳过此步",
		UIKit.F_SMALL, UIKit.C_TEXT_DIM)
	phint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pcol.add_child(phint)

	# 吐司容器：右侧中部竖排（只在非战斗场景出现）
	_toast_box = UIKit.vbox(6)
	_toast_box.name = "TutToasts"
	_toast_box.position = Vector2(1280.0 - 292.0, 300.0)
	_toast_box.custom_minimum_size = Vector2(280.0, 0.0)
	add_child(_toast_box)


# ===================== 红点 / 吐司 =====================

func attach_badge(btn: Control, _kind: String) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	_prune_badge_dots()
	var key := btn.get_instance_id()
	if _badge_dots.has(key):
		return
	var dot := UIKit.label("●", UIKit.F_SECTION, Color(0.94, 0.28, 0.24, 1.0))
	dot.name = "TutDot"
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.position = Vector2(btn.size.x - 12.0, -6.0)
	dot.visible = false
	btn.add_child(dot)
	_badge_dots[key] = dot


## 红点是按钮的子节点，按钮释放时红点跟着没了，但表里的键还悬着
## （实例 id 复用会让新按钮误判「已经挂过」）→ 这类死键要清掉
func _prune_badge_dots() -> void:
	var dead: Array = []
	for k in _badge_dots:
		var d: Variant = _badge_dots[k]
		if d == null or not is_instance_valid(d):
			dead.append(k)
	for k in dead:
		_badge_dots.erase(k)


func set_badge(btn: Control, count: int) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	var key := btn.get_instance_id()
	var raw_dot: Variant = _badge_dots.get(key)
	if raw_dot == null or not is_instance_valid(raw_dot):
		# 记录丢了（按钮重建 / 场景重进）→ 就地补挂，别让红点永久消失
		_badge_dots.erase(key)
		attach_badge(btn, "")
		raw_dot = _badge_dots.get(key)
		if raw_dot == null or not is_instance_valid(raw_dot):
			return
	var dot: Label = raw_dot as Label
	dot.visible = count > 0
	# 位置每帧可能变（按钮重建 / 布局调整），顺手对一次
	dot.position = Vector2(maxf(btn.size.x - 12.0, 0.0), -6.0)


func push_toast(text: String, kind: String) -> void:
	# 最多 3 条，旧的先走
	while _toasts.size() >= 3:
		var old: Control = _toasts.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var card := PanelContainer.new()
	var sb := UIKit.accent_card_style(UIKit.C_ACCENT, 0.9, 0.3, 6)
	sb.bg_color = Color(0.075, 0.068, 0.058, 0.96)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(280.0, 0.0)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	card.add_child(pad)
	var col := UIKit.vbox(2)
	pad.add_child(col)
	var line := UIKit.label(text, UIKit.F_SMALL, UIKit.C_TEXT)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(line)
	col.add_child(UIKit.label("点这里去看看", UIKit.F_BADGE, UIKit.C_ACCENT))
	# 整条可点（用 Button 包一层会丢样式，这里用 gui_input 自己接）
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			Tutorial.toast_clicked.emit(kind)
			_drop_toast(card))
	_toast_box.add_child(card)
	_toasts.append(card)
	# 5 秒后自动收
	var t := get_tree().create_timer(5.0, true, false, true)
	t.timeout.connect(func() -> void: _drop_toast(card))


func _drop_toast(card: Control) -> void:
	if not is_instance_valid(card):
		return
	_toasts.erase(card)
	card.queue_free()


# ===================== 聚光刷新入口 =====================

func _on_step_started(_step: Dictionary) -> void:
	_refresh_card()


# ===================== 说明卡 + 聚光 =====================

## 这一屏该不该露指引（2026-11-12 用户定「进入无关界面时当前指引要消失」）：
##   · 没有模态界面 ⇒ 露（照旧看场景）
##   · 有模态界面   ⇒ **只有锚点落在最上层那个界面里**才露；锚点不在 / 本步没锚点 ⇒ 藏
## 藏的时候步骤照样挂着（不判完成），关掉界面或回到相关场景会自己再出来。
func _guide_context_ok(target: Node) -> bool:
	if not GameState.modal_ui_open():
		return true
	var top := GameState.top_modal()
	if top == null:
		# 计数和栈不同步（历史调用点没传节点）：按老规矩放行，宁可见错也不要藏死
		return true
	if target == null or not is_instance_valid(target):
		return false
	return target == top or top.is_ancestor_of(target)


func _refresh_card() -> void:
	# 标题 / 入口界面整块藏掉（与任务面板同根因：autoload UI 跨场景常驻；
	# 玩家在教学中从战斗退回开始界面时，说明卡/聚光会跟着飘到标题上）。
	if not GameState.in_game_world():
		_hide_guide()
		return
	if Tutorial.active_step.is_empty() or not Tutorial.step_visible():
		# 空步、或这一步的 need 当前没满足（例：「三选一里挑一张」要等三选一面板开着）
		# → 整张先藏，序列照旧占位，条件再满足时由 Tutorial.changed 叫回来。
		_hide_guide()
		return
	var step: Dictionary = Tutorial.active_step
	# 触屏没有键盘：写了「按右键」的步子给一句 text_touch，PC 仍读 text
	var text_key := "text_touch" if VirtualPad.is_touch_enabled() else "text"
	_card_label.text = String(step.get(text_key, step.get("text", "")))
	var tip := String(step.get("tip", ""))
	_card_tip.text = tip
	_card_tip.visible = tip != ""
	_card_ok.visible = bool(step.get("manual", false))
	_card_skip.visible = not bool(step.get("manual", false))

	var anchor := String(step.get("anchor", ""))
	var target := _resolve_anchor(anchor)
	# 界面遮挡（2026-11-12 用户定）：开着一个「无关界面」时当前指引必须消失，
	# 回到它所属的界面（或关掉那个界面）再出来；只有完成 / 跳过才永久消失。
	if not _guide_context_ok(target):
		_hide_guide()
		return
	# 界内指引（2026-11-12 用户定）：锚点找不到 = 它所属的界面关了 / 场景换了 →
	# 暂时整块消失；锚点再出现（重新打开那个界面 / 回到那个场景）就自己回来。
	# ⚠ 只有锚点写空（纯说明步）才降级成「没有聚光的卡片」，设计案 3.1 的兜底只留这一种。
	if anchor != "" and (target == null or _rect_of(target).size == Vector2.ZERO):
		_hide_guide()
		return
	_target_node = target
	_update_target_rect()
	# 以「算得出矩形」为准，而不是「找得到节点」：控件隐藏时不该画一个空框
	_has_target = _target_rect.size != Vector2.ZERO
	_place_card()
	# ⚠ 暂停喂招期间必须藏卡片：pause_prompt() 会触发 changed → 走到这里把 _card 又打开，
	#   结果说明卡和暂停卡叠在一起（2026-11-10 截图里抓到过）。
	if Tutorial.is_pause_prompt():
		_card.visible = false
		_card_pass_rect = Rect2()
		_sync_pad_pass()
	_spot.queue_redraw()


## 整块收起：卡片、聚光、目标引用一起清（步骤本身不动，事件/状态照样能把它做完）
func _hide_guide() -> void:
	_card.visible = false
	_card_pass_rect = Rect2()
	_sync_pad_pass()
	_has_target = false
	_target_node = null
	_target_rect = Rect2()
	_spot.queue_redraw()


## 从目标节点算屏幕矩形（聚光画在 CanvasLayer 上，用的是屏幕坐标）
func _update_target_rect() -> void:
	_target_rect = _rect_of(_target_node)


## ⚠ 世界设施是 Area2D 而不是 Control：`node as Control` 恒为 null，
##   曾经导致所有 `path:Facilities/...` 锚点静默降级成「没有聚光」。
##   这里同时吃 Control（UI 控件）与 CanvasItem（世界里的 Node2D / Area2D）。
func _rect_of(node: Node) -> Rect2:
	if node == null or not is_instance_valid(node):
		return Rect2()
	if node is Control:
		var c := node as Control
		if not c.is_visible_in_tree():
			return Rect2()
		return c.get_global_rect()
	if node is CanvasItem:
		return _node2d_rect(node as CanvasItem)
	return Rect2()


## Node2D → 屏幕矩形：用 with_canvas 变换（自动吃到摄像机），尺寸取碰撞体包围盒
func _node2d_rect(ci: CanvasItem) -> Rect2:
	var xf := ci.get_global_transform_with_canvas()
	var z := maxf(absf(xf.get_scale().x), 0.001)
	var half := _node2d_half_size(ci) * z
	return Rect2(xf.origin - half, half * 2.0)


## 碰撞体给的尺寸最准（设施 120×80）；没有碰撞体就按默认框，宁可粗一点
func _node2d_half_size(node: Node) -> Vector2:
	var best := Vector2.ZERO
	for c in node.get_children():
		if not (c is CollisionShape2D):
			continue
		var sh: Shape2D = (c as CollisionShape2D).shape
		var sz := Vector2.ZERO
		if sh is RectangleShape2D:
			sz = (sh as RectangleShape2D).size
		elif sh is CircleShape2D:
			sz = Vector2.ONE * ((sh as CircleShape2D).radius * 2.0)
		elif sh is CapsuleShape2D:
			var cap := sh as CapsuleShape2D
			sz = Vector2(cap.radius * 2.0, cap.height)
		best = best.max(sz)
	if best == Vector2.ZERO:
		best = Vector2(96.0, 64.0)
	return best * 0.5


## 锚点解析：meta 优先，其次场景节点路径
## ⚠ 找不到返回 null 不算错：步骤照样挂着、事件照样能做完（表里 33 步不保证每个锚点都在）。
##   浮层对「有锚点但找不到」的处理是**整块暂时藏起来**（见 _refresh_card），
##   不是降级成一张没有聚光的卡片 —— 后者会在无关界面上飘着（2026-11-12 用户报）。
func _resolve_anchor(spec: String) -> Node:
	if spec == "":
		return null
	if spec.begins_with("path:"):
		var p := spec.trim_prefix("path:")
		var scene := get_tree().current_scene
		if scene != null:
			var n := scene.get_node_or_null(p)
			if n != null:
				return n
		# ⚠ 截图 / 调试脚本里主场景不是 current_scene（手动 add_child 进来的），
		#   这时按「路径后缀」全树兜底，否则聚光会静默消失
		return _find_path_suffix(get_tree().root, p, 0)
	if spec.begins_with("meta:"):
		var key := spec.trim_prefix("meta:")
		# ⚠ 2026-11-12 去掉了「具体控件找不到就圈整个面板」的兜底：那个兜底会让
		#   **已经关掉的那个界面**的指引，在另一块面板上重新露脸（截图里「去制符台」
		#   浮在棋坛长卷上）。现在找不到就是 null，由 _refresh_card 整块藏起来。
		return _find_meta(get_tree().root, key, 0)
	return null


func _find_meta(node: Node, key: String, depth: int) -> Node:
	if depth > 12:
		return null
	# ⚠ 世界里的设施 / 灵田是 Node2D / Area2D，不是 Control：
	#   只认 Control 的话这些 meta 锚点永远匹配不到，会静默降级成「圈整个面板」。
	if node is CanvasItem and (node as CanvasItem).is_visible_in_tree() \
			and String(node.get_meta("tut", "")) == key:
		return node
	for c in node.get_children():
		var hit := _find_meta(c, key, depth + 1)
		if hit != null:
			return hit
	return null


## 按「路径后缀」找节点：`Facilities/DomainGate` 能匹配 `/root/xxx/Facilities/DomainGate`
func _find_path_suffix(node: Node, p: String, depth: int) -> Node:
	if depth > 16:
		return null
	if node is CanvasItem and String(node.get_path()).ends_with("/" + p):
		return node
	for c in node.get_children():
		var hit := _find_path_suffix(c, p, depth + 1)
		if hit != null:
			return hit
	return null


func _place_card() -> void:
	var vp := get_viewport().get_visible_rect().size
	_card.visible = true
	_card.reset_size()
	var sz := _card.get_combined_minimum_size()
	if _has_target:
		# ⚠ 用屏幕上真正画出来的框（_spot_frame），不是目标原始矩形：
		#   目标在屏幕外时原始矩形可能整块在视口外，照它摆卡片会盖在收边后的框上。
		var vis := _spot_frame()
		var x := clampf(vis.get_center().x - sz.x * 0.5,
			12.0, vp.x - sz.x - 12.0)
		var y := vis.end.y + 16.0
		if y + sz.y > vp.y - 12.0:
			y = vis.position.y - sz.y - 16.0
		_card.position = Vector2(x, clampf(y, 12.0, vp.y - sz.y - 12.0))
	else:
		_card.position = Vector2((vp.x - sz.x) * 0.5, vp.y - sz.y - 96.0)
	_card_pass_rect = Rect2(_card.position, sz)
	_sync_pad_pass()


## 说明卡画在虚拟键**上面**（本层 120 > VirtualPad 的 90），所以它整块矩形
## 要报给 VirtualPad 让路 —— 否则卡片底部（尤其「知道了」）落在摇杆召唤区里，
## 手游一点就被摇杆认领，按钮永远点不着（2026-11-13 用户报）。
func _sync_pad_pass() -> void:
	if not VirtualPad.is_touch_enabled():
		return
	if _card.visible and _card_pass_rect.size.x > 0.0:
		VirtualPad.set_pass_rects([_card_pass_rect])
	else:
		VirtualPad.set_pass_rects([])


func _draw_spot() -> void:
	var vp := get_viewport().get_visible_rect().size
	if not _has_target or _target_rect.size == Vector2.ZERO:
		return
	var raw := _target_rect.grow(6.0)
	var r := _spot_frame()
	# 目标有一部分在屏幕外（回城时万界塔正好在屏幕上边缘外）：
	# 框已经收到视口里，箭头改成贴框外侧、指向真正的目标方向
	var off := r.position.distance_to(raw.position) > 0.5
	var accent: Color = UIKit.C_ACCENT
	# ⚠ 目标本身就占了屏幕一大半（兜底圈的整个面板）时不要压暗：
	#   这时「洞」几乎等于全屏，压暗等于没压，反而会在四周留一圈莫名其妙的黑边。
	var big := r.size.x * r.size.y > vp.x * vp.y * 0.8
	if not big:
		# 四块压暗（等于挖一个洞，比 shader 稳，且截图能直接看到）
		_spot.draw_rect(Rect2(0.0, 0.0, vp.x, maxf(0.0, r.position.y)), DIM)
		_spot.draw_rect(Rect2(0.0, r.end.y, vp.x, maxf(0.0, vp.y - r.end.y)), DIM)
		_spot.draw_rect(Rect2(0.0, r.position.y, maxf(0.0, r.position.x), r.size.y), DIM)
		_spot.draw_rect(Rect2(r.end.x, r.position.y, maxf(0.0, vp.x - r.end.x), r.size.y), DIM)
	# 呼吸边框
	var pulse := 0.55 + 0.25 * sin(Time.get_ticks_msec() / 260.0)
	_spot.draw_rect(r, Color(accent.r, accent.g, accent.b, pulse), false, 2.0)
	if off:
		# 目标在屏幕外：箭头画在**玩家脚边**（用户 2026-11-12：边缘那个箭头离得太远、
		# 经常看不见）。找不到玩家（面板里 / 试炼没有玩家）才退回贴框边指。
		if not _draw_arrow_at_player():
			_draw_arrow_to(r, (_target_rect.get_center() - r.get_center()).normalized())
		return
	# 箭头：从目标上方指向目标中心
	var cx := r.get_center().x
	var tip_y := r.position.y - 4.0
	var base_y := tip_y - 18.0
	var pts := PackedVector2Array([
		Vector2(cx, tip_y), Vector2(cx - 11.0, base_y), Vector2(cx + 11.0, base_y)])
	_spot.draw_colored_polygon(pts, Color(accent.r, accent.g, accent.b, 0.92))


## 目标在屏幕外时：黄色箭头挂在**玩家脚边**，朝目标方向指。
## 返回 false = 场上没有玩家（面板遮住 / 非游戏场景），调用方退回贴框边的老画法。
##
## 几何抽成 `_feet_arrow_geometry()`（探针直接验），绘制只负责照着它画。
func _draw_arrow_at_player() -> bool:
	var geo := _feet_arrow_geometry()
	if geo.is_empty():
		return false
	var accent: Color = UIKit.C_ACCENT
	_spot.draw_colored_polygon(
		PackedVector2Array([geo["tip"], geo["left"], geo["right"]]),
		Color(accent.r, accent.g, accent.b, 0.95))
	return true


## 玩家脚边箭头的三个点（屏幕坐标）。返回 {} = 没有玩家 / 方向算不出来。
##   base = 玩家脚下正中；tip = base + 方向 × 26（带轻微呼吸，提示「往这边走」）
func _feet_arrow_geometry() -> Dictionary:
	var player := _player_node()
	if player == null:
		return {}
	# ⚠ 不能用 _node2d_rect 算脚：它会取「最大的碰撞体」（玩家身上还有个很长的攻击胶囊），
	#   量出来整个人三四百像素高，脚就被推到屏幕外了。玩家原点本身就在脚下
	#   （碰撞胶囊中心在 -32），直接取画布变换的原点最准。
	var xf := (player as CanvasItem).get_global_transform_with_canvas()
	var feet_screen := xf.origin
	var body := feet_screen + Vector2(0.0, -34.0)
	var to := _target_rect.get_center() - body
	if to.length() < 1.0:
		return {}
	var dir := to.normalized()
	var base := feet_screen + Vector2(0.0, 12.0)
	var bob := 2.0 * sin(Time.get_ticks_msec() / 1000.0 * 3.2)
	var tip := base + dir * (24.0 + bob)
	var side := Vector2(-dir.y, dir.x) * 9.0
	return {
		"base": base,
		"tip": tip,
		"left": base + side + dir * 5.0,
		"right": base - side + dir * 5.0,
		"dir": dir,
	}


## 场上的玩家（Node2D）。没有返回 null（主菜单 / 面板-only 场景）。
func _player_node() -> Node2D:
	var p := get_tree().get_first_node_in_group("player")
	if p is Node2D and is_instance_valid(p):
		return p as Node2D
	return null


## 目标在屏幕外：箭头沿框边缘往目标方向指（tip 在外侧，底边贴着框）
func _draw_arrow_to(r: Rect2, dir: Vector2) -> void:
	var d := dir
	if d.length() < 0.5:
		d = Vector2(0.0, -1.0)
	d = d.normalized()
	var accent: Color = UIKit.C_ACCENT
	var half := r.size * 0.5
	# 从中心沿 d 走到框边上的点
	var edge := r.get_center() + d * (absf(d.x) * half.x + absf(d.y) * half.y)
	var tip := edge + d * 16.0
	var base := edge + d * 1.0
	var side := Vector2(-d.y, d.x) * 10.0
	_spot.draw_colored_polygon(
		PackedVector2Array([tip, base + side, base - side]),
		Color(accent.r, accent.g, accent.b, 0.92))


## 聚光框实际画在哪：目标在屏幕外时整块收进视口。
## ⚠ 不收的话，框画在屏幕外 = 洞在屏幕外 → 四块压暗拼成满屏黑，玩家看不到目标也看不到指路。
func _spot_frame() -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	return _clamp_rect_to_view(_target_rect.grow(6.0), vp)


func _clamp_rect_to_view(r: Rect2, vp: Vector2) -> Rect2:
	var m := 16.0
	var sz := Vector2(minf(r.size.x, maxf(8.0, vp.x - m * 2.0)),
		minf(r.size.y, maxf(8.0, vp.y - m * 2.0)))
	var p := r.position
	p.x = clampf(p.x, m, maxf(m, vp.x - sz.x - m))
	p.y = clampf(p.y, m, maxf(m, vp.y - sz.y - m))
	return Rect2(p, sz)


# ===================== 暂停喂招 =====================

func show_pause_prompt(text: String) -> void:
	_pause_label.text = text
	_pause_box.visible = true
	_pause_box.reset_size()
	var vp := get_viewport().get_visible_rect().size
	var sz := _pause_box.get_combined_minimum_size()
	_pause_box.position = Vector2((vp.x - sz.x) * 0.5, vp.y * 0.28)
	_card.visible = false
	_spot.visible = false
	get_tree().paused = true


func hide_pause_prompt() -> void:
	_pause_box.visible = false
	_spot.visible = true
	get_tree().paused = false


func _input(event: InputEvent) -> void:
	if not Tutorial.is_pause_prompt():
		return
	if event.is_action_pressed("parry"):
		get_viewport().set_input_as_handled()
		Tutorial.call("_on_pause_parry")
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Tutorial.call("_on_pause_skip")


func _process(_delta: float) -> void:
	# 切场景后重新判定露不露脸（change_scene 没有信号 → 比对 current_scene 引用）
	var cs := get_tree().current_scene
	if cs != _seen_scene:
		_seen_scene = cs
		_refresh_card()
	# 模态界面开/关：这一屏该不该露脸要重算（指引只在它所属的界面里露面）
	var depth := GameState._modal_ui_depth
	if depth != _seen_modal_depth:
		_seen_modal_depth = depth
		_refresh_card()
	# 目标被重建 / 被藏起来：丢掉引用，下面的重试逻辑才扫得到新的那一个
	# ⚠ 只丢「已释放 / 算不出矩形」的：世界设施在屏幕外时矩形仍成立，不能误丢
	if _target_node != null and (not is_instance_valid(_target_node)
			or _rect_of(_target_node).size == Vector2.ZERO):
		_target_node = null
	# 锚点重试：本步声明了锚点但还没扫到节点 → 定期重扫（面板/掉落物是后来才建的）
	if _target_node == null and not Tutorial.active_step.is_empty() \
			and String(Tutorial.active_step.get("anchor", "")) != "":
		_anchor_retry -= _delta
		if _anchor_retry <= 0.0:
			_anchor_retry = ANCHOR_RETRY_INTERVAL
			_refresh_card()
	# 目标会动（设施不动的，但面板里的按钮会随滚动位移）→ 每帧重取一次矩形
	if _target_node == null or not _spot.visible:
		return
	var old := _target_rect
	_update_target_rect()
	_has_target = _target_rect.size != Vector2.ZERO
	if _has_target != (old.size != Vector2.ZERO) or _target_rect != old:
		_place_card()
	_spot.queue_redraw()
