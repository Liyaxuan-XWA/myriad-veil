class_name CodexDB
extends RefCounted
## 图鉴数据：BOSS 卡面（独立一页）+ 装备 / 法宝 / 材料（来自 ItemDB）。
## 道具的解锁状态由 CharacterData.codex_unlocked 记录；BOSS 卡的解锁按「是否击败过」算。

const CAT_BOSS := "boss"
const CAT_PACK := "pack"
const CAT_EQUIPMENT := "equipment"
const CAT_TREASURE := "treasure"
const CAT_MATERIAL := "material"
## 试炼之路的增强卡片（2026-11-09 用户定）：卡片**只在本模式局内生效**，
## 所以不走 CharacterData.codex_unlocked —— 条目直接从 RogueDB.POOLS 现生成，
## 解锁只看「该流派是否已按历史最高层开放」，不另存任何字段。
const CAT_ROGUE_CARD := "rogue_card"

## 2026-10-30 用户定：卡包迁到「成就 → 成就收藏」，图鉴只留资料类卷目。
const CATEGORIES: Array = [
	{"id": CAT_BOSS, "title": "BOSS"},
	{"id": CAT_EQUIPMENT, "title": "装备"},
	{"id": CAT_TREASURE, "title": "法宝"},
	{"id": CAT_MATERIAL, "title": "材料"},
	{"id": CAT_ROGUE_CARD, "title": "卡牌"},
]

## 图鉴二级分类：只影响列表筛选，不改条目与解锁。
const SUB_ALL := "all"
const SUB_FLOOR := "floor"
const SUB_WORLD := "world"
const SUB_WEAPON := "weapon"
const SUB_ARMOR := "armor"
const SUB_SHOES := "shoes"
const SUB_ACCESSORY := "accessory"
const SUB_SUMMON := "summon"
const SUB_ACTIVE := "active"
const SUB_OTHER := "other"
const SUB_REALM_LIANQI := "练气"
const SUB_REALM_ZHUJI := "筑基"
const SUB_REALM_JIEDAN := "结丹"
const SUB_REALM_YUANYING := "元婴"

## 大世界核心首领：图鉴 / 卡包统一按这张表收录；新区域核心登记到这里。
const CORE_BOSS_IDS: Array = [
	"world_core_lianqi", "world_core_zhuji", "world_core_jiedan", "world_core_shihou",
]

const SUB_CATEGORIES: Dictionary = {
	CAT_BOSS: [
		{"id": SUB_ALL, "title": "全部"},
		{"id": SUB_FLOOR, "title": "位面首领"},
		{"id": SUB_WORLD, "title": "大陆核心"},
	],
	CAT_EQUIPMENT: [
		{"id": SUB_ALL, "title": "全部"},
		{"id": SUB_WEAPON, "title": "武器"},
		{"id": SUB_ARMOR, "title": "护甲"},
		{"id": SUB_SHOES, "title": "鞋子"},
		{"id": SUB_ACCESSORY, "title": "饰品"},
	],
	CAT_TREASURE: [
		{"id": SUB_ALL, "title": "全部"},
		{"id": SUB_SUMMON, "title": "召唤"},
		{"id": SUB_ACTIVE, "title": "主动"},
		{"id": SUB_OTHER, "title": "其它"},
	],
	CAT_MATERIAL: [
		{"id": SUB_ALL, "title": "全部"},
		{"id": SUB_REALM_LIANQI, "title": "练气"},
		{"id": SUB_REALM_ZHUJI, "title": "筑基"},
		{"id": SUB_REALM_JIEDAN, "title": "结丹"},
		{"id": SUB_REALM_YUANYING, "title": "元婴"},
		{"id": SUB_OTHER, "title": "其它"},
	],
	## 试炼卡牌按稀有度筛选（不按流派：13 个流派 tab 在 800px 面板里会横向溢出）
	CAT_ROGUE_CARD: [
		{"id": SUB_ALL, "title": "全部"},
		{"id": "common", "title": "普通"},
		{"id": "rare", "title": "稀有"},
		{"id": "legend", "title": "传说"},
	],
}

## 卡包收藏：同层通关「双倍气血」挑战（第 11 次及以后）才点亮华彩。
## 每个 BOSS 默认四张卡：普通原画 / 华彩 · 有背景 / 标准 · 无背景 / 纸本水墨；
## 水墨异画按 INK_NOTES 全量登记，需在双倍气血场次 10 秒内通关。
const HOLO_CLEAR_REQUIRED := 11
const INK_CLEAR_TIME_LIMIT := 10.0
const PLAIN_HOLO_BG := "res://assets/ui/codex/holo/plain_bg.png"
## 普通卡：BOSS 图鉴原画，静态卡面（CardFace kind = "still"），不参与视差与箔光。
const PORTRAIT_CARD_STYLE := {
	"id": "portrait",
	"kind": "still",
	"label": "普通卡",
	"desc": "BOSS 图鉴原画卡，无华彩分层。",
	"unlock": "boss",
	"art": "",
}
const PLAIN_HOLO_STYLE := {
	"id": "plain",
	"kind": "holo",
	"label": "纯华彩 · 无背景",
	"desc": "无背景的纯华彩卡面；无伤通关双倍气血 BOSS 解锁。",
	"unlock": "perfect",
	"bg": PLAIN_HOLO_BG,
	"bg_scale": 0.5,
	"bg_shift": 0.25,
	"prism": 1.0,
	"contour": 0.15,
	"emission_gain": 1.0,
	"wide_glow": 0.0,
	"aura": 0.0,
	"legacy": true,
}
## 场景版：背景 1:1 不进 2× 裁切，保留地面/台阶的原始落点。
const SCENE_HOLO_STYLE := {
	"id": "scene",
	"kind": "holo",
	"label": "华彩 · 有背景",
	"desc": "保留原战场背景，拖动时背景与角色分层错动。",
	"unlock": "double",
	"bg_scale": 1.0,
	"bg_shift": 0.08,
	"prism": 1.0,
	"contour": 0.18,
	"emission_gain": 1.15,
	"wide_glow": 0.3,
	"aura": 0.35,
}
## 纸本水墨全套：13 位 BOSS 同一口径——图鉴原画为骨，墨在纸上，纸面留白。
## INK_NOTES 只写这张画「保留了哪些身份特征」，动效说明共用 INK_DESC_TAIL。
const INK_STYLE := {
	"id": "ink",
	"kind": "still",
	"label": "水墨 · 纸本",
	"unlock": "speed",
	"fx": "paper",
	"hint": "纸本水墨 · 墨迹流动 · 滑动微倾 · 晃动出水痕",
}
const INK_DESC_TAIL := "纸本卡面；墨迹沿笔势缓慢流动；卡面滑动会微倾，快速晃动产生水痕；展开页与收藏封面同样响应。"
const INK_NOTES := {
	"boss_huyao": "纸本水墨重绘；保留虎的姿态、结构、岩台与林雾关系，",
	"boss_01": "纸本水墨重绘；保留扛刀侧立的身形、披风与石灯竹影，脚下环形刀痕收成淡墨，",
	"boss_01_c": "纸本水墨重绘；保留白衣负手的身形与身后悬浮的万剑，云海孤石用湿墨晕开，",
	"boss_02": "纸本水墨重绘；保留黑白道袍、身后太极盘与掌中珠，石阶退成淡墨，",
	"boss_02_b": "纸本水墨重绘；保留背后旗杆、脚下阵图与远处阵列，衣纹用枯笔扫出，",
	"boss_02_c": "纸本水墨重绘；保留白发、掌中青色气环与身后残环，云气留白，",
	"boss_03": "纸本水墨重绘；保留重甲、红披风与肩后鼓盾，脚下雷纹压成焦墨，",
	"boss_03_b": "纸本水墨重绘；保留当空红日、手中圆镜与红黑长袍，山石留淡墨，",
	"boss_03_c": "纸本水墨重绘；保留白面具、橙青紫三道劫环与灰袍，乱石用散锋，",
	"boss_04": "纸本水墨重绘；保留黑发、银灰镜纹长袍与高举的碎镜，镜面用水法晕开，倒影留白，",
	"boss_04_b": "纸本水墨重绘；保留青黑广袖、垂到地的披影与一只空铜界灯，灯焰留白，地上那道影子用泼墨一笔拖长，",
	"boss_04_c": "纸本水墨重绘；保留月白纸袍上那道硬折棱、对折的纸面与一柄青铜镇尺，折缝留白，身侧两块纸面错开半寸，",
	"world_core_lianqi": "纸本水墨重绘；保留苔石巨猿撑在岩台上的体块与雾林纵深，",
	"world_core_zhuji": "纸本水墨重绘；保留枯木巨鹿的枝角、垂蔓与谷心石圈，",
	"world_core_jiedan": "纸本水墨重绘；保留金角、火焰鬃尾与侧腹丹核，峡谷留白，",
	"world_core_shihou": "纸本水墨重绘；保留叠石鬃、封眼石带、胸前青焰与左下垂石槌尾，山门残柱用枯笔，",
}
const HOLO_CARDS: Dictionary = {
	"boss_huyao": {
		"accent": Color(0.86, 0.66, 0.32, 1.0),
		"art": "res://assets/ui/codex/holo/boss_huyao_plain_art.png",
		"lines": "res://assets/ui/codex/holo/boss_huyao_plain_fine20.png",
		"scene": {
			"art": "res://assets/ui/codex/holo/boss_huyao_art.png",
			"bg": "res://assets/ui/codex/holo/boss_huyao_bg.png",
			"lines": "res://assets/ui/codex/holo/boss_huyao_lines.png",
		},
	},
	"boss_01": {
		"accent": Color(0.80, 0.36, 0.34, 1.0),
		"art": "res://assets/ui/codex/holo/boss_01_art.png",
		"lines": "res://assets/ui/codex/holo/boss_01_plain_lines.png",
		"scene": {
			"art": "res://assets/ui/codex/holo/boss_01_art.png",
			"bg": "res://assets/ui/codex/holo/boss_01_bg.png",
			"lines": "res://assets/ui/codex/holo/boss_01_lines.png",
		},
	},
	"boss_01_c": {
		"accent": Color(0.62, 0.80, 0.86, 1.0),
		"art": "res://assets/ui/codex/holo/boss_01_c_plain_art.png",
		"lines": "res://assets/ui/codex/holo/boss_01_c_plain_lines.png",
		"scene": {
			"art": "res://assets/ui/codex/holo/boss_01_c_art.png",
			"bg": "res://assets/ui/codex/holo/boss_01_c_bg.png",
			"lines": "res://assets/ui/codex/holo/boss_01_c_lines.png",
		},
	},
	"boss_02": {
		"accent": Color(0.82, 0.80, 0.66, 1.0),
		"art": "res://assets/ui/codex/holo/boss_02_plain_art.png",
		"lines": "res://assets/ui/codex/holo/boss_02_plain_lines.png",
		"scene": {
			"art": "res://assets/ui/codex/holo/boss_02_art.png",
			"bg": "res://assets/ui/codex/holo/boss_02_bg.png",
			"lines": "res://assets/ui/codex/holo/boss_02_lines.png",
		},
	},
	"boss_02_b": {
		"accent": Color(0.84, 0.40, 0.30, 1.0),
		"art": "res://assets/ui/codex/holo/boss_02_b_plain_art.png",
		"lines": "res://assets/ui/codex/holo/boss_02_b_plain_lines.png",
		"scene": {
			"art": "res://assets/ui/codex/holo/boss_02_b_art.png",
			"bg": "res://assets/ui/codex/holo/boss_02_b_bg.png",
			"lines": "res://assets/ui/codex/holo/boss_02_b_lines.png",
		},
	},
	"boss_02_c": {
		"accent": Color(0.62, 0.86, 0.80, 1.0),
		"art": "res://assets/ui/codex/holo/boss_02_c_plain_art.png",
		"lines": "res://assets/ui/codex/holo/boss_02_c_plain_lines.png",
		"scene": {
			"art": "res://assets/ui/codex/holo/boss_02_c_art.png",
			"bg": "res://assets/ui/codex/holo/boss_02_c_bg.png",
			"lines": "res://assets/ui/codex/holo/boss_02_c_lines.png",
		},
	},
	"boss_03": {
		"accent": Color(0.86, 0.56, 0.30, 1.0),
		"art": "res://assets/ui/codex/holo/boss_03_plain_art.png",
		"lines": "res://assets/ui/codex/holo/boss_03_plain_lines.png",
		"scene": {
			"art": "res://assets/ui/codex/holo/boss_03_art.png",
			"bg": "res://assets/ui/codex/holo/boss_03_bg.png",
			"lines": "res://assets/ui/codex/holo/boss_03_lines.png",
		},
	},
	"boss_03_b": {
		"accent": Color(0.92, 0.46, 0.24, 1.0),
		"art": "res://assets/ui/codex/holo/boss_03_b_art.png",
		"lines": "res://assets/ui/codex/holo/boss_03_b_lines.png",
		"scene": {
			"art": "res://assets/ui/codex/holo/boss_03_b_art.png",
			"bg": "res://assets/ui/codex/holo/boss_03_b_bg.png",
			"lines": "res://assets/ui/codex/holo/boss_03_b_lines.png",
		},
	},
	"boss_03_c": {
		"accent": Color(0.72, 0.60, 0.86, 1.0),
		"art": "res://assets/ui/codex/holo/boss_03_c_art.png",
		"lines": "res://assets/ui/codex/holo/boss_03_c_lines.png",
		"scene": {
			"art": "res://assets/ui/codex/holo/boss_03_c_art.png",
			"bg": "res://assets/ui/codex/holo/boss_03_c_bg.png",
			"lines": "res://assets/ui/codex/holo/boss_03_c_lines.png",
		},
	},
	"boss_04": {
		"accent": Color(0.62, 0.90, 1.00, 1.0),
		"art": "res://assets/ui/codex/holo/boss_04_art.png",
		"lines": "res://assets/ui/codex/holo/boss_04_lines.png",
		"scene": {
			"art": "res://assets/ui/codex/holo/boss_04_art.png",
			"bg": "res://assets/ui/codex/holo/boss_04_bg.png",
			"lines": "res://assets/ui/codex/holo/boss_04_lines.png",
		},
	},
	"boss_04_b": {
		"accent": Color(0.58, 0.64, 0.92, 1.0),
		"art": "res://assets/ui/codex/holo/boss_04_b_art.png",
		"lines": "res://assets/ui/codex/holo/boss_04_b_lines.png",
		"scene": {
			"art": "res://assets/ui/codex/holo/boss_04_b_art.png",
			"bg": "res://assets/ui/codex/holo/boss_04_b_bg.png",
			"lines": "res://assets/ui/codex/holo/boss_04_b_lines.png",
		},
	},
	"boss_04_c": {
		"accent": Color(0.86, 0.84, 0.72, 1.0),
		"art": "res://assets/ui/codex/holo/boss_04_c_art.png",
		"lines": "res://assets/ui/codex/holo/boss_04_c_lines.png",
		"scene": {
			"art": "res://assets/ui/codex/holo/boss_04_c_art.png",
			"bg": "res://assets/ui/codex/holo/boss_04_c_bg.png",
			"lines": "res://assets/ui/codex/holo/boss_04_c_lines.png",
		},
	},
	# 大世界核心首领：分支重战双倍血 / 双倍血无伤解锁（2026-10-30 用户定）
	"world_core_lianqi": {
		"accent": Color(0.62, 0.76, 0.45, 1.0),
		"art": "res://assets/ui/codex/holo/world_core_lianqi_art.png",
		"lines": "res://assets/ui/codex/holo/world_core_lianqi_lines.png",
		"scene": {
			"art": "res://assets/ui/codex/holo/world_core_lianqi_art.png",
			"bg": "res://assets/ui/codex/holo/world_core_lianqi_bg.png",
			"lines": "res://assets/ui/codex/holo/world_core_lianqi_lines.png",
		},
	},
	"world_core_zhuji": {
		"accent": Color(0.48, 0.78, 0.66, 1.0),
		"art": "res://assets/ui/codex/holo/world_core_zhuji_art.png",
		"lines": "res://assets/ui/codex/holo/world_core_zhuji_lines.png",
		"scene": {
			"art": "res://assets/ui/codex/holo/world_core_zhuji_art.png",
			"bg": "res://assets/ui/codex/holo/world_core_zhuji_bg.png",
			"lines": "res://assets/ui/codex/holo/world_core_zhuji_lines.png",
		},
	},
	"world_core_jiedan": {
		"accent": Color(0.92, 0.60, 0.26, 1.0),
		"art": "res://assets/ui/codex/holo/world_core_jiedan_art.png",
		"lines": "res://assets/ui/codex/holo/world_core_jiedan_lines.png",
		"scene": {
			"art": "res://assets/ui/codex/holo/world_core_jiedan_art.png",
			"bg": "res://assets/ui/codex/holo/world_core_jiedan_bg.png",
			"lines": "res://assets/ui/codex/holo/world_core_jiedan_lines.png",
		},
	},
	"world_core_shihou": {
		"accent": Color(0.42, 0.82, 0.78, 1.0),
		"art": "res://assets/ui/codex/holo/world_core_shihou_art.png",
		"lines": "res://assets/ui/codex/holo/world_core_shihou_lines.png",
		"scene": {
			"art": "res://assets/ui/codex/holo/world_core_shihou_art.png",
			"bg": "res://assets/ui/codex/holo/world_core_shihou_bg.png",
			"lines": "res://assets/ui/codex/holo/world_core_shihou_lines.png",
		},
	},
}

