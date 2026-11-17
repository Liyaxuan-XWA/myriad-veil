extends CharacterBody2D
## BOSS 共有机制基类
## 依据任务书 2.12 强制规范，所有 BOSS 共用的战斗规则骨架：
## - 双阶段（50% 血量切换）
## - 一阶段慢速规律，二阶段保留招式 + 提速 + 频率增加
## - 无 UI 预警 / 无红圈 / 无范围标记 / 无韧性条 / 无破防
## - 技能判断仅依赖肢体动作、抬手、蓄力
## - 可弹刀：物理近战/投掷；不可弹：元素/法术/能量
## - 弹刀成功 → 抵消伤害 + BOSS 僵直 + 输出窗口
## 特有招式由子类通过覆写虚方法实现。

class_name BossBase

signal health_changed(current: float, max_hp: float)
signal phase_changed(phase: int)
signal died(boss_id: String)
## 前摇开始（新手指引的「抬手暂停」教学用）
## ⚠ 所有出招都必须经过 _begin_attack()，改出招流程时别绕开它，
##   否则引导抓不到抬手，弹刀教学会静默失效（不报错）。
## 出招起手（进入前摇）广播：新手指引的弹刀教学靠它「等它抬手」。
## ⚠ kind 用 MoveDB 的字符串口径（"physical_melee" / "physical_projectile" / "elemental"…），
##   不用 AttackKind 枚举 —— 招式型 BOSS 只有字符串，枚举版会让两套起手对不上。
## ⚠ **两套起手都要发**：通用 `_begin_attack`（枚举）与招式型 `_begin_skill`（技能 id）。
##   2026-11-10 踩过：只挂在 `_begin_attack` 上，而凡界第一位面 BOSS 走 `_begin_skill`，
##   结果弹刀教学对真 BOSS 一次都不触发（端到端自检才抓到）。
signal attack_windup(kind: String, windup_time: float)

# ===== 基础状态（特有状态由子类以 100+ 追加） =====
enum BossState { IDLE, CHASE, WINDUP, ATTACK, RECOVER, STAGGER, DEAD }

# ===== 攻击类型 =====
enum AttackKind { PHYSICAL_MELEE, PHYSICAL_PROJECTILE, ELEMENTAL }

# ===== 时停（2026-11-03 用户 B 案：对局选牌窗口真的把时间停住）=====
## 全局开关，由场景层（MatchArena）按 `MatchState.time_stopped()` 拨。
## 主闸门是 `get_tree().paused`：物理、Tween、粒子、动画、以及全部按 delta
## 走的计时（buff/debuff 剩余、招式状态机、冷却）一把冻住，一个字段都不用在
## 各个 BOSS 里判断。
## **但 pause 拦不住 `get_tree().create_timer()`** —— 它的 `process_always`
## 默认 true，有 11 个 BOSS 脚本用它排招式的落地时刻（赫连霄的雷、火麟的陨、
## 石犼的爪…），树停了这些回调照样触发。所以招式的**后果**必须再拦一道：
## 掉血、挂 debuff、报名字幕这三条是所有延迟回调共同的出口。
static var world_frozen: bool = false

# ===== 血量与阶段 =====
@export var boss_id: String = "boss"
@export var max_hp: float = 1000.0
var current_hp: float
var phase: int = 1
const PHASE_TRIGGER_RATIO := 0.5

# ===== 玩家召唤的友军（2026-10-21 用户定）=====
## is_ally = true 时这个 BOSS 是「法宝召唤出来的友军」：
##   - 不加入 "boss" 组（玩家的索敌与伤害只查 boss 组，否则会被玩家误伤），改入 "ally_summon"
##   - target 指向敌方 BOSS，AI 与招式全部复用原 BOSS
##   - 有独立血量，会被敌方 BOSS 的范围攻击打死；到时间也会自动消散
##   - 消散/死亡都不发 died 信号，不影响战斗结算
var is_ally: bool = false
## ===== 对战队伍号（2026-11-02 卡片自走棋）=====
## -1 = 沿用上面 `is_ally` 那套**二值阵营**，现有全部玩法（秘境 / 塔 / 演武场 /
##   法宝召唤）行为一字不变。
## 0 / 1 = 这是某场对局里某队的棋子。敌我**只看队伍号**，既不看 is_ally，
##   也不查 "player" 组 —— 棋盘上根本没有玩家，走旧路径 `enemy_units()` 会返回空表，
##   AI 每帧拿到 null target 直接 return，整只站着不动（照影界那三只就是这么停摆的）。
## ⚠ 必须在 add_child **之前**设：`_ready()` 据此决定进不进 "match_piece" 组。
var team_id: int = -1
## ===== 休眠（试炼之路的「预告身」）=====
## 试炼开局就要把本层 BOSS 实例化出来（血条 / 骨骼 / 阶段都要提前接好），
## 但第 1~3 小关它是**不该存在**的：玩家会走到 BossSpawn 打一团空气。
## 只关 visible / process 不够 —— 伤害与索敌全是「boss 组 + 距离」的纯数学判定，
## 照样能打到、弹反追击照样往它身上冲（2026-11-09 用户报「透明的 boss 能打到」）。
## ⚠ 休眠时**必须退出 "boss" 组并关掉所有碰撞形状**，由 `RogueArena._set_boss_dormant()`
##   统一维护；其他模式不碰这个字段，默认 false 时行为与以前一字不差。
var dormant: bool = false
## 对局棋子专用组：扫这张表找队友/敌人，不去碰 "boss"，
## 免得和 combat_arena 的胜利结算、玩家索敌那套混在一起。
const MATCH_PIECE_GROUP := "match_piece"
## 友军召唤物专用物理层（第 5 层）
## ⚠ 不能留在 BOSS 层 2：玩家投射物的 mask 就是 2，会误伤友军；而且友军自己也会被
##   自己的投射物（mask=2）在出生瞬间命中 —— 2026-10-21 用户报的「召唤 BOSS 放远程打自己」。
const ALLY_SUMMON_LAYER := 16
const BOSS_LAYER := 2
const PLAYER_LAYER := 1
## 对局棋子的血条配色：己方绿、敌方红（与棋盘上卡片底座同色，一眼能认出谁是谁的）
const TEAM_HP_GREEN := Color(0.32, 0.82, 0.42, 1.0)
const TEAM_HP_RED := Color(0.86, 0.28, 0.24, 1.0)
## 召唤物伤害倍率（0.7 = 只打出本体 70% 的伤害）
var ally_damage_scale: float = 1.0
## 剩余存活时间（秒）；<= 0 表示不自动消散
var summon_life: float = 0.0
var _summon_gone: bool = false

# ===== 仇恨值系统（2026-10-21 用户定）=====
## 敌方 BOSS 对「玩家 + 每个友军召唤物」各记一份仇恨，**最高者成为 target**
## （AI 追击/面向/单体招式全都读 target，所以换 target = 换仇恨目标）。
##
## 仇恨 = ① 近 5 秒对它造成的伤害 × THREAT_PER_DAMAGE
##      + ② 距离（**越近越高**，贴脸时给 THREAT_DIST_MAX）
##      + ③ 嘲讽等外部写入（add_threat，留给以后的嘲讽机制）
##
## 切换规则（用户拍板）：
##   - **只在待机 / 追击时换目标**：前摇、出招、收招、僵直期间锁定，不会打到一半转身
##   - **目标消失立刻强制重选**（召唤物消散/被打死 → 仇恨立刻清除，BOSS 马上回玩家），
##     ⚠ 这条也是防崩：target 若留在已释放的召唤物上，下一帧读 global_position 就崩
##   - 迟滞 THREAT_SWITCH_MARGIN：新目标要高出当前目标 10% 才换，避免两个单位仇恨接近时来回抖
const THREAT_DAMAGE_WINDOW := 5.0    # 伤害记忆窗口（秒）：只算最近 5 秒打出来的伤害
const THREAT_PER_DAMAGE := 1.0       # 1 点伤害 = 1 点仇恨（调这个就能调「输出拉仇恨」的权重）
const THREAT_DIST_MAX := 40.0        # 贴脸（距离 0）时的距离仇恨上限
const THREAT_DIST_RANGE := 600.0     # 超过这个距离，距离仇恨归零
const THREAT_RECHECK := 0.4          # 定时重选目标的间隔（秒）
const THREAT_SWITCH_MARGIN := 1.1    # 新目标仇恨 ≥ 当前目标 ×1.1 才换（防抖动）
## unit → { "dmg": [[数量, 剩余秒], ...], "taunt": [...], "flat": [...] }
## dmg / taunt 按秒衰减；flat 常驻（直到该单位消失）
var _threat: Dictionary = {}
var _threat_timer: float = 0.0
## 当前仇恨最高的单位（= target 的镜像，供调试/以后的仇恨条读取）
var threat_target: Node2D = null

# ===== 战报台账（2026-11-06 棋局结算「各技能输出」）=====
## 记的是**减免后实际掉血**（= 决定这局怎么收的那个数字），不是招式名义伤害。
## ⚠ 只对带队伍号的对局棋子记账（`team_id >= 0`）：大世界 / 塔 / 演武场一字不记，
##   既不涨内存也不改变任何 PvE 行为。
## 行名 = 玩家看得懂的招式名，直接复用招名字幕那两条入口已经算好的字符串
## （`show_skill_name_at_windup` / `show_skill_line`），**不再另立一张 form_id→名字 的表** ——
## 同一件事写两处迟早和飘字漂开。
const REPORT_ROW_BASIC := "普通攻击"   # 没有招名戳记时的行（平A / 没报名字的出手）
const REPORT_ROW_REST := "其余"         # 归属不明的兜底行：宁可并进来，也不要静默丢伤害
## 行名 → 累计实际掉血
var report_rows: Dictionary = {}
## 承受账：来源棋子名 → { 招式行 → 金额 }（与 report_rows 同一笔钱，只是记在另一侧）
var report_taken: Dictionary = {}
## 当前招式名（前摇那一刻戳上，随招名一起挂到伤害落地）
var _report_form_name: String = ""
## 卫星实体自己的行名（刀痕 / 镜环场 / 点燃…）；非空时优先于主人的当前戳记
var report_tag: String = ""
## 卫星实体的伤害并入谁名下（观澜的镜像、剑客的天剑都走这条）
var report_owner: Node = null

# ===== 防御属性（玩家伤害的减免乘区）=====
## 与玩家的 AttributeDB 同名同口径，方便 DamageCalc 对双方用同一套代码。
## 抗性走递减公式：减免率 = 抗性 / (抗性 + 100)，上限 90%。
@export var physical_resist: float = 0.0
@export var magic_resist: float = 0.0
@export var resist_metal: float = 0.0
@export var resist_wood: float = 0.0
@export var resist_water: float = 0.0
@export var resist_fire: float = 0.0
@export var resist_earth: float = 0.0
@export var resist_wind: float = 0.0
@export var resist_thunder: float = 0.0

## BOSS 自身攻击力：招式伤害 = BOSS 攻击力 × 招式系数 × 阶段倍率
## 让 BOSS 伤害也能随强度成长，而不是每个招式写死绝对值
@export var attack_power: float = 40.0
## 阵旗五旗区域的攻击乘区：所有 BOSS 招式都读 attack_power，所以直接写回它。
## self = BOSS 在自家阵内 1.3；enemy = 处在玩家阵内 0.9；两个来源独立相乘。
var _zone_attack_base: float = -1.0
var _zone_self_attack_mult: float = 1.0
var _zone_enemy_attack_mult: float = 1.0


## 统一的属性读取入口 —— 与 CharacterData.attribute(attr_id) 同名同签名，
## 这样 CharacterData 计算玩家伤害时不必区分「目标是玩家还是 BOSS」
func attribute(attr_id: String) -> float:
	match attr_id:
		AttributeDB.ATTR_PHYSICAL_RESIST:
			return physical_resist
		AttributeDB.ATTR_MAGIC_RESIST:
			return magic_resist
		"resist_metal":
			return resist_metal
		"resist_wood":
			return resist_wood
		"resist_water":
			return resist_water
		"resist_fire":
			return resist_fire
		"resist_earth":
			return resist_earth
		"resist_wind":
			return resist_wind
		"resist_thunder":
			return resist_thunder
		AttributeDB.ATTR_STRENGTH, AttributeDB.ATTR_SPELL_POWER:
			return attack_power
		_:
			return 0.0


## 单独元素抗性接口：空串 / 非元素返回 0
func element_resist(element: String) -> float:
	if not AttributeDB.is_element(element):
		return 0.0
	return attribute("resist_" + element)

# 转阶段保护：期间无敌，免疫伤害与硬直，让"能量聚集"演出完整播完
var phase_transitioning: bool = false
const PHASE_TRANSITION_TIME := 1.0  # 转阶段无敌时长（秒）
## 转阶段把玩家向外推开的**冲量**（像素/秒，玩家击退速度按此衰减）
## 2026-10-18 翻倍：260 → 520，让玩家真正被打断、退出刀圈，演出才有分量
const PHASE_TRANSITION_PUSH := 520.0
# ===== 通用状态机 =====
var state: int = BossState.IDLE
var state_timer: float = 0.0
var current_attack_kind: int = AttackKind.PHYSICAL_MELEE

# ===== 受控状态（玩家气君：气锁减速 / 封技；御风回旋击退）=====
## 减速写进走位速度乘区；封技只拦「起手」，前摇会被打断；击退是独立速度，逐帧衰减。
var _cc_slow_left: float = 0.0
var _cc_slow_mult: float = 1.0
var _cc_silence_left: float = 0.0
var _knock_vel: Vector2 = Vector2.ZERO

# ===== 野修法宝在 BOSS 侧的通用状态（2026-11-01）=====
## 断念铃带一个目标侧冷却，防多只野修连锁封技。
var _treasure_bell_immune_left: float = 0.0
## 续命灯触发的短暂无敌（玩家侧另有 invincible_timer，这里给 BOSS / 野修用）
var _treasure_invuln_left: float = 0.0

