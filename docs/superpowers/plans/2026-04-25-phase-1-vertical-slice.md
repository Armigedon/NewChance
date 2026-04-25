# Phase 1 — Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a playable up/down/deposit loop in Godot 4.6 with one color (Red), one upstairs corner, one welp enemy type, one pyre, and minimum-viable combat. Validates the core game feel of the design before broader systems are built.

**Architecture:** GDScript with autoloaded singletons (`GameState`, `SoulEconomy`) for run-independent state, scene composition for entities and world, GdUnit4 for unit tests on logic. Scene-swap navigation between the two world scenes (main hall ↔ upstairs).

**Tech Stack:** Godot 4.6.2 (.NET build, Forward+ renderer, Jolt 3D physics, already configured), GDScript, GdUnit4 testing addon.

**Spec reference:** [`docs/superpowers/specs/2026-04-25-new-chance-design.md`](../specs/2026-04-25-new-chance-design.md)

**Phase 1 scope cut (vs. full MVP):**
- ✅ Player movement, dash, HP, death/respawn
- ✅ Sword auto-melee (no skill-element inheritance yet)
- ✅ Red welp enemy (one tier, one color)
- ✅ Soul pickup → carry pool
- ✅ Single Red pyre with fill state
- ✅ Descent staircase prompt + deposit logic
- ✅ Main hall + upstairs scenes (placeholder geometry)
- ✅ HUD: HP bar, carried souls counter
- ✅ Death → respawn in main hall, clear unbanked souls
- ❌ Skill system / casts / modifiers (Phase 2)
- ❌ Multiple colors / corners (Phase 3)
- ❌ Pyre milestones / hub features (Phase 4)
- ❌ Boss fight (Phase 5)
- ❌ Audio / polish (Phase 6)
- ❌ Save/load (Phase 4)

**Acceptance test for Phase 1 done:**
A player can spawn in the main hall, walk to the upstairs staircase, fight Red welps with the sword, pick up Red minor souls, walk to the descent staircase, deposit souls into the Red pyre (fill increases), and respawn in the main hall with full HP and 0 carried souls. Dying upstairs respawns them in main hall with 0 souls and lost run state. The Red pyre persists its fill across scene transitions.

---

## File structure

**Created in this phase:**

```
new-chance/
├── addons/
│   └── gdUnit4/                          # Cloned in Task 1
├── scenes/
│   ├── world/
│   │   ├── main_hall.tscn                # Hub
│   │   └── upstairs.tscn                 # Single arena
│   ├── entities/
│   │   ├── player.tscn
│   │   └── welp.tscn                     # Red welp (Phase 1 only color)
│   ├── interactables/
│   │   ├── pyre.tscn
│   │   ├── soul_pickup.tscn
│   │   └── descent_staircase.tscn
│   └── ui/
│       ├── hud.tscn
│       └── descent_prompt.tscn
├── scripts/
│   ├── core/
│   │   ├── game_state.gd                 # Autoload singleton
│   │   └── soul_economy.gd               # Autoload singleton
│   ├── entities/
│   │   ├── player.gd
│   │   ├── sword.gd
│   │   └── welp.gd
│   ├── interactables/
│   │   ├── pyre.gd
│   │   ├── soul_pickup.gd
│   │   └── descent_staircase.gd
│   └── ui/
│       ├── hud.gd
│       └── descent_prompt.gd
├── test/
│   ├── test_game_state.gd
│   ├── test_soul_economy.gd
│   ├── test_pyre.gd
│   └── test_player.gd
├── project.godot                         # Modified: register autoloads, input map
└── .gitignore                            # Modified: add addons/gdUnit4 cache files if any
```

**File responsibilities:**

| File | Single responsibility |
|---|---|
| `scripts/core/game_state.gd` | Track current location (main hall / upstairs), emit transitions, drive scene swaps |
| `scripts/core/soul_economy.gd` | Hold carry pool + pyre fills; deposit math; clearing logic |
| `scripts/entities/player.gd` | Player movement, dash, HP, death; aggregate Sword child |
| `scripts/entities/sword.gd` | Auto-melee timer, hit detection, damage application |
| `scripts/entities/welp.gd` | Welp AI (chase + contact attack), HP, soul drop on death |
| `scripts/interactables/pyre.gd` | Visual fill response to SoulEconomy state for one color |
| `scripts/interactables/soul_pickup.gd` | Pickup collision → call SoulEconomy.add_to_carry; queue_free |
| `scripts/interactables/descent_staircase.gd` | Trigger area; show DescentPrompt; on confirm: deposit, transition, respawn |
| `scripts/ui/hud.gd` | Display HP and carried-soul counts; bind to SoulEconomy + Player signals |
| `scripts/ui/descent_prompt.gd` | Modal preview UI; emit confirm/cancel signals |

---

## Task 1: Project scaffold + GdUnit4 install

**Files:**
- Create: `addons/gdUnit4/` (cloned)
- Create folders: `scenes/world/`, `scenes/entities/`, `scenes/interactables/`, `scenes/ui/`, `scripts/core/`, `scripts/entities/`, `scripts/interactables/`, `scripts/ui/`, `test/`
- Modify: `project.godot` (add autoloads, input map)

- [ ] **Step 1: Clone GdUnit4 into addons folder**

```bash
cd /c/Users/wyenk/OneDrive/Documents/godot/new-chance
git clone --depth 1 https://github.com/MikeSchulze/gdUnit4.git addons/gdUnit4
```

- [ ] **Step 2: Create project folder structure**

```bash
mkdir -p scenes/world scenes/entities scenes/interactables scenes/ui
mkdir -p scripts/core scripts/entities scripts/interactables scripts/ui
mkdir -p test
```

- [ ] **Step 3: Open Godot Editor, enable GdUnit4 plugin**

Manual: open `project.godot` in Godot. Project → Project Settings → Plugins tab → check **GdUnit4** to enable. Save.

The editor will write the plugin entry into `project.godot` automatically.

- [ ] **Step 4: Add input action `dash` to InputMap**

Manual: in Godot, Project → Project Settings → Input Map tab. Add new action `dash`, bind to **Space** keyboard key. Save.

The editor will append:
```ini
[input]

dash={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":32,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

- [ ] **Step 5: Verify GdUnit4 runs from CLI**

Run:
```bash
cd /c/Users/wyenk/OneDrive/Documents/godot/new-chance
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
```
Expected: GdUnit4 starts, finds 0 tests, exits cleanly with exit code 0 (no tests to run yet — that's fine).

- [ ] **Step 6: Commit**

```bash
git add addons/gdUnit4 project.godot scenes scripts test
git commit -m "chore: install GdUnit4 + scaffold project folders"
```

---

## Task 2: GameState autoload — location tracking

**Files:**
- Create: `scripts/core/game_state.gd`
- Create: `test/test_game_state.gd`
- Modify: `project.godot` (register autoload)

- [ ] **Step 1: Write the failing test**

Create `test/test_game_state.gd`:

```gdscript
# GdUnit generated TestSuite
extends GdUnitTestSuite

