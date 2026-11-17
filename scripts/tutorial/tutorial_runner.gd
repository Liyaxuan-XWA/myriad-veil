extends Node
## 新手指引 · 步骤机（autoload 名 = Tutorial）
##
## 为什么是 autoload：引导要跨「主城 → 战斗 → 回城」和换场景存活，
##   挂在任何一个场景节点上都会在切场景时丢掉进度与遮罩。
##
## 职责边界：
##   - 只做「现在该哪一步 / 完成了没有」，不画任何东西（画在 tutorial_overlay.gd）
##   - 事件一律从外面 `Tutorial.note(kind, arg)` 打进来，不反查业务对象
##   - 存档只读写 CharacterData.tutorial_data，不自己写盘
##
## ⚠ 性能：note() 在攻击命中、每次受击都会被调用，第一行必须先判「有没有在听」，
##   否则每帧几十次字典查找会拖慢战斗。

signal changed                      ## 清单/卡片需要重画
signal step_started(step: Dictionary)
signal step_finished(step_id: String)
signal chapter_finished(chapter_id: String)
signal pause_parry                   ## 暂停提示里玩家按了右键（战斗教学用）
signal pause_skip                    ## 暂停提示里玩家放弃
signal toast_clicked(kind: String)   ## 玩家点了「可领取」吐司（由场景决定开哪个面板）

## 状态兜底轮询间隔：0.25 秒够用，别每帧查存档
const POLL_INTERVAL := 0.25

var active_chapter: String = ""
var active_step: Dictionary = {}
var _count: float = 0.0              ## 当前步骤的累计（事件 / 距离）
var _paused_prompt := false
var _poll_left := 0.0
var _overlay: Node = null

## 排队中的下一章（空 = 没有）。见 request_chapter
var _queued_chapter: String = ""

## 正在监听的事件名（空 = 没有在看事件，note() 直接 return）
var _listen_ev: String = ""
var _listen_cond: String = ""
## 本步的 `need`（露面条件）当前是否满足。false = 这一步还没到点 / 条件已经走了，
## 卡片先藏起来（序列照旧占位），下次条件再满足时自己回来（2026-11-12 用户定：
## 「退出界面时要暂时消失，要再达成出现指引条件时才会再次出现」）。
var _step_need_ok := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = load("res://scripts/tutorial/tutorial_overlay.gd").new()
	_overlay.name = "TutorialOverlay"
	add_child(_overlay)


# ===================== 存档读写 =====================

func _done() -> Dictionary:
	var d: Dictionary = CharacterData.tutorial_data.get("done", {})
	return d


func is_done(step_id: String) -> bool:
	return bool(_done().get(step_id, false))


func is_legacy() -> bool:
	return bool(CharacterData.tutorial_data.get("legacy", false))


## 老档（存档里没有 tutorial_data 字段）不弹，但允许从小书重看
func reset_all() -> void:
	CharacterData.tutorial_data = {"done": {}}
	active_chapter = ""
	active_step = {}
	_queued_chapter = ""
	_listen_ev = ""
	_listen_cond = ""
	CharacterData.force_enhance_success = false
	changed.emit()
	start_chapter("c1")


func _mark_done(step_id: String) -> void:
	if not CharacterData.tutorial_data.has("done"):
		CharacterData.tutorial_data["done"] = {}
	(CharacterData.tutorial_data["done"] as Dictionary)[step_id] = true


# ===================== 章节触发 =====================

## 外部只需报「发生了什么」，这里决定要不要开一章
## ⚠ 一章允许写多个触发键（逗号分隔）：万界塔既由「首杀 BOSS 回城」主动触发，
##   也允许玩家自己先点开塔面板时兜底，见 TutorialDB 第 5 章。
func maybe_start(trigger: String) -> void:
	_start_by_trigger(trigger, false)


