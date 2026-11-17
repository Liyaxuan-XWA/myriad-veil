class_name MatchDB
extends RefCounted
## 卡片召唤自走棋 · 规则常量与棋子面板折算表（纯数据，不碰节点、不读输入）
##
## 设计口径来自 2026-11-02 与用户的逐题访谈：
##   对手 = 单人 vs AI，但规则层双方对称、全部决策走可序列化指令（以后接 SDK 联机不改写）；
##   激活敌方卡 = 翻开即召唤，BOSS 归原主、在其出生格进场；
##   胜负 = 清场制，12 张翻完前不判负，翻完后再打最多 120 秒、第 60 秒起时间加速；
##   棋子 = 原 BOSS + PieceAdapter，只在格子上出生、之后自由走动。

# ===================== 对局参数 =====================

const TEAM_COUNT := 2
const DECK_SIZE := 6                     ## 每人 6 张卡
const BOARD_COLS := 6
const BOARD_ROWS := 6
## 每格边长（像素）。这条不是手感参数而是硬约束：
## `BossBase.PHASE_TRANSITION_PUSH = 520` 是转阶段击退距离，格子太小的话
## 一次转阶段就把棋子顶到墙上反复弹（`combat_arena.gd:1766` 的钳制是 half-48）。
## 6 格 × 260 = 1560，半宽 780 > 520 + 48，留得住。
const CELL_PX := 260.0

const PICK_SECONDS := 10.0               ## 暗选窗口（决定翻哪张牌的时间）
const ROUND_SECONDS := 15.0              ## 每轮战斗窗口（两次翻牌之间的间隔，11-03 由 20 调到 15）
const FINAL_LIMIT_SECONDS := 120.0       ## 全部翻完后的上限
const ACCEL_START_SECONDS := 60.0        ## 从第 60 秒开始推时间流速
const ACCEL_MAX_SCALE := 2.0             ## 到 120 秒时线性推到 2.0

## 锁定阶段：玩家自己指定 1 反 1 正，剩下 4 张由系统随机 2 反 2 正
const LOCK_OWN_DOWN := 1
const LOCK_OWN_UP := 1

## 结算页的「结束方式」—— 内部枚举是给规则层看的，玩家看得懂的是这一列。
## key 必须与 `match_state.gd` 里 `_end()` 实传的 reason 一字不差；
## 漏一条不会报错，只会在结算页把英文原样吐给玩家，所以 `probe_match_text` 做全量对账。
const END_REASON_TEXT := {
	"no_legal_move": "双方都无子可放",
	"mutual_annihilation": "同时清场",
	"clear_field": "清场",
	"timeout_equal": "超时且血量持平",
	"timeout_hp": "超时，剩余血量更多者胜",
}

# ===================== 真实面板快照 =====================
## 由 `tools/dump_match_panel.tscn` 从真实场景 / SecretWorldDB 区域表导出，别手抄。
## ⚠ 第四只核心在区域表里 core_boss_id = "world_core_yuanying"，
##   而 CodexDB.CORE_BOSS_IDS 用的是 "world_core_shihou" —— 同一只 BOSS 两张表两个名字。
##   本表按**卡包口径**（world_core_shihou）登记，`probe_match_rules` 会把两种叫法都对账，
##   免得以后有人按区域表读不到面板还以为数值丢了。
const PANEL_SNAPSHOT := {
	"boss_huyao": {"hp": 800, "atk": 40},
	"boss_01": {"hp": 1000, "atk": 100},
	"boss_01_c": {"hp": 1500, "atk": 20},
	"boss_02": {"hp": 4000, "atk": 24},
	"boss_02_b": {"hp": 4400, "atk": 26},
	"boss_02_c": {"hp": 5000, "atk": 33},
	"boss_03": {"hp": 13000, "atk": 90},
	"boss_03_b": {"hp": 15500, "atk": 96},
	"boss_03_c": {"hp": 20500, "atk": 108},
	"boss_04": {"hp": 40000, "atk": 180},
	"boss_04_b": {"hp": 56000, "atk": 205},
	"boss_04_c": {"hp": 62000, "atk": 238},
	"world_core_lianqi": {"hp": 2200, "atk": 50},
	"world_core_zhuji": {"hp": 4000, "atk": 62},
	"world_core_jiedan": {"hp": 20000, "atk": 100},
	"world_core_shihou": {"hp": 44000, "atk": 112},   # 区域表叫 world_core_yuanying
}
## 区域表口径 → 卡包口径，只有这一只需要翻译
const PANEL_ALIAS := {"world_core_yuanying": "world_core_shihou"}

