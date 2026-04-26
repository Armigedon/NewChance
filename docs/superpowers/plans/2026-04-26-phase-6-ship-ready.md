# Phase 6 Ship-Ready Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert FAST-TEST playtest values to ship-ready medium-pacing values via a Debug autoload toggle, weight open-arena spawning by player proximity to corner spawners, and expand the necromancer's taunt content (~36 lines) so death + boss combat carry the disappointed-parent voice consistently.

**Architecture:** Five sequential tasks, each producing self-contained changes against existing files. Task 1 lays the toggle infrastructure; Task 2 conditionalizes the 5 FAST-TEST constants and rebalances them; Task 3 reshapes spawn weighting; Task 4 adds line content; Task 5 wires triggers for new line categories. No new scenes. One new autoload script.

**Tech Stack:** Godot 4.6 (.NET, Forward+), GDScript with type hints, GdUnit4 for unit tests, Jolt 3D physics. Existing autoloads: GameState, SoulEconomy, Escalation, SaveSystem, MetaProgress, BossFlow.

**Spec:** [docs/superpowers/specs/2026-04-26-phase-6-ship-ready-design.md](../specs/2026-04-26-phase-6-ship-ready-design.md)

**Branch:** `phase-6-ship-ready` (already created)

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `scripts/core/debug.gd` | **Create** | Single-constant autoload exposing `FAST_TEST: bool` |
| `project.godot` | Modify | Register `Debug` autoload (must precede SoulEconomy in load order) |
| `scripts/core/soul_economy.gd` | Modify | Conditionalize `PYRE_CAP` and `SOUL_VALUES["elder"]` (TEST/SHIP pair via static var) |
| `scripts/ui/soul_altar_ui.gd` | Modify | Conditionalize `ALTAR_COST` |
| `scripts/ui/cantrip_stones_ui.gd` | Modify | Conditionalize `STONE_COST` |
| `scripts/entities/boss_dragon.gd` | Modify | Conditionalize `MAX_HP`; add taunt trigger wiring (phase + idle) |
| `scripts/world/corner_spawner.gd` | Modify | Add proximity multiplier, burst-spawn, far-tier biasing |
| `scripts/ui/dialogue_banner.gd` | Modify | Expand `LINES` dict with 36 new lines across 5 categories |
| `test/test_soul_economy.gd` | Modify | Update PYRE_CAP / SOUL_VALUES references for static-var access |
| `test/test_corner_spawner.gd` | **Create** | Unit tests for proximity multiplier helper |
| `test/test_boss_taunts.gd` | **Create** | Unit tests for boss-dragon taunt trigger logic |

---

## Task 1: Debug Autoload

**Files:**
- Create: `scripts/core/debug.gd`
- Modify: `project.godot`

- [ ] **Step 1: Create the Debug autoload script**

Write to `scripts/core/debug.gd`:

```gdscript
extends Node

# Single source of truth for FAST-TEST vs SHIP value selection.
# Flip to false before any release build.
const FAST_TEST: bool = true
```

- [ ] **Step 2: Register Debug as the first autoload**

Edit `project.godot`. Find the `[autoload]` section (around line 18) and add `Debug` as the FIRST entry:

```ini
[autoload]

Debug="*res://scripts/core/debug.gd"
GameState="*res://scripts/core/game_state.gd"
SoulEconomy="*res://scripts/core/soul_economy.gd"
Escalation="*res://scripts/world/escalation.gd"
SaveSystem="*res://scripts/core/save_system.gd"
MetaProgress="*res://scripts/core/meta_progress.gd"
BossFlow="*res://scripts/core/boss_flow.gd"
```

Order matters: SoulEconomy's static-var initializer in Task 2 reads `Debug.FAST_TEST`, so Debug must be parsed first.

- [ ] **Step 3: Verify autoload loads cleanly**

Run the editor smoke check (or run all tests):

```bash
cd /c/Users/wyenk/OneDrive/Documents/godot/new-chance
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/
```

Expected: 102/102 tests pass (no behavior change yet).

- [ ] **Step 4: Commit**

```bash
git add scripts/core/debug.gd project.godot
git commit -m "feat(debug): add Debug autoload with FAST_TEST toggle constant"
```

---

