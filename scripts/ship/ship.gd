# scripts/ship/ship.gd  (Godot 4.5)
extends RigidBody3D
class_name Ship

@export var loadout: ShipLoadoutDef
@export var ship_override: ShipDef
@export var pilot_override: PilotDef

@export var explosion_scene: PackedScene
@export var return_to_menu_delay: float = 3.0

@export var max_hull: float = 100.0
@export var overheal: float = 0.0
@export var max_shield: float = 100.0
@export var shield_regen: float = 5.0
@export var base_evasion: float = 0.1

@export var max_speed_forward: float = 400.0 # hard cap on forward speed
@export var max_speed_reverse: float = 60.0  # hard cap on reverse speed
@export var drag: float = 0.01         # higher is faster slowdown
@export var accel_forward: float = 100.0     # the amount of acceleration being applied by thrust
@export var accel_reverse: float = 60.0      # see above
@export var boost_mult: float = 1.5          # multiplies accel
@export_enum("Combine", "Replace") var rigidbody_linear_damp_mode: int = RigidBody3D.DAMP_MODE_REPLACE
@export var rigidbody_linear_damp: float = 0.0
@export_enum("Combine", "Replace") var rigidbody_angular_damp_mode: int = RigidBody3D.DAMP_MODE_REPLACE
@export var rigidbody_angular_damp: float = 0.0

# Translation assist tuning (base handling before upgrades)
@export_range(0.0, 1.0, 0.01) var base_spaciness: float = 0.35  # 0=tight arcade, 1=floaty/newtonian
@export var coast_brake_accel: float = 120.0
@export var lateral_brake_accel: float = 90.0
@export var vertical_brake_accel: float = 90.0
@export var turn_assist_brake_bonus: float = 140.0
@export var no_throttle_turn_assist_bonus: float = 60.0
@export var counter_thrust_brake_mult: float = 1.35
@export var thrust_drag_scale: float = 0.2
@export var coast_drag_scale: float = 1.0
@export var forward_drag_scale_throttle: float = 0.0
@export var forward_drag_scale_coast: float = 0.35

# Default pilot forward-load tolerance fallback (used if no pilot is assigned).
@export var default_forward_g_tolerance: float = 6.0
@export var default_forward_g_hard_limit: float = 10.0
@export_range(0.0, 1.0, 0.01) var default_forward_accel_min_scale: float = 0.35
@export_range(0.0, 1.0, 0.01) var default_forward_speed_min_scale: float = 0.55
@export var default_forward_g_from_ang_rate: float = 3.0
@export var default_forward_g_from_ang_accel: float = 3.0
@export var default_forward_g_smoothing_hz: float = 8.0

@export var pickup_range: float = 40.0
@export var nanobot_gain_mult: float = 1.0
@export var score_gain_mult: float = 1.0
@export var hull_repair_cost: int = 500
@export var hull_repair_amount: float = 50.0
@export var hull_repair_cooldown: float = 5.0

@export var max_ang_rate := Vector3( # caps the rate the *ship* can actually reach
	deg_to_rad(120.0),  # pitch
	deg_to_rad(120.0),  # yaw
	deg_to_rad(120.0))  # roll

@export var angular_accel := Vector3(
	deg_to_rad(500.0),  # how fast you ramp toward target rate
	deg_to_rad(500.0),
	deg_to_rad(500.0))

@onready var visual_root: Node3D = $VisualRoot
@onready var camera_rig = $CameraPivot/CameraRig
@onready var hardpoint_manager: TurretHardpointManager = $TurretController/HardpointManager
@onready var stat_aggregator: StatAggregator = $StatAggregator
const Stat = StatTypes.Stat
@onready var shield_hit_audio: AudioStreamPlayer3D = $Audio/ShieldHitAudio
@onready var hull_hit_audio: AudioStreamPlayer3D = $Audio/HullHitAudio
@onready var shield_low_alarm_audio: AudioStreamPlayer3D = $Audio/ShieldLowAlarm
@onready var hull_low_alarm_audio: AudioStreamPlayer3D = $Audio/HullLowAlarm
const LOW_ALARM_THRESHOLD: float = 0.2
var _current_alarm: AudioStreamPlayer3D = null

# --- cached effective stats ---
var eff_max_hull: float
var eff_max_shield: float
var eff_shield_regen: float
var eff_evasion: float
var eff_damage_taken_mult: float
var eff_max_speed_forward: float
var eff_max_speed_reverse: float
var eff_accel_forward: float
var eff_accel_reverse: float
var eff_boost_mult: float
var eff_drag: float
var eff_max_ang_rate: Vector3
var eff_angular_accel: Vector3
var eff_pickup_range: float
var eff_nanobot_gain_mult: float
var eff_score_gain_mult: float
var eff_pilot_g_tolerance: float
var eff_pilot_g_hard_limit: float
var eff_pilot_forward_accel_min_scale: float
var eff_pilot_forward_speed_min_scale: float
var eff_pilot_forward_g_from_ang_rate: float
var eff_pilot_forward_g_from_ang_accel: float
var eff_pilot_forward_g_smoothing_hz: float
var eff_pilot_perception: float
var eff_pilot_charisma: float
var eff_pilot_ingenuity: float

var hull: float = 100.0
var shield: float = 100.0
var _target_ang_rate: Vector3 = Vector3.ZERO   # desired ω from input (rad/s)
var _throttle_input: float = 0.0
var _thrusting: bool = false
var _reversing: bool = false
var _boosting: bool = false
var _dead: bool = false
var _pilot_forward_g_tolerance: float = 6.0
var _pilot_forward_g_hard_limit: float = 10.0
var _pilot_forward_accel_min_scale: float = 0.35
var _pilot_forward_speed_min_scale: float = 0.55
var _pilot_forward_g_from_ang_rate: float = 3.0
var _pilot_forward_g_from_ang_accel: float = 3.0
var _pilot_forward_g_smoothing_hz: float = 8.0
var _smoothed_forward_g: float = 1.0
var _pilot_perception: float = 5.0
var _pilot_charisma: float = 5.0
var _pilot_ingenuity: float = 5.0
var _regen_timer: Timer
var _nanobots: int = 0
var _hull_repair_cooldown_remaining: float = 0.0
var shield_mesh: MeshInstance3D
var _shield_mat: StandardMaterial3D
var _shield_base_albedo: Color = Color.WHITE
var _emission_value: float = 0.0
var _runtime_layout_root: Node3D
var _runtime_model_root: Node3D
var _runtime_anchors_root: Node3D
var _runtime_thruster_nodes: Array[Node3D] = []
var _runtime_thruster_materials: Array[BaseMaterial3D] = []
var _runtime_thruster_particles: Array[GPUParticles3D] = []
var _active_ship_id: StringName = &""

