extends Node
## 诊断：对局场景里**棋盘上实际出现了什么**（不碰 events，免得抢走场景自己的消费）。
## Pieces 的直接子节点是每只棋子的 host，棋子在 host 里面一层，所以要下钻一层再数。
## 用法：godot --headless --path . res://tools/diag_match_spawn.tscn -- --no-save

var _seen: Dictionary = {}
var _last_phase := -1
var _last_round := -1


## 场上真正的棋子（带血条的那种）
func _all_units(pieces: Node) -> Array:
	var out: Array = []
	for host in pieces.get_children():
		if not is_instance_valid(host):
			continue
		for raw in host.get_children():
			if is_instance_valid(raw) and raw is BossBase:
				out.append(raw)
	return out


func _tally(pieces: Node) -> String:
	var a := 0
	var b := 0
	var other := 0
	for raw in _all_units(pieces):
		var t := BossBase.unit_team(raw)
		if t == 0:
			a += 1
		elif t == 1:
			b += 1
		else:
			other += 1
	return "0队=%d 1队=%d 无队伍=%d" % [a, b, other]


func _ready() -> void:
	var arena := (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	arena.set("player_stage_timeout", 1.2)
	add_child(arena)
	var pieces: Node = arena.get_node("Pieces")
	var st = null
	for guard in 20000:
		await get_tree().physics_frame
		st = arena.get("_state")
		if st == null:
			continue
		if int(st.phase) != _last_phase:
			_last_phase = int(st.phase)
			print("### 阶段 → ", String(MatchState.PHASE_NAME.get(_last_phase, "?")))
		if int(st.phase) == MatchState.Phase.BATTLE and st.round_index != _last_round:
			_last_round = st.round_index
			print("--- 第 %d 轮（%s）  场上 %s" % [st.round_index,
					"己方" if st.is_own_round() else "对方", _tally(pieces)])
		for raw in _all_units(pieces):
			if _seen.has(raw.get_instance_id()):
				continue
			_seen[raw.get_instance_id()] = true
			var bar: ColorRect = raw.get_node_or_null("HPBarBG/HPBar")
			print("  +", MatchState.PHASE_NAME.get(int(st.phase), "?"),
					" team=", BossBase.unit_team(raw),
					" boss=", raw.get("boss_id"),
					" 血条=", bar.color if bar != null else "无",
					" hp=", raw.get("current_hp"))
		if int(st.phase) == MatchState.Phase.OVER:
			break
	print("DIAG 结束 winner=", st.winner, " reason=", st.end_reason, " ", _tally(pieces))
	var nonteam: Array = []
	for raw in _all_units(pieces):
		if BossBase.unit_team(raw) < 0:
			nonteam.append("%s(%s)" % [String(raw.name), raw.get_class()])
	print("DIAG host数=", pieces.get_child_count(),
			" match_piece组=", get_tree().get_nodes_in_group("match_piece").size(),
			" 其中没有队伍号的=", nonteam)
	get_tree().quit(0)
