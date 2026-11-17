class_name SkillDB
extends RefCounted
## 功法静态数据表（任务书 §5.4）
##
## 硬约束（§2.9 / §5.4）：
##   - 主角开局零功法，所有功法后天获取
##   - 唯一获取途径：真实位面 BOSS 击杀 → 解锁塔投影 → 首杀感悟 → 永久习得
##   - 习得即完整版，无等级、无升级（is_upgradeable 恒为 false）
##   - 主城可自由切换搭配，战斗内不可更换
##
## ======================= 与招式形态的关系 =======================
## 本表只描述「功法条目」，招式长什么样、怎么判定，全部在 MoveDB 里。
## 一个功法通过 **form_id** 指向 MoveDB 的一个招式形态：
##
##   SkillDB.SKILLS[i].form_id ──▶ MoveDB.FORMS[form_id]
##                                   ├── 表现（visual_id / 判定形状 / 时序）双方共享
##                                   ├── player 子字典 → 玩家消耗与系数
##                                   └── boss  子字典 → BOSS 规则与系数
##
## 因此「BOSS 用什么招」和「玩家学到的功用什么招」天然是同一份形态数据，
## 表现完全一致，但消耗 / 冷却 / 伤害各自独立计算。
##
## 功法可选的 cost_override 用来在形态的玩家规则上做二次覆盖，
## 例如同一招「横斩」作为 BOSS 专属技能时更耗灵力、或作为新手功法时更便宜。
##
## ⚠ 本表不含任何具体数值平衡结论，系数为占位初值，待定稿。

const TYPE_ACTIVE := "active"    # 主动功法
const TYPE_PASSIVE := "passive"  # 被动功法

## 三灾（晏无咎玩家侧）：被动「三灾·灾身」装备后才开启玩家灾位 / 灾势 / 灾替。
## 灾身加成与灾崩易伤都从这里取，面板文案与战斗同源。
const CALAMITY_BOON_PCT := 12.0
const CALAMITY_BREAK_TAKEN_MULT := 1.30
## 灾劫连锁（2026-10-31）：风 / 火 / 雷三痕互相引爆，装备或未装备被动都生效。
## kind 决定引爆后的持续表现：
##   fire_tornado = 在引爆点留火龙卷，按 ticks × interval 持续跳火伤并续劫火；
##   burst        = 一次性火爆（主目标 + 周围溅射）；
##   vortex       = 风雷涡，只吸附不伤害，把半径内敌人持续拉向中心。
## 触发方向仍是 风→劫火、火→感电、雷→风蚀；fuel = 被消耗的灾痕，trigger = 触发属性。
const CALAMITY_REACTIONS: Dictionary = {
	"wind_fire": {
		"id": "wind_fire", "name": "风助火势", "trigger": "wind", "fuel": "jie_huo",
		"kind": "fire_tornado",
		"tick_ratio": 0.30, "ticks": 6, "interval": 0.5, "life": 3.0,
		"radius": 120.0, "color": Color(1.0, 0.68, 0.30, 1.0),
	},
	"fire_thunder": {
		"id": "fire_thunder", "name": "雷火交击", "trigger": "fire", "fuel": "gan_dian",
		"kind": "burst",
		"ratio": 1.2, "radius": 110.0, "color": Color(1.0, 0.80, 0.42, 1.0),
	},
	"thunder_wind": {
		"id": "thunder_wind", "name": "风雷引", "trigger": "thunder", "fuel": "feng_shi",
		"kind": "vortex",
		"life": 3.0, "interval": 0.3, "radius": 260.0, "pull": 150.0,
		"color": Color(0.66, 0.86, 1.0, 1.0),
	},
}
## 目标头顶三痕读数的固定顺序（美术 / 规则卡共用）
const CALAMITY_MARK_IDS: Array[String] = ["feng_shi", "jie_huo", "gan_dian"]

## 无功法 / 非伤害型功法时的默认功法系数
const DEFAULT_DAMAGE_MULT := 1.0

## ===== 两仪势（数值的唯一来源）=====
## player.gd 的 YINYANG_* 常量从这里取，功法库 / 图鉴的文案也从这里出 ——
## 改一处，战斗与说明同时跟着变（以前数值锁在 player.gd，面板就只能手抄，一抄就漂）。
## 颜色口径：物理 = 阳，术法 = 阴；打出的颜色与势条当前颜色**相反 = 逆式**。
const YINYANG_MAX_STACKS := 3                 ## 势的层数上限
const YINYANG_REVERSE_BONUS := 0.20           ## 逆式这一发：伤害 +20%
const YINYANG_STACK_BONUS := 0.02             ## 身上每层势：伤害 +2%（顺式也吃）
const YINYANG_MARK_BONUS := 0.25              ## 引爆对方的印：这一发 +25%
const YINYANG_MARK_SECONDS := 5.0             ## 阳印 / 阴印 留存时间
const YINYANG_FLIP_FORCE_SECONDS := 4.0       ## 两仪转「下一招必定逆式」的窗口
const YINYANG_COLLAPSE_COEFF_PER_STACK := 0.5 ## 太极崩每层势追加的物/法系数
const YINYANG_COLLAPSE_STAGGER_SECONDS := 1.0 ## 满层太极崩命中后的硬直
const YINYANG_WARD_BREAK_MULT := 1.3          ## 倒悬被异色打散：这一发多受 30%

## ===== 剑意·剑心通明（数值唯一来源）=====
## 被动「剑心通明」：每层剑意使自身物理功法伤害 +8%；任意物理近战功法释放时也可积攒剑意。
## 上限层数读 form_sword_heaven 的 intent_full_at（玩家运行时对应 player.gd 的 SWORD_INTENT_MAX）。
const SWORD_INTENT_PHYS_PER_STACK := 0.08

## ===== 雷积·震魂（数值唯一来源）=====
## player.gd 的 THUNDER_* 从这里取，被动详情 / 规则卡也从这里现算 ——
## 改一处，战斗与说明同时跟着变。
const THUNDER_MAX_LEI := 3                    ## 雷势上限
const THUNDER_ACCUM_REQUIRED := 9             ## 触发眩晕所需雷击次数
const THUNDER_ACCUM_STUN_SECONDS := 0.5       ## 眩晕时长
const THUNDER_ACCUM_CD_PER_LEI := 1.0         ## 每消耗 1 雷势，全主动 CD -1 秒

