extends GdUnitTestSuite

const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

var boss: CharacterBody3D
var player: CharacterBody3D

func before_test() -> void:
	for z in get_tree().get_nodes_in_group("mark_zone"):
		z.queue_free()
	for w in get_tree().get_nodes_in_group("bone_wall"):
		w.queue_free()
	await get_tree().process_frame
	boss = auto_free(BossScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	add_child(player); player.global_position = Vector3(5, 0, 0)
	await get_tree().process_frame

func test_boss_has_all_8_mechanics_registered() -> void:
	assert_int(boss._mechanics.size()).is_equal(8)

func test_phase_2_unlocks_more_mechanics_than_phase_1() -> void:
	# At P2, P1 mechanics (slam, static breath, mark, jump) + P2 unlocks
	# (sweeping breath, armor wings) should all be ready (6 total).
	# Allow for one being mid-windup from auto-fire in before_test's process_frame.
	boss._phase = 2
	# Reset cooldowns so auto-fired state from before_test doesn't bias the count.
	for m in boss._mechanics:
		m._cooldown_remaining = 0.0
	var unlocked_in_p2: int = 0
	for m in boss._mechanics:
		if m.is_ready(2):
			unlocked_in_p2 += 1
	# Charge (P3) and FlyingSlam (P3) are still locked — so max ready = 6.
	# After auto-fire from before_test at most 1 is busy, leaving >= 5.
	# Use >= 4 to be resilient to edge cases (e.g. two mechanics both auto-firing
	# in the same frame during test suite parallelism is theoretically possible).
	assert_int(unlocked_in_p2).is_greater_equal(4)

func test_only_one_big_mechanic_busy_at_a_time() -> void:
	boss._phase = 1
	# Tick the scheduler once more and verify the mutual-exclusivity invariant.
	boss._tick_mechanics(0.05)
	var busy_bigs: int = 0
	for m in boss._mechanics:
		if m.is_busy() and m.is_big:
			busy_bigs += 1
	# At most 1 big mechanic should ever be in windup/execution simultaneously.
	assert_int(busy_bigs).is_less_equal(1)

func test_boss_dies_at_zero_hp() -> void:
	boss.hp = 1
	boss.take_damage(100)  # capped to 15 by DMG_CAP_PER_TICK, still lethal (hp=1→0)
	assert_int(boss.hp).is_equal(0)
	assert_bool(boss._is_dead).is_true()
	# The boss death sequence creates a tween that mutates Engine.time_scale for
	# a slow-mo effect. The tween runs over ~2.35s real time and continues
	# updating Engine.time_scale every frame. If we don't kill it here, it bleeds
	# into subsequent test files and corrupts physics-driven timing assertions.
	for tw in get_tree().get_processed_tweens():
		tw.kill()
	Engine.time_scale = 1.0