## BOSS 卡面资料：只放「卡面文案 + 原画」。数值 / 招式 / 掉落全部现查数据表，不在这里抄一遍。
## ⚠ 只登记已经做进项目的 BOSS（WorldDB.BOSS_SCENES 里有映射的），占位 BOSS 不进图鉴。
const BOSS_CODEX: Dictionary = {
	"boss_huyao": {
		"subtitle": "凡界 · 第一关",
		"epithet": "千嶂林中的山君",
		"portrait": "res://assets/ui/codex/card_boss_huyao.png",
		"tags": ["兽型", "距离档", "后撤步", "突进砸地"],
		"mechanic_title": "距离档 · 兽性反制",
		"intro_hint": "近战两次会后撤；远程两次会突进砸地。",
		"mechanic": "虎妖按与自身边缘的距离选择招式：近距离爪击，中距离掷石，远距离突进。连续两次近战出手会触发后撤；连续两次远程出手会触发突进砸地。二阶段招式伤害提高，并解锁妖丹、三连砸地与砂石乱舞。贴身时只使用爪击，远程招式不会触发。",
		"mechanic_points": [
			"距离档：近距爪击 / 中距掷石 / 远距突进；站位决定它可用的招式",
			"反制：连续两次近战出手 → 后撤；连续两次远程出手 → 突进砸地",
			"二阶段：伤害提高，新增妖丹、三连砸地、砂石乱舞",
			"贴身时只出爪击，可限制远程招式",
		],
	},
	"boss_01": {
		"subtitle": "凡界 · 第二关",
		"epithet": "石灯残局里的持刀人",
		"portrait": "res://assets/ui/codex/card_boss_daoke.png",
		"tags": ["人形", "刀痕", "弹反", "破步"],
		"mechanic_title": "刀痕 · 场地博弈",
		"intro_hint": "满势断岳仅在目标站在刀痕上时释放；刀域引爆范围内刀痕。",
		"mechanic": "刀客的部分物理挥砍会在地面留下刀痕，刀痕持续 10 秒，场上最多 4 道，超出时移除最早的一道。刀痕本身不造成伤害。断岳会沿飞行路径引爆刀痕，封路刀域会引爆范围内的全部刀痕；每道刀痕转化为一次斩击后消失。满势断岳只在目标站在刀痕上时释放。二阶段会将物理投射物弹回，法术投射物不受影响。",
		"mechanic_points": [
			"刀痕：部分物理挥砍留下，持续 10 秒、场上最多 4 道",
			"引爆：断岳沿路径、刀域按范围；每道刀痕转化为一次斩击后消失",
			"满势断岳：仅当目标站在刀痕上时释放；前摇即预警",
			"二阶段：物理投射物被弹回，法术投射物不受影响",
		],
	},
	"boss_01_c": {
		"subtitle": "凡界 · 第三关",
		"epithet": "云海之上的剑指",
		"portrait": "res://assets/ui/codex/card_boss_jianke.png",
		"tags": ["人形", "剑意", "蓄压", "九式"],
		"mechanic_title": "剑意 · 蓄压爆发",
		"intro_hint": "连续两次远程出手，它会向目标方向突进约 323 像素。",
		"mechanic": "它靠出招和命中攒剑意 —— 剑意越高，万剑归宗的飞剑越多；二阶段换成一剑开天，会一次吃掉全部剑意。你连续命中就能削它的剑意，所以别让它舒舒服服地出手。",
		"mechanic_points": [
			"首杀必得：筑基天髓（半枚）—— 与练气区核心首领的筑基底髓在锻造台熔铸成筑基破境晶，那才算练气→筑基的突破材料",
			"剑意：出招与命中积累；万剑归宗的飞剑数量随剑意提高",
			"压制：连续命中会削减剑意；满层的一剑开天消耗全部剑意",
			"穿：连续两次远程出手 → 向目标方向突进约 323 像素，落点在目标前方",
			"转阶段：插剑封阵 → 斩决；插地剑可击碎，未击碎的剑为其回复气血",
			"二阶段：一剑开天替换万剑归宗",
		],
	},
	"boss_02": {
		"subtitle": "冲和界 · 第一关",
		"epithet": "阴阳同炉的守门人",
		"portrait": "res://assets/ui/codex/card_boss_liangyi.png",
		"tags": ["人形", "两仪护体", "阴阳易位", "破盾"],
		"mechanic_title": "两仪护体 · 阴阳易位",
		"intro_hint": "同色减伤且不削盾；异色增伤并削盾。弹反与完美闪避也削盾，不受颜色影响。",
		"mechanic": "它的护体分阳 / 阴两色：只有**异色**命中才增伤并削盾，同色打上去只是减伤、白耗一手。弹反与完美闪避不看颜色，照样削盾。盾一破它就硬直翻面、受伤加重，随后回盾并进入封窗 —— 封窗期间谁都削不动盾，那是唯一能安心输出的时候。",
		"mechanic_points": [
			"读色：护体条旁显示当前阳 / 阴；只有异色命中增伤并削盾",
			"削盾：异色命中、弹反、完美闪避；同色只减伤，不削盾",
			"破盾：硬直、翻面、受伤增加；随后回盾并进入封窗",
			"封窗：任何来源都不能削盾，是输出窗口",
			"两仪转前摇不可打断；倒悬同色吸收并反击、异色破势；太极崩为二阶段大招",
		],
	},
	"boss_02_b": {
		"subtitle": "冲和界 · 第二关",
		"epithet": "经纬在手的盲阵师",
		"portrait": "res://assets/ui/codex/card_boss_dingzhen.png",
		"tags": ["人形", "三色阵旗", "连线", "拔旗"],
		"mechanic_title": "阵旗 · 连线",
		"intro_hint": "三色旗：攻 / 困 / 守；打掉旗会断开对应阵线。",
		"mechanic": "它插三色阵旗：朱砂为攻、墨为困、石青为守。旗与旗之间连成阵线挡住去路，只有打掉旗才断线（施法者可以穿行）。五面旗首尾闭合成环，它在环内攻守 +30% 并每秒落雷 —— 所以别让它把第五面插完。",
		"mechanic_points": [
			"三色旗：朱砂＝攻、墨＝困、石青＝守；守旗存活时它受伤 -50%",
			"攻旗自动攻击；困旗锁步并禁闪避；旗与旗连成阵线阻挡移动，施法者可穿行",
			"五旗成环：环内它攻防 +30%，目标攻击 -10%，每秒落雷并消耗阵力；阵力耗尽撤旗",
			"旗有 3 点耐久；破坏守旗后它的受伤减免消失",
			"五旗反噬：玩家完整五旗被它破坏一面 → 眩晕 5 秒，15 秒内无法插旗 / 踏阵 / 垒旗",
			"三同色套招：三攻万剑 / 三困定身锁 / 三守龟甲阵",
			"封阵：四旗成牢；攻牢伤害 / 困牢眩晕 5 秒 / 守牢减伤 70% 持续 10 秒；任一旗破立即结束",
			"攻旗自动打阵内目标；困旗锁步并禁闪避；守旗存活时它受伤 -50%",
			"每面旗 3 点耐久，需 3 次攻击破坏；落雷消耗它的隐藏阵力，阵力耗尽旗全散",
			"三面同色出套招：三攻落万剑、三困定身锁、三守龟甲阵",
			"封阵（四面旗）按多数色结牢：攻牢造成伤害、困牢眩晕 5 秒、守牢减伤 70% 持续 10 秒；任一成阵旗被破坏立即结束",
			"玩家的完整五旗被它破一面：玩家眩晕 5 秒，且 15 秒内无法插旗 / 踏阵 / 垒旗",
		],
		"status_note": "它的垒旗会附加「重伤」；阵线阻挡移动但不造成伤害；五旗环每秒落雷并使玩家攻击 -10%；攻旗命中叠加「阵伤」（受到伤害增加）。",
	},
	"boss_02_c": {
		"subtitle": "冲和界 · 第三关",
		"epithet": "一息化万法的气主",
		"portrait": "res://assets/ui/codex/card_boss_qijun.png",
		"tags": ["人形", "气环", "化劲", "滞气"],
		"mechanic_title": "气环 · 化劲",
		"intro_hint": "3 枚气环时它会化劲：停手可减少储存；气浪可弹反或躲避。",
		"mechanic": "它靠气环做事：最多 3 枚，只有「引气·聚环」会凝环。攒满 3 枚它才起手化劲 —— 2.2 秒内受伤 -40%，并把其中 60% 存下来（上限 140），结束时吐出一道物理气浪。看到它开始凝环就该压它，逼它把化劲交在还没存够的时候。",
		"mechanic_points": [
			"首杀必得：结丹天髓（半枚）—— 与云隐谷核心首领的结丹底髓熔铸成结丹破境晶",
			"气环：上限 3 枚，只有引气凝环；冲气消耗 1 枚，气爆消耗全部",
			"化劲：3 环时起手；2.2 秒内受伤 -40%，储存其中 60%（上限 140），结束释放物理气浪（1.20× + 储存）",
			"气浪是物理近战，可弹反、可躲避；化劲期间停手会减少储存量",
			"吐纳：回复 10% 最大气血，不凝环；期间受到超过 8% 最大气血的伤害会被打断",
			"气锁：滞气使灵力停止回复、移速 -20%",
			"二阶段·气海：化劲结束留下气海，持续伤害并减速",
			"气浪可弹反、可走位躲；伤害 = 1.20 倍基础 + 储存量",
			"冲气消耗 1 枚换伤害与射程；气爆消耗全部气环，每枚提高伤害",
			"气锁命中附加滞气：灵力停止回复、移速 -20%",
			"二阶段：化劲结束后原地留气海，持续伤害并降移速",
			"吐纳回复 10% 最大气血，期间吃到超过 8% 最大气血的伤害就被打断；吐纳不凝环",
		],
		"status_note": "它的气浪为物理近战，可弹反；滞气使灵力停止回复、移速 -20%。",
	},
	"boss_03": {
		"subtitle": "赤霄界 · 第一关",
		"epithet": "雷部判官 · 执劫之人",
		"portrait": "res://assets/ui/codex/card_boss_heiliao.png",
		"tags": ["人形", "判词", "雷势", "抗辩"],
		"mechanic_title": "判词 · 天律",
		"intro_hint": "宣判可弹反；判词期间按律限制行动。",
		"mechanic": "它按你最近 1.5 秒的动作下判词：走路→禁行，出手→禁攻，闪避→禁避，站定→禁立。判下来后违律就挨一道 0.25 秒预警的雷（走开能躲），它还得一层雷势；全程守住则你拿「顺天」增益、它掉一层雷势 —— 判什么就偏不做，是最赚的打法。宣判本身是物理笔锋，可弹反，弹反直接撤销判词并让它僵直。",
		"mechanic_points": [
			"选律：按最近 1.5 秒行为；移动 / 出手 / 闪避 / 站定 → 禁行 / 禁攻 / 禁避 / 禁立",
			"数量与时长：一阶段 1 条、二阶段 2 条不冲突；每条 5 秒，二阶段 6 秒",
			"违律：0.25 秒预警雷击，可走位躲避；赫连霄雷势 +1（上限 3）",
			"守律：每条律全程未违律 → 顺天 6 秒（攻速 +20%、移速 +10%），赫连霄雷势 -1",
			"抗辩：宣判可弹反；弹反撤销判词、使其僵直、雷势 -1",
			"二阶段：双律 + 雷牢进入常规选招",
		],
		"status_note": "判词状态显示在头顶（雷印 + 倒计时）；滞雷使移速 -25%、闪避距离 -30%；雷牢收拢命中会眩晕 1 秒。",
		"status_extra": [
			{"id": "verdict_no_move", "time": 5.0, "source": "判词·天律"},
			{"id": "verdict_no_attack", "time": 5.0, "source": "判词·天律"},
			{"id": "verdict_no_dodge", "time": 5.0, "source": "判词·天律"},
			{"id": "verdict_no_still", "time": 5.0, "source": "判词·天律"},
			{"id": "thunder_stagnation", "time": 4.0, "source": "锁雷·缚魂"},
			{"id": "stun", "time": 1.0, "source": "雷牢·天罚"},
		],
	},
	"boss_03_b": {
		"subtitle": "赤霄界 · 第二关",
		"epithet": "赤霄火正 · 盗火的天官",
		"portrait": "res://assets/ui/codex/card_boss_lizhao.png",
		"tags": ["人形", "天火种", "日冕", "夺火"],
		"mechanic_title": "逐日 · 天火",
		"intro_hint": "天火种可被双方拾取；日冕满 3 层后持续受伤，3 秒后爆裂。",
		"mechanic": "场上同时只有一枚天火种，谁拿着谁变强：持种每 1.6 秒叠一层日冕（最多 3 层），玩家每层所有伤害 +12%。但火种也咬人 —— 叠满后每秒掉血、3 秒就当场爆裂。离照的逐日步 / 牵日 / 焚风 / 日蚀都必须打中持有者才夺得动，所以让它打空，就是拆它的引擎。",
		"mechanic_points": [
			"火种：场上 1 枚；46 像素内自动拾取；落地 0.6 秒内不可拾取",
			"日冕：每 1.6 秒 +1 层，上限 3；玩家全伤害 +12%/层，离照攻击 +8%/层，持种额外减伤 15%",
			"引燃：玩家叠满 3 层后，下一次逐日功法命中使目标体内延迟 1 秒爆出 2.0×法强的火伤；每次叠满只触发 1 次",
			"满层：每秒 6 点火焰伤害；3 秒后爆裂，玩家损失 12% / 离照损失 6% 最大气血",
			"夺火：逐日步 / 牵日 / 焚风 / 日蚀必须命中持有者；层数随火种转移",
			"它抢火的判定：逐日步落点在首帧固定；牵日走廊宽 50；焚风正中 60°；日蚀需留在黑日圈内侧（约 72% 半径）",
			"重生：消耗或爆裂后 8 秒，二阶段 6 秒",
			"火忌：连续两次夺火落空 → 6 秒内四招抢火不可用",
			"二阶段：天火坠加入常规选招",
		],
		"status_note": "日冕满 3 层后每秒受到 6 点火焰伤害；被投日/日蚀命中会附加灼心；连续两次夺火落空触发火忌。",
		"status_extra": [
			{"id": "sunburn", "time": 4.0, "source": "日冕斩 / 投日 / 日蚀"},
			{"id": "sun_fire_ban", "time": 6.0, "source": "连续两次夺火落空"},
			"拾取：进入 46 像素自动拿；火种落地后 0.6 秒内谁都拿不走",
			"离照持种：每层攻击力 +8%，持种期间额外减伤 15%",
			"引燃：玩家叠满 3 层得 1 次 —— 下一次逐日功法命中后延迟 1 秒爆出 2.0 倍法强的火伤，耗该火种 1 层日冕（脱手也算）并刷新逐日步",
			"爆裂：3 层后每秒 6 点火焰伤害，3 秒炸 —— 玩家掉 12% 最大气血，离照掉 6%",
			"重生：火种被消耗或爆裂后 8 秒在新位置重生，二阶段 6 秒",
			"火忌：连续两次夺火落空，离照 6 秒内用不了逐日步 / 牵日 / 焚风 / 日蚀",
		],
	},
	"boss_03_c": {
		"subtitle": "赤霄界 · 第三关",
		"epithet": "赤霄劫主 · 执掌三灾的天劫",
		"portrait": "res://assets/ui/codex/card_boss_wujiu.png",
		"tags": ["人形", "三灾轮转", "破灾", "灾势"],
		"mechanic_title": "三灾 · 轮转",
		"intro_hint": "灾位相克：风克火、火克雷、雷克风；任意风 / 火 / 雷属性功法克制其当前灾位即可破灾。",
		"mechanic": "双方各占一个灾位（风 / 火 / 雷），风克火、火克雷、雷克风。用克制它当前灾位的属性命中就破灾：伤害 ×1.15，它灾崩 3 秒、受伤 +30%；用同属性命中反而替它攒灾势。你的风火雷技能会在它身上留下灾痕，灾痕相叠当场引爆 —— 这是破它的第二条路。",
		"mechanic_points": [
			"首杀必得：元婴天髓（半枚）—— 与赤金丹霞核心首领的元婴底髓熔铸成元婴破境晶",
			"灾位：风 / 火 / 雷，双方各一；任意对应属性功法命中都参与破灾 / 喂灾（玩家灾位 / 灾势需装备被动）",
			"灾劫连锁（装不装被动都生效）：风 + 劫火 = 3 秒火龙卷；火 + 感电 = 一次火爆；雷 + 风蚀 = 3 秒风雷涡吸附；燎原 / 雷池跳伤也能引爆",
			"相克：风克火、火克雷、雷克风；克制命中 → 伤害 ×1.15、灾势 +1、目标灾崩 3 秒（受到伤害 +30%）",
			"同灾：同属性命中 → 伤害 ×0.85，目标灾势 +1",
			"灾身：风=目标移速 +25% / 玩家移速 +12%；火=命中挂劫火 / 玩家法技增伤 +12%；雷=命中挂感电 / 玩家攻速 +12%；玩家侧需装备被动「三灾·灾身」",
			"灾势：上限 3；万劫归一消耗全部灾势追加灾柱与伤害",
			"灾替：三灾轮转起手 1.5 秒 / 三灾轮法宝 8 秒内，第一次被破灾改为免疫并 +1 灾势",
			"锁灾：雷池首跳锁目标灾轮 3 秒；被破灾时目标受伤 ×1.15、灾势 -1、锁灾 2 秒",
			"二阶段：50% 气血时 8 秒三灾归一，无法破灾但受伤 +20%；结束后灾轮 5 秒一转",
		],
		"status_note": "劫火每秒造成 6 点火焰伤害；感电使受到伤害 +15%；风蚀使移速 -15%；锁灾期间无法切换灾位；灾崩使受到伤害 +30%。",
		"status_extra": [
			{"id": "jie_huo", "time": 4.0, "source": "焚天印 / 燎原"},
			{"id": "gan_dian", "time": 3.0, "source": "引雷诀 / 雷池"},
			{"id": "feng_shi", "time": 4.0, "source": "裂云步 / 断空斩 / 未带被动的轮转"},
			{"id": "suo_zai", "time": 3.0, "source": "雷池"},
			{"id": "zai_beng", "time": 3.0, "source": "破灾 / 万劫归一"},
		],
	},
	"boss_04": {
		"subtitle": "照影界 · 第一关",
		"epithet": "照影镜主 · 站在倒影里的人",
		"portrait": "res://assets/ui/codex/card_boss_guanying.png",
		"tags": ["人形", "镜身", "镜像", "真假", "元婴"],
		"mechanic_title": "镜身 · 照影",
		"intro_hint": "真身脚下有倒影，镜像没有；镜像会从你四周站起、复读本体招式（半伤），法术免疫，必须用物理命中打碎。换镜后真身会暴露 1.2 秒，正是打它的窗口。",
		"mechanic": "场上只有一个真身：它脚下有一层随它移动的倒影，镜像没有 —— 这是唯一的辨识依据，别靠动作和血条认人。镜像免疫法术，必须用物理命中打碎；它们会站到你四周，并在观澜出招时复读同一式，只有半伤。它一换镜，真身就暴露 1.2 秒 —— 那是最稳的输出窗口。",
		"mechanic_points": [
			"识真：真身脚下有倒影并随它移动；镜像会走位、带假血条，唯一破绽是没有倒影",
			"镜像：一阶段上限 2 具、二阶段 3 具；从玩家四周站起；会周期补斩，并在观澜出招时复读同一式（伤害 50%）；法术免疫，物理命中一击即碎",
			"换镜：真身与镜像换位，换位后真身暴露 1.2 秒、受到伤害 +20% —— 这是最稳的输出窗口",
			"碎镜：捏碎一具镜像，110 范围水伤 + 「镜滞」2 秒（移速 -30%）",
			"镜返：1.2 秒架势，第一次物理近战 / 投掷被挡下并奉还 35% 水属术法伤害；术法照吃",
			"水镜环：脚下 150 范围水场，持续 3 秒，每 0.8 秒结算水伤并刷新镜滞",
			"万镜归一（二阶段）：130° 扇形，命中时所有镜像同帧补刀",
			"首战可破：不需要本关功法；物理命中碎镜，任意属性功法打真身；没有势条、不攒层、不引爆",
			"玩家继承：任意功法出手（召镜两式除外）都会让场上所有镜像同时复读同一招 —— 50% 伤害，不论是否命中，放完即碎",
			"玩家继承：镜花 / 万镜召镜上限 2 具，带被动「照影」3 具并在完美闪避后免费留一具；换镜带 0.6 秒无敌，碎镜范围减速，镜湖铺场",
			"玩家侧镜返：挡下打过来的术法，并按 100% 原样反弹回去",
		],
		"status_note": "镜滞使移动速度 -30%，由碎镜与水镜环施加；BOSS 的镜返架势只挡物理近战 / 投掷，挡下后一次性消耗。玩家侧的镜返相反：挡的是打过来的术法，并按 100% 原样反弹。",
		"status_extra": [
			{"id": "mirror_slow", "time": 2.0, "source": "碎镜 / 水镜环"},
		],
	},
	"boss_04_b": {
		"subtitle": "照影界 · 第二关",
		"epithet": "照影影主 · 影子比自己先动手的人",
		"portrait": "res://assets/ui/codex/card_boss_zhizhu.png",
		"tags": ["人形", "投影", "影身", "光源", "元婴"],
		"mechanic_title": "投影 · 身外之影",
		"intro_hint": "战场只有一盏界灯。要躲的不是它的手，是地上那条影子 —— 影子铺到哪儿，它就打得到哪儿。",
		"mechanic": "全场只有一盏界灯，执烛不亲自打你 —— 它把影子铺在地上打你。影子从它脚下朝背离灯的方向铺开，它离灯越远影子越长，所以它的射程是走位问题：把它逼到灯下，远程招当场够不着。血量到一半它把灯提进自己手里，规则翻转，改成用你自己的影子结算。",
		"mechanic_points": [
			"影身就是它的射程：从它脚下背灯铺开，灯正下方只剩脚边一截",
			"逼灯：把它压到灯下，投晷 / 缚影射程跟着塌 —— 拆招靠站位，不靠减免",
			"它会抢位：影子盖不住你时，踏到灯的另一侧把影子重新拉长 —— 你跟着绕，别直线后退",
			"明灭：它把灯捻暗 4.5 秒，自己变强也变脆 —— 这段时间是你的输出窗口",
			"可弹反：削影 / 投晷 / 缚影 / 踏灯 / 分影 / 长夜；弹反成功，影子折回来斩它自己",
			"不可弹反：照骨是法术光束，只能走位让开 —— 贴脸混不过去",
			"缚影看你在不在动：一直走只吃一段墨痕减速；站住才被钉在原地（钉住仍能出手）",
			"分影：影子脱手独立横扫 5.2 秒，代价是它自己受伤加重、且用不了三招 —— 硬开的窗口",
			"二阶段·夺灯：它不再有影子，改以你脚下的影带结算；带子在你身后，后退等于走进自己的影子 —— 只能侧移或朝它压出去",
			"首战可破：普攻与任意属性功法都能打本体，物理可弹反，影身靠走位退出；没有势条、不攒层、不引爆",
			"玩家继承：跑动与突进把灯笼甩远、影子拉长，影系招式射程 = 当前影长；被动「执灯」影长 ×1.3，完美闪避后 2 秒拉满",
			"首杀必得：化神天髓（半枚）—— 与化神底髓在锻造台熔铸成化神破境晶",
		],
		"status_note": "影缚：被钉在原地，无法移动与闪避，但仍然可以出手 —— 由缚影（按住时）与长夜 · 一灯施加。影没：移动速度 -35%，由投晷 / 踏灯 / 照骨 / 分影以及缚影抓空时的墨痕施加。蚀：它八式全是暗属性，打中你就不只掉血 —— 你的物抗 / 法抗 / 元素抗数值先被打穿四成再算减免，期间受到的治疗只剩 10%（丹药、水愈符、气环·回息、续命灯一起压）。同一目标 9 秒内只会被挂上一次，所以它是节奏压力而不是常驻惩罚。弹反或闪避挡掉的暗击不挂蚀：元素交互跟着「这一下真的打中了」走。影缚与影没都是走位问题，蚀是走位与回复的双重问题，不是资源问题。",
		"status_extra": [
			{"id": "shadow_bind", "time": 1.1, "source": "缚影（起手时站定）/ 长夜 · 一灯"},
			{"id": "shadow_soak", "time": 2.0, "source": "投晷 / 踏灯 / 照骨 / 分影 / 缚影抓空"},
			# 蚀是**元素规则**（暗属性命中自动挂），不在任何 form 的 debuff_on_hit 里，
			# 所以必须走 status_extra 登记，否则图鉴会漏掉一个玩家一定会中的状态。
			{"id": "dark_erosion", "time": 6.0, "source": "全部暗属性招式（影系八式）"},
		],
	},
	"boss_04_c": {
		"subtitle": "照影界 · 第三关",
		"epithet": "叠纸 · 把战场折起来的那位",
		"portrait": "res://assets/ui/codex/card_boss_diezhi.png",
		"tags": ["人形", "折痕", "空间连通", "对位区", "元婴"],
		"mechanic_title": "折影为径 · 空间连通",
		"intro_hint": "照影界是一张纸。地上一条折痕把相距很远的两块纸面贴在一起 —— 要防的不是它的手，是「折过来之后的你」。离折痕够远，它这一面就永远碰不到你。",
		"mechanic": "场上有一条发光的折痕。任何一击同时判定两处：出手者脚下，以及目标关于这条痕的镜像位置。镜像那一半有条件 —— 目标必须和出手者分处痕的两侧，且到痕的垂直距离落在贴合带内（一折 300，二折 260）。超出这条带，就等于那块纸根本没被折过来，镜像必然落空，所以「离痕远」是空手也能用的解法。折痕两端各有一枚同号圆牌，踩进这头会从那头走出来。血量到一半它落下第二条平行折痕，战场被切成三个互通区，终局招同时朝三区落掌。",
		"mechanic_points": [
			"折痕：地面上一条线段，把相距很远的两块纸面贴在一起；每一击都同时判定本体与镜像两处",
			"贴合带：只有「目标与它分处两侧」且「目标到痕的垂直距离 ≤ 300（二阶段 260）」时镜像才成立 —— 站得比这更远，镜像那一面绝对打不到你",
			"对位圆牌：痕的两端各一枚，同色同号成对。踩进这头就从那头走出来（这一步叫穿缝），方向不变、距离缩短；穿缝之后下一次攻击加重（被动「量折」）",
			"换痕：每 15 秒重新折一次，换之前有 1.2 秒压痕预告。刚找到的安全位置会当场作废，别把保命押在同一条痕上",
			"按纸：一掌按下去，痕对侧同时按出你的位置 —— 你以为躲开了正面，其实背面也在判定里",
			"循痕：顺着痕滑出去，掠过的痕线上两面一起割；它把痕当高速路，贴脸不等于安全",
			"跨缝：从这头的圆牌钻进去、从那头的圆牌出来，落点在你身后 —— 背后那张纸会先立起来",
			"押痕（反站远）：把折痕立在你们正中间、垂直于连线，折过来之后你的位置正好在它掌下。这一式有距离上限，退到两倍贴合带以外它就压不到",
			"碎痕（反蹲点）：不靠镜像，沿痕直接撕开一条宽 220 的长直线 —— 站着不动、缩在掩体后都躲不掉",
			"唯一的免费窗口：碎痕撕完 4 秒内全场折痕作废，双方都没有镜像落点。这段时间是白打，但要用一记重击换",
			"叠掩：折一层纸护身，首次受击大减，且这段时间它没有对位面 —— 你的镜像落点也借不走",
			"二阶段 · 折两次：落下第二条平行痕，三个互通区成立；终局招「三重落纸」三区同时落掌，你只能站在其中一个里",
			"可弹反：按纸 / 循痕 / 跨缝（都是物理）；弹反成功，纸面折回来割它自己",
			"不可弹反：押痕 / 碎痕 / 双屏 / 三重落纸全是术法，只能走位让开",
			"纸印：被镜像落点按住后 4 秒内，对你生效的贴合带放宽 120 —— 带着纸印还赖在痕边上，就是自己把退路交出去",
			"首战可破：普攻与任意属性功法都能打本体，破解只需要读地上那条痕，不需要任何叠纸功法；没有势条、不攒层、不引爆",
			"玩家继承：裁痕自己造一道只属于你的痕，八式全部自带镜像落点；穿圆牌后下一次攻击加重（被动「量折」）",
			"掉落：照影纸痕（本界第三件专属材料）+ 纸错剑（普攻第三段变前后夹击）+ 折痕佩（受击后位移折一下）",
			"三件照影专属材料在锻造台熔铸可得位面法宝「照影·迟照符」：受伤暂缓结算，以闪避 / 弹反 / 断招逐笔抹去",
		],
		"status_note": "纸印：这块纸被压皱了，折痕对你的贴合带放宽 120，需要离痕更远才脱开 —— 由按纸 / 循痕 / 押痕 / 碎痕施加。它是走位问题，不是减免问题。",
		"status_extra": [
			{"id": "fold_mark", "time": 4.0, "source": "按纸 / 循痕 / 押痕 / 碎痕"},
		],
	},

	# ===== 大世界核心首领（2026-10-28）=====
	## 不属任何位面关卡，图鉴单独收一张；world_region 让解锁 / 属性回查 SecretWorldDB。
	"world_core_lianqi": {
		"subtitle": "苍澜大陆 · 青岚野 · 练气",
		"epithet": "青岚野的老山主",
		"portrait": "res://assets/ui/codex/card_boss_core_ape.png",
		"tags": ["兽型", "核心首领", "投石", "二阶段"],
		"mechanic_title": "山野石主 · 距离选招",
		"intro_hint": "投石可弹反；二阶段山崩地裂与青岚灵爆为木属性法术，需离开落点。",
		"domain": "苍澜大陆",
		"world_region": "world_lianqi",
		"mechanic": "青岚古猿按距离选择招式：近距离双拳砸地，中距离拔石投掷，远距离扇形乱石。近战扇面覆盖正面；绕到身后可避开正面扇面。投石与乱石是物理投射物，可弹反；二阶段解锁山崩地裂与青岚灵爆，二者均为木属性法术，不可弹反，需要离开落点。该核心首领每个角色只击杀一次。",
		"mechanic_points": [
			"首杀必得：筑基底髓（半枚）—— 与凡界第三位的筑基天髓熔铸成筑基破境晶",
			"距离选招：近距砸地 / 中距拔石 / 远距乱石",
			"近战扇面覆盖正面，绕到身后可避开",
			"投石与乱石是物理投射物，可弹反",
			"二阶段解锁山崩地裂与青岚灵爆；二者为木属性法术，不可弹反",
			"每个角色只击杀一次",
		],
	},
	"world_core_zhuji": {
		"subtitle": "苍澜大陆 · 云隐谷 · 筑基",
		"epithet": "云隐谷的苔石古鹿",
		"portrait": "res://assets/ui/codex/card_boss_core_stag.png",
		"tags": ["兽型", "核心首领", "苔甲", "雾隐", "二阶段"],
		"mechanic_title": "苔甲护身 · 雾隐寻真",
		"intro_hint": "三片苔甲各需 3 次攻击；二阶段雾隐时只有真身角尖发冷蓝光，命中真身可识破。",
		"domain": "苍澜大陆",
		"world_region": "world_zhuji",
		"mechanic": "它身上悬着三片苔甲：甲片还在时受伤 -42%；每片要 3 次攻击才碎，弹反它的角撞或角扫可以直接碎一片。三片碎完，护甲就没了。半血后它每 12 秒进一次雾隐、留下三团雾影 —— 只有真身的角尖亮冷蓝光，认出真身就能识破。",
		"mechanic_points": [
			"苔甲 3 片：每片需 3 次攻击；存在时受伤 -42%；弹反角撞或角扫可击碎 1 片",
			"三片全部破碎后护甲消失，受伤回到 100%",
			"二阶段（50% 气血）：每 12 秒雾隐 2.4 秒，留下 3 团雾影；真身角尖显示冷蓝光",
			"命中真身可识破；未识破时雾爆半径 260，法术 ×0.80",
			"物理：角撞 / 角扫 / 落石，可弹反；法术：雾吐 / 古根 / 鹿鸣，不可弹反",
			"首杀奖励：结丹底髓（半枚，与冲和界第三位的结丹天髓熔铸）+ 苍角甲",
			"物理可弹反：角撞 / 角扫 / 落石；法术不可弹反：雾吐 / 古根 / 鹿鸣",
			"雾隐未识破时雾爆半径 260、法术 ×0.80",
			"首杀奖励：结丹底髓（半枚，与冲和界第三位的结丹天髓熔铸成结丹破境晶）+ 苍角甲",
		],
	},
	"world_core_shihou": {
		"subtitle": "苍澜大陆 · 幽冥灵墟 · 元婴",
		"epithet": "九天门前的守墓石兽",
		"portrait": "res://assets/ui/codex/card_boss_core_shihou.png",
		"tags": ["兽型", "核心首领", "闻声", "石碣", "二阶段"],
		"mechanic_title": "闻声 · 盲兽寻踪",
		"intro_hint": "它看不见：跑动、出手、施法、闪避都会留下声点；扑与撞只打旧声点。引它撞石碣可拿硬直。",
		"domain": "苍澜大陆",
		"world_region": "world_yuanying",
		"mechanic": "它看不见，只追你最后一次发出声响的位置：跑动、出手、施法、闪避都会留声点，站住 0.35 秒它就跟丢。它的盲扑与崩山撞都砸在那个旧点上，所以「先骗一步、再走开」本身就是防御。墓庭里立着六根石碣：引它撞上去，它硬直 2 秒、受伤 +25%。",
		"mechanic_points": [
			"盲视：只追最后声点；跑动 / 出手 / 施法 / 闪避留声，静步 0.35 秒跟丢",
			"盲扑 / 崩山撞 / 闻声吐息都打旧点；扑与撞会在声点显示预警",
			"石碣：引它撞碑 → 硬直 2 秒、受伤 +25% 5 秒；每碑承受 2 次撞击",
			"二阶段（50%）：塌 2 碑、脚步 0.3 秒、回声定位（移动被扫到会暴露；静止安全）",
			"长吼后自聋 2 秒 = 换位窗口；吐息后自聋 2.5 秒",
			"物理可弹反；吐息为风法术不可弹反",
			"首杀奖励：化神底髓（半枚，与照影界第三位的化神天髓熔铸成化神破境晶）",
			"身后那道九天门通往九天之上：带齐熔铸好的化神破境晶、修为到元婴后期圆满才能开门，进门后在化神坛突破",
		],
	},
	"world_core_jiedan": {
		"subtitle": "苍澜大陆 · 赤金丹霞 · 结丹",
		"epithet": "丹霞地火所化的火麟",
		"portrait": "res://assets/ui/codex/card_boss_core_qilin.png",
		"tags": ["兽型", "核心首领", "日轮", "霞印", "二阶段"],
		"mechanic_title": "霞印灼身 · 日轮当空",
		"intro_hint": "招式命中叠霞印，三层触发日蚀；弹反物理招可清除一层。二阶段日轮落地后，外圈灼土与轮下都会叠印，需离开预警圈。",
		"domain": "苍澜大陆",
		"world_region": "world_jiedan",
		"mechanic": "它的招式命中会给你叠「霞印」，最多 3 层，叠满当场触发日蚀爆炸 —— 除裂岩冲与普攻外都叠。弹反它任意物理招式能清掉 1 层，所以弹反就是拆弹。半血后日轮落到场心、外圈变灼土，站在轮下还会多叠 1 层。",
		"mechanic_points": [
			"霞印：除火麟裂岩冲与普攻外，其余招式命中各叠 1 层，最多 3 层；3 层触发日蚀爆炸",
			"弹反任意物理招式可清除 1 层霞印",
			"霞印显示为 3 枚绕身日轮，层数可读",
			"二阶段（50% 气血）：日轮落场心，外圈灼土定期脉冲；站轮下额外叠 1 层",
			"物理：裂岩冲 / 踏霞地火 / 赤金三连，可弹反；法术：火雨 / 阳炎 / 日冕环 / 日蚀 / 陨日，不可弹反",
			"首杀奖励：元婴底髓（半枚，与赤霄界第三位的元婴天髓熔铸）+ 火麟甲",
		],
	},
}