# ===================== 折算：把 62 倍面板差压进 ±20% =====================
## 塔层 12 位 + 核心 4 位的原始 HP 跨 800 → 62000（**77 倍**）、攻击 20 → 238。
## 直接照搬进棋盘，「选哪 6 张」第一局就会被数值碾平，暗牌与顺序全部作废。
## 所以这里按**设计角色**给系数，而不是按原始面板开根号 —— 差异交给机制、元素、射程，
## 面板只保证「坦克比刺客肉一点」这种程度。系数待千局模拟后再调。
## 棋子血量基准。2026-11-03 用户「都死太快了」→ 由 10000 提到 30000（×3）。
## 只动基准、不动 `FACTORS`，所以各只之间的相对肉度（观澜 1.18 / 刀客 0.84）原样保留。
## ⚠ 伤害侧没跟着改，所以单挑击杀时间也 ×3：配合 15 秒一轮，
##   一只棋子现在要两三轮才倒得下，场上会明显攒得更满、更容易打到终局阶段。
const PIECE_HP_BASE := 30000.0
const PIECE_DPS_BASE := 900.0
## ===== 2026-11-07：`hp` 改成按**有效身板**记账，实测减免另立一张表 =====
## 原来这列是**面板**系数（设计角色）。实测之后发现机制免伤没记进任何账：
## 面板压进 0.84~1.20（1.43×），实际吞下的伤害却是 25500~48000（**1.88×**），
## 观澜对法术 70500（1.99×）。后果在实测表里看得见：输出垫底的定阵 0.74、叠纸 0.74
## 却 6/6 全胜；输出达标的赫连霄 1.20 却 0/4 全皆负 —— 减免那一层白送了一整档强度。
## 现在 `面板 = 设计角色 ÷ 实测减免`（`MEASURED_EHP_MULT`），
## **有效**身板（面板 × 减免）才等于这列的设计角色值。设计意图一个数没改。
## ⚠ 只动棋盘这一侧：苔甲 −42%、护体 −30%、法抗 100 这些机制本体一个字没改；
##   秘境 / 塔 / 演武场读各 BOSS 自己的面板与抗性，一分没变。
##   苍角面板因此 27600 → 15900：它就是"看着薄、实际难杀"的定位；
##   真要让面板也厚，该削的是苔甲本身（用户定的机制），不是这张表。
const FACTORS := {
	# boss_id          hp     dps    角色
	"boss_huyao":      [0.90, 1.18],   # 扑咬快攻
	"boss_01":         [0.84, 1.20],   # 刀客：连斩高伤、身板薄
	"boss_01_c":       [0.88, 1.05],   # 剑客：万剑远程
	"boss_02":         [1.05, 0.95],   # 两仪：护体反击
	"boss_02_b":       [1.00, 0.98],   # 定阵：阵地控场
	"boss_02_c":       [1.08, 0.92],   # 气君：气环续航
	"boss_03":         [1.12, 1.00],   # 赫连霄：判词压制
	"boss_03_b":       [1.06, 1.04],   # 离照：火种争夺
	"boss_03_c":       [1.10, 1.02],   # 晏无咎：三灾轮转
	"boss_04":         [1.18, 0.86],   # 观澜：镜像分摊、本体法免
	"boss_04_b":       [1.14, 0.94],   # 执烛：影子机制
	"boss_04_c":       [1.20, 0.88],   # 叠纸：折痕对位、最肉
	"world_core_lianqi": [0.95, 1.10], # 古猿
	"world_core_zhuji":  [0.92, 1.08], # 苍角
	"world_core_jiedan": [1.02, 1.12], # 火麟
	"world_core_shihou": [1.16, 0.90], # 石犼
}

