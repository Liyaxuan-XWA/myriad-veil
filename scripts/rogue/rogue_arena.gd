class_name RogueArena
extends Node2D
## 试炼之路的局内调度器（挂在 combat_arena 下，只在 SOURCE_ROGUE 时创建）
##
## 职责：
##   - 波次刷怪 / 清空判定 / 喘息 / 三选一 / 下一关 / BOSS 关 / 下一层
##   - 局内 HUD（层数 · 小关 · 波次 + 本局增益列表）
##   - 复活与结算的入口（由 combat_arena 转进来）
##
## 不负责：角色数据快照与还原（RogueRun）、卡池数据（RogueDB）、BOSS 数值表（RogueDB）。
##
## ⚠ 模式隔离：本节点只在 SOURCE_ROGUE 下存在。其它模式的战斗流程一行都不碰。

signal finished(by_death: bool)

enum Phase { IDLE, FIGHT, BREAK, PICK, BOSS, OVER }

const MINION_SCENE := "res://scenes/world/world_enemy.tscn"
const PICKUP_SCENE := "res://scenes/items/item_pickup.tscn"
const SPAWN_MIN_DIST := 300.0
const SPAWN_MAX_DIST := 560.0
## BOSS 遗物落地后最多等这么久；玩家不捡就自动收进行囊再弹三选一（防卡关）
const BOSS_DROP_AUTOPICK := 10.0

## ===== 遗物到手提示（2026-11-11 用户要「获得装备时给个点开背包穿戴的提示」）=====
## 原来只有玩家头顶 1 秒飘字「获得 X · Tab 试炼行囊佩戴」：正忙着打下一关，回头既没看清
## 拿到了什么，也不知道该按哪个键去穿。这里在屏幕下方补一条**可点的提示卡**：
##   标题写拿到了什么 → 正文写「按 Tab 打开行囊穿戴」→ 整条可点，点了直接开行囊。
## ⚠ 位置固定在底部中央、技能栏上方：右侧是 BOSS 站位、左侧是增益清单，都会挡视线。
const GEAR_HINT_SECONDS := 12.0     ## 停留时间；树上暂停（三选一）时不计时，选完还看得到
const GEAR_HINT_W := 420.0
const GEAR_HINT_H := 56.0
const GEAR_HINT_Y := 468.0

var arena: Node2D = null
var player: Node2D = null
var boss: Node2D = null

var _phase: int = Phase.IDLE
var _break_left := 0.0
var _alive: Array = []
## 休眠期间被我们关掉的 BOSS 碰撞形状（唤醒时只打开这些，不碰原本就 disabled 的）
var _dormant_shapes: Array = []
## 上面那张表属于哪一只 BOSS —— 换层换 BOSS 时要整表重记，
## 否则第二层再休眠会「一个都记不到」，唤醒时旧表还指向已释放节点 → BOSS 永远打不到。
var _dormant_boss: Node2D = null
var _pick_panel: RoguePickPanel = null
var _settle_panel: RogueSettlePanel = null

var _hud: CanvasLayer = null
var _info_label: Label = null
var _wave_label: Label = null
## 境界 / 修为 / 行囊常驻行；突破时短暂转金色（明显提示之一）
var _realm_label: Label = null
var _realm_flash := 0.0
var _buff_panel: PanelContainer = null
var _buff_box: VBoxContainer = null
## 复活 / 结算只跑一次（玩家死亡信号与 BOSS 死亡信号可能同帧触发）
var _resolving := false
## BOSS 遗物：落地后等玩家按 F 捡（空 = 没有待捡遗物）
var _boss_drop_nodes: Array = []
## 兜底倒计时：玩家迟迟不捡就自动收进行囊再弹三选一，防卡关
var _boss_drop_wait := 0.0
## 遗物到手提示卡（可点 → 打开试炼行囊）
var _gear_hint: PanelContainer = null
var _gear_hint_title: Label = null
var _gear_hint_body: Label = null
var _gear_hint_left := 0.0


# ===================== 初始化 =====================

## 必须在 add_child 之前调用（_ready 立刻开第一波）
func setup(p_arena: Node2D, p_player: Node2D, p_boss: Node2D) -> void:
	arena = p_arena
	player = p_player
	boss = p_boss


func _ready() -> void:
	name = "RogueArena"
	_build_hud()
	# 小怪阶段先藏掉 BOSS 与它的血条，走到第 4 小关才亮出来
	_set_boss_dormant(true)
	_update_hud()
	_start_stage()


# ===================== 阶段推进 =====================

func _start_stage() -> void:
	if _phase == Phase.OVER:
		return
	if RogueRun.is_boss_stage():
		_start_boss_stage()
	else:
		_spawn_wave()