## Task 2: Conditionalize FAST-TEST Constants + Apply SHIP Values

**Files:**
- Modify: `scripts/core/soul_economy.gd:3-8`
- Modify: `scripts/ui/soul_altar_ui.gd:14`
- Modify: `scripts/ui/cantrip_stones_ui.gd:9`
- Modify: `scripts/entities/boss_dragon.gd:3`
- Modify: `test/test_soul_economy.gd` (update access pattern for static vars)

- [ ] **Step 1: Refactor `soul_economy.gd` constants**

Edit `scripts/core/soul_economy.gd`. Replace lines 1-8 with:

```gdscript
extends Node

const PYRE_CAP_TEST: int = 10
const PYRE_CAP_SHIP: int = 100
static var PYRE_CAP: int = PYRE_CAP_TEST if Debug.FAST_TEST else PYRE_CAP_SHIP

const COLORS: Array[String] = ["red", "blue", "green", "purple", "gold", "white"]
static var SOUL_VALUES: Dictionary = {
	"minor": 1,
	"elder": 5 if Debug.FAST_TEST else 10,
}
```

The rest of the file is unchanged. All call sites read `SoulEconomy.PYRE_CAP` and `SoulEconomy.SOUL_VALUES[...]` — both still work with static vars accessed via the autoload singleton.

- [ ] **Step 2: Refactor `soul_altar_ui.gd` cost constant**

Edit `scripts/ui/soul_altar_ui.gd`. Replace line 14 with:

```gdscript
const ALTAR_COST_TEST: int = 3
const ALTAR_COST_SHIP: int = 10
static var ALTAR_COST: int = ALTAR_COST_TEST if Debug.FAST_TEST else ALTAR_COST_SHIP
```

All other lines in that file reference `ALTAR_COST` and continue to work unchanged.

- [ ] **Step 3: Refactor `cantrip_stones_ui.gd` cost constant**

Edit `scripts/ui/cantrip_stones_ui.gd`. Replace line 9 with:

```gdscript
const STONE_COST_TEST: int = 3
const STONE_COST_SHIP: int = 12
static var STONE_COST: int = STONE_COST_TEST if Debug.FAST_TEST else STONE_COST_SHIP
```

- [ ] **Step 4: Refactor `boss_dragon.gd` MAX_HP**

Edit `scripts/entities/boss_dragon.gd`. Replace line 3 with:

```gdscript
const MAX_HP_TEST: int = 150
const MAX_HP_SHIP: int = 400
static var MAX_HP: int = MAX_HP_TEST if Debug.FAST_TEST else MAX_HP_SHIP
```

The `var hp: int = MAX_HP` initializer at line 16 still resolves to the picked static var value at instantiation. Unchanged.

- [ ] **Step 5: Update `test_soul_economy.gd` for static-var access**

Edit `test/test_soul_economy.gd`. Where the test reads constants via the local instance (`econ.PYRE_CAP`, `econ.SOUL_VALUES`), GDScript 4 emits a warning when static vars are accessed via instance. Replace those references with the script-level reference using `SoulEconomyScript`. Find the existing `const SoulEconomyScript = preload(...)` line near the top of the file. The references to update:

- Line 28: `econ.add_to_carry("red", "minor", econ.PYRE_CAP * 2)` → `econ.add_to_carry("red", "minor", SoulEconomyScript.PYRE_CAP * 2)`
- Line 30: `assert_that(econ.pyre_fill("red")).is_equal(econ.PYRE_CAP)` → `is_equal(SoulEconomyScript.PYRE_CAP)`
- Line 39: `econ.add_to_carry("red", "minor", econ.PYRE_CAP)` → `SoulEconomyScript.PYRE_CAP`
- Line 44: same pattern → `SoulEconomyScript.PYRE_CAP`
- Line 92: `var expected: int = min(econ.SOUL_VALUES["elder"], econ.PYRE_CAP)` → `min(SoulEconomyScript.SOUL_VALUES["elder"], SoulEconomyScript.PYRE_CAP)`
- Line 100: `var expected: int = min(1 + econ.SOUL_VALUES["elder"], econ.PYRE_CAP)` → `min(1 + SoulEconomyScript.SOUL_VALUES["elder"], SoulEconomyScript.PYRE_CAP)`
- Line 105: `var near_cap: int = econ.PYRE_CAP - 2` → `SoulEconomyScript.PYRE_CAP - 2`
- Line 109: `assert_that(econ.pyre_fill("red")).is_equal(econ.PYRE_CAP)` → `is_equal(SoulEconomyScript.PYRE_CAP)`

