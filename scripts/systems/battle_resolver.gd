class_name BattleResolver
extends RefCounted
## 战斗来源与结算器
##
## 作用：位面 BOSS / 万界塔投影现在接入真实战斗（复用阶段1 的 combat_arena.tscn），
## 但切场景会丢失调用方上下文，无法在胜利后回调发放奖励。
## 因此把「这次战斗是为什么打的」写进 GameState.battle_context，
## 战斗场景在 BOSS 死亡时读取它并结算。
##
## 流程：
##   位面/塔面板点「挑战」 → start_xxx() 写上下文 → 切到战斗场景
##   战斗胜利 → resolve_victory() 结算出奖励与「待感悟功法」→ 战斗场景弹出感悟 UI
##             → 玩家点「确认收下」→ confirm_tower_rewards() 才真正写入 learned_skills
##   玩家按 ESC 回主城 → clear() 清空上下文
##
## 硬约束（§2.7 / §2.8.3）：
##   - 真实位面 BOSS 才产出万界本源，塔投影不产出
##   - 塔投影仅首杀可感悟功法，重复挑战不再获得
##   - **感悟功法不自动发放**：概率照旧（必得 1 / 30% 得 2 / 5% 全得），
##     但结果先挂在待确认区，玩家在感悟 UI 里确认后才入册；中途退出不损失也不白拿。

const SOURCE_ARENA := "arena"
const SOURCE_DOMAIN := "domain"
const SOURCE_TOWER := "tower"
## 大世界区域核心首领的重复挑战（从万界塔的分支节点进入）
const SOURCE_WORLD_CORE := "world_core"
## 肉鸽爬塔「试炼之路」：无限层、三选一构筑；不产出任何主模式掉落，只在结算发锻造晶石
const SOURCE_ROGUE := "rogue"
## 万界位面 BOSS 每次击杀给 500 修为（2026-10-24 用户定；2026-10-27 扩到位面 02；
## 2026-10-29 赫连霄落地后扩到位面 03）。万界塔投影不算；位面 04 及之后的修为产出
## 等对应 BOSS 做好后再登记。
const DOMAIN_BOSS_EXP := 500

const BATTLE_SCENE := "res://scenes/combat/combat_arena.tscn"

## 待玩家在感悟 UI 里确认的功法（id 数组）与所属塔层。
## ⚠ 用 static var 暂存：切场景会丢实例状态，但静态变量属于脚本本身，跨场景存活。
static var _pending_tower_skills: Array = []
static var _pending_tower_floor: int = 0

## C 重开时跳过一次 BOSS 入场卡（一次性：reload 前置 true，下一场 _ready 消费掉）
static var skip_next_intro := false


## 读取并清空「重开跳过入场卡」标记
static func consume_intro_skip() -> bool:
	var v := skip_next_intro
	skip_next_intro = false
	return v


# ===================== 开战入口 =====================

## 演武场：训练木桩，无奖励、不结算
static func start_arena() -> void:
	GameState.battle_context = {"source": SOURCE_ARENA}
	_go_to_battle()


## 位面真实 BOSS
## ⚠ 守关者按序挑战（2026-11-12 用户定）：入口这一侧也拦一道，
##   面板置灰只是表现，顺序本身由 CharacterData 说了算。
static func start_domain(domain_id: String, boss_id: String) -> void:
	if not CharacterData.is_boss_challengeable(domain_id, boss_id):
		return
	GameState.battle_context = {"source": SOURCE_DOMAIN, "domain_id": domain_id, "boss_id": boss_id}
	_go_to_battle()


## 万界塔投影（用对应 BOSS 的模型，投影与本体同形）
static func start_tower(floor_no: int) -> void:
	var f := WorldDB.get_floor(floor_no)
	GameState.battle_context = {
		"source": SOURCE_TOWER,
		"floor": floor_no,
		"boss_id": String(f.get("boss_id", "")),
	}
	_go_to_battle()


## 大世界区域核心首领的重复挑战：只允许已击败过的区域进入；
## 走战斗箱庭 + WorldEnemy，本体奖励不再重复，掉落装备由战斗场景按核心配置生成。
static func start_world_core(region_id: String) -> void:
	var region := SecretWorldDB.get_region(region_id)
	var boss_id := String(region.get("core_boss_id", ""))
	if boss_id == "" or not CharacterData.is_core_killed(region_id):
		return
	GameState.battle_context = {
		"source": SOURCE_WORLD_CORE,
		"region_id": region_id,
		"boss_id": boss_id,
	}
	_go_to_battle()


## 试炼之路：先建局（快照角色数据 → 换成裸装练气），再进战斗场景
## ⚠ 必须先 RogueRun.start_run()：战斗场景 _ready 读的就是「裸装后的属性」
## fam = 本局流派（sword / scar），决定开局功法与卡池
static func start_rogue(fam: String = "sword", tal_picks: Array = []) -> void:
	RogueRun.start_run(fam, tal_picks)
	GameState.battle_context = {
		"source": SOURCE_ROGUE,
		"floor": RogueRun.floor_no,
	}
	_go_to_battle()


