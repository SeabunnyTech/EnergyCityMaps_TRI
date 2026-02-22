extends BaseFacility

## 水壩發電設施
## 升級時模型閃黃光 + 白色水粒子上升 + 閃電粒子上升 + 瀑布水流加速

# 升級閃光顏色（金黃色，電力感）
@export var upgrade_emission_color: Color = Color(1.0, 0.85, 0.1, 1.0)

# 閃電效果設定
@export var bolt_texture_path: String = "res://maps/Texture/bolt.png"
@export var bolt_spawn_radius: float = 0.5
@export var bolt_spawn_min_height: float = 0.0
@export var bolt_spawn_max_height: float = 0.6
@export var bolt_rise_height: float = 0.5
@export var bolt_size: float = 0.225
@export var bolt_lifetime: float = 0.7
@export var bolt_max_count: int = 10
@export var bolt_base_interval: float = 0.5        # boost_level 1 時的生成間隔（秒）
@export var bolt_speed_factor: float = 1.2         # 每級加速倍率：interval = base / (level * factor)

# 白色粒子變速（boost level 1, 2, 3 對應的 speed_scale）
@export var rise_speed_scales: Array[float] = [0.9, 1.2, 1.5]

# 瀑布 Wave_Speed（boost level 1, 2, 3 對應值）
@export var wave_speeds: Array[float] = [0.1, 0.3, 0.5]
@export var wave_speed_default: float = 0.1

# 材質相關
var _mesh_instances: Array[MeshInstance3D] = []
var _original_materials: Array[Material] = []
var _glow_materials: Array[StandardMaterial3D] = []

# 白色上升粒子
var _rise_particles: GPUParticles3D = null

# 閃電相關
var _bolt_texture: Texture2D = null
var _active_bolts: Array[Sprite3D] = []
var _bolt_spawn_timer: float = 0.0

# 瀑布節點（從 map_west.tscn 中搜尋）
var _waterfall_node: MeshInstance3D = null
var _waterfall_material: ShaderMaterial = null

# 閃光動畫
var _glow_tween: Tween = null

# 模型範圍（延遲計算後更新）
var _model_half_extents: Vector3 = Vector3(0.5, 0.3, 0.8)  # fallback 預設值
var _model_center_local: Vector3 = Vector3.ZERO


func _facility_ready() -> void:
	_setup_rise_particles()
	_bolt_texture = load(bolt_texture_path)
	_setup_glow_materials()
	# 延遲一幀：等場景完全載入後搜尋 Waterfall 並計算模型範圍
	call_deferred("_find_waterfall_node")
	call_deferred("_compute_model_extents")


# ── 白色水粒子 ────────────────────────────────────────────

func _setup_rise_particles() -> void:
	_rise_particles = GPUParticles3D.new()
	_rise_particles.name = "RiseParticles"
	_rise_particles.emitting = false
	_rise_particles.amount = 20
	_rise_particles.lifetime = 2.0
	_rise_particles.top_level = true
	_rise_particles.visibility_aabb = AABB(Vector3(-5, -1, -5), Vector3(10, 8, 10))

	var mat_override = StandardMaterial3D.new()
	mat_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_override.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_override.albedo_color = Color(1, 1, 1, 0.6)
	_rise_particles.material_override = mat_override

	var proc_mat = ParticleProcessMaterial.new()
	proc_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# 初始值為 fallback，_compute_model_extents() 執行後會更新為實際模型範圍
	proc_mat.emission_box_extents = Vector3(_model_half_extents.x, 0.05, _model_half_extents.z)
	proc_mat.direction = Vector3(0, 1, 0)
	proc_mat.spread = 20.0
	proc_mat.initial_velocity_min = 0.1
	proc_mat.initial_velocity_max = 0.3
	proc_mat.gravity = Vector3(0, 0.02, 0)
	proc_mat.scale_min = 0.6
	proc_mat.scale_max = 1.8

	var gradient = Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.0))
	gradient.add_point(0.1, Color(1, 1, 1, 0.7))
	gradient.add_point(0.5, Color(0.9, 0.95, 1.0, 0.5))
	gradient.set_color(1, Color(1, 1, 1, 0.0))
	var ramp = GradientTexture1D.new()
	ramp.gradient = gradient
	proc_mat.color_ramp = ramp

	# 上升時逐漸變大
	var scale_tex = CurveTexture.new()
	var curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(0.4, 1.2))
	curve.add_point(Vector2(1.0, 1.8))
	scale_tex.curve = curve
	proc_mat.scale_curve = scale_tex

	_rise_particles.process_material = proc_mat

	var draw_mesh = SphereMesh.new()
	draw_mesh.radius = 0.015
	draw_mesh.height = 0.03
	_rise_particles.draw_pass_1 = draw_mesh

	add_child(_rise_particles)


# ── 模型範圍計算 ──────────────────────────────────────────

