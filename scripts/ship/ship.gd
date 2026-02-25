# scripts/ship/ship.gd  (Godot 4.5)
extends RigidBody3D
class_name Ship

@export var loadout: ShipLoadoutDef
@export_range(0, 16, 1) var starting_weapons: int = 1
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

@onready var thruster1: MeshInstance3D = $VisualRoot/Thruster
@onready var thruster2: MeshInstance3D = $VisualRoot/Thruster2
@onready var thruster_mat1: StandardMaterial3D = thruster1.get_active_material(0).duplicate()
@onready var thruster_mat2: StandardMaterial3D = thruster2.get_active_material(0).duplicate()
@onready var thruster_particles1: GPUParticles3D = $VisualRoot/ThrusterParticles1
@onready var thruster_particles2: GPUParticles3D = $VisualRoot/ThrusterParticles2
@onready var camera_pivot: Marker3D = $CameraPivot
@onready var hardpoint_manager: TurretHardpointManager = $TurretController/HardpointManager
@onready var stat_aggregator: StatAggregator = $StatAggregator
const Stat = StatTypes.Stat
@onready var shield_hit_audio: AudioStreamPlayer3D = $Audio/ShieldHitAudio
@onready var hull_hit_audio: AudioStreamPlayer3D = $Audio/HullHitAudio
@onready var shield_mesh: MeshInstance3D = $VisualRoot/Shield
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

var hull: float = 100.0
var shield: float = 100.0
var _target_ang_rate: Vector3 = Vector3.ZERO   # desired ω from input (rad/s)
var _throttle_input: float = 0.0
var _thrusting: bool = false
var _reversing: bool = false
var _boosting: bool = false
var _dead: bool = false
var _regen_timer: Timer
var _stack: Array[WeaponDef] = []
var _nanobots: int = 0
var _hull_repair_cooldown_remaining: float = 0.0
var _shield_mat: StandardMaterial3D
var _shield_base_albedo: Color = Color.WHITE
var _emission_value: float = 0.0

func _ready() -> void:
	add_to_group("player")
	reconfigure_from_selected_pilot()
	RunState.start_run()
	_initialize_shield_material()
	_initialize_thruster_material()
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
		hardpoint_manager.apply_loadout(loadout, starting_weapons)

func reconfigure_from_selected_pilot(reset_current_health: bool = true) -> void:
	_apply_selected_defs()
	_refresh_effective_stats()
	if reset_current_health:
		hull = eff_max_hull
		shield = eff_max_shield
	_update_shield_mesh_visibility()
	update_alarms()
	if hardpoint_manager != null:
		hardpoint_manager.apply_loadout(loadout, starting_weapons)

func _apply_selected_defs() -> void:
	var selected_ship_def: ShipDef = ship_override
	var selected_pilot: PilotDef = _resolve_selected_pilot()

	if selected_pilot != null and selected_pilot.ship != null:
		selected_ship_def = selected_pilot.ship

	if selected_ship_def != null:
		_apply_ship_def(selected_ship_def)

	if selected_pilot != null:
		_apply_pilot_def(selected_pilot)
	else:
		_apply_pilot_stat_profile(null)

func _resolve_selected_pilot() -> PilotDef:
	if pilot_override != null:
		return pilot_override
	return GameFlow.selected_pilot

func _apply_pilot_def(def: PilotDef) -> void:
	if def == null:
		_apply_pilot_stat_profile(null)
		return

	if def.loadout_override != null:
		loadout = def.loadout_override
	starting_weapons = max(0, def.get_effective_starting_weapons(starting_weapons))

	if hardpoint_manager != null and def.mount_layout_policy_override != null:
		hardpoint_manager.policy = def.mount_layout_policy_override

	_apply_pilot_stat_profile(def)

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

