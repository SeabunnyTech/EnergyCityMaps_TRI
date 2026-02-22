extends BaseFacility

## 小型水力河流發電機
## 繼承 BaseFacility，Water_energy_002 渦輪旋轉 + 升級 VFX

# 渦輪轉速
@export var base_speed: float = 60.0
@export var speed_deviation: float = 5.0

# 升級閃光顏色（水藍色）
@export var upgrade_emission_color: Color = Color(0.3, 0.7, 1.0, 1.0)

# === 閃電粒子設定 ===
@export var bolt_texture_path: String = "res://maps/Texture/bolt.png"
@export var bolt_spawn_radius: float = 0.5
@export var bolt_spawn_min_height: float = 0.0
@export var bolt_spawn_max_height: float = 0.3
@export var bolt_rise_height: float = 0.5
@export var bolt_size: float = 0.12
@export var bolt_lifetime: float = 1.0
@export var bolt_max_count: int = 8
@export var bolt_base_interval: float = 0.5

# 升級地面脈衝設定
@export var ground_pulse_max_radius: float = 0.6
@export var ground_pulse_duration: float = 0.9
@export var ground_pulse_count: int = 3
@export var ground_pulse_stagger: float = 0.12

var _current_speed: float = 0.0
var _target_speed: float = 0.0
var _random_speed_offset: float = 0.0

# 升級用：環繞粒子（繞 Y 軸圓周運動）
var _orbit_particles: GPUParticles3D = null

# 閃電相關
var _bolt_texture: Texture2D = null
var _active_bolts: Array[Sprite3D] = []
var _bolt_spawn_timer: float = 0.0

# 材質相關
var _mesh_instances: Array[MeshInstance3D] = []
var _original_materials: Array[Material] = []
var _glow_materials: Array[StandardMaterial3D] = []
var _white_flash_materials: Array[StandardMaterial3D] = []

# 閃光動畫
var _glow_tween: Tween = null

@onready var _turbine: Node3D = $Water_energy_002


## 取得模型在世界座標的 AABB
func _get_world_aabb() -> AABB:
	if _mesh_instances.size() > 0:
		var mi = _mesh_instances[0]
		var local_aabb = mi.get_aabb()
		var gt = mi.global_transform
		var first = gt * local_aabb.position
		var world_min = first
		var world_max = first
		for i in 8:
			var corner = gt * local_aabb.get_endpoint(i)
			world_min = Vector3(min(world_min.x, corner.x), min(world_min.y, corner.y), min(world_min.z, corner.z))
			world_max = Vector3(max(world_max.x, corner.x), max(world_max.y, corner.y), max(world_max.z, corner.z))
		for j in range(1, _mesh_instances.size()):
			var mj = _mesh_instances[j]
			var la = mj.get_aabb()
			var gtj = mj.global_transform
			for k in 8:
				var corner = gtj * la.get_endpoint(k)
				world_min = Vector3(min(world_min.x, corner.x), min(world_min.y, corner.y), min(world_min.z, corner.z))
				world_max = Vector3(max(world_max.x, corner.x), max(world_max.y, corner.y), max(world_max.z, corner.z))
		return AABB(world_min, world_max - world_min)
	return AABB(global_position - Vector3(0.1, 0.05, 0.1), Vector3(0.2, 0.1, 0.2))


func _get_model_center() -> Vector3:
	return _get_world_aabb().get_center()


func _get_ground_center() -> Vector3:
	var aabb = _get_world_aabb()
	return Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)


func _facility_ready() -> void:
	_random_speed_offset = randf_range(-speed_deviation, speed_deviation)
	_update_target_speed()
	_current_speed = _target_speed

	# 設置升級效果粒子系統
	_setup_orbit_particles()

	# 載入閃電材質
	_bolt_texture = load(bolt_texture_path)

	# 收集 mesh 材質準備發光效果
	_setup_glow_materials()

	# 延遲一幀用模型 AABB 更新粒子範圍
	call_deferred("_update_particle_extents")


