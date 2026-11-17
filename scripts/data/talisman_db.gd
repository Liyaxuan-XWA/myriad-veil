class_name TalismanDB
extends RefCounted
## 试炼之路「符箓」流派 —— 四符 + 连携体系的数据表（2026-11-10 重做）
##
## 只服务试炼：局外七元灵符（ItemDB.ELEMENT_TALISMAN_BASES / talisman_cabinet）一行不动。
## 设计案：docs/符箓流派重做_设计案.md
##
## 字段口径：
##   id / name / element / role   元素是连携「定弦」与符阵配色的唯一来源
##   mana / cd                    基础施放成本与冷却；变体继承原符，不单独写
##   ops                          效果**按顺序执行**的一个列表，见下方 op 清单
##   variants                     两个互斥变体 id（选了任一就不再出另一个）
##
## ⚠ 数值只在这里改：伤害系数是「法强的倍数」，品质倍率由 player 统一乘一次，
##   变体参数里**不要**再乘品质，否则四档之间会差出十几倍（旧版踩过）。
## ⚠ 品质只加数值与时长，不改形状；形状差异一律走变体。

const QUALITY_MULT: Array[float] = [1.0, 1.30, 1.70, 2.20]
const QUALITY_NAME: Array[String] = ["练气", "筑基", "结丹", "元婴"]
## 连携：70% 效率、不耗灵、不进冷却、不再触发二次连携
const CHAIN_EFF := 0.70
const CHAIN_MANA_GAIN := 2.0
## 符囊初始格数（灵机「开匣」+1）
const BAG_BASE := 2

## op 清单（player.gd 的 _run_tal_op_* 一一对应；探针会扫这张表验证没人漏实现）：
##   damage    shape=single/aoe/fan/line/chain；coeff 法强倍数；可带 delay/dot/lifesteal
##   debuff    挂 DebuffDB 里的负面；chance 概率、time 时长
##   dot       持续伤害；coeff 每秒法强倍数
##   regen     每秒回最大气血百分比
##   haste     移速百分比
##   guard     减伤 + 挡次数（土）
##   shield    护盾（按最大气血百分比），可带 nova 破碎反击
##   reflect   存伤反弹（光）
##   frost     霜层：叠满 stacks 层冻结
##   zone      地面持续区（tag=damage/drain/slow/absorb/regen）
##   spirit    符灵：定时束缚 + 伤害
##   blink     瞬移到目标背后
##   dash      朝输入方向冲刺
##   cleanse   清负面
##   invuln    无敌帧
##   sacrifice 支付当前气血百分比
##   heal      立即回最大气血百分比
##   dispel    清掉范围内的敌方弹幕

