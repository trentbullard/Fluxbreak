# scripts/hud/upgrade_menu.gd (Godot 4.5)
# Modal menu shown when docking at a POI is complete.
# Displays upgrade choices and allows player to pick one.
extends CanvasLayer
class_name UpgradeMenu

signal upgrade_selected(upgrade: Upgrade)
signal weapon_selected(weapon: WeaponDef)
signal menu_closed

@export_group("Upgrade Pool")
@export var available_upgrades: Array[Upgrade] = []
@export var available_weapons: Array[WeaponDef] = []
@export var offer_memory_def: UpgradeOfferMemoryDef

@export_group("Display")
@export var num_upgrade_choices: int = 3
@export var menu_font: FontFile = preload("res://assets/fonts/Oxanium/Oxanium-Regular.ttf")

@onready var btn_close: Button = $Close
const UPGRADE_COST_VARIANCE: float = 0.05
const TIER_PROGRESS_WAVE_SPAN: float = 10.0

var _root: Control
var _dim: ColorRect
var _container: VBoxContainer
var _title_label: Label
var _buttons: Array[Button] = []
var _current_poi: PoiInstance = null

# Choices for this menu instance
var _upgrade_choices: Array[Upgrade] = []
var _upgrade_offer_costs: Array[int] = []
var _weapon_choice: WeaponDef = null
var _last_offer_debug: Dictionary = {}

# Nanobot tracking
var _current_nanobots: int = 0
var _was_mouse_mode: int = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	RunState.nanobots_updated.connect(_on_nanobots_updated)
	layer = 3  # Above pause menu
	visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	
	_build_ui()


func _build_ui() -> void:
	# Root control
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_menu_font_theme()
	add_child(_root)
	
	# Dim background
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.0, 0.0, 0.0, 0.7)
	_root.add_child(_dim)
	
	# Center container
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	
	# Panel for the menu
	var panel: PanelContainer = PanelContainer.new()
	center.add_child(panel)
	
	# Reparent the close button into the root so it's above the dim background
	if btn_close != null:
		btn_close.reparent(_root)
		btn_close.focus_mode = Control.FOCUS_ALL
		btn_close.pressed.connect(_close_without_purchase)
	
	# Margin inside panel
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	panel.add_child(margin)
	
	# VBox for content
	_container = VBoxContainer.new()
	_container.add_theme_constant_override("separation", 15)
	margin.add_child(_container)
	
	# Title
	_title_label = Label.new()
	_title_label.text = "Choose 1 Upgrade"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 24)
	_container.add_child(_title_label)
	
	# Separator
	var sep: HSeparator = HSeparator.new()
	_container.add_child(sep)
	
	# Create buttons (3 upgrades + 1 weapon)
	for i in 4:
		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(400, 50)
		btn.focus_mode = Control.FOCUS_ALL
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(_on_button_pressed.bind(i))
		_container.add_child(btn)
		if btn_close != null:
			btn.focus_neighbor_right = btn.get_path_to(btn_close)
		_buttons.append(btn)

	if btn_close != null and _buttons.size() > 0:
		btn_close.focus_neighbor_bottom = btn_close.get_path_to(_buttons[0])
		_buttons[0].focus_neighbor_top = _buttons[0].get_path_to(btn_close)


func _apply_menu_font_theme() -> void:
	if _root == null or menu_font == null:
		return
	var theme: Theme = Theme.new()
	theme.default_font = menu_font
	_root.theme = theme


func show_for_poi(poi: PoiInstance) -> void:
	_current_poi = poi
	_randomize_choices(poi)
	_update_buttons()
	
	visible = true
	get_tree().paused = true
	
	# Show mouse cursor
	_was_mouse_mode = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Focus first button
	_focus_default_control()


