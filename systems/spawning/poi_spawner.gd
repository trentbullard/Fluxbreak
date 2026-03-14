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
## Initial spawn radius at game start
@export var initial_spawn_radius: float = 2000.0
## Maximum spawn radius after growth completes
@export var max_spawn_radius: float = 10000.0
## Time in seconds for radius to grow from initial to max (30 min = 1800s)
@export var radius_growth_time: float = 1800.0
## Minimum spawn radius from origin (inner boundary)
@export var min_spawn_radius: float = 500.0
## Minimum separation between POIs
@export var min_poi_separation: float = 1000.0
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
## Pool of POI definitions used for type selection and spawning
@export var poi_defs: Array[PoiDef] = []

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

## Definitions grouped by POI type
var _defs_by_type: Dictionary = {}

## Count of each configured POI type currently active
var _type_counts: Dictionary = {}

## Ordered list of configured POI types (derived from poi_defs)
var _configured_types: Array[int] = []

## Next instance ID to assign
var _next_instance_id: int = 0

## Total POIs spawned (used for spawn index)
var _total_spawned: int = 0

## Whether first POI has been spawned
var _first_poi_spawned: bool = false

## Elapsed time since spawner started (for radius growth)
var _elapsed_time: float = 0.0

var _last_spawn_used_scene_override: bool = false

# ─────────────────────────────────────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Initialize RNG
	if use_seed:
		_rng.seed = rng_seed
	else:
		_rng.randomize()

	_rebuild_definition_cache()
	
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


func _process(delta: float) -> void:
	_elapsed_time += delta


# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

## Get counts of active POIs by type
func get_poi_counts() -> Dictionary:
	var by_type: Dictionary = {}
	for type_val in _type_counts.keys():
		by_type[type_val] = int(_type_counts[type_val])

	return {
		"offense": int(_type_counts.get(PoiDef.PoiType.OFFENSE, 0)),
		"defense": int(_type_counts.get(PoiDef.PoiType.DEFENSE, 0)),
		"utility": int(_type_counts.get(PoiDef.PoiType.UTILITY, 0)),
		"total": get_active_pois().size(),
		"by_type": by_type,
	}


## Get all active POI instances
func get_active_pois() -> Array[PoiInstance]:
	var active_pois: Array[PoiInstance] = []
	for poi: PoiInstance in _active_pois:
		if _is_poi_active(poi):
			active_pois.append(poi)
	return active_pois


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
	# Get the definition for this type
	var def: PoiDef = _pick_def_for_type(type)
	if def == null:
		push_warning("PoiSpawner: No definition for type %d" % type)
		return null
	
	# Calculate spawn position
	var spawn_position: Vector3 = _pick_spawn_position()
	
	# Instantiate POI
	var inst: Node = _instantiate_poi_scene(def)
	if inst == null:
		return null

	var poi: PoiInstance = inst as PoiInstance
	
	if poi == null:
		push_warning("PoiSpawner: Scene for POI '%s' must have PoiInstance as root." % def.poi_id)
		inst.queue_free()
		return null
	
	# Configure the POI
	var id: int = _next_instance_id
	_next_instance_id += 1
	var index: int = _total_spawned
	_total_spawned += 1
	
	poi.configure(def, id, index, _last_spawn_used_scene_override)
	
	# Add to scene tree
	get_tree().current_scene.add_child(poi)
	poi.global_position = spawn_position
	
	# Add to 'poi' group for offscreen indicator tracking
	poi.add_to_group("poi")
	
	# Track the POI
	_active_pois.append(poi)
	if not _type_counts.has(type):
		_type_counts[type] = 0
	_type_counts[type] = int(_type_counts[type]) + 1
	
	# Connect to tree_exited for cleanup
	var type_captured: PoiDef.PoiType = type
	poi.tree_exited.connect(func() -> void:
		_on_poi_removed(poi, type_captured)
	)
	
	# Emit signals
	poi_spawned.emit(poi)
	_emit_counts_changed()
	
	_log("Spawned POI [%s] type=%d at %s (index=%d, id=%d)" % [
		def.display_name, type, spawn_position, index, id
	])
	
	return poi


func _on_poi_removed(poi: PoiInstance, type: PoiDef.PoiType) -> void:
	_active_pois.erase(poi)
	if _type_counts.has(type):
		_type_counts[type] = maxi(int(_type_counts[type]) - 1, 0)
	_emit_counts_changed()
	_log("POI removed. Active count: %d" % _active_pois.size())


