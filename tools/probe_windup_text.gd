extends Node
## 技能飘字「前摇第一帧」自检（2026-10-28）：
##   出招进入 WINDUP 时必须立刻有招名；释放阶段不得再补报一次。
## 用法：godot --headless --path . res://tools/probe_windup_text.tscn

const DZ_FORMS := [
	"form_array_plant", "form_array_line", "form_array_pull", "form_array_seal",
	"form_array_sweep", "form_array_step", "form_array_pile", "form_array_burst",
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


func _labels(text: String = "") -> int:
	var n := 0
	for c in get_children():
		if c is Label and (text == "" or (c as Label).text == text):
			n += 1
	return n


func _clear_labels() -> void:
	for c in get_children():
		if c is Label:
			c.queue_free()


func _label_color(text: String) -> Color:
	for c in get_children():
		if c is Label and (c as Label).text == text:
			return (c as Label).get_theme_color("font_color")
	return Color.TRANSPARENT


func _spawn(scene: String) -> Node:
	var boss: Node = (load(scene) as PackedScene).instantiate()
	add_child(boss)
	await get_tree().process_frame
	await get_tree().process_frame
	boss.set_physics_process(false)
	boss.set_process(false)
	return boss


func _ready() -> void:
	print("\n########## 技能飘字前摇探针 ##########")
	var dummy := Node2D.new()
	dummy.global_position = Vector2(220.0, 0.0)
	add_child(dummy)

	# ---------- 定阵先生：八式招名都必须在 _begin 出现 ----------
	var dz := await _spawn("res://scenes/boss/domain_boss_02_b.tscn")
	dz.target = dummy
	for form in DZ_FORMS:
		_clear_labels()
		await get_tree().process_frame
		var expect := String(MoveDB.resolve_boss(form).get("form_name", ""))
		dz._begin(form)
		var got := ""
		for c in get_children():
			if c is Label:
				got = (c as Label).text
				break
		_check(got == expect, "前摇首帧报招名 " + form, got)
		_check(not _label_color(expect).is_equal_approx(UIKit.C_TEXT_DIM),
			"招名保持原色（非灰）：" + form, str(_label_color(expect)))

	# ---------- 2026-10-31：非招名飘字统一灰色 ----------
	_clear_labels()
	await get_tree().process_frame
	dz.show_skill_line("测试招名", 0.1, 20, 160.0, UIKit.C_DMG_PHYS, -170.0)
	_check(_label_color("测试招名").is_equal_approx(UIKit.C_DMG_PHYS),
		"show_skill_line 保留招名颜色", str(_label_color("测试招名")))
	_clear_labels()
	await get_tree().process_frame
	dz.show_windup_line("测试状态", 0.1, 20, 160.0, Color.RED, -170.0)
	## 2026-11-02：状态字填充从 UIKit.C_TEXT_DIM 换成 BossBase.SKILL_TEXT_FILL（近白）。
	## 执烛场地重做后地面中位亮度到 73，深色 dim 字心与地面同亮度、4px 描边一盖就只剩轮廓。
	## 「不许按招式家族染色」这条规则没动 —— 仍然忽略传进来的 Color.RED。
	_check(_label_color("测试状态").is_equal_approx(BossBase.SKILL_TEXT_FILL),
		"show_windup_line 强制统一填充（忽略传入色）", str(_label_color("测试状态")))
	_clear_labels()
	await get_tree().process_frame
	dz._show_status_text("测试状态2")
	_check(_label_color("测试状态2").is_equal_approx(BossBase.SKILL_TEXT_FILL),
		"状态短入口统一填充", str(_label_color("测试状态2")))

	_clear_labels()
	await get_tree().process_frame
	dz._begin("form_array_burst")
	var before := _labels("解阵·雷落")
	dz._fire_skill()
	_check(before == 1 and _labels("解阵·雷落") == 1, "释放时不再重报招名",
		"%d -> %d" % [before, _labels("解阵·雷落")])
	dz.queue_free()

	# ---------- 太虚气君：化劲 / 吐纳只报招名，不带应对提示 ----------
	var qj := await _spawn("res://scenes/boss/domain_boss_02_c.tscn")
	_clear_labels()
	await get_tree().process_frame
	qj._qi = qj.MAX_QI
	qj._begin(qj.F_WARD)
	_check(_labels("化劲·卸力") == 1 and _labels("化劲·卸力 —— 停手！") == 0,
		"化劲只报招名")
	before = _labels("化劲·卸力")
	qj._cast_ward(MoveDB.resolve_boss(qj.F_WARD))
	_check(_labels("化劲·卸力") == before, "释放时不再重报化劲招名")
	_clear_labels()
	await get_tree().process_frame
	qj._qi = 0
	qj._begin(qj.F_BREATH)
	_check(_labels("归元·吐纳") == 1 and _labels("归元·吐纳 —— 打断它！") == 0,
		"吐纳只报招名")
	before = _labels("归元·吐纳")
	qj._cast_breath(MoveDB.resolve_boss(qj.F_BREATH))
	_check(_labels("归元·吐纳") == before, "释放时不再重报吐纳招名")
	qj.queue_free()

	# ---------- 虎妖 P2 砂石乱舞：后撤（前摇）首帧就报，出手不重报 ----------
	var tiger := await _spawn("res://scenes/boss/boss.tscn")
	tiger.target = dummy
	tiger.phase = 2
	_clear_labels()
	await get_tree().process_frame
	tiger._start_dash_back()
	_check(_labels("砂石乱舞") == 1, "砂石乱舞在后撤首帧")
	before = _labels("砂石乱舞")
	tiger._fire_burst_projectiles()
	_check(_labels("砂石乱舞") == before, "砂石乱舞出手不重报")
	tiger.queue_free()

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("FAILED  ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
