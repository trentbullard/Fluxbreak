extends RefCounted
class_name CombatStatContext

var pilot_id: StringName = &""
var ship_id: StringName = &""
var weapon_direct_id: StringName = &""
var equipped_weapon_ids: Array[StringName] = []
var enemy_id: StringName = &""
var faction_id: StringName = &""
var role_id: StringName = &""

func duplicate_context() -> CombatStatContext:
	var copy: CombatStatContext = CombatStatContext.new()
	copy.pilot_id = pilot_id
	copy.ship_id = ship_id
	copy.weapon_direct_id = weapon_direct_id
	copy.equipped_weapon_ids = get_normalized_equipped_weapon_ids()
	copy.enemy_id = enemy_id
	copy.faction_id = faction_id
	copy.role_id = role_id
	return copy

func add_equipped_weapon_id(weapon_id: StringName) -> void:
	if weapon_id == &"":
		return
	for existing_id in equipped_weapon_ids:
		if existing_id == weapon_id:
			return
	equipped_weapon_ids.append(weapon_id)

func get_normalized_equipped_weapon_ids() -> Array[StringName]:
	var unique_ids: Array[StringName] = []
	for weapon_id in equipped_weapon_ids:
		if weapon_id == &"":
			continue
		var already_present: bool = false
		for existing_id in unique_ids:
			if existing_id == weapon_id:
				already_present = true
				break
		if not already_present:
			unique_ids.append(weapon_id)
	return unique_ids

func set_enemy_identity_from_source(source: Object) -> void:
	if source == null or not is_instance_valid(source):
		return
	enemy_id = _read_string_name(source, "get_enemy_id", "enemy_id")
	faction_id = _read_string_name(source, "get_faction_id", "faction_id")
	role_id = _read_string_name(source, "get_role_id", "role_id")

func _read_string_name(source: Object, method_name: String, property_name: String) -> StringName:
	if source == null:
		return &""
	if source.has_method(method_name):
		return StringName(String(source.call(method_name)))
	for property_info_variant in source.get_property_list():
		var property_info: Dictionary = property_info_variant as Dictionary
		if String(property_info.get("name", "")) != property_name:
			continue
		var raw_value: Variant = source.get(property_name)
		return StringName(String(raw_value))
	return &""
