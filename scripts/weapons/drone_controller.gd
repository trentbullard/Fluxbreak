extends Node3D
class_name DroneController

const STATE_DOCKED: int = 0
const STATE_ACTIVE: int = 1
const STATE_ATTACKING: int = 2
const STATE_RETURNING: int = 3

signal state_reported(origin_bay_id: int, slot_index: int, next_state: int)

var origin_bay_id: int = -1
var slot_index: int = -1
var _target_ref: WeakRef = weakref(null)
var _anchor_ref: WeakRef = weakref(null)
var _drone_weapon: WeaponDef = null
var _flight_state: int = STATE_DOCKED
var _velocity: Vector3 = Vector3.ZERO
var _swarm_clock: float = 0.0
var _slot_phase: float = 0.0
var _trail_particles: GPUParticles3D = null
var _trail_process: ParticleProcessMaterial = null
var _trail_dir: Vector3 = Vector3.BACK
var _swarm_radius_scale: float = 1.0
var _swarm_height_scale: float = 1.0
var _swarm_speed_scale: float = 1.0
var _attack_radius_scale: float = 1.0
var _attack_speed_scale: float = 1.0
var _jitter_phase_a: float = 0.0
var _jitter_phase_b: float = 0.0
var _jitter_phase_c: float = 0.0
var _shot_cooldown: float = 0.0
var _muzzles: Array[Marker3D] = []
var _muzzle_cursor: int = 0
var _anchor_prev_position: Vector3 = Vector3.ZERO
var _anchor_velocity: Vector3 = Vector3.ZERO
var _has_anchor_sample: bool = false

const ACTIVE_SPEED: float = 110.0
const ACTIVE_ACCEL: float = 800.0
const ATTACK_SPEED: float = 165.0
const ATTACK_ACCEL: float = 700.0
const RETURN_SPEED: float = 220.0
const RETURN_ACCEL: float = 900.0
const SWARM_RADIUS_BASE: float = 4.0
const SWARM_RADIUS_STEP: float = 1.15
const SWARM_HEIGHT: float = 0.85
const SWARM_ANGULAR_SPEED: float = 2.6
const ATTACK_ORBIT_RADIUS: float = 2.1
const ATTACK_ANGULAR_SPEED: float = 7.0
const TRAIL_LENGTH: float = 2.0
const TRAIL_WIDTH: float = 0.05
const TRAIL_MIN_LIFETIME: float = 0.03
const TRAIL_MAX_LIFETIME: float = 0.22

func _ready() -> void:
	_cache_muzzles()

func configure_drone(origin_bay_id_value: int, slot_index_value: int, anchor: Node3D = null, drone_weapon: WeaponDef = null) -> void:
	origin_bay_id = origin_bay_id_value
	slot_index = slot_index_value
	_anchor_ref = weakref(anchor) if anchor != null else weakref(null)
	_drone_weapon = drone_weapon
	_has_anchor_sample = false
	_anchor_velocity = Vector3.ZERO
	_seed_swarm_jitter()

func set_weapon_profile(drone_weapon: WeaponDef) -> void:
	_drone_weapon = drone_weapon

func _seed_swarm_jitter() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var bay_bits: int = int(origin_bay_id) & 0x7fffffff
	var slot_bits: int = int(slot_index) & 0x7fffffff
	var seed_value: int = bay_bits * 73856093 + slot_bits * 19349663 + 83492791
	rng.seed = int(seed_value & 0x7fffffff)

	_slot_phase = float(slot_index) * 0.917 + rng.randf_range(0.0, TAU)
	_swarm_radius_scale = rng.randf_range(0.82, 1.28)
	_swarm_height_scale = rng.randf_range(0.72, 1.45)
	_swarm_speed_scale = rng.randf_range(0.86, 1.22)
	_attack_radius_scale = rng.randf_range(0.85, 1.35)
	_attack_speed_scale = rng.randf_range(0.9, 1.25)
	_jitter_phase_a = rng.randf_range(0.0, TAU)
	_jitter_phase_b = rng.randf_range(0.0, TAU)
	_jitter_phase_c = rng.randf_range(0.0, TAU)

