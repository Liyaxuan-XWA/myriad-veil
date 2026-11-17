extends Node
## 仓库存量 / 指引书 smoke：确认符箓移出仓库、新文案不影响面板构建。

func _ready() -> void:
	print("\n########## 仓库 / 指引书 smoke ##########")
	var wh := WarehousePanel.new()
	add_child(wh)
	await get_tree().process_frame
	await get_tree().process_frame
	var has_talisman := false
	for n in wh.find_children("*", "Label", true, false):
		# RuleNote 是底部规则说明，里面出现「符箓」是有意解释去向，不算被列成库存项
		if (n as Node).name == "RuleNote":
			continue
		if String((n as Label).text).contains("符箓"):
			has_talisman = true
			break
	print("PASS  仓库面板已构建" if wh.is_inside_tree() else "FAIL 仓库面板未构建")
	print("PASS  仓库不再显示符箓" if not has_talisman else "FAIL 仓库仍显示符箓")
	wh.queue_free()
	var gp := GuidePanel.new()
	add_child(gp)
	await get_tree().process_frame
	await get_tree().process_frame
	print("PASS  指引书面板已构建" if gp.is_inside_tree() else "FAIL 指引书面板未构建")
	gp.queue_free()
	get_tree().quit(0)