func _ready() -> void:
	add_to_group("player")
	reconfigure_from_selected_pilot()
	_apply_rigidbody_damping()
	RunState.start_run()
	_initialize_shield_material()
	_update_shield_mesh_visibility()
	EventBus.heal_hull_requested.connect(_on_heal_hull_requested)
	RunState.nanobots_spent.connect(spend_nanobots)
	if stat_aggregator != null and not stat_aggregator.stats_changed.is_connected(_on_stats_changed):
		stat_aggregator.stats_changed.connect(_on_stats_changed)
		if not EventBus.add_bulkhead_requested.is_connected(stat_aggregator.add_upgrade):
			EventBus.add_bulkhead_requested.connect(stat_aggregator.add_upgrade)
		if not EventBus.add_shield_requested.is_connected(stat_aggregator.add_upgrade):
			EventBus.add_shield_requested.connect(stat_aggregator.add_upgrade)
		if not EventBus.add_targeting_requested.is_connected(stat_aggregator.add_upgrade):
			EventBus.add_targeting_requested.connect(stat_aggregator.add_upgrade)
		if not EventBus.add_systems_requested.is_connected(stat_aggregator.add_upgrade):
			EventBus.add_systems_requested.connect(stat_aggregator.add_upgrade)
		if not EventBus.add_salvage_requested.is_connected(stat_aggregator.add_upgrade):
			EventBus.add_salvage_requested.connect(stat_aggregator.add_upgrade)
		if not EventBus.add_thrusters_requested.is_connected(stat_aggregator.add_upgrade):
			EventBus.add_thrusters_requested.connect(stat_aggregator.add_upgrade)
	
	# --- shield regen timer ---
	_regen_timer = Timer.new()
	_regen_timer.wait_time = 1.0
	_regen_timer.autostart = true
	_regen_timer.timeout.connect(_on_regen_tick)
	add_child(_regen_timer)

	# --- weapon manager ---
	if hardpoint_manager != null and hardpoint_manager.get_weapon_count() <= 0:
		hardpoint_manager.apply_loadout(loadout)

func reconfigure_from_selected_pilot(reset_current_health: bool = true) -> void:
	_apply_selected_defs()
	_refresh_effective_stats()
	if reset_current_health:
		hull = eff_max_hull
		shield = eff_max_shield
	_update_shield_mesh_visibility()
	update_alarms()
	if hardpoint_manager != null:
		hardpoint_manager.apply_loadout(loadout)

func _apply_selected_defs() -> void:
	var selected_pilot: PilotDef = _resolve_selected_pilot()
	var selected_ship_def: ShipDef = ship_override
	_active_ship_id = &""
	if selected_ship_def == null:
		selected_ship_def = GameFlow.get_selected_ship()

	if selected_ship_def == null and selected_pilot != null and selected_pilot.ship != null:
		selected_ship_def = selected_pilot.ship

	if selected_ship_def != null:
		_apply_ship_def(selected_ship_def)

	if selected_pilot != null:
		_apply_pilot_def(selected_pilot)
	else:
		_apply_pilot_forward_load_profile(null)
		_apply_pilot_attributes(null)
		_apply_pilot_stat_profile(null)

	_apply_selected_starting_weapon()

func _resolve_selected_pilot() -> PilotDef:
	if pilot_override != null:
		return pilot_override
	return GameFlow.selected_pilot

func _apply_pilot_def(def: PilotDef) -> void:
	if def == null:
		_apply_pilot_forward_load_profile(null)
		_apply_pilot_attributes(null)
		_apply_pilot_stat_profile(null)
		return

	if def.loadout_override != null:
		loadout = def.loadout_override

	if hardpoint_manager != null and def.mount_layout_policy_override != null:
		hardpoint_manager.policy = def.mount_layout_policy_override

	_apply_pilot_forward_load_profile(def)
	_apply_pilot_attributes(def)
	_apply_pilot_stat_profile(def)

func _apply_pilot_forward_load_profile(def: PilotDef) -> void:
	if def == null:
		_pilot_forward_g_tolerance = max(default_forward_g_tolerance, 0.0)
		_pilot_forward_g_hard_limit = max(default_forward_g_hard_limit, _pilot_forward_g_tolerance + 0.01)
		_pilot_forward_accel_min_scale = clamp(default_forward_accel_min_scale, 0.0, 1.0)
		_pilot_forward_speed_min_scale = clamp(default_forward_speed_min_scale, 0.0, 1.0)
		_pilot_forward_g_from_ang_rate = max(default_forward_g_from_ang_rate, 0.0)
		_pilot_forward_g_from_ang_accel = max(default_forward_g_from_ang_accel, 0.0)
		_pilot_forward_g_smoothing_hz = max(default_forward_g_smoothing_hz, 0.0)
	else:
		_pilot_forward_g_tolerance = max(def.forward_g_tolerance, 0.0)
		_pilot_forward_g_hard_limit = max(def.forward_g_hard_limit, _pilot_forward_g_tolerance + 0.01)
		_pilot_forward_accel_min_scale = clamp(def.forward_accel_min_scale, 0.0, 1.0)
		_pilot_forward_speed_min_scale = clamp(def.forward_speed_min_scale, 0.0, 1.0)
		_pilot_forward_g_from_ang_rate = max(def.forward_g_from_ang_rate, 0.0)
		_pilot_forward_g_from_ang_accel = max(def.forward_g_from_ang_accel, 0.0)
		_pilot_forward_g_smoothing_hz = max(def.forward_g_smoothing_hz, 0.0)

	if stat_aggregator != null:
		stat_aggregator.set_base_value(Stat.PILOT_G_TOLERANCE, _pilot_forward_g_tolerance)
		stat_aggregator.set_base_value(Stat.PILOT_G_HARD_LIMIT, _pilot_forward_g_hard_limit)
		stat_aggregator.set_base_value(Stat.PILOT_FORWARD_ACCEL_MIN_SCALE, _pilot_forward_accel_min_scale)
		stat_aggregator.set_base_value(Stat.PILOT_FORWARD_SPEED_MIN_SCALE, _pilot_forward_speed_min_scale)
		stat_aggregator.set_base_value(Stat.PILOT_FORWARD_G_FROM_ANG_RATE, _pilot_forward_g_from_ang_rate)
		stat_aggregator.set_base_value(Stat.PILOT_FORWARD_G_FROM_ANG_ACCEL, _pilot_forward_g_from_ang_accel)
		stat_aggregator.set_base_value(Stat.PILOT_FORWARD_G_SMOOTHING_HZ, _pilot_forward_g_smoothing_hz)
	_smoothed_forward_g = 1.0

func _apply_pilot_attributes(def: PilotDef) -> void:
	if def == null:
		_pilot_perception = 5.0
		_pilot_charisma = 5.0
		_pilot_ingenuity = 5.0
	else:
		_pilot_perception = max(def.perception, 0.0)
		_pilot_charisma = max(def.charisma, 0.0)
		_pilot_ingenuity = max(def.ingenuity, 0.0)

	if stat_aggregator != null:
		stat_aggregator.set_base_value(Stat.PILOT_PERCEPTION, _pilot_perception)
		stat_aggregator.set_base_value(Stat.PILOT_CHARISMA, _pilot_charisma)
		stat_aggregator.set_base_value(Stat.PILOT_INGENUITY, _pilot_ingenuity)

func _apply_pilot_stat_profile(def: PilotDef) -> void:
	if stat_aggregator == null:
		return
	stat_aggregator.clear()
	if def == null:
		return

	var pilot_source_id: String = "pilot:%s" % String(def.get_pilot_id())
	for mod in def.stat_modifiers:
		if mod == null:
			continue
		var mod_copy: StatModifier = mod.duplicate(true) as StatModifier
		if mod_copy == null:
			continue
		if mod_copy.source_id == "":
			mod_copy.source_id = pilot_source_id
		stat_aggregator.add_modifier(mod_copy)

	for upgrade in def.starting_upgrades:
		if upgrade == null:
			continue
		var upgrade_copy: Upgrade = upgrade.duplicate(true) as Upgrade
		if upgrade_copy == null:
			continue
		stat_aggregator.add_upgrade(upgrade_copy)

