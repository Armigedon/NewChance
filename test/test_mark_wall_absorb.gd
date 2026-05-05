extends GdUnitTestSuite

const MarkMechanic = preload("res://scripts/entities/boss_mechanics/mechanic_mark.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")
const WallScene: PackedScene = preload("res://scenes/effects/effect_bone_wall.tscn")

var boss: CharacterBody3D
var player: CharacterBody3D
var wall: StaticBody3D
var mark: Node

func before_test() -> void:
	# Free any stale zones/walls from prior tests BEFORE awaiting any frame —
	# their _process callbacks could otherwise fire during the await and damage
	# the new test's player.
	for z in get_tree().get_nodes_in_group("mark_zone"):
		z.queue_free()
	for w in get_tree().get_nodes_in_group("bone_wall"):
		w.queue_free()
	await get_tree().process_frame  # let queued frees actually take effect
	boss = auto_free(BossScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	wall = auto_free(WallScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	add_child(player); player.global_position = Vector3(3, 0, 0)
	add_child(wall); wall.global_position = Vector3(3, 0, 0)
	wall.configure(30, 5.0, 4.0)  # hp, lifetime (>2.5s mark delay), length
	await get_tree().process_frame
	boss._player = player
	for m in boss._mechanics.duplicate():
		m.queue_free()
	boss._mechanics.clear()
	mark = MarkMechanic.new()
	boss._register_mechanic(mark)
	mark._cooldown_remaining = 99.0
	await get_tree().process_frame
	# Position boss far away so its contact-damage _physics_process cannot reach
	# the player during the 3s await window (boss moves at 2.0 m/s, needs 50 units
	# of margin to stay out of the 2.5-unit contact range for 3+ seconds).
	boss.global_position = Vector3(-50, 0, 0)
	player.global_position = Vector3(3, 0, 0)
	wall.global_position = Vector3(3, 0, 0)

func test_wall_in_mark_zone_absorbs_strike() -> void:
	var initial_hp: int = player.hp
	var initial_wall_hp: int = wall.hp
	mark.trigger(1)
	var ticked: float = 0.0
	while ticked < 0.10:
		mark.tick(1.0 / 60.0, 1)
		ticked += 1.0 / 60.0
	for i in range(180):
		await get_tree().physics_frame
	assert_int(player.hp).is_equal(initial_hp)  # absorbed
	if is_instance_valid(wall):
		assert_int(wall.hp).is_less(initial_wall_hp)

func test_wall_outside_mark_zone_does_not_absorb() -> void:
	wall.global_position = Vector3(20, 0, 0)  # far from mark
	await get_tree().process_frame
	var initial_hp: int = player.hp
	mark.trigger(1)
	var ticked: float = 0.0
	while ticked < 0.10:
		mark.tick(1.0 / 60.0, 1)
		ticked += 1.0 / 60.0
	for i in range(180):
		await get_tree().physics_frame
	assert_int(player.hp).is_less(initial_hp)
