extends Node

## Run through the unique-save wrapper; optional --output captures require a renderer.
const UPGRADE_MENU_SCENE: PackedScene = preload("res://scenes/hud/upgrade_menu.tscn")
const META_PANEL_SCENE: PackedScene = preload("res://scenes/main_menu/upgrades_panel.tscn")
const WEAPON: WeaponDef = preload("res://content/data/weapons/pulse_mk1.tres")
const META_ID: String = "composite_hull_materials"

var _checks: int = 0
var _failures: int = 0
var _output: String = ""
var _pois: Array[PoiInstance] = []
var _pool: Array[Upgrade] = []
var _menu: UpgradeMenu = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run_checks.call_deferred()

func _run_checks() -> void:
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Logistics Validation":
		push_error("Logistics checks require their isolated validation wrapper.")
		get_tree().quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	if not _output.is_empty():
		if DisplayServer.get_name() == "headless":
			push_error("Logistics captures require a renderer.")
			get_tree().quit(2)
			return
		DirAccess.make_dir_recursive_absolute(_output)
	get_tree().root.size = Vector2i(1280, 720)
	AudioServer.set_bus_mute(0, true)
	GameFlow.abandon_run()
	_check_save_and_meta_contract()
	_check_run_and_sector_contract()
	_check_offer_cache_and_refresh()
	_check_family_exclusion_and_fallbacks()
	_check_exhausted_pool()
	await _check_upgrade_ui()
	await _check_dynamic_ui_and_navigation()
	await _check_meta_ui()
	GameFlow.abandon_run()
	get_tree().paused = false
	for poi: PoiInstance in _pois:
		if is_instance_valid(poi):
			poi.queue_free()
	await _wait_frames(3)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("LOGISTICS_CHECKS: %s (%d assertions, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _check_save_and_meta_contract() -> void:
	var old_save: ConfigFile = ConfigFile.new()
	old_save.set_value(GameFlow.META_SECTION, GameFlow.META_KEY_SAVE_SCHEMA_VERSION, GameFlow.CURRENT_SAVE_SCHEMA_VERSION)
	old_save.set_value(GameFlow.META_SECTION, GameFlow.META_KEY_GAME_VERSION, ProjectSettings.get_setting("application/config/version", "dev"))
	old_save.set_value(GameFlow.META_SECTION, GameFlow.META_KEY_FLUX_ANCHORS, 1000)
	old_save.set_value(GameFlow.SCORE_SECTION, GameFlow.SCORE_KEY_HIGH_SCORE, 4321)
	old_save.set_value(GameFlow.META_UPGRADES_SECTION, META_ID, 1)
	old_save.set_value(GameFlow.META_STATS_GLOBAL_SECTION, "kills", 17)
	_check(old_save.save(GameFlow.SAVE_PATH) == OK, "The legacy fixture writes only into the isolated save namespace")
	GameFlow._load_user_data()
	_check(GameFlow.get_logistics_level("refresh_stock") == 0 and GameFlow.get_logistics_level("blacklist") == 0, "A save without logistics starts with zero purchased allowances")
	_check(GameFlow.high_score == 4321 and GameFlow.flux_anchors == 1000 and GameFlow.get_meta_upgrade_level(META_ID) == 1 and GameFlow.get_meta_stat_value(GameFlow.META_STAT_KILLS) == 17, "Adding logistics preserves legacy score, currency, stats and permanent upgrades")
	var catalog: Array[LogisticsDef] = GameFlow.get_all_logistics()
	_check(catalog.size() == 2, "The first pass exposes two resource-authored Logistics purchases")
	var refresh: LogisticsDef = _find_logistics("refresh_stock")
	var blacklist: LogisticsDef = _find_logistics("blacklist")
	_check(refresh != null and refresh.max_tiers == 3 and blacklist != null and blacklist.max_tiers == 1, "Permanent allowances cap at three refreshes and one blacklist")
	if refresh == null or blacklist == null:
		return
	var max_cost: int = refresh.get_total_cost_for_levels(0, 3) + blacklist.get_total_cost_for_levels(0, 1)
	_check(max_cost > 0, "Authored Logistics allowances cost Flux Anchors")
	var upgrade_levels: Dictionary = GameFlow.get_current_meta_upgrade_levels()
	var pending_upgrade_levels: Dictionary = upgrade_levels.duplicate()
	pending_upgrade_levels[META_ID] = 2
	var stat_transition_cost: int = 0
	for upgrade: MetaUpgradeDef in GameFlow.get_all_meta_upgrades():
		if upgrade.id == META_ID:
			stat_transition_cost = upgrade.get_tier_cost(2)
	var old_levels: Dictionary = GameFlow.get_current_logistics_levels()
	var old_entries: Array[Dictionary] = GameFlow.get_purchased_meta_upgrade_entries()
	GameFlow.flux_anchors = max_cost + stat_transition_cost - 1
	GameFlow._save_user_data()
	var before_file: String = FileAccess.get_file_as_string(GameFlow.SAVE_PATH)
	_check(not GameFlow.apply_meta_purchases(pending_upgrade_levels, {"refresh_stock": 3, "blacklist": 1}), "Insufficient funds reject a combined stat-upgrade and Logistics purchase even when either section alone is affordable")
	_check(GameFlow.flux_anchors == max_cost + stat_transition_cost - 1 and GameFlow.get_current_logistics_levels() == old_levels and GameFlow.get_current_meta_upgrade_levels() == upgrade_levels and FileAccess.get_file_as_string(GameFlow.SAVE_PATH) == before_file, "Rejected purchases mutate neither section, balance nor saved data")
	GameFlow.flux_anchors = 10000
	_check(GameFlow.apply_meta_purchases(upgrade_levels, {"refresh_stock": 999, "blacklist": 999, "unknown_tool": 999}), "A valid affordable transaction normalizes configured allowance limits")
	_check(GameFlow.flux_anchors == 10000 - max_cost and GameFlow.get_logistics_level("refresh_stock") == 3 and GameFlow.get_logistics_level("blacklist") == 1 and GameFlow.get_logistics_level("unknown_tool") == 0, "Capped known purchases charge exactly their authored cost and ignore unknown IDs")
	_check(GameFlow.get_purchased_meta_upgrade_entries() == old_entries, "Logistics are not inserted into the stat-upgrade entry list")
	GameFlow._load_user_data()
	_check(GameFlow.get_logistics_level("refresh_stock") == 3 and GameFlow.get_logistics_level("blacklist") == 1 and GameFlow.flux_anchors == 10000 - max_cost, "Purchased allowances and currency survive save/reload")
	_check(GameFlow.high_score == 4321 and GameFlow.get_meta_stat_value(GameFlow.META_STAT_KILLS) == 17, "Save/reload preserves unrelated legacy progression")
	_check(GameFlow.apply_meta_upgrades(upgrade_levels) and GameFlow.get_logistics_level("refresh_stock") == 3 and GameFlow.get_logistics_level("blacklist") == 1, "Legacy meta-upgrade callers preserve Logistics purchases")
	var malformed: ConfigFile = ConfigFile.new()
	_check(malformed.load(GameFlow.SAVE_PATH) == OK, "The saved transaction can be loaded as a ConfigFile")
	malformed.set_value("logistics", "refresh_stock", 500)
	malformed.set_value("logistics", "blacklist", -5)
	malformed.set_value("logistics", "unknown_tool", 100)
	_check(malformed.save(GameFlow.SAVE_PATH) == OK, "Malformed allowance data is seeded only in the test save")
	GameFlow._load_user_data()
	_check(GameFlow.get_logistics_level("refresh_stock") == 3 and GameFlow.get_logistics_level("blacklist") == 0 and GameFlow.get_logistics_level("unknown_tool") == 0, "Loading clamps authored limits and rejects negative/unknown allowances")
	_purchase_max()

func _purchase_max() -> void:
	GameFlow.abandon_run()
	GameFlow.flux_anchors = 10000
	_check(GameFlow.apply_meta_purchases(GameFlow.get_current_meta_upgrade_levels(), {"refresh_stock": 3, "blacklist": 1}), "The fixture purchases the configured maximum allowances")

func _check_run_and_sector_contract() -> void:
	GameFlow.start_new_run(PracticeRunFactory.create_run(&"machines", false))
	_check(RunState.get_refresh_stock_remaining() == 3 and RunState.get_blacklist_remaining() == 1, "A Campaign snapshots purchased allowances at run start")
	var saved: String = FileAccess.get_file_as_string(GameFlow.SAVE_PATH)
	var anchors: int = GameFlow.flux_anchors
	_check(not GameFlow.apply_meta_purchases(GameFlow.get_current_meta_upgrade_levels(), {}), "Permanent Logistics cannot be refunded or repurchased during an active run")
	_check(GameFlow.flux_anchors == anchors and RunState.get_refresh_stock_remaining() == 3 and FileAccess.get_file_as_string(GameFlow.SAVE_PATH) == saved, "Rejected live-run Logistics changes preserve the snapshot and persistent save")
	_check(RunState.try_use_refresh_stock() and RunState.try_blacklist_upgrade_family("fixture_owned"), "Run-local actions consume their independent allowance pools")
	var stage: StageDef = GameFlow.get_current_stage()
	var routes: Array[SectorRouteDef] = stage.get_gateway_routes()
	_check(not routes.is_empty(), "The actual Campaign exposes its next-sector routes")
	if not routes.is_empty():
		_check(GameFlow.advance_to_next_stage(routes[0].get_destination_id()), "The actual Campaign route advances to the second sector")
	_check(RunState.get_refresh_stock_remaining() == 2 and RunState.get_blacklist_remaining() == 0 and RunState.is_upgrade_family_blacklisted("fixture_owned"), "Sector transfer preserves remaining allowances and run-wide exclusions")
	_check(not RunState.try_blacklist_upgrade_family("fixture_other"), "Exhausted blacklists cannot be overspent")
	RunState.try_use_refresh_stock()
	RunState.try_use_refresh_stock()
	_check(not RunState.try_use_refresh_stock() and RunState.get_refresh_stock_remaining() == 0, "Refresh allowances stop at zero")
	GameFlow.start_new_run(PracticeRunFactory.create_run(&"bugs", true))
	_check(RunState.get_refresh_stock_remaining() == 3 and RunState.get_blacklist_remaining() == 1 and RunState.get_blacklisted_upgrade_families().is_empty(), "A new Practice run replenishes its transient allowances and clears old exclusions")
	var balance: int = GameFlow.flux_anchors
	saved = FileAccess.get_file_as_string(GameFlow.SAVE_PATH)
	RunState.try_use_refresh_stock()
	RunState.try_blacklist_upgrade_family("practice_fixture")
	GameFlow.abandon_run()
	_check(GameFlow.flux_anchors == balance and FileAccess.get_file_as_string(GameFlow.SAVE_PATH) == saved and GameFlow.get_logistics_level("blacklist") == 1, "Practice use changes no permanent currency, stock or saved progression")
	RunState.start_run()
	_check(RunState.get_refresh_stock_remaining() == 3 and RunState.get_blacklist_remaining() == 1 and not RunState.is_upgrade_family_blacklisted("practice_fixture"), "Starting another run resets tools without changing permanent purchases")

func _make_upgrade(family: String, tier: int, tag: String = "offense") -> Upgrade:
	var item: Upgrade = Upgrade.new()
	item.id = "%s_%d" % [family, tier]
	item.family_id = family
	item.tier = tier
	item.display_name = "%s %d" % [family.replace("_", " ").capitalize(), tier]
	item.descripton = "A logistics offer fixture."
	item.cost = 1000
	item.tags.assign([tag])
	return item

func _make_pool() -> Array[Upgrade]:
	var items: Array[Upgrade] = []
	for family: int in range(4):
		for tier: int in range(1, 3):
			items.append(_make_upgrade("fixture_family_%d" % family, tier))
	return items

func _poi(tags: Array[String] = ["offense"]) -> PoiInstance:
	var definition: PoiDef = PoiDef.new()
	definition.poi_id = "logistics_fixture"
	definition.display_name = "Logistics Fixture"
	definition.upgrade_choices = 3
	definition.upgrade_tags = tags
	var poi: PoiInstance = PoiInstance.new()
	poi.configure(definition, _pois.size() + 1, _pois.size())
	add_child(poi)
	_pois.append(poi)
	return poi

func _service(items: Array[Upgrade], choices: int = 3) -> UpgradeOfferService:
	var service: UpgradeOfferService = UpgradeOfferService.new()
	service.configure(items, [WEAPON], preload("res://content/data/upgrades/upgrade_offer_memory_default.tres"), choices)
	return service

func _ids(offer: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for upgrade: Upgrade in offer.get("upgrades", []):
		result.append(upgrade.id)
	return result

func _costs_by_id(offer: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var upgrades: Array = offer.get("upgrades", [])
	var costs: Array = offer.get("costs", [])
	for index: int in range(upgrades.size()):
		result[(upgrades[index] as Upgrade).id] = costs[index]
	return result

func _check_offer_cache_and_refresh() -> void:
	_pool = _make_pool()
	var service: UpgradeOfferService = _service(_pool)
	for seed_value: int in [1, 7, 29, 103]:
		seed(seed_value)
		RunState.start_run()
		var poi: PoiInstance = _poi()
		var initial: Dictionary = service.get_or_create_offer(poi)
		_check(_ids(initial).size() == 3, "Seeded station offers retain their authored choice count")
		var repeated: Dictionary = service.get_or_create_offer(poi)
		_check(_ids(repeated) == _ids(initial) and repeated.get("costs") == initial.get("costs") and repeated.get("weapon") == initial.get("weapon"), "Reopening a station preserves its choices, prices and weapon")
		var history: Array[String] = RunState.get_purchased_upgrade_ids()
		_check(service.can_refresh_stock(poi) and service.refresh_stock(poi), "An eligible alternate stock selection can be requested")
		var refreshed: Dictionary = service.get_or_create_offer(poi)
		var shared: int = 0
		for upgrade_id: String in _ids(refreshed):
			if _ids(initial).has(upgrade_id):
				shared += 1
		_check(shared == 0 and _ids(refreshed).size() == 3 and RunState.get_refresh_stock_remaining() == 2, "Refresh maximizes new eligible choices and consumes exactly one use")
		_check(refreshed.get("weapon") == initial.get("weapon") and RunState.get_purchased_upgrade_ids() == history, "Refresh changes neither the weapon offer nor purchase history")
		var other_poi: PoiInstance = _poi()
		service.get_or_create_offer(other_poi)
		_check(service.refresh_stock(other_poi) and RunState.get_refresh_stock_remaining() == 1, "Different stations share one run-wide refresh pool")
	RunState.start_run()
	var limited: Array[Upgrade] = [_pool[0], _pool[2], _pool[4]]
	var limited_service: UpgradeOfferService = _service(limited)
	var limited_poi: PoiInstance = _poi()
	var limited_before: Dictionary = limited_service.get_or_create_offer(limited_poi)
	_check(not limited_service.can_refresh_stock(limited_poi) and not limited_service.refresh_stock(limited_poi), "A pool already showing every legal upgrade cannot charge for a meaningless refresh")
	var limited_after: Dictionary = limited_service.get_or_create_offer(limited_poi)
	_check(RunState.get_refresh_stock_remaining() == 3 and _ids(limited_before) == _ids(limited_after) and limited_before.get("costs") == limited_after.get("costs"), "No-alternative refresh preserves both the allowance and existing prices")
	var small_pool: Array[Upgrade] = [_pool[0], _pool[2], _pool[4], _pool[6]]
	var small_service: UpgradeOfferService = _service(small_pool)
	var small_poi: PoiInstance = _poi()
	var small_before: Dictionary = small_service.get_or_create_offer(small_poi)
	_check(small_service.refresh_stock(small_poi), "A small pool can still provide a useful partial refresh")
	var small_after: Dictionary = small_service.get_or_create_offer(small_poi)
	var repeated_ids: int = 0
	var before_costs: Dictionary = _costs_by_id(small_before)
	for upgrade_id: String in _ids(small_after):
		if before_costs.has(upgrade_id):
			repeated_ids += 1
			_check(_costs_by_id(small_after)[upgrade_id] == before_costs[upgrade_id], "Necessary repeated choices preserve their existing prices")
	_check(repeated_ids == 2 and _ids(small_after).size() == 3 and RunState.get_refresh_stock_remaining() == 2, "One available alternative replaces one slot while filling the other slots without duplicates")

func _check_family_exclusion_and_fallbacks() -> void:
	RunState.start_run()
	var service: UpgradeOfferService = _service(_pool)
	var poi: PoiInstance = _poi()
	var initial: Dictionary = service.get_or_create_offer(poi)
	var selected: Upgrade = initial.get("upgrades", [])[0] as Upgrade
	var original_costs: Dictionary = _costs_by_id(initial)
	var history: Array[String] = RunState.get_purchased_upgrade_ids()
	RunState.record_upgrade_purchase(selected.id, selected)
	var owned_history: Array[Dictionary] = RunState.get_purchased_upgrade_entries()
	var other_tier: Upgrade = _make_upgrade(selected.family_id, 99)
	var fallback_item: Upgrade = _make_upgrade("fallback_fixture", 1, "defense")
	var other_service: UpgradeOfferService = _service([selected, other_tier, fallback_item])
	var other_poi: PoiInstance = _poi(["offense"])
	var other_before: Dictionary = other_service.get_or_create_offer(other_poi)
	_check(_ids(other_before).has(selected.id) and _ids(other_before).has(other_tier.id), "The already-cached comparison station contains both tiers of the selected family")
	_check(service.blacklist_upgrade(poi, selected), "An offered upgrade family can be blacklisted")
	_check(RunState.get_blacklist_remaining() == 0 and RunState.is_upgrade_family_blacklisted(selected.family_id), "Blacklist records the run-wide family and consumes one allowance")
	var after: Dictionary = service.get_or_create_offer(poi)
	_check(after.get("weapon") == initial.get("weapon"), "Blacklisting does not replace the weapon offer")
	for upgrade: Upgrade in after.get("upgrades", []):
		_check(upgrade.family_id != selected.family_id, "A blacklisted family's other tiers cannot refill the slot")
		if original_costs.has(upgrade.id):
			_check(_costs_by_id(after).get(upgrade.id) == original_costs[upgrade.id], "Unchanged upgrade offers keep their original prices")
	_check(RunState.get_purchased_upgrade_entries() == owned_history and RunState.get_purchased_upgrade_ids().size() == history.size() + 1, "Blacklisting an owned family retains all purchased upgrade effects/history")
	var other_after: Dictionary = other_service.get_or_create_offer(other_poi)
	_check(not _ids(other_after).has(selected.id) and not _ids(other_after).has(other_tier.id) and _ids(other_after).has(fallback_item.id), "A different station repairs cached blacklisted tiers without resurrecting them through tag fallback")
	var empty_service: UpgradeOfferService = _service([selected, other_tier])
	var empty_offer: Dictionary = empty_service.get_or_create_offer(_poi(["utility"]))
	_check(_ids(empty_offer).is_empty(), "An empty station fallback never restores a blacklisted family")
	_check(not service.blacklist_upgrade(poi, selected), "Repeated or exhausted blacklist requests cannot consume below zero")
	var exclusions: PackedStringArray = RunState.get_blacklisted_upgrade_families()
	exclusions.clear()
	_check(RunState.is_upgrade_family_blacklisted(selected.family_id), "Caller mutation cannot erase run-owned exclusions")

func _check_exhausted_pool() -> void:
	RunState.start_run()
	var item: Upgrade = _make_upgrade("last_family", 1)
	var service: UpgradeOfferService = _service([item])
	var poi: PoiInstance = _poi()
	service.get_or_create_offer(poi)
	_check(service.blacklist_upgrade(poi, item) and _ids(service.get_or_create_offer(poi)).is_empty(), "Blacklisting the final legal family produces an honest empty offer")
	_check(not service.refresh_stock(poi) and RunState.get_refresh_stock_remaining() == 3, "An exhausted offer pool cannot spend refresh charges")
	_check(RunState.get_purchased_upgrade_ids().is_empty(), "Logistics tools never masquerade as purchased upgrades")

func _check_upgrade_ui() -> void:
	RunState.start_run()
	_menu = UPGRADE_MENU_SCENE.instantiate() as UpgradeMenu
	add_child(_menu)
	_menu.available_upgrades = _pool
	_menu.available_weapons = [WEAPON]
	RunState.nanobots_updated.emit(0)
	var poi: PoiInstance = _poi()
	_menu.show_for_poi(poi)
	await _wait_frames(4)
	_check(_menu._refresh_stock_button.text == "Refresh Stock (3)" and not _menu._refresh_stock_button.disabled, "Refresh Stock shows remaining uses in parentheses")
	_check(_menu._blacklist_buttons.size() == 3 and _menu._blacklist_buttons[0].text == "Blacklist (1)", "Every upgrade row has a Blacklist button with the shared allowance")
	_check(_menu._buttons[0].disabled and not _menu._blacklist_buttons[0].disabled, "An unaffordable upgrade can still be blacklisted")
	_check(_menu._weapon_separator.is_visible_in_tree() and _menu._weapon_separator.get_global_rect().position.y < _menu._buttons.back().get_global_rect().position.y, "A visible separator distinguishes upgrade tools from the weapon offer")
	_check(_menu._refresh_stock_button.get_global_rect().end.x <= _menu._buttons[0].get_global_rect().position.x, "Refresh Stock sits to the left of the upgrade choices")
	for index: int in range(_menu._blacklist_buttons.size()):
		var button: Button = _menu._blacklist_buttons[index]
		_check(button.get_global_rect().position.x >= _menu._buttons[index].get_global_rect().end.x and button.focus_mode == Control.FOCUS_ALL, "Blacklist sits to the right of its upgrade and accepts controller focus")
	var weapon: WeaponDef = _menu._weapon_choice
	_menu._refresh_stock_button.pressed.emit()
	await _wait_frames(3)
	_check(_menu.visible and get_tree().paused and _menu._refresh_stock_button.text == "Refresh Stock (2)" and _menu._weapon_choice == weapon, "The real refresh button updates its count, preserves the weapon and keeps the menu paused")
	var selected: Upgrade = _menu._upgrade_choices[0]
	_menu._blacklist_buttons[0].pressed.emit()
	await _wait_frames(3)
	_check(RunState.is_upgrade_family_blacklisted(selected.family_id) and _menu.visible, "The actual per-row Blacklist button excludes that family without purchasing or closing")
	for button: Button in _menu._blacklist_buttons:
		_check(button.text == "Blacklist (0)" and button.disabled, "Every Blacklist button updates and disables when the shared allowance is exhausted")
	await _capture("logistics_upgrade_menu_720p.png")
	_menu._refresh_stock_button.pressed.emit()
	_menu._refresh_stock_button.pressed.emit()
	await _wait_frames(3)
	_check(_menu._refresh_stock_button.text == "Refresh Stock (0)" and _menu._refresh_stock_button.disabled, "Refresh Stock updates and disables at zero uses")
	var before_close: PackedStringArray = PackedStringArray()
	for upgrade: Upgrade in _menu._upgrade_choices:
		before_close.append(upgrade.id)
	var costs_before: Array[int] = _menu._upgrade_offer_costs.duplicate()
	_menu.btn_close.pressed.emit()
	await _wait_frames(2)
	_menu.show_for_poi(poi)
	await _wait_frames(3)
	var after_reopen: PackedStringArray = PackedStringArray()
	for upgrade: Upgrade in _menu._upgrade_choices:
		after_reopen.append(upgrade.id)
	_check(after_reopen == before_close and _menu._upgrade_offer_costs == costs_before and _menu._refresh_stock_button.disabled, "Actual close/re-dock preserves stock, prices and exhausted allowance")
	_menu.btn_close.pressed.emit()
	_menu.queue_free()
	await _wait_frames(3)

func _check_dynamic_ui_and_navigation() -> void:
	RunState.start_run()
	var menu: UpgradeMenu = UPGRADE_MENU_SCENE.instantiate() as UpgradeMenu
	add_child(menu)
	RunState.nanobots_updated.emit(100000)
	var poi: PoiInstance = _poi()
	var definition: PoiDef = preload("res://content/data/pois/offense_station.tres").duplicate(true) as PoiDef
	definition.upgrade_choices = 4
	poi.configure(definition, 400, 400)
	menu.show_for_poi(poi)
	await _wait_frames(4)
	_check(menu._upgrade_choices.size() == 4 and menu._blacklist_buttons.size() == 4 and menu._buttons.size() == 5 and menu._buttons.back() == menu._weapon_button, "A future four-choice POI receives one tool per upgrade and retains its separate final weapon slot")
	var viewport: Rect2 = get_viewport().get_visible_rect()
	for button: Button in menu._buttons + menu._blacklist_buttons:
		_check(viewport.encloses(button.get_global_rect()), "Real catalog names/descriptions and dynamic POI rows fit the 720p viewport")
	menu._buttons[0].grab_focus()
	await _send_joy(JOY_BUTTON_DPAD_RIGHT)
	_check(get_viewport().gui_get_focus_owner() == menu._blacklist_buttons[0], "Controller Right moves from an upgrade to its Blacklist action")
	await _send_joy(JOY_BUTTON_DPAD_LEFT)
	_check(get_viewport().gui_get_focus_owner() == menu._buttons[0], "Controller Left returns from Blacklist to its upgrade")
	await _send_key(KEY_TAB)
	_check(get_viewport().gui_get_focus_owner() == menu._blacklist_buttons[0], "Tab follows the explicit upgrade-to-Blacklist focus order")
	menu._refresh_stock_button.grab_focus()
	await _send_joy(JOY_BUTTON_A)
	_check(RunState.get_refresh_stock_remaining() == 2 and menu.visible and get_tree().paused, "Controller Accept activates Refresh Stock without leaving the paused offer screen")
	await _wait_frames(3)
	await _capture("logistics_real_catalog_four_choices_720p.png")
	menu.btn_close.pressed.emit()
	menu.queue_free()
	await _wait_frames(3)

func _check_meta_ui() -> void:
	GameFlow.abandon_run()
	GameFlow.apply_meta_purchases(GameFlow.get_current_meta_upgrade_levels(), {})
	GameFlow.flux_anchors = 10000
	var panel: UpgradesPanel = META_PANEL_SCENE.instantiate() as UpgradesPanel
	add_child(panel)
	panel.show_panel()
	await _wait_frames(4)
	var texts: PackedStringArray = PackedStringArray()
	for label: Node in panel.find_children("*", "Label", true, false):
		texts.append((label as Label).text.to_lower())
	_check(texts.has("logistics"), "The meta purchase panel has a distinct Logistics section")
	_check(_find_text(panel, "Refresh Stock") and _find_text(panel, "Blacklist"), "Both allowance types are visible in the meta purchase panel")
	_check(panel._logistics_row_data.size() == 2, "Logistics use their own rows rather than appearing as stat upgrades")
	for row: Dictionary in panel._logistics_row_data:
		var item: LogisticsDef = row["logistics"] as LogisticsDef
		for level: int in range(item.max_tiers):
			(row["plus_btn"] as Button).pressed.emit()
		_check((row["plus_btn"] as Button).disabled, "The real Logistics plus button disables at its authored allowance cap")
	_check(GameFlow.get_logistics_level("refresh_stock") == 0 and GameFlow.get_logistics_level("blacklist") == 0 and not panel._apply_btn.disabled, "Logistics changes are staged until Apply")
	for row: Dictionary in panel._row_data:
		var upgrade: MetaUpgradeDef = row["upgrade"] as MetaUpgradeDef
		_check((row["tier_label"] as Label).text == "[%d/%d]" % [int(panel._pending_levels.get(upgrade.id, 0)), upgrade.max_tiers], "Staging Logistics leaves each permanent stat-upgrade tier display unchanged")
	await _wait_frames(3)
	await _capture("logistics_meta_panel_720p.png")
	panel._reset_btn.pressed.emit()
	_check(int(panel._pending_logistics_levels.get("refresh_stock", 0)) == 0 and int(panel._pending_logistics_levels.get("blacklist", 0)) == 0 and panel._apply_btn.disabled, "Reset discards staged Logistics changes without charging currency")
	for row: Dictionary in panel._logistics_row_data:
		(row["plus_btn"] as Button).pressed.emit()
	var cost: int = _find_logistics("refresh_stock").get_tier_cost(1) + _find_logistics("blacklist").get_tier_cost(1)
	panel._apply_btn.pressed.emit()
	_check(GameFlow.get_logistics_level("refresh_stock") == 1 and GameFlow.get_logistics_level("blacklist") == 1 and GameFlow.flux_anchors == 10000 - cost and panel._apply_btn.disabled, "Actual Logistics row and Apply buttons purchase both allowances at the shared Flux Anchor balance")
	panel.btn_close.pressed.emit()
	panel.queue_free()
	await _wait_frames(3)
	_purchase_max()

func _find_logistics(id: String) -> LogisticsDef:
	for item: LogisticsDef in GameFlow.get_all_logistics():
		if item.id == id:
			return item
	return null

func _find_text(parent: Node, text: String) -> bool:
	for node: Node in parent.find_children("*", "Label", true, false):
		if (node as Label).text.contains(text):
			return true
	return false

func _wait_frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame

func _send_key(code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await _wait_frames(2)
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	Input.parse_input_event(event)
	await _wait_frames(2)

func _send_joy(button: JoyButton) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await _wait_frames(2)
	event = InputEventJoypadButton.new()
	event.button_index = button
	Input.parse_input_event(event)
	await _wait_frames(2)

func _capture(filename: String) -> void:
	if _output.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_output.path_join(filename))

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
