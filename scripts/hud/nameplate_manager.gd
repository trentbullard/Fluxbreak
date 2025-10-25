# nameplate_manager.gd  (Godot 4.5)
extends Control
class_name NameplateManager

@export var nameplate_scene: PackedScene
@export var show_within_meters := 1000
@export var pixel_offset_up := 35

var _camera: Camera3D
var _ship: Node3D
var _pool: Array[Control] = []
var _map: Dictionary[Node3D, Control] = {}

func init(cam: Camera3D, ship: Node3D) -> void:
	_camera = cam
	_ship = ship

func _process(_dt: float) -> void:
	if _camera == null or nameplate_scene == null:
		return
	_sync_targets()

func _sync_targets() -> void:
	var targets: Array = get_tree().get_nodes_in_group("targets")
	
	for t in targets:
		var target: Node3D = t
		if target == null:
			continue
		if not _map.has(target):
			var ui: Control = _pool_take()
			if ui.get_parent() != self:
				if ui.get_parent() != null:
					ui.get_parent().remove_child(ui)
				add_child(ui)
			_map[target] = ui
			
			var tracked: Node3D = target
			target.tree_exited.connect(func() -> void:
				if _map.has(tracked):
					_pool_release(_map[tracked])
					_map.erase(tracked)
			)

	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	for target in _map.keys():
		var ui: Control = _map[target]
		var pos3: Vector3 = target.global_position

		var ship_pos: Vector3 = _ship.global_transform.origin if (_ship != null) else _camera.global_position
		var d: float = pos3.distance_to(ship_pos)
		var visible_now: bool = (d <= float(show_within_meters)) and _camera.is_position_in_frustum(pos3)

		if visible_now:
			var sp: Vector2 = _camera.unproject_position(pos3)
			ui.visible = true

			var label := ui.get_node("HBox/Label") as Label
			if label != null:
				var kind: String = _kind_of(target)
				if kind == "enemy":
					label.text = "%s (%s)\n%dm  •  HP: %d" % [
						target.display_name,
						target.faction,
						int(round(d)),
						int(round(max(target.hull, 0.0)))
					]
				elif kind == "target":
					label.text = "%s\n%dm  •  HP: %d" % [
						target.display_name,
						int(round(d)),
						int(round(max(target.hull, 0.0)))
					]

			_place_center_bottom(ui, sp, vp_size)
		else:
			_pool_release(ui)
			_map.erase(target)

func _pool_take() -> Control:
	if _pool.is_empty():
		return nameplate_scene.instantiate() as Control
	return _pool.pop_back()

func _pool_release(ui: Control) -> void:
	ui.visible = false
	if ui.get_parent() != null:
		ui.get_parent().remove_child(ui)
	_pool.push_back(ui)

func _place_center_bottom(ui: Control, screen_pos: Vector2, vp_size: Vector2) -> void:
	ui.size = ui.get_combined_minimum_size()
	var s: Vector2 = ui.size
	var pos: Vector2 = screen_pos - Vector2(s.x * 0.5, s.y) - Vector2(0.0, float(pixel_offset_up))
	pos.x = clamp(pos.x, 0.0, vp_size.x - s.x)
	pos.y = clamp(pos.y, 0.0, vp_size.y - s.y)
	ui.position = pos

func _kind_of(node: Object) -> String:
	if not is_instance_valid(node):
		return "unknown"
	if node.has_meta("kind"):
		return String(node.get_meta("kind"))
	return "enemy" if node.is_class("Enemy") else "target"
