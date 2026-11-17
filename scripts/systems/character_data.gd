extends Node
## 角色持久数据（唯一数据源）
## 字段严格对齐任务书 §5.1 角色数据 / §5.2 装备数据 / §5.4 功法数据
## 阶段2 各系统（A境界 B装备 E功法 F炼丹 G制符 H记忆）共用本文件
##
## 本文件只定义「数据结构 + 开局初始值」，不实现任何养成逻辑。
## 开局状态依任务书 §2.9：零功法；§6.1：主角开局修为归零、能力后天获取。

# ===== §5.1 角色数据 =====
var character_id: String = "li_qingyun"
var character_name: String = "李青云"
var current_realm: String = "练气"
var realm_stage: int = 0                     # 当前小阶段：0 前期 / 1 中期 / 2 后期；化神固定 0
## 当前小阶段已积累的修为点数（2026-10-24 用户定：改为整数，不再用 0~1 百分比）
var realm_exp: int = 0
var original_world_max_realm: String = "元婴"  # 原始位面境界上限（§2.5）
var current_world_realm_limit: String = "化神" # 当前允许突破到的最高境界：最多化神
## 九天门（幽冥灵墟中心、镇墟石犼身后）是否已被打开过。
## 开了 = 化神突破已完成、九天之上永久可进；这个位必须存档，否则玩家回档会被踢回落后期。
var huashen_gate_opened: bool = false
var cultivation_state: Dictionary = {}       # 修炼状态（阶段2-A 填充）
var memory_state: Dictionary = {}            # 记忆状态（阶段2-H 填充）
var unlocked_abilities: Array = []           # 已解锁能力
var learned_skills: Array = []               # 已习得功法 id（§2.9：开局为空）
## 新获得但还没在功法库里展开看过详情的功法：主城右上角 Y 的红圈靠它显隐
var new_skill_ids: Array = []
var active_skill_loadout: Array = []         # 主动功法携带
var passive_skill_loadout: Array = []        # 被动功法携带（2026-10-30 起最多 1 门）
## 日冕（离照）当前对玩家**所有伤害**的乘区；由 player 持种/丢种时设置，不进存档。
var sun_damage_mult: float = 1.0
## 试炼之路「从零开始」互斥锁：本局进行中禁止换装 / 突破。进出局由 `RogueRun` 置位，不进存档。
## ⚠ 这里刻意只用一个 bool，**不引用 RogueRun** —— RogueRun 已经引用 CharacterData，
##   双向引用会在解析期成环（症状是整包 class 解析失败、一堆 Cannot infer）。
var rogue_lock: bool = false

# ===== 境界顺序（§2.5 固定，不得增删）=====
## 2026-10-23 用户定：第三阶改名「金丹」→「结丹」。
## 旧存档里的「金丹」由 SaveManager 读档时迁移（见 LEGACY_REALM_ALIAS）。
const REALM_ORDER: Array[String] = ["练气", "筑基", "结丹", "元婴", "化神"]
## 每个大境界内部的小阶段（2026-10-24 用户定）：前期 → 中期 → 后期。
## 2026-11-01 用户定：化神不再分小阶段，进入化神后直接封顶 99,999 修为。
const REALM_STAGES: Array[String] = ["前期", "中期", "后期"]
const REALM_HUASHEN := "化神"
const HUASHEN_EXP_CAP := 99999
## 每突破一次，下一个阶段所需修为 +1,000；练气前期从 1,000 起。
const STAGE_EXP_BASE := 1000
const STAGE_EXP_STEP := 1000
## 小阶段突破 / 大境界突破的属性增幅（只作用于下面这六项本体基础值）
const REALM_MINOR_GAIN := 0.1
const REALM_MAJOR_GAIN := 0.5
## 小阶段突破 / 大境界突破的灵力回复增量（加法，不参与百分比成长）
const REALM_MINOR_MANA_REGEN := 0.1
const REALM_MAJOR_MANA_REGEN := 0.3
## 随境界成长的本体基础属性：力量 / 法强 / 物抗 / 法抗 / 气血 / 灵力
const REALM_GROWTH_ATTRS: Array[String] = [
	AttributeDB.ATTR_STRENGTH,
	AttributeDB.ATTR_SPELL_POWER,
	AttributeDB.ATTR_PHYSICAL_RESIST,
	AttributeDB.ATTR_MAGIC_RESIST,
	AttributeDB.ATTR_HP_MAX,
	AttributeDB.ATTR_MANA_MAX,
]
## 旧境界名 → 当前境界名（只用于读档迁移，不要在玩法逻辑里引用）
const LEGACY_REALM_ALIAS: Dictionary = {
	"金丹": "结丹",
}

## 把旧存档里的境界名规范化成当前名字（不在表里的原样返回）
static func normalize_realm_name(realm: String) -> String:
	return String(LEGACY_REALM_ALIAS.get(realm, realm))

# ===== §5.4 功法分类 =====
const SKILL_TYPE_ACTIVE: String = "active"    # 主动功法
const SKILL_TYPE_PASSIVE: String = "passive"  # 被动功法
## 主动功法固定 4 槽，允许空槽（Q/E/R/T 可任意指派，不再要求从左往右填满）
const MAX_ACTIVE_SKILLS: int = 4
## 2026-10-30 用户定：被动功法只能带 1 门（功法库 / 旧存档迁移共用）
const MAX_PASSIVE_SKILLS: int = 1

# ===== §5.2 装备槽位 =====
## 6 个装备槽：武器 / 护甲 / 鞋子 / 饰品 ×3
## 槽位 id 是**具体槽**（accessory_1..3），装备条目的 equipment_type 是**类别**（accessory）。
## 两者靠 SLOT_TYPE / slots_for_type() 对应 —— 不要把 etype 直接当 slot 用。
var equipment_slots: Dictionary = {
	"weapon": null,
	"armor": null,
	"shoes": null,
	"accessory_1": null,
	"accessory_2": null,
	"accessory_3": null,
}
const SLOT_ORDER: Array[String] = [
	"weapon", "armor", "shoes", "accessory_1", "accessory_2", "accessory_3",
]
const SLOT_DISPLAY: Dictionary = {
	"weapon": "武器",
	"armor": "护甲",
	"shoes": "鞋子",
	"accessory_1": "饰品一",
	"accessory_2": "饰品二",
	"accessory_3": "饰品三",
	# 法宝并入装备后仍有 3 个独立槽位；缺这几项时穿戴区会直接显示英文键名 treasure_1…
	"treasure_1": "法宝一",
	"treasure_2": "法宝二",
	"treasure_3": "法宝三",
}
## 槽位 → 装备类别
const SLOT_TYPE: Dictionary = {
	"weapon": "weapon",
	"armor": "armor",
	"shoes": "shoes",
	"accessory_1": "accessory",
	"accessory_2": "accessory",
	"accessory_3": "accessory",
}
## 装备类别 → 显示名（用于「部位」文案与错位提示）
const EQUIP_TYPE_DISPLAY: Dictionary = {
	"weapon": "武器",
	"armor": "护甲",
	"shoes": "鞋子",
	"accessory": "饰品",
	"treasure": "法宝",
}
## 旧存档装备类别别名（2026-10-19）
## ⚠ 背景：清风鞋模板早期把 equipment_type 误写成 "boots"，而项目的类别键是 "shoes"
##   （见 SLOT_TYPE）。只修模板救不了**旧存档 JSON**——读档时错误值被原样带回，
##   first_free_slot("boots") 找不到槽位 → 表现为「清风鞋穿不上」。
##   以后改任何类别键，都必须在这里加一条别名 + 保证 migrate_legacy_equip_types() 跑掉。
const LEGACY_EQUIP_TYPE_ALIAS: Dictionary = {
	"boots": "shoes",
}

## 把旧类别名规范化成当前类别键（不在表里的原样返回）
static func normalize_equip_type(etype: String) -> String:
	return String(LEGACY_EQUIP_TYPE_ALIAS.get(etype, etype))

# ===== 佩戴槽位（装备 6 + 法宝 3，**统一管理**）=====
## 用户 2026-10-17 定：法宝不再独立于装备体系 ——
##   法宝能进背包、能在装备佩戴区显示、能吃强化、有品阶（只是没有「凡品」档）。
## 数据上仍分两个字典存（存档结构不变），但**读写一律走统一接口**：
##   get_equipped / equip / unequip / equip_from_inventory / unequip_to_inventory
## 这些接口内部按槽位名自动路由到 equipment_slots 或 treasure_slots。
var treasure_slots: Dictionary = {
	"treasure_1": null,
	"treasure_2": null,
	"treasure_3": null,
}
const TREASURE_SLOT_ORDER: Array[String] = ["treasure_1", "treasure_2", "treasure_3"]
const TREASURE_SLOT_DISPLAY: Dictionary = {
	"treasure_1": "法宝一",
	"treasure_2": "法宝二",
	"treasure_3": "法宝三",
}

## 全部 9 个佩戴槽（装备面板按这个顺序渲染，法宝排在最后三行）
const WORN_SLOT_ORDER: Array[String] = [
	"weapon", "armor", "shoes", "accessory_1", "accessory_2", "accessory_3",
	"treasure_1", "treasure_2", "treasure_3",
]


## 槽位属于哪本字典（法宝槽 → treasure_slots，其余 → equipment_slots）
static func _slot_table_of(slot: String) -> String:
	return "treasure" if slot.begins_with("treasure_") else "equipment"

# 品阶（§2.6.1 固定，不得增删）
## 品阶（用户 2026-10-17 定）：**7 档**，凡品最低
## ⚠ 法宝没有「凡品」这一档，法宝模板最低就是「法器」——
##   品阶表本身共用，只是法宝不会停在凡品（见 ItemDB.TREASURE_TEMPLATES）。
const EQUIPMENT_GRADES: Array[String] = ["凡品", "法器", "灵器", "宝器", "道器", "仙器", "神器/先天至宝"]

# ===== 属性：基础值 + 聚合 =====
## 玩家**裸装**基础属性。装备 / 法宝 / buff 都在这之上叠加。
## ⚠ 「攻击力」不是属性 —— 它由力量换算而来（见 physical_attack()）。
## 2026-10-24 用户定：练气基础值 = 力量 10 / 法强 10 / 双抗 10 / 气血 100 / 灵力 50
const BASE_ATTRIBUTE_DEFAULTS: Dictionary = {
	AttributeDB.ATTR_HP_MAX: 100.0,
	AttributeDB.ATTR_SPEED: 220.0,
	AttributeDB.ATTR_STRENGTH: 10.0,
	AttributeDB.ATTR_SPELL_POWER: 10.0,
	AttributeDB.ATTR_ATTACK_SPEED: 0.0,
	AttributeDB.ATTR_PHYSICAL_RESIST: 10.0,
	AttributeDB.ATTR_MAGIC_RESIST: 10.0,
	"resist_metal": 0.0,
	"resist_wood": 0.0,
	"resist_water": 0.0,
	"resist_fire": 0.0,
	"resist_earth": 0.0,
	"resist_wind": 0.0,
	"resist_thunder": 0.0,
	"resist_dark": 0.0,
	AttributeDB.ATTR_MANA_MAX: 50.0,
	## 基础回蓝速度（每秒）：2026-10-19 6.0 → 3.0；2026-10-31 用户定「所有灵力恢复砍到十分之一」3.0 → 0.3
	AttributeDB.ATTR_MANA_REGEN: 0.3,
	AttributeDB.ATTR_STAMINA_MAX: 5.0,
	AttributeDB.ATTR_STAMINA_REGEN: 0.25,
}
var base_attributes: Dictionary = BASE_ATTRIBUTE_DEFAULTS.duplicate(true)

## 临时属性修正（buff / debuff）
## 结构：{ 来源key: { attr_id: {"flat": 加值, "mult": 倍率} } }
## 同一来源的修正可一次性清除 —— 便于 buff 到期时整体移除
var attribute_mods: Dictionary = {}

# ===== 肉鸽爬塔「试炼之路」元进度（2026-11-08）=====
## 这三项是**唯一**写入永久存档的肉鸽数据；其余局内状态全在 RogueRun 里，退出即还原。
## 历史最高层：决定流派解锁与面板显示（死亡也计入，不要求一次爬到）
var rogue_best_floor: int = 0
## 累计局数（结算面板显示用）
var rogue_runs: int = 0

# ===== 新手指引（2026-11-10）=====
## 只存「哪些步骤做过了 / 哪些东西看过了」，步骤内容在 TutorialDB 里。
## { "done": {step_id: true}, "seen_items": int, "seen_codex": int, "legacy": bool }
## ⚠ 不要加进 SaveManager.is_blank_run 的进度键：只走了两步引导的空档会被当成「有进度」
var tutorial_data: Dictionary = {}
## 顺序任务面板进度（2026-11-11）：{ done: { quest_id: true } }，由 Quest autoload 读写
var quest_data: Dictionary = {}

## 力量 → 物理攻击力 的换算系数
const STRENGTH_TO_ATTACK := 1.0
## 法强 → 法术攻击力 的换算系数
const SPELL_POWER_TO_ATTACK := 1.0

# ===== 随身背包：四类分背包（2026-11-02 用户定）=====
## 背包**仍然是一个数组** —— 所有按索引读写的 API（remove_item_at / _inventory_index_of /
## take_for_forge / 拖拽）都不用改，只把「容量」从总格数改成**按分背包分别计**：
## 丹药 / 材料 / 装备 / 法宝 各 100 格，互不占用。
## ⚠ 法宝不是独立 type：它是 type=="equipment" 且 equipment_type=="treasure"，
##   所以分类必须走 bag_category_of()，不能直接拿 type 比。
const BAG_CAP_PILL: int = 100
const BAG_CAP_MATERIAL: int = 100
const BAG_CAP_EQUIPMENT: int = 100
const BAG_CAP_TREASURE: int = 100
var inventory: Array = []
## 符匣库存：{ 符箓 item_id: 张数 }。符箓不占背包格，只在符匣里查看 / 装配。
var talisman_stock: Dictionary = {}

# 背包物品类型
const ITEM_PILL: String = "pill"          # 丹药（§2.10）
const ITEM_TALISMAN: String = "talisman"  # 符箓（§2.11）
const ITEM_MATERIAL: String = "material"  # 材料
const ITEM_EQUIPMENT: String = "equipment" # 装备（§2.6）
const ITEM_TREASURE: String = "treasure"   # 分背包「法宝」的类别键（存档里法宝的 type 仍是 equipment）
const ITEM_TYPE_DISPLAY: Dictionary = {
	"pill": "丹药",
	"talisman": "符箓",
	"material": "材料",
	"equipment": "装备",
	"treasure": "法宝",
}
## 背包上从左到右的分背包（符箓走符匣，不在此列）
const BAG_CATEGORIES: Array[String] = [ITEM_PILL, ITEM_MATERIAL, ITEM_EQUIPMENT, ITEM_TREASURE]


## 物品属于哪个分背包
static func bag_category_of(item: Dictionary) -> String:
	if String(item.get("type", "")) == ITEM_EQUIPMENT \
			and String(item.get("equipment_type", "")) == "treasure":
		return ITEM_TREASURE
	return String(item.get("type", ""))


static func bag_cap_for(cat: String) -> int:
	match cat:
		ITEM_PILL:
			return BAG_CAP_PILL
		ITEM_MATERIAL:
			return BAG_CAP_MATERIAL
		ITEM_EQUIPMENT:
			return BAG_CAP_EQUIPMENT
		ITEM_TREASURE:
			return BAG_CAP_TREASURE
	return BAG_CAP_MATERIAL


static func bag_cap_of_item(item: Dictionary) -> int:
	return bag_cap_for(bag_category_of(item))


## 某个分背包当前占了多少格（一格 = 一条堆叠；装备/法宝天然一条一件）
func bag_count_for(cat: String) -> int:
	var n := 0
	for it in inventory:
		if bag_category_of(it as Dictionary) == cat:
			n += 1
	return n


## 还能不能塞下：能堆到现有格子上就一定放得下，否则看该类有没有空位
func bag_has_room(item: Dictionary, amount: int = 1) -> bool:
	if item.is_empty():
		return false
	if _find_stackable(item) >= 0:
		return true
	return bag_count_for(bag_category_of(item)) + amount <= bag_cap_of_item(item)


# ===== 仓库（2026-11-02 用户定：独立存储空间，不再和背包混在一起）=====
## 仓库和背包一样是「一个数组 + 按分背包类别算容量」，每类上限 500 格。
## ⚠ 只有背包里的东西能被使用：炼丹 / 制符 / 锻造投料、战斗轮盘丹药、
##   破境材料判定全都只读 inventory —— 所以 count_item / count_material /
##   has_materials 一律**不**把仓库算进去，这是规则而不是遗漏。
## 符箓照旧进符匣（talisman_stock），既不占背包也不进仓库。
const WAREHOUSE_CAP_PER_CATEGORY: int = 500
var warehouse: Array = []

## ===== 背包「首次获得」红点（2026-11-12 用户定）=====
## bag_seen_ids：已经拿到过、也看过的 id（永久）；bag_new_ids：第一次进背包、还没点开看过的 id。
## ⚠ 不复用图鉴：图鉴不收丹药，且图鉴只记「获得过」，分不出「还没看过」。
var bag_seen_ids: Dictionary = {}
var bag_new_ids: Dictionary = {}


## 某样东西第一次进背包 → 记一笔红点（重复获得不再亮）
func mark_bag_new(item_id: String) -> void:
	if item_id == "" or bag_seen_ids.has(item_id) or bag_new_ids.has(item_id):
		return
	bag_new_ids[item_id] = true


func is_bag_new(item_id: String) -> bool:
	return bag_new_ids.has(item_id)


## 玩家在背包里点开了它的详情 = 看过了：红点永远熄灭（同一 id 一辈子只亮这一次）
func clear_bag_new(item_id: String) -> void:
	if not bag_new_ids.has(item_id):
		return
	bag_new_ids.erase(item_id)
	bag_seen_ids[item_id] = true


## 仓库里某个分背包占了多少格
func warehouse_count_for(cat: String) -> int:
	var n := 0
	for it in warehouse:
		if bag_category_of(it as Dictionary) == cat:
			n += 1
	return n


## 仓库放不放得下：能堆到已有格子上就一定放得下
func warehouse_has_room(item: Dictionary) -> bool:
	if item.is_empty():
		return false
	if _warehouse_stack_index(item) >= 0:
		return true
	return warehouse_count_for(bag_category_of(item)) + 1 <= WAREHOUSE_CAP_PER_CATEGORY


## 找到可堆叠的同款（丹药 / 材料按 id + type 合堆；装备法宝永远单独占格）
func _warehouse_stack_index(item: Dictionary) -> int:
	if String(item.get("type", "")) == ITEM_EQUIPMENT:
		return -1
	var iid := String(item.get("id", ""))
	for i in warehouse.size():
		var w: Dictionary = warehouse[i]
		if String(w.get("id", "")) == iid and String(w.get("type", "")) == String(item.get("type", "")):
			return i
	return -1


## 拾取/发放的统一落点（2026-11-12 用户定）：**先背包（能叠就叠），再仓库**，两边都放不下才算失败。
## 返回 1 = 进背包，2 = 进仓库，0 = 两边都放不下。
## ⚠ 「背包满了但里面有晶石」必须还能捡：`add_item` 会先找同 id 的堆，满格也能叠上去。
func add_item_or_warehouse(item: Dictionary) -> int:
	if add_item(item):
		return 1
	if not warehouse_has_room(item):
		return 0
	var copy: Dictionary = item.duplicate(true)
	var stack := _warehouse_stack_index(copy)
	if stack >= 0:
		warehouse[stack]["count"] = int(warehouse[stack].get("count", 1)) + int(copy.get("count", 1))
	else:
		warehouse.append(copy)
	mark_codex_from_item(item)
	return 2


## 背包 → 仓库。放不下 / 符箓 / 越界都拒绝，物品原地不动
func store_to_warehouse(index: int) -> Dictionary:
	if index < 0 or index >= inventory.size():
		return {"ok": false, "message": "这件物品已不在背包里。"}
	var item: Dictionary = inventory[index]
	if bag_category_of(item) == ITEM_TALISMAN:
		return {"ok": false, "message": "符箓收在符匣，不进仓库。"}
	if not warehouse_has_room(item):
		return {"ok": false, "message": "仓库「%s」已满 %d 格" % [
			String(ITEM_TYPE_DISPLAY.get(bag_category_of(item), "物品")), WAREHOUSE_CAP_PER_CATEGORY]}
	# 先确认能收下，再从背包摘走，中途不出现「两边都没有」的窗口
	var copy: Dictionary = (item as Dictionary).duplicate(true)
	var stack := _warehouse_stack_index(copy)
	if stack >= 0:
		warehouse[stack]["count"] = int(warehouse[stack].get("count", 1)) + int(copy.get("count", 1))
	else:
		warehouse.append(copy)
	inventory.remove_at(index)
	return {"ok": true, "message": "已存入仓库：%s" % String(copy.get("name", copy.get("id", "")))}


