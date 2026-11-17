extends Node2D
## 万界秘境·苍澜大陆（第三套玩法循环）—— 场景管理器
##
## 结构：苍澜大陆是一张连续的大地图（当前只开放右下角的练气区域「青岚野」）。
##   世界实体（药材 / 灵气团 / 灵兽 / 野修 / 核心首领）由本脚本按 SecretWorldDB 的
##   坐标表生成；刷新时刻、核心首领是否已杀等**持久状态**存在 CharacterData.secret_world。
##
## 三条硬规则（用户 2026-10-23 定）：
##   1. 必须走回入口处的传送门才能离开（ESC 只提示，不直接退）
##   2. 死亡 → 本次副本里获得的战利品全部消失（进副本时快照背包，死亡时回滚）
##   3. 核心首领一次性击杀；首杀奖励直接入包并立即存档，且**永不因回滚丢失**
##      （_ensure_core_reward 会在每次进入时补发，防止死一次就永久卡住突破）
##
## 局内背包（2026-10-23 追加）：副本内拾取先进 _run_items（不写存档），
##   死亡清空、成功撤离才并入永久背包；可在局内按 B 打开并拖拽丢弃。
##
## 视觉：练气区走 terrain 配方（低频遮罩混三套手绘 tile + 南/东两条林带，见
##   assets/shaders/region_terrain.gdshader）；西/北留草地向其他区域敞开。
##   还没配 terrain 的区域退回色块 + 网格占位。野修复用主角美术。
##
## 灵气团是引导式交互：按 F 开始吸收，5 秒进度条走完才入账，离开范围会中断。

const ENEMY_SCENE := preload("res://scenes/world/world_enemy.tscn")
const PICKUP_SCENE := preload("res://scenes/items/item_pickup.tscn")

## 地形配方（2026-10-26）：低频遮罩 + 可平铺 tile，配了 SecretWorldDB.terrain 的区域才走
const TERRAIN_SHADER := preload("res://assets/shaders/region_terrain.gdshader")
const BAND_SHADER := preload("res://assets/shaders/region_band.gdshader")
## 接缝过渡：一条真实的「谷地暗林地 → 草原」横向地面纹理（1536×735，x 无缝）。
## 纹理自带上下 alpha 羽化，铺在地形之上、林带之下（z=1），不再画乘算暗影。
const SEAM_TRANSITION_TEX := "res://assets/scenes/tiles/seam_transition.png"
const SEAM_TRANSITION_ABOVE := 140.0
## 林带贴着邻区的那一端向里多铺一段；两端各按 2 倍叠宽淡出，
## 使区域交界线落在两条带子各 ~50% 的位置，不再是一刀切（2026-11-01）。
const BAND_END_OVERLAP := 220.0
## 云隐谷南口两侧林带的收口宽度（只在缺口处淡出，不向缺口里铺树）。
const BAND_GAP_FADE := 150.0
## 一张 tile 盖的世界像素，以及 tile 自己的边长 —— 两者之比就是贴图密度
## （896/512 = 1.75 texel/世界像素）。林带按同一密度铺，才不会出现「树比草清晰」。
const TILE_WORLD := 512.0
const TILE_TEXELS := 896.0
const TEXELS_PER_WORLD := TILE_TEXELS / TILE_WORLD

## 苍澜大陆探索 BGM（tools/gen_battle_music.py 生成）
const BGM_CONTINENT := "res://assets/audio/bgm/world_continent.wav"
var _bgm: BgmPlayer = null
const REALM_SCENE := "res://scenes/main/primordial_realm.tscn"

const VIEW_W := 1280.0
const VIEW_H := 720.0

const WALL_LAYER := 32
const WALL_INSET := 40.0
const WALL_THICKNESS := 80.0
const GRID_STEP := 400.0

const SKILL_BAR_KEYS: Array = ["Q", "E", "R", "T"]
const SKILL_SLOT_SIZE := Vector2(48.0, 48.0)
const SKILL_SLOT_GAP := 8.0
const SKILL_ICON_SIZE := Vector2(34.0, 34.0)
const TREASURE_SLOT_SIZE := Vector2(44.0, 44.0)
const TREASURE_SLOT_GAP := 6.0
const TREASURE_BAR_MARGIN := 12.0
## 局内背包容量（格）：与永久背包同一口径，堆叠按材料 id 合并
const RUN_BAG_CAPACITY := 60

@onready var ground: Node2D = $Ground
@onready var content: Node2D = $Content
@onready var player: Node2D = $Player
@onready var hud: CanvasLayer = $HUD

var region: Dictionary = {}
var region_id: String = SecretWorldDB.REGION_LIANQI
var arena_half_extents: Vector2 = Vector2.ZERO
## 区域中心（世界坐标）：BossBase 的边界钳制以它为基准
var arena_center: Vector2 = Vector2.ZERO

var _content_def: Dictionary = {}
var _resources: Dictionary = {}   # node_id -> WorldResource（药材 / 灵气团 / 传送门）
var _enemies: Dictionary = {}     # node_id / 修士槽位 -> WorldEnemy
var _drops: Array = []            # 地面掉落物（ItemPickup）
var _portal: WorldResource = null
## 并集里每个已解锁区域各有一个撤离传送门；HUD 罗盘指向最近的一个
var _portals: Array[WorldResource] = []

## ===== 局内背包（本次副本所得，不写存档）=====
var _run_items: Array = []         # 与 ItemPickup.item 同结构，按 id 堆叠
var _run_bag: RunBagPanel = null

## 进入副本时的战利品快照（死亡回滚用）
var _loot_snapshot: Dictionary = {}
var _dead := false
## 自动拾取节拍（2026-11-12 用户定）：走进范围就捡，不用按 F。
## ⚠ 局内背包满时没有仓库可去，掉落物留在原地（这是本模式与竞技场的唯一区别）。
const AUTO_PICKUP_INTERVAL := 0.12
var _auto_pick_left := 0.0
var _leaving := false
var _respawn_timer := 0.0
var _nearest: WorldResource = null
## 灵田在这张图里是否已经播报过（按地块前缀记：三个区域各播一次）
var _farm_announced: Dictionary = {}
## 地面材质（并集会有多张）+ 上一次喂给它们的 mipmap 层级（-1 = 还没喂过）
var _terrain_mats: Array = []
var _terrain_lod := -1.0
## 并集里各区域的 rect 与外包矩形：林带端头是否为「内部交界」靠它判断
var _open_rects: Array[Rect2] = []
var _open_union := Rect2()
## 当前所站区域：HUD 标题 / 空首领提示 / 进入云隐谷的提示都读它
var _current_region_id: String = ""
var _region_check_timer: float = 0.0
var _seen_region_ids: Dictionary = {}
## 正在吸收的灵气团（null = 没在读条）与剩余秒数
var _absorb: WorldResource = null
var _absorb_left := 0.0

# ===== HUD =====
var _title: Label
var _core_status: Label
## 死亡代价常驻提示（2026-11-13 用户定）：屏幕正上方右侧的红字括号。
var _death_warn: Label
var _cult_label: Label
var _cult_bar: ProgressBar
var _bag_label: Label
## 大世界状态栏（2026-11-01）：野修法宝的断念 / 禁步 / 蚀甲 / 续命在这里常驻显示。
## 大世界没有战斗箱庭的 debuff 栏，不补这条玩家只能看到一次飘字。
var _status_box: VBoxContainer = null
var _status_rows: Dictionary = {}
var _compass_portal: Label
var _prompt_bg: ColorRect
var _prompt: Label
var _absorb_box: Control
var _absorb_bar: ProgressBar
var _absorb_label: Label
var _announce: Label
var _announce_tween: Tween
var _death_overlay: Control
var _skill_slots: Array = []
var _treasure_slots: Array = []


func _ready() -> void:
	# 安卓返回键在本场景 = 后退（ESC 语义：指路回传送门），见 GameState.handle_go_back()
	GameState.back_uses_esc = true
	region = SecretWorldDB.get_open_region()
	if region.is_empty():
		push_error("苍澜大陆：SecretWorldDB 没有可用区域")
		return
	region_id = String(region.get("region_id", SecretWorldDB.REGION_LIANQI))

	# 内容表坐标以区域中心为原点；并集内容把每个区域的实体平移到各自 rect 中心
	var spawn_region_id := SecretWorldDB.take_pending_spawn_region()
	if spawn_region_id == "" or SecretWorldDB.get_region(spawn_region_id).is_empty():
		spawn_region_id = region_id
	_current_region_id = spawn_region_id
	_content_def = _collect_open_content()
	# 敌人不认碰撞墙（mask 不含墙层），靠 BossBase 的逻辑边界钳制位置
	add_to_group("combat_arena")
	# ===== 并集（2026-10-28）：几何用所有已解锁区域的并集；地形按区各铺一张 =====
	var world_rect: Rect2 = get_open_rect()
	if world_rect.size.x <= 0.0 or world_rect.size.y <= 0.0:
		world_rect = _region_rect()
	var open_regions := get_open_regions()
	if open_regions.is_empty():
		open_regions = [region]
	_open_rects.clear()
	for r in open_regions:
		_open_rects.append((r as Dictionary).get("rect", Rect2()))
	_open_union = _open_rects[0]
	for rr in _open_rects:
		_open_union = _open_union.merge(rr)
	var inner := _inner_rect(world_rect)
	arena_half_extents = inner.size * 0.5
	arena_center = inner.get_center()

	for r in open_regions:
		var rrect: Rect2 = (r as Dictionary).get("rect", Rect2())
		var terr = (r as Dictionary).get("terrain", {})
		var rid := String((r as Dictionary).get("region_id", ""))
		if terr is Dictionary and not (terr as Dictionary).is_empty():
			_build_terrain_ground(rrect, terr, "_" + rid)
		else:
			_build_ground(rrect, r)
		_build_region_landmark(r as Dictionary)
	_build_huashen_gate()
	_build_huashen_altar()
	_build_seam_transitions(open_regions)
	_build_corner_caps(open_regions)
	_spawn_player(world_rect, spawn_region_id)
	_build_walls(world_rect)
	_apply_camera_limits(world_rect)
	_build_hud()
	_build_run_bag()
	_start_continent_bgm()

	player.player_died.connect(_on_player_died)
	player.skill_used.connect(_on_player_skill_used)
	VirtualPad.set_context("combat")
	get_tree().paused = false

	# 快照要在「核心奖励自愈」之前拍：首杀奖励属于必得内容，不该被死亡回滚掉
	_ensure_core_reward()
	# 石台彩蛋同理：剑已永久取走却又不在身上（拔完立刻死、或老档里丢过）→ 补发一次
	_ensure_reliquary_reward()
	# 位面 BOSS 的首杀门票（破境天髓）同样自愈补发：丢了残晶等于化神之路断掉
	CharacterData.ensure_first_kill_rewards()
	_loot_snapshot = _capture_loot()

	_spawn_due_content()
	_update_hud()
	_seen_region_ids[_current_region_id] = true
	# 新手指引：第 8 章（苍澜大陆）首次出门
	Tutorial.maybe_start("event:world_enter")
	_refresh_region_header(true)


## 离场交还返回键：新场景没声明时，返回键回到「退出确认」
func _exit_tree() -> void:
	GameState.back_uses_esc = false


## 内容表坐标是「区域中心为原点」的局部坐标：深拷贝后整体平移
## ⚠ 表是 const，不能就地改，否则第二次进图会在已偏移的坐标上再偏一次
func _offset_content(def: Dictionary, offset: Vector2) -> Dictionary:
	var out := def.duplicate(true)
	for key in ["portal", "core_boss", "farm", "spawn"]:
		var entry = out.get(key, null)
		if entry is Dictionary and (entry as Dictionary).has("pos"):
			(entry as Dictionary)["pos"] = Vector2((entry as Dictionary)["pos"]) + offset
	for key in ["herbs", "beasts", "qi_orbs", "cultivators", "reliquaries", "god_altars"]:
		var arr = out.get(key, [])
		if not (arr is Array):
			continue
		for raw in arr:
			if raw is Dictionary and (raw as Dictionary).has("pos"):
				(raw as Dictionary)["pos"] = Vector2((raw as Dictionary)["pos"]) + offset
	return out


## 并集内容：所有已解锁区域的草药 / 灵兽 / 灵气团 / 野修合并到一张表；
## 传送门 / 核心首领 / 灵田都按区域各收一份 —— 谁的核心首领被击败，谁的门旁就长田。
## 每条实体带 region_id：野修功法池、掉落与修为按所在区算。
func _collect_open_content() -> Dictionary:
	var out := {"herbs": [], "beasts": [], "qi_orbs": [], "cultivators": [],
		"portals": [], "core_bosses": [], "farms": [], "reliquaries": [], "god_altars": []}
	for raw in get_open_regions():
		var r := raw as Dictionary
		var rid := String(r.get("region_id", ""))
		var rrect: Rect2 = r.get("rect", Rect2())
		var c := _offset_content(SecretWorldDB.get_region_content(rid), rrect.get_center())
		for key in ["herbs", "beasts", "qi_orbs", "cultivators", "reliquaries", "god_altars"]:
			var arr = c.get(key, [])
			if not (arr is Array):
				continue
			for e in arr:
				var ed := (e as Dictionary).duplicate(true)
				ed["region_id"] = rid
				(out[key] as Array).append(ed)
		# 每个区域自己的撤离传送门（练气东南角 / 云隐谷右上角）
		var pc = c.get("portal", null)
		if pc is Dictionary and not (pc as Dictionary).is_empty():
			var pd := (pc as Dictionary).duplicate(true)
			pd["region_id"] = rid
			(out["portals"] as Array).append(pd)
		# 核心首领：每个区域各一个，统一进 core_bosses（同一大世界可同时存在）
		var core = c.get("core_boss", null)
		if core is Dictionary and not (core as Dictionary).is_empty():
			var cd := (core as Dictionary).duplicate(true)
			cd["region_id"] = rid
			(out["core_bosses"] as Array).append(cd)
		# 灵田：每个区域一块，各自按本区核心首领击杀进度解锁
		var farm = c.get("farm", null)
		if farm is Dictionary and not (farm as Dictionary).is_empty():
			var fd := (farm as Dictionary).duplicate(true)
			fd["region_id"] = rid
			(out["farms"] as Array).append(fd)
	return out


# ===================== 场景搭建 =====================

