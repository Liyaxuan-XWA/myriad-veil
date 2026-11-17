extends Node
## 虎妖战败「封印松动 · 去取剑」实机截图（**必须窗口化**）
##
## 用法：godot --path . --resolution 1280x720 res://tools/shot_sword_hint.tscn -- --no-save
## 出图：
##   output/sword_hint_death.png   战败屏上的取剑卡（压在「玩家死亡」上方）
##   output/sword_hint_landing.png 点卡之后落在「万界秘境 · 苍澜大陆 · 青岚野」
##
## ⚠ 换场景是同步的：点卡那一步先把本节点挂到 GameState 底下，否则拍不到回城后的界面。

const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"
const SWORD := "eq_wentian_jian"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	# 现场：没剑 + 已经死过一次（这一次死亡 = 第 2 次）
	for i in range(CharacterData.inventory.size() - 1, -1, -1):
		if String((CharacterData.inventory[i] as Dictionary).get("id", "")) == SWORD:
			CharacterData.inventory.remove_at(i)
	for slot in CharacterData.equipment_slots.keys():
		var it = CharacterData.equipment_slots[slot]
		if it is Dictionary and String((it as Dictionary).get("id", "")) == SWORD:
			CharacterData.equipment_slots[slot] = null
	CharacterData.boss_death_count["domain_01/boss_huyao"] = 1
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_01",
		"boss_id": "boss_huyao",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	for i in 4:
		await get_tree().process_frame
	var p: Node = arena.get("player")
	p.set_physics_process(false)
	p.set("hp", 0.0)
	p.emit_signal("player_died")
	# 等慢动作 / 卡入场（0.26s）走完
	for i in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/sword_hint_death.png")
	print("SHOT output/sword_hint_death.png")

	# 点卡 → 回城 → 面板停在青岚野（把本节点挪出去才活得到那时）
	var card: Control = arena.get_node_or_null("HUD/SwordHint")
	if card == null:
		print("[!] 取剑卡没出现")
		get_tree().quit(1)
		return
	var host := get_node_or_null("/root/GameState")
	if host != null:
		get_parent().remove_child(self)
		host.add_child(self)
	var btn: Button = null
	for n in card.find_children("*", "Button", true, false):
		btn = n as Button
	if btn == null:
		print("[!] 卡上没有令签")
		get_tree().quit(1)
		return
	btn.pressed.emit()
	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/sword_hint_landing.png")
	print("SHOT output/sword_hint_landing.png")
	get_tree().quit(0)
