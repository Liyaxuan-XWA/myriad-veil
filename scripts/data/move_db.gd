class_name MoveDB
extends RefCounted
## 招式形态表 —— BOSS 与玩家共享的「同一招」
##
## ============================ 设计意图 ============================
## 需求：BOSS 的招式可以在塔内击败 BOSS 后习得，玩家装备对应功法后能施展**相同的招式表现**；
## 但「玩家用」和「BOSS 用」的规则完全不同 —— 消耗、冷却、节奏、伤害来源都不一样，
## **只有表现（形态/特效/判定形状）相同**。
##
## 因此本表把一招拆成三层：
##
##   1. 形态层（FORMS 条目的根字段）
##      双方共享：命中形状、范围、张角、投射物速度/数量/散布、特效 visual_id、时序骨架。
##      → 换美术只改 visual_id（指向 ArtDB.EFFECTS 条目），玩法代码不动。
##
##   2. 玩家规则层（条目的 "player" 子字典）
##      灵力消耗 / 精力消耗 / 冷却 / 招式伤害系数 / 更短的前摇后摇 / 施法位移。
##      玩家伤害 = 玩家攻击力 × 兵器系数 × 功法系数 × **招式伤害系数** × 随机浮动
##
##   3. BOSS 规则层（条目的 "boss" 子字典）
##      attack_kind（决定能否被弹刀）/ 阶段倍率 / 伤害系数或固定伤害 / 蓄力倍率。
##      BOSS 伤害 = BOSS 攻击力 × **招式伤害系数** × 阶段倍率
##
## 玩家侧的「功法」见 SkillDB：一个功法通过 form_id 指向本表的一个形态，
## 并可以覆盖消耗与系数（例如同名招式但更省灵力/伤害更低）。
##
## ⚠ 本表只描述「招式怎么打」，不登记任何 BOSS 个体数值（血量/等级/选招顺序）。
##   BOSS 用哪些招式、按什么距离和权重选，见 WorldDB.BOSS_MOVES。

# ===== 命中形状 =====
const SHAPE_FAN := "fan"                ## 扇形近战（挥砍/横扫）
const SHAPE_LINE := "line"              ## 直线贯穿（突刺）
const SHAPE_CIRCLE := "circle"          ## 圆形范围（砸地/爆发）
const SHAPE_PROJECTILE := "projectile"  ## 投射物（箭矢/法球）
const SHAPE_SELF := "self"              ## 作用于自身（护体/增益）
const SHAPE_RECT := "rect"              ## 矩形长条（前方 长×宽；一剑开天·满层专用）

# ===== 玩家侧消耗类型 =====
const COST_MANA := "mana"           ## 消耗灵力
const COST_STAMINA := "stamina"     ## 消耗精力（与闪避/弹刀抢资源）
const COST_COOLDOWN := "cooldown"   ## 只走冷却，不耗资源
const COST_NONE := "none"           ## 无消耗（被动/普通攻击）

## ⚠⚠ 消耗准则（用户 2026-10-19 定，新增/调整招式一律照此配）：
##   · **物理伤害招式 → COST_STAMINA + stamina_cost 1**（只吃 1 格精力，不耗蓝）
##   · **法术伤害招式 → COST_MANA + mana_cost**（按强度定价，精力一格不掉）
##   · 混伤招式以主伤害类型为准；两个系数都 >0 时择优归类并在desc 写清
##   · 大招可追加 stamina_all / mana_all 抽空整条资源（一剑开天双形态）
##   · 改消耗只改本表 / SkillDB 的 cost_override，玩法脚本不写死数值

# ===== 施法者 =====
const CASTER_PLAYER := "player"
const CASTER_BOSS := "boss"

