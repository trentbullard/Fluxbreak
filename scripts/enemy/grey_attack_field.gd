extends MeshInstance3D
class_name GreyAttackField

## Sparse line geometry bounds each attack, with a few internal electric paths.
## Built once per shape, shared across every attack; never rebuilt during play.
const FIELD_SHADER: Shader = preload("res://scripts/enemy/grey_attack_field.gdshader")
const RING_SEGMENTS: int = 24

static var _material: ShaderMaterial = null
static var _sphere: ArrayMesh = null
static var _corridor: ArrayMesh = null
static var _link: ArrayMesh = null
static var _marker: ArrayMesh = null

var _state: Vector4 = Vector4.ZERO

func _init() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = FIELD_SHADER
	material_override = _material

func configure_sphere(radius: float) -> void:
	if _sphere == null:
		_sphere = _build_sphere()
	mesh = _sphere
	basis = Basis.IDENTITY.scaled(Vector3.ONE * maxf(radius, 1.0))
	_state.w = 0.0

## The unit corridor spans z=0..1 with flat end rings, matching the hit test.
func configure_corridor(start: Vector3, end: Vector3, radius: float) -> void:
	if start.distance_squared_to(end) <= 0.0001:
		configure_sphere(radius)
		global_position = end
		return
	if _corridor == null:
		_corridor = _build_corridor()
	mesh = _corridor
	_align_segment(start, end, maxf(radius, 1.0))
	_state.w = 1.0

## An attached tether moves only its transform, using a shared two-vertex mesh.
func configure_link(start: Vector3, end: Vector3) -> void:
	if _link == null:
		_link = _make_mesh(PackedVector3Array([Vector3.ZERO, Vector3.BACK]), PackedVector2Array([Vector2.ZERO, Vector2(1.0, 0.0)]))
	if mesh != _link:
		mesh = _link
	_align_segment(start, end, 1.0)
	_state.w = 2.0

## A diamond indicates harmless relocation rather than an attack boundary.
func configure_marker(radius: float) -> void:
	if _marker == null:
		var vertices: PackedVector3Array = PackedVector3Array()
		var uv: PackedVector2Array = PackedVector2Array()
		for pole: Vector3 in [Vector3.UP, Vector3.DOWN]:
			for index: int in range(4):
				var angle: float = float(index) * TAU / 4.0
				var next_angle: float = float(index + 1) * TAU / 4.0
				var point: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
				var next: Vector3 = Vector3(cos(next_angle), 0.0, sin(next_angle))
				_append_line(vertices, uv, pole, point, float(index), 0.0)
				if pole == Vector3.UP:
					_append_line(vertices, uv, point, next, float(index), 0.0)
		_marker = _make_mesh(vertices, uv)
	mesh = _marker
	basis = Basis.IDENTITY.scaled(Vector3.ONE * maxf(radius, 1.0))
	_state.w = 3.0

func set_charge(progress: float, elapsed: float) -> void:
	_state.x = clampf(progress, 0.0, 1.0)
	_state.y = elapsed
	_state.z = 0.0
	set_instance_shader_parameter(&"field_state", _state)

func set_capture_style() -> void:
	_state.w = 2.0
	set_instance_shader_parameter(&"field_state", _state)

func set_release(fraction: float) -> void:
	_state.z = clampf(fraction, 0.0, 1.0)
	set_instance_shader_parameter(&"field_state", _state)
	visible = fraction > 0.0

func _align_segment(start: Vector3, end: Vector3, radius: float) -> void:
	var segment: Vector3 = end - start
	var length: float = maxf(segment.length(), 0.001)
	var forward: Vector3 = segment / length if segment.length_squared() > 0.000001 else Vector3.BACK
	var reference: Vector3 = Vector3.UP if absf(forward.y) < 0.95 else Vector3.RIGHT
	var right: Vector3 = forward.cross(reference).normalized()
	var up: Vector3 = forward.cross(right).normalized()
	global_transform = Transform3D(Basis(right * radius, up * radius, forward * length), start)

static func _build_sphere() -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	var uv: PackedVector2Array = PackedVector2Array()
	_append_ring(vertices, uv, Vector3.ZERO, Vector3.RIGHT, Vector3.UP, 1.0)
	_append_ring(vertices, uv, Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, 1.0)
	_append_ring(vertices, uv, Vector3.ZERO, Vector3.UP, Vector3.BACK, 1.0)
	for height: float in [-0.5, 0.5]:
		_append_ring(vertices, uv, Vector3.UP * height, Vector3.RIGHT, Vector3.BACK, sqrt(0.75))
	for axis: int in range(3):
		for index: int in range(10):
			var start: Vector3 = _sphere_filament(float(index) / 10.0, axis)
			var end: Vector3 = _sphere_filament(float(index + 1) / 10.0, axis)
			_append_line(vertices, uv, start, end, float(index) / 10.0 + float(axis), 1.0)
	return _make_mesh(vertices, uv)

static func _sphere_filament(fraction: float, axis: int) -> Vector3:
	var wobble: float = sin(fraction * TAU * 2.0 + float(axis)) * 0.18
	var point: Vector3 = Vector3(lerpf(-0.82, 0.82, fraction), wobble, -wobble * 0.7)
	if axis == 1:
		return Vector3(point.z, point.x, point.y)
	if axis == 2:
		return Vector3(point.y, point.z, point.x)
	return point

static func _build_corridor() -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	var uv: PackedVector2Array = PackedVector2Array()
	_append_ring(vertices, uv, Vector3.ZERO, Vector3.RIGHT, Vector3.UP, 1.0)
	_append_ring(vertices, uv, Vector3.BACK, Vector3.RIGHT, Vector3.UP, 1.0)
	for rail: int in range(6):
		var angle: float = TAU * float(rail) / 6.0
		var offset: Vector3 = Vector3(cos(angle), sin(angle), 0.0)
		_append_line(vertices, uv, offset, offset + Vector3.BACK, float(rail), 0.0)
	for strand: int in range(3):
		for index: int in range(10):
			var start: Vector3 = _corridor_filament(float(index) / 10.0, strand)
			var end: Vector3 = _corridor_filament(float(index + 1) / 10.0, strand)
			_append_line(vertices, uv, start, end, float(index) / 10.0 + float(strand), 1.0)
	return _make_mesh(vertices, uv)

static func _corridor_filament(fraction: float, strand: int) -> Vector3:
	var angle: float = float(strand) * TAU / 3.0 + fraction * TAU
	return Vector3(cos(angle) * 0.42, sin(angle) * 0.42, fraction)

static func _append_ring(vertices: PackedVector3Array, uv: PackedVector2Array, center: Vector3, first: Vector3, second: Vector3, radius: float) -> void:
	for index: int in range(RING_SEGMENTS):
		var angle: float = TAU * float(index) / float(RING_SEGMENTS)
		var next_angle: float = TAU * float(index + 1) / float(RING_SEGMENTS)
		_append_line(vertices, uv, center + (first * cos(angle) + second * sin(angle)) * radius, center + (first * cos(next_angle) + second * sin(next_angle)) * radius, float(index) / float(RING_SEGMENTS), 0.0)

static func _append_line(vertices: PackedVector3Array, uv: PackedVector2Array, start: Vector3, end: Vector3, phase: float, internal: float) -> void:
	vertices.append(start)
	vertices.append(end)
	uv.append(Vector2(phase, internal))
	uv.append(Vector2(phase + 0.1, internal))

static func _make_mesh(vertices: PackedVector3Array, uv: PackedVector2Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var result: ArrayMesh = ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return result
