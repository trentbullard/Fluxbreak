# scripts/hud/pause_menu.gd (godot 4.5)
extends CanvasLayer
class_name PauseMenu

@export var weapon_defs: Array[WeaponDef] = []
@export var bulkhead_upgrade: Upgrade
@export var shield_upgrade: Upgrade
@export var targeting_upgrade: Upgrade
@export var systems_upgrade: Upgrade
@export var salvage_upgrade: Upgrade
@export var thrusters_upgrade: Upgrade

# --- Costs ---
@export var pulse_weapon_cost: int = 1500
@export var laser_weapon_cost: int = 1500
@export var bulkhead_upgrade_cost: int = 1000
@export var shield_upgrade_cost: int = 1000
@export var targeting_upgrade_cost: int = 1000
@export var systems_upgrade_cost: int = 1000
@export var salvage_upgrade_cost: int = 1000
@export var thrusters_upgrade_cost: int = 1000
@export var refund_on_removal: bool = true
@export var remove_refund_pct: float = 0.50
@export var repair_cost: int = 500

@onready var root: Control = $ScreenRoot
@onready var btn_resume: Button = $ScreenRoot/CenterContainer/VBox/Resume
@onready var btn_restart: Button = $ScreenRoot/CenterContainer/VBox/Restart
@onready var btn_menu: Button = $ScreenRoot/CenterContainer/VBox/MainMenu
@onready var btn_quit: Button = $ScreenRoot/CenterContainer/VBox/Quit
@onready var btn_repair: Button = $ScreenRoot/Upgrades/CenterContainer/VBoxContainer/Repair
@onready var label_gun: Label = $ScreenRoot/MarginContainer/CenterContainer/VBoxContainer/Label
@onready var btn_add_pulse: Button = $ScreenRoot/MarginContainer/CenterContainer/VBoxContainer/AddPulse
@onready var btn_rem_pulse: Button = $ScreenRoot/MarginContainer/CenterContainer/VBoxContainer/RemovePulse
@onready var btn_add_laser: Button = $ScreenRoot/MarginContainer/CenterContainer/VBoxContainer/AddLaser
@onready var btn_rem_laser: Button = $ScreenRoot/MarginContainer/CenterContainer/VBoxContainer/RemoveLaser
@onready var btn_bulkhead: Button = $ScreenRoot/Upgrades/CenterContainer/VBoxContainer/Bulkhead
@onready var btn_shield: Button = $ScreenRoot/Upgrades/CenterContainer/VBoxContainer/Shield
@onready var btn_targeting: Button = $ScreenRoot/Upgrades/CenterContainer/VBoxContainer/Targeting
@onready var btn_systems: Button = $ScreenRoot/Upgrades/CenterContainer/VBoxContainer/Systems
@onready var btn_salvage: Button = $ScreenRoot/Upgrades/CenterContainer/VBoxContainer/Salvage
@onready var btn_thrusters: Button = $ScreenRoot/Upgrades/CenterContainer/VBoxContainer/Thrusters
@onready var label_stats: Label = $ScreenRoot/Upgrades/CenterContainer/VBoxContainer/Label

var num_guns: int = 0
var max_hull: float = 0.0
var max_shield: float = 0.0
var accuracy: float = 0.0
var _weapon_defs: Dictionary[String, WeaponDef] = {}
var _current_nanobots: int = 0.0

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	btn_resume.pressed.connect(_on_resume_clicked)
	btn_restart.pressed.connect(_on_restart_clicked)
	btn_menu.pressed.connect(_on_menu_clicked)
	btn_quit.pressed.connect(_on_quit_clicked)
	btn_add_pulse.pressed.connect(_on_add_pulse_clicked)
	btn_rem_pulse.pressed.connect(_on_rem_pulse_clicked)
	btn_add_laser.pressed.connect(_on_add_laser_clicked)
	btn_rem_laser.pressed.connect(_on_rem_laser_clicked)
	btn_bulkhead.pressed.connect(_on_bulkhead_clicked)
	btn_shield.pressed.connect(_on_shield_clicked)
	btn_targeting.pressed.connect(_on_targeting_clicked)
	btn_systems.pressed.connect(_on_systems_clicked)
	btn_salvage.pressed.connect(_on_salvage_clicked)
	btn_thrusters.pressed.connect(_on_thrusters_clicked)
	btn_repair.pressed.connect(_on_repair_clicked)
	
	PauseManager.paused_changed.connect(_on_paused_changed)
	EventBus.weapons_changed.connect(_set_num_guns)
	RunState.nanobots_updated.connect(_on_nanobots_updated)
	
	for d in weapon_defs:
		_weapon_defs[d.weapon_id] = d
	
	_refresh_affordability()

func _on_paused_changed(is_paused: bool) -> void:
	visible = is_paused
	if is_paused:
		btn_resume.grab_focus()

func _on_resume_clicked() -> void:
	PauseManager.resume_requested.emit()

func _on_restart_clicked() -> void:
	visible = false
	PauseManager.restart_requested.emit()

func _on_menu_clicked() -> void:
	visible = false
	PauseManager.menu_requested.emit()

