extends TextureRect
class_name EnemyIconPreview

const PREVIEW_SIZE: Vector2i = Vector2i(128, 128)
const FRAME_INTERVAL_SEC: float = 1.0 / 30.0
const ROTATION_SPEED: float = PI / 6.0
const CAMERA_POSITION: Vector3 = Vector3(0.0, 1.9, -4.0)
const FRAME_PADDING: float = 1.08

var _viewport: SubViewport = null
var _model_root: Node3D = null
var _visual: Node3D = null
var _camera: Camera3D = null
var _model_bounds: AABB = AABB()
var _scroll: ScrollContainer = null
var _source_scene: PackedScene = null
var _preview_materials: Dictionary = {}
var _active: bool = false
var _has_model: bool = false
var _frame_elapsed: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	set_process(false)
	_build_stage()
	visibility_changed.connect(_sync_activity)
	resized.connect(_sync_activity)
	set_notify_transform(true)
	var ancestor: Node = get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			_scroll = ancestor as ScrollContainer
			_scroll.get_v_scroll_bar().value_changed.connect(_on_scroll_changed)
			_scroll.get_h_scroll_bar().value_changed.connect(_on_scroll_changed)
			_scroll.resized.connect(_sync_activity)
			break
		ancestor = ancestor.get_parent()
	get_viewport().size_changed.connect(_sync_activity)
	_sync_activity.call_deferred()

## Only copied visual meshes enter this isolated world, never gameplay actors.
func set_model(scene: PackedScene) -> bool:
	if scene == null or _visual == null:
		return false
	if _has_model and _source_scene == scene:
		_sync_activity()
		return true
	_has_model = false
	_sync_activity()
	for child: Node in _visual.get_children():
		child.free()
	_preview_materials.clear()
	var source: Node = scene.instantiate()
	_copy_meshes(source, Transform3D.IDENTITY, true)
	source.free()
	if _visual.get_child_count() == 0:
		return false
	var bounds: AABB = AABB()
	var first: bool = true
	for child: Node in _visual.get_children():
		var mesh: MeshInstance3D = child as MeshInstance3D
		var box: AABB = mesh.transform * mesh.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var longest: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if not is_finite(longest) or longest <= 0.0001:
		return false
	var scale_factor: float = 2.0 / longest
	_visual.scale = Vector3.ONE * scale_factor
	_visual.position = -bounds.get_center() * scale_factor
	_model_root.rotation.y = -PI / 6.0
	_model_bounds = AABB(-bounds.size * scale_factor * 0.5, bounds.size * scale_factor)
	_frame_model()
	_source_scene = scene
	_has_model = true
	_sync_activity()
	return true

func get_viewport_3d() -> SubViewport:
	return _viewport

func get_model_root() -> Node3D:
	return _model_root

func get_model_bounds() -> AABB:
	return _model_bounds

func get_camera_3d() -> Camera3D:
	return _camera

func is_active() -> bool:
	return _active

func _build_stage() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "ModelViewport"
	_viewport.size = PREVIEW_SIZE
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.physics_object_picking = false
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	texture = _viewport.get_texture()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.82, 1.0)
	environment.ambient_light_energy = 0.8
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)
	_model_root = Node3D.new()
	_model_root.name = "Turntable"
	_viewport.add_child(_model_root)
	_visual = Node3D.new()
	_visual.name = "CenteredModel"
	_model_root.add_child(_visual)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35.0, 150.0, 0.0)
	key.light_color = Color(0.9, 0.95, 1.0)
	key.light_energy = 1.5
	key.shadow_enabled = false
	_viewport.add_child(key)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(20.0, -30.0, 0.0)
	fill.light_color = Color(0.4, 0.7, 1.0)
	fill.light_energy = 0.7
	fill.shadow_enabled = false
	_viewport.add_child(fill)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 2.8
	_camera.near = 0.1
	_camera.far = 10.0
	_camera.position = CAMERA_POSITION
	_viewport.add_child(_camera)
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_camera.make_current()

## Fit the complete yaw envelope once, so every model stays framed while turning.
func _frame_model() -> void:
	var half: Vector3 = _model_bounds.size * 0.5
	var horizontal_radius: float = Vector2(half.x, half.z).length()
	var elevation: float = atan2(CAMERA_POSITION.y, absf(CAMERA_POSITION.z))
	var vertical_radius: float = half.y * cos(elevation) + horizontal_radius * sin(elevation)
	_camera.size = maxf(2.8, maxf(horizontal_radius, vertical_radius) * 2.0 * FRAME_PADDING)

func _copy_meshes(source: Node, parent_transform: Transform3D, inherited_visible: bool) -> void:
	var combined: Transform3D = parent_transform
	var shown: bool = inherited_visible
	if source is Node3D:
		var spatial: Node3D = source as Node3D
		combined = parent_transform * spatial.transform
		shown = shown and spatial.visible
	if shown and source is MeshInstance3D:
		var original: MeshInstance3D = source as MeshInstance3D
		if original.mesh != null:
			var mesh: MeshInstance3D = MeshInstance3D.new()
			mesh.mesh = original.mesh
			mesh.transform = combined
			mesh.material_override = _preview_material(original.material_override)
			mesh.material_overlay = _preview_material(original.material_overlay)
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for surface: int in original.get_surface_override_material_count():
				mesh.set_surface_override_material(surface, _preview_material(original.get_active_material(surface)))
			_visual.add_child(mesh)
	for child: Node in source.get_children():
		_copy_meshes(child, combined, shown)

func _preview_material(material: Material) -> Material:
	var standard: BaseMaterial3D = material as BaseMaterial3D
	if standard == null or not standard.subsurf_scatter_enabled:
		return material
	var key: int = material.get_instance_id()
	if not _preview_materials.has(key):
		# Transparent viewports do not support SSS. Leave gameplay assets intact.
		var copy: BaseMaterial3D = standard.duplicate() as BaseMaterial3D
		copy.subsurf_scatter_enabled = false
		_preview_materials[key] = copy
	return _preview_materials[key] as Material

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_inside_tree():
		_sync_activity()

func _on_scroll_changed(_value: float) -> void:
	_sync_activity()

func _sync_activity() -> void:
	if _viewport == null:
		return
	var active: bool = _has_model and is_visible_in_tree() and get_global_rect().has_area()
	if active:
		active = get_global_rect().intersects(get_viewport_rect())
	if active and _scroll != null:
		active = get_global_rect().intersects(_scroll.get_global_rect())
	if active == _active:
		return
	_active = active
	_frame_elapsed = 0.0
	set_process(active)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if active else SubViewport.UPDATE_DISABLED

func _process(delta: float) -> void:
	_frame_elapsed += minf(delta, 0.1)
	if _frame_elapsed < FRAME_INTERVAL_SEC:
		return
	_model_root.rotate_y(ROTATION_SPEED * _frame_elapsed)
	_frame_elapsed = 0.0
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
