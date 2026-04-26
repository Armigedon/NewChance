# Phase 6: Ship-Ready Balance Pass — Design

**Date:** 2026-04-26
**Status:** Approved (pending user review of written spec)
**Predecessor:** Phase 5 (boss flow) — shipped, tagged `v0.5-boss-flow`

---

## Goal

Take the game from FAST-TEST playtest mode to a state that can be played end-to-end at intended length and difficulty. Three concrete improvements:

1. Replace scattered FAST-TEST constants with a single debug toggle that flips between test and ship values.
2. Make open-arena spawning feel intentional by weighting spawn rates by player proximity to each corner.
3. Expand necromancer taunt content so death and boss combat carry the disappointed-parent personality consistently.

Phase 6 does **not** include: SFX, music, particle juice, art replacement, animation, ranged-attack enemies, or new skills. Those are deferred to Phase 7+.

---

## Architecture

Five mostly-mechanical changes, all against existing files. No new autoloads except a one-constant `Debug` autoload. No new scenes.

| Subsystem | Files touched | Change type |
|---|---|---|
| Debug toggle | `scripts/core/debug.gd` (new), `project.godot`, 3 existing scripts | Add autoload, refactor 5 constants |
| Number tuning | Same 3 scripts as above | Pure constant changes |
| Proximity spawning | `scripts/world/corner_spawner.gd` | Add distance-based multiplier + burst spawn |
| Taunt content expansion | `scripts/ui/dialogue_banner.gd` | Add new line categories, expand existing pools |
| Taunt trigger wiring | `scripts/entities/boss_dragon.gd`, possibly new helper | Hook phase transitions and idle taunts |

---

## Section 1: Debug Toggle

### New autoload

`scripts/core/debug.gd`:

```gdscript
extends Node

# Single source of truth for FAST-TEST vs SHIP value selection.
# Flip to false before any release build.
const FAST_TEST: bool = true
```

Registered in `project.godot` `[autoload]` block as `Debug="*res://scripts/core/debug.gd"`.

### Refactored sites

Each FAST-TEST site changes from a single hard-coded const to a paired test/ship const + a static var that picks one based on `Debug.FAST_TEST`.

**Five sites:**

| File | Constant | TEST value | SHIP value |
|---|---|---|---|
| `scripts/core/soul_economy.gd` | `PYRE_CAP` | 10 | 100 |
| `scripts/core/soul_economy.gd` | `SOUL_VALUES["elder"]` | 5 | 10 |
| `scripts/ui/soul_altar_ui.gd` | `ALTAR_COST` | 3 | 10 |
| `scripts/ui/cantrip_stones_ui.gd` | `STONE_COST` | 3 | 12 |
| `scripts/entities/boss_dragon.gd` | `MAX_HP` | 150 | 400 |

**Pattern:**

```gdscript
const PYRE_CAP_TEST: int = 10
const PYRE_CAP_SHIP: int = 100
static var PYRE_CAP: int = PYRE_CAP_TEST if Debug.FAST_TEST else PYRE_CAP_SHIP
```

**Note on `SOUL_VALUES["elder"]`:** This sits inside a Dictionary const, which can't be conditionalized inline. Refactor to a static var dict initialized in `_ready` or at parse time:

```gdscript
static var SOUL_VALUES: Dictionary = {
    "minor": 1,
    "elder": 5 if Debug.FAST_TEST else 10,
}
```

### Testing

Existing tests assume FAST-TEST values. Two options:
1. Keep `Debug.FAST_TEST = true` for the test suite (tests stay passing as-is).
2. Update tests to read the constants dynamically rather than hard-coding numerics.

**Decision:** Option 1. Tests don't need to validate the SHIP-value math; they validate the system behavior. Document in test files (existing comments already note FAST-TEST mode).

### Acceptance

- All 5 constants conditionalize correctly.
- Flipping `Debug.FAST_TEST` from `true` to `false` and re-running the game yields ship values everywhere.
- All 102 existing tests still pass with `Debug.FAST_TEST = true`.

---

## Section 2: Number Tuning Targets

These are the SHIP values referenced in Section 1. Reproduced here with rationale so the spec is self-contained.