Open the file, do these 8 edits with Edit tool. The preload const is named `SoulEconomyScript` at the top of the file.

- [ ] **Step 6: Run all tests; expect green**

```bash
cd /c/Users/wyenk/OneDrive/Documents/godot/new-chance
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/
```

Expected: 102/102 tests pass. The static-var values are still TEST values because `Debug.FAST_TEST = true`.

- [ ] **Step 7: Manual SHIP-mode smoke check (no commit)**

Temporarily edit `scripts/core/debug.gd` to set `FAST_TEST = false`. Open the editor and start the game. Walk to a pyre, deposit a soul, confirm pyre fill ratio is 1/100 not 1/10. Then **revert the change**:

```bash
git checkout -- scripts/core/debug.gd
```

This is a manual sanity check, not committed.

- [ ] **Step 8: Commit Task 2**

```bash
git add scripts/core/soul_economy.gd scripts/ui/soul_altar_ui.gd scripts/ui/cantrip_stones_ui.gd scripts/entities/boss_dragon.gd test/test_soul_economy.gd
git commit -m "feat(debug): conditionalize 5 FAST-TEST constants behind Debug.FAST_TEST

PYRE_CAP 10/100, elder soul value 5/10, ALTAR_COST 3/10,
STONE_COST 3/12, boss MAX_HP 150/400. Tests still pass with FAST_TEST=true."
```

---

## Task 3: Proximity-Weighted Corner Spawning

**Files:**
- Modify: `scripts/world/corner_spawner.gd`
- Create: `test/test_corner_spawner.gd`

- [ ] **Step 1: Write failing tests for proximity helper**

Create `test/test_corner_spawner.gd`:

```gdscript
extends GdUnitTestSuite

const SpawnerScript = preload("res://scripts/world/corner_spawner.gd")

var spawner: Node3D

func before_test() -> void:
	spawner = auto_free(SpawnerScript.new())
	spawner.global_position = Vector3.ZERO
	add_child(spawner)
	# Disable autorun process so tests don't trigger _spawn().
	spawner.set_process(false)

func test_proximity_multiplier_close() -> void:
	# Player within 8m → 2.5x multiplier.
	var mult: float = spawner._compute_proximity_multiplier(Vector3(5, 0, 0))
	assert_that(mult).is_equal_approx(2.5, 0.001)

func test_proximity_multiplier_at_close_boundary() -> void:
	# Exactly 8m → still close (≤ 8 inclusive).
	var mult: float = spawner._compute_proximity_multiplier(Vector3(8, 0, 0))
	assert_that(mult).is_equal_approx(2.5, 0.001)

func test_proximity_multiplier_medium() -> void:
	# Between 8m and 16m → 1.0x.
	var mult: float = spawner._compute_proximity_multiplier(Vector3(12, 0, 0))
	assert_that(mult).is_equal_approx(1.0, 0.001)

func test_proximity_multiplier_at_far_boundary() -> void:
	# Exactly 16m → still medium (≤ 16 inclusive).
	var mult: float = spawner._compute_proximity_multiplier(Vector3(16, 0, 0))
	assert_that(mult).is_equal_approx(1.0, 0.001)

func test_proximity_multiplier_far() -> void:
	# Beyond 16m → 0.3x.
	var mult: float = spawner._compute_proximity_multiplier(Vector3(20, 0, 0))
	assert_that(mult).is_equal_approx(0.3, 0.001)

func test_proximity_multiplier_ignores_y() -> void:
	# Y axis must not affect distance (top-down 3D).
	var mult: float = spawner._compute_proximity_multiplier(Vector3(5, 100, 0))
	assert_that(mult).is_equal_approx(2.5, 0.001)

func test_proximity_multiplier_no_player_returns_one() -> void:
	# Sentinel: when player position is INF, treat as medium (no boost, no penalty).
	var mult: float = spawner._compute_proximity_multiplier(Vector3.INF)
	assert_that(mult).is_equal_approx(1.0, 0.001)

func test_is_close_for_burst_check() -> void:
	# _is_close returns true iff player within 8m XZ.
	assert_that(spawner._is_close(Vector3(5, 0, 0))).is_true()
	assert_that(spawner._is_close(Vector3(8, 0, 0))).is_true()
	assert_that(spawner._is_close(Vector3(8.1, 0, 0))).is_false()
	assert_that(spawner._is_close(Vector3(20, 0, 0))).is_false()
	assert_that(spawner._is_close(Vector3.INF)).is_false()

func test_is_far_check() -> void:
	# _is_far returns true iff player beyond 16m XZ.
	assert_that(spawner._is_far(Vector3(20, 0, 0))).is_true()
	assert_that(spawner._is_far(Vector3(16, 0, 0))).is_false()
	assert_that(spawner._is_far(Vector3(5, 0, 0))).is_false()
	assert_that(spawner._is_far(Vector3.INF)).is_false()
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_corner_spawner.gd
```