## 获取方式：按模板 / 材料 id 登记。新增条目未登记时显示兜底文案，不会漏掉图鉴项。
const SOURCES: Dictionary = {
	"eq_cangjiao_jia": "苍澜大陆 · 云隐谷核心首领「云隐苍角」击败掉落",
	"eq_huolin_jia": "苍澜大陆 · 赤金丹霞核心首领「赤金火麟」击败掉落",
	"eq_zhenxu_jia": "苍澜大陆 · 幽冥灵墟核心首领「镇墟石犼」击败掉落",
	"mat_jd_xuecao": "苍澜大陆·赤金丹霞采集赤金血参；丹霞野修也可能掉落",
	"mat_jd_lanyingcao": "苍澜大陆·赤金丹霞采集赤金蓝萤草；丹霞野修也可能掉落",
	"mat_jd_liyuanguo": "苍澜大陆·赤金丹霞采集赤金力元果；丹霞野修也可能掉落",
	"mat_jd_falinghua": "苍澜大陆·赤金丹霞采集赤金法灵花；丹霞野修也可能掉落",
	"mat_jd_huguteng": "苍澜大陆·赤金丹霞采集赤金护骨藤；丹霞野修也可能掉落",
	"mat_jd_ruishoupi": "苍澜大陆·赤金丹霞击败赤鬃锋牙兽；丹霞野修也可能掉落",
	"mat_jd_jianshoupi": "苍澜大陆·赤金丹霞击败赤岩坚甲兽；丹霞野修也可能掉落",
	# 幽冥灵墟（元婴）材料
	"mat_yy_xuecao": "苍澜大陆·幽冥灵墟采集幽冥血参；幽冥野修也可能掉落",
	"mat_yy_lanyingcao": "苍澜大陆·幽冥灵墟采集幽冥蓝萤草；幽冥野修也可能掉落",
	"mat_yy_liyuanguo": "苍澜大陆·幽冥灵墟采集幽冥力元果；幽冥野修也可能掉落",
	"mat_yy_falinghua": "苍澜大陆·幽冥灵墟采集幽冥法灵花；幽冥野修也可能掉落",
	"mat_yy_huguteng": "苍澜大陆·幽冥灵墟采集幽冥护骨藤；幽冥野修也可能掉落",
	"mat_yy_ruishoupi": "苍澜大陆·幽冥灵墟击败幽冥锋牙兽；幽冥野修也可能掉落",
	"mat_yy_jianshoupi": "苍澜大陆·幽冥灵墟击败幽冥坚甲兽；幽冥野修也可能掉落",
	# 定阵先生掉落
	"eq_zhuxian_chizhang": "冲和界「定阵先生」击败掉落",
	"eq_dingzhen_chanwan": "冲和界「定阵先生」击败掉落",
	"mat_zhusha_zhending": "冲和界「定阵先生」击败 20% 掉落（冲和界专属材料）",
	"eq_taixu_yunlv": "冲和界「太虚气君」击败掉落",
	"eq_qihai_yuzhui": "冲和界「太虚气君」击败掉落",
	"mat_taixu_qijing": "冲和界「太虚气君」击败 20% 掉落（冲和界专属材料）",
	"soul_qi": "万界塔第 6 层投影 · 太虚气君掉落（塔 11+ 50%）",
	"tr_qi_ling": "锻造台·合成：太虚气君元魂 + 任一破损的气君装备",
	"eq_leiwen_huqi": "赤霄界「赫连霄」击败掉落",
	"eq_panguan_tiebi": "赤霄界「赫连霄」击败掉落",
	"mat_chixiao_leijing": "赤霄界「赫连霄」击败 20% 掉落（赤霄界专属材料）",
	"soul_helianxiao": "万界塔第 7 层投影 · 赫连霄掉落（塔 11+ 50%）",
	"tr_panguan_ling": "锻造台·合成：赫连霄元魂 + 任一破损的判官装备",
	"eq_jinwen_zhanpao": "赤霄界「离照」击败掉落",
	"eq_zhuri_lv": "赤霄界「离照」击败掉落",
	"mat_chixiao_risui": "赤霄界「离照」击败 20% 掉落（赤霄界专属材料）",
	"soul_lizhao": "万界塔第 8 层投影 · 离照掉落（塔 11+ 50%）",
	"tr_huozheng_ling": "锻造台·合成：离照元魂 + 任一破损的日纹装备",
	"eq_jiefeng": "赤霄界「晏无咎」击败掉落",
	"eq_jiehui_fayi": "赤霄界「晏无咎」击败掉落",
	"mat_chixiao_jiehui": "赤霄界「晏无咎」击败 20% 掉落（赤霄界专属材料）",
	"soul_yanwujiu": "万界塔第 9 层投影 · 晏无咎掉落（塔 11+ 50%）",
	"tr_jiezhu_ling": "锻造台·合成：晏无咎元魂 + 任一破损的劫纹装备",
	"tr_sanzai_lun": "锻造台·熔铸：赤霄雷晶 + 赤霄日髓 + 赤霄劫灰（赤霄界专属法宝）",
	"eq_jingtan_chi": "照影界「观澜」击败掉落",
	"eq_shuiyue_pao": "照影界「观澜」击败掉落",
	"mat_zhaoying_jingsha": "照影界「观澜」击败 20% 掉落（照影界专属材料）",
	"soul_guanying": "万界塔第 10 层投影 · 观澜掉落（塔 11+ 50%）",
	"tr_guanying_ling": "锻造台·合成：观澜元魂 + 任一破损的镜纹装备",
	"eq_changye_ren": "照影界「执烛」击败掉落",
	"eq_zhului_zhui": "照影界「执烛」击败掉落",
	"mat_zhaoying_zhulei": "照影界「执烛」击败 20% 掉落（照影界专属材料）",
	"soul_zhizhu": "万界塔第 11 层投影 · 执烛掉落（塔 12+ 50%）",
	"tr_zhizhu_ling": "锻造台·合成：执烛元魂 + 任一破损的执烛装备",
	"eq_zhicuo_jian": "照影界「叠纸」击败掉落",
	"eq_zhehen_pei": "照影界「叠纸」击败掉落",
	"mat_zhaoying_zhihen": "照影界「叠纸」击败 20% 掉落（照影界专属材料）",
	"soul_diezhi": "万界塔第 12 层投影 · 叠纸掉落（血量翻倍阶段 50%）",
	"tr_diezhi_ling": "锻造台·合成：叠纸元魂 + 任一破损的叠纸装备",
	"tr_zhaoying_zhefu": "锻造台·熔铸：照影镜砂 + 照影烛泪 + 照影纸痕（照影界专属法宝）",
	"tr_blade_form": "锻造台·熔铸：界门虎牙 + 凡铁断刃 + 清风剑屑（凡界专属法宝）",
	"mat_fanjie_huya": "万界位面·凡界「虎妖」击败掉落（20%）",
	"mat_fanjie_duanren": "万界位面·凡界「刀客」击败掉落（20%）",
	"mat_fanjie_jianxie": "万界位面·凡界「剑客」击败掉落（20%）",
	"soul_dingzhen": "万界塔第 5 层投影 · 定阵先生掉落（塔 11+ 50%）",
	# ---------- 装备 ----------
	"eq_fanpinwandao": "万界位面·凡界「刀客」击败掉落",
	"eq_tiejian": "首次进入原初位面时自动获得并装备",
	"eq_hupipao": "万界位面·凡界「虎妖」击败掉落",
	"eq_tengjia": "苍澜大陆·练气区核心首领「青岚古猿」首杀掉落",
	"eq_huyaxianglian": "万界位面·凡界「虎妖」击败掉落",
	"eq_qingfengjian": "万界位面·凡界「剑客」击败掉落",
	"eq_qingfengxie": "万界位面·凡界「剑客」击败掉落",
	"eq_liangyi_yujue": "冲和界「两仪真人」击败掉落",
	"eq_xuansu_daopao": "冲和界「两仪真人」击败掉落",
	# ---------- 法宝 ----------
	"tr_huyao_ling": "锻造台·合成：虎妖元魂 + 任一破损的虎妖装备",
	"tr_daoke_ling": "锻造台·合成：刀客元魂 + 破损的弯刀",
	"tr_jianke_ling": "锻造台·合成：剑客元魂 + 任一破损的剑客装备",
	"tr_liangyi_ling": "锻造台·合成：两仪真人元魂 + 任一破损的两仪装备",
	"tr_zhenqi_ling": "锻造台·合成：定阵先生元魂 + 任一破损的阵师装备",
	"tr_taiji_pan": "集齐冲和界三件专属材料（两仪玄石 / 朱砂阵钉 / 太虚气晶）在锻造台熔铸页投入，任意顺序自动识别合成",
	"tr_ningshuipei": "苍澜大陆·各区域击败野修，100% 掉落其携带法宝",
	"tr_zhudianhuan": "苍澜大陆·各区域击败野修，100% 掉落其携带法宝",
	"tr_jinbu_zhuang": "苍澜大陆·练气区起，击败野修 100% 掉落其携带法宝",
	"tr_duannian_ling": "苍澜大陆·筑基区起，击败野修 100% 掉落其携带法宝",
	"tr_xuming_deng": "苍澜大陆·结丹区起，击败野修 100% 掉落其携带法宝",
	"tr_shixi_zhui": "苍澜大陆·元婴区击败野修，100% 掉落其携带法宝",
	"tr_jijia_pei": "苍澜大陆·筑基区起，击败野修 100% 掉落其携带法宝",
	"tr_huifeng_dai": "苍澜大陆·筑基区起，击败野修 100% 掉落其携带法宝",
	"tr_xuesi_yin": "苍澜大陆·结丹区起，击败野修 100% 掉落其携带法宝",
	"tr_huanwei_jue": "苍澜大陆·结丹区起，击败野修 100% 掉落其携带法宝",
	# ---------- 材料 ----------
	"mat_duanzaojingshi": "万界塔通关掉落；无伤通关可在塔面板额外领取",
	"soul_huyao": "万界塔·虎妖层第 11 次及以后通关，50% 概率掉落",
	"soul_daoke": "万界塔·刀客层第 11 次及以后通关，50% 概率掉落",
	"soul_jianke": "万界塔·剑客层第 11 次及以后通关，50% 概率掉落",
	"soul_liangyi": "万界塔·第 4 层（两仪真人）第 11 次及以后通关，50% 概率掉落",
	"mat_liangyi_xuanshi": "冲和界「两仪真人」击败 20% 掉落（冲和界专属材料）",
	"mat_xuecao": "苍澜大陆·青岚野采集青岚血参；野修也可能掉落",
	"mat_lanyingcao": "苍澜大陆·青岚野采集青岚蓝萤草；野修也可能掉落",
	"mat_liyuanguo": "苍澜大陆·青岚野采集青岚力元果；野修也可能掉落",
	"mat_falinghua": "苍澜大陆·青岚野采集青岚法灵花；野修也可能掉落",
	"mat_huguteng": "苍澜大陆·青岚野采集青岚护骨藤；野修也可能掉落",
	"mat_ruishoupi": "苍澜大陆·青岚野击败锋牙兽；野修也可能掉落",
	"mat_jianshoupi": "苍澜大陆·青岚野击败坚甲兽；野修也可能掉落",
	"mat_zj_xuecao": "苍澜大陆·云隐谷采集云隐血参；云隐野修也可能掉落",
	"mat_zj_lanyingcao": "苍澜大陆·云隐谷采集云隐蓝萤草；云隐野修也可能掉落",
	"mat_zj_liyuanguo": "苍澜大陆·云隐谷采集云隐力元果；云隐野修也可能掉落",
	"mat_zj_falinghua": "苍澜大陆·云隐谷采集云隐法灵花；云隐野修也可能掉落",
	"mat_zj_huguteng": "苍澜大陆·云隐谷采集云隐护骨藤；云隐野修也可能掉落",
	"mat_zj_ruishoupi": "苍澜大陆·云隐谷击败云隐锋牙兽；云隐野修也可能掉落",
	"mat_zj_jianshoupi": "苍澜大陆·云隐谷击败云隐坚甲兽；云隐野修也可能掉落",
	# ===== 破境材料：残晶 → 锻造台熔铸 → 完整晶（2026-11-02 用户定）=====
	## 地髓出自各境界大陆区域核心首领首杀，天髓出自对应位面第三位 BOSS 首杀，
	## 两枚在锻造台「熔铸」页合璧成完整破境晶 —— 只有完整晶才算大突破材料。
	"mat_pojing_di_zhuji": "苍澜大陆·练气区核心首领「青岚古猿」首杀必得（半枚地髓）",
	"mat_pojing_tian_zhuji": "万界位面·凡界第三位「剑客」首杀必得（半枚天髓）",
	"mat_pojing_zhuji": "锻造台「熔铸」：筑基底髓 + 筑基天髓合璧",
	"mat_pojing_di_jiedan": "苍澜大陆·云隐谷核心首领「云隐苍角」首杀必得（半枚地髓）",
	"mat_pojing_tian_jiedan": "万界位面·冲和界第三位「太虚气君」首杀必得（半枚天髓）",
	"mat_pojing_jiedan": "锻造台「熔铸」：结丹底髓 + 结丹天髓合璧",
	"mat_pojing_di_yuanying": "苍澜大陆·赤金丹霞核心首领「赤金火麟」首杀必得（半枚地髓）",
	"mat_pojing_tian_yuanying": "万界位面·赤霄界第三位「晏无咎」首杀必得（半枚天髓）",
	"mat_pojing_yuanying": "锻造台「熔铸」：元婴底髓 + 元婴天髓合璧",
	"mat_pojing_di_huashen": "苍澜大陆·幽冥灵墟核心首领「镇墟石犼」首杀必得（半枚地髓）",
	"mat_pojing_tian_huashen": "万界位面·照影界第三位 BOSS 首杀必得（半枚天髓；第三位未落地前由末位「执烛」代发）",
	## 化神例外：完整晶不吃在境界面板，而是拿去幽冥灵墟中心的九天门开门，进门后在化神坛突破
	"mat_pojing_huashen": "锻造台「熔铸」：化神底髓 + 化神天髓合璧 · 九天门的门票",
}