## ===== 实测减免倍数（2026-11-07，tools/match_strength_probe.tscn --axis=ehp）=====
## 定义：死前吞下的**原始**伤害 ÷ 面板血。1.00 = 减免与续航为零。
## 量法：来源冻结成不打人的假人，每 0.5 秒喂一发固定 1500 原始伤害，物理 / 法术各一轮；
##       抗性、护体、护身纸、转阶段无敌、回血全部在同一条真实管线上生效。
## 分辨率 = 一发 = 1500（≈±5%），所以 1.00±0.05 一律记 1.00 不折。
## 属性分侧的那几只（两仪 1.43/0.95、观澜 1.02/1.99、执烛 1.18/1.01）取**几何平均**；
## ⚠ 这是"物理/法术各半"的假设而不是实测，对局构成真偏向哪侧下一轮再挪。
## ⚠ 缺一只不会报错，只会**静默按 1.00** —— 那只棋子就白拿一层减免，正是这次要修的毛病。
##   所以 `probe_match_rules` 钉了一条「16 张全都在表里」。
## 实测明细（物理/法术）：虎妖 1.00/1.00｜刀客 1.01/1.01｜剑客 1.02/1.02
##   两仪 1.43/0.95｜定阵 1.30/1.30｜气君 1.02/1.02（吐纳治疗在持续换伤下必被打断）
##   赫连霄 1.03/1.03｜离照 1.08/1.08（日冕只在持有火种时成立）｜晏无咎 0.95/0.95（灾身自扣血）
##   观澜 1.02/1.99（本体法抗 100）｜执烛 1.18/1.01（物抗 20）｜叠纸 1.21/1.21（护身纸首击 −60%）
##   古猿 1.00/1.00｜苍角 1.74/1.74（三片苔甲 + 雾隐整发挡）｜火麟 1.03/1.03｜石犼 0.95/0.95（引撞自扣）
const MEASURED_EHP_MULT := {
	"boss_huyao": 1.00, "boss_01": 1.01, "boss_01_c": 1.02,
	"boss_02": 1.17, "boss_02_b": 1.30, "boss_02_c": 1.02,
	"boss_03": 1.03, "boss_03_b": 1.08, "boss_03_c": 0.95,
	"boss_04": 1.43, "boss_04_b": 1.09, "boss_04_c": 1.21,
	"world_core_lianqi": 1.00, "world_core_zhuji": 1.74,
	"world_core_jiedan": 1.03, "world_core_shihou": 0.95,
}
## 卡池唯一口径：卡包里那 16 位守关者的 id（含四位大陆核心首领 —— 用户 11-02 明确要包含）。
const CARD_POOL: Array = [
	"boss_huyao", "boss_01", "boss_01_c", "boss_02", "boss_02_b", "boss_02_c",
	"boss_03", "boss_03_b", "boss_03_c", "boss_04", "boss_04_b", "boss_04_c",
	"world_core_lianqi", "world_core_zhuji", "world_core_jiedan", "world_core_shihou",
]

# ===================== 入场与押注（2026-11-02 用户定）=====================

## 入口**不设进度门槛**（用户定：没有门槛）。
## 押注：胜者拿走双方注额，但**按两人中较少的一方计**，多押的部分原样退回 ——
## 零和，谁都不会因为押得多被多扣，系统也不凭空印钱。
const BET_MIN := 50.0            ## 起步注额，与卡包「非普通卡每张领 50 晶石」同档
const BET_MAX := 5000.0

## 有效注额 = min(a, b)；超出部分退回，不参与输赢。
static func bet_matched(a: float, b: float) -> float:
	return minf(a, b)


## 注额合法性：0 不允许（不打免费局），且必须是 BET_MIN..BET_MAX 的整数。
static func bet_allowed(amount: float, wallet: float) -> bool:
	return amount >= BET_MIN and amount <= BET_MAX and amount <= wallet


## ===== 关卡制的首通奖（2026-11-05 用户定，见 ADR-0001）=====
## 关卡模式下**不再走押注**：进关不扣钱、输了不罚、重打已通关不给钱，
## 只有第一次打通某一关时发这一笔。定这么小是刻意的 —— 关卡无限延伸，
## 再按关卡递增就成了无限印钱；8 颗相对卡包「非普通卡每张 50」小到不能刷，
## 玩家推关的动力是"破这道题"，不是搬砖。
## ⚠ 上面那三个 bet_* 函数与 BET_MIN/BET_MAX **保留不删**：
##   `min(A押,B押)` 这条规则本身是留给以后真人对局的，只是关卡路径不再调用。
const LEVEL_FIRST_CLEAR_REWARD := 8
## 快速模式终局时间窗（票 004 / ADR-0003）。**只有 quick 那一侧用这两个数**，
## 上面的 FINAL_LIMIT_SECONDS / ACCEL_START_SECONDS 一个数字都没动。
## 240s 的推导口径是"同一份战斗预算"：普通模式最多 6 轮 × 15s = 90s 轮次战斗
## + 120s 残局 = 210s；快速模式一上来就是 12 只全活，把这 210s 的预算一次给完，
## 再留 30s 余量。加速区间按窗口等比重算（120→240 推 1.0→2.0），
## 不是沿用"60s 起推"—— 那样第 120 秒之后到 240 秒会全程 2.0× 恒速。
const QUICK_FINAL_LIMIT_SECONDS := 240.0
const QUICK_ACCEL_START_SECONDS := 120.0