## 仓库 → 背包。背包放不下就原样留在仓库，绝不消失
func take_from_warehouse(index: int) -> Dictionary:
	if index < 0 or index >= warehouse.size():
		return {"ok": false, "message": "仓库里没有这件物品。"}
	var item: Dictionary = warehouse[index]
	if not bag_has_room(item):
		return {"ok": false, "message": bag_full_message(item)}
	if not add_item((item as Dictionary).duplicate(true)):
		# 预检通过却仍失败（并发整理等）→ 原地不动
		return {"ok": false, "message": "背包放不下，先整理背包。"}
	warehouse.remove_at(index)
	return {"ok": true, "message": "已取回：%s" % String(item.get("name", item.get("id", "")))}


## 整类搬运（背包↔仓库），返回搬动格数；逐件走单件接口，遇到满就自然停下
func store_category(cat: String) -> int:
	var moved := 0
	var i := inventory.size() - 1
	while i >= 0:
		if bag_category_of(inventory[i] as Dictionary) == cat:
			if bool(store_to_warehouse(i).get("ok", false)):
				moved += 1
			else:
				break
		i -= 1
	return moved


func take_category(cat: String) -> int:
	var moved := 0
	var i := warehouse.size() - 1
	while i >= 0:
		if bag_category_of(warehouse[i] as Dictionary) == cat:
			if bool(take_from_warehouse(i).get("ok", false)):
				moved += 1
			else:
				break
		i -= 1
	return moved


## 上一次穿戴 / 锻造换位被拒的原因（界面直接显示；空 = 没被拒）
var equip_block_reason: String = ""


## 给玩家看的一句容量提示（哪个分背包满了就说哪个）
func bag_full_message(item: Dictionary) -> String:
	var cat := bag_category_of(item)
	return "%s背包已满（%d 格）—— 先整理或存入仓库" % [
		String(ITEM_TYPE_DISPLAY.get(cat, "背包")), bag_cap_for(cat)]


# ===== 进度与养成状态（任务书 §5.8 存档容器子集）=====
# 各系统的运行时状态，阶段2 正式实现时直接消费这些字段
var origin_energy: float = 0.0            # 万界本源（§2.7：仅真实位面 BOSS 产出）
var boss_progress: Dictionary = {}         # { boss_id: {"killed": bool, "first_kill": bool} }

## 强化必定成功旗标：**只有**新手指引 c5 的强化教学步激活期间为 true
## （tutorial_runner._enter_step 按步骤表 force_success 字段置位/复位）。
## 只影响 enhance_item 的随机数，不改变消耗与进阶逻辑 —— 玩家手动强化永远真随机。
var force_enhance_success: bool = false
## BOSS 连败提醒（2026-10-27 用户定）：{ 计数键: 连续战败次数 }
##   位面 = boss_id；万界塔 = "tower_层号"（同一只 BOSS 的投影与本体各算各的）
##   打赢清零；活着主动撤退也清零；死亡不清（撤退发生在死亡之后时不该抹掉记录）
var boss_fail_streak: Dictionary = {}
## 位面 BOSS 死亡记录（2026-10-31 用户定）：{ "domain_id/boss_id": 累计死亡次数 }
##   塔与演武场不计；首通时把当时的累计次数快照到 boss_first_clear_deaths。
var boss_death_count: Dictionary = {}
var boss_first_clear_deaths: Dictionary = {}
## 万界塔各层最快通关时间（秒）：{ floor:int -> float }
## 仅塔内投影首杀/重复挑战成功时记录，死亡或中途退出不记录。
## 注：位面 BOSS 不再记录通关时间，通关计时只作为塔的挑战成绩。
var tower_best_time: Dictionary = {}
## 万界塔「无伤通关」奖励状态（2026-10-24 用户定）：{ floor:int -> "ready" | "claimed" }
##   ready   = 该层曾全程未掉血通关，50 晶石奖励可领
##   claimed = 已在选关界面领过这 50 颗晶石（每层仅一次）
var tower_no_hit_reward: Dictionary = {}
## 万界塔「无伤通关双倍气血」：{ floor:int -> true }（卡包「纯华彩 · 无背景」解锁）
var tower_no_hit_double: Dictionary = {}
## 大世界核心首领重战（塔内分支节点）：{ region_id:
##   {"clear_count": int, "no_hit_double": bool, "no_hit_rewarded": bool} }
## 与塔层分开存：分支不占层号，但沿用同一套血量成长 / 卡片 / 无伤规则。
var core_replay: Dictionary = {}
## 卡包卡序：{ boss_id: [card_id, ...] }；第一位是收藏册格子的封面
var card_order: Dictionary = {}
## 卡片自走棋用哪一档卡面："" = 跟随卡包封面，其余是 CodexDB 的卡种 id
## （portrait / scene / plain / ink）。是显示偏好不是进度，旧档没有就取 ""。
var match_card_kind: String = ""
## 万界棋坛关卡进度：**已经通关的最高关卡号**（0 = 还没打过，当前关就是第 1 关）。
## 线性推进 ⇒ 已通关的关卡必然是 1..N 连续一段，所以一个 int 就够，不用存集合。
## 旧档没有这个字段 → 0。
var match_level_cleared: int = 0
## 万界棋坛「快速模式」开关（票 001 / ADR-0003）。**默认关**：不拨它就一直走普通模式。
## 是偏好不是进度 ⇒ 不记录"哪一关是快速过的"，旧档没有这个键就按关。
var match_quick_mode: bool = false
## 非普通卡解锁奖励领取记录：{ "boss_id/card_id": true }
## 每张普通卡以外的卡（华彩 / 纯华彩 / 纸本水墨等）首次解锁后可领 50 锻造晶石
var card_reward_claimed: Dictionary = {}
const CARD_UNLOCK_BONUS_CRYSTALS := 50
var domain_progress: Dictionary = {}       # { domain_id: {"unlocked": bool, "cleared_bosses": Array} }
var tower_progress: Dictionary = {}        # { floor:int -> {"unlocked": bool, "first_kill": bool} }

# ===== 万界秘境·大世界（2026-10-23）=====
## 持久世界状态（跨进出、跨存档保留）：
##   core_kills   { region_id: true }                       核心首领是否已被永久击杀
##   nodes        { node_id: {"at": unix秒, "pos": [x,y]} } 药材 / 妖兽 / 灵气团的重生时刻
##   cultivators  { slot_id: {"at": unix秒, "pos": [x,y], "skills": [...], "alive": bool} }
## 只存「何时重生 / 在哪重生」，场上实体本身每次进入时按这份状态重建。
var secret_world: Dictionary = {
	"core_kills": {},
	"nodes": {},
	"cultivators": {},
	## 铸神祭坛阶段（2026-11-13）：node_id → 0 未取 / 1 已取铸神晶 / 2 化神后再取也取完
	"god_altars": {},
}


## 铸神祭坛取到第几阶段（0 / 1 / 2）
func god_altar_stage(node_id: String) -> int:
	var t = secret_world.get("god_altars", {})
	if not (t is Dictionary):
		return 0
	return clampi(int((t as Dictionary).get(node_id, 0)), 0, 2)


func set_god_altar_stage(node_id: String, stage: int) -> void:
	if not (secret_world.get("god_altars") is Dictionary):
		secret_world["god_altars"] = {}
	(secret_world["god_altars"] as Dictionary)[node_id] = clampi(stage, 0, 2)


## 被动槽只有 1 格：旧存档多带的保留第一门，其余卸下
func trim_passive_loadout() -> void:
	if passive_skill_loadout.size() > MAX_PASSIVE_SKILLS:
		passive_skill_loadout = passive_skill_loadout.slice(0, MAX_PASSIVE_SKILLS)


## 某区域的核心首领是否已被永久击杀（塔里的区域首领分支节点用它解锁）
func is_core_killed(region_id: String) -> bool:
	var kills: Dictionary = secret_world.get("core_kills", {})
	return bool(kills.get(region_id, false))

## 已获得过的元魂 id（2026-10-21 用户定：**每种元魂全局只掉一次**）
## 拾取时写入、永久保存在存档里；再次挑战同一 BOSS 不会重复掉落元魂
var obtained_souls: Array = []
## 图鉴永久解锁记录：{ item_id: true }
## 只在物品真正入手（入包 / 穿戴 / 局内拾取 / 必得材料）时写入；丢弃或消耗后仍然保留。
var codex_unlocked: Dictionary = {}

var alchemy_progress: Dictionary = {}      # { recipe_id: {"state": String, "proficiency": float} }
var talisman_crafting_progress: Dictionary = {}
var home_progress: Dictionary = {}         # { plot_index:int -> {"seed_id": String, "planted_at": int, "grow_seconds": int} }
## 已开垦的灵田地块（2026-10-23）：荒田要先用猛虎踏地踏开，才能播种
var tilled_plots: Dictionary = {}          # { plot_index:int -> true }

# ===== 战斗轮盘装配（2026-10-24 用户定）=====
## 三种丹药 + 三种符箓：槽位 id -> 物品 id（空串 = 未装配）
## 槽位固定六个，读档时缺的键补空串，老存档不用迁移。
var quick_slots: Dictionary = {
	"pill_1": "", "pill_2": "", "pill_3": "",
}
var memory_progress: Dictionary = {}       # { fragment_id: {"is_unlocked": bool, "playback_state": String} }
var story_progress: int = 0
var chapter_state: String = "第一篇章 · 未启"
## 开局装备是否已发放（一次性）。
## 首次启动发一把凡品铁剑并自动装备；之后（含读档）不再补发，
## 玩家自己把铁剑卖掉/丢掉也不会被重新塞回来。
var starting_equipment_granted: bool = false

## 开局法宝是否已发放（一次性，逻辑同上）
var starting_treasure_granted: bool = false

# 灵田地块数量（2026-10-23 用户定：九块，打完核心首领后出现在传送门旁）
const PLOT_COUNT: int = 9
# 丹方/符方状态
const RECIPE_UNKNOWN: String = "未领悟"
const RECIPE_KNOWN: String = "已领悟"

# ===== 战斗基础时序（非属性，纯手感常量）=====
## 气血上限 / 精力 / 灵力 / 速度 / 力量 / 法强 等已迁到 base_attributes，
## 这里只保留不随装备成长的战斗节奏参数。
var base_dodge_speed: float = 480.0
var attack_time: float = 0.35
var parry_window: float = 0.22
var dodge_time: float = 0.18
var perfect_dodge_window: float = 0.108
var dodge_cooldown: float = 0.5
var parry_cooldown: float = 0.6


# ===== 境界 =====

func get_realm_index() -> int:
	return REALM_ORDER.find(current_realm)


func get_next_realm() -> String:
	var idx := get_realm_index()
	if idx < 0 or idx + 1 >= REALM_ORDER.size():
		return ""
	return REALM_ORDER[idx + 1]


func is_huashen() -> bool:
	return current_realm == REALM_HUASHEN


## 当前小阶段名（前期 / 中期 / 后期）；化神没有小阶段，返回空串
func get_realm_stage_name() -> String:
	if is_huashen():
		return ""
	return REALM_STAGES[clampi(realm_stage, 0, REALM_STAGES.size() - 1)]


## 下一小阶段名；已在后期 / 化神时返回空串
func get_next_stage_name() -> String:
	if is_huashen() or realm_stage >= REALM_STAGES.size() - 1:
		return ""
	return REALM_STAGES[realm_stage + 1]


## 是否已是本境界的最后一个阶段（后期 / 化神终境）
func is_final_stage() -> bool:
	return is_huashen() or realm_stage >= REALM_STAGES.size() - 1


## 当前小阶段升满所需修为：
##   练气 1000/2000/3000 → 筑基 4000/5000/6000 → 结丹 7000/8000/9000 →
##   元婴 10000/11000/12000；化神单阶段上限 99,999。
func get_stage_exp_required() -> int:
	if is_huashen():
		return HUASHEN_EXP_CAP
	var index := maxi(0, get_realm_index()) * REALM_STAGES.size() \
		+ clampi(realm_stage, 0, REALM_STAGES.size() - 1)
	return STAGE_EXP_BASE + index * STAGE_EXP_STEP


## 当前小阶段修为进度 0.0~1.0（只给进度条用；逻辑判断请用 is_stage_full）
func get_stage_exp_ratio() -> float:
	return clampf(float(realm_exp) / float(maxi(1, get_stage_exp_required())), 0.0, 1.0)


## 本阶段修为是否已满：满了之后吸灵气 / 打怪都不再增加，必须先突破
func is_stage_full() -> bool:
	return realm_exp >= get_stage_exp_required()


## 后期圆满：本境界的修炼到此为止，只能靠大境界突破继续
func is_realm_peak() -> bool:
	return is_final_stage() and is_stage_full()


## 当前修为已满、且有下一步突破可走（HUD / 按钮提醒用）
## 包含「材料还未凑齐」的大突破：先提醒玩家去准备；只排除真正的终点
## （最终境界后期圆满 / 当前位面境界上限，这两种情况点突破也没有意义）。
func has_breakthrough_pending() -> bool:
	if is_huashen() or not is_stage_full():
		return false
	if not is_final_stage():
		return true
	if is_realm_capped():
		return false
	if get_realm_index() >= REALM_ORDER.size() - 1:
		return false
	return true


# ===================== 九天门与化神坛（化神之路）=====================
## 2026-11-02 用户定：化神分两步，两步都在元婴区中心那一处 ——
##   ① 九天门：修为到元婴后期圆满 + 背包里有完整的「化神破境晶」→ 开门进九天之上，
##      开门**不吃材料**（吃了就没法在坛上突破了，也会把玩家卡在门外）。
##   ② 化神坛：进了九天之上再按 F，这时才吃掉化神破境晶、当场突破化神。
## 那颗完整晶本身要熔铸：化神底髓（幽冥灵墟首领镇墟石犼首杀）+ 化神天髓（照影界第三位
##   BOSS 首杀，目前挂在末位执烛）→ 锻造台「熔铸」页合成，见 ItemDB.POJING_SYNTH_RECIPES。
## 境界面板的化神档只指路、不许就地突破：晶在面板里被吃掉的话，这道门就永远开不了。

## 开九天门所需材料（= 化神突破材料，同一张表，口径不分叉）
static func huashen_gate_requirements() -> Dictionary:
	return ItemDB.get_breakthrough_requirements(REALM_HUASHEN)


## 化神材料还差哪一件，按名字列出来（门和坛共用）
func _huashen_missing_text() -> String:
	var req := huashen_gate_requirements()
	var missing: Array[String] = []
	for k in req:
		if count_material(String(k)) < int(req[k]):
			missing.append(String(ItemDB.get_material(String(k)).get("name", String(k))))
	if missing.is_empty():
		return ""
	var rec := ItemDB.get_pojing_synth_recipe(REALM_HUASHEN)
	return "还缺 %s —— 它由「%s」与「%s」在锻造台熔铸合成，分别出自镇墟石犼与照影界第三位 BOSS" % [
		"、".join(missing),
		String(ItemDB.get_material(String(rec.get("di", ""))).get("name", "化神底髓")),
		String(ItemDB.get_material(String(rec.get("tian", ""))).get("name", "化神天髓"))]


## 现在能不能开九天门 / 还差什么。返回 {ok, message}，message 直接给交互提示用。
func huashen_gate_check() -> Dictionary:
	if huashen_gate_opened:
		return {"ok": true, "message": "九天门已开 · F 进入九天之上"}
	if get_realm_index() < REALM_ORDER.find("元婴"):
		return {"ok": false, "message": "修为不足 · 需元婴后期圆满"}
	if current_realm != "元婴" or not is_realm_peak():
		return {"ok": false, "message": "修为不足 · 需元婴后期圆满（当前 %s · %s）"
			% [current_realm, get_realm_stage_name()]}
	var lack := _huashen_missing_text()
	if lack != "":
		return {"ok": false, "message": lack}
	return {"ok": true, "message": "化神破境晶在手 · F 开九天门，进入九天之上"}


## 门前交互条上的一行短提示（长句给按 F 之后的公告条）
func huashen_gate_prompt() -> String:
	if huashen_gate_opened:
		return "F　进入九天之上"
	var c := huashen_gate_check()
	if bool(c.get("ok", false)):
		return "F　开九天门 · 化神破境晶在手"
	return "九天门 · " + String(c.get("message", ""))


## 开九天门：只解锁 + 放行，不吃材料。条件不满足时什么都不做。
func open_huashen_gate() -> bool:
	if huashen_gate_opened:
		return true
	if not bool(huashen_gate_check().get("ok", false)):
		return false
	huashen_gate_opened = true
	return true


## 坛前提示 + 能不能突破
func huashen_altar_check() -> Dictionary:
	if is_huashen():
		return {"ok": false, "message": "已在此突破化神，九天之上常驻"}
	if current_realm != "元婴" or not is_realm_peak():
		return {"ok": false, "message": "需元婴后期圆满方可登坛"}
	var lack := _huashen_missing_text()
	if lack != "":
		return {"ok": false, "message": lack}
	return {"ok": true, "message": "F　登坛突破化神（炼化化神破境晶）"}


## 真正突破：吃掉化神破境晶 → 化神 → 境界上限推到化神。与面板大突破同一收尾。
func perform_huashen_breakthrough() -> bool:
	if rogue_lock:
		return false
	var c := huashen_altar_check()
	if not bool(c.get("ok", false)):
		return false
	if not consume_materials(huashen_gate_requirements()):
		return false
	break_realm(REALM_HUASHEN)
	current_world_realm_limit = REALM_HUASHEN
	return true


## 属性成长倍率：每个大境界 +50%、每个小阶段 +10%，均为**乘算累积**
## 例：筑基中期 = 1.5 × 1.1
func realm_stat_multiplier() -> float:
	var majors := maxi(0, get_realm_index())
	var minors := clampi(realm_stage, 0, REALM_STAGES.size() - 1)
	return pow(1.0 + REALM_MAJOR_GAIN, majors) * pow(1.0 + REALM_MINOR_GAIN, minors)


## 灵力回复的额外加值：大境界 +0.3 / 小阶段 +0.1（加法，不吃百分比成长；2026-10-31 全部 ÷10）
func realm_mana_regen_bonus() -> float:
	var majors := maxi(0, get_realm_index())
	var minors := clampi(realm_stage, 0, REALM_STAGES.size() - 1)
	return majors * REALM_MAJOR_MANA_REGEN + minors * REALM_MINOR_MANA_REGEN


## 当前是否可做「小阶段突破」（前期 / 中期修为满）
func can_break_stage() -> bool:
	return not is_huashen() and is_stage_full() and not is_final_stage()


## 执行小阶段突破：修为清零，进入下一阶段
func break_stage() -> void:
	if rogue_lock:
		return
	if not can_break_stage():
		return
	realm_stage = mini(realm_stage + 1, REALM_STAGES.size() - 1)
	realm_exp = 0


## 执行大境界突破：进入下一境界的前期，修为清零
func break_realm(next_realm: String) -> void:
	if rogue_lock:
		return
	if is_huashen() or next_realm == "" or REALM_ORDER.find(next_realm) < 0:
		return
	current_realm = next_realm
	realm_stage = 0
	realm_exp = 0


## 是否已达到当前位面允许的最高境界
func is_realm_capped() -> bool:
	return current_realm == current_world_realm_limit


## 增加修为（灵气团 / 击杀），返回实际增加量；本阶段已满时返回 0
func add_realm_exp(amount: int) -> int:
	if amount <= 0:
		return 0
	var req := get_stage_exp_required()
	if realm_exp >= req:
		return 0
	var before := realm_exp
	realm_exp = mini(req, realm_exp + amount)
	return realm_exp - before


# ===== 功法：新获得标记 =====

func is_skill_new(skill_id: String) -> bool:
	return skill_id in new_skill_ids


func has_new_skills() -> bool:
	return not new_skill_ids.is_empty()


## 功法入册时调用：标记为「新」，直到玩家在功法库展开详情
func mark_skill_new(skill_id: String) -> void:
	if skill_id == "":
		return
	var skill := SkillDB.get_skill(skill_id)
	# 变体（如满剑意一剑开天）不进功法库，标了也永远清不掉
	if skill.is_empty() or bool(skill.get("is_variant", false)):
		return
	if not (skill_id in new_skill_ids):
		new_skill_ids.append(skill_id)


## 功法库展开详情时调用：清掉这一门的新标记
func mark_skill_seen(skill_id: String) -> void:
	new_skill_ids.erase(skill_id)


# ===== 装备 =====

## 读取任意佩戴槽（装备 6 槽 + 法宝 3 槽，统一入口）
func get_equipped(slot: String) -> Dictionary:
	if _slot_table_of(slot) == "treasure":
		var t = treasure_slots.get(slot)
		return t if t is Dictionary else {}
	var item = equipment_slots.get(slot)
	return item if item is Dictionary else {}


## 是否佩戴着某个模板的装备（六槽都算；空槽与法宝不参与）。
## 装备的「用途差」效果在 player.gd 里读这个 —— 它们改的是打法，不是数值词条。
func is_wearing(template_id: String) -> bool:
	if template_id == "":
		return false
	for slot in SLOT_ORDER:
		var item = equipment_slots.get(slot)
		## 装备实例上的模板键是 "id"（不是 "template_id" —— 那是掉落表条目的键）。
		## 读错键不会报错，只会让 is_wearing 永远返回假，两件装备的用途差就此全哑。
		if item is Dictionary and String((item as Dictionary).get("id", "")) == template_id:
			return true
	return false


