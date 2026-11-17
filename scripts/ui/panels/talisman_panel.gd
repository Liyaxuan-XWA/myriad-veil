class_name TalismanPanel
extends CraftStage
## 制符台 —— 全屏符案舞台（2026-10-28 重做；2026-10-31 改为直接进符匣）
##
## 打开即进符匣：选七系符 → 选品阶 → 「走笔制符」沿该符专属符路描完，
## 再按当前境界成功率逐张结算（本境界 100% / 越一级 5% / 越两级不可制）。
## 可批量 ×N，消耗 = 该品阶兽皮 ×N + 修为 ×N；失败同样扣料与修为。

const STAGE_ART := "res://assets/ui/talisman/stage_desk.png"

var _canvas: TalismanCanvas
var _elem_cabinet: Control = null


func _init() -> void:
	panel_title = "制符台"
	panel_hint = "ESC 关闭 · 兽皮丢进皮匣"


func facility_visual() -> Dictionary:
	return UIKit.facility_style("talisman")


func open() -> void:
	super.open()
	# 2026-10-31：制符台直接进入符匣。所有符先走笔，再按当前境界成功率结算。
	_open_elem_cabinet()


func _input(event: InputEvent) -> void:
	if _elem_cabinet != null and is_instance_valid(_elem_cabinet):
		return
	super(event)


func _open_elem_cabinet() -> void:
	if _elem_cabinet != null and is_instance_valid(_elem_cabinet):
		_elem_cabinet.queue_free()
	var cab = load("res://scripts/ui/talisman_cabinet.gd").new()
	cab.use_stage_bg = true
	cab.closed.connect(func() -> void:
		_elem_cabinet = null
		close())
	add_child(cab)
	_elem_cabinet = cab


# ===================== 舞台口径 =====================

func craft_kind() -> String:
	return "talisman"


func stage_texture() -> String:
	return STAGE_ART


func stage_mouth_rect() -> Rect2:
	return Rect2(300.0, 470.0, 260.0, 120.0)


func stage_shelf_rect() -> Rect2:
	return Rect2(960.0, 130.0, 272.0, 320.0)


func stage_dose_center() -> Vector2:
	return Vector2(640.0, 430.0)


func stage_dish_rect() -> Rect2:
	return Rect2(600.0, 470.0, 260.0, 120.0)


func stage_play_rect() -> Rect2:
	return Rect2(320.0, 192.0, 600.0, 250.0)   # 按重绘后的符案面校准（2026-10-28）


func verb_start() -> String:
	return "执笔"


func unit_word() -> String:
	return "张"


func vessel_word() -> String:
	return "案"


func product_word() -> String:
	return "道"


func word_success() -> String:
	return "符成！"


func word_blocked() -> String:
	return "符未画完，符台封闭 —— 先把符路描满"


func play_hint() -> String:
	return "按住鼠标沿金色符路走笔；描满符路这一案的皮全部成符，墨先耗光则尽毁"


## 走笔由符台自己判满，玩法阶段不显示底部按钮（免得玩家以为要点什么）
func play_has_action() -> bool:
	return false


func product_payload(recipe: Dictionary, n: int) -> Dictionary:
	return {
		"id": String(recipe.get("talisman_id", "")),
		"name": String(recipe.get("talisman_name", "")),
		"type": CharacterData.ITEM_TALISMAN,
		"count": n,
		"icon": String(recipe.get("icon", "")),
		"desc": String(recipe.get("desc", "")),
		"talisman_type": String(recipe.get("talisman_type", "")),
		"battle_cooldown": float(recipe.get("battle_cooldown", 0.0)),
		"is_consumable": bool(recipe.get("is_consumable", true)),
	}


# ===================== 走笔玩法 =====================

func _build_play() -> Control:
	_canvas = TalismanCanvas.new()
	_canvas.completed.connect(_on_drawn)
	_canvas.ink_empty.connect(_on_ink_empty)
	return _canvas


func _begin_play() -> void:
	if _canvas != null:
		_canvas.activate()


func _stop_play() -> void:
	# 没有「停手」这一步：走笔由符台自己判满
	pass


func _on_drawn() -> void:
	if _canvas != null:
		_canvas.deactivate()
	settle_ratio(1.0, "符路描满")


func _on_ink_empty() -> void:
	if _canvas != null:
		_canvas.deactivate()
	settle_ratio(0.0, "符墨耗尽")
