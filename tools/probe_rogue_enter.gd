extends Node
## 验「点踏入试炼 → 万界塔面板自己关掉，不会盖在战斗画面上」。
## 跑法：godot --headless --path . res://tools/probe_rogue_enter.tscn -- --no-save
##
## ⚠ 本探针走的是真实入口 `_on_enter_rogue()`，它会 `change_scene_to_file` 换到战斗场景，
##   探针节点会被一起销毁 —— 所以**触发之后的断言必须同步做完，一句 await 都不能有**。
##   （曾经的 bug：`_open_system_panel` 把面板 add 到 `get_tree().root`，
##     `change_scene_to_file` 只换「当前场景」，挂在 root 下的面板不随之销毁，
##     于是战斗画面被面板整块盖住，得玩家自己点关闭。）

var _pass := 0
var _fail := 0
var _failed: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var tree := get_tree()   # 切场景后本节点会脱树，SceneTree 引用要提前抓
	# 工具环境：置「已通关万界秘境·凡界虎妖」，否则试炼入口的前置门禁会挡住本工具。
	# 直接写 domain_progress（不调 mark_boss_killed，避免掺进首杀奖励等无关副作用）。
	CharacterData.domain_progress[RogueDB.TRIAL_UNLOCK_DOMAIN] = {
		"unlocked": true, "cleared_bosses": [RogueDB.TRIAL_UNLOCK_BOSS]}
	var panel := (load("res://scripts/ui/panels/tower_panel.gd") as GDScript).new() as SystemPanel
	if panel == null:
		print("✗ 塔面板脚本加载失败")
		get_tree().quit(1)
		return
	# 真实运行时面板挂在 root 下（primordial_realm._open_system_panel），探针保持一致。
	# ⚠ _ready 阶段 root 正在装配子节点，直接 add_child 会被拒（"Parent node is busy..."），
	#   必须走 call_deferred，再等两帧让面板自己的 _ready 跑完（它要靠 _ready 建外壳）。
	get_tree().root.add_child.call_deferred(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	_check(panel.get("_visible") == true, "面板已打开（对照项）", str(panel.get("_visible")))
	_check(tree.paused == true, "打开时暂停游戏（对照项）", str(tree.paused))

	var fired := [0]
	panel.closed.connect(func() -> void: fired[0] += 1)

	# ↓↓↓ 以下全部同步：这一行会把整个场景换掉 ↓↓↓
	panel.call("_on_enter_rogue")

	_check(fired[0] == 1, "点踏入试炼：面板发出 closed 一次", str(fired[0]))
	_check(panel.is_queued_for_deletion(), "点踏入试炼：面板排队自我销毁",
		str(panel.is_queued_for_deletion()))
	# ⚠ 用缓存下来的 tree：change_scene_to_file 会把本节点从树上摘下来，
	#   这之后再 get_tree() 就返回 null（不是 "previously freed"，节点还活着只是脱离了树）。
	_check(tree.paused == false, "点踏入试炼：已解除暂停（否则战斗进去不动）",
		"paused=%s" % str(tree.paused))
	_check(RogueRun.active, "点踏入试炼：肉鸽局已开", "active=%s" % str(RogueRun.active))

	print("########## 结果 %d 通过 / %d 失败 ##########" % [_pass, _fail])
	tree.quit(_fail)


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  ✓ ", label, "  ", detail)
	else:
		_fail += 1
		var line := "%s  %s" % [label, detail]
		_failed.append(line)
		print("  ✗ ", line)
