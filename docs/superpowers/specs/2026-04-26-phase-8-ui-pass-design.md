# Phase 8: UI Pass — Design

**Date:** 2026-04-26
**Status:** Approved (pending user review of written spec)
**Predecessor:** Phase 7 (game-feel) — shipped, tagged `v0.7-game-feel`

---

## Goal

Replace the placeholder UI with a polished, on-tone player experience. Five components:

1. **Start screen** — entry point with New Game / Continue / How to Play / Quit
2. **In-run HUD redesign** — corner-tucked HP + wispy soul carry pool with elder distinction + active skill indicator
3. **Pause menu** — ESC overlay with Resume / How to Play / Restart Run / Quit to Menu
4. **Run-end summary** — death-only stats panel before returning to hub
5. **How-to-play overlay** — single-page reference reachable from start screen + pause menu

Phase 8 does **not** include: audio/music (Phase 9), settings menu (volume/keybinds), pyre status panel, tooltips, run-end summary on voluntary descent or boss kill (those have other flows), first-run forced popup, controller support.

---

## Architecture

Five new scenes, three modified scripts, one new autoload. All UI is `CanvasLayer`-based and pause-aware via `process_mode = PROCESS_MODE_WHEN_PAUSED` where appropriate. Existing autoloads (GameState, BossFlow, SoulEconomy, MetaProgress) provide all the data the UI needs.

| File | Status | Responsibility |
|---|---|---|
| `scenes/world/start_screen.tscn` | **Create** | Initial scene on game launch — replaces direct main_hall load |
| `scripts/world/start_screen.gd` | **Create** | Handles button signals; loads save / clears save / transitions |
| `scenes/ui/pause_menu.tscn` | **Create** | Pause overlay with 4 buttons + confirm modal for Restart Run |
| `scripts/ui/pause_menu.gd` | **Create** | Toggle on `ui_cancel`; manages `get_tree().paused` |
| `scenes/ui/run_end_summary.tscn` | **Create** | Death-only summary panel |
| `scripts/ui/run_end_summary.gd` | **Create** | Reads run stats from RunStats autoload; shows panel |
| `scenes/ui/how_to_play.tscn` | **Create** | Reference overlay |
| `scripts/ui/how_to_play.gd` | **Create** | Show / hide; ESC dismisses |
| `scenes/ui/soul_wisp.tscn` | **Create** | Reusable wispy-soul widget for HUD + run-end |
| `scripts/ui/soul_wisp.gd` | **Create** | Animates scale.y + modulate via Tween; loops |
| `scripts/core/run_stats.gd` | **Create** | Autoload — tracks elapsed time, kills, last damage source per run |
| `project.godot` | Modify | Register `RunStats` autoload + change `run/main_scene` to start_screen |
| `scenes/ui/hud.tscn` | Modify | Add wispy soul row + elder cluster + active skill indicator |
| `scripts/ui/hud.gd` | Modify | Wire soul carry counts (all 6 colors + elder); active skill from SkillSystem |
| `scripts/entities/player.gd` | Modify | Track last damage source for "killed by" line; report kills/death to RunStats |
| `scripts/entities/welp.gd` | Modify | Notify RunStats on death (counts as kill); pass self to player.take_damage as source |
| `scripts/world/death_handler.gd` | Modify | Show run_end_summary instead of direct scene transition |
| `scripts/world/main_hall_upstairs_trigger.gd` | Modify | Reset RunStats on entry to upstairs (run begins) |

---

## Section 1: Start Screen

### Layout (Option C — split with hero)

Left half: title "New Chance" with subtitle "a roguelike of disappointment" and version string.
Right half: vertical button stack. The "NEW GAME" button is a prominent gold-accented hero CTA with subtle box-shadow glow; subsidiary buttons (Continue / How to Play / Quit) are smaller and quieter.

### Scene structure

`scenes/world/start_screen.tscn`:
- `Node3D` root (so the dark camera-environment carries through; or `Control` root with a black background — final choice in implementation)
- `CanvasLayer` for UI
  - `Center` MarginContainer
    - `HBoxContainer`
      - `Title` VBoxContainer (left): RichTextLabel for stylized title, Label for subtitle, Label for version
      - `Buttons` VBoxContainer (right): NewGame, Continue, HowToPlay, Quit

### Behavior

