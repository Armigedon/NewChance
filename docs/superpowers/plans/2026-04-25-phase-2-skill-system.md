# Phase 2 — Skill System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Implement the soul-stacking skill system: first soul unlocks Skill 1, minor souls add elemental modifiers, elder souls unlock new skills, manual switching, replace-prompt at cap, sword element inheritance. Add a second dragon color (Blue) so modifier stacking is observable.

**Architecture:** A `SkillSystem` node attached to the Player owns the active skill list (max = active_skill_cap, hardcoded 3 in Phase 2; cap growth via pyre milestones is Phase 4). Skills are runtime-only (cleared on run_ended); they do not persist between runs. Each skill has a `base_color` (cast shape) and a `modifier_stack` (list of elemental modifiers applied to the cast). Casts are PackedScene-instanced spell projectiles; the modifier_stack is passed to the cast at instantiation and modulates damage, on-hit effects, and visual tint.

**Tech Stack:** Godot 4.6.2, GDScript, GdUnit4. Same as Phase 1.

**Spec reference:** [`docs/superpowers/specs/2026-04-25-new-chance-design.md`](../specs/2026-04-25-new-chance-design.md) §3 (Combat & soul system).

**Phase 2 scope (vs full skill spec):**
- ✅ Skill data model + SkillSystem service with unit tests
- ✅ 2 cast types: Red Fireball, Blue Ice Line
- ✅ Minor soul → elemental modifier stacking (math + on-hit)
- ✅ Elder soul → new skill (with replace-prompt at cap)
- ✅ Manual switch via 1/2/3 keys
- ✅ Manual cast on left-click (with cursor aim)
- ✅ Sword element inheritance (visual tint by active skill base color)
- ✅ End-of-run skill clear (hooks `GameState.run_ended`)
- ✅ Blue welp variant (drops blue minor souls)
- ❌ Active skill cap GROWS via pyre milestones (Phase 4 — hardcoded 3 here)
- ❌ Other 4 colors: Green, Purple, Gold, White (Phase 3)
- ❌ Full elder dragon tier with proper drop scaling (Phase 3 — Phase 2 ships welps only with simulated elder soul drops via debug spawn or rare welp variant)
- ❌ Cooldown polish, animation timing (Phase 6)

**Acceptance test:** Player walks upstairs, kills welps, picks up red minor souls (first one unlocks Fireball as Skill 1, sword glows red). Picks up more red minors → fireball gets stronger. Picks up a blue minor → fireball now also applies chill on hit (test by killing a welp with multi-color stack). Spawn a Blue welp; pick up its blue elder (test debug spawn) → Skill 2 unlocks (Ice Spike Line, base blue), prior Fireball locks. Press 1 to switch back to fire skill — sword glows red again, casts fireball (locked at its accumulated state). Press 2 to switch to ice. Pick up a third elder → cap reached → replace prompt asks which to discard. Decline → soul converts to 3 minors. Die or descend → all skills clear.

---

## File structure

**Created in this phase:**

```
scenes/
├── entities/
│   └── welp_blue.tscn               # New: blue welp variant
├── interactables/
│   └── soul_pickup_blue.tscn        # New: blue soul pickup
└── skills/
    ├── cast_red_fireball.tscn       # Red base shape: aimed projectile
    └── cast_blue_ice_line.tscn      # Blue base shape: piercing line
scripts/
├── entities/
│   └── (welp.gd refactored to be color-parameterized)
├── interactables/
│   └── (soul_pickup.gd refactored to be color-parameterized)
└── skills/
    ├── skill.gd                      # Skill data class (Resource)
    ├── skill_system.gd               # Per-player service: active skills, switch, replace
    ├── cast_base.gd                  # Base class for cast projectiles/instances
    ├── cast_red_fireball.gd
    └── cast_blue_ice_line.gd
scripts/ui/
└── replace_skill_prompt.gd           # Modal at active skill cap
scenes/ui/
└── replace_skill_prompt.tscn
test/
├── test_skill.gd                     # Skill data class behavior
└── test_skill_system.gd              # SkillSystem state machine
```

