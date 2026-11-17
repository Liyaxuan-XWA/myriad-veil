class_name RogueDB
extends RefCounted
## 肉鸽爬塔「试炼之路」—— 全部数值与卡池表
##
## 设计案：docs/肉鸽爬塔模式_试炼之路_设计案.md
## 本文件只管「数据」，运行期状态与结算在 rogue_run.gd，波次推进在 rogue_arena.gd。
##
## 铁律（与主模式隔离）：
##   - 本模式**不产出**主模式装备 / 材料 / 功法；唯一产出是锻造晶石。
##   - 所有小怪 / BOSS 都是临时实例，退出即销毁，不写任何永久字段（除层数成绩）。
##
## 美术替换：小怪立绘走 ArtDB.VISUALS 的 rogue_* 条目，缺图自动回退占位色块。
## 卡池文案只写「效果」，数值也写在这里 —— 改数值只改这张表。

# ===== 稀有度 =====
const RARITY_COMMON := "common"
const RARITY_RARE := "rare"
const RARITY_LEGEND := "legend"
const RARITY_NAME: Dictionary = {
	RARITY_COMMON: "普通",
	RARITY_RARE: "稀有",
	RARITY_LEGEND: "传说",
}
## 稀有度配色（青 / 紫 / 金）：与主城「宣纸 + 朱砂」语言共存，不新增色系
const RARITY_COLOR: Dictionary = {
	RARITY_COMMON: Color(0.52, 0.84, 0.78, 1.0),
	RARITY_RARE: Color(0.70, 0.56, 0.95, 1.0),
	RARITY_LEGEND: Color(0.96, 0.78, 0.36, 1.0),
}
## 出现权重（BOSS 关后必出至少 1 张稀有）
const RARITY_WEIGHT: Dictionary = {
	RARITY_COMMON: 60.0,
	RARITY_RARE: 32.0,
	RARITY_LEGEND: 8.0,
}
## 同一张增益最多叠几层（传说另有限制）
const MAX_STACKS := 3
const MAX_STACKS_LEGEND := 1

# ===== 资源上限基值（P0 变量化的统一口径）=====
## 各技能组的层数 / 数量上限。主模式下 RogueRun 不激活，取值恒等于基值。
const CAP_BASE: Dictionary = {
	"sword_intent_max": 5,   # 剑意
	"scar_max": 4,           # 场上刀痕
	"qi_max": 5,             # 气环
	"yinyang_max": 3,        # 阴阳势
	"thunder_max": 3,        # 雷势
	"sun_max": 3,            # 天火种
	"mirror_max": 2,         # 镜像
	"array_max": 5,          # 阵旗
	"calamity_max": 3,       # 灾势
	"talisman_bag": 2,       # 符囊格数（符箓：仓库 + 连携池，不占按键；连携是可选强化）
}
## 资源上限 → 中文名（「本局增益」面板里算「当前累计」用）
## ⚠ 新增 CAP_BASE 条目必须同步登记，否则面板会直接印出 `sun_max` 这种原始 key。
const CAP_NAME: Dictionary = {
	"sword_intent_max": "剑意上限",
	"scar_max": "刀痕上限",
	"qi_max": "气环上限",
	"yinyang_max": "阴阳势上限",
	"thunder_max": "雷势上限",
	"sun_max": "天火种上限",
	"mirror_max": "镜像上限",
	"array_max": "阵旗上限",
	"calamity_max": "灾势上限",
	"talisman_bag": "符囊格数",
}

# ===== 数值曲线 =====
## 小怪：第 1 层基准，每层血量 ×1.30、攻击 ×1.18
const MINION_HP_GROWTH := 1.30
const MINION_ATK_GROWTH := 1.12
## BOSS：第 1 层基准 500 血 / 12 攻，每层血量 ×1.35、攻击 ×1.15
const BOSS_HP_BASE := 500.0
const BOSS_ATK_BASE := 12.0
const BOSS_HP_GROWTH := 1.35
const BOSS_ATK_GROWTH := 1.15
## 按原 BOSS 档位乘系数（凡界 / 筑基 / 结丹 / 元婴）
const BOSS_TIER: Dictionary = {
	"boss_huyao": 1.00, "boss_01": 1.00, "boss_01_c": 1.00,
	"boss_02": 1.15, "boss_02_b": 1.15, "boss_02_c": 1.15,
	"boss_03": 1.30, "boss_03_b": 1.30, "boss_03_c": 1.30,
	"boss_04": 1.45, "boss_04_b": 1.45, "boss_04_c": 1.45,
}
## BOSS 抽取队列：12 只洗牌按层取，抽完再洗；第 1 层固定虎妖教学
const BOSS_POOL: Array[String] = [
	"boss_huyao", "boss_01", "boss_01_c",
	"boss_02", "boss_02_b", "boss_02_c",
	"boss_03", "boss_03_b", "boss_03_c",
	"boss_04", "boss_04_b", "boss_04_c",
]
const BOSS_TUTORIAL := "boss_huyao"
## 每 4 层优先出一只元婴档
const BOSS_TIER_SENIOR_EVERY := 4
const BOSS_SENIOR_IDS: Array[String] = ["boss_04", "boss_04_b", "boss_04_c"]

## 每层 = 3 小关 + 1 BOSS 关；每小关 3 波
const STAGES_PER_FLOOR := 4
const WAVES_PER_STAGE := 3
## 波次之间的喘息时间（秒）
const WAVE_BREAK := 2.0
## 关间补给（2026-11-08 平衡）：裸装练气只有 100 血，一层 9 波零回血必死。
## 每清一小关回 STAGE_HEAL_PCT%，进 BOSS 关再回 BOSS_STAGE_HEAL_PCT%。
## ⚠ 走 player.rogue_heal_pct()（自带 RogueRun.active 门禁 + HUD 刷新），别自己写 hp +=。
const STAGE_HEAL_PCT := 20.0
const BOSS_STAGE_HEAL_PCT := 30.0
## 前几层教学缓冲（2026-11-08 用户报「还没碰到第 1 层 BOSS 就死了」）。
## 索引 = floor_no-1；第 4 层起 1.0，后期数值与原来完全一致，不影响深爬目标。
## ⚠ 攻击缓冲比血量更狠：它直接决定玩家每波挨多少下、能不能活到 BOSS。
const FLOOR_HP_RELIEF: Array[float] = [0.60, 0.80, 0.92, 1.0]
const FLOOR_ATK_RELIEF: Array[float] = [0.45, 0.62, 0.82, 1.0]
## 首层 BOSS 也留一口：满血走到 BOSS 却被两下拍死，教学层就白做了。
## 第 3 层起归 1.0，BOSS 后期曲线不变。
const FLOOR_BOSS_RELIEF: Array[float] = [0.75, 0.90, 1.0, 1.0]
## 每波出怪数（逐层渐进）：第 1 层 1/2/2、第 2 层 2/2/2、第 3 层 2/2/3、
## 第 4 层起 2/3/3。⚠ 别让「怪数增加 + 缓冲回升 + 新怪种解锁」同时压在同一层，
##   那样第 1→3 层会出现 3× 断崖（probe_rogue_balance 首轮实测 3.16× / 2.54×）。
const WAVE_COUNTS: Array = [[1, 2, 2], [2, 2, 2], [2, 2, 3], [2, 3, 3]]
## 通用池传说档（不灭 / 洗髓）解锁层：到达该层起才进池（设计案 §9.2）。
## ⚠ 只作用于通用池传说，各流派自己的传说卡 / 通用池普通·稀有都不受限。
const GENERIC_LEGEND_FLOOR := 10
## 局内成长：BOSS 装备 + 修为突破（2026-11-08 用户定）
## ⚠ 这两套状态全部只在 RogueRun 里，绝不写 CharacterData 的装备槽 / 境界字段，
##   出局 restore() 整组清空。属性走独立 source rogue_gear / rogue_realm
##   （🚫 不能并进 "rogue"，rebuild() 会整组重写）。
## 击杀修为：小怪 / 精英 / BOSS 各一档，随层小幅成长，保证一层内能突破 1~2 次
const MINION_EXP_BASE := 12.0
const ELITE_EXP_MULT := 2.5
const BOSS_EXP_BASE := 60.0
const EXP_FLOOR_GROWTH := 0.15
## 局内小阶段阈值（远低于局外的 STAGE_EXP_BASE，练气前期 100 → 中期 135 → 后期 170）
const TRIAL_STAGE_EXP_BASE := 100
const TRIAL_STAGE_EXP_STEP := 35

## 试炼局内回血丹（2026-11-08）：击杀小怪概率掉落，走近按 F 拾取**即回血**。
## ⚠ 这是「局内虚拟物品」：id / type 都不在 ItemDB 主表里，拾取走 item_pickup 的
##   pickup_handler 直接调 player.rogue_heal_pct()，不进背包、不写图鉴、不落存档
##   —— 天然带不出局外，也不需要局内背包容器或新键位。
## ⚠ 换美术只改 HEAL_PILL_ICON（128² 透明底小丹丸，缺图自动回退品阶色块）；
##   落地尺寸 / 光柱 / 提示参数在 ArtDB.ROGUE_HEAL_PICKUP_STYLE。
const MINION_HEAL_DROP_CHANCE := 0.18
const HEAL_PILL_PCT := 15.0
const HEAL_PILL_ID := "rogue_heal_pill"
const HEAL_PILL_NAME := "试炼回血丹"
const HEAL_PILL_ICON := "res://assets/ui/icon/rogue_heal_pill.png"
## 地上同时最多几颗，防止一路不捡越堆越多
const MAX_GROUND_HEAL_PILLS := 5
## 小丹丸图标只有 30px，装备级 42px 判定圈看着「站在旁边」却够不着 →
## 回血丹单独放宽到 56px。⚠ 实例化时必须 duplicate() shape，
## 否则改的是共享 SubResource，会把主模式所有掉落物的判定圈一起改掉。
const HEAL_PILL_PICKUP_RADIUS := 56.0
## 试炼之路入口前置（2026-11-08 用户定）：通关万界秘境·凡界的虎妖后才开放。
## 口径与万界塔层解锁一致（CharacterData.is_boss_cleared），domain_progress 已进存档。
const TRIAL_UNLOCK_DOMAIN := "domain_01"
const TRIAL_UNLOCK_BOSS := "boss_huyao"
const TRIAL_UNLOCK_HINT := "通关万界秘境·凡界的虎妖后开放"

## ⚠ 本模式先上线、门禁后补：已有肉鸽进度（rogue_runs / rogue_best_floor）的老档
##   直接视为已解锁，不能把已经玩过的玩家反锁在门外。新档才需要打虎妖。
static func trial_unlocked() -> bool:
	if CharacterData.is_boss_cleared(TRIAL_UNLOCK_DOMAIN, TRIAL_UNLOCK_BOSS):
		return true
	return CharacterData.rogue_runs > 0 or CharacterData.rogue_best_floor > 0

## 击败 BOSS 必掉「该 BOSS 的装备之一」：从 DROP_TEMPLATES 的装备条目里等概率取一件。
## ⚠ 不走 roll_boss_drops()（那是按掉率摇全部、还会带材料与图鉴），这里只给 1 件装备。
## 占位 BOSS 没登记装备时，从全部装备模板兜底，保证「必掉一件」不落空。
static func roll_boss_gear(boss_id: String) -> Dictionary:
	var pool: Array = []
	for raw in ItemDB.get_drops_for_boss(boss_id):
		var e: Dictionary = raw
		if String(e.get("kind", "equipment")) != "equipment":
			continue
		var tpl := ItemDB.get_equipment_template(String(e.get("item_id", "")))
		if not tpl.is_empty():
			pool.append(tpl)
	if pool.is_empty():
		# 兜底池排除开发者武器（房主神器）：它只能从 F2 调试面板获取
		var fallback: Array = []
		for raw in ItemDB.EQUIPMENT_TEMPLATES:
			if not bool((raw as Dictionary).get("dev_only", false)):
				fallback.append(raw)
		pool = fallback
	if pool.is_empty():
		return {}
	return CharacterData.make_equipment_instance(pool[randi() % pool.size()])


static func exp_for_minion(floor_no: int, elite: bool = false) -> float:
	var base := MINION_EXP_BASE * (1.0 + EXP_FLOOR_GROWTH * float(maxi(1, floor_no) - 1))
	return base * (ELITE_EXP_MULT if elite else 1.0)


static func exp_for_boss(floor_no: int) -> float:
	return BOSS_EXP_BASE * (1.0 + EXP_FLOOR_GROWTH * float(maxi(1, floor_no) - 1))


## 每局复活次数
const REVIVE_PER_RUN := 1
## 虎煞（兽潮流）默认层数上限：击杀叠层，无增益卡时根本不产生
const HUNT_BASE_CAP := 8
## 结算奖励（2026-11-11 用户定）：每通关 1 关（小怪关或 BOSS 关）+1；
## 每过 1 层（打完层 BOSS 进入下一层）额外 +2。进入就退出 = 0，没有保底。
const CRYSTALS_PER_STAGE := 1
const CRYSTALS_PER_FLOOR_BONUS := 2
const CRYSTAL_ID := "mat_duanzaojingshi"

