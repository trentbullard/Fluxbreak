# content/defs/stat_types.gd - autoload (godot 4.5)
extends Node

## Central enum of all upgradable stats.
## IMPORTANT: append new entries to the end to preserve serialized enum values in resources.
enum Stat {
	# Mobility
	MAX_SPEED_FORWARD,
	MAX_SPEED_REVERSE,
	ACCEL_FORWARD,
	ACCEL_REVERSE,
	BOOST_MULT,
	DRAG,
	ANGULAR_RATE_PITCH,
	ANGULAR_RATE_YAW,
	ANGULAR_RATE_ROLL,
	ANGULAR_ACCEL_PITCH,
	ANGULAR_ACCEL_YAW,
	ANGULAR_ACCEL_ROLL,
	
	# Defenses
	MAX_HULL,
	MAX_SHIELD,
	SHIELD_REGEN,
	EVASION_BASE,
	DAMAGE_TAKEN_MULT,         # global incoming damage multiplier (0.9 = -10%) hard damage reduction
	REFLECT_DAMAGE,            # like thorns
	CRITICAL_HIT_RESISTANCE,
	
	# Firepower (weapon-level; applied via turret callbacks)
	WEAPON_FIRE_RATE,          # seconds between shots (lower is better)
	WEAPON_BASE_ACCURACY,
	WEAPON_BASE_RANGE,
	WEAPON_RANGE_FALLOFF,
	WEAPON_CRIT_CHANCE,
	WEAPON_GRAZE_ON_HIT,
	WEAPON_GRAZE_ON_MISS,
	WEAPON_GRAZE_MULT,
	WEAPON_CRIT_MULT,
	WEAPON_DAMAGE_MIN,
	WEAPON_DAMAGE_MAX,
	WEAPON_RANGE_BONUS,        # turret assignment bonus
	WEAPON_SYSTEMS_BONUS,      # additive accuracy systems bonus
	WEAPON_PENETRATION,
	WEAPON_SHIELD_EFFECTIVENESS,
	WEAPON_HULL_EFFECTIVENESS,
	
	# Ship-wide DoT / Status Effect
	APPLIED_STATUS_EFFECT_DURATION,
	APPLIED_STATUS_EFFECT_TICK_RATE,
	APPLIED_STATUS_EFFECT_DAMAGE,
	APPLIED_STATUS_EFFECT_DAMAGE_CRIT_CHANCE,
	APPLIED_STATUS_EFFECT_DAMAGE_CRIT_BONUS,
	SUSTAINED_STATUS_EFFECT_DURATION,  # effects recieved last less time
	SUSTAINED_STATUS_EFFECT_MAGNITUDE, # damage reduction, slow reduction, etc
	
	# Ship-wide Projectile Mods
	PROJECTILE_SIZE,
	PROJECTILE_SPEED,
	PROJECTILE_LIFE,
	PROJECTILE_SPREAD,
	
	# Utility / Economy
	PICKUP_RANGE,
	NANOBOT_GAIN_MULT,
	SCORE_GAIN_MULT,
	
	# Meta / FX
	SCANNER_RANGE, # turret controller target acquisition range
	ABILITY_COOLDOWN,
	PBAOE_RADIUS, # ship-based aoe abilities (e.g. emp) / weapons (e.g. shock/arc pulse weapon)
	REMOTE_AOE_RADIUS, # chemical, explosive, gravity, stasis mesh, etc. radius
	
	# Energy / Power Management
	ENERGY_REGEN_RATE,
	MAX_ENERGY,
	SYSTEM_EFFICIENCY,
	OVERHEAT_THRESHOLD,
	HEAT_DISSIPATION_RATE,

	# Pilot core attributes
	PILOT_G_TOLERANCE,
	PILOT_G_HARD_LIMIT,
	PILOT_PERCEPTION,
	PILOT_CHARISMA,
	PILOT_INGENUITY,

	# Pilot forward-load mobility tuning
	PILOT_FORWARD_ACCEL_MIN_SCALE,
	PILOT_FORWARD_SPEED_MIN_SCALE,
	PILOT_FORWARD_G_FROM_ANG_RATE,
	PILOT_FORWARD_G_FROM_ANG_ACCEL,
	PILOT_FORWARD_G_SMOOTHING_HZ,

	# Minion / drone controls
	MINION_RECHARGE_RATE,
	MINION_DISCHARGE_RATE,
	MINION_RADIO_RANGE,
}

## Types of damage
enum DamageTypes {
	BURN,
	RADIATION,
	ELECTRICAL,
	STASIS,
	GRAVITY,
	CHEMICAL,
	EMP,
	KINETIC,
	PLASMA,
	MAGNETIC,
	SONIC,
	NANITE,
	CRYO,
	VOID,
	PSIONIC,
	CORROSIVE,
}

## Processing phases: earlier phases feed later
## e.g. PRE_OVERRIDE then ADD/MULT then POST_OVERRIDE then clamps
enum Phase { PRE_OVERRIDE, ADD_MULT, POST_OVERRIDE, FINAL_CLAMP }

## Operation that the stat's value will be applied to the latest stat's value
enum Op { ADD, MULT, OVERRIDE, CLAMP_MIN, CLAMP_MAX, HARD_SET }
