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

func test_to_dict_serializes_full_state() -> void:
	mp.buy_cantrip("max_hp")
	var d: Dictionary = mp.to_dict()
	assert_that(d.has("cantrips")).is_true()
	assert_that(d.has("hub_features_unlocked")).is_true()
	assert_that(d.has("filled_pyres")).is_true()
	assert_that(d.has("pyre_milestones")).is_true()

func test_from_dict_restores_state() -> void:
	mp.buy_cantrip("sword_damage")
	var d: Dictionary = mp.to_dict()
	var mp2: Node = auto_free(MetaProgressScript.new())
	add_child(mp2)
	mp2.from_dict(d)
	assert_that(mp2.cantrip_level("sword_damage")).is_equal(1)
