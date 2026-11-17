class_name RogueRun
extends RefCounted
## 肉鸽爬塔「试炼之路」—— 本局运行期状态（全静态）
##
## 为什么用 static var 而不是 autoload：切战斗场景会丢实例状态，但静态变量属于脚本本身，
## 跨场景存活（与 BattleResolver 的待确认感悟同一套做法）；退出时统一 restore()。
##
## ⚠ 隔离铁律（2026-11-08 用户定）：
##   进局时把角色数据整组快照下来、换成裸装练气；出局时逐字段还原。
##   本局期间 **关闭自动存档**，防止「裸装状态」被写进永久档。
##   唯一写回永久存档的是：rogue_best_floor / rogue_runs / 锻造晶石。

# ===== 局内进度 =====
static var active := false
# 三选一面板是否正开着（2026-11-12：教学「三选一里挑一张」要在第一次弹面板时才露面）
static var pick_open := false
## 本局流派（开局功法与卡池都按它走）
static var family := "sword"
## 当前层（从 1 开始）；也是结算奖励的计分口径
static var floor_no := 1
## 当前小关：1~3 = 小怪关，4 = BOSS 关
static var stage_no := 1
## 当前波次：1~3
static var wave_no := 1
## 本局**已用掉**的复活次数。剩余量走 `revive_left()`，不存字段：
## ⚠ 11-12 审计修的真空卡「不灭」—— 它加的是 stat("revive_plus")，而复活数原来存成
##   开局算好的一次性数字，中途选到这张卡也追不上去。存「用了几次」+ 派生「总共几条」
##   才能让这张卡在任意时刻生效（和 cap/stat 同一个口径）。
static var revives_used := 0
## 本局击败的 BOSS 数
static var boss_kills := 0
## 本局已通关的关数（小怪关与 BOSS 关都算）——晶石结算计分口径之一
static var stages_cleared := 0
## 本局通过的层数（打完层 BOSS 进入下一层才 +1）——晶石结算另一口径
static var floors_cleared := 0
## 当前层 / 下一层的 BOSS
static var boss_id := ""
static var boss_queue: Array = []

# ===== 增益派生结果 =====
## id -> 叠层
static var buffs: Dictionary = {}
## 资源上限：name -> 加值（基值在 RogueDB.CAP_BASE）
static var cap_bonus: Dictionary = {}
## 机制乘区：name -> 加值（百分比类一律按「点」存，如 6.0 = +6%）
static var stats: Dictionary = {}
## 机制开关
static var flags: Dictionary = {}
## 招式覆盖：form_id -> { field: 倍率 }
static var form_mods: Dictionary = {}
## 虎煞层数（兽潮流）：开局 / 退出归零，击杀叠层。这是本模式唯一的「运行期层数资源」，
## 不进 buffs 字典 —— buffs 记的是「拿到几张卡」，层数记的是「这局杀了多少人」。
static var hunt_stacks := 0
## 杀意层数（通用卡「嗜杀」）：与虎煞同构的第二套运行期层数 —— 任何流派都能滚，
## 但受一次伤就掉一半。⚠ 不进 buffs，否则「拿到几张卡」与「现在几层」会混成一个数。
static var kill_marks := 0
## 一次性保命卡是否已用（每局重置，不随复活刷新 —— 否则一次复活能白嫖两次）
static var used_last_stand := false
static var used_mirror_stand_in := false

# ===== 局内成长：装备 / 境界（2026-11-08 用户定）=====
## ⚠ 全都是**本局独立容器**，绝不写 CharacterData.equipment_slots / realm_*。
## 拾到的装备进 gear_bag，穿戴的引用放 gear_slots（槽位名与 CharacterData.SLOT_ORDER 一致）。
static var gear_bag: Array = []
static var gear_slots: Dictionary = {}
## 局内境界：大境界索引 / 小阶段 / 修为 / 累计突破次数
static var realm_idx := 0
static var realm_minor := 0
static var realm_exp := 0
static var breakthroughs := 0

# ===== 符箓：四符连携（2026-11-10 重做；2026-11-11 连携改为可选强化）=====
## 主符 4 张占 Q/E/R/T，符囊（初始 2 格）做仓库 + 连携候选；
## ⚠ 连携机制本体要选到「连携」卡（tal_chain_on）才解锁，开局没有。
## 品阶 0~3（练气/筑基/结丹/元婴），变体每符二选一、互斥。
## ⚠ 这里存的是**符的 base_id**（tal_jinfeng），不是带品质后缀的 item_id ——
##   品质由 tal_tier 单独记，两套 id 混用会出现「装了符却读不到品阶」。
static var tal_main: Array[String] = []
static var tal_bag: Array[String] = []
static var tal_tier: Dictionary = {}
static var tal_variant: Dictionary = {}

# ===== 结算 =====
static var pending_result: Dictionary = {}

# ===== 快照 =====
static var _snapshot: Dictionary = {}
static var _auto_save_was_enabled := true


# ===================== 开局 / 收局 =====================