# ===== 小怪表 =====
## kind 对应 WorldEnemy 的敌人种类：beast（近战）/ cultivator（远程）
## 数值为「第 1 层基准」，实际生成时按层数乘成长，见 hp_for() / atk_for()
const MINIONS: Dictionary = {
	"rogue_rat": {
		"name": "噬灵鼠", "kind": "beast", "visual_id": "rogue_rat",
		"hp": 80.0, "atk": 8.0, "speed": 150.0,
		"melee_range": 72.0, "melee_angle": 70.0, "melee_coeff": 0.9,
		"body_radius": 20.0, "attack_name": "扑咬",
		"scale": 0.85,
	},
	"rogue_archer": {
		"name": "山魈射手", "kind": "cultivator", "visual_id": "rogue_archer",
		"hp": 60.0, "atk": 6.0, "speed": 90.0,
		"melee_range": 64.0, "melee_angle": 90.0, "melee_coeff": 0.6,
		"body_radius": 18.0, "attack_name": "射石",
		"skills": ["skill_tiger_rock"], "cast_coeff": 0.8,
		"scale": 1.0,
	},
	"rogue_golem": {
		"name": "石傀", "kind": "beast", "visual_id": "rogue_golem",
		"hp": 160.0, "atk": 12.0, "speed": 60.0,
		"melee_range": 92.0, "melee_angle": 360.0, "melee_coeff": 1.3,
		"body_radius": 30.0, "attack_name": "砸地",
		"scale": 1.0,
	},
	"rogue_elite": {
		"name": "赤目虎魈", "kind": "beast", "visual_id": "rogue_elite",
		"hp": 420.0, "atk": 16.0, "speed": 110.0,
		"melee_range": 100.0, "melee_angle": 110.0, "melee_coeff": 1.1,
		"body_radius": 34.0, "attack_name": "裂喉",
		"scale": 1.35,
	},
}
## 出怪解锁：第 1~3 层只出鼠 / 射手，第 4 层起加入石傀
const MINIONS_EARLY: Array[String] = ["rogue_rat", "rogue_archer"]
const MINIONS_MID: Array[String] = ["rogue_rat", "rogue_archer", "rogue_golem"]
const ELITE_FROM_FLOOR := 3

## 试炼小怪的默认血条 / 名字配色。
## 本模式场上的单位**全是敌人**，所以不走大世界那套「野修蓝 / 核心橙」的分色：
## 山魈射手借用了修士 AI（远程风筝），按 kind 上色就会得到一条蓝血条，
## 玩家第一反应是「这是友军？」（2026-11-08 用户报）。条目里可单独覆盖。
const MINION_HP_COLOR := Color(0.90, 0.22, 0.20, 1.0)
const MINION_NAME_COLOR := Color(0.80, 0.70, 0.62, 1.0)

# ===== 起始功法（按流派）=====
## 本模式从零开始：开局只带「本局所选流派」的基础四式（+ 被动），装进 4 个主动槽。
## ⚠ 一张增益卡只对本流派的招式有意义（刀修卡对剑修是死卡），所以卡池按本局流派过滤，
##   见 RogueRun.roll_choices()。加新流派时这里必须一起登记，否则开局是空手。
## 剑修 4 槽：刺 / 斩 / 万剑归宗 / 一剑开天；被动：剑心通明
## 刀修 4 槽：留痕斩 / 刀气追击 / 封路刀域 / 纳势反击；无被动（刀修本就没有被动功法）
const FAMILY_START: Dictionary = {
	"sword": {
		"active": ["skill_sword_stab", "skill_sword_chop",
			"skill_sword_myriad", "skill_sword_heaven"],
		"passive": ["skill_sword_intent"],
		"learned": ["skill_sword_stab", "skill_sword_chop", "skill_sword_myriad",
			"skill_sword_heaven", "skill_sword_intent"],
	},
	"scar": {
		"active": ["skill_blade_scar", "skill_blade_qi",
			"skill_blade_field", "skill_blade_counter"],
		"passive": [],
		"learned": ["skill_blade_scar", "skill_blade_qi", "skill_blade_field",
			"skill_blade_counter", "skill_blade_peak"],
	},
	## 虎妖：四式取自 BOSS 本体，无被动、无流派资源，纯冷却。
	## 装 爪（近战）/ 群砂（弹幕）/ 踏地（重击）/ 妖丹（法术）—— 物理三式 + 法术一式，
	## 这样「凝气 / 长息 / 通脉 / 引灵」这些通用灵力卡也有实感，不会变成废卡。
	## 碎岩飞砂（单发远程）只进 learned：4 槽放不下五式，留作以后的「局内换招」素材。
	"beast": {
		"active": ["skill_tiger_claw", "skill_tiger_sandstorm",
			"skill_tiger_stomp", "skill_tiger_orb"],
		"passive": [],
		"learned": ["skill_tiger_claw", "skill_tiger_rock", "skill_tiger_sandstorm",
			"skill_tiger_stomp", "skill_tiger_orb"],
	},
	## 两仪：阳/阴各一门起手，配两仪转（免费、只翻面）与太极崩（清势处决）。
	## 被动「负阴抱阳」是势条本体 —— 不戴它，两仪势整套不激活，卡池会变死卡。
	"yinyang": {
		"active": ["skill_yinyang_palm", "skill_yinyang_finger",
			"skill_yinyang_flip", "skill_yinyang_collapse"],
		"passive": ["skill_yinyang_harmony"],
		"learned": ["skill_yinyang_palm", "skill_yinyang_finger", "skill_yinyang_flip",
			"skill_yinyang_collapse", "skill_yinyang_harmony",
			"skill_yinyang_triple", "skill_yinyang_wind", "skill_yinyang_fish",
			"skill_yinyang_counter"],
	},
	## 阵旗：插旗 / 引阵 / 扫阵 / 雷落。没有被动，阵区由「五旗成阵」自动激活。
	"array": {
		"active": ["skill_array_plant", "skill_array_line",
			"skill_array_sweep", "skill_array_burst"],
		"passive": [],
		"learned": ["skill_array_plant", "skill_array_line", "skill_array_sweep",
			"skill_array_burst", "skill_array_pull", "skill_array_seal",
			"skill_array_step", "skill_array_pile"],
	},
	## 气环：聚环 / 冲气 / 回旋 / 气爆 + 被动「气环·回息」（环身吸血）
	"qi": {
		"active": ["skill_qi_gather", "skill_qi_wave",
			"skill_qi_spin", "skill_qi_burst"],
		"passive": ["skill_qi_ring_heal"],
		"learned": ["skill_qi_gather", "skill_qi_wave", "skill_qi_spin",
			"skill_qi_burst", "skill_qi_ring_heal", "skill_qi_lock",
			"skill_qi_ward", "skill_qi_step", "skill_qi_breath"],
	},
	## 判词雷：天律 / 雷殛 / 雷鼓 / 九霄 + 被动「雷积·震魂」（耗势减 CD）
	"thunder": {
		"active": ["skill_thunder_verdict", "skill_thunder_execute",
			"skill_thunder_drum", "skill_thunder_nine"],
		"passive": ["skill_thunder_accum"],
		"learned": ["skill_thunder_verdict", "skill_thunder_execute", "skill_thunder_drum",
			"skill_thunder_nine", "skill_thunder_accum", "skill_thunder_lock",
			"skill_thunder_step", "skill_thunder_gather", "skill_thunder_prison"],
	},
	## 逐日：逐日步 / 日冕斩 / 投日 / 焚风 + 被动「盗火者」（持种）
	"sun": {
		"active": ["skill_sun_step", "skill_sun_slash", "skill_sun_throw", "skill_sun_wind"],
		"passive": ["skill_sun_wheel"],
		"learned": ["skill_sun_step", "skill_sun_slash", "skill_sun_throw", "skill_sun_wind",
			"skill_sun_wheel", "skill_sun_pull", "skill_sun_eclipse", "skill_sun_meteor"],
	},
	## 三灾：风 / 火 / 雷各一门 + 三灾轮转 + 被动「三灾·灾身」
	"calamity": {
		"active": ["skill_calamity_slash", "skill_calamity_fire_seal",
			"skill_calamity_thunder_strike", "skill_calamity_turn"],
		"passive": ["skill_calamity_body"],
		"learned": ["skill_calamity_slash", "skill_calamity_fire_seal",
			"skill_calamity_thunder_strike", "skill_calamity_turn", "skill_calamity_body",
			"skill_calamity_step", "skill_calamity_fire_field",
			"skill_calamity_thunder_pool", "skill_calamity_final"],
	},
	## 镜身：镜水斩 / 照影刺 / 碎镜 / 万镜 + 被动「照影」（镜像复读）
	"mirror": {
		"active": ["skill_mirror_slash", "skill_mirror_thrust",
			"skill_mirror_shatter", "skill_mirror_myriad"],
		"passive": ["skill_mirror_echo"],
		"learned": ["skill_mirror_slash", "skill_mirror_thrust", "skill_mirror_shatter",
			"skill_mirror_myriad", "skill_mirror_echo", "skill_mirror_bloom",
			"skill_mirror_swap", "skill_mirror_return", "skill_mirror_ring"],
	},
	## 投影：削影 / 投晷 / 明灭 / 长夜 + 被动「执灯」（灯笼影长）
	"shadow": {
		"active": ["skill_shadow_cut", "skill_shadow_reach",
			"skill_shadow_dim", "skill_shadow_longnight"],
		"passive": ["skill_shadow_lamp"],
		"learned": ["skill_shadow_cut", "skill_shadow_reach", "skill_shadow_dim",
			"skill_shadow_longnight", "skill_shadow_lamp", "skill_shadow_bind",
			"skill_shadow_step", "skill_shadow_beam", "skill_shadow_split"],
	},
	## 折影：按纸 / 循痕 / 跨缝 / 裁痕 + 被动「量折」。
	## ⚠ 裁痕必须进出战槽：折痕是这一族的判定本体，没有个人折痕等于整套机制空转
	"fold": {
		"active": ["skill_fold_press", "skill_fold_trace",
			"skill_fold_stride", "skill_fold_seam"],
		"passive": ["skill_fold_measure"],
		"learned": ["skill_fold_press", "skill_fold_trace", "skill_fold_stride",
			"skill_fold_seam", "skill_fold_measure", "skill_fold_tear",
			"skill_fold_shroud", "skill_fold_twin", "skill_fold_triple"],
	},
	## 符箓：2026-11-10 重做 —— 开局不再发固定五式，由「结符页」从七张元素符里选四张，
	## 四张符直接占 Q/E/R/T（槽值 `talisman:<base_id>`，见 RogueRun._apply_bare_state）。
	## 符匣 / 落笔 / 贴符 / 引爆 / 符罩 整套退役，改成「施放 → 随机连携另一张」。
	"talisman": {
		"active": [],
		"passive": [],
		"learned": [],
	},
}
## 初始可选流派（0 层就能选的四套，仅作文档 / 顺序参考）
## ⚠ **门禁不读这张表**：真实判定一律走 FAMILY_UNLOCK_FLOOR[x] <= 历史最高层
##   （入口页 `_family_is_unlocked()` / `RogueRun.unlocked_families()`），
##   改解锁条件只改 FAMILY_UNLOCK_FLOOR，别只改这里以为生效了。
const START_FAMILIES: Array[String] = ["sword", "scar", "beast", "talisman"]

## 入口页的流派按钮顺序（含未解锁的 9 套：显示成暗色 + 「第 N 层解锁」）
## ⚠ 与 START_FAMILIES 的区别：START_FAMILIES 是「现在就能选」，这个是「全部要展示」
const FAMILY_ORDER: Array[String] = [
	"sword", "scar", "beast",
	"yinyang", "array", "qi",
	"thunder", "sun", "calamity",
	"mirror", "shadow", "fold",
	"talisman",
]

## 入口页的流派说明（纯 UI 文案；机制本体在各自的招式 / 场地脚本里）
const FAMILY_BLURB: Dictionary = {
	"sword": {
		"mechanic": "剑意：出招叠层，层数放大物理功法伤害；满层时「一剑开天」变全形态。",
		"paths": "万剑流（快速叠满清场）／一剑流（免叠层处决）／剑气流（意转法术炮台）",
	},
	"scar": {
		"mechanic": "刀痕：留痕招式先铺场，激活招式一次引爆；同一击引爆 N 处，每处系数都是 ×N。",
		"paths": "铺痕流（留满再全引爆）／断岳流（格挡蓄力一刀劈穿）／血刀流（越残越狠）",
	},
	## 虎妖没有专属资源条，第三条流派用「虎煞」——击杀叠层、越杀越狠，靠击杀节奏吃收益
	"beast": {
		"mechanic": "无流派资源：五式全是标准形态、只吃冷却，靠冷却压到多段输出。",
		"paths": "蛮力流（踏地破防，重重一记）／砂暴流（群砂铺场，多段压制）／兽潮流（击杀叠虎煞，越打越狠）",
	},
	"yinyang": {
		"mechanic": "阴阳势：打出与势条相反的颜色＝逆式，伤害 +20%、势 +1 层并翻面；每层势再 +2%，太极崩一次清空。",
		"paths": "逆式流（高频翻面）／崩拳流（攒满一崩）／双印流（挂印引爆）",
	},
	"array": {
		"mechanic": "阵旗：场上五面旗首尾相连成阵，阵内攻防 +30%、每秒落雷。",
		"paths": "五旗大阵（铺满碾压）／游击布旗（边打边布）／雷落流（阵做雷池）",
	},
	"qi": {
		"mechanic": "气环：环身扫过敌人持续掉血并吸血，气爆一次倾泻全部层数。",
		"paths": "环身流（贴脸磨）／气爆流（攒满一炸）／回息流（吸血续航）",
	},
	"thunder": {
		"mechanic": "雷势：满势普攻附带协同雷击；消耗雷势换取全部功法冷却。",
		"paths": "雷罚流（雷柱爆发）／攻速流（满势普攻）／减CD流（雷势当冷却货币）",
	},
	"sun": {
		"mechanic": "天火种：持种每秒叠层，每层放大全部伤害；投日 / 日蚀丢种，满层焚心引爆。",
		"paths": "日冕流（全程持种）／投日流（扔种爆发）／焚心流（攒满引爆）",
	},
	"calamity": {
		"mechanic": "三灾：风 / 火 / 雷各挂一痕，互相连锁；三痕齐全时灾崩易伤。",
		"paths": "灾轮流（频繁换灾）／单灾专精（只走一条）／万劫流（归一清场）",
	},
	"mirror": {
		"mechanic": "镜像：放功法时镜像同帧复读一段；镜返反弹术法，碎镜减速。",
		"paths": "复读流（多镜像多复读）／镜返流（反弹术法）／换镜流（换位碎镜）",
	},
	"shadow": {
		"mechanic": "影长：招式射程等于当前影长；影长归零触发明灭，物理大幅强化。",
		"paths": "长影流（全程远程）／明灭流（反复归零）／分影流（影兽代打）",
	},
	"fold": {
		"mechanic": "折痕：每一击同时判定本体与关于折痕的镜像点；穿缝额外加成。",
		"paths": "双面流（镜像点主输出）／穿缝流（位移突进）／折叠流（折痕铺场）",
	},
	"talisman": {
		"mechanic": "四符：开局挑四张符装进 Q/E/R/T，各自独立施放；三选一选到「连携」强化后才解锁：每放一张，随机免费连携符囊里的另一张（70% 效率，回 2 灵力）。",
		"paths": "厚囊流（多符多连携）／单符流（改符把一张符吃透）／连携流（先选「连携」再叠双符+顺笔+同气）／无墨流（不耗灵力，靠冷却压节奏）／绝笔流（不要冷却，用伤害换出手密度）",
	},
}

