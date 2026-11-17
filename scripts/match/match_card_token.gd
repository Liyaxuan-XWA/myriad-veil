class_name MatchCardToken
extends Node2D
## 棋盘上的一张牌（2026-11-04）
##
## 以前这里是一张 Sprite2D 原画直接贴在棋盘贴图上面，所以玩家说「像一张图平铺在面前」。
## 现在把卡片语言在**世界层**重演一遍，一次 _draw() 画完五层，顺序就是层叠顺序：
##   ① 投影：圆角多边形往下偏，两层递减 alpha 假柔边 —— 没有它牌就是"印在地上"，
##      有了它才读得出"摆在桌面上"。
##   ② 卡套：比牌大一圈的深色底 + 队伍色描边。队伍归属还是全场唯一的分色信息，
##      但改成描边而不是整块色板，色板原来把卡面下沿一整截洗掉了。
##   ③ 牌面：圆角已烘进 alpha（见 MatchCard.rounded_art），反面统一牌背。
##   ④ 金框：外圈 2px + 内圈 1px 衬线 + 四角金线，参数与 CardFace 同一套。
##   ⑤ 名牌：底部压暗带 + 名字。**反面绝对不画** —— 牌面一泄露身份暗牌机制就塌了。
##
## ⚠ 不用 ShaderMaterial：draw_texture_rect() 没有逐次绘制的材质入口，
##   圆角只能预先烘进贴图；好处是整张牌一个绘制批次，12 张同屏也不涨 draw call。

const PLATE_FRAC := 0.15         ## 名牌高度 = 牌高的 15%
const SHADOW_FRAC := 0.05        ## 投影下移量 = 牌高的 5%
## 卡套比牌四周各多出的边距（探针用它断言"连卡套一起装得进一格"，别再写死一份）
const SLEEVE_PAD := 6.0
## 棋盘整屏缩得比较狠（cam.zoom ≈ 0.55），15 号落到屏幕上只有 8px 高。
## 抬到 19 后约 10px —— 名字带是"这是一张卡"的结构性线索，长名字由自动收字号兜住。
const NAME_FONT_SIZE := 19.0
## 呼吸灯周期（秒）与幅度
const BREATH_CYCLE := 1.6
const BREATH_LO := 0.30
const BREATH_HI := 0.92

## 可点状态：这一档决定"这张牌现在能不能点"，与归属（队伍色）是**两条独立通道**。
## 用户 2026-11-04 报：激活阶段一眼看不出哪些能选，且敌我全靠红绿边框。
enum Avail { LOCKED = -1, NEUTRAL = 0, READY = 1 }

var boss_id: String = ""
var team: int = 0
## 这张牌在 `MatchState.cards` 里的下标 —— 可点状态要按它去查规则层
var card_index: int = -1
var card_h: float = MatchDB.card_token_height()
var avail: int = Avail.NEUTRAL

var _revealed := false
var _face_front := false
var _dim := 1.0
var _pulse := 0.0
var _accent := Color(0.86, 0.72, 0.42)
var _art: Texture2D = null
var _name := ""


func setup(id: String, boss_name: String, revealed: bool, team_no: int) -> void:
	boss_id = id
	team = team_no
	_name = boss_name
	_revealed = revealed
	_face_front = revealed
	_accent = MatchCard.accent(id)
	card_h = MatchDB.card_token_height()
	_resolve_art()
	queue_redraw()


## 换档（原画↔水墨↔华彩）之后重取一次贴图。反面不取：牌背是全局那一张，
## 而且提前解析等于把正面画在背面底下，翻面瞬间会闪一下。
func _resolve_art() -> void:
	_art = MatchCard.rounded_art(_art_path(boss_id)) if (_revealed or _face_front) else null


## 对局界面切档时调用：重取配色与贴图再重画
func restyle() -> void:
	_accent = MatchCard.accent(boss_id)
	_resolve_art()
	queue_redraw()


## 棋子出生后这张牌退成「已出」记号：整张牌一起压暗，
## ⚠ 不要只压卡面 —— modulate 的 alpha 叠在暗底上会把红框洗成土黄、绿框洗成灰绿，
##   而队伍色是这块要传达的唯一信息（这条是上一版实机踩过的）。
func set_dim(a: float) -> void:
	_dim = clampf(a, 0.0, 1.0)
	modulate.a = _dim