static func categories() -> Array:
	return CATEGORIES


## 某卷目的二级分类；没有二级分类的卷目返回只有「全部」。
static func subcategories(category_id: String) -> Array:
	return SUB_CATEGORIES.get(category_id, [{"id": SUB_ALL, "title": "全部"}])


static func category_title(category_id: String) -> String:
	for c in CATEGORIES:
		if String((c as Dictionary).get("id", "")) == category_id:
			return String((c as Dictionary).get("title", ""))
	return ""


static func _treasure_group(entry: Dictionary) -> String:
	var tpl: Dictionary = entry.get("template", {})
	if String(tpl.get("summon_boss_id", "")) != "":
		return SUB_SUMMON
	if String(tpl.get("active_type", "")) != "":
		return SUB_ACTIVE
	return SUB_OTHER


static func _material_group(entry: Dictionary) -> String:
	var realm := String(entry.get("realm", ""))
	if realm in [SUB_REALM_LIANQI, SUB_REALM_ZHUJI, SUB_REALM_JIEDAN, SUB_REALM_YUANYING]:
		return realm
	return SUB_OTHER


static func _filter_entries(entries: Array, category_id: String, sub_id: String) -> Array:
	if sub_id == "" or sub_id == SUB_ALL:
		return entries
	var out: Array = []
	for raw in entries:
		var e: Dictionary = raw
		var group := ""
		match category_id:
			CAT_EQUIPMENT:
				group = String(e.get("equip_type", ""))
			CAT_TREASURE:
				group = _treasure_group(e)
			CAT_MATERIAL:
				group = _material_group(e)
		if group == sub_id:
			out.append(e)
	return out


