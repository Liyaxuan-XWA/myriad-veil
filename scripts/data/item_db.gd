class_name ItemDB
extends RefCounted
## 物品静态数据表：材料 / 装备模板 / 法宝模板 / 合成配方 / 丹方 / 符方
## 字段对齐任务书 §5.2 装备数据、§5.5 丹药数据、§5.6 符箓数据
##
## ⚠ 以下条目为「示例数据」，用于打通系统流程，正式内容待定稿后整体替换。
## ⚠ icon 字段统一留空：美术出图后填入 res://assets/... 路径，UI 自动切换为贴图（见 UIKit.icon_node）

# ===== 材料 =====
## realm = 材料所属区域境界（2026-10-24 用户定：药材 / 兽皮都要标境界）
const MATERIALS: Array = [
	{"id": "mat_duanzaojingshi", "name": "锻造晶石", "type": "material", "rarity": "uncommon", "icon": "res://assets/ui/icon/mat_duanzaojingshi.png", "desc": "万界塔投影身上剥落的晶石，是强化装备的唯一媒介。"},
	# ===== BOSS 元魂（2026-10-21 用户定）=====
	## 紫色品质的稀有材料：只在万界塔「血量翻倍」的场次（该层第 11 次及以后）胜利时按 50% 掉落。
	## rarity 供 UI 上色（紫 = epic），与装备品阶（凡品/法器…）是两套口径，互不影响。
	{"id": "soul_huyao", "name": "虎妖元魂", "type": "material", "rarity": "epic", "icon": "res://assets/ui/icon/soul_huyao.png",
		"desc": "虎妖留在塔中投影上的残魂，紫气缠绕。与破损的虎皮袍熔铸，可得虎妖令。不可丢弃、不可分解。"},
	{"id": "soul_daoke", "name": "刀客元魂", "type": "material", "rarity": "epic", "icon": "res://assets/ui/icon/soul_daoke.png",
		"desc": "刀客留在塔中投影上的残魂，紫气缠绕。与破损的弯刀熔铸，可得刀客令。不可丢弃、不可分解。"},
	{"id": "soul_jianke", "name": "剑客元魂", "type": "material", "rarity": "epic", "icon": "res://assets/ui/icon/soul_jianke.png",
		"desc": "剑客留在塔中投影上的残魂，紫气缠绕。与破损的清风剑熔铸，可得剑客令。不可丢弃、不可分解。"},
	{"id": "soul_liangyi", "name": "两仪真人元魂", "type": "material", "rarity": "epic", "icon": "res://assets/ui/icon/soul_liangyi.png",
		"desc": "两仪真人留在塔中投影上的残魂，一半金白、一半青黑。与破损的两仪装备熔铸，可得两仪令。不可丢弃、不可分解。"},

	# ===== 位面 01 专属材料（2026-11-07 补）=====
	## 凡界三只 BOSS 各掉一件；三件合成 domain_01 位面法宝「凡界·换锋符」。
	## ⚠ 原规则「从位面 02 起」于本日扩展到凡界，见 PLANE_TREASURE_RECIPES 表头。
	{"id": "mat_fanjie_huya", "name": "界门虎牙", "type": "material", "realm": "练气", "rarity": "epic", "icon": "res://assets/ui/icon/mat_fanjie_huya.png",
		"desc": "守在凡界界门的那头虎妖崩落的一枚獠牙，牙根还带着界门的石屑。凡界专属材料之一。"},
	{"id": "mat_fanjie_duanren", "name": "凡铁断刃", "type": "material", "realm": "练气", "rarity": "epic", "icon": "res://assets/ui/icon/mat_fanjie_duanren.png",
		"desc": "刀客那柄凡品弯刀崩下的断刃，铁色发灰，刃口却仍亮。凡界专属材料之一。"},
	{"id": "mat_fanjie_jianxie", "name": "清风剑屑", "type": "material", "realm": "练气", "rarity": "epic", "icon": "res://assets/ui/icon/mat_fanjie_jianxie.png",
		"desc": "剑客收剑时从清风剑上抖落的一缕碎屑，落在掌心微凉。凡界专属材料之一。"},

	# ===== 位面 02 专属材料（2026-10-27）=====
	## 每个位面的三只 BOSS 各掉一件专属材料，集齐三件合成该位面专属法宝。
	## 位面 02 三件已齐：两仪玄石 / 朱砂阵钉 / 太虚气晶 → 太极盘。
	{"id": "mat_liangyi_xuanshi", "name": "两仪玄石", "type": "material", "realm": "筑基", "rarity": "epic", "icon": "res://assets/ui/icon/mat_liangyi_xuanshi.png",
		"desc": "两仪真人护体崩碎时落下的玄石，一面金白、一面青黑。冲和界专属材料之一。"},
	{"id": "mat_zhusha_zhending", "name": "朱砂阵钉", "type": "material", "realm": "筑基", "rarity": "epic", "icon": "res://assets/ui/icon/mat_zhusha_zhending.png",
		"desc": "定阵先生插阵用的朱砂钉，钉头刻着一圈拆不开的阵纹。冲和界专属材料之一。"},
	{"id": "soul_dingzhen", "name": "定阵先生元魂", "type": "material", "rarity": "epic", "icon": "res://assets/ui/icon/soul_dingzhen.png",
		"desc": "定阵先生留在塔中投影上的残魂，指尖还捻着一根断线。与破损的阵师装备熔铸，可得阵旗令。不可丢弃、不可分解。"},
	{"id": "mat_taixu_qijing", "name": "太虚气晶", "type": "material", "realm": "筑基", "rarity": "epic", "icon": "res://assets/ui/icon/mat_taixu_qijing.png",
		"desc": "太虚气君一呼一吸间凝下的气晶，握在手里轻若无物。冲和界专属材料之一。"},
	{"id": "soul_qi", "name": "太虚气君元魂", "type": "material", "rarity": "epic", "icon": "res://assets/ui/icon/soul_qi.png",
		"desc": "太虚气君留在塔中投影上的残魂。与破损的气君装备熔铸，可得气君令。不可丢弃、不可分解。"},

	# ===== 位面 03 专属材料（2026-10-29）=====
	## 赤霄界第一件专属材料；另两件随本界另外两位 BOSS 落地后补齐。
	{"id": "mat_chixiao_leijing", "name": "赤霄雷晶", "type": "material", "realm": "结丹", "rarity": "epic", "icon": "res://assets/ui/icon/mat_chixiao_leijing.png",
		"desc": "赫连霄笔尖凝下的雷晶，内里一道赤金雷纹久久不散。赤霄界专属材料之一。"},
	{"id": "mat_chixiao_risui", "name": "赤霄日髓", "type": "material", "realm": "结丹", "rarity": "epic", "icon": "res://assets/ui/icon/mat_chixiao_risui.png",
		"desc": "离照日轮扇中心凝下的一滴日髓。赤霄界专属材料之一。"},
	{"id": "mat_chixiao_jiehui", "name": "赤霄劫灰", "type": "material", "realm": "结丹", "rarity": "epic", "icon": "res://assets/ui/icon/mat_chixiao_jiehui.png",
		"desc": "三灾台中央落下的灰白劫灰，摸上去还有雷火的余温。赤霄界专属材料之一。"},
	{"id": "soul_helianxiao", "name": "赫连霄元魂", "type": "material", "rarity": "epic", "icon": "res://assets/ui/icon/soul_helianxiao.png",
		"desc": "赫连霄留在塔中投影上的残魂，半张雷纹面具仍未散形。与破损的判官装备熔铸，可得判官令。不可丢弃、不可分解。"},
	{"id": "soul_lizhao", "name": "离照元魂", "type": "material", "rarity": "epic", "icon": "res://assets/ui/icon/soul_lizhao.png",
		"desc": "离照留在塔中投影上的残魂，日轮扇只剩一圈焦金扇骨。与破损的日纹装备熔铸，可得火正令。不可丢弃、不可分解。"},
	{"id": "soul_yanwujiu", "name": "晏无咎元魂", "type": "material", "rarity": "epic", "icon": "res://assets/ui/icon/soul_yanwujiu.png",
		"desc": "晏无咎留在塔中投影上的残魂，三张面具只剩一张完好。与破损的劫纹装备熔铸，可得劫主令。不可丢弃、不可分解。"},

	# ===== 位面 04 专属材料（2026-11-01 起，逐只补齐）=====
	## 照影界三只 BOSS 各掉一件；第三件随本界第三位落地后补齐，三件合成 domain_04 位面法宝。
	{"id": "mat_zhaoying_jingsha", "name": "照影镜砂", "type": "material", "realm": "元婴", "rarity": "epic", "icon": "res://assets/ui/icon/mat_zhaoying_jingsha.png",
		"desc": "观澜碎镜时落下的银蓝细砂，捧在手里能照出第二个自己。照影界专属材料之一。"},
	{"id": "mat_zhaoying_zhulei", "name": "照影烛泪", "type": "material", "realm": "元婴", "rarity": "epic", "icon": "res://assets/ui/icon/mat_zhaoying_zhulei.png",
		"desc": "执烛那盏界灯凝下的冷蜡，落在地上就拖出一条不肯散的黑影。照影界专属材料之一。"},
	{"id": "mat_zhaoying_zhihen", "name": "照影纸痕", "type": "material", "realm": "元婴", "rarity": "epic", "icon": "res://assets/ui/icon/mat_zhaoying_zhihen.png",
		"desc": "叠纸把战场折起来又展开后留在地上的那道白棱，摸上去是硬的。照影界专属材料之一，三件合璧可炼照影界位面法宝。"},
	{"id": "soul_guanying", "name": "观澜元魂", "type": "material", "rarity": "epic", "icon": "res://assets/ui/icon/soul_guanying.png",
		"desc": "观澜留在塔中投影上的残魂，一层薄镜面里还映着未散的倒影。与破损的镜纹装备熔铸，可得镜主令。不可丢弃、不可分解。"},
	{"id": "soul_zhizhu", "name": "执烛元魂", "type": "material", "rarity": "epic", "icon": "res://assets/ui/icon/soul_zhizhu.png",
		"desc": "执烛留在塔中投影上的残魂，一只空灯里还剩一点不肯熄的暗光。与破损的影纹装备熔铸，可得执烛令。不可丢弃、不可分解。"},
	{"id": "soul_diezhi", "name": "叠纸元魂", "type": "material", "rarity": "epic", "icon": "res://assets/ui/icon/soul_diezhi.png",
		"desc": "叠纸留在塔中投影上的残魂，一张对折的白纸，摊开来是一道空的折痕。与破损的纸纹装备熔铸，可得叠纸令。不可丢弃、不可分解。"},

	# ===== 苍澜大陆材料（2026-10-30 用户定名：地区 + 草药/兽皮）=====
##   材料 =「所属地区 + 草药/兽皮」：青岚野 → 青岚X、云隐谷 → 云隐X、赤金丹霞 → 赤金X；
##   丹药 =「对应境界 + 丹名」：练气回春丹 / 筑基回春丹 / 结丹回春丹 / 元婴回春丹。
	## 练气区域的 5 种药材：分别对应回气血 / 回灵力 / 力量 / 法强 / 防御（物抗+法抗）方向的丹药。
	## 对应的五张丹方见下面的 PILL_RECIPES。
	{"id": "mat_xuecao", "name": "青岚血参", "type": "material", "realm": "练气", "rarity": "common", "icon": "res://assets/ui/icon/mat_xuecao.png",
		"desc": "青岚野常见的赤色灵参，药性偏温，是炼制回气血丹药的主材。"},
	{"id": "mat_lanyingcao", "name": "青岚蓝萤草", "type": "material", "realm": "练气", "rarity": "common", "icon": "res://assets/ui/icon/mat_lanyingcao.png",
		"desc": "青岚野入夜后叶脉泛出蓝光的灵草，是炼制回灵力丹药的主材。"},
	{"id": "mat_liyuanguo", "name": "青岚力元果", "type": "material", "realm": "练气", "rarity": "common", "icon": "res://assets/ui/icon/mat_liyuanguo.png",
		"desc": "青岚野沉甸甸的褐色灵果，药力浑厚，是炼制增力量丹药的主材。"},
	{"id": "mat_falinghua", "name": "青岚法灵花", "type": "material", "realm": "练气", "rarity": "common", "icon": "res://assets/ui/icon/mat_falinghua.png",
		"desc": "青岚野花瓣纹路如灵纹流转的灵花，是炼制增法强丹药的主材。"},
	{"id": "mat_huguteng", "name": "青岚护骨藤", "type": "material", "realm": "练气", "rarity": "common", "icon": "res://assets/ui/icon/mat_huguteng.png",
		"desc": "青岚野坚韧如骨的藤蔓，是炼制增防御（物抗与法抗）丹药的主材。"},
	## 妖兽皮毛：两种，分别用于绘制攻击方向 / 防御方向的符箓。
	{"id": "mat_ruishoupi", "name": "青岚锐兽皮", "type": "material", "realm": "练气", "rarity": "common", "icon": "res://assets/ui/icon/mat_ruishoupi.png",
		"desc": "妖兽体表锋锐处的皮毛，纹理锋利，可绘制攻击方向符箓。"},
	{"id": "mat_jianshoupi", "name": "青岚坚兽皮", "type": "material", "realm": "练气", "rarity": "common", "icon": "res://assets/ui/icon/mat_jianshoupi.png",
		"desc": "妖兽背部的厚皮毛，坚韧耐磨，可绘制防御方向符箓。"},
	# ===== 境界突破材料：残晶 → 熔铸合成 → 完整破境晶（2026-11-02 用户定）=====
	## 原来「区域首领直接掉能用的破境晶」拆成两步，逼玩家把大陆和位面两边都打通：
	##   地髓 = 本境界**大陆区域核心首领**首杀必得（灵脉里凝出的半枚，走 SecretWorldDB 的 core_reward）
	##   天髓 = 对应**位面第三位 BOSS** 首杀必得（界域里凝出的另半枚，走下面的 FIRST_KILL_REWARDS）
	##   两枚到锻造台「熔铸」页合成 → 完整破境晶 → 这才算大突破的材料
	## 完整晶沿用旧 id（mat_pojing_zhuji / _jiedan / _yuanying / _huashen）：境界面板、
	## 背包丢弃保护、九天门判定都是按 id 读表的，id 不动这些口径就自动跟着走。
	## ⚠ 未登记的境界 = 无材料门槛（点一下就白嫖一个大境界），所以四档必须全部占位。
	## 图标已接正式素材（2026-11-02 用户外部生成，tools/import_pojing_icons.py 切表键底）。
	## 品质档（2026-11-02 用户定）：跟 `realm` 走，与该境界大陆的其它材料 / 丹药 / 符箓同档
	## —— 练气链白、筑基链蓝、结丹链紫、元婴链橙；所以一条链里的底髓 / 天髓 / 完整晶同色，
	## 区分靠名字与说明，不靠颜色。

	## ---- 练气 → 筑基：凡界 ----
	{"id": "mat_pojing_di_zhuji", "name": "筑基底髓", "type": "material", "realm": "练气", "rarity": "common", "icon": "res://assets/ui/icon/mat_pojing_di_zhuji.png",
		"desc": "练气区核心首领「青岚古猿」灵脉里凝出的半枚破境晶。地脉之性，须与筑基天髓合璧才可用。"},
	{"id": "mat_pojing_tian_zhuji", "name": "筑基天髓", "type": "material", "realm": "练气", "rarity": "common", "icon": "res://assets/ui/icon/mat_pojing_tian_zhuji.png",
		"desc": "凡界第三位「剑客」剑意凝出的半枚破境晶。界域之性，与筑基底髓合璧成筑基破境晶。"},
	{"id": "mat_pojing_zhuji", "name": "筑基破境晶", "type": "material", "realm": "练气", "rarity": "common", "icon": "res://assets/ui/icon/mat_pojing_zhuji.png",
		"desc": "地髓与天髓合璧后的完整破境晶，是练气修士跨入筑基的凭依。"},

	## ---- 筑基 → 结丹：冲和界 ----
	{"id": "mat_pojing_di_jiedan", "name": "结丹底髓", "type": "material", "realm": "筑基", "rarity": "rare", "icon": "res://assets/ui/icon/mat_pojing_di_jiedan.png",
		"desc": "云隐谷核心首领「云隐苍角」灵脉里凝出的半枚破境晶，须与结丹天髓合璧。"},
	{"id": "mat_pojing_tian_jiedan", "name": "结丹天髓", "type": "material", "realm": "筑基", "rarity": "rare", "icon": "res://assets/ui/icon/mat_pojing_tian_jiedan.png",
		"desc": "冲和界第三位「太虚气君」气机凝出的半枚破境晶，与结丹底髓合璧成结丹破境晶。"},
	{"id": "mat_pojing_jiedan", "name": "结丹破境晶", "type": "material", "realm": "筑基", "rarity": "rare", "icon": "res://assets/ui/icon/mat_pojing_jiedan.png",
		"desc": "地髓与天髓合璧后的完整破境晶，是筑基修士跨入结丹的凭依。"},

	## ---- 结丹 → 元婴：赤霄界 ----
	{"id": "mat_pojing_di_yuanying", "name": "元婴底髓", "type": "material", "realm": "结丹", "rarity": "epic", "icon": "res://assets/ui/icon/mat_pojing_di_yuanying.png",
		"desc": "赤金丹霞核心首领「赤金火麟」丹脉里凝出的半枚破境晶，须与元婴天髓合璧。"},
	{"id": "mat_pojing_tian_yuanying", "name": "元婴天髓", "type": "material", "realm": "结丹", "rarity": "epic", "icon": "res://assets/ui/icon/mat_pojing_tian_yuanying.png",
		"desc": "赤霄界第三位「晏无咎」判词压出的半枚破境晶，与元婴底髓合璧成元婴破境晶。"},
	{"id": "mat_pojing_yuanying", "name": "元婴破境晶", "type": "material", "realm": "结丹", "rarity": "epic", "icon": "res://assets/ui/icon/mat_pojing_yuanying.png",
		"desc": "地髓与天髓合璧后的完整破境晶，是结丹修士跨入元婴的凭依。"},

	## ---- 元婴 → 化神：照影界（化神例外，走九天门）----
	## 化神不在境界面板点：要拿完整化神破境晶去**幽冥灵墟中心的九天门**（元婴区首领
	## 镇墟石犼身后）开门，进九天之上之后在化神坛上才真正突破。
	## ⚠ 天髓出自照影界**第三位** BOSS：2026-11-02 叠纸落地后，FIRST_KILL_REWARDS 的 key
	##   已从临时挂着的 boss_04_b（执烛）换成 boss_04_c（叠纸）。
	{"id": "mat_pojing_di_huashen", "name": "化神底髓", "type": "material", "realm": "元婴", "rarity": "legendary", "icon": "res://assets/ui/icon/mat_pojing_di_huashen.png",
		"desc": "幽冥灵墟核心首领「镇墟石犼」墟脉里凝出的半枚破境晶，须与化神天髓合璧。"},
	{"id": "mat_pojing_tian_huashen", "name": "化神天髓", "type": "material", "realm": "元婴", "rarity": "legendary", "icon": "res://assets/ui/icon/mat_pojing_tian_huashen.png",
		"desc": "照影界「叠纸」把战场重新摊平后留下的半枚破境晶，与化神底髓合璧成化神破境晶。"},
	{"id": "mat_pojing_huashen", "name": "化神破境晶", "type": "material", "realm": "元婴", "rarity": "legendary", "icon": "res://assets/ui/icon/mat_pojing_huashen.png",
		"desc": "地髓与天髓合璧后的完整破境晶。元婴后期圆满时持它到幽冥灵墟中心的九天门开门，入九天之上于化神坛突破。"},


	# ===== 筑基区材料（2026-10-28 用户定：同构升级 + 品质提一档，图标复用炼气那套）=====
	## 品质档规则（2026-11-02 用户定）：一个区的材料与该区的丹药 / 符箓同档，
	## 练气 common → 筑基 rare → 结丹 epic → 元婴 legendary；血参 / 蓝萤草原先低一档，已抬平。
	{"id": "mat_zj_xuecao", "name": "云隐血参", "type": "material", "realm": "筑基", "rarity": "rare",
		 "icon": "res://assets/ui/icon/mat_xuecao.png",
		 "desc": "生于云隐谷高处寒土的血参，药性比青岚野更厚。"},
	{"id": "mat_zj_lanyingcao", "name": "云隐蓝萤草", "type": "material", "realm": "筑基", "rarity": "rare",
		 "icon": "res://assets/ui/icon/mat_lanyingcao.png",
		 "desc": "夜半泛蓝萤光的草，灵气聚而不散。"},
	{"id": "mat_zj_liyuanguo", "name": "云隐力元果", "type": "material", "realm": "筑基", "rarity": "rare",
		 "icon": "res://assets/ui/icon/mat_liyuanguo.png",
		 "desc": "入腹如坠石，气力沉厚。"},
	{"id": "mat_zj_falinghua", "name": "云隐法灵花", "type": "material", "realm": "筑基", "rarity": "rare",
		 "icon": "res://assets/ui/icon/mat_falinghua.png",
		 "desc": "花瓣内里流转细密灵纹。"},
	{"id": "mat_zj_huguteng", "name": "云隐护骨藤", "type": "material", "realm": "筑基", "rarity": "rare",
		 "icon": "res://assets/ui/icon/mat_huguteng.png",
		 "desc": "藤质如骨，捣碎可固本。"},
	{"id": "mat_zj_ruishoupi", "name": "云隐锐兽皮", "type": "material", "realm": "筑基", "rarity": "rare",
		 "icon": "res://assets/ui/icon/mat_ruishoupi.png",
		 "desc": "筑基妖兽的皮，坚韧可制符。"},
	{"id": "mat_zj_jianshoupi", "name": "云隐坚兽皮", "type": "material", "realm": "筑基", "rarity": "rare",
		 "icon": "res://assets/ui/icon/mat_jianshoupi.png",
		 "desc": "厚如甲片的兽皮，用于护体符。"},

	# ===== 赤金丹霞（结丹）材料（2026-10-29）=====
	## 与云隐谷同构：五种草药 + 两张兽皮；图标复用练气那套，只换名字与品质。
	{"id": "mat_jd_xuecao", "name": "赤金血参", "type": "material", "realm": "结丹", "rarity": "epic",
		 "icon": "res://assets/ui/icon/mat_xuecao.png",
		 "desc": "吸了地火的血参，断面凝着金丝，药性燥烈。"},
	{"id": "mat_jd_lanyingcao", "name": "赤金蓝萤草", "type": "material", "realm": "结丹", "rarity": "epic",
		 "icon": "res://assets/ui/icon/mat_lanyingcao.png",
		 "desc": "白日收拢、夜里泛出冷蓝萤光的草，是丹霞少见的凉性药。"},
	{"id": "mat_jd_liyuanguo", "name": "赤金力元果", "type": "material", "realm": "结丹", "rarity": "epic",
		 "icon": "res://assets/ui/icon/mat_liyuanguo.png",
		 "desc": "在赤岩缝里长成的灵果，果皮如烙铁，入腹气力翻涌。"},
	{"id": "mat_jd_falinghua", "name": "赤金法灵花", "type": "material", "realm": "结丹", "rarity": "epic",
		 "icon": "res://assets/ui/icon/mat_falinghua.png",
		 "desc": "花瓣纹路如日轮流转，触之灼指，是丹霞法修的珍材。"},
	{"id": "mat_jd_huguteng", "name": "赤金护骨藤", "type": "material", "realm": "结丹", "rarity": "epic",
		 "icon": "res://assets/ui/icon/mat_huguteng.png",
		 "desc": "盘在丹崖背阴处的老藤，藤质如骨，耐火耐折。"},
	{"id": "mat_jd_ruishoupi", "name": "赤金锐兽皮", "type": "material", "realm": "结丹", "rarity": "epic",
		 "icon": "res://assets/ui/icon/mat_ruishoupi.png",
		 "desc": "赤鬃锋牙兽体表锋锐处的皮毛，纹理锋利，可绘攻击符。"},
	{"id": "mat_jd_jianshoupi", "name": "赤金坚兽皮", "type": "material", "realm": "结丹", "rarity": "epic",
		 "icon": "res://assets/ui/icon/mat_jianshoupi.png",
		 "desc": "赤岩坚甲兽背部的厚甲皮，耐火耐磨，可绘护体符。"},

	# ===== 幽冥灵墟（元婴）材料（2026-10-31）=====
	## 与前三区同构：五种草药 + 两张兽皮；图标复用练气那套，只换名字与品质。
	## 品质按境界产品口径走：元婴丹药与元婴符都是 legendary（橙），材料同档。
	## （2026-11-02 用户指出血参 / 蓝萤草 / 锐兽皮错标 epic 显示成紫色，已抬到橙色）
	{"id": "mat_yy_xuecao", "name": "幽冥血参", "type": "material", "realm": "元婴", "rarity": "legendary",
		 "icon": "res://assets/ui/icon/mat_xuecao.png",
		 "desc": "长在残碑阴影里的血参，断面泛着幽蓝，药性沉寒。"},
	{"id": "mat_yy_lanyingcao", "name": "幽冥蓝萤草", "type": "material", "realm": "元婴", "rarity": "legendary",
		 "icon": "res://assets/ui/icon/mat_lanyingcao.png",
		 "desc": "在灵墟阴气里结出萤光的草，夜里像一小簇鬼火。"},
	{"id": "mat_yy_liyuanguo", "name": "幽冥力元果", "type": "material", "realm": "元婴", "rarity": "legendary",
		 "icon": "res://assets/ui/icon/mat_liyuanguo.png",
		 "desc": "墟土深处结出的黑紫灵果，入口寒气刺骨，气力却翻涌。"},
	{"id": "mat_yy_falinghua", "name": "幽冥法灵花", "type": "material", "realm": "元婴", "rarity": "legendary",
		 "icon": "res://assets/ui/icon/mat_falinghua.png",
		 "desc": "花瓣像被幽火从内部照亮，是灵墟法修最看重的药引。"},
	{"id": "mat_yy_huguteng", "name": "幽冥护骨藤", "type": "material", "realm": "元婴", "rarity": "legendary",
		 "icon": "res://assets/ui/icon/mat_huguteng.png",
		 "desc": "缠在断柱上的老藤，藤质如骨，沾着不散的阴雾。"},
	{"id": "mat_yy_ruishoupi", "name": "幽冥锐兽皮", "type": "material", "realm": "元婴", "rarity": "legendary",
		 "icon": "res://assets/ui/icon/mat_ruishoupi.png",
		 "desc": "幽冥锋牙兽的皮毛，边缘像被阴火燎过，锋利而轻。"},
	{"id": "mat_yy_jianshoupi", "name": "幽冥坚兽皮", "type": "material", "realm": "元婴", "rarity": "legendary",
		 "icon": "res://assets/ui/icon/mat_jianshoupi.png",
		 "desc": "幽冥坚甲兽背上的石甲皮，敲之有金石声，阴气不侵。"},

	# ===== 铸神 / 补天（2026-11-13 用户定）=====
	## 铸神晶：大世界每区一座铸神祭坛，首次取 1 枚；化神后可再取 1 枚。
	## 补天石：祭坛第二阶段一次给 7 枚，用来清普通失败磨损。
	{"id": "mat_zhushenjing", "name": "铸神晶", "type": "material", "rarity": "mythic",
		 "cannot_discard": true,
		 "icon": "res://assets/ui/icon/mat_zhushenjing.png",
		 "desc": "无比珍贵的材料，谨慎使用。铸神祭坛上封印的金色晶石。仙器强化到 +10 后，点锻造台顶栏「铸神」即可铸成神器；神器不再有强化等级。"},
	{"id": "mat_butianshi", "name": "补天石", "type": "material", "rarity": "mythic",
		 "cannot_discard": true,
		 "icon": "res://assets/ui/icon/mat_butianshi.png",
		 "desc": "无比珍贵的材料，谨慎使用。裂金蛋白石。锻造时用它补天，可清掉普通敲击失败留下的磨损；进阶失败留下的磨损清不掉。通关一个位面也会获得 1 枚。"},
	{"id": "mat_yunxiansui", "name": "蕴仙髓", "type": "material", "rarity": "mythic",
		 "cannot_discard": true,
		 "icon": "res://assets/ui/icon/mat_yunxiansui.png",
		 "desc": "无比珍贵的材料，谨慎使用。仙器淬炼的引子：在锻造台点上方「蕴仙」淬炼，每点一次消耗 1 枚；常规敲砧与自动锻造对仙器不可用，满 +10 后再用铸神晶铸神。主线 BOSS 首杀、万界塔 BOSS 与九天之上的祭坛都会产出。"},
]

