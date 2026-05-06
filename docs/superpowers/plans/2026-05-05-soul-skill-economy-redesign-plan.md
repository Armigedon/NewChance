# Soul/Skill Economy Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** rework the soul/skill economy per [the design spec](../specs/2026-05-05-soul-skill-economy-redesign-design.md) so that whelps drop nothing, dragons drop minor souls (meta currency), elders drop a drafted transformative modifier + elder currency, and cross-run progression moves to a player-driven shop.

**Architecture:** drop policy on `welp.gd`, pickup decouples from `SkillSystem`, `SkillSystem` simplifies to single-wand-with-elder-modifiers, new `ElderRegistry` autoload + `ElderModifier` resource type, new `ElderDraft` UI flow on elder pickup, new `MetaShop` autoload + UI replacing `MetaProgress` auto-unlock paths. Existing `damage_pipeline.gd` gains hooks to fold elder modifier effects into the damage event chain.

**Tech Stack:** Godot 4.6, GDScript, GdUnit4 testing.

**Scope note:** this plan delivers Phase 1 (drop policy) + Phase 2 infrastructure + the first 12 elder modifiers (2 per color = a working draft system with limited variety) + Phase 3 (meta shop + migration). The remaining 36 modifiers are content expansion in a follow-up plan; the draft scene gracefully handles smaller pools (draws min(3, pool_size) cards). All existing 302 tests must still pass after each task; tests touching `add_minor`/`add_elder`/multi-wand will be rewritten in-place.

---

## File structure

**Create:**
- `scripts/skills/elder_modifier.gd` — resource defining one modifier (id, color, name, description, hooks)
- `scripts/skills/elder_registry.gd` — autoload mapping `modifier_id → ElderModifier`; loaded once at boot
- `scripts/ui/elder_draft.gd` + `scenes/ui/elder_draft.tscn` — modal scene shown on elder pickup
- `scripts/core/meta_shop.gd` — autoload replacing `meta_progress.gd` purchase logic
- `scripts/ui/meta_shop_ui.gd` + `scenes/ui/meta_shop_ui.tscn` — shop scene with two tabs
- `test/test_drop_policy.gd` — drop counts per tier
- `test/test_skill_system_elder.gd` — apply_elder_modifier semantics
- `test/test_elder_registry.gd` — registry lookups + pool queries
- `test/test_elder_draft.gd` — scene flow + draft draws
- `test/test_meta_shop.gd` — purchase logic, currency spend, rank caps
- `test/test_meta_shop_migration.gd` — old MetaProgress state → new MetaShop state

**Modify:**
- `scripts/entities/welp.gd` (`_drop_souls`)
- `scripts/interactables/soul_pickup.gd` (`_on_body_entered`)
- `scripts/skills/skill.gd` (add `elder_modifier_stacks` field)
- `scripts/skills/skill_system.gd` (remove `add_minor`/`add_elder`/multi-wand; add `apply_elder_modifier`)
- `scripts/skills/damage_pipeline.gd` (hook elder modifier callbacks)
- `scripts/entities/player.gd` (`_ready` defaults to red wand; remove `add_minor` call)
- `scripts/core/meta_progress.gd` (deprecate — keep file for save migration only)
- `scripts/core/game_state.gd` (no logic change; verify `end_run(DESCENDED)` deposit path still works)
- `test/test_skill_system.gd` (rewrite for new API)
- `test/test_soul_economy.gd` (drop multi-wand assertions if present)

---

## Phase 1 — Drop policy + pickup decoupling

### Task 1: Tier-aware drop policy on welp.gd

**Files:**
- Modify: `scripts/entities/welp.gd:237-247` (`_drop_souls` method)
- Test: `test/test_drop_policy.gd` (new)

- [ ] **Step 1: Write the failing test**

Create `test/test_drop_policy.gd`:

```gdscript
extends GdUnitTestSuite

const WelpScene: PackedScene = preload("res://scenes/entities/welp.tscn")

func before_test() -> void:
	# Clear any stale soul pickups from prior tests.
	for p in get_tree().get_nodes_in_group("soul_pickup"):
		p.queue_free()
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
	for n in get_tree().get_root().get_children():
		_walk_count(n, counts)
	return counts

func _walk_count(node: Node, counts: Dictionary) -> void:
	if node.has_method("_on_body_entered") and "tier" in node:
		counts[String(node.tier)] = int(counts.get(String(node.tier), 0)) + 1
	for c in node.get_children():
		_walk_count(c, counts)

func test_whelp_drops_nothing() -> void:
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
```

- [ ] **Step 2: Run test to verify it fails**

Run from project root:
```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_drop_policy.gd --ignoreHeadlessMode
```
Expected: `test_whelp_drops_nothing FAILED` (whelp drops 1 minor today).

- [ ] **Step 3: Update `_drop_souls` in `scripts/entities/welp.gd`**

Replace lines 237-247 with:

```gdscript
func _drop_souls() -> void:
	# Special "alarm" welps drop nothing (used by time-alarm spawner in T8)
	# Boss-summoned whelps also drop nothing
	if color == "alarm" or color == "boss":
		return
	# Phase 9 redesign (May 2026): tier-aware drop policy.
	# - welp: nothing (was 1 minor)
	# - dragon: 1-2 minor (was 2-3)
	# - elder: 1 elder, no minors (was 1 elder + 2-3 minor)
	if tier == "welp":
		return
	if tier == "dragon":
		var minor_count: int = 1 + (1 if randf() < 0.5 else 0)
		for i in range(minor_count):
			_spawn_pickup("minor", _random_offset())
		return
	if tier == "elder":
		_spawn_pickup("elder", _random_offset())
		return
```

- [ ] **Step 4: Run the new test, verify pass**

Same command as step 2. Expected: 3 PASSED.

- [ ] **Step 5: Run the full test suite, verify nothing else broke**

```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --continue --ignoreHeadlessMode 2>&1 | tail -3
```
Expected: `Overall Summary: 305+ test cases | 0 errors | 0 failures` (3 new tests added). If failures appear in other suites that depended on whelps dropping minors, those tests need updates — note them and continue, fixing in the next task.

- [ ] **Step 6: Commit**

```
git add test/test_drop_policy.gd scripts/entities/welp.gd
git commit -m "feat(economy): tier-aware drop policy — whelps drop nothing, dragons drop minors, elders drop elder pickup"
```

---

### Task 2: Decouple soul pickup from SkillSystem

**Files:**
- Modify: `scripts/interactables/soul_pickup.gd:53-64`
- Modify: `scripts/entities/player.gd:32-37` (remove `add_minor` call from `_ready`)
- Test: existing `test/test_soul_economy.gd` already covers carry semantics

- [ ] **Step 1: Write the failing test**

Add to `test/test_drop_policy.gd`:

```gdscript
func test_minor_pickup_does_not_call_skill_system() -> void:
	# Stand up a player and a minor pickup overlapping the player.
	var player: CharacterBody3D = auto_free(load("res://scenes/entities/player.tscn").instantiate())
	add_child(player)
	player.global_position = Vector3.ZERO
	await get_tree().process_frame
	var ss: SkillSystem = player.get_node("SkillSystem")
	# Snapshot skill state pre-pickup.
	var skills_before: int = ss.skill_count()
	var pickup: Area3D = auto_free(load("res://scenes/interactables/soul_pickup.tscn").instantiate())
	pickup.color = "red"
	pickup.tier = "minor"
	add_child(pickup)
	pickup.global_position = Vector3.ZERO
	# Trigger pickup via direct call (bypasses Area3D body_entered timing).
	pickup._on_body_entered(player)
	# Skill system should be unchanged; carry should have one minor red.
	assert_int(ss.skill_count()).is_equal(skills_before)
	assert_int(SoulEconomy.carry_count("red", "minor")).is_equal(1)

func test_elder_pickup_carries_and_triggers_draft() -> void:
	# We don't have ElderDraft yet (Task 8); for this task, just verify the
	# pickup banks to carry and does NOT call add_elder anymore.
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
	# Skill system unchanged in this task; ElderDraft hookup lands in Task 8.
	assert_int(ss.skill_count()).is_equal(skills_before)
	assert_int(SoulEconomy.carry_count("blue", "elder")).is_equal(1)
```

- [ ] **Step 2: Run test, verify it fails**

Same command as Task 1 step 2 with `test_drop_policy.gd`. Expected: the new tests fail because pickup currently calls `ss.add_minor` / `ss.add_elder` which mutates skill state.

- [ ] **Step 3: Modify `soul_pickup.gd._on_body_entered`**

Replace lines 53-64 with:

```gdscript
func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	# Phase 9 redesign: pickups bank to SoulEconomy carry only. The direct
	# SkillSystem mutation is gone — minors are pure meta currency, elders
	# trigger an ElderDraft flow in soul_pickup.gd Task 8.
	SoulEconomy.add_to_carry(color, tier, 1)
	queue_free()
```

- [ ] **Step 4: Modify `player.gd._ready` — remove `add_minor` call**

In `scripts/entities/player.gd:32-37`, replace:

```gdscript
	if not BossFlow.retained_skills.is_empty() and _skill_system != null:
		_skill_system.from_dict(BossFlow.retained_skills)
	else:
		var queued: String = MetaProgress.consume_start_with_skill()
		if queued != "" and _skill_system != null:
			_skill_system.add_minor(queued)
```

with:

```gdscript
	if not BossFlow.retained_skills.is_empty() and _skill_system != null:
		_skill_system.from_dict(BossFlow.retained_skills)
	# Phase 9 redesign: default starting wand handled in Task 4 of soul-skill
	# economy plan via _skill_system.start_default_wand(). The
	# MetaProgress.consume_start_with_skill() path is gone — replaced by
	# Wand Choice structural unlock + start_default_wand_color in Task 13.
```

