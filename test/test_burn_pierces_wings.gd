extends GdUnitTestSuite

const ArmorWingsScript = preload("res://scripts/entities/boss_mechanics/mechanic_armor_wings.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")

var boss: CharacterBody3D
var wings: Node

func before_test() -> void:
	for z in get_tree().get_nodes_in_group("mark_zone"):
		z.queue_free()
	for w in get_tree().get_nodes_in_group("bone_wall"):
		w.queue_free()
	await get_tree().process_frame
	boss = auto_free(BossScene.instantiate())
	add_child(boss)
	await get_tree().process_frame
	for m in boss._mechanics.duplicate():
		m.queue_free()
	boss._mechanics.clear()
	wings = ArmorWingsScript.new()
	boss._register_mechanic(wings)
	wings._cooldown_remaining = 99.0
	await get_tree().process_frame

func test_burn_damage_ignores_wing_reduction() -> void:
	wings.trigger(2)
	for i in range(40):  # past windup, ~60% reduction active
		await get_tree().physics_frame
	var hp_before: int = boss.hp
	boss.take_damage_with_source(10, "burn")
	# Burn bypasses reduction. Cap is 15 per 0.5s, well above 10. Expect 10 actual.
	assert_int(hp_before - boss.hp).is_equal(10)

func test_non_burn_damage_still_reduced() -> void:
	wings.trigger(2)
	for i in range(40):
		await get_tree().physics_frame
	var hp_before: int = boss.hp
	boss.take_damage_with_source(10, "fireball")
	# Reduction ~0.6 applied: 10 * 0.4 = 4 actual (subject to cap, well under 15).
	# Allow ±1 tolerance for decay timing slack.
	var dmg: int = hp_before - boss.hp
	assert_int(dmg).is_between(3, 5)
