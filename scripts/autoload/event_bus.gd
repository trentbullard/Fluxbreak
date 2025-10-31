# scripts/autoload/event_bus.gd (godot 4.5)
extends Node

signal weapons_changed(weapons: Array[WeaponDef])
signal add_gun_requested(weapon: WeaponDef)
signal rem_gun_requested(idx: int, weapon: WeaponDef) ## idx is the index of the weapon you want to remove. no null, -1 is last weapon
