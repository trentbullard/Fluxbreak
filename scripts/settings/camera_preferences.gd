class_name CameraPreferences
extends RefCounted

const SETTINGS_PATH: String = "user://camera_settings.cfg"
const SCHEMA_VERSION: int = 2
const DEFAULTS: Dictionary = {
	&"fov": 75.0,
	&"distance_scale": 1.0,
	&"height_scale": 1.0,
	&"tightness": 1.0 / 6.0,
	&"look_ahead": 1.0,
	&"acceleration_pullback": 0.2,
}
const LIMITS: Dictionary = {
	&"fov": Vector2(60.0, 110.0),
	&"distance_scale": Vector2(0.75, 1.75),
	&"height_scale": Vector2(0.5, 2.0),
	&"tightness": Vector2(0.0, 1.0),
	&"look_ahead": Vector2(0.0, 1.0),
	&"acceleration_pullback": Vector2(0.0, 0.2),
}

static var _settings: Dictionary = {}
static var _loaded: bool = false
static var _dirty: bool = false

static func get_settings() -> Dictionary:
	_ensure_loaded()
	return _settings.duplicate()

static func set_setting(key: StringName, value: Variant, persist: bool = true) -> void:
	_ensure_loaded()
	if not DEFAULTS.has(key) or not _is_valid_number(value):
		return
	var bounds: Vector2 = LIMITS[key]
	var sanitized: float = clampf(float(value), bounds.x, bounds.y)
	if is_equal_approx(float(_settings[key]), sanitized):
		return
	_settings[key] = sanitized
	_dirty = true
	EventBus.camera_preferences_changed.emit(get_settings())
	if persist:
		save_settings()

static func save_settings() -> Error:
	_ensure_loaded()
	if not _dirty:
		return OK
	var config: ConfigFile = ConfigFile.new()
	config.set_value("camera", "version", SCHEMA_VERSION)
	for key: StringName in DEFAULTS:
		config.set_value("camera", String(key), _settings[key])
	var error: Error = config.save(SETTINGS_PATH)
	if error == OK:
		_dirty = false
	return error

static func reset_defaults() -> void:
	_settings = DEFAULTS.duplicate()
	_loaded = true
	_dirty = true
	EventBus.camera_preferences_changed.emit(get_settings())
	save_settings()

static func reload() -> void:
	_loaded = false
	_ensure_loaded()
	EventBus.camera_preferences_changed.emit(get_settings())

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_dirty = false
	_settings = DEFAULTS.duplicate()
	var config: ConfigFile = ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	# Read only the six numeric preferences; older experimental mode keys are ignored.
	for key: StringName in DEFAULTS:
		var value: Variant = config.get_value("camera", String(key), DEFAULTS[key])
		if not _is_valid_number(value):
			continue
		var bounds: Vector2 = LIMITS[key]
		_settings[key] = clampf(float(value), bounds.x, bounds.y)

static func _is_valid_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))