# ===== 目标与面向 =====
var target: Node2D = null
var facing: Vector2 = Vector2.DOWN
## 朝向符号（+1 朝右 / -1 朝左）。美术集一律画成朝右，朝向只靠 Visual.scale.x 取反表达。
## ⚠ 符号必须单独存，不能每次去读 anim.scale.x：蓄力脉动、转阶段弹跳、消散缩小都在改 scale，
##   读回来就会把 ±1 当成倍率用，或者被 Tween 写回的绝对值抹掉符号 ——
##   表现就是「BOSS 出招途中突然转身、或者一直背对玩家」。2026-10-26 修。
var _face_sign: float = 1.0
## 体型脉动倍率（蓄力放大 / 转阶段弹跳 / 消散缩小），由 Tween 独占。
## 每帧在 _update_skin_motion 里与 _face_sign 合成一次：scale = (±_face_sign × _pulse, _pulse)。
## 这样「转身」和「呼吸」两个写入方再也不会互相覆盖。
var _pulse: float = 1.0
## 当前脉动 Tween。必须**单写者**：蓄力 Tween 跑到 1.25 才结束，
## 若出招时另起一条收招 Tween，两条会同时写 _pulse，先建的先结束、后建的赢，
## 结果就是 BOSS 待机时卡在 1.25 倍体型（2026-10-26 修）。
var _pulse_tween: Tween = null

# ===== 战斗区域边界（2026-10-23）=====
## 由 CombatArena 注入：地图半宽高（地图中心 = 世界原点）。
## Vector2.ZERO = 不限制（未注入时完全保持原行为，原型场景/独立测试不受影响）。
##
## ⚠ 为什么必须逻辑钳制、不能靠物理墙：
##   BOSS 的 collision_mask 只有 1（玩家层），而战场边界墙在 WALL_LAYER = 32，
##   **墙根本拦不住 BOSS**。虎妖的「后撤步」是朝玩家反方向冲（900 像素/秒），
##   玩家贴着地图边打它时就会被直接送出地图外，看着像闪进了虚空。
##   （刀客的瞬移 `global_position = 目标 + dir*reach` 同理。）
var arena_half_extents: Vector2 = Vector2.ZERO
## 战场中心（世界坐标）：位面战斗恒为原点；苍澜大陆的区域在地图各处，
## 钳制必须围绕区域中心，否则敌人会被拽回世界原点
var arena_center: Vector2 = Vector2.ZERO
## 边界内留的余量（像素）：让身体不贴死在墙上
## 取 56 ≈ 虎妖碰撞体半宽，比墙的内缩 40 再放宽一点，视觉上不会「半个身子在墙外」
var arena_margin: float = 56.0

# ===== 负面状态 debuff（2026-10-23）=====
## id -> 剩余秒。定义见 DebuffDB。
## ⚠ 为什么 BOSS 也要有：玩家召唤出来的刀客用沉步竖斩打敌方 BOSS 时，
##   「重伤」必须真的挂上去 —— 否则「BOSS 的改动要同步到召唤物」只做了一半
##   （召唤物的技能播了、伤害算了，附带效果却被 has_method("apply_debuff") 静默跳过）。
var debuffs: Dictionary = {}
## debuff id → 挂上它的单位（只给战报台账认归属用；不传就是没人认领，跳进"其余"）
var _debuff_by: Dictionary = {}
## 持续伤害 debuff id -> 距下一次跳伤的秒数（点燃等）
var _dot_timers: Dictionary = {}
## 暗属性「蚀」的刷新锁：>0 期间再中暗招**不续杯**（见 AttributeDB.DARK_EROSION_REFRESH_CD）。
## 没有这条，执烛的暗招会把玩家常驻磨在减疗 90% 里 —— 治疗流直接报废，而且只有玩家吃亏。
var dark_erosion_lock := 0.0

# ===== 阶段相关计时（运行时可变，供调试面板调整） =====
@export var MOVE_SPEED_P1 := 60.0
@export var MOVE_SPEED_P2 := 85.0
@export var WINDUP_TIME_P1 := 0.8
@export var WINDUP_TIME_P2 := 0.55
@export var RECOVER_TIME_P1 := 0.6
@export var RECOVER_TIME_P2 := 0.45
@export var STAGGER_TIME := 1.2

# ===== 远程停止距离（追逐时停下的距离） =====
@export var RANGED_STOP_DISTANCE := 240.0

@onready var anim: Node = $Visual
## Visual 下的 SkinVisual —— 用于把攻击特效定位到身体中心而不是脚底
## 用 get_node_or_null：场景结构变动时不至于整个脚本失效，只是退回默认值
@onready var skin: SkinVisual = get_node_or_null("Visual/Skin") as SkinVisual
@onready var head_hp_bar: ColorRect = $HPBarBG/HPBar

# ===== 受击反馈（2026-10-27 平A 手感第 3 步）=====
## 闪白打在 skin 上，不碰 anim.modulate —— 后者被转阶段红染 / 死亡渐隐占用
const HIT_FLASH_COLOR := Color(2.0, 2.0, 2.0, 1.0)
## 回弹只挪 Visual 节点，不动本体坐标与受击球：2px 足够看出「被打了一下」
const HIT_RECOIL_PX := 2.0
var _hit_flash_tween: Tween
var _hit_recoil_tween: Tween
var _visual_rest := Vector2.ZERO
var _visual_rest_ready := false

# 头顶血条宽度常量（与场景 HPBarBG 的 64px 对齐）
const HEAD_HP_BAR_WIDTH := 64.0


func _ready() -> void:
	current_hp = max_hp
	state = BossState.IDLE
	if is_ally:
		# 友军换到专用层：玩家的投射物只查 layer 2，不含这一层 → 不会误伤自己人
		collision_layer = ALLY_SUMMON_LAYER
		add_to_group("ally_summon")
		# 友军被敌方 BOSS 的阵线挡；不被玩家自己的线挡
		collision_mask |= ArrayFlag.LINE_LAYER_BOSS
	else:
		add_to_group("boss")
		# 敌方 BOSS 被玩家的阵线挡；自己的线不挡自己
		collision_mask |= ArrayFlag.LINE_LAYER_PLAYER
	# 友军召唤物**不进 "boss" 组**：玩家的索敌与伤害都只查 boss 组，
	# 进去就会被玩家自己误伤；同时也不该触发 BOSS 血条/死亡结算那套
	if team_id >= 0:
		# 对局棋子另外登记一份，敌我按队伍号判（见上面 team_id 的说明）
		add_to_group(MATCH_PIECE_GROUP)
	_update_head_hp_bar()
	_tint_head_hp_bar()
	call_deferred("_layout_head_hud")
	# 皮肤/rig 比本节点晚一帧才建好贴图，而且 idle 姿势会改变头顶高度 ——
	# 用一个 0.35 秒的低频计时器持续对齐，比只在 _ready 排一次稳。
	var hud_tick := Timer.new()
	hud_tick.wait_time = 0.35
	hud_tick.autostart = true
	hud_tick.timeout.connect(_layout_head_hud)
	add_child(hud_tick)
	# 受击/碰撞体按朝向镜像的基准值先记一遍：此刻 _face_sign 还是 +1（美术原生朝向），
	# 记早了记晚都可能把镜像后的值当成基准，导致掉头后整体错位一倍。
	_mirror_collision_shapes()
	_setup()
	# 边界同步延后一帧：BOSS 是场景里的子节点，_ready 比 CombatArena 的
	# _apply_arena_bounds() 更早跑，此刻主 BOSS 的位置还没设呢。
	# 让召唤出来的友军也能拿到（它在战斗中才 add_child，deferred 立刻能读到）。
	call_deferred("_sync_arena_bounds")


## 子类初始化钩子
func _setup() -> void:
	pass


## 从当前场景里的 CombatArena 取边界（用 group 查找，不写死节点路径）
func _sync_arena_bounds() -> void:
	if arena_half_extents != Vector2.ZERO:
		return
	var arena := get_tree().get_first_node_in_group("combat_arena")
	if arena != null and "arena_half_extents" in arena:
		var center := Vector2.ZERO
		if "arena_center" in arena:
			center = Vector2(arena.get("arena_center"))
		set_arena_bounds(Vector2(arena.get("arena_half_extents")), center)


## 注入边界与中心
## ⚠ 参数是**半宽高**（与 arena_half_extents 同口径），不是整张地图尺寸 ——
##   曾经在这里写成 map_size * 0.5，结果传入的已经是半宽高，又除了一次 2，
##   召唤物只能在半个地图里活动。
## center 不给 = 原点（位面战斗的老口径）
func set_arena_bounds(half_extents: Vector2, center: Vector2 = Vector2.ZERO) -> void:
	arena_half_extents = half_extents
	arena_center = center


## 可活动的半宽高（扣掉余量；返回 ZERO = 不限制）
func _arena_limit() -> Vector2:
	if arena_half_extents == Vector2.ZERO:
		return Vector2.ZERO
	return Vector2(
		maxf(arena_half_extents.x - arena_margin, 0.0),
		maxf(arena_half_extents.y - arena_margin, 0.0)
	)


## **位移前**的方向修正：沿 dir 走 dist 会不会把自己带出界？
## 越界就把越界那一维清零（改成沿边界切向移动），两维都越界（角落）则返回 ZERO。
## 供「后闪 / 突进」这类一次性位移在**起手时**调用，避免冲出去再被硬拉回来。
func clamp_burst_dir(dir: Vector2, dist: float) -> Vector2:
	var lim := _arena_limit()
	if lim == Vector2.ZERO:
		return dir
	var next := global_position + dir * dist
	var out := dir
	if next.x < arena_center.x - lim.x or next.x > arena_center.x + lim.x:
		out.x = 0.0
	if next.y < arena_center.y - lim.y or next.y > arena_center.y + lim.y:
		out.y = 0.0
	if out.length_squared() < 0.0001:
		return Vector2.ZERO
	return out.normalized()


# ===================== 负面状态（与玩家侧同一套 DebuffDB）=====================

## 施加 debuff（重复施加不叠加，取剩余时间较长的那个）
## `from_unit` = 挂上它的那只单位，只用于**战报台账**把跳伤记到源头名下；不传不影响效果。
## 返回是否新挂上（false = 只是刷新了时长）
func apply_debuff(id: String, duration: float, from_unit: Node = null) -> bool:
	# 时停：延迟招式带的控制 / 点燃也不能在窗口里挂上（和 deal_damage_to 同一个洞）。
	# 剩余时间本身按 delta 走，pause 时自然不走，所以只需拦住入口。
	if world_frozen:
		return false
	if id == "" or duration <= 0.0:
		return false
	var dinfo := DebuffDB.get_debuff(id)
	if dinfo.is_empty():
		push_warning("未登记的 debuff：" + id)
		return false
	var fresh := not debuffs.has(id)
	debuffs[id] = maxf(float(debuffs.get(id, 0.0)), duration)
	if from_unit != null:
		_debuff_by[id] = from_unit
	# 持续伤害：首次挂上时从第一个间隔后开始跳，不立刻跳
	if float(dinfo.get("dot_damage", 0.0)) > 0.0 and not _dot_timers.has(id):
		_dot_timers[id] = maxf(0.05, float(dinfo.get("dot_interval", 0.5)))
	if id == "stun":
		StunFx.attach(self, duration)
	return fresh
	# 持续伤害：首次挂上时从第一个间隔后开始跳，不立刻跳
	if float(dinfo.get("dot_damage", 0.0)) > 0.0 and not _dot_timers.has(id):
		_dot_timers[id] = maxf(0.05, float(dinfo.get("dot_interval", 0.5)))
	if id == "stun":
		StunFx.attach(self, duration)
	return fresh


func has_debuff(id: String) -> bool:
	return float(debuffs.get(id, 0.0)) > 0.0


## 移除一个 debuff（玩家侧的「印」引爆后要立刻清掉）
func remove_debuff(id: String) -> void:
	debuffs.erase(id)


## 外部指定的硬直（玩家的太极崩 3 层、机制奖励用）。
## 与弹刀僵直共用 STAGGER 状态，但不会覆盖掉更长的剩余僵直。
func stagger_for(seconds: float) -> void:
	if state == BossState.DEAD or phase_transitioning:
		return
	var prev := state_timer if state == BossState.STAGGER else 0.0
	state = BossState.STAGGER
	state_timer = maxf(prev, seconds)
	velocity = Vector2.ZERO


## 真·眩晕：硬直 + 头顶眩晕星（被动「雷积·震魂」等）。
## 与 stagger_for 分开 —— 弹刀 / 破盾的硬直不挂星，免得每次弹刀都像被控。
func stun_for(seconds: float) -> void:
	if seconds <= 0.0 or state == BossState.DEAD or phase_transitioning:
		return
	var prev := state_timer if state == BossState.STAGGER else 0.0
	stagger_for(seconds)
	StunFx.attach(self, maxf(prev, seconds))


## 头顶眩晕星是否该继续存在（死亡不算；硬直与 stun debuff 都算）
func is_stunned() -> bool:
	if state == BossState.DEAD:
		return false
	return state == BossState.STAGGER or has_debuff("stun")


## 眩晕星锚点：头顶再往上留出星环的呼吸位
func stun_fx_anchor_y() -> float:
	return head_top_y() - 52.0


## 移动速度乘区（多个 debuff 取最小，不连乘）
func debuff_move_mult() -> float:
	var m := 1.0
	for id in debuffs.keys():
		m = minf(m, float(DebuffDB.get_debuff(String(id)).get("move_mult", 1.0)))
	return m


## 是否被禁止「闪避类位移」（虎妖的后撤步算这一类）
func is_dodge_blocked() -> bool:
	for id in debuffs.keys():
		if bool(DebuffDB.get_debuff(String(id)).get("no_dodge", false)):
			return true
	return false


func _tick_debuffs(delta: float) -> void:
	if dark_erosion_lock > 0.0:
		dark_erosion_lock = maxf(0.0, dark_erosion_lock - delta)
	if debuffs.is_empty():
		return
	for id in debuffs.keys():
		# 持续伤害：按各自间隔结算（点燃每 0.5 秒 3 点）
		var dinfo := DebuffDB.get_debuff(String(id))
		var dot := float(dinfo.get("dot_damage", 0.0))
		if dot > 0.0:
			var interval := maxf(0.05, float(dinfo.get("dot_interval", 0.5)))
			var t := float(_dot_timers.get(id, interval)) - delta
			while t <= 0.0:
				t += interval
				_apply_dot(dot, String(id))
			_dot_timers[id] = t
		var left := float(debuffs[id]) - delta
		if left <= 0.0:
			debuffs.erase(id)
			_dot_timers.erase(id)
			_debuff_by.erase(id)
		else:
			debuffs[id] = left


