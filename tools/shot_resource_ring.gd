extends Node
## 三才灵环 · 截图验收（2026-11-11）
##
## ⚠ 必须在**战斗场景**拍：灵环挂在 combat_arena 的 player 上，
##   主城的 Player 是另一套 `primordial_player.gd`（安全枢纽控制器，没有血/灵/精力，
##   也没有环）—— 第一版拿主城当现场，直接取不到 player。
##
## ⚠ 必须拍**非满值**：血/灵都铺满时根本看不出「还剩多少」这条核心诉求。三张分别是：
##   ① ring_full.png   满值（基准观感）
##   ② ring_half.png   血 50% / 灵 30% / 精力 2 格 —— 常态，看缺口读不读得出
##   ③ ring_alert.png  血 18%（告警红）/ 灵 8% / 精力 0 格 + 力竭（琥珀点 + 倒计时光）
##
## 用法：godot --path . --resolution 1280x720 res://tools/shot_resource_ring.tscn -- --no-save


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_03",
		"boss_id": "boss_03",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	for i in 4:
		await get_tree().process_frame
	var p: Node2D = arena.player
	if p == null:
		print("FAIL 竞技场没拿到 player")
		get_tree().quit(1)
		return
	# 冻住双方：否则 BOSS 会打、玩家会掉血，三张图的状态就不是摆出来的
	p.set_physics_process(false)
	p.set("invincible_timer", 9999.0)
	var boss: Node2D = arena.boss
	if boss != null:
		boss.set_physics_process(false)
	# 把人物摆到画面中央偏下，裁剪框才框得住整环
	p.global_position = Vector2(0.0, 180.0)
	# 等开场大字幕/HUD 提示淡出
	for i in 90:
		await get_tree().process_frame

	_aim(p, 1.0, 1.0, 5)
	await _shot("ring_full")
	_aim(p, 0.5, 0.3, 2)
	await _shot("ring_half")
	# ★ 没有力竭、单纯一格精力都没有：验「闪红」本身（2026-11-12 用户定）
	_aim(p, 0.6, 0.4, 0)
	await _shot("ring_no_stamina")
	_aim(p, 0.18, 0.08, 0)
	p.call("apply_debuff", "exhausted", 3.0, true)
	p.call("_refresh_exhaust_seal")
	await _shot("ring_alert")
	get_tree().quit(0)


## 摆状态。帧等待统一交给 _shot()，这里只写值并走三个既有刷新入口
func _aim(p: Node, hp_k: float, mp_k: float, st: int) -> void:
	p.set("hp", float(p.get("max_hp")) * hp_k)
	p.set("mana", float(p.get("max_mana")) * mp_k)
	p.set("stamina", st)
	p.call("_update_health_bar")
	p.call("_update_mana_bar")
	p.call("_update_stamina_bar")


func _shot(tag: String) -> void:
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/%s_raw.png" % tag)
	# 人物在 (0,180) 世界坐标 → 屏幕中心附近；裁 220×220 再 3× 放大，
	# 才能看出弧边有没有发毛、点有没有压到弧上
	var c := img.get_region(Rect2i(530, 230, 220, 220))
	var big := Image.create(c.get_width() * 3, c.get_height() * 3, false, c.get_format())
	for y in c.get_height():
		for x in c.get_width():
			var col := c.get_pixel(x, y)
			for dy in 3:
				for dx in 3:
					big.set_pixel(x * 3 + dx, y * 3 + dy, col)
	var path := "output/%s.png" % tag
	big.save_png(path)
	print("SHOT ", path)
