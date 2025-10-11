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

#@onready var _ship: Node3D = get_node_or_null(ship_path)
#@onready var _label: Label3D = $Nameplate

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
	#if _label:
		#_label.global_position = global_position + Vector3.UP * label_height
	
	_accum += delta
	var interval: float = 1.0 / max(label_update_hz, 1.0)
	if _accum >= interval:
		#_update_billboard()
		_accum = 0.0

#func _update_billboard() -> void:
	#if _label == null or _ship == null:
		#if _label:
			#_label.visible = false
		#return
	#
	#var d := global_position.distance_to(_ship.global_position)
	#var should_show := d <= show_within_meters and hp > 0.0
	#
	#_label.visible = should_show
	#if should_show:
		#var dist_int := int(round(d))
		#var hp_int := int(round(max(hp, 0.0)))
		#_label.text = "%dm  •  HP: %d" % [dist_int, hp_int]

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