const GameStateScript = preload("res://scripts/core/game_state.gd")

var gs: Node

func before_test() -> void:
    gs = auto_free(GameStateScript.new())
    add_child(gs)

func test_default_location_is_main_hall() -> void:
    assert_that(gs.current_location).is_equal(GameStateScript.Location.MAIN_HALL)

func test_transition_changes_location() -> void:
    gs.transition_to(GameStateScript.Location.UPSTAIRS)
    assert_that(gs.current_location).is_equal(GameStateScript.Location.UPSTAIRS)

func test_transition_emits_signal() -> void:
    var monitor := monitor_signals(gs)
    gs.transition_to(GameStateScript.Location.UPSTAIRS)
    await assert_signal(gs).is_emitted("location_changed", [GameStateScript.Location.UPSTAIRS])
```

- [ ] **Step 2: Run test — verify it fails**

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_game_state.gd --ignoreHeadlessMode
```
Expected: FAIL with "preload failed" or "cannot find script".

- [ ] **Step 3: Implement GameState minimal**

Create `scripts/core/game_state.gd`:

```gdscript
extends Node

enum Location { MAIN_HALL, UPSTAIRS }

signal location_changed(new_location: Location)

var current_location: Location = Location.MAIN_HALL

func transition_to(location: Location) -> void:
    if location == current_location:
        return
    current_location = location
    location_changed.emit(location)
```

- [ ] **Step 4: Run test — verify it passes**

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_game_state.gd --ignoreHeadlessMode
```
Expected: 3 tests pass, exit 0.

- [ ] **Step 5: Register GameState as autoload**

Manual: Godot → Project Settings → Globals/Autoload tab. Add `scripts/core/game_state.gd` with name `GameState`, enable.

`project.godot` will gain:
```ini
[autoload]
GameState="*res://scripts/core/game_state.gd"
```

- [ ] **Step 6: Commit**

```bash
git add scripts/core/game_state.gd test/test_game_state.gd project.godot
git commit -m "feat(core): add GameState autoload with location enum"
```

---

## Task 3: SoulEconomy autoload — carry pool, pyre fills, deposit math

**Files:**
- Create: `scripts/core/soul_economy.gd`
- Create: `test/test_soul_economy.gd`
- Modify: `project.godot` (register autoload)

- [ ] **Step 1: Write the failing tests**

Create `test/test_soul_economy.gd`:

```gdscript
extends GdUnitTestSuite

const SoulEconomyScript = preload("res://scripts/core/soul_economy.gd")

var econ: Node

func before_test() -> void:
    econ = auto_free(SoulEconomyScript.new())
    add_child(econ)

func test_carry_starts_empty() -> void:
    assert_that(econ.carry_count("red", "minor")).is_equal(0)

func test_pyre_starts_empty() -> void:
    assert_that(econ.pyre_fill("red")).is_equal(0)

func test_add_to_carry_increments_count() -> void:
    econ.add_to_carry("red", "minor", 3)
    assert_that(econ.carry_count("red", "minor")).is_equal(3)

func test_deposit_moves_carry_to_pyres_minor() -> void:
    econ.add_to_carry("red", "minor", 10)
    econ.deposit_to_pyres()
    assert_that(econ.carry_count("red", "minor")).is_equal(0)
    assert_that(econ.pyre_fill("red")).is_equal(10)

func test_pyre_caps_at_250() -> void:
    econ.add_to_carry("red", "minor", 300)
    econ.deposit_to_pyres()
    assert_that(econ.pyre_fill("red")).is_equal(250)

func test_clear_carry_zeroes_pool() -> void:
    econ.add_to_carry("red", "minor", 5)
    econ.clear_carry()
    assert_that(econ.carry_count("red", "minor")).is_equal(0)

func test_pyre_filled_signal_at_100_percent() -> void:
    var monitor := monitor_signals(econ)
    econ.add_to_carry("red", "minor", 250)
    econ.deposit_to_pyres()
    await assert_signal(econ).is_emitted("pyre_filled", ["red"])

func test_pyre_filled_signal_only_once() -> void:
    econ.add_to_carry("red", "minor", 250)
    econ.deposit_to_pyres()
    var monitor := monitor_signals(econ)
    econ.add_to_carry("red", "minor", 5)
    econ.deposit_to_pyres()
    await assert_signal(econ).is_not_emitted("pyre_filled")
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_soul_economy.gd --ignoreHeadlessMode
```
Expected: 8 tests fail.

- [ ] **Step 3: Implement SoulEconomy**

Create `scripts/core/soul_economy.gd`:

```gdscript
extends Node

const PYRE_CAP: int = 250
const COLORS: Array[String] = ["red", "blue", "green", "purple", "gold", "white"]
const SOUL_VALUES: Dictionary = {
    "minor": 1,
    "elder": 10,
}

signal pyre_filled(color: String)

var _carry: Dictionary = {}     # { color: { tier: count } }
var _pyres: Dictionary = {}     # { color: int (0..PYRE_CAP) }
var _filled_pyres: Dictionary = {}  # { color: bool } — track which already emitted filled signal

func _ready() -> void:
    _reset_state()

func _reset_state() -> void:
    _carry.clear()
    _pyres.clear()
    _filled_pyres.clear()
    for color in COLORS:
        _carry[color] = {"minor": 0, "elder": 0}
        _pyres[color] = 0
        _filled_pyres[color] = false

func add_to_carry(color: String, tier: String, count: int) -> void:
    assert(color in COLORS, "unknown color: %s" % color)
    assert(tier in SOUL_VALUES, "unknown tier: %s" % tier)
    _carry[color][tier] += count

func carry_count(color: String, tier: String) -> int:
    return _carry[color][tier]

func pyre_fill(color: String) -> int:
    return _pyres[color]

func clear_carry() -> void:
    for color in COLORS:
        _carry[color] = {"minor": 0, "elder": 0}

func deposit_to_pyres() -> void:
    for color in COLORS:
        var fill_units: int = (
            _carry[color]["minor"] * SOUL_VALUES["minor"]
            + _carry[color]["elder"] * SOUL_VALUES["elder"]
        )
        if fill_units == 0:
            continue
        var new_fill: int = min(_pyres[color] + fill_units, PYRE_CAP)
        var was_full: bool = _filled_pyres[color]
        _pyres[color] = new_fill
        if new_fill >= PYRE_CAP and not was_full:
            _filled_pyres[color] = true
            pyre_filled.emit(color)
    clear_carry()

func has_any_carry() -> bool:
    for color in COLORS:
        if _carry[color]["minor"] > 0 or _carry[color]["elder"] > 0:
            return true
    return false
