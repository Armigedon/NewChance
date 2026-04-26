extends Node
class_name SkillSystem

const SkillScript = preload("res://scripts/skills/skill.gd")

enum AddResult { UNLOCKED, AT_CAP, MODIFIED, NOOP }

signal active_skill_changed(new_index: int)
signal skill_unlocked(index: int)
signal at_cap_replace_prompt_requested(incoming_color: String)

const BASE_CAP: int = 3

var _skills: Array[Skill] = []
var _active_index: int = -1
var _cap_override: int = -1  # -1 = use MetaProgress; >=0 = test override
var _in_run_elder_count: int = 0

func set_cap(n: int) -> void:
	_cap_override = n

func cap() -> int:
	if _cap_override >= 0:
		return _cap_override
	return BASE_CAP + MetaProgress.active_skill_cap_bonus()

func skill_count() -> int:
	return _skills.size()

func skill_at(index: int) -> Skill:
	if index < 0 or index >= _skills.size():
		return null
	return _skills[index]

func active_skill() -> Skill:
	return skill_at(_active_index)

func active_element() -> String:
	var s: Skill = active_skill()
	return s.base_color if s != null else ""

func add_minor(color: String) -> int:
	if _skills.is_empty():
		var first := SkillScript.new(color) as Skill
		_skills.append(first)
		_active_index = 0
		skill_unlocked.emit(0)
		active_skill_changed.emit(0)
		return AddResult.UNLOCKED
	var active: Skill = active_skill()
	if active == null:
		return AddResult.NOOP
	if active.locked:
		return AddResult.NOOP
	active.add_modifier(color)
	return AddResult.MODIFIED

func add_elder(color: String) -> int:
	if _skills.size() >= cap():
		at_cap_replace_prompt_requested.emit(color)
		return AddResult.AT_CAP
	if _active_index >= 0:
		_skills[_active_index].locked = true
	var new_skill := SkillScript.new(color) as Skill
	_skills.append(new_skill)
	_active_index = _skills.size() - 1
	_in_run_elder_count += 1
	Escalation.set_in_run_elder_count(_in_run_elder_count)
	skill_unlocked.emit(_active_index)
	active_skill_changed.emit(_active_index)
	return AddResult.UNLOCKED

func switch_active(index: int) -> void:
	if index < 0 or index >= _skills.size():
		return
	if index == _active_index:
		return
	_active_index = index
	active_skill_changed.emit(index)

func replace_at(index: int, new_color: String) -> void:
	if index < 0 or index >= _skills.size():
		return
	var new_skill := SkillScript.new(new_color) as Skill
	_skills[index] = new_skill
	_active_index = index
	skill_unlocked.emit(index)
	active_skill_changed.emit(index)

func decline_elder(declined_color: String) -> void:
	if _active_index < 0:
		return
	for i in range(3):
		add_minor(declined_color)

func clear() -> void:
	_skills.clear()
	_active_index = -1
	_in_run_elder_count = 0
	Escalation.set_in_run_elder_count(0)
	active_skill_changed.emit(-1)

# --- Serialize/restore for cross-scene retention (boss flow) ---

func to_dict() -> Dictionary:
	var skill_dicts: Array = []
	for s in _skills:
		skill_dicts.append({
			"base_color": s.base_color,
			"modifier_stack": s.modifier_stack.duplicate(),
			"locked": s.locked,
		})
	return {
		"skills": skill_dicts,
		"active_index": _active_index,
		"in_run_elder_count": _in_run_elder_count,
	}

func from_dict(d: Dictionary) -> void:
	_skills.clear()
	var skill_dicts: Array = d.get("skills", [])
	for sd in skill_dicts:
		var s := SkillScript.new(sd.get("base_color", "red")) as Skill
		# Bypass add_modifier (which respects locked) by appending directly
		var mods: Array = sd.get("modifier_stack", [])
		for m in mods:
			s.modifier_stack.append(m)
		s.locked = bool(sd.get("locked", false))
		_skills.append(s)
	_active_index = int(d.get("active_index", -1))
	_in_run_elder_count = int(d.get("in_run_elder_count", 0))
	Escalation.set_in_run_elder_count(_in_run_elder_count)
	if _active_index >= 0:
		skill_unlocked.emit(_active_index)
		active_skill_changed.emit(_active_index)
