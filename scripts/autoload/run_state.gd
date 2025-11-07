# scripts/autoload/run_state.gd (autoload)
extends Node

signal score_changed(total: int, delta: int, reason: String)
signal nanobots_updated(amount: int)

enum State { IN_WAVE, DOWNTIME }

var run_state: State = State.DOWNTIME
var run_score: int = 0

func start_run() -> void:
	reset_score()

func set_state(state: State) -> void:
	run_state = state

func reset_score() -> void:
	run_score = 0
	score_changed.emit(run_score, 0, "reset")

func add_score(amount: int, reason: String = "") -> void:
	if amount == 0:
		return
	run_score += amount
	score_changed.emit(run_score, amount, reason)
