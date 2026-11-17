extends Node
## 叠纸 · 无头假玩家实测（2026-11-02）
## 真实 CombatArena + 真实 Player + 叠纸 AI，跑三种节奏各 30 秒：
##   A 贴脸循环：靠近 → 站桩输出 → 拉开；
##   B 中距绕圈：维持 360，站在折痕的贴合带里；
##   C 离痕远站：主动走到「离最近那条痕 > 贴合带」的位置 —— 空手可破那一面。
## 统计每式出手 / 落空 / **选招门禁违规**（起手那一帧既不盖本体也不盖对位落点却硬放），
## 并实测：折痕条数、圆牌数、穿缝真的换位置、玩家侧九门全部能用、二阶段自然推进、TTK。
## 用法：godot --headless --path . res://tools/probe_fold_play.tscn -- --no-save

const TICK := 0.1
const SIM_TIME := 30.0
const ALL_FORMS: Array[String] = [
	"form_fold_press", "form_fold_trace", "form_fold_stride", "form_fold_pressmark",
	"form_fold_shroud", "form_fold_tear", "form_fold_twin", "form_fold_triple",
]
## 裁痕与叠掩是状态招：它们本来就不该掉 BOSS 的血，用「能不能放 + 状态有没有挂上」验
const FOLD_STATE_SKILLS: Array[String] = ["skill_fold_seam", "skill_fold_shroud"]
const PLAYER_SKILLS: Array[String] = [
	"skill_fold_press", "skill_fold_trace", "skill_fold_stride", "skill_fold_seam",
	"skill_fold_shroud", "skill_fold_tear", "skill_fold_twin", "skill_fold_triple",
	"skill_fold_measure",
]

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	print("\n########## 叠纸 · 无头假玩家实测 ##########")
	await _run()
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _run() -> void:
	seed(20261102)
	for sid in PLAYER_SKILLS:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	CharacterData.active_skill_loadout = ["skill_fold_press", "skill_fold_seam",
		"skill_fold_trace", "skill_fold_stride"]
	CharacterData.passive_skill_loadout = ["skill_fold_measure"]
	CharacterData.current_realm = "元婴"
	CharacterData.realm_stage = 3
	_wear_baseline(1, 6)
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_04",
		"boss_id": "boss_04_c",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	for i in 4:
		await get_tree().process_frame
	var player: Node2D = arena.player
	var boss: Node2D = arena.boss
	_check(player != null and is_instance_valid(player), "真实 Player 已生成")
	_check(boss != null and is_instance_valid(boss), "真实 BOSS（叠纸）已生成")
	if player == null or boss == null:
		return
	player._apply_attributes_to_runtime(true)
	print("  玩家面板：HP %.0f · 物攻 %.0f · 法强 %.0f" % [
		player.max_hp, CharacterData.physical_attack(), CharacterData.spell_attack()])

	# ---------- 折痕场真的立起来了 ----------
	var field = boss._field
	_check(field != null and is_instance_valid(field), "FoldField 已挂在战场根节点")
	if field == null or not is_instance_valid(field):
		return
	_check((field.spans as Array).size() == 1, "一阶段场上只有一条折痕",
		"spans=%d" % (field.spans as Array).size())
	_check(field._seams.size() == 2, "一阶段两端各一枚圆牌", "seams=%d" % field._seams.size())
	var sp0: Dictionary = (field.spans as Array)[0]
	var a0: Vector2 = sp0.get("a", Vector2.ZERO)
	var b0: Vector2 = sp0.get("b", Vector2.ZERO)
	var lim: Vector2 = boss.arena_half_extents
	_check(a0.distance_to(boss.arena_center) < lim.x + 10.0
			and b0.distance_to(boss.arena_center) < lim.x + 10.0,
		"痕的两端都在场内（圆牌踩得到）", "A=%s B=%s" % [str(a0), str(b0)])

	# ---------- 穿缝：踩上圆牌必须从对侧出来 ----------
	var disc = field._seams[0]
	player.global_position = (disc as Node2D).global_position
	field._exit_guard.clear()
	field._re_cd.clear()
	var before: Vector2 = player.global_position
	await get_tree().create_timer(0.12).timeout
	var moved: float = before.distance_to(player.global_position)
	_check(moved > 120.0, "踩上圆牌真的被送到对侧那一头", "位移 %.0f px" % moved)
	_check(player.has_method("on_fold_crossed"), "玩家侧收到穿缝通知（被动量折吃这一次）")
	_check(player._fold_cross_left > 0.0 and player._fold_measure_on(),
		"穿缝后「量折」旗标已挂上（下一次攻击 +30%）")
	field._exit_guard.clear()
	field._re_cd.clear()

	# ---------- 三段节奏实测 ----------
	var a := await _sim(player, boss, 0)
	var b := await _sim(player, boss, 1)
	var c := await _sim(player, boss, 2)
	_report("A 贴脸循环", a)
	_report("B 痕内绕圈", b)
	_report("C 离痕远站", c)

	var seen := {}
	var gate_total := 0
	for s in [a, b, c]:
		for k in (s as Dictionary)["att"].keys():
			seen[String(k)] = true
		gate_total += int((s as Dictionary)["gate_violation"])
	_check(gate_total == 0, "三段都没有「本体与对位落点都不在形状里却硬放」的空放",
		"违规 %d 次" % gate_total)
	for f in ALL_FORMS:
		if f == "form_fold_triple":
			continue
		_check(seen.has(f), "AI 真的用过 " + String(f).replace("form_fold_", ""))
	_check(seen.has("form_fold_triple") or int(a["max_phase"]) < 2,
		"二阶段终局招在打到半血后出现过", "seen=%s" % str(seen.has("form_fold_triple")))
	_check(int(a["max_phase"]) >= 2, "假玩家把战斗自然推进到二阶段",
		"phase=%d" % int(a["max_phase"]))

	# ---------- 二阶段专属机制层：折两次 ----------
	_revive(player)
	boss.current_hp = boss.max_hp * 0.55
	boss.phase = 1
	boss.state = BossBase.BossState.IDLE
	boss.take_damage(boss.max_hp * 0.07, player, "physical", "water")
	await get_tree().create_timer(0.2).timeout
	for i in 40:
		await get_tree().create_timer(0.1).timeout
		if int(boss.phase) >= 2:
			break
	_check(int(boss.phase) >= 2, "血量掉到 40% 后进入二阶段")
	await get_tree().create_timer(1.4).timeout
	_check((field.spans as Array).size() == 2, "二阶段场上有两条折痕（三个互通区）",
		"spans=%d" % (field.spans as Array).size())
	if (field.spans as Array).size() == 2:
		var s1: Dictionary = (field.spans as Array)[0]
		var s2: Dictionary = (field.spans as Array)[1]
		var d1 := FoldLaw.crease_dir(s1.get("a", Vector2.ZERO), s1.get("b", Vector2.ZERO))
		var d2 := FoldLaw.crease_dir(s2.get("a", Vector2.ZERO), s2.get("b", Vector2.ZERO))
		_check(absf(absf(d1.dot(d2)) - 1.0) < 0.05,
			"第二条痕与第一条平行（三区成立的前提）", "dot=%.3f" % d1.dot(d2))
	_check(field._seams.size() == 4, "二阶段两对圆牌", "seams=%d" % field._seams.size())
	_check(absf(FoldLaw.reach_for(2) - FoldLaw.REACH_P2) < 0.01,
		"二阶段贴合带收窄到 %.0f" % FoldLaw.REACH_P2)

	# ---------- 反逃课：站远必须被处理 ----------
	var c_att: Dictionary = c["att"]
	_check(int(c_att.get("form_fold_pressmark", 0)) + int(c_att.get("form_fold_tear", 0)) > 0,
		"玩家离痕远站时它改用押痕 / 碎痕（有反制，不是干瞪眼）",
		"押痕 %d / 碎痕 %d" % [int(c_att.get("form_fold_pressmark", 0)),
			int(c_att.get("form_fold_tear", 0))])
	# ⚠ 这条断言在 2026-11-05 被改动**取代**了，不是放松、是原来那句写错了口径：
	# 旧版断言「离痕远站时镜像面一次也不成立」，理由是痕随机摆、玩家能走出痕的影响圈。
	# 现在痕是**照着玩家摆的**（意图折），"离痕远"不再是绝对安全位 —— 再拿这条当守卫，
	# 等于把新逻辑判成 bug。真正该钉的是几何硬边界：**离 BOSS 足够远时这一折根本摆不出来**，
	# 那才是这套机制的活路，而且它和场地怎么摆无关。
	var escape_d := FoldLaw.reach_for(1) * 2.0 + FoldLaw.AIM_LANDING + FoldLaw.HIT_MARGIN * 2.0 + 20.0
	_check(not FoldLaw.aim_feasible(escape_d, FoldLaw.reach_for(1)),
			"离 BOSS 超过折痕窗口（%.0f）时镜像面摆不出来 —— 这才是真正的活路" % escape_d)
	_check(FoldLaw.aim_feasible(escape_d - 120.0, FoldLaw.reach_for(1)),
			"窗口边界内侧仍然可折（活路不是靠贴脸换的）")
	# 改动之后最要紧的一条新保证：痕真的参与了进攻（旧版三段全是 0）
	var fold_hits := int(a["fold_landings"]) + int(b["fold_landings"]) + int(c["fold_landings"])
	_check(fold_hits > 0,
			"折痕现在真的在帮 BOSS 打人：三段合计纯镜像命中 %d 次（改前三段全是 0）" % fold_hits)
	_check(int(b["fold_windows"]) > 0,
		"站在贴合带里时，镜像那一面确实成立（机制真的在生效）",
		"B 镜像面可用 %d 次 / 纯镜像命中 %d 次" % [int(b["fold_windows"]),
				int(b["fold_landings"])])
	## ⚠ 这里**不能**断言"站远挨得更少"。设计案 §1.4 要的是反过来：
	## 退到贴合带外只拆掉镜像那一面，它立刻改用押痕 / 碎痕这两式**不依赖镜像**的招，
	## 所以站远仍然会挨打 —— 这才是"有弱点但不可逃课"。真正要钉死的是上面两条：
	## 镜像面在 C 段一次都不成立、在 B 段成立。
	##
	## 2026-11-05 意图折之后，"C 的镜像次数 < B" 这种相对断言已经站不住了：
	## 痕是照着人摆的，躲痕不再是绝对安全位（实测 C 7 次 / B 6 次，差在噪声里）。
	## 所以这里只留两条能站住的：**硬边界**（上面 aim_feasible 那两条）与**不可逃课**（下面这条）。
	_check(int(c["landings"]) > 0,
		"离痕远站仍然会挨打（站远不是无敌点，不可逃课）",
		"C 段挨了 %d 次" % int(c["landings"]))
	_check(float(b["player_hp_lost"]) > 0.0, "痕内绕圈仍然会被打到（不是无敌靶）",
		"掉血 %.0f" % float(b["player_hp_lost"]))
	_check(is_instance_valid(boss) and not player.is_dead, "三段模拟都没有异常 / 玩家没被秒杀")

	# ---------- 2026-11-05 口径：痕=射程放大器，BOSS 追着对位落点站 ----------
	await _stance_guards(player, boss, field)

	# ---------- 玩家侧九门全部能用（不靠 BOSS 的痕也能出双落点）----------
	await _player_side(player, boss)

	# ---------- 两件掉落装备的用途差（有代码就必须有测试）----------
	await _equipment_effects(player, boss)
	# 装备测试把六个槽都清空了，TTK 之前必须把夹具档穿回来
	_wear_baseline(1, 6)
	player._apply_attributes_to_runtime(true)

	# ---------- TTK
	await _ttk(player, boss)
	GameState.battle_context = {}


