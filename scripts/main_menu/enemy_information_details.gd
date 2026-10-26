extends RefCounted
class_name EnemyInformationDetails

## Authored copy stays separate from the reusable view and live combat resources.
## Copy describes implemented behavior; combat values remain in their definitions.
const ENTRIES: Dictionary = {
	"machine_drone_mk1": {
		"lore": "A compact warform of the Machine collective. Its simple frame and single sensor conceal an unrelenting directive: maintain contact and keep firing.",
		"role": "A lightly protected scout that pressures the player with persistent laser fire while circling through changing approach angles.",
		"attack": "Closes to medium range, then orbits while firing single laser bolts. Changes its orbit plane periodically and backs away when crowded.",
		"weapon": "Laser turret",
	},
	"machine_sentinel_mk1": {
		"lore": "The collective's patient sentry. A reinforced shell and steady power supply turn a simple weapon into a persistent problem.",
		"role": "A sustained-fire combatant with more protection and longer weapon reach than a Drone.",
		"attack": "Approaches and circles while firing regular laser bolts. Its sustained fire layers with nearby Machine units; breaking contact reduces incoming pressure.",
		"weapon": "Laser turret",
	},
	"machine_reaper_mk1": {
		"lore": "An economical answer to close resistance: a compact engine, a heavy emitter, and no concern for the pilot it pursues.",
		"role": "A close-range brawler whose heavier laser shots make nearby space dangerous.",
		"attack": "Pursues and orbits using the Machine steering pattern. Its short weapon reach rewards keeping distance while faster threats are cleared.",
		"weapon": "Heavy laser turret",
	},
	"machine_warden_mk1": {
		"lore": "A layered warform designed to remain operational after lighter frames have failed. Its revolving armor makes endurance look effortless.",
		"role": "A durable front-line anchor with strong hull and regenerating shields.",
		"attack": "Advances and circles under steady laser fire. It relies on its own durability rather than granting protection to other ships; sustained focus helps overcome its continual shield recovery.",
		"weapon": "Laser turret",
	},
	"machine_coremind_mk1": {
		"lore": "Nested shells shelter a dense synthetic core. Every exposed surface is another layer between the collective's calculations and the void.",
		"role": "A shield-heavy support-class hull that adds persistent long-range fire. Its current combat systems restore its own shields.",
		"attack": "Orbits and fires regular laser bolts while its shields regenerate. Focus it through its defenses instead of allowing repeated breaks in damage.",
		"weapon": "Laser turret",
	},
	"machine_boss_1_mk1": {
		"lore": "A fortress-grade core built to make withdrawal unnecessary. Its rotating assemblies surround a battery that can sustain pressure from several firing arcs.",
		"role": "A heavily shielded siege boss with multiple independently firing laser mounts.",
		"attack": "Maintains a preferred distance while strafing horizontally and vertically. Every weapon mount fires on its own cooldown when in range; there is no separate charge or invulnerability phase.",
		"weapon": "Fortress laser battery",
	},
	"merc_corvette_mk1": {
		"lore": "The smallest hull in a contractor's battle line, built to turn speed and repeated firing passes into a reliable invoice.",
		"role": "A fast skirmisher that keeps moving through short weapon bursts and retreats.",
		"attack": "Closes for a burst, strafes in a changing three-dimensional orbit, then pulls away before returning. Its shots use the normal accuracy and evasion rolls.",
		"weapon": "Corvette burst cannon",
	},
	"merc_frigate_mk1": {
		"lore": "A contractor fleet protects its investment. The Frigate carries the equipment that keeps an expensive firing line intact.",
		"role": "An armed support ship that follows heavier allies and restores nearby allied shields.",
		"attack": "Positions behind an escorted ally, fires single shots, and sends bounded shield pulses to nearby recipients. Destroying it removes future support, making the remaining formation easier to finish.",
		"weapon": "Frigate cannon",
	},
	"merc_destroyer_mk1": {
		"lore": "A siege gun with engines attached. Its crews trust a clean firing solution more than an elegant maneuver.",
		"role": "A durable artillery ship that denies a straight corridor through space.",
		"attack": "Brakes for a charged cannon strike along a locked corridor, then recovers. Turn or climb outside the marked lane before release; the committed shot does not follow you.",
		"weapon": "Charged siege cannon",
	},
	"merc_cruiser_mk1": {
		"lore": "Armor, power, and a broadside crew drilled to fire by sequence. The Cruiser brings a whole firing line in a single hull.",
		"role": "A heavy formation anchor that forces several successive evasive decisions.",
		"attack": "Presents a flank and fires a sequence of separately warned corridors. After the final round it makes a silent recovery turn and prepares the opposite broadside.",
		"weapon": "Broadside battery",
	},
	"merc_carrier_mk1": {
		"lore": "A mobile contract depot whose cargo arrives armed. Its value is measured in every wing still fighting after the launch bays fall silent.",
		"role": "A heavily armored fleet multiplier that repeatedly launches Corvette escorts.",
		"attack": "Maintains standoff distance, fires between launches, and pauses for a visible escort release. Launches have no total minion ceiling; escorts already released survive the Carrier's destruction.",
		"weapon": "Carrier defense cannon",
	},
	"merc_contract_enforcer_mk1": {
		"lore": "The clause at the bottom of the contract, delivered in armor. An Enforcer remains on station until the debt is settled.",
		"role": "A siege boss that alternates corridor denial and spherical salvo pressure.",
		"attack": "Commits a broadside lane, then a fixed salvo sphere, with an exposed recovery after each. Its hull threshold quickens the cadence and calls one Frigate escort. The escort remains if the Enforcer dies first.",
		"weapon": "Enforcer siege cannon",
	},
	"merc_vanguard_flagship_mk1": {
		"lore": "A private fleet's center of authority. The Flagship carries enough armor to remain a command post while the surrounding contract turns into a war.",
		"role": "A capital boss combining heavy broadsides, siege salvos, and escort support.",
		"attack": "Changes its broadside and salvo sequence at two hull thresholds. Launches escort wings on arrival and at phase changes, then periodically restores its own escorts' shields. Every strike keeps its full warning and recovery.",
		"weapon": "Vanguard batteries",
	},
	"bug_sporeling_mk1": {
		"lore": "A small shard of the hive's appetite. What it lacks in carapace it makes up for in restless movement and the company of its brood.",
		"role": "The fastest, lightest Bug pursuer, dangerous when many approach together.",
		"attack": "Weaves around the player at close range and commits a delayed spore strike to a fixed position. The organism keeps strafing, but its marked strike stays where it was placed.",
		"weapon": "Spore strike",
	},
	"bug_carapace_mk1": {
		"lore": "Growth traded for armor. Layered plates let this organism keep advancing through punishment that would scatter a lighter brood.",
		"role": "A shieldless hull tank that creates close-range corridor pressure.",
		"attack": "Closes steadily, contracts, and releases a strike down a locked ram corridor. Escape sideways or vertically before the release, then use its stationary recovery window.",
		"weapon": "Carapace ram",
	},
	"bug_broodmother_mk1": {
		"lore": "A living nursery armored against the vacuum. The hive does not need a dock when its next wave can be grown on the battlefield.",
		"role": "A slow, durable spawner that adds continuing Sporeling pressure.",
		"attack": "Keeps its distance, marks spore volleys, and visibly swells before each brood release. Broods have no total minion ceiling and survive their mother's death; killing her prevents later releases.",
		"weapon": "Spore volley",
	},
	"bug_devourer_mk1": {
		"lore": "A thick-shelled predator grown around one brutal instinct: choose a line and commit everything to it.",
		"role": "A heavy charger that threatens a long path through the player's position.",
		"attack": "Locks a corridor through an overshoot destination, resolves its strike, then travels that committed line without steering. Physical contact during travel causes no extra damage. Punish the recovery after the charge.",
		"weapon": "Devourer charge",
	},
	"bug_hive_queen_mk1": {
		"lore": "A wandering pocket of the hive itself, carrying both its offspring and the spores that turn open space into occupied territory.",
		"role": "A capital support organism that combines brood growth with fixed area denial.",
		"attack": "Alternates continuing brood releases with a finite supply of spore zones. Each zone has a fresh warning before every pulse and eventually expires. Released offspring remain independent combatants.",
		"weapon": "Hive spore zone",
	},
	"bug_nestbreaker_matron_mk1": {
		"lore": "A siege organism whose body is both battering ram and nursery. The Matron breaks resistance by arriving with the next generation already inside her.",
		"role": "A heavily armored brood boss that alternates direct charges with reinforcement releases.",
		"attack": "Locks a charge lane, commits to it, then swells for a brood release. At its hull threshold the Matron produces larger broods and attacks more frequently. Her surviving offspring remain after she falls.",
		"weapon": "Matron charge",
	},
	"bug_first_queen_mk1": {
		"lore": "An ancient sovereign whose carapace carries the weight of countless broods. Her presence makes every patch of open space feel temporary.",
		"role": "A hive boss that layers brood pressure, repeated spore pulses, and committed charges.",
		"attack": "Begins with brood and royal spore blooms. A hull threshold adds charge lanes; a later threshold changes the sequence and shortens the quiet cadence. Full warnings and recovery remain, and she can always take damage.",
		"weapon": "Royal spore and charge attacks",
	},
	"grey_probe_mk1": {
		"lore": "A silent point of attention wrapped in a hull. Whether the Probe is watching the ship or the space it will occupy remains unclear.",
		"role": "An evasive light ship with strong shields for its modest hull and a simple delayed pulse.",
		"attack": "Strafes through a changing three-dimensional orbit while a pulse charges at the player's captured position. Leave the fixed field before it flashes; the Probe's movement does not drag it along.",
		"weapon": "Thought pulse",
	},
	"grey_seeker_mk1": {
		"lore": "The Seeker treats motion as an answer already given. Its next position and the space it marks seem to arrive from the same unfinished thought.",
		"role": "A displacement skirmisher that punishes a steady course with forecast ruptures.",
		"attack": "Places a rupture ahead of the player's sampled velocity and periodically relocates before another forecast. Change heading after commitment: predictions lock once and never chase the player. Arrival markers are harmless.",
		"weapon": "Forecast rupture",
	},
	"grey_vessel_mk1": {
		"lore": "A smooth shell around a patient restraint. The Vessel does not need to hold a target forever, only long enough for the next field to bloom.",
		"role": "A control ship that combines damaging phase lanes with brief movement tethers.",
		"attack": "Alternates crossing damage lanes with forecast capture corridors. Leave the capture lane to avoid attachment; an attached tether breaks with distance or source destruction. Turning and boost remain usable, and tethers do not stack.",
		"weapon": "Phase lane and capture tether",
	},
	"grey_harbinger_mk1": {
		"lore": "One presence, two consequences. A Harbinger's fields describe both where a pilot is and where that pilot expected to go.",
		"role": "A heavy spatial attacker that makes constant straight-line movement less reliable.",
		"attack": "Commits complementary current-position and forecast ruptures as a staggered echo pair. Both remain fixed after commitment; a deliberate turn or climb can leave the two danger volumes together.",
		"weapon": "Echo ruptures",
	},
	"grey_mothership_mk1": {
		"lore": "A silent center around which lesser hulls seem to agree. Its influence is visible only when several empty spaces become dangerous at once.",
		"role": "A shield-heavy coordinator that combines its own patterns with one nearby ally's forecast.",
		"attack": "Opens a crossing lane while requesting a forecast from an idle ally. Relocation and tether setups lead into separately warned echo collapses. Committed attacks and exposed recovery are never skipped by its ally command.",
		"weapon": "Coordinated phase patterns",
	},
	"grey_witness_mk1": {
		"lore": "It appears where it can observe, then makes observation an attack. The Witness keeps no obvious weapon trained on its target.",
		"role": "A regenerating shield boss that combines repositioning, crossing fields, and tether control.",
		"attack": "Relocates before a crossing lane and current-position rupture, then uses capture setups for fresh warned attacks. A combined hull-and-shield threshold quickens its cadence. Change direction or climb out of committed geometry.",
		"weapon": "Witness phase cross",
	},
	"grey_veiled_mind_mk1": {
		"lore": "A distant intelligence given the minimum shape needed to enter the battlefield. Every collapse feels less like a shot than a decision already made.",
		"role": "A shield-dominant boss that escalates from forecast attacks to overlapping spatial patterns.",
		"attack": "Starts with locked forecasts, then adds current-position echoes and finally crossing lanes to three-part collapses as combined defenses fall. Relocations and tethers set up new warnings. Phase changes never interrupt a warning or grant invulnerability.",
		"weapon": "Veil collapse",
	},
}

