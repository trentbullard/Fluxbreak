# visual_bank.gd  (Godot 4.5)
extends Node3D

@export var ship: Ship
@export var max_bank_deg: float = 25.0        # how much to roll into a yaw
@export var bank_from_yaw_gain: float = 0.75  # scales yaw-rate → roll
@export var max_pitch_vis_deg: float = 15.0    # subtle nose-up/down visual
@export var pitch_from_pitch_gain: float = 0.6
@export var smooth: float = 10.0              # lerp speed

var _vis_target: Vector3 = Vector3.ZERO   # (pitch,x; yaw,y unused; roll,z)
var _vis_now: Vector3 = Vector3.ZERO

func _physics_process(delta: float) -> void:
	if ship == null:
		return

	# global ω → ship-local ω (Godot: X=pitch, Y=yaw, Z=roll)
	var w_local: Vector3 = ship.transform.basis.inverse() * ship.angular_velocity

	# roll into yaw (bank), nose follow pitch (visual only)
	var roll: float = clamp(-w_local.y * bank_from_yaw_gain, -1.0, 1.0) * deg_to_rad(max_bank_deg)
	var pitch: float = clamp(w_local.x * pitch_from_pitch_gain, -1.0, 1.0) * deg_to_rad(max_pitch_vis_deg)
	_vis_target = Vector3(pitch, 0.0, roll)

	# smooth it
	_vis_now = _vis_now.lerp(_vis_target, smooth * delta)

	# apply as an extra LOCAL rotation on top of the ship
	var b: Basis = Basis()
	b = b.rotated(Vector3.RIGHT,   _vis_now.x)  # pitch
	# (we leave yaw empty here)
	b = b.rotated(Vector3.FORWARD, _vis_now.z)  # roll
	transform.basis = b
