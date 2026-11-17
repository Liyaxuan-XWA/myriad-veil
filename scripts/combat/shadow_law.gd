class_name ShadowLaw
extends RefCounted
## 照影界第二位「执烛」· 投影 · 身外之影 —— 影子几何的唯一口径（2026-11-02）
##
## 一条规则同时管三处：BOSS 侧判定、玩家侧判定、图鉴与功法库文案。
## 改这里，射程 / 走廊宽度 / 文案数字一起跟着变（数值不在脚本里手抄）。
##
## 规则本体：
##   影身 = 从单位脚下沿「单位位置 − 光源位置」方向向外延伸的一条地面走廊。
##   影长只由「单位离光源有多远」决定 —— 光正下方只剩脚边一截，越靠场边影子越长。
##   没有势条、没有层数：机制状态只有「光源在哪、影子属于谁、影长多少」三个可见量。

# ===== 通用影身几何 =====
const SHADOW_MIN := 40.0        ## 光源正下方也留的这一截短刃
const SHADOW_SLOPE := 1.15      ## 影长 = 到光源距离 × 本斜率
const SHADOW_MAX := 620.0       ## 影长上限（贴场边也拉不出更多）
const WIDTH_ROOT := 54.0        ## 走廊在脚下的宽度
const WIDTH_TIP := 104.0        ## 走廊在影尖的宽度（向外张开）
const HIT_MARGIN := 18.0        ## 判定余量（与其它 BOSS 的 +18 同口径）
const LAMP_FORWARD := 300.0     ## 灯台在战场上偏「北」的固定距离

## 到光源的距离 → 影长
static func shadow_len(dist_from_light: float) -> float:
	return clampf(SHADOW_MIN + maxf(0.0, dist_from_light) * SHADOW_SLOPE, SHADOW_MIN, SHADOW_MAX)

## 影子朝向：背离光源。单位几乎站在光源正下方时方向无意义，退回它自己的朝向。
static func shadow_dir(unit_pos: Vector2, light_pos: Vector2, fallback: Vector2) -> Vector2:
	var d := unit_pos - light_pos
	if d.length_squared() < 16.0:
		return fallback.normalized() if fallback.length_squared() > 0.01 else Vector2.DOWN
	return d.normalized()

## 走廊上 t（0=脚下，1=影尖）那个点的世界坐标
static func shadow_point(unit_pos: Vector2, dir: Vector2, length: float, t: float) -> Vector2:
	return unit_pos + dir * (length * clampf(t, 0.0, 1.0))

## 走廊在 t 处的宽度
static func corridor_width(length: float, t: float) -> float:
	return lerpf(WIDTH_ROOT, WIDTH_TIP, clampf(t, 0.0, 1.0)) * maxf(0.6, minf(1.0, length / 420.0) + 0.35)

## 命中判定：point 是否落在「unit_pos 沿 dir 长 length」这条走廊里
static func corridor_contains(unit_pos: Vector2, dir: Vector2, length: float,
		point: Vector2, margin: float = HIT_MARGIN) -> bool:
	var to := point - unit_pos
	var forward := to.dot(dir)
	if forward < -12.0 or forward > length + margin:
		return false
	var lateral := absf(to.cross(dir))
	if lateral > corridor_width(length, clampf(forward / maxf(length, 1.0), 0.0, 1.0)) * 0.5 + margin:
		return false
	return true

## 这一招能不能打到 target —— BOSS 选招前的「不许空放」校验
static func can_reach(unit_pos: Vector2, light_pos: Vector2, fallback_dir: Vector2,
		target_pos: Vector2) -> bool:
	var d := unit_pos.distance_to(light_pos)
	var length := shadow_len(d)
	var dir := shadow_dir(unit_pos, light_pos, fallback_dir)
	return corridor_contains(unit_pos, dir, length, target_pos)

## 影长读数文案（图鉴 / 功法库共用，全部现算）
static func length_text() -> String:
	return "影长 %.0f~%.0f（到光源距离 × %.2f）" % [SHADOW_MIN, SHADOW_MAX, SHADOW_SLOPE]

# ===== 玩家侧：灯笼拖尾 =====
## 玩家的影长不吃「到界灯的距离」，而是吃「灯笼被甩在身后多远」：
## 跑动 / 突进 → 灯笼落后 → 影子伸长 → 影系招式射程变长；站定 → 灯笼追上来 → 影子塌回脚边。
## 同一条几何，BOSS 那边是空间博弈，玩家这边是移动表达。
const LANTERN_LAG_MAX := 250.0      ## 灯笼最多被甩在身后这么远
const LANTERN_CATCHUP := 430.0      ## 灯笼追向玩家的速度（px/秒）
const LANTERN_SLOPE := 1.70         ## 影长 = 拖尾距离 × 本斜率
const LANTERN_SHADOW_MAX := 520.0   ## 玩家影长上限（比 BOSS 短一档）
## 拖尾吃的是「最近这段时间跑了多快」，不是「这一帧的速度」。
## ⚠ 用瞬时速度会把整组拆台：平A 期间人是定身的（player.gd 的 is_attacking 锁移动），
##   一刀 0.35 秒就把 250 拖尾抽干，影技射程当场掉回脚边 —— 影系明明要穿插平A。
##   0.6 秒的均值窗口 = 平A 那一小段只削掉约四成，跑两步就补回来；真站着不动照样塌。
const LANTERN_INERTIA := 0.6        ## 速度均值的时间常数（秒）
const PASSIVE_MULT := 1.30          ## 被动「执灯」：影长乘区
const PASSIVE_DODGE_SECONDS := 2.0  ## 被动「执灯」：完美闪避后这段时间影长直接拉满
const PASSIVE_DODGE_CD := 6.0       ## 被动「执灯」：内部冷却

static func player_shadow_len(lag_dist: float, mult: float = 1.0) -> float:
	return clampf(lag_dist * LANTERN_SLOPE * mult, SHADOW_MIN, LANTERN_SHADOW_MAX * mult)

static func player_shadow_text(mult: float) -> String:
	return "影长 %.0f~%.0f（灯笼落后距离 × %.2f%s）" % [
		SHADOW_MIN, player_shadow_len(LANTERN_LAG_MAX, mult), LANTERN_SLOPE,
		"" if is_equal_approx(mult, 1.0) else "，被动「执灯」×%.2f" % mult]

# ===== 明灭（暗场）=====
## 暗场不是「打折」而是「缩短」：影长乘区压到 DIM_MULT，远程招射程当场掉一截。
const DIM_MULT := 0.28
const DIM_SELF_ATTACK_MULT := 1.35   ## 暗场期间本体招式伤害
const DIM_SPEED_MULT := 1.30         ## 暗场期间本体攻速（间隔 ÷ 本值）
const DIM_PHYS_VULN := 1.15          ## 暗场期间本体受物理伤害
const DIM_TIME := 4.5

## 分影（影子脱手）期间的自曝破口
const SPLIT_TAKEN_MULT := 1.35
const SPLIT_TIME := 5.2
const SPLIT_SWEEP_GAP := 0.9