func equip(slot: String, item: Dictionary) -> void:
	var is_treasure := _slot_table_of(slot) == "treasure"
	var table: Dictionary = treasure_slots if is_treasure else equipment_slots
	if not table.has(slot):
		push_warning("未知装备槽位: " + slot)
		return
	if item.is_empty():
		table[slot] = null
		return
	# ---- 同种装备唯一性（法宝 2026-10-22 / 饰品 2026-10-31 用户定）----
	# 「相同」按**模板 id** 判定：同一种装备的强化等级/磨损不同也算同一种，不能各占一个槽。
	# 只对多槽类别生效（饰品 3 槽 / 法宝 3 槽）；武器护甲鞋各只有一槽，天然不会重复。
	# ⚠ 这里是**最后一道防线**（UI 拖放 / equip_from_inventory / equip_treasure 都会先拦一次），
	#   留着是为了防未来新代码绕过。命中时**不改任何状态**：不穿、也不从背包移除。
	var dup := equip_dup_slot(item, slot)
	if dup != "":
		push_warning("同种%s已在【%s】，不能重复佩戴：%s" % [
			String(EQUIP_TYPE_DISPLAY.get(String(item.get("equipment_type", "")), "装备")),
			slot_display_name(dup), String(item.get("name", ""))])
		return
	# ---- 唯一性防线（2026-10-17）----
	# 背景：锻造台曾直接调 equip() 穿戴（只放进槽位、没从背包移除），
	# 于是同一个对象同时存在于背包与穿戴槽，之后上砧 / 取下就会「一物变两件」。
	# 现在 equip() 自身也兜一道底，避免任何新代码再犯同样的错。
	if _inventory_index_of_same(item) >= 0:
		inventory.remove_at(_inventory_index_of_same(item))
	var held := _slot_holding(item)
	if held != "" and held != slot:
		_set_slot(held, {})
	table[slot] = item
	mark_codex_from_item(item)
	# 新手指引：穿戴类步骤（锻造台 / 背包都走这里）
	var tut := get_node_or_null("/root/Tutorial")
	if tut != null:
		tut.note("gear_equipped")


## 清空某个佩戴槽（不负责放回背包；需要入包请用 unequip_to_inventory）
func unequip(slot: String) -> Dictionary:
	var old := get_equipped(slot)
	_set_slot(slot, {})
	return old


## 直接写某个槽位（内部用；统一处理两本字典）
func _set_slot(slot: String, item: Dictionary) -> void:
	if _slot_table_of(slot) == "treasure":
		treasure_slots[slot] = null if item.is_empty() else item
	else:
		equipment_slots[slot] = null if item.is_empty() else item


## 发放开局自带装备（一次性）
##
## 幂等：靠 starting_equipment_granted 标记保证只发一次。
## 首次启动 → 发凡品铁剑并直接装备到兵器槽（开局就有武器用）；
## 之后（含读档已有存档）不再补发，玩家自己处理掉铁剑也不会被塞回来。
## 返回本次实际发放的装备名列表（已发过则返回空数组）
func ensure_starting_equipment() -> Array:
	var granted: Array = []
	if starting_equipment_granted:
		return granted
	starting_equipment_granted = true

	for tpl in ItemDB.get_starting_equipment():
		var item := make_equipment_instance(tpl)
		var etype := String(item.get("equipment_type", ""))
		# 该类槽位还有空位就直接穿上（开局一把武器在手），否则放进背包
		var slot := first_free_slot(etype)
		if slot != "" and get_equipped(slot).is_empty():
			equip(slot, item)
		else:
			add_item(item)
		granted.append(String(item.get("name", "")))
	return granted


# ===== 装备实例化 / 穿戴 / 攻击力 =====

## 由装备模板生成一件「可入背包的装备实例」（独立字典，改它不会污染模板）
## attack_bonus_base 存装备自身的基础攻击力（模板值，当前模板均为 0）。
## ⚠ 2026-10-17 起：强化与品阶**不再叠加固定攻击力**，装备强度完全由 attributes 决定。
##   - attributes        最终属性值（强化会直接在这里加）
##   - attributes_base   模板原值（用于 UI 显示「+2」的强化增量，以及分解口径）
##   - enhance_fail_count 累计失败次数（磨损），到 ENHANCE_FAIL_LIMIT 即破损
##   - enhance_success_count 累计强化词条次数（普通成功 +1、大成功 +2，按实际升的强化级数；不含进阶）
##   - enhance_crystal_spent 累计消耗的锻造晶石（分解返还按它算）
##   - is_broken         破损后仍可穿戴，但强化永久停止
func make_equipment_instance(template: Dictionary) -> Dictionary:
	var base := float(template.get("attack_bonus", 0.0))
	var tpl_attrs = template.get("attributes", {})
	var item := {
		"id": String(template.get("equipment_id", "")),
		"name": String(template.get("equipment_name", "未知装备")),
		"type": ITEM_EQUIPMENT,
		"count": 1,
		"icon": String(template.get("icon", "")),
		"desc": String(template.get("desc", "")),
		"equipment_grade": String(template.get("equipment_grade", "")),
		"equipment_type": String(template.get("equipment_type", "")),
		# 武器外观 id（空 = 用默认 player_weapon）；只对 equipment_type == "weapon" 有意义
		"weapon_visual": String(template.get("weapon_visual", "")),
		"equipment_level": int(template.get("equipment_level", 1)),
		"enhancement_level": 0,
		"refinement_state": String(template.get("refinement_state", "未精炼")),
		"enhancement_limit": ItemDB.MAX_ENHANCE,
		"current_realm_limit": String(template.get("current_realm_limit", "")),
		"current_domain": String(template.get("current_domain", "")),
		"is_permanently_owned": bool(template.get("is_permanently_owned", true)),
		"attributes": tpl_attrs.duplicate(true) if tpl_attrs is Dictionary else {},
		"attributes_base": (tpl_attrs.duplicate(true) if tpl_attrs is Dictionary else {}),
		"enhance_fail_count": 0,
		"enhance_ascend_fail_count": 0,
		"enhance_wear_seq": [],
		"enhance_success_count": 0,
		"enhance_crystal_spent": 0,
		"is_broken": false,
		"attack_bonus_base": base,
		"attack_bonus": base,
	}
	item["attack_bonus"] = ItemDB.compute_attack_bonus(item)
	return item


## 由法宝模板生成一件法宝实例
## ⚠ 2026-10-17 用户要求「法宝并入装备体系」：
##   法宝实例和装备实例**结构完全一致**（type = ITEM_EQUIPMENT、equipment_type = "treasure"），
##   所以它天然能进背包、能在装备佩戴区显示、能上锻造台强化、能吃品阶与磨损。
##   品阶口径：法宝**没有「凡品」档**，模板最低就是「法器」。
func make_treasure_instance(template: Dictionary) -> Dictionary:
	var grade := String(template.get("treasure_grade", "法器"))
	# 法宝不允许停在凡品：万一模板写了凡品，抬到法器
	if grade == "凡品" or grade == "":
		grade = "法器"
	## 法宝不带属性词条（2026-11-01 用户定）：实例属性恒为空，成长只走进阶。
	var tpl_attrs: Dictionary = {}
	var item := {
		"id": String(template.get("treasure_id", "")),
		"name": String(template.get("treasure_name", "未知法宝")),
		"type": ITEM_EQUIPMENT,
		"count": 1,
		"icon": String(template.get("icon", "")),
		"desc": String(template.get("desc", "")),
		"equipment_grade": grade,
		"equipment_type": "treasure",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		## 法宝没有普通强化等级，只有进阶（品阶 +1）
		"enhancement_limit": 0,
		"current_realm_limit": "",
		"current_domain": "",
		"is_permanently_owned": true,
		"attributes": {},
		"attributes_base": {},
		"enhance_fail_count": 0,
		"enhance_ascend_fail_count": 0,
		"enhance_wear_seq": [],
		"enhance_success_count": 0,
		"enhance_crystal_spent": 0,
		"is_broken": false,
		"attack_bonus_base": 0.0,
		"attack_bonus": 0.0,
		# 召唤法宝专属：强化成功累计级数（每级给召唤物 +2% 基础气血/攻击，跨进阶保留）
		"summon_boost_count": 0,
		# 召唤法宝专属：合成时熔掉的那件破损装备花过的晶石（分解时按一半返还）
		"synth_crystal_spent": 0,
		# 召唤法宝专属：进阶成功的次数（每次让召唤物多存在 5 秒）
		"summon_duration_bonus": 0,
		# 召唤法宝专属：进阶奖励累计的额外加成百分比（进阶前加成的 50%，含小数）
		"summon_ascend_boost_pct": 0.0,
	}
	return item


## 旧存档迁移：把 treasure_slots 里按老结构（type=treasure）存的法宝
## 补齐成装备实例结构，否则它们无法进背包、无法强化。
## 幂等：已经是新结构的条目原样跳过。
func migrate_legacy_treasures() -> int:
	var fixed := 0
	for slot in TREASURE_SLOT_ORDER:
		var it = treasure_slots.get(slot)
		if not (it is Dictionary) or (it as Dictionary).is_empty():
			continue
		var d: Dictionary = it
		if String(d.get("type", "")) == ITEM_EQUIPMENT and d.has("equipment_type"):
			continue
		d["type"] = ITEM_EQUIPMENT
		d["equipment_type"] = "treasure"
		d["equipment_grade"] = String(d.get("equipment_grade", d.get("treasure_grade", "法器")))
		if String(d.get("equipment_grade", "")) == "凡品":
			d["equipment_grade"] = "法器"
		d["equipment_level"] = int(d.get("equipment_level", 1))
		d["enhancement_level"] = int(d.get("enhancement_level", 0))
		d["enhancement_limit"] = int(d.get("enhancement_limit", ItemDB.MAX_ENHANCE))
		d["refinement_state"] = String(d.get("refinement_state", "未精炼"))
		d["enhance_fail_count"] = int(d.get("enhance_fail_count", 0))
		d["enhance_ascend_fail_count"] = int(d.get("enhance_ascend_fail_count", 0))
		var raw_seq = d.get("enhance_wear_seq", [])
		d["enhance_wear_seq"] = (raw_seq as Array).duplicate(true) if raw_seq is Array else []
		d["enhance_crystal_spent"] = int(d.get("enhance_crystal_spent", 0))
		d["is_broken"] = bool(d.get("is_broken", false))
		d["attack_bonus_base"] = float(d.get("attack_bonus_base", 0.0))
		d["attack_bonus"] = float(d.get("attack_bonus", 0.0))
		if not d.has("attributes_base"):
			var src = d.get("attributes", {})
			d["attributes_base"] = src.duplicate(true) if src is Dictionary else {}
		treasure_slots[slot] = d
		fixed += 1
	return fixed


## 2026-11-01 新规：法宝不带属性词条，只有进阶能增强主动效果。
## 迁移旧档：清掉法宝实例上的属性 / 普通强化等级 / 磨损 / 破损；
## 旧召唤令靠普通强化堆出来的加成并入 summon_ascend_boost_pct，成长线不断。
func migrate_treasure_no_affixes() -> int:
	var fixed := 0
	for slot in TREASURE_SLOT_ORDER:
		var it = treasure_slots.get(slot)
		if it is Dictionary and not (it as Dictionary).is_empty():
			if _normalize_treasure_no_affixes(it as Dictionary):
				fixed += 1
	for raw in inventory:
		if raw is Dictionary \
				and String((raw as Dictionary).get("equipment_type", "")) == "treasure":
			if _normalize_treasure_no_affixes(raw as Dictionary):
				fixed += 1
	return fixed


## 单件法宝归一：幂等。返回是否改动。
func _normalize_treasure_no_affixes(item: Dictionary) -> bool:
	if String(item.get("equipment_type", "")) != "treasure":
		return false
	var changed := false
	# 旧召唤令：普通强化级数 ×2% → 转入进阶加成
	var boost_count := maxi(0, int(item.get("summon_boost_count", 0)))
	if boost_count > 0:
		item["summon_ascend_boost_pct"] = float(item.get("summon_ascend_boost_pct", 0.0)) \
			+ float(boost_count) * float(SUMMON_BOOST_PER_LEVEL)
		item["summon_boost_count"] = 0
		changed = true
	for key in ["attributes", "attributes_base"]:
		var attrs = item.get(key)
		if attrs is Dictionary and (attrs as Dictionary).is_empty():
			continue
		item[key] = {}
		changed = true
	for key in ["enhancement_level", "enhance_success_count", "enhance_fail_count", "enhance_ascend_fail_count"]:
		if int(item.get(key, 0)) != 0:
			item[key] = 0
			changed = true
	var raw_wear = item.get("enhance_wear_seq", [])
	if raw_wear is Array and not (raw_wear as Array).is_empty():
		item["enhance_wear_seq"] = []
		changed = true
	if int(item.get("enhancement_limit", 0)) != 0:
		item["enhancement_limit"] = 0
		changed = true
	if bool(item.get("is_broken", false)):
		item["is_broken"] = false
		changed = true
	for key in ["attack_bonus_base", "attack_bonus"]:
		if not is_zero_approx(float(item.get(key, 0.0))):
			item[key] = 0.0
			changed = true
	return changed


## 旧存档迁移：装备类别别名规范化（2026-10-19）
## 把背包 / 穿戴槽里 equipment_type 为旧别名（如清风鞋的 "boots"）的物品
## 原地改成当前类别键（"shoes"）。只修模板救不了已存盘的 JSON，必须在这里兜。
## 返回修正的件数（0 = 没有需要修的数据）。
func migrate_legacy_equip_types() -> int:
	var fixed := 0
	for i in range(inventory.size()):
		var it = inventory[i]
		if it is Dictionary and _fix_legacy_equip_type(it):
			fixed += 1
	for slot in equipment_slots.keys():
		var it = equipment_slots.get(slot)
		if it is Dictionary and _fix_legacy_equip_type(it):
			fixed += 1
	for slot in treasure_slots.keys():
		var it = treasure_slots.get(slot)
		if it is Dictionary and _fix_legacy_equip_type(it):
			fixed += 1
	return fixed


## 原地修正单件物品的旧装备类别（修正了返回 true）
static func _fix_legacy_equip_type(item: Dictionary) -> bool:
	var etype := String(item.get("equipment_type", ""))
	var canon := normalize_equip_type(etype)
	if canon == etype:
		return false
	item["equipment_type"] = canon
	return true


## 旧档饰品去重（2026-10-31 新规：同种饰品只能戴一件）
## 保留槽位顺序最靠前的一件，其余放回背包；背包到软上限时允许临时超出一格，
## 仍然强制执行唯一性 —— 不吞装备，也不把重复件留在身上。
## 返回挪回背包的件数（0 = 没有重复）。
func migrate_duplicate_accessories() -> int:
	var seen: Dictionary = {}
	var moved := 0
	for slot in WORN_SLOT_ORDER:
		var s := String(slot)
		if slot_type(s) != "accessory":
			continue
		var item := get_equipped(s)
		if item.is_empty():
			continue
		var id := String(item.get("id", ""))
		if id == "":
			continue
		if not seen.has(id):
			seen[id] = s
			continue
		if not add_item(item):
			# 软上限：装备不堆叠，add_item 满了会拒绝；直接占一格保证规则生效
			inventory.append(item.duplicate())
			mark_codex_from_item(item)
		_set_slot(s, {})
		moved += 1
	return moved


## 旧存档迁移：清风剑 / 清风鞋的绝对值词条 → 百分比词条（2026-10-19 用户调价）
## ⚠ 背景：用户实测「清风剑加的精力恢复太多了」——
##   旧版清风剑 stamina_regen +0.10（绝对值，0.25→0.35 约 +40%）、清风鞋 speed +11（约 +5%）；
##   新版改成百分比词条：基础各 +1%，锻造（强化）有几率再 +0.5%~1%。
## 换算口径：**旧模板基础值记 1%**（剑 0.10 / 鞋 11.0），实例里的旧值按比例折算，
##   强化涨的部分也按同一比例走（保相对投资），折算后保留 1 位小数。
## 幂等：已经是新词条（没有旧键）的条目跳过。
const LEGACY_PCT_CONVERT: Dictionary = {
	"eq_qingfengjian": {
		"flat": AttributeDB.ATTR_STAMINA_REGEN,
		"pct": AttributeDB.ATTR_STAMINA_REGEN_PCT,
		"base": 0.10,
	},
	"eq_qingfengxie": {
		"flat": AttributeDB.ATTR_SPEED,
		"pct": AttributeDB.ATTR_SPEED_PCT,
		"base": 11.0,
	},
}

## 2026-10-31：旧烈火 / 磐石符整套下架，读档时清掉旧物品、符方与图鉴记录。
const LEGACY_TALISMAN_IDS: Array[String] = [
	"tal_pofengfu", "tal_panshifu",
	"tal_zj_liehuofu", "tal_zj_panshifu",
	"tal_jd_liehuofu", "tal_jd_panshifu",
]
const LEGACY_TALISMAN_RECIPE_IDS: Array[String] = [
	"recipe_pofengfu", "recipe_panshifu",
	"recipe_zj_liehuofu", "recipe_zj_panshifu",
	"recipe_jd_liehuofu", "recipe_jd_panshifu",
]


func migrate_remove_legacy_talismans() -> int:
	var removed := 0
	for i in range(inventory.size() - 1, -1, -1):
		if String(inventory[i].get("id", "")) in LEGACY_TALISMAN_IDS:
			inventory.remove_at(i)
			removed += 1
	for rid in LEGACY_TALISMAN_RECIPE_IDS:
		talisman_crafting_progress.erase(rid)
		codex_unlocked.erase(rid)
	for iid in LEGACY_TALISMAN_IDS:
		codex_unlocked.erase(iid)
		if talisman_stock.has(iid):
			talisman_stock.erase(iid)
			removed += 1
	for slot in quick_slots.keys():
		if String(quick_slots.get(slot, "")) in LEGACY_TALISMAN_IDS:
			quick_slots[slot] = ""
	for i in range(active_skill_loadout.size()):
		var sid := String(active_skill_loadout[i])
		if is_talisman_slot(sid) and talisman_slot_item_id(sid) in LEGACY_TALISMAN_IDS:
			active_skill_loadout[i] = ""
	return removed


## 2026-10-31 灵力恢复 ÷10：把旧档里的装备词条一起折算。
## 幂等判据看 attributes_base：旧基础 1.5 / 新基础 0.15，强化增量不会写回 base。
func migrate_mana_regen_tenth() -> int:
	var fixed := 0
	var base := float(base_attributes.get(AttributeDB.ATTR_MANA_REGEN, 0.0))
	if base > 1.0:
		base_attributes[AttributeDB.ATTR_MANA_REGEN] = float(BASE_ATTRIBUTE_DEFAULTS[AttributeDB.ATTR_MANA_REGEN])
		fixed += 1
	for i in range(inventory.size()):
		var it = inventory[i]
		if it is Dictionary and _fix_mana_regen_legacy_attrs(it):
			fixed += 1
	for slot in equipment_slots.keys():
		var it = equipment_slots.get(slot)
		if it is Dictionary and _fix_mana_regen_legacy_attrs(it):
			fixed += 1
	for slot in treasure_slots.keys():
		var it = treasure_slots.get(slot)
		if it is Dictionary and _fix_mana_regen_legacy_attrs(it):
			fixed += 1
	return fixed


## 单件旧装备的灵力恢复词条 ÷10（幂等）。
## attributes_base 缺失的极旧结构才用当前值兜底，且阈值抬到 1.0，避免把新装备的强化值再砍一次。
static func _fix_mana_regen_legacy_attrs(item: Dictionary) -> bool:
	var base_attrs = item.get("attributes_base")
	var cur_attrs = item.get("attributes")
	var has_base := base_attrs is Dictionary and (base_attrs as Dictionary).has(AttributeDB.ATTR_MANA_REGEN)
	var marker := 0.0
	if has_base:
		marker = float((base_attrs as Dictionary).get(AttributeDB.ATTR_MANA_REGEN, 0.0))
	elif cur_attrs is Dictionary and (cur_attrs as Dictionary).has(AttributeDB.ATTR_MANA_REGEN):
		marker = float((cur_attrs as Dictionary).get(AttributeDB.ATTR_MANA_REGEN, 0.0))
	if marker <= (0.5 if has_base else 1.0):
		return false
	for field in ["attributes", "attributes_base"]:
		var attrs = item.get(field)
		if attrs is Dictionary and (attrs as Dictionary).has(AttributeDB.ATTR_MANA_REGEN):
			attrs[AttributeDB.ATTR_MANA_REGEN] = float((attrs as Dictionary)[AttributeDB.ATTR_MANA_REGEN]) / 10.0
	return true


func migrate_legacy_pct_attrs() -> int:
	var fixed := 0
	for i in range(inventory.size()):
		var it = inventory[i]
		if it is Dictionary and _fix_legacy_pct_attrs(it):
			fixed += 1
	for slot in equipment_slots.keys():
		var it = equipment_slots.get(slot)
		if it is Dictionary and _fix_legacy_pct_attrs(it):
			fixed += 1
	for slot in treasure_slots.keys():
		var it = treasure_slots.get(slot)
		if it is Dictionary and _fix_legacy_pct_attrs(it):
			fixed += 1
	return fixed


