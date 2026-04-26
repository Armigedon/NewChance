# Phase 4 — Meta-Progression Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal:** Add the meta-progression spine. Pyre fills now drive permanent player upgrades and unlock hub features. Save/load persists progress across sessions. Active skill cap grows from 3 → 9 as primary pyres reach 100%. In-run elder-soul scaling makes "should I take this elder?" a real choice. Two main hub features ship (Soul Altar, Cantrip Stones); two are stubbed (Sigil Forge, Trial Chamber).

**Architecture:**
- New `MetaProgress` autoload owns all permanent, per-color, run-independent state: pyre fills (mirrors `SoulEconomy._pyres` but reads from save), cap purchased (HP, sword damage, dash CD reductions), unlocked-hub-feature index, sigil equipped (stub).
- `SaveSystem` autoload handles serialization to `user://save.tres`.
- Milestone effects fire from `SoulEconomy.pyre_fill_changed` signal — listened to by MetaProgress, which applies passive bonuses + hub unlocks.
- Hub scenes get new interactable objects (Soul Altar pillar, Cantrip Stones pillar) that are visible/usable only when unlocked.
- Player and combat scripts read effective values from MetaProgress (e.g., `Player.effective_max_hp = MAX_HP + MetaProgress.cantrip_bonus("max_hp")`).
- In-run elder counter on `SkillSystem` (already counts elder unlocks); spawn rate / enemy HP scale with this count via Escalation.

**Tech Stack:** Godot 4.6.2, GDScript, GdUnit4. Same as Phases 1–3.

**Spec reference:** [`docs/superpowers/specs/2026-04-25-new-chance-design.md`](../specs/2026-04-25-new-chance-design.md) §4 Meta-progression.

**Phase 4 scope (vs full design):**
- ✅ Save/load system (`user://save.tres`)
- ✅ Pyre milestones at 25/50/75/100 with effects firing
- ✅ Active skill cap growth (3 → 9)
- ✅ In-run elder-soul scaling (+12% spawn rate / +8% enemy HP per elder taken)
- ✅ Soul Altar (drain X souls to start run with chosen skill)
- ✅ Cantrip Stones (3 permanent upgrades: max HP, sword damage, dash cooldown)
- ✅ Hub-feature unlock progression (1st pyre 50% = altar, 2nd 50% = cantrips, 3rd 50% = sigil stub, 4th 50% = trial stub)
- ✅ Final-pyre detection in descent prompt (sets up boss-trigger UX text — actual boss is Phase 5)
- ❌ Sigil Forge content (stub UI only)
- ❌ Trial Chamber content (stub UI only)
- ❌ Boss flow (Phase 5)

**Acceptance test:**
A player who has previously played and partially filled some pyres can launch the game, see those pyre fills preserved in the main hall (visible glow level + altar UI counts). Filling a pyre to 25% gives a permanent run-start damage bonus that color (visible HUD next run). Filling a pyre to 50% reveals a new hub object (first one = Soul Altar with usable UI). Filling to 100% increases the active skill cap by 1 (visible: at-cap behavior changes — replace prompt fires at 4th elder instead of 3rd). Taking an elder soul during a run measurably increases enemy density / HP for that run. Soul Altar lets you spend a chosen color's banked souls to start next run with that color's skill already unlocked. Cantrip Stones let you spend banked souls on max HP / sword damage / dash cooldown reductions. All saves persist across game restarts.

---

## File structure

**Created:**
```
scripts/core/
├── meta_progress.gd          # Autoload: pyre fills, cantrips, hub unlocks, sigil
└── save_system.gd            # Autoload: serialize / deserialize MetaProgress to user://save.tres
scripts/interactables/
├── soul_altar.gd             # 3D interactable pillar in main hall
└── cantrip_stones.gd         # 3D interactable pillar in main hall
scripts/ui/
├── soul_altar_ui.gd          # Modal: pick color + spend souls to pre-unlock skill for next run
└── cantrip_stones_ui.gd      # Modal: 3 buy-buttons for max HP / sword dmg / dash CD
scenes/interactables/
├── soul_altar.tscn
└── cantrip_stones.tscn
scenes/ui/
├── soul_altar_ui.tscn
└── cantrip_stones_ui.tscn
test/
├── test_meta_progress.gd
├── test_save_system.gd
└── test_pyre_milestones.gd
```

**Modified:**
- `scripts/core/soul_economy.gd` — already emits `pyre_fill_changed`; MetaProgress will subscribe.
- `scripts/core/game_state.gd` — `end_run` now also calls `SaveSystem.save_meta()` to persist pyre fills after deposit.
- `scripts/core/escalation.gd` — `roll_tier` and `spawn_rate_factor` now factor in `_in_run_elder_count` (per-run elder soul taken count). Add `set_in_run_elder_count(n)` method.
- `scripts/skills/skill_system.gd` — `add_elder` increments a counter and notifies Escalation.
- `scripts/entities/player.gd` — read effective max HP from MetaProgress.cantrip_bonus.
- `scripts/entities/sword.gd` — read effective base_damage from MetaProgress.cantrip_bonus.
- `scenes/world/main_hall.tscn` — add SoulAltar and CantripStones interactables (initially hidden, made visible by MetaProgress on hub-unlock event).
- `scripts/ui/descent_prompt.gd` — detect "this deposit fills the 6th primary pyre" and add a "Descend & fight" option text (boss trigger marker; actual cutscene + boss is Phase 5 — for Phase 4 just print a message).
- `project.godot` — register MetaProgress + SaveSystem autoloads.

---

## Task 1: SaveSystem autoload

**Files:**
- Create: `scripts/core/save_system.gd`
- Create: `test/test_save_system.gd`
- Modify: `project.godot` (autoload)