static func for_enemy(definition: EnemyDef) -> Dictionary:
	if definition == null or not ENTRIES.has(definition.id):
		return {}
	var copy: Dictionary = ENTRIES[definition.id]
	var stats: Array[Dictionary] = [
		{"label": "Hull", "value": String.num(definition.max_hull, 2)},
		{"label": "Shield", "value": String.num(definition.max_shield, 2)},
		{"label": "Shield regeneration", "value": String.num(definition.shield_regen, 2) + " / s"},
		{"label": "Evasion", "value": String.num(definition.evasion * 100.0, 2) + "%"},
	]
	var weapon: WeaponDef = definition.weapon
	if weapon != null and not definition is EnemyBossDef:
		stats.append_array([
			{"label": "Weapon", "value": String(copy["weapon"])},
			{"label": "Damage per release" if _has_committed_attacks(definition) else "Damage per shot", "value": _damage(weapon)},
			{"label": "Weapon range", "value": String.num(weapon.base_range, 2) + " m"},
			{"label": "Base accuracy", "value": String.num(weapon.base_accuracy * 100.0, 2) + "%"},
		])
		if definition.get_faction_id() == &"machines":
			# Machine turrets use their weapon's real autonomous shot interval.
			stats.insert(6, {"label": "Shot interval", "value": String.num(weapon.fire_rate, 2) + " s"})
	_add_behavior_stats(definition, stats)
	var sections: Array[Dictionary] = [
		{"title": "Lore", "text": String(copy["lore"])},
		{"title": "Role", "text": String(copy["role"])},
		{"title": "Attack pattern", "text": String(copy["attack"])},
		{"title": "Base stats", "text": "Before run scaling, elites and sector modifiers. Accuracy also depends on range and the target's evasion.", "stats": stats},
	]
	if definition is EnemyBossDef:
		_add_boss_armament(definition as EnemyBossDef, sections)
		sections[3]["text"] = "Full Campaign base defenses before run and sector modifiers. Practice can use reduced defenses. Damage is listed per shot or field release, not per complete attack sequence."
	elif _has_committed_attacks(definition):
		sections[3]["text"] = "Before run scaling, elites and sector modifiers. Damage is per field release, not per sequence. Leave a committed volume before it flashes to avoid its hit; attacks inside it still use accuracy and evasion."
	return {
		"id": StringName(definition.id),
		"name": definition.get_display_name_or_default(),
		"subtitle": "%s  /  %s  /  Tier %d" % [definition.get_faction_display_name(), definition.get_role_display_name(), definition.tier],
		"model_scene": definition.model_scene,
		"sections": sections,
	}