static func start_run(fam: String = "sword", tal_picks: Array = []) -> void:
	if active:
		restore()
	_snapshot = _capture_player()
	# 关自动存档：本局角色数据是「裸装练气」，绝不能被写盘
	_auto_save_was_enabled = SaveManager.auto_save_enabled
	SaveManager.auto_save_enabled = false

	active = true
	family = fam if RogueDB.FAMILY_START.has(fam) else "sword"
	floor_no = 1
	stage_no = 1
	wave_no = 1
	boss_kills = 0
	stages_cleared = 0
	floors_cleared = 0
	revives_used = 0
	buffs.clear()
	pending_result = {}
	pick_open = false
	hunt_stacks = 0
	kill_marks = 0
	used_last_stand = false
	used_mirror_stand_in = false

	init_gear_state()
	reset_talisman_state()
	if family == "talisman":
		_init_talisman_loadout(tal_picks)
	_apply_bare_state()
	_rebuild_boss_queue()
	boss_id = _next_boss_id()
	rebuild()
	# ⚠ _apply_bare_state() 里 attribute_mods.clear() 会清掉所有来源，
	#   rebuild() 也只写 "rogue" 组 —— 局内两套加成必须在这之后重新注入。
	refresh_gear_mods()
	refresh_realm_mods()


## 收局：还原角色数据、结算晶石、写回历史最高层。返回结果字典（给结算面板读）
static func finish_run(cleared_by_death: bool) -> Dictionary:
	if not active:
		return pending_result.duplicate(true)
	var reached := maxi(1, floor_no)
	# 晶石 = 通关关数 × 1 + 通过层数 × 2（2026-11-11 用户定）。
	# 进入就退出 = 0 关 0 层 = 0 晶石，没有保底（旧公式「到达层数 × 4」白嫖问题已修）。
	var crystals := stages_cleared * RogueDB.CRYSTALS_PER_STAGE \
		+ floors_cleared * RogueDB.CRYSTALS_PER_FLOOR_BONUS
	var best_before := CharacterData.rogue_best_floor

	restore()

	# 晶石入包：唯一的主模式产出
	var item := _make_crystal_item(crystals)
	CharacterData.return_item_or_force(item)

	CharacterData.rogue_best_floor = maxi(best_before, reached)
	CharacterData.rogue_runs += 1
	var unlocked: Array = []
	for fam in RogueDB.FAMILY_UNLOCK_FLOOR.keys():
		var need := int(RogueDB.FAMILY_UNLOCK_FLOOR[fam])
		if need > best_before and need <= CharacterData.rogue_best_floor:
			unlocked.append(String(fam))
	SaveManager.auto_save()

	pending_result = {
		"floor": reached,
		"boss_kills": boss_kills,
		"stages": stages_cleared,
		"floors": floors_cleared,
		"crystals": crystals,
		"best": CharacterData.rogue_best_floor,
		"new_best": reached > best_before,
		"unlocked": unlocked,
		"by_death": cleared_by_death,
	}
	return pending_result.duplicate(true)


## 开局初始化局内成长状态
static func init_gear_state() -> void:
	gear_bag = []
	gear_slots = {}
	for raw in CharacterData.SLOT_ORDER:
		gear_slots[String(raw)] = null
	realm_idx = 0
	realm_minor = 0
	realm_exp = 0
	breakthroughs = 0


## 拾到的装备进局内行囊（不进 CharacterData.inventory）
static func add_gear(item: Dictionary) -> bool:
	if not active or item.is_empty():
		return false
	gear_bag.append(item.duplicate(true))
	return true


## 装备类别 → 可放的槽位（与 CharacterData.slot_accepts 同口径，但这里不读局外状态）
static func gear_slots_for(etype: String) -> Array:
	match etype:
		"weapon": return ["weapon"]
		"armor": return ["armor"]
		"shoes": return ["shoes"]
		"accessory": return ["accessory_1", "accessory_2", "accessory_3"]
		_: return []


## 从行囊第 index 件穿戴；同类槽全满则顶掉第一个，被换下的回到行囊
static func equip_from_bag(index: int) -> bool:
	if not active or index < 0 or index >= gear_bag.size():
		return false
	var raw = gear_bag[index]
	if not (raw is Dictionary):
		return false
	var item: Dictionary = raw
	var slots := gear_slots_for(String(item.get("equipment_type", "")))
	if slots.is_empty():
		return false
	var slot := ""
	for s in slots:
		if gear_slots.get(String(s)) == null:
			slot = String(s)
			break
	if slot == "":
		slot = String(slots[0])
	var old = gear_slots.get(slot)
	gear_bag.remove_at(index)
	if old is Dictionary:
		gear_bag.append(old)
	gear_slots[slot] = item
	refresh_gear_mods()
	return true


static func unequip_gear(slot: String) -> bool:
	if not active or not gear_slots.has(slot):
		return false
	var raw = gear_slots.get(slot)
	if not (raw is Dictionary):
		return false
	gear_slots[slot] = null
	gear_bag.append(raw)
	refresh_gear_mods()
	return true


## 局内装备属性 → 独立 source "rogue_gear"。
## ⚠ ItemDB.item_attributes() 的 key 既可能是绝对词条，也可能是 "<attr>_pct" 百分比词条；
##   统一写成 {"flat": v} 后，绝对值走 _mod_flat(attr)、百分比走 _mod_flat(attr_pct)
##   → _pct_total()，与主模式 equipment_attributes() 的语义完全一致。
static func refresh_gear_mods() -> void:
	var sum: Dictionary = {}
	for slot in gear_slots.keys():
		var raw = gear_slots.get(slot)
		if not (raw is Dictionary):
			continue
		var attrs := ItemDB.item_attributes(raw as Dictionary)
		for k in attrs.keys():
			sum[String(k)] = float(sum.get(k, 0.0)) + float(attrs[k])
	var mods: Dictionary = {}
	for k in sum.keys():
		mods[String(k)] = {"flat": float(sum[k])}
	CharacterData.set_attribute_mod("rogue_gear", mods)


