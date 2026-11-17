extends Node2D
## 棋子远程命中 + 队伍配色回归（2026-11-03 用户报「远程打不中人」）
##
## 两层同时堵死：
##   ① 物理层：`_spawn_projectile` 给敌方写的 mask = 玩家(1)|友军(16)|阵旗(256)，
##      不含棋子所在的 BOSS 层 2 → 弹体从对手身上穿过去。
##   ② 阵营判定：`source_is_ally == target.is_ally` 对两只 is_ally=false 的棋子
##      恒为真 → 即使碰到了也不结算。
## 两处都改成按 `team_id` 判，并且 mask 在 source 的 setter 里补
## （`source` 是各调用方在 add_child 之后才赋的，_ready 里修来不及）。
##
## 用法：godot --headless --path . res://tools/probe_match_ranged.tscn -- --no-save

const PROJ := "res://scenes/boss/boss_projectile.tscn"

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _piece(team: int, cell: Vector2i) -> Node2D:
	return MatchAdapter.spawn_piece(self, "boss_03", team, cell)


func _ready() -> void:
	print("\n########## 棋子远程命中与队伍配色 ##########")
	await get_tree().process_frame

	var a := _piece(0, Vector2i(1, 1))
	var b := _piece(1, Vector2i(4, 1))
	var c := _piece(0, Vector2i(1, 4))
	await get_tree().process_frame

	# ---- 1. mask 必须补上棋子所在的 BOSS 层 ----
	var proj := (load(PROJ) as PackedScene).instantiate() as Area2D
	add_child(proj)
	proj.set("damage", 500.0)
	var before_mask := proj.collision_mask
	proj.set("source", a)
	_check(int(proj.get("source_team")) == 0, "发射时抄到发射者的队伍号",
			"team=%s" % proj.get("source_team"))
	_check(proj.collision_mask & BossBase.BOSS_LAYER != 0,
			"棋子弹体的 mask 含 BOSS 层（原来会穿过对手）",
			"mask %d → %d" % [before_mask, proj.collision_mask])

	# ---- 2. 打到对方要真扣血 ----
	var hp_b := float(b.get("current_hp"))
	proj.call("_on_body_entered", b)
	_check(float(b.get("current_hp")) < hp_b, "敌方棋子被弹体结算了伤害",
			"%.0f → %.0f" % [hp_b, float(b.get("current_hp"))])

	# ---- 3. 同队不能误伤 ----
	var proj2 := (load(PROJ) as PackedScene).instantiate() as Area2D
	add_child(proj2)
	proj2.set("damage", 500.0)
	proj2.set("source", a)
	var hp_c := float(c.get("current_hp"))
	proj2.call("_on_body_entered", c)
	_check(float(c.get("current_hp")) == hp_c, "同队弹体不结算伤害（补了层也不会误伤）")

	# ---- 4. 旧玩法回归：没有队伍号的发射者不得被改动 ----
	var legacy := _piece(-1, Vector2i(3, 4))
	await get_tree().process_frame
	var proj3 := (load(PROJ) as PackedScene).instantiate() as Area2D
	add_child(proj3)
	var m3 := proj3.collision_mask
	proj3.set("source", legacy)
	_check(int(proj3.get("source_team")) == -1, "无队伍发射者 source_team 保持 -1")
	_check(proj3.collision_mask == m3, "无队伍时不擅自改 mask（现有玩法行为不变）")

	# ---- 5. 血条按队伍染色，非棋子不变 ----
	var bar_a: ColorRect = a.get_node("HPBarBG/HPBar")
	var bar_b: ColorRect = b.get_node("HPBarBG/HPBar")
	_check(bar_a.color == BossBase.TEAM_HP_GREEN, "己方(0队)血条绿", str(bar_a.color))
	_check(bar_b.color == BossBase.TEAM_HP_RED, "敌方(1队)血条红", str(bar_b.color))
	var bar_l: ColorRect = legacy.get_node("HPBarBG/HPBar")
	_check(bar_l.color != BossBase.TEAM_HP_GREEN and bar_l.color != BossBase.TEAM_HP_RED,
			"非棋子血条保持场景原色（PvE 不受影响）", str(bar_l.color))

	# ---- 6. sky_sword 也要能砍到棋子 ----
	var sw := (load("res://scenes/boss/sky_sword.tscn") as PackedScene).instantiate() \
			if ResourceLoader.exists("res://scenes/boss/sky_sword.tscn") else null
	if sw != null:
		add_child(sw)
		sw.set("source", a)
		sw.set("damage", 400.0)
		sw.global_position = (b as Node2D).global_position
		var hp_b2 := float(b.get("current_hp"))
		var hit: bool = sw.call("_hit_player")
		_check(hit and float(b.get("current_hp")) < hp_b2,
				"巨剑在棋盘上能砍到对方棋子（原来只查 player 组，永远空放）",
				"hit=%s" % hit)
		sw.queue_free()
	else:
		print("     （sky_sword 场景路径没找到，跳过该条）")

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for s in _fails:
		print("  ! ", s)
	get_tree().quit(1 if not _fails.is_empty() else 0)
