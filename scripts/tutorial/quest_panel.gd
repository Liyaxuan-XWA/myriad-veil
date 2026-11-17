extends CanvasLayer
## 顺序任务面板（由 Quest 自动创建，不要手动挂到场景里）
##
## 2026-11-11 用户定（第二轮改版）：「面板太大，一次只显示一个任务，字体要大一点、清晰好辨认」：
##   - **只画当前任务**：第一行任务名（20px 暖宣纸色），下面一段怎么做（15px 系统无衬线）
##   - 做完一个 → Quest.changed → 自动换成下一个；12 个全完成显示「全部完成」
##   - 旧的 12 条列表已删（它把面板撑到 400px 高、11px 小字挤成一团）
##
## 2026-11-11 第三轮（用户）：「点收起后只剩一个可展开的小箭头按钮，不要留一条长框」：
##   收起 = 整块 `_box` 收掉，原位只留一个 30×30 的小按钮（自绘三角，非字体符号）。
##
## 2026-11-11 第四轮（用户：「太普通死板了，做成半透明质感」）—— 三层一起改，不是只调 alpha：
##   ① **质感**：底色从近乎不透明的 0.90 降到 0.55 档，卡面由 `QuestCardDeco` 现画一层
##      上亮下暗的受光渐变 + 1px 亮边/收边 + 左缘朱砂色脊。按 UIKit 的光影模型走，
##      **靠光影与留白分层，不加粗描边**（原来那圈 0.55 alpha 的整圈描边已撤）。
##   ② **图形读数**：标题下面一条「进度细杠」，已完成段暖金 + 末端亮点呼吸，
##      未完成段收暗 —— 数字保留（用户定的标题格式），这条是补充读数。
##   ③ **时间层次**（死板的主因是全场静止）：一道极淡的斜向流光缓慢扫过卡面
##      （峰值 alpha 0.055，是光泽不是闪光）、进度亮点呼吸、**换任务时整卡淡入 + 落位**、
##      收起态小箭头呼吸。
##
## ⚠ 可见性（2026-11-11 用户第二次收紧）：
##   **只在原初位面显示，且任何系统面板 / 角色面板 / 确认框打开时都藏起来。**
##   判据：`GameState.in_primordial_realm()` + `GameState.modal_ui_open()`。
## ⚠ 防变形：宽恒 300 + 只许换行不许撑宽 + 高度连续校准到收敛（首帧宽度 0 会算出假高度）。
## ⚠ 装饰层必须是 `_box` 的**第一个子节点**：PanelContainer 把所有子节点都铺满内容区，
##   谁先入树谁在底下。并且 `MOUSE_FILTER_IGNORE`，否则吞掉「收起」按钮的点击。
## ⚠ 美术后置：不引新贴图，配色全部取 `UIKit.C_* / EDGE_*`。

const PANEL_W := 300.0        ## 面板宽（比旧 272 略宽，给 15px 正文留出行宽）
const PANEL_Y := 184.0        ## 主城位置：接在「成就」按钮（y=128+48）下方
const PANEL_X := 20.0
const TAB_SIZE := 30.0        ## 收起后的小箭头按钮边长（用户要「小」，别做成长条）
const CARD_R := 7.0           ## 圆角半径（装饰层的边与角要跟 stylebox 对齐）
const PAD_L := 14.0
const PAD_R := 12.0
const PAD_T := 11.0
const PAD_B := 12.0