## 持续伤害跳伤：真实伤害，不走抗性（点燃不是一次攻击）
## 不触发顿帧 / 仇恨，避免每 0.5 秒卡一下
func _apply_dot(amount: float, debuff_id: String = "") -> void:
	if state == BossState.DEAD or phase_transitioning or amount <= 0.0:
		return
	# 续命灯的短暂无敌也挡持续伤害
	if _treasure_invuln_left > 0.0:
		return
	# 续命灯：持续伤害致死同样改判（野修覆写 _adjust_lethal_damage）
	var dmg := _adjust_lethal_damage(amount)
	current_hp = maxf(0.0, current_hp - dmg)
	health_changed.emit(current_hp, max_hp)
	_update_head_hp_bar()
	DamageNumber.spawn(get_parent(), global_position + Vector2(0.0, head_top_y() - 6.0), dmg,
		DamageNumber.Kind.SPELL)
	# 战报：跳伤不走 take_damage，所以要在这一条单独接上，行名用 DebuffDB 的中文名（点燃 / 阴蚀）。
	# ⚠ 漏掉这里 = 「所有行加起来 == 对面掉了多少血」这条自洽判据永远差一截。
	if debuff_id != "":
		_register_damage_report(_debuff_by.get(debuff_id), dmg,
			String(DebuffDB.get_debuff(debuff_id).get("name", "持续伤害")))
	if current_hp <= 0.0:
		_die()
	elif phase == 1 and current_hp <= max_hp * PHASE_TRIGGER_RATIO:
		_enter_phase_two()


## **位移后**的位置兜底：任何路径（后闪 / 突进 / 击退 / 瞬移）都不许停在界外
func _clamp_to_arena() -> void:
	var lim := _arena_limit()
	if lim == Vector2.ZERO:
		return
	global_position.x = clampf(global_position.x, arena_center.x - lim.x, arena_center.x + lim.x)
	global_position.y = clampf(global_position.y, arena_center.y - lim.y, arena_center.y + lim.y)


func _physics_process(delta: float) -> void:
	# 时停：主闸门是树 pause（默认 process_mode 下这里根本不会跑）。留这一道
	# 是给挂在 PROCESS_MODE_ALWAYS 祖先下面的棋子兜底 —— 冻住「不动」比冻住「怎么动」容易验证。
	if world_frozen:
		return
	if state == BossState.DEAD:
		return
	# 召唤物存活倒计时：到点自行消散（不触发结算）
	if is_ally and summon_life > 0.0:
		summon_life -= delta
		if summon_life <= 0.0:
			_expire_summon()
			return
	_tick_cooldowns(delta)
	_tick_cc(delta)
	_tick_debuffs(delta)
	_tick_threat(delta)
	_tick_state(delta)
	# 击退独立于 velocity：不和追击 / 招式位移打架，逐帧衰减
	if _knock_vel.length_squared() > 1.0:
		global_position += _knock_vel * delta
		_knock_vel = _knock_vel.move_toward(Vector2.ZERO, 700.0 * delta)
	move_and_slide()
	# 位移后钳回战斗区域：见 arena_half_extents 的说明（墙拦不住 BOSS）
	_clamp_to_arena()
	_update_skin_motion()


## 把「在不在移动 / 朝哪」交给视觉节点 —— 接了正式帧的 BOSS 因此才会播 walk_side
## 两个 setter 内部都有等值判断，每帧调用不会反复重启动画；
## 一次性动作（招式）在 SkinVisual 里优先级更高，所以出招期间这两行抢不走动作。
func _update_skin_motion() -> void:
	# 朝向与脉动每帧合成一次：这是 Visual.scale 的**唯一**写入点
	anim.scale = Vector2(_face_sign * _pulse, _pulse)
	if skin == null:
		return
	skin.set_moving(velocity.length_squared() > 25.0)
	skin.set_facing(facing)


## 玩家当前所有有效阵旗（按插旗顺序；玩家旗是实体，可被 BOSS 正常索敌/命中）
func _player_array_flags() -> Array:
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not is_instance_valid(p):
		return []
	var flags = p.get("array_flags")
	if not (flags is Array):
		return []
	var out: Array = []
	for raw in flags:
		# ⚠ 必须先 is_instance_valid 再 `is Node2D`：雷落清旗后 array_flags 里可能留着
		#   已释放的旗，对 freed 实例做 `is` 会直接报错并中断战斗。
		if is_instance_valid(raw) and raw is Node2D and not bool((raw as Node).get("_dead")):
			out.append(raw)
	return out


## 玩家五旗是否闭合围住了本 BOSS；是则返回最近的一面旗（作为普通目标）
func _player_array_trap_flag() -> Node2D:
	var valid := _player_array_flags()
	if valid.size() < 5:
		return null
	var poly := PackedVector2Array()
	for raw in valid:
		poly.append((raw as Node2D).global_position)
	if not Geometry2D.is_point_in_polygon(global_position, poly):
		return null
	var best: Node2D = null
	var best_d := INF
	for raw in valid:
		var f := raw as Node2D
		var d := global_position.distance_squared_to(f.global_position)
		if d < best_d:
			best_d = d
			best = f
	return best


## 召唤物消散：缩小淡出后销毁（不算击杀，不发 died）
func _expire_summon() -> void:
	if _summon_gone:
		return
	_summon_gone = true
	state = BossState.DEAD
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	for cs in find_children("*", "CollisionShape2D", true, false):
		(cs as CollisionShape2D).set_deferred("disabled", true)
	var tween := create_tween()
	tween.tween_property(anim, "scale", Vector2(0.2, 0.2), 0.35).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(anim, "modulate:a", 0.0, 0.35)
	tween.tween_callback(queue_free)


# ===== 阵营与伤害分派（召唤系统用）=====

## 这一方攻击应该命中的所有敌对单位
## - 敌方 BOSS：玩家 + 玩家召唤出来的友军
##   ⚠ 召唤物不在 "boss" 组，只认 target 的话它永远不会挨打（用户要求「会被打死」）
## - 友军召唤物：只有它的 target（敌方 BOSS）
##   把玩家放进来就等于允许友军的范围招打到召唤者（2026-11-02 用户报的三条
##   「召唤出来的 BOSS 打自己人」全是这一类：晏无咎 / 离照 索敌、观澜镜湖）
func enemy_units() -> Array:
	if team_id >= 0:
		return _team_enemy_units()
	var out: Array = []
	if is_ally:
		if target != null and is_instance_valid(target):
			out.append(target)
		return out
	var p := get_tree().get_first_node_in_group("player")
	if p != null and not is_unit_dead(p):
		out.append(p)
	for s in get_tree().get_nodes_in_group("ally_summon"):
		if is_instance_valid(s) and not is_unit_dead(s) and not out.has(s):
			out.append(s)
	# 被玩家五旗环围住时，玩家旗也是可攻击实体（正常招式/AoE 都能打到）
	if _player_array_trap_flag() != null:
		for f in _player_array_flags():
			if not out.has(f):
				out.append(f)
	return out


## 对局棋子的可攻击列表：同组里队伍号不同、且还活着的都算敌人。
## 走 "match_piece" 组而不是 "boss" 组：棋盘上双方都是棋子，
## 用 boss 组会把「敌方队伍」和「我方队伍」混成一锅，也没法排除自己。
func _team_enemy_units() -> Array:
	var out: Array = []
	for raw in get_tree().get_nodes_in_group(MATCH_PIECE_GROUP):
		var u := raw as Node2D
		if u == null or not is_instance_valid(u) or u == self:
			continue
		if unit_team(u) != team_id and not is_unit_dead(u):
			out.append(u)
	return out


## 卫星实体的**统一取敌入口**。
##
## 为什么要有这一份：`enemy_units()` / `opponent_node()` 都是**实例方法**，只有 BossBase
## 自己用得上；而刀痕、法宝场地、扇形弹体、火种、镜像、界灯这些卫星都不是 BossBase，
## 于是各自 `get_nodes_in_group("player")` / `("boss")` 拼阵营。
## **棋局里没有 "player" 组节点**（双方都是带 `team_id` 的 `match_piece`），
## 所以那些写法在棋局里恒空 —— 2026-11-05 实测 16 张卡里至少 10 张的卫星机制静默打空。
##
## 口径与 `enemy_units()` 完全一致，只是不要求调用者是 BossBase：
## - 发起者是棋子（`team_id >= 0`）⇒ 同组里队伍号不同且活着的都算敌人
## - 发起者是 BOSS / 友军召唤物 ⇒ 直接复用它的 `enemy_units()`，不另开一套
## - 发起者是玩家侧（含玩家本人）⇒ 敌对 = "boss" 组里活着的
static func hostile_units(source: Node) -> Array:
	if source == null or not is_instance_valid(source):
		return []
	var tree := source.get_tree()
	if tree == null:
		return []
	var team := unit_team(source)
	if team >= 0:
		var out: Array = []
		for raw in tree.get_nodes_in_group(MATCH_PIECE_GROUP):
			if not is_instance_valid(raw) or raw == source:
				continue
			if unit_team(raw) != team and not is_unit_dead(raw):
				out.append(raw)
		return out
	if source is BossBase:
		return (source as BossBase).enemy_units()
	var pawns: Array = []
	for raw in tree.get_nodes_in_group("boss"):
		if is_instance_valid(raw) and raw != source and not is_unit_dead(raw):
			pawns.append(raw)
	return pawns


## 只取一个对手（卫星实体的"该朝谁走 / 该锁谁"用这个，别自己查 player 组）。
static func hostile_target(source: Node) -> Node2D:
	var list := hostile_units(source)
	if list.is_empty():
		return null
	var t: Variant = list[0]
	return t as Node2D if t is Node2D else null


## 队伍号读数：Player / 木桩 / 阵旗这些没参与对局的节点压根没有 team_id 字段，
## `int(node.get("team_id"))` 会把 null 转成 0 —— 于是**所有人都变成 0 队**，
## 棋子会把玩家当队友、把 1 队棋子当自己人。所以必须显式区分「没有这个字段」。
static func unit_team(node: Object) -> int:
	if node == null:
		return -1
	var v = node.get("team_id")
	if v == null:
		return -1
	return int(v)


## 本次攻击要结算的单位列表
func attack_units() -> Array:
	return enemy_units()


## 对任意单位结算伤害（按目标类型自动选签名）
##   玩家：take_damage(amount, attack_kind, source, element)
##   其它可受伤单位（BOSS / 友军召唤物 / 演武场木桩）：take_damage(amount, source, damage_kind, element, from_projectile)
## ⚠ 不要用 `unit is BossBase` 来分流：演武场木桩不是 BossBase，却同样使用 BOSS 版签名。
##   之前召唤物打木桩时把 attack_kind(String) 塞进 source(Node) 参数，会报
##   "Cannot convert argument 2 from String to Object" 并卡住战斗。
## 设置某来源的阵旗攻击乘区（"self" = 自家五旗阵；其它 = 敌方五旗阵）。
## 写回 attack_power，让引阵 / 封阵 / 雷击 / 剑气等全部招式统一吃到。
func set_zone_attack_mult(source: String, mult: float) -> void:
	if _zone_attack_base < 0.0:
		_zone_attack_base = attack_power
	if source == "self":
		_zone_self_attack_mult = clampf(mult, 0.0, 9.0)
	else:
		_zone_enemy_attack_mult = clampf(mult, 0.0, 9.0)
	attack_power = _zone_attack_base * _zone_self_attack_mult * _zone_enemy_attack_mult


## 对局专用的伤害倍率。**`team_id < 0` 恒为 1.0** —— 秘境 / 万界塔 / 演武场
## 拿不到这个队伍号，那些模式一分一毫都没变。
## 为什么需要它：`MatchAdapter` 是靠 `attack_power` 折算输出的，而通用 prototype
## 那一档 BOSS 的伤害根本不读 `attack_power`（见 `MatchDB.FLAT_DAMAGE_CARDS`），
## 实测虎妖在棋盘上只打出 2 DPS（名义 1062）。倍率放在这两个出口上，
## 就不必去动它自己的常数。
func _match_damage_scale() -> float:
	return 1.0 if team_id < 0 else MatchDB.match_damage_scale(boss_id)


func deal_damage_to(unit: Node, amount: float, attack_kind: String, element: String = "") -> bool:
	# 时停里招式不落地的关键一道：延迟回调由 SceneTreeTimer 驱动，
	# 它 process_always=true，树暂停也照发 —— 实测（负面测试：把这道去掉）
	# 选牌窗口里那一发 500 点延迟伤害照样落在棋盘上。
	if world_frozen:
		return false
	if unit == null or not is_instance_valid(unit) or not unit.has_method("take_damage"):
		return false
	# 尸体不吃伤害：半招收刀前目标已经倒下时，剩下那几段不该继续打在淡出动画上
	# （返回 false 也让「打中才成立」的那几招按落空处理，符合实际观感）
	if is_unit_dead(unit):
		return false
	# 对局棋子只打对方队伍。队伍号 -1 的（玩家 / 木桩 / 没入队的场景物）在棋子里一律打不动：
	# 棋盘上不该有任何东西被"顺带"蹭到，漏标的召唤物也比误伤好查。
	if team_id >= 0:
		var tt := unit_team(unit)
		if tt < 0 or tt == team_id:
			return false
	var dmg := amount * (ally_damage_scale if is_ally else 1.0) * _match_damage_scale()
	if unit.is_in_group("player"):
		unit.take_damage(dmg, attack_kind, self, element)
	else:
		var dk := "elemental" if attack_kind == "elemental" else "physical"
		unit.take_damage(dmg, self, dk, element, false)
	return true


## 读血量（玩家用 hp、BOSS 用 current_hp），读不到返回 -1
## 用于判断「这一下是否真的扣到血了」（无敌帧/弹反会让 take_damage 空转）
## ⚠ 演武场木桩永远不扣血：必须返回 -1（未知），否则 BOSS 会误判「没打中」而卡在出招循环。
func unit_hp(unit: Node) -> float:
	if unit == null or not is_instance_valid(unit):
		return -1.0
	if unit.has_method("get_training_stats"):
		return -1.0
	var v = unit.get("hp")
	if v != null:
		return float(v)
	var c = unit.get("current_hp")
	if c != null:
		return float(c)
	return -1.0


# ===================== 仇恨值系统 =====================