func _randomize_choices(poi: PoiInstance) -> void:
	_upgrade_choices.clear()
	_upgrade_offer_costs.clear()
	_weapon_choice = null
	_last_offer_debug.clear()
	
	var choice_count: int = _get_upgrade_choice_count_for_poi(poi)
	var candidate_upgrades: Array[Upgrade] = _build_upgrade_pool_for_poi(poi)
	if candidate_upgrades.is_empty():
		candidate_upgrades = available_upgrades.duplicate()

	_upgrade_choices = _pick_weighted_upgrade_choices(candidate_upgrades, choice_count, poi)
	if _upgrade_choices.size() < mini(choice_count, candidate_upgrades.size()):
		var fill_pool: Array[Upgrade] = candidate_upgrades.duplicate()
		fill_pool.shuffle()
		for upgrade: Upgrade in fill_pool:
			if _upgrade_choices.size() >= choice_count:
				break
			if not _upgrade_choices.has(upgrade):
				_upgrade_choices.append(upgrade)

	for upgrade: Upgrade in _upgrade_choices:
		_upgrade_offer_costs.append(_roll_upgrade_offer_cost(upgrade))
	_append_offer_debug_choices()
	
	# Pick a random weapon
	if available_weapons.size() > 0:
		var shuffled_weapons: Array[WeaponDef] = available_weapons.duplicate()
		shuffled_weapons.shuffle()
		_weapon_choice = shuffled_weapons[0]


func _pick_weighted_upgrade_choices(pool: Array[Upgrade], count: int, poi: PoiInstance) -> Array[Upgrade]:
	var results: Array[Upgrade] = []
	if pool.is_empty() or count <= 0:
		return results

	var remaining: Array[Upgrade] = pool.duplicate()
	var context: Dictionary = _build_upgrade_context(poi)
	var desired: int = mini(count, remaining.size())

	while results.size() < desired and not remaining.is_empty():
		var family_weight_data: Dictionary = _build_family_weight_data(remaining, context)
		context["family_multipliers"] = family_weight_data.get("family_multipliers", {})
		if _last_offer_debug.is_empty():
			_last_offer_debug = family_weight_data.get("debug", {}).duplicate(true)
		var total_weight: float = 0.0
		var weights: Array[float] = []
		for upgrade: Upgrade in remaining:
			var weight: float = max(_get_upgrade_offer_weight(upgrade, context), 0.0)
			weights.append(weight)
			total_weight += weight

		if total_weight <= 0.0:
			break

		var pick: float = randf() * total_weight
		var accum: float = 0.0
		var picked_index: int = max(weights.size() - 1, 0)
		for i in weights.size():
			accum += weights[i]
			if pick <= accum:
				picked_index = i
				break

		results.append(remaining[picked_index])
		remaining.remove_at(picked_index)

	return results


func _build_upgrade_context(poi: PoiInstance) -> Dictionary:
	var purchased_ids: Array[String] = []
	if RunState.has_method("get_purchased_upgrade_ids"):
		purchased_ids = RunState.get_purchased_upgrade_ids()

	var counts_by_id: Dictionary = {}
	var highest_tier_by_family: Dictionary = {}
	for raw_id: String in purchased_ids:
		var id: String = raw_id.strip_edges().to_lower()
		if id == "":
			continue
		counts_by_id[id] = int(counts_by_id.get(id, 0)) + 1

		var family: String = _extract_upgrade_family_from_id(id)
		var tier: int = _extract_tier_from_id(id)
		var best_tier: int = int(highest_tier_by_family.get(family, 0))
		if tier > best_tier:
			highest_tier_by_family[family] = tier

	var wave_index: int = 1
	if RunState.has_method("get_wave_index"):
		wave_index = max(1, int(RunState.get_wave_index()))
	var wave_progress: float = clamp(float(wave_index - 1) / TIER_PROGRESS_WAVE_SPAN, 0.0, 1.0)
	var poi_type: int = _get_poi_type(poi)
	var poi_purchase_memory: Dictionary = {}
	if RunState.has_method("get_upgrade_purchase_memory_for_poi_type"):
		poi_purchase_memory = RunState.get_upgrade_purchase_memory_for_poi_type(poi_type)

	return {
		"counts_by_id": counts_by_id,
		"highest_tier_by_family": highest_tier_by_family,
		"wave_progress": wave_progress,
		"wave_index": wave_index,
		"poi_type": poi_type,
		"poi_purchase_memory": poi_purchase_memory,
		"stickiness_intensity": _compute_offer_memory_intensity(wave_index),
		"family_multipliers": {},
	}