## 地面三条路：配了 terrain 走遮罩+tile；否则退回色块 + 网格 + 斑块 + 边界。
## 色块那套是给还没做地形的区域占位的，纯色会「看不出在移动」，所以要画参照线。
## 没有 terrain 的区域只能铺纯色底。**必须按「这一块地是谁的」取色**：
## 早先这里直接读 region（= 家的区域），结果给九天之上铺了一身练气区的草地。
func _build_ground(rect: Rect2, owner_r: Dictionary = {}) -> void:
	var owner_r2: Dictionary = owner_r if not owner_r.is_empty() else region
	var terrain = owner_r2.get("terrain", {})
	if terrain is Dictionary and not (terrain as Dictionary).is_empty():
		_build_terrain_ground(rect, terrain as Dictionary)
		return

	var base := ColorRect.new()
	base.color = owner_r2.get("ground_color", Color(0.13, 0.19, 0.15, 1.0))
	base.position = rect.position
	base.size = rect.size
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ground.add_child(base)

	var line_color := Color(1.0, 1.0, 1.0, 0.035)
	var x := rect.position.x
	while x <= rect.end.x:
		var vline := ColorRect.new()
		vline.color = line_color
		vline.position = Vector2(x, rect.position.y)
		vline.size = Vector2(1.0, rect.size.y)
		vline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ground.add_child(vline)
		x += GRID_STEP
	var y := rect.position.y
	while y <= rect.end.y:
		var hline := ColorRect.new()
		hline.color = line_color
		hline.position = Vector2(rect.position.x, y)
		hline.size = Vector2(rect.size.x, 1.0)
		hline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ground.add_child(hline)
		y += GRID_STEP

	# 深色斑块：固定种子 → 每次进图位置一致（否则同一片区域看起来会「换地形」）
	# 用柔边椭圆代替硬边 ColorRect，避免草地上出现直角暗块。
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(owner_r2.get("region_id", region_id)))
	var shadow_tex := GradientTexture2D.new()
	shadow_tex.width = 128
	shadow_tex.height = 128
	shadow_tex.fill = GradientTexture2D.FILL_RADIAL
	shadow_tex.fill_from = Vector2(0.5, 0.5)
	shadow_tex.fill_to = Vector2(1.0, 0.5)
	var shadow_grad := Gradient.new()
	shadow_grad.set_color(0, Color(0.0, 0.0, 0.0, 1.0))
	shadow_grad.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	shadow_tex.gradient = shadow_grad
	for i in range(56):
		var patch := Sprite2D.new()
		var psize := Vector2(rng.randf_range(140.0, 460.0), rng.randf_range(90.0, 300.0))
		patch.texture = shadow_tex
		patch.centered = true
		patch.scale = psize / 128.0
		patch.position = Vector2(
			rng.randf_range(rect.position.x + psize.x * 0.5, rect.end.x - psize.x * 0.5),
			rng.randf_range(rect.position.y + psize.y * 0.5, rect.end.y - psize.y * 0.5)
		)
		patch.modulate = Color(1.0, 1.0, 1.0, rng.randf_range(0.10, 0.26))
		patch.rotation = rng.randf_range(-0.5, 0.5)
		ground.add_child(patch)

	var border: Color = owner_r2.get("border_color", Color(0.34, 0.54, 0.34, 1.0))
	_add_border_strip(rect, border)


func _add_border_strip(rect: Rect2, color: Color) -> void:
	var w := 20.0
	var rects: Array = [
		Rect2(rect.position, Vector2(rect.size.x, w)),
		Rect2(Vector2(rect.position.x, rect.end.y - w), Vector2(rect.size.x, w)),
		Rect2(rect.position, Vector2(w, rect.size.y)),
		Rect2(Vector2(rect.end.x - w, rect.position.y), Vector2(w, rect.size.y)),
	]
	for r in rects:
		var strip := ColorRect.new()
		strip.color = Color(color.r, color.g, color.b, 0.55)
		strip.position = r.position
		strip.size = r.size
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ground.add_child(strip)


## 低频遮罩混三套 tile 画满地面，再沿边压两条林带把出图的路挡住。
## 加进去的顺序有意义：东带先、南带后 —— 南带是**侧视**树墙，画在俯视密冠之上
## 才接得住东南那个角；反过来会让密冠像一张贴在树墙上的纸。
func _build_terrain_ground(rect: Rect2, terrain: Dictionary, tag: String = "") -> void:
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	mat.set_shader_parameter("world_size", rect.size)
	mat.set_shader_parameter("tile_world", TILE_WORLD)
	mat.set_shader_parameter("mask_tex", load(String(terrain.get("mask", ""))))
	for key in ["grass", "road", "forest"]:
		mat.set_shader_parameter(key + "_tex", load(String(terrain.get(key, ""))))
	# 区域可覆盖大尺度明暗：赤金丹霞的地表太平，靠这一层把 512px 格网再压散一档
	for key in ["macro_scale", "macro_amount", "jitter_amount"]:
		if terrain.has(key):
			mat.set_shader_parameter(key, float(terrain[key]))
	if terrain.has("decal_tint"):
		mat.set_shader_parameter("decal_tint", terrain["decal_tint"])
	if terrain.has("decal_strength"):
		mat.set_shader_parameter("decal_strength", float(terrain["decal_strength"]))
	_terrain_mats.append(mat)
	_add_ground_plate("TerrainGround" + tag, rect, mat)

	var bands = terrain.get("bands", {})
	if not (bands is Dictionary):
		return
	for side: String in ["east", "west", "north", "south"]:
		var path := String((bands as Dictionary).get(side, ""))
		if path == "" or not ResourceLoader.exists(path):
			continue
		_build_band(side, rect, load(path) as Texture2D, tag)
	# 接缝林带：只画在云隐谷的南沿，中间留出南口；南口与林带都不设碰撞
	var seam_path := String((bands as Dictionary).get("seam", ""))
	if seam_path != "" and ResourceLoader.exists(seam_path):
		var seam_tex := load(seam_path) as Texture2D
		var seam_depth := seam_tex.get_size().y / TEXELS_PER_WORLD
		var gap: Vector2 = terrain.get("seam_gap", Vector2(-360.0, 360.0))
		var cx := rect.get_center().x
		var g0 := clampf(cx + gap.x, rect.position.x, rect.end.x)
		var g1 := clampf(cx + gap.y, rect.position.x, rect.end.x)
		if g0 - rect.position.x > 1.0:
			var rl := Rect2(rect.position.x, rect.end.y - seam_depth, g0 - rect.position.x, seam_depth)
			var fade_l := 0.0
			if rect.position.x > _open_union.position.x + 1.0:
				rl.position.x -= BAND_END_OVERLAP
				rl.size.x += BAND_END_OVERLAP
				fade_l = BAND_END_OVERLAP * 2.0 / rl.size.x
			# 南带的内缘在上、朝练气的一侧在下，两侧都咬一档
			_build_band_plate("Band_seam_l" + tag, rl, seam_tex, true, 2,
				0.10, 0.12, fade_l, BAND_GAP_FADE / rl.size.x, true, 0.035)
		if rect.end.x - g1 > 1.0:
			var rr := Rect2(g1, rect.end.y - seam_depth, rect.end.x - g1, seam_depth)
			var fade_r := 0.0
			if rect.end.x < _open_union.end.x - 1.0:
				rr.size.x += BAND_END_OVERLAP
				fade_r = BAND_END_OVERLAP * 2.0 / rr.size.x
			_build_band_plate("Band_seam_r" + tag, rr, seam_tex, true, 2,
				0.10, 0.12, BAND_GAP_FADE / rr.size.x, fade_r, true, 0.035)
	# 竖向接缝（赤金丹霞 → 云隐谷）：一条沿 y 重复的地面过渡，圆心压在两区边界上
	var vpath := String((terrain as Dictionary).get("seam_vertical", ""))
	if vpath != "" and ResourceLoader.exists(vpath):
		var vtex := load(vpath) as Texture2D
		var vdepth := vtex.get_size().x / TEXELS_PER_WORLD
		var vr := Rect2(rect.end.x - vdepth * 0.5, rect.position.y, vdepth, rect.size.y)
		var vspan := _stretch_plate(vr, false, BAND_END_OVERLAP)
		_build_band_plate("SeamVertical" + tag, vspan["rect"], vtex, false, 3,
			0.0, 0.0, vspan["fade_low"], vspan["fade_high"], true, 0.06)


## 接缝过渡：铺一条**真实的地面过渡纹理**（谷地暗林地 → 草原），不再用乘算暗影。
## 纹理上下自带 alpha 羽化、横向无缝；只夹在地形与林带之间，不加碰撞。
func _build_seam_transitions(open_regions: Array) -> void:
	for raw_n in open_regions:
		for raw_s in open_regions:
			if raw_n == raw_s:
				continue
			var north := raw_n as Dictionary
			var south := raw_s as Dictionary
			var nr: Rect2 = north.get("rect", Rect2())
			var sr: Rect2 = south.get("rect", Rect2())
			# 北区下沿贴南区上沿（云隐谷南沿 / 青岚野北沿；结丹南沿 / 幽冥北沿）
			if absf(nr.end.y - sr.position.y) > 1.0:
				continue
			var x0 := maxf(nr.position.x, sr.position.x)
			var x1 := minf(nr.end.x, sr.end.x)
			if x1 - x0 <= 1.0:
				continue
			# 南区可指定自己的横向接缝（幽冥 → 结丹用紫雾过渡，不再借云隐的冷绿）
			var tex_path := SEAM_TRANSITION_TEX
			var south_terrain = south.get("terrain", {})
			if south_terrain is Dictionary:
				var override := String((south_terrain as Dictionary).get("seam_horizontal", ""))
				if override != "":
					tex_path = override
			var tex := load(tex_path) as Texture2D
			if tex == null:
				push_warning("接缝过渡纹理缺失：" + tex_path)
				continue
			var depth := tex.get_size().y / TEXELS_PER_WORLD
			var r := Rect2(x0, nr.end.y - SEAM_TRANSITION_ABOVE, x1 - x0, depth)
			var span := _stretch_plate(r, true, BAND_END_OVERLAP)
			_build_band_plate("SeamTransition_%s_%s" % [
				String(north.get("region_id", "")),
				String(south.get("region_id", ""))], span["rect"], tex, true, 3,
				0.0, 0.0, span["fade_low"], span["fade_high"], true, 0.06)


## 多区交汇点补片：四个象限都被已解锁区域占满时，把 SecretWorldDB.CORNER_CAPS
## 里的贴图按原生密度铺在交汇点上（z=4，压在接缝带之上）。
func _build_corner_caps(open_regions: Array) -> void:
	for raw in SecretWorldDB.CORNER_CAPS:
		var cap := raw as Dictionary
		var pos: Vector2 = cap.get("pos", Vector2.ZERO)
		var tex_path := String(cap.get("tex", ""))
		if tex_path == "" or not ResourceLoader.exists(tex_path):
			continue
		var covered := 0
		for r in open_regions:
			var rr: Rect2 = (r as Dictionary).get("rect", Rect2())
			for c in [rr.position, Vector2(rr.end.x, rr.position.y), rr.end,
					Vector2(rr.position.x, rr.end.y)]:
				if pos.distance_to(c) < 1.0:
					covered += 1
					break
		if covered < 4:
			continue
		var tex := load(tex_path) as Texture2D
		var plate_size := Vector2(tex.get_size()) / TEXELS_PER_WORLD
		var plate := TextureRect.new()
		plate.name = "CornerCap_%d_%d" % [roundi(pos.x), roundi(pos.y)]
		plate.texture = tex
		plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		plate.stretch_mode = TextureRect.STRETCH_SCALE
		plate.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		plate.position = pos - plate_size * 0.5
		plate.size = plate_size
		plate.z_index = 4
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ground.add_child(plate)


## 一条边上的林带。长边是重复方向，短边换算成带子在世界里的深度；
## 密度必须和 tile 一致（1.75 texel/世界像素），否则树会比草明显更锐或更糊。
## 2026-11-01：长边两端朝邻区多铺一段再交叉淡出；朝活动区的内缘咬出不规则边。
func _build_band(side: String, rect: Rect2, tex: Texture2D, tag: String = "") -> void:
	var along_x := side == "south" or side == "north"
	var px := Vector2(tex.get_size())
	var depth := (px.y if along_x else px.x) / TEXELS_PER_WORLD
	var r: Rect2
	match side:
		"south":
			r = Rect2(rect.position.x, rect.end.y - depth, rect.size.x, depth)
		"north":
			r = Rect2(rect.position.x, rect.position.y, rect.size.x, depth)
		"east":
			r = Rect2(rect.end.x - depth, rect.position.y, depth, rect.size.y)
		_:
			r = Rect2(rect.position.x, rect.position.y, depth, rect.size.y)
	var span := _stretch_plate(r, along_x, BAND_END_OVERLAP)
	var carve_low := 0.0
	var carve_high := 0.0
	if along_x:
		if side == "south":
			carve_low = 0.12
			# 南带下沿只有落在并集内部（如结丹南崖接幽冥）才咬；地图外沿不动
			if rect.end.y < _open_union.end.y - 1.0:
				carve_high = 0.14
		else:
			carve_high = 0.12
			if rect.position.y > _open_union.position.y + 1.0:
				carve_low = 0.14
	else:
		if side == "east":
			carve_low = 0.12
			if rect.end.x < _open_union.end.x - 1.0:
				carve_high = 0.14
		else:
			carve_high = 0.12
			if rect.position.x > _open_union.position.x + 1.0:
				carve_low = 0.14
	_build_band_plate("Band_" + side + tag, span["rect"], tex, along_x, 2,
		carve_low, carve_high, span["fade_low"], span["fade_high"], true, 0.035)


## 长轴两端只朝并集内部多铺：贴邻区的一端延伸 overlap，并按 2×overlap 淡出，
## 让交界线落在两条带子各约 50% 处；地图外沿不延伸也不淡出。
func _stretch_plate(r: Rect2, along_x: bool, overlap: float) -> Dictionary:
	var low_in := false
	var high_in := false
	if along_x:
		low_in = r.position.x > _open_union.position.x + 1.0
		high_in = r.end.x < _open_union.end.x - 1.0
	else:
		low_in = r.position.y > _open_union.position.y + 1.0
		high_in = r.end.y < _open_union.end.y - 1.0
	if low_in:
		if along_x:
			r.position.x -= overlap
			r.size.x += overlap
		else:
			r.position.y -= overlap
			r.size.y += overlap
	if high_in:
		if along_x:
			r.size.x += overlap
		else:
			r.size.y += overlap
	var span := r.size.x if along_x else r.size.y
	var fade := overlap * 2.0 / maxf(span, 1.0)
	return {
		"rect": r,
		"fade_low": fade if low_in else 0.0,
		"fade_high": fade if high_in else 0.0,
	}