```

- [ ] **Step 4: Run tests — verify they pass**

Run the same command from Step 2.
Expected: 8 tests pass, exit 0.

- [ ] **Step 5: Register SoulEconomy as autoload**

Manual: Godot → Project Settings → Globals/Autoload. Add `scripts/core/soul_economy.gd` named `SoulEconomy`, enable.

- [ ] **Step 6: Commit**

```bash
git add scripts/core/soul_economy.gd test/test_soul_economy.gd project.godot
git commit -m "feat(core): add SoulEconomy autoload with carry/deposit/pyre math"
```

---

## Task 4: Pyre scene + script

**Files:**
- Create: `scenes/interactables/pyre.tscn`
- Create: `scripts/interactables/pyre.gd`
- Create: `test/test_pyre.gd`

- [ ] **Step 1: Write the failing test (logic only)**

Create `test/test_pyre.gd`:

```gdscript
extends GdUnitTestSuite

const PyreScript = preload("res://scripts/interactables/pyre.gd")

var pyre: Node3D

func before_test() -> void:
    # autoloads are running; reset their state for isolation
    SoulEconomy._reset_state()
    pyre = auto_free(PyreScript.new())
    pyre.color = "red"
    add_child(pyre)
    # _ready runs

func test_pyre_reads_initial_fill_from_economy() -> void:
    SoulEconomy.add_to_carry("red", "minor", 50)
    SoulEconomy.deposit_to_pyres()
    pyre.refresh_visual()  # method called manually for test
    assert_that(pyre.fill_ratio).is_equal_approx(50.0 / 250.0, 0.001)

func test_pyre_responds_to_pyre_filled_signal() -> void:
    SoulEconomy.add_to_carry("red", "minor", 250)
    SoulEconomy.deposit_to_pyres()
    await get_tree().process_frame
    assert_that(pyre.is_fully_lit).is_true()
