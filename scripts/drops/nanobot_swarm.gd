# scripts/drops/nanobot_swarm.gd (Godot 4.7.2)
extends Node3D
class_name NanobotSwarm

enum LifecycleState { ACTIVE, COLLECTED, EXPIRED }

## Existing cloud particles; visual extent is independent of collection geometry.
@export var particles: GPUParticles3D
## Existing player-following particle attractor.
@export var attractor: GPUParticlesAttractorSphere3D
## Delay after entering pickup range before attraction starts moving the swarm.
@export var magnet_delay: float = 0.6
## Initial particle attraction radius; does not change the ship's pickup range.
@export var attract_radius_start: float = 30.0
## Particle attraction strength at the start of collection.
@export var attract_strength_start: float = 40.0
## Particle attraction strength after the existing collection ramp.
@export var attract_strength_max: float = 120.0
## Seconds used by the existing particle attraction ramp.
@export var ramp_time: float = 0.5
## Active gameplay seconds until the original value has decayed completely.
@export_range(0.01, 600.0, 0.01, "or_greater") var lifetime_sec: float = 120.0
## Authored starting value before initialization; reads the current uncollected value.
@export var value: int = 0:
	get:
		return get_remaining_value()
	set(next_value):
		# Legacy authoring may supply a value before insertion, but cannot refresh a drop.
		if not _initialized:
			_original_value = maxi(next_value, 0)
			_remaining_value = _original_value

## Collection hitbox radius; deliberately unchanged by visual enlargement.
@export var pickup_distance: float = 5.0
## Existing attraction speed for the hitbox and the visual cloud.
@export var move_towards_player_speed: float = 120.0

var _magnet_on: bool = false
var _magnet_started_ts: float = 0.0
var _player: Ship
var _initialized: bool = false
var _original_value: int = 0
var _remaining_value: int = 0
var _age_sec: float = 0.0
var _lifetime_sec: float = 120.0
var _state: LifecycleState = LifecycleState.ACTIVE
var _committed_value: int = 0
var _committed_player: Ship
var _award_committed: bool = false

# Invisible collection hitbox position (decoupled from visual particles).
var _collection_pos: Vector3

## Production drop paths call this once, before adding the swarm to the scene.
func initialize(drop_value: int) -> bool:
	if _initialized or is_inside_tree():
		return false
	_initialize_value(drop_value)
	return true

func _initialize_value(drop_value: int) -> void:
	_initialized = true
	_original_value = maxi(drop_value, 0)
	_remaining_value = _original_value
	_lifetime_sec = maxf(lifetime_sec, 0.01)
	_age_sec = 0.0

func get_remaining_value() -> int:
	return _remaining_value if _state == LifecycleState.ACTIVE else 0

func get_value_fraction() -> float:
	if _original_value <= 0 or _state != LifecycleState.ACTIVE:
		return 0.0
	# Smooth visual aging is independent of integer rounding on the actual payout.
	return clampf(1.0 - _age_sec / _lifetime_sec, 0.0, 1.0)

func get_age_sec() -> float:
	return _age_sec

func get_lifecycle_state() -> LifecycleState:
	return _state

func is_active() -> bool:
	return _state == LifecycleState.ACTIVE and _remaining_value > 0

func _ready() -> void:
	# Scene-authored values remain valid; runtime callers initialize before insertion.
	if not _initialized:
		_initialize_value(_original_value)
	if process_mode == Node.PROCESS_MODE_INHERIT:
		process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("drops")
	set_meta("kind", "drop")
	_player = get_tree().get_first_node_in_group("player") as Ship
	if particles != null:
		particles.emitting = true
	if attractor != null:
		attractor.radius = attract_radius_start
		attractor.strength = 0.0
	_collection_pos = global_transform.origin
	if _remaining_value <= 0:
		_expire()

func _process(delta: float) -> void:
	if _state != LifecycleState.ACTIVE or not is_inside_tree() or get_tree().paused:
		return
	# Age before every attraction/player check, including distant and playerless drops.
	_age_sec = minf(_age_sec + maxf(delta, 0.0), _lifetime_sec)
	if _age_sec >= _lifetime_sec:
		_expire()
		return
	_remaining_value = ceili(float(_original_value) * (1.0 - _age_sec / _lifetime_sec))
	if not is_instance_valid(_player) or _player.is_queued_for_deletion():
		_player = get_tree().get_first_node_in_group("player") as Ship
	if not is_instance_valid(_player) or _player.is_queued_for_deletion() or not _player.is_alive():
		return

	# Collection hitbox (_collection_pos) moves toward player independently.
	var player_pos: Vector3 = _player.global_transform.origin
	var dist_to_collection_sq: float = _collection_pos.distance_squared_to(player_pos)
	var trigger_range: float = _player.get_effective_pickup_range()
	if not _magnet_on:
		var trigger_sq: float = trigger_range * trigger_range
		if dist_to_collection_sq <= trigger_sq:
			_magnet_on = true
			_magnet_started_ts = 0.0
			if attractor != null:
				attractor.strength = attract_strength_start
		else:
			if attractor != null:
				attractor.strength = 0.0
			return

	_magnet_started_ts += delta
	if _magnet_started_ts >= magnet_delay:
		var t: float = clampf((_magnet_started_ts - magnet_delay) / maxf(ramp_time, 0.000001), 0.0, 1.0)
		if attractor != null:
			attractor.strength = lerpf(attract_strength_start, attract_strength_max, t)

		# Preserve the original invisible hitbox attraction movement and pickup check.
		var collection_dir: Vector3 = player_pos - _collection_pos
		var collection_dir_len_sq: float = collection_dir.length_squared()
		if collection_dir_len_sq > 0.000001:
			var step_dist: float = move_towards_player_speed * delta
			if step_dist * step_dist >= collection_dir_len_sq:
				_collection_pos = player_pos
			else:
				_collection_pos += (collection_dir / sqrt(collection_dir_len_sq)) * step_dist

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

	if attractor != null:
		attractor.global_transform.origin = player_pos
	var pickup_sq: float = pickup_distance * pickup_distance
	if dist_to_collection_sq <= pickup_sq:
		_commit_pickup()

func _commit_pickup() -> void:
	if not is_active() or not is_instance_valid(_player) or _player.is_queued_for_deletion() or not _player.is_alive():
		return
	# Lock this frame's integer payout and recipient before deferring credit.
	_committed_value = _remaining_value
	_committed_player = _player
	_state = LifecycleState.COLLECTED
	remove_from_group("drops")
	if particles != null:
		particles.emitting = false
	if attractor != null:
		attractor.strength = attract_strength_max * 2.0
	call_deferred("_on_picked")

func _on_picked() -> void:
	if _state != LifecycleState.COLLECTED or _award_committed:
		return
	_award_committed = true
	if is_instance_valid(_committed_player) and not _committed_player.is_queued_for_deletion() and _committed_player.is_alive():
		# Ship retains its existing nanobot collection modifiers.
		_committed_player.collect_nanobots(_committed_value)
	queue_free()

func _expire() -> void:
	if _state != LifecycleState.ACTIVE:
		return
	_state = LifecycleState.EXPIRED
	_remaining_value = 0
	remove_from_group("drops")
	if particles != null:
		particles.emitting = false
	hide()
	queue_free()