static func category_entries(category_id: String, sub_id: String = SUB_ALL) -> Array:
	var out: Array = []
	match category_id:
		CAT_BOSS:
			return boss_entries(sub_id)
		CAT_PACK:
			return card_entries()
		CAT_EQUIPMENT:
			for tpl in ItemDB.EQUIPMENT_TEMPLATES:
				# 开发者武器（房主神器）只在 F2 调试面板发放，不进玩家图鉴
				if bool((tpl as Dictionary).get("dev_only", false)):
					continue
				out.append(_make_entry(CAT_EQUIPMENT, tpl))
		CAT_TREASURE:
			for tpl in ItemDB.TREASURE_TEMPLATES:
				out.append(_make_entry(CAT_TREASURE, tpl))
		CAT_MATERIAL:
			for tpl in ItemDB.MATERIALS:
				out.append(_make_entry(CAT_MATERIAL, tpl))
		CAT_ROGUE_CARD:
			return rogue_card_entries(sub_id)
	return _filter_entries(out, category_id, sub_id)


# ===================== 试炼卡牌（2026-11-09）=====================

## 一张卡的叠加上限：传说固定 1 层，其余读卡表 max，缺省 = MAX_STACKS
static func _rogue_stack_of(def: Dictionary) -> int:
	if String(def.get("rarity", "")) == RogueDB.RARITY_LEGEND:
		return RogueDB.MAX_STACKS_LEGEND
	return int(def.get("max", RogueDB.MAX_STACKS))