func _get_upgrade_offer_weight(upgrade: Upgrade, context: Dictionary) -> float:
	var weight: float = _get_base_upgrade_offer_weight(upgrade, context)
	if upgrade == null:
		return weight
	var family: String = _get_upgrade_family(upgrade)
	var family_multipliers: Dictionary = context.get("family_multipliers", {})
	weight *= float(family_multipliers.get(family, 1.0))
	return max(weight, 0.0)


func _get_base_upgrade_offer_weight(upgrade: Upgrade, context: Dictionary) -> float:
	if upgrade == null:
		return 0.0

	var id: String = upgrade.id.strip_edges().to_lower()
	var tier: int = _get_upgrade_tier(upgrade)
	var family: String = _get_upgrade_family(upgrade)

	var counts_by_id: Dictionary = context.get("counts_by_id", {})
	var highest_tier_by_family: Dictionary = context.get("highest_tier_by_family", {})
	var wave_progress: float = float(context.get("wave_progress", 0.0))

	var weight: float = 1.0
	if tier <= 1:
		weight *= lerp(1.85, 0.65, wave_progress)
	elif tier == 2:
		weight *= lerp(0.70, 1.55, wave_progress)
	else:
		weight *= lerp(0.40, 1.80, wave_progress)

	var owned_same_count: int = int(counts_by_id.get(id, 0))
	if owned_same_count > 0:
		weight *= pow(0.35, owned_same_count)

	var highest_family_tier: int = int(highest_tier_by_family.get(family, 0))
	if highest_family_tier > 0:
		if tier == highest_family_tier + 1:
			weight *= 1.85
		elif tier <= highest_family_tier:
			weight *= 0.55
		else:
			weight *= 0.8
	elif tier > 1:
		weight *= lerp(0.55, 1.15, wave_progress)

	return max(weight, 0.0)


