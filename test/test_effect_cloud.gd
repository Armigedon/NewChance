extends GdUnitTestSuite

const EffectCloudScene: PackedScene = preload("res://scenes/effects/effect_cloud.tscn")
const WelpScene: PackedScene = preload("res://scenes/entities/welp.tscn")

func test_cloud_ticks_damage_to_enemies_in_radius() -> void:
	var cloud: Node3D = auto_free(EffectCloudScene.instantiate())
	var welp: CharacterBody3D = auto_free(WelpScene.instantiate())
	add_child(cloud)
	add_child(welp)
	cloud.global_position = Vector3.ZERO
	welp.global_position = Vector3(1.0, 0, 0)  # within 2m
	cloud.configure(3.0, 2.0, 5, [], "green")
	await get_tree().process_frame
	await get_tree().process_frame  # let physics report overlaps
	var initial_hp: int = welp.hp
	cloud._tick_enemies()
	assert_that(welp.hp).is_less(initial_hp)

func test_cloud_despawns_after_lifetime() -> void:
	var cloud: Node3D = EffectCloudScene.instantiate()
	add_child(cloud)
	cloud.configure(0.1, 2.0, 5, [], "green")
	# Drive enough simulated time to exceed lifetime so queue_free is called.
	for i in range(20):
		cloud._process(1.0 / 60.0)
	# queue_free is deferred — let the tree actually delete the node.
	await get_tree().process_frame
	await get_tree().process_frame
	assert_that(is_instance_valid(cloud)).is_false()

func test_cloud_does_not_tick_outside_radius() -> void:
	var cloud: Node3D = auto_free(EffectCloudScene.instantiate())
	var welp: CharacterBody3D = auto_free(WelpScene.instantiate())
	add_child(cloud)
	add_child(welp)
	cloud.global_position = Vector3.ZERO
	welp.global_position = Vector3(5.0, 0, 0)  # outside 2m
	cloud.configure(3.0, 2.0, 5, [], "green")
	await get_tree().process_frame
	await get_tree().process_frame
	var initial_hp: int = welp.hp
	cloud._tick_enemies()
	assert_that(welp.hp).is_equal(initial_hp)
