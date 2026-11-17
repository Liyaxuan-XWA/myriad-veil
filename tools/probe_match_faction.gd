extends Node
## 对战队伍阵营回归（2026-11-02 卡片自走棋地基第②项）
##
## 改之前阵营是**二值**的：`is_ally` 决定进 "boss" 还是 "ally_summon" 组，
## `enemy_units()` 的敌方分支写死查 "player" 组。放进 6×6 棋盘会同时出两个问题：
##   ① 棋盘上没有玩家 → 敌方分支返回空表 → `_choose()` 每帧 return，整只 BOSS 站着不动；
##   ② 双方棋子若都进 "boss" 组会被互认友军，或都进 "ally_summon" 又互相打不到。
## 所以新增 `team_id`（-1 = 沿用旧二值阵营，0/1 = 对局队伍）。
##
## 本探针必须同时证明：新路径没有玩家也能打，旧路径行为一字未变。
## 用法：godot --headless --path . tools/probe_match_faction.tscn -- --no-save

const BOSS_SCENE := "res://scenes/boss/domain_boss_01.tscn"

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


## 生成一只棋子。team_id / is_ally / max_hp 必须在 add_child **之前**设：
## _ready() 据此决定入哪个组、以及 current_hp = max_hp。
func _piece(team: int, pos: Vector2, label: String) -> Node2D:
	var n := (load(BOSS_SCENE) as PackedScene).instantiate() as Node2D
	n.name = label
	n.set("team_id", team)
	n.set("is_ally", false)
	n.set("max_hp", 5000.0)
	n.position = pos
	add_child(n)
	return n