## 原地把单件物品的旧绝对值词条折算成百分比词条（修正了返回 true）
static func _fix_legacy_pct_attrs(item: Dictionary) -> bool:
	var spec = LEGACY_PCT_CONVERT.get(String(item.get("id", "")), null)
	if spec == null:
		return false
	var fixed := false
	var s: Dictionary = spec
	var flat_id := String(s.get("flat", ""))
	var pct_id := String(s.get("pct", ""))
	var base_flat := float(s.get("base", 0.0))
	# attributes（当前值）与 attributes_base（模板原值）都要折算，否则强化增量显示会错
	for field in ["attributes", "attributes_base"]:
		var attrs = item.get(field)
		if not (attrs is Dictionary) or not attrs.has(flat_id):
			continue
		var flat_val := float(attrs[flat_id])
		attrs.erase(flat_id)
		# 旧基础值 = 1%；按比例换算后收圆到 0.1，避免 9.956% 这种长尾
		var pct_val := 1.0 if is_zero_approx(base_flat) else snappedf(flat_val / base_flat, 0.1)
		attrs[pct_id] = float(attrs.get(pct_id, 0.0)) + pct_val
		fixed = true
	return fixed


## 单件装备提供的攻击力加成
## 统一走 ItemDB.compute_attack_bonus，保证「基础 + 品阶 + 强化」口径单一
func get_item_attack_bonus(item: Dictionary) -> float:
	return ItemDB.compute_attack_bonus(item)


## 把背包里第 index 件物品穿到对应槽位；成功返回被换下的旧装备（可能为空字典）
## prefer_slot 可指定具体槽（饰品有三个）；不指定则找该类第一个空槽
func equip_from_inventory(index: int, prefer_slot: String = "") -> Dictionary:
	# 试炼之路本局进行中：换装一律拒绝（面板已拦，这里是数据层保险）。
	# ⚠ 必须放在下标检查之前：放后面的话空背包会先命中 `index >= size` 直接返回，
	#   保险形同不存在，探针也断言不到
	if rogue_lock:
		equip_block_reason = "试炼之路：本局从零开始，无法换装"
		return {}
	if index < 0 or index >= inventory.size():
		return {}
	var item: Dictionary = inventory[index]
	if String(item.get("type", "")) != ITEM_EQUIPMENT:
		return {}
	var etype := String(item.get("equipment_type", ""))
	var slot := prefer_slot
	if slot == "" or not slot_accepts(slot, etype):
		slot = first_free_slot(etype)
	if slot == "":
		push_warning("未知装备部位：" + etype)
		return {}
	# 同种饰品 / 法宝不能重复佩戴（饰品 2026-10-31 / 法宝 2026-10-22 用户定）
	# ⚠ 必须在 `inventory.remove_at()` **之前**拦：这里已经算出了真实目标槽位，
	#   拦晚了会先把它从背包移除、又没穿上 —— 直接把物品弄丢
	var dup := equip_dup_slot(item, slot)
	if dup != "":
		push_warning("同种%s已在【%s】，不能重复佩戴：%s" % [
			String(EQUIP_TYPE_DISPLAY.get(etype, "装备")),
			slot_display_name(dup), String(item.get("name", ""))])
		return {}
	# 先从背包移除，再穿上；被换下的旧装备（若有）回到背包
	inventory.remove_at(index)
	var old := get_equipped(slot)
	if not old.is_empty() and not bag_has_room(old):
		# 换下来的旧装备放不下 → 原样塞回背包，整个穿戴作废。
		# 绝不能像以前那样 add_item() 失败就把它吞掉（2026-11-02 用户报的丢装备 bug）
		inventory.insert(clampi(index, 0, inventory.size()), item)
		equip_block_reason = "换下的「%s」放不下 —— %s" % [
			String(old.get("name", "旧装备")), bag_full_message(old)]
		return {}
	equip(slot, item)
	if not old.is_empty():
		add_item(old)
	return old


## 把一件装备放回背包；放不下就**强制越上限入包**并告警。
## 用于「东西已经不在任何槽位/背包里、只被界面拿在手上」的归还场景 ——
## 这种时候拒绝归还会直接让装备消失，所以宁可超上限（沿用去重迁移的做法）。
func return_item_or_force(item: Dictionary) -> void:
	if item.is_empty():
		return
	if add_item(item.duplicate(true)):
		return
	inventory.append(item.duplicate(true))
	mark_codex_from_item(item)
	push_warning("分背包已满，装备强制归位：%s" % String(item.get("id", item.get("name", "?"))))


## 卸下某槽位装备并放回背包；背包放不下则拒绝（返回是否成功）
func unequip_to_inventory(slot: String) -> bool:
	if rogue_lock:
		return false
	var item := get_equipped(slot)
	if item.is_empty():
		return false
	if not bag_has_room(item):
		return false
	unequip(slot)
	add_item(item)
	return true


## 玩家是否持有某件装备（按模板 id）：背包 + 六个穿戴槽 + 三个法宝槽。
## 「这东西还在不在玩家手上」的**唯一**口径（例：石台剑的自愈补发、虎妖战败提示）。
## ⚠ 不要只看背包：装到身上的也算持有。
func owns_equipment(equipment_id: String) -> bool:
	if equipment_id == "":
		return false
	for raw in inventory:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == equipment_id:
			return true
	for group in [equipment_slots, treasure_slots]:
		var g: Dictionary = group
		for slot in g.keys():
			var it = g[slot]
			if it is Dictionary and String((it as Dictionary).get("id", "")) == equipment_id:
				return true
	return false


# ===== 锻造台：装备的「实体取用 / 归还」=====
## 设计（用户 2026-10-17）：一件装备**同一时刻只能在一个地方**——
##   穿戴槽 ↔ 背包 ↔ 锻造台，三处互斥。
##   放上砧 = 实体真的离开原位置（身上的要先卸、背包里的要移出）；
##   取下来 = 实体回到背包，并且会重新出现在素材区列表里。
##
## ⚠ 为什么不能只存引用：面板里若还拿着背包里那条的引用，
##   锻造写入（attributes 原地加值）会与背包那一份互相污染，且素材区会重复显示。

## 找出持有「同一个对象」的穿戴槽 id（没有则空串）
## ⚠ 判定同一对象必须用 `is_same()`，**绝不能用 `==`**：
##   GDScript 里 Dictionary 的 `==` 是**内容深比较**，
##   两件同款装备（内容完全一样但本就是两件）会被误判成同一件。
func _slot_holding(item: Dictionary) -> String:
	for slot in equipment_slots.keys():
		var it = equipment_slots.get(slot)
		if it is Dictionary and is_same(it, item):
			return String(slot)
	# 法宝也是装备实例，必须一起查；否则 equip_treasure_from_inventory()
	# 穿完会误报失败，锻造台的「是否在身上」判断也会漏掉法宝
	for slot in treasure_slots.keys():
		var it = treasure_slots.get(slot)
		if it is Dictionary and is_same(it, item):
			return String(slot)
	return ""


## 背包里是否也有「同一个对象」，有则返回其下标（没有则 -1）
func _inventory_index_of_same(item: Dictionary) -> int:
	for i in range(inventory.size()):
		var it = inventory[i]
		if it is Dictionary and is_same(it, item):
			return i
	return -1


## 该装备对象当前是否正被某个穿戴槽持有（按引用判定）
func is_held_by_slot(item: Dictionary) -> bool:
	return _slot_holding(item) != ""


## 把装备「交给锻造台」：从背包或穿戴槽**真正取出**
##   index >= 0 → 从背包取（按 CharacterData.inventory 的下标）
##   index < 0  → 从穿戴槽取（传 slot）
##
## ⚠ 规则（2026-10-17 用户改定）：**不能把身上正穿着的装备直接拖上砧**，
##   必须先手动卸下（此时它才回到背包，才能按背包下标取）。
##   所以 index 路径里若检测到该对象仍被某个穿戴槽持有，直接返回空并给出原因，
##   由面板提示「请先卸下装备」，而不是像以前那样自动卸下。
##   这能让「实体唯一归属」的语义对玩家可见，而不是被静默修正。
##
## 返回 { "item": 装备字典, "reason": String }
##   item 为空 = 取用失败；reason 为空串 = 成功
func take_for_forge(index: int = -1, slot: String = "") -> Dictionary:
	var empty := func(r: String) -> Dictionary:
		return {"item": {}, "reason": r}
	if index >= 0:
		if index >= inventory.size():
			return empty.call("这件装备已不在背包里。")
		var item: Dictionary = inventory[index]
		if String(item.get("type", "")) != ITEM_EQUIPMENT:
			return empty.call("只能强化装备。")
		# 正在穿戴的装备不允许直接上砧 → 提示先卸下
		var held := _slot_holding(item)
		if held != "":
			return empty.call("请先卸下「%s」再放入锻造台。" % String(item.get("name", "装备")))
		inventory.remove_at(index)
		return {"item": item, "reason": ""}
	if slot != "":
		var it := get_equipped(slot)
		if it.is_empty():
			return empty.call("这个槽位没有装备。")
		unequip(slot)
		# 防线：同一个对象若还残留在背包里（历史脏数据），也一并移出
		var idx := _inventory_index_of_same(it)
		if idx >= 0:
			inventory.remove_at(idx)
		return {"item": it, "reason": ""}
	return empty.call("无法取用这件装备。")


## 锻造结束（或玩家取下）把装备放回背包；背包满则返回 false（装备留在砧上）
## 这里用**深拷贝**入包：锻造期间砧上那份与背包那份彻底隔离，杜绝共享 attributes
func return_from_forge(item: Dictionary) -> bool:
	if item.is_empty():
		return false
	if not bag_has_room(item):
		return false
	return add_item(item.duplicate(true))


## 发放开局自带法宝（一次性，逻辑同 ensure_starting_equipment）
## 让法宝面板一开始就有内容可看，也方便玩家理解「法宝能加属性」
func ensure_starting_treasures() -> Array:
	var granted: Array = []
	if starting_treasure_granted:
		return granted
	starting_treasure_granted = true
	for tpl in ItemDB.get_starting_treasures():
		var item := make_treasure_instance(tpl)
		var slot := first_free_treasure_slot()
		var equipped_ok := false
		if slot != "" and get_treasure(slot).is_empty():
			equipped_ok = equip_treasure(slot, item)
		if not equipped_ok:
			add_item(item)
		granted.append(String(item.get("name", "")))
	return granted


# ===== 槽位工具 =====

## 槽位 → 装备类别（weapon / armor / shoes / accessory）
## 槽位显示名（装备槽走 SLOT_DISPLAY，法宝槽走 TREASURE_SLOT_DISPLAY）
static func slot_display_name(slot: String) -> String:
	if TREASURE_SLOT_DISPLAY.has(slot):
		return String(TREASURE_SLOT_DISPLAY[slot])
	return String(SLOT_DISPLAY.get(slot, slot))


static func slot_type(slot: String) -> String:
	# 法宝槽单独一类：equipment_type == "treasure" 的条目（法宝实例）落这些槽
	if slot.begins_with("treasure_"):
		return "treasure"
	return String(SLOT_TYPE.get(slot, ""))


## 某装备类别可用的槽位列表（含法宝）
## ⚠ etype 先过 normalize_equip_type：旧别名（boots）也能解析到正确槽位
static func slots_for_type(etype: String) -> Array:
	var want := normalize_equip_type(etype)
	var out: Array = []
	for slot in WORN_SLOT_ORDER:
		if slot_type(String(slot)) == want:
			out.append(slot)
	return out


## 该类别第一个空槽；全满则返回该类第一个槽（调用方自行决定是替换还是拒绝）
func first_free_slot(etype: String) -> String:
	var slots := slots_for_type(etype)
	if slots.is_empty():
		return ""
	for slot in slots:
		if get_equipped(String(slot)).is_empty():
			return String(slot)
	return String(slots[0])


## 该装备能否穿到指定槽位（类别必须匹配；旧别名同样接受）
static func slot_accepts(slot: String, etype: String) -> bool:
	var want := normalize_equip_type(etype)
	return slot_type(slot) != "" and slot_type(slot) == want


## 同一种装备已经戴在哪个槽（空串 = 没冲突）
## 只对可占多个槽的类别生效：饰品（3 槽）/ 法宝（3 槽）。单槽类别恒返回空串。
## 「相同」按模板 id 判定 —— 强化等级不同也算同一种，见 equip() 里的口径说明
## except_slot：检查时忽略这个槽（换装到同一槽必须忽略自己，否则永远算重复）
## 同一件对象换槽（is_same）不算重复：它只会从旧槽挪走，不会多出一件
## ⚠ 不是 static：要读 get_equipped()（实例状态）。调用照旧走 CharacterData.xxx()
func equip_dup_slot(item: Dictionary, except_slot: String = "") -> String:
	var etype := String(item.get("equipment_type", ""))
	if etype != "accessory" and etype != "treasure":
		return ""
	var want := String(item.get("id", ""))
	if want == "":
		return ""
	for slot in WORN_SLOT_ORDER:
		var s := String(slot)
		if s == except_slot or slot_type(s) != etype:
			continue
		var other: Dictionary = get_equipped(s)
		if other.is_empty() or is_same(other, item):
			continue
		if String(other.get("id", "")) == want:
			return s
	return ""


# ===== 法宝（已并入装备体系，这里只留兼容别名）=====
## ⚠ 2026-10-17 起法宝与装备统一：
##   法宝实例的 type 就是 ITEM_EQUIPMENT、equipment_type == "treasure"，
##   所以它能进背包、能在装备佩戴区显示、能上锻造台强化。
##   下面这几个函数保留为兼容层（旧代码 / 旧存档仍可能调到）。

func get_treasure(slot: String) -> Dictionary:
	return get_equipped(slot)


## 兼容层：法宝的旧接口全部委托到统一接口（法宝与装备现在是同一套）
## 穿法宝（兼容入口）
## 返回是否真的穿上 —— 失败时调用方**必须**把 item 放回背包，否则物品会凭空消失
func equip_treasure(slot: String, item: Dictionary) -> bool:
	if equip_dup_slot(item, slot) != "":
		push_warning("同种法宝已在其它法宝槽，不能重复佩戴：%s" % String(item.get("name", "")))
		return false
	equip(slot, item)
	return true


func unequip_treasure(slot: String) -> Dictionary:
	return unequip(slot)


func first_free_treasure_slot() -> String:
	return first_free_slot("treasure")


## 把背包里第 index 件法宝穿到指定槽（不传则找第一个空槽）
## 返回 { ok: bool, replaced: Dictionary } —— replaced 是被换下并已回背包的旧法宝
func equip_treasure_from_inventory(index: int, prefer_slot: String = "") -> Dictionary:
	if index < 0 or index >= inventory.size():
		return {"ok": false, "replaced": {}}
	var item: Dictionary = inventory[index]
	# 兼容新旧两种类型标记（旧存档的法宝是 ITEM_TREASURE）
	if String(item.get("type", "")) != ITEM_EQUIPMENT:
		return {"ok": false, "replaced": {}}
	# 同种法宝不能重复：先拦一次，避免下面误报成功
	if equip_dup_slot(item, prefer_slot) != "":
		return {"ok": false, "replaced": {}}
	var old := equip_from_inventory(index, prefer_slot)
	# 判成败看「是否真的戴在身上」，不能无条件报 ok
	return {"ok": is_held_by_slot(item), "replaced": old}


func unequip_treasure_to_inventory(slot: String) -> bool:
	return unequip_to_inventory(slot)


# ===== 属性聚合 =====

## 全部已穿戴装备提供的属性合计（不含武器 attack_bonus，那部分单独算进物理攻击）
func equipment_attributes() -> Dictionary:
	var sum: Dictionary = {}
	for slot in SLOT_ORDER:
		var item := get_equipped(slot)
		if item.is_empty():
			continue
		_sum_into(sum, ItemDB.item_attributes(item))
	return sum


## 全部已佩戴法宝提供的属性合计
func treasure_attributes() -> Dictionary:
	var sum: Dictionary = {}
	for slot in TREASURE_SLOT_ORDER:
		var item := get_treasure(slot)
		if item.is_empty():
			continue
		_sum_into(sum, ItemDB.item_attributes(item))
	return sum


func _sum_into(target: Dictionary, src: Dictionary) -> void:
	for k in src.keys():
		target[k] = float(target.get(k, 0.0)) + float(src[k])


# ===== 临时属性修正（buff / debuff）=====

## 写入某来源的整组修正（同 key 覆盖）
## mods 结构：{ attr_id: {"flat": 数值, "mult": 倍率} }，两个字段都可省略
func set_attribute_mod(source: String, mods: Dictionary) -> void:
	attribute_mods[source] = mods.duplicate(true)


## 清除某来源的修正（buff 到期 / 离开战斗时调用）
func clear_attribute_mod(source: String) -> void:
	attribute_mods.erase(source)


func clear_all_attribute_mods() -> void:
	attribute_mods.clear()


## 临时修正的加值合计
func _mod_flat(attr_id: String) -> float:
	var total := 0.0
	for source in attribute_mods.keys():
		var mods: Dictionary = attribute_mods[source]
		var m = mods.get(attr_id, {})
		if m is Dictionary:
			total += float(m.get("flat", 0.0))
	return total


## 临时修正的「本体百分比」合计（单位 %，只按裸装基础值计算，装备/法宝不参与）
## 2026-10-24 用户定：练气丹药只能增加角色本体基础数值的百分比。
func _mod_base_pct(attr_id: String) -> float:
	var total := 0.0
	for source in attribute_mods.keys():
		var mods: Dictionary = attribute_mods[source]
		var m = mods.get(attr_id, {})
		if m is Dictionary:
			total += float(m.get("base_pct", 0.0))
	return total


## 临时修正的倍率合计（默认 1.0，多个来源相乘）
func _mod_mult(attr_id: String) -> float:
	var mult := 1.0
	for source in attribute_mods.keys():
		var mods: Dictionary = attribute_mods[source]
		var m = mods.get(attr_id, {})
		if m is Dictionary:
			mult *= float(m.get("mult", 1.0))
	return mult


## 某属性的百分比加成合计（装备 + 法宝 + 临时的 <attr_id>_pct 词条，单位 %，1.0 = +1%）
## ⚠ 2026-10-19 用户调价：清风剑/清风鞋的基础词条从绝对值改成百分比
##   （精力恢复 +0.10 格/秒实测过量 → 精力恢复速度 +1%），走的就是这套 _pct 词条。
func _pct_total(attr_id: String) -> float:
	var pct_id := attr_id + "_pct"
	var pct := float(equipment_attributes().get(pct_id, 0.0))
	pct += float(treasure_attributes().get(pct_id, 0.0))
	pct += _mod_flat(pct_id)
	return pct


## 境界成长给某项基础值带来的绝对增量（不吃装备 / 法宝 / 百分比词条）
func _realm_bonus(attr_id: String, base: float) -> float:
	if REALM_GROWTH_ATTRS.has(attr_id):
		return base * (realm_stat_multiplier() - 1.0)
	if attr_id == AttributeDB.ATTR_MANA_REGEN:
		return realm_mana_regen_bonus()
	return 0.0


## 最终属性值 = (基础 + 境界成长 + 装备 + 法宝 + 临时加值 + 本体百分比加值) × 百分比增幅 × 临时倍率
## 本体百分比加值只按 base_attributes 计算，装备 / 法宝提供的属性不参与（2026-10-24 用户定）
## 这是全项目读取属性的**唯一入口**，不要在别处直接读 base_attributes
func attribute(attr_id: String) -> float:
	var base := float(base_attributes.get(attr_id, 0.0))
	var realm := _realm_bonus(attr_id, base)
	var base_add := (base + realm) * _mod_base_pct(attr_id) / 100.0
	var total := base + realm + base_add
	total += float(equipment_attributes().get(attr_id, 0.0))
	total += float(treasure_attributes().get(attr_id, 0.0))
	total += _mod_flat(attr_id)
	return maxf(0.0, total * (1.0 + _pct_total(attr_id) / 100.0) * _mod_mult(attr_id))


## 某属性的来源拆解（面板显示「基础 / 装备 / 法宝 / 临时」用）
## 返回 { base, realm, equipment, treasure, mod_flat, mod_base, mod_base_pct, mod_mult,
##        equipment_pct, treasure_pct, mod_pct, pct_total, total }
func attribute_breakdown(attr_id: String) -> Dictionary:
	var base := float(base_attributes.get(attr_id, 0.0))
	var realm := _realm_bonus(attr_id, base)
	var eq := float(equipment_attributes().get(attr_id, 0.0))
	var tr := float(treasure_attributes().get(attr_id, 0.0))
	var flat := _mod_flat(attr_id)
	var base_pct := _mod_base_pct(attr_id)
	var base_add := (base + realm) * base_pct / 100.0
	var mult := _mod_mult(attr_id)
	var eq_pct := float(equipment_attributes().get(attr_id + "_pct", 0.0))
	var tr_pct := float(treasure_attributes().get(attr_id + "_pct", 0.0))
	var mod_pct := _mod_flat(attr_id + "_pct")
	return {
		"base": base,
		"realm": realm,
		"equipment": eq,
		"treasure": tr,
		"mod_flat": flat,
		"mod_base": base_add,
		"mod_base_pct": base_pct,
		"mod_mult": mult,
		"equipment_pct": eq_pct,
		"treasure_pct": tr_pct,
		"mod_pct": mod_pct,
		"pct_total": eq_pct + tr_pct + mod_pct,
		"total": maxf(0.0, (base + realm + eq + tr + flat + base_add)
			* (1.0 + (eq_pct + tr_pct + mod_pct) / 100.0) * mult),
	}


