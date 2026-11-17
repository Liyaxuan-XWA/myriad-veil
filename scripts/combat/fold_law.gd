class_name FoldLaw
extends RefCounted
## 照影界第三位「叠纸」· 空间连通 · 折影为径 —— 折痕几何的唯一口径（2026-11-02）
##
## 一条规则同时管三处：BOSS 侧判定、玩家侧判定、图鉴与功法库文案。
## 改这里，折痕长度 / 贴合宽度 / 镜像比例 / 文案数字一起跟着变（数值不在脚本里手抄）。
##
## 规则本体：
##   战场是一张纸。折痕 = 地面上一条线段 AB，它把相距很远的两块纸面**贴在一起**。
##   任何一击的判定位置取两处：出手者自己脚下 与 它关于折痕直线的镜像点。
##   镜像那一半只有在「目标确实还贴在折过来的那部分纸上」时才成立 ——
##   也就是 目标到痕的垂直距离 ≤ fold_reach **且** 目标与出手者分处痕的两侧。
##   ⇒ 站得比 fold_reach 远，镜像永远碰不到你。这就是"首战空手可破"的那只手。
##   没有势条、没有层数：机制状态只有「痕在哪、离痕多远、圆牌在哪」三个可见量。

# ===== 折痕贴合宽度 =====
const REACH_P1 := 300.0     ## 一折：折过来的纸能贴住这么宽
const REACH_P2 := 260.0     ## 二折：纸叠了两层，贴合带反而收窄（规则要自洽，不白送强度）
const CREASE_MARGIN := 40.0 ## 沿痕方向超出端点的容差：痕外这段不算"折过来"
const HIT_MARGIN := 18.0    ## 判定余量（与其它 BOSS 的 +18 同口径）
const FAR_EPS := 1.0e6      ## "不在贴合带内"的哨兵值

# ===== 对位区（缝合圆牌）=====
const SEAM_R := 62.0        ## 圆牌半径：踩进去就从对侧出来
const SEAM_CD := 0.6        ## 同一对圆牌的重触发间隔（防抖帧）
const SEAM_EXIT_GUARD := 0.25  ## 出牌后的短暂无敌（防止两端互为输入无限来回）

# ===== 换痕节奏 =====
const REFOLD_P1 := 15.0     ## 一阶段：每隔这么久重新折一次
const REFOLD_P2 := 11.0     ## 二阶段
const PREVIEW_TIME := 1.2   ## 换痕前的压痕预告时长
const TEAR_DOWN_TIME := 4.0 ## 碎痕之后折痕作废这么久 —— 全场唯一的免费窗口

# ===== 镜像伤害比例 =====
const MIRROR_RATIO := 0.6      ## 镜像落点吃到本体的 60%
const MIRROR_RATIO_NEAR := 0.75 ## 被动「量折」：站在痕附近时抬到 75%
const NEAR_SEAM := 120.0       ## "站在折痕附近"的距离口径
const CROSS_BONUS := 0.30      ## 穿缝后下一次攻击 +30%
const CROSS_BONUS_TIME := 3.0  ## 这个旗标挂多久（不是条，是一次性旗标）

# ===== 纸印（debuff）：被押上痕的人 =====
const MARK_REACH_BONUS := 120.0 ## 带纸印期间，对它生效的贴合带宽 +120

# ===== 玩家侧：自己裁一道痕 =====
const PLAYER_SEAM_LEN := 340.0  ## 个人折痕全长
const PLAYER_SEAM_TIME := 3.2   ## 存续时长
const PLAYER_SEAM_OFFSET := 60.0 ## 痕中心在玩家身前的距离

# ===== 意图折（2026-11-05：BOSS 靠折痕**增加射程**打到玩家）=====
## 旧版周期性重折是纯随机（随机方向 + 随机半长 + 中心只往玩家挪 18~50%），
## 实测三段 40 秒里「玩家对位点落进按纸扇形」只有 0~1% 的采样、镜像落点 **0 次** ——
## 痕画得再好看也不参与进攻，玩家绕着 300~400 走就是绝对安全。
## 意图折把痕摆成「垂直于 BOSS→玩家连线、中心落在合法窗口里」，
## 于是玩家折过来的对位点必然落在 BOSS 面前 —— 痕就是它的射程放大器。
const AIM_LANDING := 150.0        ## 目标：对位点离 BOSS 不超过这么远（= 押痕圆半径）
const AIM_ANGLE_JITTER := 22.0    ## 痕方向相对「垂直于连线」的抖动（度）
const AIM_SLIDE := 0.14           ## 痕中心沿连线在合法窗口里滑动的比例
## 取点偏向窗口的**上端**（靠玩家那一侧），不是正中。
## 原因：BOSS 追击时会朝玩家走 —— 痕摆在正中，它只要走完一半就穿到痕的另一边，
## 两者变成同侧，镜像当场失效（实测自然绕圈那段 56% 的采样里 BOSS 与玩家同侧）。
## 摆在靠玩家一侧，BOSS 要多走将近一整段才穿得过去，这一折的"射程加成"能撑久得多。
const AIM_T_BIAS := 0.72
## 两条约束必须同时成立（d = BOSS 到玩家的距离，t = 痕中心离 BOSS 沿连线的距离）：
##   ① 对位点够近：|2t − d| ≤ AIM_LANDING
##   ② 玩家自己还在贴合带里：|d − t| ≤ reach + HIT_MARGIN
## 窗口为空 ⇔ d > 2×reach + AIM_LANDING + HIT_MARGIN×2 ⇒ 退回随机折（也是玩家的活路）。