Expected: All 9 tests fail with "method not found: _compute_proximity_multiplier" (or similar).

- [ ] **Step 3: Add proximity helpers to `corner_spawner.gd`**

Edit `scripts/world/corner_spawner.gd`. Add three new helper methods after the existing `_get_player_pos` method (after line 98). The helpers compute distance on the XZ plane only and return multiplier / boolean:

```gdscript
func _compute_proximity_multiplier(player_pos: Vector3) -> float:
	if player_pos == Vector3.INF:
		return 1.0
	var d: float = Vector2(player_pos.x - global_position.x, player_pos.z - global_position.z).length()
	if d <= 8.0:
		return 2.5
	if d <= 16.0:
		return 1.0
	return 0.3

func _is_close(player_pos: Vector3) -> bool:
	if player_pos == Vector3.INF:
		return false
	var d: float = Vector2(player_pos.x - global_position.x, player_pos.z - global_position.z).length()
	return d <= 8.0

func _is_far(player_pos: Vector3) -> bool:
	if player_pos == Vector3.INF:
		return false
	var d: float = Vector2(player_pos.x - global_position.x, player_pos.z - global_position.z).length()
	return d > 16.0
```

- [ ] **Step 4: Run helper tests; expect green**

```bash
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_corner_spawner.gd
```

Expected: 9/9 tests pass.

- [ ] **Step 5: Wire helpers into `_process` and `_spawn`**

Edit `scripts/world/corner_spawner.gd`. Replace the existing `_process` method (lines 32-38) with:

```gdscript
func _process(delta: float) -> void:
	var heat: float = Escalation.corner_heat(color)
	var player_pos: Vector3 = _get_player_pos()
	var proximity_mult: float = _compute_proximity_multiplier(player_pos)
	var effective_interval: float = base_spawn_interval / (Escalation.spawn_rate_factor(heat) * proximity_mult)
	_timer += delta
	if _timer >= effective_interval and _alive_count < max_alive:
		_timer = 0.0
		_spawn()
		# Burst spawn: 25% chance of a second welp same tick when player is close.
		if _is_close(player_pos) and randf() < 0.25 and _alive_count < max_alive:
			_spawn()
```

Now bias the tier roll for far corners. Replace the existing `_spawn` method (lines 40-56) with:

```gdscript
func _spawn() -> void:
	var heat: float = Escalation.corner_heat(color)
	var player_pos: Vector3 = _get_player_pos()
	var tier: String = Escalation.roll_tier(heat)
	# Far corners only ever produce welps — no off-screen dragons/elders.
	if _is_far(player_pos):
		tier = "welp"
	var scene: PackedScene = _scene_for_tier(tier)
	if scene == null:
		return
	var enemy = scene.instantiate()
	if "max_hp" in enemy:
		enemy.max_hp = int(enemy.max_hp * Escalation.enemy_hp_factor())
	if tier in ["dragon", "elder"]:
		enemy.color = color
		_apply_color_tint(enemy, color)
	var spawn_pos: Vector3 = _pick_spawn_position()
	enemy.died.connect(_on_died)
	get_parent().add_child(enemy)
	enemy.global_position = spawn_pos
	_alive_count += 1
```

- [ ] **Step 6: Run full test suite; expect green**

```bash
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/
```

