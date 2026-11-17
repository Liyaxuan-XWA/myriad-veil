extends CanvasLayer
## 战斗轮盘 —— 2026-10-24 用户定
##
## 战斗中按 G 唤出：右侧三格丹药、左侧三格符箓，鼠标指向扇区后左键使用。
## 装配在角色面板（Tab）的「战斗轮盘」一栏改，三种丹药 + 三种符箓，各不重复。
##
## 几条口径：
##   1. 打开的瞬间**暂停整棵树**（与角色面板同口径）—— 玩家用鼠标点选时不会被普攻/挨打打断，
##      轮盘节点自身 PROCESS_MODE_ALWAYS，暂停期间照常收键、照常画。
##   2. 只在战斗场景可用（场景里挂了 "combat_arena" 组才认），原初位面按 G 不弹。
##   3. 使用 = 扣背包里 1 个 → 按 ItemDB 的 battle_effect 生效 → 记该道具的 battle_cooldown。
##      持续类效果同时挂 BuffDB 的 buff（HUD 会显示剩余时间）与临时属性修正；
##      属性修正在 buff 到期后由本节点清掉，避免加成泄漏到下一场战斗。

## 2026-10-31：符箓占功法格，轮盘只负责 3 个丹药位。
const SLOT_ORDER: Array = ["pill_1", "pill_2", "pill_3"]
## 三个扇区的中心角度（度；0 = 正右，屏幕 y 轴向下，所以正角是顺时针）
const SLOT_ANGLES: Array = [210.0, 330.0, 90.0]
const WEDGE_HALF := 27.0
const RING_INNER := 76.0
const RING_OUTER := 198.0
## 鼠标落在圆环外的这个范围内也算「没选中」
const HOVER_INNER := 54.0
const HOVER_OUTER := 226.0
## 文字所在半径
const TEXT_RADIUS := 122.0
const SUB_RADIUS := 162.0

var _open := false
var _hovered := -1
## 打开后的短暂点击保护：手机用「道具」键打开时，同一次触摸还会模拟出一次鼠标点击，
## 不拦住的话刚打开就会被「点空白关闭」逻辑立刻关掉（2026-10-24）
var _ignore_click_until_msec: int = 0
const OPEN_CLICK_GUARD_MSEC := 200
## item_id -> 剩余战斗冷却秒数（运行时状态，不进存档）
var _cooldowns: Dictionary = {}
## item_id -> buff_id：持续效果还在生效的消耗品（buff 到期后清属性修正）
var _active_mods: Dictionary = {}

var _view: WheelView


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_view = WheelView.new()
	_view.owner_wheel = self
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.visible = false
	add_child(_view)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	var code := key.physical_keycode
	if code == KEY_G:
		get_viewport().set_input_as_handled()
		if _open:
			_close()
		elif RogueRun.active:
			# 试炼的四张符固定在 Q / E / R / T（use_run_talisman），轮盘里没有它们的位置
			_flash("试炼里符箓在 Q / E / R / T —— 结符页选的四张就是你的全部技能")
		elif _can_open():
			_open_wheel()
	elif _open and code == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()
	elif _open and code >= KEY_1 and code <= KEY_7:
		# 轮盘打开时按序号使用；局外是 1~3（丹药），试炼里是 1~N（已解锁的传承符）
		var idx := code - KEY_1
		if idx >= _slot_count():
			return
		get_viewport().set_input_as_handled()
		use_slot(idx)


func _process(delta: float) -> void:
	# 暂停期间（轮盘开着 / 别处面板开着）不推进冷却，也不清 buff 修正
	if get_tree().paused:
		return
	_tick_cooldowns(delta)
	_sweep_expired_mods()
	if _open:
		_view.queue_redraw()


## 退出副本 / 重开副本时清空本场战斗的丹药符箓冷却与临时属性修正
## （2026-10-24 用户定；玩家身上的 buff / debuff 由 player.reset_player() 另行清空）
func reset_battle_state() -> void:
	_cooldowns.clear()
	for iid in _active_mods.keys():
		CharacterData.clear_attribute_mod(_mod_source(String(iid)))
	_active_mods.clear()