func _apply_selected_starting_weapon() -> void:
	if loadout == null:
		return
	loadout = GameFlow.build_selected_starting_loadout(loadout)

func _apply_ship_def(def: ShipDef) -> void:
	if def == null:
		return
	_active_ship_id = def.get_ship_id()

	if def.loadout != null:
		loadout = def.loadout
	if def.explosion_scene != null:
		explosion_scene = def.explosion_scene

	max_hull = def.max_hull
	overheal = def.overheal
	max_shield = def.max_shield
	shield_regen = def.shield_regen
	base_evasion = def.base_evasion

	max_speed_forward = def.max_speed_forward
	max_speed_reverse = def.max_speed_reverse
	drag = def.drag
	accel_forward = def.accel_forward
	accel_reverse = def.accel_reverse
	boost_mult = def.boost_mult
	rigidbody_linear_damp_mode = def.rigidbody_linear_damp_mode
	rigidbody_linear_damp = def.rigidbody_linear_damp
	rigidbody_angular_damp_mode = def.rigidbody_angular_damp_mode
	rigidbody_angular_damp = def.rigidbody_angular_damp
	_apply_rigidbody_damping()
	base_spaciness = def.base_spaciness
	coast_brake_accel = def.coast_brake_accel
	lateral_brake_accel = def.lateral_brake_accel
	vertical_brake_accel = def.vertical_brake_accel
	turn_assist_brake_bonus = def.turn_assist_brake_bonus
	no_throttle_turn_assist_bonus = def.no_throttle_turn_assist_bonus
	counter_thrust_brake_mult = def.counter_thrust_brake_mult
	thrust_drag_scale = def.thrust_drag_scale
	coast_drag_scale = def.coast_drag_scale
	forward_drag_scale_throttle = def.forward_drag_scale_throttle
	forward_drag_scale_coast = def.forward_drag_scale_coast

	pickup_range = def.pickup_range
	nanobot_gain_mult = def.nanobot_gain_mult
	score_gain_mult = def.score_gain_mult

	max_ang_rate = Vector3(
		deg_to_rad(def.max_ang_rate_deg.x),
		deg_to_rad(def.max_ang_rate_deg.y),
		deg_to_rad(def.max_ang_rate_deg.z))
	angular_accel = Vector3(
		deg_to_rad(def.angular_accel_deg.x),
		deg_to_rad(def.angular_accel_deg.y),
		deg_to_rad(def.angular_accel_deg.z))
	_apply_ship_visuals(def.visuals)

# --- public api for upgrades/ui ---

func push_weapon_to_stack(w: WeaponDef) -> void:
	if hardpoint_manager != null:
		hardpoint_manager.push_weapon(w)

func pop_weapon_from_stack() -> void:
	if hardpoint_manager != null:
		hardpoint_manager.pop_weapon()

func swap_weapon_at(index: int, w: WeaponDef) -> void:
	if hardpoint_manager != null:
		hardpoint_manager.swap_weapon_at(index, w)

func collect_nanobots(amount: int) -> void:
	var gain_mult: float = eff_nanobot_gain_mult if eff_nanobot_gain_mult > 0.0 else 1.0
	var adjusted: int = int(round(max(0.0, float(amount) * gain_mult)))
	_nanobots += adjusted
	RunState.nanobots_updated.emit(_nanobots)

func spend_nanobots(amount: int) -> void:
	_nanobots -= amount
	RunState.nanobots_updated.emit(_nanobots)

func get_nanobots() -> int:
	return _nanobots

func reset_for_stage_transition() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D.IDENTITY
	sleeping = false

func get_hull_repair_cost() -> int:
	return max(hull_repair_cost, 0)

func get_hull_repair_cooldown_remaining() -> float:
	return max(_hull_repair_cooldown_remaining, 0.0)

func get_hull_repair_cooldown() -> float:
	return max(hull_repair_cooldown, 0.0)

# --- private methods ---

func _refresh() -> void:
	if hardpoint_manager == null:
		return
	hardpoint_manager.rebuild_anchor_cache()

func _physics_process(delta: float) -> void:
	if _hull_repair_cooldown_remaining > 0.0:
		_hull_repair_cooldown_remaining = max(_hull_repair_cooldown_remaining - delta, 0.0)
	if Input.is_action_just_pressed("hull_repair"):
		_try_use_hull_repair()

	_update_translation()
	
	var target_emission: float = 0.0
	if _thrusting:
		target_emission = 1.15 if _boosting else 1.0
	
	_emission_value = lerp(_emission_value, target_emission, delta * 8.0)
	
	for mat in _runtime_thruster_materials:
		if mat != null:
			mat.emission_energy_multiplier = _emission_value

	if not _runtime_thruster_particles.is_empty():
		var forward_vel: float = linear_velocity.dot(-transform.basis.z)
		var main_emit: bool = _thrusting and not _reversing
		var particle_cap: float = max(eff_max_speed_forward * (eff_boost_mult if _boosting else 1.0), 1.0)
		var ratio: float = clamp(max(forward_vel, 0.0) / particle_cap, 0.15, 1.0)
		for particles in _runtime_thruster_particles:
			if particles == null:
				continue
			particles.emitting = main_emit
			particles.amount_ratio = ratio

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt: float = state.step
	
	var basis_inv: Basis = transform.basis.inverse()
	var w_local: Vector3 = basis_inv * state.angular_velocity
	
	var next_local: Vector3 = Vector3(
		move_toward(w_local.x, _target_ang_rate.x, eff_angular_accel.x * dt),
		move_toward(w_local.y, _target_ang_rate.y, eff_angular_accel.y * dt),
		move_toward(w_local.z, _target_ang_rate.z, eff_angular_accel.z * dt)
	)
	
	state.angular_velocity = transform.basis * next_local

	var ang_accel_local: Vector3 = Vector3.ZERO
	if dt > 0.0:
		ang_accel_local = (next_local - w_local) / dt

	var lv_local: Vector3 = basis_inv * state.linear_velocity
	var lateral_drag_scale: float = thrust_drag_scale if absf(_throttle_input) > 0.001 else coast_drag_scale
	var vertical_drag_scale: float = lateral_drag_scale
	var forward_drag_scale: float = forward_drag_scale_throttle if absf(_throttle_input) > 0.001 else forward_drag_scale_coast
	var base_drag_coeff: float = max(eff_drag, 0.0)
	lv_local.x = _apply_axis_quadratic_drag(lv_local.x, base_drag_coeff * max(lateral_drag_scale, 0.0), dt)
	lv_local.y = _apply_axis_quadratic_drag(lv_local.y, base_drag_coeff * max(vertical_drag_scale, 0.0), dt)
	lv_local.z = _apply_axis_quadratic_drag(lv_local.z, base_drag_coeff * max(forward_drag_scale, 0.0), dt)

	var assist_scale: float = _get_assist_scale()
	var desired_forward: float = 0.0
	var forward_rate: float = max(coast_brake_accel * assist_scale, 0.0)
	var boost: float = eff_boost_mult if _boosting else 1.0
	var g_limited_forward_cap: float = eff_max_speed_forward
	var g_limited_accel_scale: float = 1.0

	if _throttle_input > 0.0:
		var current_forward_g: float = _compute_forward_g_load(w_local, ang_accel_local, dt)
		g_limited_accel_scale = _compute_g_limiter_scale(current_forward_g, eff_pilot_forward_accel_min_scale)
		var g_limited_speed_scale: float = _compute_g_limiter_scale(current_forward_g, eff_pilot_forward_speed_min_scale)
		g_limited_forward_cap = eff_max_speed_forward * g_limited_speed_scale
		desired_forward = g_limited_forward_cap
		forward_rate = max(eff_accel_forward * boost * g_limited_accel_scale, 0.0)
	elif _throttle_input < 0.0:
		desired_forward = -eff_max_speed_reverse
		forward_rate = max(eff_accel_reverse * boost, 0.0)

	var forward_speed: float = -lv_local.z
	if desired_forward != 0.0 and signf(desired_forward) != signf(forward_speed):
		forward_rate *= max(counter_thrust_brake_mult, 0.0)

	forward_speed = move_toward(forward_speed, desired_forward, forward_rate * dt)
	forward_speed = clamp(forward_speed, -eff_max_speed_reverse, g_limited_forward_cap)
	lv_local.z = -forward_speed

	var yaw_norm: float = absf(w_local.y) / max(eff_max_ang_rate.y, 0.0001)
	var pitch_norm: float = absf(w_local.x) / max(eff_max_ang_rate.x, 0.0001)
	var turn_amount: float = clamp(max(yaw_norm, pitch_norm), 0.0, 1.0)
	var turn_bonus: float = turn_assist_brake_bonus * assist_scale * turn_amount
	if absf(_throttle_input) < 0.001:
		turn_bonus += no_throttle_turn_assist_bonus * assist_scale

	var lateral_rate: float = max(lateral_brake_accel * assist_scale + turn_bonus, 0.0)
	var vertical_rate: float = max(vertical_brake_accel * assist_scale + turn_bonus, 0.0)
	lv_local.x = move_toward(lv_local.x, 0.0, lateral_rate * dt)
	lv_local.y = move_toward(lv_local.y, 0.0, vertical_rate * dt)

	state.linear_velocity = transform.basis * lv_local

