class_name DamageCalc
extends RefCounted
## 最终伤害计算器 —— 全项目「一次伤害打出多少」的唯一公式入口
##
## ============================ 公式 ============================
## 一次伤害分两段（物理 / 法术），各自吃自己的攻击力和抗性：
##
##   物理段 = 物理攻击力 × 技能物理系数
##   法术段 = 法术攻击力 × 技能法术系数
##
##   攻击方合计 = (物理段 + 法术段) × 攻击方增伤系数 × 随机浮动
##
##   物理段最终 = 物理段 × 攻击方增伤 × (1 − 目标物抗减免)
##   法术段最终 = 法术段 × 攻击方增伤 × (1 − 目标法抗减免) × (1 − 目标五行抗减免)
##
##   最终伤害 = (物理段最终 + 法术段最终) × 目标易伤系数
##
## 各乘区的含义：
##   - 攻击力：玩家侧由属性推导（力量→物理攻击力、法强→法术攻击力）
##   - 技能系数：来自招式形态（MoveDB），物理/法术各一个
##   - 攻击方增伤系数：自身 buff 增幅与削弱合并后的乘积（1.0 = 无变化）
##   - 抗性减免：递减公式 resist / (resist + K)，上限 90%，见 AttributeDB
##   - 目标易伤系数：敌方 buff 的增伤/减伤合并（1.0 = 无变化）
##
## ⚠ 本类**不读取任何全局状态**，所有输入都在 ctx 里传进来，
##   这样既能给玩家用，也能给 BOSS 用，还能单独做数值验证。

## 计算一次伤害
## ctx 可用字段（缺省按 0 / 1.0 处理）：
##   phys_power            攻击方物理攻击力
##   spell_power           攻击方法术攻击力
##   phys_coeff            技能物理系数
##   spell_coeff           技能法术系数
##   attack_mult           攻击方增伤系数（buff 合并，1.0 = 无）
##   target_phys_resist    目标物抗
##   target_magic_resist   目标法抗（总体）
##   target_element_resist 目标对应元素抗性
##   target_mult           目标易伤系数（1.0 = 无）
##   random                是否附加随机浮动（默认 true）
##
## 返回：
##   amount              最终伤害（取整前）
##   phys_component      物理段最终值
##   spell_component     法术段最终值
##   phys_raw / spell_raw  抗性前、buff 前的原始分量
##   phys_reduction / magic_reduction / element_reduction  各抗性减免率
##   attack_mult / target_mult                             各乘区系数
static func resolve(ctx: Dictionary) -> Dictionary:
	var phys_power := float(ctx.get("phys_power", 0.0))
	var spell_power := float(ctx.get("spell_power", 0.0))
	var phys_coeff := float(ctx.get("phys_coeff", 0.0))
	var spell_coeff := float(ctx.get("spell_coeff", 0.0))
	var attack_mult := float(ctx.get("attack_mult", 1.0))
	var target_mult := float(ctx.get("target_mult", 1.0))
	var use_random := bool(ctx.get("random", true))

	# 原始分量（未加 buff、未减抗）
	var phys_raw := maxf(0.0, phys_power) * phys_coeff
	var spell_raw := maxf(0.0, spell_power) * spell_coeff

	# 攻击方增伤乘区（buff 增幅 / 削弱）
	var phys_after_buff := phys_raw * attack_mult
	var spell_after_buff := spell_raw * attack_mult

	# 目标抗性减免（递减收益，见 AttributeDB.resist_reduction）
	var phys_red := AttributeDB.resist_reduction(float(ctx.get("target_phys_resist", 0.0)))
	var magic_red := AttributeDB.resist_reduction(float(ctx.get("target_magic_resist", 0.0)))
	var elem_red := AttributeDB.resist_reduction(float(ctx.get("target_element_resist", 0.0)))

	var phys_final := phys_after_buff * (1.0 - phys_red)
	# 法术段：法抗与五行抗性**叠乘**（两种独立防护，都堆才最抗打）
	var spell_final := spell_after_buff * (1.0 - magic_red) * (1.0 - elem_red)

	var amount := (phys_final + spell_final) * target_mult

	# 随机浮动（「其他因素」乘区，默认 ±5%）
	if use_random:
		amount *= randf_range(ItemDB.RANDOM_MIN, ItemDB.RANDOM_MAX)

	return {
		"amount": maxf(0.0, amount),
		"phys_component": phys_final,
		"spell_component": spell_final,
		"phys_raw": phys_raw,
		"spell_raw": spell_raw,
		"phys_reduction": phys_red,
		"magic_reduction": magic_red,
		"element_reduction": elem_red,
		"attack_mult": attack_mult,
		"target_mult": target_mult,
	}


