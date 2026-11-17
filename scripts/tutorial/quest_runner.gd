extends Node
## 顺序任务系统 · 步骤机（autoload 名 = Quest）
##
## 2026-11-11 用户定：把旧「教学清单」重置成真正的任务面板——
## 12 个任务**按表序一个一个完成**，完成打勾，点开条目看指引（面板画在 quest_panel.gd）。
##
## 判定双通道（与教学步骤机同哲学）：
##   - **事件**：Tutorial.note() 开头转发进来（note 是全局事件入口，教学没在听也转发）；
##     另有「会话缓冲」——事件发生在任务激活**之前**会被记进 _seen，
##     任务激活时轮询补完成（玩家乱序提前做了后面的动作也不卡死）。
##   - **cond 轮询**：读存档级持久状态（boss_progress / tower_progress / 境界 / 破境材料），
##     跨会话兜底。cond 优先于事件。
##
## 职责边界：只做「当前哪个任务 / 完成了没有」；存档只读写 CharacterData.quest_data，
## 写盘走 SaveManager.auto_save()（闸门机制照旧）。
## ⚠ 性能：on_event 高频调用（攻击命中也发），第一行先判「还有没有任务」再干活。

signal changed                      ## 面板需要重画

const POLL_INTERVAL := 0.5          ## cond / 缓冲轮询间隔

## 本会话收到过的全部事件（kind → true）。乱序兜底用，不进存档。
var _seen: Dictionary = {}
var _poll_left := 0.0
var _panel: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 任务面板挂在 Quest 自己下面（CanvasLayer 由面板内部建），与教学浮层互不依赖
	_panel = load("res://scripts/tutorial/quest_panel.gd").new()
	_panel.name = "QuestPanel"
	add_child(_panel)


# ===================== 存档 =====================

func _done() -> Dictionary:
	return CharacterData.quest_data.get("done", {})


func is_done(id: String) -> bool:
	return bool(_done().get(id, false))


## 全部做完（面板可以隐藏 / 显示「全部完成」态）
func all_done() -> bool:
	return current_id() == ""


## 当前任务 = 第一条没完成的（顺序解锁的唯一真相）
func current_id() -> String:
	for raw in QuestDB.QUESTS:
		var q: Dictionary = raw
		if not bool(_done().get(String(q.get("id", "")), false)):
			return String(q.get("id", ""))
	return ""


func current_quest() -> Dictionary:
	return QuestDB.get_quest(current_id())


func progress() -> Vector2i:
	var done := 0
	for raw in QuestDB.QUESTS:
		if bool(_done().get(String((raw as Dictionary).get("id", "")), false)):
			done += 1
	return Vector2i(done, QuestDB.QUESTS.size())


func _mark_done(id: String) -> void:
	if not CharacterData.quest_data.has("done"):
		CharacterData.quest_data["done"] = {}
	(CharacterData.quest_data["done"] as Dictionary)[id] = true


# ===================== 事件入口 =====================

## 由 Tutorial.note() 转发（所有 note 事件都过这里，教学在不在听无关）。
## kind 形如 "forge_enhance" / "craft_done:pill" / "boss_died"
func on_event(kind: String) -> void:
	if kind == "":
		return
	_seen[kind] = true
	var q := current_quest()
	if q.is_empty():
		return
	var ev := String(q.get("ev", ""))
	if ev != "" and _ev_match(ev, kind):
		_complete()


## 与教学 note 同语义：want 带参（"craft_done:pill"）要求全等；
## want 不带参只比基础名（"boss_died" 能吃下任何带参变体）
func _ev_match(want: String, kind: String) -> bool:
	if want.contains(":"):
		return want == kind
	return kind.split(":")[0] == want


# ===================== 轮询兜底 =====================

func _process(delta: float) -> void:
	var q := current_quest()
	if q.is_empty():
		return
	_poll_left -= delta
	if _poll_left > 0.0:
		return
	_poll_left = POLL_INTERVAL
	# cond 优先（存档级事实）
	# cond 优先（存档级事实）
	var cond := String(q.get("cond", ""))
	if cond != "" and _cond_met(cond):
		_complete()
		return
	# 会话缓冲：事件发在任务激活前（乱序操作）→ 激活后立即补完成
	var ev := String(q.get("ev", ""))
	if ev != "":
		var base := ev.split(":")[0]
		if _seen.has(ev) or _seen.has(base):
			_complete()


## 状态兜底：只读不写。键表与 QuestDB.QUESTS 里的 cond 字面量一一对应，
## 由 probe_quest_panel 静态审计盯死（写错 = 任务永远完不成）。
func _cond_met(key: String) -> bool:
	match key:
		"boss_killed:boss_huyao":
			return CharacterData.boss_progress.has("boss_huyao")
		"tower_cleared_any":
			# 塔通关计数在 tower_progress[floor]["clear_count"]（battle_resolver._resolve_tower 写入）
			for floor_no in CharacterData.tower_progress:
				var rec: Dictionary = CharacterData.tower_progress[floor_no]
				if int(rec.get("clear_count", 0)) > 0:
					return true
			return false
		"realm_broken_any":
			# 小突破 stage>0，大突破换 realm（初始 练气·前期）
			return CharacterData.realm_stage > 0 \
				or CharacterData.current_realm != CharacterData.REALM_ORDER[0]
		"has_pojing_material":
			# 背包里数得着任一破境材料（id 前缀 mat_pojing_，只有首领掉）
			for it in CharacterData.inventory:
				var d: Dictionary = it
				if String(d.get("id", "")).begins_with("mat_pojing_") \
						and int(d.get("count", 1)) > 0:
					return true
			return false
		"lianqi_core_killed":
			# 存档级事实：secret_world._core_kill_table()[rid] = true → core_kills
			# 认**区域**而不是认物品：底髓可以丢、可以花，击杀是永久进度
			return CharacterData.is_core_killed(SecretWorldDB.REGION_LIANQI)
		_:
			return false


# ===================== 完成 =====================

func _complete() -> void:
	var id := current_id()
	if id == "":
		return
	_mark_done(id)
	SaveManager.auto_save()
	changed.emit()
