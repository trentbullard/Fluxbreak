extends RefCounted
class_name LoadoutInformationDetails

const Stat = StatTypes.Stat
const UPGRADE_MENU_PATH: String = "res://scenes/hud/upgrade_menu.tscn"
const WEAPON_COPY: Dictionary = {
	&"pulse_mk1": {
		"lore": "A compact pulse assembly kept alive by interchangeable parts and stubborn engineering. Its rapid report is a familiar sound around contested salvage lanes.",
		"description": "A rapid-fire automatic turret for close encounters. Frequent shots keep damage flowing, while its shorter reach and stronger accuracy falloff reward staying near the target.",
	},
	&"laser_mk1": {
		"lore": "A rugged emitter that trades rapid cycling for a heavier, more focused discharge. The design survives because a clear firing solution is often worth waiting for.",
		"description": "Fires slower, heavier laser bolts. Its longer range and gentler accuracy falloff let it apply pressure from farther away than the Pulse Gun.",
	},
	&"drone_bay_mk1": {
		"lore": "A miniature maintenance hangar repurposed for combat. Each launch sends another small machine out to do dangerous work its carrier would rather avoid.",
		"description": "Deploys independently flying laser drones that pursue assigned targets and orbit them at close range. Each drone spends charge while attacking, returns to redock when depleted, and recharges before launching again. Radio-range upgrades extend its reach; attacks beyond the carrier's normal assignment range consume charge faster.",
	},
	&"particle_beam_mk1": {
		"lore": "A tightly focused particle stream whose real strength appears only after its emitter settles into a stable lock. Holding that lock turns a modest first touch into a sustained threat.",
		"description": "Acquires a target, then deals damage on repeated ticks. Hits build damage stacks and critical hits build more; grazes and misses remove stacks. Changing targets or losing a valid lock resets the ramp, so sustained contact matters more than the first tick.",
	},
}
const SHIP_COPY: Dictionary = {
	&"starter_fighter": {
		"lore": "A compact, serviceable fighter built to keep flying long after its original parts have been replaced. It is an adaptable frame for a pilot who has to make every salvage stop count.",
		"description": "A balanced starting hull with equal hull and shield capacity. Its faster forward speed and stronger boost make it well suited to chasing light enemies, changing approach angles and retrieving scattered salvage.",
	},
	&"heavy_bruiser": {
		"lore": "A reinforced combat frame with little patience for elegance. The broad hull carries its weapons into the fight behind a substantial reserve of metal.",
		"description": "A hull-focused alternative to the Fighter, with lower evasion, weaker shields and slower straight-line movement. It begins with more occupied weapon mounts, trading some agility for a stronger opening armament.",
	},
	&"drone_carrier": {
		"lore": "A mobile support platform that treats drones, salvage and power management as parts of the same problem: keeping useful machines working when the sector turns hostile.",
		"description": "A shield-focused support hull with strong shield regeneration, fragile hull plating and slower forward travel. Its wider salvage magnet and nanobot collection bonus reward deliberate collection routes. It begins with multiple occupied weapon mounts.",
	},
}

static var _upgrade_pool: Array[Upgrade] = []
static var _upgrade_pool_loaded: bool = false

static func for_weapon(definition: WeaponDef, unlocked: bool, unlock_text: String) -> Dictionary:
	if definition == null:
		return {}
	var entry: Dictionary = _entry(definition.get_weapon_id(), definition.get_display_name_or_default(), "Weapon")
	if not unlocked:
		return _locked_entry(entry, unlock_text)
	entry["model_scene"] = definition.visual_scene
	var copy: Dictionary = WEAPON_COPY.get(definition.get_weapon_id(), {})
	var description: String = String(copy.get("description", "An automatic weapon that engages targets assigned by the ship's targeting systems."))
	var sections: Array[Dictionary] = [
		{"title": "Lore", "text": String(copy.get("lore", "A modular weapon assembly designed for the hazards of contested space."))},
		{"title": "Description", "text": description},
		{"title": "Base stats", "text": "Before pilot bonuses, upgrades and sector modifiers. Shot intervals are seconds between attacks; lower values fire more often.", "stats": _weapon_stats(definition)},
		{"title": "Applicable upgrades", "text": _applicable_upgrades(definition)},
	]
	entry["sections"] = sections
	return entry

