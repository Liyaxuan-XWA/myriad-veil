extends Node2D
## 真棋子对决验证（2026-11-02 卡片自走棋第 4 步）
##
## 规则层用的是抽象战斗模型，只能证明状态机闭合。这里换**真 BOSS 场景**上场，
## 回答三个探针规则层答不了的问题：
##   ① 照影界那三只在棋盘上会不会整只发呆（它们原本绕过统一索敌直查 player 组）；
##   ② 棋子之间能不能真的互相造成伤害、能不能打死；
##   ③ 位移技 / 转阶段击退会不会把棋子顶出战场边界。
## 同时量出真实 TTK，用来校准 MatchAdapter 里「attack_power 直接当 DPS」那个约定。
##
## 用法：godot --headless --path . res://tools/probe_match_pieces.tscn -- --no-save

var _passes := 0
var _fails: Array = []

## 每场最多跑多少秒真实模拟时间。超了就记为「打不死」，不当失败
## （面板是 ±20% 窄带，两只同量级的互相啃本来就该很久，这里要抓的是"不动/不打"）。
## 可在命令行覆盖：`-- --no-save limit=10 duels=1`（无头模拟很慢时先小跑量速率）
var duel_limit := 45.0
var duel_count := 5

const DUELS := [
	["boss_04", "boss_03"],        # 观澜：原本直查 player 组 → 停摆
	["boss_04_b", "boss_02_c"],    # 执烛：同上
	["boss_04_c", "boss_01"],      # 叠纸：同上
	["world_core_zhuji", "boss_02"],   # 苍角：曾实测 0 输出（装成了通用 prototype）
	["world_core_shihou", "boss_02_b"],  # 石犼：卡包 id 与区域表 id 不同名，专测这条
]

## 四位核心必须是 WorldEnemy —— 它们在正常玩法里的招式来自
## `SecretWorldDB.CORE_SKILLS`，由 `WorldEnemy.configure()` 安装。
## 若装配时错走 `boss.tscn`（通用 prototype_boss），四只会变成同一套假招式，
## 实测苍角 / 火麟十秒 0 输出。这条断言就是为了让这种"静默装错实体"当场响。
const CORE_IDS := ["world_core_lianqi", "world_core_zhuji",
	"world_core_jiedan", "world_core_shihou"]


func _check_cores_are_world_enemy() -> void:
	var bad: Array = []
	for id in CORE_IDS:
		var p := MatchAdapter.spawn_piece(self, String(id), 0, Vector2i(2, 2))
		if p == null:
			bad.append(String(id) + ":null")
			continue
		if not (p is WorldEnemy):
			bad.append("%s:不是 WorldEnemy（%s）" % [id, p.get_script().resource_path])
		elif (p.get("skill_ids") as Array).is_empty() \
				and (p.get("_core_skills") as Array).is_empty():
			bad.append(String(id) + ":没有招式表")
		elif String(p.get("boss_id")) != String(id):
			bad.append("%s:boss_id 被写成 %s" % [id, p.get("boss_id")])
		elif Vector2(p.get("spawn_home")) != p.position:
			bad.append("%s:spawn_home 还指着大世界坐标 %s" % [id, str(p.get("spawn_home"))])
		p.queue_free()
		await get_tree().process_frame
	_check(bad.is_empty(), "四位核心装成 WorldEnemy 且带真招式表与正确的脱战锚点", str(bad))


## 血条染色必须覆盖**全部 16 位 × 两支队伍**。
## 原来只在 probe_match_ranged 里测了一只 BossBase 棋子，于是
## `WorldEnemy._setup()` 在 `super._ready()` 之后按 `enemy_kind` 把颜色刷回去
## 这件事没人发现 —— 四只大陆核心棋子哪怕属于我方也顶着红色血条
## （2026-11-03 用户报「血条颜色显示错误」）。
func _check_hp_bar_colors() -> void:
	var bad: Array = []
	for id in MatchDB.CARD_POOL:
		for team in [0, 1]:
			var p := MatchAdapter.spawn_piece(self, String(id), int(team), Vector2i(0, 0))
			if p == null:
				bad.append("%s:%d队=null" % [String(id), int(team)])
				continue
			var bar: ColorRect = p.get_node_or_null("HPBarBG/HPBar")
			var want := BossBase.TEAM_HP_GREEN if int(team) == 0 else BossBase.TEAM_HP_RED
			if bar == null:
				bad.append("%s:%d队=场景里没有 HPBarBG/HPBar" % [String(id), int(team)])
			elif bar.color != want:
				bad.append("%s:%d队=%s 应为 %s" % [String(id), int(team), bar.color, want])
			p.queue_free()
			await get_tree().process_frame
	_check(bad.is_empty(), "16 位棋子 × 双方血条都按队伍染色", str(bad))


