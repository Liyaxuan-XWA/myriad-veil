class_name TutorialDB
extends RefCounted
## 新手指引 · 步骤表（2026-11-10 用户定：全流程分章、非纯文字）
##
## 这里只放**数据**：每步长什么样、怎么算完成、聚光指向谁。
## 渲染在 tutorial_overlay.gd，推进在 tutorial_runner.gd。
##
## 字段说明：
##   id      唯一键，也是存档里的完成标记（改名 = 老玩家会重看这一步，慎改）
##   text    清单一行的文案（**玩家视角**，一句说完，不写死数值）
##   tip     卡片上的补充（可空）
##   anchor  聚光目标：
##             "meta:forge.enhance"        → 找 set_meta("tut", "...") 的控件
##             "path:Facilities/DomainGate" → 当前场景里的节点路径
##             ""                          → 不聚光，只出卡片
##   ev      事件名（GameState.tut_event）。空 = 不看事件
##   cond    状态兜底键（每 0.25 秒轮询一次）。空 = 不看状态
##   n       需要累计的次数（ev / cond 共用，默认 1）
##   manual  true = 卡片上点「知道了」才算过（纯说明步骤）
##
## 章节 trigger：new（新号进主城）/ battle（进 BOSS 战）/ world（进大世界）
##               panel:<面板键> / event:<事件名> / after_huyao（首杀虎妖，战斗结算里报，见主城）
##   一章可写多个触发键，逗号分隔。
## 章节 need：可选前置状态键（复用 Tutorial._cond_met），不满足就绝不开章。
##   ⚠ 键写错 = 这章永远不开（静态审计会拦，见 probe_tutorial ⑩）。
## ⚠ 面板键来自 SystemPanel.panel_key（脚本文件名去掉 _panel），改名会断掉触发。