# ===== 境界突破材料（2026-10-23 新增，2026-10-26 补齐占位）=====
## 目标境界 → { 材料id: 数量 }
## ⚠ **未登记的境界 = 无材料门槛**，玩家点一下就能白嫖一个大境界。
##   所以每一个还能继续突破的大境界都必须在这里占位，哪怕材料暂时拿不到 ——
##   拿不到材料只是「暂时停在圆满」，裸奔突破则是直接把境界体系跳过。
const BREAKTHROUGH_REQUIREMENTS: Dictionary = {
	"筑基": {"mat_pojing_zhuji": 1},
	"结丹": {"mat_pojing_jiedan": 1},
	"元婴": {"mat_pojing_yuanying": 1},
	## 化神例外：完整晶不在境界面板吃掉，而是拿去幽冥灵墟中心的九天门开门，
	## 进了九天之上再在化神坛上突破。仍然登记在这里，是为了让「持有判定 /
	## 背包丢弃保护 / 境界面板的材料清单」都跟着同一张表，不在别处硬写 id。
	"化神": {"mat_pojing_huashen": 1},
}


## ===== 破境晶熔铸配方（2026-11-02 用户定）=====
## 目标境界 → { di 地髓（大陆区域核心首领首杀）, tian 天髓（本位面第三位 BOSS 首杀）, result 完整晶 }
## 锻造台「熔铸」页读这张表：两格放一地上两天即合成，不收晶石、不出法宝。
const POJING_SYNTH_RECIPES: Dictionary = {
	"筑基": {"di": "mat_pojing_di_zhuji", "tian": "mat_pojing_tian_zhuji", "result": "mat_pojing_zhuji"},
	"结丹": {"di": "mat_pojing_di_jiedan", "tian": "mat_pojing_tian_jiedan", "result": "mat_pojing_jiedan"},
	"元婴": {"di": "mat_pojing_di_yuanying", "tian": "mat_pojing_tian_yuanying", "result": "mat_pojing_yuanying"},
	"化神": {"di": "mat_pojing_di_huashen", "tian": "mat_pojing_tian_huashen", "result": "mat_pojing_huashen"},
}


## 按目标境界取熔铸配方
static func get_pojing_synth_recipe(target_realm: String) -> Dictionary:
	var r = POJING_SYNTH_RECIPES.get(String(target_realm), {})
	return r if r is Dictionary else {}


## 熔铸页匹配：两格材料（不分先后）能否合成出某档完整晶；不匹配返回空字典
static func find_pojing_recipe(material_a: String, material_b: String) -> Dictionary:
	if material_a == "" or material_b == "" or material_a == material_b:
		return {}
	for r in POJING_SYNTH_RECIPES.values():
		var rec := r as Dictionary
		var pair: Array = [String(rec.get("di", "")), String(rec.get("tian", ""))]
		if pair.has(material_a) and pair.has(material_b):
			return rec
	return {}


## 所有残晶 id：既是熔铸页的候选白名单，也享受「突破材料不可丢弃」保护
static func pojing_fragment_ids() -> Array:
	var out: Array = []
	for r in POJING_SYNTH_RECIPES.values():
		out.append(String((r as Dictionary).get("di", "")))
		out.append(String((r as Dictionary).get("tian", "")))
	return out


## 位面 BOSS 首杀必得（直接进背包，不落地面、不会被死亡吞掉）
## 与 DROP_TEMPLATES 分开：那张表是**每次击杀都摇**的掉落，门票类必须只给一次且必得。
## 每档天髓出自该位面的**第三位** BOSS；照影界第三位「叠纸」已于 2026-11-02 落地，
## key 已从临时的 boss_04_b 换回 boss_04_c（换 key 不影响已拿到手的残晶）。
const FIRST_KILL_REWARDS: Dictionary = {
	"boss_01_c": {"mat_pojing_tian_zhuji": 1},
	"boss_02_c": {"mat_pojing_tian_jiedan": 1},
	"boss_03_c": {"mat_pojing_tian_yuanying": 1},
	"boss_04_c": {"mat_pojing_tian_huashen": 1},
}


static func get_first_kill_reward(boss_id: String) -> Dictionary:
	var r = FIRST_KILL_REWARDS.get(String(boss_id), {})
	return r if r is Dictionary else {}


## 突破到 next_realm 需要的材料（未登记返回空字典 = 无材料门槛）
## 突破材料不可丢弃：以 BREAKTHROUGH_REQUIREMENTS 为准，新增占位材料自动受保护；
## 残晶（地髓 / 天髓）也一并保护 —— 它是合成完整晶的唯一原料，丢了等于断链。
static func is_breakthrough_material(item_id: String) -> bool:
	for req in BREAKTHROUGH_REQUIREMENTS.values():
		if req is Dictionary and (req as Dictionary).has(item_id):
			return true
	return pojing_fragment_ids().has(item_id)


static func get_breakthrough_requirements(next_realm: String) -> Dictionary:
	var req = BREAKTHROUGH_REQUIREMENTS.get(next_realm, {})
	return req if req is Dictionary else {}


# ===== 丹方 / 符方（2026-10-23 用户要求重新开放炼丹房 / 制符台时加入）=====
## materials 为 { 材料id: 数量 }；success_rate 为基础成功率，受熟练度加成
## 配方全部只吃**苍澜大陆练气区域能拿到的材料**（药材 / 皮毛），
## 2026-10-23 用户定：一张方子只吃对应的一种材料。
## 2026-10-27 用户定（炼丹/制符重做）：**一株料 = 一颗成品**（原为各 3 份）。
##   丹炉 / 符台改成自由投料：一次只放一味料，放 N 株就最多出 N 颗，
##   实出数由控火（丹）/ 走笔（符）决定 —— 所以这里数量记 1，代表「单株的用量」。
##
## 丹药与五种药材一一对应：回气血 / 回灵力 / 增力量 / 增法强 / 增防御。
## realm 为丹药所属区域境界（玩家可见）。
## battle_effect 是**战斗轮盘使用**的效果口径（2026-10-24 用户定稿）：
##   heal_hp / restore_mana 用 ratio（按**当前上限**的百分比）；
##   buff 用 BuffDB 的 id + 持续秒数 + 属性修正。
##   属性修正结构见 CharacterData.set_attribute_mod：
##     {"flat": 加值}                            固定加值
##     {"base_pct": 百分比}                      只按**裸装本体基础值**计算（装备不参与）
##   练气丹药只能加本体基础值的 10%，因此力量 / 法强用 base_pct；
##   金刚丹按用户定：凡品（练气）直接 +10 点双抗，不走百分比。
const PILL_RECIPES: Array = [
	{
		"recipe_id": "recipe_huichundan",
		"pill_id": "pill_huichundan",
		"pill_name": "练气回春丹",
		"realm": "练气",
		"rarity": "common",
		"icon": "res://assets/ui/icon/pill_huichundan.png",
		"materials": {"mat_xuecao": 1},
		"success_rate": 0.75,
		"battle_cooldown": 30.0,
		"battle_effect": {"kind": "heal_hp", "ratio": 0.10},
		"is_consumable": true,
		"desc": "以青岚血参入药，药性温和。服下可回复气血。",
	},
	{
		"recipe_id": "recipe_julingdan",
		"pill_id": "pill_julingdan",
		"pill_name": "练气聚灵丹",
		"realm": "练气",
		"rarity": "common",
		"icon": "res://assets/ui/icon/pill_julingdan.png",
		"materials": {"mat_lanyingcao": 1},
		"success_rate": 0.75,
		"battle_cooldown": 30.0,
		"battle_effect": {"kind": "restore_mana", "ratio": 0.10},
		"is_consumable": true,
		"desc": "以青岚蓝萤草为主药，灵力如萤火汇聚。服下可回复灵力。",
	},
	{
		"recipe_id": "recipe_julidan",
		"pill_id": "pill_julidan",
		"pill_name": "练气巨力丹",
		"realm": "练气",
		"rarity": "common",
		"icon": "res://assets/ui/icon/pill_julidan.png",
		"materials": {"mat_liyuanguo": 1},
		"success_rate": 0.70,
		"battle_cooldown": 45.0,
		"battle_effect": {
			"kind": "buff", "buff_id": "pill_juli", "seconds": 20.0,
			"mods": {"strength": {"base_pct": 10.0}},
		},
		"is_consumable": true,
		"desc": "以青岚力元果为主药，药力沉厚。服下后短时间内力量上涨。",
	},
	{
		"recipe_id": "recipe_lingfadan",
		"pill_id": "pill_lingfadan",
		"pill_name": "练气灵法丹",
		"realm": "练气",
		"rarity": "common",
		"icon": "res://assets/ui/icon/pill_lingfadan.png",
		"materials": {"mat_falinghua": 1},
		"success_rate": 0.70,
		"battle_cooldown": 45.0,
		"battle_effect": {
			"kind": "buff", "buff_id": "pill_lingfa", "seconds": 20.0,
			"mods": {"spell_power": {"base_pct": 10.0}},
		},
		"is_consumable": true,
		"desc": "以青岚法灵花为主药，灵纹流转。服下后短时间内法强上涨。",
	},
	{
		"recipe_id": "recipe_jingangdan",
		"pill_id": "pill_jingangdan",
		"pill_name": "练气金刚丹",
		"realm": "练气",
		"rarity": "common",
		"icon": "res://assets/ui/icon/pill_jingangdan.png",
		"materials": {"mat_huguteng": 1},
		"success_rate": 0.70,
		"battle_cooldown": 45.0,
		"battle_effect": {
			"kind": "buff", "buff_id": "pill_jingang", "seconds": 20.0,
			"mods": {"physical_resist": {"flat": 10.0}, "magic_resist": {"flat": 10.0}},
		},
		"is_consumable": true,
		"desc": "以青岚护骨藤为主药，筋骨如铁。服下后短时间内物抗与法抗提升。",
	},

	# ===== 筑基丹方（2026-10-28：同结构上调一档；一株料 = 一颗成品）=====
	{
		"recipe_id": "recipe_zj_huichundan", "pill_id": "pill_zj_huichundan", "pill_name": "筑基回春丹",
		"realm": "筑基", "rarity": "rare",
		"icon": "res://assets/ui/icon/pill_huichundan.png",
		"materials": {"mat_zj_xuecao": 1},
		"success_rate": 0.72, "battle_cooldown": 30.0,
		"battle_effect": {"kind": "heal_hp", "ratio": 0.15},
		"is_consumable": true,
		"desc": "以云隐血参入药。服下回复三成不到的气血。",
	},
	{
		"recipe_id": "recipe_zj_julingdan", "pill_id": "pill_zj_julingdan", "pill_name": "筑基聚灵丹",
		"realm": "筑基", "rarity": "rare",
		"icon": "res://assets/ui/icon/pill_julingdan.png",
		"materials": {"mat_zj_lanyingcao": 1},
		"success_rate": 0.72, "battle_cooldown": 30.0,
		"battle_effect": {"kind": "restore_mana", "ratio": 0.15},
		"is_consumable": true,
		"desc": "以云隐蓝萤草为主药。服下回复灵力。",
	},
	{
		"recipe_id": "recipe_zj_julidan", "pill_id": "pill_zj_julidan", "pill_name": "筑基巨力丹",
		"realm": "筑基", "rarity": "rare",
		"icon": "res://assets/ui/icon/pill_julidan.png",
		"materials": {"mat_zj_liyuanguo": 1},
		"success_rate": 0.68, "battle_cooldown": 45.0,
		"battle_effect": {"kind": "buff", "buff_id": "pill_juli_zj", "seconds": 20.0, "mods": {"strength": {"base_pct": 14.0}}},
		"is_consumable": true,
		"desc": "以云隐力元果为主药。服下后短时间内力量上涨。",
	},
	{
		"recipe_id": "recipe_zj_lingfadan", "pill_id": "pill_zj_lingfadan", "pill_name": "筑基灵法丹",
		"realm": "筑基", "rarity": "rare",
		"icon": "res://assets/ui/icon/pill_lingfadan.png",
		"materials": {"mat_zj_falinghua": 1},
		"success_rate": 0.68, "battle_cooldown": 45.0,
		"battle_effect": {"kind": "buff", "buff_id": "pill_lingfa_zj", "seconds": 20.0, "mods": {"spell_power": {"base_pct": 14.0}}},
		"is_consumable": true,
		"desc": "以云隐法灵花为主药。服下后短时间内法强上涨。",
	},
	{
		"recipe_id": "recipe_zj_jingangdan", "pill_id": "pill_zj_jingangdan", "pill_name": "筑基金刚丹",
		"realm": "筑基", "rarity": "rare",
		"icon": "res://assets/ui/icon/pill_jingangdan.png",
		"materials": {"mat_zj_huguteng": 1},
		"success_rate": 0.68, "battle_cooldown": 45.0,
		"battle_effect": {"kind": "buff", "buff_id": "pill_jingang_zj", "seconds": 20.0, "mods": {"physical_resist": {"flat": 16.0}, "magic_resist": {"flat": 16.0}}},
		"is_consumable": true,
		"desc": "以云隐护骨藤为主药。服下后物抗与法抗提升。",
	},

	# ===== 赤金丹霞丹方（2026-10-30：结丹档；丹药名 = 对应境界名 + 丹名）=====
	{
		"recipe_id": "recipe_jd_huichundan", "pill_id": "pill_jd_huichundan", "pill_name": "结丹回春丹",
		"realm": "结丹", "rarity": "epic",
		"icon": "res://assets/ui/icon/pill_huichundan.png",
		"materials": {"mat_jd_xuecao": 1},
		"success_rate": 0.70, "battle_cooldown": 30.0,
		"battle_effect": {"kind": "heal_hp", "ratio": 0.20},
		"is_consumable": true,
		"desc": "以赤金血参入药。服下回复气血上限的两成。",
	},
	{
		"recipe_id": "recipe_jd_julingdan", "pill_id": "pill_jd_julingdan", "pill_name": "结丹聚灵丹",
		"realm": "结丹", "rarity": "epic",
		"icon": "res://assets/ui/icon/pill_julingdan.png",
		"materials": {"mat_jd_lanyingcao": 1},
		"success_rate": 0.70, "battle_cooldown": 30.0,
		"battle_effect": {"kind": "restore_mana", "ratio": 0.20},
		"is_consumable": true,
		"desc": "以赤金蓝萤草为主药。服下回复灵力上限的两成。",
	},
	{
		"recipe_id": "recipe_jd_julidan", "pill_id": "pill_jd_julidan", "pill_name": "结丹巨力丹",
		"realm": "结丹", "rarity": "epic",
		"icon": "res://assets/ui/icon/pill_julidan.png",
		"materials": {"mat_jd_liyuanguo": 1},
		"success_rate": 0.66, "battle_cooldown": 45.0,
		"battle_effect": {"kind": "buff", "buff_id": "pill_juli_jd", "seconds": 20.0, "mods": {"strength": {"base_pct": 18.0}}},
		"is_consumable": true,
		"desc": "以赤金力元果为主药。服下后短时间内力量上涨。",
	},
	{
		"recipe_id": "recipe_jd_lingfadan", "pill_id": "pill_jd_lingfadan", "pill_name": "结丹灵法丹",
		"realm": "结丹", "rarity": "epic",
		"icon": "res://assets/ui/icon/pill_lingfadan.png",
		"materials": {"mat_jd_falinghua": 1},
		"success_rate": 0.66, "battle_cooldown": 45.0,
		"battle_effect": {"kind": "buff", "buff_id": "pill_lingfa_jd", "seconds": 20.0, "mods": {"spell_power": {"base_pct": 18.0}}},
		"is_consumable": true,
		"desc": "以赤金法灵花为主药。服下后短时间内法强上涨。",
	},
	{
		"recipe_id": "recipe_jd_jingangdan", "pill_id": "pill_jd_jingangdan", "pill_name": "结丹金刚丹",
		"realm": "结丹", "rarity": "epic",
		"icon": "res://assets/ui/icon/pill_jingangdan.png",
		"materials": {"mat_jd_huguteng": 1},
		"success_rate": 0.66, "battle_cooldown": 45.0,
		"battle_effect": {"kind": "buff", "buff_id": "pill_jingang_jd", "seconds": 20.0, "mods": {"physical_resist": {"flat": 22.0}, "magic_resist": {"flat": 22.0}}},
		"is_consumable": true,
		"desc": "以赤金护骨藤为主药。服下后物抗与法抗提升。",
	},

	# ===== 幽冥灵墟丹方（2026-11-01：元婴档；一株料 = 一颗成品）=====
	{
		"recipe_id": "recipe_yy_huichundan", "pill_id": "pill_yy_huichundan", "pill_name": "元婴回春丹",
		"realm": "元婴", "rarity": "legendary",
		"icon": "res://assets/ui/icon/pill_huichundan.png",
		"materials": {"mat_yy_xuecao": 1},
		"success_rate": 0.68, "battle_cooldown": 30.0,
		"battle_effect": {"kind": "heal_hp", "ratio": 0.25},
		"is_consumable": true,
		"desc": "以幽冥血参入药，药性沉寒而回元。服下回复气血上限的两成半。",
	},
	{
		"recipe_id": "recipe_yy_julingdan", "pill_id": "pill_yy_julingdan", "pill_name": "元婴聚灵丹",
		"realm": "元婴", "rarity": "legendary",
		"icon": "res://assets/ui/icon/pill_julingdan.png",
		"materials": {"mat_yy_lanyingcao": 1},
		"success_rate": 0.68, "battle_cooldown": 30.0,
		"battle_effect": {"kind": "restore_mana", "ratio": 0.25},
		"is_consumable": true,
		"desc": "以幽冥蓝萤草为主药，萤光聚而不散。服下回复灵力上限的两成半。",
	},
	{
		"recipe_id": "recipe_yy_julidan", "pill_id": "pill_yy_julidan", "pill_name": "元婴巨力丹",
		"realm": "元婴", "rarity": "legendary",
		"icon": "res://assets/ui/icon/pill_julidan.png",
		"materials": {"mat_yy_liyuanguo": 1},
		"success_rate": 0.64, "battle_cooldown": 45.0,
		"battle_effect": {"kind": "buff", "buff_id": "pill_juli_yy", "seconds": 20.0, "mods": {"strength": {"base_pct": 22.0}}},
		"is_consumable": true,
		"desc": "以幽冥力元果为主药，寒意入腹而气力翻涌。服下后短时间内力量上涨。",
	},
	{
		"recipe_id": "recipe_yy_lingfadan", "pill_id": "pill_yy_lingfadan", "pill_name": "元婴灵法丹",
		"realm": "元婴", "rarity": "legendary",
		"icon": "res://assets/ui/icon/pill_lingfadan.png",
		"materials": {"mat_yy_falinghua": 1},
		"success_rate": 0.64, "battle_cooldown": 45.0,
		"battle_effect": {"kind": "buff", "buff_id": "pill_lingfa_yy", "seconds": 20.0, "mods": {"spell_power": {"base_pct": 22.0}}},
		"is_consumable": true,
		"desc": "以幽冥法灵花为主药，花心幽火不散。服下后短时间内法强上涨。",
	},
	{
		"recipe_id": "recipe_yy_jingangdan", "pill_id": "pill_yy_jingangdan", "pill_name": "元婴金刚丹",
		"realm": "元婴", "rarity": "legendary",
		"icon": "res://assets/ui/icon/pill_jingangdan.png",
		"materials": {"mat_yy_huguteng": 1},
		"success_rate": 0.64, "battle_cooldown": 45.0,
		"battle_effect": {"kind": "buff", "buff_id": "pill_jingang_yy", "seconds": 20.0, "mods": {"physical_resist": {"flat": 28.0}, "magic_resist": {"flat": 28.0}}},
		"is_consumable": true,
		"desc": "以幽冥护骨藤为主药，藤骨相缠、阴气不侵。服下后物抗与法抗提升。",
	},
]

