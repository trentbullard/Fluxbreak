extends InformationIconGrid
class_name UnlockInformationGrid

## Each identity is listed once, including options behind still-locked parents.
## Availability follows the same pilot -> ship -> starting weapon path as Hangar.
func refresh(category: StringName, roster: PilotRoster) -> void:
	_clear_entries()
	var pilots: Array[PilotDef] = roster.get_pilots() if roster != null else GameFlow.get_all_pilots()
	var records: Array[Dictionary] = []
	var by_id: Dictionary = {}
	for pilot: PilotDef in pilots:
		var pilot_unlocked: bool = GameFlow.is_pilot_unlocked(pilot)
		if category == &"pilots":
			_record(records, by_id, pilot.get_pilot_id(), pilot.get_display_name_or_default(), pilot_unlocked)
			continue
		for ship_option: PilotStarterShipOptionDef in GameFlow.get_starter_ship_options(pilot):
			var ship_unlocked: bool = pilot_unlocked and GameFlow.is_ship_option_unlocked(ship_option)
			if category == &"ships":
				_record(records, by_id, ship_option.get_ship_id(), ship_option.ship.get_display_name_or_default(), ship_unlocked)
			elif category == &"weapons":
				for weapon_option: ShipStarterWeaponOptionDef in GameFlow.get_starter_weapon_options(ship_option.ship):
					var weapon_unlocked: bool = ship_unlocked and GameFlow.is_weapon_option_unlocked(weapon_option)
					_record(records, by_id, weapon_option.get_weapon_id(), weapon_option.weapon.get_display_name_or_default(), weapon_unlocked)
	var singular: String = "weapon" if category == &"weapons" else ("ship" if category == &"ships" else "pilot")
	if records.is_empty():
		_add_empty_message("No %s available." % String(category))
	else:
		_begin_section("")
		for record: Dictionary in records:
			var entry_id: StringName = record["id"]
			var unlocked: bool = bool(record["unlocked"])
			var button: Button = _append_icon(entry_id)
			button.set_meta(&"entry_type", category)
			button.set_meta(&"unlocked", unlocked)
			_set_icon_state(button, unlocked, String(record["name"]), "Locked " + singular)
	_reset_scroll()

func _record(records: Array[Dictionary], by_id: Dictionary, entry_id: StringName, display_name: String, unlocked: bool) -> void:
	if entry_id == &"":
		return
	if by_id.has(entry_id):
		var existing: Dictionary = records[int(by_id[entry_id])]
		existing["unlocked"] = bool(existing["unlocked"]) or unlocked
		return
	by_id[entry_id] = records.size()
	records.append({"id": entry_id, "name": display_name, "unlocked": unlocked})