func _spawn_wave() -> void:
	_phase = Phase.FIGHT
	_alive.clear()
	# 小怪关一律把 BOSS 收起来：BOSS 打完那一只还留在场上（尸体不销毁），
	# 不重申就会在下一层的小怪波里杵着当背景。
	_set_boss_dormant(true)
	var ids := RogueDB.roll_wave(RogueRun.floor_no, RogueRun.stage_no, RogueRun.wave_no)
	var packed := load(MINION_SCENE) as PackedScene
	if packed == null:
		push_warning("小怪场景缺失：" + MINION_SCENE)
		return
	for id in ids:
		var def := RogueDB.MINIONS.get(id, {}) as Dictionary
		if def.is_empty():
			continue
		var e := packed.instantiate() as WorldEnemy
		if e == null:
			continue
		var pos := _pick_spawn_pos()
		var cfg := {
			"pos": pos,
			"max_hp": RogueDB.minion_hp(def, RogueRun.floor_no),
			"attack_power": RogueDB.minion_atk(def, RogueRun.floor_no),
			"move_speed": float(def.get("speed", 100.0)),
			"visual_id": String(def.get("visual_id", "")),
			"aggro_range": 4000.0,
			"leash_range": 9000.0,
			"melee_range": float(def.get("melee_range", 78.0)),
			"melee_angle": float(def.get("melee_angle", 110.0)),
			"melee_coeff": float(def.get("melee_coeff", 0.7)),
			"body_radius": float(def.get("body_radius", 22.0)),
			"attack_name": String(def.get("attack_name", "攻击")),
			"skills": (def.get("skills", []) as Array).duplicate(),
			"cast_coeff": float(def.get("cast_coeff", 0.35)),
			# ⚠ 试炼里全是敌人，血条 / 名字不能按大世界「野修 = 蓝、核心 = 橙」分色：
			#   山魈射手借用修士 AI（会远程风筝）就顶着一条蓝血条，玩家会误以为是友军
			#   （2026-11-08 用户报）。颜色按条目可覆盖，缺省统一敌方红。
			"hp_color": def.get("hp_color", RogueDB.MINION_HP_COLOR),
			"name_color": def.get("name_color", RogueDB.MINION_NAME_COLOR),
		}
		e.name = "Rogue_%s" % id
		e.position = pos
		e.boss_id = ""
		e.configure(cfg, String(def.get("kind", WorldEnemy.KIND_BEAST)), String(def.get("name", id)))
		var scale_v := float(def.get("scale", 1.0))
		if not is_equal_approx(scale_v, 1.0):
			e.scale = Vector2(scale_v, scale_v)
		add_child(e)
		_alive.append(e)
	_update_hud()
	arena.call("_show_center_announcement",
		"第 %d 层 · %s · 第 %d 波" % [RogueRun.floor_no, RogueRun.stage_label(), RogueRun.wave_no],
		UIKit.C_TITLE)


func _start_boss_stage() -> void:
	_phase = Phase.BOSS
	# 上一关没捡完的遗物不该跨关留着（正常流程捡完才推进，这里只兜底）
	_boss_drop_nodes.clear()
	_boss_drop_wait = 0.0
	# 兜底：正常流程到这里 _alive 必然是空的，但被强制切关时（探针 / 将来跳关）别把活怪丢在场上
	for e in _alive:
		if is_instance_valid(e):
			(e as Node).queue_free()
	_alive.clear()
	# BOSS 关开场再补一口：三个小关打完不该残血见 BOSS
	if player != null and is_instance_valid(player):
		player.call("rogue_heal_pct", RogueDB.BOSS_STAGE_HEAL_PCT)
	# ⚠ 每层 BOSS 关必须**重新实例化** BOSS：
	#   ① 每层的 BOSS 可能不同只（boss_id 每层重抽），复用旧节点就会打着上一层的敌人；
	#   ② 更致命的是上一层的 BOSS 已经 state=DEAD、died 只发过一次，
	#      复用后永远等不到击杀信号 → 卡在 BOSS 关，进不了下一层（2026-11-08 用户报）。
	if arena.has_method("spawn_rogue_boss_now"):
		var nb: Node2D = arena.call("spawn_rogue_boss_now") as Node2D
		if nb != null:
			boss = nb
	_update_hud()
	if is_instance_valid(boss):
		boss.position = arena.get_node("BossSpawn").position
		boss.visible = true
		boss.process_mode = Node.PROCESS_MODE_INHERIT
		boss.set_physics_process(true)
		if "current_hp" in boss:
			boss.set("current_hp", boss.get("max_hp"))
		if boss.has_method("_update_head_hp_bar"):
			boss.call("_update_head_hp_bar")
		boss.set("target", player)
	# ⚠ 血条靠 BOSS 的 health_changed 信号推，休眠期间没发过 → 亮出来时必须手动置满，
	#   否则顶栏是空槽（2026-11-08 截图发现）
	_set_boss_dormant(false)
	if arena.has_method("_on_boss_health_changed"):
		arena.call("_on_boss_health_changed", float(boss.get("max_hp")), float(boss.get("max_hp")))
	arena.call("_show_center_announcement",
		"第 %d 层 · %s" % [RogueRun.floor_no, WorldDB.get_boss_name(RogueRun.boss_id)],
		UIKit.C_ANNOUNCE_TITLE)


## BOSS 被击杀（combat_arena._on_boss_died 转进来）
func on_boss_defeated() -> void:
	if _phase != Phase.BOSS or _resolving:
		return
	RogueRun.boss_kills += 1
	_grant_kill_exp(null, true)
	# BOSS 击杀不走小怪那条 _rogue_on_kill，机制卡（嗜杀 / 猎杀本能 / 盗火）在这里补
	if is_instance_valid(player):
		player.call("_rogue_on_boss_kill", boss)
	arena.get_node("HUD/BossHealthBar").visible = false
	# ⚠ 顺序很重要：**先让遗物落地、玩家自己按 F 捡，捡完再弹三选一**。
	#   三选一 `SystemPanel.open()` 会暂停整棵树，落地以后再弹面板就永远捡不了了。
	if not _drop_boss_gear():
		# 没掉出东西（模板缺失等）也别卡住流程
		_open_pick(true)


## 玩家死亡（combat_arena._on_player_died 转进来）
## 返回 true = 已处理（复活或结算），false = 不该拦（理论上不会出现）
func on_player_died() -> bool:
	if _resolving:
		return true
	if RogueRun.revive_left() > 0:
		RogueRun.revives_used += 1
		_revive_player()
		return true
	_settle(true)
	return true


func _revive_player() -> void:
	if player == null or not is_instance_valid(player):
		return
	player.call("reset_player")
	player.set("invincible_timer", 3.0)
	# 清空场上残留的敌方投射物，避免刚站起来又被同一波打死
	for raw in get_tree().get_nodes_in_group("enemy_projectile"):
		if is_instance_valid(raw):
			(raw as Node).queue_free()
	arena.call("_show_center_announcement", "劫后余生（本局仅此一次）", UIKit.C_GREAT)
	_update_hud()


