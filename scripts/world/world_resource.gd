class_name WorldResource
extends Node2D
## 大世界可交互资源：药材 / 灵气团 / 传送门
##
## 交互统一入口 try_interact()，由 secret_world.gd 在玩家按 F 时调用。
## 本节点只负责「外观 + 自身这一下能不能拿」，是否移除 / 何时重生由世界管理器决定。
##
## 外观走 ArtDB（visual_id 取自 SecretWorldDB），未接贴图时是色块占位。

const KIND_HERB := "herb"
const KIND_QI := "qi"
const KIND_PORTAL := "portal"
## 森林灵田地块：外观、交互距离、提示都由 FarmPlot 子类接管，世界管理器只负责调度
const KIND_FARM := "farm"
## 九天门（幽冥灵墟中心，通往九天之上）：由子类 HuashenGate 接管外观与提示
const KIND_GATE := "gate"
## 化神坛（九天之上中央）：进门之后在这里吃掉化神破境晶、当场突破
const KIND_ALTAR := "altar"
## 石台插剑（练气区彩蛋，2026-11-12）：一次性设施，取走一件装备后**永久消失**
const KIND_RELIQUARY := "reliquary"
## 铸神祭坛（2026-11-13）：每区一座常驻；交互分两阶段发铸神晶 / 补天石
const KIND_GOD_ALTAR := "god_altar"

## 采集 / 吸收的交互距离（像素）
const REACH_HERB := 74.0
const REACH_QI := 92.0
const REACH_PORTAL := 120.0
## 石台比草药宽，但必须明显小于传送门的 120：剑就摆在门北 340 处，
## 两个距离相加 < 间距，站在门边不会同时够到两样东西（谁近听谁的）。
const REACH_RELIQUARY := 88.0
## 祭坛石台比剑台大，站位松一点；门槛仍低于传送门
const REACH_GOD_ALTAR := 120.0

## 灵气团是引导式交互：站在范围内吸收满这么久才入账（用户 2026-10-23 定）
const QI_ABSORB_TIME := 5.0

var kind: String = KIND_HERB
var node_id: String = ""
## 药材：ItemDB 材料 id 与数量
var material_id: String = ""
var amount: int = 1
var display_name: String = ""
## 药材归属：不设 = 永久背包；苍澜大陆指向「局内背包」
## 签名 (material_id: String, amount: int) -> bool（false = 背包已满，本次采集失败）
var herb_sink: Callable = Callable()
## 石台插剑：要给出的装备模板 id。
## 拔出来直接进**永久背包**（用户 2026-11-12 定，不走局内背包）：
##   彩蛋只有一次，走局内背包会被大陆死亡回滚吃掉。
##   永久消失的标记仍由世界管理器写，补发见 secret_world._ensure_reliquary_reward。
var reward_equipment: String = ""

var _visual: SkinVisual
var _label: Label
var _time: float = 0.0


func setup(p_kind: String, p_node_id: String, p_visual_id: String, p_name: String) -> void:
	kind = p_kind
	node_id = p_node_id
	display_name = p_name
	set_meta("visual_id", p_visual_id)