## 玩家侧继承：先测「完全没有折痕的普通场景」也不能报错，再测有痕时的双落点
## 把 BOSS 摆回「能自由走位」那一档：状态 IDLE + 速度清零 + 锁住选招计时。
## 不这么做的话，上一段留下的起手/收招状态会让走位层当拍直接 return，
## 量到的"它没动"其实是状态机挡的，不是逻辑错（本段两次三天地红过一次）。
func _hold_ai(boss: Node2D) -> void:
	boss.state = BossBase.BossState.IDLE
	boss.velocity = Vector2.ZERO
	boss._decide_wait = 1.0e6


## 意图折 · 站位 · 出手优先级（2026-11-05）
## 这五条是「靠折痕把攻击接到玩家身上」的骨架，少任何一条，
## 痕就退回用户报的那个样子：画得漂亮、位置随机、四十年也打不到人。
func _stance_guards(player: Node2D, boss: Node2D, field) -> void:
	print("\n──── 折痕当射程放大器：站位与出手 ────")
	var press_range := float(MoveDB.resolve_boss("form_fold_press").get("range", 178.0))
	for k in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(k)
	## 夹具：整段冻住 BOSS 的物理，全部改成"直接调决策函数"。
	## 留着物理时，三段模拟剩下的起手 / 三重落纸会在两次断言之间改写 spans，
	## 同一份代码能连绿三轮、下一轮突然红七条 —— 那是夹具在踩自己的几何，不是逻辑飘
	## （2026-11-05 实测：加冻结之前 7 红，加完之后稳定全绿）。
	boss.set_physics_process(false)
	boss._triple_plan.clear()
	boss._triple_left = 0.0
	## 三段模拟里玩家会给它挂沉默/眩晕，而 `is_skill_locked()` 一走位层就直接 return。
	## 物理又冻住了没人替它把这些计时往下减 —— 不清就是"步速 0"的假红（实测三轮一遇）。
	boss._cc_silence_left = 0.0
	boss._cc_slow_left = 0.0
	boss.phase_transitioning = false
	## 夹具：停掉周期折与主动重折，免得量到一半痕自己跑了
	field._down_left = 0.0
	field._preview_left = 0.0
	field._refold_left = 1.0e6
	boss._refold_ask = 1.0e6
	boss._cools.clear()
	## 三重落纸也是条件招，且它自己会重排两条痕 —— 这一段不许它插进来
	boss._cools["form_fold_triple"] = 9999.0
	boss._recent.clear()
	boss._decide_wait = 0.0
	boss.state = BossBase.BossState.IDLE
	boss.velocity = Vector2.ZERO
	## 血抬满：三段模拟把它打到过半，血线节点会在测量中途触发叠掩/特殊演出，
	## 招式一起手就离开 IDLE/CHASE，走位层当拍不执行 —— 量到的"没走"是假的。
	boss.current_hp = boss.max_hp
	var b0: Vector2 = boss.global_position
	var pp := b0 + Vector2(0.0, 340.0)
	player.global_position = pp
	player.velocity = Vector2.ZERO
	player.invincible_timer = 0.0

	# —— ① 押痕是教科书：折完对位点必须**正好**在 BOSS 脚下（这一式不取偏置）
	_check(bool(field.bisect(b0, pp, 520.0)), "押痕在 d=340 摆得出这一折")
	var img0: Vector2 = boss._fold_image_at(pp, false)
	_check(img0 != Vector2.INF and img0.distance_to(b0) <= 10.0,
		"押痕把玩家的落点正好压在 BOSS 脚下（玩家一眼看懂'折过来就在我脚下'）",
		"偏 %.1f px" % (0.0 if img0 == Vector2.INF else img0.distance_to(b0)))
	_check(float(field._preview_left) == 0.0
			and absf(float(field._refold_left) - FoldLaw.refold_for(int(boss.phase))) < 0.01,
		"押痕自己就是一次重折：排队中的预告作废、周期重新上表（刚压好的痕不会被随机折抹掉）",
		"preview=%.2f refold=%.1f" % [float(field._preview_left), float(field._refold_left)])

	# —— ② 周期性意图折：带偏置，但落点仍要收进按纸射程
	var lead_pt := pp + Vector2(120.0, 0.0)
	field.set_aim(b0, lead_pt)
	_check(bool(field._aim_ready), "锁意图：d=%.0f 时窗口算得出来" % b0.distance_to(lead_pt))
	field.rebuild_aimed()
	var img1: Vector2 = boss._fold_image_at(lead_pt, false)
	_check(img1 != Vector2.INF and img1.distance_to(b0) <= FoldLaw.AIM_LANDING,
		"意图折的落点收在按纸圆里（≤ %.0f）—— 痕摆完就该打得到人，不是摆着好看" % FoldLaw.AIM_LANDING,
		"实际 %.1f px" % (0.0 if img1 == Vector2.INF else img1.distance_to(b0)))

	# —— ③ 预告不再没收放大器；碎痕仍是全场唯一的免费窗口
	field._preview_left = FoldLaw.PREVIEW_TIME
	_check(boss._fold_image_at(lead_pt, false) != Vector2.INF,
		"压痕预告期间当前这条痕照样结算（旧版在此判空，每次重折自己没收 1.2 秒）")
	field._preview_left = 0.0
	field._down_left = FoldLaw.TEAR_DOWN_TIME
	_check(boss._fold_image_at(lead_pt, false) == Vector2.INF,
		"碎痕期间镜像才真的不存在（唯一免费窗口，没被稀释成两个）")
	field._down_left = 0.0

	# —— ④ 落点在扇形外、但确实在前方 → 朝落点走过去
	## 玩家摆在 BOSS 下方 340（u = (0,+1)），痕水平摆在 t=(340+250)/2 处
	## ⇒ 对位点 = 2t − d = 250 落在 BOSS 正前方 250，比扇形 178 远一档
	var c_at := Vector2(b0.x, b0.y + (340.0 + 250.0) * 0.5)
	var nrm := Vector2.RIGHT
	field.spans = [{"a": c_at - nrm * 260.0, "b": c_at + nrm * 260.0}]
	field._rebuild_nodes()
	var img2: Vector2 = boss._fold_image_at(player.global_position, false)
	_check(img2 != Vector2.INF
			and img2.distance_to(boss.global_position) > press_range,
		"先确认这一摆确实落在扇形之外（不然后面的走位无从证明）",
		"落点离 BOSS %.0f · 扇形 %.0f" % [
			0.0 if img2 == Vector2.INF else img2.distance_to(boss.global_position), press_range])
	_hold_ai(boss)
	boss._stance_on_fold()                      ## 直接问决策，不靠跑物理碰运气
	var step: Vector2 = boss.velocity
	var toward: Vector2 = Vector2.ZERO if img2 == Vector2.INF \
			else (img2 - boss.global_position).normalized()
	_check(step.length() > 20.0 and step.dot(toward) > step.length() * 0.7,
		"落点在扇形外时它朝落点走 —— 痕就是它的瞄准，不是站桩等痕转回来",
		"步速 %.0f · 与落点方向 cos=%.2f" % [step.length(),
			step.dot(toward) / maxf(step.length(), 1.0)])

	# —— ⑤ 已经够得到的位置不许为了追落点走开（玩家贴到脸上时反过来转身，是最扎眼的蠢样）
	## 170 而不是 110：两个 CharacterBody2D 在 110 会互相挤出去（实测漂 15~40 px），
	## 那量的就不是走位逻辑而是碰撞分离。170 仍在本体扇形的 196 里，且不贴身。
	_place(player, boss, Vector2(0.0, 170.0))
	_hold_ai(boss)
	boss._stance_on_fold()
	_check(boss.velocity == Vector2.ZERO,
		"本体扇形已经盖得住时站住不打转（贴脸不许转身去追更远的对位落点）",
		"速度 %s" % str(boss.velocity))

	# —— ⑥ 只有折痕够得到的那一刻，按纸插队兑现
	_place(player, boss, Vector2(0.0, 340.0))   ## 退回"本体够不到"那一档
	field._refold_left = 1.0e6
	_check(bool(field.bisect(boss.global_position, player.global_position, 520.0)),
		"重新押一次痕（构造'本体够不到、镜像够得到'的那一瞬）")
	boss._decide_wait = 0.0
	boss.state = BossBase.BossState.IDLE
	## 逐式清零，但三重落纸保持压制：`_cools.clear()` 会把上面那句压制一起清掉，
	## 于是这一发被三重落纸顶掉、断言报"出招 form_fold_triple"（2026-11-05 就红在这儿）
	for f in ["form_fold_press", "form_fold_trace", "form_fold_stride",
			"form_fold_pressmark", "form_fold_shroud", "form_fold_tear", "form_fold_twin"]:
		boss._cools[f] = 0.0
	boss.velocity = Vector2(300.0, 0.0)      ## 故意带着走位速度起手
	boss._choose()
	_check(String(boss._current_skill) == "form_fold_press",
		"本体够不到而折痕够得到 → 立刻按纸兑现这一刀（不被条件招吃掉）",
		"实际出招 %s" % String(boss._current_skill))
	_check(boss.velocity == Vector2.ZERO,
		"起手瞬间收住速度（前摇里还滑着就会漂出扇形，落点算的是起手那一刻的账）")
	boss._current_skill = ""
	boss.state = BossBase.BossState.IDLE
	boss._refold_ask = 0.0
	field._refold_left = FoldLaw.refold_for(int(boss.phase))
	boss.set_physics_process(true)   ## 装备段 / 三段 / TTK 都要它自己行动


