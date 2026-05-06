extends GdUnitTestSuite

func before_test() -> void:
	Escalation.reset()
	for n in get_tree().get_nodes_in_group("enemy"):
		n.queue_free()
	await get_tree().process_frame

func test_spawn_records_tier_when_dragon_rolled() -> void:
	# Force a dragon roll by ensuring heat is high enough.
	Escalation._heat["red"] = 100.0  # max heat for red corner
	# Stub: directly call record_tier_spawn to simulate a successful spawn,
	# then verify the floor blocks the next attempt.
	Escalation.record_tier_spawn("dragon")
	assert_bool(Escalation.can_spawn_tier("dragon")).is_false()

func test_corner_spawner_downgrades_when_floor_active() -> void:
	# Set up: floor is active for dragon. The spawner's _spawn rolls dragon
	# but should downgrade to welp.
	var spawner = preload("res://scripts/world/corner_spawner.gd").new()
	spawner.color = "red"
	spawner.max_alive = 10
	add_child(spawner)
	spawner.global_position = Vector3.ZERO
	# Force heat high so roll_tier returns dragon-ish.
	Escalation._heat["red"] = 100.0
	# Mark dragon floor as recently used.
	Escalation.record_tier_spawn("dragon")
	# Drive _spawn 20 times. With dragon floor active, all spawns should be welps.
	# (heat 100 alone might still roll elder, so also block elder.)
	Escalation.record_tier_spawn("elder")
	var dragon_or_elder_count: int = 0
	for i in range(20):
		spawner._spawn()
	for n in get_tree().get_nodes_in_group("enemy"):
		if "tier" in n and (n.tier == "dragon" or n.tier == "elder"):
			dragon_or_elder_count += 1
	# All spawns should have downgraded to welp.
	assert_int(dragon_or_elder_count).is_equal(0)

func test_corner_spawner_records_tier_after_successful_spawn() -> void:
	var spawner = preload("res://scripts/world/corner_spawner.gd").new()
	spawner.color = "red"
	spawner.max_alive = 10
	add_child(spawner)
	spawner.global_position = Vector3.ZERO
	Escalation._heat["red"] = 100.0
	# At least one of 30 spawns should record a dragon or elder (since heat 100
	# rolls dragon ~35% / elder ~15%).
	for i in range(30):
		spawner._spawn()
	# After enough spawns, at least one of the tier timestamps should be non-zero.
	var any_recorded: bool = (
		Escalation._last_dragon_spawn_msec > 0
		or Escalation._last_elder_spawn_msec > 0
	)
	assert_bool(any_recorded).is_true()