## 打开条件：战斗场景 + 有活着的玩家 + 没有别的面板占着（暂停中）
func _can_open() -> bool:
	if get_tree().paused:
		return false
	if CharacterPanel.is_open():
		return false
	if get_tree().get_first_node_in_group("combat_arena") == null:
		return false
	var p := _player()
	if p == null or bool(p.get("is_dead")) or bool(p.get("is_casting_talisman")):
		return false
	# 试炼里不放丹药：轮盘整局都用不上（符在 Q / E / R / T）
	if RogueRun.active:
		return false
	return true


func _open_wheel() -> void:
	_open = true
	_hovered = -1
	_ignore_click_until_msec = Time.get_ticks_msec() + OPEN_CLICK_GUARD_MSEC
	_view.visible = true
	_view.queue_redraw()
	get_tree().paused = true
	# 手机：把虚拟摇杆 / 按键收起，避免它们抢走轮盘扇区的触摸
	VirtualPad.set_overlay_blocked(true)


func _close() -> void:
	if not _open:
		return
	_open = false
	_hovered = -1
	_view.visible = false
	get_tree().paused = false
	VirtualPad.set_overlay_blocked(false)
	# 用 1~6 选完道具时按键可能还按着；同步给玩家，避免关轮盘瞬间误召唤法宝
	var p := _player()
	if p != null and p.has_method("sync_summon_key_edges"):
		p.sync_summon_key_edges()


func is_open() -> bool:
	return _open


# ===================== 使用 =====================

## 鼠标/触屏点选：index 为当前扇区下标
func use_slot(index: int) -> void:
	if index < 0 or index >= _slot_count():
		return
	var slot_id := String(SLOT_ORDER[index])
	var item_id := CharacterData.quick_item_id(slot_id)
	if item_id == "":
		_flash("这一格还没装配")
		return
	var def := ItemDB.get_consumable(item_id)
	if def.is_empty():
		_flash("道具已不存在")
		return
	var cd := float(_cooldowns.get(item_id, 0.0))
	if cd > 0.0:
		_flash("%s 还在冷却（%.0f 秒）" % [String(def.get("pill_name", def.get("talisman_name", ""))), cd])
		return
	if CharacterData.count_item(item_id) <= 0:
		_flash("背包里没有%s了" % String(def.get("pill_name", def.get("talisman_name", ""))))
		return
	# 符箓的灵力门槛（2026-10-24 用户定：每张练气符纸 10 点）
	var mana_cost := float(def.get("mana_cost", 0.0))
	var p := _player()
	if mana_cost > 0.0 and (p == null or float(p.get("mana")) < mana_cost):
		_flash("灵力不足（%s 需要 %d 点）" % [String(def.get("talisman_name", "")), int(round(mana_cost))])
		return

	# 符纸 = 施法道具（2026-10-24）：收起轮盘 → 玩家原地施法 2 秒 → 完成后再结算
	if String(def.get("kind", "")) == "talisman":
		_close()
		_start_talisman_cast(item_id, p)
		return

	var msg := _apply_effect(item_id, def)
	if msg == "":
		return
	if p != null and mana_cost > 0.0:
		p.spend_mana(mana_cost)
	CharacterData.consume_item(item_id)
	# 任务面板（2026-11-11）：轮盘里真实用掉一颗才算
	Tutorial.note("pill_used")
	_cooldowns[item_id] = float(def.get("battle_cooldown", 0.0))
	if p != null:
		p._show_float_text(msg, UIKit.C_OK)
	GameState.play_ui("pickup")
	_close()


## 符纸施法：把 2 秒僵直与动画交给玩家，完成信号回来后才扣符纸 / 灵力并生效。
## ⚠ 用一次性连接而不是 await：玩家中途死亡 / 切场景时信号不会发，协程也不会挂着。
func _start_talisman_cast(item_id: String, p: Node) -> void:
	if p == null or not p.begin_talisman_cast(item_id):
		_flash("当前无法施符")
		return
	# 上一次施法若被死亡中断，旧连接还挂着；先清掉再连，避免下次完成时重复结算
	if p.is_connected("talisman_cast_finished", _on_talisman_cast_finished):
		p.disconnect("talisman_cast_finished", _on_talisman_cast_finished)
	p.connect("talisman_cast_finished", _on_talisman_cast_finished, CONNECT_ONE_SHOT)