### Step 1: Write failing tests

Create `test/test_save_system.gd`:

```gdscript
extends GdUnitTestSuite

const SaveSystemScript = preload("res://scripts/core/save_system.gd")

const TEST_PATH: String = "user://test_save.tres"

func after_test() -> void:
	# clean up test save
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("test_save.tres"):
		dir.remove("test_save.tres")

func test_save_round_trip_pyres() -> void:
	var data: Dictionary = {"pyres": {"red": 100, "blue": 50}}
	SaveSystemScript.save_to_path(TEST_PATH, data)
	var loaded: Dictionary = SaveSystemScript.load_from_path(TEST_PATH)
	assert_that(loaded.get("pyres", {})).is_equal({"red": 100, "blue": 50})

func test_load_missing_file_returns_empty() -> void:
	var loaded: Dictionary = SaveSystemScript.load_from_path("user://nonexistent.tres")
	assert_that(loaded).is_empty()

func test_save_round_trip_complex() -> void:
	var data: Dictionary = {
		"pyres": {"red": 50, "blue": 75},
		"cantrips": {"max_hp": 2, "sword_damage": 1},
		"hub_features_unlocked": 2,
		"sigil_equipped": "elder_drop_bonus",
	}
	SaveSystemScript.save_to_path(TEST_PATH, data)
	var loaded: Dictionary = SaveSystemScript.load_from_path(TEST_PATH)
	assert_that(loaded).is_equal(data)
```

### Step 2: Run tests — verify failures

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_save_system.gd --ignoreHeadlessMode
```

### Step 3: Implement SaveSystem

Create `scripts/core/save_system.gd`:

```gdscript
extends Node

# Lightweight save: serializes a Dictionary to a Resource and writes to user://.
# Format-versioned for future migrations.

const SAVE_PATH: String = "user://save.tres"
const SAVE_VERSION: int = 1

static func save_to_path(path: String, data: Dictionary) -> Error:
	var res := Resource.new()
	res.set_meta("version", SAVE_VERSION)
	res.set_meta("data", data.duplicate(true))
	return ResourceSaver.save(res, path)

static func load_from_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var res = load(path)
	if res == null:
		return {}
	return res.get_meta("data", {})

static func save(data: Dictionary) -> Error:
	return save_to_path(SAVE_PATH, data)

static func load_save() -> Dictionary:
	return load_from_path(SAVE_PATH)
```

### Step 4: Register autoload

Add to project.godot `[autoload]`:
```
SaveSystem="*res://scripts/core/save_system.gd"
```

### Step 5: Verify tests pass

Run the test command from Step 2. Then full suite:
```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
```

Expected: 79 tests pass (76 + 3 new).

### Step 6: Commit

```bash
git add scripts/core/save_system.gd test/test_save_system.gd project.godot
git commit -m "feat(save): SaveSystem autoload with Resource-based round-trip"
```

---

## Task 2: MetaProgress autoload

**Files:**
- Create: `scripts/core/meta_progress.gd`
- Create: `test/test_meta_progress.gd`
- Modify: `project.godot` (autoload)

### Step 1: Write failing tests

Create `test/test_meta_progress.gd`:

```gdscript
extends GdUnitTestSuite

const MetaProgressScript = preload("res://scripts/core/meta_progress.gd")

var mp: Node

func before_test() -> void:
	mp = auto_free(MetaProgressScript.new())
	add_child(mp)

func test_starts_with_default_state() -> void:
	assert_that(mp.cantrip_level("max_hp")).is_equal(0)
	assert_that(mp.cantrip_bonus("max_hp")).is_equal(0)
	assert_that(mp.hub_features_unlocked()).is_equal(0)
	assert_that(mp.active_skill_cap_bonus()).is_equal(0)

func test_buy_cantrip_increments_level() -> void:
	mp.buy_cantrip("max_hp")
	assert_that(mp.cantrip_level("max_hp")).is_equal(1)

func test_buy_cantrip_increases_bonus() -> void:
	# Each level of max_hp adds +20
	mp.buy_cantrip("max_hp")
	mp.buy_cantrip("max_hp")
	assert_that(mp.cantrip_bonus("max_hp")).is_equal(40)

func test_buy_cantrip_max_level_caps() -> void:
	for i in range(20):
		mp.buy_cantrip("max_hp")
	assert_that(mp.cantrip_level("max_hp")).is_equal(MetaProgressScript.CANTRIP_MAX_LEVEL)

func test_unlock_next_hub_feature() -> void:
	mp.unlock_next_hub_feature()
	mp.unlock_next_hub_feature()
	assert_that(mp.hub_features_unlocked()).is_equal(2)

func test_hub_features_capped_at_4() -> void:
	for i in range(10):
		mp.unlock_next_hub_feature()
	assert_that(mp.hub_features_unlocked()).is_equal(4)

func test_active_skill_cap_bonus_increments_per_full_pyre() -> void:
	mp.on_pyre_full("red")
	mp.on_pyre_full("blue")
	assert_that(mp.active_skill_cap_bonus()).is_equal(2)

func test_pyre_full_only_counts_once_per_color() -> void:
	mp.on_pyre_full("red")
	mp.on_pyre_full("red")
	assert_that(mp.active_skill_cap_bonus()).is_equal(1)

func test_passive_color_bonus_at_25_percent() -> void:
	# At 25%, color gets +5% damage bonus
	mp.on_pyre_milestone("red", 25)
	assert_that(mp.color_damage_bonus("red")).is_equal_approx(0.05, 0.001)

func test_passive_color_bonus_increases_at_75_percent() -> void:
	# At 75%, color gets +10% damage bonus
	mp.on_pyre_milestone("red", 25)
	mp.on_pyre_milestone("red", 75)
	assert_that(mp.color_damage_bonus("red")).is_equal_approx(0.10, 0.001)