## 卡池不足 6 张时**随机补满**（用户定，取代我原先"按凡界顺序确定性补发"的方案）。
## 已有的牌全部保留，只补差额 —— 否则新手辛苦打通两只结果被系统换掉，比不给还糟。
## ⚠ 随机必须走传进来的 rng（对局种子），不能用手气或引擎全局随机：
##   联机时服务器要能凭种子复现出同一手补发牌，否则两端卡池不一致，整局作废。
static func fill_pool(unlocked: Array, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for id in unlocked:
		var s := String(id)
		if CARD_POOL.has(s) and not out.has(s):
			out.append(s)
	var rest: Array = []
	for id in CARD_POOL:
		if not out.has(id):
			rest.append(id)
	while out.size() < DECK_SIZE and not rest.is_empty():
		var i := rng.randi_range(0, rest.size() - 1)
		out.append(String(rest.pop_at(i)))
	return out


## ===== 真实出手速率校准（attack_power 表）=====
## `attack_power` **不能**直接当 DPS 用：招式伤害 = attack_power × 招式系数，
## 而一只 BOSS 在一段时间里实际出手几次取决于它的 AI 节奏（前摇、走位、召镜像、
## 放领域、二阶段演出全在吃时间）。本表 = 该棋子要打进
## `PIECE_DPS_BASE × FACTORS.dps` 所需的 attack_power。
##
## ===== 口径（改过四次，每次都是上一版量错）=====
## 11-02 对**不还手的同类假人**打 10 秒 ⇒ 慢热型（二阶段 / 天剑阵 / 刀痕）整段被切掉。
## 11-03 对真棋子打 22 秒、两侧平均 ⇒ ① 不扫场：上一场残留的镜像会在下一场
##        **替上一只棋子打人**；② 窗口内不判死亡：凡杀掉量尺的棋子都读成封顶值 1432。
## 11-07 第 1 折：扫场 + 死亡帧收手，并把减免折进面板（见 `MEASURED_EHP_MULT`）。
## 11-07 第 2 折：窗口拉到 30 秒（= 一场同级对决的真实寿命 26923 ÷ 900 ≈ 30s）、每只 8 样本。
## 11-07 第 3、4 折：**把量尺攻击力钉成常数** `--yard=3393`。
##        不钉就不收敛 —— 量尺作为一张牌被一起削之后，它打在被测棋子身上的伤害变小，
##        被测棋子活得久 ⇒ ramp 型实测输出反而上涨：赫连霄 +28% 攻击力读成 1.32、
##        刀客 -17% 反而从 1.20 涨到 1.53。钉住之后读数只取决于这只棋子自己的攻击力，
##        折算才是单调的（工具：`tools/match_balance_pass.py`，日志 `output/ms7/ms9/ms10`）。
## 判据 = **实测 ÷ 名义**，目标 1.00，带 ±18%。
##   ⚠ 不要用"除以基准自检"那一列指数：基准会把量尺自己的二阶段时机耦合进每一行
##     （面板按减免折算后量尺 31500→26923 ⇒ 同一份攻击力从 788 跳到 1090，
##      全体凭空平移 27%）。基准自检只当诊断。
##
## ===== 第 4 折之后的验收 =====
## 6 样本验收说"带外还剩气君 1.23 / 执烛 1.16"，加到 8 样本（ms10）又冒出观澜 1.22，
## 加到 12 样本（ms11）全部回到带内：观澜 1.08、气君 1.04、虎妖 0.95、执烛 1.05。
## ⇒ **15/16 在带内，定稿在第 4 折，没有第 5 折** —— 按 6~8 样本那批数再折一次
##   （观澜 →2331、气君 →2381）就是在追噪声，不是在做平衡。
##   唯一带外是赫连霄 0.84，**故意留着不折**（理由见下面两条）。
## 这一轴的分辨率：SE ≈ 极差 ÷ d₂(n) ÷ √n；n=12 时是 ±6~9%，带宽 ±18%。
##   够判"在不在带内"，不够判"1.04 和 1.08 谁更高" ⇒ 验收只按带内/带外说话。
##   ⚠ `match_balance_pass.py` 的 `se_of()` 曾写死 1.128 = d₂(n=2)，把 σ 夸大约 2.5 倍，
##     满屏"置信不足"是换算错误造成的假象（已按样本数查表修掉）。
## 赫连霄 0.84 只是旁证，**不要再拿攻击力去盖**：他的四条判词律里 `verdict_no_attack` 要
## `_is_player_source(source)`、`verdict_no_dodge` 要 `is_dodging`，而棋盘上没有
## `"player"` 组节点（11-05 已经量死这一点）⇒ 半数律在棋局里永远不成立。
## 那是机制通道问题，接通之后再回来折这一格。
const ATTACK_CALIB := {
	"boss_huyao": 24021.0,		# 第4折 ÷0.96；12 样本复测 0.95（6 样本曾读 0.91）；⚠ 它走 FLAT_DAMAGE_CARDS ⇒ 生效的是这个数 ÷ 100
	"boss_01": 3272.0,		# 第4折 ÷1.07；验收 1.03；全表最大改动：11-03 的 16887 是 3.7 倍超标（当年不扫场+不判死亡，量不出来）
	"boss_01_c": 2409.0,		# 第4折 ÷1.07；验收 1.14；万剑远程+剑意叠层，拖长局还会更高（B 口径 1.6×）
	"boss_02": 2938.0,		# 第4折 ÷1.00；验收 1.00；量尺本身；yard 钉在 3393，所以这只的读数来自镜像自检那一行
	"boss_02_b": 4595.0,		# 第4折 ÷0.94；验收 0.98；输出欠标却全胜：那档强度原来在减免里，现已折进面板
	"boss_02_c": 2833.0,		# 第4折 ÷0.75；12 样本复测 1.04（6/8 样本曾读 1.23/1.19，是杀尺截断不是超标）；吐纳治疗在持续换伤下必被打断 ⇒ 棋盘上没有续航可读
	"boss_03": 1068.0,		# 第4折 ÷1.40；验收 0.84；欠标但不要再折：四条判词律有两条在棋盘上永远不成立（文档第十二节第 1 条）
	"boss_03_b": 1924.0,		# 第4折 ÷0.88；验收 0.93；日冕 -15% 只在正持有火种时成立，所以减免只记到 1.07
	"boss_03_c": 2807.0,		# 第4折 ÷1.07；验收 1.07；三灾轮转要轮次，ramp 1.9×
	"boss_04": 2844.0,		# 第4折 ÷0.95；12 样本复测 1.08（8 样本曾读 1.22 = 6/8 场杀尺的截断）；11-06 口头给的 ≈4900 已作废（被残留镜像污染的 1.98× 折出来的）
	"boss_04_b": 3134.0,		# 第4折 ÷1.25；验收 1.16；全场最难量：位置极差 128%、同格散布最高 179%
	"boss_04_c": 3825.0,		# 第4折 ÷1.05；验收 1.06；意图折之后棋盘输出确实掉一半，所以是上调进来的
	"world_core_lianqi": 2257.0,		# 第4折 ÷0.94；验收 1.00
	"world_core_zhuji": 2842.0,		# 第4折 ÷1.30；验收 1.07；它 1v1 全胜原来靠 1.74~1.80 苔甲减免，已折进面板（面板只剩 15862）
	"world_core_jiedan": 1859.0,		# 第4折 ÷1.02；验收 0.98
	"world_core_shihou": 2751.0,		# 第4折 ÷0.89；验收 1.03；引撞自扣血 ⇒ 实测减免 <1，面板反而略升
}

## ===== 伤害不读 attack_power 的棋子：棋盘里改用倍率补（2026-11-03 用户「虎妖伤害太低」）=====
## 虎妖走的是通用 `scenes/boss/boss.tscn`（prototype_boss），它的伤害是
## `MELEE_DAMAGE / PROJECTILE_DAMAGE / ELEMENTAL_DAMAGE / SMASH_DAMAGE` 这几个
## @export 常数 × 阶段倍率 —— **完全不读 `attack_power`**。
## 于是 `ATTACK_CALIB` 给它抬到 26579 攻击力是空转的：实测它对面的棋子只掉 2 DPS
## （名义 1062），因为它六成的招还是远程弹体，一并走那几个常数。
## 修法不是去改常数（那会动到秘境 / 塔 / 演武场的虎妖面板），而是只对棋子乘一个倍率：
## 倍率 = 校准值 ÷ 校准用的单位攻击力，正是当初那次校准想表达的"要放大多少倍"。
## ⚠ 以后哪只棋子换成自己的脚本、伤害改走 `MoveDB.boss_damage(form, attack_power, …)`，
##   就要把它从这张表里删掉，否则会乘两次。
const UNIT_ATTACK_POWER := 100.0
const FLAT_DAMAGE_CARDS: Array = ["boss_huyao"]


static func match_damage_scale(boss_id: String) -> float:
	if not FLAT_DAMAGE_CARDS.has(boss_id):
		return 1.0
	return float(ATTACK_CALIB.get(boss_id, UNIT_ATTACK_POWER)) / UNIT_ATTACK_POWER


## 卡包 id → 区域 id。四位核心是 WorldEnemy，装配要按区域取 CORE_SKILLS。
## ⚠ 幽冥那只的 core_boss_id 在区域表里是 "world_core_yuanying"，
##   而卡包/CodexDB 用 "world_core_shihou" —— 两种写法都要能认出来，
##   否则石犼会静默走回退分支，变成一只假招式的通用怪。
static func core_region_id(boss_id: String) -> String:
	for raw in SecretWorldDB.REGIONS:
		var r := raw as Dictionary
		var core := String(r.get("core_boss_id", ""))
		if core == "":
			continue
		if core == boss_id or String(PANEL_ALIAS.get(core, core)) == boss_id:
			return String(r.get("region_id", ""))
	return ""


static func is_core_boss(boss_id: String) -> bool:
	return core_region_id(boss_id) != ""


## 棋子折算后的面板。原始面板只用来查「有没有登记漏人」，不参与最终数值。
static func piece_stats(boss_id: String) -> Dictionary:
	var key := String(PANEL_ALIAS.get(boss_id, boss_id))
	var f: Array = FACTORS.get(key, [1.0, 1.0])
	# 面板 = 设计角色 ÷ 实测减免 ⇒ **有效**身板（面板 × 减免）才等于设计角色那一档。
	var mult := float(MEASURED_EHP_MULT.get(key, 1.0))
	return {"hp": PIECE_HP_BASE * float(f[0]) / mult, "dps": PIECE_DPS_BASE * float(f[1])}


## 有效身板读数：面板 × 实测减免 = 该吃到的那档设计角色值。
## 判据读这个，不要读面板 —— 面板这一列现在是"补偿之后"的数，跨度故意比设计带宽。
static func effective_hp(boss_id: String) -> float:
	return float(piece_stats(boss_id)["hp"]) * float(MEASURED_EHP_MULT.get(
			String(PANEL_ALIAS.get(boss_id, boss_id)), 1.0))


static func panel_of(boss_id: String) -> Dictionary:
	var key := String(PANEL_ALIAS.get(boss_id, boss_id))
	return PANEL_SNAPSHOT.get(key, {})


## 棋子卡片占格子的高度比例。
## ⚠ 正反面必须走同一个数：以前正面按 640 算、背面按 64 算却各写一套公式，
##   结果卡背 161×242、卡面只有 88×132 —— 翻开的牌反而比盖着的更小。
##   现在两张面共用 MatchCardToken 里的同一个 Rect2，比例只要贴图自己是 2:3 就一定一致。
## 上限是"连卡套一起装得进一格"：卡片是 2:3 竖版，格子是正方形，
## 比例超过 0.92 之后卡套高度就会顶到上下相邻格，棋盘会糊成一片。
const TOKEN_H_RATIO := 0.92


## 卡片在棋盘上的实际像素高度（探针用它断言"别又缩回去"）
static func card_token_height() -> float:
	return CELL_PX * TOKEN_H_RATIO


## 格子坐标 → 战场坐标（棋盘以原点为中心）
static func cell_to_pos(cell: Vector2i) -> Vector2:
	var half := Vector2((BOARD_COLS - 1) * CELL_PX * 0.5, (BOARD_ROWS - 1) * CELL_PX * 0.5)
	return Vector2(cell.x, cell.y) * CELL_PX - half


## 战场半尺寸：给 `BossBase.set_arena_bounds()` 用，外扩半格让击退有缓冲
static func arena_half() -> Vector2:
	return Vector2(BOARD_COLS, BOARD_ROWS) * CELL_PX * 0.5


static func in_board(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < BOARD_COLS and cell.y < BOARD_ROWS
