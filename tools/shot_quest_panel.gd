extends Node
## 顺序任务面板 · 截图验收（2026-11-11）
## 出四张：
##   ① 原初位面展开态 —— 面板在左上按钮列下方（y=184）：任务名 + 怎么做
##   ② 收起态 —— **只剩一个 30×30 的小箭头按钮**，不许留长框（2026-11-11 用户报）
##   ③ 打开万界秘境 —— 任务面板整块消失（不压在面板上层）
##   ④ 开始界面 —— 面板必须整块不显示
## 用法：godot --path . --resolution 1280x720 res://tools/shot_quest_panel.tscn -- --no-save

const REALM_SCENE := "res://scenes/main/primordial_realm.tscn"
const DOMAIN_PANEL := "res://scripts/ui/panels/domain_panel.gd"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	# 教学全静默（legacy 不自动弹），任务面板摆出「前 4 个已完成、第 5 个进行中」的现场
	CharacterData.tutorial_data = {"legacy": true}
	CharacterData.quest_data = {"done": {
		"q_kill_huyao": true, "q_enhance": true, "q_tower": true, "q_equip_skill": true}}
	CharacterData.boss_progress = {"boss_huyao": {"killed": true, "first_kill": true}}

	# ===== ① 原初位面全景 =====
	# ⚠ 必须把 current_scene 指到主城：任务面板的露脸判据是 in_primordial_realm()
	# ⚠ _ready 里 root 还在 setup 子节点，直接 add_child 会失败 → 走 deferred 再等两帧
	var realm = (load(REALM_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(realm)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = realm
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	# ⚠ 主城 _ready 会做存档初始化（把 quest_data 覆盖回空表）→ 必须在它之后摆进度
	CharacterData.tutorial_data = {"legacy": true}
	CharacterData.quest_data = {"done": {
		"q_kill_huyao": true, "q_enhance": true, "q_tower": true, "q_equip_skill": true}}
	CharacterData.boss_progress = {"boss_huyao": {"killed": true, "first_kill": true}}
	# 摆现场：当前任务（q5）自动展示「任务名 + 怎么做」
	# （主城读档带进来的境界/材料状态会让 cond 把现场滚走，截图期间要压住轮询）
	Quest.set("_poll_left", 99999.0)
	Quest.changed.emit()
	for i in 12:
		await get_tree().process_frame
	# 等面板高度校准（_fit_pending 下一帧才跑）
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/quest_panel_realm.png")
	print("SHOT output/quest_panel_realm.png")

	# ===== ② 收起：只剩小箭头按钮 =====
	var qp: Node = Quest.get("_panel") as Node
	qp.call("_toggle_fold")
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/quest_panel_folded.png")
	print("SHOT output/quest_panel_folded.png")
	qp.call("_toggle_fold")          # 展开回来，后面的截图要正常现场
	for i in 6:
		await get_tree().process_frame

	# ===== ③ 打开万界秘境：任务面板必须让位 =====
	var dlg = (load(DOMAIN_PANEL) as Script).new()
	get_tree().root.add_child(dlg)
	dlg.open()
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/quest_panel_domain.png")
	print("SHOT output/quest_panel_domain.png")
	dlg.close()
	for i in 6:
		await get_tree().process_frame

	realm.queue_free()
	get_tree().current_scene = self
	for i in 4:
		await get_tree().process_frame

	# ===== ④ 开始界面：任务面板必须整块不露脸 =====
	# （2026-11-11 用户报「为什么在这里就显示了」——Quest 是 autoload，面板跨场景常驻）
	var title = (load("res://scenes/ui/title_screen.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(title)
	await get_tree().process_frame
	get_tree().current_scene = title
	title.modulate.a = 1.0            # 跳过淡入，免得截到黑屏
	# 面板靠 _process 比对判定刷新 → 多等几帧
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/quest_panel_title.png")
	print("SHOT output/quest_panel_title.png")

	get_tree().quit(0)