# ===================== 帧循环 =====================

func _process(delta: float) -> void:
	# 遗物到手提示：到点自动收。
	# ⚠ 放在所有 early-return 之前：阶段推进（FIGHT/BREAK/BOSS/OVER）都可能带着提示，
	#   写在下面对应分支之后会出现「提示永远不消失」。
	_tick_gear_hint(delta)
	# 突破高亮 2 秒后回落（不依赖 tween：三选一面板会暂停树）
	if _realm_flash > 0.0:
		_realm_flash -= delta
		if _realm_flash <= 0.0 and _realm_label != null:
			_realm_label.add_theme_color_override("font_color", UIKit.C_TEXT_DIM)
	if _phase == Phase.OVER:
		return
	# BOSS 遗物还在地上：倒计时到了就自动收进行囊并继续流程（防玩家找不到而卡关）
	if _phase == Phase.BOSS and not _boss_drop_nodes.is_empty() and not _resolving:
		_boss_drop_wait -= delta
		if _boss_drop_wait <= 0.0:
			_collect_boss_drops_auto()
		return
	if _phase == Phase.BREAK:
		_break_left -= delta
		if _break_left <= 0.0:
			_start_stage()
		return
	if _phase != Phase.FIGHT:
		return
	# 清空判定：直接轮询存活（小怪用 queue_free 自行消散，信号在离场时不可靠）
	var still: Array = []
	for e in _alive:
		if is_instance_valid(e) and int(e.get("state")) != BossBase.BossState.DEAD:
			still.append(e)
	if still.size() < _alive.size():
		for e in _alive:
			if not still.has(e) and is_instance_valid(player):
				player.call("_rogue_on_kill", e)
				_roll_minion_drop(e)
				_grant_kill_exp(e, false)
	_alive = still
	if _alive.is_empty() and not _resolving:
		_on_wave_cleared()


## 击败 BOSS：随机掉「该 BOSS 的装备之一」，**落在地上等玩家按 F 捡**。
## 返回是否成功落地（false = 没掉出东西，调用方直接开三选一）。
## ⚠ 全程不碰 CharacterData.inventory / equipment_slots / codex：
##   地面那份是「显示副本」（type 改成试炼专属值，mark_codex_from_item 才会早退），
##   真正入包时再还原 type —— 否则捡一次装备就永久解锁了图鉴、带出了局外。
func _drop_boss_gear() -> bool:
	if not RogueRun.active:
		return false
	var eq := RogueDB.roll_boss_gear(RogueRun.boss_id)
	if eq.is_empty():
		return false
	var at := Vector2.ZERO
	if is_instance_valid(boss):
		# 用脚底：BOSS 原点在画布中心，直接用 global_position 遗物会飘在半空
		at = boss.call("feet_position") if boss.has_method("feet_position") else boss.global_position
	elif is_instance_valid(player):
		at = player.global_position
	if not _spawn_gear_drop(eq, at):
		return false
	arena.call("_show_center_announcement", "BOSS 遗物已落地 · 走近按 F 拾取",
		UIKit.C_ANNOUNCE_GOLD)
	return true


## 生成一份 BOSS 装备掉落（探针可直接调，绕开随机）
func _spawn_gear_drop(eq: Dictionary, at: Vector2) -> bool:
	if not RogueRun.active or arena == null:
		return false
	var packed := load(PICKUP_SCENE) as PackedScene
	if packed == null:
		return false
	# 显示副本：type 换成试炼专属值 → mark_codex_from_item() 早退，不写图鉴；
	# 真 type 先存起来，入包时还原（见 _grant_gear_to_bag）。
	var disp := eq.duplicate(true)
	disp["_rogue_real_type"] = String(eq.get("type", CharacterData.ITEM_EQUIPMENT))
	disp["type"] = "rogue_gear_drop"
	# 装备图标留白大，全局 62px 摊到地上几乎看不见 → 用试炼遗物专用的一组显示参数
	disp["pickup_style"] = ArtDB.get_rogue_gear_pickup_style()
	var pickup: Area2D = packed.instantiate()
	pickup.item = disp
	# bind 把节点自己带进回调：捡完要知道还剩几件，才能决定什么时候弹三选一
	pickup.pickup_handler = Callable(self, "_on_boss_gear_picked").bind(pickup)
	# ⚠ 场景里的 CollisionShape2D 是共享 SubResource，改半径前必须 duplicate()
	var cs: CollisionShape2D = pickup.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is CircleShape2D:
		var shp: CircleShape2D = (cs.shape as CircleShape2D).duplicate()
		shp.radius = 64.0
		cs.shape = shp
	# ⚠ 入树前设 position（未入树时 global_position 不生效），并夹在战场内
	var pos := at
	var half := Vector2.ZERO
	if "arena_half_extents" in arena:
		half = arena.get("arena_half_extents")
	if half != Vector2.ZERO:
		pos.x = clampf(pos.x, -half.x + 48.0, half.x - 48.0)
		pos.y = clampf(pos.y, -half.y + 48.0, half.y - 48.0)
	pickup.position = pos
	arena.add_child(pickup)
	# ⚠ 必须同时登记进 combat_arena 的 _drops_on_ground：F 拾取只扫那张表
	#   （_try_pickup_nearest），漏登记 = 看得见捡不到。
	if "_drops_on_ground" in arena:
		var ground: Array = arena.get("_drops_on_ground")
		ground.append(pickup)
	_boss_drop_nodes.append(pickup)
	_boss_drop_wait = BOSS_DROP_AUTOPICK
	return true


