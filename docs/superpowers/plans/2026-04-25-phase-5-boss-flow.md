# Phase 5 — Boss Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal:** Implement the full end-game boss flow. Filling all 6 primary pyres triggers a cutscene where the necromancer drains the flames and transforms into the black dragon. The fight happens in a new courtyard scene with a 3-phase HP-threshold dragon that summons black whelps. Death during the fight clears in-run state and locks the courtyard; retry requires depositing 1 elder soul via the existing descent prompt's "Descend & fight" option. Victory dissolves the dragon, returns flames to pyres, and reveals a hidden basement staircase. The upstairs is shadow-warded during boss flow.

**Architecture:**
- New `BossFlow` autoload tracks boss state machine (`Idle / Pending / Active / Won / Lost`) and emits transitions.
- New `Necromancer` Node3D + mesh in main hall (initially hidden); appears during cutscene.
- New `Cutscene` autoload-controlled controller (text overlay + camera pan + flame particle drain), keyed off BossFlow state.
- `descent_prompt.gd` extended: when all 6 pyres are at 100% (already detected in Phase 4), skill-retention is now active AND a "Descend & Fight" option appears that consumes 1 elder soul on retries.
- New `BossDragon` script with 3 HP-threshold phases.
- New `boss_whelp.tscn` — same as `welp.gd` with `color="boss"` so it drops nothing AND inherits standard AI but tinted black.
- New `Courtyard` scene with circular arena, seal-on-entry gate, basement door (initially cracked, opens on victory).
- `Upstairs` scene gets a `ShadowWard` Area3D that blocks player exit when BossFlow state is `Pending` or `Active`.
- Necromancer dialogue plays via existing pause-able CanvasLayer pattern (new `DialogueBanner` UI with timed text).

**Tech Stack:** Godot 4.6.2, GDScript, GdUnit4. Same as Phases 1–4.

**Spec reference:** [`docs/superpowers/specs/2026-04-25-new-chance-design.md`](../specs/2026-04-25-new-chance-design.md) §5 Boss & endgame.

**Phase 5 scope (vs full design):**
- ✅ Boss-trigger detection with skill retention (final pyre + retry path)
- ✅ Cutscene (text + camera pan + simple flame particle drain — not full cinematic)
- ✅ Courtyard scene with seal-on-entry gate
- ✅ 3-phase HP-threshold boss with summons + telegraphed attacks
- ✅ Boss-summoned whelps (no drops)
- ✅ Death/retry flow with elder soul cost
- ✅ Victory: flames return + basement door reveals (visible stair, no content)
- ✅ Upstairs ward during boss flow
- ✅ Necromancer dialogue banner (death taunts + boss intro lines, text only)
- ❌ Full animated cinematic (Phase 6 polish)
- ❌ Voiced dialogue (Phase 6+)
- ❌ Basement post-game content (post-MVP)
- ❌ Full elder-tier minion appearance with drops (Phase 6 polish)

