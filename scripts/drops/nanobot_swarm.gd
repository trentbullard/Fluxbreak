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

# Invisible collection hitbox position (decoupled from visual particles)
var _collection_pos: Vector3

func _ready() -> void:
	add_to_group("drops")
	set_meta("kind", "drop")
	_player = get_tree().get_first_node_in_group("player") as RigidBody3D
	particles.emitting = true
	attractor.radius = attract_radius_start
	attractor.strength = 0.0
	# Initialize collection position to spawn location
	_collection_pos = global_transform.origin

func _process(delta: float) -> void:
	if _player == null:
		return
	
	# Collection hitbox (_collection_pos) moves toward player independently
	var player_pos: Vector3 = _player.global_transform.origin
	
	# Use collection position for trigger/pickup checks
	var dist_to_collection_sq: float = _collection_pos.distance_squared_to(player_pos)
	
	var trigger_range: float = _player.get_effective_pickup_range()

	if not _magnet_on:
		var trigger_sq: float = trigger_range * trigger_range
		if dist_to_collection_sq <= trigger_sq:
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
		
		# Move the invisible collection hitbox toward player
		var collection_dir: Vector3 = player_pos - _collection_pos
		var collection_dir_len_sq: float = collection_dir.length_squared()
		if collection_dir_len_sq > 0.000001:
			var step_dist: float = move_towards_player_speed * delta
			if step_dist * step_dist >= collection_dir_len_sq:
				_collection_pos = player_pos
			else:
				_collection_pos += (collection_dir / sqrt(collection_dir_len_sq)) * step_dist
		
		# Move the visual particles toward player (original cur_pos behavior)
		var cur_pos: Vector3 = global_transform.origin
		var visual_dir: Vector3 = player_pos - cur_pos
		var visual_dir_len_sq: float = visual_dir.length_squared()
		if visual_dir_len_sq > 0.000001:
			var visual_step_dist: float = move_towards_player_speed * delta
			if visual_step_dist * visual_step_dist >= visual_dir_len_sq:
				cur_pos = player_pos
			else:
				cur_pos += (visual_dir / sqrt(visual_dir_len_sq)) * visual_step_dist
			global_transform.origin = cur_pos
	
	# Attractor always follows player so visible particles swarm correctly
	attractor.global_transform.origin = player_pos
	
	# Check pickup against the invisible collection hitbox, not visual position
	var pickup_sq: float = pickup_distance * pickup_distance
	if not _picked and dist_to_collection_sq <= pickup_sq:
		_picked = true
		particles.emitting = false
		attractor.strength = attract_strength_max * 2.0
		call_deferred("_on_picked")

func _on_picked() -> void:
	_player.collect_nanobots(value)
	queue_free()