## 摆位必须「位置 + 速度」一起钉死：只改位置的话，上一门招式留下的速度还挂在
## `player.velocity` 上，而 BOSS 的预判吃的就是速度 —— 假人明明站着不动，
## BOSS 却以为它在冲刺，提前量把人算到 190px 之外，判成"本体够不到"，
## 于是转身去追对位落点，玩家这一门的判定距离当场被拉开（实测 press 打空）。
func _place(player: Node2D, boss: Node2D, off: Vector2) -> void:
	player.global_position = boss.global_position + off
	player.velocity = Vector2.ZERO


func _player_side(player: Node2D, boss: Node2D) -> void:
	_revive(player)
	## 这一段量的是「玩家这八式在真实战场里打不打得到人」，不是 BOSS 会不会走位。
	## 必须冻住它的物理：① 玩家摆在 110 时两个 CharacterBody2D 互相挤开，1 秒里
	##   BOSS 被推走 88px，按纸的 178 扇形量成"打不到"；② 它中途出招还会把玩家顶飞，
	##   下一门的摆位就成了运气。BOSS 自己的行为由上面的站位段与三段模拟单独量。
	boss.set_physics_process(false)
	boss.current_hp = boss.max_hp
	_place(player, boss, Vector2(0.0, 120.0))
	player.mana = player.max_mana
	player.stamina = player.max_stamina
	var field = boss._field
	# 先把场上痕临时作废，验「没痕也能放」（不许出现"这招在别处完全不能用"）
	field.disable_for(60.0)
	var no_field_ok := 0
	var no_field_miss := ""
	for sid in PLAYER_SKILLS:
		if sid == "skill_fold_measure" or sid in FOLD_STATE_SKILLS:
			continue
		CharacterData.active_skill_loadout = [sid, "skill_fold_press",
				"skill_fold_trace", "skill_fold_stride"]
		_revive(player)
		## 摆位必须固定：循痕 / 双屏的射程是定值，玩家被上一门甩到别处就会测成"打不到"
		_place(player, boss, Vector2(0.0, 150.0))
		player.attack_dir = (boss.global_position - player.global_position).normalized()
		var hp0: float = boss.current_hp
		if player.try_use_skill(sid):
			await get_tree().create_timer(0.9).timeout
			if boss.current_hp < hp0 - 0.5:
				no_field_ok += 1
			else:
				no_field_miss += "%s " % sid.replace("skill_fold_", "")
	_check(no_field_ok >= 5, "场上没有折痕时，6 门伤害向里至少 5 门照样造成伤害",
		"命中 %d/6 门，缺：%s" % [no_field_ok, no_field_miss])
	field.disable_for(0.0)
	(field.spans as Array).clear()
	field._down_left = 0.0
	field.rebuild_near(player.global_position)

	# 个人痕：裁痕之后应当能拿到对位落点（不依赖 BOSS 那条）
	CharacterData.active_skill_loadout = ["skill_fold_seam", "skill_fold_press",
			"skill_fold_trace", "skill_fold_stride"]
	_revive(player)
	_place(player, boss, Vector2(0.0, 150.0))
	player.skill_cooldowns.clear()
	player.mana = player.max_mana
	_check(player.try_use_skill("skill_fold_seam"), "裁痕可释放")
	await get_tree().create_timer(0.35).timeout
	_check(player._fold_has_field(), "裁痕生成了玩家自己的折痕")
	var tgt := boss as Node2D
	var img: Vector2 = player._fold_image_of(tgt)
	_check(img != Vector2.INF or player._fold_arena_field() != null,
		"玩家侧能取到对位落点（借自己或借场上那条）")

	# 逐门实测：都要求真的打到人
	var ok := 0
	var detail := ""
	for sid in PLAYER_SKILLS:
		if sid == "skill_fold_measure":
			continue
		_revive(player)
		# BOSS 也要逐门重置：这里只 _revive(player)，七门连打的伤害会累计把 62000 血打死。
		# 一旦打死，is_unit_dead 让它不再是可打目标 → _fold_nearest_enemy_from 返回 null →
		# 后面那几门（twin 是第 7 位）就报「放=true 伤=0」。表现为随机红，其实是判据自身漏重置。
		boss._cools.clear()
		boss.current_hp = boss.max_hp
		boss.phase = 1
		boss.state = BossBase.BossState.IDLE
		player._fold_field = null
		field.rebuild_near(player.global_position)
		CharacterData.active_skill_loadout = [sid, "skill_fold_press",
				"skill_fold_trace", "skill_fold_stride"]
		player.skill_cooldowns.clear()
		player.mana = player.max_mana
		player.stamina = player.max_stamina
		_place(player, boss, Vector2(0.0, 110.0))
		if sid == "skill_fold_twin" or sid == "skill_fold_triple":
			## 这两式是"借痕开火"：场上没有靠近人的折面时它们本来就没有目标（判定没错），
			## 但"这一门到底打不打得动人"必须给一个确定存在的折面 —— 用押痕把痕压到两者正中。
			## 随机痕 + 固定 110 摆位就是上一版偶发红的那枚硬币（实测 twin 有时 7/8）。
			field.bisect(player.global_position, boss.global_position, 520.0)
		if sid == "skill_fold_trace" or sid == "skill_fold_tear":
			## 这两式沿痕走：要的是「一条真的从玩家伸到 BOSS 那边的痕」。
			## 随机痕的线段可能只到人这一头、另一端根本没经过 BOSS，
			## 于是走廊盖不到 —— 那是摆位运气，不是招式不能用（实测 tear 偶发 0 伤）。
			var u := (boss.global_position - player.global_position).normalized()
			var mid := (boss.global_position + player.global_position) * 0.5
			field.spans = [{"a": mid - u * 400.0, "b": mid + u * 400.0}]
			field._rebuild_nodes()
		var hp1: float = boss.current_hp
		var b_cast: Vector2 = boss.global_position   ## 施放那一刻 BOSS 在哪（之后它有没有走开）
		# 施放瞬间 BOSS 已经死了 → 这是判据没重置干净，不是招式的问题，单独报出来
		var dead_before := bool(BossBase.is_unit_dead(boss))
		var cast: bool = player.try_use_skill(sid)
		await get_tree().create_timer(1.0).timeout
		var dmg: float = hp1 - boss.current_hp
		if dead_before:
			detail += "%s(施放前BOSS已死) " % sid.replace("skill_fold_", "")
			continue
		## 状态招只验「放得出去 + 状态挂得上」，伤害向才要求真的掉血
		if sid in FOLD_STATE_SKILLS:
			var st_ok: bool = false
			if sid == "skill_fold_seam":
				st_ok = player._fold_has_field()
			elif sid == "skill_fold_shroud":
				st_ok = player._fold_shroud_left > 0.0
			if cast and st_ok:
				ok += 1
				continue
		if cast and dmg > 0.5:
			ok += 1
		else:
			## 顺手把"为什么没伤"要的信息带上：距离与 BOSS 状态 —— 这一式的判定是几何的，
			## 摆位被推开的话必须一眼看出来，不能只报一个 0（2026-11-05 排查站位改造时就缺这个）
			detail += "%s(放=%s 伤=%.0f d=%.0f B态=%s 招=%s 痕=%d) " % [
				sid.replace("skill_fold_", ""), str(cast), dmg,
				player.global_position.distance_to(boss.global_position),
				str(boss.state), String(boss._current_skill), (field.spans as Array).size()]
	_check(ok == 8, "折影八式在玩家侧全部可用（6 门掉血 + 2 门挂上状态）",
		"%d/8 %s" % [ok, detail])
	var passive := SkillDB.get_passive_by_effect("fold_measure")
	_check(not passive.is_empty(), "被动「量折」按 passive_effect 可查到",
		str(passive.get("skill_id", "")))
	boss.set_physics_process(true)   ## 装备段与 TTK 段要它照常行动
	player._fold_reset()


