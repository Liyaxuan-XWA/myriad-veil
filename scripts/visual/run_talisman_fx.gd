extends RefCounted
class_name RunTalFx
## 试炼四符的**局内演出**（2026-11-10）。
##
## 之前这一族只有飘字：`_run_tal_cast` 结算完就没了，玩家根本看不出符飞没飞出去。
## 本文件补齐四类表现，全部程序合成（复用 SkillFx 的 dot / ring / star 纹理），
## 不新增贴图，换美术时只改 ArtDB.ELEMENT_COLORS 就能整体换色。
##
##   cast()    施符：手里那张符浮起 → 亮闪 → 碎成元素光飞向目标
##   impact()  命中：元素色爆闪 + 冲击环（半径跟着技能实际范围走）
##   beam()    直线 / 连锁：两点之间的柔光带
##   shell()   自身增益（石甲 / 霜甲 / 折光 / 护盾）绕身符文
##
## ⚠ 三条硬约束：
##   1. **不要在这里算伤害或改状态** —— 本文件只画，结算全在 player 的 `_run_tal_*`。
##   2. 所有节点自带 Tween 自动释放，调用方不要持有引用（fire-and-forget）。
##   3. 节点一律 `add_child` 之后再写 `global_position`：host 自身有缩放/位移时，
##      先定位再挂树会算错（战斗场景根节点就是缩放过的）。

const FLASH_LIFE := 0.24
const RING_LIFE := 0.34


# =====================================================================
# 施符
# =====================================================================
## via_chain = 连携出来的那一张：从侧后方起手、整体缩一号、节奏更快，
## 让玩家一眼看出「这张不是我按的」。
static func cast(caster: Node2D, base_id: String, element: String, aim: Vector2,
		via_chain: bool = false) -> void:
	if caster == null or not caster.is_inside_tree():
		return
	var host := caster.get_parent()
	if host == null:
		return
	var color: Color = ArtDB.element_color(element)
	var dir := aim - caster.global_position
	if dir.length_squared() < 4.0:
		dir = Vector2.RIGHT
	dir = dir.normalized()

	var holder := Node2D.new()
	holder.z_index = 32
	host.add_child(holder)
	var side := Vector2(-dir.y, dir.x) * (-1.0 if via_chain else 1.0)
	# ⚠ 位置/尺寸踩过三轮，结论按**角色身高**（实测屏幕高约 50px）来定：
	#   -34 直接糊住上半身；-66 时符纸底边离头顶只剩 13px，碎裂白闪正砸在头上，
	#   截图里角色整颗头都是白的 → 改成 -74 与 36px，头顶留出约 30px 空档。
	#   符纸一旦比角色还高，玩家就看不清自己在往哪走，这族最显眼的东西必须是「浮在头顶」而不是「贴在脸上」。
	holder.global_position = caster.global_position + Vector2(0.0, -74.0) \
		+ dir * (10.0 if via_chain else 20.0) + side * (24.0 if via_chain else 8.0)

	var scale_mul := 0.82 if via_chain else 1.0
	var paper := Sprite2D.new()
	paper.texture = _card_texture(base_id)
	if paper.texture != null:
		# 36px ≈ 角色的 0.72 倍：整张卡面（朱砂框 + 符文）在这个尺寸下仍然认得出
		var s := 36.0 * scale_mul / maxf(float(paper.texture.get_height()), 1.0)
		paper.scale = Vector2(s, s)
	else:
		paper.texture = SkillFx.dot_texture()
		paper.material = SkillFx.additive_material()
		paper.scale = Vector2(0.34, 0.34) * scale_mul
	paper.centered = true
	paper.modulate = Color(1.0, 1.0, 1.0, 0.0)
	paper.rotation = randf_range(-0.16, 0.16)
	holder.add_child(paper)

	var spent := 0.30 if via_chain else 0.38
	# 1) 浮起：从手心冒出来
	var intro := paper.create_tween().set_parallel(true)
	intro.tween_property(paper, "modulate:a", 1.0, 0.08)
	intro.tween_property(paper, "scale", paper.scale * (1.14 if via_chain else 1.22), 0.11) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	intro.tween_property(holder, "global_position",
		holder.global_position + dir * 12.0 + Vector2(0.0, -6.0), 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 2) 碎裂：闪一下、符纸淡掉、元素光朝目标喷出去
	# ⚠ 回调里只捕获 **instance_id**：直接捕获 node 的话，节点先被释放时
	#   Godot 会打印 "Lambda capture at index 0 was freed"（探针清场必现）。
	var host_id := host.get_instance_id()
	var holder_id := holder.get_instance_id()
	var burst := paper.create_tween()
	burst.tween_interval(0.085)
	burst.tween_callback(func() -> void:
		var h := instance_from_id(host_id) as Node
		var hp := instance_from_id(holder_id) as Node2D
		if h == null or hp == null or not h.is_inside_tree():
			return
		var at := hp.global_position
		# ⚠ 闪光半径要跟着符纸一起收：52 时白斑直径 100px，正好盖住整颗头
		_flash(h, at, color, 34.0 * scale_mul, 0.24)
		_burst(h, at, color, 10 if via_chain else 14, 150.0)
		_shot(h, at, dir, color, via_chain)
	)
	burst.tween_property(paper, "modulate:a", 0.0, 0.12)
	burst.parallel().tween_property(paper, "scale", paper.scale * 1.18, 0.12)
	burst.tween_interval(spent)
	burst.tween_callback(holder.queue_free)