func command_launch(target: Node3D) -> void:
	_flight_state = STATE_ACTIVE
	_shot_cooldown = 0.0
	command_set_target(target)
	_report_state(STATE_ACTIVE)

func command_attack(target: Node3D) -> void:
	command_set_target(target)
	if target == null:
		_flight_state = STATE_ACTIVE
		_report_state(STATE_ACTIVE)
		return
	_flight_state = STATE_ATTACKING
	_report_state(STATE_ATTACKING)

func command_idle() -> void:
	_flight_state = STATE_ACTIVE
	command_set_target(null)
	_report_state(STATE_ACTIVE)

func command_set_target(target: Node3D) -> void:
	_target_ref = weakref(target) if target != null else weakref(null)

func command_begin_return() -> void:
	_flight_state = STATE_RETURNING
	command_set_target(null)
	_report_state(STATE_RETURNING)

func command_dock() -> void:
	_flight_state = STATE_DOCKED
	_velocity = Vector3.ZERO
	_shot_cooldown = 0.0
	command_set_target(null)
	_report_state(STATE_DOCKED)
	if is_inside_tree():
		call_deferred("queue_free")
	else:
		queue_free()

func get_target() -> Node3D:
	return _target_ref.get_ref() as Node3D if _target_ref != null else null

func _physics_process(delta: float) -> void:
	if _flight_state == STATE_DOCKED:
		return
	var anchor: Node3D = _get_anchor()
	if anchor == null:
		return

	_swarm_clock += delta
	_shot_cooldown = max(0.0, _shot_cooldown - delta)
	_update_anchor_velocity(anchor, delta)

	match _flight_state:
		STATE_ACTIVE:
			var swarm_point: Vector3 = _compute_anchor_swarm_point(anchor)
			_move_toward_world_point(swarm_point, ACTIVE_SPEED, ACTIVE_ACCEL, delta, _anchor_velocity)
		STATE_ATTACKING:
			var target: Node3D = get_target()
			if target == null or not is_instance_valid(target):
				_flight_state = STATE_ACTIVE
				_report_state(STATE_ACTIVE)
				return
			var attack_point: Vector3 = _compute_target_attack_point(target)
			_move_toward_world_point(attack_point, ATTACK_SPEED, ATTACK_ACCEL, delta)
			_tick_attack_fire(target)
		STATE_RETURNING:
			var return_point: Vector3 = anchor.global_position
			_move_toward_world_point(return_point, RETURN_SPEED, RETURN_ACCEL, delta, _anchor_velocity)

func _get_anchor() -> Node3D:
	return _anchor_ref.get_ref() as Node3D if _anchor_ref != null else null

func _compute_anchor_swarm_point(anchor: Node3D) -> Vector3:
	var base_radius: float = SWARM_RADIUS_BASE + SWARM_RADIUS_STEP * float(max(0, slot_index))
	var wobble_t: float = _swarm_clock * (2.1 * _swarm_speed_scale) + _jitter_phase_b
	var radius_wobble: float = 1.0 + 0.2 * sin(wobble_t)
	var radius: float = base_radius * _swarm_radius_scale * radius_wobble
	var angle: float = _swarm_clock * SWARM_ANGULAR_SPEED * _swarm_speed_scale + _slot_phase + _jitter_phase_a
	var vertical_amp: float = SWARM_HEIGHT * _swarm_height_scale
	var drift: Vector3 = Vector3(
		sin(_swarm_clock * 1.7 + _jitter_phase_c),
		0.0,
		cos(_swarm_clock * 1.9 + _jitter_phase_b)
	) * 0.35
	var local_offset: Vector3 = Vector3(
		cos(angle) * radius,
		sin(angle * 1.6 + _slot_phase + _jitter_phase_c) * vertical_amp,
		sin(angle) * radius
	) + drift
	return anchor.global_position + anchor.global_transform.basis * local_offset