## 意图折的合法窗口；空数组 = 距离太远，折不过来
static func aim_window(d: float, reach: float) -> Array:
	if d < 90.0:
		return []          # 贴脸不需要放大器，直接走本体判定
	var lo := maxf((d - AIM_LANDING) * 0.5, d - reach - HIT_MARGIN)
	var hi := (d + AIM_LANDING) * 0.5
	if lo > hi:
		return []
	return [lo, hi]


static func aim_feasible(d: float, reach: float) -> bool:
	return not aim_window(d, reach).is_empty()

# ===================== 几何 =====================

## 痕的方向（A→B 单位向量）；退化线段返回 Vector2.RIGHT
static func crease_dir(a: Vector2, b: Vector2) -> Vector2:
	var d := b - a
	return d.normalized() if d.length_squared() > 0.01 else Vector2.RIGHT

## 侧向符号：+1 / −1 / 0（正落在痕线上）。同一击的"两侧"就用它比。
static func side(a: Vector2, b: Vector2, p: Vector2) -> float:
	var d := crease_dir(a, b)
	return signf(d.cross(p - a))

## P 到痕直线的垂足参数（像素，可负、可超出痕长）
static func along(a: Vector2, b: Vector2, p: Vector2) -> float:
	return (p - a).dot(crease_dir(a, b))

## P 到痕直线的垂直距离（带判定余量的口径写在 mirror_valid 里）
static func _perp_len(a: Vector2, b: Vector2, p: Vector2) -> float:
	return ((p - a) - crease_dir(a, b) * (p - a).dot(crease_dir(a, b))).length()

## **贴合距离**：P 还在"折过来的那部分纸"上时 = 到痕的垂直距离；
## 垂足落在线段之外（超出容差）说明那块纸根本没折过来 → 返回 FAR_EPS。
static func fold_dist(a: Vector2, b: Vector2, p: Vector2) -> float:
	var seg_len := a.distance_to(b)
	var t := along(a, b, p)
	if t < -CREASE_MARGIN or t > seg_len + CREASE_MARGIN:
		return FAR_EPS
	return _perp_len(a, b, p)

## P 关于痕所在直线的镜像点（对位落点）
static func mirror(a: Vector2, b: Vector2, p: Vector2) -> Vector2:
	var d := crease_dir(a, b)
	var v := p - a
	var perp_v := v - d * v.dot(d)
	return p - perp_v * 2.0

## 这一道镜像判定成不成立：出手者 src 打目标 tgt，要求异侧 + tgt 在贴合带内。
## reach 传本阶段口径；has_mark 是被打者带「纸印」时放宽。
static func mirror_valid(a: Vector2, b: Vector2, src: Vector2, tgt: Vector2,
		reach: float, has_mark: bool = false) -> bool:
	if a.distance_to(b) < 1.0:
		return false
	var r := reach + (MARK_REACH_BONUS if has_mark else 0.0)
	if side(a, b, src) * side(a, b, tgt) >= 0.0:
		return false
	return fold_dist(a, b, tgt) <= r + HIT_MARGIN

## 两折复合映射（"夹层"）：只用于 BOSS 判定，不生成圆牌、不上 HUD。
static func mirror_twice(c1: Vector2, c2: Vector2, c3: Vector2, c4: Vector2,
		p: Vector2) -> Vector2:
	return mirror(c3, c4, mirror(c1, c2, p))

# ===================== 本阶段口径 =====================

static func reach_for(phase: int) -> float:
	return REACH_P2 if phase >= 2 else REACH_P1

static func refold_for(phase: int) -> float:
	return REFOLD_P2 if phase >= 2 else REFOLD_P1

# ===================== 文案（全部现算，图鉴与功法库共用）=====================

static func reach_text(phase: int = 1) -> String:
	return "贴合带 %.0f（二阶段 %.0f）" % [REACH_P1, REACH_P2]

static func seam_text() -> String:
	return "圆牌半径 %.0f" % SEAM_R

static func refold_text() -> String:
	return "每 %.0f 秒重新折一次（换痕前 %.1f 秒压痕预告）" % [REFOLD_P1, PREVIEW_TIME]

static func mirror_text() -> String:
	return "镜像落点 %d%%（站痕 %.0f 内 %d%%）" % [
		int(round(MIRROR_RATIO * 100.0)), NEAR_SEAM, int(round(MIRROR_RATIO_NEAR * 100.0))]

static func tear_text() -> String:
	return "撕开后折痕作废 %.1f 秒" % TEAR_DOWN_TIME