func set_target_angular_rates(rad_per_sec: Vector3) -> void:
	_target_ang_rate = Vector3(
		clamp(rad_per_sec.x, -eff_max_ang_rate.x, eff_max_ang_rate.x),
		clamp(rad_per_sec.y, -eff_max_ang_rate.y, eff_max_ang_rate.y),
		clamp(rad_per_sec.z, -eff_max_ang_rate.z, eff_max_ang_rate.z)
	)

func get_evasion() -> float:
	return eff_evasion

func get_speed_caps() -> Vector2:
	return Vector2(eff_max_speed_reverse, eff_max_speed_forward)

func get_effective_accel_forward() -> float:
	return eff_accel_forward

func get_effective_accel_reverse() -> float:
	return eff_accel_reverse

func get_effective_boost_mult() -> float:
	return eff_boost_mult

func get_effective_drag() -> float:
	return eff_drag

func get_effective_max_angular_rates() -> Vector3:
	return eff_max_ang_rate

func get_effective_angular_accel() -> Vector3:
	return eff_angular_accel

func get_effective_pickup_range() -> float:
	return eff_pickup_range

func get_effective_nanobot_gain_mult() -> float:
	return eff_nanobot_gain_mult

func get_effective_score_gain_mult() -> float:
	return eff_score_gain_mult

func get_equipped_weapon_ids() -> Array[StringName]:
	var weapon_ids: Array[StringName] = []
	if hardpoint_manager != null:
		for weapon in hardpoint_manager.get_weapons():
			if weapon == null:
				continue
			var weapon_id: StringName = weapon.get_weapon_id()
			if weapon_id == &"":
				continue
			var already_present: bool = false
			for existing_id in weapon_ids:
				if existing_id == weapon_id:
					already_present = true
					break
			if not already_present:
				weapon_ids.append(weapon_id)
	if weapon_ids.is_empty() and loadout != null:
		for mount in loadout.mounts:
			if mount == null or mount.weapon == null:
				continue
			var mount_weapon_id: StringName = mount.weapon.get_weapon_id()
			if mount_weapon_id == &"":
				continue
			var has_weapon_id: bool = false
			for existing_id in weapon_ids:
				if existing_id == mount_weapon_id:
					has_weapon_id = true
					break
			if not has_weapon_id:
				weapon_ids.append(mount_weapon_id)
	return weapon_ids

func build_combat_stat_context(weapon_direct_id: StringName = &"", target: Object = null) -> CombatStatContext:
	var context: CombatStatContext = CombatStatContext.new()
	var active_pilot: PilotDef = _resolve_selected_pilot()
	context.pilot_id = active_pilot.get_pilot_id() if active_pilot != null else &""
	context.ship_id = _active_ship_id
	context.weapon_direct_id = weapon_direct_id
	context.equipped_weapon_ids = get_equipped_weapon_ids()
	if target != null:
		context.set_enemy_identity_from_source(target)
	return context

func get_pilot_g_tolerance() -> float:
	return _pilot_forward_g_tolerance

func get_pilot_g_hard_limit() -> float:
	return _pilot_forward_g_hard_limit

func get_effective_pilot_g_tolerance() -> float:
	return eff_pilot_g_tolerance

func get_effective_pilot_g_hard_limit() -> float:
	return eff_pilot_g_hard_limit

func get_pilot_forward_accel_min_scale() -> float:
	return _pilot_forward_accel_min_scale

func get_pilot_forward_speed_min_scale() -> float:
	return _pilot_forward_speed_min_scale

func get_pilot_forward_g_from_ang_rate() -> float:
	return _pilot_forward_g_from_ang_rate

func get_pilot_forward_g_from_ang_accel() -> float:
	return _pilot_forward_g_from_ang_accel

func get_pilot_forward_g_smoothing_hz() -> float:
	return _pilot_forward_g_smoothing_hz

func get_effective_pilot_forward_accel_min_scale() -> float:
	return eff_pilot_forward_accel_min_scale

func get_effective_pilot_forward_speed_min_scale() -> float:
	return eff_pilot_forward_speed_min_scale

func get_effective_pilot_forward_g_from_ang_rate() -> float:
	return eff_pilot_forward_g_from_ang_rate

func get_effective_pilot_forward_g_from_ang_accel() -> float:
	return eff_pilot_forward_g_from_ang_accel

func get_effective_pilot_forward_g_smoothing_hz() -> float:
	return eff_pilot_forward_g_smoothing_hz

func get_pilot_perception() -> float:
	return _pilot_perception

func get_pilot_charisma() -> float:
	return _pilot_charisma

func get_pilot_ingenuity() -> float:
	return _pilot_ingenuity

func get_effective_pilot_perception() -> float:
	return eff_pilot_perception

func get_effective_pilot_charisma() -> float:
	return eff_pilot_charisma

func get_effective_pilot_ingenuity() -> float:
	return eff_pilot_ingenuity

func is_alive() -> bool:
	return not _dead