## 每帧推进仇恨：清理失效单位 → 窗口衰减 → 必要时重选目标
## 玩家五旗环的目标覆盖：被围住时用最近旗做普通目标；环破后清掉旗目标。
## BossBase 与 WorldEnemy 各自的 _tick_threat 都先走这里，避免大世界 BOSS 漏掉。
func _tick_player_array_trap_override() -> bool:
	if is_ally:
		return false
	# ⚠ target 可能是刚被雷落/爆发打掉的旗或召唤物：已释放实例不能做 `is`，
	#   否则报 "Left operand of 'is' is a previously freed instance" 直接闪退。
	if not is_instance_valid(target):
		target = null
		threat_target = null
	var trap := _player_array_trap_flag()
	if trap != null:
		if state == BossState.IDLE or state == BossState.CHASE:
			_set_threat_target(trap)
		return true
	# 环破了 / 目标旗没了：立刻丢掉旗目标，下一段正常重选玩家
	if is_instance_valid(target) and target is ArrayFlag:
		target = null
		threat_target = null
	return false


func _tick_threat(delta: float) -> void:
	if is_ally:
		return   # 召唤物自己不需要仇恨表（它的 target 恒为敌方 BOSS）
	if _tick_player_array_trap_override():
		return
	# ① 单位消失（召唤物消散 / 被打死）→ 仇恨立刻清除
	var dirty := false
	for u in _threat.keys():
		if _threat_of(u) < 0.0:
			_threat.erase(u)
			dirty = true
	# ② 只记最近 THREAT_DAMAGE_WINDOW 秒的伤害，超时的那笔自动失效
	for u in _threat.keys():
		var rec: Dictionary = _threat[u]
		for key in ["dmg", "taunt"]:
			var arr: Array = rec.get(key, [])
			var i := arr.size() - 1
			while i >= 0:
				arr[i][1] = float(arr[i][1]) - delta
				if float(arr[i][1]) <= 0.0:
					arr.remove_at(i)
				i -= 1
	# ③ ⚠ 当前目标没了 → **强制立刻重选**（不受「出招中不换目标」限制，
	#    否则 target 指向已释放的召唤物，下一帧读 global_position 就崩）
	if target == null or not is_instance_valid(target) or _threat_of(target) < 0.0:
		_update_threat_target(true)
		return
	# ④ 定时重选（或刚有单位消失）
	_threat_timer -= delta
	if dirty or _threat_timer <= 0.0:
		_threat_timer = THREAT_RECHECK
		_update_threat_target()


## 重选仇恨目标：force=true 时无视「出招中不换」的限制
func _update_threat_target(force := false) -> void:
	if is_ally or state == BossState.DEAD:
		return
	# 前摇 / 出招 / 收招 / 僵直期间锁定目标（用户定：只在待机与追击时换）
	if not force and not (state == BossState.IDLE or state == BossState.CHASE):
		return
	var best: Node2D = null
	var best_v := -1.0
	for u in enemy_units():
		var v := _threat_of(u)
		if v > best_v:
			best_v = v
			best = u
	if best == null:
		return
	var cur := threat_target
	if cur == null or _threat_of(cur) < 0.0:
		_set_threat_target(best)
		return
	if best == cur:
		return
	# 迟滞：新目标得高出当前目标 10% 才换，否则两个单位仇恨接近时会来回抖
	if best_v > _threat_of(cur) * THREAT_SWITCH_MARGIN:
		_set_threat_target(best)


## 真正切换：target 就是 AI 与单体招式读的那个变量，改它即改仇恨目标
func _set_threat_target(unit: Node2D) -> void:
	if unit == null or unit == threat_target:
		return
	threat_target = unit
	target = unit


## 该单位当前的仇恨值（-1 = 已失效/已消散，不该再当目标）
## ⚠ 入参故意不加类型：`_threat` 的键可能是**已经释放**的召唤物（玩家的镜像分身
##   复读功法打完伤害就碎，键还留在表里）。写成 `unit: Node` 的话，传已释放实例
##   在调用边界就被拒（「argument 1 (previously freed) is not a subclass of the
##   expected argument class」），函数体里那句 is_instance_valid 根本轮不到执行，
##   于是失效的键永远清不掉、BOSS 打完分身就再也选不出目标（2026-11-02 探针抓到）。
func _threat_of(unit) -> float:
	if unit == null or not is_instance_valid(unit):
		return -1.0
	# 已经开始消散的召唤物不再算数（用户定：召唤物没了就立刻回玩家）
	if unit is BossBase and bool((unit as BossBase)._summon_gone):
		return -1.0
	# ⚠ 尸体：`_die()` 只关碰撞、播完淡出动画才 free，期间节点还在树上、组里。
	#   而死亡后 `current_hp` 恰好是 **0** 而不是负数，所以只看血量读数的「单位消失」
	#   判定永远不会触发 —— 于是 target 钉在尸体上，整只 BOSS 对着空气反复出招
	#   （2026-11-03 用户报「boss 死后还会被当做目标攻击」）。
	#   必须走 is_unit_dead：它同时认 BossBase 的 state、Player 的 is_dead 变量、旗的 is_dead。
	if is_unit_dead(unit):
		return -1.0
	var total := 0.0
	var rec: Dictionary = _threat.get(unit, {})
	for e in rec.get("dmg", []):
		total += float((e as Array)[0]) * THREAT_PER_DAMAGE
	for key in ["taunt", "flat"]:
		for e in rec.get(key, []):
			total += float((e as Array)[0])
	# 距离仇恨：**越近越高**
	var up := unit as Node2D
	if up != null:
		var d := global_position.distance_to(up.global_position)
		total += THREAT_DIST_MAX * clampf(1.0 - d / THREAT_DIST_RANGE, 0.0, 1.0)
	return total


## 读某单位的仇恨（对外：调试面板 / 以后做仇恨条用）
func threat_of_unit(unit) -> float:
	return _threat_of(unit)


## 外部写入仇恨 —— 将来的「嘲讽」机制就调这个
## duration > 0：按秒衰减；duration <= 0：常驻，直到该单位消失
func add_threat(unit, amount: float, duration := 5.0) -> void:
	if is_ally or unit == null or not is_instance_valid(unit):
		return
	var rec := _threat_entry(unit)
	var key := "flat" if duration <= 0.0 else "taunt"
	(rec[key] as Array).append([amount, duration])


## 受伤时给来源记一笔伤害仇恨（在 take_damage 里调，用的是**实际扣掉的血**）
func _register_damage_threat(src, amount: float) -> void:
	if is_ally or amount <= 0.0:
		return
	var unit := _threat_unit_of(src)
	if unit == null:
		return
	(_threat_entry(unit)["dmg"] as Array).append([amount, THREAT_DAMAGE_WINDOW])


## 战报：把这一笔**实际掉血**记到"打出来的那只棋子"名下的一行里，
## 同时在**挨打的我这只**身上记一行「来源棋子 · 招式」的承受账。
## 归属还原与仇恨走同一套思路（弹体→发射者、召唤物→主人），但这里要的是
## "棋子"而不是"单位"：玩家侧、没有队伍号的 PvE 单位一律不记。
func _register_damage_report(src, amount: float, label: String = "") -> void:
	if amount <= 0.0:
		return
	var piece := _report_piece_of(src)
	if piece == null:
		return
	# 调用方给了行名（跳伤这类"不是一次出手"的伤害）就用它，否则按卫星戳记→主人招名→平A
	var row := label if label != "" else _report_label_of(src, piece)
	piece._report_add(row, amount)
	# 承受账：同一笔钱记到**挨打这一侧**，行名按来源棋子分组。
	# ⚠ 镜像 / 天剑这类"自己也是 BossBase、也带队伍号"的召唤物，承受要并回主人：
	#   它们不是 12 张卡之一，账留在自己身上就永远收不进快照
	#   （实测对面打出 212,794 而我方承受只有 179,138，差的就是打在镜像身上的那截）。
	var sink := self
	if report_owner != null and is_instance_valid(report_owner) and report_owner is BossBase:
		sink = report_owner as BossBase
	if sink.team_id >= 0:
		# 两层：来源棋子名 → { 招式行 → 金额 }。
		# ⚠ 不用「来源 · 招式」拼一层键：视图要把来源当组头、招式当行，
		#   拼串就得再拆回去，而招式名里本来就带「·」（天律·宣读）—— 拆错一次错一整列。
		var src_name := WorldDB.get_boss_name(piece.boss_id)
		if not sink.report_taken.has(src_name):
			sink.report_taken[src_name] = {}
		var bucket: Dictionary = sink.report_taken[src_name]
		bucket[row] = float(bucket.get(row, 0.0)) + amount


## 读卫星实体身上的战报字段：先看脚本属性，再看 meta。
## ⚠ 为什么要允许 meta：刀痕 / 场地 / 弹体这些**不是 BossBase** 的节点各自散在 8 个文件里，
##   给每个类都补两个成员变量等于把改动摊到别人正在改的文件上；
##   `set_meta("report_owner", 主人)` 一行就够，而且读侧只有一条路，不会两种写法各记一半。
static func _report_field(node: Node, prop: String) -> Variant:
	if node == null or not is_instance_valid(node):
		return null
	var v: Variant = node.get(prop)
	if v == null and node.has_meta(prop):
		v = node.get_meta(prop)
	return v


## `_report_field` 读出来的东西要当字符串用时的**唯一**安全出口。
## 属性不存在 → null；`String(null)` 不是空串而是运行期错误（与 `bool(null)` 同族坑）。
static func _report_str(node: Node, prop: String) -> String:
	var v: Variant = _report_field(node, prop)
	if typeof(v) == TYPE_STRING:
		return String(v)
	return ""


## 伤害来源 → 该记在谁名下。返回 null = 不该记（不是棋子）。
## ⚠ 只认 BossBase 且 `team_id >= 0`：棋局棋子才有战报，PvE 一个字都不写。
func _report_piece_of(src) -> BossBase:
	if src == null or not is_instance_valid(src):
		return null
	var unit: Node = null
	# 卫星实体自己带了主人（镜像 / 天剑 / 场地 / 弹体）
	var own: Node = _report_field(src, "report_owner") as Node
	if own != null and is_instance_valid(own):
		unit = own
	if unit == null and (src is BossBase or src.is_in_group("player")):
		unit = src
	if unit == null:
		# 没显式挂主人的投射物：沿用仇恨那条归属链的字段口径
		var raw = src.get("source")
		unit = raw as Node if is_instance_valid(raw) else null
	if unit == null:
		var raw2 = src.get("owner_unit")
		unit = raw2 as Node if is_instance_valid(raw2) else null
	if unit == null or not (unit is BossBase):
		return null
	var b := unit as BossBase
	if b.team_id < 0 or not is_instance_valid(b):
		return null
	return b


## 这一笔算哪一行：卫星自带行名 > 来源自己的戳记 > 主人当前招式戳 > 「普通攻击」。
## 平A 与"没报名字的出手"合并成一行，是口径上的诚实：表里出现的那一行
## 一定真有其事，而不是硬凑一个玩家看不懂的枚举。
## ⚠ 一律走 `_report_str()`：`String(null)` 在本机 4.7.2 是
##   「Invalid call. Nonexistent 'String' constructor」，直接崩整局
##   （实机崩在观澜的镜像上 —— MirrorImage 不是 BossBase，压根没有 `_report_form_name`）。
func _report_label_of(src, piece: BossBase) -> String:
	var tag := _report_str(src, "report_tag")
	if tag != "":
		return tag
	var t := _report_str(src, "_report_form_name")
	if t != "":
		return t
	var own := _report_str(piece, "_report_form_name")
	if own != "":
		return own
	return REPORT_ROW_BASIC


func _report_add(row: String, amount: float) -> void:
	if row == "":
		row = REPORT_ROW_REST
	report_rows[row] = float(report_rows.get(row, 0.0)) + amount


## 这只棋子到目前为止的总输出（战报页与"行加起来==对面掉了多少"的自洽判据用）
func report_total() -> float:
	var t := 0.0
	for k in report_rows.keys():
		t += float(report_rows[k])
	return t


## 前摇戳记：招名一飘出来就把它当作"当前招式"。
## 只在这一条入口写，状态字幕（护体/夺火/阶段）不会污染台账。
func _report_stamp(text: String) -> void:
	if team_id < 0 or text == "":
		return
	# 「招名 · 补充说明」这类回执行（离照投日打空）不当作新招式：
	# 带空格的 " · " 是本项目给回执用的分隔，招式名里的「·」两侧没有空格（天律·宣读）。
	if text.contains(" · "):
		return
	_report_form_name = text


## 该单位的仇恨记录（没有就建一条）
func _threat_entry(unit: Node) -> Dictionary:
	if not _threat.has(unit):
		_threat[unit] = { "dmg": [], "taunt": [], "flat": [] }
	return _threat[unit]


## 伤害来源 → 仇恨单位：BOSS / 召唤物 → 它自己；玩家 → 玩家
## （src 同样不限类型：投射物的发射者可能就是刚碎掉的镜像分身）
## 投射物自己不是单位 → 先看它身上有没有发射者字段（boss_projectile 的 source），
## 都没有就当玩家的攻击（玩家投射物目前不带发射者字段）
func _threat_unit_of(src) -> Node2D:
	if src == null or not is_instance_valid(src):
		return null
	if src is BossBase or src.is_in_group("player"):
		return src as Node2D
	var raw = src.get("source")
	# raw 可能指向已释放的召唤物；Variant 上的 `is Node` 同样会报 previously freed
	var owner_node: Node = raw as Node if is_instance_valid(raw) else null
	if owner_node == null:
		var raw2 = src.get("owner_unit")
		owner_node = raw2 as Node if is_instance_valid(raw2) else null
	if owner_node != null and is_instance_valid(owner_node):
		if owner_node is BossBase or owner_node.is_in_group("player"):
			return owner_node as Node2D
	# 对局棋子里不兜底给玩家：棋盘上本来就没有玩家，而万一场景里同时存在一个
	# （例如从主城直接切进去、玩家节点还没释放），把伤害记到玩家头上就会串台。
	if team_id >= 0:
		return null
	return get_tree().get_first_node_in_group("player") as Node2D


## 子类可覆写：处理自身技能冷却
func _tick_cooldowns(_delta: float) -> void:
	pass


