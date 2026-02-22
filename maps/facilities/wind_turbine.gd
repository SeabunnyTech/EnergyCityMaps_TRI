extends BaseFacility

## 風力發電機
## 繼承 BaseFacility，添加風扇旋轉和風粒子效果

# 基礎轉速 (度/秒)
@export var base_speed: float = 30.0

# 避免多台風機因為轉速相同變得看起來太整齊
@export var speed_deviation: float = 5.0
@export var random_phase: bool = true

# 升級閃光顏色
@export var upgrade_emission_color: Color = Color(1.0, 0.8, 0.2, 1.0)

# 閃電效果設定（圍繞風機持續噴發）
@export var bolt_texture_path: String = "res://maps/Texture/bolt.png"
@export var bolt_spawn_radius: float = 0.6
@export var bolt_spawn_min_height: float = 0.0
@export var bolt_spawn_max_height: float = 0.7
@export var bolt_rise_height: float = 0.5
@export var bolt_size: float = 0.15
@export var bolt_lifetime: float = 0.7
@export var bolt_max_count: int = 10
@export var bolt_base_interval: float = 0.5        # boost_level 1 時的生成間隔（秒）

var _random_speed_offset: float = 0.0
var _current_speed: float = 0.0
var _target_speed: float = 0.0

# 材質相關
var _mesh_instances: Array[MeshInstance3D] = []
var _original_materials: Array[Material] = []
var _glow_materials: Array[StandardMaterial3D] = []

# 閃電相關
var _bolt_texture: Texture2D = null
var _active_bolts: Array[Sprite3D] = []
var _bolt_spawn_timer: float = 0.0

@onready var _fan: Node3D = $WindNearFan
@onready var _wind_particles: Array[GPUParticles3D] = [
	$WindNearFan/WindParticles1,
	$WindNearFan/WindParticles2,
	$WindNearFan/WindParticles3
]


func _facility_ready() -> void:
	# 隨機化初始角度和速度偏移
	_random_speed_offset = randf_range(-speed_deviation, speed_deviation)
	if random_phase and _fan:
		_fan.rotation_degrees.x = randf_range(0, 360.0)

	# 設定固定的 AABB 避免視錐剔除導致的閃爍
	if _fan is GeometryInstance3D:
		var box_size = Vector3(30, 30, 30)
		_fan.custom_aabb = AABB(-box_size / 2.0, box_size)

	_update_target_speed()
	_current_speed = _target_speed
	_update_wind_particles()

	# 收集所有 MeshInstance3D 並準備發光材質
	_setup_glow_materials()

	# 載入閃電貼圖
	_bolt_texture = load(bolt_texture_path)


func _on_boost_level_changed(_old_value: int, _new_value: int) -> void:
	_update_target_speed()
	_update_wind_particles()


func _update_target_speed() -> void:
	# 每個 boost_level 轉速翻倍
	# 兼顧低速與高速區段的成長差距
	_target_speed = base_speed * pow(2, boost_level) + boost_level * 60.0 + _random_speed_offset


func _update_wind_particles() -> void:
	for p in _wind_particles:
		if p == null:
			continue

		if boost_level == 0:
			p.emitting = false
		else:
			p.emitting = true
			# 風機：粒子快速增多，模擬越來越猛烈的風
			p.amount = 3 + boost_level * 4   # 1→7, 2→11, 3→15
			p.speed_scale = 0.6 + boost_level * 0.7  # 1→1.3, 2→2.0, 3→2.7


func _physics_process(delta: float) -> void:
	if _fan == null:
		return

	# 平滑過渡到目標速度
	_current_speed = lerp(_current_speed, _target_speed, delta * 5.0)

	# 繞 X 軸旋轉
	_fan.rotate_x(deg_to_rad(_current_speed * delta))

	# 持續噴發閃電（噴泉效果）
	if boost_level > 0 and _bolt_texture != null:
		_bolt_spawn_timer -= delta
		if _bolt_spawn_timer <= 0.0:
			_spawn_single_bolt()
			# 風機閃電間隔：較快
			_bolt_spawn_timer = bolt_base_interval / (boost_level * 1.2)