func _on_talisman_cast_finished(item_id: String) -> void:
	var p := _player()
	if p == null or bool(p.get("is_dead")):
		return
	var def := ItemDB.get_consumable(item_id)
	if def.is_empty() or CharacterData.count_item(item_id) <= 0:
		return
	var mana_cost := float(def.get("mana_cost", 0.0))
	if mana_cost > 0.0 and not p.spend_mana(mana_cost):
		p._show_float_text("灵力不足（%s 需要 %d 点）" % [
			String(def.get("talisman_name", "")), int(round(mana_cost))], UIKit.C_FLOAT_WARN)
		return
	var msg := _apply_effect(item_id, def)
	if msg == "":
		return
	CharacterData.consume_item(item_id)
	_cooldowns[item_id] = float(def.get("battle_cooldown", 0.0))
	p._show_float_text(msg, UIKit.C_OK)
	GameState.play_ui("pickup")


## 按 battle_effect 生效；返回给玩家看的飘字文案（空串 = 没生效）
func _apply_effect(item_id: String, def: Dictionary) -> String:
	var p := _player()
	if p == null:
		return ""
	var eff = def.get("battle_effect", {})
	if not (eff is Dictionary):
		return ""
	var e: Dictionary = eff
	var name := String(def.get("pill_name", def.get("talisman_name", "")))
	match String(e.get("kind", "")):
		"heal_hp":
			var got: float = p.restore_health(float(p.max_hp) * float(e.get("ratio", 0.0)))
			return "%s · 回复气血 %d" % [name, int(got)]
		"restore_mana":
			var got_m: float = p.restore_mana(float(p.max_mana) * float(e.get("ratio", 0.0)))
			return "%s · 回复灵力 %d" % [name, int(got_m)]
		"buff":
			var bid := String(e.get("buff_id", ""))
			if BuffDB.get_buff(bid).is_empty():
				return ""
			p.apply_buff(bid, float(e.get("seconds", 0.0)))
			var mods = e.get("mods", {})
			if mods is Dictionary and not (mods as Dictionary).is_empty():
				CharacterData.set_attribute_mod(_mod_source(item_id), mods)
				_active_mods[item_id] = bid
			return "%s · %s" % [name, BuffDB.display_text(bid)]
	return ""


# ===================== 运行时状态 =====================

func _tick_cooldowns(delta: float) -> void:
	if _cooldowns.is_empty():
		return
	for iid in _cooldowns.keys():
		var left := float(_cooldowns[iid]) - delta
		if left <= 0.0:
			_cooldowns.erase(iid)
		else:
			_cooldowns[iid] = left


## buff 到期 / 玩家离场 → 把该消耗品写的临时属性修正撤掉
func _sweep_expired_mods() -> void:
	if _active_mods.is_empty():
		return
	var p := _player()
	for iid in _active_mods.keys():
		var bid := String(_active_mods[iid])
		if p == null or not p.has_buff(bid):
			CharacterData.clear_attribute_mod(_mod_source(String(iid)))
			_active_mods.erase(iid)


func _mod_source(item_id: String) -> String:
	return "consumable_" + item_id


func _cooldown_left(item_id: String) -> float:
	return float(_cooldowns.get(item_id, 0.0))


func _player() -> Node:
	var arr := get_tree().get_nodes_in_group("player")
	return arr[0] if arr.size() > 0 else null


func _flash(text: String) -> void:
	var p := _player()
	if p != null:
		p._show_float_text(text, UIKit.C_FLOAT_WARN)


# ===================== 绘制 / 鼠标 =====================

## 扇区数：固定三个丹药位（试炼不开放轮盘，符在 Q / E / R / T）
func _slot_count() -> int:
	return SLOT_ORDER.size()


## 扇区中心角：固定表（三个 120° 分布）
func _slot_angle(i: int) -> float:
	return float(SLOT_ANGLES[i]) if i >= 0 and i < SLOT_ANGLES.size() else 0.0


