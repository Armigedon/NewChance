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

const WelpScene: PackedScene = preload("res://scenes/entities/welp.tscn")

func _spawn_elder(color: String, position: Vector3 = Vector3.ZERO) -> CharacterBody3D:
	var w: CharacterBody3D = auto_free(WelpScene.instantiate())
	w.tier = "elder"
	w.color = color
	add_child(w)
	w.global_position = position
	return w

func test_red_elder_drops_fire_pool_on_death() -> void:
	for c in get_tree().get_nodes_in_group("damage_cloud"):
		c.queue_free()
	await get_tree().process_frame
	var elder := _spawn_elder("red")
	await get_tree().process_frame
	elder.take_damage(elder.max_hp + 100)
	await get_tree().process_frame
	var found_red_pool: bool = false
	for c in get_tree().get_nodes_in_group("damage_cloud"):
		if c.get("base_color") == "red":
			found_red_pool = true
			break
	assert_bool(found_red_pool).is_true()

func test_blue_elder_chill_aura_applies_chill_to_player() -> void:
	var elder := _spawn_elder("blue")
	var player: CharacterBody3D = auto_free(load("res://scenes/entities/player.tscn").instantiate())
	add_child(player)
	player.global_position = Vector3(2, 0, 0)  # within 3m
	await get_tree().process_frame
	# Drive the alive_tick hook directly with a delta past the 1.0s tick interval.
	# Relying on physics_frame is flaky in the gdunit headless harness — welps'
	# _physics_process doesn't always advance during test waits.
	elder._elder_ability.on_alive_tick.call(elder, 1.5)
	assert_float(player._chill_stacks).is_greater_equal(1.0)

func test_green_elder_drops_poison_trail_on_movement() -> void:
	for c in get_tree().get_nodes_in_group("damage_cloud"):
		c.queue_free()
	await get_tree().process_frame
	var elder := _spawn_elder("green", Vector3.ZERO)
	await get_tree().process_frame
	# Anchor the trail at origin (first tick records position and returns).
	elder._elder_ability.on_alive_tick.call(elder, 1.0 / 60.0)
	# Move elder ~1.5m and fire again — anchor distance now exceeds drop threshold.
	elder.global_position = Vector3(1.5, 0, 0)
	elder._elder_ability.on_alive_tick.call(elder, 1.0 / 60.0)
	await get_tree().process_frame
	var found_green_cloud: bool = false
	for c in get_tree().get_nodes_in_group("damage_cloud"):
		if c.get("base_color") == "green":
			found_green_cloud = true
			break
	assert_bool(found_green_cloud).is_true()

func test_purple_elder_pulls_player_on_attack() -> void:
	var elder := _spawn_elder("purple", Vector3.ZERO)
	var player: CharacterBody3D = auto_free(load("res://scenes/entities/player.tscn").instantiate())
	add_child(player)
	player.global_position = Vector3(2, 0, 0)
	await get_tree().process_frame
	var prev_kb: Vector3 = player._knockback_velocity
	# Force-fire on_attack (purple's ability calls apply_pull_toward on the target).
	elder._elder_ability.on_attack.call(elder, player)
	# Knockback velocity x should have decreased (player pulled toward elder at origin).
	assert_bool(player._knockback_velocity.x < prev_kb.x).is_true()

func test_gold_elder_chain_zaps_other_enemy() -> void:
	var elder := _spawn_elder("gold", Vector3.ZERO)
	var other: CharacterBody3D = auto_free(WelpScene.instantiate())
	other.tier = "welp"
	other.color = "red"
	add_child(other)
	other.global_position = Vector3(2, 0, 0)
	await get_tree().process_frame
	var initial_hp: int = other.hp
	# Fire on_attack with player as the primary target (not really used by gold).
	elder._elder_ability.on_attack.call(elder, null)
	assert_int(other.hp).is_less(initial_hp)

func test_white_elder_spawns_bone_wall_near_pc_on_death() -> void:
	for w in get_tree().get_nodes_in_group("bone_wall"):
		w.queue_free()
	await get_tree().process_frame
	var elder := _spawn_elder("white", Vector3(8, 0, 0))
	var player: CharacterBody3D = auto_free(load("res://scenes/entities/player.tscn").instantiate())
	add_child(player)
	player.global_position = Vector3.ZERO
	await get_tree().process_frame
	elder.take_damage(elder.max_hp + 100)
	await get_tree().process_frame
	var found_wall: bool = false
	for w in get_tree().get_nodes_in_group("bone_wall"):
		if not is_instance_valid(w):
			continue
		var d: float = w.global_position.distance_to(player.global_position)
		# Wall should be 2-3m from the player.
		if d >= 1.5 and d <= 3.5:
			found_wall = true
			break
	assert_bool(found_wall).is_true()
