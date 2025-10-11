extends GPUParticles3D
@export var target_path: NodePath
@export var box_extents: Vector3 = Vector3(500, 500, 500)
@export var margin: float = 400.0
@export var snap_step: float = 50.0

var _target: Node3D
var _home: Vector3

func _ready() -> void:
	_target = get_node_or_null(target_path)
	_home = global_position

func _process(_dt: float) -> void:
	if _target == null:
		return

	var to_ship = _target.global_position - global_position

	var moved := false
	var new_pos := global_position

	var limit = box_extents - Vector3.ONE * margin

	for axis in 3:
		var val = to_ship[axis]
		if val > limit[axis]:
			new_pos[axis] += floor((val - limit[axis]) / snap_step + 1.0) * snap_step
			moved = true
		elif val < -limit[axis]:
			new_pos[axis] -= floor((-val - limit[axis]) / snap_step + 1.0) * snap_step
			moved = true

	if moved:
		global_position = new_pos
		_home = new_pos

		visible = false
		visible = true
