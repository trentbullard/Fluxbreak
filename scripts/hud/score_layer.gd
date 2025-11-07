# score_layer.gd
extends Control

@onready var score_label: Label = $VBoxContainer/Score as Label
@onready var nanobot_label: Label = $VBoxContainer/Nanobots as Label

func _ready() -> void:
	score_label.text = "Score: 0"
	nanobot_label.text = "Nanobots: 0"
	RunState.score_changed.connect(_on_score_changed)
	RunState.nanobots_updated.connect(_on_nanobots_updated)

func _on_score_changed(total: int, _delta: int, _reason: String) -> void:
	score_label.text = "Score: %d" % total
	# tiny pop animation so the player notices increases
	var t: Tween = create_tween()
	t.tween_property(score_label, "scale", Vector2(1.15, 1.15), 0.08)
	t.tween_property(score_label, "scale", Vector2(1.0, 1.0), 0.12)

func _on_nanobots_updated(amount: int) -> void:
	nanobot_label.text = "Nanobots: %d" % amount
	var t: Tween = create_tween()
	t.tween_property(nanobot_label, "scale", Vector2(1.15, 1.15), 0.08)
	t.tween_property(nanobot_label, "scale", Vector2(1.0, 1.0), 0.12)
