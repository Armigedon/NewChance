extends GdUnitTestSuite

func test_get_returns_modifier_by_id() -> void:
	var m: ElderModifier = ElderRegistry.get_modifier("ignite_all_hits")
	assert_object(m).is_not_null()
	assert_str(m.color).is_equal("red")

func test_get_unknown_id_returns_null() -> void:
	assert_object(ElderRegistry.get_modifier("nonexistent_xyz")).is_null()

func test_pool_for_color_returns_only_that_color() -> void:
	var pool: Array = ElderRegistry.pool_for_color("red")
	assert_int(pool.size()).is_greater(0)
	for m in pool:
		assert_str(m.color).is_equal("red")

func test_draft_returns_three_distinct_or_pool_size() -> void:
	# Draft should return min(3, pool_size) distinct modifiers.
	var draft: Array = ElderRegistry.draft_for_color("red")
	assert_int(draft.size()).is_between(1, 3)
	# All distinct.
	var ids: Dictionary = {}
	for m in draft:
		assert_bool(ids.has(m.modifier_id)).is_false()
		ids[m.modifier_id] = true

func test_all_six_colors_have_pools() -> void:
	for color in ["red", "blue", "green", "purple", "gold", "white"]:
		var pool: Array = ElderRegistry.pool_for_color(color)
		assert_int(pool.size()).is_greater(0)
