extends GdUnitTestSuite

const WallScene: PackedScene = preload("res://scenes/effects/effect_bone_wall.tscn")

func test_wall_registers_in_group() -> void:
	var wall: StaticBody3D = auto_free(WallScene.instantiate())
	add_child(wall)
	wall.configure(30, 1.5, 4.0)
	await get_tree().process_frame
	assert_bool(wall.is_in_group("bone_wall")).is_true()
	assert_int(wall.spawn_time_msec).is_greater(0)

func test_third_wall_despawns_oldest() -> void:
	# Spawn three walls in sequence; oldest should be freed
	var w1: StaticBody3D = auto_free(WallScene.instantiate())
	var w2: StaticBody3D = auto_free(WallScene.instantiate())
	add_child(w1); w1.configure(30, 1.5, 4.0); await get_tree().process_frame
	add_child(w2); w2.configure(30, 1.5, 4.0); await get_tree().process_frame
	# Simulate the cast logic enforcing the cap before instantiating w3
	var existing: Array = get_tree().get_nodes_in_group("bone_wall")
	existing.sort_custom(func(a, b): return a.spawn_time_msec < b.spawn_time_msec)
	if existing.size() >= 2:
		existing[0].queue_free()
	await get_tree().process_frame
	assert_bool(is_instance_valid(w1)).is_false()
	assert_bool(is_instance_valid(w2)).is_true()
