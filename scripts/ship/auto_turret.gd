extends Node3D

@export var projectile_scene: PackedScene
@export var fire_rate: float = 0.5			# seconds between shots
@export var detection_radius: float = 200.0	# should match Detector sphere radius
@export var lead_fraction: float = 0.0		# 0 for now; can add leading later

@onready var detector: Area3D   = $Detector
@onready var muzzle: Marker3D   = $Muzzle

var _cooldown := 0.0
var _targets: Array[Node3D] = []

func _ready() -> void:
	# Ensure detector radius matches range
	var cs := detector.get_node("CollisionShape3D") as CollisionShape3D
	var sphere := cs.shape as SphereShape3D
	if sphere:
		sphere.radius = detection_radius

	# Track bodies entering/leaving
	detector.body_entered.connect(_on_body_entered)
	detector.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if body is Node3D and body.is_in_group("targets"):
		_targets.append(body)

func _on_body_exited(body: Node) -> void:
	_targets.erase(body)

func _physics_process(delta: float) -> void:
	# Trim freed/null targets
	for i in range(_targets.size() - 1, -1, -1):
		if _targets[i] == null or not is_instance_valid(_targets[i]):
			_targets.remove_at(i)

	_cooldown -= delta
	if _cooldown > 0.0:
		return

	var target := _pick_nearest()
	if target == null:
		return

	_fire_at(target)
	_cooldown = fire_rate

func _pick_nearest() -> Node3D:
	var best: Node3D = null
	var best_d2 := INF
	for t in _targets:
		var d2 := global_position.distance_squared_to(t.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = t
	return best

func _fire_at(target: Node3D) -> void:
	if projectile_scene == null:
		return

	# Aim from muzzle toward target (no leading yet)
	var dir := (target.global_position - muzzle.global_position).normalized()
	var aim_basis := Basis.looking_at(dir, Vector3.UP)

	var p = projectile_scene.instantiate() as Area3D
	get_tree().current_scene.add_child(p)
	p.global_transform = Transform3D(aim_basis, muzzle.global_position)