- [ ] **Step 5: Run tests, verify pass**

Run `test/test_drop_policy.gd` plus full suite. Expected: drop policy tests pass; existing tests in `test_skill_system.gd` may now fail because `add_minor` no longer fires from pickups (those tests call `add_minor` directly so they'll still work, but anything that relied on pickup → skill state will fail). Note failures and proceed; Task 3 rewrites the affected tests.

- [ ] **Step 6: Commit**

```
git add test/test_drop_policy.gd scripts/interactables/soul_pickup.gd scripts/entities/player.gd
git commit -m "refactor(economy): decouple soul pickup from SkillSystem (carry-only)"
```

---

## Phase 2a — SkillSystem rework

### Task 3: Add elder_modifier_stacks to Skill

**Files:**
- Modify: `scripts/skills/skill.gd` (add field + helpers)
- Test: existing `test/test_skill_system.gd`

- [ ] **Step 1: Write the failing test**

Append to `test/test_skill_system.gd`:

```gdscript
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
```

- [ ] **Step 2: Run test, verify it fails**

Run:
```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_skill_system.gd --ignoreHeadlessMode
```
Expected: failures because `elder_modifier_count` / `apply_elder_modifier` don't exist.

- [ ] **Step 3: Add elder modifier support to `scripts/skills/skill.gd`**

Replace the file contents with:

```gdscript
extends RefCounted
class_name Skill

var base_color: String
var modifier_stack: Array[String] = []
var locked: bool = false
# Phase 9: elder modifiers are a separate stack from color modifiers (which
# come from the now-removed minor-pickup path). Keyed by modifier_id; value
# is the stack count (compounds on repeat draft).
var elder_modifier_stacks: Dictionary = {}

func _init(p_base_color: String) -> void:
	base_color = p_base_color

func add_modifier(color: String) -> void:
	if locked:
		return
	modifier_stack.append(color)

func modifier_count_for(color: String) -> int:
	var n: int = 0
	for c in modifier_stack:
		if c == color:
			n += 1
	return n

func has_modifier(color: String) -> bool:
	return modifier_count_for(color) > 0

func apply_elder_modifier(modifier_id: String) -> void:
	# Compounds on repeat — bumps stack count instead of adding a duplicate
	# entry. Distinct modifier ids each get their own entry.
	elder_modifier_stacks[modifier_id] = int(elder_modifier_stacks.get(modifier_id, 0)) + 1

func elder_modifier_count() -> int:
	return elder_modifier_stacks.size()

func elder_modifier_stack_count(modifier_id: String) -> int:
	return int(elder_modifier_stacks.get(modifier_id, 0))

func has_elder_modifier(modifier_id: String) -> bool:
	return elder_modifier_stacks.has(modifier_id)
```

- [ ] **Step 4: Run tests, verify pass**

Same command as step 2. Expected: 3 new tests pass.

- [ ] **Step 5: Commit**

```
git add scripts/skills/skill.gd test/test_skill_system.gd
git commit -m "feat(skill): add elder_modifier_stacks field + apply/query helpers"
```

---

### Task 4: SkillSystem single-wand model + remove add_minor/add_elder

**Files:**
- Modify: `scripts/skills/skill_system.gd` (gut multi-wand path)
- Modify: `test/test_skill_system.gd` (rewrite affected tests)

- [ ] **Step 1: Write the failing test**

Append to `test/test_skill_system.gd`:

```gdscript
func test_starts_with_default_red_wand() -> void:
	var ss: SkillSystem = auto_free(SkillSystem.new())
	add_child(ss)
	ss.start_default_wand("red")
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
```

- [ ] **Step 2: Run tests, verify they fail**

Same command as Task 3 step 2. Expected: `start_default_wand`, `apply_elder_modifier` don't exist on SkillSystem.

- [ ] **Step 3: Replace `scripts/skills/skill_system.gd`**

```gdscript
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
```

- [ ] **Step 4: Update `player.gd._ready`**

In `scripts/entities/player.gd:32-37`, replace the comment block from Task 2 step 4 with the actual default-wand call:

```gdscript
	if not BossFlow.retained_skills.is_empty() and _skill_system != null:
		_skill_system.from_dict(BossFlow.retained_skills)
	elif _skill_system != null:
		# Phase 9: default starting wand. Pre-Wand-Choice unlock = always red.
		# After Wand Choice purchased, MetaShop returns the player's chosen color.
		var start_color: String = MetaShop.starting_wand_color() if Engine.has_singleton("MetaShop") else "red"
		_skill_system.start_default_wand(start_color)
```

- [ ] **Step 5: Update `test/test_skill_system.gd`**

Remove tests that reference: `add_minor`, `add_elder`, `replace_at`, `decline_elder`, `at_cap_replace_prompt_requested`, `_in_run_elder_count`, multi-wand cap, locked skills. Replace assertions that reach into those APIs with the new single-wand + elder-modifier API. Where a test specifically validated multi-wand behavior, delete it (we no longer have multi-wand).

For tests that are still relevant but call the old API, rewrite to use the new API. Example:

OLD:
```gdscript
func test_minor_unlocks_first_skill() -> void:
	ss.add_minor("red")
	assert_int(ss.skill_count()).is_equal(1)
```

NEW (delete — minors no longer unlock anything; first wand comes from `start_default_wand`):
```gdscript
# Removed: minors no longer unlock skills (Phase 9 redesign).
```

- [ ] **Step 6: Run tests, verify pass**

Run full suite:
```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --continue --ignoreHeadlessMode 2>&1 | tail -3
```
Expected: 0 failures. The skill_system test suite count drops (multi-wand tests removed); new single-wand tests pass.

- [ ] **Step 7: Commit**

```
git add scripts/skills/skill_system.gd scripts/entities/player.gd test/test_skill_system.gd
git commit -m "feat(skill): single-wand model with apply_elder_modifier; remove multi-wand path"
```

---

## Phase 2b — ElderModifier infrastructure

### Task 5: ElderModifier resource type

**Files:**
- Create: `scripts/skills/elder_modifier.gd`
- Test: `test/test_elder_registry.gd` (new — tests the type via the registry in Task 6)

- [ ] **Step 1: Create the resource type**

Create `scripts/skills/elder_modifier.gd`:

```gdscript
extends RefCounted
class_name ElderModifier

# Definition of one elder modifier. The registry holds one instance per
# modifier_id; live skill state lives on Skill.elder_modifier_stacks.
#
# Hooks: subclasses or instances assign Callables to these to wire into
# damage_pipeline.gd at the appropriate event. All hooks are optional —
# unset (Callable()) means no behavior at that event.
#
# stack_count is passed to every hook so effect strength can scale with
# repeat draws (per spec: repeats compound).

var modifier_id: String
var color: String
var name: String
var description: String

# Hook signatures (all optional):
# on_hit(target: Node, damage: int, source_pos: Vector3, stack_count: int) -> void
# on_kill(target: Node, source_pos: Vector3, stack_count: int) -> void
# on_cast(caster: Node, modifier_stack: Array, base_color: String, stack_count: int) -> void
# on_player_damaged(player: Node, amount: int, stack_count: int) -> void
# damage_multiplier(target: Node, base_damage: int, stack_count: int) -> float
#   (returns the multiplier; 1.0 = no change)
var on_hit: Callable = Callable()
var on_kill: Callable = Callable()
var on_cast: Callable = Callable()
var on_player_damaged: Callable = Callable()
var damage_multiplier: Callable = Callable()

func _init(p_id: String, p_color: String, p_name: String, p_description: String) -> void:
	modifier_id = p_id
	color = p_color
	name = p_name
	description = p_description
```

- [ ] **Step 2: Commit**

```
git add scripts/skills/elder_modifier.gd
git commit -m "feat(skill): ElderModifier resource type with optional event hooks"
```

---

### Task 6: ElderRegistry autoload

**Files:**
- Create: `scripts/skills/elder_registry.gd`
- Modify: `project.godot` (register autoload)
- Test: `test/test_elder_registry.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_elder_registry.gd`:

```gdscript
extends GdUnitTestSuite

func test_get_returns_modifier_by_id() -> void:
	var m: ElderModifier = ElderRegistry.get_modifier("ignite_all_hits")
	assert_object(m).is_not_null()
	assert_str(m.color).is_equal("red")

func test_get_unknown_id_returns_null() -> void:
	assert_object(ElderRegistry.get_modifier("nonexistent_xyz")).is_null()

func test_pool_for_color_returns_only_that_color() -> void:
	var pool: Array = ElderRegistry.pool_for_color("red")
	assert_int(pool.size()).is_greater(0)
	for m in pool:
		assert_str(m.color).is_equal("red")

func test_draft_returns_three_distinct_or_pool_size() -> void:
	# Draft should return min(3, pool_size) distinct modifiers.
	var draft: Array = ElderRegistry.draft_for_color("red")
	assert_int(draft.size()).is_between(1, 3)
	# All distinct.
	var ids: Dictionary = {}
	for m in draft:
		assert_bool(ids.has(m.modifier_id)).is_false()
		ids[m.modifier_id] = true

func test_all_six_colors_have_pools() -> void:
	for color in ["red", "blue", "green", "purple", "gold", "white"]:
		var pool: Array = ElderRegistry.pool_for_color(color)
		assert_int(pool.size()).is_greater(0)
```

- [ ] **Step 2: Run test, verify it fails**

Run:
```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_elder_registry.gd --ignoreHeadlessMode
```
Expected: ElderRegistry doesn't exist.

- [ ] **Step 3: Create `scripts/skills/elder_registry.gd`**

```gdscript
extends Node
# Autoload — registry of all ElderModifier definitions, indexed by id.
# Loaded once at boot. The ElderDraft scene queries this via draft_for_color.

const ElderModifierScript = preload("res://scripts/skills/elder_modifier.gd")

var _modifiers: Dictionary = {}  # modifier_id -> ElderModifier
var _by_color: Dictionary = {}    # color -> Array[ElderModifier]

func _ready() -> void:
	_register_all()

func _register_all() -> void:
	# First batch (Phase 2 of plan): 2 modifiers per color = 12 total.
	# Follow-up plan adds the remaining 36 to reach the spec's 48.
	# Each modifier is registered with hooks wired to its behavior; behavior
	# scripts live alongside this file (e.g., elder_mod_red_ignite.gd).
	_register(ElderModRedIgniteAllHits.new())
	_register(ElderModRedCinderTrail.new())
	_register(ElderModBlueChillAllHits.new())
	_register(ElderModBlueBrittle.new())
	_register(ElderModGreenToxinAllHits.new())
	_register(ElderModGreenSporeBloom.new())
	_register(ElderModPurplePullOnHit.new())
	_register(ElderModPurpleCrushingMass.new())
	_register(ElderModGoldChainOnHit.new())
	_register(ElderModGoldOvercharge.new())
	_register(ElderModWhiteBoneShield.new())
	_register(ElderModWhiteMarrowPierce.new())

func _register(m: ElderModifier) -> void:
	_modifiers[m.modifier_id] = m
	if not _by_color.has(m.color):
		_by_color[m.color] = []
	(_by_color[m.color] as Array).append(m)

func get_modifier(modifier_id: String) -> ElderModifier:
	return _modifiers.get(modifier_id, null)

func pool_for_color(color: String) -> Array:
	return (_by_color.get(color, []) as Array).duplicate()

func draft_for_color(color: String) -> Array:
	# Return up to 3 distinct modifiers from the color's pool.
	var pool: Array = pool_for_color(color)
	pool.shuffle()
	return pool.slice(0, min(3, pool.size()))
```

The `ElderModRedIgniteAllHits` etc. classes are subclass scripts — Task 7 creates the first batch.

- [ ] **Step 4: Register as autoload in `project.godot`**

Open `project.godot`. Find the `[autoload]` section. Append:

```
ElderRegistry="*res://scripts/skills/elder_registry.gd"
```

(The `*` prefix makes it a singleton.)

- [ ] **Step 5: Test will still fail until Task 7 ships modifier subclasses. Commit infrastructure now.**

```
git add scripts/skills/elder_registry.gd test/test_elder_registry.gd project.godot
git commit -m "feat(skill): ElderRegistry autoload (skeleton; modifier classes added in next task)"
```

---

### Task 7: First batch of 12 elder modifiers (2 per color)

**Files:**
- Create: 12 new files under `scripts/skills/elder_mods/`:
  - `elder_mod_red_ignite_all_hits.gd`
  - `elder_mod_red_cinder_trail.gd`
  - `elder_mod_blue_chill_all_hits.gd`
  - `elder_mod_blue_brittle.gd`
  - `elder_mod_green_toxin_all_hits.gd`
  - `elder_mod_green_spore_bloom.gd`
  - `elder_mod_purple_pull_on_hit.gd`
  - `elder_mod_purple_crushing_mass.gd`
  - `elder_mod_gold_chain_on_hit.gd`
  - `elder_mod_gold_overcharge.gd`
  - `elder_mod_white_bone_shield.gd`
  - `elder_mod_white_marrow_pierce.gd`
- Test: `test/test_elder_modifiers_first_batch.gd`

This is a content-authoring task with 12 modifier sub-implementations. Each follows the same template: define class extending ElderModifier, set hooks. We write all 12, then run the tests once for the batch.

- [ ] **Step 1: Write the batch test**

Create `test/test_elder_modifiers_first_batch.gd`:

```gdscript
extends GdUnitTestSuite

const WelpScene: PackedScene = preload("res://scenes/entities/welp.tscn")

var welp: CharacterBody3D

func before_test() -> void:
	for w in get_tree().get_nodes_in_group("enemy"):
		w.queue_free()
	await get_tree().process_frame
	welp = auto_free(WelpScene.instantiate())
	welp.tier = "welp"
	welp.color = "red"
	add_child(welp)
	welp.global_position = Vector3.ZERO

func test_ignite_all_hits_applies_burn_on_hit() -> void:
	var m: ElderModifier = ElderRegistry.get_modifier("ignite_all_hits")
	assert_object(m).is_not_null()
	assert_object(m.on_hit).is_not_null()
	# Trigger the hook directly with stack_count=1.
	m.on_hit.call(welp, 10, Vector3.ZERO, 1)
	assert_float(welp._burn_remaining).is_greater(0.0)

func test_chill_all_hits_applies_chill_on_hit() -> void:
	var m: ElderModifier = ElderRegistry.get_modifier("chill_all_hits")
	m.on_hit.call(welp, 10, Vector3.ZERO, 1)
	assert_int(welp._chill_stacks).is_greater_equal(1)

func test_pull_on_hit_pulls_target() -> void:
	welp.global_position = Vector3(2, 0, 0)
	var m: ElderModifier = ElderRegistry.get_modifier("pull_on_hit")
	var prev_kb: Vector3 = welp._knockback_velocity
	m.on_hit.call(welp, 10, Vector3.ZERO, 1)
	assert_bool(welp._knockback_velocity != prev_kb).is_true()

func test_chain_on_hit_attempts_chain() -> void:
	# Chain modifier should signal chain budget bump; full chain integration
	# is in damage_pipeline (Task 9). Just verify the hook exists.
	var m: ElderModifier = ElderRegistry.get_modifier("chain_on_hit")
	assert_object(m).is_not_null()
	assert_object(m.on_hit).is_not_null()

func test_brittle_returns_damage_multiplier_when_target_frozen() -> void:
	welp.apply_chill(5)  # freeze threshold
	var m: ElderModifier = ElderRegistry.get_modifier("brittle")
	var mult: float = m.damage_multiplier.call(welp, 10, 1)
	assert_float(mult).is_greater(1.5)  # +100% = 2.0x

func test_crushing_mass_returns_damage_multiplier_when_pulled() -> void:
	# Crushing Mass requires a tagged "recently pulled" state on the welp.
	# For the test, manually set the tag.
	welp.set_meta("recently_pulled_until_msec", Time.get_ticks_msec() + 1000)
	var m: ElderModifier = ElderRegistry.get_modifier("crushing_mass")
	var mult: float = m.damage_multiplier.call(welp, 10, 1)
	assert_float(mult).is_greater(1.2)

func test_marrow_pierce_modifier_exists() -> void:
	# Pierce affects projectile travel; verified separately in pipeline tests.
	var m: ElderModifier = ElderRegistry.get_modifier("marrow_pierce")
	assert_object(m).is_not_null()

func test_bone_shield_player_damaged_hook_absorbs() -> void:
	var player: CharacterBody3D = auto_free(load("res://scenes/entities/player.tscn").instantiate())
	add_child(player)
	await get_tree().process_frame
	var m: ElderModifier = ElderRegistry.get_modifier("bone_shield")
	player.set_meta("bone_shield_charges", 1)
	# When charges > 0, on_player_damaged should consume a charge and bypass damage.
	# The test verifies the hook decrements charges; the damage pipeline integration
	# (Task 9) actually reads the meta to short-circuit damage.
	m.on_player_damaged.call(player, 10, 1)
	assert_int(player.get_meta("bone_shield_charges", 0)).is_equal(0)
```

- [ ] **Step 2: Run test, verify fails**

```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_elder_modifiers_first_batch.gd --ignoreHeadlessMode
```
Expected: failures because the modifier classes don't exist.

- [ ] **Step 3: Create the 12 modifier scripts**

For each modifier, create the file under `scripts/skills/elder_mods/` with the body shown. Each subclass `extends ElderModifier`. Class name comes from filename.

`scripts/skills/elder_mods/elder_mod_red_ignite_all_hits.gd`:
```gdscript
extends ElderModifier
class_name ElderModRedIgniteAllHits

func _init() -> void:
	super._init("ignite_all_hits", "red", "Ignite All Hits", "Every cast applies a 1s burn DoT. Repeats add +0.5s duration.")
	on_hit = func(target: Node, damage: int, source_pos: Vector3, stack_count: int) -> void:
		if not is_instance_valid(target):
			return
		if target.has_method("apply_burn"):
			var duration: float = 1.0 + 0.5 * float(stack_count - 1)
			# Burn DPS uses the same fraction as native red burn.
			target.apply_burn(float(damage) * 0.15, duration)
```

`scripts/skills/elder_mods/elder_mod_red_cinder_trail.gd`:
```gdscript
extends ElderModifier
class_name ElderModRedCinderTrail

# Cinder trail spawns trail nodes from player movement. Player movement code
# has to read this modifier's stack count off the active wand and emit trail
# segments. For the resource itself, on_cast just tags state on the player.
func _init() -> void:
	super._init("cinder_trail", "red", "Cinder Trail", "Moving leaves a fire trail that burns enemies. Repeats extend duration.")
	on_cast = func(caster: Node, _mod_stack: Array, _base_color: String, stack_count: int) -> void:
		if not is_instance_valid(caster):
			return
		caster.set_meta("cinder_trail_stack", stack_count)
```

`scripts/skills/elder_mods/elder_mod_blue_chill_all_hits.gd`:
```gdscript
extends ElderModifier
class_name ElderModBlueChillAllHits

func _init() -> void:
	super._init("chill_all_hits", "blue", "Chill All Hits", "Every cast applies 1 chill stack. Repeats add +1 stack per hit.")
	on_hit = func(target: Node, _damage: int, _source_pos: Vector3, stack_count: int) -> void:
		if not is_instance_valid(target):
			return
		if target.has_method("apply_chill"):
			target.apply_chill(stack_count)
```

`scripts/skills/elder_mods/elder_mod_blue_brittle.gd`:
```gdscript
extends ElderModifier
class_name ElderModBlueBrittle

# Brittle: hits against frozen enemies deal +100% damage and shatter freeze.
# Stack: +50% per copy.
func _init() -> void:
	super._init("brittle", "blue", "Brittle", "Hits against frozen enemies deal +100% damage and shatter freeze. Stack: +50%.")
	damage_multiplier = func(target: Node, _base_damage: int, stack_count: int) -> float:
		if not is_instance_valid(target):
			return 1.0
		if not target.has_method("is_frozen"):
			return 1.0
		if not target.is_frozen():
			return 1.0
		return 2.0 + 0.5 * float(stack_count - 1)
	on_hit = func(target: Node, _damage: int, _source_pos: Vector3, _stack_count: int) -> void:
		if is_instance_valid(target) and target.has_method("is_frozen") and target.is_frozen():
			# Shatter freeze.
			if "_frozen_remaining" in target:
				target._frozen_remaining = 0.0
```

`scripts/skills/elder_mods/elder_mod_green_toxin_all_hits.gd`:
```gdscript
extends ElderModifier
class_name ElderModGreenToxinAllHits

# Toxin uses the existing burn DoT plumbing tagged with a different source.
# Future: separate poison state if/when it diverges from burn semantics.
func _init() -> void:
	super._init("toxin_all_hits", "green", "Toxin All Hits", "Every cast applies a 2s poison DoT. Repeats extend duration.")
	on_hit = func(target: Node, damage: int, _source_pos: Vector3, stack_count: int) -> void:
		if not is_instance_valid(target):
			return
		if target.has_method("apply_burn"):
			var duration: float = 2.0 + 1.0 * float(stack_count - 1)
			target.apply_burn(float(damage) * 0.10, duration)
```

`scripts/skills/elder_mods/elder_mod_green_spore_bloom.gd`:
```gdscript
extends ElderModifier
class_name ElderModGreenSporeBloom

const CloudScene: PackedScene = preload("res://scenes/effects/effect_cloud.tscn")

func _init() -> void:
	super._init("spore_bloom", "green", "Spore Bloom", "Kills release a 2m poison cloud. Stack: +1m radius.")
	on_kill = func(target: Node, source_pos: Vector3, stack_count: int) -> void:
		if not is_instance_valid(target):
			return
		var radius: float = 2.0 + 1.0 * float(stack_count - 1)
		var cloud: Node3D = CloudScene.instantiate()
		var parent: Node = target.get_parent()
		if parent == null:
			return
		parent.add_child(cloud)
		cloud.global_position = source_pos
		cloud.configure(2.0, radius, 5, [], "green")
```

`scripts/skills/elder_mods/elder_mod_purple_pull_on_hit.gd`:
```gdscript
extends ElderModifier
class_name ElderModPurplePullOnHit

func _init() -> void:
	super._init("pull_on_hit", "purple", "Pull on Hit", "Every cast pulls the target 1m toward the caster. Stack: +1m.")
	on_hit = func(target: Node, _damage: int, source_pos: Vector3, stack_count: int) -> void:
		if not is_instance_valid(target):
			return
		if target.has_method("apply_pull_toward"):
			# Tag for Crushing Mass timing.
			if target.has_method("set_meta"):
				target.set_meta("recently_pulled_until_msec", Time.get_ticks_msec() + 1000)
			var impulse: float = 1.0 + 1.0 * float(stack_count - 1)
			target.apply_pull_toward(source_pos, impulse)
```

`scripts/skills/elder_mods/elder_mod_purple_crushing_mass.gd`:
```gdscript
extends ElderModifier
class_name ElderModPurpleCrushingMass

func _init() -> void:
	super._init("crushing_mass", "purple", "Crushing Mass", "Pulled enemies take +30% damage for 1s. Stack: +15%.")
	damage_multiplier = func(target: Node, _base_damage: int, stack_count: int) -> float:
		if not is_instance_valid(target):
			return 1.0
		if not target.has_meta("recently_pulled_until_msec"):
			return 1.0
		var until: int = int(target.get_meta("recently_pulled_until_msec"))
		if Time.get_ticks_msec() > until:
			return 1.0
		var bonus: float = 0.30 + 0.15 * float(stack_count - 1)
		return 1.0 + bonus
```

`scripts/skills/elder_mods/elder_mod_gold_chain_on_hit.gd`:
```gdscript
extends ElderModifier
class_name ElderModGoldChainOnHit

# The chain itself runs in damage_pipeline.gd; this modifier just tags a
# bonus chain budget. Pipeline integration in Task 9 reads
# active_skill.elder_modifier_stack_count("chain_on_hit") and adds to
# ChainState.budget.
func _init() -> void:
	super._init("chain_on_hit", "gold", "Chain on Hit", "Casts chain to 1 nearby enemy. Stack: +1 chain target.")
	on_hit = func(_target: Node, _damage: int, _source_pos: Vector3, _stack_count: int) -> void:
		# No-op here — pipeline reads stack count for budget directly.
		pass
```

`scripts/skills/elder_mods/elder_mod_gold_overcharge.gd`:
```gdscript
extends ElderModifier
class_name ElderModGoldOvercharge

# Overcharge: every Nth cast deals double damage. Cycle via player meta counter.
func _init() -> void:
	super._init("overcharge", "gold", "Overcharge", "Every 3rd cast deals double damage. Stack: every 2nd / every cast.")
	on_cast = func(caster: Node, _mod_stack: Array, _base_color: String, stack_count: int) -> void:
		if not is_instance_valid(caster):
			return
		var counter: int = int(caster.get_meta("overcharge_counter", 0)) + 1
		caster.set_meta("overcharge_counter", counter)
		var trigger_at: int = max(1, 4 - stack_count)  # stack=1 → every 3rd; stack=2 → every 2nd; stack=3+ → every cast
		if counter >= trigger_at:
			caster.set_meta("overcharge_active", true)
			caster.set_meta("overcharge_counter", 0)
		else:
			caster.set_meta("overcharge_active", false)
	damage_multiplier = func(_target: Node, _base_damage: int, _stack_count: int) -> float:
		# Pipeline reads from caster meta; multiplier hook reads target side
		# is no-op for this modifier. Pipeline integration in Task 9.
		return 1.0
```

`scripts/skills/elder_mods/elder_mod_white_bone_shield.gd`:
```gdscript
extends ElderModifier
class_name ElderModWhiteBoneShield

# Bone Shield: charges absorb the next N hits. Charges set on encounter start
# (per spec). For Phase 1 of plan, "encounter" = current run; reset on
# run_ended. Stack: +1 charge per copy.
func _init() -> void:
	super._init("bone_shield", "white", "Bone Shield", "First N hits per encounter are absorbed. Stack: +1 absorb.")
	on_player_damaged = func(player: Node, _amount: int, _stack_count: int) -> void:
		if not is_instance_valid(player):
			return
		var charges: int = int(player.get_meta("bone_shield_charges", 0))
		if charges <= 0:
			return
		player.set_meta("bone_shield_charges", charges - 1)
```

`scripts/skills/elder_mods/elder_mod_white_marrow_pierce.gd`:
```gdscript
extends ElderModifier
class_name ElderModWhiteMarrowPierce

# Pierce affects projectile travel (the projectile keeps going after hitting an
# enemy). Pipeline integration in Task 9 reads stack count off the active
# wand to set per-projectile pierce budget.
func _init() -> void:
	super._init("marrow_pierce", "white", "Marrow Pierce", "Casts pierce through 1 enemy. Stack: +1 pierce.")
	# No callable hooks; pipeline reads stack count directly.
```

- [ ] **Step 4: Run the test, verify pass**

Same command as step 2. Expected: all 8 in test_elder_modifiers_first_batch.gd PASS. test_elder_registry.gd from Task 6 also passes now.

- [ ] **Step 5: Commit**

```
git add scripts/skills/elder_mods/ test/test_elder_modifiers_first_batch.gd
git commit -m "feat(skill): first batch of 12 elder modifiers (2 per color)"
```

---

### Task 8: Hook elder modifiers into damage_pipeline

**Files:**
- Modify: `scripts/skills/damage_pipeline.gd` (apply hooks per event)
- Test: `test/test_elder_modifiers_first_batch.gd` (add integration tests)

The pipeline currently has color-based layer dispatch. Add a parallel dispatch for elder modifiers that runs through the active wand's `elder_modifier_stacks` and invokes the registry's hooks.

- [ ] **Step 1: Add integration test**

Append to `test/test_elder_modifiers_first_batch.gd`:

```gdscript
func test_ignite_all_hits_via_pipeline() -> void:
	# Set up: a player with active red wand carrying ignite_all_hits.
	var player: CharacterBody3D = auto_free(load("res://scenes/entities/player.tscn").instantiate())
	add_child(player)
	await get_tree().process_frame
	var ss: SkillSystem = player.get_node("SkillSystem")
	ss.start_default_wand("red")
	ss.apply_elder_modifier("ignite_all_hits")
	# Drive a damage event through the pipeline.
	var enemy: CharacterBody3D = auto_free(WelpScene.instantiate())
	enemy.tier = "welp"
	enemy.color = "red"
	add_child(enemy)
	enemy.global_position = Vector3.ZERO
	await get_tree().process_frame
	const DamagePipeline = preload("res://scripts/skills/damage_pipeline.gd")
	DamagePipeline.apply(enemy, 10, ["red"], "red", Vector3.ZERO, "test_cast", null, ss)
	# Burn from native red layer + ignite_all_hits.
	assert_float(enemy._burn_remaining).is_greater(0.0)

func test_chain_on_hit_increases_budget() -> void:
	var player: CharacterBody3D = auto_free(load("res://scenes/entities/player.tscn").instantiate())
	add_child(player)
	await get_tree().process_frame
	var ss: SkillSystem = player.get_node("SkillSystem")
	ss.start_default_wand("gold")
	ss.apply_elder_modifier("chain_on_hit")
	# Spawn 3 enemies in a line; expect chain to hit at least 1 extra past the primary.
	var primary: CharacterBody3D = auto_free(WelpScene.instantiate())
	primary.tier = "welp"
	primary.color = "gold"
	add_child(primary)
	primary.global_position = Vector3.ZERO
	var secondary: CharacterBody3D = auto_free(WelpScene.instantiate())
	secondary.tier = "welp"
	secondary.color = "gold"
	add_child(secondary)
	secondary.global_position = Vector3(2, 0, 0)
	await get_tree().process_frame
	const DamagePipeline = preload("res://scripts/skills/damage_pipeline.gd")
	var initial_secondary_hp: int = secondary.hp
	DamagePipeline.apply(primary, 10, ["gold"], "gold", Vector3.ZERO, "test_cast", null, ss)
	# Secondary should be hit by chain.
	assert_int(secondary.hp).is_less(initial_secondary_hp)
```

- [ ] **Step 2: Run test, verify fails**

Same command as Task 7 step 2. Expected: tests fail because pipeline doesn't take a SkillSystem argument and doesn't dispatch elder modifiers yet.

- [ ] **Step 3: Modify `scripts/skills/damage_pipeline.gd`**

Update the `apply` static signature to accept optional `skill_system`. Add elder modifier dispatch.

Replace the `apply` function (line 30 onward) with:

```gdscript
static func apply(target: Node, damage: int, modifier_stack: Array, base_color: String, source_pos: Vector3, source_tag: String = "", chain_state: ChainState = null, skill_system: Node = null) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not target.has_method("take_damage"):
		return

	# Apply elder modifier damage_multiplier hooks before computing final damage.
	var effective_damage: int = damage
	if skill_system != null and skill_system.has_method("active_skill"):
		var active: Skill = skill_system.active_skill()
		if active != null:
			for modifier_id in active.elder_modifier_stacks.keys():
				var em: ElderModifier = ElderRegistry.get_modifier(modifier_id)
				if em == null or em.damage_multiplier.is_null():
					continue
				var stack: int = active.elder_modifier_stack_count(modifier_id)
				var mult: float = em.damage_multiplier.call(target, effective_damage, stack)
				effective_damage = int(float(effective_damage) * mult)

	if chain_state == null:
		chain_state = ChainState.new()
		chain_state.budget = _count(modifier_stack, "gold")
		# Add elder chain modifier budget on top.
		if skill_system != null and skill_system.has_method("active_skill"):
			var active2: Skill = skill_system.active_skill()
			if active2 != null and active2.has_elder_modifier("chain_on_hit"):
				chain_state.budget += active2.elder_modifier_stack_count("chain_on_hit")

	var meter_tag: String = source_tag if source_tag != "" else base_color
	if chain_state.hit_set.size() > 0:
		meter_tag = meter_tag + "+chain"

	var hp_before: int = -1
	if "hp" in target:
		hp_before = int(target.get("hp"))
	if target.has_method("take_damage_with_source"):
		target.take_damage_with_source(effective_damage, meter_tag)
	else:
		target.take_damage(effective_damage)
	var actual: int = effective_damage
	if hp_before >= 0 and "hp" in target:
		actual = max(0, hp_before - int(target.get("hp")))
	DamageMeter.record(target, effective_damage, actual, meter_tag)

	if target.has_method("flash_hit"):
		target.flash_hit()
	ScreenShake.shake(0.02, 0.04)
	chain_state.hit_set[target.get_instance_id()] = true

	# Apply elder modifier on_hit hooks (post-damage, but pre-kill check below).
	if skill_system != null and skill_system.has_method("active_skill"):
		var active3: Skill = skill_system.active_skill()
		if active3 != null:
			for modifier_id in active3.elder_modifier_stacks.keys():
				var em2: ElderModifier = ElderRegistry.get_modifier(modifier_id)
				if em2 == null or em2.on_hit.is_null():
					continue
				var stack2: int = active3.elder_modifier_stack_count(modifier_id)
				em2.on_hit.call(target, effective_damage, source_pos, stack2)

	# Burn (red, native + modifier counts) — unchanged from prior.
	var red_modifier_count: int = _count(modifier_stack, "red")
	var burn_base: float = 3.0 if base_color == "red" else 0.0
	var burn_bonus: float = 5.0 * (1.0 - pow(0.6, red_modifier_count))
	var total_burn_duration: float = burn_base + burn_bonus
	if total_burn_duration > 0.0 and target.has_method("apply_burn"):
		target.apply_burn(float(effective_damage) * BURN_DPS_FRAC, total_burn_duration)

	_apply_native_layer(target, base_color, effective_damage, source_pos)
	for color in modifier_stack:
		_apply_modifier_layer(target, color, effective_damage, source_pos)

	# Apply elder on_kill hooks if the target died from this hit.
	var target_dead: bool = false
	if "_is_dead" in target:
		target_dead = bool(target.get("_is_dead"))
	elif "hp" in target:
		target_dead = int(target.get("hp")) <= 0
	if target_dead and skill_system != null and skill_system.has_method("active_skill"):
		var active4: Skill = skill_system.active_skill()
		if active4 != null:
			for modifier_id in active4.elder_modifier_stacks.keys():
				var em3: ElderModifier = ElderRegistry.get_modifier(modifier_id)
				if em3 == null or em3.on_kill.is_null():
					continue
				var stack3: int = active4.elder_modifier_stack_count(modifier_id)
				em3.on_kill.call(target, source_pos, stack3)

	if chain_state.budget > 0:
		var next: Node = _find_chain_target(target, chain_state.hit_set, CHAIN_RANGE)
		if next != null:
			chain_state.budget -= 1
			apply(next, effective_damage, modifier_stack, base_color, source_pos, source_tag, chain_state, skill_system)
```

- [ ] **Step 4: Update callers to pass `skill_system`**

Find callers of `DamagePipeline.apply` that have a `_skill_system` reference and update them. Likely callers: `cast_base.gd`, `effect_cloud.gd`, `effect_breath_cone.gd`. Pass the player's skill system where the cast originated. For boss-side damage applications (mark zone, breath cone hitting player), the boss has no SkillSystem so pass `null`.

Run a search to find all callers:
```bash
grep -rn "DamagePipeline.apply" scripts/
```

For each call site, locate the caster's SkillSystem reference and pass it as the new optional 8th argument. If the caster is the boss, pass `null` (boss doesn't have elder modifiers; this is player-side only). Specifically:
- `scripts/skills/cast_base.gd` — caster is the player; pass `_caster._skill_system`.
- `scripts/effects/effect_cloud.gd` — caster could be either; pass `null` for now since clouds outlive their cast.
- Other call sites: pass `null` if caster is boss-side; pass player skill system if player-side.

