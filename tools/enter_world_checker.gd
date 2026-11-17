extends Node
## 切场景后的检查器：挂在 SceneTree.root 上，不会被 change_scene 释放。

var _frames := 0


func _ready() -> void:
	# ⚠ 面板打开期间树是暂停的（SystemPanel.open 会 pause）。检查器若跟着暂停，
	#   就永远等不到第 5 帧 → 探针挂死、看不出到底是「点击没生效」还是「场景没切」。
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("CHECKER ready")

func _process(_d: float) -> void:
	_frames += 1
	if _frames < 5:
		return
	if _frames == 5:
		var cs := get_tree().current_scene
		print("CHECKER current_scene=", cs.name if cs != null else "<null>")
		if cs != null:
			print("CHECKER pending_left=", SecretWorldDB.pending_spawn_region)
			print("CHECKER player=", cs.get_node_or_null("Player") != null)
			print("CHECKER ground_children=", cs.get_node_or_null("Ground").get_child_count()
				if cs.get_node_or_null("Ground") != null else -1)
			var p := cs.get_node_or_null("Player") as Node2D
			if p != null:
				print("CHECKER player_pos=", p.global_position)
	if _frames == 30:
		get_tree().quit(0)