# ── 環繞圓形粒子（繞 Y 軸公轉 + 持續上升 + 淡出）──
func _setup_orbit_particles() -> void:
	_orbit_particles = GPUParticles3D.new()
	_orbit_particles.name = "OrbitParticles"
	_orbit_particles.emitting = false
	_orbit_particles.amount = 20
	_orbit_particles.lifetime = 1.6
	_orbit_particles.top_level = true
	_orbit_particles.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))

	var mat_override = StandardMaterial3D.new()
	mat_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_override.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_override.albedo_color = Color(1, 1, 1, 1)
	_orbit_particles.material_override = mat_override

	var proc_mat = ParticleProcessMaterial.new()
	proc_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	proc_mat.emission_ring_radius = 0.15
	proc_mat.emission_ring_inner_radius = 0.10
	proc_mat.emission_ring_height = 0.02
	proc_mat.emission_ring_axis = Vector3(0, 1, 0)
	proc_mat.direction = Vector3(0, 1, 0)
	proc_mat.spread = 15.0
	proc_mat.initial_velocity_min = 0.05
	proc_mat.initial_velocity_max = 0.15
	proc_mat.orbit_velocity_min = 0.6
	proc_mat.orbit_velocity_max = 1.2
	proc_mat.gravity = Vector3(0, 0.02, 0)
	proc_mat.scale_min = 0.5
	proc_mat.scale_max = 1.5
	proc_mat.color = Color(0.5, 0.85, 1.0, 0.8)
	var gradient = Gradient.new()
	gradient.set_color(0, Color(0.6, 0.9, 1.0, 0.0))
	gradient.add_point(0.1, Color(0.6, 0.9, 1.0, 0.9))
	gradient.add_point(0.5, Color(0.4, 0.8, 1.0, 0.7))
	gradient.add_point(0.8, Color(0.3, 0.7, 1.0, 0.3))
	gradient.set_color(1, Color(0.2, 0.6, 0.9, 0.0))
	var ramp = GradientTexture1D.new()
	ramp.gradient = gradient
	proc_mat.color_ramp = ramp
	_orbit_particles.process_material = proc_mat

	var draw_mesh = SphereMesh.new()
	draw_mesh.radius = 0.006
	draw_mesh.height = 0.012
	_orbit_particles.draw_pass_1 = draw_mesh

	add_child(_orbit_particles)


func _update_particle_extents() -> void:
	var aabb = _get_world_aabb()
	var half_size = aabb.size * 0.5
	var model_radius = maxf(half_size.x, half_size.z)

	# 環繞粒子：環形半徑覆蓋模型外圍
	if _orbit_particles:
		var orbit_mat: ParticleProcessMaterial = _orbit_particles.process_material
		orbit_mat.emission_ring_radius = model_radius * 1.3
		orbit_mat.emission_ring_inner_radius = model_radius * 0.9


func _update_target_speed() -> void:
	_target_speed = base_speed * pow(2, boost_level) + boost_level * 60.0 + _random_speed_offset


func _on_boost_level_changed(_old_value: int, _new_value: int) -> void:
	_update_target_speed()

	if _new_value == 0:
		# 關閉持續環繞粒子
		if _orbit_particles:
			_orbit_particles.emitting = false
	else:
		# 開啟持續環繞粒子，數量和速度隨等級增加
		if _orbit_particles:
			_orbit_particles.emitting = true
			_orbit_particles.amount = 12 + _new_value * 6
			_orbit_particles.speed_scale = 0.8 + _new_value * 0.3
			var orbit_mat: ParticleProcessMaterial = _orbit_particles.process_material
			orbit_mat.orbit_velocity_min = 0.5 + _new_value * 0.2
			orbit_mat.orbit_velocity_max = 0.9 + _new_value * 0.3
			orbit_mat.initial_velocity_min = 0.04 + _new_value * 0.03
			orbit_mat.initial_velocity_max = 0.12 + _new_value * 0.05


func _play_upgrade_animation() -> void:
	# 1. 地面圓形脈衝波
	_spawn_ground_pulses()

	# 2. 材質閃爍 + 白色閃光
	_play_extra_upgrade_animation()


func _physics_process(delta: float) -> void:
	# 渦輪旋轉
	if _turbine:
		_current_speed = lerp(_current_speed, _target_speed, delta * 5.0)
		_turbine.rotate_x(deg_to_rad(-_current_speed * delta))

	# 持續環繞粒子跟隨模型中心
	if _orbit_particles and _orbit_particles.emitting:
		_orbit_particles.global_position = _get_model_center()

	# 閃電粒子持續生成（boost_level > 0 時）
	if boost_level > 0 and _bolt_texture != null:
		_bolt_spawn_timer -= delta
		if _bolt_spawn_timer <= 0.0:
			_spawn_bolt()
			_bolt_spawn_timer = bolt_base_interval / (boost_level * 1.1)


# ── 閃電粒子：隨機向上漂浮，漸漸消失 ───

