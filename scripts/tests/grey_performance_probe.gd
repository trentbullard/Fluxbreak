extends Node3D

## Diagnostic component comparison, never a production tuning or combat change.
const SHIP_SCENE: PackedScene = preload("res://scenes/ship/ship.tscn")
const GREY_SCENE: PackedScene = preload("res://scenes/enemies/grey_enemy.tscn")
const DEFINITIONS: Array[GreyEnemyDef] = [
	preload("res://content/data/enemies/grey_probe_mk1.tres"),
	preload("res://content/data/enemies/grey_seeker_mk1.tres"),
	preload("res://content/data/enemies/grey_vessel_mk1.tres"),
	preload("res://content/data/enemies/grey_harbinger_mk1.tres"),
	preload("res://content/data/enemies/grey_mothership_mk1.tres"),
]
const WARMUP_FRAMES: int = 60
const SAMPLE_FRAMES: int = 120
const WINDUP: float = 60.0
const MODES: Array[String] = ["no_warnings", "static_warnings", "dynamic_warnings", "dynamic_hidden"]

var _ship: Ship
var _camera: Camera3D
var _actors: Array[GreyEnemy] = []
var _warnings: Array[EnemyAttackTelegraph] = []
var _model_geometry: Array[GeometryInstance3D] = []
var _mode: String = "idle"
var _tick_usec: int = 0
var _tick_count: int = 0
var _reports: Array[Dictionary] = []
var _output: String = ""
var _capture_visuals: bool = false
var _environment: Environment
var _visual_captures: Array[Dictionary] = []

func _ready() -> void:
	_run_probe.call_deferred()

func _run_probe() -> void:
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Grey Performance Probe":
		push_error("Grey performance probe requires its save-isolated wrapper.")
		get_tree().quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
		elif argument == "--capture-visuals":
			_capture_visuals = true
	if _output.is_empty() or DisplayServer.get_name() == "headless":
		push_error("Grey performance probe requires Vulkan rendering and an output directory.")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_output)
	AudioServer.set_bus_mute(0, true)
	get_tree().node_added.connect(_mute_audio)
	GameFlow.abandon_run()
	get_tree().current_scene = self
	_build_stage()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await _wait_frames(120)
	for count: int in [50, 100, 150, 200]:
		_build_fixture(count)
		await _wait_frames(60)
		var point_test_ms: float = _measure_point_tests()
		for mode: String in MODES:
			await _measure_case(count, mode, point_test_ms)
		var reverse_modes: Array[String] = MODES.duplicate()
		reverse_modes.reverse()
		for mode: String in reverse_modes:
			await _measure_case(count, mode, point_test_ms)
		if count == 100:
			await _measure_case(count, "models_hidden", point_test_ms)
		if count == 200 and _capture_visuals:
			var original_camera: Transform3D = _camera.global_transform
			_camera.global_position = Vector3(0.0, 10.0, 20.0)
			_camera.look_at(Vector3(0.0, 0.0, -200.0), Vector3.UP)
			await _measure_case(count, "dynamic_close", point_test_ms)
			await _measure_case(count, "release_close", point_test_ms)
			_camera.global_transform = original_camera
		_clear_fixture()
		await _wait_frames(8)
	if _capture_visuals:
		await _capture_field_views()
	var report: Dictionary = {
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"resolution": [1280, 720],
		"warmup_frames": WARMUP_FRAMES,
		"sample_frames": SAMPLE_FRAMES,
		"fixture": "Authored Grey models and real weapon hosts, evenly mixed five ordinary classes. Actors frozen; movement, targeting, player weapons, HUD, separation, drops and attack damage resolution excluded. Directional shadows enabled.",
		"warning_fixture": "Actual production sphere/cylinder/paired patterns with 60-second diagnostic windup, reset to 60 percent per case. Hidden resident warnings remain allocated in baseline. Manual production warning physics runs at real 60 Hz; rendering capped at 240 FPS.",
		"interpretation": "Component comparison, not full-combat FPS. Viewport render CPU/GPU measurements exclude script time. Wall times include the frame cap. Direct tick CPU measurements include production visual updates and driver submissions. Point tests are a separate repeated microbenchmark.",
		"case_order": "Forward modes followed by reverse modes for each count (ABCDDCBA).",
		"close_up_stress": "Optional CaptureVisuals adds unmatched 200-enemy dynamic_close and release_close cases after matched measurements. Camera (0,10,20) looks toward (0,0,-200), inside overlapping fields. release_close holds every field at peak flash without resolving damage. These stress cases have no old-presentation baseline and must not be used for before/after claims.",
		"metrics": _reports,
		"visual_captures": _visual_captures,
	}
	var file: FileAccess = FileAccess.open(_output.path_join("metrics.json"), FileAccess.WRITE)
	if file == null:
		push_error("Could not write Grey performance metrics.")
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	_ship.queue_free()
	await _wait_frames(4)
	print("GREY_PERFORMANCE_PROBE: COMPLETE; metrics: " + _output.path_join("metrics.json"))
	get_tree().quit()