## 兼容旧调用点：等价于「剑修开局」
const START_ACTIVE: Array[String] = [
	"skill_sword_stab", "skill_sword_chop", "skill_sword_myriad", "skill_sword_heaven",
]
const START_PASSIVE: Array[String] = ["skill_sword_intent"]
const START_LEARNED: Array[String] = [
	"skill_sword_stab", "skill_sword_chop", "skill_sword_myriad",
	"skill_sword_heaven", "skill_sword_intent",
]


## 取某流派的起始功法；未知流派回落剑修（保证开局永远有招可用）
static func family_start(fam: String) -> Dictionary:
	if FAMILY_START.has(fam):
		return FAMILY_START[fam]
	return FAMILY_START["sword"]

# ===== 卡池：通用（20 条）=====
## 字段说明：
##   attr  → 走 CharacterData.set_attribute_mod（flat / base_pct / mult）
##   cap   → 资源上限，走 RogueRun.cap()
##   stat  → 本模式自算乘区，走 RogueRun.stat()
##   flag  → 机制开关，走 RogueRun.has_flag()
##   form  → 招式覆盖，走 RogueRun.apply_form_mods()
const GENERIC_BUFFS: Array = [
	{"id": "g_str", "name": "淬体", "rarity": RARITY_COMMON, "max": 3,
		"desc": "力量 +3", "attr": {"strength": {"flat": 3.0}}},
	{"id": "g_spell", "name": "凝气", "rarity": RARITY_COMMON, "max": 3,
		"desc": "法强 +3", "attr": {"spell_power": {"flat": 3.0}}},
	{"id": "g_hp", "name": "壮血", "rarity": RARITY_COMMON, "max": 3,
		"desc": "气血上限 +15%", "attr": {"hp_max": {"base_pct": 15.0}}},
	{"id": "g_res", "name": "铁骨", "rarity": RARITY_COMMON, "max": 3,
		"desc": "双抗 +8%", "attr": {
			"physical_resist_pct": {"flat": 8.0},
			"magic_resist_pct": {"flat": 8.0}}},
	{"id": "g_speed", "name": "轻身", "rarity": RARITY_COMMON, "max": 3,
		"desc": "移速 +6%", "attr": {"speed_pct": {"flat": 6.0}}},
	{"id": "g_mana", "name": "长息", "rarity": RARITY_COMMON, "max": 3,
		"desc": "灵力上限 +20%", "attr": {"mana_max": {"base_pct": 20.0}}},
	{"id": "g_regen", "name": "通脉", "rarity": RARITY_COMMON, "max": 3,
		"desc": "灵力回复 +30%", "attr": {"mana_regen": {"base_pct": 30.0}}},
	{"id": "g_stamina", "name": "蓄劲", "rarity": RARITY_RARE, "max": 2,
		"desc": "精力上限 +1", "attr": {"stamina_max": {"flat": 1.0}}},
	{"id": "g_haste", "name": "疾风", "rarity": RARITY_RARE, "max": 3,
		"desc": "攻击速度 +10%", "attr": {"attack_speed": {"flat": 10.0}}},
	{"id": "g_full", "name": "破竹", "rarity": RARITY_COMMON, "max": 3,
		"desc": "对满血敌人伤害 +15%", "stat": {"dmg_vs_full": 15.0}},
	{"id": "g_low", "name": "斩弱", "rarity": RARITY_COMMON, "max": 3,
		"desc": "对 30% 血以下敌人伤害 +20%", "stat": {"dmg_vs_low": 20.0}},
	{"id": "g_leech", "name": "饮血", "rarity": RARITY_COMMON, "max": 3,
		"desc": "击杀回复 3% 气血", "stat": {"heal_on_kill": 3.0}},
	{"id": "g_cd", "name": "顺势", "rarity": RARITY_RARE, "max": 2,
		"desc": "击杀使随机一门冷却中的功法 -3 秒", "stat": {"cd_on_kill": 3.0}},
	{"id": "g_scale", "name": "逆鳞", "rarity": RARITY_RARE, "max": 3,
		"desc": "受击后 2 秒内伤害 +20%", "stat": {"dmg_after_hit": 20.0}},
	{"id": "g_step", "name": "踏影", "rarity": RARITY_RARE, "max": 2,
		"desc": "闪避后下一击 +40%", "stat": {"dmg_after_dodge": 40.0}},
	{"id": "g_parry", "name": "归元", "rarity": RARITY_RARE, "max": 2,
		"desc": "弹反成功回复 1 精力", "stat": {"stamina_on_parry": 1.0}},
	{"id": "g_dodge", "name": "疾行", "rarity": RARITY_COMMON, "max": 3,
		"desc": "闪避冷却 -15%", "stat": {"dodge_cd_pct": 15.0}},
	{"id": "g_mana_kill", "name": "引灵", "rarity": RARITY_COMMON, "max": 3,
		"desc": "击杀回复 5 灵力", "stat": {"mana_on_kill": 5.0}},
	{"id": "g_revive", "name": "不灭", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "本局复活次数 +1", "stat": {"revive_plus": 1.0}},
	{"id": "g_cleanse", "name": "洗髓", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "每层开始回复满血，并清空所有负面", "flag": "floor_cleanse"},
	# ===== 机制拓展（2026-11-09）：不叠数值，改行为 =====
	## 风险回报：血越低越狠，但一刀也越疼。数值给得克制，靠「什么时候敢打」制造张力。
	{"id": "g_desperate", "name": "背水", "rarity": RARITY_RARE, "max": 2,
		"desc": "气血低于 35% 时伤害 +20%，但受到的伤害 +8%",
		"stat": {"desperate_dmg": 20.0, "desperate_taken": 8.0}},
	## 杀意是**第二个运行期层数容器**（与虎煞分开）：任何流派都能滚雪球，
	## 但受一次伤就掉一半 —— 逼玩家在「继续收割」与「先躲一手」之间取舍。
	{"id": "g_bloodlust", "name": "嗜杀", "rarity": RARITY_RARE, "max": 1,
		"desc": "击杀叠 1 层杀意（上限 12），每层伤害 +3%；受伤时直接清空一半",
		"stat": {"killmark_per": 3.0, "killmark_cap": 12.0}},
	## 保命型传说：不改输出，改「这一局还能不能继续」。
	{"id": "g_last_stand", "name": "借命", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "每局一次：受到致命伤害时保留 1 点气血，并获得 2 秒无敌",
		"flag": "last_stand"},
	## 节奏型：把「清波」这个本来只有喘息的时间点变成资源回收点。
	{"id": "g_echo", "name": "回响", "rarity": RARITY_RARE, "max": 1,
		"desc": "每清空一波，随机一门冷却中的功法立刻转好",
		"flag": "wave_echo"},
	## 「越少越强」的取舍卡：精力上限少一格 = 少一次弹反/闪避机会，换全程输出。
	{"id": "g_purist", "name": "破釜", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "精力上限 -1，但全部伤害 +25%",
		"attr": {"stamina_max": {"flat": -1.0}}, "stat": {"all_dmg_pct": 25.0}},
]

# ===== 卡池：剑修（3 流派 × 5 条）=====
const SWORD_BUFFS: Array = [
	# --- 万剑流：快速叠满，用万剑归宗清场 ---
	{"id": "s_wj_cap", "name": "纳锋", "rarity": RARITY_RARE, "max": 1,
		"desc": "剑意上限 +2", "cap": {"sword_intent_max": 2}},
	{"id": "s_wj_gain", "name": "聚意", "rarity": RARITY_RARE, "max": 1,
		"desc": "每次获取剑意的层数 +1", "stat": {"intent_gain_bonus": 1.0}},
	{"id": "s_wj_count", "name": "万剑·盈", "rarity": RARITY_RARE, "max": 3,
		"desc": "万剑归宗飞剑 +2 把", "stat": {"myriad_count": 2.0}},
	{"id": "s_wj_amp", "name": "意涌", "rarity": RARITY_COMMON, "max": 3,
		"desc": "每层剑意增幅 +4%", "stat": {"intent_amp": 4.0}},
	{"id": "s_wj_return", "name": "万剑·回锋", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "万剑归宗击杀返还 2 层剑意", "flag": "myriad_kill_refund"},
	# --- 一剑流：放弃群攻，把一剑开天做成处决 ---
	{"id": "s_yj_free", "name": "天成", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "一剑开天无需满剑意即可施展满形态", "flag": "heaven_free"},
	{"id": "s_yj_dmg", "name": "开天·重", "rarity": RARITY_RARE, "max": 1,
		"desc": "一剑开天伤害 +40%", "form": [
			{"form_id": "form_sword_heaven", "field": "phys_coeff", "mult_per": 0.4},
			{"form_id": "form_sword_heaven_full", "field": "spell_coeff", "mult_per": 0.4}]},
	{"id": "s_yj_width", "name": "裂地", "rarity": RARITY_COMMON, "max": 3,
		"desc": "满形态劈落宽度 +10%", "form": [
			{"form_id": "form_sword_heaven_full", "field": "range", "mult_per": 0.1},
			{"form_id": "form_sword_heaven_full", "field": "width", "mult_per": 0.1}]},
	{"id": "s_yj_refund", "name": "开天·收势", "rarity": RARITY_RARE, "max": 1,
		"desc": "一剑开天击杀后返还全部剑意", "flag": "heaven_kill_refund"},
	{"id": "s_yj_cd", "name": "开天·速", "rarity": RARITY_RARE, "max": 1,
		"desc": "一剑开天冷却 -25%", "form": [
			{"form_id": "form_sword_heaven", "field": "cooldown", "mult_per": -0.25},
			{"form_id": "form_sword_heaven_full", "field": "cooldown", "mult_per": -0.25}]},
	# --- 剑气流：剑意转法术，物理剑修变远程炮台 ---
	{"id": "s_jq_spell", "name": "意化", "rarity": RARITY_RARE, "max": 3,
		"desc": "每层剑意额外 +3% 法术伤害", "stat": {"intent_spell_pct": 3.0}},
	{"id": "s_jq_atk", "name": "剑气随身", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "满剑意时普攻附带 0.5× 法强的剑气", "flag": "intent_attack_qi"},
	{"id": "s_jq_mana", "name": "以意御法", "rarity": RARITY_RARE, "max": 1,
		"desc": "剑意可抵灵力：施法时每缺 10 灵力消耗 1 层剑意", "flag": "intent_as_mana"},
	{"id": "s_jq_cap", "name": "纳锋·极", "rarity": RARITY_RARE, "max": 1,
		"desc": "剑意上限 +3", "cap": {"sword_intent_max": 3}},
	{"id": "s_jq_pierce", "name": "破法", "rarity": RARITY_COMMON, "max": 3,
		"desc": "法术功法伤害 +8%", "stat": {"spell_dmg_pct": 8.0}},
	# ===== 机制拓展（2026-11-09）=====
	## 把「攒满再放」的收束点变成爆发点：大招清空几层，就在原地炸几层。
	## 与「天成」相反 —— 天成让你随时满形态，意尽让你舍不得提前放。
	{"id": "s_yj_break", "name": "意尽", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "剑意被清空时，每清空 1 层对周围造成 0.45× 物理伤害",
		"stat": {"intent_break_coeff": 0.45}},
	## 节奏型：清波本来只是喘息，现在变成下一波的起手资本。
	{"id": "s_wj_seed", "name": "剑冢", "rarity": RARITY_RARE, "max": 2,
		"desc": "每清空一波获得 1 层剑意", "stat": {"intent_on_wave": 1.0}},
]