const CHAPTERS: Array = [
	{
		"id": "c1", "title": "开局带路", "trigger": "new",
		"steps": [
			{"id": "c1_move", "text": "用 WASD 走两步（触屏拖左侧摇杆）",
				"tip": "走到发光的设施旁边，按 F 或直接点它；触屏点右下那颗「进入」。",
				"anchor": "", "ev": "moved", "n": 240.0},
			{"id": "c1_gate", "text": "去「万界秘境」——打 BOSS、掉装备",
				"tip": "它在你右手边，名字叫万界秘境。",
				"anchor": "path:Facilities/DomainGate", "ev": "panel_opened:domain_panel"},
			{"id": "c1_enter", "text": "选「凡界」，点进入",
				"tip": "第一场战斗会手把手教你弹刀。",
				"anchor": "meta:domain.enter", "ev": "battle_started:domain"},
			{"id": "c1_win", "text": "打赢这只 BOSS",
				"tip": "输了不掉东西，回城再来就是。",
				"anchor": "", "ev": "boss_died", "cond": "any_boss_killed"},
			{"id": "c1_bag", "text": "回城打开背包，看看掉了什么",
				"tip": "装备要点一下才穿上，不会自动穿。",
				"anchor": "meta:hud.bag", "ev": "bag_opened"},
		],
	},
	{
		"id": "c2", "title": "战斗基础", "trigger": "battle",
		"steps": [
			{"id": "c2_attack", "text": "左键攻击，先打三下",
				"text_touch": "点「攻」键，先打三下",
				"tip": "第三下是终结技，伤害更高。",
				"anchor": "", "ev": "attack_hit", "n": 3},
			{"id": "c2_parry", "text": "它抬手就按右键弹刀",
				"text_touch": "它抬手就点右下的「弹」键弹刀",
				"tip": "前三次抬手会停下来等你，弹满了三次就算学会。",
				"anchor": "", "ev": "parry_success", "n": 3},
			{"id": "c2_dash", "text": "空格闪避，不吃这一下",
				"text_touch": "点「闪」键，不吃这一下",
				"tip": "闪避费精力，别一直按。",
				"anchor": "", "ev": "dash_used", "n": 1},
			# ⚠ 这里**不能**放「按 Q 放功法」：开局 learned_skills 为空（见 CharacterData §2.9），
			#   空槽按 Q 什么都不发生（player._poll_skill_keys 直接 continue）→ 这一步永远做不完，
			#   玩家只能跳过。功法教学挪到 c5_cast（首通万界塔拿到第一门功法之后）。
			# ⚠ 11-12 修正：这条原来写的是「头顶两条横条 + 身侧五小格」，那是已被删掉的旧
			#   HUD（HealthBar/ManaBar/StaminaBar 节点已从 player.tscn 撤走）。现在读的是
			#   ResourceRing：血=左半弧、灵=右半弧、精=环内底前一排光点。
			#   另外「脱战后回得更快」也**不成立**：精力恢复只看 stamina_regen_seconds
			#   （属性「精力恢复」换算），与战斗状态无关；真正不回的是**力竭期间**。
			{"id": "c2_blood", "text": "周身一环：左气血、右灵力",
				"tip": "两条弧从脚下往头顶填；环内一排光点是精力，闪避、弹刀、挨打都吃它，打空会力竭，那几秒不回。",
				"anchor": "", "ev": "", "manual": true},
		],
	},
	{
		"id": "c3", "title": "装备与锻造", "trigger": "panel:forge_panel",
		"steps": [
			{"id": "c3_equip", "text": "把装备穿到槽里",
				"tip": "点空槽选装备，穿上属性立刻变。",
				"anchor": "meta:forge.slot", "ev": "gear_equipped"},
			{"id": "c3_enhance", "text": "强化一次，吃锻造晶石",
				"tip": "强化只加主属性，失败不降级。",
				"anchor": "meta:forge.enhance", "ev": "forge_enhance"},
			# 强化与进阶都是「点砧面」，共用同一个锚点（表里不要再写 forge.advance）
			{"id": "c3_advance", "text": "进阶一次，跨品质档",
				"tip": "进阶要同部位材料，别把材料卖了。",
				"anchor": "meta:forge.enhance", "ev": "forge_advance"},
			{"id": "c3_synth", "text": "去「熔铸」页合成法宝",
				"tip": "三件同源材料同投，能召唤 BOSS 的法宝。",
				"anchor": "meta:forge.tab_synth", "ev": "forge_synth"},
		],
	},
	{
		# 2026-11-12 用户定：这一步不再跟着锻造章走（原来只要开着锻造面板就会弹，
		# 玩家点装备详情也会看到它）。改成**拿到能参与合成的材料**才触发，
		# 且全局只教一次 —— 做完/跳过之后本章没有未完成步骤，再捡材料也不会重来。
		"id": "c3b", "title": "合成指引", "trigger": "event:craft_material",
		"steps": [
			{"id": "c3_where", "text": "点开背包里的材料看「合成指引」",
				"tip": "写着这件材料该去哪合成、和谁一起投。",
				"anchor": "meta:forge.material", "ev": "material_inspect"},
		],
	},
	{
		"id": "c4", "title": "生活技艺", "trigger": "panel:alchemy_panel",
		"steps": [
			{"id": "c4_alchemy", "text": "炼一炉丹：选配方、投料、开炉",
				"tip": "火候别过头，糊了就白搭材料。",
				"anchor": "meta:alchemy.brew", "ev": "craft_done:pill"},
			{"id": "c4_talisman", "text": "去制符台画一张符",
				"tip": "符进「符匣」，不占背包格。",
				"anchor": "meta:talisman.draw", "ev": "craft_done:talisman"},
			{"id": "c4_load", "text": "把符装到 Q/E/R/T 才能用",
				"tip": "打开功法库装符，和功法抢同一排槽。",
				"anchor": "meta:talisman.assign", "ev": "talisman_loaded"},
			{"id": "c4_warehouse", "text": "仓库存一次东西",
				"tip": "炼丹制符只认背包，用之前要先取回来。",
				"anchor": "meta:warehouse.tab", "ev": "warehouse_move"},
		],
	},
	{
		# 触发键可以逗号分隔（见 Tutorial.maybe_start）：首杀「虎妖」在战斗结算里当场开链，
		# 玩家自己先点开塔面板时也兜底触发。
		# need = 打过虎妖本体：任何入口在没打过前都不许把这一章带出来
		# （塔第 1 层就是虎妖投影，没打过本体连层都进不去，提前指过去只会撞墙）。
		# ⚠ 步骤顺序 = 真实事件顺序：步骤机只监听「当前这一步」的事件，玩家提前做了
		#   后面的事会被丢掉。所以每个关键步骤都配了 cond 兜底（见 Tutorial._cond_met）——
		#   cond 读的是**持久状态**，事件在错误窗口里丢掉后，步一激活轮询立刻补完。
		"id": "c5", "title": "首战之后", "trigger": "after_huyao,panel:tower_panel",
		"need": "boss_killed:boss_huyao",
		"steps": [
			{"id": "c5_crystal", "text": "捡起 BOSS 掉落的锻造晶石",
				"tip": "走近掉落物按 F 拾取。晶石是强化装备的唯一媒介。",
				"anchor": "meta:drop.item", "ev": "item_picked:mat_duanzaojingshi",
				"cond": "has_crystal"},
			{"id": "c5_return", "text": "点左上角「返回原初位面」回城",
				"tip": "掉落已经进背包，回城就能用。",
				"anchor": "meta:combat.return", "ev": "returned_realm", "cond": "in_realm"},
			{"id": "c5_forge", "text": "去「装备锻造台」打开锻造",
				"tip": "强化、熔铸都在这里做。",
				"anchor": "path:Facilities/Equipment", "ev": "panel_opened:forge_panel"},
			{"id": "c5_place", "text": "把身上的铁剑拖到铁砧上",
				"tip": "按住身上的铁剑挂签拖过去；点背包里的装备也能直接上砧。",
				"anchor": "meta:forge.enhance", "ev": "forge_place", "cond": "forge_anvil_filled"},
			{"id": "c5_hammer", "text": "拿起石台上的锤子",
				"tip": "点锤子拿在手里，才能敲砧面。",
				"anchor": "meta:forge.hammer", "ev": "forge_hammer", "cond": "forge_hammer_held"},
			# 教学必成（2026-11-10 用户定）：这一步激活期间强化 100% 成功，
			# 由 Tutorial runner 把 force_success 同步到 CharacterData.force_enhance_success
			{"id": "c5_enhance", "text": "点击砧面，敲一锤强化铁剑",
				"tip": "教学期间强化必定成功，晶石自动消耗。",
				"anchor": "meta:forge.enhance", "ev": "forge_enhance", "force_success": true},
			{"id": "c5_take", "text": "点「取下」，把铁剑收回背包",
				"tip": "强化完取下来，才能重新穿回身上。",
				"anchor": "meta:forge.take", "ev": "forge_take", "cond": "forge_anvil_empty"},
			{"id": "c5_equip", "text": "把铁剑拖回身上的武器格",
				"tip": "从背包拖到左上的装备格；强化加的属性立刻生效。",
				"anchor": "meta:forge.worn", "ev": "gear_equipped", "cond": "weapon_equipped"},
			# ⚠ 2026-11-10 用户要：首杀虎妖回原初位面就该把玩家带到塔前。
			#   塔是功法唯一来源，不主动指路新号会一直没功法可放（c2 因此删过一步）。
			#   锚点是主城的塔设施本身；打开塔面板即算到过（该事件由 SystemPanel 报）。
			{"id": "c5_go", "text": "去「万界塔」——功法只能从这儿拿",
				"tip": "每层通关必感悟 1 门功法，是你唯一的功法来源。",
				"anchor": "path:Facilities/Tower", "ev": "panel_opened:tower_panel"},
			{"id": "c5_pick", "text": "选第 1 层——正是虎妖的投影",
				"tip": "打过本体才解锁投影层；每层记录最快通关时间。",
				"anchor": "meta:tower.floor", "ev": "tower_floor_pick"},
			{"id": "c5_start", "text": "点右下角的「挑战」进入战斗",
				"tip": "投影比本体弱一些，打法完全一样。",
				"anchor": "meta:tower.challenge", "ev": "tower_challenge"},
			{"id": "c5_first", "text": "击败虎妖的投影",
				"tip": "刚在秘境打过它，同样的招式同样弹。",
				"anchor": "", "ev": "boss_died"},
			{"id": "c5_insight", "text": "在感悟面板点「确认收下」",
				"tip": "首通必得一门虎妖的功法，确认后才入册。",
				"anchor": "meta:insight.confirm", "ev": "skill_learned"},
			{"id": "c5_loot", "text": "捡起投影掉落的晶石",
				"tip": "和秘境一样，走近按 F 拾取。",
				"anchor": "meta:drop.item", "ev": "item_picked:mat_duanzaojingshi",
				"cond": "has_crystal"},
			{"id": "c5_back", "text": "点「返回原初位面」回城",
				"tip": "功法已经在册，回城去装配。",
				"anchor": "meta:combat.return", "ev": "returned_realm", "cond": "in_realm"},
			{"id": "c5_book", "text": "按 Y 打开功法库",
				"tip": "触屏玩家点右上角的功法库图标。",
				"anchor": "meta:hud.skill.key", "ev": "panel_opened:skill_panel"},
			{"id": "c5_equip_skill", "text": "把新功法装到 Q 槽",
				"tip": "点 Q 槽的「装配」，选刚感悟的那门。",
				"anchor": "meta:hud.skill.book", "ev": "skill_slotted",
				"cond": "skill_in_slot_q"},
			# 新号开局无功法，这里才是第一次真正能按出功法的地方（c2 已不放这步）
			{"id": "c5_cast", "text": "回战斗按 Q 放一次新功法",
				"text_touch": "回战斗点「功1」键放一次新功法",
				"tip": "Q/E/R/T 对应功法库的四个装配位；灵力不够时图标变灰。",
				"anchor": "meta:hud.skill.q", "ev": "skill_used"},
		],
	},
	{
		"id": "c6", "title": "试炼之路", "trigger": "event:rogue_tab",
		"steps": [
			{"id": "c6_family", "text": "选一套流派",
				"tip": "每套开局四式完全不同，符箓自带符匣。",
				"anchor": "meta:rogue.family", "ev": "rogue_family"},
			{"id": "c6_card", "text": "三选一里挑一张",
				"tip": "只出本流派 + 通用的卡，叠满的不再出现。",
				"anchor": "meta:rogue.card", "ev": "rogue_card",
				# 2026-11-12 用户定：这一步**第一次弹三选一时**才露面（原来一进试炼就挂在那）
				"need": "rogue_pick_open"},
			{"id": "c6_deck", "text": "局内按 TAB 看「玉简」",
				"tip": "已经拿了哪些卡、每张叠到几层，都在玉简里。",
				"anchor": "", "ev": "rogue_deck_open"},
		],
	},
	{
		"id": "c7", "title": "收集与领取", "trigger": "panel:achievement_panel",
		"steps": [
			{"id": "c7_badge", "text": "按钮上的红点 = 有东西能领",
				"tip": "红点不是装饰，点进去就对了。",
				"anchor": "meta:hud.achievement", "ev": "", "manual": true},
			{"id": "c7_task", "text": "在「成就任务」页点领取",
				"tip": "卡面解锁后能领锻造晶石。",
				"anchor": "meta:ach.task", "ev": "reward_claim"},
			{"id": "c7_codex", "text": "图鉴能查所有见过的 BOSS 与卡",
				"tip": "图鉴在成就上方，不是同一页。",
				"anchor": "meta:hud.codex", "ev": "panel_opened:codex_panel"},
			{"id": "c7_cardpack", "text": "卡包在「成就收藏」里",
				"tip": "不在图鉴里，别翻错地方。",
				"anchor": "meta:ach.pack", "ev": "ach_pack_open"},
		],
	},
	{
		"id": "c8", "title": "苍澜大陆", "trigger": "event:world_enter",
		"steps": [
			{"id": "c8_gather", "text": "出门采第一株药",
				"tip": "草药能采，是炼丹的原料。",
				"anchor": "", "ev": "world_pickup"},
			{"id": "c8_beast", "text": "打死一只灵兽或野修",
				"tip": "小怪给修为，别只盯着 BOSS。",
				"anchor": "", "ev": "world_enemy_kill"},
			{"id": "c8_core", "text": "挑战区域核心首领",
				"tip": "核心首杀给突破材料。",
				"anchor": "", "ev": "world_core_kill"},
			{"id": "c8_farm", "text": "打完核心首领去森林开灵田",
				"tip": "开垦后能种药，不必满地图找。",
				"anchor": "meta:world.farm", "ev": "farm_tilled"},
		],
	},
]


## 全部步骤（探针用：遍历不留死角）
static func all_steps() -> Array:
	var out: Array = []
	for raw_ch in CHAPTERS:
		var ch: Dictionary = raw_ch
		for raw_step in (ch.get("steps", []) as Array):
			var s: Dictionary = (raw_step as Dictionary).duplicate()
			s["chapter"] = String(ch.get("id", ""))
			out.append(s)
	return out


static func get_chapter(chapter_id: String) -> Dictionary:
	for raw in CHAPTERS:
		if String((raw as Dictionary).get("id", "")) == chapter_id:
			return raw
	return {}


static func get_step(step_id: String) -> Dictionary:
	for s in all_steps():
		if String((s as Dictionary).get("id", "")) == step_id:
			return s
	return {}


## 章节里第一步没做过的（都做完了返回空字典）
static func first_open_step(chapter_id: String, done: Dictionary) -> Dictionary:
	var ch := get_chapter(chapter_id)
	for raw in (ch.get("steps", []) as Array):
		var s: Dictionary = raw
		if not bool(done.get(String(s.get("id", "")), false)):
			return s
	return {}
