class_name SecretWorldDB
extends RefCounted
## 万界秘境·苍澜大陆（第三套玩法循环）静态数据表
##
## 结构：苍澜大陆是一张 3 列 × 2 行的连续大地图（每格 6000×4000），
##   五个境界区域首尾相接：练气（右下）→ 筑基（中右）→ 结丹（中上，筑基正左）
##   → 元婴（中下，结丹正下 / 练气正左）→ 化神（左上，占位）。右上角留给海域，后续需要时再扩。
##   当前开放「练气」「筑基」「结丹」「元婴」四区；化神区域数据先占位，
##   等对应位面的核心首领 / 灵兽 / 药材设计完成后再打开（把 unlocked 改成 true 即可）。
##
## 本表只登记「有什么、在哪、多久刷新、掉什么」。
## 运行时状态（核心首领是否已杀、资源下次刷新时刻）存在 CharacterData.secret_world，
## 与静态表分开 —— 换地图/改刷新时间不需要迁移存档。

const REGION_LIANQI := "world_lianqi"
const REGION_ZHUJI := "world_zhuji"
const REGION_JIEDAN := "world_jiedan"
const REGION_YUANYING := "world_yuanying"
const REGION_HUASHEN := "world_huashen"

## 九天门：幽冥灵墟中心、由元婴区首领镇墟石犼镇守的那道门，通往九天之上。
## 门槛写在 CharacterData.huashen_gate_check()（元婴后期圆满 + 持有完整化神破境晶），
## 这里只管「门在世界里的哪个点」。
static func huashen_gate_pos() -> Vector2:
	var r := get_region(REGION_YUANYING)
	var rect: Rect2 = r.get("rect", Rect2())
	var off := Vector2.ZERO
	var lm = r.get("landmark", null)
	if lm is Dictionary:
		off = (lm as Dictionary).get("pos", Vector2.ZERO)
	# 和 _build_region_landmark 同一个算式：门永远开在山门贴图上，不会画在空地里
	return rect.get_center() + off


## 化神坛：九天之上中央的突破点。开过九天门才进得来，所以位置直接取区域中心，
## 和 HUASHEN_CONTENT 的落点（偏东南）错开，玩家一进场不会站在坛上按 F。
static func huashen_altar_pos() -> Vector2:
	return (get_region(REGION_HUASHEN).get("rect", Rect2()) as Rect2).get_center()


## 区域是否真的对玩家开放。
## 化神区（九天之上）不看静态 unlocked —— 它由「九天门开过没有」决定，
## 所以这里漏掉的读取点会退回读 unlocked（=false），失败方向是「进不去」而不是「提前开」。
static func is_region_open(r: Dictionary) -> bool:
	if String(r.get("region_id", "")) == REGION_HUASHEN:
		return CharacterData.huashen_gate_opened
	return bool(r.get("unlocked", false))


## 从世界区域面板直接进区时，记下玩家选的那一块；secret_world 进场取一次后清空。
## 走传送门 / 正常进图时为空 → 落在练气区入口。
static var pending_spawn_region: String = ""


static func take_pending_spawn_region() -> String:
	var rid := pending_spawn_region
	pending_spawn_region = ""
	return rid

# ===== 修为产出（2026-10-24 用户定）=====
## 苍澜大陆：小怪（灵兽 / 野修）每只 30，核心首领 500
const EXP_BEAST := 30
const EXP_CULTIVATOR := 30
const EXP_CORE := 500

# ===== 区域 =====
## rect：该区域在苍澜大陆世界坐标里的矩形（连续拼在一起，不重叠）
## ⚠ 练气区固定在**右下角**（用户 2026-10-23 定）
## 区域内的资源坐标表以区域中心为原点，secret_world 加载时整体平移到 rect 中心
## terrain：低频遮罩 + 可平铺 tile 的地形配方（2026-10-26 练气区先上）
##   三套 tile 各盖 512 世界像素，按 mask 的 RGB 加权混合，A 通道叠地面贴花；
##   bands 是压在 rect 边上的林带（南=侧视树墙、东=俯视密冠），只在长边重复。
##   遮罩和 tile 都由 tools/{prep_region_tiles,bake_region_mask,bake_region_bands}.py
##   从 vibe_images 的出图确定性重烘，改图不用改代码。
## map_image：世界区域面板背后那张总览图。配了 terrain 的区域由
##   tools/bake_region_minimap.py 从同一批素材反推，不单独画第二张地图。
## wall_inset：碰撞墙从 rect 每条边内缩多少（配字典 = 按边，配数字 = 四边同值）。
##   南/东是森林，墙放在树线内侧，玩家被树挡住而不是撞空气墙；
##   西/北将来是通往其他区域的路，不种树，墙先贴边拦一下（用户 2026-10-23）
## ground_color / border_color：没有贴图时的色块配色（占位兜底）
## corner_caps：多区交汇点的地面补片（世界坐标 → 贴图）。四条接缝带在交角处
##   各自淡到约 50% alpha，地形板块的硬边会从缝里透出来；补片中心不透明、
##   往外径向淡出，把直边压掉。只有该点四周的象限全被已解锁区域占满时才铺。
const CORNER_CAPS: Array = [
	{"pos": Vector2(0.0, 0.0), "tex": "res://assets/scenes/tiles/corner_fourway_v2.png"},
]
const REGIONS: Array = [
	{
		"region_id": REGION_LIANQI,
		"name": "青岚野",
		"realm": "练气",
		"order": 1,
		"unlocked": true,
		"rect": Rect2(0.0, 0.0, 6000.0, 4000.0),
		"map_image": "res://assets/ui/facilities/world_map_lianqi.png",
		"terrain": {
			"mask": "res://assets/scenes/tiles/lianqi_mask.png",
			"grass": "res://assets/scenes/tiles/lianqi_grass.png",
			"road": "res://assets/scenes/tiles/lianqi_road.png",
			"forest": "res://assets/scenes/tiles/lianqi_forestfloor.png",
			"bands": {
				"south": "res://assets/scenes/tiles/lianqi_band_south_v2.png",
				"east": "res://assets/scenes/tiles/lianqi_band_east_v2.png",
			},
			## 北沿接云隐谷：俯视草地 → 林下腐叶的接缝地垫（上下各留 210 世界像素）
			"seam_horizontal": "res://assets/scenes/tiles/seam_h_lianqi_zhuji_v2.png",
		},
		"wall_inset": {"north": 40.0, "west": 40.0, "south": 355.0, "east": 400.0},
		"ground_color": Color(0.13, 0.19, 0.15, 1.0),
		"border_color": Color(0.34, 0.54, 0.34, 1.0),
		"desc": "松杉成岗、草色深青的凡俗旷野。灵兽与药材都不算稀有，适合初入修行的修士。",
		"core_boss_id": "world_core_lianqi",
		"core_reward": {"mat_pojing_di_zhuji": 1},
		"core_where": "青岚野中央",
		## 野外修士的功法池：取这些 BOSS 会用的招式反查功法（凡界 = 练气境界）
		"skill_pool_bosses": ["boss_huyao", "boss_01", "boss_01_c"],
	},
	{
		"region_id": REGION_ZHUJI,
		"name": "云隐谷",
		"realm": "筑基",
		"order": 2,
		"unlocked": true,
		"rect": Rect2(0.0, -4000.0, 6000.0, 4000.0),
		"map_image": "res://assets/ui/facilities/world_map_zhuji.png",
		"terrain": {
			"mask": "res://assets/scenes/tiles/zhuji_mask.png",
			"grass": "res://assets/scenes/tiles/zhuji_grass.png",
			"road": "res://assets/scenes/tiles/zhuji_road.png",
			"forest": "res://assets/scenes/tiles/zhuji_forestfloor.png",
			"bands": {
				"east": "res://assets/scenes/tiles/zhuji_band_east_v2.png",
				"north": "res://assets/scenes/tiles/zhuji_band_north_v2.png",
			},
		},
		"wall_inset": {"north": 480.0, "west": 40.0, "south": 0.0, "east": 400.0},
		"ground_color": Color(0.12, 0.16, 0.21, 1.0),
		"border_color": Color(0.35, 0.45, 0.62, 1.0),
		"desc": "寒雾锁谷、冷杉与石径交错。药力比青岚野更厚，灵兽与野修也更难缠；南口与青岚野相接。",
		"core_boss_id": "world_core_zhuji",
		"core_reward": {"mat_pojing_di_jiedan": 1},
		"core_where": "云隐谷谷心",
		## 大世界野修没有阵旗 / 气环 / 两仪的状态机，冲和界三只的专属功法不能直接给野修；
		## 先用凡界三只的通用招式，等大世界支持专属系统后再换。
		"skill_pool_bosses": ["boss_huyao", "boss_01", "boss_01_c"],
	},
	{
		"region_id": REGION_JIEDAN,
		"name": "赤金丹霞",
		"realm": "结丹",
		"order": 3,
		"unlocked": true,
		"rect": Rect2(-6000.0, -4000.0, 6000.0, 4000.0),
		"map_image": "res://assets/ui/facilities/world_map_jiedan.png",
		"terrain": {
			"mask": "res://assets/scenes/tiles/jiedan_mask.png",
			"grass": "res://assets/scenes/tiles/jiedan_grass.png",
			"road": "res://assets/scenes/tiles/jiedan_road.png",
			"forest": "res://assets/scenes/tiles/jiedan_forestfloor.png",
			"bands": {
				"west": "res://assets/scenes/tiles/jiedan_band_west_v2.png",
				"north": "res://assets/scenes/tiles/jiedan_band_north_v2.png",
			},
			## 东沿与云隐谷相接：没有林带，铺一条竖向地面过渡（丹霞红 → 云隐冷绿）
			"seam_vertical": "res://assets/scenes/tiles/seam_v_jiedan_zhuji_v2.png",
			## 丹霞地表本身很平，大尺度明暗拉大一档，别让 512px 格网露出来
			"macro_scale": 1150.0,
			"macro_amount": 0.15,
		},
		"wall_inset": {"north": 480.0, "west": 400.0, "south": 355.0, "east": 0.0},
		"ground_color": Color(0.38, 0.16, 0.08, 1.0),
		"border_color": Color(0.86, 0.52, 0.22, 1.0),
		"desc": "赤岩如霞、金纹入地的丹霞绝谷。地火在岩缝里烧了千年，草木皆染赤金；东沿与云隐谷相接，谷心盘着这片大地的火麟。",
		"core_boss_id": "world_core_jiedan",
		"core_reward": {"mat_pojing_di_yuanying": 1},
		"core_where": "霞心",
		"skill_pool_bosses": ["boss_03", "boss_03_b", "boss_03_c"],
	},
	{
		"region_id": REGION_YUANYING,
		"name": "幽冥灵墟",
		"realm": "元婴",
		"order": 4,
		"unlocked": true,
		"rect": Rect2(-6000.0, 0.0, 6000.0, 4000.0),
		"map_image": "res://assets/ui/facilities/world_map_youming.png",
		"terrain": {
			"mask": "res://assets/scenes/tiles/youming_mask.png",
			"grass": "res://assets/scenes/tiles/youming_grass.png",
			"road": "res://assets/scenes/tiles/youming_road.png",
			"forest": "res://assets/scenes/tiles/youming_forestfloor.png",
			"bands": {
				"west": "res://assets/scenes/tiles/youming_band_west_v2.png",
				"south": "res://assets/scenes/tiles/youming_band_south_v2.png",
			},
			## 北接赤金丹霞、东邻青岚野：两条接缝都用地面对渡条，不种墙
			"seam_horizontal": "res://assets/scenes/tiles/seam_h_jiedan_youming_v2.png",
			"seam_vertical": "res://assets/scenes/tiles/seam_v_lianqi_youming_v2.png",
			"decal_tint": Color(0.58, 0.66, 0.78, 1.0),
			"decal_strength": 0.58,
			"macro_scale": 1650.0,
			"macro_amount": 0.14,
		},
		"wall_inset": {"north": 0.0, "west": 400.0, "south": 355.0, "east": 0.0},
		"ground_color": Color(0.09, 0.075, 0.13, 1.0),
		"border_color": Color(0.52, 0.40, 0.74, 1.0),
		"desc": "阴雾覆墟、残碑如林。灵墟深处只剩幽火与兽影；北接丹霞，东邻青岚，元婴修士可在此采药猎兽。",
		"core_boss_id": "world_core_yuanying",
		"core_reward": {"mat_pojing_di_huashen": 1},
		"core_where": "九天门",
		"skill_pool_bosses": ["boss_03", "boss_03_b", "boss_03_c"],
		## 区域中央的九天门：纯景观，不参与战斗 / 不挡路
		"landmark": {
			"texture": "res://assets/scenes/youming_gate.png",
			"pos": Vector2.ZERO,
			"scale": 0.46,
			"glow": Color(0.42, 0.78, 0.86, 1.0),
		},
	},
	{
		"region_id": REGION_HUASHEN,
		"name": "九天之上",
		"realm": "化神",
		"order": 5,
		## 这块地不吃 unlocked：开没开由 CharacterData.huashen_gate_opened 决定
		## （见上面的 is_region_open）。unlocked 留 false 只是漏读时的安全兜底。
		"unlocked": false,
		"rect": Rect2(-12000.0, -4000.0, 6000.0, 4000.0),
		## 地貌（2026-11-06 出图）：中央玉台（坛在下面）→ 云海 → 贴边的雾岩岛缘。
		## 三套 tile 与遮罩都由 tools/bake_jiutian_mask.py + tools/prep_region_tiles.py
		## + sprite_gen background-tile 烘出来，遮罩的台子/甬道位置是**现读** portal/spawn 坐标算的，
		## 所以改了那两个坐标必须重跑一次 bake_jiutian_mask，不然玉台会朝旧位置指。
		"terrain": {
			"mask": "res://assets/scenes/tiles/jiutian_mask.png",
			"grass": "res://assets/scenes/tiles/jiutian_cloudsea.png",
			"road": "res://assets/scenes/tiles/jiutian_terrace.png",
			"forest": "res://assets/scenes/tiles/jiutian_mistrock.png",
			## 仙气：贴花是这场的主题，不是点缀，所以强度和保底都比其它区高一档。
			## 玉台上会压掉大半（台子是踩出来的石面，雾在脚边绕而不是把字糊住）。
			"decal_tint": Color(0.74, 0.72, 0.86, 1.0),
			"decal_strength": 0.72,
			"macro_scale": 1900.0,
			"macro_amount": 0.10,
		},
		## 岛缘带宽 240 世界像素，墙再往里收一点：玩家走到云海边就停，
		## 外面那段碎岩是看的，不是踩着掉下去的。
		"wall_inset": {"north": 400.0, "west": 400.0, "south": 400.0, "east": 400.0},
		"ground_color": Color(0.13, 0.115, 0.175, 1.0),
		"border_color": Color(0.62, 0.56, 0.80, 1.0),
		"desc": "第一篇章的终点。九天门开后方可进入；中央化神坛可突破化神，东侧传送门可撤离。",
		"core_boss_id": "",
		"core_reward": {},
		"skill_pool_bosses": [],
	},
]

