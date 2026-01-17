# scripts/drops/nanobot_swarm.gd (godot 4.5)
extends Node3D
class_name NanobotSwarm

@export var particles: GPUParticles3D
@export var attractor: GPUParticlesAttractorSphere3D
@export var magnet_delay: float = 0.6
@export var attract_radius_start: float = 30.0
@export var attract_strength_start: float = 40.0
@export var attract_strength_max: float = 120.0
@export var ramp_time: float = 0.5
@export var value: int = 0

@export var pickup_distance: float = 5.0
@export var move_towards_player_speed: float = 120.0

var _magnet_on: bool = false
var _magnet_started_ts: float = 0.0
var _player: Ship
var _picked: bool = false

func _ready() -> void:
	add_to_group("drops")
	set_meta("kind", "drop")
	_player = get_tree().get_first_node_in_group("player") as RigidBody3D
	particles.emitting = true
	attractor.radius = attract_radius_start
	attractor.strength = 0.0

func _process(delta: float) -> void:
	if _player == null:
		return
	
	var cur_pos: Vector3 = global_transform.origin
	var player_pos: Vector3 = _player.global_transform.origin
	var dist_sq: float = cur_pos.distance_squared_to(player_pos)
	
	var trigger_range: float = 0.0
	trigger_range = _player.get_effective_pickup_range()

	if not _magnet_on:
		var trigger_sq: float = trigger_range * trigger_range
		if dist_sq <= trigger_sq:
			_magnet_on = true
			_magnet_started_ts = 0.0
			attractor.strength = attract_strength_start
		else:
			attractor.strength = 0.0
			return
	
	_magnet_started_ts += delta
	if _magnet_started_ts >= magnet_delay:
		var t: float = clamp((_magnet_started_ts - magnet_delay) / ramp_time, 0.0, 1.0)
		attractor.strength = lerp(attract_strength_start, attract_strength_max, t)
		
		var dir: Vector3 = player_pos - cur_pos
		var dir_len: float = dir.length()
		if dir_len > 0.001:
			var step: Vector3 = (dir / dir_len) * move_towards_player_speed * delta
			if step.length() >= dir_len:
				cur_pos = player_pos
			else:
				cur_pos += step
			var txf: Transform3D = global_transform
			txf.origin = cur_pos
			global_transform = txf
	
	attractor.global_transform.origin = player_pos
	
	var pickup_sq: float = pickup_distance * pickup_distance
	if not _picked and dist_sq <= pickup_sq:
		_picked = true
		particles.emitting = false
		attractor.strength = attract_strength_max * 2.0
		call_deferred("_on_picked")

func _on_picked() -> void:
	_player.collect_nanobots(value)
	queue_free()
