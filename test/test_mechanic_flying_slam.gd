extends GdUnitTestSuite

const FlyingSlamScript = preload("res://scripts/entities/boss_mechanics/mechanic_flying_slam.gd")
const ChargeScript = preload("res://scripts/entities/boss_mechanics/mechanic_charge.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

var boss: CharacterBody3D
var player: CharacterBody3D
var slam: Node
var charge: Node

func before_test() -> void:
	for z in get_tree().get_nodes_in_group("mark_zone"):
		z.queue_free()
	for w in get_tree().get_nodes_in_group("bone_wall"):
		w.queue_free()
	await get_tree().process_frame
	boss = auto_free(BossScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	add_child(player); player.global_position = Vector3(0, 0, 3)
	await get_tree().process_frame
	for m in boss._mechanics.duplicate():
		m.queue_free()
	boss._mechanics.clear()
	slam = FlyingSlamScript.new()
	charge = ChargeScript.new()
	boss._register_mechanic(slam)
	boss._register_mechanic(charge)
	slam._cooldown_remaining = 99.0
	charge._cooldown_remaining = 99.0
	boss._player = player
	await get_tree().process_frame

func test_timings() -> void:
	assert_float(slam.windup_duration).is_equal_approx(2.0, 0.001)
	assert_float(slam.execution_duration).is_equal_approx(0.4, 0.001)

func test_unlocked_phase_3() -> void:
	assert_int(slam.unlock_phase).is_equal(3)

func test_lands_at_locked_target_and_damages() -> void:
	boss._phase = 3
	var initial_hp: int = player.hp
	slam.trigger(3)
	var ticked: float = 0.0
	while ticked < 2.5:  # past 2.0s windup + 0.4s execution
		slam.tick(1.0 / 60.0, 3)
		ticked += 1.0 / 60.0
	assert_int(player.hp).is_less(initial_hp)

func test_charge_triggers_shared_lockout() -> void:
	boss._phase = 3
	charge.trigger(3)
	charge.tick(1.0 / 60.0, 3)  # _on_windup_start fires
	assert_bool(boss.is_charge_or_slam_locked()).is_true()

func test_slam_triggers_shared_lockout() -> void:
	boss._phase = 3
	slam.trigger(3)
	slam.tick(1.0 / 60.0, 3)
	assert_bool(boss.is_charge_or_slam_locked()).is_true()