# ===== 灵兽 =====
## 两种灵兽分别掉不同皮毛：锋牙兽→攻击方向符箓，坚甲兽→防御方向符箓
const BEASTS: Dictionary = {
	"fengya": {
		"name": "锋牙兽",
		"visual_id": "world_beast_fengya",
		"hide_id": "mat_ruishoupi",
		"max_hp": 180.0,
		"attack_power": 20.0,
		"move_speed": 108.0,
		"aggro_range": 330.0,
		"leash_range": 720.0,
		"melee_range": 78.0,
		"melee_angle": 110.0,
		"melee_coeff": 0.70,
		"attack_name": "裂牙扑咬",
		"melee_fx": "skill_beast_bite",
		"body_radius": 28.0,
		"hide_min": 2,
		"hide_max": 4,
	},
	"jianjia": {
		"name": "坚甲兽",
		"visual_id": "world_beast_jianjia",
		"hide_id": "mat_jianshoupi",
		"max_hp": 260.0,
		"attack_power": 22.0,
		"move_speed": 86.0,
		"aggro_range": 300.0,
		"leash_range": 720.0,
		"melee_range": 84.0,
		"melee_angle": 120.0,
		"melee_coeff": 0.65,
		"attack_name": "甲背撞击",
		"melee_fx": "skill_beast_charge",
		"body_radius": 32.0,
		"hide_min": 2,
		"hide_max": 3,
	},
	# ===== 云隐谷（筑基）灵兽：同造型、同机制，数值按筑基玩家反推（2026-10-28）=====
	## 基准：筑基后期 + 六件筑基装 ≈ 气血 340 / 物攻 32；小怪偏精英，挨 ~20 下会死。
	"zj_fengya": {
		"name": "云隐锋牙兽",
		"visual_id": "world_beast_fengya",
		"hide_id": "mat_zj_ruishoupi",
		"max_hp": 620.0,
		"attack_power": 22.0,
		"move_speed": 112.0,
		"aggro_range": 360.0,
		"leash_range": 780.0,
		"melee_range": 82.0,
		"melee_angle": 110.0,
		"melee_coeff": 0.70,
		"attack_name": "裂牙扑咬",
		"melee_fx": "skill_beast_bite",
		"body_radius": 28.0,
		"hide_min": 2,
		"hide_max": 4,
	},
	"zj_jianjia": {
		"name": "云隐坚甲兽",
		"visual_id": "world_beast_jianjia",
		"hide_id": "mat_zj_jianshoupi",
		"max_hp": 780.0,
		"attack_power": 24.0,
		"move_speed": 90.0,
		"aggro_range": 330.0,
		"leash_range": 780.0,
		"melee_range": 88.0,
		"melee_angle": 120.0,
		"melee_coeff": 0.65,
		"attack_name": "甲背撞击",
		"melee_fx": "skill_beast_charge",
		"body_radius": 32.0,
		"hide_min": 2,
		"hide_max": 3,
	},
	# ===== 赤金丹霞（结丹）灵兽：同造型同机制，数值按结丹标准档（279 血 / 99 物攻 /
	# 313~376 DPS，2026-10-29 定标）反推：约 6~8 刀一只，挨 ~9 下会死 =====
	"jd_fengya": {
		"name": "赤鬃锋牙兽",
		"visual_id": "world_beast_fengya",
		"hide_id": "mat_jd_ruishoupi",
		"max_hp": 1900.0,
		"attack_power": 30.0,
		"move_speed": 116.0,
		"aggro_range": 380.0,
		"leash_range": 820.0,
		"melee_range": 84.0,
		"melee_angle": 110.0,
		"melee_coeff": 0.70,
		"attack_name": "裂牙扑咬",
		"melee_fx": "skill_beast_bite",
		"body_radius": 30.0,
		"hide_min": 2,
		"hide_max": 4,
	},
	"jd_jianjia": {
		"name": "赤岩坚甲兽",
		"visual_id": "world_beast_jianjia",
		"hide_id": "mat_jd_jianshoupi",
		"max_hp": 2400.0,
		"attack_power": 32.0,
		"move_speed": 92.0,
		"aggro_range": 350.0,
		"leash_range": 820.0,
		"melee_range": 90.0,
		"melee_angle": 120.0,
		"melee_coeff": 0.65,
		"attack_name": "甲背撞击",
		"melee_fx": "skill_beast_charge",
		"body_radius": 34.0,
		"hide_min": 2,
		"hide_max": 3,
	},
	# ===== 幽冥灵墟（元婴）灵兽：修为/数值按元婴初期道器 +6 面板（447 血 / 183 物攻 /
	# 581~794 DPS）反推；约 6~8 刀一只，挨 ~10~12 下会死 =====
	"yy_fengya": {
		"name": "幽冥锋牙兽",
		"visual_id": "world_beast_youming_fengya",
		"hide_id": "mat_yy_ruishoupi",
		"max_hp": 3400.0,
		"attack_power": 58.0,
		"move_speed": 120.0,
		"aggro_range": 400.0,
		"leash_range": 860.0,
		"melee_range": 86.0,
		"melee_angle": 110.0,
		"melee_coeff": 0.70,
		"attack_name": "幽牙扑咬",
		"melee_fx": "skill_beast_bite",
		"body_radius": 30.0,
		"hide_min": 2,
		"hide_max": 4,
	},
	"yy_jianjia": {
		"name": "幽冥坚甲兽",
		"visual_id": "world_beast_youming_jianjia",
		"hide_id": "mat_yy_jianshoupi",
		"max_hp": 4200.0,
		"attack_power": 62.0,
		"move_speed": 94.0,
		"aggro_range": 370.0,
		"leash_range": 860.0,
		"melee_range": 92.0,
		"melee_angle": 120.0,
		"melee_coeff": 0.65,
		"attack_name": "墟甲撞击",
		"melee_fx": "skill_beast_charge",
		"body_radius": 34.0,
		"hide_min": 2,
		"hide_max": 3,
	},
}

