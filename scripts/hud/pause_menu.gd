extends CanvasLayer
class_name PauseMenu

@export var weapon_defs: Array[WeaponDef] = []

@onready var root: Control = $ScreenRoot
@onready var btn_resume: Button = $ScreenRoot/CenterContainer/VBox/Resume
@onready var btn_restart: Button = $ScreenRoot/CenterContainer/VBox/Restart
@onready var btn_menu: Button = $ScreenRoot/CenterContainer/VBox/MainMenu
@onready var btn_quit: Button = $ScreenRoot/CenterContainer/VBox/Quit
@onready var label_gun: Label = $ScreenRoot/MarginContainer/CenterContainer/VBoxContainer/Label
@onready var btn_add_pulse: Button = $ScreenRoot/MarginContainer/CenterContainer/VBoxContainer/AddPulse
@onready var btn_rem_pulse: Button = $ScreenRoot/MarginContainer/CenterContainer/VBoxContainer/RemovePulse
@onready var btn_add_laser: Button = $ScreenRoot/MarginContainer/CenterContainer/VBoxContainer/AddLaser
@onready var btn_rem_laser: Button = $ScreenRoot/MarginContainer/CenterContainer/VBoxContainer/RemoveLaser

var num_guns: int = 0
var _weapon_defs: Dictionary[String, WeaponDef] = {}

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
	
	PauseManager.paused_changed.connect(_on_paused_changed)
	EventBus.weapons_changed.connect(_set_num_guns)
	
	for d in weapon_defs:
		_weapon_defs[d.weapon_id] = d

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

func _on_add_pulse_clicked() -> void:
	EventBus.add_gun_requested.emit(_weapon_defs["pulse_mk1"])

func _on_rem_pulse_clicked() -> void:
	EventBus.rem_gun_requested.emit(-1, _weapon_defs["pulse_mk1"])

func _on_add_laser_clicked() -> void:
	EventBus.add_gun_requested.emit(_weapon_defs["laser_mk1"])

func _on_rem_laser_clicked() -> void:
	EventBus.rem_gun_requested.emit(-1, _weapon_defs["laser_mk1"])

func _set_num_guns(weapons: Array[WeaponDef]) -> void:
	num_guns = weapons.size()
	label_gun.text = "Guns: %d" % num_guns