## 2026-10-31：旧烈火符 / 磐石符（含三个境界变体）已整套移除，只保留七元素符。
const TALISMAN_RECIPES: Array = []


# ===== 元素符（2026-10-31 定稿）=====
const ELEMENT_TALISMAN_QUALITIES: Array = [
	{"key": "lianqi", "realm": "练气", "rarity": "common", "cost": 10.0},
	{"key": "zhuji", "realm": "筑基", "rarity": "rare", "cost": 50.0},
	{"key": "jiedan", "realm": "结丹", "rarity": "epic", "cost": 100.0},
	{"key": "yuanying", "realm": "元婴", "rarity": "legendary", "cost": 200.0},
]
const TALISMAN_ATTACK_MATERIALS: Array[String] = [
	"mat_ruishoupi", "mat_zj_ruishoupi", "mat_jd_ruishoupi", "mat_yy_ruishoupi",
]
const TALISMAN_FUNC_MATERIALS: Array[String] = [
	"mat_jianshoupi", "mat_zj_jianshoupi", "mat_jd_jianshoupi", "mat_yy_jianshoupi",
]
const ELEMENT_TALISMAN_BASES: Array = [
	{
		"base_id": "tal_jinfeng", "name": "金锋符", "element": "metal",
		"talisman_type": "攻击", "effect": "sword_qi", "damage": [60, 120, 600, 1800],
		"icon": "res://assets/ui/icon/tal_element_metal.png",
		"card": "res://assets/ui/talisman/cards/talisman_card_metal.png",
		"desc": "向目标射出一道剑气，命中第一个目标。伤害固定，只有品阶会提高伤害。",
	},
	{
		"base_id": "tal_huoqiu", "name": "火球符", "element": "fire",
		"talisman_type": "攻击", "effect": "fireball", "damage": [50, 100, 500, 1500],
		"icon": "res://assets/ui/icon/tal_element_fire.png",
		"card": "res://assets/ui/talisman/cards/talisman_card_fire.png",
		"desc": "在最近目标处落火球，80 半径内结算火伤，并附加灼烧。伤害固定。",
	},
	{
		"base_id": "tal_yinlei", "name": "引雷符", "element": "thunder",
		"talisman_type": "攻击", "effect": "lightning", "damage": [50, 100, 500, 1500],
		"stun_chance": [0.25, 0.30, 0.35, 0.40], "stun_time": [0.8, 1.0, 1.2, 1.4],
		"icon": "res://assets/ui/icon/tal_element_thunder.png",
		"card": "res://assets/ui/talisman/cards/talisman_card_thunder.png",
		"desc": "在最近目标头顶落雷，造成固定雷伤；有概率眩晕目标。",
	},
	{
		"base_id": "tal_muling", "name": "木缚符", "element": "wood",
		"talisman_type": "控制", "effect": "root", "root_time": [2.0, 3.0, 4.0, 5.0],
		"icon": "res://assets/ui/icon/tal_element_wood.png",
		"card": "res://assets/ui/talisman/cards/talisman_card_wood.png",
		"desc": "藤缚最近目标，使其定身 2 / 3 / 4 秒；目标仍可出招。",
	},
	{
		"base_id": "tal_shuihui", "name": "水愈符", "element": "water",
		"talisman_type": "功能", "effect": "regen_hp",
		"heal_per_sec": [10.0, 10.0, 10.0, 16.0], "heal_time": [8.0, 10.0, 12.0, 14.0],
		"icon": "res://assets/ui/icon/tal_element_water.png",
		"card": "res://assets/ui/talisman/cards/talisman_card_water.png",
		"desc": "8 / 10 / 12 秒内每秒回复 10 点气血，不瞬间抬血。",
	},
	{
		"base_id": "tal_fengji", "name": "风疾符", "element": "wind",
		"talisman_type": "功能", "effect": "speed_up",
		"speed_pct": [30.0, 35.0, 40.0, 45.0], "duration": [10.0, 12.0, 15.0, 18.0],
		"icon": "res://assets/ui/icon/tal_element_wind.png",
		"card": "res://assets/ui/talisman/cards/talisman_card_wind.png",
		"desc": "10 / 12 / 15 秒内移速 +30% / +35% / +40%，不加攻速与伤害。",
	},
	{
		"base_id": "tal_tushi", "name": "石附符", "element": "earth",
		"talisman_type": "功能", "effect": "stone_body",
		"speed_down": [15.0, 15.0, 20.0, 20.0], "damage_reduction": [20.0, 30.0, 40.0, 50.0],
		"hits": [3, 4, 5, 6], "duration": 12.0,
		"icon": "res://assets/ui/icon/tal_element_earth.png",
		"card": "res://assets/ui/talisman/cards/talisman_card_earth.png",
		"desc": "石块附身：移速下降、受到的伤害降低；受伤次数用尽或 12 秒后解除。",
	},
]


static func element_talisman_item_id(base_id: String, quality_index: int) -> String:
	if quality_index < 0 or quality_index >= ELEMENT_TALISMAN_QUALITIES.size():
		return ""
	return "%s_%s" % [base_id, String((ELEMENT_TALISMAN_QUALITIES[quality_index] as Dictionary).get("key", ""))]


static func is_element_talisman_id(item_id: String) -> bool:
	return not element_talisman_def(item_id).is_empty()


static func element_talisman_def(item_id: String) -> Dictionary:
	if item_id == "" or not item_id.begins_with("tal_"):
		return {}
	for raw_base in ELEMENT_TALISMAN_BASES:
		var b: Dictionary = raw_base
		var base_id := String(b.get("base_id", ""))
		for qi in range(ELEMENT_TALISMAN_QUALITIES.size()):
			if element_talisman_item_id(base_id, qi) != item_id:
				continue
			var q: Dictionary = ELEMENT_TALISMAN_QUALITIES[qi]
			var realm := String(q.get("realm", ""))
			var mats: Array = TALISMAN_ATTACK_MATERIALS if String(b.get("talisman_type", "")) == "攻击" else TALISMAN_FUNC_MATERIALS
			var material := String(mats[qi])
			var eff := {
				"kind": "element_talisman",
				"effect": String(b.get("effect", "")),
				"element": String(b.get("element", "")),
				"quality": qi,
				"realm": realm,
			}
			if b.has("damage"):
				eff["damage"] = int((b.get("damage") as Array)[qi])
			if b.has("stun_chance"):
				eff["stun_chance"] = float((b.get("stun_chance") as Array)[qi])
				eff["stun_time"] = float((b.get("stun_time") as Array)[qi])
			if b.has("root_time"):
				eff["root_time"] = float((b.get("root_time") as Array)[qi])
			if b.has("heal_time"):
				var hps = b.get("heal_per_sec", 10.0)
				eff["heal_per_sec"] = float(hps[qi]) if hps is Array else float(hps)
				eff["heal_time"] = float((b.get("heal_time") as Array)[qi])
			if b.has("speed_pct"):
				eff["speed_pct"] = float((b.get("speed_pct") as Array)[qi])
				eff["duration"] = float((b.get("duration") as Array)[qi])
			if b.has("speed_down"):
				eff["speed_down"] = float((b.get("speed_down") as Array)[qi])
				eff["damage_reduction"] = float((b.get("damage_reduction") as Array)[qi])
				eff["hits"] = int((b.get("hits") as Array)[qi])
				eff["duration"] = float(b.get("duration", 12.0))
			return {
				"id": item_id,
				"kind": "talisman",
				"base_id": base_id,
				"talisman_id": item_id,
				"talisman_name": "%s·%s" % [String(b.get("name", "")), realm],
				"name": "%s·%s" % [String(b.get("name", "")), realm],
				"talisman_type": String(b.get("talisman_type", "")),
				"element": String(b.get("element", "")),
				"realm": realm,
				"quality": qi,
				"rarity": String(q.get("rarity", "common")),
				"icon": String(b.get("icon", "")),
				"card": String(b.get("card", "")),
				"materials": {material: 1},
				"cultivation_cost": float(q.get("cost", 0.0)),
				"uses_realm_success": true,
				"mana_cost": 5.0,
				"battle_cooldown": 0.0,
				"battle_effect": eff,
				"is_consumable": true,
				"desc": String(b.get("desc", "")),
			}
	return {}


static func element_talisman_recipes() -> Array:
	var out: Array = []
	for raw_base in ELEMENT_TALISMAN_BASES:
		var b: Dictionary = raw_base
		for qi in range(ELEMENT_TALISMAN_QUALITIES.size()):
			var item_id := element_talisman_item_id(String(b.get("base_id", "")), qi)
			var def := element_talisman_def(item_id)
			if def.is_empty():
				continue
			out.append({
				"recipe_id": "recipe_" + item_id,
				"talisman_id": item_id,
				"talisman_name": String(def.get("talisman_name", "")),
				"realm": String(def.get("realm", "")),
				"rarity": String(def.get("rarity", "common")),
				"talisman_type": String(def.get("talisman_type", "")),
				"icon": String(def.get("icon", "")),
				"materials": (def.get("materials", {}) as Dictionary).duplicate(true),
				"cultivation_cost": float(def.get("cultivation_cost", 0.0)),
				"uses_realm_success": true,
				"mana_cost": 5.0,
				"battle_cooldown": 0.0,
				"battle_effect": (def.get("battle_effect", {}) as Dictionary).duplicate(true),
				"is_consumable": true,
				"desc": String(def.get("desc", "")),
			})
	return out


static func all_talisman_recipes() -> Array:
	return element_talisman_recipes()


static func talisman_cultivation_cost(recipe: Dictionary) -> float:
	if recipe.has("cultivation_cost"):
		return float(recipe.get("cultivation_cost", 0.0))
	var realm := String(recipe.get("realm", ""))
	for q in ELEMENT_TALISMAN_QUALITIES:
		if String((q as Dictionary).get("realm", "")) == realm:
			return float((q as Dictionary).get("cost", 0.0))
	return 0.0


static func talisman_success_rate(recipe_realm: String) -> float:
	var cur := CharacterData.get_realm_index()
	var idx := CharacterData.REALM_ORDER.find(recipe_realm)
	if cur < 0 or idx < 0:
		return 0.0
	if cur >= idx:
		return 1.0
	if idx == cur + 1:
		return 0.05
	return 0.0