func _slot_half() -> float:
	return WEDGE_HALF


func _slot_item_id(i: int) -> String:
	if i < 0 or i >= SLOT_ORDER.size():
		return ""
	return CharacterData.quick_item_id(String(SLOT_ORDER[i]))


func _slot_has_count(i: int) -> bool:
	var iid := _slot_item_id(i)
	return iid != "" and CharacterData.count_item(iid) > 0


func _slot_color(i: int) -> Color:
	if _slot_item_id(i) == "":
		return Color(0.13, 0.13, 0.17, 0.94)
	return Color(0.17, 0.33, 0.26, 0.94)


func _draw_wheel(c: Control) -> void:
	var center := c.size * 0.5
	var font := c.get_theme_font("font", "Label")
	if font == null:
		font = ThemeDB.fallback_font
	var gold := Color(1.0, 0.86, 0.42, 1.0)

	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.02, 0.02, 0.05, 0.58))
	c.draw_circle(center, RING_INNER - 10.0, Color(0.05, 0.05, 0.09, 0.95))
	c.draw_arc(center, RING_INNER - 10.0, 0.0, TAU, 64, Color(0.55, 0.45, 0.26, 0.8), 2.0)
	c.draw_arc(center, RING_OUTER + 8.0, 0.0, TAU, 96, Color(0.55, 0.45, 0.26, 0.35), 1.5)

	for i in range(_slot_count()):
		_draw_slot(c, center, font, i)

	# 中心圆只有 132px 宽：提示行（"1~7 快速使用 · G 关闭"）本来就会横穿到扇区上，
	# 何况底部已经常驻一条操作提示 —— 圆里只留标题。
	var inner_w := (RING_INNER - 10.0) * 2.0
	c.draw_string(font, center + Vector2(-inner_w * 0.5, -6.0), "丹药轮盘",
		HORIZONTAL_ALIGNMENT_CENTER, inner_w, 17, gold)

	var tip := _hover_text()
	if tip != "":
		c.draw_string(UIKit.readable_font(), Vector2(center.x - 300.0, c.size.y - 74.0), tip,
			HORIZONTAL_ALIGNMENT_CENTER, 600.0, 15, Color(0.95, 0.92, 0.82, 1.0))


func _draw_slot(c: Control, center: Vector2, font: Font, i: int) -> void:
	var a := deg_to_rad(_slot_angle(i))
	var hovered := i == _hovered
	var base := _slot_color(i)
	var fill := base.lightened(0.22) if hovered else base
	var iid := _slot_item_id(i)
	# 品质描边：已装配的物品按稀有度上色；空格保持原来的暗金边
	var border := Color(1.0, 0.86, 0.42, 0.95) if hovered else Color(0.45, 0.38, 0.24, 0.85)
	if iid != "":
		border = ItemDB.rarity_color(String(ItemDB.get_consumable(iid).get("rarity", "common")))
		if hovered:
			border = border.lightened(0.25)
	var pts := _wedge_points(center, a, deg_to_rad(_slot_half()), RING_INNER, RING_OUTER)
	c.draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	c.draw_polyline(pts, border, 2.0 if (hovered or iid != "") else 1.0, true)

	# 内沿的编号数字就是「第几格」，不再另画「药 1 / 符 2」——七等分时那行会和符名叠在一起
	var dir := Vector2.RIGHT.rotated(a)
	c.draw_string(font, center + dir * (RING_INNER + 16.0) + Vector2(-14.0, -8.0), str(i + 1),
		HORIZONTAL_ALIGNMENT_CENTER, 28.0, 14, Color(1.0, 0.86, 0.42, 0.95))

	var text_r := TEXT_RADIUS
	var tw := 140.0
	var tx := -tw * 0.5

	if iid == "":
		c.draw_string(font, center + dir * text_r + Vector2(tx, -2.0),
			"未装配",
			HORIZONTAL_ALIGNMENT_CENTER, tw, 13, Color(0.52, 0.52, 0.58, 1.0))
		return

	var def := ItemDB.get_consumable(iid)
	var title := String(def.get("pill_name", def.get("talisman_name", iid)))
	var sub := ""
	var dim := false
	var count := CharacterData.count_item(iid)
	var cd := _cooldown_left(iid)
	dim = count <= 0 or cd > 0.0
	sub = "×%d" % count
	if cd > 0.0:
		sub = "冷却 %.0f 秒" % cd
	elif count <= 0:
		sub = "已用完"
	var title_col := Color(0.98, 0.95, 0.86, 1.0) if not dim else Color(0.58, 0.58, 0.62, 1.0)

	c.draw_string(font, center + dir * text_r + Vector2(tx, -2.0), title,
		HORIZONTAL_ALIGNMENT_CENTER, tw, 15, title_col)

	c.draw_string(font, center + dir * SUB_RADIUS + Vector2(tx, 4.0), sub,
		HORIZONTAL_ALIGNMENT_CENTER, tw, 12,
		Color(0.95, 0.72, 0.38, 1.0) if dim else Color(0.70, 0.82, 0.70, 1.0))