func _build_band_plate(node_name: String, r: Rect2, tex: Texture2D,
		along_x: bool, z_index: int = 2, carve_low: float = 0.0,
		carve_high: float = 0.0, fade_low: float = 0.0,
		fade_high: float = 0.0, mirror: bool = true,
		shade_jitter: float = 0.0) -> void:
	var px := Vector2(tex.get_size())
	var span := r.size.x if along_x else r.size.y
	var band_mat := ShaderMaterial.new()
	band_mat.shader = BAND_SHADER
	band_mat.set_shader_parameter("band_tex", tex)
	band_mat.set_shader_parameter("along_y", not along_x)
	band_mat.set_shader_parameter("repeat_count",
		span / ((px.x if along_x else px.y) / TEXELS_PER_WORLD))
	band_mat.set_shader_parameter("mirror", mirror)
	band_mat.set_shader_parameter("shade_jitter", shade_jitter)
	band_mat.set_shader_parameter("carve_low", carve_low)
	band_mat.set_shader_parameter("carve_high", carve_high)
	band_mat.set_shader_parameter("end_fade_low", fade_low)
	band_mat.set_shader_parameter("end_fade_high", fade_high)
	_add_ground_plate(node_name, r, band_mat, z_index)


func _add_ground_plate(node_name: String, r: Rect2, mat: Material,
		z_index: int = 0) -> void:
	var plate := ColorRect.new()
	plate.name = node_name
	plate.material = mat
	plate.position = r.position
	plate.size = r.size
	plate.z_index = z_index
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ground.add_child(plate)


## 地面 tile 的 mipmap 层级由脚本喂，不交给 GPU 用屏幕差分猜：逐格镜像那版在格边界上
## 让差分看到将近一整格的跳变，那一列被挑到最深的 mip，地面上多出一条直线（实机见过）。
## 换成连续域扭曲后差分不再跳，但顶视平面的缩放本来就处处一致，没必要让 GPU 去猜 ——
## 直接按「一个 texel 占几个屏幕像素」算，顺带得到可复现的参数（自检钉 lod 也不用改 shader）。
## 缩放 = canvas_transform（含相机 zoom）× final_transform（含窗口拉伸）。
## 注意别用 get_screen_transform()：实测它只到 GUI 层，相机 zoom 不在里面。
func _sync_terrain_lod() -> void:
	if _terrain_mats.is_empty():
		return
	var vp := get_viewport()
	var px_per_world := absf(vp.get_canvas_transform().x.x * vp.get_final_transform().x.x)
	if px_per_world <= 0.0:
		return
	var lod := maxf(0.0, log(TEXELS_PER_WORLD / px_per_world) / log(2.0))
	if absf(lod - _terrain_lod) < 0.01:
		return
	_terrain_lod = lod
	for m in _terrain_mats:
		if is_instance_valid(m):
			(m as ShaderMaterial).set_shader_parameter("tile_lod", lod)


func _spawn_player(rect: Rect2, spawn_region_id: String) -> void:
	var target_rid := spawn_region_id if spawn_region_id != "" else region_id
	var target_rect: Rect2 = SecretWorldDB.get_region(target_rid).get("rect", rect)
	var target_content := SecretWorldDB.get_region_content(target_rid)
	var spawn := rect.get_center() + Vector2(-2600.0, 0.0)

	if target_rid == region_id:
		# 默认入口：本区传送门旁（练气 = 东南角）
		var pd = target_content.get("portal", {})
		if pd is Dictionary:
			spawn = Vector2((pd as Dictionary).get("pos", spawn - target_rect.get_center())) \
				+ target_rect.get_center()
			spawn += Vector2((pd as Dictionary).get("spawn_offset", Vector2(240.0, 120.0)))
	else:
		# 区域面板直接进云隐谷：用该区配置的落点（右上角）；没有就退回该区传送门旁
		var spd = target_content.get("spawn", {})
		if spd is Dictionary and (spd as Dictionary).has("pos"):
			spawn = Vector2((spd as Dictionary)["pos"]) + target_rect.get_center()
		else:
			var pd2 = target_content.get("portal", {})
			if pd2 is Dictionary:
				spawn = Vector2((pd2 as Dictionary).get("pos", spawn - target_rect.get_center())) \
					+ target_rect.get_center()
				spawn += Vector2((pd2 as Dictionary).get("spawn_offset", Vector2(240.0, 120.0)))
	var walkable := _inner_rect(rect).grow(-40.0)
	spawn.x = clampf(spawn.x, walkable.position.x, walkable.end.x)
	spawn.y = clampf(spawn.y, walkable.position.y, walkable.end.y)
	player.global_position = spawn
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		cam.position = Vector2.ZERO
		cam.reset_smoothing()


## 已解锁区域的**并集矩形**：炼气(0,0)+筑基(0,-4000) 时得到 6000×8000 的一张图。
## 相机 limit、墙、出生点钳制都该用它；逐区地形仍按各自 rect 铺（见 _build_terrain_ground）。
## 2026-10-28 筑基区并集加载第一步：先提供入口，_ready 的接线下一步做。
func get_open_rect() -> Rect2:
	var out := Rect2()
	var first := true
	for r in SecretWorldDB.REGIONS:
		if not SecretWorldDB.is_region_open(r as Dictionary):
			continue
		var rr: Rect2 = (r as Dictionary).get("rect", Rect2())
		if first:
			out = rr
			first = false
		else:
			out = out.merge(rr)
	return out


## 已解锁区域列表（按 order 升序；并集铺地/接缝判断都用它）
func get_open_regions() -> Array:
	var out: Array = []
	for r in SecretWorldDB.REGIONS:
		if SecretWorldDB.is_region_open(r as Dictionary):
			out.append(r)
	out.sort_custom(func(a, b): return int((a as Dictionary).get("order", 0)) < int((b as Dictionary).get("order", 0)))
	return out


func _apply_camera_limits(rect: Rect2) -> void:
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	cam.limit_left = int(round(rect.position.x))
	cam.limit_right = int(round(rect.end.x))
	cam.limit_top = int(round(rect.position.y))
	cam.limit_bottom = int(round(rect.end.y))


## 并集每条边的内缩：取**贴在那条边上**的已解锁区域的 wall_inset。
## 例：北边是云隐谷（北带深 470）就吃它的 480；南边是青岚野就吃它的 355。
## 只有一块区域时，结果与旧的单区行为完全一致。
func _wall_inset(side: StringName, union_rect: Rect2) -> float:
	for raw in SecretWorldDB.REGIONS:
		var r := raw as Dictionary
		if not SecretWorldDB.is_region_open(r):
			continue
		var rr: Rect2 = r.get("rect", Rect2())
		var on_edge := false
		match side:
			&"west":
				on_edge = absf(rr.position.x - union_rect.position.x) <= 0.5
			&"east":
				on_edge = absf(rr.end.x - union_rect.end.x) <= 0.5
			&"north":
				on_edge = absf(rr.position.y - union_rect.position.y) <= 0.5
			&"south":
				on_edge = absf(rr.end.y - union_rect.end.y) <= 0.5
		if not on_edge:
			continue
		var ins = r.get("wall_inset", WALL_INSET)
		if ins is Dictionary:
			return float((ins as Dictionary).get(side, WALL_INSET))
		return float(ins)
	return WALL_INSET


## 可走范围：rect 按边内缩后的矩形（物理墙、BOSS 逻辑边界、出生点钳制共用）
func _inner_rect(rect: Rect2) -> Rect2:
	var w := _wall_inset(&"west", rect)
	var e := _wall_inset(&"east", rect)
	var n := _wall_inset(&"north", rect)
	var s := _wall_inset(&"south", rect)
	return Rect2(
		rect.position + Vector2(w, n),
		Vector2(maxf(rect.size.x - w - e, 0.0), maxf(rect.size.y - n - s, 0.0))
	)


func _build_walls(rect: Rect2) -> void:
	var inner := _inner_rect(rect)
	var body := StaticBody2D.new()
	body.name = "Barrier"
	body.collision_layer = WALL_LAYER
	body.collision_mask = 0
	add_child(body)

	var t := WALL_THICKNESS
	var c := inner.get_center()
	_add_wall(body, Vector2(inner.position.x - t * 0.5, c.y), Vector2(t, inner.size.y + t * 2.0))
	_add_wall(body, Vector2(inner.end.x + t * 0.5, c.y), Vector2(t, inner.size.y + t * 2.0))
	_add_wall(body, Vector2(c.x, inner.position.y - t * 0.5), Vector2(inner.size.x + t * 2.0, t))
	_add_wall(body, Vector2(c.x, inner.end.y + t * 0.5), Vector2(inner.size.x + t * 2.0, t))


## 接缝不再设隐形挡墙（2026-10-29 用户定：交界处可以不设置屏障）。
## 视觉上保留南口与树带，但玩家可以从任意位置跨区；外圈地图墙仍在 _build_walls 里。


