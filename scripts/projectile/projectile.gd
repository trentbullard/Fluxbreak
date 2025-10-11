extends Area3D
@export var speed: float = 1000
@export var damage: float = 10.0

@onready var life_timer: Timer = $Timer

func _ready() -> void:
	life_timer.timeout.connect(_on_timer_timeout)
	life_timer.start()
	connect("body_entered", Callable(self, "_on_body_entered"))

func _physics_process(delta: float) -> void:
	global_position += -global_transform.basis.z * speed * delta

func _on_body_entered(body: Node) -> void:
	if "apply_damage" in body:
		body.apply_damage(damage)
	queue_free()

func _on_timer_timeout() -> void:
	queue_free()