const BASES: Array = [
	{
		"id": "tal_jinfeng", "name": "金锋符", "element": "metal", "role": "attack",
		"mana": 5.0, "cd": 4.0,
		"desc": "一道剑气直取最近目标，简单、快、不挑场合。",
		"ops": [{"op": "damage", "shape": "single", "coeff": 1.60, "element": "metal"}],
		"variants": ["talv_jinfeng_myriad", "talv_jinfeng_break"],
	},
	{
		"id": "tal_huoqiu", "name": "火球符", "element": "fire", "role": "attack",
		"mana": 5.0, "cd": 5.0,
		"desc": "在目标处炸开一团火，火苗会黏在身上烧一会儿。",
		"ops": [
			{"op": "damage", "shape": "aoe", "coeff": 1.35, "radius": 80.0, "element": "fire"},
			{"op": "debuff", "id": "burn", "time": 4.0},
		],
		"variants": ["talv_huoqiu_rain", "talv_huoqiu_fenxin"],
	},
	{
		"id": "tal_yinlei", "name": "引雷符", "element": "thunder", "role": "attack",
		"mana": 6.0, "cd": 6.0,
		"desc": "目标头顶落雷，偶尔把人劈得动不了。",
		"ops": [
			{"op": "damage", "shape": "single", "coeff": 1.50, "element": "thunder"},
			{"op": "debuff", "id": "stun", "time": 1.0, "chance": 0.25, "chance_per_tier": 0.05},
		],
		"variants": ["talv_yinlei_chain", "talv_yinlei_prison"],
	},
	{
		"id": "tal_muling", "name": "木缚符", "element": "wood", "role": "control",
		"mana": 7.0, "cd": 9.0,
		"desc": "藤蔓从地里钻出来缠住目标 —— 它还能出招，只是走不了。",
		"ops": [{"op": "debuff", "id": "rooted", "time": 2.0, "time_per_tier": 0.6}],
		"variants": ["talv_muling_tangle", "talv_muling_spirit"],
	},
	{
		"id": "tal_shuihui", "name": "水愈符", "element": "water", "role": "utility",
		"mana": 7.0, "cd": 12.0,
		"desc": "水气慢慢渗进伤口，不瞬间抬血，但回得久。",
		"ops": [{"op": "regen", "pct": 1.6, "time": 8.0}],
		"variants": ["talv_shuihui_tide", "talv_shuihui_marrow"],
	},
	{
		"id": "tal_fengji", "name": "风疾符", "element": "wind", "role": "utility",
		"mana": 4.0, "cd": 10.0,
		"desc": "风托着脚底，跑得比平常快一截。",
		"ops": [{"op": "haste", "pct": 30.0, "time": 10.0}],
		"variants": ["talv_fengji_gale", "talv_fengji_feather"],
	},
	{
		"id": "tal_tushi", "name": "石附符", "element": "earth", "role": "utility",
		"mana": 6.0, "cd": 12.0,
		"desc": "石皮附身，挨打不那么疼，但腿也沉了。",
		"ops": [{"op": "guard", "reduce": 25.0, "reduce_per_tier": 5.0,
			"hits": 3, "hits_per_tier": 1, "time": 12.0, "speed_down": 15.0}],
		"variants": ["talv_tushi_array", "talv_tushi_boulder"],
	},
	{
		"id": "tal_bingning", "name": "凝霜符", "element": "ice", "role": "control",
		"mana": 6.0, "cd": 8.0,
		"desc": "霜一层层结上去：先只是发冷，叠到第三层就把人冻住。",
		"ops": [{"op": "frost", "slow": 25.0, "time": 6.0, "stacks": 3, "freeze": 1.8}],
		"variants": ["talv_bingning_seal", "talv_bingning_armor"],
	},
	{
		"id": "tal_zheguang", "name": "折光符", "element": "light", "role": "utility",
		"mana": 7.0, "cd": 14.0,
		"desc": "把挨的打折进光里存着，三秒后原样还回去。",
		"ops": [{"op": "reflect", "cap_pct": 30.0, "time": 3.0, "coeff": 1.2}],
		"variants": ["talv_zheguang_pillar", "talv_zheguang_heal"],
	},
	{
		"id": "tal_shiyuan", "name": "噬元符", "element": "dark", "role": "attack",
		"mana": 0.0, "cd": 8.0,
		"desc": "以自身气血喂符，换一记狠的，还把血吸回来一部分。",
		"ops": [
			{"op": "sacrifice", "hp_pct": 8.0},
			{"op": "damage", "shape": "single", "coeff": 2.60, "element": "dark",
				"lifesteal": 0.40},
		],
		"variants": ["talv_shiyuan_blink", "talv_shiyuan_array"],
	},
]

