# auto_turret.gd  (Godot 4.5)
extends Node3D

@export var projectile_scene: PackedScene
@export var fire_rate: float = 0.5                 # seconds between shots
@export var detection_radius: float = 200.0        # should match Detector sphere radius

@export var base_accuracy: float = 0.75            # turret's baseline 0..1
@export var systems_bonus: float = 0.10            # upgrades add here
@export var accuracy_range_falloff: float = 0.50   # at max range, lose this fraction

@export var prox_radius_at_perfect: float = 3.0    # generous full-hit window
@export var prox_radius_at_miss: float = 0.0       # hard miss -> no fuse
@export var graze_radius_at_perfect: float = 1.25

@export var crit_chance: float = 0.15       # given a hit
@export var graze_on_hit: float = 0.10      # of the remaining non-crits
@export var graze_on_miss: float = 0.05     # chance to graze when missed
@export var graze_mult: float = 0.35        # 35% damage on graze
@export var crit_mult: float = 1.5          # damage multiplier on critical

@onready var shot_sound: AudioStreamPlayer3D = $ShotSound
@onready var detector: Area3D   = $Detector
@onready var muzzle: Marker3D   = $Muzzle

var _cooldown := 0.0
var _targets: Array[Node3D] = []

enum ShotResult { MISS, GRAZE, HIT, CRIT }

func _ready() -> void:
	# Ensure detector radius matches range
	var cs: CollisionShape3D = detector.get_node("CollisionShape3D") as CollisionShape3D
	var sphere: SphereShape3D = cs.shape as SphereShape3D
	if sphere != null:
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

	var target: Node3D = _pick_nearest()
	if target == null:
		return

	_fire_at_with_roll(target)
	_cooldown = fire_rate

func _pick_nearest() -> Node3D:
	var best: Node3D = null
	var best_d2: float = INF
	for t in _targets:
		var d2: float = global_position.distance_squared_to(t.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = t
	return best

func _effective_accuracy_vs(target: Node3D) -> float:
	var ev: float = 0.0
	if target is Enemy:
		ev = (target as Enemy).get_evasion()
	
	var dist: float = global_position.distance_to(target.global_position)
	var range_factor: float = clamp(dist / detection_radius, 0.0, 1.0) # 0 close -> 1 far
	var acc_base: float = clamp(base_accuracy + systems_bonus, 0.0, 1.0)
	var acc_range_scaled: float = acc_base * lerp(1.0, 1.0 - accuracy_range_falloff, range_factor)
	
	var net: float = clamp(acc_range_scaled - ev, 0.0, 1.0)
	return net

func _fire_at_with_roll(target: Node3D) -> void:
	if projectile_scene == null:
		return

	# Aim (still straight) -- projectile will use proximity fuse to "connect"
	var dir: Vector3 = (target.global_position - muzzle.global_position).normalized()
	var aim_basis: Basis = Basis.looking_at(dir, Vector3.UP)
	
	var hit_chance: float = _effective_accuracy_vs(target)
	var outcome: int = resolve_shot(hit_chance)

	var p: Projectile = projectile_scene.instantiate() as Projectile
	if p == null:
		return

	p.global_transform = Transform3D(aim_basis, muzzle.global_position)
	p.configure_with_outcome(get_parent(), target, outcome, graze_mult, crit_mult)
	get_tree().current_scene.add_child(p)

	if shot_sound != null:
		shot_sound.pitch_scale = randf_range(0.90, 1.10)
		shot_sound.play()

func resolve_shot(hit_chance: float) -> int:
	var hc: float = clamp(hit_chance, 0.0, 1.0)
	var cc: float = clamp(crit_chance, 0.0, 1.0)
	var gh: float = clamp(graze_on_hit, 0.0, 1.0)
	var gm: float = clamp(graze_on_miss, 0.0, 1.0)

	# If it hits at all…
	var r1: float = randf()
	if r1 <= hc:
		# Crit → Graze-on-hit → Normal
		var r2: float = randf()
		if r2 <= cc:
			return ShotResult.CRIT
		elif r2 <= cc + max(0.0, 1.0 - cc) * gh:
			return ShotResult.GRAZE
		else:
			return ShotResult.HIT
	else:
		# Miss → maybe graze-on-miss
		var r3: float = randf()
		if r3 <= gm:
			return ShotResult.GRAZE
		return ShotResult.MISS