## 观澜镜像（MirrorImage）不是 BossBase，`host.child_entered_tree` 那条染色路径管不到它；
## 它的假血条原先只看 faction，而棋局里 faction 由 is_ally 派生（我方棋子 is_ally=false
## ⇒ faction="boss"）⇒ 我方分身顶着敌方红（2026-11-07 用户报「我方的分身也显示红色」）。
## 这里走真实棋子 → _spawn_image() 链路，比对分身与本体是否同队同色。
func _check_mirror_hp_bar_colors() -> void:
	var bad: Array = []
	for team in [0, 1]:
		var p := MatchAdapter.spawn_piece(self, "boss_04", int(team), Vector2i(0, 0))
		if p == null:
			bad.append("%d队=观澜棋子生成失败" % int(team))
			continue
		var img: MirrorImage = null
		if p.has_method("_spawn_image"):
			img = p.call("_spawn_image", 0) as MirrorImage
		if img == null or img._fake_fill == null:
			bad.append("%d队=镜像/假血条没生成" % int(team))
		else:
			var want := BossBase.TEAM_HP_GREEN if int(team) == 0 else BossBase.TEAM_HP_RED
			var got: Color = img._fake_fill.color
			if absf(got.r - want.r) > 0.001 or absf(got.g - want.g) > 0.001 \
					or absf(got.b - want.b) > 0.001:
				bad.append("%d队=分身 %s 应为 %s" % [int(team), got, want])
			img.free()
		p.free()
		await get_tree().process_frame
	_check(bad.is_empty(), "观澜双方分身假血条与本体同队同色", str(bad))


## 读命令行开关。探针会跑很久，必须能"先小跑一把看要不要等"。
func _read_args() -> void:
	for raw in OS.get_cmdline_user_args():
		var s := String(raw)
		if s.begins_with("limit="):
			duel_limit = maxf(1.0, float(s.trim_prefix("limit=")))
		elif s.begins_with("duels="):
			duel_count = clampi(int(s.trim_prefix("duels=")), 1, DUELS.size())


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	_read_args()
	print("\n########## 真棋子对决 ##########  limit=%.0fs duels=%d" % [duel_limit, duel_count])
	_check_spawn_all()
	_check_cores_are_world_enemy()
	await _check_hp_bar_colors()
	await _check_mirror_hp_bar_colors()
	_check_sync_in_pick_window()
	var ttks: Array = []
	for i in range(mini(duel_count, DUELS.size())):
		var pair: Array = DUELS[i]
		print("     开打 %s vs %s ..." % [pair[0], pair[1]])
		ttks.append(await _duel(String(pair[0]), String(pair[1])))
	_report_ttk(ttks)
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for s in _fails:
		print("  ! ", s)
	get_tree().quit(1 if not _fails.is_empty() else 0)


func _check_spawn_all() -> void:
	var bad: Array = []
	for id in MatchDB.CARD_POOL:
		var p := MatchAdapter.spawn_piece(self, String(id), 0, Vector2i(0, 0))
		if p == null:
			bad.append(String(id) + ":null")
			continue
		var problems: Array = []
		if int(p.get("team_id")) != 0:
			problems.append("team_id=%s" % p.get("team_id"))
		if not p.is_in_group("match_piece"):
			problems.append("没进 match_piece 组")
		if bool(p.get("is_ally")):
			problems.append("is_ally 仍为真")
		var st := MatchDB.piece_stats(String(id))
		if absf(float(p.get("max_hp")) - float(st["hp"])) > 1.0:
			problems.append("max_hp=%.0f 期望=%.0f" % [float(p.get("max_hp")), float(st["hp"])])
		# ⚠ 半血上场：max_hp 没在 add_child 之前设就会中这条
		if absf(float(p.get("current_hp")) - float(st["hp"])) > 1.0:
			problems.append("current_hp=%.0f（半血上场）" % float(p.get("current_hp")))
		if absf(float(p.get("summon_life"))) > 0.001:
			problems.append("summon_life=%s（会凭空消散）" % p.get("summon_life"))
		if not p.has_method("set_arena_bounds"):
			problems.append("没有 set_arena_bounds")
		if problems.is_empty():
			p.queue_free()
		else:
			bad.append("%s: %s" % [id, ", ".join(problems)])
		await get_tree().process_frame
	_check(bad.is_empty(), "16 位全部能生成成棋子且面板/阵营/边界注入正确", str(bad))


