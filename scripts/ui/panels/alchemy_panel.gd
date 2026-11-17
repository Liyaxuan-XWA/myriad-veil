class_name AlchemyPanel
extends CraftStage
## 炼丹房 —— 全屏丹炉舞台（2026-10-28 推到重做，取代「方卷列表 + 弹窗炼制层」）
##
## 玩家口径：
##   · 一味药材 = 一颗对应的丹（青岚血参→练气回春丹、云隐血参→筑基回春丹、
##     赤金血参→结丹回春丹；另外四味同理）
##   · 一炉只认一味：拖别的进炉 = 先前那批整批退回，绝不吞材料
##   · 投 N 株 → 点「开炉」（这一刻才真正扣料）→ 控火停手
##   · 停火位置决定出几颗：丹眼全成 / 偏温约六成 / 偏猛约三成 / 差太多尽毁
##   · 该味熟练度满（100%）后免控火，开炉直接全成

const STAGE_ART := "res://assets/ui/alchemy/stage_hearth.png"
## 指针每秒扫过的轨道比例
const NEEDLE_SPEED := 0.42

var _gauge: AlchemyHeatGauge
var _needle := 0.0
var _needle_dir := 1.0
var _target := 0.5


func _init() -> void:
	panel_title = "炼丹房"
	panel_hint = "ESC 关闭 · 药材丢进炉口"


func facility_visual() -> Dictionary:
	return UIKit.facility_style("alchemy")


# ===================== 舞台口径 =====================

func craft_kind() -> String:
	return "pill"


func stage_texture() -> String:
	return STAGE_ART


func stage_mouth_rect() -> Rect2:
	return Rect2(516.0, 188.0, 248.0, 124.0)


func stage_shelf_rect() -> Rect2:
	return Rect2(948.0, 140.0, 284.0, 316.0)


func stage_dose_center() -> Vector2:
	return Vector2(640.0, 366.0)


func stage_dish_rect() -> Rect2:
	return Rect2(150.0, 448.0, 240.0, 128.0)


func stage_play_rect() -> Rect2:
	## 火候轨往右挪、收窄：左半边留给出炉盘，两者不再互相压
	return Rect2(420.0, 546.0, 560.0, 66.0)


func verb_start() -> String:
	return "开炉"


func verb_stop() -> String:
	return "停火"


func unit_word() -> String:
	return "株"


func product_word() -> String:
	return "丹"


func word_success() -> String:
	return "丹成！"


func word_blocked() -> String:
	return "火候未收，丹炉封闭 —— 先点「停火」"


func play_hint() -> String:
	return "指针扫到金色炉心时停火 = 全成；偏一点约六成 / 三成，差太多一炉尽毁"


func product_payload(recipe: Dictionary, n: int) -> Dictionary:
	return {
		"id": String(recipe.get("pill_id", "")),
		"name": String(recipe.get("pill_name", "")),
		"type": CharacterData.ITEM_PILL,
		"count": n,
		"icon": String(recipe.get("icon", "")),
		"desc": String(recipe.get("desc", "")),
		"battle_cooldown": float(recipe.get("battle_cooldown", 0.0)),
		"is_consumable": bool(recipe.get("is_consumable", true)),
	}


# ===================== 控火玩法 =====================

func _build_play() -> Control:
	_gauge = AlchemyHeatGauge.new()
	return _gauge


func _begin_play() -> void:
	_target = randf_range(0.2, 0.8)
	_needle = randf_range(0.0, 0.15)
	_needle_dir = 1.0
	if _gauge != null:
		_gauge.set_state(_needle, _target)


func _tick_play(delta: float) -> void:
	if _gauge == null:
		return
	_needle += _needle_dir * NEEDLE_SPEED * delta
	if _needle >= 1.0:
		_needle = 1.0
		_needle_dir = -1.0
	elif _needle <= 0.0:
		_needle = 0.0
		_needle_dir = 1.0
	_gauge.set_state(_needle, _target)


func _stop_play() -> void:
	if _gauge == null:
		settle_ratio(1.0)
		return
	var ratio := _gauge.ratio_for(_needle)
	settle_ratio(ratio, _gauge.tier_text(_needle))
