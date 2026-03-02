# scripts/vfx/trail.gd  (Godot 4.5)
extends MeshInstance3D

@export var target_path: NodePath
@export var trail_length_m: float = 2.0
@export var width_m: float = 0.08
@export var min_step_m: float = 0.03
@export var max_points: int = 96
@export var max_new_points_per_tick: int = 12

@export var emission_color: Color = Color(0.4, 0.9, 1.0, 1.0)
@export var emission_energy: float = 6.0

var _target: Node3D = null
var _mesh: ImmediateMesh = null

# Newest -> oldest, stored in world space.
var _points: Array[Vector3] = []
var _distances: Array[float] = [] # distance from _points[i] to _points[i + 1]
var _accum_length: float = 0.0

func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	if _target == null:
		push_error("Trail: target_path is invalid.")
		return

	_mesh = ImmediateMesh.new()
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 2000.0

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = emission_color
	mat.emission_energy_multiplier = emission_energy
	material_override = mat

	_add_point(_target.global_position)
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	if _target == null:
		return

	var p: Vector3 = _target.global_position
	if _points.is_empty():
		_add_point(p)
		_rebuild()
		return

	var head: Vector3 = _points[0]
	var step: float = max(0.005, min_step_m)
	var segment: Vector3 = p - head
	var dist: float = segment.length()

	if dist >= step:
		var spacing: float = max(step, dist / float(max(1, max_new_points_per_tick)))
		var dir: Vector3 = segment / max(dist, 0.000001)
		var cursor: Vector3 = head
		var remaining: float = dist
		var emitted: int = 0
		while remaining >= spacing and emitted < max_new_points_per_tick:
			cursor += dir * spacing
			_add_point(cursor)
			remaining -= spacing
			emitted += 1

	_move_head(p)
	_trim_to_length()
	_rebuild()

func _add_point(p_world: Vector3) -> void:
	if _points.size() > 0:
		var d: float = p_world.distance_to(_points[0])
		_distances.insert(0, d)
		_accum_length += d
	_points.insert(0, p_world)

	while _points.size() > max(2, max_points):
		_remove_last_point()

func _move_head(p_world: Vector3) -> void:
	if _points.is_empty():
		_add_point(p_world)
		return
	if _points.size() == 1:
		_points[0] = p_world
		return

	var old_seg: float = _distances[0]
	var new_seg: float = p_world.distance_to(_points[1])
	_points[0] = p_world
	_distances[0] = new_seg
	_accum_length += new_seg - old_seg

func _remove_last_point() -> void:
	if _points.size() <= 1:
		return
	var last_seg_index: int = _distances.size() - 1
	if last_seg_index >= 0:
		_accum_length -= _distances[last_seg_index]
		_distances.remove_at(last_seg_index)
	_points.remove_at(_points.size() - 1)

func _trim_to_length() -> void:
	var target_length: float = max(0.05, trail_length_m)
	while _accum_length > target_length and _points.size() > 2:
		_remove_last_point()

	# Clamp the two-point case exactly to requested length.
	if _points.size() == 2 and _accum_length > target_length:
		var head: Vector3 = _points[0]
		var tail: Vector3 = _points[1]
		var dir: Vector3 = tail - head
		var length: float = dir.length()
		if length > 0.000001:
			tail = head + dir / length * target_length
			_points[1] = tail
			_distances[0] = target_length
			_accum_length = target_length

func _rebuild() -> void:
	_mesh.clear_surfaces()
	if _points.size() < 2:
		return

	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return

	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var half_w: float = max(0.001, width_m * 0.5)
	var last_index: int = _points.size() - 1

	for i in range(_points.size()):
		var curr_w: Vector3 = _points[i]
		var prev_w: Vector3 = _points[max(i - 1, 0)]
		var next_w: Vector3 = _points[min(i + 1, last_index)]
		var dir_w: Vector3 = prev_w - next_w
		if dir_w.length_squared() < 0.000001:
			dir_w = Vector3.BACK
		else:
			dir_w = dir_w.normalized()

		var to_cam: Vector3 = cam.global_position - curr_w
		if to_cam.length_squared() < 0.000001:
			to_cam = Vector3.UP
		else:
			to_cam = to_cam.normalized()

		var right_w: Vector3 = dir_w.cross(to_cam)
		if right_w.length_squared() < 0.000001:
			right_w = cam.global_basis.x
		else:
			right_w = right_w.normalized()

		var v0_local: Vector3 = to_local(curr_w + right_w * half_w)
		var v1_local: Vector3 = to_local(curr_w - right_w * half_w)

		var t: float = float(i) / float(last_index)
		var a: float = 1.0 - t
		var c: Color = Color(emission_color.r, emission_color.g, emission_color.b, a)

		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(v0_local)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(v1_local)

	_mesh.surface_end()
