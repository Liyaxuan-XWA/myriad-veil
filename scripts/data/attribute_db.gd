class_name AttributeDB
extends RefCounted
## 属性定义表 —— 项目里「有哪些属性、怎么显示、怎么参与计算」的唯一来源
##
## ============================ 设计要点 ============================
## 1. 属性 id 是**字符串**，存档里也是字符串键，新增属性不会破坏旧档。
## 2. 每个属性只有「定义」，没有「数值」。数值来自三层聚合：
##       玩家基础（CharacterData.base_attributes）
##     + 装备 / 法宝属性（ItemDB 条目的 attributes 字典）
##     + 临时修正（buff / debuff，见 CharacterData.attribute_mods）
##    全部相加后再乘临时倍率，结果由 CharacterData.attribute(id) 返回。
## 3. 抗性不是「百分比减伤」，而是**递减收益**的数值：
##       减免率 = 抗性 / (抗性 + RESIST_K)，上限 MAX_REDUCTION
##    这样抗性可以一直成长而不会溢出到 100%。
##
## ⚠ 本表只定义属性本身；具体由谁提供、提供多少，分别在
##   CharacterData（基础）与 ItemDB（装备/法宝）里。

# ===== 属性 id 常量（避免各处写死字符串拼错）=====
const ATTR_HP_MAX := "hp_max"                    ## 气血上限
const ATTR_SPEED := "speed"                      ## 速度（移动）
const ATTR_STRENGTH := "strength"                ## 力量（增强物理伤害）
const ATTR_SPELL_POWER := "spell_power"          ## 法强（增强法术伤害）
## 法技增伤（2026-10-24 用户定）：只增强法术功法的直接伤害，不影响普攻 / 召唤等非功法伤害
const ATTR_SPELL_SKILL_DAMAGE_PCT := "spell_skill_damage_pct"
const ATTR_ATTACK_SPEED := "attack_speed"        ## 攻速（百分比，提高普攻频率）
const ATTR_PHYSICAL_RESIST := "physical_resist"  ## 物抗
const ATTR_MAGIC_RESIST := "magic_resist"        ## 法抗（总体）
const ATTR_MANA_MAX := "mana_max"                ## 灵力上限
const ATTR_MANA_REGEN := "mana_regen"            ## 灵力恢复（每秒）
const ATTR_STAMINA_MAX := "stamina_max"          ## 精力格数
const ATTR_STAMINA_REGEN := "stamina_regen"      ## 精力恢复（每秒格数）
# ---------- 百分比增幅词条（2026-10-19 用户调价新增）----------
## 命名约定：<基础属性>_pct，值 1.0 = 该基础属性 +1%（乘算，见 CharacterData.attribute）
## ⚠ 这两个不是独立属性，是「挂在基础属性上的百分比词条」：
##   装备/法宝/临时修正里写 stamina_regen_pct: 1.0 → 精力恢复最终值 ×1.01
const ATTR_STAMINA_REGEN_PCT := "stamina_regen_pct"  ## 精力恢复速度（百分比）
const ATTR_SPEED_PCT := "speed_pct"                  ## 移动速度（百分比）

# ===== 分类 =====
const CAT_BASE := "base"
const CAT_RESIST := "resist"
const CAT_RESOURCE := "resource"

## 分类顺序（面板按此顺序分组显示）
const CATEGORIES: Array = [
	{"id": CAT_BASE, "name": "基础属性"},
	{"id": CAT_RESIST, "name": "抗性"},
	{"id": CAT_RESOURCE, "name": "资源"},
]

## 五行 + 风雷 + 暗（法抗的细分维度）
## 暗 = 照影界投影一路（影身 / 光束 / 影没），2026-11-05 从「水」里分出来：
## 影系原本挂水，是因为它读起来冷；但观澜（镜）也挂水，两支在同界撞成同一个抗性维度。
const ELEMENTS: Array[String] = ["metal", "wood", "water", "fire", "earth", "wind", "thunder", "dark"]
const ELEMENT_NAMES: Dictionary = {
	"metal": "金",
	"wood": "木",
	"water": "水",
	"fire": "火",
	"earth": "土",
	"wind": "风",
	"thunder": "雷",
	"dark": "暗",
	"ice": "冰",
	"light": "光",
	"none": "无",
}

# ===== 抗性减免曲线 =====
## 减免率 = 抗性 / (抗性 + RESIST_K)。K 越大，堆抗性收益越平缓。
const RESIST_K := 100.0
## 减免率上限，防止抗性无限堆叠后免疫
const MAX_REDUCTION := 0.9

