extends Camera3D
class_name CameraController

var camera_positions = {}
var current_tween: Tween
var is_animating = false

@export var default_duration: float = 1.5
@export var ease_type: Tween.EaseType = Tween.EASE_IN_OUT
@export var trans_type: Tween.TransitionType = Tween.TRANS_CUBIC

func _ready():
	_build_camera_positions_dict()
	
	# 自動移動到 overview（如果存在）
	if camera_positions.has("overview"):
		global_transform = camera_positions["overview"].global_transform

func _build_camera_positions_dict():
	camera_positions.clear()
	
	# 尋找同層級或父節點下的 CameraPositions
	var positions_node = _find_camera_positions_node()
	
	if not positions_node:
		push_warning("找不到 CameraPositions 節點")
		return
	
	for child in positions_node.get_children():
		if child is Marker3D or child is Node3D:
			if child.has_meta("position_id"):
				var pos_id = child.get_meta("position_id")
				camera_positions[pos_id] = child
				print("註冊相機位置: ", pos_id)
			else:
				push_warning("節點 '%s' 沒有設定 position_id metadata" % child.name)

func _find_camera_positions_node() -> Node:
	# 先檢查父節點的子節點中是否有 CameraPositions
	var parent = get_parent()
	if parent:
		for child in parent.get_children():
			if child.name == "CameraPositions":
				return child
	
	# 如果沒找到，嘗試在父節點中找
	if parent and parent.has_node("CameraPositions"):
		return parent.get_node("CameraPositions")
	
	return null


func zoom_to(position_id: String, duration: float = -1, on_complete: Callable = Callable()) -> bool:
	if is_animating:
		push_warning("相機正在移動中，忽略請求")
		return false
	if not camera_positions.has(position_id):
		push_error("找不到相機位置: " + position_id)
		return false
	
	var tween_duration = duration if duration >= 0 else default_duration
	is_animating = true
	var target_marker = camera_positions[position_id]
	
	if current_tween:
		current_tween.kill()
	
	current_tween = create_tween()
	#current_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	current_tween.set_parallel(true)
	current_tween.set_ease(ease_type)
	current_tween.set_trans(trans_type)
	
	var target_transform = target_marker.global_transform
	
	# === 平移 === (註解掉這段來停用)
	current_tween.tween_property(
		self,
		"global_position",
		target_transform.origin,
		tween_duration
	)
	
	# === 旋轉 === (註解掉這段來停用)
	current_tween.tween_property(
		self,
		"global_basis",
		target_transform.basis,
		tween_duration
	)
	
	current_tween.finished.connect(func(): 
		is_animating = false
		if on_complete.is_valid():
			on_complete.call()
	)
	
	return true

## 便捷方法
func zoom_to_overview(duration: float = -1):
	zoom_to("overview", duration)

func is_camera_animating() -> bool:
	return is_animating

func get_available_positions() -> Array:
	return camera_positions.keys()

func has_position(position_id: String) -> bool:
	return camera_positions.has(position_id)
