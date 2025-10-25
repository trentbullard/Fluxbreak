# content/defs/enemy_def.gd (godot 4.5)
extends Resource
class_name EnemyDef

@export_group("Meta Attributes")
@export var id: String = ""               # e.g. "machine_drone_mk1"
@export var display_name: String = ""
@export var faction: String = ""          # see below
@export var role: String = ""             # see below
@export var tier: int = 1                 # 1..5
@export var threat_cost: int = 1
@export var bounty_scrap: int = 1         # economy faucet
@export var can_be_elite: bool = true     # whether to apply an affix
@export var affixes: Array[String] = []   # see below
@export var score_on_kill: int = 10

@export_group("Defense")
@export var max_hull: float = 20.0
@export var max_shield: float = 0.0
@export var shield_regen: float = 0.0
@export var evasion: float = 0.10
@export var thrust: float = 40.0

@export_group("Offense")
@export var weapon: WeaponDef
@export var team_id: int = 1              # optional, for IFF/targeting groups

@export_group("Visual")
@export var model_scene: PackedScene      # optional model override
@export var material: StandardMaterial3D  # optional single material to apply to all meshes

# --- Machines (AI Collective) ---
# drone
# sentinel
# reaper
# warden
# overmind

# affixes: prime, core, sigma
# mk1..mk5

# --- Mercs (Human/Corporate Force) ---
# corvette
# frigate
# destroyer
# cruiser

# battleship
# carrier
# - or -
# dreadnought?

# affixes: veteran, elite, vanguard
# mk1..mk5

# --- Bugs (Swarm Hive) ---
# sporeling
# carapace
# broodmother
# devourer
# hive queen

# affixes: alpha, apex, matron?
# color-code? tier I - tier III?
# larval -> mature -> apex -> royal

# --- Greys (Ethereal/Psionic Aliens) ---
# probe
# seeker
# vessel
# harbinger
# mothership

# affixes: eternal, awoken, voidborn
# proto -> awakened -> ascendant

# --- Roles ---
# Core Combat Roles:
# Brawler – Closes distance aggressively. Prefers ramming arcs or short-range bursts. Think “make the player backpedal.”
# Sniper – Maintains standoff range. Lingers near the edges of detection cones, forcing the player to chase.
# Support – Buffs or heals nearby allies (speed bursts, temporary shields, damage amplifiers). Often low-threat but high-priority targets.
# Scout – Fast, low-HP, extends vision for others or marks the player. Their main purpose is to alert heavier units.
# Bruiser / Vanguard – Slower than brawlers, but tanks damage and soaks aggro. Creates “walls” that shield glass cannons.

# Disruption Roles:
# Suppressor – Fires continuous beams or EMPs that reduce the player’s rate of fire, energy regen, or boost.
# Interceptor – Dashes to intercept projectiles or physically blocks line-of-fire.
# Tether / Harpooner – Pulls or slows the player, cutting off escape vectors.
# Displacer – Teleports or phase-shifts behind the player, disrupting predictable formations.
# Jammer – Scrambles radar, HUD, or auto-targeting, forcing manual awareness.

# Area Control Roles
# Seeder / Spawner – Leaves behind mines, spores, or autonomous drones.
# Siege / Artillery – Anchors at a distance to lob slow, high-damage AoE shells. Encourages line-of-sight play.
# Webber – Creates temporary zones that slow movement or boost damage taken.
# Terraformer – Alters the environment (ion storms, black-hole singularities, plasma clouds). Great for boss waves or rare elites.

# Adaptive / Utility Roles
# Assimilator – Absorbs wreckage from dead allies to evolve or repair.
# Hijacker – Briefly commandeers allied turrets, drones, or even environmental hazards.
# Echo / Clone – Creates decoy versions of itself or the player, forcing target verification.
# Specter / Phase – Can only be hit during certain windows (phasing enemies that appear/disappear).
# Collector – Prioritizes gathering dropped resources before the player, cutting your loot yield if ignored.

# How to Mix Them
# Each wave type could mix 2–3 roles for synergy (e.g. Bruisers + Supports + Snipers).
# Threat scaling isn’t just HP/damage—it’s composition density.
# You can even tag roles per faction flavor:

# Machines: Suppressor, Jammer, Spawner
# Mercs: Sniper, Support, Bruiser
# Bugs: Brawler, Seeder, Devourer
# Greys: Displacer, Specter, Harpooner
