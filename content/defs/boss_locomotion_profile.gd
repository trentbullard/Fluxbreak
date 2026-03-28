extends Resource
class_name BossLocomotionProfile

@export_group("Distance")
@export_range(0.0, 4000.0, 1.0) var preferred_distance: float = 850.0
@export_range(0.0, 2000.0, 1.0) var distance_tolerance: float = 180.0

@export_group("Motion")
@export_range(0.0, 4.0, 0.01) var radial_force_scale: float = 1.0
@export_range(0.0, 4.0, 0.01) var strafe_force_scale: float = 0.55
@export_range(0.0, 4.0, 0.01) var vertical_force_scale: float = 0.18
@export_range(0.1, 10.0, 0.01) var strafe_retarget_sec: float = 2.4
@export_range(0.1, 10.0, 0.01) var vertical_retarget_sec: float = 3.8
