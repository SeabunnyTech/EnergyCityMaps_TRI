extends BaseFacility

## 節電設施（儲能電池）
## 未來科幻風格：擴散粒子 + 護盾球（向內聚攏）+ 收斂閃電爆發

# === 升級閃光 ===
@export var upgrade_emission_color: Color = Color(0.4, 0.8, 1.0, 1.0)

# === 擴散粒子設定 ===
@export var disperse_color: Color = Color(0.5, 0.85, 1.0, 0.7)
@export var disperse_particle_size: float = 0.005
@export var disperse_lifetime: float = 1.5
@export var disperse_base_amount: int = 20
@export var disperse_speed_min: float = 0.2
@export var disperse_speed_max: float = 0.4

# === 收斂閃電設定 ===
@export var bolt_texture_path: String = "res://maps/Texture/bolt.png"
@export var bolt_color: Color = Color(0.7, 0.9, 1.0, 1.0)
@export var bolt_size: float = 0.12
@export var bolt_lifetime_min: float = 0.3
@export var bolt_lifetime_max: float = 0.5
@export var bolt_max_count: int = 10
@export var bolt_burst_base_count: int = 6
@export var bolt_burst_count_per_level: int = 3
@export var bolt_spawn_range_min: float = 0.8
@export var bolt_spawn_range_max: float = 1.5

# === 護盾球設定 ===
@export var shield_color: Color = Color(0.3, 0.7, 1.0, 0.15)
@export var shield_radius: float = 0.3
@export var shield_height: float = 0.6
@export var shield_shrink_duration: float = 0.4
@export var shield_fade_duration: float = 0.3


# --- 粒子 ---
var _disperse_particles: GPUParticles3D = null

# --- 護盾球 ---
var _shield_sphere: MeshInstance3D = null
var _shield_material: StandardMaterial3D = null

# --- 材質 ---
var _mesh_instances: Array[MeshInstance3D] = []
var _original_materials: Array[Material] = []
var _glow_materials: Array[StandardMaterial3D] = []

# --- 閃電 ---
var _bolt_texture: Texture2D = null
var _active_bolts: Array[Sprite3D] = []

# --- 動畫 ---
var _glow_tween: Tween = null


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
	return AABB(global_position - Vector3(0.2, 0.1, 0.2), Vector3(0.4, 0.2, 0.4))


func _get_model_center() -> Vector3:
	return _get_world_aabb().get_center()


func _get_ground_center() -> Vector3:
	var aabb = _get_world_aabb()
	return Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)


func _facility_ready() -> void:
	_setup_disperse_particles()
	_setup_shield_sphere()

	_bolt_texture = load(bolt_texture_path)
	_setup_glow_materials()
	call_deferred("_update_emission_extents")


# ── 擴散粒子（從中心向外擴散）─────────────────────────

func _setup_disperse_particles() -> void:
	_disperse_particles = GPUParticles3D.new()
	_disperse_particles.name = "DisperseParticles"
	_disperse_particles.emitting = false
	_disperse_particles.amount = disperse_base_amount
	_disperse_particles.lifetime = disperse_lifetime
	_disperse_particles.top_level = true
	_disperse_particles.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))

	var mat_override = StandardMaterial3D.new()
	mat_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_override.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_override.albedo_color = Color(1, 1, 1, 1)
	_disperse_particles.material_override = mat_override

	var proc_mat = ParticleProcessMaterial.new()
	proc_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc_mat.emission_sphere_radius = 0.05
	proc_mat.direction = Vector3(0, 0, 0)
	proc_mat.spread = 0.0
	proc_mat.initial_velocity_min = 0.0
	proc_mat.initial_velocity_max = 0.0
	proc_mat.radial_velocity_min = disperse_speed_min
	proc_mat.radial_velocity_max = disperse_speed_max
	proc_mat.gravity = Vector3(0, 0, 0)
	proc_mat.scale_min = 0.2
	proc_mat.scale_max = 0.8
	proc_mat.color = disperse_color
	# 離開中心時漸漸消失
	var gradient = Gradient.new()
	gradient.set_color(0, Color(0.8, 1.0, 1.0, 0.0))
	gradient.add_point(0.1, Color(0.6, 0.9, 1.0, 0.9))
	gradient.add_point(0.5, Color(0.4, 0.7, 1.0, 0.5))
	gradient.set_color(1, Color(0.3, 0.6, 0.9, 0.0))
	var ramp = GradientTexture1D.new()
	ramp.gradient = gradient
	proc_mat.color_ramp = ramp
	_disperse_particles.process_material = proc_mat

	var draw_mesh = SphereMesh.new()
	draw_mesh.radius = disperse_particle_size
	draw_mesh.height = disperse_particle_size * 2.0
	_disperse_particles.draw_pass_1 = draw_mesh

	add_child(_disperse_particles)


# ── 護盾球（升級時從大向內收縮聚攏）─────────────────────

func _setup_shield_sphere() -> void:
	_shield_sphere = MeshInstance3D.new()
	_shield_sphere.name = "ShieldSphere"
	_shield_sphere.top_level = true

	var sphere = SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	sphere.radial_segments = 32
	sphere.rings = 16
	_shield_sphere.mesh = sphere

	_shield_material = StandardMaterial3D.new()
	_shield_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shield_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_shield_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shield_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shield_material.albedo_color = Color(shield_color.r, shield_color.g, shield_color.b, 0.0)
	_shield_material.no_depth_test = true
	_shield_sphere.material_override = _shield_material

	_shield_sphere.visible = false
	add_child(_shield_sphere)