**Modified:**
- `scripts/entities/player.gd` — add SkillSystem child, manual cast input, skill switch input, sword element inheritance
- `scripts/entities/sword.gd` — accept active_element from SkillSystem, tint mesh
- `scripts/world/welp_spawner.gd` — spawn red OR blue welps (50/50 random in Phase 2 for testing)
- `project.godot` — add input actions: `cast` (left-click), `switch_skill_1` (key 1), `switch_skill_2` (key 2), `switch_skill_3` (key 3)
- `scenes/world/upstairs.tscn` — add ReplaceSkillPrompt instance

---

## Task 1: Skill data class

**Files:**
- Create: `scripts/skills/skill.gd`
- Create: `test/test_skill.gd`

- [ ] **Step 1: Write failing test**

Create `test/test_skill.gd`:

```gdscript
extends GdUnitTestSuite

const SkillScript = preload("res://scripts/skills/skill.gd")

func test_skill_starts_with_no_modifiers() -> void:
	var s := SkillScript.new("red")
	assert_that(s.base_color).is_equal("red")
	assert_that(s.modifier_stack).is_empty()
	assert_that(s.locked).is_false()

func test_skill_add_modifier_appends() -> void:
	var s := SkillScript.new("red")
	s.add_modifier("blue")
	s.add_modifier("green")
	assert_that(s.modifier_stack).is_equal(["blue", "green"])

func test_skill_add_modifier_when_locked_does_nothing() -> void:
	var s := SkillScript.new("red")
	s.locked = true
	s.add_modifier("blue")
	assert_that(s.modifier_stack).is_empty()

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
```

- [ ] **Step 2: Run tests — verify failures**

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_skill.gd --ignoreHeadlessMode
```

- [ ] **Step 3: Implement Skill class**

Create `scripts/skills/skill.gd`:

```gdscript
extends RefCounted
class_name Skill

var base_color: String
var modifier_stack: Array[String] = []  # color names of minor souls added since this became active
var locked: bool = false

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
```

Use tabs.

- [ ] **Step 4: Run tests — verify pass**

Same command from Step 2. Expected: 5/5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/skills/skill.gd test/test_skill.gd
git commit -m "feat(skill): Skill data class with modifier stack + lock"
```

---

## Task 2: SkillSystem service

**Files:**
- Create: `scripts/skills/skill_system.gd`
- Create: `test/test_skill_system.gd`

- [ ] **Step 1: Write failing tests**

Create `test/test_skill_system.gd`:

```gdscript
extends GdUnitTestSuite

const SkillSystemScript = preload("res://scripts/skills/skill_system.gd")
const SkillScript = preload("res://scripts/skills/skill.gd")

var ss: Node

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
	ss.add_minor("red")  # first soul, unlocks
	ss.add_minor("blue")
	ss.add_minor("green")
	var active: Skill = ss.active_skill()
	assert_that(active.modifier_stack).is_equal(["blue", "green"])

func test_elder_soul_unlocks_new_skill_locks_prior() -> void:
	ss.add_minor("red")
	ss.add_minor("blue")  # red skill now has [blue]
	var add_result := ss.add_elder("green")
	assert_that(add_result).is_equal(SkillSystemScript.AddResult.UNLOCKED)
	assert_that(ss.skill_count()).is_equal(2)
	# Active is now the new green skill
	assert_that(ss.active_skill().base_color).is_equal("green")
	# Prior red skill is locked
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

func test_minor_soul_after_switch_modifies_switched_skill() -> void:
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
	ss.add_elder("green")  # 3 skills now
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
	# New skill is unlocked, others remain locked
	assert_that(ss.skill_at(0).locked).is_false()

func test_decline_elder_converts_to_3_minors() -> void:
	ss.set_cap(3)
	ss.add_minor("red")  # red active
	ss.add_elder("blue")  # blue active (red locked)
	ss.add_elder("green")  # green active (blue locked)
	# Now decline an elder; should add 3 minors of declined color to ACTIVE skill
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
```