# ===== 核心首领（通用占位）=====
## 一次性击杀：杀掉后永久留在 CharacterData.secret_world.core_kills，不再刷新。
## 首杀奖励直接入包（不是地面掉落），并且受死亡回滚保护 —— 见 secret_world.gd。
## 青岚古猿技能组（2026-10-24 用户要求丰富）
## form_id 复用 MoveDB 现有招式形态（不新增美术 / 玩家功法）；
## range / min_range / ideal_range 用于 BOSS 选招；damage_scale 乘在 attack_power 上；
## windup 是前摇秒数；phase=2 表示二阶段才解锁。
const CORE_SKILLS: Array = [
	{
		"id": "ape_slam", "anim": "slam", "name": "裂地重锤", "form_id": "form_smash",
		"fx_id": "skill_ape_slam",
		"desc": "双拳砸地，近身圆形碎石冲击。",
		"attack_kind": "physical_melee", "phase": 1,
		"min_range": 0.0, "range": 190.0, "ideal_range": 100.0,
		"cooldown": 5.0, "damage_scale": 0.85, "windup": 0.75, "weight": 1.2,
	},
	{
		"id": "ape_boulder", "anim": "throw", "name": "崩石投掷", "form_id": "form_arrow",
		"fx_id": "skill_ape_boulder",
		"desc": "拔起苔石掷向远处，物理投掷、可弹反。",
		"attack_kind": "physical_projectile", "phase": 1,
		"min_range": 160.0, "range": 560.0, "ideal_range": 340.0,
		"cooldown": 4.5, "damage_scale": 0.65, "windup": 0.6, "weight": 1.0,
	},
	{
		"id": "ape_volley", "anim": "volley", "name": "乱石飞掷", "form_id": "form_arrow_volley",
		"fx_id": "skill_ape_volley",
		"desc": "扇形连掷五块碎石，逐块可弹反。",
		"attack_kind": "physical_projectile", "phase": 1,
		"min_range": 220.0, "range": 560.0, "ideal_range": 380.0,
		"cooldown": 7.0, "damage_scale": 0.22, "windup": 0.8, "weight": 0.9,
	},
	{
		"id": "ape_quake", "anim": "quake", "name": "山崩地裂", "form_id": "form_smash",
		"fx_id": "skill_ape_quake",
		"desc": "双拳连砸，震起大范围木属性冲击。",
		"attack_kind": "elemental", "damage_element": "wood", "phase": 2,
		"min_range": 0.0, "range": 300.0, "ideal_range": 120.0,
		"cooldown": 10.0, "damage_scale": 1.0, "windup": 0.95, "weight": 1.5,
	},
	{
		"id": "ape_orb", "anim": "orb", "name": "青岚灵爆", "form_id": "form_element_orb",
		"fx_id": "skill_ape_orb",
		"desc": "凝聚青岚灵球掷出，法术伤害、不可弹反。",
		"attack_kind": "elemental", "damage_element": "wood", "phase": 2,
		"min_range": 180.0, "range": 620.0, "ideal_range": 380.0,
		"cooldown": 8.0, "damage_scale": 0.9, "windup": 0.8, "weight": 1.1,
	},
]

const CORE_BOSS: Dictionary = {
	"node_id": "lianqi_core_boss",
	"name": "青岚古猿",
	"visual_id": "world_core_lianqi",
	"max_hp": 2200.0,
	"attack_power": 50.0,
	"move_speed": 96.0,
	"aggro_range": 900.0,
	"leash_range": 1650.0,
	"melee_range": 150.0,
	"melee_angle": 130.0,
	"melee_coeff": 0.90,
	"attack_name": "古猿裂地击",
	"windup": 0.85,
	"melee_fx": "skill_ape_swipe",
	"body_radius": 44.0,
	"core_skills": CORE_SKILLS,
	"reward": {"mat_pojing_di_zhuji": 1},
	## 核心首领死亡时掉落（每次击杀；核心只击杀一次）
	"equipment_drops": ["eq_tengjia"],
}

# ===== 云隐谷核心首领：云隐苍角（2026-10-29 用户定）=====
## 谷心苔石古鹿。主线规格：2 阶段、8 式、苔甲三片、雾隐二阶段、完整图鉴/掉落。
## 伤害反推：筑基玩家约 340 血 / 32 攻；苍角 62 攻，招式 0.55~1.0×，二阶段 ×2。
## 首杀给「结丹底髓」（半枚），与冲和界第三位的天髓熔铸成结丹破境晶；专属掉落苍角甲。
const CORE_SKILLS_ZHUJI: Array = [
	{
		"id": "stag_gore", "anim": "gore", "name": "角撞·裂岩", "form_id": "form_blade_dash",
		"fx_id": "skill_stag_gore",
		"desc": "低头蓄力后向前撞出，物理直线，可弹反。",
		"attack_kind": "physical_melee", "phase": 1,
		"min_range": 0.0, "range": 360.0, "ideal_range": 210.0,
		"cooldown": 6.0, "damage_scale": 0.95, "windup": 0.78, "weight": 1.4,
	},
	{
		"id": "stag_stomp", "anim": "stomp", "name": "踏地·苔震", "form_id": "form_smash",
		"fx_id": "skill_stag_stomp",
		"desc": "前蹄砸地，近身圆形震荡。",
		"attack_kind": "physical_melee", "phase": 1,
		"min_range": 0.0, "range": 220.0, "ideal_range": 90.0,
		"cooldown": 5.0, "damage_scale": 0.80, "windup": 0.80, "weight": 1.2,
	},
	{
		"id": "stag_mist", "anim": "mist", "name": "雾吐·寒潮", "form_id": "form_slash_single",
		"fx_id": "skill_stag_mist", "angle": 90.0,
		"desc": "吐出一片寒雾，前方扇形法术，命中挂滞气。",
		"attack_kind": "elemental", "damage_element": "water", "phase": 1,
		"min_range": 0.0, "range": 300.0, "ideal_range": 180.0,
		"cooldown": 6.5, "damage_scale": 0.65, "windup": 0.90, "weight": 1.0,
	},
	{
		"id": "stag_roots", "anim": "roots", "name": "古根·缠足", "form_id": "form_smash",
		"fx_id": "skill_stag_stomp",
		"desc": "在玩家脚下催生根须，延迟后束缚。",
		"attack_kind": "elemental", "damage_element": "wood", "phase": 1,
		"min_range": 0.0, "range": 360.0, "ideal_range": 220.0,
		"cooldown": 8.0, "damage_scale": 0.55, "windup": 0.90, "weight": 0.9,
	},
	{
		"id": "stag_rocks", "anim": "rocks", "name": "落石·垂枝", "form_id": "form_arrow_volley",
		"fx_id": "skill_stag_volley",
		"desc": "抖落角上碎石，扇形投掷，可弹反。",
		"attack_kind": "physical_projectile", "phase": 1,
		"min_range": 180.0, "range": 560.0, "ideal_range": 360.0,
		"cooldown": 6.0, "damage_scale": 0.22, "windup": 0.80, "weight": 1.0,
	},
	{
		"id": "stag_sweep", "anim": "sweep", "name": "角扫·断雾", "form_id": "form_slash_single",
		"fx_id": "skill_stag_sweep", "angle": 150.0,
		"desc": "横甩巨角，宽扇物理，绕背比后退安全。",
		"attack_kind": "physical_melee", "phase": 1,
		"min_range": 0.0, "range": 240.0, "ideal_range": 100.0,
		"cooldown": 4.5, "damage_scale": 0.80, "windup": 0.62, "weight": 1.3,
	},
	{
		"id": "stag_miststep", "anim": "miststep", "name": "雾步·迷踪", "form_id": "form_blade_dash",
		"fx_id": "skill_stag_gore", "angle": 100.0,
		"desc": "踏入雾中换位，从侧后撞出；二阶段专属。",
		"attack_kind": "elemental", "damage_element": "water", "phase": 2,
		"min_range": 120.0, "range": 460.0, "ideal_range": 280.0,
		"cooldown": 9.0, "damage_scale": 0.70, "windup": 0.55, "weight": 1.0,
	},
	{
		"id": "stag_roar", "anim": "roar", "name": "鹿鸣·山回", "form_id": "form_smash",
		"fx_id": "skill_stag_quake",
		"desc": "仰首长鸣，大范围木属性回声；二阶段专属。",
		"attack_kind": "elemental", "damage_element": "wood", "phase": 2,
		"min_range": 0.0, "range": 340.0, "ideal_range": 80.0,
		"cooldown": 11.0, "damage_scale": 1.0, "windup": 1.0, "weight": 1.2,
	},
]