Expected: 111/111 tests pass (102 prior + 9 new).

- [ ] **Step 7: Commit**

```bash
git add scripts/world/corner_spawner.gd test/test_corner_spawner.gd
git commit -m "feat(spawn): proximity-weighted corner spawning with burst + far-tier bias

Close (≤8m) corners spawn 2.5x base rate with 25% burst chance.
Medium (8-16m) unchanged. Far (>16m) at 0.3x rate, welps only.
Stacks multiplicatively with existing heat factor."
```

---

## Task 4: Taunt Content Expansion

**Files:**
- Modify: `scripts/ui/dialogue_banner.gd:5-27`

This task is content-only. No new logic, no triggers — those are wired in Task 5.

- [ ] **Step 1: Expand the `LINES` dict with all 36 new lines + 5 categories**

Edit `scripts/ui/dialogue_banner.gd`. Replace the existing `LINES` dict (lines 5-27) with the expanded version below. New lines marked with `# new` so the diff is reviewable; remove the comments after merge.

```gdscript
const LINES: Dictionary = {
	"death_normal": [
		"Get up, fool. The dragons aren't going to slay themselves.",
		"You die so well, little corpse. Try harder.",
		"What a waste of bone. Again.",
		"Did you forget what I made you for?",
		"Crawl back to the pyres. The dragons grow restless.",
		"Pathetic. I expected more from you, even now.",
		"Was that meant to be effort? I am embarrassed for you.",
		"Death again. As if you have nothing better to do.",
		"How disappointing. And yet, somehow, predictable.",
		"Stand. The work isn't done because YOU are tired.",
		"You die so often I begin to forget which one you are.",
		"Try, this time, to last more than a moment.",
	],
	"death_boss": [
		"Did you really believe this would be enough?",
		"You knew what I was. You came anyway.",
		"Your bones will burn alongside the rest.",
		"Crawl back, little corpse. Try harder this time.",
		"You came so far only to die at my feet. Touching.",
		"All those flames you stole, and still — not enough.",
		"You should have stayed upstairs, little corpse.",
		"I made you. Do you really think I cannot unmake you?",
	],
	"flame_drain": [
		"At last. The flames are mine.",
		"You did all the hard work for me, little corpse.",
		"I will wear these flames as my crown.",
	],
	"victory": [
		"Impossible…",
	],
	"phase_2_taunt": [
		"You hurt me? Cute. Now I am paying attention.",
		"Ah. So the toy has teeth after all.",
		"Enough play. Bleed for me properly.",
		"Did that flicker of strength surprise you? It surprised me.",
		"Very well. No more games, little corpse.",
	],
	"phase_3_taunt": [
		"You will not survive what comes next.",
		"You should be dead. Why are you not dead?",
		"This is what you wanted? This is your reward.",
		"Burn out, then. Like all the others before you.",
		"Last chance to kneel. Refuse, and I will tear what's left.",
	],
	"boss_idle": [
		"Run faster, little corpse. I have appointments.",
		"You swing like a child with a stick.",
		"Is this all you brought me? After everything?",
		"I made you better than this. Behave like it.",
		"Slower. You are getting slower. I can see it.",
		"You think hiding will help? Adorable.",
		"Every breath you take here is a kindness from me.",
		"Closer, little corpse. Let me see your face when you fail.",
		"My patience is a flame. It is going out.",
		"Strike me, then. Or do you need a moment?",
		"Disappointing. As always. As ever.",
		"You move as though I might tire. I will not.",
		"Such effort. Such waste.",
		"Yes — keep trying. I find it amusing.",
		"There is still time to lie down quietly.",
	],
}
```

- [ ] **Step 2: Run tests; confirm no regressions**

```bash
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/
```

Expected: 111/111 tests pass. No tests assert on specific line counts; this is pure content.

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/dialogue_banner.gd
git commit -m "content(taunts): expand necromancer line pool to 36 new lines