## 招式形态表
##
## 根字段（双方共享）
##   form_name      招式名（展示）
##   desc           说明文案
##   visual_id      美术替换口：ArtDB.EFFECTS 里的条目 id（空 = 由调用方自行处理表现）
##   hit_shape      命中形状，见顶部 SHAPE_* 常量
##   range          扇形/直线/圆形的有效半径；投射物则为最大飞行距离；
##                  矩形长条则为**长度**（前方，像素）
##   angle          扇形张角（度）；圆形/直线忽略
##   width          矩形**宽度**（像素，仅 SHAPE_RECT）：与 range（长度）共同构成长条判定
##   speed          投射物速度（仅 SHAPE_PROJECTILE）
##   count          投射物数量 / 连击段数
##   spread         多发时的扇形总散布角（度）
##   interval       多发之间的间隔（秒）；0 = 同帧全部发出
##   windup/active/recover   时序骨架（秒）。双方可各自覆盖
##   dash_speed/dash_time    招式附带的位移（0 = 不位移）
##   damage_element  元素属性（metal/wood/water/fire/earth/wind/thunder/dark），空串 = 无属性。
##                   仅影响「五行抗性」减免，法术伤害才有意义
##
## player 子字典（玩家使用规则）
##   cost_kind      COST_* 之一
##   mana_cost      灵力消耗
##   stamina_cost   精力消耗
##   stamina_all    true = 抽空当前**全部精力**（一剑开天普通形态；至少 1 格才能放）
##   mana_all       true = 抽空当前**全部灵力**（一剑开天·满层；至少 1 点才能放）
##   exhaust_time   >0 = 放完进入**力竭**（秒）：期间精力停止恢复（一剑开天普通形态 3 秒）
##                  ⚠ 满层变体不配这个字段 —— 用户定「法术形态不付力竭代价」
##   cooldown       冷却（秒）
##   phys_coeff     招式**物理**攻击系数（乘玩家物理攻击力）
##   spell_coeff    招式**法术**攻击系数（乘玩家法术攻击力）
##   两者可同时非 0（混伤招式），最终伤害见 DamageCalc
##   windup/active/recover   覆盖根字段的时序（玩家通常更轻快）
##   move_forward   施法时向前小位移距离（像素）。0 = 不位移；
##                  非 0 时玩家会在前摇期间朝技能方向冲相应距离（破步突进斩 90）。
##
## boss 子字典（BOSS 使用规则）
##   attack_kind    "physical_melee" / "physical_projectile" / "elemental"（决定能否弹刀）
##   parryable      是否可被弹刀（物理近战/投掷为 true，元素为 false）
##   damage_coeff   招式伤害系数（× BOSS 攻击力）
##   flat_damage    固定伤害（>0 时直接用该值，忽略 damage_coeff）
##   damage_mult_p2 二阶段伤害倍率
##   windup_mult_p2 二阶段蓄力缩短倍率
const FORMS: Dictionary = {
	# ============ 近战：单次横斩 ============
	"form_slash_single": {
		"form_name": "横斩",
		"damage_element": "earth",
		"desc": "一记大范围横斩，扇形覆盖身前。",
		"visual_id": "boss_blade_arc",
		"hit_shape": SHAPE_FAN,
		"range": 150.0,
		"angle": 110.0,
		"speed": 0.0,
		"count": 1,
		"spread": 0.0,
		"interval": 0.0,
		"windup": 0.85,
		"active": 0.15,
		"recover": 0.60,
		"dash_speed": 0.0,
		"dash_time": 0.0,
		"player": {
			"cost_kind": COST_STAMINA,
			"mana_cost": 0.0,
			"stamina_cost": 1,
			"cooldown": 2.5,
			"phys_coeff": 1.60,
			"spell_coeff": 0.0,
			"windup": 0.16,
			"active": 0.12,
			"recover": 0.22,
			"move_forward": 0.0,
		},
		"boss": {
			"attack_kind": "physical_melee",
			"parryable": true,
			"damage_coeff": 1.0,
			"damage_mult_p2": 1.5,
			"windup_mult_p2": 0.8,
		},
	},

	# ============ 远程：单发射箭 ============
	"form_arrow": {
		"form_name": "射箭",
		"damage_element": "earth",
		"desc": "射出一支箭矢，物理投掷，可被弹反。",
		"visual_id": "arrow_shot",
		"hit_shape": SHAPE_PROJECTILE,
		"range": 620.0,
		"angle": 0.0,
		"speed": 620.0,
		"count": 1,
		"spread": 0.0,
		"interval": 0.0,
		"windup": 0.55,
		"active": 0.10,
		"recover": 0.50,
		"dash_speed": 0.0,
		"dash_time": 0.0,
		"player": {
			"cost_kind": COST_STAMINA,
			"mana_cost": 0.0,
			"stamina_cost": 1,
			"cooldown": 1.8,
			"phys_coeff": 1.10,
			"spell_coeff": 0.0,
			"windup": 0.12,
			"active": 0.08,
			"recover": 0.20,
			"move_forward": 0.0,
		},
		"boss": {
			"attack_kind": "physical_projectile",
			"parryable": true,
			"damage_coeff": 1.0,
			"damage_mult_p2": 1.5,
			"windup_mult_p2": 0.8,
		},
	},

	# ============ 远程：五连发（扇形散布）============
	"form_arrow_volley": {
		"form_name": "五连射",
		"damage_element": "earth",
		"desc": "扇形连发多支箭矢，可逐支弹反。",
		"visual_id": "arrow_shot",
		"hit_shape": SHAPE_PROJECTILE,
		"range": 620.0,
		"angle": 0.0,
		"speed": 650.0,
		"count": 5,
		"spread": 28.0,
		"interval": 0.07,
		"windup": 0.60,
		"active": 0.10,
		"recover": 0.55,
		"dash_speed": 0.0,
		"dash_time": 0.0,
		"player": {
			"cost_kind": COST_STAMINA,
			"mana_cost": 0.0,
			"stamina_cost": 2,
			"cooldown": 10.0,
			"phys_coeff": 1.0,
			"spell_coeff": 0.0,
			"windup": 0.16,
			"active": 0.08,
			"recover": 0.28,
			"move_forward": 0.0,
		},
		"boss": {
			"attack_kind": "physical_projectile",
			"parryable": true,
			"damage_coeff": 1.0,
			"damage_mult_p2": 1.6,
			"windup_mult_p2": 0.8,
		},
	},

	# ============ 范围：砸地 ============
	"form_smash": {
		"form_name": "砸地",
		"damage_element": "earth",
		"desc": "重击地面，圆形范围震荡。",
		"visual_id": "smash_burst",
		"hit_shape": SHAPE_CIRCLE,
		"range": 120.0,
		"angle": 360.0,
		"speed": 0.0,
		"count": 1,
		"spread": 0.0,
		"interval": 0.0,
		"windup": 0.35,
		"active": 0.12,
		"recover": 0.60,
		"dash_speed": 0.0,
		"dash_time": 0.0,
		"player": {
			"cost_kind": COST_STAMINA,
			"mana_cost": 0.0,
			"stamina_cost": 1,
			"cooldown": 4.0,
			"phys_coeff": 1.40,
			"spell_coeff": 0.0,
			"windup": 0.20,
			"active": 0.10,
			"recover": 0.35,
			"move_forward": 0.0,
		},
		"boss": {
			"attack_kind": "physical_melee",
			"parryable": true,
			"damage_coeff": 1.0,
			"damage_mult_p2": 1.5,
			"windup_mult_p2": 0.8,
		},
	},

	# ============ 远程：元素法球 ============
	"form_element_orb": {
		"form_name": "元素法球",
		"desc": "凝聚法力掷出法球，法术伤害，受法抗与五行抗性减免，不可弹反。",
		"visual_id": "element_orb",
		"hit_shape": SHAPE_PROJECTILE,
		"damage_element": "water",
		"range": 600.0,
		"angle": 0.0,
		"speed": 338.0,
		"count": 1,
		"spread": 0.0,
		"interval": 0.0,
		"windup": 0.70,
		"active": 0.10,
		"recover": 0.55,
		"dash_speed": 0.0,
		"dash_time": 0.0,
		"player": {
			"cost_kind": COST_MANA,
			"mana_cost": 22.0,
			"stamina_cost": 0,
			"cooldown": 4.5,
			"phys_coeff": 0.0,
			"spell_coeff": 1.75,   # 元素法球是法术伤害
			"windup": 0.22,
			"active": 0.08,
			"recover": 0.30,
			"move_forward": 0.0,
		},
		"boss": {
			"attack_kind": "elemental",
			"parryable": false,
			"damage_coeff": 1.0,
			"damage_mult_p2": 1.5,
			"windup_mult_p2": 0.8,
		},
	},

	# ========================================================================
	# 刀客 BOSS 招式组（P1-P5 物理 / M1-M4 法术）
	# ------------------------------------------------------------------------
	# BOSS 侧：attack_power = 100，damage_coeff 直接等于「玩家满血百分比」，
	#          即 0.12 → 对 100 血玩家造成 12 伤害。
	# 玩家侧：phys_coeff / spell_coeff 是倍率，乘自己的攻击力。
	# 双方共用同一份形态与刀痕联动规则 —— 玩家学会后能搭出同类玩法。
	# ⚠ 二阶段伤害 ×2（用户 2026-10-27 定，见各招 damage_mult_p2；此前一直是 1.0 不加成）
	# ========================================================================

	# ============ P1 正面横斩 ============
	"form_blade_slash": {
		"form_name": "横斩",
		"damage_element": "metal",
		"desc": "向身前大范围横斩。",
		"visual_id": "boss_blade_arc",
		"hit_shape": SHAPE_FAN,
		"range": 150.0,
		"angle": 110.0,
		"windup": 0.85,
		"active": 0.15,
		"recover": 0.60,
		"player": {
			"cost_kind": COST_STAMINA,
			"mana_cost": 0.0,
			"stamina_cost": 1,
			"cooldown": 2.5, "phys_coeff": 1.40, "spell_coeff": 0.0,
			"windup": 0.16, "active": 0.12, "recover": 0.22,
			"move_forward": 0.0,
		},
		"boss": {
			"attack_kind": "physical_melee", "parryable": true,
			"damage_coeff": 0.12, "damage_mult_p2": 2.0, "windup_mult_p2": 0.9,
			"stagger_coeff": 0.12,
		},
	},

	# ============ P2 沉步竖斩 ============
	## 2026-10-23 用户定：前摇加长 + 命中挂「重伤」debuff（代替原来的 0.6 秒小减速）
	##   · windup 0.95 → 1.25：抬手更明显，给玩家留出躲开的时间
	##   · 命中 → 重伤 3 秒（无法闪避 + 移速 -50%，定义见 DebuffDB）
	"form_blade_heavy": {
		"form_name": "沉步竖斩",
		"damage_element": "metal",
		"desc": "沉身蓄力后竖斩，轨迹窄但伤害高，命中者身负重伤。",
		"visual_id": "boss_blade_arc",
		"hit_shape": SHAPE_FAN,
		"range": 165.0,
		"angle": 55.0,
		"windup": 1.25,
		"active": 0.15,
		"recover": 0.85,
		## 命中挂的 debuff（id 见 DebuffDB）与持续时间
		"debuff_on_hit": "wounded",
		"debuff_time": 3.0,
		"player": {
			"cost_kind": COST_STAMINA,
			"mana_cost": 0.0,
			"stamina_cost": 1,
			"cooldown": 4.0, "phys_coeff": 1.85, "spell_coeff": 0.0,
			"windup": 0.22, "active": 0.12, "recover": 0.30,
			"move_forward": 0.0,
		},
		"boss": {
			"attack_kind": "physical_melee", "parryable": true,
			"damage_coeff": 0.20, "damage_mult_p2": 2.0, "windup_mult_p2": 0.92,
			"stagger_coeff": 0.20,
		},
	},

	# ============ P3 破步突进斩 ============
	## 2026-10-23 用户定：距离翻倍 + 连续两段突进斩
	##   · 每段位移 = 原来的 2 倍：BOSS 走 dash_time（0.22 → 0.44，速度不变所以距离翻倍），
	##     玩家走 move_forward（90 → 180）
	##   · dash_times = 2：第一段斩完、短暂停顿后立刻再突进一次
	##   · **第二段方向**：BOSS 重新取玩家当前方位；玩家跟当前移动输入，没输入就沿用第一段
	##   ⚠ 两段各自结算一次伤害、各自留一道刀痕 —— 总伤害是原来的 2 倍
	"form_blade_dash": {
		"form_name": "破步突进斩",
		"damage_element": "metal",
		"desc": "朝目标方向连续两次突进斩击，每段落点都留下刀痕。",
		"visual_id": "boss_blade_arc",
		"hit_shape": SHAPE_FAN,
		"range": 130.0,
		"angle": 90.0,
		"windup": 0.70,
		"active": 0.15,
		"recover": 0.80,
		"dash_speed": 620.0,
		"dash_time": 0.44,
		## 连续突进的段数（1 = 老行为）与段间停顿（秒）
		"dash_times": 2,
		"dash_gap": 0.12,
		"scar_effect": "create",
		"scar_offset": 70.0,
		"player": {
			"cost_kind": COST_STAMINA,
			"mana_cost": 0.0,
			"stamina_cost": 1,
			"cooldown": 5.0, "phys_coeff": 1.35, "spell_coeff": 0.0,
			"windup": 0.14, "active": 0.10, "recover": 0.26,
			"move_forward": 180.0,
			## 玩家侧段间停顿比 BOSS 短：手感上更像一气呵成的连斩
			"dash_gap": 0.08,
		},
		"boss": {
			"attack_kind": "physical_melee", "parryable": true,
			"damage_coeff": 0.16, "damage_mult_p2": 2.0, "windup_mult_p2": 0.9,
			"stagger_coeff": 0.16,
			"dash_p2_mult": 1.08,
		},
	},

	# ============ P4 回身斩 ============
	"form_blade_turn": {
		"form_name": "回身斩",
		"damage_element": "metal",
		"desc": "转身向侧后方斩击，转身过程是可利用的窗口。",
		"visual_id": "boss_blade_arc",
		"hit_shape": SHAPE_FAN,
		"range": 115.0,
		"angle": 140.0,
		"windup": 0.55,
		"active": 0.15,
		"recover": 0.70,
		"player": {
			"cost_kind": COST_STAMINA,
			"mana_cost": 0.0,
			"stamina_cost": 1,
			"cooldown": 3.0, "phys_coeff": 1.20, "spell_coeff": 0.0,
			"windup": 0.10, "active": 0.10, "recover": 0.20,
			"move_forward": 0.0,
		},
		"boss": {
			"attack_kind": "physical_melee", "parryable": true,
			"damage_coeff": 0.14, "damage_mult_p2": 2.0, "windup_mult_p2": 0.85,
			"stagger_coeff": 0.14,
		},
	},

	# ============ P5 留痕斩 ============
	"form_blade_scar": {
		"form_name": "留痕斩",
		"damage_element": "metal",
		"desc": "中距离斩击，攻击终点留下刀痕，限制走位。",
		"visual_id": "boss_blade_arc_heavy",
		"hit_shape": SHAPE_FAN,
		"range": 220.0,
		"angle": 70.0,
		"windup": 0.80,
		"active": 0.15,
		"recover": 0.65,
		"scar_effect": "create",
		"scar_offset": 150.0,
		"player": {
			"cost_kind": COST_STAMINA,
			"mana_cost": 0.0,
			"stamina_cost": 1,
			"cooldown": 4.5, "phys_coeff": 1.10, "spell_coeff": 0.0,
			"windup": 0.18, "active": 0.12, "recover": 0.24,
			"move_forward": 0.0,
		},
		"boss": {
			"attack_kind": "physical_melee", "parryable": true,
			"damage_coeff": 0.12, "damage_mult_p2": 2.0, "windup_mult_p2": 0.92,
			"stagger_coeff": 0.12,
		},
	},

	# ============ M1 刀气追击 ============
	"form_blade_qi": {
		"form_name": "刀气追击",
		"desc": "直线刀气，穿过刀痕会激活最多 2 处（每处斩击系数 = 本次激活数）。",
		"visual_id": "blade_qi",
		"hit_shape": SHAPE_PROJECTILE,
		"damage_element": "metal",
		"range": 560.0,
		"angle": 0.0,
		"speed": 560.0,
		"count": 1,
		"spread": 0.0,
		"interval": 0.0,
		"windup": 0.65,
		"active": 0.10,
		"recover": 0.55,
		"scar_effect": "ignite_path",
		"scar_ignite_max": 2,
		"player": {
			"cost_kind": COST_MANA, "mana_cost": 22.0, "stamina_cost": 0,
			"cooldown": 6.0, "phys_coeff": 0.0, "spell_coeff": 1.50,
			"windup": 0.18, "active": 0.08, "recover": 0.26,
			"move_forward": 0.0,
		},
		"boss": {
			"attack_kind": "elemental", "parryable": false,
			"damage_coeff": 0.15, "damage_mult_p2": 2.0, "windup_mult_p2": 0.9,
			"cooldown_p1": 10.0, "cooldown_p2": 8.5,
		},
	},

	# ============ M2 封路刀域 ============
	"form_blade_field": {
		"form_name": "封路刀域",
		"damage_element": "metal",
		"desc": "激活范围内全部刀痕（最多 4 处）—— 铺满后一次激活即为满伤爆发。",
		"visual_id": "blade_field",
		"hit_shape": SHAPE_CIRCLE,
		"range": 210.0,
		"angle": 360.0,
		"windup": 0.75,
		"active": 0.12,
		"recover": 0.60,
		"scar_effect": "ignite_area",
		"scar_ignite_max": 4,
		"player": {
			"cost_kind": COST_MANA, "mana_cost": 26.0, "stamina_cost": 0,
			"cooldown": 8.0, "phys_coeff": 0.0, "spell_coeff": 0.90,
			"windup": 0.20, "active": 0.10, "recover": 0.28,
			"move_forward": 0.0,
		},
		"boss": {
			"attack_kind": "elemental", "parryable": false,
			"damage_coeff": 0.06, "damage_mult_p2": 2.0, "windup_mult_p2": 0.95,
			"cooldown_p1": 16.0, "cooldown_p2": 16.0,
		},
	},

	# ============ M3 纳势反击 ============
	"form_blade_counter": {
		"form_name": "纳势反击",
		"damage_element": "metal",
		"desc": "原地蓄力格挡，蓄得越久、挨得越多，反击越重。最多蓄 5 秒，左键可提前斩出。",
		"visual_id": "boss_blade_arc_heavy",
		"hit_shape": SHAPE_FAN,
		# BOSS 版：范围更大更广（必定蓄力 3 秒后释放）
		"range": 210.0,
		"angle": 140.0,
		"windup": 3.0,
		"active": 0.12,
		"recover": 0.65,
		"player": {
			"cost_kind": COST_STAMINA,
			"mana_cost": 0.0,
			"stamina_cost": 1,
			"cooldown": 7.0,
			# 基础物理伤害系数 1.0；实际系数见下方 charge_coeff_gain（无上限）
			"phys_coeff": 1.0, "spell_coeff": 0.0,
			"windup": 0.0, "active": 0.10, "recover": 0.24,
			"move_forward": 0.0,
			# ---- 蓄力格挡（>0 才启用这套机制）----
			# ⚠ 「格挡」是**功法自带的效果**，不是装备词条 —— 这些字段跟着招式走，
			#   换装备不影响；哪门功法写了 charge_max，哪门才有格挡机制。
			"charge_max": 5.0,        # 最大蓄力秒数，到点自动斩出
			# 格挡**减伤比例**（0.7 = 减伤 70%，即只承受 30%；2026-10-19 用户定）；仅对物理有效
			# ⚠ 代码里是 `amount *= (1 - charge_block)`，写的是「减掉多少」不是「承受多少」
			"charge_block": 0.7,
			# 每「蓄力 1 秒」与每「受击 1 次」各加多少伤害系数（无上限）
			# 实际系数 = phys_coeff(1.0) + (已蓄秒数 + 受击次数) × 本值
			"charge_coeff_gain": 0.5,
		},
		"boss": {
			"attack_kind": "physical_melee", "parryable": true,
			"damage_coeff": 0.18, "damage_mult_p2": 2.0, "windup_mult_p2": 0.9,
			"stagger_coeff": 0.18,
			"cooldown_p1": 20.0, "cooldown_p2": 17.0,
		},
	},

	# ============ M4 满势断岳 ============
	"form_blade_peak": {
		"form_name": "满势断岳",
		"desc": "目标踩在刀痕上时释放的远距重斩，出手方向锁定后不再追踪；沿途激活最多 3 处刀痕。",
		"visual_id": "blade_qi",
		"hit_shape": SHAPE_PROJECTILE,
		"damage_element": "metal",
		"range": 620.0,
		"angle": 0.0,
		"speed": 760.0,
		"count": 1,
		"spread": 0.0,
		"interval": 0.0,
		"windup": 1.10,
		"active": 0.12,
		"recover": 0.90,
		"scar_effect": "ignite_path",
		"scar_ignite_max": 3,
		"player": {
			"cost_kind": COST_MANA, "mana_cost": 34.0, "stamina_cost": 0,
			"cooldown": 12.0, "phys_coeff": 0.0, "spell_coeff": 2.00,
			"windup": 0.26, "active": 0.10, "recover": 0.34,
			"move_forward": 0.0,
		},
		"boss": {
			"attack_kind": "elemental", "parryable": false,
			"damage_coeff": 0.24, "damage_mult_p2": 2.0, "windup_mult_p2": 1.0,
			"cooldown_p1": 24.0, "cooldown_p2": 24.0,
			# ⚠ 刀势机制已整体删除（用户 2026-10-22 定）：
			#   满势断岳的触发条件改为「目标正站在刀痕上」（DomainBoss01._target_on_scar），
			#   原来的 momentum_cost / momentum_gain / momentum_loss 三个字段已全部移除。
			"body_scale": 1.35,
		},
	},

	# ========================================================================
	# 剑客（凡界第 3 位 BOSS，boss_01_c）—— 剑意蓄压体系
	#
	# 设计案（用户 2026-10-19）：BOSS 攻击力 20，靠「剑意」层数放大招。
	#   - 剑意上限 5：释放刺/撩/斩/云 +1，命中玩家再 +1；二阶段翻倍
	#   - BOSS 每累计被打 5 次，剑意 -1（玩家进攻能压制资源）
	#   - 万剑归宗（CD 15s）：2 + 剑意×2 把飞剑，放完清空剑意；二阶段禁用
	#   - 一剑开天（二阶段解锁）：消耗全部剑意，每层 +18 射程；
	#     满 5 层时变为**法术**且范围巨大（form_sword_heaven_full）
	#   - 穿：连续释放两次远程（云）后强制触发，突刺到玩家身后
	#   - 转阶段演出：三角封绝（3 点法术系数）+ 天剑阵（5 把插地剑）
	#   ⚠ 二阶段伤害 ×1.5（用户指定，比共有机制的 ×2 低，见各招 damage_mult_p2）
	# ========================================================================

	# ============ 刺：快、远、窄 ============
	## ⚠ line 形状的 angle 是**判定半宽**（BOSS 侧按扇形夹角过滤命中，0 度等于永远打不中），
	##   「窄」靠小张角实现，不是靠 line 本身
	"form_sword_stab": {
		"form_name": "刺",
		"desc": "一剑直取，快过视线。",
		"visual_id": "fx_sword_stab",
		"hit_shape": SHAPE_LINE,
		"damage_element": "metal",
		"range": 240.0,
		"angle": 26.0,
		"speed": 0.0,
		"count": 1,
		"spread": 0.0,
		"interval": 0.0,
		"windup": 0.30,
		"active": 0.10,
		"recover": 0.45,
		"dash_speed": 0.0,
		"dash_time": 0.0,
		"player": {
			"cost_kind": COST_STAMINA,
			"mana_cost": 0.0,
			"stamina_cost": 1,
			"cooldown": 2.0, "phys_coeff": 1.00, "spell_coeff": 0.0,
			"windup": 0.12, "active": 0.08, "recover": 0.20,
			"move_forward": 0.0,
			## 玩家侧剑意：释放 +1 层（命中不叠加，用户 2026-10-19 定）
			"intent_gain": 1,
		},
		"boss": {
			"attack_kind": "physical_melee", "parryable": true,
			# 刺是剑客最快、最远的点刺（前摇 0.30 / 二阶段 0.255），出手频率远高于撩斩；
			# 用户 2026-10-27 要求降低它的伤害：damage_coeff 1.0 → 0.7（攻击力 20 → 14，二阶段 21）
			"damage_coeff": 0.7, "damage_mult_p2": 1.5, "windup_mult_p2": 0.85,
			"stagger_coeff": 0.10,
		},
	},

	# ============ 撩：速度/距离/范围都中等 ============
	"form_sword_lift": {
		"form_name": "撩",
		"desc": "剑锋贴地而起，撩起一片寒光。",
		"visual_id": "fx_sword_lift",
		"hit_shape": SHAPE_FAN,
		"damage_element": "metal",
		"range": 170.0,
		"angle": 100.0,
		"speed": 0.0,
		"count": 1,
		"spread": 0.0,
		"interval": 0.0,
		"windup": 0.45,
		"active": 0.14,
		"recover": 0.50,
		"dash_speed": 0.0,
		"dash_time": 0.0,
		"player": {
			"cost_kind": COST_STAMINA,
			"mana_cost": 0.0,
			"stamina_cost": 1,
			"cooldown": 3.0, "phys_coeff": 2.00, "spell_coeff": 0.0,
			"windup": 0.16, "active": 0.10, "recover": 0.24,
			"move_forward": 0.0,
			"intent_gain": 1,
		},
		"boss": {
			"attack_kind": "physical_melee", "parryable": true,
			"damage_coeff": 2.0, "damage_mult_p2": 1.5, "windup_mult_p2": 0.88,
			"stagger_coeff": 0.20,
		},
	},

	# ============ 斩：距离短、范围大、前摇大 ============
	"form_sword_chop": {
		"form_name": "斩",
		"desc": "举剑过顶，全力下劈。",
		"visual_id": "fx_sword_chop",
		"hit_shape": SHAPE_FAN,
		"damage_element": "metal",
		"range": 120.0,
		"angle": 160.0,
		"speed": 0.0,
		"count": 1,
		"spread": 0.0,
		"interval": 0.0,
		"windup": 0.95,
		"active": 0.18,
		"recover": 0.75,
		"dash_speed": 0.0,
		"dash_time": 0.0,
		"player": {
			"cost_kind": COST_STAMINA,
			"mana_cost": 0.0,
			"stamina_cost": 1,
			"cooldown": 4.5, "phys_coeff": 3.00, "spell_coeff": 0.0,
			"windup": 0.24, "active": 0.12, "recover": 0.34,
			"move_forward": 0.0,
			"intent_gain": 1,
		},
		"boss": {
			"attack_kind": "physical_melee", "parryable": true,
			"damage_coeff": 3.0, "damage_mult_p2": 1.5, "windup_mult_p2": 0.92,
			"stagger_coeff": 0.30,
		},
	},

	# ============ 云：远程物理，飞出一把剑 ============
	"form_sword_cloud": {
		"form_name": "云",
		"desc": "袖手一挥，一剑破空而去。",
		"visual_id": "fx_sword_cloud",
		"hit_shape": SHAPE_PROJECTILE,
		"damage_element": "metal",
		"range": 520.0,
		"angle": 0.0,
		"speed": 460.0,
		"count": 1,
		"spread": 0.0,
		"interval": 0.0,
		"windup": 0.50,
		"active": 0.10,
		"recover": 0.55,
		"dash_speed": 0.0,
		"dash_time": 0.0,
		"player": {
			"cost_kind": COST_STAMINA,
			"mana_cost": 0.0,
			"stamina_cost": 1,
			"cooldown": 3.0, "phys_coeff": 1.00, "spell_coeff": 0.0,
			"windup": 0.18, "active": 0.08, "recover": 0.26,
			"move_forward": 0.0,
			"intent_gain": 1,
		},
		"boss": {
			"attack_kind": "physical_projectile", "parryable": true,
			"damage_coeff": 1.0, "damage_mult_p2": 1.5, "windup_mult_p2": 0.85,
			"stagger_coeff": 0.10,
			"cooldown_p1": 3.0, "cooldown_p2": 2.5,
		},
	},

	# ============ 穿：突刺到玩家身后（连续两次远程后强制触发）============
	"form_sword_pierce": {
		"form_name": "穿",
		"desc": "锁定对手，人与剑一同穿过。",
		"visual_id": "fx_sword_stab",
		"hit_shape": SHAPE_LINE,
		"damage_element": "metal",
		"range": 300.0,
		"angle": 40.0,
		"speed": 0.0,
		"count": 1,
		"spread": 0.0,
		"interval": 0.0,
		"windup": 0.55,
		"active": 0.12,
		"recover": 0.60,
		"dash_speed": 950.0,
		"dash_time": 0.34,
		"player": {
			"cost_kind": COST_STAMINA,
			"mana_cost": 0.0,
			"stamina_cost": 1,
			"cooldown": 3.5, "phys_coeff": 1.00, "spell_coeff": 0.0,
			"windup": 0.16, "active": 0.10, "recover": 0.26,
			# 前冲距离（2026-10-21 用户要求「位移更远」：60 → 180，约 2.7 个身位）
			# 速度 = 距离 / 前摇 ≈ 1020 px/s，与剑客本体「穿」的突进速度（950）同一档；
			# 走 velocity + move_and_slide，撞墙/撞 BOSS 会自然停住，不会穿模
			"move_forward": 180.0,
		},
		"boss": {
			"attack_kind": "physical_melee", "parryable": true,
			"damage_coeff": 1.0, "damage_mult_p2": 1.5, "windup_mult_p2": 0.85,
			"stagger_coeff": 0.10,
		},
	},

	# ============ 万剑归宗：一阶段大招，2 + 剑意×2 把飞剑 ============
	"form_sword_myriad": {
		"form_name": "万剑归宗",
		"desc": "万剑听令，自鞘中齐出。",
		"visual_id": "fx_sword_myriad",
		"hit_shape": SHAPE_PROJECTILE,
		"damage_element": "metal",
		"range": 620.0,
		"angle": 0.0,
		"speed": 420.0,
		"count": 2,
		"spread": 26.0,
		"interval": 0.09,
		"windup": 1.10,
		"active": 0.20,
		"recover": 0.90,
		"dash_speed": 0.0,
		"dash_time": 0.0,
		"player": {
			## 万剑归宗是**大招**：消耗 3 格精力（普通物理招式只吃 1 格，见头部消耗准则）
			"cost_kind": COST_STAMINA,
			"mana_cost": 0.0,
			"stamina_cost": 3,
			"cooldown": 20.0, "phys_coeff": 1.00, "spell_coeff": 0.0,
			"windup": 0.30, "active": 0.12, "recover": 0.40,
			"move_forward": 0.0,
			## 玩家侧剑意：飞剑数 = base + 剑意×per，放完清空剑意（镜像 BOSS 侧规则）
			"intent_count_scale": {"base": 2, "per": 2},
		},
		"boss": {
			"attack_kind": "physical_projectile", "parryable": true,
			"damage_coeff": 1.0, "damage_mult_p2": 1.5, "windup_mult_p2": 1.0,
			"stagger_coeff": 0.10,
			"cooldown_p1": 15.0, "cooldown_p2": 15.0,
		},
	},

	# ============ 一剑开天：二阶段大招，消耗全部剑意 ============
	"form_sword_heaven": {
		"form_name": "一剑开天",
		"desc": "剑意尽注于一剑，可开天光。",
		"visual_id": "fx_sword_heaven_charge",
		## 表现：走 SwordHeavenFx 四段流程（蓄力 → 劈落 → 撞击 → 地面劈痕）
		## 劈痕形状跟 hit_shape 走：扇形形态 → 扇形劈痕，矩形形态 → 矩形劈痕（与判定同尺寸）
		"fx_heaven": true,
		## 蓄力光效悬在头顶多高处（像素）
		"fx_charge_height": 150.0,
		## 劈落耗时（秒）：从头顶沿直线落到施法者身位
		"fx_release_time": 0.12,
		"hit_shape": SHAPE_FAN,
		"damage_element": "metal",
		"range": 220.0,
		"angle": 130.0,
		"speed": 0.0,
		"count": 1,
		"spread": 0.0,
		"interval": 0.0,
		"windup": 1.30,
		"active": 0.20,
		"recover": 1.00,
		"dash_speed": 0.0,
		"dash_time": 0.0,
		"player": {
			"cost_kind": COST_STAMINA,
			"mana_cost": 0.0,
			"stamina_cost": 0,
			"stamina_all": true,
			"exhaust_time": 3.0,
			"cooldown": 20.0, "phys_coeff": 4.00, "spell_coeff": 0.0,
			"windup": 0.34, "active": 0.12, "recover": 0.40,
			"move_forward": 0.0,
			## 玩家侧剑意：满 intent_full_at 层时切换 full_form_id 形态（法术矩形巨斩）
			## ⚠ intent_full_at 须与 player.gd 的 SWORD_INTENT_MAX 保持一致（那边是运行时上限）
			"intent_full_at": 5,
			"full_form_id": "form_sword_heaven_full",
		},
		"boss": {
			"attack_kind": "physical_melee", "parryable": true,
			"damage_coeff": 4.0, "damage_mult_p2": 1.5, "windup_mult_p2": 1.0,
			"stagger_coeff": 0.40,
		},
	},

	# ============ 一剑开天·满层：剑意叠满时变为法术长条巨斩 ============
	## 触发条件见 form_sword_heaven 的 player.intent_full_at（两侧通用）：
	##   - BOSS 侧  由 domain_boss_01_c._fire_heaven() 在满层时切换（原 FAN 300° 改矩形）
	##   - 玩家侧  由 player.gd::_cast_skill 在满层时切换；SkillDB 登记为**变体条目**
	##             （skill_sword_heaven_full，不进功法库、不首杀奖励，仅供切换与文案取数）
	## ⚠ 满层形态的玩家侧法术系数 = **20.0**（普通形态只有 4.00 物理）：
	## 5 层剑意全部注入这一剑，代价是抽空全部精力 + 全部灵力（见下方 player{}）。
	## 改伤害直接改 player{} 的 spell_coeff，功法库文案由 SkillDB 现算
	"form_sword_heaven_full": {
		"form_name": "一剑开天·剑意盈天",
		"desc": "剑意盈天，一剑既出，日月无光。",
		"visual_id": "fx_sword_heaven_charge",
		## 满层：蓄力更夸张、劈落放慢（巨剑演出 + 出伤延后到剑落地）
		"fx_heaven": true,
		## 满剑意专属：额外劈下一把程序化金黄巨剑（观感在 ArtDB.HEAVEN_CINEMATIC）
		"fx_giant_sword": true,
		"fx_charge_height": 220.0,
		"fx_release_time": 0.26,
		## 满剑意：蓄力 / 劈落光柱的横向宽度倍率（只加粗视觉，不改 1000×160 判定）
		"fx_beam_width_mult": 2.0,
		"hit_shape": SHAPE_RECT,
		"damage_element": "metal",
		"range": 1000.0,
		"width": 160.0,
		"angle": 0.0,
		"speed": 0.0,
		"count": 1,
		"spread": 0.0,
		"interval": 0.0,
		"windup": 1.30,
		"active": 0.20,
		"recover": 1.00,
		"dash_speed": 0.0,
		"dash_time": 0.0,
		"player": {
			"cost_kind": COST_STAMINA,
			"mana_cost": 0.0,
			"stamina_cost": 0,
			"stamina_all": true,
			"mana_all": true,
			## 满剑意（5 层）时这一剑的**法术系数**：20.0 = 普通形态（4.00 物理）的 5 倍
			"cooldown": 20.0, "phys_coeff": 0.0, "spell_coeff": 20.0,
			"windup": 0.34, "active": 0.12, "recover": 0.40,
			"move_forward": 0.0,
		},
		"boss": {
			"attack_kind": "elemental", "parryable": false,
			"damage_coeff": 4.0, "damage_mult_p2": 1.5, "windup_mult_p2": 1.0,
			"stagger_coeff": 0.0,
		},
	},

	# ============ 三角封绝：转阶段演出，三剑成阵后斩决 ============
	## 转阶段演出技：不参与选招、不登记为功法（BOSS_MOVES / SkillDB 都不收）
	"form_sword_triangle": {
		"form_name": "三角封绝",
		"desc": "三剑封位，剑成之刻便是斩决之刻。",
		"visual_id": "fx_sword_triangle",
		"hit_shape": SHAPE_CIRCLE,
		"damage_element": "metal",
		"range": 150.0,
		"angle": 0.0,
		"speed": 0.0,
		"count": 3,
		"spread": 0.0,
		"interval": 0.0,
		"windup": 2.0,
		"active": 0.10,
		"recover": 0.30,
		"dash_speed": 0.0,
		"dash_time": 0.0,
		"player": {
			"cost_kind": COST_NONE, "mana_cost": 0.0, "stamina_cost": 0,
			"cooldown": 0.0, "phys_coeff": 0.0, "spell_coeff": 0.0,
			"windup": 0.0, "active": 0.0, "recover": 0.0,
			"move_forward": 0.0,
		},
		"boss": {
			"attack_kind": "elemental", "parryable": false,
			"damage_coeff": 3.0, "damage_mult_p2": 1.5, "windup_mult_p2": 1.0,
			"stagger_coeff": 0.0,
		},
	},

	# ========================================================================
	# 两仪真人（位面 02 第 1 位，boss_02）—— 阴阳易位体系，共 8 式，8 式玩家全可学
	#
	# BOSS 侧机制（两仪护体）：
	#   · 同属性伤害 ×0.5、异属性 ×1.3；
	#   · **只有异色伤害削盾**（同色 0 / 异色 14）；弹反 20、完美闪避 20、起手闪避 6
	#     不看颜色，内部 0.12 秒冷却 —— 单流派靠防御手段也能破，第一战不绑两仪功法；
	#   · 破盾 → 硬直 + 翻面 + 易伤；**破盾后 3 秒封窗**，任何来源都削不动盾；
	#   · 两仪转前摇必成（打不断），只吃「读色」这一层反制。
	# 玩家侧机制（两仪势）：学会任意一门 yinyang 功法才激活，第一战不参与。
	#   · 物理算阳、术法算阴；打出与当前势相反的招 = 逆式（增伤 + 叠 1 层 + 翻面）；
	#   · 每层 +2%；异色命中带对印的目标触发「阴阳爆」（+25% 并消耗印）；
	#   · 两仪功法命中挂本属性印；两仪转清阴蚀、耗 1 层换「必定逆式」。
	# 定位分工：掌=站桩阳伤、指=远程阴伤挂蚀、三叠=阳系贴脸位移、
	#   风=阴系贴身领域、双鱼=一出手两色齐走、崩=满势收割、转=手动翻势、
	#   倒悬=防御转势。
	# ========================================================================

	# ---------- 1. 阳诀·焚脉掌（玩家可学）----------
	"form_yinyang_palm": {
		"form_name": "阳诀·焚脉掌",
		"desc": "阳火焚脉，近身一掌。逆式释放伤害更高。",
		"visual_id": "fx_yinyang_palm",
		"hit_shape": SHAPE_FAN,
		"damage_element": "fire",
		"range": 170.0,
		"angle": 150.0,
		"speed": 0.0,
		"count": 1,
		"spread": 0.0,
		"interval": 0.0,
		"windup": 0.75,
		"active": 0.15,
		"recover": 0.55,
		"dash_speed": 0.0,
		"dash_time": 0.0,
		"yinyang_polarity": "yang",
		"player": {
			"cost_kind": COST_STAMINA,
			"mana_cost": 0.0,
			"stamina_cost": 1,
			"cooldown": 3.0,
			"phys_coeff": 1.60,
			"spell_coeff": 0.0,
			"windup": 0.16,
			"active": 0.12,
			"recover": 0.22,
			"move_forward": 0.0,
		},
		"boss": {
			"attack_kind": "physical_melee",
			"parryable": true,
			"damage_coeff": 1.0,
			"damage_mult_p2": 1.25,
			"windup_mult_p2": 0.90,
			"stagger_coeff": 0.18,
		},
	},

	# ---------- 2. 阴诀·玄冥指（玩家可学）----------
	"form_yinyang_finger": {
		"form_name": "阴诀·玄冥指",
		"desc": "青黑指力贯穿一线，中者阴蚀入骨。",
		"visual_id": "fx_yinyang_finger",
		"hit_shape": SHAPE_LINE,
		"damage_element": "water",
		"range": 340.0,
		"angle": 22.0,
		"speed": 0.0,
		"count": 1,
		"spread": 0.0,
		"interval": 0.0,
		"windup": 0.70,
		"active": 0.12,
		"recover": 0.50,
		"dash_speed": 0.0,
		"dash_time": 0.0,
		"yinyang_polarity": "yin",
		"debuff_on_hit": "yin_erosion",
		"debuff_time": 6.0,
		"player": {
			"cost_kind": COST_MANA,
			"mana_cost": 22.0,
			"stamina_cost": 0,
			"cooldown": 4.5,
			"phys_coeff": 0.0,
			"spell_coeff": 1.75,
			"windup": 0.18,
			"active": 0.10,
			"recover": 0.24,
			"move_forward": 0.0,
		},
		"boss": {
			"attack_kind": "elemental",
			"parryable": false,
			"damage_coeff": 0.9,
			"damage_mult_p2": 1.25,
			"windup_mult_p2": 0.90,
			"stagger_coeff": 0.0,
		},
	},

	# ---------- 3. 两仪转（玩家可学 / BOSS 翻盾）----------
	"form_yinyang_flip": {
		"form_name": "两仪转",
		"desc": "拨转仪态，阴阳易位。",
		"visual_id": "fx_yinyang_flip",
		"hit_shape": SHAPE_SELF,
		"damage_element": "none",
		"range": 0.0,
		"angle": 0.0,
		"speed": 0.0,
		"count": 1,
		"spread": 0.0,
		"interval": 0.0,
		"windup": 0.60,
		"active": 0.20,
		"recover": 0.40,
		"dash_speed": 0.0,
		"dash_time": 0.0,
		"yinyang_polarity": "neutral",
		"player": {
			"cost_kind": COST_NONE,
			"mana_cost": 0.0,
			"stamina_cost": 0,
			"cooldown": 12.0,
			"phys_coeff": 0.0,
			"spell_coeff": 0.0,
			"windup": 0.20,
			"active": 0.10,
			"recover": 0.20,
			"move_forward": 0.0,
		},
		"boss": {
			"attack_kind": "elemental",
			"parryable": false,
			"damage_coeff": 0.0,
			"damage_mult_p2": 1.0,
			"windup_mult_p2": 1.0,
			"stagger_coeff": 0.0,
		},
	},

	# ---------- 4. 太极崩（玩家可学 / 二阶段大招）----------
	"form_yinyang_collapse": {
		"form_name": "太极崩",
		"desc": "阴阳二气归于一点，倾泻而出。势越高，威力越大。",
		"visual_id": "fx_yinyang_collapse",
		"hit_shape": SHAPE_CIRCLE,
		"damage_element": "none",
		"range": 260.0,
		"angle": 0.0,
		"speed": 0.0,
		"count": 1,
		"spread": 0.0,
		"interval": 0.0,
		"windup": 1.20,
		"active": 0.20,
		"recover": 0.80,
		"dash_speed": 0.0,
		"dash_time": 0.0,
		"yinyang_polarity": "mixed",
		"player": {
			"cost_kind": COST_MANA,
			"mana_cost": 26.0,
			"stamina_cost": 0,
			"cooldown": 20.0,
			"phys_coeff": 1.20,
			"spell_coeff": 1.80,
			"windup": 0.30,
			"active": 0.15,
			"recover": 0.40,
			"move_forward": 0.0,
		},
		"boss": {
			"attack_kind": "elemental",
			"parryable": false,
			# 2026-10-28 用户要求再调高：2.4 → 3.0（+25%）。24 攻 → 单发 68~76，二阶段 75~83
			"damage_coeff": 3.0,
			"damage_mult_p2": 1.10,
			"windup_mult_p2": 1.0,
			"stagger_coeff": 0.0,
			# 命中眩晕 2 秒（2026-10-28 用户定）。⚠ 只写在 boss{} 里：
			#   BOSS 的 _apply_form_debuff 读 resolve_boss，会挂；
			#   玩家的 _apply_player_skill_debuff 读 resolve_player，所以玩家版太极崩不会反向硬控 BOSS。
			"debuff_on_hit": "stun",
			"debuff_time": 2.0,
		},
	},

	# ---------- 5. 阳关三叠（玩家可学）----------
	"form_yinyang_triple": {
		"form_name": "阳关三叠",
		"desc": "三步叠浪，一浪高过一浪。",
		"visual_id": "fx_yinyang_triple",
		"hit_shape": SHAPE_FAN,
		"damage_element": "fire",
		"range": 150.0,
		"angle": 90.0,
		"speed": 0.0,
		"count": 3,
		"spread": 0.0,
		"interval": 0.0,
		"windup": 0.60,
		"active": 0.15,
		"recover": 0.70,
		"dash_speed": 720.0,
		"dash_time": 0.20,
		"dash_times": 3,
		"dash_gap": 0.10,
		"yinyang_polarity": "yang",
		"player": {
			"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 2,
			"cooldown": 7.0, "phys_coeff": 0.72, "spell_coeff": 0.0,
			"windup": 0.22, "active": 0.10, "recover": 0.18,
			"move_forward": 180.0,
			# ⚠ 三段各 180、判定扇形只有 150，而且冲刺会被身体挡住（探针实测：
			#   空场跑满 532；贴着 260 处的 BOSS 只走到 198 就被挡住）。
			#   所以它是「踏到人即停」的贴脸位移，不是穿身 —— 与破步同一套手感。
			# 玩家侧段间留 0.16 秒（BOSS 侧 0.10 要的是连踏压迫感；
			# 玩家这边得看清「踏—踏—踏」的节奏才好接下一招）
			"dash_gap": 0.16,
		},
		"boss": {
			"attack_kind": "physical_melee",
			"parryable": true,
			"damage_coeff": 0.55,
			"damage_mult_p2": 1.25,
			"windup_mult_p2": 0.90,
			"stagger_coeff": 0.10,
		},
	},

	# ---------- 6. 阴风蚀骨（玩家可学）----------
	"form_yinyang_wind": {
		"form_name": "阴风蚀骨",
		"desc": "阴风盘踞，蚀骨销魂。",
		"player_desc": "三步一候，阴风自足下生：近身者中蚀。",
		"visual_id": "fx_yinyang_wind",
		"hit_shape": SHAPE_CIRCLE,
		"damage_element": "water",
		"range": 180.0,
		"angle": 0.0,
		"speed": 0.0,
		"count": 3,
		"spread": 0.0,
		"interval": 0.45,
		"windup": 0.80,
		"active": 0.20,
		"recover": 0.60,
		"dash_speed": 0.0,
		"dash_time": 0.0,
		"yinyang_polarity": "yin",
		"debuff_on_hit": "yin_erosion",
		"debuff_time": 6.0,
		"player": {
			"cost_kind": COST_MANA, "mana_cost": 20.0, "stamina_cost": 0,
			"cooldown": 11.0, "phys_coeff": 0.0, "spell_coeff": 0.55,
			"windup": 0.30, "active": 0.10, "recover": 0.25,
			"move_forward": 0.0,
			# 玩家侧的「原地领域」跳数：与 BOSS 的 field_ticks 同义但分开写，
			# 免得两侧节奏被一次数值调整绑死
			"player_ticks": 3,
			"player_tick_interval": 0.45,
		},
		"boss": {
			"attack_kind": "elemental",
			"parryable": false,
			"damage_coeff": 0.45,
			"damage_mult_p2": 1.25,
			"windup_mult_p2": 0.95,
			"stagger_coeff": 0.0,
			"field_ticks": 3,
			"field_interval": 0.45,
		},
	},

	# ---------- 7. 阴阳双鱼（玩家可学）----------
	"form_yinyang_fish": {
		"form_name": "阴阳双鱼",
		"desc": "一阴一阳，双鱼衔尾而至。",
		"player_desc": "前衔阳、后抱阴：一出手两色齐到。",
		"visual_id": "fx_yinyang_fish",
		"hit_shape": SHAPE_PROJECTILE,
		"damage_element": "none",
		"range": 520.0,
		"angle": 0.0,
		"speed": 520.0,
		"count": 2,
		# ⚠ 不再用散射角分开两枚（spread/interval 归零）：
		#   分开与交叉全部交给下面的正弦摆动，平均航线始终压在瞄准线上
		"spread": 0.0,
		"interval": 0.0,
		## 侧向摆动（两侧共用）：两枚取反相 → 途中互相交叉，像两条鱼对游过来
		"swim_amp": 54.0,
		"swim_freq": 1.05,
		"windup": 0.70,
		"active": 0.10,
		"recover": 0.50,
		"dash_speed": 0.0,
		"dash_time": 0.0,
		"yinyang_polarity": "mixed",
		"player": {
			"cost_kind": COST_MANA, "mana_cost": 26.0, "stamina_cost": 0,
			"cooldown": 9.0, "phys_coeff": 0.85, "spell_coeff": 0.95,
			"windup": 0.26, "active": 0.10, "recover": 0.24,
			"move_forward": 0.0,
			# ⚠ 玩家侧这两枚弹**各吃一段系数**：阳弹只走 phys_coeff、阴弹只走 spell_coeff，
			#   所以 calc_skill_damage 的两段合计在这里等于「两弹总伤害」，
			#   实际结算在 player._calc_polarity_damage() 里按段拆开算。
		},
		"boss": {
			"attack_kind": "physical_projectile",
			"parryable": true,
			"damage_coeff": 0.7,
			"damage_mult_p2": 1.25,
			"windup_mult_p2": 0.90,
			"stagger_coeff": 0.10,
			"second_projectile_kind": "elemental",
		},
	},

	# ---------- 8. 两仪倒悬（玩家可学）----------
	"form_yinyang_counter": {
		"form_name": "两仪倒悬",
		"desc": "仪态倒悬，同源之力尽数奉还。",
		"visual_id": "fx_yinyang_counter",
		"hit_shape": SHAPE_FAN,
		"damage_element": "fire",
		"range": 190.0,
		"angle": 120.0,
		"speed": 0.0,
		"count": 1,
		"spread": 0.0,
		"interval": 0.0,
		"windup": 0.80,
		"active": 0.15,
		"recover": 0.50,
		"dash_speed": 0.0,
		"dash_time": 0.0,
		"yinyang_polarity": "yang",
		"player": {
			"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 2,
			"cooldown": 12.0, "phys_coeff": 0.95, "spell_coeff": 0.0,
			"windup": 0.0, "active": 0.10, "recover": 0.24,
			"move_forward": 0.0,
			# 守势走「蓄力格挡」那条释放路径（纳势反击同一套），但判定规则不同：
			# charge_block 在这里**不生效** —— 同色是全额奉还、异色是破势，见 yinyang_ward
			"charge_max": 1.0,
			"charge_block": 0.0,
			"charge_coeff_gain": 0.35,
			"yinyang_ward": true,
		},
		"boss": {
			"attack_kind": "physical_melee",
			"parryable": true,
			"damage_coeff": 1.4,
			"damage_mult_p2": 1.25,
			"windup_mult_p2": 0.90,
			"stagger_coeff": 0.30,
			"counter_window": 0.8,
		},
	},

	# ========================================================================
	# 定阵先生（冲和界第 2 位，boss_02_b）—— 阵旗 · 连线，共 8 式，玩家全可学
	#   布点：插旗；用线：引阵 / 卷阵 / 封阵；不依赖旗：扫阵 / 踏阵 / 垒旗 / 解阵
	# 阵旗实体与阵线判定在 domain_boss_02_b.gd；本表只管招式数值。
	# ========================================================================
	"form_array_plant": {
		"form_name": "插旗·定星", "desc": "一旗落定，星位自成。",
		"visual_id": "fx_array_plant", "hit_shape": SHAPE_SELF, "damage_element": "earth",
		"range": 320.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.60, "active": 0.10, "recover": 0.45, "dash_speed": 0.0, "dash_time": 0.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 12.0, "stamina_cost": 0, "cooldown": 5.0,
			"phys_coeff": 0.0, "spell_coeff": 0.0, "windup": 0.18, "active": 0.08,
			"recover": 0.20, "move_forward": 0.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.0,
			"damage_mult_p2": 1.0, "windup_mult_p2": 1.0, "stagger_coeff": 0.0,
			"cooldown_p1": 6.0, "cooldown_p2": 5.0, "plant_flags": 1},
	},
	"form_array_line": {
		"form_name": "引阵·朱弦", "desc": "两旗之间崩起一道朱弦。",
		"visual_id": "fx_array_line", "hit_shape": SHAPE_LINE, "damage_element": "fire",
		"range": 520.0, "width": 60.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.75, "active": 0.12, "recover": 0.50, "dash_speed": 0.0, "dash_time": 0.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 22.0, "stamina_cost": 0, "cooldown": 8.0,
			"phys_coeff": 0.0, "spell_coeff": 1.55, "windup": 0.24, "active": 0.10,
			"recover": 0.28, "move_forward": 0.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 1.10,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.92, "stagger_coeff": 0.0,
			"cooldown_p1": 7.0, "cooldown_p2": 6.0},
	},
	"form_array_pull": {
		"form_name": "卷阵·收旗", "desc": "旗随线起，卷回身侧。",
		"visual_id": "fx_array_pull", "hit_shape": SHAPE_LINE, "damage_element": "earth",
		"range": 380.0, "width": 54.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.65, "active": 0.12, "recover": 0.45, "dash_speed": 0.0, "dash_time": 0.0,
		"player": {"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 1, "cooldown": 7.0,
			"phys_coeff": 1.15, "spell_coeff": 0.0, "windup": 0.16, "active": 0.10,
			"recover": 0.24, "move_forward": 0.0},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 0.90,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.92, "stagger_coeff": 0.12,
			"cooldown_p1": 8.0, "cooldown_p2": 7.0},
	},
	"form_array_seal": {
		"form_name": "封阵·四象", "desc": "四面旗成，四象成牢。",
		"visual_id": "fx_array_seal", "hit_shape": SHAPE_CIRCLE, "damage_element": "fire",
		"range": 210.0, "angle": 0.0, "speed": 0.0, "count": 3, "spread": 0.0, "interval": 0.45,
		"windup": 1.10, "active": 0.20, "recover": 0.70, "dash_speed": 0.0, "dash_time": 0.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 26.0, "stamina_cost": 0, "cooldown": 13.0,
			"phys_coeff": 0.0, "spell_coeff": 0.60, "windup": 0.30, "active": 0.15,
			"recover": 0.32, "move_forward": 0.0,
			"player_ticks": 4, "player_tick_interval": 0.55},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.50,
			"damage_mult_p2": 1.25, "windup_mult_p2": 1.0, "stagger_coeff": 0.0,
			"cooldown_p1": 16.0, "cooldown_p2": 14.0,
			"needs_flags": 4, "field_ticks": 4, "field_interval": 0.55},
	},
	"form_array_sweep": {
		"form_name": "扫阵·横天", "desc": "盘若轮转，旗风横天。",
		"visual_id": "fx_array_sweep", "hit_shape": SHAPE_FAN, "damage_element": "earth",
		"range": 160.0, "angle": 150.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.62, "active": 0.12, "recover": 0.42, "dash_speed": 0.0, "dash_time": 0.0,
		"player": {"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 1, "cooldown": 3.0,
			"phys_coeff": 1.30, "spell_coeff": 0.0, "windup": 0.14, "active": 0.10,
			"recover": 0.20, "move_forward": 0.0},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 1.00,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.90, "stagger_coeff": 0.18,
			"cooldown_p1": 3.5, "cooldown_p2": 3.0},
	},
	"form_array_step": {
		"form_name": "踏阵·走罡", "desc": "踩罡步斗，一步一旗。",
		"visual_id": "fx_array_step", "hit_shape": SHAPE_CIRCLE, "damage_element": "earth",
		"range": 110.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.55, "active": 0.12, "recover": 0.40,
		"dash_speed": 760.0, "dash_time": 0.18, "dash_times": 1,
		"player": {"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 1, "cooldown": 6.0,
			"phys_coeff": 0.95, "spell_coeff": 0.0, "windup": 0.12, "active": 0.10,
			"recover": 0.20, "move_forward": 220.0},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 0.75,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.90, "stagger_coeff": 0.12,
			"cooldown_p1": 6.0, "cooldown_p2": 5.0},
	},
	"form_array_pile": {
		"form_name": "垒旗·镇岳", "desc": "旗作山岳，一落镇地。",
		"visual_id": "fx_array_pile", "hit_shape": SHAPE_CIRCLE, "damage_element": "earth",
		"range": 120.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 1.10, "active": 0.15, "recover": 0.60, "dash_speed": 0.0, "dash_time": 0.0,
		"player": {"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 2, "cooldown": 9.0,
			"phys_coeff": 1.75, "spell_coeff": 0.0, "windup": 0.26, "active": 0.12,
			"recover": 0.32, "move_forward": 0.0},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 1.40,
			"damage_mult_p2": 1.25, "windup_mult_p2": 1.0, "stagger_coeff": 0.30,
			"cooldown_p1": 10.0, "cooldown_p2": 9.0,
			"debuff_on_hit": "wounded", "debuff_time": 2.0},
	},
	"form_array_burst": {
		"form_name": "解阵·雷落", "desc": "万阵皆解，雷自旗落。",
		"visual_id": "fx_array_burst", "hit_shape": SHAPE_CIRCLE, "damage_element": "fire",
		"range": 140.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 1.20, "active": 0.20, "recover": 0.70, "dash_speed": 0.0, "dash_time": 0.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 30.0, "stamina_cost": 0, "cooldown": 15.0,
			"phys_coeff": 0.0, "spell_coeff": 1.90, "windup": 0.30, "active": 0.15,
			"recover": 0.36, "move_forward": 0.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.60,
			"damage_mult_p2": 1.10, "windup_mult_p2": 1.0, "stagger_coeff": 0.0,
			"cooldown_p1": 18.0, "cooldown_p2": 16.0, "consume_flags": 4},
	},

	# ========================================================================
	# 太虚气君（冲和界第 3 位）—— 气环 · 化劲
	# ========================================================================
	"form_qi_gather": {
		"form_name": "引气·聚环", "desc": "一息入怀，气环自生。",
		"player_desc": "引一道气入体，凝成一枚气环（最多 5 枚）。",
		"visual_id": "fx_qi_gather", "hit_shape": SHAPE_SELF, "damage_element": "wind",
		"range": 0.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.55, "active": 0.10, "recover": 0.35, "dash_speed": 0.0, "dash_time": 0.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 8.0, "stamina_cost": 0, "cooldown": 4.0,
			"phys_coeff": 0.0, "spell_coeff": 0.0, "windup": 0.18, "active": 0.08,
			"recover": 0.18, "move_forward": 0.0, "qi_gain": 1},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.0,
			"damage_mult_p2": 1.0, "windup_mult_p2": 1.0, "stagger_coeff": 0.0,
			"cooldown_p1": 4.5, "cooldown_p2": 4.0, "qi_gain": 1},
	},
	"form_qi_wave": {
		"form_name": "冲气·裂空", "desc": "气冲一线，裂石分云。",
		"player_desc": "一道压缩气浪贯穿前方；消耗 1 枚气环，伤害 +0.5 倍、射程 +90。",
		"visual_id": "fx_qi_wave", "hit_shape": SHAPE_LINE, "damage_element": "wind",
		"range": 460.0, "width": 50.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.68, "active": 0.12, "recover": 0.45,
		"player": {"cost_kind": COST_MANA, "mana_cost": 18.0, "stamina_cost": 0, "cooldown": 6.0,
			"phys_coeff": 0.0, "spell_coeff": 1.30, "windup": 0.22, "active": 0.12,
			"recover": 0.26, "move_forward": 0.0, "qi_spend": 1, "qi_bonus_coeff": 0.50, "qi_bonus_range": 90.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 1.05,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.92, "stagger_coeff": 0.0,
			"cooldown_p1": 6.0, "cooldown_p2": 5.0, "qi_spend": 1, "qi_bonus_coeff": 0.35, "qi_bonus_range": 90.0},
	},
	"form_qi_spin": {
		"form_name": "御风·回旋", "desc": "身随气转，风自成环。",
		"player_desc": "气环随身横扫一圈，把近身敌人与 BOSS 推开。",
		"visual_id": "fx_qi_spin", "hit_shape": SHAPE_CIRCLE, "damage_element": "wind",
		"range": 150.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.60, "active": 0.12, "recover": 0.40,
		"player": {"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 1, "cooldown": 6.0,
			"phys_coeff": 1.00, "spell_coeff": 0.0, "windup": 0.16, "active": 0.12,
			"recover": 0.22, "move_forward": 0.0, "knockback": 320.0},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 0.90,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.92, "stagger_coeff": 0.18,
			"cooldown_p1": 8.0, "cooldown_p2": 7.0, "knockback": 320.0},
	},
	"form_qi_lock": {
		"form_name": "气锁·缚脉", "desc": "气结如锁，脉滞难行。",
		"player_desc": "前方扇面锁住气脉：命中者灵力停回、移速下降；消耗 1 枚气环可把 BOSS 减速压到 50%，并封技 2 秒。",
		"visual_id": "fx_qi_lock", "hit_shape": SHAPE_FAN, "damage_element": "wind",
		"range": 200.0, "angle": 90.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.62, "active": 0.12, "recover": 0.40,
		"player": {"cost_kind": COST_MANA, "mana_cost": 14.0, "stamina_cost": 0, "cooldown": 9.0,
			"phys_coeff": 0.0, "spell_coeff": 0.65, "windup": 0.20, "active": 0.10,
			"recover": 0.24, "move_forward": 0.0, "debuff_on_hit": "qi_stagnation", "debuff_time": 4.0,
			"qi_spend": 1, "qi_lock_slow": 0.50, "qi_lock_skill": 2.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.55,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.95, "stagger_coeff": 0.0,
			"cooldown_p1": 9.0, "cooldown_p2": 8.0, "debuff_on_hit": "qi_stagnation", "debuff_time": 4.0},
	},
	"form_qi_ward": {
		"form_name": "化劲·卸力", "desc": "引进落空，借力还施。",
		"player_desc": "消耗 1 枚气环：短时间受击转为蓄劲，结束时把蓄下的力放出去。",
		"visual_id": "fx_qi_ward", "hit_shape": SHAPE_SELF, "damage_element": "wind",
		"range": 0.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.50, "active": 0.10, "recover": 0.40, "dash_speed": 0.0, "dash_time": 0.0,
		"player": {"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 2, "cooldown": 16.0,
			"phys_coeff": 0.0, "spell_coeff": 0.0, "windup": 0.14, "active": 0.08,
			"recover": 0.20, "move_forward": 0.0, "qi_need": 1, "qi_ward_time": 2.2,
			"qi_ward_reduce": 0.40, "qi_ward_store": 0.60, "qi_ward_cap": 140.0,
			"qi_release_coeff": 1.20, "qi_release_radius": 260.0},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 0.0,
			"damage_mult_p2": 1.0, "windup_mult_p2": 1.0, "stagger_coeff": 0.0,
			"cooldown_p1": 16.0, "cooldown_p2": 14.0, "qi_need": 3, "qi_ward_time": 2.2,
			"qi_ward_reduce": 0.40, "qi_ward_store": 0.60, "qi_ward_cap": 140.0,
			"qi_release_coeff": 1.20, "qi_release_radius": 260.0},
	},
	"form_qi_step": {
		"form_name": "踏罡·缩地", "desc": "一步罡斗，缩地成寸。",
		"player_desc": "向前突进并结算一次；落地凝成 1 枚气环。",
		"visual_id": "fx_qi_step", "hit_shape": SHAPE_CIRCLE, "damage_element": "wind",
		"range": 110.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.55, "active": 0.12, "recover": 0.40, "dash_speed": 760.0, "dash_time": 0.26, "dash_times": 1,
		"player": {"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 1, "cooldown": 6.0,
			"phys_coeff": 0.80, "spell_coeff": 0.0, "windup": 0.12, "active": 0.10,
			"recover": 0.20, "move_forward": 220.0, "qi_gain": 1},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 0.70,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.90, "stagger_coeff": 0.12,
			"cooldown_p1": 7.0, "cooldown_p2": 6.0},
	},
	"form_qi_burst": {
		"form_name": "气爆·周天", "desc": "周天一转，气海倾泻。",
		"player_desc": "引爆全部气环：环越多，爆得越狠。",
		"visual_id": "fx_qi_burst", "hit_shape": SHAPE_CIRCLE, "damage_element": "wind",
		"range": 240.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.90, "active": 0.15, "recover": 0.55, "dash_speed": 0.0, "dash_time": 0.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 30.0, "stamina_cost": 0, "cooldown": 15.0,
			"phys_coeff": 0.0, "spell_coeff": 1.00, "windup": 0.26, "active": 0.12,
			"recover": 0.30, "move_forward": 0.0, "qi_spend_all": true, "qi_per_coeff": 0.60},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 1.00,
			"damage_mult_p2": 1.10, "windup_mult_p2": 1.0, "stagger_coeff": 0.0,
			"cooldown_p1": 20.0, "cooldown_p2": 18.0, "qi_spend_all": true, "qi_per_coeff": 0.60},
	},
	"form_qi_breath": {
		"form_name": "归元·吐纳", "desc": "一吐一纳，气归丹田。",
		"player_desc": "消耗 1 枚气环吐纳回复气血；引导 1.2 秒，期间受伤超过 8% 最大气血会被打断。",
		"visual_id": "fx_qi_breath", "hit_shape": SHAPE_SELF, "damage_element": "wind",
		"range": 0.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.80, "active": 0.10, "recover": 0.45, "dash_speed": 0.0, "dash_time": 0.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 20.0, "stamina_cost": 0, "cooldown": 10.0,
			"phys_coeff": 0.0, "spell_coeff": 0.0, "windup": 0.30, "active": 0.10,
			"recover": 0.30, "move_forward": 0.0, "heal_pct": 0.10, "qi_need": 1,
			"channel_time": 1.2, "channel_break_damage": 0.08},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.0,
			"damage_mult_p2": 1.0, "windup_mult_p2": 1.0, "stagger_coeff": 0.0,
			"cooldown_p1": 18.0, "cooldown_p2": 16.0, "heal_pct": 0.10,
			"channel_time": 1.2, "channel_break_damage": 0.08},
	},

	# ========================================================================
	# 赫连霄（赤霄界第 1 位，boss_03）—— 判词 · 天律
	#
	# 核心：宣判 / 判词·天律 按目标最近行为落一条「律」：
	#   禁行（移动）/ 禁攻（出手）/ 禁避（闪避）/ 禁立（站定）。
	#   违律 → 落雷 + 雷势 +1；守律 → 顺天 + 雷势 -1；宣判可弹反（抗辩）。
	# 八式双侧：判词 / 定刑 / 雷鼓 / 锁雷 / 雷遁 / 聚雷 / 九霄 / 雷牢。
	# 雷属法术统一记 metal（金），走五行抗性；物理招不带属性。
	# ========================================================================

	# ---------- 1. 判词·天律（宣判·落笔）----------
	"form_thunder_verdict": {
		"form_name": "判词·天律", "desc": "笔锋落处，天律即成：违律者引雷，守律者顺天。",
		"player_desc": "按目标近 1.5 秒的行为落一条判词；目标违律会给你雷势。",
		"visual_id": "fx_thunder_verdict", "hit_shape": SHAPE_LINE, "damage_element": "thunder",
		"range": 320.0, "width": 56.0, "angle": 0.0, "speed": 0.0, "count": 1,
		"spread": 0.0, "interval": 0.0,
		"windup": 0.85, "active": 0.12, "recover": 0.55, "dash_speed": 0.0, "dash_time": 0.0,
		"thunder_verdict": true, "verdict_time": 5.0, "verdict_range": 360.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 16.0, "stamina_cost": 0, "cooldown": 12.0,
			"phys_coeff": 0.0, "spell_coeff": 0.45, "windup": 0.22, "active": 0.10,
			"recover": 0.24, "move_forward": 0.0, "verdict_time": 5.0},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 0.55,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.90, "stagger_coeff": 0.15,
			"cooldown_p1": 9.0, "cooldown_p2": 8.5, "verdict_time": 5.0, "verdict_time_p2": 6.0},
	},

	# ---------- 2. 定刑·雷殛 ----------
	"form_thunder_execute": {
		"form_name": "定刑·雷殛", "desc": "笔尖一点，天雷落于所点之处。",
		"player_desc": "指定落点延迟落雷；目标身上有判词时伤害 +50%。",
		"visual_id": "fx_thunder_execute", "hit_shape": SHAPE_CIRCLE, "damage_element": "thunder",
		"range": 90.0, "cast_range": 420.0, "targeted_circle": true, "delay": 0.45,
		"angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.65, "active": 0.10, "recover": 0.50, "dash_speed": 0.0, "dash_time": 0.0,
		"verdict_bonus": 0.50,
		"player": {"cost_kind": COST_MANA, "mana_cost": 18.0, "stamina_cost": 0, "cooldown": 6.5,
			"phys_coeff": 0.0, "spell_coeff": 0.95, "windup": 0.24, "active": 0.10,
			"recover": 0.24, "move_forward": 0.0, "targeted_circle": true, "cast_range": 420.0,
			"delay": 0.45, "verdict_bonus": 0.50},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 1.05,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.90, "stagger_coeff": 0.0,
			"cooldown_p1": 6.5, "cooldown_p2": 6.0, "targeted_circle": true,
			"cast_range": 420.0, "delay": 0.45, "verdict_bonus": 0.50},
	},

	# ---------- 3. 雷鼓·震天 ----------
	"form_thunder_drum": {
		"form_name": "雷鼓·震天", "desc": "鼓面一响，雷从地起，震开近身之敌。",
		"player_desc": "雷鼓震荡一圈，击退近身敌人。",
		"visual_id": "fx_thunder_drum", "hit_shape": SHAPE_CIRCLE, "damage_element": "thunder",
		"range": 180.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.60, "active": 0.12, "recover": 0.45, "dash_speed": 0.0, "dash_time": 0.0,
		"knockback": 360.0,
		"player": {"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 1, "cooldown": 7.0,
			"phys_coeff": 1.00, "spell_coeff": 0.0, "windup": 0.16, "active": 0.10,
			"recover": 0.22, "move_forward": 0.0, "knockback": 260.0},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 1.00,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.90, "stagger_coeff": 0.20,
			"cooldown_p1": 7.0, "cooldown_p2": 6.5, "knockback": 360.0},
	},

	# ---------- 4. 锁雷·缚魂 ----------
	"form_thunder_lock": {
		"form_name": "锁雷·缚魂", "desc": "雷链贴地游走，锁住脚步与身法。",
		"player_desc": "直线雷链：命中挂「滞雷」——移速下降、闪避距离缩短。",
		"visual_id": "fx_thunder_lock", "hit_shape": SHAPE_LINE, "damage_element": "thunder",
		"range": 300.0, "width": 54.0, "angle": 0.0, "speed": 0.0, "count": 1,
		"spread": 0.0, "interval": 0.0,
		"windup": 0.65, "active": 0.12, "recover": 0.45, "dash_speed": 0.0, "dash_time": 0.0,
		"debuff_on_hit": "thunder_stagnation", "debuff_time": 4.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 14.0, "stamina_cost": 0, "cooldown": 9.0,
			"phys_coeff": 0.0, "spell_coeff": 0.55, "windup": 0.20, "active": 0.10,
			"recover": 0.24, "move_forward": 0.0,
			"debuff_on_hit": "thunder_stagnation", "debuff_time": 3.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.65,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.95, "stagger_coeff": 0.0,
			"cooldown_p1": 9.0, "cooldown_p2": 8.0,
			"debuff_on_hit": "thunder_stagnation", "debuff_time": 4.0},
	},

	# ---------- 5. 雷遁·换位 ----------
	"form_thunder_step": {
		"form_name": "雷遁·换位", "desc": "身化雷光，一步即至。",
		"player_desc": "向前突进，落点结算一次雷击。",
		"visual_id": "fx_thunder_step", "hit_shape": SHAPE_CIRCLE, "damage_element": "thunder",
		"range": 110.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.50, "active": 0.12, "recover": 0.45, "dash_speed": 900.0, "dash_time": 0.18,
		"teleport_step": true, "teleport_dist": 110.0,
		"player": {"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 1, "cooldown": 6.0,
			"phys_coeff": 0.80, "spell_coeff": 0.0, "windup": 0.14, "active": 0.10,
			"recover": 0.20, "move_forward": 240.0},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 0.85,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.90, "stagger_coeff": 0.12,
			"cooldown_p1": 8.0, "cooldown_p2": 7.0, "teleport_step": true,
			"teleport_dist": 110.0},
	},

	# ---------- 6. 聚雷·引霆 ----------
	"form_thunder_gather": {
		"form_name": "聚雷·引霆", "desc": "以身为引，九霄之雷尽入此身。",
		"player_desc": "引导 1.2 秒：身周不断落雷，完成时 +1 雷势；受伤超过 8% 最大气血会被打断。",
		"visual_id": "fx_thunder_gather", "hit_shape": SHAPE_SELF, "damage_element": "thunder",
		"range": 0.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.70, "active": 0.10, "recover": 0.50, "dash_speed": 0.0, "dash_time": 0.0,
		"channel_time": 1.4, "channel_break_damage": 0.08, "gather_lei": 1,
		"gather_bolt_interval": 0.35, "gather_bolt_coeff": 0.35,
		"gather_bolt_radius": 80.0, "gather_bolt_spread": 200.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 20.0, "stamina_cost": 0, "cooldown": 15.0,
			"phys_coeff": 0.0, "spell_coeff": 0.0, "windup": 0.24, "active": 0.10,
			"recover": 0.24, "move_forward": 0.0, "channel_time": 1.2,
			"channel_break_damage": 0.08, "gather_lei": 1, "gather_bolt_interval": 0.40,
			"gather_bolt_coeff": 0.35, "gather_bolt_radius": 80.0, "gather_bolt_spread": 200.0,
			"gather_bolt_count": 3},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.0,
			"damage_mult_p2": 1.0, "windup_mult_p2": 1.0, "stagger_coeff": 0.0,
			"cooldown_p1": 14.0, "cooldown_p2": 12.0, "channel_time": 1.4,
			# BOSS 血量是玩家约 46 倍，8% 门槛会变成打不断的假引导；
			# 2.5% × 13000 ≈ 325，结丹标准档 1.4 秒普攻（约 346）可打断
			"channel_break_damage": 0.025, "gather_lei": 1,
			"gather_bolt_interval": 0.35, "gather_bolt_coeff": 0.35,
			"gather_bolt_radius": 80.0, "gather_bolt_spread": 200.0},
	},

	# ---------- 7. 九霄·雷罚 ----------
	"form_thunder_nine": {
		"form_name": "九霄·雷罚", "desc": "雷势越高，落下的雷柱越多。",
		"player_desc": "在目标周围落下 2 + 雷势 道雷柱，消耗全部雷势。",
		"visual_id": "fx_thunder_nine", "hit_shape": SHAPE_CIRCLE, "damage_element": "thunder",
		"range": 100.0, "cast_range": 520.0, "targeted_circle": true,
		"pillar_count_base": 2, "pillar_per_lei": 1, "pillar_spread": 120.0,
		"angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 1.20, "active": 0.20, "recover": 0.90, "dash_speed": 0.0, "dash_time": 0.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 30.0, "stamina_cost": 0, "cooldown": 20.0,
			"phys_coeff": 0.0, "spell_coeff": 0.85, "windup": 0.30, "active": 0.15,
			"recover": 0.34, "move_forward": 0.0, "targeted_circle": true,
			"cast_range": 520.0, "pillar_count_base": 2, "pillar_per_lei": 1,
			"pillar_spread": 120.0, "consumes_lei": true},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.90,
			"damage_mult_p2": 1.25, "windup_mult_p2": 1.0, "stagger_coeff": 0.0,
			"cooldown_p1": 24.0, "cooldown_p2": 22.0, "targeted_circle": true,
			"cast_range": 520.0, "pillar_count_base": 2, "pillar_per_lei": 1,
			"pillar_spread": 120.0, "consumes_lei": true},
	},

	# ---------- 8. 雷牢·天罚（二阶段）----------
	"form_thunder_prison": {
		"form_name": "雷牢·天罚", "desc": "雷环收拢，牢中之人尽受天罚。",
		"player_desc": "在目标脚下布下雷环，1.2 秒后收拢：仍在圈内者受重击并眩晕。",
		"visual_id": "fx_thunder_prison", "hit_shape": SHAPE_CIRCLE, "damage_element": "thunder",
		"range": 170.0, "cast_range": 520.0, "targeted_circle": true,
		"closing_time": 1.2, "prison_radius": 170.0,
		"angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.80, "active": 0.15, "recover": 0.60, "dash_speed": 0.0, "dash_time": 0.0,
		"debuff_on_hit": "stun", "debuff_time": 1.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 26.0, "stamina_cost": 0, "cooldown": 16.0,
			"phys_coeff": 0.0, "spell_coeff": 1.50, "windup": 0.26, "active": 0.15,
			"recover": 0.32, "move_forward": 0.0, "targeted_circle": true,
			"cast_range": 520.0, "closing_time": 1.2, "prison_radius": 170.0,
			"stagger_on_hit": 1.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 1.50,
			"damage_mult_p2": 1.25, "windup_mult_p2": 1.0, "stagger_coeff": 0.0,
			"cooldown_p1": 16.0, "cooldown_p2": 15.0, "targeted_circle": true,
			"cast_range": 520.0, "closing_time": 1.2, "prison_radius": 170.0,
			"debuff_on_hit": "stun", "debuff_time": 1.0},
	},

	# ========================================================================
	# 离照（赤霄界第 2 位，boss_03_b）—— 逐日·天火
	#
	# 核心：场上一枚「天火种」可被双方拾取 / 夺取 / 投掷 / 引爆。
	#   持种者每 1.6 秒叠 1 层日冕（最多 3 层）；3 层后灼心，3 秒后爆裂。
	#   火伤统一记 fire，走法抗 + 火抗；逐日步是物理近战，可弹反。
	# ========================================================================

	# ---------- 1. 逐日步 ----------
	"form_sun_step": {
		"form_name": "逐日步", "desc": "身化日影，一步夺火。",
		"player_desc": "无方向输入时朝火种突进；无火种或火种在身上则朝 BOSS；有方向输入按输入方向。撞到持种者时把火种夺过来。",
		"visual_id": "fx_sun_step", "hit_shape": SHAPE_CIRCLE, "damage_element": "fire",
		"range": 110.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0,
		"interval": 0.0, "windup": 0.55, "active": 0.12, "recover": 0.45,
		"dash_speed": 900.0, "dash_time": 0.18, "steal_seed": true, "steal_range": 130.0,
		"player": {"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 1, "cooldown": 5.0,
			"phys_coeff": 0.45, "spell_coeff": 0.0, "windup": 0.14, "active": 0.10,
			"recover": 0.20, "move_forward": 220.0, "steal_seed": true, "steal_range": 130.0},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 0.80,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.90, "stagger_coeff": 0.12,
			"cooldown_p1": 8.0, "cooldown_p2": 7.0, "dash_speed": 900.0, "dash_time": 0.18,
			"steal_seed": true, "steal_range": 130.0, "vulnerable_after": 0.7,
			"vulnerable_bonus": 0.15},
	},

	# ---------- 2. 日冕斩 ----------
	"form_sun_slash": {
		"form_name": "日冕斩", "desc": "日轮扇扫过，火冕层层叠开。",
		"player_desc": "持种时伤害提高并附加灼心；每层日冕再增伤。",
		"visual_id": "fx_sun_slash", "hit_shape": SHAPE_FAN, "damage_element": "fire",
		"range": 190.0, "angle": 110.0, "speed": 0.0, "count": 1, "spread": 0.0,
		"interval": 0.0, "windup": 0.65, "active": 0.12, "recover": 0.50,
		"dash_speed": 0.0, "dash_time": 0.0,
		"debuff_on_hit": "sunburn", "debuff_time": 3.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 16.0, "stamina_cost": 0, "cooldown": 6.0,
			"phys_coeff": 0.0, "spell_coeff": 1.15, "windup": 0.20, "active": 0.10,
			"recover": 0.24, "move_forward": 0.0, "seed_bonus": 0.20, "stack_bonus": 0.15,
			"debuff_on_hit": "sunburn", "debuff_time": 2.5},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.95,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.95, "stagger_coeff": 0.0,
			"cooldown_p1": 7.0, "cooldown_p2": 6.5, "seed_bonus": 0.25,
			"debuff_on_hit": "sunburn", "debuff_time": 3.0},
	},

	# ---------- 3. 投日 ----------
	"form_sun_throw": {
		"form_name": "投日", "desc": "把手中的太阳掷出去。",
		"player_desc": "持种：把火种沿弧线掷向目标，造成大额火伤并灼心；无种：掷余烬火球，造成 65% 伤害。",
		"visual_id": "fx_sun_throw", "hit_shape": SHAPE_PROJECTILE, "damage_element": "fire",
		"range": 520.0, "angle": 0.0, "speed": 460.0, "count": 1, "spread": 0.0,
		"interval": 0.0, "windup": 0.55, "active": 0.10, "recover": 0.45,
		"dash_speed": 0.0, "dash_time": 0.0, "requires_seed": true, "seed_throw": true,
		"debuff_on_hit": "sunburn", "debuff_time": 3.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 14.0, "stamina_cost": 0, "cooldown": 2.0,
			"phys_coeff": 0.0, "spell_coeff": 1.60, "windup": 0.22, "active": 0.10,
			"recover": 0.26, "move_forward": 0.0, "seed_throw": true,
			"projectile_speed": 460.0, "blast_radius": 100.0,
			"no_seed_coeff": 0.65, "no_seed_blast_radius": 90.0,
			"debuff_on_hit": "sunburn", "debuff_time": 3.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 1.60,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.90, "stagger_coeff": 0.0,
			"cooldown_p1": 6.5, "cooldown_p2": 6.0, "requires_seed": true, "seed_throw": true,
			"projectile_speed": 460.0, "blast_radius": 100.0,
			"debuff_on_hit": "sunburn", "debuff_time": 3.0},
	},

	# ---------- 4. 牵日 ----------
	"form_sun_pull": {
		"form_name": "牵日", "desc": "金丝倒卷，把太阳拉回掌心。",
		"player_desc": "有火种：把 420 内的火种拉回/夺火；无火种：金丝抽击目标造成 100% 火伤与灼心。",
		"visual_id": "fx_sun_pull", "hit_shape": SHAPE_LINE, "damage_element": "fire",
		"range": 420.0, "width": 50.0, "angle": 0.0, "speed": 0.0, "count": 1,
		"spread": 0.0, "interval": 0.0, "windup": 0.80, "active": 0.12, "recover": 0.55,
		"dash_speed": 0.0, "dash_time": 0.0, "requires_seed": true, "steal_seed": true,
		"steal_range": 420.0, "pull_seed": true,
		"player": {"cost_kind": COST_MANA, "mana_cost": 18.0, "stamina_cost": 0, "cooldown": 10.0,
			"phys_coeff": 0.0, "spell_coeff": 0.55, "windup": 0.20, "active": 0.10,
			"recover": 0.24, "move_forward": 0.0,
			"steal_seed": true, "steal_range": 420.0, "pull_seed": true,
			"no_seed_coeff": 1.00, "debuff_on_hit": "sunburn", "debuff_time": 3.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.55,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.95, "stagger_coeff": 0.0,
			"cooldown_p1": 11.0, "cooldown_p2": 10.0, "requires_seed": true,
			"steal_seed": true, "steal_range": 420.0, "pull_seed": true,
			"vulnerable_after": 0.5, "vulnerable_bonus": 0.15},
	},

	# ---------- 5. 焚风 ----------
	"form_sun_wind": {
		"form_name": "焚风", "desc": "热浪推着余烬逆飞，连人带火一起掀开。",
		"player_desc": "扇面击退，风持续 0.3 秒；90° 扇面内持种者/火种都会被掀飞，击飞更远，火种撞到 BOSS 会停下。",
		"visual_id": "fx_sun_wind", "hit_shape": SHAPE_FAN, "damage_element": "fire",
		"range": 230.0, "angle": 90.0, "speed": 0.0, "count": 1, "spread": 0.0,
		"interval": 0.0, "windup": 0.60, "active": 0.12, "recover": 0.45,
		"dash_speed": 0.0, "dash_time": 0.0, "knockback": 300.0, "knock_seed": true,
		"seed_knock_angle": 60.0,
		"player": {"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 1, "cooldown": 8.0,
			"phys_coeff": 0.0, "spell_coeff": 0.70, "windup": 0.16, "active": 0.10,
			"recover": 0.22, "move_forward": 0.0, "knockback": 260.0, "knock_seed": true},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.70,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.95, "stagger_coeff": 0.0,
			"cooldown_p1": 9.0, "cooldown_p2": 8.0, "knockback": 300.0, "knock_seed": true},
	},

	# ---------- 6. 日蚀 ----------
	"form_sun_eclipse": {
		"form_name": "日蚀", "desc": "黑日吞光，随后万物焚尽。",
		"player_desc": "持种：掷出/引爆火种，完整 1.45×；无种：在目标处落小日蚀，造成 65% 伤害（75% 半径）。",
		"visual_id": "fx_sun_eclipse", "hit_shape": SHAPE_CIRCLE, "damage_element": "fire",
		"range": 140.0, "cast_range": 460.0, "targeted_circle": true,
		"angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.75, "active": 0.12, "recover": 0.60, "dash_speed": 0.0,
		"dash_time": 0.0, "delay": 0.55, "requires_seed": true, "seed_detonate": true,
		"player": {"cost_kind": COST_MANA, "mana_cost": 22.0, "stamina_cost": 0, "cooldown": 12.0,
			"phys_coeff": 0.0, "spell_coeff": 1.45, "windup": 0.24, "active": 0.10,
			"recover": 0.28, "move_forward": 0.0, "targeted_circle": true,
			"cast_range": 460.0, "delay": 0.35,
			"seed_detonate": true, "throw_forward": 120.0,
			"no_seed_coeff": 0.65, "no_seed_radius_mult": 0.75,
			"debuff_on_hit": "sunburn", "debuff_time": 3.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 1.45,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.90, "stagger_coeff": 0.0,
			"cooldown_p1": 10.0, "cooldown_p2": 9.0, "targeted_circle": true,
			"cast_range": 460.0, "delay": 0.45, "requires_seed": true,
			"seed_detonate": true},
	},

	# ---------- 7. 日轮 ----------
	"form_sun_wheel": {
		"form_name": "日轮", "desc": "日轮碾过，火种自归阵心。",
		"player_desc": "布下持续 4.5 秒的日轮阵；阵心会凝出天火种（没有火种时），并把火种往中心拉。",
		"visual_id": "fx_sun_wheel", "hit_shape": SHAPE_CIRCLE, "damage_element": "fire",
		"range": 130.0, "cast_range": 460.0, "targeted_circle": true,
		"angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.80, "active": 0.12, "recover": 0.50, "dash_speed": 0.0,
		"dash_time": 0.0, "duration": 4.5, "ticks": 3, "tick_interval": 1.5,
		"pull_seed": true, "debuff_on_hit": "sunburn", "debuff_time": 2.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 24.0, "stamina_cost": 0, "cooldown": 14.0,
			"phys_coeff": 0.0, "spell_coeff": 0.55, "windup": 0.22, "active": 0.10,
			"recover": 0.26, "move_forward": 0.0, "targeted_circle": true,
			"cast_range": 460.0, "duration": 4.5, "player_ticks": 3,
			"player_tick_interval": 1.5, "pull_seed": true, "summon_seed_if_none": true,
			"debuff_on_hit": "sunburn", "debuff_time": 2.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.55,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.95, "stagger_coeff": 0.0,
			"cooldown_p1": 13.0, "cooldown_p2": 12.0, "targeted_circle": true,
			"cast_range": 460.0, "duration": 4.5, "ticks": 3, "tick_interval": 1.5,
			"pull_seed": true, "debuff_on_hit": "sunburn", "debuff_time": 2.0},
	},

	# ---------- 8. 天火坠（二阶段）----------
	"form_sun_meteor": {
		"form_name": "天火坠", "desc": "天上那轮火，掉下来了。",
		"player_desc": "天火同时砸向火种与目标，两处都造成完整伤害并留下 3 秒火地；两圈重叠即双倍伤害。",
		"visual_id": "fx_sun_meteor", "hit_shape": SHAPE_CIRCLE, "damage_element": "fire",
		"range": 180.0, "cast_range": 520.0, "targeted_circle": true,
		"angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 1.10, "active": 0.15, "recover": 0.80, "dash_speed": 0.0,
		"dash_time": 0.0, "delay": 0.55, "ground_burn_time": 4.0,
		"ground_burn_tick": 1.0, "ground_burn_coeff": 0.25,
		"debuff_on_hit": "sunburn", "debuff_time": 4.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 30.0, "stamina_cost": 0, "cooldown": 18.0,
			"phys_coeff": 0.0, "spell_coeff": 1.80, "windup": 0.28, "active": 0.10,
			"recover": 0.34, "move_forward": 0.0, "targeted_circle": true,
			"cast_range": 520.0, "delay": 0.45, "ground_burn_time": 3.0,
			"ground_burn_tick": 1.0, "ground_burn_coeff": 0.25,
			"debuff_on_hit": "sunburn", "debuff_time": 4.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 1.80,
			"damage_mult_p2": 1.25, "windup_mult_p2": 1.0, "stagger_coeff": 0.0,
			"cooldown_p1": 18.0, "cooldown_p2": 16.0, "targeted_circle": true,
			"cast_range": 520.0, "delay": 0.55, "ground_burn_time": 4.0,
			"ground_burn_tick": 1.0, "ground_burn_coeff": 0.25,
			"debuff_on_hit": "sunburn", "debuff_time": 4.0},
	},

	# ========================================================================
	# 晏无咎（赤霄界第 3 位，boss_03_c）—— 三灾轮转
	#
	# 风 / 火 / 雷三方相克；双方各有灾位，只有克位才能破灾、攒灾势。
	# 火、雷走法术（火 / 金），风走物理；灾位标签与伤害元素分开。
	# ========================================================================

	# ---------- 1. 风灾·裂云步 ----------
	"form_calamity_step": {
		"form_name": "风灾·裂云步", "desc": "一步踏碎云头，风从脚底起。",
		"player_desc": "向目标突进，命中附加风蚀；在风灾位时移速更快。",
		"visual_id": "fx_calamity_step", "hit_shape": SHAPE_CIRCLE, "damage_element": "wind",
		"calamity_tag": "wind",
		"range": 100.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0,
		"interval": 0.0, "windup": 0.55, "active": 0.12, "recover": 0.45,
		"dash_speed": 850.0, "dash_time": 0.18, "knockback": 200.0,
		"player": {"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 1, "cooldown": 5.0,
			"phys_coeff": 0.45, "spell_coeff": 0.0, "windup": 0.14, "active": 0.10,
			"recover": 0.20, "move_forward": 220.0, "calamity_tag": "wind",
			"debuff_on_hit": "feng_shi", "debuff_time": 4.0},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 0.80,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.90, "stagger_coeff": 0.12,
			"cooldown_p1": 7.0, "cooldown_p2": 6.0, "dash_speed": 850.0, "dash_time": 0.18,
			"calamity_tag": "wind"},
	},

	# ---------- 2. 风灾·断空斩 ----------
	"form_calamity_slash": {
		"form_name": "风灾·断空斩", "desc": "风刃横过，空处先断。",
		"player_desc": "大风刃横扫，命中附加风蚀；在风灾位时移速更快。",
		"visual_id": "fx_calamity_slash", "hit_shape": SHAPE_FAN, "damage_element": "wind",
		"calamity_tag": "wind", "range": 190.0, "angle": 100.0,
		"speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.60, "active": 0.12, "recover": 0.45, "dash_speed": 0.0, "dash_time": 0.0,
		"player": {"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 1, "cooldown": 6.0,
			"phys_coeff": 1.05, "spell_coeff": 0.0, "windup": 0.16, "active": 0.10,
			"recover": 0.22, "move_forward": 0.0, "calamity_tag": "wind",
			"debuff_on_hit": "feng_shi", "debuff_time": 4.0},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 0.95,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.95, "stagger_coeff": 0.12,
			"cooldown_p1": 7.0, "cooldown_p2": 6.5, "calamity_tag": "wind"},
	},

	# ---------- 3. 火灾·焚天印 ----------
	"form_calamity_fire_seal": {
		"form_name": "火灾·焚天印", "desc": "一印落额，火从印里生。",
		"player_desc": "在目标处落下火印，延迟引爆并附加劫火；未带被动时可直接引爆感电。",
		"visual_id": "fx_calamity_fire_seal", "hit_shape": SHAPE_CIRCLE, "damage_element": "fire",
		"calamity_tag": "fire", "range": 100.0, "cast_range": 460.0, "targeted_circle": true,
		"angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.70, "active": 0.12, "recover": 0.50, "dash_speed": 0.0,
		"dash_time": 0.0, "delay": 0.25, "debuff_on_hit": "jie_huo", "debuff_time": 4.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 16.0, "stamina_cost": 0, "cooldown": 7.0,
			"phys_coeff": 0.0, "spell_coeff": 1.15, "windup": 0.20, "active": 0.10,
			"recover": 0.24, "move_forward": 0.0, "targeted_circle": true,
			"cast_range": 460.0, "delay": 0.25, "calamity_tag": "fire",
			"debuff_on_hit": "jie_huo", "debuff_time": 4.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 1.05,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.95, "stagger_coeff": 0.0,
			"cooldown_p1": 8.0, "cooldown_p2": 7.5, "targeted_circle": true,
			"cast_range": 460.0, "delay": 0.25, "calamity_tag": "fire",
			"debuff_on_hit": "jie_huo", "debuff_time": 4.0},
	},

	# ---------- 4. 火灾·燎原 ----------
	"form_calamity_fire_field": {
		"form_name": "火灾·燎原", "desc": "火不挑地方，落在哪里就烧到哪里。",
		"player_desc": "布下持续 4.5 秒的火场，每跳附加劫火；跳伤也能引爆灾痕。",
		"visual_id": "fx_calamity_fire_field", "hit_shape": SHAPE_CIRCLE, "damage_element": "fire",
		"calamity_tag": "fire", "range": 140.0, "cast_range": 460.0, "targeted_circle": true,
		"angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.75, "active": 0.12, "recover": 0.50, "dash_speed": 0.0,
		"dash_time": 0.0, "duration": 4.5, "ticks": 3, "tick_interval": 1.5,
		"debuff_on_hit": "jie_huo", "debuff_time": 3.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 22.0, "stamina_cost": 0, "cooldown": 12.0,
			"phys_coeff": 0.0, "spell_coeff": 0.65, "windup": 0.22, "active": 0.10,
			"recover": 0.26, "move_forward": 0.0, "targeted_circle": true,
			"cast_range": 460.0, "duration": 4.5, "player_ticks": 3,
			"player_tick_interval": 1.5, "calamity_tag": "fire",
			"debuff_on_hit": "jie_huo", "debuff_time": 3.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.65,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.95, "stagger_coeff": 0.0,
			"cooldown_p1": 12.0, "cooldown_p2": 11.0, "targeted_circle": true,
			"cast_range": 460.0, "duration": 4.5, "ticks": 3, "tick_interval": 1.5,
			"calamity_tag": "fire", "debuff_on_hit": "jie_huo", "debuff_time": 3.0},
	},

	# ---------- 5. 雷灾·引雷诀 ----------
	"form_calamity_thunder_strike": {
		"form_name": "雷灾·引雷诀", "desc": "指尖一引，雷从天上认人。",
		"player_desc": "在目标处引落一道雷柱，延迟命中并附加感电；未带被动时可直接引爆风蚀。",
		"visual_id": "fx_calamity_thunder_strike", "hit_shape": SHAPE_CIRCLE,
		"damage_element": "thunder", "calamity_tag": "thunder",
		"range": 120.0, "cast_range": 520.0, "targeted_circle": true,
		"angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.75, "active": 0.12, "recover": 0.50, "dash_speed": 0.0,
		"dash_time": 0.0, "delay": 0.35, "debuff_on_hit": "gan_dian", "debuff_time": 3.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 18.0, "stamina_cost": 0, "cooldown": 8.0,
			"phys_coeff": 0.0, "spell_coeff": 1.25, "windup": 0.22, "active": 0.10,
			"recover": 0.24, "move_forward": 0.0, "targeted_circle": true,
			"cast_range": 520.0, "delay": 0.35, "calamity_tag": "thunder",
			"debuff_on_hit": "gan_dian", "debuff_time": 3.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 1.15,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.95, "stagger_coeff": 0.0,
			"cooldown_p1": 9.0, "cooldown_p2": 8.0, "targeted_circle": true,
			"cast_range": 520.0, "delay": 0.35, "calamity_tag": "thunder",
			"debuff_on_hit": "gan_dian", "debuff_time": 3.0},
	},

	# ---------- 6. 雷灾·雷池 ----------
	"form_calamity_thunder_pool": {
		"form_name": "雷灾·雷池", "desc": "雷落地成池，池里的人连念头都慢半拍。",
		"player_desc": "布下持续 4 秒的雷池，每跳附加感电，跳伤也能引爆灾痕；首跳锁住 BOSS 的灾轮 3 秒。",
		"visual_id": "fx_calamity_thunder_pool", "hit_shape": SHAPE_CIRCLE,
		"damage_element": "thunder", "calamity_tag": "thunder",
		"range": 150.0, "cast_range": 460.0, "targeted_circle": true,
		"angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.80, "active": 0.12, "recover": 0.50, "dash_speed": 0.0,
		"dash_time": 0.0, "duration": 4.0, "ticks": 4, "tick_interval": 1.0,
		"debuff_on_hit": "gan_dian", "debuff_time": 3.0, "lock_calamity": 3.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 24.0, "stamina_cost": 0, "cooldown": 14.0,
			"phys_coeff": 0.0, "spell_coeff": 0.55, "windup": 0.24, "active": 0.10,
			"recover": 0.26, "move_forward": 0.0, "targeted_circle": true,
			"cast_range": 460.0, "duration": 4.0, "player_ticks": 4,
			"player_tick_interval": 1.0, "calamity_tag": "thunder",
			"debuff_on_hit": "gan_dian", "debuff_time": 3.0, "lock_calamity": 3.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.55,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.95, "stagger_coeff": 0.0,
			"cooldown_p1": 13.0, "cooldown_p2": 12.0, "targeted_circle": true,
			"cast_range": 460.0, "duration": 4.0, "ticks": 4, "tick_interval": 1.0,
			"calamity_tag": "thunder", "debuff_on_hit": "gan_dian", "debuff_time": 3.0,
			"lock_calamity": 3.0},
	},

	# ---------- 7. 三灾轮转 ----------
	"form_calamity_turn": {
		"form_name": "三灾轮转", "desc": "轮一转，天就换一副脸。",
		"player_desc": "切换自己的灾位；未装备「三灾·灾身」时改为风环，附加风蚀并引爆灾痕。",
		"visual_id": "fx_calamity_turn", "hit_shape": SHAPE_CIRCLE, "damage_element": "none",
		"calamity_tag": "turn", "range": 120.0, "cast_range": 300.0,
		"angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.70, "active": 0.12, "recover": 0.45, "dash_speed": 0.0, "dash_time": 0.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 12.0, "stamina_cost": 0, "cooldown": 10.0,
			"phys_coeff": 0.0, "spell_coeff": 0.60, "windup": 0.22, "active": 0.10,
			"recover": 0.26, "move_forward": 0.0, "calamity_tag": "turn"},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.60,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.95, "stagger_coeff": 0.0,
			"cooldown_p1": 9.0, "cooldown_p2": 8.0, "calamity_tag": "turn"},
	},

	# ---------- 8. 万劫归一 ----------
	"form_calamity_final": {
		"form_name": "万劫归一", "desc": "三灾不再轮转，一起落下。",
		"player_desc": "消耗全部灾势，在目标处降下万劫；未装备被动时按火属性结算，可引爆感电。",
		"visual_id": "fx_calamity_final", "hit_shape": SHAPE_CIRCLE, "damage_element": "none",
		"calamity_tag": "final", "range": 200.0, "cast_range": 520.0, "targeted_circle": true,
		"angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 1.20, "active": 0.15, "recover": 0.80, "dash_speed": 0.0,
		"dash_time": 0.0, "delay": 0.55, "debuff_on_hit": "zai_beng", "debuff_time": 3.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 30.0, "stamina_cost": 0, "cooldown": 20.0,
			"phys_coeff": 0.0, "spell_coeff": 1.60, "windup": 0.28, "active": 0.10,
			"recover": 0.34, "move_forward": 0.0, "targeted_circle": true,
			"cast_range": 520.0, "delay": 0.45, "calamity_tag": "final",
			"debuff_on_hit": "zai_beng", "debuff_time": 3.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 1.90,
			"damage_mult_p2": 1.25, "windup_mult_p2": 1.0, "stagger_coeff": 0.0,
			"cooldown_p1": 22.0, "cooldown_p2": 20.0, "targeted_circle": true,
			"cast_range": 520.0, "delay": 0.55, "calamity_tag": "final",
			"debuff_on_hit": "zai_beng", "debuff_time": 3.0},
	},

	# =====================================================================
	# 照影界 · 观澜「镜身」八式（2026-11-01）
	# 共享机制：真身脚下有倒影；镜像 1 击碎；镜像会补斩；换镜后真身暴露。
	# 玩家侧同一套形态；镜花/换镜/碎镜/镜返/镜湖/万镜由 player.gd 自定义结算。
	# 2026-11-01 改版：玩家侧的镜像复读**任意物理功法**（不再只有镜水斩 / 照影刺），
	# 且不论是否命中都会在放完后消散；镜返改挡法术并 100% 反弹。
	# =====================================================================
	"form_mirror_slash": {
		"form_name": "镜水斩", "desc": "镜面一斜，身前泛起一道水银弧光；镜像会跟着斩同一刀。",
		"player_desc": "身前扇形水刃；出手时最近的一具镜像会跟着斩同一刀。",
		"visual_id": "fx_mirror_slash", "hit_shape": SHAPE_FAN, "damage_element": "water",
		"range": 150.0, "angle": 110.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.78, "active": 0.14, "recover": 0.55, "dash_speed": 0.0, "dash_time": 0.0,
		"mirror_tag": "slash",
		"player": {"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 1, "cooldown": 3.0,
			"phys_coeff": 1.55, "spell_coeff": 0.0, "windup": 0.16, "active": 0.12,
			"recover": 0.22, "move_forward": 0.0},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 1.0,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.88, "stagger_coeff": 1.0,
			"cooldown_p1": 6.0, "cooldown_p2": 5.0},
	},
	"form_mirror_thrust": {
		"form_name": "照影刺", "desc": "镜中倒影先一步递出刺，真身才跟上；直线穿透。",
		"player_desc": "直线水刺，可被弹反；出手时最近的一具镜像会跟着刺同一枪。",
		"visual_id": "fx_mirror_thrust", "hit_shape": SHAPE_LINE, "damage_element": "water",
		"range": 280.0, "width": 54.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0,
		"interval": 0.0, "windup": 0.65, "active": 0.12, "recover": 0.48, "dash_speed": 0.0,
		"dash_time": 0.0, "mirror_tag": "thrust",
		"player": {"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 1, "cooldown": 5.0,
			"phys_coeff": 1.70, "spell_coeff": 0.0, "windup": 0.18, "active": 0.10,
			"recover": 0.24, "move_forward": 40.0},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 0.9,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.88, "stagger_coeff": 1.0,
			"cooldown_p1": 7.0, "cooldown_p2": 6.0},
	},
	"form_mirror_bloom": {
		"form_name": "镜花", "desc": "镜面开花，水面站起两三个和它一模一样的人。",
		"player_desc": "召出一具自己的镜像；你下一次出手时场上所有镜像会同时复读同一招（50% 伤害），随后消散。",
		"visual_id": "fx_mirror_bloom", "hit_shape": SHAPE_SELF, "damage_element": "water",
		"range": 0.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.50, "active": 0.20, "recover": 0.50, "dash_speed": 0.0, "dash_time": 0.0,
		"mirror_tag": "bloom",
		"player": {"cost_kind": COST_MANA, "mana_cost": 20.0, "stamina_cost": 0, "cooldown": 12.0,
			"phys_coeff": 0.0, "spell_coeff": 0.0, "windup": 0.20, "active": 0.10,
			"recover": 0.24, "move_forward": 0.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.0,
			"damage_mult_p2": 1.0, "windup_mult_p2": 0.9, "stagger_coeff": 0.0,
			"cooldown_p1": 18.0, "cooldown_p2": 14.0},
	},
	"form_mirror_shatter": {
		"form_name": "碎镜", "desc": "捏碎一面镜子，镜片在对手脚边炸开。",
		"player_desc": "碎掉自己的镜像，镜片在镜像位置炸开并减速；没有镜像时不可施放。",
		"visual_id": "fx_mirror_shatter", "hit_shape": SHAPE_CIRCLE, "damage_element": "water",
		"range": 110.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.55, "active": 0.12, "recover": 0.45, "dash_speed": 0.0, "dash_time": 0.0,
		"mirror_tag": "shatter",
		"player": {"cost_kind": COST_MANA, "mana_cost": 15.0, "stamina_cost": 0, "cooldown": 10.0,
			"phys_coeff": 0.0, "spell_coeff": 1.05, "windup": 0.18, "active": 0.10,
			"recover": 0.26, "move_forward": 0.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.9,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.9, "stagger_coeff": 0.0,
			"cooldown_p1": 10.0, "cooldown_p2": 8.0},
	},
	"form_mirror_swap": {
		"form_name": "换镜", "desc": "真身与镜中身换了位置；旧位置只剩一层薄影。",
		"player_desc": "与自己的镜像互换位置，落地短暂无形。",
		"visual_id": "fx_mirror_swap", "hit_shape": SHAPE_SELF, "damage_element": "water",
		"range": 0.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.35, "active": 0.10, "recover": 0.35, "dash_speed": 0.0, "dash_time": 0.0,
		"mirror_tag": "swap",
		"player": {"cost_kind": COST_MANA, "mana_cost": 15.0, "stamina_cost": 0, "cooldown": 16.0,
			"phys_coeff": 0.0, "spell_coeff": 0.0, "windup": 0.12, "active": 0.08,
			"recover": 0.20, "move_forward": 0.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.0,
			"damage_mult_p2": 1.0, "windup_mult_p2": 0.9, "stagger_coeff": 0.0,
			"cooldown_p1": 12.0, "cooldown_p2": 9.0},
	},
	"form_mirror_return": {
		"form_name": "镜返", "desc": "它把镜面横在身前，等着你把刀送进去。",
		"player_desc": "短时间镜面架势：期间第一次打过来的术法会被挡下并按 100% 原样反弹。",
		"visual_id": "fx_mirror_return", "hit_shape": SHAPE_SELF, "damage_element": "water",
		"range": 0.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.20, "active": 0.10, "recover": 0.40, "dash_speed": 0.0, "dash_time": 0.0,
		"mirror_tag": "return",
		"player": {"cost_kind": COST_MANA, "mana_cost": 15.0, "stamina_cost": 0, "cooldown": 18.0,
			"phys_coeff": 0.0, "spell_coeff": 0.0, "windup": 0.10, "active": 0.08,
			"recover": 0.22, "move_forward": 0.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.0,
			"damage_mult_p2": 1.0, "windup_mult_p2": 0.9, "stagger_coeff": 0.0,
			"cooldown_p1": 16.0, "cooldown_p2": 12.0},
	},
	"form_mirror_ring": {
		"form_name": "水镜环", "desc": "一圈镜水从脚下铺开，踩进去的人会觉得时间变慢。",
		"player_desc": "在脚下铺一圈镜水，持续减速并间歇造成水伤。",
		"visual_id": "fx_mirror_ring", "hit_shape": SHAPE_CIRCLE, "damage_element": "water",
		"range": 150.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.60, "active": 0.20, "recover": 0.50, "dash_speed": 0.0, "dash_time": 0.0,
		"mirror_tag": "ring",
		"player": {"cost_kind": COST_MANA, "mana_cost": 20.0, "stamina_cost": 0, "cooldown": 20.0,
			"phys_coeff": 0.0, "spell_coeff": 0.55, "windup": 0.22, "active": 0.10,
			"recover": 0.28, "move_forward": 0.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.5,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.9, "stagger_coeff": 0.0,
			"cooldown_p1": 20.0, "cooldown_p2": 16.0},
	},
	"form_mirror_myriad": {
		"form_name": "万镜归一", "desc": "所有镜面同时抬手，真身藏在其中一道倒影里。",
		"player_desc": "把镜像补到上限（基础 2 具，带被动「照影」3 具）；每具都会在后续出手时复读一次。",
		"visual_id": "fx_mirror_myriad", "hit_shape": SHAPE_FAN, "damage_element": "water",
		"range": 180.0, "angle": 130.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 1.10, "active": 0.15, "recover": 0.70, "dash_speed": 0.0, "dash_time": 0.0,
		"mirror_tag": "myriad",
		"player": {"cost_kind": COST_MANA, "mana_cost": 30.0, "stamina_cost": 0, "cooldown": 30.0,
			"phys_coeff": 0.0, "spell_coeff": 0.0, "windup": 0.26, "active": 0.12,
			"recover": 0.32, "move_forward": 0.0},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 1.2,
			"damage_mult_p2": 1.25, "windup_mult_p2": 0.95, "stagger_coeff": 0.0,
			"cooldown_p1": 30.0, "cooldown_p2": 26.0},
	},

	# =====================================================================
	# 照影界 · 执烛「投影」八式（2026-11-02）
	# 共享机制（唯一几何口径见 ShadowLaw）：场上只有一处光源，任何单位都有一条**影身** ——
	# 从脚下沿「单位 − 光源」方向铺出去的一条地面走廊，长度只由「离光源多远」决定。
	# 执烛的招式全部由影身交付，本体只管走位与一记近身扇形。
	# 没有势条 / 资源条 / 叠层兑现：读的就是地上那条黑刃有多长、朝哪儿。
	# range / width 只是**名义值**（图鉴与回退用）；真实射程与走廊宽在运行时按影长算。
	# =====================================================================
	"form_shadow_cut": {
		"form_name": "削影", "desc": "本体横削一记，地上那条影子同时在影尖反手补一段。",
		"player_desc": "身前扇形削击；影长足够时，影尖会同时补一段短削（两段判定）。",
		"visual_id": "fx_shadow_cut", "hit_shape": SHAPE_FAN, "damage_element": "dark",
		"range": 150.0, "angle": 92.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.74, "active": 0.14, "recover": 0.50, "dash_speed": 0.0, "dash_time": 0.0,
		"shadow_tag": "cut", "shadow_tip_extra": 150.0,
		"player": {"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 1, "cooldown": 3.0,
			"phys_coeff": 1.55, "spell_coeff": 0.0, "windup": 0.15, "active": 0.12,
			"recover": 0.22, "move_forward": 0.0},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 1.05,
			"damage_mult_p2": 1.5, "windup_mult_p2": 0.88, "stagger_coeff": 1.0,
			"cooldown_p1": 5.5, "cooldown_p2": 4.5},
	},
	"form_shadow_reach": {
		"form_name": "投晷", "desc": "把影子钉出去：影子有多长，这一刺就有多远。",
		"player_desc": "沿自己影身的直线长刺，**射程 = 按下那一瞬定格的影长**（站定影短就打不远，跑动拉开灯笼才够长）。",
		"visual_id": "fx_shadow_reach", "hit_shape": SHAPE_LINE, "damage_element": "dark",
		"range": 480.0, "width": 64.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0,
		"interval": 0.0, "windup": 0.86, "active": 0.14, "recover": 0.52, "dash_speed": 0.0,
		"dash_time": 0.0, "shadow_tag": "reach", "debuff_on_hit": "shadow_soak",
		"debuff_time": 2.0,
		"player": {"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 1, "cooldown": 5.0,
			"phys_coeff": 1.75, "spell_coeff": 0.0, "windup": 0.18, "active": 0.12,
			"recover": 0.26, "move_forward": 0.0},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 1.15,
			"damage_mult_p2": 1.5, "windup_mult_p2": 0.86, "stagger_coeff": 1.0,
			"cooldown_p1": 7.5, "cooldown_p2": 6.0},
	},
	"form_shadow_bind": {
		"form_name": "缚影", "desc": "影子探过去按住你的影子；被按住的那一段地就归它了。",
		"player_desc": "在影尖按住敌人：0.7 秒后定身 1.1 秒（仍可出手）并补一斩。",
		"visual_id": "fx_shadow_bind", "hit_shape": SHAPE_CIRCLE, "damage_element": "dark",
		"range": 96.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.80, "active": 0.16, "recover": 0.48, "dash_speed": 0.0, "dash_time": 0.0,
		"shadow_tag": "bind", "bind_delay": 0.9, "bind_time": 1.1,
		"player": {"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 1, "cooldown": 12.0,
			"phys_coeff": 1.30, "spell_coeff": 0.0, "windup": 0.20, "active": 0.12,
			"recover": 0.24, "move_forward": 0.0},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 0.8,
			"damage_mult_p2": 1.5, "windup_mult_p2": 0.88, "stagger_coeff": 0.8,
			"cooldown_p1": 12.0, "cooldown_p2": 10.0},
	},
	"form_shadow_step": {
		"form_name": "踏灯", "desc": "踩着灯影绕到另一侧去 —— 掠过的走廊上，影子先扫一遍。",
		"player_desc": "朝输入方向（无输入则朝目标）突进，掠过的走廊上影刃横扫一次。",
		"visual_id": "fx_shadow_step", "hit_shape": SHAPE_LINE, "damage_element": "dark",
		"range": 300.0, "width": 96.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0,
		"interval": 0.0, "windup": 0.55, "active": 0.12, "recover": 0.40,
		"dash_speed": 880.0, "dash_time": 0.34, "shadow_tag": "step",
		"debuff_on_hit": "shadow_soak", "debuff_time": 1.4,
		"player": {"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 1, "cooldown": 8.0,
			"phys_coeff": 1.45, "spell_coeff": 0.0, "windup": 0.10, "active": 0.10,
			"recover": 0.20, "move_forward": 240.0},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 0.9,
			"damage_mult_p2": 1.5, "windup_mult_p2": 0.85, "stagger_coeff": 0.8,
			"cooldown_p1": 9.0, "cooldown_p2": 7.5},
	},
	"form_shadow_dim": {
		"form_name": "明灭", "desc": "它伸手把界灯捻暗一格：影子塌回脚边，但人也逼近了你。",
		"player_desc": "把灯笼收到贴身 2.5 秒：影长归零，期间自己的**物理功法伤害 +30%**。",
		"visual_id": "fx_shadow_dim", "hit_shape": SHAPE_SELF, "damage_element": "dark",
		"range": 0.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.42, "active": 0.10, "recover": 0.38, "dash_speed": 0.0, "dash_time": 0.0,
		"shadow_tag": "dim",
		"player": {"cost_kind": COST_MANA, "mana_cost": 18.0, "stamina_cost": 0, "cooldown": 18.0,
			"phys_coeff": 0.0, "spell_coeff": 0.0, "windup": 0.12, "active": 0.08,
			"recover": 0.20, "move_forward": 0.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.0,
			"damage_mult_p2": 1.0, "windup_mult_p2": 0.9, "stagger_coeff": 0.0,
			"cooldown_p1": 16.0, "cooldown_p2": 13.0},
	},
	"form_shadow_beam": {
		"form_name": "照骨", "desc": "冷光从眼里直直落下来；这道光与影子无关，只能靠走位让开。",
		"player_desc": "沿自身影身打出一道暗寒光束（暗属性），命中挂「影没」；光束与影身同向时走廊更宽。",
		"visual_id": "fx_shadow_beam", "hit_shape": SHAPE_LINE, "damage_element": "dark",
		"range": 520.0, "width": 62.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0,
		"interval": 0.0, "windup": 0.78, "active": 0.16, "recover": 0.46, "dash_speed": 0.0,
		"dash_time": 0.0, "shadow_tag": "beam", "shadow_widen": 96.0,
		"debuff_on_hit": "shadow_soak", "debuff_time": 2.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 24.0, "stamina_cost": 0, "cooldown": 9.0,
			"phys_coeff": 0.0, "spell_coeff": 1.25, "windup": 0.20, "active": 0.12,
			"recover": 0.24, "move_forward": 0.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.85,
			"damage_mult_p2": 1.5, "windup_mult_p2": 0.88, "stagger_coeff": 0.0,
			"cooldown_p1": 8.0, "cooldown_p2": 6.5},
	},
	"form_shadow_split": {
		"form_name": "分影", "desc": "把影子从脚下撕下来，让它自己去找人；它自己就少了一层壳。",
		"player_desc": "撕下影尖那一截让它在身前代打 4 秒（每 0.9 秒扫一段）；代价是自己影长 ×0.72，期间缚影 / 分影用不了（投晷照打）。",
		"visual_id": "fx_shadow_split", "hit_shape": SHAPE_SELF, "damage_element": "dark",
		"range": 0.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.62, "active": 0.12, "recover": 0.46, "dash_speed": 0.0, "dash_time": 0.0,
		"shadow_tag": "split",
		"player": {"cost_kind": COST_MANA, "mana_cost": 26.0, "stamina_cost": 0, "cooldown": 22.0,
			"phys_coeff": 1.00, "spell_coeff": 0.0, "windup": 0.16, "active": 0.10,
			"recover": 0.24, "move_forward": 0.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.7,
			"damage_mult_p2": 1.5, "windup_mult_p2": 0.9, "stagger_coeff": 0.0,
			"cooldown_p1": 22.0, "cooldown_p2": 18.0},
	},
	"form_shadow_longnight": {
		"form_name": "长夜 · 一灯", "desc": "它把界灯提进自己手里 —— 从这一刻起，你的影子归它用。",
		"player_desc": "把灯笼甩到身前 420 处，10 秒内影长钉在满值不再塌、走廊 ×1.25、削影必定双段：这一段你的影技射程全开。",
		"visual_id": "fx_shadow_longnight", "hit_shape": SHAPE_CIRCLE, "damage_element": "dark",
		"range": 240.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 1.50, "active": 0.18, "recover": 0.72, "dash_speed": 0.0, "dash_time": 0.0,
		"shadow_tag": "longnight",
		"player": {"cost_kind": COST_MANA, "mana_cost": 24.0, "stamina_cost": 0, "cooldown": 20.0,
			"phys_coeff": 1.90, "spell_coeff": 0.0, "windup": 0.26, "active": 0.14,
			"recover": 0.30, "move_forward": 0.0},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 1.3,
			"damage_mult_p2": 1.5, "windup_mult_p2": 0.92, "stagger_coeff": 0.0,
			"cooldown_p1": 34.0, "cooldown_p2": 30.0},
	},

	# =====================================================================
	# 叠纸（照影界第 3 位 · boss_04_c）—— 空间连通 · 折影为径
	# 战场是一张纸，折痕把相距很远的两块纸面贴在一起。
	# 每一式的判定都取两处：本体位置 与 折痕镜像位置；
	# 镜像那一路只在「目标离痕 ≤ fold_reach 且与本体异侧」时参与 ——
	# 所以「离折痕远」永远是安全的答案，破解不需要任何本关功法。
	# 选招由 domain_boss_04_c 按**真实折痕几何**门禁，range/weight 只是名义登记值。
	# =====================================================================
	"form_fold_press": {
		"form_name": "按纸", "desc": "一掌按下去，折痕对侧的那张纸同时被按出一只手印。",
		"player_desc": "身前扇形按击；痕存在且目标在异侧时，对侧镜像同时落一段 60% 掌印。",
		"visual_id": "fx_fold_press", "hit_shape": SHAPE_FAN, "damage_element": "water",
		"range": 178.0, "angle": 104.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.72, "active": 0.14, "recover": 0.50, "dash_speed": 0.0, "dash_time": 0.0,
		"fold_tag": "press", "fold_mirror_ratio": 0.6, "debuff_on_hit": "fold_mark",
		"debuff_time": 4.0,
		"player": {"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 1, "cooldown": 3.0,
			"phys_coeff": 1.55, "spell_coeff": 0.0, "windup": 0.15, "active": 0.12,
			"recover": 0.22, "move_forward": 0.0},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 1.0,
			"damage_mult_p2": 1.45, "windup_mult_p2": 0.88, "stagger_coeff": 1.0,
			"cooldown_p1": 5.5, "cooldown_p2": 4.5},
	},
	"form_fold_trace": {
		"form_name": "循痕", "desc": "它是纸，贴着折痕滑——掠过的痕线上两面一起割。",
		"player_desc": "沿折痕方向（无痕时朝输入）突进 300，掠过的痕线带一段横扫。",
		"visual_id": "fx_fold_trace", "hit_shape": SHAPE_LINE, "damage_element": "wind",
		"range": 380.0, "width": 132.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0,
		"interval": 0.0, "windup": 0.58, "active": 0.12, "recover": 0.42,
		"dash_speed": 1020.0, "dash_time": 0.372, "fold_tag": "trace",
		"debuff_on_hit": "fold_mark", "debuff_time": 2.6,
		## ⚠ move_forward 必须给 0：循痕的位移由 player._fold_cast_trace 自己搬，
		##   因为伤害走廊要贴着「实际走过的那一段」结算。给了 300 就是通用层先冲一段、
		##   这里再冲一段，走廊被推到目标身后，实机看着像这招打不到人。
		"player": {"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 1, "cooldown": 8.0,
			"phys_coeff": 1.45, "spell_coeff": 0.0, "windup": 0.10, "active": 0.10,
			"recover": 0.20, "move_forward": 0.0},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 0.9,
			"damage_mult_p2": 1.45, "windup_mult_p2": 0.85, "stagger_coeff": 0.8,
			"cooldown_p1": 9.0, "cooldown_p2": 7.5},
	},
	"form_fold_stride": {
		"form_name": "跨缝", "desc": "从折痕这头跨进去，从那头出来——你背后那张纸先立起来。",
		"player_desc": "穿最近的一对圆牌从对侧走出并落斩；痕外时退化为直线突进 220。",
		"visual_id": "fx_fold_stride", "hit_shape": SHAPE_CIRCLE, "damage_element": "water",
		"range": 132.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.66, "active": 0.14, "recover": 0.44, "dash_speed": 0.0, "dash_time": 0.0,
		"fold_tag": "stride",
		"player": {"cost_kind": COST_STAMINA, "mana_cost": 0.0, "stamina_cost": 1, "cooldown": 12.0,
			"phys_coeff": 1.35, "spell_coeff": 0.0, "windup": 0.14, "active": 0.12,
			"recover": 0.22, "move_forward": 0.0},
		"boss": {"attack_kind": "physical_melee", "parryable": true, "damage_coeff": 1.1,
			"damage_mult_p2": 1.45, "windup_mult_p2": 0.88, "stagger_coeff": 0.9,
			"cooldown_p1": 11.0, "cooldown_p2": 9.0},
	},
	"form_fold_pressmark": {
		"form_name": "押痕", "desc": "它把整条折痕朝你脚下压过来：你以为离得够远，纸不这么想。",
		"player_desc": "把最近的一条痕朝目标压 210，随即在落点按下一记镜像掌印。",
		"visual_id": "fx_fold_pressmark", "hit_shape": SHAPE_CIRCLE, "damage_element": "water",
		"range": 150.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.80, "active": 0.16, "recover": 0.52, "dash_speed": 0.0, "dash_time": 0.0,
		"fold_tag": "pressmark", "pressmark_length": 520.0, "debuff_on_hit": "fold_mark",
		"debuff_time": 4.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 22.0, "stamina_cost": 0, "cooldown": 16.0,
			"phys_coeff": 0.0, "spell_coeff": 1.10, "windup": 0.20, "active": 0.12,
			"recover": 0.26, "move_forward": 0.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.95,
			"damage_mult_p2": 1.5, "windup_mult_p2": 0.88, "stagger_coeff": 0.0,
			"cooldown_p1": 9.0, "cooldown_p2": 7.5},
	},
	"form_fold_shroud": {
		"form_name": "叠掩", "desc": "折一层纸挡在身前：这一层纸不替你挨打，它把镜像那一面先合上。",
		"player_desc": "折纸护身 3.0 秒：首次受击减 60%，期间镜像判定对你关闭。",
		"visual_id": "fx_fold_shroud", "hit_shape": SHAPE_SELF, "damage_element": "water",
		"range": 0.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0, "interval": 0.0,
		"windup": 0.44, "active": 0.10, "recover": 0.40, "dash_speed": 0.0, "dash_time": 0.0,
		"fold_tag": "shroud", "shroud_time": 3.2, "shroud_guard": 0.6,
		"player": {"cost_kind": COST_MANA, "mana_cost": 18.0, "stamina_cost": 0, "cooldown": 18.0,
			"phys_coeff": 0.0, "spell_coeff": 0.0, "windup": 0.12, "active": 0.08,
			"recover": 0.20, "move_forward": 0.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.0,
			"damage_mult_p2": 1.0, "windup_mult_p2": 0.9, "stagger_coeff": 0.0,
			"cooldown_p1": 16.0, "cooldown_p2": 13.0},
	},
	"form_fold_tear": {
		"form_name": "碎痕", "desc": "它顺着折痕把纸撕开——这一撕不靠镜像，但也把自己 4 秒的贴合撕没了。",
		"player_desc": "沿痕炸一条 560 长直线；消耗你自己的个人痕时这一段全额结算。",
		"visual_id": "fx_fold_tear", "hit_shape": SHAPE_LINE, "damage_element": "thunder",
		"range": 560.0, "width": 220.0, "angle": 0.0, "speed": 0.0, "count": 1, "spread": 0.0,
		"interval": 0.0, "windup": 0.92, "active": 0.18, "recover": 0.62, "dash_speed": 0.0,
		"dash_time": 0.0, "fold_tag": "tear", "tear_disable_time": 4.0,
		"debuff_on_hit": "fold_mark", "debuff_time": 3.0,
		"player": {"cost_kind": COST_MANA, "mana_cost": 26.0, "stamina_cost": 0, "cooldown": 14.0,
			"phys_coeff": 0.0, "spell_coeff": 1.30, "windup": 0.22, "active": 0.14,
			"recover": 0.26, "move_forward": 0.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 1.05,
			"damage_mult_p2": 1.5, "windup_mult_p2": 0.9, "stagger_coeff": 0.0,
			"cooldown_p1": 15.0, "cooldown_p2": 12.0},
	},
	"form_fold_twin": {
		"form_name": "双屏", "desc": "折痕两端的圆牌各立起一具纸影，两道线同时朝你合过来。",
		"player_desc": "从你个人痕的两端各打一线，每线 55% 法强；两线都吃折痕朝向。",
		"visual_id": "fx_fold_twin", "hit_shape": SHAPE_LINE, "damage_element": "water",
		"range": 460.0, "width": 96.0, "angle": 0.0, "speed": 0.0, "count": 2, "spread": 0.0,
		"interval": 0.10, "windup": 0.76, "active": 0.14, "recover": 0.46, "dash_speed": 0.0,
		"dash_time": 0.0, "fold_tag": "twin", "twin_ratio": 0.45,
		"player": {"cost_kind": COST_MANA, "mana_cost": 24.0, "stamina_cost": 0, "cooldown": 9.0,
			"phys_coeff": 0.0, "spell_coeff": 1.05, "windup": 0.20, "active": 0.12,
			"recover": 0.24, "move_forward": 0.0},
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 0.85,
			"damage_mult_p2": 1.5, "windup_mult_p2": 0.88, "stagger_coeff": 0.0,
			"cooldown_p1": 8.0, "cooldown_p2": 6.5},
	},
	"form_fold_triple": {
		"form_name": "三重落纸", "desc": "纸折了两层，三个区就在同一刻落掌——你只能站在其中一个里。",
		"player_desc": "三区同落（各 50% 法强），需个人痕；CD 最长，是这套的收官。",
		"visual_id": "fx_fold_triple", "hit_shape": SHAPE_CIRCLE, "damage_element": "water",
		"range": 168.0, "angle": 0.0, "speed": 0.0, "count": 3, "spread": 0.0, "interval": 0.34,
		"windup": 1.58, "active": 0.18, "recover": 0.74, "dash_speed": 0.0, "dash_time": 0.0,
		"fold_tag": "triple", "triple_ratio": 0.5,
		"player": {"cost_kind": COST_MANA, "mana_cost": 34.0, "stamina_cost": 0, "cooldown": 32.0,
			"phys_coeff": 0.0, "spell_coeff": 1.65, "windup": 0.26, "active": 0.14,
			"recover": 0.30, "move_forward": 0.0},
		# ⚠ 终局招只在二阶段存在，damage_mult_p2 必须写 1.0：
		#   它出招时已经是 P2，再乘 1.5 就等于把系数表里的 1.25 偷偷抬到 1.875。
		"boss": {"attack_kind": "elemental", "parryable": false, "damage_coeff": 1.25,
			"damage_mult_p2": 1.0, "windup_mult_p2": 1.0, "stagger_coeff": 0.0,
			"cooldown_p1": 999.0, "cooldown_p2": 26.0},
	},
	# 符箓四式（落笔 / 贴符 / 引爆 / 符罩）已于 2026-11-10 随功法一起退役，
	# 试炼四符的形态在 TalismanDB.BASES 里，不再走 MoveDB。
}