func test_to_dict_serializes_full_state() -> void:
	mp.buy_cantrip("max_hp")
	mp.on_pyre_full("red")
	mp.on_pyre_milestone("red", 25)
	var d: Dictionary = mp.to_dict()
	assert_that(d.has("cantrips")).is_true()
	assert_that(d.has("hub_features_unlocked")).is_true()
	assert_that(d.has("filled_pyres")).is_true()
	assert_that(d.has("pyre_milestones")).is_true()

func test_from_dict_restores_state() -> void:
	mp.buy_cantrip("sword_damage")
	mp.on_pyre_full("blue")
	var d: Dictionary = mp.to_dict()
	# Fresh instance
	var mp2: Node = auto_free(MetaProgressScript.new())
	add_child(mp2)
	mp2.from_dict(d)
	assert_that(mp2.cantrip_level("sword_damage")).is_equal(1)
	assert_that(mp2.active_skill_cap_bonus()).is_equal(1)
```

### Step 2: Run tests — verify failures

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_meta_progress.gd --ignoreHeadlessMode
```

### Step 3: Implement MetaProgress

Create `scripts/core/meta_progress.gd`:

```gdscript
extends Node

const COLORS: Array[String] = ["red", "blue", "green", "purple", "gold", "white"]
const CANTRIP_KEYS: Array[String] = ["max_hp", "sword_damage", "dash_cooldown"]
const CANTRIP_MAX_LEVEL: int = 5
const CANTRIP_BONUSES: Dictionary = {
	"max_hp": 20,           # +20 HP per level
	"sword_damage": 3,      # +3 damage per level
	"dash_cooldown": -0.2,  # -0.2s per level (faster dash)
}
const HUB_FEATURE_MAX: int = 4

# 25% milestone = +5% color damage; 75% milestone = +10% (cumulative cap at +10%).
const PYRE_DAMAGE_BONUS_25: float = 0.05
const PYRE_DAMAGE_BONUS_75: float = 0.10

signal hub_feature_unlocked(index: int)
signal cantrip_purchased(key: String, new_level: int)

var _cantrips: Dictionary = {}
var _hub_features_unlocked: int = 0
var _filled_pyres: Dictionary = {}  # color -> bool
var _pyre_milestones: Dictionary = {}  # color -> int (last milestone reached)

func _ready() -> void:
	_init_defaults()

func _init_defaults() -> void:
	_cantrips.clear()
	for k in CANTRIP_KEYS:
		_cantrips[k] = 0
	_hub_features_unlocked = 0
	_filled_pyres.clear()
	for c in COLORS:
		_filled_pyres[c] = false
	_pyre_milestones.clear()
	for c in COLORS:
		_pyre_milestones[c] = 0

# --- Cantrips ---
func cantrip_level(key: String) -> int:
	return _cantrips.get(key, 0)

func cantrip_bonus(key: String) -> int:
	# Returns total bonus value (level × per-level value), as int. For dash_cooldown it's negative.
	var lvl: int = cantrip_level(key)
	var per_level = CANTRIP_BONUSES.get(key, 0)
	if per_level is int:
		return lvl * per_level
	return int(lvl * per_level)

func cantrip_bonus_float(key: String) -> float:
	# Float version for fractional values like dash_cooldown.
	var lvl: int = cantrip_level(key)
	var per_level = CANTRIP_BONUSES.get(key, 0)
	return float(lvl) * float(per_level)

func buy_cantrip(key: String) -> bool:
	if not (key in CANTRIP_KEYS):
		return false
	if _cantrips[key] >= CANTRIP_MAX_LEVEL:
		return false
	_cantrips[key] += 1
	cantrip_purchased.emit(key, _cantrips[key])
	return true

# --- Hub features ---
func hub_features_unlocked() -> int:
	return _hub_features_unlocked

func unlock_next_hub_feature() -> void:
	if _hub_features_unlocked >= HUB_FEATURE_MAX:
		return
	_hub_features_unlocked += 1
	hub_feature_unlocked.emit(_hub_features_unlocked)

# --- Pyre milestones ---
func on_pyre_milestone(color: String, milestone: int) -> void:
	# Called by SoulEconomy when a pyre crosses 25/50/75/100. Idempotent within a milestone level.
	if not (color in COLORS):
		return
	var prior: int = _pyre_milestones.get(color, 0)
	if milestone <= prior:
		return  # already at or past this milestone
	_pyre_milestones[color] = milestone
	if milestone == 50:
		unlock_next_hub_feature()
	# 25 and 75 just record the milestone for color_damage_bonus to read.

func on_pyre_full(color: String) -> void:
	# Called when pyre hits 100. Marks +1 active skill cap bonus.
	if not (color in COLORS):
		return
	if _filled_pyres.get(color, false):
		return
	_filled_pyres[color] = true
	# 100 also IS a milestone; record it.
	_pyre_milestones[color] = 100

func active_skill_cap_bonus() -> int:
	var n: int = 0
	for c in COLORS:
		if _filled_pyres.get(c, false):
			n += 1
	return n

func color_damage_bonus(color: String) -> float:
	var milestone: int = _pyre_milestones.get(color, 0)
	if milestone >= 75:
		return PYRE_DAMAGE_BONUS_75
	if milestone >= 25:
		return PYRE_DAMAGE_BONUS_25
	return 0.0

# --- Save / load serialization ---
func to_dict() -> Dictionary:
	return {
		"cantrips": _cantrips.duplicate(),
		"hub_features_unlocked": _hub_features_unlocked,
		"filled_pyres": _filled_pyres.duplicate(),
		"pyre_milestones": _pyre_milestones.duplicate(),
	}

func from_dict(d: Dictionary) -> void:
	_init_defaults()
	if d.has("cantrips"):
		for k in CANTRIP_KEYS:
			_cantrips[k] = int(d["cantrips"].get(k, 0))
	_hub_features_unlocked = int(d.get("hub_features_unlocked", 0))
	if d.has("filled_pyres"):
		for c in COLORS:
			_filled_pyres[c] = bool(d["filled_pyres"].get(c, false))
	if d.has("pyre_milestones"):
		for c in COLORS:
			_pyre_milestones[c] = int(d["pyre_milestones"].get(c, 0))
```

