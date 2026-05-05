extends GdUnitTestSuite

const ChargeScript = preload("res://scripts/entities/boss_mechanics/mechanic_charge.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

var boss: CharacterBody3D
var player: CharacterBody3D
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
	add_child(player); player.global_position = Vector3(0, 0, 5)
	await get_tree().process_frame
	for m in boss._mechanics.duplicate():
		m.queue_free()
	boss._mechanics.clear()
	charge = ChargeScript.new()
	boss._register_mechanic(charge)
	charge._cooldown_remaining = 99.0
	boss._player = player
	await get_tree().process_frame

func test_chill_during_charge_slows_velocity() -> void:
	boss._phase = 3
	charge.trigger(3)
	var ticked: float = 0.0
	while ticked < 1.45:
		charge.tick(1.0 / 60.0, 3)
		ticked += 1.0 / 60.0
	# Now in execution; apply chill 4x
	boss.apply_chill(4)
	# 4 stacks × 8% = 32% reduction → modifier ≤ 0.75 (allow tiny float slack)
	assert_float(charge._velocity_modifier).is_less(0.75)

func test_pull_during_charge_redirects_trajectory() -> void:
	boss._phase = 3
	charge.trigger(3)
	var ticked: float = 0.0
	while ticked < 1.45:
		charge.tick(1.0 / 60.0, 3)
		ticked += 1.0 / 60.0
	var initial_dir: Vector3 = charge._charge_dir
	boss.apply_pull_toward(boss.global_position + Vector3(2, 0, 0), 1.0)
	# Direction should have changed
	var dx: float = absf(charge._charge_dir.x - initial_dir.x)
	var dz: float = absf(charge._charge_dir.z - initial_dir.z)
	assert_bool(dx + dz > 0.001).is_true()
