extends CharacterBody2D
## ============================================================================
## 玩家角色（李青云）—— 战斗操作与状态机
## ============================================================================
##
## 【这个文件负责什么】
##   移动、普攻（三段连击）、闪避、弹刀、受击与死亡、功法施放。
##   **数值不在这里算** —— 攻击力/抗性/伤害公式统一走 CharacterData 与 DamageCalc，
##   本文件只负责「什么时候、朝哪个方向、打成什么形状」。
##
## 【阅读顺序（在文件里搜 "# ===== 一、" 这类分节标签）】
##   一、生命周期       _ready 初始化、属性同步
##   二、表现层初始化   低血量泛红、程序合成的占位音效
##   三、帧循环         推进计时器 → 读输入 → 算速度 → 移动
##   四、输入与动作     闪避 / 弹刀 / 攻击 的起手与收招
##   五、普攻与命中判定 普攻与功法共用 _damage_bosses_in_shape
##   六、受击入口       take_damage：弹刀 → 闪避 → 扣抗性
##   七、弹刀系统       可弹性、成功结算、增伤 buff
##   八、反馈表现       飘字、震屏、弹反特效、极限闪避
##   九、掉血与死亡     掉血、精力惩罚、击退、死亡
##   十、HUD 与资源     血条、精力条、灵力条
##   十一、功法施放     消耗校验 → 表现 → 命中结算
##   十二、通用工具     闪烁、朝向、重开
##
## 【改数值前先分清两类】
##   真实数值（攻击力、气血、抗性…）→ 属性系统 CharacterData / 数据表
##   操作手感（窗口时长、后摇、击退力度）→ 本文件顶部各状态旁边的常量
##
## 【美术替换】
##   角色形象走 SkinVisual + ArtDB（visual_id = "player_liqingyun"），
##   刀光/特效走 FxPlayer + ArtDB.EFFECTS，本文件不写死任何贴图与配色。
## ============================================================================

signal health_changed(current: float, max_hp: float)
signal player_died
signal mana_changed(current: float, max_mana: float)
## 功法真正施放成功（扣完消耗、进了冷却）后广播；大世界用它接「猛虎踏地开垦」
signal skill_used(skill_id: String)
## 符纸施法完成（2 秒僵直结束）后广播；BattleWheel 收到后才结算符纸效果与扣道具
signal talisman_cast_finished(item_id: String)

var move_speed: float = 220.0
const DODGE_SPEED := 480.0
const DODGE_TIME := 0.18
const DODGE_COOLDOWN := 0.5

# 极限闪避窗口：闪避开始后这段时间内若被攻击判定为"极限闪避"
# 前 60% 时间（0.18 * 0.6 = 0.108）
const PERFECT_DODGE_WINDOW := 0.108

# 弹刀窗口（按下后的判定时长）与冷却
const PARRY_WINDOW := 0.22
const PARRY_COOLDOWN := 0.6

var max_hp: float = 100.0
## 本场战斗是否真正掉过血（万界塔无伤通关奖励用）
## ⚠ 弹反 / 闪避 / 无敌帧都不算受伤；只有 _apply_damage 实际扣了气血才置 true
var took_damage_this_battle: bool = false

# 精力系统：5 格，弹刀/闪避各扣 1 格、挨打也扣 1 格，随时间缓慢恢复
var max_stamina: int = 5          # 精力格数（整数）
const STAMINA_COST := 1           # 每次弹刀/闪避扣的精力格数
## 受击时扣的精力格数（2026-10-17 用户定：固定扣 1 格，不再按比例减半）
const STAMINA_LOSS_ON_HIT := 1
## 每回满 1 格所需秒数（由属性「精力恢复」换算，入场时写入）
var stamina_regen_seconds: float = 4.0

var hp: float = max_hp
var stamina: int = max_stamina      # 当前精力格数（整数）
## 本次力竭的总时长（进入力竭时记下）—— 只给灵环精力点阵上那道倒计时光用。
## 不能从 DebuffDB 查：条目里没有 duration，时长是 apply_debuff 的入参。
var _exhaust_total := 1.0
var stamina_regen_timer: float = 0.0  # 恢复计时器
## ⚠ 力竭已并入 debuff 体系（2026-10-23）：状态在 `debuffs["exhausted"]` 里，
##   判定统一走 `is_exhausted()` → `has_debuff("exhausted")`，
##   时长仍由招式表 `player.exhaust_time` 驱动（当前 3 秒），这里不再单独存字段。
var is_dead: bool = false

# ===== 法宝主动使用（2026-10-21 召唤令 / 2026-10-24 凝水佩）=====
## 装备在法宝槽的法宝按 1 / 2 / 3 使用：
##   召唤令 → 唤出 BOSS 友军；凝水佩 → 持续引导回血；逐电环 → 短时加速
## 主动法宝冷却按法宝 id 记（跨战斗保留），不消耗法宝本身
var _summon_cooldowns: Dictionary = {}
## 三个召唤键的上一帧状态（轮询输入做边沿检测，和其它按键同一套写法）
var _summon_key_prev: Array = [false, false, false]
## 凝水佩引导状态：每秒耗灵力回血，最多 duration 秒；灵力不足立即中断
const HEAL_TREASURE_TICK := 1.0
var _heal_treasure_id: String = ""
var _heal_treasure_left: float = 0.0
var _heal_treasure_tick: float = 0.0
var _heal_treasure_heal: float = 0.0
var _heal_treasure_mana: float = 10.0
## 逐电环加速状态：3 秒内移速固定为 800（仍吃减速/重伤倍率）
var _haste_treasure_id: String = ""
var _haste_treasure_left: float = 0.0
var _haste_treasure_speed: float = 0.0
var _haste_treasure_fx: Node2D = null

# 太极盘主动：限时减伤（2026-10-28）+ 接化发（2026-10-29）
var _taiji_guard_id: String = ""
var _taiji_guard_left: float = 0.0
var _taiji_guard_pct: float = 0.0
var _taiji_guard_fx: Node2D = null
## 护体期间敌弹进入这个半径就被接住；绕玩家一周后反打来源
const TAIJI_CAPTURE_RADIUS := 170.0
const TAIJI_ORBIT_TIME := 0.70

# 三元轮主动：风 / 火 / 雷三炁环身，轮转打击周围敌人（2026-10-31 通用化）
var _tri_ring_id: String = ""
var _tri_ring_left: float = 0.0
var _tri_ring_tick: float = 0.0
var _tri_ring_index: int = 0
var _tri_ring_radius: float = 240.0
var _tri_ring_interval: float = 1.0
var _tri_ring_ratio: float = 0.65
var _tri_ring_fx: Node2D = null

# ===== 位面法宝「照影·迟照符」：延迟结算（2026-11-07）=====
## 窗口内本该扣血的伤害记进 _reckoning_pool，不落地；用操作抹账，到期一次结算。
var _reckoning_id: String = ""
var _reckoning_left: float = 0.0
var _reckoning_pool: float = 0.0
var _reckoning_wipes: int = 0
var _reckoning_wipe_pct: float = 0.30
var _reckoning_max_wipes: int = 3

# ===== 位面法宝「凡界·换锋符」：普攻三段改远程穿透剑气（2026-11-07）=====
## 判定长条的射程/宽度从模板现算，不在此硬编码；下面只是兜底初值。
var _blade_form_id: String = ""
var _blade_form_left: float = 0.0
var _blade_form_range: float = 320.0
var _blade_form_width: float = 96.0

# 断念铃目标侧抗性（2026-11-01）：防多只野修连锁封技
var _treasure_bell_immune_left: float = 0.0

# 禁步桩：场上有自己的桩时记录，用于 HUD 倒计时与离场清理
var _stake_id: String = ""
var _stake_left: float = 0.0
var _stake_field: Node2D = null

# 续命灯：点亮窗口 / 触发后的 1 秒回复
var _lamp_id: String = ""
var _lamp_left: float = 0.0
var _lamp_heal_left: float = 0.0
var _lamp_heal_rate: float = 0.0
var _lamp_heal_ratio: float = 0.15
var _lamp_invuln: float = 0.8
var _lamp_knockback: float = 200.0
var _lamp_fx: Node2D = null

# 棘甲佩：近战反伤状态
var _thorns_id: String = ""
var _thorns_left: float = 0.0
var _thorns_ratio: float = 0.0
var _thorns_fx: Node2D = null

# ===== 灵力（功法消耗资源，与精力分离）=====
var mana: float = 0.0
var max_mana: float = 60.0
## 各功法剩余冷却：{ skill_id: 剩余秒数 }
var skill_cooldowns: Dictionary = {}

## 主动功法快捷键：Q / E / R / T 对应第 1~4 个装配位
## （F 仍是拾取，C 是战斗内重开，避免冲突）
const SKILL_KEYS: Array[int] = [KEY_Q, KEY_E, KEY_R, KEY_T]
## 上一帧按键状态，用于做「刚按下」边沿检测
var _skill_key_down: Dictionary = {}

const PLAYER_PROJECTILE_SCENE := "res://scenes/combat/player_projectile.tscn"

# ===== 剑意（玩家侧，2026-10-19 实装；机制对齐 BOSS 剑客 domain_boss_01_c）=====
## 规则（用户定）：
##   - 积攒：释放刺/撩/斩/云 **仅释放 +1**（命中不叠加）；数值在招式表 player.intent_gain
##   - 衰减：**受到一次攻击 -1 层**（真掉血才算；弹反/闪避的无敌不扣）
##   - 大招：万剑归宗 = 2 + 剑意×2 把、一剑开天满层切换法术矩形巨斩，放完都清空
##   - 被动「剑心通明」：佩戴后每层剑意 +8% 物理功法伤害，且所有物理近战功法释放时也积攒 1 层
##   - 反馈：不出层数 HUD，靠「积攒特效 + 大招图标剑气环绕」表达（见 combat_arena.gd）
var sword_intent: int = 0
## 剑意上限：基值在 RogueDB.CAP_BASE，肉鸽增益可 +N；主模式恒为 5
## ⚠ 一剑开天的「满层」展示口径走 MoveDB.resolve_player 的 intent_full_at，
##   那边由 RogueRun.apply_form_mods() 同步成同一个数，不要另写一份。
func _sword_intent_max() -> int:
	return RogueRun.cap("sword_intent_max")

# ===== 肉鸽爬塔「试炼之路」运行时挂钩（主模式恒为空转）=====
## 逆鳞：受击后 2 秒内伤害提高，剩余秒数
var _rogue_scale_left := 0.0
## 踏影：闪避后下一击提高（一次性，命中即消费）
var _rogue_step_ready := false
## 以意御法：本次施法预借的剑意层数 / 灵力（施法成功才真正扣层）
var _rogue_borrowed_stacks := 0
var _rogue_borrowed_mana := 0.0
## 最近一次造成伤害的功法 id（击杀时判「万剑 / 开天 击杀返还剑意」）
var _rogue_last_hit_skill := ""
## 换镜·锐：换位后的增伤窗口（秒）
var _rogue_mirror_swap_left := 0.0
## 受击减少的剑意层数（用户原话：「受到一次攻击就减少一层剑意」）
const SWORD_INTENT_LOSS_ON_HIT := 1
## 万剑归宗：基础飞剑数 / 每层剑意追加（镜像 BOSS 侧同名常量）
const MYRIAD_BASE_COUNT := 2
const MYRIAD_PER_INTENT := 2
## 万剑归宗逐把发射间隔（秒）、身侧偏航角（度）、弧线转向速度（度/秒）
const MYRIAD_INTERVAL := 0.09
const MYRIAD_SIDE_ANGLE := 65.0
const MYRIAD_TURN_SPEED := 200.0
## 万剑归宗功法 id（_spawn_skill_projectiles 靠 intent_count_scale 识别，这里只作伤害追溯）
const SKILL_SWORD_MYRIAD := "skill_sword_myriad"

# ===== 两仪势（两仪真人功法体系，2026-10-27）=====
## 只有学会任意一门带 `yinyang` 标记的功法才会激活；第一战打两仪真人时没有这门功法，
## 所以势条不显示、也不参与任何计算 —— 这是「打完 BOSS 后才解锁的奖励层」。
## 规则：物理 = 阳，法术 = 阴；与当前仪态相反 = 逆式，+20% 伤害、+1 势、翻面。
const YINYANG_YANG := 0
const YINYANG_YIN := 1
# ⚠ 数值口径全部来自 SkillDB 的「两仪势」常量：战斗结算与功法库 / 图鉴的文案
#   读同一批数字，改了不会只改到一边（以前锁在这里，面板只能手抄，一抄就漂）
## 阴阳势上限：基值在 RogueDB.CAP_BASE，肉鸽增益可 +N；主模式恒为 3
func _yinyang_max() -> int:
	return RogueRun.cap("yinyang_max")
const YINYANG_REVERSE_BONUS := SkillDB.YINYANG_REVERSE_BONUS
const YINYANG_STACK_BONUS := SkillDB.YINYANG_STACK_BONUS
const YINYANG_MARK_BONUS := SkillDB.YINYANG_MARK_BONUS
const YINYANG_MARK_SECONDS := SkillDB.YINYANG_MARK_SECONDS
var yinyang_polarity: int = YINYANG_YANG
var yinyang_stacks: int = 0
var _yinyang_unlocked: bool = false
var _yinyang_pips: MechanicPips = null
# 头顶机制徽记带的预留位（宽 / 高 / 顶边 Y）：两行高，新机制往上排队
const MECH_HUD_W := 128.0
const MECH_HUD_H := 36.0
const MECH_HUD_TOP := -110.0
var _mech_hud: VBoxContainer = null
var _collapse_stacks: int = 0

# ===== 减速（被招式/刀痕命中时施加）=====
var _slow_timer: float = 0.0
var _slow_ratio: float = 0.0

# ===== 负面状态 debuff（2026-10-23）=====
## id -> 剩余秒数。定义见 DebuffDB，招式表里用 debuff_on_hit / debuff_time 触发。
## ⚠ 效果**每帧现查**（debuff_move_mult() / is_dodge_blocked()），
##   不在施加时改 move_speed 或锁状态 —— 否则计时一结束还得逐个还原，必然漏。
## 负面状态 debuff：id -> 剩余秒数。定义见 DebuffDB。
var debuffs: Dictionary = {}
## DoT 跳伤计时（阴蚀 / 点燃等）；与 debuffs 分开存，避免把「剩余持续时间」和「下一跳时间」混在一起
var _debuff_dot_timers: Dictionary = {}
## 暗属性「蚀」的刷新锁：>0 期间再中暗招不续杯（见 AttributeDB.DARK_EROSION_REFRESH_CD）。
## 与 BOSS 侧同一条规则、同一个数 —— 暗是通用属性，两边的约束必须对称。
var dark_erosion_lock := 0.0

# ===== 增益状态 buff（2026-10-23）=====
## id -> { "left": 剩余秒, "count": 剩余次数 }
##   · 时间型（BuffDB.count_based = false）：left 倒计时，到 0 自动移除
##   · 次数型（count_based = true）：count 计次，被消耗到 0 时移除
## 定义与绿色配色都在 BuffDB；HUD 在**第一个法宝格上方**列出，与 debuff 对称。
var buffs: Dictionary = {}

## 玩家刀痕的伤害系数（× 留痕技能的攻/法攻击力；物理留痕＝物攻，法术留痕＝法强）—— 与 BOSS 的系数分开配
## 玩家刀痕的伤害系数（× 物理攻击力）
## 2026-10-18 改版后基础值为 1.0：实际系数 = 本值 × 本次激活的刀痕数量。
const SCAR_PLAYER_DAMAGE_COEFF := 1.0

# 闪避状态
var is_dodging: bool = false
var dodge_timer: float = 0.0
var dodge_cooldown_timer: float = 0.0
var _dodge_dir: Vector2 = Vector2.ZERO

# 技能前冲状态（招式表里的 move_forward：施法时朝技能方向小位移）
# 典型用途是「破步突进斩」这类突进技 —— 没有它，玩家放突进斩只会原地砍。
# 与弹反追击（_parry_followup_dash）互斥：那段用 tween 直接改坐标，两段叠在一起会送过头。
var _skill_dash_timer: float = 0.0
var _skill_dash_dir: Vector2 = Vector2.ZERO
var _skill_dash_speed: float = 0.0
## 本段前冲的起点：突进斩穿过目标后，判定帧也要能用起手位置补一次命中
var _skill_dash_origin: Vector2 = Vector2.INF
## 施法朝向锁：剩余秒数 > 0 时 `_update_visual` 不再按移动输入翻面。
## 破步突进斩在前摇里就已经朝技能方向冲了，而技能方向是软锁定 BOSS 的 ——
## 这时只要按住反方向的键，人物就会边前冲边背对目标（用户 2026-10-26 报的「前摇期间素材还是反的」）。
var _skill_face_lock: float = 0.0

# ===== 弹刀 / 弹反状态 =====
## 是否正在弹刀判定窗口内
var is_parrying: bool = false
## 当前弹刀窗口的剩余时间（>0 表示还能挡）
var parry_timer: float = 0.0
## 弹刀冷却剩余时间（冷却中按不出来，避免无脑连按）
var parry_cooldown_timer: float = 0.0
## 完美弹反的**定身**剩余时间：普通弹刀零前摇（按下即判定），
## 只有完美弹反才有这 0.2 秒站定，期间禁止移动与一切操作
var parry_stance_timer: float = 0.0
const PARRY_STANCE_TIME := 0.2

## 弹刀成功后的「追击位移」窗口时长（秒），每次弹刀成功都会重新计满
## ⚠ 这个窗口只服务「追击位移」，不是弹刀判定窗口。
##    「按下后连续自动再弹」已于 2026-10-17 取消；
##    不按键的「自动弹刀」是另一套机制（2026-10-19 加入并保留，见下方 AUTO_PARRY_WINDOW）。
const PARRY_FOLLOWUP_WINDOW := 1.2
## ⚠ 窗口状态已并入 buff 体系（2026-10-23）：`buffs["parry_followup"]`，
##   判定走 `has_buff("parry_followup")`，HUD 会在法宝栏上方显示「追击 1.2s」。
##   （原来的 parry_followup_active / parry_followup_timer 两个字段已删）
## 追击位移资格：完美弹反 / 自动弹刀能拿到，用掉即失效
## ⚠ 它只表示"这次弹刀拿到了资格"，**是否还在窗口内**看 has_buff("parry_followup")，
##   所以不需要跟着倒计时清零（buff 一过期，两者的「与」自然是 false）
var parry_followup_can_dash: bool = false

## ===== 自动弹刀（守势窗口）=====
## 完美弹刀后开启：窗口内**站着不动、也不主动攻击**，受到可弹攻击时自动弹开，不限次数。
## 这是「完美弹反」的额外奖励 —— 玩家选择站桩防守，就能白嫖后续连击；
## 自动弹刀**不消耗精力**，0 精力也能继续弹。
## ⚠ 与 2026-10-17 取消的「连续弹刀」不同：那个是按下弹刀键后自动再按，
##   这个是**不按键**也能弹，且只在完美弹刀后的短窗口内成立。
const AUTO_PARRY_WINDOW := 1.2
## 自动弹刀窗口剩余秒数（>0 才可能触发自动弹刀）
var auto_parry_timer: float = 0.0

## 次数型增伤 buff：弹刀成功后，**下一次近战伤害 ×1.5**，命中后消费，不累计。
## 倍率本体在 ItemDB.PARRY_DAMAGE_BUFF_COEFF，这里只记「有没有」。
## ⚠ 用户 2026-10-17 定：这个 buff **不做任何视觉表现**（不要角色光环），只体现在伤害上。
## ⚠ 弹刀增伤已并入 buff 体系（2026-10-23）：状态在 `buffs["parry_power"]`，
##   判定统一走 `has_buff("parry_power")`。

# 极限闪避增幅状态（阶段1基础：记录触发，阶段2接入功法前摇/伤害增幅）
## ===== 纳势反击（蓄力格挡型功法）=====
## 蓄力期间：移动锁死、伤害按 charge_block 削减、每次受击 +1 伤害系数；
## 左键提前斩出，或蓄满 charge_max 秒自动斩出。
var _counter_charging: bool = false
var _counter_skill: String = ""
var _counter_form: Dictionary = {}
var _counter_charge: float = 0.0      # 已蓄力秒数
var _counter_hits: int = 0            # 蓄力期间受到的伤害次数
var _counter_max: float = 5.0
var _counter_block: float = 0.7
## 两仪·倒悬：守势判定不走 charge_block，改成「同色奉还 / 异色破势」
var _counter_yinyang_ward: bool = false
## 纳势反击的可视护势（SkillFx 创建；释放/取消时 finish）
var _counter_ward: CounterWardFx = null

## ⚠ 「极限闪避增幅」这个 buff 已整体删除（2026-10-23 用户拍板）：
##   它从来没有被任何逻辑读取过（只写不读，是个空壳），
##   还因为弹刀成功也调用了同一个字段，导致 HUD 上「弹刀成功 → 冒出极限闪避」的错乱。
##   极限闪避本身的收益（回 2 格精力 / 子弹时间 / 蓝特效）都在 _trigger_perfect_dodge() 里直接给，
##   不依赖任何 buff。

# 攻击状态
var is_attacking: bool = false
var attack_timer: float = 0.0
var attack_time: float = 0.35
## 攻击范围与招式倍率（伤害相关常量已迁到数据表，见 ItemDB / CharacterData）
const ATTACK_RANGE := 46.0

## 平A「近距离吸附」（2026-11-10 用户：贴着敌人却砍空，要自动补到能打到的位置）。
## 2026-11-11 改版：按**落空原因**分治 —— 角度不对只转向、人一步不动；只有距离真的
## 不够才补位，且只补到「刚好进判定」。旧口径不看原因、一律走到固定站位，于是段 3
## 刺击（半角 35°，段 1/2 是 89.5°）贴身循环时每三段白扑一次脸 —— 那是玩家报的
## 「明明砍得到却吸到 BOSS 面前」。
const MELEE_SNAP_TIME := 0.12
## 落点余量：命中条件是「距球心 ≤ reach + 该球半径」，贴着边站会被挤出去。
## 20 = 玩家胶囊半径 12 + 这 0.12s 里 BOSS 常规追近的约 10px（P2 移速 85）。
const MELEE_SNAP_MARGIN := 20.0
## 平A 单次补位的位移上限：60px / 0.12s = 500px/s，与闪避 480 同档，是「补一步」不是冲锋。
## ⚠ 弹反追击**不吃这条** —— 它消耗完美弹反给的一次性资格，追远正是奖励本身。
const MELEE_SNAP_MAX_STEP := 60.0
## 落点离 BOSS 身体的最小间距（玩家胶囊半径，见 player.tscn 的 CapsuleShape2D_player）：
## 再近就钻进碰撞体、被 move_and_slide 弹开，落点当场作废。
const PLAYER_BODY_RADIUS := 12.0
var _melee_snapped := false           ## 本次平A是否真的补了位（探针 / 调试用）
var _melee_turned := false            ## 本次平A是否「只转向没位移」（探针 / 调试用）
## 本次吸附锁定的目标（只存 instance_id：存节点会在目标先释放时刷
## "Lambda capture at index 0 was freed"，探针清场必现）。落地再校验要用。
var _snap_target_id := 0
## 本次吸附的滑步 tween。⚠ 再校验前必须先 kill 它 —— 见 _melee_snap_recheck。
var _snap_tween: Tween = null

var attack_dir: Vector2 = Vector2.RIGHT
var attack_combo: int = 0  # 攻击连击计数：0/1/2 对应"来/回/终结"，循环
const ATTACK_COMBO_MAX := 3  # 三段连击
const FINISHER_RANGE_MULT := 1.4   # 终结技范围倍率
const FINISHER_TIME := 0.5         # 终结技更长后摇
var attack_cancel_available: bool = false  # 攻击后摇阶段可被闪避/弹刀取消
## 普攻出伤计时（秒）：<0 = 没有待结算的普攻。
## 为什么不在起手那帧结算：刀锋真正扫到正前方要 0.09~0.18 秒，
## 提前扣血会让「先掉血、后看到刀」，顿帧也冻在刀还没动的时候（2026-10-27 手感调整）。
var _attack_hit_timer: float = -1.0
const ATTACK_CANCEL_RATIO := 0.5  # 攻击进行到 50% 后进入可取消后摇
var is_finisher_attack: bool = false  # 当前攻击是否为终结技（第三段）
## 本次攻击的段号（0/1/2），出伤时用来取推镜幅度
var _attack_seg_idx := 0

# ===== 传送登场（2026-10-24）=====
## 进副本 / 回主城时，角色由小放大淡入并锁操作约 0.75 秒
const TELEPORT_ARRIVAL_TIME := 0.75
var is_teleporting: bool = false

# ===== 符纸施法（2026-10-24 用户定）=====
## 使用符纸 = 原地施法 2 秒：期间不能移动 / 攻击 / 弹刀 / 闪避 / 用功法 / 召唤法宝。
## 效果在施法**完成**后由 BattleWheel 结算；死亡会中断施法且不消耗符纸。
## 施法动作优先用 "cast" 动画，素材里没有就退回 "attack"（现有 41 帧正好是引火施法姿态）。
const TALISMAN_CAST_TIME := 2.0
var is_casting_talisman: bool = false
var _talisman_cast_left: float = 0.0
var _talisman_cast_item: String = ""

# 受击无敌（受击后短暂无敌避免连击秒杀；缩短到 0.3s 让连续被击更有压迫感）
## 闪避 / 弹反 / 无敌帧躲掉的那一下：短窗口内拒绝同一击附带的 debuff。
## 很多 BOSS 是「先 deal_damage_to，再 apply_debuff」，伤害被无敌帧吞掉后 debuff 仍会落地。
const DEBUFF_NEGATE_WINDOW := 0.10
var _hit_negated_timer: float = 0.0
var invincible_timer: float = 0.0
const INVINCIBLE_TIME := 0.3

# 受击击退：受击瞬间被推开，短暂减速衰减
var knockback_velocity: Vector2 = Vector2.ZERO
const KNOCKBACK_DECAY := 12.0  # 击退速度每秒衰减系数
const KNOCKBACK_MELEE := 320.0      # 近战击退力度（大）
const KNOCKBACK_PROJECTILE := 140.0 # 物理投掷击退力度（小）
const KNOCKBACK_ELEMENTAL := 120.0  # 元素法球击退力度（小）
const PARRY_KNOCKBACK := 180.0      # 格挡成功后的自身击退力度（完美格挡不击退）

# 低血量反馈
const LOW_HP_RATIO := 0.3  # 血量低于 30% 触发警示
const VIGNETTE_SHADER := "res://assets/shaders/low_hp_vignette.gdshader"
var _vignette: ColorRect = null
var _vignette_mat: ShaderMaterial = null

# 闪烁令牌：每次闪烁自增，用于避免多次闪烁互相覆盖
var _flash_token: int = 0

@onready var anim: Node2D = $Visual
## Visual 下的 SkinVisual 子节点（用于控制行走动画的播放/暂停）
## 用 get_node_or_null：万一场景结构变了也不至于整个脚本失效，只是动画不受控
@onready var skin: SkinVisual = get_node_or_null("Visual/Skin") as SkinVisual
## 御剑武器：常驻悬浮 + 攻击扫弧。没在 ArtDB 配贴图时为 null（零开销）
var weapon: WeaponOrbit = null
@onready var attack_hitbox: Area2D = $AttackHitbox
## 三才灵环：气血 / 灵力 / 精力 的随身读数，人物脚前三层同心柔光弧 + 一排精力点。
## ⚠ 取代原来的 `HealthBar/Fill`、`ManaBar/Fill`、`StaminaBar` 三组 ColorRect
##   （头顶两条平色横条 + 体侧 5 根白色竖条，互不成体系）。节点由代码建，
##   不进 .tscn —— 它没有任何贴图依赖，换外观只改 scripts/ui/resource_ring.gd。
var _ring: ResourceRing = null
@onready var camera: Camera2D = $Camera2D

# 屏幕震动状态
var _shake_timer: float = 0.0
var _shake_duration: float = 0.0
var _shake_intensity: float = 0.0
var _camera_base_offset: Vector2 = Vector2.ZERO

# 音效播放器 + 程序生成的音效（占位，正式阶段替换为音频资源）
var _audio_player: AudioStreamPlayer
var _parry_sound: AudioStreamWAV          # 普通弹刀
var _perfect_parry_sound: AudioStreamWAV  # 完美弹刀（更亮）
var _dodge_sound: AudioStreamWAV          # 普通闪避（轻）
var _perfect_dodge_sound: AudioStreamWAV  # 完美闪避（更亮）



# ===== 一、生命周期：初始化 / 属性同步 =====
func _ready() -> void:
	# 加入 player 组：掉落物（item_pickup）靠它判断"玩家是否走进拾取范围"
	add_to_group("player")
	# 敌方 BOSS 的阵线挡玩家；玩家自己的线不在自己的掩码里，可自由穿行
	collision_mask |= ArrayFlag.LINE_LAYER_BOSS
	# 全部战斗数值从属性层读取（力量→物理攻击、攻速→攻击间隔…）
	_apply_attributes_to_runtime(true)
	skill_cooldowns.clear()
	_ensure_ring()
	_update_health_bar()
	_update_stamina_bar()
	_update_mana_bar()
	if camera:
		_camera_base_offset = camera.offset
	_setup_audio()
	_setup_vignette()
	_setup_weapon()
	# 两仪势：只有已学会两仪功法时才激活；第一战两仪真人时是隐藏的
	yinyang_polarity = YINYANG_YANG
	yinyang_stacks = 0
	sun_stacks = 0
	_sun_seed = null
	_reset_sun_nova()
	_refresh_yinyang_unlock()
	_ensure_mechanic_hud()
	_refresh_thunder_unlock()
	_ensure_thunder_hud()
	CharacterData.sun_damage_mult = 1.0
	_sync_sword_intent_skill_mult()
	_refresh_sun_unlock()
	_ensure_sun_hud()
	if _sun_bearer_equipped():
		_sun_bearer_respawn_left = SUN_BEARER_FIRST_DELAY
	_refresh_calamity_unlock()
	_ensure_calamity_hud()
	# 登场演出延迟到父场景摆好出生点之后再播（_ready 比父场景早）
	is_teleporting = true
	invincible_timer = maxf(invincible_timer, TELEPORT_ARRIVAL_TIME + 0.15)
	TeleportArrival.prepare(anim)
	call_deferred("_begin_teleport_arrival")


func _exit_tree() -> void:
	_reckoning_reset()
	_stop_blade_form()
	# 五旗阵攻击乘区挂在全局 CharacterData 上，离场必须还原，避免带进下一场
	CharacterData.array_zone_attack_mult = 1.0
	# 日冕 / 三灾属性修正同样挂在全局，离场必须撤掉
	_clear_sun_crown()
	_reset_sun_nova()
	CharacterData.sun_damage_mult = 1.0
	CharacterData.sword_intent_skill_mult = 1.0
	CharacterData.clear_attribute_mod("calamity_element")
	remove_buff("sanzai_guard")
	# 旗与线挂在父场景下；玩家离场时一并清掉，避免留下无主阵线
	_clear_array_flags()
	_clear_player_law()


func _begin_teleport_arrival() -> void:
	# 等两帧：让父场景完成摆位 / 首帧资源加载，否则重演出可能在第一帧就被吃掉
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	TeleportArrival.play(self, anim, _body_center(), TELEPORT_ARRIVAL_TIME,
		func() -> void: is_teleporting = false)


## 统一的属性读取入口（与 CharacterData.attribute / BossBase.attribute 同名）
## 让 DamageCalc 算「玩家受击减免」时不必特判对象类型
func attribute(attr_id: String) -> float:
	return CharacterData.attribute(attr_id)


## 单独元素抗性接口（DamageCalc 使用）
func element_resist(element: String) -> float:
	return CharacterData.element_resist(element)


## 把 CharacterData 的属性同步到本节点的运行时字段
## refill = true 时同时把当前值补满（入场 / 重开）
func _apply_attributes_to_runtime(refill: bool) -> void:
	max_hp = CharacterData.max_hp()
	max_stamina = CharacterData.max_stamina()
	move_speed = CharacterData.move_speed()
	attack_time = CharacterData.attack_interval()
	max_mana = CharacterData.max_mana()
	stamina_regen_seconds = CharacterData.stamina_regen_seconds()
	if refill:
		hp = max_hp
		stamina = max_stamina
		mana = max_mana
	else:
		hp = minf(hp, max_hp)
		stamina = mini(stamina, max_stamina)
		mana = minf(mana, max_mana)


## 初始化音效：程序生成普通/完美弹刀 + 普通/完美闪避四类音效（占位音频）
func _setup_audio() -> void:
	_audio_player = AudioStreamPlayer.new()
	_audio_player.volume_db = -6.0
	add_child(_audio_player)
	# 普通弹刀：低一点、短一点；完美弹刀：更高更亮、拖得更长
	_parry_sound = _make_metal_sound(0.18, 30.0, 2200.0, 3300.0, 1500.0, 0.08, 12345)
	_perfect_parry_sound = _make_metal_sound(0.24, 25.0, 3000.0, 4500.0, 2100.0, 0.06, 54321)
	_dodge_sound = _make_whoosh_sound(false)
	_perfect_dodge_sound = _make_whoosh_sound(true)


## 低血量屏幕泛红：全屏 shader 红晕（软边 + 越靠近 0 血越浓 + 缓慢脉动）
##
## ⚠ 2026-10-27 换掉原来「四条 60px 红色直边」的做法：硬边矩形贴在水墨画面上像 UI 框，
##   而且尺寸是建的时候量一次视口，窗口比例一变就错位。全用 UV 算，任何分辨率都对。
func _setup_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20  # 置于 UI 之上
	add_child(layer)
	_vignette = ColorRect.new()
	_vignette.name = "LowHpVignette"
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_mat = ShaderMaterial.new()
	if ResourceLoader.exists(VIGNETTE_SHADER):
		_vignette_mat.shader = load(VIGNETTE_SHADER)
	_vignette.material = _vignette_mat
	layer.add_child(_vignette)
	_update_vignette()


## 更新低血量泛红：血量越低浓度越高，脉动也跟着加快（心跳感）
func _update_vignette() -> void:
	if _vignette_mat == null:
		return
	var ratio: float = clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	var t := 0.0
	var danger := 0.0
	if ratio < LOW_HP_RATIO:
		t = (LOW_HP_RATIO - ratio) / LOW_HP_RATIO
		# 一跌破阈值就有一层看得见的红（0.42），再线性加浓到 0 血拉满。
		# 不能从 0 开始：血 29% 和 31% 看不出区别的话，这个警示等于没有。
		danger = 0.42 + 0.58 * t
	_vignette_mat.set_shader_parameter("danger", danger)
	_vignette_mat.set_shader_parameter("pulse_hz", lerpf(0.8, 1.7, t))
	# 满血时整层隐藏：这是一张全屏半透明 quad，留着会白跑一遍全屏混合
	_vignette.visible = danger > 0.0


## ===================== 占位音效（程序合成）=====================
## 正式阶段应替换成音频资源；现在用代码合成，只求「有声、能区分」。
## 两个合成器覆盖四种音效：金属撞击（普通 / 完美弹刀）、破风（普通 / 完美闪避）。

## 生成一段「金属撞击」声：三个高频正弦叠加 + 指数衰减 + 少量噪声
##   duration / decay : 时长（秒）与衰减系数（越大衰减越快）
##   f1 / f2 / f3     : 三个正弦分量的频率（Hz）
##   noise            : 噪声幅度，用来模拟撞击质感
##   seed_value       : 随机种子，固定后每次音色一致
func _make_metal_sound(duration: float, decay: float, f1: float, f2: float, f3: float,
		noise: float, seed_value: int) -> AudioStreamWAV:
	var sample_rate := 22050
	var sample_count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)  # 16-bit 单声道：每个采样占 2 字节

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(sample_count):
		var t := float(i) / sample_rate
		var env := exp(-t * decay)  # 瞬时起音 + 指数衰减
		var sample := sin(TAU * f1 * t) * 0.6 + sin(TAU * f2 * t) * 0.3 + sin(TAU * f3 * t) * 0.2
		sample += rng.randf_range(-noise, noise)
		sample *= env
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))

	return _wrap_wav(data, sample_rate)


## 生成一段「破风」声：频率由低向上滑，普通闪避偏闷、完美闪避更亮更高
func _make_whoosh_sound(is_perfect: bool) -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.22
	var sample_count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	var base_freq := 1400.0 if is_perfect else 700.0
	var sweep := 2600.0 if is_perfect else 1500.0
	var amp := 0.75 if is_perfect else 0.5
	var decay := 16.0 if is_perfect else 22.0

	for i in range(sample_count):
		var t := float(i) / sample_rate
		var env := exp(-t * decay)
		var freq := base_freq + sweep * (t / duration)
		var phase := TAU * freq * t
		var sample := sin(phase) * amp + sin(phase * 1.5) * (0.2 if is_perfect else 0.1)
		sample *= env
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))

	return _wrap_wav(data, sample_rate)


## 把 16-bit 单声道采样数据包装成 AudioStreamWAV（两个合成器共用）
func _wrap_wav(data: PackedByteArray, sample_rate: int) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = data
	return wav


## 播放一段音效；音效流为空时静默跳过（不报错、不打断游戏）
func _play_sfx(stream: AudioStreamWAV) -> void:
	if _audio_player != null and stream != null:
		_audio_player.stream = stream
		_audio_player.play()



# ===== 三、帧循环：推进计时器 → 读输入 → 移动 =====
## 每个物理帧：先推进所有计时器，再读输入，最后算速度并移动。
## 移动优先级：攻击中 → 站定；闪避中 → 按闪避方向冲；弹刀/定身中 → 站定；其余按方向走。
func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	_handle_action_input()
	_tick_counter_charge(delta)
	_tick_screen_shake(delta)

	if is_dead:
		return

	var move_dir := _get_move_dir()

	if is_casting_talisman:
		# 符纸施法：原地僵直，移动 / 攻击全部锁死
		velocity = Vector2.ZERO
	elif is_teleporting:
		velocity = Vector2.ZERO
	elif is_attacking or _counter_charging:
		# 纳势反击：蓄力格挡期间原地不动（must stand still）
		velocity = Vector2.ZERO
	elif is_dodging:
		velocity = _dodge_dir * DODGE_SPEED * _dodge_distance_mult()
	elif _skill_dash_timer > 0.0:
		# 技能前冲（破步突进斩等）：突进期间锁死普通移动，速度由前冲自己给
		velocity = _skill_dash_dir * _skill_dash_speed
	elif is_parrying or parry_stance_timer > 0.0:
		# 弹刀必须站定释放：普通弹刀零前摇，按下即判定且移动被锁死；
		# 完美弹反额外有 PARRY_STANCE_TIME 的定身演出
		velocity = Vector2.ZERO
	else:
		# 移速乘区：逐电环覆盖基础移速，再乘招式减速与 debuff 倍率
		var base_speed := _haste_treasure_speed if _haste_treasure_left > 0.0 else move_speed
		base_speed *= _rogue_move_mult()
		velocity = move_dir * base_speed * (1.0 - _slow_ratio) * debuff_move_mult()
		if move_dir.length_squared() > 0.0:
			attack_dir = move_dir.normalized()

	# 叠加受击击退速度（持续衰减）
	if knockback_velocity.length_squared() > 0.0:
		velocity += knockback_velocity
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * 60.0 * delta)

	move_and_slide()
	# 施法 / 传送期间不按输入改朝向（动作序列帧自己演）
	_update_visual(Vector2.ZERO if (is_casting_talisman or is_teleporting) else move_dir)


## 每物理帧推进所有计时器。分成三组，顺序不能调换：
##   1) 各种冷却 / buff 倒计时（先到期的先生效）
##   2) 资源恢复（精力、灵力、功法冷却）
##   3) 动作状态机（闪避、弹刀、攻击的结束判定）
func _tick_timers(delta: float) -> void:
	_tick_cooldowns(delta)
	_tick_heal_treasure(delta)
	_tick_haste_treasure(delta)
	_tick_taiji_guard(delta)
	_tick_tri_ring(delta)
	_tick_stake_treasure(delta)
	_tick_lamp_treasure(delta)
	_tick_thorns_treasure(delta)
	_tick_array_flags(delta)
	_tick_qi_rings(delta)
	_tick_qi_ward(delta)
	_tick_qi_channel(delta)
	_tick_boss_watch(delta)
	_tick_thunder_law(delta)
	_tick_thunder_channel(delta)
	_tick_thunder_banner()
	_tick_sun(delta)
	_tick_calamity(delta)
	_tick_mirror(delta)
	_tick_shadow(delta)
	_tick_fold(delta)
	_talisman_tick(delta)
	_tick_reckoning(delta)
	_tick_blade_form(delta)
	_tick_talisman_effects(delta)
	_tick_debuffs(delta)
	_tick_buffs(delta)
	_tick_resources(delta)
	_tick_action_states(delta)
	# 精力耗尽不再每帧刷红色脉冲：空爻本身有极缓的明暗起伏（ResourceRing._stamina_rows），
	# 用户 2026-11-11 定「状态只在简上说话」，屏幕上少一类持续闪烁


## 第 1 组：冷却与临时状态的倒计时
func _tick_cooldowns(delta: float) -> void:
	if dodge_cooldown_timer > 0.0:
		dodge_cooldown_timer -= delta
	if parry_cooldown_timer > 0.0:
		parry_cooldown_timer -= delta
	if invincible_timer > 0.0:
		invincible_timer -= delta
	if _hit_negated_timer > 0.0:
		_hit_negated_timer = maxf(0.0, _hit_negated_timer - delta)
	if _rogue_lei_chain_left > 0.0:
		_rogue_lei_chain_left = maxf(0.0, _rogue_lei_chain_left - delta)
	# 断念铃的目标侧抗性窗口：8 秒
	if _treasure_bell_immune_left > 0.0:
		_treasure_bell_immune_left = maxf(0.0, _treasure_bell_immune_left - delta)
	# ⚠ 「极限闪避增幅」buff 已整体删除（2026-10-23），这里原本的递减也一并去掉了。
	# 弹刀成功后的追击位移窗口到期
	# ⚠ 追击窗口的倒计时由 _tick_buffs 统一推进（2026-10-23 并入 buff），
	#   资格标记 parry_followup_can_dash 不用跟着清 —— 判定时与 has_buff 相与即可。
	# 完美弹反的定身计时
	if parry_stance_timer > 0.0:
		parry_stance_timer = maxf(0.0, parry_stance_timer - delta)
	# 自动弹刀窗口：倒计时 + 「站着不动」的保持条件
	# ⚠ 只在有移动输入时才打断（被击退是被动位移，不算玩家自己动了）
	if auto_parry_timer > 0.0:
		auto_parry_timer = maxf(0.0, auto_parry_timer - delta)
		if _get_move_dir().length_squared() > 0.0001:
			auto_parry_timer = 0.0
	# 肉鸽「逆鳞」增伤窗口
	if _rogue_scale_left > 0.0:
		_rogue_scale_left = maxf(0.0, _rogue_scale_left - delta)
	# 肉鸽「换镜·锐」增伤窗口
	if _rogue_mirror_swap_left > 0.0:
		_rogue_mirror_swap_left = maxf(0.0, _rogue_mirror_swap_left - delta)
	# 减速衰减
	if _slow_timer > 0.0:
		_slow_timer -= delta
		if _slow_timer <= 0.0:
			_slow_ratio = 0.0
	# 法宝召唤冷却（按法宝 id 记，跨战斗保留）
	for k in _summon_cooldowns.keys():
		var v := float(_summon_cooldowns[k]) - delta
		if v <= 0.0:
			_summon_cooldowns.erase(k)
		else:
			_summon_cooldowns[k] = v


## 第 2 组：资源恢复
func _tick_resources(delta: float) -> void:
	# 力竭 / 禁步：期间精力一律不恢复，计时器也清零
	# （避免状态结束那一刻瞬间补 1 格）。
	# ⚠ 计时由 _tick_debuffs 统一推进，这里只管「拦恢复」——不要再自己减计时，
	#   否则会和 debuff 表里的剩余时间对不上。
	if debuff_blocks_stamina_regen():
		stamina_regen_timer = 0.0
	# 精力：每满 stamina_regen_seconds 秒回 1 格（由属性「精力恢复」换算）
	elif stamina < max_stamina:
		stamina_regen_timer += delta
		if stamina_regen_timer >= stamina_regen_seconds:
			stamina_regen_timer -= stamina_regen_seconds
			stamina += 1
			_update_stamina_bar()
	else:
		stamina_regen_timer = 0.0

	# 灵力：连续回复，不像精力那样分格
	if mana < max_mana and not debuff_blocks_mana_regen():
		mana = minf(max_mana, mana + CharacterData.mana_regen() * delta)
		_update_mana_bar()

	# 功法冷却倒计时：到 0 就删除这一项（避免字典无限增长）
	for sid in skill_cooldowns.keys():
		var left := float(skill_cooldowns[sid]) - delta
		if left <= 0.0:
			skill_cooldowns.erase(sid)
		else:
			skill_cooldowns[sid] = left


## 第 3 组：动作状态机（闪避 / 弹刀 / 攻击 的结束判定）
func _tick_action_states(delta: float) -> void:
	if is_casting_talisman:
		_tick_talisman_cast(delta)

	if is_dodging:
		dodge_timer -= delta
		if dodge_timer <= 0.0:
			_end_dodge()

	# 技能前冲倒计时：走完就交还操作权
	if _skill_dash_timer > 0.0:
		_skill_dash_timer -= delta
		if _skill_dash_timer <= 0.0:
			_skill_dash_timer = 0.0
			_skill_dash_dir = Vector2.ZERO
			_skill_dash_speed = 0.0

	if _skill_face_lock > 0.0:
		_skill_face_lock = maxf(0.0, _skill_face_lock - delta)

	if is_parrying:
		parry_timer -= delta
		if parry_timer <= 0.0:
			_end_parry()

	if is_attacking:
		# 出伤卡在刀锋扫过的时刻（见 _start_attack 的 strike_delay）
		if _attack_hit_timer >= 0.0:
			_attack_hit_timer -= delta
			if _attack_hit_timer <= 0.0:
				_attack_hit_timer = -1.0
				if not is_dead:
					_perform_attack_hit()
		attack_timer -= delta
		# 后摇判定：进行到一定比例后进入「可被闪避 / 弹刀取消」的后摇
		if not attack_cancel_available and attack_timer <= attack_time * (1.0 - ATTACK_CANCEL_RATIO):
			attack_cancel_available = true
		if attack_timer <= 0.0:
			# 兜底：窗口走完了还挂着没落地的命中（被更短的窗口挤掉、外部改过 attack_timer 等）
			# 当场补结算。⚠ 只在这里补，不在 _end_attack 里补 —— 闪避/弹刀取消后摇
			# 是玩家主动中断，那一刀本来就该没有伤害。
			if _attack_hit_timer >= 0.0:
				_attack_hit_timer = -1.0
				if not is_dead:
					_perform_attack_hit()
			_end_attack()


# ===== 四、输入与动作：闪避 / 弹刀 / 攻击 =====
func _get_move_dir() -> Vector2:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return dir


func _handle_action_input() -> void:
	# 施符僵直：完全锁操作。仍同步按键边沿，避免按住 Q / 1 在施法结束后立刻自动放技
	if is_casting_talisman:
		_sync_input_edges_during_cast()
		return
	# 传送登场期间完全锁操作
	if is_teleporting:
		_sync_input_edges_during_cast()
		return
	# 法宝召唤：1 / 2 / 3 对应三个法宝槽（按下的那一瞬触发，长按不连发）
	# ⚠ 走 VirtualPad.is_key_down() 而不是 Input.is_physical_key_pressed()：
	#   后者只认真实键盘，触屏的虚拟键永远读不到（2026-10-22 加触屏支持）
	for i in 3:
		var down := VirtualPad.is_key_down(KEY_1 + i)
		if down and not bool(_summon_key_prev[i]):
			_try_summon_treasure(i)
		_summon_key_prev[i] = down
	# 使用轮询方式读取输入，避免鼠标点击被 UI/CanvasLayer 消费导致 _unhandled_input 收不到
	if is_dead:
		return
	# 眩晕（太极崩命中）：完全锁操作 —— 与施符僵直同一套处理，边沿照常同步，
	# 免得「按住攻击键」在眩晕结束时立刻触发一次普攻
	if is_action_blocked():
		_sync_input_edges_during_cast()
		return
	# 完美弹反的定身演出：站住 0.2 秒是「完美」的仪式感，但**绝不能吞掉反击键**。
	# 弹反的收益本来就是「立刻惩罚」，锁死输入会让玩家觉得按键没响应 —— 手感直接崩。
	# 所以攻击 / 闪避可以提前打断定身，什么都不按时才站满这 0.2 秒。
	if parry_stance_timer > 0.0:
		if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("dodge"):
			parry_stance_timer = 0.0
		else:
			return
	# 纳势反击蓄力中：只允许「左键提前斩出」（在 _physics_process 里处理），
	# 其它输入一律吞掉，否则同帧会连带触发普攻
	if _counter_charging:
		return

	# 攻击后摇可取消：闪避/弹刀可打断攻击收招
	var can_cancel_attack := is_attacking and attack_cancel_available

	# 闪避
	if Input.is_action_just_pressed("dodge") and not is_dodging and dodge_cooldown_timer <= 0.0 and _can_spend_stamina() and (not is_attacking or can_cancel_attack):
		if can_cancel_attack:
			_end_attack()
		_start_dodge()

	# 弹刀
	if Input.is_action_just_pressed("parry") and not is_parrying and parry_cooldown_timer <= 0.0 and _can_spend_stamina() and (not is_attacking or can_cancel_attack):
		if can_cancel_attack:
			_end_attack()
		_start_parry()

	# 攻击
	if Input.is_action_just_pressed("attack") and not is_attacking and not is_dodging:
		_start_attack()

	# 功法：Q / E / R / T 对应主动功法第 1~4 装配位
	_poll_skill_keys()


## 轮询功法快捷键：自己做边沿检测，不依赖 InputMap 配置
func _poll_skill_keys() -> void:
	var actives := CharacterData.equipped_active_skills()
	for i in range(SKILL_KEYS.size()):
		var code: int = SKILL_KEYS[i]
		# 同上：触屏虚拟键也要能触发功法
		var down := VirtualPad.is_key_down(code)
		var was_down := bool(_skill_key_down.get(code, false))
		_skill_key_down[code] = down
		if not down or was_down:
			continue
		if i >= actives.size():
			continue
		var sid := String(actives[i])
		if sid == "":
			continue
		if CharacterData.is_talisman_slot(sid):
			use_talisman_slot(sid)
		else:
			try_use_skill(sid)


## 施符僵直期间只同步按键状态、不触发任何动作
func _sync_input_edges_during_cast() -> void:
	for code in SKILL_KEYS:
		_skill_key_down[code] = VirtualPad.is_key_down(code)
	for i in 3:
		_summon_key_prev[i] = VirtualPad.is_key_down(KEY_1 + i)


## 轮盘用 1~6 快速使用后调用：把仍按住的 1/2/3 视为已处理，
## 避免关闭轮盘的同一帧被当成「刚按下」而误召唤法宝
func sync_summon_key_edges() -> void:
	for i in 3:
		_summon_key_prev[i] = VirtualPad.is_key_down(KEY_1 + i)


## ===== 法宝召唤（2026-10-21）=====
## 用法宝槽里的「召唤令」唤出对应 BOSS 当友军：不消耗法宝，按法宝 id 走冷却
func _try_summon_treasure(slot_index: int) -> void:
	if is_dead:
		return
	var slot := "treasure_%d" % (slot_index + 1)
	# ⚠ 必须走 get_equipped()：空槽在 treasure_slots 里存的是 **null**，
	#   直接 treasure_slots.get(slot, {}) 会拿到 null，再 .is_empty() 就闪退
	#   （用户 2026-10-21 报的 bug）
	var t: Dictionary = CharacterData.get_equipped(slot)
	if t.is_empty():
		_show_float_text("法宝槽 %d 是空的" % (slot_index + 1), Color(0.7, 0.7, 0.75))
		return
	var tid := String(t.get("id", ""))
	# ⚠ 主动参数在**模板**里：make_treasure_instance 只拷了 id/名称/属性，
	#   召唤 / 回血相关字段要从 ItemDB 反查，别读实例
	var tpl := ItemDB.get_treasure_template(tid)
	if tpl.is_empty():
		_show_float_text("这件法宝没有主动效果", Color(0.7, 0.7, 0.75))
		return
	if String(tpl.get("active_type", "")) == "heal":
		_start_heal_treasure(t, tpl)
		return
	if String(tpl.get("active_type", "")) == "haste":
		_start_haste_treasure(t, tpl)
		return
	if String(tpl.get("active_type", "")) == "taiji_guard":
		_start_taiji_guard_treasure(t, tpl)
		return
	if String(tpl.get("active_type", "")) == "delayed_reckoning":
		_start_delayed_reckoning_treasure(t, tpl)
		return
	if String(tpl.get("active_type", "")) == "blade_form":
		_start_blade_form_treasure(t, tpl)
		return
	if String(tpl.get("active_type", "")) == "tri_ring":
		_start_tri_ring_treasure(t, tpl)
		return
	if String(tpl.get("active_type", "")) == "mind_lock":
		_start_mind_lock_treasure(t, tpl)
		return
	if String(tpl.get("active_type", "")) == "stake":
		_start_stake_treasure(t, tpl)
		return
	if String(tpl.get("active_type", "")) == "lamp":
		_start_lamp_treasure(t, tpl)
		return
	if String(tpl.get("active_type", "")) == "corrode":
		_start_corrode_treasure(t, tpl)
		return
	if String(tpl.get("active_type", "")) == "blood_seal":
		_start_blood_seal_treasure(t, tpl)
		return
	if String(tpl.get("active_type", "")) == "swap":
		_start_swap_treasure(t, tpl)
		return
	if String(tpl.get("active_type", "")) == "thorns":
		_start_thorns_treasure(t, tpl)
		return
	if String(tpl.get("active_type", "")) == "gust":
		_start_gust_treasure(t, tpl)
		return
	if String(tpl.get("summon_boss_id", "")) == "":
		_show_float_text("这件法宝没有主动效果", Color(0.7, 0.7, 0.75))
		return
	var left := float(_summon_cooldowns.get(tid, 0.0))
	if left > 0.0:
		_show_float_text("法宝冷却中（%.0f 秒）" % left, Color(0.85, 0.6, 0.35))
		return
	# 强化加成：法宝实例上的 summon_boost_count（每级 +2%，跨进阶累积）
	var boost_count := int(t.get("summon_boost_count", 0))
	# 进阶奖励：进阶成功时额外获得「进阶前加成的一半」，单独累积（可带小数）
	var ascend_boost_pct := float(t.get("summon_ascend_boost_pct", 0.0))
	# 进阶加成：每次进阶成功让召唤物多存在 5 秒（也累积）
	var duration_bonus := int(t.get("summon_duration_bonus", 0))
	if _summon_ally_boss(tpl, boost_count, duration_bonus, ascend_boost_pct):
		_summon_cooldowns[tid] = float(tpl.get("summon_cooldown", 60.0))


## 该法宝当前的召唤冷却剩余秒数（战斗 HUD 的法宝栏用它显示）
func summon_cooldown_left(treasure_id: String) -> float:
	return float(_summon_cooldowns.get(treasure_id, 0.0))


## 凝水佩主动回血：开始引导（同一时间只允许一个）
func _start_heal_treasure(item: Dictionary, tpl: Dictionary) -> void:
	if _heal_treasure_id != "":
		_show_float_text("法宝正在生效", Color(0.7, 0.85, 1.0))
		return
	var tid := String(tpl.get("treasure_id", ""))
	var left := summon_cooldown_left(tid)
	if left > 0.0:
		_show_float_text("法宝冷却中（%.0f 秒）" % left, Color(0.85, 0.6, 0.35))
		return
	var stats := ItemDB.treasure_active_stats(item, tpl)
	if stats.is_empty():
		return
	var mana_cost := float(stats.get("mana", 10.0))
	if mana < mana_cost:
		_show_float_text("灵力不足（凝水佩需要 %d 点）" % int(round(mana_cost)),
			UIKit.C_FLOAT_WARN)
		return
	_heal_treasure_id = tid
	_heal_treasure_left = float(stats.get("duration", 8.0))
	_heal_treasure_tick = 0.0
	_heal_treasure_heal = float(stats.get("heal", 5.0))
	_heal_treasure_mana = mana_cost
	_summon_cooldowns[tid] = float(stats.get("cooldown", 20.0))
	TreasureFx.play_water_gather(self, _body_center())
	_show_float_text("凝水佩 · 每秒 -%d 灵力 / +%d 气血" % [
		int(round(mana_cost)), int(round(_heal_treasure_heal))], Color(0.52, 0.9, 1.0))


## 每物理帧推进：先判灵力是否还够 10 点，再按秒结算回复
func _tick_heal_treasure(delta: float) -> void:
	if _heal_treasure_id == "":
		return
	if is_dead:
		_stop_heal_treasure("", false)
		return
	if mana < _heal_treasure_mana:
		_stop_heal_treasure("灵力不足，凝水佩中断", true)
		return
	_heal_treasure_left -= delta
	_heal_treasure_tick += delta
	while _heal_treasure_tick >= HEAL_TREASURE_TICK:
		_heal_treasure_tick -= HEAL_TREASURE_TICK
		if not spend_mana(_heal_treasure_mana):
			_stop_heal_treasure("灵力不足，凝水佩中断", true)
			return
		var healed := restore_health(_heal_treasure_heal)
		if healed > 0.0:
			_show_float_text("+%d 气血" % int(round(healed)), Color(0.52, 1.0, 0.68))
			_flash_color(Color(0.62, 1.0, 0.72, 1.0), 0.16)
		if _heal_treasure_left <= 0.0:
			_stop_heal_treasure("凝水佩结束", false)
			return


## 结束引导；message 非空时飘一行提示，warn = 灵力不足等警告色
func _stop_heal_treasure(message: String = "", warn: bool = false) -> void:
	_heal_treasure_id = ""
	_heal_treasure_left = 0.0
	_heal_treasure_tick = 0.0
	_heal_treasure_heal = 0.0
	if message != "":
		_show_float_text(message, UIKit.C_FLOAT_WARN if warn else Color(0.62, 0.85, 1.0))


## 逐电环主动加速：一次性扣 30 灵力，3 秒移速 800，雷光覆体并拖尾
func _start_haste_treasure(item: Dictionary, tpl: Dictionary) -> void:
	if _haste_treasure_left > 0.0:
		_show_float_text("法宝正在生效", Color(1.0, 0.92, 0.4))
		return
	var tid := String(tpl.get("treasure_id", ""))
	var left := summon_cooldown_left(tid)
	if left > 0.0:
		_show_float_text("法宝冷却中（%.0f 秒）" % left, Color(0.85, 0.6, 0.35))
		return
	var stats := ItemDB.treasure_active_stats(item, tpl)
	if stats.is_empty():
		return
	var cost := float(stats.get("mana", 30.0))
	if mana < cost:
		_show_float_text("灵力不足（逐电环需要 %d 点）" % int(round(cost)),
			UIKit.C_FLOAT_WARN)
		return
	if not spend_mana(cost):
		return
	var duration := float(stats.get("duration", 3.0))
	_haste_treasure_id = tid
	_haste_treasure_left = duration
	_haste_treasure_speed = float(stats.get("speed", 800.0))
	_summon_cooldowns[tid] = float(stats.get("cooldown", 30.0))
	_haste_treasure_fx = TreasureFx.attach_thunder(self, _body_center(), duration)
	_show_float_text("逐电环 · 速度提升至 %d" % int(round(_haste_treasure_speed)),
		TreasureFx.THUNDER_COLOR)


func _tick_haste_treasure(delta: float) -> void:
	if _haste_treasure_left <= 0.0:
		return
	_haste_treasure_left = maxf(0.0, _haste_treasure_left - delta)
	if _haste_treasure_left <= 0.0:
		_stop_haste_treasure()


func _stop_haste_treasure() -> void:
	_haste_treasure_id = ""
	_haste_treasure_left = 0.0
	_haste_treasure_speed = 0.0
	if is_instance_valid(_haste_treasure_fx):
		_haste_treasure_fx.queue_free()
	_haste_treasure_fx = null


## 太极盘主动·太极护体：一次性耗蓝，限时减伤（player.take_damage 里乘 1-reduction）
func _start_taiji_guard_treasure(item: Dictionary, tpl: Dictionary) -> void:
	if _taiji_guard_left > 0.0:
		_show_float_text("法宝正在生效", Color(1.0, 0.92, 0.6))
		return
	var tid := String(tpl.get("treasure_id", ""))
	var left := summon_cooldown_left(tid)
	if left > 0.0:
		_show_float_text("法宝冷却中（%.0f 秒）" % left, Color(0.85, 0.6, 0.35))
		return
	var stats := ItemDB.treasure_active_stats(item, tpl)
	if stats.is_empty():
		return
	var cost := float(stats.get("mana", 20.0))
	if mana < cost:
		_show_float_text("灵力不足（太极盘需要 %d 点）" % int(round(cost)),
			UIKit.C_FLOAT_WARN)
		return
	if not spend_mana(cost):
		return
	_taiji_guard_id = tid
	_taiji_guard_left = float(stats.get("duration", 6.0))
	_taiji_guard_pct = float(stats.get("reduction", 0.3))
	_summon_cooldowns[tid] = float(stats.get("cooldown", 30.0))
	_taiji_guard_fx = TreasureFx.attach_taiji_guard(self, _body_center(), _taiji_guard_left)
	_show_float_text("太极盘 · %d 秒内受伤 -%d%%" % [
		int(round(_taiji_guard_left)), int(round(_taiji_guard_pct * 100.0))],
		TreasureFx.TAIJI_COLOR)


func _tick_taiji_guard(delta: float) -> void:
	if _taiji_guard_left <= 0.0:
		return
	_taiji_guard_left = maxf(0.0, _taiji_guard_left - delta)
	if _taiji_guard_left <= 0.0:
		_stop_taiji_guard()
		return
	_capture_taiji_projectiles()


## 太极接化：护体期间，敌方飞行物进入身周就先接住，交给弹体自己绕圈/反打
func _capture_taiji_projectiles() -> void:
	if is_dead:
		return
	var r2 := TAIJI_CAPTURE_RADIUS * TAIJI_CAPTURE_RADIUS
	for raw in get_tree().get_nodes_in_group("enemy_projectile"):
		if not is_instance_valid(raw) or not raw is Node2D:
			continue
		if bool(raw.get("is_deflected")) or bool(raw.get("_capture_active")):
			continue
		if global_position.distance_squared_to((raw as Node2D).global_position) > r2:
			continue
		if raw.has_method("begin_taiji_capture"):
			raw.call("begin_taiji_capture", self, TAIJI_ORBIT_TIME)


func _stop_taiji_guard() -> void:
	_taiji_guard_id = ""
	_taiji_guard_left = 0.0
	_taiji_guard_pct = 0.0
	if is_instance_valid(_taiji_guard_fx):
		_taiji_guard_fx.queue_free()
	_taiji_guard_fx = null


## 凝水佩剩余引导秒数（战斗 HUD 法宝栏显示倒计时）
func heal_treasure_left(treasure_id: String) -> float:
	if _heal_treasure_id != treasure_id:
		return 0.0
	return maxf(0.0, _heal_treasure_left)


## 逐电环剩余加速秒数（战斗 HUD 法宝栏显示倒计时）
func haste_treasure_left(treasure_id: String) -> float:
	if _haste_treasure_id != treasure_id:
		return 0.0
	return maxf(0.0, _haste_treasure_left)


## 太极盘剩余护体秒数
func taiji_guard_left(treasure_id: String) -> float:
	if _taiji_guard_id != treasure_id:
		return 0.0
	return maxf(0.0, _taiji_guard_left)


func tri_ring_left(treasure_id: String) -> float:
	if _tri_ring_id != treasure_id:
		return 0.0
	return maxf(0.0, _tri_ring_left)


## 法宝栏统一状态：冷却或主动效果剩余，取较长者
## 迟照符的窗口也要显示，否则玩家看不到「还剩几秒结算」
func treasure_status_left(treasure_id: String) -> float:
	var left := 0.0
	for v in [summon_cooldown_left(treasure_id), heal_treasure_left(treasure_id),
			haste_treasure_left(treasure_id), taiji_guard_left(treasure_id),
			tri_ring_left(treasure_id), stake_left(treasure_id),
			lamp_left(treasure_id), thorns_left(treasure_id),
			reckoning_left(treasure_id), blade_form_left(treasure_id)]:
		left = maxf(left, float(v))
	return left


## 迟照符剩余窗口（法宝栏倒计时用）
func reckoning_left(treasure_id: String) -> float:
	if _reckoning_id != treasure_id:
		return 0.0
	return maxf(0.0, _reckoning_left)


## 换锋符剩余窗口（法宝栏倒计时用）
func blade_form_left(treasure_id: String) -> float:
	if _blade_form_id != treasure_id:
		return 0.0
	return maxf(0.0, _blade_form_left)


## 生成友军 BOSS（复用原 BOSS 的场景与 AI，只把阵营翻转）
## boost_count      = 法宝的强化累计级数：每级让召唤物气血/攻击各 +2% 基础值
## duration_bonus   = 法宝进阶成功的次数：每次让存在时间 +5 秒
## ascend_boost_pct = 进阶奖励累计的额外百分比（进阶前加成的 50%）
## 返回是否成功
func _summon_ally_boss(tpl: Dictionary, boost_count: int = 0, duration_bonus: int = 0,
		ascend_boost_pct: float = 0.0) -> bool:
	var boss_id := String(tpl.get("summon_boss_id", ""))
	var scene_path := WorldDB.get_boss_scene(boss_id)
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		push_warning("召唤失败：找不到 BOSS 场景 " + boss_id)
		return false
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return false
	var node: Node2D = packed.instantiate()
	# 强化加成：气血与攻击各 +2%/级；再加进阶奖励的额外百分比（乘在基础值上，无上限）
	var boost := 1.0 + 0.02 * float(maxi(0, boost_count)) + ascend_boost_pct / 100.0
	# ⚠ 以下四项必须在 add_child **之前**设：
	#   is_ally   → BossBase._ready() 据此决定入 "ally_summon" 还是 "boss" 组
	#   max_hp    → _ready() 里 current_hp = max_hp，进树后再改会变成半血
	#   summon_life / ally_damage_scale → 由基类倒计时与伤害分派读取
	node.set("is_ally", true)
	node.set("max_hp", float(node.get("max_hp")) * float(tpl.get("summon_hp_ratio", 0.5)) * boost)
	node.set("ally_damage_scale", float(tpl.get("summon_damage_scale", 0.7)) * boost)
	# 存在时间：基础时长 + 每次进阶 +5 秒
	var life := float(tpl.get("summon_duration", 20.0)) \
		+ float(maxi(0, duration_bonus)) * CharacterData.SUMMON_DURATION_PER_ASCEND
	node.set("summon_life", maxf(1.0, life))
	var dir := attack_dir.normalized()
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	node.position = global_position + dir * 110.0 + Vector2(0.0, -20.0)
	get_parent().add_child(node)
	# 目标 = 最近的敌方 BOSS（"boss" 组只含敌方，友军不会选中自己）
	node.set("target", _nearest_boss(9999.0))
	# 友军标识：头顶绿色「友军」标签
	# ⚠ 不能只靠 modulate 染色：占位色块/贴图颜色是乘法，橙色 BOSS 乘绿色还是橙的，
	#   用一个独立标签才能一眼区分阵营（换正式美术后同样有效）
	var tag := Label.new()
	tag.text = "友军"
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", Color(0.45, 1.0, 0.6))
	tag.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	tag.add_theme_constant_override("outline_size", 3)
	tag.position = Vector2(-16.0, -104.0)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(tag)
	# 召唤表现 + 提示（走 ArtDB 特效表，换美术只改表）
	FxPlayer.spawn(get_parent(), "fx_phase_gather", {
		"global_position": node.global_position + Vector2(0.0, -20.0),
		"lifetime": 0.6,
	})
	_show_float_text("召唤！%s" % String(tpl.get("treasure_name", "")), Color(0.62, 1.0, 0.78))
	_apply_ally_dark_theme(node)
	return true


## 友军的「黑化」表现（2026-10-21 用户定）：贴图压暗 + 身边持续冒黑气
## ⚠ 变暗必须改 **SkinVisual 的 render_node**，不能改 BOSS 的 `Visual.modulate`：
##   基类的 `_flash_attack` 会把 `Visual.modulate` 覆盖成白色再还原，变黑会被冲掉；
##   而 render_node 的 modulate 是叠加在上层，不受影响。头顶血条也不在 Visual 下，不会被压暗。
func _apply_ally_dark_theme(node: Node) -> void:
	var skin_vis := node.get_node_or_null("Visual/Skin")
	if skin_vis != null:
		var rn = skin_vis.get("render_node")
		if rn is CanvasItem:
			(rn as CanvasItem).modulate = Color(0.52, 0.48, 0.60)

	# 黑气：每 0.25 秒在身体周围随机位置冒一团（挂 Timer，召唤物销毁时一起释放）
	var smoke := Timer.new()
	smoke.name = "BlackSmokeTimer"
	smoke.wait_time = 0.25
	smoke.autostart = true
	smoke.timeout.connect(func() -> void:
		if not is_instance_valid(node):
			return
		var off := Vector2(randf_range(-26.0, 26.0), randf_range(-52.0, 10.0))
		FxPlayer.spawn(node, "fx_summon_black_smoke", {"position": off})
	)
	node.add_child(smoke)


## 起手闪避：扣 1 格精力，进入 0.18 秒无敌位移
## 没有移动输入时朝当前攻击朝向翻滚（保证原地按也能滚出去）
func _start_dodge() -> void:
	# 重伤等 debuff 会封掉闪避（2026-10-23）：拦在**真正起手之前**，
	# 这样精力不会被扣、冷却也不会进
	if is_dodge_blocked():
		var blocker := ""
		for id in debuffs.keys():
			if bool(DebuffDB.get_debuff(String(id)).get("no_dodge", false)):
				blocker = String(id)
				break
		_show_float_text("%s中，无法闪避" % DebuffDB.display_name(blocker),
			DebuffDB.color(blocker))
		return
	# 主动翻滚 = 放弃守势（与移动/出手一样会打断自动弹刀窗口）
	auto_parry_timer = 0.0
	var dir := _get_move_dir()
	if dir.length_squared() == 0.0:
		dir = attack_dir
	_dodge_dir = dir.normalized()
	is_dodging = true
	Tutorial.note("dash_used")
	dodge_timer = DODGE_TIME
	emit_noise()
	# 闪避优先于技能前冲：手动打断时把前冲状态清掉，避免两段位移叠加
	_skill_dash_timer = 0.0
	_skill_dash_dir = Vector2.ZERO
	_skill_dash_speed = 0.0
	_skill_dash_origin = Vector2.INF
	_skill_face_lock = 0.0
	dodge_cooldown_timer = DODGE_COOLDOWN * (1.0 - clampf(RogueRun.stat("dodge_cd_pct") / 100.0, 0.0, 0.8))
	# 肉鸽「踏影」：闪避后下一击 +N%（一次性，命中时消费）
	if RogueRun.active and RogueRun.stat("dmg_after_dodge") > 0.0:
		_rogue_step_ready = true
	_spend_stamina()
	# 普通闪避音效（轻"嗖"声，与完美闪避区分）
	_play_sfx(_dodge_sound)
	# 闪避拖影
	_spawn_dodge_trail()
	# 两仪真人：普通闪避只在 BOSS 出招时给一点小震盾（BOSS 自己会判断状态）
	_notify_bosses("notify_dodge_started")


## 闪避拖影：复制角色形象生成浅色残影
func _spawn_dodge_trail() -> void:
	_spawn_ghost(Color(0.3, 0.7, 1.0, 0.35), 0.0, 0.25)


## 结束闪避（无敌帧也随之结束）
func _end_dodge() -> void:
	is_dodging = false
	# 肉鸽「踏阵」：在己方阵区内闪避 → 落点引爆阵纹（阵内减伤乘区 < 1.0 即「在阵里」）
	if RogueRun.active and not is_dead and RogueRun.has_flag("array_step_trap") \
			and _array_zone_defense_mult < 1.0:
		var trap_dmg := CharacterData.spell_attack()
		var trapped := false
		for e in _array_enemy_units():
			if not is_instance_valid(e) or not e is Node2D:
				continue
			if (e as Node2D).global_position.distance_to(global_position) > 220.0:
				continue
			_deal_direct_damage(e, trap_dmg, "elemental", "thunder", "skill_array_sweep")
			if e.has_method("apply_debuff"):
				e.call("apply_debuff", "array_slow", 2.0, self)
			trapped = true
		if trapped:
			SkillFx.play_at_point(get_parent(), "skill_array_sweep",
				MoveDB.resolve_player("form_array_sweep"), Vector2.RIGHT, global_position, self)
			_show_float_text("踏阵 · 阵纹引爆", Color(0.80, 0.86, 1.0))


## 起手弹刀：扣 1 格精力，开启 0.22 秒判定窗口
## ⚠ 普通弹刀**零前摇**（按下即判定），只有完美弹反才会有 0.2 秒定身
func _start_parry() -> void:
	if is_action_blocked():
		return
	is_parrying = true
	parry_timer = PARRY_WINDOW
	parry_cooldown_timer = PARRY_COOLDOWN
	_spend_stamina()
	_flash(Color(0.4, 0.9, 1.0))


## 关闭弹刀窗口（时间到 / 弹成功都会调用）
func _end_parry() -> void:
	is_parrying = false


func _start_attack() -> void:
	if is_action_blocked():
		return
	# 主动出手 = 放弃守势：自动弹刀窗口立即失效
	auto_parry_timer = 0.0
	is_attacking = true
	emit_noise()
	attack_cancel_available = false
	# 每次起手现算间隔：满雷势 +30% 攻速与「顺天」等临时属性都要当场生效
	attack_time = CharacterData.attack_interval() / _attack_haste_mult()
	# 判断当前是否为终结技（连击第三段）
	is_finisher_attack = (attack_combo % ATTACK_COMBO_MAX) == 2
	# 终结技用更长后摇
	attack_timer = _finisher_attack_time() if is_finisher_attack else attack_time
	# 有移动输入就朝移动方向挥刀，没有就沿用上一次的朝向
	var move_dir := _get_move_dir()
	var moving := move_dir.length_squared() > 0.0
	if moving:
		attack_dir = move_dir.normalized()
	# 软锁定：附近有 BOSS 时，攻击方向自动朝向最近的 BOSS
	#   - 移动中：保留「前方 ±90°」限制，避免自动转身去打背后
	#   - 静止时：不限制角度 —— 站着不动时玩家只能用上次朝向，
	#     若那次朝向恰好背对 BOSS，限制会让锁定失效、导致贴着 BOSS 打空
	_auto_aim_to_boss(not moving)
	# 攻击朝向：人物立即转向本次攻击方向（含软锁定 BOSS 后的方向）
	# ⚠ 只翻转水平镜像，不旋转节点 —— 素材是侧向作画，朝上下时仍用左/右朝向
	# ⚠ 纯垂直攻击（|x| ≤ 0.1）不翻转：避免站着朝右时按"上"攻击会突然转身
	# ⚠ 攻击期间 _update_visual 里的翻转被 is_attacking 挡住，所以这里的朝向不会被移动覆盖
	if absf(attack_dir.x) > 0.1:
		anim.scale.x = 1.0 if attack_dir.x > 0.0 else -1.0
	# 挥刀特效：第1段"来"、第2段"回"、第3段"终结技"（更华丽）
	var swing_back := (attack_combo % ATTACK_COMBO_MAX) == 1
	# ⚠ 段位必须在 attack_combo 自增**之前**取：出伤时刻按本段算，
	#   取晚了会拿到下一段的时刻（实测会错成 0.085 秒而不是 0.184 秒）
	_attack_seg_idx = attack_combo % ATTACK_COMBO_MAX
	var atk_seg := _combo_segment()
	_spawn_slash_effect(swing_back, is_finisher_attack)
	# 攻击动作序列帧：一次性动作，整段压进本次后摇（普通 0.35s / 终结技 0.5s）
	# ⚠ 必须传 attack_timer（本次实际时长）而不是写死值：终结技后摇更长，动作要跟着放慢
	if skin != null:
		skin.play_one_shot("attack", attack_timer)
	# ⚠ 段位在这里定稿：弹反追击与吸附的几何都必须和**出伤那一帧**同一段
	#   （`_perform_attack_hit` → `_melee_shape` 读的是自增后的 attack_combo）。
	attack_combo += 1
	var snap_seg := attack_combo % ATTACK_COMBO_MAX
	# 弹反追击：完美弹反窗口内，普攻会快速位移到可命中 BOSS 的距离
	# （资格检查与消费都在 _parry_followup_dash 内部统一处理；
	#   传 shape = 走与吸附共用的落点求解器，不传 = 功法入口的原口径）
	var did_dash := _parry_followup_dash(ATTACK_RANGE, _melee_shape(snap_seg))
	# 平A 近距离吸附：每次起手都尝试，但只在「这一刀原本会落空」时才动手，
	# 且按落空原因分开：角度不够只转向、距离不够才补到刚好进判定。
	# ⚠ 弹反追击已经在位移了就别叠加，两段滑步会把人送过头。
	var did_snap := false if did_dash else _melee_snap_to_target(snap_seg)
	# 攻击命中判定：等刀锋扫到正前方再结算（方向/半径仍按段位弧，判定本身没变）
	var strike := 0.12
	if weapon != null:
		strike = weapon.strike_delay(atk_seg)
	# ⚠ 出伤时刻必须落在本次挥刀窗口内：武器那 0.19 秒左右的刀锋时刻是按慢速标定的，
	#   攻速一快（装备攻速 / 满雷势 ÷1.3）窗口比它还短，attack_timer 会先走完，
	#   _end_attack 顺手把 _attack_hit_timer 清成 -1 —— 结果就是「攻速越高越不掉血」。
	#   压到窗口的 72%：慢速时完全不受影响（0.184 < 0.35×0.72），只在快起来时前移。
	strike = minf(strike, attack_timer * 0.72)
	if did_dash or did_snap:
		# 弹反追击 / 吸附先位移 0.12 秒，落地后再按段位时刻结算，避免打空
		await get_tree().create_timer(MELEE_SNAP_TIME).timeout
		if is_dead:
			return
		if not is_attacking:
			# 位移这 0.12 秒里窗口已经走完（攻速极快时会出现）：当场结算，别把这一刀丢掉
			_perform_attack_hit()
			return
		if did_snap:
			# 落点是起手那一帧锁死的，但这 0.12s 里 BOSS 会走位 ——
			# 出伤前一帧用**当时的几何**再校一次，还差就只补差的那一段
			_melee_snap_recheck(attack_combo % ATTACK_COMBO_MAX)
		_attack_hit_timer = minf(maxf(0.0, strike - MELEE_SNAP_TIME), attack_timer * 0.72)
	else:
		_attack_hit_timer = strike


## 弹反追击位移：快速贴近最近的 BOSS，使其进入攻击命中范围
## target_range = 期望的最终距离（功法用自己的射程）
## ⚠ shape 非空 = **平A 入口**，与近距离吸附共用同一套落点求解器 `_auto_step_solve`；
##   留空 = 功法入口，站位口径原样保留（用户明确排除了「三处统一」，功法位移本次不动）。
## 成功后**消耗位移资格**（窗口内只有一次），位移资格只由完美弹反提供
func _parry_followup_dash(target_range: float = ATTACK_RANGE, shape: Dictionary = {}) -> bool:
	# 换锋窗口内别把人拉到近战贴脸：停在剑气射程内即可
	if _blade_form_left > 0.0 and is_equal_approx(target_range, ATTACK_RANGE):
		target_range = _blade_form_range * 0.55
	if not (has_buff("parry_followup") and parry_followup_can_dash):
		return false
	var nearest: Node2D = null
	var nearest_dist := 99999.0
	for boss in get_tree().get_nodes_in_group("boss"):
		# ⚠ 死单位不参与索敌 / 结算：试炼里 BOSS 尸体不销毁、仍在 "boss" 组
		if BossBase.is_unit_dead(boss):
			continue
		if not is_instance_valid(boss) or not boss is Node2D:
			continue
		var d := global_position.distance_to(boss.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = boss
	if not nearest:
		return false
	# 落点基准是**受击球球心**（球心即命中平面），不是脚底、也不是 sprite 底边：
	# ⚠ 受击球是偏心的，赫连霄正面几个球在 +25~+75、背后只剩一根 r16 胶囊；
	# ⚠ 更关键的是 feet_position() 读 skin.visual_rect.end.y —— 赤霄界 rig 画布底下
	#   留了 95px 空边，脚底被算成 +95，而受击球压在地面 y=0。按它站位会让玩家落到
	#   命中平面下方 95px，追击「看着贴身」也一定打空（2026-10-30 实机反馈）。
	var anchor := _nearest_hit_sphere(nearest, global_position)
	var stand := 0.0
	var mid_deg := 0.0
	if not shape.is_empty():
		mid_deg = float(shape["mid_deg"])
		var sol := _auto_step_solve(nearest, shape, global_position, _snap_stand_floor(nearest))
		# 本来就能打到 ⇒ 不位移，而且**资格不消耗**：这一刀已经吃到弹反的奖励了
		if sol.is_empty():
			return false
		stand = float(sol["stand"])
		anchor = sol["anchor"]
	else:
		# 功法入口的站位口径原样保留：⚠ 上限不能只按 hit_radius（外接半径，含头顶球）——
		# 赫连霄 hit_radius≈93 → 站到 111，命中容差只剩 2~3 像素，会「看着贴身却打空」
		var boss_r := 0.0
		if nearest.has_method("hit_radius"):
			boss_r = float(nearest.call("hit_radius"))
		var body_r := boss_r
		if nearest.has_method("body_radius"):
			body_r = float(nearest.call("body_radius"))
		stand = maxf(target_range * 0.7, minf(boss_r + 18.0, body_r + 24.0))
	var side := _snap_side(anchor)
	var target_pos := anchor + Vector2(side * stand, 0.0)
	# 位移后重新对准：落点变了，沿用旧朝向会打偏（命中判定用的是 attack_dir）
	_aim_at(anchor, target_pos, mid_deg)
	# 资格用掉，**buff 也一起清**：否则 HUD 还挂着「追击 x.xs」，实际却已经追不了
	parry_followup_can_dash = false
	remove_buff("parry_followup")
	# 清掉残余速度：tween 是直接改坐标的，若还带着上一帧的速度，
	# move_and_slide 会在位移结束后继续把人推偏几个像素（落点就不准了）
	velocity = Vector2.ZERO
	# 快速位移（带拖影）
	# ⚠ 与平A 吸附**相反**，这里必须继续实时追踪 BOSS：弹反僵直里 BOSS 会被击退 120
	#   （BossBase.on_parried → _bump_back，0.18 秒），用开打瞬间的坐标会在追击路上直接
	#   打空（2026-10-30 实机反馈：完美弹反赫连霄后追击打不到他）。位移时长 0.22s
	#   略长于击退的 0.18 秒，落点才算得准。别照着吸附把它一起「锁死」。
	_spawn_dodge_trail()
	var start_pos := global_position
	# ⚠ 只捕获 instance_id：直接捕获节点，目标先释放时 Godot 会刷
	#   "Lambda capture at index 0 was freed"（探针清场必现）。
	var nearest_id := nearest.get_instance_id()
	var dash_tween := create_tween()
	dash_tween.tween_method(func(t: float) -> void:
		var live := instance_from_id(nearest_id) as Node2D
		if live == null or not is_instance_valid(live):
			return
		var live_c := _nearest_hit_sphere(live, start_pos)
		global_position = start_pos.lerp(live_c + Vector2(side * stand, 0.0), t)
		if t >= 0.999:
			_aim_at(_nearest_hit_sphere(live, global_position), global_position, mid_deg)
	, 0.0, 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return true


## 离 from 最近的受击球球心（世界坐标）。追击落点按它算：受击球是偏心的。
func _nearest_hit_sphere(boss: Node2D, from: Vector2) -> Vector2:
	var best := boss.global_position
	var best_d := 1.0e9
	if boss.has_method("hit_spheres"):
		for sp in boss.call("hit_spheres"):
			var sv: Vector3 = sp
			var c: Vector2 = boss.global_position + Vector2(sv.x, sv.y)
			var d := from.distance_to(c)
			if d < best_d:
				best_d = d
				best = c
	return best


## ---------------------------------------------------------------------
## 平A 近距离吸附（2026-11-10 用户：「平a会有攻击不到人的情况」；2026-11-11 按落空原因分治）
##
## 判定中心是玩家本体、目标却是**偏心的受击球**（木桩球心 y=-65，赫连霄正面球在
## +25~+75、背后只剩一根 r16 胶囊），再加上玩家碰撞体会被 BOSS 挤开，「看着贴脸」
## 常常还差几十像素。起手时做一次**与实判同源**的预检，然后把落空分成两种分开治：
##   ① 距离够、角度不够 → 只改 attack_dir，人一步不动、不出残影；
##   ② 距离真的不够     → 补到「刚好进判定 + 余量」，缺口 > 60px 就不管。
## 旧版不看原因、一律走到固定贴脸站位，于是段 3 刺击（半角 35°，段 1/2 是 89.5°）
## 贴身循环时每三段白扑一次脸 —— 用户报的「明明砍得到还是吸到面前」就是这一条。
## ---------------------------------------------------------------------

## 这一刀的扇形形状。抽成纯函数是为了让「预检」和 `_perform_attack_hit` 用同一份参数：
## ⚠ seg_idx 由调用方传，不要在这里读 attack_combo —— 起手时它还没自增，
##   而出伤时 `_combo_segment()` 读的是已自增的值（注释见 _start_attack 的 1510 行）。
##   预检传 `(attack_combo+1)%3`，出伤传 `attack_combo%3`，两者才是同一段。
func _melee_shape(seg_idx: int) -> Dictionary:
	var half_angle := deg_to_rad(80.0 if is_finisher_attack else 70.0)
	var reach := (ATTACK_RANGE + 24.0) * (FINISHER_RANGE_MULT if is_finisher_attack else 1.0)
	var mid_deg := 0.0
	if weapon != null:
		var segs: Array = ArtDB.get_visual(weapon.weapon_id).get("combo_sweeps", [])
		if segs.is_empty():
			segs = ArtDB.WEAPON_COMBO_SWEEPS
		if seg_idx >= 0 and seg_idx < segs.size():
			var seg: Dictionary = segs[seg_idx]
			var from_deg := float(seg.get("from_deg", -85.0))
			var to_deg := float(seg.get("to_deg", 70.0))
			mid_deg = (from_deg + to_deg) * 0.5
			half_angle = deg_to_rad(maxf(absf(to_deg - from_deg) * 0.5 + 12.0, 35.0))
			reach = weapon.seg_reach(seg)
	return {
		"dir": attack_dir.rotated(deg_to_rad(mid_deg)),
		"reach": reach,
		"half_angle": half_angle,
		"mid_deg": mid_deg,
	}


## 与 `_damage_bosses_in_shape` 同源的纯判定（只回答「这一刀能不能打到它」，不结算伤害）。
## ⚠ 逐个受击球独立算距离与夹角：横长 BOSS 用身体中心算会漏掉头侧的球。
func _would_hit_boss(boss: Node2D, shape: Dictionary, from: Vector2) -> bool:
	if boss == null or not boss.has_method("hit_spheres"):
		return false
	var dir: Vector2 = shape["dir"]
	var reach := float(shape["reach"])
	var cos_half := cos(float(shape["half_angle"]))
	for sp in boss.call("hit_spheres"):
		var sv: Vector3 = sp
		if sv.z <= 0.0:
			continue
		var to_sp: Vector2 = boss.global_position + Vector2(sv.x, sv.y) - from
		var d := to_sp.length()
		if d > reach + sv.z:
			continue
		if d > 1.0 and dir.dot(to_sp / d) < cos_half:
			continue
		return true
	return false


## 落点离 BOSS 身体的下限（防钻身）：按目标的**身体厚度**收口，不是外接半径。
## ⚠ 训练木桩不是 BossBase 子类、没有 body_radius()：不兜这一句会按 0 站位，
##   落点直接钻进胶囊被物理弹开，看着「贴身」却一定打空。
func _snap_stand_floor(boss: Node2D) -> float:
	var body_r := 0.0
	if boss.has_method("body_radius"):
		body_r = float(boss.call("body_radius"))
	if boss.has_method("hit_spheres"):
		for sp in boss.call("hit_spheres"):
			body_r = maxf(body_r, float((sp as Vector3).z))
	return body_r + PLAYER_BODY_RADIUS


## 落点取球心的哪一侧：沿用玩家当前所在侧，不跨越 BOSS 身体。
func _snap_side(anchor: Vector2) -> float:
	var side := signf(global_position.x - anchor.x)
	if is_zero_approx(side):
		side = signf(attack_dir.x)
	if is_zero_approx(side):
		side = 1.0
	return side


## 把扇形中心对准球心。⚠ 实判的扇形是 `attack_dir` 再旋转 `mid_deg`（第 3 段前刺
## 偏 −11°、半角仅 35°），所以必须反解掉这段旋转；直接令 attack_dir = 朝敌方向会偏出去。
## 这也是弹反追击原来的写法不对的地方（它没反解，段 3 追击天生偏 11°）。
func _aim_at(anchor: Vector2, at: Vector2, mid_deg: float) -> void:
	var to_target: Vector2 = anchor - at
	if to_target.length_squared() <= 0.0001:
		return
	attack_dir = to_target.normalized().rotated(-deg_to_rad(mid_deg))
	if absf(attack_dir.x) > 0.1:
		anim.scale.x = 1.0 if attack_dir.x > 0.0 else -1.0


## 共用求解器：对**一只目标 + 一份扇形**回答「这一击要不要动、该站多远、该瞄哪只球」。
## 只算几何，不改任何状态。与 `_damage_bosses_in_shape` 同源（先过 `_would_hit_boss`）。
## 返回空字典 = 本来就能打到 ⇒ 调用方连朝向都不许多改。
##   step   : 需要补的位移。0 = 纯角度问题，转个腕子就够，人不该动
##   anchor : 该瞄的那只受击球球心。取「所需位移最小」者 —— 所以白捡的转向优先于位移，
##            这条专治宽体 BOSS（脚下球近而角度偏、头侧球远而角度正）
##   stand  : 落点到该球心的水平距离 = 命中上界 − 余量，再垫上防钻身下限
##   room   : stand 是否还在命中上界之内。false = 这只胖到站不进判定，别位移
func _auto_step_solve(boss: Node2D, shape: Dictionary, from: Vector2, stand_floor: float) -> Dictionary:
	if boss == null or not boss.has_method("hit_spheres"):
		return {}
	# 本来就能打到：直接收手，后面的选球逻辑一概不走
	if _would_hit_boss(boss, shape, from):
		return {}
	var reach := float(shape["reach"])
	var best: Dictionary = {}
	var best_step := 1.0e9
	for sp in boss.call("hit_spheres"):
		var sv: Vector3 = sp
		if sv.z <= 0.0:
			continue
		var c: Vector2 = boss.global_position + Vector2(sv.x, sv.y)
		# 命中上界 = reach + **该球自身半径**。不能换成外接半径 hit_radius()：
		# 那含头顶球，赫连霄 ≈93 → 站位 111，普攻只剩 2~3 像素容差（10-28 实测过的坑）。
		var ceiling := reach + sv.z
		var step := maxf(0.0, from.distance_to(c) - (ceiling - MELEE_SNAP_MARGIN))
		if step >= best_step:
			continue
		var stand := maxf(ceiling - MELEE_SNAP_MARGIN, stand_floor)
		best_step = step
		best = {"step": step, "anchor": c, "radius": sv.z, "stand": stand,
				"room": stand <= ceiling - 1.0}
	return best


## 每次起手都尝试，但**只有这一刀原本会落空**才动手，并且按落空原因分开处理。
## 返回 true = 发生了 0.12s 滑步，调用方必须把出伤延后到落地之后，并再校验一次。
## 返回 false 且 `_melee_turned` = 只改了朝向，没位移、没残影。
func _melee_snap_to_target(seg_idx: int) -> bool:
	_melee_snapped = false
	_melee_turned = false
	_snap_target_id = 0
	# 换锋符：这一刀是远程直线剑气，贴身反而会打偏
	if _blade_form_left > 0.0:
		return false
	var shape := _melee_shape(seg_idx)
	var mid_deg := float(shape["mid_deg"])
	var moving := _get_move_dir().length_squared() > 0.0
	# 在所有活 BOSS 里取「需要补的位移最小」的那一只
	var best: Dictionary = {}
	var best_step := 1.0e9
	var best_id := 0
	for raw in get_tree().get_nodes_in_group("boss"):
		# ⚠ 死单位不参与：试炼里 BOSS 尸体不销毁、仍在 "boss" 组
		if BossBase.is_unit_dead(raw) or not is_instance_valid(raw) or not (raw is Node2D):
			continue
		var b := raw as Node2D
		var near_c := _nearest_hit_sphere(b, global_position)
		# 转向门禁与软锁定同一判据：移动中只认前方 ±90°，静止不限
		if not _aim_gate_ok(global_position, near_c - global_position, not moving):
			continue
		var sol := _auto_step_solve(b, shape, global_position, _snap_stand_floor(b))
		# 空 = 这一刀本来就能打到它 ⇒ 什么都不改（用户正在贴身输出时最忌被拉来拉去）
		if sol.is_empty():
			return false
		if float(sol["step"]) < best_step:
			best_step = float(sol["step"])
			best = sol
			best_id = b.get_instance_id()
	if best.is_empty() or best_step > MELEE_SNAP_MAX_STEP:
		return false
	var anchor: Vector2 = best["anchor"]
	# ① 纯角度问题：转向就够了，人一步都不许动
	if best_step <= 0.0:
		_melee_turned = true
		_aim_at(anchor, global_position, mid_deg)
		return false
	# 站不进命中上界（BOSS 身体太厚）就别位移，那是玩家自己该走的位
	if not bool(best["room"]):
		return false
	# ② 距离不够：补到「刚好进判定 + 余量」，而不是走到固定贴脸站位
	var target_pos: Vector2 = anchor + Vector2(_snap_side(anchor) * float(best["stand"]), 0.0)
	_aim_at(anchor, target_pos, mid_deg)
	# tween 直接改坐标，先清残余速度，免得 move_and_slide 落地后把人推偏
	velocity = Vector2.ZERO
	_melee_snapped = true
	_snap_target_id = best_id
	_spawn_dodge_trail()
	# ⚠ 落点**锁死在起手这一帧**算出的值，tween 不再每帧重读 BOSS 位置。旧写法每帧
	#   `_nearest_hit_sphere(live, start_pos)`，而 BOSS 的**招式位移**（虎妖后撤 520、
	#   刀客突进几百 px）正好落在这 0.12s 里 —— 那不是「补一步」，是被 BOSS 拖着走；
	#   且 side 是起手定的，BOSS 一旦穿身而过，落点会算到它另一侧、直接钻进碰撞体。
	#   （弹反追击**必须**继续实时追踪：那里有弹反击退 120px / 0.18s 的既定原因）
	var start_pos := global_position
	var snap_tween := create_tween()
	_snap_tween = snap_tween
	snap_tween.tween_method(func(t: float) -> void:
		global_position = start_pos.lerp(target_pos, t)
		if t >= 0.999:
			# 强制对齐最终落点：出伤的 create_timer 与这条 tween 都是 0.12s，
			# 差一帧就会「刀先落、人还没到」，落地帧钉死位置才不会打空。
			global_position = target_pos
	, 0.0, 1.0, MELEE_SNAP_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return true


## 滑步落地、出伤前一帧的**再校验**：这 0.12s 里 BOSS 会走位，起手锁死的落点可能已经偏。
## 已能命中就就地收手；确实还差就只补「还差的那一段」—— 不再播 tween，因为已经在出伤
## 帧前，再滑 0.12s 这一刀必然过期。
func _melee_snap_recheck(seg_idx: int) -> void:
	if _snap_target_id == 0:
		return
	# ⚠ 先掐掉滑步 tween：它和出伤计时器都是 0.12s，谁先跑完不确定。若让 tween 多跑
	#   一帧，它末帧的 `global_position = target_pos` 会把这里刚补好的位置又拽回
	#   起手的旧落点 —— 探针 ⑦ 实测到「补完位 hits 仍然是 0」。
	if _snap_tween != null and _snap_tween.is_valid():
		_snap_tween.kill()
	_snap_tween = null
	var boss := instance_from_id(_snap_target_id) as Node2D
	_snap_target_id = 0
	if boss == null or not is_instance_valid(boss) or BossBase.is_unit_dead(boss):
		return
	var shape := _melee_shape(seg_idx)
	var sol := _auto_step_solve(boss, shape, global_position, _snap_stand_floor(boss))
	if sol.is_empty() or not bool(sol["room"]):
		return
	var step := float(sol["step"])
	if step > MELEE_SNAP_MAX_STEP:
		return
	var mid_deg := float(shape["mid_deg"])
	if step <= 0.0:
		_aim_at(sol["anchor"], global_position, mid_deg)
		return
	var land: Vector2 = sol["anchor"] + Vector2(_snap_side(sol["anchor"]) * float(sol["stand"]), 0.0)
	global_position = land
	_aim_at(sol["anchor"], land, mid_deg)


## 该功法能否吃「弹反追击位移」：窗口内 + 有资格 + 是**近战物理**招式
## 法术招式与投射物不享受（法术自带远程，不需要贴近）
func _skill_allows_followup_dash(form: Dictionary) -> bool:
	if not (has_buff("parry_followup") and parry_followup_can_dash):
		return false
	var shape := String(form.get("hit_shape", ""))
	if shape == MoveDB.SHAPE_PROJECTILE:
		return false
	# 物理系功法才吃这个位移与增伤
	var sid := String(form.get("skill_id", ""))
	return SkillDB.get_phys_coeff(sid) > 0.0


## 软锁定：附近有 BOSS 且位于前方一定角度内时，攻击方向自动朝向最近的 BOSS
## 软锁定：把 attack_dir 转向最近的 BOSS（锁定范围与命中半径一致，不会锁到打不到的）
## ignore_facing = true 时**不做**「只在攻击方向前方 ±90°」的过滤。
##   移动中攻击用默认值（保留限制，避免自动转身打背后）；
##   静止攻击必须传 true —— 否则玩家站在 BOSS 斜下方、上次移动方向又背对 BOSS 时，
##   锁定会被过滤掉，攻击照旧朝旧方向打，于是"明明贴着 BOSS 却打不到"
func _auto_aim_to_boss(ignore_facing: bool = false) -> void:
	var nearest: Node2D = null
	# 换锋窗口内按剑气射程软锁定，否则「看得到打不到」
	var nearest_dist := _blade_form_range if _blade_form_left > 0.0 else ATTACK_RANGE + 24.0
	for boss in get_tree().get_nodes_in_group("boss"):
		# ⚠ 死单位不参与索敌 / 结算：试炼里 BOSS 尸体不销毁、仍在 "boss" 组
		if BossBase.is_unit_dead(boss):
			continue
		if not is_instance_valid(boss) or not boss is Node2D:
			continue
		var to_boss: Vector2 = boss.global_position - global_position
		var d := to_boss.length()
		# 前方角度限制：仅攻击方向前方 ±90° 内的 BOSS 才参与软锁定，避免"背后误锁"
		if not _aim_gate_ok(global_position, to_boss, ignore_facing):
			continue
		if d < nearest_dist:
			nearest_dist = d
			nearest = boss
	if nearest:
		var dir := (nearest.global_position - global_position)
		if dir.length_squared() > 0.0001:
			attack_dir = dir.normalized()


## 转向门禁的**唯一**判据：移动中只认攻击方向前方 ±90°，静止时不限角度。
## ⚠ 软锁定 / 平A 吸附 / 弹反追击的转向必须全部走这里。吸附原先自己另写了一句
##   `attack_dir = 朝敌方向`，绕过了这道门禁 —— 按住方向键、目标在侧后方时会
##   触发一次幅度不设上限的强行转身，玩家读作「我没让它转，它自己转过去了」。
## ignore_facing 的语义沿用 _auto_aim_to_boss：静止时玩家只能用上一次的朝向，
## 若那次朝向恰好背对目标，加限制会让锁定失效、导致贴着目标打空。
func _aim_gate_ok(from: Vector2, to_target: Vector2, ignore_facing: bool) -> bool:
	if ignore_facing or to_target.length_squared() <= 0.0001:
		return true
	return attack_dir.dot(to_target.normalized()) >= 0.0


## 挥刀特效：弧形刀光（美化：渐变月牙 + 拖尾）
## swing_back 为 true 时从另一侧挥回；is_finisher 为 true 时是终结技（更大更亮）
##
## 美术替换点：刀光外观由 ArtDB.EFFECTS 的 "slash_normal" / "slash_finisher" 决定。
## 未接入贴图时自动回退为程序化月牙绘制（与改造前外观一致）。
func _spawn_slash_effect(swing_back: bool, is_finisher: bool = false) -> void:
	# 换锋窗口内不画近战刀光 / 武器扫弧：剑气在命中帧由 _spawn_blade_form_qi() 出
	if _blade_form_left > 0.0:
		return
	var effect_id := "slash_finisher" if is_finisher else "slash_normal"
	# 半径沿用本脚本的范围常量，保证与攻击判定一致（换图后判定不受影响）
	var extra := FINISHER_RANGE_MULT if is_finisher else 1.0

	# 只有刀光「有内容」时才生成节点：贴图已接 或 fallback 是实绘
	# 现在两者都没配（攻击改由御剑武器表现），跳过可省一个空节点
	var scfg := ArtDB.get_effect(effect_id)
	var has_visual := String(scfg.get("texture", "")) != "" \
		or String(scfg.get("fallback_kind", "none")) != "none"
	if has_visual:
		FxPlayer.spawn(self, effect_id, {
			# 从身体中心发出，而不是脚底原点（角色贴图越高差别越明显）
			"position": _body_center(),
			"rotation": attack_dir.angle(),
			"swing_back": swing_back,
			"radius": (ATTACK_RANGE + 14.0) * extra,
			"lifetime": _finisher_attack_time() if is_finisher else attack_time,
		})

	# 御剑武器：按连段取不同轨迹（上劈 / 上撩 / 前刺），段间不回位
	if weapon != null:
		weapon.sweep(attack_dir, _combo_segment(), is_finisher)

	# 武器挥砍：以身体为中心扫过一道弧（武器贴图绕角色转，不是原地自转）
	# 仅当 ArtDB 的 weapon_slash 填了 texture 时才生成 —— 没填就完全跳过，不影响现有刀光
	if ArtDB.effect_has_texture("weapon_slash"):
		var wcfg := ArtDB.get_effect("weapon_slash")
		var sweep_deg := float(wcfg.get("sweep_angle_deg", 120.0))
		var aim_deg := rad_to_deg(attack_dir.angle())
		# 正向：从「瞄准方向左侧半角」扫到右侧半角；反向则相反
		var start_deg: float = aim_deg + sweep_deg * 0.5 if swing_back else aim_deg - sweep_deg * 0.5
		FxPlayer.spawn(self, "weapon_slash", {
			"position": _body_center(),
			"rotation": deg_to_rad(start_deg),
			"sweep_deg": -sweep_deg if swing_back else sweep_deg,
			"lifetime": _finisher_attack_time() if is_finisher else attack_time,
		})


## 创建御剑武器。未配贴图时立刻释放 —— 保证「没美术 = 没这个节点」，不影响旧行为
func _setup_weapon() -> void:
	weapon = WeaponOrbit.new()
	weapon.name = "WeaponOrbit"
	add_child(weapon)
	if not weapon.has_weapon():
		weapon.queue_free()
		weapon = null


## 按当前装备的武器切换外观：模板里的 weapon_visual 为空就用默认 player_weapon
## 于是「换武器不换攻击表现」，要换表现才给那把武器配专属的 visual id
func _sync_weapon_visual() -> void:
	if weapon == null:
		return
	var vis_id := "player_weapon"
	var w := CharacterData.get_equipped("weapon")
	if not w.is_empty():
		var vid := ItemDB.weapon_visual_for(w)
		if vid != "":
			vis_id = vid
			if String(w.get("weapon_visual", "")) == "":
				w["weapon_visual"] = vid
	if weapon.weapon_id != vis_id:
		weapon.set_weapon(vis_id)


## 取当前连段对应的武器轨迹配置（第 1/2/3 段各不同，见 ArtDB 的 combo_sweeps）
## ⚠ 必须在 attack_combo 自增**之前**调用，否则段号会错位
func _combo_segment() -> Dictionary:
	# 优先用当前武器条目里的自定义轨迹；没配就退回全局默认（所有武器共用同一套攻击）
	var segs: Array = []
	if weapon != null:
		segs = ArtDB.get_visual(weapon.weapon_id).get("combo_sweeps", [])
	if segs.is_empty():
		segs = ArtDB.WEAPON_COMBO_SWEEPS
	var idx := attack_combo % ATTACK_COMBO_MAX
	if idx >= 0 and idx < segs.size():
		return segs[idx]
	return {}


## 身体视觉中心（相对本节点原点）：特效、飘字应当出现在这里，而不是脚底
## 未接入贴图 / 节点缺失时给一个保守值（约半个身位），保证不会贴地
func _body_center() -> Vector2:
	if skin != null:
		return skin.body_center()
	return Vector2(0.0, -16.0)


## 本体最高点在局部坐标里的 Y（负值），头顶星 / 血条类读数用
func head_top_y() -> float:
	if skin == null or not is_instance_valid(skin):
		return -68.0
	var y := skin.position.y + skin.top_extent()
	var holder := skin.get_parent()
	if holder is Node2D:
		y += (holder as Node2D).position.y
	if anim != null:
		y *= anim.scale.y
	return y


## 眩晕星锚点：头顶再往上留出星环的呼吸位
func stun_fx_anchor_y() -> float:
	return head_top_y() - 52.0


## 是否正被眩晕（行动锁死那类硬控；死亡不算）
func is_stunned() -> bool:
	return not is_dead and has_debuff("stun")


## 结束攻击（时间到 / 被闪避、弹刀取消后摇）
func _end_attack() -> void:
	is_attacking = false
	attack_cancel_available = false
	_attack_hit_timer = -1.0
	# 吸附的「落地再校验」还没跑就被取消（闪断 / 弹刀打断）时别把目标 id 留下一次
	_snap_target_id = 0
	_snap_tween = null
	# 攻击动作收尾：正常到点时动画已播完（时长按后摇算），
	# 被闪避/弹刀**中途取消**时靠这句立刻切回待机，避免「人在闪避、手还在放招」
	if skin != null:
		skin.cancel_one_shot()


# ===== 符纸施法（2026-10-24 用户定：使用符纸时原地施法 2 秒）=====

## 开始施符：锁住全部操作并播施法动作。返回 false = 已死 / 正在施法。
## 效果不在这里结算 —— 到点发 talisman_cast_finished，由 BattleWheel 扣道具与生效。
func begin_talisman_cast(item_id: String) -> bool:
	if is_dead or is_casting_talisman:
		return false
	is_casting_talisman = true
	emit_noise()
	_talisman_cast_left = TALISMAN_CAST_TIME
	_talisman_cast_item = item_id
	# 施法优先：打断攻击 / 闪避 / 弹刀 / 技能前冲 / 蓄力格挡
	if is_attacking:
		_end_attack()
	is_dodging = false
	is_parrying = false
	parry_stance_timer = 0.0
	auto_parry_timer = 0.0
	_skill_dash_timer = 0.0
	_skill_dash_dir = Vector2.ZERO
	_skill_dash_speed = 0.0
	_skill_dash_origin = Vector2.INF
	_skill_face_lock = 0.0
	_counter_charging = false
	_finish_counter_ward()
	_counter_skill = ""
	velocity = Vector2.ZERO
	if skin != null:
		# 未来接入专门的施法序列帧时，只要在 SpriteFrames 里加 "cast" 就会自动优先使用
		var cast_anim := "cast" if skin.has_animation("cast") else "attack"
		skin.play_one_shot(cast_anim, TALISMAN_CAST_TIME)
	var item_name := String(ItemDB.get_consumable(item_id).get("talisman_name", "符纸"))
	_show_float_text("施符 · %s" % item_name, UIKit.C_HUD_MANA)
	return true


## 施法计时：到点发完成信号（暂停时随物理帧一起暂停）
func _tick_talisman_cast(delta: float) -> void:
	if not is_casting_talisman:
		return
	_talisman_cast_left -= delta
	if _talisman_cast_left > 0.0:
		return
	is_casting_talisman = false
	_talisman_cast_left = 0.0
	var item_id := _talisman_cast_item
	_talisman_cast_item = ""
	if item_id != "":
		talisman_cast_finished.emit(item_id)


## 死亡 / 重开时中断施法（不发完成信号 = 效果不结算、符纸不消耗）
func cancel_talisman_cast() -> void:
	is_casting_talisman = false
	_talisman_cast_left = 0.0
	_talisman_cast_item = ""


## 普通攻击命中结算：扇形几何判定，不依赖物理重叠，命中更可靠
## 伤害统一走 CharacterData 的物理伤害公式：
##   伤害 = 攻击力（基础 + 装备加成）× 兵器系数 × 招式倍率 × 随机浮动
## 因此「攻击力」不是某一击的固定伤害，而是作用于全部物理攻击的成长乘区。
# ===== 五、普攻与命中判定（普攻 / 功法共用同一套判定）=====
func _perform_attack_hit() -> void:
	# 换锋符：普攻判定整体换成远程直线穿透剑气（不改伤害系数）
	if _blade_form_left > 0.0:
		_perform_blade_form_hit()
		return
	# 判定适配「武器实际扫过的范围」：
	#   半径 = 剑尖触达距离；半角 = 本段扫角的一半（+ 余量，剑有宽度）
	# 这样三段连击的手感各不相同：劈/撩是大扇形，前刺是长而窄的锥形
	# 形状计算统一走 _melee_shape：起手的「吸附预检」和这里必须用同一份参数，
	# 否则会出现「预检说打得到、实际砍空」（或吸进去了还是打空）。
	# ⚠ 段号仍按原口径读**已自增的** attack_combo（_combo_segment 的原有行为），
	#   这次重构不改判定结果，只把算式收进一个函数。
	var shape := _melee_shape(attack_combo % ATTACK_COMBO_MAX)
	var hit_dir := shape["dir"] as Vector2
	var hit_radius := float(shape["reach"])
	var half_angle := float(shape["half_angle"])
	# 带不带弹刀增伤在这里就定下来（次数型 buff：命中后马上消费）
	var dmg := CharacterData.calc_physical_damage(is_finisher_attack, has_buff("parry_power"))
	var hit_any := _damage_bosses_in_shape(hit_dir, hit_radius, half_angle, dmg, "physical")
	# 新手指引：只统计「普攻打中」，功法走自己的 skill_used（不混在一起）
	if hit_any:
		Tutorial.note("attack_hit")
	# 纸错剑（叠纸掉落）：终结段在每个被打中的目标**身后 120** 再落一段 60%。
	# 现游戏所有普攻都只有一个落点 —— 这件给的是「前后夹击」这个用途，不是攻击力。
	if is_finisher_attack and CharacterData.is_wearing("eq_zhicuo_jian"):
		_zhicuo_second_landing(hit_dir, hit_radius, dmg)
	# 满雷势：每一记平A（含打空）都召一道协同雷击
	if _thunder_full_active() and not is_dead:
		_trigger_thunder_coop()
	# 满剑意 · 剑气随身（肉鸽卡）：平A再附一道 0.5× 法强的剑气，口径与协同雷击对齐
	if RogueRun.has_flag("intent_attack_qi") and not is_dead \
			and sword_intent >= _sword_intent_max():
		_trigger_intent_slash()
	if not hit_any:
		return
	# 每一段命中都轻推镜头：第一段 1.5%、第二段 2.2%、终结段 4%
	_attack_camera_punch()
	# 终结段压帧：比普通命中多顿一倍多，把「最后一刀」的重量压出来；
	# 强制触发 —— 终结段紧接第二段落地时，0.12s 节流会把这一下吃掉
	if is_finisher_attack:
		GameState.trigger_hit_stop(FINISHER_HIT_STOP, true)
	else:
		GameState.trigger_hit_stop()
	GameState.play_sfx("attack_hit")
	# 材质音叠在「唰」下面：低频+噪声的一记实心命中
	GameState.play_sfx("attack_impact")
	_consume_parry_damage_buff()


## 满雷势 · 协同雷击：平A时在身前最近目标处引一道雷（法术 ×0.5）
## 无目标时只落雷不出伤；落点 62px 内的敌人一起吃。
func _trigger_thunder_coop() -> void:
	if is_dead or not _thunder_full_active():
		return
	var target := _thunder_coop_target()
	var pos := global_position + attack_dir * 120.0
	if target != null:
		pos = target.global_position
	SkillFx.play_at_strike(self, "fx_thunder_coop",
		{"range": THUNDER_COOP_RADIUS, "hit_shape": MoveDB.SHAPE_CIRCLE},
		Vector2.RIGHT, pos)
	var dmg := CharacterData.spell_attack() * THUNDER_COOP_COEF \
		* (1.0 + RogueRun.stat("coop_pct") / 100.0)
	var coop_radius := THUNDER_COOP_RADIUS * (1.0 + RogueRun.stat("coop_range") / 100.0)
	var struck: Array = []
	for raw in _array_enemy_units():
		if not is_instance_valid(raw) or not raw is Node2D:
			continue
		var b := raw as Node2D
		if _enemy_is_dead(b):
			continue
		if b.global_position.distance_to(pos) > coop_radius + 18.0:
			continue
		_deal_direct_damage(b, dmg, "elemental", "thunder",
			THUNDER_COOP_SKILL_ID, false)
		struck.append(b)
	# 肉鸽「协雷·连」：从**没被主雷劈到**的敌人里再找最近的补一刀（主模式 stat 恒 0）
	var chain := int(RogueRun.stat("coop_chain"))
	for _step in chain:
		var best: Node2D = null
		var best_d := INF
		for raw in _array_enemy_units():
			if not is_instance_valid(raw) or not (raw is Node2D):
				continue
			if struck.has(raw) or _enemy_is_dead(raw as Node2D):
				continue
			var d := (raw as Node2D).global_position.distance_to(pos)
			if d < best_d and d <= coop_radius + 150.0:
				best_d = d
				best = raw as Node2D
		if best == null:
			break
		_deal_direct_damage(best, dmg * 0.6, "elemental", "thunder",
			THUNDER_COOP_SKILL_ID, false)
		struck.append(best)


## 协同雷击的目标：身前 85° / 320px 内最近的活着的敌人
func _thunder_coop_target() -> Node2D:
	var best: Node2D = null
	var best_d := THUNDER_COOP_RANGE
	var facing := attack_dir.normalized() if attack_dir.length_squared() > 0.0001 else Vector2.RIGHT
	var min_dot := cos(deg_to_rad(THUNDER_COOP_HALF_ANGLE))
	for raw in _array_enemy_units():
		if not is_instance_valid(raw) or not raw is Node2D:
			continue
		var b := raw as Node2D
		if _enemy_is_dead(b):
			continue
		var to := b.global_position - global_position
		var d := to.length()
		if d > THUNDER_COOP_RANGE:
			continue
		if d > 1.0 and facing.dot(to / d) < min_dot:
			continue
		if d < best_d:
			best_d = d
			best = b
	return best


## 满剑意 · 剑气随身（肉鸽卡 s_jq_atk）：平A时在身前最近目标处补一道剑气。
## 系数走 0.5× 法强、金属性、独立 skill_id —— 与「满雷势协同雷」同一套附带型出手的口径。
const QI_SLASH_COEF := 0.50
const QI_SLASH_RANGE := 300.0
const QI_SLASH_HALF_ANGLE := 80.0
const QI_SLASH_RADIUS := 58.0
const QI_SLASH_SKILL_ID := "skill_sword_qi_slash"


## 一记平A 落一道：打空（身前没敌人）就不出手，不浪费演出
func _trigger_intent_slash() -> void:
	if is_dead or not RogueRun.has_flag("intent_attack_qi"):
		return
	if sword_intent < _sword_intent_max():
		return
	var target := _intent_slash_target()
	if target == null:
		return
	var pos: Vector2 = target.global_position
	var dir := facing_dir_to(pos)
	SkillFx.play_at_strike(self, "fx_sword_qi_slash",
		{"range": QI_SLASH_RADIUS, "hit_shape": MoveDB.SHAPE_CIRCLE}, dir, pos)
	var dmg := CharacterData.spell_attack() * QI_SLASH_COEF
	for raw in _array_enemy_units():
		if not is_instance_valid(raw) or not (raw is Node2D):
			continue
		var b := raw as Node2D
		if _enemy_is_dead(b):
			continue
		if b.global_position.distance_to(pos) > QI_SLASH_RADIUS + 18.0:
			continue
		_deal_direct_damage(b, dmg, "elemental", "metal", QI_SLASH_SKILL_ID, false)


## 剑气落点：身前 80° / 300px 内最近的活敌人（比协同雷收一档，贴着普攻自身射程）
func _intent_slash_target() -> Node2D:
	var best: Node2D = null
	var best_d := QI_SLASH_RANGE
	var facing := attack_dir.normalized() if attack_dir.length_squared() > 0.0001 else Vector2.RIGHT
	var min_dot := cos(deg_to_rad(QI_SLASH_HALF_ANGLE))
	for raw in _array_enemy_units():
		if not is_instance_valid(raw) or not (raw is Node2D):
			continue
		var b := raw as Node2D
		if _enemy_is_dead(b):
			continue
		var to := b.global_position - global_position
		var d := to.length()
		if d > QI_SLASH_RANGE:
			continue
		if d > 1.0 and facing.dot(to / d) < min_dot:
			continue
		if d < best_d:
			best_d = d
			best = b
	return best


func _enemy_is_dead(node: Node) -> bool:
	if node.has_method("is_dead"):
		return bool(node.call("is_dead"))
	var raw = node.get("is_dead")
	return raw == true


## 命中推镜：按段号给不同幅度（1.5% / 2.2% / 4%），再缓慢回到玩家当前 zoom。
## 只动 Camera2D.zoom，HUD 在 CanvasLayer 上不受影响。
const ATTACK_ZOOM_MULT := [1.008, 1.012, 1.022]
const ATTACK_ZOOM_IN := [0.04, 0.045, 0.05]
const ATTACK_ZOOM_OUT := [0.16, 0.20, 0.24]
## 终结段顿帧时长（真实秒）：普通命中 0.05，终结段明显更长
const FINISHER_HIT_STOP := 0.09
var _attack_zoom_tween: Tween
var _zoom_before_punch := -1.0

func _attack_camera_punch() -> void:
	if camera == null:
		return
	# 演出镜头（满剑意一剑开天拉远）期间普攻推镜让路，避免两套镜头打架
	if _cinematic_zoom_active:
		return
	if _attack_zoom_tween != null and _attack_zoom_tween.is_valid():
		_attack_zoom_tween.kill()
	if _zoom_before_punch < 0.0:
		_zoom_before_punch = camera.zoom.x
	var idx := clampi(_attack_seg_idx, 0, ATTACK_ZOOM_MULT.size() - 1)
	var base := _zoom_before_punch
	var punch := base * float(ATTACK_ZOOM_MULT[idx])
	_attack_zoom_tween = create_tween()
	# 顿帧期间镜头照常推：否则终结段先冻住 0.09s、冻结结束才开始推镜，
	# 冲击会拆成两拍；用真实时间跑，顿帧那一瞬镜头已经顶出去了
	_attack_zoom_tween.set_ignore_time_scale(true)
	_attack_zoom_tween.tween_property(camera, "zoom", Vector2(punch, punch),
		float(ATTACK_ZOOM_IN[idx])).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_attack_zoom_tween.tween_property(camera, "zoom", Vector2(base, base),
		float(ATTACK_ZOOM_OUT[idx])).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_attack_zoom_tween.tween_callback(func() -> void:
		_zoom_before_punch = -1.0)


# ===== 演出镜头（满剑意一剑开天：拉远 / 收回）=====
## 只给巨剑形态用：前摇把视野拉远，落地稍等再缓回；期间普攻推镜让路。
var _cinematic_zoom_active := false
var _cinematic_zoom_tween: Tween

func cinematic_zoom_out(target_zoom: float, time: float) -> void:
	if camera == null:
		return
	if _attack_zoom_tween != null and _attack_zoom_tween.is_valid():
		_attack_zoom_tween.kill()
	_zoom_before_punch = -1.0
	_cinematic_zoom_active = true
	if _cinematic_zoom_tween != null and _cinematic_zoom_tween.is_valid():
		_cinematic_zoom_tween.kill()
	_cinematic_zoom_tween = create_tween()
	_cinematic_zoom_tween.set_ignore_time_scale(true)
	_cinematic_zoom_tween.tween_property(camera, "zoom", Vector2(target_zoom, target_zoom),
		maxf(time, 0.01)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func cinematic_zoom_back(time: float) -> void:
	if _cinematic_zoom_tween != null and _cinematic_zoom_tween.is_valid():
		_cinematic_zoom_tween.kill()
	_zoom_before_punch = -1.0
	if camera == null:
		_cinematic_zoom_active = false
		return
	_cinematic_zoom_tween = create_tween()
	_cinematic_zoom_tween.set_ignore_time_scale(true)
	_cinematic_zoom_tween.tween_property(camera, "zoom", Vector2.ONE,
		maxf(time, 0.01)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cinematic_zoom_tween.tween_callback(func() -> void:
		_cinematic_zoom_active = false)


## 中断演出镜头：立刻回到 1.0，不走补间（死亡 / 重开用）
func _cancel_cinematic_zoom() -> void:
	_cinematic_zoom_active = false
	if _cinematic_zoom_tween != null and _cinematic_zoom_tween.is_valid():
		_cinematic_zoom_tween.kill()
	_zoom_before_punch = -1.0
	if camera != null:
		camera.zoom = Vector2.ONE


## 对「扇形 / 圆形」范围内的所有 BOSS 逐一结算伤害，返回是否命中至少一个
##   dir        攻击朝向（圆形判定时忽略）
##   reach      有效半径（像素）
##   half_angle 扇形半角（弧度）
##   dmg        每只 BOSS 承受的伤害
##   kind       伤害类型：physical / elemental
##   elem       五行属性（可空）
##   circle     true = 圆形范围，不看方向
## 普攻与功法共用这一份判定，保证「看到多大就打多大」的手感一致。
func _damage_bosses_in_shape(dir: Vector2, reach: float, half_angle: float, dmg: float,
		kind: String, elem: String = "", circle: bool = false, skill_id: String = "",
		knockback: float = 0.0, origin: Variant = null,
		calamity_reaction_tag: String = "") -> bool:
	var from: Vector2 = global_position if origin == null else Vector2(origin)
	var boss_hit := false
	var hit_any := false
	for boss in get_tree().get_nodes_in_group("boss"):
		# ⚠ 死单位不参与索敌 / 结算：试炼里 BOSS 尸体不销毁、仍在 "boss" 组
		if BossBase.is_unit_dead(boss):
			continue
		if not is_instance_valid(boss) or not boss is Node2D or not boss.has_method("take_damage"):
			continue
		# 受击球：横长体型的 BOSS（虎妖 277 长 × 80 厚）会返回多个，
		# 任一相交即命中。默认实现读场景里所有 CollisionShape2D，人形 BOSS 仍是单球。
		# ⚠ 每个球必须**独立**做距离与夹角判定：只用身体中心算夹角的话，
		#   站在虎妖头侧（离中心 130px）会被判成「不在正面扇形里」而漏打 ——
		#   那正是「明明贴着虎头砍却不算命中」的另一半原因。
		var spheres: Array = [Vector3(0.0, 0.0, 0.0)]
		if boss.has_method("hit_spheres"):
			spheres = boss.call("hit_spheres")
		var hit_this_boss := false
		for sp in spheres:
			var sv: Vector3 = sp
			if sv.z <= 0.0:
				continue
			var to_sp: Vector2 = boss.global_position + Vector2(sv.x, sv.y) - from
			var dist := to_sp.length()
			if dist > reach + sv.z:
				continue
			# 距离极近（几乎重叠）时直接判定命中，避免方向归一化误差；
			# 其余情况用「朝向夹角」过滤，超出扇形半角的不算命中
			if not circle and dist > 1.0 and dir.dot(to_sp / dist) < cos(half_angle):
				continue
			hit_this_boss = true
			break
		if not hit_this_boss:
			continue
		var final_dmg := _yinyang_modify_damage(boss, kind, dmg, skill_id)
		final_dmg = _rogue_modify_damage(final_dmg, boss, kind, skill_id)
		# 普攻（不带功法）：两仪护体只认一半削盾量，先通知再扣血（同一帧内消费）
		if skill_id == "" and boss.has_method("notify_normal_attack_hit"):
			boss.call("notify_normal_attack_hit")
		DamageMeter.push(_meter_tag(skill_id))
		boss.take_damage(final_dmg, self, kind, elem)
		boss_hit = true
		_note_thunder_skill_hit(boss, skill_id, elem)
		_apply_player_skill_debuff(boss, skill_id)
		_rogue_apply_hit_debuff(boss, skill_id)
		_rogue_try_lei_chain(boss, elem, skill_id)
		if calamity_reaction_tag != "":
			_try_calamity_reaction(boss, calamity_reaction_tag, dmg)
		_try_arm_sun_nova(boss, skill_id)
		notify_calamity_element_hit(boss, elem, skill_id)
		if knockback > 0.0 and boss.has_method("take_knockback"):
			var away := (boss as Node2D).global_position - from
			if away.length_squared() > 1.0:
				boss.call("take_knockback", away.normalized() * knockback)
		hit_any = true

	# 插地剑（剑客天剑阵 / 三角封绝）：玩家攻击一次即击碎
	# ⚠ 单独一个组，不并进 "boss" —— 它们没有血条、不该被技能自动瞄准、
	#   也不该触发 BOSS 相关的逻辑，只是「场上可破坏物」
	for sw in get_tree().get_nodes_in_group("breakable_sword"):
		if not is_instance_valid(sw) or not sw is Node2D or not sw.has_method("take_hit"):
			continue
		var focal := _breakable_hit_point(sw)
		var extra := _breakable_radius(sw)
		var to_sw: Vector2 = focal - from
		var sw_dist := to_sw.length()
		if sw_dist > reach + extra:
			continue
		if not circle and sw_dist > 1.0 and dir.dot(to_sw / sw_dist) < cos(half_angle):
			continue
		sw.take_hit(dmg)
		hit_any = true

	# 突进斩穿过了目标：末端扇形/直线/圆形已经指向身后，打不到刚越过的 BOSS。
	# 本段起手位置再判一次（只对 move_forward 招式；命中一次就消费起点，避免多段重复吃）。
	if origin == null and skill_id != "":
		var is_dash_skill := float(SkillDB.get_skill_form(skill_id).get("move_forward", 0.0)) > 0.0
		if is_dash_skill and boss_hit:
			_skill_dash_origin = Vector2.INF
		elif is_dash_skill and _skill_dash_origin != Vector2.INF:
			var dash_from := _skill_dash_origin
			_skill_dash_origin = Vector2.INF
			hit_any = _damage_bosses_in_shape(dir, reach, half_angle, dmg, kind, elem,
				circle, skill_id, knockback, dash_from) or hit_any
	return hit_any


## 可破坏物（阵旗）的受击点：有 hit_point() 就用它（旗面中心），否则按原点
func _breakable_hit_point(sw: Node) -> Vector2:
	if sw.has_method("hit_point"):
		return Vector2(sw.call("hit_point"))
	return (sw as Node2D).global_position


## 可破坏物（阵旗）的受击半径：没有该属性的旧可破坏物按 0
func _breakable_radius(sw: Node) -> float:
	var raw = sw.get("hit_radius")
	return float(raw) if raw != null else 0.0


## 对「矩形长条」范围内的所有 BOSS 逐一结算伤害，返回是否命中至少一个
##   dir     攻击朝向（矩形长度方向，原点在角色中心）
##   length  矩形长度（前方，像素）
##   width   矩形宽度（像素，以 dir 为轴居中）
## 一剑开天·满层专用（前方 1000 × 160）。几何与 _damage_bosses_in_shape 同一套
## 「到 BOSS 边缘」容差，只是把扇形夹角判定换成沿轴/侧向的正交投影判定。
func _damage_bosses_in_rect(dir: Vector2, length: float, width: float, dmg: float,
		kind: String, elem: String = "", skill_id: String = "") -> bool:
	var axis := dir.normalized()
	var side := Vector2(-axis.y, axis.x)   # 轴的左侧法向
	var half_w := width * 0.5
	var hit_any := false
	for boss in get_tree().get_nodes_in_group("boss"):
		# ⚠ 死单位不参与索敌 / 结算：试炼里 BOSS 尸体不销毁、仍在 "boss" 组
		if BossBase.is_unit_dead(boss):
			continue
		if not is_instance_valid(boss) or not boss is Node2D or not boss.has_method("take_damage"):
			continue
		# 同扇形判定：逐个受击球做正交投影，任一落进长条即命中
		var spheres: Array = [Vector3(0.0, 0.0, 0.0)]
		if boss.has_method("hit_spheres"):
			spheres = boss.call("hit_spheres")
		var rect_hit := false
		for sp in spheres:
			var sv: Vector3 = sp
			if sv.z <= 0.0:
				continue
			var rel: Vector2 = boss.global_position + Vector2(sv.x, sv.y) - global_position
			var fwd := rel.dot(axis)
			var lat := absf(rel.dot(side))
			if fwd < -sv.z or fwd > length + sv.z:
				continue
			if lat > half_w + sv.z:
				continue
			rect_hit = true
			break
		if not rect_hit:
			continue
		var final_dmg := _yinyang_modify_damage(boss, kind, dmg, skill_id)
		final_dmg = _rogue_modify_damage(final_dmg, boss, kind, skill_id)
		if skill_id == "" and boss.has_method("notify_normal_attack_hit"):
			boss.call("notify_normal_attack_hit")
		DamageMeter.push(_meter_tag(skill_id))
		boss.take_damage(final_dmg, self, kind, elem)
		_note_thunder_skill_hit(boss, skill_id, elem)
		notify_calamity_element_hit(boss, elem, skill_id)
		hit_any = true

	# 插地剑（剑客天剑阵 / 三角封绝）：矩形扫过即击碎（不给半径容差，与扇形口径一致）
	for sw in get_tree().get_nodes_in_group("breakable_sword"):
		if not is_instance_valid(sw) or not sw is Node2D or not sw.has_method("take_hit"):
			continue
		var focal := _breakable_hit_point(sw)
		var extra := _breakable_radius(sw)
		var to_sw: Vector2 = focal - global_position
		if to_sw.dot(axis) < -extra or to_sw.dot(axis) > length + extra:
			continue
		if absf(to_sw.dot(side)) > half_w + extra:
			continue
		sw.take_hit(dmg)
		hit_any = true
	return hit_any

## 受击入口：所有打到玩家的伤害都从这里进
##   - amount      伤害数值（已含攻击方倍率，这里还要扣玩家抗性）
##   - attack_kind 攻击类型：physical_melee / physical_projectile / elemental / …
##   - source      伤害来源节点（用于僵直、反弹、击退方向）
##   - element     五行属性（可空），非空时额外吃该属性抗性
## 处理顺序：弹刀 → 闪避无敌 → 扣抗性结算，先判定的先生效。
## 弹刀分两种：主动弹刀窗口（`is_parrying`）与自动弹刀守势窗口（完美弹反后 1.2 秒，
## 站着不动就不按键也能弹，见 `auto_parry_timer`）。
## ⚠ 2026-10-17 取消的是「按下后连续自动再弹」，不要和自动弹刀混为一谈。
# ===== 六、受击入口：弹刀 → 闪避 → 扣抗性 =====
func take_damage(amount: float, attack_kind: String, source: Node = null, element: String = "") -> void:
	if is_dead:
		return
	# 光愈符：无敌帧（优先级最高 —— 连判词都不该记一笔挨打）
	if _run_tal_invuln_left > 0.0:
		_hit_negated_timer = DEBUFF_NEGATE_WINDOW
		return
	# 判词·禁攻：BOSS 一出手就记一笔（即使这一下被弹反 / 闪避，也算“出手”）
	if source != null and is_instance_valid(source):
		var src_boss := _source_boss(source)
		if src_boss != null:
			_boss_attack_recent = 1.5
			if _law_target == src_boss:
				_law_violate("verdict_no_attack")

	# 纳势反击「格挡」判定：**只挡物理**（近战/投掷），法术照吃全额且不计次数
	# 格挡期间**不受无敌帧限制** —— 每一段伤害都要计入受击次数（这是格挡的核心收益）
	# 两仪·倒悬是另一套规则：物理与术法都进判定，同色全额奉还、异色破势反噬
	var warding := _counter_charging and _counter_yinyang_ward
	var blocking := warding or (_counter_charging and attack_kind.begins_with("physical"))
	if not blocking and invincible_timer > 0.0:
		_hit_negated_timer = DEBUFF_NEGATE_WINDOW
		return
	if blocking:
		if warding:
			var incoming := YINYANG_YANG if attack_kind.begins_with("physical") else YINYANG_YIN
			if _yinyang_unlocked and incoming == yinyang_polarity:
				_counter_hits += 1
				_absorb_yinyang_ward(incoming)
				_hit_negated_timer = DEBUFF_NEGATE_WINDOW
				return
			_break_yinyang_ward()
			amount *= SkillDB.YINYANG_WARD_BREAK_MULT
		else:
			_counter_hits += 1
			amount *= (1.0 - _counter_block)

	# 镜返架势：第一次打过来的法术被镜面挡下并 100% 反弹（一次性）
	if _mirror_try_return(amount, attack_kind, source, element):
		return

	# 弹刀判定：仅物理近战/物理投掷可弹，且必须是玩家自己按出来的弹刀窗口
	if is_parrying and _is_parryable(attack_kind):
		_hit_negated_timer = DEBUFF_NEGATE_WINDOW
		_on_parry_success(attack_kind, source)
		return

	# 自动弹刀判定：完美弹刀后的守势窗口内，**站着不动、也没主动攻击** → 不按键也弹开
	# 1.2 秒内不限次数；窗口由玩家自己移动或出手打断（见 _tick_cooldowns / _start_attack / _cast_skill）
	if auto_parry_timer > 0.0 and _is_parryable(attack_kind):
		_hit_negated_timer = DEBUFF_NEGATE_WINDOW
		_on_parry_success(attack_kind, source, true)
		return

	# 闪避无敌判定
	if is_dodging:
		# 极限闪避判定
		if dodge_timer >= DODGE_TIME - PERFECT_DODGE_WINDOW:
			_trigger_perfect_dodge()
		_hit_negated_timer = DEBUFF_NEGATE_WINDOW
		return

	# 抗性减免：物抗管物理、法抗+五行抗性管法术（统一走 DamageCalc）
	var mitigated := float(DamageCalc.incoming(amount, self, attack_kind, element).get("amount", amount))
	# 暗属性 → 挂「蚀」（减免被打穿 + 减疗 90%）。放在减免之后：
	# 堆抗性能把伤害压低，但不该顺便免疫整个暗体系。
	if element == AttributeDB.DARK:
		try_dark_erosion()
	# 蚀甲锥：护体类减伤减半（只削减伤层，抗性与易伤照常）
	var shred := debuff_guard_shred()
	# 石附符：减伤按当前品阶，之后扣一次可挡次数
	# ⚠ 石附符是符箓：蚀甲锥只削法宝/守阵护体，不削符箓，避免两套系统互相拆台
	var stone_hit := _talisman_stone_left > 0.0
	if stone_hit:
		mitigated *= (1.0 - _talisman_stone_reduce)
	# 易伤（阵伤）：抗性之后乘一档
	mitigated *= debuff_damage_taken_mult()
	# 太极盘·太极护体：物理/法术一起减（放在抗性之后，读作"最终伤害再减 30%"）
	if _taiji_guard_left > 0.0:
		mitigated *= (1.0 - _taiji_guard_pct * (1.0 - shred))
	# 叠掩（叠纸玩家侧）：护身纸的首次受击 -60%（一次性，扣完等下次叠掩）
	mitigated *= _fold_shroud_mult()
	# 折痕佩（叠纸掉落）：挨这一下就把「折位」窗口打开 0.3 秒（见 _zhehen_fold_escape）
	if CharacterData.is_wearing("eq_zhehen_pei"):
		_zhehen_window = ZHEHEN_WINDOW
	# 玩家守旗：任意一面存活 → 受伤 -15%
	if _array_guard_alive():
		mitigated *= (1.0 - SkillDB.ARRAY_GUARD_REDUCTION * (1.0 - shred))
	# 封阵·四象（守牢）：四跳期间受到的伤害 -70%
	if _array_seal_guard_left > 0.0:
		mitigated *= (1.0 - _array_seal_guard_pct * (1.0 - shred))
	# 五旗阵内：防御 +30% → 受伤 ×1/1.3（严格按防御折算，不是直接 -30%）
	if _array_zone_defense_mult < 1.0:
		mitigated *= DamageCalc.apply_guard_shred(_array_zone_defense_mult, shred)
	# 化劲：受伤 -40%，并把其中的 60% 存起来（上限 140）
	if _qi_ward_left > 0.0:
		mitigated *= (1.0 - _qi_ward_reduce * (1.0 - shred))
		_qi_ward_stored = minf(_qi_ward_cap, _qi_ward_stored + mitigated * _qi_ward_store)
	# 吐纳引导：受到的伤害累计，达到 8% 最大气血会被打断
	if _qi_channel_left > 0.0:
		_qi_channel_damage += mitigated
	# 聚雷引导：同一套打断口径
	if _thunder_channel_left > 0.0:
		_thunder_channel_damage += mitigated
	# 棘甲佩：近战物理受击时反弹一部分真实伤害给攻击者
	var thorns_dmg := 0.0
	if _thorns_left > 0.0 and attack_kind == "physical_melee" \
			and source != null and is_instance_valid(source) and source != self:
		thorns_dmg = mitigated * _thorns_ratio
	# 肉鸽气环：环守（每层减伤）/ 环御（消耗 1 层抵消 20%）。
	# ⚠ 插在所有乘区都算完的位置（与迟照符同一口径）：放到前面会被抗性 / 易伤再乘一遍
	if RogueRun.active and qi_rings > 0:
		var qi_flat := RogueRun.stat("qi_def_pct") * float(qi_rings)
		if qi_flat > 0.0:
			mitigated *= maxf(0.25, 1.0 - qi_flat / 100.0)
		if RogueRun.has_flag("qi_guard"):
			mitigated *= 0.80
			_add_qi(-1)
	# 肉鸽三灾：灾衣（灾位激活常驻）/ 劫衣（灾势满层）
	if RogueRun.active and calamity_element != "":
		var body_pct := RogueRun.stat("calamity_body_pct")
		if body_pct > 0.0:
			mitigated *= maxf(0.3, 1.0 - body_pct / 100.0)
		var full_ward := RogueRun.stat("calamity_full_ward")
		if full_ward > 0.0 and calamity_momentum >= RogueRun.cap("calamity_max"):
			mitigated *= maxf(0.3, 1.0 - full_ward / 100.0)
	# 肉鸽投影：影兽在场上时代影
	if RogueRun.active and _shadow_split_left > 0.0:
		var beast_guard := RogueRun.stat("shadow_beast_guard")
		if beast_guard > 0.0:
			mitigated *= maxf(0.3, 1.0 - beast_guard / 100.0)
	# 肉鸽投影「自灭」：明灭期间减伤
	if RogueRun.active and _shadow_dim_left > 0.0:
		var dim_ward := RogueRun.stat("shadow_dim_ward")
		if dim_ward > 0.0:
			mitigated *= maxf(0.3, 1.0 - dim_ward / 100.0)
	# 肉鸽折影「折守」：场上还有自己的折痕时减伤
	if RogueRun.active and _fold_has_field():
		var fold_guard := RogueRun.stat("fold_field_guard")
		if fold_guard > 0.0:
			mitigated *= maxf(0.3, 1.0 - fold_guard / 100.0)
	# 符箓符罩：一池绝对气血，按**最终伤害**扣。
	# ⚠ 位置必须在这里 —— 放在抗性 / 易伤之前，护盾会被它们再乘一遍，等于凭空变厚。
	if _tal_shield > 0.0 and _tal_shield_left > 0.0 and mitigated > 0.0:
		var absorbed := minf(_tal_shield, mitigated)
		_tal_shield -= absorbed
		mitigated -= absorbed
		if _tal_shield <= 0.0001:
			_tal_shield = 0.0
			_tal_shield_left = 0.0
			_talisman_shield_break()
	# ===== 肉鸽机制卡：受击侧的改写 =====
	# ⚠ 位置必须在 mitigated 定稿之后（抗性 / 护体 / 易伤 / 守旗 / 化劲全部乘完），
	#   否则「背水多受 8%」会被抗性再乘一遍，实际只有 5%。
	if RogueRun.active and not is_dead:
		# 守灯：影长满时减伤
		var lamp_ward := RogueRun.stat("shadow_full_ward")
		if lamp_ward > 0.0 and _shadow_len() >= ShadowLaw.LANTERN_SHADOW_MAX * 0.99:
			mitigated *= maxf(0.3, 1.0 - lamp_ward / 100.0)
		# 背水：残血增伤的代价
		var desperate_taken := RogueRun.stat("desperate_taken")
		if desperate_taken > 0.0 and max_hp > 0.0 and hp / max_hp < 0.35:
			mitigated *= 1.0 + desperate_taken / 100.0
		# 嗜杀：挨一下掉一半杀意（滚雪球被打断，但不至于清零）
		RogueRun.drop_kill_mark_half()
		# 镜替：致命伤时碎一面镜像抵消（每局一次）
		if mitigated >= hp and RogueRun.has_flag("mirror_stand_in") \
				and not RogueRun.used_mirror_stand_in:
			_mirror_prune()
			if not _mirror_images.is_empty():
				var stand_img = _mirror_images.pop_back()
				if is_instance_valid(stand_img):
					stand_img.queue_free()
				RogueRun.used_mirror_stand_in = true
				hp = minf(max_hp, hp + max_hp * 0.20)
				invincible_timer = 2.0
				health_changed.emit(hp, max_hp)
				_update_health_bar()
				_show_float_text("镜替 · 碎影代身", Color(0.72, 0.90, 1.0))
				return
		# 借命：致命伤时保留 1 点气血（每局一次）
		if mitigated >= hp and RogueRun.has_flag("last_stand") \
				and not RogueRun.used_last_stand:
			RogueRun.used_last_stand = true
			hp = 1.0
			invincible_timer = 2.0
			health_changed.emit(hp, max_hp)
			_update_health_bar()
			_show_float_text("借命 · 一线生机", UIKit.C_GREAT)
			return
	# 迟照符：只有真正要扣血的那笔才进池（上面所有免伤分支都已 return）。
	# ⚠ 记的是 mitigated 定稿值 —— 抗性 / 护体 / 易伤 / 守旗 / 化劲全部乘完之后的数。
	if _reckoning_left > 0.0 and not is_dead:
		_reckoning_pool += maxf(0.0, mitigated)
		# 保持原受击节奏：无敌帧照给，否则一套连击会在窗口里堆出巨额待结账
		if not blocking:
			invincible_timer = INVINCIBLE_TIME
		# 石附符已经减过伤，次数照扣，否则窗口内可无限白嫖它的减伤
		if stone_hit:
			_consume_talisman_stone_hit()
		return
	_run_tal_store_damage(mitigated)
	_apply_damage(mitigated, attack_kind, source, blocking)
	_run_tal_on_hit(source)
	# 肉鸽「逆鳞」：受击后 2 秒内伤害 +N%（死了就不挂）
	if RogueRun.active and not is_dead and RogueRun.stat("dmg_after_hit") > 0.0:
		_rogue_scale_left = 2.0
	if thorns_dmg > 0.0 and is_instance_valid(source) and source.has_method("take_true_damage"):
		TreasureFx.play_thorns_burst(self, _body_center())
		source.call("take_true_damage", thorns_dmg, self)
	if stone_hit:
		_consume_talisman_stone_hit()


# ===== 七、弹刀系统：可弹性 / 成功结算 / 增伤 buff =====
func _is_parryable(kind: String) -> bool:
	# 依据任务书：物理近战/物理投掷可弹，元素/法术/能量/神魂不可弹
	return kind == "physical_melee" or kind == "physical_projectile"


## 弹刀成功结算：抵消本次伤害 + 反馈 + 发奖励（僵直 / 反弹 / 追击窗口 / 增伤 buff）
## is_perfect 的判据：窗口前段（剩余时间 > 65%）弹中算「完美弹反」，近战与远程同一套标准
## is_auto = true 表示「自动弹刀」（守势窗口内不按键自动弹开，见 AUTO_PARRY_WINDOW）：
##   - **不消耗精力**（没有门槛，0 精力也能弹）、**不奖励恢复**
##   - 不算完美（不定身、不击退），但同样拿到追击位移资格
func _on_parry_success(attack_kind: String, source: Node, is_auto: bool = false) -> void:
	# 新手指引：自动弹刀也算「弹住了」，但教学计数只认玩家自己按出来的
	if not is_auto:
		Tutorial.note("parry_success")
	var remaining_ratio := parry_timer / PARRY_WINDOW
	# 完美判据：窗口前段（剩余时间 > 65%）弹中
	# ⚠ 近战与物理远程**同一套判据**，不按攻击类型放宽（2026-10-20 纠正：
	#   早前误按"物理远程弹中即完美"实现过一版，那是需求理解错误，已撤销）
	# ⚠ 自动弹刀（is_auto）永远不算完美：那是"不按键"的守势，不给定身/击退/追击奖励
	var is_perfect := (not is_auto) and remaining_ratio > 0.65
	# 迟照符：只有完美弹反抹账（自动弹刀 is_auto=true 恒不算，避免守势窗口无限刷）
	if is_perfect:
		_reckoning_on_wipe()
	parry_timer = 0.0
	_end_parry()
	# 弹刀顿帧：要的是「脆」不是「黏」。0.06 秒（约 4 帧）足够读出一次兵刃接触，
	# 再长就会顶到玩家自己的反击输入 —— 弹成功的那一瞬间最想按的是攻击键。
	GameState.trigger_hit_stop(0.06)
	# 慢动作只留给完美弹反。普通弹刀后面再挂一段 0.4 倍速，
	#   等于把「弹成功 → 立刻斩回去」这段最要紧的窗口揉软，是手感而非观感问题。
	# ⚠ 自动弹刀同样不给：它 1.2 秒内不限次数，而时间流阶段是排队顺延的，
	#   连弹几次就会堆成长时间的慢放（与万剑归宗「顿帧累积」是同一个坑）
	if is_perfect:
		GameState.trigger_slow_mo(0.09, 0.45)
	# 屏幕震动：幅度小、时间短 —— 特效已经简化，这一下「抖」就是主要的物理反馈
	_screen_shake(5.0, 0.09)

	if attack_kind == "physical_melee":
		# 弹近战：BOSS 僵直 + 输出窗口
		if source and source.has_method("on_parried"):
			source.on_parried(self)
	elif attack_kind == "physical_projectile":
		# 弹远程投掷：不僵直，投掷物随机角度反弹（玩家面向 ±120°）
		# 反弹伤害同样是物理攻击 → 走统一公式，装备攻击力加成同样生效
		if source and source.has_method("deflect"):
			if "deflect_damage" in source:
				source.deflect_damage = CharacterData.calc_physical_damage(false, false, false)
			source.deflect(_random_deflect_dir())

	# ⚠ 这里原本会挂一个「极限闪避」buff（阶段1只记录、阶段2接增幅），但它从未被读取，
	#   而且弹刀成功挂「极限闪避」本身就不对 → 2026-10-23 用户拍板整体删除。
	#   弹刀的实际收益是下面那条 parry_power（下一次近战 ×1.5），HUD 也显示它。
	# 弹反追击：完美弹反 / 自动弹刀拿到 1.2 秒的「追击」buff（HUD 会显示剩余时间）
	# ⚠ 只有这两类才有追击资格，所以 buff 也只给它们挂 —— 普通弹刀不显示、也追不了
	if is_perfect or is_auto:
		apply_buff("parry_followup", PARRY_FOLLOWUP_WINDOW)
		# 追击位移资格**只增不减**：拿到后窗口内不会再被其他逻辑抹掉
		parry_followup_can_dash = true
	# 次数增伤 buff：下一次近战伤害 ×1.5，**不累计**（已有则不刷新）
	_grant_parry_damage_buff()
	# 完美弹反专属定身演出（普通弹刀零前摇）
	if is_perfect:
		parry_stance_timer = PARRY_STANCE_TIME
		# 自动弹刀的额外奖励：完美弹刀后开启守势窗口（站着不动就能连弹）
		auto_parry_timer = AUTO_PARRY_WINDOW
	if not is_auto:
		# 主动弹刀成功回复 1 格精力（普通与完美格挡均只回 1 格）
		# 自动弹刀不扣精力，也不走这条奖励恢复
		_recover_stamina(1)
	# 肉鸽「归元」：弹反成功额外回复精力（自动弹刀同样算）
	if RogueRun.active:
		var extra := int(RogueRun.stat("stamina_on_parry"))
		if extra > 0:
			_recover_stamina(extra)
	# 格挡击退：普通格挡会因冲击力后退，完美格挡则不受击退
	# 自动弹刀也不击退 —— 玩家是「站桩防守」，被推走就守不住了
	# ⚠ 先 is_instance_valid 再 `is`：对已释放实例用 `is` 会报 freed 错误（顺序不能反）
	if not is_perfect and not is_auto and source != null and is_instance_valid(source) and source is Node2D:
		var back: Vector2 = (global_position - (source as Node2D).global_position).normalized()
		take_knockback(back * PARRY_KNOCKBACK)
	# 弹刀特效：档位决定层级，方向取攻击源
	_play_parry_effect("perfect" if is_perfect else ("auto" if is_auto else "normal"), source)
	# 弹刀音效：普通/完美区分
	if is_perfect:
		_play_sfx(_perfect_parry_sound)
	else:
		_play_sfx(_parry_sound)
	# 完美弹反文字提示（普通弹刀不飘字，避免刷屏）
	if is_perfect:
		_show_float_text("完美弹反！", Color(1.0, 0.9, 0.3, 1.0))


## ===== 弹刀增伤 buff（次数型，无视觉表现）=====

## 授予次数增伤 buff：**不累计**，已经有时直接返回（不会叠成两倍）
## ⚠ 不加任何角色特效 —— 用户要求 buff 不显示在身上，只影响下一次近战伤害
func _grant_parry_damage_buff() -> void:
	apply_buff("parry_power", 0.0, 1)


## 消费次数增伤 buff：打出一次**近战物理伤害**后消失
func _consume_parry_damage_buff() -> void:
	consume_buff("parry_power")


## 通用浮字提示：指定文字与颜色，从玩家上方浮起渐隐
# ===== 八、反馈表现：飘字 / 震屏 / 弹反特效 / 极限闪避 =====
func _show_float_text(text: String, color: Color) -> void:
	_show_float_text_at(global_position, text, color)


## 在指定世界坐标飘字（符箓命中要落在目标身上，而不是玩家头顶）
func _show_float_text_at(world_pos: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", color)
	label.position = world_pos + Vector2(-40, -60)
	label.z_index = 10
	get_parent().add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y - 30.0, 0.5)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)


## 招名飘字：与 BOSS 的 show_windup_line 同一套样式（金字 + 深色描边），
## 玩家侧只给阵旗八式用 —— 让"这一下是哪招"和 BOSS 一样可读。
func _show_skill_name(text: String, hold: float, color: Color = UIKit.C_SKILL_NAME) -> void:
	if text == "":
		return
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UIKit.SKILL_NAME_SIZE)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 0.95))
	label.add_theme_constant_override("outline_size", 4)
	label.size = Vector2(UIKit.SKILL_NAME_WIDTH, float(UIKit.SKILL_NAME_SIZE) + 8.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = global_position + Vector2(-UIKit.SKILL_NAME_WIDTH * 0.5, -138.0)
	label.z_index = 60
	get_parent().add_child(label)
	var tw := label.create_tween()
	if hold > 0.0:
		tw.tween_interval(hold)
	tw.tween_property(label, "position:y", label.position.y - 30.0, 0.5)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.5)
	tw.tween_callback(label.queue_free)


## 弹反方向：在玩家面向 ±120° 范围内随机
func _random_deflect_dir() -> Vector2:
	var base_angle := attack_dir.angle()
	var offset := deg_to_rad(randf_range(-60.0, 60.0))
	return Vector2.RIGHT.rotated(base_angle + offset)


## ===== 屏幕震动（打击感核心反馈） =====
func _screen_shake(intensity: float, duration: float) -> void:
	_shake_intensity = intensity
	_shake_duration = duration
	_shake_timer = duration


func _tick_screen_shake(delta: float) -> void:
	if _shake_timer <= 0.0:
		# 震动结束，复位相机偏移
		if camera and _camera_base_offset != Vector2.ZERO:
			camera.offset = _camera_base_offset
			_camera_base_offset = Vector2.ZERO
		return
	_shake_timer -= delta
	# 随机偏移，随剩余时间线性衰减
	var strength := _shake_intensity * (_shake_timer / _shake_duration)
	var rng_offset := Vector2(
		randf_range(-1.0, 1.0) * strength,
		randf_range(-1.0, 1.0) * strength
	)
	if camera:
		camera.offset = _camera_base_offset + rng_offset


## 弹刀成功特效：金铁迸溅（图形合成在 SkillFx，配色与尺寸在 ArtDB.EFFECTS 的 fx_parry_*）
## tier = "auto" / "normal" / "perfect"，与收益严格对齐：
##   三档是同一套图形（白点 + 小星芒 + 零星碎星），只差数量与尺寸；
##   自动弹刀 1.2 秒内不限次数，所以给得最少，避免连弹刷屏
func _play_parry_effect(tier: String, source: Node) -> void:
	var key := "fx_parry_normal"
	if tier == "perfect":
		key = "fx_parry_perfect"
	elif tier == "auto":
		key = "fx_parry_auto"
	var cfg: Dictionary = ArtDB.EFFECTS.get(key, {})
	if cfg.is_empty():
		return
	var host := get_parent()
	if host == null:
		return
	# 朝攻击者迸：source 无效时回退玩家面向
	# ⚠ 先 is_instance_valid 再用 `is`：对已释放实例用 `is` 会报 freed 错误
	var dir: Vector2 = attack_dir
	if source != null and is_instance_valid(source) and source is Node2D:
		var to_src: Vector2 = (source as Node2D).global_position - global_position
		if to_src.length_squared() > 1.0:
			dir = to_src.normalized()
	var point := global_position + _body_center() + dir * float(cfg.get("contact_offset", 26.0))
	SkillFx.play_parry(host, point, dir, key)


## 极限闪避：闪避起始的极短时间内挨打触发
## 回 2 格精力 + 短暂子弹时间 + 蓝色特效，是「赌」出来的高收益反馈
func _trigger_perfect_dodge() -> void:
	# 注意：极限闪避**不挂 buff**（用户 2026-10-23 定）—— 收益只有下面这几项即时反馈
	_flash(Color(0.5, 0.9, 1.0))
	# 极限闪避回复2格精力
	_recover_stamina(2)
	# 子弹时间：极限闪避触发短暂慢动作，强化"极限"反馈
	GameState.trigger_slow_mo(0.15, 0.3)
	# 完美闪避音效（更亮，与普通闪避区分）
	_play_sfx(_perfect_dodge_sound)
	# 完美闪避：复制角色形象生成残影，更深更久停留
	_spawn_perfect_dodge_trail()
	# 极限闪避冷蓝光带（不喷碎星：闪避没有任何兵刃接触）
	_play_perfect_dodge_effect()
	# 完美闪避蓝色文字提示（与弹刀的"金色"区分）
	_show_float_text("完美闪避！", Color(0.4, 0.8, 1.0, 1.0))
	# 两仪真人：完美闪避阴招会震掉它的护体（BOSS 侧可选实现该接口）
	_notify_bosses("notify_perfect_dodge")
	# 照影（观澜被动）：完美闪避后留下一具镜像
	_mirror_passive_on_perfect_dodge()
	# 执灯（执烛被动）：完美闪避后影长直接拉满
	_shadow_passive_on_perfect_dodge()
	# 迟照符：完美闪避抹掉一笔待结伤害
	_reckoning_on_wipe()


## 极限闪避特效：沿闪避方向拖一道冷蓝光带（图形合成在 SkillFx，参数在 ArtDB.EFFECTS）
## 与弹反一眼能分：闪避全程没有兵刃接触，所以这一套不喷金属碎星、不放星芒
func _play_perfect_dodge_effect() -> void:
	var host := get_parent()
	if host == null:
		return
	var dir := _dodge_dir
	if dir.length_squared() < 0.0001:
		dir = attack_dir
	SkillFx.play_dodge_slip(host, global_position + _body_center(), dir, "fx_dodge_slip")


## 完美闪避拖影：复制角色形象生成残影，更深、更长、短暂停留
func _spawn_perfect_dodge_trail() -> void:
	for i in range(3):
		_spawn_ghost(Color(0.4, 0.85, 1.0), 0.15 + i * 0.05, 0.5)


## 生成角色形象残影：**快照本体当前那帧贴图**，做成一个纯 Sprite2D 挂到场景里
##
## ⚠ 2026-10-19 用户定（推倒重做）：旧实现是 `anim.duplicate()` 复制整个 Visual 树
##   （含 SkinVisual + AnimatedSprite2D），真实游戏里残影会"原地跑"——因为复制体入树后
##   动画节点会自动 play。现改为**贴图快照**：残影节点只有 贴图 + 变换 + 着色，
##   没有脚本、没有动画节点、没有 _process —— 物理上不存在"播放"的可能，百分百静止。
## tint = 着色（完美闪避不透明青、普通闪避半透明蓝）；hold_time 后开始 fade_time 渐隐
func _spawn_ghost(tint: Color, hold_time: float, fade_time: float) -> void:
	if not is_instance_valid(anim) or skin == null:
		return
	var tex: Texture2D = skin.current_texture()
	if tex == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = tex
	ghost.modulate = tint
	ghost.z_index = -1   # 置于角色下层，避免遮挡本体
	get_parent().add_child(ghost)
	# 入树后继承本体渲染节点的**世界变换**（位置/缩放/翻转/旋转），与本体视觉严丝合缝
	# ⚠ 未入树时 global_* 不生效，必须放在 add_child 之后
	if skin.render_node is Node2D:
		var rn: Node2D = skin.render_node as Node2D
		ghost.global_position = rn.global_position
		ghost.global_scale = rn.global_scale
		ghost.global_rotation = rn.global_rotation
	else:
		ghost.global_position = anim.global_position
	# 停留后渐隐：tween 只改 alpha，不碰任何动画状态
	var tween := ghost.create_tween()
	tween.tween_interval(hold_time)
	tween.tween_property(ghost, "modulate:a", 0.0, fade_time)
	tween.tween_callback(ghost.queue_free)


# ===== 九、掉血、击退与死亡 =====
## 真正掉血：扣血 → 无敌帧 → 飘字 → 精力惩罚 → 击退 → 判死
## amount 已经过 DamageCalc 扣过抗性，这里不再做任何减免
func _apply_damage(amount: float, attack_kind: String, source: Node = null, blocking: bool = false) -> void:
	var hp_before := hp
	# 续命灯：致死伤害先改判成「留 1 点气血」，再按正常受击走反馈
	var lamp_saved := amount >= hp_before and _lamp_left > 0.0 and not is_dead
	if lamp_saved:
		amount = maxf(0.0, hp_before - 1.0)
	hp = maxf(0.0, hp - amount)
	if hp < hp_before:
		took_damage_this_battle = true
	# 格挡中不进入无敌帧：否则连续挨打只算第一次，受击次数叠不上去
	if not blocking:
		invincible_timer = INVINCIBLE_TIME
	if lamp_saved:
		_trigger_lamp_save()
	health_changed.emit(hp, max_hp)
	_update_health_bar()
	_play_hit_flash()
	# 伤害数字：所有伤害只按物理/法术两色（用户 2026-10-29 改定，不再用受击红）
	DamageNumber.spawn(get_parent(), global_position, amount,
		DamageNumber.kind_from_damage_kind(attack_kind))
	# 受击顿帧：被击中瞬间短暂停顿
	GameState.trigger_hit_stop()
	# 受击扣精力：固定掉 1 格（惩罚贪刀）
	# 定势：格挡蓄力期间受击不掉精力（蓄力被打断的成本已经够高了）
	if not (RogueRun.active and RogueRun.has_flag("charge_no_stamina") and _counter_charging):
		_lose_stamina_on_hit()
	# 受击削剑意：固定掉 1 层（用户 2026-10-19 定：「受到一次攻击就减少一层剑意」）
	# ⚠ 只有真掉血才会走到这里 —— 弹反/闪避的无敌、纳势格挡的减伤都不影响「掉层」本身
	_lose_sword_intent(SWORD_INTENT_LOSS_ON_HIT)
	# 受击音效
	GameState.play_sfx("player_hit")
	# 受击击退：沿"被攻击来源指向自己"的方向推开，力度按攻击类型区分
	# 格挡中**不被击退**（否则蓄力位会被推走，还可能脱离自己的斩击范围）
	# ⚠ 先 is_instance_valid 再 `is`：对已释放实例用 `is` 会报 freed 错误（顺序不能反）
	if not blocking and source != null and is_instance_valid(source) and source is Node2D:
		var away: Vector2 = (global_position - (source as Node2D).global_position).normalized()
		take_knockback(away * _knockback_strength(attack_kind))
	if hp <= 0.0:
		_die()


## 真实伤害：不走抗性 / 护体 / 无敌帧，只保留续命灯致死改判。
## 棘甲佩的反弹走这里，避免和「受击 → 反伤」形成递归。
func take_true_damage(amount: float, _source: Node = null) -> void:
	if is_dead or amount <= 0.0:
		return
	var dmg := amount
	if hp - dmg <= 0.0 and _lamp_left > 0.0:
		dmg = maxf(0.0, hp - 1.0)
		_trigger_lamp_save()
	hp = maxf(0.0, hp - dmg)
	took_damage_this_battle = true
	health_changed.emit(hp, max_hp)
	_update_health_bar()
	DamageNumber.spawn(get_parent(), global_position + Vector2(0.0, -34.0), dmg,
		DamageNumber.Kind.PHYSICAL)
	if hp <= 0.0:
		_die()


## 受击时扣精力：**固定扣 1 格**（用户 2026-10-17 改定，旧规则是「减半、向下取整」）
## 作用不变：让贪刀有代价，但不会一刀把 5 格精力削成 2 格那么狠
func _lose_stamina_on_hit() -> void:
	stamina = maxi(0, stamina - STAMINA_LOSS_ON_HIT)
	_update_stamina_bar()


## 按攻击类型返回击退力度：近战大、远程/元素小
func _knockback_strength(attack_kind: String) -> float:
	match attack_kind:
		"physical_melee":
			return KNOCKBACK_MELEE
		"physical_projectile":
			return KNOCKBACK_PROJECTILE
		"elemental":
			return KNOCKBACK_ELEMENTAL
		_:
			return KNOCKBACK_PROJECTILE


## 受击击退：设置一个瞬时击退速度，随时间衰减（由 BOSS 转阶段弹开等复用）
func take_knockback(impulse: Vector2) -> void:
	knockback_velocity = impulse


# ===== 十、HUD 与资源：血条 / 精力 / 灵力 =====

## 战斗消耗品回血：返回实际回复量（已满血时返回 0）
func restore_health(amount: float) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	# 治疗乘区（暗「蚀」= 只剩 10%）：丹药 / 水愈符 / 法宝 / 气环·回息 / 续命灯全走这里
	amount *= debuff_heal_mult()
	if amount <= 0.0:
		return 0.0
	var before := hp
	hp = minf(max_hp, hp + amount)
	health_changed.emit(hp, max_hp)
	_update_health_bar()
	return hp - before


## 战斗消耗品回灵：返回实际回复量
func restore_mana(amount: float) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	var before := mana
	mana = minf(max_mana, mana + amount)
	mana_changed.emit(mana, max_mana)
	_update_mana_bar()
	return mana - before


## 消耗品 / 符箓的灵力消耗（2026-10-24：练气符纸每张 10 点）。
## 灵力不足时返回 false 且**不扣**，由调用方给提示。
func spend_mana(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if mana < amount:
		return false
	mana = maxf(0.0, mana - amount)
	mana_changed.emit(mana, max_mana)
	_update_mana_bar()
	return true


## 更新头顶血条（越简洁越好：仅按血量比例调整填充宽度；低血量变红警示）
## 三才灵环的接入点。只建一次；建在玩家节点下 → 跟着人物一起进相机，
## 但**不挂在 Visual 下**，所以人物镜像翻转不会把简也翻过去。
func _ensure_ring() -> void:
	if _ring != null and is_instance_valid(_ring):
		return
	_ring = ResourceRing.new()
	_ring.name = "ResourceRing"
	add_child(_ring)


## 把三个资源一次推给简。⚠ 别在这里另算一套判定：血量/灵力/精力一律读玩家自己的字段。
func _refresh_ring() -> void:
	if _ring == null or not is_instance_valid(_ring):
		return
	_ring.set_state(clampf(hp / maxf(max_hp, 0.001), 0.0, 1.0),
			clampf(mana / maxf(max_mana, 0.001), 0.0, 1.0),
			stamina, max_stamina)


## 力竭的剩余时间交给简上的「竭」印倒计时（屏幕上不再常驻力竭标签）
## ⚠ 总时长取**进入力竭那一刻**记下的值：DebuffDB 的条目里没有 duration，
##   时长是 apply_debuff 的入参，去表里查会拿到默认值、倒计时线就成了错的。
func _refresh_exhaust_seal() -> void:
	if _ring == null or not is_instance_valid(_ring):
		return
	_ring.set_exhaust(float(debuffs.get("exhausted", 0.0)), _exhaust_total)


func _update_health_bar() -> void:
	# ⚠ 三个 `_update_*_bar()` 是 30+ 处调用点的既有入口，名字必须留着；
	#   内部不再各画各的，一律汇到 _refresh_ring()，三位一体只有一处绘制。
	_refresh_ring()
	# 同步屏幕边缘泛红（用户定：低血暗角是**唯一保留**的二级通道）
	_update_vignette()


## 是否有足够精力执行动作
func _can_spend_stamina() -> bool:
	return stamina >= STAMINA_COST


## 消耗精力（弹刀/闪避各扣1格）
func _spend_stamina() -> void:
	stamina = maxi(0, stamina - STAMINA_COST)
	_update_stamina_bar()


## 恢复精力（奖励触发，如极限闪避+2、弹刀成功+1）
## ⚠ 力竭期间一律无效（用户 2026-10-19 定：有力竭 debuff 时无法恢复精力）
func _recover_stamina(amount: int) -> void:
	if is_exhausted():
		return
	stamina = mini(max_stamina, stamina + amount)
	_update_stamina_bar()


## 是否处于力竭（精力恢复被阻断）—— 直接查 debuff，力竭已经并入 DebuffDB
func is_exhausted() -> bool:
	return has_debuff("exhausted")


## 进入力竭：一剑开天普通形态抽空精力后的 debuff（时长读招式表 exhaust_time）
func _enter_exhaustion(seconds: float) -> void:
	if seconds <= 0.0:
		return
	# 力竭现在是 DebuffDB 里的一条，效果判定统一走 has_debuff("exhausted")；
	# 显示改由灵环的琥珀色精力点阵 + 倒计时光承担（combat_arena 的 debuff 标签已排除它）
	apply_debuff("exhausted", seconds, true)
	_exhaust_total = seconds
	stamina_regen_timer = 0.0
	_update_stamina_bar()
	_refresh_exhaust_seal()
	_show_float_text("力竭！精力暂时无法恢复", UIKit.C_WARN)


## 更新精力条：5格竖排白色线条，有精力亮白，无精力透明；精力耗尽闪红
func _update_stamina_bar() -> void:
	# 精力格数由属性决定（可能不是 5），简按 _stamina_max 现画，
	# 原来「场景里固定 5 段 + 超出隐藏」那套 ColorRect 补丁不再需要
	_refresh_ring()


# ===== 十一、功法施放：消耗校验 → 表现 → 命中结算 =====
# ===================== 功法 / 灵力 =====================

## 更新灵力条（横向填充，与血条同宽）
func _update_mana_bar() -> void:
	mana_changed.emit(mana, max_mana)
	# 灵力不足一半转暗紫，这条判据搬进简里画（ResourceRing._paint）
	_refresh_ring()


## 某功法的剩余冷却秒数
func skill_cooldown_left(skill_id: String) -> float:
	return float(skill_cooldowns.get(skill_id, 0.0))


## HUD 用：该功法当前的**资源**够不够（只看灵力 / 精力，不看冷却与场景门槛）
## 返回 "" = 资源够；否则返回不足原因（"灵力不足" / "精力不足"），供技能格灰化 + tooltip
## ⚠ 口径必须和 can_use_skill() 对齐：大招「抽空整条资源」和肉鸽「以意御法」借剑意
##   都要算进来，否则会出现「格子是灰的、按下去却能放」的自相矛盾。
## ⚠ 气环 / 阵旗 / 目标距离这些场景门槛**故意不算**：它们随时在变，并且按键时已有飘字说明，
##   算进来会让格子频繁闪灰。
func skill_resource_block(skill_id: String) -> String:
	if is_dead:
		return ""
	var cost := SkillDB.get_skill_cost(_resolve_cast_form_skill(skill_id))
	var avail := _castable_mana(cost)
	if bool(cost.get("stamina_all", false)) and stamina < 1:
		return "精力不足"
	if bool(cost.get("mana_all", false)) and avail < 1.0:
		return "灵力不足"
	match String(cost.get("cost_kind", MoveDB.COST_NONE)):
		MoveDB.COST_MANA:
			if avail < float(cost.get("mana_cost", 0.0)):
				return "灵力不足"
		MoveDB.COST_STAMINA:
			if stamina < int(cost.get("stamina_cost", 0)):
				return "精力不足"
	return ""


## 本次施法可动用的灵力：肉鸽「以意御法」下剑意每层抵 10 点
## 与 _rogue_prepare_intent_mana() 同一口径，但**纯计算** —— 不改 mana、不扣剑意
## （HUD 每帧都会来问，绝不能有副作用）。
func _castable_mana(cost: Dictionary) -> float:
	var avail := mana
	if not RogueRun.active or not RogueRun.has_flag("intent_as_mana") or sword_intent <= 0:
		return avail
	if String(cost.get("cost_kind", "")) != MoveDB.COST_MANA:
		return avail
	var need := float(cost.get("mana_cost", 0.0))
	if need <= avail:
		return avail
	var stacks := mini(int(ceil((need - avail) / 10.0)), sword_intent)
	return avail + minf(need - avail, float(stacks) * 10.0)


## HUD 用：符箓格当前能不能按（灵力 / 试炼内是否已解锁）
## 返回 "" = 可释放；否则返回不足原因
## ⚠ 冷却不在这里判：符箓格没有冷却遮罩，多一条原因只会让灰化状态反复横跳。
func talisman_slot_block(slot_value: String) -> String:
	if is_dead:
		return ""
	var item_id := CharacterData.talisman_slot_item_id(slot_value)
	if item_id == "":
		return ""
	# 试炼：四符连携体系（冷却 / 灵力 / 血墨 / 无墨都在那边判定）
	if RogueRun.active and not TalismanDB.base_def(item_id).is_empty():
		return run_talisman_block(slot_value)
	if mana < TALISMAN_MANA_COST:
		return "灵力不足"
	return ""


## 演武场训练面板：刷新功法冷却 + 精力补满（2026-10-25 用户要求）
## 训练场不死亡、不消耗资源；刷新时连「力竭」也一并解除，
## 避免出现「精力已满、却仍处于力竭无法恢复」的矛盾状态。
func refresh_training_resources() -> void:
	skill_cooldowns.clear()
	stamina = max_stamina
	stamina_regen_timer = 0.0
	debuffs.erase("exhausted")
	_debuff_dot_timers.clear()
	_mirror_clear_images()
	_mirror_return_left = 0.0
	_mirror_passive_cd = 0.0
	remove_buff("mirror_return")
	_shadow_reset()
	_fold_reset()
	_talisman_reset()
	yinyang_polarity = YINYANG_YANG
	yinyang_stacks = 0
	remove_buff("yinyang_reverse")
	_refresh_yinyang_pips()
	_update_stamina_bar()


## 演武场训练：从背包 / 装备面板返回后刷新运行时缓存属性。
## 伤害计算直接读 CharacterData，这里主要刷新气血/精力/灵力上限、移速与武器外观。
func refresh_training_loadout() -> void:
	_refresh_qi_unlock()
	_refresh_thunder_unlock()
	_refresh_sun_unlock()
	_refresh_calamity_unlock()
	_apply_attributes_to_runtime(false)
	_update_health_bar()
	_update_stamina_bar()
	_update_mana_bar()
	if weapon == null:
		_setup_weapon()
	_sync_weapon_visual()
	_refresh_yinyang_unlock()


## 属性卡落地后重读运行时缓存，并刷新三条资源读数（试炼玉简的三选一用）。
## ⚠ 试炼里玩家是**常驻**的：max_stamina / max_hp / max_mana / 移速 / 攻速都只在
##   `_apply_attributes_to_runtime` 里缓存过一次 —— 拿到卡不重读，就要等下一局才生效。
##   2026-11-12 用户报「精力上限 / 额外回精力没生效」，根因就是这条缓存没刷新。
func refresh_runtime_attributes() -> void:
	_apply_attributes_to_runtime(false)
	_update_health_bar()
	_update_stamina_bar()
	_update_mana_bar()


## 尝试使用某个主动功法
## 流程：解析实际形态（满层变体）→ 校验（是否习得/装配/冷却/资源）→ 扣消耗 →
##       进冷却 → 播放形态表现 → 按系数结算伤害
## 返回是否成功施放
func try_use_skill(skill_id: String) -> bool:
	if is_dead:
		return false
	if is_action_blocked():
		return false
	# 断念铃：封技期间不能起功法；普攻 / 闪避 / 弹刀 / 法宝 / 丹药 / 符箓都能用
	if has_debuff("duannian"):
		_show_float_text("断念：功法被封", DebuffDB.color("duannian"))
		return false
	# 一剑开天满层时会切换法术变体：消耗按**变体**口径校验与扣缴
	#（习得/装配/冷却仍认原技能 —— 变体条目不进功法库，见 _resolve_cast_form_skill）
	var cast_id := _resolve_cast_form_skill(skill_id)
	# 肉鸽「以意御法」：灵力不够时先借剑意垫上（校验通过后才真正扣层）
	_rogue_prepare_intent_mana(cast_id)
	var check := CharacterData.can_use_skill(
		skill_id, mana, skill_cooldown_left(skill_id), stamina, cast_id)
	if not bool(check.get("ok", false)):
		_rogue_rollback_intent_mana()
		var reason := String(check.get("reason", ""))
		if reason != "":
			_show_float_text(reason, UIKit.C_FLOAT_WARN)
		return false

	# 气环门槛：聚气满环不能放；化劲 / 吐纳这类带 qi_need 的技能不够环就不白扣资源
	if skill_id == "skill_qi_gather" and qi_rings >= _qi_max():
		_show_float_text("气环已满", Color(0.62, 0.86, 1.0))
		return false
	var qi_need := int(SkillDB.get_skill_form(skill_id).get("qi_need", 0))
	if qi_need > 0 and qi_rings < qi_need:
		_show_float_text("气环不足（需要 %d 枚）" % qi_need, UIKit.C_FLOAT_WARN)
		return false
	# 阵旗门槛（与 BOSS 的 _usable 同口径）：没旗 / 旗不够 / 阵位满时不白扣资源
	_prune_array_flags()
	# 破阵反噬：五旗被敌对破去一面后，10 秒内插旗 / 踏阵 / 垒旗全部不可用
	if skill_id in ARRAY_PLANT_SKILLS and has_debuff("array_recoil"):
		_show_float_text("破阵反噬：15 秒内无法插旗", UIKit.C_FLOAT_WARN)
		return false
	if skill_id == "skill_array_plant" and array_flags.size() >= _array_max_flags():
		_show_float_text("阵位已满（%d 面）" % _array_max_flags(), UIKit.C_FLOAT_WARN)
		return false
	if skill_id == "skill_array_pull" and array_flags.is_empty():
		_show_float_text("无旗可卷", UIKit.C_FLOAT_WARN)
		return false
	if skill_id == "skill_array_seal" and array_flags.size() < 4:
		_show_float_text("封阵需要四面旗（当前 %d）" % array_flags.size(), UIKit.C_FLOAT_WARN)
		return false
	if skill_id == "skill_array_burst" and array_flags.is_empty():
		_show_float_text("无阵可解", UIKit.C_FLOAT_WARN)
		return false
	# 判词八式门槛：打不到 / 雷势已满时不白扣资源
	if skill_id == "skill_thunder_gather" and lei_shi >= _thunder_max():
		_show_float_text("雷势已满", Color(0.86, 0.70, 1.0))
		return false
	if skill_id == "skill_thunder_verdict" and _nearest_boss(380.0) == null:
		_show_float_text("目标不在判词范围内", UIKit.C_FLOAT_WARN)
		return false
	if skill_id == "skill_thunder_execute" and _nearest_boss(460.0) == null:
		_show_float_text("目标不在定刑范围内", UIKit.C_FLOAT_WARN)
		return false
	if skill_id == "skill_thunder_lock" and _nearest_boss(340.0) == null:
		_show_float_text("目标不在锁雷范围内", UIKit.C_FLOAT_WARN)
		return false
	if skill_id in ["skill_thunder_nine", "skill_thunder_prison"] and _nearest_boss(520.0) == null:
		_show_float_text("目标不在范围内", UIKit.C_FLOAT_WARN)
		return false
	# 逐日：火种不再是门槛 —— 无种也能放基础版，持种才完整。
	# 只挡「既没有种子、也没有目标」的空放，避免白扣资源。
	if skill_id in ["skill_sun_throw", "skill_sun_pull", "skill_sun_eclipse",
			"skill_sun_meteor"]:
		_sun_seed = _find_sun_seed()
		if _sun_seed == null and _nearest_boss(520.0) == null:
			_show_float_text("目标不在范围内", UIKit.C_FLOAT_WARN)
			return false
	# 镜身门槛：碎镜 / 换镜要有一具自己的镜像；召镜类镜像已满时不白扣资源
	_mirror_prune()
	if skill_id in ["skill_mirror_shatter", "skill_mirror_swap"] \
			and _mirror_images.is_empty():
		_show_float_text("没有镜像可用", UIKit.C_FLOAT_WARN)
		return false
	if skill_id in ["skill_mirror_bloom", "skill_mirror_myriad"] \
			and _mirror_images.size() >= _mirror_max_images():
		_show_float_text("镜像已满（%d 具）" % _mirror_max_images(), UIKit.C_FLOAT_WARN)
		return false
	if skill_id == "skill_mirror_return" and _mirror_return_left > 0.0:
		_show_float_text("镜面已经架好", UIKit.C_FLOAT_WARN)
		return false
	# 投影门槛：影子只有一份，撕出去代打期间影系三招哑火
	if _shadow_cast_blocked(skill_id):
		return false
	var cost: Dictionary = check.get("cost", {})
	# 扣消耗。⚠ 一剑开天双形态的 stamina_all / mana_all 优先于常规数值扣缴：
	#   普通形态抽空全部精力并进力竭；满层法术形态抽空全部精力+灵力、不进力竭
	var spend_all_stamina: bool = bool(cost.get("stamina_all", false))
	var spend_all_mana: bool = bool(cost.get("mana_all", false))
	if spend_all_stamina:
		stamina = 0
		_update_stamina_bar()
	elif String(cost.get("cost_kind", MoveDB.COST_NONE)) == MoveDB.COST_STAMINA:
		stamina = maxi(0, stamina - int(cost.get("stamina_cost", 0)))
		_update_stamina_bar()
	if spend_all_mana:
		mana = 0.0
		_update_mana_bar()
	elif String(cost.get("cost_kind", MoveDB.COST_NONE)) == MoveDB.COST_MANA:
		mana = maxf(0.0, mana - float(cost.get("mana_cost", 0.0)))
		_update_mana_bar()
	# 力竭 debuff（仅配了 exhaust_time 的招式会触发，一剑开天普通形态 3 秒）
	_enter_exhaustion(float(cost.get("exhaust_time", 0.0)))

	# 进冷却
	var cd := float(cost.get("cooldown", 0.0))
	if cd > 0.0:
		skill_cooldowns[skill_id] = cd
	_rogue_commit_intent_mana()

	# 通知场上 BOSS：玩家刚刚出招（用于「纳势反击」的触发判断）
	_notify_boss_player_skill()
	_cast_skill(skill_id)
	skill_used.emit(skill_id)
	Tutorial.note("skill_used")
	return true


## 符箓：4 个功法格里的 talisman: 条目直接瞬发。
## 局外：消耗 5 灵力 + 1 张，无前摇无冷却。
## 试炼：走四符连携体系（独立冷却 / 连携 / 符方品阶），见 use_run_talisman。
func use_talisman_slot(slot_value: String) -> bool:
	var id := CharacterData.talisman_slot_item_id(slot_value)
	if RogueRun.active and not TalismanDB.base_def(id).is_empty():
		return use_run_talisman(id)
	return use_talisman(id)


func use_talisman(item_id: String) -> bool:
	if is_dead or is_action_blocked():
		return false
	# 演武场是试招场：符箓按无限张处理，不扣符匣（真实位面 / 塔照常扣）
	var training := BattleResolver.current_source() == BattleResolver.SOURCE_ARENA
	var def := ItemDB.get_consumable(item_id)
	if def.is_empty() or String(def.get("kind", "")) != "talisman":
		return false
	if not training and CharacterData.talisman_count(item_id) <= 0:
		_show_float_text("符箓已用完", UIKit.C_FLOAT_WARN)
		return false
	if mana < TALISMAN_MANA_COST:
		_show_float_text("灵力不足（需要 %d 点）" % int(TALISMAN_MANA_COST), UIKit.C_FLOAT_WARN)
		return false
	var eff: Dictionary = def.get("battle_effect", {})
	var target: Node2D = null
	var aim := global_position + Vector2(0.0, -30.0)
	if _talisman_needs_target(eff):
		target = _nearest_boss(520.0)
		if target == null:
			_show_float_text("附近没有目标", UIKit.C_FLOAT_WARN)
			return false
		aim = _boss_aim_point(target)
	if not spend_mana(TALISMAN_MANA_COST):
		return false
	if not training and not CharacterData.consume_talisman(item_id):
		return false
	# 任务面板：主模式真实施出一张符才算。位置在**灵力已扣、符已消耗之后**——
	# 早一步会把「施放失败」也记成用过一次。
	# ⚠ 演武场（training）不扣符也算：那是试招场，学会用比省一张符重要。
	# ⚠ 试炼局内走的是 use_run_talisman → _run_tal_cast，发的是另一个事件
	#   `run_talisman_used`，两者不许混用（11-11 任务口径改回主模式，见 quest_db）。
	Tutorial.note("talisman_used")
	# 符卡先飞出去，落点那一帧才真正结算（见 talisman_fx.gd）
	var host := get_parent()
	if host != null and host.is_inside_tree():
		var fx = TALISMAN_FX.new()
		host.add_child(fx)
		fx.setup(self, target, def, aim,
			Callable(self, "_apply_talisman_effect").bind(item_id, def, target, aim))
	else:
		_apply_talisman_effect(item_id, def, target, aim)
	skill_used.emit(item_id)
	return true


func _talisman_needs_target(eff: Dictionary) -> bool:
	return String(eff.get("kind", "")) == "element_talisman" \
		and String(eff.get("effect", "")) in ["sword_qi", "fireball", "lightning", "root"]


func _apply_talisman_effect(_item_id: String, def: Dictionary, target: Node2D,
		aim: Vector2) -> void:
	if is_dead:
		return
	var eff: Dictionary = def.get("battle_effect", {})
	if String(eff.get("kind", "")) != "element_talisman":
		return
	# 局外元素符：数值写死在 ItemDB（试炼的四符体系不走这条路径，见 use_run_talisman）
	var effect := String(eff.get("effect", ""))
	var element := String(eff.get("element", ""))
	match effect:
		"sword_qi":
			if target != null and is_instance_valid(target) and target.has_method("take_damage"):
				_talisman_deal(def, eff, target, element, "skill_talisman_item")
				_show_talisman_hit_text(def, eff, target)
		"fireball":
			var center := aim
			if target != null and is_instance_valid(target):
				center = _boss_aim_point(target)
			for raw in get_tree().get_nodes_in_group("boss"):
				# ⚠ 死单位不参与索敌 / 结算：试炼里 BOSS 尸体不销毁、仍在 "boss" 组
				if BossBase.is_unit_dead(raw):
					continue
				var b := raw as Node2D
				if b == null or not is_instance_valid(b) or not b.has_method("take_damage"):
					continue
				if _boss_aim_point(b).distance_to(aim) > 80.0:
					continue
				_talisman_deal(def, eff, b, "fire", "skill_talisman_item")
				if b.has_method("apply_debuff"):
					b.call("apply_debuff", "burn", 8.0)
				_show_talisman_hit_text(def, eff, b)
		"lightning":
			if target != null and is_instance_valid(target) and target.has_method("take_damage"):
				_talisman_deal(def, eff, target, "thunder", "skill_talisman_item")
				_show_talisman_hit_text(def, eff, target)
				if randf() < float(eff.get("stun_chance", 0.0)):
					if target.has_method("stun_for"):
						target.call("stun_for", float(eff.get("stun_time", 1.0)))
					elif target.has_method("apply_debuff"):
						target.call("apply_debuff", "stun", float(eff.get("stun_time", 1.0)))
		"root":
			if target != null and is_instance_valid(target):
				if target.has_method("apply_debuff"):
					target.call("apply_debuff", "rooted", float(eff.get("root_time", 2.0)))
				_show_float_text("木缚 · 定身 %.0f 秒" % float(eff.get("root_time", 2.0)),
					Color(0.58, 0.86, 0.54))
		"regen_hp":
			_talisman_water_left = float(eff.get("heal_time", 8.0))
			_talisman_water_tick = 0.0
			_talisman_water_per_sec = float(eff.get("heal_per_sec", 10.0))
			apply_buff("talisman_water", _talisman_water_left)
			_show_float_text("水愈 · 缓慢恢复", Color(0.48, 0.82, 0.94))
		"speed_up":
			_talisman_wind_left = float(eff.get("duration", 3.0))
			CharacterData.set_attribute_mod(TALISMAN_WIND_SOURCE,
				{AttributeDB.ATTR_SPEED_PCT: {"flat": float(eff.get("speed_pct", 10.0))}})
			apply_buff("talisman_wind", _talisman_wind_left)
			_show_float_text("风疾 · 大幅提速", Color(0.62, 0.88, 0.78))
		"stone_body":
			_talisman_stone_left = float(eff.get("duration", 12.0))
			_talisman_stone_reduce = float(eff.get("damage_reduction", 20.0)) / 100.0
			_talisman_stone_hits = int(eff.get("hits", 3))
			CharacterData.set_attribute_mod(TALISMAN_STONE_SOURCE,
				{AttributeDB.ATTR_SPEED_PCT: {"flat": -float(eff.get("speed_down", 15.0))}})
			apply_buff("talisman_stone", _talisman_stone_left)
			_show_float_text("石附 · 挡 %d 次伤害" % _talisman_stone_hits,
				Color(0.78, 0.68, 0.52))


## 符箓伤害的统一出口。
## ⚠ 局外那套是直接 `target.take_damage(...)`：试炼里这样做会**绕开所有全局乘区**
##   —— 两仪、肉鸽全局增伤、命中挂 debuff 全在 `_tal_hit_one` 这条钩子链上。
##   所以试炼里必须改走它，主模式保持原样（那些乘区在那里本来就不该生效）。
func _talisman_deal(_def: Dictionary, eff: Dictionary, target: Node, element: String,
		skill_id: String) -> void:
	var dmg := float(eff.get("damage", 0.0))
	if dmg <= 0.0 or not is_instance_valid(target):
		return
	if RogueRun.active:
		_tal_hit_one(target, dmg, "elemental", skill_id, element)
		return
	target.take_damage(dmg, self, "elemental", element)


func _show_talisman_hit_text(def: Dictionary, eff: Dictionary, target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_show_float_text_at(_boss_aim_point(target),
		"%s · %d" % [String(def.get("talisman_name", "符箓")), int(eff.get("damage", 0.0))],
		UIKit.C_FLOAT_WARN)


func _tick_talisman_effects(delta: float) -> void:
	if _talisman_water_left > 0.0:
		_talisman_water_left = maxf(0.0, _talisman_water_left - delta)
		_talisman_water_tick += delta
		while _talisman_water_tick >= 1.0 and _talisman_water_left > 0.0:
			_talisman_water_tick -= 1.0
			restore_health(_talisman_water_per_sec)
		if _talisman_water_left <= 0.0:
			remove_buff("talisman_water")
	if _talisman_wind_left > 0.0:
		_talisman_wind_left = maxf(0.0, _talisman_wind_left - delta)
		if _talisman_wind_left <= 0.0:
			CharacterData.clear_attribute_mod(TALISMAN_WIND_SOURCE)
			remove_buff("talisman_wind")
	if _talisman_stone_left > 0.0:
		_talisman_stone_left = maxf(0.0, _talisman_stone_left - delta)
		if _talisman_stone_left <= 0.0:
			_clear_talisman_stone()
	elif _talisman_stone_hits <= 0:
		_clear_talisman_stone()


func _consume_talisman_stone_hit() -> void:
	if _talisman_stone_left <= 0.0:
		return
	_talisman_stone_hits -= 1
	if _talisman_stone_hits <= 0:
		_clear_talisman_stone()
		_show_float_text("石附解除", Color(0.78, 0.68, 0.52))


func _clear_talisman_stone() -> void:
	_talisman_stone_left = 0.0
	_talisman_stone_hits = 0
	_talisman_stone_reduce = 0.0
	CharacterData.clear_attribute_mod(TALISMAN_STONE_SOURCE)
	remove_buff("talisman_stone")


## 解析实际要施展的技能 id：一剑开天在满剑意时切换为法术变体
##（skill_sword_heaven_full 是 is_variant 条目，不进功法库、不占首杀奖励，
##  所以这里只把它的**消耗口径**借给校验用，其余流程仍走原技能）
func _resolve_cast_form_skill(skill_id: String) -> String:
	if not (RogueRun.has_flag("heaven_free") or sword_intent >= _sword_intent_max()):
		return skill_id
	var form := SkillDB.get_skill_form(skill_id)
	var full_id := String(form.get("full_form_id", ""))
	if full_id == "":
		return skill_id
	var full_skill := SkillDB.get_skill_id_by_form(full_id)
	return full_skill if full_skill != "" else skill_id


## 广播「玩家使用了功法」给场上 BOSS（BOSS 侧可选实现该接口）
func _notify_boss_player_skill() -> void:
	for b in get_tree().get_nodes_in_group("boss"):
		# ⚠ 死单位不参与索敌 / 结算：试炼里 BOSS 尸体不销毁、仍在 "boss" 组
		if BossBase.is_unit_dead(b):
			continue
		if is_instance_valid(b) and b.has_method("notify_player_skill_used"):
			b.notify_player_skill_used()


## 施放功法：读招式形态 → 播表现 →（前摇后）结算命中
## 蓄力推进：到点自动斩出，左键提前斩出
## ⚠ 必须在 _handle_action_input() **之后**调用 —— 那一帧普攻已被蓄力态吞掉，
##   否则释放的同帧会连带打出一记普攻
func _tick_counter_charge(delta: float) -> void:
	if not _counter_charging:
		return
	if is_dead:
		_counter_charging = false
		_finish_counter_ward()
		return
	_counter_charge += delta
	if is_instance_valid(_counter_ward):
		_counter_ward.set_charge(_counter_charge / maxf(_counter_max, 0.01), _counter_hits)
	if _counter_charge >= _counter_max:
		_release_counter()
		return
	if Input.is_action_just_pressed("attack"):
		_release_counter()


## 进入蓄力格挡
func _begin_counter_charge(skill_id: String, form: Dictionary, dir: Vector2, charge_max: float) -> void:
	_counter_charging = true
	_counter_skill = skill_id
	_counter_form = form
	_counter_charge = 0.0
	_counter_hits = 0
	_counter_max = charge_max
	# 铁壁：格挡减伤按比例抬（0.7 → 0.7×(1+15%)）；上限 0.9，留出「必挨一点」的底线
	var block := float(form.get("charge_block", 0.7))
	if RogueRun.active:
		block *= 1.0 + RogueRun.stat("charge_block_pct") / 100.0
	_counter_block = clampf(block, 0.0, 0.9)
	_counter_yinyang_ward = bool(form.get("yinyang_ward", false))
	velocity = Vector2.ZERO
	is_attacking = false   # 蓄力不是攻击态，避免普攻逻辑干扰
	_counter_ward = SkillFx.play_counter_ward(self, skill_id, form)
	_show_float_text("阴阳守势" if _counter_yinyang_ward else "蓄力格挡", UIKit.C_FLOAT_BLOCK)


## 结束/清理蓄力护势（释放、取消、死亡、施符都要走这里）
func _finish_counter_ward() -> void:
	_counter_yinyang_ward = false
	if is_instance_valid(_counter_ward):
		_counter_ward.finish()
	_counter_ward = null


## 斩出：系数 = 基础 1.0 + （已蓄秒数 + 受击次数）× charge_coeff_gain（无上限）
## gain 默认 0.5 → 蓄 5 秒满 = ×3.5；再挨 4 下 = ×5.5
func _release_counter() -> void:
	if not _counter_charging:
		return
	_counter_charging = false
	var sk := _counter_skill
	var frm := _counter_form
	var is_yinyang := _counter_yinyang_ward
	var gain := float(frm.get("charge_coeff_gain", 1.0))
	# 蓄劲：每蓄 1 秒的系数加成 +N（主模式 stat 恒为 0）
	if RogueRun.active:
		gain += RogueRun.stat("charge_gain_add")
	var mult := 1.0 + (_counter_charge + float(_counter_hits)) * gain
	_show_float_text(("两仪倒悬 ×%.2f" if is_yinyang else "纳势反击 ×%.2f") % mult, UIKit.C_FLOAT_COUNTER)
	# 方向用「释放瞬间」的瞄准方向，蓄力期间可以调
	var dir := _skill_aim_dir()
	_finish_counter_ward()
	# ⚠ 必须自己播特效：常规功法在 _cast_skill 里播，蓄力释放走的是另一条路径
	_spawn_skill_visual(frm, dir, sk)
	_apply_skill_hit(sk, frm, dir, mult)
	_mirror_on_skill_cast(sk, frm)


# ===== 两仪势（玩家侧，2026-10-27）=====

## 是否已学会任意一门两仪功法 —— 决定势条是否出现、机制是否参与计算。
## 第一战打两仪真人时玩家还没学过，所以这里是 false，第一战完全不受影响。
func _refresh_yinyang_unlock() -> void:
	_yinyang_unlocked = false
	for sid in CharacterData.learned_skills:
		var sk := SkillDB.get_skill(String(sid))
		if bool(sk.get("yinyang", false)):
			_yinyang_unlocked = true
			break
	_refresh_yinyang_pips()


## 被动「负阴抱阳」是否佩戴 —— 决定阴阳这套语言**能覆盖到哪里**（2026-10-27 用户定稿）：
##   · 没戴：只有两仪真人掉落的八门功法自己算阴阳（逆式增伤 / 叠势 / 印 / 引爆照常），
##     普攻与其他功法（刀痕、剑意、虎妖那五门…）一律原样伤害，势条也不显示；
##   · 戴了：所有伤害来源都算颜色 —— 普攻与任何功法都能吃逆式、叠势、引爆印，势条出现。
## 被动靠 SkillDB 的 passive_effect 查，不在这里硬比 skill_id。
func _yinyang_universal() -> bool:
	if not _yinyang_unlocked:
		return false
	var gate := SkillDB.get_passive_by_effect("yinyang_stacks")
	return not gate.is_empty() and String(gate.get("skill_id", "")) in CharacterData.passive_skill_loadout


## 这一发是不是两仪功法自己（决定「没戴被动时它算不算阴阳」）
func _is_yinyang_skill(skill_id: String) -> bool:
	if skill_id == "":
		return false
	return bool(SkillDB.get_skill(skill_id).get("yinyang", false))


## 头顶的「机制徽记带」：一条向上排的 VBox，以后新机制（剑意格、刀痕计数…）
## 只要再塞一行 MechanicPips 进来，就会自动排在下一行 —— 位置已经预留好。
## 预留两行高：第一行贴着额头，第二行往上长，不会挤到伤害飘字那一路。
func _ensure_mechanic_hud() -> void:
	if _mech_hud != null and is_instance_valid(_mech_hud):
		_refresh_yinyang_pips()
		return
	_mech_hud = VBoxContainer.new()
	_mech_hud.name = "MechanicHud"
	_mech_hud.alignment = BoxContainer.ALIGNMENT_END
	_mech_hud.add_theme_constant_override("separation", 3)
	_mech_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mech_hud.z_index = 80
	_mech_hud.custom_minimum_size = Vector2(MECH_HUD_W, MECH_HUD_H)
	_mech_hud.size = Vector2(MECH_HUD_W, MECH_HUD_H)
	_mech_hud.position = Vector2(-MECH_HUD_W * 0.5, MECH_HUD_TOP)
	add_child(_mech_hud)
	_yinyang_pips = MechanicPips.new()
	_yinyang_pips.name = "YinyangPips"
	_mech_hud.add_child(_yinyang_pips)
	_refresh_yinyang_pips()


## 给机制徽记带加一行（新机制的接入点：自己造一个 MechanicPips 或 Control 交进来）
func add_mechanic_row(row: Control) -> void:
	_ensure_mechanic_hud()
	if row != null:
		_mech_hud.add_child(row)


## 身上有没有「能产势的来源」—— 决定势条要不要占位（没来源就别摆三枚空槽）：
##   · 戴了被动：普攻与任何功法都算颜色 → 永远有来源；
##   · 没戴被动：只有装进主动槽（Q/E/R/T）的两仪功法算，而且两仪转与太极崩只吃势不产势。
func _yinyang_source_equipped() -> bool:
	if not _yinyang_unlocked:
		return false
	if _yinyang_universal():
		return true
	for sid in CharacterData.active_skill_loadout:
		if SkillDB.builds_yinyang_stacks(String(sid)):
			return true
	return false


## 势的图形读数：点亮几枚玉佩 = 几层势，玉佩颜色 = 当前仪态，「逆」字 = 必定逆式。
## 只在「学完两仪功法」且「身上有能产势的来源」时显示（用户 10-27 定）。
func _refresh_yinyang_pips() -> void:
	if _yinyang_pips == null or not is_instance_valid(_yinyang_pips):
		return
	_yinyang_pips.visible = _yinyang_source_equipped()
	if not _yinyang_pips.visible:
		return
	_yinyang_pips.set_state(yinyang_stacks, _yinyang_color(),
			"逆" if has_buff("yinyang_reverse") else "")


## 阳 / 阴的配色直接取 DebuffDB 的阳印 / 阴印 —— 与 BOSS 头顶的标记同一份色
func _yinyang_color() -> Color:
	return DebuffDB.color("yang_mark") if yinyang_polarity == YINYANG_YANG \
		else DebuffDB.color("yin_mark")


## 本次命中属于阳还是阴；-1 = 不参与（无属性 / 混伤 / 两仪转）
func _yinyang_hit_polarity(kind: String, skill_id: String) -> int:
	if skill_id != "":
		var sk := SkillDB.get_skill(skill_id)
		var pol := String(sk.get("polarity", ""))
		if pol == "mixed" or pol == "neutral":
			return -1
		if pol == "yang":
			return YINYANG_YANG
		if pol == "yin":
			return YINYANG_YIN
	return YINYANG_YANG if kind.begins_with("physical") else YINYANG_YIN


## 命中前的两仪结算：逆式增伤 / 叠势 / 翻面 / 印引爆 / 挂印。
## 返回修改后的伤害。第一战未解锁时原样返回；
## 没佩戴被动时，非两仪来源（普攻与其他功法）也原样返回 —— 它们不参与阴阳。
## can_stack = false：后续触发的伤害（阵旗自动剑气 / 环身气 / 刀痕）只吃增伤与逆印结算，
## 不加层、不翻面、不消耗「必定逆式」buff；主动出手的命中才传 true。
## 肉鸽爬塔的伤害乘区（主模式直接原样返回）
## 分工：全局通用池（对满血/残血、逆鳞、踏影、法术增伤）在 RogueRun 里算；
##       剑意相关的两套（每层额外法术增伤 / 意涌）只有玩家知道当前层数，在这里乘。
func _rogue_modify_damage(dmg: float, boss: Node, kind: String, skill_id: String) -> float:
	if not RogueRun.active or dmg <= 0.0:
		return dmg
	var out := RogueRun.modify_outgoing(dmg, boss, kind, skill_id)
	# 剑气流：每层剑意额外 +N% 法术伤害
	var per_stack_spell := RogueRun.stat("intent_spell_pct")
	if per_stack_spell > 0.0 and not kind.begins_with("physical") and sword_intent > 0:
		out *= 1.0 + per_stack_spell / 100.0 * float(sword_intent)
	# 气环·环法：每层气环额外 +N% 法术伤害
	var qi_spell := RogueRun.stat("qi_spell_per")
	if qi_spell > 0.0 and not kind.begins_with("physical") and qi_rings > 0:
		out *= 1.0 + qi_spell / 100.0 * float(qi_rings)
	# 血刀流·血刃：每损失 10% 气血，物理伤害 +N%（向下取整，满血时恒为 0）
	var low_hp_phys := RogueRun.stat("low_hp_phys_pct")
	if low_hp_phys > 0.0 and kind.begins_with("physical") and max_hp > 0.0:
		var lost_steps := int(floor((1.0 - clampf(hp / max_hp, 0.0, 1.0)) * 10.0 + 0.0001))
		if lost_steps > 0:
			out *= 1.0 + low_hp_phys / 100.0 * float(lost_steps)
	# 背水：残血时的全局增伤（代价在 take_damage 里加受伤）
	var desperate := RogueRun.stat("desperate_dmg")
	if desperate > 0.0 and max_hp > 0.0 and hp / max_hp < 0.35:
		out *= 1.0 + desperate / 100.0
	# 逆鳞：受击后的短窗口
	if _rogue_scale_left > 0.0:
		out *= 1.0 + RogueRun.stat("dmg_after_hit") / 100.0
	# 虎妖·压强：对破防目标加伤（破防是 debuff，别人挂的也算 —— 只看目标身上有没有）
	var vs_broken := RogueRun.stat("dmg_vs_broken")
	if vs_broken > 0.0 and boss != null and is_instance_valid(boss) \
			and boss.has_method("has_debuff") \
			and bool(boss.call("has_debuff", "armor_break")):
		out *= 1.0 + vs_broken / 100.0
	# 判词雷·定罪：对眩晕目标加伤
	var vs_stun := RogueRun.stat("dmg_vs_stun")
	if vs_stun > 0.0 and boss != null and is_instance_valid(boss) \
			and boss.has_method("has_debuff") \
			and bool(boss.call("has_debuff", "stun")):
		out *= 1.0 + vs_stun / 100.0
	# 三灾：灾崩易伤 / 每道痕加伤 / 当前灾位对应的灾害招式加伤
	if boss != null and is_instance_valid(boss) and boss.has_method("has_debuff"):
		var break_amp := RogueRun.stat("calamity_break_pct")
		if break_amp > 0.0 and bool(boss.call("has_debuff", "zai_beng")):
			out *= 1.0 + break_amp / 100.0
		var per_mark := RogueRun.stat("calamity_per_mark")
		var lone_amp := RogueRun.stat("calamity_lone_pct")
		if per_mark > 0.0 or lone_amp > 0.0:
			var marks := 0
			for mark_id in SkillDB.CALAMITY_MARK_IDS:
				if bool(boss.call("has_debuff", String(mark_id))):
					marks += 1
			if per_mark > 0.0 and marks > 0:
				out *= 1.0 + per_mark / 100.0 * float(marks)
			# 独灾：目标身上只有一种灾痕时反而更痛（与万劫流互斥的赌法）
			if lone_amp > 0.0 and marks == 1:
				out *= 1.0 + lone_amp / 100.0
	var elem_pct := RogueRun.stat("calamity_elem_pct")
	if elem_pct > 0.0 and calamity_element != "" and skill_id != "":
		var sk_def := SkillDB.get_skill(skill_id)
		if not sk_def.is_empty():
			var form_def := MoveDB.get_form(String(sk_def.get("form_id", "")))
			if String(form_def.get("calamity_tag", "")) == calamity_element:
				out *= 1.0 + elem_pct / 100.0
	# 踏影：闪避后的下一击（消费掉）
	if _rogue_step_ready:
		out *= 1.0 + RogueRun.stat("dmg_after_dodge") / 100.0
		_rogue_step_ready = false
	# 镜身·映照 / 换镜·锐：镜像数量与换位窗口
	var mirror_per := RogueRun.stat("mirror_dmg_per")
	if mirror_per > 0.0 and not _mirror_images.is_empty():
		out *= 1.0 + mirror_per / 100.0 * float(_mirror_images.size())
	if _rogue_mirror_swap_left > 0.0:
		out *= 1.0 + RogueRun.stat("mirror_swap_dmg") / 100.0
	# 投影：每 100 影长加伤 / 影长满时额外 / 影兽在场
	var len_dmg := RogueRun.stat("shadow_len_dmg")
	if len_dmg > 0.0:
		out *= 1.0 + len_dmg / 100.0 * (_shadow_len() / 100.0)
	if RogueRun.has_flag("shadow_full_dmg") \
			and _shadow_len() >= ShadowLaw.LANTERN_SHADOW_MAX * 0.99:
		out *= 1.20
	if _shadow_split_left > 0.0:
		var beast_dmg := RogueRun.stat("shadow_beast_dmg")
		if beast_dmg > 0.0:
			out *= 1.0 + beast_dmg / 100.0
	# 折影·折刃：自己场上还有折痕时的通用增伤
	var fold_amp := RogueRun.stat("fold_field_dmg")
	if fold_amp > 0.0 and _fold_has_field():
		out *= 1.0 + fold_amp / 100.0
	# 记下造成伤害的功法：击杀时用它判「万剑 / 开天 击杀返还剑意」
	if skill_id != "":
		_rogue_last_hit_skill = skill_id
	return out


## 肉鸽移速乘区（主模式恒为 1.0）：踏痕（场上有刀痕）/ 急血（残血）
## ⚠ 直接乘在基础移速上，不改 move_speed 本身 —— 否则每帧改属性会和装备刷新打架
func _rogue_move_mult() -> float:
	if not RogueRun.active:
		return 1.0
	var mult := 1.0
	var scar_move := RogueRun.stat("scar_move_pct")
	if scar_move > 0.0:
		var field := ScarField.get_active()
		if field != null and field.normal_count() > 0:
			mult *= 1.0 + scar_move / 100.0
	var low_move := RogueRun.stat("low_hp_move_pct")
	if low_move > 0.0 and max_hp > 0.0 and hp / max_hp <= 0.30:
		mult *= 1.0 + low_move / 100.0
	# 兽潮流·煞贯：虎煞满层时的移速
	var hunt_move := RogueRun.stat("hunt_full_move")
	if hunt_move > 0.0 and RogueRun.hunt_is_full():
		mult *= 1.0 + hunt_move / 100.0
	# 阵旗·旗行：每面旗移速（只在拿到卡时才有值，主模式恒 0）
	var flag_move := RogueRun.stat("array_flag_move")
	if flag_move > 0.0 and not array_flags.is_empty():
		mult *= 1.0 + flag_move / 100.0 * float(array_flags.size())
	# 气环·环行：气环满层移速
	var qi_move := RogueRun.stat("qi_full_move")
	if qi_move > 0.0 and qi_rings >= _qi_max():
		mult *= 1.0 + qi_move / 100.0
	# 逐日·日行：天火种满层移速
	var sun_move := RogueRun.stat("sun_full_move")
	if sun_move > 0.0 and sun_stacks >= RogueRun.cap("sun_max"):
		mult *= 1.0 + sun_move / 100.0
	# 投影·影行：明灭期间移速
	var shadow_move := RogueRun.stat("shadow_dim_move")
	if shadow_move > 0.0 and _shadow_dim_left > 0.0:
		mult *= 1.0 + shadow_move / 100.0
	return mult


# ===== 肉鸽爬塔：以意御法 / 洗髓 / 击杀结算 =====

## 以意御法：本次施法灵力不足时，用剑意补足（每 1 层抵 10 灵力）
## ⚠ 只是「先垫上让校验通过」；真正扣层在 _rogue_commit_intent_mana（施法成功之后）
func _rogue_prepare_intent_mana(cast_id: String) -> void:
	_rogue_borrowed_stacks = 0
	_rogue_borrowed_mana = 0.0
	if not RogueRun.active or not RogueRun.has_flag("intent_as_mana") or sword_intent <= 0:
		return
	var c := SkillDB.get_skill_cost(cast_id)
	if String(c.get("cost_kind", "")) != MoveDB.COST_MANA:
		return
	var need := float(c.get("mana_cost", 0.0))
	if need <= mana:
		return
	var deficit := need - mana
	var stacks := mini(int(ceil(deficit / 10.0)), sword_intent)
	if stacks <= 0:
		return
	_rogue_borrowed_stacks = stacks
	_rogue_borrowed_mana = minf(deficit, float(stacks) * 10.0)
	mana += _rogue_borrowed_mana
	_update_mana_bar()


func _rogue_rollback_intent_mana() -> void:
	if _rogue_borrowed_mana <= 0.0:
		return
	mana = maxf(0.0, mana - _rogue_borrowed_mana)
	_rogue_borrowed_mana = 0.0
	_rogue_borrowed_stacks = 0
	_update_mana_bar()


func _rogue_commit_intent_mana() -> void:
	if _rogue_borrowed_stacks <= 0:
		return
	_lose_sword_intent(_rogue_borrowed_stacks)
	_rogue_borrowed_stacks = 0
	_rogue_borrowed_mana = 0.0


## 洗髓：每层开始回满血 / 灵力 / 精力，并清空全部负面
func rogue_full_restore() -> void:
	hp = max_hp
	stamina = max_stamina
	mana = max_mana
	debuffs.clear()
	health_changed.emit(hp, max_hp)
	_update_health_bar()
	_update_stamina_bar()
	_update_mana_bar()


## 肉鸽：按气血上限的百分比回血（刀痕斩击等外部伤害来源调用）
## pct 是「点」，2.0 = 回 2% 气血上限
func rogue_heal_pct(pct: float) -> void:
	if not RogueRun.active or pct <= 0.0 or is_dead:
		return
	if hp >= max_hp:
		return
	hp = minf(max_hp, hp + max_hp * pct / 100.0)
	health_changed.emit(hp, max_hp)
	_update_health_bar()


## 击杀结算：饮血 / 引灵 / 顺势 + 万剑与开天的「击杀返还剑意」
## 由肉鸽竞技场在小怪或 BOSS 死亡时调用（玩家自己不监听击杀）
## victim：被击杀的单位（可为 null）。机制卡「猎杀本能 / 灾疫」需要它判精英与灾痕。
func _rogue_on_kill(victim: Node = null) -> void:
	if not RogueRun.active:
		return
	# 嗜杀：任何击杀都叠 1 层杀意（没拿卡时 cap = 0，函数内部自己早退）
	RogueRun.add_kill_mark(1)
	var heal := RogueRun.stat("heal_on_kill")
	if heal > 0.0 and hp < max_hp:
		hp = minf(max_hp, hp + max_hp * heal / 100.0)
		health_changed.emit(hp, max_hp)
		_update_health_bar()
	var mp := RogueRun.stat("mana_on_kill")
	if mp > 0.0 and mana < max_mana:
		mana = minf(max_mana, mana + mp)
		_update_mana_bar()
	var cd := RogueRun.stat("cd_on_kill")
	if cd > 0.0:
		var keys: Array = []
		for k in skill_cooldowns.keys():
			if float(skill_cooldowns[k]) > 0.0:
				keys.append(k)
		if not keys.is_empty():
			var pick := String(keys[randi() % keys.size()])
			skill_cooldowns[pick] = maxf(0.0, float(skill_cooldowns[pick]) - cd)
	if RogueRun.has_flag("myriad_kill_refund") and _rogue_last_hit_skill == "skill_sword_myriad":
		_gain_sword_intent(2)
	if RogueRun.has_flag("heaven_kill_refund") \
			and _rogue_last_hit_skill in ["skill_sword_heaven", "skill_sword_heaven_full"]:
		_gain_sword_intent(_sword_intent_max())
	# 兽潮流：击杀叠虎煞；「万兽」在满层时把踏地冷却直接砍掉 4 秒
	RogueRun.add_hunt(1)
	# 猎杀本能：精英额外获得 N 层虎煞（BOSS 击杀走 _rogue_on_boss_kill，避免重复叠）
	if victim != null and is_instance_valid(victim):
		var big_hunt := int(RogueRun.stat("hunt_on_big_kill"))
		if big_hunt > 0 and String(victim.name).ends_with("rogue_elite"):
			RogueRun.add_hunt(big_hunt)
	# 盗火：击杀补天火种（只有手持火种时 _rogue_gain_sun_stack 才生效）
	var sun_gain := int(RogueRun.stat("sun_on_kill"))
	for _i in sun_gain:
		_rogue_gain_sun_stack()
	# 灾疫：三痕俱在的敌人死亡时，把三痕传给最近的另一个敌人
	if RogueRun.has_flag("calamity_plague") and victim != null and is_instance_valid(victim):
		_rogue_spread_calamity(victim)
	if RogueRun.hunt_is_full() and RogueRun.has_flag("hunt_full_bloom"):
		var stomp_cd := float(skill_cooldowns.get("skill_tiger_stomp", 0.0))
		if stomp_cd > 0.0:
			skill_cooldowns["skill_tiger_stomp"] = maxf(0.0, stomp_cd - 4.0)
	_rogue_on_kill_family()
	_rogue_last_hit_skill = ""


## 各流派「击杀触发」类增益：统一在这里收口，避免每条都去改 _rogue_on_kill
## ⚠ 依赖 _rogue_last_hit_skill —— 调用点必须在 _rogue_on_kill 清空它之前
func _rogue_on_kill_family() -> void:
	if not RogueRun.active:
		return
	var last := _rogue_last_hit_skill
	# 两仪·崩势：太极崩击杀返还 2 层势
	if last == "skill_yinyang_collapse" and RogueRun.has_flag("yy_collapse_refund"):
		yinyang_stacks = mini(_yinyang_max(), yinyang_stacks + 2)
		_refresh_yinyang_pips()
	# 气环·爆环：气爆击杀返还 2 层气环
	if last == "skill_qi_burst" and RogueRun.has_flag("qi_burst_refund"):
		_add_qi(2)
	# 判词雷·雷殛：九霄雷罚击杀返还全部雷势
	if last == "skill_thunder_nine" and RogueRun.has_flag("pillar_kill_refund"):
		lei_shi = _thunder_max()
		_refresh_thunder_hud()
	# 判词雷·定刑·极：雷殛击杀刷新全部功法冷却
	if last == "skill_thunder_execute" and RogueRun.has_flag("exec_kill_reset"):
		skill_cooldowns.clear()
		_show_float_text("定刑 · 冷却尽消", Color(0.86, 0.70, 1.0))
	# 逐日·日归：投日击杀返还 1 层天火种
	if last == "skill_sun_throw" and RogueRun.has_flag("sun_throw_refund"):
		_rogue_gain_sun_stack()
	# 三灾·劫尽：万劫归一击杀刷新自身冷却
	if last == "skill_calamity_final" and RogueRun.has_flag("calamity_final_reset"):
		skill_cooldowns.erase("skill_calamity_final")


## BOSS 击杀的机制卡结算：普通击杀走 _rogue_on_kill，BOSS 不走那条路
## （on_boss_defeated 只发修为与遗物），所以这里单独补上击杀类新卡的触发。
func _rogue_on_boss_kill(_victim: Node = null) -> void:
	if not RogueRun.active:
		return
	RogueRun.add_kill_mark(1)
	var big_hunt := int(RogueRun.stat("hunt_on_big_kill"))
	if big_hunt > 0:
		RogueRun.add_hunt(big_hunt)
	var sun_gain := int(RogueRun.stat("sun_on_kill"))
	for _i in sun_gain:
		_rogue_gain_sun_stack()


## 灾疫：把死者身上的三痕转给最近的存活敌人（400 内）
## ⚠ 目标恒定是敌人（BossBase 系），apply_debuff 是 (id, seconds, from_unit) 三参；
##   不会走到玩家那套 (id, seconds, quiet: bool) 签名上。
func _rogue_spread_calamity(victim: Node) -> void:
	if not victim.has_method("has_debuff") or not victim is Node2D:
		return
	var marks: Array = []
	for mark_id in SkillDB.CALAMITY_MARK_IDS:
		if bool(victim.call("has_debuff", String(mark_id))):
			marks.append(String(mark_id))
	if marks.size() < SkillDB.CALAMITY_MARK_IDS.size():
		return
	var from_pos: Vector2 = (victim as Node2D).global_position
	var best: Node2D = null
	var best_dist := 400.0
	for raw in _array_enemy_units():
		if not is_instance_valid(raw) or raw == victim or not raw is Node2D:
			continue
		if BossBase.is_unit_dead(raw):
			continue
		var d := (raw as Node2D).global_position.distance_to(from_pos)
		if d <= best_dist:
			best_dist = d
			best = raw as Node2D
	if best == null or not best.has_method("apply_debuff"):
		return
	for mark_id in marks:
		best.call("apply_debuff", String(mark_id), 6.0, self)
	_show_float_text("灾疫 · 三痕传染", Color(0.86, 0.62, 0.42))


## 肉鸽「引雷」：对眩晕目标造成雷击时，追加一道 0.8× 法强落雷
## ⚠ 带 1.5 秒内置 CD：多段雷招一次能命中同一目标好几次，不限频会瞬间刷满屏
func _rogue_try_lei_chain(boss: Node, elem: String, skill_id: String) -> void:
	if not RogueRun.active or _rogue_lei_chain_left > 0.0:
		return
	var coeff := RogueRun.stat("lei_chain_coeff")
	if coeff <= 0.0:
		return
	if elem != "thunder" and not skill_id.begins_with("skill_thunder_"):
		return
	if boss == null or not is_instance_valid(boss) or not boss.has_method("has_debuff"):
		return
	if not bool(boss.call("has_debuff", "stun")):
		return
	_rogue_lei_chain_left = 1.5
	var dmg := CharacterData.spell_attack() * coeff
	# ⚠ 目标是 BossBase 系：签名是 (amount, source, kind, element)，与玩家侧相反
	boss.call("take_damage", dmg, self, "elemental", "thunder")
	_show_float_text("引雷 · 追加天雷", Color(0.80, 0.74, 1.0))


## 肉鸽「印染」：把一枚印传给 320 内最近的另一个敌人
## ⚠ 目标恒定是敌人 → apply_debuff 走 BossBase 的三参签名 (id, seconds, from_unit)
func _rogue_spread_yinyang_mark(from: Node2D, mark: String) -> void:
	var best: Node2D = null
	var best_dist := 320.0
	for raw in _array_enemy_units():
		if not is_instance_valid(raw) or raw == from or not raw is Node2D:
			continue
		if BossBase.is_unit_dead(raw):
			continue
		var d := (raw as Node2D).global_position.distance_to(from.global_position)
		if d <= best_dist:
			best_dist = d
			best = raw as Node2D
	if best == null or not best.has_method("apply_debuff"):
		return
	best.call("apply_debuff", mark, YINYANG_MARK_SECONDS + RogueRun.stat("yy_mark_sec"), self)


func _yinyang_modify_damage(boss: Node, kind: String, damage: float, skill_id: String,
		can_stack: bool = true) -> float:
	if not _yinyang_unlocked or damage <= 0.0:
		return damage
	if not _yinyang_universal() and not _is_yinyang_skill(skill_id):
		return damage
	var polarity := _yinyang_hit_polarity(kind, skill_id)
	if polarity < 0:
		return damage
	var is_reverse := false
	if can_stack and has_buff("yinyang_reverse"):
		is_reverse = true
		remove_buff("yinyang_reverse")
	elif polarity != yinyang_polarity:
		is_reverse = true
	elif can_stack and yinyang_stacks == 0:
		# 空条 = 还没有仪态：第一发不论阴阳都算起势（+1 层并定色）。
		# 否则开局按阳色算，物理玩家的第一发永远同色、叠不起来，只有法术能起势。
		is_reverse = true
	# 肉鸽「同流」：同色命中也算起势，但只给 10% 的弱化加成（换掉逆式的 20%）
	var same_flow := false
	if not is_reverse and can_stack and RogueRun.active and RogueRun.has_flag("yy_same_stack"):
		same_flow = true
	var dmg := damage
	if is_reverse:
		dmg *= 1.0 + YINYANG_REVERSE_BONUS + RogueRun.stat("yy_reverse_pct") / 100.0
		if can_stack:
			yinyang_stacks = mini(_yinyang_max(),
				yinyang_stacks + 1 + int(RogueRun.stat("yy_extra_stack")))
			yinyang_polarity = polarity
			# 逆式回灵（肉鸽「借势」；主模式 stat 恒 0，不进这个分支）
			var back_mana := RogueRun.stat("yy_mana_reverse")
			if back_mana > 0.0 and mana < max_mana:
				mana = minf(max_mana, mana + back_mana)
				_update_mana_bar()
	elif same_flow:
		dmg *= 1.10
		yinyang_stacks = mini(_yinyang_max(), yinyang_stacks + 1)
		yinyang_polarity = polarity
	elif can_stack:
		yinyang_polarity = polarity
	dmg *= 1.0 + (YINYANG_STACK_BONUS + RogueRun.stat("yy_stack_pct") / 100.0) \
		* float(yinyang_stacks)

	# 印：两仪功法挂印；任意异属性命中引爆对方的印（后续触发也结算逆印，但不挂新印）
	if boss != null and is_instance_valid(boss) and boss.has_method("has_debuff"):
		var is_yang := polarity == YINYANG_YANG
		var opposite_mark := "yin_mark" if is_yang else "yang_mark"
		if bool(boss.call("has_debuff", opposite_mark)):
			dmg *= 1.0 + YINYANG_MARK_BONUS + RogueRun.stat("yy_mark_pct") / 100.0
			# 肉鸽「双印」：引爆时补一段法强伤害；「印回」顺手回血
			var mark_burst := RogueRun.stat("yy_mark_burst")
			if mark_burst > 0.0:
				dmg += CharacterData.spell_attack() * mark_burst
			var mark_heal := RogueRun.stat("yy_mark_heal")
			if mark_heal > 0.0:
				rogue_heal_pct(mark_heal)
			if boss.has_method("remove_debuff"):
				boss.call("remove_debuff", opposite_mark)
			# 肉鸽「印染」：引爆时把同色印传染给最近的另一个敌人
			if RogueRun.has_flag("yy_mark_spread") and boss is Node2D:
				_rogue_spread_yinyang_mark(boss as Node2D,
					"yang_mark" if is_yang else "yin_mark")
			_show_float_text("阴阳爆！", _yinyang_color())
		if can_stack and skill_id != "":
			var sk := SkillDB.get_skill(skill_id)
			if bool(sk.get("yinyang", false)) and boss.has_method("apply_debuff"):
				var mark := "yang_mark" if is_yang else "yin_mark"
				boss.call("apply_debuff", mark,
					YINYANG_MARK_SECONDS + RogueRun.stat("yy_mark_sec"))
	_refresh_yinyang_pips()
	return dmg


## 玩家来源的**直接伤害**统一入口（不走扇形 / 矩形判定的技能）。
## 阵旗、气环、环身气、刀痕这类世界层结算原来直接 take_damage，佩戴「负阴抱阳」后也绕过两仪势；
## 这里统一先过 `_yinyang_modify_damage`，让被动真正覆盖「所有伤害来源」。
## 未解锁 / 未佩戴被动时，非两仪技能的伤害会原样返回，行为不变。
func _deal_direct_damage(target: Node, amount: float, kind: String,
		elem: String = "", skill_id: String = "", can_stack: bool = true,
		notify_calamity: bool = true) -> void:
	if target == null or not is_instance_valid(target) or not target.has_method("take_damage"):
		return
	var final_dmg := _yinyang_modify_damage(target, kind, amount, skill_id, can_stack)
	final_dmg = _rogue_modify_damage(final_dmg, target, kind, skill_id)
	target.call("take_damage", final_dmg, self, kind, elem)
	_note_thunder_skill_hit(target, skill_id, elem)
	_try_arm_sun_nova(target, skill_id)
	if notify_calamity:
		notify_calamity_element_hit(target, elem, skill_id)


## 玩家功法命中后的附带 debuff（招式表根字段 debuff_on_hit / debuff_time）。
## BOSS 侧在 _apply_form_debuff 里做同一件事；玩家侧此前没有入口，阴诀的「阴蚀」会只写在描述里。
func _apply_player_skill_debuff(boss: Node, skill_id: String) -> void:
	if skill_id == "" or boss == null or not is_instance_valid(boss):
		return
	if not boss.has_method("apply_debuff"):
		return
	var form := SkillDB.get_skill_form(skill_id)
	var debuff_id := String(form.get("debuff_on_hit", ""))
	if debuff_id == "":
		return
	boss.call("apply_debuff", debuff_id, float(form.get("debuff_time", 3.0)))
	_attach_calamity_marks_if_needed(boss, debuff_id)


## 肉鸽「命中附加」：碎甲（破防）/ 迷眼（减速）。主模式恒为空操作。
## ⚠ 投射物**不走** _apply_player_skill_debuff（那条只在近战形状结算里调），
##   player_projectile 会单独再调一次本函数 —— 两处必须是同一份判定。
func _rogue_apply_hit_debuff(target: Node, skill_id: String) -> void:
	if not RogueRun.active or target == null or not is_instance_valid(target):
		return
	if not target.has_method("apply_debuff"):
		return
	var break_sec := RogueRun.stat("break_sec")
	if break_sec > 0.0 \
			and (skill_id == "skill_tiger_stomp" or skill_id == "skill_tiger_claw"):
		target.call("apply_debuff", "armor_break", break_sec)
	var slow_sec := RogueRun.stat("sand_slow_sec")
	if slow_sec > 0.0 and skill_id == "skill_tiger_sandstorm":
		target.call("apply_debuff", "blinding_sand", slow_sec)
	# 肉鸽「兽性」：虎煞满层时踏地自带 3 秒破防（不依赖「碎甲」卡）
	if skill_id == "skill_tiger_stomp" and RogueRun.has_flag("hunt_stomp_free") \
			and RogueRun.hunt_is_full():
		target.call("apply_debuff", "armor_break", 3.0)


## 太极崩：基础 1.2 物理 + 1.8 法术，每层势再 +0.5 / +0.5。
## 不走 SkillDB 的固定系数 —— 势是招式释放前现读并清空的。
func _calc_collapse_damage(stacks: int) -> float:
	var sid := "skill_yinyang_collapse"
	# 肉鸽「蓄崩」：每层势的系数再加一点（主模式 stat 恒 0）
	var per := SkillDB.YINYANG_COLLAPSE_COEFF_PER_STACK + RogueRun.stat("yy_collapse_per")
	var phys_c := (SkillDB.get_phys_coeff(sid) + per * float(stacks)) \
		* CharacterData.sword_intent_skill_mult
	var spell_c := SkillDB.get_spell_coeff(sid) + per * float(stacks)
	var ctx := {
		"phys_power": CharacterData.physical_attack(),
		"spell_power": CharacterData.spell_attack(),
		"phys_coeff": phys_c,
		"spell_coeff": spell_c,
		"random": true,
	}
	return float(DamageCalc.resolve(ctx).get("amount", 0.0)) * CharacterData.sun_damage_mult


## 双鱼的单枚弹：只走自己那一段系数（阳弹吃物抗、阴弹吃法抗）。
## 乘区与 CharacterData.calc_skill_damage 一致，区别是不把两段加起来 ——
## 合起来算就变成「一发起两段伤害」，两色也就没了。
func _calc_polarity_damage(coeff: float, is_yang: bool) -> float:
	if coeff <= 0.0:
		return 0.0
	var phys_c := 0.0
	var spell_c := 0.0
	if is_yang:
		phys_c = coeff * ItemDB.WEAPON_COEFF * ItemDB.SKILL_DAMAGE_COEFF \
			* CharacterData.sword_intent_skill_mult
	else:
		spell_c = coeff * ItemDB.SKILL_DAMAGE_COEFF * CharacterData.spell_skill_damage_mult()
	var ctx := {
		"phys_power": CharacterData.physical_attack(),
		"spell_power": CharacterData.spell_attack(),
		"phys_coeff": phys_c,
		"spell_coeff": spell_c,
		"random": true,
	}
	return float(DamageCalc.resolve(ctx).get("amount", 0.0)) * CharacterData.sun_damage_mult


## 两仪·双鱼：阳弹在前（挂阳印），阴弹在后（正好引爆阳印并改挂阴印）。
## 两枚一阴一阳 → 一次出手就能走完「阳→阴」的逆式，这是它叠势最快的原因；
## 代价是两枚都得命中同一个目标，所以系数只有掌/指的一半多。
func _cast_yinyang_fish(form: Dictionary, dir: Vector2, coeff_mult: float) -> void:
	var packed := _projectile_scene()
	if packed == null:
		push_warning("玩家投射物场景缺失：" + PLAYER_PROJECTILE_SCENE)
		return
	var sid := "skill_yinyang_fish"
	var sfx := ArtDB.get_skill_fx(sid)
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	var shots := [
		{"yang": true, "coeff": SkillDB.get_phys_coeff(sid), "kind": "physical", "elem": "fire",
			"color": Color(0.98, 0.82, 0.38, 1.0), "trail": "ember", "phase": 0.0},
		{"yang": false, "coeff": SkillDB.get_spell_coeff(sid), "kind": "elemental", "elem": "water",
			"color": Color(0.48, 0.90, 0.98, 1.0), "trail": "smoke", "phase": PI},
	]
	var angle := dir.angle()
	var ahead := dir.normalized()
	for shot in shots:
		var dmg := _calc_polarity_damage(float(shot["coeff"]), bool(shot["yang"])) * coeff_mult
		if dmg <= 0.0:
			continue
		var proj: Node2D = packed.instantiate()
		proj.skill_id = sid
		proj.source = self
		proj.damage = dmg
		proj.damage_kind = String(shot["kind"])
		proj.element = String(shot["elem"])
		proj.speed = float(form.get("speed", 600.0))
		proj.max_distance = float(form.get("range", 600.0))
		proj.direction = Vector2.RIGHT.rotated(angle)
		proj.visual_color = Color(shot["color"])
		proj.trail_kind = String(shot["trail"])
		proj.trail_color = Color(shot["color"])
		var pv := String(sfx.get("projectile_visual", ""))
		if pv != "":
			proj.visual_id = pv
		# 反相的正弦横移：两枚在飞行途中互相交叉（与 BOSS 侧同一份数据、同一套手感）
		proj.swim_amp = float(form.get("swim_amp", 0.0))
		proj.swim_freq = float(form.get("swim_freq", 0.0))
		proj.swim_phase = float(shot["phase"])
		proj.launch_side = 1.0 if bool(shot["yang"]) else -1.0
		# 阳弹在前、阴弹在后，沿飞行轴错开 46 像素：命中顺序由位置决定，
		# 「阳挂印 → 阴引爆并改挂阴印」才是确定的，视觉上也真是双鱼衔尾
		proj.position = global_position + ahead * (23.0 if bool(shot["yang"]) else -23.0)
		get_parent().add_child(proj)
		if not proj.align_visual:
			proj.rotation = angle


## 太极崩 3 层：额外硬直 + 同时挂双印
func _apply_collapse_finish() -> void:
	var radius := 260.0
	for b in get_tree().get_nodes_in_group("boss"):
		# ⚠ 死单位不参与索敌 / 结算：试炼里 BOSS 尸体不销毁、仍在 "boss" 组
		if BossBase.is_unit_dead(b):
			continue
		if not is_instance_valid(b) or not (b is Node2D):
			continue
		if global_position.distance_to((b as Node2D).global_position) > radius + 60.0:
			continue
		if b.has_method("stagger_for"):
			b.call("stagger_for", SkillDB.YINYANG_COLLAPSE_STAGGER_SECONDS)
		if b.has_method("apply_debuff"):
			b.call("apply_debuff", "yang_mark", YINYANG_MARK_SECONDS)
			b.call("apply_debuff", "yin_mark", YINYANG_MARK_SECONDS)


## 肉鸽两仪：太极崩命中后的附带（定身崩硬直 / 崩息回灵）。主模式整段早退，行为不变。
func _rogue_collapse_extras() -> void:
	if not RogueRun.active:
		return
	var mana_back := RogueRun.stat("yy_collapse_mana")
	if mana_back > 0.0 and mana < max_mana:
		mana = minf(max_mana, mana + mana_back)
		_update_mana_bar()
	if not RogueRun.has_flag("yy_collapse_stun"):
		return
	var radius := float(MoveDB.resolve_player("form_yinyang_collapse").get("range", 200.0))
	for raw in _array_enemy_units():
		if not is_instance_valid(raw) or not (raw is Node2D):
			continue
		if global_position.distance_to((raw as Node2D).global_position) > radius + 40.0:
			continue
		if raw.has_method("stagger_for"):
			raw.call("stagger_for", 1.2)
		elif raw.has_method("apply_debuff"):
			raw.call("apply_debuff", "stun", 1.2)


## 两仪转：翻自己的仪态；清阴蚀；消耗 1 层势，使下一招必定逆式。
func _cast_yinyang_flip() -> void:
	yinyang_polarity = YINYANG_YIN if yinyang_polarity == YINYANG_YANG else YINYANG_YANG
	debuffs.erase("yin_erosion")
	if yinyang_stacks > 0:
		yinyang_stacks -= 1
		apply_buff("yinyang_reverse", SkillDB.YINYANG_FLIP_FORCE_SECONDS)
	_refresh_yinyang_pips()
	_show_float_text("两仪转！", _yinyang_color())


## 两仪·倒悬 —— 奉还一发与当前势同色的攻击：免伤、势翻面、+1 层。
## ⚠ 奉还完立刻翻面是刻意的：同色连打只能吸第一发，第二发就成异色 → 破势。
##    想连续奉还得让攻击一阴一阳地来，读的是自己的势 —— 与「弹刀只看时机」分工清楚。
func _absorb_yinyang_ward(incoming: int) -> void:
	yinyang_polarity = YINYANG_YIN if incoming == YINYANG_YANG else YINYANG_YANG
	yinyang_stacks = mini(_yinyang_max(), yinyang_stacks + 1)
	_refresh_yinyang_pips()
	_show_float_text("奉还！", _yinyang_color())


## 两仪·倒悬 —— 被异色打散：守势碎、这一发的反击不斩出，伤害 ×1.3 照吃
func _break_yinyang_ward() -> void:
	_counter_charging = false
	_finish_counter_ward()
	_show_float_text("势破！", UIKit.C_FLOAT_WARN)


func _notify_bosses(method: String) -> void:
	for b in get_tree().get_nodes_in_group("boss"):
		# ⚠ 死单位不参与索敌 / 结算：试炼里 BOSS 尸体不销毁、仍在 "boss" 组
		if BossBase.is_unit_dead(b):
			continue
		if is_instance_valid(b) and b.has_method(method):
			b.call(method)


# ===== 剑意（玩家侧）=====

## 被动「剑心通明」是否佩戴（认 passive_effect，不硬比 skill_id）
func _sword_intent_passive_on() -> bool:
	var gate := SkillDB.get_passive_by_effect("sword_intent_physical")
	return not gate.is_empty() and String(gate.get("skill_id", "")) in CharacterData.passive_skill_loadout


## 把「层数 × 每层增伤」写进 CharacterData 的物理功法乘区。
## 普攻 / 法术 / 召唤物不走 calc_skill_damage 的物理段，自然不会吃到。
func _sync_sword_intent_skill_mult() -> void:
	var mult := 1.0
	if _sword_intent_passive_on():
		# 肉鸽「意涌」：每层剑意的增幅再加 N%（主模式 stat 恒为 0）
		var per := SkillDB.SWORD_INTENT_PHYS_PER_STACK + RogueRun.stat("intent_amp") / 100.0
		mult += float(sword_intent) * per
	CharacterData.sword_intent_skill_mult = mult


## 物理近战功法：物理系数为主、非投射物。大招由 _cast_skill 的 is_ultimate 单独排除。
func _is_physical_melee_skill(form: Dictionary) -> bool:
	var phys := float(form.get("phys_coeff", 0.0))
	var spell := float(form.get("spell_coeff", 0.0))
	if phys <= 0.0 or spell > phys:
		return false
	return String(form.get("hit_shape", "")) != MoveDB.SHAPE_PROJECTILE


## 剑意 +N（已满则不再涨，与 BOSS 侧 _gain_intent 同规则）
## 肉鸽增益「聚意」让每次获取额外 +1 层（只影响获取，不影响受击扣层）
func _gain_sword_intent(n: int) -> void:
	var cap := _sword_intent_max()
	if n <= 0 or sword_intent >= cap:
		return
	sword_intent = mini(cap, sword_intent + n + int(RogueRun.stat("intent_gain_bonus")))
	_sync_sword_intent_skill_mult()
	# 每层一点视觉反馈（走 ArtDB.EFFECTS，换美术只改表）
	FxPlayer.spawn(self, "fx_sword_intent", {
		"position": _body_center() + Vector2(0.0, -34.0),
		"lifetime": 0.4,
	})


## 剑意 -N（受击 / 被大招消耗）
func _lose_sword_intent(n: int) -> void:
	if n <= 0 or sword_intent <= 0:
		return
	var before := sword_intent
	sword_intent = maxi(0, sword_intent - n)
	_sync_sword_intent_skill_mult()
	# 肉鸽「意尽」：只有真的清空才炸（掉 1 层还剩几层时不触发）
	if sword_intent == 0 and before > 0:
		_rogue_intent_break(before)


## 肉鸽「意尽」：剑意被清空时按清空层数在身周炸开一圈
## ⚠ 两个清空入口（大招放完 / 受击掉光）都必须走这里，否则「放完大招不炸」很隐蔽
func _rogue_intent_break(cleared: int) -> void:
	if not RogueRun.active or cleared <= 0:
		return
	var coeff := RogueRun.stat("intent_break_coeff")
	if coeff <= 0.0:
		return
	var dmg := CharacterData.physical_attack() * coeff * float(cleared)
	_damage_bosses_in_shape(Vector2.RIGHT, 280.0, PI, dmg, "physical", "", true, "")
	_show_float_text("意尽 · %d 层爆发" % cleared, Color(0.86, 0.90, 1.0))


## 剑意是否叠满（战斗 HUD 的「剑气环绕」图标特效读它）
func is_sword_intent_full() -> bool:
	return sword_intent >= _sword_intent_max()


## 施放功法（消耗已在 try_use_skill 扣过）
## 剑意流程：满层时一剑开天切换法术矩形巨斩变体 → 万剑归宗按层数算飞剑数 →
##            大招清空剑意 / 基础四式释放 +1 → 前摇后按 eff_id 的系数结算
func _cast_skill(skill_id: String) -> void:
	var form := SkillDB.get_skill_form(skill_id)
	if form.is_empty():
		push_warning("功法 %s 未关联招式形态" % skill_id)
		return
	# 主动出手 = 放弃守势：自动弹刀窗口立即失效
	# （放在校验之后：资源不足放不出来时，不算「出手」，守势仍保留）
	auto_parry_timer = 0.0
	emit_noise()

	# 太极崩：释放瞬间把势读进 _collapse_stacks 并清空；伤害由 _apply_skill_hit 现算
	if skill_id == "skill_yinyang_collapse":
		_collapse_stacks = yinyang_stacks
		yinyang_stacks = 0
		_refresh_yinyang_pips()

	# ===== 剑意结算（先判定层数，再消耗）=====
	# 大招（万剑归宗有 intent_count_scale / 一剑开天有 full_form_id）放完清空剑意；
	# 基础四式（有 intent_gain）仅释放 +1，命中不叠加
	var ics: Dictionary = form.get("intent_count_scale", {})
	var has_full_form: bool = String(form.get("full_form_id", "")) != ""
	var is_ultimate: bool = (not ics.is_empty()) or has_full_form
	# 一剑开天满层 → 切换法术矩形巨斩变体（skill_sword_heaven_full，is_variant 条目）
	# 肉鸽「天成」：无需满层也能切满形态（代价照旧：抽空全部精力与灵力）
	var eff_id := skill_id
	if has_full_form and (RogueRun.has_flag("heaven_free") or sword_intent >= _sword_intent_max()):
		var full_skill := SkillDB.get_skill_id_by_form(String(form.get("full_form_id", "")))
		if full_skill != "":
			eff_id = full_skill
			form = SkillDB.get_skill_form(eff_id)
	# 万剑归宗：飞剑数 = base + 剑意×per + 肉鸽「万剑·盈」（必须在清空**之前**按当前层数算好）
	if not ics.is_empty():
		form["count"] = int(ics.get("base", MYRIAD_BASE_COUNT)) \
			+ sword_intent * int(ics.get("per", MYRIAD_PER_INTENT)) \
			+ int(RogueRun.stat("myriad_count"))
	if is_ultimate:
		var spent := sword_intent
		sword_intent = 0
		_sync_sword_intent_skill_mult()
		_rogue_intent_break(spent)
	else:
		var ig := int(form.get("intent_gain", 0))
		# 剑心通明：把积攒范围从剑客四式扩展到所有物理近战功法；
		# 四式本来就有 intent_gain，不重复加；投射物与大招不在此列。
		if ig <= 0 and _sword_intent_passive_on() and _is_physical_melee_skill(form):
			ig = 1
		if ig > 0:
			_gain_sword_intent(ig)

	# 带位移的招式：有移动输入时优先按玩家方向释放；没有输入才自动朝 BOSS
	var dir := _skill_cast_dir(form)
	# 逐日步特例：无方向输入时优先朝火种；无火种 / 火种在身上才朝 BOSS。
	if eff_id == "skill_sun_step":
		dir = _sun_step_dir(_get_move_dir(), dir)

	# 阵旗八式：前摇起手报招名 + 布点预告（与 BOSS 的 show_windup_line / 同色阵纹同节奏）
	_array_precast(eff_id, dir)
	# 气君八式：同一套起手报招名；缩地的云步拖尾也在起手帧铺
	_qi_precast(eff_id, dir)
	# 判词八式：起手报判词名称（玩家在前摇第一帧就知道会被罚什么）
	_thunder_precast(eff_id, dir)
	# 逐日八式：起手报招名；投日/日蚀/天火坠额外报应对
	_sun_precast(eff_id, dir)
	# 三灾八式：灾位在起手帧就切换（BOSS 能看到你当前灾位）
	_calamity_precast(eff_id)
	_mirror_precast(eff_id)
	# 执烛八式：起手报招名，并把影亮点亮一拍（影长就是这一招的射程）
	_shadow_precast(eff_id, dir)
	_fold_precast(eff_id, dir)
	# 直线影技的射程按当前影长覆盖（判定与特效同一份数据）
	form = _shadow_fit_form(eff_id, form)
	form = _fold_fit_form(eff_id, form)
	# 肉鸽「兽性」：虎煞满层时踏地范围 +50%（判定与特效读同一份 form）
	if RogueRun.active and RogueRun.has_flag("hunt_stomp_free") \
			and eff_id == "skill_tiger_stomp" and RogueRun.hunt_is_full():
		var stomp_form: Dictionary = form.duplicate(true)
		stomp_form["range"] = float(stomp_form.get("range", 150.0)) * 1.5
		form = stomp_form

	# 纳势反击这类「蓄力格挡」功法：不走常规「前摇 → 命中」流程
	var charge_max := float(form.get("charge_max", 0.0))
	if charge_max > 0.0:
		_begin_counter_charge(skill_id, form, dir, charge_max)
		return

	# 弹反追击：完美弹反窗口内，近战物理功法也能快速贴近（与普攻同一套位移）
	var used_followup := false
	if _skill_allows_followup_dash(form):
		used_followup = _parry_followup_dash(float(form.get("range", ATTACK_RANGE)))

	var windup := float(form.get("windup", 0.0))

	# 朝向锁定：技能朝 dir 打、前摇里人也朝 dir 冲 → 立刻翻面并锁住这段时间。
	# ⚠ 必须放在 _start_skill_dash 之前：漏了这一段就会出现「人已经朝 BOSS 冲出去了、
	#   身体还朝着反方向」——破步突进斩前摇前半段正是这样（2026-10-26 用户报的现象）。
	_lock_skill_facing(dir, windup)

	# 招式自带前冲（move_forward）：「破步突进斩」这类突进技靠它位移。
	# ⚠ move_forward 写在 player{} 子表里，而 get_skill_form 返回的是**合并后的玩家侧**数据，
	#   所以这里直接取根字段即可（不要再去翻 form["player"]）。
	# ⚠ 与弹反追击互斥 —— 那段用 tween 直接改坐标，两段叠在一起会把玩家送过头。
	var move_forward := float(form.get("move_forward", 0.0))
	if move_forward > 0.0 and not used_followup:
		move_forward = _zhehen_fold_escape(skill_id, move_forward)
		_start_skill_dash(dir, move_forward, windup)

	# 表现与判定同源：都用这一份形态数据（BOSS 用同一形态时表现完全一致）
	_spawn_skill_visual(form, dir, eff_id)

	# 一剑开天：伤害等剑真正落地（SwordHeavenFx 的劈落段走完）再结算，
	# 和地面劈痕同一帧；否则先掉血、剑还悬在半空
	var hit_delay := windup
	if bool(form.get("fx_heaven", false)):
		hit_delay += maxf(float(form.get("fx_release_time", 0.12)), 0.0)

	if hit_delay > 0.0:
		# ignore_time_scale=true：顿帧期间不拖慢技能节奏
		await get_tree().create_timer(hit_delay, true, false, true).timeout
		if not is_instance_valid(self) or is_dead:
			return
	_apply_skill_hit(eff_id, form, dir)
	# 镜身：本体这一招收完，场上剩下的镜像一起复读同一招
	# （放在后面才不会被自己抢走口粮 —— 碎镜 / 换镜本身就要消耗一具镜像）
	_mirror_on_skill_cast(eff_id, form)
	# 投影：削影在影长够长时，影尖同帧补一段短削
	_shadow_after_cast(eff_id, form, dir)

	# 原地领域（阴诀·蚀骨风）：同一个圆分几跳结算，跳与跳之间人不动。
	# 每一跳都重新起特效 —— 判定和看得见的范围必须同帧。
	await _skill_tick_repeats(eff_id, form, dir)

	# 连续突进斩（破步突进斩 2026-10-23）：第一段斩完，接着再突进再斩
	await _skill_dash_followups(eff_id, form, dir)


## 领域类招式的后续跳（player_ticks > 1 才生效；1 = 一次结算，绝大多数招式走这条）
func _skill_tick_repeats(skill_id: String, form: Dictionary, dir: Vector2) -> void:
	# 封阵 / 火灾 / 雷池已有专属结算并自己排跳数；这里再跑一遍会变成 3 次施放
	if skill_id in ["skill_array_seal", "skill_calamity_fire_field",
			"skill_calamity_thunder_pool"]:
		return
	var times := int(form.get("player_ticks", 1))
	if times <= 1:
		return
	var gap := maxf(float(form.get("player_tick_interval", 0.45)), 0.0)
	for _t in range(1, times):
		if gap > 0.0:
			await get_tree().create_timer(gap, true, false, true).timeout
		if not is_instance_valid(self) or is_dead:
			return
		_spawn_skill_visual(form, dir, skill_id)
		_apply_skill_hit(skill_id, form, dir)


## 连续突进斩的后续段（招式表 dash_times，1 = 没有后续段）
##
## 每一段 = 短停顿 → 按方向前冲 → 到点斩击，与第一段完全同构（同距离、同伤害系数）。
## **第二段方向**（用户 2026-10-23 定）：
##   读玩家当前移动输入 —— 想拐哪边就拐哪边；**没按方向键就沿用上一段**。
##   ⚠ 不能重新瞄 BOSS：玩家侧的方向选择权交给玩家自己，这样连斩可以主动拐弯绕背。
func _skill_dash_followups(skill_id: String, form: Dictionary, first_dir: Vector2) -> void:
	var times := int(form.get("dash_times", 1))
	if times <= 1:
		return
	var move_forward := float(form.get("move_forward", 0.0))
	var gap := maxf(float(form.get("dash_gap", 0.0)), 0.0)
	var windup := float(form.get("windup", 0.0))
	var dir := first_dir
	for i in range(1, times):
		if gap > 0.0:
			await get_tree().create_timer(gap, true, false, true).timeout
		if not is_instance_valid(self) or is_dead:
			return
		var move_dir := _get_move_dir()
		if move_dir.length_squared() > 0.0001:
			dir = move_dir.normalized()
		attack_dir = dir
		# 后续段也要跟着转：第二段可以由输入改向，人物必须转到新方向
		_lock_skill_facing(dir, windup)
		if move_forward > 0.0:
			_start_skill_dash(dir, move_forward, windup)
		_spawn_skill_visual(form, dir, skill_id)
		if windup > 0.0:
			await get_tree().create_timer(windup, true, false, true).timeout
			if not is_instance_valid(self) or is_dead:
				return
		_apply_skill_hit(skill_id, form, dir)


## 单个物理帧的时长（秒）—— 用来把「多补一帧」换算成时间
func _physics_frame_time() -> float:
	var hz := float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))
	return 1.0 / maxf(hz, 1.0)


## 施法朝向锁定：立刻把人物翻到技能方向，并在这段时间内拒绝「按移动输入翻面」。
## hold = 前摇时长；+0.15 是出手判定的余量，避免前摇刚结束就被输入翻回去。
## ⚠ 只翻转水平镜像（素材是侧向作画），纯垂直方向不翻 —— 与普攻的约定一致。
func _lock_skill_facing(dir: Vector2, hold: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	if absf(dir.x) > 0.1:
		anim.scale.x = 1.0 if dir.x > 0.0 else -1.0
	# 御剑也跟着转：它只在有移动输入时才更新朝向，施法时站着不动就会保持旧方向
	if weapon != null:
		weapon.facing_dir = dir.normalized()
	_skill_face_lock = maxf(_skill_face_lock, hold + 0.15)


## 技能前冲：施法时朝技能方向位移一段（招式表 move_forward 字段）
##
## distance 位移距离（像素）；windup 该招的前摇时长。
## 速度按「距离 / 前摇」算，所以前冲恰好在前摇时间内跑完 ——
## 前摇结束那一刻正好是斩击判定点，突进感与命中点对得上。
## ⚠ 时长多补一帧：计时器归零的那一帧不会再走位移，不多补就会少走一步
##   （实测 90px 只走得到 81px，补上后就准了）。
func _start_skill_dash(dir: Vector2, distance: float, windup: float) -> void:
	if distance <= 0.0:
		return
	var dur := maxf(windup, 0.06) + _physics_frame_time()
	_skill_dash_origin = global_position
	_skill_dash_dir = dir.normalized() if dir.length_squared() > 0.0001 else attack_dir
	_skill_dash_speed = distance / dur
	_skill_dash_timer = dur


## 朝向：优先瞄准最近的 BOSS（限技能射程），否则沿用当前攻击朝向
## 场上最近的 BOSS 节点（软锁定 / 万剑归宗追踪共用）；超出 max_dist 返回 null
func _nearest_boss(max_dist: float = 640.0) -> Node2D:
	var nearest: Node2D = null
	var best := max_dist
	for b in get_tree().get_nodes_in_group("boss"):
		# ⚠ 死单位不参与索敌 / 结算：试炼里 BOSS 尸体不销毁、仍在 "boss" 组
		if BossBase.is_unit_dead(b):
			continue
		if not is_instance_valid(b) or not b is Node2D:
			continue
		var d := global_position.distance_to((b as Node2D).global_position)
		if d < best:
			best = d
			nearest = b as Node2D
	return nearest


func _skill_aim_dir() -> Vector2:
	var nearest := _nearest_boss()
	if nearest != null:
		var v: Vector2 = _boss_aim_point(nearest) - global_position
		if v.length_squared() > 0.0001:
			return v.normalized()
	return attack_dir


## 自瞄点：取受击球按半径加权的中心，而不是脚底原点。
## 直线/狭窄功法近距离朝脚底打会从高个目标身下穿过（训练木桩最明显）。
func _boss_aim_point(boss: Node2D) -> Vector2:
	var point := boss.global_position
	if not boss.has_method("hit_spheres"):
		return point
	var sum := Vector2.ZERO
	var weight := 0.0
	for sp in boss.call("hit_spheres"):
		var sv: Vector3 = sp
		if sv.z <= 0.0:
			continue
		sum += Vector2(sv.x, sv.y) * sv.z
		weight += sv.z
	if weight <= 0.0:
		return point
	return point + sum / weight


## 带位移的招式才吃玩家移动输入；普通远程/范围技仍自动朝 BOSS
func _skill_cast_dir(form: Dictionary) -> Vector2:
	if _form_has_displacement(form):
		var wanted := _get_move_dir()
		if wanted.length_squared() > 0.0001:
			return wanted.normalized()
	return _skill_aim_dir()


func _form_has_displacement(form: Dictionary) -> bool:
	if float(form.get("move_forward", 0.0)) > 0.0:
		return true
	if form.get("teleport_step", false) == true:
		return true
	if float(form.get("teleport_dist", 0.0)) > 0.0:
		return true
	return float(form.get("dash_speed", 0.0)) > 0.0 \
		and float(form.get("dash_time", 0.0)) > 0.0


## 播放招式表现（玩家侧：SkillFx 分族演出；未登记的招式仍回退 ArtDB.EFFECTS）
func _spawn_skill_visual(form: Dictionary, dir: Vector2, skill_id: String = "") -> void:
	# 一剑开天：四段表现（蓄力 → 劈落 → 撞击 → 地面劈痕），由 SwordHeavenFx 驱动
	# 劈痕尺寸直接取判定形状，保证「看到的区域 = 打得到的区域」
	if bool(form.get("fx_heaven", false)):
		SwordHeavenFx.play(self, form, dir, skill_id)
		return
	# 阵旗四式（布旗 / 引阵 / 封阵 / 解阵）由 ArrayFx 在**命中帧**按真实几何画，
	# 不走 SkillFx 的通用扇形/直线
	if skill_id in ["skill_array_plant", "skill_array_line", "skill_array_pull", "skill_array_seal",
			"skill_array_burst", "skill_array_sweep", "skill_array_step", "skill_array_pile"]:
		return
	# 气君八式：同样在命中帧由 QiFx 按真实几何画（气环 / 气浪 / 气柱）
	if skill_id in ["skill_qi_gather", "skill_qi_wave", "skill_qi_spin", "skill_qi_lock",
			"skill_qi_ward", "skill_qi_step", "skill_qi_burst", "skill_qi_breath"]:
		return
	# 判词八式：在命中帧由 SkillFx 的 thunder motif 按真实落点画
	if skill_id in ["skill_thunder_verdict", "skill_thunder_execute", "skill_thunder_drum",
			"skill_thunder_lock", "skill_thunder_step", "skill_thunder_gather",
			"skill_thunder_nine", "skill_thunder_prison"]:
		return
	# 逐日八式：全部由 _sun_handle_cast 在命中帧按真实落点画
	if skill_id.begins_with("skill_sun_"):
		return
	# 三灾八式：由 _calamity_handle_cast 按命中帧 / 延迟落点画
	if skill_id.begins_with("skill_calamity_"):
		return
	# 投影八式：全部由 _shadow_* 自己按**当前影长**画 —— 通用层拿不到随跑位变化的射程
	if skill_id.begins_with("skill_shadow_"):
		return
	# 折影八式：由 _fold_* 自己按「有没有痕、痕在哪一侧」结算，通用层拿不到这些
	if skill_id.begins_with("skill_fold_"):
		return
	# 有技能表现数据 → 走新的分族演出（不再画扇形/方块占位）
	if skill_id != "" and not ArtDB.get_skill_fx(skill_id).is_empty():
		SkillFx.play(self, skill_id, form, dir)
		return
	# 回退 ArtDB.EFFECTS：尺寸跟随形状 —— 与镜像复读共用同一份实现（SkillFx）
	SkillFx.play_form_fallback(self, _body_center(), form, dir)


## 结算命中：按招式形态决定判定方式，伤害统一走 CharacterData.calc_skill_damage
func _apply_skill_hit(skill_id: String, form: Dictionary, dir: Vector2, coeff_mult: float = 1.0) -> void:
	# 镜身八式：镜花 / 碎镜 / 换镜 / 镜返 / 镜湖 / 万镜走自己的结算
	if _mirror_handle_cast(skill_id, dir):
		return
	# 投影八式：影技按**影身走廊**结算（射程 = 当前影长），明灭 / 分影 / 长夜是状态招
	if _shadow_handle_cast(skill_id, dir):
		return
	# 折影八式：每一击同时判定本体与对位落点（镜像那一面打折）
	if _fold_handle_cast(skill_id, dir):
		return
	# 三灾八式：转轮 / 破灾 / 锁灾 / 万劫归一走自己的结算
	if _calamity_handle_cast(skill_id, dir):
		return
	# 逐日八式：夺火 / 投日 / 日蚀 / 日轮 / 天火坠走自己的结算
	if _sun_handle_cast(skill_id, dir):
		return
	# 判词八式：立律 / 定刑 / 雷鼓 / 锁雷 / 雷遁 / 聚雷 / 九霄 / 雷牢
	if _thunder_handle_cast(skill_id, dir):
		return
	# 气君八式：气环 → 化劲 / 冲气 / 气爆走自己的结算
	if _qi_handle_cast(skill_id, dir):
		return
	# 阵旗（定阵先生）：布旗 / 引阵 / 解阵 走自己的结算，不进通用伤害路径
	if _array_handle_cast(skill_id, dir):
		return
	# 两仪转：自身状态技，不结算伤害（翻仪态 / 清阴蚀 / 蓄逆式）
	if skill_id == "skill_yinyang_flip":
		_cast_yinyang_flip()
		return
	# 两仪·双鱼：两枚弹各走一段系数、各是一种颜色，不能合并成一次伤害结算
	if skill_id == "skill_yinyang_fish":
		_cast_yinyang_fish(form, dir, coeff_mult)
		return
	var shape := String(form.get("hit_shape", MoveDB.SHAPE_FAN))
	# 伤害类型与五行元素：交给受击方扣抗性（物抗 / 法抗+五行抗性）
	var kind := "elemental" if SkillDB.get_spell_coeff(skill_id) > SkillDB.get_phys_coeff(skill_id) else "physical"
	var elem := SkillDB.get_damage_element(skill_id)
	# 是否「近战物理」：非投射物 + 物理系 —— 决定能否吃弹刀增伤 buff 并在命中后消费它
	var is_melee_phys := shape != MoveDB.SHAPE_PROJECTILE and kind == "physical"
	# 太极崩：势在 _cast_skill 里已经结算并清空；这里按释放瞬间的层数现算系数
	var is_collapse := skill_id == "skill_yinyang_collapse"
	var dmg := 0.0
	if is_collapse:
		dmg = _calc_collapse_damage(_collapse_stacks) * coeff_mult
	else:
		# ⚠ 必须在算伤害**之前**决定带不带 buff（次数型 buff 命中后立即消费）
		dmg = CharacterData.calc_skill_damage(skill_id, true, is_melee_phys and has_buff("parry_power")) * coeff_mult
	# 明灭（执烛玩家侧）：影长归零的这段时间，物理功法伤害上涨
	dmg *= _shadow_dim_mult(kind)
	# 量折（叠纸玩家侧被动）：穿缝后的下一次攻击加重
	dmg *= _fold_cross_mult()

	# 刀痕联动（可选玩法）：先结算刀痕，再走命中
	_apply_scar_effect(form, dir)

	# 守阵（玩家侧）：站在自己任意一段阵线上 → 伤害 +10%
	if _array_onsite():
		dmg *= 1.10

	# 矩形长条（一剑开天·满层）：前方 长×宽 的正交投影判定
	if shape == MoveDB.SHAPE_RECT:
		if _damage_bosses_in_rect(dir,
				float(form.get("range", 1000.0)), float(form.get("width", 160.0)),
				dmg, kind, elem, skill_id):
			GameState.trigger_hit_stop()
			GameState.play_sfx("attack_hit")
		return

	# 投射物：交给投射物自己飞过去结算
	if shape == MoveDB.SHAPE_PROJECTILE:
		_spawn_skill_projectiles(skill_id, form, dir, dmg)
		return

	var hit_any := _damage_bosses_in_shape(
		dir,
		float(form.get("range", 60.0)),
		deg_to_rad(float(form.get("angle", 60.0)) * 0.5),
		dmg, kind, elem,
		shape == MoveDB.SHAPE_CIRCLE,
		skill_id
	)
	if is_collapse:
		if hit_any:
			_rogue_collapse_extras()
		if hit_any and _collapse_stacks >= _yinyang_max():
			_apply_collapse_finish()
		_collapse_stacks = 0
	if not hit_any:
		return
	GameState.trigger_hit_stop()
	GameState.play_sfx("attack_hit")
	# 弹刀增伤 buff：只有近战物理功法命中才消费（法术 / 投射物不消费）
	if is_melee_phys:
		_consume_parry_damage_buff()


## 刀痕联动 —— 只有带 scar_effect 的招式才会触发
## 刀痕不是基础系统：没有刀痕类招式时，这里什么都不会发生，也不会创建管理器
func _apply_scar_effect(form: Dictionary, dir: Vector2) -> void:
	var effect := String(form.get("scar_effect", ""))
	if effect == "":
		return
	match effect:
		"create":
			# 首次留痕才按需创建（ScarField.ensure）
			var field := ScarField.ensure()
			if field == null:
				return
			var offset := float(form.get("scar_offset", 90.0))
			# 刀痕强度跟留痕技能的攻击类型走：物理技能 → 物攻；法术技能 → 法强 × 法技增伤
			var phys := float(form.get("phys_coeff", 0.0))
			var spell := float(form.get("spell_coeff", 0.0))
			var scar_kind := "elemental" if spell > phys else "physical"
			var power := CharacterData.spell_attack() * CharacterData.spell_skill_damage_mult() \
				if scar_kind == "elemental" else CharacterData.physical_attack()
			# 重痕：一次留两道，第二道沿刀锋垂直方向错开（不是往后放，后方没有敌人）
			# ⚠ 数量走 RogueRun，主模式恒为 1
			var extra := 1 if (RogueRun.active and RogueRun.has_flag("scar_extra")) else 0
			var fwd := dir.normalized()
			var side_axis := Vector2(-fwd.y, fwd.x)
			for i in range(1 + extra):
				var pos := global_position + fwd * offset + side_axis * 72.0 * float(i)
				field.spawn_scar(pos, BladeScar.SIDE_PLAYER, power,
					SCAR_PLAYER_DAMAGE_COEFF, self, scar_kind, self)
		"ignite_path":
			var field2 := ScarField.get_active()
			if field2 == null:
				return
			var reach := float(form.get("range", 400.0))
			field2.ignite_in_path(global_position, global_position + dir.normalized() * reach,
				int(form.get("scar_ignite_max", 1)), BladeScar.SIDE_PLAYER, self)
		"ignite_area":
			var field3 := ScarField.get_active()
			if field3 == null:
				return
			field3.ignite_in_radius(global_position, float(form.get("range", 180.0)),
				int(form.get("scar_ignite_max", 2)), BladeScar.SIDE_PLAYER, self)


## 通用减速接口（被 BOSS 招式命中时调用）
func apply_slow(duration: float, ratio: float) -> void:
	_slow_ratio = maxf(_slow_ratio, clampf(ratio, 0.0, 0.9))
	_slow_timer = maxf(_slow_timer, duration)


# ===================== 负面状态 debuff =====================

## 施加一个 debuff（重复施加不叠加，取剩余时间较长的那个）
## quiet = true 时不自带飘字（调用方自己有更详细的提示，例如「力竭！精力暂时无法恢复」）
## 返回值仅用于调试：是否是新挂上的（false = 只是刷新了时长）
func apply_debuff(id: String, duration: float, quiet := false) -> bool:
	if id == "" or duration <= 0.0:
		return false
	# 同一击被闪避 / 弹反 / 无敌帧吞掉：伤害没有落地，附带 debuff 也不挂
	if _hit_negated_timer > 0.0:
		return false
	if DebuffDB.get_debuff(id).is_empty():
		push_warning("未登记的 debuff：" + id)
		return false
	var fresh := not debuffs.has(id)
	debuffs[id] = maxf(float(debuffs.get(id, 0.0)), duration)
	# 眩晕这类硬控：被打中就当帧断掉正在进行的守势 / 翻滚 / 弹刀窗口，
	# 否则会出现「眩晕中还能把倒悬的反击按出来」的怪状
	if bool(DebuffDB.get_debuff(id).get("no_action", false)):
		if _counter_charging:
			_counter_charging = false
			_finish_counter_ward()
		is_dodging = false
		is_parrying = false
		auto_parry_timer = 0.0
	# 眩晕：头顶挂星星（重复施加只刷新，不叠第二套）
	if id == "stun" and not is_dead:
		StunFx.attach(self, duration)
	# 断念：正在引导的吐纳 / 聚雷会被打断（正在起手的招式同理）
	if id == "duannian":
		_cancel_qi_channel(true)
		_cancel_thunder_channel(true)
	# 飘字提示：玩家得知道自己中了什么（HUD 在技能栏上方另有常驻标签）
	if not quiet:
		_show_float_text("%s！" % DebuffDB.display_name(id), DebuffDB.color(id))
	return fresh


## 是否正带着某个 debuff
func has_debuff(id: String) -> bool:
	return float(debuffs.get(id, 0.0)) > 0.0


## 主动清掉一个 debuff（阵伤层数切换、离开攻旗范围时用）
func clear_debuff(id: String) -> void:
	debuffs.erase(id)


## 受到伤害乘区（阵伤这类"易伤"debuff）：多个取最大，不连乘
func debuff_damage_taken_mult() -> float:
	var m := 1.0
	for id in debuffs.keys():
		m = maxf(m, float(DebuffDB.get_debuff(String(id)).get("damage_taken_mult", 1.0)))
	return m


## 当前移动速度乘区（多个 debuff 取**最小**的那个，不做连乘 —— 免得叠两个就动不了）
func debuff_move_mult() -> float:
	var m := 1.0
	for id in debuffs.keys():
		m = minf(m, float(DebuffDB.get_debuff(String(id)).get("move_mult", 1.0)))
	return m


## 当前身上最高的穿抗削减（暗「蚀」）—— DamageCalc 在进减免曲线之前读这个。
func debuff_resist_shred() -> float:
	var v := 0.0
	for id in debuffs.keys():
		v = maxf(v, float(DebuffDB.get_debuff(String(id)).get("resist_shred", 0.0)))
	return clampf(v, 0.0, 0.9)


## 当前受到的治疗乘区（蚀 = 0.10，即减疗 90%）。
## 所有回血入口都必须过 restore_health()，否则这条就会漏 —— 吐纳那口原本绕过入口直接写 hp，
## 已经改走 restore_health()；新增回复来源时同样别自己写 hp += 。
func debuff_heal_mult() -> float:
	var v := 1.0
	for id in debuffs.keys():
		v = minf(v, float(DebuffDB.get_debuff(String(id)).get("heal_mult", 1.0)))
	return clampf(v, 0.0, 1.0)


## 暗属性命中的通用结算：被暗打中 → 尝试挂「蚀」（穿抗 + 减疗）。
## 读自己的暗抗来缩短持续，所以 resist_dark 一旦有装备/符箓来源就立刻有用。
func try_dark_erosion() -> void:
	if dark_erosion_lock > 0.0 or is_dead:
		return
	var dur := AttributeDB.dark_erosion_time(element_resist(AttributeDB.DARK))
	if dur <= 0.0:
		return
	dark_erosion_lock = AttributeDB.DARK_EROSION_REFRESH_CD
	apply_debuff(AttributeDB.DARK_EROSION_ID, dur)


## 是否被禁止回复灵力（滞气）
func debuff_blocks_mana_regen() -> bool:
	for id in debuffs.keys():
		if bool(DebuffDB.get_debuff(String(id)).get("no_mana_regen", false)):
			return true
	return false


## 是否被禁止回复精力（力竭 / 禁步）
func debuff_blocks_stamina_regen() -> bool:
	for id in debuffs.keys():
		if bool(DebuffDB.get_debuff(String(id)).get("no_stamina_regen", false)):
			return true
	return false


## 是否被禁止闪避
func is_dodge_blocked() -> bool:
	for id in debuffs.keys():
		if bool(DebuffDB.get_debuff(String(id)).get("no_dodge", false)):
			return true
	return false


## 是否被完全锁住行动（眩晕这类 no_action）：移动由 move_mult=0 锁死，
## 攻击 / 闪避 / 弹反 / 功法由各处入口读这个判定吞掉 —— 加新硬控只改 DebuffDB
func is_action_blocked() -> bool:
	for id in debuffs.keys():
		if bool(DebuffDB.get_debuff(String(id)).get("no_action", false)):
			return true
	return false


## 每个物理帧推进 debuff 计时，到点自动清除
func _tick_debuffs(delta: float) -> void:
	if dark_erosion_lock > 0.0:
		dark_erosion_lock = maxf(0.0, dark_erosion_lock - delta)
	if debuffs.is_empty():
		_debuff_dot_timers.clear()
		# 空表也要刷一次：否则最后一条力竭到期后，简上的「竭」印会一直挂着
		_refresh_exhaust_seal()
		return
	for id in debuffs.keys():
		var dinfo := DebuffDB.get_debuff(String(id))
		var dot := float(dinfo.get("dot_damage", 0.0))
		if dot > 0.0:
			var interval := maxf(0.05, float(dinfo.get("dot_interval", 1.0)))
			var t := float(_debuff_dot_timers.get(id, interval)) - delta
			while t <= 0.0:
				t += interval
				if is_dead:
					break
				took_damage_this_battle = true
				# 续命灯：持续伤害致死同样改判，避免「灯亮着却被点燃烧死」
				var dot_tick := dot
				if hp - dot_tick <= 0.0 and _lamp_left > 0.0:
					dot_tick = maxf(0.0, hp - 1.0)
					_trigger_lamp_save()
				hp = maxf(0.0, hp - dot_tick)
				health_changed.emit(hp, max_hp)
				_update_health_bar()
				DamageNumber.spawn(get_parent(), global_position + Vector2(0.0, -34.0),
					dot_tick, DamageNumber.Kind.SPELL)
				if hp <= 0.0:
					_die()
					break
			_debuff_dot_timers[id] = t
		else:
			_debuff_dot_timers.erase(id)
		var left := float(debuffs[id]) - delta
		if left <= 0.0:
			debuffs.erase(id)
			_debuff_dot_timers.erase(id)
		else:
			debuffs[id] = left
	# 力竭倒计时现在只活在简上的「竭」印里，跟着 debuff 计时一起走
	_refresh_exhaust_seal()


# ===================== 增益状态 buff =====================

## 施加一个 buff
##   duration = 时间型的持续秒数；count = 次数型的次数
## 时间型重复施加取**较长**的剩余时间；次数型取**较大**次数（保持「弹刀增伤不累计」的口径，
## 以后真要能叠层再把它改成相加即可）。
func apply_buff(id: String, duration := 0.0, count := 1) -> void:
	if id == "":
		return
	if BuffDB.get_buff(id).is_empty():
		push_warning("未登记的 buff：" + id)
		return
	var e: Dictionary = buffs.get(id, {"left": 0.0, "count": 0})
	if BuffDB.is_count_based(id):
		e["count"] = maxi(int(e.get("count", 0)), count)
	else:
		e["left"] = maxf(float(e.get("left", 0.0)), duration)
	buffs[id] = e


## 是否正带着某个 buff（次数型看剩余次数，时间型看剩余秒）
func has_buff(id: String) -> bool:
	if not buffs.has(id):
		return false
	var e: Dictionary = buffs[id]
	if BuffDB.is_count_based(id):
		return int(e.get("count", 0)) > 0
	return float(e.get("left", 0.0)) > 0.0


## 直接移除一个 buff（时间型被**提前用掉**时用，例如追击窗口用完）
func remove_buff(id: String) -> void:
	buffs.erase(id)


## 消费次数型 buff（例如弹刀增伤命中后扣 1 次），扣到 0 就移除
func consume_buff(id: String, n := 1) -> void:
	if not buffs.has(id):
		return
	var e: Dictionary = buffs[id]
	e["count"] = maxi(0, int(e.get("count", 0)) - n)
	if int(e["count"]) <= 0:
		buffs.erase(id)


## 每个物理帧推进时间型 buff；次数型不按时间消失
func _tick_buffs(delta: float) -> void:
	# 顺天到期：把临时属性修正一起撤掉（攻击 / 移速百分比）
	if not has_buff("shuntian") and CharacterData.attribute_mods.has("shuntian"):
		CharacterData.clear_attribute_mod("shuntian")
	if buffs.is_empty():
		return
	for id in buffs.keys():
		if BuffDB.is_count_based(String(id)):
			continue
		var e: Dictionary = buffs[id]
		var left := float(e.get("left", 0.0)) - delta
		if left <= 0.0:
			buffs.erase(id)
		else:
			e["left"] = left


## 投射物场景缓存：万剑归宗一次要实例化十几把剑，
## 每把都走一次 load() 太浪费（load 虽有缓存，但每次都要查一遍资源路径）
static var _proj_scene_cache: PackedScene = null

## 取投射物场景（首次加载后一直复用）
func _projectile_scene() -> PackedScene:
	if _proj_scene_cache == null:
		_proj_scene_cache = load(PLAYER_PROJECTILE_SCENE) as PackedScene
	return _proj_scene_cache


## 投射物型招式：按 count / spread / interval 生成玩家投射物
func _spawn_skill_projectiles(skill_id: String, form: Dictionary, dir: Vector2, dmg: float) -> void:
	var packed := _projectile_scene()
	if packed == null:
		push_warning("玩家投射物场景缺失：" + PLAYER_PROJECTILE_SCENE)
		return
	# 万剑归宗：镜像 BOSS 侧弧线追踪（身侧斜飞 → 逐把错开 → 拐向目标），不走直线散射
	var ics: Dictionary = form.get("intent_count_scale", {})
	if not ics.is_empty():
		_spawn_myriad_swords(form, dir, dmg)
		return
	var count := maxi(1, int(form.get("count", 1)))
	var spread := deg_to_rad(float(form.get("spread", 0.0)))
	var base_angle := dir.angle()
	var sfx := ArtDB.get_skill_fx(skill_id)
	for i in range(count):
		var angle := base_angle
		if count > 1:
			var t := float(i) / float(count - 1)
			angle = base_angle - spread * 0.5 + spread * t
		var proj: Node2D = packed.instantiate()
		proj.skill_id = skill_id
		proj.source = self
		proj.damage = dmg
		proj.damage_kind = "elemental" if SkillDB.get_spell_coeff(skill_id) > SkillDB.get_phys_coeff(skill_id) else "physical"
		proj.element = SkillDB.get_damage_element(skill_id)
		proj.speed = float(form.get("speed", 600.0))
		proj.max_distance = float(form.get("range", 600.0))
		proj.direction = Vector2.RIGHT.rotated(angle)
		var pv := String(sfx.get("projectile_visual", ""))
		if pv != "":
			proj.visual_id = pv
		proj.align_visual = bool(sfx.get("projectile_align", false))
		# 入树前设 global_position 不生效，用 position 并挂到玩家父节点
		proj.position = global_position
		get_parent().add_child(proj)
		# 需要沿飞行方向对齐的贴图交给 SkinVisual 自己转（父节点保持 0°，避免双重旋转）
		if not proj.align_visual:
			proj.rotation = angle


## 万剑归宗：逐把从身侧斜放，弧线追踪最近的 BOSS
## 与 BOSS 侧（domain_boss_01_c._launch_one_sword）同一套手感：
##   左右交替各偏 65° 出发 → 每把错开 interval 秒 → 放出后以 turn_speed 拐向目标
func _spawn_myriad_swords(form: Dictionary, dir: Vector2, dmg: float) -> void:
	var packed := _projectile_scene()
	if packed == null:
		return
	# count 已在 _cast_skill 按剑意层数算好（base + 层数×per）
	var count := maxi(1, int(form.get("count", MYRIAD_BASE_COUNT)))
	var speed := float(form.get("speed", 420.0))
	var interval := float(form.get("interval", MYRIAD_INTERVAL))
	var max_distance := float(form.get("range", 620.0))
	var kind := "elemental" if SkillDB.get_spell_coeff(SKILL_SWORD_MYRIAD) > 0.0 else "physical"
	var target := _nearest_boss()
	for i in range(count):
		var side := -1.0 if (i % 2 == 0) else 1.0
		var launch_dir := dir.rotated(side * deg_to_rad(MYRIAD_SIDE_ANGLE))
		var delay := float(i) * interval
		if delay <= 0.0:
			_launch_myriad_sword(packed, launch_dir, side, speed, dmg, kind, max_distance, target)
		else:
			# 逐把错开放出；玩家已死/离场则不再放（与 BOSS 侧 _schedule_sword 同保险）
			get_tree().create_timer(delay).timeout.connect(func() -> void:
				if is_inside_tree() and not is_dead:
					_launch_myriad_sword(packed, launch_dir, side, speed, dmg, kind, max_distance, target)
			)
	# 出手时一团剑雾反馈（走 ArtDB.EFFECTS）
	FxPlayer.spawn(self, "fx_sword_myriad", {
		"position": _body_center(),
		"lifetime": 0.5,
	})


## 放一把万剑归宗的飞剑（delay <= 0 的立即放；延迟放的由计时器回调进来）
func _launch_myriad_sword(packed: PackedScene, launch_dir: Vector2, side: float,
		speed: float, dmg: float, kind: String, max_distance: float, target: Node2D) -> void:
	var proj: Node2D = packed.instantiate()
	proj.skill_id = SKILL_SWORD_MYRIAD
	proj.source = self
	proj.damage = dmg
	proj.damage_kind = kind
	proj.element = ""
	proj.speed = speed
	proj.max_distance = max_distance
	proj.direction = launch_dir
	# 弧线追踪三件套（字段在 player_projectile.gd 声明；与 boss_projectile.gd 同名同义）
	proj.turn_speed_deg = MYRIAD_TURN_SPEED
	proj.homing_target = target
	proj.align_visual = true
	proj.launch_side = side
	# 飞剑形象与 BOSS 侧共用同一条美术条目（换图只改 ArtDB 的 boss_sword_projectile）
	proj.visual_id = "boss_sword_projectile"
	# 入树前用 position（相对玩家父节点）；从身侧偏出、略上移，像从鞘中斜飞而出
	proj.position = global_position + launch_dir * 26.0 + Vector2(0.0, -30.0)
	get_parent().add_child(proj)


## 受击表现：短暂变红 + 闪烁，持续整个无敌帧
# ===== 十二、通用工具：闪烁 / 朝向 / 重开 =====
func _play_hit_flash() -> void:
	_flash_color(Color(1.0, 0.25, 0.25), INVINCIBLE_TIME)


## 短促闪色（0.12 秒）：起手反馈用，比如弹刀按键的蓝色一闪
func _flash(color: Color) -> void:
	_flash_color(color, 0.12)


## 通用颜色闪烁：先置为指定颜色，闪烁持续时长后恢复白色
func _flash_color(color: Color, duration: float) -> void:
	if not is_instance_valid(anim):
		return
	_flash_token += 1
	var token := _flash_token
	anim.modulate = color
	await get_tree().create_timer(duration).timeout
	if is_instance_valid(anim) and token == _flash_token:
		anim.modulate = Color.WHITE


## 死亡：停止移动、广播死亡信号，由战斗场景决定后续（结算 / 重开）
func _die() -> void:
	_reckoning_reset()
	_stop_blade_form()
	is_dead = true
	velocity = Vector2.ZERO
	_clear_sun_crown()
	sun_stacks = 0
	_reset_sun_nova()
	CharacterData.clear_attribute_mod("calamity_element")
	calamity_element = ""
	calamity_momentum = 0
	# 死亡时把演出镜头立刻收回，别把 zoom 停在拉远值上
	_cancel_cinematic_zoom()
	cancel_talisman_cast()
	_stop_heal_treasure("", false)
	_stop_haste_treasure()
	_stop_lamp_treasure()
	_stop_thorns_treasure()
	if is_instance_valid(_stake_field):
		_stake_field.queue_free()
	_stake_field = null
	_stake_id = ""
	_stake_left = 0.0
	if skin != null:
		skin.cancel_one_shot()
	player_died.emit()
	GameState.player_died.emit()


## 更新朝向：只在「没在攻击、没在弹刀、没在闪避」时按移动方向翻转形象
## 翻转只改 Visual 的 scale.x，替换美术后依然有效
func _update_visual(move_dir: Vector2) -> void:
	# 行走动画：只有真的在移动才播；静止时停在 idle_frame，避免原地踏步
	if skin != null:
		skin.set_moving(move_dir.length_squared() > 0.0)
		# 朝向驱动动画：有 walk_down / walk_up / walk_side 时自动切换（没有就保持原行为）
		# 静止时传零向量，set_facing 会忽略，保留上一次朝向
		skin.set_facing(move_dir)
		# 御剑武器跟着朝向走（静止时保留上次朝向，所以只在有输入时更新）
		if weapon != null and move_dir.length_squared() > 0.0:
			weapon.facing_dir = move_dir.normalized()
		# 换装备后切换武器外观（每帧比对 id，开销可忽略；没有装备变化信号可用）
		_sync_weapon_visual()
	# 面向（阶段1用色块朝向表示）
	# ⚠ 施法前摇 / 前冲期间由 _skill_face_lock 拦住：技能方向是软锁定 BOSS 的，
	#   若这时按住反方向的键，人物会一边前冲一边背对目标
	if not is_attacking and not is_parrying and _skill_face_lock <= 0.0:
		if move_dir.length_squared() > 0.0 and not is_dodging:
			if absf(move_dir.x) > 0.1:
				anim.scale.x = 1.0 if move_dir.x > 0 else -1.0


## 战斗内重开：把所有状态、资源、计时器恢复到入场状态
## ⚠ 新增状态字段时记得在这里一起清掉，否则重开后会残留
func reset_player() -> void:
	_reckoning_reset()
	_stop_blade_form()
	hp = max_hp
	took_damage_this_battle = false
	stamina = max_stamina
	stamina_regen_timer = 0.0
	# 灵力与功法冷却一并重置：重开一局等同于满状态入场
	max_mana = CharacterData.max_mana()
	mana = max_mana
	skill_cooldowns.clear()
	_skill_key_down.clear()
	is_dead = false
	is_dodging = false
	is_attacking = false
	is_parrying = false
	# 主动法宝引导 + buff / debuff 一并清空：重开一局等同于满状态入场
	_stop_heal_treasure("", false)
	_stop_haste_treasure()
	_stop_taiji_guard()
	_stop_tri_ring()
	_stop_lamp_treasure()
	_stop_thorns_treasure()
	if is_instance_valid(_stake_field):
		_stake_field.queue_free()
	_stake_field = null
	_stake_id = ""
	_stake_left = 0.0
	_lamp_heal_left = 0.0
	_lamp_heal_rate = 0.0
	_treasure_bell_immune_left = 0.0
	qi_rings = 0
	_qi_ward_left = 0.0
	_qi_ward_stored = 0.0
	_qi_ring_contacts.clear()
	_cancel_qi_channel(false)
	_refresh_qi_hud()
	_refresh_qi_rings()
	lei_shi = 0
	_clear_player_law()
	_cancel_thunder_channel(false)
	_refresh_thunder_hud()
	_clear_array_flags()
	_array_zone_enemy_attack_mult = 1.0
	_refresh_array_zone_attack_mult()
	debuffs.erase("array_zone_weaken")
	_array_seal_guard_left = 0.0
	_array_seal_guard_pct = 0.0
	_array_pending_pos = Vector2.INF
	_array_pending_kind = -1
	_array_step_from = Vector2.INF
	buffs.clear()
	debuffs.clear()
	parry_followup_can_dash = false
	parry_stance_timer = 0.0
	# 剑意一并清零：重开一局等同于满状态入场
	sword_intent = 0
	_sync_sword_intent_skill_mult()
	is_finisher_attack = false
	attack_combo = 0
	# 技能前冲状态一并清零（死亡/重开时不能留着半段位移）
	_skill_dash_timer = 0.0
	_skill_dash_dir = Vector2.ZERO
	_skill_dash_speed = 0.0
	_skill_dash_origin = Vector2.INF
	_skill_face_lock = 0.0
	_cancel_cinematic_zoom()
	cancel_talisman_cast()
	is_teleporting = false
	if skin != null:
		skin.cancel_one_shot()
	velocity = Vector2.ZERO
	knockback_velocity = Vector2.ZERO
	health_changed.emit(hp, max_hp)
	_update_health_bar()
	_update_stamina_bar()
	_update_mana_bar()


# ===== 阵旗（定阵先生，2026-10-28）=====
## 学会任意一门带 array 标记的功法才解锁；第一战没有这些功法，不参与。
## 阵旗上限：基值在 RogueDB.CAP_BASE，肉鸽增益可 +N；主模式恒为 5
func _array_max_flags() -> int:
	return RogueRun.cap("array_max")
# ===== 气环（太虚气君，2026-10-28）=====
## 气环上限：基值在 RogueDB.CAP_BASE，肉鸽增益可 +N；主模式恒为 5
func _qi_max() -> int:
	return RogueRun.cap("qi_max")
var qi_rings: int = 0
var _qi_unlocked: bool = false
var _qi_ward_left: float = 0.0
var _qi_ward_stored: float = 0.0
var _qi_ward_reduce: float = 0.0
var _qi_ward_store: float = 0.0
var _qi_ward_cap: float = 0.0
var _qi_release_coeff: float = 0.0
var _qi_release_radius: float = 0.0
## 环身气（与 BOSS 同款）：气环绕体（玩家上限 5）；气环本体碰到敌人时造成一次伤害并回血
var _qi_ring_nodes: Array = []
## 每枚气环各自记录「当前接触中的敌人」：进入接触才结算一次，离开后才能再次命中
var _qi_ring_contacts: Array = []
## 吐纳引导：1.2 秒，期间受伤超过 8% 最大气血会被打断
var _qi_channel_left: float = 0.0
var _qi_channel_damage: float = 0.0
var _qi_channel_break: float = 0.08
var _qi_channel_fx: Node2D = null
const QI_RING_ORBIT := Vector2(76.0, 34.0)
## 气环贴图 256² × 0.34 缩放，外缘约 40px；取 36 更贴视觉，不虚胖
const QI_RING_HIT_RADIUS := 36.0
const QI_TOUCH_COEF := 0.30
## 气环接触伤害的 10% 回复自身气血
const QI_RING_HEAL_RATIO := 0.10
var array_flags: Array = []
var _array_unlocked: bool = false
var _array_flag_cd: Dictionary = {}
var _array_strikes: Array = []
## 布点前摇：落点 + 旗型在起手时定死（和 BOSS 的 _pending_plant_pos 同一口径）
var _array_pending_pos := Vector2.INF
var _array_pending_kind: int = -1
## 踏阵：起手位置（旗插在原地，人冲出去）
var _array_step_from := Vector2.INF
## 旗与旗之间的常驻阵线（每段一根，颜色取多数旗色）
var _array_line_visuals: Array = []
var _array_guard_aura: Sprite2D = null
## 封阵·四象（守牢）：期间受到的伤害 -70%，持续 10 秒；任一旗被破立即结束
var _array_seal_guard_left: float = 0.0
var _array_seal_guard_pct: float = 0.0
var _array_seal_guard_flags: Array = []
const ARRAY_LINE_TEX := "res://assets/effects/skills/array_line.png"
const ARRAY_SEAL_GUARD_PCT := 0.70
## 五旗被敌对破去一面 → 破阵反噬：眩晕 5 秒 + 15 秒内所有插旗类技能不可用
const ARRAY_RECOIL_SECONDS := 15.0
const ARRAY_RECOIL_STUN_SECONDS := 5.0
const ARRAY_PLANT_SKILLS := ["skill_array_plant", "skill_array_step", "skill_array_pile"]

# ===== 五旗阵（2026-10-29 用户定）=====
## 五面旗首尾相连成区域：使用者在内攻击 +30% / 防御 +30%（受伤 ×1/1.3），
## 区域内对手攻击 -10%，每秒落一次雷击（0.6×法攻，扣 10 法力，耗尽撤旗）。
const ARRAY_ZONE_ATTACK_BUFF := 1.30
const ARRAY_ZONE_DEFENSE_DIV := 1.30
const ARRAY_ZONE_ENEMY_ATTACK_MULT := 0.90
const ARRAY_ZONE_LIGHTNING_INTERVAL := 1.0
const ARRAY_ZONE_LIGHTNING_COEF := 0.6
const ARRAY_ZONE_MANA_COST := 10.0
var _array_zone_timer := 0.0
var _array_zone_complete := false
var _array_zone_self_attack_mult := 1.0
var _array_zone_enemy_attack_mult := 1.0
var _array_zone_defense_mult := 1.0
var _array_zone_fill: Polygon2D = null
var _array_line_barrier: ArrayLineBarrier = null
var _array_zone_affected_enemies: Array = []



func _refresh_array_unlock() -> void:
	_array_unlocked = false
	for sid in CharacterData.learned_skills:
		if bool(SkillDB.get_skill(String(sid)).get("array", false)):
			_array_unlocked = true
			break
	if not _array_unlocked:
		_clear_array_flags()


## 前摇起手：报招名 + 布点预告（与 BOSS 的 show_windup_line / 同色阵纹同节奏）
func _array_precast(skill_id: String, dir: Vector2) -> void:
	if not skill_id.begins_with("skill_array_"):
		return
	if not _array_unlocked:
		_refresh_array_unlock()
	if not _array_unlocked:
		return
	var form := SkillDB.get_skill_form(skill_id)
	var show_name := SkillDB.get_skill_name(skill_id)
	# 封阵的牢型由四面旗的多数色决定：攻牢才有法伤，困/守牢零伤害。
	# 旗色是自动补缺的，玩家很难在混战里数色 —— 起手就把这一下的牢型报出来。
	if skill_id == "skill_array_seal" and array_flags.size() >= 4:
		match _array_majority_kind():
			ArrayFlag.Kind.ATTACK:
				show_name += "（攻牢 · 法伤）"
			ArrayFlag.Kind.BIND:
				show_name += "（困牢 · 眩晕5秒）"
			ArrayFlag.Kind.GUARD:
				show_name += "（守牢 · 减伤10秒）"
	_show_skill_name(show_name, float(form.get("windup", 0.15)) + 0.2)
	_array_pending_pos = Vector2.INF
	_array_pending_kind = -1
	_array_step_from = Vector2.INF
	match skill_id:
		"skill_array_plant":
			# 玩家侧在**当前坐标**落旗（用户 2026-10-28 定）；预告也只铺在脚下。
			# ⚠ 不再按战场内缩钳制：玩家已被墙挡住，再钳一次会让贴边的旗落到 40~60px 外
			_array_pending_kind = _next_player_flag_kind()
			_array_pending_pos = global_position
			_array_plant_telegraph(_array_pending_pos, _array_pending_kind)
		"skill_array_step":
			_array_step_from = global_position
		"skill_array_pile":
			_array_pending_pos = _array_clamp_point(global_position + dir * 90.0)


## 布点预告：落点亮同色阵纹（和 BOSS 的 _show_plant_telegraph 同一张图）
func _array_plant_telegraph(pos: Vector2, kind: int) -> void:
	var spr := Sprite2D.new()
	spr.texture = load("res://assets/effects/skills/array_decal.png")
	spr.centered = true
	spr.scale = Vector2(0.18, 0.18)
	var c := Color(ArtDB.ARRAY_FLAG_KIND_COLORS.get(kind, Color.WHITE))
	spr.modulate = Color(c.r, c.g, c.b, 0.78)
	spr.z_index = 1
	get_parent().add_child(spr)
	spr.global_position = pos
	var tw := spr.create_tween()
	tw.tween_property(spr, "modulate:a", 0.18, 0.55)
	tw.tween_callback(spr.queue_free)


func _array_handle_cast(skill_id: String, dir: Vector2) -> bool:
	if not skill_id.begins_with("skill_array_"):
		return false
	if array_flags.is_empty() and not _array_unlocked:
		_refresh_array_unlock()   # 懒刷新：学会功法后第一次出手就能生效
	if not _array_unlocked:
		return false
	_prune_array_flags()
	match skill_id:
		"skill_array_plant":
			# 落旗点 = 命中帧的玩家当前坐标（前摇内走位也跟着人走）；贴墙时也必须落在脚下
			var p_pos := global_position
			var p_kind := _array_pending_kind if _array_pending_kind >= 0 else _next_player_flag_kind()
			_array_pending_pos = Vector2.INF
			_array_pending_kind = -1
			if _plant_array_flag(p_pos, p_kind) != null:
				ArrayFx.play_plant(get_parent(), p_pos, p_kind)
			else:
				_show_float_text("阵位已满（%d 面）" % _array_max_flags(), UIKit.C_FLOAT_WARN)
			return true
		"skill_array_line":
			# 引阵：全部旗段一起亮（5 面含首尾收口）；每段一根线，按多数色整段结算
			var segments: Array = []
			var line_kind := _array_majority_kind()
			if array_flags.size() >= 2:
				for seg in _array_segments():
					var a: Vector2 = (seg[0] as Node2D).global_position
					var b: Vector2 = (seg[1] as Node2D).global_position
					segments.append({"a": a, "b": b, "kind": line_kind})
					_array_line_effect(a, b, line_kind, 1.24, "skill_array_line")
			else:
				# 没旗兜底：朝瞄准方向拉一道直线（与 BOSS 无旗时同构）
				var line_end := global_position + dir * 460.0
				segments.append({"a": global_position, "b": line_end, "kind": ArrayFlag.Kind.ATTACK})
				_array_line_damage(global_position, line_end, 1.25)
			ArrayFx.play_line(get_parent(), segments)
			return true
		"skill_array_pull":
			var pull_flag := _array_pull_flag()
			if pull_flag == null:
				_show_float_text("无旗可卷", UIKit.C_FLOAT_WARN)
				return true
			var old_pos: Vector2 = pull_flag.global_position
			var new_pos := _array_clamp_point(global_position + dir.normalized() * 110.0)
			pull_flag.global_position = new_pos
			ArrayFx.play_pull(get_parent(), old_pos, new_pos, int(pull_flag.get("kind")))
			# 沿整根线按旗色结算（攻伤害 / 困锁步 / 守无伤），旗不消失
			_array_line_effect(old_pos, new_pos, int(pull_flag.get("kind")), 1.15,
				"skill_array_pull", "physical", "earth")
			# 肉鸽「收势」：收旗回精力（主模式 stat 恒 0）
			var pull_stam := RogueRun.stat("array_pull_stamina")
			if pull_stam > 0.0:
				stamina = minf(max_stamina, stamina + pull_stam)
				_update_stamina_bar()
			return true
		"skill_array_seal":
			# 封阵·四象：四面旗成阵，按多数旗色结牢，连打四跳；不撤旗
			if array_flags.size() < 4:
				_show_float_text("封阵需要四面旗（当前 %d）" % array_flags.size(), UIKit.C_FLOAT_WARN)
				return true
			var seal_center := _array_centroid()
			var seal_kind := _array_majority_kind()
			ArrayFx.play_seal(get_parent(), seal_center, 210.0, seal_kind, 4, 0.55)
			_array_start_seal(seal_kind, seal_center)
			return true
		"skill_array_sweep":
			ArrayFx.play_sweep(get_parent(), global_position, dir, 160.0, 150.0)
			return false
		"skill_array_step":
			# 踏阵：起手处留一面旗，人冲出去；落点伤害走通用结算
			var step_from := _array_step_from
			if step_from == Vector2.INF:
				step_from = global_position - dir * float(MoveDB.resolve_player("form_array_step").get("move_forward", 220.0))
			_array_step_from = Vector2.INF
			var step_kind := _next_player_flag_kind()
			if _plant_array_flag(step_from, step_kind) != null:
				ArrayFx.play_plant(get_parent(), step_from, step_kind)
			ArrayFx.play_step(get_parent(), step_from, global_position, step_kind)
			return false
		"skill_array_pile":
			# 垒旗：判定在自身（和 BOSS 同构），砸完在身前 90 处补一面旗
			var pile_pos := _array_pending_pos
			if pile_pos == Vector2.INF:
				pile_pos = _array_clamp_point(global_position + dir * 90.0)
			_array_pending_pos = Vector2.INF
			ArrayFx.play_pile(get_parent(), global_position, dir, 120.0)
			var pile_kind := _next_player_flag_kind()
			if _plant_array_flag(pile_pos, pile_kind) != null:
				ArrayFx.play_plant(get_parent(), pile_pos, pile_kind)
			return false
		"skill_array_burst":
			# 解阵：引爆全部旗——攻旗伤害 / 困旗锁步 / 守旗回血；引爆后全部消失
			if array_flags.is_empty():
				_show_float_text("无阵可解", UIKit.C_FLOAT_WARN)
				return true
			var fx_flags: Array = []
			for bf in array_flags:
				if is_instance_valid(bf):
					fx_flags.append({"pos": (bf as Node2D).global_position, "kind": int(bf.get("kind"))})
			ArrayFx.play_burst(get_parent(), fx_flags)
			var burst_dmg := CharacterData.calc_skill_damage("skill_array_burst", true, false)
			for bf in array_flags.duplicate():
				if not is_instance_valid(bf):
					continue
				var bp: Vector2 = (bf as Node2D).global_position
				match int(bf.get("kind")):
					ArrayFlag.Kind.ATTACK:
						for e in _array_enemy_units():
							if e.global_position.distance_to(bp) <= 140.0:
								_deal_direct_damage(e, burst_dmg, "elemental", "fire",
									"skill_array_burst")
					ArrayFlag.Kind.BIND:
						for e in _array_enemy_units():
							if e.global_position.distance_to(bp) <= 140.0 and e.has_method("apply_debuff"):
								e.call("apply_debuff", "lock_step", 2.0)
					ArrayFlag.Kind.GUARD:
						restore_health(max_hp * 0.08)
				# 肉鸽「解阵·回响」：每面旗（含困旗 / 守旗）都额外炸一次
				var echo := RogueRun.stat("array_burst_echo")
				if echo > 0.0:
					var echo_dmg := CharacterData.spell_attack() * echo
					for e in _array_enemy_units():
						if (e as Node2D).global_position.distance_to(bp) <= 160.0:
							_deal_direct_damage(e, echo_dmg, "elemental", "thunder",
								"skill_array_burst")
			_clear_array_flags()
			# 肉鸽「解阵」：把这一发的灵力退回来（主模式不生效）
			if RogueRun.has_flag("array_burst_free"):
				var cost := SkillDB.get_skill_cost("skill_array_burst")
				mana = minf(max_mana, mana + float(cost.get("mana_cost", 0.0)))
				_update_mana_bar()
			return true
	return false


## 封阵四跳（每 0.55 秒一跳）：攻＝法伤 / 困＝锁步 / 守＝自身减伤 70%（2.2 秒）
func _array_start_seal(kind: int, center: Vector2) -> void:
	if kind == ArrayFlag.Kind.GUARD:
		_array_seal_guard_left = 10.0
		_array_seal_guard_pct = ARRAY_SEAL_GUARD_PCT
		_array_seal_guard_flags.clear()
		for f in array_flags:
			if is_instance_valid(f) and not bool(f.get("_dead")):
				_array_seal_guard_flags.append(f)
		_show_float_text("守阵·四象 · 护体 10 秒（无伤）", Color(0.62, 0.90, 1.0))
		return
	if kind == ArrayFlag.Kind.BIND:
		_show_float_text("困阵·四象 · 眩晕 5 秒（无伤）", Color(0.82, 0.86, 0.90))
	var tick_dmg := CharacterData.calc_skill_damage("skill_array_seal", true, false)
	for i in 4:
		if i == 0:
			# 主动施放的第一跳可以起势/叠层；后续三跳是定时触发，只吃增伤与逆印
			_array_seal_tick(kind, center, tick_dmg, true)
			continue
		get_tree().create_timer(0.55 * float(i), true, false, true).timeout.connect(
			func() -> void:
				if is_instance_valid(self) and not is_dead:
					_array_seal_tick(kind, center, tick_dmg, false))


func _array_seal_tick(kind: int, center: Vector2, tick_dmg: float,
		can_stack: bool = false) -> void:
	for e in _array_enemy_units():
		if e.global_position.distance_to(center) > 210.0:
			continue
		match kind:
			ArrayFlag.Kind.ATTACK:
				if e.has_method("take_damage"):
					_deal_direct_damage(e, tick_dmg, "elemental", "fire", "skill_array_seal",
						can_stack)
			ArrayFlag.Kind.BIND:
				# 困牢：5 秒眩晕（BOSS 走 stagger_for；玩家走 stun），已在眩晕中不刷新时长
				_stun_array_unit(e, 5.0)


## 卷阵选旗：挑离「目标→玩家」这条线最近的一面（与 BOSS 的选旗口径一致）
func _array_pull_flag() -> ArrayFlag:
	if array_flags.is_empty():
		return null
	var boss := _nearest_boss(800.0)
	var best: ArrayFlag = null
	var best_d := 999999.0
	for cand in array_flags:
		if not is_instance_valid(cand) or not (cand is Node2D):
			continue
		var fp: Vector2 = (cand as Node2D).global_position
		var d := fp.distance_to(global_position)
		if boss != null:
			d = _array_point_segment_distance(fp, boss.global_position, global_position)
		if d < best_d:
			best_d = d
			best = cand as ArrayFlag
	return best


func _array_centroid() -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for f in array_flags:
		if is_instance_valid(f):
			sum += (f as Node2D).global_position
			n += 1
	return sum / float(maxi(n, 1))


## 封阵多数色（平票 攻 > 困 > 守，与 BOSS 同口径）
func _array_majority_kind() -> int:
	var counts := {ArrayFlag.Kind.ATTACK: 0, ArrayFlag.Kind.BIND: 0, ArrayFlag.Kind.GUARD: 0}
	for f in array_flags:
		if is_instance_valid(f):
			var k := int(f.get("kind"))
			counts[k] = int(counts.get(k, 0)) + 1
	var best := ArrayFlag.Kind.ATTACK
	var best_n := -1
	for k in [ArrayFlag.Kind.ATTACK, ArrayFlag.Kind.BIND, ArrayFlag.Kind.GUARD]:
		if int(counts.get(k, 0)) > best_n:
			best_n = int(counts.get(k, 0))
			best = k
	return best


## 插旗：满 5 面插不下（与 BOSS 同口径，不顶掉旧旗）
func _plant_array_flag(pos: Vector2, kind_id: int = -1) -> ArrayFlag:
	if array_flags.size() >= _array_max_flags():
		return null
	if kind_id < 0:
		kind_id = _next_player_flag_kind()
	var f := ArrayFlag.new()
	f.setup(false, false, kind_id)
	# 玩家旗被敌对打掉 → 五旗完整时触发破阵反噬
	f.destroyed.connect(_on_player_flag_destroyed)
	get_parent().add_child(f)
	# 落点由调用方决定：插旗/踏阵传玩家脚下，垒旗已自行钳过，低级函数不再二次钳制
	f.global_position = pos
	array_flags.append(f)
	# 新旗起手延迟：不让它落地瞬间就轰/锁（与 BOSS 同口径）
	_array_flag_cd[f.get_instance_id()] = 0.8
	_rogue_array_plant_burst(pos)
	return f


## 肉鸽「布杀」：布旗瞬间对落点周围打一发法术伤害。主模式 stat 恒 0 → 不进循环。
func _rogue_array_plant_burst(pos: Vector2) -> void:
	if not RogueRun.active:
		return
	var coef := RogueRun.stat("array_plant_dmg")
	if coef <= 0.0:
		return
	var dmg := CharacterData.spell_attack() * coef
	# 肉鸽「布杀·扩」：溅射半径（主模式 stat 恒 0）
	var radius := 170.0 * (1.0 + RogueRun.stat("array_plant_radius") / 100.0)
	for raw in _array_enemy_units():
		if not is_instance_valid(raw) or not (raw is Node2D):
			continue
		if (raw as Node2D).global_position.distance_to(pos) > radius:
			continue
		_deal_direct_damage(raw, dmg, "elemental", "earth", "skill_array_plant")


func _prune_array_flags() -> void:
	if array_flags.is_empty():
		return
	var live: Array = []
	for f in array_flags:
		if is_instance_valid(f) and not bool(f.get("_dead")):
			live.append(f)
		elif is_instance_valid(f):
			_array_flag_cd.erase((f as Node).get_instance_id())
	if live.size() != array_flags.size():
		array_flags = live


func _clear_array_flags() -> void:
	for f in array_flags:
		if is_instance_valid(f):
			(f as Node).queue_free()
	array_flags.clear()
	_array_flag_cd.clear()
	_array_strikes.clear()
	_clear_array_line_visuals()
	_clear_array_zone()
	_array_seal_guard_left = 0.0
	_array_seal_guard_flags.clear()
	if _array_guard_aura != null and is_instance_valid(_array_guard_aura):
		_array_guard_aura.visible = false


## 清掉「自家五旗阵」的所有区域效果；不涉及敌方阵对玩家的 -10% 攻（那是 boss 的来源）
func _clear_array_zone() -> void:
	_array_zone_complete = false
	_array_zone_timer = 0.0
	_array_zone_self_attack_mult = 1.0
	_array_zone_defense_mult = 1.0
	_refresh_array_zone_attack_mult()
	_clear_array_zone_enemy_debuffs()
	if _array_zone_fill != null and is_instance_valid(_array_zone_fill):
		_array_zone_fill.visible = false
	if has_buff("array_zone"):
		remove_buff("array_zone")


func _refresh_array_zone_attack_mult() -> void:
	CharacterData.array_zone_attack_mult = _array_zone_self_attack_mult * _array_zone_enemy_attack_mult


## 敌方 BOSS 的五旗阵给玩家的攻击削弱（0.9）；离阵/阵散时恢复
func set_array_zone_enemy_attack_mult(mult: float) -> void:
	_array_zone_enemy_attack_mult = clampf(mult, 0.0, 9.0)
	_refresh_array_zone_attack_mult()


func _clear_array_zone_enemy_debuffs() -> void:
	for e in _array_zone_affected_enemies:
		if is_instance_valid(e) and e.has_method("set_zone_attack_mult"):
			e.call("set_zone_attack_mult", "enemy", 1.0)
	_array_zone_affected_enemies.clear()


## 玩家旗被打掉：只有「原本是完整五旗」且「被敌对打掉」才触发反噬
func _on_player_flag_destroyed(flag: ArrayFlag, by_enemy: bool, _source: Node) -> void:
	if not by_enemy:
		return
	# 这面正在破的旗也算一旗；其余只数未 _dead 的
	var alive := 1
	for f in array_flags:
		if f == flag:
			continue
		if is_instance_valid(f) and not bool(f.get("_dead")):
			alive += 1
	if alive < 5:
		return
	apply_debuff("stun", ARRAY_RECOIL_STUN_SECONDS)
	apply_debuff("array_recoil", ARRAY_RECOIL_SECONDS)
	_show_float_text("破阵反噬 · 眩晕5秒 / 15秒无法插旗", UIKit.C_FLOAT_WARN)


func _clear_array_line_visuals() -> void:
	for pair in _array_line_visuals:
		for sp in pair:
			if is_instance_valid(sp):
				(sp as Node).queue_free()
	_array_line_visuals.clear()
	if _array_line_barrier != null and is_instance_valid(_array_line_barrier):
		_array_line_barrier.clear()


## 沿线段结算：命中判据 = 到线段距离 ≤ 40
func _array_line_damage(a: Vector2, b: Vector2, coeff: float) -> void:
	var dmg := CharacterData.spell_attack() * coeff
	for boss in _array_enemy_units():
		if _array_point_segment_distance(boss.global_position, a, b) > 40.0:
			continue
		_deal_direct_damage(boss, dmg, "elemental", "fire", "skill_array_line")


## 布点不能落到墙外：读战场的半尺寸与中心（普通战斗以原点为中心，大世界的中心在世界矩形中心）。
## ⚠ 不能只按原点钳：大世界也暴露 arena_half_extents，但坐标是绝对世界坐标；
##   只按原点钳会在玩家 x≈5000 时把旗甩到 x≈2700，画面上直接看不见旗。
func _array_clamp_point(pos: Vector2) -> Vector2:
	var host := get_parent()
	if host == null:
		return pos
	var half = host.get("arena_half_extents")
	if half is Vector2 and (half as Vector2).x > 1.0 and (half as Vector2).y > 1.0:
		var h := half as Vector2
		var center := Vector2.ZERO
		var c = host.get("arena_center")
		if c is Vector2:
			center = c
		return Vector2(
			clampf(pos.x, center.x - h.x + 60.0, center.x + h.x - 60.0),
			clampf(pos.y, center.y - h.y + 60.0, center.y + h.y - 60.0))
	return pos


func _array_point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## 阵线：n 面旗连成 n-1 段，满 5 面补一段收口（与 BOSS 同构）
func _array_segments() -> Array:
	var live: Array = []
	for f in array_flags:
		if is_instance_valid(f) and f is Node2D:
			live.append(f)
	var out: Array = []
	for i in range(live.size() - 1):
		out.append([live[i], live[i + 1]])
	if live.size() >= _array_max_flags():
		out.append([live[live.size() - 1], live[0]])
	return out


## ===== 气环 · 化劲（太虚气君，2026-10-28）=====

## 学会任意一门气君功法才解锁气环条（和阵旗同一套懒刷新）
func _refresh_qi_unlock() -> void:
	_qi_unlocked = _family_equipped("qi")
	if not _qi_unlocked:
		qi_rings = 0
		_qi_ring_contacts.clear()
		_cancel_qi_channel(false)
	_refresh_qi_hud()


## 气环不再在玩家头顶出读数条（2026-10-30 用户定）：只保留环身气的世界层
func _refresh_qi_hud() -> void:
	_refresh_qi_rings()


## 五枚环身气的世界层（和 BOSS 同一张 qi_ring、同一轨道）
func _ensure_qi_rings() -> void:
	if not _qi_ring_nodes.is_empty():
		while _qi_ring_contacts.size() < _qi_max():
			_qi_ring_contacts.append({})
		return
	for i in _qi_max():
		var spr := Sprite2D.new()
		spr.texture = load(ArtDB.QI_RING_TEX)
		spr.centered = true
		spr.scale = Vector2(0.34, 0.34)
		spr.z_index = 3
		spr.visible = false
		add_child(spr)
		_qi_ring_nodes.append(spr)


func _refresh_qi_rings() -> void:
	for i in _qi_ring_nodes.size():
		var spr: Sprite2D = _qi_ring_nodes[i]
		if is_instance_valid(spr):
			spr.visible = _qi_unlocked and i < qi_rings


## 气环绕体：每枚环按自己的位置找接触到的敌人。
## 判定：环心到敌人**本体边缘**（hit_spheres / hit_radius）≤ QI_RING_HIT_RADIUS。
## 每枚环各自维护「接触中」集合：进入接触才算一次，离开后才能再次命中。
func _tick_qi_rings(delta: float) -> void:
	if not _qi_unlocked and qi_rings <= 0:
		return
	_ensure_qi_rings()
	# 肉鸽「满环·息」：气环满层时持续回血（每帧按秒速折，主模式 stat 恒 0）
	var full_regen := RogueRun.stat("qi_full_regen")
	if full_regen > 0.0 and qi_rings >= _qi_max():
		rogue_heal_pct(full_regen * delta)
	var t := float(Time.get_ticks_msec()) * 0.001
	# 肉鸽「张环」：轨道与判定半径一起放大，纯视觉放大不算数
	var radius_mult := 1.0 + RogueRun.stat("qi_radius_pct") / 100.0
	var orbit := QI_RING_ORBIT * radius_mult
	for i in _qi_ring_nodes.size():
		var spr: Sprite2D = _qi_ring_nodes[i]
		if not is_instance_valid(spr):
			continue
		var ang := t * 1.1 + TAU * float(i) / float(_qi_max())
		spr.position = Vector2(cos(ang) * orbit.x, sin(ang) * orbit.y - 18.0)
		spr.rotation += delta * 1.4
		spr.scale = Vector2(0.34, 0.34) * radius_mult
		spr.visible = _qi_unlocked and i < qi_rings
		if spr.visible:
			spr.modulate = Color(0.60, 0.88, 1.0, 0.92)
	_tick_qi_ring_contacts()


func _tick_qi_ring_contacts() -> void:
	while _qi_ring_contacts.size() < _qi_max():
		_qi_ring_contacts.append({})
	if is_dead:
		return
	var enemies := _array_enemy_units()
	var hit_radius := QI_RING_HIT_RADIUS * (1.0 + RogueRun.stat("qi_radius_pct") / 100.0)
	for i in _qi_ring_nodes.size():
		var spr: Sprite2D = _qi_ring_nodes[i]
		if not is_instance_valid(spr) or i >= _qi_ring_contacts.size():
			continue
		var prev: Dictionary = _qi_ring_contacts[i]
		var now: Dictionary = {}
		if spr.visible:
			var ring_pos: Vector2 = global_position + spr.position
			for e in enemies:
				if not is_instance_valid(e) or not e is Node2D:
					continue
				var d := INF
				if e.has_method("edge_distance_to"):
					d = float(e.call("edge_distance_to", ring_pos))
				elif e.has_method("hit_radius"):
					d = maxf(0.0, ring_pos.distance_to((e as Node2D).global_position)
						- float(e.call("hit_radius")))
				else:
					d = ring_pos.distance_to((e as Node2D).global_position)
				if d > hit_radius:
					continue
				var key := (e as Node2D).get_instance_id()
				now[key] = true
				if not prev.has(key):
					_qi_ring_hit(e)
		_qi_ring_contacts[i] = now


## 单次气环接触：一次元素伤害；回血要佩戴被动「气环·回息」
## 同一次接触不会重复结算
func _qi_ring_hit(target: Node) -> void:
	# 肉鸽「环锋」：接触伤害按 stat 抬（主模式恒 0）
	var dmg := CharacterData.spell_attack() * QI_TOUCH_COEF \
		* (1.0 + RogueRun.stat("qi_touch_pct") / 100.0)
	var final_dmg := _yinyang_modify_damage(target, "elemental", dmg, "", false)
	final_dmg = _rogue_modify_damage(final_dmg, target, "elemental", "")
	if target.has_method("take_damage"):
		target.call("take_damage", final_dmg, self, "elemental", "")
	if target.has_method("apply_debuff"):
		target.call("apply_debuff", "qi_stagnation", 0.8)
	if not _qi_ring_leech_equipped():
		return
	# 肉鸽「吸息」：吸血比例按 stat 抬
	var leech := QI_RING_HEAL_RATIO * (1.0 + RogueRun.stat("qi_leech_pct") / 100.0)
	var healed := restore_health(final_dmg * leech)
	if healed > 0.01:
		QiFx.play_heal(get_parent(), global_position, healed)


## 被动「气环·回息」是否佩戴 —— 只影响环身气回血，不影响伤害 / 滞气 / 气环资源
func _qi_ring_leech_equipped() -> bool:
	var gate := SkillDB.get_passive_by_effect("qi_ring_leech")
	if gate.is_empty():
		return false
	var sid := String(gate.get("skill_id", ""))
	return sid in CharacterData.learned_skills and sid in CharacterData.passive_skill_loadout


func _add_qi(n: int) -> void:
	var before := qi_rings
	qi_rings = clampi(qi_rings + n, 0, _qi_max())
	# 肉鸽「溢息」：环已满时再吃环，改成回复精力（负值 = 消耗，不换算）
	if n > 0 and before >= _qi_max() and RogueRun.active and RogueRun.has_flag("qi_overflow"):
		stamina = minf(max_stamina, stamina + float(n))
		_update_stamina_bar()
	_refresh_qi_hud()


## 气君八式起手：报招名；缩地的云步拖尾在起手帧铺（和 BOSS 的 _cast_step 同拍）
func _qi_precast(skill_id: String, dir: Vector2) -> void:
	if not skill_id.begins_with("skill_qi_"):
		return
	if not _qi_unlocked:
		_refresh_qi_unlock()
	if not _qi_unlocked:
		return
	var form := SkillDB.get_skill_form(skill_id)
	_show_skill_name(SkillDB.get_skill_name(skill_id),
		float(form.get("windup", 0.15)) + 0.2, Color(0.66, 0.90, 1.0))
	if skill_id == "skill_qi_step":
		var fwd := float(form.get("move_forward", 220.0))
		QiFx.play_cloud_step(get_parent(), global_position,
			global_position + dir.normalized() * fwd, float(form.get("windup", 0.12)))


## 气君八式的特殊结算（与 BOSS 同一套）：true = 已经处理完，不再走通用伤害
func _qi_handle_cast(skill_id: String, dir: Vector2) -> bool:
	if not skill_id.begins_with("skill_qi_"):
		return false
	if not _qi_unlocked and qi_rings == 0:
		_refresh_qi_unlock()
	var form := SkillDB.get_skill_form(skill_id)
	match skill_id:
		"skill_qi_gather":
			if qi_rings >= _qi_max():
				_show_float_text("气环已满", Color(0.62, 0.86, 1.0))
				return true
			_add_qi(1)
			SkillFx.play_at_strike(self, skill_id, form, dir)
			return true
		"skill_qi_wave":
			var spent := 0
			if qi_rings > 0:
				qi_rings -= 1
				spent = 1
			_refresh_qi_hud()
			var coeff := 1.30 + float(form.get("qi_bonus_coeff", 0.50)) * float(spent)
			var reach := 460.0 + float(form.get("qi_bonus_range", 90.0)) * float(spent)
			var dmg := CharacterData.calc_skill_damage(skill_id, true, false) * (coeff / 1.30)
			for boss in _array_enemy_units():
				var p: Vector2 = boss.global_position
				var ab := dir.normalized() * reach
				var t := clampf((p - global_position).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
				if p.distance_to(global_position + ab * t) > 50.0:
					continue
				if boss.has_method("take_damage"):
					_deal_direct_damage(boss, dmg, "elemental", "wind", "skill_qi_wave")
			SkillFx.play_at_strike(self, skill_id, form, dir)
			return true
		"skill_qi_spin":
			var dmg2 := CharacterData.calc_skill_damage(skill_id, true, false)
			for boss in _array_enemy_units():
				if boss.global_position.distance_to(global_position) > 168.0:
					continue
				if boss.has_method("take_damage"):
					_deal_direct_damage(boss, dmg2, "physical", "", "skill_qi_spin")
				if boss.has_method("take_knockback"):
					var away: Vector2 = (boss.global_position - global_position).normalized()
					boss.call("take_knockback", away * float(form.get("knockback", 320.0)))
			SkillFx.play_at_strike(self, skill_id, form, dir)
			return true
		"skill_qi_lock":
			# 伤害 / 滞气仍走通用结算；有气环时额外花 1 枚，压 BOSS 移速 + 封技
			if qi_rings > 0:
				qi_rings -= 1
				_refresh_qi_hud()
				var reach := float(form.get("range", 200.0))
				var half := deg_to_rad(float(form.get("angle", 90.0)) * 0.5)
				var fwd := dir.normalized()
				var slow := float(form.get("qi_lock_slow", 0.5))
				var lock_time := float(form.get("qi_lock_skill", 2.0))
				for boss in _array_enemy_units():
					var to: Vector2 = boss.global_position - global_position
					if to.length() > reach:
						continue
					if to.length() > 1.0 and fwd.dot(to.normalized()) < cos(half):
						continue
					if boss.has_method("apply_slow"):
						boss.call("apply_slow", slow, lock_time)
					if boss.has_method("apply_skill_lock"):
						boss.call("apply_skill_lock", lock_time)
				_show_float_text("气锁 · 缚脉", Color(0.62, 0.90, 1.0))
			SkillFx.play_at_strike(self, skill_id, form, dir)
			return false
		"skill_qi_ward":
			var need := int(form.get("qi_need", 1))
			if qi_rings < need:
				_show_float_text("气环不足（需要 %d 枚）" % need, UIKit.C_FLOAT_WARN)
				return true
			qi_rings -= need
			_refresh_qi_hud()
			_qi_ward_reduce = float(form.get("qi_ward_reduce", 0.40))
			_qi_ward_store = float(form.get("qi_ward_store", 0.60))
			_qi_ward_cap = float(form.get("qi_ward_cap", 140.0))
			_qi_release_coeff = float(form.get("qi_release_coeff", 1.20))
			_qi_release_radius = float(form.get("qi_release_radius", 260.0))
			_qi_ward_left = float(form.get("qi_ward_time", 2.2))
			_qi_ward_stored = 0.0
			QiFx.play_ward(self, self, _qi_ward_left)
			_show_float_text("化劲 · 卸力", Color(0.62, 0.90, 1.0))
			return true
		"skill_qi_step":
			# 云步拖尾在起手帧铺（见 _qi_precast）；落点伤害走通用结算；落地凝 1 枚气环
			_add_qi(int(form.get("qi_gain", 1)))
			return false
		"skill_qi_burst":
			var rings := qi_rings
			qi_rings = 0
			_refresh_qi_hud()
			# 肉鸽「爆劲 / 周天」：每环系数与总伤害都能再抬（主模式两个 stat 恒 0）
			var per_ring := 0.60 + RogueRun.stat("qi_burst_per")
			var coeff2 := 1.0 + per_ring * float(rings)
			var dmg3 := CharacterData.calc_skill_damage(skill_id, true, false) * coeff2 \
				* (1.0 + RogueRun.stat("qi_burst_pct") / 100.0)
			var burst_hit := false
			for boss in _array_enemy_units():
				if boss.global_position.distance_to(global_position) <= 240.0:
					if boss.has_method("take_damage"):
						_deal_direct_damage(boss, dmg3, "elemental", "wind", "skill_qi_burst")
						burst_hit = true
			# 肉鸽「爆息」：气爆命中回灵
			var burst_mana := RogueRun.stat("qi_burst_mana")
			if burst_hit and burst_mana > 0.0 and mana < max_mana:
				mana = minf(max_mana, mana + burst_mana)
				_update_mana_bar()
			# 肉鸽「环吸」：爆完把周围敌人向中心拽近（击退向量反向 = 吸）
			if RogueRun.has_flag("qi_burst_pull"):
				for boss in _array_enemy_units():
					if not is_instance_valid(boss) or not boss is Node2D:
						continue
					var pull: Vector2 = global_position - (boss as Node2D).global_position
					if pull.length() > 240.0 or pull.length() < 1.0:
						continue
					if boss.has_method("take_knockback"):
						boss.call("take_knockback", pull.normalized() * 160.0)
			SkillFx.play_at_strike(self, skill_id, form, dir)
			return true
		"skill_qi_breath":
			# 与 BOSS 同款：1.2 秒引导，期间受伤超过 8% 最大气血会被打断；要花 1 枚气环
			if _qi_channel_left > 0.0:
				_show_float_text("吐纳中…", Color(0.62, 0.98, 0.78))
				return true
			var breath_need := int(form.get("qi_need", 1))
			if qi_rings < breath_need:
				_show_float_text("气环不足（需要 %d 枚）" % breath_need, UIKit.C_FLOAT_WARN)
				return true
			qi_rings -= breath_need
			_refresh_qi_hud()
			_qi_channel_damage = 0.0
			_qi_channel_break = float(form.get("channel_break_damage", 0.08))
			_qi_channel_left = float(form.get("channel_time", 1.2))
			if is_instance_valid(_qi_channel_fx):
				_qi_channel_fx.queue_free()
			_qi_channel_fx = QiFx.play_breath(get_parent(), self, _qi_channel_left)
			return true
	return false


func _tick_qi_ward(delta: float) -> void:
	if _qi_ward_left <= 0.0:
		return
	_qi_ward_left = maxf(0.0, _qi_ward_left - delta)
	if _qi_ward_left > 0.0:
		return
	# 结束：把蓄下的力放出去（与 BOSS 同款，物理近战）
	var dmg := (CharacterData.spell_attack() * _qi_release_coeff + _qi_ward_stored) \
		* CharacterData.sword_intent_skill_mult
	for boss in _array_enemy_units():
		if boss.global_position.distance_to(global_position) <= _qi_release_radius:
			if boss.has_method("take_damage"):
				_deal_direct_damage(boss, dmg, "physical", "", "skill_qi_ward")
	QiFx.play_release(get_parent(), global_position, _qi_release_radius, _qi_ward_stored > 1.0)
	_qi_ward_stored = 0.0


## 吐纳引导：与 BOSS 同款 1.2 秒；期间受伤超过 8% 最大气血会被打断
func _tick_qi_channel(delta: float) -> void:
	if _qi_channel_left <= 0.0:
		return
	_qi_channel_left = maxf(0.0, _qi_channel_left - delta)
	if is_dead:
		_cancel_qi_channel(false)
		return
	if _qi_channel_damage >= max_hp * _qi_channel_break:
		_cancel_qi_channel(true)
		return
	if _qi_channel_left > 0.0:
		return
	var healed := restore_health(max_hp * 0.10)
	if healed > 0.0:
		QiFx.play_heal(get_parent(), global_position, healed)
	_free_qi_channel_fx()
	_qi_channel_damage = 0.0


func _cancel_qi_channel(announce: bool) -> void:
	_free_qi_channel_fx()
	_qi_channel_left = 0.0
	_qi_channel_damage = 0.0
	if announce and not is_dead:
		_show_float_text("吐纳被打断", UIKit.C_FLOAT_WARN)


func _free_qi_channel_fx() -> void:
	if is_instance_valid(_qi_channel_fx):
		_qi_channel_fx.queue_free()
	_qi_channel_fx = null


# ===== 判词 · 天律（赫连霄，2026-10-29）=====
## 玩家侧与 BOSS 完全同构：
##   · 判词按目标最近 1.5 秒的行为自动选律（移动 / 出手 / 闪避 / 站定）；
##   · 目标违律 → 落雷 + 玩家雷势 +1；判词走完没违律 → 它守住了，没有奖励；
##   · 雷势 0~3，九霄·雷罚消耗全部；聚雷·引霆也能 +1。
## 目标被下律后会按律改变行为（少走 / 收手 / 少遁 / 少站），所以判词也是控制。
## 雷势上限：基值在 RogueDB.CAP_BASE，肉鸽增益可 +N；主模式恒为 3
func _thunder_max() -> int:
	return RogueRun.cap("thunder_max")
## 满雷势：攻速 +30%（按「攻速 +100% = 间隔减半」的口径，间隔 ÷1.3）
const THUNDER_FULL_HASTE := 0.30
## 满雷势平A协同雷击：法术 ×0.5，落点 = 身前 320 内最近目标
const THUNDER_COOP_COEF := 0.50
const THUNDER_COOP_RANGE := 320.0
const THUNDER_COOP_HALF_ANGLE := 85.0
const THUNDER_COOP_RADIUS := 62.0
const THUNDER_COOP_SKILL_ID := "skill_thunder_coop"
const THUNDER_LAW_TIME := 5.0
const THUNDER_LAW_COEF := 0.75
## 被动「雷积·震魂」：数值在 SkillDB（被动详情与规则卡同源）
const THUNDER_ACCUM_REQUIRED := SkillDB.THUNDER_ACCUM_REQUIRED
const THUNDER_ACCUM_STUN_SECONDS := SkillDB.THUNDER_ACCUM_STUN_SECONDS
const THUNDER_ACCUM_CD_PER_LEI := SkillDB.THUNDER_ACCUM_CD_PER_LEI
const THUNDER_ACCUM_META := "player_thunder_accum_hits"
var lei_shi: int = 0
## 肉鸽「引雷」内置 CD：同一时间只允许一道追加雷（防连击刷满屏）
var _rogue_lei_chain_left: float = 0.0
var _thunder_unlocked: bool = false
var _thunder_pips: ThunderPips = null
var _verdict_banner: VerdictBanner = null
var _pending_player_law: String = ""
var _pending_player_laws: Array[String] = []

# 玩家下给目标的两条判词：主律保留旧字段，副律用 _law2_*
var _law_target: Node2D = null
var _law_id: String = ""
var _law_left: float = 0.0
var _law_total: float = THUNDER_LAW_TIME
var _law_violations: int = 0
var _law_cd: float = 0.0
var _law2_id: String = ""
var _law2_left: float = 0.0
var _law2_violations: int = 0
var _law2_cd: float = 0.0
var _law_moved: float = 0.0
var _law_still: float = 0.0
var _law_prev_pos := Vector2.INF
var _law_prev_state: int = 0
var _law_dash_window: float = 0.0
var _law_dash_dist: float = 0.0
var _law_mark: Node2D = null
var _law_mark_label: Label = null
var _law_mark_label2: Label = null

# 目标行为窗口（选律用）：雷遁 / 出手 / 移动
var _boss_watch_target: Node2D = null
var _boss_watch_pos := Vector2.INF
var _boss_dash_window: float = 0.0
var _boss_dash_dist: float = 0.0
var _boss_dash_recent: float = 0.0
var _boss_move_recent: float = 0.0
var _boss_attack_recent: float = 0.0
var _boss_still: float = 0.0

# 聚雷引导
var _thunder_channel_left: float = 0.0
var _thunder_channel_damage: float = 0.0
var _thunder_channel_break: float = 0.08
var _thunder_channel_tick: float = 0.0
var _thunder_channel_fx: Node2D = null


# ===== 逐日·天火（离照，2026-10-29）=====
## 天火种是场上实体（SunSeed）；玩家只同步持有状态、层数与 HUD。
## 日冕走 CharacterData.sun_damage_mult（玩家所有伤害乘区），不绑火焰功法。
const SUN_HOLD_BURN_SECONDS := 1.4
const SUN_HOLD_DAMAGE_PER_STACK := 0.12
const SUN_BEARER_FIRST_DELAY := 1.0
const SUN_BEARER_RESPAWN := 1.5
const SUN_BEARER_RADIUS_MIN := 90.0
const SUN_BEARER_RADIUS_MAX := 130.0
## 日冕满层的「焚心」：下一次离照功法命中后，1 秒在目标体内爆一次 2.0×法强火伤
const SUN_NOVA_DELAY := 1.0
const SUN_NOVA_SPELL_COEFF := 2.0
const SUN_NOVA_BURST_RADIUS := 92.0
var sun_stacks: int = 0
## 满层蓄引燃：每次从 <3 层升到 3 层只给 1 次，命中后消费；不因丢种立即失效
var _sun_nova_charge: bool = false
## 蓄满那一刻的日冕乘区（3 层固定值），投日丢种后引爆也不会丢加成
var _sun_nova_mult: float = 1.0
var _sun_nova_target: Node2D = null
var _sun_nova_marker: Node2D = null
var _sun_nova_offset := Vector2(0.0, -48.0)
## 盗火者被动的凝种倒计时；离照会抢同一枚种子，但被动仍照常凝种。
var _sun_bearer_respawn_left: float = 0.0
var _sun_unlocked: bool = false
var _sun_seed: SunSeed = null
var _sun_pips: SunPips = null
var _wind_window_token: int = 0

# ===== 符箓（2026-10-31）：4 功法格瞬发 =====
const TALISMAN_FX := preload("res://scripts/visual/talisman_fx.gd")
const TALISMAN_MANA_COST := 5.0
const TALISMAN_WIND_SOURCE := "talisman_wind"
const TALISMAN_STONE_SOURCE := "talisman_stone"
var _talisman_water_left: float = 0.0
var _talisman_water_tick: float = 0.0
var _talisman_water_per_sec: float = 0.0
var _talisman_wind_left: float = 0.0
var _talisman_stone_left: float = 0.0
var _talisman_stone_reduce: float = 0.0
var _talisman_stone_hits: int = 0


# ===== 噪声事件（大世界闻声首领读取，2026-10-31）=====
## 出手 / 施法 / 闪避会在当前位置留下一个「大声点」；跑动由首领按脚步轮询。
## 首领把该点当最后声点，不读取玩家实时位置。
var noise_ping_seq: int = 0
var noise_ping_pos: Vector2 = Vector2.ZERO


func emit_noise() -> void:
	noise_ping_seq += 1
	noise_ping_pos = global_position


# ===== 三灾·轮转（晏无咎，2026-10-29）=====
## 玩家灾位 / 灾势；灾位跟最近使用的灾属性功法走，灾势由轮转与破灾产生。
const CALAMITY_WIND := "wind"
const CALAMITY_FIRE := "fire"
const CALAMITY_THUNDER := "thunder"
const CALAMITY_MAX_MOMENTUM := 3
var calamity_element: String = ""
var calamity_momentum: int = 0
var _calamity_unlocked: bool = false
## 被动「三灾·灾身」是否佩戴：它才是玩家三灾轮 / 灾身加成 / 灾替的开关。
## 未佩戴时仍可用任意对应属性功法破灾 / 喂灾，但没有玩家侧灾位资源。
var _calamity_passive_on: bool = false
var _calamity_wheel: CalamityWheel = null
var _calamity_break_cd: float = 0.0


## 这一族（sun / thunder / calamity / qi）的功法是否**带在身上**（出战槽：主动 4 / 被动 1）。
## ⚠ 只「学会」不算有手段：带不上场就涨不了势，对应的势条也不该显示（2026-10-30 用户定）。
func _family_equipped(field: String) -> bool:
	for sid in CharacterData.active_skill_loadout:
		if bool(SkillDB.get_skill(String(sid)).get(field, false)):
			return true
	for sid in CharacterData.passive_skill_loadout:
		if bool(SkillDB.get_skill(String(sid)).get(field, false)):
			return true
	return false

func _refresh_sun_unlock() -> void:
	_sun_unlocked = false
	for sid in CharacterData.learned_skills:
		if bool(SkillDB.get_skill(String(sid)).get("sun", false)):
			_sun_unlocked = true
			break
	if not _sun_unlocked:
		_clear_sun_crown()
		sun_stacks = 0
		_reset_sun_nova()
	_refresh_sun_hud()
	_ensure_sun_hud()


func _ensure_sun_hud() -> void:
	if not _sun_unlocked:
		if _sun_pips != null and is_instance_valid(_sun_pips):
			_sun_pips.visible = false
		return
	if _sun_pips == null or not is_instance_valid(_sun_pips):
		_sun_pips = SunPips.new()
		_sun_pips.name = "SunPips"
		add_mechanic_row(_sun_pips)
	_refresh_sun_hud()


func _find_sun_seed() -> SunSeed:
	for raw in get_tree().get_nodes_in_group("sun_seed"):
		var s := raw as SunSeed
		if s != null and is_instance_valid(s):
			return s
	return null


func _sun_holding() -> bool:
	return _sun_seed != null and is_instance_valid(_sun_seed) \
		and _sun_seed.is_held_by(self)


func _refresh_sun_hud() -> void:
	if _sun_pips == null or not is_instance_valid(_sun_pips):
		return
	var seed := _sun_seed
	if not _sun_unlocked or seed == null or not is_instance_valid(seed):
		_sun_pips.visible = false
		return
	_sun_pips.visible = true
	var marker := ""
	if seed.is_held_by(self) and sun_stacks >= SunSeed.MAX_STACKS:
		marker = "灼"
	elif seed.holder != null and seed.holder.is_in_group("boss"):
		marker = "夺"
	elif seed.is_free():
		marker = "日"
	_sun_pips.set_state(sun_stacks, marker)


func _apply_sun_crown() -> void:
	if sun_stacks <= 0:
		_clear_sun_crown()
		return
	# 2026-10-29 用户定：持种加成作用于自身**所有伤害**，不再只加火焰/力量法强。
	var per_stack := SUN_HOLD_DAMAGE_PER_STACK + RogueRun.stat("sun_per_stack") / 100.0
	var total := 1.0 + per_stack * float(sun_stacks)
	# 肉鸽「烈阳」：满层时再叠一档（主模式 stat 恒 0）
	if sun_stacks >= RogueRun.cap("sun_max"):
		total += RogueRun.stat("sun_full_dmg") / 100.0
	CharacterData.sun_damage_mult = total
	remove_buff("sun_crown")
	apply_buff("sun_crown", 0.0, sun_stacks)


func _clear_sun_crown() -> void:
	CharacterData.sun_damage_mult = 1.0
	# 旧版曾用 attribute_mods 存日冕；这里顺手清掉旧存档/热重载残留
	CharacterData.clear_attribute_mod("sun_crown")
	remove_buff("sun_crown")


## 日冕满层后的一次性引燃：只由离照功法命中消费；普攻、火地跳伤不触发
func _try_arm_sun_nova(target: Node, skill_id: String) -> void:
	if not _sun_nova_charge:
		return
	if not skill_id.begins_with("skill_sun_"):
		return
	if target == null or not is_instance_valid(target) or not target is Node2D:
		return
	if not target.has_method("take_damage"):
		return
	if _enemy_is_dead(target):
		return
	_sun_nova_charge = false
	var t := target as Node2D
	_sun_nova_target = t
	_sun_nova_offset = _sun_nova_body_offset(t)
	_clear_sun_nova_marker()
	_sun_nova_marker = SkillFx.sun_ember_mark(get_parent(), SUN_NOVA_DELAY)
	if _sun_nova_marker != null and is_instance_valid(_sun_nova_marker):
		_sun_nova_marker.global_position = t.global_position + _sun_nova_offset
	var dmg := _sun_nova_damage(_sun_nova_mult)
	_show_float_text("日冕引燃", Color(1.0, 0.66, 0.26))
	# 用默认计时器（随时间缩放）：ignore_time_scale=true 在本机引擎上于部分时机会当帧触发
	get_tree().create_timer(SUN_NOVA_DELAY).timeout.connect(
		func() -> void: _detonate_sun_nova(t, dmg))


## 引燃落在目标体内：取可见立绘的包围盒中点（rig 原点有的在脚底、有的在胸口，
## 不能用受击球 y —— BOSS 的 hit_spheres 已把 y 压到命中平面 0）
func _sun_nova_body_offset(t: Node2D) -> Vector2:
	var root: Node = t.get_node_or_null("Visual")
	if root == null:
		root = t
	var top := INF
	var bottom := -INF
	for n in root.find_children("*", "CanvasItem", true, false):
		var ci := n as CanvasItem
		if ci == null or not ci.is_visible_in_tree() or not (n is Node2D):
			continue
		var half := 0.0
		var spr := n as Sprite2D
		if spr != null and spr.texture != null:
			half = float(spr.texture.get_height()) * 0.5
		elif n is AnimatedSprite2D:
			var anim := n as AnimatedSprite2D
			if anim.sprite_frames == null \
					or not anim.sprite_frames.has_animation(anim.animation):
				continue
			var max_h := 0
			for fi in anim.sprite_frames.get_frame_count(anim.animation):
				var tex := anim.sprite_frames.get_frame_texture(anim.animation, fi)
				if tex != null:
					max_h = maxi(max_h, tex.get_height())
			if max_h <= 0:
				continue
			half = float(max_h) * 0.5
		else:
			continue
		var nd := n as Node2D
		var p_top := t.to_local(nd.to_global(Vector2(0.0, -half)))
		var p_bot := t.to_local(nd.to_global(Vector2(0.0, half)))
		top = minf(top, p_top.y)
		bottom = maxf(bottom, p_bot.y)
	if top == INF or bottom == -INF or bottom - top < 20.0:
		return Vector2(0.0, -48.0)
	return Vector2(0.0, (top + bottom) * 0.5)


func _sun_nova_damage(sun_mult: float) -> float:
	var ctx := {
		"phys_power": CharacterData.physical_attack(),
		"spell_power": CharacterData.spell_attack(),
		"phys_coeff": 0.0,
		"spell_coeff": SUN_NOVA_SPELL_COEFF * ItemDB.SKILL_DAMAGE_COEFF \
			* CharacterData.spell_skill_damage_mult(),
		"random": true,
	}
	return float(DamageCalc.resolve(ctx).get("amount", 0.0)) * sun_mult \
		* (1.0 + RogueRun.stat("sun_nova_pct") / 100.0)


func _detonate_sun_nova(t: Node2D, dmg: float) -> void:
	_clear_sun_nova_marker()
	if not is_instance_valid(self) or is_dead:
		return
	if t == null or not is_instance_valid(t) or _enemy_is_dead(t):
		return
	SkillFx.sun_burst_at(get_parent(), t.global_position + _sun_nova_offset,
		SUN_NOVA_BURST_RADIUS * (1.0 + RogueRun.stat("sun_nova_radius") / 100.0), 0.95, 0.5)
	_deal_direct_damage(t, dmg, "elemental", "fire", "sun_nova")
	# 肉鸽「余烬」：焚心命中附带灼烧（主模式 has_flag 恒 false）
	if RogueRun.has_flag("sun_nova_burn") and t.has_method("apply_debuff"):
		t.call("apply_debuff", "sunburn", 3.0)
	# 满日冕引燃真正炸到敌人：消耗 1 层日冕，并刷新逐日步，让下一段位移立刻接上
	_consume_sun_layer_for_nova()
	skill_cooldowns.erase("skill_sun_step")


func _consume_sun_layer_for_nova() -> void:
	var seed := _find_sun_seed()
	if seed != null and is_instance_valid(seed) and seed.state != SunSeed.State.GONE \
			and seed.consume_layer():
		_tick_sun(0.0)


func _clear_sun_nova_marker() -> void:
	if _sun_nova_marker != null and is_instance_valid(_sun_nova_marker):
		_sun_nova_marker.queue_free()
	_sun_nova_marker = null


func _update_sun_nova_marker() -> void:
	if _sun_nova_marker == null:
		return
	if not is_instance_valid(_sun_nova_marker):
		_sun_nova_marker = null
		return
	var t := _sun_nova_target
	if t == null or not is_instance_valid(t) or _enemy_is_dead(t):
		_clear_sun_nova_marker()
		return
	_sun_nova_marker.global_position = t.global_position + _sun_nova_offset


func _reset_sun_nova() -> void:
	_sun_nova_charge = false
	_sun_nova_mult = 1.0
	_sun_nova_target = null
	_clear_sun_nova_marker()


## 盗火者被动是否佩戴（认 passive_effect，不硬比 skill_id）
func _sun_bearer_equipped() -> bool:
	if not _sun_unlocked:
		return false
	var gate := SkillDB.get_passive_by_effect("sun_seed_bearer")
	if gate.is_empty():
		return false
	var sid := String(gate.get("skill_id", ""))
	return sid in CharacterData.learned_skills and sid in CharacterData.passive_skill_loadout


func _sun_bearer_seed_pos() -> Vector2:
	var ang := randf() * TAU
	var dist := randf_range(SUN_BEARER_RADIUS_MIN, SUN_BEARER_RADIUS_MAX)
	return global_position + Vector2(cos(ang), sin(ang)) * dist + Vector2(0.0, -10.0)


func _tick_sun_bearer(delta: float) -> void:
	if not _sun_bearer_equipped():
		return
	if _find_sun_seed() != null:
		_sun_bearer_respawn_left = 0.0
		return
	_sun_bearer_respawn_left = maxf(0.0, _sun_bearer_respawn_left - delta)
	if _sun_bearer_respawn_left <= 0.0 and not is_dead:
		_spawn_player_sun_seed(_sun_bearer_seed_pos())


func _on_sun_bearer_seed_consumed() -> void:
	if not _sun_bearer_equipped():
		return
	_sun_bearer_respawn_left = SUN_BEARER_RESPAWN


func _tick_sun(delta: float) -> void:
	_update_sun_nova_marker()
	# 肉鸽「日浴」：满层天火种持续回血（主模式 stat 恒 0）
	var sun_regen := RogueRun.stat("sun_full_regen")
	if sun_regen > 0.0 and sun_stacks >= RogueRun.cap("sun_max"):
		rogue_heal_pct(sun_regen * delta)
	_tick_sun_bearer(delta)
	_sun_seed = _find_sun_seed()
	if _sun_seed == null or not is_instance_valid(_sun_seed):
		sun_stacks = 0
		_clear_sun_crown()
		_refresh_sun_hud()
		return
	if _sun_seed.is_held_by(self):
		var prev_stacks := sun_stacks
		sun_stacks = _sun_seed.stacks
		_apply_sun_crown()
		if sun_stacks >= SunSeed.MAX_STACKS:
			# 每次从 <3 层升满只蓄一次引燃；引爆后要重新叠满
			if not _sun_nova_charge and prev_stacks < SunSeed.MAX_STACKS:
				_sun_nova_charge = true
				_sun_nova_mult = CharacterData.sun_damage_mult
			# 持种满层的自灼：短刷新；丢种后自然到期，不会洗掉 BOSS 打的灼烧
			apply_debuff("sunburn", SUN_HOLD_BURN_SECONDS, true)
	else:
		sun_stacks = 0
		_clear_sun_crown()
	_refresh_sun_hud()


## 肉鸽逐日：给手里的火种补 1 层（主模式不会被调用 —— 所有调用点都带 RogueRun 判定）
func _rogue_gain_sun_stack() -> void:
	if not RogueRun.active:
		return
	if _sun_seed == null or not is_instance_valid(_sun_seed) or not _sun_seed.is_held_by(self):
		return
	_sun_seed.stacks = mini(_sun_seed.max_stacks(), _sun_seed.stacks + 1)
	if _sun_seed.has_method("_apply_stack_visual"):
		_sun_seed.call("_apply_stack_visual")
	_show_float_text("日归 · 火种 +1", Color(1.0, 0.78, 0.32))


func on_sun_seed_gained(_seed: SunSeed) -> void:
	_show_float_text("日冕加身", Color(1.0, 0.78, 0.32))

func on_sun_seed_lost(_seed: SunSeed) -> void:
	sun_stacks = 0
	_clear_sun_crown()
	_refresh_sun_hud()


func on_sun_seed_full(_seed: SunSeed) -> void:
	_show_float_text("烈阳！投日或日蚀", Color(1.0, 0.54, 0.22))


func on_sun_seed_burst(_seed: SunSeed) -> void:
	# 火种在手里爆裂：12% 最大气血火焰伤害（过抗后由 take_damage 结算）
	take_damage(max_hp * float(SunSeed.PLAYER_BURST_PCT), "elemental", null, "fire")
	sun_stacks = 0
	_clear_sun_crown()
	_refresh_sun_hud()


func _refresh_calamity_unlock() -> void:
	# 本族主动仍决定「招式专属结算是否运行」；玩家灾轮 / 加成只认被动。
	_calamity_unlocked = _family_equipped("calamity")
	_calamity_passive_on = _calamity_passive_equipped()
	if not _calamity_passive_on:
		calamity_element = ""
		calamity_momentum = 0
		CharacterData.clear_attribute_mod("calamity_element")
		remove_buff("sanzai_guard")
	_refresh_calamity_hud()
	_ensure_calamity_hud()


func _calamity_passive_equipped() -> bool:
	var gate := SkillDB.get_passive_by_effect("calamity_stance")
	if gate.is_empty():
		return false
	var sid := String(gate.get("skill_id", ""))
	return sid in CharacterData.learned_skills and sid in CharacterData.passive_skill_loadout


func _ensure_calamity_hud() -> void:
	if not _calamity_passive_on:
		if _calamity_wheel != null and is_instance_valid(_calamity_wheel):
			_calamity_wheel.visible = false
		return
	if _calamity_wheel == null or not is_instance_valid(_calamity_wheel):
		_calamity_wheel = CalamityWheel.new()
		_calamity_wheel.name = "CalamityWheel"
		add_mechanic_row(_calamity_wheel)
	_refresh_calamity_hud()


func _tick_calamity(delta: float) -> void:
	_calamity_break_cd = maxf(0.0, _calamity_break_cd - delta)
	if not _calamity_passive_on:
		return
	if calamity_element != "":
		_apply_calamity_boon()
	_refresh_calamity_hud()


func _apply_calamity_boon() -> void:
	CharacterData.clear_attribute_mod("calamity_element")
	if not _calamity_passive_on:
		return
	var boon := SkillDB.CALAMITY_BOON_PCT
	if calamity_element == CALAMITY_WIND:
		CharacterData.set_attribute_mod("calamity_element", {
			AttributeDB.ATTR_SPEED_PCT: {"flat": boon},
		})
	elif calamity_element == CALAMITY_FIRE:
		CharacterData.set_attribute_mod("calamity_element", {
			AttributeDB.ATTR_SPELL_SKILL_DAMAGE_PCT: {"flat": boon},
		})
	elif calamity_element == CALAMITY_THUNDER:
		CharacterData.set_attribute_mod("calamity_element", {
			AttributeDB.ATTR_ATTACK_SPEED: {"flat": boon},
		})


func _calamity_boss() -> Node2D:
	for raw in get_tree().get_nodes_in_group("boss"):
		# ⚠ 死单位不参与索敌 / 结算：试炼里 BOSS 尸体不销毁、仍在 "boss" 组
		if BossBase.is_unit_dead(raw):
			continue
		var b := raw as Node2D
		if b == null or not is_instance_valid(b):
			continue
		if not b.has_method("calamity_state"):
			continue
		var st = b.get("state")
		if st != null and int(st) == 6:
			continue
		return b
	return null


func _calamity_beats(a: String, b: String) -> bool:
	return (a == CALAMITY_WIND and b == CALAMITY_FIRE) \
		or (a == CALAMITY_FIRE and b == CALAMITY_THUNDER) \
		or (a == CALAMITY_THUNDER and b == CALAMITY_WIND)


func _calamity_counter_of(element: String) -> String:
	match element:
		CALAMITY_FIRE:
			return CALAMITY_WIND
		CALAMITY_THUNDER:
			return CALAMITY_FIRE
		CALAMITY_WIND:
			return CALAMITY_THUNDER
	return CALAMITY_WIND


func _calamity_next(element: String) -> String:
	match element:
		CALAMITY_WIND:
			return CALAMITY_FIRE
		CALAMITY_FIRE:
			return CALAMITY_THUNDER
		_:
			return CALAMITY_WIND


func _calamity_set_element(element: String, gain: bool = true) -> void:
	if element == "" or not _calamity_passive_on:
		return
	if has_debuff("suo_zai") and calamity_element != "" and element != calamity_element:
		_show_float_text("灾位被锁", UIKit.C_FLOAT_WARN)
		return
	var prev := calamity_element
	calamity_element = element
	if gain and prev != "" and prev != element:
		_calamity_add_momentum(1)
	elif gain and prev == "":
		_calamity_add_momentum(1)
	_apply_calamity_boon()
	_refresh_calamity_hud()
	# 肉鸽「灾临」：换灾位时给场上所有敌人挂上对应灾痕（主模式 has_flag 恒 false）
	if gain and prev != "" and prev != element and RogueRun.has_flag("calamity_swap_all"):
		var mark := "feng_shi"
		if element == CALAMITY_FIRE:
			mark = "jie_huo"
		elif element == CALAMITY_THUNDER:
			mark = "gan_dian"
		for raw in _array_enemy_units():
			if not is_instance_valid(raw) or not raw.has_method("apply_debuff"):
				continue
			raw.call("apply_debuff", mark, 4.0)
			_attach_calamity_marks_if_needed(raw, mark)


func _calamity_add_momentum(n: int) -> void:
	if not _calamity_passive_on:
		return
	calamity_momentum = clampi(calamity_momentum + n, 0, RogueRun.cap("calamity_max"))
	_refresh_calamity_hud()


func _refresh_calamity_hud() -> void:
	if _calamity_wheel == null or not is_instance_valid(_calamity_wheel):
		return
	if not _calamity_passive_on:
		_calamity_wheel.visible = false
		return
	# 灾位与灾势都是玩家自己的资源：装备被动后始终可见。
	# 灾势靠风 / 火 / 雷轮换灾位积累，打任何 BOSS 都会涨；只有「克 / 危 / 锁 / 替 / 乱」
	# 需要对手本身有灾位读数时才显示。
	var boss := _calamity_boss()
	var has_boss := boss != null
	_calamity_wheel.visible = true
	var marker := ""
	if has_boss:
		var boss_el := String(boss.call("calamity_state"))
		if has_debuff("suo_zai"):
			marker = "锁"
		elif has_buff("sanzai_guard"):
			marker = "替"
		elif boss_el == "fusion":
			marker = "乱"
		elif _calamity_beats(calamity_element, boss_el):
			marker = "克"
		elif _calamity_beats(boss_el, calamity_element):
			marker = "危"
	_calamity_wheel.set_state(calamity_element, calamity_momentum, marker)


func _calamity_precast(skill_id: String) -> void:
	if not _calamity_passive_on:
		return
	var tag := _calamity_tag_for_skill(skill_id)
	if tag == "":
		return
	_calamity_set_element(tag, true)


## 任意风 / 火 / 雷功法都可作为玩家灾位的切换来源；本族 turn / final 交专属结算。
func _calamity_tag_for_skill(skill_id: String) -> String:
	var form := SkillDB.get_skill_form(skill_id)
	if form.is_empty():
		return ""
	var raw := String(form.get("calamity_tag", ""))
	if raw == "turn" or raw == "final":
		return ""
	if raw != "":
		return raw
	return _calamity_tag_for_element(String(form.get("damage_element", "")))


## true = 三灾八式已处理，不再走通用伤害
func _calamity_handle_cast(skill_id: String, dir: Vector2) -> bool:
	if not skill_id.begins_with("skill_calamity_"):
		return false
	if not _calamity_unlocked:
		_refresh_calamity_unlock()
	if not _calamity_unlocked:
		return false
	var form := SkillDB.get_skill_form(skill_id)
	if form.is_empty():
		return false
	match skill_id:
		"skill_calamity_step":
			_cast_calamity_step(form, dir)
			return true
		"skill_calamity_slash":
			_cast_calamity_slash(form, dir)
			return true
		"skill_calamity_fire_seal":
			_cast_calamity_fire_seal(form, dir)
			return true
		"skill_calamity_fire_field":
			_cast_calamity_fire_field(form, dir)
			return true
		"skill_calamity_thunder_strike":
			_cast_calamity_thunder_strike(form, dir)
			return true
		"skill_calamity_thunder_pool":
			_cast_calamity_thunder_pool(form, dir)
			return true
		"skill_calamity_turn":
			_cast_calamity_turn(form, dir)
			return true
		"skill_calamity_final":
			_cast_calamity_final(form, dir)
			return true
	return false


func _calamity_out_mult(tag: String) -> float:
	var boss := _calamity_boss()
	if boss == null or tag == "" or tag == "turn":
		return 1.0
	var boss_el := String(boss.call("calamity_state"))
	if boss_el == "fusion":
		return 1.0
	if _calamity_beats(tag, boss_el):
		return 1.15
	if tag == boss_el:
		return 0.85
	return 1.0


## 任意风 / 火 / 雷属性功法命中都参与三灾判定，不要求功法属于晏无咎本族。
## 普通功法只负责破灾 / 喂灾；灾势、灾替与万劫归一仍由本族功法那套层处理。
func _calamity_tag_for_element(elem: String) -> String:
	match elem:
		"wind":
			return CALAMITY_WIND
		"fire":
			return CALAMITY_FIRE
		"thunder":
			return CALAMITY_THUNDER
	return ""


func notify_calamity_element_hit(target: Node, elem: String, skill_id: String = "") -> void:
	if skill_id.begins_with("skill_calamity_"):
		return
	if target == null or not is_instance_valid(target) or not (target is Node2D):
		return
	if not target.has_method("calamity_state"):
		return
	var tag := _calamity_tag_for_element(elem)
	if tag == "" and skill_id != "":
		tag = _calamity_tag_for_element(SkillDB.get_damage_element(skill_id))
	if tag == "":
		return
	_calamity_notify_hit(target as Node2D, tag)


func _calamity_notify_hit(boss: Node2D, tag: String) -> void:
	if boss == null or not is_instance_valid(boss) or tag == "" or tag == "turn":
		return
	var boss_el := String(boss.call("calamity_state"))
	if boss_el == "fusion":
		return
	if _calamity_beats(tag, boss_el):
		if bool(boss.call("on_calamity_broken", self)):
			_calamity_add_momentum(1)
	elif tag == boss_el:
		boss.call("gain_calamity_momentum", 1)


## 灾劫连锁：用克制目标灾痕的属性命中，引爆对应反应。
## 装备 / 未装备「三灾·灾身」都生效；燎原 / 雷池的持续跳伤也能引爆（同一道灾痕只消耗一次）。
## 只有能被直接命中或跳伤命中的敌人会引爆；返回是否真的引爆。
func _try_calamity_reaction(target: Node, trigger_tag: String, base_dmg: float) -> bool:
	if not _calamity_unlocked:
		return false
	if target == null or not is_instance_valid(target) or base_dmg <= 0.0:
		return false
	if _enemy_is_dead(target):
		return false
	var reaction := SkillDB.calamity_reaction_for(trigger_tag)
	if reaction.is_empty():
		return false
	var fuel := String(reaction.get("fuel", ""))
	if fuel == "" or not target.has_method("has_debuff") \
			or not target.has_method("remove_debuff"):
		return false
	if not bool(target.call("has_debuff", fuel)):
		return false
	target.call("remove_debuff", fuel)
	var rid := String(reaction.get("id", ""))
	var radius := float(reaction.get("radius", 100.0))
	var pos: Vector2 = (target as Node2D).global_position if target is Node2D else global_position
	var kind := String(reaction.get("kind", "burst"))
	# 肉鸽「连锁·烈」：连锁伤害整体放大（主模式 stat 恒 0）
	var react_amp := 1.0 + RogueRun.stat("calamity_react_pct") / 100.0
	match kind:
		"fire_tornado":
			# 风助火势：引爆点留火龙卷，持续跳火伤并续劫火
			_calamity_spawn_fire_tornado(pos, reaction, base_dmg * react_amp)
		"vortex":
			# 风雷引：留风雷涡，持续把周围敌人吸向中心（不造成伤害）
			_calamity_spawn_wind_vortex(pos, reaction)
		_:
			# 雷火交击：一次性火爆，主目标全伤，周围六成
			var reaction_dmg := base_dmg * float(reaction.get("ratio", 1.0)) * react_amp
			_deal_direct_damage(target, reaction_dmg, "elemental", "fire", "", true, false)
			for raw in _array_enemy_units():
				if raw == target or raw == null or not is_instance_valid(raw) or not (raw is Node2D):
					continue
				if _enemy_is_dead(raw):
					continue
				if (raw as Node2D).global_position.distance_to(pos) > radius + 18.0:
					continue
				_deal_direct_damage(raw, reaction_dmg * 0.6, "elemental", "fire", "", true, false)
	if target is Node2D:
		var reaction_name := String(reaction.get("name", ""))
		var reaction_color: Color = reaction.get("color", Color.WHITE)
		_show_reaction_name(pos, reaction_name, reaction_color)
		SkillFx.calamity_reaction(get_parent(), pos, rid)
		match kind:
			"fire_tornado":
				GameState.play_sfx("attack_hit")
				_screen_shake(3.0, 0.12)
			"vortex":
				GameState.play_sfx("attack_hit")
				_screen_shake(2.0, 0.10)
			_:
				GameState.play_sfx("attack_impact")
				_screen_shake(5.0, 0.16)
				GameState.trigger_hit_stop(0.06)
	return true


## 风助火势的持续段：火龙卷每 0.5 秒跳一次火伤并续劫火；不参与再次引爆。
func _calamity_spawn_fire_tornado(pos: Vector2, reaction: Dictionary, base_dmg: float) -> void:
	var ticks := maxi(1, int(reaction.get("ticks", 6)))
	var interval := maxf(0.1, float(reaction.get("interval", 0.5)))
	var radius := float(reaction.get("radius", 120.0))
	var tick_dmg := base_dmg * float(reaction.get("tick_ratio", 0.30))
	var life := maxf(interval * float(ticks), float(reaction.get("life", 3.0)))
	SkillFx.calamity_fire_tornado(get_parent(), pos, radius, life)
	_calamity_run_fire_tornado(pos, radius, tick_dmg, ticks, interval)


func _calamity_run_fire_tornado(pos: Vector2, radius: float, tick_dmg: float,
		ticks: int, interval: float) -> void:
	for i in range(ticks):
		if i > 0:
			await get_tree().create_timer(interval).timeout
		if not is_instance_valid(self) or is_dead:
			return
		_calamity_damage_circle(pos, radius, tick_dmg, "fire", "jie_huo",
			2.0, false)


## 风雷引的持续段：风雷涡每 0.3 秒把半径内敌人往中心拽一次，不造成伤害。
func _calamity_spawn_wind_vortex(pos: Vector2, reaction: Dictionary) -> void:
	var life := maxf(0.3, float(reaction.get("life", 3.0)))
	var interval := maxf(0.1, float(reaction.get("interval", 0.3)))
	var radius := float(reaction.get("radius", 260.0))
	var pull := float(reaction.get("pull", 150.0))
	SkillFx.calamity_vortex(get_parent(), pos, radius, life)
	_calamity_run_wind_vortex(pos, radius, pull, life, interval)


func _calamity_run_wind_vortex(pos: Vector2, radius: float, pull: float,
		life: float, interval: float) -> void:
	var elapsed := 0.0
	while elapsed < life:
		await get_tree().create_timer(interval).timeout
		if not is_instance_valid(self) or is_dead:
			return
		elapsed += interval
		_calamity_vortex_pull(pos, radius, pull)


func _calamity_vortex_pull(pos: Vector2, radius: float, pull: float) -> void:
	for raw in _array_enemy_units():
		if raw == null or not is_instance_valid(raw) or not (raw is Node2D):
			continue
		if _enemy_is_dead(raw):
			continue
		var unit := raw as Node2D
		var to_center := pos - unit.global_position
		var dist := to_center.length()
		if dist > radius or dist < 16.0:
			continue
		var dir := to_center / dist
		if unit.has_method("take_knockback"):
			unit.call("take_knockback", dir * pull)
		else:
			unit.global_position += dir * minf(12.0, dist * 0.5)


## 灾痕读数：挂在目标头顶，装备 / 未装备被动都显示
func _attach_calamity_marks_if_needed(target: Node, debuff_id: String) -> void:
	if debuff_id == "":
		return
	if target == null or not is_instance_valid(target) or not (target is Node2D):
		return
	if debuff_id in SkillDB.CALAMITY_MARK_IDS:
		CalamityMarkFx.attach(target as Node2D)


## 反应名：比普通飘字更大、带描边，避免被伤害数字淹没
func _show_reaction_name(world_pos: Vector2, text: String, color: Color) -> void:
	if text == "":
		return
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 0.95))
	label.add_theme_constant_override("outline_size", 5)
	label.size = Vector2(220, 34)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 落在目标脚下：避开 BOSS 头顶血条 / 阶段字，反应名不被 UI 盖住
	label.position = world_pos + Vector2(-110, 34)
	label.z_index = 62
	get_parent().add_child(label)
	var tw := label.create_tween()
	tw.tween_property(label, "position:y", label.position.y + 18.0, 0.55)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.55)
	tw.tween_callback(label.queue_free)


func _calamity_damage_circle(pos: Vector2, radius: float, dmg: float,
		elem: String, debuff_id: String = "", debuff_time: float = 0.0,
		allow_reaction: bool = true) -> bool:
	var hit_any := false
	for b in _array_enemy_units():
		if b == null or not is_instance_valid(b) or not (b is Node2D):
			continue
		if (b as Node2D).global_position.distance_to(pos) > radius + 18.0:
			continue
		hit_any = true
		_deal_direct_damage(b, dmg, "elemental", elem, "", true, false)
		if allow_reaction:
			_try_calamity_reaction(b, elem, dmg)
		if debuff_id != "" and b.has_method("apply_debuff"):
			b.call("apply_debuff", debuff_id, debuff_time)
			_attach_calamity_marks_if_needed(b, debuff_id)
	return hit_any


func _calamity_ticks(pos: Vector2, radius: float, dmg: float, elem: String,
		debuff_id: String, debuff_time: float, ticks: int, gap: float,
		lock_boss: bool = false) -> void:
	for i in range(maxi(1, ticks)):
		if i > 0:
			await get_tree().create_timer(maxf(0.05, gap), true, false, true).timeout
		if not is_instance_valid(self) or is_dead:
			return
		# 燎原 / 雷池的跳伤也能引爆灾痕（同一道痕只消耗一次）
		_calamity_damage_circle(pos, radius, dmg, elem, debuff_id, debuff_time, true)
		var boss := _calamity_boss()
		if boss != null:
			_calamity_notify_hit(boss, elem_to_calamity(elem))
			if lock_boss and i == 0:
				if boss.has_method("apply_debuff"):
					boss.call("apply_debuff", "suo_zai", 3.0)
				if boss.has_method("on_calamity_lock"):
					boss.call("on_calamity_lock", 3.0)


func elem_to_calamity(elem: String) -> String:
	match elem:
		"fire":
			return CALAMITY_FIRE
		"thunder":
			return CALAMITY_THUNDER
		_:
			return CALAMITY_WIND


func _cast_calamity_step(form: Dictionary, dir: Vector2) -> void:
	SkillFx.play_at_strike(self, "skill_calamity_step", form, dir, global_position)
	var dmg := CharacterData.calc_skill_damage("skill_calamity_step", true, false) \
		* _calamity_out_mult(CALAMITY_WIND)
	var hit := _damage_bosses_in_shape(dir, 110.0, deg_to_rad(70.0), dmg,
		"physical", "", true, "skill_calamity_step", 0.0, null, CALAMITY_WIND)
	if hit:
		_calamity_notify_hit(_calamity_boss(), CALAMITY_WIND)


func _cast_calamity_slash(form: Dictionary, dir: Vector2) -> void:
	var dmg := CharacterData.calc_skill_damage("skill_calamity_slash", true, false) \
		* _calamity_out_mult(CALAMITY_WIND)
	SkillFx.play_at_strike(self, "skill_calamity_slash", form, dir)
	var hit := _damage_bosses_in_shape(dir, float(form.get("range", 190.0)),
		deg_to_rad(float(form.get("angle", 100.0)) * 0.5), dmg, "physical", "",
		false, "skill_calamity_slash", 0.0, null, CALAMITY_WIND)
	if hit:
		_calamity_notify_hit(_calamity_boss(), CALAMITY_WIND)


func _cast_calamity_fire_seal(form: Dictionary, dir: Vector2) -> void:
	var target := _calamity_target_pos(dir, 260.0)
	var radius := float(form.get("range", 100.0))
	var delay := float(form.get("delay", 0.25))
	var dmg := CharacterData.calc_skill_damage("skill_calamity_fire_seal", true, false) \
		* _calamity_out_mult(CALAMITY_FIRE)
	SkillFx.calamity_warn_at(get_parent(), target, radius, delay,
		Color(1.0, 0.52, 0.18))
	get_tree().create_timer(delay, true, false, true).timeout.connect(
		func() -> void:
			if not is_instance_valid(self) or is_dead:
				return
			SkillFx.play_at_strike(self, "skill_calamity_fire_seal", form,
				Vector2.RIGHT, target)
			_calamity_damage_circle(target, radius, dmg, "fire", "jie_huo",
				float(form.get("debuff_time", 4.0)))
			_calamity_notify_hit(_calamity_boss(), CALAMITY_FIRE))


func _cast_calamity_fire_field(form: Dictionary, dir: Vector2) -> void:
	var target := _calamity_target_pos(dir, 260.0)
	var radius := float(form.get("range", 140.0))
	var dmg := CharacterData.calc_skill_damage("skill_calamity_fire_field", true, false) \
		* _calamity_out_mult(CALAMITY_FIRE)
	SkillFx.play_at_strike(self, "skill_calamity_fire_field", form, dir, target)
	_calamity_ticks(target, radius, dmg, "fire", "jie_huo",
		float(form.get("debuff_time", 3.0)), int(form.get("player_ticks", 3)),
		float(form.get("player_tick_interval", 1.5)))


func _cast_calamity_thunder_strike(form: Dictionary, dir: Vector2) -> void:
	var target := _calamity_target_pos(dir, 300.0)
	var radius := float(form.get("range", 120.0))
	var delay := float(form.get("delay", 0.35))
	var dmg := CharacterData.calc_skill_damage("skill_calamity_thunder_strike", true, false) \
		* _calamity_out_mult(CALAMITY_THUNDER)
	SkillFx.calamity_warn_at(get_parent(), target, radius, delay,
		Color(0.72, 0.64, 1.0))
	get_tree().create_timer(delay, true, false, true).timeout.connect(
		func() -> void:
			if not is_instance_valid(self) or is_dead:
				return
			SkillFx.play_at_strike(self, "skill_calamity_thunder_strike", form,
				Vector2.RIGHT, target)
			_calamity_damage_circle(target, radius, dmg, "thunder", "gan_dian",
				float(form.get("debuff_time", 3.0)))
			_calamity_notify_hit(_calamity_boss(), CALAMITY_THUNDER))


func _cast_calamity_thunder_pool(form: Dictionary, dir: Vector2) -> void:
	var target := _calamity_target_pos(dir, 300.0)
	var radius := float(form.get("range", 150.0))
	var dmg := CharacterData.calc_skill_damage("skill_calamity_thunder_pool", true, false) \
		* _calamity_out_mult(CALAMITY_THUNDER)
	SkillFx.play_at_strike(self, "skill_calamity_thunder_pool", form, dir, target)
	_calamity_ticks(target, radius, dmg, "thunder", "gan_dian",
		float(form.get("debuff_time", 3.0)), int(form.get("player_ticks", 4)),
		float(form.get("player_tick_interval", 1.0)), true)


func _cast_calamity_turn(form: Dictionary, dir: Vector2) -> void:
	SkillFx.play_at_strike(self, "skill_calamity_turn", form, dir)
	var dmg := CharacterData.calc_skill_damage("skill_calamity_turn", true, false)
	var no_passive := not _calamity_passive_on
	# 未装备被动：轮转改为风环，给命中目标上风蚀并引爆劫火；不再发无效的灾替
	var elem := calamity_element if calamity_element != "" else CALAMITY_WIND
	_calamity_damage_circle(global_position, float(form.get("range", 120.0)), dmg,
		elem, "feng_shi" if no_passive else "", 4.0)
	# 肉鸽「天轮」：轮转不消耗灵力（把这一发的灵力退回来，主模式 stat 恒 0）
	if RogueRun.stat("calamity_turn_free") > 0.0:
		var turn_cost := SkillDB.get_skill_cost("skill_calamity_turn")
		mana = minf(max_mana, mana + float(turn_cost.get("mana_cost", 0.0)))
		_update_mana_bar()
	if not no_passive:
		apply_buff("sanzai_guard", float(form.get("windup", 0.22)) + 1.5)
		var next := _calamity_next(calamity_element)
		_calamity_set_element(next, true)
		_show_float_text("三灾轮转 · %s" % _calamity_name(next), Color(0.86, 0.82, 0.72))


func _cast_calamity_final(form: Dictionary, dir: Vector2) -> void:
	var target := _calamity_target_pos(dir, 300.0)
	var radius := float(form.get("range", 200.0))
	var delay := float(form.get("delay", 0.45))
	var stacks := calamity_momentum
	var elem_tag := calamity_element if calamity_element != "" else CALAMITY_FIRE
	if calamity_element == "":
		_calamity_set_element(CALAMITY_FIRE, false)
	var base := CharacterData.calc_skill_damage("skill_calamity_final", true, false)
	var dmg := base * ((1.6 + 0.5 * float(stacks)) / 1.6)
	dmg *= _calamity_out_mult(elem_tag)
	# 肉鸽「万劫·烈」：万劫归一整体伤害（主模式 stat 恒 0）
	dmg *= 1.0 + RogueRun.stat("calamity_final_pct") / 100.0
	calamity_momentum = 0
	_refresh_calamity_hud()
	SkillFx.calamity_warn_at(get_parent(), target, radius, delay,
		Color(0.92, 0.80, 0.58))
	get_tree().create_timer(delay, true, false, true).timeout.connect(
		func() -> void:
			if not is_instance_valid(self) or is_dead:
				return
			SkillFx.play_at_strike(self, "skill_calamity_final", form,
				Vector2.RIGHT, target)
			_calamity_damage_circle(target, radius, dmg,
				"thunder" if elem_tag == CALAMITY_THUNDER else ("fire" if elem_tag == CALAMITY_FIRE else "wind"),
				"zai_beng", float(form.get("debuff_time", 3.0)))
			_rogue_calamity_final_extras(target, radius)
			_calamity_notify_hit(_calamity_boss(), elem_tag))


## 肉鸽三灾：万劫归一命中后的补痕与回灵（主模式整段早退）
func _rogue_calamity_final_extras(center: Vector2, radius: float) -> void:
	if not RogueRun.active:
		return
	var mana_back := RogueRun.stat("calamity_final_mana")
	if mana_back > 0.0 and mana < max_mana:
		mana = minf(max_mana, mana + mana_back)
		_update_mana_bar()
	if not RogueRun.has_flag("calamity_final_marks"):
		return
	for raw in _array_enemy_units():
		if not is_instance_valid(raw) or not (raw is Node2D):
			continue
		if (raw as Node2D).global_position.distance_to(center) > radius + 40.0:
			continue
		if not raw.has_method("apply_debuff"):
			continue
		for mark in SkillDB.CALAMITY_MARK_IDS:
			raw.call("apply_debuff", String(mark), 4.0)
			_attach_calamity_marks_if_needed(raw, String(mark))


func _calamity_target_pos(dir: Vector2, fallback: float) -> Vector2:
	# 三灾需要瞄准任何可命中的敌人（不止晏无咎），否则普通 BOSS / 演武木桩会落空
	var boss := _nearest_boss(10000.0)
	if boss != null:
		return _boss_aim_point(boss)
	return global_position + dir.normalized() * fallback


func _calamity_name(element: String) -> String:
	match element:
		CALAMITY_WIND:
			return "风灾"
		CALAMITY_FIRE:
			return "火灾"
		CALAMITY_THUNDER:
			return "雷灾"
	return "未定"


func calamity_state() -> String:
	return calamity_element


## BOSS 的克制灾位打到玩家时先问伤害倍率；这里**不落任何副作用**。
## 真正的灾替 / 锁灾 / 灾势 -1 由 apply_calamity_break() 在确认伤害落地后调用，
## 否则闪掉的那一下也会白吃锁灾、白烧灾替。
func calamity_incoming_multiplier(attacker_calamity: String) -> float:
	if not _calamity_passive_on or calamity_element == "" \
			or attacker_calamity == "" or attacker_calamity == "fusion":
		return 1.0
	if not _calamity_beats(attacker_calamity, calamity_element):
		return 1.0
	if has_buff("sanzai_guard") or _calamity_break_cd > 0.0:
		return 1.0
	return 1.15


## 伤害真正落地后由 BOSS 调用：处理灾替 / 被破灾 / 锁灾。
func apply_calamity_break(attacker_calamity: String) -> void:
	if not _calamity_passive_on or calamity_element == "" \
			or attacker_calamity == "" or attacker_calamity == "fusion":
		return
	if not _calamity_beats(attacker_calamity, calamity_element):
		return
	if has_buff("sanzai_guard"):
		remove_buff("sanzai_guard")
		_calamity_add_momentum(1)
		_show_float_text("灾替 · 免破", Color(0.92, 0.80, 0.46))
		return
	if _calamity_break_cd > 0.0:
		return
	_calamity_break_cd = 1.2
	calamity_momentum = maxi(0, calamity_momentum - 1)
	apply_debuff("suo_zai", 2.0, true)
	_show_float_text("灾位被破 · 锁灾", UIKit.C_FLOAT_WARN)
	_refresh_calamity_hud()


## 三元轮：风 / 火 / 雷三炁环身，轮转打击身周敌人。
## 通用主动法宝：不读灾位、不要求 BOSS 功法，任何战斗都能用。
func _start_tri_ring_treasure(item: Dictionary, tpl: Dictionary) -> void:
	if _tri_ring_left > 0.0:
		_show_float_text("法宝正在生效", Color(1.0, 0.92, 0.6))
		return
	var tid := String(tpl.get("treasure_id", ""))
	var left := summon_cooldown_left(tid)
	if left > 0.0:
		_show_float_text("法宝冷却中（%.0f 秒）" % left, Color(0.85, 0.6, 0.35))
		return
	var stats := ItemDB.treasure_active_stats(item, tpl)
	if stats.is_empty():
		return
	var cost := float(stats.get("mana", 20.0))
	if mana < cost:
		_show_float_text("灵力不足（三元轮需要 %d 点）" % int(round(cost)),
			UIKit.C_FLOAT_WARN)
		return
	if not spend_mana(cost):
		return
	_tri_ring_id = tid
	_tri_ring_left = float(stats.get("duration", 8.0))
	_tri_ring_tick = 0.0
	_tri_ring_index = 0
	_tri_ring_radius = float(stats.get("radius", 240.0))
	_tri_ring_interval = maxf(0.5, float(stats.get("interval", 1.0)))
	_tri_ring_ratio = float(stats.get("ratio", 0.65))
	_summon_cooldowns[tid] = float(stats.get("cooldown", 40.0))
	_tri_ring_fx = TreasureFx.attach_tri_ring(self, _body_center(), _tri_ring_left)
	_show_float_text("三元轮 · 三炁环身", TreasureFx.TRI_RING_COLOR)
	_tri_ring_pulse()
	_tri_ring_tick = _tri_ring_interval


func _tick_tri_ring(delta: float) -> void:
	if _tri_ring_left <= 0.0:
		return
	_tri_ring_left = maxf(0.0, _tri_ring_left - delta)
	if _tri_ring_left <= 0.0:
		_stop_tri_ring()
		return
	_tri_ring_tick -= delta
	while _tri_ring_tick <= 0.0 and _tri_ring_left > 0.0:
		_tri_ring_tick += _tri_ring_interval
		_tri_ring_pulse()


func _tri_ring_pulse() -> void:
	if is_dead:
		return
	var elements: Array[String] = ["wind", "fire", "thunder"]
	var elem := elements[_tri_ring_index % elements.size()]
	_tri_ring_index += 1
	var dmg := CharacterData.spell_attack() * _tri_ring_ratio
	var hit_any := false
	for raw in _array_enemy_units():
		var b := raw as Node2D
		if b == null or not is_instance_valid(b):
			continue
		if b.global_position.distance_to(global_position) > _tri_ring_radius + 18.0:
			continue
		_deal_direct_damage(b, dmg, "elemental", elem, "")
		if b.has_method("apply_debuff"):
			match elem:
				"wind":
					b.call("apply_debuff", "tri_wind_bind", 1.5)
				"fire":
					b.call("apply_debuff", "jie_huo", 2.0)
				"thunder":
					b.call("apply_debuff", "gan_dian", 1.5)
		hit_any = true
	if hit_any:
		GameState.trigger_hit_stop(0.035)
	SkillFx.tri_ring_pulse(get_parent(), global_position + _body_center(),
		_tri_ring_radius, TreasureFx.tri_ring_color(elem))


func _stop_tri_ring() -> void:
	_tri_ring_id = ""
	_tri_ring_left = 0.0
	_tri_ring_tick = 0.0
	if is_instance_valid(_tri_ring_fx):
		_tri_ring_fx.queue_free()
	_tri_ring_fx = null


# ===================== 野修法宝第二组（2026-11-01）=====================

## 主动法宝的敌方目标：排除友军召唤物与已死亡单位
func _treasure_enemy_target(max_dist: float) -> Node2D:
	var nearest: Node2D = null
	var best := max_dist
	for raw in _treasure_enemy_units(max_dist):
		var b := raw as Node2D
		var d := global_position.distance_to(b.global_position)
		if d < best:
			best = d
			nearest = b
	return nearest


## 主动法宝的范围内敌方单位（排除友军召唤物与死亡单位）
func _treasure_enemy_units(radius: float) -> Array:
	var out: Array = []
	for raw in get_tree().get_nodes_in_group("boss"):
		# ⚠ 死单位不参与索敌 / 结算：试炼里 BOSS 尸体不销毁、仍在 "boss" 组
		if BossBase.is_unit_dead(raw):
			continue
		if not is_instance_valid(raw) or not raw is Node2D:
			continue
		var b := raw as Node2D
		if BossBase.is_ally_unit(b):
			continue
		if b.has_method("is_dead") and bool(b.call("is_dead")):
			continue
		if global_position.distance_to(b.global_position) > radius:
			continue
		out.append(b)
	return out


## 断念铃：即时封技；打断前摇返还灵力。
func _start_mind_lock_treasure(item: Dictionary, tpl: Dictionary) -> void:
	var tid := String(tpl.get("treasure_id", ""))
	var left := summon_cooldown_left(tid)
	if left > 0.0:
		_show_float_text("法宝冷却中（%.0f 秒）" % left, Color(0.85, 0.6, 0.35))
		return
	var stats := ItemDB.treasure_active_stats(item, tpl)
	if stats.is_empty():
		return
	var reach := float(stats.get("range", 300.0))
	var target := _treasure_enemy_target(reach)
	if target == null:
		_show_float_text("断念铃：范围内没有目标", Color(0.7, 0.7, 0.75))
		return
	if target.has_method("is_treasure_bell_immune") \
			and bool(target.call("is_treasure_bell_immune")):
		_show_float_text("断念抗性中", Color(0.74, 0.62, 0.98))
		return
	var cost := float(stats.get("mana", 20.0))
	if mana < cost:
		_show_float_text("灵力不足（断念铃需要 %d 点）" % int(round(cost)),
			UIKit.C_FLOAT_WARN)
		return
	if not spend_mana(cost):
		return
	_summon_cooldowns[tid] = float(stats.get("cooldown", 35.0))
	var silence := float(stats.get("silence", 1.8))
	# 打断判定要在 apply_skill_lock 之前读 —— 那个函数会把 WINDUP 直接取消
	var target_state = target.get("state")
	var was_winding := target_state != null \
		and int(target_state) == int(BossBase.BossState.WINDUP)
	if target.has_method("apply_debuff"):
		target.call("apply_debuff", "duannian", silence)
	if target.has_method("apply_skill_lock"):
		target.call("apply_skill_lock", silence)
	if target.has_method("mark_treasure_bell_immune"):
		target.call("mark_treasure_bell_immune", 8.0)
	TreasureFx.play_bell_ring(self, _body_center(), reach, DebuffDB.color("duannian"))
	var refund := float(stats.get("refund", 10.0))
	if was_winding:
		mana = minf(max_mana, mana + refund)
		# 迟照符：成功打断 BOSS 起手也算一次操作抹账
		_reckoning_on_wipe()
		_show_float_text("断念 · 断招（返还 %d 灵力）" % int(round(refund)),
			Color(0.86, 0.78, 1.0))
	else:
		_show_float_text("断念铃 · 封技 %s 秒" % _fmt_sec(silence),
			DebuffDB.color("duannian"))


## 禁步桩：在目标脚下埋桩，0.8 秒后展开。
func _start_stake_treasure(item: Dictionary, tpl: Dictionary) -> void:
	var tid := String(tpl.get("treasure_id", ""))
	var left := summon_cooldown_left(tid)
	if left > 0.0:
		_show_float_text("法宝冷却中（%.0f 秒）" % left, Color(0.85, 0.6, 0.35))
		return
	var stats := ItemDB.treasure_active_stats(item, tpl)
	if stats.is_empty():
		return
	var cost := float(stats.get("mana", 15.0))
	if mana < cost:
		_show_float_text("灵力不足（禁步桩需要 %d 点）" % int(round(cost)),
			UIKit.C_FLOAT_WARN)
		return
	if not spend_mana(cost):
		return
	_summon_cooldowns[tid] = float(stats.get("cooldown", 28.0))
	var target := _treasure_enemy_target(float(stats.get("range", 300.0)))
	var pos := target.global_position if target != null else global_position
	if is_instance_valid(_stake_field):
		_stake_field.queue_free()
	_stake_field = TreasureStakeField.new()
	_stake_field.setup(pos, true,
		float(stats.get("radius", 110.0)),
		float(stats.get("arm_time", 0.8)),
		float(stats.get("duration", 4.0)),
		float(stats.get("initial_slow", 1.5)),
		float(stats.get("slow_mult", 0.65)),
		float(stats.get("slow_refresh", 0.6)),
		String(tpl.get("icon", "")))
	get_parent().add_child(_stake_field)
	_stake_id = tid
	_stake_left = float(stats.get("arm_time", 0.8)) + float(stats.get("duration", 4.0))
	_show_float_text("禁步桩 · 画地为牢", DebuffDB.color("jinbu"))


func _tick_stake_treasure(delta: float) -> void:
	if _stake_left > 0.0:
		_stake_left = maxf(0.0, _stake_left - delta)
		if _stake_left <= 0.0:
			_stake_id = ""
	if _stake_id != "" and not is_instance_valid(_stake_field):
		_stake_id = ""
		_stake_left = 0.0


## 续命灯：提前点亮 10 秒，第一次致死改判。
func _start_lamp_treasure(item: Dictionary, tpl: Dictionary) -> void:
	if _lamp_left > 0.0:
		_show_float_text("续命灯还亮着", Color(1.0, 0.92, 0.6))
		return
	var tid := String(tpl.get("treasure_id", ""))
	var left := summon_cooldown_left(tid)
	if left > 0.0:
		_show_float_text("法宝冷却中（%.0f 秒）" % left, Color(0.85, 0.6, 0.35))
		return
	var stats := ItemDB.treasure_active_stats(item, tpl)
	if stats.is_empty():
		return
	var cost := float(stats.get("mana", 25.0))
	if mana < cost:
		_show_float_text("灵力不足（续命灯需要 %d 点）" % int(round(cost)),
			UIKit.C_FLOAT_WARN)
		return
	if not spend_mana(cost):
		return
	_summon_cooldowns[tid] = float(stats.get("cooldown", 60.0))
	_lamp_id = tid
	_lamp_left = float(stats.get("duration", 10.0))
	_lamp_heal_left = 0.0
	_lamp_heal_rate = 0.0
	_lamp_heal_ratio = float(stats.get("heal_ratio", 0.15))
	_lamp_invuln = float(stats.get("invuln", 0.8))
	_lamp_knockback = float(stats.get("knockback_radius", 200.0))
	apply_buff("xuming", _lamp_left)
	if is_instance_valid(_lamp_fx):
		_lamp_fx.queue_free()
	_lamp_fx = TreasureFx.attach_lamp(self, _body_center(), _lamp_left)
	_show_float_text("续命灯 · 十息内替死", Color(1.0, 0.86, 0.46))


func _tick_lamp_treasure(delta: float) -> void:
	# 触发后的 1 秒回血（即使灯已经灭了也继续走完）
	if _lamp_heal_left > 0.0:
		var step := minf(delta, _lamp_heal_left)
		_lamp_heal_left -= step
		if not is_dead and _lamp_heal_rate > 0.0:
			var healed := restore_health(_lamp_heal_rate * step)
			if healed > 0.0:
				_update_health_bar()
	if _lamp_left <= 0.0:
		return
	_lamp_left = maxf(0.0, _lamp_left - delta)
	if _lamp_left <= 0.0:
		_stop_lamp_treasure()


## 致死改判：留 1 点气血，1 秒内回复，短暂无敌并击退身周敌人
func _trigger_lamp_save() -> void:
	var heal_ratio := _lamp_heal_ratio
	_lamp_left = 0.0
	_lamp_id = ""
	remove_buff("xuming")
	_lamp_heal_left = 1.0
	_lamp_heal_rate = max_hp * heal_ratio
	invincible_timer = maxf(invincible_timer, _lamp_invuln)
	if is_instance_valid(_lamp_fx):
		_lamp_fx.queue_free()
	_lamp_fx = null
	TreasureFx.play_lamp_break(self, _body_center())
	# 击退：只推不伤，留出 1 秒回血窗口
	for raw in _array_enemy_units():
		if not is_instance_valid(raw) or not raw is Node2D:
			continue
		var b := raw as Node2D
		if global_position.distance_to(b.global_position) > _lamp_knockback:
			continue
		if b.has_method("take_knockback"):
			var dir: Vector2 = (b.global_position - global_position)
			if dir.length_squared() > 0.0001:
				b.call("take_knockback", dir.normalized() * 280.0)
	_show_float_text("灯替一死", Color(1.0, 0.88, 0.50))


func _stop_lamp_treasure() -> void:
	_lamp_id = ""
	_lamp_left = 0.0
	remove_buff("xuming")
	if is_instance_valid(_lamp_fx):
		_lamp_fx.queue_free()
	_lamp_fx = null


## 蚀甲锥：掷出锥子，命中后挂蚀甲。
func _start_corrode_treasure(item: Dictionary, tpl: Dictionary) -> void:
	var tid := String(tpl.get("treasure_id", ""))
	var left := summon_cooldown_left(tid)
	if left > 0.0:
		_show_float_text("法宝冷却中（%.0f 秒）" % left, Color(0.85, 0.6, 0.35))
		return
	var stats := ItemDB.treasure_active_stats(item, tpl)
	if stats.is_empty():
		return
	var target := _treasure_enemy_target(float(stats.get("range", 400.0)))
	if target == null:
		_show_float_text("蚀甲锥：范围内没有目标", Color(0.7, 0.7, 0.75))
		return
	var cost := float(stats.get("mana", 15.0))
	if mana < cost:
		_show_float_text("灵力不足（蚀甲锥需要 %d 点）" % int(round(cost)),
			UIKit.C_FLOAT_WARN)
		return
	if not spend_mana(cost):
		return
	_summon_cooldowns[tid] = float(stats.get("cooldown", 30.0))
	# 锥子的判定是一根「身体立柱」(26×104，中心抬到腰高)，逐帧形状查询补一次：
	# 只按脚底高度的小圆会擦过木桩 / 贴脚底的碰撞体，见 treasure_cone.gd
	var dir := target.global_position - global_position
	if dir.length_squared() < 0.0001:
		dir = attack_dir
	dir = dir.normalized()
	var cone := TreasureCone.new()
	cone.setup(self, "boss", dir, float(stats.get("speed", 900.0)),
		float(stats.get("range", 400.0)), "shixi",
		float(stats.get("duration", 8.0)), String(tpl.get("icon", "")))
	get_parent().add_child(cone)
	cone.global_position = global_position + dir * 26.0
	_show_float_text("蚀甲锥", DebuffDB.color("shixi"))


## 血饲印：以最大气血换功法冷却与灵力。
func _start_blood_seal_treasure(item: Dictionary, tpl: Dictionary) -> void:
	var tid := String(tpl.get("treasure_id", ""))
	var left := summon_cooldown_left(tid)
	if left > 0.0:
		_show_float_text("法宝冷却中（%.0f 秒）" % left, Color(0.85, 0.6, 0.35))
		return
	var stats := ItemDB.treasure_active_stats(item, tpl)
	if stats.is_empty():
		return
	var min_hp := max_hp * float(stats.get("min_hp_ratio", 0.25))
	if hp <= min_hp:
		_show_float_text("气血过低，无法血饲", UIKit.C_FLOAT_WARN)
		return
	_summon_cooldowns[tid] = float(stats.get("cooldown", 60.0))
	var cost_hp := max_hp * float(stats.get("hp_ratio", 0.15))
	hp = maxf(1.0, hp - cost_hp)
	health_changed.emit(hp, max_hp)
	_update_health_bar()
	skill_cooldowns.clear()
	mana = minf(max_mana, mana + max_mana * float(stats.get("mana_restore", 0.30)))
	_update_mana_bar()
	TreasureFx.play_blood_seal(self, _body_center())
	_show_float_text("血饲印 · 功法冷却已清　气血 -%d" % int(round(cost_hp)),
		Color(0.86, 0.32, 0.28))


## 换位玦：与目标互换位置，落地短暂无敌。
func _start_swap_treasure(item: Dictionary, tpl: Dictionary) -> void:
	var tid := String(tpl.get("treasure_id", ""))
	var left := summon_cooldown_left(tid)
	if left > 0.0:
		_show_float_text("法宝冷却中（%.0f 秒）" % left, Color(0.85, 0.6, 0.35))
		return
	var stats := ItemDB.treasure_active_stats(item, tpl)
	if stats.is_empty():
		return
	var target := _treasure_enemy_target(float(stats.get("range", 360.0)))
	if target == null:
		_show_float_text("换位玦：范围内没有目标", Color(0.7, 0.7, 0.75))
		return
	var cost := float(stats.get("mana", 20.0))
	if mana < cost:
		_show_float_text("灵力不足（换位玦需要 %d 点）" % int(round(cost)),
			UIKit.C_FLOAT_WARN)
		return
	if not spend_mana(cost):
		return
	_summon_cooldowns[tid] = float(stats.get("cooldown", 45.0))
	var my_pos := global_position
	var target_pos := target.global_position
	target.global_position = my_pos
	global_position = target_pos
	if target.has_method("_clamp_to_arena"):
		target.call("_clamp_to_arena")
	invincible_timer = maxf(invincible_timer, float(stats.get("invuln", 0.4)))
	TreasureFx.play_swap(get_parent(), my_pos, target_pos)
	_show_float_text("换位玦", Color(0.56, 0.86, 0.78))


## 棘甲佩：4 秒近战反伤。
func _start_thorns_treasure(item: Dictionary, tpl: Dictionary) -> void:
	if _thorns_left > 0.0:
		_show_float_text("棘甲还在", Color(0.92, 0.46, 0.38))
		return
	var tid := String(tpl.get("treasure_id", ""))
	var left := summon_cooldown_left(tid)
	if left > 0.0:
		_show_float_text("法宝冷却中（%.0f 秒）" % left, Color(0.85, 0.6, 0.35))
		return
	var stats := ItemDB.treasure_active_stats(item, tpl)
	if stats.is_empty():
		return
	var cost := float(stats.get("mana", 15.0))
	if mana < cost:
		_show_float_text("灵力不足（棘甲佩需要 %d 点）" % int(round(cost)),
			UIKit.C_FLOAT_WARN)
		return
	if not spend_mana(cost):
		return
	_summon_cooldowns[tid] = float(stats.get("cooldown", 35.0))
	_thorns_id = tid
	_thorns_left = float(stats.get("duration", 4.0))
	_thorns_ratio = float(stats.get("reflect_ratio", 0.30))
	apply_buff("jijia", _thorns_left)
	_thorns_fx = TreasureFx.attach_thorns(self, _body_center(), _thorns_left)
	_show_float_text("棘甲佩 · 近战反伤 %d%%" % int(round(_thorns_ratio * 100.0)),
		Color(0.92, 0.46, 0.38))


func _tick_thorns_treasure(delta: float) -> void:
	if _thorns_left <= 0.0:
		return
	_thorns_left = maxf(0.0, _thorns_left - delta)
	if _thorns_left <= 0.0:
		_stop_thorns_treasure()


func _stop_thorns_treasure() -> void:
	_thorns_id = ""
	_thorns_left = 0.0
	_thorns_ratio = 0.0
	remove_buff("jijia")
	if is_instance_valid(_thorns_fx):
		_thorns_fx.queue_free()
	_thorns_fx = null


func thorns_left(treasure_id: String) -> float:
	if _thorns_id != treasure_id:
		return 0.0
	return maxf(0.0, _thorns_left)


## 回风袋：把身周敌人推开。
func _start_gust_treasure(item: Dictionary, tpl: Dictionary) -> void:
	var tid := String(tpl.get("treasure_id", ""))
	var left := summon_cooldown_left(tid)
	if left > 0.0:
		_show_float_text("法宝冷却中（%.0f 秒）" % left, Color(0.85, 0.6, 0.35))
		return
	var stats := ItemDB.treasure_active_stats(item, tpl)
	if stats.is_empty():
		return
	var cost := float(stats.get("mana", 15.0))
	if mana < cost:
		_show_float_text("灵力不足（回风袋需要 %d 点）" % int(round(cost)),
			UIKit.C_FLOAT_WARN)
		return
	if not spend_mana(cost):
		return
	_summon_cooldowns[tid] = float(stats.get("cooldown", 30.0))
	var radius := float(stats.get("radius", 220.0))
	var push := float(stats.get("push", 240.0))
	for raw in _treasure_enemy_units(radius):
		var b := raw as Node2D
		if not b.has_method("take_knockback"):
			continue
		var dir := b.global_position - global_position
		if dir.length_squared() <= 0.0001:
			continue
		b.call("take_knockback", dir.normalized() * push)
	TreasureFx.play_gust(self, _body_center(), radius)
	_show_float_text("回风袋 · 推开 %d" % int(round(push)), Color(0.64, 0.86, 0.84))


func _fmt_sec(value: float) -> String:
	return "%d" % int(round(value)) if is_zero_approx(value - roundf(value)) else "%.1f" % value


## 断念铃 / 禁步桩的目标侧抗性（玩家被野修命中时也要防连锁）
func is_treasure_bell_immune() -> bool:
	return _treasure_bell_immune_left > 0.0


func mark_treasure_bell_immune(seconds: float) -> void:
	_treasure_bell_immune_left = maxf(_treasure_bell_immune_left, seconds)


## 当前身上最高的护体削减（蚀甲锥）
func debuff_guard_shred() -> float:
	var s := 0.0
	for id in debuffs.keys():
		s = maxf(s, float(DebuffDB.get_debuff(String(id)).get("guard_shred", 0.0)))
	return clampf(s, 0.0, 1.0)


func stake_left(treasure_id: String) -> float:
	if _stake_id != treasure_id:
		return 0.0
	return maxf(0.0, _stake_left)


func lamp_left(treasure_id: String) -> float:
	if _lamp_id != treasure_id:
		return 0.0
	return maxf(0.0, _lamp_left)


func _spawn_player_sun_seed(pos: Vector2) -> SunSeed:
	if _find_sun_seed() != null:
		return null
	var seed := SunSeed.new()
	get_parent().add_child(seed)
	seed.global_position = pos
	seed.set_claim_lock(0.8)
	if not seed.consumed.is_connected(_on_sun_bearer_seed_consumed):
		seed.consumed.connect(_on_sun_bearer_seed_consumed)
	_sun_seed = seed
	_refresh_sun_hud()
	return seed


func _sun_precast(skill_id: String, _dir: Vector2) -> void:
	if not skill_id.begins_with("skill_sun_"):
		return
	if not _sun_unlocked:
		_refresh_sun_unlock()
	if not _sun_unlocked:
		return
	var form := SkillDB.get_skill_form(skill_id)
	var title := SkillDB.get_skill_name(skill_id)
	var extra := ""
	match skill_id:
		"skill_sun_throw":
			extra = " —— 火种脱手！"
		"skill_sun_pull":
			extra = " —— 把火种拉回来！"
		"skill_sun_eclipse":
			extra = " —— 离开落点！"
		"skill_sun_meteor":
			extra = " —— 离开落点！"
	_show_skill_name(title + extra, float(form.get("windup", 0.2)) + 0.25,
		Color(1.0, 0.72, 0.28))


## 逐日八式：true = 已处理完，不再走通用伤害路径
func _sun_handle_cast(skill_id: String, dir: Vector2) -> bool:
	if not skill_id.begins_with("skill_sun_"):
		return false
	if not _sun_unlocked:
		_refresh_sun_unlock()
	if not _sun_unlocked:
		return false
	var form := SkillDB.get_skill_form(skill_id)
	if form.is_empty():
		return false
	_sun_seed = _find_sun_seed()
	match skill_id:
		"skill_sun_step":
			_cast_sun_step(form, dir)
			return true
		"skill_sun_slash":
			_cast_sun_slash(form, dir)
			return true
		"skill_sun_throw":
			_cast_sun_throw(form)
			return true
		"skill_sun_pull":
			_cast_sun_pull(form, dir)
			return true
		"skill_sun_wind":
			_cast_sun_wind(form, dir)
			return true
		"skill_sun_eclipse":
			_cast_sun_eclipse(form, dir)
			return true
		"skill_sun_meteor":
			_cast_sun_meteor(form, dir)
			return true
	return false


## 逐日步方向：有输入跟输入；无输入时朝火种（火种在身上则朝 BOSS）。
func _sun_step_dir(wanted: Vector2, fallback: Vector2) -> Vector2:
	if wanted.length_squared() > 0.0001:
		return wanted.normalized()
	var seed := _find_sun_seed()
	if seed != null and is_instance_valid(seed) and seed.state != SunSeed.State.GONE \
			and not seed.is_held_by(self):
		var to_seed := seed.global_position - global_position
		if to_seed.length_squared() > 0.0001:
			return to_seed.normalized()
	var boss := _nearest_boss(100000.0)
	if boss != null:
		var to_boss := _boss_aim_point(boss) - global_position
		if to_boss.length_squared() > 0.0001:
			return to_boss.normalized()
	return fallback


func _cast_sun_step(form: Dictionary, dir: Vector2) -> void:
	SkillFx.play_at_strike(self, "skill_sun_step", form, dir, global_position)
	var dmg := CharacterData.calc_skill_damage("skill_sun_step", true, false)
	var connected := _damage_bosses_in_shape(dir, float(form.get("range", 110.0)),
		deg_to_rad(70.0), dmg, "physical", "", true, "skill_sun_step")
	var seed := _sun_seed
	var steal_reach := float(form.get("steal_range", 130.0))
	if seed != null and is_instance_valid(seed):
		if seed.is_free() and global_position.distance_to(seed.global_position) <= 120.0:
			seed.pickup(self)
		elif connected and seed.holder != null and is_instance_valid(seed.holder) \
				and seed.holder.is_in_group("boss") \
				and global_position.distance_to((seed.holder as Node2D).global_position) <= steal_reach:
			seed.steal_by(self)


func _cast_sun_slash(form: Dictionary, dir: Vector2) -> void:
	var holding := _sun_holding()
	var mult := 1.0
	if holding:
		mult += float(form.get("seed_bonus", 0.20)) \
			+ float(form.get("stack_bonus", 0.15)) * float(sun_stacks)
	var dmg := CharacterData.calc_skill_damage("skill_sun_slash", true, false) * mult
	SkillFx.play_at_strike(self, "skill_sun_slash", form, dir)
	var slashed := _damage_bosses_in_shape(dir, float(form.get("range", 190.0)),
		deg_to_rad(float(form.get("angle", 110.0)) * 0.5), dmg,
		"elemental", "fire", false, "skill_sun_slash" if holding else "")
	# 肉鸽「日进」：日冕斩命中接着补柴（未满层才加，函数内部自己判）
	if slashed and RogueRun.has_flag("sun_hit_stack"):
		_rogue_gain_sun_stack()


func _cast_sun_throw(form: Dictionary) -> void:
	var target := _nearest_boss(520.0)
	if target == null:
		return
	var seed := _sun_seed
	var has_seed := seed != null and is_instance_valid(seed) and seed.is_held_by(self)
	var coeff := 1.0 if has_seed else float(form.get("no_seed_coeff", 0.65))
	var radius := float(form.get("blast_radius", 100.0))
	if not has_seed:
		radius = float(form.get("no_seed_blast_radius", 90.0))
	var dmg := CharacterData.calc_skill_damage("skill_sun_throw", true, false) * coeff
	var pos := target.global_position
	if has_seed:
		var dist := global_position.distance_to(pos)
		var fly_time := clampf(dist / 1400.0, 0.18, 0.32)
		seed.fly_to(pos, fly_time, clampf(dist * 0.10, 18.0, 48.0))
		SkillFx.sun_tether(get_parent(), global_position, pos, Color(1.0, 0.62, 0.22), fly_time)
		get_tree().create_timer(fly_time, true, false, true).timeout.connect(
			func() -> void:
				if not is_instance_valid(self) or is_dead:
					return
				SkillFx.play_at_strike(self, "skill_sun_throw", form, Vector2.RIGHT, pos)
				_sun_throw_hit(pos, radius, dmg))
	else:
		# 无种基础版：掷一团余烬，不再要求先拿到火种
		SkillFx.play_at_strike(self, "skill_sun_throw", form, Vector2.RIGHT, pos)
		_sun_throw_hit(pos, radius, dmg)


func _cast_sun_pull(form: Dictionary, dir: Vector2) -> void:
	var seed := _sun_seed
	var target := _nearest_boss(520.0)
	var can_pull := seed != null and is_instance_valid(seed) and not seed.is_held_by(self)
	if can_pull:
		can_pull = global_position.distance_to(seed.global_position) <= float(form.get("steal_range", 420.0))
	# 对手手里的种要这一发金丝真的扫到它：按 LINE 形态的宽 50 做走廊判定
	if can_pull and seed.holder != null and is_instance_valid(seed.holder) \
			and seed.holder.is_in_group("boss"):
		var aim := dir.normalized() if dir.length_squared() > 0.0001 else facing_dir_to(seed.global_position)
		var line_end := global_position + aim * float(form.get("steal_range", 420.0))
		var half_w := float(form.get("width", 50.0)) * 0.5 + 18.0
		if _array_point_segment_distance((seed.holder as Node2D).global_position,
				global_position, line_end) > half_w:
			can_pull = false
			_show_float_text("没拉住！", UIKit.C_FLOAT_WARN)
	var dmg := CharacterData.calc_skill_damage("skill_sun_pull", true, false)
	if can_pull:
		SkillFx.sun_tether(get_parent(), seed.global_position, global_position,
			Color(1.0, 0.72, 0.30), 0.30)
		SkillFx.play_at_strike(self, "skill_sun_pull", form,
			facing_dir_to(seed.global_position))
		get_tree().create_timer(0.20, true, false, true).timeout.connect(
			func() -> void:
				if not is_instance_valid(self) or is_dead:
					return
				if is_instance_valid(seed):
					seed.steal_by(self))
	else:
		# 无种基础版：金丝抽击目标，仍然造成火伤与灼心
		if target == null:
			return
		dmg *= float(form.get("no_seed_coeff", 0.80))
		SkillFx.sun_tether(get_parent(), global_position, target.global_position,
			Color(1.0, 0.68, 0.28), 0.24)
		SkillFx.play_at_strike(self, "skill_sun_pull", form,
			facing_dir_to(target.global_position))
	if target != null and is_instance_valid(target):
		_deal_direct_damage(target, dmg, "elemental", "fire", "skill_sun_pull")
		_apply_player_skill_debuff(target, "skill_sun_pull")


func _cast_sun_wind(form: Dictionary, dir: Vector2) -> void:
	var dmg := CharacterData.calc_skill_damage("skill_sun_wind", true, false)
	SkillFx.play_at_strike(self, "skill_sun_wind", form, dir)
	var reach := float(form.get("range", 230.0))
	var angle := float(form.get("angle", 90.0))
	var knock_angle := float(form.get("angle", 90.0))
	var wind_hit := _damage_bosses_in_shape(dir, reach, deg_to_rad(angle * 0.5), dmg,
		"elemental", "fire", false, "skill_sun_wind", float(form.get("knockback", 260.0)))
	# 肉鸽「日进」：焚风命中同样补柴
	if wind_hit and RogueRun.has_flag("sun_hit_stack"):
		_rogue_gain_sun_stack()
	# 焚风扇面持续 0.3 秒：起手后才进入扇面的火种/持种者也会被掀落
	_wind_window_token += 1
	_wind_knock_window(global_position, dir.normalized(), reach, knock_angle,
		_wind_window_token)


## 焚风扇面持续 0.3 秒，每 0.04 秒扫一次；掀到一次就停
func _wind_knock_window(origin: Vector2, dir: Vector2, reach: float,
		knock_angle: float, token: int) -> void:
	var left := 0.30
	while left > 0.0:
		if token != _wind_window_token:
			return
		if not is_instance_valid(self) or is_dead:
			return
		if _try_wind_knock(origin, dir, reach, knock_angle):
			return
		await get_tree().create_timer(0.04, true, false, true).timeout
		left -= 0.04


func _try_wind_knock(origin: Vector2, dir: Vector2, reach: float,
		knock_angle: float) -> bool:
	var seed := _sun_seed
	if seed == null or not is_instance_valid(seed) or seed.state == SunSeed.State.GONE:
		return false
	var holder := seed.holder
	var arena_boss := _nearest_boss(2000.0)
	if holder != null and is_instance_valid(holder) and holder.is_in_group("boss"):
		arena_boss = holder as Node2D
	if holder != null and is_instance_valid(holder) and holder.is_in_group("boss") \
			and _sun_point_in_cone_from(origin, (holder as Node2D).global_position,
				dir, reach, knock_angle):
		var dest := _clamp_seed_knock(
			(holder as Node2D).global_position + dir * 480.0, arena_boss)
		seed.fly_to(dest, 0.36, 56.0, holder)
		return true
	if seed.is_free() and _sun_point_in_cone_from(origin, seed.global_position,
			dir, reach, knock_angle):
		var dest := _clamp_seed_knock(seed.global_position + dir * 440.0, arena_boss)
		seed.fly_to(dest, 0.34, 52.0)
		return true
	return false


## 击飞距离翻倍后别把火种送出战斗区：按 BOSS 的 arena 边界钳一下
func _clamp_seed_knock(dest: Vector2, boss: Node2D) -> Vector2:
	if boss == null or not is_instance_valid(boss):
		return dest
	var half = boss.get("arena_half_extents")
	if not (half is Vector2) or (half as Vector2) == Vector2.ZERO:
		return dest
	var center := Vector2.ZERO
	var c = boss.get("arena_center")
	if c is Vector2:
		center = c
	var margin := 56.0
	var m = boss.get("arena_margin")
	if m is float:
		margin = m
	var lim := (half as Vector2) - Vector2(margin, margin)
	return Vector2(clampf(dest.x, center.x - lim.x, center.x + lim.x),
		clampf(dest.y, center.y - lim.y, center.y + lim.y))


## 逐日 · 焚风用的扇形包含判定，和 _damage_bosses_in_shape 的过滤条件一致
func _sun_point_in_cone_from(origin: Vector2, pos: Vector2, dir: Vector2,
		reach: float, angle_deg: float) -> bool:
	var to: Vector2 = pos - origin
	var d := to.length()
	if d > reach + 18.0:
		return false
	if d <= 1.0:
		return true
	return dir.normalized().dot(to / d) >= cos(deg_to_rad(angle_deg * 0.5))


func _cast_sun_eclipse(form: Dictionary, dir: Vector2) -> void:
	var seed := _sun_seed
	var has_seed := seed != null and is_instance_valid(seed)
	var target := Vector2.ZERO
	if has_seed:
		if seed.is_held_by(self):
			target = global_position + dir.normalized() * float(form.get("throw_forward", 120.0))
		elif seed.holder != null and seed.holder.is_in_group("boss"):
			target = seed.holder.global_position
		elif seed.is_free():
			target = seed.global_position
		else:
			has_seed = false
	if not has_seed:
		var b := _nearest_boss(520.0)
		if b == null:
			return
		target = b.global_position
	var coeff := 1.0 if has_seed else float(form.get("no_seed_coeff", 0.65))
	var radius := float(form.get("range", 140.0))
	if not has_seed:
		radius *= float(form.get("no_seed_radius_mult", 0.75))
	var dmg := CharacterData.calc_skill_damage("skill_sun_eclipse", true, false) * coeff
	var delay := float(form.get("delay", 0.35))
	if has_seed:
		seed.consume()
	SkillFx.sun_warn_at(get_parent(), target, radius, delay)
	get_tree().create_timer(delay, true, false, true).timeout.connect(
		func() -> void:
			if not is_instance_valid(self) or is_dead:
				return
			SkillFx.play_at_strike(self, "skill_sun_eclipse", form, dir, target)
			_sun_damage_circle(target, radius, dmg, "skill_sun_eclipse"))


func _cast_sun_meteor(form: Dictionary, dir: Vector2) -> void:
	var seed := _sun_seed
	var points: Array[Vector2] = []
	if seed != null and is_instance_valid(seed):
		points.append(seed.global_position)
	var b := _nearest_boss(520.0)
	if b != null:
		points.append(b.global_position)
	elif points.is_empty():
		points.append(global_position + dir.normalized() * 260.0)
	var dmg := CharacterData.calc_skill_damage("skill_sun_meteor", true, false)
	# 火地是延迟跳伤，火种可能已经消耗；把当前的日冕乘区抓到闭包里，
	# 否则后续每跳按丢种后的 1.0 算，等于把持种加成吞掉。
	var burn_mult := CharacterData.sun_damage_mult
	for point in points:
		_sun_meteor_impact(point, form, dir, dmg, burn_mult)


## 火种落点与目标各落一发；两圈重叠时 BOSS 吃两份完整伤害，火地也叠两层
func _sun_meteor_impact(target: Vector2, form: Dictionary, dir: Vector2,
		dmg: float, burn_mult: float) -> void:
	var radius := float(form.get("range", 180.0))
	var delay := float(form.get("delay", 0.45))
	SkillFx.sun_warn_at(get_parent(), target, radius, delay)
	get_tree().create_timer(delay, true, false, true).timeout.connect(
		func() -> void:
			if not is_instance_valid(self) or is_dead:
				return
			SkillFx.play_at_strike(self, "skill_sun_meteor", form, dir, target)
			_sun_damage_circle(target, radius, dmg, "skill_sun_meteor")
			_sun_burn_ticks(target, radius * 0.75,
				float(form.get("ground_burn_time", 3.0)),
				float(form.get("ground_burn_tick", 1.0)),
				float(form.get("ground_burn_coeff", 0.25)), burn_mult))


func _sun_burn_ticks(pos: Vector2, radius: float, duration: float,
		interval: float, coeff: float, sun_mult: float = 1.0) -> void:
	var left := duration
	while left > 0.0:
		await get_tree().create_timer(maxf(0.05, interval), true, false, true).timeout
		if not is_instance_valid(self) or is_dead:
			return
		left -= interval
		_sun_damage_circle(pos, radius,
			CharacterData.spell_attack() * coeff * sun_mult, "", false)


## 返回是否打中过至少一个敌人（投日的「焚息」回灵要按命中算，不按施放算）
func _sun_damage_circle(pos: Vector2, radius: float, dmg: float,
		skill_id: String, apply_debuff: bool = true) -> bool:
	var struck := false
	for b in _array_enemy_units():
		if b == null or not is_instance_valid(b) or not (b is Node2D):
			continue
		if (b as Node2D).global_position.distance_to(pos) > radius + 18.0:
			continue
		_deal_direct_damage(b, dmg, "elemental", "fire", skill_id)
		if apply_debuff and skill_id != "":
			_apply_player_skill_debuff(b, skill_id)
		struck = true
	return struck


## 投日（日曜·掷种）的命中结算：范围火伤 + 肉鸽「焚息」按命中回灵。
## ⚠ 带种/无种两条分支都走这里，否则回灵只在其中一半情况下成立。
func _sun_throw_hit(pos: Vector2, radius: float, dmg: float) -> void:
	if not _sun_damage_circle(pos, radius, dmg, "skill_sun_throw"):
		return
	var back := RogueRun.stat("sun_throw_mana")
	if back > 0.0:
		var got := restore_mana(back)
		if got > 0.0:
			_show_float_text("焚息 · 回灵 %d" % int(round(got)), Color(0.52, 0.78, 1.0))


func facing_dir_to(pos: Vector2) -> Vector2:
	var v := pos - global_position
	return v.normalized() if v.length_squared() > 0.0001 else attack_dir


func _refresh_thunder_unlock() -> void:
	_thunder_unlocked = _family_equipped("thunder")
	if not _thunder_unlocked:
		lei_shi = 0
		_clear_player_law()
		_cancel_thunder_channel(false)
	_refresh_thunder_hud()


func _ensure_thunder_hud() -> void:
	if _mech_hud == null:
		return
	if _thunder_pips == null or not is_instance_valid(_thunder_pips):
		_thunder_pips = ThunderPips.new()
		_thunder_pips.name = "ThunderPips"
		add_mechanic_row(_thunder_pips)
	if _verdict_banner == null or not is_instance_valid(_verdict_banner):
		_verdict_banner = VerdictBanner.new()
		_verdict_banner.name = "VerdictBanner"
		add_mechanic_row(_verdict_banner)
	_refresh_thunder_hud()


func _refresh_thunder_hud() -> void:
	if _thunder_pips != null and is_instance_valid(_thunder_pips):
		_thunder_pips.visible = _thunder_unlocked
		_thunder_pips.set_state(lei_shi)


## 满雷势：攻速 +30% 与平A协同雷击的门槛
func _thunder_full_active() -> bool:
	return _thunder_unlocked and lei_shi >= _thunder_max()


## 攻速乘区（+30% = 间隔 ÷1.3；与装备 / 顺天的攻速按乘区叠加）
func _attack_haste_mult() -> float:
	var bonus := THUNDER_FULL_HASTE if _thunder_full_active() else 0.0
	# 肉鸽「满势·疾」：只在满雷势时生效（主模式 stat 恒 0）
	if _thunder_full_active():
		bonus += RogueRun.stat("thunder_full_haste") / 100.0
	# 肉鸽「明灭·疾」：明灭窗口内攻速
	if _shadow_dim_left > 0.0:
		bonus += RogueRun.stat("shadow_dim_haste") / 100.0
	return 1.0 + bonus


func _finisher_attack_time() -> float:
	return FINISHER_TIME / _attack_haste_mult()


## 判词读数：BOSS 挂在玩家身上的四条律（读 debuffs，不在别处再存一份）
func _tick_thunder_banner() -> void:
	if _verdict_banner == null or not is_instance_valid(_verdict_banner):
		return
	var ids: Array = []
	var max_left := 0.0
	for id in ["verdict_no_move", "verdict_no_attack", "verdict_no_dodge", "verdict_no_still"]:
		var left := float(debuffs.get(String(id), 0.0))
		if left > 0.0:
			ids.append(String(id))
			max_left = maxf(max_left, left)
	_verdict_banner.set_laws(ids, max_left)


func _add_lei(n: int) -> void:
	var before := lei_shi
	lei_shi = clampi(lei_shi + n, 0, _thunder_max())
	_refresh_thunder_hud()
	if lei_shi > before:
		if lei_shi >= _thunder_max():
			_show_float_text("雷势已满 · 攻速 +30%", Color(0.86, 0.70, 1.0))
		else:
			_show_float_text("雷势 %d/%d" % [lei_shi, _thunder_max()], Color(0.86, 0.70, 1.0))
		SkillFx.thunder_mark(get_parent(), global_position, 46.0,
			Color(0.86, 0.70, 1.0), 0.32)


## 消耗雷势：被动「雷积·震魂」佩戴时，每 1 点让所有主动功法剩余 CD -1 秒
func _spend_lei(n: int) -> int:
	var spent := mini(maxi(n, 0), lei_shi)
	if spent <= 0:
		return 0
	lei_shi -= spent
	_refresh_thunder_hud()
	if _thunder_accum_equipped():
		# 肉鸽「雷势·减」：每点雷势额外减 CD（主模式 stat 恒 0）
		var cut := float(spent) * (THUNDER_ACCUM_CD_PER_LEI + RogueRun.stat("lei_cd_add"))
		for sid in skill_cooldowns.keys():
			var left := float(skill_cooldowns[sid]) - cut
			if left <= 0.0:
				skill_cooldowns.erase(sid)
			else:
				skill_cooldowns[sid] = left
		_show_float_text("雷势 -%d · 全功法 CD -%d 秒" % [spent, int(round(cut))],
			Color(0.86, 0.70, 1.0))
	# 肉鸽「雷爆」：每消耗 1 层雷势，身周炸一圈雷（不依赖「雷积」被动）
	var lei_burst := RogueRun.stat("lei_spend_burst")
	if lei_burst > 0.0 and RogueRun.active:
		var burst_dmg := CharacterData.spell_attack() * lei_burst * float(spent)
		for boss in _array_enemy_units():
			if not is_instance_valid(boss) or not boss is Node2D:
				continue
			if (boss as Node2D).global_position.distance_to(global_position) <= 260.0:
				_deal_direct_damage(boss, burst_dmg, "elemental", "thunder", "skill_thunder_nine")
		_show_float_text("雷爆 · 雷势倾泻", Color(0.78, 0.72, 1.0))
	return spent


## 被动「雷积·震魂」是否佩戴
func _thunder_accum_equipped() -> bool:
	var gate := SkillDB.get_passive_by_effect("thunder_accum_stun")
	if gate.is_empty():
		return false
	var sid := String(gate.get("skill_id", ""))
	return sid in CharacterData.learned_skills and sid in CharacterData.passive_skill_loadout


## 这次伤害是否算「雷击功法」：带 thunder 标记 / 雷灾标记，或 thunder 元素
func _is_thunder_attack(skill_id: String, elem: String) -> bool:
	if elem == "thunder":
		return true
	var sk := SkillDB.get_skill(skill_id)
	if sk.is_empty():
		return false
	return bool(sk.get("thunder", false)) \
		or String(sk.get("calamity_tag", "")) == "thunder"


## 敌人每被雷击功法命中一次计数；第 9 次眩晕 0.5 秒并清零
func _note_thunder_skill_hit(target: Node, skill_id: String, elem: String) -> void:
	if not _thunder_accum_equipped() or target == null or not is_instance_valid(target):
		return
	if not _is_thunder_attack(skill_id, elem):
		return
	var hits := int(target.get_meta(THUNDER_ACCUM_META, 0)) + 1
	# 肉鸽「速判」：降低所需雷击次数（主模式 stat 恒 0）
	var need := THUNDER_ACCUM_REQUIRED - int(RogueRun.stat("thunder_stun_less"))
	need = maxi(1, need)
	# 肉鸽「震魂」：延长眩晕
	var stun_sec := THUNDER_ACCUM_STUN_SECONDS + RogueRun.stat("thunder_stun_add")
	if hits >= need:
		target.set_meta(THUNDER_ACCUM_META, 0)
		if target.has_method("stun_for"):
			target.call("stun_for", stun_sec)
		elif target.has_method("stagger_for"):
			target.call("stagger_for", stun_sec)
		elif target.has_method("apply_debuff"):
			target.call("apply_debuff", "stun", stun_sec)
		if target is Node2D:
			_float_at_world("雷积 · 震魂",
				(target as Node2D).global_position + Vector2(0.0, -110.0),
				Color(0.90, 0.74, 1.0))
	else:
		target.set_meta(THUNDER_ACCUM_META, hits)


## 从伤害来源解析出 BOSS（投射物带 source / owner_unit；近战直接就是 BOSS）
func _source_boss(src: Node) -> Node2D:
	if src == null or not is_instance_valid(src):
		return null
	if src.is_in_group("boss"):
		return src as Node2D
	for key in ["source", "owner_unit"]:
		var raw = src.get(key)
		if raw is Node and is_instance_valid(raw) and (raw as Node).is_in_group("boss"):
			return raw as Node2D
	return null


## 目标行为窗口：只服务「下哪条律」，不参与任何伤害
func _tick_boss_watch(delta: float) -> void:
	_boss_dash_recent = maxf(0.0, _boss_dash_recent - delta)
	_boss_move_recent = maxf(0.0, _boss_move_recent - delta)
	_boss_attack_recent = maxf(0.0, _boss_attack_recent - delta)
	var b := _nearest_boss(640.0)
	if b == null:
		_boss_watch_target = null
		_boss_watch_pos = Vector2.INF
		return
	if b != _boss_watch_target or _boss_watch_pos == Vector2.INF:
		_boss_watch_target = b
		_boss_watch_pos = b.global_position
		_boss_dash_window = 0.0
		_boss_dash_dist = 0.0
		return
	var moved := b.global_position.distance_to(_boss_watch_pos)
	_boss_watch_pos = b.global_position
	if moved > 0.6:
		_boss_move_recent = 1.5
		_boss_still = 0.0
	else:
		_boss_still += delta
	_boss_dash_window += delta
	_boss_dash_dist += moved
	if _boss_dash_window >= 0.2:
		if _boss_dash_dist >= 140.0:
			_boss_dash_recent = 1.5
		_boss_dash_window = 0.0
		_boss_dash_dist = 0.0
	var raw_state = b.get("state")
	if raw_state != null and int(raw_state) >= 100:
		_boss_dash_recent = 1.5


## 选两条律：优先最近最“醒目”的行为，再从剩余律里补齐第二条
func _choose_player_laws() -> Array[String]:
	var out: Array[String] = []
	if _boss_dash_recent > 0.0:
		out.append("verdict_no_dodge")
	if _boss_attack_recent > 0.0 and not out.has("verdict_no_attack"):
		out.append("verdict_no_attack")
	if _boss_move_recent > 0.0 and not out.has("verdict_no_move"):
		out.append("verdict_no_move")
	for id in ["verdict_no_still", "verdict_no_move", "verdict_no_attack", "verdict_no_dodge"]:
		if out.size() >= 2:
			break
		if not out.has(id):
			out.append(id)
	var picked: Array[String] = []
	for i in mini(2, out.size()):
		picked.append(out[i])
	return picked


## 兼容旧调用/测试：返回第一条律
func _choose_player_law() -> String:
	var laws := _choose_player_laws()
	return laws[0] if not laws.is_empty() else "verdict_no_still"


func _law_short_hint(id: String) -> String:
	match id:
		"verdict_no_move":
			return "它一动就引雷"
		"verdict_no_attack":
			return "它出手就引雷"
		"verdict_no_dodge":
			return "它遁走就引雷"
		"verdict_no_still":
			return "它站定就引雷"
	return "违律引雷"


func _apply_player_laws(target: Node2D, laws: Array) -> void:
	if target == null or not is_instance_valid(target) or laws.is_empty():
		return
	_clear_player_law()
	_law_target = target
	_law_total = THUNDER_LAW_TIME
	var ids: Array[String] = []
	for raw in laws:
		var id := String(raw)
		if id == "" or ids.has(id):
			continue
		if ids.size() >= 2:
			break
		ids.append(id)
	if ids.is_empty():
		return
	_law_id = ids[0]
	_law_left = _law_total
	_law_violations = 0
	_law_cd = 0.0
	_law2_id = ids[1] if ids.size() > 1 else ""
	_law2_left = _law_total if _law2_id != "" else 0.0
	_law2_violations = 0
	_law2_cd = 0.0
	_law_moved = 0.0
	_law_still = 0.0
	_law_prev_pos = target.global_position
	var raw_state = target.get("state")
	_law_prev_state = int(raw_state) if raw_state != null else 0
	_law_dash_window = 0.0
	_law_dash_dist = 0.0
	if target.has_method("apply_debuff"):
		for id in ids:
			target.call("apply_debuff", id, _law_total)
	_create_law_mark(target)
	var names: Array[String] = []
	for id in ids:
		names.append(DebuffDB.display_name(id).replace("判词·", ""))
	_show_float_text("判词 · %s" % " / ".join(names), DebuffDB.color(ids[0]))
	for id in ids:
		SkillFx.thunder_mark(get_parent(), target.global_position, 52.0,
			DebuffDB.color(id), 0.40)


## 兼容旧调用/测试：单条施加
func _apply_player_law(target: Node2D, id: String) -> void:
	_apply_player_laws(target, [id])


func _clear_player_law() -> void:
	if _law_target != null and is_instance_valid(_law_target):
		for id in [_law_id, _law2_id]:
			var lid := String(id)
			if lid == "":
				continue
			if _law_target.has_method("remove_debuff"):
				_law_target.call("remove_debuff", lid)
			elif _law_target.has_method("clear_debuff"):
				_law_target.call("clear_debuff", lid)
	if is_instance_valid(_law_mark):
		_law_mark.queue_free()
	_law_mark = null
	_law_mark_label = null
	_law_mark_label2 = null
	_law_target = null
	_law_id = ""
	_law_left = 0.0
	_law2_id = ""
	_law2_left = 0.0
	_law_moved = 0.0
	_law_still = 0.0
	_law_cd = 0.0
	_law2_cd = 0.0
	_law_violations = 0
	_law2_violations = 0
	_law_prev_pos = Vector2.INF
	_law_dash_window = 0.0
	_law_dash_dist = 0.0


## 目标头顶的判词印：雷印 + 名称 + 倒计时（跟着目标走）
func _create_law_mark(target: Node2D) -> void:
	var mark := Node2D.new()
	mark.name = "PlayerVerdictMark"
	mark.z_as_relative = false
	mark.z_index = 90
	target.add_child(mark)
	var seal_path := ArtDB.THUNDER_LAW_SEAL_TEX
	if ResourceLoader.exists(seal_path):
		var spr := Sprite2D.new()
		spr.texture = load(seal_path)
		spr.centered = true
		spr.scale = Vector2(0.24, 0.24)
		spr.modulate = Color(1.0, 0.96, 0.86, 0.92)
		mark.add_child(spr)
	_law_mark_label = _make_law_mark_label(mark, 8.0)
	_law_mark_label2 = _make_law_mark_label(mark, 26.0)
	_law_mark = mark
	_update_law_mark()


func _make_law_mark_label(mark: Node2D, y: float) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 0.95))
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(190.0, 18.0)
	label.position = Vector2(-95.0, y)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.add_child(label)
	return label


func _update_law_mark() -> void:
	if not is_instance_valid(_law_target) or not is_instance_valid(_law_mark):
		return
	var top := -110.0
	if _law_target.has_method("head_top_y"):
		top = float(_law_target.call("head_top_y"))
	_law_mark.position = Vector2(0.0, top - 56.0)
	_update_law_label(_law_mark_label, _law_id, _law_left)
	_update_law_label(_law_mark_label2, _law2_id, _law2_left)


func _update_law_label(label: Label, id: String, left: float) -> void:
	if label == null or not is_instance_valid(label):
		return
	label.visible = id != "" and left > 0.0
	if not label.visible:
		return
	label.text = "%s %.1fs" % [DebuffDB.display_name(id), maxf(left, 0.0)]
	label.add_theme_color_override("font_color", DebuffDB.color(id))


## 玩家判词的执法：两条律各自计时/记违律；违律只落雷 + 给雷势，不提前结束判词
func _tick_thunder_law(delta: float) -> void:
	if _law_target == null or (_law_id == "" and _law2_id == ""):
		return
	if not is_instance_valid(_law_target) or is_dead:
		_clear_player_law()
		return
	# BossBase 的 is_dead 是方法，不是属性；Object.get("is_dead") 会拿到 Callable。
	var dead_now := false
	if _law_target.has_method("is_dead"):
		dead_now = _law_target.call("is_dead") == true
	else:
		var dead_raw = _law_target.get("is_dead")
		dead_now = dead_raw == true
	if dead_now:
		_clear_player_law()
		return
	if _law_id != "":
		_law_left -= delta
		_law_cd = maxf(0.0, _law_cd - delta)
	if _law2_id != "":
		_law2_left -= delta
		_law2_cd = maxf(0.0, _law2_cd - delta)
	var pos: Vector2 = _law_target.global_position
	var moved := pos.distance_to(_law_prev_pos) if _law_prev_pos != Vector2.INF else 0.0
	_law_prev_pos = pos
	if moved > 0.6:
		_law_moved += moved
		_law_still = 0.0
	else:
		_law_still += delta
	_law_dash_window += delta
	_law_dash_dist += moved
	if _law_dash_window >= 0.2:
		if _law_dash_dist >= 140.0:
			_law_violate("verdict_no_dodge")
		_law_dash_window = 0.0
		_law_dash_dist = 0.0
	var raw_state = _law_target.get("state")
	var st := int(raw_state) if raw_state != null else 0
	if (st == int(BossBase.BossState.ATTACK) or st >= 100) and _law_prev_state != st:
		_law_violate("verdict_no_attack")
	_law_prev_state = st
	if _law_id == "verdict_no_move" and _law_cd <= 0.0 and _law_moved >= 110.0:
		_law_moved = 0.0
		_law_violate("verdict_no_move")
	elif _law2_id == "verdict_no_move" and _law2_cd <= 0.0 and _law_moved >= 110.0:
		_law_moved = 0.0
		_law_violate("verdict_no_move")
	if _law_id == "verdict_no_still" and _law_cd <= 0.0 and _law_still >= 0.9:
		_law_still = 0.0
		_law_violate("verdict_no_still")
	elif _law2_id == "verdict_no_still" and _law2_cd <= 0.0 and _law_still >= 0.9:
		_law_still = 0.0
		_law_violate("verdict_no_still")
	_expire_player_laws()


func _expire_player_laws() -> void:
	var had_primary := _law_id != ""
	var had_secondary := _law2_id != ""
	var total_violations := _law_violations + _law2_violations
	if had_primary and _law_left <= 0.0:
		_remove_law_debuff(_law_id)
		_law_id = ""
		_law_left = 0.0
		_law_violations = 0
		_law_cd = 0.0
	if had_secondary and _law2_left <= 0.0:
		_remove_law_debuff(_law2_id)
		_law2_id = ""
		_law2_left = 0.0
		_law2_violations = 0
		_law2_cd = 0.0
	if _law_id == "" and _law2_id == "":
		if total_violations == 0 and not is_dead:
			apply_shuntian(6.0)
			if _law_target != null and is_instance_valid(_law_target) \
					and _law_target.has_method("on_player_law_kept"):
				_law_target.call("on_player_law_kept")
			_show_float_text("判词已过 · 它守住了", Color(0.82, 0.66, 1.0))
		_clear_player_law()
	else:
		_update_law_mark()


func _remove_law_debuff(id: String) -> void:
	if _law_target == null or not is_instance_valid(_law_target) or id == "":
		return
	if _law_target.has_method("remove_debuff"):
		_law_target.call("remove_debuff", id)
	elif _law_target.has_method("clear_debuff"):
		_law_target.call("clear_debuff", id)


func _law_violate(id: String) -> void:
	if _law_target == null or not is_instance_valid(_law_target):
		return
	var primary := _law_id == id
	var secondary := _law2_id == id
	if not primary and not secondary:
		return
	if primary:
		if _law_cd > 0.0:
			return
		_law_cd = 0.35
		_law_violations += 1
	else:
		if _law2_cd > 0.0:
			return
		_law2_cd = 0.35
		_law2_violations += 1
	_add_lei(1)
	var pos: Vector2 = _law_target.global_position
	_float_at_world("违律！", pos + Vector2(0.0, -120.0), Color(0.90, 0.62, 1.0))
	SkillFx.thunder_mark(get_parent(), pos, 58.0, Color(0.86, 0.66, 1.0), 0.25)
	get_tree().create_timer(0.25, true, false, true).timeout.connect(func() -> void:
		if not is_instance_valid(self) or is_dead:
			return
		if _law_target == null or not is_instance_valid(_law_target):
			return
		SkillFx.play_at_strike(self, "fx_thunder_violation",
			{"range": 60.0, "hit_shape": MoveDB.SHAPE_CIRCLE}, Vector2.RIGHT, pos)
		if _law_target.global_position.distance_to(pos) <= 62.0:
			_deal_direct_damage(_law_target,
				CharacterData.spell_attack() * THUNDER_LAW_COEF,
				"elemental", "thunder", "skill_thunder_verdict", false))


func _float_at_world(text: String, pos: Vector2, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 0.95))
	label.add_theme_constant_override("outline_size", 4)
	label.size = Vector2(300.0, 24.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = pos + Vector2(-150.0, 0.0)
	label.z_index = 70
	get_parent().add_child(label)
	var tw := label.create_tween()
	tw.tween_property(label, "position:y", label.position.y - 24.0, 0.5)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.5)
	tw.tween_callback(label.queue_free)


## 聚雷引导：1.2 秒；每 0.4 秒在身周落一道雷；完成才 +1 雷势
func _tick_thunder_channel(delta: float) -> void:
	if _thunder_channel_left <= 0.0:
		return
	_thunder_channel_left -= delta
	if is_dead or _thunder_channel_damage >= max_hp * _thunder_channel_break:
		_cancel_thunder_channel(true)
		return
	_thunder_channel_tick -= delta
	if _thunder_channel_tick <= 0.0:
		_thunder_channel_tick = 0.4
		var pos := global_position + Vector2(randf_range(-180.0, 180.0),
			randf_range(-110.0, 110.0))
		pos = _array_clamp_point(pos)
		var dmg := CharacterData.spell_attack() * 0.35
		SkillFx.thunder_mark(get_parent(), pos, 80.0, Color(0.80, 0.62, 1.0), 0.22)
		get_tree().create_timer(0.22, true, false, true).timeout.connect(func() -> void:
			if not is_instance_valid(self) or is_dead:
				return
			SkillFx.play_at_strike(self, "fx_thunder_violation",
				{"range": 80.0, "hit_shape": MoveDB.SHAPE_CIRCLE}, Vector2.RIGHT, pos)
			for b in _array_enemy_units():
				if b.global_position.distance_to(pos) <= 96.0:
					_deal_direct_damage(b, dmg, "elemental", "thunder",
						"skill_thunder_gather", false))
	if _thunder_channel_left <= 0.0:
		_add_lei(1)
		_show_float_text("聚雷已成 · 雷势 +1", Color(0.86, 0.70, 1.0))
		_free_thunder_channel_fx()


func _cancel_thunder_channel(announce: bool) -> void:
	_free_thunder_channel_fx()
	_thunder_channel_left = 0.0
	_thunder_channel_damage = 0.0
	if announce and not is_dead:
		_show_float_text("聚雷被打断", UIKit.C_FLOAT_WARN)


func _free_thunder_channel_fx() -> void:
	if is_instance_valid(_thunder_channel_fx):
		_thunder_channel_fx.queue_free()
	_thunder_channel_fx = null


## 判词起手：报招名 + 写明这一条律；玩家在风摇第一帧就知道会被罚什么
func _thunder_precast(skill_id: String, _dir: Vector2) -> void:
	if not skill_id.begins_with("skill_thunder_"):
		return
	if not _thunder_unlocked:
		_refresh_thunder_unlock()
	if not _thunder_unlocked:
		return
	var form := SkillDB.get_skill_form(skill_id)
	var title := SkillDB.get_skill_name(skill_id)
	var color := Color(0.82, 0.66, 1.0)
	if skill_id == "skill_thunder_verdict":
		_pending_player_laws = _choose_player_laws()
		_pending_player_law = _pending_player_laws[0] if not _pending_player_laws.is_empty() else ""
		var names: Array[String] = []
		for id in _pending_player_laws:
			names.append(DebuffDB.display_name(id).replace("判词·", ""))
		title = "判词 · %s" % " / ".join(names)
		color = DebuffDB.color(_pending_player_laws[0]) if not _pending_player_laws.is_empty() else color
	_show_skill_name(title, float(form.get("windup", 0.2)) + 0.2, color)


## 八式结算：true = 已处理完；雷遁返回 false，让通用圆形结算在落点出伤
func _thunder_handle_cast(skill_id: String, dir: Vector2) -> bool:
	if not skill_id.begins_with("skill_thunder_"):
		return false
	if not _thunder_unlocked:
		_refresh_thunder_unlock()
	if not _thunder_unlocked:
		return false
	var form := SkillDB.get_skill_form(skill_id)
	if form.is_empty():
		return false
	match skill_id:
		"skill_thunder_verdict":
			return _cast_thunder_verdict(form, dir)
		"skill_thunder_execute":
			return _cast_thunder_execute(form)
		"skill_thunder_drum":
			return _cast_thunder_drum(form)
		"skill_thunder_lock":
			return _cast_thunder_lock(form, dir)
		"skill_thunder_step":
			SkillFx.play_at_strike(self, skill_id, form, dir, global_position)
			return false
		"skill_thunder_gather":
			return _cast_thunder_gather(form, dir)
		"skill_thunder_nine":
			return _cast_thunder_nine(form)
		"skill_thunder_prison":
			return _cast_thunder_prison(form)
	return false


func _cast_thunder_verdict(form: Dictionary, dir: Vector2) -> bool:
	var laws: Array = _pending_player_laws.duplicate()
	if laws.is_empty():
		if _pending_player_law != "":
			laws = [_pending_player_law]
		else:
			laws = _choose_player_laws()
	# 补足第二条，保证每次判词都是两条不同的律
	for id in _choose_player_laws():
		if laws.size() >= 2:
			break
		if not laws.has(id):
			laws.append(id)
	_pending_player_laws.clear()
	_pending_player_law = ""
	SkillFx.play_at_strike(self, "skill_thunder_verdict", form, dir, null)
	var dmg := CharacterData.calc_skill_damage("skill_thunder_verdict", true, false)
	var reach := float(form.get("range", 320.0))
	var half_w := float(form.get("width", 56.0)) * 0.5 + 24.0
	for b in _array_enemy_units():
		if _array_point_segment_distance(b.global_position, global_position,
				global_position + dir.normalized() * reach) <= half_w:
			_deal_direct_damage(b, dmg, "elemental", "thunder", "skill_thunder_verdict")
	var target := _nearest_boss(380.0)
	if target != null:
		var to := target.global_position - global_position
		if to.length() <= 380.0 and to.normalized().dot(dir.normalized()) >= cos(deg_to_rad(60.0)):
			_apply_player_laws(target, laws)
	return true


func _cast_thunder_execute(form: Dictionary) -> bool:
	var target := _nearest_boss(460.0)
	if target == null:
		return true
	var pos: Vector2 = target.global_position
	var radius := float(form.get("range", 90.0))
	var delay := float(form.get("delay", 0.45))
	var dmg := CharacterData.calc_skill_damage("skill_thunder_execute", true, false)
	var bonus := 0.0
	if _law_target == target and (_law_left > 0.0 or _law2_left > 0.0):
		bonus = float(form.get("verdict_bonus", 0.5))
	SkillFx.thunder_mark(get_parent(), pos, radius, Color(0.86, 0.66, 1.0), delay)
	get_tree().create_timer(delay, true, false, true).timeout.connect(func() -> void:
		if not is_instance_valid(self) or is_dead:
			return
		SkillFx.play_at_strike(self, "skill_thunder_execute", form, Vector2.RIGHT, pos)
		for b in _array_enemy_units():
			if b.global_position.distance_to(pos) <= radius + 18.0:
				_deal_direct_damage(b, dmg * (1.0 + bonus), "elemental", "thunder",
					"skill_thunder_execute"))
	return true


func _cast_thunder_drum(form: Dictionary) -> bool:
	SkillFx.play_at_strike(self, "skill_thunder_drum", form, attack_dir, null)
	var radius := float(form.get("range", 180.0))
	var kb := float(form.get("knockback", 260.0))
	var dmg := CharacterData.calc_skill_damage("skill_thunder_drum", true,
		has_buff("parry_power"))
	var hit := false
	for b in _array_enemy_units():
		var d: float = b.global_position.distance_to(global_position)
		if d > radius + 18.0:
			continue
		hit = true
		_deal_direct_damage(b, dmg, "physical", "", "skill_thunder_drum")
		if b.has_method("take_knockback") and d > 0.1:
			b.call("take_knockback",
				((b.global_position - global_position).normalized()) * kb)
	if hit and has_buff("parry_power"):
		consume_buff("parry_power")
	return true


func _cast_thunder_lock(form: Dictionary, dir: Vector2) -> bool:
	SkillFx.play_at_strike(self, "skill_thunder_lock", form, dir, null)
	var dmg := CharacterData.calc_skill_damage("skill_thunder_lock", true, false)
	var reach := float(form.get("range", 300.0))
	var half_w := float(form.get("width", 54.0)) * 0.5 + 24.0
	for b in _array_enemy_units():
		if _array_point_segment_distance(b.global_position, global_position,
				global_position + dir.normalized() * reach) <= half_w:
			_deal_direct_damage(b, dmg, "elemental", "thunder", "skill_thunder_lock")
			_apply_player_skill_debuff(b, "skill_thunder_lock")
	return true


func _cast_thunder_gather(form: Dictionary, dir: Vector2) -> bool:
	_thunder_channel_damage = 0.0
	_thunder_channel_break = float(form.get("channel_break_damage", 0.08))
	_thunder_channel_left = float(form.get("channel_time", 1.2))
	_thunder_channel_tick = 0.0
	_free_thunder_channel_fx()
	_thunder_channel_fx = SkillFx.play_at_strike(self, "skill_thunder_gather",
		form, dir, null)
	_show_float_text("聚雷 · 引霆", Color(0.86, 0.70, 1.0))
	return true


func _cast_thunder_nine(form: Dictionary) -> bool:
	var target := _nearest_boss(520.0)
	if target == null:
		return true
	var center: Vector2 = target.global_position
	var spent_lei := lei_shi
	# 肉鸽「雷柱·增」：额外雷柱（主模式 stat 恒 0）
	var count := int(form.get("pillar_count_base", 2)) + spent_lei \
		+ int(RogueRun.stat("pillar_add"))
	_spend_lei(spent_lei)
	var radius := float(form.get("range", 100.0))
	var spread := float(form.get("pillar_spread", 120.0))
	# 肉鸽「雷柱·重」：整体伤害
	var dmg := CharacterData.calc_skill_damage("skill_thunder_nine", true, false) \
		* (1.0 + RogueRun.stat("pillar_pct") / 100.0)
	var offsets: Array = [Vector2.ZERO]
	for i in range(1, maxi(1, count)):
		var ang := TAU * float(i - 1) / float(maxi(1, count - 1)) + randf_range(-0.2, 0.2)
		offsets.append(Vector2(cos(ang), sin(ang) * 0.62) * spread)
	for i in range(count):
		var pos: Vector2 = _array_clamp_point(center + (offsets[i % offsets.size()] as Vector2))
		SkillFx.thunder_mark(get_parent(), pos, radius, Color(0.86, 0.66, 1.0), 0.42)
		get_tree().create_timer(0.42, true, false, true).timeout.connect(func() -> void:
			if not is_instance_valid(self) or is_dead:
				return
			SkillFx.play_at_strike(self, "skill_thunder_nine", form, Vector2.RIGHT, pos)
			for b in _array_enemy_units():
				if b.global_position.distance_to(pos) <= radius + 18.0:
					_deal_direct_damage(b, dmg, "elemental", "thunder",
						"skill_thunder_nine"))
	_show_float_text("九霄 · %d 道雷罚" % count, Color(0.86, 0.70, 1.0))
	return true


func _cast_thunder_prison(form: Dictionary) -> bool:
	var target := _nearest_boss(520.0)
	if target == null:
		return true
	var center: Vector2 = target.global_position
	var radius := float(form.get("prison_radius", 170.0))
	var closing := float(form.get("closing_time", 1.2))
	var dmg := CharacterData.calc_skill_damage("skill_thunder_prison", true, false)
	SkillFx.play_at_strike(self, "skill_thunder_prison", form, Vector2.RIGHT, center)
	get_tree().create_timer(closing, true, false, true).timeout.connect(func() -> void:
		if not is_instance_valid(self) or is_dead:
			return
		for b in _array_enemy_units():
			if b.global_position.distance_to(center) <= radius:
				_deal_direct_damage(b, dmg, "elemental", "thunder", "skill_thunder_prison")
				if b.has_method("stagger_for"):
					b.call("stagger_for", float(form.get("stagger_on_hit", 1.0))))
	return true


## 顺天（守律奖励）：6 秒攻速 +20%、移速 +10%；属性修正走 CharacterData
func apply_shuntian(seconds: float) -> void:
	if seconds <= 0.0:
		return
	apply_buff("shuntian", seconds)
	CharacterData.set_attribute_mod("shuntian", {
		"attack_speed": {"flat": 20.0},
		"speed_pct": {"flat": 10.0},
	})
	_show_float_text("顺天 · 攻速与移速提升", Color(1.0, 0.86, 0.46))
	SkillFx.thunder_mark(get_parent(), global_position, 54.0,
		Color(1.0, 0.86, 0.46), 0.40)


## 滞雷：闪避距离乘区（移速乘区仍走 debuff_move_mult）
func _dodge_distance_mult() -> float:
	var m := 1.0
	for id in debuffs.keys():
		m = minf(m, float(DebuffDB.get_debuff(String(id)).get("dodge_mult", 1.0)))
	return m


## 下一面玩家旗的颜色：先补缺色（三才），某色已有两面时 45% 补成三同色，其余按局面选
func _next_player_flag_kind() -> int:
	var have := {0: 0, 1: 0, 2: 0}
	for f in array_flags:
		if is_instance_valid(f):
			var k := int(f.get("kind"))
			have[k] = int(have.get(k, 0)) + 1
	for k in [0, 1, 2]:
		if int(have.get(k, 0)) == 2 and randf() < 0.45:
			return k
	for k in [0, 1, 2]:
		if int(have.get(k, 0)) == 0:
			return k
	if _array_nearest_enemy_dist() <= 240.0:
		return ArrayFlag.Kind.ATTACK
	if hp / maxf(max_hp, 1.0) <= 0.5:
		return ArrayFlag.Kind.GUARD
	return ArrayFlag.Kind.BIND


func _array_nearest_enemy_dist() -> float:
	var best := 99999.0
	for e in _array_enemy_units():
		best = minf(best, global_position.distance_to(e.global_position))
	return best


## 玩家侧三色被动（与 BOSS 同一套）：攻旗 150 内每 2.6 秒落一道预警剑气；
## 困旗 90 内锁步；守旗减伤由 take_damage 读 _array_guard_alive()。
func _tick_array_flags(delta: float) -> void:
	# 即使没学阵旗功法，只要站在敌方五旗阵里也要跑：攻击 -10% 的标签与数值在阵区逻辑里
	if not _array_unlocked and array_flags.is_empty() and _array_seal_guard_left <= 0.0 \
			and _array_zone_enemy_attack_mult >= 1.0 and not _array_zone_complete:
		return
	_array_seal_guard_left = maxf(0.0, _array_seal_guard_left - delta)
	_prune_array_flags()
	_tick_array_seal_guard()
	_sync_array_line_visuals()
	_tick_array_zone(delta)
	_tick_array_guard_aura(delta)
	for k in _array_flag_cd.keys():
		_array_flag_cd[k] = maxf(0.0, float(_array_flag_cd[k]) - delta)
	var enemies := _array_enemy_units()
	if not array_flags.is_empty() and not enemies.is_empty():
		for f in array_flags:
			if int(f.get("kind")) != ArrayFlag.Kind.ATTACK:
				continue
			var fp: Vector2 = (f as Node2D).global_position
			var near: Node2D = null
			for e in enemies:
				if e.global_position.distance_to(fp) <= 150.0:
					near = e
					break
			if near == null:
				continue
			var key: int = int((f as Node).get_instance_id())
			if float(_array_flag_cd.get(key, 0.0)) <= 0.0:
				_array_flag_cd[key] = SkillDB.ARRAY_ATTACK_INTERVAL
				_array_strikes.append({"pos": near.global_position, "t": 0.5,
					"dmg": CharacterData.spell_attack() * SkillDB.ARRAY_ATTACK_COEF})
				_array_spawn_mark(ArtDB.ARRAY_FLAG_WARN_TEX, near.global_position, 58.0, 0.5)
		for f in array_flags:
			if int(f.get("kind")) != ArrayFlag.Kind.BIND:
				continue
			var fp2: Vector2 = (f as Node2D).global_position
			for e in enemies:
				if e.global_position.distance_to(fp2) <= ArrayFlag.BIND_RADIUS and e.has_method("apply_debuff"):
					e.call("apply_debuff", "lock_step", 0.35)
					break
	for s in _array_strikes.duplicate():
		s["t"] = float(s["t"]) - delta
		if float(s["t"]) > 0.0:
			continue
		_array_strikes.erase(s)
		var pos: Vector2 = s["pos"]
		var dmg := float(s["dmg"])
		for e in _array_enemy_units():
			if e.global_position.distance_to(pos) <= 58.0:
				_deal_direct_damage(e, dmg, "elemental", "fire", "skill_array_plant", false)
		ArrayFx.play_bombard(get_parent(), pos)


## 旗与旗之间的常驻阵线（与 BOSS 同构）：每段一根，不再拆半。
## 线同时挂 ArrayLineBarrier，挡住敌方单位；玩家自己的线不进自己的掩码。
func _sync_array_line_visuals() -> void:
	var segs := _array_segments()
	var need := segs.size()
	while _array_line_visuals.size() < need:
		var rope := Sprite2D.new()
		rope.texture = load(ARRAY_LINE_TEX)
		rope.centered = true
		rope.material = SkillFx.additive_material()
		rope.z_index = 1
		get_parent().add_child(rope)
		var glow := Sprite2D.new()
		glow.texture = rope.texture
		glow.centered = true
		glow.material = SkillFx.additive_material()
		glow.z_index = 0
		get_parent().add_child(glow)
		_array_line_visuals.append([rope, glow])
	while _array_line_visuals.size() > need:
		var pair = _array_line_visuals.pop_back()
		for sp in pair:
			if is_instance_valid(sp):
				(sp as Node).queue_free()
	if _array_line_barrier == null or not is_instance_valid(_array_line_barrier):
		_array_line_barrier = ArrayLineBarrier.new()
		_array_line_barrier.name = "ArrayLineBarrier"
		_array_line_barrier.top_level = true
		_array_line_barrier.setup(ArrayFlag.LINE_LAYER_PLAYER)
		add_child(_array_line_barrier)
	_array_line_barrier.sync(segs)
	var c := _array_line_color()
	for i in range(segs.size()):
		var fa: Node2D = segs[i][0]
		var fb: Node2D = segs[i][1]
		_place_array_line(_array_line_visuals[i], fa.global_position, fb.global_position, c)


func _array_line_color() -> Color:
	var k := _array_majority_kind()
	var c := Color(ArtDB.ARRAY_FLAG_KIND_COLORS.get(k, Color(0.96, 0.84, 0.58)))
	return c.lerp(Color(0.98, 0.86, 0.60), 0.35)


func _place_array_line(pair: Array, a: Vector2, b: Vector2, color: Color) -> void:
	var v := b - a
	var rope: Sprite2D = pair[0]
	var glow: Sprite2D = pair[1]
	var center := (a + b) * 0.5
	var ang := v.angle()
	var sx := maxf(v.length(), 1.0) / 256.0
	rope.global_position = center
	rope.rotation = ang
	rope.scale = Vector2(sx, 1.0)
	rope.modulate = Color(1.3, 1.25, 1.15, 1.0)
	glow.global_position = center
	glow.rotation = ang
	glow.scale = Vector2(sx, 1.7)
	glow.modulate = Color(color.r, color.g, color.b, 0.24)


## 五旗区域：使用者在内 +30% 攻/防；区域内敌人 -10% 攻 + 每秒雷击（10 法力）
func _tick_array_zone(delta: float) -> void:
	# 敌方五旗阵压：攻击 -10% 的 HUD 标签（数值由 boss 调 set_array_zone_enemy_attack_mult）
	if _array_zone_enemy_attack_mult < 1.0:
		apply_debuff("array_zone_weaken", 1.2)
	elif debuffs.has("array_zone_weaken"):
		debuffs.erase("array_zone_weaken")
	var poly := _array_zone_polygon()
	if poly.size() < _array_max_flags():
		if _array_zone_complete:
			_clear_array_zone()
			_show_float_text("阵势已散", UIKit.C_TEXT_DIM)
		return
	if not _array_zone_complete:
		_array_zone_complete = true
		_show_float_text("五旗成阵 · 阵内攻防 +30%", Color(0.95, 0.82, 0.45))
	var inside := Geometry2D.is_point_in_polygon(global_position, poly)
	# 肉鸽「阵威」：阵内攻击加成从 1.30 起再叠（主模式 stat 恒 0）
	var zone_buff := ARRAY_ZONE_ATTACK_BUFF + RogueRun.stat("array_zone_amp") / 100.0
	_array_zone_self_attack_mult = zone_buff if inside else 1.0
	_array_zone_defense_mult = 1.0 / ARRAY_ZONE_DEFENSE_DIV if inside else 1.0
	_refresh_array_zone_attack_mult()
	if inside:
		apply_buff("array_zone", 1.2)
	elif has_buff("array_zone"):
		remove_buff("array_zone")
	_update_array_zone_fill(poly)
	var enemies := _array_zone_enemies_inside(poly)
	_apply_array_zone_enemy_debuff(enemies)
	if enemies.is_empty():
		_array_zone_timer = 0.0
		return
	# 肉鸽「雷速 / 雷池」：缩短落雷间隔
	var strike_haste := RogueRun.stat("array_strike_haste")
	var interval := ARRAY_ZONE_LIGHTNING_INTERVAL / (1.0 + maxf(0.0, strike_haste) / 100.0)
	_array_zone_timer += delta
	if _array_zone_timer < interval:
		return
	_array_zone_timer = 0.0
	if mana < ARRAY_ZONE_MANA_COST:
		_show_float_text("灵力枯竭 · 阵旗消散", UIKit.C_FLOAT_WARN)
		_clear_array_flags()
		return
	spend_mana(ARRAY_ZONE_MANA_COST)
	# 肉鸽「雷落·重 / 旗引」：按旗数叠伤害
	var strike_pct := RogueRun.stat("array_strike_pct") \
		+ RogueRun.stat("array_strike_per_flag") * float(array_flags.size())
	var dmg := CharacterData.spell_attack() * ARRAY_ZONE_LIGHTNING_COEF \
		* (1.0 + strike_pct / 100.0)
	var c := _array_line_color()
	for e in enemies:
		if is_instance_valid(e) and e.has_method("take_damage"):
			# 阵旗雷击按 metal 雷伤结算：计入「雷积·震魂」，也吃雷抗
			_deal_direct_damage(e, dmg, "elemental", "thunder", "skill_array_zone", false)
			ArrayFx.play_thunder(get_parent(), e.global_position, c)
			_rogue_array_strike_extras(e)


## 肉鸽雷落流：感电 + 连锁。主模式整段早退（`stat` 恒 0、`has_flag` 恒 false）。
## ⚠ 连锁要排除「已经吃到主雷」的那一批，否则同一只怪被劈两次
func _rogue_array_strike_extras(hit_enemy: Node) -> void:
	if not RogueRun.active:
		return
	if RogueRun.has_flag("array_strike_elec") and hit_enemy.has_method("apply_debuff"):
		hit_enemy.call("apply_debuff", "gan_dian", 3.0)
	var chain := int(RogueRun.stat("array_strike_chain"))
	if chain <= 0 or not (hit_enemy is Node2D):
		return
	var origin: Vector2 = (hit_enemy as Node2D).global_position
	var dmg := CharacterData.spell_attack() * ARRAY_ZONE_LIGHTNING_COEF \
		* (1.0 + (RogueRun.stat("array_strike_pct")
			+ RogueRun.stat("array_strike_per_flag") * float(array_flags.size())) / 100.0)
	var hits := 0
	for raw in _array_enemy_units():
		if hits >= chain:
			break
		if not is_instance_valid(raw) or not (raw is Node2D) or raw == hit_enemy:
			continue
		if (raw as Node2D).global_position.distance_to(origin) > 220.0:
			continue
		_deal_direct_damage(raw, dmg * 0.7, "elemental", "thunder", "skill_array_zone", false)
		ArrayFx.play_thunder(get_parent(), (raw as Node2D).global_position, _array_line_color())
		hits += 1


func _array_zone_polygon() -> PackedVector2Array:
	var poly := PackedVector2Array()
	if array_flags.size() < _array_max_flags():
		return poly
	for f in array_flags:
		if is_instance_valid(f) and f is Node2D:
			poly.append((f as Node2D).global_position)
	if poly.size() < _array_max_flags():
		return PackedVector2Array()
	return poly


func _array_zone_enemies_inside(poly: PackedVector2Array) -> Array:
	var out: Array = []
	for e in _array_enemy_units():
		if e is Node2D and Geometry2D.is_point_in_polygon((e as Node2D).global_position, poly):
			out.append(e)
	return out


func _apply_array_zone_enemy_debuff(enemies: Array) -> void:
	for e in _array_zone_affected_enemies.duplicate():
		if not is_instance_valid(e) or not (e in enemies):
			if is_instance_valid(e) and e.has_method("set_zone_attack_mult"):
				e.call("set_zone_attack_mult", "enemy", 1.0)
			_array_zone_affected_enemies.erase(e)
	for e in enemies:
		if e.has_method("set_zone_attack_mult"):
			e.call("set_zone_attack_mult", "enemy", ARRAY_ZONE_ENEMY_ATTACK_MULT)
			if not (e in _array_zone_affected_enemies):
				_array_zone_affected_enemies.append(e)


func _update_array_zone_fill(poly: PackedVector2Array) -> void:
	if _array_zone_fill == null or not is_instance_valid(_array_zone_fill):
		_array_zone_fill = Polygon2D.new()
		_array_zone_fill.name = "ArrayZoneFill"
		_array_zone_fill.top_level = true
		_array_zone_fill.z_as_relative = false
		_array_zone_fill.z_index = -8
		add_child(_array_zone_fill)
	_array_zone_fill.polygon = poly
	var c := _array_line_color()
	_array_zone_fill.color = Color(c.r, c.g, c.b, 0.06)
	_array_zone_fill.visible = true


## 守旗 / 守阵：脚下石青护罩（BOSS 同款常驻环，让"减伤正在生效"看得见）
func _tick_array_guard_aura(delta: float) -> void:
	var on := _array_guard_alive() or _array_seal_guard_left > 0.0
	if on and (_array_guard_aura == null or not is_instance_valid(_array_guard_aura)):
		_array_guard_aura = Sprite2D.new()
		_array_guard_aura.texture = load(ArtDB.ARRAY_FLAG_GUARD_TEX)
		_array_guard_aura.centered = true
		_array_guard_aura.position = Vector2(0.0, 18.0)
		_array_guard_aura.scale = Vector2(0.86, 0.86)
		_array_guard_aura.z_index = 1
		add_child(_array_guard_aura)
	if _array_guard_aura == null or not is_instance_valid(_array_guard_aura):
		return
	_array_guard_aura.visible = on and not is_dead
	if _array_guard_aura.visible:
		_array_guard_aura.rotation += delta * 0.35
		var a := 0.34 + 0.10 * sin(float(Time.get_ticks_msec()) * 0.004)
		_array_guard_aura.modulate = Color(0.55, 0.95, 1.0, a)


func _array_enemy_units() -> Array:
	var out: Array = []
	for b in get_tree().get_nodes_in_group("boss"):
		# ⚠ 死单位不参与索敌 / 结算：试炼里 BOSS 尸体不销毁、仍在 "boss" 组
		if BossBase.is_unit_dead(b):
			continue
		if is_instance_valid(b) and b is Node2D:
			out.append(b)
	return out


func _array_spawn_mark(tex_path: String, pos: Vector2, radius: float, life: float) -> void:
	var spr := Sprite2D.new()
	spr.texture = load(tex_path)
	spr.centered = true
	spr.scale = Vector2(radius * 2.0 / 256.0, radius * 2.0 / 256.0)
	spr.modulate = Color(1, 1, 1, 0.85)
	spr.z_index = 1
	get_parent().add_child(spr)
	spr.global_position = pos
	var tw := spr.create_tween()
	tw.tween_property(spr, "modulate:a", 0.0, maxf(0.12, life))
	tw.tween_callback(spr.queue_free)


## 守牢计时与「旗破瞬间消失」：记录的旗任何一面失效/被拔/离开数组 → 立刻结束
func _tick_array_seal_guard() -> void:
	if _array_seal_guard_left <= 0.0:
		_array_seal_guard_flags.clear()
		return
	var intact := array_flags.size() >= 4
	if intact:
		for f in _array_seal_guard_flags:
			if not is_instance_valid(f) or bool(f.get("_dead")) or not (f in array_flags):
				intact = false
				break
	if not intact:
		_array_seal_guard_left = 0.0
		_array_seal_guard_flags.clear()
		_show_float_text("守阵已破", UIKit.C_FLOAT_WARN)


## 玩家侧困牢：BOSS 走 stagger_for（BossBase 的硬控状态），其它单位走 stun debuff
func _stun_array_unit(u: Node, seconds: float) -> void:
	if u == null or not is_instance_valid(u):
		return
	if u.has_method("stagger_for"):
		if int(u.get("state")) == BossBase.BossState.STAGGER:
			return
		u.call("stagger_for", seconds)
		return
	if u.has_method("apply_debuff"):
		if u.has_method("has_debuff") and bool(u.call("has_debuff", "stun")):
			return
		u.call("apply_debuff", "stun", seconds)


## 引阵/卷阵整段结算（与 BOSS 同构）：攻＝伤害 / 困＝锁步 / 守＝不参与杀伤
func _array_line_effect(a: Vector2, b: Vector2, kind: int, coeff: float,
		skill_id: String = "skill_array_line", damage_kind: String = "elemental",
		element: String = "fire") -> void:
	if kind == ArrayFlag.Kind.GUARD:
		return
	var power := CharacterData.physical_attack() if damage_kind == "physical" else CharacterData.spell_attack()
	if damage_kind == "physical":
		power *= CharacterData.sword_intent_skill_mult
	var dmg := power * coeff
	for boss in _array_enemy_units():
		if _array_point_segment_distance(boss.global_position, a, b) > 42.0:
			continue
		if kind == ArrayFlag.Kind.ATTACK:
			if boss.has_method("take_damage"):
				_deal_direct_damage(boss, dmg, damage_kind, element, skill_id)
		elif boss.has_method("apply_debuff"):
			boss.call("apply_debuff", "lock_step", 1.0)


## 玩家守旗：任意一面存活 → 受伤 -15%
func _array_guard_alive() -> bool:
	for f in array_flags:
		if is_instance_valid(f) and int(f.get("kind")) == ArrayFlag.Kind.GUARD:
			return true
	return false


## 守阵：站在任意一段阵线上 → 伤害 +10%（读的是"布点后的站位"）
func _array_onsite() -> bool:
	if not _array_unlocked or array_flags.size() < 2:
		return false
	for seg in _array_segments():
		var a: Vector2 = (seg[0] as Node2D).global_position
		var b: Vector2 = (seg[1] as Node2D).global_position
		if _array_point_segment_distance(global_position, a, b) <= 42.0:
			return true
	return false


# =====================================================================
# 镜身 · 照影（照影界 · 观澜，2026-11-01）
# =====================================================================
## 玩家侧完整继承 BOSS 的镜身机制：
##   镜花 / 万镜 → 召出镜像（基础 2 具，佩戴被动「照影」再 +1；1 击碎，存在 10 秒）
##   任意功法（镜花 / 万镜除外）→ 场上所有镜像同时使出同一招（50% 伤害），放完即碎、不看命中
##   换镜 → 与镜像互换位置，短暂无形
##   碎镜 → 捏碎镜像，镜片在镜像处炸开并挂「镜滞」
##   镜返 → 短时间横镜架势，第一次接触到的**法术**被挡下并 100% 反弹
##   镜湖 → 脚下铺一圈水镜，间歇结算水伤并减速
## 没有势条、不攒层、不引爆：镜像只是一次性的场压与位移锚点。

const MIRROR_MAX_IMAGES := MirrorImage.MAX_IMAGES
const MIRROR_IMAGE_LIFE := MirrorImage.IMAGE_LIFE
const MIRROR_ECHO_RATIO := MirrorImage.ECHO_RATIO
const MIRROR_RETURN_TIME := MirrorImage.RETURN_TIME
const MIRROR_RETURN_RATIO := MirrorImage.RETURN_RATIO
const MIRROR_SWAP_IFRAMES := MirrorImage.SWAP_IFRAMES
const MIRROR_PASSIVE_CD := MirrorImage.PASSIVE_CD
const MIRROR_SHATTER_RADIUS := MirrorImage.SHATTER_RADIUS
const MIRROR_SLOW_TIME := MirrorImage.SLOW_TIME
const MIRROR_RING_RADIUS := MirrorImage.RING_RADIUS
const MIRROR_RING_DURATION := MirrorImage.RING_DURATION

var _mirror_images: Array = []
var _mirror_passive_cd: float = 0.0
var _mirror_return_left: float = 0.0
## 召镜两式自己不算「复读」，否则镜花一放出去就把刚召出的镜像用掉
const MIRROR_SUMMON_SKILLS: Array[String] = ["skill_mirror_bloom", "skill_mirror_myriad"]


func _mirror_prune() -> void:
	var keep: Array = []
	for raw in _mirror_images:
		if is_instance_valid(raw) and raw is MirrorImage and not bool(raw.call("is_dead")):
			keep.append(raw)
		elif is_instance_valid(raw) and raw is MirrorImage:
			# 肉鸽「镜爆」：自然消散的镜像在落点炸开（被剔除的这一帧只触发一次）
			_mirror_burst_on_gone(raw)
	_mirror_images = keep


## 肉鸽「镜爆」：镜像消散时的范围法术伤害
func _mirror_burst_on_gone(img: Node) -> void:
	if not RogueRun.active or not img is Node2D:
		return
	var coeff := RogueRun.stat("mirror_burst_coeff")
	if coeff <= 0.0:
		return
	var pos: Vector2 = (img as Node2D).global_position
	var dmg := CharacterData.spell_attack() * coeff
	for e in _array_enemy_units():
		if not is_instance_valid(e) or not e is Node2D:
			continue
		if (e as Node2D).global_position.distance_to(pos) > 150.0:
			continue
		_deal_direct_damage(e, dmg, "elemental", "", "skill_mirror_shatter")
	SkillFx.play_at_point(get_parent(), "skill_mirror_shatter",
		MoveDB.resolve_player("form_mirror_shatter"), Vector2.RIGHT, pos, self)


func _mirror_clear_images() -> void:
	for raw in _mirror_images:
		if is_instance_valid(raw):
			raw.queue_free()
	_mirror_images.clear()


func _mirror_pick() -> MirrorImage:
	_mirror_prune()
	if _mirror_images.is_empty():
		return null
	return _mirror_images[0] as MirrorImage


func _tick_mirror(delta: float) -> void:
	if _mirror_passive_cd > 0.0:
		_mirror_passive_cd = maxf(0.0, _mirror_passive_cd - delta)
	if _mirror_return_left > 0.0:
		_mirror_return_left = maxf(0.0, _mirror_return_left - delta)
		if _mirror_return_left <= 0.0:
			remove_buff("mirror_return")
	_mirror_prune()


## 玩家镜像的贴图 / 缩放 / 偏移全部从当前 SkinVisual 快照，和本体同一帧形象
func _mirror_spawn(world_pos: Vector2) -> MirrorImage:
	var tex: Texture2D = null
	var sc := Vector2(0.25, 0.25)
	var off := Vector2(0.0, 5.0)
	var flip := false
	if skin != null and is_instance_valid(skin):
		tex = skin.current_texture()
		if skin.render_node is Node2D:
			var rn := skin.render_node as Node2D
			sc = rn.scale.abs()
			off = rn.position
			if rn is Sprite2D:
				flip = (rn as Sprite2D).flip_h
	var img := MirrorImage.new()
	# 肉鸽「复读 / 镜久」：复读倍率与寿命都能再加（主模式 stat 恒 0）
	img.setup(self, "player", world_pos, tex, sc, off,
		Color(0.90, 0.96, 1.0, 0.94),
		MIRROR_ECHO_RATIO + RogueRun.stat("mirror_echo_add"),
		MIRROR_IMAGE_LIFE + RogueRun.stat("mirror_life"), flip)
	var host := get_parent()
	if host == null:
		img.free()
		return null
	host.add_child(img)
	img.global_position = world_pos
	_mirror_images.append(img)
	SkillFx.play_at_point(host, "skill_mirror_bloom",
		MoveDB.resolve_player("form_mirror_bloom"), Vector2.RIGHT, world_pos, self)
	return img


## 起手报招名：玩家侧和 BOSS 的 show_skill_line 同节奏，读前摇多久就挂多久
func _mirror_precast(skill_id: String) -> void:
	var sk := SkillDB.get_skill(skill_id)
	if sk.is_empty() or not bool(sk.get("mirror", false)):
		return
	var form := SkillDB.get_skill_form(skill_id)
	var color := UIKit.C_DMG_PHYS if SkillDB.get_phys_coeff(skill_id) > SkillDB.get_spell_coeff(skill_id) \
		else UIKit.C_DMG_SPELL
	_show_skill_name(String(sk.get("skill_name", "")),
		maxf(0.25, float(form.get("windup", 0.2)) + 0.25), color)


## 镜身自定义结算入口；返回 true = 不走通用命中
func _mirror_handle_cast(skill_id: String, dir: Vector2) -> bool:
	match skill_id:
		"skill_mirror_bloom":
			return _mirror_cast_bloom()
		"skill_mirror_shatter":
			return _mirror_cast_shatter()
		"skill_mirror_swap":
			return _mirror_cast_swap(dir)
		"skill_mirror_return":
			return _mirror_cast_return(dir)
		"skill_mirror_ring":
			return _mirror_cast_ring(dir)
		"skill_mirror_myriad":
			return _mirror_cast_myriad()
	return false


func _mirror_cast_bloom() -> bool:
	_mirror_prune()
	if _mirror_images.size() >= _mirror_max_images():
		return true
	var pos := global_position + Vector2(randf_range(-72.0, 72.0),
		randf_range(-26.0, 18.0))
	_mirror_spawn(pos)
	_show_float_text("镜花 · %d 影" % _mirror_images.size(), Color(0.62, 0.86, 1.0))
	return true


func _mirror_cast_myriad() -> bool:
	_mirror_prune()
	var index := _mirror_images.size()
	while _mirror_images.size() < _mirror_max_images():
		var side := -1.0 if index % 2 == 0 else 1.0
		var pos := global_position + Vector2(side * 82.0, randf_range(-18.0, 22.0))
		if _mirror_spawn(pos) == null:
			break
		index += 1
	_show_float_text("万镜 · %d 影" % _mirror_images.size(), Color(0.64, 0.88, 1.0))
	return true


func _mirror_cast_shatter() -> bool:
	var img := _mirror_pick()
	if img == null:
		return true
	var pos: Vector2 = img.global_position
	img.call("take_damage", 0.0)
	var dmg := CharacterData.calc_skill_damage("skill_mirror_shatter", true, false)
	SkillFx.play_at_point(get_parent(), "skill_mirror_shatter",
		MoveDB.resolve_player("form_mirror_shatter"), Vector2.RIGHT, pos, self)
	_damage_bosses_in_shape(Vector2.RIGHT, MIRROR_SHATTER_RADIUS, 0.0,
		dmg, "elemental", "water", true, "skill_mirror_shatter", 0.0, pos)
	_mirror_slow_area(pos, MIRROR_SHATTER_RADIUS, MIRROR_SLOW_TIME)
	_show_float_text("碎镜", Color(0.62, 0.86, 1.0))
	return true


func _mirror_cast_swap(dir: Vector2) -> bool:
	var img := _mirror_pick()
	if img == null:
		return true
	var old := global_position
	var dest: Vector2 = img.global_position
	global_position = dest
	img.global_position = old
	invincible_timer = maxf(invincible_timer, MIRROR_SWAP_IFRAMES
		+ RogueRun.stat("mirror_swap_inv"))
	TreasureFx.play_swap(get_parent(), old, dest)
	attack_dir = (dest - old).normalized() if dest.distance_squared_to(old) > 1.0 else dir
	# 肉鸽「换镜·锐」：换位后短窗口增伤
	var swap_amp := RogueRun.stat("mirror_swap_dmg")
	if swap_amp > 0.0:
		_rogue_mirror_swap_left = 2.0
	_show_float_text("换镜", Color(0.66, 0.88, 1.0))
	return true


func _mirror_cast_return(dir: Vector2) -> bool:
	_mirror_return_left = MIRROR_RETURN_TIME
	apply_buff("mirror_return", MIRROR_RETURN_TIME)
	SkillFx.play_at_point(get_parent(), "skill_mirror_return",
		MoveDB.resolve_player("form_mirror_return"), dir,
		global_position + _body_center(), self)
	_show_float_text("镜返", Color(0.66, 0.88, 1.0))
	return true


func _mirror_cast_ring(dir: Vector2) -> bool:
	var dmg := CharacterData.calc_skill_damage("skill_mirror_ring", true, false)
	var field := MirrorRingField.new()
	field.setup(global_position, true, MIRROR_RING_RADIUS, MIRROR_RING_DURATION,
		dmg, self, Color(0.62, 0.86, 1.0, 1.0))
	get_parent().add_child(field)
	SkillFx.play_at_strike(self, "skill_mirror_ring",
		MoveDB.resolve_player("form_mirror_ring"), dir)
	_show_float_text("镜湖", Color(0.62, 0.86, 1.0))
	return true


## 镜身 · 照影（玩家侧）：本体这一招收完后，场上**所有**镜像同时跟着使出同一招。
## 由 `_cast_skill` / `_release_counter` 在 `_apply_skill_hit` **之后**调用：
## 碎镜 / 换镜自己就要吃掉一具镜像，复读必须排在那之后，否则会把本体的招一起抢没。
## 只有打得出伤害的功法会复读：镜花 / 万镜显式排除，换镜 / 镜返 / 凝环这类状态技
## 本来就算不出伤害（`calc_skill_damage` 返回 0），自然不参与。
## 每具镜像复读一次就碎，所以领域跳 / 连段突进也不会重复消耗。
func _mirror_on_skill_cast(skill_id: String, form: Dictionary) -> void:
	if skill_id in MIRROR_SUMMON_SKILLS or form.is_empty():
		return
	_mirror_prune()
	if _mirror_images.is_empty():
		return
	var dmg := CharacterData.calc_skill_damage(skill_id, true, false)
	if dmg <= 0.0:
		return
	# 伤害类型跟本体一致：法术为主的功法（碎镜 / 镜湖）也照样复读，只是走对方法抗
	var phys := float(form.get("phys_coeff", 0.0))
	var spell := float(form.get("spell_coeff", 0.0))
	var kind := "elemental" if spell > phys else "physical"
	var elem := String(form.get("damage_element", ""))
	for raw in _mirror_images:
		var img := raw as MirrorImage
		if img != null:
			img.call("cast_echo", skill_id, form, dmg, kind, elem)


## 被动「照影」是否佩戴（认 passive_effect，不硬比 skill_id）
func _mirror_echo_passive_on() -> bool:
	var gate := SkillDB.get_passive_by_effect("mirror_echo")
	if gate.is_empty():
		return false
	return String(gate.get("skill_id", "")) in CharacterData.passive_skill_loadout


## 镜像上限：基础 2 具，佩戴被动「照影」再 +1
func _mirror_max_images() -> int:
	var bonus := RogueRun.cap("mirror_max") - int(RogueDB.CAP_BASE.get("mirror_max", 2))
	return MIRROR_MAX_IMAGES + bonus + (MirrorImage.PASSIVE_EXTRA_IMAGES \
			if _mirror_echo_passive_on() else 0)


func _mirror_slow_area(pos: Vector2, radius: float, seconds: float) -> void:
	# 肉鸽「碎镜·滞」：减速时长（主模式 stat 恒 0）
	var slow_sec := seconds + RogueRun.stat("mirror_slow_sec")
	for raw in get_tree().get_nodes_in_group("boss"):
		# ⚠ 死单位不参与索敌 / 结算：试炼里 BOSS 尸体不销毁、仍在 "boss" 组
		if BossBase.is_unit_dead(raw):
			continue
		if not is_instance_valid(raw) or not raw is Node2D:
			continue
		var u := raw as Node2D
		if u.global_position.distance_to(pos) > radius + 18.0:
			continue
		if u.has_method("apply_debuff"):
			u.call("apply_debuff", "mirror_slow", slow_sec)


## 镜返：只挡**法术**（elemental）；挡下后按原伤害 100% 原样反弹回来源（一次性）
## 物理近战 / 投掷不再被镜面吃掉 —— 那些留给弹刀与闪避处理
func _mirror_try_return(amount: float, attack_kind: String, source: Node,
		element: String = "") -> bool:
	if _mirror_return_left <= 0.0:
		return false
	if attack_kind != "elemental":
		return false
	_mirror_return_left = 0.0
	remove_buff("mirror_return")
	_hit_negated_timer = DEBUFF_NEGATE_WINDOW
	var target := _mirror_reflect_target(source)
	if target != null and target.has_method("take_damage"):
		# 肉鸽「镜返·反 / 镜返·烈」：反弹倍率（主模式 stat 恒 0）
		var reflect_mult := MIRROR_RETURN_RATIO \
			* (1.0 + RogueRun.stat("mirror_reflect_pct") / 100.0)
		target.call("take_damage", amount * reflect_mult, self,
			"elemental", element if element != "" else "water")
	# 肉鸽「镜返·护 / 镜返·归」
	var extra_inv := RogueRun.stat("mirror_reflect_inv")
	if extra_inv > 0.0:
		invincible_timer = maxf(invincible_timer, extra_inv)
	if RogueRun.has_flag("mirror_reflect_stamina"):
		stamina = minf(max_stamina, stamina + 2.0)
		_update_stamina_bar()
	SkillFx.play_at_point(get_parent(), "skill_mirror_return",
		MoveDB.resolve_player("form_mirror_return"), attack_dir,
		global_position + _body_center(), self)
	_show_float_text("镜返 · 奉还", Color(0.66, 0.88, 1.0))
	GameState.play_sfx("attack_hit")
	return true


func _mirror_reflect_target(source: Node) -> Node:
	if source == null or not is_instance_valid(source):
		return null
	var raw = source.get("source")
	if is_instance_valid(raw) and raw is Node and (raw as Node).has_method("take_damage"):
		return raw as Node
	if source.has_method("take_damage"):
		return source
	return null


func _mirror_passive_on_perfect_dodge() -> void:
	if _mirror_passive_cd > 0.0:
		return
	if not _mirror_echo_passive_on():
		return
	_mirror_prune()
	if _mirror_images.size() >= _mirror_max_images():
		return
	var pos := global_position + Vector2(randf_range(-64.0, 64.0),
		randf_range(-20.0, 16.0))
	_mirror_spawn(pos)
	_mirror_passive_cd = MIRROR_PASSIVE_CD
	_show_float_text("照影 · 留镜", Color(0.62, 0.86, 1.0))


# =====================================================================
# 投影 · 身外之影（照影界第 2 位「执烛」玩家侧，2026-11-02）
# =====================================================================
## 灯笼拖在身后：影长 = 你与灯笼的距离 × 1.70。
## 跑动 / 突进把灯甩远 → 影子拉长 → 影系招式的射程跟着变长；站定 → 灯笼追上来 → 影长塌回脚边。
## 几何口径全在 ShadowLaw —— 执烛那边是「绕灯抢位」，你这边是「跑位换射程」，
## 读的是同一条地上的黑刃。不读写任何 BOSS 私有状态，所以演武场 / 万界秘境 / 任何战场都成立。

const SHADOW_LINE_SKILLS: Array[String] = [
	"skill_shadow_reach", "skill_shadow_beam", "skill_shadow_step",
]
## 影子只有一份：撕出去代打期间，靠影尖的那两招哑火
## ⚠ 投晷不在表里：分影撕走的是**影尖那一截**（代价改成影长打折，见 SHADOW_SPLIT_LEN_MULT），
##   脚下到断口这段还在，所以长刺照打。原来把投晷也封掉，等于用 22 秒 CD 去封全组 DPS
##   最高的一招（投晷 64），分影自己只值 21 —— 那是净负收益，没人会点。
const SHADOW_SPLIT_BLOCKED: Array[String] = [
	"skill_shadow_bind", "skill_shadow_split",
]
const SHADOW_GROUND_Y := 26.0        ## 玩家脚下的地面锚点（灯笼 / 影带都挂在这里）
## ⚠ 用 preload 而不是类名：新建 class_name 不在编辑器当前的全局类缓存里，
##   直接写 ShadowSweeper 会让 player.gd 解析失败（2026-11-02 踩过）
const SHADOW_SWEEPER_SCRIPT := preload("res://scripts/combat/shadow_sweeper.gd")
## 影根那具站起来的墨影：分影脱手时画在走廊起点，读得出「是影子在替你打」
const SHADOW_ROOT_TEX := preload("res://assets/effects/skills/zhizhu_shadow.png")
const SHADOW_ROOT_SCALE := 0.24
## 玩家抢过来提着的那盏界灯 = 执烛的灯笼拆件（同一件东西，别画成两样）
const SHADOW_LANTERN_TEX := preload("res://assets/characters/boss/zhizhu_rig/lantern.png")

var _lantern_pos := Vector2.ZERO
var _lantern_lag_want := 0.0
## 最近 LANTERN_INERTIA 秒的移动速度均值 —— 拖尾吃这个，不吃瞬时速度
var _lantern_speed_avg := 0.0
## 按下影技那一帧定格的影长，与剩余有效时间（判定/特效/影带同一份）
var _shadow_snap_len := 0.0
var _shadow_snap_left := 0.0
var _lantern_node: Node2D = null
var _shadow_band: ShadowVisual = null
var _shadow_band_left := 0.0
var _shadow_dim_left := 0.0
var _shadow_long_left := 0.0
var _shadow_passive_left := 0.0
var _shadow_passive_cd := 0.0
var _shadow_split_left := 0.0
var _shadow_split_dmg := 0.0
var _shadow_split_sweeper: Node2D = null
var _shadow_bind_left := 0.0
var _shadow_bind_pos := Vector2.ZERO
var _shadow_bind_dmg := 0.0
var _shadow_bind_moving: bool = false


## 身上有没有影系功法（主动四格 + 被动都算）。没有就整条机制不出现 —— 无来源不显示。
func _shadow_equipped() -> bool:
	for raw in CharacterData.active_skill_loadout:
		if bool(SkillDB.get_skill(String(raw)).get("shadow", false)):
			return true
	for raw in CharacterData.passive_skill_loadout:
		if bool(SkillDB.get_skill(String(raw)).get("shadow", false)):
			return true
	return false


## 被动「执灯」是否佩戴（认 passive_effect，不硬比 skill_id）
func _shadow_lamp_passive_on() -> bool:
	var gate := SkillDB.get_passive_by_effect("shadow_lamp")
	if gate.is_empty():
		return false
	return String(gate.get("skill_id", "")) in CharacterData.passive_skill_loadout


func _shadow_feet() -> Vector2:
	return global_position + Vector2(0.0, SHADOW_GROUND_Y)


## 灯笼落后多远 —— 就是影长的来源
func _shadow_lag() -> float:
	return _lantern_pos.distance_to(global_position)


## 实时影长（不含快照）：暗场归零、分影打折、长夜抬上限、完美闪避后拉满
func _shadow_len_now() -> float:
	if _shadow_dim_left > 0.0:
		return ShadowLaw.SHADOW_MIN * 0.6
	var mult := ShadowLaw.PASSIVE_MULT if _shadow_lamp_passive_on() else 1.0
	## 分影撕走的是影尖那一截：脚下这段还在，所以投晷照打，只是短一截
	## —— 这是它的代价。以前改成「封掉投晷/缚影/分影」，等于用 22 秒 CD 去封
	##    全组 DPS 最高的一招，而影兽自己只值三分之一，点了反而更弱。
	if _shadow_split_left > 0.0:
		mult *= SkillDB.SHADOW_SPLIT_LEN_MULT
	var cap := ShadowLaw.LANTERN_SHADOW_MAX * mult
	# 肉鸽「长影」：影长上限放大（主模式 stat 恒 0）
	cap *= 1.0 + RogueRun.stat("shadow_len_pct") / 100.0
	if _shadow_long_left > 0.0:
		cap += SkillDB.SHADOW_LONGNIGHT_EXTRA_MAX
	var lag := _shadow_lag()
	if _shadow_passive_left > 0.0:
		lag = ShadowLaw.LANTERN_LAG_MAX + (200.0 if _shadow_long_left > 0.0 else 0.0)
	return clampf(lag * ShadowLaw.LANTERN_SLOPE * mult, ShadowLaw.SHADOW_MIN, cap)


## 出招读的影长：按下那一帧定格的快照（见 _shadow_precast）。
## ⚠ 不快照会自欺欺人：影技不锁移动，但前摇那 0.1~0.3 秒里人一停、灯笼就以 430px/s
##   追上来，特效按按下时的长度画、判定按命中帧的长度算 —— 看着够、实际打空。
func _shadow_len() -> float:
	return _shadow_snap_len if _shadow_snap_left > 0.0 else _shadow_len_now()


## 影带方向 = 出招方向（灯笼吊在它的反方向），所以射程由影长决定、方向仍归玩家
func _shadow_dir(dir: Vector2) -> Vector2:
	var d := dir.normalized() if dir.length_squared() > 0.01 else attack_dir.normalized()
	return d if d.length_squared() > 0.01 else Vector2.RIGHT


func _tick_shadow(delta: float) -> void:
	if _shadow_band_left > 0.0:
		_shadow_band_left = maxf(0.0, _shadow_band_left - delta)
	if _shadow_dim_left > 0.0:
		_shadow_dim_left = maxf(0.0, _shadow_dim_left - delta)
		if _shadow_dim_left <= 0.0:
			remove_buff("shadow_dim")
	if _shadow_long_left > 0.0:
		_shadow_long_left = maxf(0.0, _shadow_long_left - delta)
	if _shadow_passive_left > 0.0:
		_shadow_passive_left = maxf(0.0, _shadow_passive_left - delta)
	if _shadow_passive_cd > 0.0:
		_shadow_passive_cd = maxf(0.0, _shadow_passive_cd - delta)
	if _shadow_split_left > 0.0:
		_shadow_split_left = maxf(0.0, _shadow_split_left - delta)
	if _shadow_bind_left > 0.0:
		_shadow_bind_left = maxf(0.0, _shadow_bind_left - delta)
		if _shadow_bind_left <= 0.0:
			_shadow_resolve_bind()
	if _shadow_snap_left > 0.0:
		_shadow_snap_left = maxf(0.0, _shadow_snap_left - delta)
	if not _shadow_equipped():
		_shadow_clear_visuals()
		return
	_shadow_update_lantern(delta)
	_shadow_update_band()


func _shadow_update_lantern(delta: float) -> void:
	var aim := attack_dir
	if aim.length_squared() < 0.01:
		aim = Vector2.RIGHT
	## 拖尾吃「最近这段时间跑了多快」的均值，不吃瞬时速度：
	## 平A / 弹反 / 符箓那零点几秒人是定身的（velocity 归零），按瞬时速度算
	## 就等于每一下普攻都在抽干自己的射程 —— 而这组本来要穿插平A。
	_lantern_speed_avg = lerpf(_lantern_speed_avg, velocity.length(),
			clampf(delta / ShadowLaw.LANTERN_INERTIA, 0.0, 1.0))
	var want := clampf(_lantern_speed_avg * 1.30, 0.0, ShadowLaw.LANTERN_LAG_MAX)
	if _shadow_long_left > 0.0:
		want = ShadowLaw.LANTERN_LAG_MAX + 200.0
	if _shadow_dim_left > 0.0:
		want = 0.0
	# 肉鸽「定影」：影长不随静止衰减（只进不退，主模式 stat 恒 0）
	var prev_want := _lantern_lag_want
	_lantern_lag_want = lerpf(prev_want, want, clampf(delta * 4.5, 0.0, 1.0))
	if RogueRun.stat("shadow_hold") > 0.0 and _shadow_dim_left <= 0.0:
		_lantern_lag_want = maxf(_lantern_lag_want, prev_want)
	var goal := global_position - aim.normalized() * _lantern_lag_want
	if _lantern_pos == Vector2.ZERO:
		_lantern_pos = goal
	# 肉鸽「追灯」：灯笼追赶速度（主模式 stat 恒 0）
	var catchup := ShadowLaw.LANTERN_CATCHUP \
		* (1.0 + RogueRun.stat("shadow_recover_pct") / 100.0)
	_lantern_pos = _lantern_pos.move_toward(goal, catchup * delta)
	if _lantern_node == null or not is_instance_valid(_lantern_node):
		_lantern_node = _shadow_build_lantern()
	if _lantern_node != null:
		_lantern_node.global_position = _lantern_pos
		var k := 0.55 + 0.45 * clampf(_shadow_lag() / ShadowLaw.LANTERN_LAG_MAX, 0.0, 1.0)
		_lantern_node.scale = Vector2.ONE * k


func _shadow_build_lantern() -> Node2D:
	var host := get_parent()
	if host == null:
		return null
	var n := Node2D.new()
	n.name = "PlayerLantern"
	n.z_index = -1
	host.add_child(n)
	var halo := Sprite2D.new()
	halo.texture = SkillFx.dot_texture()
	halo.centered = true
	halo.material = SkillFx.additive_material()
	halo.modulate = Color(0.86, 0.82, 0.56, 0.34)
	halo.scale = Vector2(1.5, 1.5)
	n.add_child(halo)
	## 灯体用执烛那盏界灯的拆件：玩家是「把灯抢过来提着」，
	## 画成一团星芒就看不出抢的是同一件东西。提钩在画布 (62,14)，
	## 所以整张图往下挪半个画布再缩，让钩子正好落在锚点上。
	var k := 44.0 / 239.0
	var body := Sprite2D.new()
	body.texture = SHADOW_LANTERN_TEX
	body.centered = true
	body.scale = Vector2.ONE * k
	body.position = Vector2(0.0, (239.0 * 0.5 - 14.0) * k)
	body.z_index = 1
	n.add_child(body)
	var core := Sprite2D.new()
	var flame: Texture2D = SkillFx.skill_texture("lamp_flame")
	core.texture = flame if flame != null else SkillFx.star_texture()
	core.centered = true
	core.material = SkillFx.additive_material()
	core.modulate = Color(0.98, 0.92, 0.70, 0.80)
	core.scale = Vector2.ONE * (0.28 if flame == null else 34.0 / 115.0)
	core.position = Vector2(0.0, 14.0 * k)
	core.z_index = 2
	n.add_child(core)
	return n


## 影带读数：淡墨一条铺在前方，长度就是影系招式的射程
func _shadow_update_band() -> void:
	var length := _shadow_len()
	var show := length > ShadowLaw.SHADOW_MIN * 1.6
	if not show and _shadow_band_left <= 0.0:
		if _shadow_band != null and is_instance_valid(_shadow_band):
			_shadow_band.set_shape(_shadow_dir(attack_dir), length,
				ShadowLaw.WIDTH_ROOT, 0.16, false)
		return
	if _shadow_band == null or not is_instance_valid(_shadow_band):
		var host := get_parent()
		if host == null:
			return
		_shadow_band = ShadowVisual.new()
		_shadow_band.name = "PlayerShadowBand"
		_shadow_band.ink = Color(0.05, 0.06, 0.10)
		_shadow_band.tip_color = Color(0.80, 0.94, 1.0)
		host.add_child(_shadow_band)
	_shadow_band.global_position = _shadow_feet()
	var alpha := 0.62 if _shadow_band_left > 0.0 else 0.24
	_shadow_band.set_shape(_shadow_dir(attack_dir), length,
		ShadowLaw.corridor_width(length, 1.0), alpha)


func _shadow_clear_visuals() -> void:
	if _shadow_band != null and is_instance_valid(_shadow_band):
		_shadow_band.queue_free()
	_shadow_band = null
	if _lantern_node != null and is_instance_valid(_lantern_node):
		_lantern_node.queue_free()
	_lantern_node = null


## 起手：报招名 + 把影带点亮一拍（与 BOSS 的 show_windup_line 同一节奏）
func _shadow_precast(skill_id: String, dir: Vector2) -> void:
	if not skill_id.begins_with("skill_shadow_"):
		return
	if not _shadow_equipped():
		return
	var form := SkillDB.get_skill_form(skill_id)
	## 影长快照：按下这一帧定格，整招（前摇 + 判定 + 后摇）都用这一份。
	## ⚠ 必须排在 _shadow_fit_form 之前（同一个 _cast_skill 里紧跟着调），
	##   否则特效覆盖射程时读到的还是实时值，判定与画面又分叉了。
	_shadow_snap_len = _shadow_len_now()
	_shadow_snap_left = float(form.get("windup", 0.15)) + float(form.get("active", 0.12)) \
			+ float(form.get("recover", 0.22)) + SkillDB.SHADOW_SNAP_TAIL
	_shadow_band_left = float(form.get("windup", 0.15)) + 0.25
	_show_skill_name(SkillDB.get_skill_name(skill_id),
		float(form.get("windup", 0.15)) + 0.2, Color(0.62, 0.72, 0.98))
	_shadow_update_band()


## 直线影技的射程改成当前影长（判定与特效同一份数据）
func _shadow_fit_form(skill_id: String, form: Dictionary) -> Dictionary:
	if not skill_id in SHADOW_LINE_SKILLS or form.is_empty():
		return form
	var out := form.duplicate(true)
	var length := _shadow_len()
	if skill_id == "skill_shadow_beam":
		out["range"] = maxf(length * 0.86, 240.0)
	elif skill_id == "skill_shadow_step":
		out["range"] = maxf(length * 0.7, 160.0)
	else:
		out["range"] = length
	out["width"] = ShadowLaw.corridor_width(float(out["range"]), 1.0) * _shadow_width_mult()
	return out


## 影技的特殊结算：true = 已处理，不再走通用伤害
func _shadow_handle_cast(skill_id: String, dir: Vector2) -> bool:
	if not skill_id.begins_with("skill_shadow_"):
		return false
	match skill_id:
		"skill_shadow_reach":
			return _shadow_cast_reach(dir)
		"skill_shadow_beam":
			return _shadow_cast_beam(dir)
		"skill_shadow_step":
			return _shadow_cast_step(dir)
		"skill_shadow_bind":
			return _shadow_cast_bind(dir)
		"skill_shadow_dim":
			return _shadow_cast_dim()
		"skill_shadow_split":
			return _shadow_cast_split(dir)
		"skill_shadow_longnight":
			return _shadow_cast_longnight(dir)
	return false


func _shadow_cast_reach(dir: Vector2) -> bool:
	var form := MoveDB.resolve_player("form_shadow_reach")
	var length := _shadow_len()
	var dmg := CharacterData.calc_skill_damage("skill_shadow_reach", true, false)
	var hit := _shadow_damage_corridor(_shadow_feet(), _shadow_dir(dir), length,
		ShadowLaw.WIDTH_TIP, dmg, "physical",
		SkillDB.get_damage_element("skill_shadow_reach"), "skill_shadow_reach")
	_shadow_strike_fx("skill_shadow_reach", form, dir, length)
	if hit:
		GameState.trigger_hit_stop()
		GameState.play_sfx("attack_hit")
	return true


func _shadow_cast_beam(dir: Vector2) -> bool:
	var form := MoveDB.resolve_player("form_shadow_beam")
	var length := maxf(_shadow_len() * 0.86, 240.0)
	var dmg := CharacterData.calc_skill_damage("skill_shadow_beam", true, false)
	var hit := _shadow_damage_corridor(_shadow_feet(), _shadow_dir(dir), length,
		ShadowLaw.WIDTH_TIP * 0.9, dmg, "elemental",
		SkillDB.get_damage_element("skill_shadow_beam"), "skill_shadow_beam")
	_shadow_strike_fx("skill_shadow_beam", form, dir, length)
	if hit:
		GameState.trigger_hit_stop()
		GameState.play_sfx("attack_hit")
	return true


func _shadow_cast_step(dir: Vector2) -> bool:
	var form := MoveDB.resolve_player("form_shadow_step")
	var length := maxf(_shadow_len() * 0.7, 160.0)
	var dmg := CharacterData.calc_skill_damage("skill_shadow_step", true, false)
	var hit := _shadow_damage_corridor(_shadow_feet(), _shadow_dir(dir), length,
		ShadowLaw.WIDTH_TIP, dmg, "physical",
		SkillDB.get_damage_element("skill_shadow_step"), "skill_shadow_step")
	_shadow_strike_fx("skill_shadow_step", form, dir, length)
	if hit:
		GameState.trigger_hit_stop()
		GameState.play_sfx("attack_hit")
	return true


## 缚影：在影身 62% 处落印，延迟后钉住（敌人在动就只留墨痕减速）
func _shadow_cast_bind(dir: Vector2) -> bool:
	var length := _shadow_len()
	_shadow_bind_pos = _shadow_feet() + _shadow_dir(dir) * (length * 0.62)
	_shadow_bind_dmg = CharacterData.calc_skill_damage("skill_shadow_bind", true, false)
	_shadow_bind_left = SkillDB.SHADOW_BIND_DELAY
	var moving := false
	for raw in _array_enemy_units():
		var u := raw as Node2D
		var vel: Variant = u.get("velocity")
		if vel is Vector2 and (vel as Vector2).length() > 40.0:
			moving = true
	_shadow_bind_moving = moving
	SkillFx.play_at_point(get_parent(), "skill_shadow_bind",
		MoveDB.resolve_player("form_shadow_bind"), _shadow_dir(dir), _shadow_bind_pos, self)
	_show_float_text("缚影 · %s" % ("按住" if not moving else "追人"), Color(0.62, 0.68, 0.94))
	return true


func _shadow_resolve_bind() -> void:
	var radius := 96.0
	var hit := false
	for raw in _array_enemy_units():
		var u := raw as Node2D
		if u.global_position.distance_to(_shadow_bind_pos) > radius + 18.0:
			continue
		var dmg := _shadow_bind_dmg if not _shadow_bind_moving else _shadow_bind_dmg * 0.5
		_deal_direct_damage(u, dmg * _shadow_dim_mult("physical"), "physical",
			SkillDB.get_damage_element("skill_shadow_bind"),
			"skill_shadow_bind")
		if u.has_method("apply_debuff"):
			if _shadow_bind_moving:
				u.call("apply_debuff", "shadow_soak", 1.6)
			else:
				u.call("apply_debuff", "shadow_bind", SkillDB.SHADOW_BIND_SECONDS)
		hit = true
	SkillFx.play_at_point(get_parent(), "skill_shadow_bind",
		MoveDB.resolve_player("form_shadow_bind"), Vector2.RIGHT, _shadow_bind_pos, self)
	if hit:
		GameState.play_sfx("attack_hit")


## 明灭：灯笼收到贴身、影长归零，换来这段时间物理功法伤害上涨
func _shadow_cast_dim() -> bool:
	# 肉鸽「明灭·长」：持续变长（主模式 stat 恒 0）
	var dim_sec := SkillDB.SHADOW_DIM_SECONDS + RogueRun.stat("shadow_dim_sec")
	_shadow_dim_left = dim_sec
	apply_buff("shadow_dim", dim_sec)
	_lantern_lag_want = 0.0
	SkillFx.play_at_strike(self, "skill_shadow_dim",
		MoveDB.resolve_player("form_shadow_dim"), attack_dir, _shadow_feet())
	var bonus_pct := int((SkillDB.SHADOW_DIM_PHYS_BONUS
		+ RogueRun.stat("shadow_dim_pct") / 100.0) * 100.0)
	_show_float_text("明灭 · 影收身前，物理功法 +%d%%" % bonus_pct, Color(0.86, 0.82, 0.58))
	# 肉鸽「熄灯」：灯灭的一瞬炸开一圈（影长归零 = 力量释放，不是逃跑）
	var nova := RogueRun.stat("shadow_dim_nova")
	if nova > 0.0 and RogueRun.active:
		var nova_dmg := CharacterData.physical_attack() * nova
		var nova_hit := false
		for e in _array_enemy_units():
			if not is_instance_valid(e) or not e is Node2D:
				continue
			var off: Vector2 = (e as Node2D).global_position - global_position
			if off.length() > 300.0:
				continue
			_deal_direct_damage(e, nova_dmg, "physical", "", "skill_shadow_dim")
			if e.has_method("take_knockback") and off.length() > 1.0:
				e.call("take_knockback", off.normalized() * 180.0)
			nova_hit = true
		if nova_hit:
			SkillFx.play_at_point(get_parent(), "skill_shadow_dim",
				MoveDB.resolve_player("form_shadow_dim"), Vector2.RIGHT, global_position, self)
			_show_float_text("熄灯 · 影爆", Color(0.84, 0.78, 0.64))
	return true


## 暗场（影长归零）期间：物理功法伤害上涨
func _shadow_dim_mult(kind: String) -> float:
	if _shadow_dim_left <= 0.0 or kind != "physical":
		return 1.0
	return 1.0 + SkillDB.SHADOW_DIM_PHYS_BONUS + RogueRun.stat("shadow_dim_pct") / 100.0


## 分影：影身脱手，在身前代打几拍；期间影系三招哑火
func _shadow_cast_split(dir: Vector2) -> bool:
	# 肉鸽「分影·久」：影兽持续时间（主模式 stat 恒 0）
	var split_sec := SkillDB.SHADOW_SPLIT_SECONDS + RogueRun.stat("shadow_beast_sec")
	_shadow_split_left = split_sec
	_shadow_split_dmg = CharacterData.calc_skill_damage("skill_shadow_split", true, false) \
		* SkillDB.SHADOW_SPLIT_RATIO * (1.0 + RogueRun.stat("shadow_beast_pct") / 100.0)
	if _shadow_split_sweeper == null or not is_instance_valid(_shadow_split_sweeper):
		# 肉鸽「分影·快」：出手间隔
		var beast_gap := SkillDB.SHADOW_SPLIT_GAP \
			/ (1.0 + maxf(0.0, RogueRun.stat("shadow_beast_gap")) / 100.0)
		_shadow_split_sweeper = SHADOW_SWEEPER_SCRIPT.new()
		_shadow_split_sweeper.name = "PlayerTornShadow"
		get_parent().add_child(_shadow_split_sweeper)
		_shadow_split_sweeper.call("setup", self, _shadow_split_dmg,
			split_sec, beast_gap,
			Callable(self, "_shadow_sweep_channel"),
			SkillDB.get_damage_element("skill_shadow_split"))
		_shadow_split_sweeper.call("set_root_silhouette", SHADOW_ROOT_TEX, SHADOW_ROOT_SCALE)
	SkillFx.play_at_strike(self, "skill_shadow_split",
		MoveDB.resolve_player("form_shadow_split"), _shadow_dir(dir), _shadow_feet())
	_show_float_text("分影 · 影子代打", Color(0.58, 0.64, 0.88))
	return true


## 玩家侧脱手影身的走廊：每次指向最近的敌人
func _shadow_sweep_channel() -> Dictionary:
	var t := _nearest_boss(760.0)
	var origin := _shadow_feet()
	var dir := attack_dir.normalized() if attack_dir.length_squared() > 0.01 else Vector2.RIGHT
	if t != null:
		var to := t.global_position - origin
		if to.length_squared() > 36.0:
			dir = to.normalized()
	## 上界不再写死 520：那会把戴「执灯」时影长能到 676 的这一档硬生生截掉
	return {"origin": origin, "dir": dir,
		"length": maxf(_shadow_len() + 120.0, 180.0), "anchored": true}


## 长夜：把灯甩远，一段时间内影长上限暴涨
func _shadow_cast_longnight(dir: Vector2) -> bool:
	_shadow_long_left = SkillDB.SHADOW_LONGNIGHT_SECONDS
	var length := _shadow_len()
	_lantern_pos = global_position - _shadow_dir(dir) * (length + SkillDB.SHADOW_LONGNIGHT_THROW)
	var dmg := CharacterData.calc_skill_damage("skill_shadow_longnight", true, false)
	var hit := _shadow_damage_corridor(_shadow_feet(), _shadow_dir(dir), length,
		ShadowLaw.WIDTH_TIP * 1.1, dmg, "physical",
		SkillDB.get_damage_element("skill_shadow_longnight"), "skill_shadow_longnight")
	SkillFx.play_at_strike(self, "skill_shadow_longnight",
		MoveDB.resolve_player("form_shadow_longnight"), _shadow_dir(dir), _shadow_feet())
	_show_float_text("长夜 · 影长全开 %.1f 秒" % SkillDB.SHADOW_LONGNIGHT_SECONDS,
		Color(0.72, 0.80, 1.0))
	if hit:
		GameState.trigger_hit_stop()
		GameState.play_sfx("attack_hit")
	return true


## 走廊判定：从 origin 沿 dir 长 length、宽 width（与 ShadowVisual 画出来的完全一致）
## 长夜期间走廊整体加宽 —— 加在判定这一层，特效那一层见 _shadow_fit_form，两边同源
func _shadow_width_mult() -> float:
	return SkillDB.SHADOW_LONGNIGHT_WIDTH_MULT if _shadow_long_left > 0.0 else 1.0


func _shadow_damage_corridor(origin: Vector2, dir: Vector2, length: float, width: float,
		dmg: float, kind: String, elem: String, skill_id: String) -> bool:
	width *= _shadow_width_mult()
	var hit_any := false
	for raw in _array_enemy_units():
		var u := raw as Node2D
		if not ShadowLaw.corridor_contains(origin + dir * 8.0, dir, length,
				u.global_position, 18.0):
			continue
		_deal_direct_damage(u, dmg * _shadow_dim_mult(kind), kind, elem, skill_id)
		_apply_player_skill_debuff(u, skill_id)
		hit_any = true
	return hit_any


func _shadow_strike_fx(skill_id: String, form: Dictionary, dir: Vector2, length: float) -> void:
	var f := form.duplicate(true)
	f["range"] = length
	SkillFx.play_at_strike(self, skill_id, f, _shadow_dir(dir), _shadow_feet())


## 削影：本体扇形打完，影长够长时影尖再补一段
func _shadow_after_cast(skill_id: String, _form: Dictionary, dir: Vector2) -> void:
	if skill_id != "skill_shadow_cut":
		return
	var length := _shadow_len()
	## 长夜期间影尖那一截归你支配：削影必定双段，不再看影长够不够 150
	if _shadow_long_left > 0.0:
		length = maxf(length, SkillDB.SHADOW_CUT_TIP_EXTRA)
	if length < SkillDB.SHADOW_CUT_TIP_EXTRA:
		return
	var tip := _shadow_feet() + _shadow_dir(dir) * length
	var dmg := CharacterData.calc_skill_damage(skill_id, true, false) * 0.55 \
		* _shadow_dim_mult("physical")
	for raw in _array_enemy_units():
		var u := raw as Node2D
		if u.global_position.distance_to(tip) > 74.0 + 18.0:
			continue
		# 影尖那一刀与本体同元素：从表里取，不要再写死（写死过一次，MoveDB 改暗时它没跟着走）
		_deal_direct_damage(u, dmg, "physical",
				SkillDB.get_damage_element(skill_id), skill_id)
		_apply_player_skill_debuff(u, skill_id)
	SkillFx.play_at_point(get_parent(), "skill_shadow_reach",
		MoveDB.resolve_player("form_shadow_reach"), _shadow_dir(dir), tip, self)


## 被动「执灯」：完美闪避后影长直接拉满 2 秒（6 秒内最多一次）
func _shadow_passive_on_perfect_dodge() -> void:
	if _shadow_passive_cd > 0.0 or not _shadow_lamp_passive_on():
		return
	_shadow_passive_left = ShadowLaw.PASSIVE_DODGE_SECONDS
	_shadow_passive_cd = ShadowLaw.PASSIVE_DODGE_CD
	_show_float_text("执灯 · 影长拉满", Color(0.70, 0.78, 1.0))


## 影系功法的施放校验：影子脱手期间那三招哑火
func _shadow_cast_blocked(skill_id: String) -> bool:
	if _shadow_split_left > 0.0 and skill_id in SHADOW_SPLIT_BLOCKED \
			and skill_id != "skill_shadow_split":
		_show_float_text("影子正在代打，这一招用不了", UIKit.C_FLOAT_WARN)
		return true
	return false


## 退出副本 / 重开战斗：清掉灯笼与影带（与其他机制同口径）
func _shadow_reset() -> void:
	_shadow_dim_left = 0.0
	_shadow_long_left = 0.0
	_shadow_passive_left = 0.0
	_shadow_passive_cd = 0.0
	_shadow_split_left = 0.0
	_shadow_band_left = 0.0
	_shadow_bind_left = 0.0
	_shadow_bind_moving = false
	_lantern_lag_want = 0.0
	_lantern_speed_avg = 0.0
	_shadow_snap_len = 0.0
	_shadow_snap_left = 0.0
	_lantern_pos = Vector2.ZERO
	remove_buff("shadow_dim")
	if _shadow_split_sweeper != null and is_instance_valid(_shadow_split_sweeper):
		_shadow_split_sweeper.call("detach_and_free")
	_shadow_split_sweeper = null
	_shadow_clear_visuals()


# ===================== 叠纸 · 折影为径（照影界第 3 位，玩家侧，2026-11-02）=====================
## 玩家侧完整继承「空间连通」：自己裁一道痕 → 每一击同时判定两处 → 穿缝换来下一发更重。
## 几何口径全在 FoldLaw / FoldField —— BOSS 那边是「抢痕位」，你这边是「自己造痕」，
## 同一套镜像判定。**个人痕不依赖任何 BOSS 或关卡私有状态**，出照影界照样能用。
##
## 借痕的顺序：先试自己的个人痕（裁痕 / 位面法宝按出来的），再试场上那条（打叠纸时）。
## 一次形状里每个敌人最多吃一下（本体或镜像，取高的那一档），不重复结算。

const FOLD_FIELD_SCRIPT := preload("res://scripts/combat/fold_field.gd")
## 跨缝允许的出口误差 = 落斩半径 132 + 判定余量 18
const FOLD_STRIDE_LAND := 150.0

var _fold_field: Node2D = null        ## 自己的个人折痕（裁痕）
var _fold_cross_left: float = 0.0     ## 被动「量折」：穿缝后的强化窗口
var _fold_shroud_left: float = 0.0    ## 叠掩：护身纸剩余
var _fold_shroud_used: bool = false
var _fold_hit: Dictionary = {}        ## 本次形状已结算过的敌人 id
var _fold_ratio_override: float = -1.0


## 离某个点最近的敌人（默认离自己最近）：跨缝落点、双屏瞄准都靠它
func _fold_nearest_enemy() -> Node2D:
	return _fold_nearest_enemy_from(global_position)


func _fold_nearest_enemy_from(pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := 1.0e9
	for raw in _array_enemy_units():
		if raw == null or not is_instance_valid(raw) or not (raw is Node2D):
			continue
		var u := raw as Node2D
		if BossBase.is_unit_dead(u):
			continue
		var d := u.global_position.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = u
	return best


## 命中反馈：与影系同一口径（顿帧 + 命中音），不额外刷飘字
func _fold_hit_feedback() -> void:
	GameState.trigger_hit_stop()
	GameState.play_sfx("attack_hit")


## 被动「量折」是否生效（只认佩戴位，与执灯同口径）
func _fold_measure_on() -> bool:
	var gate := SkillDB.get_passive_by_effect("fold_measure")
	if gate.is_empty():
		return false
	return String(gate.get("skill_id", "")) in CharacterData.passive_skill_loadout


## 场上那条痕（叠纸立的；召唤叠纸助战时复用同一条）
func _fold_arena_field() -> Node2D:
	return FOLD_FIELD_SCRIPT.find(get_parent())


func _fold_has_field() -> bool:
	return _fold_field != null and is_instance_valid(_fold_field) \
		and (_fold_field as FoldField).active()


func _fold_feet() -> Vector2:
	return _shadow_feet()


## 逐条痕试镜像：返回敌人的对位落点，取不到就是 Vector2.INF
## ⚠ 目标自己把镜像那一面合上了（叠掩）时它没有对位面 —— 借不走
func _fold_image_of(u: Node2D) -> Vector2:
	if u == null or not is_instance_valid(u):
		return Vector2.INF
	if u.has_method("mirror_shielded") and bool(u.call("mirror_shielded")):
		return Vector2.INF
	var marked := false
	if u.has_method("has_debuff"):
		marked = bool(u.call("has_debuff", "fold_mark"))
	var fields: Array = []
	if _fold_has_field():
		fields.append(_fold_field)
	var arena := _fold_arena_field()
	if arena != null:
		fields.append(arena)
	for raw in fields:
		var fld := raw as FoldField
		if fld == null or not fld.active():
			continue
		if fld.personal and not fld.usable_by(self):
			continue
		var sp: Dictionary = fld.mirror_hit_span(global_position, u.global_position,
				FoldLaw.reach_for(fld.phase), marked)
		if not sp.is_empty():
			return FoldField.mirror_across(sp, u.global_position)
	return Vector2.INF


## 站在痕附近（被动「量折」的第二条收益）时，镜像那一面打折更少
func _fold_mirror_ratio() -> float:
	# 肉鸽「双面 / 折远 / 量折·准」：比例与近缝口径都能抬（主模式 stat 全 0）
	var base_ratio := FoldLaw.MIRROR_RATIO + RogueRun.stat("fold_ratio_add")
	var near_ratio := FoldLaw.MIRROR_RATIO_NEAR + RogueRun.stat("fold_ratio_add") \
		+ RogueRun.stat("fold_near_add")
	var near_seam := FoldLaw.NEAR_SEAM * (1.0 + RogueRun.stat("fold_range_pct") / 100.0)
	var near := false
	if _fold_has_field():
		near = (_fold_field as FoldField).fold_dist(global_position) <= near_seam
	if not near:
		var arena := _fold_arena_field()
		if arena != null:
			near = (arena as FoldField).fold_dist(global_position) <= near_seam
	return near_ratio if (near and _fold_measure_on()) else base_ratio


## 穿缝后的下一次攻击加重（一次性旗标，不是条、不攒层）
func _fold_cross_mult() -> float:
	if _fold_cross_left > 0.0 and _fold_measure_on():
		return 1.0 + FoldLaw.CROSS_BONUS + RogueRun.stat("fold_cross_pct") / 100.0
	return 1.0


## FoldField 把人从圆牌另一头送出来之后调用（没有这个方法的其他单位自动忽略）
func on_fold_crossed() -> void:
	if not _fold_measure_on():
		return
	_fold_cross_left = FoldLaw.CROSS_BONUS_TIME
	apply_buff("fold_measure", FoldLaw.CROSS_BONUS_TIME)
	# 肉鸽「穿缝·护」：出缝补一段无敌（主模式 stat 恒 0）
	var extra_inv := RogueRun.stat("fold_cross_inv")
	if extra_inv > 0.0:
		invincible_timer = maxf(invincible_timer, extra_inv)
	# 肉鸽「穿缝·痕」：出缝落点打一圈物理伤害
	if RogueRun.has_flag("fold_cross_damage"):
		var dmg := CharacterData.physical_attack() * 0.8
		for raw in _array_enemy_units():
			if not is_instance_valid(raw) or not (raw is Node2D):
				continue
			if (raw as Node2D).global_position.distance_to(global_position) > 140.0:
				continue
			_deal_direct_damage(raw, dmg, "physical", "", "fold_cross", false)


func _tick_fold(delta: float) -> void:
	if _fold_cross_left > 0.0:
		_fold_cross_left = maxf(0.0, _fold_cross_left - delta)
		if _fold_cross_left <= 0.0:
			remove_buff("fold_measure")
	if _fold_shroud_left > 0.0:
		_fold_shroud_left = maxf(0.0, _fold_shroud_left - delta)
		if _fold_shroud_left <= 0.0:
			_fold_shroud_used = false
			remove_buff("fold_shroud")
	if _zhehen_window > 0.0:
		_zhehen_window = maxf(0.0, _zhehen_window - delta)
	## 个人痕自己会到期 queue_free；这里只把引用清掉，不留一条「看不见的痕」
	if _fold_field != null and not is_instance_valid(_fold_field):
		_fold_field = null


## 叠掩的首次受击减伤（在 take_damage 的抗性之后读，读作「最终伤害再乘一档」）
func _fold_shroud_mult() -> float:
	if _fold_shroud_left > 0.0 and not _fold_shroud_used:
		_fold_shroud_used = true
		return 1.0 - SkillDB.FOLD_SHROUD_GUARD
	return 1.0


## 折影招式的起手：把「这一击有几面」先说清楚
func _fold_precast(skill_id: String, _dir: Vector2) -> void:
	if skill_id == "skill_fold_stride":
		var p := _fold_nearest_enemy()
		if p != null and _fold_seam_exit(p) != Vector2.INF:
			_show_float_text("跨缝 · 对侧出", Color(0.90, 0.90, 0.82))
		else:
			_show_float_text("无缝可跨 · 直进", Color(0.80, 0.80, 0.76))
	elif skill_id == "skill_fold_press":
		var t := _fold_nearest_enemy()
		if t != null and _fold_image_of(t) != Vector2.INF:
			_show_float_text("折痕两面 · 落掌印", Color(0.92, 0.92, 0.86))


## 沿痕类招式的射程：有痕才走得满，没痕缩短 —— 裁痕才是把射程拿全的那把钥匙
func _fold_fit_form(skill_id: String, form: Dictionary) -> Dictionary:
	if skill_id != "skill_fold_trace" and skill_id != "skill_fold_tear":
		return form
	var f := form.duplicate(true)
	if _fold_has_field() or _fold_arena_field() != null:
		return f
	if skill_id == "skill_fold_trace":
		f["range"] = SkillDB.FOLD_TRACE_DASH * 0.7
	else:
		f["range"] = SkillDB.FOLD_TEAR_LINE * 0.55
	return f


## 结算入口：返回 true 表示这一招已由折影层自己打完，通用层不要再画
func _fold_handle_cast(skill_id: String, dir: Vector2) -> bool:
	if not skill_id.begins_with("skill_fold_"):
		return false
	_fold_hit.clear()
	match skill_id:
		"skill_fold_press":
			return _fold_cast_press(dir)
		"skill_fold_trace":
			return _fold_cast_trace(dir)
		"skill_fold_stride":
			return _fold_cast_stride(dir)
		"skill_fold_seam":
			return _fold_cast_seam(dir)
		"skill_fold_shroud":
			return _fold_cast_shroud()
		"skill_fold_tear":
			return _fold_cast_tear(dir)
		"skill_fold_twin":
			return _fold_cast_twin(dir)
		"skill_fold_triple":
			return _fold_cast_triple(dir)
	return false


# ---------- 八式 ----------

## 按纸：身前扇形 + 对侧镜像同帧落掌印
func _fold_cast_press(dir: Vector2) -> bool:
	var form := MoveDB.resolve_player("form_fold_press")
	var dmg := CharacterData.calc_skill_damage("skill_fold_press", true, false) \
		* _fold_cross_mult()
	var hit := _fold_damage_fan(_fold_feet(), dir, float(form.get("range", 178.0)),
			float(form.get("angle", 104.0)), dmg, "physical",
			String(form.get("damage_element", "water")), "skill_fold_press")
	SkillFx.play_at_strike(self, "skill_fold_press", form, dir, _fold_feet())
	_consume_fold_cross()
	if hit:
		_fold_hit_feedback()
	return true


## 循痕：有痕就贴着痕滑，无痕就朝输入方向突进
func _fold_cast_trace(dir: Vector2) -> bool:
	var form := MoveDB.resolve_player("form_fold_trace")
	var along := dir.normalized()
	var sp := _fold_span_for_shot()
	if not sp.is_empty():
		var cd := FoldLaw.crease_dir(sp.get("a", Vector2.ZERO) as Vector2,
				sp.get("b", Vector2.ZERO) as Vector2)
		var t := _fold_nearest_enemy()
		if t != null and cd.dot(t.global_position - global_position) < 0.0:
			cd = -cd
		along = cd
	var old := global_position
	var land := _array_clamp_point(old + along * SkillDB.FOLD_TRACE_DASH)
	global_position = land
	var f := form.duplicate(true)
	f["range"] = old.distance_to(land)
	var dmg := CharacterData.calc_skill_damage("skill_fold_trace", true, false) \
		* _fold_cross_mult()
	SkillFx.play_at_strike(self, "skill_fold_trace", f, along, old)
	TreasureFx.play_swap(get_parent(), old, land)
	var hit := _fold_damage_corridor(old, along, old.distance_to(land),
			float(form.get("width", 132.0)), dmg, "physical",
			String(form.get("damage_element", "wind")), "skill_fold_trace")
	_consume_fold_cross()
	if hit:
		_fold_hit_feedback()
	return true


## 跨缝：钻这头的圆牌、从那头的圆牌出来并落斩；无痕时退化为直线突进
func _fold_cast_stride(dir: Vector2) -> bool:
	var form := MoveDB.resolve_player("form_fold_stride")
	var dmg := CharacterData.calc_skill_damage("skill_fold_stride", true, false) \
		* _fold_cross_mult()
	var t := _fold_nearest_enemy()
	var exit := _fold_seam_exit(t)
	var old := global_position
	var land := exit
	if exit == Vector2.INF:
		## 没有对位区可跨：退化成直线突进，不许空放
		land = _array_clamp_point(old + dir.normalized() * SkillDB.FOLD_STRIDE_FALLBACK)
	else:
		land = _array_clamp_point(exit)
	global_position = land
	on_fold_crossed()
	TreasureFx.play_swap(get_parent(), old, land)
	SkillFx.play_at_strike(self, "skill_fold_stride", form, dir, land)
	var hit := _fold_damage_circle(land, float(form.get("range", 132.0)), dmg,
			"physical", String(form.get("damage_element", "water")), "skill_fold_stride")
	_consume_fold_cross()
	if hit:
		_fold_hit_feedback()
		# 肉鸽「连折」：穿缝途中碰到人 → 跨缝立刻转好，可以马上再穿一次
		if RogueRun.has_flag("fold_cross_reset"):
			skill_cooldowns.erase("skill_fold_stride")
			_show_float_text("连折 · 跨缝重置", Color(0.90, 0.92, 0.98))
	# 肉鸽「折返」：起点也折一道（顶掉旧痕，折影同时只有一道个人折痕）
	if RogueRun.has_flag("fold_cross_again") and old.distance_to(land) > 8.0:
		_fold_spawn_personal_seam(old, land - old)
	return true


## 裁痕：在身前裁出一道只属于自己的折痕 —— 机制的便携入口，本身不打伤害
func _fold_cast_seam(dir: Vector2) -> bool:
	var form := MoveDB.resolve_player("form_fold_pressmark")
	if get_parent() == null:
		return false
	_fold_spawn_personal_seam(global_position, dir)
	_show_float_text("裁痕 · 你的折痕 %.1f 秒"
			% (FoldLaw.PLAYER_SEAM_TIME + RogueRun.stat("fold_field_sec")),
			Color(0.90, 0.92, 0.98))
	SkillFx.play_at_strike(self, "skill_fold_seam", form, dir, _fold_feet())
	return true


## 铺一道属于玩家的折痕（会先顶掉旧的）——裁痕与「折返」共用同一段构造
func _fold_spawn_personal_seam(at: Vector2, dir: Vector2) -> void:
	var host := get_parent()
	if host == null:
		return
	if _fold_field != null and is_instance_valid(_fold_field):
		(_fold_field as FoldField).dismiss()
	var fld: Node2D = FOLD_FIELD_SCRIPT.new()
	fld.name = "PlayerFold"
	host.add_child(fld)
	(fld as FoldField).build_personal(self, at,
			dir.normalized() if dir.length_squared() > 0.0001 else attack_dir,
			FoldLaw.PLAYER_SEAM_LEN * (1.0 + RogueRun.stat("fold_field_radius") / 100.0),
			FoldLaw.PLAYER_SEAM_TIME + RogueRun.stat("fold_field_sec"))
	_fold_field = fld


## 叠掩：折纸护身 —— 首次受击大减，这段时间镜像判定对你关闭（对面的手够不着你）
func _fold_cast_shroud() -> bool:
	var form := MoveDB.resolve_player("form_fold_shroud")
	_fold_shroud_left = SkillDB.FOLD_SHROUD_SECONDS
	_fold_shroud_used = false
	apply_buff("fold_shroud", SkillDB.FOLD_SHROUD_SECONDS)
	_show_float_text("叠掩 · 合上一面 %.1f 秒" % SkillDB.FOLD_SHROUD_SECONDS,
			Color(0.88, 0.90, 0.94))
	SkillFx.play_at_strike(self, "skill_fold_shroud", form, Vector2.RIGHT, _fold_feet())
	return true


## 碎痕：沿痕撕一条长直线；消耗个人痕换来镜像那一面全额
func _fold_cast_tear(dir: Vector2) -> bool:
	var form := MoveDB.resolve_player("form_fold_tear")
	var along := dir.normalized()
	var sp := _fold_span_for_shot()
	if not sp.is_empty():
		var cd := FoldLaw.crease_dir(sp.get("a", Vector2.ZERO) as Vector2,
				sp.get("b", Vector2.ZERO) as Vector2)
		var t := _fold_nearest_enemy()
		if t != null and cd.dot(t.global_position - global_position) < 0.0:
			cd = -cd
		along = cd
	var consume := _fold_has_field()
	var span := SkillDB.FOLD_TEAR_LINE if (consume or _fold_arena_field() != null) \
		else SkillDB.FOLD_TEAR_LINE * 0.55
	var f := form.duplicate(true)
	f["range"] = span
	if consume:
		(_fold_field as FoldField).dismiss()
		_fold_field = null
		_show_float_text("碎痕 · 撕开自己那道", Color(0.94, 0.88, 0.66))
	var dmg := CharacterData.calc_skill_damage("skill_fold_tear", true, false) \
		* _fold_cross_mult()
	SkillFx.play_at_strike(self, "skill_fold_tear", f, along, _fold_feet())
	## 撕开自己那道痕 = 换来镜像那一面不再打折：临时把比例抬到全额
	if consume:
		_fold_ratio_override = 1.0
	var hit := _fold_damage_corridor(_fold_feet(), along, span,
			float(form.get("width", 220.0)), dmg, "spell",
			String(form.get("damage_element", "thunder")), "skill_fold_tear")
	_fold_ratio_override = -1.0
	_consume_fold_cross()
	if hit:
		_fold_hit_feedback()
	return true


## 双屏：从痕的两端圆牌各打一线
func _fold_cast_twin(dir: Vector2) -> bool:
	var form := MoveDB.resolve_player("form_fold_twin")
	var sp := _fold_span_for_shot()
	var base_dmg := CharacterData.calc_skill_damage("skill_fold_twin", true, false) \
		* _fold_cross_mult()
	var reach := float(form.get("range", 460.0))
	var width := float(form.get("width", 96.0))
	var hit_any := false
	var ends: Array = []
	if not sp.is_empty():
		ends = [sp.get("a", Vector2.ZERO) as Vector2, sp.get("b", Vector2.ZERO) as Vector2]
	else:
		## 没有痕就退化成身前两路（不许空放，也不许出现「这招在别处完全不能用」）
		var n := Vector2(-dir.y, dir.x)
		ends = [_fold_feet() + n * 46.0, _fold_feet() - n * 46.0]
	for raw in ends:
		var aim := raw as Vector2
		var to := dir.normalized()
		var t := _fold_nearest_enemy_from(aim)
		if t != null:
			to = (t.global_position - aim).normalized()
		SkillFx.play_at_point(get_parent(), "skill_fold_twin", form, to, aim, self)
		_fold_hit.clear()
		if _fold_damage_corridor(aim, to, reach, width,
				base_dmg * SkillDB.FOLD_TWIN_RATIO, "spell",
				String(form.get("damage_element", "water")), "skill_fold_twin"):
			hit_any = true
	_consume_fold_cross()
	if hit_any:
		_fold_hit_feedback()
	return true


## 三重落纸：三个区依次落掌（有个人痕就三区都是真的；没有也照样落三面）
func _fold_cast_triple(dir: Vector2) -> bool:
	var form := MoveDB.resolve_player("form_fold_triple")
	var dmg := CharacterData.calc_skill_damage("skill_fold_triple", true, false) \
		* _fold_cross_mult()
	var t := _fold_nearest_enemy()
	var center := _fold_feet() + dir.normalized() * 150.0
	if t != null:
		center = t.global_position
	var radius := float(form.get("range", 168.0))
	var zones: Array = [center]
	var fld := _fold_shooting_field()
	if fld != null:
		for raw in fld.spans:
			var sp: Dictionary = raw
			zones.append(FoldLaw.mirror(sp.get("a", Vector2.ZERO) as Vector2,
					sp.get("b", Vector2.ZERO) as Vector2, center))
	## 凑满三个区：缺的按 120° 绕中心补（读起来仍然是「三面同落」）
	var k := 0
	while zones.size() < 3 and k < 6:
		var ang := TAU * float(k) / 3.0
		zones.append(center + Vector2(cos(ang), sin(ang)) * radius * 1.5)
		k += 1
	var hit_any := false
	for raw in zones:
		var zp := raw as Vector2
		SkillFx.play_at_point(get_parent(), "skill_fold_triple", form, dir, zp, self)
		if _fold_damage_circle(zp, radius, dmg * SkillDB.FOLD_TRIPLE_RATIO, "spell",
				String(form.get("damage_element", "water")), "skill_fold_triple"):
			hit_any = true
	_consume_fold_cross()
	if hit_any:
		_fold_hit_feedback()
	return true


# ---------- 结算层：本体 或 对位落点，一次形状每人最多吃一下 ----------

func _fold_apply(u: Node2D, inside: bool, folded: bool, dmg: float, kind: String,
		elem: String, skill_id: String) -> bool:
	if u == null or not is_instance_valid(u):
		return false
	if not inside and not folded:
		return false
	if _fold_hit.has(u.get_instance_id()):
		return false
	_fold_hit[u.get_instance_id()] = true
	var ratio := _fold_mirror_ratio()
	if _fold_ratio_override > 0.0:
		ratio = _fold_ratio_override
	var amount := dmg if inside else dmg * ratio
	_deal_direct_damage(u, amount, kind, elem, skill_id)
	_apply_player_skill_debuff(u, skill_id)
	# 肉鸽「镜像归元」：只在镜像落点命中时回精力（主模式 stat 恒 0）
	if not inside and RogueRun.stat("fold_mirror_stam") > 0.0:
		stamina = minf(max_stamina, stamina + RogueRun.stat("fold_mirror_stam"))
		_update_stamina_bar()
	return true


func _fold_damage_fan(origin: Vector2, dir: Vector2, reach: float, angle_deg: float,
		dmg: float, kind: String, elem: String, skill_id: String) -> bool:
	var d := dir.normalized()
	var cos_half := cos(deg_to_rad(angle_deg * 0.5))
	var hit_any := false
	for raw in _array_enemy_units():
		var u := raw as Node2D
		var inside := _in_fan_shape(u.global_position, origin, d, reach, cos_half)
		var img := _fold_image_of(u)
		var folded := not inside and img != Vector2.INF \
			and _in_fan_shape(img, origin, d, reach, cos_half)
		if _fold_apply(u, inside, folded, dmg, kind, elem, skill_id):
			hit_any = true
	return hit_any


func _fold_damage_circle(center: Vector2, radius: float, dmg: float, kind: String,
		elem: String, skill_id: String) -> bool:
	var hit_any := false
	for raw in _array_enemy_units():
		var u := raw as Node2D
		var inside := u.global_position.distance_to(center) <= radius + 18.0
		var img := _fold_image_of(u)
		var folded := not inside and img != Vector2.INF \
			and img.distance_to(center) <= radius + 18.0
		if _fold_apply(u, inside, folded, dmg, kind, elem, skill_id):
			hit_any = true
	return hit_any


func _fold_damage_corridor(origin: Vector2, dir: Vector2, length: float, width: float,
		dmg: float, kind: String, elem: String, skill_id: String) -> bool:
	var d := dir.normalized()
	if d.length_squared() < 0.0001:
		return false
	var hit_any := false
	for raw in _array_enemy_units():
		var u := raw as Node2D
		var inside := _in_corridor_shape(u.global_position, origin + d * 8.0, d, length, width)
		var img := _fold_image_of(u)
		var folded := not inside and img != Vector2.INF \
			and _in_corridor_shape(img, origin + d * 8.0, d, length, width)
		if _fold_apply(u, inside, folded, dmg, kind, elem, skill_id):
			hit_any = true
	return hit_any


func _in_fan_shape(at: Vector2, origin: Vector2, dir: Vector2, reach: float,
		cos_half: float) -> bool:
	var to := at - origin
	var dd := to.length()
	if dd > reach + 18.0:
		return false
	return not (dd > 1.0 and dir.dot(to / dd) < cos_half)


func _in_corridor_shape(at: Vector2, origin: Vector2, dir: Vector2, length: float,
		width: float) -> bool:
	var to := at - origin
	var forward := to.dot(dir)
	if forward < -12.0 or forward > length + 18.0:
		return false
	return absf(to.cross(dir)) <= width * 0.5 + 18.0


# ---------- 痕的取用 ----------

## 我这条（优先个人痕，其次场上那条）—— 用来沿痕突进 / 双屏两端
func _fold_span_for_shot() -> Dictionary:
	if _fold_has_field():
		return (_fold_field as FoldField).nearest(global_position)
	var arena := _fold_arena_field()
	if arena != null:
		return (arena as FoldField).nearest(global_position)
	return {}


## 三重落纸借哪条痕展开镜像区
func _fold_shooting_field() -> FoldField:
	if _fold_has_field():
		return _fold_field as FoldField
	return _fold_arena_field() as FoldField


## 跨缝的出口：优先自己的圆牌（个人痕），再试场上的
func _fold_seam_exit(t: Node2D) -> Vector2:
	for fld in [_fold_field, _fold_arena_field()]:
		if fld == null or not is_instance_valid(fld):
			continue
		var f := fld as FoldField
		if not f.active():
			continue
		var exit := f.seam_exit_for(global_position)
		if exit == Vector2.INF:
			continue
		## 出口必须真的落在这一记落斩的半径里（含判定余量），否则宁可退化成直线突进 ——
		## 以前按 FOLD_STRIDE_FALLBACK(220) 放行，而落斩只有 132+18，跨过去照样打空。
		if t != null and exit.distance_to(t.global_position) > FOLD_STRIDE_LAND:
			continue
		return exit
	return Vector2.INF


func _consume_fold_cross() -> void:
	_fold_cross_left = 0.0
	remove_buff("fold_measure")


## 退出副本 / 重开战斗：收掉个人痕与旗标（与其他机制同口径）
func _fold_reset() -> void:
	_fold_cross_left = 0.0
	_fold_shroud_left = 0.0
	_fold_shroud_used = false
	_reckoning_reset()
	_stop_blade_form()
	_fold_ratio_override = -1.0
	_zhehen_window = 0.0
	_fold_hit.clear()
	remove_buff("fold_measure")
	remove_buff("fold_shroud")
	if _fold_field != null and is_instance_valid(_fold_field):
		(_fold_field as FoldField).dismiss()
	_fold_field = null


# ---------- 位面法宝「照影·迟照符」：延迟结算 + 操作抹账（2026-11-07）----------

func _start_delayed_reckoning_treasure(item: Dictionary, tpl: Dictionary) -> void:
	var tid := String(tpl.get("treasure_id", ""))
	var left := summon_cooldown_left(tid)
	if left > 0.0:
		_show_float_text("法宝冷却中（%.0f 秒）" % left, Color(0.85, 0.6, 0.35))
		return
	if _reckoning_left > 0.0:
		_show_float_text("迟照仍在生效", UIKit.C_FLOAT_WARN)
		return
	var stats := ItemDB.treasure_active_stats(item, tpl)
	if stats.is_empty():
		return
	var cost := float(stats.get("mana", 20.0))
	if mana < cost:
		_show_float_text("灵力不足（迟照符需要 %d 点）" % int(round(cost)),
			UIKit.C_FLOAT_WARN)
		return
	if not spend_mana(cost):
		return
	_reckoning_id = tid
	_reckoning_left = float(stats.get("duration", 4.0))
	_reckoning_pool = 0.0
	_reckoning_wipes = 0
	_reckoning_wipe_pct = clampf(float(stats.get("wipe_pct", 0.30)), 0.0, 1.0)
	_reckoning_max_wipes = maxi(1, int(stats.get("max_wipes", 3)))
	_summon_cooldowns[tid] = float(stats.get("cooldown", 38.0))
	_show_float_text("迟照 · %.1f 秒内伤害暂缓" % _reckoning_left, Color(0.90, 0.92, 0.98))


## 每物理帧推进窗口；到期一次性结算剩余账
func _tick_reckoning(delta: float) -> void:
	if _reckoning_left <= 0.0:
		return
	_reckoning_left = maxf(0.0, _reckoning_left - delta)
	if _reckoning_left <= 0.0:
		_settle_reckoning()


## 一次成功操作（完美闪避 / 完美弹反 / 打断起手）抹掉池内固定比例
func _reckoning_on_wipe() -> void:
	if _reckoning_left <= 0.0 or _reckoning_pool <= 0.0:
		return
	if _reckoning_wipes >= _reckoning_max_wipes:
		return
	_reckoning_wipes += 1
	_reckoning_pool = maxf(0.0, _reckoning_pool * (1.0 - _reckoning_wipe_pct))
	_show_float_text("迟照 · 抹去 %d%%，待结 %d" % [
		int(round(_reckoning_wipe_pct * 100.0)), int(round(_reckoning_pool))],
		Color(0.72, 0.90, 0.98))


## 结算：只扣血 + 判死，不重放顿帧 / 扣精力 / 削剑意 / 击退。
## ⚠ 先清池再扣血：_die() 里会再调 _reckoning_reset()，避免二次结算。
func _settle_reckoning() -> void:
	var owed := _reckoning_pool
	_reckoning_reset()
	if owed <= 0.0 or is_dead:
		return
	hp = maxf(0.0, hp - owed)
	took_damage_this_battle = true
	health_changed.emit(hp, max_hp)
	_update_health_bar()
	_play_hit_flash()
	DamageNumber.spawn(get_parent(), global_position, owed, DamageNumber.Kind.PHYSICAL)
	_show_float_text("迟照 · 结算 %d" % int(round(owed)), Color(0.94, 0.72, 0.62))
	if hp <= 0.0:
		_die()


func _reckoning_reset() -> void:
	_reckoning_id = ""
	_reckoning_left = 0.0
	_reckoning_pool = 0.0
	_reckoning_wipes = 0


# ---------- 位面法宝「凡界·换锋符」：普攻三段改远程穿透剑气 ----------

func _start_blade_form_treasure(item: Dictionary, tpl: Dictionary) -> void:
	var tid := String(tpl.get("treasure_id", ""))
	var left := summon_cooldown_left(tid)
	if left > 0.0:
		_show_float_text("法宝冷却中（%.0f 秒）" % left, Color(0.85, 0.6, 0.35))
		return
	if _blade_form_left > 0.0:
		_show_float_text("换锋仍在生效", UIKit.C_FLOAT_WARN)
		return
	var stats := ItemDB.treasure_active_stats(item, tpl)
	if stats.is_empty():
		return
	var cost := float(stats.get("mana", 15.0))
	if mana < cost:
		_show_float_text("灵力不足（换锋符需要 %d 点）" % int(round(cost)),
			UIKit.C_FLOAT_WARN)
		return
	if not spend_mana(cost):
		return
	_blade_form_id = tid
	_blade_form_left = float(stats.get("duration", 5.0))
	_blade_form_range = maxf(1.0, float(stats.get("range", 320.0)))
	_blade_form_width = maxf(1.0, float(stats.get("width", 96.0)))
	_summon_cooldowns[tid] = float(stats.get("cooldown", 22.0))
	_show_float_text("换锋 · %.1f 秒剑气" % _blade_form_left, Color(0.72, 0.90, 0.98))


func _tick_blade_form(delta: float) -> void:
	if _blade_form_left > 0.0:
		_blade_form_left = maxf(0.0, _blade_form_left - delta)
		if _blade_form_left <= 0.0:
			_stop_blade_form()


func _stop_blade_form() -> void:
	_blade_form_id = ""
	_blade_form_left = 0.0


## 换锋符命中帧：判定从近战扇形换成前方长条，逐只结算即「穿透」。
## 伤害仍用原本三段连击的系数（终结段更高），不改数值、不叠层、不留痕。
func _perform_blade_form_hit() -> void:
	var dmg := CharacterData.calc_physical_damage(is_finisher_attack,
		has_buff("parry_power"))
	var hit_any := _damage_bosses_in_rect(attack_dir, _blade_form_range,
		_blade_form_width, dmg, "physical")
	_spawn_blade_form_qi(is_finisher_attack)
	if not hit_any:
		return
	_attack_camera_punch()
	if is_finisher_attack:
		GameState.trigger_hit_stop(FINISHER_HIT_STOP, true)
	else:
		GameState.trigger_hit_stop()
	GameState.play_sfx("attack_hit")
	GameState.play_sfx("attack_impact")
	_consume_parry_damage_buff()


## 剑气表现：贴图 320×96 横向，节点中心放在「玩家 → 终点」的中点，1:1 覆盖判定长条。
## ⚠ 外观只走 ArtDB.EFFECTS.fx_blade_form_qi，换图不用改这里。
func _spawn_blade_form_qi(is_finisher: bool) -> void:
	var mid := global_position + _body_center() + attack_dir * (_blade_form_range * 0.5)
	FxPlayer.spawn(self, "fx_blade_form_qi", {
		"global_position": mid,
		"rotation": attack_dir.angle(),
		"lifetime": 0.26 if is_finisher else 0.20,
	})


# ===================== 叠纸掉落装备的用途差（2026-11-02）=====================
## 两件都改「怎么打」，不改词条数字：纸错剑给普攻第二个落点，折痕佩给位移一次折位。

const ZHICUO_OFFSET_PX := 120.0     ## 纸错剑：第二落点在目标身后这么远
const ZHICUO_OFFSET_RADIUS := 90.0  ## 纸错剑：第二落点的半径
const ZHICUO_OFFSET_RATIO := 0.6    ## 纸错剑：第二落点 = 本段的 60%
const ZHEHEN_WINDOW := 0.3          ## 折痕佩：受击后的折位窗口
const ZHEHEN_EXTRA_PX := 90.0       ## 折痕佩：终点额外折出去这么远

var _zhehen_window: float = 0.0


## 纸错剑：终结段命中谁，就在谁身后 120 补一记 60% 的圆形落点。
## 半径 90 + 判定余量 18 < 120 ⇒ 同一个目标不会被这两段同时吃到，是真·夹击不是翻倍。
func _zhicuo_second_landing(hit_dir: Vector2, reach: float, dmg: float) -> void:
	if is_dead:
		return
	var d := hit_dir.normalized()
	var cos_half := cos(deg_to_rad(70.0 * 0.5))
	for raw in _array_enemy_units():
		if raw == null or not is_instance_valid(raw) or not (raw is Node2D):
			continue
		var u := raw as Node2D
		var to: Vector2 = u.global_position - global_position
		var dist := to.length()
		if dist > reach + 18.0 or (dist > 1.0 and d.dot(to / dist) < cos_half):
			continue
		var at := u.global_position + d * ZHICUO_OFFSET_PX
		_damage_bosses_in_shape(d, ZHICUO_OFFSET_RADIUS, 0.0, dmg * ZHICUO_OFFSET_RATIO,
				"physical", "", true, "", 0.0, at)
		SkillFx.play_at_point(get_parent(), "skill_fold_stride",
				MoveDB.resolve_player("form_fold_stride"), d, at, self)


## 折痕佩：受击后 0.3 秒内的下一次位移技立即转好，并且终点朝行进方向再折 90。
## 现游戏所有位移都是直线冲刺 —— 这件给的是「挨了打还能折一下再出来」这个用途。
func _zhehen_fold_escape(skill_id: String, distance: float) -> float:
	if _zhehen_window <= 0.0:
		return distance
	_zhehen_window = 0.0
	if skill_id != "" and skill_cooldowns.has(skill_id):
		skill_cooldowns[skill_id] = 0.0
	_show_float_text("折痕 · 位移折位", Color(0.90, 0.90, 0.80))
	return distance + ZHEHEN_EXTRA_PX


# =====================================================================
# 符箓 · 四符连携（2026-11-10 重做 · 试炼之路专属）
# =====================================================================
## 设计案：docs/符箓流派重做_设计案.md
## 四张主符占 Q/E/R/T（槽值 `talisman:<base_id>`）：施放耗灵力、进独立冷却。
## ⚠ 连携不是开局自带（2026-11-11 用户定）：三选一选到「连携」卡
##   （tal_chain_on）才解锁 —— 施放成功后随机连携符囊/主符里另一张，
##   70% 效率、不耗灵、不进 CD、不再连锁、回 2 灵力。
## ⚠ 局外七元灵符仍走 use_talisman()：这里只处理 RogueRun.active 的分支。
## ⚠ 伤害一律走 _tal_hit_one（两仪 / 肉鸽全局乘区 / 命中挂减益都在那条钩子链上），
##   直接 take_damage 会绕开所有乘区（旧版踩过）。
## ⚠ 品质倍率只在 _run_tal_cast 里乘一次；op 里不要再各乘一遍。

const RUN_TAL_SKILL_TAG := "run_talisman"
const RUN_TAL_REACH := 520.0
const RUN_TAL_LINE_WIDTH := 60.0
const RUN_TAL_CHAIN_REACH := 300.0
const RUN_TAL_DOT_INTERVAL := 1.0
const RUN_TAL_FROST_KEEP := 8.0
## 蓄势卡：这么久没施符就加成下一张
const RUN_TAL_HOLD_TIME := 8.0

## 护盾（磐石符 / 旧符罩共用同一池；盾碎触发 nova）
var _tal_shield := 0.0
var _tal_shield_left := 0.0
var _tal_shield_max := 0.0


## 冷却：base_id -> 可再用的毫秒时间戳（用时间戳而不是倒计时，暂停时不走表）
var _run_tal_ready: Dictionary = {}
## 下一张符的额外倍率（风羽 / 影遁）
var _run_tal_boost := 0.0
var _run_tal_boost_left := 0.0
## 折光：存伤反弹
var _run_tal_reflect_left := 0.0
var _run_tal_reflect_cap := 0.0
var _run_tal_reflect_stored := 0.0
var _run_tal_reflect_coeff := 1.0
## 霜：instance_id -> {node, stacks, left}
var _run_tal_frost: Dictionary = {}
## 霜甲：受击时给攻击者叠霜
var _run_tal_thorn_left := 0.0
var _run_tal_thorn_slow := 25.0
var _run_tal_invuln_left := 0.0
var _run_tal_shield_nova := 0.0
## 蓄势：多久没施符
var _run_tal_hold := 0.0
## 持续伤害：{node, dmg_per_sec, left, acc, element}
var _run_tal_dots: Array = []
## 连携统计（探针读它，别改成只写日志）
var _run_tal_last_chain_element := ""
var _run_tal_last_chain_id := ""
var _run_tal_chain_count := 0
var _run_tal_cast_count := 0


# ---------------------- 对外接口 ----------------------

func run_talisman_cd_left(talisman_id: String) -> float:
	var base := TalismanDB.base_of(talisman_id)
	if base == "":
		return 0.0
	# 绝笔（11-12 新增卡）：冷却直接归零。判据放在**读数侧**而不是只放在 _run_tal_arm，
	# 否则选卡之前已经武装好的旧冷却还会继续挡人，玩家会觉得「选了卡没反应」。
	if RogueRun.has_flag("tal_no_cd"):
		return 0.0
	var ready := int(_run_tal_ready.get(base, 0))
	return maxf(0.0, float(ready - Time.get_ticks_msec()) / 1000.0)


## 灰化原因（空 = 现在能放）。战斗技能栏每帧读它。
func run_talisman_block(slot_value: String) -> String:
	if is_dead:
		return ""
	var base := CharacterData.talisman_slot_item_id(slot_value)
	if base == "" or TalismanDB.base_def(base).is_empty():
		return ""
	if not RogueRun.talisman_owned(base):
		return "未解锁"
	if run_talisman_cd_left(base) > 0.0:
		return "符还没画好"
	if _run_tal_mana_cost(base) > mana and not RogueRun.has_flag("tal_blood_ink") \
			and not RogueRun.has_flag("tal_free"):
		return "灵力不足"
	return ""


func can_cast_run_talisman(talisman_id: String) -> bool:
	return run_talisman_block(CharacterData.talisman_slot_value(talisman_id)) == ""


## Q/E/R/T 里按到符：走这里（不是 use_talisman 的局外路径）
func use_run_talisman(talisman_id: String) -> bool:
	return _run_tal_cast(talisman_id, 1.0, false)


func _run_tal_mana_cost(base_id: String) -> float:
	if RogueRun.has_flag("tal_free"):
		return 0.0
	return TalismanDB.mana_cost(base_id)


## 符阵 / 符灵在自己的脚本里取法强：走这个接口，别让它们直接读 CharacterData
## （试炼里「法强」被 rogue 修正过，绕过去会算少一截）
func _run_tal_spell_attack() -> float:
	return CharacterData.spell_attack()


## 正式施放。via_chain = 连携出来的那一张：不付费、不进冷却、不再连锁。
func _run_tal_cast(talisman_id: String, eff: float, via_chain: bool) -> bool:
	if is_dead or is_action_blocked():
		return false
	if not RogueRun.active:
		return false
	var base := TalismanDB.base_of(talisman_id)
	if base == "" or TalismanDB.base_def(base).is_empty():
		return false
	if not RogueRun.talisman_owned(base):
		return false
	if not via_chain and run_talisman_cd_left(base) > 0.0:
		return false
	if not via_chain and not _run_tal_pay(_run_tal_mana_cost(base)):
		return false

	var tier := RogueRun.talisman_tier(base)
	var variant := RogueRun.talisman_variant_of(base)
	var def := TalismanDB.get_def(variant if variant != "" else base)
	if def.is_empty():
		return false

	# 倍率：品质 → 连携效率 → 实战加成（贯注 / 蓄势 / 风羽 / 影遁）
	var mult := eff * TalismanDB.QUALITY_MULT[clampi(tier, 0, TalismanDB.QUALITY_MULT.size() - 1)]
	if not via_chain:
		if RogueRun.has_flag("tal_focus"):
			mult *= 1.15
		if RogueRun.has_flag("tal_hold") and _run_tal_hold >= RUN_TAL_HOLD_TIME:
			mult *= 1.5
			_show_float_text("蓄势 · 符成", UIKit.C_GREAT)
		mult *= (1.0 + _run_tal_boost)
		_run_tal_boost = 0.0
		_run_tal_boost_left = 0.0
	elif RogueRun.has_flag("tal_focus"):
		mult *= 0.90
	# 绝笔的代价：主符与连携符**一律**打八折。放在 if/elif 之外是必须的 ——
	# 放进 `not via_chain` 里会让连携出来的那一张绕过惩罚，选了卡就变成纯收益。
	if RogueRun.has_flag("tal_no_cd"):
		mult *= 0.80
	_run_tal_hold = 0.0
	_run_tal_cast_count += 1

	var element := TalismanDB.element_of(base)
	var color: Color = ArtDB.element_color(element)
	# 施符演出：手里那张符浮起 → 碎裂 → 元素光射向目标。
	# ⚠ 纯表现，不参与结算：伤害在下一行同步算完，视觉滞后 0.1 秒玩家感知不到。
	var fx_target := _run_tal_target()
	var fx_aim := global_position + _run_tal_dir(null) * 200.0
	if fx_target != null:
		fx_aim = (fx_target as Node2D).global_position
	RunTalFx.cast(self, base, element, fx_aim, via_chain)
	_show_float_text("%s" % TalismanDB.display_name(variant if variant != "" else base), color)
	_run_tal_ops((def.get("ops", []) as Array), tier, mult)

	if not via_chain:
		_run_tal_arm(base)
		# 连携是可选强化（2026-11-11 用户定）：没选「连携」卡就四符各自独立
		if RogueRun.has_flag("tal_chain_on"):
			_run_tal_chain_from(base)
	# 试炼局内真实施放一张符（连携段不算新的一次使用）。
	# ⚠ 当前**没有消费者**：11-11 把第 12 条任务改回主模式口径（`talisman_used`），
	#   因为试炼里没有制符台、而且这条只在选了符箓流派的那一局才可能发。
	#   保留这个埋点作为试炼侧的遥测钩子，将来做「试炼流派成就」直接接。
	Tutorial.note("run_talisman_used")
	return true


## 灵力支付：无墨免费 / 血墨以血代灵
func _run_tal_pay(cost: float) -> bool:
	if cost <= 0.0 or RogueRun.has_flag("tal_free"):
		return true
	if mana >= cost:
		return spend_mana(cost)
	if RogueRun.has_flag("tal_blood_ink") and max_hp > 0.0:
		var missing := cost - mana
		var hp_cost := max_hp * missing * 1.5 / 100.0
		if hp - hp_cost <= 1.0:
			_show_float_text("气血不足以代灵", UIKit.C_FLOAT_WARN)
			return false
		spend_mana(mana)
		hp = maxf(1.0, hp - hp_cost)
		health_changed.emit(hp, max_hp)
		_update_health_bar()
		_show_float_text("血墨 · 以血代灵", Color(0.86, 0.36, 0.34))
		return true
	_show_float_text("灵力不足（需要 %d 点）" % int(cost), UIKit.C_FLOAT_WARN)
	return false


func _run_tal_arm(base_id: String) -> void:
	# 绝笔：干脆不武装，免得 `_run_tal_ready` 里留一堆永远用不上的时间戳
	if RogueRun.has_flag("tal_no_cd"):
		return
	var cd := TalismanDB.cooldown(base_id)
	# tal_cd_pct：疾书 -15 / 无墨 +25，正负相加后一次性乘
	cd *= maxf(0.25, 1.0 + RogueRun.stat("tal_cd_pct") / 100.0)
	_run_tal_ready[base_id] = Time.get_ticks_msec() + int(round(cd * 1000.0))


func _run_tal_gain_mana(amount: float) -> void:
	if amount <= 0.0:
		return
	mana = minf(max_mana, mana + amount)
	mana_changed.emit(mana, max_mana)


# ---------------------- 连携 ----------------------

## 连携：随机抽一张「不是本张、不在冷却」的符，按 70% 打出去。
## 抽不到就本次不连携（符囊只有本张时很正常）。
func _run_tal_chain_from(from_base: String) -> void:
	if not RogueRun.active:
		return
	var pool: Array = RogueRun.talisman_pool()
	var diff_only := RogueRun.has_flag("tal_chain_diff")
	var from_element := TalismanDB.element_of(from_base)
	var cands: Array = []
	for raw in pool:
		var b := String(raw)
		if b == "" or b == from_base:
			continue
		if run_talisman_cd_left(b) > 0.0:
			continue
		if diff_only and TalismanDB.element_of(b) == from_element:
			continue
		cands.append(b)
	if cands.is_empty():
		return

	var count := 1
	if RogueRun.has_flag("tal_chain_double"):
		count += 1
	if RogueRun.has_flag("tal_chain_echo") and randf() < 0.25:
		count += 1
	var eff := 1.0 if RogueRun.has_flag("tal_chain_full") else TalismanDB.CHAIN_EFF
	var done := 0
	for _i in count:
		if cands.is_empty():
			break
		var pick := String(cands.pick_random())
		cands.erase(pick)
		var element := TalismanDB.element_of(pick)
		var m := eff
		# 同气：连续两次连携同元素，第二张 +80%
		if RogueRun.has_flag("tal_chain_same") and element == _run_tal_last_chain_element:
			m *= 1.8
			_show_float_text("同气 · 连携加成", UIKit.C_GREAT)
		_run_tal_last_chain_element = element
		if _run_tal_cast(pick, m, true):
			done += 1
			_run_tal_chain_count += 1
			_run_tal_last_chain_id = pick
			_run_tal_gain_mana(TalismanDB.CHAIN_MANA_GAIN + RogueRun.stat("tal_chain_mana"))
	if done > 0:
		_show_float_text("连携 ×%d" % done, Color(0.94, 0.86, 0.62))
		if RogueRun.has_flag("tal_chain_cd"):
			_run_tal_ready[from_base] = int(_run_tal_ready.get(from_base, 0)) - 1500


# ---------------------- 目标与方向 ----------------------

func _run_tal_target() -> Node2D:
	return _nearest_boss(RUN_TAL_REACH)


func _run_tal_dir(target: Node2D) -> Vector2:
	if target != null and is_instance_valid(target):
		var d := (target as Node2D).global_position - global_position
		if d.length_squared() > 1.0:
			return d.normalized()
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input.length_squared() > 0.01:
		return input.normalized()
	return Vector2.RIGHT


func _run_tal_aim(target: Node2D) -> Vector2:
	if target != null and is_instance_valid(target):
		return _boss_aim_point(target)
	return global_position + _run_tal_dir(target) * 160.0


# ---------------------- ops 执行 ----------------------

func _run_tal_ops(ops: Array, tier: int, mult: float) -> void:
	for raw in ops:
		var op: Dictionary = raw
		_run_tal_op(op, tier, mult)


func _run_tal_op(op: Dictionary, tier: int, mult: float) -> void:
	match String(op.get("op", "")):
		"sacrifice":
			var pct := float(op.get("hp_pct", 8.0))
			hp = maxf(1.0, hp - max_hp * pct / 100.0)
			health_changed.emit(hp, max_hp)
			_update_health_bar()
		"damage":
			_run_tal_op_damage(op, tier, mult)
		"debuff":
			var target := _run_tal_target()
			if target == null:
				return
			var chance := float(op.get("chance", 1.0)) + float(op.get("chance_per_tier", 0.0)) * tier
			if randf() <= chance:
				_run_tal_debuff(target, String(op.get("id", "")),
					float(op.get("time", 1.0)) + float(op.get("time_per_tier", 0.0)) * tier)
		"dot":
			var t := _run_tal_target()
			if t == null:
				return
			_run_tal_add_dot(t, CharacterData.spell_attack() * float(op.get("coeff", 0.0)) * mult,
				float(op.get("time", 3.0)), String(op.get("element", "")))
		"regen":
			_talisman_water_left = float(op.get("time", 8.0))
			_talisman_water_tick = 0.0
			_talisman_water_per_sec = max_hp * float(op.get("pct", 1.5)) * mult / 100.0
			apply_buff("talisman_water", _talisman_water_left)
			RunTalFx.shell(self, "regen", "water", _talisman_water_left)
			_show_float_text("回春", Color(0.48, 0.82, 0.94))
		"haste":
			_talisman_wind_left = float(op.get("time", 10.0))
			CharacterData.set_attribute_mod(TALISMAN_WIND_SOURCE,
				{AttributeDB.ATTR_SPEED_PCT: {"flat": float(op.get("pct", 30.0))}})
			apply_buff("talisman_wind", _talisman_wind_left)
			RunTalFx.shell(self, "haste", "wind", _talisman_wind_left)
			_show_float_text("风疾", Color(0.62, 0.88, 0.78))
		"guard":
			_talisman_stone_left = float(op.get("time", 12.0))
			_talisman_stone_reduce = (float(op.get("reduce", 25.0))
				+ float(op.get("reduce_per_tier", 0.0)) * tier) / 100.0
			_talisman_stone_hits = int(op.get("hits", 3)) + int(op.get("hits_per_tier", 0)) * tier
			CharacterData.set_attribute_mod(TALISMAN_STONE_SOURCE,
				{AttributeDB.ATTR_SPEED_PCT: {"flat": -float(op.get("speed_down", 15.0))}})
			apply_buff("talisman_stone", _talisman_stone_left)
			RunTalFx.shell(self, "stone", "earth", _talisman_stone_left)
			_show_float_text("石附 · 挡 %d 次" % _talisman_stone_hits, Color(0.78, 0.68, 0.52))
		"shield":
			_run_tal_shield_add(max_hp * float(op.get("pct", 15.0)) / 100.0,
				float(op.get("time", 12.0)), float(op.get("nova", 0.0)) * mult)
			RunTalFx.shell(self, "shield", "earth", float(op.get("time", 12.0)))
			_show_float_text("石甲", Color(0.82, 0.72, 0.54))
		"reflect":
			_run_tal_reflect_left = float(op.get("time", 3.0))
			_run_tal_reflect_cap = max_hp * float(op.get("cap_pct", 30.0)) / 100.0
			_run_tal_reflect_stored = 0.0
			_run_tal_reflect_coeff = float(op.get("coeff", 1.0)) * mult
			RunTalFx.shell(self, "reflect", "light", _run_tal_reflect_left)
			_show_float_text("折光 · 存伤", Color(1.0, 0.92, 0.66))
		"frost":
			var t2 := _run_tal_target()
			if t2 != null:
				_run_tal_frost_apply(t2, float(op.get("slow", 25.0)),
					float(op.get("time", 6.0)), int(op.get("stacks", 3)),
					float(op.get("freeze", 1.8)))
		"frost_armor":
			_run_tal_thorn_left = float(op.get("time", 8.0))
			_run_tal_thorn_slow = float(op.get("slow", 25.0))
			RunTalFx.shell(self, "frost", "ice", _run_tal_thorn_left)
			_show_float_text("霜甲", Color(0.70, 0.90, 1.0))
		"zone":
			_run_tal_spawn_zone(op, mult)
		"spirit":
			_run_tal_spawn_spirit(op, mult)
		"blink":
			_run_tal_blink(op)
		"dash":
			_run_tal_dash(op)
		"cleanse":
			_run_tal_cleanse(int(op.get("count", 1)))
		"invuln":
			_run_tal_invuln_left = float(op.get("time", 1.0))
			apply_buff("run_tal_invuln", _run_tal_invuln_left)
			RunTalFx.shell(self, "shield", "light", _run_tal_invuln_left)
			_show_float_text("光护", Color(1.0, 0.94, 0.70))
		"heal":
			restore_health(max_hp * float(op.get("pct", 15.0)) * mult / 100.0)
		"dispel":
			_run_tal_dispel(float(op.get("radius", 180.0)))


func _run_tal_op_damage(op: Dictionary, _tier: int, mult: float) -> void:
	var coeff := float(op.get("coeff", 1.0)) * mult
	var dmg := CharacterData.spell_attack() * coeff
	var element := String(op.get("element", ""))
	var lifesteal := float(op.get("lifesteal", 0.0))
	var target := _run_tal_target()
	if target == null:
		return
	var aim := _run_tal_aim(target)

	# 命中演出（一次 op 只播一次）：放在 delay 判断之后、shape 分支之前，
	# ⚠ 别塞进 shape 的 for 循环 —— 多段伤害会在同一点叠成一坨白光。
	var shape := String(op.get("shape", "single"))
	var radius := float(op.get("radius", 80.0))

	# 延迟引爆：先挂持续伤害，到点再炸（焚心 / 冰封）
	if float(op.get("delay", 0.0)) > 0.0:
		if float(op.get("dot_coeff", 0.0)) > 0.0:
			_run_tal_add_dot(target,
				CharacterData.spell_attack() * float(op.get("dot_coeff", 0.0)) * mult,
				float(op.get("dot_time", 3.0)), element)
		_run_tal_delayed(float(op.get("delay", 0.0)), aim,
			float(op.get("radius", 90.0)), dmg, element)
		return

	_play_tal_hit_fx(get_parent(), shape, element, aim, radius, target)

	match shape:
		"aoe":
			var times := int(op.get("count", 1))
			for _i in times:
				for raw in _run_tal_enemies_near(aim, radius):
					_run_tal_hit(raw, dmg, element, lifesteal)
				if float(op.get("spread", 0.0)) > 0.0:
					aim += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) \
						* float(op.get("spread", 0.0)) * 0.5
		"fan":
			var dir := _run_tal_dir(target)
			var half := deg_to_rad(float(op.get("angle", 70.0)) * 0.5)
			var hits := _tal_targets(dir, RUN_TAL_REACH, half)
			if hits.is_empty():
				hits = [target]
			for raw in hits:
				_run_tal_hit(raw, dmg, element, lifesteal)
			# 只有单个目标时补几段，别让「万剑」在 BOSS 身上变成一张弱化符
			if hits.size() == 1:
				var extra := maxi(0, int(op.get("count", 1)) / 2 - 1)
				for _i in extra:
					_run_tal_hit(target, dmg, element, lifesteal)
		"line":
			var from := global_position
			var to := from + _run_tal_dir(target) * 700.0
			for raw in _array_enemy_units():
				var p: Vector2 = (raw as Node2D).global_position
				var closest := Geometry2D.get_closest_point_to_segment(p, from, to)
				if closest.distance_to(p) <= RUN_TAL_LINE_WIDTH:
					_run_tal_hit(raw, dmg, element, lifesteal)
		"chain":
			var hit_ids: Array = []
			var current: Node = target
			var cur_dmg := dmg
			for _i in int(op.get("jumps", 2)) + 1:
				if current == null or not is_instance_valid(current):
					break
				_run_tal_hit(current, cur_dmg, element, lifesteal)
				hit_ids.append(current.get_instance_id())
				cur_dmg *= (1.0 - float(op.get("falloff", 0.2)))
				var next: Node = null
				var best := RUN_TAL_CHAIN_REACH
				for raw in _array_enemy_units():
					if hit_ids.has(raw.get_instance_id()):
						continue
					var d := (raw as Node2D).global_position.distance_to(
						(current as Node2D).global_position)
					if d < best:
						best = d
						next = raw
				# 连锁引线：每跳之间一道细光，画出「电流顺着跳过去」的路径
				if next != null:
					RunTalFx.beam(get_parent(), (current as Node2D).global_position,
						(next as Node2D).global_position, element, 22.0)
				current = next
		_:
			_run_tal_hit(target, dmg, element, lifesteal)


## 命中演出：形状决定画什么，半径决定圈多大（玩家靠圈的大小读出「这张符打多远」）。
## ⚠ 一次 op 调一次。塞进 shape 的 for 循环里会在同一坐标叠出好几层白光。
func _play_tal_hit_fx(host: Node, shape: String, element: String, aim: Vector2,
		radius: float, target: Node2D) -> void:
	if host == null or not host.is_inside_tree():
		return
	match shape:
		"line":
			RunTalFx.beam(host, global_position,
				global_position + _run_tal_dir(target) * 700.0, element, 46.0)
			RunTalFx.impact(host, aim, element, maxf(radius, 70.0), false)
		"fan":
			RunTalFx.beam(host, global_position, aim, element, 34.0)
			RunTalFx.impact(host, aim, element, 96.0, false)
		"chain":
			RunTalFx.impact(host, aim, element, 66.0, false)
		"aoe":
			RunTalFx.impact(host, aim, element, maxf(radius, 60.0), radius > 110.0)
		_:
			RunTalFx.impact(host, aim, element, 48.0, false)


func _run_tal_hit(target: Node, dmg: float, element: String, lifesteal: float) -> void:
	if dmg <= 0.0 or not is_instance_valid(target):
		return
	_tal_hit_one(target, dmg, "elemental", RUN_TAL_SKILL_TAG, element)
	if lifesteal > 0.0:
		restore_health(dmg * lifesteal)


func _run_tal_enemies_near(at: Vector2, radius: float) -> Array:
	var out: Array = []
	for raw in _array_enemy_units():
		if (raw as Node2D).global_position.distance_to(at) <= radius:
			out.append(raw)
	return out


func _run_tal_debuff(target: Node, id: String, time: float) -> void:
	if target == null or id == "" or not is_instance_valid(target):
		return
	if target.has_method("apply_debuff"):
		target.call("apply_debuff", id, time)
	elif target.has_method("stun_for") and id == "stun":
		target.call("stun_for", time)


func _run_tal_add_dot(target: Node, dmg_per_sec: float, time: float, element: String) -> void:
	if not is_instance_valid(target) or dmg_per_sec <= 0.0:
		return
	_run_tal_dots.append({
		"node": target, "dps": dmg_per_sec, "left": time, "acc": 0.0, "element": element,
	})


func _run_tal_delayed(delay: float, at: Vector2, radius: float, dmg: float,
		element: String) -> void:
	var timer := get_tree().create_timer(delay, false)
	timer.timeout.connect(_run_tal_delayed_blast.bind(at, radius, dmg, element))


func _run_tal_delayed_blast(at: Vector2, radius: float, dmg: float, element: String) -> void:
	if not is_inside_tree():
		return
	RunTalFx.impact(get_parent(), at, element, maxf(radius, 70.0), true)
	for raw in _run_tal_enemies_near(at, radius):
		_run_tal_hit(raw, dmg, element, 0.0)


func _run_tal_frost_apply(target: Node, slow: float, time: float, need: int, freeze: float) -> void:
	var id := target.get_instance_id()
	var rec: Dictionary = _run_tal_frost.get(id, {})
	var stacks := int(rec.get("stacks", 0)) + 1
	_run_tal_debuff(target, "array_slow", time)
	if stacks >= maxi(1, need):
		stacks = 0
		_run_tal_debuff(target, "frozen", freeze)
		_show_float_text("冻结", Color(0.66, 0.90, 1.0))
	_run_tal_frost[id] = {"node": target, "stacks": stacks, "left": RUN_TAL_FROST_KEEP}


func _run_tal_shield_add(amount: float, time: float, nova: float) -> void:
	if amount <= 0.0:
		return
	_tal_shield += amount
	_tal_shield_max = maxf(_tal_shield_max, _tal_shield)
	_tal_shield_left = time
	_run_tal_shield_nova = nova


func _talisman_shield_break() -> void:
	if _run_tal_shield_nova <= 0.0:
		return
	var dmg := CharacterData.spell_attack() * _run_tal_shield_nova
	for raw in _run_tal_enemies_near(global_position, 220.0):
		_run_tal_hit(raw, dmg, "earth", 0.0)
	RunTalFx.impact(get_parent(), global_position, "earth", 220.0, true)
	_show_float_text("石甲 · 碎裂反击", Color(1.0, 0.78, 0.46))
	_run_tal_shield_nova = 0.0


func _run_tal_blink(op: Dictionary) -> void:
	var target := _run_tal_target()
	if target == null:
		return
	var from := (target as Node2D).global_position
	var behind := global_position - from
	if behind.length_squared() < 1.0:
		behind = Vector2.RIGHT
	global_position = from + behind.normalized() * 60.0
	_apply_boost(float(op.get("boost", 60.0)), float(op.get("boost_time", 3.0)))
	_show_float_text("影遁", Color(0.70, 0.52, 0.86))


func _run_tal_dash(op: Dictionary) -> void:
	var dir := _run_tal_dir(_run_tal_target())
	global_position += dir * float(op.get("dist", 180.0))
	_apply_boost(float(op.get("boost", 45.0)), float(op.get("boost_time", 3.0)))
	_show_float_text("风羽", Color(0.62, 0.90, 0.80))


func _apply_boost(pct: float, time: float) -> void:
	_run_tal_boost = maxf(_run_tal_boost, pct / 100.0)
	_run_tal_boost_left = time


func _run_tal_cleanse(count: int) -> void:
	var removed := 0
	for raw_key in debuffs.keys():
		if removed >= count:
			break
		var key := String(raw_key)
		debuffs.erase(key)
		remove_buff(key)
		removed += 1
	if removed > 0:
		_show_float_text("洗髓 · 清 %d 个负面" % removed, Color(0.60, 0.88, 0.94))


func _run_tal_dispel(radius: float) -> void:
	for raw in get_tree().get_nodes_in_group("boss_projectile"):
		var p := raw as Node2D
		if p == null or not is_instance_valid(p):
			continue
		if bool(p.get("source_is_ally")):
			continue
		if p.global_position.distance_to(global_position) <= radius:
			p.queue_free()
	_show_float_text("罡风 · 清弹", Color(0.66, 0.90, 0.82))


## 清场：符阵 / 符灵挂在**场景**上（不跟 player 走），换层或退出试炼时必须主动收掉，
## 否则上一层的雷狱会留在原地继续打空气 / 继续给玩家回血。
func _run_tal_clear_summons() -> void:
	for group in ["talisman_zone", "talisman_spirit"]:
		for raw in get_tree().get_nodes_in_group(group):
			var n := raw as Node
			if n != null and is_instance_valid(n):
				n.queue_free()


func _run_tal_spawn_zone(op: Dictionary, mult: float) -> void:
	var target := _run_tal_target()
	var at := _run_tal_aim(target)
	if String(op.get("tag", "")) in ["regen", "absorb"]:
		at = global_position
	var host := get_parent()
	if host == null or not host.is_inside_tree():
		return
	var zone := TalismanZone.new()
	host.add_child(zone)
	var el := String(op.get("element", ""))
	zone.setup(self, at, op, mult, ArtDB.element_color(el))
	# 落成用单环：heavy 会再叠一圈 1.28 倍的大环，加上符阵本身已经很满了
	RunTalFx.impact(host, at, el, float(op.get("radius", 90.0)) * 1.15, false)


func _run_tal_spawn_spirit(op: Dictionary, mult: float) -> void:
	var host := get_parent()
	if host == null or not host.is_inside_tree():
		return
	var spirit := TalismanSpirit.new()
	host.add_child(spirit)
	# ⚠ 偏移要落在**侧后方**：正上方会被玩家头顶的血条与飘字糊住（截图验过）
	var el := String(op.get("element", "wood"))
	spirit.setup(self, global_position + Vector2(46.0, -30.0), op, mult,
		ArtDB.element_color(el))
	RunTalFx.impact(host, global_position + Vector2(46.0, -30.0), el, 74.0, false)


# ---------------------- 每帧 ----------------------

func _run_tal_tick(delta: float) -> void:
	if _run_tal_boost_left > 0.0:
		_run_tal_boost_left = maxf(0.0, _run_tal_boost_left - delta)
		if _run_tal_boost_left <= 0.0:
			_run_tal_boost = 0.0
	if _run_tal_invuln_left > 0.0:
		_run_tal_invuln_left = maxf(0.0, _run_tal_invuln_left - delta)
		if _run_tal_invuln_left <= 0.0:
			remove_buff("run_tal_invuln")
	if _run_tal_thorn_left > 0.0:
		_run_tal_thorn_left = maxf(0.0, _run_tal_thorn_left - delta)
	if _run_tal_reflect_left > 0.0:
		_run_tal_reflect_left = maxf(0.0, _run_tal_reflect_left - delta)
		if _run_tal_reflect_left <= 0.0:
			_run_tal_reflect_burst()
	if _tal_shield_left > 0.0:
		_tal_shield_left = maxf(0.0, _tal_shield_left - delta)
		if _tal_shield_left <= 0.0:
			_tal_shield = 0.0
			_tal_shield_max = 0.0
	_run_tal_hold += delta
	_run_tal_tick_dots(delta)
	_run_tal_tick_frost(delta)


func _run_tal_reflect_burst() -> void:
	var dmg := maxf(_run_tal_reflect_stored,
		CharacterData.spell_attack() * _run_tal_reflect_coeff)
	_run_tal_reflect_stored = 0.0
	if dmg <= 0.0:
		return
	for raw in _run_tal_enemies_near(global_position, 200.0):
		_run_tal_hit(raw, dmg, "light", 0.0)
	_show_float_text("折光 · 反照", Color(1.0, 0.94, 0.70))


func _run_tal_tick_dots(delta: float) -> void:
	if _run_tal_dots.is_empty():
		return
	var keep: Array = []
	for raw in _run_tal_dots:
		var d: Dictionary = raw
		var node = d.get("node")
		if not is_instance_valid(node):
			continue
		d["left"] = float(d.get("left", 0.0)) - delta
		if float(d.get("left", 0.0)) <= 0.0:
			continue
		d["acc"] = float(d.get("acc", 0.0)) + delta
		while float(d.get("acc", 0.0)) >= RUN_TAL_DOT_INTERVAL:
			d["acc"] = float(d.get("acc", 0.0)) - RUN_TAL_DOT_INTERVAL
			_run_tal_hit(node, float(d.get("dps", 0.0)) * RUN_TAL_DOT_INTERVAL,
				String(d.get("element", "")), 0.0)
		keep.append(d)
	_run_tal_dots = keep


func _run_tal_tick_frost(delta: float) -> void:
	if _run_tal_frost.is_empty():
		return
	var keep: Dictionary = {}
	for raw_key in _run_tal_frost.keys():
		var rec: Dictionary = _run_tal_frost[raw_key]
		rec["left"] = float(rec.get("left", 0.0)) - delta
		if float(rec.get("left", 0.0)) <= 0.0:
			continue
		if not is_instance_valid(rec.get("node")):
			continue
		keep[raw_key] = rec
	_run_tal_frost = keep


## 受击钩子：折光存伤（在 take_damage 里调）
func _run_tal_store_damage(amount: float) -> void:
	if _run_tal_reflect_left > 0.0 and amount > 0.0:
		_run_tal_reflect_stored = minf(_run_tal_reflect_cap,
			_run_tal_reflect_stored + amount)


## 受击钩子：霜甲给攻击者叠霜（在 take_damage 里调）
func _run_tal_on_hit(source: Node) -> void:
	if _run_tal_thorn_left <= 0.0 or source == null or not is_instance_valid(source):
		return
	if source.has_method("apply_debuff"):
		source.call("apply_debuff", "array_slow", 6.0)
		_show_float_text("霜甲 · 反霜", Color(0.70, 0.90, 1.0))


# ---------------------- 复位与旧接口 ----------------------

func _talisman_tick(delta: float) -> void:
	_run_tal_tick(delta)


func _talisman_reset() -> void:
	_tal_shield = 0.0
	_tal_shield_left = 0.0
	_tal_shield_max = 0.0
	_run_tal_ready.clear()
	_run_tal_boost = 0.0
	_run_tal_boost_left = 0.0
	_run_tal_reflect_left = 0.0
	_run_tal_reflect_cap = 0.0
	_run_tal_reflect_stored = 0.0
	_run_tal_frost.clear()
	_run_tal_thorn_left = 0.0
	_run_tal_invuln_left = 0.0
	_run_tal_shield_nova = 0.0
	_run_tal_hold = 0.0
	_run_tal_dots.clear()
	_run_tal_last_chain_element = ""
	_run_tal_last_chain_id = ""
	_run_tal_chain_count = 0
	_run_tal_cast_count = 0
	_run_tal_clear_summons()


## 伤害统计的来源标签（2026-11-12）：普攻算「平A」，功法取功法名
func _meter_tag(skill_id: String) -> String:
	if skill_id == "":
		return "平A"
	var nm := SkillDB.get_skill_name(skill_id)
	return nm if nm != "" and nm != skill_id else skill_id


## 单个目标的伤害结算（与 _damage_bosses_in_shape 里那段钩子链保持一致）
## ⚠ 连携 / 符阵 / 符灵全都走这里，绕开它就会吃不到两仪与肉鸽全局乘区。
func _tal_hit_one(boss: Node, dmg: float, kind: String, skill_id: String,
		element: String = "") -> void:
	if dmg <= 0.0 or not is_instance_valid(boss):
		return
	if not boss is Node2D or not boss.has_method("take_damage"):
		return
	var final_dmg := _yinyang_modify_damage(boss, kind, dmg, skill_id)
	final_dmg = _rogue_modify_damage(final_dmg, boss, kind, skill_id)
	# 符箓统一记一行「符箓」：连携 / 符阵 / 符灵都汇到这里，分到具体哪张符反而看不清
	DamageMeter.push("符箓" if skill_id.begins_with("talisman") else _meter_tag(skill_id))
	boss.take_damage(final_dmg, self, kind, element)
	_apply_player_skill_debuff(boss, skill_id)
	_rogue_apply_hit_debuff(boss, skill_id)


## 扇形里的目标（与 _damage_bosses_in_shape 同一套受击球判定：每球独立算夹角）
func _tal_targets(dir: Vector2, reach: float, half_angle: float) -> Array:
	var out: Array = []
	var from := global_position
	var d := dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	for b in _array_enemy_units():
		var spheres: Array = [Vector3(0.0, 0.0, 0.0)]
		if b.has_method("hit_spheres"):
			spheres = b.call("hit_spheres")
		for sp in spheres:
			var sv: Vector3 = sp
			if sv.z <= 0.0:
				continue
			var to_sp: Vector2 = (b as Node2D).global_position + Vector2(sv.x, sv.y) - from
			var dist := to_sp.length()
			if dist > reach + sv.z:
				continue
			if dist > 1.0 and d.dot(to_sp / dist) < cos(half_angle):
				continue
			out.append(b)
			break
	return out


func _tal_hp_ratio(node: Node) -> float:
	var h = node.get("hp")
	var m = node.get("max_hp")
	if h == null or m == null or float(m) <= 0.0:
		return 1.0
	return float(h) / float(m)


func _tal_fx(key: String, at: Vector2, rot: float, radius: float, sweep: float) -> void:
	var host := get_parent()
	if host == null or not host.is_inside_tree():
		return
	var params := {"position": at, "rotation": rot}
	if radius > 0.0:
		params["radius"] = radius
	if sweep > 0.0:
		params["sweep_deg"] = sweep
	FxPlayer.spawn(host, key, params)
