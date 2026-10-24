extends RefCounted
class_name GreyAttackGeometry

## Prediction is sampled once per warning. No committed geometry follows a ship.
static func forecast(position: Vector3, velocity: Vector3, windup: float, lead_fraction: float, maximum_lead: float) -> Vector3:
	return position + (velocity * maxf(windup, 0.0) * clampf(lead_fraction, 0.0, 1.0)).limit_length(maxf(maximum_lead, 0.0))

## A crosswise closed cylinder leaves vertical and lateral escape open.
static func crossing_axis(velocity: Vector3, source_to_target: Vector3) -> Vector3:
	var heading: Vector3 = velocity.normalized() if velocity.length_squared() > 1.0 else source_to_target.normalized()
	if heading.length_squared() < 0.001:
		heading = Vector3.FORWARD
	var axis: Vector3 = heading.cross(Vector3.UP)
	if axis.length_squared() < 0.001:
		axis = heading.cross(Vector3.RIGHT)
	return axis.normalized()

static func target_velocity(target: Node3D) -> Vector3:
	var body: RigidBody3D = target as RigidBody3D
	return body.linear_velocity if body != null else Vector3.ZERO
