class_name MatchAdapter
extends RefCounted
## 把一张卡变成场上棋子（第 4 步：PieceAdapter）。
##
## 复用项目里已经跑通的那条路 —— 法宝召唤就是拿**真 BOSS 场景**当替身
## （`player.gd:1241 _summon_ally_boss`），所以这里不新建单位体系，只换阵营与面板。
##
## 与法宝召唤的关键差别：法宝召唤的是友军（`is_ally = true`，target 一次性设死、
## 到 `summon_life` 就消散）；对局棋子是**有队伍号的独立单位**，
## 必须走仇恨路径（目标死了要自动重选，否则场上剩两只时它会盯着尸体），
## 而且只会被打死、不会按时消散。

## 没有专属战斗场景的单位（凡界核心古猿就是这张通用 WorldEnemy）用的兜底场景。
## 写成常量而不是 `preload` 就地使用：`scene_path_for()` 与装配必须指同一个文件。
const FALLBACK_ENEMY_SCENE := "res://scenes/world/world_enemy.tscn"

## 面板折算后 attack_power 直接等于目标 DPS。
## 这是个**约定**而不是推导：招式伤害 = attack_power × 招式系数，系数与出手间隔
## 每只都不同，所以真实 TTK 只能测。`probe_match_pieces` 会量出每对的实际击杀时间，
## 用实测值回来校准这个常数 —— 别把它当成已经平衡好了。
static func spawn_piece(parent: Node, boss_id: String, team: int, cell: Vector2i) -> Node2D:
	var pos := MatchDB.cell_to_pos(cell)
	var node := _instantiate(boss_id)
	if node == null:
		push_error("MatchAdapter: %s 装配失败" % boss_id)
		return null
	var st := MatchDB.piece_stats(boss_id)
	# ⚠ 以下必须在 add_child **之前**设：
	#   is_ally / team_id → BossBase._ready() 据此决定入 "boss" / "ally_summon" / "match_piece"
	#   max_hp            → _ready() 里 current_hp = max_hp，进树后再改就变成半血上场
	if "boss_id" in node:
		node.set("boss_id", boss_id)
	node.set("is_ally", false)
	node.set("team_id", team)
	node.set("max_hp", float(st["hp"]))
	# attack_power 走实测校准，不能直接填目标 DPS —— 实测 atk=100 的真实输出只有 4–40，
	# 直接填会高估一到两个数量级，棋子互相啃不动，一局全拖到 120 秒超时判定。
	# 校准值缺失（0）时退回目标 DPS 并**告警**：宁可慢，也不要静默造出一只 10 倍弱的棋子。
	var calib := float(MatchDB.ATTACK_CALIB.get(boss_id, 0.0))
	if calib <= 0.0:
		push_warning("MatchAdapter: %s 没有 DPS 校准值，attack_power 暂用目标 DPS（会明显偏弱）" % boss_id)
		calib = float(st["dps"])
	node.set("attack_power", calib)
	# 0 = 不自动消散。走法宝召唤那条默认值会让棋子在 20 秒后凭空蒸发，
	# 表现为「明明优势局突然少一只」，而且不发 died 信号，规则层还以为它活着。
	node.set("summon_life", 0.0)
	# 脱战回拽锚点。WorldEnemy.configure() 把它设成该核心在**大世界里的坐标**，
	# 搬到棋盘上就是几千像素外 —— 棋子会一边打一边被拽向那个点，最后整只消失。
	if "spawn_home" in node:
		node.set("spawn_home", pos)
	node.position = pos
	parent.add_child(node)
	# 战场边界：棋盘不是 combat_arena，得自己把半尺寸塞进去，
	# 否则 `boss_base.gd:294-318` 的位移钳制拿不到边界，突进技会把棋子送出图外。
	if node.has_method("set_arena_bounds"):
		node.call("set_arena_bounds", MatchDB.arena_half())
	return node