+7 death_normal, +4 death_boss, +5 phase_2_taunt, +5 phase_3_taunt,
+15 boss_idle. Phase/idle categories ready to be triggered in next task."
```

---

## Task 5: Phase Transition + Idle Taunt Triggers

**Files:**
- Modify: `scripts/entities/boss_dragon.gd`
- Create: `test/test_boss_taunts.gd`

This task wires the boss dragon to fire `phase_2_taunt`, `phase_3_taunt`, and `boss_idle` lines via the DialogueBanner. Uses two timer fields for cooldown enforcement so idle taunts don't step on phase taunts.

- [ ] **Step 1: Write failing tests for taunt timer logic**

Create `test/test_boss_taunts.gd`:

```gdscript
extends GdUnitTestSuite

const BossScript = preload("res://scripts/entities/boss_dragon.gd")

var boss: CharacterBody3D

func before_test() -> void:
	boss = auto_free(BossScript.new())
	add_child(boss)

func test_idle_taunt_fires_when_timer_exceeds_threshold() -> void:
	# After accumulating > IDLE_TAUNT_INTERVAL of fight time, _should_fire_idle_taunt() returns true.
	boss._idle_taunt_timer = 18.5
	boss._taunt_cooldown = 0.0
	assert_that(boss._should_fire_idle_taunt()).is_true()

func test_idle_taunt_blocked_when_cooldown_active() -> void:
	# Even at the threshold, cooldown > 0 prevents firing.
	boss._idle_taunt_timer = 18.5
	boss._taunt_cooldown = 2.0
	assert_that(boss._should_fire_idle_taunt()).is_false()

func test_idle_taunt_blocked_below_threshold() -> void:
	boss._idle_taunt_timer = 5.0
	boss._taunt_cooldown = 0.0
	assert_that(boss._should_fire_idle_taunt()).is_false()

func test_record_taunt_resets_idle_timer_and_sets_cooldown() -> void:
	# Calling _record_taunt_fired() resets idle timer to 0 and arms 5s cooldown.
	boss._idle_taunt_timer = 18.5
	boss._taunt_cooldown = 0.0
	boss._record_taunt_fired()
	assert_that(boss._idle_taunt_timer).is_equal_approx(0.0, 0.001)
	assert_that(boss._taunt_cooldown).is_equal_approx(5.0, 0.001)

func test_advance_taunt_timers_increments_idle_and_decays_cooldown() -> void:
	boss._idle_taunt_timer = 0.0
	boss._taunt_cooldown = 3.0
	boss._advance_taunt_timers(1.0)
	assert_that(boss._idle_taunt_timer).is_equal_approx(1.0, 0.001)
	assert_that(boss._taunt_cooldown).is_equal_approx(2.0, 0.001)

func test_advance_taunt_timers_floors_cooldown_at_zero() -> void:
	boss._idle_taunt_timer = 0.0
	boss._taunt_cooldown = 0.5
	boss._advance_taunt_timers(2.0)
	assert_that(boss._taunt_cooldown).is_equal_approx(0.0, 0.001)
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_boss_taunts.gd
```

Expected: All 6 tests fail with missing-field or missing-method errors.

- [ ] **Step 3: Add taunt fields and helpers to `boss_dragon.gd`**

Edit `scripts/entities/boss_dragon.gd`. Add new constants near the top (just below the `MAX_HP_*` constants from Task 2), add new fields with the existing `var` block, and add new helper functions before the closing of the file.

After the existing `const PHASE_3_HP_PCT: float = 0.33` line (around line 5), add:

```gdscript
const IDLE_TAUNT_INTERVAL: float = 18.0
const TAUNT_COOLDOWN_SECONDS: float = 5.0
```

After the existing `var _is_dead: bool = false` line (around line 21), add:

```gdscript
var _idle_taunt_timer: float = 0.0
var _taunt_cooldown: float = 0.0
```

Before the existing `func _check_phase_transition()` (around line 96), add these new helpers:

```gdscript
func _advance_taunt_timers(delta: float) -> void:
	_idle_taunt_timer += delta
	if _taunt_cooldown > 0.0:
		_taunt_cooldown = max(0.0, _taunt_cooldown - delta)

func _should_fire_idle_taunt() -> bool:
	return _idle_taunt_timer >= IDLE_TAUNT_INTERVAL and _taunt_cooldown <= 0.0

func _record_taunt_fired() -> void:
	_idle_taunt_timer = 0.0
	_taunt_cooldown = TAUNT_COOLDOWN_SECONDS

func _find_dialogue_banner() -> CanvasLayer:
	return get_tree().root.find_child("DialogueBanner", true, false) as CanvasLayer