static func _rogue_card_row(def: Dictionary, family: String) -> Dictionary:
	return {
		"id": String(def.get("id", "")),
		"name": String(def.get("name", "")),
		"desc": String(def.get("desc", "")),
		"rarity": String(def.get("rarity", "common")),
		"family": family,
		"cap": _rogue_stack_of(def),
	}


## 全部试炼卡（可只取某一稀有度）。顺序固定：通用在前，其后按入口页的流派顺序。
## ⚠ 数据源只有 RogueDB.POOLS 一张表：这里绝不复制一份卡表，改卡只改那边。
static func rogue_card_entries(sub_id: String = SUB_ALL) -> Array:
	var out: Array = []
	var fams: Array = ["generic"]
	for f in RogueDB.FAMILY_ORDER:
		fams.append(String(f))
	for fam in fams:
		var key := String(fam)
		if not RogueDB.POOLS.has(key):
			continue
		for raw in RogueDB.POOLS[key]:
			var def: Dictionary = raw
			var rarity := String(def.get("rarity", "common"))
			if sub_id != "" and sub_id != SUB_ALL and rarity != sub_id:
				continue
			out.append(_rogue_card_row(def, key))
	return out


## 按流派分组（图鉴列表用）：每组带解锁层与是否已开放
static func rogue_card_groups() -> Array:
	var out: Array = []
	var fams: Array = ["generic"]
	for f in RogueDB.FAMILY_ORDER:
		fams.append(String(f))
	var best := CharacterData.rogue_best_floor
	for fam in fams:
		var key := String(fam)
		if not RogueDB.POOLS.has(key):
			continue
		var need := int(RogueDB.FAMILY_UNLOCK_FLOOR.get(key, 0))
		var cards: Array = []
		for raw in RogueDB.POOLS[key]:
			cards.append(_rogue_card_row(raw as Dictionary, key))
		out.append({
			"family": key,
			"title": String(RogueDB.FAMILY_NAME.get(key, key)),
			"unlock_floor": need,
			"unlocked": need <= best,
			"cards": cards,
		})
	return out


# ===================== BOSS 卡面 =====================

## 只列已经做进项目的 BOSS（有战斗场景映射的），按位面顺序排；
## 占位 BOSS 不进图鉴（空 BOSS 不主动提示）。
static func boss_entries(sub_id: String = SUB_ALL) -> Array:
	var out: Array = []
	for d in WorldDB.DOMAINS:
		for b in (d as Dictionary).get("boss_ids", []):
			var bid := String(b)
			if not WorldDB.BOSS_SCENES.has(bid):
				continue
			var e := boss_entry(bid)
			if not e.is_empty():
				out.append(e)
	# 大世界核心首领不属于位面关卡，单独补在最后（空 BOSS 仍然不进图鉴）
	for core_id in CORE_BOSS_IDS:
		var core_entry := boss_entry(core_id)
		if not core_entry.is_empty():
			out.append(core_entry)
	if sub_id == SUB_FLOOR:
		return out.filter(func(e: Dictionary) -> bool: return not bool(e.get("world_boss", false)))
	if sub_id == SUB_WORLD:
		return out.filter(func(e: Dictionary) -> bool: return bool(e.get("world_boss", false)))
	return out


