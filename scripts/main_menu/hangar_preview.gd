extends Node3D
class_name HangarPreview

const ROSTER_PATH: String = "res://content/data/pilots/pilot_roster.tres"
const SHIP_PATHS: Array[String] = [
	"res://content/data/ships/starter_fighter.tres",
	"res://content/data/ships/heavy_bruiser.tres",
	"res://content/data/ships/drone_carrier.tres",
]
const BAY_PITCH: Vector2 = Vector2(28.0, 32.0)
const DISPLAY_SPAN: float = 10.5
const DISPLAY_HEIGHT: float = 3.2
const CAMERA_OFFSET: Vector3 = Vector3(14.0, 10.0, -18.0)
const FRAME_SHIFT: float = 6.3

@onready var _camera: Camera3D = $Camera3D
@onready var _bays_root: Node3D = $Bays
@onready var _key_light: OmniLight3D = $DisplayKey
@onready var _rim_light: OmniLight3D = $DisplayRim

var _active: bool = true
var _motion_enabled: bool = true
var _ready_for_selection: bool = false
var _selection_pending: bool = false
var _pending_pilot: PilotDef = null
var _pending_ship: ShipDef = null
var _selected_bay_id: StringName = &""
var _bays: Dictionary = {}
var _visual_templates: Dictionary = {}
var _camera_tween: Tween = null
var _camera_destination: Transform3D = Transform3D.IDENTITY
var _transitioning: bool = false
var _idle_time: float = 0.0
var _unit_box: BoxMesh = null
var _materials: Dictionary = {}

func _ready() -> void:
	# The menu can remain visible while its containing game tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_unit_box = BoxMesh.new()
	_unit_box.size = Vector3.ONE
	_build_materials()
	_build_known_bays()
	_ready_for_selection = true
	_camera_destination = _camera.transform
	if _selection_pending:
		set_selection(_pending_pilot, _pending_ship, true)
	else:
		var roster: PilotRoster = load(ROSTER_PATH) as PilotRoster
		var pilots: Array[PilotDef] = roster.get_pilots() if roster != null else []
		if not pilots.is_empty():
			set_selection(pilots[0], pilots[0].ship, true)
	set_active(_active)

## Show only visual resources; gameplay actors, hardpoints and effects stay absent.
func set_selection(pilot: PilotDef, ship: ShipDef, immediate: bool = false) -> void:
	_pending_pilot = pilot
	_pending_ship = ship
	_selection_pending = true
	if not _ready_for_selection:
		return
	var selected_ship: ShipDef = ship if ship != null else (pilot.ship if pilot != null else null)
	if selected_ship == null:
		_selected_bay_id = &""
		_stop_camera_transition()
		_refresh_bay_lighting()
		return
	var bay_id: StringName = _get_bay_id(pilot, selected_ship)
	if not _bays.has(bay_id):
		_create_bay(pilot, selected_ship, _bays.size())
	var unchanged: bool = bay_id == _selected_bay_id
	_selected_bay_id = bay_id
	_refresh_bay_lighting()
	if unchanged and not immediate:
		return
	var bay: Node3D = _bays[bay_id] as Node3D
	_camera_destination = _camera_transform_for_bay(bay.position)
	_key_light.position = bay.position + Vector3(2.0, 9.0, -7.0)
	_rim_light.position = bay.position + Vector3(-6.0, 5.0, 6.0)
	if immediate or not _motion_enabled or not _active:
		_stop_camera_transition()
		_camera.transform = _camera_destination
		return
	_stop_camera_transition()
	var travel: float = sqrt(_camera.position.distance_squared_to(_camera_destination.origin))
	var duration: float = clampf(travel / 45.0, 0.45, 1.1)
	_transitioning = true
	_camera_tween = create_tween()
	_camera_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_camera_tween.set_parallel(true)
	_camera_tween.set_trans(Tween.TRANS_CUBIC)
	_camera_tween.set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_property(_camera, "position", _camera_destination.origin, duration)
	_camera_tween.tween_property(_camera, "quaternion", _camera_destination.basis.get_rotation_quaternion(), duration)
	_camera_tween.finished.connect(_on_camera_transition_finished)

## Stop all preview work while the menu's viewport is hidden or disabled.
func set_active(active: bool) -> void:
	_active = active
	visible = active
	set_process(active and _motion_enabled)
	if not active:
		_stop_camera_transition()
		if _ready_for_selection:
			_camera.transform = _camera_destination

## Reduced motion snaps every selection and removes the idle ship animation.
func set_motion_enabled(enabled: bool) -> void:
	_motion_enabled = enabled
	if not enabled:
		_stop_camera_transition()
		if _ready_for_selection:
			_camera.transform = _camera_destination
			_reset_idle_poses()
	set_process(_active and enabled)