func _update_emission_extents() -> void:
	var aabb = _get_world_aabb()
	var half_size = aabb.size * 0.5
	var max_dim = max(aabb.size.x, max(aabb.size.y, aabb.size.z))

	# 爆發粒子
	if _burst_particles:
		var burst_mat: ParticleProcessMaterial = _burst_particles.process_material
		burst_mat.emission_sphere_radius = max(half_size.x, half_size.z) * 0.3

	# 擴散粒子發射半徑（從中心小範圍開始）
	if _disperse_particles:
		var disp_mat: ParticleProcessMaterial = _disperse_particles.process_material
		disp_mat.emission_sphere_radius = max_dim * 0.15

	# 護盾球大小
	if _shield_sphere:
		var sphere: SphereMesh = _shield_sphere.mesh
		sphere.radius = max_dim * 0.65
		sphere.height = max_dim * 1.3


func _on_boost_level_changed(_old_value: int, _new_value: int) -> void:
	if _new_value == 0:
		if _disperse_particles:
			_disperse_particles.emitting = false
	else:
		# 擴散粒子：數量和擴散速度隨等級增加
		if _disperse_particles:
			_disperse_particles.emitting = true
			_disperse_particles.amount = disperse_base_amount + _new_value * 8
			_disperse_particles.speed_scale = 0.7 + _new_value * 0.3
			var disp_mat: ParticleProcessMaterial = _disperse_particles.process_material
			disp_mat.radial_velocity_min = disperse_speed_min + _new_value * 0.1
			disp_mat.radial_velocity_max = disperse_speed_max + _new_value * 0.08


func _play_upgrade_animation() -> void:
	# 徑向爆發粒子
	if _burst_particles:
		_burst_particles.global_position = _get_model_center()
		_burst_particles.amount = 40
		_burst_particles.restart()
		_burst_particles.emitting = true

	# 護盾球向內聚攏
	_flash_shield()

	# 收斂閃電
	_spawn_radial_burst()

	# 材質閃光
	_play_extra_upgrade_animation()


func _physics_process(_delta: float) -> void:
	var center = _get_model_center()

	# 更新粒子位置
	if _disperse_particles and _disperse_particles.emitting:
		_disperse_particles.global_position = center


# ── 護盾球動畫（從大縮到小，向內聚攏）────────────────────

func _flash_shield() -> void:
	if _shield_sphere == null:
		return

	_shield_sphere.global_position = _get_model_center()
	_shield_sphere.visible = true
	_shield_sphere.scale = Vector3(1.2, 1.2, 1.2)
	_shield_material.albedo_color = Color(shield_color.r, shield_color.g, shield_color.b, shield_color.a)

	var tween = create_tween()
	tween.set_parallel(true)
	# 從大縮到極小
	tween.tween_property(_shield_sphere, "scale", Vector3(0.05, 0.05, 0.05), shield_shrink_duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# 後半段漸漸淡出
	tween.tween_property(_shield_material, "albedo_color:a", 0.0, shield_fade_duration).set_delay(shield_shrink_duration * 0.5).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func(): _shield_sphere.visible = false)


# ── 收斂閃電（升級時從外向內匯聚）────────────────────────

func _spawn_radial_burst() -> void:
	var center = _get_model_center()
	var aabb = _get_world_aabb()
	var max_dim = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
	var burst_count = bolt_burst_base_count + boost_level * bolt_burst_count_per_level

	for i in burst_count:
		if _active_bolts.size() >= bolt_max_count + burst_count:
			break

		var bolt = Sprite3D.new()
		bolt.texture = _bolt_texture
		bolt.pixel_size = bolt_size / 100.0
		bolt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bolt.transparent = true
		bolt.modulate = Color(bolt_color.r, bolt_color.g, bolt_color.b, 0)
		bolt.top_level = true

		add_child(bolt)
		_active_bolts.append(bolt)

		# 從外圍隨機位置出發，向中心收斂
		var dir = Vector3(randf_range(-1, 1), randf_range(-0.3, 1), randf_range(-1, 1)).normalized()
		var start_pos = center + dir * max_dim * randf_range(bolt_spawn_range_min, bolt_spawn_range_max)
		bolt.global_position = start_pos
		var lifetime = randf_range(bolt_lifetime_min, bolt_lifetime_max)

		bolt.rotation_degrees.z = randf_range(-90, 90)

		var spin = create_tween()
		spin.tween_property(bolt, "rotation_degrees:z", bolt.rotation_degrees.z + randf_range(-180, 180), lifetime)

		var tween = create_tween()
		tween.tween_method(
			func(t: float):
				bolt.global_position = start_pos.lerp(center, t)
				if t < 0.1:
					bolt.modulate.a = t / 0.1
				elif t > 0.7:
					bolt.modulate.a = (1.0 - t) / 0.3
				else:
					bolt.modulate.a = 1.0,
			0.0, 1.0, lifetime
		)
		tween.tween_callback(_remove_bolt.bind(bolt))


# ── 材質發光系統 ──────────────────────────────────────────

func _play_extra_upgrade_animation() -> void:
	if _glow_tween and _glow_tween.is_valid():
		_glow_tween.kill()

	_set_glow_emission(0.0)
	_apply_glow_materials()

	_glow_tween = create_tween()
	# 閃光：快速亮起再淡出，恢復原材質
	_glow_tween.tween_method(_set_glow_emission, 0.0, 3.0, 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_glow_tween.tween_method(_set_glow_emission, 3.0, 0.0, 0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
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
			glow_mat.emission_energy_multiplier = 0.0
			_glow_materials.append(glow_mat)


func _collect_mesh_instances(node: Node) -> void:
	if node is MeshInstance3D and node != _shield_sphere:
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
