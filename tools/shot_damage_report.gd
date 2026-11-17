extends Node
## 伤害统计面板实机截图（窗口化）
## godot --path . --resolution 1280x720 res://tools/shot_damage_report.tscn -- --no-save
## ⚠ BOSS 会在 50% 血转阶段（转阶段期间伤害被吃），这里每一下前先清掉转阶段标记，
##   否则截图脚本自己会漏掉几行。

const ARENA := "res://scenes/combat/combat_arena.tscn"

func _ready() -> void:
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN, "domain_id": "domain_01", "boss_id": "boss_01",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load(ARENA) as PackedScene).instantiate()
	add_child(arena)
	for i in 10:
		await get_tree().process_frame
	var p: Node2D = arena.get("player")
	var boss: Node2D = arena.get("boss")
	p.set_physics_process(false)
	boss.set_physics_process(false)
	var max_hp := float(boss.get("max_hp"))
	var plan := [["刺", 0.21], ["斩", 0.30], ["平A", 0.26], ["万剑", 0.09], ["平A", 0.08]]
	for item in plan:
		boss.set("phase_transitioning", false)
		DamageMeter.push(String(item[0]))
		boss.take_damage(max_hp * float(item[1]), p, "physical", "")
		await get_tree().process_frame
	# 收尾：打到死（同样每下先清转阶段）
	for i in 40:
		if BossBase.is_unit_dead(boss):
			break
		boss.set("phase_transitioning", false)
		DamageMeter.push("平A")
		boss.take_damage(50.0, p, "physical", "")
		await get_tree().process_frame
	print("rows=", DamageMeter.rows, " dead=", BossBase.is_unit_dead(boss))
	for i in 60:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/damage_report.png")
	print("SHOT output/damage_report.png")
	get_tree().quit(0)
