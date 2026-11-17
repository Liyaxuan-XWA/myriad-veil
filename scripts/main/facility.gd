extends Area2D
## 万界锚点空间内的功能设施（可点击进入）
##
## 视觉走统一皮肤表（ArtDB）：
##   - 美术接入：在 art_db.gd 里加一条 "facility_<facility_id>"（如 facility_arena），
##     填 texture 即自动替换本设施贴图，本脚本与场景文件均无需改动
##   - 未接入贴图：回退为场景原有配色色块（place_holder 沿用 _ready 时读到的颜色）
##
## 点击后对外抛出 activated(facility_id)，由 AnchorSpace 统一分发
signal activated(facility_id: String)
## 玩家进入 / 离开本设施的靠近范围（主城据此显示「按 F 进入」提示）
signal player_near(facility_id: String, is_near: bool)

@export var facility_id: String = ""
@export var facility_name: String = ""

# 悬停高亮
const HOVER_COLOR := Color(0.4, 0.6, 0.85, 1.0)
## 「暂未开启」时的压暗透明度（悬停会稍微提亮，但仍然明显比正常设施暗）
const LOCKED_ALPHA := 0.45

# 各设施自身配色由场景指定，此处记录初始色以便悬停后还原
var _base_color: Color = Color(0.25, 0.35, 0.5, 1.0)

## 视觉节点（SkinVisual）：场景里的 ColorRect 会在 _ready 时被它替换
var _visual: SkinVisual = null

## 是否处于「暂未开启」状态（由主城按名单设置，见 primordial_realm.gd 的 LOCKED_FACILITIES）
var is_locked := false
## 名字下方的「暂未开启」小字（懒创建）
var _lock_tag: Label = null

@onready var name_label: Label = $NameLabel


func _ready() -> void:
	input_pickable = true
	input_event.connect(_on_input_event)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	# 靠近检测：玩家（layer 1 / 组 "player"）进入碰撞范围即视为「靠近」
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if name_label:
		name_label.text = facility_name
		# 关键：文字标签必须忽略鼠标，否则会吃掉点击导致 Area2D 收不到 input_event
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setup_visual()


## 建立统一视觉：把场景里的占位 ColorRect 换成 SkinVisual
## 保留原 ColorRect 的颜色作为占位色，保证未接入贴图时外观与改造前完全一致
func _setup_visual() -> void:
	var old := get_node_or_null("Visual")
	if old != null and old is ColorRect:
		_base_color = (old as ColorRect).color
		# 必须立即移除并释放，否则新建的同名节点会被自动改名为 Visual2
		remove_child(old)
		old.free()

	_visual = SkinVisual.new()
	_visual.name = "Visual"
	_visual.visual_id = "facility_" + facility_id
	# 未单独登记 facility_<id> 时回退到通用设施条目
	_visual.fallback_visual_id = "facility_generic"
	# 场景配色传给占位色（ArtDB 里已登记贴图时该色仅作为兜底）
	_visual.placeholder_color_override = _base_color
	# 占位尺寸沿用场景碰撞体尺寸，保证点击热区与视觉一致
	var shape := get_node_or_null("CollisionShape2D")
	if shape != null and shape is CollisionShape2D and (shape as CollisionShape2D).shape is RectangleShape2D:
		_visual.placeholder_size_override = ((shape as CollisionShape2D).shape as RectangleShape2D).size
	# 形象压在名字下面：SkinVisual 是 _ready 时才加进来的（排在 NameLabel 之后），
	# 不设 z 会盖住设施名 —— 接入贴图后同样会盖，所以这里统一压到 -1
	_visual.z_index = -1
	add_child(_visual)
	_visual.refresh()
	_place_name_below_visual()


## 设施名挪到图标**下方**（2026-10-22 接入正式美术后）
## 原来名字压在色块正中；换成带画面的设施图后，文字正好糊在图标中间看不清。
## 位置按 SkinVisual 实测的包围盒算，所以每个设施（塔更高、药田更矮）都能自动贴边。
func _place_name_below_visual() -> void:
	if name_label == null or _visual == null:
		return
	var half_h := _visual.visual_rect.size.y * 0.5
	if half_h <= 0.0:
		half_h = 40.0   # 占位兜底：沿用原 120×80 的一半
	name_label.position = Vector2(name_label.position.x, half_h + 4.0)


## 点击进设施。
## ⚠ 触屏不能照抄「按下即开」：手指落下那一拍还不知道它会不会滑走，而安卓的触摸
##   会额外合成一条鼠标事件（摇杆/按键区的已在 VirtualPad 挡掉，场景区的会漏到这里）。
##   所以触屏改在**抬手**时结算，且只认 VirtualPad 判定的点按 —— 拖过阈值、
##   长按后抬起都不算。PC（没开触屏按键）保持按下即开，手感一个字节不动。
func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if VirtualPad.is_touch_enabled():
		if not mb.pressed and VirtualPad.is_tap_at(mb.position):
			activated.emit(facility_id)
		return
	if mb.pressed:
		activated.emit(facility_id)


## 悬停高亮：触屏下手指划过不算悬停，跟着亮只会晃眼（抬手时还会留一层下不去的亮）
func _on_mouse_entered() -> void:
	if VirtualPad.is_touch_enabled():
		return
	set_highlight(true)


func _on_mouse_exited() -> void:
	if VirtualPad.is_touch_enabled():
		return
	set_highlight(false)


## 悬停高亮：对 SkinVisual 统一生效（贴图 / 占位都走 modulate，不破坏素材本色）
func set_highlight(on: bool) -> void:
	if _visual == null or not is_instance_valid(_visual):
		return
	var alpha := LOCKED_ALPHA if is_locked else 1.0
	if on:
		_visual.modulate = Color(1.35, 1.35, 1.35, alpha)
	else:
		_visual.modulate = Color(1.0, 1.0, 1.0, alpha)


## 标记「暂未开启」：整块压暗 + 名字下加一行小字，点击由主城统一给提示
## 文案颜色取 UIKit，换 UI 配色时跟着变，不在这里写死颜色
## reason 非空时用它替代默认的「暂未开启」：进度锁必须说清差什么，
## 只写「暂未开启」玩家会当成功能没做而不再回来（2026-11-04 用户要求棋坛按通关解锁）
func set_locked(locked: bool, reason: String = "") -> void:
	is_locked = locked
	if locked and _lock_tag == null and name_label != null:
		_lock_tag = UIKit.label(reason if reason != "" else "暂未开启",
				UIKit.F_SMALL, UIKit.C_WARN)
		_lock_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lock_tag.position = Vector2(name_label.position.x, name_label.position.y + name_label.size.y + 2.0)
		_lock_tag.size = Vector2(name_label.size.x, 16.0)
		_lock_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_lock_tag)
	if _lock_tag != null:
		_lock_tag.visible = locked
	if name_label != null:
		name_label.modulate = Color(1.0, 1.0, 1.0, 0.55) if locked else Color.WHITE
	set_highlight(false)


# ===================== 靠近检测 =====================

## 有 body 进入碰撞范围：是玩家就通知主城「有人靠近了」
func _on_body_entered(body: Node) -> void:
	if is_instance_valid(body) and body.is_in_group("player"):
		player_near.emit(facility_id, true)


## 有 body 离开碰撞范围：是玩家就通知主城「人走了」
func _on_body_exited(body: Node) -> void:
	if is_instance_valid(body) and body.is_in_group("player"):
		player_near.emit(facility_id, false)
