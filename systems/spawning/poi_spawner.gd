# systems/spawning/poi_spawner.gd (Godot 4.5)
extends Node3D
class_name PoiSpawner

## Emitted when a POI is spawned
signal poi_spawned(poi: PoiInstance)

## Emitted when active POI counts change
signal poi_counts_changed(offense: int, defense: int, utility: int, total: int)

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

@export_group("References")
## Path to player ship node for position tracking
@export var ship_path: NodePath
## Default POI scene to instantiate
@export var poi_scene: PackedScene

@export_group("Spawn Timing")
## Delay before first POI spawns (seconds)
@export var initial_spawn_delay: float = 0.5
## Minimum time between subsequent POI spawns (seconds)
@export var spawn_interval_min: float = 120.0
## Maximum time between subsequent POI spawns (seconds)
@export var spawn_interval_max: float = 180.0

@export_group("Spawn Distances")
## Distance from origin for the first POI
@export var first_poi_distance: float = 3000.0
## Distance increment per POI index
@export var distance_step: float = 500.0
## Random jitter applied to spawn distance
@export var distance_jitter: float = 300.0
## Minimum separation between POIs
@export var min_poi_separation: float = 800.0
## Minimum distance from player when spawning
@export var min_distance_from_player: float = 500.0
## Maximum placement attempts before relaxing constraints
@export var max_placement_attempts: int = 20
## How much to relax separation per failed batch
@export var separation_relaxation: float = 0.8

@export_group("Type Weighting")
## Base weight for each POI type
@export var base_type_weight: float = 1.0
## Extra weight for types not currently on the map
@export var missing_type_bonus: float = 3.0
## Minimum weight to always allow duplicates (low-ish chance)
@export var min_duplicate_weight: float = 0.3

@export_group("POI Definitions")
## Definition to use for OFFENSE type
@export var offense_def: PoiDef
## Definition to use for DEFENSE type
@export var defense_def: PoiDef
## Definition to use for UTILITY type
@export var utility_def: PoiDef

@export_group("Debug")
## Enable debug logging
@export var debug_logging: bool = true
## Use deterministic seed for reproducible spawns
@export var use_seed: bool = false
## Seed value when use_seed is true
@export var rng_seed: int = 12345

# ─────────────────────────────────────────────────────────────────────────────
# Runtime State
# ─────────────────────────────────────────────────────────────────────────────

## Internal RNG instance
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Timer for spawning POIs
var _spawn_timer: Timer

## Reference to player ship
var _player_ship: Node3D

## List of all active POI instances
var _active_pois: Array[PoiInstance] = []

## Count of each POI type currently active
var _type_counts: Dictionary = {
	PoiDef.PoiType.OFFENSE: 0,
	PoiDef.PoiType.DEFENSE: 0,
	PoiDef.PoiType.UTILITY: 0,
}

## Next instance ID to assign
var _next_instance_id: int = 0

## Total POIs spawned (used for spawn index)
var _total_spawned: int = 0

## Whether first POI has been spawned
var _first_poi_spawned: bool = false


# ─────────────────────────────────────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Initialize RNG
	if use_seed:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	
	# Get player ship reference
	_player_ship = get_node_or_null(ship_path) as Node3D
	
	# Create and configure spawn timer
	_spawn_timer = Timer.new()
	_spawn_timer.one_shot = true
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(_spawn_timer)
	
	# Start initial spawn delay
	_spawn_timer.start(initial_spawn_delay)
	
	_log("PoiSpawner initialized. First POI in %.1f seconds." % initial_spawn_delay)


# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

## Get counts of active POIs by type
func get_poi_counts() -> Dictionary:
	return {
		"offense": _type_counts[PoiDef.PoiType.OFFENSE],
		"defense": _type_counts[PoiDef.PoiType.DEFENSE],
		"utility": _type_counts[PoiDef.PoiType.UTILITY],
		"total": _active_pois.size(),
	}


## Get all active POI instances
func get_active_pois() -> Array[PoiInstance]:
	return _active_pois.duplicate()


## Force spawn a POI of a specific type (for testing/debugging)
func force_spawn(type: PoiDef.PoiType) -> PoiInstance:
	return _spawn_poi_of_type(type)


# ─────────────────────────────────────────────────────────────────────────────
# Timer Callback
# ─────────────────────────────────────────────────────────────────────────────

func _on_spawn_timer_timeout() -> void:
	# Pick weighted type
	var chosen_type: PoiDef.PoiType = _pick_weighted_type()
	
	# Spawn the POI
	var poi: PoiInstance = _spawn_poi_of_type(chosen_type)
	
	if poi != null:
		_first_poi_spawned = true
	
	# Schedule next spawn
	var next_interval: float = _rng.randf_range(spawn_interval_min, spawn_interval_max)
	_spawn_timer.start(next_interval)
	
	_log("Next POI spawn in %.1f seconds." % next_interval)


# ─────────────────────────────────────────────────────────────────────────────
# Spawning Logic
# ─────────────────────────────────────────────────────────────────────────────