## 排队版 maybe_start：当前已有章在做时不放弃，记下来等那一章走完自动接上。
## 用在「不打断玩家手上这件事、但这件事做完必须带他去做下一件」的场合：
## 首杀 BOSS 回城时第 1 章往往正停在「回城开背包」，整块换掉清单就漏看掉落了。
## ⚠ 队列只存一章且先来后到：首杀回城这一条优先级最高，不被后来的覆盖。
func request_chapter_by_trigger(trigger: String) -> void:
	_start_by_trigger(trigger, true)


func _start_by_trigger(trigger: String, queue_if_busy: bool) -> void:
	if trigger == "":
		return
	if is_legacy():
		return
	for raw in TutorialDB.CHAPTERS:
		var ch: Dictionary = raw
		if not _trigger_matches(String(ch.get("trigger", "")), trigger):
			continue
		# 可选前置（章节 need）：不满足就绝不开章。例：万界塔要先打过 BOSS。
		var need := String(ch.get("need", ""))
		if need != "" and not _cond_met(need):
			continue
		var cid := String(ch.get("id", ""))
		if TutorialDB.first_open_step(cid, _done()).is_empty():
			continue          # 这章早做完了
		if active_chapter == cid:
			return
		if active_chapter == "":
			start_chapter(cid)
			return
		if queue_if_busy and _queued_chapter == "":
			_queued_chapter = cid
		return


func _trigger_matches(cfg: String, trigger: String) -> bool:
	for raw in cfg.split(","):
		if String(raw).strip_edges() == trigger:
			return true
	return false


func _drain_queue() -> void:
	if _queued_chapter == "":
		return
	var ch := _queued_chapter
	_queued_chapter = ""
	if TutorialDB.first_open_step(ch, _done()).is_empty():
		return
	start_chapter(ch)


## 当前这一步的露面条件（步骤级 need）现在满不满足。false = 条件还没到 / 已经走了，
## 例如「三选一里挑一张」只在三选一面板开着时露脸。指引浮层与探针都读这一条。
## ⚠ 锚点层面的可见性（界面关了整块藏）在 tutorial_overlay 里判，不在这里。
func step_visible() -> bool:
	return _step_need_ok


## 是否已经打过 BOSS（首杀回城要引导去万界塔，判据就是这个）。
## 由主城在 _ready 里问：打过就 request_chapter_by_trigger("after_first_boss")。
func has_killed_boss() -> bool:
	return not CharacterData.boss_progress.is_empty()


func start_chapter(chapter_id: String) -> void:
	var step := TutorialDB.first_open_step(chapter_id, _done())
	if step.is_empty():
		active_chapter = ""
		active_step = {}
		_listen_ev = ""
		_listen_cond = ""
		_step_need_ok = true
		CharacterData.force_enhance_success = false
		changed.emit()
		return
	active_chapter = chapter_id
	_enter_step(step)


func _enter_step(step: Dictionary) -> void:
	active_step = step
	_count = 0.0
	var need := String(step.get("need", ""))
	_step_need_ok = need == "" or _cond_met(need)
	_listen_ev = String(step.get("ev", ""))
	_listen_cond = String(step.get("cond", ""))
	# 教学必成（2026-11-10 用户定）：带 force_success 的步骤（c5 强化教学）激活期间，
	# CharacterData.enhance_item 直接走成功分支；离开这一步（完成 / 跳过 / 换步）立即复位。
	CharacterData.force_enhance_success = bool(step.get("force_success", false))
	step_started.emit(step)
	changed.emit()


func _finish_step() -> void:
	if active_step.is_empty():
		return
	var sid := String(active_step.get("id", ""))
	_mark_done(sid)
	step_finished.emit(sid)
	var next := TutorialDB.first_open_step(active_chapter, _done())
	if next.is_empty():
		var ch := active_chapter
		active_chapter = ""
		active_step = {}
		_listen_ev = ""
		_listen_cond = ""
		_step_need_ok = true
		CharacterData.force_enhance_success = false
		chapter_finished.emit(ch)
		changed.emit()
		# 排队中的下一章（例：首杀回城要去的万界塔）在这一章收尾后自动接上
		_drain_queue()
		return
	_enter_step(next)