const CORE_BOSS_ZHUJI: Dictionary = {
	"node_id": "zhuji_core_boss",
	"name": "云隐苍角",
	"visual_id": "world_core_zhuji",
	## 专属场景（WorldEnemy 子类 + 苔甲/雾隐机制）
	"scene": "res://scenes/world/zhuji_core_stag.tscn",
	"max_hp": 4000.0,
	"attack_power": 62.0,
	"move_speed": 96.0,
	"aggro_range": 900.0,
	"leash_range": 1650.0,
	"melee_range": 170.0,
	"melee_angle": 130.0,
	"melee_coeff": 0.75,
	"attack_name": "苍角·裂岩",
	"windup": 0.82,
	"melee_fx": "skill_stag_gore",
	"body_radius": 58.0,
	"core_skills": CORE_SKILLS_ZHUJI,
	"reward": {"mat_pojing_di_jiedan": 1},
	"equipment_drops": ["eq_cangjiao_jia"],
	## 重战箱庭：谷心石圈贴花在场地中心，本体也站在圈心
	"arena_spawn": Vector2.ZERO,
}

# ===== 赤金丹霞核心首领：赤金火麟（2026-10-29 用户定）=====
## 丹霞地火所化的四足火麟，日轮悬在肩后。
## 数值：结丹初期标准档 279 血 / 99 物攻 / 313~376 DPS（10-29 定标）反推 ——
##   20,000 血 ≈ 100~115 秒有效输出（2026-11-01 用户上调）；100 攻，主招过抗后 64~99。
## 独有机制：霞印（火招命中叠层，3 层日蚀；弹反清 1 层；印记图形绕玩家显示）。
## 二阶段：日轮离体落到场心，外圈灼烧 + 每 6 秒脉冲叠印，并解锁日蚀/陨日。
const CORE_SKILLS_JIEDAN: Array = [
	{
		"id": "qilin_gore", "anim": "charge", "name": "火麟·裂岩冲", "form_id": "form_blade_dash",
		"fx_id": "skill_qilin_gore",
		"desc": "低头蓄力后向前撞出，沿途留下燃烧的蹄印。物理直线，可弹反。",
		"attack_kind": "physical_melee", "phase": 1,
		"min_range": 0.0, "range": 400.0, "ideal_range": 240.0,
		"cooldown": 6.5, "damage_scale": 0.95, "windup": 0.78, "weight": 1.5,
	},
	{
		"id": "qilin_stomp", "anim": "stomp", "name": "踏霞·地火", "form_id": "form_smash",
		"fx_id": "skill_qilin_stomp",
		"desc": "前蹄砸地，近身圆形震荡并溅起火屑。命中叠 1 层霞印。",
		"attack_kind": "physical_melee", "phase": 1,
		"min_range": 0.0, "range": 250.0, "ideal_range": 100.0,
		"cooldown": 5.5, "damage_scale": 0.80, "windup": 0.85, "weight": 1.3,
		"mark": 1,
	},
	{
		"id": "qilin_rain", "anim": "rain", "name": "火雨·焚野", "form_id": "form_smash",
		"fx_id": "skill_qilin_rain",
		"desc": "昂首召下六道火雨砸向玩家周围，落点延迟爆开。命中叠 1 层霞印。",
		"attack_kind": "elemental", "damage_element": "fire", "phase": 1,
		"min_range": 140.0, "range": 660.0, "ideal_range": 380.0,
		"cooldown": 9.0, "damage_scale": 0.38, "windup": 0.95, "weight": 1.1,
		"mark": 1,
	},
	{
		"id": "qilin_orb", "anim": "sunburst", "name": "阳炎·流火", "form_id": "form_element_orb",
		"fx_id": "skill_qilin_orb",
		"desc": "吐出一颗缓慢的阳炎火球，飞到近处炸开。法术伤害，不可弹反。命中叠 1 层霞印。",
		"attack_kind": "elemental", "damage_element": "fire", "phase": 1,
		"min_range": 180.0, "range": 660.0, "ideal_range": 400.0,
		"cooldown": 8.0, "damage_scale": 0.85, "windup": 0.80, "weight": 1.0,
		"mark": 1,
	},
	{
		"id": "qilin_claw", "anim": "combo", "name": "赤金·三连", "form_id": "form_slash_single",
		"fx_id": "skill_qilin_claw",
		"desc": "贴身后连续三爪，每爪都可弹反；三段全吃必中霞印。",
		"attack_kind": "physical_melee", "phase": 1,
		"min_range": 0.0, "range": 220.0, "ideal_range": 90.0,
		"cooldown": 7.0, "damage_scale": 0.38, "windup": 0.55, "weight": 1.2,
	},
	{
		"id": "qilin_ring", "anim": "ring", "name": "日冕·环裂", "form_id": "form_smash",
		"fx_id": "skill_qilin_ring",
		"desc": "日轮震出一圈火环向外扩，越过身体时灼伤。法术伤害，可穿环躲。命中叠 1 层霞印。",
		"attack_kind": "elemental", "damage_element": "fire", "phase": 1,
		"min_range": 0.0, "range": 460.0, "ideal_range": 200.0,
		"cooldown": 8.5, "damage_scale": 0.70, "windup": 1.0, "weight": 1.1,
		"mark": 1,
	},
	{
		"id": "qilin_eclipse", "anim": "eclipse", "name": "日蚀·坠光", "form_id": "form_element_orb",
		"fx_id": "skill_qilin_eclipse",
		"desc": "场心日轮锁定玩家，落下一道日蚀光柱。二阶段专属，必须离开落点。",
		"attack_kind": "elemental", "damage_element": "fire", "phase": 2,
		"min_range": 0.0, "range": 720.0, "ideal_range": 320.0,
		"cooldown": 10.0, "damage_scale": 1.15, "windup": 1.3, "weight": 1.3,
		"mark": 1,
	},
	{
		"id": "qilin_meteor", "anim": "meteor", "name": "金乌·陨日", "form_id": "form_smash",
		"fx_id": "skill_qilin_meteor",
		"desc": "召来金乌坠日，大范围落地并留下燃烧的坑。二阶段专属。",
		"attack_kind": "elemental", "damage_element": "fire", "phase": 2,
		"min_range": 0.0, "range": 720.0, "ideal_range": 300.0,
		"cooldown": 13.0, "damage_scale": 1.45, "windup": 1.5, "weight": 1.2,
		"mark": 1,
	},
]

## ===== 幽冥灵墟核心首领：镇墟石犼（2026-10-31 用户实装）=====
## 一只石胎守墓兽，看不见，只追踪「最后一次响声的位置」。
## 数值按元婴初期 +6 道器（447 血 / 183 物攻 / 约 500~580 有效 DPS）反推：
##   44,000 血 ≈ 110~130 秒有效输出（2026-11-01 用户要求血量翻倍）；112 攻，主招过抗后 56~113，元婴档 4~6 下死。
## 独有机制：闻声（足迹/出手留下声点，大扑与吐息只打旧点；石碣可引撞）。
## 二阶段：封眼石带裂开，震塌两根石碣，听觉过敏 + 回声定位；长吼后自聋 2 秒。
const CORE_SKILLS_YUANYING: Array = [
	{
		"id": "shihou_pounce", "anim": "pounce", "name": "盲扑", "form_id": "form_smash",
		"fx_id": "skill_shihou_pounce",
		"desc": "伏低后扑向最后声点；撞上石碣会自己硬直。",
		"attack_kind": "physical_melee", "phase": 1,
		"min_range": 0.0, "range": 520.0, "ideal_range": 240.0,
		"cooldown": 6.5, "damage_scale": 0.90, "windup": 0.72, "weight": 1.2,
		"dash": 420.0,
	},
	{
		"id": "shihou_claw", "anim": "claw", "name": "裂石爪", "form_id": "form_slash_single",
		"fx_id": "skill_shihou_claw",
		"desc": "一记裂石爪，三道爪痕同帧落下；物理可弹反。",
		"attack_kind": "physical_melee", "phase": 1,
		"min_range": 0.0, "range": 230.0, "ideal_range": 90.0,
		"cooldown": 5.5, "damage_scale": 1.05, "windup": 0.45, "weight": 1.3,
		"hits": 1,
	},
	{
		"id": "shihou_slam", "anim": "slam", "name": "震地", "form_id": "form_smash",
		"fx_id": "skill_shihou_slam",
		"desc": "前爪砸地，震波向四周扩散，并留下 3 秒裂地。",
		"attack_kind": "physical_melee", "phase": 1,
		"min_range": 0.0, "range": 270.0, "ideal_range": 90.0,
		"cooldown": 7.0, "damage_scale": 0.85, "windup": 0.85, "weight": 1.6,
	},
	{
		"id": "shihou_breath", "anim": "breath", "name": "闻声吐息", "form_id": "form_slash_single",
		"fx_id": "skill_shihou_breath",
		"desc": "朝最后声点吐出一道尘息；放完后它会短暂自聋，正是换位窗口。",
		"attack_kind": "elemental", "damage_element": "wind", "phase": 1,
		"min_range": 160.0, "range": 560.0, "ideal_range": 380.0,
		"cooldown": 8.5, "damage_scale": 0.80, "windup": 0.90, "weight": 1.4,
	},
	{
		"id": "shihou_tail", "anim": "tail_sweep", "name": "石尾扫", "form_id": "form_smash",
		"fx_id": "skill_shihou_tail",
		"desc": "贴背时原地甩尾一圈；物理可弹反。",
		"attack_kind": "physical_melee", "phase": 1,
		"min_range": 0.0, "range": 240.0, "ideal_range": 70.0,
		"cooldown": 6.0, "damage_scale": 0.70, "windup": 0.55, "weight": 1.5,
	},
	{
		"id": "shihou_charge", "anim": "charge", "name": "崩山撞", "form_id": "form_smash",
		"fx_id": "skill_shihou_charge",
		"desc": "沿最后声点长距离冲撞，撞碎石碣会硬直；撞人重击退。",
		"attack_kind": "physical_melee", "phase": 2,
		"min_range": 240.0, "range": 900.0, "ideal_range": 500.0,
		"cooldown": 10.0, "damage_scale": 1.30, "windup": 1.00, "weight": 1.8,
		"dash": 900.0,
	},
]