## 功法条目
##   skill_id            唯一 id
##   skill_name          展示名
##   skill_type          TYPE_ACTIVE / TYPE_PASSIVE
##   form_id             关联的招式形态（MoveDB.FORMS 的键）；被动功法留空
##   source_boss_id      来源 BOSS（该 BOSS 的招式即本功法）；待定为空
##   tower_projection_id 对应塔投影 id
##   is_unlocked         是否已解锁（运行时以 CharacterData.learned_skills 为准）
##   is_first_kill_reward 是否首杀投影才发放
##   is_complete / is_upgradeable  §2.9 固定为 true / false
##   damage_coeff        功法系数：在招式伤害系数之外再乘一次（默认 1.0）
##   cost_override       可选，覆盖 MoveDB 玩家侧消耗，如 {"mana_cost": 10.0}
##   icon / desc         表现文案：icon 留给美术；desc **只写风味，不许写数值与机制**
##                       （效果说明一律由 get_effect_lines() 从招式数据现算，
##                        手写数值迟早跟改动作废 —— 见该函数注释）
const SKILLS: Array = [
	# ========================================================================
	# 虎妖招式对应的功法（击败塔第 1 层投影后随机感悟）
	# 虎妖 = 凡界第 1 位 BOSS，本体就是演武场那只（prototype_boss.gd）。
	# 它的招式是「横扫 / 掷石 / 群砂 / 踏地 / 妖丹法球」，
	# 这里按 MoveDB 的 5 个通用形态各配一门功法，玩家学会后可原样施展。
	# ========================================================================
	{
		"skill_id": "skill_tiger_claw",
		"skill_name": "虎爪裂空",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_slash_single",
		"source_boss_id": "boss_huyao",
		"tower_projection_id": "proj_boss_huyao",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_tiger_claw.png",
		"desc": "一爪撕开，身前尽是裂痕。",
	},
	{
		"skill_id": "skill_tiger_rock",
		"skill_name": "碎岩飞砂",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_arrow",
		"source_boss_id": "boss_huyao",
		"tower_projection_id": "proj_boss_huyao",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_tiger_rock.png",
		"desc": "掀地一抓，砂石扑面。",
	},
	{
		"skill_id": "skill_tiger_sandstorm",
		"skill_name": "砂石乱舞",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_arrow_volley",
		"source_boss_id": "boss_huyao",
		"tower_projection_id": "proj_boss_huyao",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_tiger_sandstorm.png",
		"desc": "连掀数把砂石，铺天盖地。",
	},
	{
		"skill_id": "skill_tiger_stomp",
		"skill_name": "猛虎踏地",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_smash",
		"source_boss_id": "boss_huyao",
		"tower_projection_id": "proj_boss_huyao",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_tiger_stomp.png",
		"desc": "双掌重踏，地面为之震颤。",
	},
	{
		"skill_id": "skill_tiger_orb",
		"skill_name": "虎煞妖丹",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_element_orb",
		"source_boss_id": "boss_huyao",
		"tower_projection_id": "proj_boss_huyao",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_tiger_orb.png",
		"desc": "吐出凝着虎煞之气的妖丹。",
	},

	# ========================================================================
	# 刀客招式对应的功法（击败塔第 2 层投影后随机感悟）
	# 与 BOSS 共用同一份 MoveDB 形态：表现完全一致，消耗/冷却/伤害各算各的。
	# 学会后可以自己搭「留痕 → 激活 → 封路」的联动玩法。
	# ========================================================================

	{
		"skill_id": "skill_blade_slash",
		"skill_name": "横斩",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_blade_slash",
		"source_boss_id": "boss_01",
		"tower_projection_id": "proj_boss_01",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_blade_slash.png",
		"desc": "刀客的起手式，干净利落的一记横扫。",
	},
	{
		"skill_id": "skill_blade_heavy",
		"skill_name": "沉步竖斩",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_blade_heavy",
		"source_boss_id": "boss_01",
		"tower_projection_id": "proj_boss_01",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_blade_heavy.png",
		"desc": "沉肩落步，自上而下的一刀。斩中挂重伤 3 秒：不能闪避、移速减半。",
	},
	{
		"skill_id": "skill_blade_dash",
		"skill_name": "破步突进斩",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_blade_dash",
		"source_boss_id": "boss_01",
		"tower_projection_id": "proj_boss_01",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_blade_dash.png",
		"desc": "踏碎步法抢进身位，人到刀到。",
	},
	{
		"skill_id": "skill_blade_turn",
		"skill_name": "回身斩",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_blade_turn",
		"source_boss_id": "boss_01",
		"tower_projection_id": "proj_boss_01",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_blade_turn.png",
		"desc": "借着转身的势头反手削出。",
	},
	{
		"skill_id": "skill_blade_scar",
		"skill_name": "留痕斩",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_blade_scar",
		"source_boss_id": "boss_01",
		"tower_projection_id": "proj_boss_01",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_blade_scar.png",
		"desc": "刀锋过处，留下一道未散的痕迹。",
	},
	{
		"skill_id": "skill_blade_qi",
		"skill_name": "刀气追击",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_blade_qi",
		"source_boss_id": "boss_01",
		"tower_projection_id": "proj_boss_01",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_blade_qi.png",
		"desc": "把刀意送出去，追着痕迹走。",
	},
	{
		"skill_id": "skill_blade_field",
		"skill_name": "封路刀域",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_blade_field",
		"source_boss_id": "boss_01",
		"tower_projection_id": "proj_boss_01",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_blade_field.png",
		"desc": "一片刀域压下，先封退路，再收人头。",
	},
	{
		"skill_id": "skill_blade_counter",
		"skill_name": "纳势反击",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_blade_counter",
		"source_boss_id": "boss_01",
		"tower_projection_id": "proj_boss_01",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_blade_counter.png",
		"desc": "以守为攻 —— 挨得越多，还回去的越重。",
	},
	{
		"skill_id": "skill_blade_peak",
		"skill_name": "满势断岳",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_blade_peak",
		"source_boss_id": "boss_01",
		"tower_projection_id": "proj_boss_01",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_blade_peak.png",
		"desc": "目标踏在刀痕上时，倾尽所有的一斩。",
	},

	# ========================================================================
	# 剑客招式对应的功法（凡界第 3 位 BOSS，塔第 3 层投影首杀后随机感悟）
	#
	# 玩家侧**也有剑意系统**（2026-10-19 实装，规则见 form_sword_* 的 player.intent_* 字段
	#   与 player.gd 顶部常量）：
	#   - 可学的 7 门主动 = 刺 / 撩 / 斩 / 云 / 穿 / 万剑归宗 / 一剑开天；外加 1 门被动「剑心通明」
	#   - 释放刺/撩/斩/云 +1 层（仅释放，命中不叠加）；受击 -1 层；上限 5 层
	#   - 万剑归宗 = 2 + 剑意×2 把飞剑，一剑开天满 5 层切换法术矩形巨斩，放完都清空
	#   - skill_sword_heaven_full（满层法术版）是**变体条目**（is_variant）：
	#     不进功法库、不首杀奖励，只供 _cast_skill 满层切换与效果文案取数
	#   - form_sword_triangle 是转阶段演出，两侧都不登记
	# ========================================================================
	{
		"skill_id": "skill_sword_stab",
		"skill_name": "刺",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_sword_stab",
		"source_boss_id": "boss_01_c",
		"tower_projection_id": "proj_boss_01_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_sword_stab.png",
		"desc": "一剑直取，快过视线。",
	},
	{
		"skill_id": "skill_sword_lift",
		"skill_name": "撩",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_sword_lift",
		"source_boss_id": "boss_01_c",
		"tower_projection_id": "proj_boss_01_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_sword_lift.png",
		"desc": "剑锋贴地而起，撩起一片寒光。",
	},
	{
		"skill_id": "skill_sword_chop",
		"skill_name": "斩",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_sword_chop",
		"source_boss_id": "boss_01_c",
		"tower_projection_id": "proj_boss_01_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_sword_chop.png",
		"desc": "举剑过顶，全力下劈。",
	},
	{
		"skill_id": "skill_sword_cloud",
		"skill_name": "云",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_sword_cloud",
		"source_boss_id": "boss_01_c",
		"tower_projection_id": "proj_boss_01_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_sword_cloud.png",
		"desc": "袖手一挥，一剑破空而去。",
	},
	{
		"skill_id": "skill_sword_pierce",
		"skill_name": "穿",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_sword_pierce",
		"source_boss_id": "boss_01_c",
		"tower_projection_id": "proj_boss_01_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_sword_pierce.png",
		"desc": "锁定对手，人与剑一同穿过。",
	},
	{
		"skill_id": "skill_sword_myriad",
		"skill_name": "万剑归宗",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_sword_myriad",
		"source_boss_id": "boss_01_c",
		"tower_projection_id": "proj_boss_01_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_sword_myriad.png",
		"desc": "万剑听令，自鞘中齐出。",
	},
	{
		"skill_id": "skill_sword_heaven",
		"skill_name": "一剑开天",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_sword_heaven",
		"source_boss_id": "boss_01_c",
		"tower_projection_id": "proj_boss_01_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_sword_heaven.png",
		"desc": "剑意尽注于一剑，可开天光。",
	},
	{
		## 满层变体：不是独立功法，玩家剑意满 5 层时由 _cast_skill 自动切换过来。
		## is_variant = true → 功法库过滤、首杀奖励不授予（见 get_library_groups）
		"skill_id": "skill_sword_heaven_full",
		"skill_name": "一剑开天·剑意盈天",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_sword_heaven_full",
		"source_boss_id": "boss_01_c",
		"tower_projection_id": "proj_boss_01_c",
		"is_unlocked": false, "is_first_kill_reward": false,
		"is_complete": true, "is_upgradeable": false,
		"is_variant": true,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_sword_heaven.png",
		"desc": "剑意盈天，一剑既出，日月无光。",
	},
	{
		## 被动「剑心通明」：把剑意从「只有剑客四式能攒」扩展成「所有物理近战功法都能攒」，
		## 同时让每层剑意加成物理功法伤害。生效方式认 passive_effect，不硬比 skill_id。
		"skill_id": "skill_sword_intent",
		"skill_name": "剑心通明",
		"skill_type": TYPE_PASSIVE,
		"form_id": "",
		"source_boss_id": "boss_01_c",
		"tower_projection_id": "proj_boss_01_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_sword_intent.png",
		"sword": true, "passive_effect": "sword_intent_physical",
		"desc": "剑心不昧，意到锋随。",
	},

	# ========================================================================
	# 两仪真人（位面 02 第 1 位 BOSS）—— 玩家侧八门（全可学）
	#
	# 这八门是「两仪势」体系的载体（数值见本表上方 YINYANG_* 常量）：
	#   · 任意物理命中 = 阳，任意术法命中 = 阴（普攻也算）；
	#   · 打出与势条相反的颜色 = 逆式：伤害 +20%、势 +1 层、势翻面；
	#   · 每层势再 +2%；两仪功法命中挂阳印 / 阴印，异色命中引爆（+25%）。
	# 效果说明由 _yinyang_texts() 从常量现算，desc 只留风味（见本表顶部约定）。
	# 塔第 4 层首通从这八门里随机感悟 —— 八门全部登记，没有 BOSS 专属残式。
	# ========================================================================
	{
		"skill_id": "skill_yinyang_palm",
		"skill_name": "阳诀·焚脉掌",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_yinyang_palm",
		"source_boss_id": "boss_02",
		"tower_projection_id": "proj_boss_02",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_yinyang_palm.png",
		"yinyang": true, "polarity": "yang",
		"desc": "阳火焚脉，近身一掌。",
	},
	{
		"skill_id": "skill_yinyang_finger",
		"skill_name": "阴诀·玄冥指",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_yinyang_finger",
		"source_boss_id": "boss_02",
		"tower_projection_id": "proj_boss_02",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_yinyang_finger.png",
		"yinyang": true, "polarity": "yin",
		"desc": "青黑指力贯穿一线，中者阴蚀入骨。",
	},
	{
		"skill_id": "skill_yinyang_flip",
		"skill_name": "两仪转",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_yinyang_flip",
		"source_boss_id": "boss_02",
		"tower_projection_id": "proj_boss_02",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_yinyang_flip.png",
		"yinyang": true, "polarity": "neutral", "utility": true,
		"desc": "拨转仪态，阴阳易位。",
	},
	{
		"skill_id": "skill_yinyang_collapse",
		"skill_name": "太极崩",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_yinyang_collapse",
		"source_boss_id": "boss_02",
		"tower_projection_id": "proj_boss_02",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_yinyang_collapse.png",
		"yinyang": true, "polarity": "mixed", "finisher": true,
		"desc": "阴阳二气归于一点，倾泻而出。",
	},
	{
		"skill_id": "skill_yinyang_triple",
		"skill_name": "阳诀·三叠踏",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_yinyang_triple",
		"source_boss_id": "boss_02",
		"tower_projection_id": "proj_boss_02",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_yinyang_triple.png",
		"yinyang": true, "polarity": "yang",
		"desc": "三步叠浪，一浪高过一浪。",
	},
	{
		"skill_id": "skill_yinyang_wind",
		"skill_name": "阴诀·蚀骨风",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_yinyang_wind",
		"source_boss_id": "boss_02",
		"tower_projection_id": "proj_boss_02",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_yinyang_wind.png",
		"yinyang": true, "polarity": "yin",
		"desc": "阴风自立身之处盘踞，不须瞄准。",
	},
	{
		"skill_id": "skill_yinyang_fish",
		"skill_name": "两仪·双鱼",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_yinyang_fish",
		"source_boss_id": "boss_02",
		"tower_projection_id": "proj_boss_02",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_yinyang_fish.png",
		"yinyang": true,
		# ⚠ 故意不写 polarity：两枚弹一阳一阴，势按「这一发是物理还是术法」判定，
		#   所以一出手就能走完「阳→阴」的逆式，是叠势最快的一门。
		"desc": "一阴一阳，双鱼衔尾而至。",
	},
	{
		"skill_id": "skill_yinyang_counter",
		"skill_name": "两仪·倒悬",
		"skill_type": TYPE_ACTIVE,
		"form_id": "form_yinyang_counter",
		"source_boss_id": "boss_02",
		"tower_projection_id": "proj_boss_02",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_yinyang_counter.png",
		"yinyang": true, "polarity": "yang", "guard": true,
		"desc": "仪态倒悬，同源之力尽数奉还。",
	},

	# ========================================================================
	# 两仪真人的被动功法 —— 全项目第一门被动（功法库的被动槽由此开始有内容）
	#
	# 定位：阴阳这套语言的**参与范围开关**（没戴时只有本 BOSS 掉落的八门算阴阳）。
	#   · 没戴：只有本 BOSS 掉落的八门功法自己算阴阳 —— 逆式增伤 / 叠势 / 挂印 / 引爆照常；
	#     普攻与其他功法一律原样伤害，不叠势也不引爆；
	#   · 戴了：所有伤害来源都算颜色，普攻与任何功法都能吃逆式、叠势、引爆印。
	#   代价是占唯一的被动槽（2026-10-30 起被动只能带 1 门）。
	# 生效方式不写在 player.gd 里比对 skill_id，而是认 `passive_effect` 字段（见
	# get_passive_by_effect），以后再加别的被动门禁只改数据。
	# ========================================================================
	{
		"skill_id": "skill_yinyang_harmony",
		"skill_name": "负阴抱阳",
		"skill_type": TYPE_PASSIVE,
		"form_id": "",
		"source_boss_id": "boss_02",
		"tower_projection_id": "proj_boss_02",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_yinyang_harmony.png",
		"yinyang": true, "passive_effect": "yinyang_stacks",
		"desc": "万物负阴而抱阳，冲气以为和。",
	},

	# ========================================================================
	# 定阵先生（冲和界第 2 位）—— 玩家侧八门：阵旗 · 连线
	# 布旗 / 用线 / 不依赖旗三类分工；机制说明由 _array_texts() 现算
	# ========================================================================
	{
		"skill_id": "skill_array_plant", "skill_name": "插旗·定星", "skill_type": TYPE_ACTIVE,
		"form_id": "form_array_plant", "source_boss_id": "boss_02_b",
		"tower_projection_id": "proj_boss_02_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_array_plant.png",
		"array": true, "desc": "一旗落定，星位自成。",
	},
	{
		"skill_id": "skill_array_line", "skill_name": "引阵·朱弦", "skill_type": TYPE_ACTIVE,
		"form_id": "form_array_line", "source_boss_id": "boss_02_b",
		"tower_projection_id": "proj_boss_02_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_array_line.png",
		"array": true, "desc": "两旗之间崩起一道朱弦。",
	},
	{
		"skill_id": "skill_array_pull", "skill_name": "卷阵·收旗", "skill_type": TYPE_ACTIVE,
		"form_id": "form_array_pull", "source_boss_id": "boss_02_b",
		"tower_projection_id": "proj_boss_02_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_array_pull.png",
		"array": true, "desc": "旗随线起，卷回身侧。",
	},
	{
		"skill_id": "skill_array_seal", "skill_name": "封阵·四象", "skill_type": TYPE_ACTIVE,
		"form_id": "form_array_seal", "source_boss_id": "boss_02_b",
		"tower_projection_id": "proj_boss_02_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_array_seal.png",
		"array": true, "desc": "四面旗成，四象成牢。",
	},
	{
		"skill_id": "skill_array_sweep", "skill_name": "扫阵·横天", "skill_type": TYPE_ACTIVE,
		"form_id": "form_array_sweep", "source_boss_id": "boss_02_b",
		"tower_projection_id": "proj_boss_02_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_array_sweep.png",
		"array": true, "desc": "盘若轮转，旗风横天。",
	},
	{
		"skill_id": "skill_array_step", "skill_name": "踏阵·走罡", "skill_type": TYPE_ACTIVE,
		"form_id": "form_array_step", "source_boss_id": "boss_02_b",
		"tower_projection_id": "proj_boss_02_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_array_step.png",
		"array": true, "desc": "踩罡步斗，一步一旗。",
	},
	{
		"skill_id": "skill_array_pile", "skill_name": "垒旗·镇岳", "skill_type": TYPE_ACTIVE,
		"form_id": "form_array_pile", "source_boss_id": "boss_02_b",
		"tower_projection_id": "proj_boss_02_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_array_pile.png",
		"array": true, "desc": "旗作山岳，一落镇地。",
	},
	{
		"skill_id": "skill_array_burst", "skill_name": "解阵·雷落", "skill_type": TYPE_ACTIVE,
		"form_id": "form_array_burst", "source_boss_id": "boss_02_b",
		"tower_projection_id": "proj_boss_02_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_array_burst.png",
		"array": true, "desc": "万阵皆解，雷自旗落。",
	},

	# ========================================================================
	# 太虚气君（冲和界第 3 位）—— 玩家侧八门：气环 · 化劲（2026-10-30 玩家侧数值改版）
	# ========================================================================
	{
		"skill_id": "skill_qi_gather", "skill_name": "引气·聚环", "skill_type": TYPE_ACTIVE,
		"form_id": "form_qi_gather", "source_boss_id": "boss_02_c",
		"tower_projection_id": "proj_boss_02_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_qi_gather.png",
		"qi": true, "desc": "一息入怀，气环自生。",
	},
	{
		"skill_id": "skill_qi_wave", "skill_name": "冲气·裂空", "skill_type": TYPE_ACTIVE,
		"form_id": "form_qi_wave", "source_boss_id": "boss_02_c",
		"tower_projection_id": "proj_boss_02_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_qi_wave.png",
		"qi": true, "desc": "气冲一线，裂石分云。",
	},
	{
		"skill_id": "skill_qi_spin", "skill_name": "御风·回旋", "skill_type": TYPE_ACTIVE,
		"form_id": "form_qi_spin", "source_boss_id": "boss_02_c",
		"tower_projection_id": "proj_boss_02_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_qi_spin.png",
		"qi": true, "desc": "身随气转，风自成环。",
	},
	{
		"skill_id": "skill_qi_lock", "skill_name": "气锁·缚脉", "skill_type": TYPE_ACTIVE,
		"form_id": "form_qi_lock", "source_boss_id": "boss_02_c",
		"tower_projection_id": "proj_boss_02_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_qi_lock.png",
		"qi": true, "desc": "气结如锁，脉滞难行。",
	},
	{
		"skill_id": "skill_qi_ward", "skill_name": "化劲·卸力", "skill_type": TYPE_ACTIVE,
		"form_id": "form_qi_ward", "source_boss_id": "boss_02_c",
		"tower_projection_id": "proj_boss_02_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_qi_ward.png",
		"qi": true, "desc": "引进落空，借力还施。",
	},
	{
		"skill_id": "skill_qi_step", "skill_name": "踏罡·缩地", "skill_type": TYPE_ACTIVE,
		"form_id": "form_qi_step", "source_boss_id": "boss_02_c",
		"tower_projection_id": "proj_boss_02_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_qi_step.png",
		"qi": true, "desc": "一步罡斗，缩地成寸。",
	},
	{
		"skill_id": "skill_qi_burst", "skill_name": "气爆·周天", "skill_type": TYPE_ACTIVE,
		"form_id": "form_qi_burst", "source_boss_id": "boss_02_c",
		"tower_projection_id": "proj_boss_02_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_qi_burst.png",
		"qi": true, "desc": "周天一转，气海倾泻。",
	},
	{
		"skill_id": "skill_qi_breath", "skill_name": "归元·吐纳", "skill_type": TYPE_ACTIVE,
		"form_id": "form_qi_breath", "source_boss_id": "boss_02_c",
		"tower_projection_id": "proj_boss_02_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_qi_breath.png",
		"qi": true, "desc": "一吐一纳，气归丹田。",
	},
	{
		# 2026-10-30 用户定：气环接触回血拆成被动；不戴这门被动，气环只伤敌不回血。
		"skill_id": "skill_qi_ring_heal", "skill_name": "气环·回息",
		"skill_type": TYPE_PASSIVE,
		"form_id": "", "source_boss_id": "boss_02_c",
		"tower_projection_id": "proj_boss_02_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_qi_ring_heal.png",
		"qi": true, "passive_effect": "qi_ring_leech",
		"desc": "环息相济，伤彼以养己。",
	},

	# ========================================================================
	# 赫连霄（赤霄界第 1 位）—— 玩家侧八式：判词 · 天律
	# 与 BOSS 完全同构：判词按目标最近行为自动选律；敌人违律给你雷势；
	# 九霄消耗雷势。规则卡见 get_thunder_rules()。
	# ========================================================================
	{
		"skill_id": "skill_thunder_verdict", "skill_name": "判词·天律", "skill_type": TYPE_ACTIVE,
		"form_id": "form_thunder_verdict", "source_boss_id": "boss_03",
		"tower_projection_id": "proj_boss_03",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_thunder_verdict.png",
		"thunder": true, "desc": "笔锋落处，天律即成。",
	},
	{
		"skill_id": "skill_thunder_execute", "skill_name": "定刑·雷殛", "skill_type": TYPE_ACTIVE,
		"form_id": "form_thunder_execute", "source_boss_id": "boss_03",
		"tower_projection_id": "proj_boss_03",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_thunder_execute.png",
		"thunder": true, "desc": "笔尖一点，天雷落于所点之处。",
	},
	{
		"skill_id": "skill_thunder_drum", "skill_name": "雷鼓·震天", "skill_type": TYPE_ACTIVE,
		"form_id": "form_thunder_drum", "source_boss_id": "boss_03",
		"tower_projection_id": "proj_boss_03",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_thunder_drum.png",
		"thunder": true, "desc": "鼓面一响，雷从地起。",
	},
	{
		"skill_id": "skill_thunder_lock", "skill_name": "锁雷·缚魂", "skill_type": TYPE_ACTIVE,
		"form_id": "form_thunder_lock", "source_boss_id": "boss_03",
		"tower_projection_id": "proj_boss_03",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_thunder_lock.png",
		"thunder": true, "desc": "雷链贴地游走，锁住脚步与身法。",
	},
	{
		"skill_id": "skill_thunder_step", "skill_name": "雷遁·换位", "skill_type": TYPE_ACTIVE,
		"form_id": "form_thunder_step", "source_boss_id": "boss_03",
		"tower_projection_id": "proj_boss_03",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_thunder_step.png",
		"thunder": true, "desc": "身化雷光，一步即至。",
	},
	{
		"skill_id": "skill_thunder_gather", "skill_name": "聚雷·引霆", "skill_type": TYPE_ACTIVE,
		"form_id": "form_thunder_gather", "source_boss_id": "boss_03",
		"tower_projection_id": "proj_boss_03",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_thunder_gather.png",
		"thunder": true, "desc": "以身为引，九霄之雷尽入此身。",
	},
	{
		"skill_id": "skill_thunder_nine", "skill_name": "九霄·雷罚", "skill_type": TYPE_ACTIVE,
		"form_id": "form_thunder_nine", "source_boss_id": "boss_03",
		"tower_projection_id": "proj_boss_03",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_thunder_nine.png",
		"thunder": true, "desc": "雷势越高，落下的雷柱越多。",
	},
	{
		"skill_id": "skill_thunder_prison", "skill_name": "雷牢·天罚", "skill_type": TYPE_ACTIVE,
		"form_id": "form_thunder_prison", "source_boss_id": "boss_03",
		"tower_projection_id": "proj_boss_03",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_thunder_prison.png",
		"thunder": true, "desc": "雷环收拢，牢中之人尽受天罚。",
	},
	{
		# 2026-10-30 用户定：雷击累计 5 次眩晕 0.5 秒；每消耗 1 雷势全主动 CD -1 秒
		"skill_id": "skill_thunder_accum", "skill_name": "雷积·震魂",
		"skill_type": TYPE_PASSIVE,
		"form_id": "", "source_boss_id": "boss_03",
		"tower_projection_id": "proj_boss_03",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_thunder_accum.png",
		"thunder": true, "passive_effect": "thunder_accum_stun",
		"desc": "雷威积于敌身，九击而震。",
	},

	# ========================================================================
	# 离照（赤霄界第 2 位）—— 玩家侧八式：逐日 · 天火
	# 与 BOSS 同构：天火种可被双方拾取 / 夺取 / 投掷 / 引爆；
	# 日冕叠层，3 层烈阳灼心。规则卡见 get_sun_rules()。
	# ========================================================================
	{
		"skill_id": "skill_sun_step", "skill_name": "逐日步", "skill_type": TYPE_ACTIVE,
		"form_id": "form_sun_step", "source_boss_id": "boss_03_b",
		"tower_projection_id": "proj_boss_03_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_sun_step.png",
		"sun": true, "desc": "身化日影，一步夺火。",
	},
	{
		"skill_id": "skill_sun_slash", "skill_name": "日冕斩", "skill_type": TYPE_ACTIVE,
		"form_id": "form_sun_slash", "source_boss_id": "boss_03_b",
		"tower_projection_id": "proj_boss_03_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_sun_slash.png",
		"sun": true, "desc": "日轮扇扫过，火冕层层叠开。",
	},
	{
		"skill_id": "skill_sun_throw", "skill_name": "投日", "skill_type": TYPE_ACTIVE,
		"form_id": "form_sun_throw", "source_boss_id": "boss_03_b",
		"tower_projection_id": "proj_boss_03_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_sun_throw.png",
		"sun": true, "desc": "把手中的太阳掷出去。",
	},
	{
		"skill_id": "skill_sun_pull", "skill_name": "牵日", "skill_type": TYPE_ACTIVE,
		"form_id": "form_sun_pull", "source_boss_id": "boss_03_b",
		"tower_projection_id": "proj_boss_03_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_sun_pull.png",
		"sun": true, "desc": "金丝倒卷，把太阳拉回掌心。",
	},
	{
		"skill_id": "skill_sun_wind", "skill_name": "焚风", "skill_type": TYPE_ACTIVE,
		"form_id": "form_sun_wind", "source_boss_id": "boss_03_b",
		"tower_projection_id": "proj_boss_03_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_sun_wind.png",
		"sun": true, "desc": "热浪推着余烬逆飞。",
	},
	{
		"skill_id": "skill_sun_eclipse", "skill_name": "日蚀", "skill_type": TYPE_ACTIVE,
		"form_id": "form_sun_eclipse", "source_boss_id": "boss_03_b",
		"tower_projection_id": "proj_boss_03_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_sun_eclipse.png",
		"sun": true, "desc": "黑日吞光，随后万物焚尽。",
	},
	{
		# 2026-10-29 用户定：玩家侧日轮改被动「盗火者」；BOSS 侧日轮保留为主动。
		"skill_id": "skill_sun_wheel", "skill_name": "盗火者", "skill_type": TYPE_PASSIVE,
		"form_id": "", "source_boss_id": "boss_03_b",
		"tower_projection_id": "proj_boss_03_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_sun_wheel.png",
		"sun": true, "passive_effect": "sun_seed_bearer",
		"desc": "天火随身，烬而复燃。",
	},
	{
		"skill_id": "skill_sun_meteor", "skill_name": "天火坠", "skill_type": TYPE_ACTIVE,
		"form_id": "form_sun_meteor", "source_boss_id": "boss_03_b",
		"tower_projection_id": "proj_boss_03_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_sun_meteor.png",
		"sun": true, "desc": "天上那轮火，掉下来了。",
	},

	# ========================================================================
	# 晏无咎（赤霄界第 3 位）—— 玩家侧八式：三灾 · 轮转
	# 风 / 火 / 雷三灾位，克位破灾攒灾势；玩家可转轮、锁灾、放大招。
	# 规则卡见 get_calamity_rules()。
	# ========================================================================
	{
		"skill_id": "skill_calamity_step", "skill_name": "风灾·裂云步", "skill_type": TYPE_ACTIVE,
		"form_id": "form_calamity_step", "source_boss_id": "boss_03_c",
		"tower_projection_id": "proj_boss_03_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_calamity_step.png",
		"calamity": true, "calamity_tag": "wind", "desc": "一步踏碎云头，风从脚底起。",
	},
	{
		"skill_id": "skill_calamity_slash", "skill_name": "风灾·断空斩", "skill_type": TYPE_ACTIVE,
		"form_id": "form_calamity_slash", "source_boss_id": "boss_03_c",
		"tower_projection_id": "proj_boss_03_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_calamity_slash.png",
		"calamity": true, "calamity_tag": "wind", "desc": "风刃横过，空处先断。",
	},
	{
		"skill_id": "skill_calamity_fire_seal", "skill_name": "火灾·焚天印", "skill_type": TYPE_ACTIVE,
		"form_id": "form_calamity_fire_seal", "source_boss_id": "boss_03_c",
		"tower_projection_id": "proj_boss_03_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_calamity_fire_seal.png",
		"calamity": true, "calamity_tag": "fire", "desc": "一印落额，火从印里生。",
	},
	{
		"skill_id": "skill_calamity_fire_field", "skill_name": "火灾·燎原", "skill_type": TYPE_ACTIVE,
		"form_id": "form_calamity_fire_field", "source_boss_id": "boss_03_c",
		"tower_projection_id": "proj_boss_03_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_calamity_fire_field.png",
		"calamity": true, "calamity_tag": "fire", "desc": "火不挑地方，落在哪里就烧到哪里。",
	},
	{
		"skill_id": "skill_calamity_thunder_strike", "skill_name": "雷灾·引雷诀", "skill_type": TYPE_ACTIVE,
		"form_id": "form_calamity_thunder_strike", "source_boss_id": "boss_03_c",
		"tower_projection_id": "proj_boss_03_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_calamity_thunder_strike.png",
		"calamity": true, "calamity_tag": "thunder", "desc": "指尖一引，雷从天上认人。",
	},
	{
		"skill_id": "skill_calamity_thunder_pool", "skill_name": "雷灾·雷池", "skill_type": TYPE_ACTIVE,
		"form_id": "form_calamity_thunder_pool", "source_boss_id": "boss_03_c",
		"tower_projection_id": "proj_boss_03_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_calamity_thunder_pool.png",
		"calamity": true, "calamity_tag": "thunder", "desc": "雷落地成池，池里的人连念头都慢半拍。",
	},
	{
		"skill_id": "skill_calamity_turn", "skill_name": "三灾轮转", "skill_type": TYPE_ACTIVE,
		"form_id": "form_calamity_turn", "source_boss_id": "boss_03_c",
		"tower_projection_id": "proj_boss_03_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_calamity_turn.png",
		"calamity": true, "calamity_tag": "turn", "desc": "轮一转，天就换一副脸。",
	},
	{
		"skill_id": "skill_calamity_final", "skill_name": "万劫归一", "skill_type": TYPE_ACTIVE,
		"form_id": "form_calamity_final", "source_boss_id": "boss_03_c",
		"tower_projection_id": "proj_boss_03_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_calamity_final.png",
		"calamity": true, "calamity_tag": "final", "desc": "三灾不再轮转，一起落下。",
	},
	{
		# 2026-10-31 用户定：装备这门被动才开启玩家侧三灾轮、灾身加成与灾替。
		"skill_id": "skill_calamity_body", "skill_name": "三灾·灾身",
		"skill_type": TYPE_PASSIVE,
		"form_id": "", "source_boss_id": "boss_03_c",
		"tower_projection_id": "proj_boss_03_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_calamity_turn.png",
		"calamity": true, "passive_effect": "calamity_stance",
		"desc": "三灾加身，风火雷随位而变；未装备时八式走灾劫连锁。",
	},
	# ============ 照影界 · 观澜（2026-11-01）============
	# 玩家侧完整继承「镜身」：召镜像、镜像复读任意物理功法、换镜、碎镜、镜返挡法术、镜湖、万镜。
	# 首战不需要本族功法：BOSS 镜像 1 击碎、真身看倒影，空手可破。
	{
		"skill_id": "skill_mirror_slash", "skill_name": "镜水斩", "skill_type": TYPE_ACTIVE,
		"form_id": "form_mirror_slash", "source_boss_id": "boss_04",
		"tower_projection_id": "proj_boss_04",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_mirror_slash.png",
		"mirror": true, "mirror_tag": "slash",
		"desc": "起身前斩出一道水银弧，横扫身前一片。",
	},
	{
		"skill_id": "skill_mirror_thrust", "skill_name": "照影刺", "skill_type": TYPE_ACTIVE,
		"form_id": "form_mirror_thrust", "source_boss_id": "boss_04",
		"tower_projection_id": "proj_boss_04",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_mirror_thrust.png",
		"mirror": true, "mirror_tag": "thrust",
		"desc": "镜中倒影先递刺，真身才跟上；直线上的人会被穿透。",
	},
	{
		"skill_id": "skill_mirror_bloom", "skill_name": "镜花", "skill_type": TYPE_ACTIVE,
		"form_id": "form_mirror_bloom", "source_boss_id": "boss_04",
		"tower_projection_id": "proj_boss_04",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_mirror_bloom.png",
		"mirror": true, "mirror_tag": "bloom",
		"desc": "在脚下凝出一具自己的镜像。镜像会跟着你使出下一门功法，然后消散。",
	},
	{
		"skill_id": "skill_mirror_shatter", "skill_name": "碎镜", "skill_type": TYPE_ACTIVE,
		"form_id": "form_mirror_shatter", "source_boss_id": "boss_04",
		"tower_projection_id": "proj_boss_04",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_mirror_shatter.png",
		"mirror": true, "mirror_tag": "shatter",
		"desc": "捏碎自己的镜像，镜片在镜像处炸开并拖慢敌人。",
	},
	{
		"skill_id": "skill_mirror_swap", "skill_name": "换镜", "skill_type": TYPE_ACTIVE,
		"form_id": "form_mirror_swap", "source_boss_id": "boss_04",
		"tower_projection_id": "proj_boss_04",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_mirror_swap.png",
		"mirror": true, "mirror_tag": "swap",
		"desc": "与自己的镜像互换位置，落地短暂无形。",
	},
	{
		"skill_id": "skill_mirror_return", "skill_name": "镜返", "skill_type": TYPE_ACTIVE,
		"form_id": "form_mirror_return", "source_boss_id": "boss_04",
		"tower_projection_id": "proj_boss_04",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_mirror_return.png",
		"mirror": true, "mirror_tag": "return",
		"desc": "横镜架势：第一次打过来的术法会被镜面挡下，并原样反弹回去。",
	},
	{
		"skill_id": "skill_mirror_ring", "skill_name": "镜湖", "skill_type": TYPE_ACTIVE,
		"form_id": "form_mirror_ring", "source_boss_id": "boss_04",
		"tower_projection_id": "proj_boss_04",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_mirror_ring.png",
		"mirror": true, "mirror_tag": "ring",
		"desc": "在脚下铺一圈镜水，持续减速并间歇造成水伤。",
	},
	{
		"skill_id": "skill_mirror_myriad", "skill_name": "万镜", "skill_type": TYPE_ACTIVE,
		"form_id": "form_mirror_myriad", "source_boss_id": "boss_04",
		"tower_projection_id": "proj_boss_04",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_mirror_myriad.png",
		"mirror": true, "mirror_tag": "myriad",
		"desc": "一次把镜像补到上限；它们会跟着你使出后续的功法。",
	},
	{
		"skill_id": "skill_mirror_echo", "skill_name": "照影", "skill_type": TYPE_PASSIVE,
		"form_id": "", "source_boss_id": "boss_04",
		"tower_projection_id": "proj_boss_04",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_mirror_echo.png",
		"mirror": true, "mirror_tag": "echo", "passive_effect": "mirror_echo",
		"desc": "完美闪避后留下一具镜像；8 秒内最多触发一次。",
	},
	# ============ 照影界 · 执烛（2026-11-02）============
	# 玩家侧完整继承「投影」：灯笼拖在身后 → 影长随跑位变化 → 影系招式打在影身上。
	# 几何口径全部在 ShadowLaw，本表只登记功法条目；文案数字也现算，不手抄。
	# 首战空手可破与本表无关：打执烛不需要任何执烛功法。
	{
		"skill_id": "skill_shadow_cut", "skill_name": "削影", "skill_type": TYPE_ACTIVE,
		"form_id": "form_shadow_cut", "source_boss_id": "boss_04_b",
		"tower_projection_id": "proj_boss_04_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_shadow_cut.png",
		"shadow": true, "shadow_tag": "cut",
		"desc": "身前横削一记；影长够长时，影尖同帧反手补一段。",
	},
	{
		"skill_id": "skill_shadow_reach", "skill_name": "投晷", "skill_type": TYPE_ACTIVE,
		"form_id": "form_shadow_reach", "source_boss_id": "boss_04_b",
		"tower_projection_id": "proj_boss_04_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_shadow_reach.png",
		"shadow": true, "shadow_tag": "reach",
		"desc": "把影子钉出去：这一刺的射程等于你当前的影长。",
	},
	{
		"skill_id": "skill_shadow_bind", "skill_name": "缚影", "skill_type": TYPE_ACTIVE,
		"form_id": "form_shadow_bind", "source_boss_id": "boss_04_b",
		"tower_projection_id": "proj_boss_04_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_shadow_bind.png",
		"shadow": true, "shadow_tag": "bind",
		"desc": "在影尖按住敌人：短暂钉在原地（仍可出手），随后补一斩。",
	},
	{
		"skill_id": "skill_shadow_step", "skill_name": "踏灯", "skill_type": TYPE_ACTIVE,
		"form_id": "form_shadow_step", "source_boss_id": "boss_04_b",
		"tower_projection_id": "proj_boss_04_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_shadow_step.png",
		"shadow": true, "shadow_tag": "step",
		"desc": "朝输入方向突进，灯笼被甩在身后 —— 掠过的走廊上影刃横扫，落点影子更长。",
	},
	{
		"skill_id": "skill_shadow_dim", "skill_name": "明灭", "skill_type": TYPE_ACTIVE,
		"form_id": "form_shadow_dim", "source_boss_id": "boss_04_b",
		"tower_projection_id": "proj_boss_04_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_shadow_dim.png",
		"shadow": true, "shadow_tag": "dim",
		"desc": "把灯笼收到贴身：影长归零，换来这段时间物理功法伤害上涨。",
	},
	{
		"skill_id": "skill_shadow_beam", "skill_name": "照骨", "skill_type": TYPE_ACTIVE,
		"form_id": "form_shadow_beam", "source_boss_id": "boss_04_b",
		"tower_projection_id": "proj_boss_04_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_shadow_beam.png",
		"shadow": true, "shadow_tag": "beam",
		"desc": "沿自身影身打出一道暗寒光束（暗属性），命中拖慢脚步；光束与影子同向时走廊更宽。",
	},
	{
		"skill_id": "skill_shadow_split", "skill_name": "分影", "skill_type": TYPE_ACTIVE,
		"form_id": "form_shadow_split", "source_boss_id": "boss_04_b",
		"tower_projection_id": "proj_boss_04_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_shadow_split.png",
		"shadow": true, "shadow_tag": "split",
		"desc": "撕下影尖那一截代你横扫数秒；你自己这段影子短一成，缚影 / 分影要等它回来。",
	},
	{
		"skill_id": "skill_shadow_longnight", "skill_name": "长夜", "skill_type": TYPE_ACTIVE,
		"form_id": "form_shadow_longnight", "source_boss_id": "boss_04_b",
		"tower_projection_id": "proj_boss_04_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_shadow_longnight.png",
		"shadow": true, "shadow_tag": "longnight",
		"desc": "把灯笼甩到身前远处，一段时间内影长不再塌、钉在满值 —— 影技射程全开的窗口。",
	},
	{
		"skill_id": "skill_shadow_lamp", "skill_name": "执灯", "skill_type": TYPE_PASSIVE,
		"form_id": "", "source_boss_id": "boss_04_b",
		"tower_projection_id": "proj_boss_04_b",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_shadow_lamp.png",
		"shadow": true, "shadow_tag": "lamp", "passive_effect": "shadow_lamp",
		"desc": "灯笼拖得更远，影长整体上涨；完美闪避后短时间影长直接拉满。",
	},
	# ============ 照影界 · 叠纸（2026-11-02）============
	# 玩家侧完整继承「空间连通」：自己裁出一道个人折痕 → 命中同时落两处 → 穿缝换来下一发更重。
	# 几何口径全部在 FoldLaw，本表只登记功法条目；文案数字现算，不手抄。
	# 首战空手可破与本表无关：打叠纸不需要任何叠纸功法。
	{
		"skill_id": "skill_fold_press", "skill_name": "按纸", "skill_type": TYPE_ACTIVE,
		"form_id": "form_fold_press", "source_boss_id": "boss_04_c",
		"tower_projection_id": "proj_boss_04_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_fold_press.png",
		"fold": true, "fold_tag": "press",
		"desc": "身前按下一掌；折痕存在且敌人在痕对侧时，对侧镜像同帧落一段掌印。",
	},
	{
		"skill_id": "skill_fold_trace", "skill_name": "循痕", "skill_type": TYPE_ACTIVE,
		"form_id": "form_fold_trace", "source_boss_id": "boss_04_c",
		"tower_projection_id": "proj_boss_04_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_fold_trace.png",
		"fold": true, "fold_tag": "trace",
		"desc": "有痕就贴着痕滑出去，无痕就朝输入方向突进 —— 掠过的这条线上两面一起割。",
	},
	{
		"skill_id": "skill_fold_stride", "skill_name": "跨缝", "skill_type": TYPE_ACTIVE,
		"form_id": "form_fold_stride", "source_boss_id": "boss_04_c",
		"tower_projection_id": "proj_boss_04_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_fold_stride.png",
		"fold": true, "fold_tag": "stride",
		"desc": "从这头的圆牌跨进去、从那头的圆牌出来并落斩；附近没有对位区时退化为直线突进。",
	},
	{
		"skill_id": "skill_fold_seam", "skill_name": "裁痕", "skill_type": TYPE_ACTIVE,
		"form_id": "form_fold_pressmark", "source_boss_id": "boss_04_c",
		"tower_projection_id": "proj_boss_04_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_fold_seam.png",
		"fold": true, "fold_tag": "seam",
		"desc": "在身前裁出一道只属于你自己的折痕：这段时间你的招式都带镜像落点。",
	},
	{
		"skill_id": "skill_fold_shroud", "skill_name": "叠掩", "skill_type": TYPE_ACTIVE,
		"form_id": "form_fold_shroud", "source_boss_id": "boss_04_c",
		"tower_projection_id": "proj_boss_04_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_fold_shroud.png",
		"fold": true, "fold_tag": "shroud",
		"desc": "折一层纸护身：首次受击大幅减伤，这段时间镜像判定对你关闭（对面的手够不着你）。",
	},
	{
		"skill_id": "skill_fold_tear", "skill_name": "碎痕", "skill_type": TYPE_ACTIVE,
		"form_id": "form_fold_tear", "source_boss_id": "boss_04_c",
		"tower_projection_id": "proj_boss_04_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_fold_tear.png",
		"fold": true, "fold_tag": "tear",
		"desc": "顺着痕撕开一条长直线；消耗你自己的折痕时，这一段按全额结算、不再打折。",
	},
	{
		"skill_id": "skill_fold_twin", "skill_name": "双屏", "skill_type": TYPE_ACTIVE,
		"form_id": "form_fold_twin", "source_boss_id": "boss_04_c",
		"tower_projection_id": "proj_boss_04_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_fold_twin.png",
		"fold": true, "fold_tag": "twin",
		"desc": "折痕两端的圆牌各立起一具纸影，两道线同时朝目标合过来。",
	},
	{
		"skill_id": "skill_fold_triple", "skill_name": "三重落纸", "skill_type": TYPE_ACTIVE,
		"form_id": "form_fold_triple", "source_boss_id": "boss_04_c",
		"tower_projection_id": "proj_boss_04_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_fold_triple.png",
		"fold": true, "fold_tag": "triple",
		"desc": "痕全开时三个互通区在同一刻落掌 —— 你只能站在其中一个里，另外两个照样挨打。",
	},
	{
		"skill_id": "skill_fold_measure", "skill_name": "量折", "skill_type": TYPE_PASSIVE,
		"form_id": "", "source_boss_id": "boss_04_c",
		"tower_projection_id": "proj_boss_04_c",
		"is_unlocked": false, "is_first_kill_reward": true,
		"is_complete": true, "is_upgradeable": false,
		"damage_coeff": 1.0, "cost_override": {},
		"icon": "res://assets/ui/icon/skill_fold_measure.png",
		"fold": true, "fold_tag": "measure", "passive_effect": "fold_measure",
		"desc": "穿过圆牌后下一次攻击加重；站在折痕附近时，你的镜像落点比例上涨。",
	},
	# =====================================================================
	# ⚠ 符箓五式（落笔 / 贴符 / 引爆 / 符罩 / 符心）已于 2026-11-10 整套退役：
	#   试炼之路的符箓流派改成「结符四选四 + 随机连携」（见 TalismanDB / RogueDB.TALISMAN_BUFFS），
	#   这五条不再发放、实现也删了 —— 留在这里只会在功法库里显示成能学却放不出的死功法。
	#   局外的七元灵符（消耗品）是另一套东西，仍然在 ItemDB 的 element_talisman 里，别一起删了。
	# =====================================================================
]


