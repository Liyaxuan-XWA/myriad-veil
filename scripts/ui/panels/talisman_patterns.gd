class_name TalismanPatterns
extends RefCounted
## 每张符的独立走笔符路（归一化 0~1，绘制在符纸内）。
## 新 7 张元素符按类型共用一张符路；旧烈火 / 磐石符已下架。

const PATTERNS: Dictionary = {
	# ---------- 新 7 张元素符 ----------
	"tal_jinfeng": [
		[Vector2(0.50, 0.08), Vector2(0.50, 0.90)],
		[Vector2(0.20, 0.26), Vector2(0.80, 0.26)],
		[Vector2(0.50, 0.26), Vector2(0.32, 0.44)],
		[Vector2(0.50, 0.26), Vector2(0.68, 0.44)],
		[Vector2(0.36, 0.62), Vector2(0.64, 0.62)],
		[Vector2(0.44, 0.78), Vector2(0.56, 0.78)],
	],
	"tal_huoqiu": [
		[Vector2(0.50, 0.34), Vector2(0.62, 0.40), Vector2(0.62, 0.54),
			Vector2(0.50, 0.60), Vector2(0.38, 0.54), Vector2(0.38, 0.40),
			Vector2(0.50, 0.34)],
		[Vector2(0.50, 0.62), Vector2(0.50, 0.86)],
		[Vector2(0.34, 0.70), Vector2(0.42, 0.82)],
		[Vector2(0.66, 0.70), Vector2(0.58, 0.82)],
		[Vector2(0.26, 0.40), Vector2(0.34, 0.52)],
		[Vector2(0.74, 0.40), Vector2(0.66, 0.52)],
	],
	"tal_yinlei": [
		[Vector2(0.50, 0.08), Vector2(0.38, 0.28), Vector2(0.58, 0.42),
			Vector2(0.42, 0.60), Vector2(0.56, 0.76), Vector2(0.50, 0.92)],
		[Vector2(0.26, 0.20), Vector2(0.38, 0.28)],
		[Vector2(0.68, 0.50), Vector2(0.56, 0.60)],
		[Vector2(0.30, 0.66), Vector2(0.42, 0.60)],
	],
	"tal_muling": [
		[Vector2(0.50, 0.08), Vector2(0.50, 0.90)],
		[Vector2(0.50, 0.28), Vector2(0.32, 0.40), Vector2(0.32, 0.56),
			Vector2(0.46, 0.64)],
		[Vector2(0.50, 0.42), Vector2(0.68, 0.54), Vector2(0.68, 0.70),
			Vector2(0.54, 0.78)],
		[Vector2(0.38, 0.18), Vector2(0.50, 0.26), Vector2(0.62, 0.18)],
		[Vector2(0.42, 0.86), Vector2(0.58, 0.86)],
	],
	"tal_shuihui": [
		[Vector2(0.20, 0.32), Vector2(0.38, 0.26), Vector2(0.56, 0.32),
			Vector2(0.74, 0.26), Vector2(0.84, 0.32)],
		[Vector2(0.16, 0.50), Vector2(0.34, 0.44), Vector2(0.52, 0.50),
			Vector2(0.70, 0.44), Vector2(0.86, 0.50)],
		[Vector2(0.20, 0.68), Vector2(0.38, 0.62), Vector2(0.56, 0.68),
			Vector2(0.74, 0.62), Vector2(0.82, 0.68)],
		[Vector2(0.50, 0.82), Vector2(0.42, 0.74), Vector2(0.50, 0.66),
			Vector2(0.58, 0.74), Vector2(0.50, 0.82)],
	],
	"tal_fengji": [
		[Vector2(0.18, 0.22), Vector2(0.42, 0.16), Vector2(0.64, 0.24),
			Vector2(0.82, 0.18)],
		[Vector2(0.18, 0.46), Vector2(0.40, 0.40), Vector2(0.62, 0.48),
			Vector2(0.84, 0.42)],
		[Vector2(0.18, 0.70), Vector2(0.40, 0.64), Vector2(0.62, 0.72),
			Vector2(0.84, 0.66)],
		[Vector2(0.50, 0.36), Vector2(0.50, 0.60)],
	],
	"tal_tushi": [
		[Vector2(0.28, 0.20), Vector2(0.72, 0.20), Vector2(0.72, 0.78),
			Vector2(0.28, 0.78), Vector2(0.28, 0.20)],
		[Vector2(0.28, 0.50), Vector2(0.72, 0.50)],
		[Vector2(0.50, 0.20), Vector2(0.50, 0.78)],
		[Vector2(0.34, 0.32), Vector2(0.44, 0.42)],
		[Vector2(0.56, 0.58), Vector2(0.66, 0.68)],
	],

}


static func for_item(item_id: String) -> Array:
	if PATTERNS.has(item_id):
		return PATTERNS[item_id]
	var base := item_id
	for suffix in ["_lianqi", "_zhuji", "_jiedan", "_yuanying"]:
		base = base.trim_suffix(suffix)
	return PATTERNS.get(base, [])
