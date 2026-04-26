extends GdUnitTestSuite

const MetaProgressScript = preload("res://scripts/core/meta_progress.gd")

var mp: Node

func before_test() -> void:
	mp = auto_free(MetaProgressScript.new())
	add_child(mp)

func test_starts_with_default_state() -> void:
	assert_that(mp.cantrip_level("max_hp")).is_equal(0)
	assert_that(mp.cantrip_bonus("max_hp")).is_equal(0)
	assert_that(mp.hub_features_unlocked()).is_equal(0)
	assert_that(mp.active_skill_cap_bonus()).is_equal(0)

func test_buy_cantrip_increments_level() -> void:
	mp.buy_cantrip("max_hp")
	assert_that(mp.cantrip_level("max_hp")).is_equal(1)

func test_buy_cantrip_increases_bonus() -> void:
	mp.buy_cantrip("max_hp")
	mp.buy_cantrip("max_hp")
	assert_that(mp.cantrip_bonus("max_hp")).is_equal(40)

func test_buy_cantrip_max_level_caps() -> void:
	for i in range(20):
		mp.buy_cantrip("max_hp")
	assert_that(mp.cantrip_level("max_hp")).is_equal(MetaProgressScript.CANTRIP_MAX_LEVEL)

func test_unlock_next_hub_feature() -> void:
	mp.unlock_next_hub_feature()
	mp.unlock_next_hub_feature()
	assert_that(mp.hub_features_unlocked()).is_equal(2)

func test_hub_features_capped_at_4() -> void:
	for i in range(10):
		mp.unlock_next_hub_feature()
	assert_that(mp.hub_features_unlocked()).is_equal(4)

func test_active_skill_cap_bonus_increments_per_full_pyre() -> void:
	mp.on_pyre_full("red")
	mp.on_pyre_full("blue")
	assert_that(mp.active_skill_cap_bonus()).is_equal(2)

func test_pyre_full_only_counts_once_per_color() -> void:
	mp.on_pyre_full("red")
	mp.on_pyre_full("red")
	assert_that(mp.active_skill_cap_bonus()).is_equal(1)

func test_passive_color_bonus_at_25_percent() -> void:
	mp.on_pyre_milestone("red", 25)
	assert_that(mp.color_damage_bonus("red")).is_equal_approx(0.05, 0.001)

func test_passive_color_bonus_increases_at_75_percent() -> void:
	mp.on_pyre_milestone("red", 25)
	mp.on_pyre_milestone("red", 75)
	assert_that(mp.color_damage_bonus("red")).is_equal_approx(0.10, 0.001)

func test_to_dict_serializes_full_state() -> void:
	mp.buy_cantrip("max_hp")
	mp.on_pyre_full("red")
	mp.on_pyre_milestone("red", 25)
	var d: Dictionary = mp.to_dict()
	assert_that(d.has("cantrips")).is_true()
	assert_that(d.has("hub_features_unlocked")).is_true()
	assert_that(d.has("filled_pyres")).is_true()
	assert_that(d.has("pyre_milestones")).is_true()

func test_from_dict_restores_state() -> void:
	mp.buy_cantrip("sword_damage")
	mp.on_pyre_full("blue")
	var d: Dictionary = mp.to_dict()
	var mp2: Node = auto_free(MetaProgressScript.new())
	add_child(mp2)
	mp2.from_dict(d)
	assert_that(mp2.cantrip_level("sword_damage")).is_equal(1)
	assert_that(mp2.active_skill_cap_bonus()).is_equal(1)
