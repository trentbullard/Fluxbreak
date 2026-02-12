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

@export var max_speed_forward := 400.0 # hard cap on forward speed
@export var max_speed_reverse := 60.0  # hard cap on reverse speed
@export var drag: float = 0.01         # higher is faster slowdown
@export var accel_forward := 100.0     # the amount of acceleration being applied by thrust (fighting drag)
@export var accel_reverse := 60.0      # see above
@export var boost_mult := 1.5          # multiplies accel

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
var _target_ang_rate := Vector3.ZERO   # desired ω from input (rad/s)
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
	_apply_selected_defs()
	RunState.start_run()
	_refresh_effective_stats()
	hull = eff_max_hull
	shield = eff_max_shield
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
	if hardpoint_manager != null:
		hardpoint_manager.apply_loadout(loadout, starting_weapons)

func _apply_selected_defs() -> void:
	var selected_ship_def: ShipDef = ship_override

	var selected_pilot: PilotDef = pilot_override
	if selected_pilot == null:
		selected_pilot = GameFlow.selected_pilot

	if selected_pilot != null and selected_pilot.ship != null:
		selected_ship_def = selected_pilot.ship

	if selected_ship_def != null:
		_apply_ship_def(selected_ship_def)

func _apply_ship_def(def: ShipDef) -> void:
	if def == null:
		return

	if def.loadout != null:
		loadout = def.loadout
	starting_weapons = def.starting_weapons
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
	
	var thrusting: bool = Input.is_action_pressed("thrust")
	var boosting: bool = Input.is_action_pressed("boost")
	
	var target: float = 0.0
	if thrusting:
		target = 1.15 if boosting else 1.0
	
	_emission_value = lerp(_emission_value, target, delta * 8.0)
	
	if thruster_mat1 and thruster_mat2:
		thruster_mat1.emission_energy_multiplier = _emission_value
		thruster_mat2.emission_energy_multiplier = _emission_value

	if thruster_particles1 and thruster_particles2:
		var reverse_key: bool = Input.is_action_pressed("reverse")
		var forward_vel: float = linear_velocity.dot(-transform.basis.z)
		var main_emit: bool = thrusting and not reverse_key

		thruster_particles1.emitting = main_emit
		thruster_particles2.emitting = main_emit
		thruster_particles1.amount_ratio = clamp(max(forward_vel, 0.0) / (max_speed_forward * boost_mult), 0.15, 1.0)
		thruster_particles2.amount_ratio = clamp(max(forward_vel, 0.0) / (max_speed_forward * boost_mult), 0.15, 1.0)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt: float = state.step
	
	var basis_inv: Basis = transform.basis.inverse()
	var w_local: Vector3 = basis_inv * state.angular_velocity
	
	var next_local: Vector3 = Vector3(
		move_toward(w_local.x, _target_ang_rate.x, angular_accel.x * dt),
		move_toward(w_local.y, _target_ang_rate.y, angular_accel.y * dt),
		move_toward(w_local.z, _target_ang_rate.z, angular_accel.z * dt)
	)
	
	state.angular_velocity = transform.basis * next_local
	
	var lv: Vector3 = state.linear_velocity
	var drag_force: Vector3
	
	if Input.is_action_pressed("thrust") or Input.is_action_pressed("reverse"):
		drag_force = -lv * lv.length() * 0.001
	else:
		drag_force = -lv * lv.length() * drag
	
	state.apply_central_force(drag_force)

func set_target_angular_rates(rad_per_sec: Vector3) -> void:
	_target_ang_rate = Vector3(
		clamp(rad_per_sec.x, -max_ang_rate.x, max_ang_rate.x),
		clamp(rad_per_sec.y, -max_ang_rate.y, max_ang_rate.y),
		clamp(rad_per_sec.z, -max_ang_rate.z, max_ang_rate.z)
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
	var boost := boost_mult if Input.is_action_pressed("boost") else 1.0
	
	if Input.is_action_pressed("thrust"):
		var forward_vel: float = linear_velocity.dot(-transform.basis.z)
		if forward_vel < max_speed_forward:
			apply_central_force(-transform.basis.z * accel_forward * boost)
	if Input.is_action_pressed("reverse"):
		var reverse_vel: float = linear_velocity.dot(transform.basis.z)
		if reverse_vel < max_speed_reverse:
			apply_central_force(transform.basis.z * accel_reverse * boost)

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
		eff_max_speed_forward = max_speed_forward
		eff_max_speed_reverse = max_speed_reverse
		eff_accel_forward = accel_forward
		eff_accel_reverse = accel_reverse
		eff_boost_mult = boost_mult
		eff_drag = drag
		eff_max_ang_rate = max_ang_rate
		eff_angular_accel = angular_accel
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
	eff_max_speed_forward = aggr.compute(Stat.MAX_SPEED_FORWARD, max_speed_forward)
	eff_max_speed_reverse = aggr.compute(Stat.MAX_SPEED_REVERSE, max_speed_reverse)
	eff_accel_forward = aggr.compute(Stat.ACCEL_FORWARD, accel_forward)
	eff_accel_reverse = aggr.compute(Stat.ACCEL_REVERSE, accel_reverse)
	eff_boost_mult = aggr.compute(Stat.BOOST_MULT, boost_mult)
	eff_drag = aggr.compute(Stat.DRAG, drag)
	eff_max_ang_rate = Vector3(
		aggr.compute(Stat.ANGULAR_RATE_PITCH, max_ang_rate.x),
		aggr.compute(Stat.ANGULAR_RATE_YAW, max_ang_rate.y),
		aggr.compute(Stat.ANGULAR_RATE_ROLL, max_ang_rate.z))
	eff_angular_accel = Vector3(
		aggr.compute(Stat.ANGULAR_ACCEL_PITCH, angular_accel.x),
		aggr.compute(Stat.ANGULAR_ACCEL_YAW, angular_accel.y),
		aggr.compute(Stat.ANGULAR_ACCEL_ROLL, angular_accel.z))
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
