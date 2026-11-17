class_name DamageNumber
extends RefCounted
## 伤害数字飘字 —— 全项目**唯一**的伤害数字生成入口
##
## 配色规则（用户 2026-10-29 改定）：
##   - **所有伤害飘字只按伤害类型两色**：物理伤害黄色 / 法术伤害蓝色。
##   - 不再有「BOSS→玩家红色」等第三色；玩家挨打也按 BOSS 这一下的攻击类型取色。
##
## 接入方式（受击方自己飘，天然覆盖所有伤害路径）：
##   BossBase.take_damage()  → DamageNumber.spawn(..., DamageNumber.kind_from_damage_kind(kind))
##   Player._apply_damage()  → DamageNumber.spawn(..., DamageNumber.kind_from_damage_kind(attack_kind))
## 因此普攻 / 功法 / 投射物 / 反弹 / 刀痕 / BOSS 物理法术都会自动有数字，不用逐个调用点去加。
##
## 美术接入（长期约定）：
##   - 两个颜色在 `ui_kit.gd` 的 `C_DMG_PHYS` / `C_DMG_SPELL`（换皮改那一处）
##   - 字号、描边、飘起距离、存活时间都在本文件顶部常量，改动画不用动逻辑
##   - 将来要换成贴图数字，把这里换成 `TextureRect` + `ArtDB` 里登记的图集即可

## ===== 表现参数（可替换）=====
const FONT_SIZE := 22
const FONT_SIZE_BIG := 28      ## 暴击/大伤害稍大（预留）
## 2026-11-04：数字是文字三级里的「数字级」——靠明度和字号站住，不靠粗描边。
## 战斗场景确实花，所以保留 1px 极细边 + 柔和投影（左上光 → 影子向右下）。
const OUTLINE_SIZE := 1
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.50)
const RISE_DISTANCE := 46.0    ## 上飘距离（像素）
const LIFETIME := 0.7          ## 存活时间（秒）
const HORIZONTAL_JITTER := 24.0 ## 水平随机偏移，避免多段命中叠字
const Z_INDEX := 40            ## 压在实体与血条之上

enum Kind {
	PHYSICAL,   ## 物理伤害（黄）
	SPELL,      ## 法术伤害（蓝）
}


## 按伤害类型取飘字种类：physical_melee / physical_projectile / physical → 物理，其余 → 法术
static func kind_from_damage_kind(damage_kind: String) -> int:
	return Kind.PHYSICAL if damage_kind.begins_with("physical") else Kind.SPELL


static func color_for(kind: int) -> Color:
	match kind:
		Kind.PHYSICAL:
			return UIKit.C_DMG_PHYS
		_:
			return UIKit.C_DMG_SPELL


## 生成一个伤害飘字
## parent   承载节点（一般是战斗场景根 Node2D）
## world_pos 世界坐标（通常是受击者位置）
## amount   **实际扣血量**（已扣抗性后的值，不是调用方传入的原始伤害）
## kind     Kind 枚举
static func spawn(parent: Node, world_pos: Vector2, amount: float, kind: int) -> void:
	if parent == null or not is_instance_valid(parent) or amount < 0.0:
		return

	var label := Label.new()
	label.text = str(int(round(amount)))
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color_for(kind))
	UIKit.soft_text_shadow(label, OUTLINE_SIZE)
	label.add_theme_color_override("font_shadow_color", SHADOW_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.z_index = Z_INDEX
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var origin := world_pos
	if parent is Node2D:
		origin = (parent as Node2D).to_local(world_pos)
	# 左右轻微错开，多段命中时数字不会糊成一坨
	origin += Vector2(randf_range(-HORIZONTAL_JITTER, HORIZONTAL_JITTER) * 0.5, -18.0)
	label.position = origin - Vector2(40.0, 12.0)
	label.size = Vector2(80.0, 24.0)
	parent.add_child(label)

	var tween := label.create_tween()
	# 先弹一下再上飘，给命中一点分量
	label.scale = Vector2(0.6, 0.6)
	label.pivot_offset = Vector2(40.0, 12.0)
	tween.tween_property(label, "scale", Vector2(1.15, 1.15), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.08)
	tween.parallel().tween_property(label, "position:y", label.position.y - RISE_DISTANCE, LIFETIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, LIFETIME).set_delay(LIFETIME * 0.45)
	tween.tween_callback(label.queue_free)
