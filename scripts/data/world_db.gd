class_name WorldDB
extends RefCounted
## 世界静态数据表：万界位面（界域）/ 万界塔 / 记忆碎片
## 字段对齐任务书 §5.3 BOSS 数据、§5.7 记忆碎片数据
##
## 硬约束：
##   - §2.7 进入下一界域条件：境界达标 + 通关上一界域全部 BOSS
##   - §2.8.3 万界塔是唯一功法来源；重复击杀不再获得功法
##   - §2.8.4 万界塔禁止产出功法以外的成长资源
##
## 命名：第一界域定名「凡界」，其 BOSS 定名「刀客」；后续界域暂以「位面 0X」占位。
##
## ⚠ 条目为示例数据，正式内容待定稿

# ===== 万界位面 / 界域 =====
## prev_domain 为前置界域 id（空表示首个）
## 解锁规则：首个界域默认开放；其余通关前置界域后自动开放（见 CharacterData.is_domain_unlocked）
##
## ⚠ boss_ids 为**唯一**的「本界域有哪些 BOSS」来源。
##   **每个位面固定 3 名 BOSS，三名全部击杀才算通关该位面**（2026-10-17 用户定），
##   通关后才自动开放下一个位面 / 对应的万界塔层。
##   空数组 = 本界域暂无内容，视为「未通关」（不会误判为已通关），
##   因此依赖它解锁的下一界域/塔层都会保持锁定。
##
## ⚠ **数组顺序同时是挑战顺序**（2026-11-12 用户定）：只有第一个还没击杀的能进，
##   已击杀的仍可再战。调整数组顺序 = 改玩家的实际推进路线（塔层号也跟着重排），
##   判据见 CharacterData.is_boss_challengeable，不是界面自己排的。
##
## 命名：每个位面的第 1 名 BOSS 沿用原来的 boss_0X（塔层与旧存档都指向它），
##   第 2/3 名用 boss_0X_b / boss_0X_c。除 boss_01（刀客）外均为**占位内容**，
##   战斗会回退到原型 BOSS（见 BOSS_SCENES）。
const DOMAINS: Array = [
	{
		"domain_id": "domain_01",
		"name": "凡界",
		"realm_required": "练气",
		"prev_domain": "",
		"boss_ids": ["boss_huyao", "boss_01", "boss_01_c"],
		"desc": "最下层的凡俗界域。虎妖先守住界门，刀客在门后等着。",
	},
	{
		"domain_id": "domain_02",
		"name": "冲和界",
		"realm_required": "筑基",
		"prev_domain": "domain_01",
		"boss_ids": ["boss_02", "boss_02_b", "boss_02_c"],
		"desc": "万物负阴而抱阳，冲气以为和。",
	},
	{
		"domain_id": "domain_03",
		"name": "赤霄界",
		"realm_required": "结丹",
		"prev_domain": "domain_02",
		"boss_ids": ["boss_03", "boss_03_b", "boss_03_c"],
		"desc": "雷出于地，火生于天；一念动，九霄皆兵。",
	},
	{
		"domain_id": "domain_04",
		"name": "照影界",
		"realm_required": "元婴",
		"prev_domain": "domain_03",
		# 照影界三位（观澜 = 镜身 / 执烛 = 投影 / 叠纸 = 折径）
		"boss_ids": ["boss_04", "boss_04_b", "boss_04_c"],
		"desc": "镜水无波，万象皆有其影；照影界以倒影证道，真假同源。",
	},
]
# ===== 万界塔 =====
## 塔层表 —— **由 DOMAINS 自动生成，不需要单独维护**：
##   每个位面的每一名 BOSS 各占一层，层号从 1 开始，按「位面顺序 → 位面内 BOSS 顺序」连续编号。
##   例：凡界 3 只 = 第 1~3 层，位面 02 = 第 4~6 层，位面 03 = 第 7~9 层，照影界首位 = 第 10 层。
##   → 新增 / 调整位面 BOSS 时只改 DOMAINS，塔层自动跟着变。
##
## **解锁规则（2026-10-17 用户定）**：在万界秘境**击败该层对应的那名 BOSS**，
##   对应塔层立刻开放（不再等整个位面通关）。见 CharacterData.is_tower_floor_unlocked。
##
## 首杀感悟：该层 BOSS 的招式 → 反查对应功法（见 get_floor_reward_skills）。
## 没在 BOSS_MOVES 里登记招式的 BOSS（目前是占位 BOSS），该层没有功法可感悟，只能打。
##
## ⚠ 旧版是手写的 3 条 TOWER_FLOORS 常量，已改成生成式；层号 1~3 与旧版一致，
##   老存档的 tower_progress（按层号存）继续有效。
static func get_floors() -> Array:
	var out: Array = []
	var floor_no := 1
	for d in DOMAINS:
		var domain_id := String(d.get("domain_id", ""))
		var domain_name := String(d.get("name", domain_id))
		for b in d.get("boss_ids", []):
			var boss_id := String(b)
			out.append({
				"floor": floor_no,
				"projection_id": "proj_" + boss_id,
				"boss_id": boss_id,
				"boss_name": get_boss_name(boss_id),
				"domain_id": domain_id,
				"unlock_requirement": "在「%s」击败 %s" % [domain_name, get_boss_name(boss_id)],
			})
			floor_no += 1
	return out

