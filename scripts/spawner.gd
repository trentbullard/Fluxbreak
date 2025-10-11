# spawner.gd  (Godot 4.5)
extends Node3D

@export var target_scene: PackedScene
@export var spawn_radius: float = 400
@export var min_distance_from_ship: float = 150.0
@export var max_alive: int = 10
@export var spawn_interval: float = 1.5
@export var ship_path: NodePath

var _alive := 0
var _timer: Timer
var _ship: Node3D

func _ready() -> void:
	_ship = get_node_or_null(ship_path)
	_timer = Timer.new()
	_timer.wait_time = spawn_interval
	_timer.autostart = true
	_timer.timeout.connect(_try_spawn)
	add_child(_timer)

func _try_spawn() -> void:
	if _alive >= max_alive or target_scene == null:
		return

	var pos := _pick_spawn_position()
	var inst := target_scene.instantiate() as Node3D
	
	if _ship and inst.has_method("set"):
		inst.set("ship_path", _ship.get_path())
	
	get_tree().current_scene.add_child(inst)
	inst.global_position = pos
	
	_alive += 1
	inst.tree_exited.connect(func(): _alive = max(_alive - 1, 0))

func _pick_spawn_position() -> Vector3:
	var center := _ship.global_position if _ship else Vector3.ZERO
	var dir := Vector3(randf()*2-1, randf()*2-1, randf()*2-1).normalized()
	var pos := center + dir * spawn_radius

	if _ship and pos.distance_to(center) < min_distance_from_ship:
		pos = center + dir * min_distance_from_ship
	return pos
