extends BaseFacility

## 太陽能板
## 繼承 BaseFacility，添加粒子和閃電效果

# 升級閃光顏色（金色）
@export var upgrade_emission_color: Color = Color(1.0, 0.85, 0.2, 1.0)

# 閃電效果設定
@export var bolt_texture_path: String = "res://maps/Texture/bolt.png"
@export var bolt_spawn_radius: float = 0.5
@export var bolt_spawn_min_height: float = 0.0
@export var bolt_spawn_max_height: float = 0.5
@export var bolt_rise_height: float = 0.4
@export var bolt_size: float = 0.12
@export var bolt_lifetime: float = 0.7
@export var bolt_max_count: int = 8
@export var bolt_base_interval: float = 0.5

# 持續光粒子
var _light_particles: GPUParticles3D = null

# 材質相關
var _mesh_instances: Array[MeshInstance3D] = []
var _original_materials: Array[Material] = []
var _glow_materials: Array[StandardMaterial3D] = []

# 閃電相關
var _bolt_texture: Texture2D = null
var _active_bolts: Array[Sprite3D] = []
var _bolt_spawn_timer: float = 0.0

# 閃光動畫
var _glow_tween: Tween = null


func _facility_ready() -> void:
	# --- UpgradeBurst（按 SPACE 時，火花向外彈射）---
	var burst = GPUParticles3D.new()
	burst.name = "UpgradeBurst"
	burst.emitting = false
	burst.one_shot = true
	burst.amount = 20
	burst.lifetime = 0.8
	burst.explosiveness = 1.0
	burst.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))

	var burst_override = StandardMaterial3D.new()
	burst_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	burst_override.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	burst_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	burst_override.albedo_color = Color(1, 0.9, 0.5, 1)
	burst.material_override = burst_override

	var burst_mat = ParticleProcessMaterial.new()
	burst_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	burst_mat.emission_sphere_radius = 0.05
	burst_mat.direction = Vector3(0, 1, 0)
	burst_mat.spread = 70.0
	burst_mat.initial_velocity_min = 0.8
	burst_mat.initial_velocity_max = 1.5
	burst_mat.gravity = Vector3(0, -2.0, 0)
	burst_mat.scale_min = 0.5
	burst_mat.scale_max = 1.0
	burst_mat.color = Color(1, 0.9, 0.5, 1)
	# 火花沿飛行方向對齊
	burst_mat.particle_flag_align_y = true
	# 漸淡消失
	var burst_gradient = Gradient.new()
	burst_gradient.set_color(0, Color(1, 1, 1, 1))
	burst_gradient.add_point(0.4, Color(1, 1, 1, 1))
	burst_gradient.set_color(1, Color(1, 1, 1, 0))
	var burst_ramp = GradientTexture1D.new()
	burst_ramp.gradient = burst_gradient
	burst_mat.color_ramp = burst_ramp
	burst.process_material = burst_mat

	# 細長條作為火花拖尾
	var burst_draw = BoxMesh.new()
	burst_draw.size = Vector3(0.002, 0.06, 0.002)
	burst.draw_pass_1 = burst_draw

	add_child(burst)
	_burst_particles = burst  # BaseFacility 會自動觸發

	# --- LightParticles（持續半透明小圓點沿圓柱面向上跑動）---
	_light_particles = GPUParticles3D.new()
	_light_particles.name = "LightParticles"
	_light_particles.emitting = false
	_light_particles.amount = 8
	_light_particles.lifetime = 1.0
	_light_particles.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))

	var light_override = StandardMaterial3D.new()
	light_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	light_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	light_override.albedo_color = Color(1.0, 1.0, 1.0, 0.4)
	_light_particles.material_override = light_override

	var light_mat = ParticleProcessMaterial.new()
	light_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	light_mat.emission_ring_radius = 0.4
	light_mat.emission_ring_inner_radius = 0.38
	light_mat.emission_ring_height = 0.0
	light_mat.emission_ring_axis = Vector3(0, 1, 0)
	light_mat.direction = Vector3(0, 1, 0)
	light_mat.spread = 0.0
	light_mat.initial_velocity_min = 0.3
	light_mat.initial_velocity_max = 0.5
	light_mat.gravity = Vector3(0, 0, 0)
	light_mat.scale_min = 0.3
	light_mat.scale_max = 0.8
	light_mat.color = Color(1.0, 1.0, 1.0, 0.4)
	_light_particles.process_material = light_mat

	var light_draw = SphereMesh.new()
	light_draw.radius = 0.006
	light_draw.height = 0.012
	_light_particles.draw_pass_1 = light_draw

	add_child(_light_particles)

	# 載入閃電貼圖
	_bolt_texture = load(bolt_texture_path)

	# 收集 mesh 材質準備發光效果
	_setup_glow_materials()