## 卡面底色：上亮下暗。**半透明质感是靠渐变做出来的**，不是把一整块颜色调薄——
## 一整块薄底只会发灰发脏，看不见材质。
## ⚠ 顶部透光、底部收稳：正文压在下面那半，底部太透会被地面纹理抢字。
const CARD_TOP := Color(0.158, 0.142, 0.116, 0.46)
const CARD_BOT := Color(0.030, 0.029, 0.026, 0.72)
const SHEEN_COLOR := Color(1.0, 0.96, 0.86)
## 流光透明度。**实测出来的数**：0.055 + 30px 窄带 + 5.6s 周期里 3.4s 静止，
## 整卡区域均值只抬升 0.06 灰阶 —— 截图上两张一模一样，等于没做。
## 加宽到 58px、静止窗收到 1.6s 后，均值抬升才进到肉眼读得出「光泽扫过」的量级。
const SHEEN_PEAK := 0.09
const SHEEN_SPAN := 58.0      ## 光带总宽（斜向铺开，不是硬边一条）
const SHEEN_SWEEP := 2.2      ## 扫一次用时
const SHEEN_CYCLE := 3.8      ## 一轮周期（扫 2.2 + 停 1.6）；停太长就回到「死板」
const SPINE_COLOR := Color(0.86, 0.36, 0.24)   ## 左缘朱砂色脊（全卡唯一的强调色，不给边框）


## 小三角图标：**自绘**，不用 `▾ / ▶` 这类字体符号
## ⚠ 泼墨字体缺几何符号（`→ / ◂` 会渲染成缺字小方点，项目里踩过），箭头只能画出来。
class FoldArrow extends Control:
	var pointing_down := true
	var arrow_color := Color(0.95, 0.82, 0.45, 0.95)

	func _draw() -> void:
		var w := minf(11.0, size.x * 0.55)
		var h := w * 0.62
		var cx := size.x * 0.5
		var cy := size.y * 0.5
		var pts := PackedVector2Array()
		if pointing_down:
			pts.append(Vector2(cx - w * 0.5, cy - h * 0.5))
			pts.append(Vector2(cx + w * 0.5, cy - h * 0.5))
			pts.append(Vector2(cx, cy + h * 0.5))
		else:
			pts.append(Vector2(cx - w * 0.5, cy + h * 0.5))
			pts.append(Vector2(cx + w * 0.5, cy + h * 0.5))
			pts.append(Vector2(cx, cy - h * 0.5))
		draw_colored_polygon(pts, arrow_color)


