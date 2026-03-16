extends Node3D
class_name BeamVisualController

@export var core_path: NodePath = ^"Core"
@export var glow_path: NodePath = ^"Glow"
@export var beam_pivot_path: NodePath = ^"BeamPivot"
@export var beam_particles_path: NodePath = ^"BeamPivot/BeamParticles"
@export var impact_root_path: NodePath = ^"Impact"
@export var impact_flare_path: NodePath = ^"Impact/ImpactFlare"
@export var impact_particles_path: NodePath = ^"Impact/ImpactParticles"

@export_category("Beam Shape")
@export var acquire_core_width: float = 0.055
@export var locked_core_width: float = 0.11
@export var acquire_glow_width: float = 0.15
@export var locked_glow_width: float = 0.30
@export var max_ramp_width_bonus: float = 0.05

@export_category("Beam Color")
@export var core_color: Color = Color(0.82, 0.96, 1.0, 1.0)
@export var glow_color: Color = Color(0.22, 0.78, 1.0, 1.0)
@export var impact_color: Color = Color(0.92, 0.98, 1.0, 1.0)

@export_category("Beam Intensity")
@export var acquire_emission_energy: float = 1.2
@export var locked_emission_energy: float = 4.5
@export var ramp_emission_bonus: float = 1.5

var _turret: PlayerTurret = null
var _runtime: BeamWeaponRuntime = null
var _target_ref: WeakRef = weakref(null)

var _core: MeshInstance3D = null
var _glow: MeshInstance3D = null
var _beam_pivot: Node3D = null
var _beam_particles: GPUParticles3D = null
var _impact_root: Node3D = null
var _impact_flare: MeshInstance3D = null
var _impact_particles: GPUParticles3D = null

var _core_mesh: ImmediateMesh = null
var _glow_mesh: ImmediateMesh = null
var _core_material: StandardMaterial3D = null
var _glow_material: StandardMaterial3D = null
var _impact_material: StandardMaterial3D = null
var _beam_particles_process: ParticleProcessMaterial = null
var _impact_particles_process: ParticleProcessMaterial = null

func _ready() -> void:
	_capture_scene_nodes()
	_prepare_beam_meshes()
	_prepare_materials()
	_prepare_particles()
	_set_effect_active(false)
	if _turret != null:
		_bind_runtime()
	set_physics_process(true)

func _exit_tree() -> void:
	_disconnect_runtime()

func bind_turret(value: PlayerTurret) -> void:
	if _turret == value:
		return
	_disconnect_runtime()
	_turret = value
	if is_inside_tree():
		_bind_runtime()

func _physics_process(_delta: float) -> void:
	if _turret == null:
		_set_effect_active(false)
		_clear_beam_meshes()
		return

	var current_runtime: BeamWeaponRuntime = _turret.get_runtime() as BeamWeaponRuntime
	if current_runtime != _runtime:
		_bind_runtime()

	var target: Node3D = _get_active_target()
	if _runtime == null or target == null or not is_instance_valid(target):
		_set_effect_active(false)
		_clear_beam_meshes()
		return
	if not target.visible:
		_set_effect_active(false)
		_clear_beam_meshes()
		return

	var lock_state: int = _runtime.get_lock_state()
	if lock_state == BeamWeaponRuntime.LockState.IDLE:
		_set_effect_active(false)
		_clear_beam_meshes()
		return

	var start: Vector3 = _turret.get_shot_origin()
	var end: Vector3 = target.global_position
	var beam_vector: Vector3 = end - start
	var beam_length_sq: float = beam_vector.length_squared()
	if beam_length_sq <= 0.0001:
		_set_effect_active(false)
		_clear_beam_meshes()
		return

	var beam_length: float = sqrt(beam_length_sq)
	var beam_dir: Vector3 = beam_vector / beam_length
	var lock_progress: float = clamp(_runtime.get_lock_progress(), 0.0, 1.0)
	var ramp_ratio: float = clamp(_runtime.get_ramp_ratio(), 0.0, 1.0)
	var width_bonus: float = max_ramp_width_bonus * ramp_ratio
	var core_width: float = lerp(acquire_core_width, locked_core_width, lock_progress) + width_bonus
	var glow_width: float = lerp(acquire_glow_width, locked_glow_width, lock_progress) + width_bonus * 1.8
	var emission_energy: float = lerp(acquire_emission_energy, locked_emission_energy, lock_progress) + ramp_emission_bonus * ramp_ratio

	_set_effect_active(true)
	_update_beam_materials(lock_progress, ramp_ratio, emission_energy)
	_update_beam_mesh(_core_mesh, start, end, core_width)
	_update_beam_mesh(_glow_mesh, start, end, glow_width)
	_update_particles(start, end, beam_dir, beam_length, lock_progress, ramp_ratio)

