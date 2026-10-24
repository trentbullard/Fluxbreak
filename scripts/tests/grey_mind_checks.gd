extends "res://scripts/tests/grey_boss_checks.gd"

const MIND: GreyMindDef = preload("res://content/data/enemies/grey_veiled_mind_mk1.tres")
const PRACTICE: GreyMindDef = preload("res://content/data/enemies/grey_veiled_mind_practice.tres")

func _suite_name() -> String:
	return "GREY_MIND_CHECKS"

func _definitions() -> Array[GreyBossDef]:
	return [MIND, PRACTICE]