## BOSS 遗物被拾取（pickup_handler）：还原 type 后进局内行囊。
## ⚠ 这里不能 await / 不能直接开三选一：本函数是 pickup_handler 的回调，
##   必须同步返回 bool；而且拾取光效还在飞，立刻弹面板会暂停树把 tween 冻住。
func _on_boss_gear_picked(disp_item: Dictionary, node: Node) -> bool:
	if not RogueRun.active:
		return false
	_boss_drop_nodes.erase(node)
	if not _grant_gear_to_bag(disp_item):
		return false
	if is_instance_valid(player):
		player.call("_show_float_text",
			"获得 %s · Tab 试炼行囊佩戴" % String(disp_item.get("name", "装备")),
			UIKit.C_ANNOUNCE_GOLD)
	# 头顶飘字只停 1 秒，正打怪根本来不及看 → 屏幕下方再挂一张可点的提示卡
	_push_gear_hint(String(disp_item.get("name", "装备")))
	GameState.play_ui("ui_open")
	_update_hud()
	if _boss_drop_nodes.is_empty() and _phase == Phase.BOSS and not _resolving:
		# 0.45s ≈ 拾取光效飞完的时间；期间树没暂停，计时器照跑
		var timer := get_tree().create_timer(0.45)
		timer.timeout.connect(_open_pick_after_drop)
	return true


## 把地面显示副本还原成真装备并入局内行囊（不落局外档）
func _grant_gear_to_bag(disp_item: Dictionary) -> bool:
	var eq := disp_item.duplicate(true)
	eq["type"] = String(eq.get("_rogue_real_type", CharacterData.ITEM_EQUIPMENT))
	eq.erase("_rogue_real_type")
	# 落地表现参数只是显示用的，别跟着装备进局内行囊（否则面板/存档里全是垃圾键）
	eq.erase("pickup_style")
	eq.erase("pickup_tint")
	return RogueRun.add_gear(eq)


## 遗物捡完后的三选一入口（延迟调用，避免打断拾取光效）
func _open_pick_after_drop() -> void:
	if not is_inside_tree() or _resolving or _phase != Phase.BOSS:
		return
	_open_pick(true)


## 兜底：玩家迟迟不去捡（或遗物落在够不到的地方）→ 自动收进行囊再开三选一，防卡关
func _collect_boss_drops_auto() -> void:
	var nodes := _boss_drop_nodes.duplicate()
	_boss_drop_nodes.clear()
	_boss_drop_wait = 0.0
	var got := 0
	var last_name := ""
	for nd in nodes:
		if not is_instance_valid(nd):
			continue
		var it: Dictionary = (nd as Node).get("item")
		if _grant_gear_to_bag(it):
			got += 1
			last_name = String(it.get("name", "装备"))
		(nd as Node).queue_free()
	if got > 0:
		if is_instance_valid(player):
			player.call("_show_float_text", "遗物已自动收入行囊 · Tab 试炼行囊佩戴",
				UIKit.C_TEXT_DIM)
		_push_gear_hint(last_name if got == 1 else "%s 等 %d 件" % [last_name, got])
	_update_hud()
	_open_pick(true)


## 击杀给修为：小怪 / 精英 / BOSS 三档，修为满自动突破并播明显提示
func _grant_kill_exp(e: Node, is_boss: bool) -> void:
	if not RogueRun.active:
		return
	var elite := false
	if not is_boss and e != null and is_instance_valid(e):
		elite = String(e.name).ends_with("rogue_elite")
	var amount := RogueDB.exp_for_boss(RogueRun.floor_no) if is_boss \
		else RogueDB.exp_for_minion(RogueRun.floor_no, elite)
	var info := RogueRun.add_exp(amount)
	if bool(info.get("broke", false)):
		_announce_breakthrough(info)
	_update_hud()


## 自动突破的明显提示：48px 中心公告 + 玩家头顶飘字 + 音效 + HUD 境界行高亮 2 秒
func _announce_breakthrough(info: Dictionary) -> void:
	var to := String(info.get("to", ""))
	arena.call("_show_center_announcement",
		"突破 · %s！全属性提升" % to, UIKit.C_GREAT)
	if is_instance_valid(player):
		player.call("_show_float_text", "突破！", UIKit.C_GREAT)
	GameState.play_ui("ui_open")
	_realm_flash = 2.0
	if _realm_label != null:
		_realm_label.add_theme_color_override("font_color", UIKit.C_GREAT)


## 击杀小怪 → 概率掉「试炼回血丹」。只在试炼局内，BOSS / 主模式都不产。
func _roll_minion_drop(e: Node) -> void:
	if not RogueRun.active or not is_instance_valid(e):
		return
	if randf() >= RogueDB.MINION_HEAL_DROP_CHANCE:
		return
	_spawn_heal_pill((e as Node2D).global_position)


## 生成一颗局内回血丹（探针可直接调，绕开随机）
## ⚠ 复用主模式 item_pickup 场景只是为了「光柱 + F 拾取」这套现成表现，
##   拾取归属靠 pickup_handler 拦下，绝不走 CharacterData.add_item()。
func _spawn_heal_pill(at: Vector2) -> void:
	if not RogueRun.active or arena == null:
		return
	# ⚠ 别把 arena.get() 直接赋给 Array 类型变量：属性不存在时会拿到 null，
	#   GDScript 会报「Trying to assign null to Array」。先判在不在再取。
	var drops: Array = []
	if "_drops_on_ground" in arena:
		drops = arena.get("_drops_on_ground")
	var on_ground := 0
	for d in drops:
		if not is_instance_valid(d):
			continue
		var it: Dictionary = (d as Node).get("item")
		if String(it.get("id", "")) == RogueDB.HEAL_PILL_ID:
			on_ground += 1
	if on_ground >= RogueDB.MAX_GROUND_HEAL_PILLS:
		return
	var packed := load(PICKUP_SCENE) as PackedScene
	if packed == null:
		return
	var pickup: Area2D = packed.instantiate()
	pickup.item = _heal_pill_item()
	pickup.pickup_handler = Callable(self, "_on_heal_pill_picked")
	# ⚠ 场景里的 CircleShape2D 是共享 SubResource，直接改 radius 会污染主模式掉落物。
	#   先 duplicate() 再改，只作用于这一颗。
	var cs: CollisionShape2D = pickup.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is CircleShape2D:
		var shp: CircleShape2D = (cs.shape as CircleShape2D).duplicate()
		shp.radius = RogueDB.HEAL_PILL_PICKUP_RADIUS
		cs.shape = shp
	# ⚠ 入树前设 position（未入树时 global_position 不生效），并夹在战场内
	var pos := at
	var half := Vector2.ZERO
	if "arena_half_extents" in arena:
		half = arena.get("arena_half_extents")
	if half != Vector2.ZERO:
		pos.x = clampf(pos.x, -half.x + 48.0, half.x - 48.0)
		pos.y = clampf(pos.y, -half.y + 48.0, half.y - 48.0)
	pickup.position = pos
	arena.add_child(pickup)
	drops.append(pickup)


