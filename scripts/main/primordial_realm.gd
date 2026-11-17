extends Node2D
## 原初位面 —— 第一篇章唯一安全枢纽（对应任务书 §2.14「主城万界锚点空间」）
## 用户命名「原初位面」，工程内统一使用此名；设定归属仍对应 §2.14 主城。
##
## 连接真实位面、万界塔、装备养成、炼丹、制符、功法与记忆。
## 本阶段为「场景骨架」：9 个地面设施可点击进入，各系统内部逻辑留待后续实现。
##
## 功法库不在地图上，为随身携带（Y 键打开），且仅原初位面可用 ——
## 依据任务书 §2.9 / §6.1：主城可自由切换功法搭配，战斗内禁止更换功法。

@onready var hint_label: Label = $HUD/HintLabel
@onready var key_hint_label: Label = $HUD/KeyHintLabel

## 主城 BGM：空灵、舒缓的循环曲（tools/gen_battle_music.py 生成）
const BGM_REALM := "res://assets/audio/bgm/realm_primordial.wav"
var _bgm: BgmPlayer = null

## 暂未开启的设施：点击只提示，不打开界面
## 设施本体会压暗并显示「暂未开启」，见 facility.gd 的 set_locked()
##
## 2026-10-23 用户要求：炼丹房 / 制符台全部开放（配方见 ItemDB）。
## 药田已迁到大世界练气区：打完该区域核心首领后在森林开垦灵田。
## 关掉某个设施：把它的 id 加回这张表即可，_on_facility_activated 会自动拦截。
##
## 2026-11-02 用户要求：记忆幻像碑暂时封锁 —— 里面的剧情还没制作，
## 面板与脚本都留着，剧情做完把这一行清空就重新开。
const LOCKED_FACILITIES := {
	"memory": "记忆幻像碑",
}

## 通关某个位面才解锁的设施：facility_id → 前置界域 id
## 与 LOCKED_FACILITIES 分清：那张表是「功能还没做」，这张表是「玩家还没打到」。
## 压暗 + 名字下写「通关凡界后开启」，点击只给一句提示（见 _facility_gate_reason）
## 2026-11-04 用户要求：万界棋坛要通关第一位面才开。
const GATED_FACILITIES := {
	"match": "domain_01",
}

# 当前打开的系统界面（同时只允许一个）
var _current_panel: SystemPanel = null

## 当前靠近的设施 id（空 = 没有靠近任何设施）
## 靠近时 HUD 常驻「按 F 进入」，离开即清空；面板打开期间也清掉，关掉后面板再恢复
var _near_facility_id := ""
## HUD 提示的默认文案（进场时常驻显示的操作说明），没有靠近设施时恢复它
var _default_hint_text := ""
## _show_hint 的渐隐 tween 引用：靠近提示要接管 Label 时先把它掐掉，
## 否则它稍后会把 alpha 补到 0，把常驻的「按 F 进入」一起淡掉
var _hint_tween: Tween = null
## 右上角「Y 功法库」的新功法红圈（有未查看的新功法时显示）
var _new_skill_ring: Control = null
## 右上角「Tab 角色信息」的突破红圈（修为圆满时显示）
var _breakthrough_ring: Control = null

# ===================== 场地屏障（2026-10-22 用户定）=====================
## 玩家活动范围 = **地面美术的可见范围**（读 Ground/Skin 的 visual_rect，换地图自动跟着变）
## 三层限制，缺一层都会漏：
##   ① 镜头 limit：镜头不会移出边界（能看到的最大范围就是屏障内）
##   ② 四面 StaticBody2D 碰撞墙：人走不出去（否则人跑出屏幕、镜头停在边上）
##   ③ 可见能量光墙：让玩家看得见边界在哪
const BARRIER_WALL_THICKNESS := 40.0
## 碰撞墙与光墙相对地面边缘**内缩**的距离（2026-10-22 实测修正）
## ⚠ 不能贴在地面边缘：镜头 limit 也贴边时，光墙正好落在屏幕最外沿 → 玩家根本看不见。
##   内缩 56px 后：人被墙挡住时，镜头还能再往外带 56px，那一圈光带就露在屏幕里侧。
const BARRIER_INSET := 56.0

## 屏障矩形 = 地面美术范围（镜头 limit 用它，能看到墙外侧一小条地面）
var _barrier_bounds := Rect2()
## 碰撞墙 / 光墙用的矩形（比 _barrier_bounds 内缩 BARRIER_INSET）
var _barrier_wall_rect := Rect2()


