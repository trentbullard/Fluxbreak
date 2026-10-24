extends RefCounted
class_name GreyAttackPattern

enum Shape { FORECAST, CROSSING, ECHO_PAIR, CONVERGENCE, PHASE_CROSS }

const PULSE_TINT: Color = Color(0.66, 0.5, 1.0, 0.9)
const LANE_TINT: Color = Color(0.4, 0.8, 1.0, 0.9)

## All positions are captured together. Complementary warnings are independent
## immutable volumes, with a full warning for the final member of each pattern.
static func start(source: Enemy, target: Node3D, host: Object, label: String, shape: Shape, windup: float, radius: float, lead_fraction: float, maximum_lead: float, lane_half_length: float, lane_radius: float, echo_gap: float = 0.25) -> EnemyAttackTelegraph:
	if not is_instance_valid(source) or source._dead or source.is_queued_for_deletion() or not source.is_inside_tree() or not is_instance_valid(target) or not is_instance_valid(host):
		return null
	if source.get_tree().current_scene == null:
		return null
	var velocity: Vector3 = GreyAttackGeometry.target_velocity(target)
	var position: Vector3 = target.global_position
	var forecast: Vector3 = GreyAttackGeometry.forecast(position, velocity, windup, lead_fraction, maximum_lead)
	var axis: Vector3 = GreyAttackGeometry.crossing_axis(velocity, position - source.global_position)
	var primary: EnemyAttackTelegraph = null
	match shape:
		Shape.FORECAST:
			primary = _sphere(source, target, host, label, windup, radius, forecast)
		Shape.CROSSING:
			primary = _lane(source, target, host, label, windup, lane_radius, forecast, axis, lane_half_length)
		Shape.PHASE_CROSS:
			primary = _sphere(source, target, host, label + " / RUPTURE", windup, radius, position)
			var crossing_center: Vector3 = GreyAttackGeometry.forecast(position, velocity, windup + echo_gap, lead_fraction, maximum_lead)
			var crossing: EnemyAttackTelegraph = _lane(source, target, host, label + " / CROSSING", windup + echo_gap, lane_radius, crossing_center, axis, lane_half_length)
			primary.add_companion(crossing)
		_:
			primary = _sphere(source, target, host, label + " / ECHO", windup, radius, position)
			forecast = GreyAttackGeometry.forecast(position, velocity, windup + echo_gap, lead_fraction, maximum_lead)
			# A stationary ship still sees separated geometry and an escape gap.
			if forecast.distance_squared_to(position) < radius * radius * 0.25:
				forecast = position + axis * radius * 1.55
			var echo: EnemyAttackTelegraph = _sphere(source, target, host, label + " / FORECAST", windup + echo_gap, radius * 0.85, forecast)
			primary.add_companion(echo)
			if shape == Shape.CONVERGENCE:
				var lane_center: Vector3 = GreyAttackGeometry.forecast(position, velocity, windup + echo_gap * 2.0, lead_fraction, maximum_lead)
				var lane: EnemyAttackTelegraph = _lane(source, target, host, label + " / PHASE LANE", windup + echo_gap * 2.0, lane_radius, lane_center, axis, lane_half_length)
				primary.add_companion(lane)
	return primary

static func _sphere(source: Enemy, target: Node3D, host: Object, label: String, windup: float, radius: float, position: Vector3) -> EnemyAttackTelegraph:
	var warning: EnemyAttackTelegraph = EnemyAttackTelegraph.new()
	warning.set_warning_style(label, PULSE_TINT)
	warning.set_response_hint("CHANGE COURSE / LEAVE THE ECHO")
	source.get_tree().current_scene.add_child(warning)
	warning.start_attack(source, target, host, windup, radius, false, position)
	return warning

static func _lane(source: Enemy, target: Node3D, host: Object, label: String, windup: float, radius: float, center: Vector3, axis: Vector3, half_length: float) -> EnemyAttackTelegraph:
	var warning: EnemyAttackTelegraph = EnemyAttackTelegraph.new()
	warning.set_warning_style(label, LANE_TINT)
	warning.set_response_hint("TURN / CLIMB OUT OF THE LANE")
	source.get_tree().current_scene.add_child(warning)
	warning.start_attack(source, target, host, windup, radius, true, center + axis * half_length, center - axis * half_length)
	return warning