func _spawn_poi_of_type(type: PoiDef.PoiType) -> PoiInstance:
	if poi_scene == null:
		push_warning("PoiSpawner: No poi_scene assigned!")
		return null
	
	# Get the definition for this type
	var def: PoiDef = _get_def_for_type(type)
	if def == null:
		push_warning("PoiSpawner: No definition for type %d" % type)
		return null
	
	# Calculate spawn position
	position = _pick_spawn_position()
	
	# Instantiate POI
	var inst: Node3D = poi_scene.instantiate()
	var poi: PoiInstance = inst as PoiInstance
	
	if poi == null:
		push_warning("PoiSpawner: poi_scene does not contain PoiInstance!")
		inst.queue_free()
		return null
	
	# Configure the POI
	var id: int = _next_instance_id
	_next_instance_id += 1
	var index: int = _total_spawned
	_total_spawned += 1
	
	poi.configure(def, id, index)
	
	# Add to scene tree
	get_tree().current_scene.add_child(poi)
	poi.global_position = position
	
	# Add to 'poi' group for offscreen indicator tracking
	poi.add_to_group("poi")
	
	# Track the POI
	_active_pois.append(poi)
	_type_counts[type] += 1
	
	# Connect to tree_exited for cleanup
	var type_captured: PoiDef.PoiType = type
	poi.tree_exited.connect(func() -> void:
		_on_poi_removed(poi, type_captured)
	)
	
	# Emit signals
	poi_spawned.emit(poi)
	_emit_counts_changed()
	
	_log("Spawned POI [%s] type=%d at %s (index=%d, id=%d)" % [
		def.display_name, type, position, index, id
	])
	
	return poi


func _on_poi_removed(poi: PoiInstance, type: PoiDef.PoiType) -> void:
	_active_pois.erase(poi)
	_type_counts[type] = maxi(_type_counts[type] - 1, 0)
	_emit_counts_changed()
	_log("POI removed. Active count: %d" % _active_pois.size())


func _emit_counts_changed() -> void:
	poi_counts_changed.emit(
		_type_counts[PoiDef.PoiType.OFFENSE],
		_type_counts[PoiDef.PoiType.DEFENSE],
		_type_counts[PoiDef.PoiType.UTILITY],
		_active_pois.size()
	)


# ─────────────────────────────────────────────────────────────────────────────
# Type Selection
# ─────────────────────────────────────────────────────────────────────────────

func _pick_weighted_type() -> PoiDef.PoiType:
	var weights: Dictionary = {}
	
	for type_val in [PoiDef.PoiType.OFFENSE, PoiDef.PoiType.DEFENSE, PoiDef.PoiType.UTILITY]:
		var type: PoiDef.PoiType = type_val as PoiDef.PoiType
		var count: int = _type_counts[type]
		
		if count == 0:
			# Type not present on map - give bonus weight
			weights[type] = base_type_weight + missing_type_bonus
		else:
			# Type present - use minimum weight to allow duplicates
			weights[type] = maxf(min_duplicate_weight, base_type_weight / float(count + 1))
	
	# Weighted random selection
	var total_weight: float = 0.0
	for w: float in weights.values():
		total_weight += w
	
	var roll: float = _rng.randf() * total_weight
	var cumulative: float = 0.0
	
	for type_val in weights.keys():
		cumulative += weights[type_val]
		if roll < cumulative:
			_log("Type selection: roll=%.2f, weights=%s, chose=%d" % [roll, weights, type_val])
			return type_val as PoiDef.PoiType
	
	# Fallback
	return PoiDef.PoiType.OFFENSE


func _get_def_for_type(type: PoiDef.PoiType) -> PoiDef:
	match type:
		PoiDef.PoiType.OFFENSE:
			return offense_def
		PoiDef.PoiType.DEFENSE:
			return defense_def
		PoiDef.PoiType.UTILITY:
			return utility_def
		_:
			return offense_def


# ─────────────────────────────────────────────────────────────────────────────
# Position Selection
# ─────────────────────────────────────────────────────────────────────────────

func _pick_spawn_position() -> Vector3:
	var spawn_index: int = _total_spawned
	var base_distance: float = first_poi_distance + (spawn_index * distance_step)
	
	var current_separation: float = min_poi_separation
	var attempts: int = 0
	
	while attempts < max_placement_attempts * 3:
		# Pick a random direction on the XZ plane (space is horizontal)
		var angle: float = _rng.randf() * TAU
		var direction: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		
		# Apply distance with jitter
		var jitter: float = _rng.randf_range(-distance_jitter, distance_jitter)
		var distance: float = base_distance + jitter
		
		var candidate: Vector3 = direction * distance
		
		# Validate position
		if _is_valid_position(candidate, current_separation):
			_log("Position found after %d attempts at distance %.1f" % [attempts + 1, distance])
			return candidate
		
		attempts += 1
		
		# Relax constraints every max_placement_attempts
		if attempts > 0 and attempts % max_placement_attempts == 0:
			current_separation *= separation_relaxation
			base_distance *= 1.1  # Also expand search radius
			_log("Relaxing constraints: separation=%.1f, base_distance=%.1f" % [
				current_separation, base_distance
			])
	
	# Fallback: just return something valid distance-wise
	push_warning("PoiSpawner: Could not find valid position after %d attempts!" % attempts)
	var fallback_angle: float = _rng.randf() * TAU
	return Vector3(cos(fallback_angle), 0.0, sin(fallback_angle)) * base_distance


func _is_valid_position(pos: Vector3, separation: float) -> bool:
	# Check distance from player
	if _player_ship != null:
		var player_dist: float = pos.distance_to(_player_ship.global_position)
		if player_dist < min_distance_from_player:
			return false
	
	# Check distance from other POIs
	for poi: PoiInstance in _active_pois:
		if not is_instance_valid(poi):
			continue
		var poi_dist: float = pos.distance_to(poi.global_position)
		if poi_dist < separation:
			return false
	
	return true


# ─────────────────────────────────────────────────────────────────────────────
# Debug Logging
# ─────────────────────────────────────────────────────────────────────────────

func _log(message: String) -> void:
	if debug_logging:
		print("[PoiSpawner] %s" % message)