- [ ] **Step 2: Run tests — verify failures (script doesn't exist)**

- [ ] **Step 3: Implement SkillSystem**

Create `scripts/skills/skill_system.gd`:

```gdscript
extends Node
class_name SkillSystem

const SkillScript = preload("res://scripts/skills/skill.gd")

enum AddResult { UNLOCKED, AT_CAP, MODIFIED, NOOP }

signal active_skill_changed(new_index: int)
signal skill_unlocked(index: int)
signal at_cap_replace_prompt_requested(incoming_color: String)

var _skills: Array[Skill] = []
var _active_index: int = -1
var _cap: int = 3

func set_cap(n: int) -> void:
	_cap = n

func cap() -> int:
	return _cap

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
	# First soul unlocks Skill 1 with this color as base.
	if _skills.is_empty():
		var first := SkillScript.new(color) as Skill
		_skills.append(first)
		_active_index = 0
		skill_unlocked.emit(0)
		active_skill_changed.emit(0)
		return AddResult.UNLOCKED
	# Else: modify the active skill (no-op if active is locked).
	var active: Skill = active_skill()
	if active == null:
		return AddResult.NOOP
	if active.locked:
		return AddResult.NOOP
	active.add_modifier(color)
	return AddResult.MODIFIED

func add_elder(color: String) -> int:
	if _skills.size() >= _cap:
		at_cap_replace_prompt_requested.emit(color)
		return AddResult.AT_CAP
	# Lock prior active
	if _active_index >= 0:
		_skills[_active_index].locked = true
	# Add new skill, make it active
	var new_skill := SkillScript.new(color) as Skill
	_skills.append(new_skill)
	_active_index = _skills.size() - 1
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
	# Per spec: declined elder converts to 3 minor souls of its color, applied to active skill.
	if _active_index < 0:
		return
	for i in range(3):
		add_minor(declined_color)

func clear() -> void:
	_skills.clear()
	_active_index = -1
	active_skill_changed.emit(-1)
```

- [ ] **Step 4: Run tests — verify all pass**

- [ ] **Step 5: Commit**

```bash
git add scripts/skills/skill_system.gd test/test_skill_system.gd
git commit -m "feat(skill-system): per-player service with stacking, switching, replace-prompt"
```

---

## Task 3: Replace-skill prompt UI

**Files:**
- Create: `scenes/ui/replace_skill_prompt.tscn`
- Create: `scripts/ui/replace_skill_prompt.gd`

- [ ] **Step 1: Implement script**

Create `scripts/ui/replace_skill_prompt.gd`:

```gdscript
extends CanvasLayer

signal replace_chosen(index: int)
signal declined

@onready var _summary: Label = $Center/Panel/VBox/Summary
@onready var _btn_replace_0: Button = $Center/Panel/VBox/Buttons/Replace0
@onready var _btn_replace_1: Button = $Center/Panel/VBox/Buttons/Replace1
@onready var _btn_replace_2: Button = $Center/Panel/VBox/Buttons/Replace2
@onready var _btn_decline: Button = $Center/Panel/VBox/Buttons/Decline

var _incoming_color: String = ""

func _ready() -> void:
	visible = false
	_btn_replace_0.pressed.connect(func(): _on_replace(0))
	_btn_replace_1.pressed.connect(func(): _on_replace(1))
	_btn_replace_2.pressed.connect(func(): _on_replace(2))
	_btn_decline.pressed.connect(_on_decline)

func show_prompt(skill_system: SkillSystem, incoming_color: String) -> void:
	_incoming_color = incoming_color
	_summary.text = (
		"You picked up an Elder %s soul, but you're at the skill cap.\n" % incoming_color
		+ "Replace which skill, or decline (converts to 3 minor souls)?"
	)
	# Update button labels with current skill colors
	for i in range(3):
		var skill: Skill = skill_system.skill_at(i)
		var btn: Button = [_btn_replace_0, _btn_replace_1, _btn_replace_2][i]
		if skill != null:
			btn.text = "Replace [%d] %s" % [i + 1, skill.base_color.capitalize()]
			btn.disabled = false
		else:
			btn.disabled = true
	visible = true
	get_tree().paused = true

func hide_prompt() -> void:
	visible = false
	get_tree().paused = false

func _on_replace(index: int) -> void:
	hide_prompt()
	replace_chosen.emit(index)

func _on_decline() -> void:
	hide_prompt()
	declined.emit()
```

- [ ] **Step 2: Build scene as text**

Create `scenes/ui/replace_skill_prompt.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/replace_skill_prompt.gd" id="1_replace"]

[node name="ReplaceSkillPrompt" type="CanvasLayer"]
process_mode = 3
script = ExtResource("1_replace")

[node name="Center" type="CenterContainer" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0

[node name="Panel" type="PanelContainer" parent="Center"]
layout_mode = 2

[node name="VBox" type="VBoxContainer" parent="Center/Panel"]
layout_mode = 2
theme_override_constants/separation = 12

[node name="Summary" type="Label" parent="Center/Panel/VBox"]
layout_mode = 2
text = "Replace prompt"
autowrap_mode = 2

[node name="Buttons" type="VBoxContainer" parent="Center/Panel/VBox"]
layout_mode = 2
theme_override_constants/separation = 8

[node name="Replace0" type="Button" parent="Center/Panel/VBox/Buttons"]
layout_mode = 2
text = "Replace [1]"

[node name="Replace1" type="Button" parent="Center/Panel/VBox/Buttons"]
layout_mode = 2
text = "Replace [2]"

[node name="Replace2" type="Button" parent="Center/Panel/VBox/Buttons"]
layout_mode = 2
text = "Replace [3]"

[node name="Decline" type="Button" parent="Center/Panel/VBox/Buttons"]
layout_mode = 2
text = "Decline (3 minor souls)"
```

- [ ] **Step 3: Verify import + commit**

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . --import 2>&1 | grep -i error | head -5
git add scripts/ui/replace_skill_prompt.gd scenes/ui/replace_skill_prompt.tscn
git commit -m "feat(replace-prompt): UI modal for elder-soul-at-cap decision"
```

---

## Task 4: Cast base + cast input action

**Files:**
- Create: `scripts/skills/cast_base.gd`
- Modify: `project.godot` (add `cast` input action and `switch_skill_1/2/3` actions)

- [ ] **Step 1: Add input actions to project.godot**

Append to existing `[input]` section in `project.godot`:

```ini
cast={
"deadzone": 0.5,
"events": [Object(InputEventMouseButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"position":Vector2(0, 0),"global_position":Vector2(0, 0),"factor":1.0,"button_index":1,"canceled":false,"button_mask":0,"double_click":false,"script":null)
]
}
switch_skill_1={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":49,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
switch_skill_2={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":50,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
switch_skill_3={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":51,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

(physical_keycode: 1=49, 2=50, 3=51, mouse left button=button_index 1)

- [ ] **Step 2: Implement cast base**

Create `scripts/skills/cast_base.gd`:

```gdscript
extends Node3D
class_name CastBase

# Defaults — overridden per-cast
@export var base_damage: int = 25
@export var lifetime: float = 3.0

var modifier_stack: Array[String] = []
var _age: float = 0.0

func configure(skill: Skill) -> void:
	# Called by SkillSystem at instantiation. Sets damage scaling and modifier list.
	modifier_stack = skill.modifier_stack.duplicate()
	# Same-color minor souls deepen base damage by 30% per stack
	var same_color_count: int = skill.modifier_count_for(skill.base_color)
	base_damage = int(base_damage * (1.0 + 0.3 * same_color_count))

func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()

func _on_hit_enemy(enemy: Node) -> void:
	if not enemy.has_method("take_damage"):
		return
	enemy.take_damage(base_damage)
	# Apply elemental modifiers
	for color in modifier_stack:
		_apply_modifier(enemy, color)

func _apply_modifier(enemy: Node, color: String) -> void:
	# Stub: in Phase 2, modifiers do nothing visible beyond damage. The infrastructure
	# is here for Phase 3's full elemental effects (burn, freeze, slow, etc).
	# For now, each modifier adds 10% damage as a placeholder.
	if enemy.has_method("take_damage"):
		enemy.take_damage(int(base_damage * 0.1))
```

- [ ] **Step 3: Commit**

```bash
git add scripts/skills/cast_base.gd project.godot
git commit -m "feat(cast): base class + cast/switch_skill input actions"
```

---

## Task 5: Red Fireball cast

**Files:**
- Create: `scripts/skills/cast_red_fireball.gd`
- Create: `scenes/skills/cast_red_fireball.tscn`

- [ ] **Step 1: Implement script**

Create `scripts/skills/cast_red_fireball.gd`:

```gdscript
extends CastBase

const PROJECTILE_SPEED: float = 12.0

@export var direction: Vector3 = Vector3.FORWARD

func _ready() -> void:
	# Connect Area3D body_entered for hit detection
	var area: Area3D = $HitArea
	area.body_entered.connect(_on_body_entered)
	area.monitoring = true

func _physics_process(delta: float) -> void:
	global_position += direction.normalized() * PROJECTILE_SPEED * delta

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemy"):
		_on_hit_enemy(body)
		queue_free()
```

Note: this is the script for the projectile root. The cast's HitArea Area3D is added in the .tscn.

- [ ] **Step 2: Build scene**

Create `scenes/skills/cast_red_fireball.tscn`:

```
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://scripts/skills/cast_red_fireball.gd" id="1_fireball"]

[sub_resource type="SphereShape3D" id="SphereShape3D_fireball"]
radius = 0.4

[sub_resource type="SphereMesh" id="SphereMesh_fireball"]
radius = 0.3
height = 0.6

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_fireball"]
albedo_color = Color(1, 0.4, 0.1, 1)
emission_enabled = true
emission = Color(1, 0.5, 0.1, 1)
emission_energy_multiplier = 4.0

[node name="CastRedFireball" type="Node3D"]
script = ExtResource("1_fireball")

[node name="HitArea" type="Area3D" parent="."]
collision_layer = 0
collision_mask = 2

[node name="CollisionShape3D" type="CollisionShape3D" parent="HitArea"]
shape = SubResource("SphereShape3D_fireball")

[node name="Mesh" type="MeshInstance3D" parent="."]
mesh = SubResource("SphereMesh_fireball")
material_override = SubResource("StandardMaterial3D_fireball")
```

- [ ] **Step 3: Commit**

```bash
git add scripts/skills/cast_red_fireball.gd scenes/skills/cast_red_fireball.tscn
git commit -m "feat(cast): red fireball — aimed projectile with AoE on impact"
```

---

## Task 6: Blue Ice Line cast

**Files:**
- Create: `scripts/skills/cast_blue_ice_line.gd`
- Create: `scenes/skills/cast_blue_ice_line.tscn`

- [ ] **Step 1: Implement script**

Create `scripts/skills/cast_blue_ice_line.gd`:

```gdscript
extends CastBase

const PROJECTILE_SPEED: float = 18.0

@export var direction: Vector3 = Vector3.FORWARD

var _hit_enemies: Array[Node] = []

func _ready() -> void:
	var area: Area3D = $HitArea
	area.body_entered.connect(_on_body_entered)
	area.monitoring = true

func _physics_process(delta: float) -> void:
	global_position += direction.normalized() * PROJECTILE_SPEED * delta

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemy") and not (body in _hit_enemies):
		_hit_enemies.append(body)
		_on_hit_enemy(body)
		# Pierces through — does NOT queue_free on hit (let lifetime expire)
```

- [ ] **Step 2: Build scene**

Create `scenes/skills/cast_blue_ice_line.tscn`:

```
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://scripts/skills/cast_blue_ice_line.gd" id="1_iceline"]

[sub_resource type="BoxShape3D" id="BoxShape3D_iceline"]
size = Vector3(0.4, 0.4, 2.0)

[sub_resource type="BoxMesh" id="BoxMesh_iceline"]
size = Vector3(0.3, 0.3, 1.8)

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_iceline"]
albedo_color = Color(0.6, 0.8, 1, 1)
emission_enabled = true
emission = Color(0.6, 0.85, 1, 1)
emission_energy_multiplier = 3.5

[node name="CastBlueIceLine" type="Node3D"]
script = ExtResource("1_iceline")

[node name="HitArea" type="Area3D" parent="."]
collision_layer = 0
collision_mask = 2

[node name="CollisionShape3D" type="CollisionShape3D" parent="HitArea"]
shape = SubResource("BoxShape3D_iceline")

[node name="Mesh" type="MeshInstance3D" parent="."]
mesh = SubResource("BoxMesh_iceline")
material_override = SubResource("StandardMaterial3D_iceline")
```

- [ ] **Step 3: Commit**

```bash
git add scripts/skills/cast_blue_ice_line.gd scenes/skills/cast_blue_ice_line.tscn
git commit -m "feat(cast): blue ice line — piercing line projectile"
```

---

## Task 7: Player integration — SkillSystem + cast input + skill switch

**Files:**
- Modify: `scripts/entities/player.gd`
- Modify: `scenes/entities/player.tscn` (add SkillSystem child node)

- [ ] **Step 1: Add SkillSystem child to player.tscn**

Read the current `scenes/entities/player.tscn`. Append a SkillSystem child node and the script ext_resource.

Bump load_steps from 8 to 9. Add to ext_resources:

```
[ext_resource type="Script" path="res://scripts/skills/skill_system.gd" id="3_skillsys"]
```

Add as child of Player root (place before the Sword node):

```
[node name="SkillSystem" type="Node" parent="."]
script = ExtResource("3_skillsys")
```

- [ ] **Step 2: Add cast/switch input handlers + cast scene preload to player.gd**

Read current `scripts/entities/player.gd`. Add at the top after existing constants:

```gdscript
const CAST_RED_FIREBALL: PackedScene = preload("res://scenes/skills/cast_red_fireball.tscn")
const CAST_BLUE_ICE_LINE: PackedScene = preload("res://scenes/skills/cast_blue_ice_line.tscn")
const CAST_COOLDOWN: float = 0.6  # seconds between casts (Phase 6 will refine per-color)

@export var cast_cooldown: float = CAST_COOLDOWN

@onready var _skill_system: SkillSystem = $SkillSystem

var _cast_cooldown_remaining: float = 0.0
```

In `_process(delta)`, add at the top:

```gdscript
if _cast_cooldown_remaining > 0.0:
	_cast_cooldown_remaining = max(0.0, _cast_cooldown_remaining - delta)
```

After the dash input check, add cast + switch input:

```gdscript
if Input.is_action_just_pressed("cast"):
	_try_cast()
if Input.is_action_just_pressed("switch_skill_1"):
	_skill_system.switch_active(0)
if Input.is_action_just_pressed("switch_skill_2"):
	_skill_system.switch_active(1)
if Input.is_action_just_pressed("switch_skill_3"):
	_skill_system.switch_active(2)
```

Add `_try_cast`:

```gdscript
func _try_cast() -> void:
	if _cast_cooldown_remaining > 0.0:
		return
	var skill: Skill = _skill_system.active_skill()
	if skill == null:
		return
	var cast_scene: PackedScene = _scene_for_color(skill.base_color)
	if cast_scene == null:
		return
	var cast = cast_scene.instantiate()
	cast.configure(skill)
	# Aim direction: toward mouse cursor on the floor plane
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		cast.direction = Vector3.FORWARD
	else:
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		var ray_origin: Vector3 = cam.project_ray_origin(mouse_pos)
		var ray_dir: Vector3 = cam.project_ray_normal(mouse_pos)
		# Project ray onto y=1 plane (player height)
		var t: float = (1.0 - ray_origin.y) / ray_dir.y
		var hit_point: Vector3 = ray_origin + ray_dir * t
		var to_target: Vector3 = hit_point - global_position
		to_target.y = 0.0
		cast.direction = to_target.normalized() if to_target.length() > 0.01 else Vector3.FORWARD
	cast.global_position = global_position + cast.direction * 1.0 + Vector3(0, 0.5, 0)
	get_parent().add_child(cast)
	_cast_cooldown_remaining = cast_cooldown

func _scene_for_color(color: String) -> PackedScene:
	match color:
		"red": return CAST_RED_FIREBALL
		"blue": return CAST_BLUE_ICE_LINE
		_: return null
```

- [ ] **Step 3: Verify scene + run tests**

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . --import 2>&1 | grep -i error | head -10
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
```

Expected: no errors, all tests pass (Skill + SkillSystem tests will be the new ones; existing 41 still pass).

- [ ] **Step 4: Commit**

```bash
git add scripts/entities/player.gd scenes/entities/player.tscn
git commit -m "feat(player): integrate SkillSystem, cast input, skill switch hotkeys"
```

---

## Task 8: Sword element inheritance

**Files:**
- Modify: `scripts/entities/sword.gd`
- Modify: `scenes/entities/player.tscn` (wire signal)

- [ ] **Step 1: Update sword.gd to react to active_element**

Read `scripts/entities/sword.gd`. Add at the bottom:

```gdscript
@onready var _blade_mesh: MeshInstance3D = $Blade if has_node("Blade") else null

const COLOR_TINTS: Dictionary = {
	"": Color(0.55, 0.5, 0.42, 1),  # default rusty
	"red": Color(1, 0.3, 0.1, 1),
	"blue": Color(0.4, 0.7, 1, 1),
}

func set_active_element(color: String) -> void:
	if _blade_mesh == null:
		return
	var mat: StandardMaterial3D = _blade_mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	var tint: Color = COLOR_TINTS.get(color, COLOR_TINTS[""])
	mat.albedo_color = tint
	mat.emission_enabled = (color != "")
	mat.emission = tint
	mat.emission_energy_multiplier = 2.0 if color != "" else 0.0
```

- [ ] **Step 2: Hook player's SkillSystem signal to sword**

In player.gd `_ready` (add if not present, or merge with existing):

```gdscript
func _ready() -> void:
	_skill_system.active_skill_changed.connect(_on_active_skill_changed)

func _on_active_skill_changed(_index: int) -> void:
	var element: String = _skill_system.active_element()
	$Sword.set_active_element(element)
```

Also subscribe to GameState.run_ended to clear skills when run ends:

```gdscript
	GameState.run_ended.connect(_on_run_ended)

func _on_run_ended(_outcome: int) -> void:
	_skill_system.clear()
	$Sword.set_active_element("")
```

- [ ] **Step 3: Verify + commit**

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
git add scripts/entities/sword.gd scripts/entities/player.gd
git commit -m "feat(sword): inherit active skill element + clear on run_ended"
```

---

## Task 9: Replace-prompt wiring

**Files:**
- Modify: `scenes/world/upstairs.tscn` (instance ReplaceSkillPrompt)
- Modify: `scripts/entities/player.gd` (connect at_cap signal)

- [ ] **Step 1: Add ReplaceSkillPrompt to upstairs scene**

Read `scenes/world/upstairs.tscn`. Add ext_resource for the new prompt scene, bump load_steps, add as child of Upstairs root:

Add ext_resource:
```
[ext_resource type="PackedScene" path="res://scenes/ui/replace_skill_prompt.tscn" id="7_replace"]
```

Add child node:
```
[node name="ReplaceSkillPrompt" parent="." instance=ExtResource("7_replace")]
```

Bump load_steps appropriately (current is 13; should become 14).

- [ ] **Step 2: Wire player → SkillSystem at-cap signal → prompt**

In `scripts/entities/player.gd` `_ready`, add:

```gdscript
	_skill_system.at_cap_replace_prompt_requested.connect(_on_at_cap)

func _on_at_cap(incoming_color: String) -> void:
	var prompt = get_tree().root.find_child("ReplaceSkillPrompt", true, false)
	if prompt == null:
		return
	if not prompt.replace_chosen.is_connected(_on_replace_chosen):
		prompt.replace_chosen.connect(_on_replace_chosen.bind(incoming_color))
		prompt.declined.connect(_on_replace_declined.bind(incoming_color))
	prompt.show_prompt(_skill_system, incoming_color)

func _on_replace_chosen(index: int, incoming_color: String) -> void:
	_skill_system.replace_at(index, incoming_color)

func _on_replace_declined(incoming_color: String) -> void:
	_skill_system.decline_elder(incoming_color)
```

(Note: `bind` is used to pass the incoming_color into the handler, since the signal itself only carries the index.)

- [ ] **Step 3: Verify + commit**

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . --import 2>&1 | grep -i error | head -5
git add scenes/world/upstairs.tscn scripts/entities/player.gd
git commit -m "feat(player): wire replace-prompt for at-cap elder soul handling"
```

---

## Task 10: Blue welp variant + soul_pickup color parameterization

**Files:**
- Modify: `scripts/entities/welp.gd` (already has @export color — verify it drops the right pickup)
- Modify: `scripts/interactables/soul_pickup.gd` (already has @export color — verify color tints visual)
- Create: `scenes/entities/welp_blue.tscn`
- Create: `scenes/interactables/soul_pickup_blue.tscn`
- Modify: `scripts/world/welp_spawner.gd` (50/50 random spawn red vs blue)

- [ ] **Step 1: Verify welp.gd pickup spawn uses self.color**

Read `scripts/entities/welp.gd` and confirm `take_damage` death branch sets `pickup.color = color`. Already done in Phase 1. No change.

- [ ] **Step 2: Make soul_pickup color-aware**

Read `scripts/interactables/soul_pickup.gd`. Modify `_ready` to set the visual based on color:

```gdscript
const TINTS: Dictionary = {
	"red": Color(1, 0.4, 0.2, 1),
	"blue": Color(0.4, 0.7, 1, 1),
}

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	# Recolor mesh based on color export
	var mesh: MeshInstance3D = $Mesh if has_node("Mesh") else null
	if mesh != null:
		var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D
		if mat != null:
			var tint: Color = TINTS.get(color, TINTS["red"])
			mat.albedo_color = tint
			mat.emission = tint
```

This way the existing soul_pickup.tscn handles BOTH red and blue at runtime. No need for a separate blue scene.

- [ ] **Step 3: Create welp_blue.tscn (variant scene with color="blue")**

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/entities/welp.gd" id="1_welp"]

[sub_resource type="BoxShape3D" id="BoxShape3D_welp"]
size = Vector3(0.7, 0.7, 0.7)

[sub_resource type="BoxMesh" id="BoxMesh_welp"]
size = Vector3(0.7, 0.7, 0.7)

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_welp_blue"]
albedo_color = Color(0.2, 0.4, 0.85, 1)

[node name="Welp" type="CharacterBody3D"]
script = ExtResource("1_welp")
color = "blue"

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
shape = SubResource("BoxShape3D_welp")

[node name="Mesh" type="MeshInstance3D" parent="."]
mesh = SubResource("BoxMesh_welp")
material_override = SubResource("StandardMaterial3D_welp_blue")
```

- [ ] **Step 4: Update welp_spawner to spawn 50/50 red/blue**

Read `scripts/world/welp_spawner.gd`. Add:

```gdscript
const WELP_BLUE_SCENE: PackedScene = preload("res://scenes/entities/welp_blue.tscn")
```

Modify `_spawn_welp`:

```gdscript
func _spawn_welp() -> void:
	var scene: PackedScene = WELP_SCENE if randf() < 0.5 else WELP_BLUE_SCENE
	var welp: CharacterBody3D = scene.instantiate()
	var angle: float = randf() * TAU
	var offset: Vector3 = Vector3(cos(angle) * spawn_radius, 1.0, sin(angle) * spawn_radius)
	welp.global_position = global_position + offset
	welp.died.connect(_on_welp_died)
	get_parent().add_child(welp)
	_alive_count += 1
```

- [ ] **Step 5: Verify + commit**

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . --import 2>&1 | grep -i error | head -5
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
git add scripts/interactables/soul_pickup.gd scenes/entities/welp_blue.tscn scripts/world/welp_spawner.gd
git commit -m "feat(welp): blue variant + color-aware soul pickup tint + 50/50 spawn"
```

---

## Task 11: Acceptance playtest (USER ACTION)

After all 10 implementation tasks, the user runs the game. Acceptance:

- [ ] Game starts in main hall
- [ ] Walk upstairs
- [ ] Welps spawn (red AND blue)
- [ ] Kill a red welp → red soul pickup → walk into it → SkillSystem unlocks Skill 1 (red Fireball), sword tints red
- [ ] Left-click → fireball flies toward cursor, kills welps on hit
- [ ] Kill a blue welp → blue soul pickup → adds blue modifier to active skill (red Fireball with blue mod)
- [ ] Press 1 / 2 / 3 to switch skills (only 1 active in current state)
- [ ] **Manually testing elder souls in Phase 2:** since elder dragons aren't in Phase 2, modify `welp_spawner.gd` temporarily to drop an elder soul on every Nth welp death — OR add a debug input action that spawns an elder pickup at the player's position. (User can ask for this if needed.)
- [ ] Die or descend → skills clear, sword tint resets to default
- [ ] All unit tests pass

If anything fails, file as follow-up.

- [ ] **Step 1: User confirms playtest pass**

(Manual step.)

- [ ] **Step 2: Tag**

```bash
git tag -a v0.2-skill-system -m "Phase 2: skill stacking, manual cast, replace-prompt, sword inheritance, blue welps. All Phase 1 + Phase 2 tests pass."
```

---

## Phase 2 → Phase 3 handoff notes

What Phase 2 leaves for Phase 3:
- Active skill cap is hardcoded 3 — Phase 4 will tie it to pyre milestones.
- Modifiers visually do nothing distinctive on cast (just damage scaling) — Phase 6 polish adds particles, on-hit effects.
- Only red + blue casts implemented — Phase 3 adds green, purple, gold, white casts.
- No corner-heat mechanic — Phase 3 adds upstairs heat per corner.
- No proper elder dragon enemy — Phase 3 adds 3 tiers (welp/dragon/elder) with proper drop scaling.
- No proper modifier effects (burn, freeze, slow) — placeholders only. Phase 6 polish adds the real effects.

Phase 3 plan starts when Phase 2 ships and an acceptance playtest validates the skill loop.
