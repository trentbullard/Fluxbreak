extends Node3D

## Opt-in, rendered validation. Its wrapper isolates saves and writes artifacts
## outside the repository. Backdrops are labelled representative geometry/shaders,
## rather than captures of the game's asset-backed environments.
const SWARM_SCENE: PackedScene = preload("res://scenes/drops/nanobot_swarm.tscn")
const SHIP_SCENE: PackedScene = preload("res://scenes/ship/ship.tscn")
const CORVETTE: MercEnemyDef = preload("res://content/data/enemies/merc_corvette_mk1.tres")
const WIDTH: int = 1280
const HEIGHT: int = 720
const BACKDROPS: Array[String] = ["empty_space", "asteroid_field", "planet", "solar_flare"]
const SAMPLE_FRAMES: int = 480
const WARMUP_FRAMES: int = 360

var _camera: Camera3D
var _arena: Node3D
var _backdrop: MeshInstance3D
var _environment: Environment
var _title: Label
var _distance_labels: Array[Label] = []
var _output: String = ""
var _screenshots_only: bool = false
var _checks: int = 0
var _failures: int = 0
var _reports: Array[Dictionary] = []

func _ready() -> void:
	call_deferred("_run_checks")

func _run_checks() -> void:
	if str(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Swarm Visual Validation":
		push_error("Swarm visual checks require their save-isolated validation wrapper.")
		get_tree().quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
		elif argument == "--screenshots-only":
			_screenshots_only = true
	if _output.is_empty() or DisplayServer.get_name() == "headless":
		push_error("Rendered swarm checks require a real display/rendering backend and an --output directory.")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_output)
	get_tree().node_added.connect(_mute_audio)
	GameFlow.abandon_run()
	_build_stage()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var captures: Array[Image] = []
	for index: int in range(BACKDROPS.size()):
		await _clear_arena()
		(_backdrop.material_override as ShaderMaterial).set_shader_parameter("backdrop_type", index)
		_title.text = "Representative %s | actual swarms | top: fresh / bottom: 90 s old (120 s lifetime)" % BACKDROPS[index].replace("_", " ")
		_add_distance_grid()
		await _wait_frames(80)
		var capture: Image = await _capture(BACKDROPS[index] + ".png")
		captures.append(capture)
		_check(not capture.is_empty(), "The %s rendered capture contains pixels." % BACKDROPS[index])
	_save_contact_sheet(captures)
	await _capture_stage_panoramas()
	await _check_particle_style_pixels()
	await _check_occlusion()
	await _clear_arena()
	(_backdrop.material_override as ShaderMaterial).set_shader_parameter("backdrop_type", 0)
	if not _screenshots_only:
		for count: int in [50, 100]:
			await _measure_matched_load(count)
	var report: Dictionary = {
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"resolution": [WIDTH, HEIGHT],
		"samples_per_case": SAMPLE_FRAMES,
		"backdrops": "Four labelled representative shader environments plus real stage panorama resources (empty space, asteroid field and planet); solar flare is representative.",
		"combatants": "Real Corvette physics/steering and separation, simple inherited hull mesh, weapon attacks disabled in both matched cases.",
		"baseline": "Same active production lifetime code and particle count, original cloud extent and opaque lit blue point material. Enhanced style uses the production outlined particle material; neither style has a centre badge.",
		"cpu_note": "render_cpu_ms is viewport render CPU timing; swarm_update_cpu_ms directly times 100 production lifetime/visual updates. Periodically refreshed Performance.TIME_PROCESS is retained as a diagnostic and is not a complete per-frame CPU measurement.",
		"metrics": _reports,
		"checks": _checks,
		"failures": _failures,
	}
	var report_name: String = "metrics_visual_only.json" if _screenshots_only else "metrics.json"
	var file: FileAccess = FileAccess.open(_output.path_join(report_name), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	await _clear_arena()
	print("NANOBOT_SWARM_VISUAL_CHECKS: %s (%d checks, %d failures); artifacts: %s" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures, _output])
	get_tree().quit(0 if _failures == 0 else 1)