## 取某个招式形态的原始条目（未登记返回空字典）
## ⚠ 返回的是表内原引用，只读使用；需要合并规则请用 resolve()
static func get_form(form_id: String) -> Dictionary:
	return FORMS.get(form_id, {})


static func has_form(form_id: String) -> bool:
	return FORMS.has(form_id)


static func form_ids() -> Array:
	return FORMS.keys()


static func get_form_name(form_id: String) -> String:
	var f := get_form(form_id)
	return String(f.get("form_name", form_id)) if not f.is_empty() else form_id


## 取某形态在指定施法者下的**完整可用参数**（根字段 + 该侧规则合并）
## caster 传 CASTER_PLAYER / CASTER_BOSS
## 返回副本，调用方可安全修改
static func resolve(form_id: String, caster: String) -> Dictionary:
	var raw := get_form(form_id)
	if raw.is_empty():
		return {}
	var merged: Dictionary = {}
	for k in raw.keys():
		if k == CASTER_PLAYER or k == CASTER_BOSS:
			continue
		merged[k] = raw[k]
	var side: Dictionary = raw.get(caster, {})
	for k in side.keys():
		merged[k] = side[k]
	merged["form_id"] = form_id
	merged["caster"] = caster
	return merged


## 玩家侧参数（等价于 resolve(form_id, CASTER_PLAYER)）
## ⚠ 肉鸽爬塔的增益可以改玩家侧招式数值（伤害 / 范围 / 冷却 / 满层阈值），
##   统一在这里乘 —— 所有读招式的入口（施法、技能面板、文案）都会自动一致。
static func resolve_player(form_id: String) -> Dictionary:
	var out := resolve(form_id, CASTER_PLAYER)
	if not out.is_empty() and RogueRun.active:
		RogueRun.apply_form_mods(form_id, out)
	return out