func apply_damage(amount: float, combat_stat_context: CombatStatContext = null) -> void:
	if _dead:
		return
	var incoming: float = max(0.0, amount * eff_damage_taken_mult)
	if incoming <= 0.0:
		return
	var remaining: float = incoming
	var shield_damage: float = 0.0
	if shield > 0.0:
		var absorbed: float = min(shield, remaining)
		if absorbed > 0.0:
			shield -= absorbed
			remaining -= absorbed
			shield_damage = absorbed
	var hull_damage: float = 0.0
	if remaining > 0.0:
		hull_damage = min(hull, remaining)
		hull -= remaining
	var total_damage_applied: float = shield_damage + hull_damage
	if total_damage_applied > 0.0:
		CombatStats.report_damage_taken(total_damage_applied)
		if combat_stat_context != null:
			GameFlow.record_damage_taken(total_damage_applied, combat_stat_context)
	_update_shield_mesh_visibility()
	if hull_damage > 0.0:
		_play_hit_sound(hull_hit_audio)
	elif shield_damage > 0.0:
		_flash_shield()
		_play_hit_sound(shield_hit_audio)
	if hull <= 0.0:
		_die()

func update_alarms() -> void:
	var shield_frac: float = 0.0
	var hull_frac: float = 0.0
	
	if eff_max_shield > 0.0:
		shield_frac = shield / eff_max_shield
	if eff_max_hull > 0.0:
		hull_frac = hull / eff_max_hull
	
	var desired_alarm: AudioStreamPlayer3D = null
	
	if shield_frac < LOW_ALARM_THRESHOLD and hull_frac >= LOW_ALARM_THRESHOLD:
		desired_alarm = shield_low_alarm_audio
	
	elif shield_frac < LOW_ALARM_THRESHOLD and hull_frac < LOW_ALARM_THRESHOLD:
		desired_alarm = hull_low_alarm_audio
	
	_switch_alarm(desired_alarm)

func _switch_alarm(desired: AudioStreamPlayer3D) -> void:
	if desired == _current_alarm:
		return
	
	if _current_alarm != null and _current_alarm.playing:
		_current_alarm.stop()
	
	_current_alarm = desired
	
	if _current_alarm != null and not _current_alarm.playing:
		_current_alarm.play()

func _play_hit_sound(player: AudioStreamPlayer3D) -> void:
	if player == null:
		return
	player.pitch_scale = randf_range(0.95, 1.05)
	player.play()

func _flash_shield() -> void:
	_initialize_shield_material()
	if _shield_mat == null:
		return
	var t: Tween = create_tween()
	t.tween_property(_shield_mat, "emission_energy_multiplier", 3, 0.1)
	t.tween_property(_shield_mat, "emission_energy_multiplier", 1, 0.25)

func _update_translation() -> void:
	_thrusting = Input.is_action_pressed("thrust")
	_reversing = Input.is_action_pressed("reverse")
	_boosting = Input.is_action_pressed("boost")
	_throttle_input = 0.0
	if _thrusting:
		_throttle_input += 1.0
	if _reversing:
		_throttle_input -= 1.0
	_throttle_input = clamp(_throttle_input, -1.0, 1.0)

func _get_assist_scale() -> float:
	return lerp(1.6, 0.4, clamp(base_spaciness, 0.0, 1.0))

func _apply_axis_quadratic_drag(component: float, drag_coeff: float, dt: float) -> float:
	if dt <= 0.0 or drag_coeff <= 0.0:
		return component
	var abs_component: float = absf(component)
	if abs_component <= 0.00001:
		return component
	var drag_factor: float = 1.0 / (1.0 + drag_coeff * abs_component * dt)
	return component * drag_factor

func _compute_forward_g_load(w_local: Vector3, ang_accel_local: Vector3, dt: float) -> float:
	var rate_cap: float = max(eff_max_ang_rate.length(), 0.0001)
	var accel_cap: float = max(eff_angular_accel.length(), 0.0001)
	var rate_ratio: float = clamp(w_local.length() / rate_cap, 0.0, 2.0)
	var accel_ratio: float = clamp(ang_accel_local.length() / accel_cap, 0.0, 2.0)
	var target_g: float = 1.0 + eff_pilot_forward_g_from_ang_rate * rate_ratio + eff_pilot_forward_g_from_ang_accel * accel_ratio
	var smoothing_hz: float = max(eff_pilot_forward_g_smoothing_hz, 0.0)
	if dt > 0.0 and smoothing_hz > 0.0:
		var t: float = 1.0 - exp(-smoothing_hz * dt)
		_smoothed_forward_g = lerp(_smoothed_forward_g, target_g, t)
	else:
		_smoothed_forward_g = target_g
	return _smoothed_forward_g

func _compute_g_limiter_scale(current_g: float, min_scale: float) -> float:
	var tolerance: float = max(eff_pilot_g_tolerance, 0.0)
	var hard_limit: float = max(eff_pilot_g_hard_limit, tolerance + 0.01)
	if current_g <= tolerance:
		return 1.0
	var overload_alpha: float = clamp((current_g - tolerance) / (hard_limit - tolerance), 0.0, 1.0)
	return lerp(1.0, clamp(min_scale, 0.0, 1.0), overload_alpha)

func _apply_rigidbody_damping() -> void:
	linear_damp_mode = rigidbody_linear_damp_mode as RigidBody3D.DampMode
	linear_damp = max(rigidbody_linear_damp, 0.0)
	angular_damp_mode = rigidbody_angular_damp_mode as RigidBody3D.DampMode
	angular_damp = max(rigidbody_angular_damp, 0.0)

func _on_regen_tick() -> void:
	if _dead:
		return
	if shield < eff_max_shield and eff_shield_regen > 0.0:
		shield = min(shield + eff_shield_regen, eff_max_shield)
	_update_shield_mesh_visibility()
	update_alarms()

func _try_use_hull_repair() -> void:
	if _dead:
		return
	if _hull_repair_cooldown_remaining > 0.0:
		return
	if hull >= eff_max_hull:
		return

	var cost: int = max(hull_repair_cost, 0)
	if _nanobots < cost:
		return

	if cost > 0:
		spend_nanobots(cost)
	_on_heal_hull_requested(hull_repair_amount, 0.0)
	_hull_repair_cooldown_remaining = max(hull_repair_cooldown, 0.0)