func _add_wall(body: StaticBody2D, center: Vector2, size: Vector2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = center
	body.add_child(cs)


# ===================== 内容生成 =====================

## 每次进图 / 每秒触发：把「到点该出现」的资源补回场上
func _spawn_due_content() -> void:
	if _dead or _leaving or region.is_empty():
		return
	var now := _now()

	for raw in _content_def.get("portals", []):
		var pd := raw as Dictionary
		var prid := String(pd.get("region_id", ""))
		var pid := "portal_" + prid
		if _resources.has(pid):
			continue
		_spawn_portal(Vector2(pd.get("pos", _region_rect().get_center() + Vector2(-2600.0, 0.0))), prid)

	for h in _content_def.get("herbs", []):
		var hd: Dictionary = h
		var nid := String(hd.get("node_id", ""))
		if nid == "" or _resources.has(nid) or not _node_due(nid, now):
			continue
		_spawn_herb(hd)

	for q in _content_def.get("qi_orbs", []):
		var qd: Dictionary = q
		var nid := String(qd.get("node_id", ""))
		if nid == "" or _resources.has(nid) or not _node_due(nid, now):
			continue
		_spawn_qi(qd)

	for b in _content_def.get("beasts", []):
		var bd: Dictionary = b
		var nid := String(bd.get("node_id", ""))
		if nid == "" or _enemies.has(nid) or not _node_due(nid, now):
			continue
		_spawn_beast(bd)

	for raw_core in _content_def.get("core_bosses", []):
		var core_cfg: Dictionary = raw_core
		var core_rid := String(core_cfg.get("region_id", region_id))
		var core_nid := String(SecretWorldDB.get_core_boss(core_rid).get("node_id", ""))
		if core_nid == "" or _enemies.has(core_nid):
			continue
		if CharacterData.is_core_killed(core_rid):
			continue
		_spawn_core(core_cfg)
	for raw_farm in _content_def.get("farms", []):
		var fd: Dictionary = raw_farm
		var frid := String(fd.get("region_id", region_id))
		if CharacterData.is_core_killed(frid):
			_spawn_farm_if_unlocked(fd)

	# 石台插剑（彩蛋设施）：**永久**一次性 —— 判据是「表里有没有这条记录」，
	# ⚠ 绝对不能用 _node_due()：它只认 "at"，缺 "at" 的记录会被它当场 erase 并返回 true，
	#   等于「没标记」，剑每次进图都会复活。
	for raw_rel in _content_def.get("reliquaries", []):
		var rd: Dictionary = raw_rel
		var rnid := String(rd.get("node_id", ""))
		if rnid == "" or _resources.has(rnid) or _nodes_table().has(rnid):
			continue
		_spawn_reliquary(rd)

	# 铸神祭坛：每区一座、常驻不消失；阶段存在 CharacterData.secret_world.god_altars
	for raw_alt in _content_def.get("god_altars", []):
		var ad: Dictionary = raw_alt
		var anid := String(ad.get("node_id", ""))
		if anid == "" or _resources.has(anid):
			continue
		_spawn_god_altar(ad)

	for c in _content_def.get("cultivators", []):
		var cd: Dictionary = c
		var slot := String(cd.get("slot_id", ""))
		if slot == "" or _enemies.has(slot):
			continue
		if _cultivator_due(slot, now):
			_spawn_cultivator(cd, now)


func _spawn_portal(pos: Vector2, portal_region_id: String = "") -> void:
	var rid := portal_region_id if portal_region_id != "" else region_id
	var res := WorldResource.new()
	res.setup(WorldResource.KIND_PORTAL, "portal_" + rid, "world_portal", "返回原初位面")
	res.position = pos
	content.add_child(res)
	_portal = res
	_portals.append(res)
	_resources[res.node_id] = res


func _spawn_herb(cfg: Dictionary) -> void:
	var mid := String(cfg.get("material", ""))
	if mid == "":
		return
	var def := ItemDB.get_material(mid)
	var res := WorldResource.new()
	res.setup(
		WorldResource.KIND_HERB,
		String(cfg.get("node_id", "")),
		SecretWorldDB.get_herb_visual(mid),
		String(def.get("name", mid))
	)
	res.material_id = mid
	res.herb_sink = _collect_material
	res.position = Vector2(cfg.get("pos", Vector2.ZERO))
	content.add_child(res)
	_resources[res.node_id] = res


## 石台插剑（一次性彩蛋设施）：外观走 ArtDB.world_sword_shrine，
## 拔剑**直接进永久背包**（用户 2026-11-12 定），成功后由 _on_resource_gone 落永久标记。
func _spawn_god_altar(cfg: Dictionary) -> void:
	var res := WorldResource.new()
	res.setup(WorldResource.KIND_GOD_ALTAR, String(cfg.get("node_id", "")),
		"world_god_altar", "铸神祭坛")
	res.position = Vector2(cfg.get("pos", Vector2.ZERO))
	content.add_child(res)
	_resources[res.node_id] = res


func _spawn_reliquary(cfg: Dictionary) -> void:
	var res := WorldResource.new()
	res.setup(
		WorldResource.KIND_RELIQUARY,
		String(cfg.get("node_id", "")),
		String(cfg.get("visual_id", "world_sword_shrine")),
		String(cfg.get("display_name", "问天剑"))
	)
	res.reward_equipment = String(cfg.get("reward_equipment", ""))
	res.position = Vector2(cfg.get("pos", Vector2.ZERO))
	content.add_child(res)
	_resources[res.node_id] = res


## 一次性设施的自愈：已经拔过（nodes 里有 taken 记录）但玩家**完全不再持有**这把剑 →
## 补发一次。剑进的是永久背包，但背包本身会被死亡回滚拍回进图时的快照，
## 所以「拔完立刻死」照样能把彩蛋删掉；补发只在真放不下时（装备包 100 格满）才静默跳过，
## 下次进图再试。与 _ensure_core_reward 同一个动机、同一个调用点。
func _ensure_reliquary_reward() -> void:
	var changed := false
	for raw in _content_def.get("reliquaries", []):
		var rd: Dictionary = raw
		var rnid := String(rd.get("node_id", ""))
		var eid := String(rd.get("reward_equipment", ""))
		if rnid == "" or eid == "":
			continue
		if not _nodes_table().has(rnid):
			continue
		if CharacterData.owns_equipment(eid):
			continue
		var tpl := ItemDB.get_equipment_template(eid)
		if tpl.is_empty():
			continue
		changed = CharacterData.add_item(CharacterData.make_equipment_instance(tpl)) \
				or changed
	if changed:
		SaveManager.auto_save()


## 玩家是否还持有这件装备 —— 走 CharacterData.owns_equipment（背包 + 穿戴槽 + 法宝槽）。
## ⚠ 局内背包 `_run_items` 不算：那部分死亡会清，靠它判「还在手上」会漏。


func _spawn_qi(cfg: Dictionary) -> void:
	var anchor := Vector2(cfg.get("pos", Vector2.ZERO))
	var radius := float(cfg.get("radius", 220.0))
	var res := WorldResource.new()
	res.setup(WorldResource.KIND_QI, String(cfg.get("node_id", "")), "world_qi_orb", "灵气团")
	res.position = SecretWorldDB.random_point_near(anchor, radius)
	content.add_child(res)
	_resources[res.node_id] = res


func _spawn_beast(cfg: Dictionary) -> void:
	var beast_id := String(cfg.get("beast_id", ""))
	var beast := SecretWorldDB.get_beast(beast_id)
	if beast.is_empty():
		return
	var nid := String(cfg.get("node_id", ""))
	var stats := beast.duplicate(true)
	stats["pos"] = Vector2(cfg.get("pos", Vector2.ZERO))
	var enemy := ENEMY_SCENE.instantiate() as WorldEnemy
	enemy.node_id = nid
	enemy.configure(stats, WorldEnemy.KIND_BEAST, String(beast.get("name", "灵兽")))
	enemy.position = Vector2(stats["pos"])
	content.add_child(enemy)
	enemy.world_died.connect(_on_enemy_died.bind({
		"kind": WorldEnemy.KIND_BEAST, "node_id": nid, "beast": beast_id,
		"region_id": String(cfg.get("region_id", region_id)),
	}))
	_enemies[nid] = enemy


func _spawn_core(core_cfg: Dictionary) -> void:
	var rid := String(core_cfg.get("region_id", region_id))
	var pos := Vector2(core_cfg.get("pos", Vector2.ZERO))
	var stats: Dictionary = SecretWorldDB.get_core_boss(rid).duplicate(true)
	if stats.is_empty():
		stats = core_cfg.duplicate(true)
	stats["pos"] = pos
	var nid := String(stats.get("node_id", "core"))
	var scene_path := String(stats.get("scene", ""))
	var packed: PackedScene = load(scene_path) as PackedScene \
		if scene_path != "" and ResourceLoader.exists(scene_path) else ENEMY_SCENE
	var enemy := packed.instantiate() as WorldEnemy
	if enemy == null:
		push_warning("核心首领场景不是 WorldEnemy：" + scene_path)
		return
	enemy.node_id = nid
	enemy.boss_id = String(SecretWorldDB.get_region(rid).get("core_boss_id", ""))
	enemy.configure(stats, WorldEnemy.KIND_CORE, String(stats.get("name", "核心首领")))
	enemy.position = pos
	content.add_child(enemy)
	enemy.world_died.connect(_on_enemy_died.bind({
		"kind": WorldEnemy.KIND_CORE, "node_id": nid, "region_id": rid,
	}))
	_enemies[nid] = enemy
	_build_core_landmark(pos, rid)


## 区域纯景观地标（目前只有幽冥灵墟的中央山门）。不参与战斗、不加碰撞。
func _build_region_landmark(r: Dictionary) -> void:
	var lm = r.get("landmark", null)
	if not (lm is Dictionary):
		return
	var tex_path := String((lm as Dictionary).get("texture", ""))
	if tex_path == "" or not ResourceLoader.exists(tex_path):
		return
	var tex := load(tex_path) as Texture2D
	if tex == null:
		return
	var scale := float((lm as Dictionary).get("scale", 0.4))
	var rect: Rect2 = r.get("rect", Rect2())
	var pos: Vector2 = rect.get_center() + Vector2((lm as Dictionary).get("pos", Vector2.ZERO))
	var spr := Sprite2D.new()
	spr.name = "RegionLandmark_" + String(r.get("region_id", ""))
	spr.texture = tex
	spr.centered = false
	spr.scale = Vector2.ONE * scale
	# 贴图底边压在地标点上，和 WorldEnemy 的 anchor_bottom 同口径
	spr.position = pos + Vector2(-tex.get_width() * scale * 0.5, -tex.get_height() * scale)
	spr.z_index = 1
	ground.add_child(spr)


## 九天门的交互节点：开在幽冥灵墟中心那张贴山门图上（坐标同一个算式，见
## SecretWorldDB.huashen_gate_pos()）。元婴区一开就常驻 —— 门看得见、走得近，
## 只是条件不够时按 F 只会告诉你还差什么。
func _build_huashen_gate() -> void:
	if _resources.has("huashen_gate"):
		return
	var yy := SecretWorldDB.get_region(SecretWorldDB.REGION_YUANYING)
	if yy.is_empty() or not SecretWorldDB.is_region_open(yy):
		return
	var gate := HuashenGate.new()
	gate.name = "HuashenGate"
	gate.setup_gate()
	gate.global_position = SecretWorldDB.huashen_gate_pos()
	add_child(gate)
	_resources["huashen_gate"] = gate


## 化神坛：九天之上中央的突破点。只有开过门、九天之上真的铺进图里时才建。
func _build_huashen_altar() -> void:
	if _resources.has("huashen_altar"):
		return
	var hs := SecretWorldDB.get_region(SecretWorldDB.REGION_HUASHEN)
	if hs.is_empty() or not SecretWorldDB.is_region_open(hs):
		return
	var altar := HuashenGate.new()
	altar.name = "HuashenAltar"
	altar.setup_altar()
	altar.global_position = SecretWorldDB.huashen_altar_pos()
	add_child(altar)
	_resources["huashen_altar"] = altar


## 铸神祭坛：阶段 0 取铸神晶×1；阶段 1 且已化神 → 铸神晶×1 + 补天石×7；阶段 2 已空。
## 奖励直接进**主背包**（不是局内背包）；背包放不下就整份留在祭坛上，不推进阶段。
func _on_god_altar(altar: WorldResource) -> void:
	var nid := altar.node_id
	var stage := CharacterData.god_altar_stage(nid)
	if stage >= 2:
		_show_announcement("祭坛上的封印已经取空。", UIKit.C_TEXT_DIM, 1.8)
		return
	if stage == 1 and not CharacterData.is_huashen():
		_show_announcement("祭坛沉寂 —— 在九天之上突破化神后，可再来取第二份。",
			UIKit.C_WARN, 2.8)
		return
	var reward: Dictionary = (SecretWorldDB.GOD_ALTAR_FIRST if stage == 0 		else SecretWorldDB.GOD_ALTAR_HUASHEN).duplicate(true)
	# 九天之上的祭坛（化神后的第二份）：额外给蕴仙髓 ×12（2026-11-13 用户定）
	if stage == 1 and nid == "hs_god_altar":
		reward[CharacterData.YUNXIAN_MATERIAL] = 12
	for mid in reward.keys():
		if not CharacterData.bag_has_room({"id": String(mid), "type": CharacterData.ITEM_MATERIAL}):
			_show_announcement("背包已满，%s 先留在祭坛上" % ItemDB.get_material_name(String(mid)),
				UIKit.C_DANGER, 2.4)
			return
	var parts: Array[String] = []
	for mid in reward.keys():
		var n := int(reward[mid])
		CharacterData.grant_material(String(mid), n)
		parts.append("%s ×%d" % [ItemDB.get_material_name(String(mid)), n])
	CharacterData.set_god_altar_stage(nid, stage + 1)
	altar.refresh_altar_look()
	SaveManager.auto_save()
	GameState.play_ui("forge_great")
	_show_announcement("获得 %s（已入主背包）" % "、".join(parts), UIKit.C_ASCEND, 3.0)


## 按 F 在门口：条件不足只提示；够了就开门并把人送进九天之上（门不吃材料）。
func _on_huashen_gate() -> void:
	var check := CharacterData.huashen_gate_check()
	if not bool(check.get("ok", false)):
		_show_announcement(String(check.get("message", "")), UIKit.C_WARN, 3.0)
		return
	if not CharacterData.huashen_gate_opened:
		if not CharacterData.open_huashen_gate():
			_show_announcement("九天门未开：需元婴后期圆满，且背包里要有完整的化神破境晶",
				UIKit.C_DANGER, 2.4)
			return
		# 开门位必须立刻落盘：回档到开门之前，玩家会站在门外却已经进不去
		SaveManager.auto_save()
		GameState.play_ui("forge_great")
		_show_announcement("九天门开 —— 踏入九天之上，中央的化神坛才是突破之处",
			UIKit.C_ASCEND, 3.4)
	_travel_to_region(SecretWorldDB.REGION_HUASHEN)


## 按 F 在坛前：这一步才真正吃掉化神破境晶、当场突破化神。
func _on_huashen_altar() -> void:
	var check := CharacterData.huashen_altar_check()
	if not bool(check.get("ok", false)):
		_show_announcement(String(check.get("message", "")), UIKit.C_WARN, 3.0)
		return
	if not CharacterData.perform_huashen_breakthrough():
		_show_announcement("突破失败：化神破境晶不在背包里", UIKit.C_DANGER, 2.2)
		return
	# 晶已消耗、境界已推进：不回档就立刻存一次，否则回档会留下「有门无晶」的死局
	SaveManager.auto_save()
	GameState.play_ui("forge_great")
	_show_announcement("登坛突破 · 化神 —— 第一篇章至此终局", UIKit.C_ASCEND, 3.6)


## 换区：和区域面板走同一条路（先落 pending_spawn_region，再重载苍澜大陆）
func _travel_to_region(region_id: String) -> void:
	if _leaving:
		return
	_leaving = true
	SecretWorldDB.pending_spawn_region = region_id
	GameState.reset_time_flow()
	get_tree().change_scene_to_file("res://scenes/world/secret_world.tscn")


## 谷心苔石圈 + 冷雾：只给云隐谷核心；霞心日轮祭坛：只给赤金丹霞核心。
func _build_core_landmark(pos: Vector2, rid: String) -> void:
	if rid == SecretWorldDB.REGION_JIEDAN:
		_build_jiedan_altar(pos)
		return
	if rid != "world_zhuji":
		return
	var ring_tex: Texture2D = load("res://assets/scenes/zhuji_stone_ring.png")
	if ring_tex != null:
		var ring := Sprite2D.new()
		ring.name = "CangjiaoStoneRing"
		ring.texture = ring_tex
		ring.centered = true
		ring.position = pos
		ring.z_index = -8
		var ring_w := 560.0
		ring.scale = Vector2.ONE * (ring_w / float(ring_tex.get_width()))
		add_child(ring)
	# 贴地冷雾：低透明柔光，慢慢呼吸
	var mist := Sprite2D.new()
	mist.texture = SkillFx.dot_texture()
	mist.centered = true
	mist.position = pos
	mist.z_index = -7
	mist.scale = Vector2(4.2, 1.8)
	mist.modulate = Color(0.58, 0.84, 1.0, 0.12)
	add_child(mist)
	var tw := create_tween().set_loops()
	tw.tween_property(mist, "modulate:a", 0.20, 2.8).set_trans(Tween.TRANS_SINE)
	tw.tween_property(mist, "modulate:a", 0.10, 2.8).set_trans(Tween.TRANS_SINE)


## 霞心日轮祭坛：火麟站在坛心；坛心亮着地火，呼吸式明灭。
## 二阶段「日轮当空」的视觉中心就是这座坛，不再另铺一张假圆环。
func _build_jiedan_altar(pos: Vector2) -> void:
	var tex: Texture2D = load("res://assets/scenes/jiedan_sun_altar.png")
	if tex != null:
		var altar := Sprite2D.new()
		altar.name = "JiedanSunAltar"
		altar.texture = tex
		altar.centered = true
		altar.position = pos
		altar.z_index = -8
		altar.scale = Vector2.ONE * (980.0 / float(tex.get_width()))
		add_child(altar)
	var glow := Sprite2D.new()
	glow.texture = SkillFx.dot_texture()
	glow.centered = true
	glow.position = pos
	glow.z_index = -7
	glow.scale = Vector2(2.6, 2.6)
	glow.modulate = Color(1.0, 0.62, 0.22, 0.16)
	glow.material = SkillFx.additive_material()
	add_child(glow)
	var tw := create_tween().set_loops()
	tw.tween_property(glow, "modulate:a", 0.30, 2.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(glow, "modulate:a", 0.14, 2.2).set_trans(Tween.TRANS_SINE)


## 灵田：本区核心首领击杀后，在**本区传送门旁**出现一片九块荒地，之后常驻（不刷新、不消失）。
## 区域内容表给的是整片田的中心与行列间距；plot_base 把存档格分段，三区灵田互不串。
func _spawn_farm_if_unlocked(cfg: Dictionary) -> void:
	if cfg.is_empty():
		return
	var prefix := String(cfg.get("node_id_prefix", "lq_farm"))
	var base := int(cfg.get("plot_base", 0))
	var rid := String(cfg.get("region_id", region_id))
	var center := Vector2(cfg.get("pos", Vector2.ZERO))
	var cols := maxi(1, int(cfg.get("cols", 3)))
	var rows := maxi(1, int(cfg.get("rows", 2)))
	var spacing := Vector2(cfg.get("spacing", Vector2(138.0, 100.0)))

	var created := false
	for i in range(mini(CharacterData.PLOT_COUNT, cols * rows)):
		var nid := "%s_%d" % [prefix, i]
		if _resources.has(nid):
			continue
		var plot := FarmPlot.new()
		plot.set_meta("tut", "world.farm")
		plot.setup(WorldResource.KIND_FARM, nid, "", "灵田")
		plot.plot_index = i
		plot.state_base = base
		plot.region_id = rid
		var col := i % cols
		var row := int(i / cols)
		plot.position = center + Vector2(
			(float(col) - (float(cols) - 1.0) * 0.5) * spacing.x,
			(float(row) - (float(rows) - 1.0) * 0.5) * spacing.y
		)
		content.add_child(plot)
		_resources[nid] = plot
		created = true

	if created and not bool(_farm_announced.get(prefix, false)):
		_farm_announced[prefix] = true
		var region_name := String(SecretWorldDB.get_region(rid).get("name", "此地"))
		_show_announcement("%s的传送门旁多出九块荒地 —— 站上去施展「猛虎踏地」才能开垦"
			% region_name, UIKit.C_OK, 3.0)


## 修士槽位判定：
##   记录里的 at 在未来 = 上一次刷出的修士仍在「存活窗口」内 → 进图直接重建
##   at 已过 / 无记录                       → 按概率重新判定
##   ⚠ 击杀后也会写一条 at 在未来的记录，但**不带 skills** —— 那是复活等待，
##     不能当成存活窗口，否则修士会在下一秒原地复活且没有功法
func _cultivator_due(slot: String, now: float) -> bool:
	var table := _cultivators_table()
	var rec = table.get(slot, null)
	if rec is Dictionary:
		var at := float((rec as Dictionary).get("at", 0.0))
		if at > now:
			var saved = (rec as Dictionary).get("skills", [])
			return saved is Array and not (saved as Array).is_empty()
		table.erase(slot)
	return true


func _spawn_cultivator(cfg: Dictionary, now: float) -> void:
	var slot := String(cfg.get("slot_id", ""))
	var rid := String(cfg.get("region_id", region_id))
	var table := _cultivators_table()
	var rec = table.get(slot, null)
	var skills: Array = []

	if rec is Dictionary and float((rec as Dictionary).get("at", 0.0)) > now:
		var saved = (rec as Dictionary).get("skills", [])
		if saved is Array and not (saved as Array).is_empty():
			skills = (saved as Array).duplicate()
	if skills.is_empty():
		if randf() > float(cfg.get("chance", 0.5)):
			table[slot] = {"at": now + SecretWorldDB.CULTIVATOR_RECHECK}
			return
		skills = _roll_cultivator_skills(rid)
		if skills.is_empty():
			table[slot] = {"at": now + SecretWorldDB.CULTIVATOR_RECHECK}
			return

	var anchor := Vector2(cfg.get("pos", Vector2.ZERO))
	var pos := SecretWorldDB.random_point_near(anchor, float(cfg.get("radius", 170.0)))
	var stats: Dictionary = SecretWorldDB.get_cultivator(rid).duplicate(true)
	stats["pos"] = pos
	stats["skills"] = skills
	var enemy := ENEMY_SCENE.instantiate() as WorldEnemy
	enemy.node_id = slot
	enemy.configure(stats, WorldEnemy.KIND_CULTIVATOR, String(stats.get("name", "野修")))
	# 出生时决定是否携带法宝；携带者在战斗中会主动使用，死亡时**必定**掉落同一件
	enemy.carried_treasure = _roll_cultivator_treasure(rid)
	enemy.position = pos
	content.add_child(enemy)
	enemy.world_died.connect(_on_enemy_died.bind({
		"kind": WorldEnemy.KIND_CULTIVATOR, "node_id": slot, "slot": slot,
		"region_id": rid,
	}))
	_enemies[slot] = enemy
	table[slot] = {"at": now + SecretWorldDB.RESPAWN_CULTIVATOR, "skills": skills}


func _roll_cultivator_skills(rid: String) -> Array:
	var pool := SecretWorldDB.get_cultivator_skill_pool(rid)
	pool.shuffle()
	var count := mini(int(SecretWorldDB.get_cultivator(rid).get("skill_count", 4)), pool.size())
	return pool.slice(0, count)


## 野外修士出生时抽携带法宝：池子按所在区域的境界取（练气 3 / 筑基 6 / 结丹 9 / 元婴 10）。
## ⚠ 必须走 get_cultivator(rid)：写死 CULTIVATOR 会让四个区一律只掉练气那 3 件，
##   后三档追加的 7 件配置里登记了却永远掉不出来（2026-11-07 统计发现并接线）。
func _roll_cultivator_treasure(rid: String) -> Dictionary:
	var cfg := SecretWorldDB.get_cultivator(rid)
	var pool: Array = cfg.get("treasure_pool", [])
	if pool.is_empty():
		return {}
	var chance := clampf(float(cfg.get("treasure_carry_chance", 0.0)), 0.0, 1.0)
	if randf() >= chance:
		return {}
	var tid := String(pool[randi() % pool.size()])
	var tpl := ItemDB.get_treasure_template(tid)
	if tpl.is_empty():
		return {}
	return CharacterData.make_treasure_instance(tpl)


# ===================== 大陆 BGM =====================

func _start_continent_bgm() -> void:
	if _bgm != null:
		return
	_bgm = BgmPlayer.new()
	_bgm.name = "ContinentBgm"
	add_child(_bgm)
	_bgm.play_loop(BGM_CONTINENT, BgmPlayer.AMBIENT_VOLUME_DB - 1.0, 2.0)


# ===================== 击杀 / 掉落 =====================

func _on_enemy_died(enemy: WorldEnemy, info: Dictionary) -> void:
	var nid := String(info.get("node_id", ""))
	if nid != "":
		_enemies.erase(nid)
	var pos: Vector2 = enemy.global_position
	var now := _now()
	var rid := String(info.get("region_id", region_id))

	match String(info.get("kind", "")):
		WorldEnemy.KIND_BEAST:
			Tutorial.note("world_enemy_kill")
			_nodes_table()[nid] = {"at": now + SecretWorldDB.RESPAWN_BEAST}
			_drop_beast_loot(pos, String(info.get("beast", "")))
			_grant_cultivation(SecretWorldDB.kill_exp(rid, true))
		WorldEnemy.KIND_CULTIVATOR:
			_cultivators_table()[String(info.get("slot", nid))] = {
				"at": now + SecretWorldDB.RESPAWN_CULTIVATOR,
			}
			_drop_cultivator_loot(pos, rid)
			# 携带法宝：死亡必掉（不再按概率判定）
			# 兜底：旧场次 / 本次修改前已经刷出的野修没有 carried_treasure，
			# 在 100% 携带规则下死亡时补抽一件，保证「必掉」不会因旧实例失效。
			var carried := enemy.carried_treasure
			var cultivator_cfg := SecretWorldDB.get_cultivator(rid)
			var carry_chance := clampf(float(cultivator_cfg.get("treasure_carry_chance", 0.0)), 0.0, 1.0)
			if carried.is_empty() and carry_chance >= 1.0:
				carried = _roll_cultivator_treasure(rid)
			if not carried.is_empty():
				_spawn_drop_item(carried,
					pos + Vector2(randf_range(-26.0, 26.0), randf_range(-16.0, 16.0)))
			_grant_cultivation(SecretWorldDB.kill_exp(rid, false))
		WorldEnemy.KIND_CORE:
			var core_cfg := SecretWorldDB.get_core_boss(rid)
			if core_cfg.is_empty():
				core_cfg = SecretWorldDB.CORE_BOSS
			_core_kill_table()[rid] = true
			# ⚠ 带 region_id：四个区的核心首领共用这一个埋点，裸名会让「练气区核心」这条
			#   任务被别的区勾掉（quest_db.q_lianqi_core 认全等）。
			#   教学侧按基础名匹配（tutorial_runner 的 `want` 无参时只比 base），不受影响。
			Tutorial.note("world_core_kill:" + rid)
			_grant_core_reward(core_cfg)
			_drop_core_equipment(core_cfg, pos)
			var core_exp := _grant_cultivation(SecretWorldDB.EXP_CORE)
			# 首杀是永久进度，立刻存档：哪怕之后死亡回滚，也不会把「已击杀」退回去
			SaveManager.auto_save()
			var exp_text := "　修为 +%d" % core_exp if core_exp > 0 else ""
			_show_announcement("击败核心首领·%s　%s%s" % [
				String(core_cfg.get("name", "核心首领")), _core_reward_text(core_cfg), exp_text],
				UIKit.C_GREAT, 3.5)


## 击杀给修为；本阶段修为已满时不增加、不飘字。返回实际获得量
func _grant_cultivation(amount: int) -> int:
	var gained := CharacterData.add_realm_exp(amount)
	if gained <= 0:
		return 0
	if player != null and is_instance_valid(player) and player.has_method("_show_float_text"):
		player._show_float_text("修为 +%d" % gained, UIKit.C_HUD_MANA)
	_update_hud()
	return gained


func _drop_beast_loot(pos: Vector2, beast_id: String) -> void:
	var beast := SecretWorldDB.get_beast(beast_id)
	var hide_id := String(beast.get("hide_id", ""))
	if hide_id == "":
		return
	var count := randi_range(int(beast.get("hide_min", 1)), int(beast.get("hide_max", 3)))
	_spawn_drop(hide_id, count, pos + Vector2(randf_range(-26.0, 26.0), randf_range(-16.0, 16.0)))


func _drop_cultivator_loot(pos: Vector2, rid: String) -> void:
	var herbs := SecretWorldDB.get_herb_ids(rid)
	herbs.shuffle()
	for i in mini(2, herbs.size()):
		_spawn_drop(
			String(herbs[i]),
			randi_range(1, 2),
			pos + Vector2(randf_range(-30.0, 30.0), randf_range(-20.0, 20.0))
		)
	var hides := SecretWorldDB.get_hide_ids(rid)
	if not hides.is_empty():
		_spawn_drop(
			String(hides[randi() % hides.size()]),
			randi_range(1, 3),
			pos + Vector2(randf_range(-30.0, 30.0), randf_range(-20.0, 20.0))
		)


func _spawn_drop(material_id: String, count: int, pos: Vector2) -> void:
	var def := ItemDB.get_material(material_id)
	_spawn_drop_item({
		"id": material_id,
		"name": String(def.get("name", material_id)),
		"type": "material",
		"count": count,
		"icon": String(def.get("icon", "")),
		"desc": String(def.get("desc", "")),
	}, pos)


func _spawn_drop_item(item: Dictionary, pos: Vector2) -> void:
	var pickup := PICKUP_SCENE.instantiate() as Area2D
	# ⚠ item 必须在入树前赋值：ItemPickup._ready 会照着它建光柱 / 名字
	pickup.item = item.duplicate(true)
	# 苍澜大陆的拾取先进局内背包；死亡清空、撤离才带回
	pickup.pickup_handler = _collect_run_item
	pickup.position = pos
	content.add_child(pickup)
	_drops.append(pickup)
	pickup.picked_up.connect(_on_drop_picked)


func _on_drop_picked(pickup: Area2D) -> void:
	_drops.erase(pickup)
	# 新手指引：大世界第一次捡东西（草药 / 战利品都算）
	Tutorial.note("world_pickup")
	var item: Dictionary = pickup.get("item")
	if item is Dictionary:
		_show_announcement(
			"拾取 %s ×%d" % [String(item.get("name", "")), int(item.get("count", 1))],
			UIKit.C_OK, 1.2
		)


## 玩家正站在其拾取范围内的最近掉落物（没有则 null）
## 自动拾取：站在哪件掉落物范围内就捡哪件（跳过刚丢下、还在宽限期的那件）
func _update_auto_pickup(delta: float) -> void:
	if _dead or _leaving or player == null or not is_instance_valid(player):
		return
	if _drops.is_empty():
		return
	_auto_pick_left -= delta
	if _auto_pick_left > 0.0:
		return
	_auto_pick_left = AUTO_PICKUP_INTERVAL
	for raw in _drops:
		var p := raw as Area2D
		if not is_instance_valid(p) or not p.has_method("has_player_inside"):
			continue
		if not bool(p.call("has_player_inside")):
			continue
		if not bool(p.call("auto_pickable")):
			continue
		# 捡一件就收手：让光柱 / 飘字一件件播，不要同一帧糊成一片
		if bool(p.call("try_pickup")):
			return


func _nearest_drop() -> Area2D:
	var nearest: Area2D = null
	var best := 99999.0
	for raw in _drops:
		var p := raw as Area2D
		if not is_instance_valid(p) or not p.has_method("has_player_inside"):
			continue
		if not bool(p.call("has_player_inside")):
			continue
		var d: float = player.global_position.distance_to(p.global_position)
		if d < best:
			best = d
			nearest = p
	return nearest


## 按 F 捡脚边最近的一件；返回是否真的拾到了（拾不到就不拦后面的地块交互）
func _try_pickup_nearest_drop() -> bool:
	var nearest := _nearest_drop()
	if nearest == null:
		return false
	return bool(nearest.call("try_pickup"))


# ===================== 核心首领奖励（永久） =====================

func _grant_core_reward(core_cfg: Dictionary) -> void:
	var rewards: Dictionary = core_cfg.get("reward", {})
	if rewards.is_empty():
		rewards = region.get("core_reward", {})
	for mid in rewards.keys():
		CharacterData.grant_material_guaranteed(String(mid), int(rewards[mid]))


## 核心首领的装备掉落（练气区藤甲 / 云隐谷苍角甲）
## 走普通地面掉落 → 局内背包 → 撤离带回，和普通战利品同一套规则。
func _drop_core_equipment(core_cfg: Dictionary, pos: Vector2) -> void:
	var ids: Array = core_cfg.get("equipment_drops", [])
	for i in ids.size():
		var tpl_id := String(ids[i])
		var tpl := ItemDB.get_equipment_template(tpl_id)
		if tpl.is_empty():
			continue
		_spawn_drop_item(CharacterData.make_equipment_instance(tpl),
			pos + Vector2(-24.0 + 48.0 * float(i), 28.0))


## 进图自愈：核心已杀 + 仍是该区域境界 + 破境材料为 0 → 补发
## 防的是「首杀后立刻死亡，回滚把必得材料一起清掉」造成的永久死锁。
## 并集世界里两个区域的核都可能已杀，逐个核对。
func _ensure_core_reward() -> void:
	var changed := false
	for raw in get_open_regions():
		var r: Dictionary = raw
		var rid := String(r.get("region_id", ""))
		if not CharacterData.is_core_killed(rid):
			continue
		if CharacterData.current_realm != String(r.get("realm", "")):
			continue
		var core_cfg := SecretWorldDB.get_core_boss(rid)
		var rewards: Dictionary = core_cfg.get("reward", {})
		if rewards.is_empty():
			rewards = r.get("core_reward", {})
		for mid in rewards.keys():
			var need := int(rewards[mid])
			if CharacterData.count_material(String(mid)) < need:
				CharacterData.grant_material_guaranteed(String(mid), need)
				changed = true
	if changed:
		SaveManager.auto_save()


func _core_reward_text(core_cfg: Dictionary = {}) -> String:
	var rewards: Dictionary = core_cfg.get("reward", {})
	if rewards.is_empty():
		rewards = region.get("core_reward", {})
	var parts: Array = []
	for mid in rewards.keys():
		var def := ItemDB.get_material(String(mid))
		parts.append("%s ×%d" % [String(def.get("name", mid)), int(rewards[mid])])
	return "获得 " + "、".join(parts)


# ===================== 死亡 / 离开 =====================

func _capture_loot() -> Dictionary:
	return {
		"inventory": CharacterData.inventory.duplicate(true),
		"equipment": CharacterData.equipment_slots.duplicate(true),
		"treasure": CharacterData.treasure_slots.duplicate(true),
	}


## 死亡回滚：只回滚「背包 / 穿戴」，修炼进度与核心首领击杀进度保留
func _restore_loot() -> void:
	if _loot_snapshot.is_empty():
		return
	var inv = _loot_snapshot.get("inventory", [])
	var eq = _loot_snapshot.get("equipment", {})
	var tr = _loot_snapshot.get("treasure", {})
	if inv is Array:
		CharacterData.inventory = (inv as Array).duplicate(true)
	if eq is Dictionary:
		CharacterData.equipment_slots = (eq as Dictionary).duplicate(true)
	if tr is Dictionary:
		CharacterData.treasure_slots = (tr as Dictionary).duplicate(true)


func _on_player_died() -> void:
	if _dead or _leaving:
		return
	_dead = true
	_stop_absorb()
	if _bgm != null:
		_bgm.fade_out(1.2)
	_restore_loot()
	# 局内背包随死亡清空（用户 2026-10-23 定）；地面掉落也一起消失
	_run_items.clear()
	if _run_bag != null and is_instance_valid(_run_bag):
		_run_bag.close_bag()
	_refresh_run_bag()
	_clear_drops()
	# 核心奖励自愈必须在回滚之后：首杀材料是必得内容，不能被死亡吞掉
	_ensure_core_reward()
	# 石台剑同理 —— 设施已永久消失，回滚把剑吞掉就等于把彩蛋删了
	_ensure_reliquary_reward()
	SaveManager.auto_save()
	_show_death_overlay()
	await get_tree().create_timer(3.0).timeout
	_return_to_realm()


func _clear_drops() -> void:
	for raw in _drops:
		if is_instance_valid(raw):
			(raw as Node).queue_free()
	_drops.clear()


func _return_to_realm() -> void:
	if _leaving:
		return
	_leaving = true
	if _bgm != null:
		_bgm.fade_out(0.5)
	# 成功撤离：局内背包并入永久背包（死亡路径已在 _on_player_died 清空）
	_flush_run_items()
	# 退出副本：清空丹药 / 符箓冷却与玩家全部 buff / debuff
	BattleWheel.reset_battle_state()
	if player != null and is_instance_valid(player):
		player.reset_player()
	VirtualPad.set_context("realm")
	SaveManager.auto_save()
	GameState.reset_time_flow()
	BattleResolver.clear()
	get_tree().paused = false
	get_tree().change_scene_to_file(REALM_SCENE)


func _ask_leave() -> void:
	ConfirmDialog.ask(
		"离开苍澜大陆",
		"返回原初位面？局内背包中的战利品会全部带回。",
		"离开", "取消", _return_to_realm, false
	)


# ===================== 输入 =====================

func _unhandled_input(event: InputEvent) -> void:
	if _dead or _leaving:
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_F:
			_on_interact()
		KEY_B:
			_toggle_run_bag()
		KEY_ESCAPE:
			_show_announcement("需回到入口处的传送门才能返回原初位面", UIKit.C_WARN, 2.0)


func _on_interact() -> void:
	if _absorb != null:
		return
	# 脚边的掉落物优先（2026-11-02 用户报「站在农田上捡不起东西」）：
	# 灵田 REACH 92 比拾取范围还大，以前 F 永远先被地块吃掉，东西只能干看着。
	# 真的拾到手才算吃掉这次交互，背包放不下时仍然让地块接管。
	if _try_pickup_nearest_drop():
		return
	if _nearest != null and is_instance_valid(_nearest):
		if _nearest.kind == WorldResource.KIND_GOD_ALTAR:
			_on_god_altar(_nearest)
			return
		if _nearest.kind == WorldResource.KIND_PORTAL:
			_ask_leave()
			return
		if _nearest.kind == WorldResource.KIND_QI:
			_begin_absorb(_nearest)
			return
		if _nearest.kind == WorldResource.KIND_FARM:
			_on_farm_interact(_nearest as FarmPlot)
			return
		if _nearest.kind == WorldResource.KIND_GATE:
			_on_huashen_gate()
			return
		if _nearest.kind == WorldResource.KIND_ALTAR:
			_on_huashen_altar()
			return
		var result := _nearest.try_interact()
		var msg := String(result.get("message", ""))
		if msg != "":
			_show_announcement(msg, result.get("color", UIKit.C_TEXT), 1.4)
		if bool(result.get("ok", false)) and bool(result.get("remove", false)):
			# 新手指引 c8「出门采第一株药」：草药是 F 采集，不走掉落物的 _on_drop_picked
			# （那里只在「捡起」时报 world_pickup）—— 漏报会让这一步永远做不完。
			if _nearest.kind == WorldResource.KIND_HERB:
				Tutorial.note("world_pickup")
			_on_resource_gone(_nearest)
		return
	_try_pickup_nearest_drop()


## 森林灵田：一块地一块地打理，成熟的收成进局内背包（死了跟着丢）
func _on_farm_interact(plot: FarmPlot) -> void:
	if not plot.is_tilled():
		_show_announcement("这块还是荒地 —— 站上去施展「猛虎踏地」把它踏开", UIKit.C_WARN, 1.8)
		return
	if plot.is_empty():
		_open_seed_picker(plot)
		return
	if not plot.is_mature():
		_show_announcement("%s 还在长，还需 %s" % [plot.crop_name(), FarmPlot.grow_text(plot.remaining())], UIKit.C_WARN, 1.6)
		return
	var mid := plot.crop_id()
	if not _collect_material(mid, 2):
		_show_announcement("局内背包已满，收获不了", UIKit.C_DANGER, 1.6)
		return
	CharacterData.clear_plot(plot.state_index())
	GameState.play_ui("pickup")
	_show_announcement("收获 %s ×2（局内背包）" % ItemDB.get_material_name(mid), UIKit.C_OK, 1.6)


func _open_seed_picker(plot: FarmPlot) -> void:
	var panel := FarmSeedPanel.new()
	panel.plot_index = plot.state_index()
	panel.plot_number = plot.plot_index + 1
	# 只列这片区域自己长的草药（每区一块田，不串别区种子）
	panel.seeds = SecretWorldDB.get_herb_ids(plot.region_id)
	panel.on_plant = func(_key: int, sid: String) -> void: _plant_plot(plot, sid)
	add_child(panel)
	panel.open()


func _plant_plot(plot: FarmPlot, seed_id: String) -> void:
	CharacterData.plant_plot(plot.state_index(), seed_id, FarmPlot.GROW_SECONDS)
	_show_announcement("第 %d 号灵田种下 %s，%s后成熟" % [
		plot.plot_index + 1, ItemDB.get_material_name(seed_id),
		FarmPlot.grow_text(FarmPlot.GROW_SECONDS)
	], UIKit.C_OK, 1.8)


## 猛虎踏地：站在荒地上放这一招，就把脚下这块踏成田
## 判定用地块矩形（contains_point），不用「最近资源」—— 九块地紧挨着，
## 站中间时最近的不一定是脚下这块。
func _on_player_skill_used(skill_id: String) -> void:
	if skill_id == FarmPlot.SLASH_HARVEST_SKILL_ID:
		_harvest_mature_with_slash()
		return
	if skill_id != FarmPlot.TILL_SKILL_ID:
		return
	for raw in _resources.values():
		if not (raw is FarmPlot):
			continue
		var plot := raw as FarmPlot
		if plot.is_tilled() or not plot.contains_point(player.global_position):
			continue
		plot.till()
		GameState.play_ui("pickup")
		_show_announcement("猛虎踏地 —— 第 %d 块荒地开垦好了，按「F」播种" % [plot.plot_index + 1], UIKit.C_OK, 2.2)
		return


## 横斩批量收获（2026-10-24 用户定）：
## 站在任意一块成熟灵田旁释放横斩，就把场上所有成熟地块一次收完。
## 单块 F 收获仍然保留；局内背包放不下的地块不清空，避免作物凭空消失。
func _harvest_mature_with_slash() -> void:
	if player == null or not is_instance_valid(player):
		return
	var mature: Array[FarmPlot] = []
	var near_mature := false
	for raw in _resources.values():
		if not (raw is FarmPlot):
			continue
		var plot := raw as FarmPlot
		if not plot.is_tilled() or plot.is_empty() or not plot.is_mature():
			continue
		mature.append(plot)
		if plot.global_position.distance_to(player.global_position) <= FarmPlot.SLASH_HARVEST_RADIUS:
			near_mature = true
	if not near_mature or mature.is_empty():
		return

	var harvested := 0
	var failed := 0
	for plot in mature:
		var mid := plot.crop_id()
		if _collect_material(mid, 2):
			CharacterData.clear_plot(plot.state_index())
			harvested += 1
		else:
			failed += 1
	if harvested > 0:
		GameState.play_ui("pickup")
		_show_announcement("横斩 · 收获 %d 块成熟灵田（每块作物 ×2，已入局内背包）" % harvested,
			UIKit.C_OK, 2.0)
	if failed > 0:
		_show_announcement("局内背包已满：还有 %d 块成熟灵田未收获" % failed,
			UIKit.C_WARN, 2.0)


## 采集 / 吸收成功后：写重生时刻并移除场上实体
func _on_resource_gone(res: WorldResource) -> void:
	var nid := res.node_id
	var now := _now()
	if res.kind == WorldResource.KIND_HERB:
		_nodes_table()[nid] = {"at": now + SecretWorldDB.RESPAWN_HERB}
	elif res.kind == WorldResource.KIND_QI:
		_nodes_table()[nid] = {"at": now + SecretWorldDB.RESPAWN_QI}
	elif res.kind == WorldResource.KIND_RELIQUARY:
		# ⚠ 键用 "taken" 不用 "at"：_node_due() 只认 "at"，写 "at" 会被当成刷新计时，
		#   到点剑又长回来；写别的键则 _node_due 根本不读它，生成侧靠 has() 拦。
		_nodes_table()[nid] = {"taken": now}
		# 立刻落盘：设施消失是永久事实，不存就等着下次进图复活
		SaveManager.auto_save()
	_resources.erase(nid)
	res.queue_free()


# ===================== 灵气吸收（5 秒引导）=====================

## 按 F 开始读条；秒数走完才真正加成，中途离开范围就作废
func _begin_absorb(res: WorldResource) -> void:
	var check := res.check_absorbable()
	if not bool(check.get("ok", false)):
		var msg := String(check.get("message", ""))
		if msg != "":
			_show_announcement(msg, check.get("color", UIKit.C_WARN), 1.6)
		return
	_absorb = res
	_absorb_left = WorldResource.QI_ABSORB_TIME
	_absorb_bar.value = 0.0
	_absorb_label.text = _absorb_text()
	_absorb_box.visible = true


func _update_absorb(delta: float) -> void:
	if _absorb == null:
		return
	if not is_instance_valid(_absorb) or _absorb.kind != WorldResource.KIND_QI:
		_stop_absorb()
		return
	if player.global_position.distance_to(_absorb.global_position) > _absorb.reach_distance():
		_stop_absorb()
		_show_announcement("离开灵气范围，吸收中断", UIKit.C_WARN, 1.4)
		return
	_absorb_left -= delta
	_absorb_bar.value = clampf(1.0 - _absorb_left / WorldResource.QI_ABSORB_TIME, 0.0, 1.0) * 100.0
	_absorb_label.text = _absorb_text()
	if _absorb_left > 0.0:
		return

	var res := _absorb
	_stop_absorb()
	var result := res.try_interact()
	var msg := String(result.get("message", ""))
	if msg != "":
		_show_announcement(msg, result.get("color", UIKit.C_TEXT), 1.6)
	if bool(result.get("ok", false)) and bool(result.get("remove", false)):
		_on_resource_gone(res)


func _absorb_text() -> String:
	return "吸收灵气　%.1f 秒" % maxf(_absorb_left, 0.0)


func _stop_absorb() -> void:
	_absorb = null
	_absorb_left = 0.0
	if _absorb_box != null:
		_absorb_box.visible = false


# ===================== 局内背包 =====================

func _build_run_bag() -> void:
	_run_bag = RunBagPanel.new()
	_run_bag.items = _run_items
	_run_bag.capacity = RUN_BAG_CAPACITY
	_run_bag.drop_handler = _drop_run_item
	add_child(_run_bag)


func _toggle_run_bag() -> void:
	if _dead or _leaving or _run_bag == null:
		return
	_run_bag.toggle_bag()


## 局内拾取统一入口：先塞局内背包（不写永久背包）
## 返回 false = 已满（地面掉落物保留，玩家可清包后再捡）
func _collect_run_item(item: Dictionary) -> bool:
	var iid := String(item.get("id", ""))
	var cnt := maxi(1, int(item.get("count", 1)))
	if iid == "":
		return false
	# 装备 / 法宝是独立实体，不能按 id 堆叠（否则两件凝水佩会变成 count=2 的一格）
	var is_equipment := String(item.get("type", "")) == CharacterData.ITEM_EQUIPMENT
	var stack := -1 if is_equipment else _find_run_stack(iid)
	if stack < 0 and _run_items.size() >= RUN_BAG_CAPACITY:
		_show_announcement("局内背包已满（%d 格），按 B 打开后可拖出丢弃" % RUN_BAG_CAPACITY, UIKit.C_WARN, 1.8)
		return false
	if stack >= 0:
		_run_items[stack]["count"] = int(_run_items[stack].get("count", 1)) + cnt
	else:
		var copy := item.duplicate(true)
		copy["count"] = 1 if is_equipment else cnt
		_run_items.append(copy)
	CharacterData.mark_codex_from_item(item)
	_refresh_run_bag()
	return true


func _collect_material(material_id: String, amount: int) -> bool:
	var def := ItemDB.get_material(material_id)
	return _collect_run_item({
		"id": material_id,
		"name": String(def.get("name", material_id)),
		"type": "material",
		"count": amount,
		"icon": String(def.get("icon", "")),
		"desc": String(def.get("desc", "")),
	})


func _find_run_stack(item_id: String) -> int:
	for i in _run_items.size():
		if String(_run_items[i].get("id", "")) == item_id:
			return i
	return -1


func _refresh_run_bag() -> void:
	if _run_bag != null and is_instance_valid(_run_bag):
		_run_bag.refresh()
	if _bag_label != null:
		_bag_label.text = "局内背包 %d / %d" % [_run_items.size(), RUN_BAG_CAPACITY]


## 面板把物品拖出面板外松手 → 在玩家脚下生成地面掉落物（可再捡回）
func _drop_run_item(item: Dictionary) -> void:
	_spawn_drop_item(item, player.global_position + Vector2(randf_range(-20.0, 20.0), 26.0))
	# ⚠ 自己丢出去的东西不能立刻被自动拾取吸回来，否则「拖出丢弃」等于丢不掉。
	#   给 3 秒宽限；F 键仍可手动捡回来。
	var dropped: Area2D = _drops[-1] if not _drops.is_empty() else null
	if dropped != null:
		dropped.set("auto_pick_block_until", Time.get_ticks_msec() / 1000.0 + 3.0)
	_show_announcement("丢弃 %s ×%d" % [String(item.get("name", "")), int(item.get("count", 1))],
		UIKit.C_TEXT_DIM, 1.2)


## 成功撤离：局内背包并入永久背包
## 容量满时按「必得材料」口径强制入包 —— 整趟副本的收获不能静默消失
func _flush_run_items() -> void:
	for raw in _run_items:
		var item: Dictionary = raw
		if CharacterData.add_item(item):
			continue
		if String(item.get("type", "")) == CharacterData.ITEM_EQUIPMENT:
			# 装备 / 法宝不能转成材料；背包满也强制占一格，避免整趟副本的收获消失
			CharacterData.inventory.append(item.duplicate(true))
			push_warning("背包已满，装备「%s」强制入包" % String(item.get("name", "")))
		else:
			CharacterData.grant_material_guaranteed(String(item.get("id", "")), int(item.get("count", 1)))
	_run_items.clear()
	_refresh_run_bag()


# ===================== 每帧 =====================

func _process(delta: float) -> void:
	if region.is_empty() or _leaving:
		return
	if _dead:
		return

	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn_timer = 1.0
		_spawn_due_content()

	_update_interaction()
	_update_absorb(delta)
	_update_auto_pickup(delta)
	_sync_terrain_lod()
	_region_check_timer -= delta
	if _region_check_timer <= 0.0:
		_region_check_timer = 0.35
		var here := SecretWorldDB.region_at(player.global_position)
		var rid := String(here.get("region_id", ""))
		if rid != "" and rid != _current_region_id:
			_current_region_id = rid
			var first := not _seen_region_ids.has(rid)
			_seen_region_ids[rid] = true
			_refresh_region_header(first)
	_update_hud()


func _update_interaction() -> void:
	_nearest = null
	var best := 99999.0
	for raw in _resources.values():
		var res := raw as WorldResource
		if res == null or not is_instance_valid(res):
			continue
		var d: float = player.global_position.distance_to(res.global_position)
		if d <= res.reach_distance() and d < best:
			best = d
			_nearest = res

	# 灵田九块地紧挨着：把「当前打理的这块」描上金边，免得站中间分不清
	for raw in _resources.values():
		if raw is FarmPlot:
			(raw as FarmPlot).set_highlight(raw == _nearest)

	if _prompt_bg == null:
		return
	if _absorb != null:
		_prompt.text = "吸收灵气中…　离开范围会中断"
		_prompt_bg.visible = true
		return
	if _nearest != null and _nearest_drop() == null:
		_prompt.text = _nearest.prompt_text()
		_prompt_bg.visible = true
	else:
		# 脚边有掉落物时按 F 是先捡东西（见 _on_interact），地块提示让位给
		# 物品自己那句「F 拾取」，否则提示和行为对不上
		_prompt_bg.visible = false


# ===================== 刷新时刻工具 =====================

func _now() -> float:
	return Time.get_unix_time_from_system()


func _region_rect() -> Rect2:
	var r: Rect2 = region.get("rect", Rect2())
	return r


func _nodes_table() -> Dictionary:
	var t = CharacterData.secret_world.get("nodes", {})
	if not (t is Dictionary):
		CharacterData.secret_world["nodes"] = {}
		return CharacterData.secret_world["nodes"]
	return t


func _cultivators_table() -> Dictionary:
	var t = CharacterData.secret_world.get("cultivators", {})
	if not (t is Dictionary):
		CharacterData.secret_world["cultivators"] = {}
		return CharacterData.secret_world["cultivators"]
	return t


func _core_kill_table() -> Dictionary:
	var t = CharacterData.secret_world.get("core_kills", {})
	if not (t is Dictionary):
		CharacterData.secret_world["core_kills"] = {}
		return CharacterData.secret_world["core_kills"]
	return t


## 资源节点是否到点：无记录 = 立即生成；有记录且未到点 = 继续等
func _node_due(node_id: String, now: float) -> bool:
	var table := _nodes_table()
	var rec = table.get(node_id, null)
	if rec is Dictionary:
		if float((rec as Dictionary).get("at", 0.0)) > now:
			return false
		table.erase(node_id)
	return true


# ===================== HUD =====================

func _build_hud() -> void:
	var cr := SecretWorldDB.get_region(_current_region_id)
	if cr.is_empty():
		cr = region
	_title = UIKit.label("苍澜大陆 · %s · %s" % [String(cr.get("name", "")), String(cr.get("realm", ""))],
		UIKit.F_TITLE, UIKit.C_ACCENT)
	_title.size = Vector2(600.0, 34.0)
	_title.position = Vector2((VIEW_W - 600.0) * 0.5, 8.0)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_title)

	_core_status = UIKit.label("", UIKit.F_SMALL, UIKit.C_TEXT_DIM)
	_core_status.size = Vector2(900.0, 20.0)
	_core_status.position = Vector2((VIEW_W - 900.0) * 0.5, 42.0)
	_core_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_core_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_core_status)

	# 死亡代价（2026-11-13 用户定）：屏幕正上方右侧、红字括号，常驻提醒
	# 「局内背包（B）里的东西死了全掉」。与核心状态同一行，右对齐到右边距；
	# ⚠ y 必须 ≥ 40：设置按钮占 6~38，传送门方向占 y=70，夹在中间才不打架。
	_death_warn = UIKit.label("（死亡掉落局内背包（B）的所有道具材料）",
		UIKit.F_SMALL, UIKit.C_DANGER)
	_death_warn.size = Vector2(360.0, 20.0)
	_death_warn.position = Vector2(VIEW_W - 360.0 - 16.0, 42.0)
	_death_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_death_warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_death_warn)

	_build_cult_box()
	_build_status_box()
	_build_compass()
	_build_prompt()
	_build_absorb_bar()
	_build_announce()
	_build_treasure_bar()
	_build_skill_bar()
	_build_death_overlay()