## 选牌窗口里真棋子死了，规则层必须**当场**知道。
## 原来 `combat.step()` 只在 `_fighting` 分支里调用，于是窗口那 10 秒完全不镜像血量 ——
## 棋盘上已经躺了一只，HUD 的存活数还当两边都站着，玩家读成"一到选牌就时间暂停"
## （2026-11-03 实测 Engine.time_scale 全程 1.000，引擎根本没停，停的是镜像这一层）。
func _check_sync_in_pick_window() -> void:
	var st := MatchState.new()
	var live := MatchLiveCombat.new()
	st.combat = live
	var pool: Array = []
	for id in MatchDB.CARD_POOL:
		pool.append(String(id))
	st.start([pool.slice(0, 8), pool.slice(8, 16)], 424242, 0)
	st.apply_command({"t": "pick", "team": 1, "ids": MatchPolicy.decide_deck(st.legal_pool(1))})
	st.apply_command({"t": "pick", "team": 0, "ids": MatchPolicy.decide_deck(st.legal_pool(0))})
	for t in [0, 1]:
		var lk: Dictionary = MatchPolicy.decide_lock(st, t)
		if not lk.is_empty():
			st.apply_command({"t": "lock", "team": t,
					"down": int(lk["down"]), "up": int(lk["up"])})
	for guard in 40:
		if st.phase != MatchState.Phase.DEPLOY:
			break
		for t in [0, 1]:
			var mv: Dictionary = MatchPolicy.decide_deploy(st, t, st.rng)
			if not mv.is_empty():
				st.apply_command({"t": "deploy", "team": t,
						"card": int(mv["card"]), "cell": mv["cell"]})
	# 双方各交一张 → 结算、放真棋子进场
	var c0: Array = st.legal_activate(0)
	var c1: Array = st.legal_activate(1)
	st.apply_command({"t": "activate", "team": 0, "card": int(c0[0])})
	st.apply_command({"t": "activate", "team": 1, "card": int(c1[0])})
	var spawned: Array = []
	for e in st.drain_events():
		if String(e.get("t", "")) == "spawn":
			var p := MatchAdapter.spawn_piece(self, String(e["boss_id"]),
					int(e["team"]), e["cell"])
			if p != null:
				live.pieces[int(e["card"])] = p
				spawned.append(int(e["card"]))
	_check(spawned.size() == 2, "选牌窗口镜像测试需要先放两只真棋子进场", str(spawned))
	if spawned.size() != 2:
		return
	# 把状态拨回"选牌窗口"：_fighting=false，计时器还剩很多
	st.set("_fighting", false)
	st.timer = MatchDB.PICK_SECONDS
	var victim: Node = live.pieces[spawned[0]]
	victim.set("current_hp", 0.0)
	victim.set("state", 6)          # BossState.DEAD
	var before_alive := bool(st.cards[spawned[0]]["alive"])
	st.advance(1.0 / 30.0)          # 只走一帧
	_check(before_alive, "死之前规则层认为它活着", "")
	_check(not bool(st.cards[spawned[0]]["alive"]),
			"选牌窗口里棋子一死，规则层当帧就收到（不等到下一个战斗窗口）",
			"alive=%s hp=%.0f" % [bool(st.cards[spawned[0]]["alive"]),
					float(st.cards[spawned[0]]["hp"])])
	var other: Node = live.pieces[spawned[1]]
	_check(absf(float(st.cards[spawned[1]]["hp"]) - float(other.get("current_hp"))) < 0.01,
			"同一帧里另一只的血量也照常镜像回来",
			"规则层=%.0f 真实=%.0f" % [float(st.cards[spawned[1]]["hp"]),
					float(other.get("current_hp"))])
	# 收干净：这两只是塞进探针节点自己打的，留着会污染后面的对决样本
	for k in live.pieces.keys():
		var raw = live.pieces[k]
		if raw != null and is_instance_valid(raw):
			(raw as Node).queue_free()
	await get_tree().process_frame