# ===== 刀修池（15 条 = 3 流派 × 5）=====
## 刀修的资源是「刀痕」：留痕招式（scar_effect=create）铺场，
## 激活招式（ignite_path / ignite_area）把它变成斩击，**一次激活 N 处就每处 ×N**。
## 三个流派分别抓「铺得多」「蓄得满」「血越少越狠」。
const SCAR_BUFFS: Array = [
	# --- 铺痕流：留满一地，一次全引爆 ---
	{"id": "b_sp_cap", "name": "拓痕", "rarity": RARITY_RARE, "max": 1,
		"desc": "刀痕上限 +2", "cap": {"scar_max": 2}},
	{"id": "b_sp_life", "name": "余烬", "rarity": RARITY_COMMON, "max": 3,
		"desc": "刀痕留存 +4 秒", "stat": {"scar_life": 4.0}},
	{"id": "b_sp_extra", "name": "重痕", "rarity": RARITY_RARE, "max": 1,
		"desc": "留痕招式额外留下 1 道刀痕", "flag": "scar_extra"},
	{"id": "b_sp_mult", "name": "连斩", "rarity": RARITY_RARE, "max": 3,
		"desc": "刀痕斩击伤害 +20%", "stat": {"scar_mult_pct": 20.0}},
	{"id": "b_sp_move", "name": "踏痕", "rarity": RARITY_COMMON, "max": 3,
		"desc": "场上留有刀痕时移速 +8%", "stat": {"scar_move_pct": 8.0}},
	# --- 断岳流：格挡蓄力 → 蓄满一刀劈穿一条线 ---
	{"id": "b_pk_charge", "name": "蓄势", "rarity": RARITY_RARE, "max": 1,
		"desc": "纳势反击蓄力上限 +3 秒", "form": [
			{"form_id": "form_blade_counter", "field": "charge_max", "add": 3.0}]},
	{"id": "b_pk_block", "name": "铁壁", "rarity": RARITY_COMMON, "max": 3,
		"desc": "纳势格挡减伤 +15%", "stat": {"charge_block_pct": 15.0}},
	{"id": "b_pk_gain", "name": "蓄劲", "rarity": RARITY_RARE, "max": 2,
		"desc": "纳势每蓄 1 秒的系数加成 +0.2", "stat": {"charge_gain_add": 0.2}},
	{"id": "b_pk_pierce", "name": "断岳·裂", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "满势断岳沿途多激活 2 处刀痕", "form": [
			{"form_id": "form_blade_peak", "field": "scar_ignite_max", "add": 2.0}]},
	{"id": "b_pk_stamina", "name": "定势", "rarity": RARITY_COMMON, "max": 1,
		"desc": "格挡蓄力期间受击不掉精力", "flag": "charge_no_stamina"},
	# --- 血刀流：血越少打得越狠 ---
	{"id": "b_bd_low", "name": "血刃", "rarity": RARITY_RARE, "max": 3,
		"desc": "每损失 10% 气血，物理伤害 +6%", "stat": {"low_hp_phys_pct": 6.0}},
	{"id": "b_bd_heal", "name": "饮痕", "rarity": RARITY_COMMON, "max": 3,
		"desc": "刀痕斩击命中时回复 2% 气血", "stat": {"scar_heal_pct": 2.0}},
	{"id": "b_bd_cap", "name": "血怒", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "气血低于 30% 时刀痕上限翻倍", "flag": "scar_cap_low_double"},
	{"id": "b_bd_move", "name": "急血", "rarity": RARITY_COMMON, "max": 3,
		"desc": "气血低于 30% 时移速 +8%", "stat": {"low_hp_move_pct": 8.0}},
	{"id": "b_bd_kill", "name": "啖血", "rarity": RARITY_COMMON, "max": 3,
		"desc": "击杀回复 4% 气血", "stat": {"heal_on_kill": 4.0}},
	# ===== 机制拓展（2026-11-09）=====
	## 与「铺满再全引爆」正相反的赌法：只留一道痕、只引爆一次，换来一击穿甲。
	## 玩家得主动忍住不叠第二道 —— 这才是「玩法」而不是「数值」。
	{"id": "b_sp_lone", "name": "孤刃", "rarity": RARITY_RARE, "max": 1,
		"desc": "只引爆 1 道刀痕时，该次斩击伤害 ×2.5", "stat": {"scar_lone_mult": 2.5}},
	## 让刀痕变成「可反复点燃的柴」而不是一次性炸药：首爆后留半条余命。
	{"id": "b_sp_ember", "name": "余痕", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "刀痕被引爆后不消失，保留一半余时（每道只能重生一次）",
		"flag": "scar_rekindle"},
]

# ===== 虎妖池（15 条 = 3 流派 × 5）=====
## 虎妖的资源是「冷却」：4 式全是标准形态（爪 / 群砂 / 踏地 / 妖丹），没有专属资源条。
## 蛮力抓「踏地这一记重击」，砂暴抓「砂石乱舞这一轮弹幕」，
## 兽潮抓「击杀滚雪球」—— 虎煞层数是本模式唯一的运行期层数资源（见 RogueRun.hunt_stacks）。
## ⚠ 兽潮流的第一张「虎煞」是**唯一**的开关卡：没有它，hunt_stacks 恒为 0，
##   其余四张兽潮卡全是废卡。所以它必须是普通档、max 1、且不会被别的途径漏掉。
const BEAST_BUFFS: Array = [
	# --- 蛮力流：重击破防，一击一截血 ---
	{"id": "t_bl_range", "name": "撼地", "rarity": RARITY_COMMON, "max": 2,
		"desc": "猛虎踏地范围 +25%", "form": [
			{"form_id": "form_smash", "field": "range", "mult_per": 0.25}]},
	{"id": "t_bl_break", "name": "碎甲", "rarity": RARITY_RARE, "max": 1,
		"desc": "猛虎踏地与虎爪裂空命中附加 3 秒破防（受伤 +15%）",
		"stat": {"break_sec": 3.0}},
	{"id": "t_bl_heavy", "name": "崩山", "rarity": RARITY_RARE, "max": 2,
		"desc": "猛虎踏地伤害 +20%", "form": [
			{"form_id": "form_smash", "field": "phys_coeff", "mult_per": 0.20}]},
	{"id": "t_bl_broken", "name": "压强", "rarity": RARITY_RARE, "max": 2,
		"desc": "对破防目标伤害 +15%", "stat": {"dmg_vs_broken": 15.0}},
	{"id": "t_bl_phys", "name": "蛮劲", "rarity": RARITY_COMMON, "max": 3,
		"desc": "物理招式伤害 +10%", "stat": {"phys_dmg_pct": 10.0}},
	# --- 砂暴流：远程多段，把整片战场铺满 ---
	{"id": "t_sb_count", "name": "飞砂", "rarity": RARITY_RARE, "max": 2,
		"desc": "砂石乱舞弹数 +1", "form": [
			{"form_id": "form_arrow_volley", "field": "count", "add": 1.0}]},
	{"id": "t_sb_range", "name": "远砂", "rarity": RARITY_COMMON, "max": 2,
		"desc": "远程招式射程 +15%", "form": [
			{"form_id": "form_arrow", "field": "range", "mult_per": 0.15},
			{"form_id": "form_arrow_volley", "field": "range", "mult_per": 0.15},
			{"form_id": "form_element_orb", "field": "range", "mult_per": 0.15}]},
	{"id": "t_sb_slow", "name": "迷眼", "rarity": RARITY_COMMON, "max": 1,
		"desc": "砂石乱舞命中附加 3 秒迷眼（移速 -25%）",
		"stat": {"sand_slow_sec": 3.0}},
	{"id": "t_sb_cd", "name": "骤雨", "rarity": RARITY_RARE, "max": 2,
		"desc": "远程招式冷却 -12%", "form": [
			{"form_id": "form_arrow", "field": "cooldown", "mult_per": -0.12},
			{"form_id": "form_arrow_volley", "field": "cooldown", "mult_per": -0.12},
			{"form_id": "form_element_orb", "field": "cooldown", "mult_per": -0.12}]},
	{"id": "t_sb_orb", "name": "妖丹·烈", "rarity": RARITY_RARE, "max": 2,
		"desc": "虎煞妖丹伤害 +20%", "form": [
			{"form_id": "form_element_orb", "field": "spell_coeff", "mult_per": 0.20}]},
	# --- 兽潮流：击杀叠「虎煞」，越杀越狠（不需要召唤实体，纯玩家自身增益）---
	{"id": "t_cy_base", "name": "虎煞", "rarity": RARITY_COMMON, "max": 1,
		"desc": "击杀敌人获得 1 层虎煞（上限 8 层），每层伤害 +2%",
		"flag": "hunt_gain", "stat": {"hunt_dmg_per": 2.0}},
	{"id": "t_cy_dmg", "name": "凶性", "rarity": RARITY_COMMON, "max": 3,
		"desc": "每层虎煞额外 +1% 伤害", "stat": {"hunt_dmg_per": 1.0}},
	{"id": "t_cy_aspd", "name": "噬血", "rarity": RARITY_RARE, "max": 3,
		"desc": "每层虎煞额外 +1.5% 攻击速度", "stat": {"hunt_aspd_per": 1.5}},
	{"id": "t_cy_cap", "name": "煞贯", "rarity": RARITY_RARE, "max": 1,
		"desc": "虎煞上限 +4；虎煞满层时移速 +15%",
		"stat": {"hunt_cap_add": 4.0, "hunt_full_move": 15.0}},
	{"id": "t_cy_bloom", "name": "万兽", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "虎煞满层时，虎煞的伤害与攻速加成翻倍，且击杀使猛虎踏地冷却 -4 秒",
		"flag": "hunt_full_bloom"},
	# ===== 机制拓展（2026-11-09）=====
	## 把「打小怪攒层」改造成「打大怪直接兑现」：精英与 BOSS 变成虎煞补给点。
	{"id": "t_cy_hunt", "name": "猎杀本能", "rarity": RARITY_RARE, "max": 1,
		"desc": "击杀精英或 BOSS 时额外获得 3 层虎煞", "stat": {"hunt_on_big_kill": 3.0}},
	## 满层不再是纯增伤，而是换一种出招方式：踏地变成免费的破防领域。
	{"id": "t_bl_feral", "name": "兽性", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "虎煞满层时，猛虎踏地范围 +50%，命中附加 3 秒破防",
		"flag": "hunt_stomp_free"},
]

# ===== 两仪池（15 条 = 3 流派 × 5）=====
## 资源是「阴阳势」：逆式叠层、满层太极崩清空。
## 三条路：高频翻面（逆式流）／攒满一崩（崩拳流）／挂印引爆（双印流）。
const YINYANG_BUFFS: Array = [
	# --- 逆式流 ---
	{"id": "y_ni_cap", "name": "太极枢", "rarity": RARITY_RARE, "max": 1,
		"desc": "阴阳势上限 +2", "cap": {"yinyang_max": 2}},
	{"id": "y_ni_stack", "name": "逆流", "rarity": RARITY_RARE, "max": 1,
		"desc": "逆式命中额外叠 1 层势", "stat": {"yy_extra_stack": 1.0}},
	{"id": "y_ni_dmg", "name": "反骨", "rarity": RARITY_RARE, "max": 2,
		"desc": "逆式伤害 +15%", "stat": {"yy_reverse_pct": 15.0}},
	{"id": "y_ni_cd", "name": "疾转", "rarity": RARITY_COMMON, "max": 3,
		"desc": "两仪转冷却 -12%", "form": [
			{"form_id": "form_yinyang_flip", "field": "cooldown", "mult_per": -0.12}]},
	{"id": "y_ni_mana", "name": "借势", "rarity": RARITY_COMMON, "max": 3,
		"desc": "逆式命中回复 4 灵力", "stat": {"yy_mana_reverse": 4.0}},
	# --- 崩拳流 ---
	{"id": "y_beng_per", "name": "蓄崩", "rarity": RARITY_RARE, "max": 2,
		"desc": "太极崩每层势的系数 +0.15", "stat": {"yy_collapse_per": 0.15}},
	{"id": "y_beng_range", "name": "崩山", "rarity": RARITY_COMMON, "max": 3,
		"desc": "太极崩范围 +12%", "form": [
			{"form_id": "form_yinyang_collapse", "field": "range", "mult_per": 0.12}]},
	{"id": "y_beng_refund", "name": "崩势", "rarity": RARITY_RARE, "max": 1,
		"desc": "太极崩击杀返还 2 层势", "flag": "yy_collapse_refund"},
	{"id": "y_beng_stun", "name": "定身崩", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "太极崩命中使敌人硬直 1.2 秒", "flag": "yy_collapse_stun"},
	{"id": "y_beng_mana", "name": "崩息", "rarity": RARITY_COMMON, "max": 3,
		"desc": "太极崩命中回复 6 灵力", "stat": {"yy_collapse_mana": 6.0}},
	# --- 双印流 ---
	{"id": "y_yin_life", "name": "印长", "rarity": RARITY_COMMON, "max": 3,
		"desc": "阴印 / 阳印持续 +2 秒", "stat": {"yy_mark_sec": 2.0}},
	{"id": "y_yin_amp", "name": "印重", "rarity": RARITY_RARE, "max": 2,
		"desc": "引爆阴阳印的伤害 +10%", "stat": {"yy_mark_pct": 10.0}},
	{"id": "y_yin_cap", "name": "抱元", "rarity": RARITY_RARE, "max": 1,
		"desc": "阴阳势上限 +1，每层势增伤 +1%",
		"cap": {"yinyang_max": 1}, "stat": {"yy_stack_pct": 1.0}},
	{"id": "y_yin_heal", "name": "印回", "rarity": RARITY_COMMON, "max": 3,
		"desc": "引爆阴阳印回复 2% 气血", "stat": {"yy_mark_heal": 2.0}},
	{"id": "y_yin_burst", "name": "双印", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "引爆阴阳印时额外造成 0.8× 法强的阴阳爆", "stat": {"yy_mark_burst": 0.8}},
	# ===== 机制拓展（2026-11-09）=====
	## 把「必须逆式才叠势」这条铁律掀掉：同色也能叠，代价是逆式那 20% 变成 10%。
	## 与「逆流」互斥地改变整个循环，而不是又加一层伤害。
	{"id": "y_ni_same", "name": "同流", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "同色命中也可叠 1 层势（逆式额外伤害从 +20% 降为 +10%）",
		"flag": "yy_same_stack"},
	## 印不再只属于一个人：引爆时把同色的印传给最近的另一个目标。
	{"id": "y_yin_taint", "name": "印染", "rarity": RARITY_RARE, "max": 1,
		"desc": "引爆阴阳印时，把同色印传染给 320 范围内最近的另一个敌人",
		"flag": "yy_mark_spread"},
]