func _capture_scene_nodes() -> void:
	_core = get_node_or_null(core_path) as MeshInstance3D
	_glow = get_node_or_null(glow_path) as MeshInstance3D
	_beam_pivot = get_node_or_null(beam_pivot_path) as Node3D
	_beam_particles = get_node_or_null(beam_particles_path) as GPUParticles3D
	_impact_root = get_node_or_null(impact_root_path) as Node3D
	_impact_flare = get_node_or_null(impact_flare_path) as MeshInstance3D
	_impact_particles = get_node_or_null(impact_particles_path) as GPUParticles3D

func _prepare_beam_meshes() -> void:
	_core_mesh = ImmediateMesh.new()
	_glow_mesh = ImmediateMesh.new()
	if _core != null:
		_core.mesh = _core_mesh
		_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_core.extra_cull_margin = 2000.0
	if _glow != null:
		_glow.mesh = _glow_mesh
		_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_glow.extra_cull_margin = 2000.0

func _prepare_materials() -> void:
	_core_material = _resolve_standard_material(_core)
	_glow_material = _resolve_standard_material(_glow)
	_impact_material = _resolve_standard_material(_impact_flare)

func _prepare_particles() -> void:
	if _beam_particles != null:
		var beam_material: Material = _beam_particles.process_material
		if beam_material != null:
			_beam_particles_process = beam_material.duplicate(true) as ParticleProcessMaterial
			_beam_particles.process_material = _beam_particles_process
		_beam_particles.emitting = false
	if _impact_particles != null:
		var impact_material: Material = _impact_particles.process_material
		if impact_material != null:
			_impact_particles_process = impact_material.duplicate(true) as ParticleProcessMaterial
			_impact_particles.process_material = _impact_particles_process
		_impact_particles.emitting = false

func _resolve_standard_material(mesh_instance: MeshInstance3D) -> StandardMaterial3D:
	if mesh_instance == null:
		return null

	var material: Material = mesh_instance.material_override
	if material == null and mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0:
		material = mesh_instance.mesh.surface_get_material(0)

	var standard: StandardMaterial3D = null
	if material is StandardMaterial3D:
		standard = material.duplicate(true) as StandardMaterial3D
	else:
		standard = StandardMaterial3D.new()

	standard.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	standard.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	standard.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	standard.cull_mode = BaseMaterial3D.CULL_DISABLED
	standard.vertex_color_use_as_albedo = true
	standard.emission_enabled = true
	mesh_instance.material_override = standard
	return standard

func _bind_runtime() -> void:
	_disconnect_runtime()
	if _turret == null:
		_set_effect_active(false)
		return

	_runtime = _turret.get_runtime() as BeamWeaponRuntime
	if _runtime == null:
		_set_effect_active(false)
		_clear_beam_meshes()
		return
	if not _runtime.state_changed.is_connected(_on_beam_state_changed):
		_runtime.state_changed.connect(_on_beam_state_changed)
	_on_beam_state_changed(
		_runtime.get_lock_state(),
		_runtime.get_locked_target(),
		_runtime.get_lock_progress(),
		_runtime.get_ramp_stacks()
	)

func _disconnect_runtime() -> void:
	if _runtime != null and _runtime.state_changed.is_connected(_on_beam_state_changed):
		_runtime.state_changed.disconnect(_on_beam_state_changed)
	_runtime = null
	_target_ref = weakref(null)

func _on_beam_state_changed(_lock_state: int, target: Node3D, _lock_progress: float, _ramp_stacks: int) -> void:
	_target_ref = weakref(target) if target != null else weakref(null)
	var should_show: bool = target != null and _runtime != null and _runtime.get_lock_state() != BeamWeaponRuntime.LockState.IDLE
	_set_effect_active(should_show)
	if not should_show:
		_clear_beam_meshes()

func _get_active_target() -> Node3D:
	if _runtime != null:
		var runtime_target: Node3D = _runtime.get_locked_target()
		if runtime_target != null:
			return runtime_target
	if _target_ref == null:
		return null
	return _target_ref.get_ref() as Node3D