## 跑一场对决，返回击杀用时（秒）；-1 表示超时无人生死


## 跑一场对决，返回击杀用时（秒）；-1 表示超时无人生死
func _duel(id_a: String, id_b: String) -> float:
	var a := MatchAdapter.spawn_piece(self, id_a, 0, Vector2i(1, 4))
	var b := MatchAdapter.spawn_piece(self, id_b, 1, Vector2i(4, 1))
	if a == null or b == null:
		_check(false, "%s vs %s 生成失败" % [id_a, id_b])
		return -1.0
	await get_tree().physics_frame
	var origin_a: Vector2 = a.position
	var origin_b: Vector2 = b.position
	var far_a := 0.0
	var far_b := 0.0
	var hurt_a := float(a.get("current_hp"))
	var hurt_b := float(b.get("current_hp"))
	# 首次出手用时。这条不是随便记的：每轮战斗窗口只有 ROUND_SECONDS（现在 20 秒），
	# 一只开局要召镜像 / 先摆阵 / 长前摇的 BOSS 若一个窗口内一下都打不出，
	# 它在整局里就永远慢半拍 —— 那是规则参数问题，不是它能靠校准攻击力解决的。
	var first_a := -1.0
	var first_b := -1.0
	var outside := 0
	var nan_seen := false
	var half := MatchDB.arena_half()
	var t := 0.0
	var killed := -1
	var frames := 0
	while t < duel_limit:
		await get_tree().physics_frame
		frames += 1
		t += get_physics_process_delta_time()
		if not is_instance_valid(a) or not is_instance_valid(b):
			break
		far_a = maxf(far_a, origin_a.distance_to(a.global_position))
		far_b = maxf(far_b, origin_b.distance_to(b.global_position))
		hurt_a = minf(hurt_a, float(a.get("current_hp")))
		hurt_b = minf(hurt_b, float(b.get("current_hp")))
		if first_a < 0.0 and hurt_a < float(a.get("max_hp")):
			first_a = t
		if first_b < 0.0 and hurt_b < float(b.get("max_hp")):
			first_b = t
		if a.global_position.x != a.global_position.x or b.global_position.x != b.global_position.x:
			nan_seen = true
			break
		if absf(a.global_position.x) > half.x + 4.0 or absf(b.global_position.x) > half.x + 4.0 \
				or absf(a.global_position.y) > half.y + 4.0 or absf(b.global_position.y) > half.y + 4.0:
			outside += 1
		if BossBase.is_unit_dead(a) or BossBase.is_unit_dead(b):
			killed = t
			break
	var label := "%s vs %s" % [id_a, id_b]
	_check(not nan_seen, label + " 位置未出现 NaN")
	_check(outside == 0, label + " 全程没有越出战场边界",
			"越界帧=%d 半宽=%.0f" % [outside, half.x])
	# 核心断言：两只都必须动起来。伤害断言要看得多久 —— 窗口被压到几秒时
	# "没打到"可能只是没轮到，所以只有跑满窗口才判失败，短窗口改为记录首次出手用时。
	_check(far_a > 8.0 and far_b > 8.0, label + " 两只都在移动（没有整只发呆）",
			"位移 %.0f / %.0f px" % [far_a, far_b])
	if duel_limit >= 20.0:
		_check(hurt_b < float(b.get("max_hp")) or BossBase.is_unit_dead(b),
				label + " A 在窗口内打到了 B", "B %.0f→%.0f" % [float(b.get("max_hp")), hurt_b])
		_check(hurt_a < float(a.get("max_hp")) or BossBase.is_unit_dead(a),
				label + " B 在窗口内打到了 A", "A %.0f→%.0f" % [float(a.get("max_hp")), hurt_a])
	print("     %s：模拟 %.1fs / %d 帧，位移 %.0f·%.0fpx，首次出手 A=%.1fs B=%.1fs（-1=窗口内未出手）" % [
		label, t, frames, far_a, far_b, first_a, first_b])
	if is_instance_valid(a):
		a.queue_free()
	if is_instance_valid(b):
		b.queue_free()
	await get_tree().process_frame
	return float(killed)


func _report_ttk(ttks: Array) -> void:
	var s := ""
	for v in ttks:
		s += "%.1fs  " % float(v)
	print("     实测击杀用时：", s, "（-1 = 超过 %.0f 秒未分生死）" % duel_limit)