# ===== 暗属性的专属规则（2026-11-05 用户定）=====
## 暗 = **通用属性**，不是任何一只 BOSS 媒介的附属：规则挂在「这一击的元素是暗」上，
## 不挂在 form.debuff_on_hit 上 —— 所以将来任何暗来源（别的 BOSS、符箓、装备特效）自动生效。
## 任何暗属性命中 → 目标挂「蚀」两条效果：
##   ① 物抗 / 法抗 / 元素抗三类**减免数值**先 ×(1-SHRED) 再进减免曲线；
##   ② 期间受到的治疗只剩 HEAL_MULT（用户定减疗 90%）。
## 与已有「易伤」(DebuffDB.damage_taken_mult，6 条在用) 的分工要说清：
## 易伤是**无条件乘伤**（你防多少都多挨三成），蚀是**按你堆的减免按比例吃掉**：
##   抗 0 → 完全无感；抗 40 → 多挨 12.9%；抗 100 → +25%；抗 200 → +36.6%。
## 所以暗的定位是「破硬」—— 高抗 BOSS 与堆抗流的解，不是又一档增伤。
const DARK := "dark"
const DARK_EROSION_ID := "dark_erosion"
const DARK_EROSION_TIME := 6.0                 ## 基础持续（还会按目标暗抗缩短）
const DARK_EROSION_RESIST_SHRED := 0.40        ## 吃掉四成减免数值
const DARK_EROSION_HEAL_MULT := 0.10           ## 治疗只生效 10% = 减疗 90%
## 同一目标每这么久最多被挂上 1 次：蚀期间再中暗招**不续杯**。
## 没有这条，执烛的暗招会把玩家常驻磨在蚀里（减疗 90% 不断 = 治疗流直接报废），
## 而玩家对 BOSS 也只是把覆盖率拉满 —— 不对称。有了它，双方共用一个 6/9 的节奏，
## 这也是「暗」唯一的公平阀，比给某只 BOSS 的场地开特例更通用。
const DARK_EROSION_REFRESH_CD := 9.0


## 蚀的持续按目标的暗减免缩短：暗抗 100 → 只剩 3 秒；暗抗 0 → 满 6 秒。
## 这是新注册的 resist_dark 目前唯一的用处（暗抗来源属用户定稿内容，我没补配方/词条/符）。
static func dark_erosion_time(dark_resist: float) -> float:
	return DARK_EROSION_TIME * (1.0 - resist_reduction(dark_resist))

## 属性定义
##   name     显示名
##   cat      分类（CAT_*）
##   percent  是否为百分比属性（显示带 %，且参与倍率计算时按 /100 处理）
##   desc     一句话说明（面板 tooltip / 说明区用）
const ATTRS: Dictionary = {
	# ---------- 基础属性 ----------
	ATTR_SPEED: {
		"name": "速度", "cat": CAT_BASE, "percent": false,
		"desc": "移动速度，影响走位与追击节奏。",
	},
	ATTR_STRENGTH: {
		"name": "力量", "cat": CAT_BASE, "percent": false,
		"desc": "增强物理伤害：力量换算为物理攻击力，作用于全部物理攻击与物理招式。",
	},
	ATTR_SPELL_POWER: {
		"name": "法强", "cat": CAT_BASE, "percent": false,
		"desc": "增强法术伤害：法强换算为法术攻击力，作用于法术招式。",
	},
	ATTR_SPELL_SKILL_DAMAGE_PCT: {
		"name": "法技增伤", "cat": CAT_BASE, "percent": true,
		"desc": "只提高法术功法造成的伤害，不影响普通攻击、法宝召唤等非功法伤害。",
	},
	ATTR_ATTACK_SPEED: {
		"name": "攻速", "cat": CAT_BASE, "percent": true,
		"desc": "提高普通攻击频率。攻速 +100% 即攻击间隔减半。",
	},

	# ---------- 抗性 ----------
	ATTR_PHYSICAL_RESIST: {
		"name": "物抗", "cat": CAT_RESIST, "percent": false,
		"desc": "降低受到的物理伤害。收益递减，不会免疫。",
	},
	ATTR_MAGIC_RESIST: {
		"name": "法抗", "cat": CAT_RESIST, "percent": false,
		"desc": "降低受到的法术伤害（总体），与五行抗性叠乘生效。",
	},

	# ---------- 资源 ----------
	ATTR_HP_MAX: {
		"name": "气血上限", "cat": CAT_RESOURCE, "percent": false,
		"desc": "生命值上限。",
	},
	ATTR_MANA_MAX: {
		"name": "灵力", "cat": CAT_RESOURCE, "percent": false,
		"desc": "灵力上限，功法消耗的资源。",
	},
	ATTR_MANA_REGEN: {
		"name": "灵力恢复", "cat": CAT_RESOURCE, "percent": false,
		"desc": "每秒回复的灵力。",
	},
	ATTR_STAMINA_MAX: {
		"name": "精力", "cat": CAT_RESOURCE, "percent": false,
		"desc": "精力格数，闪避 / 弹刀 / 部分招式消耗。",
	},
	ATTR_STAMINA_REGEN: {
		"name": "精力恢复", "cat": CAT_RESOURCE, "percent": false,
		"desc": "每秒回复的精力格数。",
	},
	ATTR_STAMINA_REGEN_PCT: {
		"name": "精力恢复速度", "cat": CAT_RESOURCE, "percent": true,
		"desc": "按百分比提升精力恢复（在精力恢复总值上乘算，+1% 即 ×1.01）。",
	},
	ATTR_SPEED_PCT: {
		"name": "移动速度", "cat": CAT_BASE, "percent": true,
		"desc": "按百分比提升移动速度（在速度总值上乘算，+1% 即 ×1.01）。",
	},
}

