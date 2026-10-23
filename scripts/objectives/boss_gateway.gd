extends Node3D
class_name BossGateway

## Fallback name for a legacy gateway without an authored route.
@export var display_name: String = "Boss Gateway"
## Proximity required to inspect or enter this gateway.
@export var docking_radius: float = 240.0
## Legacy docking hold time, retained for existing stage definitions.
@export var docking_time: float = 2.5
## Rotation speed of the legacy ring hardware; names and route glyphs stay steady.
@export var spin_speed_rad_per_sec: float = 0.4

const DEFAULT_MARKER_COLOR: Color = Color(0.35, 1.0, 0.95, 1.0)

@onready var _ring: MeshInstance3D = $Ring
@onready var _cross_ring: MeshInstance3D = $CrossRing
@onready var _core: MeshInstance3D = $Core
@onready var _marker_glyph: Node3D = $MarkerGlyph
@onready var _route_label: Label3D = $RouteLabel

var _route: SectorRouteDef = null
var _salvage_marker: Node3D = null
var _assault_marker: Node3D = null
var _marker_material: StandardMaterial3D = null
var _accent_material: StandardMaterial3D = null

func _ready() -> void:
	add_to_group("boss_gateways")
	_build_route_markers()
	_apply_route_visuals()
	_face_marker_to_camera()

func _process(delta: float) -> void:
	var turn: float = maxf(spin_speed_rad_per_sec, 0.0) * maxf(delta, 0.0)
	_ring.rotate_y(turn)
	_cross_ring.rotate_y(-turn * 0.7)
	_face_marker_to_camera()

## Accept an authored route before or after entering the scene tree.
func configure_route(route: SectorRouteDef) -> void:
	_route = route
	if is_node_ready():
		_apply_route_visuals()

func get_route() -> SectorRouteDef:
	return _route

## Stable identity shared by the world marker and its on/off-screen HUD cues.
func get_marker_key() -> StringName:
	if _route != null:
		match _route.marker_kind:
			SectorRouteDef.MarkerKind.SALVAGE:
				return &"salvage"
			SectorRouteDef.MarkerKind.ASSAULT:
				return &"assault"
	return &"default"

func get_marker_color() -> Color:
	var tint: Color = _route.marker_color if _route != null else DEFAULT_MARKER_COLOR
	tint.a = 1.0
	return tint

func get_display_name() -> String:
	if _route != null:
		return _route.get_display_name()
	var trimmed: String = display_name.strip_edges()
	if trimmed != "":
		return trimmed
	return "Boss Gateway"

func get_docking_radius() -> float:
	return max(docking_radius, 0.0)

func get_docking_time() -> float:
	return max(docking_time, 0.0)

func _build_route_markers() -> void:
	_marker_material = _make_marker_material(DEFAULT_MARKER_COLOR)
	_accent_material = _make_marker_material(Color(1.0, 0.22, 0.12, 1.0))
	_salvage_marker = Node3D.new()
	_salvage_marker.name = "SalvageMarker"
	_marker_glyph.add_child(_salvage_marker)
	for side: int in range(6):
		var angle_a: float = PI / 6.0 + TAU * float(side) / 6.0
		var angle_b: float = PI / 6.0 + TAU * float(side + 1) / 6.0
		var start: Vector3 = Vector3(cos(angle_a), sin(angle_a), 0.0) * 105.0
		var finish: Vector3 = Vector3(cos(angle_b), sin(angle_b), 0.0) * 105.0
		_add_beam(_salvage_marker, "HexBracket%d" % side, start, finish, 10.0, _marker_material)
	# An open-jaw salvage tool stays recognizable inside the closed hexagonal frame.
	_add_beam(_salvage_marker, "ToolHandle", Vector3(-34.0, -50.0, 0.0), Vector3(14.0, 20.0, 0.0), 14.0, _marker_material)
	_add_beam(_salvage_marker, "ToolJawLeft", Vector3(14.0, 20.0, 0.0), Vector3(0.0, 46.0, 0.0), 12.0, _marker_material)
	_add_beam(_salvage_marker, "ToolJawLeftTip", Vector3(0.0, 46.0, 0.0), Vector3(10.0, 62.0, 0.0), 12.0, _marker_material)
	_add_beam(_salvage_marker, "ToolJawRight", Vector3(14.0, 20.0, 0.0), Vector3(43.0, 21.0, 0.0), 12.0, _marker_material)
	_add_beam(_salvage_marker, "ToolJawRightTip", Vector3(43.0, 21.0, 0.0), Vector3(59.0, 34.0, 0.0), 12.0, _marker_material)
	_assault_marker = Node3D.new()
	_assault_marker.name = "AssaultMarker"
	_marker_glyph.add_child(_assault_marker)
	for row: int in range(2):
		var peak_y: float = 80.0 - float(row) * 75.0
		var peak: Vector3 = Vector3(0.0, peak_y, 0.0)
		_add_beam(_assault_marker, "Chevron%dLeft" % row, Vector3(-76.0, peak_y - 67.0, 0.0), peak, 18.0, _marker_material)
		_add_beam(_assault_marker, "Chevron%dRight" % row, peak, Vector3(76.0, peak_y - 67.0, 0.0), 18.0, _marker_material)
	_add_beam(_assault_marker, "AlertSpine", Vector3(0.0, -75.0, 0.0), Vector3(0.0, -108.0, 0.0), 16.0, _accent_material)

func _add_beam(parent: Node3D, beam_name: String, start: Vector3, finish: Vector3, thickness: float, material: StandardMaterial3D) -> void:
	var delta: Vector3 = finish - start
	var beam_mesh: BoxMesh = BoxMesh.new()
	beam_mesh.size = Vector3(thickness, delta.length(), 10.0)
	var beam: MeshInstance3D = MeshInstance3D.new()
	beam.name = beam_name
	beam.mesh = beam_mesh
	beam.material_override = material
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = (start + finish) * 0.5
	beam.rotation.z = -atan2(delta.x, delta.y)
	parent.add_child(beam)

func _make_marker_material(tint: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = tint
	return material

func _apply_route_visuals() -> void:
	var key: StringName = get_marker_key()
	var tint: Color = get_marker_color()
	_marker_material.albedo_color = tint
	_accent_material.albedo_color = tint.lerp(Color(1.0, 0.16, 0.08, 1.0), 0.72)
	_ring.material_override = _marker_material
	_cross_ring.material_override = _marker_material
	_core.material_override = _marker_material
	_ring.visible = key == &"default"
	_cross_ring.visible = key == &"default"
	_core.visible = key == &"default"
	_salvage_marker.visible = key == &"salvage"
	_assault_marker.visible = key == &"assault"
	_route_label.text = get_display_name()
	_route_label.modulate = tint.lerp(Color.WHITE, 0.6)

func _face_marker_to_camera() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or _marker_glyph.global_position.distance_squared_to(camera.global_position) <= 0.0001:
		return
	var direction: Vector3 = (camera.global_position - _marker_glyph.global_position).normalized()
	var up: Vector3 = Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
	_marker_glyph.look_at(camera.global_position, up)