func _compute_model_extents() -> void:
	if _mesh_instances.is_empty():
		return

	var self_inv = global_transform.affine_inverse()
	var first := true
	var local_min := Vector3.ZERO
	var local_max := Vector3.ZERO

	for mi in _mesh_instances:
		if mi.mesh == null:
			continue
		var local_aabb = mi.get_aabb()
		var mi_to_local = self_inv * mi.global_transform
		for i in 8:
			var corner: Vector3 = mi_to_local * local_aabb.get_endpoint(i)
			if first:
				local_min = corner
				local_max = corner
				first = false
			else:
				local_min = local_min.min(corner)
				local_max = local_max.max(corner)

	if not first:
		_model_half_extents = (local_max - local_min) * 0.5
		_model_center_local = (local_min + local_max) * 0.5
		print("[Dam] Model extents: half=", _model_half_extents, " center=", _model_center_local)

		# 更新白色粒子發射範圍至完整模型足跡
		if _rise_particles:
			var proc_mat: ParticleProcessMaterial = _rise_particles.process_material
			proc_mat.emission_box_extents = Vector3(_model_half_extents.x, 0.05, _model_half_extents.z)

		# debug 模式下根據模型實際範圍自動定位相機
		_reposition_debug_camera()


# ── Debug 相機自動定位（45° 俯瞰）────────────────────────

func _reposition_debug_camera() -> void:
	if not debug_mode or _debug_camera == null:
		return

	# 以 XZ 最大半徑決定觀看距離，保留 3 倍餘裕讓 VFX 完整入鏡
	var max_xz = max(_model_half_extents.x, _model_half_extents.z)
	var h: float = max_xz * 3.0          # 相機距模型中心的垂直高度
	var d: float = h / sqrt(2.0)          # 水平偏移（使俯仰角恰好 45°）

	var center_world: Vector3 = to_global(_model_center_local)
	_debug_camera.global_position = center_world + Vector3(d, h, d)
	_debug_camera.look_at(center_world)
	print("[Dam] Debug camera: pos=", _debug_camera.global_position,
			"  target=", center_world,
			"  pitch≈45°")


# ── 瀑布節點搜尋 ──────────────────────────────────────────

func _find_waterfall_node() -> void:
	# 只在自己的子樹搜尋，避免找到 map_west 地形中同名的 Waterfall 節點
	var found = get_node_or_null("Waterfall")
	if found is MeshInstance3D:
		_waterfall_node = found
		_waterfall_material = _waterfall_node.material_override as ShaderMaterial
		print("[Dam] Found Waterfall: ", _waterfall_node.get_path())
	else:
		print("[Dam] Waterfall node not found (normal in debug scene)")


# ── Boost 變化 ────────────────────────────────────────────

func _on_boost_level_changed(_old_value: int, _new_value: int) -> void:
	_update_rise_particles(_new_value)
	_update_waterfall_speed(_new_value)


func _update_rise_particles(level: int) -> void:
	if _rise_particles == null:
		return
	if level == 0:
		_rise_particles.emitting = false
	else:
		_rise_particles.emitting = true
		_rise_particles.amount = 10 + level * 10
		if level - 1 < rise_speed_scales.size():
			_rise_particles.speed_scale = rise_speed_scales[level - 1]


func _update_waterfall_speed(level: int) -> void:
	if _waterfall_material == null:
		return
	var speed: float = wave_speed_default
	if level > 0 and level - 1 < wave_speeds.size():
		speed = wave_speeds[level - 1]
	_waterfall_material.set_shader_parameter("Wave_Speed", speed)


# ── 每幀更新 ──────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	# top_level 粒子需手動跟隨模型中心
	if _rise_particles and _rise_particles.emitting:
		_rise_particles.global_position = to_global(_model_center_local)

	# 持續噴發閃電
	if boost_level > 0 and _bolt_texture != null:
		_bolt_spawn_timer -= delta
		if _bolt_spawn_timer <= 0.0:
			_spawn_single_bolt()
			_bolt_spawn_timer = bolt_base_interval / (boost_level * bolt_speed_factor)


# ── 閃電（從壩體周圍上升）────────────────────────────────

func _spawn_single_bolt() -> void:
	if _active_bolts.size() >= bolt_max_count:
		return

	var bolt = Sprite3D.new()
	bolt.texture = _bolt_texture
	bolt.pixel_size = bolt_size / 100.0
	bolt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bolt.transparent = true
	bolt.modulate = Color(1, 1, 1, 0)

	# 以矩形分布覆蓋整個壩體 XZ 範圍
	var height = randf_range(bolt_spawn_min_height, bolt_spawn_max_height)
	var start_pos = Vector3(
		_model_center_local.x + randf_range(-_model_half_extents.x, _model_half_extents.x),
		height,
		_model_center_local.z + randf_range(-_model_half_extents.z, _model_half_extents.z)
	)
	bolt.position = start_pos
	bolt.rotation_degrees.z = randf_range(-60, 60)

	add_child(bolt)
	_active_bolts.append(bolt)

	# 飛行中持續旋轉
	var spin_tween = create_tween()
	spin_tween.tween_property(bolt, "rotation_degrees:z", bolt.rotation_degrees.z + randf_range(-120, 120), bolt_lifetime)

	var target_pos = Vector3(
		start_pos.x + randf_range(-0.05, 0.05),
		height + bolt_rise_height + randf_range(-0.05, 0.05),
		start_pos.z + randf_range(-0.05, 0.05)
	)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(bolt, "modulate:a", 1.0, bolt_lifetime * 0.15).set_ease(Tween.EASE_OUT)
	tween.tween_property(bolt, "position", target_pos, bolt_lifetime * 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_property(bolt, "modulate:a", 0.0, bolt_lifetime * 0.3).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(_remove_bolt.bind(bolt))


# ── 材質黃色閃爍（升級動畫）──────────────────────────────

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