func _ready() -> void:
	# 安卓返回键在本场景 = 后退（ESC 语义：返回登录界面），见 GameState.handle_go_back()
	GameState.back_uses_esc = true
	# 触屏：切到主城布局（摇杆 + 进入 + 设置；功法库/背包是 HUD 图标）
	VirtualPad.set_context("realm")
	# 遍历所有设施，统一接入点击分发
	for node in $Facilities.get_children():
		if node.has_signal("activated"):
			node.activated.connect(_on_facility_activated)
		# 靠近检测：进范围显示「按 F 进入」，离开清空
		if node.has_signal("player_near"):
			node.player_near.connect(_on_facility_near)
		# 暂未开启的设施：压暗 + 名字下加提示，避免玩家白点
		if node.get("facility_id") != null:
			var fid := String(node.get("facility_id"))
			if LOCKED_FACILITIES.has(fid) and node.has_method("set_locked"):
				node.set_locked(true)
			else:
				var gate := _facility_gate_reason(fid)
				if gate != "" and node.has_method("set_locked"):
					node.set_locked(true, gate)

	# 缓存 HUD 的默认操作提示：离开设施时要恢复它（而不是留一片空白）
	if hint_label:
		_default_hint_text = hint_label.text
	# 新手指引锚点：c5 教「按 Y 打开功法库」，聚光指在这条键位提示上
	if key_hint_label != null:
		key_hint_label.set_meta("tut", "hud.skill.key")

	# 触屏专用 HUD：背包 / 功法库图标（PC 上不显示）
	_setup_touch_hud()

	# 左上角「新手指引」小书（PC / 触屏都显示）
	_setup_guide_book()

	# 右上角 Y 的新功法红圈 / Tab 的突破红圈
	_setup_new_skill_ring()
	_setup_breakthrough_ring()

	# 四周屏障：镜头 + 碰撞 + 能量墙（必须在设施/地面就绪之后）
	_setup_barrier()

	# 主城氛围 BGM（暂停面板时也继续，由 BgmPlayer 的 ALWAYS 保证）
	_start_realm_bgm()

	# 回到主城即自动存档（轮流写入 1–4 槽）
	SaveManager.auto_save()

	# 新手指引：必须放在最后（设施 / HUD / 小书都建完，聚光才找得到锚点）
	_setup_tutorial()

	# 跨场景界面请求（战败提示「去青岚野取剑」）：回城直接停在那一页
	_consume_pending_panel()


## 离场交还返回键：新场景没声明时，返回键回到「退出确认」而不是把主城语义带过去
func _exit_tree() -> void:
	GameState.back_uses_esc = false


## 消费 GameState.pending_panel —— 只活一次，消费完立刻清空。
## 目前只有一条请求：「万界秘境 → 苍澜大陆 → 指定区」（虎妖战败提示点进来）。
func _consume_pending_panel() -> void:
	var req: Dictionary = GameState.pending_panel
	if req.is_empty():
		return
	GameState.pending_panel = {}
	if String(req.get("panel", "")) != "domain":
		return
	var tab := String(req.get("tab", "domains"))
	var region := String(req.get("region", ""))
	_open_system_panel("res://scripts/ui/panels/domain_panel.gd",
		func(p: SystemPanel) -> void:
			p.set("start_tab", tab)
			p.set("start_region_id", region))


# ===================== 主城 BGM =====================

func _start_realm_bgm() -> void:
	if _bgm != null:
		return
	_bgm = BgmPlayer.new()
	_bgm.name = "RealmBgm"
	add_child(_bgm)
	_bgm.play_loop(BGM_REALM, BgmPlayer.AMBIENT_VOLUME_DB, 2.2)


# ===================== 触屏 HUD（2026-10-22）=====================

## 触屏专用的两个常驻图标：背包 / 功法库
## 为什么不做成虚拟键：用户明确要「屏幕上的图标方便点」，这两项又是随时会用的高频入口，
##   固定图标比塞进可拖动的虚拟键盘更直观；虚拟键盘那边只保留摇杆 + 进入 + 设置。
## PC 上节点照建但整层隐藏 —— 不影响任何键鼠操作。
var _touch_hud: Control = null


func _setup_touch_hud() -> void:
	var hud := get_node_or_null("HUD")
	if hud == null:
		return
	_touch_hud = Control.new()
	_touch_hud.name = "TouchHud"
	_touch_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_touch_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_touch_hud)

	# 右上角竖排：背包在上、功法库在下（避开顶部的按键提示文字）
	var bag_btn := _make_touch_hud_button("背包", 96.0, func() -> void:
		CharacterPanel.toggle_panel()
	)
	bag_btn.set_meta("tut", "hud.bag")
	Tutorial.attach_badge(bag_btn, "bag")
	_touch_hud.add_child(bag_btn)
	_touch_hud.add_child(_make_touch_hud_button("功法库", 172.0, func() -> void:
		_open_skill_library()
	))

	VirtualPad.enabled_changed.connect(_on_touch_enabled_changed)
	VirtualPad.edit_mode_changed.connect(_on_touch_edit_mode_changed)
	_apply_touch_hud_state()


