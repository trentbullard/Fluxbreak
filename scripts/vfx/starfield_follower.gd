extends GPUParticles3D
@export var target_path: NodePath               # assign your Ship node in the editor
@export var box_extents: Vector3 = Vector3(250, 250, 250)  # must match Emission Box Extents
@export var margin: float = 20.0                # move a bit before/after boundary
@export var snap_step: float = 100.0            # recenter in chunks to reduce jitter

var _target: Node3D
var _home: Vector3

func _ready() -> void:
	_target = get_node_or_null(target_path)
	_home = global_position

func _process(_dt: float) -> void:
	if _target == null:
		return

	# Vector from starfield center to ship
	var to_ship = _target.global_position - global_position

	# If the ship drifts near the edge of the emission box on any axis, recenter in a snapped chunk
	var moved := false
	var new_pos := global_position

	# half extents minus margin
	var limit = box_extents - Vector3.ONE * margin
	# Check each axis
	for axis in 3:
		var val = to_ship[axis]
		if val > limit[axis]:
			new_pos[axis] += floor((val - limit[axis]) / snap_step + 1.0) * snap_step
			moved = true
		elif val < -limit[axis]:
			new_pos[axis] -= floor((-val - limit[axis]) / snap_step + 1.0) * snap_step
			moved = true

	if moved:
		# Moving the emitter in world-space will not teleport existing particles.
		global_position = new_pos
		_home = new_pos

		# Nudge visibility to ensure culling updates this frame (prevents rare popping).
		visible = false
		visible = true