# ===== 装备模板（§5.2）=====
## equipment_type 为**装备类别**，与槽位的对应关系由 CharacterData.SLOT_TYPE 决定：
##   weapon 武器 / armor 护甲 / shoes 鞋子 / accessory 饰品（可装 3 个）
##
## attributes 为该装备提供的**属性**（力量/法强/攻速/抗性/气血…），属性 id 见 AttributeDB。
## 这是「装备给玩家提供基础属性数值」的落点。
##
## attack_bonus 只表示「武器自身的基础攻击力」，会随品阶与强化成长；
## 新模板一般留 0，把主要数值放进 attributes.strength，避免同一份伤害被加两次。
##
## ⚠ 2026-10-17 用户要求：**只保留刀客掉落的弯刀**，其余装备全部删除；
##   新增虎妖掉落的虎皮袍。开局不再自带任何装备（装备来源只有 BOSS 掉落）。
##   想加新装备：在这里补一条模板 + 在下面的 DROP_TEMPLATES 里挂到某个 BOSS 上。
const EQUIPMENT_TEMPLATES: Array = [
	# ---------- 武器：弯刀（凡界 · 刀客掉落）----------
	{
		"equipment_id": "eq_fanpinwandao",
		"equipment_name": "弯刀",
		"equipment_grade": "凡品",
		"equipment_type": "weapon",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "练气",
		"current_domain": "domain_01",
		"is_permanently_owned": true,
		"attributes": {"strength": 8.0},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_curved_blade.png",
		# 武器外观（ArtDB.VISUALS 的条目 id）。留空 = 用默认的 player_weapon
		"weapon_visual": "weapon_curved_blade",
		"desc": "凡界刀客的随身弯刀，刃口已卷，胜在称手。力量 +8。",
	},

	# ---------- 武器：铁剑（初始武器）----------
	{
		"equipment_id": "eq_tiejian",
		"equipment_name": "铁剑",
		"equipment_grade": "凡品",
		"equipment_type": "weapon",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "练气",
		"current_domain": "domain_01",
		"is_permanently_owned": true,
		"is_starting_equipment": true,
		"attributes": {"strength": 1.0},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_iron_sword.png",
		# 复用默认的御剑外观：换武器不换攻击表现，除非这把武器单独配了别的 id
		"weapon_visual": "",
		"desc": "村口铁匠打的粗剑，剑身沉手，胜在轻便顺手。力量 +1。",
	},

	# ---------- 护甲：虎皮袍（凡界 · 虎妖掉落）----------
	{
		"equipment_id": "eq_hupipao",
		"equipment_name": "虎皮袍",
		"equipment_grade": "凡品",
		"equipment_type": "armor",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "练气",
		"current_domain": "domain_01",
		"is_permanently_owned": true,
		"attributes": {
			AttributeDB.ATTR_HP_MAX: 10.0,
		},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_hupipao.png",
		"desc": "虎妖的整张皮毛粗粗硝制而成，厚实御寒。气血 +10。",
	},

	# ---------- 护甲：藤甲（苍澜大陆 · 练气区核心首领掉落）----------
	{
		"equipment_id": "eq_tengjia",
		"equipment_name": "藤甲",
		"equipment_grade": "凡品",
		"equipment_type": "armor",
		"icon": "res://assets/ui/icon/equip_tengjia.png",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "练气",
		"current_domain": "domain_01",
		"is_permanently_owned": true,
		"attributes": {
			AttributeDB.ATTR_HP_MAX: 10.0,
			"resist_water": 1.0,
		},
		"attack_bonus": 0.0,
		"desc": "以老藤与灵木编成的护甲，轻便耐水。气血上限 +10，水抗 +1（约 1% 水属性减伤）。",
	},

	# ---------- 护甲：苍角甲（苍澜大陆 · 云隐谷核心首领掉落，2026-10-29）----------
	{
		"equipment_id": "eq_cangjiao_jia",
		"equipment_name": "苍角甲",
		"equipment_grade": "凡品",
		"equipment_type": "armor",
		"icon": "res://assets/ui/icon/equip_cangjiao_jia.png",
		"equipment_level": 2,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "筑基",
		"current_domain": "domain_02",
		"is_permanently_owned": true,
		"attributes": {
			AttributeDB.ATTR_HP_MAX: 24.0,
			AttributeDB.ATTR_PHYSICAL_RESIST: 3.0,
			"resist_wood": 2.0,
		},
		"attack_bonus": 0.0,
		"desc": "以苍角褪下的苔石片与老藤编成的轻甲，沉而不滞。气血上限 +24，物抗 +3，木抗 +2。",
	},

	# ---------- 护甲：火麟甲（苍澜大陆 · 赤金丹霞核心首领掉落，2026-10-29）----------
	# 物理坦克向：气血 +40 / 物抗 +5 / 火抗 +4；与烬纹战袍（法系火袍）、苍角甲（木抗）、藤甲（水抗）区分。
	{
		"equipment_id": "eq_huolin_jia",
		"equipment_name": "火麟甲",
		"equipment_grade": "凡品",
		"equipment_type": "armor",
		"icon": "res://assets/ui/icon/equip_huolin_jia.png",
		"equipment_level": 2,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "结丹",
		"current_domain": "domain_03",
		"is_permanently_owned": true,
		"attributes": {
			AttributeDB.ATTR_HP_MAX: 40.0,
			AttributeDB.ATTR_PHYSICAL_RESIST: 5.0,
			"resist_fire": 4.0,
		},
		"attack_bonus": 0.0,
		"desc": "以火麟褪下的赤金鳞片编成的轻甲，触手仍有余温。气血上限 +40，物抗 +5，火抗 +4。",
	},

	# ---------- 护甲：镇墟石甲（苍澜大陆 · 幽冥灵墟核心首领掉落，2026-10-31）----------
	# 石兽向：气血 +60 / 物抗 +7 / 土抗 +6；与火麟甲（火抗）、苍角甲（木抗）、烬纹战袍（法系）区分。
	{
		"equipment_id": "eq_zhenxu_jia",
		"equipment_name": "镇墟石甲",
		"equipment_grade": "凡品",
		"equipment_type": "armor",
		"icon": "res://assets/ui/icon/equip_zhenxu_jia.png",
		"equipment_level": 3,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "元婴",
		"current_domain": "world",
		"is_permanently_owned": true,
		"attributes": {
			AttributeDB.ATTR_HP_MAX: 60.0,
			AttributeDB.ATTR_PHYSICAL_RESIST: 7.0,
			"resist_earth": 6.0,
		},
		"attack_bonus": 0.0,
		"desc": "以九天门崩落的墓石与镇兽褪下的石片拼成，胸口的青幽火始终不灭。气血上限 +60，物抗 +7，土抗 +6。",
	},

	# ---------- 饰品：虎牙项链（凡界 · 虎妖掉落）----------
	{
		"equipment_id": "eq_huyaxianglian",
		"equipment_name": "虎牙项链",
		"equipment_grade": "凡品",
		"equipment_type": "accessory",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "练气",
		"current_domain": "domain_01",
		"is_permanently_owned": true,
		# 法技增伤：只增强法术功法的直接伤害（2026-10-24 用户定）
		"attributes": {
			AttributeDB.ATTR_SPELL_SKILL_DAMAGE_PCT: 1.0,
		},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_huyaxianglian.png",
		"desc": "虎妖的獠牙系在旧皮绳上，凶气未散。法技增伤 +1%。",
	},

	# ---------- 武器：清风剑（凡界 · 剑客掉落）----------
	{
		"equipment_id": "eq_qingfengjian",
		"equipment_name": "清风剑",
		"equipment_grade": "凡品",
		"equipment_type": "weapon",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "练气",
		"current_domain": "domain_01",
		"is_permanently_owned": true,
		# ⚠ 数值口径（用户 2026-10-19 调价，原话「精力恢复加太多了」）：
		#   旧版 stamina_regen +0.10（绝对值，0.25→0.35 约 +40%）实测过量；
		#   新版改成百分比词条 stamina_regen_pct +1.0（= 精力恢复速度 +1%，0.25→0.2525），
		#   锻造（强化）有几率再 +0.5%~1.0（区间见 AttributeDB.ENHANCE_RANGE）。
		"attributes": {
			AttributeDB.ATTR_STRENGTH: 20.0,
			AttributeDB.ATTR_STAMINA_REGEN_PCT: 1.0,
		},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_qingfengjian.png",
		# 局内御剑形象：ArtDB.VISUALS 的 weapon_qingfeng_jian（战斗图已由 UI 图标转正生成，
		# assets/effects/weapons/qingfeng_jian.png，竖直、透明底、刃尖朝下）
		"weapon_visual": "weapon_qingfeng_jian",
		"desc": "剑客佩剑，剑身泛青，挥动时自带清风。力量 +20，精力恢复速度 +1%。",
	},

	# ---------- 鞋子：清风鞋（凡界 · 剑客掉落）----------
	{
		"equipment_id": "eq_qingfengxie",
		"equipment_name": "清风鞋",
		"equipment_grade": "凡品",
		# ⚠ 类别必须是 `shoes`（CharacterData.SLOT_TYPE 的键），写 boots 找不到槽位、无法穿戴
		"equipment_type": "shoes",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "练气",
		"current_domain": "domain_01",
		"is_permanently_owned": true,
		# ⚠ 数值口径（用户 2026-10-19 调价，与清风剑同一套）：
		#   旧版 speed +11（绝对值，220→231 约 +5%）→ 新版百分比词条 speed_pct +1.0
		#   （= 移动速度 +1%，220→222.2），锻造每次有几率再 +0.1%~0.5%。
		"attributes": {
			AttributeDB.ATTR_SPEED_PCT: 1.0,
		},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_qingfengxie.png",
		"desc": "云纹绣口，踏地无声。移动速度 +1%。",
	},

	# ---------- 位面 02 · 太虚气君掉落（2026-10-28）----------
	# 用途差异：补「灵力回复」这一空缺（现有装备只有灵力上限、没有回复），
	# 以及第二双鞋（此前只有清风鞋）。
	{
		"equipment_id": "eq_taixu_yunlv",
		"equipment_name": "太虚云履",
		"equipment_grade": "凡品",
		"equipment_type": "shoes",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "筑基",
		"current_domain": "domain_02",
		"is_permanently_owned": true,
		"attributes": {
			AttributeDB.ATTR_MANA_REGEN: 0.15,
			AttributeDB.ATTR_SPEED_PCT: 1.0,
		},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_taixu_yunlv.png",
		"desc": "履底薄如云，走路时灵力自回。灵力恢复 +0.15/秒，移动速度 +1%。",
	},
	{
		"equipment_id": "eq_qihai_yuzhui",
		"equipment_name": "气海玉坠",
		"equipment_grade": "凡品",
		"equipment_type": "accessory",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "筑基",
		"current_domain": "domain_02",
		"is_permanently_owned": true,
		"attributes": {
			AttributeDB.ATTR_SPELL_POWER: 4.0,
			AttributeDB.ATTR_MANA_MAX: 10.0,
		},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_qihai_yuzhui.png",
		"desc": "一枚中空的玉坠，贴在耳边能听见气海潮声。法强 +4，灵力上限 +10。",
	},

	# ---------- 位面 02 · 两仪真人掉落（2026-10-27）----------
	# 用途差异：不追数值膨胀，补玩家当前最缺的「法强 / 法抗 / 灵力」。
	{
		"equipment_id": "eq_liangyi_yujue",
		"equipment_name": "两仪玉玦",
		"equipment_grade": "凡品",
		"equipment_type": "accessory",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "筑基",
		"current_domain": "domain_02",
		"is_permanently_owned": true,
		# 混伤向：力量 +6 / 法强 +10。玩家此前几乎没有法强装备，
		# 这件是把「阴招」从摆设变成可用手段的关键（见 docs/两仪真人BOSS完整资料.md）。
		"attributes": {
			AttributeDB.ATTR_STRENGTH: 6.0,
			AttributeDB.ATTR_SPELL_POWER: 10.0,
		},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_liangyi_yujue.png",
		"desc": "半金半青的玉玦，阴阳二气在缺口处流转。力量 +6，法强 +10。",
	},
	{
		"equipment_id": "eq_zhuxian_chizhang",
		"equipment_name": "朱弦阵尺",
		"equipment_grade": "凡品",
		"equipment_type": "weapon",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "筑基",
		"current_domain": "domain_02",
		"is_permanently_owned": true,
		# 法系武器：玩家此前没有主加法强的兵器（两仪玉玦是饰品）。
		"attributes": {AttributeDB.ATTR_SPELL_POWER: 9.0},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_zhuxian_chizhang.png",
		"weapon_visual": "weapon_zhuxian_chizhang",
		"desc": "一柄朱砂色的阵尺，尺面刻满经纬。法强 +9。",
	},
	{
		"equipment_id": "eq_dingzhen_chanwan",
		"equipment_name": "定阵缠手",
		"equipment_grade": "凡品",
		"equipment_type": "accessory",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "筑基",
		"current_domain": "domain_02",
		"is_permanently_owned": true,
		# 续航向：法抗 + 少量法强，与两仪玉玦（纯输出）区分。
		"attributes": {AttributeDB.ATTR_MAGIC_RESIST: 3.0, AttributeDB.ATTR_SPELL_POWER: 2.0},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_dingzhen_chanwan.png",
		"desc": "缠在腕上的阵线，抬手时自动绷直。法抗 +3，法强 +2。",
	},
	{
		"equipment_id": "eq_xuansu_daopao",
		"equipment_name": "玄素道袍",
		"equipment_grade": "凡品",
		"equipment_type": "armor",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "筑基",
		"current_domain": "domain_02",
		"is_permanently_owned": true,
		# 防御向：气血 +16 / 法抗 +6 / 灵力上限 +8。
		# 与虎皮袍（纯气血）、藤甲（气血 + 水抗）区分：这件偏法抗与续航。
		"attributes": {
			AttributeDB.ATTR_HP_MAX: 16.0,
			AttributeDB.ATTR_MAGIC_RESIST: 6.0,
			AttributeDB.ATTR_MANA_MAX: 8.0,
		},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_xuansu_daopao.png",
		"desc": "玄黑为底、素白为纹的道袍，袖口绣着半枚太极。气血 +16，法抗 +6，灵力 +8。",
	},

	# ---------- 位面 03 · 赫连霄掉落（2026-10-29）----------
	# 用途差异：补「攻速」这一空缺（此前没有任何装备提供攻速），
	# 以及法系武器的「法技增伤」向（此前只有虎牙项链给 1%）。
	{
		"equipment_id": "eq_leiwen_huqi",
		"equipment_name": "雷纹护臂",
		"equipment_grade": "凡品",
		"equipment_type": "accessory",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "结丹",
		"current_domain": "domain_03",
		"is_permanently_owned": true,
		# 全项目首件攻速装备：不加力量、只让你出手更密；物抗补一点物理生存。
		"attributes": {
			AttributeDB.ATTR_ATTACK_SPEED: 6.0,
			AttributeDB.ATTR_PHYSICAL_RESIST: 2.0,
		},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_leiwen_huqi.png",
		"desc": "雷纹缠腕的护臂，出手越快纹路越亮。攻速 +6%，物抗 +2。",
	},
	{
		"equipment_id": "eq_panguan_tiebi",
		"equipment_name": "判官铁笔",
		"equipment_grade": "凡品",
		"equipment_type": "weapon",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "结丹",
		"current_domain": "domain_03",
		"is_permanently_owned": true,
		# 法系武器：法强 + 法技增伤。与朱弦阵尺（纯法强）、清风剑（物攻+回精）区分。
		"attributes": {
			AttributeDB.ATTR_SPELL_POWER: 8.0,
			AttributeDB.ATTR_SPELL_SKILL_DAMAGE_PCT: 2.0,
		},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_panguan_tiebi.png",
		"weapon_visual": "weapon_panguan_tiebi",
		"desc": "以雷纹铁铸成的判笔，落墨如雷。法强 +8，法技增伤 +2%。",
	},

	# ---------- 位面 03 · 离照掉落（2026-10-29）----------
	# 用途差异：补火系法袍与精力循环；不与玄素道袍（法抗）、太虚云履（回灵）重复。
	{
		"equipment_id": "eq_jinwen_zhanpao",
		"equipment_name": "烬纹战袍",
		"equipment_grade": "凡品",
		"equipment_type": "armor",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "结丹",
		"current_domain": "domain_03",
		"is_permanently_owned": true,
		# 火祭法袍向：气血 +18 / 法抗 +4 / 火抗 +6 / 法强 +6。
		# 与火麟甲（气血/物抗/火抗的物理坦克）、玄素道袍（法抗+灵力）、劫灰法衣（物法均衡）区分。
		"attributes": {
			AttributeDB.ATTR_HP_MAX: 18.0,
			AttributeDB.ATTR_MAGIC_RESIST: 4.0,
			"resist_fire": 6.0,
			AttributeDB.ATTR_SPELL_POWER: 6.0,
		},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_jinwen_zhanpao.png",
		"desc": "火正祭袍的残片，烬纹在布面下缓缓流动。气血 +18，法抗 +4，火抗 +6，法强 +6。",
	},
	{
		"equipment_id": "eq_zhuri_lv",
		"equipment_name": "逐日履",
		"equipment_grade": "凡品",
		"equipment_type": "shoes",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "结丹",
		"current_domain": "domain_03",
		"is_permanently_owned": true,
		# 精力循环向：移速 +2% / 精力恢复 +2% / 火抗 +3。
		"attributes": {
			AttributeDB.ATTR_SPEED_PCT: 2.0,
			AttributeDB.ATTR_STAMINA_REGEN_PCT: 2.0,
			"resist_fire": 3.0,
		},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_zhuri_lv.png",
		"desc": "履底绣着两枚追逐的日纹，踏火不焦。移速 +2%，精力恢复 +2%，火抗 +3。",
	},

	# ---------- 位面 03 · 晏无咎掉落（2026-10-29）----------
	# 用途差异：劫锋补「纯输出武器」（力量 + 攻速，不要精力），
	# 劫灰法衣补「物法双抗护甲」（不是纯物抗/纯法抗）。
	{
		"equipment_id": "eq_jiefeng",
		"equipment_name": "劫锋",
		"equipment_grade": "凡品",
		"equipment_type": "weapon",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "结丹",
		"current_domain": "domain_03",
		"is_permanently_owned": true,
		# 纯输出向：力量 + 攻速。与清风剑（力量+回精）、弯刀（纯力量）区分。
		"attributes": {
			AttributeDB.ATTR_STRENGTH: 20.0,
			AttributeDB.ATTR_ATTACK_SPEED: 3.0,
		},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_jiefeng.png",
		"weapon_visual": "weapon_jiefeng",
		"desc": "一柄从劫灰里捡回来的断锋，刃口还留着三道雷痕。力量 +20，攻速 +3%。",
	},
	{
		"equipment_id": "eq_jiehui_fayi",
		"equipment_name": "劫灰法衣",
		"equipment_grade": "凡品",
		"equipment_type": "armor",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "结丹",
		"current_domain": "domain_03",
		"is_permanently_owned": true,
		# 均衡防御：气血 + 物抗 + 法抗；与烬纹（物抗/火抗）、玄素（法抗/灵力）区分。
		"attributes": {
			AttributeDB.ATTR_HP_MAX: 20.0,
			AttributeDB.ATTR_PHYSICAL_RESIST: 4.0,
			AttributeDB.ATTR_MAGIC_RESIST: 4.0,
		},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_jiehui_fayi.png",
		"desc": "劫灰织成的法衣，灰白布面下压着风、火、雷三道暗纹。气血 +20，物抗 +4，法抗 +4。",
	},

	# ---------- 位面 04 · 观澜掉落（2026-11-01）----------
	# 用途差异：镜潭尺补「法强 + 回灵」的续航法器（判官铁笔是法强+法技，朱弦阵尺是纯法强）；
	# 水月袍补「法抗 + 水抗」的护甲（现有护甲要么偏物抗，要么火抗/木抗/土抗）。
	{
		"equipment_id": "eq_jingtan_chi",
		"equipment_name": "镜潭尺",
		"equipment_grade": "凡品",
		"equipment_type": "weapon",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "元婴",
		"current_domain": "domain_04",
		"is_permanently_owned": true,
		# 续航型法系武器：法强 + 灵力恢复。与判官铁笔（法技增伤）、朱弦阵尺（纯法强）区分。
		"attributes": {
			AttributeDB.ATTR_SPELL_POWER: 10.0,
			AttributeDB.ATTR_MANA_REGEN: 0.15,
		},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_jingtan_chi.png",
		"weapon_visual": "weapon_jingtan_chi",
		"desc": "一柄薄如镜面的青银短尺，尺身里养着一小潭静水，握久了灵力自回。法强 +10，灵力恢复 +0.15/秒。",
	},
	{
		"equipment_id": "eq_shuiyue_pao",
		"equipment_name": "水月袍",
		"equipment_grade": "凡品",
		"equipment_type": "armor",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "元婴",
		"current_domain": "domain_04",
		"is_permanently_owned": true,
		# 法抗向护甲：气血 + 法抗 + 水抗；与烬纹（物抗/火抗）、劫灰（物法双抗）区分。
		"attributes": {
			AttributeDB.ATTR_HP_MAX: 24.0,
			AttributeDB.ATTR_MAGIC_RESIST: 5.0,
			"resist_water": 7.0,
		},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_shuiyue_pao.png",
		"desc": "袍面像一泓没有风的水，走动时衣褶里浮起月白的倒影。气血 +24，法抗 +5，水抗 +7。",
	},

	# ---------- 位面 04 · 执烛掉落（2026-11-02）----------
	# 用途差异：观澜给的是法术向（镜潭尺＝法强/回灵、水月袍＝法抗/水抗），
	# 本只补**物理游击向武器**与**雷抗缺口** —— 影系招式吃「跑位换射程」，
	# 所以这件武器给移速与精力上限，而不是再叠一遍力量。
	{
		"equipment_id": "eq_changye_ren",
		"equipment_name": "长夜刃",
		"equipment_grade": "凡品",
		"equipment_type": "weapon",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "元婴",
		"current_domain": "domain_04",
		"is_permanently_owned": true,
		# 游击向：力量 +26 / 移速 +3% / 精力上限 +1 格。
		# 与弯刀（纯力量）、清风剑（力量+回精）、劫锋（力量+攻速）、镜潭尺（法强+回灵）都不同档不同用途。
		"attributes": {
			AttributeDB.ATTR_STRENGTH: 26.0,
			AttributeDB.ATTR_SPEED_PCT: 3.0,
			AttributeDB.ATTR_STAMINA_MAX: 1.0,
		},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_changye_ren.png",
		"weapon_visual": "weapon_changye_ren",
		"desc": "一柄没有反光的黑刃，灯下挥起来只见影子不见刀。力量 +26，移速 +3%，精力上限 +1。",
	},
	{
		"equipment_id": "eq_zhului_zhui",
		"equipment_name": "烛泪坠",
		"equipment_grade": "凡品",
		"equipment_type": "accessory",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "元婴",
		"current_domain": "domain_04",
		"is_permanently_owned": true,
		# 补的是**雷抗**：全套装备里此前没有一件给雷抗（只有水/木/火/土），
		# 赫连霄与雷系功法密集的元婴档一直无处可堆。气血 + 物抗 + 雷抗，纯生存向。
		"attributes": {
			AttributeDB.ATTR_HP_MAX: 28.0,
			AttributeDB.ATTR_PHYSICAL_RESIST: 5.0,
			"resist_thunder": 8.0,
		},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_zhului_zhui.png",
		"desc": "一滴凝住的烛泪，里面压着一段不肯散的暗。气血 +28，物抗 +5，雷抗 +8。",
	},
	# 照影界第三位「叠纸」（2026-11-02）—— 两件都是**用途差**，不是数值档
	# 纸错剑：把普攻第三段变成「前后夹击」（现游戏所有普攻都只有一个落点）。
	# 折痕佩：把受击后的位移变成「折一下再出来」（现游戏所有位移都是直线冲刺）。
	# 属性刻意压低力量、往续航与生存偏，避免与长夜刃 / 镜潭尺 叠成同一把数字。
	{
		"equipment_id": "eq_zhicuo_jian",
		"equipment_name": "纸错剑",
		"equipment_grade": "凡品",
		"equipment_type": "weapon",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "元婴",
		"current_domain": "domain_04",
		"is_permanently_owned": true,
		"attributes": {
			AttributeDB.ATTR_STRENGTH: 12.0,
			AttributeDB.ATTR_ATTACK_SPEED: 5.0,
			AttributeDB.ATTR_STAMINA_REGEN: 0.5,
		},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_zhicuo_jian.png",
		"weapon_visual": "weapon_zhicuo_jian",
		"special_effect": "zhicuo_offset_swing",
		"desc": "一柄薄得像一页纸的剑，挥出去却在敌人身后先一步落下。力量 +12，攻速 +5%，精力恢复 +0.5。",
	},

	# ---------- 彩蛋武器：问天剑（练气区石台插剑，取走即永久消失）----------
	# 新手彩蛋：数值刻意压在清风剑（力量 20）之下、弯刀（8）之上 —— 它的价值是
	# 「大陆上有一把剑等你去拔」，不是强度。
	# ⚠ 三条禁令写在模板里，判定一律**按 id 回查模板**（ItemDB.has_equipment_flag）：
	#   `make_equipment_instance` 根本不会把这三个字段抄进实例（它只抄 grade/type/visual…），
	#   所以「读实例字段」的写法对这把剑永远是 false —— 老档、新档都同理。
	#   ⚠ 也别指望 `enhancement_limit: 0` 拦住强化：实例创建时它被统一写成
	#   ItemDB.MAX_ENHANCE（character_data.gd:917），真正的闸是 cannot_enhance。
	{
		"equipment_id": "eq_wentian_jian",
		"equipment_name": "问天剑",
		"equipment_grade": "凡品",
		"equipment_type": "weapon",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 0,
		"current_realm_limit": "练气",
		"current_domain": "domain_01",
		"is_permanently_owned": true,
		"cannot_discard": true,
		"cannot_dismantle": true,
		"cannot_enhance": true,
		"attributes": {
			AttributeDB.ATTR_STRENGTH: 10.0,
		},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_wentianjian.png",
		## 局内御剑形象：ArtDB.VISUALS 的 weapon_wentian_jian
		## （战斗图 assets/effects/weapons/wentian_jian.png，竖直、透明底、刃尖朝下）
		"weapon_visual": "weapon_wentian_jian",
		"desc": "青岚野石台上插着的那把剑，没人知道是谁留下的。力量 +10。传家之物 —— 不可丢弃、不可分解、不可强化。",
	},
	{
		"equipment_id": "eq_zhehen_pei",
		"equipment_name": "折痕佩",
		"equipment_grade": "凡品",
		"equipment_type": "accessory",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 5,
		"current_realm_limit": "元婴",
		"current_domain": "domain_04",
		"is_permanently_owned": true,
		# 纯生存：气血 + 双抗，不给任何攻击词条（用途差才是它的价值）。
		"attributes": {
			AttributeDB.ATTR_HP_MAX: 34.0,
			AttributeDB.ATTR_PHYSICAL_RESIST: 6.0,
			AttributeDB.ATTR_MAGIC_RESIST: 6.0,
		},
		"attack_bonus": 0.0,
		"icon": "res://assets/ui/icon/equip_zhehen_pei.png",
		"special_effect": "zhehen_fold_escape",
		"desc": "一段压平的纸痕，戴在身上挨打时脚下会自己折一下。气血 +34，物抗 +6，法抗 +6。",
	},
	# ---------- 开发者武器：房主神器（2026-11-13 用户定）----------
	# ⚠ 只在编辑器里的 F2 调试面板发放（DebugItemPanel 遍历模板表自动列出）。
	#   dev_only 标记 = 不进图鉴、不进试炼 BOSS 的兜底掉落，也不在任何掉表里。
	# ⚠ 不配美术：icon 留空，背包/挂签用「名字首字」占位。
	{
		"equipment_id": "eq_fangzhu_shenqi",
		"equipment_name": "房主神器",
		"equipment_grade": "神器/先天至宝",
		"equipment_type": "weapon",
		"equipment_level": 1,
		"enhancement_level": 0,
		"refinement_state": "未精炼",
		"enhancement_limit": 10,
		"current_realm_limit": "化神",
		"current_domain": "",
		"is_permanently_owned": true,
		"dev_only": true,
		"attributes": {
			AttributeDB.ATTR_STRENGTH: 9999999.0,
		},
		"attack_bonus": 0.0,
		"icon": "",
		"desc": "开发者武器：力量 +9999999。仅在编辑器里的 F2 调试面板发放。",
	},
]

