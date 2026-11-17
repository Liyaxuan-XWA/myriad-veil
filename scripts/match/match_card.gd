class_name MatchCard
extends RefCounted
## 棋盘模式的「这张牌长什么样」唯一出口（2026-11-04）
##
## 以前这里就是两张平铺的图：手牌一张 TextureRect 贴原画、棋盘一张 Sprite2D 贴原画，
## 没有框、没有圆角、没有厚度、名字还写在图外面 —— 用户的原话是「像一张图平铺在面前」。
## 卡包那边早就有一整套卡片语言（CardFace：圆角 + 双层金框 + 四角金线 + 底部名牌 + 华彩流彩），
## 所以这里**不自造第二套**：
##   · UI（选牌 / 锁定 / 布阵 / 出手 / 结算）→ 直接挂 CardFace，与卡包封面同一支渲染器；
##   · 世界（棋盘上的棋子卡）→ MatchCardToken 用同一套参数叠出圆角、金框、投影与名牌。
## 两边共用 cover_style() 与 accent()，所以「我在卡包里挑的就是场上那张牌」是看得出来的。

## 圆角半径 = 短边的 4.5%，夹在 6~20px（与 CardFace._sync_geometry 同一个口径，别各写一套）
const CORNER_FRAC := 0.045
const CORNER_MIN := 6.0
const CORNER_MAX := 20.0
## 棋盘卡面烘进内存的尺寸（2:3，与图鉴原画同比例）
const ART_BAKE_W := 256
const ART_BAKE_H := 384

static var _style_cache: Dictionary = {}
static var _back_tex: ImageTexture = null
static var _rounded_cache: Dictionary = {}


## 卡面种类（对局界面那一排切换按钮的取值）。
## "" = 跟随卡包：取玩家自己卡包里当封面展示的那一张（ordered_variants 的第一位，
##     他在收藏册里拖动卡序改的就是这个顺序 —— achievement_view._make_boss_cell 同一口径）。
const KINDS: Array = [
	{"id": "", "label": "跟随卡包"},
	{"id": "portrait", "label": "原画"},
	{"id": "scene", "label": "华彩·有背景"},
	{"id": "plain", "label": "华彩·无背景"},
	{"id": "ink", "label": "水墨"},
]


static func kind_label(kind: String) -> String:
	for k in KINDS:
		if String(k["id"]) == kind:
			return String(k["label"])
	return "跟随卡包"


## 这张卡用哪一档渲染。
## `want` 是玩家选的种类；该档**没解锁就回退到封面**（棋盘要显示对手没打到的卡，
## 不能因为没解锁就画不出来）。一位都没解锁过时用全量 card_variants 兜底。
static func cover_style(boss_id: String, want: String = "") -> Dictionary:
	var cache_key := "%s|%s" % [boss_id, want]
	if _style_cache.has(cache_key):
		return _style_cache[cache_key]
	var e: Dictionary = CodexDB.card_entry(boss_id)
	var owned: Array = CodexDB.ordered_variants(e)
	var source: Array = owned if not owned.is_empty() else (e.get("card_variants", []) as Array)
	var out: Dictionary = {}
	if want != "":
		for raw in source:
			var v: Dictionary = raw
			if String(v.get("id", "")) != want:
				continue
			if _usable(v):
				out = v.duplicate(true)
				break
	if out.is_empty():
		for raw in source:
			var v2: Dictionary = raw
			if _usable(v2):
				out = v2.duplicate(true)
				break
	if out.is_empty():
		var portrait := String(CodexDB.boss_entry(boss_id).get("portrait", ""))
		if portrait != "" and ResourceLoader.exists(portrait):
			out = {"id": "match_portrait", "kind": "still", "art": portrait}
	_style_cache[cache_key] = out
	return out


## 「原画 + 普通卡框」：不读玩家卡包偏好，也不读解锁进度。
## 棋盘上凡是「不由玩家收集进度决定」的牌都走这里（敌方卡 / 开局补发卡）。
static func portrait_style(boss_id: String) -> Dictionary:
	var portrait := String(CodexDB.boss_entry(boss_id).get("portrait", ""))
	if portrait == "" or not ResourceLoader.exists(portrait):
		return cover_style(boss_id, "")
	var out: Dictionary = CodexDB.PORTRAIT_CARD_STYLE.duplicate(true)
	out["art"] = portrait
	return out