static func _has_committed_attacks(definition: EnemyDef) -> bool:
	if definition is BugEnemyDef or definition is GreyEnemyDef:
		return true
	var merc: MercEnemyDef = definition as MercEnemyDef
	return merc != null and merc.behavior != null and merc.behavior.mode in [MercBehaviorDef.Mode.DESTROYER, MercBehaviorDef.Mode.CRUISER]

static func _damage(weapon: WeaponDef) -> String:
	return "%s–%s" % [String.num(weapon.damage_min, 2), String.num(weapon.damage_max, 2)]

static func _stat(rows: Array[Dictionary], label: String, value: float, unit: String = "") -> void:
	rows.append({"label": label, "value": String.num(value, 2) + unit})

static func _add_behavior_stats(definition: EnemyDef, rows: Array[Dictionary]) -> void:
	if definition is MercEnemyDef:
		_add_merc_stats((definition as MercEnemyDef).behavior, rows)
	elif definition is BugEnemyDef:
		_add_bug_stats((definition as BugEnemyDef).behavior, rows)
	elif definition is GreyEnemyDef:
		_add_grey_stats((definition as GreyEnemyDef).behavior, rows)
	elif definition is MercBossDef:
		_add_merc_boss_stats(definition as MercBossDef, rows)
	elif definition is BugBossDef:
		_add_bug_boss_stats(definition as BugBossDef, rows)
	elif definition is GreyBossDef:
		_add_grey_boss_stats(definition as GreyBossDef, rows)