func get_selected_bay_id() -> StringName:
	return _selected_bay_id

func is_transitioning() -> bool:
	return _transitioning

func _process(delta: float) -> void:
	if not _active or not _motion_enabled or not _ready_for_selection:
		return
	_idle_time += minf(maxf(delta, 0.0), 0.1)
	for bay_value: Variant in _bays.values():
		var bay: Node3D = bay_value as Node3D
		var display: Node3D = bay.get_node_or_null("Display") as Node3D
		if display == null:
			continue
		var phase: float = float(bay.get_meta("idle_phase", 0.0))
		display.position.y = DISPLAY_HEIGHT + sin(_idle_time * 0.65 + phase) * 0.07
		display.rotation.y = -0.16 + sin(_idle_time * 0.3 + phase) * 0.025

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree() and not is_visible_in_tree():
		_stop_camera_transition()
		if _ready_for_selection:
			_camera.transform = _camera_destination
	elif what == NOTIFICATION_PAUSED:
		_stop_camera_transition()
		if _ready_for_selection:
			_camera.transform = _camera_destination

func _exit_tree() -> void:
	_stop_camera_transition()
	for template_value: Variant in _visual_templates.values():
		var template: Node3D = template_value as Node3D
		if is_instance_valid(template):
			template.free()
	_visual_templates.clear()
	_bays.clear()
	_ready_for_selection = false

func _stop_camera_transition() -> void:
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera_tween = null
	_transitioning = false

func _on_camera_transition_finished() -> void:
	_camera_tween = null
	_transitioning = false
	if _ready_for_selection:
		_camera.transform = _camera_destination

func _camera_transform_for_bay(bay_position: Vector3) -> Transform3D:
	var focus: Vector3 = bay_position + Vector3(0.0, 3.0, 0.0)
	var pose: Transform3D = Transform3D(Basis.IDENTITY, focus + CAMERA_OFFSET)
	pose = pose.looking_at(focus, Vector3.UP)
	# A parallel framing offset places the hull in the right two thirds and
	# reserves the left side for the menu at either supported widescreen size.
	pose.origin -= pose.basis.x * FRAME_SHIFT
	return pose

func _get_bay_id(pilot: PilotDef, ship: ShipDef) -> StringName:
	var pilot_id: StringName = pilot.get_pilot_id() if pilot != null else &"unassigned"
	return StringName("%s:%s" % [pilot_id, ship.get_ship_id()])

func _build_known_bays() -> void:
	var roster: PilotRoster = load(ROSTER_PATH) as PilotRoster
	if roster == null:
		return
	var ships: Array[ShipDef] = []
	for path: String in SHIP_PATHS:
		var ship: ShipDef = load(path) as ShipDef
		if ship != null:
			ships.append(ship)
	for pilot: PilotDef in roster.get_pilots():
		for ship: ShipDef in ships:
			_create_bay(pilot, ship, _bays.size())

func _create_bay(pilot: PilotDef, ship: ShipDef, index: int) -> void:
	var bay_id: StringName = _get_bay_id(pilot, ship)
	if _bays.has(bay_id):
		return
	var bay: Node3D = Node3D.new()
	bay.name = "Bay_%02d" % (index + 1)
	bay.position = Vector3(float(index % 3) * BAY_PITCH.x, 0.0, float(index / 3) * BAY_PITCH.y)
	bay.set_meta("idle_phase", float(index) * 0.67)
	_bays_root.add_child(bay)
	_bays[bay_id] = bay
	var metal: StandardMaterial3D = _materials[&"metal"] as StandardMaterial3D
	var deck: StandardMaterial3D = _materials[&"deck"] as StandardMaterial3D
	var dark: StandardMaterial3D = _materials[&"dark"] as StandardMaterial3D
	var amber: StandardMaterial3D = _materials[&"amber"] as StandardMaterial3D
	var cyan: StandardMaterial3D = _materials[&"cyan_dim"] as StandardMaterial3D
	_make_box(bay, "DockDeck", Vector3(0, -0.25, 0), Vector3(18, 0.4, 18), deck)
	_make_box(bay, "PortRail", Vector3(-8.5, 0.015, 0), Vector3(0.055, 0.03, 17), amber)
	_make_box(bay, "StarboardRail", Vector3(8.5, 0.015, 0), Vector3(0.055, 0.03, 17), amber)
	_make_box(bay, "FrontGuide", Vector3(0, 0.02, -8.5), Vector3(16, 0.03, 0.065), cyan)
	_make_box(bay, "RearGuide", Vector3(0, 0.02, 8.5), Vector3(16, 0.03, 0.065), cyan)
	_make_box(bay, "PortColumn", Vector3(-9.3, 5, 8.8), Vector3(0.65, 10, 0.7), metal)
	_make_box(bay, "StarboardColumn", Vector3(9.3, 5, 8.8), Vector3(0.65, 10, 0.7), metal)
	_make_box(bay, "ServiceBeam", Vector3(0, 10.0, 8.8), Vector3(19.3, 0.8, 0.75), metal)
	_make_box(bay, "ServiceLamp", Vector3(0, 9.54, 8.8), Vector3(10.5, 0.05, 0.25), cyan)
	_make_box(bay, "BackBulkhead", Vector3(0, 3.6, 10), Vector3(17.8, 7.2, 0.4), dark)
	_make_box(bay, "BackInset", Vector3(0, 4.0, 9.77), Vector3(12.8, 5.0, 0.08), deck)
	for stripe: int in range(5):
		_make_box(bay, "DockMark%d" % stripe, Vector3(-1.2 + float(stripe) * 0.6, 0.025, -7.9), Vector3(0.3, 0.035, 0.35), amber)
	var number: Label3D = Label3D.new()
	number.name = "BayNumber"
	number.text = "BAY %02d" % (index + 1)
	number.position = Vector3(0, 8.7, 9.5)
	number.rotation.y = PI
	number.font_size = 44
	number.pixel_size = 0.017
	number.modulate = Color(0.42, 0.64, 0.72)
	number.outline_size = 0
	number.no_depth_test = false
	bay.add_child(number)
	var display: Node3D = Node3D.new()
	display.name = "Display"
	display.position.y = DISPLAY_HEIGHT
	display.rotation.y = -0.16
	bay.add_child(display)
	var visual_template: Node3D = _get_visual_template(ship)
	if visual_template != null:
		var model: Node3D = visual_template.duplicate() as Node3D
		if model != null:
			model.name = "ShipVisual"
			display.add_child(model)
	_build_pilot_stand_in(bay, pilot, index / 3)