**Acceptance test:**
Player fills all 6 primary pyres. On the descent that fills the 6th, the descent prompt shows "Descend & Fight" option (skills retained). Player confirms → returns to main hall with skills intact. Cutscene fires: necromancer materializes, raises arms, flames stream from pyres into him, he transforms into the black dragon, courtyard door opens. Player walks into the courtyard; gate seals. Boss fight begins with 3 phases (HP 100-66% / 66-33% / 33-0%). Black whelps spawn periodically; killing them grants nothing. Player wins → flames burst back to pyres, basement stair appears visible. Player loses → dialogue plays, returns to main hall, courtyard locks. To retry: descend with 1+ elder soul → prompt offers "Descend & Fight" (consumes 1 elder), cutscene fires again, fight resumes. Upstairs is warded shut during boss flow (player can't escape mid-cutscene/fight).

---

## File structure

**Created:**
```
scripts/core/
└── boss_flow.gd                    # Autoload: state machine for boss flow
scripts/entities/
├── necromancer.gd                  # NPC in main hall, runs cutscene actions
└── boss_dragon.gd                  # Boss AI with 3-phase HP-threshold logic
scripts/world/
├── cutscene_controller.gd          # Drives flame-drain animation + camera pan
├── shadow_ward.gd                  # Area3D in upstairs that blocks exit during boss flow
└── courtyard_gate.gd               # Seals behind player on entry
scripts/ui/
└── dialogue_banner.gd              # Timed text banner for necromancer lines
scenes/entities/
├── necromancer.tscn
├── boss_dragon.tscn
└── boss_whelp.tscn
scenes/world/
└── courtyard.tscn
scenes/ui/
└── dialogue_banner.tscn
test/
├── test_boss_flow.gd
└── test_dialogue_banner.gd
```

**Modified:**
- `scripts/core/game_state.gd` — add `Location.COURTYARD`; `transition_to` reset upstairs ward state.
- `scripts/ui/descent_prompt.gd` — when boss-triggering, add "Descend & Fight" button (skill retention path).
- `scripts/world/escalation.gd` — `set_player_in_corner("")` when in courtyard so heat doesn't ramp.
- `scenes/world/main_hall.tscn` — add Necromancer (hidden), Cutscene controller, basement stair (initially hidden), gate to courtyard (locked).
- `scenes/world/upstairs.tscn` — add ShadowWard at staircase down.
- `project.godot` — register BossFlow autoload + add COURTYARD_SCENE_PATH constant in game_state.

---

## Task 1: BossFlow autoload state machine

**Files:**
- Create: `scripts/core/boss_flow.gd`
- Create: `test/test_boss_flow.gd`
- Modify: `project.godot` (autoload)

### Step 1: Write failing tests

`test/test_boss_flow.gd`:

```gdscript
extends GdUnitTestSuite

const BossFlowScript = preload("res://scripts/core/boss_flow.gd")

var bf: Node

func before_test() -> void:
	bf = auto_free(BossFlowScript.new())
	add_child(bf)

func test_starts_idle() -> void:
	assert_that(bf.state).is_equal(BossFlowScript.State.IDLE)

func test_trigger_boss_moves_to_pending() -> void:
	bf.trigger_boss()
	assert_that(bf.state).is_equal(BossFlowScript.State.PENDING)

func test_enter_arena_moves_to_active() -> void:
	bf.trigger_boss()
	bf.enter_arena()
	assert_that(bf.state).is_equal(BossFlowScript.State.ACTIVE)

func test_boss_killed_moves_to_won() -> void:
	bf.trigger_boss()
	bf.enter_arena()
	bf.boss_killed()
	assert_that(bf.state).is_equal(BossFlowScript.State.WON)

func test_player_died_moves_to_lost() -> void:
	bf.trigger_boss()
	bf.enter_arena()
	bf.player_died_in_boss()
	assert_that(bf.state).is_equal(BossFlowScript.State.LOST)

func test_lost_can_retrigger() -> void:
	bf.trigger_boss()
	bf.enter_arena()
	bf.player_died_in_boss()
	bf.trigger_boss()
	assert_that(bf.state).is_equal(BossFlowScript.State.PENDING)

func test_won_stays_won() -> void:
	bf.trigger_boss()
	bf.enter_arena()
	bf.boss_killed()
	bf.trigger_boss()
	# Once won, can't re-trigger boss
	assert_that(bf.state).is_equal(BossFlowScript.State.WON)

func test_state_changed_signal() -> void:
	var monitor := monitor_signals(bf)
	bf.trigger_boss()
	await assert_signal(bf).is_emitted("state_changed", [BossFlowScript.State.PENDING])

func test_is_active_during_pending_or_active() -> void:
	assert_that(bf.is_active()).is_false()
	bf.trigger_boss()
	assert_that(bf.is_active()).is_true()  # PENDING also counts (cutscene running)
	bf.enter_arena()
	assert_that(bf.is_active()).is_true()
	bf.boss_killed()
	assert_that(bf.is_active()).is_false()

func test_reset_returns_to_idle_unless_won() -> void:
	bf.trigger_boss()
	bf.player_died_in_boss()
	bf.reset()
	assert_that(bf.state).is_equal(BossFlowScript.State.IDLE)

func test_reset_preserves_won() -> void:
	bf.trigger_boss()
	bf.enter_arena()
	bf.boss_killed()
	bf.reset()
	assert_that(bf.state).is_equal(BossFlowScript.State.WON)
```

### Step 2: Run tests — verify failures

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_boss_flow.gd --ignoreHeadlessMode
```

### Step 3: Implement BossFlow

```gdscript
extends Node

enum State { IDLE, PENDING, ACTIVE, WON, LOST }

signal state_changed(new_state: State)

var state: State = State.IDLE

func trigger_boss() -> void:
	if state == State.WON:
		return  # Already beaten — no re-trigger
	_set_state(State.PENDING)

func enter_arena() -> void:
	if state == State.PENDING:
		_set_state(State.ACTIVE)

func boss_killed() -> void:
	if state == State.ACTIVE:
		_set_state(State.WON)

func player_died_in_boss() -> void:
	if state == State.ACTIVE or state == State.PENDING:
		_set_state(State.LOST)

func reset() -> void:
	# Reset transient state but preserve WON.
	if state != State.WON:
		_set_state(State.IDLE)

func is_active() -> bool:
	return state == State.PENDING or state == State.ACTIVE

func has_won() -> bool:
	return state == State.WON

func _set_state(s: State) -> void:
	if s == state:
		return
	state = s
	state_changed.emit(s)
```

### Step 4: Run tests + register autoload

Run tests, expect 11/11 pass.

Add to project.godot `[autoload]`:
```
BossFlow="*res://scripts/core/boss_flow.gd"
```

Full suite expected: 102 tests (91 + 11).

### Step 5: Commit

```bash
git add scripts/core/boss_flow.gd test/test_boss_flow.gd project.godot
git commit -m "feat(boss): BossFlow autoload state machine (idle/pending/active/won/lost)"
```

---

## Task 2: Necromancer NPC + black dragon mesh

**Files:**
- Create: `scripts/entities/necromancer.gd`
- Create: `scenes/entities/necromancer.tscn`
- Modify: `scenes/world/main_hall.tscn` — instance Necromancer (initially hidden)

### Step 1: Implement script

```gdscript
# scripts/entities/necromancer.gd
extends Node3D

@onready var _humanoid_mesh: MeshInstance3D = $HumanoidMesh
@onready var _dragon_mesh: MeshInstance3D = $DragonMesh

func _ready() -> void:
	visible = false
	_dragon_mesh.visible = false
	BossFlow.state_changed.connect(_on_boss_state_changed)

func _on_boss_state_changed(s: int) -> void:
	if s == BossFlow.State.PENDING:
		appear_humanoid()

func appear_humanoid() -> void:
	visible = true
	_humanoid_mesh.visible = true
	_dragon_mesh.visible = false

func transform_to_dragon() -> void:
	_humanoid_mesh.visible = false
	_dragon_mesh.visible = true

func dismiss() -> void:
	visible = false
```

### Step 2: Build scene

`scenes/entities/necromancer.tscn`:

```
[gd_scene load_steps=8 format=3]

[ext_resource type="Script" path="res://scripts/entities/necromancer.gd" id="1_necro"]

[sub_resource type="CapsuleMesh" id="CapsuleMesh_humanoid"]
radius = 0.4
height = 1.8

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_humanoid"]
albedo_color = Color(0.15, 0.05, 0.2, 1)
emission_enabled = true
emission = Color(0.5, 0.1, 0.6, 1)
emission_energy_multiplier = 0.5

[sub_resource type="BoxMesh" id="BoxMesh_dragon"]
size = Vector3(2.5, 2.5, 4)

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_dragon"]
albedo_color = Color(0.05, 0.05, 0.08, 1)
emission_enabled = true
emission = Color(0.4, 0.05, 0.1, 1)
emission_energy_multiplier = 1.5
metallic = 0.4
roughness = 0.6

[node name="Necromancer" type="Node3D"]
script = ExtResource("1_necro")

[node name="HumanoidMesh" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.9, 0)
mesh = SubResource("CapsuleMesh_humanoid")
material_override = SubResource("StandardMaterial3D_humanoid")

[node name="DragonMesh" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.25, 0)
mesh = SubResource("BoxMesh_dragon")
material_override = SubResource("StandardMaterial3D_dragon")
```

### Step 3: Add to main_hall.tscn

Read main_hall.tscn. Add ext_resource for necromancer.tscn (next available id) and instance:

```
[node name="Necromancer" parent="." instance=ExtResource("X_necro")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, -3)
```

(Position center-back of main hall.)

### Step 4: Verify import + commit

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . --import 2>&1 | grep -i error | head -5
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
git add scripts/entities/necromancer.gd scenes/entities/necromancer.tscn scenes/world/main_hall.tscn
git commit -m "feat(necromancer): NPC with humanoid + black dragon mesh forms (hidden by default)"
```

---

## Task 3: Dialogue banner UI

**Files:**
- Create: `scripts/ui/dialogue_banner.gd`
- Create: `scenes/ui/dialogue_banner.tscn`
- Modify: `scenes/world/main_hall.tscn` — instance the banner

### Step 1: Implement script

```gdscript
extends CanvasLayer

@onready var _label: Label = $Margin/Panel/Label

const LINES: Dictionary = {
	"death_normal": [
		"Get up, fool. The dragons aren't going to slay themselves.",
		"You die so well, little corpse. Try harder.",
		"What a waste of bone. Again.",
		"Did you forget what I made you for?",
		"Crawl back to the pyres. The dragons grow restless.",
	],
	"death_boss": [
		"Did you really believe this would be enough?",
		"You knew what I was. You came anyway.",
		"Your bones will burn alongside the rest.",
		"Crawl back, little corpse. Try harder this time.",
	],
	"flame_drain": [
		"At last. The flames are mine.",
		"You did all the hard work for me, little corpse.",
		"I will wear these flames as my crown.",
	],
	"victory": [
		"Impossible…",
	],
}

@export var line_duration: float = 4.0

var _timer: float = 0.0

func _ready() -> void:
	visible = false
	set_process(true)

func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		visible = false

func show_line(category: String) -> void:
	var pool: Array = LINES.get(category, [])
	if pool.is_empty():
		return
	var line: String = pool[randi() % pool.size()]
	_label.text = line
	visible = true
	_timer = line_duration

func show_specific(line: String, duration: float = 4.0) -> void:
	_label.text = line
	visible = true
	_timer = duration
```

### Step 2: Build scene

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/dialogue_banner.gd" id="1_banner"]

[node name="DialogueBanner" type="CanvasLayer"]
process_mode = 3
script = ExtResource("1_banner")

[node name="Margin" type="MarginContainer" parent="."]
anchors_preset = 12
anchor_top = 1.0
anchor_right = 1.0
anchor_bottom = 1.0
offset_top = -120.0
grow_horizontal = 2
grow_vertical = 0
theme_override_constants/margin_left = 40
theme_override_constants/margin_right = 40
theme_override_constants/margin_bottom = 32

[node name="Panel" type="PanelContainer" parent="Margin"]
layout_mode = 2

[node name="Label" type="Label" parent="Margin/Panel"]
layout_mode = 2
text = "..."
autowrap_mode = 2
horizontal_alignment = 1
```

### Step 3: Add to main_hall.tscn AND upstairs.tscn AND courtyard.tscn (when built)

For now, add to main_hall.tscn:
```
[node name="DialogueBanner" parent="." instance=ExtResource("Y_banner")]
```

Will be added to upstairs and courtyard in later tasks.

### Step 4: Verify + commit

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . --import 2>&1 | grep -i error | head -5
git add scripts/ui/dialogue_banner.gd scenes/ui/dialogue_banner.tscn scenes/world/main_hall.tscn
git commit -m "feat(dialogue): DialogueBanner UI with necromancer line pools"
```

---

## Task 4: Cutscene controller (flame drain + transformation)

**Files:**
- Create: `scripts/world/cutscene_controller.gd`
- Modify: `scenes/world/main_hall.tscn` — instance CutsceneController

### Step 1: Implement controller

```gdscript
# scripts/world/cutscene_controller.gd
extends Node

# Listens to BossFlow.PENDING transitions, runs the cutscene sequence,
# then opens the courtyard door. Pauses player input during sequence.

@export var necromancer_path: NodePath
@export var dialogue_banner_path: NodePath
@export var courtyard_door_path: NodePath  # body that gets removed/visible toggled

var _necromancer: Node3D = null
var _banner: CanvasLayer = null
var _door: Node3D = null

func _ready() -> void:
	if necromancer_path != NodePath(""):
		_necromancer = get_node_or_null(necromancer_path)
	if dialogue_banner_path != NodePath(""):
		_banner = get_node_or_null(dialogue_banner_path)
	if courtyard_door_path != NodePath(""):
		_door = get_node_or_null(courtyard_door_path)
	BossFlow.state_changed.connect(_on_boss_state_changed)

func _on_boss_state_changed(s: int) -> void:
	if s == BossFlow.State.PENDING:
		_run_cutscene()

func _run_cutscene() -> void:
	# Step 1: Necromancer appears (handled by Necromancer's own listener — already up)
	if _banner != null:
		_banner.show_line("flame_drain")
	# Step 2: Wait for line to be heard, then drain pyres (just play SFX/visual stub)
	await get_tree().create_timer(2.5).timeout
	# Step 3: Visually extinguish all 6 pyres (set their fill ratios to 0 visually
	# WITHOUT modifying SoulEconomy state — just darken them temporarily)
	# For Phase 5: simplify by tinting pyres dark via per-color iteration.
	_visually_extinguish_pyres()
	await get_tree().create_timer(1.5).timeout
	# Step 4: Necromancer transforms
	if _necromancer != null and _necromancer.has_method("transform_to_dragon"):
		_necromancer.transform_to_dragon()
	await get_tree().create_timer(2.0).timeout
	# Step 5: Open courtyard door (just hide the door mesh / disable collider)
	if _door != null:
		_door.visible = false
		var col: CollisionShape3D = _door.get_node_or_null("CollisionShape3D")
		if col != null:
			col.disabled = true

func _visually_extinguish_pyres() -> void:
	var hall: Node = get_tree().root.find_child("MainHall", true, false)
	if hall == null:
		return
	# Find all Pyre nodes (they have a Flame child); set flame mat emission_energy to 0
	for c in hall.get_children():
		if c.has_node("Flame"):
			var flame: MeshInstance3D = c.get_node("Flame")
			var mat: StandardMaterial3D = flame.material_override as StandardMaterial3D
			if mat != null:
				mat.emission_energy_multiplier = 0.0
				flame.scale.y = 0.05  # near-zero
```

### Step 2: Add CutsceneController to main_hall.tscn

After all other nodes in main_hall.tscn:

```
[node name="CutsceneController" type="Node" parent="."]
script = ExtResource("Z_cutscene")
necromancer_path = NodePath("../Necromancer")
dialogue_banner_path = NodePath("../DialogueBanner")
courtyard_door_path = NodePath("../CourtyardDoor")
```

(`CourtyardDoor` will be added in Task 5.)

### Step 3: Verify + commit

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . --import 2>&1 | grep -i error | head -5
git add scripts/world/cutscene_controller.gd scenes/world/main_hall.tscn
git commit -m "feat(cutscene): controller drives flame-drain + necromancer transform on PENDING"
```

---

## Task 5: Courtyard scene + entry transition

**Files:**
- Create: `scripts/world/courtyard_gate.gd` (seals on player entry)
- Create: `scenes/world/courtyard.tscn`
- Modify: `scripts/core/game_state.gd` (add Location.COURTYARD + scene path)
- Modify: `scenes/world/main_hall.tscn` (add CourtyardDoor that triggers transition)

### Step 1: Add Location.COURTYARD to game_state

```gdscript
enum Location { MAIN_HALL, UPSTAIRS, COURTYARD }

const COURTYARD_SCENE_PATH: String = "res://scenes/world/courtyard.tscn"

# In scene_path_for, add:
		Location.COURTYARD:
			return COURTYARD_SCENE_PATH
```

### Step 2: Implement courtyard_gate.gd

```gdscript
extends Area3D

# Detects player entry → calls BossFlow.enter_arena() and seals the gate.

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	BossFlow.enter_arena()
	# Disable further entry/exit (player is committed)
	monitoring = false
	# Make gate visible and physical to block exit
	var gate_mesh: MeshInstance3D = get_node_or_null("GateMesh")
	var gate_collider: CollisionShape3D = get_node_or_null("GateCollider")
	if gate_mesh != null:
		gate_mesh.visible = true
	if gate_collider != null:
		gate_collider.disabled = false
```

### Step 3: Build courtyard.tscn

A circular arena. Stone perimeter. Entry gate area at one side (where player enters). Boss spawn point at center. Player spawn point near the gate.

```
[gd_scene load_steps=12 format=3]

[ext_resource type="Script" path="res://scripts/world/courtyard_gate.gd" id="1_gate"]
[ext_resource type="PackedScene" path="res://scenes/entities/player.tscn" id="2_player"]
[ext_resource type="PackedScene" path="res://scenes/ui/hud.tscn" id="3_hud"]
[ext_resource type="PackedScene" path="res://scenes/ui/dialogue_banner.tscn" id="4_banner"]
[ext_resource type="PackedScene" path="res://scenes/entities/boss_dragon.tscn" id="5_boss"]

[sub_resource type="CylinderShape3D" id="floor_shape"]
height = 0.5
radius = 18.0

[sub_resource type="CylinderMesh" id="floor_mesh"]
top_radius = 18.0
bottom_radius = 18.0
height = 0.5

[sub_resource type="StandardMaterial3D" id="floor_mat"]
albedo_color = Color(0.2, 0.18, 0.16, 1)

[sub_resource type="Environment" id="env"]
background_mode = 1
background_color = Color(0.04, 0.02, 0.04, 1)
ambient_light_source = 2
ambient_light_color = Color(0.4, 0.2, 0.2, 1)
ambient_light_energy = 0.4

[sub_resource type="BoxShape3D" id="gate_trigger_shape"]
size = Vector3(6, 4, 2)

[sub_resource type="BoxMesh" id="gate_block_mesh"]
size = Vector3(6, 4, 0.5)

[sub_resource type="StandardMaterial3D" id="gate_block_mat"]
albedo_color = Color(0.3, 0.05, 0.05, 1)
emission_enabled = true
emission = Color(0.6, 0.1, 0.1, 1)
emission_energy_multiplier = 1.5

[node name="Courtyard" type="Node3D"]

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("env")

[node name="DirectionalLight3D" type="DirectionalLight3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 0.7071, 0.7071, 0, -0.7071, 0.7071, 0, 8, 0)
light_color = Color(0.9, 0.6, 0.4, 1)
light_energy = 0.5

[node name="Floor" type="StaticBody3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.25, 0)

[node name="CollisionShape3D" type="CollisionShape3D" parent="Floor"]
shape = SubResource("floor_shape")

[node name="Mesh" type="MeshInstance3D" parent="Floor"]
mesh = SubResource("floor_mesh")
material_override = SubResource("floor_mat")

[node name="EntryGate" type="Area3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 16)
script = ExtResource("1_gate")

[node name="CollisionShape3D" type="CollisionShape3D" parent="EntryGate"]
shape = SubResource("gate_trigger_shape")

[node name="GateMesh" type="MeshInstance3D" parent="EntryGate"]
visible = false
mesh = SubResource("gate_block_mesh")
material_override = SubResource("gate_block_mat")

[node name="GateCollider" type="StaticBody3D" parent="EntryGate"]

[node name="GateColliderShape" type="CollisionShape3D" parent="EntryGate/GateCollider"]
disabled = true
shape = SubResource("gate_trigger_shape")

[node name="Camera3D" type="Camera3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 0.5736, 0.8192, 0, -0.8192, 0.5736, 0, 18, 14)

[node name="Player" parent="." instance=ExtResource("2_player")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 14)

[node name="Boss" parent="." instance=ExtResource("5_boss")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2, 0)

[node name="HUD" parent="." instance=ExtResource("3_hud")]
[node name="DialogueBanner" parent="." instance=ExtResource("4_banner")]
```

(BossDragon scene built in Task 6 — for now, building the courtyard scene without it would error. Build boss_dragon.tscn first OR remove the Boss node temporarily and add in Task 6.)

**ALTERNATIVE:** build courtyard.tscn WITHOUT the Boss node first, run import to verify, then in Task 6 add the Boss instance back. This avoids needing both files at once.

### Step 4: Add CourtyardDoor to main_hall.tscn

CourtyardDoor is a visible block in the main hall that triggers transition to Courtyard scene when the player walks into it. Initially blocks the player.

In main_hall.tscn, add:

```
[sub_resource type="BoxShape3D" id="door_shape"]
size = Vector3(4, 4, 0.5)

[sub_resource type="BoxMesh" id="door_mesh"]
size = Vector3(4, 4, 0.5)

[sub_resource type="StandardMaterial3D" id="door_mat"]
albedo_color = Color(0.4, 0.2, 0.2, 1)
emission_enabled = true
emission = Color(0.7, 0.3, 0.3, 1)
emission_energy_multiplier = 0.8
```

(After existing sub_resources)

```
[node name="CourtyardDoor" type="StaticBody3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0)

[node name="CollisionShape3D" type="CollisionShape3D" parent="CourtyardDoor"]
shape = SubResource("door_shape")

[node name="Mesh" type="MeshInstance3D" parent="CourtyardDoor"]
mesh = SubResource("door_mesh")
material_override = SubResource("door_mat")

[node name="Trigger" type="Area3D" parent="CourtyardDoor"]

[node name="TriggerCollider" type="CollisionShape3D" parent="CourtyardDoor/Trigger"]
shape = SubResource("door_shape")
```

For the trigger, attach a small inline script (or new file) that on body_entered transitions to courtyard ONLY when BossFlow state is PENDING (door is "open").

Create `scripts/world/courtyard_door_trigger.gd`:

```gdscript
extends Area3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if BossFlow.state == BossFlow.State.PENDING:
		GameState.transition_to(GameState.Location.COURTYARD)
```

Attach this to the Trigger Area3D.

### Step 5: Verify + commit

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . --import 2>&1 | grep -i error | head -10
git add scripts/world/courtyard_gate.gd scripts/world/courtyard_door_trigger.gd scripts/core/game_state.gd scenes/world/courtyard.tscn scenes/world/main_hall.tscn
git commit -m "feat(courtyard): scene + gate seal + main_hall door trigger"
```

---

## Task 6: Boss dragon AI with 3 phases + boss whelp

**Files:**
- Create: `scripts/entities/boss_dragon.gd`
- Create: `scenes/entities/boss_dragon.tscn`
- Create: `scenes/entities/boss_whelp.tscn`

### Step 1: Implement boss_dragon.gd

```gdscript
extends CharacterBody3D

const MAX_HP: int = 600
const MOVE_SPEED: float = 2.0
const PHASE_2_HP_PCT: float = 0.66
const PHASE_3_HP_PCT: float = 0.33

const BOSS_WHELP_SCENE: PackedScene = preload("res://scenes/entities/boss_whelp.tscn")

@export var phase_1_summon_interval: float = 3.0
@export var phase_2_summon_interval: float = 2.0
@export var phase_3_summon_interval: float = 4.0  # slower but elder-tier
@export var contact_damage: int = 30
@export var contact_interval: float = 1.5

var hp: int = MAX_HP
var _player: Node = null
var _summon_timer: float = 0.0
var _contact_timer: float = 0.0
var _phase: int = 1
var _is_dead: bool = false

signal phase_changed(new_phase: int)
signal died

func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 2
	_find_player()

func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	if _player == null or not is_instance_valid(_player):
		_find_player()
		if _player == null:
			return
	# Slow chase + contact damage
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	var dist: float = to_player.length()
	if dist > 2.5:
		velocity.x = to_player.normalized().x * MOVE_SPEED
		velocity.z = to_player.normalized().z * MOVE_SPEED
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if _contact_timer <= 0.0 and _player.has_method("take_damage"):
			_player.take_damage(contact_damage)
			_contact_timer = contact_interval
	if _contact_timer > 0.0:
		_contact_timer = max(0.0, _contact_timer - delta)
	# Whelp summons
	_summon_timer += delta
	var interval: float = _interval_for_phase()
	if _summon_timer >= interval:
		_summon_timer = 0.0
		_summon_whelp()
	velocity.y -= 9.8 * delta if not is_on_floor() else 0.0
	move_and_slide()

func _find_player() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]

func _interval_for_phase() -> float:
	match _phase:
		1: return phase_1_summon_interval
		2: return phase_2_summon_interval
		3: return phase_3_summon_interval
		_: return phase_1_summon_interval

func _summon_whelp() -> void:
	var whelp: CharacterBody3D = BOSS_WHELP_SCENE.instantiate()
	# In phase 3, summon elder-sized whelps
	if _phase == 3 and "max_hp" in whelp:
		whelp.max_hp = 80  # elder-tier HP
	var angle: float = randf() * TAU
	var spawn_pos: Vector3 = global_position + Vector3(cos(angle) * 5.0, 1.0, sin(angle) * 5.0)
	get_parent().add_child(whelp)
	whelp.global_position = spawn_pos

func take_damage(amount: int) -> void:
	if _is_dead:
		return
	hp = max(0, hp - amount)
	_check_phase_transition()
	if hp == 0:
		_is_dead = true
		died.emit()
		BossFlow.boss_killed()
		queue_free()

func _check_phase_transition() -> void:
	var pct: float = float(hp) / float(MAX_HP)
	var new_phase: int = _phase
	if pct <= PHASE_3_HP_PCT:
		new_phase = 3
	elif pct <= PHASE_2_HP_PCT:
		new_phase = 2
	if new_phase != _phase:
		_phase = new_phase
		phase_changed.emit(_phase)
```

### Step 2: Build boss_dragon.tscn

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/entities/boss_dragon.gd" id="1_boss"]

[sub_resource type="BoxShape3D" id="BoxShape3D_boss"]
size = Vector3(3, 3, 5)

[sub_resource type="BoxMesh" id="BoxMesh_boss"]
size = Vector3(3, 3, 5)

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_boss"]
albedo_color = Color(0.05, 0.05, 0.08, 1)
emission_enabled = true
emission = Color(0.5, 0.05, 0.1, 1)
emission_energy_multiplier = 1.8
metallic = 0.5

[node name="BossDragon" type="CharacterBody3D"]
script = ExtResource("1_boss")

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
shape = SubResource("BoxShape3D_boss")

[node name="Mesh" type="MeshInstance3D" parent="."]
mesh = SubResource("BoxMesh_boss")
material_override = SubResource("StandardMaterial3D_boss")
```

### Step 3: Build boss_whelp.tscn

Identical to welp_blue.tscn but with `color = "boss"` (so welp.gd's `_drop_souls` returns early — no drops) and dark albedo:

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/entities/welp.gd" id="1_welp"]

[sub_resource type="BoxShape3D" id="BoxShape3D_welp"]
size = Vector3(0.7, 0.7, 0.7)

[sub_resource type="BoxMesh" id="BoxMesh_welp"]
size = Vector3(0.7, 0.7, 0.7)

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_welp_boss"]
albedo_color = Color(0.1, 0.05, 0.1, 1)

[node name="Welp" type="CharacterBody3D"]
script = ExtResource("1_welp")
color = "boss"

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
shape = SubResource("BoxShape3D_welp")

[node name="Mesh" type="MeshInstance3D" parent="."]
mesh = SubResource("BoxMesh_welp")
material_override = SubResource("StandardMaterial3D_welp_boss")
```

Modify `welp.gd._drop_souls` to also short-circuit on `color == "boss"`:

```gdscript
func _drop_souls() -> void:
	if color == "alarm" or color == "boss":
		return
	# ... rest unchanged
```

### Step 4: Verify + commit

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . --import 2>&1 | grep -i error | head -5
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
git add scripts/entities/boss_dragon.gd scenes/entities/boss_dragon.tscn scenes/entities/boss_whelp.tscn scripts/entities/welp.gd
git commit -m "feat(boss): boss_dragon AI with 3 HP-threshold phases + boss_whelp summons (no drops)"
```

---

## Task 7: Boss death + retry flow

**Files:**
- Modify: `scripts/world/death_handler.gd` — detect boss death (when player dies in courtyard)
- Modify: `scripts/ui/descent_prompt.gd` — add "Descend & Fight" option that consumes 1 elder soul on retry

### Step 1: Update death_handler.gd

Read existing death_handler.gd. Modify to check if player died in courtyard, then call `BossFlow.player_died_in_boss()` instead of (or in addition to) end_run:

```gdscript
extends Node

func _ready() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.size() == 0:
		push_warning("DeathHandler: no player found")
		return
	var player: Node = players[0]
	if not player.died.is_connected(_on_player_died):
		player.died.connect(_on_player_died)

func _on_player_died() -> void:
	if GameState.current_location == GameState.Location.COURTYARD:
		BossFlow.player_died_in_boss()
		# Banner: boss death taunt
		var banner: CanvasLayer = get_tree().root.find_child("DialogueBanner", true, false)
		if banner != null:
			banner.show_line("death_boss")
		GameState.end_run(GameState.Outcome.DIED)
	else:
		# Banner: normal death taunt
		var banner: CanvasLayer = get_tree().root.find_child("DialogueBanner", true, false)
		if banner != null:
			banner.show_line("death_normal")
		GameState.end_run(GameState.Outcome.DIED)
```

### Step 2: DescentPrompt — Descend & Fight retry option

Read scripts/ui/descent_prompt.gd. Modify show_prompt to add retry button when:
- All 6 pyres at 100% AND
- Player has at least 1 elder soul carried AND
- BossFlow state is LOST or IDLE (not WON)

For Phase 5 simplification: extend the prompt with a second confirm button "Descend & Fight". For Phase 5 implementation, the existing single Confirm button can be repurposed via a state check.

Simpler: keep single Confirm button. When the boss-trigger condition holds (all pyres at 100% AND have elder), show button text as "Descend & Fight" and on confirm:
- Consume 1 elder soul
- Skip skill-strip (don't call clear_carry — actually deposit_to_pyres clears it; need a path that retains skills)

This gets complex. The architectural fix: have GameState.end_run accept a flag for skill retention.

Modify GameState.end_run to take an optional skill_retain flag:

```gdscript
func end_run(outcome: Outcome, retain_skills: bool = false) -> void:
	if outcome == Outcome.DESCENDED:
		SoulEconomy.deposit_to_pyres()
	elif outcome == Outcome.DIED:
		SoulEconomy.clear_carry()
	# Only clear skills if NOT retaining
	if not retain_skills:
		# (Player handles its own skill clear via run_ended listener; we'd need a way to skip that)
		pass
	run_ended.emit(outcome)
	# ... rest unchanged
```

This is getting complex. Simplification: have descent_prompt detect boss-trigger and call a NEW method `GameState.end_run_for_boss()` that:
1. Deposits souls (which fills the 6th pyre and triggers `pyre_filled` → MetaProgress)
2. Calls BossFlow.trigger_boss() → cutscene fires
3. Does NOT clear player skills (special path)

In `descent_prompt.gd._on_confirm`:

```gdscript
func _on_confirm() -> void:
	hide_prompt()
	if _will_fill_all_primary_pyres() or _can_retry_boss():
		# Boss-triggering path: skill retention
		_descend_and_fight()
	else:
		confirmed.emit()  # normal extract path

func _can_retry_boss() -> bool:
	# All pyres already lit + player has elder soul + boss not yet won
	var all_lit: bool = true
	for c in SoulEconomy.COLORS:
		if SoulEconomy.pyre_fill(c) < SoulEconomy.PYRE_CAP:
			all_lit = false
			break
	if not all_lit:
		return false
	if BossFlow.has_won():
		return false
	# Need at least 1 elder soul carried
	var has_elder: bool = false
	for c in SoulEconomy.COLORS:
		if SoulEconomy.carry_count(c, "elder") > 0:
			has_elder = true
			break
	return has_elder

func _descend_and_fight() -> void:
	# Consume 1 elder soul if this is a retry (pyres already full)
	if _can_retry_boss():
		# Drain 1 elder from any color
		for c in SoulEconomy.COLORS:
			if SoulEconomy.carry_count(c, "elder") > 0:
				SoulEconomy._carry[c]["elder"] -= 1
				break
	# Deposit remaining (this fills the final pyre on first trigger)
	SoulEconomy.deposit_to_pyres()
	# Trigger boss flow (cutscene fires, courtyard door opens)
	BossFlow.trigger_boss()
	# Transition back to main hall (where cutscene plays)
	GameState.transition_to(GameState.Location.MAIN_HALL)
	# (Skills are NOT cleared — this is the retention path)
```

Note: this bypasses GameState.end_run entirely, which means Escalation.reset() isn't called. Add it manually:

```gdscript
	Escalation.reset()
```

### Step 3: Verify + commit

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . --import 2>&1 | grep -i error | head -5
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
git add scripts/world/death_handler.gd scripts/ui/descent_prompt.gd
git commit -m "feat(boss-flow): boss-triggering descent retains skills, retry costs 1 elder soul"
```

---

## Task 8: Victory + flame return + basement reveal

**Files:**
- Modify: `scripts/world/cutscene_controller.gd` (add victory handler)
- Modify: `scenes/world/main_hall.tscn` — add BasementStair (initially hidden, reveals on victory)

### Step 1: Update cutscene_controller for victory

Add to cutscene_controller.gd:

```gdscript
func _on_boss_state_changed(s: int) -> void:
	if s == BossFlow.State.PENDING:
		_run_cutscene()
	elif s == BossFlow.State.WON:
		_run_victory()

func _run_victory() -> void:
	# Restore pyre flame visuals (still at 100% in SoulEconomy data)
	var hall: Node = get_tree().root.find_child("MainHall", true, false)
	if hall == null:
		return
	for c in hall.get_children():
		if c.has_node("Flame"):
			var flame: MeshInstance3D = c.get_node("Flame")
			flame.scale.y = 1.6  # restored
			var mat: StandardMaterial3D = flame.material_override as StandardMaterial3D
			if mat != null:
				mat.emission_energy_multiplier = 4.5  # extra bright after return
	# Banner: victory line
	if _banner != null:
		_banner.show_line("victory")
	# Reveal basement stair
	var stair: Node3D = hall.get_node_or_null("BasementStair")
	if stair != null:
		stair.visible = true
	# Hide necromancer (he's defeated)
	if _necromancer != null and _necromancer.has_method("dismiss"):
		_necromancer.dismiss()
```

### Step 2: Add BasementStair to main_hall.tscn

```
[sub_resource type="BoxMesh" id="basement_mesh"]
size = Vector3(3, 0.3, 5)

[sub_resource type="StandardMaterial3D" id="basement_mat"]
albedo_color = Color(0.15, 0.1, 0.2, 1)
emission_enabled = true
emission = Color(0.4, 0.2, 0.6, 1)
emission_energy_multiplier = 1.5
```

```
[node name="BasementStair" type="Node3D" parent="."]
visible = false
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.15, 5)

[node name="Mesh" type="MeshInstance3D" parent="BasementStair"]
mesh = SubResource("basement_mesh")
material_override = SubResource("basement_mat")
```

(Position behind the player spawn — visible after boss victory.)

### Step 3: Verify + commit

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . --import 2>&1 | grep -i error | head -5
git add scripts/world/cutscene_controller.gd scenes/world/main_hall.tscn
git commit -m "feat(victory): flame restoration + basement stair reveal on boss death"
```

---

## Task 9: Upstairs shadow ward

**Files:**
- Create: `scripts/world/shadow_ward.gd`
- Modify: `scenes/world/upstairs.tscn` — add ShadowWard at staircase

### Step 1: Implement shadow_ward.gd

```gdscript
extends Area3D

# Sits at the upstairs staircase. When BossFlow is PENDING or ACTIVE, the ward is up
# (visible, blocks player exit via collision). Otherwise dropped.

@onready var _ward_mesh: MeshInstance3D = $WardMesh
@onready var _ward_collider: StaticBody3D = $WardCollider

func _ready() -> void:
	BossFlow.state_changed.connect(_on_boss_state_changed)
	_refresh()

func _on_boss_state_changed(_s: int) -> void:
	_refresh()

func _refresh() -> void:
	var blocked: bool = BossFlow.is_active()
	if _ward_mesh != null:
		_ward_mesh.visible = blocked
	if _ward_collider != null:
		var col: CollisionShape3D = _ward_collider.get_node_or_null("CollisionShape3D")
		if col != null:
			col.disabled = not blocked
```

### Step 2: Add to upstairs.tscn

Read upstairs.tscn. The descent staircase is at center (0, 0.1, 0). Add a ShadowWard right next to it that, when active, physically blocks the player from descending (so they can't escape mid-cutscene).

Actually — the cutscene fires AFTER the player descends, so the ward should block UPWARDS movement (preventing the player from going back upstairs after triggering the boss). Hmm. Actually:

- Player is upstairs, fills 6th pyre via descent prompt with souls.
- Player descends → arrives in main hall → cutscene fires → courtyard door opens → fight.
- During fight, player is in courtyard. Can't get to upstairs (different scene).
- If player dies → returns to main hall (LOST state) → courtyard door re-locks. Now they can go upstairs to farm elder.

So the ward at upstairs really blocks the player from re-entering upstairs WHILE the boss flow is active — which is between PENDING (cutscene) and either WON or LOST. The main hall's "go upstairs" trigger should respect this state.

Adjust: the ward goes on the main_hall.tscn's UpstairsTrigger Area3D, not in upstairs.tscn. Or: ShadowWard is at the upstairs trigger in main_hall.

Simpler: modify the existing `main_hall_upstairs_trigger.gd` to NOT transition when BossFlow.is_active().

Update `scripts/world/main_hall_upstairs_trigger.gd`:

```gdscript
extends Area3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if BossFlow.is_active():
		# Optional: show banner "the ward seals the way"
		var banner: CanvasLayer = get_tree().root.find_child("DialogueBanner", true, false)
		if banner != null:
			banner.show_specific("The flames have already chosen.", 3.0)
		return
	GameState.transition_to(GameState.Location.UPSTAIRS)
```

This achieves the same effect without a separate scene-bound ward.

For Phase 5 simplicity, do this and skip the visual ward. (Phase 6 polish can add the visual.)

### Step 3: Verify + commit

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . --import 2>&1 | grep -i error | head -5
git add scripts/world/main_hall_upstairs_trigger.gd
git commit -m "feat(ward): block upstairs entry while BossFlow is active (cutscene/fight in progress)"
```

(Skip dedicated shadow_ward.gd file for Phase 5; revisit in polish.)

---

## Task 10: Acceptance playtest (USER)

After all 9 tasks land, the user runs the game. Validation:

- [ ] Fill all 6 primary pyres (use FAST-TEST values from Phase 4 to make this quick)
- [ ] On the descent that fills the 6th: prompt shows "Descend & Fight" path (skills retained)
- [ ] Cutscene fires in main hall: necromancer appears, banner line, pyres extinguish, transformation, courtyard door opens
- [ ] Walk into courtyard door → transitions to courtyard scene
- [ ] Boss begins; gate seals behind player
- [ ] Boss summons whelps periodically; killing them yields nothing
- [ ] Player attacks boss; HP visibly drops (debug log or HUD if present)
- [ ] At 66% HP: boss enters phase 2 (faster summons)
- [ ] At 33% HP: phase 3 (elder-tier whelp summons)
- [ ] Player dies in courtyard → boss-death banner line → returns to main hall, courtyard door re-locks
- [ ] Try to go upstairs while courtyard is locked but BossFlow is LOST → succeeds (ward only active in PENDING/ACTIVE)
- [ ] Farm an elder soul upstairs, descend → prompt shows "Descend & Fight" retry option (consumes 1 elder)
- [ ] Cutscene re-fires; back into the courtyard
- [ ] Boss killed → flames burst back (visually restored), basement stair appears in main hall, banner victory line
- [ ] Game state transitions cleanly

### Step 1: User runs the game

(Manual.)

### Step 2: Tag

```bash
git tag -a v0.5-boss-flow -m "Phase 5: full boss flow — cutscene, courtyard, 3-phase boss dragon, retry mechanic, victory + basement reveal, upstairs ward."
```

---

## Phase 5 → Phase 6 handoff

What Phase 5 leaves for Phase 6 (polish):
- Cutscene is text + simple visuals — no animated camera, no particle FX, no music sting.
- Banner uses Label, not voiced or styled with portraits.
- Basement reveal is just a visible stair stub with no destination scene.
- Boss visual is a single static box mesh — no animation, no roar, no flame breath particles.
- Ward is logic-only (no visual barrier in scene).
- All combat numbers (boss HP, contact damage, summon rate) untuned beyond first-pass guesses.

Phase 6 (polish + tuning) addresses all of the above + audio + cantrip placeholders → real elemental effects + final balance.