# ===================== 基础查询 =====================

static func get_skill(skill_id: String) -> Dictionary:
	for s in SKILLS:
		if String(s.get("skill_id", "")) == skill_id:
			return s
	return {}


static func get_skill_name(skill_id: String) -> String:
	var s := get_skill(skill_id)
	return String(s.get("skill_name", skill_id)) if not s.is_empty() else skill_id


static func get_by_type(skill_type: String) -> Array:
	var out: Array = []
	for s in SKILLS:
		if String(s.get("skill_type", "")) == skill_type:
			out.append(s)
	return out


static func is_type_active(skill_id: String) -> bool:
	return String(get_skill(skill_id).get("skill_type", "")) == TYPE_ACTIVE


## 按 passive_effect 查被动功法（战斗与文案都从这里取，不在代码里硬比 skill_id）
## 例：get_passive_by_effect("yinyang_stacks") → 「负阴抱阳」；没有则返回空字典
static func get_passive_by_effect(effect_id: String) -> Dictionary:
	if effect_id == "":
		return {}
	for s in get_by_type(TYPE_PASSIVE):
		var sk := s as Dictionary
		if String(sk.get("passive_effect", "")) == effect_id:
			return sk
	return {}


## 这门功法自己能不能**产势**：两仪功法里，只有会算颜色的那几门主动功法能叠势。
## 两仪转（中性）与太极崩（混伤）只吃势、不产势；被动本身不产势（它改变的是别人算不算）。
static func builds_yinyang_stacks(skill_id: String) -> bool:
	var sk := get_skill(skill_id)
	if not bool(sk.get("yinyang", false)):
		return false
	if String(sk.get("skill_type", "")) != TYPE_ACTIVE:
		return false
	var pol := String(sk.get("polarity", ""))
	return pol != "neutral" and pol != "mixed"


