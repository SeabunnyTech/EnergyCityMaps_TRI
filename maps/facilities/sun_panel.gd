extends BaseFacility

## 太陽能板
## 閃電粒子隨機向上漂浮漸漸消失 + 綠色上升粒子 + 能量脈衝環 + 升級閃光

# 升級閃光顏色（金色）
@export var upgrade_emission_color: Color = Color(1.0, 0.85, 0.2, 1.0)

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

# === 綠色上升粒子設定 ===
@export var green_color: Color = Color(0.3, 1.0, 0.45, 0.7)

# === 能量脈衝設定 ===
@export var pulse_interval: float = 1.8
@export var pulse_color: Color = Color(0.5, 1.0, 0.6, 0.4)

# 節點引用
var _green_particles: GPUParticles3D = null
var _pulse_ring: MeshInstance3D = null
var _pulse_material: StandardMaterial3D = null

# 材質相關
var _mesh_instances: Array[MeshInstance3D] = []
var _original_materials: Array[Material] = []
var _glow_materials: Array[StandardMaterial3D] = []

# 閃電相關
var _bolt_texture: Texture2D = null
var _active_bolts: Array[Sprite3D] = []
var _bolt_spawn_timer: float = 0.0

# 脈衝計時
var _pulse_timer: float = 0.0

# 閃光動畫
var _glow_tween: Tween = null


func _facility_ready() -> void:
	_setup_green_particles()
	_setup_pulse_ring()
	_setup_glow_materials()
	_bolt_texture = load(bolt_texture_path)


# ─── GreenRiseParticles（綠色粒子從面板表面上升）───
func _setup_green_particles() -> void:
	_green_particles = GPUParticles3D.new()
	_green_particles.name = "GreenRiseParticles"
	_green_particles.emitting = false
	_green_particles.amount = 12
	_green_particles.lifetime = 1.4
	_green_particles.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))

	var mat_override = StandardMaterial3D.new()
	mat_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_override.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_override.albedo_color = Color(1, 1, 1, 1)
	_green_particles.material_override = mat_override

	var proc_mat = ParticleProcessMaterial.new()
	proc_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	proc_mat.emission_ring_radius = 0.4
	proc_mat.emission_ring_inner_radius = 0.1
	proc_mat.emission_ring_height = 0.02
	proc_mat.emission_ring_axis = Vector3(0, 1, 0)
	proc_mat.direction = Vector3(0, 1, 0)
	proc_mat.spread = 10.0
	proc_mat.initial_velocity_min = 0.15
	proc_mat.initial_velocity_max = 0.35
	proc_mat.gravity = Vector3(0, 0.05, 0)
	proc_mat.scale_min = 0.3
	proc_mat.scale_max = 0.7
	proc_mat.color = green_color
	# 淡入 → 全亮 → 淡出
	var gradient = Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0))
	gradient.add_point(0.15, Color(1, 1, 1, 1))
	gradient.add_point(0.6, Color(1, 1, 1, 0.8))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var ramp = GradientTexture1D.new()
	ramp.gradient = gradient
	proc_mat.color_ramp = ramp
	# 大小隨生命週期變化
	var scale_tex = CurveTexture.new()
	var curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(0.7, 0.8))
	curve.add_point(Vector2(1.0, 0.0))
	scale_tex.curve = curve
	proc_mat.scale_curve = scale_tex
	_green_particles.process_material = proc_mat

	var draw_mesh = SphereMesh.new()
	draw_mesh.radius = 0.008
	draw_mesh.height = 0.016
	_green_particles.draw_pass_1 = draw_mesh

	add_child(_green_particles)


# ─── EnergyPulseRing（能量脈衝環，週期性向外擴散）───
func _setup_pulse_ring() -> void:
	_pulse_ring = MeshInstance3D.new()
	_pulse_ring.name = "EnergyPulseRing"
	var torus = TorusMesh.new()
	torus.inner_radius = 0.35
	torus.outer_radius = 0.4
	torus.rings = 32
	torus.ring_segments = 16
	_pulse_ring.mesh = torus

	_pulse_material = StandardMaterial3D.new()
	_pulse_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pulse_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_pulse_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pulse_material.albedo_color = Color(pulse_color.r, pulse_color.g, pulse_color.b, 0.0)
	_pulse_material.no_depth_test = true
	_pulse_ring.material_override = _pulse_material

	_pulse_ring.position.y = 0.1
	_pulse_ring.scale = Vector3(0.1, 0.1, 0.1)
	_pulse_ring.visible = false
	add_child(_pulse_ring)