## 大世界状态栏：放在修为框下方。没有状态时整块隐藏，不占视觉。
func _build_status_box() -> void:
	_status_box = VBoxContainer.new()
	_status_box.position = Vector2(16.0, 100.0)
	_status_box.size = Vector2(300.0, 240.0)
	_status_box.add_theme_constant_override("separation", 3)
	_status_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_box.visible = false
	hud.add_child(_status_box)


func _build_cult_box() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09, 0.62)
	bg.position = Vector2(16.0, 14.0)
	bg.size = Vector2(238.0, 78.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bg)

	_cult_label = UIKit.label("", UIKit.F_SMALL, UIKit.C_TEXT)
	_cult_label.position = Vector2(26.0, 20.0)
	_cult_label.size = Vector2(218.0, 18.0)
	_cult_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_cult_label)

	_cult_bar = ProgressBar.new()
	_cult_bar.position = Vector2(26.0, 42.0)
	_cult_bar.size = Vector2(218.0, 14.0)
	_cult_bar.min_value = 0.0
	_cult_bar.max_value = 100.0
	_cult_bar.show_percentage = false
	_cult_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color(0.10, 0.10, 0.14, 0.9)
	bgs.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UIKit.C_HUD_MANA
	fill.set_corner_radius_all(3)
	_cult_bar.add_theme_stylebox_override("background", bgs)
	_cult_bar.add_theme_stylebox_override("fill", fill)
	hud.add_child(_cult_bar)

	_bag_label = UIKit.label("", UIKit.F_BADGE, UIKit.C_TEXT_DIM)
	_bag_label.position = Vector2(26.0, 62.0)
	_bag_label.size = Vector2(218.0, 16.0)
	_bag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_bag_label)

	# 局内背包按钮：触屏也能开（PC 也可按 B）
	var bag_btn := UIKit.button("局内背包（B）", Vector2(238.0, 28.0))
	bag_btn.position = Vector2(16.0, 96.0)
	bag_btn.pressed.connect(_toggle_run_bag)
	hud.add_child(bag_btn)


