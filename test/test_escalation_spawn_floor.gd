extends GdUnitTestSuite

func before_test() -> void:
	Escalation.reset()

func test_dragon_floor_blocks_second_dragon_within_window() -> void:
	assert_bool(Escalation.can_spawn_tier("dragon")).is_true()
	Escalation.record_tier_spawn("dragon")
	assert_bool(Escalation.can_spawn_tier("dragon")).is_false()

func test_elder_floor_blocks_second_elder_within_window() -> void:
	assert_bool(Escalation.can_spawn_tier("elder")).is_true()
	Escalation.record_tier_spawn("elder")
	assert_bool(Escalation.can_spawn_tier("elder")).is_false()

func test_dragon_floor_does_not_block_elder() -> void:
	Escalation.record_tier_spawn("dragon")
	assert_bool(Escalation.can_spawn_tier("elder")).is_true()

func test_elder_floor_does_not_block_dragon() -> void:
	Escalation.record_tier_spawn("elder")
	assert_bool(Escalation.can_spawn_tier("dragon")).is_true()

func test_welps_always_spawnable() -> void:
	Escalation.record_tier_spawn("dragon")
	Escalation.record_tier_spawn("elder")
	assert_bool(Escalation.can_spawn_tier("welp")).is_true()

func test_unknown_tier_always_spawnable() -> void:
	assert_bool(Escalation.can_spawn_tier("alarm")).is_true()

func test_reset_clears_floors() -> void:
	Escalation.record_tier_spawn("dragon")
	Escalation.record_tier_spawn("elder")
	Escalation.reset()
	assert_bool(Escalation.can_spawn_tier("dragon")).is_true()
	assert_bool(Escalation.can_spawn_tier("elder")).is_true()