## 受控计时：减速 / 封技（玩家气锁·缚脉）/ 野修法宝抗性窗口
func _tick_cc(delta: float) -> void:
	if _cc_slow_left > 0.0:
		_cc_slow_left = maxf(0.0, _cc_slow_left - delta)
		if _cc_slow_left <= 0.0:
			_cc_slow_mult = 1.0
	_cc_silence_left = maxf(0.0, _cc_silence_left - delta)
	if _treasure_bell_immune_left > 0.0:
		_treasure_bell_immune_left = maxf(0.0, _treasure_bell_immune_left - delta)
	if _treasure_invuln_left > 0.0:
		_treasure_invuln_left = maxf(0.0, _treasure_invuln_left - delta)


## 断念铃：同一目标 8 秒内只吃一次封技
func is_treasure_bell_immune() -> bool:
	return _treasure_bell_immune_left > 0.0


func mark_treasure_bell_immune(seconds: float) -> void:
	_treasure_bell_immune_left = maxf(_treasure_bell_immune_left, seconds)


## 当前身上最高的穿抗削减（暗属性「蚀」）—— 由 DamageCalc 在进减免曲线之前读取。
func debuff_resist_shred() -> float:
	var v := 0.0
	for id in debuffs.keys():
		v = maxf(v, float(DebuffDB.get_debuff(String(id)).get("resist_shred", 0.0)))
	return clampf(v, 0.0, 0.9)


## 当前受到的治疗乘区（暗「蚀」= 0.10，即减疗 90%）。身上没有相关 debuff 时是 1.0。
func debuff_heal_mult() -> float:
	var v := 1.0
	for id in debuffs.keys():
		v = minf(v, float(DebuffDB.get_debuff(String(id)).get("heal_mult", 1.0)))
	return clampf(v, 0.0, 1.0)


## 暗属性命中的通用结算：这一击是暗 → 尝试挂「蚀」。
## 放在受击方而不是攻击方：任何暗来源（BOSS / 玩家 / 符箓 / 以后再加的东西）都自动成立，
## 不需要每个 form 配 debuff_on_hit，也就不会把「暗」重新绑回某一只 BOSS 的媒介。
func try_dark_erosion() -> void:
	if dark_erosion_lock > 0.0:
		return
	var dur := AttributeDB.dark_erosion_time(element_resist(AttributeDB.DARK))
	if dur <= 0.0:
		return
	dark_erosion_lock = AttributeDB.DARK_EROSION_REFRESH_CD
	apply_debuff(AttributeDB.DARK_EROSION_ID, dur)


## 统一回血入口：治疗乘区（蚀）只在这里过一遍，子类不要再自己写 current_hp + heal
func apply_heal(amount: float) -> float:
	if state == BossState.DEAD or amount <= 0.0:
		return 0.0
	var before := current_hp
	current_hp = minf(max_hp, current_hp + amount * debuff_heal_mult())
	if current_hp > before:
		health_changed.emit(current_hp, max_hp)
		_update_head_hp_bar()
	return current_hp - before


## 当前身上最高的护体削减（蚀甲锥）
func debuff_guard_shred() -> float:
	var s := 0.0
	for id in debuffs.keys():
		s = maxf(s, float(DebuffDB.get_debuff(String(id)).get("guard_shred", 0.0)))
	return clampf(s, 0.0, 1.0)


## 续命灯：子类覆写；返回实际要扣的血量
func _adjust_lethal_damage(amount: float) -> float:
	return amount


## 棘甲佩：子类覆写；返回要真实反弹给攻击者的伤害（0 = 不反）
func _reflect_thorns(_mitigated: float, _source: Node, _damage_kind: String,
		_from_projectile: bool) -> float:
	return 0.0


## 真实伤害：不走抗性 / 护体 / 弹反，只保留致死改判与阶段切换。
## 棘甲佩的反弹走这里，避免和「受击 → 反伤」形成递归。
func take_true_damage(amount: float, _source: Node = null) -> void:
	if state == BossState.DEAD or phase_transitioning or amount <= 0.0:
		return
	if _treasure_invuln_left > 0.0:
		return
	var dmg := _adjust_lethal_damage(amount)
	current_hp = maxf(0.0, current_hp - dmg)
	health_changed.emit(current_hp, max_hp)
	_update_head_hp_bar()
	DamageNumber.spawn(get_parent(), global_position + Vector2(0.0, head_top_y() - 6.0), dmg,
		DamageNumber.Kind.PHYSICAL)
	if current_hp <= 0.0:
		_die()
	elif phase == 1 and current_hp <= max_hp * PHASE_TRIGGER_RATIO:
		_enter_phase_two()


## 减速：mult = 移速乘区（0.5 = 减速 50%），同一次控制取最强 + 最长
func apply_slow(mult: float, seconds: float) -> void:
	if state == BossState.DEAD or seconds <= 0.0:
		return
	var m := clampf(mult, 0.05, 1.0)
	if _cc_slow_left <= 0.0 or m < _cc_slow_mult:
		_cc_slow_mult = m
	_cc_slow_left = maxf(_cc_slow_left, seconds)


## 封技：期间不开始新招；正在前摇的直接打断（走位仍然按减速继续）。
## ⚠ 这是「控制」打断，和「目标走开就收招」不是一回事：后者已按用户要求取消（2026-11-12）。
func apply_skill_lock(seconds: float) -> void:
	if state == BossState.DEAD or seconds <= 0.0:
		return
	_cc_silence_left = maxf(_cc_silence_left, seconds)
	if state == BossState.WINDUP:
		_cancel_windup()


func is_skill_locked() -> bool:
	return _cc_silence_left > 0.0


## 击退：加到独立的击退速度上，逐帧衰减（不会打断招式与追击逻辑）
func take_knockback(impulse: Vector2) -> void:
	if state == BossState.DEAD or phase_transitioning:
		return
	_knock_vel += impulse * 1.2


## 状态机主循环：处理基础状态，特有状态交由子类覆写 _tick_extra_state
func _tick_state(delta: float) -> void:
	# 先让子类处理特有状态（若当前是特有状态）
	if _is_extra_state(state):
		_tick_extra_state(delta)
		return

	match state:
		BossState.IDLE:
			# 站桩时也要盯着玩家：以前 IDLE/RECOVER 不更新朝向，BOSS 会一直保持
			# 上一次出手的方向，玩家绕到背后它就是"背对玩家站着"（2026-10-26 修）
			_update_facing_to_target()
			if is_skill_locked():
				velocity = Vector2.ZERO
			elif _should_trigger_special():
				_trigger_special()
			else:
				state_timer -= delta
				if state_timer <= 0.0:
					_choose_next_action()
		BossState.CHASE:
			_chase_target(delta)
			if is_skill_locked():
				return
			if _should_trigger_special():
				_trigger_special()
				return
			if target:
				var dist := _distance_to_target()
				_on_chase_reached(dist)
		BossState.WINDUP:
			# 前摇一旦起手就**不许因为目标走开而收招**（2026-11-12 用户定：
			# 玩家躲判定可以，但怪不能自己把已经抬手的招咽回去）。
			# 只有控制类（封技 / 弹刀僵直）还能打断 —— 见 apply_skill_lock / STAGGER。
			state_timer -= delta
			if state_timer <= 0.0:
				_fire_attack()
		BossState.ATTACK:
			state_timer -= delta
			if state_timer <= 0.0:
				state = BossState.RECOVER
				state_timer = _recover_time()
		BossState.RECOVER:
			# 收招后重新看向玩家，下一招才是从"对着人"起手
			_update_facing_to_target()
			state_timer -= delta
			if state_timer <= 0.0:
				state = BossState.IDLE
				state_timer = _idle_time()
		BossState.STAGGER:
			# 被弹刀打断：手上的招式动作立刻停掉回到待机。
			# 放在状态分支而不是各 BOSS 的 on_parried 里：子类会覆写 on_parried
			# （刀客按伤害系数算僵直时长、剑客另有追击 buff），只有这里是所有来源的必经之路。
			# cancel_one_shot 在没播动作时直接 return，每帧调不浪费。
			if skin != null:
				skin.cancel_one_shot()
			# 蓄力脉动的 Tween 是「到点才结束」的，被打断后没人收尾，
			# 会一直停在 1.25 倍体型。僵直是唯一可靠的必经点，在这里把脉动归位。
			_tween_pulse(1.0, 0.0)
			state_timer -= delta
			if state_timer <= 0.0:
				state = BossState.IDLE
				state_timer = _idle_time()


## 是否为子类特有的状态（默认 false，子类覆写）
func _is_extra_state(_s: int) -> bool:
	return false


## 子类特有状态处理（覆写）
func _tick_extra_state(_delta: float) -> void:
	pass


## 是否应触发特有技能（默认 false，子类覆写）
func _should_trigger_special() -> bool:
	return false


## 触发特有技能（子类覆写）
func _trigger_special() -> void:
	pass


## 追逐到一定距离后的处理（子类覆写，实现"近战/远程选招"）
func _on_chase_reached(_dist: float) -> void:
	pass


## 中断前摇：动画收回待机、脉动归位、回到追击。写在一处，子类不用各写一遍。
func _cancel_windup() -> void:
	if skin != null:
		skin.cancel_one_shot()
	_tween_pulse(1.0, 0.0)
	velocity = Vector2.ZERO
	state = BossState.CHASE


## 选择下一步动作（子类覆写）
func _choose_next_action() -> void:
	state = BossState.CHASE


## 当前与目标的距离
func _distance_to_target() -> float:
	if target != null and is_instance_valid(target):
		return global_position.distance_to(target.global_position)
	return 99999.0


## 开始攻击（进入蓄力阶段）
func _begin_attack(kind: int) -> void:
	if is_skill_locked():
		return
	current_attack_kind = kind
	state = BossState.WINDUP
	state_timer = _windup_time()
	attack_windup.emit(_attack_kind_name(kind), _windup_time())

	# 更新面向
	if target != null and is_instance_valid(target):
		_set_facing((target.global_position - global_position).normalized())

	# 技能名在**前摇的这一瞬间**飘出，并一直挂到技能释放（hold = 前摇时长）
	var wname := _attack_kind_skill_name(kind)
	if wname != "":
		show_skill_name_at_windup(wname, _windup_time(), _windup_color(kind))

	_on_attack_windup(kind)


## 前摇飘字要显示的技能名（通用 AttackKind 体系，子类覆写）
## 返回空串 = 这个 BOSS 不在前摇显示技能名（默认关闭，不影响既有 BOSS）
## ⚠ 覆写了本函数的子类，必须同时去掉技能释放时的 _show_skill_text 调用，
##   否则同一招会飘两次名字（一次前摇、一次释放）
## ⚠ 不要改名成 _windup_skill_name：剑客/刀客有自己的同名函数但参数是 String，
##   GDScript 要求覆写签名一致，同名会直接把子类脚本判成解析错误（已踩过）
func _attack_kind_skill_name(_kind: int) -> String:
	return ""


## 蓄力时的动作表现（子类覆写）
func _on_attack_windup(_kind: int) -> void:
	pass


## 攻击释放（蓄力结束）
func _fire_attack() -> void:
	state = BossState.ATTACK
	state_timer = 0.15
	_reset_visual()
	# 出招音效
	GameState.play_sfx("boss_attack")
	_do_attack(current_attack_kind)


## 实际执行攻击（子类覆写，按 attack_kind 分发）
func _do_attack(_kind: int) -> void:
	pass


## 更新面向为当前指向玩家的方向
func _update_facing_to_target() -> void:
	if target != null and is_instance_valid(target):
		_set_facing((target.global_position - global_position).normalized())


## 设置朝向（唯一入口）。只记符号，真正写 Visual.scale 在 _update_skin_motion，
## 所以调用时机不会和蓄力/转阶段的 Tween 抢同一帧的 scale。
func _set_facing(dir: Vector2) -> void:
	facing = dir
	var sign_now := 1.0 if dir.x >= 0.0 else -1.0
	if not is_equal_approx(sign_now, _face_sign):
		_face_sign = sign_now
		_mirror_collision_shapes()


## 碰撞体按朝向镜像。
##
## ⚠ 为什么需要：受击形状是**照着美术轮廓**摆的，球心不一定在 x=0。
##   翻转只发生在 `Visual.scale.x` 上，碰撞体挂在 CharacterBody2D 下不会跟着翻 ——
##   不镜像的话，掉头后受击框会跑到身后，正面砍头反而打不到。
## ⚠ 基准值在第一次调用时记进 meta（此时 _face_sign 必为 +1，即美术原生朝向），
##   之后每帧只在符号真的变化时才写，不会和物理线程抢。
func _mirror_collision_shapes() -> void:
	for cs in find_children("*", "CollisionShape2D", true, false):
		var c := cs as CollisionShape2D
		if c == null:
			continue
		if not c.has_meta("facing_base_x"):
			c.set_meta("facing_base_x", c.position.x)
		var bx := float(c.get_meta("facing_base_x"))
		c.position.x = bx * _face_sign