## 卡面装饰层：受光渐变 + 亮边/收边 + 左缘色脊 + 斜向流光。全部现画，不用贴图。
class QuestCardDeco extends Control:
	var _t := 0.0

	## 光带第 k 条线的两端 x（顶部 / 底部）。**两端都夹在左右内缘之间** ——
	## 卡面是圆角，越出去就会在面板外面露出一截亮线（2026-11-12 用户报的 bug）。
	## 抽成静态纯函数是为了让探针能直接验，不用去截像素。
	static func sheen_segment(cx: float, k: float, w: float) -> Vector2:
		var lo := CARD_R
		var hi := maxf(lo, w - CARD_R)
		var x_top := clampf(cx + k * SHEEN_SPAN, lo, hi)
		var x_bot := clampf(cx + k * SHEEN_SPAN - 26.0, lo, hi)
		return Vector2(x_top, x_bot)

	func _process(delta: float) -> void:
		# ⚠ 面板在战斗 / 其它场景是整块隐藏的，但 _process 照跑 —— 不挡掉就是
		#   每帧空转重绘一张看不见的卡。
		# ⚠ 用 is_visible_in_tree() 而不是 visible：面板整块隐藏时改的是父级标志位，
		#   子节点自己的 visible 仍然是 true，用后者守卫等于没写。
		if not is_visible_in_tree():
			return
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 8.0 or h < 8.0:
			return
		# ① 主体竖向渐变。圆角由底下的 stylebox 负责，这里只在 x∈[r/2, w-r/2] 的
		#    直边区间画横条，避免方角从圆角里戳出去。
		var bands := 10
		var span := maxf(1.0, h - CARD_R)
		for i in range(bands):
			var k := float(i) / float(bands)
			draw_rect(Rect2(CARD_R * 0.5, CARD_R + float(i) * (span / float(bands)),
					w - CARD_R, span / float(bands) + 1.0), CARD_TOP.lerp(CARD_BOT, k))
		# ② 顶部受光：1px 亮边之下再压一层向下渐隐的高光（同一个左上光源）。
		#    原来只压 6 段 ≈12px，静态截图上看不出上下差别，加到 10 段 22px。
		for i in range(10):
			var a := lerpf(0.10, 0.0, float(i) / 10.0)
			draw_rect(Rect2(CARD_R, 1.0 + float(i) * 2.2, w - CARD_R * 2.0, 2.2),
					Color(UIKit.EDGE_LIGHT.r, UIKit.EDGE_LIGHT.g, UIKit.EDGE_LIGHT.b, a))
		# ③ 1px 亮边（上/左 = 受光侧）+ 1px 收边（下/右 = 背光侧）+ 四角补弧。
		#    这就是「用光影代替粗描边」的具体做法。
		var lit := UIKit.EDGE_LIGHT
		var shade := UIKit.EDGE_SHADE
		draw_line(Vector2(CARD_R, 0.5), Vector2(w - CARD_R, 0.5), lit, 1.0)
		draw_line(Vector2(0.5, CARD_R), Vector2(0.5, h - CARD_R),
				Color(lit.r, lit.g, lit.b, lit.a * 0.7), 1.0)
		draw_line(Vector2(CARD_R, h - 0.5), Vector2(w - CARD_R, h - 0.5), shade, 1.0)
		draw_line(Vector2(w - 0.5, CARD_R), Vector2(w - 0.5, h - CARD_R), shade, 1.0)
		draw_arc(Vector2(CARD_R, CARD_R), CARD_R - 0.5, PI, PI * 1.5, 8, lit, 1.0)
		draw_arc(Vector2(w - CARD_R, CARD_R), CARD_R - 0.5, PI * 1.5, TAU, 8, lit, 1.0)
		draw_arc(Vector2(CARD_R, h - CARD_R), CARD_R - 0.5, PI * 0.5, PI, 8, shade, 1.0)
		draw_arc(Vector2(w - CARD_R, h - CARD_R), CARD_R - 0.5, 0.0, PI * 0.5, 8, shade, 1.0)
		# ④ 左缘朱砂色脊：向下渐隐，给整卡一个「哪里是头」的锚点。
		#    实机截图上 2px / 0.82 太弱、几乎看不见，收到 2.5px + 顶部 0.95 才立得住。
		var spine_h := maxf(1.0, h - CARD_R * 2.0 - 2.0)
		var segs := 12
		for i in range(segs):
			var k := float(i) / float(segs)
			draw_rect(Rect2(2.0, CARD_R + 1.0 + k * spine_h, 2.5, spine_h / float(segs) + 1.0),
					Color(SPINE_COLOR.r, SPINE_COLOR.g, SPINE_COLOR.b, lerpf(0.95, 0.06, k)))
		# ⑤ 斜向流光：SHEEN_SWEEP 扫一次，停 SHEEN_CYCLE-SHEEN_SWEEP 再扫。
		#    带内 14 条线按「中间亮两端淡」排布，两端再整体淡入淡出。
		# ⚠ 每条线的两端都夹在左右内缘之间（2026-11-12 用户报：流光越出面板右边）。
		#   旧版 cx 从 -0.30w 扫到 1.30w，卡外的线头直接画到了面板外面。
		var cycle := fposmod(_t, SHEEN_CYCLE)
		if cycle < SHEEN_SWEEP:
			var p := cycle / SHEEN_SWEEP
			var cx := lerpf(-0.30 * w, 1.30 * w, p)
			var fade := clampf(minf(p, 1.0 - p) * 4.0, 0.0, 1.0)
			for i in range(14):
				var k2 := float(i) / 13.0
				var a2 := SHEEN_PEAK * (1.0 - absf(k2 * 2.0 - 1.0)) * fade
				if a2 <= 0.001:
					continue
				var seg := sheen_segment(cx, k2, w)
				draw_line(Vector2(seg[0], CARD_R), Vector2(seg[1], h - CARD_R),
						Color(SHEEN_COLOR.r, SHEEN_COLOR.g, SHEEN_COLOR.b, a2), 3.2)