static func for_ship(definition: ShipDef, unlocked: bool, unlock_text: String) -> Dictionary:
	if definition == null:
		return {}
	var entry: Dictionary = _entry(definition.get_ship_id(), definition.get_display_name_or_default(), "Ship")
	if not unlocked:
		return _locked_entry(entry, unlock_text)
	entry["model_scene"] = definition.visuals.model_scene if definition.visuals != null else null
	entry["exposure_multiplier"] = UnlockInformationGrid.SHIP_PREVIEW_EXPOSURE
	var copy: Dictionary = SHIP_COPY.get(definition.get_ship_id(), {})
	var stats: Array[Dictionary] = [
		_row("Hull", _number(definition.max_hull)),
		_row("Shield", _number(definition.max_shield)),
		_row("Shield regeneration", _number(definition.shield_regen) + " / s"),
		_row("Evasion", _percent(definition.base_evasion)),
		_row("Forward speed", _number(definition.max_speed_forward) + " m/s"),
		_row("Reverse speed", _number(definition.max_speed_reverse) + " m/s"),
		_row("Forward acceleration", _number(definition.accel_forward) + " m/s²"),
		_row("Reverse acceleration", _number(definition.accel_reverse) + " m/s²"),
		_row("Boost multiplier", _number(definition.boost_mult) + "×"),
		_row("Pitch rate", _number(definition.max_ang_rate_deg.x) + "°/s"),
		_row("Yaw rate", _number(definition.max_ang_rate_deg.y) + "°/s"),
		_row("Roll rate", _number(definition.max_ang_rate_deg.z) + "°/s"),
		_row("Salvage magnet range", _number(definition.pickup_range) + " m"),
		_row("Nanobot gain", _percent(definition.nanobot_gain_mult)),
		_row("Score gain", _percent(definition.score_gain_mult)),
	]
	var occupied_mounts: int = definition.loadout.mounts.size() if definition.loadout != null else 0
	stats.append(_row("Starting weapon mounts", str(occupied_mounts)))
	var sections: Array[Dictionary] = [
		{"title": "Lore", "text": String(copy.get("lore", "A flight-ready hull assembled to survive the sector's demanding conditions."))},
		{"title": "Description", "text": String(copy.get("description", "A configurable player ship. Its base frame determines defenses, handling and salvage collection before pilot bonuses and upgrades."))},
		{"title": "Base stats", "text": "Base hull values before pilot bonuses, meta upgrades and run upgrades. Pilot G-force limits and active modifiers can reduce the speed, acceleration and turning rate achieved in flight.", "stats": stats},
	]
	entry["sections"] = sections
	return entry

static func _entry(entry_id: StringName, display_name: String, subtitle: String) -> Dictionary:
	return {"id": entry_id, "name": display_name, "subtitle": subtitle, "model_scene": null, "exposure_multiplier": 1.0, "sections": []}

static func _locked_entry(entry: Dictionary, unlock_text: String) -> Dictionary:
	entry["subtitle"] = "Locked"
	entry["placeholder"] = "?"
	var requirements: String = unlock_text if not unlock_text.strip_edges().is_empty() else "Unlock this starting option through the Hangar's progression requirements."
	entry["sections"] = [{"title": "Unlock requirements", "text": "Earn unlock progress in Campaign. Practice does not count.\n\n" + requirements}]
	return entry

static func _weapon_stats(definition: WeaponDef) -> Array[Dictionary]:
	var drone_bay: DroneBayWeaponDef = definition as DroneBayWeaponDef
	if drone_bay != null:
		return _drone_stats(drone_bay)
	var beam: BeamWeaponDef = definition as BeamWeaponDef
	var damage_label: String = "Damage per tick" if beam != null else "Damage per shot"
	var stats: Array[Dictionary] = [
		_row(damage_label, _damage_range(definition)),
		_row("Weapon range", _number(definition.base_range) + " m"),
		_row("Base accuracy", _percent(definition.base_accuracy)),
		_row("Accuracy range falloff", _percent(definition.accuracy_range_falloff)),
		_row("Critical chance", _percent(definition.crit_chance)),
		_row("Critical multiplier", _number(definition.crit_mult) + "×"),
		_row("Graze damage", _percent(definition.graze_mult)),
	]
	if beam == null:
		stats.insert(1, _row("Shot interval", _number(definition.fire_rate) + " s"))
	else:
		stats.append_array([
			_row("Lock acquisition", _number(beam.lock_acquire_time) + " s"),
			_row("Damage tick interval", _number(beam.damage_tick_interval) + " s"),
			_row("Max ramp stacks", str(beam.max_ramp_stacks)),
			_row("Damage per stack", "+" + _percent(beam.damage_ramp_per_stack)),
			_row("Stacks on hit", "+" + str(beam.ramp_gain_on_hit)),
			_row("Stacks on critical hit", "+" + str(beam.ramp_gain_on_crit)),
			_row("Stacks lost on graze", str(beam.ramp_loss_on_graze)),
			_row("Stacks lost on miss", str(beam.ramp_loss_on_miss)),
		])
	return stats