### Step 4: Run tests pass

Run the test from Step 2 again. Expected 12/12. Then full suite (79 + 12 = 91 tests).

### Step 5: Register autoload

Add to project.godot `[autoload]`:
```
MetaProgress="*res://scripts/core/meta_progress.gd"
```

### Step 6: Commit

```bash
git add scripts/core/meta_progress.gd test/test_meta_progress.gd project.godot
git commit -m "feat(meta): MetaProgress autoload (cantrips, hub unlocks, pyre milestones, cap bonus, save dict)"
```

---

## Task 3: Wire SoulEconomy → MetaProgress milestone events

**Files:**
- Modify: `scripts/core/meta_progress.gd` — connect to SoulEconomy.pyre_fill_changed in _ready
- Modify: `scripts/core/game_state.gd` — load save on game start, save on end_run

### Step 1: Connect MetaProgress to SoulEconomy.pyre_fill_changed

In `meta_progress.gd` `_ready`, after `_init_defaults()`, add:

```gdscript
	SoulEconomy.pyre_fill_changed.connect(_on_pyre_fill_changed)

func _on_pyre_fill_changed(color: String, new_fill: int) -> void:
	# PYRE_CAP is 250. Milestones at 25%/50%/75%/100% = 62.5/125/187.5/250.
	var pct: float = (float(new_fill) / float(SoulEconomy.PYRE_CAP)) * 100.0
	if pct >= 100.0:
		on_pyre_milestone(color, 100)
		on_pyre_full(color)
	elif pct >= 75.0:
		on_pyre_milestone(color, 75)
	elif pct >= 50.0:
		on_pyre_milestone(color, 50)
	elif pct >= 25.0:
		on_pyre_milestone(color, 25)
```

### Step 2: Wire SaveSystem to GameState.end_run + game start

In `game_state.gd`, modify `_ready` (or add one) to load save on game start and apply to MetaProgress:

```gdscript
func _ready() -> void:
	var save_data: Dictionary = SaveSystem.load_save()
	if save_data.has("meta"):
		MetaProgress.from_dict(save_data["meta"])
	if save_data.has("pyres"):
		# Restore pyre fills into SoulEconomy
		for color in save_data["pyres"]:
			var fill: int = int(save_data["pyres"][color])
			# Manually set _pyres (no public setter exists; use add_to_carry+deposit as a workaround
			# OR add a SoulEconomy.set_pyre_fill(color, fill) method).
			SoulEconomy._pyres[color] = fill  # direct access — see notes
```

That direct-access is hacky. Better: add a public method to SoulEconomy:

In `soul_economy.gd`, add:
```gdscript
func set_pyre_fill(color: String, fill: int) -> void:
	if not (color in COLORS):
		return
	_pyres[color] = clamp(fill, 0, PYRE_CAP)
	if _pyres[color] >= PYRE_CAP:
		_filled_pyres[color] = true
```

Then in game_state._ready, use `SoulEconomy.set_pyre_fill(color, fill)`.

Modify `end_run` to save after side effects:

```gdscript
func end_run(outcome: Outcome) -> void:
	if outcome == Outcome.DESCENDED:
		SoulEconomy.deposit_to_pyres()
	elif outcome == Outcome.DIED:
		SoulEconomy.clear_carry()
	run_ended.emit(outcome)
	Escalation.reset()
	# Persist meta progress + pyre fills
	var save_data: Dictionary = {
		"meta": MetaProgress.to_dict(),
		"pyres": _pyre_fills_dict(),
	}
	SaveSystem.save(save_data)
	transition_to(Location.MAIN_HALL)

func _pyre_fills_dict() -> Dictionary:
	var d: Dictionary = {}
	for c in SoulEconomy.COLORS:
		d[c] = SoulEconomy.pyre_fill(c)
	return d
```

### Step 3: Verify tests still pass

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
```

Existing tests use `before_test` to reset `SoulEconomy.reset_meta()`, which clears all pyre fills — unaffected by save state at runtime. The new code paths don't fire in unit tests (no save file, no pyre_fill_changed unless tests cause it).

Expected: 91 tests pass.

### Step 4: Commit

```bash
git add scripts/core/meta_progress.gd scripts/core/game_state.gd scripts/core/soul_economy.gd
git commit -m "feat(meta): wire SoulEconomy.pyre_fill_changed → milestones; load on start, save on end_run"
```

---

## Task 4: SkillSystem cap reads from MetaProgress + in-run elder counter

**Files:**
- Modify: `scripts/skills/skill_system.gd`
- Modify: `scripts/core/escalation.gd`
- Modify: `test/test_skill_system.gd` (verify cap is dynamic)

### Step 1: SkillSystem — cap = base + MetaProgress bonus

In `scripts/skills/skill_system.gd`, change:

```gdscript
var _cap: int = 3
```

to:

```gdscript
const BASE_CAP: int = 3
```

And replace `func cap()`:

```gdscript
func cap() -> int:
	return BASE_CAP + MetaProgress.active_skill_cap_bonus()
