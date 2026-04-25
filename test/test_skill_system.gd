extends GdUnitTestSuite

const SkillSystemScript = preload("res://scripts/skills/skill_system.gd")
const SkillScript = preload("res://scripts/skills/skill.gd")

var ss: SkillSystem

func before_test() -> void:
	ss = auto_free(SkillSystemScript.new())
	add_child(ss)

func test_starts_with_no_skills() -> void:
	assert_that(ss.skill_count()).is_equal(0)
	assert_that(ss.active_skill()).is_null()

func test_first_minor_soul_unlocks_skill_with_that_base() -> void:
	ss.add_minor("red")
	assert_that(ss.skill_count()).is_equal(1)
	var active: Skill = ss.active_skill()
	assert_that(active.base_color).is_equal("red")

func test_subsequent_minor_souls_modify_active_skill() -> void:
	ss.add_minor("red")
	ss.add_minor("blue")
	ss.add_minor("green")
	var active: Skill = ss.active_skill()
	assert_that(active.modifier_stack).is_equal(["blue", "green"])

func test_elder_soul_unlocks_new_skill_locks_prior() -> void:
	ss.add_minor("red")
	ss.add_minor("blue")
	var add_result := ss.add_elder("green")
	assert_that(add_result).is_equal(SkillSystemScript.AddResult.UNLOCKED)
	assert_that(ss.skill_count()).is_equal(2)
	assert_that(ss.active_skill().base_color).is_equal("green")
	var skill_0: Skill = ss.skill_at(0)
	assert_that(skill_0.base_color).is_equal("red")
	assert_that(skill_0.locked).is_true()

func test_minor_soul_after_elder_modifies_new_active() -> void:
	ss.add_minor("red")
	ss.add_elder("blue")
	ss.add_minor("green")
	var active: Skill = ss.active_skill()
	assert_that(active.base_color).is_equal("blue")
	assert_that(active.modifier_stack).is_equal(["green"])

func test_switch_active_changes_active_skill() -> void:
	ss.add_minor("red")
	ss.add_elder("blue")
	ss.switch_active(0)
	assert_that(ss.active_skill().base_color).is_equal("red")

func test_switch_active_invalid_index_no_op() -> void:
	ss.add_minor("red")
	ss.switch_active(5)
	assert_that(ss.active_skill().base_color).is_equal("red")

func test_minor_soul_after_switch_to_locked_does_not_modify() -> void:
	ss.add_minor("red")
	ss.add_elder("blue")
	ss.switch_active(0)
	ss.add_minor("green")
	# But the red skill is locked, so modifier should not apply
	var skill_red: Skill = ss.skill_at(0)
	assert_that(skill_red.modifier_stack).is_empty()

func test_active_element_returns_base_color_or_empty() -> void:
	assert_that(ss.active_element()).is_equal("")
	ss.add_minor("red")
	assert_that(ss.active_element()).is_equal("red")

func test_clear_removes_all_skills() -> void:
	ss.add_minor("red")
	ss.add_elder("blue")
	ss.clear()
	assert_that(ss.skill_count()).is_equal(0)
	assert_that(ss.active_skill()).is_null()

func test_at_cap_elder_returns_AT_CAP_no_unlock() -> void:
	ss.set_cap(3)
	ss.add_minor("red")
	ss.add_elder("blue")
	ss.add_elder("green")
	var result := ss.add_elder("purple")
	assert_that(result).is_equal(SkillSystemScript.AddResult.AT_CAP)
	assert_that(ss.skill_count()).is_equal(3)

func test_replace_at_index_swaps_skill() -> void:
	ss.set_cap(3)
	ss.add_minor("red")
	ss.add_elder("blue")
	ss.add_elder("green")
	ss.replace_at(0, "purple")
	assert_that(ss.skill_at(0).base_color).is_equal("purple")
	assert_that(ss.skill_at(0).locked).is_false()

func test_decline_elder_converts_to_3_minors() -> void:
	ss.set_cap(3)
	ss.add_minor("red")
	ss.add_elder("blue")
	ss.add_elder("green")
	ss.decline_elder("purple")
	var active: Skill = ss.active_skill()
	assert_that(active.modifier_count_for("purple")).is_equal(3)

func test_active_skill_changed_signal() -> void:
	var monitor := monitor_signals(ss)
	ss.add_minor("red")
	await assert_signal(ss).is_emitted("active_skill_changed", [0])

func test_skill_unlocked_signal() -> void:
	var monitor := monitor_signals(ss)
	ss.add_minor("red")
	await assert_signal(ss).is_emitted("skill_unlocked", [0])
