extends Node2D
## 虎妖战败「封印松动 · 去取剑」提示自检（2026-11-12 用户定）
##
## 用法：godot --headless --path . --quit-after 30000 res://tools/probe_sword_hint.tscn -- --no-save
##
## 判据口径：
##   ① 触发条件全部走**真实死亡链**：`player.player_died` 信号 → arena._on_player_died，
##      不直接调 `_maybe_show_sword_hint()`（那样阈值/来源判定都没被覆盖）；
##   ② 「没拿到剑」用 CharacterData.owns_equipment 验三条路：没拿 / 在背包 / 穿在身上；
##   ③ 点卡跳转要验到底：真的按按钮 → 回城 → 面板停在「苍澜大陆 · 青岚野」，
##      不是只看 `pending_panel` 有没有写。
##
## ⚠ 换场景是同步的（见 probe_domain_boss_order 的同一条坑）：最后一步之前先把探针
##   挂到 autoload 底下，才活得到断言。

const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"
const SWORD := "eq_wentian_jian"

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _drop_sword() -> void:
	for i in range(CharacterData.inventory.size() - 1, -1, -1):
		if String((CharacterData.inventory[i] as Dictionary).get("id", "")) == SWORD:
			CharacterData.inventory.remove_at(i)
	for slot in CharacterData.equipment_slots.keys():
		var it = CharacterData.equipment_slots[slot]
		if it is Dictionary and String((it as Dictionary).get("id", "")) == SWORD:
			CharacterData.equipment_slots[slot] = null


func _give_sword(equip_it: bool) -> void:
	var tpl := ItemDB.get_equipment_template(SWORD)
	var item: Dictionary = CharacterData.make_equipment_instance(tpl)
	if equip_it:
		CharacterData.equipment_slots["weapon"] = item
	else:
		CharacterData.inventory.append(item)


func _set_deaths(n: int, boss_id: String = "boss_huyao") -> void:
	CharacterData.boss_death_count["domain_01/" + boss_id] = n
	CharacterData.boss_fail_streak.erase(boss_id)


func _arena(source: String, boss_id: String) -> Node:
	if source == BattleResolver.SOURCE_DOMAIN:
		GameState.battle_context = {
			"source": source, "domain_id": "domain_01", "boss_id": boss_id,
		}
	else:
		GameState.battle_context = {"source": source, "floor": 1, "boss_id": boss_id}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	return arena


## 走真实死亡链：玩家信号 → arena._on_player_died
func _die(arena: Node) -> void:
	var p: Node = arena.get("player")
	p.set("hp", 0.0)
	p.emit_signal("player_died")
	await get_tree().process_frame


func _card(arena: Node) -> Control:
	return arena.get_node_or_null("HUD/SwordHint") as Control


