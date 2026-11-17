class_name FarmPlot
extends WorldResource
## 灵田地块：一块地一个节点，九块拼成传送门旁的一片田（每个区域各一片）
##
## 打完**本区**核心首领后生成的全是**荒地**：站在上面施展「猛虎踏地」才开垦（存档记 tilled_plots）。
## 开垦后才能播种，走完整套流程：
##   荒地 → 猛虎踏地 → 空地（F 播种）→ 生长中（报剩余时间）→ 成熟（收进局内背包）
## 状态存在 CharacterData.home_progress / tilled_plots：键 = state_base + plot_index，
## 三区灵田各占一段（0~8 / 9~17 / 18~26），离开重进都在且互不串。

const KIND := WorldResource.KIND_FARM

## 开垦技能：猛虎踏地（虎妖首杀奖励）
const TILL_SKILL_ID := "skill_tiger_stomp"
## 批量收获技能：横斩（站在成熟灵田旁释放，收完全部成熟地块）
const SLASH_HARVEST_SKILL_ID := "skill_blade_slash"
## 「旁」的判定半径：略大于横斩自身 150 的射程，站在田边也能触发
const SLASH_HARVEST_RADIUS := 170.0

## 一块地的尺寸（松土范围，田埂另画在外面）
const BED := Vector2(104.0, 70.0)
const REACH := 92.0
## 灵植成熟秒数（2026-10-23 用户定：3 小时）
const GROW_SECONDS := 10800

const WILD_TUFTS: Array = [
	Vector2(-40.0, -22.0), Vector2(-14.0, 14.0), Vector2(10.0, -6.0),
	Vector2(34.0, 20.0), Vector2(42.0, -18.0), Vector2(-30.0, 22.0),
	Vector2(-2.0, -26.0), Vector2(24.0, 6.0), Vector2(-18.0, -4.0),
	Vector2(4.0, 24.0), Vector2(-44.0, 8.0), Vector2(20.0, -22.0),
]
const WILD_STONES: Array = [Vector2(-36.0, 4.0), Vector2(16.0, -20.0), Vector2(38.0, -2.0)]

var plot_index: int = 0
## 存档键起点：本区田地在 CharacterData 里的分段起点（三区互不串）
var state_base: int = 0
## 这块田属于哪个区域（种子目录按它取本区草药）
var region_id: String = ""
## 玩家站在这块地旁时描金边，九块地里一眼看出正在打理哪块
var highlight: bool = false

var _t: float = 0.0


func _ready() -> void:
	# 不走 WorldResource 的外观：地块外观全部由 _draw 画，不需要贴图与飘字标签
	kind = KIND
	# 压在单位之下（2026-11-02 用户报：怪物站在田里被农田盖住）。
	# 项目没有开 YSort，同 z 时谁后 add_child 谁盖在上面 —— 田是后生成的，
	# 所以必须显式压一层：地面 -20 < 田埂 -1 < 玩家 / 怪 / 掉落物 0。
	z_index = -1


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func reach_distance() -> float:
	return REACH


# ===================== 地块状态 =====================

## 存档键：区域分段 + 本区第几块地
func state_index() -> int:
	return state_base + plot_index


func crop_id() -> String:
	return String(CharacterData.get_plot(state_index()).get("seed_id", ""))


func is_empty() -> bool:
	return CharacterData.get_plot(state_index()).is_empty()


## 荒地：还没被猛虎踏地开垦过（种上作物的一律算已开垦）
func is_tilled() -> bool:
	return CharacterData.is_plot_tilled(state_index())


func till() -> void:
	CharacterData.till_plot(state_index())


## 玩家是否真的站在这块地上（含一点脚下容错，站在田埂边也能踏）
func contains_point(world_pos: Vector2) -> bool:
	return Rect2(-BED * 0.5, BED).grow(8.0).has_point(to_local(world_pos))


func is_mature() -> bool:
	return CharacterData.is_plot_ready(state_index())


