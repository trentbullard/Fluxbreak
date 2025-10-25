# scripts/target_object/target_object.gd  (Godot 4.5)
extends RigidBody3D
class_name TargetObject

@export var player_ship: Ship
@export var explosion_scene: PackedScene

# Prefab/test defaults (used if no def injected)
@export var max_hull: float = 20.0
@export var max_shield: float = 0.0
@export var shield_regen: float = 0.0
@export var score_on_kill: int = 5
@export var lifetime: float = 0.0

# Optional: editor preview convenience
@export var editor_preview_def: TargetDef

# Runtime identity
var def: TargetDef = null
var target_id: String = ""
var display_name: String = ""
var size_band: int = 1
var threat_cost: int = 1
var bounty_scrap: int = 1
var hazard_tag: String = ""

# internals
var _dead: bool = false
var _last_xform: Transform3D = Transform3D()
var hull: float = 20.0
var shield: float = 0.0
var persist: bool = true

func configure_target(d: TargetDef) -> void:
	if d == null:
		return
	def = d
	
	# Identity
	target_id = d.id
	display_name = d.display_name
	size_band = d.size_band
	threat_cost = d.threat_cost
	bounty_scrap = d.bounty_scrap
	hazard_tag = d.hazard_tag
	
	# Handy hooks
	set_meta("kind", "target")
	set_meta("hazard", hazard_tag)
	if hazard_tag != "":
		add_to_group("hazard_" + hazard_tag)
	add_to_group("targets")  # keep your existing targeting flow
	
	# Stats
	max_hull = d.max_hull
	max_shield = d.max_shield
	shield_regen = d.shield_regen
	score_on_kill = d.score_on_kill
	lifetime = d.lifetime
	if lifetime > 0.0: persist = false
	
	# Visuals
	var visual_root: Node3D = $VisualRoot
	if d.model_scene != null:
		# Replace the visual node (keeps physics/collider siblings intact)
		if visual_root != null:
			visual_root.queue_free()
		var new_vis := d.model_scene.instantiate() as Node3D
		new_vis.name = "VisualRoot"
		add_child(new_vis)
		visual_root = new_vis

	_apply_material_and_emission(visual_root, d)

func set_ship(ship: Ship):
	player_ship = ship

func apply_damage(amount: float) -> void:
	if _dead: return
	hull -= amount
	if hull <= 0.0:
		_die()

func _ready() -> void:
	add_to_group("targets")
	_last_xform = global_transform
	hull = max_hull
	shield = max_shield

func _process(delta: float) -> void:
	if is_inside_tree():
		_last_xform = global_transform
	if not persist:
		lifetime -= delta
		if lifetime < 0.0:
			hide()
			queue_free()

func _die() -> void:
	if _dead: return
	_dead = true
	RunState.add_score(score_on_kill, "target")
	
	if has_node("CollisionShape3D"):
		$CollisionShape3D.disabled = true
	
	var xf: Transform3D = global_transform if is_inside_tree() else _last_xform

	if explosion_scene != null:
		var fx: CPUParticles3D = explosion_scene.instantiate() as CPUParticles3D
		fx.global_transform = xf
		(get_parent() if get_parent() != null else get_tree().root).add_child(fx)

	hide()
	queue_free()

func _is_offscreen(cam: Camera3D, world_pos: Vector3) -> bool:
	# Behind camera?
	if cam.is_position_behind(world_pos):
		return true

	# Outside viewport rect?
	var screen_pos: Vector2 = cam.unproject_position(world_pos)
	var rect: Rect2i = get_viewport().get_visible_rect()
	return not rect.has_point(screen_pos)

func _apply_material_and_emission(root: Node, d: TargetDef) -> void:
	if root == null or d == null:
		return
	if d.material != null:
		for mi in root.get_children(true):
			if mi is MeshInstance3D:
				(mi as MeshInstance3D).material_override = d.material
		return
	for mi in root.get_children(true):
		if mi is MeshInstance3D:
			var mesh_inst := mi as MeshInstance3D
			var surf_count: int = mesh_inst.get_surface_override_material_count()
			if surf_count == 0 and mesh_inst.mesh != null:
				surf_count = mesh_inst.mesh.get_surface_count()
			for si in surf_count:
				var mat: Material = mesh_inst.get_active_material(si)
				if mat is StandardMaterial3D:
					var std := (mat as StandardMaterial3D).duplicate(true) as StandardMaterial3D
					std.emission_enabled = true
					std.emission = d.emission_color
					std.emission_energy_multiplier = d.emission_energy
					mesh_inst.set_surface_override_material(si, std)

func _enter_tree() -> void:
	# Editor preview: hydrate from preview def if present
	if Engine.is_editor_hint() and def == null and editor_preview_def != null:
		configure_target(editor_preview_def)