func _ready() -> void:
	print("\n########## 虎妖战败 · 封印松动提示 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _run() -> void:
	# ===== 1. 「有没有这柄剑」的唯一口径 =====
	_drop_sword()
	_check(not CharacterData.owns_equipment(SWORD), "身上没剑 ⇒ 未持有（题目成立）")
	_give_sword(false)
	_check(CharacterData.owns_equipment(SWORD), "在背包里也算持有")
	_drop_sword()
	_give_sword(true)
	_check(CharacterData.owns_equipment(SWORD), "穿在身上也算持有（不能只看背包）")
	_drop_sword()
	_check(not CharacterData.owns_equipment(SWORD), "清掉后回到未持有")
	_check(not CharacterData.owns_equipment(""), "空 id 不会误判成持有")

	# ===== 2. 阈值：一次不弹、两次才弹 =====
	_set_deaths(0)
	var a1 = await _arena(BattleResolver.SOURCE_DOMAIN, "boss_huyao")
	await _die(a1)
	_check(_card(a1) == null, "第 1 次死亡：不弹（阈值 2）")
	_check(int(CharacterData.get_boss_death("domain_01", "boss_huyao")) == 1,
		"死亡次数照常记 1", str(CharacterData.get_boss_death("domain_01", "boss_huyao")))
	await _die(a1)
	_check(_card(a1) != null, "第 2 次死亡：弹卡")
	var card := _card(a1)
	if card != null:
		var texts := ""
		for n in card.find_children("*", "Label", true, false):
			texts += String((n as Label).text)
		_check(texts.contains("青岚大陆有一柄剑"), "正文按用户原话", texts)
		_check(texts.contains("封印松动"), "写到「封印松动」")
		_check(texts.contains("青岚野"), "标题点名青岚野")
		var btn: Button = null
		for n in card.find_children("*", "Button", true, false):
			btn = n as Button
		_check(btn != null and btn.text == "前往青岚野", "卡上有「前往青岚野」令签",
				"" if btn == null else btn.text)
	# 连败横幅让位：同一场死亡不再叠「怎么变强」
	_check(a1.get("_grow_banner") == null, "取剑卡占位时，「怎么变强」横幅不叠上来")
	# 第 3 次死亡：仍然弹（「每次死亡都会提示」），且不叠第二张卡
	await _die(a1)
	var cards := 0
	for n in a1.get_node("HUD").get_children():
		if String(n.name) == "SwordHint":
			cards += 1
	_check(cards == 1, "第 3 次死亡仍然提示，但只有一张卡", "%d 张" % cards)
	a1.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# ===== 3. 拿到剑之后：不弹，且连败横幅回到原位 =====
	_set_deaths(5)
	CharacterData.boss_fail_streak["boss_huyao"] = 1   # 这一次死亡 = 连败第 2 场
	_give_sword(false)
	var a2 = await _arena(BattleResolver.SOURCE_DOMAIN, "boss_huyao")
	await _die(a2)
	_check(_card(a2) == null, "已经有剑 ⇒ 不再提示")
	_check(a2.get("_grow_banner") != null, "不提示取剑时，「怎么变强」横幅照旧出现")
	a2.queue_free()
	await get_tree().process_frame
	_drop_sword()

	# ===== 4. 别的 BOSS / 别的来源不弹 =====
	# ⚠ 刀客这一例必须把**刀客自己**的死亡数铺够：只铺虎妖的话，它卡在阈值上，
	#   等于根本没测到「认不认 BOSS」这一条（第一版变异 M3 就是这么假绿的）。
	_set_deaths(5, "boss_01")
	var a3 = await _arena(BattleResolver.SOURCE_DOMAIN, "boss_01")
	await _die(a3)
	_check(_card(a3) == null, "刀客死再多次也不推取剑（只针对虎妖）")
	a3.queue_free()
	await get_tree().process_frame
	# 塔里打虎妖投影：塔的死亡根本不进 boss_death_count，_maybe 拿到的是 0
	_set_deaths(5, "boss_huyao")
	var a4 = await _arena(BattleResolver.SOURCE_TOWER, "boss_huyao")
	await _die(a4)
	_check(_card(a4) == null, "万界塔的虎妖投影不推取剑（塔的死亡不进位面死亡表）")
	a4.queue_free()
	await get_tree().process_frame

	# ===== 5. 点卡真的跳到「苍澜大陆 · 青岚野」=====
	_set_deaths(1)
	var a5 = await _arena(BattleResolver.SOURCE_DOMAIN, "boss_huyao")
	await _die(a5)
	var card5 := _card(a5)
	_check(card5 != null, "现场：卡已弹出（题目成立）")
	if card5 == null:
		return
	# 换场景是同步的：先把自己挂到 autoload 底下，才活得到回城之后
	var host := get_node_or_null("/root/GameState")
	if host != null:
		get_parent().remove_child(self)
		host.add_child(self)
	GameState.pending_panel = {}
	var btn5: Button = null
	for n in card5.find_children("*", "Button", true, false):
		btn5 = n as Button
	_check(btn5 != null, "拿到卡上的令签")
	if btn5 != null:
		btn5.pressed.emit()
	for i in 3:
		await get_tree().process_frame
	_check(String(get_tree().current_scene.name) == "PrimordialRealm",
		"点卡之后回到了原初位面", str(get_tree().current_scene.name))
	_check(GameState.pending_panel.is_empty(), "一次性请求已被消费掉（不会粘住）")
	var panel: SystemPanel = null
	for n in get_tree().root.get_children():
		if n is DomainPanel:
			panel = n as DomainPanel
	_check(panel != null, "万界秘境面板已打开")
	if panel != null:
		_check(String(panel.get("_tab")) == "world", "直接停在「苍澜大陆」页",
				String(panel.get("_tab")))
		_check(String(panel.get("start_region_id")) == SecretWorldDB.REGION_LIANQI,
			"预选的是练气区（青岚野）", String(panel.get("start_region_id")))
		var board: Node = null
		for n in panel.find_children("*", "", true, false):
			if n.get("_selected_id") != null:
				board = n
		_check(board != null and String(board.get("_selected_id")) == SecretWorldDB.REGION_LIANQI,
			"区域板选中的确实是青岚野",
				"?" if board == null else String(board.get("_selected_id")))
		panel.close()
