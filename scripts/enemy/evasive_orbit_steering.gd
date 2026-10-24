extends RefCounted
class_name EvasiveOrbitSteering

## Lightweight fighter steering: a moving three-dimensional orbit, not a hold.
## The changing axis is local to one actor; no neighbor scans or target prediction.
var _phase: float = 0.0

func reset(actor_id: int) -> void:
	_phase = fposmod(float(actor_id % 997) * 0.61803398875, TAU)

func desired_velocity(delta: float, to_target: Vector3, target_velocity: Vector3, inner_range: float, outer_range: float, max_speed: float, orbit_strength: float, orbit_direction: float, jink_interval_sec: float, jink_strength: float) -> Vector3:
	_phase = fposmod(_phase + maxf(delta, 0.0) * TAU / maxf(jink_interval_sec, 0.25), TAU)
	var speed: float = maxf(max_speed, 1.0)
	var distance: float = to_target.length()
	var radial: Vector3 = to_target / distance if distance > 0.001 else Vector3.FORWARD
	var tilt: float = clampf(jink_strength, 0.0, 1.0)
	var axis: Vector3 = Vector3(sin(_phase) * tilt, 1.0, cos(_phase * 2.0) * tilt).normalized()
	var tangent: Vector3 = radial.cross(axis)
	if tangent.length_squared() < 0.001:
		tangent = radial.cross(Vector3.RIGHT if absf(radial.x) < 0.9 else Vector3.FORWARD)
	tangent = tangent.normalized() * orbit_direction
	var inner: float = maxf(inner_range, 1.0)
	var outer: float = maxf(outer_range, inner + 1.0)
	var preferred: float = (inner + outer) * 0.5
	var radial_fraction: float = clampf((distance - preferred) / maxf(outer - inner, 30.0), -1.0, 1.0)
	# Distant fighters close directly; nearby fighters retain speed while strafing.
	var closing_fraction: float = clampf((distance - outer) / maxf(outer, 1.0), 0.0, 1.0)
	var lateral_speed: float = speed * clampf(orbit_strength, 0.0, 1.0) * lerpf(1.0, 0.2, closing_fraction)
	var result: Vector3 = radial * radial_fraction * speed + tangent * lateral_speed
	# Follow a moving combat center without replacing the lateral escape movement.
	result += target_velocity.limit_length(speed) * (1.0 - closing_fraction) * 0.5
	return result.limit_length(speed)