## TTK 标定：贴住自动普攻 + 循环功法，量「这套养成打这管血要多久」
func _ttk(player: Node2D, boss: Node2D) -> void:
	_revive(player)
	player._fold_reset()
	boss._cools.clear()
	boss.current_hp = boss.max_hp
	boss.phase = 1
	boss.state = BossBase.BossState.IDLE
	boss._field.set_phase(1)
	boss._field.rebuild_near(player.global_position)
	player.invincible_timer = 1.0e9
	var t := 0.0
	var atk_tick := 0.0
	var sk_tick := 0.0
	var phase2 := -1.0
	var killed := -1.0
	while t < 150.0:
		await get_tree().create_timer(TICK).timeout
		t += TICK
		if not is_instance_valid(boss):
			break
		player.invincible_timer = 1.0e9
		player.hp = player.max_hp
		player.mana = player.max_mana
		player.stamina = player.max_stamina
		if boss.state == BossBase.BossState.DEAD:
			killed = t
			break
		if int(boss.phase) == 2 and phase2 < 0.0:
			phase2 = t
		var to_b: Vector2 = boss.global_position - player.global_position
		if to_b.length() > 90.0:
			player.global_position = boss.global_position - to_b.normalized() * 86.0
		player.attack_dir = to_b.normalized()
		atk_tick -= TICK
		if atk_tick <= 0.0:
			atk_tick = CharacterData.attack_interval()
			if not player.is_attacking and not player.is_dead:
				player._start_attack()
		sk_tick -= TICK
		if sk_tick <= 0.0:
			sk_tick = 1.6
			for sid in CharacterData.active_skill_loadout:
				if player.try_use_skill(String(sid)):
					break
	print("      TTK：phase2=%.1f kill=%.1f boss 余血 %.0f/%.0f" % [
		phase2, killed, boss.current_hp, boss.max_hp])
	## 夹具档（元婴初期·道器+6）只用来验行为；血量标定交给 probe_fold_live_play 读实机存档量
	_check(killed > 0.0 or boss.current_hp < boss.max_hp * 0.75,
		"夹具档假玩家确实打得动这管血（不是打不动的墙）",
		"kill=%.1f 余血 %.0f" % [killed, boss.current_hp])