- **NEW GAME**: if `user://save.tres` exists, show confirmation modal "Overwrite save? Yes / No". On confirm: delete save file, reset all autoload state via `MetaProgress._init_defaults()` + `SoulEconomy.reset_meta()` + `BossFlow.reset()` + `BossFlow.clear_retained_skills()`, transition to main_hall.
- **CONTINUE**: disabled (greyed out) if no save file exists. On click: load save (existing GameState `_load_save_state` already runs on autoload `_ready` — Continue just transitions to main_hall and the load is automatic). For a clean re-entry, reset run-scoped state but preserve meta-state.
- **HOW TO PLAY**: instantiate how_to_play overlay (see Section 5).
- **QUIT**: `get_tree().quit()`.

### Implementation hooks

- `project.godot` `application/run/main_scene` changes from `scenes/world/main_hall.tscn` to `scenes/world/start_screen.tscn`.
- This means the current behavior of "open the game → drop into main hall" becomes "open the game → start screen → click New Game / Continue → main hall." A side effect: tests that depend on the autoload chain still work because autoloads run regardless of starting scene.

### Acceptance

- Start screen appears on game launch.
- Continue is disabled when no save file exists.
- New Game with existing save shows confirmation modal.
- New Game without save bypasses modal.
- Quit exits the game cleanly.

---

## Section 2: In-Run HUD Redesign

### Layout (Option A — corner-tucked, with wispy souls)

- **Top-left:** "HEALTH" label + HP bar (160px × 14px, dark background, red gradient fill) + numeric "80/100" on right.
- **Bottom-left:** "CARRY" label + 6 soul-wisp chips in row + vertical divider + elder cluster (1 chip, taller, brighter, with star marker).
- **Bottom-right:** "SKILL" label + 3 slots (32×32 each) representing skill positions 1/2/3, with the active slot enlarged to 36×36 and given the active-color border + glow.

### Wispy soul chip widget

`scenes/ui/soul_wisp.tscn`:
- `MarginContainer` with a TextureRect (or CanvasItem with custom_draw for a flame shape)
- Below: Label for the count

`scripts/ui/soul_wisp.gd`:
- `@export var color: String` (red/blue/green/purple/gold/white)
- `@export var is_elder: bool = false`
- `@export var stagger_seconds: float = 0.0` (per-chip animation phase offset)
- `var count: int = 0` with setter that updates the label and dim/animate state

Animation: in `_ready`, create a looping Tween:
- If `is_elder`: 2.0s loop, scale.y 0.92 → 1.12 → 0.92 with `set_ease(Tween.EASE_IN_OUT)`, plus modulate.a 0.9 → 1.0 → 0.9.
- Else: 1.6s loop, scale.y 0.95 → 1.08 → 0.95, modulate.a 0.85 → 1.0 → 0.85.
- If `count == 0`: skip the tween, set modulate.a = 0.4 (dimmed). Re-enable when count > 0.
- `stagger_seconds` is applied as an initial delay so chips don't pulse in unison.

The flame shape itself: implementation choice between (a) a small flame texture asset, (b) a Polygon2D with the wispy SVG path translated to Godot points, (c) a custom_draw on a Control node. The plan will pick one in implementation; the spec is silent on the rendering approach.

### Modified hud.gd

Existing `_hp_label` and `_souls_label` remain as fallbacks until the new widget is wired. The HUD script gains:
- `@onready var _wisp_red: SoulWisp = $...`, etc., for each color.
- `@onready var _wisp_elder: SoulWisp = $...` (the elder cluster — receives total elder count across all colors, OR per-color elder; spec defaults to per-color elder so the chip color matches what the player sees).
- Wait — actually, the existing data model is: `SoulEconomy._carry[color]["minor"|"elder"]`. So elder counts ARE per-color. The HUD has 6 elder chips? That's a lot.

**Decision:** the HUD shows 6 minor chips (one per color), and ONE aggregate elder chip showing total elder count across all colors with no color tint (gold star + white-gold flame). Per-color elder is preserved internally and shown on hover (Phase 9+) or in the soul-altar UI.

### Active skill indicator

The HUD subscribes to `SkillSystem.active_skill_changed(index)`. Three slot widgets (Slot 1 / 2 / 3) each show:
- Slot number ("1", "2", "3") if empty.
- Skill name + color-tinted border if filled (e.g., "FIRE" in red, "ICE" in blue, etc.).
- The active slot is enlarged and gets a glow box-shadow (shader or modulate-based).

### Acceptance

