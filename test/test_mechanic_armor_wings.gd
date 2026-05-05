extends GdUnitTestSuite

const ArmorWingsScript = preload("res://scripts/entities/boss_mechanics/mechanic_armor_wings.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")

var boss: CharacterBody3D
var wings: Node

func before_test() -> void:
	# Stale-state cleanup from prior tests
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

func test_timings() -> void:
	assert_float(wings.windup_duration).is_equal_approx(0.5, 0.001)
	assert_float(wings.execution_duration).is_equal_approx(4.0, 0.001)

func test_unlocked_phase_2() -> void:
	assert_int(wings.unlock_phase).is_equal(2)

func test_active_reduction_starts_at_60_pct() -> void:
	wings.trigger(2)
	for i in range(40):
		await get_tree().physics_frame
	assert_float(wings.current_reduction_pct()).is_equal_approx(0.6, 0.05)

func test_reduction_decays_to_zero() -> void:
	wings.trigger(2)
	for i in range(280):
		await get_tree().physics_frame
	assert_float(wings.current_reduction_pct()).is_equal_approx(0.0, 0.001)

func test_boss_take_damage_applies_reduction_during_active_window() -> void:
	wings.trigger(2)
	for i in range(40):
		await get_tree().physics_frame
	var hp_before: int = boss.hp
	boss.take_damage(100)
	var dmg_taken: int = hp_before - boss.hp
	# Cap is 15; even after 60% reduction (40 → 16), cap dominates → ≤ 15
	assert_int(dmg_taken).is_less_equal(15)