```

Remove `func set_cap(n)` (unless still needed for tests). Tests use `set_cap` — keep it as a test-only override:

```gdscript
var _cap_override: int = -1

func set_cap(n: int) -> void:
	_cap_override = n

func cap() -> int:
	if _cap_override >= 0:
		return _cap_override
	return BASE_CAP + MetaProgress.active_skill_cap_bonus()
```

Update internal `_cap` references in add_elder to use `cap()`:

```gdscript
func add_elder(color: String) -> int:
	if _skills.size() >= cap():
		at_cap_replace_prompt_requested.emit(color)
		return AddResult.AT_CAP
	# ... rest unchanged
```

### Step 2: Add in-run elder counter

In skill_system.gd, add:

```gdscript
var _in_run_elder_count: int = 0
```

In `add_elder` (after the cap check, when actually unlocking):

```gdscript
	_in_run_elder_count += 1
	Escalation.set_in_run_elder_count(_in_run_elder_count)
```

In `clear()`:

```gdscript
	_in_run_elder_count = 0
	Escalation.set_in_run_elder_count(0)
```

### Step 3: Escalation reads in-run elder count

In `scripts/core/escalation.gd`, add:

```gdscript
var _in_run_elders: int = 0

func set_in_run_elder_count(n: int) -> void:
	_in_run_elders = n
```

Modify `spawn_rate_factor`:

```gdscript
func spawn_rate_factor(heat: float) -> float:
	# Heat scaling + per-elder spawn rate bump (12% per elder taken in current run)
	var heat_factor: float = 1.0 + (heat / HEAT_CAP) * 2.0
	var elder_factor: float = 1.0 + 0.12 * float(_in_run_elders)
	return heat_factor * elder_factor
```

Add a separate getter for enemy HP scaling (used by corner_spawner):

```gdscript
func enemy_hp_factor() -> float:
	return 1.0 + 0.08 * float(_in_run_elders)
```

In `reset()`, also reset `_in_run_elders`:

```gdscript
func reset() -> void:
	# ... existing code
	_in_run_elders = 0
```

### Step 4: Apply HP factor in corner_spawner

In `corner_spawner.gd` `_spawn`, after `enemy = scene.instantiate()`:

```gdscript
	# In-run elder scaling boosts spawned enemy HP
	if "max_hp" in enemy:
		enemy.max_hp = int(enemy.max_hp * Escalation.enemy_hp_factor())
```

### Step 5: Verify tests

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
```

Existing skill_system tests use `set_cap(3)` — they should still work via the test-only override. Existing `spawn_rate_factor` tests in test_escalation use specific values:
- `spawn_rate_factor(0)` → 1.0 (no in-run elders)
- `spawn_rate_factor(50)` → 2.0
- `spawn_rate_factor(100)` → 3.0

Without elders, `elder_factor = 1.0` so heat_factor = unchanged. Tests still pass.

Expected: 91 tests pass.

### Step 6: Commit

```bash
git add scripts/skills/skill_system.gd scripts/core/escalation.gd scripts/world/corner_spawner.gd
git commit -m "feat(scaling): cap from MetaProgress + in-run elder counter affects spawn rate + enemy HP"
```

---

## Task 5: Soul Altar interactable + UI

**Files:**
- Create: `scenes/interactables/soul_altar.tscn`
- Create: `scripts/interactables/soul_altar.gd`
- Create: `scenes/ui/soul_altar_ui.tscn`
- Create: `scripts/ui/soul_altar_ui.gd`
- Modify: `scripts/core/meta_progress.gd` (add `start_with_skill: String` for next-run head start)
- Modify: `scripts/entities/player.gd` (read `MetaProgress.start_with_skill` in `_ready` and pre-unlock if set)
- Modify: `scenes/world/main_hall.tscn` — instance SoulAltar (initially hidden, made visible by hub-feature unlock)

### Step 1: Add start_with_skill to MetaProgress

In `meta_progress.gd`, add:
```gdscript
var _start_with_skill: String = ""

func set_start_with_skill(color: String) -> void:
	_start_with_skill = color

func consume_start_with_skill() -> String:
	# Returns the queued color and clears it (one-shot per run).
	var c: String = _start_with_skill
	_start_with_skill = ""
	return c
```

Also include in `to_dict` / `from_dict`.

### Step 2: Implement soul_altar.gd

```gdscript
extends Area3D

@export var ui_path: NodePath

var _ui: CanvasLayer = null

func _ready() -> void:
	visible = MetaProgress.hub_features_unlocked() >= 1
	MetaProgress.hub_feature_unlocked.connect(_on_unlock)
	body_entered.connect(_on_body_entered)
	if ui_path != NodePath(""):
		_ui = get_node(ui_path)

func _on_unlock(_idx: int) -> void:
	visible = MetaProgress.hub_features_unlocked() >= 1

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if _ui == null:
		return
	_ui.show_prompt()
```

### Step 3: Implement soul_altar_ui.gd

