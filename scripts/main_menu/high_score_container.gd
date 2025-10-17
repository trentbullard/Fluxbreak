# high_score_container.gd (godot 4.5)
extends Control

@onready var label: Label = $Label as Label

func _ready() -> void:
	_update_label(GameFlow.high_score)
	GameFlow.high_score_updated.connect(_on_high_score_updated)

func _on_high_score_updated(new_score: int, _old_score: int) -> void:
	_update_label(new_score)

func _update_label(value: int) -> void:
	label.text = "High Score: %d" % [value]