func _build_compass() -> void:
	# 右上角只保留「入口」方向（用户 2026-10-23 定）
	# ⚠ 必须避开设置按钮（右上角 1190,6 起 84×32）与核心状态行（y42~62）：
	#   放在 y=70，右对齐到 x=1264
	_compass_portal = UIKit.label("", UIKit.F_SMALL, UIKit.C_ASCEND)
	_compass_portal.size = Vector2(300.0, 20.0)
	_compass_portal.position = Vector2(VIEW_W - 316.0, 70.0)
	_compass_portal.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_compass_portal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_compass_portal)


func _build_prompt() -> void:
	_prompt_bg = ColorRect.new()
	_prompt_bg.color = Color(0.05, 0.06, 0.09, 0.76)
	_prompt_bg.position = Vector2((VIEW_W - 380.0) * 0.5, VIEW_H - 112.0)
	_prompt_bg.size = Vector2(380.0, 32.0)
	_prompt_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_bg.visible = false
	hud.add_child(_prompt_bg)

	_prompt = UIKit.label("", UIKit.F_SUBTITLE, UIKit.C_ACCENT)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_bg.add_child(_prompt)


## 吸收灵气进度条：贴在交互提示上方
func _build_absorb_bar() -> void:
	_absorb_box = Control.new()
	_absorb_box.position = Vector2((VIEW_W - 380.0) * 0.5, VIEW_H - 160.0)
	_absorb_box.size = Vector2(380.0, 44.0)
	_absorb_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_absorb_box.visible = false
	hud.add_child(_absorb_box)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09, 0.80)
	bg.size = _absorb_box.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_absorb_box.add_child(bg)

	_absorb_label = UIKit.label("", UIKit.F_SMALL, UIKit.C_HUD_MANA)
	_absorb_label.position = Vector2(10.0, 4.0)
	_absorb_label.size = Vector2(360.0, 16.0)
	_absorb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_absorb_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_absorb_box.add_child(_absorb_label)

	_absorb_bar = ProgressBar.new()
	_absorb_bar.position = Vector2(10.0, 24.0)
	_absorb_bar.size = Vector2(360.0, 13.0)
	_absorb_bar.min_value = 0.0
	_absorb_bar.max_value = 100.0
	_absorb_bar.show_percentage = false
	_absorb_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color(0.10, 0.10, 0.14, 0.9)
	bgs.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UIKit.C_HUD_MANA
	fill.set_corner_radius_all(3)
	_absorb_bar.add_theme_stylebox_override("background", bgs)
	_absorb_bar.add_theme_stylebox_override("fill", fill)
	_absorb_box.add_child(_absorb_bar)