## mode 0 贴脸循环 / 1 痕内绕圈 / 2 离痕远站
func _sim(player: Node2D, boss: Node2D, mode: int) -> Dictionary:
	var att := {}
	var whiff := {}
	var gate := {}
	var last_skill := ""
	var pending: Array = []
	var hp_min := 0.0
	var max_phase := 1
	var field = boss._field
	boss.current_hp = boss.max_hp * (0.56 if mode == 0 else 1.0)
	boss.phase = 1
	boss.state = BossBase.BossState.IDLE
	boss._cools.clear()
	boss._recent.clear()
	boss._shroud_left = 0.0
	boss._nodes_done.clear()
	boss._hits.clear()
	boss._triple_plan.clear()
	boss._direct_landings = 0
	boss._fold_landings = 0
	boss._fold_windows = 0
	boss._gate_blocked = 0
	field.set_phase(1)
	field._down_left = 0.0
	field.rebuild_near(player.global_position)
	_revive(player)
	hp_min = player.max_hp
	player.global_position = boss.global_position + Vector2(0.0, 260.0)
	await get_tree().process_frame
	var start_dist: float = player.global_position.distance_to(boss.global_position)
	var t := 0.0
	var strafe := 1.0
	while t < SIM_TIME:
		await get_tree().create_timer(TICK).timeout
		t += TICK
		if not is_instance_valid(player) or not is_instance_valid(boss):
			break
		if player.is_dead:
			_revive(player)
		player.stamina = player.max_stamina
		player.mana = player.max_mana
		if int(boss.phase) == 2:
			max_phase = 2
		_move_player(player, boss, mode, t, strafe, field)
		if int(t * 10.0) % 27 == 0:
			strafe = -strafe
		if int(t * 10.0) % 3 == 0 and not player.is_attacking:
			player.attack_dir = (boss.global_position - player.global_position).normalized()
			player._start_attack()
		if int(t * 10.0) % 22 == 0:
			for sid in CharacterData.active_skill_loadout:
				if player.try_use_skill(String(sid)):
					break
		var cur := String(boss._current_skill)
		if cur != "" and cur != last_skill:
			att[cur] = int(att.get(cur, 0)) + 1
			## cover 由 BOSS 自己在起手那一帧判（_begin 里的几何闸），探针只读结果 ——
			## 自己复算必然晚一个 tick，会把「起手时收得到、落帧前人走开」误判成空放
			var snap: Dictionary = boss._begin_snapshot
			pending.append({"form": cur, "hp0": player.hp, "t0": t,
				"cover": bool(snap.get("cover", false)),
				"fd": float(snap.get("fd", 0.0)),
				"d": float(snap.get("d", 0.0))})
		last_skill = cur
		for i in range(pending.size() - 1, -1, -1):
			var e: Dictionary = pending[i]
			var form := String(e["form"])
			var w: float = float(MoveDB.resolve_boss(form).get("windup", 0.7))
			if t < float(e["t0"]) + w + 0.22:
				continue
			pending.remove_at(i)
			if player.hp < float(e["hp0"]) - 0.5:
				continue
			whiff[form] = int(whiff.get(form, 0)) + 1
			if not bool(e["cover"]):
				gate[form] = int(gate.get(form, 0)) + 1
		hp_min = minf(hp_min, player.hp)
		player.hp = maxf(player.hp, player.max_hp * 0.62)
	return {"att": att, "whiff": whiff, "gate": gate,
		"landings": int(boss._direct_landings) + int(boss._fold_landings),
		"fold_landings": int(boss._fold_landings),
		"fold_windows": int(boss._fold_windows),
		"gate_violation": int(gate.values().reduce(func(x, y2): return x + y2, 0)),
		"start_dist": start_dist, "player_hp_lost": player.max_hp - hp_min,
		"boss_hp_end": boss.current_hp, "max_phase": max_phase}