| Constant | Old TEST | Original Design | Phase 6 SHIP | Rationale |
|---|---|---|---|---|
| `PYRE_CAP` | 10 | 250 | **100** | Medium pacing target: 6 pyres × 100 ≈ 600 souls to boss-ready, ~1-2hr to first boss attempt |
| Minor soul value | 1 | 1 | **1** | Unchanged baseline |
| Elder soul value | 5 | 10 | **10** | One elder = 10% of a pyre — meaningful but not gamebreaking |
| `ALTAR_COST` | 3 | 25 | **10** | Scaled proportionally to PYRE_CAP (100/250 ratio); ~10% of pyre |
| `STONE_COST` | 3 | 30 | **12** | Scaled proportionally; ~12% of pyre |
| Boss `MAX_HP` | 150 | 600 | **400** | Dropped from 600 — medium-paced player arrives less optimized; want fight to last 2-4 min not 5-10 |

**Unchanged values (deliberate):**
- Welp HP / damage / spawn rate — descent length per-run unchanged, only number of descents changes.
- Player HP / damage — same reasoning.
- Escalation curves (`HEAT_BUILD_PER_SEC`, `HEAT_DECAY_PER_SEC`, `roll_tier` thresholds) — descent shape unchanged.
- MetaProgress thresholds (active skill cap, modifier cap progression) — gated by total elder souls earned. With elder = 10 and PYRE_CAP = 100, existing thresholds remain reachable. **Validation:** plan task includes a math check; if numbers fall out of whack, retune as a follow-up subtask.

---

## Section 3: Proximity-Weighted Corner Spawning

### Problem

Six corner spawners run at independent rates determined by `Escalation.spawn_rate_factor(heat)`. Heat builds only when the player physically stands in a corner zone. When the player is fighting in the middle of the arena, all 6 corners decay to base heat and spawn at equal `1.0×` rate. Result: welps converge from all six directions every cycle. Player feedback: "felt ungenuine."

### Solution

Add a per-spawner **proximity factor** based on Euclidean XZ distance from the spawner's own position to the player. Multiply into the existing `effective_interval` calculation.

**Tiers** (distance in meters, on the XZ plane only):

| Distance | Proximity factor | Tier-roll bias | Burst-spawn chance |
|---|---|---|---|
| Close (≤ 8m) | **2.5×** spawn rate | unchanged | 25% chance to spawn 2 welps in one tick |
| Medium (8–16m) | **1.0×** | unchanged | 0% |
| Far (> 16m) | **0.3×** | force `tier = "welp"` | 0% |

**Stacking with existing heat:** The proximity factor multiplies the existing `spawn_rate_factor` from `Escalation`. So a corner that is both player-occupied (high heat) AND close (≤8m) gets the full stacked aggression: `(1 + 2*heat/cap) * 2.5 ≈ 7.5×` at max. This is intentional — being IN a corner should feel maximally hot.

### Implementation sketch

In `scripts/world/corner_spawner.gd._process`:

```gdscript
func _process(delta: float) -> void:
    var heat: float = Escalation.corner_heat(color)
    var proximity_mult: float = _proximity_multiplier()
    var effective_interval: float = base_spawn_interval / (Escalation.spawn_rate_factor(heat) * proximity_mult)
    _timer += delta
    if _timer >= effective_interval and _alive_count < max_alive:
        _timer = 0.0
        _spawn()
        if _should_burst():
            _spawn()  # second welp same tick

func _proximity_multiplier() -> float:
    var p: Vector3 = _get_player_pos()
    if p == Vector3.INF:
        return 1.0
    var d: float = Vector2(p.x - global_position.x, p.z - global_position.z).length()
    if d <= 8.0:
        return 2.5
    if d <= 16.0:
        return 1.0
    return 0.3

func _should_burst() -> bool:
    var p: Vector3 = _get_player_pos()
    if p == Vector3.INF:
        return false
    var d: float = Vector2(p.x - global_position.x, p.z - global_position.z).length()
    return d <= 8.0 and randf() < 0.25
```

**Far-corner tier biasing:** in `_spawn`, if the proximity tier is "far," override the `Escalation.roll_tier(heat)` result back to `"welp"`. Distant corners shouldn't be lobbing dragons.

### Future work (deferred)

User noted: closer to launch (after art/graphics pass), expand the open arena and move spawners farther apart so the proximity tiers feel more spatially significant. **Not part of Phase 6** — current arena geometry stays.

### Acceptance

- Player standing dead-center: all 6 corners spawn at `1.0×` (medium distance from center if arena radius ≈ 12m, all corners fall in the 8-16m band).
- Player walking toward one corner: that corner's spawn rate ramps up (close + heat); other corners decay (far).
- Burst spawns visibly happen at close range (player notices "two at once" pattern).
- No regression in welps-per-minute averaged across a full descent at typical play pattern.