## 读取受击方的单元素抗性。优先走统一接口 element_resist()，
## 没有该接口的旧单位退回 attribute("resist_<element>")。
static func target_element_resist(target: Node, element: String) -> float:
	if target == null or not is_instance_valid(target) or not AttributeDB.is_element(element):
		return 0.0
	if target.has_method("element_resist"):
		return float(target.call("element_resist", element))
	if target.has_method("attribute"):
		return float(target.call("attribute", "resist_" + element))
	return 0.0


## 单元素最终减免率（面板/探针用）
static func element_reduction(target: Node, element: String) -> float:
	return AttributeDB.resist_reduction(target_element_resist(target, element))


## 暗属性「蚀」的穿抗乘区：受击方身上 debuff 里最高的 resist_shred（没被蚀 = 0）。
## ⚠ 只在**结算这一层**打折，绝不去改 attribute()：面板与图鉴必须显示真实抗性，
##   否则玩家会看到「物抗 100」却挨了按 60 抗算的伤害，规则就不可读了。
##   同理 element_reduction() 不掺这层 —— 那个函数是给面板/探针看的。
static func target_resist_shred(target: Node) -> float:
	if target == null or not is_instance_valid(target):
		return 0.0
	if not target.has_method("debuff_resist_shred"):
		return 0.0
	return clampf(float(target.call("debuff_resist_shred")), 0.0, 0.9)


## 便捷包装：由「攻击方属性快照」直接算
## 玩家侧常用，省去手工拼 ctx；BOSS 侧如需自定义攻击力可继续用 resolve()
static func from_attributes(attacker: Node, target: Node, phys_coeff: float,
		spell_coeff: float, element: String = "", attack_mult: float = 1.0,
		use_random: bool = true) -> Dictionary:
	var ctx := {
		"phys_power": attacker.physical_attack() if attacker.has_method("physical_attack") else 0.0,
		"spell_power": attacker.spell_attack() if attacker.has_method("spell_attack") else 0.0,
		"phys_coeff": phys_coeff,
		"spell_coeff": spell_coeff,
		"attack_mult": attack_mult,
		"random": use_random,
	}
	# 「蚀」在进减免曲线之前吃掉减免数值（见 target_resist_shred）
	var keep := 1.0 - target_resist_shred(target)
	if target != null and is_instance_valid(target):
		if target.has_method("attribute"):
			ctx["target_phys_resist"] = float(target.attribute(AttributeDB.ATTR_PHYSICAL_RESIST)) * keep
			ctx["target_magic_resist"] = float(target.attribute(AttributeDB.ATTR_MAGIC_RESIST)) * keep
		ctx["target_element_resist"] = target_element_resist(target, element) * keep
	return resolve(ctx)


## 受击方减免：把「已经算好的原始伤害」按受击方抗性削减
## 用在玩家/BOSS 收到伤害的那一刻，避免各处的 take_damage 各写一套减伤
## attack_kind 为 "elemental" 时走法术抗性，其余走物理抗性；element 非空再叠该元素抗性
static func incoming(amount: float, target: Node, attack_kind: String,
		element: String = "") -> Dictionary:
	var is_spell := attack_kind == "elemental"
	var ctx := {
		"phys_coeff": 1.0,
		"spell_coeff": 1.0,
		"random": false,
	}
	if is_spell:
		ctx["phys_power"] = 0.0
		ctx["spell_power"] = amount
	else:
		ctx["phys_power"] = amount
		ctx["spell_power"] = 0.0
	# 「蚀」在进减免曲线之前吃掉减免数值（玩家与 BOSS 的受击都走这条 incoming）
	var keep := 1.0 - target_resist_shred(target)
	if target != null and is_instance_valid(target) and target.has_method("attribute"):
		ctx["target_phys_resist"] = float(target.attribute(AttributeDB.ATTR_PHYSICAL_RESIST)) * keep
		ctx["target_magic_resist"] = float(target.attribute(AttributeDB.ATTR_MAGIC_RESIST)) * keep
		ctx["target_element_resist"] = target_element_resist(target, element) * keep
	return resolve(ctx)


## 抗性 → 减免率的说明文案（面板 / 调试用）
## 例：「物抗 40（减免 28.6%）」
static func resist_text(attr_id: String, value: float) -> String:
	var red := AttributeDB.resist_reduction(value)
	return "%s %.0f（减免 %.1f%%）" % [AttributeDB.attr_name(attr_id), value, red * 100.0]


## 护体减伤被「蚀甲」削去一截：shred = 0.5 表示减伤幅度只按一半结算。
## 只处理 <1.0 的减伤乘区；易伤（>1.0）原样返回，避免把破绽放大成减伤。
static func apply_guard_shred(mult: float, shred: float) -> float:
	if mult >= 1.0 or shred <= 0.0:
		return mult
	var s := clampf(shred, 0.0, 1.0)
	return 1.0 - (1.0 - mult) * (1.0 - s)
