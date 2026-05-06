extends GdUnitTestSuite

const SwordScene: PackedScene = preload("res://scenes/entities/sword.tscn")

var sword: Area3D

func before_test() -> void:
	sword = auto_free(SwordScene.instantiate())
	add_child(sword)
	await get_tree().process_frame

func test_sword_dmg_no_white_returns_base() -> void:
	sword.set_active_element("red", 0)
	assert_that(sword.scaled_damage()).is_equal(15)

func test_sword_dmg_white_base_n1_scales() -> void:
	# n = 0 modifiers + 1 (white base) = 1; mult = 1 + 1*(1 - 0.7^1) = 1.30; floor(15*1.30) = 19
	sword.set_active_element("white", 0)
	assert_that(sword.scaled_damage()).is_equal(19)

func test_sword_dmg_white_base_with_modifiers() -> void:
	# n = 4 + 1 = 5; mult = 1 + 1*(1 - 0.7^5) = 1.832; floor(15*1.832) = 27
	sword.set_active_element("white", 4)
	assert_that(sword.scaled_damage()).is_equal(27)

func test_sword_dmg_caps_at_2x() -> void:
	# Very high n approaches 2.0x -> floor(30) = 30
	sword.set_active_element("red", 100)
	assert_that(sword.scaled_damage()).is_equal(29)

func test_sword_white_count_refreshes_when_modifier_added_to_active_skill() -> void:
	# Build a player with skill system, sword, and a white-base skill.
	# Phase 9 redesign: wand is seeded by player._ready as red. We clear and
	# restart it as white, then push a white modifier directly to verify the
	# sword's scaled_damage reflects the new n.
	var PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")
	var player: CharacterBody3D = auto_free(PlayerScene.instantiate())
	add_child(player)
	await get_tree().process_frame
	var ss: SkillSystem = player.get_node("SkillSystem")
	var sword: Area3D = player.get_node("Sword")
	# Replace the default red wand with a white-base wand (n_effective = 1, sword = 19).
	ss.clear()
	ss.start_default_wand("white")
	await get_tree().process_frame
	assert_int(sword.scaled_damage()).is_equal(19)
	# Add a white modifier to the active skill (n_effective = 2, sword = 22)
	ss.active_skill().add_modifier("white")
	# Re-emit active_skill_changed so the sword refreshes its cached white count.
	ss.active_skill_changed.emit(ss.active_index())
	await get_tree().process_frame
	# n=2: mult = 1 + 1*(1 - 0.7^2) = 1.51, floor(15*1.51) = 22
	assert_int(sword.scaled_damage()).is_equal(22)