```gdscript
extends CanvasLayer

@onready var _summary: Label = $Center/Panel/VBox/Summary
@onready var _color_buttons: Array = [
	$Center/Panel/VBox/Buttons/Red,
	$Center/Panel/VBox/Buttons/Blue,
	$Center/Panel/VBox/Buttons/Green,
	$Center/Panel/VBox/Buttons/Purple,
	$Center/Panel/VBox/Buttons/Gold,
	$Center/Panel/VBox/Buttons/White,
]
@onready var _close_btn: Button = $Center/Panel/VBox/Close

const ALTAR_COST: int = 25  # banked pyre fill drained per chosen color

func _ready() -> void:
	visible = false
	for i in range(_color_buttons.size()):
		var color: String = SoulEconomy.COLORS[i]
		_color_buttons[i].pressed.connect(func(): _on_pick(color))
	_close_btn.pressed.connect(hide_prompt)

func show_prompt() -> void:
	_summary.text = (
		"Drain %d fill from a pyre to start your next run with that color's skill already unlocked.\n" % ALTAR_COST
		+ "(Currently queued: %s)" % (MetaProgress._start_with_skill if MetaProgress._start_with_skill != "" else "none")
	)
	for i in range(_color_buttons.size()):
		var color: String = SoulEconomy.COLORS[i]
		var fill: int = SoulEconomy.pyre_fill(color)
		var btn: Button = _color_buttons[i]
		btn.text = "%s (pyre: %d)" % [color.capitalize(), fill]
		btn.disabled = fill < ALTAR_COST
	visible = true
	get_tree().paused = true

func hide_prompt() -> void:
	visible = false
	get_tree().paused = false

func _on_pick(color: String) -> void:
	if SoulEconomy.pyre_fill(color) < ALTAR_COST:
		return
	SoulEconomy.set_pyre_fill(color, SoulEconomy.pyre_fill(color) - ALTAR_COST)
	MetaProgress.set_start_with_skill(color)
	hide_prompt()
```

### Step 4: Build the .tscn files

`scenes/interactables/soul_altar.tscn`:

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/interactables/soul_altar.gd" id="1_altar"]

[sub_resource type="BoxShape3D" id="altar_shape"]
size = Vector3(2, 2, 2)

[sub_resource type="CylinderMesh" id="altar_mesh"]
top_radius = 0.7
bottom_radius = 0.9
height = 1.6

[sub_resource type="StandardMaterial3D" id="altar_mat"]
albedo_color = Color(0.6, 0.5, 0.7, 1)
emission_enabled = true
emission = Color(0.4, 0.3, 0.6, 1)
emission_energy_multiplier = 1.5

[node name="SoulAltar" type="Area3D"]
script = ExtResource("1_altar")

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
shape = SubResource("altar_shape")

[node name="Mesh" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.8, 0)
mesh = SubResource("altar_mesh")
material_override = SubResource("altar_mat")
```

`scenes/ui/soul_altar_ui.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/soul_altar_ui.gd" id="1_altarui"]

[node name="SoulAltarUI" type="CanvasLayer"]
process_mode = 3
script = ExtResource("1_altarui")

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
text = "Soul Altar"
autowrap_mode = 2

[node name="Buttons" type="VBoxContainer" parent="Center/Panel/VBox"]
layout_mode = 2
theme_override_constants/separation = 6

[node name="Red" type="Button" parent="Center/Panel/VBox/Buttons"]
layout_mode = 2
text = "Red"

[node name="Blue" type="Button" parent="Center/Panel/VBox/Buttons"]
layout_mode = 2
text = "Blue"

[node name="Green" type="Button" parent="Center/Panel/VBox/Buttons"]
layout_mode = 2
text = "Green"

[node name="Purple" type="Button" parent="Center/Panel/VBox/Buttons"]
layout_mode = 2
text = "Purple"

[node name="Gold" type="Button" parent="Center/Panel/VBox/Buttons"]
layout_mode = 2
text = "Gold"

[node name="White" type="Button" parent="Center/Panel/VBox/Buttons"]
layout_mode = 2
text = "White"

[node name="Close" type="Button" parent="Center/Panel/VBox"]
layout_mode = 2
text = "Close"
```

### Step 5: Add SoulAltar + UI to main_hall.tscn

Read `scenes/world/main_hall.tscn`. Add ext_resources for the two scenes, and add nodes:

```
[node name="SoulAltar" parent="." instance=ExtResource("X_altar")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 5, 0, 0)
ui_path = NodePath("../SoulAltarUI")

[node name="SoulAltarUI" parent="." instance=ExtResource("Y_altarui")]
```

(Position X=5 puts it on the right side of the main hall, opposite the pyre on the left.)

### Step 6: Player consumes start_with_skill on _ready

In `scripts/entities/player.gd` `_ready` (existing function), add at the end:

```gdscript
	var queued: String = MetaProgress.consume_start_with_skill()
	if queued != "" and _skill_system != null:
		_skill_system.add_minor(queued)
```

(`add_minor` with no skills unlocked → unlocks Skill 1 with that color.)

### Step 7: Verify import + tests

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . --import 2>&1 | grep -i error | head -10
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
```

### Step 8: Commit

```bash
git add scripts/core/meta_progress.gd scripts/interactables/soul_altar.gd scenes/interactables/soul_altar.tscn scripts/ui/soul_altar_ui.gd scenes/ui/soul_altar_ui.tscn scripts/entities/player.gd scenes/world/main_hall.tscn
git commit -m "feat(soul-altar): drain banked souls to pre-unlock skill for next run (1st hub feature)"
```

---

## Task 6: Cantrip Stones interactable + UI

**Files:** Same pattern as Task 5 — interactable + UI + scene wiring.

- Create: `scripts/interactables/cantrip_stones.gd`
- Create: `scripts/ui/cantrip_stones_ui.gd`
- Create: `scenes/interactables/cantrip_stones.tscn`
- Create: `scenes/ui/cantrip_stones_ui.tscn`
- Modify: `scripts/entities/player.gd` (read effective max_hp from MetaProgress.cantrip_bonus)
- Modify: `scripts/entities/sword.gd` (read effective base_damage)
- Modify: `scenes/world/main_hall.tscn`

### Step 1: cantrip_stones.gd (similar to soul_altar.gd)