static func _add_merc_stats(behavior: MercBehaviorDef, rows: Array[Dictionary]) -> void:
	if behavior == null:
		return
	_stat(rows, "Attack cooldown", behavior.attack_cooldown_sec, " s")
	match behavior.mode:
		MercBehaviorDef.Mode.CORVETTE:
			_stat(rows, "Shots per burst", behavior.burst_shots)
			_stat(rows, "Burst shot interval", behavior.burst_interval_sec, " s")
			_stat(rows, "Retreat duration", behavior.retreat_duration_sec, " s")
		MercBehaviorDef.Mode.FRIGATE:
			_stat(rows, "Shield restored per recipient", behavior.shield_restore_amount)
			_stat(rows, "Shield pulse interval", behavior.shield_pulse_interval_sec, " s")
			_stat(rows, "Support radius", behavior.shield_radius, " m")
			_stat(rows, "Recipients per pulse", behavior.shield_max_targets)
			_stat(rows, "Support shield ceiling", behavior.shield_restore_fraction * 100.0, "%")
		MercBehaviorDef.Mode.DESTROYER:
			_stat(rows, "Charge warning", behavior.charge_windup_sec, " s")
			_stat(rows, "Corridor radius", behavior.charge_radius, " m")
		MercBehaviorDef.Mode.CRUISER:
			_stat(rows, "Rounds per broadside", behavior.broadside_shots)
			_stat(rows, "Warning per round", behavior.broadside_windup_sec, " s")
			_stat(rows, "Corridor radius", behavior.broadside_radius, " m")
			_stat(rows, "Broadside recovery", behavior.broadside_recovery_sec, " s")
		MercBehaviorDef.Mode.CARRIER:
			_stat(rows, "Escorts per launch", behavior.escort_burst_count)
			_stat(rows, "Launch interval", behavior.escort_interval_sec, " s")
			_stat(rows, "Launch warning", behavior.escort_windup_sec, " s")

