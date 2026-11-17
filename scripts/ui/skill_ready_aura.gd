class_name SkillReadyAura
extends Node2D
## 技能就绪光环 —— 绕技能格旋转的剑气环
##
## 用途：战斗 HUD 技能栏里「剑意已满层且冷却已转好」时，在吃剑意的大招格子上
##   （一剑开天 / 万剑归宗）绕图标旋转，提示玩家「现在放就是满层形态」。
##
## 美术接入（长期约定，与 ArtDB.EFFECTS 同一思路）：
##   外观全部读 `ArtDB.AURAS` 表（color / core_color / radius / arc_count /
##   arc_sweep_deg / thickness / spin_deg / pulse_amp / pulse_speed），
##   **本脚本不含任何硬编码外观** —— 换皮只改 art_db.gd 的 AURAS 条目。
##   条目 id 见常量 AURA_INTENT_READY。
##
## 接入方式（combat_arena.gd 技能栏）：
##   var aura := SkillReadyAura.new()
##   row.add_child(aura)                 # ⚠ 必须挂 row（ sibling ），不能挂格子里：
##                                       #   格子 clip_contents=true，超出 48px 的环会被裁掉
##   aura.global_position = 格子中心     # 由 _update_skill_bar 每帧对齐
##   aura.visible = <就绪条件>           # 不可见时停转（_process 直接 return）

## 光环条目 id（ArtDB.AURAS 的键）
const AURA_INTENT_READY := "fx_skill_intent_ready"

## 条目 id（换条目只改这一个字符串）
var aura_id: String = AURA_INTENT_READY

## 配置缓存（_ready 时从 ArtDB.AURAS 取）
var _cfg: Dictionary = {}

## 累计旋转角（弧度）与呼吸相位
var _spin: float = 0.0
var _phase: float = 0.0


func _ready() -> void:
	_cfg = ArtDB.get_aura(aura_id)


func _process(delta: float) -> void:
	if not visible:
		return
	_spin += deg_to_rad(float(_cfg.get("spin_deg", 240.0))) * delta
	_phase += float(_cfg.get("pulse_speed", 6.0)) * delta
	queue_redraw()


func _draw() -> void:
	if _cfg.is_empty():
		return
	var color: Color = _cfg.get("color", Color.WHITE)
	var core: Color = _cfg.get("core_color", Color.WHITE)
	var count := maxi(1, int(_cfg.get("arc_count", 3)))
	var sweep := deg_to_rad(float(_cfg.get("arc_sweep_deg", 70.0)))
	var thickness := float(_cfg.get("thickness", 2.5))
	# 呼吸：半径在 1±pulse_amp 之间缓慢起伏，让光环「活」着
	var pulse := 1.0 + sin(_phase) * float(_cfg.get("pulse_amp", 0.10))
	var r := float(_cfg.get("radius", 30.0)) * pulse
	for i in range(count):
		var a0 := _spin + TAU * float(i) / float(count)
		# 主弧段
		draw_arc(Vector2.ZERO, r, a0, a0 + sweep, 20, color, thickness, true)
		# 内侧细亮边（芯色，收在弧段中段，做出「剑刃包着光」的层次）
		draw_arc(Vector2.ZERO, r - thickness * 0.9,
			a0 + sweep * 0.18, a0 + sweep * 0.82, 12, core, 1.0, true)