func remaining() -> int:
	return CharacterData.plot_remaining_seconds(state_index())


func crop_name() -> String:
	return ItemDB.get_material_name(crop_id())


func prompt_text() -> String:
	if not is_tilled():
		return "荒地 · 站上来施展「猛虎踏地」开垦"
	if is_empty():
		return "F　播种"
	if is_mature():
		return "F　收获 %s　·　横斩批量收" % crop_name()
	return "%s · 生长中，还需 %s" % [crop_name(), grow_text(remaining())]


## 把秒数写成「3 小时」「12 分钟」「45 秒」这类人话（面板与提示共用）
static func grow_text(seconds: int) -> String:
	var s := maxi(0, seconds)
	if s >= 3600:
		var h := int(s / 3600)
		var m := int((s % 3600) / 60)
		return "%d 小时 %d 分" % [h, m] if m > 0 else "%d 小时" % h
	if s >= 60:
		return "%d 分钟" % int(s / 60)
	return "%d 秒" % s


func set_highlight(v: bool) -> void:
	if highlight == v:
		return
	highlight = v
	queue_redraw()


## 生长进度 0~1（空地 0）
func _progress() -> float:
	var p := CharacterData.get_plot(state_index())
	if p.is_empty():
		return 0.0
	var total := maxf(1.0, float(p.get("grow_seconds", GROW_SECONDS)))
	return clampf(1.0 - float(remaining()) / total, 0.0, 1.0)


## 作物颜色取这种药材在地图上的占位色，成熟后一眼能认出种的是什么
func _crop_color() -> Color:
	var vid := SecretWorldDB.get_herb_visual(crop_id())
	var def = ArtDB.VISUALS.get(vid, {})
	if def is Dictionary:
		var c = (def as Dictionary).get("placeholder_color", null)
		if c is Color:
			return c
	return Color(0.50, 0.78, 0.40, 1.0)


# ===================== 绘制 =====================

func _draw() -> void:
	var half := BED * 0.5
	var bed := Rect2(-half, BED)
	if is_tilled():
		_draw_bed(half)
		if is_empty():
			_draw_holes(half)
		else:
			_draw_crop(half)
	else:
		_draw_wild(half)

	if highlight:
		draw_rect(bed.grow(9.0), Color(1.0, 0.86, 0.40, 0.85), false, 2.0)


## 已开垦：松土 + 踩实的田埂
func _draw_bed(half: Vector2) -> void:
	var bed := Rect2(-half, BED)
	# 每块地土壤色调略有差别，九块摆在一起才像田，不像复制粘贴的箱子
	var tone := 0.015 * float(plot_index % 3)

	draw_rect(Rect2(-half - Vector2(5.0, 4.0), BED + Vector2(10.0, 9.0)), Color(0.18, 0.13, 0.08, 0.28))
	draw_rect(Rect2(-half - Vector2(5.0, 5.0), BED + Vector2(10.0, 10.0)), Color(0.30 + tone, 0.22, 0.14))
	draw_rect(bed, Color(0.35 + tone, 0.25, 0.155))
	draw_line(Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Color(0.42, 0.31, 0.19, 1.0), 1.0)

	# 垄沟
	for i in range(1, 4):
		var y := -half.y + BED.y * 0.25 * float(i)
		draw_line(Vector2(-half.x + 8.0, y), Vector2(half.x - 8.0, y), Color(0.26, 0.18, 0.11, 0.85), 2.0)


