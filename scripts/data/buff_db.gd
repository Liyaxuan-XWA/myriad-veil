class_name BuffDB
extends RefCounted
## 增益状态（buff）数据表 —— 2026-10-23
##
## 与 DebuffDB 对称：玩家侧 `buffs` 字典里的 id 都到这里取显示名与颜色，
## 战斗 HUD 在**第一个法宝格上方**列出来（debuff 在功法栏上方），不写任何硬编码文案。
##
## 字段：
##   name        显示名
##   desc        一句话说明
##   color       可选；不填就用 DEFAULT_COLOR（**绿色** —— 用户 2026-10-23 定）
##   count_based true = 次数型：显示「名称 ×N」，消耗到 0 消失
##               false = 时间型：显示「名称 x.xs」，倒计时到 0 消失

## buff 一律绿色（用户 2026-10-23 定：「颜色为绿色」）
const DEFAULT_COLOR := Color(0.42, 1.00, 0.58, 1.00)

const BUFFS: Dictionary = {
	## 弹刀成功给的次数增伤：下一次近战伤害 ×1.5，命中即消耗，不累计
	"parry_power": {
		"name": "弹刀增伤",
		"desc": "下一次近战伤害 ×1.5（命中即消耗）",
		"count_based": true,
	},
	## 完美弹反 / 自动弹刀给的 1.2 秒追击窗口：窗口内下一次近战功法/普攻可以直接贴到目标身前
	## （HUD 显示「追击 1.2s」，与 parry_followup_can_dash 一起构成"能不能追击"的判定）
	"parry_followup": {
		"name": "追击",
		"desc": "可以立刻追击（1.2 秒）",
		"count_based": false,
	},
	## 明灭（照影界「执烛」玩家侧，2026-11-02）：灯笼收到贴身、影长归零，
	## 换来这段时间所有物理功法伤害 +30%。收益在 player._shadow_dim_mult 里读同一组常数。
	"shadow_dim": {
		"name": "明灭",
		"desc": "影长归零，物理功法伤害 +30%",
		"count_based": false,
		"color": Color(0.86, 0.82, 0.58, 1.0),
	},
	## 量折（照影界「叠纸」玩家侧被动，2026-11-02）：穿过折痕圆牌后的下一次攻击加重。
	## ⚠ 一次性旗标、不攒层、没有条 —— 收益在 player._fold_cross_mult 里读同一组常数。
	"fold_measure": {
		"name": "量折",
		"desc": "刚从折痕那头出来，下一次攻击 +30%",
		"count_based": false,
		"color": Color(0.90, 0.92, 0.98, 1.0),
	},
	## 叠掩（同只 BOSS 的玩家侧护身纸）：首次受击 -60%，这段时间镜像判定对自己关闭
	"fold_shroud": {
		"name": "叠掩",
		"desc": "折一层纸护身，首次受击 -60%",
		"count_based": false,
		"color": Color(0.88, 0.90, 0.94, 1.0),
	},
	## ⚠ 「极限闪避」buff 已删除（2026-10-23 用户拍板）：
	##   它只写不读、没有任何数值效果，还会因为弹刀成功复用同一字段，
	##   让 HUD 上出现「弹刀成功 → 冒出极限闪避」的错乱。
	##   极限闪避的收益（回 2 格精力 / 子弹时间 / 蓝特效）都在 player._trigger_perfect_dodge() 里直接给。

	# ---------- 战斗轮盘：丹药 / 符箓的持续效果（2026-10-24 用户定稿）----------
	## 属性修正由 BattleWheel 写入 CharacterData.attribute_mods，buff 到期后一并清掉。
	"pill_juli": {
		"name": "练气巨力丹",
		"desc": "力量 +10%（按本体基础值，20 秒）",
		"count_based": false,
	},
	"pill_lingfa": {
		"name": "练气灵法丹",
		"desc": "法强 +10%（按本体基础值，20 秒）",
		"count_based": false,
	},
	"pill_jingang": {
		"name": "练气金刚丹",
		"desc": "物抗 / 法抗 +10（20 秒）",
		"count_based": false,
	},
	## 2026-10-30：筑基 / 结丹同名丹各用独立 buff id —— HUD 与使用飘字要显示对应境界的丹名，
	##   数值本身写在 ItemDB 配方的 mods 里，这里只负责名字与说明。
	"pill_juli_zj": {
		"name": "筑基巨力丹",
		"desc": "力量 +14%（按本体基础值，20 秒）",
		"count_based": false,
	},
	"pill_lingfa_zj": {
		"name": "筑基灵法丹",
		"desc": "法强 +14%（按本体基础值，20 秒）",
		"count_based": false,
	},
	"pill_jingang_zj": {
		"name": "筑基金刚丹",
		"desc": "物抗 / 法抗 +16（20 秒）",
		"count_based": false,
	},
	"pill_juli_jd": {
		"name": "结丹巨力丹",
		"desc": "力量 +18%（按本体基础值，20 秒）",
		"count_based": false,
	},
	"pill_lingfa_jd": {
		"name": "结丹灵法丹",
		"desc": "法强 +18%（按本体基础值，20 秒）",
		"count_based": false,
	},
	"pill_jingang_jd": {
		"name": "结丹金刚丹",
		"desc": "物抗 / 法抗 +22（20 秒）",
		"count_based": false,
	},
	## 2026-11-01：元婴档丹名与数值；数值仍写在 ItemDB 配方的 mods 里。
	"pill_juli_yy": {
		"name": "元婴巨力丹",
		"desc": "力量 +22%（按本体基础值，20 秒）",
		"count_based": false,
	},
	"pill_lingfa_yy": {
		"name": "元婴灵法丹",
		"desc": "法强 +22%（按本体基础值，20 秒）",
		"count_based": false,
	},
	"pill_jingang_yy": {
		"name": "元婴金刚丹",
		"desc": "物抗 / 法抗 +28（20 秒）",
		"count_based": false,
	},
	## 两仪转：消耗 1 层势后，下一招必定按逆式结算（4 秒内有效）
	"yinyang_reverse": {
		"name": "两仪·逆",
		"desc": "下一招必定按逆式结算",
		"count_based": false,
	},
	## 五旗阵：玩家站在自己五旗区域内的常驻标签（数值由 player 的阵区逻辑结算）
	"array_zone": {
		"name": "五旗阵",
		"desc": "阵内攻击 / 防御 +30%",
		"count_based": false,
		"color": Color(0.95, 0.82, 0.45),
	},
	## 顺天（赫连霄 · 判词守律奖励）：6 秒攻速 +20%、移速 +10%。
	## 属性修正由 player 守律结算时写进 CharacterData.attribute_mods。
	"shuntian": {
		"name": "顺天",
		"desc": "攻速 +20%、移速 +10%（守律奖励，6 秒）",
		"count_based": false,
		"color": Color(1.0, 0.86, 0.46, 1.0),
	},
	## 日冕（离照 · 逐日·天火）：持种者每 1.6 秒叠 1 层；层数与加成由玩家/离照脚本结算。
	"sun_crown": {
		"name": "日冕",
		"desc": "持种：每层自身所有伤害 +12%，最多 3 层；满层后每秒受到 6 点火焰伤害；满层后下一次逐日功法命中会在目标体内引燃，1 秒后造成 2.0 倍法强的火系伤害",
		"count_based": true,
		"color": Color(1.0, 0.78, 0.34, 1.0),
	},
	## 三灾轮转 · 灾替（晏无咎）：轮转起手短减伤；不是三灾轮的主动法宝
	"sanzai_guard": {
		"name": "灾替",
		"desc": "轮转起手：1.5 秒内第一次被破灾改为免疫，并再获得 1 层灾势",
		"count_based": false,
		"color": Color(0.58, 0.84, 0.78, 1.0),
	},
	## 元素符（2026-10-31）：水愈 / 风疾 / 石附；数值在符箓数据表里现算，这里只负责 HUD
	"talisman_water": {
		"name": "水愈",
		"desc": "每秒回复 10 点气血",
		"count_based": false,
		"color": Color(0.48, 0.82, 0.94, 1.0),
	},
	"talisman_wind": {
		"name": "风疾",
		"desc": "移动速度大幅提升，持续 10 秒以上",
		"count_based": false,
		"color": Color(0.62, 0.88, 0.78, 1.0),
	},
	"talisman_stone": {
		"name": "石附",
		"desc": "移动速度下降，受到伤害降低；受伤次数用尽或 12 秒后解除",
		"count_based": false,
		"color": Color(0.78, 0.68, 0.52, 1.0),
	},
	## 续命灯（野修法宝）：10 秒内第一次致死伤害改为保留 1 点气血。
	"xuming": {
		"name": "续命",
		"desc": "下一次致死伤害改为保留 1 点气血，并快速回复气血",
		"count_based": false,
		"color": Color(1.0, 0.84, 0.46, 1.0),
	},
	## 棘甲佩：近战物理反伤（法宝主动，持续 4 秒）
	"jijia": {
		"name": "棘甲",
		"desc": "受到近战物理伤害时，把一部分真实伤害反弹给攻击者",
		"count_based": false,
		"color": Color(0.92, 0.46, 0.38, 1.0),
	},
	## 镜返（观澜 · 玩家侧）：短时间横镜架势，第一次打过来的术法会被挡下并原样反弹。
	"mirror_return": {
		"name": "镜返",
		"desc": "下一次打过来的术法被镜面挡下并 100% 反弹",
		"count_based": false,
		"color": Color(0.64, 0.86, 1.0, 1.0),
	},
}


## 取一条 buff 定义；未登记返回空字典
static func get_buff(id: String) -> Dictionary:
	return BUFFS.get(id, {})


## 显示名（未登记时回退 id 本身，方便发现拼错）
static func display_name(id: String) -> String:
	var d := get_buff(id)
	return String(d.get("name", id)) if not d.is_empty() else id


## 一句话效果说明（轮盘飘字 / tooltip 用）
static func display_text(id: String) -> String:
	return String(get_buff(id).get("desc", id))


## 标签配色（默认绿；想给某条换色就在它自己的条目里填 color）
static func color(id: String) -> Color:
	var d := get_buff(id)
	if d.is_empty():
		return DEFAULT_COLOR
	return Color(d.get("color", DEFAULT_COLOR))


## 是否次数型（决定 HUD 显示「×N」还是「x.xs」）
static func is_count_based(id: String) -> bool:
	return bool(get_buff(id).get("count_based", false))