static func boss_entry(boss_id: String) -> Dictionary:
	if not BOSS_CODEX.has(boss_id):
		return {}
	var meta: Dictionary = BOSS_CODEX[boss_id]
	var domain := String(meta.get("domain", ""))
	if domain == "":
		for d in WorldDB.DOMAINS:
			if boss_id in (d as Dictionary).get("boss_ids", []):
				domain = String((d as Dictionary).get("name", ""))
				break
	var world_region := String(meta.get("world_region", ""))
	return {
		"id": boss_id,
		"category": CAT_BOSS,
		"name": WorldDB.get_boss_name(boss_id),
		"domain": domain,
		"world_boss": world_region != "",
		"world_region": world_region,
		"subtitle": String(meta.get("subtitle", "")),
		"epithet": String(meta.get("epithet", "")),
		"portrait": String(meta.get("portrait", "")),
		"tags": (meta.get("tags", []) as Array).duplicate(),
		"mechanic_title": String(meta.get("mechanic_title", "")),
		"intro_hint": String(meta.get("intro_hint", "")),
		"mechanic": String(meta.get("mechanic", "")),
		# 机制要点（短句，不带数值）与状态补充：卡片按模块分块显示
		"mechanic_points": (meta.get("mechanic_points", []) as Array).duplicate(),
		"status_extra": (meta.get("status_extra", []) as Array).duplicate(),
	}


# ===================== 卡包收藏 =====================

## 卡包条目：塔层 BOSS + 大世界核心首领（首领卡）
static func card_entries() -> Array:
	var out: Array = []
	for f in WorldDB.get_floors():
		var boss_id := String((f as Dictionary).get("boss_id", ""))
		if not BOSS_CODEX.has(boss_id) or not WorldDB.BOSS_SCENES.has(boss_id):
			continue
		var e := card_entry(boss_id)
		if not e.is_empty():
			out.append(e)
	for core_id in CORE_BOSS_IDS:
		var ce := card_entry(core_id)
		if not ce.is_empty():
			out.append(ce)
	return out


static func card_entry(boss_id: String) -> Dictionary:
	var base := boss_entry(boss_id)
	if base.is_empty():
		return {}
	var floor_no := 0
	for f in WorldDB.get_floors():
		if String((f as Dictionary).get("boss_id", "")) == boss_id:
			floor_no = int((f as Dictionary).get("floor", 0))
			break
	var cfg: Dictionary = HOLO_CARDS.get(boss_id, {})
	var world_region := String(base.get("world_region", ""))
	var boss_cleared := false
	var clear_count := 0
	var double_cleared := false
	var perfect_cleared := false
	var ink_cleared := false
	if world_region != "":
		var kills = CharacterData.secret_world.get("core_kills", {})
		boss_cleared = kills is Dictionary and bool((kills as Dictionary).get(world_region, false))
		# 核心分支重战与塔层同口径：第 11 次起双倍血，双倍血无伤解锁纯华彩
		clear_count = CharacterData.get_core_clear_count(world_region)
		double_cleared = clear_count >= HOLO_CLEAR_REQUIRED
		perfect_cleared = CharacterData.has_core_no_hit_double(world_region)
		var core_best := CharacterData.get_core_best_time(world_region)
		ink_cleared = boss_cleared and double_cleared \
			and core_best >= 0.0 and core_best <= INK_CLEAR_TIME_LIMIT
	elif floor_no > 0:
		# 塔层击败 / 万界位面击败同一只 BOSS 都算「普通卡到手」
		boss_cleared = CharacterData.get_tower_clear_count(floor_no) >= 1 \
			or is_boss_unlocked(boss_id)
		clear_count = CharacterData.get_tower_clear_count(floor_no)
		double_cleared = clear_count >= HOLO_CLEAR_REQUIRED
		perfect_cleared = CharacterData.has_tower_no_hit_double(floor_no)
		var tower_best := CharacterData.get_tower_best_time(floor_no)
		ink_cleared = boss_cleared and double_cleared \
			and tower_best >= 0.0 and tower_best <= INK_CLEAR_TIME_LIMIT

	var variants: Array = []
	# 1) 华彩 · 有背景：击败同层 / 同首领的双倍气血场次（默认封面，排第一）
	if (floor_no > 0 or world_region != "") and cfg.has("scene"):
		var s: Dictionary = SCENE_HOLO_STYLE.duplicate(true)
		s.merge(cfg.get("scene", {}) as Dictionary, true)
		s["unlocked"] = double_cleared
		variants.append(s)
	# 2) 普通卡：击败对应的塔层 / 大陆首领 BOSS
	var portrait := String(base.get("portrait", ""))
	if portrait != "":
		var p: Dictionary = PORTRAIT_CARD_STYLE.duplicate(true)
		p["art"] = portrait
		p["unlocked"] = boss_cleared
		variants.append(p)
	# 3) 纯华彩 · 无背景：无伤通关同层双倍气血 BOSS
	var art := String(cfg.get("art", ""))
	var lines := String(cfg.get("lines", ""))
	if (floor_no > 0 or world_region != "") and art != "" and lines != "":
		var v: Dictionary = PLAIN_HOLO_STYLE.duplicate(true)
		v["art"] = art
		v["lines"] = lines
		v["unlocked"] = perfect_cleared
		variants.append(v)
	# 以后加新卡种：按下面水墨的写法在 card_entry 里追加，或往 HOLO_CARDS[boss].styles 放一条。
	for extra in cfg.get("styles", []):
		if extra is Dictionary:
			var ex: Dictionary = (extra as Dictionary).duplicate(true)
			if not ex.has("unlocked"):
				ex["unlocked"] = boss_cleared
			variants.append(ex)

	# 纸本水墨：全量 BOSS 一套，双倍气血场次 10 秒内通关解锁（放在最后，不影响封面顺序）
	if INK_NOTES.has(boss_id):
		var ink: Dictionary = INK_STYLE.duplicate(true)
		ink["desc"] = String(INK_NOTES[boss_id]) + INK_DESC_TAIL
		ink["art"] = "res://assets/ui/codex/holo/%s_ink.png" % boss_id
		ink["reveal"] = "res://assets/ui/codex/holo/%s_ink_reveal.png" % boss_id
		ink["flow_tex"] = "res://assets/ui/codex/holo/%s_ink_flow.png" % boss_id
		ink["guard_tex"] = "res://assets/ui/codex/holo/%s_ink_guard.png" % boss_id
		ink["unlocked"] = ink_cleared
		variants.append(ink)

	var collected := 0
	for raw in variants:
		if bool((raw as Dictionary).get("unlocked", false)):
			collected += 1
	base["category"] = CAT_PACK
	base["floor"] = floor_no
	base["clear_count"] = clear_count
	base["card_variants"] = variants
	base["card_collected"] = collected
	base["card_total"] = variants.size()
	base["boss_cleared"] = boss_cleared
	base["double_cleared"] = double_cleared
	base["perfect_cleared"] = perfect_cleared
	base["ink_cleared"] = ink_cleared
	base["card_accent"] = cfg.get("accent", Color(0.86, 0.72, 0.42, 1.0))
	return base


## 卡序：只排已拥有的卡；存档里没有 / 旧卡被移除时，按 card_variants 默认顺序补齐
static func ordered_variants(entry: Dictionary) -> Array:
	var by_id: Dictionary = {}
	var owned: Array = []
	for raw in entry.get("card_variants", []):
		var v: Dictionary = raw
		if not bool(v.get("unlocked", false)):
			continue
		var cid := String(v.get("id", ""))
		if cid == "" or by_id.has(cid):
			continue
		by_id[cid] = v
		owned.append(cid)
	var out: Array = []
	var seen: Dictionary = {}
	var saved = CharacterData.card_order.get(String(entry.get("id", "")), [])
	if saved is Array:
		for raw_id in saved:
			var sid := String(raw_id)
			if by_id.has(sid) and not seen.has(sid):
				out.append(by_id[sid])
				seen[sid] = true
	for cid in owned:
		if not seen.has(cid):
			out.append(by_id[cid])
			seen[cid] = true
	return out


static func set_card_order(boss_id: String, ids: Array) -> void:
	if boss_id != "":
		CharacterData.card_order[boss_id] = ids.duplicate()


## 收藏册：只列至少有一张卡的 BOSS（未获得的卡、连卡都没有的 BOSS 都不显示）
static func card_collection_entries() -> Array:
	var out: Array = []
	for e in card_entries():
		if int((e as Dictionary).get("card_collected", 0)) > 0:
			out.append(e)
	return out


static func card_total() -> int:
	var n := 0
	for e in card_entries():
		n += (e.get("card_variants", []) as Array).size()
	return n


static func card_collected() -> int:
	var n := 0
	for e in card_entries():
		for raw in e.get("card_variants", []):
			if bool((raw as Dictionary).get("unlocked", false)):
				n += 1
	return n


## 双倍气血挑战通关：同层第 HOLO_CLEAR_REQUIRED 次及以后通关（此前已清 10 次 → 第 11 战 2× 血）。
static func is_holo_unlocked(boss_id: String) -> bool:
	# 大世界核心首领：按分支重战次数算
	var core := boss_entry(boss_id)
	var world_region := String(core.get("world_region", ""))
	if world_region != "":
		return CharacterData.get_core_clear_count(world_region) >= HOLO_CLEAR_REQUIRED
	var floor_no := 0
	for f in WorldDB.get_floors():
		if String((f as Dictionary).get("boss_id", "")) == boss_id:
			floor_no = int((f as Dictionary).get("floor", 0))
			break
	if floor_no <= 0:
		return false
	return CharacterData.get_tower_clear_count(floor_no) >= HOLO_CLEAR_REQUIRED


## BOSS 卡是否解锁：以「是否击败过」为准（与道具图鉴的 codex_unlocked 分开记）
static func is_boss_unlocked(boss_id: String) -> bool:
	var rid := String((BOSS_CODEX.get(boss_id, {}) as Dictionary).get("world_region", ""))
	if rid != "":
		var kills = CharacterData.secret_world.get("core_kills", {})
		return kills is Dictionary and bool((kills as Dictionary).get(rid, false))
	var rec = CharacterData.boss_progress.get(boss_id, {})
	if not (rec is Dictionary):
		return false
	return bool((rec as Dictionary).get("killed", false))