static func _add_bug_stats(behavior: BugBehaviorDef, rows: Array[Dictionary]) -> void:
	if behavior == null:
		return
	if behavior.mode == BugBehaviorDef.Mode.HIVE_QUEEN:
		_stat(rows, "Spore warning per pulse", behavior.zone_windup_sec, " s")
		_stat(rows, "Spore radius", behavior.zone_radius, " m")
		_stat(rows, "Pulses per zone", behavior.zone_pulse_count)
		_stat(rows, "Spore zones per Queen", behavior.zone_total_cap)
	else:
		_stat(rows, "Attack cooldown", behavior.attack_cooldown_sec, " s")
		_stat(rows, "Attack warning", behavior.attack_windup_sec, " s")
		_stat(rows, "Strike radius", behavior.attack_radius, " m")
	_stat(rows, "Attack recovery", behavior.attack_recovery_sec, " s")
	if behavior.mode in [BugBehaviorDef.Mode.BROODMOTHER, BugBehaviorDef.Mode.HIVE_QUEEN]:
		_stat(rows, "Children per brood", behavior.brood_burst_count)
		_stat(rows, "Brood interval", behavior.brood_interval_sec, " s")
		_stat(rows, "Brood warning", behavior.brood_windup_sec, " s")
	elif behavior.mode == BugBehaviorDef.Mode.DEVOURER:
		_stat(rows, "Committed charge speed", behavior.charge_speed, " m/s")