func _ready() -> void:
	print("\n########## 对战队伍阵营 ##########")
	await get_tree().process_frame

	# ---- 0. 前置：场上确实没有任何玩家节点 ----
	_check(get_tree().get_nodes_in_group("player").is_empty(),
			"场上没有 player 节点（旧路径必返回空表）",
			"player组=%d" % get_tree().get_nodes_in_group("player").size())

	var a0 := _piece(0, Vector2(-260, 0), "A0")
	var a1 := _piece(0, Vector2(-520, 0), "A1")
	var b0 := _piece(1, Vector2(260, 0), "B0")
	await get_tree().process_frame
	await get_tree().process_frame

	# ---- 1. 敌我按队伍号判 ----
	var ea: Array = a0.call("enemy_units")
	_check(ea.has(b0) and not ea.has(a1) and not ea.has(a0),
			"0 号棋子的敌人只有 1 号队（不含队友、不含自己）",
			"enemy=%s" % _names(ea))
	var eb: Array = b0.call("enemy_units")
	_check(eb.has(a0) and eb.has(a1),
			"1 号棋子看到 0 号队两个都是敌人", "enemy=%s" % _names(eb))

	# ---- 2. 没有玩家也能索敌 —— 这条就是照影界三只停摆的根因 ----
	var opp: Node2D = a0.call("opponent_node")
	_check(opp == b0, "无玩家场景下 opponent_node() 仍指向对方棋子",
			"opp=%s" % (opp.name if opp != null else "null"))
	_check(a0.call("focus_node") != null, "focus_node() 兜底给的是对方棋子而不是 null")

	# ---- 3. 同队打不动，对方打得动 ----
	_check(not a0.call("deal_damage_to", a1, 500.0, "physical"),
			"同队伤害被拒（不会误伤队友）")
	_check(float(a1.get("current_hp")) == 5000.0, "队友血量没被动过",
			"hp=%.0f" % float(a1.get("current_hp")))
	_check(a0.call("deal_damage_to", b0, 500.0, "physical"), "对方伤害放行")
	_check(float(b0.get("current_hp")) < 5000.0, "对方确实掉血了",
			"hp=%.0f" % float(b0.get("current_hp")))

	# ---- 4. match_piece 组只收棋子 ----
	var pieces: Array = get_tree().get_nodes_in_group("match_piece")
	_check(pieces.size() == 3, "三只棋子都在 match_piece 组", "n=%d" % pieces.size())

	# ---- 5. 没有 team_id 字段的节点不得被当成 0 队 ----
	#   int(null) == 0，所以漏判会让玩家/木桩/场景物凭空变成 0 队成员。
	var bare := Node2D.new()
	bare.name = "BareNode"
	add_child(bare)
	_check(BossBase.unit_team(bare) == -1, "无 team_id 字段的节点队伍号为 -1",
			"got=%d" % BossBase.unit_team(bare))
	_check(not a0.call("deal_damage_to", bare, 500.0, "physical"),
			"棋子打不动没入队的节点")

	# ---- 6. 旧二值路径回归：team_id = -1 时行为与改动前一致 ----
	var legacy := _piece(-1, Vector2(0, 400), "Legacy")
	await get_tree().process_frame
	var le: Array = legacy.call("enemy_units")
	# 没有玩家时旧路径本来就返回空表 —— 这正是改动前后的共同行为，不能被 team 分支接管
	_check(le.is_empty(), "team_id=-1 仍走旧二值路径（无玩家→空表，与改动前一致）",
			"enemy=%s" % _names(le))
	_check(legacy.call("opponent_node") == null, "team_id=-1 时 opponent_node 不接管棋子逻辑")
	_check(legacy.call("focus_node") == null, "team_id=-1 时 focus_node 退回玩家组读数")
	# 旧路径下两个非队伍单位之间伤害照旧放行（法宝召唤打 BOSS 就靠这条）
	_check(legacy.call("deal_damage_to", a0, 100.0, "physical"),
			"旧路径伤害结算未被新守卫挡住")

	# ---- 7. 尸体不再被当目标（2026-11-03 用户报「boss 死后还会被当做目标攻击」）----
	# 根因：_die() 之后节点还要在树上挂完 0.5s 淡出动画，期间 current_hp 恰好是 **0**
	# 而不是负数，所以旧那句「血量 < 0 才算消失」永远不会触发，target 就钉在尸体上。
	var b1 := _piece(1, Vector2(520, 0), "B1")
	await get_tree().physics_frame
	_check(a0.call("enemy_units").has(b0), "打死之前 B0 确实在敌人列表里")
	b0.set("current_hp", 1.0)
	a0.call("deal_damage_to", b0, 9999.0, "physical")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(BossBase.is_unit_dead(b0), "B0 已进入死亡态")
	_check(is_instance_valid(b0) and b0.is_inside_tree(),
			"尸体确实还挂在树上（这才暴露了旧判据的漏洞）")
	var ea2: Array = a0.call("enemy_units")
	_check(not ea2.has(b0) and ea2.has(b1),
			"尸体从 enemy_units() 消失、活的那只顶上来", "enemy=%s" % _names(ea2))
	_check(float(a0.call("threat_of_unit", b0)) < 0.0,
			"尸体的仇恨值为 -1（不再算可选目标）")
	var opp2: Node2D = a0.call("opponent_node")
	_check(opp2 != b0, "opponent_node() 不再指回尸体",
			"opp=%s" % (String(opp2.name) if opp2 != null else "null"))
	await get_tree().physics_frame
	var tgt = a0.get("target")
	_check(tgt != b0, "仇恨表把 target 从尸体上换走",
			"target=%s" % (String((tgt as Node).name) if tgt != null and is_instance_valid(tgt) else "null"))
	var hp_corpse := float(b0.get("current_hp"))
	_check(not a0.call("deal_damage_to", b0, 500.0, "physical"), "尸体拒绝再次受伤")
	_check(float(b0.get("current_hp")) == hp_corpse, "尸体血量没有被继续扣",
			"hp=%.1f" % float(b0.get("current_hp")))

	# ---- 8. 旧二值路径同样要丢尸体（友军召唤物死掉后不该继续挨打）----
	# is_ally 必须在 add_child 之前设：_ready() 据此决定入 "boss" 还是 "ally_summon" 组
	var ally := (load(BOSS_SCENE) as PackedScene).instantiate() as Node2D
	ally.name = "AllySummon"
	ally.set("team_id", -1)
	ally.set("is_ally", true)
	ally.set("max_hp", 5000.0)
	ally.position = Vector2(0, 600)
	add_child(ally)
	var legacy2 := _piece(-1, Vector2(0, 760), "Legacy2")
	await get_tree().physics_frame
	_check(legacy2.call("enemy_units").has(ally),
			"旧路径：活着的 ally_summon 友军仍在可打列表",
			"enemy=%s" % _names(legacy2.call("enemy_units")))
	ally.set("state", 6)  # BossState.DEAD：直接置态，不走 _die()（友军会走消散分支把自己 free 掉）
	await get_tree().physics_frame
	_check(not legacy2.call("enemy_units").has(ally),
			"旧路径：死亡的 ally_summon 友军被踢出可打列表")

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for s in _fails:
		print("  ! ", s)
	get_tree().quit(1 if not _fails.is_empty() else 0)


func _names(arr: Array) -> String:
	var out: Array = []
	for u in arr:
		out.append(String((u as Node).name))
	return ",".join(out)