## 局内虚拟物品：type 故意不在 ItemDB 的 equipment/material/treasure/pill 里，
## 这样 mark_codex_from_item() 直接早退、item_rarity() 也只回落到本字典的 rarity。
func _heal_pill_item() -> Dictionary:
	return {
		"id": RogueDB.HEAL_PILL_ID,
		"name": RogueDB.HEAL_PILL_NAME,
		"type": "rogue_consumable",
		"rarity": "common",
		"icon": RogueDB.HEAL_PILL_ICON,
		"count": 1,
		# 小巧落地表现 + 玉青光柱：只作用于本掉落物，主模式掉落物不受影响
		"pickup_style": ArtDB.get_rogue_heal_pickup_style(),
		"pickup_tint": Color(0.52, 0.90, 0.76, 1.0),
	}


## pickup_handler：拾取即回血，返回 true 让 item_pickup 播拾取特效并自行销毁。
## ⚠ 不生成任何物品实例、不写图鉴、不入背包 —— 这就是「无法带出局外」的落点。
func _on_heal_pill_picked(_item: Dictionary) -> bool:
	if not RogueRun.active or player == null or not is_instance_valid(player):
		return false
	var before := float(player.get("hp"))
	player.call("rogue_heal_pct", RogueDB.HEAL_PILL_PCT)
	var gained := float(player.get("hp")) - before
	if gained > 0.01:
		arena.call("_show_center_announcement",
			"回血丹 · 气血 +%.0f" % gained, UIKit.C_OK)
	else:
		arena.call("_show_center_announcement", "回血丹 · 气血已满", UIKit.C_TEXT_DIM)
	return true


func _on_wave_cleared() -> void:
	var stage_done := RogueRun.advance_wave()
	# 清波触发（回响 / 剑冢）：只在小怪波真的清空时给，BOSS 关与三选一不走这里
	var wave_tip := RogueRun.on_wave_clear(player)
	if wave_tip != "" and is_instance_valid(player):
		player.call("_show_float_text", wave_tip, UIKit.C_ACCENT)
	_update_hud()
	if not stage_done:
		_phase = Phase.BREAK
		_break_left = RogueDB.WAVE_BREAK
		arena.call("_show_center_announcement", "第 %d 波清空" % (RogueRun.wave_no - 1), UIKit.C_OK)
		return
	# 小关结束 → 先补给再弹三选一。
	# ⚠ 裸装练气只有 100 血，一层 9 波零回血必然撑不到 BOSS（2026-11-08 用户报）。
	#   rogue_heal_pct 自带 RogueRun.active 门禁 + is_dead 检查 + HUD 刷新，别自己写 hp +=。
	if player != null and is_instance_valid(player):
		player.call("rogue_heal_pct", RogueDB.STAGE_HEAL_PCT)
	_open_pick(false)


# ===================== 三选一 =====================

func _open_pick(force_rare: bool) -> void:
	_phase = Phase.PICK
	var choices := RogueRun.roll_choices(3, force_rare)
	if choices.is_empty():
		_after_pick()
		return
	if _pick_panel == null or not is_instance_valid(_pick_panel):
		_pick_panel = RoguePickPanel.new()
		_pick_panel.picked.connect(_on_picked)
		get_tree().root.add_child(_pick_panel)
	_pick_panel.setup(choices, RogueRun.floor_no, RogueRun.stage_no)
	# 教学用：第一次弹三选一时「三选一里挑一张」那一步才准露面
	RogueRun.pick_open = true
	_pick_panel.open()


func _on_picked(buff_id: String) -> void:
	RogueRun.pick_open = false
	RogueRun.add_buff(buff_id)
	# ⚠ 属性卡（精力上限 / 气血上限 / 移速 / 攻速…）改的是 CharacterData，而本局玩家是**常驻**的
	#   —— 不重读运行时缓存，那几张卡就要等下一局才生效（2026-11-12 用户报的 bug）。
	if player != null and is_instance_valid(player) \
			and player.has_method("refresh_runtime_attributes"):
		player.call("refresh_runtime_attributes")
	_update_hud()
	# 玉简化光没入的余韵：1.2 秒后再开下一关（期间树是暂停的，不会被打断）
	await get_tree().create_timer(1.2).timeout
	if not is_inside_tree() or _phase == Phase.OVER:
		return
	_after_pick()


func _after_pick() -> void:
	RogueRun.advance_stage()
	# 新的一层：洗髓生效
	if RogueRun.stage_no == 1:
		RogueRun.on_floor_start(player)
	_update_hud()
	# 符箓：新层开始免费换一次符（符囊非空才弹，第一次进层时还没有符囊）
	if RogueRun.family == "talisman" and RogueRun.stage_no == 1 \
			and not RogueRun.tal_bag.is_empty():
		_open_talisman_swap()
		return
	_phase = Phase.BREAK
	_break_left = 0.4
	# BREAK 结束后 _start_stage() 会重置阶段（BOSS 阶段在 _start_boss_stage 里设）