const CORE_BOSS_YUANYING: Dictionary = {
	"node_id": "yuanying_core_boss",
	"name": "镇墟石犼",
	"visual_id": "world_core_shihou",
	"scene": "res://scenes/world/youming_core_shihou.tscn",
	"max_hp": 44000.0,
	"attack_power": 112.0,
	"move_speed": 105.0,
	"aggro_range": 950.0,
	"leash_range": 1750.0,
	"melee_range": 200.0,
	"melee_angle": 140.0,
	"melee_coeff": 0.82,
	"attack_name": "盲拍",
	"windup": 0.82,
	"melee_fx": "skill_shihou_swipe",
	"body_radius": 64.0,
	"core_skills": CORE_SKILLS_YUANYING,
	"reward": {"mat_pojing_di_huashen": 1},
	"equipment_drops": ["eq_zhenxu_jia"],
	"arena_spawn": Vector2.ZERO,
}

const CORE_BOSS_JIEDAN: Dictionary = {
	"node_id": "jiedan_core_boss",
	"name": "赤金火麟",
	"visual_id": "world_core_jiedan",
	## 专属场景（霞印 / 日轮当空 / 外圈灼烧）
	"scene": "res://scenes/world/jiedan_core_qilin.tscn",
	"max_hp": 20000.0,
	"attack_power": 100.0,
	"move_speed": 104.0,
	"aggro_range": 950.0,
	"leash_range": 1750.0,
	"melee_range": 190.0,
	"melee_angle": 130.0,
	"melee_coeff": 0.80,
	"attack_name": "火麟裂岩击",
	"windup": 0.85,
	"melee_fx": "skill_qilin_swipe",
	"body_radius": 62.0,
	"core_skills": CORE_SKILLS_JIEDAN,
	## 首杀奖励：元婴底髓（半枚，与赤霄界第三位的元婴天髓熔铸）
	"reward": {"mat_pojing_di_yuanying": 1},
	"equipment_drops": ["eq_huolin_jia"],
	"arena_spawn": Vector2.ZERO,
}

# ===== 野外修士 =====
## 稀有：只在资源密集区刷新，每个区域最多两个槽位，到点后按概率出现。
## 外观直接复用主角美术（用户 2026-10-23 定）。
const CULTIVATOR: Dictionary = {
	"name": "野修",
	"visual_id": "player_liqingyun",
	"max_hp": 520.0,
	"attack_power": 42.0,
	"move_speed": 122.0,
	"aggro_range": 520.0,
	"leash_range": 940.0,
	"skill_count": 4,
	"cast_coeff": 0.35,
	## 携带法宝（2026-10-24 用户定）：出生时**必定**抽一件；携带后**死亡必掉**
	## 2026-10-25 新增逐电环：一次性 30 灵力，3 秒移速 800，冷却 30 秒
	"treasure_pool": ["tr_ningshuipei", "tr_zhudianhuan", "tr_jinbu_zhuang"],
	"treasure_carry_chance": 1.0,
	## 野修自己的灵力池：凝水佩完整引导 8 秒要 80；逐电环每次 30
	"treasure_mana_max": 100.0,
	## 血量降到这个比例以下才会主动使用携带法宝
	"treasure_trigger_hp_ratio": 0.55,
}

## 云隐谷（筑基）野修：同构上浮一档（2026-10-28 访谈：气血 1550 / 物攻 46；
## 筑基面板 ≈ 气血 340 / 物攻 32，挨 ~10 下会死）。法宝与掉落沿用同一套。
const CULTIVATOR_ZHUJI: Dictionary = {
	"name": "云隐野修",
	"visual_id": "player_liqingyun",
	"max_hp": 1550.0,
	"attack_power": 46.0,
	"move_speed": 128.0,
	"aggro_range": 560.0,
	"leash_range": 980.0,
	"skill_count": 4,
	"cast_coeff": 0.35,
	"treasure_pool": ["tr_ningshuipei", "tr_zhudianhuan", "tr_jinbu_zhuang", "tr_duannian_ling", "tr_jijia_pei", "tr_huifeng_dai"],
	"treasure_carry_chance": 1.0,
	"treasure_mana_max": 100.0,
	"treasure_trigger_hp_ratio": 0.55,
}

## 赤金丹霞（结丹）野修：按结丹标准档（279 血 / 99 物攻）反推。
## 血量取 4500（约 15 秒站桩输出），物攻 60（过抗后约 45，挨 6 下）。
## 功法池走赤霄界三只的招式（见区域表 skill_pool_bosses），法宝与掉落沿用同一套。
const CULTIVATOR_JIEDAN: Dictionary = {
	"name": "丹霞野修",
	"visual_id": "player_liqingyun",
	"max_hp": 4500.0,
	"attack_power": 60.0,
	"move_speed": 132.0,
	"aggro_range": 600.0,
	"leash_range": 1020.0,
	"skill_count": 4,
	"cast_coeff": 0.35,
	"treasure_pool": ["tr_ningshuipei", "tr_zhudianhuan", "tr_jinbu_zhuang", "tr_duannian_ling", "tr_xuming_deng", "tr_jijia_pei", "tr_huifeng_dai", "tr_xuesi_yin", "tr_huanwei_jue"],
	"treasure_carry_chance": 1.0,
	"treasure_mana_max": 100.0,
	"treasure_trigger_hp_ratio": 0.55,
}

## 幽冥灵墟（元婴）野修：按元婴初期道器 +6（447 血 / 183 物攻 / 581~794 DPS）反推。
## 血量取 8000（约 14 秒站桩输出），物攻 105（过抗后约 70，挨 6~7 下）。
## 功法池沿用赤霄界三只的招式（见区域表 skill_pool_bosses），法宝与掉落沿用同一套。
const CULTIVATOR_YUANYING: Dictionary = {
	"name": "幽冥野修",
	"visual_id": "player_liqingyun",
	"max_hp": 8000.0,
	"attack_power": 105.0,
	"move_speed": 136.0,
	"aggro_range": 640.0,
	"leash_range": 1060.0,
	"skill_count": 4,
	"cast_coeff": 0.35,
	"treasure_pool": ["tr_ningshuipei", "tr_zhudianhuan", "tr_jinbu_zhuang", "tr_duannian_ling", "tr_xuming_deng", "tr_shixi_zhui", "tr_jijia_pei", "tr_huifeng_dai", "tr_xuesi_yin", "tr_huanwei_jue"],
	"treasure_carry_chance": 1.0,
	"treasure_mana_max": 100.0,
	"treasure_trigger_hp_ratio": 0.55,
}

