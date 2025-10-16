extends CharacterBody3D

@export var speed := 12.0

func _physics_process(delta):
	var dir := Vector3.ZERO
	dir.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	dir.z = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	if dir.length() > 0.0:
		dir = dir.normalized()
	velocity = dir * speed
	move_and_slide()
