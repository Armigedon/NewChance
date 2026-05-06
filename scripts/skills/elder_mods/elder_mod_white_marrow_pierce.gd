extends ElderModifier
class_name ElderModWhiteMarrowPierce

# Pierce affects projectile travel (the projectile keeps going after hitting an
# enemy). Pipeline integration in Task 9 reads stack count off the active
# wand to set per-projectile pierce budget.
func _init() -> void:
	super._init("marrow_pierce", "white", "Marrow Pierce", "Casts pierce through 1 enemy. Stack: +1 pierce.")
	# No callable hooks; pipeline reads stack count directly.