## 荒地：旧土色、碎石和乱长的杂草，一眼看出「这块还没开」
func _draw_wild(half: Vector2) -> void:
	var bed := Rect2(-half, BED)
	draw_rect(Rect2(-half - Vector2(3.0, 3.0), BED + Vector2(6.0, 6.0)), Color(0.16, 0.14, 0.09, 0.22))
	draw_rect(bed, Color(0.30, 0.28, 0.18))
	# 踩乱的土色斑块（按地块下标错开，九块不会一模一样）
	var drift := float(plot_index % 4) * 6.0 - 9.0
	for i in range(4):
		var p := Vector2(-28.0 + 22.0 * float(i) + drift, -14.0 + 12.0 * float((i + plot_index) % 3))
		draw_circle(p, 9.0 + float(i % 2) * 3.0, Color(0.26, 0.24, 0.15, 0.9))

	for i in range(WILD_STONES.size()):
		var sp: Vector2 = WILD_STONES[i] + Vector2(drift, 0.0)
		draw_circle(sp, 3.0, Color(0.45, 0.44, 0.40))
		draw_circle(sp + Vector2(-0.8, -0.8), 1.8, Color(0.56, 0.55, 0.50))

	for i in range(WILD_TUFTS.size()):
		var base: Vector2 = WILD_TUFTS[i] + Vector2(drift * 0.5, 0.0)
		_draw_tuft(base, float(i) * 0.8 + float(plot_index) * 0.3)


## 一簇野草：三根细叶，随风轻摆
func _draw_tuft(base: Vector2, phase: float) -> void:
	var sway := sin(_t * 1.4 + phase) * 2.0
	var col := Color(0.42, 0.55, 0.27, 0.95)
	for k in range(3):
		var lean := (float(k) - 1.0) * 2.5
		draw_line(base, base + Vector2(sway + lean, -7.0 - float(k % 2) * 3.0), col, 1.5)


## 田地里的种植位：两垄三列（坐标随 BED 缩放）
func _slot_pos(half: Vector2, r: int, c: int) -> Vector2:
	return Vector2(-half.x + 24.0 + 28.0 * float(c), -half.y + 22.0 + 26.0 * float(r))


## 空地：两垄三列的种坑，提示「这里可以种」
func _draw_holes(half: Vector2) -> void:
	for r in range(2):
		for c in range(3):
			var p := _slot_pos(half, r, c)
			draw_circle(p, 5.0, Color(0.23, 0.16, 0.10))
			draw_arc(p, 5.0, 0.0, TAU, 12, Color(0.45, 0.33, 0.20), 1.0)


## 已种：同样两垄三列，株高随进度长，成熟后结出药材色的果并描一圈金光
func _draw_crop(half: Vector2) -> void:
	var pr := _progress()
	var mature := is_mature()
	var crop := _crop_color()
	for r in range(2):
		for c in range(3):
			_draw_sprout(_slot_pos(half, r, c), pr, crop, mature, float(r * 3 + c) * 0.7)


func _draw_sprout(base: Vector2, pr: float, crop: Color, mature: bool, phase: float) -> void:
	var stem_h := 6.0 + 22.0 * pr
	var sway := sin(_t * 1.6 + phase) * (1.0 + pr)
	var top := base + Vector2(sway, -stem_h)
	draw_line(base, top, Color(0.33, 0.60, 0.29), 2.0)

	var leaf := Color(0.44, 0.78, 0.38, 1.0)
	if mature:
		leaf = crop.lightened(0.15)
	var leaf_r := 2.0 + 3.0 * pr
	draw_circle(top + Vector2(-leaf_r - 1.0, -1.0), leaf_r, leaf)
	draw_circle(top + Vector2(leaf_r + 1.0, -1.0), leaf_r, leaf)

	if mature:
		var pulse := 0.5 + 0.5 * sin(_t * 3.0 + phase)
		draw_circle(top + Vector2(0.0, -3.0), 4.0 + 1.5 * pulse, crop)
		draw_arc(top + Vector2(0.0, -3.0), 8.0 + 2.5 * pulse, 0.0, TAU, 20, Color(1.0, 0.90, 0.45, 0.75), 2.0)
	elif pr > 0.35:
		draw_circle(top + Vector2(0.0, -2.5), 1.5 + 2.5 * pr, crop.darkened(0.12))
