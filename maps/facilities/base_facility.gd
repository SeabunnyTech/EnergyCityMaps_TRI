class_name BaseFacility
extends Node3D

## 設施基礎類別
## 提供 boost 升級系統和測試模式支援

# 測試模式：啟用後會自帶光源，並可用按鍵測試 boost 效果
@export var debug_mode: bool = false
@export var debug_camera_position: Vector3 = Vector3(3, 2, 3)
@export var debug_camera_target: Vector3 = Vector3(0, 0.3, 0)

# 升級動畫相關
var _upgrade_tween: Tween = null

# 加速等級，每答對一題增加 1
var boost_level: int = 0:
	set(value):
		var old_value = boost_level
		boost_level = value
		_on_boost_level_changed(old_value, value)
		# 只在升級時（而非重置時）播放動畫
		if value > old_value:
			_play_upgrade_animation()

# 通用升級效果節點（子類別可選擇性使用）
var _burst_particles: GPUParticles3D = null
var _flash_light: OmniLight3D = null

# 測試模式節點
var _debug_light: DirectionalLight3D = null
var _debug_label: Label = null
var _debug_canvas: CanvasLayer = null
var _debug_camera: Camera3D = null


func _ready() -> void:
	# 嘗試獲取升級效果節點
	_burst_particles = get_node_or_null("UpgradeBurst")
	_flash_light = get_node_or_null("FlashLight")

	# 確保升級效果節點初始狀態正確
	if _flash_light:
		_flash_light.light_energy = 0.0

	# 設置測試模式
	if debug_mode:
		_setup_debug_mode()

	# 呼叫子類別的初始化
	_facility_ready()


func _facility_ready() -> void:
	# 子類別覆寫此方法進行初始化
	pass


func _on_boost_level_changed(_old_value: int, _new_value: int) -> void:
	# 子類別覆寫此方法處理 boost 變化
	pass


func _input(event: InputEvent) -> void:
	if not debug_mode:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				# 空白鍵：升級
				boost_level += 1
				print("[DEBUG] %s boost_level: %d" % [name, boost_level])
			KEY_R:
				# R 鍵：重置
				boost_level = 0
				print("[DEBUG] %s reset" % name)


func _setup_debug_mode() -> void:
	# 添加測試用相機（加到根節點避免受設施變換影響）
	_debug_camera = Camera3D.new()
	_debug_camera.name = "DebugCamera"
	_debug_camera.top_level = true  # 不受父節點變換影響
	_debug_camera.global_position = debug_camera_position
	add_child(_debug_camera)
	_debug_camera.look_at(debug_camera_target)

	# 添加測試用方向光
	_debug_light = DirectionalLight3D.new()
	_debug_light.name = "DebugLight"
	_debug_light.top_level = true  # 不受父節點變換影響
	_debug_light.light_energy = 1.0
	_debug_light.rotation_degrees = Vector3(-45, -45, 0)
	add_child(_debug_light)

	# 添加測試用 2D 標籤顯示 boost_level（固定在螢幕底部）
	_debug_canvas = CanvasLayer.new()
	_debug_canvas.name = "DebugCanvas"
	add_child(_debug_canvas)

	_debug_label = Label.new()
	_debug_label.name = "DebugLabel"
	_debug_label.text = "Boost: 0\n[SPACE] +1  [R] Reset"
	_debug_label.add_theme_font_size_override("font_size", 48)
	_debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_debug_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 設置錨點在底部中央，位置在螢幕底部 1/10 高度處
	_debug_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_debug_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_debug_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# 往上偏移螢幕高度的 1/10
	_debug_label.position.y = -get_viewport().get_visible_rect().size.y * 0.1
	_debug_canvas.add_child(_debug_label)

	print("[DEBUG] %s: Debug mode enabled. Press SPACE to boost, R to reset." % name)


func _process(_delta: float) -> void:
	if debug_mode and _debug_label:
		_debug_label.text = "Boost: %d\n[SPACE] +1  [R] Reset" % boost_level


func _play_upgrade_animation() -> void:
	# 取消之前的動畫（如果有）
	if _upgrade_tween and _upgrade_tween.is_valid():
		_upgrade_tween.kill()

	_upgrade_tween = create_tween()
	_upgrade_tween.set_parallel(true)

	# 爆發粒子效果
	if _burst_particles:
		_burst_particles.amount = 40 + boost_level * 20
		_burst_particles.restart()
		_burst_particles.emitting = true

	# 呼叫子類別的額外動畫
	_play_extra_upgrade_animation()


func _play_extra_upgrade_animation() -> void:
	# 子類別覆寫此方法添加額外的升級動畫
	pass