static func _drone_stats(definition: DroneBayWeaponDef) -> Array[Dictionary]:
	var stats: Array[Dictionary] = [
		_row("Active drones", str(definition.base_drone_count)),
		_row("Attack charge", _number(definition.drone_charge_time) + " s"),
		_row("Redock time", _number(definition.drone_redock_time) + " s"),
		_row("Launch interval", _number(definition.launch_interval) + " s"),
		_row("Targeting range", _number(definition.base_range) + " m"),
		_row("Extended-range charge use", _number(definition.extended_range_discharge_mult) + "×"),
		_row("Target priority", "Weakest total HP" if definition.target_priority == DroneBayWeaponDef.TargetPriority.WEAKEST_TOTAL_HP else "Closest"),
	]
	if definition.drone_weapon != null:
		stats.append_array([
			_row("Drone damage per shot", _damage_range(definition.drone_weapon)),
			_row("Drone shot interval", _number(definition.drone_weapon.fire_rate) + " s"),
		])
	return stats

## Read the existing authored shop pool without instantiating gameplay UI.
static func _get_upgrade_pool() -> Array[Upgrade]:
	if _upgrade_pool_loaded:
		return _upgrade_pool
	_upgrade_pool_loaded = true
	var scene: PackedScene = load(UPGRADE_MENU_PATH) as PackedScene
	if scene == null:
		return _upgrade_pool
	var state: SceneState = scene.get_state()
	for node_index: int in state.get_node_count():
		for property_index: int in state.get_node_property_count(node_index):
			if state.get_node_property_name(node_index, property_index) == &"available_upgrades":
				for upgrade: Upgrade in state.get_node_property_value(node_index, property_index):
					if upgrade != null:
						_upgrade_pool.append(upgrade)
	return _upgrade_pool

static func _applicable_upgrades(definition: WeaponDef) -> String:
	var entries: PackedStringArray = PackedStringArray()
	for upgrade: Upgrade in _get_upgrade_pool():
		var applicable: bool = false
		for modifier: StatModifier in upgrade.modifiers:
			if _modifier_applies(definition, modifier):
				applicable = true
				break
		if applicable:
			entries.append("%s\n%s" % [upgrade.display_name, upgrade.descripton])
	if entries.is_empty():
		return "No applicable upgrades in the current shop pool."
	return "These upgrades include at least one effect used by this weapon. Mixed upgrades can also improve other weapon types.\n\n" + "\n\n".join(entries)

static func _modifier_applies(definition: WeaponDef, modifier: StatModifier) -> bool:
	if modifier == null or not modifier.enabled:
		return false
	if definition is DroneBayWeaponDef:
		if modifier.applies_to_minions and modifier.stat in [Stat.MINION_COUNT, Stat.MINION_CHARGE_CAPACITY, Stat.MINION_RECHARGE_RATE, Stat.MINION_DISCHARGE_RATE, Stat.MINION_RADIO_RANGE, Stat.WEAPON_FIRE_RATE, Stat.WEAPON_DAMAGE_MIN, Stat.WEAPON_DAMAGE_MAX]:
			return true
		return modifier.applies_to_player and modifier.stat in [Stat.WEAPON_BASE_RANGE, Stat.WEAPON_RANGE_BONUS, Stat.SCANNER_RANGE]
	if not modifier.applies_to_player:
		return false
	if modifier.stat in [Stat.WEAPON_BASE_ACCURACY, Stat.WEAPON_BASE_RANGE, Stat.WEAPON_RANGE_FALLOFF, Stat.WEAPON_CRIT_CHANCE, Stat.WEAPON_GRAZE_ON_HIT, Stat.WEAPON_GRAZE_ON_MISS, Stat.WEAPON_GRAZE_MULT, Stat.WEAPON_CRIT_MULT, Stat.WEAPON_DAMAGE_MIN, Stat.WEAPON_DAMAGE_MAX, Stat.WEAPON_RANGE_BONUS, Stat.WEAPON_SYSTEMS_BONUS, Stat.SCANNER_RANGE]:
		return true
	if definition is BeamWeaponDef:
		return modifier.stat in [Stat.WEAPON_CHANNEL_ACQUIRE_TIME, Stat.WEAPON_CHANNEL_TICK_INTERVAL, Stat.WEAPON_RAMP_MAX_STACKS, Stat.WEAPON_RAMP_DAMAGE_PER_STACK, Stat.WEAPON_RAMP_STACKS_ON_HIT, Stat.WEAPON_RAMP_STACKS_ON_CRIT, Stat.WEAPON_RAMP_STACKS_LOST_ON_GRAZE, Stat.WEAPON_RAMP_STACKS_LOST_ON_MISS]
	return modifier.stat == Stat.WEAPON_FIRE_RATE

static func _row(label: String, value: String) -> Dictionary:
	return {"label": label, "value": value}

static func _number(value: float) -> String:
	return String.num(value, 2)

static func _percent(value: float) -> String:
	return _number(value * 100.0) + "%"

static func _damage_range(definition: WeaponDef) -> String:
	return "%s–%s" % [_number(definition.damage_min), _number(definition.damage_max)]