func _on_quit_clicked() -> void:
	PauseManager.quit_requested.emit()

# --- Purchases ---

func _attempt_purchase(cost: int, action: Callable) -> void:
	if cost <= 0 or _current_nanobots >= cost:
		if cost > 0:
			_current_nanobots -= cost
			RunState.nanobots_spent.emit(cost)
		action.call()
		_refresh_affordability()
	else:
		pass

func _on_add_pulse_clicked() -> void:
	_attempt_purchase(pulse_weapon_cost, func() -> void:
		EventBus.add_gun_requested.emit(_weapon_defs["pulse_mk1"])
	)
	pulse_weapon_cost *= 1.5
	btn_add_pulse.text = "+Pulse (%d)" % pulse_weapon_cost

func _on_rem_pulse_clicked() -> void:
	EventBus.rem_gun_requested.emit(-1, _weapon_defs["pulse_mk1"])

func _on_add_laser_clicked() -> void:
	_attempt_purchase(laser_weapon_cost, func() -> void:
		EventBus.add_gun_requested.emit(_weapon_defs["laser_mk1"])
	)
	laser_weapon_cost *= 1.5
	btn_add_laser.text = "+Laser (%d)" % laser_weapon_cost

func _on_rem_laser_clicked() -> void:
	EventBus.rem_gun_requested.emit(-1, _weapon_defs["laser_mk1"])

func _set_num_guns(weapons: Array[WeaponDef]) -> void:
	num_guns = weapons.size()
	label_gun.text = "Guns: %d" % num_guns

func _on_bulkhead_clicked() -> void:
	_attempt_purchase(bulkhead_upgrade_cost, func() -> void:
		EventBus.add_bulkhead_requested.emit(bulkhead_upgrade)
	)
	bulkhead_upgrade_cost *= 1.5
	btn_bulkhead.text = "Bulkhead (%d)" % bulkhead_upgrade_cost

func _on_shield_clicked() -> void:
	_attempt_purchase(shield_upgrade_cost, func() -> void:
		EventBus.add_shield_requested.emit(shield_upgrade)
	)
	shield_upgrade_cost *= 1.5
	btn_shield.text = "Shield (%d)" % shield_upgrade_cost

func _on_targeting_clicked() -> void:
	_attempt_purchase(targeting_upgrade_cost, func() -> void:
		EventBus.add_targeting_requested.emit(targeting_upgrade)
	)
	targeting_upgrade_cost *= 1.5
	btn_targeting.text = "Targeting (%d)" % targeting_upgrade_cost

func _on_systems_clicked() -> void:
	_attempt_purchase(systems_upgrade_cost, func() -> void:
		EventBus.add_systems_requested.emit(systems_upgrade)
	)
	systems_upgrade_cost *= 1.5
	btn_systems.text = "Systems (%d)" % systems_upgrade_cost

func _on_salvage_clicked() -> void:
	_attempt_purchase(salvage_upgrade_cost, func() -> void:
		EventBus.add_salvage_requested.emit(salvage_upgrade)
	)
	salvage_upgrade_cost *= 1.5
	btn_salvage.text = "Salvage (%d)" % salvage_upgrade_cost

func _on_thrusters_clicked() -> void:
	_attempt_purchase(thrusters_upgrade_cost, func() -> void:
		EventBus.add_thrusters_requested.emit(thrusters_upgrade)
	)
	thrusters_upgrade_cost *= 1.5
	btn_thrusters.text = "Thrusters (%d)" % thrusters_upgrade_cost

func _on_repair_clicked() -> void:
	_attempt_purchase(repair_cost, func() -> void:
		EventBus.heal_hull_requested.emit(25.0, 0.0)
	)
	# Repair cost does not scale (leave constant). Update button text in case design changes later.
	if btn_repair:
		btn_repair.text = "Repair (%d)" % repair_cost

func _refresh_affordability() -> void:
	var nb: int = _current_nanobots
	if btn_add_pulse:
		btn_add_pulse.disabled = (pulse_weapon_cost > nb)
	if btn_add_laser:
		btn_add_laser.disabled = (laser_weapon_cost > nb)
	if btn_bulkhead:
		btn_bulkhead.disabled = (bulkhead_upgrade_cost > nb)
	if btn_shield:
		btn_shield.disabled = (shield_upgrade_cost > nb)
	if btn_targeting:
		btn_targeting.disabled = (targeting_upgrade_cost > nb)
	if btn_systems:
		btn_systems.disabled = (systems_upgrade_cost > nb)
	if btn_thrusters:
		btn_thrusters.disabled = (thrusters_upgrade_cost > nb)
	if btn_salvage:
		btn_salvage.disabled = (salvage_upgrade_cost > nb)
	if btn_repair:
		btn_repair.disabled = (repair_cost > nb)

func _set_stat_label() -> void:
	label_stats.text = "Max Hull: %f\nMax Shield: %f\nAccuracy: %f" % [max_hull, max_shield, accuracy]

func _on_nanobots_updated(amount: int) -> void:
	_current_nanobots = amount
	_refresh_affordability()
