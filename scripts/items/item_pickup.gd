extends Area2D
## 掉落物（战场可拾取）
##
## 由 BOSS 死亡时按 ItemDB 掉落表生成，玩家走进范围内按 F 拾取。
## 拾取后物品进入随身背包（CharacterData.inventory），可在角色面板（Tab）「装备」分类中穿戴。
##
## 设计要点：
##   - 地面掉落物必须有醒目的存在感：光柱 + 上下浮动 + 名称标签，远远就能看见
##   - 走近才显示「F 拾取」提示，避免全屏飘字干扰战斗
##   - 拾取优先由 CombatArena 统一处理（它知道玩家在哪），本节点只负责「有没有玩家在范围内」

signal picked_up(pickup: Area2D)

## 待拾取物品（CharacterData 背包可直接吞下的结构）
var item: Dictionary = {}

## 拾取归属：不设 = 直接进永久背包（原初位面/战斗掉落）
## 苍澜大陆把它指向「局内背包」—— 死亡清空、撤离才带回
var pickup_handler: Callable = Callable()

## 这一次拾取最后落在哪：0 没捡到 / 1 进背包 / 2 进仓库（背包满时的溢出落点）。
## 调用方（竞技场）用它决定提示语，别自己再猜一遍。
var last_sink: int = 0

## 自动拾取的「刚丢下」宽限（秒，绝对时间）：玩家从行囊拖出来丢地上的东西，
## 自动拾取要先让开，否则丢出去立刻被吸回来、永远扔不掉。F 键仍可手动捡。
var auto_pick_block_until: float = 0.0


## 自动拾取能不能碰它（宽限期内为 false）
func auto_pickable() -> bool:
	return Time.get_ticks_msec() / 1000.0 >= auto_pick_block_until

## 玩家是否在拾取范围内
var _player_inside: bool = false
var _hint: Label
## 本掉落物实际采用的显示参数（含 item 覆盖），拾取特效也要用同一份
var _cfg: Dictionary = {}

const BEAM_SHADER := "res://assets/shaders/drop_beam.gdshader"
static var _glow_tex: Texture2D = null


func _ready() -> void:
	add_to_group("item_pickup")
	input_pickable = false  # 拾取用按键，不需要鼠标点选（避免战斗中误点）
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_setup_visual()


