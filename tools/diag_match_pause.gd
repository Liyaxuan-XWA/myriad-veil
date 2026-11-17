extends Node
## 诊断：选牌窗口里棋子到底还动不动。
## 只在场上已经有棋子时打点，报「这 0.5 秒里它移动了多少像素」+ 血量 + AI 状态。
## 用法：godot --headless --path . res://tools/diag_match_pause.tscn -- --no-save

const STEP := 0.5

var _acc := 0.0
var _prev: Dictionary = {}


func _units(pieces: Node) -> Array:
	var out: Array = []
	for host in pieces.get_children():
		if not is_instance_valid(host):
			continue
		for raw in host.get_children():
			if is_instance_valid(raw) and raw is BossBase:
				out.append(raw)
	return out


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
		_acc += get_process_delta_time()
		if _acc < STEP:
			continue
		_acc = 0.0
		var ph := String(MatchState.PHASE_NAME.get(int(st.phase), "?"))
		var units := _units(pieces)
		if ph != "battle" or units.is_empty():
			continue
		var parts: Array = []
		for raw in units:
			var n: Node = raw as Node
			var id: int = n.get_instance_id()
			var pos: Vector2 = (n as Node2D).global_position
			var moved := 0.0
			if _prev.has(id):
				moved = pos.distance_to(_prev[id] as Vector2)
			_prev[id] = pos
			parts.append("%s 动%.0fpx hp=%.0f state=%s" % [String(n.get("boss_id")),
					moved, float(n.get("current_hp")), str(n.get("state"))])
		print("DIAG 轮%d fighting=%-5s 窗口=%4.1f ts=%.3f 基准=%.3f | %s" % [
				int(st.round_index), str(st.fighting()), float(st.timer),
				Engine.time_scale, GameState.time_flow_base, " / ".join(parts)])
		if int(st.phase) == MatchState.Phase.OVER:
			break
	print("DIAG 结束")
	get_tree().quit(0)
