# floating_text.gd (Godot 4.5)
extends Control
class_name FloatingText

@export var lifetime: float = 0.9
@export var rise_pixels: float = 30.0
@export var pixel_offset_up: float = 75

@onready var _label: Label = $Label

var _camera: Camera3D
var _world_pos: Vector3
var _age: float = 0.0

func start(camera: Camera3D, world_pos: Vector3, text: String, color: Color) -> void:
	_camera = camera
	_world_pos = world_pos
	_label.text = text
	_label.modulate = color
	# first position
	var sp: Vector2 = _camera.unproject_position(_world_pos)
	position = sp - (size * 0.5) - Vector2(0.0, pixel_offset_up)

func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	
	var t: float = clamp(_age / lifetime, 0.0, 1.0)
	
	# follow world pos (so if target moves, text follows during its short life)
	var sp: Vector2 = _camera.unproject_position(_world_pos)
	sp.y -= rise_pixels * t
	position = sp - (size * 0.5) - Vector2(0.0, pixel_offset_up)
	
	# fade out
	modulate.a = 1.0 - t
