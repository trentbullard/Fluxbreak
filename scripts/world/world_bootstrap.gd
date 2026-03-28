extends Node3D

@export var ship_scene: PackedScene

@onready var menu: Control = $MainMenuOverlay
@onready var hud: CanvasLayer = $HUD
@onready var stage_root: Node3D = $StageRoot
@onready var world_environment_node: WorldEnvironment = $StageRoot/WorldEnvironment
@onready var star: DirectionalLight3D = $StageRoot/Star
@onready var poi_spawner: PoiSpawner = $StageRoot/PoiSpawner
var _ship: Ship
var _active_stage_scene: Node = null
var _stage_rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _enter_tree() -> void:
	_ensure_ship_instance()

func _ready() -> void:
	_stage_rng.randomize()
	menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	menu.visible = true
	hud.visible = false
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.practice_requested.connect(_on_start_pressed)
	if not GameFlow.stage_changed.is_connected(_on_stage_changed):
		GameFlow.stage_changed.connect(_on_stage_changed)
	if menu.has_signal("selection_changed"):
		menu.selection_changed.connect(_on_menu_selection_changed)
	_refresh_ship_from_selection(true)
	_set_ship_run_visibility(false)

func _on_start_pressed() -> void:
	GameFlow.start_new_run()
	_set_ship_run_visibility(true)
	menu.visible = false
	hud.visible = true
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_menu_selection_changed() -> void:
	if not get_tree().paused:
		return
	_refresh_ship_from_selection(true)

func _refresh_ship_from_selection(reset_current_health: bool) -> void:
	var ship: Ship = _ensure_ship_instance()
	if ship == null:
		return
	ship.reconfigure_from_selected_pilot(reset_current_health)

func _set_ship_run_visibility(ship_visible: bool) -> void:
	var ship: Ship = _ensure_ship_instance()
	if ship == null:
		return
	ship.visible = ship_visible

func _on_stage_changed(stage: StageDef, _stage_index: int) -> void:
	_swap_stage_scene(stage)
	_apply_stage_environment(stage)
	if poi_spawner != null:
		poi_spawner.apply_stage_definition(stage)

func _ensure_ship_instance() -> Ship:
	if _ship != null and is_instance_valid(_ship):
		return _ship

	var existing: Ship = get_node_or_null("Ship") as Ship
	if existing != null:
		_ship = existing
		return _ship

	if ship_scene == null:
		push_warning("WorldBootstrap has no ship_scene assigned; unable to spawn Ship node.")
		return null

	var inst: Ship = ship_scene.instantiate() as Ship
	if inst == null:
		push_warning("ship_scene did not instantiate a Ship.")
		return null

	inst.name = "Ship"
	add_child(inst)
	_ship = inst
	return _ship

func _swap_stage_scene(stage: StageDef) -> void:
	var stage_root: Node3D = _ensure_stage_root()
	if stage_root == null:
		return
	if _active_stage_scene != null and is_instance_valid(_active_stage_scene):
		_active_stage_scene.queue_free()
		_active_stage_scene = null

	if stage == null or stage.stage_scene == null:
		return

	var stage_instance: Node = stage.stage_scene.instantiate()
	if stage_instance == null:
		push_warning("Stage scene failed to instantiate for %s." % stage.resource_path)
		return

	stage_instance.name = "ActiveStage"
	stage_root.add_child(stage_instance)
	_active_stage_scene = stage_instance

func _apply_stage_environment(stage: StageDef) -> void:
	if stage == null or world_environment_node == null:
		return

	var environment: Environment = _ensure_runtime_environment()
	if environment == null:
		return

	environment.background_energy_multiplier = stage.background_energy_multiplier
	environment.ambient_light_color = stage.ambient_light_color
	environment.ambient_light_energy = stage.ambient_light_energy
	environment.ambient_light_sky_contribution = stage.ambient_light_sky_contribution
	environment.glow_enabled = stage.glow_enabled
	environment.glow_intensity = stage.glow_intensity
	environment.glow_strength = stage.glow_strength
	environment.volumetric_fog_density = stage.volumetric_fog_density
	environment.volumetric_fog_albedo = stage.volumetric_fog_albedo
	environment.volumetric_fog_emission = stage.volumetric_fog_emission
	environment.volumetric_fog_emission_energy = stage.volumetric_fog_emission_energy

	var sky: Sky = environment.sky
	var sky_material: PanoramaSkyMaterial = null
	if sky != null:
		sky_material = sky.sky_material as PanoramaSkyMaterial
	var panorama: Texture2D = stage.pick_random_panorama(_stage_rng)
	if sky_material != null and panorama != null:
		sky_material.panorama = panorama

	if star != null:
		star.light_color = stage.star_light_color
		star.light_energy = stage.star_light_energy

func _ensure_runtime_environment() -> Environment:
	if world_environment_node == null:
		return null

	var environment: Environment = world_environment_node.environment
	if environment != null:
		environment = environment.duplicate(true) as Environment
	else:
		environment = Environment.new()

	var sky: Sky = environment.sky
	if sky != null:
		sky = sky.duplicate(true) as Sky
	else:
		sky = Sky.new()

	var sky_material: PanoramaSkyMaterial = sky.sky_material as PanoramaSkyMaterial
	if sky_material != null:
		sky_material = sky_material.duplicate(true) as PanoramaSkyMaterial
	else:
		sky_material = PanoramaSkyMaterial.new()

	sky.sky_material = sky_material
	environment.sky = sky
	world_environment_node.environment = environment
	return environment

func _ensure_stage_root() -> Node3D:
	if stage_root != null and is_instance_valid(stage_root):
		return stage_root
	push_warning("WorldBootstrap expected a StageRoot node but none was found.")
	return null