## 从符纸位置射向目标的一颗元素光球（纯装饰：命中判定早已结算，这里只是「看起来飞过去了」）
static func _shot(host: Node, from: Vector2, dir: Vector2, color: Color,
		via_chain: bool) -> void:
	var ball := Sprite2D.new()
	ball.texture = SkillFx.dot_texture()
	ball.material = SkillFx.additive_material()
	ball.centered = true
	ball.z_index = 33
	ball.modulate = Color(color.r, color.g, color.b, 0.95)
	ball.scale = Vector2(0.12, 0.12) * (0.8 if via_chain else 1.0)
	host.add_child(ball)
	ball.global_position = from

	var tw := ball.create_tween().set_parallel(true)
	tw.tween_property(ball, "global_position", from + dir * 240.0, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(ball, "scale", Vector2(0.30, 0.16), 0.16)
	tw.tween_property(ball, "modulate:a", 0.0, 0.16).set_delay(0.05)
	tw.chain().tween_callback(ball.queue_free)


# =====================================================================
# 命中
# =====================================================================
## radius：这一击的**实际作用半径**（单体传 40 左右），环就按它铺开，
## 玩家能靠圈的大小读出「这张符打多远」。
static func impact(host: Node, at: Vector2, element: String, radius: float,
		heavy: bool = false) -> void:
	if host == null or not host.is_inside_tree():
		return
	var color: Color = ArtDB.element_color(element)
	_flash(host, at, color, maxf(26.0, radius * 0.36), FLASH_LIFE)
	_ring(host, at, color, maxf(34.0, radius), RING_LIFE)
	if heavy:
		# 大范围/变体技能：再来一圈错开 0.07 秒的大环，读作「余波」
		_ring(host, at, color, maxf(46.0, radius * 1.28), RING_LIFE * 1.15, 0.07)
	_burst(host, at, color, 12 if heavy else 7, 190.0 if heavy else 130.0)


# =====================================================================
# 直线 / 连锁
# =====================================================================
static func beam(host: Node, from: Vector2, to: Vector2, element: String,
		width: float = 26.0) -> void:
	if host == null or not host.is_inside_tree():
		return
	var d := to - from
	var ln := d.length()
	if ln < 8.0:
		return
	var color: Color = ArtDB.element_color(element)
	var ang := d.angle()
	var mid := from + d * 0.5
	for i in 2:
		var spr := Sprite2D.new()
		spr.texture = SkillFx.dot_texture()
		spr.material = SkillFx.additive_material()
		spr.centered = true
		spr.z_index = 33
		var w := width * (1.0 if i == 0 else 0.42)
		spr.scale = Vector2(ln / 128.0, w / 128.0)
		spr.rotation = ang
		spr.modulate = Color(color.r, color.g, color.b,
			0.34 if i == 0 else 0.62)
		host.add_child(spr)
		spr.global_position = mid
		var tw := spr.create_tween()
		tw.tween_property(spr, "modulate:a", 0.0, 0.20 if i == 0 else 0.14)
		tw.parallel().tween_property(spr, "scale:y", w / 128.0 * 0.25, 0.20)
		tw.tween_callback(spr.queue_free)


## 连携引线：两张符之间一道很细的元素色短线，告诉玩家「这两张是一起出的」
static func chain_link(host: Node, from: Vector2, to: Vector2, element: String) -> void:
	beam(host, from, to, element, 12.0)


# =====================================================================
# 自身增益：绕身符文
# =====================================================================
## kind: "stone"（石甲，土黄方环）/ "frost"（霜甲，冰蓝）/ "reflect"（折光，金）
##       / "shield"（通用护盾）/ "haste"（风疾，青绿）
##
## 两件东西叠出来：贴身的柔光环 + 绕身转的元素符文。
## ⚠ 光环直径 102px（角色身高约 50px）——第一版 0.86×256 = 220px，比人物大四倍，
##   读作「地上画了个圈」而不是「身上套了层甲」（截图验证过）。
## ⚠ 光靠转光环没有任何视觉效果：ring_texture 只有 3% 的角向抖动，近似旋转对称，
##   转了等于没转 → 必须再贴几个元素符号，玩家才看得出「符在绕着我转」。
static func shell(caster: Node2D, kind: String, element: String, duration: float) -> void:
	if caster == null or not caster.is_inside_tree():
		return
	var color: Color = ArtDB.element_color(element)
	var tex := SkillFx.ring_texture()
	var ring := Sprite2D.new()
	ring.texture = tex
	ring.material = SkillFx.additive_material()
	ring.centered = true
	# ⚠ 不能用 z_index = -1：战场地面是一层铺满的 TextureRect，负 z 会被它整个吃掉
	#   （第一次截图里石甲环完全看不见，就是这条）。
	# 2 = 压在符阵（z=1）之上：连携经常会顺带放出雷狱/潮汐阵，
	#   同层的话后建的阵会把绕身环整圈盖掉（截图验证过）。
	ring.z_index = 2
	ring.modulate = Color(color.r, color.g, color.b, 0.0)
	ring.scale = Vector2(0.26, 0.26)
	caster.add_child(ring)
	ring.position = Vector2(0.0, 4.0)

	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "modulate:a", 0.50, 0.14)
	tw.tween_property(ring, "scale", Vector2(0.40, 0.40), 0.24) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 到期前 0.35 秒开始淡出
	var out := ring.create_tween()
	out.tween_interval(maxf(duration - 0.35, 0.05))
	out.tween_property(ring, "modulate:a", 0.0, 0.35)
	out.tween_callback(ring.queue_free)

	# 绕身符文：四个元素汉字按 90° 铺开，整体绕角色匀速转
	# ⚠ 别拿技能栏那张元素图标当符文：图标是「深墨圆角底 + 元素色细边」的方形贴图，
	#   加色混合后底板会显成一块浮在半空的深色方片，读作 UI 卡片而不是符文（截图验证过）。
	#   改用 AttributeDB.ELEMENT_NAMES 的汉字：20px 下单个「土」仍然一眼可辨，
	#   而且和十张符的 glyph 是同一套字，视觉语言统一。
	var rune := String(AttributeDB.ELEMENT_NAMES.get(element, ""))
	if rune == "" or rune == "无":
		return
	var pivot := Node2D.new()
	pivot.z_index = 2
	caster.add_child(pivot)
	pivot.position = Vector2(0.0, 4.0)

	var orbit := 42.0
	var font := UIKit.readable_font()
	var half := Vector2(15.0, 15.0)
	for i in 4:
		var g := Label.new()
		g.text = rune
		g.add_theme_font_override("font", font)
		g.add_theme_font_size_override("font_size", 19)
		g.add_theme_color_override("font_color", color)
		# 描边同色 = 加粗 + 一圈柔光，比纯色字更像「燃着的符文」
		g.add_theme_color_override("font_outline_color", Color(color.r, color.g, color.b, 0.55))
		g.add_theme_constant_override("outline_size", 5)
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		g.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		g.size = half * 2.0
		g.modulate = Color(1.0, 1.0, 1.0, 0.0)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 世界里的 Control 别去抢 UI 的鼠标
		pivot.add_child(g)
		var ang := PI * 0.25 + TAU * float(i) / 4.0   # 45° 起：正上方留给血条
		g.position = Vector2(cos(ang), sin(ang)) * orbit - half
		var gi := g.create_tween()
		gi.tween_property(g, "modulate:a", 1.0, 0.16).set_delay(0.05 * float(i))

	# ⚠ 不能直接转 pivot：汉字跟着一起倾斜，转到 90° 时「土」会躺下，看着像坏了。
	#   用 tween_method 每帧只算**位置**，字始终保持正立。
	var pivot_id := pivot.get_instance_id()
	var speed := 2.2 if kind == "reflect" else -1.6
	var span := maxf(duration, 0.4)
	var orbit_tw := pivot.create_tween()
	orbit_tw.tween_method(func(a: float) -> void:
		var p := instance_from_id(pivot_id) as Node2D
		if p == null:
			return
		for k in p.get_child_count():
			var gl := p.get_child(k) as Control
			if gl == null:
				continue
			var th := a + PI * 0.25 + TAU * float(k) / 4.0
			gl.position = Vector2(cos(th), sin(th)) * orbit - half
	, 0.0, speed * span, span).set_trans(Tween.TRANS_LINEAR)

	# 折光反向快转（光的仪式感），其余缓慢顺转；角速度固定，时长再长也不会甩晕
	var pivot_out := pivot.create_tween()
	pivot_out.tween_interval(maxf(duration - 0.35, 0.05))
	pivot_out.tween_property(pivot, "modulate:a", 0.0, 0.35)
	pivot_out.tween_callback(pivot.queue_free)