## 敌方卡面固定用**原版**（图鉴原画 + 普通卡框），2026-11-05 用户定。
##
## 为什么不走 cover_style()：那条路先读玩家自己的卡包偏好（match_card_kind），
## 再按玩家自己的解锁进度逐张回退 —— 于是对手那 6 张里，打过的显示水墨、
## 没打过的显示华彩，一片花花绿绿；更糟的是它把「你打到哪了」写进了对手的外观里。
## 关卡制早就定了对手卡组不读解锁进度，卡面这一层之前漏了。
static func opponent_style(boss_id: String) -> Dictionary:
	return portrait_style(boss_id)


## 玩家侧卡面（2026-11-10 用户：开局不足 6 张时补出来的牌必须是普通卡，不能是华彩）。
## 根因链：fill_pool 补的是 `!CodexDB.is_boss_unlocked()` 的 BOSS ⇒ 这类 BOSS 四张
##   variant 的 `unlocked` 全是 false ⇒ cover_style 里 `ordered_variants` 为空 ⇒
##   退回全量 card_variants ⇒ 取第一个可用项，而那个位置正是「华彩·有背景」
##   （codex_db.gd 自己注明「默认封面，排第一」）。敌方 2026-11-05 已用
##   opponent_style 绕开这条回退链，玩家补牌是同一根因的另一半。
## ⚠ 不改 cover_style() 本身：卡包收藏册里「未解锁的封面怎么显示」是另一回事，
##   probe_match_cards 那组断言守的就是它。
## ⚠ 用 ordered_variants 是否为空做判据，正好等价于 fill_pool 的补牌集合
##   （普通卡 unlocked = boss_cleared = is_boss_unlocked），不用往 MatchState.cards
##   里塞额外标记，也不会让已经收集到的牌丢掉玩家选的档位。
static func player_style(boss_id: String, want: String = "") -> Dictionary:
	var e: Dictionary = CodexDB.card_entry(boss_id)
	if CodexDB.ordered_variants(e).is_empty():
		return portrait_style(boss_id)
	return cover_style(boss_id, want)


## 这一档到底画不画得出来：华彩缺背景或缺线层 → HoloCardView.configure() 会返回 false，
## 与其到渲染时才崩，这里就当它不可用、回退到封面。
static func _usable(v: Dictionary) -> bool:
	var art := String(v.get("art", ""))
	if art == "" or not ResourceLoader.exists(art):
		return false
	if String(v.get("kind", "holo")) != "holo":
		return true
	var bg := String(v.get("bg", ""))
	var ln := String(v.get("lines", ""))
	return bg != "" and ResourceLoader.exists(bg) and ln != "" and ResourceLoader.exists(ln)


## 换档 / 换卡序之后必须清一次：两张缓存都按 boss_id 记账，不清就是旧图。
static func clear_cache() -> void:
	_style_cache.clear()
	_rounded_cache.clear()


static func accent(boss_id: String) -> Color:
	var e: Dictionary = CodexDB.card_entry(boss_id)
	var c = e.get("card_accent", null)
	if c is Color:
		return c as Color
	return Color(0.86, 0.72, 0.42, 1.0)


static func corner_radius(short_edge: float) -> float:
	return clampf(short_edge * CORNER_FRAC, CORNER_MIN, CORNER_MAX)


## 圆角矩形轮廓（以原点为中心，顺时针一圈，首尾重合）—— 描边与填充共用
static func rounded_points(w: float, h: float, r: float, seg: int = 6) -> PackedVector2Array:
	var hw := w * 0.5
	var hh := h * 0.5
	var rr := minf(minf(r, hw), hh)
	var pts := PackedVector2Array()
	if rr <= 0.5:
		pts.append(Vector2(-hw, -hh)); pts.append(Vector2(hw, -hh))
		pts.append(Vector2(hw, hh)); pts.append(-Vector2(hw, hh))
		pts.append(Vector2(-hw, -hh))
		return pts
	var centers := PackedVector2Array([Vector2(hw - rr, -hh + rr), Vector2(hw - rr, hh - rr),
			Vector2(-hw + rr, hh - rr), Vector2(-hw + rr, -hh + rr)])
	# ⚠ 用 PackedFloat64Array 而不是普通 Array：`start_turn[i]` 取出来是 Variant，
	#   再写 `var a := (Variant + float)` 会「Cannot infer the type of "a"」直接编译不过
	var start_turn := PackedFloat64Array([-0.25, 0.0, 0.25, 0.5])
	for i in 4:
		for s in seg + 1:
			# ⚠ 每个角只扫 **1/4 圈**。第一版写成 `start + s/seg`（整圈），
			#   四个角各绕一整圈 → 多边形自交 → draw_colored_polygon 报
			#   "Invalid polygon data, triangulation failed"，投影和卡套直接不画。
			var a: float = (start_turn[i] + 0.25 * float(s) / float(seg)) * TAU
			pts.append(centers[i] + Vector2(cos(a), sin(a)) * rr)
	pts.append(pts[0])
	return pts