## 追逐目标
func _chase_target(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		velocity = Vector2.ZERO
		return

	var to_target: Vector2 = target.global_position - global_position
	var dist: float = to_target.length()
	var dir: Vector2 = to_target.normalized()

	# 已经进入远程攻击距离：停下
	if dist <= RANGED_STOP_DISTANCE:
		velocity = Vector2.ZERO
		_set_facing(dir)
		return

	# 若已经重叠，主动分离，防止"粘贴"
	if dist < 40.0:
		velocity = -dir * _move_speed()
		_set_facing(dir)
		return

	velocity = dir * _move_speed()
	_set_facing(dir)


## 阶段相关时间函数
func _move_speed() -> float:
	var base := MOVE_SPEED_P2 if phase == 2 else MOVE_SPEED_P1
	# 重伤等 debuff 只影响**走位速度**，不影响突进/瞬移这类技能位移（那是招式本身的距离）
	var slowed := _cc_slow_mult if _cc_slow_left > 0.0 else 1.0
	return base * debuff_move_mult() * slowed


func _windup_time() -> float:
	return WINDUP_TIME_P2 if phase == 2 else WINDUP_TIME_P1


func _recover_time() -> float:
	return RECOVER_TIME_P2 if phase == 2 else RECOVER_TIME_P1


func _idle_time() -> float:
	return 0.5 if phase == 2 else 1.2


## 阶段伤害倍率：二阶段翻倍（共有机制）
func _damage_multiplier() -> float:
	return 2.0 if phase == 2 else 1.0


## ===== 视觉工具 =====
## 技能字幕：出招时在 BOSS 头顶飘出招式名（样式对齐玩家那套 `_show_float_text`）
## 目的：让玩家能「读到」BOSS 在放什么招，而不是只看动作猜
##   color      文字颜色（默认技能名的橙黄色）
##   font_size  字号（默认 20）
##   width      Label 宽度（默认 120）—— ⚠ 必须显式给宽 + 居中对齐，
##             否则 Label 会从偏移点往右画、看起来偏左；长提示要给更宽的值
##   hold       上浮前的停留秒数（默认 0）—— 机制说明类提示需要停久一点
##   y_off      相对 BOSS 原点的垂直偏移（默认 -80，头顶血条上方）
func _show_skill_text(text: String, color: Color = UIKit.C_SKILL_NAME,
		font_size: int = UIKit.SKILL_NAME_SIZE, width: float = UIKit.SKILL_NAME_WIDTH,
		hold: float = 0.0, y_off: float = -160.0) -> void:
	if text == "":
		return
	# 时停：窗口里不许冒出新字幕（招名 / 机制提示都走这一条）。
	# 延迟回调由 SceneTreeTimer 驱动、树暂停时照样触发（见 world_frozen 的说明），
	# 不拦就会在静止的画面上挂出一条正在淡出的字。
	if world_frozen:
		return
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	# 深色描边：地图纹理再花，招式名也能看清（2026-10-24 用户要求）
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 0.95))
	label.add_theme_constant_override("outline_size", maxi(3, int(round(float(font_size) * 0.22))))
	# BOSS 站位以脚底为原点、身高约 92。招式名抬到 -160：
	#   ① 玩家伤害数字从 -76 起步、上飘 46px，最高只到 -122；
	#   ② 让出独立的「技能名层」，伤害数字不会再穿过招式名（2026-10-24 用户要求）。
	label.size = Vector2(width, float(font_size) + 8.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 招式名固定在「血条上方 30px」：以血条（头顶 −14）为参照物，
	# 所有 BOSS / 所有招式都在同一个相对位置，不再靠每个调用点手调 y_off
	# （2026-10-28 用户定：技能飘字位置要固定住）。
	# 直接读血条当前的顶边（而不是再算一遍头顶）：血条由 0.35 秒计时器跟随，
	# 用它的实际位置才能保证「招名永远比血条高 30px」，不受跟随间隔影响。
	var bg_ctrl := head_hp_bar.get_parent() as Control if is_instance_valid(head_hp_bar) else null
	var bar_top := bg_ctrl.offset_top if bg_ctrl != null else head_top_y() - 14.0
	var _ignored_y_off := y_off
	label.position = global_position + Vector2(-width * 0.5, bar_top - 30.0)
	# 高于 DamageNumber.Z_INDEX(40)：即使偶尔重叠，招式名仍在上层
	label.z_index = 60
	get_parent().add_child(label)
	var tween := label.create_tween()
	if hold > 0.0:
		tween.tween_interval(hold)
	# 停留越长的提示，上浮/淡出也放慢一点，避免「还在读就没了」
	var dur := 0.5 if hold <= 0.0 else 0.9
	tween.tween_property(label, "position:y", label.position.y - 30.0, dur)
	tween.parallel().tween_property(label, "modulate:a", 0.0, dur)
	tween.tween_callback(label.queue_free)


## 技能名飘字：**前摇一开始**就飘出，停留 hold 秒（应传前摇时长）后才上浮淡出。
## 效果 = 名字在前摇期间一直挂在头顶，技能真正释放的那一刻才开始消失。
## 单独包一层是因为 GDScript 不支持命名参数，而 hold 排在参数列表很后面。
## color：物理招式黄、法术招式蓝（用户 2026-10-20 定），由调用方按招式的 attack_kind 传。
func show_skill_name_at_windup(text: String, hold: float,
		color: Color = UIKit.C_SKILL_NAME) -> void:
	_report_stamp(text)
	_show_skill_text(text, color, UIKit.SKILL_NAME_SIZE,
		UIKit.SKILL_NAME_WIDTH, maxf(0.0, hold))


## 技能名飘字颜色：物理（近战/投掷）= 黄，法术/元素 = 蓝
## 入参用 MoveDB 的 attack_kind 字符串，四大 BOSS 的数据表口径统一
static func skill_name_color(attack_kind: String) -> Color:
	if attack_kind.begins_with("physical"):
		return UIKit.C_DMG_PHYS
	return UIKit.C_DMG_SPELL


## 阵营读数：训练木桩这类「在 boss 组里但不是 BossBase」的单位没有 is_ally，
## `bool(node.get("is_ally"))` 会拿到 null 并报「Nonexistent 'bool' constructor」，
## 而且每结算一次就刷一条（2026-11-01 用户实机镜湖 + 木桩 = 118 条错误）。
static func is_ally_unit(node: Object) -> bool:
	return node != null and node.get("is_ally") == true


## 对手读数：这一招该打谁、该朝谁走、距离按谁算，一律走这里。
## - 敌方 BOSS → 场上活着的玩家
## - 法宝召唤出来的友军 → 它的 target（敌方 BOSS）
## ⚠ 各 BOSS 脚本里不要再自己 `get_first_node_in_group("player")`：
##   友军一查就查到召唤者头上，2026-11-02 用户报「劫主令的晏无咎、火正令的离照
##   召出来一直对着玩家打」就是这两份各自的 `_player_node()` 漏了阵营判断。
func opponent_node() -> Node2D:
	if team_id >= 0:
		# 棋子：target 还活着且确实是对方队伍就直接用（仇恨系统会维护它），
		# 否则退回「最近的对方棋子」—— 不能返回 null，否则 AI 每帧 return、整只发呆。
		if is_instance_valid(target) and target is Node2D \
				and unit_team(target) != team_id and not is_unit_dead(target):
			return target as Node2D
		var best: Node2D = null
		var best_d := INF
		for u in _team_enemy_units():
			var d := global_position.distance_squared_to((u as Node2D).global_position)
			if d < best_d:
				best_d = d
				best = u
		return best
	if is_ally:
		if target != null and is_instance_valid(target) and target is Node2D:
			return target as Node2D
		return null
	for raw in get_tree().get_nodes_in_group("player"):
		var p := raw as Node2D
		if p != null and not is_unit_dead(p):
			return p
	return null


## 索敌**兜底**读数：拿不到 target 时该朝谁走、该看谁在移动。
## - 现有玩法 → 场上玩家
## - 对局棋子（team_id >= 0）→ 对方棋子
## ⚠ 各 BOSS 脚本里那些「`target` 空就 `get_first_node_in_group("player")` 顶一下」的兜底
##   一律改走这里。棋盘上没有 player 节点，直接查玩家组会拿到 null，
##   于是 `_choose()` 每帧 return，整只 BOSS 站着不动 —— 照影界三只都踩在这上面。
func focus_node() -> Node2D:
	if team_id >= 0:
		return opponent_node()
	return get_tree().get_first_node_in_group("player") as Node2D


## 死亡读数：`is_dead` 在 Player 上是变量，在 BossBase / MirrorImage / TrainingDummy 上是方法。
## - `bool(node.get("is_dead"))` 对方法名拿到 null 或 Callable → 报「Nonexistent 'bool' constructor」，
##   而且 AI 每帧决策刷一条（2026-11-02 分身复读一剑开天抢了仇恨，观澜 _choose() 的 target
##   变成 MirrorImage 就踩在这行）。
## - 只写 `has_method("is_dead")` 又会在 Player 上恒为 false → 死人也算活着。
## 两种都不许再手写，统一走这里。
static func is_unit_dead(node: Object) -> bool:
	if node == null or not is_instance_valid(node):
		return true
	if node.has_method("is_dead"):
		return bool(node.call("is_dead"))
	return node.get("is_dead") == true


## 通用 AttackKind 枚举 → 飘字颜色（boss_base 自己的 _begin_attack 体系用）
func _windup_color(kind: int) -> Color:
	if kind == AttackKind.ELEMENTAL:
		return UIKit.C_DMG_SPELL
	return UIKit.C_DMG_PHYS


## 招式形态 → 攻击类型（MoveDB 的 boss.attack_kind），前摇飘字据此分黄/蓝
func _attack_kind_of(form_id: String) -> String:
	return String(MoveDB.resolve_boss(form_id).get("attack_kind", ""))


## AttackKind 枚举 → MoveDB 的字符串口径（attack_windup 与弹反判定统一用字符串）
func _attack_kind_name(kind: int) -> String:
	match kind:
		AttackKind.PHYSICAL_MELEE:
			return "physical_melee"
		AttackKind.PHYSICAL_PROJECTILE:
			return "physical_projectile"
		_:
			return "elemental"


## 技能名字幕（保留调用方颜色：物理黄 / 法术蓝）
## hold 传前摇时长：名字会一直挂到技能释放（伤害打出）那一刻才开始淡出
## ⚠ _show_skill_text 的 width 是固定宽度 + 居中对齐，长文案必须显式加大，
##   否则会被裁掉（默认 120 只够 4~5 个字）
func show_skill_line(text: String, hold: float, font_size: int = UIKit.SKILL_NAME_SIZE,
		width: float = UIKit.SKILL_NAME_WIDTH, color: Color = UIKit.C_SKILL_NAME,
		y_off: float = -160.0) -> void:
	_report_stamp(text)
	_show_skill_text(text, color, font_size, width, maxf(0.0, hold), y_off)


## 状态字幕：非招式名、非伤害数字的 BOSS 提示（阶段 / 夺火 / 护体 / 阵势等）统一灰色。
## 保留 color 参数只是为了兼容旧调用点；这里不再使用它。
## 招名 / 状态字幕的填充色。
## ⚠ 不要图省事直接改 `UIKit.C_TEXT_DIM`：那个常量面板也在用。
## 原来这两条路径传的是 C_TEXT_DIM(0.62 灰)，那是按**暗战场**挑的 ——
## 执烛换成月白石坪（平均亮度 73）后，字心与地面几乎同亮度，
## 4px 深色描边一盖就只剩一圈轮廓，实测变成「空心字」。
## 提到近白：暗底上比原来更清楚，亮底也读得出来。
## 伤害数字与招名的「物理黄 / 法术蓝」两色规则走的是别的入口，不受这里影响。
const SKILL_TEXT_FILL := Color(0.94, 0.95, 0.98, 1.0)


func show_windup_line(text: String, hold: float, font_size: int = UIKit.SKILL_NAME_SIZE,
		width: float = UIKit.SKILL_NAME_WIDTH, _color: Color = UIKit.C_SKILL_NAME,
		y_off: float = -160.0) -> void:
	_show_skill_text(text, SKILL_TEXT_FILL, font_size, width, maxf(0.0, hold), y_off)


## 状态字幕的短入口（固定使用默认字号 / 宽度 / 位置）
func _show_status_text(text: String, font_size: int = UIKit.SKILL_NAME_SIZE,
		width: float = UIKit.SKILL_NAME_WIDTH, hold: float = 0.0,
		y_off: float = -160.0) -> void:
	_show_skill_text(text, SKILL_TEXT_FILL, font_size, width, maxf(0.0, hold), y_off)


## 受击半径（到最远受击体边缘的距离 = **外接半径**）
## 命中判定要把它算进去：否则判定只按「玩家→BOSS 中心」的距离，
## 会出现「剑尖已经够到 BOSS 边缘、判定却说没打到」的情况
## ⚠ 换大体型美术时要跟着改 .tscn 里的碰撞体尺寸，让碰撞轮廓 ≈ 身体轮廓：
##   判定圈比视觉身体小，玩家就会遇到「明明砍到人了却不算命中」；反过来则像挨了空气。
##   刀客正式素材身体显示宽约 78px（贴图 310 × scale 0.25）→ 半宽 39 → radius 40。
func hit_radius() -> float:
	# ⚠ 语义是「**外接半径**」：到最远受击球边缘的距离，只服务粗粒度距离
	#   （自动靠近时的站定距离、矩形判定的容差）。**精确命中一律走 hit_spheres()**。
	#   胶囊之后这个值会比身体半长长一点（虎妖圆心不在原点，取最远一侧的外接圆）。
	var max_r := 0.0
	for sp in hit_spheres():
		var sv: Vector3 = sp
		max_r = maxf(max_r, Vector2(sv.x, sv.y).length() + sv.z)
	return max_r


## 本体厚度半径：受击球半径的最大值（**不含**球心偏移）。
## 与 hit_radius() 的分工：那个是外接半径，只给粗粒度站位用；这个是「身体有多厚」，
## 招式的可见范围与判定要从本体边缘往外量，用这个才对。
## 虎妖物理胶囊 → 72（2026-10-28 按立绘轮廓重算：横向 270×144，贴在 y −147…−3）。
func body_radius() -> float:
	var r := 0.0
	for sp in hit_spheres():
		r = maxf(r, (sp as Vector3).z)
	return r


## 世界坐标某点到**本体边缘**的距离（站在身体覆盖范围内 = 0）。
##
## ⚠ 距离类判据一律用它，不要用 `_distance_to_target()`：
##   中心距离对大体型 BOSS 是错的 —— 虎妖 265px 宽的身体，玩家贴着脸打时中心距离还有 130+，
##   按 130 的近战阈值刚好卡在边界上，于是「贴着打」被判定成「离得远」去放远程（2026-10-27 用户报）。
func edge_distance_to(world_pos: Vector2) -> float:
	var best := INF
	for sp in hit_spheres():
		var sv: Vector3 = sp
		var c := global_position + Vector2(sv.x, sv.y)
		best = minf(best, maxf(0.0, world_pos.distance_to(c) - sv.z))
	return 0.0 if best == INF else best


## 受击判定用的「地面占位圆」：读场景里**所有**碰撞体，把每个形状摊成若干圆，
## 返回 [Vector3(本地球心 x, 本地球心 y, 半径)]。
##
## 为什么不只用一个半径：横长体型的身体地面占位远大于厚度。单个圆只盖得住身体中段，
## 把半径提到能盖住头尾，厚度又跟着虚胖 —— 隔着三个身位就能砍到。
##
## 形状支持（2026-10-26 起加胶囊）：
##   · CircleShape2D  → 原样一个圆
##   · CapsuleShape2D → 沿长轴采样成若干圆（间距 ≤ 0.6r，并集与胶囊轮廓误差 < 1px）
## 虎妖（2026-10-28 起）：横向胶囊 r=72 / height=270，节点 position y=−75、rotation 90°。
## 立绘实测 x −136.8…+133.1（宽 270）× y −146.5…−3.1（高 143），胶囊覆盖 x ±135、y −147…−3，
## 脚底以下不再有空白碰撞；`prototype_boss.hit_spheres()` 再把球心投影回 y=0 供扇形判定。
## 2026-10-27 的「单圆 r=84 在原点」已废弃：它在脚下多出 84px 空白，头尾又盖不住。
##
## ⚠ 和物理碰撞共用同一批形状是**故意**的：在 .tscn 里摆形状，挡路轮廓与受击判定
##   就自动一致，不会出现「调了脚本忘了场景」的漂移。
## ⚠ 球坐标是**本地**的，且**已经按朝向镜像好**（见 `_set_facing` → `_mirror_collision_shapes`）：
##   形状如果不在原点，掉头时由场景侧镜像，调用方不用再乘 flip（虎妖胶囊 x 对称，y 偏移不受影响）。
## ⚠ 全部禁用（死亡时会全部 disable）时返回半径 0 的单球 = 打不到，符合预期。
func hit_spheres() -> Array:
	var out: Array = []
	for cs in find_children("*", "CollisionShape2D", true, false):
		var c := cs as CollisionShape2D
		if c == null or c.shape == null or c.disabled:
			continue
		if c.shape is CircleShape2D:
			out.append(Vector3(c.position.x, c.position.y, (c.shape as CircleShape2D).radius))
		elif c.shape is CapsuleShape2D:
			var cap := c.shape as CapsuleShape2D
			var r := cap.radius
			# 长轴 = 形状本地 +Y。必须走 transform 才能兼容 .tscn 里写的 90° rotation
			# （横着的胶囊），将来斜着摆也不用改这里。
			var seg := maxf(cap.height * 0.5 - r, 0.0)
			var steps := maxi(1, int(ceil(seg * 2.0 / maxf(r * 0.6, 1.0))))
			for i in range(steps + 1):
				var t := -seg + seg * 2.0 * float(i) / float(steps)
				var p: Vector2 = c.transform * Vector2(0.0, t)
				out.append(Vector3(p.x, p.y, r))
	if out.is_empty():
		out.append(Vector3(0.0, 0.0, 0.0))
	return out


## 身体视觉中心（相对本节点原点）—— 攻击特效、飘字应从身体发出而不是脚底
## 角色贴图越高，返回值越靠上；未接入贴图时给保守值
func body_center() -> Vector2:
	if skin != null:
		return skin.body_center()
	return Vector2(0.0, -16.0)


## 出招原点（**世界坐标**）：妖丹从嘴里出来、爪击从爪尖起手、刀气从刀尖劈出。
##
## 为什么要单独一个接口：`global_position` 是脚底，`body_center()` 是躯干中心，
## 两者对兽型 / 持械 BOSS 都离「真正喷出东西的地方」差得很远 ——
## 虎妖原有口径是 `global_position + facing * 20`（身体正中偏前），
## 妖丹看起来像从胸口冒出来的。骨骼（BossRig）里配了锚点表后，这里就能取到
## **跟着关节一起动**的真实嘴 / 爪位置。
##
## ⚠ 只在**点状出生**的招式上用它（投射物、口喷、刀气）。
##   扇形 / 圆形 AOE 的判定中心必须留在身体中心：判定是按「玩家→球心」的距离与夹角算的，
##   FX 原点一挪，显示就会比实际判定远出去一截，玩家会觉得「明明有刀光却没伤害」。
func muzzle_position(form_id: String) -> Vector2:
	if skin != null:
		var anim := ArtDB.boss_move_anim(skin.visual_id, form_id)
		if anim != "":
			var p: Variant = skin.muzzle_position(anim)
			if p != null:
				return Vector2(p)
	# 没接骨骼 / 该动作没登记锚点：沿用老口径（身前 20px），别偷偷改其他 BOSS 的手感
	return global_position + facing * 20.0


## 从出招原点指向目标的**方向**（不是 facing）。
##
## ⚠ 出招原点一旦从身体中心挪到嘴 / 爪尖 / 刀尖，弹道就不能再抄 `facing`：
##   锚点可能比身体高几十像素、靠前上百像素，照 facing 平射等于**整体平移**，
##   近距离必定从目标旁边擦过去（虎妖实测偏 74px）。
##   有目标就按「出生点 → 目标」算；没目标才用 facing。
func _aim_from(spawn: Vector2) -> Vector2:
	if target != null and is_instance_valid(target) and target is Node2D:
		var d: Vector2 = (target as Node2D).global_position - spawn
		if d.length_squared() > 0.01:
			return d.normalized()
	return facing


## 脚底相对本节点原点的偏移（像素，通常为正 = 原点在脚底上方）
## ⚠ BOSS 形象默认 `anchor_bottom = false`：贴图**以原点为中心**，
##   所以 global_position 是身体中心，脚底在 +半高（实测虎妖 +46）。
##   而玩家是 anchor_bottom = true（原点就在脚底）。
##   任何「贴近/追击/站到目标脚边」的逻辑都必须用 feet_position() 对齐，
##   否则会把 BOSS 的中心摆在目标脚底 → 视觉上整个人压在目标上半身（2026-10-22 修）。
## ⚠ 它读的是 skin.visual_rect.end.y —— **画布底边，不是命中平面**。赤霄界三只 rig 的
##   画布底下留了 95px 空边（feet_offset = +95），而受击球压在地面 y=0；拿它当落点会让
##   玩家落到命中平面下方 95px（2026-10-30「完美弹反赫连霄后追击打不到」正是这个）。
##   涉及**命中判定**的贴近一律用 hit_spheres() 的球心定平面，feet_position 只用于看。
func feet_offset() -> float:
	if skin != null:
		return skin.visual_rect.end.y
	return 0.0


## 脚底的世界坐标（"站在地上"的那个点）
func feet_position() -> Vector2:
	return global_position + Vector2(0.0, feet_offset())


## 当前翻转符号（+1 朝右 / -1 朝左）
## 美术集一律画成朝右，朝向只靠 Visual.scale.x 取反表达（ArtDB 的 flip_driven 就是这个意思）。
## 从 scale.x 自己取而不是从 facing 取：突进 / 穿刺这类招式会把朝向临时改成位移方向
## （domain_boss_01._start_dash、domain_boss_01_c 的穿刺），facing 那时候还是旧值。
func _flip_sign() -> float:
	return _face_sign


## 脉动 Tween 的唯一入口：先杀掉上一条，保证任何时刻只有一条在写 _pulse。
## duration <= 0 表示立刻归位（打断类状态用它，别留动画尾巴）。
func _tween_pulse(target: float, duration: float) -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	if duration <= 0.0:
		_pulse = target
		_pulse_tween = null
		return
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, "_pulse", target, duration)