- [ ] **Step 5: Run tests, verify pass**

Same command as Task 7 step 2. Expected: integration tests pass.

- [ ] **Step 6: Commit**

```
git add scripts/skills/damage_pipeline.gd scripts/skills/cast_base.gd scripts/effects/ test/test_elder_modifiers_first_batch.gd
git commit -m "feat(damage): wire elder modifier hooks into damage pipeline"
```

---

## Phase 2c — ElderDraft UI flow

### Task 9: ElderDraft scene

**Files:**
- Create: `scenes/ui/elder_draft.tscn` (CanvasLayer scene with 3 card buttons)
- Create: `scripts/ui/elder_draft.gd` (controller)
- Modify: `scripts/interactables/soul_pickup.gd:_on_body_entered` (trigger draft on elder pickup)
- Test: `test/test_elder_draft.gd`

- [ ] **Step 1: Write the test**

Create `test/test_elder_draft.gd`:

```gdscript
extends GdUnitTestSuite

const DraftScene: PackedScene = preload("res://scenes/ui/elder_draft.tscn")

var draft: CanvasLayer
var player: CharacterBody3D

func before_test() -> void:
	player = auto_free(load("res://scenes/entities/player.tscn").instantiate())
	add_child(player)
	await get_tree().process_frame
	player.get_node("SkillSystem").start_default_wand("red")
	draft = auto_free(DraftScene.instantiate())
	add_child(draft)
	await get_tree().process_frame

func test_show_draft_displays_three_cards_for_red() -> void:
	draft.show_draft("red", player.get_node("SkillSystem"))
	await get_tree().process_frame
	var cards: int = draft.get_visible_card_count()
	assert_int(cards).is_between(1, 3)

func test_picking_card_applies_to_active_wand() -> void:
	var ss: SkillSystem = player.get_node("SkillSystem")
	draft.show_draft("red", ss)
	await get_tree().process_frame
	# Click the first card.
	draft.pick_card(0)
	await get_tree().process_frame
	assert_int(ss.active_skill().elder_modifier_count()).is_equal(1)
	assert_bool(draft.visible).is_false()

func test_draft_pauses_physics_while_visible() -> void:
	draft.show_draft("blue", player.get_node("SkillSystem"))
	await get_tree().process_frame
	assert_bool(get_tree().paused).is_true()
	draft.pick_card(0)
	await get_tree().process_frame
	assert_bool(get_tree().paused).is_false()
```

