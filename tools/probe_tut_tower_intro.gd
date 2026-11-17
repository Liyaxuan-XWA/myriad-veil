extends Node
## 首杀 BOSS 回原初位面 → 万界塔指引 · 端到端自检（2026-11-10）
##
## 用户要求：第一次击败 BOSS 后返回原初位面，要触发万界塔的新手指引。
## 这里走**真实入口**：实例化 primordial_realm.tscn，让主城 _ready 自己判断，
## 不是手工调 request_chapter —— 那样探针全绿、玩家照样看不到指引。
##
##   ① 首杀回城、第 1 章还停在「回城开背包」→ 只排队，不打断当前清单
##   ② 开背包那步做完 → 自动接上万界塔，聚光真的框在 Facilities/Tower 上
##   ③ 第 1 章早做完时回城 → 回城立刻开，不等任何事件
##   ④ 万界塔整章做完后回城 → 不再弹
##
## 用法：godot --headless --path . tools/probe_tut_tower_intro.tscn -- --no-save

const REALM := "res://scenes/main/primordial_realm.tscn"

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
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 首杀回城 → 万界塔指引 ##########")
	get_tree().create_timer(90.0, true, false, true).timeout.connect(func() -> void:
		print("PROBE TIMEOUT")
		get_tree().quit(2))
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _run() -> void:
	var saved_done: Dictionary = CharacterData.tutorial_data.duplicate(true)
	var saved_boss: Dictionary = CharacterData.boss_progress.duplicate(true)
	var c1_steps: Array = TutorialDB.get_chapter("c1").get("steps", [])

	# ===== ① 首杀回城，第 1 章正停在「回城开背包」 =====
	CharacterData.tutorial_data = {"done": {}}
	# 2026-11-10：链路 need 钉死虎妖本体 —— 必须用 boss_huyao 才会排队
	CharacterData.boss_progress = {"boss_huyao": {"killed": true, "first_kill": true}}
	for i in range(c1_steps.size() - 1):
		(CharacterData.tutorial_data["done"] as Dictionary)[
			String((c1_steps[i] as Dictionary).get("id", ""))] = true
	# c5 的战斗内锻造段（捡晶石→返回→上砧→拿锤→强化→取下→拖装）当作已做完，
	# 这样接上时正好停在「去万界塔」，聚光断言继续有效
	for sid in ["c5_crystal", "c5_return", "c5_forge", "c5_place", "c5_hammer",
			"c5_enhance", "c5_take", "c5_equip"]:
		(CharacterData.tutorial_data["done"] as Dictionary)[sid] = true
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	Tutorial.set("_queued_chapter", "")

	var realm: Node = await _enter_realm()
	_check(Tutorial.active_chapter == "c1", "回城后接着第 1 章", Tutorial.active_chapter)
	_check(String(Tutorial.active_step.get("id", "")) == "c1_bag",
		"第 1 章停在「回城开背包」", String(Tutorial.active_step.get("id", "")))
	_check(String(Tutorial.get("_queued_chapter")) == "c5",
		"成长链已排队（不打断当前清单）", String(Tutorial.get("_queued_chapter")))

	# ===== ② 打开背包 → 第 1 章收尾 → 自动接上万界塔 =====
	Tutorial.note("bag_opened")
	for i in 6:
		await get_tree().process_frame
	_check(Tutorial.active_chapter == "c5", "第 1 章收尾后自动接上成长链",
		Tutorial.active_chapter)
	_check(String(Tutorial.active_step.get("id", "")) == "c5_go",
		"锻造段做完后从「去万界塔」继续", String(Tutorial.active_step.get("id", "")))

	# 聚光必须真的框在塔上（不是降级成卡片）
	var ov: Node = Tutorial.get("_overlay") as Node
	var tower: Node = realm.get_node_or_null("Facilities/Tower")
	var want: Rect2 = ov.call("_rect_of", tower)
	var got: Rect2 = ov.get("_target_rect")
	_check(bool(ov.get("_has_target")), "c5_go 有聚光目标（不是降级卡片）")
	_check(got.position.distance_to(want.position) < 2.0
			and absf(got.size.x - want.size.x) < 2.0,
		"聚光框对准 Facilities/Tower 碰撞体", "got=%s want=%s" % [got, want])
	_check(want.size.x > 8.0 and want.size.x < 900.0,
		"塔的聚光框是设施本身（不是整屏兜底）", str(want.size))

	# ⚠ 截图里抓到过：回城时塔正好在屏幕上边缘外，聚光框整块画到屏幕外，
	#   洞在屏幕外 → 四块压暗拼成满屏黑，玩家既看不到目标也看不到指路。
	#   把玩家放回出生点复现，要求实际绘制的框收在视口内。
	var player := realm.get_node_or_null("Player") as Node2D
	if player != null:
		player.global_position = Vector2(0.0, 100.0)
		var cam := player.get_node_or_null("Camera2D") as Camera2D
		if cam != null:
			cam.reset_smoothing()
	for i in 8:
		await get_tree().process_frame
	var frame: Rect2 = ov.call("_spot_frame")
	var vp := get_viewport().get_visible_rect().size
	_check(frame.size != Vector2.ZERO
			and frame.position.x >= 0.0 and frame.position.y >= 0.0
			and frame.end.x <= vp.x + 0.5 and frame.end.y <= vp.y + 0.5,
		"目标在屏幕外时聚光框仍收在视口内", "%s vp=%s" % [frame, vp])
	# 单元级：把「塔在上边缘外」的真实矩形直接喂给收边函数（headless 相机与窗口不同，
	# 光靠上面那条可能恰好落在屏幕内，抓不到回归）
	var out_box: Rect2 = ov.call("_clamp_rect_to_view",
		Rect2(Vector2(1100.0, -80.0), Vector2(120.0, 80.0)), Vector2(1280.0, 720.0))
	_check(out_box.position.y >= 0.0 and out_box.end.y <= 720.5,
		"屏幕外的框被收进视口（回城时塔在上边缘外的真实情况）", str(out_box))

	# 走进塔 / 按 F 打开面板 → 这一步完成
	Tutorial.note("panel_opened:tower_panel")
	_check(String(Tutorial.active_step.get("id", "")) == "c5_pick",
		"打开塔面板 → 下一步「选一层挑战」", String(Tutorial.active_step.get("id", "")))
	await _realm_out(realm)

	# ===== ③ 第 1 章早做完 → 回城立刻开（从头开始，第一步是战斗里的捡晶石） =====
	CharacterData.tutorial_data = {"done": {}}
	for raw in c1_steps:
		(CharacterData.tutorial_data["done"] as Dictionary)[
			String((raw as Dictionary).get("id", ""))] = true
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	Tutorial.set("_queued_chapter", "")
	realm = await _enter_realm()
	_check(Tutorial.active_chapter == "c5", "第 1 章做完 → 回城立刻开成长链",
		Tutorial.active_chapter)
	_check(String(Tutorial.active_step.get("id", "")) == "c5_crystal",
		"仍然从「捡晶石」开始", String(Tutorial.active_step.get("id", "")))
	await _realm_out(realm)

	# ===== ④ 成长链做完 → 不再弹 =====
	for raw in (TutorialDB.get_chapter("c5").get("steps", []) as Array):
		(CharacterData.tutorial_data["done"] as Dictionary)[
			String((raw as Dictionary).get("id", ""))] = true
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	Tutorial.set("_queued_chapter", "")
	realm = await _enter_realm()
	_check(Tutorial.active_chapter == "" and String(Tutorial.get("_queued_chapter")) == "",
		"万界塔做完后回城不再弹",
		"%s/%s" % [Tutorial.active_chapter, String(Tutorial.get("_queued_chapter"))])
	await _realm_out(realm)

	CharacterData.tutorial_data = saved_done
	CharacterData.boss_progress = saved_boss
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	Tutorial.set("_queued_chapter", "")


## 真实进一次主城（等它自己跑完 _ready 的引导判定）
func _enter_realm() -> Node:
	var realm: Node = (load(REALM) as PackedScene).instantiate()
	add_child(realm)
	for i in 20:
		await get_tree().process_frame
	return realm


func _realm_out(realm: Node) -> void:
	if realm != null and is_instance_valid(realm):
		realm.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