## 调整按键布局时：把 HUD 文字和图标全收起来
## 否则「重置」按钮会和左上角标题、「背包」图标叠在一起，画面一团乱
func _on_touch_edit_mode_changed(on: bool) -> void:
	# ⚠ 小书也在左上角，会和编辑栏的「重置」按钮叠在一起 → 一并收起
	for path in ["HUD/TitleLabel", "HUD/HintLabel", "HUD/KeyHintLabel",
			"HUD/GuideBookButton", "HUD/CodexButton"]:
		var n := get_node_or_null(path) as CanvasItem
		if n != null:
			n.visible = not on
	if on:
		if _touch_hud != null and is_instance_valid(_touch_hud):
			_touch_hud.visible = false
		return
	# 退出编辑：恢复 HUD（hint 在触屏模式下本来就是触屏说明文案）
	if hint_label != null:
		hint_label.visible = true
	_apply_touch_hud_state()


# ===================== 新手指引「小书」（2026-10-23）=====================

## 左上角常驻的一本小书：点开查看新手指引
## 为什么做成 HUD 图标而不是设施：指引要**随时能翻**，不该让玩家跑回某个建筑前。
## PC 与触屏都显示（它不是虚拟键，不参与按键布局编辑）。
const GUIDE_BOOK_POS := Vector2(20.0, 16.0)
const HUD_LEFT_W := 80.0
const HUD_LEFT_GAP := 8.0
## 入口列高度：触屏抬到 64（拇指最小命中线），PC 保持原来的 48
const HUD_LEFT_H_PC := 48.0
const HUD_LEFT_H_TOUCH := 64.0


## 左上角入口列的一颗按钮：宽 80，高按设备取，纵向按 _hud_left_top 依次排
func _hud_left_btn(text: String, node_name: String, tooltip: String, top: float,
		on_press: Callable) -> Button:
	var h := HUD_LEFT_H_TOUCH if VirtualPad.is_touch_enabled() else HUD_LEFT_H_PC
	var btn := UIKit.button(text, Vector2(HUD_LEFT_W, h))
	btn.name = node_name
	btn.tooltip_text = tooltip
	btn.add_theme_font_size_override("font_size", 16)
	btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	btn.offset_left = GUIDE_BOOK_POS.x
	btn.offset_top = top
	btn.offset_right = GUIDE_BOOK_POS.x + HUD_LEFT_W
	btn.offset_bottom = top + h
	btn.pressed.connect(on_press)
	return btn


## 入口列第 n 个（0 起）的顶边：高度随设备变，所以不能再用编译期常量相加
func _hud_left_top(index: int) -> float:
	var h := HUD_LEFT_H_TOUCH if VirtualPad.is_touch_enabled() else HUD_LEFT_H_PC
	return GUIDE_BOOK_POS.y + float(index) * (h + HUD_LEFT_GAP)


func _setup_guide_book() -> void:
	var hud := get_node_or_null("HUD")
	if hud == null:
		return
	# ⚠ 图标必须用 Button 自带的 icon 属性，**不能** add_child 一个容器当图标：
	#   占位用的 PanelContainer 默认 mouse_filter = STOP，会把鼠标事件吃掉，
	#   Button 反而收不到 pressed（表现就是「按钮点不动」）。
	#   换图只改 UIKit.TEX_ICON_GUIDE；没有图时就是纯文字按钮，一样能用。
	var btn := _hud_left_btn("指引书", "GuideBookButton", "新手指引", _hud_left_top(0),
			_open_guide)
	if ResourceLoader.exists(UIKit.TEX_ICON_GUIDE):
		btn.icon = load(UIKit.TEX_ICON_GUIDE)
	hud.add_child(btn)

	# 图鉴独立入口：指引书下方，不再塞进指引书面板内部
	var codex := _hud_left_btn("图鉴", "CodexButton", "万界图鉴", _hud_left_top(1),
			_open_codex)
	codex.set_meta("tut", "hud.codex")
	Tutorial.attach_badge(codex, "codex")
	hud.add_child(codex)

	# 成就入口：贴在图鉴下方（卡包已从图鉴迁到「成就 → 成就收藏」）
	var achievement := _hud_left_btn("成就", "AchievementButton", "成就 · 收藏",
			_hud_left_top(2), _open_achievement)
	achievement.set_meta("tut", "hud.achievement")
	Tutorial.attach_badge(achievement, "achievement")
	hud.add_child(achievement)


func _open_guide() -> void:
	_open_system_panel("res://scripts/ui/panels/guide_panel.gd")


func _open_codex() -> void:
	Tutorial.mark_seen("codex")
	_open_system_panel("res://scripts/ui/panels/codex_panel.gd")


func _open_achievement() -> void:
	Tutorial.mark_seen("achievement")
	_open_system_panel("res://scripts/ui/panels/achievement_panel.gd")


