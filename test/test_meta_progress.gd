extends GdUnitTestSuite

# MetaProgress is now a save-format shim. Active state lives in MetaShop;
# these tests only cover the migration shape (legacy save → MetaShop).

const MetaProgressScript = preload("res://scripts/core/meta_progress.gd")

var mp: Node

func before_test() -> void:
	mp = auto_free(MetaProgressScript.new())
	add_child(mp)

func test_starts_with_default_state() -> void:
	assert_that(mp.hub_features_unlocked()).is_equal(0)

func test_to_dict_round_trip() -> void:
	mp._cantrips["max_hp"] = 3
	mp._hub_features_unlocked = 2
	var d: Dictionary = mp.to_dict()
	assert_that(d.has("cantrips")).is_true()
	assert_that(d.has("hub_features_unlocked")).is_true()
	var mp2: Node = auto_free(MetaProgressScript.new())
	add_child(mp2)
	mp2.from_dict(d)
	assert_that(mp2._cantrips["max_hp"]).is_equal(3)
	assert_that(mp2.hub_features_unlocked()).is_equal(2)