func _emit_counts_changed() -> void:
	poi_counts_changed.emit(
		int(_type_counts.get(PoiDef.PoiType.OFFENSE, 0)),
		int(_type_counts.get(PoiDef.PoiType.DEFENSE, 0)),
		int(_type_counts.get(PoiDef.PoiType.UTILITY, 0)),
		get_active_pois().size()
	)


# ─────────────────────────────────────────────────────────────────────────────
# Type Selection
# ─────────────────────────────────────────────────────────────────────────────

func _pick_weighted_type() -> PoiDef.PoiType:
	var weights: Dictionary = {}
	
	for type_val in _configured_types:
		var type: PoiDef.PoiType = type_val as PoiDef.PoiType
		var count: int = int(_type_counts.get(type, 0))
		var type_spawn_weight: float = _get_type_spawn_weight(type) * base_type_weight

		if type_spawn_weight <= 0.0:
			continue
		
		if count == 0:
			# Type not present on map - give bonus weight
			weights[type] = type_spawn_weight + missing_type_bonus
		else:
			# Type present - use minimum weight to allow duplicates
			weights[type] = maxf(min_duplicate_weight, type_spawn_weight / float(count + 1))

	if weights.is_empty():
		push_warning("PoiSpawner: Could not pick POI type because no weighted definitions are configured.")
		if _configured_types.is_empty():
			return PoiDef.PoiType.OFFENSE
		return _configured_types[0] as PoiDef.PoiType
	
	# Weighted random selection
	var total_weight: float = 0.0
	for weight_val in weights.values():
		total_weight += float(weight_val)
	
	var roll: float = _rng.randf() * total_weight
	var cumulative: float = 0.0
	
	for type_val in weights.keys():
		cumulative += float(weights[type_val])
		if roll < cumulative:
			_log("Type selection: roll=%.2f, weights=%s, chose=%d" % [roll, weights, type_val])
			return type_val as PoiDef.PoiType
	
	# Fallback
	if _configured_types.is_empty():
		return PoiDef.PoiType.OFFENSE
	return _configured_types[0] as PoiDef.PoiType


func _rebuild_definition_cache() -> void:
	_defs_by_type.clear()
	_type_counts.clear()
	_configured_types.clear()

	for def: PoiDef in poi_defs:
		if def == null:
			continue

		var type: PoiDef.PoiType = def.poi_type
		var defs_for_type: Array[PoiDef] = _get_defs_for_type(type)
		defs_for_type.append(def)
		_defs_by_type[type] = defs_for_type

		if not _type_counts.has(type):
			_type_counts[type] = 0
			_configured_types.append(type)

	if _configured_types.is_empty():
		push_warning("PoiSpawner: poi_defs is empty. No POIs will spawn.")


func _get_defs_for_type(type: PoiDef.PoiType) -> Array[PoiDef]:
	if not _defs_by_type.has(type):
		var empty_defs: Array[PoiDef] = []
		return empty_defs
	return _defs_by_type[type] as Array[PoiDef]


func _pick_def_for_type(type: PoiDef.PoiType) -> PoiDef:
	var defs_for_type: Array[PoiDef] = _get_defs_for_type(type)
	if defs_for_type.is_empty():
		return null
	if defs_for_type.size() == 1:
		return defs_for_type[0]

	var total_weight: float = 0.0
	for def: PoiDef in defs_for_type:
		total_weight += maxf(def.spawn_weight, 0.0)

	if total_weight <= 0.0:
		var random_index: int = _rng.randi_range(0, defs_for_type.size() - 1)
		return defs_for_type[random_index]

	var roll: float = _rng.randf() * total_weight
	var cumulative: float = 0.0
	for def: PoiDef in defs_for_type:
		cumulative += maxf(def.spawn_weight, 0.0)
		if roll < cumulative:
			return def

	return defs_for_type[0]


func _get_type_spawn_weight(type: PoiDef.PoiType) -> float:
	var defs_for_type: Array[PoiDef] = _get_defs_for_type(type)
	var total: float = 0.0
	for def: PoiDef in defs_for_type:
		total += maxf(def.spawn_weight, 0.0)
	return total