# ===== 阵旗池（15 条 = 3 流派 × 5）=====
## 资源是「阵旗」：5 面成阵，阵内攻防 +30%、每秒落雷。
## 三条路：铺满五旗（五旗大阵）／边打边布（游击布旗）／把阵做成雷池（雷落流）。
const ARRAY_BUFFS: Array = [
	# --- 五旗大阵 ---
	{"id": "a_flag_cap", "name": "扩阵", "rarity": RARITY_RARE, "max": 1,
		"desc": "阵旗上限 +2", "cap": {"array_max": 2}},
	{"id": "a_zone_amp", "name": "阵威", "rarity": RARITY_RARE, "max": 2,
		"desc": "阵内攻击加成 +10%", "stat": {"array_zone_amp": 10.0}},
	{"id": "a_zone_thunder", "name": "雷池", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "阵区落雷间隔减半", "stat": {"array_strike_haste": 100.0}},
	{"id": "a_plant_cd", "name": "瞬布", "rarity": RARITY_COMMON, "max": 3,
		"desc": "布旗冷却 -15%", "form": [
			{"form_id": "form_array_plant", "field": "cooldown", "mult_per": -0.15}]},
	{"id": "a_plant_range", "name": "布远", "rarity": RARITY_COMMON, "max": 3,
		"desc": "布旗距离 +20%", "form": [
			{"form_id": "form_array_plant", "field": "cast_range", "mult_per": 0.20}]},
	# --- 游击布旗 ---
	{"id": "a_plant_dmg", "name": "布杀", "rarity": RARITY_RARE, "max": 2,
		"desc": "布旗时对周围造成 0.8× 法强伤害", "stat": {"array_plant_dmg": 0.8}},
	{"id": "a_plant_radius", "name": "布杀·扩", "rarity": RARITY_COMMON, "max": 3,
		"desc": "布旗溅射范围 +20%", "stat": {"array_plant_radius": 20.0}},
	{"id": "a_flag_move", "name": "旗行", "rarity": RARITY_COMMON, "max": 3,
		"desc": "每面阵旗使移速 +3%", "stat": {"array_flag_move": 3.0}},
	{"id": "a_pull_stamina", "name": "收势", "rarity": RARITY_RARE, "max": 1,
		"desc": "收旗回复 2 点精力", "stat": {"array_pull_stamina": 2.0}},
	{"id": "a_burst_free", "name": "解阵", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "解阵·雷落不消耗灵力", "flag": "array_burst_free"},
	# --- 雷落流 ---
	{"id": "a_strike_dmg", "name": "雷落·重", "rarity": RARITY_RARE, "max": 3,
		"desc": "阵区落雷伤害 +25%", "stat": {"array_strike_pct": 25.0}},
	{"id": "a_strike_chain", "name": "连锁", "rarity": RARITY_RARE, "max": 1,
		"desc": "阵区落雷额外连锁 1 个目标", "stat": {"array_strike_chain": 1.0}},
	{"id": "a_strike_elec", "name": "感电", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "阵区落雷附加 3 秒感电", "flag": "array_strike_elec"},
	{"id": "a_strike_cd", "name": "雷速", "rarity": RARITY_COMMON, "max": 3,
		"desc": "阵区落雷间隔 -10%", "stat": {"array_strike_haste": 10.0}},
	{"id": "a_flag_strike", "name": "旗引", "rarity": RARITY_RARE, "max": 2,
		"desc": "每面阵旗使落雷伤害 +4%", "stat": {"array_strike_per_flag": 4.0}},
	# ===== 机制拓展（2026-11-09）=====
	## 解阵原本只是「收旗」，现在变成一次主动引爆：旗越多炸得越狠。
	{"id": "a_burst_echo", "name": "解阵·回响", "rarity": RARITY_RARE, "max": 2,
		"desc": "解阵时每面阵旗在落点爆炸，各造成 0.9× 法强伤害",
		"stat": {"array_burst_echo": 0.9}},
	## 把「阵内」从站桩增益改成移动中的陷阱：在阵里闪避 = 踩雷。
	{"id": "a_step_trap", "name": "踏阵", "rarity": RARITY_RARE, "max": 1,
		"desc": "在阵区内闪避时，对周围 220 范围造成 1.0× 法强伤害并减速 2 秒",
		"flag": "array_step_trap"},
]

# ===== 气环池（15 条 = 3 流派 × 5）=====
## 资源是「气环」：环身接触伤害 + 气爆一次性倾泻。
## 三条路：贴脸磨（环身流）／攒满一炸（气爆流）／吸血续航（回息流）。
const QI_BUFFS: Array = [
	# --- 环身流 ---
	{"id": "q_ring_cap", "name": "环枢", "rarity": RARITY_RARE, "max": 1,
		"desc": "气环上限 +3", "cap": {"qi_max": 3}},
	{"id": "q_touch", "name": "环锋", "rarity": RARITY_RARE, "max": 2,
		"desc": "环身接触伤害 +25%", "stat": {"qi_touch_pct": 25.0}},
	{"id": "q_radius", "name": "张环", "rarity": RARITY_COMMON, "max": 3,
		"desc": "气环半径 +15%", "stat": {"qi_radius_pct": 15.0}},
	{"id": "q_def", "name": "环守", "rarity": RARITY_COMMON, "max": 3,
		"desc": "每层气环减伤 +2%", "stat": {"qi_def_pct": 2.0}},
	{"id": "q_full_move", "name": "环行", "rarity": RARITY_RARE, "max": 1,
		"desc": "气环满层时移速 +15%", "stat": {"qi_full_move": 15.0}},
	# --- 气爆流 ---
	{"id": "q_burst_per", "name": "爆劲", "rarity": RARITY_RARE, "max": 2,
		"desc": "气爆每环系数 +0.15", "stat": {"qi_burst_per": 0.15}},
	{"id": "q_burst_range", "name": "爆域", "rarity": RARITY_COMMON, "max": 3,
		"desc": "气爆范围 +15%", "form": [
			{"form_id": "form_qi_burst", "field": "range", "mult_per": 0.15}]},
	{"id": "q_burst_dmg", "name": "周天", "rarity": RARITY_COMMON, "max": 3,
		"desc": "气爆伤害 +15%", "stat": {"qi_burst_pct": 15.0}},
	{"id": "q_burst_refund", "name": "爆环", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "气爆击杀返还 2 层气环", "flag": "qi_burst_refund"},
	{"id": "q_burst_mana", "name": "爆息", "rarity": RARITY_RARE, "max": 3,
		"desc": "气爆命中回复 8 灵力", "stat": {"qi_burst_mana": 8.0}},
	# --- 回息流 ---
	{"id": "q_leech", "name": "吸息", "rarity": RARITY_RARE, "max": 2,
		"desc": "环身气吸血 +20%", "stat": {"qi_leech_pct": 20.0}},
	{"id": "q_regen", "name": "满环·息", "rarity": RARITY_COMMON, "max": 3,
		"desc": "气环满层时每秒回复 0.4% 气血", "stat": {"qi_full_regen": 0.4}},
	{"id": "q_guard", "name": "环御", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "受击时消耗 1 层气环抵消 20% 伤害", "flag": "qi_guard"},
	{"id": "q_gather", "name": "聚气", "rarity": RARITY_RARE, "max": 2,
		"desc": "引气·聚环冷却 -20%", "form": [
			{"form_id": "form_qi_gather", "field": "cooldown", "mult_per": -0.20}]},
	{"id": "q_spell", "name": "环法", "rarity": RARITY_RARE, "max": 2,
		"desc": "每层气环使法术伤害 +3%", "stat": {"qi_spell_per": 3.0}},
	# ===== 机制拓展（2026-11-09）=====
	## 气爆从「伤害按钮」变成「聚怪按钮」：先吸再打，和气环的环身贴脸逻辑咬合。
	{"id": "q_burst_pull", "name": "环吸", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "气爆把 240 范围内的敌人向中心拉近 160 像素",
		"flag": "qi_burst_pull"},
	## 满环之后每次「再吃环」不再浪费，而是换成精力 —— 让溢出的资源有去处。
	{"id": "q_overflow", "name": "溢息", "rarity": RARITY_RARE, "max": 1,
		"desc": "气环已满时，每次获取气环改为回复 1 点精力", "flag": "qi_overflow"},
]

# ===== 判词雷池（15 条 = 3 流派 × 5）=====
## 资源是「雷势」：满势普攻带协同雷；耗势换冷却。
## 三条路：雷柱爆发（雷罚流）／满势普攻（攻速流）／雷势当冷却货币（减CD流）。
const THUNDER_BUFFS: Array = [
	# --- 雷罚流 ---
	{"id": "l_pillar_add", "name": "雷柱·增", "rarity": RARITY_RARE, "max": 2,
		"desc": "九霄雷罚雷柱 +1", "stat": {"pillar_add": 1.0}},
	{"id": "l_pillar_dmg", "name": "雷柱·重", "rarity": RARITY_RARE, "max": 3,
		"desc": "九霄雷罚伤害 +25%", "stat": {"pillar_pct": 25.0}},
	{"id": "l_pillar_range", "name": "雷柱·广", "rarity": RARITY_COMMON, "max": 3,
		"desc": "九霄雷罚落点范围 +20%", "form": [
			{"form_id": "form_thunder_nine", "field": "range", "mult_per": 0.20}]},
	{"id": "l_lei_cap", "name": "雷枢", "rarity": RARITY_RARE, "max": 1,
		"desc": "雷势上限 +2", "cap": {"thunder_max": 2}},
	{"id": "l_pillar_refund", "name": "雷殛", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "九霄雷罚击杀返还全部雷势", "flag": "pillar_kill_refund"},
	# --- 攻速流 ---
	{"id": "l_coop_dmg", "name": "协雷·烈", "rarity": RARITY_RARE, "max": 3,
		"desc": "协同雷击伤害 +25%", "stat": {"coop_pct": 25.0}},
	{"id": "l_coop_range", "name": "协雷·远", "rarity": RARITY_COMMON, "max": 3,
		"desc": "协同雷击范围 +20%", "stat": {"coop_range": 20.0}},
	{"id": "l_full_haste", "name": "满势·疾", "rarity": RARITY_RARE, "max": 2,
		"desc": "满雷势时攻击速度 +10%", "stat": {"thunder_full_haste": 10.0}},
	{"id": "l_coop_chain", "name": "协雷·连", "rarity": RARITY_RARE, "max": 1,
		"desc": "协同雷击额外劈中 1 个附近目标", "stat": {"coop_chain": 1.0}},
	{"id": "l_verdict_cd", "name": "判词·速", "rarity": RARITY_COMMON, "max": 3,
		"desc": "判词·天律冷却 -15%", "form": [
			{"form_id": "form_thunder_verdict", "field": "cooldown", "mult_per": -0.15}]},
	# --- 减CD流 ---
	{"id": "l_lei_cd", "name": "雷势·减", "rarity": RARITY_RARE, "max": 2,
		"desc": "每耗 1 雷势额外减 0.5 秒冷却", "stat": {"lei_cd_add": 0.5}},
	{"id": "l_stun_sec", "name": "震魂", "rarity": RARITY_COMMON, "max": 3,
		"desc": "雷击眩晕时长 +0.3 秒", "stat": {"thunder_stun_add": 0.3}},
	{"id": "l_vs_stun", "name": "定罪", "rarity": RARITY_RARE, "max": 3,
		"desc": "对眩晕目标伤害 +15%", "stat": {"dmg_vs_stun": 15.0}},
	{"id": "l_stun_fast", "name": "速判", "rarity": RARITY_RARE, "max": 1,
		"desc": "雷击眩晕所需次数 -2", "stat": {"thunder_stun_less": 2.0}},
	{"id": "l_exec", "name": "定刑·极", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "定刑·雷殛击杀时刷新全部功法冷却", "flag": "exec_kill_reset"},
	# ===== 机制拓展（2026-11-09）=====
	## 雷势从「攒着不用」改成「花掉才炸」：每消耗 1 层雷势，就在身周落一圈雷。
	{"id": "l_hold_lei", "name": "雷爆", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "消耗雷势时，每消耗 1 层对周围 260 范围造成 0.5× 法强雷伤",
		"stat": {"lei_spend_burst": 0.5}},
	## 把「眩晕」从增伤条件升级成连锁条件：打晕了才会引来第二道天雷。
	{"id": "l_judge_chain", "name": "引雷", "rarity": RARITY_RARE, "max": 1,
		"desc": "对眩晕目标造成雷击时，追加一道 0.8× 法强的落雷",
		"stat": {"lei_chain_coeff": 0.8}},
]

# ===== 逐日池（15 条 = 3 流派 × 5）=====
## 资源是「天火种」：持种每秒叠层、每层放大全部伤害。
## 三条路：全程持种（日冕流）／扔种爆发（投日流）／满层焚心（焚心流）。
const SUN_BUFFS: Array = [
	# --- 日冕流 ---
	{"id": "u_stack_dmg", "name": "日冕", "rarity": RARITY_RARE, "max": 3,
		"desc": "每层天火种的增伤 +3%", "stat": {"sun_per_stack": 3.0}},
	{"id": "u_cap", "name": "盛阳", "rarity": RARITY_RARE, "max": 1,
		"desc": "天火种上限 +2", "cap": {"sun_max": 2}},
	{"id": "u_gain", "name": "引火", "rarity": RARITY_COMMON, "max": 3,
		"desc": "天火种叠层速度 +25%", "stat": {"sun_gain_pct": 25.0}},
	{"id": "u_full_move", "name": "日行", "rarity": RARITY_COMMON, "max": 2,
		"desc": "天火种满层时移速 +10%", "stat": {"sun_full_move": 10.0}},
	{"id": "u_full_regen", "name": "日浴", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "天火种满层时每秒回复 1% 气血", "stat": {"sun_full_regen": 1.0}},
	# --- 投日流 ---
	{"id": "u_throw_dmg", "name": "投日·烈", "rarity": RARITY_RARE, "max": 3,
		"desc": "投日伤害 +30%", "form": [
			{"form_id": "form_sun_throw", "field": "spell_coeff", "mult_per": 0.30}]},
	{"id": "u_throw_range", "name": "投日·远", "rarity": RARITY_COMMON, "max": 3,
		"desc": "投日射程 +20%", "form": [
			{"form_id": "form_sun_throw", "field": "range", "mult_per": 0.20}]},
	{"id": "u_throw_cd", "name": "投日·疾", "rarity": RARITY_RARE, "max": 2,
		"desc": "投日冷却 -20%", "form": [
			{"form_id": "form_sun_throw", "field": "cooldown", "mult_per": -0.20}]},
	{"id": "u_throw_back", "name": "日归", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "投日命中回复 1 层天火种", "flag": "sun_throw_refund"},
	{"id": "u_throw_mana", "name": "焚息", "rarity": RARITY_COMMON, "max": 3,
		"desc": "投日命中回复 5 灵力", "stat": {"sun_throw_mana": 5.0}},
	# --- 焚心流 ---
	{"id": "u_nova_dmg", "name": "焚心·烈", "rarity": RARITY_RARE, "max": 2,
		"desc": "焚心爆炸伤害 +40%", "stat": {"sun_nova_pct": 40.0}},
	{"id": "u_nova_range", "name": "焚心·广", "rarity": RARITY_COMMON, "max": 3,
		"desc": "焚心爆炸半径 +25%", "stat": {"sun_nova_radius": 25.0}},
	{"id": "u_nova_lie", "name": "烈阳", "rarity": RARITY_RARE, "max": 2,
		"desc": "天火种满层时，全部伤害额外 +8%", "stat": {"sun_full_dmg": 8.0}},
	{"id": "u_nova_burn", "name": "余烬", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "焚心命中附加 3 秒灼烧", "flag": "sun_nova_burn"},
	# ⚠ 11-12 审计修的字段名：这里原本写 phys_coeff，但 form_sun_wind 玩家侧
	#   phys_coeff = 0.0（伤害走 spell_coeff 0.70）→ 0 × 1.15 = 0，卡等于没选。
	{"id": "u_wind", "name": "焚风", "rarity": RARITY_COMMON, "max": 3,
		"desc": "焚风伤害 +15%", "form": [
			{"form_id": "form_sun_wind", "field": "spell_coeff", "mult_per": 0.15}]},
	# ===== 机制拓展（2026-11-09）=====
	## 天火种只进不退：命中就补柴，让持种流不再靠站桩等层数。
	{"id": "u_keep_seed", "name": "日进", "rarity": RARITY_RARE, "max": 1,
		"desc": "日冕斩与焚风命中时，若天火种未满则 +1 层",
		"flag": "sun_hit_stack"},
	## 击杀 = 拾柴：把「杀怪」直接变成天火种的补给，烧得越久越猛。
	{"id": "u_kill_seed", "name": "盗火", "rarity": RARITY_RARE, "max": 1,
		"desc": "击杀敌人获得 1 层天火种", "stat": {"sun_on_kill": 1.0}},
]

