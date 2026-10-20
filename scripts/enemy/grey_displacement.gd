extends Node3D
class_name GreyDisplacement

## Arrival itself is harmless; the owner schedules a separate attack afterward.
signal completed(moved: bool)

var _source: Enemy = null
var _destination: Vector3 = Vector3.ZERO
var _origin: Vector3 = Vector3.ZERO
var _remaining_sec: float = 0.0
var _active: bool = false
var _finished: bool = false
var _label: Label3D = null
var _wire: ImmediateMesh = null

func start_displacement(source: Enemy, destination: Vector3, windup_sec: float = 1.2) -> bool:
	if _active or _finished or not is_inside_tree() or not is_instance_valid(source) or source._dead or not source.is_inside_tree() or not destination.is_finite():
		return false
	_source = source
	_origin = source.global_position
	_destination = destination
	_remaining_sec = maxf(windup_sec, 0.2)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("grey_displacements")
	_source.about_to_die.connect(_on_source_died, CONNECT_ONE_SHOT)
	_source.tree_exiting.connect(cancel, CONNECT_ONE_SHOT)
	_build_markers()
	_active = true
	_update_label()
	return true

func is_active() -> bool:
	return _active and not _finished

func cancel() -> void:
	_finish(false)

func _physics_process(delta: float) -> void:
	if not is_active():
		return
	if not is_instance_valid(_source) or _source._dead or _source.is_queued_for_deletion() or not _source.is_inside_tree():
		cancel()
		return
	_remaining_sec = maxf(_remaining_sec - delta, 0.0)
	_update_label()
	if _remaining_sec <= 0.0:
		_source.global_position = _destination
		_source.linear_velocity = Vector3.ZERO
		_source.angular_velocity = Vector3.ZERO
		_finish(true)

func _finish(moved: bool) -> void:
	if _finished:
		return
	_active = false
	_finished = true
	completed.emit(moved)
	queue_free()

func _on_source_died(_enemy: Enemy) -> void:
	cancel()

func _build_markers() -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.52, 0.75, 1.0, 0.8)
	material.no_depth_test = true
	_wire = ImmediateMesh.new()
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "OriginAndArrival"
	visual.mesh = _wire
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	_wire.surface_begin(Mesh.PRIMITIVE_LINES, material)
	_add_marker(_origin, 22.0)
	_add_marker(_destination, 30.0)
	_wire.surface_add_vertex(_origin)
	_wire.surface_add_vertex(_destination)
	_wire.surface_end()
	_label = Label3D.new()
	_label.name = "ArrivalCountdown"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 28
	_label.outline_size = 6
	_label.pixel_size = 0.3
	_label.position = _destination + Vector3.UP * 44.0
	_label.modulate = Color(0.62, 0.82, 1.0)
	add_child(_label)

func _add_marker(center: Vector3, radius: float) -> void:
	for axis in range(3):
		var first: Vector3 = Vector3.RIGHT if axis != 2 else Vector3.UP
		var second: Vector3 = Vector3.UP if axis == 0 else Vector3.BACK
		for segment in range(32):
			var angle_a: float = TAU * float(segment) / 32.0
			var angle_b: float = TAU * float(segment + 1) / 32.0
			_wire.surface_add_vertex(center + (first * cos(angle_a) + second * sin(angle_a)) * radius)
			_wire.surface_add_vertex(center + (first * cos(angle_b) + second * sin(angle_b)) * radius)

func _update_label() -> void:
	_label.text = "SHIFT ARRIVAL  %.1fs" % _remaining_sec