func _refresh_effective_stats() -> void:
	var aggr: StatAggregator = stat_aggregator
	if aggr == null:
		eff_max_hull = max_hull
		eff_max_shield = max_shield
		eff_shield_regen = shield_regen
		eff_evasion = clamp(base_evasion, 0.0, 1.0)
		eff_damage_taken_mult = 1.0
		eff_max_speed_forward = max(max_speed_forward, 0.0)
		eff_max_speed_reverse = max(max_speed_reverse, 0.0)
		eff_accel_forward = max(accel_forward, 0.0)
		eff_accel_reverse = max(accel_reverse, 0.0)
		eff_boost_mult = max(boost_mult, 0.0)
		eff_drag = max(drag, 0.0)
		eff_max_ang_rate = Vector3(max(max_ang_rate.x, 0.0), max(max_ang_rate.y, 0.0), max(max_ang_rate.z, 0.0))
		eff_angular_accel = Vector3(max(angular_accel.x, 0.0), max(angular_accel.y, 0.0), max(angular_accel.z, 0.0))
		eff_pickup_range = pickup_range
		eff_nanobot_gain_mult = nanobot_gain_mult
		eff_score_gain_mult = score_gain_mult
		eff_pilot_g_tolerance = max(_pilot_forward_g_tolerance, 0.0)
		eff_pilot_g_hard_limit = max(_pilot_forward_g_hard_limit, eff_pilot_g_tolerance + 0.01)
		eff_pilot_forward_accel_min_scale = clamp(_pilot_forward_accel_min_scale, 0.0, 1.0)
		eff_pilot_forward_speed_min_scale = clamp(_pilot_forward_speed_min_scale, 0.0, 1.0)
		eff_pilot_forward_g_from_ang_rate = max(_pilot_forward_g_from_ang_rate, 0.0)
		eff_pilot_forward_g_from_ang_accel = max(_pilot_forward_g_from_ang_accel, 0.0)
		eff_pilot_forward_g_smoothing_hz = max(_pilot_forward_g_smoothing_hz, 0.0)
		eff_pilot_perception = max(_pilot_perception, 0.0)
		eff_pilot_charisma = max(_pilot_charisma, 0.0)
		eff_pilot_ingenuity = max(_pilot_ingenuity, 0.0)
		_update_shield_mesh_visibility()
		return
	# Pull effective values once.
	eff_max_hull = aggr.compute_for_context(Stat.MAX_HULL, max_hull, StatAggregator.Context.PLAYER)
	eff_max_shield = aggr.compute_for_context(Stat.MAX_SHIELD, max_shield, StatAggregator.Context.PLAYER)
	eff_shield_regen = aggr.compute_for_context(Stat.SHIELD_REGEN, shield_regen, StatAggregator.Context.PLAYER)
	eff_evasion = clamp(aggr.compute_for_context(Stat.EVASION_BASE, base_evasion, StatAggregator.Context.PLAYER), 0.0, 1.0)
	eff_damage_taken_mult = aggr.compute_for_context(Stat.DAMAGE_TAKEN_MULT, 1.0, StatAggregator.Context.PLAYER)
	eff_max_speed_forward = max(aggr.compute_for_context(Stat.MAX_SPEED_FORWARD, max_speed_forward, StatAggregator.Context.PLAYER), 0.0)
	eff_max_speed_reverse = max(aggr.compute_for_context(Stat.MAX_SPEED_REVERSE, max_speed_reverse, StatAggregator.Context.PLAYER), 0.0)
	eff_accel_forward = max(aggr.compute_for_context(Stat.ACCEL_FORWARD, accel_forward, StatAggregator.Context.PLAYER), 0.0)
	eff_accel_reverse = max(aggr.compute_for_context(Stat.ACCEL_REVERSE, accel_reverse, StatAggregator.Context.PLAYER), 0.0)
	eff_boost_mult = max(aggr.compute_for_context(Stat.BOOST_MULT, boost_mult, StatAggregator.Context.PLAYER), 0.0)
	eff_drag = max(aggr.compute_for_context(Stat.DRAG, drag, StatAggregator.Context.PLAYER), 0.0)
	eff_max_ang_rate = Vector3(
		max(aggr.compute_for_context(Stat.ANGULAR_RATE_PITCH, max_ang_rate.x, StatAggregator.Context.PLAYER), 0.0),
		max(aggr.compute_for_context(Stat.ANGULAR_RATE_YAW, max_ang_rate.y, StatAggregator.Context.PLAYER), 0.0),
		max(aggr.compute_for_context(Stat.ANGULAR_RATE_ROLL, max_ang_rate.z, StatAggregator.Context.PLAYER), 0.0))
	eff_angular_accel = Vector3(
		max(aggr.compute_for_context(Stat.ANGULAR_ACCEL_PITCH, angular_accel.x, StatAggregator.Context.PLAYER), 0.0),
		max(aggr.compute_for_context(Stat.ANGULAR_ACCEL_YAW, angular_accel.y, StatAggregator.Context.PLAYER), 0.0),
		max(aggr.compute_for_context(Stat.ANGULAR_ACCEL_ROLL, angular_accel.z, StatAggregator.Context.PLAYER), 0.0))
	eff_pickup_range = aggr.compute_for_context(Stat.PICKUP_RANGE, pickup_range, StatAggregator.Context.PLAYER)
	eff_nanobot_gain_mult = aggr.compute_for_context(Stat.NANOBOT_GAIN_MULT, nanobot_gain_mult, StatAggregator.Context.PLAYER)
	eff_score_gain_mult = aggr.compute_for_context(Stat.SCORE_GAIN_MULT, score_gain_mult, StatAggregator.Context.PLAYER)
	eff_pilot_g_tolerance = max(aggr.compute_for_context(Stat.PILOT_G_TOLERANCE, _pilot_forward_g_tolerance, StatAggregator.Context.PLAYER), 0.0)
	eff_pilot_g_hard_limit = max(aggr.compute_for_context(Stat.PILOT_G_HARD_LIMIT, _pilot_forward_g_hard_limit, StatAggregator.Context.PLAYER), eff_pilot_g_tolerance + 0.01)
	eff_pilot_forward_accel_min_scale = clamp(aggr.compute_for_context(Stat.PILOT_FORWARD_ACCEL_MIN_SCALE, _pilot_forward_accel_min_scale, StatAggregator.Context.PLAYER), 0.0, 1.0)
	eff_pilot_forward_speed_min_scale = clamp(aggr.compute_for_context(Stat.PILOT_FORWARD_SPEED_MIN_SCALE, _pilot_forward_speed_min_scale, StatAggregator.Context.PLAYER), 0.0, 1.0)
	eff_pilot_forward_g_from_ang_rate = max(aggr.compute_for_context(Stat.PILOT_FORWARD_G_FROM_ANG_RATE, _pilot_forward_g_from_ang_rate, StatAggregator.Context.PLAYER), 0.0)
	eff_pilot_forward_g_from_ang_accel = max(aggr.compute_for_context(Stat.PILOT_FORWARD_G_FROM_ANG_ACCEL, _pilot_forward_g_from_ang_accel, StatAggregator.Context.PLAYER), 0.0)
	eff_pilot_forward_g_smoothing_hz = max(aggr.compute_for_context(Stat.PILOT_FORWARD_G_SMOOTHING_HZ, _pilot_forward_g_smoothing_hz, StatAggregator.Context.PLAYER), 0.0)
	eff_pilot_perception = max(aggr.compute_for_context(Stat.PILOT_PERCEPTION, _pilot_perception, StatAggregator.Context.PLAYER), 0.0)
	eff_pilot_charisma = max(aggr.compute_for_context(Stat.PILOT_CHARISMA, _pilot_charisma, StatAggregator.Context.PLAYER), 0.0)
	eff_pilot_ingenuity = max(aggr.compute_for_context(Stat.PILOT_INGENUITY, _pilot_ingenuity, StatAggregator.Context.PLAYER), 0.0)
	_update_shield_mesh_visibility()

func _apply_ship_visuals(visuals: ShipVisualDef) -> void:
	_clear_runtime_visual_nodes()
	_refresh_runtime_layout(visuals)
	_sync_camera_from_visuals(visuals)
	_build_runtime_model(visuals)
	_build_runtime_anchor_markers(visuals)
	_build_runtime_thrusters(visuals)
	var shield_def: ShipShieldDef = visuals.shield if visuals != null else null
	_build_runtime_shield_mesh(shield_def)
	_configure_hardpoint_anchors(visuals)