func _build_family_weight_data(pool: Array[Upgrade], context: Dictionary) -> Dictionary:
	var family_base_weights: Dictionary = {}
	var family_highest_candidate_tier: Dictionary = {}
	var family_has_repeat_candidates: Dictionary = {}
	var family_has_next_tier_candidates: Dictionary = {}
	var highest_tier_by_family: Dictionary = context.get("highest_tier_by_family", {})
	var poi_purchase_memory: Dictionary = context.get("poi_purchase_memory", {})
	var purchased_family_counts: Dictionary = poi_purchase_memory.get("counts_by_family", {})
	var intensity: float = float(context.get("stickiness_intensity", 0.0))

	for upgrade: Upgrade in pool:
		if upgrade == null:
			continue
		var family: String = _get_upgrade_family(upgrade)
		var tier: int = _get_upgrade_tier(upgrade)
		var base_weight: float = _get_base_upgrade_offer_weight(upgrade, context)
		family_base_weights[family] = float(family_base_weights.get(family, 0.0)) + base_weight
		family_highest_candidate_tier[family] = max(int(family_highest_candidate_tier.get(family, 0)), tier)
		var highest_owned_tier: int = int(highest_tier_by_family.get(family, 0))
		if highest_owned_tier > 0:
			if tier == highest_owned_tier + 1:
				family_has_next_tier_candidates[family] = true
			elif tier <= highest_owned_tier:
				family_has_repeat_candidates[family] = true

	var adjusted_family_weights: Dictionary = {}
	var family_multipliers: Dictionary = {}
	var debug_family_weights: Dictionary = {}
	var purchased_total: float = 0.0
	var unpurchased_total: float = 0.0

	for family_variant in family_base_weights.keys():
		var family: String = String(family_variant)
		var base_family_weight: float = float(family_base_weights.get(family, 0.0))
		var raw_multiplier: float = 1.0
		var purchase_count: int = int(purchased_family_counts.get(family, 0))
		var is_purchased: bool = purchase_count > 0
		if is_purchased and offer_memory_def != null:
			raw_multiplier += intensity * offer_memory_def.owned_family_base_bonus
			raw_multiplier += intensity * float(purchase_count) * offer_memory_def.owned_family_count_bonus
			if bool(family_has_repeat_candidates.get(family, false)):
				raw_multiplier += intensity * offer_memory_def.same_family_repeat_bonus
			if bool(family_has_next_tier_candidates.get(family, false)):
				raw_multiplier += intensity * offer_memory_def.same_family_next_tier_bonus

		var adjusted_weight: float = base_family_weight * max(raw_multiplier, 0.0)
		adjusted_family_weights[family] = adjusted_weight
		if is_purchased:
			purchased_total += adjusted_weight
		else:
			unpurchased_total += adjusted_weight

		debug_family_weights[family] = {
			"base_weight": base_family_weight,
			"raw_multiplier": raw_multiplier,
			"raw_weight": adjusted_weight,
			"purchase_count": purchase_count,
			"is_purchased": is_purchased,
			"has_repeat_candidate": bool(family_has_repeat_candidates.get(family, false)),
			"has_next_tier_candidate": bool(family_has_next_tier_candidates.get(family, false)),
			"highest_candidate_tier": int(family_highest_candidate_tier.get(family, 0)),
			"highest_owned_tier": int(highest_tier_by_family.get(family, 0)),
		}

	var purchased_scale: float = 1.0
	var unpurchased_scale: float = 1.0
	var total_weight: float = purchased_total + unpurchased_total
	if total_weight > 0.0 and purchased_total > 0.0 and unpurchased_total > 0.0 and offer_memory_def != null:
		var max_purchased_share: float = clamp(offer_memory_def.purchased_family_share_cap, 0.0, 1.0)
		var min_unpurchased_share: float = clamp(offer_memory_def.non_purchased_family_share_floor, 0.0, 1.0)
		max_purchased_share = min(max_purchased_share, 1.0 - min_unpurchased_share)

		var current_purchased_share: float = purchased_total / total_weight
		if current_purchased_share > max_purchased_share and current_purchased_share > 0.0:
			purchased_scale = max_purchased_share / current_purchased_share
			var current_unpurchased_share: float = unpurchased_total / total_weight
			var target_unpurchased_share: float = 1.0 - max_purchased_share
			if current_unpurchased_share > 0.0:
				unpurchased_scale = target_unpurchased_share / current_unpurchased_share

	for family_variant in adjusted_family_weights.keys():
		var family: String = String(family_variant)
		var base_family_weight: float = float(family_base_weights.get(family, 0.0))
		var family_debug: Dictionary = debug_family_weights.get(family, {})
		var is_purchased: bool = bool(family_debug.get("is_purchased", false))
		var capped_weight: float = float(adjusted_family_weights.get(family, 0.0))
		capped_weight *= purchased_scale if is_purchased else unpurchased_scale
		family_multipliers[family] = (capped_weight / base_family_weight) if base_family_weight > 0.0 else 1.0
		family_debug["capped_weight"] = capped_weight
		family_debug["final_multiplier"] = family_multipliers[family]
		debug_family_weights[family] = family_debug

	return {
		"family_multipliers": family_multipliers,
		"debug": {
			"poi_type": _get_poi_type_label(int(context.get("poi_type", PoiDef.PoiType.OFFENSE))),
			"stickiness_intensity": intensity,
			"purchased_families": PackedStringArray(poi_purchase_memory.get("families", PackedStringArray())),
			"purchase_counts_by_family": purchased_family_counts.duplicate(true),
			"family_weights": debug_family_weights,
			"purchased_family_share_cap": offer_memory_def.purchased_family_share_cap if offer_memory_def != null else 1.0,
			"non_purchased_family_share_floor": offer_memory_def.non_purchased_family_share_floor if offer_memory_def != null else 0.0,
		},
	}


func _extract_tier_from_id(raw_id: String) -> int:
	var id: String = raw_id.strip_edges().to_lower()
	if id == "":
		return 1
	var parts: PackedStringArray = id.split("_")
	if parts.is_empty():
		return 1
	var suffix: String = parts[parts.size() - 1]
	if suffix.is_valid_int():
		return max(suffix.to_int(), 1)
	return 1