# ===== 法宝模板 =====
## 2026-10-21：重新启用（此前按 2026-10-17 的要求清空过）。目前只有「召唤令」一类。
##
## 召唤字段（只有召唤类法宝填，缺字段 = 纯被动法宝）：
##   summon_boss_id      召唤谁（WorldDB 的 boss_id，决定用哪个 BOSS 场景与 AI）
##   summon_duration     持续秒数
##   summon_hp_ratio     召唤物血量 = 该 BOSS 基础血量 × 本比例
##   summon_damage_scale 召唤物伤害倍率（避免召唤物比玩家本体还猛）
##   summon_cooldown     两**场战斗**之间的冷却（按法宝记，跨战斗保留）
##
## 主动法宝字段：
##   active_type             "heal" = 每秒耗灵力回血；"haste" = 一次性耗灵力加速
##   active_cooldown         主动使用后的冷却秒数
##   heal：active_heal_per_sec / active_mana_per_sec / active_duration
##         ascend_heal_per_sec / ascend_duration（每次升阶成长）
##   haste：active_mana_cost / active_speed / active_duration
const TREASURE_TEMPLATES: Array = [
	{
		"treasure_id": "tr_huyao_ling",
		"treasure_name": "虎妖令",
		"treasure_grade": "法器",
		"icon": "res://assets/ui/icon/tr_huyao_ling.png",
		"desc": "以虎妖元魂熔入破损的虎皮袍而成。战斗中催动，唤来虎妖助战 20 秒。",
		"attributes": {},
		"summon_boss_id": "boss_huyao",
		"summon_duration": 20.0,
		"summon_hp_ratio": 0.5,
		"summon_damage_scale": 0.7,
		"summon_cooldown": 60.0,
	},
	{
		"treasure_id": "tr_daoke_ling",
		"treasure_name": "刀客令",
		"treasure_grade": "法器",
		"icon": "res://assets/ui/icon/tr_daoke_ling.png",
		"desc": "以刀客元魂熔入破损的弯刀而成。战斗中催动，唤来刀客助战 20 秒。",
		"attributes": {},
		"summon_boss_id": "boss_01",
		"summon_duration": 20.0,
		"summon_hp_ratio": 0.5,
		"summon_damage_scale": 0.7,
		"summon_cooldown": 60.0,
	},
	{
		"treasure_id": "tr_jianke_ling",
		"treasure_name": "剑客令",
		"treasure_grade": "法器",
		"icon": "res://assets/ui/icon/tr_jianke_ling.png",
		"desc": "以剑客元魂熔入破损的清风剑而成。战斗中催动，唤来剑客助战 20 秒。",
		"attributes": {},
		"summon_boss_id": "boss_01_c",
		"summon_duration": 20.0,
		"summon_hp_ratio": 0.5,
		"summon_damage_scale": 0.7,
		"summon_cooldown": 60.0,
	},
	{
		"treasure_id": "tr_liangyi_ling",
		"treasure_name": "两仪令",
		"treasure_grade": "法器",
		"icon": "res://assets/ui/icon/tr_liangyi_ling.png",
		"desc": "以两仪真人元魂熔入破损的两仪装备而成。战斗中催动，唤来两仪真人助战 20 秒。",
		"attributes": {},
		"summon_boss_id": "boss_02",
		"summon_duration": 20.0,
		"summon_hp_ratio": 0.5,
		"summon_damage_scale": 0.7,
		"summon_cooldown": 60.0,
	},
	{
		"treasure_id": "tr_zhenqi_ling",
		"treasure_name": "阵旗令",
		"treasure_grade": "法器",
		"icon": "res://assets/ui/icon/tr_zhenqi_ling.png",
		"desc": "以定阵先生元魂熔入破损的阵师装备而成。战斗中催动，唤来定阵先生助战 20 秒。",
		"attributes": {},
		"summon_boss_id": "boss_02_b",
		"summon_duration": 20.0,
		"summon_hp_ratio": 0.5,
		"summon_damage_scale": 0.7,
		"summon_cooldown": 60.0,
	},
	{
		"treasure_id": "tr_qi_ling",
		"treasure_name": "气君令",
		"treasure_grade": "法器",
		"icon": "res://assets/ui/icon/tr_qi_ling.png",
		"desc": "以太虚气君元魂熔入破损的气君装备而成。战斗中催动，唤来太虚气君助战 20 秒。",
		"attributes": {},
		"summon_boss_id": "boss_02_c",
		"summon_duration": 20.0,
		"summon_hp_ratio": 0.5,
		"summon_damage_scale": 0.7,
		"summon_cooldown": 60.0,
	},
	{
		"treasure_id": "tr_panguan_ling",
		"treasure_name": "判官令",
		"treasure_grade": "法器",
		"icon": "res://assets/ui/icon/tr_panguan_ling.png",
		"desc": "以赫连霄元魂熔入破损的判官装备而成。战斗中催动，唤来赫连霄助战 20 秒。",
		"attributes": {},
		"summon_boss_id": "boss_03",
		"summon_duration": 20.0,
		"summon_hp_ratio": 0.5,
		"summon_damage_scale": 0.7,
		"summon_cooldown": 60.0,
	},
	{
		"treasure_id": "tr_huozheng_ling",
		"treasure_name": "火正令",
		"treasure_grade": "法器",
		"icon": "res://assets/ui/icon/tr_huozheng_ling.png",
		"desc": "以离照元魂熔入破损的日纹装备而成。战斗中催动，唤来离照助战 20 秒。",
		"attributes": {},
		"summon_boss_id": "boss_03_b",
		"summon_duration": 20.0,
		"summon_hp_ratio": 0.5,
		"summon_damage_scale": 0.7,
		"summon_cooldown": 60.0,
	},
	{
		"treasure_id": "tr_jiezhu_ling",
		"treasure_name": "劫主令",
		"treasure_grade": "法器",
		"icon": "res://assets/ui/icon/tr_jiezhu_ling.png",
		"desc": "以晏无咎元魂熔入破损的劫纹装备而成。战斗中催动，唤来晏无咎助战 20 秒。",
		"attributes": {},
		"summon_boss_id": "boss_03_c",
		"summon_duration": 20.0,
		"summon_hp_ratio": 0.5,
		"summon_damage_scale": 0.7,
		"summon_cooldown": 60.0,
	},
	{
		"treasure_id": "tr_guanying_ling",
		"treasure_name": "镜主令",
		"treasure_grade": "法器",
		"icon": "res://assets/ui/icon/tr_guanying_ling.png",
		"desc": "以观澜元魂熔入破损的镜纹装备而成。战斗中催动，唤来观澜助战 20 秒。",
		"attributes": {},
		"summon_boss_id": "boss_04",
		"summon_duration": 20.0,
		"summon_hp_ratio": 0.5,
		"summon_damage_scale": 0.7,
		"summon_cooldown": 60.0,
	},
	{
		"treasure_id": "tr_zhizhu_ling",
		"treasure_name": "执烛令",
		"treasure_grade": "法器",
		"icon": "res://assets/ui/icon/tr_zhizhu_ling.png",
		"desc": "以执烛元魂熔入破损的执烛装备而成。战斗中催动，唤来执烛助战 20 秒 —— 它提着灯，替你把影子铺到敌人脚下。",
		"attributes": {},
		"summon_boss_id": "boss_04_b",
		"summon_duration": 20.0,
		"summon_hp_ratio": 0.5,
		"summon_damage_scale": 0.7,
		"summon_cooldown": 60.0,
	},
	{
		"treasure_id": "tr_diezhi_ling",
		"treasure_name": "叠纸令",
		"treasure_grade": "法器",
		"icon": "res://assets/ui/icon/tr_diezhi_ling.png",
		"desc": "以叠纸元魂熔入破损的纸纹装备而成。战斗中催动，唤来叠纸助战 20 秒 —— 它把战场折一下，你打的那一下会同时在对面落下。",
		"attributes": {},
		"summon_boss_id": "boss_04_c",
		"summon_duration": 20.0,
		"summon_hp_ratio": 0.5,
		"summon_damage_scale": 0.7,
		"summon_cooldown": 60.0,
	},
	# 位面 01 专属法宝（2026-11-07 新增）
	## 主动「换锋」：窗口内普攻三段改为远程直线穿透剑气，不依赖任何功法。
	## ⚠ 机制去重：不改伤害数值、不叠层、不留痕、不放置场地、不改写敌方状态，
	##   只替换玩家自己基础攻击的判定形状与表现。品阶用「法器」（低于后三位面的灵器）。
	{
		"treasure_id": "tr_blade_form",
		"treasure_name": "凡界·换锋符",
		"treasure_grade": "法器",
		"icon": "res://assets/ui/icon/tr_blade_form.png",
		"desc": "凡界专属法宝。集齐界门虎牙、凡铁断刃、清风剑屑三件材料合成。主动催动：短时间内把寻常挥砍化作可穿透的远行剑气；不依赖任何功法或位面机制。",
		"attributes": {},
		"active_type": "blade_form",
		"active_duration": 5.0,
		"active_cooldown": 22.0,
		"active_mana_cost": 15.0,
		## 剑气判定：沿朝向前方 320px、总宽 96px 的长条，逐只结算 = 穿透
		"active_range": 320.0,
		"active_width": 96.0,
		"ascend_duration": 1.0,
		"is_plane_treasure": true,
		"domain_id": "domain_01",
	},
	# 位面 02 专属法宝（2026-10-27 框架，2026-10-29 合成台接入）
	## 三件同一位面专属材料合成；合成入口在锻造台熔铸投入口，任意顺序自动识别。
	## 主动效果在 player.gd 的 active_type == "taiji_guard" 分支（太极护体：限时减伤）。
	{
		"treasure_id": "tr_taiji_pan",
		"treasure_name": "太极盘",
		"treasure_grade": "灵器",
		"icon": "res://assets/ui/icon/tr_taiji_pan.png",
		"desc": "冲和界专属法宝。集齐两仪玄石等三件专属材料合成。主动催动：太极护体 6 秒，受到的伤害 -30%；期间敌方飞行物近身会被太极接化，绕身一周后反打来源。",
		## 法宝不带属性词条（2026-11-01 用户定）：只靠进阶增强主动效果
		"attributes": {},
		"active_type": "taiji_guard",
		"active_duration": 6.0,
		"active_cooldown": 30.0,
		"active_mana_cost": 20.0,
		"active_damage_reduction": 0.3,
		## 每次进阶：护体 +0.5 秒、减伤 +1%
		"ascend_duration": 0.5,
		"ascend_reduction": 0.01,
		"is_plane_treasure": true,
		"domain_id": "domain_02",
	},
	# 位面 03 专属法宝（2026-10-29 首版，2026-10-31 改为通用型）
	## 主动「三炁环身」：风 / 火 / 雷三炁绕身轮转，对周围敌人造成元素伤害。
	## 主动效果在 player.gd 的 active_type == "tri_ring" 分支；不依赖任何 BOSS / 灾位机制。
	{
		"treasure_id": "tr_sanzai_lun",
		"treasure_name": "三元轮",
		"treasure_grade": "灵器",
		"icon": "res://assets/ui/icon/tr_sanzai_lun.png",
		"desc": "赤霄界专属法宝。集齐赤霄雷晶、赤霄日髓、赤霄劫灰三件材料合成。主动催动：风、火、雷三炁环绕身轮转，持续打击身周敌人；不依赖任何 BOSS 或灾位机制。",
		## 法宝不带属性词条（2026-11-01 用户定）：只靠进阶增强主动效果
		"attributes": {},
		"active_type": "tri_ring",
		"active_duration": 8.0,
		"active_cooldown": 40.0,
		"active_mana_cost": 20.0,
		## 2026-11-07 用户定：攻击范围翻倍（120→240）、脉冲间隔减半（2→1 秒）。
		## 判定半径同时驱动 SkillFx.tri_ring_pulse，特效大小与说明文案会自动跟随。
		"active_radius": 240.0,
		"active_interval": 1.0,
		"active_damage_ratio": 0.65,
		## 每次进阶：持续 +0.5 秒、元素倍率 +0.03
		"ascend_duration": 0.5,
		"ascend_damage_ratio": 0.03,
		"is_plane_treasure": true,
		"domain_id": "domain_03",
	},
	# 位面 04 专属法宝（2026-11-07 重制为「迟照符」，替换旧 fold_bridge 折痕机制）
	## 主动「迟照」：窗口内本该扣血的伤害不落地、记进待结池；期间用「完美闪避 /
	## 完美弹反 / 打断起手」抹掉池内固定比例；到期一次性结算剩余（若致死正常死亡）。
	## ⚠ 机制去重：不减伤（太极盘）、不替死（续命灯）、不反伤（棘甲佩）、不清 CD（血饲印），
	##   也不复读招式 / 放折痕 / 连两点（镜花 / 投影 / 叠纸三套功法）。它只改「结算时点」。
	## ⚠ 通用性自检：只读玩家自己的血量、计时器与操作回调，不读任何 BOSS / 关卡私有状态。
	{
		"treasure_id": "tr_zhaoying_zhefu",
		"treasure_name": "照影·迟照符",
		"treasure_grade": "灵器",
		"icon": "res://assets/ui/icon/tr_zhaoying_zhefu.png",
		"desc": "照影界专属法宝。集齐照影镜砂、照影烛泪、照影纸痕三件材料合成。主动催动：短暂时间内所受伤害暂不落地，以闪避、弹反与断招逐笔抹去，届时一并结算；不依赖任何 BOSS 或位面机制。",
		## 法宝不带属性词条（2026-11-01 用户定）：只靠进阶增强主动效果
		"attributes": {},
		"active_type": "delayed_reckoning",
		"active_duration": 4.0,
		"active_cooldown": 38.0,
		"active_mana_cost": 20.0,
		## 每次成功操作抹掉池内 30%，最多 3 次
		"active_wipe_pct": 0.30,
		"active_max_wipes": 3,
		## 每次进阶：窗口 +0.5 秒、抹除比例 +0.05
		"ascend_duration": 0.5,
		"ascend_wipe_pct": 0.05,
		"is_plane_treasure": true,
		"domain_id": "domain_04",
	},
	# 野外修士概率携带的主动法宝（2026-10-24 用户定）
	{
		"treasure_id": "tr_ningshuipei",
		"treasure_name": "凝水佩",
		"treasure_grade": "法器",
		"icon": "res://assets/ui/icon/equip_ningshuipei.png",
		"desc": "野修随身的水灵玉佩，催动时以灵力滋养气血。",
		"attributes": {},
		"active_type": "heal",
		"active_heal_per_sec": 5.0,
		"active_mana_per_sec": 10.0,
		"active_duration": 8.0,
		"active_cooldown": 20.0,
		"ascend_heal_per_sec": 1.0,
		"ascend_duration": 1.0,
	},
	{
		"treasure_id": "tr_zhudianhuan",
		"treasure_name": "逐电环",
		"treasure_grade": "法器",
		"icon": "res://assets/ui/icon/equip_zhudianhuan.png",
		"desc": "野修以雷击木与铜环炼成的法宝，催动时雷光覆体，身法骤增。",
		"attributes": {},
		"active_type": "haste",
		"active_mana_cost": 30.0,
		"active_speed": 800.0,
		"active_duration": 3.0,
		"active_cooldown": 30.0,
		## 每次进阶（品阶 +1）额外持续 0.5 秒
		"ascend_duration": 0.5,
	},
	# 野修法宝第二组（2026-11-01 用户定）：断念 / 禁步 / 续命 / 蚀甲
	## 断念铃：打断前摇并封技。玩家侧即时生效，野修侧摇铃 0.45 秒后判定。
	{
		"treasure_id": "tr_duannian_ling",
		"treasure_name": "断念铃",
		"treasure_grade": "法器",
		"icon": "res://assets/ui/icon/tr_duannian_ling.png",
		"desc": "野修从废祠里捡的裂口铜铃，铃舌缠着一缕枯发。摇响时封住对方术念，正在起手的招式会被打断。",
		"attributes": {},
		"active_type": "mind_lock",
		"active_mana_cost": 20.0,
		"active_cooldown": 35.0,
		"active_range": 300.0,
		"active_silence": 1.8,
		"active_refund": 10.0,
		"ascend_silence": 0.3,
		## 野修摇铃到判定之间的可读前摇；玩家侧即时生效
		"active_telegraph": 0.45,
	},
	## 禁步桩：先埋后触发的场地。0.8 秒后展开，圈内持续减速，展开瞬间定身。
	{
		"treasure_id": "tr_jinbu_zhuang",
		"treasure_name": "禁步桩",
		"treasure_grade": "法器",
		"icon": "res://assets/ui/icon/tr_jinbu_zhuang.png",
		"desc": "烧黑的桃木桩，桩身贴着歪歪扭扭的黄符。钉在目标脚下，0.8 秒后圈出一片禁步地。",
		"attributes": {},
		"active_type": "stake",
		"active_mana_cost": 15.0,
		"active_cooldown": 28.0,
		"active_range": 300.0,
		"active_radius": 110.0,
		"active_arm_time": 0.8,
		"active_duration": 4.0,
		"active_initial_slow": 1.5,
		"active_slow_mult": 0.65,
		"active_slow_refresh": 0.6,
		"ascend_initial_slow": 0.2,
	},
	## 续命灯：提前点灯，10 秒内第一次致死伤害改为保留 1 点气血。
	{
		"treasure_id": "tr_xuming_deng",
		"treasure_name": "续命灯",
		"treasure_grade": "法器",
		"icon": "res://assets/ui/icon/tr_xuming_deng.png",
		"desc": "缺了口的粗陶油灯，灯芯是野修自己剪下的一缕魂火。点亮后十息之内，替主人挡下一次致死。",
		"attributes": {},
		"active_type": "lamp",
		"active_mana_cost": 25.0,
		"active_cooldown": 60.0,
		"active_duration": 10.0,
		"active_heal_ratio": 0.15,
		"active_invuln": 0.8,
		"active_knockback_radius": 200.0,
		"ascend_heal_ratio": 0.01,
		## 野修血量低于这个比例才点灯
		"active_trigger_hp_ratio": 0.4,
	},
	## 蚀甲锥：破护体。+12% 受伤固定；进阶延长持续时间（避免 debuff 表出现六个同名条目）。
	{
		"treasure_id": "tr_shixi_zhui",
		"treasure_name": "蚀甲锥",
		"treasure_grade": "法器",
		"icon": "res://assets/ui/icon/tr_shixi_zhui.png",
		"desc": "妖兽獠牙磨成的锥子，尖上淬过尸水。钉中后蚀开护体，短时间内对方更易受伤。",
		"attributes": {},
		"active_type": "corrode",
		"active_mana_cost": 15.0,
		"active_cooldown": 30.0,
		"active_range": 400.0,
		"active_speed": 900.0,
		"active_debuff_time": 8.0,
		"active_damage_bonus": 0.12,
		"active_guard_shred": 0.5,
		"ascend_duration": 0.5,
	},
	# 野修法宝第三组（2026-11-01 用户定）：血饲 / 换位 / 棘甲 / 回风
	## 血饲印：以血换功法冷却。法宝不带词条，进阶只加灵力回复。
	{
		"treasure_id": "tr_xuesi_yin",
		"treasure_name": "血饲印",
		"treasure_grade": "法器",
		"icon": "res://assets/ui/icon/tr_xuesi_yin.png",
		"desc": "粗石方印，印面刻「饲」字，边角被血浸黑。以自身精血催动，重续功法。",
		"attributes": {},
		"active_type": "blood_seal",
		"active_mana_cost": 0.0,
		"active_cooldown": 60.0,
		"active_hp_ratio": 0.15,
		"active_min_hp_ratio": 0.25,
		"active_mana_restore": 0.30,
		"ascend_mana_restore": 0.03,
	},
	## 换位玦：与目标互换位置；法宝不带词条，进阶加落地无敌。
	{
		"treasure_id": "tr_huanwei_jue",
		"treasure_name": "换位玦",
		"treasure_grade": "法器",
		"icon": "res://assets/ui/icon/tr_huanwei_jue.png",
		"desc": "断了一角的青玉玦，系着两色绳。催动时与目标换位，落地时短暂无形。",
		"attributes": {},
		"active_type": "swap",
		"active_mana_cost": 20.0,
		"active_cooldown": 45.0,
		"active_range": 360.0,
		"active_invuln": 0.4,
		"ascend_invuln": 0.1,
	},
	## 棘甲佩：近战反伤；法宝不带词条，进阶加反弹比例。
	{
		"treasure_id": "tr_jijia_pei",
		"treasure_name": "棘甲佩",
		"treasure_grade": "法器",
		"icon": "res://assets/ui/icon/tr_jijia_pei.png",
		"desc": "生满黑色棘刺的骨佩。催动后棘刺竖起，近身伤我者先伤己。",
		"attributes": {},
		"active_type": "thorns",
		"active_mana_cost": 15.0,
		"active_cooldown": 35.0,
		"active_duration": 4.0,
		"active_reflect_ratio": 0.30,
		"ascend_reflect_ratio": 0.03,
	},
	## 回风袋：把身周敌人推开；法宝不带词条，进阶加推距。
	{
		"treasure_id": "tr_huifeng_dai",
		"treasure_name": "回风袋",
		"treasure_grade": "法器",
		"icon": "res://assets/ui/icon/tr_huifeng_dai.png",
		"desc": "旧皮袋，袋口用麻绳扎着，鼓着一袋回风。开袋时把近身者送出去。",
		"attributes": {},
		"active_type": "gust",
		"active_mana_cost": 15.0,
		"active_cooldown": 30.0,
		"active_radius": 220.0,
		"active_push": 240.0,
		"ascend_push": 20.0,
	},
]

# ===== 装备合成台配方（2026-10-21 用户定）=====
## 每个 BOSS 一条：**元魂** + 该 BOSS 掉落的**任意一件已破损装备** → 召唤法宝。
## 合成台第三个格子留空即可（配方只吃两样），故这里不登记第三个材料。
const SYNTH_RECIPES: Array = [
	{"recipe_id": "synth_huyao_ling", "boss_id": "boss_huyao", "soul_id": "soul_huyao", "result_id": "tr_huyao_ling"},
	{"recipe_id": "synth_daoke_ling", "boss_id": "boss_01", "soul_id": "soul_daoke", "result_id": "tr_daoke_ling"},
	{"recipe_id": "synth_jianke_ling", "boss_id": "boss_01_c", "soul_id": "soul_jianke", "result_id": "tr_jianke_ling"},
	{"recipe_id": "synth_liangyi_ling", "boss_id": "boss_02", "soul_id": "soul_liangyi", "result_id": "tr_liangyi_ling"},
	{"recipe_id": "synth_zhenqi_ling", "boss_id": "boss_02_b", "soul_id": "soul_dingzhen", "result_id": "tr_zhenqi_ling"},
	{"recipe_id": "synth_qi_ling", "boss_id": "boss_02_c", "soul_id": "soul_qi", "result_id": "tr_qi_ling"},
	{"recipe_id": "synth_panguan_ling", "boss_id": "boss_03", "soul_id": "soul_helianxiao", "result_id": "tr_panguan_ling"},
	{"recipe_id": "synth_huozheng_ling", "boss_id": "boss_03_b", "soul_id": "soul_lizhao", "result_id": "tr_huozheng_ling"},
	{"recipe_id": "synth_jiezhu_ling", "boss_id": "boss_03_c", "soul_id": "soul_yanwujiu", "result_id": "tr_jiezhu_ling"},
	{"recipe_id": "synth_jingzhu_ling", "boss_id": "boss_04", "soul_id": "soul_guanying", "result_id": "tr_guanying_ling"},
	{"recipe_id": "synth_zhizhu_ling", "boss_id": "boss_04_b", "soul_id": "soul_zhizhu", "result_id": "tr_zhizhu_ling"},
	{"recipe_id": "synth_diezhi_ling", "boss_id": "boss_04_c", "soul_id": "soul_diezhi", "result_id": "tr_diezhi_ling"},
]

# ===== 位面专属法宝配方（2026-10-27 框架，2026-10-29 接入合成台）=====
## 规则（用户 2026-10-27 定，2026-11-07 扩展到凡界）：每个位面的三只 BOSS 各掉一件专属材料，
##   集齐同一位面的三件材料，合成一件该位面专属法宝。原为「从位面 02 起」，本日起含 domain_01。
## ⚠ 合成入口在锻造台「熔铸」页：三件材料任意顺序放入三个投入口，自动识别配方，产物直接入包；
##   与「元魂 + 破损装备」的召唤法宝是两套配方，不能混投。
const PLANE_TREASURE_RECIPES: Array = [
	{
		"domain_id": "domain_01",
		"result_id": "tr_blade_form",
		"material_ids": ["mat_fanjie_huya", "mat_fanjie_duanren", "mat_fanjie_jianxie"],
		"required_count": 3,
	},
	{
		"domain_id": "domain_02",
		"result_id": "tr_taiji_pan",
		"material_ids": ["mat_liangyi_xuanshi", "mat_zhusha_zhending", "mat_taixu_qijing"],
		"required_count": 3,
	},
	{
		"domain_id": "domain_03",
		"result_id": "tr_sanzai_lun",
		"material_ids": ["mat_chixiao_leijing", "mat_chixiao_risui", "mat_chixiao_jiehui"],
		"required_count": 3,
	},
	{
		"domain_id": "domain_04",
		"result_id": "tr_zhaoying_zhefu",
		"material_ids": ["mat_zhaoying_jingsha", "mat_zhaoying_zhulei", "mat_zhaoying_zhihen"],
		"required_count": 3,
	},
]


## 某位面的专属法宝配方（未登记返回空字典）
static func get_plane_treasure_recipe(domain_id: String) -> Dictionary:
	for r in PLANE_TREASURE_RECIPES:
		if String((r as Dictionary).get("domain_id", "")) == domain_id:
			return r
	return {}


# ===== 合成指引（2026-11-09 用户要求：材料介绍里要写清「去哪合成」）=====
## ⚠ 不写进 MATERIALS 的 desc：desc 是风味文本，配方一改就会变成假信息
##   （换了材料或改了配方，旧描述里还写着上一个名字）。这里一律按配方表**反查现算**，
##   改配方时指引自动跟着变，不用回来同步二十多条描述。
## 返回 0~1 行指引；不是合成材料就返回空数组，调用方据此决定要不要显示。
static func synth_hint_lines(item_id: String) -> Array:
	var out: Array = []
	if item_id == "":
		return out
	# 玩家在大世界看到的是设施名「装备锻造台」，面板内页签叫「熔铸」—— 两个词都要给
	# 出来，否则玩家进了锻造工坊还会去找第三个按钮。
	# ⚠ 长度是算过的：角色面板详情框是**固定 146px**（用户 2026-10-24 定，防止点装备时
	#   把背包格子压扁），字号 13 一行只放得下约 40 个全角字，多出来的第二行在滚动区外
	#   —— 玩家不滚就看不见。所以「主城」「页」都省掉，也不逐个列另外两件的名字
	#   （那些在熔铸页的候选列表里本来就有），只保证「地点 + 怎么投 + 产物」一行说完。
	var here := "「装备锻造台」→「熔铸」"
	# ① 元魂：与同源破损装备一起召唤法宝
	for raw in SYNTH_RECIPES:
		var soul_rec := raw as Dictionary
		if String(soul_rec.get("soul_id", "")) != item_id:
			continue
		var soul_tpl := get_treasure_template(String(soul_rec.get("result_id", "")))
		out.append("合成指引：%s，与同源破损装备同投，召唤「%s」"
			% [here, String(soul_tpl.get("treasure_name", "法宝"))])
	# ② 位面专属材料：同界三件合成该位面法宝
	for raw in PLANE_TREASURE_RECIPES:
		var plane_rec := raw as Dictionary
		var mats: Array = plane_rec.get("material_ids", [])
		if not mats.has(item_id):
			continue
		var plane_tpl := get_treasure_template(String(plane_rec.get("result_id", "")))
		out.append("合成指引：%s，集齐同界三件材料同投，合成「%s」"
			% [here, String(plane_tpl.get("treasure_name", "法宝"))])
	# ③ 破境残晶（地髓 / 天髓）：同一页熔成完整晶。产物是突破材料、不是法宝，
	#    但它和法宝共用同一个熔铸页，玩家拿到手一样会问「这俩放哪」。
	for realm in POJING_SYNTH_RECIPES.keys():
		var pj: Dictionary = POJING_SYNTH_RECIPES[realm]
		var other := ""
		if String(pj.get("di", "")) == item_id:
			other = "天髓"
		elif String(pj.get("tian", "")) == item_id:
			other = "地髓"
		else:
			continue
		out.append("合成指引：%s，与%s同投，熔成「%s破境晶」"
			% [here, other, String(realm)])
	# ⚠ 这里用收集而不是命中即 return：将来一件材料若同时属于两张配方表
	#   （例如既进位面法宝又可熔晶），return 会把后一条静默吞掉。
	return out


# ===== 非装备类剧情道具（§5.2 之外的物品）=====
## 万界锚点戒指：任务书中的「时空至宝」，是推动剧情的信物，
## 不是可穿戴的游戏内装备，因此不登记进 EQUIPMENT_TEMPLATES。
## 单独成表是为了让任务/剧情系统能按 id 取到它的名称与描述，
## 同时天然排除在「装备锻造台」与「装备掉落表」之外。
const STORY_ITEMS: Array = [
	{
		"item_id": "item_wanjie_anchor_ring",
		"item_name": "万界锚点戒指",
		"item_type": "story",
		"icon": "",
		"desc": "挚友家族世代守护的时空至宝，是穿行万界的信物。",
	},
]

# ===== 战斗系数（§2.10 功法 / 装备加成推导口径）=====
## 主角「裸装攻击力」：与角色数据 CharacterData.base_attack 绑定。
## 校准口径：基础攻击 12 × 兵器系数 1.0 = 12，与阶段1 实测伤害一致，
## 因此接入攻击力公式后裸装手感不变。
const CHARACTER_ATTACK := 12.0

## 兵器系数：空手 / 兵器 / 兵器外的装备部位
const WEAPON_COEFF := 1.0        # 徒手与兵器皆是 1.0（徒手时「徒手」即是攻击手段）
const NON_WEAPON_COEFF := 1.0    # 护甲与饰品不参与物理攻击（预留减伤乘区）

## 功法技能系数：无功法时为 1.0；习得主动 / 被动功法后按功法伤害倍率相乘
const SKILL_DAMAGE_COEFF := 1.0

## 招式层系数（与 player.gd 的常量保持一致）
const FINISHER_COEFF := 1.8      # 连击第三段·终结技
## 弹刀增伤 buff：**次数型**，下一次近战伤害 ×1.5，命中后消费，不累计
## （用户 2026-10-17 改定：取代旧版「弹反追击首段 ×2」，且同时覆盖普攻与近战物理功法）
const PARRY_DAMAGE_BUFF_COEFF := 1.5
const RANDOM_MIN := 0.95         # 随机浮动上下限（其他因素）
const RANDOM_MAX := 1.05


