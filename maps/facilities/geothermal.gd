extends BaseFacility

## 地熱發電
## 地面裂紋橘紅熱能發光 + 蒸氣上升 + 熱能轉換為綠色電能 + 閃電效果

# 升級閃光顏色（橘紅色，地熱感）
@export var upgrade_emission_color: Color = Color(1.0, 0.4, 0.1, 1.0)

# 閃電效果設定（黃色閃電，噴泉式從模型中心噴發）
@export var bolt_texture_path: String = "res://maps/Texture/bolt.png"
@export var bolt_rise_height: float = 0.4
@export var bolt_size: float = 0.15
@export var bolt_lifetime: float = 0.7
@export var bolt_max_count: int = 8
@export var bolt_base_interval: float = 0.5

# 持續環狀波設定（橘紅色熱能脈衝）
@export var continuous_ripple_max_radius: float = 0.8
@export var continuous_ripple_duration: float = 1.2
@export var continuous_ripple_base_interval: float = 1.0
@export var continuous_ripple_color: Color = Color(1.0, 0.35, 0.05, 0.35)

# 地面熱能發光粒子
var _heat_glow_particles: GPUParticles3D = null
# 蒸氣上升粒子
var _steam_particles: GPUParticles3D = null
# 能量轉換粒子（橘紅→綠色螺旋上升）
var _energy_transform_particles: GPUParticles3D = null

# 材質相關
var _mesh_instances: Array[MeshInstance3D] = []
var _original_materials: Array[Material] = []
var _glow_materials: Array[StandardMaterial3D] = []

# 閃電相關
var _bolt_texture: Texture2D = null
var _active_bolts: Array[Sprite3D] = []
var _bolt_spawn_timer: float = 0.0
var _ripple_timer: float = 0.0

# 閃光動畫
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
	return AABB(global_position - Vector3(0.5, 0.2, 0.5), Vector3(1.0, 0.4, 1.0))


func _get_model_center() -> Vector3:
	return _get_world_aabb().get_center()


func _get_model_top() -> Vector3:
	var aabb = _get_world_aabb()
	return Vector3(aabb.get_center().x, aabb.position.y + aabb.size.y, aabb.get_center().z)


func _get_ground_center() -> Vector3:
	var aabb = _get_world_aabb()
	return Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)


func _facility_ready() -> void:
	# --- UpgradeBurst（升級時橘紅色爆發粒子）---
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
	burst_mat.color = Color(1.0, 0.5, 0.15, 0.8)
	var burst_gradient = Gradient.new()
	burst_gradient.set_color(0, Color(1.0, 0.4, 0.1, 0.9))
	burst_gradient.add_point(0.3, Color(1.0, 0.6, 0.2, 0.6))
	burst_gradient.set_color(1, Color(0.5, 0.15, 0.0, 0))
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

	_setup_heat_glow_particles()
	_setup_steam_particles()
	_setup_energy_transform_particles()

	# 載入閃電貼圖
	_bolt_texture = load(bolt_texture_path)

	# 收集 mesh 材質準備發光效果
	_setup_glow_materials()

	# 延遲一幀更新粒子發射範圍
	call_deferred("_update_emission_extents")