## 局内境界倍率 → 独立 source "rogue_realm"。
## 用 base_pct 复刻主模式 _realm_bonus() 的「按本体基础值加成」口径，
## 灵力回复另按加法补一条 flat（与 realm_mana_regen_bonus 同口径）。
static func refresh_realm_mods() -> void:
	var mult := pow(1.0 + CharacterData.REALM_MAJOR_GAIN, float(realm_idx)) \
		* pow(1.0 + CharacterData.REALM_MINOR_GAIN, float(realm_minor))
	var pct := (mult - 1.0) * 100.0
	var mods: Dictionary = {}
	for raw in CharacterData.REALM_GROWTH_ATTRS:
		mods[String(raw)] = {"base_pct": pct}
	var mr_key := String(AttributeDB.ATTR_MANA_REGEN)
	var dst: Dictionary = mods.get(mr_key, {})
	dst["flat"] = float(realm_idx) * CharacterData.REALM_MAJOR_MANA_REGEN \
		+ float(realm_minor) * CharacterData.REALM_MINOR_MANA_REGEN
	mods[mr_key] = dst
	CharacterData.set_attribute_mod("rogue_realm", mods)


static func realm_title() -> String:
	var majors: Array = CharacterData.REALM_ORDER
	var minors: Array = CharacterData.REALM_STAGES
	return "%s%s" % [
		String(majors[clampi(realm_idx, 0, majors.size() - 1)]),
		String(minors[clampi(realm_minor, 0, minors.size() - 1)])]


static func stage_exp_required() -> int:
	return RogueDB.TRIAL_STAGE_EXP_BASE \
		+ (realm_idx * CharacterData.REALM_STAGES.size() + realm_minor) \
		* RogueDB.TRIAL_STAGE_EXP_STEP


## 击杀给修为；满了**自动突破一次**，返回突破信息给调用方播明显提示。
## ⚠ 一次只突破一段，多余修为留到下次击杀再触发，避免一次击杀连弹多条公告。
static func add_exp(n: float) -> Dictionary:
	if not active or n <= 0.0:
		return {}
	realm_exp += int(round(n))
	var need := stage_exp_required()
	if realm_exp < need:
		return {}
	var from := realm_title()
	realm_exp -= need
	if realm_minor < CharacterData.REALM_STAGES.size() - 1:
		realm_minor += 1
	elif realm_idx < CharacterData.REALM_ORDER.size() - 1:
		realm_idx += 1
		realm_minor = 0
	else:
		# 化神后期圆满，封顶
		realm_exp = 0
		return {}
	breakthroughs += 1
	refresh_realm_mods()
	return {"broke": true, "from": from, "to": realm_title(), "count": breakthroughs}


## 逐字段还原角色数据（不依赖快照以外的任何东西）
static func restore() -> void:
	if not _snapshot.is_empty():
		CharacterData.base_attributes = (_snapshot.get("base_attributes", {}) as Dictionary).duplicate(true)
		CharacterData.current_realm = String(_snapshot.get("current_realm", "练气"))
		CharacterData.realm_stage = int(_snapshot.get("realm_stage", 0))
		# ⚠ 修为必须一起还原：局内是「练气前期」，突破一次就会把 realm_exp 清成 0，
		#   而 realm_exp 原本不在快照里 —— 玩家点一次突破，真实档上的几万修为直接归零（2026-11-08 报）
		CharacterData.realm_exp = int(_snapshot.get("realm_exp", CharacterData.realm_exp))
		CharacterData.learned_skills = (_snapshot.get("learned_skills", []) as Array).duplicate(true)
		CharacterData.new_skill_ids = (_snapshot.get("new_skill_ids", []) as Array).duplicate(true)
		CharacterData.active_skill_loadout = (_snapshot.get("active_skill_loadout", []) as Array).duplicate(true)
		CharacterData.passive_skill_loadout = (_snapshot.get("passive_skill_loadout", []) as Array).duplicate(true)
		CharacterData.equipment_slots = (_snapshot.get("equipment_slots", {}) as Dictionary).duplicate(true)
		CharacterData.treasure_slots = (_snapshot.get("treasure_slots", {}) as Dictionary).duplicate(true)
		CharacterData.attribute_mods = (_snapshot.get("attribute_mods", {}) as Dictionary).duplicate(true)
	CharacterData.clear_attribute_mod("rogue")
	CharacterData.clear_attribute_mod("rogue_hunt")
	CharacterData.clear_attribute_mod("rogue_gear")
	CharacterData.clear_attribute_mod("rogue_realm")
	gear_bag.clear()
	gear_slots.clear()
	realm_idx = 0
	realm_minor = 0
	realm_exp = 0
	breakthroughs = 0
	CharacterData.array_zone_attack_mult = 1.0
	CharacterData.sun_damage_mult = 1.0
	CharacterData.sword_intent_skill_mult = 1.0
	_snapshot.clear()
	active = false
	pick_open = false
	CharacterData.rogue_lock = false
	buffs.clear()
	cap_bonus.clear()
	stats.clear()
	flags.clear()
	form_mods.clear()
	hunt_stacks = 0
	kill_marks = 0
	SaveManager.auto_save_enabled = _auto_save_was_enabled