# ===== 强化系统（§2.6 装备永不淘汰 / 可强化培养）=====
## 规则概览（2026-10-17 用户改版）：
##   - 每敲击一次消耗「锻造晶石」，数量按品阶递增（凡品 1 / 法器 2 / 灵器 3 …）
##   - **强化成功不再加固定攻击力**，改为「随机选面板上的一个属性，在其专属区间内随机 +N」
##     （区间见 AttributeDB.ENHANCE_RANGE，按词条量纲分别设定）
##   - 成功 80% / 大成功 5%（连升两级，同一属性取两次区间上限）/ 失败 20%
##   - **失败不掉等级、不掉属性**，只累加该装备的「磨损」；累计 ENHANCE_FAIL_LIMIT 次即**破损**
##   - 强化等级上限 MAX_ENHANCE(=10)；满级后再敲击即「进阶敲击」（品阶 +1、等级归 0）
##   - 破损后仍可穿戴，但**强化永久停止**；可在锻造台「分解」，返还累计消耗晶石的一半

## 强化等级上限：+10（仅作进度与满级门槛，不再换算攻击力）
const MAX_ENHANCE := 10
## 每次敲击的基础成功率
const ENHANCE_SUCCESS_RATE := 0.80
## 大成功率（整体 5%）
const ENHANCE_GREAT_RATE := 0.05
## 大成功时「升两级」→ 属性连续提升两次（每次取区间上限）
const ENHANCE_GREAT_STEP := 2
## 失败扣几级（2026-10-17 起不再扣等级，此常量仅留档）
const ENHANCE_FAIL_STEP := 0
## 累计失败多少次后装备「破损」（破损 = 强化永久停止，可分解返还一半晶石）
const ENHANCE_FAIL_LIMIT := 10
## 分解返还比例：累计消耗晶石的一半（向下取整，至少 0）
const DISMANTLE_REFUND_RATIO := 0.5

## 攻击力口径（2026-10-17 起）：强化与品阶**不再叠加任何固定攻击力**，
## 只保留模板自带的基础值（当前所有模板均为 0）——
## 装备的强度完全由 attributes（面板属性）决定，而强化正是去提升那些属性。
const ENHANCE_ATTACK_PER_LEVEL := 0.0     # 已停用（保留常量避免旧引用报错）
const GRADE_ATTACK_PER_TIER := 0.0        # 已停用（保留常量避免旧引用报错）

## 强化结果枚举（供 UI 与飘字分支使用）
const ENHANCE_RESULT_FAIL := "fail"           # 普通失败：不掉等级，只 +1 磨损
const ENHANCE_RESULT_SUCCESS := "success"     # 成功：随机属性 +N，等级 +1
const ENHANCE_RESULT_GREAT := "great"         # 大成功：同一属性取两次区间上限，等级 +2
const ENHANCE_RESULT_ASCEND := "ascend"       # 进阶成功：品阶 +1，等级归 0
const ENHANCE_RESULT_ASCEND_FAIL := "ascend_fail"  # 进阶失败：等级清零、品阶不变，并计 1 道磨损（法宝不计）
const ENHANCE_RESULT_BROKEN := "broken"       # 失败累计到上限：装备破损，强化永久停止


## 品阶序号（0 起）；未知品阶返回 -1
static func grade_index(grade: String) -> int:
	return CharacterData.EQUIPMENT_GRADES.find(grade)


## 品阶等级上限（最高阶不可再进阶）
static func is_max_grade(grade: String) -> bool:
	return grade_index(grade) >= CharacterData.EQUIPMENT_GRADES.size() - 1


## 升一阶后的品阶名；已是最高阶则原样返回
static func next_grade(grade: String) -> String:
	var i := grade_index(grade)
	if i < 0 or i >= CharacterData.EQUIPMENT_GRADES.size() - 1:
		return grade
	return CharacterData.EQUIPMENT_GRADES[i + 1]


## 强化一次需要的锻造晶石：按品阶递增（2026-10-24 用户定）
## 凡品 1 / 法器 2 / 灵器 3 / 宝器 4 / 道器 5 / 仙器 6 / 神器（先天至宝） 7
## 未知品阶按凡品 1 处理，避免坏档导致无法强化。
static func enhance_crystal_cost(item: Dictionary) -> int:
	var gi := grade_index(String(item.get("equipment_grade", "")))
	return maxi(1, gi + 1)


# ===== 境界锁（2026-10-24 用户定）=====
## 玩家境界 → 该境界下装备 / 法宝**允许强化到的最高品阶**。
## 例：练气只能到「法器」（绿），突破筑基后才能继续进阶到「灵器」（蓝）。
## ⚠ 用户选「全部锁死」：到达上限品阶后整件装备都不能再敲（不是只锁进阶）。
const REALM_GRADE_CAP: Dictionary = {
	"练气": "法器",
	"筑基": "灵器",
	"结丹": "宝器",
	"元婴": "道器",
	"化神": "仙器",
}


## 该境界允许的最高品阶（未登记返回空串 = 不设锁）
static func realm_grade_cap(realm: String) -> String:
	return String(REALM_GRADE_CAP.get(CharacterData.normalize_realm_name(realm), ""))


## 下一个境界名（已是最高境界返回空串）
static func next_realm_name(realm: String) -> String:
	var normalized := CharacterData.normalize_realm_name(realm)
	var i := CharacterData.REALM_ORDER.find(normalized)
	if i < 0 or i + 1 >= CharacterData.REALM_ORDER.size():
		return ""
	return CharacterData.REALM_ORDER[i + 1]


## 境界锁提示：该品阶在当前境界下已封顶时返回原因，否则空串
## 品阶高于上限（旧档 / 降境）也一并锁住，提示同一个突破方向。
static func realm_lock_message(grade: String, realm: String) -> String:
	var cap := realm_grade_cap(realm)
	if cap == "":
		return ""
	if grade_index(grade) < grade_index(cap):
		return ""
	var normalized := CharacterData.normalize_realm_name(realm)
	var next_realm := next_realm_name(normalized)
	if next_realm != "":
		return "境界锁：%s期最多强化到「%s」，需突破至「%s」后才能继续" % [
			normalized, cap, next_realm]
	return "境界锁：%s期最多强化到「%s」，已达当前境界上限" % [normalized, cap]


## 单件装备的攻击力加成（唯一口径，UI / 战斗 / 存档都读它）
## = 基础攻击力(装备自身 attack_bonus_base) + 品阶加成 + 强化加成
static func compute_attack_bonus(item: Dictionary) -> float:
	var base := float(item.get("attack_bonus_base", item.get("attack_bonus", 0.0)))
	var gi := grade_index(String(item.get("equipment_grade", "")))
	if gi < 0:
		gi = 0
	var enh := maxi(0, int(item.get("enhancement_level", 0)))
	return base + float(gi) * GRADE_ATTACK_PER_TIER + float(enh) * ENHANCE_ATTACK_PER_LEVEL


## 强化描述文本，如「强化 +3 / 10」
static func enhance_text(item: Dictionary) -> String:
	# 法宝没有普通强化等级，只有进阶（2026-11-01 用户定）
	if String(item.get("equipment_type", "")) == "treasure":
		return "可进阶"
	return "+%d / %d" % [maxi(0, int(item.get("enhancement_level", 0))), MAX_ENHANCE]


## 磨损进度文本，如「磨损 3 / 10」；已破损返回「已破损」
static func wear_text(item: Dictionary) -> String:
	if String(item.get("equipment_type", "")) == "treasure":
		return "无磨损"
	if bool(item.get("is_broken", false)):
		return "已破损"
	return "磨损 %d / %d" % [mini(ENHANCE_FAIL_LIMIT, maxi(0, int(item.get("enhance_fail_count", 0)))), ENHANCE_FAIL_LIMIT]


## 该装备能否再强化（破损 = 强化永久停止，但仍可穿戴）
static func can_enhance(item: Dictionary) -> bool:
	return not bool(item.get("is_broken", false))


## 分解可返还的晶石数 = 累计消耗的一半（向下取整）
static func dismantle_refund(item: Dictionary) -> int:
	# 自身强化砸进去的晶石
	var spent := maxi(0, int(item.get("enhance_crystal_spent", 0)))
	# 召唤法宝：合成时熔掉的那件破损装备也花过晶石（2026-10-21 用户定：这笔同样返一半）
	spent += maxi(0, int(item.get("synth_crystal_spent", 0)))
	return int(floor(float(spent) * DISMANTLE_REFUND_RATIO))


## 装备完整显示名：名字 + 强化后缀（+N），如「弯刀 +3」
## 名字本身不含品阶前缀，品阶是独立字段，仅在 UI 单独着色展示。
static func equipped_display_name(item: Dictionary) -> String:
	var n := String(item.get("name", item.get("equipment_name", "未知装备")))
	var enh := maxi(0, int(item.get("enhancement_level", 0)))
	return n if enh <= 0 else "%s +%d" % [n, enh]


# ===== 掉落表（按 BOSS 登记）=====
## 结构：boss_id → [{ item_id(装备模板 id), chance(0~1，可省略), count }]
## 掉落物会在战斗场景里生成可拾取节点，拾取后进入随身背包。
##
## 普通 BOSS 的掉率统一取 COMMON_DROP_CHANCE；
## 条目里省略 chance 即用该默认值，需要特殊掉率（如稀有 BOSS）时再显式覆盖。
const COMMON_DROP_CHANCE := 0.5

## boss_id → 掉落条目
## 未写 chance → 采用普通 BOSS 默认掉率（50%，见 COMMON_DROP_CHANCE）
const DROP_TEMPLATES := {
	# 虎妖（凡界第 1 位）：虎皮袍 + 虎牙项链
	"boss_huyao": [
		{"item_id": "eq_hupipao", "count": 1},
		{"item_id": "eq_huyaxianglian", "count": 1},
		{"item_id": "mat_fanjie_huya", "count": 1, "chance": 0.2, "kind": "material"},
	],
	# 刀客（凡界第 2 位）：弯刀
	"boss_01": [
		{"item_id": "eq_fanpinwandao", "count": 1},
		{"item_id": "mat_fanjie_duanren", "count": 1, "chance": 0.2, "kind": "material"},
	],
	# 剑客（凡界第 3 位）：清风剑 + 清风鞋
	"boss_01_c": [
		{"item_id": "eq_qingfengjian", "count": 1},
		{"item_id": "eq_qingfengxie", "count": 1},
		{"item_id": "mat_fanjie_jianxie", "count": 1, "chance": 0.2, "kind": "material"},
	],
	# 两仪真人（位面 02 第 1 位）：混伤饰品 + 法抗护甲 + 位面专属材料
	# 专属材料 **20%** 掉落（2026-10-28 用户定，原为 100%：每个位面的三只 BOSS 各掉一件）；
	# 装备仍走 50% 默认。⚠ 太极盘要 3 件材料，期望击杀数从 3 次抬到约 15 次 —— 后续调价请先对齐这一点。
	"boss_02": [
		{"item_id": "eq_liangyi_yujue", "count": 1},
		{"item_id": "eq_xuansu_daopao", "count": 1},
		{"item_id": "mat_liangyi_xuanshi", "count": 1, "chance": 0.2, "kind": "material"},
	],
	# 太虚气君（冲和界第 3 位）：回灵鞋 + 法强玉坠 + 位面专属材料
	"boss_02_c": [
		{"item_id": "eq_taixu_yunlv", "count": 1},
		{"item_id": "eq_qihai_yuzhui", "count": 1},
		{"item_id": "mat_taixu_qijing", "count": 1, "chance": 0.2, "kind": "material"},
	],
	# 定阵先生（冲和界第 2 位）：法系兵器 + 续航饰品 + 位面专属材料
	"boss_02_b": [
		{"item_id": "eq_zhuxian_chizhang", "count": 1},
		{"item_id": "eq_dingzhen_chanwan", "count": 1},
		{"item_id": "mat_zhusha_zhending", "count": 1, "chance": 0.2, "kind": "material"},
	],
	# 赫连霄（赤霄界第 1 位）：攻速饰品 + 法技增伤武器 + 位面专属材料
	"boss_03": [
		{"item_id": "eq_leiwen_huqi", "count": 1},
		{"item_id": "eq_panguan_tiebi", "count": 1},
		{"item_id": "mat_chixiao_leijing", "count": 1, "chance": 0.2, "kind": "material"},
	],
	# 离照（赤霄界第 2 位）：物理护甲 + 精力鞋 + 位面专属材料
	"boss_03_b": [
		{"item_id": "eq_jinwen_zhanpao", "count": 1},
		{"item_id": "eq_zhuri_lv", "count": 1},
		{"item_id": "mat_chixiao_risui", "count": 1, "chance": 0.2, "kind": "material"},
	],
	# 晏无咎（赤霄界第 3 位 · 位面终章）：纯输出武器 + 物法双抗护甲 + 位面专属材料
	"boss_03_c": [
		{"item_id": "eq_jiefeng", "count": 1},
		{"item_id": "eq_jiehui_fayi", "count": 1},
		{"item_id": "mat_chixiao_jiehui", "count": 1, "chance": 0.2, "kind": "material"},
	],
	# 观澜（照影界第 1 位）：回灵法器 + 法抗水抗护甲 + 位面专属材料
	"boss_04": [
		{"item_id": "eq_jingtan_chi", "count": 1},
		{"item_id": "eq_shuiyue_pao", "count": 1},
		{"item_id": "mat_zhaoying_jingsha", "count": 1, "chance": 0.2, "kind": "material"},
	],
	# 执烛（照影界第 2 位）：物理游击武器 + 雷抗生存饰品 + 位面专属材料
	"boss_04_b": [
		{"item_id": "eq_changye_ren", "count": 1},
		{"item_id": "eq_zhului_zhui", "count": 1},
		{"item_id": "mat_zhaoying_zhulei", "count": 1, "chance": 0.2, "kind": "material"},
	],
	# 叠纸（照影界第 3 位）：前后夹击武器 + 受击折位饰品 + 位面专属材料（三件合璧开位面法宝）
	"boss_04_c": [
		{"item_id": "eq_zhicuo_jian", "count": 1},
		{"item_id": "eq_zhehen_pei", "count": 1},
		{"item_id": "mat_zhaoying_zhihen", "count": 1, "chance": 0.2, "kind": "material"},
	],
}


# ===== 万界塔掉落（按塔层登记）=====
## 塔内投影**必掉**「锻造晶石」——它是装备强化的唯一媒介（塔是唯一产出源）。
## 结构：floor → [{ item_id(材料 id), chance(可省略), count }]
##   - chance 省略时走 COMMON_DROP_CHANCE；这里显式写 1.0 = **必定掉落**
##   - count = 在地上掉落几块，roll_tower_drops 会拆成 count 个独立掉落物，
##     玩家必须逐块走近按 F 拾取（不会自动进背包）
## 与位面掉落分开登记，因为投影复用了本体的 boss_id，靠 boss_id 无法区分来源。
## 每层**默认**掉落：锻造晶石（必掉，拆成多块要自己走过去捡）
## 塔现在有 11 层（3 位面 × 3 BOSS + 照影界前两位），逐层登记太啰嗦，所以改成「默认 + 可按层覆盖」。
const TOWER_FLOOR_DROPS_DEFAULT := [
	{"item_id": "mat_duanzaojingshi", "count": 3, "chance": 1.0},
]
## 万界塔 BOSS 额外 5% 掉蕴仙髓（2026-11-13 用户定）；区域核心重战不参与，
## 所以单独做一个掷骰函数，不挂进 TOWER_FLOOR_DROPS_DEFAULT（那张表会被核心重战复用）。
const TOWER_YUNXIAN_DROP_CHANCE := 0.05
## 塔层双倍血量场次的 BOSS 元魂掉率（2026-10-21 用户定；面板也要显示，挪到数据层做唯一来源）
const TOWER_SOUL_DROP_CHANCE := 0.5
## 想给某一层特殊掉落时在这里覆盖（键 = 层号）
const TOWER_DROP_TEMPLATES := {}

## 晶石数量按「第几次通关」浮动（2026-10-17 用户定）：
##   首通 9 块 → 第二次 6 块 → 第三次及以后固定 3 块
## 表里没列出的次数一律走 TOWER_CRYSTAL_REPEAT。
const TOWER_CRYSTAL_BY_CLEAR := {1: 9, 2: 6}
const TOWER_CRYSTAL_REPEAT := 3


## 第 N 次通关给多少块锻造晶石
static func tower_crystal_count(clear_index: int) -> int:
	return int(TOWER_CRYSTAL_BY_CLEAR.get(clear_index, TOWER_CRYSTAL_REPEAT))


# ===== 查询工具 =====

## 某 BOSS 的掉落表（未登记返回空数组）
static func get_drops_for_boss(boss_id: String) -> Array:
	return DROP_TEMPLATES.get(boss_id, [])


## 取某条掉落条目的实际掉率：显式写了 chance 就用它，否则用普通 BOSS 默认掉率
static func get_drop_chance(entry: Dictionary) -> float:
	if entry.has("chance"):
		return clampf(float(entry.get("chance", COMMON_DROP_CHANCE)), 0.0, 1.0)
	return COMMON_DROP_CHANCE


## 判定掉落：返回本局实际掉落到的物品列表
## 结构：[{ "type": CharacterData.ITEM_EQUIPMENT, "template_id": ..., "item": {...}, "count": n }]
static func roll_boss_drops(boss_id: String) -> Array:
	var out: Array = []
	for entry in get_drops_for_boss(boss_id):
		var chance := get_drop_chance(entry)
		# randf() ∈ [0,1)；chance=0 恒不掉，chance=1 恒掉
		if randf() >= chance:
			continue
		var tpl_id := String(entry.get("item_id", ""))
		# 位面专属材料：与塔掉落同结构（材料条目直接走 make_material_drop）
		if String(entry.get("kind", "equipment")) == "material":
			var mat_drop := make_material_drop(tpl_id)
			if mat_drop.is_empty():
				push_warning("掉落表登记了未知材料：" + tpl_id)
				continue
			var mat_count: int = maxi(1, int(entry.get("count", 1)))
			mat_drop["count"] = mat_count
			# ⚠ 拾取走 pickup.item = d["item"]（读 item.count），结算文案读顶层 count：
			#   两层必须同步，否则把配置的 count 调成 >1 时实得恒 1、文案却显示多件
			var mat_item: Dictionary = mat_drop.get("item", {})
			mat_item["count"] = mat_count
			mat_drop["item"] = mat_item
			out.append(mat_drop)
			continue
		var tpl := get_equipment_template(tpl_id)
		if tpl.is_empty():
			push_warning("掉落表登记了未知装备模板：" + tpl_id)
			continue
		out.append({
			"type": CharacterData.ITEM_EQUIPMENT,
			"template_id": tpl_id,
			"item": CharacterData.make_equipment_instance(tpl),
			"count": maxi(1, int(entry.get("count", 1))),
		})
	return out


## 掉落描述文本（用于战斗结算提示），如「掉落：弯刀」
## 按「名称 + 物品 id」聚合数量：塔掉落已拆成每块一条，不聚合会显示成
## 「锻造晶石、锻造晶石、锻造晶石」，所以这里统一合并成「锻造晶石 ×3」
static func drops_text(drops: Array) -> String:
	if drops.is_empty():
		return ""
	var order: Array[String] = []
	var totals: Dictionary = {}
	for d in drops:
		var item: Dictionary = d.get("item", {})
		var n := String(item.get("name", "未知物品"))
		var key := "%s|%s" % [n, String(item.get("id", ""))]
		if not totals.has(key):
			order.append(key)
			totals[key] = [n, 0]
		var pair: Array = totals[key]
		pair[1] = int(pair[1]) + maxi(1, int(d.get("count", 1)))

	var parts: Array[String] = []
	for key in order:
		var pair: Array = totals[key]
		var n := String(pair[0])
		var c := int(pair[1])
		parts.append(n if c <= 1 else "%s ×%d" % [n, c])
	return "掉落：" + "、".join(parts)


# ===== 万界塔掉落判定 =====

## 某塔层的掉落表（未登记返回空数组）
## 某塔层的掉落表（按「第几次通关」调整晶石数量）
## clear_index：本次是第几次通关，1 = 首通
static func get_tower_drops(floor_no: int, clear_index: int = 1) -> Array:
	var base: Array = TOWER_DROP_TEMPLATES.get(floor_no, TOWER_FLOOR_DROPS_DEFAULT)
	var out: Array = []
	for e in base:
		var entry: Dictionary = (e as Dictionary).duplicate()
		# 晶石数量跟通关次数走；其它材料仍按表里写的 count
		if String(entry.get("item_id", "")) == CharacterData.ENHANCE_MATERIAL:
			entry["count"] = tower_crystal_count(clear_index)
		out.append(entry)
	return out


## 判定塔层掉落，返回**每块一个条目**的列表
## 结构：[{ "type": 材料类型, "material_id": ..., "item": {...}, "count": 1 }]
##
## ⚠ 表里的 count = 「在地上掉落几块」，这里会拆成 count 个独立条目，
## 战斗场景据此在 BOSS 尸身旁生成 count 个可拾取物 —— 玩家必须逐块走近按 F 拾取。
## 目的是让强化材料有「走过去捡」的仪式感，而不是自动进背包。
## clear_index：本次是第几次通关（1 = 首通），决定晶石数量
static func roll_tower_drops(floor_no: int, clear_index: int = 1) -> Array:
	var out: Array = []
	for entry in get_tower_drops(floor_no, clear_index):
		var chance := get_drop_chance(entry)
		if randf() >= chance:
			continue
		var mid := String(entry.get("item_id", ""))
		var mat := get_material(mid)
		if mat.is_empty():
			push_warning("塔掉落表登记了未知材料：" + mid)
			continue
		var count := maxi(1, int(entry.get("count", 1)))
		for _i in count:
			out.append({
				"type": CharacterData.ITEM_MATERIAL,
				"material_id": mid,
				"item": {
					"id": mid,
					"name": String(mat.get("name", mid)),
					"type": CharacterData.ITEM_MATERIAL,
					"icon": String(mat.get("icon", "")),
					"desc": String(mat.get("desc", "")),
					"count": 1,
				},
				"count": 1,
			})
	return out


static func get_material(material_id: String) -> Dictionary:
	for m in MATERIALS:
		if String(m.get("id", "")) == material_id:
			return m
	return {}


static func get_material_name(material_id: String) -> String:
	return String(get_material(material_id).get("name", material_id))


## 材料所属区域境界（未登记返回空串，例如锻造晶石 / 元魂这类跨区域材料）
static func get_material_realm(material_id: String) -> String:
	return String(get_material(material_id).get("realm", ""))


## 任意物品条目的境界：材料 / 丹药 / 符箓查数据表，装备看境界限制
## 主要用于背包详情与局内背包 tooltip（老存档的物品条目本身不带 realm 字段）
static func item_realm(item: Dictionary) -> String:
	var id := String(item.get("id", ""))
	match String(item.get("type", "")):
		"material":
			return get_material_realm(id)
		"pill", "talisman":
			return String(get_consumable(id).get("realm", ""))
		"equipment":
			return String(item.get("current_realm_limit", ""))
	return ""


static func get_pill_recipe(recipe_id: String) -> Dictionary:
	for r in PILL_RECIPES:
		if String(r.get("recipe_id", "")) == recipe_id:
			return r
	return {}