```

- [ ] **Step 2: Run tests — expect failures**

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_pyre.gd --ignoreHeadlessMode
```
Expected: 2 tests fail (script doesn't exist).

- [ ] **Step 3: Implement Pyre script**

Create `scripts/interactables/pyre.gd` (final, complete contents — do not duplicate `_ready`):

```gdscript
extends Node3D

@export var color: String = "red"

var fill_ratio: float = 0.0
var is_fully_lit: bool = false

@onready var _flame_mesh: MeshInstance3D = $Flame if has_node("Flame") else null

func _ready() -> void:
    SoulEconomy.pyre_filled.connect(_on_pyre_filled)
    set_process(true)
    refresh_visual()

func _process(_delta: float) -> void:
    # Polled refresh so partial pyre fills update visuals between pyre_filled signals.
    var fill: int = SoulEconomy.pyre_fill(color)
    var new_ratio: float = float(fill) / float(SoulEconomy.PYRE_CAP)
    if not is_equal_approx(new_ratio, fill_ratio):
        refresh_visual()

func refresh_visual() -> void:
    var fill: int = SoulEconomy.pyre_fill(color)
    fill_ratio = float(fill) / float(SoulEconomy.PYRE_CAP)
    is_fully_lit = fill >= SoulEconomy.PYRE_CAP
    _apply_visual()

func _on_pyre_filled(filled_color: String) -> void:
    if filled_color == color:
        refresh_visual()

func _apply_visual() -> void:
    if _flame_mesh == null:
        return
    # Scale flame mesh height with fill (placeholder visual)
    _flame_mesh.scale = Vector3(1.0, 0.1 + fill_ratio * 1.5, 1.0)
    var mat: StandardMaterial3D = _flame_mesh.material_override as StandardMaterial3D
    if mat != null:
        mat.emission_energy_multiplier = 0.5 + fill_ratio * 4.0
```

- [ ] **Step 4: Build the scene `scenes/interactables/pyre.tscn`**

Manual in Godot:
1. New Scene → Other Node → Node3D, rename to **Pyre**
2. Attach script `scripts/interactables/pyre.gd`
3. Add child `MeshInstance3D` named **Base** with a CylinderMesh (radius 0.5, height 0.5)
4. Add child `MeshInstance3D` named **Flame** with a CapsuleMesh (radius 0.3, height 1.5), positioned at Y=0.75
5. On Flame: set Material Override → New StandardMaterial3D, Albedo Color = bright red (`Color(1.0, 0.3, 0.1)`), Emission enabled, Emission Color same red, Emission Energy = 2.0
6. Save as `scenes/interactables/pyre.tscn`

- [ ] **Step 5: Run tests — verify they pass**

Run the same command from Step 2.
Expected: 2 tests pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/interactables/pyre.gd scenes/interactables/pyre.tscn test/test_pyre.gd
git commit -m "feat(pyre): visual fill response wired to SoulEconomy"
```

---

## Task 5: Player base — movement + scene

**Files:**
- Create: `scenes/entities/player.tscn`
- Create: `scripts/entities/player.gd`
- Create: `test/test_player.gd`

- [ ] **Step 1: Write the failing test (HP and damage logic only — visuals manual)**

Create `test/test_player.gd`:

```gdscript
extends GdUnitTestSuite

const PlayerScript = preload("res://scripts/entities/player.gd")

var player: CharacterBody3D

func before_test() -> void:
    player = auto_free(CharacterBody3D.new())
    player.set_script(PlayerScript)
    add_child(player)
    # let _ready run
    await get_tree().process_frame

func test_player_starts_with_full_hp() -> void:
    assert_that(player.hp).is_equal(100)

func test_take_damage_reduces_hp() -> void:
    player.take_damage(30)
    assert_that(player.hp).is_equal(70)

func test_take_damage_clamped_at_zero() -> void:
    player.take_damage(150)
    assert_that(player.hp).is_equal(0)

func test_died_signal_emits_at_zero_hp() -> void:
    var monitor := monitor_signals(player)
    player.take_damage(150)
    await assert_signal(player).is_emitted("died")

func test_died_signal_emits_only_once() -> void:
    player.take_damage(150)
    var monitor := monitor_signals(player)
    player.take_damage(10)
    await assert_signal(player).is_not_emitted("died")

func test_reset_restores_hp() -> void:
    player.take_damage(50)
    player.reset_run_state()
    assert_that(player.hp).is_equal(100)
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_player.gd --ignoreHeadlessMode
```
Expected: 6 tests fail.

- [ ] **Step 3: Implement Player script**

Create `scripts/entities/player.gd`:

```gdscript
extends CharacterBody3D

const MAX_HP: int = 100
const MOVE_SPEED: float = 5.0

signal died
signal hp_changed(new_hp: int)

var hp: int = MAX_HP
var _is_dead: bool = false

func _physics_process(_delta: float) -> void:
    if _is_dead:
        return
    var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    var direction: Vector3 = Vector3(input_dir.x, 0, input_dir.y)
    velocity.x = direction.x * MOVE_SPEED
    velocity.z = direction.z * MOVE_SPEED
    velocity.y -= 9.8 * _delta if not is_on_floor() else 0.0
    move_and_slide()

func take_damage(amount: int) -> void:
    if _is_dead:
        return
    hp = max(0, hp - amount)
    hp_changed.emit(hp)
    if hp == 0:
        _is_dead = true
        died.emit()

func reset_run_state() -> void:
    hp = MAX_HP
    _is_dead = false
    hp_changed.emit(hp)
```

- [ ] **Step 4: Run tests — verify they pass**

Run the same command from Step 2.
Expected: 6 tests pass.

- [ ] **Step 5: Build the scene `scenes/entities/player.tscn`**

Manual in Godot:
1. New Scene → Other Node → CharacterBody3D, rename to **Player**
2. Attach script `scripts/entities/player.gd`
3. Add child `CollisionShape3D` with a CapsuleShape3D (radius 0.4, height 1.6)
4. Add child `MeshInstance3D` named **Mesh** with a CapsuleMesh (radius 0.4, height 1.6) — placeholder skeleton
5. Set Mesh material override → new StandardMaterial3D with albedo `Color(0.85, 0.83, 0.78)` (bone)
6. Save as `scenes/entities/player.tscn`

- [ ] **Step 6: Manual smoke test — drop player into a temp scene**

Manual: New Scene → Node3D as root, add a static Plane (StaticBody3D + CollisionShape3D + MeshInstance3D plane). Instance Player as child. Add a Camera3D pointed down. Press F5 to run. Use arrow keys → player should move on the plane. WASD does NOT move (using `ui_left/right/up/down` defaults to arrows).

- [ ] **Step 7: Add WASD bindings to existing input actions**

Manual: Project Settings → Input Map. For each of `ui_left`, `ui_right`, `ui_up`, `ui_down`, add the corresponding **A / D / W / S** keyboard bindings.

- [ ] **Step 8: Re-run smoke test**

Manual: WASD now also moves the player. Discard the temp scene.

- [ ] **Step 9: Commit**

```bash
git add scripts/entities/player.gd scenes/entities/player.tscn test/test_player.gd project.godot
git commit -m "feat(player): movement, HP, death signal with WASD bindings"
```

---

## Task 6: Player dash

**Files:**
- Modify: `scripts/entities/player.gd`
- Modify: `test/test_player.gd`

- [ ] **Step 1: Add failing tests for dash logic**

Append to `test/test_player.gd`:

```gdscript
func test_dash_starts_off_cooldown() -> void:
    assert_that(player.can_dash()).is_true()

func test_dash_triggers_cooldown() -> void:
    player.try_dash(Vector3(1, 0, 0))
    assert_that(player.can_dash()).is_false()

func test_dash_cooldown_expires() -> void:
    player.try_dash(Vector3(1, 0, 0))
    # Simulate 2 seconds passing
    player._dash_cooldown_remaining = 0.0
    assert_that(player.can_dash()).is_true()

func test_dash_returns_false_on_cooldown() -> void:
    player.try_dash(Vector3(1, 0, 0))
    assert_that(player.try_dash(Vector3(1, 0, 0))).is_false()

func test_dash_grants_iframes() -> void:
    player.try_dash(Vector3(1, 0, 0))
    assert_that(player.is_invincible()).is_true()

func test_take_damage_during_iframes_does_nothing() -> void:
    player.try_dash(Vector3(1, 0, 0))
    player.take_damage(50)
    assert_that(player.hp).is_equal(100)
```

- [ ] **Step 2: Run tests — verify dash tests fail**

Run from Task 5 Step 2.
Expected: prior 6 tests pass + 6 new tests fail.

- [ ] **Step 3: Implement dash in Player script**

Modify `scripts/entities/player.gd` — add constants, state, and methods:

```gdscript
const DASH_DISTANCE: float = 4.0
const DASH_DURATION: float = 0.15
const DASH_COOLDOWN: float = 2.0
const IFRAME_DURATION: float = 0.2

var _dash_cooldown_remaining: float = 0.0
var _iframe_remaining: float = 0.0
var _dash_velocity: Vector3 = Vector3.ZERO
var _dash_time_remaining: float = 0.0

func _process(delta: float) -> void:
    if _dash_cooldown_remaining > 0.0:
        _dash_cooldown_remaining = max(0.0, _dash_cooldown_remaining - delta)
    if _iframe_remaining > 0.0:
        _iframe_remaining = max(0.0, _iframe_remaining - delta)
    if _dash_time_remaining > 0.0:
        _dash_time_remaining = max(0.0, _dash_time_remaining - delta)
    if Input.is_action_just_pressed("dash"):
        var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
        var dash_dir: Vector3 = Vector3(input_dir.x, 0, input_dir.y)
        if dash_dir.length() > 0.01:
            try_dash(dash_dir.normalized())

func can_dash() -> bool:
    return _dash_cooldown_remaining <= 0.0 and not _is_dead

func try_dash(direction: Vector3) -> bool:
    if not can_dash():
        return false
    _dash_velocity = direction * (DASH_DISTANCE / DASH_DURATION)
    _dash_time_remaining = DASH_DURATION
    _dash_cooldown_remaining = DASH_COOLDOWN
    _iframe_remaining = IFRAME_DURATION
    return true

func is_invincible() -> bool:
    return _iframe_remaining > 0.0
```

Modify `_physics_process` to use dash velocity when active:

```gdscript
func _physics_process(delta: float) -> void:
    if _is_dead:
        return
    if _dash_time_remaining > 0.0:
        velocity.x = _dash_velocity.x
        velocity.z = _dash_velocity.z
    else:
        var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
        var direction: Vector3 = Vector3(input_dir.x, 0, input_dir.y)
        velocity.x = direction.x * MOVE_SPEED
        velocity.z = direction.z * MOVE_SPEED
    velocity.y -= 9.8 * delta if not is_on_floor() else 0.0
    move_and_slide()
```

Modify `take_damage` to respect iframes:

```gdscript
func take_damage(amount: int) -> void:
    if _is_dead or is_invincible():
        return
    hp = max(0, hp - amount)
    hp_changed.emit(hp)
    if hp == 0:
        _is_dead = true
        died.emit()
```

- [ ] **Step 4: Run tests — verify they pass**

Run from Task 5 Step 2.
Expected: 12 tests pass.

- [ ] **Step 5: Manual smoke test**

Manual: re-create the temp scene from Task 5 Step 6. Press F5. Press Space while moving — player should burst forward.

- [ ] **Step 6: Commit**

```bash
git add scripts/entities/player.gd test/test_player.gd
git commit -m "feat(player): Space dash with cooldown and iframes"
```

---

## Task 7: Sword auto-melee

**Files:**
- Create: `scripts/entities/sword.gd`
- Modify: `scenes/entities/player.tscn` (add Sword child)

- [ ] **Step 1: Implement Sword script**

Create `scripts/entities/sword.gd`:

```gdscript
extends Area3D

const SWING_INTERVAL: float = 1.0  # seconds per swing
const BASE_DAMAGE: int = 15

signal hit_enemy(enemy: Node, damage: int)

var _swing_cooldown: float = 0.0

func _process(delta: float) -> void:
    if _swing_cooldown > 0.0:
        _swing_cooldown = max(0.0, _swing_cooldown - delta)
        return
    var enemies: Array = get_overlapping_bodies().filter(_is_enemy)
    if enemies.size() == 0:
        return
    var nearest: Node = enemies[0]  # Phase 1: just use first found
    if nearest.has_method("take_damage"):
        nearest.take_damage(BASE_DAMAGE)
    hit_enemy.emit(nearest, BASE_DAMAGE)
    _swing_cooldown = SWING_INTERVAL

func _is_enemy(body: Node) -> bool:
    return body.is_in_group("enemy")
```

- [ ] **Step 2: Add Sword to Player scene**

Manual in Godot:
1. Open `scenes/entities/player.tscn`
2. Add child `Area3D` to root, rename to **Sword**
3. Attach script `scripts/entities/sword.gd`
4. Add child `CollisionShape3D` to Sword with a SphereShape3D (radius 2.0) — melee range
5. Save scene

- [ ] **Step 3: Set the Sword Area3D collision mask**

Manual in Godot:
1. Select Sword node, in Inspector → Collision → Layer 0, Mask checked for Layer 2 (we'll put enemies on layer 2 in Task 8)
2. Save

- [ ] **Step 4: Manual smoke test deferred — Sword has no enemies to swing at yet**

Will be tested in Task 8 once Welp exists.

- [ ] **Step 5: Commit**

```bash
git add scripts/entities/sword.gd scenes/entities/player.tscn
git commit -m "feat(sword): auto-melee Area3D with damage signal"
```

---

## Task 8: Welp enemy

**Files:**
- Create: `scenes/entities/welp.tscn`
- Create: `scripts/entities/welp.gd`

- [ ] **Step 1: Implement Welp script**

Create `scripts/entities/welp.gd`:

```gdscript
extends CharacterBody3D

const MAX_HP: int = 30
const MOVE_SPEED: float = 3.0
const ATTACK_DAMAGE: int = 10
const ATTACK_INTERVAL: float = 1.5
const ATTACK_RANGE: float = 1.5

@export var color: String = "red"

signal died(welp: Node, color: String)

var hp: int = MAX_HP
var _attack_cooldown: float = 0.0
var _player: Node = null
var _is_dead: bool = false

func _ready() -> void:
    add_to_group("enemy")
    collision_layer = 2  # match Sword mask
    _find_player()

func _physics_process(delta: float) -> void:
    if _is_dead:
        return
    if _player == null or not is_instance_valid(_player):
        _find_player()
        if _player == null:
            return
    var to_player: Vector3 = _player.global_position - global_position
    to_player.y = 0.0
    var distance: float = to_player.length()
    if distance > ATTACK_RANGE:
        velocity.x = to_player.normalized().x * MOVE_SPEED
        velocity.z = to_player.normalized().z * MOVE_SPEED
    else:
        velocity.x = 0.0
        velocity.z = 0.0
        if _attack_cooldown <= 0.0:
            _attack_player()
            _attack_cooldown = ATTACK_INTERVAL
    if _attack_cooldown > 0.0:
        _attack_cooldown = max(0.0, _attack_cooldown - delta)
    velocity.y -= 9.8 * delta if not is_on_floor() else 0.0
    move_and_slide()

func _find_player() -> void:
    var players: Array = get_tree().get_nodes_in_group("player")
    if players.size() > 0:
        _player = players[0]

func _attack_player() -> void:
    if _player != null and _player.has_method("take_damage"):
        _player.take_damage(ATTACK_DAMAGE)

func take_damage(amount: int) -> void:
    if _is_dead:
        return
    hp = max(0, hp - amount)
    if hp == 0:
        _is_dead = true
        died.emit(self, color)
        queue_free()
```

- [ ] **Step 2: Build Welp scene**

Manual in Godot:
1. New Scene → Other Node → CharacterBody3D, rename to **Welp**
2. Attach script `scripts/entities/welp.gd`
3. Add child `CollisionShape3D` with BoxShape3D (size 1.0 × 1.0 × 1.0)
4. Add child `MeshInstance3D` named **Mesh** with BoxMesh (size 1.0 × 1.0 × 1.0)
5. Set Mesh material override → StandardMaterial3D albedo `Color(0.7, 0.15, 0.15)` (red welp)
6. Save as `scenes/entities/welp.tscn`

- [ ] **Step 3: Add Player to "player" group**

Manual in Godot:
1. Open `scenes/entities/player.tscn`
2. Select Player root → Node tab → Groups → add `player`
3. Save

- [ ] **Step 4: Manual smoke test — Player vs Welp combat**

Manual: temp scene with floor, Player instance, Welp instance positioned 5m away. Run F5. Welp should chase and bite the player. Player's sword should auto-swing on contact and kill the welp in ~2 swings (15 damage × 2 ≥ 30 HP).

- [ ] **Step 5: Commit**

```bash
git add scripts/entities/welp.gd scenes/entities/welp.tscn scenes/entities/player.tscn
git commit -m "feat(welp): chase-and-bite enemy with HP, group registration"
```

---

## Task 9: Soul pickup

**Files:**
- Create: `scenes/interactables/soul_pickup.tscn`
- Create: `scripts/interactables/soul_pickup.gd`
- Modify: `scripts/entities/welp.gd` (spawn pickup on death)

- [ ] **Step 1: Implement Soul pickup script**

Create `scripts/interactables/soul_pickup.gd`:

```gdscript
extends Area3D

@export var color: String = "red"
@export var tier: String = "minor"

func _ready() -> void:
    monitoring = true
    body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
    if body.is_in_group("player"):
        SoulEconomy.add_to_carry(color, tier, 1)
        queue_free()
```

- [ ] **Step 2: Build pickup scene**

Manual in Godot:
1. New Scene → Other Node → Area3D, rename to **SoulPickup**
2. Attach script
3. Add child `CollisionShape3D` with SphereShape3D (radius 0.6)
4. Add child `MeshInstance3D` named **Mesh** with SphereMesh (radius 0.3)
5. Mesh material → StandardMaterial3D, albedo `Color(1.0, 0.4, 0.2)` (red glow), Emission enabled, Emission Color same red, Emission Energy 3.0
6. Save as `scenes/interactables/soul_pickup.tscn`

- [ ] **Step 3: Wire welp death to spawn pickup**

Modify `scripts/entities/welp.gd` — change the `take_damage` death branch to spawn a pickup at the welp's position before queue_free:

```gdscript
const SOUL_PICKUP_SCENE: PackedScene = preload("res://scenes/interactables/soul_pickup.tscn")

func take_damage(amount: int) -> void:
    if _is_dead:
        return
    hp = max(0, hp - amount)
    if hp == 0:
        _is_dead = true
        var pickup: Area3D = SOUL_PICKUP_SCENE.instantiate()
        pickup.color = color
        pickup.tier = "minor"
        pickup.global_position = global_position
        get_parent().add_child(pickup)
        died.emit(self, color)
        queue_free()
```

- [ ] **Step 4: Manual smoke test — kill welp, walk into the soul**

Manual: temp scene with Player + Welp. Kill welp with sword. A red glowing sphere drops. Walk into it. SoulEconomy should now have 1 red minor soul. Verify by adding a temporary `print(SoulEconomy.carry_count("red", "minor"))` somewhere or by inspecting in next task's HUD.

- [ ] **Step 5: Commit**

```bash
git add scripts/interactables/soul_pickup.gd scenes/interactables/soul_pickup.tscn scripts/entities/welp.gd
git commit -m "feat(soul-pickup): welps drop pickups; player collision adds to carry"
```

---

## Task 10: HUD

**Files:**
- Create: `scenes/ui/hud.tscn`
- Create: `scripts/ui/hud.gd`

- [ ] **Step 1: Implement HUD script**

Create `scripts/ui/hud.gd`:

```gdscript
extends CanvasLayer

@onready var _hp_label: Label = $Margin/VBox/HP
@onready var _souls_label: Label = $Margin/VBox/Souls

var _player: Node = null

func _ready() -> void:
    set_process(true)
    _bind_to_player()

func _bind_to_player() -> void:
    var players: Array = get_tree().get_nodes_in_group("player")
    if players.size() > 0:
        _player = players[0]
        if not _player.hp_changed.is_connected(_on_hp_changed):
            _player.hp_changed.connect(_on_hp_changed)
        _on_hp_changed(_player.hp)

func _process(_delta: float) -> void:
    if _player == null or not is_instance_valid(_player):
        _bind_to_player()
    var red_minor: int = SoulEconomy.carry_count("red", "minor")
    _souls_label.text = "Souls (red): %d" % red_minor

func _on_hp_changed(new_hp: int) -> void:
    _hp_label.text = "HP: %d / 100" % new_hp
```

- [ ] **Step 2: Build HUD scene**

Manual in Godot:
1. New Scene → User Interface → CanvasLayer, rename to **HUD**
2. Attach script
3. Add child `MarginContainer` named **Margin**, set anchors full-rect, margins 16
4. Add child `VBoxContainer` named **VBox**
5. Add `Label` named **HP**, text "HP: 100 / 100"
6. Add `Label` named **Souls**, text "Souls (red): 0"
7. Save as `scenes/ui/hud.tscn`

- [ ] **Step 3: Manual smoke test — HUD shows live state**

Manual: temp scene with Player + Welp + HUD instance + soul pickup mechanism. Watch HP drop on welp hit, Souls count increase on pickup.

- [ ] **Step 4: Commit**

```bash
git add scripts/ui/hud.gd scenes/ui/hud.tscn
git commit -m "feat(hud): display HP and red minor soul carry count"
```

---

## Task 11: Descent prompt UI

**Files:**
- Create: `scenes/ui/descent_prompt.tscn`
- Create: `scripts/ui/descent_prompt.gd`

- [ ] **Step 1: Implement Descent prompt script**

Create `scripts/ui/descent_prompt.gd`:

```gdscript
extends CanvasLayer

signal confirmed
signal canceled

@onready var _summary_label: Label = $Center/Panel/VBox/Summary
@onready var _confirm_button: Button = $Center/Panel/VBox/Buttons/Confirm
@onready var _cancel_button: Button = $Center/Panel/VBox/Buttons/Cancel

func _ready() -> void:
    visible = false
    _confirm_button.pressed.connect(_on_confirm)
    _cancel_button.pressed.connect(_on_cancel)

func show_prompt() -> void:
    var red_minor: int = SoulEconomy.carry_count("red", "minor")
    var fill_delta: int = red_minor  # 1/1 in Phase 1
    var current_fill: int = SoulEconomy.pyre_fill("red")
    var new_fill: int = min(current_fill + fill_delta, SoulEconomy.PYRE_CAP)
    _summary_label.text = (
        "Deposit %d red minor souls.\n" % red_minor
        + "Red pyre: %d → %d / %d\n" % [current_fill, new_fill, SoulEconomy.PYRE_CAP]
        + "All current skills will be lost."
    )
    visible = true
    get_tree().paused = true

func hide_prompt() -> void:
    visible = false
    get_tree().paused = false

func _on_confirm() -> void:
    hide_prompt()
    confirmed.emit()

func _on_cancel() -> void:
    hide_prompt()
    canceled.emit()

func _process(_delta: float) -> void:
    if visible and Input.is_action_just_pressed("ui_cancel"):
        _on_cancel()
```

- [ ] **Step 2: Build descent prompt scene**

Manual in Godot:
1. New Scene → User Interface → CanvasLayer, rename to **DescentPrompt**
2. Attach script. **Important:** set Process Mode = "Always" so the script runs while paused.
3. Add `CenterContainer` named **Center**, anchors full-rect
4. Add `PanelContainer` named **Panel** as child of Center
5. Add `VBoxContainer` named **VBox** as child of Panel, separation 12, padding 24
6. Add `Label` named **Summary**, autowrap on
7. Add `HBoxContainer` named **Buttons**, alignment Center, separation 16
8. Add `Button` named **Confirm**, text "Descend & deposit"
9. Add `Button` named **Cancel**, text "Cancel"
10. Save as `scenes/ui/descent_prompt.tscn`

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/descent_prompt.gd scenes/ui/descent_prompt.tscn
git commit -m "feat(descent-prompt): pause-mode UI with deposit preview"
```

---

## Task 12: Descent staircase

**Files:**
- Create: `scenes/interactables/descent_staircase.tscn`
- Create: `scripts/interactables/descent_staircase.gd`

- [ ] **Step 1: Implement DescentStaircase script**

Create `scripts/interactables/descent_staircase.gd`:

```gdscript
extends Area3D

@export var prompt_path: NodePath  # Path to a DescentPrompt instance in the scene tree

var _prompt: CanvasLayer = null
var _player_in_zone: bool = false

func _ready() -> void:
    body_entered.connect(_on_body_entered)
    body_exited.connect(_on_body_exited)
    if prompt_path != NodePath(""):
        _prompt = get_node(prompt_path)

func _on_body_entered(body: Node) -> void:
    if not body.is_in_group("player"):
        return
    _player_in_zone = true
    if _prompt == null:
        return
    _prompt.show_prompt()
    if not _prompt.confirmed.is_connected(_on_confirmed):
        _prompt.confirmed.connect(_on_confirmed)
    if not _prompt.canceled.is_connected(_on_canceled):
        _prompt.canceled.connect(_on_canceled)

func _on_body_exited(body: Node) -> void:
    if body.is_in_group("player"):
        _player_in_zone = false

func _on_confirmed() -> void:
    SoulEconomy.deposit_to_pyres()
    GameState.transition_to(GameState.Location.MAIN_HALL)

func _on_canceled() -> void:
    pass  # player stays upstairs; nothing to do
```

- [ ] **Step 2: Build descent staircase scene**

Manual in Godot:
1. New Scene → Other Node → Area3D, rename to **DescentStaircase**
2. Attach script
3. Add child `CollisionShape3D` with BoxShape3D (size 2 × 2 × 2)
4. Add child `MeshInstance3D` named **Visual** with BoxMesh (size 2 × 0.2 × 2) — flat tile to indicate the spot
5. Material override: dark gray albedo (`Color(0.2, 0.2, 0.25)`), emission disabled
6. Save as `scenes/interactables/descent_staircase.tscn`

- [ ] **Step 3: Commit**

```bash
git add scripts/interactables/descent_staircase.gd scenes/interactables/descent_staircase.tscn
git commit -m "feat(staircase): descent trigger area wired to prompt + deposit + transition"
```

---

## Task 13: GameState scene-swap routing

**Files:**
- Modify: `scripts/core/game_state.gd`
- Modify: `test/test_game_state.gd`

- [ ] **Step 1: Add failing test for scene swap intent**

Append to `test/test_game_state.gd`:

```gdscript
func test_main_hall_scene_path() -> void:
    assert_that(GameStateScript.MAIN_HALL_SCENE_PATH).is_equal("res://scenes/world/main_hall.tscn")

func test_upstairs_scene_path() -> void:
    assert_that(GameStateScript.UPSTAIRS_SCENE_PATH).is_equal("res://scenes/world/upstairs.tscn")

func test_scene_path_for_location_returns_main_hall() -> void:
    assert_that(GameStateScript.scene_path_for(GameStateScript.Location.MAIN_HALL)).is_equal(GameStateScript.MAIN_HALL_SCENE_PATH)

func test_scene_path_for_location_returns_upstairs() -> void:
    assert_that(GameStateScript.scene_path_for(GameStateScript.Location.UPSTAIRS)).is_equal(GameStateScript.UPSTAIRS_SCENE_PATH)
```

- [ ] **Step 2: Run tests — verify they fail**

Run from Task 2 Step 4.
Expected: 4 new tests fail.

- [ ] **Step 3: Add constants and helper to GameState**

Modify `scripts/core/game_state.gd`:

```gdscript
extends Node

enum Location { MAIN_HALL, UPSTAIRS }

const MAIN_HALL_SCENE_PATH: String = "res://scenes/world/main_hall.tscn"
const UPSTAIRS_SCENE_PATH: String = "res://scenes/world/upstairs.tscn"

signal location_changed(new_location: Location)

var current_location: Location = Location.MAIN_HALL

static func scene_path_for(location: Location) -> String:
    match location:
        Location.MAIN_HALL:
            return MAIN_HALL_SCENE_PATH
        Location.UPSTAIRS:
            return UPSTAIRS_SCENE_PATH
        _:
            return ""

func transition_to(location: Location) -> void:
    if location == current_location:
        return
    current_location = location
    location_changed.emit(location)
    var path: String = scene_path_for(location)
    if path != "":
        # deferred so signal handlers run before swap
        get_tree().call_deferred("change_scene_to_file", path)
```

- [ ] **Step 4: Run tests — verify they pass**

Run from Task 2 Step 4.
Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/core/game_state.gd test/test_game_state.gd
git commit -m "feat(game-state): scene-path constants + scene swap on transition"
```

---

## Task 14: Main hall scene

**Files:**
- Create: `scenes/world/main_hall.tscn`

- [ ] **Step 1: Build the main hall scene**

Manual in Godot:
1. New Scene → Other Node → Node3D, rename to **MainHall**
2. Add child `WorldEnvironment` with new Environment, set Background → Sky → procedural, ambient light low (gloomy)
3. Add child `DirectionalLight3D` for general lighting (energy 0.6, warm color)
4. Add child `StaticBody3D` named **Floor** with CollisionShape3D (BoxShape3D 20 × 0.5 × 20) and MeshInstance3D (BoxMesh 20 × 0.5 × 20). Position at Y = -0.25. Material albedo `Color(0.25, 0.22, 0.2)` (stone).
5. Add 4 wall `StaticBody3D` blocks around the perimeter (BoxShapes 20 × 4 × 0.5 etc.). Material `Color(0.3, 0.27, 0.24)`.
6. Instance `scenes/interactables/pyre.tscn` as child, position at `Vector3(-3, 0, 0)`. Set its `color` to `red`.
7. Add a Marker3D named **PlayerSpawn** at `Vector3(0, 1, 5)`. This is where the player starts in the main hall.
8. Add a Marker3D named **UpstairsExit** at `Vector3(0, 0.1, -8)`. A simple visual cue for "go this way to head upstairs."
9. Add `Camera3D` named **Camera**. Set position `Vector3(0, 12, 8)`, rotation `Vector3(-55, 0, 0)`, projection Perspective, fov 60. (Top-down 3/4 angle.)
10. Add a child `Area3D` named **UpstairsTrigger** at the same spot as UpstairsExit, with a BoxShape3D (size 3 × 3 × 3). Add a small inline script (or the script below):

Add `scripts/world/main_hall_upstairs_trigger.gd`:

```gdscript
extends Area3D

func _ready() -> void:
    body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
    if body.is_in_group("player"):
        GameState.transition_to(GameState.Location.UPSTAIRS)
```

Attach this script to UpstairsTrigger.

11. Instance `scenes/entities/player.tscn` as child of MainHall. Position at PlayerSpawn (`Vector3(0, 1, 5)`).
12. Instance `scenes/ui/hud.tscn` as child.
13. Save as `scenes/world/main_hall.tscn`

- [ ] **Step 2: Set MainHall as the project main scene**

Manual: Project → Project Settings → General → Application → Run → Main Scene → set to `res://scenes/world/main_hall.tscn`. Save.

- [ ] **Step 3: Manual smoke test — main hall renders**

Manual: F5. Player spawns in stone room with one red pyre and a small dark tile in the back. HP 100, souls 0. Walking onto the dark tile transitions you to upstairs (which doesn't exist yet — Godot will error). That's fine for now.

- [ ] **Step 4: Commit**

```bash
git add scripts/world scenes/world/main_hall.tscn project.godot
git commit -m "feat(main-hall): pyre + stone room + transition trigger to upstairs"
```

---

## Task 15: Upstairs scene + welp spawner

**Files:**
- Create: `scenes/world/upstairs.tscn`
- Create: `scripts/world/welp_spawner.gd`

- [ ] **Step 1: Implement basic Welp spawner script**

Create `scripts/world/welp_spawner.gd`:

```gdscript
extends Node3D

const WELP_SCENE: PackedScene = preload("res://scenes/entities/welp.tscn")

@export var spawn_interval: float = 3.0
@export var max_alive: int = 5
@export var spawn_radius: float = 12.0

var _timer: float = 0.0
var _alive_count: int = 0

func _process(delta: float) -> void:
    _timer += delta
    if _timer >= spawn_interval and _alive_count < max_alive:
        _timer = 0.0
        _spawn_welp()

func _spawn_welp() -> void:
    var welp: CharacterBody3D = WELP_SCENE.instantiate()
    var angle: float = randf() * TAU
    var offset: Vector3 = Vector3(cos(angle) * spawn_radius, 1.0, sin(angle) * spawn_radius)
    welp.global_position = global_position + offset
    welp.died.connect(_on_welp_died)
    get_parent().add_child(welp)
    _alive_count += 1

func _on_welp_died(_welp: Node, _color: String) -> void:
    _alive_count = max(0, _alive_count - 1)
```

- [ ] **Step 2: Build upstairs scene**

Manual in Godot:
1. New Scene → Other Node → Node3D, rename to **Upstairs**
2. Add WorldEnvironment + DirectionalLight3D similar to main hall, but darker (ambient light at 30%)
3. Floor StaticBody3D + walls similar to main hall but larger (40 × 40 floor, walls 4m high)
4. Add Marker3D named **PlayerSpawn** at `Vector3(0, 1, 0)` (center)
5. Add Camera3D similar setup as main hall
6. Instance `scenes/entities/player.tscn` at PlayerSpawn
7. Instance `scenes/ui/hud.tscn`
8. Instance `scenes/ui/descent_prompt.tscn` (set Process Mode to Always on this node)
9. Instance `scenes/interactables/descent_staircase.tscn` at `Vector3(0, 0.1, 8)`. Set its `prompt_path` export to the DescentPrompt node.
10. Add Node3D named **WelpSpawner** at `Vector3(0, 1, -10)` with the welp_spawner.gd script attached. Defaults are fine.
11. Save as `scenes/world/upstairs.tscn`

- [ ] **Step 3: Manual smoke test — full upstairs flow**

Manual:
1. Run game (F5). Start in main hall.
2. Walk onto upstairs tile → scene swaps to upstairs.
3. Welps spawn around the player. Sword auto-attacks them.
4. Killing welps drops red soul pickups. Walk into them. Souls counter increments.
5. Walk to the descent staircase tile. Prompt appears, paused.
6. Click "Descend & deposit" → returns to main hall. Souls cleared, pyre fill increased.
7. Walk to the pyre — it should look more illuminated than before (taller flame, brighter emission).
8. Walk back upstairs. Repeat. After ~250 minor souls, pyre fully lit.

- [ ] **Step 4: Commit**

```bash
git add scripts/world/welp_spawner.gd scenes/world/upstairs.tscn
git commit -m "feat(upstairs): welp spawner + descent staircase + full loop wired"
```

---

## Task 16: Death respawn loop

**Files:**
- Create: `scripts/world/death_handler.gd`
- Modify: `scenes/world/upstairs.tscn` (add DeathHandler node)

- [ ] **Step 1: Implement death handler**

Create `scripts/world/death_handler.gd`:

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
    SoulEconomy.clear_carry()
    GameState.transition_to(GameState.Location.MAIN_HALL)
```

- [ ] **Step 2: Add DeathHandler node to upstairs scene**

Manual in Godot:
1. Open `scenes/world/upstairs.tscn`
2. Add child `Node` named **DeathHandler** (under root)
3. Attach `scripts/world/death_handler.gd`
4. Save

- [ ] **Step 3: Manual smoke test — death cycle**

Manual: F5. Go upstairs. Stand still and let welps kill you (don't dash, don't fight). HP drops, hits 0. Player should die. After ~1 frame, scene swaps to main hall. Souls counter is 0. Pyre fill from any prior deposit persists.

Note: the player instance in main hall is fresh (instanced from the main hall scene), so HP will be 100 again automatically. The dead player from upstairs is destroyed with the scene swap.

- [ ] **Step 4: Commit**

```bash
git add scripts/world/death_handler.gd scenes/world/upstairs.tscn
git commit -m "feat(death): upstairs death triggers carry-clear + return to main hall"
```

---

## Task 17: End-to-end acceptance playtest

This task is verification, not implementation.

- [ ] **Step 1: Run all unit tests**

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
```
Expected: all tests across `test/test_game_state.gd`, `test/test_soul_economy.gd`, `test/test_pyre.gd`, `test/test_player.gd` PASS.

- [ ] **Step 2: Acceptance playtest — full loop**

Manual checklist (10 minutes):
- [ ] Game starts in main hall, player spawned, HP 100, souls 0
- [ ] Pyre is dark/dim (0% fill)
- [ ] Walking onto upstairs trigger transitions to upstairs scene
- [ ] In upstairs: welps spawn at intervals, chase player
- [ ] Sword auto-swings on contact, kills welp in ~2 hits
- [ ] Welp drops a red soul pickup
- [ ] Walking into pickup increments souls counter
- [ ] Standing still under welp attack reduces HP
- [ ] Dash (Space) bursts player away briefly with iframes
- [ ] Walking onto descent staircase triggers prompt with deposit preview
- [ ] Cancel: returns to upstairs, souls retained
- [ ] Confirm: returns to main hall, souls cleared, pyre fill increased
- [ ] Pyre visually changes (taller/brighter flame) with deposits
- [ ] Dying upstairs: HP hits 0, returns to main hall with 0 souls
- [ ] Pyre fill persists across deaths
- [ ] No crashes during 30-minute play session

- [ ] **Step 3: If any acceptance check fails, file as a follow-up task**

Open the spec file `docs/superpowers/specs/2026-04-25-new-chance-design.md` and add a "Phase 1 known issues" section to the appendix listing any failures with reproduction steps.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "test: phase 1 acceptance playtest passed (or document known issues)"
```

- [ ] **Step 5: Tag the milestone**

```bash
git tag -a v0.1-vertical-slice -m "Phase 1: vertical slice complete — playable up/down/deposit loop"
```

---

## Phase 1 → Phase 2 handoff notes

What Phase 1 leaves on the table for Phase 2:

- **No skill system yet.** Picking up a soul currently does nothing in-run except increment a counter. Phase 2 introduces the cast system, modifier stacking, sword-element inheritance, and active skill cap.
- **Soul drops are minor only.** Phase 3 will add Dragon and Elder Dragon tiers with elder soul drops.
- **One color, one corner.** Phase 3 expands to 6 colors and 6 corners with corner-heat.
- **Welp AI is naïve.** Direct chase only. Phase 3 will add wandering, anchored spawns, escalation tie-ins.
- **No save/load.** Pyre fills reset on quit. Phase 4 wires `user://save.tres`.
- **Pyre milestones unimplemented.** 25/50/75/100 effects don't fire. Phase 4 adds them with hub features.
- **No HUD polish.** Bare labels. Phase 6 polishes UI.

Phase 2 plan should be written when Phase 1 ships and the loop has been confirmed fun.

---

## Open implementation notes

- **Line endings:** Project uses `.gitattributes` with default Godot LF normalization. CRLF warnings on git operations are expected and harmless on Windows.
- **GdUnit4 in CI:** the spec calls for CI/CD post-MVP. For Phase 1, tests run locally only.
- **Asset placeholders:** all visuals are Godot primitives (boxes, capsules, spheres). Real meshes come in Phase 6.
- **Pause behavior in DescentPrompt:** the Prompt sets `tree.paused = true`. Player and welp scripts use `_physics_process` (paused with tree). DescentPrompt's `_process` runs because its node Process Mode is "Always."