## 直接读战斗场景上的导出属性 —— 数值只有一处来源，图鉴不会写漂。
## ⚠ 只 instantiate、不进树：不会触发 _ready / 骨骼构建。
static func _boss_probe(boss_id: String) -> Node:
	var path := String(WorldDB.BOSS_SCENES.get(boss_id, ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	return ps.instantiate() if ps != null else null


static func boss_stats(boss_id: String) -> Dictionary:
	var world_region := String((BOSS_CODEX.get(boss_id, {}) as Dictionary).get("world_region", ""))
	if world_region != "":
		# 按区域取核心配置：写死 CORE_BOSS 会让苍角卡显示青岚古猿的血量/速度
		var core := SecretWorldDB.get_core_boss(world_region)
		var spd := float(core.get("move_speed", 100.0))
		return {
			"hp": int(round(float(core.get("max_hp", 0.0)))),
			"speed_p1": int(round(spd)),
			"speed_p2": int(round(spd * 1.3)),
			"windup": float(core.get("windup", 0.85)),
			"attack_text": "攻击力 %d" % int(round(float(core.get("attack_power", 0.0)))),
			"radius": int(round(float(core.get("body_radius", 40.0)))),
		}
	var n := _boss_probe(boss_id)
	if n == null:
		return {}
	var out := {
		"hp": int(round(float(n.get("max_hp")))),
		"speed_p1": int(round(float(n.get("MOVE_SPEED_P1")))),
		"speed_p2": int(round(float(n.get("MOVE_SPEED_P2")))),
		"windup": float(n.get("WINDUP_TIME_P1")),
		"attack_text": "",
		"radius": 0,
	}
	# ⚠ 先看「招式固定伤害」的导出（虎妖走这套）；BossBase 自带 attack_power=40 的默认值，
	#   只看 attack_power 会把虎妖误显示成「攻击力 40」，而它根本不走系数结算。
	var flat_parts: Array[String] = []
	for pair in [["爪", "MELEE_DAMAGE"], ["掷石", "PROJECTILE_DAMAGE"],
			["妖丹", "ELEMENTAL_DAMAGE"], ["踏地", "SMASH_DAMAGE"]]:
		var v = n.get(String(pair[1]))
		if v != null and float(v) > 0.0:
			flat_parts.append("%s %d" % [String(pair[0]), int(round(float(v)))])
	if not flat_parts.is_empty():
		out["attack_text"] = "招式固定伤害　" + " · ".join(flat_parts)
	else:
		# 2026-10-28 用户定：卡片就写「攻击力」，不展开成单招伤害区间。
		#   注意口径：这是 BOSS 的归一化基数（刀客 100 / 剑客 20 / 两仪 24），
		#   真实掉血 = 基数 × 招式系数，所以横向比不同 BOSS 的攻击力没有意义。
		out["attack_text"] = "攻击力 %d" % int(round(float(n.get("attack_power"))))
	if n.has_method("hit_spheres"):
		var r := 0.0
		for sp in n.call("hit_spheres"):
			r = maxf(r, float((sp as Vector3).z))
		out["radius"] = int(round(r))
	n.free()
	return out


## 招式：名字 / 类型 / 从哪个阶段可用 / 一句话说明
static func boss_moves_info(boss_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var world_region := String((BOSS_CODEX.get(boss_id, {}) as Dictionary).get("world_region", ""))
	if world_region != "":
		var core := SecretWorldDB.get_core_boss(world_region)
		for raw in core.get("core_skills", []):
			var def: Dictionary = raw
			var kind := String(def.get("attack_kind", ""))
			var kind_text := "近战"
			if kind == "elemental":
				kind_text = "法术"
			elif kind == "physical_projectile":
				kind_text = "远程"
			var desc := String(def.get("desc", ""))
			if desc == "":
				desc = String(MoveDB.resolve_boss(String(def.get("form_id", ""))).get("desc", ""))
			out.append({
				"name": String(def.get("name", "")),
				"kind": kind_text,
				"phase": int(def.get("phase", 1)),
				"desc": desc,
			})
		return out
	for raw in WorldDB.get_boss_moves(boss_id):
		var item: Dictionary = raw
		var fid := String(item.get("form_id", ""))
		var b := MoveDB.resolve_boss(fid)
		if b.is_empty():
			continue
		var kind := String(b.get("attack_kind", ""))
		var kind_text := "近战"
		if kind == "elemental":
			kind_text = "法术"
		elif kind == "physical_projectile":
			kind_text = "远程"
		out.append({
			"name": String(b.get("form_name", fid)),
			"kind": kind_text,
			"phase": int(item.get("phase", 1)),
			"desc": String(b.get("desc", "")),
		})
	return out


## 掉落：名字 / 掉率（走 ItemDB 的默认 50% 规则）
static func boss_drops_info(boss_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var world_region := String((BOSS_CODEX.get(boss_id, {}) as Dictionary).get("world_region", ""))
	if world_region != "":
		# 按区域取核心配置：不能写死 CORE_BOSS（那是青岚古猿），否则云隐苍角卡会显示猿的掉落
		var core := SecretWorldDB.get_core_boss(world_region)
		var reward: Dictionary = core.get("reward", {})
		for id in reward:
			out.append({
				"id": String(id),
				"name": ItemDB.get_material_name(String(id)),
				"chance": 1.0,
				"count": int(reward[id]),
			})
		for raw in core.get("equipment_drops", []):
			var eid := String(raw)
			var eq := ItemDB.get_equipment_template(eid)
			out.append({
				"id": eid,
				"name": String(eq.get("equipment_name", eid)) if not eq.is_empty() else eid,
				"chance": 1.0,
				"count": 1,
			})
		return out
	for raw in ItemDB.get_drops_for_boss(boss_id):
		var entry: Dictionary = raw
		var id := String(entry.get("item_id", ""))
		if id == "":
			continue
		var name := ""
		var eq := ItemDB.get_equipment_template(id)
		if not eq.is_empty():
			name = String(eq.get("equipment_name", id))
		else:
			var tr := ItemDB.get_treasure_template(id)
			if not tr.is_empty():
				name = String(tr.get("treasure_name", id))
			else:
				name = ItemDB.get_material_name(id)
		out.append({
			"id": id,
			"name": name,
			"chance": ItemDB.get_drop_chance(entry),
			"count": int(entry.get("count", 1)),
		})
	return out


## 塔层首杀能感悟到的功法（按 form_id 反查）
static func boss_learn_info(boss_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sid in WorldDB.get_boss_skill_ids(boss_id):
		var sk := SkillDB.get_skill(String(sid))
		if sk.is_empty():
			continue
		out.append({
			"name": String(sk.get("skill_name", sid)),
			"desc": String(sk.get("desc", "")),
		})
	return out


## 这一战**由 BOSS 自己的招式产生**的状态：
##   · 负面 —— 挂在玩家身上，来自 form 的 `debuff_on_hit`
##   · 增益 —— BOSS 给自己上的，来自 form 的 `buff_on_self`（没登记就不显示）
## 名字与效果文字一律由 DebuffDB / BuffDB 现生成 —— 加状态或改数字，图鉴自动跟上。
## ⚠ 玩家侧的增益（弹反奖励 / 丹药 / 符箓）不进这张卡：BOSS 卡只讲 BOSS。
static func boss_status_info(boss_id: String) -> Array[Dictionary]:
	var by_key: Dictionary = {}
	for raw in WorldDB.get_boss_moves(boss_id):
		var item: Dictionary = raw
		var fid := String(item.get("form_id", ""))
		var b := MoveDB.resolve_boss(fid)
		if b.is_empty():
			continue
		var fname := String(b.get("form_name", fid))
		for entry_key in [["bad", "debuff_on_hit", "debuff_time"], ["good", "buff_on_self", "buff_time"]]:
			var kind := String(entry_key[0])
			var id := String(b.get(String(entry_key[1]), ""))
			if id == "":
				continue
			var t := float(b.get(String(entry_key[2]), 3.0))
			var key := kind + ":" + id
			var row: Dictionary = by_key.get(key, {
				"kind": kind,
				"id": id,
				"name": DebuffDB.display_name(id) if kind == "bad" else BuffDB.display_name(id),
				"effect": DebuffDB.effect_text(id) if kind == "bad" else String(BuffDB.get_buff(id).get("desc", "")),
				"time": t,
				"sources": [],
			})
			var src: Array = row.get("sources", [])
			if not src.has(fname):
				src.append(fname)
			row["sources"] = src
			row["time"] = maxf(float(row.get("time", 0.0)), t)
			by_key[key] = row
	var out: Array[Dictionary] = []
	for k in by_key.keys():
		out.append(by_key[k])
	# 脚本施加的状态（判词 / 滞雷 / 眩晕）不在 form.debuff_on_hit 里：
	# BOSS_CODEX 的 status_extra 补登记，名称与效果仍从 DebuffDB 现算。
	for raw in (BOSS_CODEX.get(boss_id, {}) as Dictionary).get("status_extra", []):
		if not (raw is Dictionary):
			continue
		var extra: Dictionary = raw
		var did := String(extra.get("id", ""))
		if did == "" or by_key.has("bad:" + did):
			continue
		by_key["bad:" + did] = {
			"kind": "bad",
			"id": did,
			"name": DebuffDB.display_name(did),
			"effect": DebuffDB.effect_text(did),
			"time": float(extra.get("time", 0.0)),
			"sources": [String(extra.get("source", ""))],
		}
		out.append(by_key["bad:" + did])
	return out


static func all_entries() -> Array:
	var out: Array = []
	for c in CATEGORIES:
		var cid := String((c as Dictionary).get("id", ""))
		# 卡包与试炼卡牌都不是「收集品」：不参与全图鉴总数与跨卷检索
		# （试炼卡只在本模式局内生效，混进总数会让老玩家的图鉴进度凭空倒退）
		if cid == CAT_PACK or cid == CAT_ROGUE_CARD:
			continue
		out.append_array(category_entries(cid))
	return out


static func get_entry(item_id: String) -> Dictionary:
	for e in all_entries():
		if String((e as Dictionary).get("id", "")) == item_id:
			return e
	return {}


static func source_for(item_id: String) -> String:
	return String(SOURCES.get(item_id, "获取方式待补充"))


static func quality_color(entry: Dictionary) -> Color:
	if String(entry.get("category", "")) == CAT_MATERIAL:
		return ItemDB.rarity_color(String(entry.get("rarity", "common")))
	return UIKit.grade_color(String(entry.get("grade", "")))


## 解锁后名字旁的小标签：装备「凡品 · 武器」，法宝「法器 · 主动法宝」，材料「普通 · 练气」
static func tag_text(entry: Dictionary) -> String:
	match String(entry.get("category", "")):
		CAT_EQUIPMENT:
			var etype := String(entry.get("equip_type", ""))
			return "%s · %s" % [
				String(entry.get("grade", "")),
				String(CharacterData.EQUIP_TYPE_DISPLAY.get(etype, etype)),
			]
		CAT_TREASURE:
			var tpl: Dictionary = entry.get("template", {})
			var kind := "法宝"
			if String(tpl.get("active_type", "")) != "":
				kind = "主动法宝"
			elif String(tpl.get("summon_boss_id", "")) != "":
				kind = "召唤法宝"
			return "%s · %s" % [String(entry.get("grade", "")), kind]
		CAT_MATERIAL:
			var text := ItemDB.rarity_name(String(entry.get("rarity", "common")))
			var realm := String(entry.get("realm", ""))
			if realm != "":
				text += " · " + realm
			return text
	return ""


static func detail_lines(entry: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var tpl: Dictionary = entry.get("template", {})
	match String(entry.get("category", "")):
		CAT_EQUIPMENT:
			out.append("品阶：%s" % String(entry.get("grade", "")))
			out.append("部位：%s" % String(CharacterData.EQUIP_TYPE_DISPLAY.get(
				String(entry.get("equip_type", "")), "")))
			var attrs := ItemDB.item_attributes_text(tpl)
			out.append("属性：%s" % (attrs if attrs != "" else "无"))
			if float(tpl.get("attack_bonus", 0.0)) > 0.0:
				out.append("攻击加成：+%d" % int(round(float(tpl.get("attack_bonus", 0.0)))))
		CAT_TREASURE:
			out.append("品阶：%s" % String(entry.get("grade", "")))
			var item := CharacterData.make_treasure_instance(tpl)
			for line in ItemDB.treasure_effect_lines(item):
				out.append(line)
		CAT_MATERIAL:
			out.append("稀有度：%s" % ItemDB.rarity_name(String(entry.get("rarity", "common"))))
			var realm := String(entry.get("realm", ""))
			if realm != "":
				out.append("区域：%s" % realm)
	var desc := String(tpl.get("desc", ""))
	if desc != "":
		out.append("描述：%s" % desc)
	return out


static func total_count() -> int:
	return all_entries().size() + boss_entries().size()


static func unlocked_count(category_id: String = "", sub_id: String = SUB_ALL) -> int:
	if category_id == CAT_BOSS:
		var bosses := boss_entries(sub_id)
		var bn := 0
		for e in bosses:
			if is_boss_unlocked(String((e as Dictionary).get("id", ""))):
				bn += 1
		return bn
	if category_id == CAT_PACK:
		return card_collected()
	# 试炼卡牌没有「获得」概念：全量可查（未解锁流派在列表里单独压暗）
	if category_id == CAT_ROGUE_CARD:
		return rogue_card_entries(sub_id).size()
	var list: Array = category_entries(category_id, sub_id) if category_id != "" else all_entries()
	var n := 0
	for e in list:
		if CharacterData.is_codex_unlocked(String((e as Dictionary).get("id", ""))):
			n += 1
	if category_id == "":
		n += unlocked_count(CAT_BOSS)
	return n


static func _make_entry(category: String, tpl: Dictionary) -> Dictionary:
	var id := ""
	var name := ""
	var icon := ""
	var grade := ""
	var rarity := ""
	var realm := ""
	var equip_type := ""
	match category:
		CAT_EQUIPMENT:
			id = String(tpl.get("equipment_id", ""))
			name = String(tpl.get("equipment_name", ""))
			icon = String(tpl.get("icon", ""))
			grade = String(tpl.get("equipment_grade", ""))
			equip_type = String(tpl.get("equipment_type", ""))
		CAT_TREASURE:
			id = String(tpl.get("treasure_id", ""))
			name = String(tpl.get("treasure_name", ""))
			icon = String(tpl.get("icon", ""))
			grade = String(tpl.get("treasure_grade", ""))
		CAT_MATERIAL:
			id = String(tpl.get("id", ""))
			name = String(tpl.get("name", ""))
			icon = String(tpl.get("icon", ""))
			rarity = String(tpl.get("rarity", "common"))
			realm = String(tpl.get("realm", ""))
	return {
		"id": id,
		"category": category,
		"name": name,
		"icon": icon,
		"grade": grade,
		"rarity": rarity,
		"realm": realm,
		"equip_type": equip_type,
		"template": tpl,
		"source": source_for(id),
	}