func _build_announce() -> void:
	_announce = UIKit.label("", UIKit.F_SUBTITLE, UIKit.C_ACCENT)
	_announce.size = Vector2(940.0, 30.0)
	_announce.position = Vector2((VIEW_W - 940.0) * 0.5, 150.0)
	_announce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_announce.visible = false
	hud.add_child(_announce)


func _show_announcement(text: String, color: Color, hold: float) -> void:
	if _announce == null:
		return
	_announce.text = text
	_announce.add_theme_color_override("font_color", color)
	_announce.visible = true
	_announce.modulate.a = 1.0
	if _announce_tween != null and _announce_tween.is_valid():
		_announce_tween.kill()
	_announce_tween = _announce.create_tween()
	_announce_tween.tween_interval(hold)
	_announce_tween.tween_property(_announce, "modulate:a", 0.0, 0.5)
	_announce_tween.tween_callback(func() -> void:
		if is_instance_valid(_announce):
			_announce.visible = false
	)


func _build_death_overlay() -> void:
	_death_overlay = Control.new()
	_death_overlay.size = Vector2(VIEW_W, VIEW_H)
	_death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.visible = false
	hud.add_child(_death_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.0, 0.72)
	dim.size = Vector2(VIEW_W, VIEW_H)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.add_child(dim)

	var main := UIKit.label("你已陨落", 34, UIKit.C_DANGER)
	main.size = Vector2(VIEW_W, 48.0)
	main.position = Vector2(0.0, VIEW_H * 0.5 - 56.0)
	main.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.add_child(main)

	var sub := UIKit.label("本次副本获得的战利品已散失　正在返回原初位面…", UIKit.F_BODY, UIKit.C_TEXT_DIM)
	sub.size = Vector2(VIEW_W, 26.0)
	sub.position = Vector2(0.0, VIEW_H * 0.5 + 4.0)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.add_child(sub)


func _show_death_overlay() -> void:
	if _death_overlay != null:
		_death_overlay.visible = true
	if _prompt_bg != null:
		_prompt_bg.visible = false


func _update_hud() -> void:
	if _cult_label == null:
		return
	_cult_label.text = "修为　%d / %d　%s%s" % [
		CharacterData.realm_exp, CharacterData.get_stage_exp_required(),
		CharacterData.current_realm,
		"" if CharacterData.is_huashen() else " · " + CharacterData.get_realm_stage_name(),
	]
	_cult_bar.value = CharacterData.get_stage_exp_ratio() * 100.0
	if CharacterData.is_stage_full():
		_cult_bar.modulate = Color(1.0, 0.9, 0.55, 1.0)
	else:
		_cult_bar.modulate = Color.WHITE
	_bag_label.text = "局内背包 %d / %d" % [_run_items.size(), RUN_BAG_CAPACITY]

	# 空首领的区域不主动提示（内容定稿权属于用户）；有核心的区域按当前区域显示
	var cur := SecretWorldDB.get_region(_current_region_id)
	var cur_core := SecretWorldDB.get_core_boss(_current_region_id)
	if String(cur.get("core_boss_id", "")) == "" or cur_core.is_empty():
		_core_status.text = ""
	elif CharacterData.is_core_killed(_current_region_id):
		_core_status.text = "核心首领：%s · 已击杀（永久） · 区域面板可重战" % \
			String(cur_core.get("name", "核心首领"))
		_core_status.add_theme_color_override("font_color", UIKit.C_OK)
	else:
		var where := String(cur.get("core_where", "区域中央"))
		# 核心首领在区域正中，离入口很远；状态行必须给方向和实时距离，否则玩家找不到
		var guide := ""
		var core_node = _enemies.get(String(cur_core.get("node_id", "")))
		if core_node != null and is_instance_valid(core_node):
			var core_pos: Vector2 = (core_node as Node2D).global_position
			guide = "　%s %d 步" % [
				_dir_arrow(player.global_position, core_pos),
				int(round(player.global_position.distance_to(core_pos) / 10.0))]
		_core_status.text = "核心首领：%s · 未击杀（%s）%s" % [
			String(cur_core.get("name", "核心首领")), where, guide]
		_core_status.add_theme_color_override("font_color", UIKit.C_ACCENT)

	if _compass_portal != null:
		var nearest: WorldResource = null
		var nearest_d := INF
		for p in _portals:
			if not is_instance_valid(p):
				continue
			var d := player.global_position.distance_to(p.global_position)
			if d < nearest_d:
				nearest_d = d
				nearest = p
		_portal = nearest
		if nearest != null:
			_compass_portal.text = "传送门　%s %d" % [
				_dir_arrow(player.global_position, nearest.global_position),
				int(round(nearest_d))]
		else:
			_compass_portal.text = ""

	_update_skill_bar()
	_update_treasure_bar()
	_update_status_bar()


