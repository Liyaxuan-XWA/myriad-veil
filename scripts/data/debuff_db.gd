class_name DebuffDB
extends RefCounted
## 负面状态（debuff）数据表 —— 2026-10-23
##
## 为什么单独成表：debuff 现在是「谁打中都可能挂」的通用机制，
##   名称、颜色、效果倍率不该散在 BOSS 脚本里。加新 debuff 只在这里补一条 +
##   在招式表里写 `debuff_on_hit`，战斗 HUD 会自动多出一行显示。
##
## 字段：
##   name       显示名（HUD 与飘字都用它）
##   desc       一句话说明（玩家可见，别写数字机制以外的废话）
##   color      文字/边框色（HUD 标签用）
##   move_mult  移动速度乘区：1.0 = 无影响，0.5 = 只剩一半
##   no_dodge   true = 期间无法闪避
##   no_stamina_regen  true = 期间精力停止恢复（力竭）
##   no_action   true = 完全锁住行动（眩晕）：玩家侧入口读 is_action_blocked() 吞输入，
##               移动由 move_mult = 0 一并锁死
##   dot_damage / dot_interval  持续伤害（点燃等）：每 interval 秒扣 damage 点真实伤害
##   resist_shred  穿抗：目标的物抗 / 法抗 / 元素抗**数值**先 ×(1-本值) 再进减免曲线
##               （只在 DamageCalc 结算时打折，attribute() 不动 —— 面板必须显示真实抗性）
##   heal_mult   治疗乘区：期间受到的治疗只生效本值（0.10 = 减疗 90%）
##
## ⚠ 效果是**每帧现查**的（玩家侧 debuff_move_mult() / is_dodge_blocked()，BOSS 侧 _tick_debuffs），
##   不在施加时改速度或锁状态 —— 否则计时一结束还得记得还原，必然有人漏。