## 视觉：品质光柱 + 地面光晕 + 落地阴影 + 躺在地上的物品 + 拾取提示
## 全部尺寸 / 颜色 / 浮动参数来自 ArtDB.PICKUP_BEAM —— 换美术只改表，本文件不含硬编码
## 物品本体走 SkinVisual（美术接入 art_db.gd 的 "item_pickup" 条目即可替换）
## 未接入贴图时回退为「品阶色方块」，与 UI 的装备色块口径一致
func _setup_visual() -> void:
	var cfg: Dictionary = ArtDB.get_pickup_beam()
	# ⚠ 局内小件（试炼回血丹）可在 item 里带一组覆盖参数；
	#   没带的普通掉落物 100% 走全局 PICKUP_BEAM，主模式表现零变化。
	if item.has("pickup_style"):
		var style: Dictionary = item.get("pickup_style")
		for k in style.keys():
			cfg[k] = style[k]
	_cfg = cfg.duplicate(true)
	var item_name := String(item.get("name", "掉落物"))
	var qcolor := _quality_color(cfg)

	# 品质光柱：软边竖光 + 地面光晕（加法混合，没有矩形边框）
	var beam := ColorRect.new()
	beam.size = cfg["beam_size"]
	beam.position = cfg["beam_offset"]
	beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var beam_mat := ShaderMaterial.new()
	beam_mat.shader = load(BEAM_SHADER)
	beam_mat.set_shader_parameter("tint", qcolor)
	beam_mat.set_shader_parameter("strength", float(cfg["beam_strength"]))
	beam.material = beam_mat
	add_child(beam)

	var glow := Sprite2D.new()
	glow.texture = _glow_texture()
	glow.position = cfg["glow_position"]
	var gsize: Vector2 = cfg["glow_size"]
	glow.scale = Vector2(gsize.x / 64.0, gsize.y / 64.0)
	glow.modulate = Color(qcolor.r, qcolor.g, qcolor.b, float(cfg["glow_alpha"]))
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = glow_mat
	add_child(glow)

	# 落地阴影：压在光晕上、物品下，让物品「贴」在地上
	var shadow := Sprite2D.new()
	shadow.texture = _glow_texture()
	shadow.position = cfg["shadow_position"]
	var ssize: Vector2 = cfg["shadow_size"]
	shadow.scale = Vector2(ssize.x / 64.0, ssize.y / 64.0)
	shadow.modulate = Color(0.0, 0.0, 0.0, float(cfg["shadow_alpha"]))
	add_child(shadow)

	# 接触阴影：更小更实，压在物品正下方
	var contact := Sprite2D.new()
	contact.texture = _glow_texture()
	contact.position = cfg["contact_shadow_position"]
	var csize: Vector2 = cfg["contact_shadow_size"]
	contact.scale = Vector2(csize.x / 64.0, csize.y / 64.0)
	contact.modulate = Color(0.0, 0.0, 0.0, float(cfg["contact_shadow_alpha"]))
	add_child(contact)

	# 物品本体：躺在地上 —— 武器转到接近水平，其它物品轻微倾斜；
	# 外层节点再压扁 Y，模拟「倒在地上」的投影。图标/色块都挂在里面。
	var body := Node2D.new()
	body.position = Vector2(0.0, float(cfg["body_offset_y"]))
	body.scale = Vector2(1.0, float(cfg["ground_squash"]))
	add_child(body)
	var tilt_deg := float(cfg["ground_tilt_weapon_deg"]) if _is_weapon() else float(cfg["ground_tilt_deg"])

	# 物品本体：**优先显示装备自己的图标**（数据里的 icon 字段）
	# 没配图标时退回原来的 SkinVisual 品阶色块
	var icon_path := String(item.get("icon", ""))
	var placed := false
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tex: Texture2D = load(icon_path)
		if tex != null:
			# 统一缩放到「最长边 N px」：地面上不需要原图分辨率，也不能大小不一
			var longest := maxf(float(tex.get_width()), float(tex.get_height()))
			var k := float(cfg["icon_longest"]) / maxf(longest, 1.0)
			# 厚度：先在下方叠几层同形暗色（越靠下越暗），主图标压在最上面
			var layers := int(cfg.get("thickness_layers", 2))
			var step := float(cfg.get("thickness_step", 2.6))
			for s in range(layers, 0, -1):
				var side := Sprite2D.new()
				side.texture = tex
				side.scale = Vector2(k, k)
				side.rotation = deg_to_rad(tilt_deg)
				side.position = Vector2(0.0, step * float(s))
				var shade := lerpf(0.46, 0.26, float(s - 1) / maxf(1.0, float(layers - 1)))
				side.modulate = Color(shade, shade * 0.96, shade * 0.92, 1.0)
				body.add_child(side)
			var spr := Sprite2D.new()
			spr.texture = tex
			spr.scale = Vector2(k, k)
			spr.rotation = deg_to_rad(tilt_deg)
			body.add_child(spr)
			placed = true
	if not placed:
		# 没配图标 → 退回品阶 / 稀有度色块占位
		var block := SkinVisual.new()
		block.visual_id = "item_pickup"
		var grade := String(item.get("equipment_grade", ""))
		if grade != "":
			block.placeholder_color_override = UIKit.grade_color(grade)
		else:
			var rarity := ItemDB.item_rarity(item)
			block.placeholder_color_override = ItemDB.rarity_color(rarity) 				if rarity != "" else cfg["fallback_placeholder_color"]
		block.rotation = deg_to_rad(tilt_deg)
		body.add_child(block)
		block.refresh()

	# 掉落入场：从上方落下、轻微回弹后停在光柱底
	body.position.y -= float(cfg["drop_in_height"])
	body.modulate.a = 0.0
	var drop_tween := create_tween()
	drop_tween.tween_property(body, "position:y", float(cfg["body_offset_y"]),
		float(cfg["drop_in_time"])).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	drop_tween.parallel().tween_property(body, "modulate:a", 1.0,
		float(cfg["drop_in_time"]) * 0.5)

	# 拾取提示（靠近才显示）
	_hint = Label.new()
	_hint.text = String(cfg["hint_text"])
	_hint.add_theme_font_size_override("font_size", int(cfg["hint_font_size"]))
	_hint.add_theme_color_override("font_color", cfg["hint_color"])
	_hint.position = cfg["hint_offset"]
	_hint.size = cfg["hint_size"]
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.03, 0.95))
	_hint.add_theme_constant_override("outline_size", 3)
	_hint.visible = false
	add_child(_hint)