# ===== 练气区域布置 =====
## 坐标以**区域中心**为原点：x ∈ [-3000, 3000]，y ∈ [-2000, 2000]
## 进图时 secret_world 统一平移到该区域在世界里的 rect 中心 → 练气区落在苍澜大陆右下角
## 入口（传送门）在东南角，核心首领改到整张地图正中央（2026-10-24 用户定）。
## spawn_offset：出生点相对传送门的偏移（传送门贴在右下角，出生点往西北挪）
const LIANQI_CONTENT: Dictionary = {
	"portal": {"pos": Vector2(2330.0, 1420.0), "spawn_offset": Vector2(-220.0, -150.0)},
	"core_boss": {"pos": Vector2.ZERO},

	## 森林灵田：击杀本区域核心首领后才会出现（用户 2026-10-23 定）
	## 位置贴着传送门北侧，出传送门走几步就到。生成时是九块**荒地**，
	## 玩家站上去施展「猛虎踏地」才开垦；整片按 cols × rows 摆，
	## pos 是整片田的中心，spacing 是地块中心距 —— 地块本体由 FarmPlot 画。
	"farm": {
		"node_id_prefix": "lq_farm",
		"plot_base": 0,
		"pos": Vector2(1830.0, 1130.0),
		"cols": 3,
		"rows": 3,
		"spacing": Vector2(138.0, 100.0),
	},

	## 石台插剑（2026-11-12 彩蛋设施）：传送门正北约 340 世界像素，取走一次即**永久**消失。
	## ⚠ 落点三条硬约束，都在 probe_world_sword_shrine 里有断言：
	##   ① 与门同 x、y 更小 = 正上方，出门一抬头就看见；
	##   ② 间距 340 > 门 reach 120 + 台 reach 88 = 208，站在门边不会两样抢「最近交互」；
	##   ③ 灵田九格占 x 1640~2020 / y 995~1265，这里 x=2330 留了 310 像素余量，不压田。
	"reliquaries": [
		{"node_id": "lq_sword_shrine", "pos": Vector2(2330.0, 1080.0),
			"visual_id": "world_sword_shrine", "display_name": "问天剑",
			"reward_equipment": "eq_wentian_jian"},
	],

	## 铸神祭坛（2026-11-13）：每区一座。首次取铸神晶×1；化神后可再取铸神晶×1 + 补天石×7。
	"god_altars": [
		{"node_id": "lq_god_altar", "pos": Vector2(1500.0, 1550.0)},
	],

	## 5 种药材：气血 / 灵力 / 力量 / 法强 / 防御
	"herbs": [
		# 血参：西北
		{"node_id": "lq_herb_xuecao_1", "material": "mat_xuecao", "pos": Vector2(-1800.0, -1200.0)},
		{"node_id": "lq_herb_xuecao_2", "material": "mat_xuecao", "pos": Vector2(-1620.0, -1340.0)},
		{"node_id": "lq_herb_xuecao_3", "material": "mat_xuecao", "pos": Vector2(-1960.0, -1030.0)},
		# 蓝萤草：西南
		{"node_id": "lq_herb_lanying_1", "material": "mat_lanyingcao", "pos": Vector2(-1720.0, 1120.0)},
		{"node_id": "lq_herb_lanying_2", "material": "mat_lanyingcao", "pos": Vector2(-1540.0, 1280.0)},
		{"node_id": "lq_herb_lanying_3", "material": "mat_lanyingcao", "pos": Vector2(-1880.0, 950.0)},
		# 力元果：北中
		{"node_id": "lq_herb_liyuan_1", "material": "mat_liyuanguo", "pos": Vector2(-320.0, -1320.0)},
		{"node_id": "lq_herb_liyuan_2", "material": "mat_liyuanguo", "pos": Vector2(120.0, -1450.0)},
		{"node_id": "lq_herb_liyuan_3", "material": "mat_liyuanguo", "pos": Vector2(520.0, -1180.0)},
		# 法灵花：南中
		{"node_id": "lq_herb_faling_1", "material": "mat_falinghua", "pos": Vector2(180.0, 1220.0)},
		{"node_id": "lq_herb_faling_2", "material": "mat_falinghua", "pos": Vector2(500.0, 1400.0)},
		{"node_id": "lq_herb_faling_3", "material": "mat_falinghua", "pos": Vector2(-80.0, 1460.0)},
		# 护骨藤：东侧资源密集区
		{"node_id": "lq_herb_hugu_1", "material": "mat_huguteng", "pos": Vector2(1480.0, -1080.0)},
		{"node_id": "lq_herb_hugu_2", "material": "mat_huguteng", "pos": Vector2(1720.0, 920.0)},
		{"node_id": "lq_herb_hugu_3", "material": "mat_huguteng", "pos": Vector2(1260.0, 260.0)},
		{"node_id": "lq_herb_hugu_4", "material": "mat_huguteng", "pos": Vector2(1940.0, -520.0)},
	],

	## 灵兽：锋牙兽（攻击皮）与坚甲兽（防御皮）
	"beasts": [
		{"node_id": "lq_beast_feng_1", "beast_id": "fengya", "pos": Vector2(900.0, -700.0)},
		{"node_id": "lq_beast_feng_2", "beast_id": "fengya", "pos": Vector2(-900.0, -280.0)},
		{"node_id": "lq_beast_feng_3", "beast_id": "fengya", "pos": Vector2(1900.0, 520.0)},
		{"node_id": "lq_beast_feng_4", "beast_id": "fengya", "pos": Vector2(-2200.0, 640.0)},
		{"node_id": "lq_beast_jian_1", "beast_id": "jianjia", "pos": Vector2(720.0, 820.0)},
		{"node_id": "lq_beast_jian_2", "beast_id": "jianjia", "pos": Vector2(-700.0, 520.0)},
		{"node_id": "lq_beast_jian_3", "beast_id": "jianjia", "pos": Vector2(1220.0, -1500.0)},
		{"node_id": "lq_beast_jian_4", "beast_id": "jianjia", "pos": Vector2(-1250.0, -520.0)},
	],

	## 灵气团：随机出现在锚点附近，吸收后提升修炼进度
	"qi_orbs": [
		{"node_id": "lq_qi_1", "pos": Vector2(-1200.0, 40.0), "radius": 240.0},
		{"node_id": "lq_qi_2", "pos": Vector2(420.0, -720.0), "radius": 260.0},
		{"node_id": "lq_qi_3", "pos": Vector2(620.0, 900.0), "radius": 260.0},
		{"node_id": "lq_qi_4", "pos": Vector2(-320.0, 1600.0), "radius": 240.0},
		{"node_id": "lq_qi_5", "pos": Vector2(1660.0, -1620.0), "radius": 220.0},
		{"node_id": "lq_qi_6", "pos": Vector2(-2300.0, -1500.0), "radius": 220.0},
	],

	## 野外修士槽位：放在两片资源密集区附近，每区域最多两名
	"cultivators": [
		{"slot_id": "lq_cultivator_1", "pos": Vector2(-1650.0, 1020.0), "radius": 170.0, "chance": 0.60},
		{"slot_id": "lq_cultivator_2", "pos": Vector2(1560.0, -960.0), "radius": 170.0, "chance": 0.60},
	],
}

## 药材材料 id → 地面视觉条目（ArtDB.VISUALS）
## 材料名统一从 ItemDB 读，这里只解决「哪种草用哪个色块」
## 筑基区内容（2026-10-28）：本轮只落草药；兽/野修/灵气团随 #49 一起进表。
## ⚠ 灵田不在这里 —— 灵田是炼气区那 9 格，种子表按区域取。
const ZHUJI_CONTENT: Dictionary = {
	## 谷心核心首领：云隐苍角（2026-10-29 用户定）
	"core_boss": {"pos": Vector2.ZERO},
	"god_altars": [
		{"node_id": "zj_god_altar", "pos": Vector2(2400.0, -500.0)},
	],
	"herbs": [
		{"node_id": "zj_herb_xuecao_1", "material": "mat_zj_xuecao", "pos": Vector2(-1800.0, -1200.0)},
		{"node_id": "zj_herb_xuecao_2", "material": "mat_zj_xuecao", "pos": Vector2(-1620.0, -1340.0)},
		{"node_id": "zj_herb_xuecao_3", "material": "mat_zj_xuecao", "pos": Vector2(-1960.0, -1030.0)},
		{"node_id": "zj_herb_lanying_1", "material": "mat_zj_lanyingcao", "pos": Vector2(-1720.0, 1120.0)},
		{"node_id": "zj_herb_lanying_2", "material": "mat_zj_lanyingcao", "pos": Vector2(-1540.0, 1280.0)},
		{"node_id": "zj_herb_lanying_3", "material": "mat_zj_lanyingcao", "pos": Vector2(-1880.0, 950.0)},
		{"node_id": "zj_herb_liyuan_1", "material": "mat_zj_liyuanguo", "pos": Vector2(-320.0, -1320.0)},
		{"node_id": "zj_herb_liyuan_2", "material": "mat_zj_liyuanguo", "pos": Vector2(120.0, -1450.0)},
		{"node_id": "zj_herb_liyuan_3", "material": "mat_zj_liyuanguo", "pos": Vector2(520.0, -1180.0)},
		{"node_id": "zj_herb_faling_1", "material": "mat_zj_falinghua", "pos": Vector2(180.0, 1220.0)},
		{"node_id": "zj_herb_faling_2", "material": "mat_zj_falinghua", "pos": Vector2(500.0, 1400.0)},
		{"node_id": "zj_herb_faling_3", "material": "mat_zj_falinghua", "pos": Vector2(-80.0, 1460.0)},
		{"node_id": "zj_herb_hugu_1", "material": "mat_zj_huguteng", "pos": Vector2(1480.0, -1080.0)},
		{"node_id": "zj_herb_hugu_2", "material": "mat_zj_huguteng", "pos": Vector2(1720.0, 920.0)},
		{"node_id": "zj_herb_hugu_3", "material": "mat_zj_huguteng", "pos": Vector2(1260.0, 260.0)},
		{"node_id": "zj_herb_hugu_4", "material": "mat_zj_huguteng", "pos": Vector2(1940.0, -520.0)},
	],

	## 进入云隐谷的传送门：区域右上角；从区域面板直接进谷时落在门旁。
	## 南口仍可从青岚野步行进入；这个门是谷内的快速撤离点。
	"portal": {"pos": Vector2(2200.0, -1200.0), "spawn_offset": Vector2(-220.0, 150.0)},

	## 从世界区域面板直接选「云隐谷」时的落点：右上角传送门旁
	"spawn": {"pos": Vector2(1980.0, -1050.0)},

	## 本区灵田：击杀云隐苍角后出现在传送门西南侧（与青岚野同构的 3×3 荒地）。
	## plot_base = 9：地块存档格 9~17，和青岚野 0~8 互不串。
	"farm": {
		"node_id_prefix": "zj_farm",
		"plot_base": 9,
		"pos": Vector2(1700.0, -910.0),
		"cols": 3,
		"rows": 3,
		"spacing": Vector2(138.0, 100.0),
	},

	## 灵兽：锋牙兽（攻击皮）与坚甲兽（防御皮）；数值见 BEASTS 的 zj_ 条目
	"beasts": [
		{"node_id": "zj_beast_feng_1", "beast_id": "zj_fengya", "pos": Vector2(900.0, -700.0)},
		{"node_id": "zj_beast_feng_2", "beast_id": "zj_fengya", "pos": Vector2(-1000.0, -300.0)},
		{"node_id": "zj_beast_feng_3", "beast_id": "zj_fengya", "pos": Vector2(2000.0, 600.0)},
		{"node_id": "zj_beast_feng_4", "beast_id": "zj_fengya", "pos": Vector2(-2200.0, 800.0)},
		{"node_id": "zj_beast_jian_1", "beast_id": "zj_jianjia", "pos": Vector2(700.0, 850.0)},
		{"node_id": "zj_beast_jian_2", "beast_id": "zj_jianjia", "pos": Vector2(-800.0, 600.0)},
		{"node_id": "zj_beast_jian_3", "beast_id": "zj_jianjia", "pos": Vector2(1400.0, -1500.0)},
		{"node_id": "zj_beast_jian_4", "beast_id": "zj_jianjia", "pos": Vector2(-1400.0, -700.0)},
	],

	## 灵气团：锚点附近随机，吸收后提升修炼进度
	"qi_orbs": [
		{"node_id": "zj_qi_1", "pos": Vector2(-1200.0, 40.0), "radius": 240.0},
		{"node_id": "zj_qi_2", "pos": Vector2(420.0, -720.0), "radius": 260.0},
		{"node_id": "zj_qi_3", "pos": Vector2(620.0, 900.0), "radius": 260.0},
		{"node_id": "zj_qi_4", "pos": Vector2(-320.0, 1600.0), "radius": 240.0},
		{"node_id": "zj_qi_5", "pos": Vector2(1660.0, -1620.0), "radius": 220.0},
		{"node_id": "zj_qi_6", "pos": Vector2(-2300.0, -1500.0), "radius": 220.0},
	],

	## 野外修士槽位：两片资源密集区各一个，每区域最多两名
	"cultivators": [
		{"slot_id": "zj_cultivator_1", "pos": Vector2(-1650.0, 1020.0), "radius": 170.0, "chance": 0.60},
		{"slot_id": "zj_cultivator_2", "pos": Vector2(1560.0, -960.0), "radius": 170.0, "chance": 0.60},
	],
}

