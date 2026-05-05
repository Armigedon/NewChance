extends GdUnitTestSuite

const MarkMechanic = preload("res://scripts/entities/boss_mechanics/mechanic_mark.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

var boss: CharacterBody3D
var player: CharacterBody3D
var mark: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	add_child(player); player.global_position = Vector3(3, 0, 0)
	await get_tree().process_frame
	# Explicitly bind boss._player to this test's player, bypassing any stale
	# group-query result from prior test suites that left player nodes in the tree.
	boss._player = player
	# Clean up any mark zones still alive from earlier tests so their delayed
	# strikes don't fire during this one.
	for z in get_tree().get_nodes_in_group("mark_zone"):
		z.queue_free()
	for m in boss._mechanics.duplicate():
		m.queue_free()
	boss._mechanics.clear()
	mark = MarkMechanic.new()
	boss._register_mechanic(mark)
	mark._cooldown_remaining = 99.0
	await get_tree().process_frame
	boss.global_position = Vector3.ZERO
	player.global_position = Vector3(3, 0, 0)

func test_mechanic_is_locked_below_unlock_phase() -> void:
	mark._cooldown_remaining = 0.0
	assert_bool(mark.is_ready(0)).is_false()

func test_mechanic_unlocks_at_phase_1() -> void:
	mark._cooldown_remaining = 0.0
	assert_bool(mark.is_ready(1)).is_true()

func test_mechanic_is_big() -> void:
	assert_bool(mark.is_big).is_true()

func test_default_cooldown_phase_1() -> void:
	assert_float(mark.cooldowns_by_phase[1]).is_equal_approx(10.0, 0.001)

func test_mark_spawns_at_player_position_at_trigger() -> void:
	mark.trigger(1)
	# Drive past windup so _on_execution_start spawns the zone
	var ticked: float = 0.0
	while ticked < 0.10:
		mark.tick(1.0 / 60.0, 1)
		ticked += 1.0 / 60.0
	await get_tree().process_frame
	var marks: Array = get_tree().get_nodes_in_group("mark_zone")
	# At least one mark zone must be near the test player's position (3, 0, 0).
	# We search rather than assert size==1 to be resilient to stale zones from
	# other test suites that use short delays and may not yet be freed.
	var found: bool = false
	for z in marks:
		if z.global_position.distance_to(Vector3(3, 0, 0)) < 0.5:
			found = true
			break
	assert_bool(found).is_true()

func test_mark_strikes_player_if_still_in_zone_after_delay() -> void:
	var initial_hp: int = player.hp
	mark.trigger(1)
	var ticked: float = 0.0
	while ticked < 0.10:
		mark.tick(1.0 / 60.0, 1)
		ticked += 1.0 / 60.0
	# Let mark zone's _process drive the 2.5s delay
	for i in range(180):
		await get_tree().physics_frame
	assert_int(player.hp).is_less(initial_hp)

func test_mark_does_not_strike_player_who_moved_out() -> void:
	mark.trigger(1)
	var ticked: float = 0.0
	while ticked < 0.10:
		mark.tick(1.0 / 60.0, 1)
		ticked += 1.0 / 60.0
	await get_tree().process_frame
	# Player teleports out of the marked zone
	player.global_position = Vector3(20, 0, 0)
	await get_tree().process_frame
	var initial_hp: int = player.hp
	for i in range(180):
		await get_tree().physics_frame
	assert_int(player.hp).is_equal(initial_hp)
