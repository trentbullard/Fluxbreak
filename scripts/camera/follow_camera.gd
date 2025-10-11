extends Camera3D

@export var target_path: NodePath
@export var local_offset: Vector3 = Vector3(0, 0.6, -6.0) # relative to ship (back is -Z)
@export var pos_lag: float = 14.0   # higher = snappier follow
@export var rot_lag: float = 24.0   # higher = snappier rotation
@export var inherit_roll: bool = true  # keep ship roll (space has no up)

var _target: Node3D

func _ready() -> void:
	if target_path != NodePath(""):
		_target = get_node_or_null(target_path)

func _process(delta: float) -> void:
	if _target == null:
		return

	# Use pivot if present
	var pivot: Node3D = _target.get_node_or_null("CameraPivot")
	var t: Transform3D = pivot.global_transform if pivot != null else _target.global_transform

	# Desired camera position: ship transform * local_offset
	var desired_pos: Vector3 = t.origin + t.basis * local_offset
	var p_alpha: float = clamp(pos_lag * delta, 0.0, 1.0)
	global_position = global_position.lerp(desired_pos, p_alpha)

	# Desired rotation: match ship orientation (including roll)
	var q_from: Quaternion = global_transform.basis.get_rotation_quaternion()
	var q_to:   Quaternion = t.basis.get_rotation_quaternion()

	# If you ever want to ignore roll, zero it here by rebuilding a basis that keeps forward but forces a custom up.
	if not inherit_roll:
		var forward := -t.basis.z
		var up := Vector3.UP  # or a smoothed "fake up" if you prefer
		var basis_no_roll := Basis.looking_at(forward, up)
		q_to = basis_no_roll.get_rotation_quaternion()

	var r_alpha: float = clamp(rot_lag * delta, 0.0, 1.0)
	var q_final: Quaternion = q_from.slerp(q_to, r_alpha)
	global_transform.basis = Basis(q_final)