static func _capture_player() -> Dictionary:
	return {
		"base_attributes": CharacterData.base_attributes.duplicate(true),
		"current_realm": CharacterData.current_realm,
		"realm_stage": CharacterData.realm_stage,
		"realm_exp": CharacterData.realm_exp,
		"learned_skills": CharacterData.learned_skills.duplicate(true),
		"new_skill_ids": CharacterData.new_skill_ids.duplicate(true),
		"active_skill_loadout": CharacterData.active_skill_loadout.duplicate(true),
		"passive_skill_loadout": CharacterData.passive_skill_loadout.duplicate(true),
		"equipment_slots": CharacterData.equipment_slots.duplicate(true),
		"treasure_slots": CharacterData.treasure_slots.duplicate(true),
		"attribute_mods": CharacterData.attribute_mods.duplicate(true),
	}


## 裸装练气 + 本局流派的起始功法：本模式的统一入场状态
static func _apply_bare_state() -> void:
	var kit := RogueDB.family_start(family)
	CharacterData.base_attributes = CharacterData.BASE_ATTRIBUTE_DEFAULTS.duplicate(true)
	CharacterData.current_realm = "练气"
	CharacterData.realm_stage = 0
	# 修为也归零：否则面板会显示真实档的「87040 / 1000」，
	# 「突破」按钮亮着，一点就把真实修为清空
	CharacterData.realm_exp = 0
	CharacterData.learned_skills = (kit.get("learned", []) as Array).duplicate()
	CharacterData.new_skill_ids = []
	CharacterData.active_skill_loadout = (kit.get("active", []) as Array).duplicate()
	CharacterData.passive_skill_loadout = (kit.get("passive", []) as Array).duplicate()
	# 符箓：开局四符由「结符页」决定，四个槽直接装 talisman:<base_id>
	# ⚠ 槽值是符的 base_id，不带品质后缀 —— 品质走 RogueRun.tal_tier，两套别混
	if family == "talisman":
		CharacterData.passive_skill_loadout = []
		sync_talisman_loadout()
	CharacterData.equipment_slots = {
		"weapon": null, "armor": null, "shoes": null,
		"accessory_1": null, "accessory_2": null, "accessory_3": null,
	}
	CharacterData.treasure_slots = {"treasure_1": null, "treasure_2": null, "treasure_3": null}
	# 保留永久属性修正里与「丹药 / 图鉴」无关的部分：本模式直接清空全部临时修正，
	# 只留本局自己的 rogue_*（rebuild 会重写）
	CharacterData.attribute_mods.clear()
	# 上互斥锁：本局期间禁止换装 / 突破（restore() 里撤）
	CharacterData.rogue_lock = true


# ===================== 符箓：四符连携 =====================

static func reset_talisman_state() -> void:
	tal_main.clear()
	tal_bag.clear()
	tal_tier.clear()
	tal_variant.clear()


## 开局结符：不足 4 张时按表序补满（探针 / 旧调用点没传选择也能跑）
static func _init_talisman_loadout(picks: Array) -> void:
	var pool := TalismanDB.start_pool()
	for raw in picks:
		var id := String(raw)
		if pool.has(id) and not tal_main.has(id) and tal_main.size() < 4:
			tal_main.append(id)
	for raw in pool:
		if tal_main.size() >= 4:
			break
		var id := String(raw)
		if not tal_main.has(id):
			tal_main.append(id)
	for id in tal_main:
		tal_tier[id] = 0


static func talisman_owned(base_id: String) -> bool:
	return tal_tier.has(base_id)


static func talisman_tier(base_id: String) -> int:
	return int(tal_tier.get(base_id, 0))


static func talisman_variant_of(base_id: String) -> String:
	return String(tal_variant.get(base_id, ""))


static func talisman_variant_taken(base_id: String) -> bool:
	return tal_variant.has(base_id)


## 连携候选池：四张主符 + 符囊，去重保序
static func talisman_pool() -> Array:
	var out: Array = []
	for raw in tal_main:
		if not out.has(raw):
			out.append(raw)
	for raw in tal_bag:
		if not out.has(raw):
			out.append(raw)
	return out


static func talisman_bag_cap() -> int:
	return clampi(int(RogueDB.CAP_BASE.get("talisman_bag", TalismanDB.BAG_BASE))
		+ int(cap_bonus.get("talisman_bag", 0)), 0, 6)


## 符方卡：没拥有就获得（进符囊；符囊满了进主槽空位），已拥有就 +1 档
static func talisman_grant(base_id: String) -> bool:
	if TalismanDB.base_def(base_id).is_empty():
		return false
	if tal_tier.has(base_id):
		if int(tal_tier[base_id]) >= TalismanDB.QUALITY_MULT.size() - 1:
			return false
		tal_tier[base_id] = int(tal_tier[base_id]) + 1
		return true
	tal_tier[base_id] = 0
	if tal_main.size() < 4:
		tal_main.append(base_id)
	elif tal_bag.size() < talisman_bag_cap():
		tal_bag.append(base_id)
	else:
		# 符囊满：顶掉最早的一张备符（新符一定拿得到，不让玩家点了个空卡）
		if tal_bag.is_empty():
			tal_main.append(base_id)
		else:
			tal_bag.remove_at(0)
			tal_bag.append(base_id)
	return true