---

## Section 4: Taunt Content Expansion

### Existing infrastructure

`scripts/ui/dialogue_banner.gd` already has:
- A `LINES: Dictionary` mapping category → `Array[String]` of lines.
- `show_line(category)` which random-picks from the pool and displays for `line_duration` seconds.
- Existing categories: `death_normal` (5 lines), `death_boss` (4), `flame_drain` (3), `victory` (1).

### Categories to add / expand

| Category | Current count | Phase 6 target | Trigger |
|---|---|---|---|
| `death_normal` | 5 | **12** | Already wired (death in normal run) |
| `death_boss` | 4 | **8** | Already wired (death in boss fight) |
| `phase_2_taunt` | — | **5** (new) | Boss `phase_changed` signal, new phase = 2 |
| `phase_3_taunt` | — | **5** (new) | Boss `phase_changed` signal, new phase = 3 |
| `boss_idle` | — | **15** (new) | Idle timer in boss fight, every 18s of fight time |

**Total new lines to write:** 11 expansion (7 to `death_normal`, 4 to `death_boss`) + 25 in new categories (5 + 5 + 15) = **36 lines**.

### Trigger wiring

**Phase transition taunts:** `scripts/entities/boss_dragon.gd._check_phase_transition` already emits `phase_changed`. Connect a listener (in `boss_dragon.gd._ready` or a new lightweight controller):

```gdscript
phase_changed.connect(func(p: int):
    var banner: CanvasLayer = get_tree().root.find_child("DialogueBanner", true, false)
    if banner == null:
        return
    if p == 2:
        banner.show_line("phase_2_taunt")
    elif p == 3:
        banner.show_line("phase_3_taunt")
)
```

**Idle boss taunts:** Add two timer fields to `boss_dragon.gd`: `_idle_taunt_timer` (counts up, fires at 18s, then resets) and `_taunt_cooldown` (set to 5s whenever any taunt fires; idle taunts skip if it's > 0). Increment both in `_physics_process` while alive. This guarantees no idle taunt steps on a phase taunt within 5 seconds of the transition.

### Tone reference

Existing lines already nail the tone — disappointed creator, condescending, brief:

> "Get up, fool. The dragons aren't going to slay themselves."
> "Did you forget what I made you for?"
> "Crawl back to the pyres. The dragons grow restless."

New lines should match: short (one sentence), patronizing, treating the player as a defective creation. The implementation plan will include the actual line text — user can edit/replace any that don't sound right.

### Acceptance

- Dying in a normal run shows one of 12 death taunts (current 5 + 7 new).
- Dying in the boss fight shows one of 8 death taunts (current 4 + 4 new).
- Reaching Phase 2 of the boss fight triggers a `phase_2_taunt` banner.
- Reaching Phase 3 triggers a `phase_3_taunt`.
- During Phase 1+ of the boss fight, ~every 18 seconds a `boss_idle` line appears (without overlap with phase taunts).

---

## Section 5: Acceptance & Testing Plan

### Per-subtask testing

Same pattern as Phases 1-5: subagent implements + unit tests + commits, user playtest after subagent batches complete.

### Phase 6 overall acceptance

- [ ] All 102 existing tests still pass (`Debug.FAST_TEST = true` baseline).
- [ ] New tests for `corner_spawner` proximity multiplier (table-driven: feed dist, expect multiplier).
- [ ] New tests for boss-dragon idle taunt timer + phase transition signal wiring.
- [ ] User playtest: a single full descent under SHIP values feels like the medium-pacing target (1-2hr to boss across multiple descents — not validated end-to-end, but per-descent feel).
- [ ] User playtest: open-arena spawning visibly weighted by proximity (player notices fewer far-corner welps; "raiding party" near corners).
- [ ] User playtest: at least one death taunt from each new pool seen; phase transitions trigger taunts; idle taunts appear during boss fight.

### Out of scope

Anything not listed in Sections 1-4. Specifically:
- No SFX, music, animation, particle, art changes.
- No new skills, modifiers, enemy variants.
- No ranged-attack welp variant (user confirmed all melee is correct).
- No arena geometry expansion (deferred to art pass).
- No long-form ship-value playtest (would take 2+ hours; user will validate organically post-merge).

---

## Branch & Tag

- Branch: `phase-6-ship-ready`
- Tag on merge: `v0.6-ship-ready`