- [ ] **Step 2: Run test, verify it fails**

```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_elder_draft.gd --ignoreHeadlessMode
```
Expected: scene doesn't exist.

- [ ] **Step 3: Create `scripts/ui/elder_draft.gd`**

```gdscript
extends CanvasLayer

# Modal scene shown on elder pickup. Pauses physics, displays up to 3 cards
# from the elder's color pool, applies the chosen modifier to the active wand,
# resumes.
#
# Process mode: ALWAYS (so the scene can run while tree is paused).

signal picked(modifier_id: String)

var _draft: Array = []
var _skill_system: Node = null
var _color: String = ""

@onready var _card_container: HBoxContainer = $Center/Panel/VBox/Cards
@onready var _title: Label = $Center/Panel/VBox/Title

const CARD_TEMPLATE: PackedScene = preload("res://scenes/ui/elder_draft_card.tscn")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func show_draft(color: String, skill_system: Node) -> void:
	_color = color
	_skill_system = skill_system
	_draft = ElderRegistry.draft_for_color(color)
	_render_cards()
	_title.text = "%s Elder — pick a modifier" % color.capitalize()
	visible = true
	get_tree().paused = true

func _render_cards() -> void:
	for c in _card_container.get_children():
		c.queue_free()
	for i in range(_draft.size()):
		var card: Button = CARD_TEMPLATE.instantiate()
		var m: ElderModifier = _draft[i]
		var stack_note: String = ""
		if _skill_system != null and _skill_system.active_skill() != null:
			var existing: int = _skill_system.active_skill().elder_modifier_stack_count(m.modifier_id)
			if existing > 0:
				stack_note = "\n(already on wand: stack will become %d)" % (existing + 1)
		card.text = "%s\n\n%s%s" % [m.name, m.description, stack_note]
		var idx: int = i  # capture by value for callable
		card.pressed.connect(func(): pick_card(idx))
		_card_container.add_child(card)

func pick_card(index: int) -> void:
	if index < 0 or index >= _draft.size():
		return
	if _skill_system == null:
		return
	var m: ElderModifier = _draft[index]
	_skill_system.apply_elder_modifier(m.modifier_id)
	visible = false
	get_tree().paused = false
	picked.emit(m.modifier_id)

func get_visible_card_count() -> int:
	return _draft.size()
```