## 变体：每张基础符只能选一个，选了就不许换（互斥二选一）
static func talisman_set_variant(base_id: String, variant_id: String) -> bool:
	if tal_variant.has(base_id):
		return String(tal_variant[base_id]) == variant_id
	if not tal_tier.has(base_id):
		return false
	var vdef := TalismanDB.variant_def(variant_id)
	if vdef.is_empty() or String(vdef.get("base", "")) != base_id:
		return false
	tal_variant[base_id] = variant_id
	return true


## 把 `tal_main` 同步到四个主动槽与已学列表。**任何改动 tal_main 的地方都必须跟着调它。**
## ⚠ 2026-11-12 用户实机报「每层结束的换符环节，切换了但没生效」的根因：
##   `active_skill_loadout` 原来只在开局 `_apply_bare_state()` 里写过一次，
##   换符页改的是 `tal_main`，界面显示对调成功，按 Q/E/R/T 打出去的还是开局那四张。
##   数据与槽位是两份状态，改一份不叫改完。
static func sync_talisman_loadout() -> void:
	var slots: Array = []
	for raw in tal_main:
		slots.append(CharacterData.talisman_slot_value(String(raw)))
	CharacterData.active_skill_loadout = slots
	CharacterData.learned_skills = tal_main.duplicate()


## 换符：主槽 <-> 符囊（每层免费，调用方负责限制次数）
static func talisman_swap(main_index: int, bag_index: int) -> bool:
	if main_index < 0 or main_index >= tal_main.size():
		return false
	if bag_index < 0 or bag_index >= tal_bag.size():
		return false
	var a := tal_main[main_index]
	tal_main[main_index] = tal_bag[bag_index]
	tal_bag[bag_index] = a
	sync_talisman_loadout()
	return true


static func talisman_promote(base_id: String) -> bool:
	var idx := tal_bag.find(base_id)
	if idx < 0:
		return false
	if tal_main.size() < 4:
		tal_bag.remove_at(idx)
		tal_main.append(base_id)
		sync_talisman_loadout()
		return true
	return false


static func talisman_demote(main_index: int) -> bool:
	if main_index < 0 or main_index >= tal_main.size():
		return false
	if tal_bag.size() >= talisman_bag_cap():
		return false
	var id := tal_main[main_index]
	tal_bag.append(id)
	tal_main.remove_at(main_index)
	sync_talisman_loadout()
	return true


static func _make_crystal_item(count: int) -> Dictionary:
	if count <= 0:
		return {}
	var drop := ItemDB.make_material_drop(RogueDB.CRYSTAL_ID)
	if drop.is_empty():
		return {}
	var item: Dictionary = drop.get("item", {})
	item["count"] = count
	drop["count"] = count
	return item


# ===================== 进度推进 =====================

static func advance_stage() -> void:
	# 晶石计分埋点：走到这里 = 玩家打完了当前关的全部波次（普通关与 BOSS 关同路）
	stages_cleared += 1
	stage_no += 1
	wave_no = 1
	if stage_no > RogueDB.STAGES_PER_FLOOR:
		stage_no = 1
		floor_no += 1
		# 「过一层」以推进到下一层为准（打完层 BOSS 才会发生）
		floors_cleared += 1
		boss_id = _next_boss_id()


static func is_boss_stage() -> bool:
	return stage_no >= RogueDB.STAGES_PER_FLOOR


static func stage_label() -> String:
	if is_boss_stage():
		return "BOSS"
	return "小关 %d/%d" % [stage_no, RogueDB.STAGES_PER_FLOOR - 1]


## 波次清空后推进；返回是否进入了下一小关（外层据此决定要不要开三选一）
static func advance_wave() -> bool:
	wave_no += 1
	if wave_no <= RogueDB.WAVES_PER_STAGE:
		return false
	wave_no = RogueDB.WAVES_PER_STAGE
	return true


# ===================== BOSS 队列 =====================

static func _rebuild_boss_queue() -> void:
	boss_queue.clear()
	for id in RogueDB.BOSS_POOL:
		boss_queue.append(id)
	boss_queue.shuffle()
	# 第 1 层固定虎妖教学：把它从队列里摘掉，别让它在第 2 层立刻又出现
	boss_queue.erase(RogueDB.BOSS_TUTORIAL)


## 取本层 BOSS：第 1 层固定虎妖；每 4 层优先元婴档；队列空则重洗
static func _next_boss_id() -> String:
	if floor_no <= 1:
		return RogueDB.BOSS_TUTORIAL
	if floor_no % RogueDB.BOSS_TIER_SENIOR_EVERY == 0:
		for id in RogueDB.BOSS_SENIOR_IDS:
			if boss_queue.has(id):
				boss_queue.erase(id)
				return String(id)
	if boss_queue.is_empty():
		for id in RogueDB.BOSS_POOL:
			boss_queue.append(id)
		boss_queue.shuffle()
	return String(boss_queue.pop_front())


# ===================== 增益 =====================

