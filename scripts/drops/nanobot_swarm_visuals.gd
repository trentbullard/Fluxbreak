extends Node3D
class_name NanobotSwarmVisuals

## Individual particles stay small, leaving the original moving cloud visible.
## Close-range diameter of one outlined particle in render-target pixels.
@export var near_particle_size_pixels: float = 3.2
## Distant particles shrink slightly so overlapping points do not become a badge.
@export var far_particle_size_pixels: float = 2.0
## Keep full distance visibility through this range in metres.
@export var readable_distance: float = 3000.0
## Fade completely beyond this camera distance in metres.
@export var fade_distance: float = 3500.0

var _swarm: NanobotSwarm
var _cloud: GPUParticles3D
var _visual_strength: float = 0.0

func _ready() -> void:
	_swarm = get_parent() as NanobotSwarm
	_cloud = get_parent() as GPUParticles3D
	refresh_visuals()

func _process(_delta: float) -> void:
	refresh_visuals()

func refresh_visuals() -> void:
	if not is_instance_valid(_swarm):
		return
	var value_fraction: float = _swarm.get_value_fraction()
	var value_strength: float = value_visual_strength(value_fraction)
	var camera: Camera3D = get_viewport().get_camera_3d()
	var distance_strength: float = 0.0
	var particle_size: float = near_particle_size_pixels
	if is_instance_valid(camera):
		var camera_transform: Transform3D = camera.get_camera_transform()
		var to_swarm: Vector3 = global_position - camera_transform.origin
		var distance_sq: float = to_swarm.length_squared()
		var distance: float = sqrt(distance_sq)
		var depth: float = to_swarm.dot(-camera_transform.basis.z)
		if depth > camera.near and distance_sq < fade_distance * fade_distance:
			distance_strength = 1.0 - smoothstep(readable_distance, maxf(fade_distance, readable_distance + 1.0), distance)
			particle_size = lerpf(near_particle_size_pixels, far_particle_size_pixels, clampf(distance / maxf(readable_distance, 1.0), 0.0, 1.0))
	_visual_strength = distance_strength * value_strength
	if is_instance_valid(_cloud):
		# PointMesh keeps the same 1,000 particles and depth-tested world positions.
		_cloud.set_instance_shader_parameter(&"particle_size_pixels", maxf(particle_size, 1.0))
		_cloud.transparency = 1.0 - _visual_strength

## Shared with existing edge indicators; the final 5% is a gradual disappearance.
static func value_visual_strength(value_fraction: float) -> float:
	var fraction: float = clampf(value_fraction, 0.0, 1.0)
	return lerpf(0.35, 1.0, sqrt(fraction)) * smoothstep(0.0, 0.05, fraction)

func get_visual_strength() -> float:
	return _visual_strength
