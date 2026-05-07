extends GdUnitTestSuite

const SkillScript = preload("res://scripts/skills/skill.gd")

func test_skill_starts_with_no_modifiers() -> void:
	var s := SkillScript.new("red")
	assert_that(s.base_color).is_equal("red")
	assert_that(s.modifier_stack).is_empty()

func test_skill_add_modifier_appends() -> void:
	var s := SkillScript.new("red")
	s.add_modifier("blue")
	s.add_modifier("green")
	assert_that(s.modifier_stack).is_equal(["blue", "green"])

func test_skill_modifier_count_includes_base_repeats() -> void:
	# Same-color minor souls deepen the base. Track count separately.
	var s := SkillScript.new("red")
	s.add_modifier("red")
	s.add_modifier("red")
	assert_that(s.modifier_count_for("red")).is_equal(2)

func test_skill_modifier_count_other_color() -> void:
	var s := SkillScript.new("red")
	s.add_modifier("blue")
	s.add_modifier("blue")
	s.add_modifier("green")
	assert_that(s.modifier_count_for("blue")).is_equal(2)
	assert_that(s.modifier_count_for("green")).is_equal(1)
	assert_that(s.modifier_count_for("red")).is_equal(0)
