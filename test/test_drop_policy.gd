extends GdUnitTestSuite

const WelpScene: PackedScene = preload("res://scenes/entities/welp.tscn")

func before_test() -> void:
	# Clear any stale soul pickups and carry state from prior tests.
	for p in get_tree().get_nodes_in_group("soul_pickup"):
		p.queue_free()
	SoulEconomy.clear_carry()
	RunStats.reset_run()
	await get_tree().process_frame

func after_test() -> void:
	# Task 9: elder pickup spawns an ElderDraft modal and pauses the tree.
	# Tear it down so subsequent test suites aren't poisoned.
	get_tree().paused = false
	for c in get_tree().root.get_children():
		if c is CanvasLayer and c.get_script() != null:
			var src: String = c.get_script().resource_path
			if src.ends_with("/elder_draft.gd"):
				c.queue_free()
	await get_tree().process_frame

func _spawn(tier: String, color: String) -> CharacterBody3D:
	var w: CharacterBody3D = auto_free(WelpScene.instantiate())
	w.tier = tier
	w.color = color
	add_child(w)
	w.global_position = Vector3.ZERO
	return w

func _count_pickups_in_scene() -> Dictionary:
	var counts: Dictionary = {"minor": 0, "elder": 0}
	for p in get_tree().get_nodes_in_group("soul_pickup"):
		counts[String(p.tier)] = int(counts.get(String(p.tier), 0)) + 1
	return counts

func test_first_whelp_kill_drops_one_minor() -> void:
	var w := _spawn("welp", "red")
	w.take_damage(w.max_hp + 100)
	await get_tree().process_frame
	var counts := _count_pickups_in_scene()
	assert_int(counts["minor"]).is_equal(1)
	assert_int(counts["elder"]).is_equal(0)
	assert_bool(RunStats.first_whelp_kill_completed).is_true()

func test_subsequent_whelp_drops_nothing() -> void:
	# Mark first kill as already completed (simulating a prior whelp kill in the run).
	RunStats.mark_first_whelp_kill()
	var w := _spawn("welp", "red")
	w.take_damage(w.max_hp + 100)
	await get_tree().process_frame
	var counts := _count_pickups_in_scene()
	assert_int(counts["minor"]).is_equal(0)
	assert_int(counts["elder"]).is_equal(0)

func test_dragon_drops_only_minor_souls() -> void:
	var w := _spawn("dragon", "blue")
	w.take_damage(w.max_hp + 100)
	await get_tree().process_frame
	var counts := _count_pickups_in_scene()
	assert_int(counts["minor"]).is_between(1, 2)
	assert_int(counts["elder"]).is_equal(0)

func test_elder_drops_only_elder_pickup() -> void:
	var w := _spawn("elder", "purple")
	w.take_damage(w.max_hp + 100)
	await get_tree().process_frame
	var counts := _count_pickups_in_scene()
	assert_int(counts["minor"]).is_equal(0)
	assert_int(counts["elder"]).is_equal(1)

func test_minor_pickup_unlocks_first_wand_when_no_wand() -> void:
	# Phase 10 tuning: minor pickup unlocks first wand of that color when
	# the player has no wand (Wand Choice not unlocked).
	MetaShop.reset_for_test()
	var player: CharacterBody3D = auto_free(load("res://scenes/entities/player.tscn").instantiate())
	add_child(player)
	player.global_position = Vector3.ZERO
	await get_tree().process_frame
	var ss: SkillSystem = player.get_node("SkillSystem")
	# Player should start wandless (no Wand Choice unlocked in test default).
	assert_int(ss.skill_count()).is_equal(0)
	var pickup: Area3D = auto_free(load("res://scenes/interactables/soul_pickup.tscn").instantiate())
	pickup.color = "green"
	pickup.tier = "minor"
	add_child(pickup)
	pickup.global_position = Vector3.ZERO
	pickup._on_body_entered(player)
	# Wand unlocked of that color.
	assert_int(ss.skill_count()).is_equal(1)
	assert_str(ss.active_skill().base_color).is_equal("green")
	assert_int(SoulEconomy.carry_count("green", "minor")).is_equal(1)

func test_minor_pickup_no_unlock_when_wand_exists() -> void:
	# Phase 10 tuning: if the player already has a wand, minor pickup banks
	# to carry without changing the wand color.
	MetaShop.reset_for_test()
	var player: CharacterBody3D = auto_free(load("res://scenes/entities/player.tscn").instantiate())
	add_child(player)
	player.global_position = Vector3.ZERO
	await get_tree().process_frame
	var ss: SkillSystem = player.get_node("SkillSystem")
	ss.start_default_wand("red")
	var pickup: Area3D = auto_free(load("res://scenes/interactables/soul_pickup.tscn").instantiate())
	pickup.color = "green"
	pickup.tier = "minor"
	add_child(pickup)
	pickup.global_position = Vector3.ZERO
	pickup._on_body_entered(player)
	# Wand color did not change.
	assert_str(ss.active_skill().base_color).is_equal("red")
	assert_int(SoulEconomy.carry_count("green", "minor")).is_equal(1)

func test_elder_pickup_banks_carry_only() -> void:
	# ElderDraft is wired in Task 9; this task verifies that elder pickup banks
	# to carry and does NOT call add_elder anymore (no in-run wand mutation).
	var player: CharacterBody3D = auto_free(load("res://scenes/entities/player.tscn").instantiate())
	add_child(player)
	player.global_position = Vector3.ZERO
	await get_tree().process_frame
	var ss: SkillSystem = player.get_node("SkillSystem")
	var skills_before: int = ss.skill_count()
	var pickup: Area3D = auto_free(load("res://scenes/interactables/soul_pickup.tscn").instantiate())
	pickup.color = "blue"
	pickup.tier = "elder"
	add_child(pickup)
	pickup.global_position = Vector3.ZERO
	pickup._on_body_entered(player)
	# Skill system unchanged in this task; ElderDraft hookup lands in Task 9.
	assert_int(ss.skill_count()).is_equal(skills_before)
	assert_int(SoulEconomy.carry_count("blue", "elder")).is_equal(1)