## 「知道了」类步骤：玩家看完点确认即算完成（和跳过不同，会记 done）
func complete_current() -> void:
	if active_step.is_empty():
		return
	_finish_step()


## 跳过当前这一步（唯一粒度：用户 2026-11-10 定，不做整章跳过 / 全局关闭）
func skip_step() -> void:
	if active_step.is_empty():
		return
	_finish_step()


# ===================== 事件入口 =====================

## kind 形如 "attack_hit" / "panel_opened:forge_panel" / "moved"
func note(kind: String, arg: Variant = null) -> void:
	# ⚠ 先转发给顺序任务系统（Quest.on_event）：教学没在听的事件（_listen_ev == ""）
	#   到这里就 return 了，任务面板还要靠同一批事件打勾 —— 必须在丢弃之前转。
	Quest.on_event(kind)
	if _listen_ev == "" or active_step.is_empty():
		return
	# ⚠ 事件名支持 "基础名:参数"，步骤表只写基础名时不比参数
	var base := kind
	if kind.contains(":"):
		base = kind.split(":")[0]
	var want := _listen_ev
	if want.contains(":"):
		if want != kind:
			return
	elif base != want:
		return
	var need := float(active_step.get("n", 1))
	var add := 1.0
	# 位移这类事件直接传数值；其它事件传字典 {"d": 数量} 或什么都不传（每次算 1）
	if arg is float or arg is int:
		add = float(arg)
	elif arg is Dictionary and (arg as Dictionary).has("d"):
		add = float((arg as Dictionary).get("d", 0.0))
	_count += add
	if _count >= need:
		_finish_step()


func is_active_step(step_id: String) -> bool:
	return not active_step.is_empty() and String(active_step.get("id", "")) == step_id


func current_text() -> String:
	return String(active_step.get("text", ""))


# ===================== 状态兜底 =====================

func _process(delta: float) -> void:
	_tick_badges(delta)
	if active_step.is_empty():
		return
	_poll_left -= delta
	if _poll_left > 0.0:
		return
	_poll_left = POLL_INTERVAL
	# 步骤级 need：按当前状态**双向**同步 —— 满足才露脸；条件一走（三选一关掉 /
	# 离开那个界面）就再藏起来，下次满足再回来。只有完成 / 跳过才写 done。
	var need := String(active_step.get("need", ""))
	if need != "":
		var ok := _cond_met(need)
		if ok != _step_need_ok:
			_step_need_ok = ok
			changed.emit()
		if not ok:
			return
	if _listen_cond == "":
		return
	if _cond_met(_listen_cond):
		_finish_step()


## 状态兜底：事件漏埋时也能过（只读存档，不写）
## ⚠ c5 教学链（2026-11-10）的 cond 是**持久状态**，不是事件重放：
##   步骤机只听「当前这一步」的事件，玩家不按推荐顺序操作时（先拿锤 / 砧上直拖穿戴 /
##   提前回城），事件会发在「前一步还活着」的窗口里被丢掉 —— 这时轮询到这里，
##   状态已经满足，本步即刻补完。这也是静态审计（probe_tutorial ⑩）盯的键表。
func _cond_met(key: String) -> bool:
	match key:
		"any_boss_killed":
			return has_killed_boss()
		"boss_killed:boss_huyao":
			# c5 的章节 need：虎妖是凡界第一只、塔第 1 层的本体，教学链从它首杀开始
			return CharacterData.boss_progress.has("boss_huyao")
		"has_equipment":
			for raw in CharacterData.equipment_slots.values():
				if raw != null:
					return true
			return false
		"has_talisman":
			return not CharacterData.talisman_stock.is_empty()
		"has_crystal":
			# 捡没捡到锻造晶石（背包里数得着就算，哪怕事件发早了被丢）
			return CharacterData.has_materials({CharacterData.ENHANCE_MATERIAL: 1})
		"in_realm":
			# 是否已经回到原初位面（战斗来源上下文清空 = 已经不在战斗里）
			return String(GameState.battle_context.get("source", "")) == ""
		"forge_anvil_filled":
			return String(GameState.forge_anvil_id) != ""
		"forge_anvil_empty":
			return String(GameState.forge_anvil_id) == ""
		"forge_hammer_held":
			return bool(GameState.forge_hammer_held)
		"weapon_equipped":
			return CharacterData.equipment_slots.get("weapon") != null
		"rogue_pick_open":
			# 三选一面板开着 = 「三选一里挑一张」这一步才准露面
			return RogueRun.pick_open
		"skill_in_slot_q":
			# c5「把新功法装到 Q 槽」的状态兜底（2026-11-12 用户报）：Q 槽里有功法就算完成。
			# 事件只在「真的换了一门」时发 —— 玩家在步骤开始前就装好了会永远等不到。
			return CharacterData.active_skill_loadout.size() > 0 and String(CharacterData.active_skill_loadout[0]) != ""
		_:
			return false


