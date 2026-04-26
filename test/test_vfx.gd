extends GdUnitTestSuite

const VfxScript = preload("res://scripts/effects/vfx.gd")

func test_color_albedo_dict_has_six_colors() -> void:
	# Validates the Vfx.COLOR_ALBEDO map exposes the expected color set.
	for c in ["red", "blue", "green", "purple", "gold", "white"]:
		assert_that(VfxScript.COLOR_ALBEDO.has(c)).is_true()

func test_spawn_death_burst_with_null_parent_does_not_crash() -> void:
	# Null/invalid parent should be a no-op, not a crash.
	VfxScript.spawn_death_burst(Vector3.ZERO, Color.WHITE, null)
	# If we got here, the call returned cleanly.
	assert_that(true).is_true()

func test_spawn_death_burst_instantiates_child_of_parent() -> void:
	var parent: Node3D = auto_free(Node3D.new())
	add_child(parent)
	VfxScript.spawn_death_burst(Vector3(1, 2, 3), Color(0.5, 0.5, 0.5), parent)
	# At least one GPUParticles3D child should have been added.
	var found: bool = false
	for child in parent.get_children():
		if child is GPUParticles3D:
			found = true
			break
	assert_that(found).is_true()