func _update_beam_materials(lock_progress: float, ramp_ratio: float, emission_energy: float) -> void:
	if _core_material != null:
		var core_alpha: float = lerp(0.20, 0.88, lock_progress)
		_core_material.albedo_color = Color(core_color.r, core_color.g, core_color.b, core_alpha)
		_core_material.emission = core_color
		_core_material.emission_energy_multiplier = emission_energy
	if _glow_material != null:
		var glow_alpha: float = lerp(0.08, 0.30, lock_progress) + 0.05 * ramp_ratio
		_glow_material.albedo_color = Color(glow_color.r, glow_color.g, glow_color.b, glow_alpha)
		_glow_material.emission = glow_color
		_glow_material.emission_energy_multiplier = emission_energy * 0.75
	if _impact_material != null:
		var impact_alpha: float = lerp(0.16, 0.52, lock_progress) + 0.08 * ramp_ratio
		_impact_material.albedo_color = Color(impact_color.r, impact_color.g, impact_color.b, impact_alpha)
		_impact_material.emission = impact_color
		_impact_material.emission_energy_multiplier = emission_energy * 0.55

func _update_beam_mesh(mesh: ImmediateMesh, start_world: Vector3, end_world: Vector3, width: float) -> void:
	if mesh == null:
		return

	mesh.clear_surfaces()

	var beam_dir: Vector3 = end_world - start_world
	var beam_dir_length_sq: float = beam_dir.length_squared()
	if beam_dir_length_sq <= 0.0001:
		return
	beam_dir = beam_dir / sqrt(beam_dir_length_sq)

	var camera: Camera3D = get_viewport().get_camera_3d()
	var to_camera: Vector3 = Vector3.UP
	if camera != null:
		to_camera = camera.global_position - start_world.lerp(end_world, 0.5)
		if to_camera.length_squared() > 0.0001:
			to_camera = to_camera.normalized()

	var right: Vector3 = beam_dir.cross(to_camera)
	if right.length_squared() <= 0.0001:
		right = beam_dir.cross(Vector3.UP)
	if right.length_squared() <= 0.0001:
		right = beam_dir.cross(Vector3.RIGHT)
	right = right.normalized() * max(0.001, width * 0.5)

	var start_left: Vector3 = to_local(start_world + right)
	var start_right: Vector3 = to_local(start_world - right)
	var end_left: Vector3 = to_local(end_world + right)
	var end_right: Vector3 = to_local(end_world - right)

	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	mesh.surface_set_color(Color.WHITE)
	mesh.surface_add_vertex(start_left)
	mesh.surface_set_color(Color.WHITE)
	mesh.surface_add_vertex(start_right)
	mesh.surface_set_color(Color.WHITE)
	mesh.surface_add_vertex(end_left)
	mesh.surface_set_color(Color.WHITE)
	mesh.surface_add_vertex(end_right)
	mesh.surface_end()

func _update_particles(start_world: Vector3, end_world: Vector3, beam_dir: Vector3, beam_length: float, lock_progress: float, ramp_ratio: float) -> void:
	if _beam_pivot != null:
		var mid_point: Vector3 = start_world.lerp(end_world, 0.5)
		_beam_pivot.global_position = mid_point
		var up: Vector3 = Vector3.UP
		if abs(beam_dir.dot(up)) > 0.95:
			up = Vector3.RIGHT
		_beam_pivot.look_at(end_world, up, true)

	if _beam_particles != null:
		_beam_particles.position = Vector3(0.0, 0.0, -beam_length * 0.5)
		_beam_particles.amount = maxi(6, int(round(lerp(6.0, 14.0, lock_progress) + ramp_ratio * 4.0)))
		_beam_particles.speed_scale = lerp(0.55, 1.15, lock_progress) + ramp_ratio * 0.15
		if _beam_particles_process != null:
			var beam_radius: float = lerp(acquire_glow_width, locked_glow_width, lock_progress) * 0.55
			_beam_particles_process.emission_box_extents = Vector3(beam_radius, beam_radius, max(0.1, beam_length * 0.5))

	if _impact_root != null:
		_impact_root.global_position = end_world
	if _impact_flare != null:
		var flare_scale: float = lerp(0.16, 0.42, lock_progress) + ramp_ratio * 0.08
		_impact_flare.scale = Vector3.ONE * flare_scale
	if _impact_particles != null:
		_impact_particles.amount = maxi(4, int(round(lerp(4.0, 10.0, lock_progress) + ramp_ratio * 3.0)))
		_impact_particles.speed_scale = lerp(0.45, 0.95, lock_progress) + ramp_ratio * 0.10
		if _impact_particles_process != null:
			var impact_spread: float = lerp(0.04, 0.10, lock_progress) + ramp_ratio * 0.02
			_impact_particles_process.emission_sphere_radius = impact_spread

func _set_effect_active(value: bool) -> void:
	visible = value
	if _beam_particles != null:
		_beam_particles.emitting = value
	if _impact_particles != null:
		_impact_particles.emitting = value

func _clear_beam_meshes() -> void:
	if _core_mesh != null:
		_core_mesh.clear_surfaces()
	if _glow_mesh != null:
		_glow_mesh.clear_surfaces()
