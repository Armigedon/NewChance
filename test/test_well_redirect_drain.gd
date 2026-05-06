extends GdUnitTestSuite

const WellScene: PackedScene = preload("res://scenes/effects/effect_gravity_well.tscn")

func before_test() -> void:
	for n in get_tree().get_nodes_in_group("damage_cloud"):
		n.queue_free()
	await get_tree().process_frame

func test_well_consume_for_redirect_drains_lifetime() -> void:
	var well: Node3D = auto_free(WellScene.instantiate())
	add_child(well)
	await get_tree().process_frame
	well.configure(2.0, 2.0, 5, [], "purple")
	var initial_age: float = well._age
	well.consume_for_redirect()
	# Age should advance by REDIRECT_LIFETIME_DRAIN_S (0.5s).
	assert_float(well._age).is_equal_approx(initial_age + 0.5, 0.001)

func test_well_freed_when_remaining_drops_below_drain() -> void:
	var well: Node3D = auto_free(WellScene.instantiate())
	add_child(well)
	await get_tree().process_frame
	well.configure(2.0, 2.0, 5, [], "purple")
	# Manually advance age so only 0.4s remains; consume should free.
	well._age = 1.6
	well.consume_for_redirect()
	await get_tree().process_frame
	assert_bool(is_instance_valid(well)).is_false()
