# Phase 8 UI Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder UI with a polished player experience: start screen, redesigned in-run HUD with wispy animated soul widgets + elder distinction, pause menu, death summary, and how-to-play reference.

**Architecture:** Five new UI scenes + scripts, one new autoload (RunStats), one new reusable widget (SoulWisp). All UI rendered through CanvasLayer; pause-aware via `process_mode = PROCESS_MODE_WHEN_PAUSED`. SoulWisp widget uses procedural `_draw` flame shape with sine-pulse animation (no asset dependency). `project.godot` `main_scene` switches from `main_hall.tscn` to `start_screen.tscn`.

**Tech Stack:** Godot 4.6 (.NET, Forward+), GDScript with type hints, GdUnit4 testing framework. Existing autoloads: Debug, GameState, SoulEconomy, Escalation, SaveSystem, MetaProgress, BossFlow, ScreenShake, HitStop. Adding: RunStats, PauseMenu (autoload scene).

**Spec:** [docs/superpowers/specs/2026-04-26-phase-8-ui-pass-design.md](../specs/2026-04-26-phase-8-ui-pass-design.md)

**Branch:** `phase-8-ui-pass` (already created)

**Godot CLI:** `"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"` — pass `--ignoreHeadlessMode` to GdUnit4 args.

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `scripts/core/run_stats.gd` | **Create** | Autoload — tracks run start time, kills, last damage source |
| `scripts/ui/soul_wisp.gd` | **Create** | Custom-draw flame Control with pulse animation + count label |
| `scenes/ui/soul_wisp.tscn` | **Create** | SoulWisp scene with embedded Label child |
| `scenes/ui/hud.tscn` | Modify | Add 6 minor wisp chips + elder cluster + active skill row |
| `scripts/ui/hud.gd` | Modify | Wire all 6 colors of carry; subscribe to SkillSystem.active_skill_changed |
| `scripts/entities/welp.gd` | Modify | Call RunStats.record_kill on death; expose `display_name()` for run-end |
| `scripts/entities/boss_dragon.gd` | Modify | Same: record_kill on death; pass self to player.take_damage |
| `scripts/entities/player.gd` | Modify | Accept optional damage source parameter; report to RunStats |
| `scripts/world/main_hall_upstairs_trigger.gd` | Modify | Call `RunStats.reset_run()` on entry |
| `scenes/ui/how_to_play.tscn` | **Create** | Single-page reference overlay |
| `scripts/ui/how_to_play.gd` | **Create** | show()/hide()/closed signal; ESC dismiss |
| `scenes/world/start_screen.tscn` | **Create** | Initial scene — split layout with hero New Game CTA |
| `scripts/world/start_screen.gd` | **Create** | Button signals; new game / continue / quit |
| `scenes/ui/pause_menu.tscn` | **Create** | ESC overlay autoload |
| `scripts/ui/pause_menu.gd` | **Create** | ui_cancel toggle; manages get_tree().paused |
| `scenes/ui/run_end_summary.tscn` | **Create** | Death stats panel |
| `scripts/ui/run_end_summary.gd` | **Create** | Read from RunStats; show panel; Continue → main hall |
| `scripts/world/death_handler.gd` | Modify | Show run_end_summary instead of immediate transition |
| `project.godot` | Modify | Register RunStats + PauseMenu autoloads; main_scene → start_screen |
| `test/test_run_stats.gd` | **Create** | RunStats unit tests |
| `test/test_soul_wisp.gd` | **Create** | SoulWisp widget unit tests |

---

## Task 1: RunStats Autoload

Track run-scoped metrics. Used by run-end summary and (future) achievements.

**Files:**
- Create: `scripts/core/run_stats.gd`
- Modify: `project.godot` (register autoload — only this entry; main_scene changes in Task 9)
- Create: `test/test_run_stats.gd`

- [ ] **Step 1: Write failing tests**

Create `test/test_run_stats.gd`:

```gdscript
extends GdUnitTestSuite

const RunStatsScript = preload("res://scripts/core/run_stats.gd")

var rs: Node

func before_test() -> void:
	rs = auto_free(RunStatsScript.new())
	add_child(rs)

func test_starts_with_zero_kills() -> void:
	assert_that(rs.enemies_slain).is_equal(0)

func test_starts_with_empty_damage_source() -> void:
	assert_that(rs.last_damage_source_name).is_equal("")

func test_record_kill_increments() -> void:
	rs.record_kill()
	rs.record_kill()
	assert_that(rs.enemies_slain).is_equal(2)

func test_record_damage_from_sets_name() -> void:
	rs.record_damage_from("red welp")
	assert_that(rs.last_damage_source_name).is_equal("red welp")

func test_reset_zeroes_state() -> void:
	rs.record_kill()
	rs.record_kill()
	rs.record_damage_from("blue dragon")
	rs.reset_run()
	assert_that(rs.enemies_slain).is_equal(0)
	assert_that(rs.last_damage_source_name).is_equal("")

func test_reset_captures_start_time() -> void:
	var before: int = Time.get_ticks_msec()
	rs.reset_run()
	assert_that(rs.run_start_time_ms).is_greater_equal(before)
	assert_that(rs.run_start_time_ms).is_less(before + 100)

func test_elapsed_seconds_grows_after_reset() -> void:
	rs.reset_run()
	# Small busy-wait so elapsed is measurably nonzero.
	var deadline: int = Time.get_ticks_msec() + 20
	while Time.get_ticks_msec() < deadline:
		pass
	assert_that(rs.elapsed_seconds()).is_greater(0.01)
```

- [ ] **Step 2: Run tests, confirm they fail**

```bash
cd /c/Users/wyenk/OneDrive/Documents/godot/new-chance
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_run_stats.gd --ignoreHeadlessMode
```

Expected: 7 failures (script not yet defined).

- [ ] **Step 3: Implement RunStats**

Create `scripts/core/run_stats.gd`:

```gdscript
extends Node

# Run-scoped metrics. Reset when player crosses the upstairs trigger
# (a new run begins); read by run_end_summary on death.

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

- [ ] **Step 4: Register as autoload (only — main_scene change is in Task 9)**

Edit `project.godot`. Find the `[autoload]` block. Add `RunStats` AFTER the existing entries:

```ini
[autoload]

Debug="*res://scripts/core/debug.gd"
GameState="*res://scripts/core/game_state.gd"
SoulEconomy="*res://scripts/core/soul_economy.gd"
Escalation="*res://scripts/world/escalation.gd"
SaveSystem="*res://scripts/core/save_system.gd"
MetaProgress="*res://scripts/core/meta_progress.gd"
BossFlow="*res://scripts/core/boss_flow.gd"
ScreenShake="*res://scripts/world/screen_shake.gd"
HitStop="*res://scripts/world/hit_stop.gd"
RunStats="*res://scripts/core/run_stats.gd"
```

- [ ] **Step 5: Run full suite, confirm green**

```bash
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/ --ignoreHeadlessMode
```

Expected: 142/142 tests pass (135 prior + 7 new).

- [ ] **Step 6: Commit**

```bash
git add scripts/core/run_stats.gd project.godot test/test_run_stats.gd
git commit -m "feat(ui): add RunStats autoload for run-scoped metrics

Tracks run_start_time_ms, enemies_slain, last_damage_source_name.
reset_run() at run start; record_kill on enemy death; record_damage_from
on player damage. Read by run_end_summary in a later task."
```

---

## Task 2: SoulWisp Widget

Reusable wispy-flame chip with pulse animation. Used by HUD (Task 3) and run-end summary (Task 8).

**Files:**
- Create: `scripts/ui/soul_wisp.gd`
- Create: `scenes/ui/soul_wisp.tscn`
- Create: `test/test_soul_wisp.gd`

- [ ] **Step 1: Write failing tests for SoulWisp**

Create `test/test_soul_wisp.gd`:

```gdscript
extends GdUnitTestSuite

const SoulWispScript = preload("res://scripts/ui/soul_wisp.gd")

var wisp: Control

func before_test() -> void:
	wisp = auto_free(Control.new())
	wisp.set_script(SoulWispScript)
	add_child(wisp)

func test_default_count_is_zero() -> void:
	assert_that(wisp.count).is_equal(0)

func test_set_count_updates_value() -> void:
	wisp.set_count(5)
	assert_that(wisp.count).is_equal(5)

func test_set_count_zero_marks_dimmed() -> void:
	wisp.set_count(3)
	wisp.set_count(0)
	assert_that(wisp.is_dimmed()).is_true()

func test_set_count_positive_undims() -> void:
	wisp.set_count(0)
	wisp.set_count(2)
	assert_that(wisp.is_dimmed()).is_false()

func test_color_property_persists() -> void:
	wisp.color = Color(0.8, 0.2, 0.1, 1)
	assert_that(wisp.color).is_equal(Color(0.8, 0.2, 0.1, 1))

func test_is_elder_property_persists() -> void:
	wisp.is_elder = true
	assert_that(wisp.is_elder).is_true()
```

- [ ] **Step 2: Run tests, confirm fail**

```bash
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_soul_wisp.gd --ignoreHeadlessMode
```

Expected: 6 failures.

- [ ] **Step 3: Implement SoulWisp script**

Create `scripts/ui/soul_wisp.gd`:

```gdscript
extends Control

# Reusable wispy-soul widget. Custom-draws a flame polygon and pulses it
# with a sine wave on _process. Count label is added below in the .tscn.

@export var color: Color = Color(0.8, 0.8, 0.78, 1)
@export var is_elder: bool = false
@export var stagger_seconds: float = 0.0