## 进度细杠：已完成段暖金 + 末端亮点呼吸，未完成段收暗。
class QuestRule extends Control:
	var ratio := 0.0
	var _t := 0.0

	func _process(delta: float) -> void:
		# ⚠ 用 is_visible_in_tree() 而不是 visible：面板整块隐藏时改的是父级标志位，
		#   子节点自己的 visible 仍然是 true，用后者守卫等于没写。
		if not is_visible_in_tree():
			return
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var mid := size.y * 0.5
		if w < 2.0:
			return
		# 凹槽必须画满全宽并且看得见：只画已完成段的话，读起来是「一条断头金线」，
		# 而不是「12 格里走了 4 格」—— 实机截图上就是这么翻车的。
		# 上唇受光 + 槽底收暗，做成刻进卡面的一道细沟。
		draw_rect(Rect2(0.0, mid - 1.25, w, 2.5),
				Color(UIKit.EDGE_LIGHT.r, UIKit.EDGE_LIGHT.g, UIKit.EDGE_LIGHT.b, 0.13))
		draw_rect(Rect2(0.0, mid - 0.5, w, 1.5), Color(0.0, 0.0, 0.0, 0.42))
		if ratio <= 0.0:
			return
		var fill := w * clampf(ratio, 0.0, 1.0)
		for i in range(8):
			var k := float(i) / 8.0
			draw_rect(Rect2(k * fill, mid - 0.9, fill / 8.0 + 1.0, 2.2),
					Color(lerpf(0.58, 0.98, k), lerpf(0.44, 0.84, k),
							lerpf(0.16, 0.44, k), 0.92))
		# 末端亮点：呼吸。这是整卡唯一持续动的东西，幅度要小
		var pulse := 0.5 + 0.5 * sin(_t * 2.4)
		var ex := fill - 1.0
		draw_circle(Vector2(ex, mid), 3.4, Color(1.0, 0.86, 0.46, 0.16 * pulse))
		draw_circle(Vector2(ex, mid), 1.8, Color(1.0, 0.92, 0.60, 0.60 + 0.35 * pulse))


var _box: PanelContainer = null
var _deco: QuestCardDeco = null
var _rule: QuestRule = null
var _head: HBoxContainer = null
var _title: Label = null
var _fold_btn: Button = null
var _name: Label = null
var _detail: Label = null
## 收起态唯一露出的东西：原位一个小箭头按钮，点它展开
var _tab_btn: Button = null
var _tab_arrow: FoldArrow = null
var _collapsed := false
var _fit_pending := false
## 上一次的「该不该显示」判定（场景切换与面板开关都没有信号 → 自己比对）
var _shown := false
## 上一次画的任务 id：变了才播入场动画（_refresh 会被反复调，不能每次都动）
var _last_id := ""


func _ready() -> void:
	layer = 118                        # 压在 HUD 之上、教学浮层(120)之下
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	Quest.changed.connect(_refresh)
	_shown = _should_show()
	_refresh()