func _instantiate_poi_scene(def: PoiDef) -> Node:
	_last_spawn_used_scene_override = false
	if def != null and def.scene_override != null:
		var override_instance: Node = def.scene_override.instantiate()
		if override_instance is PoiInstance:
			_last_spawn_used_scene_override = true
			return override_instance
		else:
			push_warning("PoiSpawner: scene_override for POI '%s' does not have PoiInstance as root." % def.poi_id)
			override_instance.queue_free()

	if poi_scene == null:
		var poi_id: String = "unknown"
		if def != null:
			poi_id = def.poi_id
		push_warning("PoiSpawner: No scene assigned for POI '%s'." % poi_id)
		return null

	return poi_scene.instantiate()


# ─────────────────────────────────────────────────────────────────────────────
# Position Selection
# ─────────────────────────────────────────────────────────────────────────────

## Get the current spawn radius based on elapsed time
func get_current_spawn_radius() -> float:
	var progress: float = clampf(_elapsed_time / radius_growth_time, 0.0, 1.0)
	return lerpf(initial_spawn_radius, max_spawn_radius, progress)


func _pick_spawn_position() -> Vector3:
	var current_separation: float = min_poi_separation
	var current_min_player_dist: float = min_distance_from_player
	var current_spawn_radius: float = get_current_spawn_radius()
	var attempts: int = 0
	
	_log("Current spawn radius: %.1f (%.1f%% of max)" % [
		current_spawn_radius, 
		(current_spawn_radius / max_spawn_radius) * 100.0
	])
	
	while attempts < max_placement_attempts * 3:
		# Generate a random point within a 3D sphere
		var candidate: Vector3 = _random_point_in_sphere(min_spawn_radius, current_spawn_radius)
		
		# Validate position
		if _is_valid_position(candidate, current_separation, current_min_player_dist):
			var distance: float = candidate.length()
			_log("Position found after %d attempts at distance %.1f" % [attempts + 1, distance])
			return candidate
		
		attempts += 1
		
		# Relax constraints every max_placement_attempts
		if attempts > 0 and attempts % max_placement_attempts == 0:
			current_separation *= separation_relaxation
			current_min_player_dist *= separation_relaxation
			_log("Relaxing constraints: separation=%.1f, min_player_dist=%.1f" % [
				current_separation, current_min_player_dist
			])
	
	# Fallback: just return a random point, ignoring constraints
	push_warning("PoiSpawner: Could not find valid position after %d attempts!" % attempts)
	return _random_point_in_sphere(min_spawn_radius, current_spawn_radius)


## Generate a uniformly distributed random point within a spherical shell
func _random_point_in_sphere(min_radius: float, max_radius: float) -> Vector3:
	# Use spherical coordinates for uniform distribution
	# theta: azimuthal angle [0, 2*PI]
	# phi: polar angle from cos distribution for uniform sphere surface
	var theta: float = _rng.randf() * TAU
	var cos_phi: float = _rng.randf_range(-1.0, 1.0)
	var sin_phi: float = sqrt(1.0 - cos_phi * cos_phi)
	
	# For uniform distribution within volume, use cube root of random for radius
	var radius_factor: float = _rng.randf()
	# Map to the shell between min_radius and max_radius
	var radius: float = lerp(min_radius, max_radius, pow(radius_factor, 1.0 / 3.0))
	
	# Convert to Cartesian coordinates
	return Vector3(
		radius * sin_phi * cos(theta),
		radius * cos_phi,
		radius * sin_phi * sin(theta)
	)


func _is_valid_position(pos: Vector3, separation: float, min_player_dist: float) -> bool:
	# Check distance from player
	if _is_node_3d_active(_player_ship):
		var min_player_dist_sq: float = min_player_dist * min_player_dist
		var player_dist_sq: float = pos.distance_squared_to(_player_ship.global_position)
		if player_dist_sq < min_player_dist_sq:
			return false
	
	# Check distance from other POIs
	var separation_sq: float = separation * separation
	for poi: PoiInstance in _active_pois:
		if not _is_poi_active(poi):
			continue
		var poi_dist_sq: float = pos.distance_squared_to(poi.global_position)
		if poi_dist_sq < separation_sq:
			return false

	return true


func _is_poi_active(poi: PoiInstance) -> bool:
	if not is_instance_valid(poi):
		return false
	return poi.is_inside_tree()


func _is_node_3d_active(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	return node.is_inside_tree()


# ─────────────────────────────────────────────────────────────────────────────
# Debug Logging
# ─────────────────────────────────────────────────────────────────────────────

func _log(message: String) -> void:
	if debug_logging:
		print("[PoiSpawner] %s" % message)
