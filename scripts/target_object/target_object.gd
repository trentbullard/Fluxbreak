# target_object.gd  (Godot 4.5)
extends RigidBody3D
@export var hp: float = 20.0
@export var drift_speed: float = 0.0
@export var spin_speed: float = 0.0
@export var start_frozen: bool = true
@export var explosion_scene: PackedScene

@export var ship_path: NodePath
@export var show_within_meters: float = 200.0
@export var label_height: float = 1.5
@export var label_update_hz: float = 10.0

var _accum := 0.0

func _ready() -> void:
	add_to_group("targets")
	if start_frozen:
		freeze = true
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	randomize()
	apply_impulse(Vector3.ZERO, Vector3(
		randf_range(-1,1),
		randf_range(-1,1),
		randf_range(-1,1)
	).normalized() * drift_speed)
	angular_velocity = Vector3(randf(), randf(), randf()) * spin_speed

func _process(delta: float) -> void:
	_accum += delta
	var interval: float = 1.0 / max(label_update_hz, 1.0)
	if _accum >= interval:
		_accum = 0.0

func apply_damage(amount: float) -> void:
	hp -= amount
	if hp <= 0:
		_die()

func _die() -> void:
	if explosion_scene:
		var fx: GPUParticles3D = explosion_scene.instantiate()
		fx.global_transform = global_transform
		get_tree().current_scene.add_child(fx)

	$CollisionShape3D.disabled = true
	hide()
	queue_free()