## 面板用的全部属性快照：{ attr_id: { ...breakdown } }
func attributes_snapshot() -> Dictionary:
	var out: Dictionary = {}
	for id in AttributeDB.all_ids():
		out[String(id)] = attribute_breakdown(String(id))
	return out


# ===== 派生战斗数值（全部由属性推导）=====

## 五旗阵攻击乘区（1.0 = 无）：玩家侧每帧合并「己阵 +30% / 敌阵 -10%」后写入。
## 放在派生入口而不是各处伤害里，普攻 / 功法 / 阵旗 / 气环 / 雷击都会自然吃到。
var array_zone_attack_mult: float = 1.0

## 剑意·剑心通明：每层剑意带来的物理功法乘区（1.0 = 未佩戴或 0 层）。
## player.gd 在剑意变化时写入；只乘 calc_skill_damage 的物理段，普攻 / 法术 / 召唤物不吃。
var sword_intent_skill_mult: float = 1.0


## 物理攻击力 = 力量 × 换算系数 + 武器/装备的 attack_bonus
## ⚠ 「力量取代攻击力」：项目里不再有独立的 base_attack 字段
func physical_attack() -> float:
	var atk := attribute(AttributeDB.ATTR_STRENGTH) * STRENGTH_TO_ATTACK
	for slot in SLOT_ORDER:
		var item := get_equipped(slot)
		if not item.is_empty():
			atk += get_item_attack_bonus(item)
	return maxf(0.0, atk) * array_zone_attack_mult


## 法术攻击力 = 法强 × 换算系数
func spell_attack() -> float:
	return maxf(0.0, attribute(AttributeDB.ATTR_SPELL_POWER) * SPELL_POWER_TO_ATTACK) \
		* array_zone_attack_mult


## 法术功法增伤倍率（1.0 = 无加成）
## 只乘在功法的法术系数上：普攻、召唤物、刀痕等非直接功法伤害不受影响。
func spell_skill_damage_mult() -> float:
	return 1.0 + maxf(0.0, attribute(AttributeDB.ATTR_SPELL_SKILL_DAMAGE_PCT)) / 100.0


## 兼容旧调用名（大量代码用 total_attack()）
func total_attack() -> float:
	return physical_attack()


## 普通攻击间隔（攻速越高越短）；攻速 +100% → 间隔减半
func attack_interval() -> float:
	var haste := attribute(AttributeDB.ATTR_ATTACK_SPEED)
	return attack_time / maxf(0.01, 1.0 + haste / 100.0)


func max_hp() -> float:
	return maxf(1.0, attribute(AttributeDB.ATTR_HP_MAX))


func max_mana() -> float:
	return maxf(0.0, attribute(AttributeDB.ATTR_MANA_MAX))


## 灵力每秒回复
func mana_regen() -> float:
	return maxf(0.0, attribute(AttributeDB.ATTR_MANA_REGEN))


func max_stamina() -> int:
	return int(round(maxf(0.0, attribute(AttributeDB.ATTR_STAMINA_MAX))))


## 精力每秒回复格数（旧口径是「每格几秒」，这里反过来，越高越好）
func stamina_regen_per_sec() -> float:
	return maxf(0.001, attribute(AttributeDB.ATTR_STAMINA_REGEN))


## 旧的「每格秒数」口径，供仍在使用秒数的旧代码
func stamina_regen_seconds() -> float:
	return 1.0 / stamina_regen_per_sec()


func move_speed() -> float:
	return maxf(0.0, attribute(AttributeDB.ATTR_SPEED))


## 抗性减免率（0~0.9）
func resist_reduction(attr_id: String) -> float:
	return AttributeDB.resist_reduction(attribute(attr_id))


## 单独元素抗性接口：空串 / 非元素返回 0，元素返回对应抗性值
func element_resist(element: String) -> float:
	if not AttributeDB.is_element(element):
		return 0.0
	return attribute("resist_" + element)



# ===== 强化（锻造台铁砧）=====
## 强化媒介材料 id
const ENHANCE_MATERIAL := "mat_duanzaojingshi"
## 铸神晶 / 补天石（2026-11-13 用户定）：铸神只吃晶、补天只吃石
const DIVINE_MATERIAL := "mat_zhushenjing"
const MEND_MATERIAL := "mat_butianshi"
## 化神期仙器淬炼材料（2026-11-13 用户定）
const YUNXIAN_MATERIAL := "mat_yunxiansui"

## 召唤法宝（BOSS 令）每强化一级：召唤物气血与攻击 +基础值的百分之几（2 = +2%）
## 2026-10-21 用户定：**无上限**，靠反复「满级 → 进阶 → 继续强化」累积
const SUMMON_BOOST_PER_LEVEL := 2

## 召唤法宝每**进阶成功**一次：召唤物存在时间 +多少秒（2026-10-21 用户定）
const SUMMON_DURATION_PER_ASCEND := 5.0

## 召唤法宝每**进阶成功**一次：召唤物气血/攻击额外 +多少%（2026-11-01 用户定）
## 法宝不再走普通强化，进阶是唯一成长线；旧档的普通强化加成由迁移折进这个字段。
const SUMMON_ASCEND_BOOST_PER_GRADE := 6.0

## 一次强化敲击的完整结果，供 UI 飘字与提示使用
## 结构：{
##   "ok": bool,            本次叩击是否被受理（材料/条件不足时为 false）
##   "result": String,      见 ItemDB.ENHANCE_RESULT_*；未受理时为空串
##   "delta": int,          强化等级变化（进阶归零时为负）
##   "attr_gains": Array,   本次提升的属性 [{ "attr_id": String, "amount": float }]
##   "fail_count": int,     当前磨损次数
##   "broken": bool,        本次敲击后是否已破损
##   "grade_before" / "grade_after" / "enhance_before" / "enhance_after"
##   "message": String,     给玩家的中文结果文案
##   "cost_consumed": bool, 是否消耗了晶石
## }
##
## ===== 强化规则（2026-10-17 用户改版）=====
##   成功 80% / 大成功 5% / 失败 20%
##   - **成功**：随机选该装备面板上的一个属性，在其专属区间内随机 +N（区间见 AttributeDB.ENHANCE_RANGE）
##   - **大成功**：同一属性**连升两级**，两次都取区间最大值；强化等级 +2
##   - **失败**：不掉等级、不掉属性，只累加「磨损」；累计 10 次 → **破损**（强化永久停止）
## 当前装备强化一次消耗什么：仙器改用蕴仙髓 ×1；其余仍吃锻造晶石 ×品阶数。
## 2026-11-13 用户定：化神期仙器不再被境界锁挡，但要消耗蕴仙髓。
func enhance_currency(item: Dictionary) -> String:
	if String(item.get("equipment_type", "")) != "treasure" 			and String(item.get("equipment_grade", "")) == "仙器":
		return YUNXIAN_MATERIAL
	return ENHANCE_MATERIAL


func enhance_currency_cost(item: Dictionary) -> int:
	if String(item.get("equipment_type", "")) != "treasure" 			and String(item.get("equipment_grade", "")) == "仙器":
		return 1
	return ItemDB.enhance_crystal_cost(item)


## 磨损流水（2026-11-13 用户定）：每道磨损按发生顺序记一条：
##   {"k": "n"}                 普通敲击失败
##   {"k": "a", "g": "灵器"}    进阶失败，g = 失败当时的品阶（颜色不再随进阶改变）
## 老档没有流水 → 用两个计数合成「普通在前、进阶在后（用当前品阶）」，并写回装备。
func ensure_wear_seq(item: Dictionary) -> Array:
	var total := maxi(0, int(item.get("enhance_fail_count", 0)))
	var raw = item.get("enhance_wear_seq")
	if raw is Array and (not (raw as Array).is_empty() or total == 0):
		# 流水一旦存在就是唯一真相：计数跟着流水同步（防旧字段/调试写入不一致）
		var seq := raw as Array
		var asc := 0
		for e in seq:
			if e is Dictionary and String((e as Dictionary).get("k", "")) == "a":
				asc += 1
		item["enhance_fail_count"] = seq.size()
		item["enhance_ascend_fail_count"] = asc
		return seq
	var ascend := mini(total, maxi(0, int(item.get("enhance_ascend_fail_count", 0))))
	var seq: Array = []
	for i in total - ascend:
		seq.append({"k": "n"})
	for i in ascend:
		seq.append({"k": "a", "g": String(item.get("equipment_grade", ""))})
	item["enhance_wear_seq"] = seq
	return seq


##   - **进阶**（满 +10 后）：品阶 +1、等级归零，并按进阶前属性额外奖励 50%（2026-10-24 用户定）
##   - 未登记强化区间的属性不参与抽选（相当于该词条被锁定）
func enhance_item(item: Dictionary) -> Dictionary:
	var fail_ret := func(msg: String) -> Dictionary:
		return {
			"ok": false, "result": "", "delta": 0, "attr_gains": [],
			"grade_before": String(item.get("equipment_grade", "")),
			"grade_after": String(item.get("equipment_grade", "")),
			"enhance_before": int(item.get("enhancement_level", 0)),
			"enhance_after": int(item.get("enhancement_level", 0)),
			"fail_count": int(item.get("enhance_fail_count", 0)),
			"broken": bool(item.get("is_broken", false)),
			"message": msg, "extra_gain_text": "", "cost_consumed": false,
		}

	if String(item.get("type", "")) != ITEM_EQUIPMENT:
		return fail_ret.call("只能强化装备")
	# 禁令装备（彩蛋装 问天剑）：传家之物不吃锻打，境界再高也不解锁
	if ItemDB.has_equipment_flag(item, "cannot_enhance"):
		return fail_ret.call("%s是传家之物，不可强化" % String(item.get("name", "这件装备")))
	# 破损：仍可穿戴/召唤，但强化永久停止
	if bool(item.get("is_broken", false)):
		var label := "法宝" if String(item.get("equipment_type", "")) == "treasure" else "装备"
		return fail_ret.call("%s已破损，无法继续强化（可在锻造台分解）" % label)

	var grade := String(item.get("equipment_grade", ""))
	var enh := maxi(0, int(item.get("enhancement_level", 0)))
	# 神器（最高品阶）没有强化等级：不能再敲，也不走普通强化/进阶（2026-11-13 用户定）
	if ItemDB.is_max_grade(grade):
		if String(item.get("equipment_type", "")) == "treasure":
			return fail_ret.call("法宝已达最高品阶（%s），无法再进阶" % grade)
		return fail_ret.call("神器已成，无法再强化（神器没有强化等级）")
	# 仙器满 +10：普通敲击不再进阶，只能走铸神（2026-11-13 用户定）
	if enh >= ItemDB.MAX_ENHANCE \
			and ItemDB.is_max_grade(ItemDB.next_grade(grade)) \
			and String(item.get("equipment_type", "")) != "treasure":
		return fail_ret.call("仙器已满 +10：需在锻造台用「铸神晶」铸神（普通敲击不再进阶）")
	# 境界锁（2026-10-24 用户定）：到达当前境界允许的最高品阶后，整件装备停止强化
	# （用户选「全部锁死」：不是只锁进阶，+N 也不能再敲；突破后自动解锁）
	var realm_lock := ItemDB.realm_lock_message(grade, current_realm)
	if realm_lock != "":
		# 化神期「装备类仙器」例外（2026-11-13）：改用蕴仙髓继续淬炼；
		# 法宝与低境界仙器仍然按境界锁停敲。
		var xian_at_huashen := String(item.get("equipment_type", "")) != "treasure" 			and grade == "仙器" and normalize_realm_name(current_realm) == REALM_HUASHEN
		if not xian_at_huashen:
			return fail_ret.call(realm_lock)

	## 法宝只有进阶：不带属性词条，也不走普通 +N 强化（2026-11-01 用户定）
	var is_treasure := String(item.get("equipment_type", "")) == "treasure"
	var is_ascend := is_treasure or enh >= ItemDB.MAX_ENHANCE

	# 是不是「召唤法宝（BOSS 令）」：进阶改召唤物时长/加成
	var summon_tpl := ItemDB.get_treasure_template(String(item.get("id", "")))
	var is_summon_treasure := (not summon_tpl.is_empty()
		and String(summon_tpl.get("summon_boss_id", "")) != "")

	# 最高品阶不能再进阶（所有法宝/装备同一口径）
	if is_ascend and ItemDB.is_max_grade(grade):
		return fail_ret.call("已达最高品阶（%s），无法再进阶" % grade)

	# 材料检查：仙器吃蕴仙髓 ×1；其余按品阶递增吃锻造晶石（凡品 1 / 法器 2 / 灵器 3 …）
	var cost_id := enhance_currency(item)
	var cost_n := enhance_currency_cost(item)
	var have_cost := count_material(cost_id)
	if have_cost < cost_n:
		if cost_id == YUNXIAN_MATERIAL:
			return fail_ret.call(
				"蕴仙髓不足：本次需要 %d 枚（当前 %d 枚）。蕴仙髓出自主线 BOSS 首杀、万界塔 BOSS 与九天之上的祭坛"
				% [cost_n, have_cost])
		return fail_ret.call("锻造晶石不足：本次需要 %d 颗（当前 %d 颗），需在万界塔击杀投影获取" % [
			cost_n, have_cost])

	consume_materials({cost_id: cost_n})
	# 累计消耗只记锻造晶石（分解返还按它算）；蕴仙髓不参与返还
	if cost_id == ENHANCE_MATERIAL:
		item["enhance_crystal_spent"] = int(item.get("enhance_crystal_spent", 0)) + cost_n

	var grade_before := grade
	# 教学必成（2026-11-10 用户定）：c5 强化教学步激活期间（Tutorial runner 置位）
	# 固定 roll = 0.5 —— 落在「普通成功」区间 [大成功 0.05, 成功 0.85)，
	# 即必定 +1 级、不触发大成功也不磨损；其余场合一律真随机。
	var roll := 0.5 if force_enhance_success else randf()
	var result := ""
	var new_grade := grade
	var new_enh := enh
	var msg := ""
	var gains: Array = []
	var extra_gain_text := ""
	var fail_count := int(item.get("enhance_fail_count", 0))
	## 其中由「进阶失败」造成的磨损次数（2026-11-13 用户定：铭牌磨损刻度要分开着色）
	var ascend_fail_count := int(item.get("enhance_ascend_fail_count", 0))
	var success_count := int(item.get("enhance_success_count", 0))
	var broken := false
	var wear_seq := ensure_wear_seq(item)

	if is_ascend:
		# 进阶敲击：成功品阶 +1、等级归零；失败等级归零并计 1 道磨损
		# （2026-11-13 用户改：进阶失败也累计磨损、也会敲到破损）
		if roll < ItemDB.ENHANCE_SUCCESS_RATE:
			gains = _roll_ascend_gain(item)
			new_grade = ItemDB.next_grade(grade)
			new_enh = 0
			result = ItemDB.ENHANCE_RESULT_ASCEND
			msg = "进阶成功！%s → %s" % [grade_before, new_grade]
			if is_treasure:
				msg += "（法宝主动效果增强）"
				extra_gain_text = "法宝主动效果随品阶增强"
			else:
				msg += "（等级归零，属性保留）"
			if not gains.is_empty():
				msg += "　%s" % _gains_text(gains)
			# 召唤法宝：每次进阶成功固定加召唤物时长与气血/攻击（2026-11-01 改为进阶唯一成长）
			if is_summon_treasure:
				item["summon_ascend_boost_pct"] = float(item.get("summon_ascend_boost_pct", 0.0)) \
					+ SUMMON_ASCEND_BOOST_PER_GRADE
				var boost_after := _summon_boost_pct(item)
				item["summon_duration_bonus"] = int(item.get("summon_duration_bonus", 0)) + 1
				var extra := float(item["summon_duration_bonus"]) * SUMMON_DURATION_PER_ASCEND
				msg += "　召唤物 +%d%%，时长 +%d 秒（累计 +%.1f%%，+%d 秒）" % [
					int(SUMMON_ASCEND_BOOST_PER_GRADE), int(SUMMON_DURATION_PER_ASCEND),
					boost_after, int(extra)]
				extra_gain_text = "召唤物加成 +%d%%（累计 +%.1f%%）" % [
					int(SUMMON_ASCEND_BOOST_PER_GRADE), boost_after]
		else:
			new_enh = 0
			# 2026-11-13 用户定：装备进阶失败也累计磨损、也会敲到破损。
			# 法宝不记磨损（品阶就是唯一成长线，铭牌也不显示磨损刻度）→ 不参与。
			if not is_treasure:
				fail_count += 1
				ascend_fail_count += 1
				wear_seq.append({"k": "a", "g": grade_before})
				broken = fail_count >= ItemDB.ENHANCE_FAIL_LIMIT
			result = ItemDB.ENHANCE_RESULT_BROKEN if broken \
				else ItemDB.ENHANCE_RESULT_ASCEND_FAIL
			msg = "进阶失败……品阶不变（法宝不会掉阶）" if is_treasure \
				else "进阶失败……%s 等级清零（品阶不变，已获得的属性保留）" % grade_before
			if not is_treasure:
				msg += "　磨损 %d / %d" % [fail_count, ItemDB.ENHANCE_FAIL_LIMIT]
				if broken:
					msg += "（装备破损！强化已永久停止）"
	else:
		# 普通敲击：大成功 5% / 成功 80% / 失败 15%
		if roll < ItemDB.ENHANCE_GREAT_RATE:
			new_enh = mini(enh + ItemDB.ENHANCE_GREAT_STEP, ItemDB.MAX_ENHANCE)
			gains = _roll_attribute_gain(item, ItemDB.ENHANCE_GREAT_STEP, true)
			result = ItemDB.ENHANCE_RESULT_GREAT
			# 按词条强化次数记：大成功一次加两条词条，就记 2 次
			success_count += new_enh - enh
			msg = "大成功！%s　（强化 +%d → +%d）" % [_gains_text(gains), enh, new_enh]
		elif roll < ItemDB.ENHANCE_GREAT_RATE + ItemDB.ENHANCE_SUCCESS_RATE:
			new_enh = mini(enh + 1, ItemDB.MAX_ENHANCE)
			gains = _roll_attribute_gain(item, 1, false)
			result = ItemDB.ENHANCE_RESULT_SUCCESS
			success_count += new_enh - enh
			msg = "强化成功！%s　（强化 +%d → +%d）" % [_gains_text(gains), enh, new_enh]
		else:
			# 失败：不扣等级、不扣属性，只加磨损
			fail_count += 1
			wear_seq.append({"k": "n"})
			broken = fail_count >= ItemDB.ENHANCE_FAIL_LIMIT
			result = ItemDB.ENHANCE_RESULT_BROKEN if broken else ItemDB.ENHANCE_RESULT_FAIL
			if broken:
				msg = "装备破损！强化已永久停止，可到锻造台分解返还晶石"
			else:
				msg = "强化失败……磨损 %d / %d（等级与属性未变）" % [
					fail_count, ItemDB.ENHANCE_FAIL_LIMIT
				]

	item["equipment_grade"] = new_grade
	item["enhancement_level"] = new_enh
	item["enhance_fail_count"] = fail_count
	item["enhance_ascend_fail_count"] = ascend_fail_count
	item["enhance_success_count"] = success_count
	if broken:
		item["is_broken"] = true
	# 攻击力加成已停用（强化只加属性），这里保留派生字段便于旧存档/UI 直读
	item["attack_bonus"] = ItemDB.compute_attack_bonus(item)

	return {
		"ok": true, "result": result, "delta": new_enh - enh,
		"success_count": success_count,
		"attr_gains": gains,
		"grade_before": grade_before, "grade_after": new_grade,
		"enhance_before": enh, "enhance_after": new_enh,
		"fail_count": fail_count, "broken": broken,
		"is_treasure": is_treasure,
		"message": msg, "extra_gain_text": extra_gain_text, "cost_consumed": true,
	}


## 随机提升装备属性 times 次，每次在区间内取值（use_max = 大成功时直接取上限）
## 返回 [{ "attr_id": String, "amount": float }]，并已把加值写进 item["attributes"]
## ⚠ 关键：先把候选属性**收集好**再抽，
##   否则边抽边写会把刚加过的属性重复计入候选，导致「同一属性连抽两次」。
# ===== 铸神 / 补天（2026-11-13 用户定）=====