## 换符页：暂停树等玩家点完，关闭后回到 BREAK 继续推进
func _open_talisman_swap() -> void:
	_phase = Phase.PICK
	var page = load("res://scripts/ui/talisman_swap_page.gd").new()
	page.closed.connect(_on_talisman_swap_closed)
	get_tree().root.add_child(page)
	page.open()


func _on_talisman_swap_closed() -> void:
	if not is_inside_tree() or _phase == Phase.OVER:
		return
	get_tree().paused = false
	# ⚠ 必须重建技能栏：`_build_skill_bar` 把槽值缓存进 `_skill_slots[i]["sid"]`，
	#   `_update_skill_bar` 每帧读的是这份缓存 —— 只改 CharacterData 的话，
	#   格子图标、名字、tooltip 和冷却遮罩全停在换符之前（看着就是「没生效」）。
	if arena != null and is_instance_valid(arena) and arena.has_method("_build_skill_bar"):
		arena.call("_build_skill_bar")
	_phase = Phase.BREAK
	_break_left = 0.4


# ===================== 退出 / 结算 =====================

## ESC 主动退出：按当前层数结算
func request_quit() -> void:
	_settle(false)


func _settle(by_death: bool) -> void:
	if _phase == Phase.OVER:
		return
	_phase = Phase.OVER
	_resolving = true
	_alive.clear()
	_boss_drop_nodes.clear()
	_boss_drop_wait = 0.0
	# 任务面板（2026-11-11）：真实收局才算「完成一局试炼」（探针直调 finish_run 不误触）
	Tutorial.note("rogue_run_done")
	var result := RogueRun.finish_run(by_death)
	if _settle_panel == null or not is_instance_valid(_settle_panel):
		_settle_panel = RogueSettlePanel.new()
		_settle_panel.again_requested.connect(_on_again)
		_settle_panel.leave_requested.connect(_on_leave)
		get_tree().root.add_child(_settle_panel)
	_settle_panel.setup(result)
	_settle_panel.open()
	finished.emit(by_death)


func _on_again() -> void:
	# 沿用本局流派再来一次（不重置成剑修）
	RogueRun.start_run(RogueRun.family)
	var tree := get_tree()
	tree.paused = false
	tree.reload_current_scene()


func _on_leave() -> void:
	BattleResolver.clear()
	var tree := get_tree()
	tree.paused = false
	tree.change_scene_to_file("res://scenes/main/primordial_realm.tscn")


# ===================== BOSS 休眠 / HUD =====================

func _set_boss_dormant(dormant: bool) -> void:
	if not is_instance_valid(boss):
		return
	boss.visible = not dormant
	boss.process_mode = Node.PROCESS_MODE_DISABLED if dormant else Node.PROCESS_MODE_INHERIT
	boss.set_physics_process(not dormant)
	# ⚠ 只藏 visible 不够（2026-11-09 用户报「透明的 boss 能打到」）：
	#   玩家侧的伤害与索敌都是「扫 boss 组 + 算距离」的纯数学判定，根本不看可见性，
	#   于是开局站在 BossSpawn 那团空气前照样能砍掉血、弹反追击还会往它身上冲。
	#   两件事一起做：① 退出 "boss" 组（所有按组取敌的循环立刻失效）；
	#   ② 关掉全部碰撞形状（投射物 / 物理推挤也不再接触）。
	#   ⚠ 碰撞形状要**记下原本就 disabled 的那些**，唤醒时别把该关的一起打开。
	if "dormant" in boss:
		boss.set("dormant", dormant)
	if dormant:
		boss.remove_from_group("boss")
		if _dormant_boss != boss:
			_dormant_shapes.clear()
			_dormant_boss = boss
		for cs in boss.find_children("*", "CollisionShape2D", true, false):
			var c := cs as CollisionShape2D
			if c != null and not c.disabled:
				# 用 deferred：波次生成与场景树改动常在同一帧，避免 physics 回写报错
				c.set_deferred("disabled", true)
				_dormant_shapes.append(c)
	else:
		# 尸体不进组：试炼的 BOSS 节点死后不销毁，重新进组会又变成可索敌目标
		if not BossBase.is_unit_dead(boss):
			boss.add_to_group("boss")
		# ⚠ 只恢复「同一只 BOSS」的表：换层时旧 BOSS 已 queue_free，
		#   这时再去 deferred 打开它的形状会打到已释放实例。
		if _dormant_boss == boss:
			for c in _dormant_shapes:
				if is_instance_valid(c):
					(c as CollisionShape2D).set_deferred("disabled", false)
		_dormant_shapes.clear()
		_dormant_boss = null
	var bar := arena.get_node_or_null("HUD/BossHealthBar") as Control
	if bar != null:
		bar.visible = not dormant
	# ⚠ PhaseLabel 也是 BOSS 专用：小怪阶段留着会一直在屏幕中央写「BOSS 第一阶段」
	var phase_label := arena.get_node_or_null("HUD/PhaseLabel") as Control
	if phase_label != null:
		phase_label.visible = not dormant