static func _add_grey_stats(behavior: GreyBehaviorDef, rows: Array[Dictionary]) -> void:
	if behavior == null:
		return
	_stat(rows, "Attack cooldown", behavior.attack_cooldown_sec, " s")
	_stat(rows, "Field warning", behavior.attack_windup_sec, " s")
	_stat(rows, "Attack recovery", behavior.attack_recovery_sec, " s")
	if behavior.mode != GreyBehaviorDef.Mode.VESSEL:
		_stat(rows, "Rupture radius", behavior.attack_radius, " m")
	if behavior.mode in [GreyBehaviorDef.Mode.VESSEL, GreyBehaviorDef.Mode.MOTHERSHIP]:
		_stat(rows, "Phase lane radius", behavior.corridor_radius, " m")
		_stat(rows, "Phase lane length", behavior.corridor_half_length * 2.0, " m")
		_stat(rows, "Capture warning", behavior.tether_windup_sec, " s")
		_stat(rows, "Tether duration", behavior.tether_duration_sec, " s")
		_stat(rows, "Tether movement reduction", (1.0 - maxf(behavior.tether_slow_multiplier, 0.65)) * 100.0, "%")
		_stat(rows, "Tether break distance", behavior.tether_break_distance, " m")
	if behavior.mode in [GreyBehaviorDef.Mode.SEEKER, GreyBehaviorDef.Mode.MOTHERSHIP]:
		_stat(rows, "Relocation warning", behavior.displacement_windup_sec, " s")
	if behavior.mode == GreyBehaviorDef.Mode.HARBINGER:
		_stat(rows, "Echo release gap", behavior.rupture_second_gap_sec, " s")
	elif behavior.mode == GreyBehaviorDef.Mode.MOTHERSHIP:
		_stat(rows, "Ally coordination radius", behavior.coordination_radius, " m")

static func _add_merc_boss_stats(definition: MercBossDef, rows: Array[Dictionary]) -> void:
	_stat(rows, "Broadside warning", definition.broadside_windup_sec, " s")
	_stat(rows, "Broadside radius", definition.broadside_radius, " m")
	_stat(rows, "Salvo warning", definition.salvo_windup_sec, " s")
	_stat(rows, "Salvo radius", definition.salvo_radius, " m")
	_stat(rows, "Recovery per attack", definition.recovery_sec, " s")
	_stat(rows, "Opening cadence delay", definition.cadence_sec, " s")
	var flagship: MercFlagshipDef = definition as MercFlagshipDef
	if flagship != null:
		_stat(rows, "Phase two hull threshold", flagship.phase_two_hull_threshold * 100.0, "%")
		_stat(rows, "Final phase hull threshold", flagship.phase_three_hull_threshold * 100.0, "%")
		_stat(rows, "Escorts per wing", flagship.escorts_per_wing)
		_stat(rows, "Escort shield restoration", flagship.escort_shield_restore)
		_stat(rows, "Escort support interval", flagship.escort_shield_interval_sec, " s")
	else:
		_stat(rows, "Phase two hull threshold", definition.phase_hull_threshold * 100.0, "%")

