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

func test_active_element_returns_empty_when_no_wand() -> void:
	assert_that(ss.active_element()).is_equal("")

func test_active_element_returns_base_color_after_default_wand() -> void:
	ss.start_default_wand("red")
	assert_that(ss.active_element()).is_equal("red")

func test_clear_removes_wand() -> void:
	ss.start_default_wand("red")
	ss.apply_elder_modifier("ignite_all_hits")
	ss.clear()
	assert_that(ss.skill_count()).is_equal(0)
	assert_that(ss.active_skill()).is_null()

func test_active_skill_changed_signal_on_default_wand() -> void:
	var monitor := monitor_signals(ss)
	ss.start_default_wand("red")
	await assert_signal(ss).is_emitted("active_skill_changed", [0])

func test_skill_unlocked_signal_on_default_wand() -> void:
	var monitor := monitor_signals(ss)
	ss.start_default_wand("red")
	await assert_signal(ss).is_emitted("skill_unlocked", [0])

func test_apply_elder_modifier_emits_signal_with_stack() -> void:
	ss.start_default_wand("red")
	var monitor := monitor_signals(ss)
	ss.apply_elder_modifier("ignite_all_hits")
	await assert_signal(ss).is_emitted("elder_modifier_applied", ["ignite_all_hits", 1])

func test_apply_elder_modifier_no_op_without_wand() -> void:
	# Without a starting wand, apply_elder_modifier has nothing to attach to.
	ss.apply_elder_modifier("ignite_all_hits")
	assert_int(ss.skill_count()).is_equal(0)

func test_start_default_wand_idempotent() -> void:
	ss.start_default_wand("red")
	ss.start_default_wand("blue")  # Should be no-op since wand exists.
	assert_int(ss.skill_count()).is_equal(1)
	assert_str(ss.active_skill().base_color).is_equal("red")

func test_skill_starts_with_no_elder_modifiers() -> void:
	var s := Skill.new("red")
	assert_int(s.elder_modifier_count()).is_equal(0)

func test_apply_elder_modifier_adds_to_stack() -> void:
	var s := Skill.new("red")
	s.apply_elder_modifier("ignite_all_hits")
	assert_int(s.elder_modifier_count()).is_equal(1)
	assert_int(s.elder_modifier_stack_count("ignite_all_hits")).is_equal(1)

func test_repeat_elder_modifier_compounds() -> void:
	var s := Skill.new("red")
	s.apply_elder_modifier("ignite_all_hits")
	s.apply_elder_modifier("ignite_all_hits")
	# Two distinct entries OR one entry with stack=2 — we use stack count.
	assert_int(s.elder_modifier_stack_count("ignite_all_hits")).is_equal(2)
	# Distinct modifier ids count as 1 each (with their own stack count).
	s.apply_elder_modifier("cinder_trail")
	assert_int(s.elder_modifier_count()).is_equal(2)
	assert_int(s.elder_modifier_stack_count("cinder_trail")).is_equal(1)

func test_starts_with_default_red_wand() -> void:
	var ss: SkillSystem = auto_free(SkillSystem.new())
	add_child(ss)
	ss.start_default_wand("red")
	assert_int(ss.skill_count()).is_equal(1)
	assert_str(ss.active_skill().base_color).is_equal("red")

func test_unlock_first_wand_creates_wand_of_color() -> void:
	var ss: SkillSystem = auto_free(SkillSystem.new())
	add_child(ss)
	ss.unlock_first_wand("blue")
	assert_int(ss.skill_count()).is_equal(1)
	assert_str(ss.active_skill().base_color).is_equal("blue")

func test_unlock_first_wand_idempotent_when_wand_exists() -> void:
	var ss: SkillSystem = auto_free(SkillSystem.new())
	add_child(ss)
	ss.start_default_wand("red")
	ss.unlock_first_wand("blue")
	# Should not change the wand.
	assert_int(ss.skill_count()).is_equal(1)
	assert_str(ss.active_skill().base_color).is_equal("red")

func test_apply_elder_modifier_routes_to_active_wand() -> void:
	var ss: SkillSystem = auto_free(SkillSystem.new())
	add_child(ss)
	ss.start_default_wand("red")
	ss.apply_elder_modifier("ignite_all_hits")
	assert_int(ss.active_skill().elder_modifier_count()).is_equal(1)
	assert_int(ss.active_skill().elder_modifier_stack_count("ignite_all_hits")).is_equal(1)

func test_no_multi_wand_path() -> void:
	# After the redesign, SkillSystem only has one active wand. apply_elder
	# never spawns a new wand.
	var ss: SkillSystem = auto_free(SkillSystem.new())
	add_child(ss)
	ss.start_default_wand("red")
	for i in range(5):
		ss.apply_elder_modifier("test_mod_%d" % i)
	assert_int(ss.skill_count()).is_equal(1)

# --- Serialization round-trip ---

func test_to_dict_from_dict_roundtrip() -> void:
	ss.start_default_wand("blue")
	ss.apply_elder_modifier("ice_aoe")
	ss.apply_elder_modifier("ice_aoe")
	ss.apply_elder_modifier("frost_trail")
	var d := ss.to_dict()

	var ss2: SkillSystem = auto_free(SkillSystemScript.new())
	add_child(ss2)
	ss2.from_dict(d)
	assert_int(ss2.skill_count()).is_equal(1)
	var s2 := ss2.active_skill()
	assert_str(s2.base_color).is_equal("blue")
	assert_int(s2.elder_modifier_stack_count("ice_aoe")).is_equal(2)
	assert_int(s2.elder_modifier_stack_count("frost_trail")).is_equal(1)
