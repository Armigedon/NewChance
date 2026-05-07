extends GdUnitTestSuite

const EffectCloudScene: PackedScene = preload("res://scenes/effects/effect_cloud.tscn")
const WelpScene: PackedScene = preload("res://scenes/entities/welp.tscn")

func before_test() -> void:
	# Other suites can leave stale enemies/clouds in the tree at origin (e.g.
	# test_drop_policy spawns welps at Vector3.ZERO). This contaminates
	# get_overlapping_bodies() readings inside cloud._tick_enemies. Sweep
	# the groups before each test so the cloud only sees what we add here.
	for n in get_tree().get_nodes_in_group("damage_cloud"):
		n.queue_free()
	for n in get_tree().get_nodes_in_group("enemy"):
		n.queue_free()
	await get_tree().process_frame

func test_cloud_ticks_damage_to_enemies_in_radius() -> void:
	var cloud: Node3D = auto_free(EffectCloudScene.instantiate())
	var welp: CharacterBody3D = auto_free(WelpScene.instantiate())
	# Set positions before add_child so the welp's first physics step happens
	# at the test position (avoids the (0,0,0) → moved-after race).
	cloud.position = Vector3.ZERO
	welp.position = Vector3(1.0, 0, 0)  # within 2m
	add_child(cloud)
	add_child(welp)
	cloud.configure(3.0, 2.0, 5, [], "green")
	await get_tree().physics_frame
	await get_tree().physics_frame
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
	# Set positions before add_child so the welp's first physics step doesn't
	# register an overlap at (0,0,0) that persists into the test.
	cloud.position = Vector3.ZERO
	welp.position = Vector3(5.0, 0, 0)  # outside 2m
	add_child(cloud)
	add_child(welp)
	cloud.configure(3.0, 2.0, 5, [], "green")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var initial_hp: int = welp.hp
	cloud._tick_enemies()
	assert_that(welp.hp).is_equal(initial_hp)