func _reset_visual() -> void:
	# 只收脉动，不碰朝向：_face_sign 由 _update_skin_motion 每帧合成进 scale
	_tween_pulse(1.0, 0.1)


func _flash_attack(color: Color) -> void:
	anim.modulate = color
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(anim):
		anim.modulate = Color.WHITE


## 蓄力脉动的放大倍数。
## 人形 BOSS 用 1.25（膨胀感强，玩家一眼看懂「在蓄力」）；
## 兽型体量大，1.25 倍像充气、而且会盖过招式本身的骨骼动作 —— 子类覆写成更小的值。
func windup_pulse_scale() -> float:
	return 1.25


func _show_windup(color: Color) -> void:
	_tween_pulse(windup_pulse_scale(), _windup_time())
	anim.modulate = color


## 招式起手动作：把这套帧压进「前摇 + 出手」，最后一帧正好落在伤害判定那一帧上
## duration = 前摇 + ATTACK 状态时长（0.15），所以抬手→挥出→命中是一条线，不会出现
## 「人已经挥完了、判定还没到」这种动作与效果对不上的观感。
## 动作名查 ArtDB.BOSS_MOVE_ANIMS；没登记或美术集里没这套帧 → play_one_shot 自己跳过。
func _play_form_anim(form_id: String, duration: float) -> void:
	if skin == null:
		return
	skin.play_one_shot(ArtDB.boss_move_anim(skin.visual_id, form_id), duration)


## ===== 投掷物生成 =====
## origin 传了就用它当出生点（通常是 muzzle_position() 给的嘴 / 爪尖）；
## 不传 = 老口径「身体正中偏前 20px」，世界小怪等没有骨骼锚点的调用方不受影响。
func _spawn_projectile(kind: String, origin: Variant = null) -> Node2D:
	var proj_scene := load("res://scenes/boss/boss_projectile.tscn")
	var proj: Node2D = proj_scene.instantiate()
	# ⚠ 用 set() 写运行期脚本字段：proj 的静态类型是 Node2D，
	#   直接点 attack_kind 会报 "Invalid assignment ... on Area2D"
	var spawn := global_position + facing * 20.0
	if origin != null:
		spawn = Vector2(origin)
	proj.set("global_position", spawn)
	proj.set("attack_kind", kind)
	# 投射物碰撞层（2026-10-21 修）：
	#   友军 → 只打敌方 BOSS（layer 2）；**不能含 16**，否则出生瞬间命中自己
	#   敌方 → 打玩家(1) + 友军召唤物(16)，"召唤物会被打死"这条才成立
	if is_ally:
		proj.set("collision_mask", BOSS_LAYER)
	else:
		# 敌方投射物还要检测玩家阵旗的命中体（ArrayFlag 的 Hitbox 在 256 层）；
		# 漏掉这一层时 BOSS 的远程会直接穿过旗子，只有近战/AoE 打得到旗。
		proj.set("collision_mask",
			PLAYER_LAYER | ALLY_SUMMON_LAYER | ArrayFlag.PLAYER_HIT_LAYER)
	# 友军伤害倍率：投射物不走 deal_damage_to()，必须在发射时把倍率带给它
	# （boss_projectile 命中时乘 ally_scale），否则召唤物的远程技能吃不到强化加成。
	# 对局专用倍率也搭这趟车 —— 弹体同样绕不过 deal_damage_to()，
	# 虎妖六成的招是弹体，漏了它近战补再多也还是 2 DPS。
	proj.set("ally_scale",
			(ally_damage_scale if is_ally else 1.0) * _match_damage_scale())
	get_parent().add_child(proj)
	# 太极盘「接化发」按组找敌弹；必须在入树后加组，发射时就知道阵营
	if not is_ally:
		proj.add_to_group("enemy_projectile")
	return proj


## 技能投射物：套用对应功法的 ArtDB 弹体外观 / 朝向 / 缩放，
## 让 BOSS / 野修放同一门功法时，弹体也和玩家一致（普攻投射物不受影响）
func _apply_skill_projectile_visual(proj: Node2D, form_id: String) -> void:
	if not is_instance_valid(proj) or form_id == "":
		return
	var sid := SkillDB.get_skill_id_by_form(form_id)
	if sid == "":
		return
	var fx := ArtDB.get_skill_fx(sid)
	if fx.is_empty():
		return
	var pv := String(fx.get("projectile_visual", ""))
	if pv != "" and proj.has_method("set_visual_override"):
		proj.call("set_visual_override", pv)
	if bool(fx.get("projectile_align", false)):
		proj.set("align_visual", true)
	var sc := float(fx.get("projectile_scale", 1.0))
	if not is_equal_approx(sc, 1.0) and proj.has_method("set_visual_scale"):
		proj.call("set_visual_scale", sc)


## ===== 头顶血条 =====
## 填充条宽度跟着场景里 HPBarBG 的实际宽度走：
##   换大体型素材时只改 .tscn 的 HPBarBG 几何，填充条自动等宽（三只 BOSS 原本都是 64px，行为不变）
func _head_hp_bar_width() -> float:
	var bg := head_hp_bar.get_parent() as Control
	return bg.size.x if bg != null and bg.size.x > 0.0 else HEAD_HP_BAR_WIDTH


## 对局棋子的头顶血条按队伍染色：0 队（玩家方）绿、其余（敌方）红。
## 只在 team_id >= 0 时介入 —— 单人打 BOSS 时血条沿用场景里的原色，行为不变。
## 血条**显示**用哪一队的颜色：-1 = 跟随 `team_id`。
## 棋子自己召唤出来的单位（观澜倒影、石犼回声这类）是各脚本
## `get_parent().add_child(...)` 出来的，没有队伍号 → 血条走场景默认红，
## 自家召唤物看着像敌方（2026-11-03 用户报「血条显示还是有 bug」）。
## 这里只借它的颜色，不改 `team_id`：改了会连带让它开始索敌、也开始挨打，
## 那是逐招裁剪表要定的事，不该塞进一个显示修复里。
var display_team: int = -1


func _tint_head_hp_bar() -> void:
	if team_id < 0 and display_team < 0 or not is_instance_valid(head_hp_bar):
		return
	var t := team_id if team_id >= 0 else display_team
	head_hp_bar.color = TEAM_HP_GREEN if t == 0 else TEAM_HP_RED


func _update_head_hp_bar() -> void:
	if not is_instance_valid(head_hp_bar):
		return
	# ⚠ 队伍色必须在这里重申，不能只在 _ready 里上一次色：
	#   `WorldEnemy._setup()` 是在 `super._ready()` **之后**跑的，它又按 `enemy_kind`
	#   把血条刷成核心的橙红 / 野修的蓝 —— 于是对局里四只大陆核心棋子
	#   哪怕属于我方也顶着红色血条（2026-11-03 用户报「血条颜色显示错误」）。
	#   本函数被血量变化、布局、阶段切换各处反复调用，放这里等于自愈。
	_tint_head_hp_bar()
	var ratio: float = clampf(current_hp / max_hp, 0.0, 1.0)
	head_hp_bar.offset_left = 0.0
	head_hp_bar.offset_right = _head_hp_bar_width() * ratio
	head_hp_bar.offset_top = 0.0
	head_hp_bar.offset_bottom = 8.0

	_layout_head_hud()


