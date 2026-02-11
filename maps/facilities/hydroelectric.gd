extends BaseFacility

## 水力發電
## 繼承 BaseFacility，Water_energy_002 渦輪旋轉 + 粒子 + 閃電效果

# 渦輪轉速
@export var base_speed: float = 60.0
@export var speed_deviation: float = 5.0

# 升級閃光顏色（水藍色）
@export var upgrade_emission_color: Color = Color(0.3, 0.7, 1.0, 1.0)

# 閃電效果設定
@export var bolt_texture_path: String = "res://maps/Texture/bolt.png"
@export var bolt_rise_height: float = 0.4
@export var bolt_size: float = 0.15
@export var bolt_lifetime: float = 0.7
@export var bolt_max_count: int = 8
@export var bolt_base_interval: float = 0.5

# 漣漪設定
@export var ripple_max_radius: float = 0.5
@export var ripple_duration: float = 0.8
@export var ripple_stagger: float = 0.15

var _current_speed: float = 0.0
var _target_speed: float = 0.0
var _random_speed_offset: float = 0.0

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
		# 合併所有 mesh 的範圍
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

	# --- UpgradeBurst（按 SPACE 時，白色半透明圓點向上擴散）---
	var burst = GPUParticles3D.new()
	burst.name = "UpgradeBurst"
	burst.emitting = false
	burst.one_shot = true
	burst.amount = 30
	burst.lifetime = 1.0
	burst.explosiveness = 0.9
	burst.top_level = true
	burst.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))

	var burst_override = StandardMaterial3D.new()
	burst_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	burst_override.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	burst_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	burst_override.albedo_color = Color(1, 1, 1, 0.7)
	burst.material_override = burst_override

	var burst_mat = ParticleProcessMaterial.new()
	burst_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	burst_mat.emission_box_extents = Vector3(0.05, 0.02, 0.05)
	burst_mat.direction = Vector3(0, 1, 0)
	burst_mat.spread = 40.0
	burst_mat.initial_velocity_min = 0.3
	burst_mat.initial_velocity_max = 0.8
	burst_mat.gravity = Vector3(0, -0.3, 0)
	burst_mat.scale_min = 0.5
	burst_mat.scale_max = 1.5
	burst_mat.color = Color(1, 1, 1, 0.7)
	var burst_gradient = Gradient.new()
	burst_gradient.set_color(0, Color(1, 1, 1, 0.8))
	burst_gradient.add_point(0.3, Color(1, 1, 1, 0.6))
	burst_gradient.set_color(1, Color(1, 1, 1, 0))
	var burst_ramp = GradientTexture1D.new()
	burst_ramp.gradient = burst_gradient
	burst_mat.color_ramp = burst_ramp
	burst.process_material = burst_mat

	var burst_draw = SphereMesh.new()
	burst_draw.radius = 0.008
	burst_draw.height = 0.016
	burst.draw_pass_1 = burst_draw

	add_child(burst)
	_burst_particles = burst

	# --- LightParticles（持續白色半透明小圓點向上飄散）---
	_light_particles = GPUParticles3D.new()
	_light_particles.name = "LightParticles"
	_light_particles.emitting = false
	_light_particles.amount = 8
	_light_particles.lifetime = 1.2
	_light_particles.top_level = true
	_light_particles.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))

	var light_override = StandardMaterial3D.new()
	light_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	light_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	light_override.albedo_color = Color(1.0, 1.0, 1.0, 0.4)
	_light_particles.material_override = light_override

	var light_mat = ParticleProcessMaterial.new()
	light_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	light_mat.emission_box_extents = Vector3(0.05, 0.02, 0.05)
	light_mat.direction = Vector3(0, 1, 0)
	light_mat.spread = 20.0
	light_mat.initial_velocity_min = 0.2
	light_mat.initial_velocity_max = 0.5
	light_mat.gravity = Vector3(0, 0, 0)
	light_mat.scale_min = 0.3
	light_mat.scale_max = 1.0
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

	# 延遲一幀更新粒子發射範圍
	call_deferred("_update_emission_extents")


func _update_emission_extents() -> void:
	var aabb = _get_world_aabb()
	var half_size = aabb.size * 0.5
	if _burst_particles:
		var burst_mat: ParticleProcessMaterial = _burst_particles.process_material
		burst_mat.emission_box_extents = half_size
	if _light_particles:
		var light_mat: ParticleProcessMaterial = _light_particles.process_material
		light_mat.emission_box_extents = half_size