func _compute_target_attack_point(target: Node3D) -> Vector3:
	var orbit_radius: float = ATTACK_ORBIT_RADIUS * _attack_radius_scale
	var angle: float = _swarm_clock * ATTACK_ANGULAR_SPEED * _attack_speed_scale + _slot_phase + _jitter_phase_b
	var local_offset: Vector3 = Vector3(
		cos(angle) * orbit_radius,
		sin(angle * 2.0 + _slot_phase + _jitter_phase_c) * (SWARM_HEIGHT * 0.45 * _swarm_height_scale),
		sin(angle) * orbit_radius
	)
	return target.global_position + local_offset

func _update_anchor_velocity(anchor: Node3D, delta: float) -> void:
	if anchor == null or delta <= 0.000001:
		return
	var pos: Vector3 = anchor.global_position
	if not _has_anchor_sample:
		_anchor_prev_position = pos
		_anchor_velocity = Vector3.ZERO
		_has_anchor_sample = true
		return

	var raw_velocity: Vector3 = (pos - _anchor_prev_position) / delta
	_anchor_prev_position = pos
	var smooth_t: float = clamp(12.0 * delta, 0.0, 1.0)
	_anchor_velocity = _anchor_velocity.lerp(raw_velocity, smooth_t)

func _move_toward_world_point(world_point: Vector3, max_speed: float, accel: float, delta: float, base_velocity: Vector3 = Vector3.ZERO) -> void:
	var to_goal: Vector3 = world_point - global_position
	var dist: float = to_goal.length()
	var desired_vel: Vector3 = base_velocity
	if dist > 0.001:
		var target_speed: float = min(max_speed, dist * 8.0)
		desired_vel += to_goal / dist * target_speed

	_velocity = _velocity.move_toward(desired_vel, accel * delta)
	global_position += _velocity * delta

func _tick_attack_fire(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	if _drone_weapon == null:
		return
	if _shot_cooldown > 0.0:
		return

	var next_interval: float = max(0.01, _drone_weapon.fire_rate)
	_shot_cooldown = next_interval

	var dmg_min: float = minf(_drone_weapon.damage_min, _drone_weapon.damage_max)
	var dmg_max: float = maxf(_drone_weapon.damage_min, _drone_weapon.damage_max)
	var dmg: float = randf_range(dmg_min, dmg_max)
	if dmg > 0.0 and target.has_method("apply_damage"):
		target.call("apply_damage", dmg)

	_fire_projectile_visual(target)

func _fire_projectile_visual(target: Node3D) -> void:
	if _drone_weapon == null or _drone_weapon.projectile_scene == null:
		return
	var p: Projectile = _drone_weapon.projectile_scene.instantiate() as Projectile
	if p == null:
		return

	var muzzle_xf: Transform3D = _get_next_muzzle_transform()
	var dir: Vector3 = target.global_position - muzzle_xf.origin
	if dir.length_squared() < 0.000001:
		dir = -global_transform.basis.z
	else:
		dir = dir.normalized()
	p.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), muzzle_xf.origin)

	var root: Node = get_tree().current_scene
	if root == null:
		root = self
	root.add_child(p)

func _cache_muzzles() -> void:
	_muzzles.clear()
	for path: String in ["WeaponRMuzzle", "WeaponLMuzzle", "Muzzle"]:
		var m: Marker3D = get_node_or_null(path) as Marker3D
		if m != null:
			_muzzles.append(m)

func _get_next_muzzle_transform() -> Transform3D:
	if _muzzles.is_empty():
		return global_transform
	var m: Marker3D = _muzzles[_muzzle_cursor % _muzzles.size()]
	_muzzle_cursor += 1
	return m.global_transform

func _report_state(next_state: int) -> void:
	state_reported.emit(origin_bay_id, slot_index, next_state)