const FLAME_POINTS: PackedVector2Array = PackedVector2Array([
	Vector2(11, 2),
	Vector2(5, 8),
	Vector2(8, 16),
	Vector2(3, 20),
	Vector2(7, 26),
	Vector2(11, 28),
	Vector2(15, 26),
	Vector2(19, 20),
	Vector2(14, 16),
	Vector2(17, 8),
])
const FLAME_PIVOT_Y: float = 28.0
const MINOR_PERIOD: float = 1.6
const ELDER_PERIOD: float = 2.0

var count: int = 0
var _t: float = 0.0
var _label: Label = null

func _ready() -> void:
	_t = stagger_seconds
	custom_minimum_size = Vector2(28, 36)
	_label = get_node_or_null("Count") as Label
	_refresh_label()

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var period: float = ELDER_PERIOD if is_elder else MINOR_PERIOD
	var pulse: float = sin(_t * TAU / period) * 0.5 + 0.5  # 0..1
	var scale_y: float
	var alpha: float
	if is_dimmed():
		scale_y = 1.0
		alpha = 0.4
	else:
		var min_scale: float = 0.92 if is_elder else 0.95
		var max_scale: float = 1.12 if is_elder else 1.08
		var min_alpha: float = 0.9 if is_elder else 0.85
		var max_alpha: float = 1.0
		scale_y = lerp(min_scale, max_scale, pulse)
		alpha = lerp(min_alpha, max_alpha, pulse)
	var pts: PackedVector2Array = PackedVector2Array()
	for p in FLAME_POINTS:
		pts.append(Vector2(p.x, FLAME_PIVOT_Y - (FLAME_PIVOT_Y - p.y) * scale_y))
	var c: Color = color
	c.a *= alpha
	draw_colored_polygon(pts, c)

func set_count(n: int) -> void:
	count = max(0, n)
	_refresh_label()

func is_dimmed() -> bool:
	return count == 0

func _refresh_label() -> void:
	if _label != null:
		_label.text = str(count)
```

- [ ] **Step 4: Create the SoulWisp scene**

Create `scenes/ui/soul_wisp.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/soul_wisp.gd" id="1_wisp"]

[node name="SoulWisp" type="Control"]
custom_minimum_size = Vector2(28, 36)
script = ExtResource("1_wisp")

[node name="Count" type="Label" parent="."]
layout_mode = 0
offset_left = 0.0
offset_top = 30.0
offset_right = 28.0
offset_bottom = 44.0
text = "0"
horizontal_alignment = 1
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0.91, 0.85, 0.69, 1)
```

- [ ] **Step 5: Run tests, confirm pass**

```bash
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_soul_wisp.gd --ignoreHeadlessMode
```

Expected: 6/6 pass.

- [ ] **Step 6: Run full suite, no regressions**

```bash
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/ --ignoreHeadlessMode
```

Expected: 148/148 (142 + 6).

- [ ] **Step 7: Commit**

```bash
git add scripts/ui/soul_wisp.gd scenes/ui/soul_wisp.tscn test/test_soul_wisp.gd
git commit -m "feat(ui): add SoulWisp widget — wispy soul chip with pulse animation

Custom-drawn flame polygon (10 points), sine-pulse on _process.
Minor wisps loop on 1.6s; elder on 2.0s with stronger scale + alpha
range. Zero count → dimmed and static. Count label below shows the
numeric value. Stagger via stagger_seconds export so chips don't
beat in unison."
```

---

## Task 3: HUD Redesign

Replace the existing HP+single-color text with the corner-tucked layout: HP bar top-left, 6 wisp chips + elder cluster bottom-left, 3 skill slots bottom-right.

**Files:**
- Modify: `scenes/ui/hud.tscn`
- Modify: `scripts/ui/hud.gd`

- [ ] **Step 1: Replace hud.tscn structure**

Read the current `scenes/ui/hud.tscn` first to confirm layout. Replace the entire scene file with the new structure. The new file:

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/ui/hud.gd" id="1_hud"]
[ext_resource type="PackedScene" path="res://scenes/ui/soul_wisp.tscn" id="2_wisp"]

[node name="HUD" type="CanvasLayer"]
script = ExtResource("1_hud")

; --- Top-left: HP bar ---
[node name="HpBox" type="MarginContainer" parent="."]
anchors_preset = 1
anchor_left = 0.0
anchor_top = 0.0
anchor_right = 0.0
anchor_bottom = 0.0
offset_left = 16.0
offset_top = 16.0
offset_right = 240.0
offset_bottom = 60.0

[node name="HpVBox" type="VBoxContainer" parent="HpBox"]
layout_mode = 2

[node name="HpLabel" type="Label" parent="HpBox/HpVBox"]
layout_mode = 2
text = "HEALTH"
theme_override_font_sizes/font_size = 9
theme_override_colors/font_color = Color(0.48, 0.38, 0.28, 1)

[node name="HpRow" type="HBoxContainer" parent="HpBox/HpVBox"]
layout_mode = 2
theme_override_constants/separation = 6

[node name="HpBar" type="ProgressBar" parent="HpBox/HpVBox/HpRow"]
custom_minimum_size = Vector2(160, 14)
layout_mode = 2
max_value = 100.0
value = 100.0
show_percentage = false

[node name="HpNumeric" type="Label" parent="HpBox/HpVBox/HpRow"]
layout_mode = 2
text = "100/100"
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0.78, 0.63, 0.31, 1)

; --- Bottom-left: Carry souls ---
[node name="SoulsBox" type="MarginContainer" parent="."]
anchors_preset = 7
anchor_left = 0.0
anchor_top = 1.0
anchor_right = 0.0
anchor_bottom = 1.0
offset_left = 16.0
offset_top = -76.0
offset_right = 320.0
offset_bottom = -16.0
grow_vertical = 0

[node name="SoulsVBox" type="VBoxContainer" parent="SoulsBox"]
layout_mode = 2

[node name="SoulsLabel" type="Label" parent="SoulsBox/SoulsVBox"]
layout_mode = 2
text = "CARRY"
theme_override_font_sizes/font_size = 9
theme_override_colors/font_color = Color(0.48, 0.38, 0.28, 1)

[node name="SoulsRow" type="HBoxContainer" parent="SoulsBox/SoulsVBox"]
layout_mode = 2
theme_override_constants/separation = 6

[node name="WispRed" parent="SoulsBox/SoulsVBox/SoulsRow" instance=ExtResource("2_wisp")]
color = Color(0.82, 0.25, 0.19, 1)
stagger_seconds = 0.0

[node name="WispBlue" parent="SoulsBox/SoulsVBox/SoulsRow" instance=ExtResource("2_wisp")]
color = Color(0.25, 0.56, 0.82, 1)
stagger_seconds = 0.27

[node name="WispGreen" parent="SoulsBox/SoulsVBox/SoulsRow" instance=ExtResource("2_wisp")]
color = Color(0.22, 0.54, 0.22, 1)
stagger_seconds = 0.53

[node name="WispPurple" parent="SoulsBox/SoulsVBox/SoulsRow" instance=ExtResource("2_wisp")]
color = Color(0.42, 0.22, 0.54, 1)
stagger_seconds = 0.80

[node name="WispGold" parent="SoulsBox/SoulsVBox/SoulsRow" instance=ExtResource("2_wisp")]
color = Color(0.82, 0.65, 0.18, 1)
stagger_seconds = 1.07

[node name="WispWhite" parent="SoulsBox/SoulsVBox/SoulsRow" instance=ExtResource("2_wisp")]
color = Color(0.94, 0.94, 0.88, 1)
stagger_seconds = 1.33

[node name="Divider" type="ColorRect" parent="SoulsBox/SoulsVBox/SoulsRow"]
custom_minimum_size = Vector2(1, 36)
layout_mode = 2
color = Color(0.29, 0.23, 0.16, 1)

[node name="WispElder" parent="SoulsBox/SoulsVBox/SoulsRow" instance=ExtResource("2_wisp")]
color = Color(0.96, 0.85, 0.44, 1)
is_elder = true
stagger_seconds = 0.0

; --- Bottom-right: Active skill ---
[node name="SkillBox" type="MarginContainer" parent="."]
anchors_preset = 3
anchor_left = 1.0
anchor_top = 1.0
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = -200.0
offset_top = -76.0
offset_right = -16.0
offset_bottom = -16.0
grow_horizontal = 0
grow_vertical = 0

[node name="SkillVBox" type="VBoxContainer" parent="SkillBox"]
layout_mode = 2

[node name="SkillLabel" type="Label" parent="SkillBox/SkillVBox"]
layout_mode = 2
text = "SKILL"
theme_override_font_sizes/font_size = 9
horizontal_alignment = 2
theme_override_colors/font_color = Color(0.48, 0.38, 0.28, 1)

[node name="SkillRow" type="HBoxContainer" parent="SkillBox/SkillVBox"]
layout_mode = 2
alignment = 2
theme_override_constants/separation = 4

[node name="Slot1" type="Label" parent="SkillBox/SkillVBox/SkillRow"]
custom_minimum_size = Vector2(32, 32)
layout_mode = 2
text = "1"
horizontal_alignment = 1
vertical_alignment = 1
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0.35, 0.29, 0.22, 1)

[node name="Slot2" type="Label" parent="SkillBox/SkillVBox/SkillRow"]
custom_minimum_size = Vector2(32, 32)
layout_mode = 2
text = "2"
horizontal_alignment = 1
vertical_alignment = 1
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0.35, 0.29, 0.22, 1)

[node name="Slot3" type="Label" parent="SkillBox/SkillVBox/SkillRow"]
custom_minimum_size = Vector2(32, 32)
layout_mode = 2
text = "3"
horizontal_alignment = 1
vertical_alignment = 1
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0.35, 0.29, 0.22, 1)

; --- Damage flash overlay (preserved from Phase 7) ---
[node name="DamageFlash" type="ColorRect" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
color = Color(0.8, 0.05, 0.05, 0)
```