## 五行抗性 id 由元素名拼出（resist_metal 等），在下方追加进 ATTRS
static func _element_attr_id(element: String) -> String:
	return "resist_" + element


## 是否为可参与抗性结算的元素（none/空串不算）
static func is_element(element: String) -> bool:
	return element in ELEMENTS


# ===== 装备强化提升区间 =====================
## 用户需求（2026-10-17）：强化成功时**随机选该装备面板上的一个属性**，
## 在该属性的专属区间内随机提升一点 —— 不再是「全装备统一加攻击力」。
##
## 区间按属性的**量纲与价值密度**分别设定，不是所有属性都 +1。
## 2026-11-13 用户定：**所有可强化词条都必须是区间，不再有固定值**。
## 固定 1.0 的条目统一改为 0.5~1.5（均值仍 1，不动原有总量，只给波动）；
## 法强与力量同为 1:1 换算，区间对齐成 1~2。
##   - 主属性（力量 / 法强 / 速度）：1~2
##   - 大数值（气血 / 灵力）：2~4
##   - 抗性（物抗 / 法抗 / 金木火土风雷）：0.5~1.5，均值 1
##   - 百分比（攻速）：0.5~1.5 个百分点，均值 1（原固定 1，波动不改总量）
##   - 回复速率（灵力恢复 / 精力恢复）：0.05~0.1（2026-10-31 随基础回复一起 ÷10）
##   - 精力：只强化「精力恢复」（= 缩短每格恢复时间），**不强化精力格数**
##   - 水抗沿用 2026-10-24 用户定的 0.1~0.5（藤甲专属）
##   - 未登记的属性不参与强化（相当于该词条被锁定）
const ENHANCE_RANGE: Dictionary = {
	ATTR_STRENGTH: {"min": 1.0, "max": 2.0},
	ATTR_SPELL_POWER: {"min": 1.0, "max": 2.0},
	ATTR_SPEED: {"min": 1.0, "max": 2.0},
	ATTR_ATTACK_SPEED: {"min": 0.5, "max": 1.5},
	ATTR_HP_MAX: {"min": 2.0, "max": 4.0},
	ATTR_PHYSICAL_RESIST: {"min": 0.5, "max": 1.5},
	ATTR_MAGIC_RESIST: {"min": 0.5, "max": 1.5},
	ATTR_MANA_MAX: {"min": 2.0, "max": 4.0},
	ATTR_MANA_REGEN: {"min": 0.05, "max": 0.1},
	ATTR_STAMINA_REGEN: {"min": 0.05, "max": 0.10},
	# 百分比词条：
	#   精力恢复速度 / 法技增伤沿用 0.5~1.0；
	#   移动速度 2026-10-24 用户调低为 0.1%~0.5%/次（基础词条仍是 +1%）
	ATTR_STAMINA_REGEN_PCT: {"min": 0.5, "max": 1.0},
	ATTR_SPEED_PCT: {"min": 0.1, "max": 0.5},
	ATTR_SPELL_SKILL_DAMAGE_PCT: {"min": 0.5, "max": 1.0},
	"resist_metal": {"min": 0.5, "max": 1.5},
	"resist_wood": {"min": 0.5, "max": 1.5},
	# 练气区核心首领·藤甲（2026-10-24 用户定：每次强化 0.1%~0.5%）
	# 抗性按点数结算，1 点约等于 1% 减免；这里沿用同一口径
	"resist_water": {"min": 0.1, "max": 0.5},
	"resist_fire": {"min": 0.5, "max": 1.5},
	"resist_earth": {"min": 0.5, "max": 1.5},
	"resist_wind": {"min": 0.5, "max": 1.5},
	"resist_thunder": {"min": 0.5, "max": 1.5},
}


