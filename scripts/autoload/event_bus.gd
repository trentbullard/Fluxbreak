# scripts/autoload/event_bus.gd (godot 4.5)
extends Node

signal weapons_changed(weapons: Array[WeaponDef])
signal add_gun_requested(weapon: WeaponDef)
signal rem_gun_requested(idx: int, weapon: WeaponDef) ## idx is the index of the weapon you want to remove. no null, -1 is last weapon
signal add_bulkhead_requested(upgrade: Upgrade)
signal add_shield_requested(upgrade: Upgrade)
signal add_targeting_requested(upgrade: Upgrade)
signal add_systems_requested(upgrade: Upgrade)
signal add_salvage_requested(upgrade: Upgrade)
signal add_thrusters_requested(upgrade: Upgrade)
signal heal_hull_requested(amount: float, percent: float)
