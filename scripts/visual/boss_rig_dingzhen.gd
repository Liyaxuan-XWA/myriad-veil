class_name BossRigDingzhen
extends BossRigHuman
## 定阵先生的骨骼动画集（2026-10-28）。
## 关节：body（躯干 + 头 + 旗匣）├ leg_back / leg_front / arm（持朱砂尺那条臂）。
## 招式动作用基类的「慢蓄力 → 爆发 → 定格」生成器，只写差异：尺臂前探 / 横挥 / 下压。

const DZ_SKILLS := {
	"plant": {"length": 0.60, "windup": 0.60},
	"line": {"length": 0.75, "windup": 0.75},
	"pull": {"length": 0.65, "windup": 0.65},
	"seal": {"length": 1.10, "windup": 1.10},
	"sweep": {"length": 0.62, "windup": 0.62},
	"step": {"length": 0.55, "windup": 0.55},
	"pile": {"length": 1.10, "windup": 1.10},
	"burst": {"length": 1.20, "windup": 1.20},
}


func _skill_table() -> Dictionary:
	return DZ_SKILLS


func _make_skill(anim: String) -> Animation:
	var a := _skill_anim(anim)
	match anim:
		"plant":
			_strike(a, anim, Vector2(-4.0, 2.0), Vector2(8.0, -4.0),
				-0.55, 0.50, -0.03, 0.04, Vector2(1.01, 0.99))
		"line":
			_strike(a, anim, Vector2(-6.0, 2.0), Vector2(14.0, -2.0),
				-0.75, 0.60, -0.04, 0.05, Vector2(1.02, 0.98))
		"pull":
			_strike(a, anim, Vector2(8.0, 0.0), Vector2(-12.0, 2.0),
				0.60, -0.50, 0.05, -0.04, Vector2(1.00, 1.00))
		"seal":
			_strike(a, anim, Vector2(-8.0, -6.0), Vector2(10.0, 8.0),
				-0.90, 0.55, -0.06, 0.08, Vector2(1.04, 0.96))
		"sweep":
			_strike(a, anim, Vector2(-6.0, 0.0), Vector2(16.0, -2.0),
				-1.05, 0.70, -0.05, 0.06, Vector2(1.02, 0.98))
		"step":
			_strike(a, anim, Vector2(-4.0, 2.0), Vector2(20.0, 0.0),
				-0.35, 0.55, -0.03, 0.04, Vector2(1.03, 0.97))
		"pile":
			_strike(a, anim, Vector2(-8.0, -14.0), Vector2(10.0, 16.0),
				-1.10, 0.75, -0.08, 0.10, Vector2(0.95, 1.06))
		"burst":
			_strike(a, anim, Vector2(-6.0, -10.0), Vector2(8.0, 12.0),
				-1.20, 0.80, -0.09, 0.11, Vector2(0.94, 1.08))
		_:
			_strike(a, anim, Vector2(-4.0, 2.0), Vector2(10.0, -2.0),
				-0.55, 0.50, -0.03, 0.04, Vector2(1.01, 0.99))
	return a