static func _go_to_battle() -> void:
	GameState.reset_time_flow()
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		# 面板打开时游戏处于暂停状态，切场景前必须恢复，
		# 否则战斗场景一进去就是暂停的（玩家和 BOSS 都不动）
		tree.paused = false
		tree.change_scene_to_file(BATTLE_SCENE)


# ===================== 查询 =====================

static func current_source() -> String:
	return String(GameState.battle_context.get("source", SOURCE_ARENA))


## 战斗标题（显示在战斗场景顶部）
static func battle_title() -> String:
	var ctx := GameState.battle_context
	match current_source():
		SOURCE_DOMAIN:
			# get_domain_name 本身已带「位面 0X」，这里不要再拼前缀
			return "%s · %s" % [
				WorldDB.get_domain_name(String(ctx.get("domain_id", ""))),
				WorldDB.get_boss_name(String(ctx.get("boss_id", ""))),
			]
		SOURCE_TOWER:
			return "万界塔 第 %d 层 · %s" % [
				int(ctx.get("floor", 0)),
				WorldDB.get_boss_name(String(WorldDB.get_floor(int(ctx.get("floor", 0))).get("boss_id", ""))),
			]
		SOURCE_ROGUE:
			return "试炼之路 · 第 %d 层" % RogueRun.floor_no
		SOURCE_WORLD_CORE:
			var rid := String(ctx.get("region_id", ""))
			var clears := CharacterData.get_core_clear_count(rid)
			var tag := "" if clears <= 0 else " · 第 %d 次" % (clears + 1)
			return "苍澜大陆 · %s · 重战 %s%s" % [
				SecretWorldDB.get_region(rid).get("name", ""),
				WorldDB.get_boss_name(String(ctx.get("boss_id", ""))),
				tag,
			]
		_:
			return "演武场 · 木桩试炼"


# ===================== 胜利结算 =====================

## 战斗胜利结算。返回：
##   {
##     "message": String,        # 给玩家看的结算文案
##     "insight": Array[String], # 本次可感悟的功法 id（空 = 本次没有感悟环节）
##   }
static func resolve_victory() -> Dictionary:
	match current_source():
		SOURCE_DOMAIN:
			return _resolve_domain()
		SOURCE_TOWER:
			return _resolve_tower()
		SOURCE_WORLD_CORE:
			return _resolve_world_core()
		SOURCE_ROGUE:
			# 试炼之路的推进与奖励全在 RogueArena / RogueRun 里，这里不发任何东西
			return {"message": "", "insight": []}
		_:
			return {"message": "", "insight": []}


## 区域核心首领重战：不重复首杀材料 / 修为，只由战斗场景掉该首领的装备与锻造晶石。
## 每次胜利记一次重战次数（下一次血量 +10%，最多 2 倍），与塔层同口径。
static func _resolve_world_core() -> Dictionary:
	var ctx := GameState.battle_context
	var boss_id := String(ctx.get("boss_id", ""))
	var region_id := String(ctx.get("region_id", ""))
	if boss_id == "" or region_id == "":
		return {"message": "", "insight": []}
	var clears := CharacterData.record_core_clear(region_id)
	var mult := CharacterData.core_hp_multiplier(region_id)
	var next_text := ""
	if mult > 1.0:
		next_text = "　下次血量 +%d%%" % int(round((mult - 1.0) * 100.0))
		if mult >= 2.0 - 0.001:
			next_text += "（封顶）"
	return {
		"message": "重战 %s 胜利（第 %d 次）%s" % [
			WorldDB.get_boss_name(boss_id), clears, next_text],
		"insight": [],
	}


static func _resolve_domain() -> Dictionary:
	var ctx := GameState.battle_context
	var domain_id := String(ctx.get("domain_id", ""))
	var boss_id := String(ctx.get("boss_id", ""))
	if domain_id == "" or boss_id == "":
		return {"message": "", "insight": []}

	var was_cleared := CharacterData.is_domain_cleared(domain_id)
	var first := CharacterData.mark_boss_killed(domain_id, boss_id)
	# 首杀信息给掉落层用：秘境 BOSS 现在也掉锻造晶石（首杀 9 / 重复 3，
	# _spawn_drops 里按这个键取数量 —— 通关次数秘境不记档，只能在这一拍传下去）
	ctx["first_kill"] = first
	var exp_gain := 0
	if not WorldDB.get_domain(domain_id).is_empty():
		exp_gain = CharacterData.add_realm_exp(DOMAIN_BOSS_EXP)
	var exp_text := "　修为 +%d" % exp_gain if exp_gain > 0 else ""
	if not first:
		return {
			"message": "击杀 %s（此前已击杀，不再产出万界本源）%s" % [WorldDB.get_boss_name(boss_id), exp_text],
			"insight": [],
		}

	# 首杀「虎妖」当场开教学链（2026-11-10 用户定）：捡晶石 → 锻造强化 → 万界塔 → 功法。
	# ⚠ 在战斗结算里就开，不等回城 —— 链路第一步「捡晶石」发生在战斗场景里。
	#   c1/c2 还没走完时 request 是排队版，那章收尾自动接上；
	#   不是虎妖的首杀也会走到这里，开不开章由 c5 的 need（boss_killed:boss_huyao）拦。
	Tutorial.request_chapter_by_trigger("after_huyao")

	var msg := "击杀 %s，万界本源 +1%s" % [WorldDB.get_boss_name(boss_id), exp_text]
	if first:
		msg += "　蕴仙髓 ×1"
	if CharacterData.is_domain_cleared(domain_id):
		msg += "　%s 已通关" % WorldDB.get_domain_name(domain_id)
		if not was_cleared:
			msg += "，获得补天石 ×1"
		# 下一界域由 CharacterData.is_domain_unlocked 自动判定开放，无需手动解锁
		var next_id := _next_domain_id(domain_id)
		if next_id != "":
			msg += "，%s 已开放" % WorldDB.get_domain_name(next_id)
	return {"message": msg, "insight": []}


