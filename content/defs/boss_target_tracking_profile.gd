extends Resource
class_name BossTargetTrackingProfile

@export_group("Tracking")
@export_range(0.1, 20.0, 0.01) var turn_lerp_rate: float = 4.0
@export_range(-500.0, 500.0, 1.0) var aim_vertical_offset: float = 0.0