func _clear_runtime_visual_nodes() -> void:
	if shield_mesh != null:
		shield_mesh.queue_free()
	shield_mesh = null
	_shield_mat = null

	if hardpoint_manager != null:
		hardpoint_manager.detach_assemblies()

	for particles in _runtime_thruster_particles:
		if particles != null:
			particles.queue_free()
	_runtime_thruster_particles.clear()

	for node in _runtime_thruster_nodes:
		if node != null:
			node.queue_free()
	_runtime_thruster_nodes.clear()
	_runtime_thruster_materials.clear()

	if _runtime_model_root != null:
		_runtime_model_root.queue_free()
		_runtime_model_root = null

	if _runtime_anchors_root != null:
		_runtime_anchors_root = null

	if _runtime_layout_root != null:
		_runtime_layout_root.queue_free()
		_runtime_layout_root = null

func _refresh_runtime_layout(visuals: ShipVisualDef) -> void:
	if visuals == null or visuals.layout_scene == null or visual_root == null:
		return
	var inst: Node = visuals.layout_scene.instantiate()
	var root: Node3D = inst as Node3D
	if root == null:
		if inst != null:
			inst.queue_free()
		return
	root.name = "RuntimeLayout"
	root.visible = true
	visual_root.add_child(root)
	_runtime_layout_root = root

func _resolve_layout_socket(path: NodePath) -> Node3D:
	if _runtime_layout_root == null or path == NodePath(""):
		return null
	return _runtime_layout_root.get_node_or_null(path) as Node3D

func _resolve_layout_socket_with_root(root_path: NodePath, marker_path: NodePath) -> Node3D:
	if _runtime_layout_root == null or marker_path == NodePath(""):
		return null
	var direct: Node3D = _runtime_layout_root.get_node_or_null(marker_path) as Node3D
	if direct != null:
		return direct
	if root_path == NodePath(""):
		return null
	var combined_path: NodePath = NodePath("%s/%s" % [String(root_path), String(marker_path)])
	return _runtime_layout_root.get_node_or_null(combined_path) as Node3D

func _sync_camera_from_visuals(visuals: ShipVisualDef) -> void:
	if camera_rig == null or visuals == null:
		return
	camera_rig.height_offset = visuals.camera_height
	camera_rig.distance_offset = visuals.camera_distance
	camera_rig.angle_offset_deg = visuals.camera_angle_deg
	camera_rig.fov = visuals.camera_fov
	camera_rig.position = Vector3(0.0, camera_rig.height_offset, -camera_rig.distance_offset)
	var cam: Camera3D = camera_rig.get_node_or_null("Camera3D") as Camera3D
	if cam != null:
		cam.fov = visuals.camera_fov

func _build_runtime_model(visuals: ShipVisualDef) -> void:
	if visuals == null or visuals.model_scene == null:
		return
	var model_instance: Node3D = visuals.model_scene.instantiate() as Node3D
	if model_instance == null:
		return
	model_instance.name = "RuntimeModel"
	var socket: Node3D = _resolve_layout_socket(visuals.model_marker_path)
	if socket == null:
		model_instance.queue_free()
		push_warning("Ship visuals missing model marker path: %s" % String(visuals.model_marker_path))
		return
	socket.add_child(model_instance)
	model_instance.transform = Transform3D.IDENTITY
	_runtime_model_root = model_instance

func _build_runtime_anchor_markers(visuals: ShipVisualDef) -> void:
	_runtime_anchors_root = null
	if visuals == null:
		return
	if _runtime_layout_root == null:
		return
	var anchors_root: Node3D = _resolve_layout_socket(visuals.anchors_root_path)
	if anchors_root == null:
		push_warning("Ship anchors root not found in layout: %s" % String(visuals.anchors_root_path))
		return
	_runtime_anchors_root = anchors_root

func _configure_hardpoint_anchors(visuals: ShipVisualDef) -> void:
	if hardpoint_manager == null:
		return
	if _runtime_anchors_root == null:
		return
	if visuals != null and visuals.mount_layout_policy != null:
		hardpoint_manager.policy = visuals.mount_layout_policy
	hardpoint_manager.anchors_root_path = hardpoint_manager.get_path_to(_runtime_anchors_root)
	if visuals != null:
		var stow_name: String = String(visuals.stow_anchor_name).strip_edges()
		if stow_name != "":
			hardpoint_manager.stow_anchor_name = stow_name
	hardpoint_manager.rebuild_anchor_cache()

func _build_runtime_thrusters(visuals: ShipVisualDef) -> void:
	if visuals == null:
		return
	for thruster_def in visuals.thrusters:
		if thruster_def == null:
			continue
		var thruster_name: String = String(thruster_def.thruster_name).strip_edges()
		if thruster_name == "":
			thruster_name = "Thruster"
		var socket: Node3D = _resolve_thruster_socket(visuals, thruster_def, thruster_name)
		if socket == null:
			push_warning("Ship thruster marker not found for '%s': %s" % [thruster_name, String(thruster_def.marker_path)])
			continue
		var particles_parent: Node3D = _resolve_thruster_particles_parent(socket, thruster_name)

		if thruster_def.mesh != null:
			var mesh_instance: MeshInstance3D = MeshInstance3D.new()
			mesh_instance.name = thruster_name
			var runtime_mesh: Mesh = thruster_def.mesh.duplicate(true) as Mesh
			mesh_instance.mesh = runtime_mesh if runtime_mesh != null else thruster_def.mesh
			socket.add_child(mesh_instance)
			mesh_instance.transform = Transform3D.IDENTITY
			if absf(thruster_def.scale_multiplier - 1.0) > 0.001:
				mesh_instance.scale *= thruster_def.scale_multiplier

			var runtime_material: Material = null
			if thruster_def.material != null:
				runtime_material = thruster_def.material.duplicate(true) as Material
			elif mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0:
				var embedded: Material = mesh_instance.mesh.surface_get_material(0)
				if embedded != null:
					runtime_material = embedded.duplicate(true) as Material
			if runtime_material != null:
				mesh_instance.set_surface_override_material(0, runtime_material)

			var base_material: BaseMaterial3D = mesh_instance.get_active_material(0) as BaseMaterial3D
			if base_material != null:
				var mat_copy: BaseMaterial3D = base_material.duplicate(true) as BaseMaterial3D
				if mat_copy != null:
					mat_copy.albedo_color = thruster_def.color
					mat_copy.emission_enabled = true
					mat_copy.emission = thruster_def.emission_color
					mat_copy.emission_energy_multiplier = thruster_def.emission_energy
					mesh_instance.set_surface_override_material(0, mat_copy)
					_runtime_thruster_materials.append(mat_copy)

			_runtime_thruster_nodes.append(mesh_instance)

		var particles_scene: PackedScene = thruster_def.particles_scene
		if particles_scene == null:
			continue
		var particles: GPUParticles3D = particles_scene.instantiate() as GPUParticles3D
		if particles == null:
			continue
		particles.name = "%sParticles" % thruster_name
		particles_parent.add_child(particles)
		particles.transform = Transform3D.IDENTITY
		particles.emitting = false
		_apply_thruster_particles_visuals(particles, thruster_def)
		_runtime_thruster_particles.append(particles)

