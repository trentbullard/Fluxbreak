# RunState.gd (autoload)
extends Node

signal score_changed(total: int, delta: int, reason: String)
signal time_updated(remaining: float)
signal time_over()

var run_score: int = 0
var countdown_time: float = 300.0  # 5 minutes, in seconds
var _timer: Timer

func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.wait_time = 1.0  # tick every second
	_timer.autostart = false
	_timer.timeout.connect(_on_timer_tick)
	add_child(_timer)

func start_run() -> void:
	reset_score()
	countdown_time = 300.0
	start_timer()

func start_timer() -> void:
	countdown_time = 300.0
	_timer.start()

func reset_score() -> void:
	run_score = 0
	score_changed.emit(run_score, 0, "reset")

func add_score(amount: int, reason: String = "") -> void:
	if amount == 0:
		return
	run_score += amount
	score_changed.emit(run_score, amount, reason)

func _on_timer_tick() -> void:
	countdown_time -= 1.0
	if countdown_time <= 0.0:
		countdown_time = 0.0
		_timer.stop()
		time_over.emit()
	time_updated.emit(countdown_time)