func _build_stage() -> void:
	var environment: Environment = Environment.new()
	_environment = environment
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.01, 0.02, 0.045)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.35, 0.5, 0.8)
	environment.ambient_light_energy = 0.8
	environment.glow_enabled = true
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30.0, -30.0, 0.0)
	light.light_energy = 1.7
	light.shadow_enabled = true
	add_child(light)
	_ship = SHIP_SCENE.instantiate() as Ship
	_ship.freeze = true
	_ship.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_ship)
	_ship.hull = 1000000.0
	_ship.shield = 1000000.0
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 120.0, 320.0)
	_camera.fov = 75.0
	_camera.far = 6000.0
	add_child(_camera)
	_camera.look_at(Vector3(0.0, 0.0, -350.0), Vector3.UP)
	_camera.make_current()

func _build_fixture(count: int) -> void:
	for index: int in range(count):
		var definition: GreyEnemyDef = DEFINITIONS[index % DEFINITIONS.size()]
		var actor: GreyEnemy = GREY_SCENE.instantiate() as GreyEnemy
		actor.player_ship = _ship
		actor.freeze = true
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		actor.configure_enemy(definition)
		actor.position = Vector3((float(index % 15) - 7.0) * 65.0, (float(index / 15) - float(count) / 30.0) * 43.0, -650.0 - float(index % 3) * 50.0)
		add_child(actor)
		actor._regen_timer.stop()
		actor._stop_warp_in()
		_actors.append(actor)
		for node: Node in actor.find_children("*", "GeometryInstance3D", true, false):
			_model_geometry.append(node as GeometryInstance3D)
		var host: EnemyTurret = actor._first_valid_turret()
		if host == null:
			push_error("Authored Grey fixture is missing its weapon host.")
			continue
		var primary: EnemyAttackTelegraph
		match index % 5:
			0:
				primary = EnemyAttackTelegraph.new()
				add_child(primary)
				primary.set_warning_style("PSIONIC PULSE", GreyAttackPattern.PULSE_TINT)
				primary.start_attack(actor, _ship, host, WINDUP, definition.behavior.attack_radius, false, Vector3.ZERO)
			1:
				primary = GreyAttackPattern.start(actor, _ship, host, "FORECAST", GreyAttackPattern.Shape.FORECAST, WINDUP, definition.behavior.attack_radius, 0.0, 0.0, definition.behavior.corridor_half_length, definition.behavior.corridor_radius)
			2:
				primary = GreyAttackPattern.start(actor, _ship, host, "CROSSING", GreyAttackPattern.Shape.CROSSING, WINDUP, definition.behavior.attack_radius, 0.0, 0.0, definition.behavior.corridor_half_length, definition.behavior.corridor_radius)
			_:
				primary = GreyAttackPattern.start(actor, _ship, host, "ECHO PAIR", GreyAttackPattern.Shape.ECHO_PAIR, WINDUP, definition.behavior.attack_radius, 0.0, 0.0, definition.behavior.corridor_half_length, definition.behavior.corridor_radius)
	for node: Node in get_tree().get_nodes_in_group("enemy_attack_telegraphs"):
		var warning: EnemyAttackTelegraph = node as EnemyAttackTelegraph
		warning.set_physics_process(false)
		warning._elapsed_sec = warning._windup_sec * 0.6
		warning._update_visuals(0.6)
		_warnings.append(warning)
	print("GREY_PROBE_FIXTURE: actors=%d warnings=%d model_geometry=%d" % [count, _warnings.size(), _model_geometry.size()])

func _physics_process(delta: float) -> void:
	if not _mode.begins_with("dynamic") and _mode != "models_hidden":
		return
	var started: int = Time.get_ticks_usec()
	for warning: EnemyAttackTelegraph in _warnings:
		warning._physics_process(delta)
	_tick_usec += Time.get_ticks_usec() - started
	_tick_count += 1