## BOSS 侧参数（等价于 resolve(form_id, CASTER_BOSS)）
static func resolve_boss(form_id: String) -> Dictionary:
	return resolve(form_id, CASTER_BOSS)


## 玩家侧消耗摘要 —— 供 UI / 判定直接使用
## 返回 { cost_kind, mana_cost, stamina_cost, cooldown,
##        stamina_all, mana_all, exhaust_time }
## ⚠ stamina_all/mana_all 是「抽空整条资源」的大招字段（一剑开天双形态），
##   与 mana_cost/stamina_cost 互斥生效：置 true 时按「全扣」处理
static func player_cost(form_id: String) -> Dictionary:
	var p := resolve_player(form_id)
	return {
		"cost_kind": String(p.get("cost_kind", COST_NONE)),
		"mana_cost": float(p.get("mana_cost", 0.0)),
		"stamina_cost": int(p.get("stamina_cost", 0)),
		"cooldown": float(p.get("cooldown", 0.0)),
		"stamina_all": bool(p.get("stamina_all", false)),
		"mana_all": bool(p.get("mana_all", false)),
		"exhaust_time": float(p.get("exhaust_time", 0.0)),
	}


## BOSS 侧伤害：按「招式系数 × BOSS 攻击力 × 阶段倍率」计算
## boss_attack   BOSS 自身攻击力（各 BOSS 自定，可随境界/位面成长）
## phase         1 或 2
## 若条目给了 flat_damage > 0，则直接用固定值（兼容旧式硬编码伤害）
static func boss_damage(form_id: String, boss_attack: float, phase: int = 1,
		use_random: bool = true) -> float:
	var b := resolve_boss(form_id)
	if b.is_empty():
		return 0.0
	var flat := float(b.get("flat_damage", 0.0))
	var dmg := flat
	if flat <= 0.0:
		dmg = maxf(0.0, boss_attack) * float(b.get("damage_coeff", 1.0))
	if phase >= 2:
		dmg *= float(b.get("damage_mult_p2", 1.0))
	if use_random:
		dmg *= randf_range(ItemDB.RANDOM_MIN, ItemDB.RANDOM_MAX)
	return maxf(0.0, dmg)


## 该形态是否可被玩家弹刀（BOSS 使用时）
static func is_parryable(form_id: String) -> bool:
	var b := resolve_boss(form_id)
	return bool(b.get("parryable", false))


## 该形态的 attack_kind（供玩家 take_damage 判定弹刀/击退）
static func boss_attack_kind(form_id: String) -> String:
	var b := resolve_boss(form_id)
	return String(b.get("attack_kind", "physical_melee"))


## 玩家侧：该招式是否消耗灵力
static func is_mana_skill(form_id: String) -> bool:
	return String(resolve_player(form_id).get("cost_kind", COST_NONE)) == COST_MANA
