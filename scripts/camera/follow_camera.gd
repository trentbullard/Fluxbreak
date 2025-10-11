# follow_camera.gd  (Godot 4.5)
extends Camera3D

@export var target_path: NodePath
@export var local_offset := Vector3(0.0, 1.3, -6.0) # base offset from ship (back is -Z)
@export var pos_lag := 14.0                         # higher = snappier position follow
@export var rot_lag := 24.0                         # higher = snappier rotation follow
@export var inherit_roll := true                    # carry ship roll into camera

# --- Cinematic sauce ---
@export var bank_gain := 0.85       # how much we auto-bank from yaw rate (deg per (rad/s))
@export var bank_max_deg := 18.0    # cap auto-bank
@export var roll_smooth := 10.0     # how quickly the camera’s extra roll settles

@export var vel_drag := 0.6         # lateral offset response to ship velocity (m offsets)
@export var vel_drag_lag := 6.0     # how fast that lateral offset catches up

@export var look_ahead_enabled := true
@export var look_ahead_gain := Vector3(0.35, 0.25, 0.0) # X<-yaw, Y<-pitch, Z unused (in LOCAL space)
@export var look_ahead_max := 1.2                       # clamp magnitude (meters)
@export var look_ahead_lag := 10.0                      # smoothing toward target

# --- Zoom / cockpit ---
@export var min_distance := 0.2
@export var max_distance := 18.0
@export var zoom_speed := 2.0                       # units per wheel notch
@export var cockpit_threshold := 0.75               # when |offset.z| <= this, enter cockpit
@export var cockpit_socket_name := "CockpitSocket"  # optional Marker3D under ship

# --- Speed FOV (optional) ---
@export var fov_base := 75.0
@export var fov_speed_gain := 0.10  # degrees added per (m/s), small number
@export var fov_max := 92.0
@export var fov_lag := 8.0

var _target: Node3D
var _prev_ship_basis: Basis
var _have_prev := false

var _target_distance := 6.0
var _smoothed_roll := 0.0
var _vel_offset := Vector3.ZERO

var _look_offset := Vector3.ZERO

