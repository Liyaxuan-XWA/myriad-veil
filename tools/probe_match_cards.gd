extends Node
## 棋盘模式的「这看起来是一张卡吗」结构守卫（2026-11-04）
##
## 用户的原话：卡片要有卡片的感觉，现在就像一张图平铺在面前 —— 选牌时像在卡包里挑，
## 落到棋盘上也要是一张牌。这条探针把两件事钉住：
##   ① 手牌 / 结算页挂的是 **CardFace**（与卡包封面同一支渲染器），不是裸 TextureRect；
##   ② 棋盘上的棋子是 **MatchCardToken**，圆角、金框、投影、名牌都在，
##      而且**反面不许泄露任何单卡信息**（暗牌机制的地基）。
## 另外守住一批只有读代码才会发现跑偏的几何：圆角半径口径、牌背全局唯一、
## rounded_points 闭合、卡套装得进格子。
##
## 用法：godot --headless --path . res://tools/probe_match_cards.tscn -- --no-save

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _has_face(n: Node) -> bool:
	if n is CardFace:
		return true
	for c in n.get_children():
		if _has_face(c):
			return true
	return false


## 找按钮子树里的华彩卡本体（悬停视差就挂在它身上）
func _find_holo(n: Node) -> Node:
	if n is HoloCardView:
		return n
	for c in n.get_children():
		var r := _find_holo(c)
		if r != null:
			return r
	return null


func _corner_alpha(img: Image, x: int, y: int) -> float:
	return img.get_pixel(x, y).a