# ===================== 战斗教学：暂停喂招 =====================

## 进入「暂停等右键」模式。由 combat_arena 在 BOSS 抬手时调用。
## ⚠ 树暂停后玩家的 _input 不生效，所以右键必须由 overlay（ALWAYS）接住，
##   收到后 emit pause_parry，由战斗侧代按 player._start_parry() 再解除暂停。
func pause_prompt(text: String) -> void:
	if _paused_prompt:
		return
	_paused_prompt = true
	_overlay.call("show_pause_prompt", text)


func resume() -> void:
	_paused_prompt = false
	_overlay.call("hide_pause_prompt")


func is_pause_prompt() -> bool:
	return _paused_prompt


## overlay 收到右键 / 跳过时回调进来
func _on_pause_parry() -> void:
	if not _paused_prompt:
		return
	pause_parry.emit()


func _on_pause_skip() -> void:
	if not _paused_prompt:
		return
	pause_skip.emit()


# ===================== 查询（清单 / 红点用） =====================

## 当前章节还没做的步骤（最多 n 条），清单直接照着画
func pending_steps(max_n: int = 3) -> Array:
	if active_chapter == "":
		return []
	var out: Array = []
	for raw in (TutorialDB.get_chapter(active_chapter).get("steps", []) as Array):
		var s: Dictionary = raw
		if bool(_done().get(String(s.get("id", "")), false)):
			continue
		out.append(s)
		if out.size() >= max_n:
			break
	return out


func chapter_progress() -> Vector2i:
	if active_chapter == "":
		return Vector2i(0, 0)
	var steps: Array = TutorialDB.get_chapter(active_chapter).get("steps", [])
	var done := 0
	for raw in steps:
		if bool(_done().get(String((raw as Dictionary).get("id", "")), false)):
			done += 1
	return Vector2i(done, steps.size())


func chapter_title() -> String:
	if active_chapter == "":
		return ""
	return String(TutorialDB.get_chapter(active_chapter).get("title", ""))


# ===================== 红点 / 吐司（只挂确定性待办）=====================
## ⚠ 口径（用户 2026-11-10 定）：只提醒「有东西等着你点」——
##   可领晶石 / 未看过的新物品 / 未看的新图鉴。🚫 不做「有材料能合成」这类模糊红点。

var _badge_timer := 0.0
var _last_badges: Dictionary = {}
var _badges: Array = []      ## [{btn, kind}]
var _badge_seeded := false


func attach_badge(btn: Control, kind: String) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	# ⚠ 先剔死条目再查重：进主城时 HUD 是新建的，上一份主城的按钮已经释放，
	#   但 _badges 里还留着它们。不在这里清的话，条目会随进出主城一路涨，
	#   要等下一次 0.5 秒轮询才回落 —— 那个瞬间正是「拿已释放按钮去 call」的报错源头。
	#   （2026-11-10 编辑器刷屏报错的同一条链路，探针 probe_city_layout 也在盯这个数。）
	var id := btn.get_instance_id()
	for raw in _live_badges():
		var b: Dictionary = raw
		if int(b.get("id", 0)) == id and String(b.get("kind", "")) == kind:
			return
	_badges.append({"id": id, "btn": btn, "kind": kind})
	_overlay.call("attach_badge", btn, kind)
	_overlay.call("set_badge", btn, badge_count(kind))