static func add_buff(buff_id: String) -> void:
	var def := RogueDB.get_buff(buff_id)
	if def.is_empty():
		return
	var cap := RogueDB.stack_cap(buff_id)
	var cur := int(buffs.get(buff_id, 0))
	if cur >= cap:
		return
	buffs[buff_id] = cur + 1
	# 符方 / 改符卡的实际效果不在 rebuild 里：它们改的是「符的库存」，不是数值
	var recipe := String(def.get("recipe", ""))
	if recipe != "":
		talisman_grant(recipe)
	var variant := String(def.get("variant", ""))
	if variant != "":
		talisman_set_variant(String(def.get("base", "")), variant)
	rebuild()


static func buff_stacks(buff_id: String) -> int:
	return int(buffs.get(buff_id, 0))


## 三重算法：先清空派生结果，再按当前叠层整体重算（避免叠层时重复累计）
static func rebuild() -> void:
	cap_bonus.clear()
	stats.clear()
	flags.clear()
	form_mods.clear()

	var attr_mods: Dictionary = {}
	for raw_id in buffs.keys():
		var buff_id := String(raw_id)
		var def := RogueDB.get_buff(buff_id)
		if def.is_empty():
			continue
		var n := int(buffs.get(buff_id, 0))
		if n <= 0:
			continue

		var attr: Dictionary = def.get("attr", {})
		for attr_id in attr.keys():
			var m: Dictionary = attr[attr_id]
			var dst: Dictionary = attr_mods.get(attr_id, {})
			for field in ["flat", "base_pct", "mult"]:
				if m.has(field):
					var base := float(dst.get(field, 1.0 if field == "mult" else 0.0))
					if field == "mult":
						dst[field] = base * pow(float(m[field]), float(n))
					else:
						dst[field] = base + float(m[field]) * float(n)
			attr_mods[attr_id] = dst

		var cap: Dictionary = def.get("cap", {})
		for key in cap.keys():
			cap_bonus[key] = int(cap_bonus.get(key, 0)) + int(cap[key]) * n

		var st: Dictionary = def.get("stat", {})
		for key in st.keys():
			stats[key] = float(stats.get(key, 0.0)) + float(st[key]) * float(n)

		if String(def.get("flag", "")) != "":
			flags[String(def["flag"])] = true

		for fm in (def.get("form", []) as Array):
			var f: Dictionary = fm
			var form_id := String(f.get("form_id", ""))
			var field := String(f.get("field", ""))
			if form_id == "" or field == "":
				continue
			var table: Dictionary = form_mods.get(form_id, {})
			# 两种口径：默认乘算（mult_per）；带 "add" 的走加算，
			# ⚠ 加算字段在表里用 "+字段名" 作 key，避免和乘算混在同一格
			if f.has("add"):
				var add_key := "+" + field
				table[add_key] = float(table.get(add_key, 0.0)) + float(f["add"]) * float(n)
			else:
				table[field] = float(table.get(field, 1.0)) * (1.0 + float(f.get("mult_per", 0.0)) * float(n))
			form_mods[form_id] = table

	CharacterData.set_attribute_mod("rogue", attr_mods)
	_refresh_hunt_mods()


# ===================== 虎煞（兽潮流）=====================

## 虎煞上限 = 基值 + 「煞贯」
static func hunt_cap() -> int:
	if not active:
		return RogueDB.HUNT_BASE_CAP
	return maxi(1, RogueDB.HUNT_BASE_CAP + int(stat("hunt_cap_add")))


## 击杀叠层：没有「虎煞」开关卡时恒为 0（无卡不影响任何结算）
static func add_hunt(n: int) -> void:
	if not active or n <= 0 or not has_flag("hunt_gain"):
		return
	var before := hunt_stacks
	hunt_stacks = clampi(hunt_stacks + n, 0, hunt_cap())
	if hunt_stacks != before:
		_refresh_hunt_mods()


static func hunt_is_full() -> bool:
	return active and hunt_stacks > 0 and hunt_stacks >= hunt_cap()


## 虎煞的伤害加成（点）。「万兽」在满层时整段翻倍。
static func hunt_dmg_pct() -> float:
	if not active or hunt_stacks <= 0:
		return 0.0
	var pct := stat("hunt_dmg_per") * float(hunt_stacks)
	if pct <= 0.0:
		return 0.0
	if hunt_is_full() and has_flag("hunt_full_bloom"):
		pct *= 2.0
	return pct


## 虎煞的攻速加成（点，1.0 = +1%）。攻速只能走属性修正，所以单独挂一个 source，
## ⚠ 不能并进 "rogue" —— rebuild() 每拿一张卡就整组重写 "rogue"，并进去会被抹掉。
static func _refresh_hunt_mods() -> void:
	if not active:
		CharacterData.clear_attribute_mod("rogue_hunt")
		return
	var pct := stat("hunt_aspd_per") * float(hunt_stacks)
	if pct <= 0.0:
		CharacterData.clear_attribute_mod("rogue_hunt")
		return
	if hunt_is_full() and has_flag("hunt_full_bloom"):
		pct *= 2.0
	CharacterData.set_attribute_mod("rogue_hunt", {"attack_speed": {"flat": pct}})


# ===================== 杀意（通用「嗜杀」）=====================

