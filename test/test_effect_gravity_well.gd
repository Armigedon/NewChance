extends GdUnitTestSuite

const WellScene: PackedScene = preload("res://scenes/effects/effect_gravity_well.tscn")
const WelpScene: PackedScene = preload("res://scenes/entities/welp.tscn")

func test_well_pulls_enemies_in_radius() -> void:
	var well: Node3D = auto_free(WellScene.instantiate())
	var welp: CharacterBody3D = auto_free(WelpScene.instantiate())
	add_child(well)
	add_child(welp)
	well.global_position = Vector3.ZERO
	welp.global_position = Vector3(1.5, 0, 0)
	well.configure(2.0, 2.0, 5, [], "purple")
	await get_tree().process_frame
	await get_tree().process_frame
	var prev_kb: Vector3 = welp._knockback_velocity
	well._physics_process(1.0 / 60.0)
	# Pulled toward (0,0,0) from (1.5, 0, 0): -X direction
	assert_that(welp._knockback_velocity.x).is_less(prev_kb.x)

func test_well_ticks_damage() -> void:
	var well: Node3D = auto_free(WellScene.instantiate())
	var welp: CharacterBody3D = auto_free(WelpScene.instantiate())
	add_child(well)
	add_child(welp)
	well.global_position = Vector3.ZERO
	welp.global_position = Vector3(1.0, 0, 0)
	well.configure(2.0, 2.0, 6, [], "purple")
	await get_tree().process_frame
	await get_tree().process_frame
	var initial_hp: int = welp.hp
	well._tick_enemies()
	assert_that(welp.hp).is_less(initial_hp)

func test_well_despawns_after_lifetime() -> void:
	var well: Node3D = auto_free(WellScene.instantiate())
	add_child(well)
	well.configure(0.1, 2.0, 5, [], "purple")
	for i in range(20):
		if not is_instance_valid(well):
			break
		well._process(1.0 / 60.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_that(is_instance_valid(well)).is_false()
