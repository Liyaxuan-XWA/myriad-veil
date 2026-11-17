extends Node
## 三才灵环自检（2026-11-11 用户第三轮：前两版「像板块、突兀、硬边、如出一辙、还不清晰」）
##
## 一条抱怨一条锁，另外把 v3 实机截图翻车的两处也各钉一条：
##   ① 「像板块 / 突兀」 → 子树里不许出现 Panel / ColorRect（有就是又画回控件了）
##   ② 「硬边」         → 只许 draw_arc(..., true)；不许 draw_rect / draw_polyline
##                        （4.7 没有 draw_set_antialiased，折线近似必然硬边）
##   ③ 「如出一辙」     → 血与灵必须占**不同角度区间**（左半 / 右半），
##                        精力必须是点阵而不是第三条弧
##   ④ 「不如原来清晰」 → 每半环弧长 ≥ 旧横条 38px 的两倍（椭圆周长 Ramanujan 近似）
##   ⑤ v3 翻车 A        → 精力点阵与环的**径向间距 ≥ 8px**，否则点会压在弧上糊成一团
##   ⑥ v3 翻车 B        → 上下两个缺口必须存在（整圈不闭合）：
##                        闭合正圆最容易被读成「判定范围」，也是笑脸构图的来源
##   ⑦ 状态管线与力竭归属（接口与上一版一致）
##
## ⚠ 常量取法坑：`load()` 回来的 GDScript 对象不能直接点常量，
##   `get_script_constant_map()` 也拿不到 —— 要 `.new()` 一个实例再读。
##
## 用法：godot --headless --path . res://tools/probe_resource_ring.tscn -- --no-save

const OLD_BAR_WIDTH := 38.0
const MIN_DOT_GAP := 8.0

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


## 椭圆周长（Ramanujan 近似）
func _perimeter(a: float, b: float) -> float:
	return PI * (3.0 * (a + b) - sqrt((3.0 * a + b) * (a + 3.0 * b)))


func _count_nodes(n: Node, type_name: String, acc: Array) -> void:
	if n.get_class() == type_name:
		acc.append(n.name)
	for c in n.get_children():
		_count_nodes(c, type_name, acc)


