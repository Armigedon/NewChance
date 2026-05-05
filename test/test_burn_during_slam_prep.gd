extends GdUnitTestSuite

const FlyingSlamScript = preload("res://scripts/entities/boss_mechanics/mechanic_flying_slam.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")

var boss: CharacterBody3D
var slam: Node

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
	slam = FlyingSlamScript.new()
	boss._register_mechanic(slam)
	slam._cooldown_remaining = 99.0
	await get_tree().process_frame

func test_burn_does_1_5x_damage_during_slam_prep() -> void:
	boss.apply_burn(20.0, 5.0)  # 20 dps for 5s
	boss._phase = 3
	slam.trigger(3)
	var hp_before: int = boss.hp
	for i in range(30):  # 0.5s
		await get_tree().physics_frame
	var dmg_taken: int = hp_before - boss.hp
	# Without multiplier: 20 dps × 0.5s = 10 dmg
	# With 1.5x: 30 dps × 0.5s = 15 dmg (cap allows up to 15)
	assert_int(dmg_taken).is_greater(10)
