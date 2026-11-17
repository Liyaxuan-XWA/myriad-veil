class_name QuestDB
extends RefCounted
## 顺序任务表（2026-11-11 用户定）：把旧「教学清单」重置成真正的任务面板。
##
## 规则：
##   - **顺序解锁**：必须一个一个完成，`current()` = 第一条不在 done 表里的任务；
##     只有当前任务的 ev / cond 会被判定，完成一个立刻解锁下一个。
##   - `ev`   = Tutorial.note 事件键（带参全等、不带参只比基础名，与教学步骤机同语义）；
##     `cond` = 持久状态轮询键（Quest._cond_met，事件被乱序丢掉时的兜底）。
##     两者可同时配：cond 优先（存档级事实），事件与会话缓冲兜底。
##   - `detail` = 点开条目看到的指引文案（一句话，说清「去哪做」），🚫 不写数字配方。
##
## ⚠ 静态审计（probe_quest_panel）：ev / cond 字面量必须能在源码里找到埋点或实现，
##   写错 = 任务永远完不成（同教学探针 ⑩ 的教训）。

const QUESTS: Array = [
	# —— 击败虎妖：任务 1。boss_progress 是存档级状态（battle_resolver 结算写入），
	#    所以只配 cond 轮询，不需要事件。
	{"id": "q_kill_huyao", "title": "击败虎妖",
		"detail": "去万界秘境的凡界，挑战虎妖。走近漩涡传送门按 F 进入。",
		"cond": "boss_killed:boss_huyao"},
	{"id": "q_enhance", "title": "强化装备",
		"detail": "去装备锻造台：把装备放上铁砧，拿起锤子敲一次砧面。",
		"ev": "forge_enhance"},
	{"id": "q_tower", "title": "挑战万界塔",
		"detail": "去万界塔选一层，点右下角的「挑战」并获胜。",
		"ev": "tower_clear", "cond": "tower_cleared_any"},
	{"id": "q_equip_skill", "title": "装备功法",
		"detail": "按 Y 打开功法库，把领悟到的功法装配到 Q/E/R/T 槽位。",
		"ev": "skill_slotted"},
	{"id": "q_break_realm", "title": "突破境界",
		# 第二段是用户 2026-11-12 让补的：告诉玩家「修为从哪来」，不然只知道要材料
		"detail": "收集破境材料，打开角色面板突破一次境界（大小突破皆可）。\n修为达到瓶颈就可以突破：挂机打坐、击败主线 BOSS、大陆探索都能获得修为。",
		"ev": "realm_breakthrough", "cond": "realm_broken_any"},
	{"id": "q_boss_material", "title": "击败首领获得突破材料",
		"detail": "在大世界或万界位面击败首领，拾取掉落的破境材料。",
		"ev": "boss_died", "cond": "has_pojing_material"},
	{"id": "q_rogue", "title": "完成一局试炼模式",
		"detail": "从万界塔进入试炼之路，完成一局（通关、死亡或主动退出均可）。",
		"ev": "rogue_run_done"},
	{"id": "q_match", "title": "完成一局棋坛模式",
		"detail": "去棋坛完成一局对弈，无论胜负。",
		"ev": "match_finished"},
	{"id": "q_brew_pill", "title": "制作一次丹药",
		"detail": "去炼丹房选配方、投料开炉，成功炼出一颗丹药。",
		"ev": "craft_done:pill"},
	{"id": "q_use_pill", "title": "使用一次丹药",
		"detail": "先在角色面板（Tab）的背包「丹药」里点一颗，按「装入轮盘（药 1）」；战斗中按 G 开轮盘，点其中一格或按 1/2/3 使用，一次吃 1 颗。",
		"ev": "pill_used"},
	{"id": "q_draw_talisman", "title": "制作一次符纸",
		"detail": "去制符台画一张符，成品会自动收进符匣。",
		"ev": "craft_done:talisman"},
	# 11-11 口径改回主模式：装配符箓的地方是**制符台 / 功法库的符匣**，试炼里没有制符台。
	# 旧文案写「试炼中把符装配到 Q/E/R/T」会把玩家指到一个不存在该操作的地方，
	# 而且完成事件 run_talisman_used 只在**选了符箓流派**的那一局才可能发——
	# 玩剑修/刀修的人会被这条卡死。现在考的是人人都会做的主模式基础操作。
	{"id": "q_use_talisman", "title": "使用一次符纸",
		"detail": "在制符台或功法库打开符匣，把符装进 Q/E/R/T，战斗中按对应键施放。",
		"ev": "talisman_used"},
	# 11-12 新增（用户指定）：打大陆练气区的核心首领拿底髓。
	# ⚠ 区域必须钉死：埋点原来发的是裸 `world_core_kill`，四个区的核心首领共用一个键 ——
	#   只配裸 ev 的话，玩家先打结丹区核心也会把这条「练气区」的任务勾掉。
	#   所以 ① 埋点带上 region_id，② ev 写全 `world_core_kill:world_lianqi`（带参 = 全等匹配），
	#   ③ cond 用存档级事实 `is_core_killed(REGION_LIANQI)` 兜底（先打完再解锁任务也能勾）。
	#   老的教学步骤（tutorial_db 里 ev 写裸名）按基础名匹配，不受加后缀影响。
	{"id": "q_lianqi_core", "title": "击败练气区核心首领",
		"detail": "击败练气区「青岚野」中央的核心首领青岚古猿，取得筑基底髓。",
		"ev": "world_core_kill:world_lianqi", "cond": "lianqi_core_killed"},
]


static func get_quest(id: String) -> Dictionary:
	for raw in QUESTS:
		var q: Dictionary = raw
		if String(q.get("id", "")) == id:
			return q
	return {}