const VARIANTS: Dictionary = {
	# --- 金锋 ---
	"talv_jinfeng_myriad": {
		"id": "talv_jinfeng_myriad", "base": "tal_jinfeng", "name": "万剑符",
		"desc": "一支笔落下去，五道剑气同时出手。",
		"ops": [{"op": "damage", "shape": "fan", "coeff": 0.75, "count": 5,
			"angle": 70.0, "element": "metal"}],
	},
	"talv_jinfeng_break": {
		"id": "talv_jinfeng_break", "base": "tal_jinfeng", "name": "断锋符",
		"desc": "剑气穿过一整排人，被划开的甲缝会一直裂着。",
		"ops": [
			{"op": "damage", "shape": "line", "coeff": 1.60, "element": "metal"},
			{"op": "debuff", "id": "rune_crack", "time": 6.0},
		],
	},
	# --- 火球 ---
	"talv_huoqiu_rain": {
		"id": "talv_huoqiu_rain", "base": "tal_huoqiu", "name": "火雨符",
		"desc": "火球不是一颗，是一片落下来。",
		"ops": [{"op": "damage", "shape": "aoe", "coeff": 0.90, "radius": 70.0,
			"count": 3, "spread": 150.0, "element": "fire"}],
	},
	"talv_huoqiu_fenxin": {
		"id": "talv_huoqiu_fenxin", "base": "tal_huoqiu", "name": "焚心符",
		"desc": "火种钻进心里烧三秒，然后从里面炸开。",
		"ops": [{"op": "damage", "shape": "aoe", "coeff": 1.60, "radius": 90.0,
			"element": "fire", "delay": 3.0, "dot_coeff": 0.35, "dot_time": 3.0}],
	},
	# --- 引雷 ---
	"talv_yinlei_chain": {
		"id": "talv_yinlei_chain", "base": "tal_yinlei", "name": "连锁雷符",
		"desc": "雷落到一个人身上，再跳到下一个，一跳比一跳弱。",
		"ops": [{"op": "damage", "shape": "chain", "coeff": 1.50, "jumps": 3,
			"falloff": 0.20, "element": "thunder"}],
	},
	"talv_yinlei_prison": {
		"id": "talv_yinlei_prison", "base": "tal_yinlei", "name": "雷狱符",
		"desc": "雷不走了，就在脚下积成一池，谁站进去谁挨劈。",
		"ops": [{"op": "zone", "radius": 140.0, "time": 4.0, "tick": 0.8,
			"coeff": 0.50, "element": "thunder", "tag": "damage",
			"debuff": "stun", "debuff_chance": 0.15, "debuff_time": 0.6}],
	},
	# --- 木缚 ---
	"talv_muling_tangle": {
		"id": "talv_muling_tangle", "base": "tal_muling", "name": "缠根符",
		"desc": "藤不只缠住脚，还在一点点往肉里收。",
		"ops": [
			{"op": "debuff", "id": "rooted", "time": 4.0},
			{"op": "dot", "coeff": 0.35, "time": 4.0, "element": "wood"},
		],
	},
	"talv_muling_spirit": {
		"id": "talv_muling_spirit", "base": "tal_muling", "name": "符灵·青藤",
		"desc": "符纸折成一只小青藤，它自己会去找人缠。",
		"ops": [{"op": "spirit", "time": 12.0, "interval": 2.0, "coeff": 0.50,
			"root": 1.0, "element": "wood"}],
	},
	# --- 水愈 ---
	"talv_shuihui_tide": {
		"id": "talv_shuihui_tide", "base": "tal_shuihui", "name": "潮汐符",
		"desc": "脚下漫开一滩水：自己泡着回血，别人踩进来走不动。",
		"ops": [{"op": "zone", "radius": 150.0, "time": 5.0, "tick": 1.0,
			"coeff": 0.0, "element": "water", "tag": "regen",
			"slow": 30.0, "heal_pct": 1.2}],
	},
	"talv_shuihui_marrow": {
		"id": "talv_shuihui_marrow", "base": "tal_shuihui", "name": "洗髓符",
		"desc": "一口气把水灌进骨头里，立刻回一大截，还洗掉一层脏东西。",
		"ops": [{"op": "heal", "pct": 22.0}, {"op": "cleanse", "count": 1}],
	},
	# --- 风疾 ---
	"talv_fengji_gale": {
		"id": "talv_fengji_gale", "base": "tal_fengji", "name": "罡风符",
		"desc": "风从身后压过来，把人和弹幕一起推出去。",
		"ops": [{"op": "dispel", "radius": 200.0}, {"op": "damage", "shape": "fan",
			"coeff": 0.60, "count": 3, "angle": 120.0, "element": "wind"}],
	},
	"talv_fengji_feather": {
		"id": "talv_fengji_feather", "base": "tal_fengji", "name": "风羽符",
		"desc": "化成一缕风窜出去，落地时下一张符已经蓄好了。",
		"ops": [{"op": "dash", "dist": 200.0, "boost": 45.0, "boost_time": 3.0}],
	},
	# --- 石附 ---
	"talv_tushi_array": {
		"id": "talv_tushi_array", "base": "tal_tushi", "name": "石阵符",
		"desc": "石头从地里立起来围成一圈：里面的人走不动，飞来的东西也进不来。",
		"ops": [{"op": "zone", "radius": 160.0, "time": 6.0, "tick": 0.5,
			"coeff": 0.0, "element": "earth", "tag": "absorb", "slow": 40.0}],
	},
	"talv_tushi_boulder": {
		"id": "talv_tushi_boulder", "base": "tal_tushi", "name": "磐石符",
		"desc": "一层石甲裹住全身，碎的时候把碎片全崩出去。",
		"ops": [{"op": "shield", "pct": 18.0, "time": 12.0, "nova": 1.5}],
	},
	# --- 凝霜 ---
	"talv_bingning_seal": {
		"id": "talv_bingning_seal", "base": "tal_bingning", "name": "冰封符",
		"desc": "不叠霜了，直接冻成一块；冰裂的时候再补一刀。",
		"ops": [
			{"op": "debuff", "id": "frozen", "time": 2.2},
			{"op": "damage", "shape": "aoe", "coeff": 1.40, "radius": 90.0,
				"element": "ice", "delay": 2.2},
		],
	},
	"talv_bingning_armor": {
		"id": "talv_bingning_armor", "base": "tal_bingning", "name": "霜甲符",
		"desc": "霜结在自己身上：谁打你，谁就跟着发冷。",
		"ops": [{"op": "frost_armor", "time": 8.0, "slow": 25.0, "time_per_hit": 6.0}],
	},
	# --- 折光 ---
	"talv_zheguang_pillar": {
		"id": "talv_zheguang_pillar", "base": "tal_zheguang", "name": "聚光符",
		"desc": "光从天上压下来钉在原地，站在光里的人连符都更怕。",
		"ops": [{"op": "zone", "radius": 130.0, "time": 4.0, "tick": 1.0,
			"coeff": 0.55, "element": "light", "tag": "damage",
			"debuff": "rune_crack", "debuff_chance": 1.0, "debuff_time": 4.0}],
	},
	"talv_zheguang_heal": {
		"id": "talv_zheguang_heal", "base": "tal_zheguang", "name": "光愈符",
		"desc": "把存下的光直接灌回身上，顺手挡掉接下来的一小段。",
		"ops": [{"op": "heal", "pct": 15.0}, {"op": "invuln", "time": 1.5}],
	},
	# --- 噬元 ---
	"talv_shiyuan_blink": {
		"id": "talv_shiyuan_blink", "base": "tal_shiyuan", "name": "影遁符",
		"desc": "钻进影子里，从目标背后出来，手里已经捏好下一张符。",
		"ops": [{"op": "blink", "behind": true, "boost": 60.0, "boost_time": 3.0}],
	},
	"talv_shiyuan_array": {
		"id": "talv_shiyuan_array", "base": "tal_shiyuan", "name": "噬灵阵",
		"desc": "脚下铺开一片暗：它在吃他们，也在喂你。",
		"ops": [{"op": "zone", "radius": 150.0, "time": 5.0, "tick": 1.0,
			"coeff": 0.50, "element": "dark", "tag": "drain", "heal_pct": 0.5}],
	},
}


