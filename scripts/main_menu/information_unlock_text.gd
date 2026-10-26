extends RefCounted
class_name InformationUnlockText

## Describe the same AND/OR requirements used by GameFlow, including parents.
## This is presentation only; the existing unlock checks remain authoritative.
static func for_path(pilot: PilotDef, ship: PilotStarterShipOptionDef, weapon: ShipStarterWeaponOptionDef, names: Dictionary) -> String:
	var conditions: Array[String] = []
	if not GameFlow.is_pilot_unlocked(pilot):
		conditions.append("Pilot — " + describe_requirements(pilot.unlock_requirements, pilot.unlock_requirement_mode == PilotDef.UnlockRequirementMode.ALL, names))
	if not GameFlow.is_ship_option_unlocked(ship):
		conditions.append("Ship — " + describe_requirements(ship.unlock_requirements, ship.unlock_requirement_mode == PilotStarterShipOptionDef.UnlockRequirementMode.ALL, names))
	if weapon != null and not GameFlow.is_weapon_option_unlocked(weapon):
		conditions.append("Starting weapon — " + describe_requirements(weapon.unlock_requirements, weapon.unlock_requirement_mode == ShipStarterWeaponOptionDef.UnlockRequirementMode.ALL, names))
	var route: String = pilot.get_display_name_or_default() + " / " + ship.ship.get_display_name_or_default()
	if conditions.is_empty():
		return route + "\nAvailable from the start with this loadout."
	return route + "\n• " + "\n• ".join(conditions)

static func describe_requirements(requirements: Array, require_all: bool, names: Dictionary = {}) -> String:
	var descriptions: Array[String] = []
	for entry: Resource in requirements:
		var requirement: UnlockRequirement = entry as UnlockRequirement
		if requirement != null:
			descriptions.append(_describe_requirement(requirement, names))
	if descriptions.is_empty():
		return "No unlock condition is currently configured."
	if descriptions.size() == 1:
		return descriptions[0]
	return ("Meet all: " if require_all else "Meet any one: ") + ("; AND " if require_all else "; OR ").join(descriptions)

static func _describe_requirement(requirement: UnlockRequirement, names: Dictionary) -> String:
	var amount: int = maxi(requirement.minimum_value, 0)
	var text: String = ""
	match requirement.stat:
		UnlockRequirement.UnlockStat.HIGHEST_SCORE:
			text = "Reach a score of %d in one run" % amount
		UnlockRequirement.UnlockStat.LONGEST_RUN_SECONDS:
			var minutes: int = int(amount / 60.0)
			var seconds: int = amount % 60
			text = "Survive %d:%02d in one run" % [minutes, seconds]
		UnlockRequirement.UnlockStat.DEATH_RUNS:
			text = "Finish %d run%s ending in death" % [amount, "" if amount == 1 else "s"]
		UnlockRequirement.UnlockStat.TOTAL_NANOBOTS_IN_RUN:
			text = "Collect %d nanobots in one run" % amount
		UnlockRequirement.UnlockStat.HIGHEST_NANOBOTS_IN_RUN:
			text = "Hold %d nanobots at once in one run" % amount
		UnlockRequirement.UnlockStat.HIGHEST_WAVE_REACHED:
			text = "Reach wave %d" % amount
		UnlockRequirement.UnlockStat.KILLS:
			text = "Defeat %d enemies across runs" % amount
		UnlockRequirement.UnlockStat.DAMAGE_DEALT:
			text = "Deal %d damage across runs" % amount
		UnlockRequirement.UnlockStat.DAMAGE_TAKEN:
			text = "Take %d damage across runs" % amount
	if requirement.source_pilot_id != &"":
		text += " as " + _name(requirement.source_pilot_id, names)
	# GameFlow only applies equipment and target filters to lifetime kill/damage totals.
	if requirement.stat in [UnlockRequirement.UnlockStat.KILLS, UnlockRequirement.UnlockStat.DAMAGE_DEALT, UnlockRequirement.UnlockStat.DAMAGE_TAKEN]:
		if requirement.ship_id != &"":
			text += " while flying " + _name(requirement.ship_id, names)
		if requirement.weapon_id != &"":
			text += (" while equipped with " if requirement.weapon_context == UnlockRequirement.WeaponContext.EQUIPPED else " using ") + _name(requirement.weapon_id, names)
		if requirement.enemy_id != &"":
			text += "; target: " + _name(requirement.enemy_id, names)
		if requirement.faction_id != &"":
			text += "; faction: " + _name(requirement.faction_id, names)
		if requirement.role_id != &"":
			text += "; enemy role: " + _name(requirement.role_id, names)
	return text + "."

static func _name(identity: StringName, names: Dictionary) -> String:
	return String(names.get(identity, String(identity).replace("_", " ").capitalize()))