func _show_taunt(category: String) -> void:
	var banner: CanvasLayer = _find_dialogue_banner()
	if banner == null:
		return
	if not banner.has_method("show_line"):
		return
	banner.show_line(category)
	_record_taunt_fired()
```

- [ ] **Step 4: Run unit tests; expect green**

```bash
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_boss_taunts.gd
```

Expected: 6/6 tests pass.

- [ ] **Step 5: Hook taunt timers into `_physics_process` and trigger idle taunts**

Edit `scripts/entities/boss_dragon.gd`. Modify the existing `_physics_process` method (lines 31-58 in the current file). Add the taunt-tick + idle-fire calls just after the `if _is_dead: return` early-out:

```gdscript
func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	_advance_taunt_timers(delta)
	if _should_fire_idle_taunt():
		_show_taunt("boss_idle")
	if _player == null or not is_instance_valid(_player):
		_find_player()
		if _player == null:
			return
	# … rest of _physics_process unchanged below this line …
```

(Leave the rest of `_physics_process` exactly as it is — `to_player`, `dist`, summon logic, gravity, `move_and_slide`. Just insert the two new lines after `_advance_taunt_timers`.)

- [ ] **Step 6: Hook phase-change taunts into `_check_phase_transition`**

Edit `scripts/entities/boss_dragon.gd`. Replace the existing `_check_phase_transition` method (lines 96-105) with:

```gdscript
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
		if _phase == 2:
			_show_taunt("phase_2_taunt")
		elif _phase == 3:
			_show_taunt("phase_3_taunt")
```

- [ ] **Step 7: Run full test suite; expect green**

```bash
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/
```

Expected: 117/117 tests pass (111 prior + 6 new).

- [ ] **Step 8: Manual playtest checkpoint**

Open the editor, start the game with `Debug.FAST_TEST = true` (so you can reach the boss quickly). Trigger the boss flow normally (deposit enough to fill all 6 pyres + descent prompt → fight). During the boss fight verify:
- An idle taunt appears within ~20 seconds of fight start.
- When the boss drops to ~66% HP, a `phase_2_taunt` line appears (NOT a `boss_idle` line — cooldown should suppress idle).
- When the boss drops to ~33% HP, a `phase_3_taunt` line appears.
- Idle taunts continue between phase transitions (every ~18s).
- Killing the boss still works — victory cutscene fires as before (no regression).

If any of the above fails, check `_find_dialogue_banner` is finding the banner in the courtyard scene (not the main_hall banner — both scenes have one).

- [ ] **Step 9: Commit**

```bash
git add scripts/entities/boss_dragon.gd test/test_boss_taunts.gd
git commit -m "feat(boss): wire phase + idle taunts to DialogueBanner

Phase 2 and Phase 3 transitions trigger their respective taunt lines.
Idle taunts fire every 18s of boss fight time; 5s cooldown prevents
idle from stepping on phase taunts."
```

---

## Final Validation

- [ ] **Step 1: Full test suite**

```bash
cd /c/Users/wyenk/OneDrive/Documents/godot/new-chance
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/
```

Expected: 117/117 tests pass.

- [ ] **Step 2: Confirm SHIP-mode still loads**

Edit `scripts/core/debug.gd`, set `FAST_TEST = false`. Open the editor. Confirm:
- The HUD shows pyre fill out of 100 (not 10).
- The cantrip stones UI prompt shows "Spend 12 total banked pyre fill."
- The soul altar UI shows "Drain 10 fill from a pyre."

Then **revert**:

```bash
git checkout -- scripts/core/debug.gd
```

(Remember to flip `FAST_TEST` to `false` for any release build — this revert is intentional during dev so playtest stays fast.)

- [ ] **Step 3: Push branch**

```bash
git push -u origin phase-6-ship-ready
```

- [ ] **Step 4: User end-to-end playtest (USER step)**

User runs an organic playtest with `FAST_TEST = true` to validate:
- Open arena spawning visibly weighted by proximity.
- New death taunts appear after dying.
- Boss phase transitions show their taunt lines.
- Idle boss taunts appear during fight, no overlap with phase taunts.

After user approval: merge to master, tag `v0.6-ship-ready`.