# =====================================================================
# 底层合成
# =====================================================================
static func _flash(host: Node, at: Vector2, color: Color, radius: float,
		life: float) -> void:
	var spr := Sprite2D.new()
	spr.texture = SkillFx.dot_texture()
	spr.material = SkillFx.additive_material()
	spr.centered = true
	spr.z_index = 33
	spr.modulate = Color(color.r, color.g, color.b, 0.0)
	spr.scale = Vector2(0.18, 0.18)
	host.add_child(spr)
	spr.global_position = at
	var s := maxf(radius, 12.0) / 58.0
	# ⚠ 加色混合下大光斑会整片糊白（石甲碎裂 220 半径时半个屏幕发灰）：
	#   半径越大峰值压得越低，大范围读作「余波」而不是「闪光灯」
	var peak := 0.72 * clampf(1.0 - (s - 0.7) * 0.30, 0.42, 1.0)
	var tw := spr.create_tween()
	tw.tween_property(spr, "modulate:a", peak, life * 0.16)
	tw.parallel().tween_property(spr, "scale", Vector2(s, s), life) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(spr, "modulate:a", 0.0, life * 0.42)
	tw.tween_callback(spr.queue_free)


static func _ring(host: Node, at: Vector2, color: Color, radius: float,
		life: float, delay: float = 0.0) -> void:
	var spr := Sprite2D.new()
	spr.texture = SkillFx.ring_texture()
	spr.material = SkillFx.additive_material()
	spr.centered = true
	spr.z_index = 1            # 地面圈：压在角色下面
	spr.modulate = Color(color.r, color.g, color.b, 0.0)
	spr.scale = Vector2(0.16, 0.16)
	spr.rotation = randf_range(-0.4, 0.4)
	host.add_child(spr)
	spr.global_position = at
	var s := maxf(radius, 24.0) / 108.0
	# ⚠ 同上：半径 220 的环在加色下是一条刺眼的白带 → 圈越大峰值越低
	var peak := 0.55 * clampf(1.0 - (s - 1.0) * 0.26, 0.36, 1.0)
	var tw := spr.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(spr, "modulate:a", peak, 0.05)
	tw.parallel().tween_property(spr, "scale", Vector2(s, s), life) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(spr, "modulate:a", 0.0, life * 0.55)
	tw.tween_callback(spr.queue_free)


static func _burst(host: Node, at: Vector2, color: Color, amount: int,
		speed: float) -> void:
	var p := SkillFx.make_particles(SkillFx.star_texture(), maxi(amount, 4), 0.36, 34, true)
	host.add_child(p)
	p.global_position = at
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2(0.0, 60.0)
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.damping_min = speed * 0.8
	p.damping_max = speed * 1.3
	p.scale_amount_min = 0.08
	p.scale_amount_max = 0.22
	p.color = color
	p.restart()
	p.emitting = true
	# 自动回收交给 Timer 子节点：粒子被释放时它一起没，不需要回调里判存活
	var killer := Timer.new()
	killer.one_shot = true
	killer.wait_time = 1.1
	p.add_child(killer)
	killer.timeout.connect(p.queue_free)
	killer.start()


static func _card_texture(base_id: String) -> Texture2D:
	var path := String(ArtDB.talisman_style(base_id).get("card", ""))
	if path != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null