## 武器要把图标转平才像「躺在地上」；其它物品只轻微倾斜
func _is_weapon() -> bool:
	return String(item.get("equipment_type", "")) == "weapon"


## 光柱 / 光晕颜色：装备取品阶色，材料取稀有度色；都没有时用金色兜底
func _quality_color(cfg: Dictionary) -> Color:
	# 局内小件可自带光柱色（试炼回血丹用玉青，和朱砂/品阶色区分）
	if item.has("pickup_tint"):
		var tint: Color = item.get("pickup_tint")
		return tint
	var grade := String(item.get("equipment_grade", ""))
	var rarity := ItemDB.item_rarity(item)
	if grade == "" and rarity == "":
		return cfg.get("fallback_color", Color(0.98, 0.84, 0.45, 1.0))
	return ItemDB.item_border_color(item)


## 地面光晕贴图：径向白→透明，只做一次并缓存
static func _glow_texture() -> Texture2D:
	if _glow_tex != null:
		return _glow_tex
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	g.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	g.add_point(0.35, Color(1.0, 1.0, 1.0, 0.55))
	g.add_point(0.7, Color(1.0, 1.0, 1.0, 0.12))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_glow_tex = tex
	return tex


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		_hint.visible = true


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = false
		_hint.visible = false


## 玩家是否在范围内（CombatArena 按 F 时查询）
## ⚠ 不能只信 body_entered：掉落物若正好生成在玩家脚下（怪死在脚边很常见），
##   入树那一刻的 overlap 可能因物理帧时序没转成 body_entered，
##   于是出现「人明明站在丹上，按 F 却没反应 / F 提示也不亮」。
##   按 F 的瞬间再查一次实时重叠兜底，并顺手同步提示可见性。
func has_player_inside() -> bool:
	if _player_inside:
		return true
	for b in get_overlapping_bodies():
		if b.is_in_group("player"):
			_player_inside = true
			if _hint != null:
				_hint.visible = true
			return true
	return false


## 拾取：按归属入包。返回是否成功（背包满则失败，掉落物保留在原地）
func try_pickup() -> bool:
	last_sink = 0
	if item.is_empty():
		return false
	if pickup_handler.is_valid():
		if not bool(pickup_handler.call(item)):
			return false
		last_sink = 1
	else:
		# 2026-11-12 用户定：先背包（同款能叠就叠，满格也能叠上去），满格才溢到仓库
		last_sink = CharacterData.add_item_or_warehouse(item)
		if last_sink == 0:
			return false
	# 图鉴：拾取即永久记录「获得过」，之后即使丢弃 / 死亡丢失也仍然解锁
	CharacterData.mark_codex_from_item(item)
	# 元魂：拾取即永久记录（每种元魂全局只掉一次，之后同一 BOSS 不再掉）
	if ItemDB.is_soul_item(String(item.get("id", ""))):
		CharacterData.mark_soul_obtained(String(item.get("id", "")))
	# 新手指引：捡到东西要报给教学。事件名带物品 id（item_picked:mat_xxx），
	# 教学步骤可以精确要求「捡到锻造晶石」而不只是「捡到任意东西」。
	Tutorial.note("item_picked:" + String(item.get("id", "")))
	picked_up.emit(self)
	_play_pickup_effect()
	return true


## 拾取特效：向上飞起 + 渐隐，然后销毁（高度与时长读 ArtDB.PICKUP_BEAM）
func _play_pickup_effect() -> void:
	_hint.visible = false
	var cfg: Dictionary = _cfg.duplicate(true)
	if cfg.is_empty():
		cfg = ArtDB.get_pickup_beam()
	var rise := float(cfg["pickup_rise"])
	var ptime := float(cfg["pickup_time"])
	var tween := create_tween()
	tween.tween_property(self, "position:y", position.y - rise, ptime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "modulate:a", 0.0, ptime)
	tween.tween_callback(queue_free)
