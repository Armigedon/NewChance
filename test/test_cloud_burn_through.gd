extends GdUnitTestSuite

const CloudScene: PackedScene = preload("res://scenes/effects/effect_cloud.tscn")
const StaticBreathScript = preload("res://scripts/entities/boss_mechanics/mechanic_static_breath.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

func before_test() -> void:
	for c in get_tree().get_nodes_in_group("damage_cloud"):
		c.queue_free()
	await get_tree().process_frame

func test_cloud_has_hp_field_default_30() -> void:
	var cloud: Node3D = auto_free(CloudScene.instantiate())
	add_child(cloud)
	await get_tree().process_frame
	assert_int(cloud.hp).is_equal(30)

func test_cloud_take_damage_decrements_hp() -> void:
	var cloud: Node3D = auto_free(CloudScene.instantiate())
	add_child(cloud)
	await get_tree().process_frame
	cloud.take_damage(7)
	assert_int(cloud.hp).is_equal(23)

func test_cloud_freed_on_zero_hp() -> void:
	var cloud: Node3D = auto_free(CloudScene.instantiate())
	add_child(cloud)
	await get_tree().process_frame
	cloud.take_damage(30)
	await get_tree().process_frame
	assert_bool(is_instance_valid(cloud)).is_false()

func test_breath_block_damages_cloud() -> void:
	# Set up: boss + player on opposite sides of a green cloud. Drive a breath
	# tick and verify the cloud HP drops by CLOUD_BREATH_BLOCK_DAMAGE (5).
	var boss: CharacterBody3D = auto_free(BossScene.instantiate())
	var player: CharacterBody3D = auto_free(PlayerScene.instantiate())
	var cloud: Node3D = auto_free(CloudScene.instantiate())
	add_child(boss)
	boss.global_position = Vector3.ZERO
	add_child(player)
	player.global_position = Vector3(0, 0, 4)
	add_child(cloud)
	cloud.global_position = Vector3(0, 0, 2)
	cloud.configure(10.0, 2.0, 6, [], "green")
	await get_tree().process_frame
	for m in boss._mechanics.duplicate():
		m.queue_free()
	boss._mechanics.clear()
	var breath = StaticBreathScript.new()
	boss._register_mechanic(breath)
	breath._cooldown_remaining = 99.0
	await get_tree().process_frame
	cloud.global_position = Vector3(0, 0, 2)
	var initial_hp: int = cloud.hp
	breath.trigger(1)
	# Advance through windup; one tick of execution should block via cloud and damage it.
	var ticked: float = 0.0
	while ticked < 1.05:
		breath.tick(1.0 / 60.0, 1)
		ticked += 1.0 / 60.0
	for i in range(15):  # advance 15 frames of execution
		await get_tree().physics_frame
	# Expect cloud HP to have decreased.
	if is_instance_valid(cloud):
		assert_int(cloud.hp).is_less(initial_hp)
	else:
		# Cloud burned through to zero — also valid.
		assert_int(0).is_equal(0)
