extends Node3D

@onready var menu: Control = $MainMenuOverlay
@onready var hud: CanvasLayer = $HUD

func _ready() -> void:
  menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
  menu.visible = true
  hud.visible = false
  get_tree().paused = true
  Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
  menu.practice_requested.connect(_on_start_pressed)

func _on_start_pressed() -> void:
  menu.visible = false
  hud.visible = true
  get_tree().paused = false
  Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