func _setup_glow_materials() -> void:
	# 遞迴收集所有 MeshInstance3D
	_collect_mesh_instances(self)

	# 為每個 mesh 創建發光材質
	for mesh_instance in _mesh_instances:
		var surface_count = mesh_instance.get_surface_override_material_count()
		if surface_count == 0:
			continue

		# 保存原始材質並創建發光版本
		for i in range(surface_count):
			var original_mat = mesh_instance.get_active_material(i)
			_original_materials.append(original_mat)

			# 創建發光材質
			var glow_mat = StandardMaterial3D.new()
			glow_mat.albedo_color = upgrade_emission_color
			glow_mat.emission_enabled = true
			glow_mat.emission = upgrade_emission_color
			glow_mat.emission_energy_multiplier = 2.0
			_glow_materials.append(glow_mat)


func _collect_mesh_instances(node: Node) -> void:
	if node is MeshInstance3D:
		_mesh_instances.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child)


func _play_extra_upgrade_animation() -> void:
	# 瞬間切換到發光材質
	var material_index = 0
	for mesh_instance in _mesh_instances:
		var surface_count = mesh_instance.get_surface_override_material_count()
		for i in range(surface_count):
			if material_index < _glow_materials.size():
				mesh_instance.set_surface_override_material(i, _glow_materials[material_index])
				material_index += 1

	# 延遲後恢復原始材質
	var restore_tween = create_tween()
	restore_tween.tween_callback(_restore_original_materials).set_delay(0.15)



func _spawn_single_bolt() -> void:
	# 超過上限時不再生成
	if _active_bolts.size() >= bolt_max_count:
		return

	var bolt = Sprite3D.new()
	bolt.texture = _bolt_texture
	bolt.pixel_size = bolt_size / 100.0
	bolt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bolt.transparent = true
	bolt.modulate = Color(1, 1, 1, 0)

	# 用極座標在風機周圍圓柱區域內隨機生成
	var angle = randf_range(0, TAU)
	var radius = randf_range(bolt_spawn_radius * 0.3, bolt_spawn_radius)
	var height = randf_range(bolt_spawn_min_height, bolt_spawn_max_height)

	var start_pos = Vector3(
		cos(angle) * radius,
		height,
		sin(angle) * radius
	)
	bolt.position = start_pos

	# 隨機旋轉增加自然感
	bolt.rotation_degrees.z = randf_range(-60, 60)

	add_child(bolt)
	_active_bolts.append(bolt)

	# 飛行中持續旋轉
	var spin_tween = create_tween()
	spin_tween.tween_property(bolt, "rotation_degrees:z", bolt.rotation_degrees.z + randf_range(-120, 120), bolt_lifetime)

	var falls_back = randf() < 0.35
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(bolt, "modulate:a", 1.0, bolt_lifetime * 0.15).set_ease(Tween.EASE_OUT)

	if falls_back:
		# 上升後回落
		var peak_pos = Vector3(
			start_pos.x + cos(angle) * 0.05,
			height + bolt_rise_height * randf_range(0.5, 1.0),
			start_pos.z + sin(angle) * 0.05
		)
		var fall_pos = Vector3(
			peak_pos.x + randf_range(-0.08, 0.08),
			height + randf_range(-0.05, 0.05),
			peak_pos.z + randf_range(-0.08, 0.08)
		)
		tween.tween_property(bolt, "position", peak_pos, bolt_lifetime * 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.chain().tween_property(bolt, "position", fall_pos, bolt_lifetime * 0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.chain().tween_property(bolt, "modulate:a", 0.0, bolt_lifetime * 0.15).set_ease(Tween.EASE_IN)
	else:
		# 正常上升
		var target_pos = Vector3(
			start_pos.x + cos(angle) * 0.05,
			height + bolt_rise_height + randf_range(-0.05, 0.05),
			start_pos.z + sin(angle) * 0.05
		)
		tween.tween_property(bolt, "position", target_pos, bolt_lifetime * 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.chain().tween_property(bolt, "modulate:a", 0.0, bolt_lifetime * 0.3).set_ease(Tween.EASE_IN)

	tween.chain().tween_callback(_remove_bolt.bind(bolt))


func _restore_original_materials() -> void:
	var material_index = 0
	for mesh_instance in _mesh_instances:
		var surface_count = mesh_instance.get_surface_override_material_count()
		for i in range(surface_count):
			if material_index < _original_materials.size():
				mesh_instance.set_surface_override_material(i, _original_materials[material_index])
				material_index += 1


func _remove_bolt(bolt: Sprite3D) -> void:
	if bolt in _active_bolts:
		_active_bolts.erase(bolt)
	bolt.queue_free()