## 赤金丹霞（结丹区）内容：2026-10-29 用户定「筑基正左、同尺寸、传送门左上、中心首领」。
## 东沿（局部 x=+3000）与云隐谷直接相接，没有接缝林带，铺竖向地面过渡。
const JIEDAN_CONTENT: Dictionary = {
	## 霞心核心首领：赤金火麟
	"core_boss": {"pos": Vector2.ZERO},

	## 传送门：区域左上角；从区域面板直接进区时落在门旁（东南偏移）
	"portal": {"pos": Vector2(-2200.0, -1200.0), "spawn_offset": Vector2(220.0, 150.0)},
	"spawn": {"pos": Vector2(-1980.0, -1050.0)},
	"god_altars": [
		{"node_id": "jd_god_altar", "pos": Vector2(-2450.0, -500.0)},
	],

	## 本区灵田：击杀赤金火麟后出现在传送门东南侧（镜像青岚野）。
	## plot_base = 18：地块存档格 18~26，三区灵田各管各的。
	"farm": {
		"node_id_prefix": "jd_farm",
		"plot_base": 18,
		"pos": Vector2(-1700.0, -910.0),
		"cols": 3,
		"rows": 3,
		"spacing": Vector2(138.0, 100.0),
	},

	"herbs": [
		# 赤金血参：西南岩台
		{"node_id": "jd_herb_xuecao_1", "material": "mat_jd_xuecao", "pos": Vector2(-1900.0, 900.0)},
		{"node_id": "jd_herb_xuecao_2", "material": "mat_jd_xuecao", "pos": Vector2(-1720.0, 1080.0)},
		{"node_id": "jd_herb_xuecao_3", "material": "mat_jd_xuecao", "pos": Vector2(-2060.0, 760.0)},
		# 赤金蓝萤草：西北背阴坡（传送门西侧）
		{"node_id": "jd_herb_lanying_1", "material": "mat_jd_lanyingcao", "pos": Vector2(-1600.0, -1300.0)},
		{"node_id": "jd_herb_lanying_2", "material": "mat_jd_lanyingcao", "pos": Vector2(-1400.0, -1420.0)},
		{"node_id": "jd_herb_lanying_3", "material": "mat_jd_lanyingcao", "pos": Vector2(-1850.0, -1120.0)},
		# 赤金力元果：东南热土
		{"node_id": "jd_herb_liyuan_1", "material": "mat_jd_liyuanguo", "pos": Vector2(1200.0, 1300.0)},
		{"node_id": "jd_herb_liyuan_2", "material": "mat_jd_liyuanguo", "pos": Vector2(1450.0, 1450.0)},
		{"node_id": "jd_herb_liyuan_3", "material": "mat_jd_liyuanguo", "pos": Vector2(1000.0, 1550.0)},
		# 赤金法灵花：北中火脉
		{"node_id": "jd_herb_faling_1", "material": "mat_jd_falinghua", "pos": Vector2(-200.0, -1350.0)},
		{"node_id": "jd_herb_faling_2", "material": "mat_jd_falinghua", "pos": Vector2(100.0, -1450.0)},
		{"node_id": "jd_herb_faling_3", "material": "mat_jd_falinghua", "pos": Vector2(-500.0, -1250.0)},
		# 赤金护骨藤：东侧丹崖
		{"node_id": "jd_herb_hugu_1", "material": "mat_jd_huguteng", "pos": Vector2(1700.0, -900.0)},
		{"node_id": "jd_herb_hugu_2", "material": "mat_jd_huguteng", "pos": Vector2(2000.0, -700.0)},
		{"node_id": "jd_herb_hugu_3", "material": "mat_jd_huguteng", "pos": Vector2(1450.0, -1150.0)},
		{"node_id": "jd_herb_hugu_4", "material": "mat_jd_huguteng", "pos": Vector2(2100.0, -1200.0)},
	],

	"beasts": [
		{"node_id": "jd_beast_feng_1", "beast_id": "jd_fengya", "pos": Vector2(900.0, -700.0)},
		{"node_id": "jd_beast_feng_2", "beast_id": "jd_fengya", "pos": Vector2(-1000.0, -300.0)},
		{"node_id": "jd_beast_feng_3", "beast_id": "jd_fengya", "pos": Vector2(2000.0, 600.0)},
		{"node_id": "jd_beast_feng_4", "beast_id": "jd_fengya", "pos": Vector2(-2200.0, 800.0)},
		{"node_id": "jd_beast_jian_1", "beast_id": "jd_jianjia", "pos": Vector2(700.0, 850.0)},
		{"node_id": "jd_beast_jian_2", "beast_id": "jd_jianjia", "pos": Vector2(-800.0, 600.0)},
		{"node_id": "jd_beast_jian_3", "beast_id": "jd_jianjia", "pos": Vector2(1400.0, -1450.0)},
		{"node_id": "jd_beast_jian_4", "beast_id": "jd_jianjia", "pos": Vector2(-1400.0, -700.0)},
	],

	"qi_orbs": [
		{"node_id": "jd_qi_1", "pos": Vector2(-1200.0, 40.0), "radius": 240.0},
		{"node_id": "jd_qi_2", "pos": Vector2(420.0, -720.0), "radius": 260.0},
		{"node_id": "jd_qi_3", "pos": Vector2(620.0, 900.0), "radius": 260.0},
		{"node_id": "jd_qi_4", "pos": Vector2(-320.0, 1500.0), "radius": 240.0},
		{"node_id": "jd_qi_5", "pos": Vector2(1660.0, -1450.0), "radius": 220.0},
		{"node_id": "jd_qi_6", "pos": Vector2(-2300.0, -1450.0), "radius": 220.0},
	],

	"cultivators": [
		{"slot_id": "jd_cultivator_1", "pos": Vector2(-1650.0, 1020.0), "radius": 170.0, "chance": 0.60},
		{"slot_id": "jd_cultivator_2", "pos": Vector2(1560.0, -960.0), "radius": 170.0, "chance": 0.60},
	],
}

## 幽冥灵墟（元婴区）内容：练气正左、结丹正下，同尺寸。
## 北沿接赤金丹霞、东沿接青岚野，两条边界都开放步行；西/南是废墟外沿。
## 中间是九天门，无核心首领（内容定稿权留给用户），所以也没有灵田。
const YUANYING_CONTENT: Dictionary = {
	"portal": {"pos": Vector2(-2200.0, 1200.0), "spawn_offset": Vector2(220.0, -150.0)},
	"spawn": {"pos": Vector2(-1980.0, 1050.0)},
	## 九天门前的核心首领：镇墟石犼
	"core_boss": {"pos": Vector2.ZERO},
	"god_altars": [
		{"node_id": "yy_god_altar", "pos": Vector2(-2500.0, -500.0)},
	],

	"herbs": [
		# 幽冥血参：西南墟土（传送门北侧）
		{"node_id": "yy_herb_xuecao_1", "material": "mat_yy_xuecao", "pos": Vector2(-1900.0, 900.0)},
		{"node_id": "yy_herb_xuecao_2", "material": "mat_yy_xuecao", "pos": Vector2(-1720.0, 1080.0)},
		{"node_id": "yy_herb_xuecao_3", "material": "mat_yy_xuecao", "pos": Vector2(-2060.0, 760.0)},
		# 幽冥蓝萤草：西北背阴坡
		{"node_id": "yy_herb_lanying_1", "material": "mat_yy_lanyingcao", "pos": Vector2(-1600.0, -1300.0)},
		{"node_id": "yy_herb_lanying_2", "material": "mat_yy_lanyingcao", "pos": Vector2(-1400.0, -1420.0)},
		{"node_id": "yy_herb_lanying_3", "material": "mat_yy_lanyingcao", "pos": Vector2(-1850.0, -1120.0)},
		# 幽冥力元果：东南近青岚的墟田
		{"node_id": "yy_herb_liyuan_1", "material": "mat_yy_liyuanguo", "pos": Vector2(1200.0, 1300.0)},
		{"node_id": "yy_herb_liyuan_2", "material": "mat_yy_liyuanguo", "pos": Vector2(1450.0, 1450.0)},
		{"node_id": "yy_herb_liyuan_3", "material": "mat_yy_liyuanguo", "pos": Vector2(1000.0, 1550.0)},
		# 幽冥法灵花：北中幽火脉
		{"node_id": "yy_herb_faling_1", "material": "mat_yy_falinghua", "pos": Vector2(-200.0, -1350.0)},
		{"node_id": "yy_herb_faling_2", "material": "mat_yy_falinghua", "pos": Vector2(100.0, -1450.0)},
		{"node_id": "yy_herb_faling_3", "material": "mat_yy_falinghua", "pos": Vector2(-500.0, -1250.0)},
		# 幽冥护骨藤：东侧残垣
		{"node_id": "yy_herb_hugu_1", "material": "mat_yy_huguteng", "pos": Vector2(1700.0, -900.0)},
		{"node_id": "yy_herb_hugu_2", "material": "mat_yy_huguteng", "pos": Vector2(2000.0, -700.0)},
		{"node_id": "yy_herb_hugu_3", "material": "mat_yy_huguteng", "pos": Vector2(1450.0, -1150.0)},
		{"node_id": "yy_herb_hugu_4", "material": "mat_yy_huguteng", "pos": Vector2(2100.0, -1200.0)},
	],

	"beasts": [
		{"node_id": "yy_beast_feng_1", "beast_id": "yy_fengya", "pos": Vector2(900.0, -700.0)},
		{"node_id": "yy_beast_feng_2", "beast_id": "yy_fengya", "pos": Vector2(-1000.0, -300.0)},
		{"node_id": "yy_beast_feng_3", "beast_id": "yy_fengya", "pos": Vector2(2000.0, 600.0)},
		## 原 (-2200, 800) 离出生点只有 330，一落地就被扑；挪到西墙内侧
		{"node_id": "yy_beast_feng_4", "beast_id": "yy_fengya", "pos": Vector2(-2450.0, 200.0)},
		{"node_id": "yy_beast_jian_1", "beast_id": "yy_jianjia", "pos": Vector2(700.0, 850.0)},
		{"node_id": "yy_beast_jian_2", "beast_id": "yy_jianjia", "pos": Vector2(-800.0, 600.0)},
		{"node_id": "yy_beast_jian_3", "beast_id": "yy_jianjia", "pos": Vector2(1400.0, -1450.0)},
		{"node_id": "yy_beast_jian_4", "beast_id": "yy_jianjia", "pos": Vector2(-1400.0, -700.0)},
	],

	"qi_orbs": [
		{"node_id": "yy_qi_1", "pos": Vector2(-1200.0, 40.0), "radius": 240.0},
		{"node_id": "yy_qi_2", "pos": Vector2(420.0, -720.0), "radius": 260.0},
		{"node_id": "yy_qi_3", "pos": Vector2(620.0, 900.0), "radius": 260.0},
		{"node_id": "yy_qi_4", "pos": Vector2(-320.0, 1500.0), "radius": 240.0},
		{"node_id": "yy_qi_5", "pos": Vector2(1660.0, -1450.0), "radius": 220.0},
		{"node_id": "yy_qi_6", "pos": Vector2(-2300.0, -1450.0), "radius": 220.0},
	],

	"cultivators": [
		## 原 (-1650, 1020) 离落点只有 330，一进区就被野修扑上来；挪到北侧空地
		{"slot_id": "yy_cultivator_1", "pos": Vector2(500.0, -1500.0), "radius": 170.0, "chance": 0.60},
		{"slot_id": "yy_cultivator_2", "pos": Vector2(1560.0, -960.0), "radius": 170.0, "chance": 0.60},
	],
}

