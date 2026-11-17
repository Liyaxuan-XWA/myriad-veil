@tool
extends EditorPlugin
## 特效工坊（pixelfx）编辑器插件入口（2026-11-04）。
## 底部面板「特效工坊」：选特效 → 选颜色 → 调大小 → 烘焙 → 挂到场景对象。
## 库本体在项目之外（默认 E:/skill/game/pixelfx），游戏仓库里只留烘焙产物。

const SETTINGS := {
	"pixelfx_studio/library_path": "E:/skill/game/pixelfx",
	"pixelfx_studio/node_path": "node",
	"pixelfx_studio/output_dir": "res://assets/fx/pixelfx",
}

var _panel: Control
var _settings: EditorSettings


func _enter_tree() -> void:
	_settings = get_editor_interface().get_editor_settings()
	for key in SETTINGS.keys():
		if not _settings.has_setting(key):
			_settings.set_setting(key, SETTINGS[key])
		_settings.add_property_info({
			"name": String(key), "type": TYPE_STRING, "hint_string": "",
		})
	if not _settings.settings_changed.is_connected(_on_settings_changed):
		_settings.settings_changed.connect(_on_settings_changed)
	_panel = preload("res://addons/pixelfx_studio/studio_panel.gd").new()
	_panel.name = "PixelFxStudioPanel"
	_panel.plugin = self
	add_control_to_bottom_panel(_panel, "特效工坊")


func _exit_tree() -> void:
	if is_instance_valid(_panel):
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null
	if _settings != null and _settings.settings_changed.is_connected(_on_settings_changed):
		_settings.settings_changed.disconnect(_on_settings_changed)


func _on_settings_changed() -> void:
	if is_instance_valid(_panel) and _panel.has_method("refresh_settings"):
		_panel.refresh_settings()


func _read(key: String, fallback: String) -> String:
	if _settings != null and _settings.has_setting(key):
		return String(_settings.get_setting(key))
	return fallback


func get_library_path() -> String:
	return _read("pixelfx_studio/library_path", SETTINGS["pixelfx_studio/library_path"])


func get_node_path() -> String:
	return _read("pixelfx_studio/node_path", SETTINGS["pixelfx_studio/node_path"])


func get_output_dir() -> String:
	return _read("pixelfx_studio/output_dir", SETTINGS["pixelfx_studio/output_dir"])