```gdscript
extends Area3D

@export var ui_path: NodePath

var _ui: CanvasLayer = null

func _ready() -> void:
	visible = MetaProgress.hub_features_unlocked() >= 2
	MetaProgress.hub_feature_unlocked.connect(_on_unlock)
	body_entered.connect(_on_body_entered)
	if ui_path != NodePath(""):
		_ui = get_node(ui_path)

func _on_unlock(_idx: int) -> void:
	visible = MetaProgress.hub_features_unlocked() >= 2

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if _ui == null:
		return
	_ui.show_prompt()
```

### Step 2: cantrip_stones_ui.gd

```gdscript
extends CanvasLayer

@onready var _summary: Label = $Center/Panel/VBox/Summary
@onready var _btn_max_hp: Button = $Center/Panel/VBox/Buttons/MaxHP
@onready var _btn_sword: Button = $Center/Panel/VBox/Buttons/Sword
@onready var _btn_dash: Button = $Center/Panel/VBox/Buttons/Dash
@onready var _close_btn: Button = $Center/Panel/VBox/Close

const STONE_COST: int = 30  # banked pyre fill (any color) per upgrade

func _ready() -> void:
	visible = false
	_btn_max_hp.pressed.connect(func(): _buy("max_hp"))
	_btn_sword.pressed.connect(func(): _buy("sword_damage"))
	_btn_dash.pressed.connect(func(): _buy("dash_cooldown"))
	_close_btn.pressed.connect(hide_prompt)

func show_prompt() -> void:
	var total_fill: int = 0
	for c in SoulEconomy.COLORS:
		total_fill += SoulEconomy.pyre_fill(c)
	_summary.text = (
		"Spend %d total banked pyre fill (across all colors) per upgrade.\n" % STONE_COST
		+ "Total pyre fill available: %d\n" % total_fill
		+ "(Each level: +20 HP / +3 sword damage / -0.2s dash CD; max 5 levels)"
	)
	_btn_max_hp.text = "Max HP (%d/5)" % MetaProgress.cantrip_level("max_hp")
	_btn_sword.text = "Sword Damage (%d/5)" % MetaProgress.cantrip_level("sword_damage")
	_btn_dash.text = "Dash Cooldown (%d/5)" % MetaProgress.cantrip_level("dash_cooldown")
	_btn_max_hp.disabled = total_fill < STONE_COST or MetaProgress.cantrip_level("max_hp") >= MetaProgress.CANTRIP_MAX_LEVEL
	_btn_sword.disabled = total_fill < STONE_COST or MetaProgress.cantrip_level("sword_damage") >= MetaProgress.CANTRIP_MAX_LEVEL
	_btn_dash.disabled = total_fill < STONE_COST or MetaProgress.cantrip_level("dash_cooldown") >= MetaProgress.CANTRIP_MAX_LEVEL
	visible = true
	get_tree().paused = true

func hide_prompt() -> void:
	visible = false
	get_tree().paused = false

func _buy(key: String) -> void:
	# Drain STONE_COST from banked pyre fill (greedy from highest-fill color)
	var remaining: int = STONE_COST
	for c in SoulEconomy.COLORS:
		if remaining == 0:
			break
		var fill: int = SoulEconomy.pyre_fill(c)
		if fill <= 0:
			continue
		var take: int = min(fill, remaining)
		SoulEconomy.set_pyre_fill(c, fill - take)
		remaining -= take
	if remaining > 0:
		# Couldn't afford after all — restore? Simpler: cancel the buy in this rare case.
		# (Pre-check in show_prompt should have disabled the button.)
		return
	MetaProgress.buy_cantrip(key)
	# Refresh prompt
	show_prompt()
```

### Step 3: Build the .tscn files

`scenes/interactables/cantrip_stones.tscn`: similar to soul_altar.tscn, different mesh (3 small standing stones — use 3 BoxMesh children or a single CylinderMesh tinted differently). For brevity, use a single grey cylinder.

`scenes/ui/cantrip_stones_ui.tscn`: similar to soul_altar_ui.tscn, three buy buttons (MaxHP / Sword / Dash) instead of color buttons.

(Detailed .tscn text omitted for brevity — follow the pattern from Task 5 with material color `Color(0.6, 0.6, 0.65, 1)` and three buttons named MaxHP / Sword / Dash.)

### Step 4: Player and Sword read effective values from MetaProgress

In `player.gd`:

```gdscript
func _ready() -> void:
	# ... existing code ...
	var bonus_hp: int = MetaProgress.cantrip_bonus("max_hp")
	max_hp += bonus_hp
	hp = max_hp
	var bonus_dash: float = MetaProgress.cantrip_bonus_float("dash_cooldown")
	dash_cooldown = max(0.2, dash_cooldown + bonus_dash)
	# ... existing skill_system signal connects, etc.
```

Wait — `player.gd` doesn't have a `max_hp` field. The constant is `MAX_HP`. Migrate it like welp.gd did:

Change `const MAX_HP: int = 100` → `@export var max_hp: int = 100`. Update references. Then add the bonus application in `_ready`.

In `sword.gd`:

```gdscript
func _ready() -> void:
	var bonus: int = MetaProgress.cantrip_bonus("sword_damage")
	base_damage += bonus
```

### Step 5: Add CantripStones + UI to main_hall.tscn

Same pattern as Task 5. Place CantripStones at e.g. (-5, 0, 0) on the left.