# ===== 三灾池（15 条 = 3 流派 × 5）=====
## 资源是「三痕」：风 / 火 / 雷各挂一痕，互相连锁。
## 三条路：频繁换灾（灾轮流）／专精一条（单灾专精）／万劫归一清场（万劫流）。
const CALAMITY_BUFFS: Array = [
	# --- 灾轮流 ---
	{"id": "c_turn_cd", "name": "轮转·速", "rarity": RARITY_COMMON, "max": 3,
		"desc": "三灾轮转冷却 -15%", "form": [
			{"form_id": "form_calamity_turn", "field": "cooldown", "mult_per": -0.15}]},
	{"id": "c_turn_free", "name": "天轮", "rarity": RARITY_RARE, "max": 2,
		"desc": "三灾轮转不消耗灵力", "stat": {"calamity_turn_free": 1.0}},
	{"id": "c_mark_all", "name": "灾临", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "换灾位时给场上所有敌人挂 1 层对应灾痕", "flag": "calamity_swap_all"},
	{"id": "c_momentum_cap", "name": "灾枢", "rarity": RARITY_RARE, "max": 1,
		"desc": "灾势上限 +2", "cap": {"calamity_max": 2}},
	{"id": "c_break_amp", "name": "灾崩·深", "rarity": RARITY_RARE, "max": 2,
		"desc": "灾崩易伤额外 +10%", "stat": {"calamity_break_pct": 10.0}},
	# --- 单灾专精 ---
	{"id": "c_elem_dmg", "name": "专精", "rarity": RARITY_RARE, "max": 3,
		"desc": "当前灾位的灾害招式伤害 +20%", "stat": {"calamity_elem_pct": 20.0}},
	{"id": "c_mark_deep", "name": "痕深", "rarity": RARITY_RARE, "max": 3,
		"desc": "目标身上每有一道灾痕，对其伤害 +4%", "stat": {"calamity_per_mark": 4.0}},
	{"id": "c_react_dmg", "name": "连锁·烈", "rarity": RARITY_RARE, "max": 2,
		"desc": "三痕连锁伤害 +40%", "stat": {"calamity_react_pct": 40.0}},
	{"id": "c_body", "name": "灾衣", "rarity": RARITY_COMMON, "max": 3,
		"desc": "灾位激活时受伤 -6%", "stat": {"calamity_body_pct": 6.0}},
	{"id": "c_ward", "name": "劫衣", "rarity": RARITY_RARE, "max": 1,
		"desc": "灾势满层时受伤 -15%", "stat": {"calamity_full_ward": 15.0}},
	# --- 万劫流 ---
	{"id": "c_final_dmg", "name": "万劫·烈", "rarity": RARITY_RARE, "max": 3,
		"desc": "万劫归一伤害 +25%", "stat": {"calamity_final_pct": 25.0}},
	{"id": "c_turn_range", "name": "灾轮·广", "rarity": RARITY_COMMON, "max": 3,
		"desc": "三灾轮转范围 +15%", "form": [
			{"form_id": "form_calamity_turn", "field": "range", "mult_per": 0.15}]},
	{"id": "c_final_reset", "name": "劫尽", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "万劫归一击杀刷新其冷却", "flag": "calamity_final_reset"},
	{"id": "c_final_mark", "name": "万劫·痕", "rarity": RARITY_RARE, "max": 1,
		"desc": "万劫归一给命中目标补上全部三痕", "flag": "calamity_final_marks"},
	{"id": "c_final_mana", "name": "劫息", "rarity": RARITY_COMMON, "max": 3,
		"desc": "万劫归一命中回复 6 灵力", "stat": {"calamity_final_mana": 6.0}},
	# ===== 机制拓展（2026-11-09）=====
	## 三痕从「个人身上的账」变成会传染的瘟疫：清场时痕自己会找下一个宿主。
	{"id": "c_plague", "name": "灾疫", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "带满三痕的敌人死亡时，把三痕传给 400 内最近的敌人",
		"flag": "calamity_plague"},
	## 与「万劫流」相反的专精赌法：只挂一种痕，反而打得更痛。
	{"id": "c_lone_amp", "name": "独灾", "rarity": RARITY_RARE, "max": 2,
		"desc": "目标身上只有一种灾痕时，对其伤害 +15%", "stat": {"calamity_lone_pct": 15.0}},
]

# ===== 镜身池（15 条 = 3 流派 × 5）=====
## 资源是「镜像」：放功法时镜像同帧复读一段。
## 三条路：多镜像多复读（复读流）／反弹术法（镜返流）／换位碎镜（换镜流）。
const MIRROR_BUFFS: Array = [
	# --- 复读流 ---
	{"id": "m_cap", "name": "镜枢", "rarity": RARITY_RARE, "max": 1,
		"desc": "镜像上限 +2", "cap": {"mirror_max": 2}},
	{"id": "m_echo", "name": "复读", "rarity": RARITY_RARE, "max": 2,
		"desc": "镜像复读倍率 +0.15", "stat": {"mirror_echo_add": 0.15}},
	{"id": "m_life", "name": "镜久", "rarity": RARITY_COMMON, "max": 3,
		"desc": "镜像寿命 +3 秒", "stat": {"mirror_life": 3.0}},
	{"id": "m_keep", "name": "不散", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "镜像上限 +1，且复读倍率 +0.10",
		"cap": {"mirror_max": 1}, "stat": {"mirror_echo_add": 0.10}},
	{"id": "m_per_image", "name": "映照", "rarity": RARITY_COMMON, "max": 3,
		"desc": "每存在 1 个镜像使伤害 +4%", "stat": {"mirror_dmg_per": 4.0}},
	# --- 镜返流 ---
	{"id": "m_reflect", "name": "镜返·反", "rarity": RARITY_RARE, "max": 2,
		"desc": "镜返反弹倍率 +40%", "stat": {"mirror_reflect_pct": 40.0}},
	{"id": "m_reflect_inv", "name": "镜返·护", "rarity": RARITY_COMMON, "max": 2,
		"desc": "镜返成功后无敌 +0.3 秒", "stat": {"mirror_reflect_inv": 0.3}},
	{"id": "m_reflect_cd", "name": "碎镜·速", "rarity": RARITY_COMMON, "max": 3,
		"desc": "碎镜冷却 -20%", "form": [
			{"form_id": "form_mirror_shatter", "field": "cooldown", "mult_per": -0.20}]},
	{"id": "m_reflect_stam", "name": "镜返·归", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "镜返成功回复 2 点精力", "flag": "mirror_reflect_stamina"},
	{"id": "m_reflect_dmg", "name": "镜返·烈", "rarity": RARITY_RARE, "max": 2,
		"desc": "镜返反弹伤害 +30%", "stat": {"mirror_reflect_pct": 30.0}},
	# --- 换镜流 ---
	{"id": "m_swap_dmg", "name": "换镜·锐", "rarity": RARITY_RARE, "max": 3,
		"desc": "换镜后 2 秒内伤害 +20%", "stat": {"mirror_swap_dmg": 20.0}},
	{"id": "m_shatter_range", "name": "碎镜·广", "rarity": RARITY_COMMON, "max": 3,
		"desc": "碎镜范围 +25%", "form": [
			{"form_id": "form_mirror_shatter", "field": "range", "mult_per": 0.25}]},
	{"id": "m_shatter_slow", "name": "碎镜·滞", "rarity": RARITY_RARE, "max": 2,
		"desc": "碎镜减速时长 +1.5 秒", "stat": {"mirror_slow_sec": 1.5}},
	{"id": "m_swap_free", "name": "不碎", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "换镜后获得 0.6 秒额外无敌，且落点留下 1 面镜子", "stat": {"mirror_swap_inv": 0.6}},
	{"id": "m_bloom", "name": "万镜·速", "rarity": RARITY_COMMON, "max": 3,
		"desc": "万镜冷却 -20%", "form": [
			{"form_id": "form_mirror_myriad", "field": "cooldown", "mult_per": -0.20}]},
	# ===== 机制拓展（2026-11-09）=====
	## 唯一一张「改写死亡」的镜身卡：把一面镜子当成一条命。
	{"id": "m_replace", "name": "镜替", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "每局一次：受到致命伤害时碎一面镜像抵消该次伤害，并回复 20% 气血",
		"flag": "mirror_stand_in"},
	## 让「碎镜」不再只是换位手段，而是一次范围清场。
	{"id": "m_burst", "name": "镜爆", "rarity": RARITY_RARE, "max": 2,
		"desc": "镜像消散时对周围 150 范围造成 0.8× 法强伤害",
		"stat": {"mirror_burst_coeff": 0.8}},
]

# ===== 投影池（15 条 = 3 流派 × 5）=====
## 资源是「影长」：招式射程等于当前影长。
## 三条路：拉满影长（长影流）／反复归零（明灭流）／影兽代打（分影流）。
const SHADOW_BUFFS: Array = [
	# --- 长影流 ---
	{"id": "w_len", "name": "长影", "rarity": RARITY_RARE, "max": 3,
		"desc": "影长上限 +20%", "stat": {"shadow_len_pct": 20.0}},
	{"id": "w_recover", "name": "追灯", "rarity": RARITY_COMMON, "max": 3,
		"desc": "影长恢复速度 +30%", "stat": {"shadow_recover_pct": 30.0}},
	{"id": "w_len_dmg", "name": "影杀", "rarity": RARITY_RARE, "max": 3,
		"desc": "每 100 影长使招式伤害 +2%", "stat": {"shadow_len_dmg": 2.0}},
	{"id": "w_hold", "name": "定影", "rarity": RARITY_COMMON, "max": 3,
		"desc": "影长不随静止衰减", "stat": {"shadow_hold": 1.0}},
	{"id": "w_full_dmg", "name": "影满", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "影长满时招式额外 +20% 伤害", "flag": "shadow_full_dmg"},
	# --- 明灭流 ---
	{"id": "w_dim_amp", "name": "明灭·烈", "rarity": RARITY_RARE, "max": 2,
		"desc": "明灭的伤害加成 +15%", "stat": {"shadow_dim_pct": 15.0}},
	{"id": "w_dim_life", "name": "明灭·长", "rarity": RARITY_COMMON, "max": 3,
		"desc": "明灭持续 +1.5 秒", "stat": {"shadow_dim_sec": 1.5}},
	{"id": "w_dim_haste", "name": "明灭·疾", "rarity": RARITY_RARE, "max": 2,
		"desc": "明灭期间攻击速度 +15%", "stat": {"shadow_dim_haste": 15.0}},
	{"id": "w_dim_auto", "name": "自灭", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "明灭期间受伤 -15%，且移速 +10%", "stat": {"shadow_dim_ward": 15.0}},
	{"id": "w_dim_move", "name": "影行", "rarity": RARITY_COMMON, "max": 2,
		"desc": "明灭期间移速 +8%", "stat": {"shadow_dim_move": 8.0}},
	# --- 分影流 ---
	{"id": "w_split_count", "name": "分影·快", "rarity": RARITY_RARE, "max": 2,
		"desc": "影兽出手间隔 -15%", "stat": {"shadow_beast_gap": 15.0}},
	{"id": "w_split_dmg", "name": "分影·烈", "rarity": RARITY_RARE, "max": 3,
		"desc": "影兽伤害 +30%", "stat": {"shadow_beast_pct": 30.0}},
	{"id": "w_split_life", "name": "分影·久", "rarity": RARITY_COMMON, "max": 3,
		"desc": "影兽持续 +2 秒", "stat": {"shadow_beast_sec": 2.0}},
	{"id": "w_split_guard", "name": "代影", "rarity": RARITY_RARE, "max": 1,
		"desc": "影兽存在时本体减伤 10%", "stat": {"shadow_beast_guard": 10.0}},
	{"id": "w_split_erode", "name": "影蚀", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "影兽存在时，本体全部伤害 +12%", "stat": {"shadow_beast_dmg": 12.0}},
	# ===== 机制拓展（2026-11-09）=====
	## 明灭原本是「变强 2 秒」，熄灯把它改成一次爆闪：灯灭的一瞬间炸开。
	{"id": "w_dim_nova", "name": "熄灯", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "进入明灭时，对 300 范围造成 1.2× 物理伤害并击退",
		"stat": {"shadow_dim_nova": 1.2}},
	## 与「明灭流」互补的守势卡：影越长越难被打中。
	{"id": "w_lamp_ward", "name": "守灯", "rarity": RARITY_RARE, "max": 2,
		"desc": "影长满时受到的伤害 -8%", "stat": {"shadow_full_ward": 8.0}},
]