## 某属性的强化区间（未登记返回空字典 = 不可强化）
static func enhance_range(attr_id: String) -> Dictionary:
	return ENHANCE_RANGE.get(attr_id, {})


## 该属性能否参与强化
static func can_enhance(attr_id: String) -> bool:
	return ENHANCE_RANGE.has(attr_id)


## 在区间内随机一个提升量（大成功用区间上限）
static func roll_enhance_amount(attr_id: String, use_max: bool = false) -> float:
	var r := enhance_range(attr_id)
	if r.is_empty():
		return 0.0
	var lo := float(r.get("min", 1.0))
	var hi := float(r.get("max", lo))
	if use_max or hi <= lo:
		return hi
	return randf_range(lo, hi)


## 该属性本词条强化后总共能涨多少（上限 = (max-min) × MAX_ENHANCE，UI 提示用）
static func enhance_gain_cap(attr_id: String) -> float:
	var r := enhance_range(attr_id)
	if r.is_empty():
		return 0.0
	return (float(r.get("max", 1.0)) - float(r.get("min", 1.0)))


## 属性定义（未登记返回空字典）
static func get_attr(attr_id: String) -> Dictionary:
	return ATTRS.get(attr_id, {})


static func has_attr(attr_id: String) -> bool:
	return ATTRS.has(attr_id) or _is_element_resist(attr_id)


static func attr_name(attr_id: String) -> String:
	# 五行抗性：动态生成名称（金抗 / 木抗 …）
	var parts := attr_id.split("_", false, 1)
	if parts.size() == 2 and parts[0] == "resist" and String(parts[1]) in ELEMENTS:
		return "%s抗" % String(ELEMENT_NAMES.get(parts[1], parts[1]))
	return String(get_attr(attr_id).get("name", attr_id))


static func is_percent(attr_id: String) -> bool:
	return bool(get_attr(attr_id).get("percent", false))


static func attr_category(attr_id: String) -> String:
	var a := get_attr(attr_id)
	if not a.is_empty():
		return String(a.get("cat", CAT_BASE))
	if _is_element_resist(attr_id):
		return CAT_RESIST
	return CAT_BASE


static func attr_desc(attr_id: String) -> String:
	var a := get_attr(attr_id)
	if not a.is_empty():
		return String(a.get("desc", ""))
	if _is_element_resist(attr_id):
		var elem := String(attr_id).trim_prefix("resist_")
		return "降低受到的%s属性法术伤害。" % String(ELEMENT_NAMES.get(elem, elem))
	return ""


## 是否为五行抗性属性 id（resist_metal / resist_wood / …）
static func _is_element_resist(attr_id: String) -> bool:
	return attr_id.begins_with("resist_") and String(attr_id).trim_prefix("resist_") in ELEMENTS


## 某分类下的属性 id 列表（固定顺序：登记顺序 + 五行按 ELEMENTS 顺序）
static func ids_in_category(cat: String) -> Array:
	var out: Array = []
	for k in ATTRS.keys():
		if String(ATTRS[k].get("cat", "")) == cat:
			out.append(k)
	if cat == CAT_RESIST:
		for e in ELEMENTS:
			out.append(_element_attr_id(String(e)))
	return out


## 全部属性 id（含五行抗性）
static func all_ids() -> Array:
	var out: Array = []
	for c in CATEGORIES:
		for id in ids_in_category(String(c.get("id", ""))):
			out.append(id)
	return out


# ===== 抗性计算 =====

## 抗性值 → 减免率（0~MAX_REDUCTION）
## 负抗性视为 0（目前不做「易伤」语义，易伤走受击方 buff 乘区）
static func resist_reduction(resist: float) -> float:
	var r := maxf(0.0, resist)
	return minf(MAX_REDUCTION, r / (r + RESIST_K))


## 属性值格式化（百分比属性带 % 与正负号）
static func format_value(attr_id: String, value: float) -> String:
	if is_percent(attr_id):
		return "%+.1f%%" % value
	if is_zero_approx(value - roundf(value)):
		return "%.0f" % value
	# 小于 1 的非整数值（灵力恢复 0.15 / 精力恢复 0.25）保留两位，避免被四舍五入成 0.1
	if absf(value) < 1.0:
		return "%.2f" % value
	return "%.1f" % value