## 九天之上（化神区）：九天门开后才进得来。目前只有一块空场和一座回程门 ——
## 地貌 / 药材 / 灵兽 / 首领都还没设计，所以这里刻意**不放任何战斗内容**，
## 但传送门必须有：大陆的规矩是「只能走传送门离开」，缺了门就是把人关死。
const HUASHEN_CONTENT: Dictionary = {
	"portal": {"pos": Vector2(2300.0, 1300.0), "spawn_offset": Vector2(-220.0, 150.0)},
	"spawn": {"pos": Vector2(2080.0, 1450.0)},
	## 铸神祭坛：化神坛（0,0）东南侧的玉台边；化神后在这里再取第二份
	"god_altars": [
		{"node_id": "hs_god_altar", "pos": Vector2(600.0, 300.0)},
	],
	"herbs": [],
	"qi_orbs": [],
	"beasts": [],
	"cultivators": [],
}

## 铸神祭坛奖励（2026-11-13 用户定）：首次取铸神晶×1；化神后再取铸神晶×1 + 补天石×7。
## ⚠ 祭坛阶段存在 CharacterData.secret_world.god_altars，按 node_id 记 0/1/2。
const GOD_ALTAR_FIRST := {"mat_zhushenjing": 1}
const GOD_ALTAR_HUASHEN := {"mat_zhushenjing": 1, "mat_butianshi": 7}

const HERB_VISUALS: Dictionary = {	"mat_xuecao": "world_herb_xuecao",
	"mat_lanyingcao": "world_herb_lanying",
	"mat_liyuanguo": "world_herb_liyuan",
	"mat_falinghua": "world_herb_faling",
	"mat_huguteng": "world_herb_hugu",
	# 筑基草药：沿用练气的五种世界色块（访谈：只改名 / 提品质，不重新画）
	"mat_zj_xuecao": "world_herb_xuecao",
	"mat_zj_lanyingcao": "world_herb_lanying",
	"mat_zj_liyuanguo": "world_herb_liyuan",
	"mat_zj_falinghua": "world_herb_faling",
	"mat_zj_huguteng": "world_herb_hugu",
	# 结丹草药：同样复用世界色块，只换名与品质（2026-10-29）
	"mat_jd_xuecao": "world_herb_xuecao",
	"mat_jd_lanyingcao": "world_herb_lanying",
	"mat_jd_liyuanguo": "world_herb_liyuan",
	"mat_jd_falinghua": "world_herb_faling",
	"mat_jd_huguteng": "world_herb_hugu",
	# 元婴草药：复用五种世界色块，只换名与品质
	"mat_yy_xuecao": "world_herb_xuecao",
	"mat_yy_lanyingcao": "world_herb_lanying",
	"mat_yy_liyuanguo": "world_herb_liyuan",
	"mat_yy_falinghua": "world_herb_faling",
	"mat_yy_huguteng": "world_herb_hugu",
}

# ===== 刷新节奏（秒）=====
const RESPAWN_HERB := 240.0
const RESPAWN_BEAST := 120.0
const RESPAWN_QI := 180.0
const RESPAWN_CULTIVATOR := 420.0
## 修士一次刷新判定失败后，隔多久再判定
const CULTIVATOR_RECHECK := 60.0

# ===== 查询工具 =====

static func get_region(region_id: String) -> Dictionary:
	for r in REGIONS:
		if String(r.get("region_id", "")) == region_id:
			return r
	return {}


## 区域核心首领配置（塔里的重复挑战入口与战斗箱庭共用）。
## 目前练气 / 筑基 / 结丹各有一只；以后新区域在区域表登记 core_boss_id 后在这里加映射。
static func get_core_boss(region_id: String) -> Dictionary:
	var core_id := String(get_region(region_id).get("core_boss_id", ""))
	match core_id:
		"world_core_lianqi":
			return CORE_BOSS
		"world_core_zhuji":
			return CORE_BOSS_ZHUJI
		"world_core_jiedan":
			return CORE_BOSS_JIEDAN
		"world_core_yuanying":
			return CORE_BOSS_YUANYING
	return {}


static func get_open_region() -> Dictionary:
	for r in REGIONS:
		if is_region_open(r):
			return r
	return REGIONS[0] if REGIONS.size() > 0 else {}


static func get_region_content(region_id: String) -> Dictionary:
	if region_id == REGION_LIANQI:
		return LIANQI_CONTENT
	if region_id == REGION_ZHUJI:
		return ZHUJI_CONTENT
	if region_id == REGION_JIEDAN:
		return JIEDAN_CONTENT
	if region_id == REGION_YUANYING:
		return YUANYING_CONTENT
	if region_id == REGION_HUASHEN:
		return HUASHEN_CONTENT
	return {}


static func get_beast(beast_id: String) -> Dictionary:
	var d = BEASTS.get(beast_id, {})
	return d if d is Dictionary else {}


static func get_herb_visual(material_id: String) -> String:
	return String(HERB_VISUALS.get(material_id, "world_herb_xuecao"))


## 某区域的草药材料 id；不传 region_id = 所有已解锁区域（灵田种子表用）。
static func get_herb_ids(region_id: String = "") -> Array:
	var out: Array = []
	for c in _contents_for(region_id):
		for h in (c as Dictionary).get("herbs", []):
			var mid := String((h as Dictionary).get("material", ""))
			if mid != "" and mid not in out:
				out.append(mid)
	return out


## 某区域灵兽掉落的兽皮 id；不传 = 所有已解锁区域。
static func get_hide_ids(region_id: String = "") -> Array:
	var out: Array = []
	for c in _contents_for(region_id):
		for b in (c as Dictionary).get("beasts", []):
			var bid := String((b as Dictionary).get("beast_id", ""))
			var hid := String(get_beast(bid).get("hide_id", ""))
			if hid != "" and hid not in out:
				out.append(hid)
	return out


static func _contents_for(region_id: String) -> Array:
	var out: Array = []
	if region_id != "":
		var c := get_region_content(region_id)
		if not c.is_empty():
			out.append(c)
		return out
	for r in REGIONS:
		if not is_region_open(r as Dictionary):
			continue
		var c := get_region_content(String((r as Dictionary).get("region_id", "")))
		if not c.is_empty():
			out.append(c)
	return out


## 野修数值：筑基用云隐谷专用面板，结丹用丹霞专用面板，其余沿用练气那套
static func get_cultivator(region_id: String) -> Dictionary:
	var realm := String(get_region(region_id).get("realm", ""))
	if realm == "筑基":
		return CULTIVATOR_ZHUJI
	if realm == "结丹":
		return CULTIVATOR_JIEDAN
	if realm == "元婴":
		return CULTIVATOR_YUANYING
	return CULTIVATOR


## 某区域的单只击杀修为（访谈：筑基 / 野修各 60，结丹各 120，元婴各 240，练气各 30）
static func kill_exp(region_id: String, is_beast: bool) -> int:
	var realm := String(get_region(region_id).get("realm", ""))
	if realm == "筑基":
		return 60
	if realm == "结丹":
		return 120
	if realm == "元婴":
		return 240
	return EXP_BEAST if is_beast else EXP_CULTIVATOR


## 世界坐标落在哪个已解锁区域（HUD 标题 / 区域提示用）
static func region_at(pos: Vector2) -> Dictionary:
	for r in REGIONS:
		if not is_region_open(r as Dictionary):
			continue
		if (r.get("rect", Rect2()) as Rect2).has_point(pos):
			return r
	return {}


## 某区域的野外修士功法池（随机装备用）
## 取该区域登记的 BOSS 会用的招式 → SkillDB 反查功法；去掉满层变体等不可学习条目。
static func get_cultivator_skill_pool(region_id: String) -> Array:
	var region := get_region(region_id)
	var out: Array = []
	for raw in region.get("skill_pool_bosses", []):
		for sid in WorldDB.get_boss_skill_ids(String(raw)):
			var id := String(sid)
			if id == "" or id == "skill_sword_heaven_full" or id in out:
				continue
			out.append(id)
	return out


## 用确定性种子建一个「随机点」：灵气团 / 修士的重生位置
## 每次调用都不同（用时间做盐），但返回范围稳定限制在锚点周围的小圆里
static func random_point_near(anchor: Vector2, radius: float) -> Vector2:
	var angle := randf() * TAU
	var dist := sqrt(randf()) * maxf(radius, 1.0)
	return anchor + Vector2.RIGHT.rotated(angle) * dist