# ===== BOSS 招式组 =====
## boss_id → 该 BOSS 会用的招式（结构见条目注释）
## 每一项：
##   form_id     MoveDB.FORMS 里的招式形态 id
##   phase       1 / 2（该招式从哪个阶段开始可用）
##   min_range   触发该招的最小距离（像素，0 表示贴身也能用）
##   max_range   触发该招的最大距离
##   weight      选招权重（相对值，越大越常出）
##
## 「BOSS 的招式 → 玩家可学的功法」是通过 form_id 自动对应的：
##   同一 form_id 在 SkillDB 里能查到对应功法，塔层首杀时发放。
## 因此新增 BOSS 招式时，只需在这里登记 form_id，并确认 SkillDB 有对应功法。
##
## 刀客的招式组：塔首杀时按这份表反查「能学到哪些功法」
## （见 get_boss_skill_ids / roll_floor_reward_skills）
const BOSS_MOVES: Dictionary = {
	## 虎妖（凡界第 1 位）—— 招式由 prototype_boss.gd 驱动（横扫 / 掷石 / 群砂 / 踏地 / 妖丹）。
	## 这里登记的是「它会哪些形态」，用于塔层首杀反查可感悟的功法。
	## 数值口径与刀客一致：BOSS 侧 damage_coeff 只作参考，实际伤害由 prototype_boss 自己的参数给。
	"boss_huyao": [
		{"form_id": "form_slash_single", "phase": 1, "min_range": 0.0,   "max_range": 130.0, "weight": 3.0},
		{"form_id": "form_smash",        "phase": 1, "min_range": 0.0,   "max_range": 150.0, "weight": 1.6},
		{"form_id": "form_arrow",        "phase": 1, "min_range": 120.0, "max_range": 420.0, "weight": 2.2},
		{"form_id": "form_element_orb",  "phase": 1, "min_range": 150.0, "max_range": 480.0, "weight": 1.5},
		{"form_id": "form_arrow_volley", "phase": 2, "min_range": 140.0, "max_range": 460.0, "weight": 1.2},
	],
	"boss_01": [
		{"form_id": "form_blade_slash",   "phase": 1, "min_range": 0.0,   "max_range": 190.0, "weight": 3.0},
		{"form_id": "form_blade_heavy",   "phase": 1, "min_range": 0.0,   "max_range": 190.0, "weight": 2.0},
		{"form_id": "form_blade_dash",    "phase": 1, "min_range": 140.0, "max_range": 430.0, "weight": 2.0},
		{"form_id": "form_blade_turn",    "phase": 1, "min_range": 0.0,   "max_range": 210.0, "weight": 2.2},
		{"form_id": "form_blade_scar",    "phase": 1, "min_range": 120.0, "max_range": 330.0, "weight": 2.0},
		{"form_id": "form_blade_qi",      "phase": 1, "min_range": 170.0, "max_range": 560.0, "weight": 2.0},
		{"form_id": "form_blade_field",   "phase": 1, "min_range": 0.0,   "max_range": 210.0, "weight": 1.5},
		{"form_id": "form_blade_counter", "phase": 1, "min_range": 0.0   , "max_range": 175.0, "weight": 1.5},
		{"form_id": "form_blade_peak",    "phase": 1, "min_range": 150.0, "max_range": 620.0, "weight": 1.0},
	],

	## 剑客（凡界第 3 位）—— 剑意蓄压体系（domain_boss_01_c.gd 驱动）
	##   - 剑意上限 5：释放 +1、命中再 +1（二阶段翻倍）；BOSS 每被打 5 次 -1
	##   - 万剑归宗 = 2 + 剑意×2 把飞剑，CD 15s，放完清空剑意（一阶段专属）
	##   - 一剑开天 = 二阶段解锁，消耗全部剑意，每层 +18 射程；满层变法术且范围巨大
	##   - form_sword_heaven_full / form_sword_triangle 是 BOSS 专属演出，不登记
	##   ⚠ 穿（form_sword_pierce）在这里登记 **weight = 0**：它不参与评分选招
	##     （由「连续两次远程后强制触发」的机制驱动），登记只是为了
	##     ① 塔层首杀能反查出这门功法；② 表明 BOSS 会用它。
	## 定阵先生（冲和界第 2 位）—— 阵旗 · 连线
	##   布点：插旗；用线：引阵 / 卷阵 / 封阵；不依赖旗：扫阵 / 踏阵 / 垒旗 / 解阵
	## ⚠ 插旗 weight 高但不参与"伤害评分"，由 domain_boss_02_b 的旗数逻辑优先驱动
	"boss_02_b": [
		{"form_id": "form_array_plant", "phase": 1, "min_range": 0.0,   "max_range": 640.0, "weight": 0.0},
		{"form_id": "form_array_line",  "phase": 1, "min_range": 0.0,   "max_range": 640.0, "weight": 2.2},
		{"form_id": "form_array_pull",  "phase": 1, "min_range": 100.0, "max_range": 460.0, "weight": 1.8},
		{"form_id": "form_array_seal",  "phase": 1, "min_range": 0.0,   "max_range": 520.0, "weight": 1.2},
		{"form_id": "form_array_sweep", "phase": 1, "min_range": 0.0,   "max_range": 200.0, "weight": 3.0},
		{"form_id": "form_array_step",  "phase": 1, "min_range": 120.0, "max_range": 620.0, "weight": 2.0},
		{"form_id": "form_array_pile",  "phase": 1, "min_range": 0.0,   "max_range": 150.0, "weight": 2.2},
		{"form_id": "form_array_burst", "phase": 2, "min_range": 0.0,   "max_range": 640.0, "weight": 2.0},
	],

	"boss_01_c": [
		{"form_id": "form_sword_stab",   "phase": 1, "min_range": 60.0,  "max_range": 240.0, "weight": 3.0},
		{"form_id": "form_sword_lift",   "phase": 1, "min_range": 0.0,   "max_range": 180.0, "weight": 2.4},
		{"form_id": "form_sword_chop",   "phase": 1, "min_range": 0.0,   "max_range": 130.0, "weight": 2.0},
		{"form_id": "form_sword_cloud",  "phase": 1, "min_range": 200.0, "max_range": 520.0, "weight": 2.4},
		{"form_id": "form_sword_pierce", "phase": 1, "min_range": 0.0,   "max_range": 400.0, "weight": 0.0},
		{"form_id": "form_sword_myriad", "phase": 1, "min_range": 0.0,   "max_range": 620.0, "weight": 1.6},
		{"form_id": "form_sword_heaven", "phase": 2, "min_range": 0.0,   "max_range": 460.0, "weight": 2.6},
	],

	## 两仪真人（位面 02 第 1 位）—— 两仪护体 / 阴阳易位
	## 八式全部在 SkillDB 有对应功法，塔第 4 层首通从这 8 门里感悟。
	## 两仪转 weight = 0：它由「护体低于 35% / 玩家连续同属性」条件驱动，
	##   不参与常规评分（与剑客的「穿」同一套登记口径）。
	## 太虚气君（冲和界第 3 位）—— 气环 · 化劲
	##   聚环 / 裂空 / 回旋 / 缚脉 / 化劲 / 缩地 / 气爆 / 吐纳
	"boss_02_c": [
		{"form_id": "form_qi_gather", "phase": 1, "min_range": 0.0,   "max_range": 640.0, "weight": 0.0},
		{"form_id": "form_qi_wave",   "phase": 1, "min_range": 120.0, "max_range": 620.0, "weight": 2.6},
		{"form_id": "form_qi_spin",   "phase": 1, "min_range": 0.0,   "max_range": 190.0, "weight": 3.0},
		{"form_id": "form_qi_lock",   "phase": 1, "min_range": 0.0,   "max_range": 240.0, "weight": 2.2},
		{"form_id": "form_qi_ward",   "phase": 1, "min_range": 0.0,   "max_range": 640.0, "weight": 0.0},
		{"form_id": "form_qi_step",   "phase": 1, "min_range": 140.0, "max_range": 620.0, "weight": 2.0},
		{"form_id": "form_qi_burst",  "phase": 2, "min_range": 0.0,   "max_range": 420.0, "weight": 2.4},
		{"form_id": "form_qi_breath", "phase": 1, "min_range": 0.0,   "max_range": 640.0, "weight": 0.0},
	],

	## 赫连霄（赤霄界第 1 位）—— 判词 · 天律
	##   判词 / 定刑 / 雷鼓 / 锁雷 / 雷遁 / 聚雷 / 九霄 / 雷牢（二阶段）
	## ⚠ 聚雷 weight = 0：由「残血 / 雷势低」条件驱动，不参与常规评分；
	##   判词 weight 只作登记，实际由 domain_boss_03 的「无判词 + 冷却好」驱动。
	"boss_03": [
		{"form_id": "form_thunder_verdict", "phase": 1, "min_range": 0.0,   "max_range": 380.0, "weight": 2.4},
		{"form_id": "form_thunder_execute", "phase": 1, "min_range": 120.0, "max_range": 460.0, "weight": 2.6},
		{"form_id": "form_thunder_drum",    "phase": 1, "min_range": 0.0,   "max_range": 210.0, "weight": 3.0},
		{"form_id": "form_thunder_lock",    "phase": 1, "min_range": 80.0,  "max_range": 340.0, "weight": 2.2},
		{"form_id": "form_thunder_step",    "phase": 1, "min_range": 200.0, "max_range": 520.0, "weight": 2.4},
		{"form_id": "form_thunder_gather",  "phase": 1, "min_range": 0.0,   "max_range": 640.0, "weight": 0.0},
		{"form_id": "form_thunder_nine",    "phase": 1, "min_range": 0.0,   "max_range": 520.0, "weight": 1.8},
		{"form_id": "form_thunder_prison",  "phase": 2, "min_range": 0.0,   "max_range": 520.0, "weight": 2.0},
	],

	## 离照（赤霄界第 2 位）—— 逐日 · 天火
	##   逐日步 / 日冕斩 / 投日 / 牵日 / 焚风 / 日蚀 / 日轮 / 天火坠（二阶段）
	## ⚠ 权重只作登记：实际出招由 domain_boss_03_b 按「火种在谁手里」驱动。
	"boss_03_b": [
		{"form_id": "form_sun_step",    "phase": 1, "min_range": 0.0,   "max_range": 380.0, "weight": 2.6},
		{"form_id": "form_sun_slash",   "phase": 1, "min_range": 0.0,   "max_range": 230.0, "weight": 3.0},
		{"form_id": "form_sun_throw",   "phase": 1, "min_range": 120.0, "max_range": 520.0, "weight": 2.2},
		{"form_id": "form_sun_pull",    "phase": 1, "min_range": 160.0, "max_range": 440.0, "weight": 2.4},
		{"form_id": "form_sun_wind",    "phase": 1, "min_range": 0.0,   "max_range": 260.0, "weight": 2.6},
		{"form_id": "form_sun_eclipse", "phase": 1, "min_range": 80.0,  "max_range": 460.0, "weight": 2.0},
		{"form_id": "form_sun_wheel",   "phase": 1, "min_range": 140.0, "max_range": 480.0, "weight": 1.8},
		{"form_id": "form_sun_meteor",  "phase": 2, "min_range": 0.0,   "max_range": 520.0, "weight": 2.2},
	],

	## 晏无咎（赤霄界第 3 位）—— 三灾轮转
	## 权重只作登记：实际按当前灾位 / 玩家灾位 / 灾势由 domain_boss_03_c 驱动。
	"boss_03_c": [
		{"form_id": "form_calamity_step",          "phase": 1, "min_range": 0.0,   "max_range": 420.0, "weight": 2.6},
		{"form_id": "form_calamity_slash",         "phase": 1, "min_range": 0.0,   "max_range": 240.0, "weight": 3.0},
		{"form_id": "form_calamity_fire_seal",     "phase": 1, "min_range": 100.0, "max_range": 460.0, "weight": 2.4},
		{"form_id": "form_calamity_fire_field",    "phase": 1, "min_range": 80.0,  "max_range": 460.0, "weight": 2.2},
		{"form_id": "form_calamity_thunder_strike", "phase": 1, "min_range": 100.0, "max_range": 520.0, "weight": 2.6},
		{"form_id": "form_calamity_thunder_pool",  "phase": 1, "min_range": 0.0,   "max_range": 460.0, "weight": 2.2},
		{"form_id": "form_calamity_turn",          "phase": 1, "min_range": 0.0,   "max_range": 520.0, "weight": 0.0},
		{"form_id": "form_calamity_final",         "phase": 1, "min_range": 0.0,   "max_range": 520.0, "weight": 1.2},
		{"form_id": "form_calamity_final",         "phase": 2, "min_range": 0.0,   "max_range": 520.0, "weight": 2.2},
	],

	## 观澜（照影界第 1 位）—— 镜身 · 照影
	## 权重只作登记；实际由 domain_boss_04 按镜像数量 / 距离 / 冷却 / 玩家位置选招。
	"boss_04": [
		{"form_id": "form_mirror_slash",   "phase": 1, "min_range": 0.0,   "max_range": 210.0, "weight": 3.0},
		{"form_id": "form_mirror_thrust",  "phase": 1, "min_range": 120.0, "max_range": 360.0, "weight": 2.4},
		{"form_id": "form_mirror_bloom",   "phase": 1, "min_range": 0.0,   "max_range": 520.0, "weight": 1.6},
		{"form_id": "form_mirror_shatter", "phase": 1, "min_range": 0.0,   "max_range": 340.0, "weight": 2.0},
		{"form_id": "form_mirror_swap",    "phase": 1, "min_range": 0.0,   "max_range": 520.0, "weight": 1.2},
		{"form_id": "form_mirror_return",  "phase": 1, "min_range": 0.0,   "max_range": 180.0, "weight": 1.4},
		{"form_id": "form_mirror_ring",    "phase": 1, "min_range": 0.0,   "max_range": 260.0, "weight": 1.8},
		{"form_id": "form_mirror_myriad",  "phase": 2, "min_range": 0.0,   "max_range": 520.0, "weight": 2.4},
	],

	## 执烛（照影界第 2 位）—— 投影 · 身外之影
	## 权重只作登记；实际选招由 domain_boss_04_b 按**真实影身走廊**能不能命中来门禁
	## （投晷 / 缚影 的射程恒等于当前影长，影不够长就不会出招 —— 不许空放写进几何里）。
	"boss_04_b": [
		{"form_id": "form_shadow_cut",        "phase": 1, "min_range": 0.0,   "max_range": 170.0, "weight": 3.0},
		{"form_id": "form_shadow_reach",      "phase": 1, "min_range": 120.0, "max_range": 640.0, "weight": 2.6},
		{"form_id": "form_shadow_bind",       "phase": 1, "min_range": 140.0, "max_range": 620.0, "weight": 1.8},
		{"form_id": "form_shadow_step",       "phase": 1, "min_range": 0.0,   "max_range": 640.0, "weight": 1.6},
		{"form_id": "form_shadow_dim",        "phase": 1, "min_range": 0.0,   "max_range": 520.0, "weight": 1.0},
		{"form_id": "form_shadow_beam",       "phase": 1, "min_range": 150.0, "max_range": 600.0, "weight": 2.2},
		{"form_id": "form_shadow_split",      "phase": 1, "min_range": 0.0,   "max_range": 560.0, "weight": 1.2},
		{"form_id": "form_shadow_longnight",  "phase": 2, "min_range": 0.0,   "max_range": 640.0, "weight": 2.2},
	],

	## 叠纸（照影界第 3 位）—— 空间连通 · 折影为径
	## 同样「权重只作登记」：实际选招由 domain_boss_04_c 按**真实折痕几何**门禁
	## （押痕要求你离痕够远、双屏要求你在痕的射程带内、碎痕要求痕还没作废 —— 不许空放写进几何里）。
	"boss_04_c": [
		{"form_id": "form_fold_press",     "phase": 1, "min_range": 0.0,   "max_range": 340.0, "weight": 3.0},
		{"form_id": "form_fold_trace",     "phase": 1, "min_range": 0.0,   "max_range": 520.0, "weight": 2.4},
		{"form_id": "form_fold_stride",    "phase": 1, "min_range": 120.0, "max_range": 620.0, "weight": 1.9},
		{"form_id": "form_fold_pressmark", "phase": 1, "min_range": 300.0, "max_range": 700.0, "weight": 2.6},
		{"form_id": "form_fold_shroud",    "phase": 1, "min_range": 0.0,   "max_range": 560.0, "weight": 1.0},
		{"form_id": "form_fold_tear",      "phase": 1, "min_range": 150.0, "max_range": 620.0, "weight": 1.7},
		{"form_id": "form_fold_twin",      "phase": 1, "min_range": 200.0, "max_range": 480.0, "weight": 2.2},
		{"form_id": "form_fold_triple",    "phase": 2, "min_range": 0.0,   "max_range": 640.0, "weight": 2.2},
	],

	"boss_02": [
		{"form_id": "form_yinyang_palm",     "phase": 1, "min_range": 0.0,   "max_range": 180.0, "weight": 3.0},
		{"form_id": "form_yinyang_finger",   "phase": 1, "min_range": 120.0, "max_range": 420.0, "weight": 2.2},
		{"form_id": "form_yinyang_triple",   "phase": 1, "min_range": 180.0, "max_range": 560.0, "weight": 2.4},
		{"form_id": "form_yinyang_wind",     "phase": 1, "min_range": 160.0, "max_range": 520.0, "weight": 1.8},
		{"form_id": "form_yinyang_fish",     "phase": 1, "min_range": 140.0, "max_range": 480.0, "weight": 2.2},
		{"form_id": "form_yinyang_counter",  "phase": 1, "min_range": 0.0,   "max_range": 200.0, "weight": 1.2},
		{"form_id": "form_yinyang_flip",     "phase": 1, "min_range": 0.0,   "max_range": 520.0, "weight": 0.0},
		{"form_id": "form_yinyang_collapse", "phase": 2, "min_range": 0.0,   "max_range": 320.0, "weight": 2.0},
	],
}