func _pick_spawn_pos() -> Vector2:
	var half := Vector2.ZERO
	if "arena_half_extents" in arena:
		half = arena.get("arena_half_extents")
	var base: Vector2 = player.global_position if is_instance_valid(player) else Vector2.ZERO
	for attempt in 24:
		var ang := randf() * TAU
		var dist := randf_range(SPAWN_MIN_DIST, SPAWN_MAX_DIST)
		var pos := base + Vector2(cos(ang), sin(ang) * 0.85) * dist
		if half != Vector2.ZERO:
			pos.x = clampf(pos.x, -half.x + 140.0, half.x - 140.0)
			pos.y = clampf(pos.y, -half.y + 120.0, half.y - 120.0)
		if pos.distance_to(base) >= SPAWN_MIN_DIST * 0.55:
			return pos
	return base + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized() * SPAWN_MIN_DIST


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "RogueHUD"
	_hud.layer = 8
	add_child(_hud)

	# ⚠ CanvasLayer 下的 Control 一律绝对 offset（anchor 预设会算出 1280×1280）
	_info_label = UIKit.label("", 15, UIKit.C_TITLE)
	_info_label.position = Vector2(24.0, 58.0)
	_info_label.size = Vector2(520.0, 24.0)
	_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.soft_text_shadow(_info_label, 1)
	_hud.add_child(_info_label)

	_wave_label = UIKit.label("", 13, UIKit.C_TEXT_DIM)
	_wave_label.position = Vector2(24.0, 84.0)
	_wave_label.size = Vector2(420.0, 22.0)
	_wave_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.soft_text_shadow(_wave_label, 1)
	_hud.add_child(_wave_label)

	_realm_label = UIKit.label("", 13, UIKit.C_TEXT_DIM)
	_realm_label.position = Vector2(24.0, 108.0)
	_realm_label.size = Vector2(520.0, 22.0)
	_realm_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.soft_text_shadow(_realm_label, 1)
	_hud.add_child(_realm_label)

	# 左侧增益清单：裸字压在星图背景上读不清，套一层薄卡
	# ⚠ 放左边不放右边：右侧是 BOSS 站位（BossSpawn 多在右半场），面板会把 BOSS 挡掉半只
	# ⚠ y 必须让开上面那行境界（`_realm_label` 在 y=108，字高 22 → 底边 130）：
	#   原来写 112，和「◆ 炼气前期 · 修为 0/100 · 行囊 0 件」整行叠在一起，
	#   首行「本局增益」直接压在境界字上（2026-11-09 截图才发现）。
	_buff_panel = PanelContainer.new()
	_buff_panel.position = Vector2(20.0, 136.0)
	_buff_panel.custom_minimum_size = Vector2(272.0, 0.0)
	_buff_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buff_panel.add_theme_stylebox_override("panel",
		UIKit.accent_card_style(UIKit.C_ACCENT, 0.34, 0.30, 10))
	_buff_panel.visible = false
	_hud.add_child(_buff_panel)

	var col := UIKit.vbox(4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buff_panel.add_child(col)

	# 标题行右侧挂「TAB 查看」：玉简录在 TAB 面板的第二页，
	# 不在这里给个入口提示，玩家只会以为 HUD 上这十来行就是全部。
	var head_row := UIKit.hbox(6)
	head_row.custom_minimum_size = Vector2(248.0, 20.0)
	head_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := UIKit.label("本局增益", 12, UIKit.C_ACCENT)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_row.add_child(head)
	var gap := UIKit.spacer()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_row.add_child(gap)
	var open_hint := UIKit.label("TAB 查看全部", 10, UIKit.C_TEXT_FAINT)
	open_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_row.add_child(open_hint)
	col.add_child(head_row)

	_buff_box = UIKit.vbox(3)
	_buff_box.custom_minimum_size = Vector2(248.0, 0.0)
	_buff_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_buff_box)

	_build_gear_hint()


## 遗物到手提示卡：底部中央、技能栏上方，整条可点 → 打开「试炼行囊」。
## ⚠ 结构刻意做成「背景板 + 两条绝对定位的 Label」（和 `_info_label` 那几行同一套写法），
##   **不套 VBox/PanelContainer 布局**：容器要等下一帧才知道宽度，首帧按宽度≈0 换行，
##   会把 420×56 的卡直接撑成 420×765（probe 当场抓到）。固定坐标 + 固定 size 没有这个时序。
## ⚠ Label 一律 `clip_text` + 省略号：装备名再长也不许把卡片撑变形。
func _build_gear_hint() -> void:
	var x := (1280.0 - GEAR_HINT_W) * 0.5
	_gear_hint = PanelContainer.new()
	_gear_hint.name = "GearHint"
	_gear_hint.position = Vector2(x, GEAR_HINT_Y)
	_gear_hint.size = Vector2(GEAR_HINT_W, GEAR_HINT_H)
	_gear_hint.custom_minimum_size = Vector2(GEAR_HINT_W, GEAR_HINT_H)
	_gear_hint.mouse_filter = Control.MOUSE_FILTER_STOP
	_gear_hint.tooltip_text = "点击打开试炼行囊"
	_gear_hint.add_theme_stylebox_override("panel",
		UIKit.accent_card_style(UIKit.C_ANNOUNCE_GOLD, 0.94, 0.42, 8))
	_gear_hint.visible = false
	_gear_hint.gui_input.connect(_on_gear_hint_input)
	_hud.add_child(_gear_hint)

	_gear_hint_title = UIKit.label("", 14, UIKit.C_ANNOUNCE_GOLD)
	_gear_hint_title.position = Vector2(x + 12.0, GEAR_HINT_Y + 9.0)
	_gear_hint_title.size = Vector2(GEAR_HINT_W - 24.0, 20.0)
	_gear_hint_title.clip_text = true
	_gear_hint_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_gear_hint_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gear_hint_title.visible = false
	_hud.add_child(_gear_hint_title)

	_gear_hint_body = UIKit.label("", UIKit.F_SMALL, UIKit.C_TEXT_DIM)
	_gear_hint_body.position = Vector2(x + 12.0, GEAR_HINT_Y + 31.0)
	_gear_hint_body.size = Vector2(GEAR_HINT_W - 24.0, 18.0)
	_gear_hint_body.clip_text = true
	_gear_hint_body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_gear_hint_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gear_hint_body.visible = false
	_hud.add_child(_gear_hint_body)


