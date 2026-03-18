extends RefCounted
class_name HudDistanceFormatter

const KILOMETER_THRESHOLD_METERS: float = 3000.0
const METERS_PER_KILOMETER: float = 1000.0


static func format_distance(distance: float) -> String:
	var clamped_distance: float = max(distance, 0.0)
	if clamped_distance <= KILOMETER_THRESHOLD_METERS:
		return "%dm" % int(round(clamped_distance))
	return "%.1fkm" % (clamped_distance / METERS_PER_KILOMETER)