The `DamageFlash` node from Phase 7 is preserved at the end so existing damage-flash behavior keeps working.

- [ ] **Step 2: Update hud.gd to wire all 6 colors + elder + active skill**

Read the current `scripts/ui/hud.gd` to confirm structure. Replace the entire file with:

```gdscript
extends CanvasLayer

@onready var _hp_bar: ProgressBar = $HpBox/HpVBox/HpRow/HpBar
@onready var _hp_numeric: Label = $HpBox/HpVBox/HpRow/HpNumeric
@onready var _wisp_red: Control = $SoulsBox/SoulsVBox/SoulsRow/WispRed
@onready var _wisp_blue: Control = $SoulsBox/SoulsVBox/SoulsRow/WispBlue
@onready var _wisp_green: Control = $SoulsBox/SoulsVBox/SoulsRow/WispGreen
@onready var _wisp_purple: Control = $SoulsBox/SoulsVBox/SoulsRow/WispPurple
@onready var _wisp_gold: Control = $SoulsBox/SoulsVBox/SoulsRow/WispGold
@onready var _wisp_white: Control = $SoulsBox/SoulsVBox/SoulsRow/WispWhite
@onready var _wisp_elder: Control = $SoulsBox/SoulsVBox/SoulsRow/WispElder
@onready var _slot1: Label = $SkillBox/SkillVBox/SkillRow/Slot1
@onready var _slot2: Label = $SkillBox/SkillVBox/SkillRow/Slot2
@onready var _slot3: Label = $SkillBox/SkillVBox/SkillRow/Slot3
@onready var _damage_flash: ColorRect = $DamageFlash

var _player: Node = null
var _skill_system: Node = null
var _flash_tween: Tween = null

const COLOR_TINT_BORDER: Dictionary = {
	"red": Color(0.82, 0.25, 0.19, 1),
	"blue": Color(0.25, 0.56, 0.82, 1),
	"green": Color(0.22, 0.54, 0.22, 1),
	"purple": Color(0.42, 0.22, 0.54, 1),
	"gold": Color(0.82, 0.65, 0.18, 1),
	"white": Color(0.94, 0.94, 0.88, 1),
}

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
		# Bind to SkillSystem if present
		if _player.has_node("SkillSystem"):
			_skill_system = _player.get_node("SkillSystem")
			if not _skill_system.active_skill_changed.is_connected(_on_active_skill_changed):
				_skill_system.active_skill_changed.connect(_on_active_skill_changed)
			_refresh_skill_slots()

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_bind_to_player()

func _on_carry_changed(_color: String, _tier: String, _new_count: int) -> void:
	_refresh_souls()

func _refresh_souls() -> void:
	_wisp_red.set_count(SoulEconomy.carry_count("red", "minor"))
	_wisp_blue.set_count(SoulEconomy.carry_count("blue", "minor"))
	_wisp_green.set_count(SoulEconomy.carry_count("green", "minor"))
	_wisp_purple.set_count(SoulEconomy.carry_count("purple", "minor"))
	_wisp_gold.set_count(SoulEconomy.carry_count("gold", "minor"))
	_wisp_white.set_count(SoulEconomy.carry_count("white", "minor"))
	# Elder is aggregate across all colors.
	var total_elder: int = 0
	for c in SoulEconomy.COLORS:
		total_elder += SoulEconomy.carry_count(c, "elder")
	_wisp_elder.set_count(total_elder)

func _on_hp_changed(new_hp: int) -> void:
	_hp_bar.value = float(new_hp)
	if _player != null:
		_hp_bar.max_value = float(_player.max_hp)
		_hp_numeric.text = "%d/%d" % [new_hp, _player.max_hp]
	else:
		_hp_numeric.text = "%d" % new_hp

func _on_active_skill_changed(_index: int) -> void:
	_refresh_skill_slots()

func _refresh_skill_slots() -> void:
	var slots: Array = [_slot1, _slot2, _slot3]
	for i in range(3):
		var slot: Label = slots[i]
		var skill = _skill_system.skill_at(i) if _skill_system != null else null
		if skill == null:
			slot.text = str(i + 1)
			slot.modulate = Color(0.35, 0.29, 0.22, 1)
			slot.add_theme_constant_override("outline_size", 0)
			continue
		var label_text: String = (skill.base_color as String).to_upper().substr(0, 4)
		slot.text = label_text
		var tint: Color = COLOR_TINT_BORDER.get(skill.base_color, Color.WHITE)
		# Active slot gets full color; others get dimmer tint.
		var is_active: bool = (i == _skill_system._active_index)
		slot.modulate = tint if is_active else Color(tint.r * 0.6, tint.g * 0.6, tint.b * 0.6, 1)

func play_damage_flash() -> void:
	if _damage_flash == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_damage_flash.color.a = 0.45
	_flash_tween = create_tween()
	_flash_tween.tween_property(_damage_flash, "color:a", 0.0, 0.35)
```

