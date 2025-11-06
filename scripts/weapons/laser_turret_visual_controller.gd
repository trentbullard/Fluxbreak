# scripts/weapons/laser_turret_visual_controller.gd (godot 4.5)
extends Node3D
class_name LaserTurretVisualController

@export var rest_strength: float = 0.25
@export var max_strength: float = 1.50
@export var exciter_path: NodePath = ^"Exciter"

var _rings: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
var _base_emission: Array[Color] = []

func _ready() -> void:
	_capture_rings()
	set_charge(0.0)

func _capture_rings() -> void:
	_rings.clear()
	_materials.clear()
	_base_emission.clear()
	
	var exciter: Node3D = get_node_or_null(exciter_path) as Node3D
	if exciter == null:
		return
	
	for c in exciter.get_children():
		var mi: MeshInstance3D = c as MeshInstance3D
		if mi == null:
			continue
		_rings.append(mi)
	
		var src: Material = null
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			src = mi.mesh.surface_get_material(0)
		if src == null:
			src = mi.material_override
		
		var dup: Material = null
		if src != null:
			dup = src.duplicate(true)
		else:
			dup = StandardMaterial3D.new()
		
		if dup is StandardMaterial3D:
			var std: StandardMaterial3D = dup as StandardMaterial3D
			std.emission_enabled = true
			if std.emission == Color(0, 0, 0, 1):
				std.emission = Color(1, 1, 1, 1)
			_materials.append(std)
			_base_emission.append(std.emission)
			mi.material_override = std
		else:
			var std2: StandardMaterial3D = StandardMaterial3D.new()
			std2.emission_enabled = true
			std2.emission = Color(1, 1, 1, 1)
			_materials.append(std2)
			_base_emission.append(std2.emission)
			mi.material_override = std2

func set_charge(t: float) -> void:
	var s: float = lerp(rest_strength, max_strength, clamp(t, 0.0, 1.0))
	for i in range(_materials.size()):
		var std: StandardMaterial3D = _materials[i]
		var base_col: Color = _base_emission[i]
		std.emission_enabled = true
		std.emission = base_col * s

func reset_after_shot() -> void:
	set_charge(0.0)