func _build() -> void:
	_box = PanelContainer.new()
	_box.name = "QuestList"
	var sb := StyleBoxFlat.new()
	# 底只管圆角 + 柔投影 + 一层很薄的兜底色；真正的质感由下面的装饰层现画
	sb.bg_color = Color(CARD_BOT.r, CARD_BOT.g, CARD_BOT.b, 0.30)
	sb.set_corner_radius_all(int(CARD_R))
	# ⚠ 整圈描边撤掉：卡面的边由装饰层按「左上受光 / 背光收边」画，粗描边是页游感来源
	sb.set_border_width_all(0)
	# ⚠ 内容边距归零，让装饰层铺满整卡；实际留白由 MarginContainer 负责
	sb.content_margin_left = 0.0
	sb.content_margin_right = 0.0
	sb.content_margin_top = 0.0
	sb.content_margin_bottom = 0.0
	UIKit.apply_elevation(sb, UIKit.ELEV_CARD)
	_box.add_theme_stylebox_override("panel", sb)
	add_child(_box)

	# 装饰层必须**先入树**（PanelContainer 把每个子节点都铺满内容区，先画的在底下）
	_deco = QuestCardDeco.new()
	_deco.name = "Deco"
	_deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 兜底：以后往这层加装饰也不许画到卡外
	_deco.clip_contents = true
	_box.add_child(_deco)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", int(PAD_L))
	pad.add_theme_constant_override("margin_right", int(PAD_R))
	pad.add_theme_constant_override("margin_top", int(PAD_T))
	pad.add_theme_constant_override("margin_bottom", int(PAD_B))
	_box.add_child(pad)

	var col := UIKit.vbox(5)
	pad.add_child(col)

	_head = UIKit.hbox(6)
	col.add_child(_head)
	_title = UIKit.label("任务", UIKit.F_SMALL, UIKit.C_ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_head.add_child(_title)
	# 「收起」是次要操作 → 用 quiet（原来是普通按钮，跟任务名抢注意力）
	_fold_btn = UIKit.quiet_button("收起", Vector2(48.0, 22.0))
	_fold_btn.add_theme_font_size_override("font_size", UIKit.F_SMALL)
	_fold_btn.pressed.connect(_toggle_fold)
	_head.add_child(_fold_btn)

	# 进度细杠（图形读数），紧贴标题行下方
	_rule = QuestRule.new()
	_rule.name = "Rule"
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rule.custom_minimum_size = Vector2(0.0, 5.0)
	col.add_child(_rule)

	# 任务名：面板主体，20px 标题字（用户点名「字体大一点、清晰好辨认」）
	_name = UIKit.label("", UIKit.F_TITLE, UIKit.C_TITLE)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.custom_minimum_size = Vector2(0.0, 0.0)
	col.add_child(_name)

	# 怎么做：15px 系统无衬线（UIKit 规范：长说明一律 readable_*）
	_detail = UIKit.readable_label("", UIKit.F_SECTION, UIKit.C_TEXT)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(0.0, 0.0)
	_detail.add_theme_constant_override("line_spacing", 2)
	col.add_child(_detail)

	# 收起态：面板整块收掉，原位只留这个小箭头按钮（用户 2026-11-11：不要长框）
	_tab_btn = UIKit.button("", Vector2(TAB_SIZE, TAB_SIZE))
	_tab_btn.name = "QuestTab"
	_tab_btn.tooltip_text = "展开任务"
	_tab_btn.position = Vector2(PANEL_X, PANEL_Y)
	# ⚠ 显式给 size：CanvasLayer 不是 Container、不做布局，别依赖 Control 自己按
	#   custom_minimum_size 提尺寸这套隐式行为（换了主题/字体就可能变），写死才稳
	_tab_btn.size = Vector2(TAB_SIZE, TAB_SIZE)
	_tab_btn.visible = false
	_tab_btn.pressed.connect(_toggle_fold)
	add_child(_tab_btn)
	_tab_arrow = FoldArrow.new()
	_tab_arrow.pointing_down = true          # 收起 → 箭头朝下：面板从这里往下展开
	# ⚠ 必须 IGNORE：默认 STOP 会把点击吞掉，按钮永远按不动
	_tab_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tab_btn.add_child(_tab_arrow)
	_tab_arrow.resized.connect(_tab_arrow.queue_redraw)


func _toggle_fold() -> void:
	_collapsed = not _collapsed
	_refresh()


## 现在该不该露脸：只在原初位面，且没有任何模态界面（系统面板 / 背包 / 确认框）
func _should_show() -> bool:
	if not GameState.in_primordial_realm():
		return false
	return not GameState.modal_ui_open()


func _refresh() -> void:
	if _box == null:
		return
	# 不在原初位面 / 有面板开着：连小箭头一起藏掉，也不重建内容
	# （切回来时 _process 会再刷一次，收起状态本身保留）
	if not _should_show():
		_box.visible = false
		_tab_btn.visible = false
		_fit_pending = false
		return
	# 收起：主框整块收掉，原位只留一个小箭头按钮。
	# ⚠ 别再画「任务 6/12 · 名字」的长条 —— 用户 2026-11-11 明确否掉
	_box.visible = not _collapsed
	_tab_btn.visible = _collapsed
	_tab_btn.position = Vector2(PANEL_X, PANEL_Y)
	if _collapsed:
		_fit_pending = false
		return
	_box.position = Vector2(PANEL_X, PANEL_Y)
	_box.custom_minimum_size = Vector2(PANEL_W, 0.0)

	var prog := Quest.progress()
	var q: Dictionary = Quest.current_quest()
	var all_done := q.is_empty()
	var name_text := "全部完成" if all_done else String(q.get("title", ""))
	var detail_text := "十二个任务都做完了，接下来的路自己定。" if all_done \
		else String(q.get("detail", ""))
	_head.visible = true
	_fold_btn.visible = true
	_fold_btn.text = "收起"
	_title.text = "任务 · %d/%d" % [prog.x, prog.y]
	_name.text = name_text
	_detail.text = detail_text
	_name.visible = true
	_detail.visible = true
	var total := maxi(1, QuestDB.QUESTS.size())
	_rule.ratio = float(prog.x) / float(total)
	_rule.visible = true
	_fit_pending = true
	# 只有真的换了一张卡才播入场（同一个任务反复刷新不许抖）
	var now_id := String(q.get("id", "")) if not all_done else "__all__"
	if now_id != _last_id:
		_last_id = now_id
		_play_enter()


## 入场：整卡淡入 + 从左上微微落位。做完一个任务 → 新卡有明确「换上来了」的回执，
## 而不是文字原地闪一下（用户报「死板」的直接来源之一）。
func _play_enter() -> void:
	_box.pivot_offset = Vector2(0.0, maxf(1.0, _box.size.y) * 0.5)
	_box.modulate.a = 0.0
	_box.scale = Vector2(0.982, 0.982)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_box, "modulate:a", 1.0, 0.16)
	tw.tween_property(_box, "scale", Vector2.ONE, 0.18) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _process(_delta: float) -> void:
	# 场景切换 / 面板开合都没有信号可听 → 每帧比对判定，只在翻转那一帧重建
	var want := _should_show()
	if want != _shown:
		_shown = want
		_refresh()
	# 收起态的小箭头微微呼吸：一个「这里可以点」的活体回执（幅度小，不做闪光）
	if _tab_btn != null and _tab_btn.visible:
		_tab_btn.modulate.a = 0.78 + 0.22 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0028))
	# ⚠ PanelContainer 直接挂在 CanvasLayer 下（没有 Control 父级）时不会随内容收缩：
	#   首帧按「宽度≈1」算出的换行高度会把面板撑到 900+ px 且永不回落。
	#   每次重建内容后必须显式按最小尺寸重置一次，下一帧再校一次宽度。
	if _fit_pending:
		_fit_pending = false
		var want_w := _box.custom_minimum_size.x if _box.custom_minimum_size.x > 0.0 else _box.size.x
		var want_h := _box.get_combined_minimum_size().y
		if want_h > 0.0 and (not is_equal_approx(_box.size.x, want_w)
				or not is_equal_approx(_box.size.y, want_h)):
			_box.size = Vector2(want_w, want_h)
			# ⚠ 宽度一变，换行结果就变：首次构建时宽度还是 0，算出的高度会虚高到 2000+，
			#   只校一次就锁死在这个假高度上。必须下一帧按新宽度再算一遍，直到收敛。
			_fit_pending = true