The `play_damage_flash` method is preserved from Phase 7. The `_skill_system._active_index` access uses the existing public field on `SkillSystem` (it's a `var`, not encapsulated).

- [ ] **Step 3: Run full suite, no regressions**

```bash
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/ --ignoreHeadlessMode
```

Expected: 148/148. The HUD has no direct unit tests; it's covered indirectly by the player/HUD integration that tests rely on.

- [ ] **Step 4: Commit**

```bash
git add scenes/ui/hud.tscn scripts/ui/hud.gd
git commit -m "feat(ui): redesign HUD — corner-tucked HP / 6 wisp chips + elder / skill slots

Top-left: HP label + ProgressBar + numeric. Bottom-left: CARRY label
+ 6 SoulWisp chips (one per color) + divider + aggregate-elder chip.
Bottom-right: SKILL label + 3 slots (active is fully tinted, others
dimmed). DamageFlash overlay preserved from Phase 7."
```

---

## Task 4: Run Stats Wiring

Hook the RunStats autoload into welp.gd (kill counting + damage source naming) and main_hall_upstairs_trigger (run reset).

**Files:**
- Modify: `scripts/entities/welp.gd`
- Modify: `scripts/entities/boss_dragon.gd`
- Modify: `scripts/world/main_hall_upstairs_trigger.gd`

- [ ] **Step 1: Reset RunStats on entry to upstairs**

Edit `scripts/world/main_hall_upstairs_trigger.gd`. Insert `RunStats.reset_run()` in `_on_body_entered` right BEFORE the existing `GameState.transition_to(GameState.Location.UPSTAIRS)` line. The full updated method:

```gdscript
func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if BossFlow.is_active():
		var banner: CanvasLayer = get_tree().root.find_child("DialogueBanner", true, false)
		if banner != null:
			banner.show_specific("The flames have already chosen.", 3.0)
		return
	RunStats.reset_run()
	GameState.transition_to(GameState.Location.UPSTAIRS)
```

- [ ] **Step 2: Record kills + display name in welp.gd**

Edit `scripts/entities/welp.gd`. In `take_damage`, when `hp == 0`, add `RunStats.record_kill()` after `_drop_souls()` and before `HitStop.freeze`. The full updated `take_damage`:

```gdscript
func take_damage(amount: int) -> void:
	if _is_dead:
		return
	hp = max(0, hp - amount)
	if hp == 0:
		_is_dead = true
		_drop_souls()
		RunStats.record_kill()
		HitStop.freeze(_hit_stop_duration())
		var burst_color: Color = Vfx.COLOR_ALBEDO.get(color, Color(0.5, 0.5, 0.5, 1))
		Vfx.spawn_death_burst(global_position + Vector3(0, 0.5, 0), burst_color, get_parent())
		died.emit(self, color)
		queue_free()
```

Add a new method `display_name()` anywhere in welp.gd (suggest near `take_damage`):

```gdscript
func display_name() -> String:
	# Used by run-end summary's "Killed by" line.
	# Format: "<color> <tier>" — e.g., "red welp", "blue dragon", "green elder".
	if color == "alarm" or color == "boss":
		return color
	return "%s %s" % [color, tier]
```

In `_attack_player`, BEFORE calling `_player.take_damage(attack_damage)`, record the damage source. Updated method:

```gdscript
func _attack_player() -> void:
	if _player != null and _player.has_method("take_damage"):
		RunStats.record_damage_from(display_name())
		_player.take_damage(attack_damage)
```

- [ ] **Step 3: Record kills + damage source in boss_dragon.gd**

Edit `scripts/entities/boss_dragon.gd`. In `take_damage`, when `hp == 0`, add `RunStats.record_kill()` BEFORE `BossFlow.boss_killed()`:

```gdscript
	if hp == 0:
		_is_dead = true
		died.emit()
		RunStats.record_kill()
		BossFlow.boss_killed()
		ScreenShake.shake(0.7, 0.6)
		Vfx.spawn_death_burst(global_position + Vector3(0, 1, 0), Color(0.6, 0.1, 0.1), get_parent())
		# … existing slow-mo tween chain …
```

Add a `display_name()` method:

```gdscript
func display_name() -> String:
	return "the dragon"
```

In `_physics_process`, find the contact damage line:

```gdscript
if _contact_timer <= 0.0 and _player.has_method("take_damage"):
	_player.take_damage(contact_damage)
```

Replace with:

```gdscript
if _contact_timer <= 0.0 and _player.has_method("take_damage"):
	RunStats.record_damage_from(display_name())
	_player.take_damage(contact_damage)
```

- [ ] **Step 4: Run full suite**

```bash
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/ --ignoreHeadlessMode
```

Expected: 148/148. Existing welp + boss tests don't exercise RunStats and don't break.

- [ ] **Step 5: Commit**

```bash
git add scripts/entities/welp.gd scripts/entities/boss_dragon.gd scripts/world/main_hall_upstairs_trigger.gd
git commit -m "feat(ui): wire RunStats — reset on run start, record kills + damage source

main_hall_upstairs_trigger calls RunStats.reset_run() on player entry.
welp.gd + boss_dragon.gd record kill on death and damage_from on attack.
Both expose display_name() for the run-end summary's 'Killed by' line."
```

---

## Task 5: How-to-Play Overlay

Reusable scene reachable from start screen and pause menu.

**Files:**
- Create: `scenes/ui/how_to_play.tscn`
- Create: `scripts/ui/how_to_play.gd`

- [ ] **Step 1: Create the script**

Create `scripts/ui/how_to_play.gd`:

```gdscript
extends CanvasLayer

signal closed

@onready var _back_btn: Button = $Backdrop/Center/Panel/VBox/BackBtn

func _ready() -> void:
	visible = false
	_back_btn.pressed.connect(_on_back)
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

func show_overlay() -> void:
	visible = true

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()

func _on_back() -> void:
	visible = false
	closed.emit()
```

- [ ] **Step 2: Create the scene**

Create `scenes/ui/how_to_play.tscn`:

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/ui/how_to_play.gd" id="1_help"]

[sub_resource type="StyleBoxFlat" id="panel_style"]
bg_color = Color(0.04, 0.024, 0.031, 0.97)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
border_color = Color(0.78, 0.63, 0.31, 1)
content_margin_left = 24.0
content_margin_top = 24.0
content_margin_right = 24.0
content_margin_bottom = 24.0

[sub_resource type="StyleBoxFlat" id="back_btn_style"]
bg_color = Color(0.1, 0.063, 0.078, 1)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
border_color = Color(0.78, 0.63, 0.31, 1)
content_margin_left = 16.0
content_margin_top = 8.0
content_margin_right = 16.0
content_margin_bottom = 8.0

[node name="HowToPlay" type="CanvasLayer"]
layer = 10
script = ExtResource("1_help")

[node name="Backdrop" type="ColorRect" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(0, 0, 0, 0.7)
mouse_filter = 0

[node name="Center" type="CenterContainer" parent="Backdrop"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2

[node name="Panel" type="PanelContainer" parent="Backdrop/Center"]
custom_minimum_size = Vector2(640, 480)
layout_mode = 2
theme_override_styles/panel = SubResource("panel_style")

[node name="VBox" type="VBoxContainer" parent="Backdrop/Center/Panel"]
layout_mode = 2
theme_override_constants/separation = 12

[node name="Title" type="Label" parent="Backdrop/Center/Panel/VBox"]
layout_mode = 2
text = "— How to Play —"
horizontal_alignment = 1
theme_override_font_sizes/font_size = 18
theme_override_colors/font_color = Color(0.78, 0.63, 0.31, 1)

[node name="Subtitle" type="Label" parent="Backdrop/Center/Panel/VBox"]
layout_mode = 2
text = "\"Pay attention this time.\""
horizontal_alignment = 1
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0.35, 0.29, 0.22, 1)

[node name="Sections" type="GridContainer" parent="Backdrop/Center/Panel/VBox"]
layout_mode = 2
columns = 2
theme_override_constants/h_separation = 24
theme_override_constants/v_separation = 16

; --- Controls section ---
[node name="ControlsCol" type="VBoxContainer" parent="Backdrop/Center/Panel/VBox/Sections"]
layout_mode = 2

[node name="ControlsHeader" type="Label" parent="Backdrop/Center/Panel/VBox/Sections/ControlsCol"]
layout_mode = 2
text = "CONTROLS"
theme_override_font_sizes/font_size = 10
theme_override_colors/font_color = Color(0.78, 0.63, 0.31, 1)

[node name="ControlsBody" type="RichTextLabel" parent="Backdrop/Center/Panel/VBox/Sections/ControlsCol"]
custom_minimum_size = Vector2(280, 130)
layout_mode = 2
bbcode_enabled = true
fit_content = true
text = "[color=#7a6048]WASD[/color]   move\n[color=#7a6048]SPACE[/color]   dash (i-frames)\n[color=#7a6048]CLICK / hold[/color]   cast active skill\n[color=#7a6048]1 / 2 / 3[/color]   switch active skill\n[color=#7a6048]ESC[/color]   pause / cancel\n\n[i][color=#5a4a38]\"Sword swings on its own. Don't make me explain it twice.\"[/color][/i]"

; --- The Loop section ---
[node name="LoopCol" type="VBoxContainer" parent="Backdrop/Center/Panel/VBox/Sections"]
layout_mode = 2

[node name="LoopHeader" type="Label" parent="Backdrop/Center/Panel/VBox/Sections/LoopCol"]
layout_mode = 2
text = "THE LOOP"
theme_override_font_sizes/font_size = 10
theme_override_colors/font_color = Color(0.78, 0.63, 0.31, 1)

[node name="LoopBody" type="RichTextLabel" parent="Backdrop/Center/Panel/VBox/Sections/LoopCol"]
custom_minimum_size = Vector2(280, 130)
layout_mode = 2
bbcode_enabled = true
fit_content = true
text = "1. [color=#e8d8b0]Descend[/color] from the hub into the open arena.\n2. [color=#e8d8b0]Slay[/color] dragons. Pick up the souls they drop.\n3. [color=#e8d8b0]Extract[/color] back to the hub before you die.\n4. [color=#e8d8b0]Deposit[/color] souls into the pyres.\n5. [color=#e8d8b0]Repeat[/color]. Light all six pyres.\n\n[i][color=#5a4a38]\"Death keeps your souls in the world. Don't die.\"[/color][/i]"

; --- Souls section ---
[node name="SoulsCol" type="VBoxContainer" parent="Backdrop/Center/Panel/VBox/Sections"]
layout_mode = 2

[node name="SoulsHeader" type="Label" parent="Backdrop/Center/Panel/VBox/Sections/SoulsCol"]
layout_mode = 2
text = "SOULS"
theme_override_font_sizes/font_size = 10
theme_override_colors/font_color = Color(0.78, 0.63, 0.31, 1)

[node name="SoulsBody" type="RichTextLabel" parent="Backdrop/Center/Panel/VBox/Sections/SoulsCol"]
custom_minimum_size = Vector2(280, 130)
layout_mode = 2
bbcode_enabled = true
fit_content = true
text = "Six colors. Each fills one pyre.\n\n[color=#f4d870]Elder souls[/color] count for ten of their own color and matter at the altar.\n\n[i][color=#5a4a38]\"They are not gifts. They are mine. You merely fetch.\"[/color][/i]"

; --- The Hub section ---
[node name="HubCol" type="VBoxContainer" parent="Backdrop/Center/Panel/VBox/Sections"]
layout_mode = 2

[node name="HubHeader" type="Label" parent="Backdrop/Center/Panel/VBox/Sections/HubCol"]
layout_mode = 2
text = "THE HUB"
theme_override_font_sizes/font_size = 10
theme_override_colors/font_color = Color(0.78, 0.63, 0.31, 1)

[node name="HubBody" type="RichTextLabel" parent="Backdrop/Center/Panel/VBox/Sections/HubCol"]
custom_minimum_size = Vector2(280, 130)
layout_mode = 2
bbcode_enabled = true
fit_content = true
text = "[color=#e8d8b0]Soul Altar[/color]: spend pyre fill to start your next run with one skill already unlocked.\n\n[color=#e8d8b0]Cantrip Stones[/color]: spend pyre fill for permanent +HP, +damage, or -dash cooldown.\n\n[color=#e8d8b0]Pyres[/color]: deposit souls. All six lit unlocks the descent.\n\n[i][color=#5a4a38]\"Try not to lose what little progress you make.\"[/color][/i]"

; --- Back button ---
[node name="BackRow" type="HBoxContainer" parent="Backdrop/Center/Panel/VBox"]
layout_mode = 2
alignment = 2

[node name="BackBtn" type="Button" parent="Backdrop/Center/Panel/VBox/BackRow"]
layout_mode = 2
text = "BACK"
theme_override_styles/normal = SubResource("back_btn_style")
theme_override_styles/hover = SubResource("back_btn_style")
theme_override_styles/pressed = SubResource("back_btn_style")
theme_override_font_sizes/font_size = 12
theme_override_colors/font_color = Color(0.91, 0.85, 0.69, 1)
```

- [ ] **Step 3: Run full suite, no regressions**

```bash
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/ --ignoreHeadlessMode
```

Expected: 148/148.

- [ ] **Step 4: Commit**

```bash
git add scripts/ui/how_to_play.gd scenes/ui/how_to_play.tscn
git commit -m "feat(ui): add HowToPlay overlay scene + script

Single-page reference with 4 sections (Controls, Loop, Souls, Hub),
each with a necromancer-voice italic quote. Reachable from start
screen and pause menu in later tasks. ESC dismisses; emits 'closed'
signal so caller can clean up state."
```

---

## Task 6: Start Screen

Initial scene on game launch (after Task 9 wiring). Split layout with hero New Game CTA.

**Files:**
- Create: `scenes/world/start_screen.tscn`
- Create: `scripts/world/start_screen.gd`

- [ ] **Step 1: Create the script**

Create `scripts/world/start_screen.gd`:

```gdscript
extends Control

const HOW_TO_PLAY_SCENE: PackedScene = preload("res://scenes/ui/how_to_play.tscn")

@onready var _btn_new: Button = $Center/HBox/Buttons/NewGame
@onready var _btn_continue: Button = $Center/HBox/Buttons/Continue
@onready var _btn_help: Button = $Center/HBox/Buttons/HowToPlay
@onready var _btn_quit: Button = $Center/HBox/Buttons/Quit
@onready var _confirm: ColorRect = $ConfirmOverwrite

func _ready() -> void:
	_btn_new.pressed.connect(_on_new_pressed)
	_btn_continue.pressed.connect(_on_continue_pressed)
	_btn_help.pressed.connect(_on_help_pressed)
	_btn_quit.pressed.connect(_on_quit_pressed)
	$ConfirmOverwrite/Center/Panel/VBox/Buttons/Yes.pressed.connect(_on_confirm_yes)
	$ConfirmOverwrite/Center/Panel/VBox/Buttons/No.pressed.connect(_on_confirm_no)
	_btn_continue.disabled = not _save_exists()
	_confirm.visible = false

func _save_exists() -> bool:
	return FileAccess.file_exists("user://save.tres")

func _on_new_pressed() -> void:
	if _save_exists():
		_confirm.visible = true
	else:
		_start_new_game()

func _on_confirm_yes() -> void:
	_confirm.visible = false
	# Wipe save file then reset all in-memory state.
	if FileAccess.file_exists("user://save.tres"):
		DirAccess.remove_absolute("user://save.tres")
	MetaProgress._init_defaults()
	SoulEconomy.reset_meta()
	BossFlow.reset()
	BossFlow.clear_retained_skills()
	_start_new_game()

func _on_confirm_no() -> void:
	_confirm.visible = false

func _start_new_game() -> void:
	GameState.transition_to(GameState.Location.MAIN_HALL)

func _on_continue_pressed() -> void:
	# GameState's autoload _ready already loads the save into MetaProgress + pyres.
	# Just transition to main hall.
	GameState.transition_to(GameState.Location.MAIN_HALL)

func _on_help_pressed() -> void:
	var help: CanvasLayer = HOW_TO_PLAY_SCENE.instantiate()
	add_child(help)
	help.show_overlay()
	help.closed.connect(help.queue_free)

func _on_quit_pressed() -> void:
	get_tree().quit()
```

- [ ] **Step 2: Create the scene**

Create `scenes/world/start_screen.tscn`:

```
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://scripts/world/start_screen.gd" id="1_start"]

[sub_resource type="StyleBoxFlat" id="hero_btn_style"]
bg_color = Color(0.16, 0.094, 0.078, 1)
border_width_left = 2
border_width_top = 2
border_width_right = 2
border_width_bottom = 2
border_color = Color(0.78, 0.63, 0.31, 1)
shadow_color = Color(0.78, 0.31, 0.16, 0.3)
shadow_size = 16
content_margin_left = 24.0
content_margin_top = 14.0
content_margin_right = 24.0
content_margin_bottom = 14.0

[sub_resource type="StyleBoxFlat" id="sec_btn_style"]
bg_color = Color(0.058, 0.039, 0.047, 1)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
border_color = Color(0.29, 0.23, 0.16, 1)
content_margin_left = 16.0
content_margin_top = 8.0
content_margin_right = 16.0
content_margin_bottom = 8.0

[sub_resource type="StyleBoxFlat" id="confirm_panel_style"]
bg_color = Color(0.04, 0.024, 0.031, 1)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
border_color = Color(0.78, 0.31, 0.16, 1)
content_margin_left = 24.0
content_margin_top = 24.0
content_margin_right = 24.0
content_margin_bottom = 24.0

[node name="StartScreen" type="Control"]
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1_start")

[node name="Background" type="ColorRect" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(0.04, 0.024, 0.031, 1)

[node name="Center" type="CenterContainer" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2

[node name="HBox" type="HBoxContainer" parent="Center"]
custom_minimum_size = Vector2(620, 240)
layout_mode = 2
theme_override_constants/separation = 48

[node name="Title" type="VBoxContainer" parent="Center/HBox"]
layout_mode = 2
size_flags_horizontal = 3

[node name="TitleText" type="Label" parent="Center/HBox/Title"]
layout_mode = 2
text = "New
Chance"
theme_override_font_sizes/font_size = 36
theme_override_colors/font_color = Color(0.78, 0.63, 0.31, 1)

[node name="Subtitle" type="Label" parent="Center/HBox/Title"]
layout_mode = 2
text = "a roguelike of disappointment"
theme_override_font_sizes/font_size = 10
theme_override_colors/font_color = Color(0.48, 0.38, 0.28, 1)

[node name="Spacer" type="Control" parent="Center/HBox/Title"]
custom_minimum_size = Vector2(0, 32)
layout_mode = 2

[node name="Version" type="Label" parent="Center/HBox/Title"]
layout_mode = 2
text = "v0.8-ui-pass"
theme_override_font_sizes/font_size = 10
theme_override_colors/font_color = Color(0.29, 0.23, 0.16, 1)

[node name="Buttons" type="VBoxContainer" parent="Center/HBox"]
layout_mode = 2
size_flags_horizontal = 3
theme_override_constants/separation = 6

[node name="NewGame" type="Button" parent="Center/HBox/Buttons"]
layout_mode = 2
text = "NEW GAME"
theme_override_styles/normal = SubResource("hero_btn_style")
theme_override_styles/hover = SubResource("hero_btn_style")
theme_override_styles/pressed = SubResource("hero_btn_style")
theme_override_font_sizes/font_size = 14
theme_override_colors/font_color = Color(0.91, 0.85, 0.69, 1)

[node name="Continue" type="Button" parent="Center/HBox/Buttons"]
layout_mode = 2
text = "CONTINUE"
theme_override_styles/normal = SubResource("sec_btn_style")
theme_override_styles/hover = SubResource("sec_btn_style")
theme_override_styles/pressed = SubResource("sec_btn_style")
theme_override_styles/disabled = SubResource("sec_btn_style")
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0.66, 0.55, 0.38, 1)

[node name="HowToPlay" type="Button" parent="Center/HBox/Buttons"]
layout_mode = 2
text = "HOW TO PLAY"
theme_override_styles/normal = SubResource("sec_btn_style")
theme_override_styles/hover = SubResource("sec_btn_style")
theme_override_styles/pressed = SubResource("sec_btn_style")
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0.66, 0.55, 0.38, 1)

[node name="Quit" type="Button" parent="Center/HBox/Buttons"]
layout_mode = 2
text = "QUIT"
theme_override_styles/normal = SubResource("sec_btn_style")
theme_override_styles/hover = SubResource("sec_btn_style")
theme_override_styles/pressed = SubResource("sec_btn_style")
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0.66, 0.55, 0.38, 1)

; --- Confirm overwrite modal (hidden by default) ---
[node name="ConfirmOverwrite" type="ColorRect" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(0, 0, 0, 0.7)
visible = false
mouse_filter = 0

[node name="Center" type="CenterContainer" parent="ConfirmOverwrite"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2

[node name="Panel" type="PanelContainer" parent="ConfirmOverwrite/Center"]
custom_minimum_size = Vector2(360, 0)
layout_mode = 2
theme_override_styles/panel = SubResource("confirm_panel_style")

[node name="VBox" type="VBoxContainer" parent="ConfirmOverwrite/Center/Panel"]
layout_mode = 2
theme_override_constants/separation = 12

[node name="Msg" type="Label" parent="ConfirmOverwrite/Center/Panel/VBox"]
layout_mode = 2
text = "A save exists.
Overwrite it and start fresh?"
horizontal_alignment = 1
theme_override_font_sizes/font_size = 12
theme_override_colors/font_color = Color(0.91, 0.85, 0.69, 1)

[node name="Buttons" type="HBoxContainer" parent="ConfirmOverwrite/Center/Panel/VBox"]
layout_mode = 2
alignment = 1
theme_override_constants/separation = 12

[node name="Yes" type="Button" parent="ConfirmOverwrite/Center/Panel/VBox/Buttons"]
layout_mode = 2
text = "YES"
theme_override_styles/normal = SubResource("hero_btn_style")
theme_override_styles/hover = SubResource("hero_btn_style")
theme_override_styles/pressed = SubResource("hero_btn_style")
theme_override_font_sizes/font_size = 12
theme_override_colors/font_color = Color(0.91, 0.85, 0.69, 1)

[node name="No" type="Button" parent="ConfirmOverwrite/Center/Panel/VBox/Buttons"]
layout_mode = 2
text = "NO"
theme_override_styles/normal = SubResource("sec_btn_style")
theme_override_styles/hover = SubResource("sec_btn_style")
theme_override_styles/pressed = SubResource("sec_btn_style")
theme_override_font_sizes/font_size = 12
theme_override_colors/font_color = Color(0.66, 0.55, 0.38, 1)
```

- [ ] **Step 3: Run full suite**

```bash
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/ --ignoreHeadlessMode
```

Expected: 148/148.

- [ ] **Step 4: Commit**

```bash
git add scripts/world/start_screen.gd scenes/world/start_screen.tscn
git commit -m "feat(ui): add start screen — split layout with hero New Game CTA

Title left, button stack right. NEW GAME (gold accent) with confirm
modal if a save exists. CONTINUE disabled when no save. HOW TO PLAY
opens the overlay. QUIT exits. The main_scene swap happens in Task 9."
```

---

## Task 7: Pause Menu Autoload

ESC overlay reachable from any gameplay scene. Adds Resume / How to Play / Restart Run / Quit to Menu.

**Files:**
- Create: `scenes/ui/pause_menu.tscn`
- Create: `scripts/ui/pause_menu.gd`
- Modify: `project.godot` (register PauseMenu autoload after RunStats)

- [ ] **Step 1: Create the script**

Create `scripts/ui/pause_menu.gd`:

```gdscript
extends CanvasLayer

const HOW_TO_PLAY_SCENE: PackedScene = preload("res://scenes/ui/how_to_play.tscn")

@onready var _backdrop: ColorRect = $Backdrop
@onready var _btn_resume: Button = $Backdrop/Center/Panel/VBox/Resume
@onready var _btn_help: Button = $Backdrop/Center/Panel/VBox/HowToPlay
@onready var _btn_restart: Button = $Backdrop/Center/Panel/VBox/RestartRun
@onready var _btn_quit: Button = $Backdrop/Center/Panel/VBox/QuitToMenu
@onready var _confirm: ColorRect = $ConfirmRestart

var _help_overlay: CanvasLayer = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	_btn_resume.pressed.connect(_close)
	_btn_help.pressed.connect(_on_help)
	_btn_restart.pressed.connect(_on_restart)
	_btn_quit.pressed.connect(_on_quit_to_menu)
	$ConfirmRestart/Center/Panel/VBox/Buttons/Yes.pressed.connect(_on_confirm_restart_yes)
	$ConfirmRestart/Center/Panel/VBox/Buttons/No.pressed.connect(_on_confirm_restart_no)
	_confirm.visible = false

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# Don't open over an existing modal that's also paused (descent prompt etc.)
	if not visible and get_tree().paused:
		return
	# If our help overlay is open, defer to it — it handles its own ESC and
	# we don't want pause menu to also close on the same keypress.
	if _help_overlay != null and is_instance_valid(_help_overlay) and _help_overlay.visible:
		return
	# Don't open over the confirm-restart sub-modal.
	if _confirm.visible:
		_confirm.visible = false
		get_viewport().set_input_as_handled()
		return
	if visible:
		_close()
	else:
		_open()
	get_viewport().set_input_as_handled()

func _open() -> void:
	# Don't open on start screen — pause is gameplay-only.
	if get_tree().current_scene != null and get_tree().current_scene.name == "StartScreen":
		return
	visible = true
	get_tree().paused = true

func _close() -> void:
	visible = false
	get_tree().paused = false

func _on_help() -> void:
	if _help_overlay != null and is_instance_valid(_help_overlay):
		return
	_help_overlay = HOW_TO_PLAY_SCENE.instantiate()
	add_child(_help_overlay)
	_help_overlay.show_overlay()
	_help_overlay.closed.connect(_on_help_closed)

func _on_help_closed() -> void:
	if _help_overlay != null and is_instance_valid(_help_overlay):
		_help_overlay.queue_free()
	_help_overlay = null

func _on_restart() -> void:
	_confirm.visible = true

func _on_confirm_restart_yes() -> void:
	_confirm.visible = false
	SoulEconomy.clear_carry()
	get_tree().paused = false
	visible = false
	GameState.transition_to(GameState.Location.MAIN_HALL)

func _on_confirm_restart_no() -> void:
	_confirm.visible = false

func _on_quit_to_menu() -> void:
	# Auto-save before transitioning. Mirror the save shape from GameState.end_run.
	var save_data: Dictionary = {
		"meta": MetaProgress.to_dict(),
		"pyres": _pyre_fills_dict(),
	}
	SaveSystem.save(save_data)
	get_tree().paused = false
	visible = false
	get_tree().change_scene_to_file("res://scenes/world/start_screen.tscn")

func _pyre_fills_dict() -> Dictionary:
	var d: Dictionary = {}
	for c in SoulEconomy.COLORS:
		d[c] = SoulEconomy.pyre_fill(c)
	return d
```

- [ ] **Step 2: Create the scene**

Create `scenes/ui/pause_menu.tscn`:

```
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://scripts/ui/pause_menu.gd" id="1_pause"]

[sub_resource type="StyleBoxFlat" id="panel_style"]
bg_color = Color(0.04, 0.024, 0.031, 0.97)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
border_color = Color(0.78, 0.63, 0.31, 1)
content_margin_left = 32.0
content_margin_top = 24.0
content_margin_right = 32.0
content_margin_bottom = 24.0

[sub_resource type="StyleBoxFlat" id="resume_btn_style"]
bg_color = Color(0.16, 0.094, 0.078, 1)
border_width_left = 2
border_width_top = 2
border_width_right = 2
border_width_bottom = 2
border_color = Color(0.78, 0.63, 0.31, 1)
content_margin_left = 32.0
content_margin_top = 10.0
content_margin_right = 32.0
content_margin_bottom = 10.0

[sub_resource type="StyleBoxFlat" id="sec_btn_style"]
bg_color = Color(0.058, 0.039, 0.047, 1)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
border_color = Color(0.29, 0.23, 0.16, 1)
content_margin_left = 32.0
content_margin_top = 8.0
content_margin_right = 32.0
content_margin_bottom = 8.0

[sub_resource type="StyleBoxFlat" id="restart_btn_style"]
bg_color = Color(0.058, 0.039, 0.047, 1)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
border_color = Color(0.42, 0.23, 0.16, 1)
content_margin_left = 32.0
content_margin_top = 8.0
content_margin_right = 32.0
content_margin_bottom = 8.0

[node name="PauseMenu" type="CanvasLayer"]
layer = 50
script = ExtResource("1_pause")

[node name="Backdrop" type="ColorRect" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(0, 0, 0, 0.65)
mouse_filter = 0

[node name="Center" type="CenterContainer" parent="Backdrop"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2

[node name="Panel" type="PanelContainer" parent="Backdrop/Center"]
layout_mode = 2
theme_override_styles/panel = SubResource("panel_style")

[node name="VBox" type="VBoxContainer" parent="Backdrop/Center/Panel"]
layout_mode = 2
theme_override_constants/separation = 6

[node name="Title" type="Label" parent="Backdrop/Center/Panel/VBox"]
layout_mode = 2
text = "— PAUSED —"
horizontal_alignment = 1
theme_override_font_sizes/font_size = 16
theme_override_colors/font_color = Color(0.78, 0.63, 0.31, 1)

[node name="Spacer" type="Control" parent="Backdrop/Center/Panel/VBox"]
custom_minimum_size = Vector2(0, 12)
layout_mode = 2

[node name="Resume" type="Button" parent="Backdrop/Center/Panel/VBox"]
layout_mode = 2
text = "RESUME"
theme_override_styles/normal = SubResource("resume_btn_style")
theme_override_styles/hover = SubResource("resume_btn_style")
theme_override_styles/pressed = SubResource("resume_btn_style")
theme_override_font_sizes/font_size = 13
theme_override_colors/font_color = Color(0.91, 0.85, 0.69, 1)

[node name="HowToPlay" type="Button" parent="Backdrop/Center/Panel/VBox"]
layout_mode = 2
text = "HOW TO PLAY"
theme_override_styles/normal = SubResource("sec_btn_style")
theme_override_styles/hover = SubResource("sec_btn_style")
theme_override_styles/pressed = SubResource("sec_btn_style")
theme_override_font_sizes/font_size = 12
theme_override_colors/font_color = Color(0.66, 0.55, 0.38, 1)

[node name="RestartRun" type="Button" parent="Backdrop/Center/Panel/VBox"]
layout_mode = 2
text = "RESTART RUN"
theme_override_styles/normal = SubResource("restart_btn_style")
theme_override_styles/hover = SubResource("restart_btn_style")
theme_override_styles/pressed = SubResource("restart_btn_style")
theme_override_font_sizes/font_size = 12
theme_override_colors/font_color = Color(0.66, 0.55, 0.38, 1)

[node name="QuitToMenu" type="Button" parent="Backdrop/Center/Panel/VBox"]
layout_mode = 2
text = "QUIT TO MENU"
theme_override_styles/normal = SubResource("sec_btn_style")
theme_override_styles/hover = SubResource("sec_btn_style")
theme_override_styles/pressed = SubResource("sec_btn_style")
theme_override_font_sizes/font_size = 12
theme_override_colors/font_color = Color(0.66, 0.55, 0.38, 1)

; --- Confirm restart sub-modal ---
[node name="ConfirmRestart" type="ColorRect" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(0, 0, 0, 0.7)
visible = false
mouse_filter = 0

[node name="Center" type="CenterContainer" parent="ConfirmRestart"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2

[node name="Panel" type="PanelContainer" parent="ConfirmRestart/Center"]
custom_minimum_size = Vector2(360, 0)
layout_mode = 2
theme_override_styles/panel = SubResource("panel_style")

[node name="VBox" type="VBoxContainer" parent="ConfirmRestart/Center/Panel"]
layout_mode = 2
theme_override_constants/separation = 12

[node name="Msg" type="Label" parent="ConfirmRestart/Center/Panel/VBox"]
layout_mode = 2
text = "Discard run?
Carry souls will be lost."
horizontal_alignment = 1
theme_override_font_sizes/font_size = 12
theme_override_colors/font_color = Color(0.91, 0.85, 0.69, 1)

[node name="Buttons" type="HBoxContainer" parent="ConfirmRestart/Center/Panel/VBox"]
layout_mode = 2
alignment = 1
theme_override_constants/separation = 12

[node name="Yes" type="Button" parent="ConfirmRestart/Center/Panel/VBox/Buttons"]
layout_mode = 2
text = "YES"
theme_override_styles/normal = SubResource("restart_btn_style")
theme_override_styles/hover = SubResource("restart_btn_style")
theme_override_styles/pressed = SubResource("restart_btn_style")
theme_override_font_sizes/font_size = 12
theme_override_colors/font_color = Color(0.91, 0.85, 0.69, 1)

[node name="No" type="Button" parent="ConfirmRestart/Center/Panel/VBox/Buttons"]
layout_mode = 2
text = "NO"
theme_override_styles/normal = SubResource("sec_btn_style")
theme_override_styles/hover = SubResource("sec_btn_style")
theme_override_styles/pressed = SubResource("sec_btn_style")
theme_override_font_sizes/font_size = 12
theme_override_colors/font_color = Color(0.66, 0.55, 0.38, 1)
```

- [ ] **Step 3: Register PauseMenu autoload in project.godot**

Edit `project.godot`. Add `PauseMenu` AFTER `RunStats`:

```ini
[autoload]

Debug="*res://scripts/core/debug.gd"
GameState="*res://scripts/core/game_state.gd"
SoulEconomy="*res://scripts/core/soul_economy.gd"
Escalation="*res://scripts/world/escalation.gd"
SaveSystem="*res://scripts/core/save_system.gd"
MetaProgress="*res://scripts/core/meta_progress.gd"
BossFlow="*res://scripts/core/boss_flow.gd"
ScreenShake="*res://scripts/world/screen_shake.gd"
HitStop="*res://scripts/world/hit_stop.gd"
RunStats="*res://scripts/core/run_stats.gd"
PauseMenu="*res://scenes/ui/pause_menu.tscn"
```

(Note: this autoload entry points to a `.tscn`, not a `.gd`. Godot supports both — scene-based autoloads instantiate the scene as a child of root.)

- [ ] **Step 4: Run full suite**

```bash
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/ --ignoreHeadlessMode
```

Expected: 148/148. Pause menu fires only on `ui_cancel` from `_input`, which doesn't trigger in tests.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/pause_menu.gd scenes/ui/pause_menu.tscn project.godot
git commit -m "feat(ui): add PauseMenu autoload with Resume/Help/Restart/Quit-to-menu

ESC opens; ESC again closes. Doesn't open on StartScreen or when
another modal already paused the tree. Restart Run shows a confirm
sub-modal that discards carry souls and returns to main hall.
Quit to Menu auto-saves and returns to start screen. Help opens
the HowToPlay overlay; closing returns to pause menu (still paused)."
```

---

## Task 8: Run-End Summary

Death-only stats panel. Replaces immediate scene transition in death_handler.

**Files:**
- Create: `scenes/ui/run_end_summary.tscn`
- Create: `scripts/ui/run_end_summary.gd`
- Modify: `scripts/world/death_handler.gd`

- [ ] **Step 1: Create the script**

Create `scripts/ui/run_end_summary.gd`:

```gdscript
extends CanvasLayer

@onready var _title: Label = $Backdrop/Center/Panel/VBox/Title
@onready var _quote: Label = $Backdrop/Center/Panel/VBox/Quote
@onready var _stat_time: Label = $Backdrop/Center/Panel/VBox/Stats/TimeValue
@onready var _stat_kills: Label = $Backdrop/Center/Panel/VBox/Stats/KillsValue
@onready var _stat_killer: Label = $Backdrop/Center/Panel/VBox/Stats/KillerValue
@onready var _souls_lost_box: VBoxContainer = $Backdrop/Center/Panel/VBox/SoulsLost
@onready var _souls_row: HBoxContainer = $Backdrop/Center/Panel/VBox/SoulsLost/Row
@onready var _btn_continue: Button = $Backdrop/Center/Panel/VBox/Buttons/Continue
@onready var _btn_quit: Button = $Backdrop/Center/Panel/VBox/Buttons/QuitToMenu

const SOUL_WISP_SCENE: PackedScene = preload("res://scenes/ui/soul_wisp.tscn")
const COLOR_TINT: Dictionary = {
	"red": Color(0.82, 0.25, 0.19, 1),
	"blue": Color(0.25, 0.56, 0.82, 1),
	"green": Color(0.22, 0.54, 0.22, 1),
	"purple": Color(0.42, 0.22, 0.54, 1),
	"gold": Color(0.82, 0.65, 0.18, 1),
	"white": Color(0.94, 0.94, 0.88, 1),
}

const TAUNT_NORMAL: Array[String] = [
	"Crawl back to the pyres. The dragons grow restless.",
	"Pathetic. I expected more from you, even now.",
	"Death again. As if you have nothing better to do.",
	"How disappointing. And yet, somehow, predictable.",
]
const TAUNT_BOSS: Array[String] = [
	"You came so far only to die at my feet. Touching.",
	"All those flames you stole, and still — not enough.",
	"You should have stayed upstairs, little corpse.",
	"I made you. Do you really think I cannot unmake you?",
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	_btn_continue.pressed.connect(_on_continue)
	_btn_quit.pressed.connect(_on_quit_to_menu)

func show_summary(boss_death: bool) -> void:
	if boss_death:
		_title.text = "— Defeated —"
		_quote.text = TAUNT_BOSS[randi() % TAUNT_BOSS.size()]
	else:
		_title.text = "— You Died —"
		_quote.text = TAUNT_NORMAL[randi() % TAUNT_NORMAL.size()]
	_stat_time.text = _format_time(RunStats.elapsed_seconds())
	_stat_kills.text = str(RunStats.enemies_slain)
	if RunStats.last_damage_source_name == "":
		_stat_killer.text = "—"
	else:
		_stat_killer.text = RunStats.last_damage_source_name
	_populate_souls_lost()
	visible = true
	get_tree().paused = true

func _format_time(seconds: float) -> String:
	var total: int = int(seconds)
	return "%d:%02d" % [total / 60, total % 60]

func _populate_souls_lost() -> void:
	# Clear any prior wisps from a previous run summary.
	for child in _souls_row.get_children():
		child.queue_free()
	var any_carry: bool = false
	for c in SoulEconomy.COLORS:
		if SoulEconomy.carry_count(c, "minor") > 0 or SoulEconomy.carry_count(c, "elder") > 0:
			any_carry = true
			break
	if not any_carry:
		_souls_lost_box.visible = false
		return
	_souls_lost_box.visible = true
	# Add a wisp per color (dimmed-static for run-end aesthetic).
	for c in SoulEconomy.COLORS:
		var wisp: Control = SOUL_WISP_SCENE.instantiate()
		_souls_row.add_child(wisp)
		wisp.color = COLOR_TINT.get(c, Color.WHITE)
		wisp.set_count(SoulEconomy.carry_count(c, "minor"))
		wisp.set_process(false)  # static for run-end
	# Divider.
	var divider: ColorRect = ColorRect.new()
	divider.custom_minimum_size = Vector2(1, 36)
	divider.color = Color(0.29, 0.23, 0.16, 1)
	_souls_row.add_child(divider)
	# Aggregate elder.
	var elder_total: int = 0
	for c in SoulEconomy.COLORS:
		elder_total += SoulEconomy.carry_count(c, "elder")
	var elder_wisp: Control = SOUL_WISP_SCENE.instantiate()
	_souls_row.add_child(elder_wisp)
	elder_wisp.color = Color(0.96, 0.85, 0.44, 1)
	elder_wisp.is_elder = true
	elder_wisp.set_count(elder_total)
	elder_wisp.set_process(false)

func _on_continue() -> void:
	visible = false
	get_tree().paused = false
	GameState.end_run(GameState.Outcome.DIED)

func _on_quit_to_menu() -> void:
	visible = false
	get_tree().paused = false
	# Save state so the user doesn't lose progress.
	var save_data: Dictionary = {
		"meta": MetaProgress.to_dict(),
		"pyres": _pyre_fills_dict(),
	}
	SaveSystem.save(save_data)
	get_tree().change_scene_to_file("res://scenes/world/start_screen.tscn")

func _pyre_fills_dict() -> Dictionary:
	var d: Dictionary = {}
	for c in SoulEconomy.COLORS:
		d[c] = SoulEconomy.pyre_fill(c)
	return d
```

- [ ] **Step 2: Create the scene**

Create `scenes/ui/run_end_summary.tscn`:

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/ui/run_end_summary.gd" id="1_summary"]

[sub_resource type="StyleBoxFlat" id="panel_style"]
bg_color = Color(0.04, 0.024, 0.031, 0.97)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
border_color = Color(0.42, 0.16, 0.16, 1)
shadow_color = Color(0.47, 0.094, 0.094, 0.3)
shadow_size = 24
content_margin_left = 24.0
content_margin_top = 22.0
content_margin_right = 24.0
content_margin_bottom = 22.0

[sub_resource type="StyleBoxFlat" id="continue_btn_style"]
bg_color = Color(0.16, 0.094, 0.078, 1)
border_width_left = 2
border_width_top = 2
border_width_right = 2
border_width_bottom = 2
border_color = Color(0.78, 0.63, 0.31, 1)
content_margin_left = 16.0
content_margin_top = 10.0
content_margin_right = 16.0
content_margin_bottom = 10.0

[sub_resource type="StyleBoxFlat" id="sec_btn_style"]
bg_color = Color(0.058, 0.039, 0.047, 1)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
border_color = Color(0.29, 0.23, 0.16, 1)
content_margin_left = 16.0
content_margin_top = 8.0
content_margin_right = 16.0
content_margin_bottom = 8.0

[node name="RunEndSummary" type="CanvasLayer"]
layer = 40
script = ExtResource("1_summary")

[node name="Backdrop" type="ColorRect" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(0, 0, 0, 0.7)
mouse_filter = 0

[node name="Center" type="CenterContainer" parent="Backdrop"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2

[node name="Panel" type="PanelContainer" parent="Backdrop/Center"]
custom_minimum_size = Vector2(360, 0)
layout_mode = 2
theme_override_styles/panel = SubResource("panel_style")

[node name="VBox" type="VBoxContainer" parent="Backdrop/Center/Panel"]
layout_mode = 2
theme_override_constants/separation = 8

[node name="Title" type="Label" parent="Backdrop/Center/Panel/VBox"]
layout_mode = 2
text = "— You Died —"
horizontal_alignment = 1
theme_override_font_sizes/font_size = 20
theme_override_colors/font_color = Color(0.78, 0.25, 0.19, 1)

[node name="Quote" type="Label" parent="Backdrop/Center/Panel/VBox"]
layout_mode = 2
text = ""
horizontal_alignment = 1
autowrap_mode = 2
custom_minimum_size = Vector2(312, 0)
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0.48, 0.38, 0.28, 1)

[node name="Stats" type="GridContainer" parent="Backdrop/Center/Panel/VBox"]
layout_mode = 2
columns = 2
theme_override_constants/h_separation = 18
theme_override_constants/v_separation = 6

[node name="TimeLabel" type="Label" parent="Backdrop/Center/Panel/VBox/Stats"]
layout_mode = 2
text = "Survived"
theme_override_font_sizes/font_size = 12
theme_override_colors/font_color = Color(0.48, 0.38, 0.28, 1)

[node name="TimeValue" type="Label" parent="Backdrop/Center/Panel/VBox/Stats"]
layout_mode = 2
text = "0:00"
horizontal_alignment = 2
size_flags_horizontal = 3
theme_override_font_sizes/font_size = 12
theme_override_colors/font_color = Color(0.91, 0.85, 0.69, 1)

[node name="KillsLabel" type="Label" parent="Backdrop/Center/Panel/VBox/Stats"]
layout_mode = 2
text = "Enemies slain"
theme_override_font_sizes/font_size = 12
theme_override_colors/font_color = Color(0.48, 0.38, 0.28, 1)

[node name="KillsValue" type="Label" parent="Backdrop/Center/Panel/VBox/Stats"]
layout_mode = 2
text = "0"
horizontal_alignment = 2
size_flags_horizontal = 3
theme_override_font_sizes/font_size = 12
theme_override_colors/font_color = Color(0.91, 0.85, 0.69, 1)

[node name="KillerLabel" type="Label" parent="Backdrop/Center/Panel/VBox/Stats"]
layout_mode = 2
text = "Killed by"
theme_override_font_sizes/font_size = 12
theme_override_colors/font_color = Color(0.48, 0.38, 0.28, 1)

[node name="KillerValue" type="Label" parent="Backdrop/Center/Panel/VBox/Stats"]
layout_mode = 2
text = "—"
horizontal_alignment = 2
size_flags_horizontal = 3
theme_override_font_sizes/font_size = 12
theme_override_colors/font_color = Color(0.78, 0.25, 0.19, 1)

[node name="SoulsLost" type="VBoxContainer" parent="Backdrop/Center/Panel/VBox"]
layout_mode = 2
theme_override_constants/separation = 4

[node name="Header" type="Label" parent="Backdrop/Center/Panel/VBox/SoulsLost"]
layout_mode = 2
text = "SOULS LOST"
theme_override_font_sizes/font_size = 9
theme_override_colors/font_color = Color(0.48, 0.38, 0.28, 1)

[node name="Row" type="HBoxContainer" parent="Backdrop/Center/Panel/VBox/SoulsLost"]
layout_mode = 2
theme_override_constants/separation = 6

[node name="Buttons" type="HBoxContainer" parent="Backdrop/Center/Panel/VBox"]
layout_mode = 2
alignment = 1
theme_override_constants/separation = 8

[node name="Continue" type="Button" parent="Backdrop/Center/Panel/VBox/Buttons"]
layout_mode = 2
text = "CONTINUE"
size_flags_horizontal = 3
theme_override_styles/normal = SubResource("continue_btn_style")
theme_override_styles/hover = SubResource("continue_btn_style")
theme_override_styles/pressed = SubResource("continue_btn_style")
theme_override_font_sizes/font_size = 13
theme_override_colors/font_color = Color(0.91, 0.85, 0.69, 1)

[node name="QuitToMenu" type="Button" parent="Backdrop/Center/Panel/VBox/Buttons"]
layout_mode = 2
text = "QUIT TO MENU"
size_flags_horizontal = 3
theme_override_styles/normal = SubResource("sec_btn_style")
theme_override_styles/hover = SubResource("sec_btn_style")
theme_override_styles/pressed = SubResource("sec_btn_style")
theme_override_font_sizes/font_size = 12
theme_override_colors/font_color = Color(0.66, 0.55, 0.38, 1)
```

- [ ] **Step 3: Modify death_handler.gd to show the summary**

Edit `scripts/world/death_handler.gd`. Replace the entire `_on_player_died` method:

```gdscript
const RUN_END_SCENE: PackedScene = preload("res://scenes/ui/run_end_summary.tscn")

func _on_player_died() -> void:
	var boss_death: bool = (GameState.current_location == GameState.Location.COURTYARD)
	if boss_death:
		BossFlow.player_died_in_boss()
	# Spawn the summary overlay as a child of root so it survives any scene
	# operations the Continue button triggers.
	var summary: CanvasLayer = RUN_END_SCENE.instantiate()
	get_tree().root.add_child(summary)
	summary.show_summary(boss_death)
```

Add the `RUN_END_SCENE` preload at the top of the file (just below `extends Node`).

NOTE: this REPLACES the prior pending-banner-line behavior from Phase 6. The summary overlay now carries the death narrative; the DialogueBanner pending-line plumbing is no longer used for death. (It still functions for any other future use; we just don't invoke `BossFlow.set_pending_banner_line` from death_handler anymore.)

- [ ] **Step 4: Run full suite**

```bash
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/ --ignoreHeadlessMode
```

Expected: 148/148. The boss_flow tests for `_pending_banner_line` still pass (they test the BossFlow API directly, not whether death_handler calls it).

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/run_end_summary.gd scenes/ui/run_end_summary.tscn scripts/world/death_handler.gd
git commit -m "feat(ui): add run-end summary panel + wire from death_handler

Death now opens a summary overlay (instead of immediate scene swap)
showing time survived, enemies slain, killed-by, and a SOULS LOST
panel that mirrors the HUD wisp layout (dimmed, static). Continue
returns to main hall via the existing GameState.end_run flow. Quit
to Menu auto-saves and returns to start screen. Boss-death uses the
'Defeated' title variant and TAUNT_BOSS pool."
```

---

## Task 9: Switch main_scene to Start Screen + Final Validation

The last step — swapping the entry scene so the game launches into the start screen.

**Files:**
- Modify: `project.godot` (main_scene line)

- [ ] **Step 1: Switch the main_scene**

Edit `project.godot`. Find the `[application]` block (around line 11-15). Change the `run/main_scene` line:

From:
```ini
run/main_scene="res://scenes/world/main_hall.tscn"
```

To:
```ini
run/main_scene="res://scenes/world/start_screen.tscn"
```

- [ ] **Step 2: Run full suite**

```bash
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/ --ignoreHeadlessMode
```

Expected: 148/148. Tests don't depend on main_scene.

- [ ] **Step 3: Commit**

```bash
git add project.godot
git commit -m "feat(ui): switch main_scene from main_hall to start_screen

Game now launches into the start screen. New Game / Continue both
transition to main_hall via GameState.transition_to. Closes Phase 8."
```

---

## Final Validation

- [ ] **Step 1: Full test suite green**

```bash
cd /c/Users/wyenk/OneDrive/Documents/godot/new-chance
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/ --ignoreHeadlessMode
```

Expected: 148/148.

- [ ] **Step 2: Push branch**

```bash
git push -u origin phase-8-ui-pass
```

- [ ] **Step 3: USER playtest checklist**

User opens the game and validates:
- Start screen appears on launch with correct layout (title left, hero New Game right).
- Continue is greyed out if no save; enabled with save.
- New Game with existing save shows confirmation modal.
- Quit exits cleanly.
- How to Play opens overlay with all 4 sections; ESC or Back dismisses.
- In hub: HUD shows HP bar top-left, 6 wisp chips bottom-left animating with stagger, elder cluster with star + brighter glow, 3 skill slots bottom-right.
- Picking up souls updates the correct color chip; deposit clears them.
- Picking up an elder soul increments the aggregate elder chip.
- Picking up the first soul in a slot lights up the slot in that color; switching with 1/2/3 changes which slot is full-bright.
- ESC during gameplay opens pause menu; ESC again closes.
- Pause menu Resume / Help / Restart Run (with confirm) / Quit to Menu all work.
- ESC during descent_prompt does NOT also open pause menu (modal isolation).
- Player death (in upstairs) opens summary panel with correct stats; Continue returns to main hall.
- Player death (in courtyard) shows "Defeated" variant; Continue returns to main hall in BossFlow.LOST state.

After user approval: merge to master, tag `v0.8-ui-pass`.