## 铸神：满 +10 的仙器 + 铸神晶 ×1 → 神器/先天至宝。
## 神器没有强化等级（等级清零、磨损清零），此后 enhance_item 一律拒绝。
## 法宝不参加（法宝没有 +N 强化，成长线是进阶），破损装备 / 非仙器 / 未满 +10 也拒绝。
func forge_divine(item: Dictionary) -> Dictionary:
	var fail_ret := func(msg: String) -> Dictionary:
		return {"ok": false, "message": msg, "grade_before": String(item.get("equipment_grade", "")),
			"grade_after": String(item.get("equipment_grade", ""))}
	if String(item.get("type", "")) != ITEM_EQUIPMENT:
		return fail_ret.call("只有装备可以铸神")
	if String(item.get("equipment_type", "")) == "treasure":
		return fail_ret.call("法宝不铸神 —— 法宝的成长线是进阶")
	if bool(item.get("is_broken", false)):
		return fail_ret.call("装备已破损，无法铸神（先补天或分解）")
	var grade := String(item.get("equipment_grade", ""))
	if grade != "仙器":
		return fail_ret.call("只有仙器才能铸神（当前 %s）" % (grade if grade != "" else "无品阶"))
	if int(item.get("enhancement_level", 0)) < ItemDB.MAX_ENHANCE:
		return fail_ret.call("仙器要先强化到 +%d 才能铸神（当前 +%d）" % [
			ItemDB.MAX_ENHANCE, int(item.get("enhancement_level", 0))])
	var have := count_material(DIVINE_MATERIAL)
	if have < 1:
		return fail_ret.call("铸神晶不足：需要 1 枚（当前 %d 枚）。铸神晶出自大世界的铸神祭坛" % have)
	consume_materials({DIVINE_MATERIAL: 1})
	item["equipment_grade"] = "神器/先天至宝"
	item["enhancement_level"] = 0
	# 磨损流水保留：神器不再强化，旧痕仍要在铭牌上看得见（2026-11-13 用户定）
	item["is_broken"] = false
	item["attack_bonus"] = ItemDB.compute_attack_bonus(item)
	return {
		"ok": true,
		"message": "铸神成功！%s → 神器/先天至宝（神器没有强化等级，不再参与强化）" % grade,
		"grade_before": grade,
		"grade_after": "神器/先天至宝",
	}


## 补天：补天石 ×1 清掉**普通敲击失败**留下的磨损；进阶失败造成的磨损保留。
## 破损装备只要普通磨损还没清完，也能补回可强化状态（进阶失败磨损单独保留）。
func mend_item(item: Dictionary) -> Dictionary:
	var fail_ret := func(msg: String) -> Dictionary:
		return {"ok": false, "message": msg, "cleared": 0}
	if String(item.get("type", "")) != ITEM_EQUIPMENT:
		return fail_ret.call("只有装备需要补天")
	if String(item.get("equipment_type", "")) == "treasure":
		return fail_ret.call("法宝没有磨损，不需要补天")
	if ItemDB.is_max_grade(String(item.get("equipment_grade", ""))):
		return fail_ret.call("神器不再参与强化，旧痕留在铭牌上，无需补天")
	var fail_count := maxi(0, int(item.get("enhance_fail_count", 0)))
	var ascend_fail := mini(fail_count, maxi(0, int(item.get("enhance_ascend_fail_count", 0))))
	var normal_wear := fail_count - ascend_fail
	if normal_wear <= 0:
		return fail_ret.call("没有普通失败造成的磨损可补（进阶失败的磨损清不掉）")
	var have := count_material(MEND_MATERIAL)
	if have < 1:
		return fail_ret.call("补天石不足：需要 1 枚（当前 %d 枚）。补天石出自化神后的铸神祭坛" % have)
	consume_materials({MEND_MATERIAL: 1})
	# 删掉所有普通磨损流水，进阶失败的那几条按原顺序保留
	var seq_before := ensure_wear_seq(item)
	var kept: Array = []
	for e in seq_before:
		if e is Dictionary and String((e as Dictionary).get("k", "")) == "a":
			kept.append((e as Dictionary).duplicate(true))
	var cleared: int = seq_before.size() - kept.size()
	item["enhance_wear_seq"] = kept
	ascend_fail = kept.size()
	item["enhance_fail_count"] = ascend_fail
	item["enhance_ascend_fail_count"] = ascend_fail
	item["is_broken"] = ascend_fail >= ItemDB.ENHANCE_FAIL_LIMIT
	var msg := "补天成功：清掉普通磨损 %d 道（余 %d / %d）" % [
		cleared, ascend_fail, ItemDB.ENHANCE_FAIL_LIMIT]
	if ascend_fail > 0:
		msg += "；进阶失败留下的 %d 道磨损无法清除" % ascend_fail
	return {"ok": true, "message": msg, "cleared": cleared,
		"fail_count": ascend_fail, "broken": bool(item.get("is_broken", false))}


func _roll_attribute_gain(item: Dictionary, times: int, use_max: bool) -> Array:
	var attrs = item["attributes"]
	if not (attrs is Dictionary) or attrs.is_empty():
		return []
	var pool: Array[String] = []
	for k in attrs.keys():
		var key := String(k)
		if AttributeDB.can_enhance(key):
			pool.append(key)
	if pool.is_empty():
		return []

	var gains: Array = []
	var pick_idx := randi() % pool.size()
	for i in times:
		var key := pool[pick_idx]
		var amount := AttributeDB.roll_enhance_amount(key, use_max)
		if amount <= 0.0:
			continue
		attrs[key] = float(attrs[key]) + amount
		gains.append({"attr_id": key, "amount": amount})
	return gains


## 进阶成功奖励：每个可强化词条按**进阶前的当前值**额外 +50%（2026-10-24 用户定）
## 直接写进 item["attributes"]，增量放进 attr_gains → 状态行与铁砧飘字都能显示具体数值。
func _roll_ascend_gain(item: Dictionary) -> Array:
	var attrs = item.get("attributes")
	if not (attrs is Dictionary) or attrs.is_empty():
		return []
	var gains: Array = []
	for k in attrs.keys():
		var key := String(k)
		if not AttributeDB.can_enhance(key):
			continue
		var before := float(attrs[k])
		if before <= 0.0:
			continue
		var amount := _half_rounded(before)
		if amount <= 0.0:
			continue
		attrs[key] = before + amount
		gains.append({"attr_id": key, "amount": amount})
	return gains


## 取一半并保留 1 位小数（与属性 / 飘字的显示精度一致）
func _half_rounded(value: float) -> float:
	return roundf(value * 0.5 * 10.0) / 10.0


## 召唤法宝当前的总加成百分比（强化级数 ×2% + 历次进阶额外加成）
func _summon_boost_pct(item: Dictionary) -> float:
	return float(maxi(0, int(item.get("summon_boost_count", 0)))) * float(SUMMON_BOOST_PER_LEVEL) \
		+ float(item.get("summon_ascend_boost_pct", 0.0))


## 强化结果里的属性提升文案：「力量 +2、力量 +2」
func _gains_text(gains: Array) -> String:
	if gains.is_empty():
		return "（该装备无可强化词条）"
	var parts: Array[String] = []
	for g in gains:
		var key := String(g.get("attr_id", ""))
		# ⚠ `_signed_value` 自己就带正负号（返回 "+1.4"），这里不能再手写 "+"，
		#    否则会出现「速度 ++1.4」这种双加号。
		parts.append("%s %s" % [
			AttributeDB.attr_name(key), ItemDB._signed_value(key, float(g.get("amount", 0.0)))
		])
	return "、".join(parts)


# ===== 分解（锻造台）=====

## 分解一件装备：返还「累计消耗晶石的一半」，返回返还数量（0 = 不予分解）
## 规则（用户 2026-10-17）：分解返还只算**晶石**，已获得的属性随装备一起消失。
## 破损装备可分解；未破损装备也允许分解（玩家自弃时的兜底）。
## ⚠ 禁令装备（彩蛋装 问天剑）一律不给分解。**判定要留在调用方之外**：
##   砧上的装备此时已经脱离背包，只靠 UI 隐藏按钮的话，任何别的路径都能把它吞掉。
func can_dismantle_item(item: Dictionary) -> bool:
	if item.is_empty() or String(item.get("type", "")) != ITEM_EQUIPMENT:
		return false
	return not ItemDB.has_equipment_flag(item, "cannot_dismantle")


func dismantle_item(item: Dictionary) -> int:
	if String(item.get("type", "")) != ITEM_EQUIPMENT:
		return 0
	if not can_dismantle_item(item):
		return 0
	var refund := ItemDB.dismantle_refund(item)
	if refund > 0:
		grant_material(ENHANCE_MATERIAL, refund)
	return refund


# ===== 物理伤害公式 =====
## 普通攻击伤害。走 DamageCalc 统一公式：
##   伤害 = 物理攻击力 × 招式倍率 × (1 − 目标物抗减免) × 目标易伤 × 随机浮动
## 物理攻击力由「力量」换算而来（见 physical_attack）。
##
## ⚠ 功法系数不再计入普通攻击：功法有独立施放路径（见 calc_skill_damage）。
##
## is_finisher  连击第三段·终结技
## is_followup  弹反追击窗口内的首段（奖励伤害）
## use_random   是否附加 ±5% 随机浮动
## ⚠ 目标抗性由**受击方**在 take_damage 里扣（见 DamageCalc.incoming），
##   这里只算「打在 0 抗目标上的伤害」，避免投射物等异步路径漏算。
func calc_physical_damage(is_finisher: bool = false, has_parry_buff: bool = false,
		use_random: bool = true) -> float:
	# 招式倍率（终结技 / 弹刀增伤 buff）
	var move_coeff := 1.0
	if is_finisher:
		move_coeff *= ItemDB.FINISHER_COEFF
	# 弹刀增伤是**次数型**：调用方负责在命中后消费，这里只读不消耗
	if has_parry_buff:
		move_coeff *= ItemDB.PARRY_DAMAGE_BUFF_COEFF

	var ctx := {
		"phys_power": physical_attack(),
		# 兵器系数与全局功法基线并进物理系数，避免污染法术乘区
		"phys_coeff": move_coeff * ItemDB.WEAPON_COEFF * ItemDB.SKILL_DAMAGE_COEFF,
		"random": use_random,
	}
	return float(DamageCalc.resolve(ctx).get("amount", 0.0)) * sun_damage_mult


# ===== 功法（招式）=====

## 2026-10-31：符箓占 4 个功法格。槽内用前缀区分功法 id 与符箓 item_id。
const TALISMAN_SLOT_PREFIX := "talisman:"

static func is_talisman_slot(slot_value: String) -> bool:
	return slot_value.begins_with(TALISMAN_SLOT_PREFIX)


static func talisman_slot_item_id(slot_value: String) -> String:
	return slot_value.trim_prefix(TALISMAN_SLOT_PREFIX) if is_talisman_slot(slot_value) else ""


static func talisman_slot_value(item_id: String) -> String:
	return TALISMAN_SLOT_PREFIX + item_id if item_id != "" else ""


## 4 格通用显示：功法取 SkillDB，符箓取 ItemDB。
## ⚠ 试炼四符的槽值是**裸 base id**（`talisman:tal_jinfeng`），ItemDB 里查不到 ——
##   只查 ItemDB 会让技能栏四格全显示成「符箓」+ 占位字，玩家分不出哪张是哪张。
static func active_slot_display_name(slot_value: String) -> String:
	if is_talisman_slot(slot_value):
		var tid := talisman_slot_item_id(slot_value)
		var nm := String(ItemDB.get_consumable(tid).get("talisman_name", ""))
		if nm != "":
			return nm
		return TalismanDB.display_name(tid) if not TalismanDB.base_def(tid).is_empty() else "符箓"
	if slot_value == "":
		return ""
	return SkillDB.get_skill_name(slot_value)


static func active_slot_display_icon(slot_value: String) -> String:
	if is_talisman_slot(slot_value):
		var tid := talisman_slot_item_id(slot_value)
		var ic := String(ItemDB.get_consumable(tid).get("icon", ""))
		if ic == "" and not TalismanDB.base_def(tid).is_empty():
			ic = ArtDB.talisman_icon(tid)
		return ic
	if slot_value == "":
		return ""
	return String(SkillDB.get_skill(slot_value).get("icon", ""))


func active_slot_talisman_count(slot_value: String) -> int:
	return talisman_count(talisman_slot_item_id(slot_value)) if is_talisman_slot(slot_value) else -1


## 战斗内主动功法槽（固定 4 格，保留空槽；下标即 Q/E/R/T）
## 空槽用 "" 占位，避免「把技能从 Q 换到 T」时后面的键位整体前移。
func equipped_active_skills() -> Array:
	var out: Array = []
	for i in MAX_ACTIVE_SKILLS:
		var id := String(active_skill_loadout[i]) if i < active_skill_loadout.size() else ""
		if is_talisman_slot(id):
			var tid := talisman_slot_item_id(id)
			# 符箓格保留原值；数量读背包，0 张也保留格子（显示 0）。
			# ⚠ 2026-11-10 用户报「选了符箓流派但按 Q/E/R/T 放不出符」：
			#   这里原来只查 ItemDB，而试炼四符的槽值是**裸 base_id**
			#   （talisman:tal_jinfeng），它在 ItemDB 里查不到 —— 于是四格全被
			#   append("")，_poll_skill_keys() 逐格 `if sid == "": continue` 静默吞键。
			#   HUD 直接读 active_skill_loadout 不过滤，所以「看得见符、按不出来」。
			#   两类符都要保留：
			#     · 局外七元灵符 = 带品质档的 item_id（tal_jinfeng_lianqi），ItemDB 查得到；
			#     · 试炼四符 = 裸 base_id，只在 TalismanDB 里，靠 base_def 兜住。
			if not ItemDB.get_consumable(tid).is_empty() \
					or not TalismanDB.base_def(tid).is_empty():
				out.append(id)
			else:
				out.append("")
		elif id != "" and id in learned_skills and SkillDB.is_type_active(id):
			out.append(id)
		else:
			out.append("")
	return out


## 从当前境界修为里扣制作符箓的消耗；不够返回 false，不扣。
func spend_realm_exp(amount: float) -> bool:
	var need := maxf(0.0, amount)
	if need > 0.0 and realm_exp < need:
		return false
	realm_exp = maxf(0.0, realm_exp - need)
	return true


## 制作符箓：修为 + 现有材料；同级/更低 100%，越一级 5%，越两级不可做。
## 批量绘制按张独立判定成功率；失败也扣该张的材料与修为。
## 返回结果供 UI 显示（success = 至少成 1 张）。
func craft_talisman(recipe: Dictionary, count: int = 1) -> Dictionary:
	var n := maxi(1, count)
	var item_id := String(recipe.get("talisman_id", ""))
	if item_id == "":
		return {"ok": false, "message": "配方无效"}
	var realm := String(recipe.get("realm", ""))
	var rate := ItemDB.talisman_success_rate(realm)
	if rate <= 0.0:
		return {"ok": false, "message": "越两级，无法制作%s" % realm}
	if not bool(recipe.get("uses_realm_success", false)) \
			and not is_recipe_known("talisman", String(recipe.get("recipe_id", ""))):
		return {"ok": false, "message": "尚未领悟这道符方"}
	var mats: Dictionary = recipe.get("materials", {})
	var scaled := {}
	for k in mats.keys():
		scaled[String(k)] = int(mats[k]) * n
	if not has_materials(scaled):
		return {"ok": false, "message": "材料不足"}
	var cost := ItemDB.talisman_cultivation_cost(recipe) * float(n)
	if realm_exp < cost:
		return {"ok": false, "message": "修为不足（需要 %d）" % int(cost)}
	consume_materials(scaled)
	spend_realm_exp(cost)
	var success_count := 0
	for i in range(n):
		if randf() <= rate:
			success_count += 1
	var fail_count := n - success_count
	if success_count > 0:
		add_talisman(item_id, success_count)
	var msg := ""
	if success_count == n:
		msg = "符成！%s ×%d 收入符匣" % [String(recipe.get("talisman_name", item_id)), n]
	elif success_count <= 0:
		msg = ("制符失败 ×%d，材料与修为已消耗（成功率 %d%%）" % [n, int(round(rate * 100.0))]) \
			if n > 1 else ("制符失败，材料与修为已消耗（成功率 %d%%）" % int(round(rate * 100.0)))
	else:
		msg = "符成 ×%d（收入符匣）· 失败 ×%d（成功率 %d%%）" % [
			success_count, fail_count, int(round(rate * 100.0))]
	return {
		"ok": true,
		"success": success_count > 0,
		"success_count": success_count,
		"fail_count": fail_count,
		"attempts": n,
		"rate": rate,
		"cost": cost,
		"message": msg,
	}


## 已装配的主动功法数量（不计空槽）
func active_skill_count() -> int:
	var n := 0
	for sid in active_skill_loadout:
		if String(sid) != "":
			n += 1
	return n


## 功法伤害：物理段吃物理攻击力，法术段吃法术攻击力（详见 DamageCalc）
## 与 BOSS 用同一招时的伤害是**两套独立计算**：
##   BOSS 侧走 MoveDB.boss_damage()（× BOSS 自身攻击力）
##   玩家侧走本函数（× 玩家当前属性）
##
## ⚠ 目标抗性由受击方在 take_damage 里扣，这里算的是「0 抗目标伤害」
func calc_skill_damage(skill_id: String, use_random: bool = true, has_parry_buff: bool = false) -> float:
	var phys_c := SkillDB.get_phys_coeff(skill_id)
	var spell_c := SkillDB.get_spell_coeff(skill_id)
	if phys_c <= 0.0 and spell_c <= 0.0:
		return 0.0

	# 弹刀增伤 buff 只作用于**物理段**（法术功法不吃这个增伤）
	var buff := ItemDB.PARRY_DAMAGE_BUFF_COEFF if has_parry_buff else 1.0

	var ctx := {
		"phys_power": physical_attack(),
		"spell_power": spell_attack(),
		# 兵器系数与全局基线并进物理系数，避免污染法术乘区
		"phys_coeff": phys_c * buff * ItemDB.WEAPON_COEFF * ItemDB.SKILL_DAMAGE_COEFF \
			* sword_intent_skill_mult,
		# 法技增伤只进法术系数：物理功法、普攻、召唤物等不会吃到
		"spell_coeff": spell_c * ItemDB.SKILL_DAMAGE_COEFF * spell_skill_damage_mult(),
		"random": use_random,
	}
	return float(DamageCalc.resolve(ctx).get("amount", 0.0)) * sun_damage_mult


## 功法消耗：{ cost_kind, mana_cost, stamina_cost, cooldown }
func skill_cost(skill_id: String) -> Dictionary:
	return SkillDB.get_skill_cost(skill_id)


## 判定能否使用某个主动功法
## current_mana     当前灵力
## cooldown_left    该功法剩余冷却（秒）
## current_stamina  当前精力格数（cost_kind = stamina 时需要）
## form_skill_id    可选：实际施展形态的技能 id（一剑开天满层会切法术变体，
##                  消耗按变体口径校验；习得/装配/冷却仍认原技能）。空 = 用技能自身形态
## 返回 { ok: bool, reason: String, cost: Dictionary }
func can_use_skill(skill_id: String, current_mana: float,
		cooldown_left: float = 0.0, current_stamina: int = 999,
		form_skill_id: String = "") -> Dictionary:
	var cost := skill_cost(form_skill_id if form_skill_id != "" else skill_id)
	var result := {"ok": false, "reason": "", "cost": cost}

	var skill := SkillDB.get_skill(skill_id)
	if skill.is_empty():
		result["reason"] = "功法不存在"
		return result
	if String(skill.get("skill_type", "")) != SkillDB.TYPE_ACTIVE:
		result["reason"] = "该功法不是主动功法"
		return result
	if not (skill_id in learned_skills):
		result["reason"] = "尚未习得该功法"
		return result
	if not (skill_id in active_skill_loadout):
		result["reason"] = "尚未装配该功法"
		return result
	if cooldown_left > 0.0:
		result["reason"] = "冷却中（%.1f 秒）" % cooldown_left
		return result

	# 抽空整条资源的大招（一剑开天双形态）：至少得有 1 点可掏，否则等于免费放
	if bool(cost.get("stamina_all", false)) and current_stamina < 1:
		result["reason"] = "精力不足"
		return result
	if bool(cost.get("mana_all", false)) and current_mana < 1.0:
		result["reason"] = "灵力不足"
		return result

	var kind := String(cost.get("cost_kind", MoveDB.COST_NONE))
	match kind:
		MoveDB.COST_MANA:
			var need := float(cost.get("mana_cost", 0.0))
			if current_mana < need:
				result["reason"] = "灵力不足（需 %.0f，当前 %.0f）" % [need, current_mana]
				return result
		MoveDB.COST_STAMINA:
			var need_s := int(cost.get("stamina_cost", 0))
			if current_stamina < need_s:
				result["reason"] = "精力不足"
				return result
		_:
			pass

	result["ok"] = true
	return result


# ===== 背包 =====

## 背包物品结构：{ id, name, type, count, desc, grade }
## 返回是否成功放入（堆叠或占新格）
func add_item(item: Dictionary) -> bool:
	var item_id := String(item.get("id", ""))
	var def := ItemDB.get_consumable(item_id)
	# 符箓例外：不进背包，统一进符匣库存（背包格只装丹药 / 材料 / 装备）
	if String(item.get("type", "")) == ITEM_TALISMAN \
			or (not def.is_empty() and String(def.get("kind", "")) == "talisman"):
		return add_talisman(item_id, int(item.get("count", 1)))
	if not bag_has_room(item):
		return false
	var stack_idx := _find_stackable(item)
	if stack_idx >= 0:
		inventory[stack_idx]["count"] = int(inventory[stack_idx].get("count", 1)) + int(item.get("count", 1))
	else:
		inventory.append(item.duplicate())
	mark_codex_from_item(item)
	# 「首次获得」红点：这件东西这辈子第一次进背包才亮（2026-11-12 用户定）
	mark_bag_new(item_id)
	# 新手指引：背包红点只认「有没看过的新东西」，打开背包时清零（见 Tutorial）
	tutorial_data["unseen_items"] = int(tutorial_data.get("unseen_items", 0)) + int(item.get("count", 1))
	# ⚠ CharacterData 比 Tutorial 先注册（autoload 顺序），这里不能直接写 Tutorial.note
	var tut := get_node_or_null("/root/Tutorial")
	if tut != null:
		tut.note("item_gained")
		# 教学「合成指引」（2026-11-12 用户定）：**只有拿到能参与合成的材料**才触发，
		# 排队触发（不打断手上的章）；做完/跳过之后本章没有未完成步骤 → 不再触发。
		if not ItemDB.synth_hint_lines(item_id).is_empty():
			tut.call("request_chapter_by_trigger", "event:craft_material")
	return true