# ═══════════════════════════════════════════
#  升級動畫
# ═══════════════════════════════════════════

func _play_upgrade_animation() -> void:
	_play_extra_upgrade_animation()


func _on_boost_level_changed(_old_value: int, _new_value: int) -> void:
	if _green_particles == null:
		return

	if _new_value == 0:
		_green_particles.emitting = false
	else:
		_green_particles.emitting = true
		_green_particles.amount = 8 + _new_value * 6         # 1→14, 2→20, 3→26
		_green_particles.speed_scale = 0.6 + _new_value * 0.3  # 1→0.9, 2→1.2, 3→1.5
		var proc_mat: ParticleProcessMaterial = _green_particles.process_material
		proc_mat.emission_ring_radius = 0.3 + _new_value * 0.12
		proc_mat.emission_ring_inner_radius = 0.08 + _new_value * 0.04
		proc_mat.initial_velocity_min = 0.12 + _new_value * 0.1
		proc_mat.initial_velocity_max = 0.3 + _new_value * 0.15


func _play_extra_upgrade_animation() -> void:
	# 升級閃光：快速亮起再淡出，恢復原材質
	_set_glow_emission(0.0)
	_apply_glow_materials()

	if _glow_tween and _glow_tween.is_valid():
		_glow_tween.kill()

	_glow_tween = create_tween()
	_glow_tween.tween_method(_set_glow_emission, 0.0, 2.5, 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_glow_tween.tween_method(_set_glow_emission, 2.5, 0.0, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_glow_tween.tween_callback(_restore_original_materials)


# ═══════════════════════════════════════════
#  持續效果（boost_level > 0 時）
# ═══════════════════════════════════════════

func _physics_process(delta: float) -> void:
	if boost_level <= 0:
		return

	# 閃電粒子持續生成
	if _bolt_texture != null:
		_bolt_spawn_timer -= delta
		if _bolt_spawn_timer <= 0.0:
			_spawn_bolt()
			_bolt_spawn_timer = bolt_base_interval / (boost_level * 1.1)

	# 能量脈衝環
	_pulse_timer -= delta
	if _pulse_timer <= 0.0:
		_trigger_pulse()
		_pulse_timer = pulse_interval / (0.7 + boost_level * 0.3)


# ─── 閃電粒子：隨機向上漂浮，漸漸消失 ───
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


# ─── 能量脈衝：環狀向外擴散 ───
func _trigger_pulse() -> void:
	if _pulse_ring == null:
		return

	_pulse_ring.visible = true
	_pulse_ring.scale = Vector3(0.15, 0.15, 0.15)
	_pulse_material.albedo_color.a = pulse_color.a

	var max_s = 0.8 + boost_level * 0.25
	var tween = create_tween().set_parallel(true)
	tween.tween_property(_pulse_ring, "scale", Vector3(max_s, max_s, max_s), 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(_pulse_material, "albedo_color:a", 0.0, 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_callback(func(): _pulse_ring.visible = false)


# ═══════════════════════════════════════════
#  材質工具函式
# ═══════════════════════════════════════════

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
	if node is MeshInstance3D and node != _pulse_ring:
		_mesh_instances.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child)


func _apply_glow_materials() -> void:
	var idx = 0
	for mesh_instance in _mesh_instances:
		var surface_count = mesh_instance.get_surface_override_material_count()
		for i in range(surface_count):
			if idx < _glow_materials.size():
				mesh_instance.set_surface_override_material(i, _glow_materials[idx])
				idx += 1


func _set_glow_emission(energy: float) -> void:
	for glow_mat in _glow_materials:
		glow_mat.emission_energy_multiplier = energy


func _restore_original_materials() -> void:
	var idx = 0
	for mesh_instance in _mesh_instances:
		var surface_count = mesh_instance.get_surface_override_material_count()
		for i in range(surface_count):
			if idx < _original_materials.size():
				mesh_instance.set_surface_override_material(i, _original_materials[idx])
				idx += 1