# ===== BOSS 名（用于展示）=====
## 每个位面 3 名 BOSS：第 1 名沿用原 id，第 2/3 名用 _b / _c 后缀
## ⚠ 除刀客外都是占位名，正式设计定稿后只改这张表即可
const BOSS_NAMES := {
	"boss_huyao": "虎妖",
	"boss_01": "刀客",
	"boss_01_c": "剑客",
	"boss_02": "两仪真人",
	"boss_02_b": "定阵先生",
	"boss_02_c": "太虚气君",
	## 大世界核心首领（不属任何位面关卡，图鉴单独收录）
	"world_core_lianqi": "青岚古猿",
	"world_core_zhuji": "云隐苍角",
	"world_core_jiedan": "赤金火麟",
	"world_core_shihou": "镇墟石犼",
	"boss_03": "赫连霄",
	"boss_03_b": "离照",
	"boss_03_c": "晏无咎",
	"boss_04": "观澜",
	"boss_04_b": "执烛",
	"boss_04_c": "叠纸",
}

# ===== BOSS 战斗场景映射（数据驱动）=====
## 制作好新 BOSS 后只需在这里登记一行，战斗场景会自动加载对应模型。
## 未登记的 boss_id 回退到原型 BOSS（演武场、尚未制作的关卡都走这条）。
const BOSS_SCENES := {
	# 虎妖就是演武场那只，用同一个场景（prototype_boss.gd 驱动）
	"boss_huyao": "res://scenes/boss/boss.tscn",
	"boss_01": "res://scenes/boss/domain_boss_01.tscn",
	"boss_01_c": "res://scenes/boss/domain_boss_01_c.tscn",
	"boss_02": "res://scenes/boss/domain_boss_02.tscn",
	"boss_02_b": "res://scenes/boss/domain_boss_02_b.tscn",
	"boss_02_c": "res://scenes/boss/domain_boss_02_c.tscn",
	"world_core_zhuji": "res://scenes/world/zhuji_core_stag.tscn",
	"world_core_jiedan": "res://scenes/world/jiedan_core_qilin.tscn",
	"boss_03": "res://scenes/boss/domain_boss_03.tscn",
	"boss_03_b": "res://scenes/boss/domain_boss_03_b.tscn",
	"boss_03_c": "res://scenes/boss/domain_boss_03_c.tscn",
	"boss_04": "res://scenes/boss/domain_boss_04.tscn",
	"boss_04_b": "res://scenes/boss/domain_boss_04_b.tscn",
	"boss_04_c": "res://scenes/boss/domain_boss_04_c.tscn",
}