func _ready() -> void:
	print("\n########## 卡片质感 · 结构守卫 ##########")

	# ---- 1. 圆角多边形：首尾闭合、包围盒就是 w×h ----
	var pts := MatchCard.rounded_points(120.0, 180.0, 6.0, 6)
	_check(pts.size() > 8 and pts[0] == pts[pts.size() - 1],
			"rounded_points 是一条闭合环（描边不会留缺口）", "顶点 %d" % pts.size())
	var minx := INF
	var maxx := -INF
	var miny := INF
	var maxy := -INF
	for p in pts:
		minx = minf(minx, (p as Vector2).x)
		maxx = maxf(maxx, (p as Vector2).x)
		miny = minf(miny, (p as Vector2).y)
		maxy = maxf(maxy, (p as Vector2).y)
	_check(absf(maxx - minx - 120.0) < 1.0 and absf(maxy - miny - 180.0) < 1.0,
			"圆角环的包围盒 = 卡片尺寸（不会画着画着缩一号）",
			"%.1f×%.1f" % [maxx - minx, maxy - miny])
	# 鞋带公式面积必须等于圆角矩形面积 w*h −(4−π)r²。
	# 第一版每个角扫了整整一圈（应该 1/4 圈），环自交 → draw_colored_polygon 报
	# "Invalid polygon data, triangulation failed"，投影和卡套整个不画。
	# 光看包围盒是查不出来的，必须查面积。
	var area := 0.0
	for k in pts.size() - 1:
		var p0: Vector2 = pts[k]
		var p1: Vector2 = pts[k + 1]
		area += p0.x * p1.y - p1.x * p0.y
	area = absf(area) * 0.5
	var want := 120.0 * 180.0 - (4.0 - PI) * 6.0 * 6.0
	_check(absf(area - want) / want < 0.02,
			"圆角环面积 = 圆角矩形面积（自交或多绕一圈都会在这里露馅）",
			"实测 %.0f / 应为 %.0f" % [area, want])

	# ---- 2. 圆角半径与 CardFace 同一口径 ----
	var r_small := MatchCard.corner_radius(60.0)
	var r_mid := MatchCard.corner_radius(160.0)
	var r_big := MatchCard.corner_radius(900.0)
	_check(r_small >= MatchCard.CORNER_MIN - 0.01, "小卡圆角不低于下限", "%.1f" % r_small)
	_check(absf(r_mid - 160.0 * MatchCard.CORNER_FRAC) < 0.01,
			"常规尺寸按短边 4.5% 走（与 CardFace._sync_geometry 一致）", "%.1f" % r_mid)
	_check(r_big <= MatchCard.CORNER_MAX + 0.01, "大卡圆角封顶，不会圆成徽章", "%.1f" % r_big)

	# ---- 3. 牌背：全局唯一一张，且不带任何单卡信息 ----
	var back := MatchCard.back_texture()
	_check(back == MatchCard.back_texture(), "牌背是同一张贴图（每张牌各生成一张就漏了）")
	var bsz := back.get_size()
	_check(absf(float(bsz.x) / float(bsz.y) - 2.0 / 3.0) < 0.011,
			"牌背比例 2:3，与卡面共用同一个矩形", str(bsz))
	var bimg := back.get_image()
	_check(_corner_alpha(bimg, 0, 0) < 0.05 and _corner_alpha(bimg, bsz.x - 1, bsz.y - 1) < 0.05,
			"牌背四角是透明的（圆角真的裁出来了）")
	_check(bimg.get_pixel(bsz.x / 2, bsz.y / 2).a > 0.9, "牌背中心不透明")

	# ---- 4. 每个卡池成员都要有一张真卡面 ----
	var no_style: Array = []
	var still_only := 0
	for id in MatchDB.CARD_POOL:
		var bid := String(id)
		var style := MatchCard.cover_style(bid, "")
		if style.is_empty():
			no_style.append(bid)
			continue
		if String(style.get("kind", "holo")) == "still":
			still_only += 1
		# configure() 是 CardFace 唯一的成败出口：返回 false 时按钮会退回裸贴图
		var face := CardFace.new()
		var ok := face.configure(style, Vector2(160.0, 240.0), MatchCard.accent(bid), false)
		face.free()
		if not ok:
			no_style.append(bid + "(configure=false)")
	_check(no_style.is_empty(), "卡池每一位都拿得到卡面且 CardFace 建得起来",
			"缺=" + ", ".join(no_style))
	_check(still_only == 0, "没有一位退化成「只有原画没有华彩层」", "still 计数 %d" % still_only)

	# ---- 4b. 默认档必须等于卡包封面，而且四档都能切出来 ----
	# 用户报的就是这条：以前写死 variants[0]（华彩·有背景），
	# 玩家在收藏册里把水墨拖到第一位当封面，进对局看到的还是另一张。
	var cover_mismatch: Array = []
	for id in MatchDB.CARD_POOL:
		var bid2 := String(id)
		var owned: Array = CodexDB.ordered_variants(CodexDB.card_entry(bid2))
		if owned.is_empty():
			continue
		var got := String(MatchCard.cover_style(bid2, "").get("id", ""))
		var cover_id := String((owned[0] as Dictionary).get("id", ""))
		if got != cover_id:
			cover_mismatch.append("%s 对局=%s 卡包=%s" % [bid2, got, cover_id])
	_check(cover_mismatch.is_empty(), "「跟随卡包」取的就是收藏册封面那一张",
			"; ".join(cover_mismatch))
	_check(MatchCard.KINDS.size() == 5, "卡面档位是五档（跟随卡包 + 四种卡）")
	# 没解锁的档位不许报错、也不许画空 —— 自动回退到封面
	var fallback_id := String(MatchDB.CARD_POOL[0])
	var locked_out := MatchCard.cover_style(fallback_id, "ink")
	_check(not locked_out.is_empty(), "切到没解锁的档位也有牌面（回退到封面）",
			String(locked_out.get("id", "")))
	# 换档要真的换到另一张图，否则按钮按了没反应
	var changed := false
	var base_art := String(MatchCard.cover_style(fallback_id, "").get("art", ""))
	for k in MatchCard.KINDS:
		var other := String(MatchCard.cover_style(fallback_id, String(k["id"])).get("art", ""))
		if other != "" and other != base_art:
			changed = true
	_check(changed, "至少有一档的贴图与封面不同（切档看得见变化）")
	# 缓存按「boss|档位」记账：切档后不清就会端出上一档的图
	CharacterData.match_card_kind = "portrait"
	var portrait_style := String(MatchCard.cover_style(fallback_id, "portrait").get("art", ""))
	CharacterData.match_card_kind = ""
	var cover_art := String(MatchCard.cover_style(fallback_id, "").get("art", ""))
	_check(portrait_style != "" and cover_art != "", "两种档位各自都解析得出贴图",
			"%s / %s" % [portrait_style.get_file(), cover_art.get_file()])

	# ---- 5. 圆角卡面真的烘进去了 ----
	var probe_id := String(MatchDB.CARD_POOL[0])
	var probe_path := String(MatchCard.cover_style(probe_id, "").get("art", ""))
	var art := MatchCard.rounded_art(probe_path)
	_check(art != null, "卡面圆角贴图烘得出来", probe_id)
	if art != null:
		var aimg := art.get_image()
		var aw := aimg.get_width()
		var ah := aimg.get_height()
		_check(_corner_alpha(aimg, 0, 0) < 0.05 and _corner_alpha(aimg, aw - 1, 0) < 0.05
				and _corner_alpha(aimg, 0, ah - 1) < 0.05 and _corner_alpha(aimg, aw - 1, ah - 1) < 0.05,
				"卡面四个角全透明 —— 场上那张牌是圆的，不是方图贴圆框")
		_check(aimg.get_pixel(aw / 2, ah / 2).a > 0.9, "卡面中心不透明（没把人物也裁掉）")
		_check(art == MatchCard.rounded_art(probe_path), "同一路径只烘一次（缓存吃得住）")
		# 换档必须换图：缓存按路径记账，按 boss_id 记就会一直端出上一档
		var other_path := String(MatchCard.cover_style(probe_id, "ink").get("art", ""))
		if other_path != "" and other_path != probe_path:
			_check(MatchCard.rounded_art(other_path) != art,
					"换档之后棋盘卡取到的是另一张图（缓存按贴图路径记）")

	# ---- 6. 棋盘 token：反面不泄露身份 ----
	var tok_hidden := MatchCardToken.new()
	add_child(tok_hidden)
	tok_hidden.setup(probe_id, "叠纸", false, 0)
	var tok_face := MatchCardToken.new()
	add_child(tok_face)
	tok_face.setup(probe_id, "叠纸", true, 1)
	_check(not tok_hidden.is_revealed() and bool(tok_hidden.get("_face_front")) == false,
			"反面 token 画的是牌背，不是卡面")
	_check(bool(tok_face.get("_face_front")), "正面 token 画卡面")
	_check(bool(tok_hidden.get("_face_front")) == false,
			"反面牌即使名字已经传进 setup 也不许翻面（名牌整块不画）")
	tok_hidden.reveal_now()
	await get_tree().create_timer(0.5).timeout
	_check(tok_hidden.is_revealed() and bool(tok_hidden.get("_face_front")),
			"翻面动画放完落到正面，scale.x 回正", "scale.x=%.2f" % tok_hidden.scale.x)
	_check(absf(tok_face.card_w() / tok_face.card_h - 2.0 / 3.0) < 0.01,
			"棋盘卡是 2:3 竖版", "%.2f" % (tok_face.card_w() / tok_face.card_h))
	var sleeve: float = tok_face.card_h + MatchCardToken.SLEEVE_PAD * 2.0
	_check(sleeve <= MatchDB.CELL_PX, "连卡套一起装得进一格",
			"%.0f ≤ %.0f" % [sleeve, MatchDB.CELL_PX])
	tok_hidden.free()
	tok_face.free()

	# ---- 6b. 可点状态与空格提示的开关行为（呼吸灯不许全程烧绘制）----
	var probe_tok := MatchCardToken.new()
	add_child(probe_tok)
	probe_tok.setup(probe_id, "叠纸", true, 0)
	probe_tok.set_avail(MatchCardToken.Avail.READY)
	_check(probe_tok.is_processing(), "READY 的牌才跑呼吸（_process 开着）")
	probe_tok.set_avail(MatchCardToken.Avail.LOCKED)
	_check(not probe_tok.is_processing(), "压灰的牌不跑 _process")
	probe_tok.set_avail(MatchCardToken.Avail.NEUTRAL)
	_check(int(probe_tok.avail) == MatchCardToken.Avail.NEUTRAL, "状态可回到中性")
	probe_tok.free()
	var hint := MatchCellHint.new()
	add_child(hint)
	hint.set_cells([])
	_check(not hint.is_processing(), "没有可落格子时提示不跑 _process")
	hint.set_cells([Vector2i(1, 1), Vector2i(2, 2)])
	_check(hint.is_processing() and hint.cells.size() == 2, "有可落格子时提示开始呼吸")
	hint.set_cells([Vector2i(1, 1), Vector2i(2, 2)])
	_check(hint.cells.size() == 2, "重复推同一批格子不会累积（按内容去重）")
	hint.free()

	# ---- 6c. 开局补牌 = 普通卡（2026-11-10）+ 选卡聚光的分层 ----
	# 用户报：开局不足 6 张时补出来的牌是华彩，和自己收集的牌混成一片花。
	# 根因是 cover_style 在 owned 为空时退回全量第一张「华彩·有背景」。
	var fill_id := String(MatchDB.CARD_POOL[0])
	var fill_owned: Array = CodexDB.ordered_variants(CodexDB.card_entry(fill_id))
	if fill_owned.is_empty():
		var ps := MatchCard.player_style(fill_id, "")
		_check(String(ps.get("id", "")) == "portrait"
				and String(ps.get("kind", "still")) == "still",
				"⑥c 没解锁的 BOSS（= 开局补牌）玩家侧是普通卡，不是华彩",
				String(ps.get("id", "")))
		var want_art := String(CodexDB.boss_entry(fill_id).get("portrait", ""))
		_check(String(ps.get("art", "")) == want_art,
				"⑥c 补牌贴的就是图鉴原画那张", String(ps.get("art", "")).get_file())
		_check(String(MatchCard.player_style(fill_id, "ink").get("art", "")) == want_art,
				"⑥c 玩家把卡包切到水墨，补牌仍不动（不跟档位漂移）")
		# 反向守卫：别为了修补牌把 cover_style 一起改了，卡包收藏册另有口径
		_check(String(MatchCard.cover_style(fill_id, "").get("kind", "still")) == "holo",
				"⑥c cover_style 本身没被改（收藏册仍按原规则回退华彩）")
		# 已收集的 BOSS 必须仍完全跟随玩家选的档，不能一刀切全变普通卡
		var saved = CharacterData.boss_progress.get(fill_id, null)
		CharacterData.boss_progress[fill_id] = {"killed": true}
		MatchCard.clear_cache()
		var drift: Array = []
		for w in ["", "portrait", "ink"]:
			var a1 := String(MatchCard.player_style(fill_id, String(w)).get("art", ""))
			var a2 := String(MatchCard.cover_style(fill_id, String(w)).get("art", ""))
			if a1 != a2:
				drift.append(String(w))
		_check(drift.is_empty(), "⑥c 已收集的 BOSS 仍完全跟随卡包档位", ", ".join(drift))
		if saved == null:
			CharacterData.boss_progress.erase(fill_id)
		else:
			CharacterData.boss_progress[fill_id] = saved
		MatchCard.clear_cache()
	# 视差宿主没丢：普通卡不走 HoloCardView，但真华彩卡面必须还建得出来
	var holo_style := MatchCard.cover_style(fill_id, "")
	var holo_face := CardFace.new()
	var holo_ok := holo_face.configure(holo_style, Vector2(160.0, 240.0),
			MatchCard.accent(fill_id), false)
	if String(holo_style.get("kind", "still")) == "holo":
		_check(holo_ok and _find_holo(holo_face) != null,
				"⑥c 华彩卡面仍能建出 HoloCardView（视差宿主没丢）",
				String(holo_style.get("id", "")))
	holo_face.free()

	# 选卡聚光：等待激活时棋盘底图压暗，卡片按 Avail 自己亮/暗。
	# 用裸 arena + 手搓 state，不跑一局 —— 守的是 gating、遮罩层级、明暗通道这三条契约。
	# ⚠ 第一版用「遮罩 z=8 盖住一切 + 可选牌提到 z=9 穿透」，实机染红诊断显示
	#   92% 棋盘连可选牌一起被盖住（子节点绝对 z 争不过父 _tokens 分组），已废弃。
	var dim_arena := MatchArena.new()
	var dim_state := MatchState.new()
	dim_state.phase = MatchState.Phase.BATTLE
	dim_state.round_index = 0
	dim_state.cards = [
		{"team": 0, "boss_id": fill_id, "deployed": true, "activated": false},
		{"team": 0, "boss_id": fill_id, "deployed": true, "activated": true},
		{"team": 1, "boss_id": fill_id, "deployed": true, "activated": false},
	]
	dim_state.set("_fighting", false)
	var dim_tokens := Node2D.new()
	dim_arena.add_child(dim_tokens)
	dim_arena.set("_tokens", dim_tokens)
	var dim_rect := ColorRect.new()
	dim_arena.add_child(dim_rect)
	dim_arena.set("_pick_dim", dim_rect)
	dim_arena.set("_state", dim_state)
	var dim_made: Array = []
	for i in 3:
		var dt := MatchCardToken.new()
		dt.card_index = i
		dim_tokens.add_child(dt)
		dim_made.append(dt)
	dim_arena.call("_refresh_token_avail")
	var t0: MatchCardToken = dim_made[0]
	var t1: MatchCardToken = dim_made[1]
	_check(bool(dim_rect.visible), "⑥c 等待激活时棋盘暗纱亮起")
	_check(MatchArena.Z_GROUND < MatchArena.Z_PICK_DIM
			and MatchArena.Z_PICK_DIM < MatchArena.Z_TOKEN,
			"⑥c 暗纱只压棋盘底图，绝不盖到卡片上", "z=%d" % MatchArena.Z_PICK_DIM)
	_check(t0.self_modulate.r > 0.95,
			"⑥c 可选牌保持全亮（自己压暗那条路没落到它头上）",
			"r=%.2f" % t0.self_modulate.r)
	_check(t1.self_modulate.r < 0.7,
			"⑥c 不可选的牌自己压暗（不靠遮罩盖）", "r=%.2f" % t1.self_modulate.r)
	_check(int(t0.avail) == MatchCardToken.Avail.READY
			and int(t1.avail) == MatchCardToken.Avail.LOCKED,
			"⑥c 灯与规则层 legal_activate 一致")
	dim_state.set("_fighting", true)
	dim_arena.call("_refresh_token_avail")
	_check(not bool(dim_rect.visible), "⑥c 开打后暗纱撤掉，不会一直糊着棋盘")
	_check(int(t0.avail) == MatchCardToken.Avail.NEUTRAL and t0.self_modulate.r > 0.95,
			"⑥c 开打后所有牌回中性且恢复全亮")
	dim_arena.free()
	var dim_src := FileAccess.get_file_as_string("scripts/match/match_arena.gd")
	_check(dim_src.contains("_pick_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE"),
			"⑥c 暗纱不吃输入（否则 36 格点不动）")
	# 接线守卫：手牌按钮 / 拖影 / 结算页三处都得走 player_style。
	# 只改其中一处的话，玩家在另一屏还是会看到补牌变华彩，断言却全绿。
	_check(not dim_src.contains("MatchCard.cover_style(")
			and dim_src.split("MatchCard.player_style(").size() - 1 == 3,
			"⑥c 手牌 / 拖影 / 结算三处都走 player_style（没漏改一处）",
			"%d 处" % (dim_src.split("MatchCard.player_style(").size() - 1))

	# ---- 7. 真跑一局：每个阶段的手牌都必须挂着 CardFace ----
	var arena := (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	arena.set("player_stage_timeout", 0.6)
	add_child(arena)
	var seen: Dictionary = {}
	var bare := 0
	var cards_total := 0
	var token_kinds := 0
	var hidden_tokens := 0
	var leaked := 0
	var holo_total := 0
	var holo_dead := 0
	var btn_dead := 0
	var battle_checked := 0
	var avail_wrong := 0
	var team_wrong := 0
	var own_round_dark := 0
	for i in 900:
		await get_tree().process_frame
		var st = arena.get("_state")
		if st == null:
			continue
		# ⚠ 直接读 `st.phase`（int 枚举）再翻 PHASE_NAME。
		#   别写 `String(st.get("phase"))`：`String(...)` 不是万能构造器，
		#   拿到非字符串就报 Invalid call 'String' constructor（本项目第 N 次踩）。
		var pname := String(MatchState.PHASE_NAME.get(int(st.phase), "?"))
		var hand: Control = arena.get("_hand")
		if hand != null:
			for btn in hand.get_children():
				if not (btn is Button):
					continue
				var key := "%s|%s" % [pname, btn.name]
				if seen.has(key):
					continue
				seen[key] = true
				cards_total += 1
				if not _has_face(btn):
					bare += 1
					print("   裸图卡面：", pname, " / ", btn.get("tooltip_text"))
				# 悬停的通路：卡面子树必须全部 IGNORE（否则按下/松开传不回按钮，牌点不动），
				# 而按钮要把 motion 转给卡面 —— 这两条一起才既有点又有视差。
				# 用户报的「鼠标移动时卡面没有动态效果」原本就是这两条都断了。
				var hv := _find_holo(btn)
				if hv != null:
					holo_total += 1
					if (hv as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
						holo_dead += 1
				# ⚠ Button 上没有 get_connections()，取某信号的连接要用
				#   Object.get_signal_connection_list(name)
				if (btn as Button).get_signal_connection_list("gui_input").is_empty():
					btn_dead += 1
		var toks: Node2D = arena.get("_tokens")
		if toks != null:
			for t in toks.get_children():
				if not (t is MatchCardToken):
					continue
				var tk := t as MatchCardToken
				var tkey := "tok%d" % tk.get_instance_id()
				if seen.has(tkey):
					continue
				seen[tkey] = true
				token_kinds += 1
				if not tk.is_revealed():
					hidden_tokens += 1
					if bool(tk.get("_face_front")):
						leaked += 1
		# 用户要的那条：激活阶段"亮呼吸灯的牌"必须与规则层的可点集合**逐张一致**。
		# 只断言"有灯"不够 —— 灯挂到对面队伍才是真正会误导玩家的事。
		#
		# ⚠ 判据 2026-11-04 重写过一版：原来那条"己方牌不许被压灰"的前提是错的。
		#   规则层奇数轮**就是**让玩家替对方挑进场时机（legal_activate 返回对方牌），
		#   所以那时己方牌点不了、被压灰，是正确表现。真正会误导玩家的是
		#   ① 灯与规则层不一致，② 归属串台（牌套颜色/归属签说它是 A 队，
		#   规则层说是 B 队），③ 轮到己方却整场一张都没亮 —— 玩家无从下手。
		if pname == "battle" and not bool(st.fighting()):
			var legal: Array = []
			for li in st.legal_activate(0):      # 0 = 玩家队（与 MatchArena.PLAYER_TEAM 同值）
				legal.append(int(li))
			if legal.is_empty():
				pass
			else:
				battle_checked += 1
				var own_lit := 0
				for t2 in toks.get_children():
					if not (t2 is MatchCardToken):
						continue
					var tk2 := t2 as MatchCardToken
					if legal.has(tk2.card_index) != (tk2.avail == MatchCardToken.Avail.READY):
						avail_wrong += 1
					if tk2.card_index >= 0 and tk2.card_index < st.cards.size() \
							and int(st.cards[tk2.card_index]["team"]) != tk2.team:
						team_wrong += 1
					if tk2.avail == MatchCardToken.Avail.READY and tk2.team == 0:
						own_lit += 1
				if bool(st.is_own_round()) and int(st.cards[int(legal[0])]["team"]) == 0 \
						and own_lit == 0:
					own_round_dark += 1
		if pname == "over" or pname == "final":
			break
	# 结算页 = 用户报「补的牌是华彩」的那一屏。整局循环在 final 就 break 了，
	# 这里手动把状态推到 OVER 再铺一次；_show_result_deck 先 queue_free 旧卡，
	# 必须等一帧才能数到真正铺出来的那 6 张。
	var result_state = arena.get("_state")
	var rdeck: Node = arena.get("_result_deck")
	if result_state != null and rdeck != null:
		result_state.phase = MatchState.Phase.OVER
		result_state.winner = 0
		result_state.end_reason = "clear_field"
		arena.call("_settle")
		await get_tree().process_frame
		var settle_n := rdeck.get_child_count()
		var settle_holo := 0
		for ch in rdeck.get_children():
			if _find_holo(ch) != null:
				settle_holo += 1
		_check(settle_n >= 1 and settle_holo == 0,
				"结算页铺出的玩家牌全是普通卡（补牌没冒华彩）",
				"%d 张 / 华彩 %d" % [settle_n, settle_holo])
	_check(cards_total >= 5, "至少铺出过 5 张手牌卡面", "%d 张" % cards_total)
	_check(bare == 0, "每个阶段的手牌都挂着 CardFace（没有一张退回裸贴图）", "裸图 %d" % bare)
	# 2026-11-10：补牌改普通卡后，默认（没解锁任何 BOSS）存档整局手牌里
	#   一张 HoloCardView 都不该出现 —— 这正是用户要的效果。
	#   ⚠ 不能反过来把 `holo_total > 0` 留着：那等于逼补牌又变回华彩。
	#   视差链路本身由 6c 组单独验过（真华彩卡面仍建得出 HoloCardView）。
	if fill_owned.is_empty():
		_check(holo_total == 0, "补牌改普通卡后，未收集 BOSS 的手牌不再冒出华彩层",
				"%d 张" % holo_total)
	_check(holo_dead == 0,
			"卡面子树全 IGNORE —— 一旦有 PASS 的节点，按下/松开传不回按钮，牌就点不动",
			"非 IGNORE %d" % holo_dead)
	_check(btn_dead == 0, "每张按钮都接了 motion 转发（视差靠它，不靠卡面自己收输入）",
			"没接 %d" % btn_dead)
	_check(battle_checked >= 2, "至少核对过 2 次激活阶段的可点集合", "%d 次" % battle_checked)
	_check(avail_wrong == 0,
			"亮呼吸灯的牌 == 规则层 legal_activate 的那几张（逐张一致）",
			"错位 %d" % avail_wrong)
	_check(team_wrong == 0, "归属通道不串台：牌面 team 与规则层 cards[i].team 逐张一致",
			"串台 %d" % team_wrong)
	_check(own_round_dark == 0, "轮到己方时棋盘上至少有一张亮着灯（不会整场灰）",
			"全灰 %d 次" % own_round_dark)
	_check(token_kinds > 0, "棋盘上出现过卡片 token", "%d 张" % token_kinds)
	_check(hidden_tokens > 0, "这局确实有暗牌上过场", "%d 张" % hidden_tokens)
	_check(leaked == 0, "暗牌从头到尾没在牌背上露出正面", "泄露 %d" % leaked)

	# ---- 7c. 世界层叠：牌不许压在激活的 BOSS 身上（2026-11-04 用户报遮挡）----
	# 原来 token 写死 z=2、Pieces 没设（默认 0），牌整个盖在棋子身上。
	var toks2: Node2D = arena.get("_tokens")
	var pcs: Node2D = arena.get("_pieces")
	# ⚠ 别复用 `hint` 这个名字：第 6b 段已经有一个 MatchCellHint 实例了，
	#   GDScript 同作用域重名 = parse error = 整个脚本不加载、探针零输出挂死。
	var hintn: Node2D = arena.get("_cell_hint")
	var own_z := 0
	for t3 in toks2.get_children():
		if t3 is MatchCardToken:
			own_z = (t3 as MatchCardToken).z_index
			break
	_check(pcs != null and hintn != null
			and hintn.z_index < toks2.z_index and toks2.z_index < pcs.z_index,
			"层叠顺序：空格呼吸框 < 卡片 < 棋子（激活的 BOSS 不被牌挡住）",
			"hint=%d token=%d piece=%d" % [hintn.z_index, toks2.z_index, pcs.z_index])
	_check(own_z == 0, "token 自己不再写死 z —— 层叠由容器统一给，两处都设等于叠两遍",
			"token 自身 z=%d" % own_z)

	# ---- 7b. 切档按钮：五档循环一圈回到原位，且每次都真的重铺手牌 ----
	var kind_btn: Button = arena.get("_kind_btn")
	_check(kind_btn != null, "对局界面有「卡面」切换按钮")
	if kind_btn != null:
		var start_kind := CharacterData.match_card_kind
		var labels: Array = []
		for k in MatchCard.KINDS:
			labels.append(kind_btn.text)
			kind_btn.pressed.emit()
			await get_tree().process_frame
		_check(labels.size() == MatchCard.KINDS.size(),
				"按 %d 次正好走完所有档位" % MatchCard.KINDS.size(), " | ".join(PackedStringArray(labels)))
		_check(CharacterData.match_card_kind == start_kind,
				"循环一圈回到起始档位（不会越界或漏档）",
				"%s → %s" % [start_kind, CharacterData.match_card_kind])
		_check(kind_btn.text.contains("卡面："), "按钮上写着当前档位", kind_btn.text)
		CharacterData.match_card_kind = ""
		MatchCard.clear_cache()
	print("   手牌 %d 张 · token %d 张（暗 %d）" % [cards_total, token_kinds, hidden_tokens])

	for c in get_children():
		if c != arena:
			c.queue_free()
	arena.queue_free()
	await get_tree().process_frame

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  FAIL ", f)
	get_tree().quit(1 if _fails.size() > 0 else 0)