const DEBUFFS: Dictionary = {
	"wounded": {
		"name": "重伤",
		"desc": "无法闪避，移动速度 -50%",
		"color": Color(0.95, 0.36, 0.32, 1.0),
		"move_mult": 0.5,
		"no_dodge": true,
	},
	## 力竭（2026-10-23 并入 debuff 体系）：一剑开天普通形态抽空精力后的后遗症
	## 原来是一条独立的 exhausted_timer，挪进这张表之后 HUD 会自动显示「力竭 3.0s」，
	## 效果判定也统一走 has_debuff("exhausted")，不用再各写一份。
	"exhausted": {
		"name": "力竭",
		"desc": "精力停止恢复",
		"color": Color(0.95, 0.68, 0.30, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
		"no_stamina_regen": true,
	},
	## 点燃（火球符）：8 秒内每 0.5 秒扣 3 点血，共 16 跳
	## DoT 由 BossBase._tick_debuffs 统一结算
	"burn": {
		"name": "点燃",
		"desc": "每 0.5 秒受到 3 点火焰伤害",
		"color": Color(1.0, 0.55, 0.20, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
		"dot_damage": 3.0,
		"dot_interval": 0.5,
	},
	## 阴蚀（两仪真人 · 阴诀/阴风）：持续掉血 + 轻微减速。
	## 数字按筑基玩家（约 200 血）定：6 秒 12 点，是压力不是死刑。
	"yin_erosion": {
		"name": "阴蚀",
		"desc": "每秒受到 2 点阴蚀伤害，移动速度 -15%",
		"color": Color(0.46, 0.82, 0.86, 1.0),
		"move_mult": 0.85,
		"no_dodge": false,
		"dot_damage": 2.0,
		"dot_interval": 1.0,
	},
	## 眩晕（两仪真人 · 太极崩命中，2026-10-28 用户定）：2 秒完全失去控制。
	## move_mult = 0 把移动锁死（player 的移速结算读 debuff_move_mult()），
	## no_action 是新增字段，player._handle_action_input / try_use_skill 等入口读它吞输入。
	"stun": {
		"name": "眩晕",
		"desc": "无法移动与行动",
		"color": Color(1.0, 0.86, 0.35, 1.0),
		"move_mult": 0.0,
		"no_dodge": true,
		"no_action": true,
	},
	## 冻结（符箓·凝霜）：与眩晕同一套「锁行动」，但名字与颜色分开 ——
	## 玩家要靠飘字与 HUD 分辨「这是被我冻住的」而不是「被打晕的」。
	"frozen": {
		"name": "冻结",
		"desc": "无法移动与行动",
		"color": Color(0.62, 0.88, 1.0, 1.0),
		"move_mult": 0.0,
		"no_dodge": true,
		"no_action": true,
	},
	## 符裂（符箓·断锋 / 聚光）：被符撕开的甲缝，接下来一段时间更怕打。
	"rune_crack": {
		"name": "符裂",
		"desc": "受到伤害 +25%",
		"color": Color(0.95, 0.78, 0.42, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
		"damage_taken_mult": 1.25,
	},
	## 阳印 / 阴印（玩家侧两仪功法挂给敌人的标记）。
	## 本身不产生效果；玩家的异属性命中会读取它并引爆（见 player.gd 的 _yinyang_*）。
	"yang_mark": {
		"name": "阳印",
		"desc": "被阴属性命中时会引爆，受到额外伤害",
		"color": Color(1.0, 0.84, 0.46, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
	},
	"yin_mark": {
		"name": "阴印",
		"desc": "被阳属性命中时会引爆，受到额外伤害",
		"color": Color(0.46, 0.82, 0.86, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
	},
	## 锁步（定阵先生 · 困旗，2026-10-28）：只锁「走位 + 闪避」，攻击 / 功法 / 弹反照常
	"lock_step": {
		"name": "锁步",
		"desc": "移动速度 -40%，无法闪避",
		"color": Color(0.62, 0.56, 0.48, 1.0),
		"move_mult": 0.6,
		"no_dodge": true,
	},
	## 定身（三困成套「定身锁」）：可以反击，但一步也挪不动
	"rooted": {
		"name": "定身",
		"desc": "无法移动，无法闪避",
		"color": Color(0.74, 0.66, 0.50, 1.0),
		"move_mult": 0.0,
		"no_dodge": true,
	},
	## 滞气（太虚气君 · 气锁·缚脉）：灵力停止回复 + 轻微减速
	"qi_stagnation": {
		"name": "滞气",
		"desc": "灵力停止回复，移动速度 -20%",
		"color": Color(0.56, 0.78, 0.92, 1.0),
		"move_mult": 0.8,
		"no_dodge": false,
		"no_mana_regen": true,
	},
	## 风缚（三元轮 · 风炁）：通用减速，不带其它锁行动
	"tri_wind_bind": {
		"name": "风缚",
		"desc": "移动速度 -20%",
		"color": Color(0.56, 0.86, 0.76, 1.0),
		"move_mult": 0.8,
		"no_dodge": false,
	},
	## 阵缓（玩家侧困旗）：只减速，不带禁闪避（敌人本来也不闪避）
	"array_slow": {
		"name": "阵缓",
		"desc": "移动速度 -30%",
		"color": Color(0.62, 0.56, 0.48, 1.0),
		"move_mult": 0.7,
		"no_dodge": false,
	},
	## 阵伤（攻旗轰击，层数用 1/2/3 三个 id 表示；Boss 只挂最高层，避免 HUD 三行）
	"array_wound_1": {
		"name": "阵伤·一",
		"desc": "受到伤害 +8%",
		"color": Color(0.90, 0.42, 0.32, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
		"damage_taken_mult": 1.08,
	},
	"array_wound_2": {
		"name": "阵伤·二",
		"desc": "受到伤害 +16%",
		"color": Color(0.94, 0.44, 0.30, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
		"damage_taken_mult": 1.16,
	},
	"array_wound_3": {
		"name": "阵伤·三",
		"desc": "受到伤害 +24%",
		"color": Color(0.98, 0.46, 0.28, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
		"damage_taken_mult": 1.24,
	},
	## 敌方五旗阵压：玩家在敌方阵内攻击 -10%（HUD 标签；数值由 player 阵区逻辑合并）
	"array_zone_weaken": {
		"name": "阵压",
		"desc": "处于敌方五旗阵内：攻击力 -10%",
		"color": Color(0.92, 0.64, 0.36, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
	},
	## 破阵反噬：五旗被敌对破去一面，眩晕 5 秒 + 15 秒内插旗/踏阵/垒旗全部不可用
	"array_recoil": {
		"name": "破阵反噬",
		"desc": "阵旗被敌对破去：15 秒内无法插旗（附带眩晕 5 秒）",
		"color": Color(0.95, 0.52, 0.34, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
	},
	## 滞雷（赫连霄 · 锁雷·缚魂）：与滞气 / 锁步分开 —— 它专门削「闪避距离」
	"thunder_stagnation": {
		"name": "滞雷",
		"desc": "移动速度 -25%，闪避距离 -30%",
		"color": Color(0.72, 0.58, 0.98, 1.0),
		"move_mult": 0.75,
		"no_dodge": false,
		"dodge_mult": 0.7,
	},
	## 判词四条（赫连霄 · 判词·天律）：本身不写数值，效果由 BOSS / 玩家脚本按行为判定；
	## 这里登记是为了 HUD 能读出「现在犯哪条律」以及图鉴状态模块能讲清楚。
	"verdict_no_move": {
		"name": "判词·禁行",
		"desc": "每移动 110 像素引一道雷；守满判词得顺天",
		"color": Color(0.66, 0.78, 1.0, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
	},
	"verdict_no_attack": {
		"name": "判词·禁攻",
		"desc": "每次打中目标引一道雷；守满判词得顺天",
		"color": Color(1.0, 0.74, 0.40, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
	},
	"verdict_no_dodge": {
		"name": "判词·禁避",
		"desc": "每次闪避引一道雷（弹反不算）；守满判词得顺天",
		"color": Color(0.80, 0.60, 1.0, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
	},
	"verdict_no_still": {
		"name": "判词·禁立",
		"desc": "原地不动超过 0.9 秒引雷；守满判词得顺天",
		"color": Color(0.96, 0.86, 0.46, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
	},
	## 灼心（离照 · 逐日·天火）：持种满层后的持续火伤；投日/日蚀/被夺火可提前结束
	"sunburn": {
		"name": "灼心",
		"desc": "满 3 层后每秒受到 6 点火焰伤害",
		"color": Color(1.0, 0.52, 0.26, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
		"dot_damage": 6.0,
		"dot_interval": 1.0,
	},
	## 火忌（离照 · 连续两次夺火落空）：火种拒绝他，四招抢火全部哑火
	"sun_fire_ban": {
		"name": "火忌",
		"desc": "连续两次夺火落空后，6 秒内无法使用逐日步 / 牵日 / 焚风 / 日蚀",
		"color": Color(0.64, 0.82, 1.0, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
	},
	## 三灾轮转（晏无咎）
	"jie_huo": {
		"name": "劫火",
		"desc": "每秒受到 6 点火焰伤害",
		"color": Color(1.0, 0.46, 0.20, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
		"dot_damage": 6.0,
		"dot_interval": 1.0,
	},
	## 三灾·灾劫连锁（2026-10-31）：风灾命中附加，作为「风雷引」的引子
	"feng_shi": {
		"name": "风蚀",
		"desc": "移动速度 -15%",
		"color": Color(0.52, 0.86, 0.80, 1.0),
		"move_mult": 0.85,
		"no_dodge": false,
	},
	"gan_dian": {
		"name": "感电",
		"desc": "受到伤害 +15%",
		"color": Color(0.82, 0.72, 1.0, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
		"damage_taken_mult": 1.15,
	},
	## 试炼之路「虎妖·蛮力」：重击砸出的护甲裂隙，纯受伤加成。
	## ⚠ 与感电 / 阴阳印同走 debuff_damage_taken_mult()，那边取**最大值不叠乘**，
	##   所以同时挂上时只生效最高的那一条（刻意为之：避免几层增伤连乘炸数值）。
	"armor_break": {
		"name": "破防",
		"desc": "受到伤害 +15%",
		"color": Color(1.0, 0.70, 0.40, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
		"damage_taken_mult": 1.15,
	},
	## 试炼之路「虎妖·砂暴」：砂石糊眼，纯减速。
	## ⚠ debuff_move_mult() 取**最小值**，与困阵 / 缓速等同时存在时只吃最狠的一条。
	"blinding_sand": {
		"name": "迷眼",
		"desc": "砂石糊眼，移动速度 -25%",
		"color": Color(0.86, 0.78, 0.52, 1.0),
		"move_mult": 0.75,
		"no_dodge": false,
	},
	"suo_zai": {
		"name": "锁灾",
		"desc": "无法切换灾位",
		"color": Color(0.68, 0.62, 0.86, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
		"no_calamity_switch": true,
	},
	"zai_beng": {
		"name": "灾崩",
		"desc": "受到伤害 +30%",
		"color": Color(0.90, 0.78, 0.64, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
		"damage_taken_mult": 1.30,
	},
	## 断念铃（野修法宝）：封住功法，普攻 / 闪避 / 弹刀 / 法宝照常。
	## no_skill 由玩家 try_use_skill 与 BOSS apply_skill_lock 分别读。
	"duannian": {
		"name": "断念",
		"desc": "无法使用功法（普攻、闪避、弹刀不受影响）",
		"color": Color(0.74, 0.62, 0.98, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
		"no_skill": true,
	},
	## 禁步桩（野修法宝）：站在桩圈里持续挂，离开后 0.6 秒内自行消失。
	## 不含硬定身 —— 定身是木缚符的动词，法宝不抢符箓的活。
	"jinbu": {
		"name": "禁步",
		"desc": "移动速度 -35%，无法闪避，精力停止恢复",
		"color": Color(0.86, 0.70, 0.34, 1.0),
		"move_mult": 0.65,
		"no_dodge": true,
		"no_stamina_regen": true,
	},
	## 蚀甲锥（野修法宝）：受到伤害 +12%，护体类减伤只按一半结算。
	## guard_shred 由玩家 take_damage / BossBase.take_damage 的减伤聚合处读。
	## ⚠ 石附符是符箓，不参与护体削减，避免法宝和符箓互相拆台。
	"shixi": {
		"name": "蚀甲",
		"desc": "受到伤害 +12%，护体类减伤减半（符箓除外）",
		"color": Color(0.60, 0.82, 0.52, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
		"damage_taken_mult": 1.12,
		"guard_shred": 0.5,
	},
	## 镜滞（观澜 · 水镜环 / 碎镜）：脚泡在镜水里，走得比平时慢。
	## 只是减速，不带锁行动 / 禁闪避 —— 和锁步、定身、滞雷的动词分开。
	"mirror_slow": {
		"name": "镜滞",
		"desc": "移动速度 -30%",
		"color": Color(0.62, 0.86, 1.0, 1.0),
		"move_mult": 0.7,
		"no_dodge": false,
	},
	## 影缚（照影界第二位「执烛」· 缚影，2026-11-02）：被自己的影子按住。
	## 只有 move_mult = 0 + 禁闪，**不带 no_action** —— 人被钉住但还能出手，
	## 这是它的应对面：定身不是失去回合，而是「这一拍你得把背留给它」。
	"shadow_bind": {
		"name": "影缚",
		"desc": "被影子钉在原地，无法移动与闪避（仍可出手）",
		"color": Color(0.40, 0.46, 0.62, 1.0),
		"move_mult": 0.0,
		"no_dodge": true,
	},
	## 蚀（暗属性专属 · 2026-11-05 用户定）
	## ⚠ 不写在任何 form 的 debuff_on_hit 里：它是**元素规则**，由 take_damage 见到
	##   element == "dark" 时自动挂（见 AttributeDB.DARK_EROSION_*）。
	##   这样将来任何暗来源（别的 BOSS / 符箓 / 装备特效）不用配置就生效，
	##   也避免把「暗」重新绑回某一只 BOSS 的媒介上。
	"dark_erosion": {
		"name": "蚀",
		"desc": "减免被打穿（抗性只剩 60% 生效），且受到的治疗只剩 10%",
		"color": Color(0.44, 0.38, 0.60, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
		"resist_shred": 0.40,
		"heal_mult": 0.10,
	},
	## 影没（执烛的通用减速：踏灯走廊、照骨命中、空抓的墨痕）
	"shadow_soak": {
		"name": "影没",
		"desc": "脚下像踩进没有光的地方，移动速度 -35%",
		"color": Color(0.52, 0.58, 0.78, 1.0),
		"move_mult": 0.65,
		"no_dodge": false,
	},
	## 纸印（叠纸：被镜像落点按住的人 = 这块纸被压皱了，贴得比平时更紧）
	## 本表只负责名称/颜色/HUD；贴合带 +120 的读数在 FoldLaw.MARK_REACH_BONUS，
	## 由 BOSS 与玩家侧各自 has_debuff("fold_mark") 现查（不在施加时改状态）。
	"fold_mark": {
		"name": "纸印",
		"desc": "纸被压皱了：折痕对你的贴合带变宽，离痕更远才脱得开",
		"color": Color(0.80, 0.78, 0.66, 1.0),
		"move_mult": 1.0,
		"no_dodge": false,
	},
}


## 取一条 debuff 定义；未登记的 id 返回空字典（调用方按「无效果」处理）
static func get_debuff(id: String) -> Dictionary:
	return DEBUFFS.get(id, {})


## 显示名（未登记时回退 id 本身，方便发现拼错）
static func display_name(id: String) -> String:
	var d := get_debuff(id)
	return String(d.get("name", id)) if not d.is_empty() else id


## 标签配色（未登记时用警示红）
static func color(id: String) -> Color:
	var d := get_debuff(id)
	if d.is_empty():
		return UIKit.C_DANGER
	return Color(d.get("color", UIKit.C_DANGER))


## 效果摘要：把字段拼成一句玩家看得懂的话（数字全部来自本表，别在 UI 里手抄）。
## 功法库详情、图鉴状态模块、tooltip 共用这一份。
static func effect_text(id: String) -> String:
	var d := get_debuff(id)
	if d.is_empty():
		return "（该状态未登记效果）"
	var parts: Array[String] = []
	var mm := float(d.get("move_mult", 1.0))
	if mm < 1.0:
		parts.append("移速 -%d%%" % int(round((1.0 - mm) * 100.0)))
	if bool(d.get("no_dodge", false)):
		parts.append("期间无法闪避")
	var dm := float(d.get("dodge_mult", 1.0))
	if dm < 1.0:
		parts.append("闪避距离 -%d%%" % int(round((1.0 - dm) * 100.0)))
	if bool(d.get("no_stamina_regen", false)):
		parts.append("精力停止恢复")
	if bool(d.get("no_mana_regen", false)):
		parts.append("灵力停止回复")
	if bool(d.get("no_calamity_switch", false)):
		parts.append("期间无法切换灾位")
	if bool(d.get("no_skill", false)):
		parts.append("无法使用功法")
	var dtm := float(d.get("damage_taken_mult", 1.0))
	if dtm > 1.0:
		parts.append("受到伤害 +%d%%" % int(round((dtm - 1.0) * 100.0)))
	var shred := float(d.get("guard_shred", 0.0))
	if shred > 0.0:
		parts.append("护体类减伤效果减半（符箓除外）")
	var dot := float(d.get("dot_damage", 0.0))
	if dot > 0.0:
		parts.append("每 %.1f 秒扣 %.0f 点" % [float(d.get("dot_interval", 1.0)), dot])
	if parts.is_empty():
		return String(d.get("desc", ""))
	return "、".join(parts)


## 状态条说明（图鉴用）：HUD 上那些绿字 / 红字到底是什么意思
static func hud_primer() -> Array:
	return [
		"绿色是增益（buff）：列在第一个法宝格上方。次数型显示「名称 ×N」，用一次少一次，归零消失；时间型显示「名称 + 剩余秒数」，倒计时结束自动消失。",
		"红 / 橙系是负面（debuff）：列在功法栏上方，同样按剩余时间显示。名字后面的数字就是它还在身上的秒数。",
		"减速、封锁闪避、停止回精力、持续掉血这几类效果都是**每帧现查**的：状态一消失效果立刻还原，不需要谁去「解除」它。",
		"负面状态无法通过闪避的无敌帧移除；只能避免被命中（读前摇 / 弹反）或等待持续时间结束。",
	]