const DEFAULT_BOSS_SCENE := "res://scenes/boss/boss.tscn"

# ===== 记忆碎片 =====
## memory_type 为碎片类别；unlock_requirement 为解锁条件描述
const MEMORY_FRAGMENTS: Array = [
	{
		"memory_fragment_id": "mem_001",
		"memory_type": "挚友",
		"title": "少年相约",
		"unlock_requirement": "通关凡界",
		"source": "domain_01",
		"is_unlocked": false,
		"playback_state": "未回放",
		"story_progress_requirement": 1,
		"desc": "两个少年在山门前立誓，要一起走到修行的尽头。",
	},
	{
		"memory_fragment_id": "mem_002",
		"memory_type": "守戒",
		"title": "世代之约",
		"unlock_requirement": "通关位面 02",
		"source": "domain_02",
		"is_unlocked": false,
		"playback_state": "未回放",
		"story_progress_requirement": 2,
		"desc": "挚友家族世代守护时空至宝，代代以血铭记。",
	},
	{
		"memory_fragment_id": "mem_003",
		"memory_type": "背叛",
		"title": "那一剑",
		"unlock_requirement": "通关位面 03",
		"source": "domain_03",
		"is_unlocked": false,
		"playback_state": "未回放",
		"story_progress_requirement": 3,
		"desc": "记忆的尽头，是谁先出的手。",
	},
]