- [ ] **Step 4: Create scene files**

Create `scenes/ui/elder_draft_card.tscn`:

A simple Button scene with multi-line text support. Build via Godot editor or write the .tscn file directly:

```
[gd_scene format=3]

[node name="ElderDraftCard" type="Button"]
custom_minimum_size = Vector2(220, 200)
text = ""
autowrap_mode = 2
```

Create `scenes/ui/elder_draft.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/elder_draft.gd" id="1_draft"]

[node name="ElderDraft" type="CanvasLayer"]
script = ExtResource("1_draft")

[node name="Center" type="CenterContainer" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0

[node name="Panel" type="Panel" parent="Center"]
custom_minimum_size = Vector2(720, 360)

[node name="VBox" type="VBoxContainer" parent="Center/Panel"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0

[node name="Title" type="Label" parent="Center/Panel/VBox"]
text = "Elder — pick a modifier"
horizontal_alignment = 1

[node name="Cards" type="HBoxContainer" parent="Center/Panel/VBox"]
size_flags_vertical = 3
alignment = 1
```

- [ ] **Step 5: Wire elder pickup to ElderDraft**

In `scripts/interactables/soul_pickup.gd`, modify `_on_body_entered`:

```gdscript
const ElderDraftScene: PackedScene = preload("res://scenes/ui/elder_draft.tscn")

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	SoulEconomy.add_to_carry(color, tier, 1)
	# Phase 9: elder pickups also trigger an in-run modifier draft.
	if tier == "elder" and body.has_node("SkillSystem"):
		var draft: CanvasLayer = ElderDraftScene.instantiate()
		# Add at root so the modal layer is above all gameplay UI.
		body.get_tree().root.add_child(draft)
		draft.show_draft(color, body.get_node("SkillSystem"))
	queue_free()
```