func _make_touch_hud_button(text: String, top: float, on_press: Callable) -> Button:
	var btn := UIKit.button(text, Vector2(88.0, 66.0))
	btn.add_theme_font_size_override("font_size", 20)
	# 贴右上角：offset 相对右边界（-104 ~ -16 = 宽 88，留 16px 安全边距）
	btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn.offset_left = -104.0
	btn.offset_right = -16.0
	btn.offset_top = top
	btn.offset_bottom = top + 66.0
	btn.pressed.connect(on_press)
	return btn


func _on_touch_enabled_changed(_is_on: bool) -> void:
	_apply_touch_hud_state()


func _apply_touch_hud_state() -> void:
	var on := VirtualPad.is_touch_enabled()
	if _touch_hud != null and is_instance_valid(_touch_hud):
		_touch_hud.visible = on
	# 触屏模式下键盘提示没有意义，换成触屏操作说明
	var key_hint := get_node_or_null("HUD/KeyHintLabel")
	if key_hint != null:
		(key_hint as CanvasItem).visible = not on
	if hint_label != null and on:
		hint_label.text = "左下按住即出摇杆 · 「进入」亮起时点它进设施 · 右上角开背包 / 功法库"
		_default_hint_text = hint_label.text
	# 刚切到触屏（或进场）时先把「进入」键的三态摆正：
	# 否则没人靠近设施时它顶着默认文字「进入」亮着，按下去什么也不会发生
	_refresh_enter_key()


# ===================== 屏障实现 =====================

## 建立屏障：以地面美术的实测矩形为界（换图后自动适配，不用手改数字）
func _setup_barrier() -> void:
	var skin := get_node_or_null("Ground/Skin") as SkinVisual
	if skin == null or skin.visual_rect.size.x < 10.0 or skin.visual_rect.size.y < 10.0:
		# 地面贴图没接上（走占位）时 visual_rect 会很小，此时不设屏障，避免把人锁在原点
		push_warning("原初位面：地面尺寸未知，跳过屏障")
		return
	_barrier_bounds = skin.visual_rect
	# 墙/光带内缩，镜头留出余量（否则光墙贴在屏幕最外沿看不见）
	_barrier_wall_rect = _barrier_bounds.grow(-BARRIER_INSET)
	_apply_camera_limits(_barrier_bounds)
	_build_barrier_walls(_barrier_wall_rect)
	_build_barrier_glow(_barrier_wall_rect)


## ① 镜头限制：镜头视口不会越过边界
func _apply_camera_limits(r: Rect2) -> void:
	var cam := get_node_or_null("Player/Camera2D") as Camera2D
	if cam == null:
		return
	cam.limit_left = int(round(r.position.x))
	cam.limit_right = int(round(r.end.x))
	cam.limit_top = int(round(r.position.y))
	cam.limit_bottom = int(round(r.end.y))


## ② 四面碰撞墙：墙中心压在边界线上（一半在外），玩家走到边界就被挡
func _build_barrier_walls(r: Rect2) -> void:
	var body := StaticBody2D.new()
	body.name = "Barrier"
	# 玩家（CharacterBody2D）默认 mask=1，所以墙放第 1 层就能挡住
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	var t := BARRIER_WALL_THICKNESS
	var c := r.get_center()
	_add_wall_shape(body, Vector2(c.x, r.position.y - t * 0.5), Vector2(r.size.x + t * 2.0, t))
	_add_wall_shape(body, Vector2(c.x, r.end.y + t * 0.5), Vector2(r.size.x + t * 2.0, t))
	_add_wall_shape(body, Vector2(r.position.x - t * 0.5, c.y), Vector2(t, r.size.y + t * 2.0))
	_add_wall_shape(body, Vector2(r.end.x + t * 0.5, c.y), Vector2(t, r.size.y + t * 2.0))