func _resolve_thruster_socket(visuals: ShipVisualDef, thruster_def: ShipThrusterDef, thruster_name: String) -> Node3D:
	var by_path: Node3D = _resolve_layout_socket_with_root(visuals.thrusters_root_path, thruster_def.marker_path)
	if by_path != null:
		return by_path
	if thruster_name == "":
		return null
	var thrusters_root: Node3D = _resolve_layout_socket(visuals.thrusters_root_path)
	if thrusters_root != null:
		var by_name_under_root: Node3D = thrusters_root.get_node_or_null(NodePath(thruster_name)) as Node3D
		if by_name_under_root != null:
			return by_name_under_root
	if _runtime_layout_root != null:
		return _runtime_layout_root.find_child(thruster_name, true, false) as Node3D
	return null

func _resolve_thruster_particles_parent(socket: Node3D, thruster_name: String) -> Node3D:
	if socket == null:
		return null
	if thruster_name != "":
		var child_anchor: Node3D = socket.get_node_or_null(NodePath(thruster_name)) as Node3D
		if child_anchor != null:
			return child_anchor
	var particles_socket: Node3D = socket.get_node_or_null(NodePath("ParticlesSocket")) as Node3D
	if particles_socket != null:
		return particles_socket
	var particles_marker: Node3D = socket.get_node_or_null(NodePath("Particles")) as Node3D
	if particles_marker != null:
		return particles_marker
	return socket

func _apply_thruster_particles_visuals(particles: GPUParticles3D, thruster_def: ShipThrusterDef) -> void:
	if particles == null:
		return
	var draw_mesh: Mesh = particles.draw_pass_1
	if draw_mesh == null:
		return
	var mesh_copy: Mesh = draw_mesh.duplicate(true) as Mesh
	if mesh_copy == null:
		mesh_copy = draw_mesh
	particles.draw_pass_1 = mesh_copy
	if mesh_copy.get_surface_count() <= 0:
		return
	var base_material: BaseMaterial3D = mesh_copy.surface_get_material(0) as BaseMaterial3D
	if base_material == null:
		return
	var mat_copy: BaseMaterial3D = base_material.duplicate(true) as BaseMaterial3D
	if mat_copy == null:
		return
	mat_copy.albedo_color = thruster_def.color
	mat_copy.emission_enabled = true
	mat_copy.emission = thruster_def.emission_color
	mat_copy.emission_energy_multiplier = thruster_def.emission_energy
	mesh_copy.surface_set_material(0, mat_copy)

func _build_runtime_shield_mesh(shield_def: ShipShieldDef) -> void:
	shield_mesh = null
	_shield_mat = null
	if shield_def == null or shield_def.mesh == null:
		return
	var socket: Node3D = _resolve_layout_socket(shield_def.marker_path)
	if socket == null:
		push_warning("Ship shield marker not found: %s" % String(shield_def.marker_path))
		return

	var runtime_mesh: Mesh = shield_def.mesh.duplicate(true) as Mesh
	if runtime_mesh == null:
		runtime_mesh = shield_def.mesh
	if runtime_mesh is SphereMesh:
		var sphere: SphereMesh = runtime_mesh as SphereMesh
		if sphere != null:
			var base_radius: float = max(sphere.radius, 0.0001)
			if shield_def.radius > 0.0:
				sphere.radius = shield_def.radius
				if shield_def.height > 0.0:
					sphere.height = shield_def.height
				else:
					sphere.height = sphere.height * (shield_def.radius / base_radius)
			elif shield_def.height > 0.0:
				sphere.height = shield_def.height

	var runtime_shield: MeshInstance3D = MeshInstance3D.new()
	runtime_shield.name = String(shield_def.shield_name) if String(shield_def.shield_name).strip_edges() != "" else "RuntimeShield"
	runtime_shield.mesh = runtime_mesh

	if shield_def.shader_material != null:
		runtime_shield.set_surface_override_material(0, shield_def.shader_material.duplicate(true) as Material)
	elif shield_def.shader_definition != null:
		var shader_material: ShaderMaterial = ShaderMaterial.new()
		shader_material.shader = shield_def.shader_definition
		runtime_shield.set_surface_override_material(0, shader_material)
	elif shield_def.material != null:
		runtime_shield.set_surface_override_material(0, shield_def.material.duplicate(true) as Material)

	socket.add_child(runtime_shield)
	runtime_shield.transform = Transform3D.IDENTITY

	shield_mesh = runtime_shield
	_initialize_shield_material()
	if _shield_mat != null:
		var color: Color = shield_def.color
		_shield_mat.albedo_color = Color(color.r, color.g, color.b, _shield_mat.albedo_color.a)
		_shield_mat.emission_enabled = true
		_shield_mat.emission = shield_def.emission_color
		_shield_mat.emission_energy_multiplier = shield_def.emission_energy
		_shield_base_albedo = _shield_mat.albedo_color

func _initialize_shield_material() -> void:
	if shield_mesh == null:
		return
	if _shield_mat != null:
		return
	var mat: Material = shield_mesh.get_active_material(0)
	var standard_mat: StandardMaterial3D = mat as StandardMaterial3D
	if standard_mat == null:
		return
	_shield_mat = standard_mat.duplicate()
	_shield_base_albedo = _shield_mat.albedo_color
	if _shield_mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
		_shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shield_mesh.set_surface_override_material(0, _shield_mat)

func _update_shield_mesh_visibility() -> void:
	if shield_mesh == null:
		return
	_initialize_shield_material()
	var ratio: float = 0.0
	if eff_max_shield > 0.0:
		ratio = clamp(shield / eff_max_shield, 0.0, 1.0)
	if _shield_mat != null:
		var color: Color = _shield_base_albedo
		color.a = ratio
		_shield_mat.albedo_color = color
	shield_mesh.visible = ratio > 0.0

func _on_stats_changed(_affected: Array[Stat]) -> void:
	_refresh_effective_stats()

func _on_heal_hull_requested(amount: float, percent: float) -> void:
	var flat: float = max(0.0, amount)

	var pct_clamped: float = clamp(percent, 0.0, 1.0)
	var heal_from_percent: float = eff_max_hull * pct_clamped
	var total_heal: float = flat + heal_from_percent
	
	var overheal_cap_mult: float = 1.0 + max(overheal, 0.0)
	var cap: float = eff_max_hull * overheal_cap_mult
	
	hull = min(cap, hull + total_heal)
	update_alarms()

func _die() -> void:
	if _dead:
		return
	_dead = true
	_switch_alarm(null)
	if shield_low_alarm_audio != null and shield_low_alarm_audio.playing:
		shield_low_alarm_audio.stop()
	if hull_low_alarm_audio != null and hull_low_alarm_audio.playing:
		hull_low_alarm_audio.stop()
	
	var mode = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if mode == Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_VISIBLE)

	if has_node("CollisionShape3D"):
		var col: CollisionShape3D = $CollisionShape3D
		col.disabled = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	
	if explosion_scene != null:
		var fx: Node3D = explosion_scene.instantiate() as Node3D
		var audio: AudioStreamPlayer3D = fx.get_node_or_null("AudioStreamPlayer3D")
		if audio != null:
			audio.volume_db = -10.0
		fx.global_transform = global_transform
		var parent_for_fx: Node = get_parent() if get_parent() != null else get_tree().root
		parent_for_fx.add_child(fx)
	
	visible = false
	
	var turret_controller: TurretController = $TurretController
	turret_controller.queue_free()
	
	var t: SceneTreeTimer = get_tree().create_timer(return_to_menu_delay)
	await t.timeout
	
	GameFlow.player_died()
	
	queue_free()
