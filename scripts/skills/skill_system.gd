extends Node
class_name SkillSystem

const SkillScript = preload("res://scripts/skills/skill.gd")

signal active_skill_changed(new_index: int)
signal skill_unlocked(index: int)
signal elder_modifier_applied(modifier_id: String, new_stack: int)

var _skills: Array[Skill] = []
var _active_index: int = -1

# Phase 9 redesign: single-wand model. Old multi-wand cap / replace prompt /
# locked-skill path is removed. Wands now have a base_color + modifier_stack
# (color modifiers, currently empty since minors don't modify wands) +
# elder_modifier_stacks (drafted elder modifiers, compound on repeat).

func skill_count() -> int:
	return _skills.size()

func skill_at(index: int) -> Skill:
	if index < 0 or index >= _skills.size():
		return null
	return _skills[index]

func active_index() -> int:
	return _active_index

func active_skill() -> Skill:
	return skill_at(_active_index)

func active_element() -> String:
	var s: Skill = active_skill()
	return s.base_color if s != null else ""

func start_default_wand(color: String) -> void:
	# Called by player._ready (or test setup) to seed the run's wand.
	# Idempotent: if a wand already exists, no-op.
	if _skills.size() > 0:
		return
	var first := SkillScript.new(color) as Skill
	_skills.append(first)
	_active_index = 0
	skill_unlocked.emit(0)
	active_skill_changed.emit(0)

func unlock_first_wand(color: String) -> void:
	# Phase 10 tuning: the first minor soul pickup of a run unlocks a wand
	# of that color, but ONLY if no wand exists yet. Idempotent — no-op if
	# Wand Choice + start_default_wand already seeded a wand.
	if _skills.size() > 0:
		return
	var first := SkillScript.new(color) as Skill
	_skills.append(first)
	_active_index = 0
	skill_unlocked.emit(0)
	active_skill_changed.emit(0)

func apply_elder_modifier(modifier_id: String) -> void:
	# Adds modifier to the active wand, or compounds the existing stack if
	# repeat. No wand swap, no locking.
	var s: Skill = active_skill()
	if s == null:
		return
	s.apply_elder_modifier(modifier_id)
	var new_stack: int = s.elder_modifier_stack_count(modifier_id)
	elder_modifier_applied.emit(modifier_id, new_stack)
	active_skill_changed.emit(_active_index)

func clear() -> void:
	_skills.clear()
	_active_index = -1
	active_skill_changed.emit(-1)

# --- Serialize/restore for cross-scene retention (boss flow) ---

func to_dict() -> Dictionary:
	var skill_dicts: Array = []
	for s in _skills:
		skill_dicts.append({
			"base_color": s.base_color,
			"modifier_stack": s.modifier_stack.duplicate(),
			"elder_modifier_stacks": s.elder_modifier_stacks.duplicate(),
		})
	return {
		"skills": skill_dicts,
		"active_index": _active_index,
	}

func from_dict(d: Dictionary) -> void:
	_skills.clear()
	var skill_dicts: Array = d.get("skills", [])
	for sd in skill_dicts:
		var s := SkillScript.new(sd.get("base_color", "red")) as Skill
		var mods: Array = sd.get("modifier_stack", [])
		for m in mods:
			s.modifier_stack.append(m)
		var elder_stacks: Dictionary = sd.get("elder_modifier_stacks", {})
		for k in elder_stacks.keys():
			s.elder_modifier_stacks[k] = int(elder_stacks[k])
		_skills.append(s)
	_active_index = int(d.get("active_index", -1))
	if _active_index >= 0:
		skill_unlocked.emit(_active_index)
		active_skill_changed.emit(_active_index)
