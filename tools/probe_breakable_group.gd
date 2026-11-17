extends Node
## breakable_sword 是异构组 —— 天剑 / 阵旗 / 碣板都在里面
##
## 起因：用户在棋局里实机崩了，`Invalid access to property or key 'source'
## on a base object of type 'Node2D (ArrayFlag)'`，调试器一帧刷 116 条。
## 剑客 `_remaining_sky_swords()` / `_settle_sky_swords()` 直接读 `sw.source`，
## 而组里只有 SkySword 有这个字段。单打剑客时组里只有天剑所以从不露馅，
## **棋局是本项目第一个「两只 BOSS 同场」的场景**，定阵先生一插旗就炸。
##
## 这条探针不测"剑客能不能打"，测的是**组语义**：
## ① 异构成员同场时计数只算自己的天剑；
## ② 结算消散不许碰别人的旗和碣板（真碰上了等于剑客替定阵先生拆阵）。
##
## 用法：godot --headless --path . res://tools/probe_breakable_group.tscn -- --no-save

const SWORD_SCENE := "res://scenes/boss/sky_sword.tscn"
const SWORD_BOSS := "res://scenes/boss/domain_boss_01_c.tscn"

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
	print("\n########## breakable_sword 异构组共存 ##########")
	var boss: Node = (load(SWORD_BOSS) as PackedScene).instantiate()
	add_child(boss)
	boss.set_physics_process(false)
	await get_tree().process_frame

	# 三种组内成员各来一个：自己的天剑 / 别人的天剑 / 阵旗 / 碣板
	var mine := _mk_sword(boss)
	var other := _mk_sword(null)
	var flag := ArrayFlag.new()
	add_child(flag)
	var plate := StagPlate.new()
	add_child(plate)
	# ⚠ StagPlate 的入组写在 setup() 里而不是 _ready（`z_index` 与影多边形也在那儿建），
	#   不调这一步夹具就少一件，② ③ 会因为"根本没异构"而假绿。
	plate.call("setup")
	await get_tree().process_frame

	var in_group := _group_count()
	_check(in_group >= 4, "① 前置：组里确实同时有天剑×2 + 阵旗 + 碣板", "%d 个" % in_group)
	# ⚠ 反向守卫：如果哪天 ArrayFlag/StagPlate 不再进这个组，上面那条判据就空了，
	#   本探针会一直绿着保护不了任何东西 —— 所以这里点名验异构性本身。
	_check(flag.is_in_group("breakable_sword") and plate.is_in_group("breakable_sword"),
			"① 前置：阵旗与碣板仍在同一个组里（异构性没被改掉）", "")

	# ② 计数：只许算自己那把
	var n: int = boss.call("_remaining_sky_swords")
	_check(n == 1, "② 计数只算自己的天剑（别人的剑/旗/碣板都不算）", "%d 应为 1" % n)

	# ③ 消散：不许越界拆别人的东西
	boss.call("_settle_sky_swords")
	await get_tree().process_frame
	_check(is_instance_valid(flag) and flag.is_inside_tree(),
			"③ 结算不许拆定阵先生的旗", str(is_instance_valid(flag)))
	_check(is_instance_valid(plate) and plate.is_inside_tree(),
			"③ 结算不许拆石犼的碣板", str(is_instance_valid(plate)))
	_check(is_instance_valid(other), "③ 结算不许拆别人的天剑", str(is_instance_valid(other)))
	_check(not is_instance_valid(mine), "③ 自己的天剑确实消散了", str(is_instance_valid(mine)))
	_check(_group_count() == 3, "③ 组里剩下的正好是别人那三件", "%d" % _group_count())

	_finish()


func _mk_sword(src: Node) -> Node:
	var sw: Node = (load(SWORD_SCENE) as PackedScene).instantiate()
	# mode 必须在入树前设成 PLANTED —— `_ready` 里只有 PLANTED 才 add_to_group
	sw.set("mode", SkySword.Mode.PLANTED)
	sw.set("source", src)
	add_child(sw)
	return sw


func _group_count() -> int:
	var n := 0
	for raw in get_tree().get_nodes_in_group("breakable_sword"):
		if is_instance_valid(raw):
			n += 1
	return n


func _finish() -> void:
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