func _move_player(player: Node2D, boss: Node2D, mode: int, t: float, strafe: float,
		field) -> void:
	var to_b: Vector2 = boss.global_position - player.global_position
	var d := maxf(to_b.length(), 1.0)
	var radial := to_b.normalized()
	var tang := to_b.orthogonal().normalized() * strafe
	match mode:
		0:
			var cyc := fmod(t, 4.0)
			if cyc < 1.4:
				player.global_position += radial * minf(220.0 * TICK, maxf(d - 96.0, 0.0))
			elif cyc > 2.6:
				player.global_position -= radial * 200.0 * TICK
		1:
			## 「痕内绕圈」不是随便绕：要站到**离痕 <= 200 且与 BOSS 分处两侧**的位置上，
			## 镜像那一面才成立。随机绕圈时痕落在哪儿全凭运气，机制参与度会漂。
			var keep := 320.0
			var want := radial * (0.9 if d < keep - 40.0 else (-0.9 if d > keep + 40.0 else 0.0))
			var sp: Dictionary = field.nearest(player.global_position)
			if not sp.is_empty():
				var na := sp.get("a", Vector2.ZERO) as Vector2
				var nb := sp.get("b", Vector2.ZERO) as Vector2
				var cd3 := FoldLaw.crease_dir(na, nb)
				var nrm := Vector2(-cd3.y, cd3.x)
				var boss_side := FoldLaw.side(na, nb, boss.global_position)
				var my_side := FoldLaw.side(na, nb, player.global_position)
				if boss_side != 0.0 and my_side == boss_side:
					want -= nrm * boss_side * 220.0
				elif float(field.fold_dist(player.global_position)) > 200.0:
					want += nrm * (-my_side if my_side != 0.0 else 1.0) * 200.0
			player.global_position += (tang * 0.5 + want).normalized() * 250.0 * TICK
		2:
			# 离痕远站：沿痕的法向往外走，直到 fold_dist > 贴合带 + 60
			var want_r := FoldLaw.reach_for(int(boss.phase)) + 90.0
			var sp: Dictionary = field.nearest(player.global_position)
			var n := Vector2.UP
			if not sp.is_empty():
				n = Vector2(-(sp.get("b", Vector2.ZERO) as Vector2).y
						+ (sp.get("a", Vector2.ZERO) as Vector2).y,
						(sp.get("b", Vector2.ZERO) as Vector2).x
						- (sp.get("a", Vector2.ZERO) as Vector2).x).normalized()
			var cur_fd := float(field.fold_dist(player.global_position))
			var sign_n := 1.0 if n.dot(player.global_position - _span_mid(sp)) >= 0.0 else -1.0
			var step := n * sign_n * (240.0 * TICK if cur_fd < want_r else 0.0)
			player.global_position += step + tang * 60.0 * TICK
	var lim: Vector2 = boss.arena_half_extents
	if lim != Vector2.ZERO:
		player.global_position = Vector2(
			clampf(player.global_position.x, -lim.x + 70.0, lim.x - 70.0),
			clampf(player.global_position.y, -lim.y + 70.0, lim.y - 70.0))


