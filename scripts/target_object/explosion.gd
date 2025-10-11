extends GPUParticles3D
@export var auto_free := true

func _ready() -> void:
	restart()
	emitting = true
	if auto_free:
		if one_shot:
			finished.connect(queue_free)
		else:
			# fallback if you ever turn off One Shot
			get_tree().create_timer(lifetime + preprocess + 0.1).timeout.connect(queue_free)