## 遗物入囊 → 亮出提示。第二行把「按哪个键、点哪里」都写清楚。
## ⚠ 只改文本不重建节点：一局能捡十几件，反复 new/free 会让 HUD 抖动。
func _push_gear_hint(item_name: String) -> void:
	if _gear_hint == null:
		return
	_gear_hint_title.text = "◆ 获得遗物 · %s" % item_name
	_gear_hint_body.text = "按 Tab 打开试炼行囊，点一下即可穿戴 · 也可点这里直接打开"
	_gear_hint_left = GEAR_HINT_SECONDS
	if not _gear_hint.visible:
		_gear_hint.visible = true
		_gear_hint_title.visible = true
		_gear_hint_body.visible = true
		# 出现时淡入一下：不打断战斗，但让玩家注意到「底下多了一条」
		_gear_hint.modulate.a = 0.0
		_gear_hint_title.modulate.a = 0.0
		_gear_hint_body.modulate.a = 0.0
		var tw := _gear_hint.create_tween()
		tw.set_parallel(true)
		tw.tween_property(_gear_hint, "modulate:a", 1.0, 0.18)
		tw.tween_property(_gear_hint_title, "modulate:a", 1.0, 0.18)
		tw.tween_property(_gear_hint_body, "modulate:a", 1.0, 0.18)


func _tick_gear_hint(delta: float) -> void:
	if _gear_hint == null or not _gear_hint.visible:
		return
	_gear_hint_left -= delta
	if _gear_hint_left <= 0.0:
		_hide_gear_hint()


func _hide_gear_hint() -> void:
	if _gear_hint == null:
		return
	_gear_hint.visible = false
	if _gear_hint_title != null:
		_gear_hint_title.visible = false
	if _gear_hint_body != null:
		_gear_hint_body.visible = false
	_gear_hint_left = 0.0


## 点整条提示 = 直接开行囊：试炼里 `CharacterPanel.open_panel()` 会转给 RogueGearPanel
## （局外角色面板在试炼里被锁住，这里不能绕过它直接 new）。
func _on_gear_hint_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	# ⚠ 必须消费掉：否则这一下会同时被当成攻击（左键绑在 attack 上），点提示就挥一刀
	_gear_hint.accept_event()
	_hide_gear_hint()
	GameState.play_ui("ui_open")
	CharacterPanel.open_panel()


func _update_hud() -> void:
	if _info_label == null:
		return
	# 本局流派写在第二行：三选一里全是本流派的卡，玩家得随时知道自己在打哪一套
	var fam_name := String(RogueDB.FAMILY_NAME.get(RogueRun.family, RogueRun.family))
	_info_label.text = "试炼之路 · %s · 第 %d 层 · %s" % [
		fam_name, RogueRun.floor_no, RogueRun.stage_label()]
	var revive_now := RogueRun.revive_left()
	var revive_text := "　◆ 复活 ×%d" % revive_now if revive_now > 0 else "　◆ 复活已用"
	_wave_label.text = "第 %d/%d 波%s" % [
		RogueRun.wave_no, RogueDB.WAVES_PER_STAGE, revive_text]
	# 虎煞层数只在拿到「虎煞」卡后才出现，没拿卡的流派不该看到这一行
	if RogueRun.hunt_stacks > 0:
		var hunt_col := UIKit.C_GREAT if RogueRun.hunt_is_full() else UIKit.C_ACCENT
		_wave_label.text += "　◆ 虎煞 %d/%d" % [RogueRun.hunt_stacks, RogueRun.hunt_cap()]
		_wave_label.add_theme_color_override("font_color", hunt_col)
	else:
		_wave_label.add_theme_color_override("font_color", UIKit.C_TEXT_DIM)
	if RogueRun.is_boss_stage():
		_wave_label.text = "BOSS · %s" % WorldDB.get_boss_name(RogueRun.boss_id)
	_realm_label.text = "◆ %s · 修为 %d/%d · 行囊 %d 件" % [
		RogueRun.realm_title(), RogueRun.realm_exp,
		RogueRun.stage_exp_required(), RogueRun.gear_bag.size()]
	if _realm_flash <= 0.0:
		_realm_label.add_theme_color_override("font_color", UIKit.C_TEXT_DIM)
	# 场上没有常驻的 BOSS 名横条，靠顶栏标题认人；小怪阶段就别挂名字
	if arena != null:
		var title := arena.get_node_or_null("HUD/BattleTitleLabel") as Label
		if title != null:
			if RogueRun.is_boss_stage():
				title.text = "试炼之路 · 第 %d 层 · %s" % [
					RogueRun.floor_no, WorldDB.get_boss_name(RogueRun.boss_id)]
			else:
				title.text = "试炼之路 · 第 %d 层" % RogueRun.floor_no
	_refresh_buff_list()


func _refresh_buff_list() -> void:
	if _buff_box == null:
		return
	UIKit.clear_children(_buff_box)
	if _buff_panel != null:
		_buff_panel.visible = not RogueRun.buffs.is_empty()
	if RogueRun.buffs.is_empty():
		return
	var shown := 0
	for raw_id in RogueRun.buffs.keys():
		if shown >= 12:
			var more := UIKit.label("… 另有 %d 项（TAB 看全部）" % (RogueRun.buffs.size() - 12),
				10, UIKit.C_TEXT_FAINT)
			more.custom_minimum_size = Vector2(248.0, 18.0)
			more.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_buff_box.add_child(more)
			break
		var id := String(raw_id)
		var def := RogueDB.get_buff(id)
		if def.is_empty():
			continue
		var col: Color = RogueDB.RARITY_COLOR.get(String(def.get("rarity", "")), UIKit.C_TEXT_DIM)
		var stacks := int(RogueRun.buffs[id])
		var row := UIKit.label("%s ×%d" % [String(def.get("name", id)), stacks], 12, col)
		row.custom_minimum_size = Vector2(248.0, 18.0)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		# tooltip 给「每层效果 + 当前累计」，和玉简录同一口径（都走 buff_stack_line）
		var tip := String(def.get("desc", ""))
		var acc := RogueDB.buff_stack_line(id, stacks)
		if acc != "":
			tip += "\n" + acc
		row.tooltip_text = tip
		_buff_box.add_child(row)
		shown += 1