func _apply_ship_def(def: ShipDef) -> void:
	if def == null:
		return

	if def.loadout != null:
		loadout = def.loadout
	starting_weapons = max(def.starting_weapons, 0)
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
	base_spaciness = def.base_spaciness
	coast_brake_accel = def.coast_brake_accel
	lateral_brake_accel = def.lateral_brake_accel
	vertical_brake_accel = def.vertical_brake_accel
	turn_assist_brake_bonus = def.turn_assist_brake_bonus
	no_throttle_turn_assist_bonus = def.no_throttle_turn_assist_bonus
	counter_thrust_brake_mult = def.counter_thrust_brake_mult
	thrust_drag_scale = def.thrust_drag_scale
	coast_drag_scale = def.coast_drag_scale

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
	hardpoint_manager.realign_and_apply(_stack)

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
	
	if thruster_mat1 and thruster_mat2:
		thruster_mat1.emission_energy_multiplier = _emission_value
		thruster_mat2.emission_energy_multiplier = _emission_value

	if thruster_particles1 and thruster_particles2:
		var forward_vel: float = linear_velocity.dot(-transform.basis.z)
		var main_emit: bool = _thrusting and not _reversing
		var particle_cap: float = max(eff_max_speed_forward * (eff_boost_mult if _boosting else 1.0), 1.0)

		thruster_particles1.emitting = main_emit
		thruster_particles2.emitting = main_emit
		thruster_particles1.amount_ratio = clamp(max(forward_vel, 0.0) / particle_cap, 0.15, 1.0)
		thruster_particles2.amount_ratio = clamp(max(forward_vel, 0.0) / particle_cap, 0.15, 1.0)

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

	var lv_local: Vector3 = basis_inv * state.linear_velocity
	var drag_speed: float = lv_local.length()
	if drag_speed > 0.0:
		var drag_scale: float = thrust_drag_scale if absf(_throttle_input) > 0.001 else coast_drag_scale
		var drag_coeff: float = max(eff_drag, 0.0) * max(drag_scale, 0.0)
		var drag_factor: float = 1.0 / (1.0 + drag_coeff * drag_speed * dt)
		lv_local *= drag_factor

	var assist_scale: float = _get_assist_scale()
	var desired_forward: float = 0.0
	var forward_rate: float = max(coast_brake_accel * assist_scale, 0.0)
	var boost: float = eff_boost_mult if _boosting else 1.0

	if _throttle_input > 0.0:
		desired_forward = eff_max_speed_forward
		forward_rate = max(eff_accel_forward * boost, 0.0)
	elif _throttle_input < 0.0:
		desired_forward = -eff_max_speed_reverse
		forward_rate = max(eff_accel_reverse * boost, 0.0)

	var forward_speed: float = -lv_local.z
	if desired_forward != 0.0 and signf(desired_forward) != signf(forward_speed):
		forward_rate *= max(counter_thrust_brake_mult, 0.0)

	forward_speed = move_toward(forward_speed, desired_forward, forward_rate * dt)
	forward_speed = clamp(forward_speed, -eff_max_speed_reverse, eff_max_speed_forward)
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

func apply_damage(amount: float) -> void:
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
		hull -= remaining
		hull_damage = remaining
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
		_update_shield_mesh_visibility()
		return
	# Pull effective values once.
	eff_max_hull = aggr.compute(Stat.MAX_HULL, max_hull)
	eff_max_shield = aggr.compute(Stat.MAX_SHIELD, max_shield)
	eff_shield_regen = aggr.compute(Stat.SHIELD_REGEN, shield_regen)
	eff_evasion = clamp(aggr.compute(Stat.EVASION_BASE, base_evasion), 0.0, 1.0)
	eff_damage_taken_mult = aggr.compute(Stat.DAMAGE_TAKEN_MULT, 1.0)
	eff_max_speed_forward = max(aggr.compute(Stat.MAX_SPEED_FORWARD, max_speed_forward), 0.0)
	eff_max_speed_reverse = max(aggr.compute(Stat.MAX_SPEED_REVERSE, max_speed_reverse), 0.0)
	eff_accel_forward = max(aggr.compute(Stat.ACCEL_FORWARD, accel_forward), 0.0)
	eff_accel_reverse = max(aggr.compute(Stat.ACCEL_REVERSE, accel_reverse), 0.0)
	eff_boost_mult = max(aggr.compute(Stat.BOOST_MULT, boost_mult), 0.0)
	eff_drag = max(aggr.compute(Stat.DRAG, drag), 0.0)
	eff_max_ang_rate = Vector3(
		max(aggr.compute(Stat.ANGULAR_RATE_PITCH, max_ang_rate.x), 0.0),
		max(aggr.compute(Stat.ANGULAR_RATE_YAW, max_ang_rate.y), 0.0),
		max(aggr.compute(Stat.ANGULAR_RATE_ROLL, max_ang_rate.z), 0.0))
	eff_angular_accel = Vector3(
		max(aggr.compute(Stat.ANGULAR_ACCEL_PITCH, angular_accel.x), 0.0),
		max(aggr.compute(Stat.ANGULAR_ACCEL_YAW, angular_accel.y), 0.0),
		max(aggr.compute(Stat.ANGULAR_ACCEL_ROLL, angular_accel.z), 0.0))
	eff_pickup_range = aggr.compute(Stat.PICKUP_RANGE, pickup_range)
	eff_nanobot_gain_mult = aggr.compute(Stat.NANOBOT_GAIN_MULT, nanobot_gain_mult)
	eff_score_gain_mult = aggr.compute(Stat.SCORE_GAIN_MULT, score_gain_mult)
	_update_shield_mesh_visibility()

func _initialize_shield_material() -> void:
	if shield_mesh == null:
		return
	if _shield_mat != null:
		return
	var mat: StandardMaterial3D = shield_mesh.get_active_material(0)
	if mat == null:
		return
	_shield_mat = mat.duplicate()
	_shield_base_albedo = _shield_mat.albedo_color
	if _shield_mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
		_shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shield_mesh.set_surface_override_material(0, _shield_mat)

func _initialize_thruster_material() -> void:
	thruster1.set_surface_override_material(0, thruster_mat1)
	thruster2.set_surface_override_material(0, thruster_mat2)

func _update_shield_mesh_visibility() -> void:
	if shield_mesh == null:
		return
	_initialize_shield_material()
	if _shield_mat == null:
		return
	var ratio: float = 0.0
	if eff_max_shield > 0.0:
		ratio = clamp(shield / eff_max_shield, 0.0, 1.0)
	var color: Color = _shield_base_albedo
	color.a = ratio
	_shield_mat.albedo_color = color
	shield_mesh.visible = ratio > 0.0

func _on_stats_changed(_affected: Array[int]) -> void:
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