# ===== 符匣库存 =====

func talisman_count(item_id: String) -> int:
	if item_id == "":
		return 0
	return maxi(0, int(talisman_stock.get(item_id, 0)))


## 符箓入手：只记符匣，不占背包格。返回是否成功。
func add_talisman(item_id: String, count: int = 1) -> bool:
	if item_id == "" or count <= 0:
		return false
	talisman_stock[item_id] = talisman_count(item_id) + count
	return true


## 消耗符匣里的符箓；不够返回 false，不扣。
func consume_talisman(item_id: String, count: int = 1) -> bool:
	if item_id == "" or count <= 0:
		return false
	var have := talisman_count(item_id)
	if have < count:
		return false
	var left := have - count
	if left <= 0:
		talisman_stock.erase(item_id)
	else:
		talisman_stock[item_id] = left
	return true


## 旧档把符箓存在背包里：读档时整堆移进符匣，背包只留丹药 / 材料 / 装备。
func migrate_talismans_to_cabinet() -> int:
	var moved := 0
	for i in range(inventory.size() - 1, -1, -1):
		var it = inventory[i]
		if not (it is Dictionary):
			continue
		var iid := String((it as Dictionary).get("id", ""))
		var def := ItemDB.get_consumable(iid)
		var is_talisman := String((it as Dictionary).get("type", "")) == ITEM_TALISMAN \
			or (not def.is_empty() and String(def.get("kind", "")) == "talisman")
		if not is_talisman:
			continue
		add_talisman(iid, int((it as Dictionary).get("count", 1)))
		inventory.remove_at(i)
		moved += 1
	return moved


## 背包丢弃白名单：突破材料 / 传家之物 / 珍贵材料（铸神晶、补天石）不可丢，其余都可丢。
func can_discard_item(item: Dictionary) -> bool:
	return not item.is_empty() and discard_lock_reason(item) == ""


## 不可丢弃的原因（空串 = 可丢）；背包按钮直接用这句
func discard_lock_reason(item: Dictionary) -> String:
	if item.is_empty():
		return ""
	var iid := String(item.get("id", ""))
	if ItemDB.has_equipment_flag(item, "cannot_discard"):
		return "传家之物"
	if ItemDB.is_breakthrough_material(iid):
		return "突破材料"
	if bool(ItemDB.get_material(iid).get("cannot_discard", false)):
		return "珍贵材料"
	return ""


func remove_item_at(index: int, count: int = 1) -> void:
	if index < 0 or index >= inventory.size():
		return
	var left := int(inventory[index].get("count", 1)) - count
	if left <= 0:
		inventory.remove_at(index)
	else:
		inventory[index]["count"] = left


## 背包一键整理（2026-10-24 用户定）
## 排序：装备 → 丹药 → 符箓 → 材料；同类里品质高在前，再按强化 / 名称 / id 稳定排序。
## 只重排数组，不合并 / 删除任何物品；快捷轮盘与穿戴槽按 id / 引用保存，不受影响。
const INVENTORY_SORT_TYPE_ORDER := {
	ITEM_EQUIPMENT: 0,
	ITEM_PILL: 1,
	ITEM_TALISMAN: 2,
	ITEM_MATERIAL: 3,
}
const INVENTORY_SORT_EQUIP_TYPE_ORDER := {
	"weapon": 0, "armor": 1, "shoes": 2, "accessory": 3, "treasure": 4,
}


func sort_inventory() -> void:
	inventory.sort_custom(_inventory_sort_less)


func _inventory_sort_less(a: Dictionary, b: Dictionary) -> bool:
	var ta := int(INVENTORY_SORT_TYPE_ORDER.get(String(a.get("type", "")), 9))
	var tb := int(INVENTORY_SORT_TYPE_ORDER.get(String(b.get("type", "")), 9))
	if ta != tb:
		return ta < tb

	# 品质：装备用品阶，其它用稀有度（稀有度映射到同一套七色序列的前五档）
	var qa := _inventory_quality_rank(a)
	var qb := _inventory_quality_rank(b)
	if qa != qb:
		return qa > qb

	# 装备：强化等级高在前；同等级按部位（武器/护甲/鞋子/饰品/法宝）
	if ta == 0:
		var ea := int(a.get("enhancement_level", 0))
		var eb := int(b.get("enhancement_level", 0))
		if ea != eb:
			return ea > eb
		var pa := int(INVENTORY_SORT_EQUIP_TYPE_ORDER.get(String(a.get("equipment_type", "")), 9))
		var pb := int(INVENTORY_SORT_EQUIP_TYPE_ORDER.get(String(b.get("equipment_type", "")), 9))
		if pa != pb:
			return pa < pb

	var na := _inventory_sort_name(a)
	var nb := _inventory_sort_name(b)
	if na != nb:
		return na < nb
	return String(a.get("id", "")) < String(b.get("id", ""))


func _inventory_quality_rank(item: Dictionary) -> int:
	if String(item.get("type", "")) == ITEM_EQUIPMENT:
		return ItemDB.grade_index(String(item.get("equipment_grade", "")))
	var rarity := ItemDB.item_rarity(item)
	return ItemDB.grade_index(String(ItemDB.RARITY_GRADE.get(rarity, "")))


func _inventory_sort_name(item: Dictionary) -> String:
	if String(item.get("type", "")) == ITEM_EQUIPMENT:
		return ItemDB.equipped_display_name(item)
	return String(item.get("name", ""))


## 可堆叠的同类同 id 格位索引（装备不可堆叠）
func _find_stackable(item: Dictionary) -> int:
	var itype := String(item.get("type", ""))
	if itype == ITEM_EQUIPMENT:
		return -1
	var iid := String(item.get("id", ""))
	for i in range(inventory.size()):
		if String(inventory[i].get("id", "")) == iid and String(inventory[i].get("type", "")) == itype:
			return i
	return -1


## 按**分背包**取物品：法宝（equipment + equipment_type==treasure）单独成一类，
## 因此 ITEM_EQUIPMENT 这一档不再混进法宝（2026-11-02 用户要独立法宝页签）。
## 传空 / "all" 仍返回全部，留给仓库整理等整体遍历用。
func get_items_by_type(item_type: String) -> Array:
	if item_type.is_empty() or item_type == "all":
		return inventory.duplicate()
	var out: Array = []
	for it in inventory:
		if bag_category_of(it as Dictionary) == item_type:
			out.append(it)
	return out


func count_item(item_id: String) -> int:
	var total := 0
	for it in inventory:
		if String(it.get("id", "")) == item_id:
			total += int(it.get("count", 1))
	return total


## 消耗一个指定道具（丹药 / 符箓），成功返回 true
func consume_item(item_id: String) -> bool:
	for i in range(inventory.size()):
		if String(inventory[i].get("id", "")) != item_id:
			continue
		remove_item_at(i, 1)
		return true
	return false


# ===== 战斗轮盘装配（丹药 3 + 符箓 3，2026-10-24 用户定）=====

## 2026-10-31：符箓改为占 4 个功法格，战斗轮盘只保留丹药。
const QUICK_SLOT_ORDER: Array = ["pill_1", "pill_2", "pill_3"]


func quick_item_id(slot_id: String) -> String:
	return String(quick_slots.get(slot_id, ""))


## 某个物品装在哪个槽（没装返回空串）
func quick_slot_of(item_id: String) -> String:
	if item_id == "":
		return ""
	for sid in QUICK_SLOT_ORDER:
		if String(quick_slots.get(sid, "")) == item_id:
			return String(sid)
	return ""


## 某类（pill / talisman）三格里第一个空格；全满返回空串
func first_free_quick_slot(item_type: String) -> String:
	var prefix := "pill_" if item_type == ITEM_PILL else "talisman_"
	for i in range(1, 4):
		var sid := "%s%d" % [prefix, i]
		if String(quick_slots.get(sid, "")) == "":
			return sid
	return ""


## 装配：槽位类型必须对得上（pill_* 只放丹药），同一种道具不能占两格
func set_quick_slot(slot_id: String, item_id: String) -> bool:
	if not quick_slots.has(slot_id):
		return false
	var def := ItemDB.get_consumable(item_id)
	if def.is_empty():
		return false
	if slot_id.begins_with("pill_") != (String(def.get("kind", "")) == ITEM_PILL):
		return false
	if quick_slot_of(item_id) != "":
		return false
	quick_slots[slot_id] = item_id
	return true


func clear_quick_slot(slot_id: String) -> void:
	if quick_slots.has(slot_id):
		quick_slots[slot_id] = ""


## 清掉指向已不存在道具的槽（配方表改动 / 旧档脏数据兜底）
func prune_quick_slots() -> void:
	for sid in QUICK_SLOT_ORDER:
		var iid := quick_item_id(String(sid))
		if iid != "" and ItemDB.get_consumable(iid).is_empty():
			quick_slots[sid] = ""


# ===== 材料 =====

func count_material(material_id: String) -> int:
	var total := 0
	for it in inventory:
		if String(it.get("id", "")) == material_id:
			total += int(it.get("count", 1))
	return total


func grant_material(material_id: String, count: int) -> void:
	var def := ItemDB.get_material(material_id)
	add_item({
		"id": material_id,
		"name": String(def.get("name", material_id)),
		"type": ITEM_MATERIAL,
		"count": count,
		"icon": String(def.get("icon", "")),
		"desc": String(def.get("desc", "")),
	})


## 必得材料发放：背包满了也一定塞进去（核心首领首杀奖励用）
## ⚠ 普通 grant_material 在背包满且没有同类堆叠时会静默失败。
##   破境材料是突破的唯一来源、而核心首领只能杀一次 —— 一旦发放失败就是永久死锁。
##   这里优先堆叠；实在没地方就允许超出该分背包的上限占一格（软上限，UI 能正常显示）。
func grant_material_guaranteed(material_id: String, count: int) -> void:
	var def := ItemDB.get_material(material_id)
	var item := {
		"id": material_id,
		"name": String(def.get("name", material_id)),
		"type": ITEM_MATERIAL,
		"count": count,
		"icon": String(def.get("icon", "")),
		"desc": String(def.get("desc", "")),
	}
	var stack_idx := _find_stackable(item)
	if stack_idx >= 0:
		inventory[stack_idx]["count"] = int(inventory[stack_idx].get("count", 1)) + count
		mark_codex_from_item(item)
		return
	inventory.append(item.duplicate())
	mark_codex_from_item(item)
	if bag_count_for(ITEM_MATERIAL) > bag_cap_for(ITEM_MATERIAL):
		push_warning("材料背包已满，必得材料强制入包：" + material_id)


## 检查材料是否足够（不扣除）
func has_materials(materials: Dictionary) -> bool:
	for k in materials.keys():
		if count_material(String(k)) < int(materials[k]):
			return false
	return true


## 扣除材料：全部足够才扣，返回是否成功
func consume_materials(materials: Dictionary) -> bool:
	if not has_materials(materials):
		return false
	for k in materials.keys():
		_consume_one_material(String(k), int(materials[k]))
	return true


func _consume_one_material(material_id: String, count: int) -> void:
	var left := count
	for i in range(inventory.size()):
		if left <= 0:
			break
		if String(inventory[i].get("id", "")) == material_id:
			var have := int(inventory[i].get("count", 1))
			var take := mini(have, left)
			inventory[i]["count"] = have - take
			left -= take
	# 清理数量为 0 的格位
	for i in range(inventory.size() - 1, -1, -1):
		if int(inventory[i].get("count", 1)) <= 0:
			inventory.remove_at(i)


# ===== 丹方 / 符方（炼丹 F / 制符 G）=====

func _recipe_store(kind: String) -> Dictionary:
	return alchemy_progress if kind == "pill" else talisman_crafting_progress


func get_recipe_state(kind: String, recipe_id: String) -> String:
	var entry = _recipe_store(kind).get(recipe_id, {})
	return String(entry.get("state", RECIPE_UNKNOWN))


func is_recipe_known(kind: String, recipe_id: String) -> bool:
	return get_recipe_state(kind, recipe_id) == RECIPE_KNOWN


## 领悟配方（正式流程：满足条件后解锁；当前为基础功能，直接领悟）
func learn_recipe(kind: String, recipe_id: String) -> void:
	var store := _recipe_store(kind)
	if not store.has(recipe_id):
		store[recipe_id] = {"state": RECIPE_UNKNOWN, "proficiency": 0.0}
	store[recipe_id]["state"] = RECIPE_KNOWN


func get_proficiency(kind: String, recipe_id: String) -> float:
	var entry = _recipe_store(kind).get(recipe_id, {})
	return float(entry.get("proficiency", 0.0))


## 熟练度：每次炼制成功累加，影响成功率与产出（上限 1.0）
func add_proficiency(kind: String, recipe_id: String, amount: float) -> void:
	var store := _recipe_store(kind)
	if not store.has(recipe_id):
		store[recipe_id] = {"state": RECIPE_UNKNOWN, "proficiency": 0.0}
	store[recipe_id]["proficiency"] = minf(float(store[recipe_id]["proficiency"]) + amount, 1.0)


# ===== 灵田（home_progress / tilled_plots）=====

## 种着东西的地块必然已开垦；旧档里有作物的地也当已开垦，不用再踏一遍
func is_plot_tilled(plot_index: int) -> bool:
	if not get_plot(plot_index).is_empty():
		return true
	return bool(tilled_plots.get(plot_index, false))


func till_plot(plot_index: int) -> void:
	tilled_plots[plot_index] = true
	var tut := get_node_or_null("/root/Tutorial")
	if tut != null:
		tut.note("farm_tilled")


func plant_plot(plot_index: int, seed_id: String, grow_seconds: int = 60) -> void:
	home_progress[plot_index] = {
		"seed_id": seed_id,
		"planted_at": Time.get_unix_time_from_system(),
		"grow_seconds": grow_seconds,
	}


func get_plot(plot_index: int) -> Dictionary:
	return home_progress.get(plot_index, {})


func clear_plot(plot_index: int) -> void:
	home_progress.erase(plot_index)


## 剩余成熟秒数（已成熟返回 0）
func plot_remaining_seconds(plot_index: int) -> int:
	var p := get_plot(plot_index)
	if p.is_empty():
		return 0
	var elapsed := Time.get_unix_time_from_system() - int(p.get("planted_at", 0))
	return maxi(0, int(p.get("grow_seconds", 0)) - int(elapsed))


func is_plot_ready(plot_index: int) -> bool:
	var p := get_plot(plot_index)
	return (not p.is_empty()) and plot_remaining_seconds(plot_index) <= 0


## 收获：成熟则产出 2 份该材料并清空地块
func harvest_plot(plot_index: int) -> String:
	if not is_plot_ready(plot_index):
		return ""
	var seed_id := String(get_plot(plot_index).get("seed_id", ""))
	clear_plot(plot_index)
	if seed_id == "":
		return ""
	grant_material(seed_id, 2)
	return seed_id


# ===== 万界塔（D）=====

## 塔层是否已解锁 —— **自动判定，无需手动解锁**
##
## 规则（2026-10-17 用户定）：**在万界秘境击败第 N 层的对应 BOSS，第 N 层立刻开放**。
## 一名 BOSS 对应一层，不再依赖「整个位面是否通关」。
## 旧存档中曾手动解锁的层仍然保持开放（兼容）。
func is_tower_floor_unlocked(floor_no: int) -> bool:
	var e = tower_progress.get(floor_no, {})
	if bool(e.get("unlocked", false)):
		return true
	return _tower_floor_unlock_condition_met(floor_no)


## 塔层解锁条件是否满足（不含旧存档兼容标记）
## = 该层对应的那名 BOSS 已在它的位面里被击杀
func _tower_floor_unlock_condition_met(floor_no: int) -> bool:
	var f := WorldDB.get_floor(floor_no)
	if f.is_empty():
		return false
	var domain_id := String(f.get("domain_id", ""))
	var boss_id := String(f.get("boss_id", ""))
	if domain_id == "" or boss_id == "":
		return false
	return is_boss_cleared(domain_id, boss_id)


## 强制解锁某层（剧情脚本 / 调试用；正常流程无需调用）
func unlock_tower_floor(floor_no: int) -> void:
	if not tower_progress.has(floor_no):
		tower_progress[floor_no] = {"unlocked": false, "first_kill": false}
	tower_progress[floor_no]["unlocked"] = true


## 塔层尚未开放的原因（已开放返回空串），供 UI 直接显示
func tower_floor_lock_reason(floor_no: int) -> String:
	if is_tower_floor_unlocked(floor_no):
		return ""
	var f := WorldDB.get_floor(floor_no)
	if f.is_empty():
		return "层数不存在"
	var domain_id := String(f.get("domain_id", ""))
	var boss_id := String(f.get("boss_id", ""))
	if boss_id == "":
		return "未开放"
	return "需先在「%s」击败 %s" % [WorldDB.get_domain_name(domain_id), WorldDB.get_boss_name(boss_id)]


func is_tower_first_kill_done(floor_no: int) -> bool:
	var e = tower_progress.get(floor_no, {})
	return bool(e.get("first_kill", false))


## 记录首杀：返回是否首次
## ⚠ 2026-10-17 用户改定：**重复通关也能感悟功法**，首杀现在只用于面板区分「首通 / 再战」，
##   不再决定有没有功法（旧规则「重复击杀不再获得」已作废）。
func mark_tower_first_kill(floor_no: int) -> bool:
	if is_tower_first_kill_done(floor_no):
		return false
	if not tower_progress.has(floor_no):
		tower_progress[floor_no] = {"unlocked": true, "first_kill": false, "clear_count": 0}
	tower_progress[floor_no]["first_kill"] = true
	return true


## 某层已经通关过多少次（用于晶石掉落梯度：首通 9 / 第二次 6 / 之后 3）
## 旧存档只有 first_kill 标记、没有 clear_count：按「已通关 1 次」算，
## 免得老玩家下一次通关被当成首通白拿 9 块晶石。
func get_tower_clear_count(floor_no: int) -> int:
	var e = tower_progress.get(floor_no, {})
	var c := int(e.get("clear_count", 0))
	if c <= 0 and bool(e.get("first_kill", false)):
		return 1
	return c


# ===== 万界塔反复挑战的血量成长（用户 2026-10-21 定）=====
## 同一层每**通关**一次，下一次挑战的血量上限 +「基础血量的 10%」，最多 +100%（2 倍封顶）。
## 例（虎妖基础 800）：第 1 次 800 → 第 2 次 880 …… 第 11 次 1600，之后恒为 1600。
## ⚠ 规则只写在这里：战斗侧（combat_arena）与塔面板（tower_panel）都调用它，改一处即可
const TOWER_HP_STEP := 0.1
const TOWER_HP_STEP_MAX := 10

## 通关时间**只记录**第几次及以后的挑战（2026-10-22 用户定：只记双倍血量的场次）
## 血量倍率 2.0 出现在「已通关 10 次」之后的第 11 次挑战，所以阈值就是 11
const TOWER_RECORD_MIN_CLEAR := 11
## 无伤通关奖励（2026-10-24 用户定）：任意一次通关全程未掉血 → 每层一次 50 晶石
## 不再与通关用时 / 第 11 次挑战挂钩；用时纪录仍按 TOWER_RECORD_MIN_CLEAR 单独统计。
const TOWER_NO_HIT_BONUS_CRYSTALS := 50

## 某层下一次挑战的血量倍率（1.0 = 基础血量，2.0 = 封顶）
func tower_hp_multiplier(floor_no: int) -> float:
	var clears := get_tower_clear_count(floor_no)
	return 1.0 + TOWER_HP_STEP * float(mini(clears, TOWER_HP_STEP_MAX))


## 第 challenge_no 次挑战（1-based）**开打时**的血量倍率。
## ⚠ 通关结算时 clear_count 已经 +1，不能再拿 tower_hp_multiplier() 判断刚打完那场；
##   元魂等「双倍血量场次」掉落必须用这个函数对 challenge_no 查。
func tower_hp_multiplier_at(challenge_no: int) -> float:
	var prior := maxi(0, challenge_no - 1)
	return 1.0 + TOWER_HP_STEP * float(mini(prior, TOWER_HP_STEP_MAX))


## 该层下一次是第几次挑战（已通关 N 次 → 第 N+1 次）
func tower_challenge_index(floor_no: int) -> int:
	return get_tower_clear_count(floor_no) + 1


# ===== 元魂唯一性（2026-10-21 用户定）=====