# ===================== 功法库分组（UI 用） =====================

## 按**来源 BOSS** 分组，没有来源 BOSS 的统一归入独立的「杂类」分组。
##
## 返回数组，每项结构：
##   group_id    分组 id（有 BOSS 时 = boss_id，杂类固定为 "misc"）
##   group_name  展示名（如「刀客功法」/「杂类功法」）
##   boss_id     来源 BOSS（杂类为空串）
##   total       该组功法总数
##   learned     其中已习得的数量
##   skills      功法条目数组
##
## 顺序：先按万界塔层（WorldDB.get_floors()）里 BOSS 的出场顺序，
##       数据表里出现但塔层未登记的 BOSS 追加在后，**「杂类」永远排最后**。
## ⚠ 没有任何功法的分组会被过滤掉（占位 BOSS 会占塔层但不一定有招式）。
static func get_library_groups() -> Array:
	var boss_order: Array = []
	for f in WorldDB.get_floors():
		var bid := String(f.get("boss_id", ""))
		if bid != "" and bid not in boss_order:
			boss_order.append(bid)
	for s in SKILLS:
		var bid := String(s.get("source_boss_id", ""))
		if bid != "" and bid not in boss_order:
			boss_order.append(bid)

	var buckets: Dictionary = {}
	for bid in boss_order:
		buckets[bid] = []
	var misc: Array = []
	for s in SKILLS:
		# 变体条目（如满层一剑开天）不进功法库：它不是独立功法，
		# 而是某个功法在特定条件下切换的形态（is_variant 标记）
		if bool(s.get("is_variant", false)):
			continue
		var bid := String(s.get("source_boss_id", ""))
		if bid == "":
			misc.append(s)
		else:
			buckets[bid].append(s)

	var out: Array = []
	for bid in boss_order:
		var skills: Array = buckets[bid]
		# 空分组直接跳过：占位 BOSS 会占塔层，但不一定有招式/功法
		if skills.is_empty():
			continue
		out.append(_make_library_group(bid, "%s功法" % WorldDB.get_boss_name(bid), skills))
	if not misc.is_empty():
		out.append(_make_library_group("", "杂类功法", misc))
	return out


static func _make_library_group(boss_id: String, group_name: String, skills: Array) -> Dictionary:
	var learned := 0
	for s in skills:
		if String(s.get("skill_id", "")) in CharacterData.learned_skills:
			learned += 1
	return {
		"group_id": boss_id if boss_id != "" else "misc",
		"group_name": group_name,
		"boss_id": boss_id,
		"total": skills.size(),
		"learned": learned,
		"skills": skills,
	}


## 按招式形态反查功法 —— 「BOSS 用这招，玩家学到的就是这条功法」
static func get_skill_by_form(form_id: String) -> Dictionary:
	for s in SKILLS:
		if String(s.get("form_id", "")) == form_id:
			return s
	return {}


static func get_skill_id_by_form(form_id: String) -> String:
	return String(get_skill_by_form(form_id).get("skill_id", ""))


# ===================== 招式 / 消耗 / 系数 =====================

## 功法对应的招式形态 id（被动功法返回空串）
static func get_form_id(skill_id: String) -> String:
	return String(get_skill(skill_id).get("form_id", ""))


## 玩家使用该功法时的完整招式参数：MoveDB 玩家侧规则 + 功法 cost_override
static func get_skill_form(skill_id: String) -> Dictionary:
	var form_id := get_form_id(skill_id)
	if form_id == "":
		return {}
	var merged := MoveDB.resolve_player(form_id)
	var overrides: Dictionary = get_skill(skill_id).get("cost_override", {})
	for k in overrides.keys():
		merged[k] = overrides[k]
	merged["skill_id"] = skill_id
	return merged


## 玩家使用该功法的消耗：
## { cost_kind, mana_cost, stamina_cost, cooldown, stamina_all, mana_all, exhaust_time }
## ⚠ stamina_all/mana_all/exhaust_time 是大招字段（一剑开天双形态），
##   cost_override 也可覆盖它们（键名一致）
static func get_skill_cost(skill_id: String) -> Dictionary:
	var form_id := get_form_id(skill_id)
	if form_id == "":
		return {"cost_kind": MoveDB.COST_NONE, "mana_cost": 0.0, "stamina_cost": 0, "cooldown": 0.0,
			"stamina_all": false, "mana_all": false, "exhaust_time": 0.0}
	var cost := MoveDB.player_cost(form_id)
	var overrides: Dictionary = get_skill(skill_id).get("cost_override", {})
	for k in ["cost_kind", "mana_cost", "stamina_cost", "cooldown",
			"stamina_all", "mana_all", "exhaust_time"]:
		if overrides.has(k):
			cost[k] = overrides[k]
	return cost


## 功法系数（乘在招式系数之外的功法乘区），默认 1.0
static func get_skill_damage_coeff(skill_id: String) -> float:
	return float(get_skill(skill_id).get("damage_coeff", DEFAULT_DAMAGE_MULT))


## 兼容旧名：早期「功法技能系数」等同功法系数
static func get_skill_damage_mult(skill_id: String) -> float:
	return get_skill_damage_coeff(skill_id)


## 技能的**物理攻击系数** = 招式物理系数 × 功法系数
static func get_phys_coeff(skill_id: String) -> float:
	var f := get_skill_form(skill_id)
	if f.is_empty():
		return 0.0
	return float(f.get("phys_coeff", 0.0)) * get_skill_damage_coeff(skill_id)


## 技能的**法术攻击系数** = 招式法术系数 × 功法系数
static func get_spell_coeff(skill_id: String) -> float:
	var f := get_skill_form(skill_id)
	if f.is_empty():
		return 0.0
	return float(f.get("spell_coeff", 0.0)) * get_skill_damage_coeff(skill_id)


## 技能是否以法术伤害为主（用于面板分类显示）
static func is_spell_skill(skill_id: String) -> bool:
	return get_spell_coeff(skill_id) > get_phys_coeff(skill_id)


## 招式附带的五行属性（空串 = 无属性）
static func get_damage_element(skill_id: String) -> String:
	return String(get_skill_form(skill_id).get("damage_element", ""))


## 兼容旧名：返回物理系数（旧代码只关心一个系数）
static func get_total_damage_coeff(skill_id: String) -> float:
	return get_phys_coeff(skill_id)


# ===================== 效果文案（全部由招式数据实时生成） =====================
##
## ⚠⚠ 功法条目里的 `desc` **只许写风味文案**，效果说明一律走这里现算。
##   历史事故：纳势反击早已从「近身反击」改成「蓄力格挡」，desc 却还写着
##   「近身反击招式，需要贴身才命中」；留痕斩的「留存 10 秒」也是手抄常量。
##   现在改招式表（范围/系数/消耗/机制）→ 面板、格子 tooltip、感悟弹窗**同时变**。
##
## 返回 Array，每项 { "text": String, "accent": bool }
##   accent = true 表示这是机制重点（面板用强调色显示，例如格挡/刀痕联动）

## 效果说明的完整分块：形态 → 消耗 → 系数 → 机制
static func get_effect_lines(skill_id: String) -> Array:
	var out: Array = []
	var skill := get_skill(skill_id)
	var form := get_skill_form(skill_id)
	if form.is_empty():
		# 被动功法没有招式形态，说明全部由 passive_effect 现算（否则会展开成一片空白）
		for t in _passive_texts(skill):
			out.append({"text": String(t), "accent": true})
		for t in _family_texts(skill):
			out.append(t)
		return out

	var shape_text := _shape_text(form)
	if bool(skill.get("array", false)):
		var array_shape := _array_shape_text(String(skill.get("skill_id", "")))
		if array_shape != "":
			shape_text = array_shape
	if shape_text != "":
		out.append({"text": shape_text, "accent": false})

	out.append({"text": _cost_text(skill_id), "accent": false})

	var dmg_text := _damage_text(skill_id, form)
	if dmg_text != "":
		out.append({"text": dmg_text, "accent": false})

	for t in _mechanic_texts(form):
		out.append({"text": String(t), "accent": true})
	for t in _family_texts(skill):
		out.append(t)
	# 两仪势（阳印 / 阴印 / 逆式）：只有带 yinyang 标记的功法才出这批行
	for t in _yinyang_texts(skill, form):
		out.append({"text": String(t), "accent": true})
	# 剑意满层变体说明放在机制区最后（一剑开天才有这条）
	var full_text := _intent_full_text(form)
	if full_text != "":
		out.append({"text": full_text, "accent": true})
	return out


## 各族「这一门自己是什么规则」的机制行（只读 skill，不需要招式形态）
## ⚠ 被动功法没有 form，走不到上面那串现算 —— 之前执灯 / 照影这类被动在功法库里
##   只剩一句 desc，界面讲不清机制（用户 2026-10-31 定的「界面必须讲清机制」）。
##   抽成一份后主动与被动共用同一批行，谁也不会再空着。
static func _family_texts(skill: Dictionary) -> Array:
	var out: Array = []
	# 阵旗三色：每门自己读哪一色、消耗什么，全部现算
	for t in _array_texts_for(skill):
		out.append({"text": String(t), "accent": true})
	# 气环 · 化劲（太虚气君）
	for t in _qi_texts_for(skill):
		out.append({"text": String(t), "accent": true})
	# 判词 · 天律（赫连霄）
	for t in _thunder_texts_for(skill):
		out.append({"text": String(t), "accent": true})
	# 逐日 · 天火（离照玩家侧：无种基础版 / 持种完整版）
	for t in _sun_texts_for(skill):
		out.append({"text": String(t), "accent": true})
	# 镜身 · 照影（观澜玩家侧：召镜 / 换镜 / 碎镜 / 镜返 / 镜湖 / 万镜）
	for t in _mirror_texts_for(skill):
		out.append({"text": String(t), "accent": true})
	# 投影 · 身外之影（执烛玩家侧：灯笼拖尾 / 影长 / 影身判定）
	for t in _shadow_texts_for(skill):
		out.append({"text": String(t), "accent": true})
	# 空间连通 · 折影为径（叠纸玩家侧：折痕 / 镜像落点 / 对位圆牌）
	for t in _fold_texts_for(skill):
		out.append({"text": String(t), "accent": true})
	return out


## 镜像上限的口径（基础 + 被动「照影」加成），三处文案共用一份
static func _mirror_cap_text() -> String:
	return "上限 %d 具，佩戴被动「照影」再 +%d 具（%d 具）" % [
		MirrorImage.MAX_IMAGES, MirrorImage.PASSIVE_EXTRA_IMAGES,
		MirrorImage.MAX_IMAGES + MirrorImage.PASSIVE_EXTRA_IMAGES]


## 照影八式的机制行（玩家侧：镜像 1 击碎，不攒层）
static func _mirror_texts_for(skill: Dictionary) -> Array:
	if not bool(skill.get("mirror", false)):
		return []
	match String(skill.get("skill_id", "")):
		"skill_mirror_bloom":
			return ["召出 1 具镜像（%s）；镜像 1 击即碎，存在 %.0f 秒" % [
				_mirror_cap_text(), MirrorImage.IMAGE_LIFE],
				"你下一次打出伤害的功法出手时，场上所有镜像会同时跟着使出同一招（%d%% 伤害），随后消散" % [
					int(round(MirrorImage.ECHO_RATIO * 100.0))]]
		"skill_mirror_shatter":
			return ["需要 1 具镜像：捏碎后在镜像位置炸开 %.0f 范围，并挂「镜滞」%.0f 秒（%s）" % [
				MirrorImage.SHATTER_RADIUS, MirrorImage.SLOW_TIME,
				DebuffDB.effect_text("mirror_slow")]]
		"skill_mirror_swap":
			return ["需要 1 具镜像：与其互换位置，落地 %.1f 秒无敌" % MirrorImage.SWAP_IFRAMES]
		"skill_mirror_return":
			return ["%.1f 秒横镜架势：第一次打过来的**术法**被镜面挡下，并按 %d%% 原样反弹给来源" % [
				MirrorImage.RETURN_TIME, int(round(MirrorImage.RETURN_RATIO * 100.0))],
				"物理近战 / 投掷不由镜返处理 —— 那些照旧走弹刀与闪避"]
		"skill_mirror_ring":
			return ["脚下铺 %.0f 范围水镜，持续 %.0f 秒；每 0.8 秒结算一次水伤并刷新「镜滞」" % [
				MirrorImage.RING_RADIUS, MirrorImage.RING_DURATION]]
		"skill_mirror_myriad":
			return ["一次把镜像补满（%s）；每具都会在后续出手时复读一次同一招" % [
				_mirror_cap_text()]]
	return []