func _extract_upgrade_family_from_id(raw_id: String) -> String:
	var id: String = raw_id.strip_edges().to_lower()
	if id == "":
		return "unknown"
	var parts: PackedStringArray = id.split("_")
	if parts.size() <= 1:
		return id
	var suffix: String = parts[parts.size() - 1]
	if not suffix.is_valid_int():
		return id
	parts.remove_at(parts.size() - 1)
	if parts.is_empty():
		return id
	return "_".join(parts)


func _get_upgrade_tier(upgrade: Upgrade) -> int:
	if upgrade == null:
		return 1
	var tier: int = max(upgrade.tier, 1)
	var id_tier: int = _extract_tier_from_id(upgrade.id)
	if id_tier > tier:
		tier = id_tier
	return tier


func _get_upgrade_family(upgrade: Upgrade) -> String:
	if upgrade == null:
		return "unknown"
	var explicit_family: String = upgrade.family_id.strip_edges().to_lower()
	if explicit_family != "":
		return explicit_family
	return _extract_upgrade_family_from_id(upgrade.id)


func _roll_upgrade_offer_cost(upgrade: Upgrade) -> int:
	if upgrade == null:
		return 1
	var base_cost: int = max(upgrade.cost, 1)
	var variance: float = randf_range(1.0 - UPGRADE_COST_VARIANCE, 1.0 + UPGRADE_COST_VARIANCE)
	return max(int(round(float(base_cost) * variance)), 1)


func _get_offer_cost(index: int, upgrade: Upgrade) -> int:
	if index >= 0 and index < _upgrade_offer_costs.size():
		return _upgrade_offer_costs[index]
	return _roll_upgrade_offer_cost(upgrade)


func _build_upgrade_pool_for_poi(poi: PoiInstance) -> Array[Upgrade]:
	var filtered: Array[Upgrade] = []
	var fallback: Array[Upgrade] = []
	var poi_tags: Array[String] = _get_poi_upgrade_tags(poi)

	for upgrade: Upgrade in available_upgrades:
		if upgrade == null:
			continue
		if poi_tags.is_empty():
			filtered.append(upgrade)
			continue

		var upgrade_tags: Array[String] = _get_upgrade_tags(upgrade)
		if _tags_overlap(upgrade_tags, poi_tags):
			filtered.append(upgrade)
		else:
			fallback.append(upgrade)

	if filtered.is_empty():
		return fallback

	var desired: int = _get_upgrade_choice_count_for_poi(poi)
	if filtered.size() < desired:
		for upgrade: Upgrade in fallback:
			if not filtered.has(upgrade):
				filtered.append(upgrade)

	return filtered


func _get_upgrade_choice_count_for_poi(poi: PoiInstance) -> int:
	var default_count: int = max(num_upgrade_choices, 1)
	if poi == null or poi.poi_def == null:
		return default_count
	return max(1, poi.poi_def.upgrade_choices)


func _get_poi_upgrade_tags(poi: PoiInstance) -> Array[String]:
	var tags: Array[String] = []
	if poi == null or poi.poi_def == null:
		return tags

	for raw_tag: String in poi.poi_def.upgrade_tags:
		_append_normalized_tag(tags, raw_tag)

	return tags


func _get_upgrade_tags(upgrade: Upgrade) -> Array[String]:
	var tags: Array[String] = []
	if upgrade == null:
		return tags

	for raw_tag: String in upgrade.tags:
		_append_normalized_tag(tags, raw_tag)
	if not tags.is_empty():
		return tags

	var id: String = upgrade.id.to_lower()
	if "bulkhead" in id or "hull" in id:
		_append_normalized_tag(tags, "defense")
		_append_normalized_tag(tags, "hull")
	if "shield" in id:
		_append_normalized_tag(tags, "defense")
		_append_normalized_tag(tags, "shields")
	if "targeting" in id or "precision" in id or "capacitor" in id or "weapon" in id or "damage" in id:
		_append_normalized_tag(tags, "offense")
		_append_normalized_tag(tags, "weapons")
		_append_normalized_tag(tags, "damage")
	if "systems" in id:
		_append_normalized_tag(tags, "utility")
		_append_normalized_tag(tags, "misc")
	if "salvage" in id or "magnet" in id:
		_append_normalized_tag(tags, "utility")
		_append_normalized_tag(tags, "misc")
	if "thruster" in id or "vectoring" in id:
		_append_normalized_tag(tags, "utility")
		_append_normalized_tag(tags, "misc")

	return tags


