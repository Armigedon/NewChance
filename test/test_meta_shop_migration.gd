extends GdUnitTestSuite

func before_test() -> void:
	MetaShop.reset_for_test()
	MetaProgress.reset_meta()
	SoulEconomy.reset_meta()

func test_cantrips_migrate_to_stat_ranks() -> void:
	MetaProgress._cantrips["max_hp"] = 3
	MetaProgress._cantrips["sword_damage"] = 2
	MetaProgress._cantrips["dash_cooldown"] = 1
	MetaProgress.migrate_to_meta_shop()
	assert_int(MetaShop.stat_rank("vitality")).is_equal(3)
	assert_int(MetaShop.stat_rank("power")).is_equal(2)
	assert_int(MetaShop.stat_rank("cast_speed")).is_equal(1)
	assert_int(MetaShop.stat_rank("pyre_cap")).is_equal(0)
	assert_int(MetaShop.stat_rank("soul_magnetism")).is_equal(0)

func test_hub_features_migrate_to_structural_purchases() -> void:
	MetaProgress._hub_features_unlocked = 2
	MetaProgress.migrate_to_meta_shop()
	assert_bool(MetaShop.has_structural("wand_choice")).is_true()
	assert_bool(MetaShop.has_structural("second_modifier_slot")).is_true()
	assert_bool(MetaShop.has_structural("pyre_expansion_1")).is_false()

func test_pyre_fills_credit_minor_souls() -> void:
	# Pyre fills today represent banked progress; in the new system they
	# convert 1:1 to minor souls.
	SoulEconomy.set_pyre_fill("red", 30)
	SoulEconomy.set_pyre_fill("blue", 20)
	MetaProgress.migrate_to_meta_shop()
	assert_int(MetaShop.minor_souls()).is_equal(50)

func test_migration_idempotent() -> void:
	# Calling twice doesn't double-credit.
	MetaProgress._cantrips["max_hp"] = 3
	MetaProgress.migrate_to_meta_shop()
	MetaProgress.migrate_to_meta_shop()
	assert_int(MetaShop.stat_rank("vitality")).is_equal(3)