func _span_mid(sp: Dictionary) -> Vector2:
	if sp.is_empty():
		return Vector2.ZERO
	return ((sp.get("a", Vector2.ZERO) as Vector2)
			+ (sp.get("b", Vector2.ZERO) as Vector2)) * 0.5


## 恢复玩家状态：hp 钳位不清 is_dead，不扶起来后面每门功法都会 try_use_skill=false 级联假失败
func _revive(player: Node2D) -> void:
	player.is_dead = false
	player.hp = player.max_hp
	player.mana = player.max_mana
	player.stamina = player.max_stamina
	player.invincible_timer = 0.0
	player.velocity = Vector2.ZERO
	player.skill_cooldowns.clear()
	player.debuffs.clear()
	player.buffs.clear()


func _report(tag: String, s: Dictionary) -> void:
	var parts := ""
	for f in ALL_FORMS:
		var n := int((s["att"] as Dictionary).get(f, 0))
		if n > 0:
			parts += "%s %d(落空%d/违规%d) " % [String(f).replace("form_fold_", ""),
				n, int((s["whiff"] as Dictionary).get(f, 0)),
				int((s["gate"] as Dictionary).get(f, 0))]
	print("  %s：%s" % [tag, parts])
	print("      开局距离 %.0f · 玩家掉血 %.0f · 挨打 %d 次(镜像 %d) · BOSS 结束血 %.0f · 阶段 %d" % [
		float(s["start_dist"]), float(s["player_hp_lost"]), int(s["landings"]),
		int(s["fold_landings"]), float(s["boss_hp_end"]), int(s["max_phase"])])