# ── 地面熱能裂紋發光粒子 ─────────────────────────────
func _setup_heat_glow_particles() -> void:
	_heat_glow_particles = GPUParticles3D.new()
	_heat_glow_particles.name = "HeatGlowParticles"
	_heat_glow_particles.emitting = false
	_heat_glow_particles.amount = 20
	_heat_glow_particles.lifetime = 1.5
	_heat_glow_particles.top_level = true
	_heat_glow_particles.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))

	var mat_override = StandardMaterial3D.new()
	mat_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_override.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_override.albedo_color = Color(1, 1, 1, 1)
	_heat_glow_particles.material_override = mat_override

	var proc_mat = ParticleProcessMaterial.new()
	proc_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	proc_mat.emission_ring_radius = 0.2
	proc_mat.emission_ring_inner_radius = 0.03
	proc_mat.emission_ring_height = 0.01
	proc_mat.emission_ring_axis = Vector3(0, 1, 0)
	proc_mat.direction = Vector3(0, 0.3, 0)
	proc_mat.spread = 85.0
	proc_mat.initial_velocity_min = 0.01
	proc_mat.initial_velocity_max = 0.06
	proc_mat.gravity = Vector3(0, -0.03, 0)
	proc_mat.scale_min = 0.6
	proc_mat.scale_max = 2.0
	proc_mat.color = Color(1.0, 0.35, 0.05, 0.8)
	# 脈動：淡入 → 發光 → 淡出
	var gradient = Gradient.new()
	gradient.set_color(0, Color(1.0, 0.3, 0.0, 0.0))
	gradient.add_point(0.15, Color(1.0, 0.45, 0.1, 0.9))
	gradient.add_point(0.5, Color(1.0, 0.35, 0.05, 0.7))
	gradient.add_point(0.8, Color(0.8, 0.2, 0.0, 0.4))
	gradient.set_color(1, Color(0.5, 0.1, 0.0, 0.0))
	var ramp = GradientTexture1D.new()
	ramp.gradient = gradient
	proc_mat.color_ramp = ramp
	_heat_glow_particles.process_material = proc_mat

	# 扁平球體模擬地面裂紋發光
	var draw_mesh = SphereMesh.new()
	draw_mesh.radius = 0.012
	draw_mesh.height = 0.005
	_heat_glow_particles.draw_pass_1 = draw_mesh

	add_child(_heat_glow_particles)


# ── 蒸氣上升粒子 ─────────────────────────────────────
func _setup_steam_particles() -> void:
	_steam_particles = GPUParticles3D.new()
	_steam_particles.name = "SteamParticles"
	_steam_particles.emitting = false
	_steam_particles.amount = 15
	_steam_particles.lifetime = 2.0
	_steam_particles.top_level = true
	_steam_particles.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))

	var mat_override = StandardMaterial3D.new()
	mat_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_override.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_override.albedo_color = Color(1, 1, 1, 0.4)
	_steam_particles.material_override = mat_override

	var proc_mat = ParticleProcessMaterial.new()
	# BOX 發射覆蓋整個模型範圍（延遲一幀由 _update_emission_extents 更新）
	proc_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc_mat.emission_box_extents = Vector3(0.2, 0.05, 0.2)
	proc_mat.direction = Vector3(0, 1, 0)
	proc_mat.spread = 15.0
	proc_mat.initial_velocity_min = 0.08
	proc_mat.initial_velocity_max = 0.2
	proc_mat.gravity = Vector3(0, 0.02, 0)
	proc_mat.scale_min = 0.5
	proc_mat.scale_max = 1.8
	proc_mat.color = Color(0.9, 0.9, 0.95, 0.35)
	# 蒸氣淡入後緩慢消散
	var gradient = Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.0))
	gradient.add_point(0.12, Color(1, 1, 1, 0.45))
	gradient.add_point(0.45, Color(0.95, 0.95, 1.0, 0.3))
	gradient.set_color(1, Color(0.9, 0.9, 0.95, 0.0))
	var ramp = GradientTexture1D.new()
	ramp.gradient = gradient
	proc_mat.color_ramp = ramp
	# 蒸氣上升時逐漸變大
	var scale_tex = CurveTexture.new()
	var curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(0.3, 0.7))
	curve.add_point(Vector2(0.7, 1.0))
	curve.add_point(Vector2(1.0, 1.3))
	scale_tex.curve = curve
	proc_mat.scale_curve = scale_tex
	_steam_particles.process_material = proc_mat

	var draw_mesh = SphereMesh.new()
	draw_mesh.radius = 0.01
	draw_mesh.height = 0.02
	_steam_particles.draw_pass_1 = draw_mesh

	add_child(_steam_particles)