static func get_talisman_recipe(recipe_id: String) -> Dictionary:
	for r in TALISMAN_RECIPES:
		if String(r.get("recipe_id", "")) == recipe_id:
			return r
	for r in element_talisman_recipes():
		if String(r.get("recipe_id", "")) == recipe_id:
			return r
	return {}


## 单味方料 id（丹方 / 符方如今都是「一味料 → 一颗成品」，第一味就是唯一一味）
## 表里真出现多味料时返回空串 —— 自由投料的界面不接管那种方子，别猜
static func recipe_material_id(recipe: Dictionary) -> String:
	var mats: Dictionary = recipe.get("materials", {})
	if mats.size() != 1:
		return ""
	return String(mats.keys()[0])


## 反查：这味料对应哪张方子（kind = "pill" / "talisman"）
## 自由投料的判定就靠它 —— 丢进炉子的第一株决定这一炉炼什么
static func recipe_for_material(craft_kind: String, material_id: String) -> Dictionary:
	if material_id == "":
		return {}
	var recipes: Array = PILL_RECIPES if craft_kind == "pill" else all_talisman_recipes()
	for raw in recipes:
		var r: Dictionary = raw
		if recipe_material_id(r) == material_id:
			return r
	return {}


## 这味料能炼成什么（列表 / 药谱抽屉的「青岚血参 → 练气回春丹」一行字）
static func product_name_for_material(craft_kind: String, material_id: String) -> String:
	var r := recipe_for_material(craft_kind, material_id)
	if r.is_empty():
		return ""
	return String(r.get("pill_name", r.get("talisman_name", "")))


## 这类设施能用到的全部材料 id（药筐 / 皮架的候选集与拖拽预判都用它）
static func usable_material_ids(craft_kind: String) -> Dictionary:
	var out := {}
	var recipes: Array = PILL_RECIPES if craft_kind == "pill" else all_talisman_recipes()
	for raw in recipes:
		var mid := recipe_material_id(raw as Dictionary)
		if mid != "":
			out[mid] = true
	return out


## 按**物品 id**（pill_id / talisman_id）取一条消耗品定义，附带 kind 字段（"pill" / "talisman"）
## 战斗轮盘与背包装配都用这一个入口，不在调用处分别遍历两张表
static func get_consumable(item_id: String) -> Dictionary:
	if item_id == "":
		return {}
	var elem := element_talisman_def(item_id)
	if not elem.is_empty():
		elem["kind"] = "talisman"
		return elem
	for raw in PILL_RECIPES:
		var r: Dictionary = raw
		if String(r.get("pill_id", "")) == item_id:
			var out := r.duplicate(true)
			out["kind"] = "pill"
			return out
	for raw in TALISMAN_RECIPES:
		var t: Dictionary = raw
		if String(t.get("talisman_id", "")) == item_id:
			var out := t.duplicate(true)
			out["kind"] = "talisman"
			return out
	return {}


## 配方 / 消耗品的作用描述（炼丹房、制符台的「效果」行与详情用）
## 恢复类按上限百分比措辞；持续类直接取 BuffDB 的说明（一处维护，HUD 与配方不会不一致）
static func effect_text(recipe: Dictionary) -> String:
	var raw = recipe.get("battle_effect", {})
	if not (raw is Dictionary):
		return ""
	var e: Dictionary = raw
	var text := ""
	match String(e.get("kind", "")):
		"heal_hp":
			text = "服下回复气血上限的 %d%%" % int(round(float(e.get("ratio", 0.0)) * 100.0))
		"restore_mana":
			text = "服下回复灵力上限的 %d%%" % int(round(float(e.get("ratio", 0.0)) * 100.0))
		"buff":
			## 属性类丹药的数值写在配方 mods 里（不同境界同名丹数值不同），
			## 不能直接读 BuffDB 的固定说明，否则筑基 / 结丹丹会显示成练气档的数字。
			var mods = e.get("mods", {})
			if mods is Dictionary and not (mods as Dictionary).is_empty():
				text = _mods_text(mods as Dictionary, float(e.get("seconds", 0.0)))
			else:
				var bid := String(e.get("buff_id", ""))
				text = BuffDB.display_text(bid) if not BuffDB.get_buff(bid).is_empty() else ""
	var mana_cost := float(recipe.get("mana_cost", 0.0))
	if text != "" and mana_cost > 0.0:
		text += "（消耗灵力 %d）" % int(round(mana_cost))
	return text


## 配方属性修正的可读文案，如「力量 +18%（按本体基础值，20 秒）」「物抗 / 法抗 +22（20 秒）」
static func _mods_text(mods: Dictionary, seconds: float) -> String:
	var sec_inline := ""
	var sec_paren := ""
	if seconds > 0.0:
		sec_inline = "，%d 秒" % int(round(seconds))
		sec_paren = "（%d 秒）" % int(round(seconds))
	var parts: Array[String] = []
	var labels := {"strength": "力量", "spell_power": "法强"}
	for key in labels.keys():
		var spec = mods.get(key, {})
		if spec is Dictionary and (spec as Dictionary).has("base_pct"):
			parts.append("%s +%d%%（按本体基础值%s）" % [
				String(labels[key]), int(round(float(spec["base_pct"]))), sec_inline])
	var resists: Array[int] = []
	for key in ["physical_resist", "magic_resist"]:
		var spec2 = mods.get(key, {})
		if spec2 is Dictionary and (spec2 as Dictionary).has("flat"):
			resists.append(int(round(float(spec2["flat"]))))
	if resists.size() == 1:
		var one := "物抗" if mods.has("physical_resist") else "法抗"
		parts.append("%s +%d%s" % [one, resists[0], sec_paren])
	elif resists.size() >= 2:
		if resists[0] == resists[1]:
			parts.append("物抗 / 法抗 +%d%s" % [resists[0], sec_paren])
		else:
			parts.append("物抗 +%d / 法抗 +%d%s" % [resists[0], resists[1], sec_paren])
	if parts.is_empty():
		return ""
	return "、".join(PackedStringArray(parts))


static func get_equipment_template(equipment_id: String) -> Dictionary:
	for e in EQUIPMENT_TEMPLATES:
		if String(e.get("equipment_id", "")) == equipment_id:
			return e
	return {}


## 取装备实例的局内武器外观 id。旧存档的装备实例可能没有 weapon_visual 字段，
## 这里按模板 id 回查，避免后加武器在局内回退成默认剑。
static func weapon_visual_for(item: Dictionary) -> String:
	var vid := String(item.get("weapon_visual", ""))
	if vid != "":
		return vid
	var eid := String(item.get("id", item.get("equipment_id", "")))
	if eid == "":
		return ""
	return String(get_equipment_template(eid).get("weapon_visual", ""))


## 装备模板上的禁令字段（cannot_discard / cannot_dismantle / cannot_enhance）。
## ⚠ 必须**按 id 回查模板**，不能读实例字段：装备实例是创建当年的模板快照，
##   早于这几条规则的存档里根本没有这些键（和 weapon_visual_for 同一个坑）。
##   传 id 也传实例里的 id（`id` 与 `equipment_id` 两种写法都在用）。
static func equipment_flag_set(item_or_id) -> Dictionary:
	var eid := ""
	if item_or_id is Dictionary:
		var it: Dictionary = item_or_id
		eid = String(it.get("id", it.get("equipment_id", "")))
	else:
		eid = String(item_or_id)
	if eid == "":
		return {}
	var tpl := get_equipment_template(eid)
	var out := {}
	for f in ["cannot_discard", "cannot_dismantle", "cannot_enhance"]:
		if bool(tpl.get(f, false)):
			out[f] = true
	return out


static func has_equipment_flag(item_or_id, flag: String) -> bool:
	return equipment_flag_set(item_or_id).has(flag)


## 把 {材料id:数量} 转成可读文本，如「血参 ×3、锐兽皮 ×2」
static func materials_text(materials: Dictionary) -> String:
	var parts: Array[String] = []
	for k in materials.keys():
		parts.append("%s ×%d" % [get_material_name(String(k)), int(materials[k])])
	return "、".join(parts) if parts.size() > 0 else "无"


## 带境界的材料文本，如「血参（练气）×3」——配方列表与详情用
static func materials_text_with_realm(materials: Dictionary) -> String:
	var parts: Array[String] = []
	for k in materials.keys():
		var realm := get_material_realm(String(k))
		var nm := get_material_name(String(k))
		parts.append(("%s（%s）×%d" % [nm, realm, int(materials[k])])
			if realm != "" else "%s ×%d" % [nm, int(materials[k])])
	return "、".join(parts) if parts.size() > 0 else "无"


## 攻击力加成文本：+8 / -2 / 空（为 0 时返回空串）
static func attack_bonus_text(item: Dictionary) -> String:
	var bonus := float(item.get("attack_bonus", 0.0))
	if is_zero_approx(bonus):
		return ""
	return "攻击力 %+d" % int(round(bonus))


