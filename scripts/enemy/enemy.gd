# target_object.gd  (Godot 4.5)
extends RigidBody3D
class_name Enemy

@export var max_hull: float = 20.0
@export var max_shield: float = 0.0
@export var shield_regen: float = 0.0
@export var evasion: float = 0.10        # 0..1
@export var thrust: float = 40.0
@export var explosion_scene: PackedScene
@export var score_on_kill: int = 10

@export var player_ship: Ship
@export var label_height: float = 1.5
@export var label_update_hz: float = 10.0

@export var min_distance: float = 250.0
@export var max_distance: float = 400.0
@export var model_root_path: NodePath = ^"ModelRoot"

var _dead: bool = false
var _last_xform: Transform3D = Transform3D()
var hull: float
var shield: float
var _tangent_axis: Vector3 = Vector3.UP
var _axis_timer: float = 0.0

enum Size {SM, MD, LG}
@export var size: Size = Size.MD
@export var randomize_on_spawn: bool = true

const SIZE_DATA: Dictionary = {
	Size.SM: { "hull_mult": 0.5, "scale": 0.25, "thrust_mult": 1.15, "evasion_add": 0.05, "score_mult": 0.5 },
	Size.MD: { "hull_mult": 1.0, "scale": 1.0,  "thrust_mult": 1.0,  "evasion_add": 0.0, "score_mult": 1.0  },
	Size.LG: { "hull_mult": 1.5, "scale": 2.0,  "thrust_mult": 0.85, "evasion_add": -0.05, "score_mult": 1.5 }
}

func _ready() -> void:
	add_to_group("targets")
	_last_xform = global_transform
	hull = max_hull
	shield = max_shield
	if randomize_on_spawn:
		var pool: Array[int] = [Size.SM, Size.SM, Size.MD, Size.MD, Size.MD, Size.MD, Size.MD, Size.LG, Size.LG, Size.LG]
		size = pool[randi() % pool.size()] as Size
	_pick_new_axis()
	_apply_size(size)

func _physics_process(delta: float) -> void:
	_axis_timer -= delta
	if _axis_timer <= 0.0:
		_pick_new_axis()
	
	if player_ship != null:
		_face_target(player_ship.global_position)
		_orbit_target(player_ship.global_position)

func _process(_delta: float) -> void:
	if is_inside_tree():
		_last_xform = global_transform

func apply_damage(amount: float) -> void:
	if _dead:
		return
	hull -= amount
	if hull <= 0.0:
		_die()

func set_ship(ship: Ship):
	player_ship = ship

func get_evasion() -> float:
	return clamp(evasion, 0.0, 1.0)

func _die() -> void:
	if _dead:
		return
	_dead = true
	RunState.add_score(score_on_kill, "enemy")
	
	if has_node("CollisionShape3D"):
		var col: CollisionShape3D = $CollisionShape3D
		col.disabled = true
	
	if explosion_scene != null:
		var fx: Node3D = explosion_scene.instantiate() as Node3D
		fx.global_transform = global_transform
		var parent_for_fx: Node = get_parent() if get_parent() != null else get_tree().root
		parent_for_fx.add_child(fx)
	
	hide()
	queue_free()

func _face_target(target: Vector3) -> void:
	var desired: Vector3 = (target - global_position).normalized()
	var forward: Vector3 = -global_transform.basis.z
	var axis: Vector3 = forward.cross(desired)
	var dot: float = clamp(forward.dot(desired), -1.0, 1.0)
	var angle: float = acos(dot)
	
	if axis.length_squared() > 0.0001 and angle > 0.001:
		var torque: Vector3 = axis.normalized() * angle * 6.0
		apply_torque(torque)
	
	var new_transform: Transform3D = global_transform.looking_at(target, Vector3.UP)
	new_transform.origin = global_position
	global_transform = new_transform

func _orbit_target(target: Vector3) -> void:
	var to_target: Vector3 = target - global_position
	var dist2: float = to_target.length_squared()
	var min2: float = min_distance * min_distance
	var max2: float = max_distance * max_distance
	
	var radial_dir_out: Vector3 = -to_target.normalized()
	if dist2 < min2:
		apply_central_force(radial_dir_out * thrust)
	if dist2 > max2:
		apply_central_force(-radial_dir_out * thrust)
	
	var tangent: Vector3 = radial_dir_out.cross(_tangent_axis).normalized()
	apply_central_force(tangent * thrust * 0.3)

func _is_offscreen(cam: Camera3D, world_pos: Vector3) -> bool:
	# Behind camera?
	if cam.is_position_behind(world_pos):
		return true

	# Outside viewport rect?
	var screen_pos: Vector2 = cam.unproject_position(world_pos)
	var rect: Rect2i = get_viewport().get_visible_rect()
	return not rect.has_point(screen_pos)

func _apply_size(s: Size) -> void:
	var data: Dictionary = SIZE_DATA[s]
	score_on_kill = int(ceil(score_on_kill * float(data["score_mult"])))
	hull = max_hull * float(data["hull_mult"])
	thrust = thrust * float(data["thrust_mult"])
	evasion = clamp(evasion + float(data["evasion_add"]), 0.0, 1.0)
	
	var model_root: Node3D = get_node_or_null(model_root_path) as Node3D
	if model_root != null:
		var k: float = float(data["scale"])
		model_root.scale = Vector3(k, k, k)
		var col: CollisionShape3D = $CollisionShape3D
		col.scale = Vector3(k, k, k)

func _pick_new_axis() -> void:
	var choices: Array[Vector3] = [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT]
	_tangent_axis = choices.pick_random()
	_axis_timer = randf_range(1.0, 4.0)