static func all_bases() -> Array:
	return BASES


static func all_variants() -> Array:
	return VARIANTS.values()


## 开局可选池：局外就有的七张元素符（冰 / 光 / 暗只能靠局内符方）
static func start_pool() -> Array:
	return [
		"tal_jinfeng", "tal_huoqiu", "tal_yinlei", "tal_muling",
		"tal_shuihui", "tal_fengji", "tal_tushi",
	]


static func base_def(base_id: String) -> Dictionary:
	for raw in BASES:
		var d: Dictionary = raw
		if String(d.get("id", "")) == base_id:
			return d
	return {}


static func variant_def(variant_id: String) -> Dictionary:
	if VARIANT_IDS.is_empty():
		_cache_variant_ids()
	if not VARIANT_IDS.has(variant_id):
		return {}
	return VARIANTS[variant_id]


## 变体 id 集合（避免每次扫字典）
static var VARIANT_IDS: Dictionary = {}


static func _cache_variant_ids() -> void:
	VARIANT_IDS.clear()
	for raw_key in VARIANTS.keys():
		VARIANT_IDS[String(raw_key)] = true


## 通用取定义：先当变体查，再当基础符查
static func get_def(talisman_id: String) -> Dictionary:
	var v := variant_def(talisman_id)
	if not v.is_empty():
		return v
	return base_def(talisman_id)


