extends Camera3D
@export var target_path: NodePath
@export var lag: float = 8.0
@export var look_lag: float = 10.0
@export var offset: Vector3 = Vector3(0, 1.0, 0)

var _target: Node3D

func _ready() -> void:
	if target_path != NodePath(""):
		_target = get_node_or_null(target_path)

func _process(delta: float) -> void:
	if _target == null:
		return
	# Stick to the ship's CameraPivot in local space
	var pivot: Node3D = _target.get_node_or_null("CameraPivot")
	var desired_xform = pivot.global_transform if (pivot != null) else _target.global_transform
	var desired_pos = desired_xform.origin + offset
	global_position = global_position.lerp(desired_pos, clamp(lag * delta, 0.0, 1.0))
	look_at(_target.global_transform.origin, Vector3.UP)
