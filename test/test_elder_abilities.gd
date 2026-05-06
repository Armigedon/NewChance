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

func test_registry_returns_red_fire_pool() -> void:
	var ability: ElderAbility = ElderAbilityRegistry.get_for_color("red")
	assert_object(ability).is_not_null()
	assert_str(ability.color).is_equal("red")
	assert_bool(ability.on_death.is_null()).is_false()

func test_registry_returns_blue_chill_aura() -> void:
	var ability: ElderAbility = ElderAbilityRegistry.get_for_color("blue")
	assert_object(ability).is_not_null()
	assert_bool(ability.on_alive_tick.is_null()).is_false()

func test_registry_returns_green_poison_trail() -> void:
	var ability: ElderAbility = ElderAbilityRegistry.get_for_color("green")
	assert_object(ability).is_not_null()
	assert_bool(ability.on_alive_tick.is_null()).is_false()

func test_registry_returns_purple_pull_on_hit() -> void:
	var ability: ElderAbility = ElderAbilityRegistry.get_for_color("purple")
	assert_object(ability).is_not_null()
	assert_bool(ability.on_attack.is_null()).is_false()

func test_registry_returns_gold_chain_on_hit() -> void:
	var ability: ElderAbility = ElderAbilityRegistry.get_for_color("gold")
	assert_object(ability).is_not_null()
	assert_bool(ability.on_attack.is_null()).is_false()

func test_registry_returns_white_bone_wall() -> void:
	var ability: ElderAbility = ElderAbilityRegistry.get_for_color("white")
	assert_object(ability).is_not_null()
	assert_bool(ability.on_death.is_null()).is_false()
