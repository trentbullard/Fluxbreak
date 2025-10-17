# explosion.gd  (Godot 4.5)
extends CPUParticles3D

@export var auto_free: bool = true
@export var max_radius: float = 12.0   # how large the burst can get

func _ready() -> void:
	# Make sure renderer considers the whole burst's bounds.
	visibility_aabb = AABB(
		Vector3(-max_radius, -max_radius, -max_radius),
		Vector3(max_radius * 2.0, max_radius * 2.0, max_radius * 2.0)
	)

	# start immediately
	restart()
	emitting = true

	if auto_free:
		if one_shot:
			finished.connect(queue_free)
		else:
			# fallback if One Shot ever gets turned off in the editor
			get_tree().create_timer(lifetime + preprocess + 0.1).timeout.connect(queue_free)