## 杀意上限：「嗜杀」的 stat 给 12，没拿卡时为 0（不产生层数）
static func kill_mark_cap() -> int:
	return maxi(0, int(stat("killmark_cap")))


static func add_kill_mark(n: int = 1) -> void:
	var cap := kill_mark_cap()
	if not active or cap <= 0 or n <= 0:
		return
	kill_marks = clampi(kill_marks + n, 0, cap)


## 杀意增伤（点）：每层 killmark_per，层数为 0 时整段跳过
static func kill_mark_dmg_pct() -> float:
	if not active or kill_marks <= 0:
		return 0.0
	return stat("killmark_per") * float(kill_marks)


## 受伤时掉一半（向下取整）：滚雪球被打断，但不至于一层不剩
static func drop_kill_mark_half() -> void:
	if not active or kill_marks <= 0:
		return
	kill_marks = int(float(kill_marks) * 0.5)


# ===================== 清波结算 =====================

## 每清空一波的增益触发点（回响 / 剑冢）。返回提示文本，交给 HUD 飘字。
## ⚠ 只由 RogueArena 在「小怪波真的清空」时调用；BOSS 关与三选一都不走这里。
static func on_wave_clear(player: Node) -> String:
	if not active:
		return ""
	var tips: Array = []
	# 回响：随机一门冷却中的功法立刻转好（没有冷却中的就什么也不发生）
	if has_flag("wave_echo") and player != null and is_instance_valid(player):
		var raw_cd = player.get("skill_cooldowns")
		if raw_cd is Dictionary:
			var cds: Dictionary = raw_cd
			var cooling: Array = []
			for k in cds.keys():
				if float(cds[k]) > 0.0:
					cooling.append(k)
			if not cooling.is_empty():
				var pick := String(cooling[randi() % cooling.size()])
				cds[pick] = 0.0
				tips.append("回响 · %s" % SkillDB.get_skill_name(pick))
	# 剑冢：清波得剑意（只有剑修有这套资源，其它流派 _gain_sword_intent 不存在）
	var seeds := int(stat("intent_on_wave"))
	if seeds > 0 and player != null and is_instance_valid(player) \
			and player.has_method("_gain_sword_intent"):
		player.call("_gain_sword_intent", seeds)
		tips.append("剑冢 · 剑意 +%d" % seeds)
	return "　".join(PackedStringArray(tips))


# ===================== 派生查询 =====================

## 资源上限 = 基值 + 本局增益
static func cap(key: String) -> int:
	var base := int(RogueDB.CAP_BASE.get(key, 0))
	return maxi(1, base + int(cap_bonus.get(key, 0)))


static func stat(key: String) -> float:
	return float(stats.get(key, 0.0))


## 本局可复活次数 = 基值 +「不灭」（传说卡 g_revive）。每次现算，所以中途选到也立刻多一条命
static func revive_total() -> int:
	return RogueDB.REVIVE_PER_RUN + int(round(stat("revive_plus")))


## 还剩几条命可复
static func revive_left() -> int:
	return maxi(0, revive_total() - revives_used)


static func has_flag(key: String) -> bool:
	return bool(flags.get(key, false))


static func has_form_mods() -> bool:
	return active and not form_mods.is_empty()


## 把招式覆盖乘进 resolve_player 的结果（MoveDB 调用，只在本模式生效）
static func apply_form_mods(form_id: String, out: Dictionary) -> void:
	if not active:
		return
	var table: Dictionary = form_mods.get(form_id, {})
	# 剑意上限提上去之后，一剑开天的「展示口径」也要跟着改，否则技能面板还写满 5 层
	if out.has("intent_full_at"):
		out["intent_full_at"] = cap("sword_intent_max")
	if table.is_empty():
		return
	for key in table.keys():
		var k := String(key)
		if k.begins_with("+"):
			# 加算（蓄力上限 / 激活处数这类「+N」）
			var add_field := k.substr(1)
			if out.has(add_field):
				out[add_field] = float(out[add_field]) + float(table[key])
		elif out.has(k):
			out[k] = float(out[k]) * float(table[key])


# ===================== 伤害乘区 =====================

## 全局乘区：普攻 / 功法 / 投射物都走这里（player 侧的剑意乘区另算）
## ⚠ 只在「打敌人」这条路上调；玩家受击不走本函数。
static func modify_outgoing(dmg: float, target: Node, kind: String, _skill_id: String) -> float:
	if not active or dmg <= 0.0:
		return dmg
	var out := dmg
	if kind.begins_with("physical"):
		out *= 1.0 + stat("phys_dmg_pct") / 100.0
	else:
		out *= 1.0 + stat("spell_dmg_pct") / 100.0
	# 破釜：用一格精力上限换来的全局乘区（所有伤害类型都吃）
	out *= 1.0 + stat("all_dmg_pct") / 100.0
	# 嗜杀：击杀滚雪球（层数为 0 时整段跳过）
	var marks := kill_mark_dmg_pct()
	if marks > 0.0:
		out *= 1.0 + marks / 100.0
	if target != null and is_instance_valid(target):
		var hp := float(target.get("current_hp")) if "current_hp" in target else -1.0
		var max_hp := float(target.get("max_hp")) if "max_hp" in target else -1.0
		if hp >= 0.0 and max_hp > 0.0:
			var ratio := hp / max_hp
			if ratio >= 0.999:
				out *= 1.0 + stat("dmg_vs_full") / 100.0
			if ratio <= 0.30:
				out *= 1.0 + stat("dmg_vs_low") / 100.0
	# 虎煞：击杀滚雪球（层数为 0 时整段跳过，主模式永远走不到这里）
	var hunt := hunt_dmg_pct()
	if hunt > 0.0:
		out *= 1.0 + hunt / 100.0
	return out


