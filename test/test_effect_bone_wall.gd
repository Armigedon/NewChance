extends GdUnitTestSuite

const WallScene: PackedScene = preload("res://scenes/effects/effect_bone_wall.tscn")

func test_wall_starts_with_configured_hp() -> void:
	var wall: StaticBody3D = auto_free(WallScene.instantiate())
	add_child(wall)
	wall.configure(120, 4.0, 4.0)
	assert_that(wall.hp).is_equal(120)

func test_wall_breaks_at_zero_hp() -> void:
	var wall: StaticBody3D = WallScene.instantiate()
	add_child(wall)
	wall.configure(50, 4.0, 4.0)
	# Array used as a mutable reference container — GDScript lambdas capture
	# locals by value, so a bare `var broken: bool` won't be updated by the
	# closure. Arrays are reference types, so element mutation persists.
	var broken: Array[bool] = [false]
	wall.wall_broken.connect(func(): broken[0] = true)
	wall.take_damage(50)
	assert_that(broken[0]).is_true()

func test_wall_despawns_after_lifetime() -> void:
	var wall: StaticBody3D = auto_free(WallScene.instantiate())
	add_child(wall)
	wall.configure(100, 0.1, 4.0)
	for i in range(20):
		if not is_instance_valid(wall):
			break
		wall._process(1.0 / 60.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_that(is_instance_valid(wall)).is_false()