func _append_normalized_tag(target: Array[String], raw_tag: String) -> void:
	var normalized: String = raw_tag.strip_edges().to_lower()
	if normalized == "" or target.has(normalized):
		return
	target.append(normalized)


func _tags_overlap(left: Array[String], right: Array[String]) -> bool:
	if left.is_empty() or right.is_empty():
		return false

	for tag: String in left:
		if right.has(tag):
			return true
	return false


func _update_buttons() -> void:
	var nb: int = _current_nanobots
	
	# Update upgrade buttons
	for i in _buttons.size():
		var btn: Button = _buttons[i]
		
		if i < _upgrade_choices.size():
			# Upgrade button
			var upgrade: Upgrade = _upgrade_choices[i]
			var offer_cost: int = _get_offer_cost(i, upgrade)
			btn.text = "%s (%d)\n%s" % [upgrade.display_name, offer_cost, upgrade.descripton]
			btn.visible = true
			btn.disabled = offer_cost > nb
		elif i == _buttons.size() - 1 and _weapon_choice != null:
			# Weapon button (last button) - uses progressive pricing
			var weapon_cost: int = RunState.get_weapon_cost(_weapon_choice.cost)
			btn.text = "+ %s (%d)" % [_weapon_choice.display_name, weapon_cost]
			btn.visible = true
			btn.disabled = weapon_cost > nb
		else:
			btn.visible = false

	if visible:
		var focus_owner: Control = get_viewport().gui_get_focus_owner()
		if focus_owner == null:
			call_deferred("_focus_default_control")
		else:
			var focused_button: Button = focus_owner as Button
			if focused_button != null and (not focused_button.visible or focused_button.disabled):
				call_deferred("_focus_default_control")


func _on_button_pressed(index: int) -> void:
	if index < _upgrade_choices.size():
		# Upgrade selected
		var upgrade: Upgrade = _upgrade_choices[index]
		var offer_cost: int = _get_offer_cost(index, upgrade)
		if offer_cost > _current_nanobots:
			return  # Can't afford
		_spend_nanobots(offer_cost)
		RunState.record_upgrade_purchase(upgrade.id)
		if _current_poi != null and _current_poi.poi_def != null and RunState.has_method("record_upgrade_purchase_for_poi"):
			RunState.record_upgrade_purchase_for_poi(upgrade.id, _get_upgrade_family(upgrade), int(_current_poi.poi_def.poi_type))
		_apply_upgrade(upgrade)
		upgrade_selected.emit(upgrade)
	elif index == _buttons.size() - 1 and _weapon_choice != null:
		# Weapon selected - uses progressive pricing
		var weapon_cost: int = RunState.get_weapon_cost(_weapon_choice.cost)
		if weapon_cost > _current_nanobots:
			return  # Can't afford
		_spend_nanobots(weapon_cost)
		_apply_weapon(_weapon_choice)
		weapon_selected.emit(_weapon_choice)
	
	_close_menu()


func _apply_upgrade(upgrade: Upgrade) -> void:
	# Emit the appropriate signal based on upgrade type
	# For now, use a generic approach - check the upgrade id prefix
	var id: String = upgrade.id.to_lower()
	
	if "bulkhead" in id or "reinforced" in id:
		EventBus.add_bulkhead_requested.emit(upgrade)
	elif "shield" in id or "adaptive" in id:
		EventBus.add_shield_requested.emit(upgrade)
	elif "targeting" in id or "precision" in id or "capacitor" in id or "overcharged" in id:
		EventBus.add_targeting_requested.emit(upgrade)
	elif "systems" in id or "optimization" in id:
		EventBus.add_systems_requested.emit(upgrade)
	elif "salvage" in id or "magnet" in id:
		EventBus.add_salvage_requested.emit(upgrade)
	elif "thruster" in id or "vectoring" in id:
		EventBus.add_thrusters_requested.emit(upgrade)
	else:
		# Default: try bulkhead signal as generic upgrade
		EventBus.add_bulkhead_requested.emit(upgrade)


