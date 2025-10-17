# spawner.gd  (Godot 4.5)
extends Node3D

enum SpawnKind {ENEMY, TARGET}
@export_enum("Any", "EnemiesOnly", "TargetsOnly")
var spawn_mode: int = 0
@export var enemy_weight: float = 0.6
@export var anti_streak_bias: float = 0.5

enum Size {SM, MD, LG}

@export var target_scene: PackedScene
@export var enemy_scene: PackedScene
@export var ship_path: NodePath

@export var spawn_radius: float = 400
@export var min_distance_from_ship: float = 150.0
@export var max_alive: int = 10
@export var spawn_interval: float = 1.5

var _alive := 0
var _timer: Timer
var _player_ship: Node3D
var _last_kind_was_enemy: bool = false
var _have_last: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	_player_ship = get_node_or_null(ship_path)
	_timer = Timer.new()
	_timer.wait_time = spawn_interval
	_timer.autostart = true
	_timer.timeout.connect(_try_spawn)
	add_child(_timer)

func _try_spawn() -> void:
	if enemy_scene == null or target_scene == null or _player_ship == null:
		return

	if _alive >= max_alive:
		return

	var pos: Vector3 = _pick_spawn_position()
	
	var kind: int = _pick_spawn_kind()
	var inst: Node3D = null
	
	if kind == SpawnKind.ENEMY:
		inst = enemy_scene.instantiate()
		_last_kind_was_enemy = true
	else:
		inst = target_scene.instantiate()
		_last_kind_was_enemy = false
	
	_have_last = true
	
	if _player_ship:
		inst.set_ship(_player_ship)
	
	get_tree().current_scene.add_child(inst)
	inst.global_position = pos
	
	_alive += 1
	inst.tree_exited.connect(func(): _alive = max(_alive - 1, 0))

func _pick_spawn_position() -> Vector3:
	var center := _player_ship.global_position if _player_ship else Vector3.ZERO
	var dir := Vector3(randf()*2-1, randf()*2-1, randf()*2-1).normalized()
	var pos := center + dir * spawn_radius

	if _player_ship and pos.distance_to(center) < min_distance_from_ship:
		pos = center + dir * min_distance_from_ship
	return pos

func _pick_spawn_kind() -> int:
	var allowed_enemy: bool = (spawn_mode != 2)
	var allowed_target: bool = (spawn_mode != 1)
	
	if allowed_enemy and not allowed_target:
		return SpawnKind.ENEMY
	if allowed_target and not allowed_enemy:
		return SpawnKind.TARGET
	
	var e_weight: float = clampf(enemy_weight, 0.0, 1.0)
	var t_weight: float = 1.0 - e_weight
	
	if _have_last:
		if _last_kind_was_enemy:
			e_weight *= (1.0 - clampf(anti_streak_bias, 0.0, 1.0))
		else:
			t_weight *= (1.0 - clampf(anti_streak_bias, 0.0, 1.0))
	
	var total: float = e_weight + t_weight
	if total <= 0.0:
		return SpawnKind.ENEMY
	
	var roll: float = _rng.randf() * total
	return SpawnKind.ENEMY if roll < e_weight else SpawnKind.TARGET