## 把卡面按圆角裁一次烘进 alpha。
## ⚠ 为什么不用 card_still 着色器：棋盘上的卡是一个 Node2D 用 _draw() 一次画完
##   （投影 / 卡套 / 卡面 / 金框 / 名牌 叠在同一个绘制批次里），
##   而 draw_texture_rect() 没有逐次绘制的材质入口 —— 圆角只能预先烘进贴图。
##   每个 boss 烘一张 256×384，整局共用，比每帧一个 ShaderMaterial 便宜。
## 缓存按**贴图路径**记账，不按 boss_id：换档（原画↔水墨↔华彩）之后同一位要用另一张图，
## 按 boss_id 记就会一直端出旧的那张。
static func rounded_art(path: String) -> Texture2D:
	if _rounded_cache.has(path):
		return _rounded_cache[path]
	var out: Texture2D = null
	if path != "" and ResourceLoader.exists(path):
		var src := load(path) as Texture2D
		if src != null:
			var img := src.get_image()
			if img != null:
				img.convert(Image.FORMAT_RGBA8)
				img.resize(ART_BAKE_W, ART_BAKE_H, Image.INTERPOLATE_LANCZOS)
				var r := float(ART_BAKE_W) * CORNER_FRAC
				var w := ART_BAKE_W
				var h := ART_BAKE_H
				for y in h:
					for x in w:
						var dx := absf(float(x) - (w - 1) * 0.5) - ((w - 1) * 0.5 - r)
						var dy := absf(float(y) - (h - 1) * 0.5) - ((h - 1) * 0.5 - r)
						var dist := sqrt(maxf(dx, 0.0) * maxf(dx, 0.0)
								+ maxf(dy, 0.0) * maxf(dy, 0.0)) \
								+ minf(maxf(dx, dy), 0.0) - r
						if dist > 0.0:
							img.set_pixel(x, y, Color(0, 0, 0, 0))
						elif dist > -1.0:
							var c := img.get_pixel(x, y)
							c.a *= clampf(1.0 + dist, 0.0, 1.0)
							img.set_pixel(x, y, c)
				out = ImageTexture.create_from_image(img)
	_rounded_cache[path] = out
	return out


## 牌背：全局统一一张，**不许带任何单卡元素**（边光、纹章、字母都不行）——
## 牌面一泄露身份，锁正面/锁反面那套暗牌机制就整个塌掉。
static func back_texture() -> ImageTexture:
	if _back_tex != null:
		return _back_tex
	var w := 128
	var h := 192
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := corner_radius(float(w))
	var ink := Color(0.115, 0.098, 0.075)
	var ink_hi := Color(0.175, 0.150, 0.112)
	var gold := Color(0.62, 0.50, 0.28)
	var gold_dim := Color(0.42, 0.34, 0.19)
	for y in h:
		for x in w:
			# 圆角 SDF：中心为原点，换算到 [0,1] 之外
			var dx := absf(float(x) - (w - 1) * 0.5) - ((w - 1) * 0.5 - r)
			var dy := absf(float(y) - (h - 1) * 0.5) - ((h - 1) * 0.5 - r)
			var dist := sqrt(maxf(dx, 0.0) * maxf(dx, 0.0) + maxf(dy, 0.0) * maxf(dy, 0.0)) \
					+ minf(maxf(dx, dy), 0.0) - r
			if dist > 0.0:
				continue
			var c := ink
			# 斜向织纹：两组 45° 平行线交成菱格，周期取质数免得与卡片尺寸共振出莫尔
			var lattice := fmod(float(x + y) + 0.5 * float(y - x), 11.0)
			if lattice < 1.6:
				c = ink_hi
			# 外圈金框 + 内一圈暗金衬线
			if dist > -3.0:
				c = gold
			elif dist > -5.0:
				c = gold_dim
			var inset := minf(float(x), float(y))
			if inset > 9 and inset < 12 and fmod(float(x + y), 9.0) < 4.5:
				c = gold_dim          # 内框走一道极淡的绳纹，近看有东西、远看是一圈边
			img.set_pixel(x, y, c)
	_back_tex = ImageTexture.create_from_image(img)
	return _back_tex