## 这种元魂是否已经获得过 —— 获得过就不再掉落（每种只掉一次）
func has_obtained_soul(soul_id: String) -> bool:
	return soul_id in obtained_souls


## 记录一次元魂获得（拾取时调用；幂等）
## ⚠ 在**拾取时**记，不是掉落时：万一掉落物没捡到（战斗结束直接返回），
##   下次还能再掉一次，不会让玩家永久错过这件法宝
func mark_soul_obtained(soul_id: String) -> void:
	if soul_id != "" and not (soul_id in obtained_souls):
		obtained_souls.append(soul_id)


# ===== 图鉴解锁（2026-10-25 用户定）=====

## 永久记录「获得过」某件图鉴条目；重复调用无副作用
func mark_codex_unlocked(item_id: String) -> void:
	if item_id == "" or codex_unlocked.has(item_id):
		return
	codex_unlocked[item_id] = true


func is_codex_unlocked(item_id: String) -> bool:
	return bool(codex_unlocked.get(item_id, false))


## 物品真正入手时调用（只登记装备 / 法宝 / 材料，丹药符箓不进图鉴）
func mark_codex_from_item(item: Dictionary) -> void:
	var t := String(item.get("type", ""))
	if t != ITEM_EQUIPMENT and t != ITEM_MATERIAL and t != ITEM_TREASURE:
		return
	mark_codex_unlocked(String(item.get("id", "")))


## 旧存档补录：按当前持有物、开局发放记录与元魂获得记录回填。
## 已经消耗掉、又没有获得记录的材料无法追溯，这是旧档迁移的固有上限。
func rebuild_codex_from_owned() -> int:
	var before := codex_unlocked.size()
	for it in inventory:
		if it is Dictionary:
			mark_codex_from_item(it)
	for slot in SLOT_ORDER:
		var eq = equipment_slots.get(slot)
		if eq is Dictionary:
			mark_codex_from_item(eq)
	for tslot in TREASURE_SLOT_ORDER:
		var tr = treasure_slots.get(tslot)
		if tr is Dictionary:
			mark_codex_from_item(tr)
	for sid in obtained_souls:
		mark_codex_unlocked(String(sid))
	# 开局装备 / 法宝即使已被卖掉或分解，也属于「一定获得过」
	if starting_equipment_granted:
		for tpl in ItemDB.get_starting_equipment():
			mark_codex_unlocked(String((tpl as Dictionary).get("equipment_id", "")))
	if starting_treasure_granted:
		for tpl in ItemDB.get_starting_treasures():
			mark_codex_unlocked(String((tpl as Dictionary).get("treasure_id", "")))
	return codex_unlocked.size() - before


## 记录一次通关，返回「本次是第几次通关」（1 = 首通）
## ⚠ 在**结算瞬间**就记（晶石要立刻掉在地上），功法与首杀标记仍然等玩家确认后才写。
func record_tower_clear(floor_no: int) -> int:
	if not tower_progress.has(floor_no):
		tower_progress[floor_no] = {"unlocked": true, "first_kill": false, "clear_count": 0}
	var next := get_tower_clear_count(floor_no) + 1
	tower_progress[floor_no]["clear_count"] = next
	return next


# ===== 万界位面（C）=====

## 界域是否已解锁 —— **自动判定，无需手动解锁**
##
## 规则：无前置界域（首域）默认开放；其余只要「前置界域全部 BOSS 通关」即自动开放。
## 也就是说：打过前一关，下一关立即自动开放。
##
## ⚠ 境界要求不再阻挡解锁：境界不足时**允许硬打**，由 UI 给出风险提示（用户确认的设计）。
## 旧存档中曾手动解锁的界域仍然保持开放（兼容）。
func is_domain_unlocked(domain_id: String) -> bool:
	var e = domain_progress.get(domain_id, {})
	if bool(e.get("unlocked", false)):
		return true
	return _domain_unlock_condition_met(domain_id)


## 界域解锁条件是否满足（不含旧存档兼容标记）
## 只检查「前置界域是否全部通关」，境界不参与（境界仅作难度提示）
func _domain_unlock_condition_met(domain_id: String) -> bool:
	var d := WorldDB.get_domain(domain_id)
	if d.is_empty():
		return false
	var prev := String(d.get("prev_domain", ""))
	if prev == "":
		return true
	return is_domain_cleared(prev)


## 界域境界是否达标（仅供 UI 提示；不达标仍可硬打）
func is_domain_realm_ok(domain_id: String) -> bool:
	return WorldDB.meets_realm_requirement(domain_id, current_realm)

## 强制解锁某界域（剧情脚本 / 调试用；正常流程无需调用）
func unlock_domain(domain_id: String) -> void:
	if not domain_progress.has(domain_id):
		domain_progress[domain_id] = {"unlocked": false, "cleared_bosses": []}
	domain_progress[domain_id]["unlocked"] = true


## 界域尚未开放的原因（已开放返回空串），供 UI 直接显示
func domain_lock_reason(domain_id: String) -> String:
	if is_domain_unlocked(domain_id):
		return ""
	var d := WorldDB.get_domain(domain_id)
	if d.is_empty():
		return "界域不存在"
	var prev := String(d.get("prev_domain", ""))
	if prev != "" and not is_domain_cleared(prev):
		return "需先通关 %s" % WorldDB.get_domain_name(prev)
	return "未开放"


func is_boss_cleared(domain_id: String, boss_id: String) -> bool:
	var e = domain_progress.get(domain_id, {})
	return String(boss_id) in e.get("cleared_bosses", [])


## 通关条件：该界域全部 BOSS 均已击杀
## ⚠ boss_ids 为空（界域暂无内容，例如守关 BOSS 尚未设计）时视为**未通关**，
##   否则「没有 BOSS」会被当成「全部击杀」，导致下一界域/塔层被误解锁。
func is_domain_cleared(domain_id: String) -> bool:
	var domain := WorldDB.get_domain(domain_id)
	if domain.is_empty():
		return false
	var boss_ids: Array = domain.get("boss_ids", [])
	if boss_ids.is_empty():
		return false
	for b in boss_ids:
		if not is_boss_cleared(domain_id, String(b)):
			return false
	return true


## 守关者**按序挑战**（2026-11-12 用户定）：`boss_ids` 的数组顺序就是挑战顺序
## （凡界 = 虎妖 → 刀客 → 剑客），只有「本界第一个还没斩的」那一格能进；
## 已经斩过的**永远放行**（老档里跳着打过的人不会被收回入口）。
## 境界不参与判定 —— 境界不足仍可硬闯是既有设计，由 UI 给风险提示。
func is_boss_challengeable(domain_id: String, boss_id: String) -> bool:
	if not is_domain_unlocked(domain_id):
		return false
	if is_boss_cleared(domain_id, boss_id):
		return true
	for b in WorldDB.get_domain(domain_id).get("boss_ids", []):
		var bid := String(b)
		if bid == String(boss_id):
			break
		if not is_boss_cleared(domain_id, bid):
			return false
	return true


## 本界「现在该打的那一位」= 第一个还没斩的；全斩完返回空串
func domain_next_boss(domain_id: String) -> String:
	for b in WorldDB.get_domain(domain_id).get("boss_ids", []):
		var bid := String(b)
		if not is_boss_cleared(domain_id, bid):
			return bid
	return ""


## 不能挑战的原因（能打 = 空串），供界面直接显示。
## ⚠ 点名的是**当前该打的那一位**，不是「上一位」—— 跳着看的时候，
##   玩家要知道下一步去哪，而不是知道自己还差几层。
func boss_lock_reason(domain_id: String, boss_id: String) -> String:
	if is_boss_challengeable(domain_id, boss_id):
		return ""
	if not is_domain_unlocked(domain_id):
		return domain_lock_reason(domain_id)
	var gate := domain_next_boss(domain_id)
	if gate == "":
		return "未开放"
	return "需先击败 %s" % WorldDB.get_boss_name(gate)


## BOSS 连败提醒：记同一只 BOSS 连续战败次数，返回计入后的次数
## streak_key 由战斗侧给（位面 = boss_id，塔 = "tower_层号"）；空串 = 不统计（演武场）
func add_boss_fail(streak_key: String) -> int:
	if streak_key == "":
		return 0
	var count := int(boss_fail_streak.get(streak_key, 0)) + 1
	boss_fail_streak[streak_key] = count
	return count


func get_boss_fail(streak_key: String) -> int:
	return int(boss_fail_streak.get(streak_key, 0))


func clear_boss_fail(streak_key: String) -> void:
	boss_fail_streak.erase(streak_key)


## 位面 BOSS 死亡记录：键包含位面，避免不同位面复用 boss_id 时串号
func boss_death_key(domain_id: String, boss_id: String) -> String:
	if domain_id == "" or boss_id == "":
		return ""
	return domain_id + "/" + boss_id


func add_boss_death(domain_id: String, boss_id: String) -> int:
	var key := boss_death_key(domain_id, boss_id)
	if key == "":
		return 0
	var count := int(boss_death_count.get(key, 0)) + 1
	boss_death_count[key] = count
	return count


func get_boss_death(domain_id: String, boss_id: String) -> int:
	var key := boss_death_key(domain_id, boss_id)
	return int(boss_death_count.get(key, 0)) if key != "" else 0


func get_boss_first_clear_deaths(domain_id: String, boss_id: String) -> int:
	var key := boss_death_key(domain_id, boss_id)
	return int(boss_first_clear_deaths.get(key, 0)) if key != "" else 0


## 首通快照：只写一次；重复通关不会覆盖首通时的死亡次数
func record_boss_first_clear_deaths(domain_id: String, boss_id: String) -> int:
	var key := boss_death_key(domain_id, boss_id)
	if key == "":
		return 0
	if not boss_first_clear_deaths.has(key):
		boss_first_clear_deaths[key] = get_boss_death(domain_id, boss_id)
	return int(boss_first_clear_deaths.get(key, 0))


## 记录 BOSS 击杀，返回是否首次击杀（§2.7 真实位面 BOSS 才产生万界本源）
func mark_boss_killed(domain_id: String, boss_id: String) -> bool:
	if not domain_progress.has(domain_id):
		domain_progress[domain_id] = {"unlocked": false, "cleared_bosses": []}
	var cleared: Array = domain_progress[domain_id]["cleared_bosses"]
	var first := String(boss_id) not in cleared
	if first:
		cleared.append(String(boss_id))
		var bp = boss_progress.get(String(boss_id), {})
		if not bool(bp.get("first_kill", false)):
			boss_progress[String(boss_id)] = {"killed": true, "first_kill": true}
			origin_energy += 1.0
		# 首杀必得的门票类材料（破境天髓）直接进背包：走地面掉落会被死亡吞掉，
		# 玩家就得重打一遍照影界才能再开门，那是死档不是难度。
		_grant_first_kill_reward(String(boss_id))
		# 主线 BOSS 首杀：蕴仙髓 ×1（2026-11-13 用户定）。必得材料，背包满也强制入包。
		grant_material_guaranteed(YUNXIAN_MATERIAL, 1)
		# 通关整个界域则推进剧情进度，记忆碎片解锁依赖它（§5.7）
		if is_domain_cleared(domain_id):
			story_progress = maxi(story_progress, _domain_story_index(domain_id))
			# 位面首通：补天石 ×1（2026-11-13 用户定）。必得材料，背包满也强制入包。
			# 只会在「最后一位 BOSS 的首次击杀」那一拍触发，重复击杀走不到这里。
			grant_material_guaranteed(MEND_MATERIAL, 1)
	return first


## 发放某 BOSS 的首杀必得材料（表见 ItemDB.FIRST_KILL_REWARDS）
func _grant_first_kill_reward(boss_id: String) -> void:
	for k in ItemDB.get_first_kill_reward(boss_id):
		grant_material_guaranteed(String(k), int(ItemDB.get_first_kill_reward(boss_id)[k]))


## 自愈补发：已经打过、但背包里缺门票的玩家（死前丢包 / 更早的存档）重新补齐。
## 每次进大世界都跑一遍，和核心首领的 _ensure_core_reward 同一套口径。
func ensure_first_kill_rewards() -> void:
	for boss_id in ItemDB.FIRST_KILL_REWARDS:
		var bp = boss_progress.get(String(boss_id), {})
		if not bool((bp as Dictionary).get("first_kill", false)):
			continue
		var rewards: Dictionary = ItemDB.get_first_kill_reward(String(boss_id))
		for k in rewards:
			var need := int(rewards[k])
			var have := count_material(String(k))
			if have < need:
				grant_material_guaranteed(String(k), need - have)


## 记录万界塔某层的通关用时，返回是否刷新了该层最快纪录
## 只有比历史最好成绩更快才覆盖；没有纪录时也视为刷新
##
## ⚠ 2026-10-22 用户定：**只记录第 11 次及以后的挑战**（= 血量翻倍的场次）。
##   前 10 次的成绩不再计入（老纪录若存在则保留，直到被更快成绩刷新）。
##   无伤通关奖励已与用时脱钩，见 mark_tower_no_hit_reward。
func record_tower_clear_time(floor_no: int, seconds: float) -> bool:
	if floor_no <= 0 or seconds <= 0.0:
		return false
	# 入账时 clear_count 已含本次通关（resolve_victory 先记），所以本次挑战序号 = clear_count
	if get_tower_clear_count(floor_no) < TOWER_RECORD_MIN_CLEAR:
		return false
	var prev := get_tower_best_time(floor_no)
	var is_first := prev < 0.0
	if not (is_first or seconds < prev):
		return false
	tower_best_time[floor_no] = seconds
	return true


## 某层无伤奖励状态："" = 无奖励 / "ready" = 可领 / "claimed" = 已领
func tower_no_hit_reward_state(floor_no: int) -> String:
	return String(tower_no_hit_reward.get(floor_no, ""))


## 记录一次无伤通关：该层还没有奖励状态时置为 ready。
## 返回是否**本次新解锁**（已 ready / 已 claimed 都返回 false）。
## 任意一次通关都可触发，不再要求第 11 次或某个用时门槛。
## 无伤通关「双倍气血」场次（纯华彩卡解锁）；只记事实，奖励仍走 tower_no_hit_reward
func mark_tower_no_hit_double(floor_no: int) -> void:
	if floor_no > 0:
		tower_no_hit_double[floor_no] = true


func has_tower_no_hit_double(floor_no: int) -> bool:
	return bool(tower_no_hit_double.get(floor_no, false))


func mark_tower_no_hit_reward(floor_no: int) -> bool:
	if floor_no <= 0:
		return false
	if tower_no_hit_reward.has(floor_no):
		return false
	tower_no_hit_reward[floor_no] = "ready"
	return true


## 领取某层的无伤通关奖励（选关界面调用）：返回实际领到的晶石数（0 = 没得领）
func claim_tower_no_hit_reward(floor_no: int) -> int:
	if tower_no_hit_reward_state(floor_no) != "ready":
		return 0
	tower_no_hit_reward[floor_no] = "claimed"
	grant_material(ENHANCE_MATERIAL, TOWER_NO_HIT_BONUS_CRYSTALS)
	return TOWER_NO_HIT_BONUS_CRYSTALS


## 非普通卡解锁奖励：每张卡只能领一次 50 锻造晶石。
func is_card_reward_claimed(boss_id: String, card_id: String) -> bool:
	return bool(card_reward_claimed.get("%s/%s" % [boss_id, card_id], false))


func claim_card_reward(boss_id: String, card_id: String) -> int:
	if boss_id == "" or card_id == "" or card_id == "portrait":
		return 0
	var key := "%s/%s" % [boss_id, card_id]
	if bool(card_reward_claimed.get(key, false)):
		return 0
	card_reward_claimed[key] = true
	grant_material_guaranteed(ENHANCE_MATERIAL, CARD_UNLOCK_BONUS_CRYSTALS)
	return CARD_UNLOCK_BONUS_CRYSTALS


# ===== 大世界核心首领重战（塔内分支）=====
## 与塔层同一套血量成长 / 双倍血卡 / 无伤卡规则，但不占塔层号。
func _core_replay_entry(region_id: String) -> Dictionary:
	if not core_replay.has(region_id):
		core_replay[region_id] = {
			"clear_count": 0,
			"no_hit_double": false,
			"no_hit_rewarded": false,
		}
	return core_replay[region_id]


func get_core_clear_count(region_id: String) -> int:
	var e = core_replay.get(region_id, {})
	return int((e as Dictionary).get("clear_count", 0)) if e is Dictionary else 0


## 记一次核心重战胜利，返回新的通关次数
func record_core_clear(region_id: String) -> int:
	var e := _core_replay_entry(region_id)
	var n := int(e.get("clear_count", 0)) + 1
	e["clear_count"] = n
	return n


## 记录核心重战最快用时（秒），返回是否刷新纪录。
## 与塔层同口径：只记双倍气血场次（第 TOWER_RECORD_MIN_CLEAR 次及以后）。
func record_core_clear_time(region_id: String, seconds: float) -> bool:
	if region_id == "" or seconds <= 0.0:
		return false
	if get_core_clear_count(region_id) < TOWER_RECORD_MIN_CLEAR:
		return false
	var e := _core_replay_entry(region_id)
	var prev := float(e.get("best_time", -1.0))
	if prev >= 0.0 and seconds >= prev:
		return false
	e["best_time"] = seconds
	return true


## 核心重战最快用时；没有纪录返回 -1.0
func get_core_best_time(region_id: String) -> float:
	var e = core_replay.get(region_id, {})
	return float((e as Dictionary).get("best_time", -1.0)) if e is Dictionary else -1.0


## 下一次重战的血量倍率：每胜一次 +10%，最多 2 倍（与塔层同口径）
func core_hp_multiplier(region_id: String) -> float:
	var clears := get_core_clear_count(region_id)
	return 1.0 + TOWER_HP_STEP * float(mini(clears, TOWER_HP_STEP_MAX))


func core_challenge_index(region_id: String) -> int:
	return get_core_clear_count(region_id) + 1


func mark_core_no_hit_double(region_id: String) -> void:
	var e := _core_replay_entry(region_id)
	e["no_hit_double"] = true


func has_core_no_hit_double(region_id: String) -> bool:
	var e = core_replay.get(region_id, {})
	return bool((e as Dictionary).get("no_hit_double", false)) if e is Dictionary else false


func core_no_hit_rewarded(region_id: String) -> bool:
	var e = core_replay.get(region_id, {})
	return bool((e as Dictionary).get("no_hit_rewarded", false)) if e is Dictionary else false


## 核心首领无伤通关：每个区域一次 50 晶石（与塔层无伤奖同额）。
## 返回本次实际发放数量；已领过返回 0。
func grant_core_no_hit_reward(region_id: String) -> int:
	var e := _core_replay_entry(region_id)
	if bool(e.get("no_hit_rewarded", false)):
		return 0
	e["no_hit_rewarded"] = true
	grant_material(ENHANCE_MATERIAL, TOWER_NO_HIT_BONUS_CRYSTALS)
	return TOWER_NO_HIT_BONUS_CRYSTALS


## 取万界塔某层最快通关时间；没有纪录返回 -1.0
func get_tower_best_time(floor_no: int) -> float:
	if not tower_best_time.has(floor_no):
		return -1.0
	return float(tower_best_time[floor_no])


## 秒 → "MM:SS.d"；负数（无纪录）返回 "—"
static func format_duration(seconds: float) -> String:
	if seconds < 0.0:
		return "—"
	# 先整体换算到十分之一秒再拆分，避免 30.2 这种值被浮点误差算成 30.1
	var tenths := int(round(seconds * 10.0))
	var m := tenths / 600
	var s := (tenths / 10) % 60
	var d := tenths % 10
	return "%02d:%02d.%d" % [m, s, d]


## 界域在列表中的序号（从 1 起），用作剧情进度刻度
func _domain_story_index(domain_id: String) -> int:
	for i in range(WorldDB.DOMAINS.size()):
		if String(WorldDB.DOMAINS[i].get("domain_id", "")) == domain_id:
			return i + 1
	return 0


# ===== 记忆幻像（H）=====

func is_memory_unlocked(fragment_id: String) -> bool:
	var e = memory_progress.get(fragment_id, {})
	return bool(e.get("is_unlocked", false))


func unlock_memory(fragment_id: String) -> void:
	if not memory_progress.has(fragment_id):
		memory_progress[fragment_id] = {"is_unlocked": false, "playback_state": "未回放"}
	memory_progress[fragment_id]["is_unlocked"] = true


func get_memory_playback_state(fragment_id: String) -> String:
	var e = memory_progress.get(fragment_id, {})
	return String(e.get("playback_state", "未回放"))


func mark_memory_played(fragment_id: String) -> void:
	if not memory_progress.has(fragment_id):
		memory_progress[fragment_id] = {"is_unlocked": true, "playback_state": "未回放"}
	memory_progress[fragment_id]["playback_state"] = "已回放"


# ===== 启动初始化 =====

func _ready() -> void:
	# 开局自带装备：因为 CharacterData 是最早注册的 autoload 之一，
	# 这里跑在 main_scene（原初位面）之前，UI 一打开就能看到已装备的铁剑。
	# 已有存档时随后会被 SaveManager.load_slot → apply() 整体覆盖，
	# 因此本行的效果只在「全新档」可见（apply 会把标记一并读回来）。
	ensure_starting_equipment()
	ensure_starting_treasures()