# ===== 折影池（15 条 = 3 流派 × 5）=====
## 机制是「折痕镜像」：每一击同时判定本体与关于折痕的镜像点。
## 三条路：让镜像点成为主输出（双面流）／穿缝位移（穿缝流）／把折痕铺成场地（折叠流）。
const FOLD_BUFFS: Array = [
	# --- 双面流 ---
	{"id": "f_ratio", "name": "双面", "rarity": RARITY_RARE, "max": 3,
		"desc": "折痕镜像伤害比例 +0.08", "stat": {"fold_ratio_add": 0.08}},
	{"id": "f_range", "name": "折远", "rarity": RARITY_COMMON, "max": 3,
		"desc": "折痕判定距离 +15%", "stat": {"fold_range_pct": 15.0}},
	{"id": "f_seam_cd", "name": "裁痕·速", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "裁痕冷却 -40%，折痕额外持续 1 秒", "form": [
			{"form_id": "form_fold_pressmark", "field": "cooldown", "mult_per": -0.40}],
		"stat": {"fold_field_sec": 1.0}},
	{"id": "f_mirror_heal", "name": "镜像归元", "rarity": RARITY_RARE, "max": 2,
		"desc": "镜像落点命中回复 1 点精力", "stat": {"fold_mirror_stam": 1.0}},
	{"id": "f_press", "name": "按纸·重", "rarity": RARITY_COMMON, "max": 3,
		"desc": "按纸伤害 +15%", "form": [
			{"form_id": "form_fold_press", "field": "phys_coeff", "mult_per": 0.15}]},
	# --- 穿缝流 ---
	{"id": "f_cross", "name": "穿缝·锐", "rarity": RARITY_RARE, "max": 3,
		"desc": "穿缝后一击加成 +15%", "stat": {"fold_cross_pct": 15.0}},
	{"id": "f_cross_inv", "name": "穿缝·护", "rarity": RARITY_COMMON, "max": 2,
		"desc": "穿缝后无敌 +0.3 秒", "stat": {"fold_cross_inv": 0.3}},
	{"id": "f_cross_cd", "name": "穿缝·速", "rarity": RARITY_RARE, "max": 3,
		"desc": "跨缝冷却 -20%", "form": [
			{"form_id": "form_fold_stride", "field": "cooldown", "mult_per": -0.20}]},
	{"id": "f_cross_dmg", "name": "穿缝·痕", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "穿缝路径造成 0.8× 物理伤害", "flag": "fold_cross_damage"},
	{"id": "f_cross_move", "name": "过缝", "rarity": RARITY_COMMON, "max": 3,
		"desc": "跨缝位移距离 +20%", "form": [
			{"form_id": "form_fold_stride", "field": "move_forward", "mult_per": 0.20}]},
	# --- 折叠流 ---
	{"id": "f_field_life", "name": "折久", "rarity": RARITY_COMMON, "max": 3,
		"desc": "折痕持续 +3 秒", "stat": {"fold_field_sec": 3.0}},
	{"id": "f_field_radius", "name": "折广", "rarity": RARITY_COMMON, "max": 3,
		"desc": "折痕半径 +20%", "stat": {"fold_field_radius": 20.0}},
	{"id": "f_field_dmg", "name": "折刃", "rarity": RARITY_RARE, "max": 2,
		"desc": "折痕存在时招式伤害 +6%", "stat": {"fold_field_dmg": 6.0}},
	{"id": "f_field_guard", "name": "折守", "rarity": RARITY_RARE, "max": 2,
		"desc": "折痕存在时减伤 8%", "stat": {"fold_field_guard": 8.0}},
	{"id": "f_measure", "name": "量折·准", "rarity": RARITY_RARE, "max": 2,
		"desc": "量折的近缝比例额外 +0.08", "stat": {"fold_near_add": 0.08}},
	# ===== 机制拓展（2026-11-09）=====
	## 穿缝从「位移」变成「布场」：每穿一次，起点也折出一道痕，场地越穿越密。
	{"id": "f_cross_again", "name": "折返", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "穿缝后在起点留下一道折痕", "flag": "fold_cross_again"},
	## 穿到人就能再穿一次：把折影的机动性做成可以连起来的节奏。
	{"id": "f_cross_reset", "name": "连折", "rarity": RARITY_RARE, "max": 1,
		"desc": "穿缝途中穿过敌人时，跨缝冷却立刻转好（每次施放只触发一次）",
		"flag": "fold_cross_reset"},
]

# ===== 符箓池（2026-11-10 重做：连携深度 / 施法经济 / 符方 / 变体）=====
## 核心循环：四张主符放出去，每次施放随机连携符囊里的另一张（70% 效率）。
## 所以这一池的卡全部围绕三件事：**连携更狠**、**施符更省**、**符本身变样**。
##
## ⚠ 连携不再是开局自带（2026-11-11 用户定）：开局四符各自独立施放，
##   必须在三选一里选到「连携」解锁卡（t_chain_unlock，稀有档）才有连携机制。
##   深度卡带 need_flag 字段：未解锁时被 _buff_available 过滤，防废卡。
##
## 字段：
##   flag   机制开关（RogueRun.has_flag）
##   need_flag  前置机制：has_flag(need_flag) 为假时这张卡不进池
##   stat   本局自算乘区（RogueRun.stat），可正可负
##   cap    资源上限（talisman_bag = 符囊格数）
##   attr   走 CharacterData.set_attribute_mod
##   recipe 符方：值 = 基础符 base_id（未拥有则获得，已拥有则 +1 档）
##   variant 变体：值 = 变体 id；base 字段给 roll_choices 过滤用
##
## ⚠ 符方 / 变体卡**必须**带 recipe / variant 字段：三选一靠它过滤，
##   漏了就出现「还没这张符却能选它的改法」这种废卡。
const TALISMAN_BUFFS: Array = [
	# --- 连携解锁 ---
	{"id": "t_chain_unlock", "name": "连携", "rarity": RARITY_RARE, "max": 1,
		"desc": "解锁连携：每放一张符，随机免费连携符囊里的另一张（70% 效率，回 2 灵力）",
		"flag": "tal_chain_on"},
	# --- 连携深度（⚠ 全部 need_flag=tal_chain_on：没解锁连携前不进池，防废卡） ---
	{"id": "t_chain_double", "name": "双符", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "连携改为一次连携 2 张", "flag": "tal_chain_double",
		"need_flag": "tal_chain_on"},
	{"id": "t_chain_full", "name": "顺笔", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "连携不再打折（70% → 100%）", "flag": "tal_chain_full",
		"need_flag": "tal_chain_on"},
	{"id": "t_chain_echo", "name": "回响", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "连携有 25% 概率再多打一张", "flag": "tal_chain_echo",
		"need_flag": "tal_chain_on"},
	{"id": "t_chain_diff", "name": "定弦", "rarity": RARITY_RARE, "max": 1,
		"desc": "连携必定抽不同元素的符", "flag": "tal_chain_diff",
		"need_flag": "tal_chain_on"},
	{"id": "t_chain_cd", "name": "引线", "rarity": RARITY_RARE, "max": 2,
		"desc": "每次连携后，主符冷却 -1.5 秒", "flag": "tal_chain_cd",
		"need_flag": "tal_chain_on"},
	{"id": "t_chain_same", "name": "同气", "rarity": RARITY_RARE, "max": 1,
		"desc": "连续两次连携同元素，第二张 +80%", "flag": "tal_chain_same",
		"need_flag": "tal_chain_on"},
	{"id": "t_chain_focus", "name": "贯注", "rarity": RARITY_COMMON, "max": 2,
		"desc": "手动施符 +15%，连携 -10%", "flag": "tal_focus",
		"need_flag": "tal_chain_on"},
	{"id": "t_chain_mana", "name": "连珠", "rarity": RARITY_RARE, "max": 2,
		"desc": "每次连携额外回 2 点灵力", "stat": {"tal_chain_mana": 2.0},
		"need_flag": "tal_chain_on"},
	# --- 施法经济 ---
	{"id": "t_free", "name": "无墨", "rarity": RARITY_LEGEND, "max": 1,
		# ⚠ 免灵的代价走 stat 而不是写死在 _run_tal_arm 里：
		#   写死会让「疾书 -15%」与「无墨 +25%」无法相加，两卡同时拿就白拿。
		"desc": "符不再消耗灵力；代价是冷却 +25%",
		"flag": "tal_free", "stat": {"tal_cd_pct": 25.0}},
	{"id": "t_mana_max", "name": "灵泉", "rarity": RARITY_COMMON, "max": 3,
		"desc": "灵力上限 +20%", "attr": {"mana_max": {"base_pct": 20.0}}},
	{"id": "t_mana_regen", "name": "回息", "rarity": RARITY_COMMON, "max": 3,
		"desc": "灵力回复 +30%", "attr": {"mana_regen": {"base_pct": 30.0}}},
	{"id": "t_blood_ink", "name": "血墨", "rarity": RARITY_RARE, "max": 1,
		"desc": "灵力不足时用气血代替（1 灵 = 1.5% 最大气血）", "flag": "tal_blood_ink"},
	{"id": "t_cd", "name": "疾书", "rarity": RARITY_RARE, "max": 2,
		"desc": "所有符冷却 -15%", "stat": {"tal_cd_pct": -15.0}},
	# 绝笔：与「无墨」互为镜像 —— 无墨是「免灵换冷却」，绝笔是「免冷却换伤害」。
	# ⚠ 必须带代价：这一池的规矩是「改行为 / 带取舍」，发一张纯免冷却的卡会把
	#   四符循环直接压成无脑连点，构筑就没有选择了。
	{"id": "t_no_cd", "name": "绝笔", "rarity": RARITY_LEGEND, "max": 1,
		"desc": "符不再有冷却；代价是每张符伤害 -20%", "flag": "tal_no_cd"},
	{"id": "t_mana_kill", "name": "引灵", "rarity": RARITY_COMMON, "max": 3,
		"desc": "击杀回复 5 点灵力", "stat": {"mana_on_kill": 5.0}},
	{"id": "t_hold", "name": "蓄势", "rarity": RARITY_RARE, "max": 1,
		"desc": "8 秒没有施符，下一张符 +50%", "flag": "tal_hold"},
	{"id": "t_bag", "name": "开匣", "rarity": RARITY_RARE, "max": 1,
		"desc": "符囊 +1 格", "cap": {"talisman_bag": 1}},
	# --- 符方 ×10：未拥有则获得，已拥有则 +1 档（最高元婴）---
	{"id": "t_recipe_jin", "name": "符方·金锋", "rarity": RARITY_RARE, "max": 4,
		"desc": "金锋符：未拥有则获得，已有则 +1 档", "recipe": "tal_jinfeng"},
	{"id": "t_recipe_fire", "name": "符方·火球", "rarity": RARITY_RARE, "max": 4,
		"desc": "火球符：未拥有则获得，已有则 +1 档", "recipe": "tal_huoqiu"},
	{"id": "t_recipe_thunder", "name": "符方·引雷", "rarity": RARITY_RARE, "max": 4,
		"desc": "引雷符：未拥有则获得，已有则 +1 档", "recipe": "tal_yinlei"},
	{"id": "t_recipe_wood", "name": "符方·木缚", "rarity": RARITY_RARE, "max": 4,
		"desc": "木缚符：未拥有则获得，已有则 +1 档", "recipe": "tal_muling"},
	{"id": "t_recipe_water", "name": "符方·水愈", "rarity": RARITY_RARE, "max": 4,
		"desc": "水愈符：未拥有则获得，已有则 +1 档", "recipe": "tal_shuihui"},
	{"id": "t_recipe_wind", "name": "符方·风疾", "rarity": RARITY_RARE, "max": 4,
		"desc": "风疾符：未拥有则获得，已有则 +1 档", "recipe": "tal_fengji"},
	{"id": "t_recipe_earth", "name": "符方·石附", "rarity": RARITY_RARE, "max": 4,
		"desc": "石附符：未拥有则获得，已有则 +1 档", "recipe": "tal_tushi"},
	{"id": "t_recipe_ice", "name": "符方·凝霜", "rarity": RARITY_RARE, "max": 4,
		"desc": "凝霜符（试炼专属）：获得或 +1 档", "recipe": "tal_bingning"},
	{"id": "t_recipe_light", "name": "符方·折光", "rarity": RARITY_RARE, "max": 4,
		"desc": "折光符（试炼专属）：获得或 +1 档", "recipe": "tal_zheguang"},
	{"id": "t_recipe_dark", "name": "符方·噬元", "rarity": RARITY_RARE, "max": 4,
		"desc": "噬元符（试炼专属）：获得或 +1 档", "recipe": "tal_shiyuan"},
	# --- 变体 ×20：每张基础符两个，互斥二选一 ---
	{"id": "t_var_jinfeng_myriad", "name": "改符·万剑", "rarity": RARITY_RARE, "max": 1,
		"desc": "金锋符 → 万剑符：五道剑气扇形齐发",
		"variant": "talv_jinfeng_myriad", "base": "tal_jinfeng"},
	{"id": "t_var_jinfeng_break", "name": "改符·断锋", "rarity": RARITY_RARE, "max": 1,
		"desc": "金锋符 → 断锋符：穿透直线，命中挂符裂",
		"variant": "talv_jinfeng_break", "base": "tal_jinfeng"},
	{"id": "t_var_huoqiu_rain", "name": "改符·火雨", "rarity": RARITY_RARE, "max": 1,
		"desc": "火球符 → 火雨符：一次落三团火",
		"variant": "talv_huoqiu_rain", "base": "tal_huoqiu"},
	{"id": "t_var_huoqiu_fenxin", "name": "改符·焚心", "rarity": RARITY_RARE, "max": 1,
		"desc": "火球符 → 焚心符：烧三秒后从里面炸开",
		"variant": "talv_huoqiu_fenxin", "base": "tal_huoqiu"},
	{"id": "t_var_yinlei_chain", "name": "改符·连锁雷", "rarity": RARITY_RARE, "max": 1,
		"desc": "引雷符 → 连锁雷符：在敌人之间弹跳",
		"variant": "talv_yinlei_chain", "base": "tal_yinlei"},
	{"id": "t_var_yinlei_prison", "name": "改符·雷狱", "rarity": RARITY_RARE, "max": 1,
		"desc": "引雷符 → 雷狱符：脚下积成一池雷",
		"variant": "talv_yinlei_prison", "base": "tal_yinlei"},
	{"id": "t_var_muling_tangle", "name": "改符·缠根", "rarity": RARITY_RARE, "max": 1,
		"desc": "木缚符 → 缠根符：缠住并持续收伤",
		"variant": "talv_muling_tangle", "base": "tal_muling"},
	{"id": "t_var_muling_spirit", "name": "改符·青藤灵", "rarity": RARITY_RARE, "max": 1,
		"desc": "木缚符 → 符灵·青藤：召出符灵替你缠人",
		"variant": "talv_muling_spirit", "base": "tal_muling"},
	{"id": "t_var_shuihui_tide", "name": "改符·潮汐", "rarity": RARITY_RARE, "max": 1,
		"desc": "水愈符 → 潮汐符：铺一滩水，自己回血、敌人变慢",
		"variant": "talv_shuihui_tide", "base": "tal_shuihui"},
	{"id": "t_var_shuihui_marrow", "name": "改符·洗髓", "rarity": RARITY_RARE, "max": 1,
		"desc": "水愈符 → 洗髓符：立刻回一大截并清负面",
		"variant": "talv_shuihui_marrow", "base": "tal_shuihui"},
	{"id": "t_var_fengji_gale", "name": "改符·罡风", "rarity": RARITY_RARE, "max": 1,
		"desc": "风疾符 → 罡风符：清掉弹幕并把人吹开",
		"variant": "talv_fengji_gale", "base": "tal_fengji"},
	{"id": "t_var_fengji_feather", "name": "改符·风羽", "rarity": RARITY_RARE, "max": 1,
		"desc": "风疾符 → 风羽符：冲刺一段，下一张符更强",
		"variant": "talv_fengji_feather", "base": "tal_fengji"},
	{"id": "t_var_tushi_array", "name": "改符·石阵", "rarity": RARITY_RARE, "max": 1,
		"desc": "石附符 → 石阵符：立起石阵吸弹幕、困敌人",
		"variant": "talv_tushi_array", "base": "tal_tushi"},
	{"id": "t_var_tushi_boulder", "name": "改符·磐石", "rarity": RARITY_RARE, "max": 1,
		"desc": "石附符 → 磐石符：石甲吸收伤害，碎时反击",
		"variant": "talv_tushi_boulder", "base": "tal_tushi"},
	{"id": "t_var_bingning_seal", "name": "改符·冰封", "rarity": RARITY_RARE, "max": 1,
		"desc": "凝霜符 → 冰封符：直接冻住，冰裂再补一刀",
		"variant": "talv_bingning_seal", "base": "tal_bingning"},
	{"id": "t_var_bingning_armor", "name": "改符·霜甲", "rarity": RARITY_RARE, "max": 1,
		"desc": "凝霜符 → 霜甲符：谁打你谁跟着发冷",
		"variant": "talv_bingning_armor", "base": "tal_bingning"},
	{"id": "t_var_zheguang_pillar", "name": "改符·聚光", "rarity": RARITY_RARE, "max": 1,
		"desc": "折光符 → 聚光符：光柱钉住一片区域",
		"variant": "talv_zheguang_pillar", "base": "tal_zheguang"},
	{"id": "t_var_zheguang_heal", "name": "改符·光愈", "rarity": RARITY_RARE, "max": 1,
		"desc": "折光符 → 光愈符：回血并短暂无敌",
		"variant": "talv_zheguang_heal", "base": "tal_zheguang"},
	{"id": "t_var_shiyuan_blink", "name": "改符·影遁", "rarity": RARITY_RARE, "max": 1,
		"desc": "噬元符 → 影遁符：瞬移到背后，下一张符更强",
		"variant": "talv_shiyuan_blink", "base": "tal_shiyuan"},
	{"id": "t_var_shiyuan_array", "name": "改符·噬灵阵", "rarity": RARITY_RARE, "max": 1,
		"desc": "噬元符 → 噬灵阵：铺一片暗，伤人喂己",
		"variant": "talv_shiyuan_array", "base": "tal_shiyuan"},
]