# ===== 查询工具 =====

static func get_domain(domain_id: String) -> Dictionary:
	for d in DOMAINS:
		if String(d.get("domain_id", "")) == domain_id:
			return d
	return {}


static func get_domain_name(domain_id: String) -> String:
	var d := get_domain(domain_id)
	return String(d.get("name", domain_id)) if not d.is_empty() else domain_id


## 按境界找塔位面 id（大世界区域 → 对应位面分支）。
## 例：练气区域 → domain_01（凡界），筑基区域 → domain_02（冲和界）。
static func get_domain_id_for_realm(realm: String) -> String:
	for d in DOMAINS:
		if String(d.get("realm_required", "")) == realm:
			return String(d.get("domain_id", ""))
	return ""


static func get_floor(floor_no: int) -> Dictionary:
	for f in get_floors():
		if int(f.get("floor", 0)) == floor_no:
			return f
	return {}


static func get_floor_by_projection(projection_id: String) -> Dictionary:
	for f in get_floors():
		if String(f.get("projection_id", "")) == projection_id:
			return f
	return {}


static func get_fragment(fragment_id: String) -> Dictionary:
	for m in MEMORY_FRAGMENTS:
		if String(m.get("memory_fragment_id", "")) == fragment_id:
			return m
	return {}


static func get_boss_name(boss_id: String) -> String:
	return String(BOSS_NAMES.get(boss_id, boss_id))