- HUD shows HP bar in top-left with current/max numeric.
- HUD shows 6 soul-wisp chips in bottom-left, animated (pulsing, staggered).
- Zero-count chips are dimmed and don't animate.
- Elder chip in bottom-left (after divider) shows aggregate elder count across all colors, with star marker and brighter glow.
- HUD shows 3 skill slots in bottom-right; active slot is enlarged and color-tinted.

---

## Section 3: Pause Menu

### Layout

- ESC during gameplay opens overlay.
- Translucent backdrop (`Color(0,0,0,0.65)`) behind a centered panel.
- Panel: 240×260 px, dark background, gold border. Title "— PAUSED —" at top.
- 4 buttons stacked vertically: Resume (gold accent, primary), How to Play, Restart Run (red-tinted border for destructive), Quit to Menu.

### Behavior

- ESC opens; ESC inside pause closes (resumes).
- Sets `get_tree().paused = true` on open, `false` on close.
- Pause-aware nodes use `PROCESS_MODE_WHEN_PAUSED` (existing pattern in descent_prompt etc).
- **Resume:** close overlay, unpause.
- **How to Play:** show how_to_play overlay on top; Back returns to pause menu (still paused).
- **Restart Run:** confirmation modal "Discard run? Carry souls will be lost. (Yes / No)". On Yes: clear `SoulEconomy._carry`, transition to main_hall.
- **Quit to Menu:** auto-save (write meta + pyres via SaveSystem), transition to start_screen scene.

### Implementation hook

`scripts/ui/pause_menu.gd` is registered as a child of every scene that should support pausing — main_hall, upstairs, courtyard. Easiest: instantiate it as a child of each of those .tscn files, OR make it an autoload (CanvasLayer) so it's globally available. The spec defaults to **autoload** for simplicity (one less per-scene wiring point).

If autoload: `pause_menu.tscn` becomes the autoloaded scene. Its CanvasLayer renders on top of everything; visibility toggles on ESC. The autoload listens to `Input.is_action_just_pressed("ui_cancel")` in `_input()`.

Caveat: the descent_prompt + cantrip_stones_ui already consume `ui_cancel`. The pause menu must check that those modals aren't already open before consuming ESC. Easiest: walk the scene tree for any visible modal CanvasLayer in `scenes/ui/`, OR have each modal set a flag on a shared `UiState` autoload. The spec defers this to the implementation plan; either approach works.

### Acceptance

- ESC during gameplay opens pause menu.
- ESC inside pause menu resumes.
- Resume button resumes.
- How to Play button opens how-to-play; Back returns to pause menu.
- Restart Run shows confirmation; Yes discards carry + returns to main hall.
- Quit to Menu auto-saves and returns to start screen.
- Pause menu does NOT open when descent_prompt or other modals are visible.

---

## Section 4: Run-End Summary

### Trigger

Fires only on **death** during a run (not voluntary extract, not boss victory). Replaces the current behavior in `death_handler.gd._on_player_died` of immediately calling `GameState.end_run(DIED)` → scene transition.

### Layout

Centered panel (~340×360 px), dark background with subtle red border, red glow on title.
- Title: "— You Died —" (red glow). Variant for boss death: "— Defeated —".
- Necromancer line: random pick from `death_normal` (or `death_boss` for boss death) DialogueBanner pool.
- Stats grid (label / value pairs):
  - **Survived:** elapsed run time formatted as "M:SS"
  - **Enemies slain:** integer count of welps/dragons/elders killed during this run
  - **Killed by:** name of the enemy that dealt the lethal hit (e.g., "red welp", "elder dragon", "the dragon"). If implementation cost is high, drop this row.
- Divider.
- "SOULS LOST" panel: 6 minor wisp icons (dimmed, NO animation) + elder cluster, showing the carry counts at moment of death. If no carry, omit panel entirely.
- Buttons: Continue (primary, gold) → main hall. Quit to Menu → start screen.

### RunStats autoload

`scripts/core/run_stats.gd` (new autoload):

```gdscript
extends Node

var run_start_time_ms: int = 0
var enemies_slain: int = 0
var last_damage_source_name: String = ""

func reset_run() -> void:
    run_start_time_ms = Time.get_ticks_msec()
    enemies_slain = 0
    last_damage_source_name = ""

func record_kill() -> void:
    enemies_slain += 1

func record_damage_from(source_name: String) -> void:
    last_damage_source_name = source_name

func elapsed_seconds() -> float:
    return (Time.get_ticks_msec() - run_start_time_ms) / 1000.0
```