func _measure_case(count: int, mode: String, point_test_ms: float) -> void:
	_mode = "idle"
	var warning_visible: bool = mode != "no_warnings" and mode != "dynamic_hidden"
	for warning: EnemyAttackTelegraph in _warnings:
		warning.visible = warning_visible
		warning._elapsed_sec = warning._windup_sec * 0.6
		warning._update_visuals(0.6)
		if mode == "release_close":
			var field: MeshInstance3D = warning.get("_grey_field") as MeshInstance3D
			if field != null:
				field.call("set_release", 1.0)
	for visual: GeometryInstance3D in _model_geometry:
		visual.visible = mode != "models_hidden"
	_mode = mode
	await _wait_frames(WARMUP_FRAMES)
	_tick_usec = 0
	_tick_count = 0
	var samples: Array[float] = []
	var render_cpu: float = 0.0
	var render_gpu: float = 0.0
	var calls: float = 0.0
	var primitives: float = 0.0
	var previous: int = Time.get_ticks_usec()
	for index: int in range(SAMPLE_FRAMES):
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now
		render_cpu += RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid())
		render_gpu += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	_mode = "idle"
	samples.sort()
	var result: Dictionary = {
		"actors": count, "resident_warnings": _warnings.size(),
		"visible_warnings": _warnings.size() if warning_visible else 0,
		"mode": mode, "model_geometry_instances": _model_geometry.size(),
		"comparison": "unmatched_close_up_stress" if mode.ends_with("_close") else "matched_component_case",
		"wall_frame_median_ms": samples[samples.size() / 2],
		"wall_frame_p95_ms": samples[int(float(samples.size() - 1) * 0.95)],
		"render_cpu_ms": render_cpu / SAMPLE_FRAMES,
		"render_gpu_ms": render_gpu / SAMPLE_FRAMES,
		"draw_calls": calls / SAMPLE_FRAMES,
		"primitives": primitives / SAMPLE_FRAMES,
		"warning_update_cpu_ms_per_tick": float(_tick_usec) / float(maxi(_tick_count, 1)) / 1000.0,
		"warning_update_ticks": _tick_count,
		"point_test_cpu_ms_per_warning_batch": point_test_ms,
	}
	_reports.append(result)
	print("GREY_PROBE_CASE: " + JSON.stringify(result))
	if count == 100 and mode == "dynamic_warnings":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_output.path_join("grey_100_active.png"))
	elif count == 200 and mode.ends_with("_close"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_output.path_join("grey_200_%s.png" % mode))

func _measure_point_tests() -> float:
	var hits: int = 0
	var started: int = Time.get_ticks_usec()
	for repetition: int in range(500):
		for warning: EnemyAttackTelegraph in _warnings:
			if warning.contains_position(Vector3(float(repetition % 7) * 10.0, 0.0, 0.0)):
				hits += 1
	var elapsed: float = float(Time.get_ticks_usec() - started) / 500000.0
	set_meta("point_test_hits", hits)
	return elapsed

## Optional readability captures run after every timed case, never during samples.
## Bright solid color is a contrast stress test, not a substitute for stage playtesting.
func _capture_field_views() -> void:
	_build_fixture(5)
	_mode = "idle"
	for visual: GeometryInstance3D in _model_geometry:
		visual.visible = false
	for warning: EnemyAttackTelegraph in _warnings:
		warning.visible = false
	var sphere: EnemyAttackTelegraph = null
	var corridor: EnemyAttackTelegraph = null
	for warning: EnemyAttackTelegraph in _warnings:
		if warning._corridor and corridor == null:
			corridor = warning
		elif not warning._corridor and sphere == null:
			sphere = warning
	for warning: EnemyAttackTelegraph in [sphere, corridor]:
		if warning == null:
			continue
		var field: MeshInstance3D = warning.get("_grey_field") as MeshInstance3D
		if field == null or not field.has_method("set_release"):
			push_error("Field captures require the single-field Grey presentation.")
			continue
		warning.visible = true
		var center: Vector3 = (warning._locked_origin + warning._locked_position) * 0.5 if warning._corridor else warning._locked_position
		var shape: String = "corridor" if warning._corridor else "sphere"
		for background: String in ["dark", "bright"]:
			_environment.background_color = Color(0.78, 0.67, 0.43) if background == "bright" else Color(0.01, 0.02, 0.045)
			for view: String in ["outside", "inside"]:
				if view == "outside":
					var distance: float = maxf(warning._radius * 3.5, warning._locked_origin.distance_to(warning._locked_position)) if warning._corridor else warning._radius * 3.5
					_camera.global_position = center + Vector3(0.0, warning._radius * 0.6, distance)
					_camera.look_at(center, Vector3.UP)
				else:
					_camera.global_position = center + Vector3(0.0, warning._radius * 0.1, 0.0)
					_camera.look_at(center + Vector3(1.0, 0.1, -1.0) * warning._radius, Vector3.UP)
				for phase: String in ["forming", "charged", "release"]:
					var progress: float = 0.0 if phase == "forming" else 0.95
					warning._elapsed_sec = warning._windup_sec * progress
					warning._update_visuals(progress)
					if phase == "release":
						field.call("set_release", 1.0)
					await _wait_frames(4)
					await RenderingServer.frame_post_draw
					var filename: String = "field_%s_%s_%s_%s.png" % [shape, background, view, phase]
					get_viewport().get_texture().get_image().save_png(_output.path_join(filename))
					_visual_captures.append({"file": filename, "shape": shape, "background": background, "view": view, "phase": phase, "radius_metres": warning._radius})
		warning.visible = false
	_clear_fixture()

func _clear_fixture() -> void:
	_mode = "idle"
	for warning: EnemyAttackTelegraph in _warnings:
		if is_instance_valid(warning):
			warning.free()
	_warnings.clear()
	for actor: GreyEnemy in _actors:
		actor.free()
	_actors.clear()
	_model_geometry.clear()

func _wait_frames(count: int) -> void:
	for index: int in range(count):
		await get_tree().process_frame

func _mute_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stream = null
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stream = null