## 大世界状态栏：debuff 全列、buff 全列，按剩余时间倒计时。
## 行对象复用，只有状态集合变化时才增删标签；文本每帧更新。
func _update_status_bar() -> void:
	if _status_box == null or not is_instance_valid(_status_box):
		return
	if player == null or not is_instance_valid(player):
		return
	var seen: Dictionary = {}
	var entries: Array = []
	for raw in player.debuffs.keys():
		var id := String(raw)
		var left := float(player.debuffs[id])
		if left <= 0.0:
			continue
		entries.append({
			"id": id,
			"text": "%s　%.1fs" % [DebuffDB.display_name(id), left],
			"color": DebuffDB.color(id),
		})
		seen[id] = true
	for raw in player.buffs.keys():
		var id := String(raw)
		var e: Dictionary = player.buffs[id]
		if BuffDB.is_count_based(id):
			var count := int(e.get("count", 0))
			if count <= 0:
				continue
			entries.append({
				"id": id,
				"text": "%s　×%d" % [BuffDB.display_name(id), count],
				"color": BuffDB.color(id),
			})
		else:
			var left := float(e.get("left", 0.0))
			if left <= 0.0:
				continue
			entries.append({
				"id": id,
				"text": "%s　%.1fs" % [BuffDB.display_name(id), left],
				"color": BuffDB.color(id),
			})
		seen[id] = true
	_status_box.visible = not entries.is_empty()
	for raw in _status_rows.keys():
		var old_id := String(raw)
		if seen.has(old_id):
			continue
		var old_label = _status_rows[old_id]
		if is_instance_valid(old_label):
			old_label.queue_free()
		_status_rows.erase(old_id)
	for raw in entries:
		var entry: Dictionary = raw
		var id := String(entry.get("id", ""))
		var color: Color = entry.get("color", UIKit.C_TEXT)
		var text := String(entry.get("text", ""))
		var lbl: Label = _status_rows.get(id, null)
		if lbl == null or not is_instance_valid(lbl):
			lbl = UIKit.readable_label(text, 15, color)
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_status_box.add_child(lbl)
			_status_rows[id] = lbl
		else:
			lbl.text = text
			lbl.add_theme_color_override("font_color", color)


## 跨区时刷新标题与一次性提示（云隐谷南口 / 练气区入口）
func _refresh_region_header(announce: bool) -> void:
	var cr := SecretWorldDB.get_region(_current_region_id)
	if cr.is_empty():
		return
	var rid := String(cr.get("region_id", ""))
	_title.text = "苍澜大陆 · %s · %s" % [String(cr.get("name", "")), String(cr.get("realm", ""))]
	if not announce:
		return
	var base := ""
	match rid:
		SecretWorldDB.REGION_ZHUJI:
			base = "云隐谷 · 筑基区域　——　右上角传送门可撤离，南口可回青岚野"
		SecretWorldDB.REGION_JIEDAN:
			base = "赤金丹霞 · 结丹区域　——　左上角传送门可撤离，东沿可回云隐谷"
		SecretWorldDB.REGION_YUANYING:
			base = "幽冥灵墟 · 元婴区域　——　西南传送门可撤离，北接丹霞、东邻青岚；中央九天门可探"
		SecretWorldDB.REGION_HUASHEN:
			base = "九天之上 · 化神区域　——　中央化神坛可突破化神，东侧传送门可撤离"
		_:
			base = "青岚野 · 练气区域　——　采集药材、猎杀灵兽"
	# 核心首领在区域正中，入口看不到；进区公告必须带「在哪」或「已击杀」
	var core := SecretWorldDB.get_core_boss(rid)
	if not core.is_empty():
		if CharacterData.is_core_killed(rid):
			base += "；核心首领已击杀，区域面板可重战"
		else:
			var core_where := String(cr.get("core_where", "区域中央"))
			var arrow := ""
			var core_node = _enemies.get(String(core.get("node_id", "")))
			if core_node != null and is_instance_valid(core_node):
				arrow = " " + _dir_arrow(player.global_position,
					(core_node as Node2D).global_position)
			base += "；%s有核心首领「%s」%s" % [
				core_where, String(core.get("name", "核心首领")), arrow]
	_show_announcement(base, UIKit.C_ACCENT, 3.4)


## 八方向箭头（镜头不跟随目标，靠这个给玩家方位感）
func _dir_arrow(from: Vector2, to: Vector2) -> String:
	var d := to - from
	if d.length() < 8.0:
		return "·"
	var arrows := ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"]
	var idx := int(round(d.angle() / (PI / 4.0)))
	return String(arrows[(idx + 8) % 8])


# ===================== HUD：功法 / 法宝栏 =====================

func _build_skill_bar() -> void:
	var n := SKILL_BAR_KEYS.size()
	var bar_w := float(n) * SKILL_SLOT_SIZE.x + float(n - 1) * SKILL_SLOT_GAP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(SKILL_SLOT_GAP))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.offset_left = (VIEW_W - bar_w) * 0.5
	row.offset_right = row.offset_left + bar_w
	row.offset_top = VIEW_H - SKILL_SLOT_SIZE.y - 4.0
	row.offset_bottom = VIEW_H - 4.0
	hud.add_child(row)

	for i in n:
		var sid := ""
		if i < CharacterData.active_skill_loadout.size():
			sid = String(CharacterData.active_skill_loadout[i])
		row.add_child(_make_skill_slot(i, sid))
		# 剑意就绪光环：剑意满层时绕「吃剑意」的招式旋转（与竞技场同一控件、同一判定）。
		# ⚠ 必须挂 row 下当 sibling：格子 clip_contents=true，48px 的环挂里面会被裁掉。
		# ⚠ 默认隐藏：空槽会被 _update_skill_bar 的 continue 跳过，永远等不到显隐判定。
		var aura := SkillReadyAura.new()
		aura.visible = false
		row.add_child(aura)
		_skill_slots[i]["aura"] = aura


func _make_skill_slot(index: int, sid: String) -> Control:
	var filled := sid != ""
	var box := PanelContainer.new()
	box.custom_minimum_size = SKILL_SLOT_SIZE
	box.clip_contents = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", UIKit.slot_style(filled))

	var icon := UIKit.icon_node(
		CharacterData.active_slot_display_icon(sid) if filled else "",
		CharacterData.active_slot_display_name(sid) if filled else "",
		"skill", SKILL_ICON_SIZE)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not filled:
		icon.modulate = Color(1.0, 1.0, 1.0, 0.22)
	box.add_child(icon)

	# 冷却遮罩要套一层内容区（理由见 combat_arena.gd 同名函数：PanelContainer 会重排子节点）
	var cover := Control.new()
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(cover)

	var mask := ColorRect.new()
	mask.color = UIKit.C_CD_MASK
	mask.visible = false
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(mask)

	var cd := UIKit.label("", UIKit.F_BADGE, Color(1.0, 1.0, 1.0, 1.0))
	cd.set_anchors_preset(Control.PRESET_CENTER)
	cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cd.visible = false
	cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(cd)

	var key := UIKit.label(String(SKILL_BAR_KEYS[index]), UIKit.F_BADGE,
		UIKit.C_ACCENT if filled else UIKit.C_DISABLE)
	key.set_anchors_preset(Control.PRESET_TOP_LEFT)
	key.offset_left = 3.0
	key.offset_top = 1.0
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(key)

	var count_label := UIKit.label("", UIKit.F_BADGE, Color.WHITE)
	count_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	count_label.offset_left = -24.0
	count_label.offset_top = -16.0
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.visible = CharacterData.is_talisman_slot(sid)
	box.add_child(count_label)

	_skill_slots.append({
		"box": box, "cover": cover, "mask": mask, "cd": cd, "count": count_label,
		"is_talisman": CharacterData.is_talisman_slot(sid), "sid": sid,
	})
	return box


func _update_skill_bar() -> void:
	if _skill_slots.is_empty() or not is_instance_valid(player):
		return
	for e in _skill_slots:
		var sid := String(e.get("sid", ""))
		var cover := e.get("cover") as Control
		var mask := e.get("mask") as ColorRect
		var cd := e.get("cd") as Label
		if sid == "" or cover == null or mask == null or cd == null:
			continue
		var count_label: Label = e.get("count")
		if bool(e.get("is_talisman", false)):
			if count_label != null:
				count_label.text = "×%d" % CharacterData.active_slot_talisman_count(sid)
			mask.visible = false
			cd.visible = false
			_update_ready_aura(e, 0.0)
			continue
		var left: float = player.skill_cooldown_left(sid)
		if left <= 0.0:
			mask.visible = false
			cd.visible = false
		else:
			var total := float(SkillDB.get_skill_cost(sid).get("cooldown", 0.0))
			var ratio := clampf(left / total, 0.0, 1.0) if total > 0.0 else 1.0
			var area := cover.size
			var h := area.y * ratio
			mask.position = Vector2(0.0, area.y - h)
			mask.size = Vector2(area.x, h)
			mask.visible = true
			cd.visible = true
			cd.text = "%.1f" % left
		_update_ready_aura(e, left)


## 剑意就绪光环：剑意满层 + 冷却转好 + 该招式吃剑意时绕格子旋转。
## 「吃剑意」走数据判定（intent_full_at / intent_count_scale），不写死技能 id ——
## 一剑开天与万剑归宗自动覆盖。⚠ 与 combat_arena._update_ready_aura 同一套口径，
## 改判定时两处一起改（大世界与竞技场的技能栏是两份实现）。
func _update_ready_aura(e: Dictionary, cooldown_left: float) -> void:
	var aura: Node2D = e.get("aura")
	if aura == null or not is_instance_valid(aura):
		return
	var box: Control = e.get("box")
	if box == null:
		return
	var show: bool = cooldown_left <= 0.0 and player.is_sword_intent_full()
	if show:
		var form: Dictionary = SkillDB.get_skill_form(String(e.get("sid", "")))
		var ics: Dictionary = form.get("intent_count_scale", {})
		show = int(form.get("intent_full_at", 0)) > 0 or not ics.is_empty()
	aura.visible = show
	if show:
		aura.global_position = box.global_position + box.size * 0.5


func _build_treasure_bar() -> void:
	var n := 3
	var bar_w := float(n) * TREASURE_SLOT_SIZE.x + float(n - 1) * TREASURE_SLOT_GAP
	var skill_n := SKILL_BAR_KEYS.size()
	var skill_w := float(skill_n) * SKILL_SLOT_SIZE.x + float(skill_n - 1) * SKILL_SLOT_GAP
	var skill_left := (VIEW_W - skill_w) * 0.5
	var left := skill_left - TREASURE_BAR_MARGIN - bar_w

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(TREASURE_SLOT_GAP))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.offset_left = left
	row.offset_right = left + bar_w
	row.offset_top = VIEW_H - TREASURE_SLOT_SIZE.y - 4.0
	row.offset_bottom = VIEW_H - 4.0
	hud.add_child(row)

	for i in n:
		var box := PanelContainer.new()
		box.custom_minimum_size = TREASURE_SLOT_SIZE
		box.clip_contents = true
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_stylebox_override("panel", UIKit.slot_style(false))
		box.tooltip_text = "法宝槽 %d：战斗中按 %d 召唤" % [i + 1, i + 1]
		row.add_child(box)

		var layer := Control.new()
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(layer)

		var icon_wrap := CenterContainer.new()
		icon_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(icon_wrap)

		var key := UIKit.label(str(i + 1), UIKit.F_BADGE, UIKit.C_ACCENT)
		key.position = Vector2(3.0, 0.0)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(key)

		var cd := UIKit.label("", UIKit.F_BADGE, Color(1.0, 1.0, 1.0, 1.0))
		cd.set_anchors_preset(Control.PRESET_FULL_RECT)
		cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cd.visible = false
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(cd)

		# 初值不能是 "": 空槽 id 也是 ""，会被「内容没变」判断跳过 → 永远不出「空」字
		_treasure_slots.append({"box": box, "icon_wrap": icon_wrap, "cd": cd, "last_id": "__init__"})


func _update_treasure_bar() -> void:
	if _treasure_slots.is_empty():
		return
	for i in _treasure_slots.size():
		var e: Dictionary = _treasure_slots[i]
		var item: Dictionary = CharacterData.get_equipped("treasure_%d" % (i + 1))
		var tid := String(item.get("id", ""))
		var wrap := e.get("icon_wrap") as Control

		if String(e.get("last_id", "")) != tid:
			e["last_id"] = tid
			UIKit.clear_children(wrap)
			if item.is_empty():
				wrap.add_child(UIKit.label("空", UIKit.F_SMALL, UIKit.C_DISABLE))
			else:
				wrap.add_child(UIKit.equip_icon(item, Vector2(26.0, 26.0)))

		var left_cd := 0.0
		if tid != "" and player != null and player.has_method("summon_cooldown_left"):
			left_cd = float(player.call("summon_cooldown_left", tid))
		var cd_label := e.get("cd") as Label
		cd_label.visible = left_cd > 0.05
		if left_cd > 0.05:
			cd_label.text = "%d" % int(ceilf(left_cd))
		wrap.modulate = Color(1.0, 1.0, 1.0, 0.35) if left_cd > 0.05 else Color.WHITE
		var box := e.get("box") as PanelContainer
		# 法宝槽也按品阶描边（与角色面板 / 背包口径一致）
		box.add_theme_stylebox_override("panel", UIKit.slot_style(
			not item.is_empty(),
			UIKit.grade_border_color(String(item.get("equipment_grade", ""))) \
				if not item.is_empty() else UIKit.C_SLOT_BORDER,
			2 if not item.is_empty() else 1))
