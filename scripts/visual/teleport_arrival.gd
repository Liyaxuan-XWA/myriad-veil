class_name TeleportArrival
extends RefCounted
## 角色传送登场演出（2026-10-24）
##
## 进入副本 / 返回原初位面时复用：外扩光环 + 向心光点 + 角色由小放大、由透明淡入。
## 表现全部走 ArtDB 的 teleport_arrival / teleport_gather，未接贴图时用程序化回退，
## 后续换正式传送特效只改 ArtDB，不改玩家脚本。
##
## 调用方负责把 is_teleporting 锁在 true，并在 on_done 回调里解除。

## 在 _ready 里先隐藏角色：避免「首帧露出正常角色 → 下一帧才开始传送」的闪跳
static func prepare(visual: Node2D) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	var sx := -1.0 if visual.scale.x < 0.0 else 1.0
	visual.scale = Vector2(0.55 * sx, 0.55)
	visual.modulate = Color(0.58, 0.86, 1.0, 0.0)


static func play(host: Node2D, visual: Node2D, body_center: Vector2,
		duration: float = 0.75, on_done: Callable = Callable()) -> void:
	if host == null or not is_instance_valid(host):
		if on_done.is_valid():
			on_done.call()
		return

	var sx := 1.0
	if visual != null:
		sx = -1.0 if visual.scale.x < 0.0 else 1.0
		visual.scale = Vector2(0.55 * sx, 0.55)
		visual.modulate = Color(0.58, 0.86, 1.0, 0.0)

	FxPlayer.spawn(host, "teleport_arrival", {"position": body_center})
	FxPlayer.spawn(host, "teleport_gather", {"position": body_center})
	# 光柱以脚底为原点向上画；body_center 的 y 是身体中心，x 仍取角色中线
	FxPlayer.spawn(host, "teleport_beam", {"position": Vector2(body_center.x, 0.0)})

	var tw := host.create_tween()
	if visual != null:
		tw.tween_property(visual, "scale", Vector2(sx, 1.0), duration * 0.7) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(visual, "modulate", Color.WHITE, duration * 0.55)
	tw.tween_interval(duration * 0.25)
	tw.tween_callback(func() -> void:
		if visual != null and is_instance_valid(visual):
			visual.scale = Vector2(sx, 1.0)
			visual.modulate = Color.WHITE
		if on_done.is_valid():
			on_done.call()
	)
