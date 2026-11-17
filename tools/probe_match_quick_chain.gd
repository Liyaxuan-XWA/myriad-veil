extends Node
## 快速模式 · 整条场景链（票 009 ①）
##
## ⚠ 链本身交给挂在 root 上的 match_chain_checker.run_quick_chain() 跑：
##   `change_scene_to_file()` 会 free 掉旧的 current_scene，而本探针就是 current_scene，
##   在这里切场景等于把自己删了。也**不能 await** 那条协程（见 flow 探针同一套路）。
##
## 用法：godot --headless --path . res://tools/probe_match_quick_chain.tscn -- --no-save

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
	print("\n########## 快速模式 · 整条场景链 ##########")
	# 先把"快速模式确实改了日程"这件事在本进程里钉住，再把场景链交出去
	var st := MatchState.new()
	var deck: Array = MatchLevelDeck.deck_for(1)
	var pool: Array = []
	for id in MatchDB.CARD_POOL:
		if pool.size() < MatchDB.DECK_SIZE:
			pool.append(String(id))
	st.start([pool, deck], 7, 0)
	_check(int(st.deployed_count()) == 0, "① 前置：没调 quick_open 时场上没人",
			str(st.deployed_count()))
	st.quick_open(1, deck, MatchQuickSetup.layout_for(1))
	_check(int(st.deployed_count()) == MatchDB.DECK_SIZE,
			"① quick_open 后对方 6 子已摆好", str(st.deployed_count()))
	st.apply_command({"t": "pick", "team": 0, "ids": pool})
	_check(st.phase == MatchState.Phase.DEPLOY,
			"① 交完牌跳过 LOCK", String(MatchState.PHASE_NAME[st.phase]))

	var keeper := Node.new()
	keeper.name = "ChainChecker"
	keeper.set_script(load("res://tools/match_chain_checker.gd"))
	# ⚠ 必须 call_deferred + 等一帧：_ready 里同步 add_child 会撞
	#   "Parent node is busy setting up children"，keeper 静悄悄没进树，
	#   随后它里面的 get_tree() 就是 null（本项目已知坑，票 002 也记过一次）。
	get_tree().root.add_child.call_deferred(keeper)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(keeper.is_inside_tree(), "② 链检查器真的挂上了 root", "")
	keeper.inherit(_passes, _fails)
	# ⚠ 不要 await：run_quick_chain() 里会 change_scene_to_file，本探针就是那个 current_scene
	keeper.run_quick_chain()
