# Phase 1 Tech-Debt Sweep — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Address the 6 priority items from the Phase 1 final code review before starting Phase 2 (skill system). All items are extension-readiness rather than correctness fixes; the goal is to make Phase 2 implementation cheaper and avoid forking on signal contracts and end-of-run logic.

**Architecture:** Add new signals (`carry_changed`, `pyre_fill_changed`, `run_ended`) to autoloads to drive listener-based updates instead of per-frame polling. Centralize end-of-run side effects into `GameState.end_run(outcome)`. Migrate combat tuning constants to `@export` for editor tunability. Add public `reset_run()` and `reset_meta()` methods on `SoulEconomy`. Misc cleanup.

**Tech Stack:** Godot 4.6.2, GDScript, GdUnit4. Same as Phase 1.

**Spec / review references:** Code review of commit `b537302` on `phase-1-vertical-slice` branch (now merged to master, tagged `v0.1-vertical-slice`).

**Acceptance test:** All 29 existing tests still pass + new tests for SoulEconomy mixed-tier deposit math + manual smoke test of full loop in upstairs (HP, souls, pyre, dash, death, descent — same as Task 17 of Phase 1).

---

## Task 1: `GameState.end_run(outcome)` coordinator + refactor callers

**Why:** End-of-run side effects (clear carry, deposit souls, transition scene) currently happen in two places — `descent_staircase.gd` and `death_handler.gd`. Phase 2's skill-strip rules will fork in 4 places (4 distinct triggers per spec §"Skill-strip ruleset"). Centralize before adding more.

**Files:**
- Modify: `scripts/core/game_state.gd`
- Modify: `scripts/interactables/descent_staircase.gd`
- Modify: `scripts/world/death_handler.gd`
- Modify: `test/test_game_state.gd`

- [ ] **Step 1: Add Outcome enum + run_ended signal to GameState**

Add to `scripts/core/game_state.gd` after the existing `Location` enum:

```gdscript
enum Outcome { DESCENDED, DIED }

signal run_ended(outcome: Outcome)

func end_run(outcome: Outcome) -> void:
	if outcome == Outcome.DESCENDED:
		SoulEconomy.deposit_to_pyres()
	elif outcome == Outcome.DIED:
		SoulEconomy.clear_carry()
	run_ended.emit(outcome)
	transition_to(Location.MAIN_HALL)
```

- [ ] **Step 2: Add tests for end_run**

Append to `test/test_game_state.gd`:

```gdscript
func test_end_run_descended_deposits_to_pyres() -> void:
	SoulEconomy._reset_state()  # FIXME: replaced in Task 2
	SoulEconomy.add_to_carry("red", "minor", 5)
	gs.end_run(GameStateScript.Outcome.DESCENDED)
	assert_that(SoulEconomy.pyre_fill("red")).is_equal(5)
	assert_that(SoulEconomy.carry_count("red", "minor")).is_equal(0)

func test_end_run_died_clears_carry_without_deposit() -> void:
	SoulEconomy._reset_state()
	SoulEconomy.add_to_carry("red", "minor", 5)
	gs.end_run(GameStateScript.Outcome.DIED)
	assert_that(SoulEconomy.pyre_fill("red")).is_equal(0)
	assert_that(SoulEconomy.carry_count("red", "minor")).is_equal(0)

func test_end_run_emits_signal_with_outcome() -> void:
	gs.end_run(GameStateScript.Outcome.DIED)
	await assert_signal(gs).is_emitted("run_ended", [GameStateScript.Outcome.DIED])
```