## 变体 → 所属基础符；基础符返回自身
static func base_of(talisman_id: String) -> String:
	var v := variant_def(talisman_id)
	if not v.is_empty():
		return String(v.get("base", ""))
	return talisman_id


static func element_of(talisman_id: String) -> String:
	var base := base_of(talisman_id)
	return String(base_def(base).get("element", ""))


static func display_name(talisman_id: String) -> String:
	var d := get_def(talisman_id)
	if not d.is_empty():
		return String(d.get("name", talisman_id))
	var base := base_of(talisman_id)
	return String(base_def(base).get("name", talisman_id))


static func mana_cost(talisman_id: String) -> float:
	return float(base_def(base_of(talisman_id)).get("mana", 5.0))


static func cooldown(talisman_id: String) -> float:
	return float(base_def(base_of(talisman_id)).get("cd", 6.0))


static func ops_of(talisman_id: String) -> Array:
	return (get_def(talisman_id).get("ops", []) as Array)


static func variants_of(base_id: String) -> Array:
	var d := base_def(base_id)
	return (d.get("variants", []) as Array)


## 一张符（含变体）的说明行；数字全部现算，不写在 desc 里
static func effect_lines(talisman_id: String, tier: int = 0) -> Array:
	var d := get_def(talisman_id)
	if d.is_empty():
		return []
	var out: Array = []
	var t := clampi(tier, 0, QUALITY_MULT.size() - 1)
	var mult := QUALITY_MULT[t]
	for raw in (d.get("ops", []) as Array):
		var op: Dictionary = raw
		var kind := String(op.get("op", ""))
		match kind:
			"damage":
				out.append(_line_damage(op, mult))
			"debuff":
				out.append("挂「%s」%.1f 秒%s" % [
					String(DebuffDB.DEBUFFS.get(String(op.get("id", "")), {}).get("name", "负面")),
					_time_of(op, t),
					_chance_of(op, t)])
			"dot":
				out.append("每秒 %.2f× 法强，持续 %.0f 秒" % [
					float(op.get("coeff", 0.0)) * mult, _time_of(op, t)])
			"regen":
				out.append("每秒回复 %.1f%% 最大气血，持续 %.0f 秒" % [
					float(op.get("pct", 0.0)) * mult, _time_of(op, t)])
			"haste":
				out.append("移速 +%.0f%%，持续 %.0f 秒" % [
					float(op.get("pct", 0.0)), _time_of(op, t)])
			"guard":
				out.append("减伤 %.0f%%、挡 %d 次伤害，持续 %.0f 秒" % [
					float(op.get("reduce", 0.0)) + float(op.get("reduce_per_tier", 0.0)) * t,
					int(op.get("hits", 1)) + int(op.get("hits_per_tier", 0)) * t,
					_time_of(op, t)])
			"shield":
				out.append("吸收 %.0f%% 最大气血的伤害，持续 %.0f 秒" % [
					float(op.get("pct", 0.0)) * mult, _time_of(op, t)])
			"reflect":
				out.append("%.0f 秒内受到的伤害存起来（上限 %.0f%% 最大气血），到期以 %.2f× 法强打回" % [
					_time_of(op, t), float(op.get("cap_pct", 30.0)),
					float(op.get("coeff", 1.0)) * mult])
			"frost":
				out.append("减速 %.0f%% %.0f 秒；叠满 %d 层冻结 %.1f 秒" % [
					float(op.get("slow", 20.0)), _time_of(op, t),
					int(op.get("stacks", 3)), float(op.get("freeze", 1.5))])
			"zone":
				out.append(_line_zone(op, mult))
			"spirit":
				out.append("召出符灵 %.0f 秒：每 %.1f 秒束缚最近目标 %.1f 秒并造成 %.2f× 法强" % [
					_time_of(op, t), float(op.get("interval", 2.0)),
					float(op.get("root", 1.0)), float(op.get("coeff", 0.5)) * mult])
			"blink":
				out.append("瞬移到目标背后；%.0f 秒内下一张符 +%.0f%%" % [
					float(op.get("boost_time", 3.0)), float(op.get("boost", 50.0))])
			"dash":
				out.append("向输入方向冲刺 %.0f；%.0f 秒内下一张符 +%.0f%%" % [
					float(op.get("dist", 180.0)), float(op.get("boost_time", 3.0)),
					float(op.get("boost", 40.0))])
			"cleanse":
				out.append("清除 %d 个负面状态" % int(op.get("count", 1)))
			"invuln":
				out.append("%.1f 秒无敌" % float(op.get("time", 1.0)))
			"sacrifice":
				out.append("支付当前气血的 %.0f%%" % float(op.get("hp_pct", 8.0)))
			"heal":
				out.append("立即回复 %.0f%% 最大气血" % (float(op.get("pct", 10.0)) * mult))
			"dispel":
				out.append("清除 %.0f 范围内的敌方弹幕" % float(op.get("radius", 180.0)))
			"frost_armor":
				out.append("%.0f 秒内受击时给攻击者叠一层霜" % _time_of(op, t))
	return out