func _play_upgrade_animation() -> void:
	# 覆寫 BaseFacility，控制 burst 數量（不用預設的 40 + boost_level * 20）
	if _burst_particles:
		_burst_particles.amount = 20
		_burst_particles.restart()
		_burst_particles.emitting = true
	_play_extra_upgrade_animation()


func _on_boost_level_changed(_old_value: int, _new_value: int) -> void:
	if _light_particles == null:
		return

	if _new_value == 0:
		_light_particles.emitting = false
	else:
		_light_particles.emitting = true
		_light_particles.amount = 5 * _new_value
		_light_particles.speed_scale = 0.5 + _new_value * 0.5


func _physics_process(delta: float) -> void:
	# 持續噴發閃電
	if boost_level > 0 and _bolt_texture != null:
		_bolt_spawn_timer -= delta
		if _bolt_spawn_timer <= 0.0:
			_spawn_single_bolt()
			_bolt_spawn_timer = bolt_base_interval / boost_level


func _spawn_single_bolt() -> void:
	if _active_bolts.size() >= bolt_max_count:
		return

	var bolt = Sprite3D.new()
	bolt.texture = _bolt_texture
	bolt.pixel_size = bolt_size / 100.0
	bolt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bolt.transparent = true
	bolt.modulate = Color(1, 1, 1, 0)

	var angle = randf_range(0, TAU)
	var radius = randf_range(bolt_spawn_radius * 0.3, bolt_spawn_radius)
	var height = randf_range(bolt_spawn_min_height, bolt_spawn_max_height)

	var start_pos = Vector3(
		cos(angle) * radius,
		height,
		sin(angle) * radius
	)
	bolt.position = start_pos

	var target_pos = Vector3(
		start_pos.x + cos(angle) * 0.05,
		height + bolt_rise_height + randf_range(-0.05, 0.05),
		start_pos.z + sin(angle) * 0.05
	)

	bolt.rotation_degrees.z = randf_range(-25, 25)

	add_child(bolt)
	_active_bolts.append(bolt)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(bolt, "modulate:a", 1.0, bolt_lifetime * 0.15).set_ease(Tween.EASE_OUT)
	tween.tween_property(bolt, "position", target_pos, bolt_lifetime * 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_property(bolt, "modulate:a", 0.0, bolt_lifetime * 0.3).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(_remove_bolt.bind(bolt))


func _play_extra_upgrade_animation() -> void:
	# 切換到發光材質（初始能量為 0）
	_set_glow_emission(0.0)
	_apply_glow_materials()

	if _glow_tween and _glow_tween.is_valid():
		_glow_tween.kill()

	_glow_tween = create_tween()
	# Ease out: 發光漸強
	_glow_tween.tween_method(_set_glow_emission, 0.0, 2.5, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# Ease in: 發光漸弱
	_glow_tween.tween_method(_set_glow_emission, 2.5, 0.0, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# 恢復原始材質
	_glow_tween.tween_callback(_restore_original_materials)


func _apply_glow_materials() -> void:
	var material_index = 0
	for mesh_instance in _mesh_instances:
		var surface_count = mesh_instance.get_surface_override_material_count()
		for i in range(surface_count):
			if material_index < _glow_materials.size():
				mesh_instance.set_surface_override_material(i, _glow_materials[material_index])
				material_index += 1


func _set_glow_emission(energy: float) -> void:
	for glow_mat in _glow_materials:
		glow_mat.emission_energy_multiplier = energy


func _setup_glow_materials() -> void:
	_collect_mesh_instances(self)

	for mesh_instance in _mesh_instances:
		var surface_count = mesh_instance.get_surface_override_material_count()
		if surface_count == 0:
			continue

		for i in range(surface_count):
			var original_mat = mesh_instance.get_active_material(i)
			_original_materials.append(original_mat)

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