func _get_visual_template(ship: ShipDef) -> Node3D:
	if ship.visuals == null or ship.visuals.model_scene == null:
		return null
	var source: PackedScene = ship.visuals.model_scene
	var key: String = source.resource_path
	if key.is_empty():
		key = str(source.get_instance_id())
	if _visual_templates.has(key):
		return _visual_templates[key] as Node3D
	# Imported visual scenes are inspected outside the tree. Only static mesh
	# nodes are copied, so animation, particles, cameras and scripts never run.
	var imported_visual: Node = source.instantiate()
	var template: Node3D = Node3D.new()
	_copy_visual_meshes(imported_visual, Transform3D.IDENTITY, true, template)
	imported_visual.free()
	if template.get_child_count() == 0:
		template.free()
		return null
	var bounds: AABB = _get_visual_bounds(template)
	var longest: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if not is_finite(longest) or longest <= 0.0001:
		template.free()
		return null
	var scale_factor: float = clampf(DISPLAY_SPAN / longest, 0.0001, 10000.0)
	template.scale = Vector3.ONE * scale_factor
	template.position = -bounds.get_center() * scale_factor
	_visual_templates[key] = template
	return template

func _copy_visual_meshes(source: Node, parent_transform: Transform3D, inherited_visible: bool, destination: Node3D) -> void:
	var combined: Transform3D = parent_transform
	var shown: bool = inherited_visible
	if source is Node3D:
		var source_3d: Node3D = source as Node3D
		combined = parent_transform * source_3d.transform
		shown = inherited_visible and source_3d.visible
	if source is MeshInstance3D and shown:
		var original: MeshInstance3D = source as MeshInstance3D
		if original.mesh != null:
			var mesh_copy: MeshInstance3D = MeshInstance3D.new()
			mesh_copy.name = "HullMesh%d" % destination.get_child_count()
			mesh_copy.mesh = original.mesh
			mesh_copy.transform = combined
			mesh_copy.material_override = original.material_override
			mesh_copy.material_overlay = original.material_overlay
			mesh_copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh_copy.visibility_range_end = 90.0
			for surface: int in range(original.get_surface_override_material_count()):
				mesh_copy.set_surface_override_material(surface, original.get_surface_override_material(surface))
			destination.add_child(mesh_copy)
	for child: Node in source.get_children():
		_copy_visual_meshes(child, combined, shown, destination)

func _get_visual_bounds(template: Node3D) -> AABB:
	var result: AABB = AABB()
	var initialized: bool = false
	for child: Node in template.get_children():
		var mesh: MeshInstance3D = child as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var transformed: AABB = mesh.transform * mesh.mesh.get_aabb()
		result = result.merge(transformed) if initialized else transformed
		initialized = true
	return result

