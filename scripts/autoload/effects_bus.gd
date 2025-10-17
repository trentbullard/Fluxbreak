# effects_bus.gd
extends Node

signal float_text(world_pos: Vector3, text: String, color: Color)

func show_float(world_pos: Vector3, text: String, color: Color) -> void:
	emit_signal("float_text", world_pos, text, color)