func _ready() -> void:
	if target_path != NodePath(""):
		_target = get_node_or_null(target_path)
	_target_distance = abs(local_offset.z)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_distance = clamp(_target_distance - zoom_speed, min_distance, max_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_distance = clamp(_target_distance + zoom_speed, min_distance, max_distance)

func _process(delta: float) -> void:
	if _target == null:
		return

	# --- Pick the ship/pivot transform ---
	var pivot: Node3D = _target.get_node_or_null("CameraPivot")
	var ship_t: Transform3D = (pivot.global_transform if pivot != null else _target.global_transform)
	var ship_basis := ship_t.basis

	# --- Compute angular velocity from basis delta (world-space) ---
	var extra_bank_deg := 0.0
	var ang_world := Vector3.ZERO # rad/s axis * magnitude, world-space

	if _have_prev:
		var q_prev := _prev_ship_basis.get_rotation_quaternion()
		var q_now := ship_basis.get_rotation_quaternion()
		var dq := q_prev.inverse() * q_now
		dq = dq.normalized()

		# angle about some axis (radians per frame)
		var axis := dq.get_axis()
		var angle := dq.get_angle() # radians (0..pi)
		# turn that into an angular velocity vector (world)
		var w := angle / max(delta, 1e-5) as float # rad/s
		ang_world = axis * w
		
		# we want yaw component; projected into ship LOCAL space:
		var ang_local := ship_basis.inverse() * ang_world
		var yaw_rate := ang_local.y # + = yaw left (depending on basis)
		extra_bank_deg = clamp(yaw_rate * bank_gain, -bank_max_deg, bank_max_deg)
		
		# ---- Look-ahead (local-space lateral/vertical nudge) ----
		if look_ahead_enabled:
			# Note: sign choices aim the camera *into* the turn
			var la_target := Vector3(
				-ang_local.y * look_ahead_gain.x, # yaw -> push to outside of turn (so you see into it)
				ang_local.x * look_ahead_gain.y, # pitch up/down -> slight vertical lead
				0.0
			)
			if la_target.length() > look_ahead_max:
				la_target = la_target.normalized() * look_ahead_max
			_look_offset = _look_offset.lerp(la_target, clamp(look_ahead_lag * delta, 0.0, 1.0))
	else:
		_look_offset = _look_offset.lerp(Vector3.ZERO, clamp(look_ahead_lag * delta, 0.0, 1.0))

	_prev_ship_basis = ship_basis
	_have_prev = true

	# --- Build desired camera basis (with optional roll override) ---
	var desired_basis := ship_basis
	if not inherit_roll:
		# keep ship forward, use global up (no roll)
		var fwd := -ship_basis.z
		desired_basis = Basis.looking_at(fwd, Vector3.UP)

	# Apply our extra cinematic bank around the forward axis
	if extra_bank_deg != 0.0:
		_smoothed_roll = lerp(_smoothed_roll, deg_to_rad(extra_bank_deg), clamp(roll_smooth * delta, 0.0, 1.0))
	else:
		_smoothed_roll = lerp(_smoothed_roll, 0.0, clamp(roll_smooth * delta, 0.0, 1.0))
	desired_basis = desired_basis.rotated(desired_basis.z, _smoothed_roll)

	# --- Desired camera offset (distance + slight velocity drag) ---
	var desired_dist := _target_distance
	var base_offset := local_offset
	base_offset.z = -desired_dist * sign(-1.0)  # keep it behind along -Z

	# Add a tiny lateral offset based on ship local velocity to sell inertia
	var ship_cb := _target as CharacterBody3D
	if ship_cb:
		var v_world := ship_cb.velocity
		var v_local := ship_basis.inverse() * v_world
		var target_vel_offset := Vector3(-v_local.x, -v_local.y, 0.0) * vel_drag  # push opposite drift
		_vel_offset = _vel_offset.lerp(target_vel_offset, clamp(vel_drag_lag * delta, 0.0, 1.0))
	else:
		_vel_offset = _vel_offset.lerp(Vector3.ZERO, clamp(vel_drag_lag * delta, 0.0, 1.0))

	var desired_pos := ship_t.origin + desired_basis * (base_offset + _vel_offset + _look_offset)

	# --- Position lag ---
	var p_alpha := clamp(pos_lag * delta, 0.0, 1.0) as float
	global_position = global_position.lerp(desired_pos, p_alpha)

	# --- Rotation lag (slerp) ---
	var q_from := global_transform.basis.get_rotation_quaternion()
	var q_to := desired_basis.get_rotation_quaternion()
	var r_alpha := clamp(rot_lag * delta, 0.0, 1.0) as float
	var q_final := q_from.slerp(q_to, r_alpha)
	global_transform.basis = Basis(q_final)

	# --- Cockpit mode if close enough ---
	if abs(desired_dist) <= cockpit_threshold:
		var cockpit: Node3D = _target.get_node_or_null(cockpit_socket_name)
		if cockpit:
			# Sit right on the cockpit socket, align exactly to ship/cockpit
			global_transform = cockpit.global_transform
		else:
			# Fallback: sit a little in front of the pivot
			var nose := ship_t.origin + ship_basis * Vector3(0, 0.2, 0.6)
			global_position = global_position.lerp(nose, p_alpha)
			global_transform.basis = Basis(q_final)

	# --- Speed FOV ---
	var spd := 0.0
	if ship_cb:
		spd = ship_cb.velocity.length()
	var target_fov := clamp(fov_base + spd * fov_speed_gain, fov_base, fov_max) as float
	fov = lerp(fov, target_fov, clamp(fov_lag * delta, 0.0, 1.0))