func is_revealed() -> bool:
	return _revealed


## 由对局层按规则算出来的可点状态推过来（READY=能点 / NEUTRAL=中性 / LOCKED=点不了）。
## ⚠ 只画"能不能点"，绝不改队伍色 —— 归属是另一条独立通道，两条混了就读不出信息。
## 2026-11-10 选卡聚光：等激活的时停窗口里，棋盘底图被 MatchArena.PickDim 压暗，
##   卡片这一层自己负责「只有可选牌亮」：
##   · LOCKED → self_modulate 压暗降饱和（叠在 _draw 里那层灰纱上）；
##   · READY / NEUTRAL → 恢复全亮，READY 另有呼吸灯与一层暖白提亮。
## ⚠ 用 self_modulate 而不是 modulate：set_dim()（棋子出生后把退成记号的牌压到 0.4）
##   写的是 modulate.a，两条路互不覆盖；也不会被 NEUTRAL 复原时把 alpha 冲回 1。
func set_avail(v: int) -> void:
	if avail == v:
		return
	avail = v
	self_modulate = Color(0.46, 0.48, 0.52, 1.0) if v == Avail.LOCKED \
			else Color(1.0, 1.0, 1.0, 1.0)
	set_process(v == Avail.READY)
	queue_redraw()


## 呼吸灯只在 READY 时跑：12 张牌里通常只有 3～6 张可点，
## 全场每帧 queue_redraw 是白烧的绘制开销。
func _process(delta: float) -> void:
	_pulse += delta
	if _pulse >= BREATH_CYCLE:
		_pulse = fmod(_pulse, BREATH_CYCLE)
	queue_redraw()


func _breath() -> float:
	var t := _pulse / BREATH_CYCLE
	# 正弦起落，两端不硬切
	return lerpf(BREATH_LO, BREATH_HI, 0.5 - 0.5 * cos(t * TAU))


## 翻面：牌绕竖轴压扁到 0 再展开，中途换面。
## 用 scale.x 而不是 3D 旋转 —— 这是 2D 世界层，Node2D 没有 Y 轴可转。
func reveal_now() -> void:
	if _revealed:
		return
	_revealed = true
	_resolve_art()
	var t := create_tween()
	t.tween_method(_set_flip, 0.0, 1.0, 0.26).set_trans(Tween.TRANS_SINE)
	t.tween_callback(_finish_flip)


func _set_flip(k: float) -> void:
	scale.x = maxf(absf(1.0 - 2.0 * k), 0.05)
	_face_front = k >= 0.5
	queue_redraw()


func _finish_flip() -> void:
	scale.x = 1.0
	_face_front = true
	queue_redraw()


func card_w() -> float:
	return card_h * 2.0 / 3.0


