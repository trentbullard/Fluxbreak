extends Node

## Saved unlock fixtures and browsing checks use a unique user-data namespace.
const MENU_SCENE: PackedScene = preload("res://scenes/main_menu/main_menu.tscn")
const BASE_SHIP: ShipDef = preload("res://content/data/ships/starter_fighter.tres")
const BASE_WEAPON: WeaponDef = preload("res://content/data/weapons/pulse_mk1.tres")
const AUTHORED_WEAPONS: Array[WeaponDef] = [
	BASE_WEAPON,
	preload("res://content/data/weapons/laser_bolt_mk1.tres"),
	preload("res://content/data/weapons/drone_bay_mk1.tres"),
	preload("res://content/data/weapons/particle_beam_mk1.tres"),
]
const BUTTONS: String = "CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/"
const PANEL: String = "EnemyInformationPanel"
const GRID: String = "EnemyInformationPanel/Margin/Content/UnlockGrid"
const ENEMY_GRID: String = "EnemyInformationPanel/Margin/Content/EnemyGrid"
const CLOSE: String = "EnemyInformationPanel/Margin/Content/Header/Close"

var _menu: Control
var _grid: UnlockInformationGrid
var _panel: Control
var _close: Button
var _roster: PilotRoster
var _alpha: PilotDef
var _beta: PilotDef
var _ship_a: ShipDef
var _ship_b: ShipDef
var _weapon_a: WeaponDef
var _weapon_b: WeaponDef
var _weapon_c: WeaponDef
var _checks: int = 0
var _failures: int = 0
var _output: String = ""
var _panel_identity: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run_checks.call_deferred()