func _ready() -> void:
	print("\n########## 三才灵环自检 ##########")
	var ro = (load("res://scripts/ui/resource_ring.gd") as GDScript).new()
	var src: String = (FileAccess.open("res://scripts/ui/resource_ring.gd",
			FileAccess.READ) as FileAccess).get_as_text()

	# ===== ④ 清晰度：半环弧长必须碾压旧横条 =====
	var span_frac := (180.0 - 2.0 * float(ro.GAP_DEG)) / 360.0
	var arc_len := _perimeter(float(ro.RX), float(ro.RY)) * span_frac
	_check(arc_len >= OLD_BAR_WIDTH * 2.0, "每半环弧长 ≥ 旧横条两倍",
			"%.0fpx vs 旧 %.0fpx" % [arc_len, OLD_BAR_WIDTH])

	# ===== ③ 三种通道不同形 =====
	_check(ro.RX_SP < ro.RX and ro.RY_SP < ro.RY,
			"精力是内圈点阵，不是第三条弧", "点阵 %d/%d < 环 %d/%d" % [ro.RX_SP, ro.RY_SP, ro.RX, ro.RY])
	# 血占左半（90°→270°）、灵占右半（−90°→90°）：两半各自不超过 180°
	var half := PI - deg_to_rad(float(ro.GAP_DEG)) * 2.0
	_check(half < PI + 0.001, "血/灵各只占半环（左右分侧，不是两条同心弧）",
			"每半跨 %.0f°" % rad_to_deg(half))

	# ===== ⑤ 点阵与弧的径向间距（v3 就是栽在这里糊成一团）=====
	var gap := minf(float(ro.RX) - float(ro.RX_SP), float(ro.RY) - float(ro.RY_SP))
	_check(gap >= MIN_DOT_GAP, "精力点阵与环的径向间距 ≥ %dpx（不许压在弧上）" % int(MIN_DOT_GAP),
			"实测 %.0fpx" % gap)

	# ===== ⑥ 缺口存在：整圈不闭合 =====
	_check(float(ro.GAP_DEG) >= 5.0, "上下缺口 ≥ 5°（闭合正圆最易读成判定范围）",
			"%.0f°" % ro.GAP_DEG)

	# ===== ② 没有硬边 =====
	var rect_calls := 0
	var poly_calls := 0
	for line in src.split("\n"):
		var s := line.strip_edges()
		# ⚠ 只匹配真实调用行：源码注释里就写着「不用 draw_rect」，
		#   按整串 contains 判会被自己的注释误伤（第一版就这么假红过）
		if s.begins_with("draw_rect("):
			rect_calls += 1
		if s.begins_with("draw_polyline("):
			poly_calls += 1
	_check(rect_calls == 0, "不用 draw_rect（硬边来源之一）", "%d 处" % rect_calls)
	_check(poly_calls == 0, "不用 draw_polyline（4.7 无 draw_set_antialiased，折线必硬边）",
			"%d 处" % poly_calls)
	_check(src.contains("draw_arc(") and src.contains(", true)"),
			"所有弧都走 draw_arc 并开抗锯齿")

	# ===== ① 没有外壳 =====
	var p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	p.set("is_teleporting", false)
	var ring: Node = p.get("_ring")
	_check(ring != null, "灵环已挂到玩家节点下")
	if ring != null:
		var panels: Array = []
		var rects: Array = []
		_count_nodes(ring, "Panel", panels)
		_count_nodes(ring, "ColorRect", rects)
		_check(panels.is_empty() and rects.is_empty(),
				"环内没有任何外壳节点（Panel/ColorRect）",
				"panels=%s rects=%s" % [str(panels), str(rects)])
		# ===== v4 的真 bug：整条环只有一个 z，远侧也盖在人身上 → 「像贴图」 =====
		# 必须拆成前后两层：近侧 z>0 压过身体，远侧 z<0 藏到身体后面。
		var front_layer: Node = null
		var back_layer: Node = null
		for c in ring.get_children():
			if c.get("front") == true:
				front_layer = c
			elif c.get("front") == false:
				back_layer = c
		_check(front_layer != null and back_layer != null,
				"环拆成前后两层（只有一层就是 v4 的贴纸感）",
				"front=%s back=%s" % [str(front_layer), str(back_layer)])
		if front_layer != null and back_layer != null:
			_check(int(front_layer.z_index) > 0, "近侧层画在人物之前",
					"z=%d" % int(front_layer.z_index))
			_check(int(back_layer.z_index) < 0, "远侧层画在人物之后（尾部才会被身体挡住）",
					"z=%d" % int(back_layer.z_index))
		# 切分函数本身：一条跨越 180° 的弧必须被切成近/远两段，且两段拼起来等于原区间
		var cuts_f: Array = ro._clip_half(PI * 0.5, PI * 1.25, true)
		var cuts_b: Array = ro._clip_half(PI * 0.5, PI * 1.25, false)
		_check(cuts_f.size() == 1 and cuts_b.size() == 1,
				"跨中线的弧被正确切成近远两段", "front=%d back=%d" % [cuts_f.size(), cuts_b.size()])
		var total := 0.0
		for s in cuts_f + cuts_b:
			total += float(s[1]) - float(s[0])
		_check(absf(total - (PI * 0.75)) < 0.001, "两段拼起来等于原弧长（不丢角不重叠）",
				"%.4f vs %.4f" % [total, PI * 0.75])
		var cy := float(ring.position.y) + float(ring.size.y) * 0.5
		_check(cy < -8.0, "环心压在小腹而不是脚底（围周身 ≠ 站地上）", "center_y=%.1f" % cy)

		# ===== ⑦ 状态管线 =====
		p.set("hp", 50.0)
		p.call("_update_health_bar")
		_check(float(ring.get("_hit_flash")) > 0.0, "掉血触发血弧提亮回执")
		_check(absf(float(ring.get("_hp_ratio")) - 50.0 / float(p.get("max_hp"))) < 0.001,
				"血弧比例与玩家血量同源", "ring=%.3f" % float(ring.get("_hp_ratio")))

		p.set("mana", 0.0)
		p.call("_update_mana_bar")
		p.set("mana", float(p.get("max_mana")))
		p.call("_update_mana_bar")
		_check(float(ring.get("_mana_flow")) > 0.0, "灵力回升触发沿右弧爬动的亮点")

		p.set("max_stamina", 3)
		p.set("stamina", 2)
		p.call("_update_stamina_bar")
		_check(int(ring.get("_stamina_max")) == 3 and int(ring.get("_stamina")) == 2,
				"精力点数跟着属性走，不写死 5",
				"max=%d now=%d" % [int(ring.get("_stamina_max")), int(ring.get("_stamina"))])
		p.set("max_stamina", 5)
		p.set("stamina", 5)

		p.call("apply_debuff", "exhausted", 3.0, true)
		p.call("_refresh_exhaust_seal")
		_check(float(ring.get("_exhaust_left")) > 0.0, "力竭剩余时间已推给灵环点阵")
		_check(bool(p.call("has_debuff", "exhausted")), "力竭判定逻辑没动（只是显示搬走）")

		# ===== ⑧ 精力原点：金 / 闪光 / 见底闪红（2026-11-12 用户定）=====
		p.set("stamina", 3)
		p.call("_update_stamina_bar")
		ring.set("_t", 0.0)
		var gold: Color = ring.call("stamina_dot_color", 0)
		_check(gold.r > 0.9 and gold.g > 0.65 and gold.g < gold.r and gold.b < 0.6,
				"有精力的是**金色**原点（不是亮白）", str(gold))
		var off_dot: Color = ring.call("stamina_dot_color", 4)
		_check(off_dot.a < 0.3, "空的那几格仍是极淡的底", "a=%.2f" % off_dot.a)
		# 闪光：每颗错相位 + 随时间起伏（否则就是静态高光，用户会看回「朴素」）
		var tw0: float = ring.call("stamina_dot_twinkle", 0)
		var tw1: float = ring.call("stamina_dot_twinkle", 1)
		ring.set("_t", 0.4)
		var tw0_later: float = ring.call("stamina_dot_twinkle", 0)
		_check(absf(tw0 - tw1) > 0.05, "每颗原点的闪光相位错开（不是整排同步闪）",
				"%.2f vs %.2f" % [tw0, tw1])
		_check(absf(tw0 - tw0_later) > 0.05, "闪光随时间起伏（时间层次，不是静态）",
				"%.2f → %.2f" % [tw0, tw0_later])
		# 见底：整排告急红 + 呼吸；谷底也得看得见红
		p.set("stamina", 0)
		p.call("_update_stamina_bar")
		ring.set("_t", 0.0)
		var red_a: Color = ring.call("stamina_dot_color", 0)
		var red_b: Color = ring.call("stamina_dot_color", 4)
		_check(red_a.r > 0.9 and red_a.g < 0.4 and red_a.b < 0.4,
				"一格精力都没有 → 原点转告急红", str(red_a))
		_check(absf(red_a.r - red_b.r) < 0.001 and absf(red_a.a - red_b.a) < 0.001,
				"见底时整排同色同拍（不是只有第一颗在闪）", str(red_b))
		_check(red_a.a >= 0.3, "呼吸谷底也是看得见的红（不靠碰运气）", "a=%.2f" % red_a.a)
		ring.set("_t", 0.37)
		var red_later: Color = ring.call("stamina_dot_color", 0)
		_check(absf(red_a.a - red_later.a) > 0.05, "红是呼吸的（有闪动回执，不是死红）",
				"a %.2f → %.2f" % [red_a.a, red_later.a])

		# ===== ⑨ 柔边：弧是「多层由宽到窄」叠出来的，不是一条线 =====
		var layers: Array = ro.ARC_LAYERS
		var mono := true
		for k in range(1, layers.size()):
			if float(layers[k][0]) >= float(layers[k - 1][0]):
				mono = false
			if float(layers[k][1]) <= float(layers[k - 1][1]):
				mono = false
		_check(layers.size() >= 4 and mono,
				"气血/灵力弧 ≥4 层柔光：由宽到窄、由淡到亮（「硬边」的解法）",
				"%d 层" % layers.size())
		_check(float(layers[layers.size() - 1][0]) <= 2.0 and float(ro.CORE_W) <= 2.0,
				"灯芯 ≤2px（再粗就回到一条线）", "core=%.1f" % float(ro.CORE_W))
	else:
		_check(false, "灵环没挂上，后续状态锁全部跳过")

	# ===== 标签栏排除力竭（真实竞技场）=====
	var arena = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	var a_player: Node = arena.get("player")
	if a_player != null:
		a_player.call("apply_debuff", "exhausted", 3.0, true)
		a_player.call("apply_debuff", "stun", 2.0, true)
		arena.call("_update_debuff_bar")
		var rows: Dictionary = arena.get("_debuff_rows")
		_check(not rows.has("exhausted"), "debuff 标签栏不再常驻力竭那一行", str(rows.keys()))
		_check(rows.has("stun"), "其它 debuff 标签照常显示（只排除力竭）")
	else:
		_check(false, "竞技场没拿到 player", "力竭标签归属未验")
	arena.queue_free()
	await get_tree().process_frame
	ro.free()

	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