- [ ] **Step 6: Run tests, verify pass**

Same command as step 2. Expected: 3 PASSED.

- [ ] **Step 7: Commit**

```
git add scripts/ui/elder_draft.gd scripts/interactables/soul_pickup.gd scenes/ui/elder_draft.tscn scenes/ui/elder_draft_card.tscn test/test_elder_draft.gd
git commit -m "feat(ui): ElderDraft modal scene + soul_pickup wiring"
```

---

## Phase 3 — Meta shop + migration

### Task 10: MetaShop autoload

**Files:**
- Create: `scripts/core/meta_shop.gd`
- Modify: `project.godot` (register autoload, before MetaProgress in load order)
- Test: `test/test_meta_shop.gd`

- [ ] **Step 1: Write the test**

Create `test/test_meta_shop.gd`:

```gdscript
extends GdUnitTestSuite

func before_test() -> void:
	MetaShop.reset_for_test()

func test_starts_with_zero_currency() -> void:
	assert_int(MetaShop.minor_souls()).is_equal(0)
	assert_int(MetaShop.elder_currency()).is_equal(0)

func test_credit_minor_souls_adds() -> void:
	MetaShop.credit_minor_souls(15)
	assert_int(MetaShop.minor_souls()).is_equal(15)

func test_credit_elder_currency_adds() -> void:
	MetaShop.credit_elder_currency(3)
	assert_int(MetaShop.elder_currency()).is_equal(3)

func test_buy_stat_rank_consumes_minor_souls() -> void:
	MetaShop.credit_minor_souls(20)
	var ok: bool = MetaShop.buy_stat_rank("vitality")
	assert_bool(ok).is_true()
	assert_int(MetaShop.stat_rank("vitality")).is_equal(1)
	# Rank 1 cost is 5; remaining = 15.
	assert_int(MetaShop.minor_souls()).is_equal(15)

func test_buy_stat_rank_fails_when_insufficient_currency() -> void:
	MetaShop.credit_minor_souls(2)  # not enough for rank 1 (cost 5)
	var ok: bool = MetaShop.buy_stat_rank("vitality")
	assert_bool(ok).is_false()
	assert_int(MetaShop.stat_rank("vitality")).is_equal(0)

func test_buy_stat_rank_caps_at_5() -> void:
	MetaShop.credit_minor_souls(10000)
	for i in range(5):
		MetaShop.buy_stat_rank("vitality")
	# 6th attempt should fail.
	var ok: bool = MetaShop.buy_stat_rank("vitality")
	assert_bool(ok).is_false()
	assert_int(MetaShop.stat_rank("vitality")).is_equal(5)

func test_buy_structural_unlock_consumes_elder_currency() -> void:
	MetaShop.credit_elder_currency(10)
	var ok: bool = MetaShop.buy_structural("wand_choice")
	assert_bool(ok).is_true()
	assert_bool(MetaShop.has_structural("wand_choice")).is_true()
	# Wand Choice cost: 3.
	assert_int(MetaShop.elder_currency()).is_equal(7)

func test_buy_structural_unlock_fails_when_already_owned() -> void:
	MetaShop.credit_elder_currency(20)
	MetaShop.buy_structural("wand_choice")
	var ok: bool = MetaShop.buy_structural("wand_choice")
	assert_bool(ok).is_false()

func test_starting_wand_color_default_red() -> void:
	# Without Wand Choice unlocked, always red.
	assert_str(MetaShop.starting_wand_color()).is_equal("red")

func test_starting_wand_color_after_unlock() -> void:
	MetaShop.credit_elder_currency(10)
	MetaShop.buy_structural("wand_choice")
	MetaShop.set_chosen_wand_color("blue")
	assert_str(MetaShop.starting_wand_color()).is_equal("blue")
```

- [ ] **Step 2: Run test, verify fails**

```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_meta_shop.gd --ignoreHeadlessMode
```
Expected: MetaShop autoload doesn't exist.

- [ ] **Step 3: Create `scripts/core/meta_shop.gd`**

