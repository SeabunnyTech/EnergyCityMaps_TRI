extends Node3D

@onready var camera = $MainCamera
@onready var positions = $CameraPositions

# Debug 模式：當場景直接用 F6 執行時啟用
var _debug_mode: bool = false


func _ready():
	_adjust_environment_for_renderer()
	_check_debug_mode()


func _check_debug_mode():
	# 如果這個場景是根節點，表示是用 F6 直接執行
	if get_tree().current_scene == self:
		_debug_mode = true
		_setup_debug_mode()


func _setup_debug_mode():
	print("=== 地圖 Debug 模式 ===")
	print("場景: ", scene_file_path)
	print("")
	_print_debug_help()
	print("")
	print("按鈕位置:")
	var btn_positions = get_button_positions()
	for btn_name in btn_positions:
		print("  %s: %s" % [btn_name, btn_positions[btn_name]])
	print("========================")


func _print_debug_help():
	print("快捷鍵:")
	print("  [0] 回到 overview")
	print("  [1-9] 切換相機位置:")
	var key_index = 1
	for child in positions.get_children():
		if child.name.to_lower() == "overview":
			continue
		if key_index > 9:
			break
		print("    [%s] %s" % [key_index, child.name])
		key_index += 1
	print("  [B] Boost 風機")
	print("  [R] 重設設施")
	print("  [H] 顯示此說明")


# 取得非 overview 的相機位置列表
func _get_topic_positions() -> Array:
	var result = []
	for child in positions.get_children():
		if child.name.to_lower() != "overview":
			result.append(child)
	return result


func _adjust_environment_for_renderer():
	var world_env = get_node_or_null("WorldEnvironment")
	if not world_env:
		return

	var is_compatibility = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	var suffix = "_compatibility" if is_compatibility else "_forward"
	var scene_path = scene_file_path.to_lower()
	var env_path: String

	if "coast" in scene_path or "map01" in scene_path:
		env_path = "res://maps/Scene/environments/env_coast%s.tres" % suffix
	elif "west" in scene_path or "map02" in scene_path:
		env_path = "res://maps/Scene/environments/env_west%s.tres" % suffix
	elif "east" in scene_path or "map03" in scene_path:
		env_path = "res://maps/Scene/environments/env_east%s.tres" % suffix
	else:
		return

	world_env.environment = load(env_path)


func _input(event):
	# 只在 debug 模式下處理輸入
	if not _debug_mode:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		# 按 0 回到 overview
		if event.keycode == KEY_0:
			zoom_to_topic("overview")
			print("運鏡到: overview")

		# 按 1-9 對應非 overview 的相機位置
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var index = event.keycode - KEY_1
			var topic_positions = _get_topic_positions()
			if index < topic_positions.size():
				var target = topic_positions[index]
				var pos_id = target.name.to_lower()
				zoom_to_topic(pos_id)
				print("運鏡到: ", pos_id)

		# B 鍵：測試 boost_facility (wind)
		if event.keycode == KEY_B:
			boost_facility("wind")
			print("Boost wind facility")

		# R 鍵：重設設施
		if event.keycode == KEY_R:
			reset()
			print("Reset facilities")

		# H 鍵：顯示說明
		if event.keycode == KEY_H:
			_print_debug_help()


func boost_facility(topic: String):
	if topic == 'wind' and has_node("Model/WindTurbines"):
		for turbine in $Model/WindTurbines.get_children():
			turbine.boost_level += 1
	elif topic == 'solar_ground' and has_node("Model/GroundSolarPanels"):
		for panel in $Model/GroundSolarPanels.get_children():
			if panel.has_method("boost"):
				panel.boost()
	elif topic == 'solar_roof' and has_node("Model/RoofSolarPanels"):
		for panel in $Model/RoofSolarPanels.get_children():
			if panel.has_method("boost"):
				panel.boost()
	elif topic == 'energy_storage' and has_node("Model/EnergyStorage"):
		for storage in $Model/EnergyStorage.get_children():
			if storage.has_method("boost"):
				storage.boost()


func reset():
	if has_node("Model/WindTurbines"):
		for turbine in $Model/WindTurbines.get_children():
			turbine.boost_level = 0

func zoom_to_topic(topic: String, duration: float=1.5):
	camera.zoom_to(topic, duration)


# 回傳按鈕位置字典 { 按鈕名稱: Vector3 }
# 從 ButtonPositions 節點下的 Marker3D 子節點讀取
func get_button_positions() -> Dictionary:
	var result = {}
	var button_positions_node = get_node_or_null("ButtonPositions")

	if button_positions_node:
		for child in button_positions_node.get_children():
			if child is Marker3D or child is Node3D:
				result[child.name] = child.global_position

	return result