## BOSS 战斗场景路径：登记过就用专属模型，否则回退原型 BOSS
static func get_boss_scene(boss_id: String) -> String:
	var path := String(BOSS_SCENES.get(boss_id, ""))
	return path if path != "" else DEFAULT_BOSS_SCENE


# ===== BOSS 招式 / 塔层奖励功法 =====

## 某 BOSS 的招式列表（未登记返回空数组）
static func get_boss_moves(boss_id: String) -> Array:
	return BOSS_MOVES.get(boss_id, [])


## 某 BOSS 会用的招式形态 id 列表（去重，保持登记顺序）
static func get_boss_form_ids(boss_id: String) -> Array:
	var out: Array = []
	for m in get_boss_moves(boss_id):
		var fid := String(m.get("form_id", ""))
		if fid != "" and fid not in out:
			out.append(fid)
	return out


## 某 BOSS 招式对应的功法 id 列表 —— 即「打通它的塔层能学到的功法」
## 逻辑：招式形态 → SkillDB 反查功法。所以 BOSS 会什么招，就能学到什么功法。
## 被动功法没有招式形态（form_id 为空），反查不到，按 source_boss_id 补进池子里。
static func get_boss_skill_ids(boss_id: String) -> Array:
	var out: Array = []
	for fid in get_boss_form_ids(boss_id):
		var sid := SkillDB.get_skill_id_by_form(String(fid))
		if sid != "" and sid not in out:
			out.append(sid)
	for raw in SkillDB.get_by_type(SkillDB.TYPE_PASSIVE):
		var sk := raw as Dictionary
		if String(sk.get("source_boss_id", "")) != boss_id:
			continue
		var psid := String(sk.get("skill_id", ""))
		if psid != "" and psid not in out:
			out.append(psid)
	return out