- [ ] **Step 3: Run tests — verify they fail (Outcome / end_run / run_ended don't exist), then implement, then verify pass**

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_game_state.gd --ignoreHeadlessMode
```

- [ ] **Step 4: Refactor descent_staircase.gd to call end_run**

Replace `_on_confirmed` with:

```gdscript
func _on_confirmed() -> void:
	GameState.end_run(GameState.Outcome.DESCENDED)
```

Remove the direct `SoulEconomy.deposit_to_pyres()` and `GameState.transition_to(...)` calls — `end_run` handles both.

- [ ] **Step 5: Refactor death_handler.gd to call end_run**

Replace `_on_player_died` with:

```gdscript
func _on_player_died() -> void:
	GameState.end_run(GameState.Outcome.DIED)
```

Remove direct calls to `SoulEconomy.clear_carry()` and `GameState.transition_to(...)`.

- [ ] **Step 6: Run all tests, smoke check via --import**

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
```
Expected: all tests pass (29 + 3 new = 32).

- [ ] **Step 7: Commit**

```bash
git add scripts/core/game_state.gd scripts/interactables/descent_staircase.gd scripts/world/death_handler.gd test/test_game_state.gd
git commit -m "refactor: centralize end-of-run side effects in GameState.end_run()"
```

---

## Task 2: `SoulEconomy` public `reset_run()` + `reset_meta()`

**Why:** `_reset_state()` is private but called from tests. Phase 2 needs to expose meta-reset (new game) and run-reset (death) as separate concerns.

**Files:**
- Modify: `scripts/core/soul_economy.gd`
- Modify: `test/test_soul_economy.gd`
- Modify: `test/test_pyre.gd`
- Modify: `test/test_game_state.gd`

- [ ] **Step 1: Replace `_reset_state` with two public methods**

In `scripts/core/soul_economy.gd`, replace the existing `_reset_state` with:

```gdscript
func reset_run() -> void:
	# Clears in-run state only (carry pool). Pyre fills + filled flags persist.
	clear_carry()

func reset_meta() -> void:
	# Clears all state including pyres. New-game / test isolation use only.
	_carry.clear()
	_pyres.clear()
	_filled_pyres.clear()
	for color in COLORS:
		_carry[color] = {"minor": 0, "elder": 0}
		_pyres[color] = 0
		_filled_pyres[color] = false
```

Update `_ready()` to call `reset_meta()` instead of `_reset_state()`:

```gdscript
func _ready() -> void:
	reset_meta()
```

Remove the `_reset_state` function entirely.

- [ ] **Step 2: Update all test files to call `reset_meta()` instead of `_reset_state()`**

In `test/test_pyre.gd:9`, change `SoulEconomy._reset_state()` to `SoulEconomy.reset_meta()`.
In `test/test_game_state.gd` (Task 1's new tests), change `SoulEconomy._reset_state()` to `SoulEconomy.reset_meta()`.

- [ ] **Step 3: Add a test for reset_run vs reset_meta semantics**

Append to `test/test_soul_economy.gd`:

```gdscript
func test_reset_run_clears_carry_keeps_pyres() -> void:
	econ.add_to_carry("red", "minor", 5)
	econ.deposit_to_pyres()
	econ.add_to_carry("red", "minor", 3)
	econ.reset_run()
	assert_that(econ.carry_count("red", "minor")).is_equal(0)
	assert_that(econ.pyre_fill("red")).is_equal(5)

func test_reset_meta_clears_everything() -> void:
	econ.add_to_carry("red", "minor", 5)
	econ.deposit_to_pyres()
	econ.reset_meta()
	assert_that(econ.carry_count("red", "minor")).is_equal(0)
	assert_that(econ.pyre_fill("red")).is_equal(0)
```

- [ ] **Step 4: Run all tests**

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
```
Expected: 34 tests pass (32 + 2 new). Confirm no regressions.

- [ ] **Step 5: Commit**

```bash
git add scripts/core/soul_economy.gd test/test_soul_economy.gd test/test_pyre.gd test/test_game_state.gd
git commit -m "refactor: SoulEconomy public reset_run + reset_meta (was _reset_state)"
```

---

## Task 3: `pyre_fill_changed` signal + remove Pyre polling

**Why:** Pyre.gd polls `SoulEconomy.pyre_fill(color)` every frame. Phase 3 will have 6+ pyres polling; switch to signal-driven now while it's free.

**Files:**
- Modify: `scripts/core/soul_economy.gd`
- Modify: `scripts/interactables/pyre.gd`
- Modify: `test/test_soul_economy.gd`

- [ ] **Step 1: Emit pyre_fill_changed inside deposit_to_pyres**

In `scripts/core/soul_economy.gd`, add the signal declaration alongside `pyre_filled`:

```gdscript
signal pyre_filled(color: String)
signal pyre_fill_changed(color: String, new_fill: int)
```

Modify `deposit_to_pyres` to emit the new signal whenever a pyre's fill actually changes:

```gdscript
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
		var old_fill: int = _pyres[color]
		_pyres[color] = new_fill
		if new_fill != old_fill:
			pyre_fill_changed.emit(color, new_fill)
		if new_fill >= PYRE_CAP and not was_full:
			_filled_pyres[color] = true
			pyre_filled.emit(color)
	clear_carry()
```

- [ ] **Step 2: Add a test for the new signal**

Append to `test/test_soul_economy.gd`:

```gdscript
func test_pyre_fill_changed_signal_with_new_fill() -> void:
	econ.add_to_carry("red", "minor", 7)
	econ.deposit_to_pyres()
	await assert_signal(econ).is_emitted("pyre_fill_changed", ["red", 7])

func test_pyre_fill_changed_not_emitted_when_no_deposit() -> void:
	econ.deposit_to_pyres()  # no carry to deposit
	var monitor := monitor_signals(econ)
	econ.deposit_to_pyres()
	await assert_signal(econ).is_not_emitted("pyre_fill_changed")
```

- [ ] **Step 3: Replace Pyre polling with signal listener**

Replace `scripts/interactables/pyre.gd` with:

```gdscript
extends Node3D

@export var color: String = "red"

var fill_ratio: float = 0.0
var is_fully_lit: bool = false

@onready var _flame_mesh: MeshInstance3D = $Flame if has_node("Flame") else null

func _ready() -> void:
	SoulEconomy.pyre_filled.connect(_on_pyre_filled)
	SoulEconomy.pyre_fill_changed.connect(_on_pyre_fill_changed)
	refresh_visual()

func refresh_visual() -> void:
	var fill: int = SoulEconomy.pyre_fill(color)
	fill_ratio = float(fill) / float(SoulEconomy.PYRE_CAP)
	is_fully_lit = fill >= SoulEconomy.PYRE_CAP
	_apply_visual()

func _on_pyre_filled(filled_color: String) -> void:
	if filled_color == color:
		refresh_visual()

func _on_pyre_fill_changed(changed_color: String, _new_fill: int) -> void:
	if changed_color == color:
		refresh_visual()

func _apply_visual() -> void:
	if _flame_mesh == null:
		return
	_flame_mesh.scale = Vector3(1.0, 0.1 + fill_ratio * 1.5, 1.0)
	var mat: StandardMaterial3D = _flame_mesh.material_override as StandardMaterial3D
	if mat != null:
		mat.emission_energy_multiplier = 0.5 + fill_ratio * 4.0
```

`set_process(true)` and `_process` are removed — fully signal-driven now.

- [ ] **Step 4: Run all tests + import smoke check**

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . --import 2>&1 | grep -i error | head -5
```
Expected: 36 tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/core/soul_economy.gd scripts/interactables/pyre.gd test/test_soul_economy.gd
git commit -m "refactor(pyre): replace per-frame poll with pyre_fill_changed signal"
```

---

## Task 4: `carry_changed` signal + remove HUD polling

**Why:** Phase 2 HUD will display all 6 colors. Polling 6× per frame for souls counts is wasteful. Signal-drive it.

**Files:**
- Modify: `scripts/core/soul_economy.gd`
- Modify: `scripts/ui/hud.gd`
- Modify: `test/test_soul_economy.gd`

- [ ] **Step 1: Add carry_changed signal**

In `scripts/core/soul_economy.gd`:

```gdscript
signal carry_changed(color: String, tier: String, new_count: int)
```

Modify `add_to_carry` to emit:

```gdscript
func add_to_carry(color: String, tier: String, count: int) -> void:
	assert(color in COLORS, "unknown color: %s" % color)
	assert(tier in SOUL_VALUES, "unknown tier: %s" % tier)
	_carry[color][tier] += count
	carry_changed.emit(color, tier, _carry[color][tier])
```

Modify `clear_carry` to emit only for non-zero entries:

```gdscript
func clear_carry() -> void:
	for color in COLORS:
		for tier in SOUL_VALUES:
			if _carry[color][tier] > 0:
				_carry[color][tier] = 0
				carry_changed.emit(color, tier, 0)
```

- [ ] **Step 2: Add tests for carry_changed**

Append to `test/test_soul_economy.gd`:

```gdscript
func test_carry_changed_signal_on_add() -> void:
	await assert_signal(econ).wait_until(100).is_emitted_with(func(): econ.add_to_carry("red", "minor", 3), "carry_changed", ["red", "minor", 3])

# If the wait_until/is_emitted_with API is unavailable in this GdUnit version, fall back to:
func test_carry_changed_emits_with_new_count() -> void:
	var monitor := monitor_signals(econ)
	econ.add_to_carry("red", "minor", 3)
	await assert_signal(econ).is_emitted("carry_changed", ["red", "minor", 3])

func test_carry_changed_emits_on_clear() -> void:
	econ.add_to_carry("red", "minor", 5)
	var monitor := monitor_signals(econ)
	econ.clear_carry()
	await assert_signal(econ).is_emitted("carry_changed", ["red", "minor", 0])
```

(Use whichever assertion form GdUnit 6.1.3 supports. The `monitor_signals` form is known to work; remove the `wait_until` form if it errors.)

- [ ] **Step 3: Replace HUD polling with signal listener**

Replace `scripts/ui/hud.gd` with:

```gdscript
extends CanvasLayer

@onready var _hp_label: Label = $Margin/VBox/HP
@onready var _souls_label: Label = $Margin/VBox/Souls

var _player: Node = null
var _last_red_minor: int = -1

func _ready() -> void:
	_bind_to_player()
	SoulEconomy.carry_changed.connect(_on_carry_changed)
	_refresh_souls()

func _bind_to_player() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
		if not _player.hp_changed.is_connected(_on_hp_changed):
			_player.hp_changed.connect(_on_hp_changed)
		_on_hp_changed(_player.hp)

func _process(_delta: float) -> void:
	# Fallback for cross-scene rebind only — no per-frame polling for souls.
	if _player == null or not is_instance_valid(_player):
		_bind_to_player()

func _on_carry_changed(_color: String, _tier: String, _new_count: int) -> void:
	_refresh_souls()

func _refresh_souls() -> void:
	var red_minor: int = SoulEconomy.carry_count("red", "minor")
	if red_minor == _last_red_minor:
		return
	_last_red_minor = red_minor
	_souls_label.text = "Souls (red): %d" % red_minor

func _on_hp_changed(new_hp: int) -> void:
	_hp_label.text = "HP: %d / 100" % new_hp
```

`_process` shrinks to just the player-rebind concern (still needed for scene swap); soul label updates on signal.

- [ ] **Step 4: Run tests + smoke check**

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
```
Expected: 38 tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/core/soul_economy.gd scripts/ui/hud.gd test/test_soul_economy.gd
git commit -m "refactor(hud): replace soul-count poll with carry_changed signal"
```

---

## Task 5: Migrate combat tuning to `@export`

**Why:** 5 separate "tune:" commits during Phase 1 playtest. Code-edit-relaunch is 5–10× slower than editor `@export` tuning. Migrate the feel knobs now while context is fresh.

**Files:**
- Modify: `scripts/entities/player.gd`
- Modify: `scripts/entities/sword.gd`
- Modify: `scripts/entities/welp.gd`
- Modify: `scripts/world/welp_spawner.gd`

- [ ] **Step 1: Player — convert MOVE_SPEED, DASH_DISTANCE, DASH_DURATION, DASH_COOLDOWN, IFRAME_DURATION to @export**

Keep `const MAX_HP: int = 100` (structural, not feel).

Replace the const block in `scripts/entities/player.gd`:

```gdscript
const MAX_HP: int = 100

@export var move_speed: float = 5.0
@export var dash_distance: float = 4.0
@export var dash_duration: float = 0.15
@export var dash_cooldown: float = 2.0
@export var iframe_duration: float = 0.2
```

Update all references in the script: `MOVE_SPEED → move_speed`, `DASH_DISTANCE → dash_distance`, `DASH_DURATION → dash_duration`, `DASH_COOLDOWN → dash_cooldown`, `IFRAME_DURATION → iframe_duration`.

- [ ] **Step 2: Sword — convert SWING_INTERVAL, BASE_DAMAGE to @export**

Replace const block in `scripts/entities/sword.gd`:

```gdscript
@export var swing_interval: float = 0.4
@export var base_damage: int = 15
```

Update references: `SWING_INTERVAL → swing_interval`, `BASE_DAMAGE → base_damage`.

- [ ] **Step 3: Welp — convert MOVE_SPEED, ATTACK_DAMAGE, ATTACK_INTERVAL, ATTACK_RANGE to @export. Keep MAX_HP as const.**

Replace in `scripts/entities/welp.gd`:

```gdscript
const MAX_HP: int = 30

@export var move_speed: float = 3.6
@export var attack_damage: int = 10
@export var attack_interval: float = 2.0
@export var attack_range: float = 1.0
```

Update references: `MOVE_SPEED → move_speed`, `ATTACK_DAMAGE → attack_damage`, `ATTACK_INTERVAL → attack_interval`, `ATTACK_RANGE → attack_range`.

- [ ] **Step 4: welp_spawner — already uses @export, no change needed.** Verify by reading the file; the spawner declared `@export var spawn_interval`, `@export var max_alive`, `@export var spawn_radius` from the start.

- [ ] **Step 5: Run all tests**

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
```
Expected: 38 tests pass. **CAUTION:** the dash test `test_dash_cooldown_expires` accesses `_dash_cooldown_remaining` directly. The export rename doesn't affect underscore-prefixed private vars, so this test is unaffected. If any test referenced `Player.MOVE_SPEED` or similar directly (none should), update those references.

- [ ] **Step 6: Commit**

```bash
git add scripts/entities/player.gd scripts/entities/sword.gd scripts/entities/welp.gd
git commit -m "refactor: migrate combat tuning constants to @export for editor tunability"
```

---

## Task 6: Misc cleanup + extra tests

**Why:** Small wins flagged in code review.

**Files:**
- Modify: `scripts/interactables/descent_staircase.gd` (drop unused `_player_in_zone`)
- Modify: `scripts/core/game_state.gd` (push_error on unknown enum)
- Modify: `test/test_soul_economy.gd` (add elder + mixed-tier tests)

- [ ] **Step 1: Drop unused `_player_in_zone` from descent_staircase.gd**

Remove the variable declaration and the two assignment sites. Clean form:

```gdscript
extends Area3D

@export var prompt_path: NodePath  # Path to a DescentPrompt instance in the scene tree

var _prompt: CanvasLayer = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if prompt_path != NodePath(""):
		_prompt = get_node(prompt_path)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if _prompt == null:
		return
	_prompt.show_prompt()
	if not _prompt.confirmed.is_connected(_on_confirmed):
		_prompt.confirmed.connect(_on_confirmed)
	if not _prompt.canceled.is_connected(_on_canceled):
		_prompt.canceled.connect(_on_canceled)

func _on_confirmed() -> void:
	GameState.end_run(GameState.Outcome.DESCENDED)

func _on_canceled() -> void:
	pass  # player stays upstairs; nothing to do
```

(`body_exited` and the unused state are gone. Re-prompt on re-entry still works because `_on_body_entered` always calls `show_prompt()`.)

- [ ] **Step 2: Add push_error to GameState.scene_path_for default branch**

In `scripts/core/game_state.gd`, modify `scene_path_for`:

```gdscript
static func scene_path_for(location: Location) -> String:
	match location:
		Location.MAIN_HALL:
			return MAIN_HALL_SCENE_PATH
		Location.UPSTAIRS:
			return UPSTAIRS_SCENE_PATH
		_:
			push_error("scene_path_for: unknown location %s" % location)
			return ""
```

- [ ] **Step 3: Add elder + mixed deposit tests**

Append to `test/test_soul_economy.gd`:

```gdscript
func test_elder_soul_alone_advances_pyre_by_10() -> void:
	econ.add_to_carry("red", "elder", 1)
	econ.deposit_to_pyres()
	assert_that(econ.pyre_fill("red")).is_equal(10)

func test_deposit_mixes_minor_and_elder_correctly() -> void:
	econ.add_to_carry("red", "minor", 7)
	econ.add_to_carry("red", "elder", 2)
	econ.deposit_to_pyres()
	# 7 minor (1 each) + 2 elder (10 each) = 7 + 20 = 27
	assert_that(econ.pyre_fill("red")).is_equal(27)

func test_deposit_does_not_overflow_with_elder_at_cap() -> void:
	econ.add_to_carry("red", "minor", 245)
	econ.add_to_carry("red", "elder", 1)
	econ.deposit_to_pyres()
	# 245 + 10 = 255, clamped to 250
	assert_that(econ.pyre_fill("red")).is_equal(250)
```

- [ ] **Step 4: Run all tests**

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
```
Expected: 41 tests pass (38 + 3 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/interactables/descent_staircase.gd scripts/core/game_state.gd test/test_soul_economy.gd
git commit -m "cleanup: drop unused state, push_error on bad enum, elder/mixed deposit tests"
```

---

## Task 7: End-to-end smoke test (manual, by USER)

After all 6 tasks land, the user runs the full upstairs flow once to confirm:
- Player spawns in main hall, HP 100
- Up to upstairs, fight welps, pickup souls (HUD updates instantly via signal, not poll)
- Descent prompt → deposit → pyre lights up immediately (signal-driven)
- Death → return to main hall, fresh state

If anything regresses, file as a follow-up and revert offending task. Otherwise: tag.

- [ ] **Step 1: User runs the game and verifies the loop**

(Manual user step — no code action.)

- [ ] **Step 2: After user confirms, tag the milestone**

```bash
git tag -a v0.1.1-tech-debt -m "Tech-debt sweep: signal-driven updates, end_run coordinator, @export tuning, public reset_meta. 41 tests passing."
```

---

## Notes for implementers

- All 6 tasks should pass through the same TDD-or-light-tests rhythm as Phase 1.
- The combined diff is ~150 lines of code change across ~8 files. Each task should be a single commit.
- Subagent-driven execution: implementer + spec review for Tasks 1, 3, 4 (touching public APIs); implementer-only for Tasks 2, 5, 6 (mostly mechanical renames / additions).