func _build_pilot_stand_in(bay: Node3D, pilot: PilotDef, palette_index: int) -> void:
	if pilot == null:
		return
	var pilot_root: Node3D = Node3D.new()
	pilot_root.name = "PilotStandIn"
	pilot_root.position = Vector3(-5.8, 0.05, -3.8)
	bay.add_child(pilot_root)
	var suit_colors: Array[Color] = [Color(0.18, 0.3, 0.36), Color(0.36, 0.22, 0.13), Color(0.16, 0.3, 0.27)]
	var suit: StandardMaterial3D = StandardMaterial3D.new()
	suit.albedo_color = suit_colors[palette_index % suit_colors.size()]
	suit.roughness = 0.75
	var body_mesh: CapsuleMesh = CapsuleMesh.new()
	body_mesh.radius = 0.28
	body_mesh.height = 1.0
	body_mesh.radial_segments = 12
	body_mesh.rings = 4
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "Suit"
	body.mesh = body_mesh
	body.material_override = suit
	body.position.y = 1.15
	pilot_root.add_child(body)
	var helmet_mesh: SphereMesh = SphereMesh.new()
	helmet_mesh.radius = 0.27
	helmet_mesh.height = 0.54
	helmet_mesh.radial_segments = 12
	helmet_mesh.rings = 6
	var helmet: MeshInstance3D = MeshInstance3D.new()
	helmet.name = "Helmet"
	helmet.mesh = helmet_mesh
	helmet.material_override = _materials[&"metal"] as StandardMaterial3D
	helmet.position.y = 1.84
	pilot_root.add_child(helmet)
	_make_box(pilot_root, "Visor", Vector3(0, 1.85, -0.25), Vector3(0.34, 0.12, 0.07), _materials[&"cyan"] as StandardMaterial3D)
	_make_box(pilot_root, "LeftBoot", Vector3(-0.16, 0.37, 0), Vector3(0.21, 0.7, 0.3), suit)
	_make_box(pilot_root, "RightBoot", Vector3(0.16, 0.37, 0), Vector3(0.21, 0.7, 0.3), suit)
	var left_arm: MeshInstance3D = _make_box(pilot_root, "LeftArm", Vector3(-0.37, 1.15, 0), Vector3(0.16, 0.75, 0.2), suit)
	left_arm.rotation.z = -0.12
	var right_arm: MeshInstance3D = _make_box(pilot_root, "RightArm", Vector3(0.37, 1.15, 0), Vector3(0.16, 0.75, 0.2), suit)
	right_arm.rotation.z = 0.12

func _refresh_bay_lighting() -> void:
	for bay_id: Variant in _bays:
		var bay: Node3D = _bays[bay_id] as Node3D
		var material: StandardMaterial3D = _materials[&"cyan"] if bay_id == _selected_bay_id else _materials[&"cyan_dim"]
		for marker_name: String in ["FrontGuide", "RearGuide", "ServiceLamp"]:
			var marker: MeshInstance3D = bay.get_node_or_null(marker_name) as MeshInstance3D
			if marker != null:
				marker.material_override = material
		var number: Label3D = bay.get_node_or_null("BayNumber") as Label3D
		if number != null:
			number.modulate = Color(0.6, 0.9, 1.0) if bay_id == _selected_bay_id else Color(0.23, 0.37, 0.42)

func _reset_idle_poses() -> void:
	for bay_value: Variant in _bays.values():
		var bay: Node3D = bay_value as Node3D
		var display: Node3D = bay.get_node_or_null("Display") as Node3D
		if display != null:
			display.position.y = DISPLAY_HEIGHT
			display.rotation.y = -0.16

func _build_materials() -> void:
	_materials[&"metal"] = _make_material(Color(0.08, 0.11, 0.14), 0.65, 0.45)
	_materials[&"deck"] = _make_material(Color(0.035, 0.052, 0.065), 0.4, 0.75)
	_materials[&"dark"] = _make_material(Color(0.014, 0.023, 0.032), 0.3, 0.85)
	_materials[&"cyan"] = _make_material(Color(0.1, 0.65, 0.85), 0.15, 0.4, Color(0.08, 0.5, 0.7), 1.2)
	_materials[&"cyan_dim"] = _make_material(Color(0.045, 0.18, 0.24), 0.15, 0.5, Color(0.02, 0.09, 0.14), 0.5)
	_materials[&"amber"] = _make_material(Color(0.75, 0.4, 0.1), 0.25, 0.6, Color(0.45, 0.18, 0.025), 0.5)

func _make_material(color: Color, metallic: float, roughness: float, emission: Color = Color.BLACK, energy: float = 0.0) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = energy
	return material

func _make_box(parent: Node3D, node_name: String, location: Vector3, dimensions: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var box: MeshInstance3D = MeshInstance3D.new()
	box.name = node_name
	box.mesh = _unit_box
	box.position = location
	box.scale = dimensions
	box.material_override = material
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(box)
	return box
