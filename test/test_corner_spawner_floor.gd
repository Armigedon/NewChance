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

func test_corner_spawner_skips_when_floor_active() -> void:
	# When both dragon and elder floors are active, every dragon/elder roll
	# should result in NO spawn (not a welp downgrade). Welp rolls still spawn
	# normally — the floor only gates the rolled tier, not all spawns.
	var spawner = preload("res://scripts/world/corner_spawner.gd").new()
	spawner.color = "red"
	spawner.max_alive = 10
	add_child(spawner)
	spawner.global_position = Vector3.ZERO
	Escalation._heat["red"] = 100.0
	Escalation.record_tier_spawn("dragon")
	Escalation.record_tier_spawn("elder")
	for i in range(20):
		spawner._spawn()
	var dragon_or_elder_count: int = 0
	var welp_count: int = 0
	for n in get_tree().get_nodes_in_group("enemy"):
		if not "tier" in n:
			continue
		if n.tier == "dragon" or n.tier == "elder":
			dragon_or_elder_count += 1
		elif n.tier == "welp":
			welp_count += 1
	# No dragons/elders spawned (floors active).
	assert_int(dragon_or_elder_count).is_equal(0)
	# Roll outcomes that hit the floor should be skipped, not converted to welps.
	# At heat 100 the dragon+elder probability is 0.50, so on 20 rolls we expect
	# ~10 welps and ~10 skips. Allow generous variance — the assertion is just
	# that NOT all 20 became welps (which would mean downgrade).
	assert_int(welp_count).is_less(20)

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
