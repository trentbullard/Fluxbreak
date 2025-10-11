# hud_manager.gd  (Godot 4.5)
extends CanvasLayer
@export var camera_path: NodePath
@export var ship_path: NodePath

@onready var camera: Camera3D = get_node_or_null(camera_path)
@onready var ship: Node3D = get_node_or_null(ship_path)
@onready var nameplates: NameplateManager = $ScreenRoot/NameplateLayer
@onready var ship_hud: ShipHud = $ScreenRoot/BottomDock/Centerer/ShipHud

func _ready() -> void:
	if nameplates: nameplates.init(camera, ship)
	if ship_hud: ship_hud.init(ship)