## 本体在局部坐标里的最高点（负值）。血条与伤害飘字都以它为基准。
## 读所有可见 Sprite2D / AnimatedSprite2D 的贴图高度 × 实际缩放，
## 所以换体型、换 rig、抬臂都不会再让血条/飘字掉进身体里。
func head_top_y() -> float:
	var top := INF
	var root: Node = get_node_or_null("Visual")
	if root == null:
		root = self
	for n in root.find_children("*", "CanvasItem", true, false):
		var ci := n as CanvasItem
		if ci == null or not ci.is_visible_in_tree():
			continue
		var half := 0.0
		var spr := n as Sprite2D
		if spr != null and spr.texture != null:
			half = float(spr.texture.get_height()) * 0.5   # 未缩放：缩放由 to_global 负责
		else:
			var anim := n as AnimatedSprite2D
			if anim == null or anim.sprite_frames == null:
				continue
			if not anim.sprite_frames.has_animation(anim.animation):
				continue
			# 取**所有帧里最高的一张**：序列帧每帧尺寸不同，按当前帧算会让血条逐帧抖
			var max_h := 0
			for fi in anim.sprite_frames.get_frame_count(anim.animation):
				var t2 := anim.sprite_frames.get_frame_texture(anim.animation, fi)
				if t2 != null:
					max_h = maxi(max_h, t2.get_height())
			if max_h <= 0:
				continue
			half = float(max_h) * 0.5   # 未缩放：缩放由 to_global 负责
		var p := to_local((n as Node2D).to_global(Vector2(0.0, -half)))
		top = minf(top, p.y)
	if top == INF:
		# ⚠ 占位体（未接贴图时 SkinVisual 画的是 ColorRect）既不是 Sprite2D 也不是 AnimatedSprite2D，
		#   上面那圈扫描一个都扫不到 → 以前一律退到写死的 -110，血条与名字会飘在头顶几十像素之外。
		#   肉鸽小怪全是占位体，这个问题才第一次变得刺眼（2026-11-08 截图发现）。
		#   占位时改问皮肤自己的上边界（它按 placeholder_size / anchor_bottom 算得准）。
		if skin != null and is_instance_valid(skin):
			top = skin.top_extent()
		else:
			top = -110.0
	return top


## 血条压在头顶上方 14px（宽度沿用场景里的 HPBarBG 宽度，水平居中）
func _layout_head_hud() -> void:
	if not is_instance_valid(head_hp_bar):
		return
	var bg := head_hp_bar.get_parent() as Control
	if bg == null:
		return
	var w := bg.size.x if bg.size.x > 0.0 else HEAD_HP_BAR_WIDTH
	var y := head_top_y() - 14.0
	bg.offset_left = -w * 0.5
	bg.offset_right = w * 0.5
	bg.offset_top = y
	bg.offset_bottom = y + 8.0


## ===== 受击 / 死亡 / 转阶段（共有机制） =====
## damage_kind: "physical" / "elemental" —— 决定吃物抗还是法抗（+五行抗性）
## 抗性减免统一由 DamageCalc.incoming 处理，与玩家侧共用同一套公式
## from_projectile = true 表示这是**玩家的远程投射物**命中的（player_projectile.gd 传 true）
## ⚠ 近战/扇形/法术结算都是 4 参调用，默认 false，行为完全不变
func take_damage(amount: float, source: Node = null, damage_kind: String = "physical",
		element: String = "", from_projectile: bool = false) -> void:
	if state == BossState.DEAD:
		return
	# 转阶段保护 / 续命灯触发后的短暂无敌：期间忽略伤害
	if phase_transitioning or _treasure_invuln_left > 0.0:
		return
	# ★ 子类可拦截「玩家的物理远程攻击」：刀客二阶段必定完美弹开（本次伤害作废）
	#   只认物理 —— 法术远程（元素飞剑等）不在此列；近战调用 from_projectile=false 也不会进来
	if from_projectile and damage_kind == "physical" and has_method("try_parry_player_projectile"):
		if bool(call("try_parry_player_projectile", source)):
			return
	var mitigated := float(DamageCalc.incoming(amount, self, damage_kind, element).get("amount", amount))
	# 暗属性 → 挂「蚀」（穿抗 + 减疗 90%）。放在减免之后：即使这一击被减到很低，
	# 元素交互照样成立，否则高抗build能顺便免疫整个暗体系。
	if element == AttributeDB.DARK:
		try_dark_erosion()
	# 子类受击倍率（阵旗「守」减伤 / 灾崩与归一易伤）：放在抗性之后，读作"最终伤害再乘一档"。
	# ⚠ 上限不能钳在 1.0：离照的日冕破绽、晏无咎的灾崩/归一都是 >1 的易伤，
	#   旧版 clamp(0,1) 会把它们悄悄吃掉，探针只查函数返回值时完全看不出来。
	var taken_mult := clampf(damage_taken_multiplier(damage_kind), 0.0, 3.0)
	# 蚀甲锥：护体类减伤减半（只削 <1.0 的减伤，易伤破绽不碰）
	var shred := debuff_guard_shred()
	if shred > 0.0:
		taken_mult = DamageCalc.apply_guard_shred(taken_mult, shred)
	if not is_equal_approx(taken_mult, 1.0):
		mitigated *= taken_mult
	# 玩家挂的减益（感电 / 灾崩）也要在 BOSS 端生效：DebuffDB.damage_taken_mult
	# 之前只在玩家 take_damage 里读过，BOSS 端完全没接，感电等于白挂。
	var debuff_mult := debuff_damage_taken_mult()
	if not is_equal_approx(debuff_mult, 1.0):
		mitigated *= debuff_mult
	# 续命灯：子类（野修）在这里把致死伤害改成「留 1 点气血」
	mitigated = _adjust_lethal_damage(mitigated)
	# 伤害统计（2026-11-12）：记**减免之后实际掉的血**；最后一刀按剩余血量截断，
	# 不让溢出的过量伤害算进输出（不然收尾一刀会虚高几万）
	DamageMeter.record(minf(mitigated, current_hp))
	current_hp = maxf(0.0, current_hp - mitigated)
	health_changed.emit(current_hp, max_hp)
	_update_head_hp_bar()
	# ★ 飘字紧跟扣血，放在所有子类钩子之前：
	#   定阵先生这类「阵旗/守阵」会在 after_damage_taken 里做拦截与结算，
	#   钩子一旦提前 return 或抛错，排在它后面的飘字就永远出不来（2026-10-28 实机反馈）。
	#   这里飘的是扣抗性后的实际掉血；被完全减免时至少飘一个 0，让玩家知道打到了但被挡。
	DamageNumber.spawn(get_parent(), global_position + Vector2(0.0, head_top_y() - 6.0),
		maxf(mitigated, 0.0), DamageNumber.kind_from_damage_kind(damage_kind))
	# 子类结算后钩子（化劲蓄伤 / 吐纳打断这类需要"实际掉了多少"的机制）
	after_damage_taken(mitigated)
	# 仇恨：按**实际扣掉的血**给来源记账（无敌帧已经提前 return，不会记空账）
	_register_damage_threat(source, mitigated)
	# 战报：同一笔数字再记到"打出来的那只棋子"的招式行上（只对棋局棋子生效）
	_register_damage_report(source, mitigated)
	# 棘甲佩：近战物理受击时把一部分伤害真实反弹给攻击者
	var thorns := _reflect_thorns(mitigated, source, damage_kind, from_projectile)
	if thorns > 0.0 and source != null and is_instance_valid(source) \
			and source.has_method("take_true_damage"):
		source.call("take_true_damage", thorns, self)
	_play_hit_reaction(source)
	# 受击顿帧：命中瞬间短暂停顿，制造打击分量感
	GameState.trigger_hit_stop()

	# 阶段切换
	if phase == 1 and current_hp <= max_hp * PHASE_TRIGGER_RATIO:
		_enter_phase_two()

	if current_hp <= 0.0:
		_die()


## 子类可覆写：受击倍率（1.0 = 不减免；0.5 = 只吃一半；1.15 = 易伤）。默认 1.0
func damage_taken_multiplier(_damage_kind: String) -> float:
	return 1.0


## 当前身上减益里最高的「受伤倍率」（DebuffDB.damage_taken_mult，取最大值不叠乘）。
func debuff_damage_taken_mult() -> float:
	var m := 1.0
	for id in debuffs.keys():
		m = maxf(m, float(DebuffDB.get_debuff(String(id)).get("damage_taken_mult", 1.0)))
	return m


## 子类可覆写：扣血之后的钩子（拿到的是**减免后**的实际伤害）。默认空实现
func after_damage_taken(_amount: float) -> void:
	pass


## 受击反馈：闪白 + 2px 回弹。只看视觉，不动碰撞/受击球/本体坐标。
## 回弹方向 = 从伤害来源指向自己；打点越贴身越明显，远程也成立。
func _play_hit_reaction(source: Node) -> void:
	if skin != null:
		if _hit_flash_tween != null and _hit_flash_tween.is_valid():
			_hit_flash_tween.kill()
		skin.modulate = HIT_FLASH_COLOR
		_hit_flash_tween = create_tween()
		_hit_flash_tween.tween_property(skin, "modulate", Color.WHITE, 0.10)

	if anim == null:
		return
	if not _visual_rest_ready:
		_visual_rest = anim.position
		_visual_rest_ready = true
	var dir := Vector2.RIGHT
	if source != null and is_instance_valid(source) and source is Node2D:
		var away: Vector2 = global_position - (source as Node2D).global_position
		if away.length_squared() > 0.0001:
			dir = away.normalized()
	if _hit_recoil_tween != null and _hit_recoil_tween.is_valid():
		_hit_recoil_tween.kill()
	anim.position = _visual_rest
	_hit_recoil_tween = create_tween()
	_hit_recoil_tween.tween_property(anim, "position", _visual_rest + dir * HIT_RECOIL_PX, 0.03)
	_hit_recoil_tween.tween_property(anim, "position", _visual_rest, 0.11) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _enter_phase_two() -> void:
	phase = 2
	phase_changed.emit(phase)
	GameState.boss_phase_changed.emit(boss_id, phase)
	anim.modulate = Color(1.0, 0.4, 0.4, 1.0)
	_spawn_phase_change_effect()
	state = BossState.IDLE
	state_timer = 0.3
	# 转阶段保护：短暂无敌 + 弹开玩家，让演出完整播完
	_begin_phase_transition()
	_on_phase_two()


## 转阶段保护：进入无敌帧，并把玩家向外推开
func _begin_phase_transition() -> void:
	phase_transitioning = true
	if target != null and is_instance_valid(target) and target.has_method("take_knockback"):
		var away := (target.global_position - global_position).normalized()
		target.take_knockback(away * PHASE_TRANSITION_PUSH)
	# 无敌帧结束后恢复
	var timer := get_tree().create_timer(PHASE_TRANSITION_TIME)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self):
			phase_transitioning = false
	)


## 子类钩子：进入二阶段后的额外处理（如技能强化）
func _on_phase_two() -> void:
	pass


## 转阶段能量聚集特效（共有机制）
func _spawn_phase_change_effect() -> void:
	# 四周能量球向心聚集（外观走 ArtDB.EFFECTS 的 "fx_phase_gather"，换美术只改表）
	FxPlayer.spawn(self, "fx_phase_gather")

	# 本体闪红 / 弹跳：操作的是自身 Visual 节点，不属于特效绘制，保留在此
	var body_flash := create_tween()
	body_flash.tween_property(anim, "modulate", Color(1.0, 0.2, 0.2, 1.0), 0.1)
	body_flash.tween_property(anim, "modulate", Color(1.0, 0.4, 0.4, 1.0), 0.2)
	# 只改脉动，朝向由 _update_skin_motion 合成 —— 写死 Vector2.ONE 会把朝向抹成朝右
	_tween_pulse(1.3, 0.15)
	_pulse_tween.tween_property(self, "_pulse", 1.0, 0.3)


## 弹刀成功：进入僵直（共有机制，攻击反馈非韧性/破防系统）
func on_parried(source: Node) -> void:
	if state == BossState.DEAD:
		return
	state = BossState.STAGGER
	state_timer = STAGGER_TIME
	velocity = Vector2.ZERO
	_flash_attack(Color(1.0, 1.0, 0.3))
	# 踉跄位移：被格开后沿"来源指向自己"方向后退一小段，强化"被格开"感
	# ⚠ 先 is_instance_valid 再 `is`：对已释放实例用 `is` 会报 freed 错误（顺序不能反）
	if source != null and is_instance_valid(source) and source is Node2D:
		var back := (global_position - (source as Node2D).global_position).normalized()
		_bump_back(back * 120.0)


## 踉跄后退：短暂位移（沿指定方向施加一段衰减冲量）
func _bump_back(impulse: Vector2) -> void:
	var start := global_position
	var end := global_position + impulse
	var tween := create_tween()
	tween.tween_property(self, "global_position", end, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _die() -> void:
	# 友军召唤物：只消散，不发 died（否则会被战斗结算当成 BOSS 被击杀）
	if is_ally:
		_expire_summon()
		return
	state = BossState.DEAD
	velocity = Vector2.ZERO
	# 死在半招上也要立刻停手：一次性动作有计时器，不停就会在尸体上继续挥完
	if skin != null:
		skin.cancel_one_shot()
	# ⚠ **立刻关掉碰撞**：尸体只是视觉上缩小淡出，碰撞体若留着就成了一堵「隐形墙」，
	#   而掉落物恰好生成在它旁边 —— 玩家看得见却走不过去（用户报的 bug）。
	#   物理回调中不能直接改 disabled，用 set_deferred。
	collision_layer = 0
	collision_mask = 0
	for cs in find_children("*", "CollisionShape2D", true, false):
		(cs as CollisionShape2D).set_deferred("disabled", true)

	died.emit(boss_id)
	GameState.boss_died.emit(boss_id)
	anim.modulate = Color(0.4, 0.4, 0.4)
	_play_death_animation()


## 死亡消散动画：缩小 + 渐隐 + 迸发粒子碎片
func _play_death_animation() -> void:
	# 主体缩小并渐隐
	var tween := create_tween()
	tween.tween_property(anim, "scale", Vector2(0.1, 0.1), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(anim, "modulate:a", 0.0, 0.5)

	# 迸发碎片粒子（红色小块向四周散落）
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(20):
		var shard := ColorRect.new()
		shard.size = Vector2(6, 6)
		shard.position = Vector2(-3, -3)
		shard.color = Color(0.8, 0.3, 0.3, 0.9)
		shard.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shard)
		var dir := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
		var dist := rng.randf_range(30.0, 90.0)
		var st := shard.create_tween()
		st.tween_property(shard, "position", dir * dist, 0.5)
		st.parallel().tween_property(shard, "modulate:a", 0.0, 0.5)
		st.tween_callback(shard.queue_free)


func is_dead() -> bool:
	return state == BossState.DEAD