```gdscript
extends Node
# Autoload — meta-progression currency + purchase state.
# Replaces the auto-unlock paths in meta_progress.gd. Player drives spend.
#
# Two currency types:
#   - minor_souls: dropped by dragons, earned over many runs, used for stat ranks.
#   - elder_currency: dropped by elder pickups, used for structural unlocks.

const STAT_KEYS: Array[String] = ["vitality", "power", "cast_speed", "pyre_cap", "soul_magnetism"]
const STAT_MAX_RANK: int = 5
const STAT_RANK_COSTS: Array[int] = [5, 15, 50, 150, 400]

# Per-stat per-rank effect (rank_index 0..4 → effect at rank 1..5).
const STAT_VALUES: Dictionary = {
	"vitality": [0.10, 0.20, 0.35, 0.50, 0.75],
	"power": [0.05, 0.10, 0.20, 0.35, 0.50],
	"cast_speed": [0.05, 0.10, 0.15, 0.20, 0.25],
	"pyre_cap": [25, 50, 100, 175, 250],
	"soul_magnetism": [1, 2, 4, 6, 10],
}

const STRUCTURAL_COSTS: Dictionary = {
	"wand_choice": 3,
	"second_modifier_slot": 5,
	"pyre_expansion_1": 3,
	"pyre_expansion_2": 4,
	"pyre_expansion_3": 5,
	"pyre_expansion_4": 6,
	"pyre_expansion_5": 7,
	"replenish_on_descent": 4,
	"elder_sense": 2,
	"modifier_reroll": 6,
	"build_carry": 8,
	"hard_mode": 5,
	"daily_seed": 3,
	"frost_dragon": 7,
	"cinder_dragon": 7,
}

var _minor_souls: int = 0
var _elder_currency: int = 0
var _stat_ranks: Dictionary = {}  # stat_key -> rank (0..5)
var _structural_owned: Dictionary = {}  # unlock_id -> true
var _chosen_wand_color: String = "red"

func _ready() -> void:
	for k in STAT_KEYS:
		_stat_ranks[k] = 0

func reset_for_test() -> void:
	_minor_souls = 0
	_elder_currency = 0
	_stat_ranks.clear()
	for k in STAT_KEYS:
		_stat_ranks[k] = 0
	_structural_owned.clear()
	_chosen_wand_color = "red"

func minor_souls() -> int:
	return _minor_souls

func elder_currency() -> int:
	return _elder_currency

func credit_minor_souls(n: int) -> void:
	_minor_souls += n

func credit_elder_currency(n: int) -> void:
	_elder_currency += n

func stat_rank(key: String) -> int:
	return int(_stat_ranks.get(key, 0))

func stat_value(key: String) -> float:
	var rank: int = stat_rank(key)
	if rank == 0:
		return 0.0
	var values: Array = STAT_VALUES.get(key, [])
	if values.size() < rank:
		return 0.0
	return float(values[rank - 1])

func buy_stat_rank(key: String) -> bool:
	if not (key in STAT_KEYS):
		return false
	var rank: int = stat_rank(key)
	if rank >= STAT_MAX_RANK:
		return false
	var cost: int = STAT_RANK_COSTS[rank]
	if _minor_souls < cost:
		return false
	_minor_souls -= cost
	_stat_ranks[key] = rank + 1
	return true

func has_structural(unlock_id: String) -> bool:
	return _structural_owned.has(unlock_id)

func buy_structural(unlock_id: String) -> bool:
	if not STRUCTURAL_COSTS.has(unlock_id):
		return false
	if has_structural(unlock_id):
		return false
	var cost: int = int(STRUCTURAL_COSTS[unlock_id])
	if _elder_currency < cost:
		return false
	_elder_currency -= cost
	_structural_owned[unlock_id] = true
	return true

func set_chosen_wand_color(color: String) -> void:
	_chosen_wand_color = color

func starting_wand_color() -> String:
	if has_structural("wand_choice"):
		return _chosen_wand_color
	return "red"

func to_dict() -> Dictionary:
	return {
		"minor_souls": _minor_souls,
		"elder_currency": _elder_currency,
		"stat_ranks": _stat_ranks.duplicate(),
		"structural_owned": _structural_owned.duplicate(),
		"chosen_wand_color": _chosen_wand_color,
	}

func from_dict(d: Dictionary) -> void:
	_minor_souls = int(d.get("minor_souls", 0))
	_elder_currency = int(d.get("elder_currency", 0))
	var ranks: Dictionary = d.get("stat_ranks", {})
	for k in STAT_KEYS:
		_stat_ranks[k] = int(ranks.get(k, 0))
	_structural_owned.clear()
	for k in d.get("structural_owned", {}).keys():
		_structural_owned[k] = true
	_chosen_wand_color = String(d.get("chosen_wand_color", "red"))
```

- [ ] **Step 4: Register autoload in `project.godot`**

Add to `[autoload]` section, ABOVE `MetaProgress` (so MetaProgress can reference MetaShop during migration in Task 12):

```
MetaShop="*res://scripts/core/meta_shop.gd"
```

- [ ] **Step 5: Run test, verify pass**

Same command as step 2. Expected: 10 PASSED.

- [ ] **Step 6: Commit**

```
git add scripts/core/meta_shop.gd test/test_meta_shop.gd project.godot
git commit -m "feat(meta): MetaShop autoload — currency + stat rank + structural unlock state"
```

---

### Task 11: Wire deposit → MetaShop credit

**Files:**
- Modify: `scripts/core/soul_economy.gd:deposit_to_pyres` (also credit MetaShop)
- Test: integration test in `test/test_soul_economy.gd`

- [ ] **Step 1: Write the failing test**

Append to `test/test_soul_economy.gd`:

```gdscript
func test_deposit_credits_minor_souls_to_meta_shop() -> void:
	MetaShop.reset_for_test()
	SoulEconomy.add_to_carry("red", "minor", 5)
	SoulEconomy.add_to_carry("blue", "minor", 3)
	SoulEconomy.deposit_to_pyres()
	assert_int(MetaShop.minor_souls()).is_equal(8)

func test_deposit_credits_elder_currency_to_meta_shop() -> void:
	MetaShop.reset_for_test()
	SoulEconomy.add_to_carry("purple", "elder", 2)
	SoulEconomy.deposit_to_pyres()
	assert_int(MetaShop.elder_currency()).is_equal(2)
```

- [ ] **Step 2: Run, verify fails**

Same command pattern; expected fail because `deposit_to_pyres` doesn't credit MetaShop.

- [ ] **Step 3: Modify `scripts/core/soul_economy.gd:deposit_to_pyres`**

Replace the function body with:

```gdscript
func deposit_to_pyres() -> void:
	# Phase 9: also credits MetaShop currency. Pyre fill state is preserved
	# for visual displays; MetaShop is the canonical currency store.
	var minor_total: int = 0
	var elder_total: int = 0
	for color in COLORS:
		var fill_units: int = (
			_carry[color]["minor"] * SOUL_VALUES["minor"]
			+ _carry[color]["elder"] * SOUL_VALUES["elder"]
		)
		if fill_units == 0:
			continue
		var old_fill: int = _pyres[color]
		var new_fill: int = min(_pyres[color] + fill_units, PYRE_CAP)
		var was_full: bool = _filled_pyres[color]
		_pyres[color] = new_fill
		if new_fill != old_fill:
			pyre_fill_changed.emit(color, new_fill)
		if new_fill >= PYRE_CAP and not was_full:
			_filled_pyres[color] = true
			pyre_filled.emit(color)
		minor_total += _carry[color]["minor"]
		elder_total += _carry[color]["elder"]
	if minor_total > 0:
		MetaShop.credit_minor_souls(minor_total)
	if elder_total > 0:
		MetaShop.credit_elder_currency(elder_total)
	clear_carry()
```

- [ ] **Step 4: Run tests, verify pass**

Same command. Expected: deposit tests pass; existing tests still pass.

- [ ] **Step 5: Commit**

```
git add scripts/core/soul_economy.gd test/test_soul_economy.gd
git commit -m "feat(meta): deposit credits MetaShop currency in addition to pyre fills"
```

---

### Task 12: MetaProgress migration to MetaShop

**Files:**
- Modify: `scripts/core/meta_progress.gd` (add migrate_to_meta_shop, remove auto-unlock paths)
- Test: `test/test_meta_shop_migration.gd`

- [ ] **Step 1: Write the test**

Create `test/test_meta_shop_migration.gd`:

```gdscript
extends GdUnitTestSuite

func before_test() -> void:
	MetaShop.reset_for_test()
	MetaProgress.reset_meta()

func test_cantrips_migrate_to_stat_ranks() -> void:
	MetaProgress._cantrips["max_hp"] = 3
	MetaProgress._cantrips["sword_damage"] = 2
	MetaProgress._cantrips["dash_cooldown"] = 1
	MetaProgress.migrate_to_meta_shop()
	assert_int(MetaShop.stat_rank("vitality")).is_equal(3)
	assert_int(MetaShop.stat_rank("power")).is_equal(2)
	assert_int(MetaShop.stat_rank("cast_speed")).is_equal(1)
	assert_int(MetaShop.stat_rank("pyre_cap")).is_equal(0)
	assert_int(MetaShop.stat_rank("soul_magnetism")).is_equal(0)

func test_hub_features_migrate_to_structural_purchases() -> void:
	MetaProgress._hub_features_unlocked = 2
	MetaProgress.migrate_to_meta_shop()
	assert_bool(MetaShop.has_structural("wand_choice")).is_true()
	assert_bool(MetaShop.has_structural("second_modifier_slot")).is_true()
	assert_bool(MetaShop.has_structural("pyre_expansion_1")).is_false()

func test_pyre_fills_credit_minor_souls() -> void:
	# Pyre fills today represent banked progress; in the new system they
	# convert 1:1 to minor souls.
	SoulEconomy.set_pyre_fill("red", 30)
	SoulEconomy.set_pyre_fill("blue", 20)
	MetaProgress.migrate_to_meta_shop()
	assert_int(MetaShop.minor_souls()).is_equal(50)

func test_migration_idempotent() -> void:
	# Calling twice doesn't double-credit.
	MetaProgress._cantrips["max_hp"] = 3
	MetaProgress.migrate_to_meta_shop()
	MetaProgress.migrate_to_meta_shop()
	assert_int(MetaShop.stat_rank("vitality")).is_equal(3)
```

- [ ] **Step 2: Run test, verify fails**

Standard test command.

- [ ] **Step 3: Modify `scripts/core/meta_progress.gd`**

Add the migration method. Disconnect the auto-unlock signal handler so pyre fills no longer trigger auto-unlock features:

In `_ready`, comment out or remove:
```gdscript
SoulEconomy.pyre_fill_changed.connect(_on_pyre_fill_changed)
```
(Replace with: `# Phase 9: pyre_fill_changed → auto-unlock removed; MetaShop is now the canonical purchase state.`)

Add at the bottom of the file:

```gdscript
# --- Phase 9 migration ---

var _migrated: bool = false

func migrate_to_meta_shop() -> void:
	if _migrated:
		return
	# Cantrips → stat ranks (1:1 by index).
	MetaShop._stat_ranks["vitality"] = int(_cantrips.get("max_hp", 0))
	MetaShop._stat_ranks["power"] = int(_cantrips.get("sword_damage", 0))
	MetaShop._stat_ranks["cast_speed"] = int(_cantrips.get("dash_cooldown", 0))
	# Hub features → mechanic-branch purchases (in fixed order).
	var hub_unlock_order: Array = [
		"wand_choice",
		"second_modifier_slot",
		"pyre_expansion_1",
		"replenish_on_descent",
	]
	for i in range(_hub_features_unlocked):
		if i < hub_unlock_order.size():
			MetaShop._structural_owned[hub_unlock_order[i]] = true
	# Pyre fills → minor souls (1:1).
	var fill_total: int = 0
	for color in SoulEconomy.COLORS:
		fill_total += SoulEconomy.pyre_fill(color)
	if fill_total > 0:
		MetaShop.credit_minor_souls(fill_total)
		# Reset fills so visual pyres start fresh against new accumulation.
		for color in SoulEconomy.COLORS:
			SoulEconomy.set_pyre_fill(color, 0)
	_migrated = true
```