# ── 能量轉換粒子（橘紅→綠色螺旋上升）─────────────────
func _setup_energy_transform_particles() -> void:
	_energy_transform_particles = GPUParticles3D.new()
	_energy_transform_particles.name = "EnergyTransformParticles"
	_energy_transform_particles.emitting = false
	_energy_transform_particles.amount = 12
	_energy_transform_particles.lifetime = 2.5
	_energy_transform_particles.top_level = true
	_energy_transform_particles.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))

	var mat_override = StandardMaterial3D.new()
	mat_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_override.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_override.albedo_color = Color(1, 1, 1, 1)
	_energy_transform_particles.material_override = mat_override

	var proc_mat = ParticleProcessMaterial.new()
	# BOX 發射覆蓋整個模型，搭配 orbit_velocity 螺旋上升
	proc_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc_mat.emission_box_extents = Vector3(0.2, 0.05, 0.2)
	proc_mat.direction = Vector3(0, 1, 0)
	proc_mat.spread = 10.0
	proc_mat.initial_velocity_min = 0.12
	proc_mat.initial_velocity_max = 0.28
	proc_mat.orbit_velocity_min = 0.3
	proc_mat.orbit_velocity_max = 0.7
	proc_mat.gravity = Vector3(0, 0, 0)
	proc_mat.scale_min = 0.3
	proc_mat.scale_max = 1.0
	proc_mat.color = Color(1, 1, 1, 0.8)
	# 核心效果：橘紅（熱能）→ 黃色（轉換中）→ 綠色（電能）
	var gradient = Gradient.new()
	gradient.set_color(0, Color(1.0, 0.3, 0.0, 0.0))
	gradient.add_point(0.1, Color(1.0, 0.4, 0.05, 0.8))
	gradient.add_point(0.35, Color(1.0, 0.7, 0.1, 0.9))
	gradient.add_point(0.6, Color(0.5, 0.9, 0.2, 0.85))
	gradient.add_point(0.8, Color(0.2, 1.0, 0.4, 0.6))
	gradient.set_color(1, Color(0.1, 0.8, 0.3, 0.0))
	var ramp = GradientTexture1D.new()
	ramp.gradient = gradient
	proc_mat.color_ramp = ramp
	_energy_transform_particles.process_material = proc_mat

	var draw_mesh = SphereMesh.new()
	draw_mesh.radius = 0.007
	draw_mesh.height = 0.014
	_energy_transform_particles.draw_pass_1 = draw_mesh

	add_child(_energy_transform_particles)


func _update_emission_extents() -> void:
	var aabb = _get_world_aabb()
	var half_size = aabb.size * 0.5
	if _burst_particles:
		var burst_mat: ParticleProcessMaterial = _burst_particles.process_material
		burst_mat.emission_box_extents = half_size
	if _steam_particles:
		var steam_mat: ParticleProcessMaterial = _steam_particles.process_material
		steam_mat.emission_box_extents = half_size
	if _energy_transform_particles:
		var energy_mat: ParticleProcessMaterial = _energy_transform_particles.process_material
		energy_mat.emission_box_extents = half_size


func _on_boost_level_changed(_old_value: int, _new_value: int) -> void:
	if _new_value == 0:
		if _heat_glow_particles:
			_heat_glow_particles.emitting = false
		if _steam_particles:
			_steam_particles.emitting = false
		if _energy_transform_particles:
			_energy_transform_particles.emitting = false
	else:
		# 地面熱能裂紋：數量和範圍隨等級增加
		if _heat_glow_particles:
			_heat_glow_particles.emitting = true
			_heat_glow_particles.amount = 12 + _new_value * 8       # 1->20, 2->28, 3->36
			_heat_glow_particles.speed_scale = 0.8 + _new_value * 0.2
			var heat_mat: ParticleProcessMaterial = _heat_glow_particles.process_material
			heat_mat.emission_ring_radius = 0.15 + _new_value * 0.06
			heat_mat.emission_ring_inner_radius = 0.02 + _new_value * 0.02

		# 蒸氣：數量和速度隨等級增加
		if _steam_particles:
			_steam_particles.emitting = true
			_steam_particles.amount = 8 + _new_value * 6            # 1->14, 2->20, 3->26
			_steam_particles.speed_scale = 0.6 + _new_value * 0.3
			var steam_mat: ParticleProcessMaterial = _steam_particles.process_material
			steam_mat.initial_velocity_min = 0.06 + _new_value * 0.05
			steam_mat.initial_velocity_max = 0.15 + _new_value * 0.08

		# 能量轉換螺旋：數量和旋轉速度隨等級增加
		if _energy_transform_particles:
			_energy_transform_particles.emitting = true
			_energy_transform_particles.amount = 6 + _new_value * 6  # 1->12, 2->18, 3->24
			_energy_transform_particles.speed_scale = 0.6 + _new_value * 0.4
			var energy_mat: ParticleProcessMaterial = _energy_transform_particles.process_material
			energy_mat.orbit_velocity_min = 0.2 + _new_value * 0.2
			energy_mat.orbit_velocity_max = 0.5 + _new_value * 0.3
			energy_mat.initial_velocity_min = 0.1 + _new_value * 0.08
			energy_mat.initial_velocity_max = 0.25 + _new_value * 0.1


