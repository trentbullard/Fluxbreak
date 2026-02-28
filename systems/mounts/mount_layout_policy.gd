# systems/mounts/mount_layout_policy.gd (godot 4.5)
extends Resource
class_name MountLayoutPolicy

@export var anchors_by_count: Dictionary[int, PackedStringArray] = {} # key = installed weapon count

func get_anchor_names_for(count: int) -> PackedStringArray:
	var best: PackedStringArray = PackedStringArray()
	if count < 0:
		return best
	if anchors_by_count.has(count):
		return anchors_by_count[count]
	# Fallback: largest defined <= count
	var best_key: int = 0
	for k in anchors_by_count.keys():
		var ki: int = int(k)
		if ki <= count and ki > best_key:
			best_key = ki
	if best_key > 0:
		return anchors_by_count[best_key]
	return best
