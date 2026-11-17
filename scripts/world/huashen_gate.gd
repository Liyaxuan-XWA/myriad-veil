class_name HuashenGate
extends WorldResource
## 九天门与化神坛 —— 化神之路的两个交互点，共用这一个节点类。
##
##   门：幽冥灵墟中心、元婴区首领镇墟石犼身后（山门贴图那个坐标）。
##       元婴后期圆满 + 持有完整化神破境晶 → 开门进九天之上，**不吃材料**。
##   坛：九天之上中央。进门之后登坛才吃掉化神破境晶、当场突破。
##
## 两者的外观都由场景里的地标贴图负责（门就是那座山门图），本节点只撑交互范围、
## 按当前条件说一句话，剩下的交给 secret_world 的 KIND_GATE / KIND_ALTAR 分支。

const REACH_GATE := 210.0
const REACH_ALTAR := 170.0
const ALTAR_TEX := "res://assets/scenes/world/huashen_altar.png"
## 346×346 的坛图（含云座与光轮）在世界里的显示倍率
const ALTAR_SCALE := 0.62

var _is_altar: bool = false


func setup_gate() -> void:
	kind = KIND_GATE
	node_id = "huashen_gate"
	display_name = "九天门"
	set_meta("visual_id", "world_portal")


func setup_altar() -> void:
	kind = KIND_ALTAR
	node_id = "huashen_altar"
	display_name = "化神坛"
	_is_altar = true
	set_meta("visual_id", "world_portal")


func _ready() -> void:
	super._ready()
	# 山门本体是地标那张大图，再叠一个传送门形象会盖住门洞；只留头顶的名字。
	if _visual != null and is_instance_valid(_visual):
		_visual.visible = false
	if _label != null:
		_label.text = "化神坛 · 登坛突破化神" if _is_altar else "九天门 · 通往九天之上"
	if _is_altar:
		_build_altar_sprite()


## 九天之上没有别的建筑，坛要自己带图：底边压在落点上，和 WorldEnemy 同一口径。
func _build_altar_sprite() -> void:
	if not ResourceLoader.exists(ALTAR_TEX):
		return
	var tex := load(ALTAR_TEX) as Texture2D
	if tex == null:
		return
	var spr := Sprite2D.new()
	spr.name = "AltarArt"
	spr.texture = tex
	spr.centered = false
	spr.scale = Vector2.ONE * ALTAR_SCALE
	spr.position = Vector2(-tex.get_width() * ALTAR_SCALE * 0.5,
		-tex.get_height() * ALTAR_SCALE)
	spr.z_index = -1
	add_child(spr)
	# 名字抬到光轮上方，别压在坛身上
	if _label != null:
		_label.position = Vector2(-60.0, -tex.get_height() * ALTAR_SCALE - 16.0)


func reach_distance() -> float:
	return REACH_ALTAR if _is_altar else REACH_GATE


## 交互条上只放一行短提示，长句留给按 F 之后的公告条
func prompt_text() -> String:
	if _is_altar:
		var a := CharacterData.huashen_altar_check()
		if bool(a.get("ok", false)):
			return String(a.get("message", ""))
		return "化神坛 · " + String(a.get("message", ""))
	return CharacterData.huashen_gate_prompt()
