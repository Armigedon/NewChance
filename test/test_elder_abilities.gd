extends GdUnitTestSuite

func test_registry_returns_null_for_unknown_color() -> void:
	# Pre-Phase-B-2: registry is empty. After B2, the registry is populated.
	# This test asserts the unknown-color case which works either way.
	assert_object(ElderAbilityRegistry.get_for_color("xyzzy")).is_null()

func test_elder_ability_instances_construct_with_color() -> void:
	var ability := ElderAbility.new("red")
	assert_str(ability.color).is_equal("red")
	# Hooks default unset.
	assert_bool(ability.on_alive_tick.is_null()).is_true()
	assert_bool(ability.on_attack.is_null()).is_true()
	assert_bool(ability.on_death.is_null()).is_true()