func _spawn_bolt() -> void:
	if _active_bolts.size() >= bolt_max_count:
		return

	var bolt = Sprite3D.new()
	bolt.texture = _bolt_texture
	bolt.pixel_size = bolt_size / 100.0
	bolt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bolt.transparent = true
	bolt.modulate = Color(1, 1, 1, 0)

	# 隨機生成位置
	var angle = randf_range(0, TAU)
	var radius = randf_range(bolt_spawn_radius * 0.2, bolt_spawn_radius)
	var height = randf_range(bolt_spawn_min_height, bolt_spawn_max_height)

	bolt.position = Vector3(
		cos(angle) * radius,
		height,
		sin(angle) * radius
	)

	# 隨機初始旋轉
	bolt.rotation_degrees.z = randf_range(-45, 45)

	add_child(bolt)
	_active_bolts.append(bolt)

	# 目標位置：向上漂浮
	var target_pos = Vector3(
		bolt.position.x + randf_range(-0.1, 0.1),
		height + bolt_rise_height + randf_range(-0.1, 0.1),
		bolt.position.z + randf_range(-0.1, 0.1)
	)

	# 緩慢旋轉
	var spin_tween = create_tween()
	spin_tween.tween_property(
		bolt, "rotation_degrees:z",
		bolt.rotation_degrees.z + randf_range(-60, 60),
		bolt_lifetime
	)

	# 位置：向上漂浮（整個生命週期）
	var move_tween = create_tween()
	move_tween.tween_property(bolt, "position", target_pos, bolt_lifetime).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	move_tween.tween_callback(_remove_bolt.bind(bolt))

	# 透明度：快速淡入 → 緩慢淡出
	var alpha_tween = create_tween()
	alpha_tween.tween_property(bolt, "modulate:a", 0.8, bolt_lifetime * 0.15).set_ease(Tween.EASE_OUT)
	alpha_tween.tween_property(bolt, "modulate:a", 0.0, bolt_lifetime * 0.85).set_ease(Tween.EASE_IN)


func _remove_bolt(bolt: Sprite3D) -> void:
	if bolt in _active_bolts:
		_active_bolts.erase(bolt)
	bolt.queue_free()


# ── 地面圓形脈衝波（升級觸發）───────────────────────────

func _spawn_ground_pulses() -> void:
	var ground = _get_ground_center()
	for i in ground_pulse_count:
		_spawn_single_ground_pulse(ground, i * ground_pulse_stagger)


func _spawn_single_ground_pulse(center: Vector3, delay: float) -> void:
	var ring = MeshInstance3D.new()
	ring.top_level = true

	var torus = TorusMesh.new()
	torus.inner_radius = 0.025
	torus.outer_radius = 0.032
	torus.rings = 48
	torus.ring_segments = 4
	ring.mesh = torus

	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.4, 0.8, 1.0, 0.5)
	ring.material_override = mat

	ring.scale = Vector3(0.03, 0.03, 0.03)
	add_child(ring)
	ring.global_position = center

	var tween = create_tween()
	if delay > 0:
		tween.tween_interval(delay)
	tween.set_parallel(true)
	var target_scale = Vector3(ground_pulse_max_radius, 0.03, ground_pulse_max_radius)
	tween.tween_property(ring, "scale", target_scale, ground_pulse_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(mat, "albedo_color:a", 0.0, ground_pulse_duration).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ring.queue_free)


# ── 材質閃爍 + 白色閃光（升級觸發）──────────────────────

func _play_extra_upgrade_animation() -> void:
	_apply_glow_materials()

	if _glow_tween and _glow_tween.is_valid():
		_glow_tween.kill()

	_glow_tween = create_tween()
	# Phase 1: emission 脈衝上升 0.5 → 2.0
	_glow_tween.tween_method(_set_glow_emission, 0.5, 2.0, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# Phase 2: 到達頂峰時短暫白色閃光
	_glow_tween.tween_callback(_apply_white_flash)
	_glow_tween.tween_interval(0.08)
	_glow_tween.tween_callback(_apply_glow_materials)
	# Phase 3: emission 回落 2.0 → 0.5
	_glow_tween.tween_method(_set_glow_emission, 2.0, 0.5, 0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# Phase 4: 還原原始材質
	_glow_tween.tween_callback(_restore_original_materials)


func _apply_white_flash() -> void:
	var material_index = 0
	for mesh_instance in _mesh_instances:
		var surface_count = mesh_instance.get_surface_override_material_count()
		for i in range(surface_count):
			if material_index < _white_flash_materials.size():
				mesh_instance.set_surface_override_material(i, _white_flash_materials[material_index])
				material_index += 1


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

			# 升級脈衝用材質（水藍色 emission）
			var glow_mat = StandardMaterial3D.new()
			glow_mat.albedo_color = upgrade_emission_color
			glow_mat.emission_enabled = true
			glow_mat.emission = upgrade_emission_color
			glow_mat.emission_energy_multiplier = 0.5
			_glow_materials.append(glow_mat)

			# 白色閃光用材質（頂峰瞬間）
			var white_mat = StandardMaterial3D.new()
			white_mat.albedo_color = Color(1, 1, 1, 1)
			white_mat.emission_enabled = true
			white_mat.emission = Color(1, 1, 1, 1)
			white_mat.emission_energy_multiplier = 3.0
			_white_flash_materials.append(white_mat)


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