## 纯读，不写存档（写的话「看一眼就灭」会变成「刷新就灭」）
func badge_count(kind: String) -> int:
	match kind:
		"achievement":
			return _claimable_rewards()
		"codex":
			return maxi(0, CharacterData.codex_unlocked.size()
				- int(CharacterData.tutorial_data.get("seen_codex", 0)))
		"bag":
			return maxi(0, int(CharacterData.tutorial_data.get("unseen_items", 0)))
		_:
			return 0


func _claimable_rewards() -> int:
	var n := 0
	for raw in CodexDB.boss_entries():
		var e: Dictionary = raw
		for rv in (e.get("variants", []) as Array):
			var v: Dictionary = rv
			var cid := String(v.get("id", ""))
			if cid == "portrait" or not bool(v.get("unlocked", false)):
				continue
			if not CharacterData.is_card_reward_claimed(String(e.get("id", "")), cid):
				n += 1
	return n


## 某个入口看过了 → 清账（打开背包 / 图鉴 / 成就时调）
func mark_seen(kind: String) -> void:
	match kind:
		"bag":
			CharacterData.tutorial_data["unseen_items"] = 0
		"codex":
			CharacterData.tutorial_data["seen_codex"] = CharacterData.codex_unlocked.size()
	refresh_badges()


func refresh_badges() -> void:
	for raw in _live_badges():
		var b: Dictionary = raw
		var btn: Control = b.get("btn") as Control
		_overlay.call("set_badge", btn, badge_count(String(b.get("kind", ""))))


## 剔除按钮已被释放的条目，返回还活着的那些。
## ⚠ 必须真删，不能只 continue：留下的话每 0.5 秒都会拿已释放对象去 call，
##   报 "previously freed is not a subclass of the expected argument class"。
##   面板关掉 / 换场景 / 主城重建 HUD 都会造成这种悬空条目。
func _live_badges() -> Array:
	var out: Array = []
	for raw in _badges:
		var b: Dictionary = raw
		var btn: Variant = b.get("btn")
		if btn == null or not is_instance_valid(btn):
			continue
		out.append(b)
	_badges = out
	return out


func _tick_badges(delta: float) -> void:
	_badge_timer -= delta
	if _badge_timer > 0.0:
		return
	_badge_timer = 0.5
	# 同一类型可能挂在多个按钮上（触屏 / 鼠标各一个）→ 吐司按类型只弹一次
	var seen: Dictionary = {}
	for raw in _live_badges():
		var b: Dictionary = raw
		var kind := String(b.get("kind", ""))
		var btn: Control = b.get("btn") as Control
		var n := badge_count(kind)
		_overlay.call("set_badge", btn, n)
		if seen.has(kind):
			continue
		seen[kind] = true
		# 数量变多 + 不在战斗 → 弹一条可点吐司（战斗里不弹，会挡抬手）
		# ⚠ 第一次只记基线不弹：否则读档进主城会一次冒出三条「可领取」
		var prev := int(_last_badges.get(kind, 0))
		if _badge_seeded and n > prev and not _in_battle() and not is_legacy():
			_overlay.call("push_toast", _toast_text(kind, n), kind)
		_last_badges[kind] = n
	_badge_seeded = true


func _toast_text(kind: String, n: int) -> String:
	match kind:
		"achievement":
			return "成就里有 %d 项可领取晶石" % n
		"codex":
			return "图鉴有 %d 个新条目" % n
		"bag":
			return "背包里多了 %d 件东西" % n
		_:
			return "有新的东西可以看"


func _in_battle() -> bool:
	return String(GameState.battle_context.get("source", "")) != ""