## 与 probe_zhizhu 同一套夹具：元婴初期 · 道器 +6（假玩家要能真的把战斗推进到二阶段）
func _wear_baseline(stage: int, enh: int) -> void:
	var enh_avg := {
		"strength": 1.5, "spell_power": 1.0, "hp_max": 3.0,
		"physical_resist": 1.0, "magic_resist": 1.0, "mana_max": 3.0,
		"mana_regen": 0.75, "speed_pct": 0.3, "attack_speed": 1.0,
		"spell_skill_damage_pct": 0.75, "stamina_regen_pct": 0.75,
	}
	for slot in CharacterData.SLOT_ORDER:
		CharacterData.equipment_slots[slot] = null
	var gear := ["eq_qingfengjian", "eq_jinwen_zhanpao", "eq_zhuri_lv",
		"eq_liangyi_yujue", "eq_qihai_yuzhui", "eq_leiwen_huqi"]
	var slots := ["weapon", "armor", "shoes", "accessory_1", "accessory_2", "accessory_3"]
	for i in gear.size():
		var tpl := ItemDB.get_equipment_template(String(gear[i]))
		var it := CharacterData.make_equipment_instance(tpl)
		var asc := maxi(0, ItemDB.grade_index("道器") - ItemDB.grade_index(String(it.get("equipment_grade", ""))))
		var attrs: Dictionary = {}
		var base = it.get("attributes_base", {})
		for k in base.keys():
			attrs[String(k)] = float(base[k])
		for j in asc:
			for k in attrs.keys():
				attrs[k] = float(attrs[k]) * 1.5
		for k in attrs.keys():
			if enh_avg.has(k):
				attrs[k] = float(attrs[k]) + float(enh_avg[k]) * float(enh)
		it["attributes"] = attrs
		it["equipment_grade"] = "道器"
		it["enhancement_level"] = enh
		CharacterData.equipment_slots[String(slots[i])] = it


## 两件装备改的是「怎么打」而不是词条数字，所以测的是**落点与窗口**，不是属性面板
func _equipment_effects(player: Node2D, boss: Node2D) -> void:
	_revive(player)
	boss.current_hp = boss.max_hp
	# ===== 纸错剑：终结段在目标身后 120 再落一段 =====
	var sword := _wear_one(player, "eq_zhicuo_jian")
	_check(sword, "纸错剑可佩戴（is_wearing 认模板 id）")
	_check(CharacterData.is_wearing("eq_zhicuo_jian"), "is_wearing 读到纸错剑")
	# 把 BOSS 摆到「普攻扇形够不到、但身后 120 的落点够得到」的位置：
	# 正面 reach 100 + 余量 18 打不到它，第二落点圆心在它身后 120、半径 90 也打不到它 ——
	# 所以这里验的是「第二落点确实存在并且会结算」，用直接调用隔离出伤害那一半。
	var dir := Vector2.RIGHT
	var hp0: float = boss.current_hp
	boss.global_position = player.global_position + Vector2(60.0, 0.0)
	player._zhicuo_second_landing(dir, 100.0, 40.0)
	await get_tree().process_frame
	var landed: float = hp0 - boss.current_hp
	_check(landed > 0.0, "纸错剑第二落点确实结算（目标身后 120 那一记）",
		"伤害 %.1f" % landed)
	# 同一个目标不该被两段同时吃到：第二落点圆心在身后 120、半径 90+18 < 120
	boss.current_hp = boss.max_hp
	hp0 = boss.current_hp
	player._zhicuo_second_landing(dir, 400.0, 40.0)
	await get_tree().process_frame
	var once: float = hp0 - boss.current_hp
	_check(once < 40.0 * 1.9, "第二落点不会把同一目标重复翻倍",
		"单次 %.1f（上限按 60%% 一档算）" % once)

	# ===== 折痕佩：受击后 0.3 秒内位移技立即就绪、终点再折 90 =====
	var pei := _wear_one(player, "eq_zhehen_pei")
	_check(pei and CharacterData.is_wearing("eq_zhehen_pei"), "折痕佩可佩戴并被读到")
	player._zhehen_window = 0.0
	boss.current_hp = boss.max_hp
	player.take_damage(30.0, "physical_melee", boss, "water")
	_check(player._zhehen_window > 0.0, "受击后折位窗口打开",
		"%.2f 秒" % player._zhehen_window)
	player.skill_cooldowns["skill_fold_trace"] = 9.0
	var extended: float = player._zhehen_fold_escape("skill_fold_trace", 300.0)
	_check(extended > 300.0, "窗口内的位移终点被折出去", "+%.0f px" % (extended - 300.0))
	_check(float(player.skill_cooldowns.get("skill_fold_trace", 0.0)) == 0.0,
		"该位移技 CD 立即转好")
	_check(player._zhehen_window == 0.0, "窗口是一次性的（用完就关）")
	var again: float = player._zhehen_fold_escape("skill_fold_trace", 300.0)
	_check(again == 300.0, "窗口关掉之后不再给折位（不能白嫖）")
	# 没戴装备时整套必须完全沉默
	_wear_one(player, "")
	_check(not CharacterData.is_wearing("eq_zhehen_pei"), "卸下后 is_wearing 为假")
	_check(player._zhehen_fold_escape("skill_fold_trace", 300.0) == 300.0,
		"没戴折痕佩时位移不受影响")


## 只往武器槽塞一件模板，测完还原（不动其它槽，避免污染后面的 TTK 档）
func _wear_one(player: Node2D, equipment_id: String) -> bool:
	var slots := ["weapon", "armor", "shoes", "accessory_1", "accessory_2", "accessory_3"]
	for slot in slots:
		CharacterData.equipment_slots[slot] = null
	if equipment_id == "":
		player._apply_attributes_to_runtime(true)
		return true
	var tpl: Dictionary = ItemDB.get_equipment_template(equipment_id)
	if tpl.is_empty():
		return false
	var it := CharacterData.make_equipment_instance(tpl)
	var slot := "weapon" if String(tpl.get("equipment_type", "")) == "weapon" else "accessory_1"
	CharacterData.equipment_slots[slot] = it
	player._apply_attributes_to_runtime(true)
	return true