## 镜身总说明（功法库顶部与图鉴共用）
static func get_mirror_rules() -> Array:
	return [
		"镜像：镜花 / 万镜召出，%s，存在 %.0f 秒；任何物理命中一击即碎。" % [
			_mirror_cap_text(), MirrorImage.IMAGE_LIFE],
		"照影（镜像复读）：你每放一次**打得出伤害的功法**（只有镜花 / 万镜这两门召镜技除外），场上**所有**镜像同时跟着使出同一招 —— 表现、弹体、水场都与本体同一套（万剑归宗会真的飞出飞剑，镜湖会真的铺出水场，一剑开天会真的劈下一把巨剑、出伤同样卡在落地那一刻），各自以镜像的位置起手，伤害为你这招的 %d%%；不论有没有打中，放完的镜像随即消散。换镜 / 镜返这类没有伤害的状态技没有可复制的一击，不参与。" % [
			int(round(MirrorImage.ECHO_RATIO * 100.0))],
		"被动「照影」：镜像上限再 +%d 具，并在完美闪避后于原地免费留一具镜像（每 %.0f 秒最多一次）。" % [
			MirrorImage.PASSIVE_EXTRA_IMAGES, MirrorImage.PASSIVE_CD],
		"换镜：与一具镜像互换位置，落地 %.1f 秒无敌；碎镜：捏碎镜像，%.0f 范围内炸开水伤并挂「镜滞」（%s）%.0f 秒。" % [
			MirrorImage.SWAP_IFRAMES, MirrorImage.SHATTER_RADIUS,
			DebuffDB.effect_text("mirror_slow"), MirrorImage.SLOW_TIME],
		"镜返：%.1f 秒架势，第一次**打过来的术法**被镜面挡下，并按 %d%% 原样反弹回来源；物理近战 / 投掷照旧走弹刀与闪避。" % [
			MirrorImage.RETURN_TIME, int(round(MirrorImage.RETURN_RATIO * 100.0))],
		"镜湖：脚下 %.0f 范围水镜，持续 %.0f 秒，每 0.8 秒结算一次水伤并刷新镜滞。" % [
			MirrorImage.RING_RADIUS, MirrorImage.RING_DURATION],
		"镜身没有势条、不攒层、不引爆：镜像只是一次性的场压与位移锚点。",
	]


# ===== 投影 · 身外之影（执烛玩家侧；数值唯一来源）=====
## 几何（影长 / 走廊宽 / 判定）在 ShadowLaw；这里只放**玩家侧规则层**的数字，
## 面板文案与 player.gd 的战斗结算都从这几行取。
const SHADOW_DIM_SECONDS := 2.5        ## 明灭：灯笼贴身的时长
const SHADOW_DIM_PHYS_BONUS := 0.30    ## 明灭：期间物理功法伤害 +30%
const SHADOW_SPLIT_SECONDS := 4.0      ## 分影：影兽代打时长
const SHADOW_SPLIT_GAP := 0.9          ## 分影：每隔这么久扫一段
const SHADOW_SPLIT_RATIO := 0.62       ## 分影：每段扫击 = 普攻的倍数
const SHADOW_SPLIT_LEN_MULT := 0.72    ## 分影：撕走影尖那一截，自己这段影子打折
const SHADOW_LONGNIGHT_SECONDS := 10.0 ## 长夜：影长钉在满值的时长
const SHADOW_LONGNIGHT_EXTRA_MAX := 200.0 ## 长夜：影长上限追加
const SHADOW_LONGNIGHT_THROW := 420.0  ## 长夜：灯笼被甩出去的距离
const SHADOW_LONGNIGHT_WIDTH_MULT := 1.25 ## 长夜：期间所有影技走廊加宽
const SHADOW_BIND_SECONDS := 1.1       ## 缚影：钉住敌人多久（仍可出手）
const SHADOW_BIND_DELAY := 0.7         ## 缚影：从落印到生效的延迟
const SHADOW_CUT_TIP_EXTRA := 150.0    ## 削影：影长超过这个数才追加影尖第二段
## 影长快照在「前摇+判定+后摇」之后再多留这么久：
## 收招与下一次按下之间只隔一帧时，别让射程在指缝里跳一下。
const SHADOW_SNAP_TAIL := 0.05

## 投影总说明（功法库顶部与图鉴共用）
static func get_shadow_rules() -> Array:
	return [
		"影身：你的灯笼拖在身后（最多 %d 距离），影子从脚下朝**背离灯笼**的方向铺出去，" % [
			int(ShadowLaw.LANTERN_LAG_MAX)] +
			"长度 = 灯笼落后距离 × %.2f（%d~%d）。" % [
			ShadowLaw.LANTERN_SLOPE, int(ShadowLaw.SHADOW_MIN),
			int(ShadowLaw.player_shadow_len(ShadowLaw.LANTERN_LAG_MAX))],
		"跑起来影子就长、停下就塌回脚边：**影系招式的射程等于当前影长**，所以走位本身就是这把武器的弹药；" +
			"踏灯突进会把灯笼甩远，落下时影子最长。",
		"按下影技的那一瞬影长就**定格**，整招打完都用这一份 —— 前摇里停一步不会让射程缩水；" +
			"灯笼跟的是你最近 %.1f 秒跑了多快，所以平A 那零点几秒的定身只削一小截，跑两步就补回来。" % [
			ShadowLaw.LANTERN_INERTIA],
		"削影：身前扇形；影长 ≥ %d 时影尖同帧反手补一段（两段判定）。" % int(SHADOW_CUT_TIP_EXTRA),
		"投晷：沿影身的直线长刺，射程 = 当前影长，命中挂「影没」（%s）。" % DebuffDB.effect_text("shadow_soak"),
		"缚影：在影尖落印，%.1f 秒后把敌人钉在原地 %.1f 秒（仍可出手、无法移动与闪避）并补一斩。" % [
			SHADOW_BIND_DELAY, SHADOW_BIND_SECONDS],
		"明灭：灯笼贴身 %.1f 秒，影长归零 —— 影子没了，但这段时间物理功法伤害 +%d%%。" % [
			SHADOW_DIM_SECONDS, int(SHADOW_DIM_PHYS_BONUS * 100.0)],
		"照骨：沿自身影身的暗寒光束（术法 · 暗属性），光束与影子同向时走廊加宽；命中挂影没。",
		"分影：撕下**影尖那一截**让它在身前代打 %.1f 秒（每 %.1f 秒扫一段，%d%% 普攻）；" % [
			SHADOW_SPLIT_SECONDS, SHADOW_SPLIT_GAP, int(SHADOW_SPLIT_RATIO * 100.0)] +
			"代价是你自己这段影子短一成（×%.2f），缚影 / 分影要等它回来 —— 投晷照打。" % SHADOW_SPLIT_LEN_MULT,
		"长夜：把灯笼甩到身前 %d 处，%.0f 秒内影长不再塌、钉在满值，影技走廊 ×%.2f，" % [
			int(SHADOW_LONGNIGHT_THROW), SHADOW_LONGNIGHT_SECONDS, SHADOW_LONGNIGHT_WIDTH_MULT] +
			"削影必定双段 —— 这一段是影技射程全开的窗口。",
		"这八式全是**暗属性**：命中自动挂「蚀」—— 目标的物抗 / 法抗 / 元素抗数值先打穿 %d%% 再算减免，" % [
			int(AttributeDB.DARK_EROSION_RESIST_SHRED * 100.0)] +
			"期间它受到的治疗只剩 %d%%（减疗 %d%%）。持续 %.0f 秒，同一目标每 %.0f 秒只挂一次；" % [
			int(AttributeDB.DARK_EROSION_HEAL_MULT * 100.0),
			int((1.0 - AttributeDB.DARK_EROSION_HEAL_MULT) * 100.0),
			AttributeDB.DARK_EROSION_TIME, AttributeDB.DARK_EROSION_REFRESH_CD] +
			"目标自己的暗抗会缩短它的持续。蚀是暗属性的通用规则，不靠招式单独配置。",
		"被动「执灯」：影长整体 ×%.2f；完美闪避后 %.1f 秒内影长直接拉满（每 %.1f 秒最多一次）。" % [
			ShadowLaw.PASSIVE_MULT, ShadowLaw.PASSIVE_DODGE_SECONDS, ShadowLaw.PASSIVE_DODGE_CD],
		"投影没有势条、不攒层、不引爆：唯一的读数是地上那条影子有多长、朝哪儿。",
	]


## 投影八式的机制行（玩家侧）
static func _shadow_texts_for(skill: Dictionary) -> Array:
	if not bool(skill.get("shadow", false)):
		return []
	match String(skill.get("skill_id", "")):
		"skill_shadow_cut":
			return ["身前 %.0f° 扇形；影长 ≥ %.0f 时影尖同帧补一段短削（两段判定）" % [
				float(MoveDB.resolve_boss("form_shadow_cut").get("angle", 92.0)), SHADOW_CUT_TIP_EXTRA],
					ShadowLaw.player_shadow_text(1.0)]
		"skill_shadow_reach":
			return ["直线长刺，**射程 = 当前影长**（灯笼被甩得越远越够长）",
					"命中挂「影没」：%s" % DebuffDB.effect_text("shadow_soak")]
		"skill_shadow_bind":
			return ["影尖落印，%.1f 秒后钉住敌人 %.1f 秒（仍可出手）并补一斩" % [
				SHADOW_BIND_DELAY, SHADOW_BIND_SECONDS],
					"敌人一直在移动时这一按会抓空，只留一段墨痕减速"]
		"skill_shadow_step":
			return ["突进 240，掠过的走廊上影刃横扫一次；落点灯笼被甩远、影子最长"]
		"skill_shadow_dim":
			return ["灯笼贴身 %.1f 秒：影长归零，期间物理功法伤害 +%d%%" % [
				SHADOW_DIM_SECONDS, int(SHADOW_DIM_PHYS_BONUS * 100.0)]]
		"skill_shadow_beam":
			return ["沿自身影身打出暗寒光束（术法 · 暗属性，不可弹反）；与影子同向时走廊加宽到 %.0f" % [
				float(MoveDB.resolve_boss("form_shadow_beam").get("shadow_widen", 96.0))],
					"命中挂「影没」：%s" % DebuffDB.effect_text("shadow_soak")]
		"skill_shadow_split":
			return ["撕下影尖那一截，让它在身前代打 %.1f 秒（每 %.1f 秒扫一段，%d%% 普攻）" % [
				SHADOW_SPLIT_SECONDS, SHADOW_SPLIT_GAP, int(SHADOW_SPLIT_RATIO * 100.0)],
					"代价：自己这段影子 ×%.2f，缚影 / 分影等它回来才能再放 —— 投晷不受影响" % SHADOW_SPLIT_LEN_MULT]
		"skill_shadow_longnight":
			return ["把灯笼甩到身前 %.0f 处，%.0f 秒内影长钉在满值不再塌（上限 +%d）" % [
				SHADOW_LONGNIGHT_THROW, SHADOW_LONGNIGHT_SECONDS, int(SHADOW_LONGNIGHT_EXTRA_MAX)],
					"期间影技走廊 ×%.2f，削影必定双段 —— 这组的射程窗口" % SHADOW_LONGNIGHT_WIDTH_MULT]
		"skill_shadow_lamp":
			return ["影长整体 ×%.2f（%s）" % [ShadowLaw.PASSIVE_MULT,
					ShadowLaw.player_shadow_text(ShadowLaw.PASSIVE_MULT)],
					"完美闪避后 %.1f 秒内影长直接拉满（每 %.1f 秒最多一次）" % [
						ShadowLaw.PASSIVE_DODGE_SECONDS, ShadowLaw.PASSIVE_DODGE_CD]]
	return []


# ===== 空间连通 · 折影为径（叠纸玩家侧；数值唯一来源）=====
## 几何（贴合带 / 镜像点 / 圆牌）在 FoldLaw；这里只放**玩家侧规则层**的数字，
## 面板文案与 player.gd 的战斗结算都从这几行取。
const FOLD_SHROUD_SECONDS := 3.0     ## 叠掩：护身纸时长
const FOLD_SHROUD_GUARD := 0.60      ## 叠掩：首次受击减伤
const FOLD_STRIDE_FALLBACK := 220.0  ## 跨缝：附近没有对位区时退化的直线突进距离
const FOLD_TRACE_DASH := 300.0       ## 循痕：突进距离
const FOLD_TEAR_LINE := 560.0        ## 碎痕：沿痕撕开的直线长度
const FOLD_TRIPLE_RATIO := 0.50      ## 三重落纸：每区 = 法强的倍数
const FOLD_TWIN_RATIO := 0.55        ## 双屏：每线 = 法强的倍数

## ===== 符箓（符匣五式）已于 2026-11-10 整套退役 =====
## 落笔 / 贴符 / 引爆 / 符罩 / 符心 的常量、以及旧「符箓传承」的
## `TALISMAN_LEGACY_COEFF / TALISMAN_LEGACY_QUALITY_MULT / TALISMAN_LEGACY_CD` 一起删了。
## 现在符箓数值只有两处：局外七元灵符在 ItemDB.element_talisman，
## 试炼四符体系在 TalismanDB（品质倍率只在那儿，别再往技能表搬第二份）。

## 折影总说明（功法库顶部与图鉴共用）
static func get_fold_rules() -> Array:
	return [
		"折痕：地面上一条线段，把相距很远的两块纸面**贴在一起**。你的每一击都同时判定两处 —— " +
			"出手点 与 它关于折痕的镜像点。",
		"镜像那一半有条件：目标必须**与出手者分处痕的两侧**，且到痕的垂直距离 ≤ %s，" % FoldLaw.reach_text() +
			"否则那块纸根本没折过来，镜像打空。",
		"⇒ 所以离折痕比贴合带更远时，镜像那一面永远碰不到你；这是空手也能用的解法，不需要任何本关功法。",
		"圆牌：折痕**两端**各一枚，同号成对。踩进这头就从那头走出来（方向不变、距离缩短）—— " +
			"这一步就叫穿缝，" + FoldLaw.seam_text() + "。",
		"押痕（BOSS 那一半）：它把折痕立在你们正中间、垂直于连线，折过来之后你的位置正好在它掌下；" +
			"你的「裁痕」是同一件事的主动版 —— 自己立一条痕，不靠它。",
		"二折（BOSS 二阶段）：它落第二条平行痕，战场被切成三个互通区，终局招三区同落；" +
			"同时贴合带从 %.0f 收窄到 %.0f —— 纸叠两层，能贴住的范围反而更小。" % [
				FoldLaw.REACH_P1, FoldLaw.REACH_P2],
		"按纸：身前扇形；痕存在且敌人在异侧时，对侧镜像同帧落一段掌印（%s）。" % FoldLaw.mirror_text(),
		"循痕：有痕就贴着痕滑出去（突进 %d），掠过的这条线上两面一起割；无痕时朝输入方向突进。" % int(FOLD_TRACE_DASH),
		"跨缝：穿最近的一对圆牌从对侧走出并落斩；附近没有对位区时退化为直线突进 %d。" % int(FOLD_STRIDE_FALLBACK),
		"裁痕：在身前裁出一道**只属于你自己的折痕**（长 %d、%.1f 秒）—— " % [
			int(FoldLaw.PLAYER_SEAM_LEN), FoldLaw.PLAYER_SEAM_TIME] +
			"这段时间你的招式自带镜像落点，出这个副本照样能用。",
		"叠掩：折纸护身 %.1f 秒，首次受击减 %d%%，期间镜像判定对你关闭。" % [
			FOLD_SHROUD_SECONDS, int(FOLD_SHROUD_GUARD * 100.0)],
		"碎痕：顺着痕撕开一条 %d 长的直线（术法）；消耗你自己的折痕时这一段按全额结算、不再打折。" % int(FOLD_TEAR_LINE),
		"双屏：从你折痕两端各立一具纸影，两道线同时合向目标（每线 %d%% 法强）。" % int(FOLD_TWIN_RATIO * 100.0),
		"三重落纸：三个互通区在同一刻落掌（每区 %d%% 法强）——需要个人折痕，是这套的收官。" % int(FOLD_TRIPLE_RATIO * 100.0),
		"被动「量折」：穿过圆牌后 %.1f 秒内下一次攻击 +%d%%；站在折痕 %d 内时镜像落点 %d%%→%d%%。" % [
			FoldLaw.CROSS_BONUS_TIME, int(FoldLaw.CROSS_BONUS * 100.0), int(FoldLaw.NEAR_SEAM),
			int(FoldLaw.MIRROR_RATIO * 100.0), int(FoldLaw.MIRROR_RATIO_NEAR * 100.0)],
		"折影没有势条、不攒层、不引爆：唯一的读数是地上那条痕在哪、你离痕多远、圆牌在哪。",
	]


## 折影八式的机制行（玩家侧）
static func _fold_texts_for(skill: Dictionary) -> Array:
	if not bool(skill.get("fold", false)):
		return []
	match String(skill.get("skill_id", "")):
		"skill_fold_press":
			return ["身前 %.0f° 扇形按击；痕存在且敌人在异侧时，对侧镜像同帧落一段掌印" % [
				float(MoveDB.resolve_boss("form_fold_press").get("angle", 104.0))],
					FoldLaw.mirror_text()]
		"skill_fold_trace":
			return ["沿折痕方向突进 %d（无痕时朝输入方向），掠过的痕线上两面一起割" % int(FOLD_TRACE_DASH)]
		"skill_fold_stride":
			return ["从这头的圆牌跨进去、从那头的圆牌出来并落斩",
					"附近没有对位区时退化为直线突进 %d —— 不会空放" % int(FOLD_STRIDE_FALLBACK)]
		"skill_fold_seam":
			return ["裁出一道个人折痕：长 %d、存续 %.1f 秒，只对你自己和你的投射物生效" % [
				int(FoldLaw.PLAYER_SEAM_LEN), FoldLaw.PLAYER_SEAM_TIME],
					"这道痕是你带出照影界的工具：有它，按纸 / 双屏 / 三重落纸的镜像落点才成立"]
		"skill_fold_shroud":
			return ["折纸护身 %.1f 秒：首次受击减 %d%%，期间镜像判定对你关闭（对面的手够不着你）" % [
				FOLD_SHROUD_SECONDS, int(FOLD_SHROUD_GUARD * 100.0)]]
		"skill_fold_tear":
			return ["沿痕撕开一条 %d 长的直线（术法，不可弹反）" % int(FOLD_TEAR_LINE),
					"消耗你自己的折痕来换这一段全额结算 —— 撕完你的镜像落点也没有了"]
		"skill_fold_twin":
			return ["从你折痕两端的圆牌各打一条线（每线 %d%% 法强），两线都吃折痕朝向" % [
				int(FOLD_TWIN_RATIO * 100.0)]]
		"skill_fold_triple":
			return ["三个互通区同时落掌（每区 %d%% 法强），需个人折痕" % int(FOLD_TRIPLE_RATIO * 100.0)]
		"skill_fold_measure":
			return ["穿过圆牌后 %.1f 秒内下一次攻击 +%d%%（一次性旗标，不是条）" % [
				FoldLaw.CROSS_BONUS_TIME, int(FoldLaw.CROSS_BONUS * 100.0)],
					"站在折痕 %d 内时，你的镜像落点 %d%%→%d%%" % [
						int(FoldLaw.NEAR_SEAM), int(FoldLaw.MIRROR_RATIO * 100.0),
						int(FoldLaw.MIRROR_RATIO_NEAR * 100.0)]]
	return []


