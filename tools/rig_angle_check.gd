extends SceneTree

## 引擎侧口径自检：让 BossRig 自己算命中帧的刀尖朝向，和离线渲染器
## （tools/render_rig_pose.py）对一遍。
##
## 换定妆图 / 改拆件脚本 / 改 `_strike` 之后跑一次：
##   godot --headless --path . --quit-after 300 -s res://tools/rig_angle_check.gd
## 静止那一行必须和 rig.tres 的 muzzle 锚点读数一致（现在 528.9,694.5 / +70.0°），
## 不一致 = 引擎和预览器两套口径又分叉了。招式那几行允许差 3~6°，
## 那是躯干挤压拉伸（非等比 scale）把角度 skew 掉了，属于设计内。
##
## ⚠ `muzzle_position()` 只认 muzzle_anim 里登记过的动作名（刀客只登记了
##   palm_project），所以查别的招式时也要传那个名字 —— 部件和偏移是同一份，
##   变的只是节点当前变换。

func _initialize() -> void:
	var rig := BossRigHuman.new()
	if not rig.setup_from_path("res://assets/characters/boss/daoke_rig/rig.tres"):
		print("SETUP FAIL")
		quit(1)
		return
	root.add_child(rig)
	print("parts ", rig.part_names())
	var player: AnimationPlayer = rig._player
	rig.reset_pose()
	var rest_tip: Vector2 = rig.muzzle_position("palm_project")
	var rest_elbow: Vector2 = rig.joint_position("arm_fore")
	print("静止刀尖 画布 (%.1f,%.1f) 指向 %+.1f°" % [
		rest_tip.x + 450.0, rest_tip.y + 360.0,
		rad_to_deg(atan2(rest_tip.y - rest_elbow.y, rest_tip.x - rest_elbow.x))])
	for anim in rig._skill_ids():
		var name := String(anim)
		player.play(name)
		player.advance(0.0)
		var t: float = rig._hit_time(name)
		player.seek(t, true)
		player.advance(0.0)
		var tip: Vector2 = rig.muzzle_position("palm_project")
		var elbow: Vector2 = rig.joint_position("arm_fore")
		var sc: Vector2 = rig._nodes["body"].scale
		var pos: Vector2 = rig._nodes["body"].position
		print("%-14s t=%.3f  刀尖 画布(%4.0f,%4.0f) 指向 %+6.1f°  body pos(%+.0f,%+.0f) scale(%.2f,%.2f)" % [
			name, t, tip.x + 450.0, tip.y + 360.0,
			rad_to_deg(atan2(tip.y - elbow.y, tip.x - elbow.x)),
			pos.x, pos.y, sc.x, sc.y])
	quit()