# ===== 全部卡池按流派索引 =====
const POOLS: Dictionary = {
	"generic": GENERIC_BUFFS,
	"sword": SWORD_BUFFS,
	"scar": SCAR_BUFFS,
	"beast": BEAST_BUFFS,
	"yinyang": YINYANG_BUFFS,
	"array": ARRAY_BUFFS,
	"qi": QI_BUFFS,
	"thunder": THUNDER_BUFFS,
	"sun": SUN_BUFFS,
	"calamity": CALAMITY_BUFFS,
	"mirror": MIRROR_BUFFS,
	"shadow": SHADOW_BUFFS,
	"fold": FOLD_BUFFS,
	"talisman": TALISMAN_BUFFS,
}
## 流派显示名（解锁进度 UI 用）
const FAMILY_NAME: Dictionary = {
	"generic": "通用",
	"sword": "剑修",
	"scar": "刀修",
	"beast": "虎妖",
	"yinyang": "两仪",
	"array": "阵旗",
	"qi": "气环",
	"thunder": "判词雷",
	"sun": "逐日",
	"calamity": "三灾",
	"mirror": "镜身",
	"shadow": "投影",
	"fold": "折影",
	"talisman": "符箓",
}
## 流派解锁所需历史最高层（0 = 初始开放）
const FAMILY_UNLOCK_FLOOR: Dictionary = {
	"generic": 0, "sword": 0, "scar": 0, "beast": 0,
	# ⚠ 符箓 2026-11-09 改回初始开放（原 50）：玩家要求一进试炼就能选符箓。
	#   它是唯一自带独立资源（符匣）的流派，摆在「新手三套」里也不算误导；
	#   后续新流派仍按历史最高层往上排，别再占用 0 档。
	"talisman": 0,
	"yinyang": 5, "array": 10, "qi": 15, "thunder": 20,
	"sun": 25, "calamity": 30, "mirror": 35, "shadow": 40, "fold": 45,
}


# ===== 数值查询 =====

## 教学缓冲取值：越界一律钉在最后一项（第 4 层起 1.0）
static func floor_relief(table: Array, floor_no: int) -> float:
	var i := clampi(maxi(1, floor_no) - 1, 0, table.size() - 1)
	return float(table[i])


## 第 floor_no 层的小怪血量 / 攻击
## ⚠ 缓冲乘在成长曲线**外面**：第 4 层起 relief=1.0，pow() 原样保留，
##   所以后期曲线一分没动，只把前 3 层压成「教学层」。
static func minion_hp(def: Dictionary, floor_no: int) -> float:
	return float(def.get("hp", 80.0)) * pow(MINION_HP_GROWTH, float(maxi(1, floor_no) - 1)) 		* floor_relief(FLOOR_HP_RELIEF, floor_no)


static func minion_atk(def: Dictionary, floor_no: int) -> float:
	return float(def.get("atk", 8.0)) * pow(MINION_ATK_GROWTH, float(maxi(1, floor_no) - 1)) 		* floor_relief(FLOOR_ATK_RELIEF, floor_no)


## 第 floor_no 层某 BOSS 的血量 / 攻击（保留原 BOSS 招式，只换这三组数值）
static func boss_hp(boss_id: String, floor_no: int) -> float:
	var tier := float(BOSS_TIER.get(boss_id, 1.0))
	return BOSS_HP_BASE * pow(BOSS_HP_GROWTH, float(maxi(1, floor_no) - 1)) * tier 		* floor_relief(FLOOR_BOSS_RELIEF, floor_no)


static func boss_atk(boss_id: String, floor_no: int) -> float:
	var tier := float(BOSS_TIER.get(boss_id, 1.0))
	return BOSS_ATK_BASE * pow(BOSS_ATK_GROWTH, float(maxi(1, floor_no) - 1)) * tier 		* floor_relief(FLOOR_BOSS_RELIEF, floor_no)


## 本波出几只小怪（不含精英）：按层取 WAVE_COUNTS 的对应行
static func wave_size(floor_no: int, wave_no: int) -> int:
	var tier := clampi(maxi(1, floor_no) - 1, 0, WAVE_COUNTS.size() - 1)
	var row: Array = WAVE_COUNTS[tier]
	return int(row[clampi(wave_no - 1, 0, row.size() - 1)])


## 本波出怪：每小关 3 波，数量见 WAVE_COUNTS；
## 第 3 小关第 3 波把 1 只小怪换成精英，且**只在 ELITE_FROM_FLOOR 层起**。
## 第 1~3 层只出鼠 / 射手，第 4 层起加入石傀（按层随机，不写死顺序）
static func roll_wave(floor_no: int, stage_no: int, wave_no: int) -> Array:
	var pool: Array = MINIONS_EARLY.duplicate() if floor_no <= 3 else MINIONS_MID.duplicate()
	var out: Array = []
	var count := wave_size(floor_no, wave_no)
	if floor_no >= ELITE_FROM_FLOOR 			and stage_no >= STAGES_PER_FLOOR - 1 and wave_no >= WAVES_PER_STAGE:
		count = maxi(1, count - 1)
		out.append("rogue_elite")
	for i in count:
		out.append(String(pool[randi() % pool.size()]))
	return out


## 本次三选一的候选（由 RogueRun 去重 / 按叠层过滤后调用）
## ⚠ 直接遍历 POOLS 而不是逐池手写 append_array：新增流派时忘登记一次，
##   那一套卡就永远抽不到（且不报错，只有玩到那层才发现）。
static func all_buffs() -> Array:
	var out: Array = []
	for fam in POOLS.keys():
		for raw in POOLS[fam]:
			out.append(raw)
	return out


static func get_buff(buff_id: String) -> Dictionary:
	for b in all_buffs():
		if String((b as Dictionary).get("id", "")) == buff_id:
			return b
	return {}


static func family_of(buff_id: String) -> String:
	for fam in POOLS.keys():
		for raw in POOLS[fam]:
			if String((raw as Dictionary).get("id", "")) == buff_id:
				return String(fam)
	return ""


## 稀有度 → 权重（不在表里按普通算）
static func rarity_weight(rarity: String) -> float:
	return float(RARITY_WEIGHT.get(rarity, RARITY_WEIGHT[RARITY_COMMON]))


## 某增益的叠加上限（传说固定 1 层）
static func stack_cap(buff_id: String) -> int:
	var def := get_buff(buff_id)
	if def.is_empty():
		return 1
	if String(def.get("rarity", "")) == RARITY_LEGEND:
		return MAX_STACKS_LEGEND
	return int(def.get("max", MAX_STACKS))


## 带符号整数文案（`%+d` 在 GDScript 的 String % 里不可靠，自己拼）
static func _signed_num(v: float) -> String:
	var iv := int(round(v))
	return ("+%d" % iv) if iv >= 0 else ("%d" % iv)


## 某张卡叠到 stacks 层时「当前实际吃到多少」的一行文案（本局增益面板用）。
##
## ⚠ 只对 attr / cap 这两类**口径确定**的载体给数值：
##   attr 走 CharacterData.attribute() 的同一套字段（flat / base_pct / mult），
##   cap 走 RogueRun.cap() 的同一张 CAP_BASE —— 两边都是线性叠加，乘层数是准的。
## ⚠ stat / form 故意不翻译：那 142 个 key 各自口径不同（有的按点、有的按秒、
##   有的只在特定条件下生效），硬凑一句话只会写出与实战不符的假数字。
##   这类回「每层独立叠加 · 当前 N 层」，desc 已经把每层效果写清楚了，玩家自己就能乘。
## ⚠ flag 是一次性开关（拿到即生效、不随层数变化），绝不能说「×N」。
static func buff_stack_line(buff_id: String, stacks: int) -> String:
	if stacks <= 0:
		return ""
	var def := get_buff(buff_id)
	if def.is_empty():
		return ""
	var n := float(stacks)
	var parts: Array = []

	var attr: Dictionary = def.get("attr", {})
	for raw_id in attr.keys():
		var aid := String(raw_id)
		var m: Dictionary = attr[aid]
		# 百分比词条 `xxx_pct`：作用在「本体属性的百分比乘区」上，
		# 名字取本体（否则 AttributeDB 认不出 `physical_resist_pct`，会印原始 key）
		var pct_suffix := aid.ends_with("_pct")
		var shown := AttributeDB.attr_name(aid.trim_suffix("_pct") if pct_suffix else aid)
		if m.has("flat"):
			parts.append("%s %s%s" % [
				shown, _signed_num(float(m["flat"]) * n), "%" if pct_suffix else ""])
		if m.has("base_pct"):
			parts.append("%s %s%%（基于基础）" % [shown, _signed_num(float(m["base_pct"]) * n)])
		if m.has("mult"):
			parts.append("%s ×%.2f" % [shown, pow(float(m["mult"]), n)])

	var cap: Dictionary = def.get("cap", {})
	for key in cap.keys():
		parts.append("%s %s" % [
			String(CAP_NAME.get(String(key), String(key))),
			_signed_num(float(cap[key]) * n)])

	if not parts.is_empty():
		return "当前 " + " · ".join(parts)
	if String(def.get("flag", "")) != "":
		return "机制已激活（一次性开关，不叠层）"
	return "每层独立叠加 · 当前 %d 层" % stacks