## 塔层首杀奖励的功法 id 列表（完整池，不随机）
## 优先取条目里的 reward_skill_ids；否则按该层 BOSS 的招式自动推导
## （兼容更早的单个 reward_skill_id 字段）
static func get_floor_reward_skills(floor_no: int) -> Array:
	var f := get_floor(floor_no)
	if f.is_empty():
		return []
	var explicit: Array = f.get("reward_skill_ids", [])
	if not explicit.is_empty():
		return explicit.duplicate()
	var legacy := String(f.get("reward_skill_id", ""))
	if legacy != "":
		return [legacy]
	var boss_id := String(f.get("boss_id", ""))
	if boss_id == "":
		return []
	return get_boss_skill_ids(boss_id)


# ===== 塔层首杀随机掉落 =====
## 用户确认的概率：
##   - 必掉 1 本
##   - 30% 概率掉 2 本（随机）
##   - 5% 概率一次掉全部功法各一本
## 5% 优先级最高（命中即全给），否则再判断 30%。
const REWARD_ALL_CHANCE := 0.05
const REWARD_TWO_CHANCE := 0.30


## 掷一次本层可感悟的功法，返回本次实际获得的 id 列表（不重复）
##
## exclude：要排除的功法 id（调用方传 `CharacterData.learned_skills`）。
## ⚠ 必须先排除再掷，不能掷完再过滤 —— 否则「5 门里已学 4 门」时，
##   随机掷中的那一门有 80% 概率正好是已学的，过滤后本轮就空手了，
##   玩家会看到「该层功法你已全部掌握」的误导提示（2026-10-17 修的 bug）。
## 返回空数组只有一种情况：排除后真的没有可学的了。
static func roll_floor_reward_skills(floor_no: int, exclude: Array = []) -> Array:
	var pool := get_floor_reward_skills(floor_no)
	if pool.is_empty():
		return []

	# 只从「还没掌握」的门类里掷
	var remaining: Array = []
	for sid in pool:
		if String(sid) in exclude:
			continue
		remaining.append(sid)
	if remaining.is_empty():
		return []

	var roll := randf()
	var count := 1
	if roll < REWARD_ALL_CHANCE:
		count = remaining.size()      # 5%：剩余的全部给
	elif roll < REWARD_ALL_CHANCE + REWARD_TWO_CHANCE:
		count = 2                     # 30%：给 2 门
	count = mini(count, remaining.size())

	var out: Array = []
	for i in range(count):
		var idx := randi() % remaining.size()
		out.append(remaining[idx])
		remaining.remove_at(idx)
	return out


## 判断是否满足进入界域的境界要求（§2.7 前半条）
static func meets_realm_requirement(domain_id: String, current_realm: String) -> bool:
	var d := get_domain(domain_id)
	if d.is_empty():
		return false
	var required := String(d.get("realm_required", ""))
	var req_idx := CharacterData.REALM_ORDER.find(required)
	var cur_idx := CharacterData.REALM_ORDER.find(current_realm)
	return cur_idx >= req_idx and req_idx >= 0