static func _offset(pts: PackedVector2Array, d: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append((p as Vector2) + d)
	return out


func _art_path(id: String) -> String:
	# 敌方棋子用原版卡面（2026-11-05 用户定）：场上两拨牌一眼分得开，
	# 而且对手长什么样不该由我的卡包偏好决定。我方仍跟随玩家选的档。
	if team != 0:
		return String(MatchCard.opponent_style(id).get("art", ""))
	# ⚠ 补发牌（玩家没解锁任何卡面的 BOSS）走 player_style() → 普通原画，
	#   不能再用 cover_style()：那条路在 owned 为空时会退回全量的第一张「华彩·有背景」。
	var st: Dictionary = MatchCard.player_style(id, CharacterData.match_card_kind)
	var path := String(st.get("art", ""))
	if path != "":
		return path
	return String(CodexDB.boss_entry(id).get("portrait", ""))


func _draw() -> void:
	var w := card_w()
	var h := card_h
	var r := MatchCard.corner_radius(w)
	var team_col := BossBase.TEAM_HP_GREEN if team == 0 else BossBase.TEAM_HP_RED

	# ① 投影：两层递减 alpha 假柔边（Node2D 没有模糊可用）
	# ⚠ PackedVector2Array 的 `+` 是**拼接**不是平移，写错就得到一张多一个顶点的怪多边形
	var dy := h * SHADOW_FRAC
	var pad2 := SLEEVE_PAD * 2.0
	draw_colored_polygon(_offset(MatchCard.rounded_points(w + pad2 + 2.0, h + pad2 + 2.0, r + 5.0),
			Vector2(0, dy * 2.0)), Color(0.01, 0.012, 0.02, 0.26 * _dim))
	draw_colored_polygon(_offset(MatchCard.rounded_points(w + pad2 - 6.0, h + pad2 - 6.0, r + 2.0),
			Vector2(0, dy)), Color(0.01, 0.012, 0.02, 0.40 * _dim))

	# ② 卡套：深色底 + 队伍色描边
	var sleeve := MatchCard.rounded_points(w + pad2, h + pad2, r + 5.0)
	draw_colored_polygon(sleeve, Color(0.045, 0.04, 0.032, 0.92 * _dim))
	draw_polyline(sleeve, Color(team_col.r, team_col.g, team_col.b, 0.85 * _dim), 3.0, true)

	# ②b 归属签：**形状**分敌我，不只靠颜色。
	# 己方 = 牌顶朝上的梯形（像牌从卡套里探出来），对方 = 朝下的倒钩。
	# 颜色再对，色弱玩家和一眼扫过去的余光也分不清；形状差是瞬间可读的。
	var tab_w := w * 0.44
	var tab_h := 13.0
	var ty := -h * 0.5 - SLEEVE_PAD
	var tab := PackedVector2Array()
	if team == 0:
		tab = PackedVector2Array([Vector2(-tab_w * 0.5, ty), Vector2(tab_w * 0.5, ty),
				Vector2(tab_w * 0.32, ty - tab_h), Vector2(-tab_w * 0.32, ty - tab_h)])
	else:
		tab = PackedVector2Array([Vector2(-tab_w * 0.5, ty - tab_h), Vector2(tab_w * 0.5, ty - tab_h),
				Vector2(tab_w * 0.32, ty + tab_h * 0.42), Vector2(-tab_w * 0.32, ty + tab_h * 0.42)])
	draw_colored_polygon(tab, Color(team_col.r, team_col.g, team_col.b, 0.92 * _dim))
	draw_polyline(tab + PackedVector2Array([tab[0]]), Color(0.02, 0.02, 0.03, 0.8 * _dim), 1.6, true)

	# ③ 牌面 / 牌背
	# 点不了的牌：整张压成灰（modulate 降饱和 + 盖一层灰纱），
	# 这是用户要的效果 —— "选自己牌的时候，敌方牌被灰色笼罩"。
	# ⚠ 压灰要留得住"这是谁"：灰纱太重就变成一块黑牌，玩家下一步该防谁全看不出来。
	var veil := avail == Avail.LOCKED
	var art_mod := Color(1, 1, 1, _dim)
	if veil:
		art_mod = Color(0.58, 0.59, 0.63, _dim)
	var face := Rect2(-w * 0.5, -h * 0.5, w, h)
	if _face_front and _art != null:
		draw_texture_rect(_art, face, false, art_mod)
	else:
		draw_texture_rect(MatchCard.back_texture(), face, false, art_mod)
	if veil:
		draw_colored_polygon(MatchCard.rounded_points(w, h, r),
				Color(0.10, 0.11, 0.14, 0.38 * _dim))
	if avail == Avail.READY:
		# 选卡聚光：棋盘底图与所有 LOCKED 的牌都被压暗，只有这张是亮的。
		# 再叠一层暖白，读作「这张被打上了光」而不是「这张忘了变暗」。
		# ⚠ 别用 modulate 提亮：set_dim() 也写 modulate.a，两条路会互相覆盖。
		draw_colored_polygon(MatchCard.rounded_points(w, h, r),
				Color(1.0, 0.96, 0.84, 0.18 * _dim))

	# ④ 金框：外圈 + 内衬 + 四角金线（与 CardFace._draw 同一套比例）
	var outer := MatchCard.rounded_points(w, h, r)
	draw_polyline(outer, Color(_accent.r, _accent.g, _accent.b, 0.80 * _dim), 2.0, true)
	var inner := MatchCard.rounded_points(w - 8.0, h - 8.0, maxf(r - 2.0, 3.0))
	draw_polyline(inner, Color(_accent.r, _accent.g, _accent.b, 0.22 * _dim), 1.0, true)
	if _face_front:
		var inset := 6.0
		var ln := 12.0
		var pts := [
			[Vector2(-w * 0.5 + inset, -h * 0.5 + inset + ln), Vector2(-w * 0.5 + inset, -h * 0.5 + inset), Vector2(-w * 0.5 + inset + ln, -h * 0.5 + inset)],
			[Vector2(w * 0.5 - inset - ln, -h * 0.5 + inset), Vector2(w * 0.5 - inset, -h * 0.5 + inset), Vector2(w * 0.5 - inset, -h * 0.5 + inset + ln)],
			[Vector2(-w * 0.5 + inset, h * 0.5 - inset - ln), Vector2(-w * 0.5 + inset, h * 0.5 - inset), Vector2(-w * 0.5 + inset + ln, h * 0.5 - inset)],
			[Vector2(w * 0.5 - inset - ln, h * 0.5 - inset), Vector2(w * 0.5 - inset, h * 0.5 - inset), Vector2(w * 0.5 - inset, h * 0.5 - inset - ln)],
		]
		for p in pts:
			draw_polyline(PackedVector2Array(p as Array),
					Color(_accent.r, _accent.g, _accent.b, 0.72 * _dim), 1.6, true)

	# ⑤ 名牌（只在正面；反面画名字等于把暗牌机制废掉）
	if _face_front and _name != "":
		var ph := h * PLATE_FRAC
		draw_rect(Rect2(-w * 0.5, h * 0.5 - ph, w, ph),
				Color(0.015, 0.02, 0.035, 0.66 * _dim))
		var font := UIKit.readable_font()
		var fs := NAME_FONT_SIZE
		# ⚠ 这个引擎版本的 Font **没有** get_string_width()（那是 Godot 3 的名字），
		#   只有 get_string_size(text, alignment, width, font_size, ...) → 取 .x；
		#   而且第 2 参要的是 HorizontalAlignment，不是 TextServer.Direction。
		#   写错不会编译失败，是每帧刷一条 Nonexistent function，_draw 后半段整个不执行。
		while fs > 9.0 \
				and font.get_string_size(_name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(fs)).x > w - 12.0:
			fs -= 0.5
		var base_y := h * 0.5 - ph * 0.34
		draw_string_outline(font, Vector2(-w * 0.5, base_y), _name,
				HORIZONTAL_ALIGNMENT_CENTER, w, fs, 3, Color(0, 0, 0, 0.9 * _dim))
		draw_string(font, Vector2(-w * 0.5, base_y), _name,
				HORIZONTAL_ALIGNMENT_CENTER, w, fs,
				Color(_accent.r, _accent.g, _accent.b, _dim))

	# ⑥ 可点呼吸灯：套在卡套外面一圈暖金，亮度按正弦起落。
	# 这是"这张现在能点"的唯一即时读数 —— 归属看签、能不能点看这圈灯。
	# ⚠ 灯色刻意避开队伍色的两个色相：己方套边是青绿、对方是红，原来这圈用
	#   (1.0,0.84,0.42) 的金，落到 zoom≈0.31 的屏幕上与青绿几乎分不开，
	#   "能点"和"是我的"就糊成同一件事。改成偏白的香槟金 —— 读作"光"而不是"颜色"。
	if avail == Avail.READY:
		var b := _breath()
		# 第一圈**常亮**（不参与呼吸）：呼吸到最低点的 0.30 alpha 时，实机截图里
		# 四张可点牌只看得见一张，其余三张和点不了的牌混在一起 —— 玩家扫一眼是逐帧扫的，
		# 不能靠"刚好撞上亮的相位"。常亮圈保证任何时候都认得出，呼吸只负责吸引注意。
		draw_polyline(MatchCard.rounded_points(w + pad2 + 7.0, h + pad2 + 7.0, r + 8.0),
				Color(1.0, 0.95, 0.78, 0.60 * _dim), 3.0, true)
		draw_polyline(MatchCard.rounded_points(w + pad2 + 7.0, h + pad2 + 7.0, r + 8.0),
				Color(1.0, 0.96, 0.82, b * 0.92 * _dim), 3.0, true)
		draw_polyline(MatchCard.rounded_points(w + pad2 + 13.0, h + pad2 + 13.0, r + 11.0),
				Color(1.0, 0.92, 0.66, b * 0.34 * _dim), 2.0, true)
