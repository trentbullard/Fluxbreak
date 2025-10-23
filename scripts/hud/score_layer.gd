# score_layer.gd
extends Control

@onready var label: Label = $Score as Label

func _ready() -> void:
	label.text = "Score: 0"
	RunState.score_changed.connect(_on_score_changed)

func _on_score_changed(total: int, _delta: int, _reason: String) -> void:
	label.text = "Score: %d" % total
	# tiny pop animation so the player notices increases
	var t: Tween = create_tween()
	t.tween_property(label, "scale", Vector2(1.15, 1.15), 0.08)
	t.tween_property(label, "scale", Vector2(1.0, 1.0), 0.12)