func _run_checks() -> void:
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Information Categories Validation":
		push_error("Information category checks require their isolated wrapper.")
		get_tree().quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	if not _output.is_empty():
		DirAccess.make_dir_recursive_absolute(_output)
	get_tree().root.size = Vector2i(1280, 720)
	AudioServer.set_bus_mute(0, true)
	get_tree().node_added.connect(_silence)
	GameFlow.abandon_run()
	_make_fixture()
	_seed_kills(0)
	GameFlow._cached_roster = _roster
	GameFlow.set_selected_pilot(_alpha)
	GameFlow.set_selected_ship(_ship_a)
	GameFlow.set_selected_weapon(_weapon_a)
	_menu = MENU_SCENE.instantiate() as Control
	_menu.set("pilot_roster", _roster)
	_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_menu)
	await _frames(6)
	_grid = _menu.get_node(GRID) as UnlockInformationGrid
	_panel = _menu.get_node(PANEL) as Control
	_close = _menu.get_node(CLOSE) as Button
	_panel_identity = _panel.get_instance_id()
	_button("InformationContainer/Information").pressed.emit()
	await _frames(3)
	await _check_categories_and_navigation()
	await _check_saved_unlock_progress()
	await _check_authored_weapon_previews()
	await _check_empty_roster()
	_menu.queue_free()
	await _frames(5)
	GameFlow.abandon_run()
	print("INFORMATION_CATEGORIES_CHECKS: %s (%d assertions, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _make_fixture() -> void:
	_weapon_a = _make_weapon("information_fixture_pulse", "Fixture Pulse")
	_weapon_b = _make_weapon("information_fixture_beam", "Fixture Beam")
	_weapon_c = _make_weapon("information_fixture_cannon", "Fixture Cannon")
	_ship_a = _make_ship(&"information_fixture_fighter", "Fixture Fighter")
	_ship_b = _make_ship(&"information_fixture_bruiser", "Fixture Bruiser")
	_ship_a.starter_weapon_options.assign([_weapon_option(_weapon_a), _weapon_option(_weapon_b, 5)])
	_ship_b.starter_weapon_options.assign([_weapon_option(_weapon_a), _weapon_option(_weapon_c)])
	_alpha = PilotDef.new()
	_alpha.id = &"information_fixture_alpha"
	_alpha.display_name = "Fixture Alpha"
	_alpha.ship = _ship_a
	_alpha.starter_ship_options.assign([_ship_option(_ship_a), _ship_option(_ship_b, 10)])
	_beta = PilotDef.new()
	_beta.id = &"information_fixture_beta"
	_beta.display_name = "Fixture Beta"
	_beta.ship = _ship_b
	_beta.starts_unlocked = false
	_beta.sort_order = 1
	var pilot_requirement: PilotUnlockRequirement = PilotUnlockRequirement.new()
	pilot_requirement.stat = UnlockRequirement.UnlockStat.KILLS
	pilot_requirement.minimum_value = 20
	_beta.unlock_requirements.assign([pilot_requirement])
	# An individually unlocked option on a locked pilot is not an available path.
	_beta.starter_ship_options.assign([_ship_option(_ship_b), _ship_option(_ship_a)])
	_roster = PilotRoster.new()
	_roster.pilots.assign([_alpha, _beta, _alpha])

func _make_weapon(id: String, name_text: String) -> WeaponDef:
	var result: WeaponDef = BASE_WEAPON.duplicate() as WeaponDef
	result.weapon_id = id
	result.display_name = name_text
	return result

func _make_ship(id: StringName, name_text: String) -> ShipDef:
	var result: ShipDef = BASE_SHIP.duplicate() as ShipDef
	result.id = id
	result.display_name = name_text
	result.starter_weapon_options = []
	return result

func _requirement(kills: int) -> UnlockRequirement:
	var result: UnlockRequirement = UnlockRequirement.new()
	result.stat = UnlockRequirement.UnlockStat.KILLS
	result.minimum_value = kills
	return result

func _weapon_option(weapon: WeaponDef, kills: int = 0) -> ShipStarterWeaponOptionDef:
	var result: ShipStarterWeaponOptionDef = ShipStarterWeaponOptionDef.new()
	result.weapon = weapon
	result.starts_unlocked = kills == 0
	if kills > 0:
		result.unlock_requirements.assign([_requirement(kills)])
	return result

func _ship_option(ship: ShipDef, kills: int = 0) -> PilotStarterShipOptionDef:
	var result: PilotStarterShipOptionDef = PilotStarterShipOptionDef.new()
	result.ship = ship
	result.starts_unlocked = kills == 0
	if kills > 0:
		result.unlock_requirements.assign([_requirement(kills)])
	return result

func _seed_kills(kills: int) -> void:
	var saved: ConfigFile = ConfigFile.new()
	if FileAccess.file_exists(GameFlow.SAVE_PATH):
		saved.load(GameFlow.SAVE_PATH)
	saved.set_value(GameFlow.META_SECTION, GameFlow.META_KEY_SAVE_SCHEMA_VERSION, GameFlow.CURRENT_SAVE_SCHEMA_VERSION)
	saved.set_value(GameFlow.META_SECTION, GameFlow.META_KEY_GAME_VERSION, ProjectSettings.get_setting("application/config/version", "dev"))
	saved.set_value(GameFlow.META_STATS_GLOBAL_SECTION, "kills", kills)
	_expect(saved.save(GameFlow.SAVE_PATH) == OK, "Unlock fixture saves only isolated progression")
	GameFlow._load_user_data()

func _open(category: StringName) -> void:
	var name_text: String = String(category).capitalize()
	_button(name_text + "Container/" + name_text).pressed.emit()
	await _frames(4)
	_expect(_menu.call("get_current_page") == category, "Category button opens " + String(category))
	_expect(_panel.get_instance_id() == _panel_identity and _panel.is_visible_in_tree(), "Categories reuse the same visible panel")
	_expect(_grid.is_visible_in_tree() and not (_menu.get_node(ENEMY_GRID) as Control).visible, "Only the unlock grid is shown for " + String(category))
	_expect((_menu.get_node(PANEL + "/Margin/Content/Header/Title") as Label).text == String(category).to_upper(), "Shared header names the active category")
	for name: String in ["Enemies", "Weapons", "Ships", "Pilots"]:
		_expect(_button(name + "Container/" + name).is_visible_in_tree(), "Information action remains visible: " + name)

func _check_categories_and_navigation() -> void:
	var selected_pilot: PilotDef = GameFlow.selected_pilot
	var selected_ship: ShipDef = GameFlow.get_selected_ship()
	var selected_weapon: WeaponDef = GameFlow.get_selected_weapon()
	var saved_before: String = FileAccess.get_file_as_string(GameFlow.SAVE_PATH)
	for category: StringName in [&"weapons", &"ships", &"pilots"]:
		await _open(category)
		var buttons: Array[Button] = _grid.get_entry_buttons()
		_expect(buttons.size() == (3 if category == &"weapons" else 2), "Canonical IDs deduplicate shared unlock paths in " + String(category))
		var ids: Dictionary = {}
		for entry: Button in buttons:
			var id: StringName = StringName(entry.get_meta("entry_id", &""))
			_expect(id != &"" and not ids.has(id) and StringName(entry.get_meta("entry_type", &"")) == category, "Each icon has one typed canonical identity")
			ids[id] = true
			entry.pressed.emit()
			_expect(_menu.call("get_current_page") == category, "Placeholder activation opens no details")
		_expect(get_viewport().gui_get_focus_owner() == buttons[0], "Opening focuses the first visible icon")
		await _action(&"ui_left")
		var name: String = String(category).capitalize()
		_expect(get_viewport().gui_get_focus_owner() == _button(name + "Container/" + name), "Grid Left returns to the active category")
		await _action(&"ui_right")
		_expect(get_viewport().gui_get_focus_owner() == buttons[0], "Menu Right reenters its active grid")
		await _check_layout()
		await _capture(String(category) + "_placeholders_720p.png")
	_expect(GameFlow.selected_pilot == selected_pilot and GameFlow.get_selected_ship() == selected_ship and GameFlow.get_selected_weapon() == selected_weapon, "Browsing cannot change the selected pilot, ship, or starting weapon")
	_expect(FileAccess.get_file_as_string(GameFlow.SAVE_PATH) == saved_before, "Browsing and inert activation never write saved progression")
	await _open(&"weapons")
	_check_state(_weapon_a.get_weapon_id(), true)
	_check_state(_weapon_b.get_weapon_id(), false)
	_check_state(_weapon_c.get_weapon_id(), false)
	await _open(&"ships")
	_check_state(_ship_a.get_ship_id(), true)
	_check_state(_ship_b.get_ship_id(), false)
	await _open(&"pilots")
	_check_state(_alpha.get_pilot_id(), true)
	_check_state(_beta.get_pilot_id(), false)
	var source: Button = (_menu.get_node("UpgradesPanel") as UpgradesPanel).btn_close
	_expect(_close.flat == source.flat and _close.get_theme_font("font") == source.get_theme_font("font") and _close.get_theme_font_size("font_size") == source.get_theme_font_size("font_size"), "All categories retain the meta-upgrade close appearance")
	for category: StringName in [&"weapons", &"ships", &"pilots"]:
		await _open(category)
		if category == &"weapons":
			_close.pressed.emit()
		elif category == &"ships":
			_button("BackContainer/Back").pressed.emit()
		else:
			await _action(&"ui_cancel")
		await _frames(3)
		var name: String = String(category).capitalize()
		_expect(_menu.call("get_current_page") == &"information" and not _panel.visible, "Close, Back, and cancel close a category panel")
		_expect(get_viewport().gui_get_focus_owner() == _button(name + "Container/" + name), "Closing restores its matching category focus")
	_button("EnemiesContainer/Enemies").pressed.emit()
	await _frames(3)
	_expect(_panel.get_instance_id() == _panel_identity and (_menu.get_node(ENEMY_GRID) as Control).is_visible_in_tree() and not _grid.visible, "Enemies switches the same panel back to the kill grid")

func _check_saved_unlock_progress() -> void:
	_seed_kills(6)
	await _open(&"weapons")
	_check_state(_weapon_b.get_weapon_id(), true)
	_check_state(_weapon_c.get_weapon_id(), false)
	await _open(&"ships")
	_check_state(_ship_b.get_ship_id(), false)
	_seed_kills(12)
	await _open(&"ships")
	_check_state(_ship_b.get_ship_id(), true)
	await _open(&"weapons")
	_check_state(_weapon_c.get_weapon_id(), true)
	await _open(&"pilots")
	_check_state(_beta.get_pilot_id(), false)
	_seed_kills(25)
	await _open(&"pilots")
	_check_state(_beta.get_pilot_id(), true)
	get_tree().root.size = Vector2i(1920, 1080)
	await _frames(6)
	await _check_layout()
	await _capture("pilots_placeholders_1080p.png")
	get_tree().root.size = Vector2i(1280, 720)
	await _frames(4)

func _check_empty_roster() -> void:
	_menu.set("pilot_roster", PilotRoster.new())
	for category: StringName in [&"weapons", &"ships", &"pilots"]:
		await _open(category)
		_expect(_grid.get_entry_buttons().is_empty(), "An empty roster does not invent category entries")
		_expect(get_viewport().gui_get_focus_owner() == _close and _close.is_visible_in_tree(), "An empty category retains a reachable Close action")
		_close.pressed.emit()
		await _frames(3)
		_expect(_menu.call("get_current_page") == &"information", "Empty categories can close normally")

func _check_state(id: StringName, expected: bool) -> void:
	var found: bool = false
	for button: Button in _grid.get_entry_buttons():
		if StringName(button.get_meta("entry_id", &"")) == id:
			found = true
			var weapon_model: bool = expected and StringName(button.get_meta("entry_type", &"")) == &"weapons"
			var text: String = "" if weapon_model else ("!" if expected else "?")
			_expect(button.text == text and bool(button.get_meta("unlocked", false)) == expected, "Saved prerequisite path controls icon " + String(id))
			if weapon_model:
				var preview: EnemyIconPreview = button.get_node_or_null("ModelPreview") as EnemyIconPreview
				_expect(preview != null and preview.visible, "Unlocked weapon replaces its marker with the shared model preview")
	_expect(found, "Roster contains expected identity " + String(id))

func _check_authored_weapon_previews() -> void:
	var ship: ShipDef = _make_ship(&"information_weapon_visuals", "Weapon Visual Fixture")
	var materials: Dictionary = {}
	var source_meshes: Dictionary = {}
	var weapons_by_id: Dictionary = {}
	for weapon: WeaponDef in AUTHORED_WEAPONS:
		weapons_by_id[weapon.get_weapon_id()] = weapon
		ship.starter_weapon_options.append(_weapon_option(weapon))
		var source: Node = weapon.visual_scene.instantiate()
		var meshes: Array[Mesh] = []
		_collect_weapon_meshes(source, true, meshes, materials)
		source_meshes[weapon.get_weapon_id()] = meshes
		source.free()
	# Shared starting options must still produce one portrait per weapon identity.
	ship.starter_weapon_options.append(_weapon_option(AUTHORED_WEAPONS[0]))
	var pilot: PilotDef = PilotDef.new()
	pilot.id = &"information_weapon_visuals"
	pilot.ship = ship
	pilot.starter_ship_options.assign([_ship_option(ship)])
	var roster: PilotRoster = PilotRoster.new()
	roster.pilots.assign([pilot])
	_menu.set("pilot_roster", roster)
	var selected_pilot: PilotDef = GameFlow.selected_pilot
	var selected_ship: ShipDef = GameFlow.get_selected_ship()
	var selected_weapon: WeaponDef = GameFlow.get_selected_weapon()
	var saved: String = FileAccess.get_file_as_string(GameFlow.SAVE_PATH)
	await _open(&"weapons")
	var buttons: Array[Button] = _grid.get_entry_buttons()
	_expect(buttons.size() == AUTHORED_WEAPONS.size(), "All four authored player weapons have one deduplicated portrait")
	var previews: Array[EnemyIconPreview] = []
	var poses: Array[Basis] = []
	for index: int in buttons.size():
		var button: Button = buttons[index]
		var weapon: WeaponDef = weapons_by_id[StringName(button.get_meta("entry_id", &""))] as WeaponDef
		var preview: EnemyIconPreview = button.get_node_or_null("ModelPreview") as EnemyIconPreview
		_expect(preview != null and button.text.is_empty(), "Authored weapon uses its 3D model: " + weapon.weapon_id)
		if preview == null:
			continue
		previews.append(preview)
		poses.append(preview.get_model_root().global_basis)
		_expect(preview.is_active() and preview.texture != null and preview.get_viewport_3d().own_world_3d, "Visible weapon model uses a small isolated viewport")
		_expect(preview.mouse_filter == Control.MOUSE_FILTER_IGNORE and preview.focus_mode == Control.FOCUS_NONE, "Weapon portrait leaves input on the original inert button")
		var copied: int = 0
		var safe: bool = true
		var actual: bool = true
		var compatible: bool = true
		for node: Node in preview.get_model_root().find_children("*", "", true, false):
			if node.get_script() != null or node is CollisionObject3D or node is AudioStreamPlayer or node is AudioStreamPlayer3D or node is Timer or node is AnimationPlayer or node is GPUParticles3D or node is CPUParticles3D:
				safe = false
			var mesh: MeshInstance3D = node as MeshInstance3D
			if mesh != null:
				copied += 1
				actual = actual and (source_meshes[weapon.get_weapon_id()] as Array).has(mesh.mesh)
				for surface: int in mesh.mesh.get_surface_count():
					var material: BaseMaterial3D = mesh.get_active_material(surface) as BaseMaterial3D
					compatible = compatible and (material == null or not material.subsurf_scatter_enabled)
		_expect(copied > 0 and copied == (source_meshes[weapon.get_weapon_id()] as Array).size() and actual, "Weapon thumbnail uses all authored visible hull meshes")
		_expect(safe and compatible, "Weapon preview contains no firing, drone, projectile, particle, audio or gameplay behavior")
		_check_weapon_framing(preview)
	await _frames(20)
	for index: int in previews.size():
		_expect(not poses[index].is_equal_approx(previews[index].get_model_root().global_basis), "Each visible weapon portrait rotates")
	await _capture("weapons_models_720p.png")
	for button: Button in buttons:
		button.pressed.emit()
	_expect(_menu.call("get_current_page") == &"weapons", "Activating weapon portraits still opens no details")
	_expect(GameFlow.selected_pilot == selected_pilot and GameFlow.get_selected_ship() == selected_ship and GameFlow.get_selected_weapon() == selected_weapon and FileAccess.get_file_as_string(GameFlow.SAVE_PATH) == saved, "Weapon previews change neither selected loadout nor saved progress")
	var originals_unchanged: bool = not materials.is_empty()
	for resource: Variant in materials.keys():
		var material: BaseMaterial3D = resource as BaseMaterial3D
		originals_unchanged = originals_unchanged and material.subsurf_scatter_enabled == bool(materials[resource])
	_expect(originals_unchanged, "Preview-only material adjustments leave authored weapon resources unchanged")
	_menu.hide()
	await _frames(6)
	poses.clear()
	for preview: EnemyIconPreview in previews:
		_expect(not preview.is_active() and preview.get_viewport_3d().render_target_update_mode == SubViewport.UPDATE_DISABLED, "Hidden menu stops weapon viewport rendering")
		poses.append(preview.get_model_root().global_basis)
	await _frames(12)
	for index: int in previews.size():
		_expect(poses[index].is_equal_approx(previews[index].get_model_root().global_basis), "Hidden weapon portraits do no rotation work")
	_menu.show()
	await _frames(6)
	for preview: EnemyIconPreview in previews:
		_expect(preview.is_active(), "Showing the menu resumes visible weapon portraits")
	await _open(&"ships")
	for preview: EnemyIconPreview in previews:
		_expect(not is_instance_valid(preview) or not preview.is_active(), "Switching category retires the old weapon rendering")
	await _open(&"weapons")
	_expect(_grid.find_children("*", "SubViewport", true, false).size() == AUTHORED_WEAPONS.size(), "Reopening weapons cannot accumulate duplicate preview viewports")
	var missing: WeaponDef = _make_weapon("information_missing_visual", "Missing Visual")
	missing.visual_scene = null
	ship.starter_weapon_options.assign([_weapon_option(missing), _weapon_option(AUTHORED_WEAPONS[0], 1000)])
	await _open(&"weapons")
	buttons = _grid.get_entry_buttons()
	_expect(buttons.size() == 2 and buttons[0].text == "!" and buttons[0].get_node_or_null("ModelPreview") == null, "An unlocked weapon without a visual safely retains its exclamation marker")
	_expect(buttons[1].text == "?" and buttons[1].get_node_or_null("ModelPreview") == null, "A locked weapon creates no preview viewport")
	_close.pressed.emit()
	await _frames(3)
	_expect(not _panel.visible and get_viewport().gui_get_focus_owner() == _button("WeaponsContainer/Weapons"), "Weapon previews retain Close and focus-return behavior")
	_menu.set("pilot_roster", _roster)

func _collect_weapon_meshes(node: Node, inherited_visible: bool, meshes: Array[Mesh], materials: Dictionary) -> void:
	var shown: bool = inherited_visible
	if node is Node3D:
		shown = shown and (node as Node3D).visible
	var mesh: MeshInstance3D = node as MeshInstance3D
	if shown and mesh != null and mesh.mesh != null:
		meshes.append(mesh.mesh)
		for surface: int in mesh.mesh.get_surface_count():
			var material: BaseMaterial3D = mesh.get_active_material(surface) as BaseMaterial3D
			if material != null:
				materials[material] = material.subsurf_scatter_enabled
	for child: Node in node.get_children():
		_collect_weapon_meshes(child, shown, meshes, materials)

func _check_weapon_framing(preview: EnemyIconPreview) -> void:
	var model: Node3D = preview.get_model_root()
	var camera: Camera3D = preview.get_camera_3d()
	var bounds: AABB = preview.get_model_bounds()
	var original: Basis = model.basis
	var framed: bool = bounds.is_finite() and bounds.size.length_squared() > 0.0
	for angle: float in [0.0, PI / 4.0, PI / 2.0, PI * 0.75]:
		model.rotation.y = angle
		for corner: int in range(8):
			var point: Vector3 = model.to_global(bounds.get_endpoint(corner))
			var projected: Vector2 = camera.unproject_position(point)
			framed = framed and not camera.is_position_behind(point) and Rect2(Vector2(2.0, 2.0), Vector2(preview.get_viewport_3d().size) - Vector2(4.0, 4.0)).has_point(projected)
	model.basis = original
	_expect(framed, "Shared framing keeps the weapon inside its portrait throughout rotation")

func _check_layout() -> void:
	var panel_rect: Rect2 = _panel.get_global_rect()
	var left_rect: Rect2 = (_menu.get_node("CenterContainer/MainMenuContainer/ButtonPanel") as Control).get_global_rect()
	_expect(get_viewport().get_visible_rect().encloses(panel_rect) and not panel_rect.intersects(left_rect) and panel_rect.position.x >= left_rect.end.x, "Shared panel fits to the right of the menu")
	_expect(panel_rect.encloses(_grid.get_global_rect()) and panel_rect.encloses(_close.get_global_rect()), "Grid and Close remain inside the shared panel")
	for button: Button in _grid.get_entry_buttons():
		_expect(_grid.get_global_rect().encloses(button.get_global_rect()), "Small authored fixture icons remain visible inside the grid")

func _button(path: String) -> Button:
	return _menu.get_node(BUTTONS + path) as Button

func _action(name: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = name
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	event = InputEventAction.new()
	event.action = name
	Input.parse_input_event(event)
	await _frames(2)

func _frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame

func _capture(filename: String) -> void:
	if _output.is_empty():
		return
	await RenderingServer.frame_post_draw
	_expect(get_viewport().get_texture().get_image().save_png(_output.path_join(filename)) == OK, "Rendered " + filename)

func _silence(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stream = null
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stream = null

func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("INFORMATION_CATEGORIES_CHECKS: " + description)