func _ready() -> void:
	z_index = 1
	var visual_id := String(get_meta("visual_id", ""))
	if visual_id == "":
		visual_id = "world_qi_orb"
	_visual = SkinVisual.new()
	_visual.visual_id = visual_id
	add_child(_visual)
	_visual.refresh()

	_label = UIKit.label(display_name, UIKit.F_SMALL, _label_color())
	_label.size = Vector2(120.0, 18.0)
	# 贴在形象上沿外面，而不是写死一个高度：接了贴图之后传送门有 128px 高，
	# 原来那个 -56 会正好压在门洞中间。
	_label.position = Vector2(-60.0, _visual.top_extent() - 20.0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	# 药材用的是「拔出来平铺拍」的定妆图标，原样摆出去同一丛三株就是复制粘贴。
	# 按 node_id 做**确定性**抖动（同一株每次进图长得一样，不会看两眼花），
	# 让它读作地里长的东西而不是 UI 图标。
	if kind == KIND_HERB:
		# ⚠ hash() 会返回负数，GDScript 的 % 跟着被除数符号走 —— 不 absi 会抖出负角度
		var r := float(absi(hash(node_id) % 1000)) / 1000.0
		var s := float(absi(hash(node_id + "|s") % 100)) / 100.0
		var f := -1.0 if absi(hash(node_id + "|f")) % 2 == 1 else 1.0
		_visual.rotation_degrees = -9.0 + 18.0 * r
		# 镜像走 scale.x 的符号，不走 flip_h：SkinVisual 是 Node2D，没有 flip_h 这个属性
		# （flip_h 在 Sprite2D 上，而这里要翻的是整条视觉子树，和玩家翻转同一套口径）
		_visual.scale = Vector2(f * (0.90 + 0.20 * s), 0.90 + 0.20 * s)

	if kind == KIND_QI:
		var pulse := create_tween().set_loops()
		pulse.tween_property(_visual, "scale", Vector2(1.25, 1.25), 0.7).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(_visual, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)
	# 只有灵气团需要每帧浮动：石头门和长在地里的草上下飘会读成在飞
	set_process(kind == KIND_QI)
	refresh_altar_look()


## 铸神祭坛：晶石取走后压暗；阶段 2 再暗一档（不用第二张美术也能看出「已经取空」）
func refresh_altar_look() -> void:
	if kind != KIND_GOD_ALTAR or _visual == null or not is_instance_valid(_visual):
		return
	var stage := CharacterData.god_altar_stage(node_id)
	_visual.modulate = Color(1.0, 1.0, 1.0, 1.0) if stage == 0 		else (Color(0.80, 0.80, 0.86, 1.0) if stage == 1 else Color(0.52, 0.52, 0.58, 1.0))


func _process(delta: float) -> void:
	_time += delta
	if _visual != null and is_instance_valid(_visual):
		_visual.position.y = sin(_time * 2.0) * 2.5


func reach_distance() -> float:
	match kind:
		KIND_QI:
			return REACH_QI
		KIND_PORTAL:
			return REACH_PORTAL
		KIND_RELIQUARY:
			return REACH_RELIQUARY
		KIND_GOD_ALTAR:
			return REACH_GOD_ALTAR
		_:
			return REACH_HERB


func prompt_text() -> String:
	match kind:
		KIND_QI:
			return "F　吸收灵气（%d 秒）" % int(QI_ABSORB_TIME)
		KIND_PORTAL:
			return "F　返回原初位面"
		KIND_RELIQUARY:
			return "F　拔出石台上的 %s" % display_name
		KIND_GOD_ALTAR:
			# 阶段 / 化神状态直接读存档（祭坛本身不存阶段）
			var stage := CharacterData.god_altar_stage(node_id)
			if stage >= 2:
				return "祭坛已空"
			if stage == 1 and not CharacterData.is_huashen():
				return "F　祭坛沉寂（化神后可再取）"
			if stage == 0:
				return "F　取走铸神晶"
			if node_id == "hs_god_altar":
				return "F　取走铸神晶、补天石与蕴仙髓"
			return "F　取走铸神晶与补天石"
		_:
			return "F　采集 %s" % display_name


## 交互结果：
##   ok     本次是否成功（失败只提示，不移除）
##   message 提示文案
##   color   提示颜色
##   remove  成功后是否把本节点从场上移除
func try_interact() -> Dictionary:
	match kind:
		KIND_HERB:
			return _interact_herb()
		KIND_QI:
			return _interact_qi()
		KIND_RELIQUARY:
			return _interact_reliquary()
		# 灵田地块（FarmPlot）不走这里：由 secret_world 直接调地块交互，节点常驻
		_:
			return {"ok": false, "message": "", "color": UIKit.C_TEXT, "remove": false}


## 石台插剑：拔剑 → 直接进永久背包 → remove=true 让世界管理器落永久标记。
## ⚠ 背包满时**不许消失**（ok=false / remove=false）：设施是一次性的，
##   先把剑吞掉再告诉玩家「放不下」就等于把彩蛋删了。
func _interact_reliquary() -> Dictionary:
	var tpl := ItemDB.get_equipment_template(reward_equipment)
	if tpl.is_empty():
		return {"ok": false, "message": "石台上的刻文模糊，看不出是什么剑。",
				"color": UIKit.C_WARN, "remove": false}
	var item: Dictionary = CharacterData.make_equipment_instance(tpl)
	if not CharacterData.add_item(item):
		return {"ok": false,
				"message": "%s，暂时放不下「%s」" % [CharacterData.bag_full_message(item),
					String(item.get("name", reward_equipment))],
				"color": UIKit.C_DANGER, "remove": false}
	GameState.play_ui("forge_great")
	# 回执点名「已入背包」：大陆里玩家看到的 B 键包是局内背包，不说清楚会以为剑丢了
	return {"ok": true, "message": "拔出「%s」—— 已入背包，石台裂开，剑不再回来"
			% String(item.get("name", reward_equipment)), "color": UIKit.C_GREAT,
			"remove": true}


func _interact_herb() -> Dictionary:
	if herb_sink.is_valid():
		if not bool(herb_sink.call(material_id, amount)):
			return {"ok": false, "message": "局内背包已满，无法采集", "color": UIKit.C_DANGER, "remove": false}
		GameState.play_ui("pickup")
		return {
			"ok": true,
			"message": "采集 %s ×%d（局内背包）" % [display_name, amount],
			"color": UIKit.C_OK,
			"remove": true,
		}
	if _bag_would_reject(material_id):
		return {"ok": false, "message": "背包已满，无法采集", "color": UIKit.C_DANGER, "remove": false}
	CharacterData.grant_material(material_id, amount)
	GameState.play_ui("pickup")
	return {
		"ok": true,
		"message": "采集 %s ×%d" % [display_name, amount],
		"color": UIKit.C_OK,
		"remove": true,
	}


## 灵气团开始引导前的检查：ok=false 时只提示、不开始读条
func check_absorbable() -> Dictionary:
	if kind != KIND_QI:
		return {"ok": false, "message": "", "color": UIKit.C_TEXT}
	if CharacterData.is_stage_full():
		return {
			"ok": false,
			"message": "本阶段修为已满，需在境界面板突破后方可继续吸收",
			"color": UIKit.C_WARN,
		}
	return {"ok": true, "message": "", "color": UIKit.C_TEXT}


func _interact_qi() -> Dictionary:
	var check := check_absorbable()
	if not bool(check.get("ok", false)):
		return {
			"ok": false,
			"message": check.get("message", ""),
			"color": check.get("color", UIKit.C_WARN),
			"remove": false,
		}
	# 灵气团随机 50~200 修为（2026-10-24 用户定）
	var gained := CharacterData.add_realm_exp(randi_range(50, 200))
	if gained <= 0:
		return {"ok": false, "message": "灵气散逸，未能吸收", "color": UIKit.C_WARN, "remove": false}
	GameState.play_ui("pickup")
	return {
		"ok": true,
		"message": "吸收灵气　修为 +%d" % gained,
		"color": UIKit.C_HUD_MANA,
		"remove": true,
	}


## 背包还能不能塞下这种材料（有同类堆叠时永远可以）
func _bag_would_reject(mid: String) -> bool:
	return not CharacterData.bag_has_room(
		{"id": mid, "type": CharacterData.ITEM_MATERIAL})


func _label_color() -> Color:
	match kind:
		KIND_QI:
			return UIKit.C_HUD_MANA
		KIND_PORTAL:
			return UIKit.C_ASCEND
		_:
			return UIKit.C_ACCENT