## 取一件装备/法宝提供的属性（返回副本，缺失返回空字典）
static func item_attributes(item: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var src = item.get("attributes", {})
	if src is Dictionary:
		for k in src.keys():
			out[String(k)] = float(src[k])
	return out


## 不参与强化的固定词条要在面板上写清楚（用户 2026-11-04 定，如长夜刃的「精力 +1」）
## 单一口径：装备详情 / 锻造台铭牌 / 挂签 tooltip 都读这一句
const LOCKED_AFFIX_NOTE := "（固定属性，不可强化）"


static func affix_lock_note(attr_id: String) -> String:
	return "" if AttributeDB.can_enhance(attr_id) else LOCKED_AFFIX_NOTE


## 属性摘要文本（用于装备/法宝条目副标题）
static func item_attributes_text(item: Dictionary) -> String:
	var attrs := item_attributes(item)
	if attrs.is_empty():
		return ""
	var parts := PackedStringArray()
	for id in AttributeDB.all_ids():
		var key := String(id)
		if not attrs.has(key):
			continue
		var v := float(attrs[key])
		if is_zero_approx(v):
			continue
		parts.append("%s %s%s" % [AttributeDB.attr_name(key),
			AttributeDB.format_value(key, v), affix_lock_note(key)])
	return "　".join(parts)


## 属性摘要文本（**带强化增量标注**）：「力量 +10（+2）、速度 +20」
## 装备面板 / 锻造台用这个，玩家能一眼看出强化到底把哪个词条拔高了多少。
## 增量 = attributes[id] − attributes_base[id]（attributes_base 是模板原值，见 make_equipment_instance）
static func item_attributes_with_gain_text(item: Dictionary) -> String:
	var attrs := item_attributes(item)
	var base = item.get("attributes_base", {})
	var parts: Array[String] = []
	for id in attrs.keys():
		var key := String(id)
		var total := float(attrs[id])
		var origin := float(base.get(key, total)) if base is Dictionary else total
		var gain := total - origin
		var text := "%s %s%s" % [AttributeDB.attr_name(key), _signed_value(key, total),
			affix_lock_note(key)]
		if absf(gain) >= 0.005:
			text += "（%s）" % _signed_value(key, gain)
		parts.append(text)
	return "、".join(parts)


## 本次强化的属性增益文本 —— **只包含这一击加上的数值**（用户 2026-10-20 定）
## gains 结构：[{ "attr_id": String, "amount": float }]，来自 CharacterData.enhance_item 的 attr_gains
## 例："力量 +2、精力恢复 +0.5%"；进阶/失败时 gains 为空 → 返回空串（不显示属性行）
static func enhance_gain_text(gains: Array) -> String:
	var parts: Array[String] = []
	for g in gains:
		if not (g is Dictionary):
			continue
		var id := String(g.get("attr_id", ""))
		var amount := float(g.get("amount", 0.0))
		if id == "" or absf(amount) < 0.005:
			continue
		parts.append("%s %s" % [AttributeDB.attr_name(id), _signed_value(id, amount)])
	return "、".join(parts)


## 本次强化里是否有属性**顶到了区间上限**（用户 2026-10-20 定：命中上限时飘字要放大加粗）
## ⚠ 2026-11-13 起所有可强化词条都有波动（不再有固定值）；
##   仍保留 hi > lo 的判断，防以后又塞进固定值把飘字变成永久放大
static func enhance_gains_at_max(gains: Array) -> bool:
	for g in gains:
		if not (g is Dictionary):
			continue
		var id := String(g.get("attr_id", ""))
		var rng := AttributeDB.enhance_range(id)
		var lo := float(rng.get("min", 0.0))
		var hi := float(rng.get("max", 0.0))
		if hi > lo + 0.0001 and float(g.get("amount", 0.0)) >= hi - 0.005:
			return true
	return false


## 带符号的数值文案（装备属性 / 强化增益共用）
## ⚠ 2026-10-22 用户定：小数位**统一为 1 位**。
##   原来整数显示 +5（0 位）、小数显示 +3.1（1 位）、百分比 +0.8%（1 位）——位数不统一，
##   强化飘字里「+5」和「+3.1」并排显得乱。现在一律 1 位：+5.0 / +3.1 / +0.8%。
static func _signed_value(attr_id: String, value: float) -> String:
	var sign := "+" if value >= 0.0 else "-"
	var v := absf(value)
	return "%s%.1f%%" % [sign, v] if AttributeDB.is_percent(attr_id) else "%s%.1f" % [sign, v]


## 装备各词条「**成功时**」能涨多少的区间文案（锻造台铁砧上显示，用户 2026-10-22 定）
## 只列可强化词条（AttributeDB.can_enhance）；2026-11-13 起全部是区间，不再有「固定」。
## ⚠ 数值一律现算自 AttributeDB.ENHANCE_RANGE —— 调区间只改那一处，UI 自动跟上；
##   区间是「每一次成功」的取值，大成功则固定取上限并连升两级（写进 UI 提示语里）。
## ⚠ 增强量一律带 + 号（2026-11-13 用户要「增强范围」一眼能读成增益，而不是当前值）。
static func enhance_range_lines(item: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var attrs = item.get("attributes")
	if not (attrs is Dictionary):
		return out
	for k in attrs.keys():
		var key := String(k)
		if not AttributeDB.can_enhance(key):
			continue
		var r := AttributeDB.enhance_range(key)
		var lo := float(r.get("min", 0.0))
		var hi := float(r.get("max", lo))
		out.append("%s %s" % [AttributeDB.attr_name(key),
			_enhance_range_amount_text(key, lo, hi)])
	return out


## 区间两端用**同一精度**：整数区间不带小数、小数区间统一一位；
## 两个端点都小于 0.5 时保留两位（灵力恢复 / 精力恢复 的 0.05~0.10 不能被吞成 0.1~0.1）。
static func _enhance_range_amount_text(attr_id: String, lo: float, hi: float) -> String:
	# 百分比两端都要带 %，和单值增益的写法一致
	if AttributeDB.is_percent(attr_id):
		return "+%.1f%%~+%.1f%%" % [lo, hi]
	if is_zero_approx(lo - roundf(lo)) and is_zero_approx(hi - roundf(hi)):
		return "+%.0f~+%.0f" % [lo, hi]
	if maxf(lo, hi) < 0.5:
		return "+%.2f~+%.2f" % [lo, hi]
	return "+%.1f~+%.1f" % [lo, hi]


## 锻打铭牌用：这一锤「会随机拔高哪条词条、每次涨多少」。
## 强化每次从可强化词条里**随机挑一条**（大成功同上限、连升两级），所以列的是候选池。
## 例：「强化随机词条：力量 +1~+2 · 精力恢复速度 +0.5%~+1.0%」
## 返回 "" = 不显示（空砧 / 法宝 / 不可强化 —— 铭牌上另有说明）。
static func enhance_affix_line(item: Dictionary) -> String:
	if item.is_empty():
		return ""
	if String(item.get("equipment_type", "")) == "treasure":
		return ""
	if has_equipment_flag(item, "cannot_enhance"):
		return ""
	var lines := enhance_range_lines(item)
	if lines.is_empty():
		return "强化词条：无"
	return "强化随机词条：" + " · ".join(lines)


## 按部位取装备模板（weapon / armor / shoes / accessory）
static func get_equipment_by_type(equipment_type: String) -> Array:
	var out: Array = []
	for e in EQUIPMENT_TEMPLATES:
		if String(e.get("equipment_type", "")) == equipment_type:
			out.append(e)
	return out


# ===== 法宝 =====

## 全部法宝模板
static func get_treasure_templates() -> Array:
	return TREASURE_TEMPLATES


## 按 id 取法宝模板（未登记返回空字典）
static func get_treasure_template(treasure_id: String) -> Dictionary:
	for t in TREASURE_TEMPLATES:
		if String(t.get("treasure_id", "")) == treasure_id:
			return t
	return {}


## 召唤法宝（BOSS 令）的**实际**效果文案 —— 一律现算，不写死在模板 desc 里
## ⚠ 2026-10-21 用户报：强化/进阶之后背包详情里还是「助战 20 秒」，看不出成长。
##   模板 desc 只是**底稿**（写死 20 秒），真实数值必须从实例字段现算：
##     召唤时长 = summon_duration + summon_duration_bonus × SUMMON_DURATION_PER_ASCEND
##     气血/攻击加成 = summon_boost_count × SUMMON_BOOST_PER_LEVEL（%）
##                    + summon_ascend_boost_pct（进阶奖励累计）
static func _format_seconds(value: float) -> String:
	return "%d" % int(round(value)) if is_zero_approx(value - roundf(value)) else "%.1f" % value


static func _format_ratio(value: float) -> String:
	return "%.2f" % value


## 非召唤类法宝（没登记模板 / 没有 summon_boss_id）返回空数组，调用方自然不显示这几行。
static func treasure_effect_lines(item: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var tpl := get_treasure_template(String(item.get("equipment_id", item.get("id", ""))))
	if tpl.is_empty():
		return out
	# 主动回血类（凝水佩）：数值按「当前品阶 - 模板基础品阶」现算
	var active_type := String(tpl.get("active_type", ""))
	if active_type == "heal":
		var heal_stats := treasure_active_stats(item, tpl)
		out.append("主动使用：每秒消耗 %d 灵力，回复 %d 气血" % [
			int(round(float(heal_stats.get("mana", 10.0)))),
			int(round(float(heal_stats.get("heal", 5.0))))])
		out.append("持续：最多 %d 秒（每次升阶 +%d 秒）" % [
			int(round(float(heal_stats.get("duration", 8.0)))),
			int(round(float(tpl.get("ascend_duration", 1.0))))])
		out.append("灵力不足 %d 点时提前结束；每次升阶回复 +%d" % [
			int(round(float(heal_stats.get("mana", 10.0)))),
			int(round(float(tpl.get("ascend_heal_per_sec", 1.0))))])
		out.append("冷却：%d 秒" % int(round(float(heal_stats.get("cooldown", 20.0)))))
		return out
	# 主动护体类（太极盘）：一次性耗蓝，短时间减伤
	if active_type == "taiji_guard":
		var guard_stats := treasure_active_stats(item, tpl)
		out.append("主动使用：消耗 %d 灵力，受到伤害 -%d%%" % [
			int(round(float(guard_stats.get("mana", 20.0)))),
			int(round(float(guard_stats.get("reduction", 0.3)) * 100.0))])
		out.append("持续：%s 秒" % _format_seconds(float(guard_stats.get("duration", 6.0))))
		out.append("护体期间：敌方飞行物近身会被接化，绕身一周后反打来源")
		out.append("每次进阶：持续 +%s 秒、减伤 +%d%%" % [
			_format_seconds(float(tpl.get("ascend_duration", 0.5))),
			int(round(float(tpl.get("ascend_reduction", 0.01)) * 100.0))])
		out.append("冷却：%d 秒" % int(round(float(guard_stats.get("cooldown", 30.0)))))
		return out
	# 主动元素环绕（三元轮）：风 / 火 / 雷轮转打击身周敌人，任何战斗通用
	if active_type == "tri_ring":
		var ring_stats := treasure_active_stats(item, tpl)
		out.append("主动使用：消耗 %d 灵力，风 / 火 / 雷三炁环绕身 %d 秒" % [
			int(round(float(ring_stats.get("mana", 20.0)))),
			int(round(float(ring_stats.get("duration", 8.0))))])
		out.append("每 %s 秒轮换一种元素，对身周 %d 范围造成 %s× 法强的对应伤害" % [
			_format_seconds(float(ring_stats.get("interval", 1.0))),
			int(round(float(ring_stats.get("radius", 240.0)))),
			_format_ratio(float(ring_stats.get("ratio", 0.65)))])
		out.append("风：减速 20% 1.5 秒；火：劫火 2 秒；雷：感电 1.5 秒")
		out.append("每次进阶：持续 +%s 秒、元素倍率 +%s" % [
			_format_seconds(float(tpl.get("ascend_duration", 0.5))),
			_format_ratio(float(tpl.get("ascend_damage_ratio", 0.03)))])
		out.append("冷却：%d 秒" % int(round(float(ring_stats.get("cooldown", 40.0)))))
		return out
	# 主动加速类（逐电环）：一次性耗蓝，短时间把移速抬到固定值
	if active_type == "haste":
		var haste_stats := treasure_active_stats(item, tpl)
		out.append("主动使用：消耗 %d 灵力，速度提升至 %d" % [
			int(round(float(haste_stats.get("mana", 30.0)))),
			int(round(float(haste_stats.get("speed", 800.0))))])
		var duration := float(haste_stats.get("duration", 3.0))
		var ascend_add := float(tpl.get("ascend_duration", 0.0))
		var dur_txt := "%d" % int(round(duration))
		if not is_zero_approx(duration - roundf(duration)):
			dur_txt = "%.1f" % duration
		if ascend_add > 0.0:
			out.append("持续：%s 秒（每次升阶 +%.1f 秒）" % [dur_txt, ascend_add])
		else:
			out.append("持续：%s 秒" % dur_txt)
		out.append("冷却：%d 秒" % int(round(float(haste_stats.get("cooldown", 30.0)))))
		return out
	# 断念铃：打断 + 封技
	if active_type == "mind_lock":
		var bell := treasure_active_stats(item, tpl)
		out.append("主动使用：消耗 %d 灵力，封住 %d 范围内目标功法 %s 秒" % [
			int(round(float(bell.get("mana", 20.0)))),
			int(round(float(bell.get("range", 300.0)))),
			_format_seconds(float(bell.get("silence", 1.8)))])
		out.append("正在起手的招式会被打断；打断成功返还 %d 灵力" % [
			int(round(float(bell.get("refund", 10.0))))])
		out.append("每次升阶封技 +%s 秒；同一目标 8 秒内只封一次" % [
			_format_seconds(float(tpl.get("ascend_silence", 0.3)))])
		out.append("冷却：%d 秒" % int(round(float(bell.get("cooldown", 35.0)))))
		return out
	# 禁步桩：预埋场地
	if active_type == "stake":
		var stake := treasure_active_stats(item, tpl)
		out.append("主动使用：消耗 %d 灵力，在目标脚下钉桩" % [
			int(round(float(stake.get("mana", 15.0))))])
		out.append("%s 秒后展开 %d 范围禁步圈，持续 %s 秒" % [
			_format_seconds(float(stake.get("arm_time", 0.8))),
			int(round(float(stake.get("radius", 110.0)))),
			_format_seconds(float(stake.get("duration", 4.0)))])
		out.append("展开时圈内禁步 %s 秒；圈内移速 -%d%%、无法闪避、精力停止恢复" % [
			_format_seconds(float(stake.get("initial_slow", 1.5))),
			int(round((1.0 - float(stake.get("slow_mult", 0.65))) * 100.0))])
		out.append("每次升阶禁步 +%s 秒" % [
			_format_seconds(float(tpl.get("ascend_initial_slow", 0.2)))])
		out.append("冷却：%d 秒" % int(round(float(stake.get("cooldown", 28.0)))))
		return out
	# 续命灯：致死改判
	if active_type == "lamp":
		var lamp := treasure_active_stats(item, tpl)
		out.append("主动使用：消耗 %d 灵力，点亮续命灯 %s 秒" % [
			int(round(float(lamp.get("mana", 25.0)))),
			_format_seconds(float(lamp.get("duration", 10.0)))])
		out.append("期间第一次致死伤害：气血保留 1 点，随后 1 秒回复 %d%% 最大气血" % [
			int(round(float(lamp.get("heal_ratio", 0.15)) * 100.0))])
		out.append("触发时 %s 秒无敌，并击退身周 %d 范围敌人" % [
			_format_seconds(float(lamp.get("invuln", 0.8))),
			int(round(float(lamp.get("knockback_radius", 200.0))))])
		out.append("每次升阶回复 +%d%%；冷却：%d 秒" % [
			int(round(float(tpl.get("ascend_heal_ratio", 0.01)) * 100.0)),
			int(round(float(lamp.get("cooldown", 60.0))))])
		return out
	# 蚀甲锥：破护体
	if active_type == "corrode":
		var cone := treasure_active_stats(item, tpl)
		out.append("主动使用：消耗 %d 灵力，掷出锥子（射程 %d）" % [
			int(round(float(cone.get("mana", 15.0)))),
			int(round(float(cone.get("range", 400.0))))])
		out.append("命中后 %s 秒：目标受到伤害 +%d%%，护体类减伤减半（符箓除外）" % [
			_format_seconds(float(cone.get("duration", 8.0))),
			int(round(float(cone.get("damage_bonus", 0.12)) * 100.0))])
		out.append("每次升阶持续 +%s 秒；重复命中只刷新" % [
			_format_seconds(float(tpl.get("ascend_duration", 0.5)))])
		out.append("冷却：%d 秒" % int(round(float(cone.get("cooldown", 30.0)))))
		return out
	# 血饲印：以血换功法冷却
	if active_type == "blood_seal":
		var seal := treasure_active_stats(item, tpl)
		out.append("主动使用：消耗 %d%% 最大气血（需气血高于 %d%%），立刻重置全部功法冷却" % [
			int(round(float(seal.get("hp_ratio", 0.15)) * 100.0)),
			int(round(float(seal.get("min_hp_ratio", 0.25)) * 100.0))])
		out.append("回复 %d%% 最大灵力" % int(round(float(seal.get("mana_restore", 0.30)) * 100.0)))
		out.append("每次进阶灵力回复 +%d%%；冷却：%d 秒" % [
			int(round(float(tpl.get("ascend_mana_restore", 0.03)) * 100.0)),
			int(round(float(seal.get("cooldown", 60.0))))])
		return out
	# 换位玦：互换位置
	if active_type == "swap":
		var swap := treasure_active_stats(item, tpl)
		out.append("主动使用：消耗 %d 灵力，与 %d 范围内目标互换位置" % [
			int(round(float(swap.get("mana", 20.0)))),
			int(round(float(swap.get("range", 360.0))))])
		out.append("落地 %s 秒无敌；每次进阶 +%s 秒" % [
			_format_seconds(float(swap.get("invuln", 0.4))),
			_format_seconds(float(tpl.get("ascend_invuln", 0.1)))])
		out.append("冷却：%d 秒" % int(round(float(swap.get("cooldown", 45.0)))))
		return out
	# 棘甲佩：近战反伤
	if active_type == "thorns":
		var thorns := treasure_active_stats(item, tpl)
		out.append("主动使用：消耗 %d 灵力，持续 %s 秒" % [
			int(round(float(thorns.get("mana", 15.0)))),
			_format_seconds(float(thorns.get("duration", 4.0)))])
		out.append("受到近战物理伤害时，把 %d%% 反弹给攻击者" % [
			int(round(float(thorns.get("reflect_ratio", 0.30)) * 100.0))])
		out.append("只反近战物理，不反远程 / 法术 / 符箓；每次进阶 +%d%%" % [
			int(round(float(tpl.get("ascend_reflect_ratio", 0.03)) * 100.0))])
		out.append("冷却：%d 秒" % int(round(float(thorns.get("cooldown", 35.0)))))
		return out
	# 回风袋：推开身周敌人
	if active_type == "gust":
		var gust := treasure_active_stats(item, tpl)
		out.append("主动使用：消耗 %d 灵力，把身周 %d 范围敌人推开 %d" % [
			int(round(float(gust.get("mana", 15.0)))),
			int(round(float(gust.get("radius", 220.0)))),
			int(round(float(gust.get("push", 240.0))))])
		out.append("不造成伤害；每次进阶推距 +%d" % [
			int(round(float(tpl.get("ascend_push", 20.0))))])
		out.append("冷却：%d 秒" % int(round(float(gust.get("cooldown", 30.0)))))
		return out
	# 位面法宝·照影·迟照符：延迟结算，数值全部现算
	if active_type == "delayed_reckoning":
		var rk := treasure_active_stats(item, tpl)
		out.append("主动使用：消耗 %d 灵力，%s 秒内所受伤害暂不扣血、记入待结池" % [
			int(round(float(rk.get("mana", 20.0)))),
			_format_seconds(float(rk.get("duration", 4.0)))])
		out.append("期间每次完美闪避 / 完美弹反 / 打断起手，抹去待结伤害的 %d%%（最多 %d 次）" % [
			int(round(float(rk.get("wipe_pct", 0.30)) * 100.0)),
			int(rk.get("max_wipes", 3))])
		out.append("到期一次性结算剩余；若因此致死则正常死亡（不减伤、不替死）")
		out.append("每次进阶：窗口 +%s 秒、抹除 +%d%%" % [
			_format_seconds(float(tpl.get("ascend_duration", 0.5))),
			int(round(float(tpl.get("ascend_wipe_pct", 0.05)) * 100.0))])
		out.append("冷却：%d 秒" % int(round(float(rk.get("cooldown", 38.0)))))
		return out
	# 位面法宝·凡界·换锋符：替换普攻形态，数值全部现算
	if active_type == "blade_form":
		var bf := treasure_active_stats(item, tpl)
		out.append("主动使用：消耗 %d 灵力，%s 秒内换锋生效，普攻三段化作剑气" % [
			int(round(float(bf.get("mana", 15.0)))),
			_format_seconds(float(bf.get("duration", 5.0)))])
		out.append("剑气沿前方 %d 范围直线飞出，宽 %d，可穿透沿途所有敌人" % [
			int(round(float(bf.get("range", 320.0)))),
			int(round(float(bf.get("width", 96.0))))])
		out.append("伤害仍按原本三段连击结算：终结段更高，不改系数、不叠层、不留痕")
		out.append("每次进阶：持续 +%s 秒" % _format_seconds(float(tpl.get("ascend_duration", 1.0))))
		out.append("冷却：%d 秒" % int(round(float(bf.get("cooldown", 22.0)))))
		return out
	if String(tpl.get("summon_boss_id", "")) == "":
		return out
	var base_dur := float(tpl.get("summon_duration", 20.0))
	var ascends := maxi(0, int(item.get("summon_duration_bonus", 0)))
	var add_sec := float(ascends) * CharacterData.SUMMON_DURATION_PER_ASCEND
	out.append("召唤时长：%d 秒（基础 %d + 进阶 +%d）" % [
		int(round(base_dur + add_sec)), int(round(base_dur)), int(round(add_sec))])
	# 总加成 = 强化级数 × 2% + 进阶奖励累计（进阶前加成的 50% 可带小数）
	var boost := float(maxi(0, int(item.get("summon_boost_count", 0)))) \
		* CharacterData.SUMMON_BOOST_PER_LEVEL + float(item.get("summon_ascend_boost_pct", 0.0))
	var boost_txt := "%d" % int(roundf(boost)) if is_zero_approx(boost - roundf(boost)) else "%.1f" % boost
	out.append("召唤物气血与攻击：+%s%%" % boost_txt)
	out.append("冷却：%d 秒" % int(round(float(tpl.get("summon_cooldown", 60.0)))))
	return out


## 主动法宝的当前数值
## 主动回血类按「当前品阶 - 模板品阶」推导升阶次数；主动加速类不随升阶成长。
static func treasure_active_stats(item: Dictionary, tpl: Dictionary = {}) -> Dictionary:
	if tpl.is_empty():
		tpl = get_treasure_template(String(item.get("equipment_id", item.get("id", ""))))
	if tpl.is_empty():
		return {}
	var active_type := String(tpl.get("active_type", ""))
	var base_grade := String(tpl.get("treasure_grade", "法器"))
	var ascends := maxi(0, grade_index(String(item.get("equipment_grade", ""))) - grade_index(base_grade))
	if active_type == "heal":
		return {
			"kind": "heal",
			"ascends": ascends,
			"heal": float(tpl.get("active_heal_per_sec", 5.0))
				+ float(ascends) * float(tpl.get("ascend_heal_per_sec", 1.0)),
			"mana": float(tpl.get("active_mana_per_sec", 10.0)),
			"duration": float(tpl.get("active_duration", 8.0))
				+ float(ascends) * float(tpl.get("ascend_duration", 1.0)),
			"cooldown": float(tpl.get("active_cooldown", 20.0)),
		}
	if active_type == "taiji_guard":
		return {
			"kind": "taiji_guard",
			"ascends": ascends,
			"mana": float(tpl.get("active_mana_cost", 20.0)),
			"reduction": clampf(float(tpl.get("active_damage_reduction", 0.3))
				+ float(ascends) * float(tpl.get("ascend_reduction", 0.0)), 0.0, 0.8),
			"duration": float(tpl.get("active_duration", 6.0))
				+ float(ascends) * float(tpl.get("ascend_duration", 0.0)),
			"cooldown": float(tpl.get("active_cooldown", 30.0)),
		}
	if active_type == "tri_ring":
		return {
			"kind": "tri_ring",
			"ascends": ascends,
			"mana": float(tpl.get("active_mana_cost", 20.0)),
			"duration": float(tpl.get("active_duration", 8.0))
				+ float(ascends) * float(tpl.get("ascend_duration", 0.0)),
			"cooldown": float(tpl.get("active_cooldown", 40.0)),
			"radius": float(tpl.get("active_radius", 240.0)),
			"interval": float(tpl.get("active_interval", 1.0)),
			"ratio": float(tpl.get("active_damage_ratio", 0.65))
				+ float(ascends) * float(tpl.get("ascend_damage_ratio", 0.0)),
		}
	if active_type == "haste":
		return {
			"kind": "haste",
			"ascends": ascends,
			"mana": float(tpl.get("active_mana_cost", 30.0)),
			"speed": float(tpl.get("active_speed", 800.0)),
			"duration": float(tpl.get("active_duration", 3.0))
				+ float(ascends) * float(tpl.get("ascend_duration", 0.0)),
			"cooldown": float(tpl.get("active_cooldown", 30.0)),
		}
	## 照影·迟照符「迟照」：延迟结算 + 操作抹账（进阶加窗口与抹除比例）
	if active_type == "delayed_reckoning":
		return {
			"kind": "delayed_reckoning",
			"ascends": ascends,
			"mana": float(tpl.get("active_mana_cost", 20.0)),
			"duration": float(tpl.get("active_duration", 4.0))
				+ float(ascends) * float(tpl.get("ascend_duration", 0.0)),
			"cooldown": float(tpl.get("active_cooldown", 38.0)),
			"wipe_pct": clampf(float(tpl.get("active_wipe_pct", 0.30))
				+ float(ascends) * float(tpl.get("ascend_wipe_pct", 0.0)), 0.0, 1.0),
			"max_wipes": maxi(1, int(tpl.get("active_max_wipes", 3))),
		}
	## 凡界·换锋符「换锋」：普攻三段改远程直线穿透剑气
	if active_type == "blade_form":
		return {
			"kind": "blade_form",
			"ascends": ascends,
			"mana": float(tpl.get("active_mana_cost", 15.0)),
			"duration": float(tpl.get("active_duration", 5.0))
				+ float(ascends) * float(tpl.get("ascend_duration", 0.0)),
			"cooldown": float(tpl.get("active_cooldown", 22.0)),
			"range": float(tpl.get("active_range", 320.0)),
			"width": float(tpl.get("active_width", 96.0)),
		}
	if active_type == "mind_lock":
		return {
			"kind": "mind_lock",
			"ascends": ascends,
			"mana": float(tpl.get("active_mana_cost", 20.0)),
			"range": float(tpl.get("active_range", 300.0)),
			"silence": float(tpl.get("active_silence", 1.8))
				+ float(ascends) * float(tpl.get("ascend_silence", 0.0)),
			"refund": float(tpl.get("active_refund", 10.0)),
			"telegraph": float(tpl.get("active_telegraph", 0.45)),
			"cooldown": float(tpl.get("active_cooldown", 35.0)),
		}
	if active_type == "stake":
		return {
			"kind": "stake",
			"ascends": ascends,
			"mana": float(tpl.get("active_mana_cost", 15.0)),
			"range": float(tpl.get("active_range", 300.0)),
			"radius": float(tpl.get("active_radius", 110.0)),
			"arm_time": float(tpl.get("active_arm_time", 0.8)),
			"duration": float(tpl.get("active_duration", 4.0)),
			"initial_slow": float(tpl.get("active_initial_slow", 1.5))
				+ float(ascends) * float(tpl.get("ascend_initial_slow", 0.0)),
			"slow_mult": float(tpl.get("active_slow_mult", 0.65)),
			"slow_refresh": float(tpl.get("active_slow_refresh", 0.6)),
			"cooldown": float(tpl.get("active_cooldown", 28.0)),
		}
	if active_type == "lamp":
		return {
			"kind": "lamp",
			"ascends": ascends,
			"mana": float(tpl.get("active_mana_cost", 25.0)),
			"duration": float(tpl.get("active_duration", 10.0)),
			"heal_ratio": float(tpl.get("active_heal_ratio", 0.15))
				+ float(ascends) * float(tpl.get("ascend_heal_ratio", 0.0)),
			"invuln": float(tpl.get("active_invuln", 0.8)),
			"knockback_radius": float(tpl.get("active_knockback_radius", 200.0)),
			"trigger_hp_ratio": float(tpl.get("active_trigger_hp_ratio", 0.4)),
			"cooldown": float(tpl.get("active_cooldown", 60.0)),
		}
	if active_type == "corrode":
		return {
			"kind": "corrode",
			"ascends": ascends,
			"mana": float(tpl.get("active_mana_cost", 15.0)),
			"range": float(tpl.get("active_range", 400.0)),
			"speed": float(tpl.get("active_speed", 900.0)),
			"duration": float(tpl.get("active_debuff_time", 8.0))
				+ float(ascends) * float(tpl.get("ascend_duration", 0.0)),
			"damage_bonus": float(tpl.get("active_damage_bonus", 0.12)),
			"guard_shred": float(tpl.get("active_guard_shred", 0.5)),
			"cooldown": float(tpl.get("active_cooldown", 30.0)),
		}
	if active_type == "blood_seal":
		return {
			"kind": "blood_seal",
			"ascends": ascends,
			"mana": float(tpl.get("active_mana_cost", 0.0)),
			"cooldown": float(tpl.get("active_cooldown", 60.0)),
			"hp_ratio": float(tpl.get("active_hp_ratio", 0.15)),
			"min_hp_ratio": float(tpl.get("active_min_hp_ratio", 0.25)),
			"mana_restore": float(tpl.get("active_mana_restore", 0.30))
				+ float(ascends) * float(tpl.get("ascend_mana_restore", 0.0)),
		}
	if active_type == "swap":
		return {
			"kind": "swap",
			"ascends": ascends,
			"mana": float(tpl.get("active_mana_cost", 20.0)),
			"cooldown": float(tpl.get("active_cooldown", 45.0)),
			"range": float(tpl.get("active_range", 360.0)),
			"invuln": float(tpl.get("active_invuln", 0.4))
				+ float(ascends) * float(tpl.get("ascend_invuln", 0.0)),
		}
	if active_type == "thorns":
		return {
			"kind": "thorns",
			"ascends": ascends,
			"mana": float(tpl.get("active_mana_cost", 15.0)),
			"cooldown": float(tpl.get("active_cooldown", 35.0)),
			"duration": float(tpl.get("active_duration", 4.0)),
			"reflect_ratio": float(tpl.get("active_reflect_ratio", 0.30))
				+ float(ascends) * float(tpl.get("ascend_reflect_ratio", 0.0)),
		}
	if active_type == "gust":
		return {
			"kind": "gust",
			"ascends": ascends,
			"mana": float(tpl.get("active_mana_cost", 15.0)),
			"cooldown": float(tpl.get("active_cooldown", 30.0)),
			"radius": float(tpl.get("active_radius", 220.0)),
			"push": float(tpl.get("active_push", 240.0))
				+ float(ascends) * float(tpl.get("ascend_push", 0.0)),
		}
	return {}


## 模板 desc 里那句写死的「助战 20 秒」要抹掉，否则会和新算出来的时长打架
## （只去掉「 N 秒」这一小段，前面的风味文字保留；主动回血类没有这句）
static func treasure_desc_without_duration(item: Dictionary) -> String:
	var desc := String(item.get("desc", ""))
	var tpl := get_treasure_template(String(item.get("equipment_id", item.get("id", ""))))
	if tpl.is_empty() or String(tpl.get("active_type", "")) != "":
		return desc
	return desc.replace(" %d 秒" % int(round(float(tpl.get("summon_duration", 20.0)))), "")


# ===== 合成台查询（2026-10-21）=====

## 该 BOSS 会掉的装备模板 id 列表 —— 合成时用它校验「这件破损装备是不是该 BOSS 的」
static func get_boss_equipment_ids(boss_id: String) -> Array:
	var out: Array = []
	for entry in get_drops_for_boss(boss_id):
		var id := String(entry.get("item_id", ""))
		if id != "" and not (id in out):
			out.append(id)
	return out


## 按元魂 id 找配方（找不到返回空字典）
static func get_synth_recipe_by_soul(soul_id: String) -> Dictionary:
	for r in SYNTH_RECIPES:
		if String(r.get("soul_id", "")) == soul_id:
			return r
	return {}


## 按产物 id 找配方
static func get_synth_recipe_by_result(result_id: String) -> Dictionary:
	for r in SYNTH_RECIPES:
		if String(r.get("result_id", "")) == result_id:
			return r
	return {}


## 这件装备模板能配出哪条配方（不属于任何 BOSS 掉落 → 空字典）
static func get_synth_recipe_for_equipment(template_id: String) -> Dictionary:
	for r in SYNTH_RECIPES:
		if template_id in get_boss_equipment_ids(String(r.get("boss_id", ""))):
			return r
	return {}


## 该物品 id 是不是元魂（元魂统一以 soul_ 前缀登记在 MATERIALS 里）
static func is_soul_item(item_id: String) -> bool:
	return item_id.begins_with("soul_") and not get_material(item_id).is_empty()


## ===== 非装备物品的稀有度（2026-10-24 用户定：独立五档） =====
## 颜色复用装备七色环（UIKit.GRADE_COLORS），不在别处另写一套色值。
const RARITY_ORDER: Array = ["common", "uncommon", "rare", "epic", "legendary", "mythic"]
const RARITY_NAMES: Dictionary = {
	"common": "普通",
	"uncommon": "优良",
	"rare": "稀有",
	"epic": "史诗",
	"legendary": "传说",
	"mythic": "神话",
}
const RARITY_GRADE: Dictionary = {
	"common": "凡品",
	"uncommon": "法器",
	"rare": "灵器",
	"epic": "宝器",
	"legendary": "道器",
	"mythic": "仙器",
}


static func rarity_name(rarity: String) -> String:
	return String(RARITY_NAMES.get(rarity, ""))


## 稀有度 → 显示颜色（与装备同色板：白 / 绿 / 蓝 / 紫 / 橙）
static func rarity_color(rarity: String) -> Color:
	var grade := String(RARITY_GRADE.get(rarity, ""))
	return UIKit.grade_color(grade) if grade != "" else UIKit.C_TEXT


## 物品条目的稀有度：材料 / 丹药 / 符箓都按 id 回查数据表，
## 老存档条目本身没存 rarity 也能正确上色；装备走独立品阶，这里返回空串。
static func item_rarity(item: Dictionary) -> String:
	var id := String(item.get("id", ""))
	match String(item.get("type", "")):
		"material":
			return String(get_material(id).get("rarity", "common"))
		"pill", "talisman":
			var def := get_consumable(id)
			return String(def.get("rarity", item.get("rarity", "common")))
		"equipment":
			return ""
	return String(item.get("rarity", ""))


## 物品格子的描边色：装备 / 法宝 = 品阶色；材料 / 丹药 / 符箓 = 稀有度色
## ⚠ 旧存档里的法宝 type 还是 "treasure"，也要走品阶分支
static func item_border_color(item: Dictionary) -> Color:
	var t := String(item.get("type", ""))
	if t == "equipment" or t == "treasure":
		return UIKit.grade_border_color(String(item.get("equipment_grade", "")))
	return rarity_color(item_rarity(item))


## 只知道材料 id 时的描边色（炼制炉位 / 材料架用）
static func material_border_color(material_id: String) -> Color:
	return rarity_color(String(get_material(material_id).get("rarity", "common")))


## 材料的稀有度（没有该字段返回空串）
static func material_rarity(material_id: String) -> String:
	return String(get_material(material_id).get("rarity", ""))


## 该 BOSS 对应的元魂模板（找不到返回空字典）
static func soul_for_boss(boss_id: String) -> Dictionary:
	for r in SYNTH_RECIPES:
		if String(r.get("boss_id", "")) == boss_id:
			return get_material(String(r.get("soul_id", "")))
	return {}


## 造一条「材料」掉落条目（与 roll_tower_drops 同结构，供其它地方复用）
## 塔层 BOSS 的蕴仙髓掷骰：命中返回一条材料掉落，没中返回空字典
static func roll_tower_yunxian_drop() -> Dictionary:
	if randf() >= TOWER_YUNXIAN_DROP_CHANCE:
		return {}
	return make_material_drop(CharacterData.YUNXIAN_MATERIAL)


static func make_material_drop(material_id: String) -> Dictionary:
	var mat := get_material(material_id)
	if mat.is_empty():
		return {}
	return {
		"type": CharacterData.ITEM_MATERIAL,
		"material_id": material_id,
		"item": {
			"id": material_id,
			"name": String(mat.get("name", material_id)),
			"type": CharacterData.ITEM_MATERIAL,
			"icon": String(mat.get("icon", "")),
			"desc": String(mat.get("desc", "")),
			"rarity": String(mat.get("rarity", "")),
			"count": 1,
		},
	}


## 开局自带法宝的模板列表（由 CharacterData.ensure_starting_treasures 发放）
static func get_starting_treasures() -> Array:
	var out: Array = []
	for t in TREASURE_TEMPLATES:
		if bool(t.get("is_starting_treasure", false)):
			out.append(t)
	return out


## 开局自带装备（is_starting_equipment = true）的模板列表
## 由 CharacterData.ensure_starting_equipment() 在首次启动时发放
static func get_starting_equipment() -> Array:
	var out: Array = []
	for e in EQUIPMENT_TEMPLATES:
		if bool(e.get("is_starting_equipment", false)):
			out.append(e)
	return out


## 剧情道具（非装备，不可穿戴、不可锻造）
static func get_story_item(item_id: String) -> Dictionary:
	for s in STORY_ITEMS:
		if String(s.get("item_id", "")) == item_id:
			return s
	return {}


static func get_story_item_name(item_id: String) -> String:
	var s := get_story_item(item_id)
	return String(s.get("item_name", item_id)) if not s.is_empty() else item_id