## 装配本体。**四位大陆核心不是 BossBase 场景，是 WorldEnemy**：
## 它们的招式表来自 `SecretWorldDB.CORE_SKILLS`，由 `WorldEnemy.configure()` 安装
## （见 `secret_world.gd:884 _spawn_core`）。
## ⚠ 早期版本这里一律走 `WorldDB.get_boss_scene()`，核心首领查不到登记就回退到
##   `boss.tscn`（通用 prototype_boss，没有 boss_id 属性、没有数据驱动招式），
##   于是四只核心变成"同一套假招式"：实测苍角 / 火麟 十秒 0 输出、古猿 / 石犼 只有 3–4 DPS。
static func _instantiate(boss_id: String) -> Node2D:
	var region := MatchDB.core_region_id(boss_id)
	if region != "":
		var cfg: Dictionary = SecretWorldDB.get_core_boss(region)
		if cfg.is_empty():
			push_warning("MatchAdapter: 核心 %s（区域 %s）没有配置" % [boss_id, region])
			return null
		var scene_path := scene_path_for(boss_id)
		var packed: PackedScene = SkinWarm.resource(scene_path) as PackedScene
		if packed == null:
			push_warning("MatchAdapter: %s 的核心场景读不到：%s" % [boss_id, scene_path])
			return null
		var enemy := packed.instantiate() as WorldEnemy
		if enemy == null:
			push_warning("MatchAdapter: %s 的场景不是 WorldEnemy：%s" % [boss_id, scene_path])
			return null
		enemy.node_id = "match_" + boss_id
		# configure() 会**覆写** max_hp / attack_power，所以折算面板必须在它之后设。
		enemy.configure(cfg, WorldEnemy.KIND_CORE, String(cfg.get("name", "核心首领")))
		enemy.boss_id = boss_id
		return enemy
	var res := SkinWarm.resource(scene_path_for(boss_id))
	if res == null or not (res is PackedScene):
		push_error("MatchAdapter: %s 的场景读不出来" % boss_id)
		return null
	return (res as PackedScene).instantiate() as Node2D


## 这只卡该用哪个战斗场景。装配与预载**必须共用这一条解析**：
## 另写一份「BOSS → 场景」的判断等于同一个事实写两处，迟早和 _instantiate 漂开
## （预载了半天，上场读的还是另一个路径，等于白预载 —— world_core_lianqi 就这么红过）。
## 核心首领里古猿这类**没有专属场景**，装配用的就是通用 WorldEnemy，
## 所以这里返回的必须是「真正会被实例化的那一条」，包含兜底。
static func scene_path_for(boss_id: String) -> String:
	var region := MatchDB.core_region_id(boss_id)
	if region != "":
		var cfg: Dictionary = SecretWorldDB.get_core_boss(region)
		var p := String(cfg.get("scene", ""))
		if p != "" and ResourceLoader.exists(p):
			return p
		return FALLBACK_ENEMY_SCENE
	return WorldDB.get_boss_scene(boss_id)


## 提前把这只 BOSS 的场景排进线程预载队列（票 003）。
## 场景到手后 SkinWarm 会顺着你挂在这个场景里的 SkinVisual `visual_id`
## 把招式表一起拉走，所以调用方不需要知道任何贴图路径。
## ⚠ 核心首领要**多点名一次**：它的皮是运行时从区域配置里取的
##   （`world_enemy.gd:136` 用 `cfg["visual_id"]` 覆写场景里那个），
##   只扫场景会预载到错的那一份 —— 石犼就是场景写 world_core_shihou、
##   真上场穿的是 boss_huyao 那张 455ms 的大图。
static func warm_boss(boss_id: String) -> void:
	SkinWarm.request(scene_path_for(boss_id))
	var region := MatchDB.core_region_id(boss_id)
	if region != "":
		var cfg: Dictionary = SecretWorldDB.get_core_boss(region)
		SkinWarm.request_visual_entry(String(cfg.get("visual_id", "")))


## 棋子当前还活着吗。死亡读数统一走 `BossBase.is_unit_dead`
## —— `is_dead` 在 Player 上是变量、在 BossBase 上是方法，直接 `bool(get(...))`
## 会拿到 Callable 并且每帧为真（2026-10-30 判词崩溃就是这么来的）。
static func is_alive(piece: Node) -> bool:
	if piece == null or not is_instance_valid(piece):
		return false
	return not BossBase.is_unit_dead(piece)
