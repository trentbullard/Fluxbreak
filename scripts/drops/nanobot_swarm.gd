# nanobot_swarm.gd
extends Node3D

@export var particles: GPUParticles3D
@export var attractor: GPUParticlesAttractorSphere3D
@export var magnet_delay: float = 0.6
@export var attract_radius_start: float = 30.0
@export var attract_strength_start: float = 40.0
@export var attract_strength_max: float = 120.0
@export var ramp_time: float = 0.5

var _timer: float = 0.0
var _magnet_on: bool = false
var _player: RigidBody3D

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as RigidBody3D
	particles.emitting = true
	attractor.strength = 0.0
	attractor.radius = attract_radius_start
	attractor.strength = attract_strength_start

func _process(delta: float) -> void:
	if _player == null:
		return
	_timer += delta
	global_transform.origin = global_transform.origin # noop, keep anchored at spawn
	attractor.global_transform.origin = _player.global_transform.origin

	if not _magnet_on and _timer >= magnet_delay:
		_magnet_on = true
		attractor.strength = 80

	if _magnet_on and _timer <= magnet_delay + ramp_time:
		var t: float = clamp((_timer - magnet_delay) / ramp_time, 0.0, 1.0)
		attractor.strength = lerp(attract_strength_start, attract_strength_max, t)
