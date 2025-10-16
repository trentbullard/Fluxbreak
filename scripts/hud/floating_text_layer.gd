# floating_text_layer.gd (Godot 4.5)
extends Control
class_name FloatingTextLayer

@export var floating_text_scene: PackedScene

var _camera: Camera3D

func init(cam: Camera3D) -> void:
	_camera = cam

func _ready() -> void:
	EffectsBus.float_text.connect(_on_float_text)

func _on_float_text(world_pos: Vector3, text: String, color: Color) -> void:
	if _camera == null:
		return
	# skip if behind camera (optional)
	if _camera.is_position_behind(world_pos):
		return

	var ft: FloatingText = floating_text_scene.instantiate() as FloatingText
	add_child(ft)
	ft.start(_camera, world_pos, text, color)