## 符箓五式的机制行已随功法一起退役（2026-11-10）：
## 试炼四符体系不是「功法」，它走 TalismanDB.effect_lines()，别把它接回这里。


## 气君八式的机制行（玩家侧：气环最多 5 枚）
static func _qi_texts_for(skill: Dictionary) -> Array:
	if not bool(skill.get("qi", false)):
		return []
	match String(skill.get("skill_id", "")):
		"skill_qi_gather":
			return ["引气：凝 1 枚气环（上限 5）；踏罡·缩地也会凝 1 枚；不造成直接伤害",
				"环身气：气环绕体，环碰到敌人即结算一次（0.30× 法攻）并挂滞气 0.8 秒；同一次接触只结算一次，离开再碰才再算",
				"回血：只有佩戴被动「气环·回息」时，才把接触伤害的 10% 回复自身气血；不戴只伤敌"]
		"skill_qi_wave":
			return ["冲气：直线气浪；身上有气环时自动花 1 枚，伤害 +0.5 倍、射程 +90"]
		"skill_qi_spin":
			return ["回旋：自身一圈，把近身敌人与 BOSS 推开；不花气环"]
		"skill_qi_lock":
			return ["缚脉：扇面命中挂「滞气」4 秒 —— 灵力停止回复、移速 -20%",
				"消耗 1 枚气环：命中的 BOSS 移速压到 50%，并且 2 秒无法使用技能"]
		"skill_qi_ward":
			return ["化劲：消耗 1 枚气环；2.2 秒内受伤 -40%，蓄下其中 60%（上限 140）",
				"结束时放一道气浪：1.20 倍基础 + 蓄下的量；气浪是物理近战，能被弹反"]
		"skill_qi_step":
			return ["踏罡：突进 220，落点结算一次；凝成 1 枚气环"]
		"skill_qi_burst":
			return ["气爆：花掉全部气环；每枚 +0.60 倍，零环时只有基础 1.00 倍"]
		"skill_qi_breath":
			return ["吐纳：消耗 1 枚气环，引导 1.2 秒后回复 10% 最大气血；冷却 10 秒；期间受伤超过 8% 最大气血会被打断"]
	return []


## 离照八式的机制行（玩家侧：没有火种也能放基础版；持种时完整版并吃日冕）
static func _sun_texts_for(skill: Dictionary) -> Array:
	if not bool(skill.get("sun", false)):
		return []
	match String(skill.get("skill_id", "")):
		"skill_sun_step":
			var step := MoveDB.resolve_player("form_sun_step")
			return ["无方向输入时朝火种突进；无火种或火种在身上则朝 BOSS；有方向输入按输入方向",
				"突进 220 并结算伤害；只有这一发打中持种者才夺得到火（%d 内）"
				% int(step.get("steal_range", 130.0))]
		"skill_sun_slash":
			return ["无火种：完整扇形火斩；持种时伤害 +20%，每层日冕再 +15%",
				"持种时命中附带灼心；日冕的「所有伤害 +12%/层」也会同时作用在这一发"]
		"skill_sun_throw":
			return ["无火种：向目标掷余烬火球，造成 65% 伤害；持种：把火种沿弧线掷向目标，完整 1.60×，火种落在目标身前（撞到 BOSS 会停）"]
		"skill_sun_pull":
			return ["无火种：金丝抽击目标，造成 100% 火伤并附带灼心；有火种：把 420 内的火种拉回；持种者为 BOSS 时，金丝走廊宽 50，未扫中则不夺火"]
		"skill_sun_wind":
			return ["无火种：完整扇形火风 + 击退（90° 都吃伤害）；掀种认整个 90° 扇面，起手后 0.3 秒内进入也算；击飞距离 480（持种）/ 440（地上），火种撞到 BOSS 会停下"]
		"skill_sun_eclipse":
			return ["无火种：在目标处落一次小日蚀（65% 伤害、75% 半径）；持种：向面向方向掷出 120 后消耗火种，完整 1.45× 并扩大范围"]
		"skill_sun_meteor":
			return ["无火种：完整天火坠；有火种：火种与目标各落一发，两圈重叠处吃双倍伤害与双层火地，并吃日冕全伤害加成"]
	return []


## 赫连霄八式的机制行（玩家侧：判词按目标行为自动选律，敌人违律给雷势）
static func _thunder_texts_for(skill: Dictionary) -> Array:
	if not bool(skill.get("thunder", false)):
		return []
	match String(skill.get("skill_id", "")):
		"skill_thunder_verdict":
			return [
				"判词：按目标最近 1.5 秒的行为落**两条不同的律** —— 移动 → 禁行 / 出手 → 禁攻 / 闪避 → 禁避 / 站定 → 禁立",
				"四条律（5 秒）：禁行每移动 110 引雷 0.8×；禁攻每次打中引雷 0.9×；禁避每次闪避引雷 0.8×；禁立原地 0.9 秒起每 0.9 秒引雷 0.7×",
				"目标每违律一次，你 +1 雷势（上限 3）；它若一次未犯走完判词，你获得顺天 6 秒（攻速 +20%、移速 +10%）",
				"BOSS 的宣判是物理笔锋，可以被弹反 —— 弹反即撤销判词并让它僵直",
			]
		"skill_thunder_execute":
			return ["定刑：指定落点延迟 0.45 秒落雷；目标身上带判词时伤害 +50%"]
		"skill_thunder_drum":
			return ["雷鼓：自身一圈，击退 260；不花雷势"]
		"skill_thunder_lock":
			return ["锁雷：直线雷链，命中挂「滞雷」3 秒 —— 移速 -25%、闪避距离 -30%"]
		"skill_thunder_step":
			return ["雷遁：向前突进 240，落点圆 110 结算一次；不花雷势"]
		"skill_thunder_gather":
			return ["聚雷：引导 1.2 秒，期间身周落 3 道雷；完成时 +1 雷势",
				"引导期间受伤超过 8% 最大气血会被打断（没有雷势）"]
		"skill_thunder_nine":
			return ["九霄：在目标周围落 2 + 雷势 道雷柱（每道半径 100）；释放时消耗全部雷势"]
		"skill_thunder_prison":
			return ["雷牢：在目标脚下布下雷环，1.2 秒后收拢；仍在圈内 → 造成一次雷伤并眩晕 1 秒"]
	return []


## 阵旗四式的「命中几何」不按通用形态写：布旗是点、引阵在旗段之间、封阵在阵心、解阵在每面旗
static func _array_shape_text(skill_id: String) -> String:
	match skill_id:
		"skill_array_plant":
			return "布点 · 玩家脚下"
		"skill_array_line":
			return "阵线 · 全部旗段（单线整段）"
		"skill_array_pull":
			return "阵线 · 连线最近一面旗 → 自身"
		"skill_array_seal":
			return "圆形 · 半径 210（阵心 = 四旗重心）"
		"skill_array_burst":
			return "每面旗 · 半径 140"
	return ""


## 阵旗八式各自的机制行（玩家侧：与 BOSS 同一套 5 面旗 / 不自然消失 / 多数色封阵）
static func _array_texts_for(skill: Dictionary) -> Array:
	if not bool(skill.get("array", false)):
		return []
	var slow_pct := int(round((1.0 - float(DebuffDB.get_debuff("lock_step").get("move_mult", 0.6))) * 100.0))
	var guard_pct := int(round(ARRAY_GUARD_REDUCTION * 100.0))
	var max_n := ARRAY_MAX_FLAGS
	match String(skill.get("skill_id", "")):
		"skill_array_plant":
			return [
				"插旗：在玩家脚下落一面阵旗，最多同时 %d 面；旗不会自然消失" % max_n,
				"旗型先补缺色：攻（朱砂）/ 困（墨）/ 守（石青）；某色已有两面时有 45% 概率补成三同色",
				"攻旗每 %.1f 秒自动轰击 150 内敌人（%.2f× 法攻）；困旗让 90 内敌人移速 -%d%%；守旗存活时你受到的伤害 -%d%%" % [
					ARRAY_ATTACK_INTERVAL, ARRAY_ATTACK_COEF, slow_pct, guard_pct],
				"破阵反噬：完整五旗被敌对破去一面时，眩晕 5 秒，并且 15 秒内插旗 / 踏阵 / 垒旗全部不可用",
			]
		"skill_array_line":
			return [
				"引阵：全部相邻旗之间拉出阵线（五面时首尾收口），每段一根线，按多数旗色整段结算——攻伤害 / 困锁步 / 守不伤人",
				"不消耗旗：阵线是常驻的，引阵只是把每一段同时引爆一次",
			]
		"skill_array_pull":
			return [
				"卷阵：将离 BOSS→玩家连线最近的一面旗卷回身侧，沿整根线按旗色结算（攻伤害 / 困锁步 / 守无伤）",
				"旗不消失：卷阵只调整阵位",
			]
		"skill_array_seal":
			return [
				"封阵·四象：四面旗成阵，按多数旗色结牢，以阵心连打四跳（每 0.55 秒，半径 210）",
				"攻牢：法伤 / 困牢：眩晕 5 秒 / 守牢：受伤 -70% 持续 10 秒；任一旗被破立即结束，封阵不撤旗",
			]
		"skill_array_sweep":
			return [
				"扫阵：纯物理横扫，不依赖旗；旗被拔光时也能近身应对",
			]
		"skill_array_step":
			return [
				"踏阵：向前突进并在落点结算一次；起手处留一面旗，不消耗旗",
			]
		"skill_array_pile":
			return [
				"垒旗：身前重击，落点 90 处再补一面旗；不依赖场上已有的旗",
			]
		"skill_array_burst":
			return [
				"解阵：引爆全部旗——攻旗造成伤害、困旗锁步敌人、守旗为你回复气血",
				"引爆后旗全部消失。",
			]
	return []


## 效果说明的纯文本版（tooltip 用，块之间用换行）
static func get_effect_text(skill_id: String) -> String:
	var lines: Array = []
	for item in get_effect_lines(skill_id):
		lines.append(String(item.get("text", "")))
	return _join(lines, "\n")


## 命中形态与范围
static func _shape_text(form: Dictionary) -> String:
	var rng := float(form.get("range", 0.0))
	var ang := float(form.get("angle", 0.0))
	match String(form.get("hit_shape", "")):
		MoveDB.SHAPE_FAN:
			return "扇形 · 射程 %.0f · 张角 %.0f°" % [rng, ang]
		MoveDB.SHAPE_LINE:
			return "直线贯穿 · 长度 %.0f" % rng
		MoveDB.SHAPE_CIRCLE:
			return "圆形 · 半径 %.0f" % rng
		MoveDB.SHAPE_RECT:
			return "矩形长条 · 长 %.0f · 宽 %.0f" % [rng, float(form.get("width", 0.0))]
		MoveDB.SHAPE_PROJECTILE:
			var t := "飞行物"
			var cnt := int(form.get("count", 1))
			if cnt > 1:
				t += " %d 发" % cnt
			t += " · 射程 %.0f · 速度 %.0f" % [rng, float(form.get("speed", 0.0))]
			var spread := float(form.get("spread", 0.0))
			if spread > 0.0:
				t += " · 散布 %.0f°" % spread
			var interval := float(form.get("interval", 0.0))
			if interval > 0.0:
				t += " · 间隔 %.2fs" % interval
			return t
		MoveDB.SHAPE_SELF:
			return "作用于自身"
	return ""


## 消耗与冷却
##
## ⚠ 消耗准则（用户 2026-10-19 定）：物理招式 1 格精力、法术招式耗灵力；
##   一剑开天双形态走 stamina_all / mana_all 抽空整条资源。
##   面板列表行的紧凑文案也走这里的 cost_resource_text()，不要另写一套。
static func _cost_text(skill_id: String) -> String:
	var cost := get_skill_cost(skill_id)
	var parts: Array = [cost_resource_text(cost)]
	# 力竭后遗症（一剑开天普通形态）：单独一行机制说明由调用方追加，这里只标时长
	var exhaust := float(cost.get("exhaust_time", 0.0))
	if exhaust > 0.0:
		parts.append("力竭 %.0f 秒（期间无法恢复精力）" % exhaust)
	parts.append("冷却 %.1fs" % float(cost.get("cooldown", 0.0)))
	return _join(parts, " · ")


## 资源消耗部分的文案（不含冷却）—— 面板列表行 / 详情 / 满层变体说明共用
## 入参是 get_skill_cost() 返回的消耗字典
static func cost_resource_text(cost: Dictionary) -> String:
	var all_stamina: bool = bool(cost.get("stamina_all", false))
	var all_mana: bool = bool(cost.get("mana_all", false))
	if all_stamina and all_mana:
		return "精力与灵力全部"
	if all_stamina:
		return "精力全部"
	if all_mana:
		return "灵力全部"
	match String(cost.get("cost_kind", MoveDB.COST_NONE)):
		MoveDB.COST_MANA:
			return "灵力 %.0f" % float(cost.get("mana_cost", 0.0))
		MoveDB.COST_STAMINA:
			return "精力 %d 格" % int(cost.get("stamina_cost", 0))
		MoveDB.COST_COOLDOWN:
			return "不耗资源"
		_:
			return "无消耗"


## 伤害系数（含五行标注）
static func _damage_text(skill_id: String, form: Dictionary) -> String:
	var phys := get_phys_coeff(skill_id)
	var spell := get_spell_coeff(skill_id)
	# 引阵整段按多数色结算：只有攻色才吃 0.8 倍法伤
	if skill_id == "skill_array_line":
		return "法术 ×%.2f（攻色）/ 困锁步 / 守无伤" % (spell * 0.8)
	var parts: Array = []
	if phys > 0.0:
		parts.append("物理 ×%.2f" % phys)
	if spell > 0.0:
		var t := "法术 ×%.2f" % spell
		var elem := String(form.get("damage_element", ""))
		if elem != "" and elem != "none":
			t += "（%s）" % String(AttributeDB.ELEMENT_NAMES.get(elem, elem))
		parts.append(t)
	return _join(parts, " · ")


