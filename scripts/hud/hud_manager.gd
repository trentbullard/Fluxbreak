# hud_manager.gd (Godot 4.5)
extends CanvasLayer

@export var camera_path: NodePath    # optional; leave empty to auto-detect
@export var ship_path: NodePath

@onready var ship: Node3D = get_node_or_null(ship_path)
@onready var nameplates: NameplateManager = $ScreenRoot/NameplateLayer
@onready var effects: FloatingTextLayer = $ScreenRoot/EffectsLayer
@onready var ship_hud: ShipHud = $ScreenRoot/BottomDock/Centerer/ShipHud

var camera: Camera3D

func _ready() -> void:
	_refresh_camera()
	# In case camera becomes current a frame later:
	await get_tree().process_frame
	_refresh_camera()

	if nameplates and camera and ship:
		nameplates.init(camera, ship)
	if ship_hud and ship:
		ship_hud.init(ship)
	if effects and camera:
		effects.init(camera)

func _process(_dt: float) -> void:
	# If the camera changes (e.g., switch to cockpit or different scene), refresh
	if camera == null or not is_instance_valid(camera) or not camera.current:
		_refresh_camera()

func _refresh_camera() -> void:
	if camera_path != NodePath(""):
		camera = get_node_or_null(camera_path) as Camera3D
	else:
		camera = get_viewport().get_camera_3d()
