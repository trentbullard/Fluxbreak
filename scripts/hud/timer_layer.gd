# timer_layer.gd (godot 4.5)
extends Control

@onready var label: Label = $Label as Label

func _ready() -> void:
	RunState.time_updated.connect(_on_time_updated)
	RunState.time_over.connect(_on_time_over)
	label.text = "05:00"

func _on_time_updated(remaining: float) -> void:
	var minutes: int = int(remaining) / 60
	var seconds: int = int(remaining) % 60
	label.text = "%02d:%02d" % [minutes, seconds]

func _on_time_over() -> void:
	label.text = "00:00"