func _apply_weapon(weapon: WeaponDef) -> void:
	RunState.record_weapon_purchase()
	EventBus.add_gun_requested.emit(weapon)


func _close_menu() -> void:
	visible = false
	get_tree().paused = false
	
	# Restore mouse mode
	Input.set_mouse_mode(_was_mouse_mode)
	
	# Destroy the POI after purchase
	if _current_poi != null and is_instance_valid(_current_poi):
		_current_poi.queue_free()
		_current_poi = null
	
	menu_closed.emit()


func _close_without_purchase() -> void:
	# Close menu without destroying the POI (player can return later)
	visible = false
	get_tree().paused = false
	
	# Restore mouse mode
	Input.set_mouse_mode(_was_mouse_mode)
	
	# Keep the POI alive - just clear reference
	_current_poi = null
	
	menu_closed.emit()


func _spend_nanobots(amount: int) -> void:
	if amount > 0:
		_current_nanobots -= amount
		RunState.nanobots_spent.emit(amount)


func _on_nanobots_updated(amount: int) -> void:
	_current_nanobots = amount
	if visible:
		_update_buttons()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _is_controller_event(event) and get_viewport().gui_get_focus_owner() == null:
		call_deferred("_focus_default_control")
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close_without_purchase()

func _focus_default_control() -> void:
	for btn: Button in _buttons:
		if btn.visible and not btn.disabled:
			btn.grab_focus()
			return
	for btn: Button in _buttons:
		if btn.visible:
			btn.grab_focus()
			return
	if btn_close != null and btn_close.visible:
		btn_close.grab_focus()

func _is_controller_event(event: InputEvent) -> bool:
	var joy_button: InputEventJoypadButton = event as InputEventJoypadButton
	if joy_button != null:
		return joy_button.pressed
	var joy_motion: InputEventJoypadMotion = event as InputEventJoypadMotion
	return joy_motion != null and absf(joy_motion.axis_value) >= 0.5

func get_last_offer_debug() -> Dictionary:
	return _last_offer_debug.duplicate(true)

func _append_offer_debug_choices() -> void:
	if _last_offer_debug.is_empty():
		return
	var family_weights: Dictionary = _last_offer_debug.get("family_weights", {})
	var offered_upgrades: Array[Dictionary] = []
	for upgrade: Upgrade in _upgrade_choices:
		if upgrade == null:
			continue
		var family: String = _get_upgrade_family(upgrade)
		var family_entry: Dictionary = family_weights.get(family, {})
		offered_upgrades.append({
			"id": upgrade.id,
			"family": family,
			"tier": _get_upgrade_tier(upgrade),
			"final_family_multiplier": float(family_entry.get("final_multiplier", 1.0)),
		})
	_last_offer_debug["offered_upgrades"] = offered_upgrades

func _compute_offer_memory_intensity(wave_index: int) -> float:
	if offer_memory_def == null:
		return 0.0
	var wave_progress: float = float(max(wave_index - offer_memory_def.start_wave, 0))
	var intensity: float = (
		wave_progress * offer_memory_def.per_wave_linear +
		wave_progress * wave_progress * offer_memory_def.per_wave_quadratic
	)
	if offer_memory_def.intensity_cap > 0.0:
		intensity = min(intensity, offer_memory_def.intensity_cap)
	return max(intensity, 0.0)

func _get_poi_type(poi: PoiInstance) -> int:
	if poi == null or poi.poi_def == null:
		return PoiDef.PoiType.OFFENSE
	return int(poi.poi_def.poi_type)

func _get_poi_type_label(poi_type: int) -> String:
	match poi_type:
		PoiDef.PoiType.DEFENSE:
			return "DEFENSE"
		PoiDef.PoiType.UTILITY:
			return "UTILITY"
	return "OFFENSE"