func _add_wall_shape(body: StaticBody2D, center: Vector2, size: Vector2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = center
	body.add_child(cs)


## ③ 可见能量墙：闭合 Line2D 两圈（外层灵光 + 内层能量流），外观由 shader 生成
## 配色/宽度/流动速度/呼吸频率全走 ArtDB 的 "realm_barrier"，换美术只改那张表
## ⚠ 呼吸**交给 shader**（按世界坐标错相位），不要再用 tween 改 alpha：
##   两层线各自 tween 会同步闪，看起来是「整块亮暗」而不是灵力流动
func _build_barrier_glow(r: Rect2) -> void:
	var cfg := ArtDB.get_visual("realm_barrier")
	var pts := PackedVector2Array([
		Vector2(r.position.x, r.position.y),
		Vector2(r.end.x, r.position.y),
		Vector2(r.end.x, r.end.y),
		Vector2(r.position.x, r.end.y),
		Vector2(r.position.x, r.position.y),
	])

	var holder := Node2D.new()
	holder.name = "BarrierGlow"
	# 压在地面(-10)之上、设施(-1)之下：光墙不该盖住设施画面
	holder.z_index = -5
	add_child(holder)

	var tex_path := String(cfg.get("texture", ""))
	var tex: Texture2D = load(tex_path) if (tex_path != "" and ResourceLoader.exists(tex_path)) else null
	# 外层灵光：**多条不同宽度的线叠出纵向柔边**
	# ⚠ 不能靠 shader 里的 UV.y 做柔边：Line2D 无贴图时 UV 不可靠（会让整面墙 alpha 归零）
	var glow_w := float(cfg.get("glow_width", 86.0))
	var glow_a := float(cfg.get("glow_alpha", 0.30))
	for layer in [[1.0, 0.45], [0.74, 0.65], [0.50, 0.85], [0.30, 1.0]]:
		var w: float = glow_w * float(layer[0])
		var a_mul: float = float(layer[1])
		var ln := _make_barrier_line(pts, w, tex)
		ln.material = _make_barrier_material(cfg, true, glow_a * a_mul)
		holder.add_child(ln)
	# 内层能量流：细、亮
	var core := _make_barrier_line(pts, float(cfg.get("barrier_width", 13.0)), tex)
	core.material = _make_barrier_material(cfg, false, float(cfg.get("core_alpha", 0.95)))
	holder.add_child(core)


## 造一层能量墙材质：优先用 shader（流动 + 呼吸），没有 shader 就退回纯色
func _make_barrier_material(cfg: Dictionary, is_glow: bool, alpha: float) -> Material:
	var shader_path := String(cfg.get("shader", ""))
	if shader_path == "" or not ResourceLoader.exists(shader_path):
		return null
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	mat.set_shader_parameter("core_color",
		cfg.get("core_color", Color(0.82, 0.97, 1.0, 1.0)))
	mat.set_shader_parameter("glow_color",
		cfg.get("glow_color", Color(0.30, 0.74, 0.98, 1.0)))
	mat.set_shader_parameter("base_alpha", alpha)
	mat.set_shader_parameter("flow_speed", float(cfg.get("flow_speed", 24.0)))
	mat.set_shader_parameter("turbulence", float(cfg.get("turbulence", 0.02)))
	mat.set_shader_parameter("flow_contrast", float(cfg.get("flow_contrast", 1.45)))
	mat.set_shader_parameter("pulse_speed", float(cfg.get("pulse_speed", 1.0)))
	mat.set_shader_parameter("pulse_amount", float(cfg.get("pulse_amount", 0.32)))
	# 外层灵光更偏「外溢色」，内层更偏「能量色」
	if is_glow:
		mat.set_shader_parameter("core_color", cfg.get("glow_color", Color(0.30, 0.74, 0.98, 1.0)))
	return mat


func _make_barrier_line(pts: PackedVector2Array, width: float,
		tex: Texture2D) -> Line2D:
	var ln := Line2D.new()
	ln.points = pts
	ln.width = width
	# 有 shader 时颜色由 shader 算，这里的默认色只在没有 shader 时兜底（用白色以免叠色）
	ln.default_color = Color(1, 1, 1, 1)
	ln.joint_mode = Line2D.LINE_JOINT_ROUND
	ln.begin_cap_mode = Line2D.LINE_CAP_ROUND
	ln.end_cap_mode = Line2D.LINE_CAP_ROUND
	ln.antialiased = true
	if tex != null:
		ln.texture = tex
		ln.texture_mode = Line2D.LINE_TEXTURE_TILE
	return ln


func _unhandled_input(event: InputEvent) -> void:
	# 功法库随身携带：仅原初位面可打开（战斗场景内不注册此键，天然不可用）
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Y:
			_open_skill_library()
		elif event.physical_keycode == KEY_F:
			# 靠近设施时按 F = 进入（与鼠标点击完全等价）
			# 面板开着不响应：避免关面板的瞬间误触又开一个
			if _current_panel == null and _near_facility_id != "":
				_on_facility_activated(_near_facility_id)
		elif event.physical_keycode == KEY_ESCAPE:
			# 系统面板打开时 ESC 归面板（关面板），不弹确认框
			if _current_panel == null:
				_ask_return_title()


func _process(_delta: float) -> void:
	# 面板刚被关掉（节点已释放）：恢复一次靠近提示
	# 否则玩家关掉面板后站在原地，会再也看不到「按 F 进入」
	if _current_panel != null and not is_instance_valid(_current_panel):
		_current_panel = null
		_update_near_hint()
	_update_new_skill_ring()
	_update_breakthrough_ring()
	_tut_track_move()


# ===================== 新手指引（2026-11-10）=====================

var _tut_last_pos := Vector2.ZERO
var _tut_started := false


## 第 1 章：新号进主城自动开始（老档 Tutorial 自己会拒绝，见 is_legacy）
func _setup_tutorial() -> void:
	if _tut_started:
		return
	_tut_started = true
	Tutorial.maybe_start("new")
	# 首杀「虎妖」后回到原初位面：主动带玩家走「锻造强化 → 万界塔 → 功法」链
	# （塔是功法唯一来源，不指路新号会一直没功法可放）。开哪一章、要不要前置
	# （打过虎妖）都由 TutorialDB 的 trigger / need 决定，这里只报「我回来了」。
	# 链路通常已在战斗结算里开（或排队中），这一条是读档 / 中途退游戏的续路。
	# 第 1 章若还停在「回城开背包」，这一步只会排队，等那步做完自动接上。
	Tutorial.request_chapter_by_trigger("after_huyao")
	# 红点吐司：点一条直达对应入口（战斗里不弹，见 Tutorial._tick_badges）
	if not Tutorial.toast_clicked.is_connected(_on_tut_toast):
		Tutorial.toast_clicked.connect(_on_tut_toast)
	var p := get_node_or_null("Player") as Node2D
	if p != null:
		_tut_last_pos = p.global_position


## 点红点吐司 → 直达对应入口
func _on_tut_toast(kind: String) -> void:
	match kind:
		"achievement":
			_open_achievement()
		"codex":
			_open_codex()
		"bag":
			CharacterPanel.open_panel()


## 累计走过多少像素：c1_move 用事件累计，不需要引导去反查玩家
func _tut_track_move() -> void:
	if Tutorial.active_chapter == "":
		return
	var p := get_node_or_null("Player") as Node2D
	if p == null:
		return
	var d := p.global_position.distance_to(_tut_last_pos)
	_tut_last_pos = p.global_position
	if d > 0.0 and d < 200.0:      # 传送 / 切场景的跳变不计
		Tutorial.note("moved", d)


# ===================== 靠近提示 =====================

## 某个设施的靠近状态变化（多个设施范围重叠时，后靠近的覆盖前一个）
func _on_facility_near(facility_id: String, is_near: bool) -> void:
	if is_near:
		_near_facility_id = facility_id
	else:
		# 只有离开的正是「当前靠近的那个」时才清掉
		if _near_facility_id == facility_id:
			_near_facility_id = ""
	_update_near_hint()


## 刷新靠近提示：有靠近的设施就常驻「按 F 进入」，否则收起
## ⚠ 与 _show_hint 的渐隐提示共用同一个 Label，所以这里要能中途接管：
##   先把进行中的渐隐 tween 掐掉，再写新文本，否则会出现「提示突然开始淡出」
func _update_near_hint() -> void:
	_refresh_enter_key()
	if not hint_label:
		return
	# 接管 Label：先掐掉正在渐隐的提示 tween
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = null
	if _near_facility_id == "":
		# 没有靠近的设施：恢复默认操作提示（常驻，不渐隐）
		hint_label.text = _default_hint_text
		hint_label.modulate.a = 1.0
		return
	if LOCKED_FACILITIES.has(_near_facility_id):
		# 封锁的设施不再喊「按 F 进入」：按下去只会响一声拒绝，靠近时就把话说清楚
		hint_label.text = "「%s」暂未开启，敬请期待" % String(LOCKED_FACILITIES[_near_facility_id])
		hint_label.modulate.a = 1.0
		return
	var gate := _facility_gate_reason(_near_facility_id)
	if gate != "":
		# 同上：还没解锁的设施要直接说出解锁条件，不能让玩家按了才知道进不去
		hint_label.text = "「%s」%s" % [_facility_name(_near_facility_id), gate]
		hint_label.modulate.a = 1.0
		return
	hint_label.text = "按 F 进入「%s」" % _facility_name(_near_facility_id)
	hint_label.modulate.a = 1.0


## 触屏「进入」键的三态回执（2026-11-13 用户定：不能让玩家按了才知道进不去）：
## 没靠近=「走近设施」压暗 / 封锁=「暂未开启」压暗 / 未解锁=写清条件压暗 / 可进=显设施名点亮。
## PC 上这颗键整层不可见，set_button_state 没有可见后果；键盘 F 的语义本来就没变。
func _refresh_enter_key() -> void:
	if _near_facility_id == "":
		VirtualPad.set_button_state("r_enter", "走近设施", false)
		return
	if LOCKED_FACILITIES.has(_near_facility_id):
		VirtualPad.set_button_state("r_enter", "暂未开启", false)
		return
	var gate := _facility_gate_reason(_near_facility_id)
	if gate != "":
		VirtualPad.set_button_state("r_enter", gate, false)
		return
	VirtualPad.set_button_state("r_enter", _facility_name(_near_facility_id), true)


## 按设施 id 找它的显示名（找不到就退回 id 本身）
## ⚠ Node.get() 只收 1 个参数（没有默认值重载），取值后要自己判 null
func _facility_name(facility_id: String) -> String:
	for node in $Facilities.get_children():
		var fid: Variant = node.get("facility_id")
		if fid != null and String(fid) == facility_id:
			var nm: Variant = node.get("facility_name")
			return String(nm) if nm != null else facility_id
	return facility_id


## 进度锁的当前状态：空串 = 已开放，否则是「差什么」的现算文案
## 文案直接从 WorldDB 取界域名，不在表里写死 —— 界域改名时这里跟着变
func _facility_gate_reason(facility_id: String) -> String:
	var prev_domain := String(GATED_FACILITIES.get(facility_id, ""))
	if prev_domain == "":
		return ""
	if CharacterData.is_domain_cleared(prev_domain):
		return ""
	return "通关%s后开启" % WorldDB.get_domain_name(prev_domain)


## ESC → 二次确认返回登录界面，防止误触（确认后才自动存档并切场景）
func _ask_return_title() -> void:
	ConfirmDialog.ask(
		"返回登录界面",
		"确定要返回登录界面吗？\n返回前会自动写入一个自动存档槽。",
		"返回登录",
		"继续游戏",
		_on_return_title_confirmed
	)


func _on_return_title_confirmed() -> void:
	GameState.return_to_title()


## 设施点击分发：当前仅弹出占位提示，各系统实现后在此接入对应界面
func _on_facility_activated(facility_id: String) -> void:
	# ⚠ 这里**不要**清 _near_facility_id：面板会盖住 HUD，提示看不见而已；
	#   关掉面板后还要靠它恢复「按 F 进入」（见 _process 里的面板失效检测）。
	# 暂未开启的设施：只给一句提示，不打开任何界面
	# 声音上也给"闷响"而不是"展开音"——玩家一听就知道点到了但进不去
	if LOCKED_FACILITIES.has(facility_id):
		GameState.play_ui("ui_deny")
		_show_hint("「%s」暂未开启，敬请期待。" % String(LOCKED_FACILITIES[facility_id]))
		return
	var gate := _facility_gate_reason(facility_id)
	if gate != "":
		GameState.play_ui("ui_deny")
		_show_hint("「%s」%s。" % [_facility_name(facility_id), gate])
		return
	match facility_id:
		"arena":
			_open_arena()
		"domain_gate":
			_open_domain_gate()
		"tower":
			_open_tower()
		"alchemy":
			_open_alchemy()
		"talisman":
			_open_talisman()
		"memory":
			_open_memory()
		"equipment":
			_open_equipment()
		"warehouse":
			_open_warehouse()
		"match":
			_open_match()
		_:
			_show_hint("未知设施：" + facility_id)


# ===== 各设施入口 =====

## 万界棋坛（卡片召唤自走棋）。
## ⚠ 不走 BattleResolver：那条路进的是 `combat_arena.tscn`（单人打 BOSS 的结算流程），
##   对局有自己的一套场景、胜负规则与结算，塞进 battle_context 反而要在那边加分支。
## 关卡制之后先进**棋谱长卷**挑哪一局，挑好了才落到对局场景；
## 关卡号由长卷写进 `GameState.match_context`（不是 battle_context，见那条注释）。
func _open_match() -> void:
	GameState.play_ui("ui_open")
	get_tree().change_scene_to_file("res://scenes/match/match_level_scroll.tscn")

## 演武场：训练木桩模式（可切功法 / 装备 / 背包，刷新功法 CD，记录伤害）
## 通过 BattleResolver 进入，战斗来源标记为 arena（无奖励、不结算）
func _open_arena() -> void:
	BattleResolver.start_arena()


## 万界秘境：查看万界位面（阶段2-C）
## 解锁全自动：首域默认开放，通关前一界域自动开放下一界域
func _open_domain_gate() -> void:
	_open_system_panel("res://scripts/ui/panels/domain_panel.gd")


func _open_tower() -> void:
	_open_system_panel("res://scripts/ui/panels/tower_panel.gd")


func _open_alchemy() -> void:
	_open_system_panel("res://scripts/ui/panels/alchemy_panel.gd")


func _open_talisman() -> void:
	_open_system_panel("res://scripts/ui/panels/talisman_panel.gd")


## 功法库（随身携带，仅原初位面可用）
func _open_skill_library() -> void:
	_open_system_panel("res://scripts/ui/panels/skill_panel.gd")


## ===================== 键位提示红圈（2026-10-24）=====================
## 有未查看的新功法 → 右上角 Y 外红圈；修为圆满 → Tab 外红圈。
## 新功法在功法库展开详情后逐项清除；突破后修为清零，红圈自动消失。

func _setup_new_skill_ring() -> void:
	if _new_skill_ring != null:
		return
	_new_skill_ring = _make_key_hint_ring("NewSkillRing")


func _setup_breakthrough_ring() -> void:
	if _breakthrough_ring != null:
		return
	_breakthrough_ring = _make_key_hint_ring("BreakthroughRing")


func _make_key_hint_ring(node_name: String) -> Control:
	var hud := get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		return null
	var ring := KeyHintRing.new()
	ring.name = node_name
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.z_index = 5
	ring.visible = false
	hud.add_child(ring)
	return ring


func _update_new_skill_ring() -> void:
	var show := CharacterData.has_new_skills() \
		and key_hint_label != null \
		and key_hint_label.text.begins_with("Y")
	_place_key_hint_ring(_new_skill_ring, "Y", show)


func _update_breakthrough_ring() -> void:
	_place_key_hint_ring(_breakthrough_ring, "Tab", CharacterData.has_breakthrough_pending())


## 把红圈套在 key_hint_label 里某段文字外（Y / Tab 共用）
## 优先用 Label 的逐字包围盒；拿不到时退回字体宽度估算。
func _place_key_hint_ring(ring: Control, needle: String, show: bool) -> void:
	if ring == null:
		return
	if not show or key_hint_label == null or not key_hint_label.is_visible_in_tree():
		ring.visible = false
		return
	var idx := key_hint_label.text.find(needle)
	if idx < 0:
		ring.visible = false
		return

	var pos := Vector2.ZERO
	var size := Vector2.ZERO
	var first := key_hint_label.get_character_bounds(idx)
	var last := key_hint_label.get_character_bounds(idx + needle.length() - 1)
	if first.size.x > 0.0 and first.size.y > 0.0 \
			and last.size.x > 0.0 and last.size.y > 0.0:
		var left := first.position.x
		var right := last.position.x + last.size.x
		var top := minf(first.position.y, last.position.y)
		var bottom := maxf(first.position.y + first.size.y, last.position.y + last.size.y)
		pos = key_hint_label.position + Vector2(left, top)
		size = Vector2(right - left, bottom - top)
	else:
		var font := key_hint_label.get_theme_font("font")
		var fs := key_hint_label.get_theme_font_size("font_size")
		if font != null:
			var text := key_hint_label.text
			var full_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var prefix_w := font.get_string_size(text.substr(0, idx), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var needle_w := font.get_string_size(needle, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			pos = key_hint_label.position + Vector2(key_hint_label.size.x - full_w + prefix_w, 0.0)
			size = Vector2(needle_w, key_hint_label.size.y)
		else:
			pos = key_hint_label.position
			size = key_hint_label.size

	var pad := 5.0
	ring.position = pos - Vector2(pad, pad)
	ring.size = size + Vector2(pad * 2.0, pad * 2.0)
	ring.visible = true
	ring.modulate.a = 0.72 + 0.28 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006))
	ring.queue_redraw()


## 红圈绘制：2px 红色空心椭圆（不新增美术资源；Y / Tab 复用）
class KeyHintRing extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var rx := maxf(2.0, size.x * 0.5 - 1.0)
		var ry := maxf(2.0, size.y * 0.5 - 1.0)
		var points := PackedVector2Array()
		for i in 40:
			var a := TAU * float(i) / 40.0
			points.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		if points.is_empty():
			return
		points.append(points[0])
		draw_polyline(points, Color(1.0, 0.22, 0.20, 0.95), 2.0, true)


func _open_memory() -> void:
	_open_system_panel("res://scripts/ui/panels/memory_panel.gd")


func _open_equipment() -> void:
	_open_system_panel("res://scripts/ui/panels/forge_panel.gd")


func _open_warehouse() -> void:
	_open_system_panel("res://scripts/ui/panels/warehouse_panel.gd")


## 打开一个系统界面：实例化 → 挂到 root → open（面板关闭时自行销毁）
## 同时只允许开一个面板，避免多个面板叠加导致暂停状态混乱
func _open_system_panel(script_path: String, configure := Callable()) -> void:
	if _current_panel:
		return
	var script = load(script_path)
	if script == null:
		_show_hint("界面加载失败：" + script_path)
		return
	var panel := script.new() as SystemPanel
	if panel == null:
		_show_hint("界面类型错误：" + script_path)
		return
	# ⚠ 注入必须在 add_child 之前：面板 _ready 里就把内容建完了（落哪一页也一样）
	if configure.is_valid():
		configure.call(panel)
	get_tree().root.add_child(panel)
	panel.closed.connect(_on_panel_closed)
	_current_panel = panel
	panel.open()


func _on_panel_closed() -> void:
	_current_panel = null


## 屏幕下方提示：短暂显示后渐隐
func _show_hint(text: String) -> void:
	if not hint_label:
		return
	hint_label.text = text
	hint_label.modulate.a = 1.0
	_hint_tween = hint_label.create_tween()
	_hint_tween.tween_interval(1.2)
	_hint_tween.tween_property(hint_label, "modulate:a", 0.0, 0.5)
	# 渐隐结束后恢复靠近提示：否则玩家点了个「暂未开启」之后，
	# 明明还站在设施旁边，「按 F 进入」却再也不出现了
	_hint_tween.tween_callback(_update_near_hint)