func _play_upgrade_animation() -> void:
	if _burst_particles:
		_burst_particles.global_position = _get_model_center()
		_burst_particles.amount = 30
		_burst_particles.restart()
		_burst_particles.emitting = true
	_play_extra_upgrade_animation()


func _physics_process(delta: float) -> void:
	# 更新 top_level 粒子位置
	var ground = _get_ground_center()
	var center = _get_model_center()

	if _heat_glow_particles and _heat_glow_particles.emitting:
		_heat_glow_particles.global_position = ground
	if _steam_particles and _steam_particles.emitting:
		_steam_particles.global_position = center
	if _energy_transform_particles and _energy_transform_particles.emitting:
		_energy_transform_particles.global_position = center

	if boost_level > 0:
		# 持續噴發黃色閃電（噴泉式從模型中心噴出）
		if _bolt_texture != null:
			_bolt_spawn_timer -= delta
			if _bolt_spawn_timer <= 0.0:
				_spawn_single_bolt()
				_bolt_spawn_timer = bolt_base_interval / (boost_level * 1.5)

		# 持續擴散橘紅色環狀波（地面熱能脈衝，等級越高越快）
		_ripple_timer -= delta
		if _ripple_timer <= 0.0:
			_spawn_continuous_ripple()
			_ripple_timer = continuous_ripple_base_interval / (boost_level * 1.5)


# ── 持續環狀波（橘紅色熱能脈衝）─────────────────────────

func _spawn_continuous_ripple() -> void:
	var ring = MeshInstance3D.new()
	ring.top_level = true

	var torus = TorusMesh.new()
	torus.inner_radius = 0.025
	torus.outer_radius = 0.03
	torus.rings = 48
	torus.ring_segments = 4
	ring.mesh = torus

	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = continuous_ripple_color
	ring.material_override = mat

	ring.scale = Vector3(0.05, 0.05, 0.05)
	add_child(ring)
	ring.global_position = _get_ground_center()

	var target_radius = continuous_ripple_max_radius + boost_level * 0.15
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(target_radius, 0.05, target_radius), continuous_ripple_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(mat, "albedo_color:a", 0.0, continuous_ripple_duration).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ring.queue_free)


# ── 閃電（黃色，從模型中心噴泉式噴發）────────────────────

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

	# 從模型中心噴發
	var center = _get_model_center()
	bolt.rotation_degrees.z = randf_range(-60, 60)

	add_child(bolt)
	bolt.global_position = center
	_active_bolts.append(bolt)

	# 飛行中持續旋轉
	var spin_tween = create_tween()
	spin_tween.tween_property(bolt, "rotation_degrees:z", bolt.rotation_degrees.z + randf_range(-120, 120), bolt_lifetime)

	# 噴泉效果：用拋物線公式產生滑順弧形彈跳
	var aabb = _get_world_aabb()
	var half_w = aabb.size.x * 0.5
	var half_d = aabb.size.z * 0.5
	var model_h = aabb.size.y

	var angle = randf_range(0, TAU)
	var spread = randf_range(0.6, 1.2)
	var arc_height = model_h * randf_range(0.6, 1.2)

	# 落點：模型邊緣附近
	var land_pos = Vector3(
		center.x + cos(angle) * half_w * spread,
		aabb.position.y + randf_range(0, model_h * 0.15),
		center.z + sin(angle) * half_d * spread
	)

	# 用 tween_method 驅動連續拋物線軌跡 (t: 0→1)
	# y = lerp(start, end, t) + arc_height * 4t(1-t)
	var fly_time = bolt_lifetime * 0.85
	var tween = create_tween()
	tween.tween_method(
		func(t: float):
			bolt.global_position = Vector3(
				lerp(center.x, land_pos.x, t),
				lerp(center.y, land_pos.y, t) + arc_height * 4.0 * t * (1.0 - t),
				lerp(center.z, land_pos.z, t)
			)
			# 前 10% 淡入，後 15% 淡出
			if t < 0.1:
				bolt.modulate.a = t / 0.1
			elif t > 0.85:
				bolt.modulate.a = (1.0 - t) / 0.15
			else:
				bolt.modulate.a = 1.0,
		0.0, 1.0, fly_time
	)
	tween.tween_callback(_remove_bolt.bind(bolt))


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