### Step 6: Verify + commit

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . --import 2>&1 | grep -i error | head -10
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
git add scripts/interactables/cantrip_stones.gd scenes/interactables/cantrip_stones.tscn scripts/ui/cantrip_stones_ui.gd scenes/ui/cantrip_stones_ui.tscn scripts/entities/player.gd scripts/entities/sword.gd scenes/world/main_hall.tscn
git commit -m "feat(cantrip-stones): permanent HP/sword/dash upgrades (2nd hub feature)"
```

---

## Task 7: Sigil Forge + Trial Chamber stubs

**Files:**
- Create: `scripts/interactables/sigil_forge.gd` (visible at hub_features_unlocked >= 3, body_entered shows a placeholder dialog)
- Create: `scripts/interactables/trial_chamber.gd` (visible at >= 4, placeholder dialog)
- Create: `scenes/interactables/sigil_forge.tscn` (cylinder mesh, distinct color)
- Create: `scenes/interactables/trial_chamber.tscn` (cylinder mesh, distinct color)
- Modify: `scenes/world/main_hall.tscn` — instance both

These are placeholder UIs. They show a label like "Sigil Forge — coming in v0.4.1" and a Close button. Not implementing the actual sigil/trial mechanics in Phase 4.

### Step 1: stub interactable + UI

```gdscript
# scripts/interactables/sigil_forge.gd
extends Area3D

func _ready() -> void:
	visible = MetaProgress.hub_features_unlocked() >= 3
	MetaProgress.hub_feature_unlocked.connect(_on_unlock)
	body_entered.connect(_on_body_entered)

func _on_unlock(_idx: int) -> void:
	visible = MetaProgress.hub_features_unlocked() >= 3

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		print("[Sigil Forge] coming soon — currently unlocked but no content.")
```

(Same shape for trial_chamber.gd with `>= 4` threshold.)

### Step 2: Build minimal scenes

Each .tscn: Area3D + CollisionShape3D + small CylinderMesh, distinct colors:
- Sigil Forge: violet `Color(0.55, 0.3, 0.6, 1)`
- Trial Chamber: amber `Color(0.7, 0.5, 0.3, 1)`

### Step 3: Add to main_hall

Position SigilForge at (5, 0, -5) and TrialChamber at (-5, 0, -5). All four hub interactables form a square around the central pyre.

### Step 4: Verify + commit

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . --import 2>&1 | grep -i error | head -5
git add scripts/interactables/sigil_forge.gd scripts/interactables/trial_chamber.gd scenes/interactables/sigil_forge.tscn scenes/interactables/trial_chamber.tscn scenes/world/main_hall.tscn
git commit -m "feat(stubs): SigilForge + TrialChamber placeholder interactables (3rd + 4th hub features)"
```

---

## Task 8: Final-pyre detection in descent prompt

**Files:**
- Modify: `scripts/ui/descent_prompt.gd`

Phase 5 will fire the actual cutscene + boss. Phase 4 just adds the UI affordance.

### Step 1: Update show_prompt

In `descent_prompt.gd`, modify `show_prompt`. After computing the per-color preview lines, check if this deposit will fill all 6 primary pyres:

```gdscript
func show_prompt() -> void:
	# ... existing per-color preview computation ...
	# Check whether this deposit triggers boss
	var triggers_boss: bool = _will_fill_all_primary_pyres()
	if triggers_boss:
		lines.append("")
		lines.append("⚠ BOSS TRIGGER — this deposit fills the final primary pyre.")
		lines.append("(Phase 4: skill retention + boss cutscene NOT YET IMPLEMENTED — Phase 5.)")
	# ...

func _will_fill_all_primary_pyres() -> bool:
	for color in SoulEconomy.COLORS:
		var minor: int = SoulEconomy.carry_count(color, "minor")
		var elder: int = SoulEconomy.carry_count(color, "elder")
		var fill_delta: int = minor * SoulEconomy.SOUL_VALUES["minor"] + elder * SoulEconomy.SOUL_VALUES["elder"]
		var new_fill: int = min(SoulEconomy.pyre_fill(color) + fill_delta, SoulEconomy.PYRE_CAP)
		if new_fill < SoulEconomy.PYRE_CAP:
			return false
	return true
```

### Step 2: Verify + commit

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
git add scripts/ui/descent_prompt.gd
git commit -m "feat(descent-prompt): boss-trigger marker when deposit fills all 6 primary pyres"
```

---

## Task 9: Acceptance playtest (USER)

After all 8 tasks, the user runs the game. Validation:

- [ ] Game starts. If save exists, pyre fills and meta-progress restored.
- [ ] First time hitting any pyre 50%: SoulAltar appears in main hall (visible glow).
- [ ] Walking onto SoulAltar opens UI; can drain a color's pyre to queue a starting skill.
- [ ] Next run starts with that skill already unlocked (sword tinted, can cast immediately).
- [ ] Hitting any pyre 100%: active skill cap grows by 1 (test by taking enough elders to hit cap).
- [ ] Second pyre 50% milestone: CantripStones appears.
- [ ] CantripStones UI lets you spend banked fill on max HP / sword / dash upgrades.
- [ ] Bonuses persist across runs (test: buy max HP, die, restart, HP starts at 120 instead of 100).
- [ ] In-run elder soul take visibly increases enemy density and HP.
- [ ] Third pyre 50%: SigilForge stub appears.
- [ ] Fourth pyre 50%: TrialChamber stub appears.
- [ ] Filling 6th pyre: descent prompt shows "BOSS TRIGGER" warning text.
- [ ] Save persists across game restarts.

### Step 1: User runs the game

(Manual.)

### Step 2: Tag

```bash
git tag -a v0.4-meta-progression -m "Phase 4: save/load, pyre milestones, hub features (Soul Altar + Cantrip Stones + stubs), in-run elder scaling, active skill cap progression."
```

---

## Phase 4 → Phase 5 handoff

What Phase 4 leaves for Phase 5:
- Final-pyre descent prompt only shows a text marker — no skill retention, no cutscene, no boss spawn.
- The boss flow (cutscene, courtyard, 3-phase fight, victory animation, basement reveal) is the entire scope of Phase 5.
- Sigil Forge and Trial Chamber are stubbed — content fills in post-MVP.