func _build_stage() -> void:
	_arena = Node3D.new()
	add_child(_arena)
	_camera = Camera3D.new()
	_camera.fov = 70.0
	_camera.near = 0.1
	_camera.far = 10000.0
	add_child(_camera)
	_camera.make_current()
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = Environment.new()
	world_environment.environment.background_mode = Environment.BG_COLOR
	world_environment.environment.background_color = Color(0.002, 0.004, 0.009)
	world_environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_environment.environment.ambient_light_color = Color.WHITE
	world_environment.environment.ambient_light_energy = 0.8
	_environment = world_environment.environment
	add_child(world_environment)
	var backdrop_shader: Shader = Shader.new()
	backdrop_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform int backdrop_type = 0;
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 p = UV - vec2(0.5);
	vec3 color = vec3(0.003, 0.006, 0.018);
	float star = step(0.997, hash21(floor(UV * vec2(480.0, 270.0))));
	color += vec3(star * 0.8);
	if (backdrop_type == 1) {
		vec2 cell = floor(UV * vec2(13.0, 8.0));
		vec2 local = fract(UV * vec2(13.0, 8.0)) - vec2(0.5);
		float shape = length(local * vec2(1.0, 0.78));
		float rock = 1.0 - smoothstep(0.28, 0.31, shape);
		vec3 stone = mix(vec3(0.03, 0.025, 0.02), vec3(0.48, 0.40, 0.29), hash21(cell));
		color = mix(color, stone * (0.65 + local.x), rock);
	} else if (backdrop_type == 2) {
		float disk = 1.0 - smoothstep(0.38, 0.385, length(p * vec2(1.25, 1.0)));
		float stripe = 0.5 + 0.5 * sin(UV.y * 62.0 + sin(UV.x * 20.0));
		vec3 planet = mix(vec3(0.08, 0.19, 0.30), vec3(0.72, 0.79, 0.78), stripe);
		color = mix(color, planet * (0.45 + UV.x * 0.6), disk);
	} else if (backdrop_type == 3) {
		float distance = length(p * vec2(1.4, 1.0));
		float glow = exp(-distance * 3.0);
		float rays = pow(abs(sin(atan(p.y, p.x) * 11.0)), 16.0) * exp(-distance * 2.0);
		color += vec3(1.0, 0.47, 0.08) * glow + vec3(0.7, 0.42, 0.2) * rays;
		color = mix(color, vec3(1.0, 0.96, 0.76), 1.0 - smoothstep(0.19, 0.30, distance));
	}
	ALBEDO = color;
}
"""
	var backdrop_material: ShaderMaterial = ShaderMaterial.new()
	backdrop_material.shader = backdrop_shader
	_backdrop = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(18000.0, 10000.0)
	_backdrop.mesh = quad
	_backdrop.material_override = backdrop_material
	_backdrop.position.z = -6000.0
	add_child(_backdrop)
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_title = Label.new()
	_title.position = Vector2(18.0, 12.0)
	_title.add_theme_font_size_override("font_size", 19)
	_title.add_theme_constant_override("outline_size", 7)
	_title.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(_title)
	for column: int in range(3):
		var label: Label = Label.new()
		label.text = ["100 m", "1,000 m", "3,000 m"][column]
		label.position = Vector2(float(WIDTH) * (0.2 + float(column) * 0.3) - 34.0, float(HEIGHT) * 0.5 - 10.0)
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_constant_override("outline_size", 7)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		layer.add_child(label)
		_distance_labels.append(label)

func _add_distance_grid() -> void:
	var distances: Array[float] = [100.0, 1000.0, 3000.0]
	var tan_half_fov: float = tan(deg_to_rad(_camera.fov * 0.5))
	for row: int in range(2):
		for column: int in range(3):
			var distance: float = distances[column]
			var x: float = (float(column) - 1.0) * 0.6 * distance * tan_half_fov * float(WIDTH) / float(HEIGHT)
			var y: float = (0.34 if row == 0 else -0.34) * distance * tan_half_fov
			# Distance labels describe actual camera distance, including off-axis
			# columns, so the far column remains inside the 3,000 m clear band.
			var at: Vector3 = Vector3(x, y, -distance).normalized() * distance
			var swarm: NanobotSwarm = _spawn_swarm(at, 90.0 if row == 1 else 0.0)
			var visuals: Node = swarm.get_node_or_null("SwarmVisuals")
			if visuals != null:
				visuals.call("refresh_visuals")
			_check(swarm.get_node_or_null("ReadabilityCore") == null, "The swarm contains particles only, without a central badge.")

func _capture_stage_panoramas() -> void:
	var first_stage: StageDef = load("res://content/data/stages/stage_perimeter_breach.tres") as StageDef
	var second_stage: StageDef = load("res://content/data/stages/stage_reactor_graveyard.tres") as StageDef
	var textures: Array[Texture2D] = [first_stage.panorama_options[0], second_stage.panorama_options[0], second_stage.panorama_options[1]]
	var names: Array[String] = ["actual_empty_space", "actual_asteroid_field", "actual_planet"]
	_backdrop.hide()
	for index: int in range(textures.size()):
		await _clear_arena()
		var material: PanoramaSkyMaterial = PanoramaSkyMaterial.new()
		material.panorama = textures[index]
		var sky: Sky = Sky.new()
		sky.sky_material = material
		_environment.sky = sky
		_environment.background_mode = Environment.BG_SKY
		_environment.background_energy_multiplier = first_stage.background_energy_multiplier if index == 0 else second_stage.background_energy_multiplier
		_title.text = "Actual stage panorama: %s | top: fresh / bottom: 90 s old (120 s lifetime)" % names[index].trim_prefix("actual_").replace("_", " ")
		if index == 2:
			await _choose_bright_sky_view()
		_add_distance_grid()
		await _wait_frames(80)
		await _capture(names[index] + ".png")
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_energy_multiplier = 1.0
	_environment.sky = null
	_environment.sky_rotation = Vector3.ZERO
	_backdrop.show()

func _choose_bright_sky_view() -> void:
	# A panorama's planet can start behind the camera. Select its brightest
	# horizontal view using rendered pixels, rather than reading asset files or
	# accidentally documenting only the dark reverse side of that sky.
	var best_yaw: float = 0.0
	var best_luminance: float = -1.0
	for step: int in range(8):
		var yaw: float = float(step) * TAU / 8.0
		_environment.sky_rotation = Vector3(0.0, yaw, 0.0)
		await _wait_frames(8)
		await RenderingServer.frame_post_draw
		var capture: Image = get_viewport().get_texture().get_image()
		var brightness: float = 0.0
		for y: int in range(100, HEIGHT - 40, 60):
			for x: int in range(40, WIDTH - 40, 60):
				var color: Color = capture.get_pixel(x, y)
				brightness += color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
		if brightness > best_luminance:
			best_luminance = brightness
			best_yaw = yaw
	_environment.sky_rotation = Vector3(0.0, best_yaw, 0.0)

func _spawn_swarm(at: Vector3, age: float = 0.0) -> NanobotSwarm:
	var swarm: NanobotSwarm = SWARM_SCENE.instantiate() as NanobotSwarm
	swarm.initialize(1000)
	# Fully populate the existing two-second particle simulation for a readable
	# mature-cloud capture, rather than photographing only its first few points.
	swarm.particles.preprocess = swarm.particles.lifetime
	swarm.position = at
	_arena.add_child(swarm)
	if age > 0.0:
		swarm._process(age)
	swarm.set_process(false)
	return swarm

func _check_particle_style_pixels() -> void:
	await _clear_arena()
	_backdrop.hide()
	_environment.background_color = Color(0.78, 0.78, 0.78)
	_title.text = "Particle detail: original blue cloud versus larger bright particles with dark edges"
	# Labels have their own black outlines, which must not count as particle
	# contours in either the comparison or the subsequent occlusion capture.
	for label: Label in _distance_labels:
		label.hide()
	var swarm: NanobotSwarm = _spawn_swarm(Vector3(0.0, 0.0, -100.0))
	var swarms: Array[NanobotSwarm] = [swarm]
	_set_visual_style(swarms, false)
	await _wait_frames(40)
	var baseline: Image = await _capture("particles_original.png")
	_set_visual_style(swarms, true)
	await _wait_frames(40)
	var enhanced: Image = await _capture("particles_enhanced.png")
	var region: Rect2i = Rect2i(WIDTH / 2 - 240, HEIGHT / 2 - 240, 480, 480)
	var original_pixels: Dictionary = _particle_pixel_metrics(baseline, region)
	var enhanced_pixels: Dictionary = _particle_pixel_metrics(enhanced, region)
	print("SWARM_PARTICLE_PIXELS: original=%s enhanced=%s" % [JSON.stringify(original_pixels), JSON.stringify(enhanced_pixels)])
	_check(int(enhanced_pixels["tinted"]) > int(original_pixels["tinted"]), "The enhanced particle cloud occupies more cyan/blue pixels than the original point cloud.")
	_check(int(enhanced_pixels["contour"]) > int(original_pixels["contour"]) + 10, "Individual enhanced particles introduce dark contour contrast against a bright background.")
	_environment.background_color = Color(0.002, 0.004, 0.009)
	_backdrop.show()

func _check_occlusion() -> void:
	await _clear_arena()
	(_backdrop.material_override as ShaderMaterial).set_shader_parameter("backdrop_type", 0)
	_title.text = "Normal depth occlusion: centre swarm must disappear behind the solid foreground hull"
	var swarm: NanobotSwarm = _spawn_swarm(Vector3(0.0, 0.0, -100.0))
	await _wait_frames(30)
	swarm.particles.speed_scale = 0.0
	var visible: Image = await _capture("occlusion_before.png")
	var hull: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(64.0, 64.0, 2.0)
	hull.mesh = box
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.05, 0.04, 0.03)
	hull.material_override = material
	hull.position = Vector3(0.0, 0.0, -50.0)
	_arena.add_child(hull)
	await _wait_frames(5)
	var occluded: Image = await _capture("occlusion_after.png")
	var region: Rect2i = Rect2i(WIDTH / 2 - 220, HEIGHT / 2 - 220, 440, 440)
	var before: int = int(_particle_pixel_metrics(visible, region)["tinted"])
	var after: int = int(_particle_pixel_metrics(occluded, region)["tinted"])
	_check(before > 10 and after <= maxi(1, int(float(before) * 0.03)), "The foreground hull occludes the actual particle cloud (tinted pixels %d -> %d)." % [before, after])

func _measure_matched_load(count: int) -> void:
	await _clear_arena()
	seed(81357)
	var ship: Ship = SHIP_SCENE.instantiate() as Ship
	ship.freeze = true
	ship.process_mode = Node.PROCESS_MODE_DISABLED
	_arena.add_child(ship)
	# Outside every magnet range: swarms age normally, but both matched styles
	# retain the same stationary drop distribution instead of being collected.
	ship.position = Vector3(0.0, 0.0, 10000.0)
	# The ship prefab owns a current camera; keep the measurement camera fixed.
	_camera.make_current()
	ship.hull = 1000000.0
	ship.shield = 1000000.0
	var separation: EnemySeparation = EnemySeparation.new()
	_arena.add_child(separation)
	var definition: MercEnemyDef = CORVETTE.duplicate(false) as MercEnemyDef
	definition.model_scene = null
	var actors: Array[MercEnemy] = []
	for index: int in range(count):
		var actor: MercEnemy = definition.actor_scene.instantiate() as MercEnemy
		actor.set_ship(ship)
		var context: EnemySpawnContext = EnemySpawnContext.from_enemy_def(definition)
		context.is_summoned = true
		context.grants_kill_rewards = false
		context.contributes_to_pressure = false
		actor.configure_enemy(definition, context)
		actor.explosion_scene = null
		_arena.add_child(actor)
		actor.position = _actor_start(index)
		actor._attack_cooldown_left = 100000.0
		actors.append(actor)
	var swarms: Array[NanobotSwarm] = []
	for index: int in range(100):
		var depth: float = 100.0 + float(index % 10) * 260.0
		var x: float = (float(index % 10) - 4.5) * depth * 0.10
		var y: float = (float(index / 10) - 4.5) * depth * 0.065
		var swarm: NanobotSwarm = _spawn_swarm(Vector3(x, y, -depth))
		swarm.set_process(true)
		swarms.append(swarm)
	# An ABBA order reduces shader warmup and temperature/order bias. Each case
	# restores positions/velocities and both cases retain identical actor logic.
	for enhanced: bool in [false, true, true, false]:
		for index: int in range(actors.size()):
			actors[index].position = _actor_start(index)
			actors[index].linear_velocity = Vector3.ZERO
			actors[index].angular_velocity = Vector3.ZERO
		_set_visual_style(swarms, enhanced)
		_title.text = "Matched load: %d active Corvette fixtures + 100 independent 1,000-particle swarms | %s" % [count, "outlined particles" if enhanced else "original blue point cloud"]
		# Performance.TIME_PROCESS refreshes periodically. More than a second of
		# real warmup avoids reusing startup/import values in a fast GPU run.
		await _wait_frames(WARMUP_FRAMES)
		var render_cpu_ms: float = 0.0
		var render_gpu_ms: float = 0.0
		var process_ms: float = 0.0
		var frame_ms: float = 0.0
		var previous: int = Time.get_ticks_usec()
		for sample: int in range(SAMPLE_FRAMES):
			await get_tree().process_frame
			var current: int = Time.get_ticks_usec()
			frame_ms += float(current - previous) / 1000.0
			previous = current
			process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			render_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid())
			render_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		var result: Dictionary = {
			"combatants": count, "swarms": 100, "enhanced": enhanced,
			"wall_frame_ms": frame_ms / SAMPLE_FRAMES,
			"process_cpu_ms": process_ms / SAMPLE_FRAMES,
			"render_cpu_ms": render_cpu_ms / SAMPLE_FRAMES,
			"render_gpu_ms": render_gpu_ms / SAMPLE_FRAMES,
			"swarm_update_cpu_ms": _measure_swarm_updates(swarms, enhanced),
		}
		_reports.append(result)
		print("SWARM_MATCHED_LOAD: " + JSON.stringify(result))
		_check(render_cpu_ms > 0.0 and render_gpu_ms > 0.0, "Actual render CPU/GPU timing is available for the matched load.")
		if enhanced:
			await _capture("load_%d_enhanced.png" % count)
	await _capture("load_%d.png" % count)

func _measure_swarm_updates(swarms: Array[NanobotSwarm], enhanced: bool) -> float:
	# A direct batch avoids the periodically refreshed process monitor's stale
	# startup/spike samples. This covers swarm script work only, not whole-frame
	# physics/engine scheduling or render CPU work, which is reported separately.
	var started: int = Time.get_ticks_usec()
	for repetition: int in range(120):
		for swarm: NanobotSwarm in swarms:
			swarm._process(0.0001)
			if enhanced:
				var visuals: Node = swarm.get_node_or_null("SwarmVisuals")
				visuals.call("refresh_visuals")
	return float(Time.get_ticks_usec() - started) / 120000.0

func _actor_start(index: int) -> Vector3:
	return Vector3(float(index % 10) * 65.0 - 290.0, float(index / 10) * 42.0 - 180.0, -1200.0 - float(index % 3) * 70.0)

func _set_visual_style(swarms: Array[NanobotSwarm], enhanced: bool) -> void:
	for swarm: NanobotSwarm in swarms:
		# Restore identical test ages before each paired timing, without exposing
		# a production lifetime reset API that could refresh collected drops.
		swarm._age_sec = 0.0
		swarm._process(0.0)
		var visuals: Node3D = swarm.get_node_or_null("SwarmVisuals") as Node3D
		if visuals != null:
			visuals.process_mode = Node.PROCESS_MODE_INHERIT if enhanced else Node.PROCESS_MODE_DISABLED
		var particles: GPUParticles3D = swarm.particles
		if not particles.has_meta("enhanced_draw_pass"):
			particles.set_meta("enhanced_draw_pass", particles.draw_pass_1)
		particles.transparency = 0.0
		var material: ParticleProcessMaterial = particles.process_material.duplicate(true) as ParticleProcessMaterial
		# Explicit originals make repeated ABBA toggles idempotent.
		var extent: float = 2.5 if enhanced else 1.0
		material.emission_sphere_radius = extent
		material.initial_velocity_min = 5.0 * extent
		material.initial_velocity_max = 10.0 * extent
		material.radial_velocity_min = -3.0000222 * extent
		material.radial_velocity_max = -3.0000222 * extent
		particles.process_material = material
		if enhanced:
			particles.draw_pass_1 = particles.get_meta("enhanced_draw_pass") as Mesh
		else:
			var point_material: StandardMaterial3D = StandardMaterial3D.new()
			point_material.vertex_color_use_as_albedo = true
			point_material.albedo_color = Color(0.000031573774, 0.480375, 0.90340185, 1.0)
			point_material.emission_enabled = true
			point_material.emission = Color(0.000047841968, 0.47236526, 0.89034986)
			point_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			var point_mesh: PointMesh = PointMesh.new()
			point_mesh.material = point_material
			particles.draw_pass_1 = point_mesh
		if enhanced and visuals != null:
			visuals.call("refresh_visuals")
		particles.restart()

func _particle_pixel_metrics(image: Image, region: Rect2i) -> Dictionary:
	var tinted: int = 0
	var contour: int = 0
	for y: int in range(region.position.y, region.end.y):
		for x: int in range(region.position.x, region.end.x):
			var color: Color = image.get_pixel(x, y)
			if color.g > color.r + 0.08 and color.b > color.r + 0.08 and maxf(color.g, color.b) > 0.3:
				tinted += 1
			# The production 2–3 px points have antialiased, translucent edges.
			# Require a visible drop from the uniform 0.78 background, rather
			# than forcing those natural edges to contain opaque black pixels.
			if maxf(color.r, maxf(color.g, color.b)) < 0.65:
				contour += 1
	return {"tinted": tinted, "contour": contour}

func _save_contact_sheet(captures: Array[Image]) -> void:
	var sheet: Image = Image.create(WIDTH * 2, HEIGHT * 2, false, Image.FORMAT_RGBA8)
	for index: int in range(captures.size()):
		sheet.blit_rect(captures[index], Rect2i(0, 0, WIDTH, HEIGHT), Vector2i((index % 2) * WIDTH, (index / 2) * HEIGHT))
	sheet.save_png(_output.path_join("swarm_visibility_contact_sheet.png"))

func _capture(filename: String) -> Image:
	await RenderingServer.frame_post_draw
	var capture: Image = get_viewport().get_texture().get_image()
	capture.convert(Image.FORMAT_RGBA8)
	capture.save_png(_output.path_join(filename))
	return capture

func _clear_arena() -> void:
	for child: Node in _arena.get_children():
		child.queue_free()
	await _wait_frames(4)

func _wait_frames(count: int) -> void:
	for index: int in range(count):
		await get_tree().process_frame

func _mute_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stream = null
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stream = null

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("Swarm visuals: " + message)
