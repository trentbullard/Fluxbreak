# spawner.gd  (Godot 4.5)
extends Node3D

@export var target_scene: PackedScene
@export var enemy_scene: PackedScene
@export var spawn_radius: float = 400
@export var min_distance_from_ship: float = 150.0
@export var max_alive: int = 10
@export var spawn_interval: float = 1.5
@export var ship_path: NodePath
@export var enemy_chance: float = 0.4

var _alive := 0
var _timer: Timer
var _player_ship: Node3D
var _last_was_enemy: bool = false

enum Size {SM, MD, LG}

func _ready() -> void:
	_player_ship = get_node_or_null(ship_path)
	_timer = Timer.new()
	_timer.wait_time = spawn_interval
	_timer.autostart = true
	_timer.timeout.connect(_try_spawn)
	add_child(_timer)

func _try_spawn() -> void:
	if _alive >= max_alive or target_scene == null:
		return

	var pos: Vector3 = _pick_spawn_position()
	var roll: float = randf()
	var inst: Node3D
	#inst = enemy_scene.instantiate()
	#inst = target_scene.instantiate()
	if (_last_was_enemy and roll < 0.2) or (!_last_was_enemy and roll < enemy_chance):
		inst = enemy_scene.instantiate()
		_last_was_enemy = true
	else:
		inst = target_scene.instantiate()
		_last_was_enemy = false
	
	if _player_ship:
		inst.set_ship(_player_ship)
	
	var size_r: float = randf()
	var size: Size
	if size_r > 0.66:
		size = Size.LG
	elif size_r < 0.33:
		size = Size.SM
	else:
		size = Size.MD
	inst.set_size(size)
	
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