## 塔投影结算：**只算概率、只出结果，功法入册推迟到玩家在感悟 UI 里确认**
## （见 confirm_tower_rewards）。通关次数在这里就记 —— 晶石要立刻掉在地上。
##
## ⚠ 2026-10-17 用户改定：**重复通关也照样随机感悟功法**（旧规则「重复不再获得」已作废）。
##   已经掌握的门类会被跳过，所以重复刷只会补到还没学会的那几门。
static func _resolve_tower() -> Dictionary:
	var floor_no := int(GameState.battle_context.get("floor", 0))
	if floor_no <= 0:
		return {"message": "", "insight": []}

	# 记一次通关，拿到「本次是第几次」（1 = 首通）；晶石数量按这个给
	var clear_index := CharacterData.record_tower_clear(floor_no)
	# 新手指引 / 任务面板：通关即算（不等感悟确认——有的层没有功法可感悟）
	Tutorial.note("tower_clear")

	# 每次通关都掷一次：必得 1 门 / 30% 得 2 门 / 5% 得全部（**只从没掌握的里面掷**，
	# 所以只要还有没学的门类，本轮就一定有感悟 —— 不会随机空手）
	var picked: Array = []
	for sid in WorldDB.roll_floor_reward_skills(floor_no, CharacterData.learned_skills):
		var id := String(sid)
		if id == "" or id in picked:
			continue
		picked.append(id)

	_pending_tower_skills = picked
	_pending_tower_floor = floor_no

	var head := ("首杀第 %d 层" % floor_no) if clear_index == 1 \
		else ("第 %d 层第 %d 次通关" % [floor_no, clear_index])
	if picked.is_empty():
		# 占位 BOSS（没在 BOSS_MOVES 登记招式）这层本来就没有功法可感悟
		if WorldDB.get_floor_reward_skills(floor_no).is_empty():
			return {"message": "%s（该层暂无可感悟的功法）" % head, "insight": []}
		return {"message": "%s（该层功法你已全部掌握）" % head, "insight": []}
	return {
		"message": "%s，本次感悟 %d 门功法" % [head, picked.size()],
		"insight": picked,
	}


# ===================== 感悟确认 =====================

## 本次战斗是否有待确认的感悟功法
static func has_pending_insight() -> bool:
	return not _pending_tower_skills.is_empty()


## 感悟 UI 里点「确认收下」时调用：写入 learned_skills 并标记塔层首杀
## 返回真正新增的功法 id 列表（可能因已学会而为空）
static func confirm_tower_rewards() -> Array:
	var ids: Array = _pending_tower_skills.duplicate()
	_pending_tower_skills = []
	if ids.is_empty():
		return []

	var floor_no := _pending_tower_floor
	CharacterData.mark_tower_first_kill(floor_no)
	# 新手指引：塔首通（第 5 章）
	Tutorial.note("tower_clear")

	var learned: Array = []
	for sid in ids:
		var id := String(sid)
		if id in CharacterData.learned_skills:
			continue
		CharacterData.learned_skills.append(id)
		CharacterData.mark_skill_new(id)
		learned.append(id)
		Tutorial.note("skill_learned")
	return learned


## 取某界域之后的下一界域 id（无则空串）
## 注意：这里**不再写解锁标记** —— 解锁完全由 CharacterData.is_domain_unlocked 自动计算
static func _next_domain_id(cleared_id: String) -> String:
	for d in WorldDB.DOMAINS:
		if String(d.get("prev_domain", "")) == cleared_id:
			return String(d.get("domain_id", ""))
	return ""


static func clear() -> void:
	GameState.battle_context = {}
	# 待确认的感悟一并丢弃：未确认就离开 = 本次没有奖励，首杀也未标记（下次仍可获得）
	_pending_tower_skills = []
	_pending_tower_floor = 0
