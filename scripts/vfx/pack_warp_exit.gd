extends Node3D
class_name PackWarpExit

@export_group("Portal")
@export var lifetime_sec: float = 0.55
@export var portal_radius: float = 64.0
@export var glow_color: Color = Color(0.23, 0.93, 1.0, 1.0)
@export var glow_energy: float = 3.8
@export var core_radius_ratio: float = 0.72

@export_group("Spin")
@export var ring_spin_deg_per_sec: float = 140.0
@export var cross_spin_deg_per_sec: float = -110.0

@export_group("Audio")
@export var whoosh_volume_db: float = -16.0
@export var whoosh_pitch_scale: float = 0.68

@onready var _ring_a: MeshInstance3D = $RingA
@onready var _ring_b: MeshInstance3D = $RingB
@onready var _core: MeshInstance3D = $Core
@onready var _swirl: CPUParticles3D = $Swirl
@onready var _whoosh: AudioStreamPlayer3D = $Whoosh

var _elapsed_sec: float = 0.0
var _ring_a_material: BaseMaterial3D = null
var _ring_b_material: BaseMaterial3D = null
var _core_material: BaseMaterial3D = null
var _swirl_material: BaseMaterial3D = null

func configure_for_pack(member_radius: float, spawn_pressure_scale: float = 0.0) -> void:
	var safe_scale: float = clampf(spawn_pressure_scale, 0.0, 1.0)
	var radius_scale: float = lerpf(0.55, 0.80, safe_scale)
	portal_radius = clampf(member_radius * radius_scale, 38.0, 130.0)
	glow_energy *= lerpf(1.0, 1.18, safe_scale)
	lifetime_sec = max(lifetime_sec, 0.1)

func _ready() -> void:
	_ring_a_material = _duplicate_mesh_material(_ring_a)
	_ring_b_material = _duplicate_mesh_material(_ring_b)
	_core_material = _duplicate_mesh_material(_core)
	_swirl_material = _duplicate_particle_material(_swirl)

	_apply_material_style(_ring_a_material, 0.95)
	_apply_material_style(_ring_b_material, 0.75)
	_apply_material_style(_core_material, 0.55)
	_apply_material_style(_swirl_material, 0.65)

	if _swirl != null:
		_swirl.restart()
		_swirl.emitting = true
	if _whoosh != null:
		_whoosh.volume_db = whoosh_volume_db
		_whoosh.pitch_scale = whoosh_pitch_scale
		_whoosh.play()

	_apply_visuals(0.0)
	set_process(true)

func _process(delta: float) -> void:
	_elapsed_sec += max(delta, 0.0)
	var safe_lifetime: float = max(lifetime_sec, 0.01)
	var progress: float = clampf(_elapsed_sec / safe_lifetime, 0.0, 1.0)

	if _ring_a != null:
		_ring_a.rotate_object_local(Vector3.FORWARD, deg_to_rad(ring_spin_deg_per_sec) * delta)
	if _ring_b != null:
		_ring_b.rotate_object_local(Vector3.RIGHT, deg_to_rad(cross_spin_deg_per_sec) * delta)

	_apply_visuals(progress)
	if progress >= 1.0:
		queue_free()

func _apply_visuals(progress: float) -> void:
	var bloom_progress: float = clampf(progress / 0.24, 0.0, 1.0)
	var collapse_progress: float = clampf((progress - 0.56) / 0.44, 0.0, 1.0)
	var envelope: float = 1.0 - collapse_progress

	var ring_scale_factor: float = lerpf(0.22, 1.0, bloom_progress) * lerpf(1.0, 0.12, collapse_progress)
	var cross_scale_factor: float = lerpf(0.18, 0.9, bloom_progress) * lerpf(1.0, 0.18, collapse_progress)
	var core_scale_factor: float = lerpf(0.35, core_radius_ratio, bloom_progress) * lerpf(1.0, 0.08, collapse_progress)
	var swirl_scale_factor: float = lerpf(0.35, 1.0, bloom_progress) * lerpf(1.0, 0.28, collapse_progress)
	var alpha: float = envelope * lerpf(1.0, 0.0, progress)

	if _ring_a != null:
		_ring_a.scale = Vector3.ONE * max(portal_radius * ring_scale_factor, 0.001)
	if _ring_b != null:
		_ring_b.scale = Vector3.ONE * max(portal_radius * cross_scale_factor, 0.001)
	if _core != null:
		_core.scale = Vector3.ONE * max(portal_radius * core_scale_factor, 0.001)
	if _swirl != null:
		_swirl.scale = Vector3.ONE * max(portal_radius * swirl_scale_factor, 0.001)

	_set_material_alpha(_ring_a_material, alpha, 1.0)
	_set_material_alpha(_ring_b_material, alpha, 0.85)
	_set_material_alpha(_core_material, alpha * 0.75, 0.65)
	_set_material_alpha(_swirl_material, alpha * 0.55, 0.55)

func _duplicate_mesh_material(mesh_instance: MeshInstance3D) -> BaseMaterial3D:
	if mesh_instance == null:
		return null
	var source_material: Material = mesh_instance.material_override
	if source_material == null and mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0:
		source_material = mesh_instance.mesh.surface_get_material(0)
	if not source_material is BaseMaterial3D:
		return null
	var runtime_material: BaseMaterial3D = source_material.duplicate(true) as BaseMaterial3D
	mesh_instance.material_override = runtime_material
	return runtime_material

func _duplicate_particle_material(particles: CPUParticles3D) -> BaseMaterial3D:
	if particles == null:
		return null
	var draw_mesh: Mesh = particles.mesh
	if not draw_mesh is QuadMesh:
		return null
	var quad: QuadMesh = draw_mesh.duplicate(true) as QuadMesh
	if quad == null:
		return null
	if not quad.material is BaseMaterial3D:
		return null
	var runtime_material: BaseMaterial3D = quad.material.duplicate(true) as BaseMaterial3D
	quad.material = runtime_material
	particles.mesh = quad
	return runtime_material

func _apply_material_style(material: BaseMaterial3D, alpha_scale: float) -> void:
	if material == null:
		return
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(glow_color.r, glow_color.g, glow_color.b, alpha_scale)
	material.emission_enabled = true
	material.emission = glow_color
	material.emission_energy_multiplier = glow_energy
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

func _set_material_alpha(material: BaseMaterial3D, alpha: float, energy_scale: float) -> void:
	if material == null:
		return
	var tinted: Color = material.albedo_color
	tinted.a = clampf(alpha, 0.0, 1.0)
	material.albedo_color = tinted
	material.emission = glow_color
	material.emission_energy_multiplier = glow_energy * max(energy_scale, 0.0)