static func _time_of(op: Dictionary, tier: int) -> float:
	return float(op.get("time", 1.0)) + float(op.get("time_per_tier", 0.0)) * tier


static func _chance_of(op: Dictionary, tier: int) -> String:
	var c := float(op.get("chance", 1.0)) + float(op.get("chance_per_tier", 0.0)) * tier
	if c >= 1.0:
		return ""
	return "（%.0f%% 概率）" % (c * 100.0)


static func _line_damage(op: Dictionary, mult: float) -> String:
	var coeff := float(op.get("coeff", 1.0)) * mult
	var shape := String(op.get("shape", "single"))
	var text := ""
	match shape:
		"single":
			text = "单体 %.2f× 法强" % coeff
		"aoe":
			var count := int(op.get("count", 1))
			if count > 1:
				text = "%d 段 %.2f× 法强，每段 %.0f 范围" % [count, coeff, float(op.get("radius", 80.0))]
			else:
				text = "%.0f 范围 %.2f× 法强" % [float(op.get("radius", 80.0)), coeff]
		"fan":
			text = "%d 道 %.2f× 法强（%.0f° 扇形）" % [
				int(op.get("count", 3)), coeff, float(op.get("angle", 60.0))]
		"line":
			text = "穿透直线 %.2f× 法强" % coeff
		"chain":
			text = "%.2f× 法强，弹跳 %d 次（每跳 -%.0f%%）" % [
				coeff, int(op.get("jumps", 2)), float(op.get("falloff", 0.2)) * 100.0]
	if float(op.get("delay", 0.0)) > 0.0:
		text = "延迟 %.1f 秒：%s" % [float(op.get("delay", 0.0)), text]
	if float(op.get("dot_coeff", 0.0)) > 0.0:
		text += "；期间每秒 %.2f× 法强" % (float(op.get("dot_coeff", 0.0)) * mult)
	if float(op.get("lifesteal", 0.0)) > 0.0:
		text += "；吸血 %.0f%%" % (float(op.get("lifesteal", 0.0)) * 100.0)
	return text


static func _line_zone(op: Dictionary, mult: float) -> String:
	var tag := String(op.get("tag", "damage"))
	var r := float(op.get("radius", 140.0))
	var tm := float(op.get("time", 4.0))
	match tag:
		"regen":
			return "水洼 %.0f 范围 %.0f 秒：每秒回 %.1f%% 气血，敌人减速 %.0f%%" % [
				r, tm, float(op.get("heal_pct", 1.0)), float(op.get("slow", 30.0))]
		"absorb":
			return "石阵 %.0f 范围 %.0f 秒：吸收敌方弹幕，敌人减速 %.0f%%" % [
				r, tm, float(op.get("slow", 40.0))]
		"drain":
			return "暗阵 %.0f 范围 %.0f 秒：每秒 %.2f× 法强，自己回 %.1f%% 气血" % [
				r, tm, float(op.get("coeff", 0.5)) * mult, float(op.get("heal_pct", 0.5))]
		_:
			return "区域 %.0f 范围 %.0f 秒：每 %.1f 秒 %.2f× 法强" % [
				r, tm, float(op.get("tick", 1.0)), float(op.get("coeff", 0.5)) * mult]