# ===================== 三选一 =====================

## 已解锁流派（按历史最高层判定）
static func unlocked_families() -> Array:
	var best := CharacterData.rogue_best_floor
	var out: Array = []
	for fam in RogueDB.POOLS.keys():
		var key := String(fam)
		if not RogueDB.FAMILY_UNLOCK_FLOOR.has(key):
			continue
		if int(RogueDB.FAMILY_UNLOCK_FLOOR[key]) <= best:
			out.append(key)
	return out


## 本局实际进池的流派：通用 + 本局所选
## ⚠ 不用 unlocked_families() 全开：刀修卡对剑修局是「死卡」（局内没有刀痕招式可加强），
##   全开会把三选一污染成两张废卡。以后要跨流派混搭，得先有「局内学功法」的卡。
static func active_families() -> Array:
	var out: Array = ["generic"]
	if RogueDB.POOLS.has(family):
		out.append(family)
	return out


## 通用池传说档（不灭 / 洗髓）解锁门禁（设计案 §9.2，2026-11-08 补）。
## ⚠ 只拦「通用池 + 传说」，各流派自己的传说卡与普通 / 稀有都不受影响。
## ⚠ 这条规则以前只写在设计案里，roll_choices 没判层数 → 第 1 层就能抽到不灭 / 洗髓。
##   单独抽成函数是为了让探针能直接断言规则，同时再验真实抽卡入口确实调了它。
static func legend_pool_open(fam: String, rarity: String, at_floor: int) -> bool:
	if fam != "generic" or rarity != RogueDB.RARITY_LEGEND:
		return true
	return at_floor >= RogueDB.GENERIC_LEGEND_FLOOR


## 三选一过滤：符方只在「没满档」时出现，改符只在「已有该符且还没选过变体」时出现。
## need_flag：前置机制门禁（连携深度卡挂 tal_chain_on —— 没解锁连携前不进池，防废卡）。
## ⚠ 不加这一层就会抽到废卡：玩家还没有凝霜符，却看到「改符·冰封」；
##   或者还没选「连携」，却看到「双符」这种选了没效果的卡。
static func _buff_available(def: Dictionary) -> bool:
	var need_flag := String(def.get("need_flag", ""))
	if need_flag != "" and not has_flag(need_flag):
		return false
	var recipe := String(def.get("recipe", ""))
	if recipe != "":
		if not tal_tier.has(recipe):
			return true
		return int(tal_tier[recipe]) < TalismanDB.QUALITY_MULT.size() - 1
	var variant := String(def.get("variant", ""))
	if variant != "":
		var base := String(def.get("base", ""))
		if base == "" or not tal_tier.has(base):
			return false
		return not tal_variant.has(base)
	return true


## 抽取 count 张不重复、未叠满的增益
## force_rare = true 时保证至少一张稀有及以上（BOSS 关后）
static func roll_choices(count: int, force_rare: bool) -> Array:
	var pool: Array = []
	for fam in active_families():
		var fam_key := String(fam)
		for raw in RogueDB.POOLS[fam_key]:
			var def: Dictionary = raw
			var id := String(def.get("id", ""))
			if id == "":
				continue
			if int(buffs.get(id, 0)) >= RogueDB.stack_cap(id):
				continue
			if not _buff_available(def):
				continue
			if not legend_pool_open(fam_key, String(def.get("rarity", "")), floor_no):
				continue
			pool.append(def)
	if pool.is_empty():
		return []

	var out: Array = []
	var remaining := pool.duplicate()
	if force_rare:
		var rare_pool: Array = []
		for raw in remaining:
			if String((raw as Dictionary).get("rarity", "")) != RogueDB.RARITY_COMMON:
				rare_pool.append(raw)
		if not rare_pool.is_empty():
			var pick: Dictionary = _weighted_pick(rare_pool)
			out.append(pick)
			remaining.erase(pick)

	while out.size() < count and not remaining.is_empty():
		var pick: Dictionary = _weighted_pick(remaining)
		out.append(pick)
		remaining.erase(pick)
	return out


static func _weighted_pick(pool: Array) -> Dictionary:
	var total := 0.0
	for raw in pool:
		total += RogueDB.rarity_weight(String((raw as Dictionary).get("rarity", "")))
	var roll := randf() * maxf(total, 0.0001)
	var acc := 0.0
	for raw in pool:
		var def: Dictionary = raw
		acc += RogueDB.rarity_weight(String(def.get("rarity", "")))
		if roll <= acc:
			return def
	return pool[pool.size() - 1]


# ===================== 每层开始 =====================

## 洗髓：每层开始回满血、清空负面。返回是否真的生效（给 HUD 提示用）
static func on_floor_start(player: Node) -> bool:
	if not active or not has_flag("floor_cleanse"):
		return false
	if player == null or not is_instance_valid(player):
		return false
	if player.has_method("rogue_full_restore"):
		player.call("rogue_full_restore")
		return true
	return false
