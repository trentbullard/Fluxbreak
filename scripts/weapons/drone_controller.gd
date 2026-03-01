extends Node3D
class_name DroneController

enum DroneState {
	DOCKED,
	ACTIVE,
	RETURNING,
	CHARGING,
}

var team_id: int = 0
var owner_ship: Node = null
var weapon_owner: Node = null
var turret_owner: PlayerTurret = null
var turret_controller: TurretController = null
var bay_weapon: DroneBayWeaponDef = null
var drone_weapon: WeaponDef = null
var slot_index: int = -1
var runtime_context: Dictionary = {}
var state: DroneState = DroneState.DOCKED
var charge_remaining: float = 0.0
var return_remaining: float = 0.0
var _target_ref: WeakRef = null

func _ready() -> void:
	if _target_ref == null:
		_target_ref = weakref(null)

func configure_drone(context: Dictionary) -> void:
	runtime_context = context.duplicate()
	team_id = int(runtime_context.get("team_id", 0))
	owner_ship = runtime_context.get("owner_ship", null) as Node
	weapon_owner = runtime_context.get("weapon_owner", null) as Node
	turret_owner = runtime_context.get("turret_owner", null) as PlayerTurret
	turret_controller = runtime_context.get("turret_controller", null) as TurretController
	bay_weapon = runtime_context.get("bay_weapon", null) as DroneBayWeaponDef
	drone_weapon = runtime_context.get("drone_weapon", null) as WeaponDef
	slot_index = int(runtime_context.get("slot_index", -1))

func command_launch(target: Node3D, active_charge_time: float) -> void:
	state = DroneState.ACTIVE
	charge_remaining = max(0.0, active_charge_time)
	return_remaining = 0.0
	command_set_target(target)

func command_set_target(target: Node3D) -> void:
	_target_ref = weakref(target) if target != null else weakref(null)

func command_begin_return(redock_time: float) -> void:
	state = DroneState.RETURNING
	charge_remaining = 0.0
	return_remaining = max(0.0, redock_time)
	command_set_target(null)

func command_dock() -> void:
	state = DroneState.DOCKED
	charge_remaining = 0.0
	return_remaining = 0.0
	command_set_target(null)

func command_sync_timers(active_charge_time: float, redock_time: float) -> void:
	charge_remaining = max(0.0, active_charge_time)
	return_remaining = max(0.0, redock_time)

func get_target() -> Node3D:
	return _target_ref.get_ref() as Node3D if _target_ref != null else null
