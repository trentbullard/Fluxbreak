# flux_anchors_container.gd (Godot 4.5)
# Displays the player's persistent Flux Anchor balance in the main menu.
extends Control

@onready var label: Label = $Label as Label

func _ready() -> void:
	_update_label(GameFlow.flux_anchors)
	GameFlow.flux_anchors_updated.connect(_on_flux_anchors_updated)

func _on_flux_anchors_updated(new_value: int, _old_value: int) -> void:
	_update_label(new_value)

func _update_label(value: int) -> void:
	label.text = "Flux Anchors: %d" % [value]