static func _add_bug_boss_stats(definition: BugBossDef, rows: Array[Dictionary]) -> void:
	_stat(rows, "Charge warning", definition.charge_windup_sec, " s")
	_stat(rows, "Charge corridor radius", definition.charge_radius, " m")
	_stat(rows, "Brood warning", definition.brood_windup_sec, " s")
	_stat(rows, "Children per opening brood", definition.brood_release_count)
	_stat(rows, "Children per later brood", definition.phase_brood_release_count)
	_stat(rows, "Recovery per attack", definition.recovery_sec, " s")
	_stat(rows, "Opening cadence delay", definition.cadence_sec, " s")
	var queen: BugQueenDef = definition as BugQueenDef
	if queen != null:
		_stat(rows, "Phase two hull threshold", queen.second_phase_hull_threshold * 100.0, "%")
		_stat(rows, "Final phase hull threshold", queen.final_phase_hull_threshold * 100.0, "%")
		_stat(rows, "Spore warning per pulse", queen.spore_windup_sec, " s")
		_stat(rows, "Spore radius", queen.spore_radius, " m")
		_stat(rows, "Pulses per bloom", queen.spore_pulse_count)
	else:
		_stat(rows, "Phase two hull threshold", definition.phase_hull_threshold * 100.0, "%")

static func _add_grey_boss_stats(definition: GreyBossDef, rows: Array[Dictionary]) -> void:
	_stat(rows, "Rupture warning", definition.rupture_windup_sec, " s")
	_stat(rows, "Rupture radius", definition.rupture_radius, " m")
	_stat(rows, "Crossing lane radius", definition.corridor_radius, " m")
	_stat(rows, "Crossing lane length", definition.corridor_half_length * 2.0, " m")
	_stat(rows, "Capture warning", definition.tether_windup_sec, " s")
	_stat(rows, "Tether duration", definition.tether_duration_sec, " s")
	_stat(rows, "Tether movement reduction", (1.0 - maxf(definition.tether_movement_factor, 0.65)) * 100.0, "%")
	_stat(rows, "Tether break distance", definition.tether_break_distance, " m")
	_stat(rows, "Recovery per attack", definition.recovery_sec, " s")
	_stat(rows, "Opening cadence delay", definition.cadence_sec, " s")
	var mind: GreyMindDef = definition as GreyMindDef
	if mind != null:
		_stat(rows, "Phase two combined defenses", mind.phase_two_hull_threshold * 100.0, "%")
		_stat(rows, "Final phase combined defenses", mind.phase_three_hull_threshold * 100.0, "%")
	else:
		_stat(rows, "Phase two combined defenses", definition.phase_hull_threshold * 100.0, "%")

## Socket resources are the authoritative boss weapons. Inspect packed data only;
## no actor, script, timer or other gameplay node is instantiated for these stats.
static func _add_boss_armament(definition: EnemyBossDef, sections: Array[Dictionary]) -> void:
	var mounts: Dictionary = {}
	if definition.model_scene != null:
		var state: SceneState = definition.model_scene.get_state()
		for index: int in state.get_node_count():
			for property_index: int in state.get_node_property_count(index):
				if state.get_node_property_name(index, property_index) != &"weapon":
					continue
				var weapon: WeaponDef = state.get_node_property_value(index, property_index) as WeaponDef
				if weapon != null:
					mounts[weapon] = int(mounts.get(weapon, 0)) + 1
	if mounts.is_empty() and definition.weapon != null:
		mounts[definition.weapon] = 1
	for weapon: WeaponDef in mounts:
		var rows: Array[Dictionary] = [
			{"label": "Damage per shot" if definition.get_faction_id() == &"machines" else "Damage per field release", "value": _damage(weapon)},
			{"label": "Weapon range", "value": String.num(weapon.base_range, 2) + " m"},
			{"label": "Base accuracy", "value": String.num(weapon.base_accuracy * 100.0, 2) + "%"},
		]
		if definition.get_faction_id() == &"machines":
			_stat(rows, "Independent weapon mounts", int(mounts[weapon]))
			_stat(rows, "Shot interval per mount", weapon.fire_rate, " s")
		var title: String = "Fortress laser battery" if definition.get_faction_id() == &"machines" else weapon.get_display_name_or_default()
		var text: String = "Base weapon values before run scaling, range falloff and target evasion. Each shot rolls its own hit." if definition.get_faction_id() == &"machines" else "Base weapon values before run scaling, range falloff and target evasion. Each committed field rolls its own hit."
		sections.append({"title": title, "text": text, "stats": rows})