Wired to:
- `main_hall_upstairs_trigger.gd._on_body_entered`: calls `RunStats.reset_run()` when player crosses the upstairs trigger (run begins).
- `welp.take_damage` death path: calls `RunStats.record_kill()` after `_drop_souls()` and before `queue_free`.
- `boss_dragon.take_damage` death path: calls `RunStats.record_kill()` (counts as 1).
- `welp._attack_player` and `boss_dragon._physics_process` contact damage: calls `RunStats.record_damage_from(self.name_for_run_end())` before invoking `_player.take_damage(...)`. Each enemy script exposes a `name_for_run_end()` returning a human label like "%s welp" % color.tier or just "the dragon" for boss.

### Implementation hook

`death_handler._on_player_died`:
1. Existing: detect courtyard vs other → set BossFlow.LOST or stash death_normal/death_boss line.
2. NEW: instantiate run_end_summary scene, populate stats, show overlay.
3. Continue button → existing `GameState.end_run(DIED)` flow → main hall.

### Acceptance

- Player death triggers the summary overlay (instead of immediate scene transition).
- Stats show: time survived (formatted M:SS), kills count, killed-by enemy name.
- Souls-lost panel mirrors HUD layout (dimmed, not animated).
- Continue button returns to main hall.
- Boss-fight death uses "Defeated" variant title and `death_boss` taunt pool.

---

## Section 5: How-to-Play Overlay

### Trigger

Reachable from:
- Start screen "HOW TO PLAY" button.
- Pause menu "HOW TO PLAY" button.

Closeable with:
- ESC → returns to caller (start screen or pause menu).
- "BACK" button → same.

### Layout

Centered panel, ~640×480 px. Dark background, gold border. Header "— How to Play —" with a sub-header italic line like "Pay attention this time." Two-column grid below, 4 sections:

1. **CONTROLS** (with a flavor quote): WASD move, SPACE dash, CLICK / hold cast, 1/2/3 switch skill, ESC pause.
2. **THE LOOP**: ordered list (descend → slay → extract → deposit → repeat → light all six).
3. **SOULS**: shows minor + elder wisp icons inline + explanatory text ("Six colors. Each color fills one pyre. Elder souls count for ten of their own color and matter at the altar.").
4. **THE HUB**: explains Soul Altar, Cantrip Stones, Pyres.

Each section has a 1-line italic necromancer quote at the bottom for tone.

Boss fight is intentionally NOT documented (preserves surprise of the cutscene reveal).

### Implementation hook

`scenes/ui/how_to_play.tscn`:
- CanvasLayer
  - ColorRect backdrop (semi-transparent)
  - Center container
    - PanelContainer with content (title, sections, quote)
    - "BACK" button at bottom-right

`scripts/ui/how_to_play.gd`:
- `func show_overlay()`: visible = true, get_tree().paused = true (only if called from gameplay; start_screen is already not in gameplay).
- `func hide_overlay()`: emits `closed` signal; caller handles state cleanup.

### Acceptance

- Reachable from start screen and pause menu.
- ESC dismisses; Back button dismisses.
- All 4 sections render with their quotes.
- Soul section shows live minor + elder wisp icons (matching HUD style).

---

## Section 6: Testing Plan

### Unit-testable surface

- `RunStats.reset_run()` zeros fields and captures start time.
- `RunStats.record_kill()` increments `enemies_slain`.
- `RunStats.record_damage_from(name)` sets `last_damage_source_name`.
- `RunStats.elapsed_seconds()` returns time since reset.
- `SoulWisp.set_count(n)` updates label and dim state.

### Integration-only (manual playtest)

- Start screen → New Game / Continue / How to Play / Quit each work.
- HUD wisp animation visible and staggered.
- Pause menu opens/closes on ESC.
- Run-end summary appears on death with correct stats.

Target: ~8 new unit tests.

---

## Out of Scope

- Audio (Phase 9)
- Settings menu (volume / window mode / keybinds)
- Pyre status panel in main hall
- Tooltips on hover
- First-run forced popup
- Run-end summary on voluntary descent or boss kill
- Controller / gamepad support
- Localization
- Background art on start screen (will be added when art pass lands)

---

## Branch & Tag

- Branch: `phase-8-ui-pass`
- Tag on merge: `v0.8-ui-pass`