## 招式自带的特殊机制（每项一行，按需生成 —— 没有的机制不会显示）
static func _mechanic_texts(form: Dictionary) -> Array:
	var out: Array = []

	# 施法前冲（破步突进斩这类）；多段突进走下面的「分 N 段前冲」，不重复印
	var fwd := float(form.get("move_forward", 0.0))
	if fwd > 0.0 and int(form.get("dash_times", 0)) <= 1:
		out.append("施法前冲 %.0f，前摇结束前冲完" % fwd)

	# 刀痕：只写「这门」的差异（留几道 / 落在哪 / 最多引爆几道）；
	# 留存秒数、场上上限、激活即瞬间斩击、连携倍率、归属规则都在本组顶部的刀痕卡里
	var scar := String(form.get("scar_effect", ""))
	if scar == "create":
		out.append("落点留下刀痕：距自身 %.0f" % float(form.get("scar_offset", 0.0)))
	elif scar == "ignite_path" or scar == "ignite_area":
		var t := "沿飞行路径激活刀痕" if scar == "ignite_path" else "激活范围内刀痕"
		var max_n := int(form.get("scar_ignite_max", 0))
		if max_n > 0:
			t += "，最多 %d 道" % max_n
		out.append(t)

	# 命中附带的负面状态（招式表根字段 debuff_on_hit）
	# ⚠ 这句以前只手写在各条 desc 里，玩家看不出「阴蚀 / 重伤」到底做什么；
	#   现在从 DebuffDB 现算 —— 加新 debuff 或改数字，文案自动跟着变
	var dhi := String(form.get("debuff_on_hit", ""))
	if dhi != "":
		out.append("命中附带「%s」%.0f 秒：%s" % [
			DebuffDB.display_name(dhi), float(form.get("debuff_time", 3.0)),
			_debuff_effect_text(dhi)])

	# 原地多跳领域（阴风蚀骨这类：玩家侧跳数与间隔单写，不被 BOSS 侧节奏绑死）
	var ticks := int(form.get("player_ticks", 0))
	if ticks > 1:
		out.append("原地领域共 %d 跳 · 每 %.2f 秒一跳（每一跳都重新结算伤害、挂印与附带状态）" % [
			ticks, float(form.get("player_tick_interval", 0.45))])

	# 多段突进（阳关三叠这类）：段数 × 每段位移 = 最远距离，全部读数据
	var dash_n := int(form.get("dash_times", 0))
	var fwd_each := float(form.get("move_forward", 0.0))
	if dash_n > 1 and fwd_each > 0.0:
		out.append("分 %d 段前冲 · 每段 %.0f（最远 %.0f）· 段间停 %.2f 秒；冲刺被身体挡住，踏到人即停" % [
			dash_n, fwd_each, fwd_each * float(dash_n), float(form.get("dash_gap", 0.0))])

	# 侧向摆动（阴阳双鱼）：两枚取反相 → 途中互相交叉
	var amp := float(form.get("swim_amp", 0.0))
	if amp > 0.0:
		out.append("两枚弹沿反相的正弦横移（摆幅 %.0f · 每秒 %.2f 个周期）：飞行途中互相交叉游来，平均航线仍在瞄准线上" % [
			amp, float(form.get("swim_freq", 0.0))])

	# 蓄力格挡（纳势反击这类：>0 才启用这套机制）
	# ⚠ 两仪·倒悬借用同一条释放路径，但判定完全不同（同色奉还 / 异色破势），
	#   它的文案由 _yinyang_texts() 出 —— 在这里印「只挡物理 · 减伤 0%」是错的
	var charge_max := float(form.get("charge_max", 0.0))
	if charge_max > 0.0 and not bool(form.get("yinyang_ward", false)):
		out.append("蓄力格挡：最多 %.1f 秒 · 减伤 %.0f%% · 只挡物理，法术照吃" % [
			charge_max, float(form.get("charge_block", 0.0)) * 100.0])
		var gain := float(form.get("charge_coeff_gain", 0.0))
		if gain > 0.0:
			out.append("每蓄 1 秒 / 每挨 1 次：伤害系数 +%.2f（无上限）" % gain)
		out.append("左键可提前斩出，蓄满自动释放")

	# 剑意积攒（刺/撩/斩/云：仅释放 +N 层，命中不叠加 —— 用户 2026-10-19 定）
	var ig := int(form.get("intent_gain", 0))
	if ig > 0:
		out.append("释放时积攒 %d 层剑意" % ig)

	# 万剑归宗：飞剑数随剑意放大（数值读 intent_count_scale，不手抄）
	var ics: Dictionary = form.get("intent_count_scale", {})
	if not ics.is_empty():
		out.append("飞剑数 = %d + 剑意×%d，释放后清空剑意" % [
			int(ics.get("base", 2)), int(ics.get("per", 2))])
	return out


## debuff 的效果摘要：直接委托 DebuffDB.effect_text（唯一一份，图鉴状态模块共用）
static func _debuff_effect_text(debuff_id: String) -> String:
	return DebuffDB.effect_text(debuff_id)


## 两仪势的说明行 —— 只讲**这门自己的差异**（算什么色、逆式怎么触发、挂哪枚印）。
## 势 / 印 / 逆式 / 引爆 / 谁能参与这些共享规则，统一在本组顶部的两仪势卡里
## （`get_yinyang_rules()`），数字同样来自 YINYANG_*，一处改全变。
static func _yinyang_texts(skill: Dictionary, form: Dictionary) -> Array:
	if not bool(skill.get("yinyang", false)):
		return []
	var out: Array = []
	var mark_pct := int(round(YINYANG_MARK_BONUS * 100.0))
	match String(skill.get("polarity", "")):
		"yang", "yin":
			var mine := "阳" if String(skill.get("polarity", "")) == "yang" else "阴"
			var other := "阴" if String(skill.get("polarity", "")) == "yang" else "阳"
			var res := "物理" if String(skill.get("polarity", "")) == "yang" else "术法"
			out.append("两仪势 · 这门算%s（%s命中）：势条当前为%s时打出 = 逆式，势随即转成%s；已是%s时 = 顺式，只跟色、不叠层（势条空时任意颜色都算逆式起势）" % [
				mine, res, other, mine, mine])
			out.append("印 · 这门命中给目标挂「%s印」，随后用%s打中带%s印的目标就能引爆" % [
				mine, "术法" if mine == "阳" else "物理", mine])
		"neutral":
			out.append("两仪势 · 这门不算颜色（中性）：不吃逆式、不叠势、不挂印，作用是手动翻势")
			out.append("效果：势条立刻翻成相反颜色；清除自身的阴蚀；身上有势时消耗 1 层，让下一招必定按逆式结算（%.0f 秒内有效）" % YINYANG_FLIP_FORCE_SECONDS)
		"mixed":
			out.append("两仪势 · 混伤（阴阳齐走）：不吃逆式、不挂印；释放瞬间把身上的势全部吞掉")
			out.append("每层势追加 +%.2f 物理 / +%.2f 法术系数（势上限 %d 层）；满层命中额外让目标硬直 %.1f 秒，并同时挂上阳印与阴印" % [
				YINYANG_COLLAPSE_COEFF_PER_STACK, YINYANG_COLLAPSE_COEFF_PER_STACK,
				YINYANG_MAX_STACKS, YINYANG_COLLAPSE_STAGGER_SECONDS])
		_:
			# 两仪·双鱼：故意不写 polarity —— 两枚弹各算一次颜色
			out.append("两仪势 · 这门不预设颜色：两枚弹各自按「物理 = 阳、术法 = 阴」判定，所以一出手最多连着走两次逆式（+2 层势）")
			out.append("阳弹在前、阴弹在后：阳弹挂阳印，阴弹随后把它引爆（这一发 +%d%%）并改挂阴印" % mark_pct)
			out.append("势条当前为阴 → 阳弹那发就是逆式（先 +1 层），阴弹再 +1 层；势条当前为阳 → 只有阴弹那发算逆式（势条空时两发都算起势）")
	if bool(form.get("yinyang_ward", false)):
		out.append("守势（倒悬）：撑 %.1f 秒 —— 与势条同色的攻击被全额奉还（不吃这发伤害、势翻面、+1 层）" % float(form.get("charge_max", 1.0)))
		out.append("被%s（异色）打中则破势：这一发多受 %d%%，而且蓄好的反击不再斩出" % [
			"术法" if String(skill.get("polarity", "")) == "yang" else "物理",
			int(round((YINYANG_WARD_BREAK_MULT - 1.0) * 100.0))])
		out.append("反击系数 = 1.00 +（蓄力秒数 + 奉还次数）× %.2f，守得越久、奉还越多越痛" % float(form.get("charge_coeff_gain", 0.0)))
	return out


## 被动功法的说明行：被动没有形态可读，所以按 passive_effect 现算。
## 只讲这门被动**自己**带来的范围与代价；势 / 印 / 逆式 / 引爆的规则与势条显示条件
## 都在本组顶部的两仪势卡里（`get_yinyang_rules()`），这里不再重复一遍。
static func _passive_texts(skill: Dictionary) -> Array:
	var out: Array = []
	match String(skill.get("passive_effect", "")):
		"sword_intent_physical":
			var cap := int(MoveDB.resolve_player("form_sword_heaven").get("intent_full_at", 5))
			var pct := int(round(SWORD_INTENT_PHYS_PER_STACK * 100.0))
			out.append("作用：每层剑意使自身物理功法伤害 +%d%%（上限 %d 层，满层 +%d%%）；只乘功法本身的物理段，普攻、法术、召唤物与刀痕 / 场地后续触发不吃。" % [
				pct, cap, pct * cap])
			out.append("积攒扩展：任意物理近战功法（非投射物、非大招）释放时积攒 1 层；刺 / 撩 / 斩 / 云原本就积攒，不重复叠加（云是投射物，按原有规则保留）；两招大招照常清空剑意。")
			out.append("代价：占唯一被动槽；受击仍会掉 1 层。")
		"yinyang_stacks":
			out.append("作用：把阴阳这套语言从「两仪那八门」推广到**全部伤害来源** —— 普攻、其他 BOSS 功法、阵旗 / 气环 / 刀痕的直接结算都开始算色、吃逆式、引爆印")
			out.append("注意：只有**主动出手的命中**能叠势 / 翻面；阵旗自动剑气、环身气、刀痕等后续触发只吃逆式增伤与逆印结算，不叠层、不消耗「必定逆式」。叠势仍要求逆式（与势条当前颜色相反），全物理 build 需要带一门阴属性法术来交替")
			out.append("代价是占唯一的被动槽（被动只能带 1 门）：戴了它，整套 build 都往两仪势上靠")
		"sun_seed_bearer":
			out.append("作用：战斗开始 1 秒后，在自身 90~130 范围凝出一枚天火种；火种被消耗后 1.5 秒再凝一枚。")
			out.append("持种时每层日冕使自身所有伤害 +12%（最多 3 层），作用于普攻、其他功法与火焰功法。")
			out.append("离照会争夺这一枚火种；没有火种时，投日 / 日蚀 / 牵日仍可释放基础版。")
		"qi_ring_leech":
			out.append("作用：佩戴后，环身气碰到敌人结算伤害时，把该次伤害的 10% 回复为自身气血。")
			out.append("不佩戴时气环仍会造成伤害并挂滞气，但不会回血；这门被动只影响回复，不影响气环伤害与气环资源。")
		"thunder_accum_stun":
			out.append("震魂：每只敌人独立累计 %d 次雷击 → 眩晕 %.1f 秒并清零。" % [
				THUNDER_ACCUM_REQUIRED, THUNDER_ACCUM_STUN_SECONDS])
			out.append("雷势回响：每消耗 1 格雷势 → 全主动功法 CD -%d 秒。" % [
				int(round(THUNDER_ACCUM_CD_PER_LEI))])
			out.append("例：九霄·雷罚消耗 %d 格时，全主动 CD -%d 秒。" % [
				THUNDER_MAX_LEI, int(round(THUNDER_ACCUM_CD_PER_LEI * THUNDER_MAX_LEI))])
			out.append("雷击判定：判词八式、三灾·雷灾与任何雷属性命中。")
			out.append("满雷势协同雷击、五阵旗雷击也计入；普攻本体不算。")
			out.append("装备后生效，占唯一被动槽。")
		"calamity_stance":
			out.append("作用：装备后开启玩家三灾轮；任意风 / 火 / 雷属性功法命中都会切换灾位，并获得对应灾身加成（风 +%d%% 移速 / 火 +%d%% 法技增伤 / 雷 +%d%% 攻速）。" % [
				int(CALAMITY_BOON_PCT), int(CALAMITY_BOON_PCT), int(CALAMITY_BOON_PCT)])
			out.append("破灾：使目标灾崩 3 秒，灾崩期间目标受到的伤害 +%d%%。" % [
				int(round((CALAMITY_BREAK_TAKEN_MULT - 1.0) * 100.0))])
			out.append("未装备时没有玩家灾位、灾势、灾替与万劫归一；仍可用任意风 / 火 / 雷功法破灾 / 喂灾，八式改走「灾劫连锁」（风 / 火 / 雷三痕互相引爆）。")
			out.append("占唯一被动槽。")
		"mirror_echo":
			out.append("作用一：镜像上限再 +%d 具（%d 具 → %d 具）。" % [
				MirrorImage.PASSIVE_EXTRA_IMAGES, MirrorImage.MAX_IMAGES,
				MirrorImage.MAX_IMAGES + MirrorImage.PASSIVE_EXTRA_IMAGES])
			out.append("作用二：完美闪避后，在原地留下一具镜像（存在 %.0f 秒），每 %.0f 秒最多触发一次。" % [
				MirrorImage.IMAGE_LIFE, MirrorImage.PASSIVE_CD])
			out.append("镜像复读规则（与是否佩戴本被动无关）：你每放一次打得出伤害的功法（镜花 / 万镜除外），场上所有镜像同时跟着使出同一招，伤害为该次的 %d%%，放完即碎；任何物理命中都能一击即碎。" % [
				int(round(MirrorImage.ECHO_RATIO * 100.0))])
			out.append("不装备时仍可用镜花 / 万镜主动召镜，只是上限少 1 具、也少一个完美闪避的免费来源。")
			out.append("占唯一被动槽。")
		_:
			pass
	return out


## 两仪势总说明（功法库顶部与图鉴共用；数值同样来自 YINYANG_*）
static func get_yinyang_rules() -> Array:
	var out: Array = [
		"算色：物理命中 = 阳，术法命中 = 阴。学会任意一门两仪功法后生效；未学会时不参与。",
		"逆式：打出的颜色与势条当前颜色相反。势条空时第一发任意颜色都算逆式起势（+1 层并定色）；逆式命中伤害 +%d%%，势条随即转为该招颜色。同色为顺式，不叠层。" % int(round(YINYANG_REVERSE_BONUS * 100.0)),
		"势：每层使后续伤害 +%d%%（逆式、顺式均生效）。" % int(round(YINYANG_STACK_BONUS * 100.0)),
	]
	var gate := get_passive_by_effect("yinyang_stacks")
	if gate.is_empty():
		out.append("叠势：逆式命中（含空条起势的第一发）叠 1 层，上限 %d 层。" % YINYANG_MAX_STACKS)
	else:
		out.append("参与条件：未佩戴被动「%s」时，只有两仪真人掉落的八门功法参与阴阳；佩戴后，普攻、其他功法及阵旗 / 气环 / 刀痕的直接伤害也参与。只有主动出手命中能叠势 / 翻面；后续触发只获得增伤与逆印结算，不叠层。势条显示条件：佩戴被动时始终显示；未佩戴时主动槽需装有会算颜色的两仪功法。" % String(gate.get("skill_name", "")))
	out.append("阳印 / 阴印：只有两仪功法命中会挂印，颜色与招式相同，持续 %.0f 秒；印本身不造成伤害、不减防。" % YINYANG_MARK_SECONDS)
	out.append("阴阳爆：用相反颜色的命中打带印目标（阴命中阳印 / 阳命中阴印）→ 该发 +%d%%，消耗印并改挂本次命中颜色的印。佩戴被动时，这一发可以是普攻或其他功法。" % int(round(YINYANG_MARK_BONUS * 100.0)))
	out.append("例外：太极崩为混伤，不吃逆式、不挂印，消耗全部势换取伤害，满层时挂双印；两仪转为中性，不叠势，用于翻势并让下一招必定逆式。")
	return out


## 两仪势总说明的纯文本版（功法库与图鉴共用，免得两处各拼一遍前缀）
static func get_yinyang_rules_text(title: String) -> String:
	var lines: Array[String] = [title]
	for r in get_yinyang_rules():
		lines.append("· " + String(r))
	return "\n".join(lines)


# ===================== 组级机制说明 =====================
## 每个 BOSS 功法组共享的规则**只在本组顶部讲一遍**，单门详情只留这门自己的差异
## （2026-10-28 用户定：各技能重复的字段上收到总的 BOSS 功法下面）。

## 本组该挂哪张机制卡：{ "title", "lines" }；没有共享机制就返回空字典
static func get_group_rules(boss_id: String) -> Dictionary:
	if boss_id == "":
		return {}
	var skills: Array = []
	for s in SKILLS:
		if String((s as Dictionary).get("source_boss_id", "")) == boss_id:
			skills.append(s)
	if skills.is_empty():
		return {}
	for s in skills:
		if bool((s as Dictionary).get("yinyang", false)):
			return {
				"title": "两仪势 · 阳印 / 阴印 · 逆式（学会任意一门两仪功法后才生效）",
				"lines": get_yinyang_rules(),
			}
	for s in skills:
		if bool((s as Dictionary).get("array", false)):
			return {"title": "三色阵旗 · 攻 / 困 / 守（学会任意一门阵旗功法后生效）", "lines": get_array_rules()}
	for s in skills:
		if bool((s as Dictionary).get("qi", false)):
			return {"title": "气环 · 化劲（学会任意一门气君功法后才生效）", "lines": get_qi_rules()}
	for s in skills:
		if bool((s as Dictionary).get("thunder", false)):
			return {
				"title": "判词 · 天律（学会任意一门判官功法后才生效）",
				"lines": get_thunder_rules(),
			}
	for s in skills:
		if bool((s as Dictionary).get("sun", false)):
			return {
				"title": "逐日 · 天火（学会任意一门逐日功法后才生效）",
				"lines": get_sun_rules(),
			}
	for s in skills:
		if bool((s as Dictionary).get("calamity", false)):
			return {
				"title": "三灾 · 轮转（学会任意一门三灾功法后才生效）",
				"lines": get_calamity_rules(),
			}
	for s in skills:
		if bool((s as Dictionary).get("mirror", false)):
			return {
				"title": "镜身 · 照影（学会任意一门观澜功法后才生效）",
				"lines": get_mirror_rules(),
			}
	for s in skills:
		if bool((s as Dictionary).get("shadow", false)):
			return {
				"title": "投影 · 身外之影（学会任意一门执烛功法后才生效）",
				"lines": get_shadow_rules(),
			}
	for s in skills:
		if bool((s as Dictionary).get("fold", false)):
			return {
				"title": "折影为径 · 空间连通（学会任意一门叠纸功法后才生效）",
				"lines": get_fold_rules(),
			}
	if _group_forms_have(skills, "scar_effect"):
		return {"title": "刀痕 · 留痕 → 激活 → 连携", "lines": get_scar_rules()}
	if _group_forms_have(skills, "intent_gain") \
			or _group_forms_have(skills, "intent_count_scale"):
		return {"title": "剑意 · 攒层 → 两招用法", "lines": get_intent_rules()}
	return {}