- [ ] **Step 4: Trigger migration on game start**

In `scripts/core/game_state.gd`, add to `_ready` (or wherever first init runs):

```gdscript
func _ready() -> void:
	# ... existing init ...
	MetaProgress.migrate_to_meta_shop()
```

(If a `_ready` doesn't exist, create one.)

- [ ] **Step 5: Run tests, verify pass**

Standard command. Expected: migration tests + full suite pass.

- [ ] **Step 6: Commit**

```
git add scripts/core/meta_progress.gd scripts/core/game_state.gd test/test_meta_shop_migration.gd
git commit -m "feat(meta): migrate MetaProgress state into MetaShop on first load"
```

---

### Task 13: Apply MetaShop stat values to gameplay

**Files:**
- Modify: `scripts/entities/player.gd:_ready` (read MetaShop stat values for HP, etc.)
- Modify: `scripts/interactables/soul_pickup.gd` (read magnetism stat)
- Modify: `scripts/core/soul_economy.gd` (read pyre cap stat)

- [ ] **Step 1: Add player HP scaling test**

Append to `test/test_meta_shop.gd`:

```gdscript
func test_vitality_rank_scales_player_hp() -> void:
	MetaShop.reset_for_test()
	MetaShop.credit_minor_souls(10000)
	for i in range(3):
		MetaShop.buy_stat_rank("vitality")
	# Stat value at rank 3 = 0.35.
	var player: CharacterBody3D = auto_free(load("res://scenes/entities/player.tscn").instantiate())
	add_child(player)
	await get_tree().process_frame
	# Base 100 * 1.35 = 135.
	assert_int(player.max_hp).is_equal(135)
```

- [ ] **Step 2: Run test, verify fails**

Standard command.

- [ ] **Step 3: Update `scripts/entities/player.gd:_ready`**

Replace the cantrip lines (around line 38-40):

```gdscript
	# OLD:
	# max_hp += MetaProgress.cantrip_bonus("max_hp")
	# dash_cooldown = max(0.2, dash_cooldown + MetaProgress.cantrip_bonus_float("dash_cooldown"))
	# NEW (Phase 9):
	max_hp = int(float(max_hp) * (1.0 + MetaShop.stat_value("vitality")))
	hp = max_hp
	dash_cooldown = max(0.2, dash_cooldown * (1.0 - MetaShop.stat_value("cast_speed")))
```

(Keep `hp = max_hp` line — it already exists; just confirm it follows the max_hp update.)

- [ ] **Step 4: Update `soul_pickup.gd` to use Soul Magnetism**

Replace the magnetism constant block:

```gdscript
const VACUUM_RANGE_BASE: float = 4.0

func _vacuum_range() -> float:
	return VACUUM_RANGE_BASE + MetaShop.stat_value("soul_magnetism")
```

Update `_process` to call `_vacuum_range()` instead of `VACUUM_RANGE`.

- [ ] **Step 5: Update `soul_economy.gd:PYRE_CAP` to read from MetaShop**

Replace:
```gdscript
static var PYRE_CAP: int = PYRE_CAP_TEST if Debug.FAST_TEST else PYRE_CAP_SHIP
```

with a function:
```gdscript
const PYRE_CAP_TEST: int = 10
const PYRE_CAP_SHIP: int = 100

static func get_pyre_cap() -> int:
	var base: int = PYRE_CAP_TEST if Debug.FAST_TEST else PYRE_CAP_SHIP
	return base + int(MetaShop.stat_value("pyre_cap"))
```

Replace all references to `PYRE_CAP` (constant access) with `get_pyre_cap()` calls. Also update test references in `test_soul_economy.gd` if any.

- [ ] **Step 6: Run tests, verify pass**

Standard full-suite command. Some tests in `test_soul_economy.gd` that referenced `PYRE_CAP` may need updating.

- [ ] **Step 7: Commit**

```
git add scripts/entities/player.gd scripts/interactables/soul_pickup.gd scripts/core/soul_economy.gd test/
git commit -m "feat(meta): apply MetaShop stat values to player HP, dash, magnetism, pyre cap"
```

---

### Task 14: Remove dead code from SkillSystem and MetaProgress

**Files:**
- Modify: `scripts/skills/skill_system.gd` (already removed in Task 4 — confirm)
- Modify: `scripts/core/meta_progress.gd` (remove `_in_run_elder_count`, `active_skill_cap_bonus` callers, `color_damage_bonus` if no readers remain)
- Modify: `scripts/core/escalation.gd` (remove `set_in_run_elder_count` if no other callers)

- [ ] **Step 1: Audit unused references**

Search for callers:
```
grep -rn "active_skill_cap_bonus\|color_damage_bonus\|in_run_elder_count\|on_pyre_milestone\|on_pyre_full" scripts/ test/
```

For each match, decide:
- Test that asserts on dead code → delete the test.
- Production caller of dead method → replace with the new equivalent or delete.
- Method definition itself → delete.

- [ ] **Step 2: Remove the dead methods from `meta_progress.gd`**

Delete:
- `unlock_next_hub_feature`
- `on_pyre_milestone`
- `on_pyre_full`
- `active_skill_cap_bonus`
- `color_damage_bonus`
- `_on_pyre_fill_changed` (already disconnected in Task 12)

Keep `_cantrips` field for save-data backward compatibility (read by migration in Task 12). Mark as deprecated:

```gdscript
# Phase 9: this field is read by migrate_to_meta_shop() and otherwise unused.
# Save data still loads cantrip levels into here; migration moves them to
# MetaShop.stat_ranks. Don't add new readers.
var _cantrips: Dictionary = {}
```

- [ ] **Step 3: Run tests, verify pass**

Standard command. Some tests in `test_skill_system.gd` and `test_meta_progress.gd` may need to be deleted (those that asserted on deleted methods).

- [ ] **Step 4: Commit**

```
git add scripts/core/meta_progress.gd scripts/core/escalation.gd test/
git commit -m "chore(meta): remove dead auto-unlock + multi-wand code paths"
```

---

### Task 15: Final integration verification

**Files:**
- Test: existing test suite

- [ ] **Step 1: Run full test suite**

```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --continue --ignoreHeadlessMode 2>&1 | tail -5
```

Expected: 0 errors, 0 failures. Test count drops from 302 → ~280 (multi-wand tests removed) plus rises with new tests added.

- [ ] **Step 2: Sanity-check the playtest path**

In Godot editor, launch the game from `scenes/world/courtyard.tscn`. Verify:
- Whelps die, drop nothing.
- Dragons die, drop minor pickups (count 1-2).
- Elder welps die, drop a single elder pickup; touching it banks to carry AND opens the ElderDraft modal.
- Picking a card adds the modifier to the active wand (visible in DamageMeter post-fight if you've wired UI; otherwise check via debug print).
- Descending banks carry → MetaShop credits.
- Returning to main_hall: visit the future MetaShop UI scene (defer if scene not built; otherwise verify currency is reflected).

(If the MetaShop UI scene isn't yet built — that's a follow-up plan task. Just verify the autoload state is correct via debug prints.)

- [ ] **Step 3: Commit if any tweaks were needed**

```
git status  # check for any incidental fixes
git add -p  # review staged changes
git commit -m "chore: final integration verification + minor fixes"
```

---

## Self-review checklist

After implementing, verify:

- [ ] All 15 tasks committed individually.
- [ ] Full test suite passes: 0 errors, 0 failures.
- [ ] No `add_minor` / `add_elder` (old API) callers remain in the codebase: `grep -rn "add_minor\|add_elder" scripts/`.
- [ ] Whelp drop policy spot-checked in editor playtest.
- [ ] Elder pickup → ElderDraft modal flow works end-to-end.
- [ ] Descent banks both currency types into MetaShop.
- [ ] Migration test verifies old saves convert correctly.

## Out of scope for this plan

- Remaining 36 elder modifiers (follow-up plan: pool expansion).
- MetaShop UI scene (the autoload state is correct; UI scene + scene wiring is a focused follow-up).
- Spec subsystem B (spawn cadence + elder personalities) — separate spec.
- Spec subsystem C (boss cone geometry + green/purple stacking cheese) — separate spec.

---

## Self-review pass log

**Spec coverage:**
- Drop policy (§1.1): Task 1 ✓
- Pickup decoupling (§1.2): Task 2 ✓
- SkillSystem rework (§1.3): Tasks 3, 4 ✓
- ElderDraft (§1.4): Task 9 ✓
- MetaShop autoload (§1.5): Task 10 ✓
- Default starting wand (§1.3): Task 4 step 4 ✓
- Pyre semantics (Locked decisions): Task 11 ✓ (deposit credits MetaShop; pyres remain visual)
- Migration (§3c): Task 12 ✓
- Stat application to gameplay: Task 13 ✓
- Dead code removal (§1.6): Task 14 ✓
- Elder modifier infrastructure (§2): Tasks 5, 6, 7, 8 ✓
- Out-of-scope items declared in spec §7: handled by `## Out of scope for this plan` ✓

**Placeholder scan:** none found. All steps include code, exact paths, and run commands.

**Type consistency:** `apply_elder_modifier(modifier_id)` signature consistent across Skill, SkillSystem, ElderDraft, and tests. `damage_pipeline.apply()` consistently takes optional `skill_system` 8th arg.