func _hover_text() -> String:
	if _hovered < 0:
		if VirtualPad.is_touch_enabled():
			return "点击扇区使用道具，点空白处关闭"
		return "按 1~3 或左键点击扇区使用丹药"
	var iid := _slot_item_id(_hovered)
	if iid == "":
		return "空格 —— 在角色面板「战斗轮盘」里装配"
	var def := ItemDB.get_consumable(iid)
	if def.is_empty():
		return "道具已不存在"
	var name := String(def.get("pill_name", def.get("talisman_name", iid)))
	var desc := String(def.get("desc", ""))
	var mana_cost := float(def.get("mana_cost", 0.0))
	var cost_note := "　消耗灵力 %d" % int(round(mana_cost)) if mana_cost > 0.0 else ""
	var cd := _cooldown_left(iid)
	if cd > 0.0:
		return "%s · 冷却中 %.0f 秒%s" % [name, cd, cost_note]
	return "%s · %s%s" % [name, desc, cost_note]


func _wedge_points(center: Vector2, a: float, half: float, r0: float, r1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 18
	for s in range(steps + 1):
		var t := a - half + 2.0 * half * float(s) / float(steps)
		pts.append(center + Vector2.RIGHT.rotated(t) * r1)
	for s in range(steps + 1):
		var t := a + half - 2.0 * half * float(s) / float(steps)
		pts.append(center + Vector2.RIGHT.rotated(t) * r0)
	return pts


## 鼠标位置 → 槽位下标（圆环内且落在某个扇区角度内）
func _slot_at(pos: Vector2) -> int:
	var center := _view.size * 0.5
	var d := pos - center
	var dist := d.length()
	if dist < HOVER_INNER or dist > HOVER_OUTER:
		return -1
	var ang := rad_to_deg(d.angle())
	for i in range(_slot_count()):
		var diff := fposmod(ang - _slot_angle(i) + 180.0, 360.0) - 180.0
		if absf(diff) <= _slot_half():
			return i
	return -1


func _on_view_input(event: InputEvent) -> void:
	if not _open:
		return
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_close()
			_view.accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			# 刚打开的 200ms 内忽略点击：手机「道具」键的同一次触摸会模拟出一次鼠标点击
			if Time.get_ticks_msec() < _ignore_click_until_msec:
				_view.accept_event()
				return
			var slot := _slot_at(mb.position)
			if slot < 0:
				# 点轮盘外的空白 = 取消（手机没有 G / 右键，必须留一个关闭手势）
				_close()
			else:
				use_slot(slot)
			_view.accept_event()
			return
	var mm := event as InputEventMouseMotion
	if mm != null:
		var hit := _slot_at(mm.position)
		if hit != _hovered:
			_hovered = hit
			_view.queue_redraw()


## 铺满全屏的绘制层：轮盘图形与文字都画在这里
class WheelView extends Control:
	var owner_wheel: CanvasLayer = null

	func _draw() -> void:
		if owner_wheel == null:
			return
		owner_wheel._draw_wheel(self)

	func _gui_input(event: InputEvent) -> void:
		if owner_wheel == null:
			return
		owner_wheel._on_view_input(event)