func _update_target_speed() -> void:
	_target_speed = base_speed * pow(2, boost_level) + boost_level * 60.0 + _random_speed_offset


func _on_boost_level_changed(_old_value: int, _new_value: int) -> void:
	_update_target_speed()

	if _light_particles == null:
		return

	if _new_value == 0:
		_light_particles.emitting = false
	else:
		_light_particles.emitting = true
		_light_particles.amount = 5 * _new_value
		_light_particles.speed_scale = 0.5 + _new_value * 0.5


func _play_upgrade_animation() -> void:
	if _burst_particles:
		_burst_particles.global_position = _get_model_center()
		_burst_particles.amount = 30
		_burst_particles.restart()
		_burst_particles.emitting = true
	_spawn_ripples()
	_play_extra_upgrade_animation()


func _physics_process(delta: float) -> void:
	# 渦輪旋轉
	if _turbine:
		_current_speed = lerp(_current_speed, _target_speed, delta * 5.0)
		_turbine.rotate_x(deg_to_rad(-_current_speed * delta))

	# 更新 top_level 光粒子位置
	if _light_particles and _light_particles.emitting:
		_light_particles.global_position = _get_model_center()

	# 持續噴發閃電
	if boost_level > 0 and _bolt_texture != null:
		_bolt_spawn_timer -= delta
		if _bolt_spawn_timer <= 0.0:
			_spawn_single_bolt()
			_bolt_spawn_timer = bolt_base_interval / boost_level


# ── 漣漪 ──────────────────────────────────────────────

func _spawn_ripples() -> void:
	var ground = _get_ground_center()
	for i in 5:
		_spawn_single_ripple(ground, i * ripple_stagger)


func _spawn_single_ripple(center: Vector3, delay: float) -> void:
	var ring = MeshInstance3D.new()
	ring.top_level = true

	var torus = TorusMesh.new()
	torus.inner_radius = 0.035
	torus.outer_radius = 0.04
	torus.rings = 48
	torus.ring_segments = 4
	ring.mesh = torus

	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 1, 0.5)
	ring.material_override = mat

	ring.scale = Vector3(0.1, 0.1, 0.1)
	add_child(ring)
	ring.global_position = center

	var tween = create_tween()
	if delay > 0:
		tween.tween_interval(delay)
	tween.set_parallel(true)
	var target_scale = Vector3(ripple_max_radius, 0.1, ripple_max_radius)
	tween.tween_property(ring, "scale", target_scale, ripple_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(mat, "albedo_color:a", 0.0, ripple_duration).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ring.queue_free)


# ── 閃電 ──────────────────────────────────────────────

func _spawn_single_bolt() -> void:
	if _active_bolts.size() >= bolt_max_count:
		return

	var bolt = Sprite3D.new()
	bolt.texture = _bolt_texture
	bolt.pixel_size = bolt_size / 100.0
	bolt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bolt.transparent = true
	bolt.modulate = Color(1, 1, 1, 0)
	bolt.top_level = true

	var aabb = _get_world_aabb()
	var start_pos = Vector3(
		randf_range(aabb.position.x, aabb.position.x + aabb.size.x),
		randf_range(aabb.position.y, aabb.position.y + aabb.size.y),
		randf_range(aabb.position.z, aabb.position.z + aabb.size.z)
	)
	var target_pos = Vector3(
		start_pos.x + randf_range(-0.05, 0.05),
		start_pos.y + bolt_rise_height + randf_range(-0.05, 0.05),
		start_pos.z + randf_range(-0.05, 0.05)
	)

	bolt.rotation_degrees.z = randf_range(-25, 25)

	add_child(bolt)
	bolt.global_position = start_pos
	_active_bolts.append(bolt)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(bolt, "modulate:a", 1.0, bolt_lifetime * 0.15).set_ease(Tween.EASE_OUT)
	tween.tween_property(bolt, "global_position", target_pos, bolt_lifetime * 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_property(bolt, "modulate:a", 0.0, bolt_lifetime * 0.3).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(_remove_bolt.bind(bolt))


# ── 材質閃爍 ──────────────────────────────────────────

func _play_extra_upgrade_animation() -> void:
	_set_glow_emission(0.0)
	_apply_glow_materials()

	if _glow_tween and _glow_tween.is_valid():
		_glow_tween.kill()

	_glow_tween = create_tween()
	_glow_tween.tween_method(_set_glow_emission, 0.0, 2.5, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_glow_tween.tween_method(_set_glow_emission, 2.5, 0.0, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
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