static func group_rules_text(rules: Dictionary) -> String:
	var lines: Array[String] = [String(rules.get("title", ""))]
	for r in rules.get("lines", []):
		lines.append("· " + String(r))
	return "\n".join(lines)


## 组内是否有任何一门的**玩家侧形态**带这个字段（机制卡按它决定挂不挂）
static func _group_forms_have(skills: Array, field: String) -> bool:
	for s in skills:
		var fid := get_form_id(String((s as Dictionary).get("skill_id", "")))
		if fid == "" or not MoveDB.has_form(fid):
			continue
		if not MoveDB.resolve_player(fid).is_empty() \
				and MoveDB.resolve_player(fid).has(field):
			return true
	return false


## 刀痕总说明：留存秒数与场上上限全部读 BladeScar / ScarField，改常量文案自动跟上
static func get_scar_rules() -> Array:
	return [
		"部分刀法命中后在落点留下刀痕，持续 %.0f 秒，场上最多 %d 道；达到上限时移除最早的一道。" % [
			BladeScar.SCAR_LIFE, ScarField.MAX_NORMAL],
		"刀痕不造成伤害，只限制走位。刀气 / 刀域等招式经过或覆盖刀痕时，触发一次斩击，刀痕随后消失。",
		"斩击伤害类型与留痕技能一致：物理留痕按物攻结算、受物抗减免；法术留痕按法强 × 法技增伤结算、受法抗减免。伤害在留痕时记录；引爆时乘以日冕持种加成；BOSS 侧按攻击力结算。",
		"每道斩击的伤害乘以本次激活的刀痕数量：一次激活几道，就按几倍结算。",
		"玩家刀痕只伤害敌人，BOSS 刀痕只伤害玩家；双方使用同一套留痕 / 引爆规则。",
		"每门引爆招式可引爆的刀痕数量上限写在该技能的说明中。",
	]


## 剑意总说明（玩家侧）
## ⚠ 上限读 form_sword_heaven 的 intent_full_at（与 player.gd 的 SWORD_INTENT_MAX 对齐）；
##   「受到一次攻击掉 1 层」对应 player.gd 的 SWORD_INTENT_LOSS_ON_HIT，改那边要同步这句。
static func get_intent_rules() -> Array:
	var heaven := MoveDB.resolve_player("form_sword_heaven")
	var cap := int(heaven.get("intent_full_at", 5))
	var out: Array = [
		"积攒：刺 / 撩 / 斩 / 云每释放一次增加对应层数，命中不额外叠加；上限 %d 层；受到一次攻击掉 1 层。" % cap,
	]
	var ics: Dictionary = MoveDB.resolve_player("form_sword_myriad").get("intent_count_scale", {})
	if not ics.is_empty():
		out.append("用法一 · 万剑归宗：飞剑数 = %d + 剑意×%d；释放后清空剑意。" % [
			int(ics.get("base", 2)), int(ics.get("per", 2))])
	if String(heaven.get("full_form_id", "")) != "":
		out.append("用法二 · 一剑开天：剑意满 %d 层时替换为法术巨斩（使用变体形态数据）；释放后清空剑意。" % cap)
	var gate := get_passive_by_effect("sword_intent_physical")
	if not gate.is_empty():
		var pct := int(round(SWORD_INTENT_PHYS_PER_STACK * 100.0))
		out.append("被动「%s」：佩戴后每层剑意使物理功法伤害 +%d%%（满 %d 层 +%d%%）；任意物理近战功法（非投射物、非大招）释放时也积攒 1 层，刺 / 撩 / 斩 / 云不重复叠加；占唯一被动槽。" % [
			String(gate.get("skill_name", "")), pct, cap, pct * cap])
	out.append("显示：HUD 不显示层数；攒层时有积攒特效，满层时技能栏图标显示剑气环绕。")
	return out


## 剑意满层变体（一剑开天 → 一剑开天·剑意盈天）
## 触发层数与变体形态全部读数据表（form_sword_heaven 的 player.intent_full_at / full_form_id），
## 变体的形状/范围读它自己的形态条目 —— 改数值只改表，文案自动跟上。
static func _intent_full_text(form: Dictionary) -> String:
	var full_id := String(form.get("full_form_id", ""))
	if full_id == "" or not MoveDB.has_form(full_id):
		return ""
	var cap := int(form.get("intent_full_at", 0))
	var ff := MoveDB.resolve_player(full_id)
	var shape_text := _shape_text(ff)
	var t := "剑意满 %d 层时变为法术伤害" % cap
	if shape_text != "":
		t += "（%s）" % shape_text
	# 满层变体的消耗口径可能与普通形态不同（一剑开天：全部精力+灵力、无力竭）——
	# 从变体条目现算，避免「库里写着耗蓝、实际抽空灵力」的货不对板
	var full_skill_id := get_skill_id_by_form(full_id)
	if full_skill_id != "":
		var res := cost_resource_text(get_skill_cost(full_skill_id))
		if res != "":
			t += "，变体消耗%s" % res
	return t


## 拼字符串（Array 没有内建 join，PackedStringArray 才有）
static func _join(parts: Array, sep: String) -> String:
	var s := ""
	for i in parts.size():
		if i > 0:
			s += sep
		s += String(parts[i])
	return s

## 玩家侧阵旗参数（唯一来源：player.gd 与功法库文案都读这里）
## 与 BOSS 同口径：5 面上限、旗不自然消失、攻旗 2.6 秒 / 0.45× 法攻、困旗锁步 90
const ARRAY_MAX_FLAGS := 5
const ARRAY_ATTACK_INTERVAL := 2.6
const ARRAY_ATTACK_COEF := 0.45
const ARRAY_GUARD_REDUCTION := 0.15


## 判词规则卡（赫连霄）：功法库顶部与图鉴共用
static func get_thunder_rules() -> Array:
	return [
		"判词：宣判按目标最近 1.5 秒的行为选择律：移动→禁行，出手→禁攻，闪避→禁避，站定→禁立。每条律持续 5 秒；赫连霄二阶段的律持续 6 秒。",
		"四条律：禁行每移动 110 引来 0.80× 雷击；禁攻在目标进入攻击动作时引来 0.90× 雷击（不要求命中）；禁避在目标 0.2 秒内位移 ≥140 像素时引来 0.80× 雷击（赫连霄对玩家按实际闪避判定）；禁立原地 0.9 秒后每 0.9 秒引来 0.70× 雷击。",
		"违律：雷击有 0.25 秒预警，可走位躲避；赫连霄雷势 +1（上限 3），判词不会因此提前结束。",
		"守律：每条律全程未违律 → 玩家获得顺天 6 秒（攻速 +20%、移速 +10%），赫连霄雷势 -1。",
		"雷势：0~3 层；九霄·雷罚消耗全部层数，每层追加一道雷柱；玩家通过使敌人违律和聚雷·引霆获得雷势。",
		"满雷势：普攻间隔 ÷1.3（攻速 +30%）；每次普攻在身前 320 内最近目标处落一道协同雷（法术 ×0.50，落点 62 内敌人共同承受）；协同雷计入雷积·震魂。未满层时两项均不生效。",
		"雷积·震魂（被动）：每只敌人累计 %d 次雷击 → 眩晕 %.1f 秒并清零；每消耗 1 层雷势 → 全主动技能冷却 -%d 秒。满雷势协同雷与五阵旗雷击均计入。" % [
			THUNDER_ACCUM_REQUIRED, THUNDER_ACCUM_STUN_SECONDS,
			int(round(THUNDER_ACCUM_CD_PER_LEI))],
		"抗辩：宣判是物理笔锋，可弹反；弹反撤销判词、使赫连霄僵直、雷势 -1。",
		"滞雷：锁雷命中后移速 -25%、闪避距离 -30%。",
		"判词会改变被下律 BOSS 的行为：禁行时减少移动，禁攻时暂停出手，禁避时减少雷遁，禁立时减少站定。",
	]


## 逐日规则卡（离照）：功法库顶部与图鉴共用
static func get_sun_rules() -> Array:
	return [
		"天火种：场上 1 枚；双方进入 46 像素自动拾取；落地后 0.6 秒内不可拾取。被消耗或爆裂后 8 秒在新位置重生，二阶段 6 秒。",
		"日冕：持种者每 1.6 秒 +1 层，上限 3 层；玩家每层所有伤害 +12%，离照每层攻击 +8%；离照持种额外减伤 15%。",
		"引燃：玩家每次叠满 3 层获得 1 次引燃，下一次逐日功法造成伤害后，目标体内延迟 1 秒爆出 2.0 倍法强的火系伤害；引爆会消耗该火种 1 层日冕（即使火种已脱手），并立刻刷新逐日步冷却，之后需重新叠满。",
		"逐日步：无方向输入时朝火种突进；场上无火种或火种在身上时朝最近敌人；有方向输入优先按输入方向。",
		"满层：持种者每秒受到 6 点火焰伤害；3 秒后火种爆裂，玩家损失 12% 最大气血，离照损失 6%。",
		"夺火：逐日步、牵日、焚风、日蚀必须实际命中持有者；层数随火种转移。离照的逐日步落点在首帧固定，牵日走廊宽 50，焚风只认正中 60°，日蚀需留在黑日圈内侧（约 72% 半径）。",
		"火忌：连续两次夺火落空后，离照 6 秒内无法使用逐日步、牵日、焚风、日蚀；日轮显示「禁6」倒计时。",
		"盗火者（被动）：战斗开始 1 秒在自身 90~130 范围生成一枚天火种；火种被消耗后 1.5 秒再生成一枚。离照会争夺这一枚火种。",
		"无种基础版：投日掷余烬火球，造成 65% 伤害；日蚀在目标处造成 65% 伤害、75% 半径；牵日造成 100% 火伤并附加灼心。有火种时为完整版，并受日冕全伤害加成。",
		"天火坠：无火种时单发；有火种时在火种位置与目标位置各落一发，两圈重叠时目标受到两份伤害，火地叠加两层。二阶段离照的天火坠在火种或目标处落下，留下 4 秒火地。",
		"BOSS 弱点：逐日步、牵日收招期间受到伤害 +15%；将火种从离照手中夺走会移除其减伤与日冕加伤。",
	]


## 三灾规则卡（晏无咎）：功法库顶部与图鉴共用
## 按触发属性取灾劫连锁定义（wind / fire / thunder）；空串 = 无反应
static func calamity_reaction_for(trigger_tag: String) -> Dictionary:
	if trigger_tag == "":
		return {}
	for raw in CALAMITY_REACTIONS.values():
		var reaction: Dictionary = raw
		if String(reaction.get("trigger", "")) == trigger_tag:
			return reaction
	return {}


static func get_calamity_rules() -> Array:
	return [
		"灾位：风 / 火 / 雷，双方各一。任意风 / 火 / 雷属性功法命中都参与破灾 / 喂灾，不要求晏无咎本族功法；装备被动「三灾·灾身」后，任意风 / 火 / 雷功法命中还会切换玩家灾位并提供灾身加成；未装备时没有玩家侧灾位、灾势、灾替与万劫归一。",
		"灾劫连锁（装备或未装备「三灾·灾身」都生效）：风灾命中附加风蚀、火灾附加劫火、雷灾附加感电。用克制已有灾痕的属性命中会引爆：风引爆劫火＝风助火势（在引爆点留下 3 秒火龙卷，每 0.5 秒造成火伤并续劫火）；火引爆感电＝雷火交击（一次火伤爆发，周围溅射）；雷引爆风蚀＝风雷引（留下 3 秒风雷涡，持续把范围内敌人吸向中心，不造成伤害）。引爆消耗该灾痕，招式自身再留下本属性灾痕；燎原 / 雷池的持续跳伤也能引爆，同一道灾痕只消耗一次。",
		"相克：风克火、火克雷、雷克风。用任意克制目标当前灾位的风 / 火 / 雷功法命中 → 伤害 ×1.15，自身灾势 +1，目标灾崩 3 秒（失去灾身、受到伤害 +30%、灾轮冻结）。",
		"同灾：用与目标相同属性的功法命中 → 伤害 ×0.85，目标灾势 +1。",
		"灾势：自身切换灾位 +1，破灾 +1，上限 3；目标轮转或破灾也 +1。万劫归一消耗全部灾势追加灾柱与伤害，0 层也可以释放，伤害较低。",
		"灾身：风=目标移速 +25% 且物理击退 / 玩家移速 +12%；火=目标命中挂劫火 / 玩家法技增伤 +12%；雷=目标命中挂感电 / 玩家攻速 +12%。灾崩会移除目标的灾身。玩家侧灾身需装备被动「三灾·灾身」。",
		"被破灾：被克制自身灾位的功法命中 → 受到伤害 ×1.15，灾势 -1，锁灾 2 秒（期间不能切换灾位）。三灾轮转起手 1.5 秒 / 三灾轮法宝 8 秒内，第一次被破灾触发灾替：免疫本次破灾并 +1 灾势。",
		"锁灾：雷池首跳锁目标灾轮 3 秒，期间不能轮转。",
		"二阶段·三灾归一：50% 气血时进入 8 秒三灾归一，无法破灾，受到伤害 +20%；结束后灾轮每 5 秒轮转一次，万劫归一出招权重提高。",
		"BOSS 弱点：三灾轮转前摇 0.7 秒，用任意克制其当前灾位的风 / 火 / 雷功法命中可以打断并直接灾崩；裂云步 / 断空斩为物理，可弹反。",
	]


## 气环规则卡（太虚气君）：功法库顶部与图鉴共用
static func get_qi_rules() -> Array:
	return [
		"气环：上限 5 枚。引气·聚环生成 1 枚，踏罡·缩地落地生成 1 枚。气环绕体：环接触敌人时结算一次 0.30× 法攻并附加滞气 0.8 秒；同一敌人同一次接触只结算一次，离开再碰才再次结算。",
		"回血被动：佩戴被动「气环·回息」时，气环接触伤害的 10% 回复自身气血；未佩戴时不回复。",
		"消耗：冲气·裂空消耗 1 枚，伤害 +0.5 倍、射程 +90；气锁·缚脉消耗 1 枚，可将 BOSS 移速压至 50% 并封技 2 秒；气爆·周天消耗全部，每枚 +0.60 倍，0 枚时为基础 1.00 倍；化劲·卸力消耗 1 枚。",
		"化劲：2.2 秒内受到伤害 -40%，储存其中 60%（上限 140）；结束时释放气浪，伤害 1.20 倍基础 + 储存量；气浪为物理近战，可弹反。",
		"滞气：被气锁·缚脉或环身气命中后，灵力停止回复、移速 -20%；缚脉持续 4 秒，环身气持续 0.8 秒。",
		"归元·吐纳消耗 1 枚气环，冷却 10 秒；1.2 秒引导期间受到超过 8% 最大气血的伤害会被打断，打断后不回复。",
		"气环不会自然消失；达到 5 枚后不再生成。",
	]


## 阵旗规则卡（定阵先生）：功法库顶部与图鉴共用
static func get_array_rules() -> Array:
	return [
		"阵旗：最多同时 5 面，不会自然消失。插旗落在玩家脚下，并自动补缺色：攻（朱砂）、困（墨）、守（石青）；某色已有两面时有 45% 概率补成三同色。",
		"攻旗每 2.6 秒自动攻击 150 内敌人（0.45× 法攻）；困旗使 90 内敌人锁步；守旗存活时玩家受到伤害 -15%。",
		"阵线：相邻旗自动连线（5 面时首尾收口），每段一根线，阻挡移动；施法者与友军可穿行。打掉旗解除对应阵线。玩家站在任意阵线上时伤害 +10%。",
		"五旗成环：环内玩家攻击 / 防御 +30%（防御按受伤 ×1/1.3）；环内敌人攻击 -10%；每秒落雷 0.6× 法攻，每次消耗 10 法力；法力不足时五旗自动消散。被围住的敌人会把最近的旗作为普通目标攻击；旗有 3 点耐久，3 次伤害后消失。",
		"破阵反噬：玩家完整五旗被敌对破坏一面时，眩晕 5 秒，且 15 秒内插旗 / 踏阵 / 垒旗不可用。",
		"引阵：全部旗段同时引爆一次（每段按多数色整段结算），不消耗旗；卷阵将离 BOSS→玩家连线最近的一面旗卷回身边，并沿整根线结算，不撤旗。",
		"封阵·四象：四面旗成阵，按多数旗色结牢（每 0.55 秒，半径 210）——攻牢伤害 / 困牢眩晕 5 秒 / 守牢受伤 -70% 持续 10 秒（任一旗被破坏立即结束）；解阵按旗色引爆全部旗后清场。",
		"对 BOSS 同样生效：打掉它的旗会解除阵线、封阵与解阵；它的五旗环也会阻挡、降低攻击并落雷（消耗隐藏阵力，阵力耗尽撤旗）。",
	]


static func get_array_rules_text(title: String) -> String:
	var lines: Array[String] = [title]
	for r in get_array_rules():
		lines.append("· " + String(r))
	return "
".join(lines)
