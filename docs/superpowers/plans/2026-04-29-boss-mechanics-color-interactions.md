# Boss Mechanics + Tier 1 Color Interactions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the v0.9 boss fight: 8 telegraphed mechanics across 3 phases plus 16 color-specific counterplay interactions, sword white-modifier scaling, and wall concurrent cap.

**Architecture:** Each boss mechanic is a Node child of `boss_dragon`. A shared `BossTelegraph` state machine (IDLE → WINDUP → EXECUTION → COOLDOWN) drives timing. A shared `BossMechanic` base class holds cooldowns + per-phase config; subclasses override `_on_windup_start`, `_on_execution_start`, `_on_execution_end`. Boss owns mutual-exclusivity logic and per-frame mechanic dispatch.

**Tech Stack:** Godot 4.6, GDScript, GdUnit4 testing.

---

## Test Runner

All tests run via:
```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/<file>.gd
```

Full suite:
```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```

---

## File Structure

**New files:**

| Path | Responsibility |
|---|---|
| `scripts/entities/boss_telegraph.gd` | State machine: IDLE/WINDUP/EXECUTION/COOLDOWN with per-state timers and signals |
| `scripts/entities/boss_mechanic.gd` | Base class for each boss mechanic; holds telegraph + cooldown + phase unlock |
| `scripts/entities/boss_mechanics/mechanic_slam.gd` | Telegraphed slam |
| `scripts/entities/boss_mechanics/mechanic_static_breath.gd` | Static breath cone |
| `scripts/entities/boss_mechanics/mechanic_sweeping_breath.gd` | Sweeping breath cone |
| `scripts/entities/boss_mechanics/mechanic_mark.gd` | Mark + delayed strike |
| `scripts/entities/boss_mechanics/mechanic_armor_wings.gd` | Armor wings defensive ability |
| `scripts/entities/boss_mechanics/mechanic_charge.gd` | Charge attack |
| `scripts/entities/boss_mechanics/mechanic_flying_slam.gd` | Flying slam |
| `scripts/entities/boss_mechanics/mechanic_jump.gd` | Conditional jump (anti-DoT-park) |
| `scripts/effects/effect_breath_cone.gd` + `.tscn` | Breath cone visual + damage area |
| `scripts/effects/effect_mark_zone.gd` + `.tscn` | Mark + delayed strike floor zone visual |
| `scripts/effects/effect_charge_indicator.gd` + `.tscn` | Charge telegraph line |
| `scripts/effects/effect_flying_slam_zone.gd` + `.tscn` | Flying slam landing indicator |
| Tests in `test/` for each new script | |

**Modified files:**

| Path | What changes |
|---|---|
| `scripts/entities/boss_dragon.gd` | Add mechanic registry + scheduler + mutual exclusivity + armor wings reduction in take_damage + jump trigger |
| `scripts/entities/sword.gd` | White-modifier scaling |
| `scripts/skills/cast_white_bone.gd` | Despawn oldest wall when 3rd is cast |
| `scripts/effects/effect_bone_wall.gd` | Track spawn time; absorb mark; participate in charge stop logic |
| `scripts/skills/damage_pipeline.gd` | Pass through armor-wing source tag suffix |

---

## Task 1: Sword white-modifier scaling

**Files:**
- Modify: `scripts/entities/sword.gd`
- Modify: `scripts/entities/player.gd:42-47`
- Test: `test/test_sword_scaling.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_sword_scaling.gd`:

```gdscript
extends GdUnitTestSuite

const SwordScene: PackedScene = preload("res://scenes/entities/sword.tscn")

var sword: Area3D

func before_test() -> void:
	sword = auto_free(SwordScene.instantiate())
	add_child(sword)
	await get_tree().process_frame

func test_sword_dmg_no_white_returns_base() -> void:
	sword.set_active_element("red", 0)
	assert_that(sword.scaled_damage()).is_equal(15)

func test_sword_dmg_white_base_n1_scales() -> void:
	# n = 0 modifiers + 1 (white base) = 1; mult = 1 + 1*(1 - 0.7^1) = 1.30; floor(15*1.30) = 19
	sword.set_active_element("white", 0)
	assert_that(sword.scaled_damage()).is_equal(19)

func test_sword_dmg_white_base_with_modifiers() -> void:
	# n = 4 + 1 = 5; mult = 1 + 1*(1 - 0.7^5) = 1.832; floor(15*1.832) = 27
	sword.set_active_element("white", 4)
	assert_that(sword.scaled_damage()).is_equal(27)

func test_sword_dmg_caps_at_2x() -> void:
	# Very high n approaches 2.0× → floor(30) = 30
	sword.set_active_element("red", 100)
	assert_that(sword.scaled_damage()).is_equal(29)  # red base, n=100 only-modifiers; mult ≈ 2.0
	# Use 200 to get floor(30) precisely from float artifacts
```

- [ ] **Step 2: Run test to verify it fails**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_sword_scaling.gd
```
Expected: FAIL — `set_active_element` signature mismatch / `scaled_damage` not defined.

- [ ] **Step 3: Update sword.gd to add scaling**

Modify `scripts/entities/sword.gd`. Replace `set_active_element` and add `scaled_damage`:

```gdscript
var _white_count: int = 0  # white modifiers on the active skill (excludes implicit base-color +1)

func set_active_element(color: String, white_modifier_count: int = 0) -> void:
	_active_color = color
	_white_count = white_modifier_count
	_passive_armor_timer = 0.0  # reset on switch
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

func scaled_damage() -> int:
	var n: int = _white_count + (1 if _active_color == "white" else 0)
	var multiplier: float = 1.0 + 1.0 * (1.0 - pow(0.7, n))
	return int(base_damage * multiplier)
```

Update sword's `_process` damage call to use `scaled_damage()`:

```gdscript
DamagePipeline.apply(enemy, scaled_damage(), [], _active_color, global_position, "sword")
```

- [ ] **Step 4: Update player.gd to pass white count**

Modify `scripts/entities/player.gd`, `_on_active_skill_changed`:

```gdscript
func _on_active_skill_changed(_index: int) -> void:
	if _skill_system == null:
		return
	var element: String = _skill_system.active_element()
	var white_count: int = 0
	var skill: Skill = _skill_system.active_skill()
	if skill != null:
		white_count = skill.modifier_count_for("white")
	if has_node("Sword"):
		$Sword.set_active_element(element, white_count)
```

Also update `_on_run_ended` to pass 0:

```gdscript
if has_node("Sword"):
	$Sword.set_active_element("", 0)
```

- [ ] **Step 5: Run tests to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_sword_scaling.gd
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```
Expected: all pass; full suite stays at 197/197 (193 + 4 new).

- [ ] **Step 6: Commit**

```bash
git add test/test_sword_scaling.gd scripts/entities/sword.gd scripts/entities/player.gd
git commit -m "feat: sword damage scales with white modifiers, asymptote 2x base"
```

---

## Task 2: Wall concurrent cap (max 2)

**Files:**
- Modify: `scripts/effects/effect_bone_wall.gd`
- Modify: `scripts/skills/cast_white_bone.gd`
- Test: `test/test_wall_cap.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_wall_cap.gd`:

```gdscript
extends GdUnitTestSuite

const WallScene: PackedScene = preload("res://scenes/effects/effect_bone_wall.tscn")

func test_wall_registers_in_group() -> void:
	var wall: StaticBody3D = auto_free(WallScene.instantiate())
	add_child(wall)
	wall.configure(30, 1.5, 4.0)
	await get_tree().process_frame
	assert_bool(wall.is_in_group("bone_wall")).is_true()
	assert_int(wall.spawn_time_msec).is_greater(0)

func test_third_wall_despawns_oldest() -> void:
	# Spawn three walls in sequence; oldest should be freed
	var w1: StaticBody3D = auto_free(WallScene.instantiate())
	var w2: StaticBody3D = auto_free(WallScene.instantiate())
	add_child(w1); w1.configure(30, 1.5, 4.0); await get_tree().process_frame
	add_child(w2); w2.configure(30, 1.5, 4.0); await get_tree().process_frame
	# Simulate the cast logic enforcing the cap before instantiating w3
	var existing: Array = get_tree().get_nodes_in_group("bone_wall")
	existing.sort_custom(func(a, b): return a.spawn_time_msec < b.spawn_time_msec)
	if existing.size() >= 2:
		existing[0].queue_free()
	await get_tree().process_frame
	assert_bool(is_instance_valid(w1)).is_false()
	assert_bool(is_instance_valid(w2)).is_true()
```

- [ ] **Step 2: Run to verify failure**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_wall_cap.gd
```
Expected: FAIL — `spawn_time_msec` not defined; `bone_wall` group not present.

- [ ] **Step 3: Update wall to register**

Modify `scripts/effects/effect_bone_wall.gd`. Add property and register in `_ready`:

```gdscript
var spawn_time_msec: int = 0

func _ready() -> void:
	spawn_time_msec = Time.get_ticks_msec()
	add_to_group("bone_wall")
	# ... existing _ready logic preserved
```

- [ ] **Step 4: Update cast_white_bone.gd to enforce cap**

Modify `scripts/skills/cast_white_bone.gd`. Before `wall = EFFECT_WALL_SCENE.instantiate()`, add:

```gdscript
const MAX_CONCURRENT_WALLS: int = 2

func _ready() -> void:
	# Enforce concurrent wall cap before spawning new wall
	var existing: Array = get_tree().get_nodes_in_group("bone_wall")
	if existing.size() >= MAX_CONCURRENT_WALLS:
		existing.sort_custom(func(a, b): return a.spawn_time_msec < b.spawn_time_msec)
		existing[0].queue_free()
	# ... rest of existing _ready (compute perp, instantiate wall, etc.)
```

- [ ] **Step 5: Run tests to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_wall_cap.gd
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```
Expected: pass; full suite green.

- [ ] **Step 6: Commit**

```bash
git add test/test_wall_cap.gd scripts/effects/effect_bone_wall.gd scripts/skills/cast_white_bone.gd
git commit -m "feat: cap white walls at 2 concurrent, despawn oldest on 3rd cast"
```

---

## Task 3: BossTelegraph state machine

**Files:**
- Create: `scripts/entities/boss_telegraph.gd`
- Test: `test/test_boss_telegraph.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_boss_telegraph.gd`:

```gdscript
extends GdUnitTestSuite

const BossTelegraph = preload("res://scripts/entities/boss_telegraph.gd")

func test_starts_idle() -> void:
	var t: BossTelegraph = BossTelegraph.new()
	assert_int(t.state).is_equal(BossTelegraph.State.IDLE)
	assert_bool(t.is_busy()).is_false()

func test_start_windup_transitions_to_windup() -> void:
	var t: BossTelegraph = BossTelegraph.new()
	t.windup_duration = 1.0
	t.execution_duration = 0.5
	t.start_windup()
	assert_int(t.state).is_equal(BossTelegraph.State.WINDUP)
	assert_bool(t.is_busy()).is_true()

func test_windup_completes_to_execution() -> void:
	var t: BossTelegraph = BossTelegraph.new()
	t.windup_duration = 1.0
	t.execution_duration = 0.5
	t.start_windup()
	t.tick(1.1)  # exceed windup
	assert_int(t.state).is_equal(BossTelegraph.State.EXECUTION)
	assert_bool(t.is_busy()).is_true()

func test_execution_completes_to_idle() -> void:
	var t: BossTelegraph = BossTelegraph.new()
	t.windup_duration = 0.1
	t.execution_duration = 0.5
	t.start_windup()
	t.tick(0.2)  # past windup, now in EXECUTION
	t.tick(0.6)  # past execution
	assert_int(t.state).is_equal(BossTelegraph.State.IDLE)
	assert_bool(t.is_busy()).is_false()

func test_signals_fire_in_order() -> void:
	var t: BossTelegraph = BossTelegraph.new()
	t.windup_duration = 0.1
	t.execution_duration = 0.1
	var events: Array[String] = []
	t.windup_started.connect(func(): events.append("windup"))
	t.execution_started.connect(func(): events.append("execution"))
	t.execution_ended.connect(func(): events.append("end"))
	t.start_windup()
	t.tick(0.15)
	t.tick(0.15)
	assert_array(events).is_equal(["windup", "execution", "end"])
```

- [ ] **Step 2: Run to verify failure**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_boss_telegraph.gd
```
Expected: FAIL — script not defined.

- [ ] **Step 3: Implement state machine**

Create `scripts/entities/boss_telegraph.gd`:

```gdscript
extends RefCounted
class_name BossTelegraph

# Per-mechanic timing state machine. Each mechanic owns one of these and
# drives it via tick(delta). Signals fire at state transitions so the
# mechanic can wire windup/execution/end behaviors.

enum State { IDLE, WINDUP, EXECUTION }

signal windup_started
signal execution_started
signal execution_ended

var state: int = State.IDLE
var windup_duration: float = 0.0
var execution_duration: float = 0.0
var _timer: float = 0.0

func start_windup() -> void:
	state = State.WINDUP
	_timer = windup_duration
	windup_started.emit()

func tick(delta: float) -> void:
	if state == State.IDLE:
		return
	_timer -= delta
	if _timer <= 0.0:
		if state == State.WINDUP:
			state = State.EXECUTION
			_timer = execution_duration
			execution_started.emit()
		else:  # EXECUTION
			state = State.IDLE
			_timer = 0.0
			execution_ended.emit()

func is_busy() -> bool:
	return state != State.IDLE

func extend_windup(extra: float) -> void:
	# Used by blue chill to delay the windup. Only valid during WINDUP.
	if state != State.WINDUP:
		return
	_timer += extra
```

- [ ] **Step 4: Run to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_boss_telegraph.gd
```
Expected: 5/5 pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/entities/boss_telegraph.gd test/test_boss_telegraph.gd
git commit -m "feat: BossTelegraph state machine for boss mechanic windup/execution timing"
```

---

## Task 4: BossMechanic base class

**Files:**
- Create: `scripts/entities/boss_mechanic.gd`
- Test: `test/test_boss_mechanic.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_boss_mechanic.gd`:

```gdscript
extends GdUnitTestSuite

const BossMechanic = preload("res://scripts/entities/boss_mechanic.gd")

func test_starts_ready_when_unlocked() -> void:
	var m: Node = BossMechanic.new()
	add_child(auto_free(m))
	m.unlock_phase = 1
	m.cooldowns_by_phase = {1: 5.0}
	assert_bool(m.is_ready(1)).is_true()
	assert_bool(m.is_ready(0)).is_false()  # phase 0 = not unlocked

func test_unlock_phase_gates_readiness() -> void:
	var m: Node = BossMechanic.new()
	add_child(auto_free(m))
	m.unlock_phase = 3
	m.cooldowns_by_phase = {1: 5.0, 2: 4.0, 3: 3.0}
	assert_bool(m.is_ready(1)).is_false()
	assert_bool(m.is_ready(2)).is_false()
	assert_bool(m.is_ready(3)).is_true()

func test_trigger_starts_telegraph_and_resets_cooldown() -> void:
	var m: Node = BossMechanic.new()
	add_child(auto_free(m))
	m.unlock_phase = 1
	m.cooldowns_by_phase = {1: 5.0}
	m.windup_duration = 0.5
	m.execution_duration = 0.2
	m.trigger(1)
	assert_bool(m.is_busy()).is_true()
	assert_bool(m.is_ready(1)).is_false()  # cooldown active
```

- [ ] **Step 2: Run to verify failure**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_boss_mechanic.gd
```
Expected: FAIL — script not defined.

- [ ] **Step 3: Implement base class**

Create `scripts/entities/boss_mechanic.gd`:

```gdscript
extends Node
class_name BossMechanic

const TelegraphScript = preload("res://scripts/entities/boss_telegraph.gd")

# Base class for boss mechanics. Subclasses set windup/execution durations,
# cooldowns_by_phase, unlock_phase, and override the lifecycle hooks.

var unlock_phase: int = 1
var cooldowns_by_phase: Dictionary = {1: 5.0, 2: 4.0, 3: 3.0}
var windup_duration: float = 0.6
var execution_duration: float = 0.0
var is_big: bool = true  # mutual-exclusivity flag

var _telegraph: BossTelegraph
var _cooldown_remaining: float = 0.0
var _boss: Node = null

func _ready() -> void:
	_telegraph = TelegraphScript.new()
	_telegraph.windup_started.connect(_on_windup_start)
	_telegraph.execution_started.connect(_on_execution_start)
	_telegraph.execution_ended.connect(_on_execution_end)
	_boss = get_parent()

func tick(delta: float, current_phase: int) -> void:
	_telegraph.windup_duration = windup_duration
	_telegraph.execution_duration = execution_duration
	_telegraph.tick(delta)
	if _telegraph.state == BossTelegraph.State.IDLE:
		_cooldown_remaining = max(0.0, _cooldown_remaining - delta)

func is_busy() -> bool:
	return _telegraph.is_busy()

func is_ready(phase: int) -> bool:
	if phase < unlock_phase:
		return false
	if _telegraph.is_busy():
		return false
	return _cooldown_remaining <= 0.0

func trigger(phase: int) -> void:
	_telegraph.windup_duration = windup_duration
	_telegraph.execution_duration = execution_duration
	_telegraph.start_windup()
	_cooldown_remaining = cooldowns_by_phase.get(phase, 5.0)

func extend_windup(extra: float) -> void:
	_telegraph.extend_windup(extra)

func is_in_windup() -> bool:
	return _telegraph.state == BossTelegraph.State.WINDUP

func is_in_execution() -> bool:
	return _telegraph.state == BossTelegraph.State.EXECUTION

# Subclasses override these:
func _on_windup_start() -> void: pass
func _on_execution_start() -> void: pass
func _on_execution_end() -> void: pass
```

- [ ] **Step 4: Run to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_boss_mechanic.gd
```
Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/entities/boss_mechanic.gd test/test_boss_mechanic.gd
git commit -m "feat: BossMechanic base class for telegraphed boss abilities"
```

---

## Task 5: Wire mechanic registry into boss_dragon

**Files:**
- Modify: `scripts/entities/boss_dragon.gd`
- Test: `test/test_boss_scheduler.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_boss_scheduler.gd`:

```gdscript
extends GdUnitTestSuite

const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const BossMechanic = preload("res://scripts/entities/boss_mechanic.gd")

var boss: CharacterBody3D

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	add_child(boss)
	await get_tree().process_frame

func test_boss_starts_with_empty_mechanic_list() -> void:
	# Scheduler exists but mechanics added in subsequent tasks
	assert_object(boss._mechanics).is_not_null()

func test_register_mechanic_adds_to_list() -> void:
	var m: Node = BossMechanic.new()
	m.unlock_phase = 1
	boss._register_mechanic(m)
	assert_int(boss._mechanics.size()).is_equal(1)

func test_busy_check_returns_true_when_any_mechanic_busy() -> void:
	var m: Node = BossMechanic.new()
	m.unlock_phase = 1
	m.windup_duration = 0.1
	m.execution_duration = 0.1
	boss._register_mechanic(m)
	await get_tree().process_frame  # _ready on m
	m.trigger(1)
	assert_bool(boss._any_mechanic_busy()).is_true()
```

- [ ] **Step 2: Run to verify failure**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_boss_scheduler.gd
```
Expected: FAIL — `_mechanics` and `_register_mechanic` not defined.

- [ ] **Step 3: Add scheduler to boss_dragon**

Modify `scripts/entities/boss_dragon.gd`. Add near top:

```gdscript
var _mechanics: Array[Node] = []
```

Add helper methods:

```gdscript
func _register_mechanic(m: Node) -> void:
	add_child(m)
	_mechanics.append(m)

func _any_mechanic_busy() -> bool:
	for m in _mechanics:
		if m.is_busy():
			return true
	return false

func _tick_mechanics(delta: float) -> void:
	var phase: int = _phase
	for m in _mechanics:
		m.tick(delta, phase)
	if _any_mechanic_busy():
		return
	# Pick one ready mechanic to fire
	var ready: Array[Node] = []
	for m in _mechanics:
		if m.is_ready(phase):
			ready.append(m)
	if ready.is_empty():
		return
	# Random selection from ready set
	var pick: Node = ready[randi() % ready.size()]
	pick.trigger(phase)
```

In `_physics_process`, after the existing `_tick_status_effects(delta)` call, add:

```gdscript
_tick_mechanics(delta)
```

- [ ] **Step 4: Run to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_boss_scheduler.gd
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```
Expected: pass; full suite green.

- [ ] **Step 5: Commit**

```bash
git add scripts/entities/boss_dragon.gd test/test_boss_scheduler.gd
git commit -m "feat: boss mechanic registry + per-frame scheduler with mutual exclusivity"
```

---

## Task 6: Slam mechanic (P1)

**Files:**
- Create: `scripts/entities/boss_mechanics/mechanic_slam.gd`
- Modify: `scripts/entities/boss_dragon.gd` (register slam in `_ready`)
- Test: `test/test_mechanic_slam.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_mechanic_slam.gd`:

```gdscript
extends GdUnitTestSuite

const SlamScript = preload("res://scripts/entities/boss_mechanics/mechanic_slam.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

var boss: CharacterBody3D
var player: CharacterBody3D
var slam: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	add_child(player); player.global_position = Vector3(1.5, 0, 0)  # within 2m AoE
	await get_tree().process_frame
	slam = SlamScript.new()
	boss._register_mechanic(slam)
	await get_tree().process_frame

func test_slam_has_correct_timings() -> void:
	assert_float(slam.windup_duration).is_equal(0.6)
	assert_float(slam.execution_duration).is_equal_approx(0.0, 0.001)

func test_slam_unlocked_at_phase_1() -> void:
	assert_int(slam.unlock_phase).is_equal(1)

func test_slam_damages_player_in_aoe_on_execution() -> void:
	var initial_hp: int = player.hp
	slam.trigger(1)
	# advance through windup + execution
	for i in range(8):
		await get_tree().physics_frame
	assert_int(player.hp).is_less(initial_hp)

func test_slam_does_not_damage_player_outside_aoe() -> void:
	player.global_position = Vector3(5, 0, 0)  # well outside 2m
	await get_tree().physics_frame
	var initial_hp: int = player.hp
	slam.trigger(1)
	for i in range(8):
		await get_tree().physics_frame
	assert_int(player.hp).is_equal(initial_hp)
```

- [ ] **Step 2: Run to verify failure**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_mechanic_slam.gd
```
Expected: FAIL.

- [ ] **Step 3: Implement slam**

Create `scripts/entities/boss_mechanics/mechanic_slam.gd`:

```gdscript
extends BossMechanic

# Telegraphed slam — small AoE around boss position. Universal dodge-out.

const RADIUS: float = 2.0
const DAMAGE: int = 25

func _init() -> void:
	unlock_phase = 1
	is_big = true
	cooldowns_by_phase = {1: 5.0, 2: 4.0, 3: 3.0}
	windup_duration = 0.6
	execution_duration = 0.0  # impact is instantaneous on execution start

func _on_execution_start() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	var center: Vector3 = _boss.global_position
	var players: Array = get_tree().get_nodes_in_group("player")
	for p in players:
		if not is_instance_valid(p):
			continue
		if p.global_position.distance_to(center) <= RADIUS:
			if p.has_method("take_damage"):
				p.take_damage(DAMAGE)
	ScreenShake.shake(0.05, 0.1)
```

- [ ] **Step 4: Register slam in boss_dragon._ready**

Modify `scripts/entities/boss_dragon.gd` `_ready`:

```gdscript
const MechanicSlam = preload("res://scripts/entities/boss_mechanics/mechanic_slam.gd")

func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 2
	collision_mask = collision_mask | 8
	DamageMeter.start_for_target(self)
	_register_mechanic(MechanicSlam.new())
	_find_player()
```

- [ ] **Step 5: Run to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_mechanic_slam.gd
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```
Expected: pass; full suite green.

- [ ] **Step 6: Commit**

```bash
git add scripts/entities/boss_mechanics/mechanic_slam.gd scripts/entities/boss_dragon.gd test/test_mechanic_slam.gd
git commit -m "feat: boss telegraphed slam mechanic (P1, 25 dmg, 2m AoE, 0.6s windup)"
```

---

## Task 7: BreathCone effect

**Files:**
- Create: `scripts/effects/effect_breath_cone.gd`
- Create: `scenes/effects/effect_breath_cone.tscn` (Node3D with HitArea Area3D + visual mesh)
- Test: `test/test_effect_breath_cone.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_effect_breath_cone.gd`:

```gdscript
extends GdUnitTestSuite

const ConeScene: PackedScene = preload("res://scenes/effects/effect_breath_cone.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

var cone: Node3D
var player: CharacterBody3D

func before_test() -> void:
	cone = auto_free(ConeScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	add_child(cone)
	add_child(player)
	await get_tree().process_frame

func test_cone_configures_with_origin_direction_length_angle() -> void:
	cone.configure(Vector3.ZERO, Vector3.FORWARD, 5.0, 60.0, 0.8, 10)
	assert_vector(cone.global_position).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.01)
	assert_float(cone.length).is_equal(5.0)
	assert_float(cone.cone_angle_deg).is_equal(60.0)

func test_cone_ticks_damage_to_player_in_cone() -> void:
	cone.configure(Vector3.ZERO, Vector3.FORWARD, 5.0, 60.0, 0.8, 10)
	player.global_position = Vector3(0, 0, 2)  # forward 2m
	await get_tree().process_frame
	var initial_hp: int = player.hp
	# Advance for 0.5s in physics frames; expect 2-3 ticks of 10
	for i in range(35):
		await get_tree().physics_frame
	assert_int(player.hp).is_less(initial_hp)

func test_cone_expires_after_lifetime() -> void:
	cone.configure(Vector3.ZERO, Vector3.FORWARD, 5.0, 60.0, 0.2, 10)  # 0.2s lifetime
	for i in range(20):
		await get_tree().physics_frame
	assert_bool(is_instance_valid(cone)).is_false()
```

- [ ] **Step 2: Run to verify failure**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_effect_breath_cone.gd
```
Expected: FAIL — scene doesn't exist.

- [ ] **Step 3: Create the breath cone scene and script**

Create `scripts/effects/effect_breath_cone.gd`:

```gdscript
extends Node3D

# Breath cone: damages the player while they're in the cone arc, ticking
# every TICK_INTERVAL seconds for tick_damage. Lifetime expires after the
# configured duration. Used by both static and sweeping breath.

const TICK_INTERVAL: float = 0.2

@export var length: float = 5.0
@export var cone_angle_deg: float = 60.0
@export var lifetime: float = 0.8
@export var tick_damage: int = 10

var direction: Vector3 = Vector3.FORWARD
var blocking_walls_check: Callable = Callable()  # optional: returns true if a wall blocks the segment to a position
var blocking_clouds_check: Callable = Callable()  # optional: returns true if a cloud blocks the segment

var _age: float = 0.0
var _tick_timer: float = 0.0

func configure(origin: Vector3, dir: Vector3, p_length: float, p_angle_deg: float, p_lifetime: float, p_tick_damage: int) -> void:
	global_position = origin
	direction = dir.normalized()
	length = p_length
	cone_angle_deg = p_angle_deg
	lifetime = p_lifetime
	tick_damage = p_tick_damage

func _process(delta: float) -> void:
	_age += delta
	_tick_timer += delta
	if _tick_timer >= TICK_INTERVAL:
		_tick_timer = 0.0
		_tick_targets()
	if _age >= lifetime:
		queue_free()

func _tick_targets() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	for p in players:
		if not is_instance_valid(p):
			continue
		if not _in_cone(p.global_position):
			continue
		# Color interaction hooks (optional callables wired by mechanic)
		if blocking_walls_check.is_valid() and blocking_walls_check.call(p.global_position):
			continue
		if blocking_clouds_check.is_valid() and blocking_clouds_check.call(p.global_position):
			continue
		if p.has_method("take_damage"):
			p.take_damage(tick_damage)

func _in_cone(target_pos: Vector3) -> bool:
	var to_target: Vector3 = target_pos - global_position
	to_target.y = 0.0
	var dist: float = to_target.length()
	if dist > length or dist < 0.01:
		return false
	var dir_flat: Vector3 = direction
	dir_flat.y = 0.0
	dir_flat = dir_flat.normalized()
	var to_target_norm: Vector3 = to_target.normalized()
	var angle: float = rad_to_deg(acos(clampf(dir_flat.dot(to_target_norm), -1.0, 1.0)))
	return angle <= cone_angle_deg / 2.0

func set_direction(dir: Vector3) -> void:
	direction = dir.normalized()
```

Create `scenes/effects/effect_breath_cone.tscn` (in editor or as text):

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/effects/effect_breath_cone.gd" id="1"]

[sub_resource type="StandardMaterial3D" id="mat_cone"]
albedo_color = Color(1, 0.3, 0.1, 0.4)
transparency = 1
emission_enabled = true
emission = Color(1, 0.3, 0.1, 1)
emission_energy_multiplier = 1.5

[sub_resource type="CylinderMesh" id="mesh_cone"]
top_radius = 2.5
bottom_radius = 0.1
height = 5.0
material = SubResource("mat_cone")

[node name="EffectBreathCone" type="Node3D"]
script = ExtResource("1")

[node name="Mesh" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 0, -1, 0, 1, 0, 0, 0, 2.5)
mesh = SubResource("mesh_cone")
```

- [ ] **Step 4: Run to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_effect_breath_cone.gd
```
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/effects/effect_breath_cone.gd scenes/effects/effect_breath_cone.tscn test/test_effect_breath_cone.gd
git commit -m "feat: breath cone effect with tick damage + lifetime + color-interaction hooks"
```

---

## Task 8: Static breath mechanic (P1)

**Files:**
- Create: `scripts/entities/boss_mechanics/mechanic_static_breath.gd`
- Modify: `scripts/entities/boss_dragon.gd` (register)
- Test: `test/test_mechanic_static_breath.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_mechanic_static_breath.gd`:

```gdscript
extends GdUnitTestSuite

const BreathScript = preload("res://scripts/entities/boss_mechanics/mechanic_static_breath.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

var boss: CharacterBody3D
var player: CharacterBody3D
var breath: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	add_child(player); player.global_position = Vector3(0, 0, 3)
	await get_tree().process_frame
	breath = BreathScript.new()
	boss._register_mechanic(breath)
	await get_tree().process_frame

func test_timings() -> void:
	assert_float(breath.windup_duration).is_equal_approx(1.0, 0.001)
	assert_float(breath.execution_duration).is_equal_approx(0.8, 0.001)

func test_unlocked_phase_1() -> void:
	assert_int(breath.unlock_phase).is_equal(1)

func test_breath_damages_player_in_cone() -> void:
	var initial_hp: int = player.hp
	breath.trigger(1)
	for i in range(120):  # ~2s
		await get_tree().physics_frame
	assert_int(player.hp).is_less(initial_hp)
```

- [ ] **Step 2: Run to verify failure**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_mechanic_static_breath.gd
```
Expected: FAIL.

- [ ] **Step 3: Implement static breath**

Create `scripts/entities/boss_mechanics/mechanic_static_breath.gd`:

```gdscript
extends BossMechanic

const BreathConeScene: PackedScene = preload("res://scenes/effects/effect_breath_cone.tscn")
const CONE_LENGTH: float = 5.0
const CONE_ANGLE_DEG: float = 60.0
const TICK_DAMAGE: int = 10

var _cone: Node3D = null
var _aim_dir: Vector3 = Vector3.FORWARD

func _init() -> void:
	unlock_phase = 1
	is_big = true
	cooldowns_by_phase = {1: 8.0, 2: 6.0, 3: 5.0}
	windup_duration = 1.0
	execution_duration = 0.8

func _on_windup_start() -> void:
	# Lock aim at telegraph start, toward nearest player
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		_aim_dir = Vector3.FORWARD
		return
	var p: Node = players[0]
	var to_p: Vector3 = p.global_position - _boss.global_position
	to_p.y = 0.0
	if to_p.length() > 0.01:
		_aim_dir = to_p.normalized()

func _on_execution_start() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	_cone = BreathConeScene.instantiate()
	_boss.get_parent().add_child(_cone)
	_cone.configure(_boss.global_position, _aim_dir, CONE_LENGTH, CONE_ANGLE_DEG, execution_duration, TICK_DAMAGE)

func current_aim() -> Vector3:
	return _aim_dir

func set_aim(new_dir: Vector3) -> void:
	# For purple pull cone redirection. Updates aim during windup and re-aims live cone.
	new_dir.y = 0.0
	if new_dir.length() < 0.01:
		return
	_aim_dir = new_dir.normalized()
	if _cone != null and is_instance_valid(_cone):
		_cone.set_direction(_aim_dir)
```

- [ ] **Step 4: Register in boss_dragon**

Modify `scripts/entities/boss_dragon.gd`:

```gdscript
const MechanicStaticBreath = preload("res://scripts/entities/boss_mechanics/mechanic_static_breath.gd")

# In _ready, after _register_mechanic(MechanicSlam.new()):
_register_mechanic(MechanicStaticBreath.new())
```

- [ ] **Step 5: Run to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_mechanic_static_breath.gd
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```
Expected: pass; full suite green.

- [ ] **Step 6: Commit**

```bash
git add scripts/entities/boss_mechanics/mechanic_static_breath.gd scripts/entities/boss_dragon.gd test/test_mechanic_static_breath.gd
git commit -m "feat: boss static breath mechanic (P1, cone, 1.0s windup, 0.8s execution)"
```

---

## Task 9: White wall blocks breath

**Files:**
- Modify: `scripts/entities/boss_mechanics/mechanic_static_breath.gd`
- Modify: `scripts/effects/effect_bone_wall.gd` (add segment-blocking helper)
- Test: `test/test_breath_wall_block.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_breath_wall_block.gd`:

```gdscript
extends GdUnitTestSuite

const BreathScript = preload("res://scripts/entities/boss_mechanics/mechanic_static_breath.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")
const WallScene: PackedScene = preload("res://scenes/effects/effect_bone_wall.tscn")

var boss: CharacterBody3D
var player: CharacterBody3D
var wall: StaticBody3D
var breath: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	wall = auto_free(WallScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	add_child(player); player.global_position = Vector3(0, 0, 4)
	add_child(wall); wall.global_position = Vector3(0, 0, 2)  # between boss and player
	wall.configure(30, 1.5, 4.0)
	await get_tree().process_frame
	breath = BreathScript.new()
	boss._register_mechanic(breath)
	await get_tree().process_frame

func test_wall_between_boss_and_player_blocks_breath() -> void:
	var initial_hp: int = player.hp
	breath.trigger(1)
	for i in range(120):
		await get_tree().physics_frame
	assert_int(player.hp).is_equal(initial_hp)  # wall blocked

func test_wall_takes_damage_from_blocked_breath() -> void:
	var initial_wall_hp: int = wall.hp if "hp" in wall else 30
	breath.trigger(1)
	for i in range(120):
		await get_tree().physics_frame
	if "hp" in wall and is_instance_valid(wall):
		assert_int(wall.hp).is_less(initial_wall_hp)
```

- [ ] **Step 2: Run to verify failure**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_breath_wall_block.gd
```
Expected: FAIL — wall doesn't block.

- [ ] **Step 3: Add segment-blocking helper to wall**

Modify `scripts/effects/effect_bone_wall.gd`. Add method:

```gdscript
func blocks_segment(from: Vector3, to: Vector3) -> bool:
	# Treat wall as a thin AABB at its position and rotation. Returns true if
	# the segment from→to crosses the wall plane within wall length.
	var wall_pos: Vector3 = global_position
	var wall_axis: Vector3 = global_transform.basis.x.normalized()  # length axis
	var wall_normal: Vector3 = global_transform.basis.z.normalized()  # facing
	var segment_dir: Vector3 = to - from
	var seg_len: float = segment_dir.length()
	if seg_len < 0.001:
		return false
	# Project segment onto wall normal; if both endpoints same side, no cross
	var d_from: float = (from - wall_pos).dot(wall_normal)
	var d_to: float = (to - wall_pos).dot(wall_normal)
	if (d_from >= 0 and d_to >= 0) or (d_from <= 0 and d_to <= 0):
		return false
	var t: float = d_from / (d_from - d_to)
	var hit: Vector3 = from + segment_dir * t
	# Check the hit point is within wall length along the wall axis
	var along: float = (hit - wall_pos).dot(wall_axis)
	var half_length: float = length_total * 0.5 if "length_total" in self else 2.0
	return absf(along) <= half_length
```

(Note: `length_total` should already exist on the wall from existing `configure()` — verify in the file. If named differently, adjust.)

- [ ] **Step 4: Wire wall-block into breath mechanic**

Modify `scripts/entities/boss_mechanics/mechanic_static_breath.gd` `_on_execution_start`:

```gdscript
func _on_execution_start() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	_cone = BreathConeScene.instantiate()
	_boss.get_parent().add_child(_cone)
	_cone.configure(_boss.global_position, _aim_dir, CONE_LENGTH, CONE_ANGLE_DEG, execution_duration, TICK_DAMAGE)
	_cone.blocking_walls_check = func(target_pos: Vector3) -> bool:
		return _segment_blocked_by_wall(_boss.global_position, target_pos)

func _segment_blocked_by_wall(from: Vector3, to: Vector3) -> bool:
	var walls: Array = get_tree().get_nodes_in_group("bone_wall")
	for w in walls:
		if not is_instance_valid(w):
			continue
		if w.has_method("blocks_segment") and w.blocks_segment(from, to):
			# Wall takes 1 damage per blocked tick
			if w.has_method("take_damage"):
				w.take_damage(1)
			return true
	return false
```

- [ ] **Step 5: Run tests to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_breath_wall_block.gd
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```
Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/entities/boss_mechanics/mechanic_static_breath.gd scripts/effects/effect_bone_wall.gd test/test_breath_wall_block.gd
git commit -m "feat: white wall blocks breath cone segments + takes damage from blocked ticks"
```

---

## Task 10: Green cloud blocks breath

**Files:**
- Modify: `scripts/entities/boss_mechanics/mechanic_static_breath.gd`
- Modify: `scripts/effects/effect_cloud.gd` (add segment overlap helper)
- Test: `test/test_breath_cloud_block.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_breath_cloud_block.gd`:

```gdscript
extends GdUnitTestSuite

const BreathScript = preload("res://scripts/entities/boss_mechanics/mechanic_static_breath.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")
const CloudScene: PackedScene = preload("res://scenes/effects/effect_cloud.tscn")

var boss: CharacterBody3D
var player: CharacterBody3D
var cloud: Node3D
var breath: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	cloud = auto_free(CloudScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	add_child(player); player.global_position = Vector3(0, 0, 4)
	add_child(cloud); cloud.global_position = Vector3(0, 0, 2)
	cloud.configure(10.0, 2.0, 6, [], "green")
	await get_tree().process_frame
	breath = BreathScript.new()
	boss._register_mechanic(breath)
	await get_tree().process_frame

func test_cloud_between_boss_and_player_blocks_breath() -> void:
	var initial_hp: int = player.hp
	breath.trigger(1)
	for i in range(120):
		await get_tree().physics_frame
	assert_int(player.hp).is_equal(initial_hp)
```

- [ ] **Step 2: Run to verify failure**

Expected: FAIL.

- [ ] **Step 3: Add segment overlap helper to cloud**

Modify `scripts/effects/effect_cloud.gd`. Add method:

```gdscript
func blocks_segment(from: Vector3, to: Vector3) -> bool:
	# True if the line segment from→to passes within `radius` of the cloud center.
	var center: Vector3 = global_position
	var seg: Vector3 = to - from
	var seg_len_sq: float = seg.length_squared()
	if seg_len_sq < 0.0001:
		return from.distance_to(center) <= radius
	var t: float = clampf((center - from).dot(seg) / seg_len_sq, 0.0, 1.0)
	var closest: Vector3 = from + seg * t
	return closest.distance_to(center) <= radius
```

- [ ] **Step 4: Wire cloud-block into breath**

Modify `scripts/entities/boss_mechanics/mechanic_static_breath.gd` `_on_execution_start`. Add the blocking_clouds_check assignment:

```gdscript
	_cone.blocking_clouds_check = func(target_pos: Vector3) -> bool:
		return _segment_blocked_by_cloud(_boss.global_position, target_pos)

func _segment_blocked_by_cloud(from: Vector3, to: Vector3) -> bool:
	var clouds: Array = get_tree().get_nodes_in_group("damage_cloud")
	for c in clouds:
		if not is_instance_valid(c):
			continue
		if c.has_method("blocks_segment") and c.blocks_segment(from, to):
			return true
	return false
```

Modify `scripts/effects/effect_cloud.gd` `_ready` to add to group:

```gdscript
func _ready() -> void:
	add_to_group("damage_cloud")
```

(If `_ready` doesn't exist, create it; otherwise append to existing.)

- [ ] **Step 5: Run tests to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_breath_cloud_block.gd
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```
Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/entities/boss_mechanics/mechanic_static_breath.gd scripts/effects/effect_cloud.gd test/test_breath_cloud_block.gd
git commit -m "feat: green cloud blocks breath cone segments"
```

---

## Task 11: Blue chill extends breath telegraph

**Files:**
- Modify: `scripts/entities/boss_mechanics/mechanic_static_breath.gd`
- Modify: `scripts/entities/boss_dragon.gd` (route chill applications to active breath mechanic)
- Test: `test/test_breath_chill_extends.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_breath_chill_extends.gd`:

```gdscript
extends GdUnitTestSuite

const BreathScript = preload("res://scripts/entities/boss_mechanics/mechanic_static_breath.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")

var boss: CharacterBody3D
var breath: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	add_child(boss)
	await get_tree().process_frame
	breath = BreathScript.new()
	boss._register_mechanic(breath)
	await get_tree().process_frame

func test_chill_during_windup_extends_telegraph_per_stack() -> void:
	breath.trigger(1)
	# Apply 2 chill stacks during windup — should add 0.30s to remaining windup
	boss.apply_chill(2)
	# Total expected windup ≈ 1.0 + 0.3 = 1.3s
	# Tick 1.05s; should still be in windup
	for i in range(63):  # 63 frames at 60fps ≈ 1.05s
		await get_tree().physics_frame
	assert_bool(breath.is_in_windup()).is_true()

func test_chill_outside_windup_no_effect() -> void:
	# Apply chill without breath active
	boss.apply_chill(2)
	breath.trigger(1)
	# Tick standard 1.0s windup; should be in execution by now
	for i in range(65):
		await get_tree().physics_frame
	assert_bool(breath.is_in_execution()).is_true()
```

- [ ] **Step 2: Run to verify failure**

Expected: FAIL.

- [ ] **Step 3: Override boss.apply_chill to forward to breath mechanic**

Modify `scripts/entities/boss_dragon.gd` `apply_chill`:

```gdscript
const CHILL_TELEGRAPH_EXTEND_PER_STACK: float = 0.15

func apply_chill(stacks: int) -> void:
	# Chill applied during a breath windup extends the windup per stack
	# (color interaction). The cap on chill stacks below FREEZE_THRESHOLD - 1
	# is preserved (boss CC immunity).
	var prior_stacks: int = _chill_stacks
	_chill_stacks = mini(_chill_stacks + stacks, FREEZE_THRESHOLD - 1)
	var added: int = _chill_stacks - prior_stacks
	apply_slow(SLOW_PER_CHILL_STACK * float(_chill_stacks), 1.0)
	# Forward telegraph extension to any breath mechanic in windup
	for m in _mechanics:
		if not m.has_method("on_chill_applied"):
			continue
		m.on_chill_applied(added)
```

- [ ] **Step 4: Add hook to breath mechanic**

Modify `scripts/entities/boss_mechanics/mechanic_static_breath.gd`:

```gdscript
const CHILL_EXTEND_PER_STACK: float = 0.15

func on_chill_applied(stacks_added: int) -> void:
	if not is_in_windup():
		return
	if stacks_added <= 0:
		return
	extend_windup(CHILL_EXTEND_PER_STACK * float(stacks_added))
```

- [ ] **Step 5: Run tests to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_breath_chill_extends.gd
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```
Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/entities/boss_mechanics/mechanic_static_breath.gd scripts/entities/boss_dragon.gd test/test_breath_chill_extends.gd
git commit -m "feat: blue chill extends boss breath telegraph by 0.15s per stack"
```

---

## Task 12: Purple pull redirects breath cone

**Files:**
- Modify: `scripts/entities/boss_mechanics/mechanic_static_breath.gd`
- Modify: `scripts/entities/boss_dragon.gd` (override apply_pull_toward to forward redirect to breath)
- Test: `test/test_breath_pull_redirect.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_breath_pull_redirect.gd`:

```gdscript
extends GdUnitTestSuite

const BreathScript = preload("res://scripts/entities/boss_mechanics/mechanic_static_breath.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")

var boss: CharacterBody3D
var breath: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	await get_tree().process_frame
	breath = BreathScript.new()
	boss._register_mechanic(breath)
	await get_tree().process_frame

func test_pull_during_windup_rotates_cone_aim() -> void:
	breath.trigger(1)
	breath._aim_dir = Vector3.FORWARD
	# Simulate pull from a point that should rotate the cone direction
	boss.apply_pull_toward(Vector3(2, 0, 1), 1.0)
	var aim: Vector3 = breath.current_aim()
	# Cone aim should have rotated +15° toward +X (right-handed Y-up rotation)
	var expected: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(15.0))
	assert_float(aim.x).is_equal_approx(expected.x, 0.01)
	assert_float(aim.z).is_equal_approx(expected.z, 0.01)

func test_pull_outside_windup_does_not_redirect() -> void:
	breath._aim_dir = Vector3.FORWARD
	boss.apply_pull_toward(Vector3(2, 0, 1), 1.0)
	# Aim unchanged because no windup active
	assert_vector(breath.current_aim()).is_equal_approx(Vector3.FORWARD, Vector3.ONE * 0.01)
```

- [ ] **Step 2: Run to verify failure**

Expected: FAIL.

- [ ] **Step 3: Override apply_pull_toward in boss_dragon**

Modify `scripts/entities/boss_dragon.gd` `apply_pull_toward`:

```gdscript
const CONE_REDIRECT_PER_PULL_DEG: float = 15.0

func apply_pull_toward(target_pos: Vector3, impulse: float) -> void:
	var dir: Vector3 = target_pos - global_position
	dir.y = 0.0
	if dir.length() < 0.001:
		return
	# Forward to any breath mechanic in windup for cone redirect
	for m in _mechanics:
		if not m.has_method("on_pull_during_windup"):
			continue
		m.on_pull_during_windup(target_pos, CONE_REDIRECT_PER_PULL_DEG)
	var effective_impulse: float = impulse / _mass()
	_knockback_velocity += dir.normalized() * effective_impulse
	_clamp_knockback_velocity()
```

- [ ] **Step 4: Add hook to breath mechanic**

Modify `scripts/entities/boss_mechanics/mechanic_static_breath.gd`:

```gdscript
func on_pull_during_windup(pull_origin: Vector3, rotation_deg: float) -> void:
	if not is_in_windup():
		return
	# Rotate aim toward the pull origin's side. Sign: if pull origin is to
	# the right of current aim, rotate +; left, rotate -.
	if _boss == null or not is_instance_valid(_boss):
		return
	var to_pull: Vector3 = pull_origin - _boss.global_position
	to_pull.y = 0.0
	if to_pull.length() < 0.01:
		return
	var aim_2d: Vector2 = Vector2(_aim_dir.x, _aim_dir.z)
	var pull_2d: Vector2 = Vector2(to_pull.x, to_pull.z).normalized()
	var cross_z: float = aim_2d.cross(pull_2d)
	var sign: float = signf(cross_z) if absf(cross_z) > 0.001 else 1.0
	set_aim(_aim_dir.rotated(Vector3.UP, deg_to_rad(rotation_deg) * sign))
```

- [ ] **Step 5: Run tests to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_breath_pull_redirect.gd
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```
Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/entities/boss_mechanics/mechanic_static_breath.gd scripts/entities/boss_dragon.gd test/test_breath_pull_redirect.gd
git commit -m "feat: purple pull redirects boss breath cone by 15° per cast during windup"
```

---

## Task 13: MarkZone effect

**Files:**
- Create: `scripts/effects/effect_mark_zone.gd`
- Create: `scenes/effects/effect_mark_zone.tscn` (Node3D + ring mesh + Area3D)
- Test: `test/test_effect_mark_zone.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_effect_mark_zone.gd`:

```gdscript
extends GdUnitTestSuite

const MarkScene: PackedScene = preload("res://scenes/effects/effect_mark_zone.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

var mark: Node3D
var player: CharacterBody3D

func before_test() -> void:
	mark = auto_free(MarkScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	add_child(mark); mark.global_position = Vector3.ZERO
	add_child(player)
	await get_tree().process_frame

func test_mark_strikes_after_delay() -> void:
	mark.configure(2.0, 0.1, 30)  # 2m radius, 0.1s delay, 30 dmg
	player.global_position = Vector3.ZERO  # in zone
	var initial_hp: int = player.hp
	for i in range(15):
		await get_tree().physics_frame
	assert_int(player.hp).is_less(initial_hp)

func test_mark_does_not_damage_player_outside_zone() -> void:
	mark.configure(2.0, 0.1, 30)
	player.global_position = Vector3(5, 0, 0)
	var initial_hp: int = player.hp
	for i in range(15):
		await get_tree().physics_frame
	assert_int(player.hp).is_equal(initial_hp)

func test_mark_freed_after_strike() -> void:
	mark.configure(2.0, 0.1, 30)
	for i in range(15):
		await get_tree().physics_frame
	assert_bool(is_instance_valid(mark)).is_false()
```

- [ ] **Step 2: Run to verify failure**

Expected: FAIL.

- [ ] **Step 3: Implement mark zone**

Create `scripts/effects/effect_mark_zone.gd`:

```gdscript
extends Node3D

# Mark + delayed strike floor zone. Configures with radius, delay, damage.
# Strike lands at position the mark was placed (2.5s ago). Visual ring
# fills/grows during delay; at delay end, damages players in radius and frees.

@export var radius: float = 2.0
@export var delay: float = 2.5
@export var damage: int = 30

var _age: float = 0.0
var _struck: bool = false

# Optional callable for wall-absorb interaction. Returns true if a wall
# absorbed the strike (no player damage applied).
var wall_absorb_check: Callable = Callable()

func configure(p_radius: float, p_delay: float, p_damage: int) -> void:
	radius = p_radius
	delay = p_delay
	damage = p_damage
	add_to_group("mark_zone")
	# Resize visual mesh to match radius
	var mesh: MeshInstance3D = get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null:
		mesh.scale = Vector3.ONE * (radius / 2.0)

func _process(delta: float) -> void:
	_age += delta
	# Update visual fill (grow ring)
	var mesh: MeshInstance3D = get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null and mesh.material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = mesh.material_override
		mat.albedo_color.a = clampf(_age / delay, 0.2, 0.9)
	if _age >= delay and not _struck:
		_struck = true
		_strike()
		queue_free()

func _strike() -> void:
	# Wall-absorb interaction (white wall in radius absorbs damage)
	if wall_absorb_check.is_valid() and wall_absorb_check.call(global_position, radius, damage):
		return
	var players: Array = get_tree().get_nodes_in_group("player")
	for p in players:
		if not is_instance_valid(p):
			continue
		if p.global_position.distance_to(global_position) <= radius:
			if p.has_method("take_damage"):
				p.take_damage(damage)
	ScreenShake.shake(0.06, 0.12)
```

Create `scenes/effects/effect_mark_zone.tscn`:

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/effects/effect_mark_zone.gd" id="1"]

[sub_resource type="StandardMaterial3D" id="mat_mark"]
albedo_color = Color(1, 0.1, 0.1, 0.3)
transparency = 1
emission_enabled = true
emission = Color(1, 0.1, 0.1, 1)
emission_energy_multiplier = 1.5

[sub_resource type="CylinderMesh" id="mesh_mark"]
top_radius = 2.0
bottom_radius = 2.0
height = 0.05
material = SubResource("mat_mark")

[node name="EffectMarkZone" type="Node3D"]
script = ExtResource("1")

[node name="Mesh" type="MeshInstance3D" parent="."]
mesh = SubResource("mesh_mark")
```

- [ ] **Step 4: Run to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_effect_mark_zone.gd
```
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/effects/effect_mark_zone.gd scenes/effects/effect_mark_zone.tscn test/test_effect_mark_zone.gd
git commit -m "feat: mark zone effect with delayed strike + wall-absorb hook"
```

---

## Task 14: Mark + delayed strike mechanic (P1)

**Files:**
- Create: `scripts/entities/boss_mechanics/mechanic_mark.gd`
- Modify: `scripts/entities/boss_dragon.gd` (register)
- Test: `test/test_mechanic_mark.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_mechanic_mark.gd`:

```gdscript
extends GdUnitTestSuite

const MarkMechanic = preload("res://scripts/entities/boss_mechanics/mechanic_mark.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

var boss: CharacterBody3D
var player: CharacterBody3D
var mark: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	add_child(player); player.global_position = Vector3(3, 0, 0)
	await get_tree().process_frame
	mark = MarkMechanic.new()
	boss._register_mechanic(mark)
	await get_tree().process_frame

func test_mark_spawns_at_player_position_at_trigger() -> void:
	mark.trigger(1)
	await get_tree().process_frame
	var marks: Array = get_tree().get_nodes_in_group("mark_zone")
	assert_int(marks.size()).is_equal(1)
	assert_vector(marks[0].global_position).is_equal_approx(Vector3(3, 0, 0), Vector3.ONE * 0.1)

func test_mark_strikes_player_if_still_in_zone_after_delay() -> void:
	var initial_hp: int = player.hp
	mark.trigger(1)
	# Wait through 2.5s delay
	for i in range(180):
		await get_tree().physics_frame
	assert_int(player.hp).is_less(initial_hp)

func test_mark_does_not_strike_player_who_moved_out() -> void:
	mark.trigger(1)
	await get_tree().process_frame
	player.global_position = Vector3(20, 0, 0)
	await get_tree().process_frame
	var initial_hp: int = player.hp
	for i in range(180):
		await get_tree().physics_frame
	assert_int(player.hp).is_equal(initial_hp)
```

- [ ] **Step 2: Run to verify failure**

Expected: FAIL.

- [ ] **Step 3: Implement mark mechanic**

Create `scripts/entities/boss_mechanics/mechanic_mark.gd`:

```gdscript
extends BossMechanic

const MarkScene: PackedScene = preload("res://scenes/effects/effect_mark_zone.tscn")
const RADIUS: float = 2.0
const DELAY: float = 2.5
const DAMAGE: int = 30

func _init() -> void:
	unlock_phase = 1
	is_big = true
	cooldowns_by_phase = {1: 10.0, 2: 8.0, 3: 6.0}
	windup_duration = 0.05  # mark placement is "instant" relative to player perception
	execution_duration = 0.0

func _on_execution_start() -> void:
	# Place mark at player's current position
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var p: Node = players[0]
	if not is_instance_valid(p):
		return
	var mark_zone: Node3D = MarkScene.instantiate()
	_boss.get_parent().add_child(mark_zone)
	mark_zone.global_position = p.global_position
	mark_zone.configure(RADIUS, DELAY, DAMAGE)
```

- [ ] **Step 4: Register in boss_dragon**

Modify `scripts/entities/boss_dragon.gd`:

```gdscript
const MechanicMark = preload("res://scripts/entities/boss_mechanics/mechanic_mark.gd")

# In _ready, after other mechanic registrations:
_register_mechanic(MechanicMark.new())
```

- [ ] **Step 5: Run tests to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_mechanic_mark.gd
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```
Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/entities/boss_mechanics/mechanic_mark.gd scripts/entities/boss_dragon.gd test/test_mechanic_mark.gd
git commit -m "feat: boss mark + delayed strike mechanic (P1, 2.5s delay, 30 dmg, 2m AoE)"
```

---

## Task 15: White wall absorbs mark strike

**Files:**
- Modify: `scripts/entities/boss_mechanics/mechanic_mark.gd`
- Test: `test/test_mark_wall_absorb.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_mark_wall_absorb.gd`:

```gdscript
extends GdUnitTestSuite

const MarkMechanic = preload("res://scripts/entities/boss_mechanics/mechanic_mark.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")
const WallScene: PackedScene = preload("res://scenes/effects/effect_bone_wall.tscn")

var boss: CharacterBody3D
var player: CharacterBody3D
var wall: StaticBody3D
var mark: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	wall = auto_free(WallScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	add_child(player); player.global_position = Vector3(3, 0, 0)
	add_child(wall); wall.global_position = Vector3(3, 0, 0)
	wall.configure(30, 5.0, 4.0)
	await get_tree().process_frame
	mark = MarkMechanic.new()
	boss._register_mechanic(mark)
	await get_tree().process_frame

func test_wall_in_mark_zone_absorbs_strike() -> void:
	var initial_hp: int = player.hp
	var initial_wall_hp: int = wall.hp
	mark.trigger(1)
	for i in range(180):
		await get_tree().physics_frame
	assert_int(player.hp).is_equal(initial_hp)  # absorbed
	# Wall took the 30 damage and is likely destroyed
	if is_instance_valid(wall):
		assert_int(wall.hp).is_less(initial_wall_hp)
```

- [ ] **Step 2: Run to verify failure**

Expected: FAIL.

- [ ] **Step 3: Wire wall-absorb in mark mechanic**

Modify `scripts/entities/boss_mechanics/mechanic_mark.gd` `_on_execution_start`:

```gdscript
func _on_execution_start() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var p: Node = players[0]
	if not is_instance_valid(p):
		return
	var mark_zone: Node3D = MarkScene.instantiate()
	_boss.get_parent().add_child(mark_zone)
	mark_zone.global_position = p.global_position
	mark_zone.configure(RADIUS, DELAY, DAMAGE)
	mark_zone.wall_absorb_check = func(pos: Vector3, r: float, dmg: int) -> bool:
		return _wall_absorbs_at(pos, r, dmg)

func _wall_absorbs_at(pos: Vector3, radius: float, dmg: int) -> bool:
	var walls: Array = get_tree().get_nodes_in_group("bone_wall")
	for w in walls:
		if not is_instance_valid(w):
			continue
		if w.global_position.distance_to(pos) <= radius:
			if w.has_method("take_damage"):
				w.take_damage(dmg)
			return true
	return false
```

- [ ] **Step 4: Run tests to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_mark_wall_absorb.gd
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/entities/boss_mechanics/mechanic_mark.gd test/test_mark_wall_absorb.gd
git commit -m "feat: white wall absorbs mark strike if in zone at impact"
```

---

## Task 16: Conditional jump mechanic

**Files:**
- Create: `scripts/entities/boss_mechanics/mechanic_jump.gd`
- Modify: `scripts/entities/boss_dragon.gd` (register, position-history tracking, damage tracking)
- Test: `test/test_mechanic_jump.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_mechanic_jump.gd`:

```gdscript
extends GdUnitTestSuite

const JumpMechanic = preload("res://scripts/entities/boss_mechanics/mechanic_jump.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")

var boss: CharacterBody3D
var jump: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	await get_tree().process_frame
	jump = JumpMechanic.new()
	boss._register_mechanic(jump)
	await get_tree().process_frame

func test_jump_does_not_trigger_when_boss_moving() -> void:
	# Manually update position history to show movement
	boss._record_position_history(Vector3.ZERO)
	for i in range(60):
		boss.global_position = Vector3(i * 0.05, 0, 0)
		boss._record_position_history(boss.global_position)
		await get_tree().physics_frame
	# Even with damage taken, no jump because boss has moved
	boss._record_damage_taken(30)
	assert_bool(jump._should_trigger()).is_false()

func test_jump_triggers_when_stationary_and_taking_damage() -> void:
	# Force position to be unchanged for >2s and damage taken
	boss.global_position = Vector3.ZERO
	for i in range(130):
		boss._record_position_history(Vector3.ZERO)
		await get_tree().physics_frame
	boss._record_damage_taken(30)
	assert_bool(jump._should_trigger()).is_true()

func test_jump_min_3s_gap_between_jumps() -> void:
	jump._last_jump_time_msec = Time.get_ticks_msec()
	boss.global_position = Vector3.ZERO
	for i in range(130):
		boss._record_position_history(Vector3.ZERO)
		await get_tree().physics_frame
	boss._record_damage_taken(30)
	# Within 3s of last jump → should not trigger
	assert_bool(jump._should_trigger()).is_false()
```

- [ ] **Step 2: Run to verify failure**

Expected: FAIL.

- [ ] **Step 3: Add position/damage history to boss_dragon**

Modify `scripts/entities/boss_dragon.gd`. Add:

```gdscript
const POSITION_HISTORY_WINDOW: float = 2.0
const POSITION_HISTORY_INTERVAL: float = 0.1

var _position_history: Array[Dictionary] = []  # [{time_msec: int, pos: Vector3}, ...]
var _damage_in_window_msec: int = 0  # last time damage was taken
var _position_history_timer: float = 0.0

func _record_position_history(pos: Vector3) -> void:
	var now_msec: int = Time.get_ticks_msec()
	_position_history.append({"time_msec": now_msec, "pos": pos})
	# Drop entries older than window
	var cutoff_msec: int = now_msec - int(POSITION_HISTORY_WINDOW * 1000.0)
	while not _position_history.is_empty() and _position_history[0].time_msec < cutoff_msec:
		_position_history.pop_front()

func _record_damage_taken(_amt: int) -> void:
	_damage_in_window_msec = Time.get_ticks_msec()

func position_change_in_window() -> float:
	if _position_history.size() < 2:
		return 0.0
	var first: Vector3 = _position_history[0].pos
	var last: Vector3 = _position_history[-1].pos
	return first.distance_to(last)

func damage_taken_within(window_seconds: float) -> bool:
	var cutoff_msec: int = Time.get_ticks_msec() - int(window_seconds * 1000.0)
	return _damage_in_window_msec >= cutoff_msec
```

In `_physics_process`, sample position history every POSITION_HISTORY_INTERVAL:

```gdscript
_position_history_timer += delta
if _position_history_timer >= POSITION_HISTORY_INTERVAL:
	_position_history_timer = 0.0
	_record_position_history(global_position)
```

In `take_damage`, after applying damage:

```gdscript
_record_damage_taken(actual)
```

- [ ] **Step 4: Implement jump mechanic**

Create `scripts/entities/boss_mechanics/mechanic_jump.gd`:

```gdscript
extends BossMechanic

# Conditional jump: triggered (not cooldowned) when boss is stationary
# while taking damage. Counters DoT-park strategy. Boss leaps to a new
# random valid position.

const STATIONARY_THRESHOLD_M: float = 1.0
const STATIONARY_WINDOW_S: float = 2.0
const MIN_GAP_S: float = 3.0
const MIN_HOP_DISTANCE: float = 4.0
const MAX_HOP_DISTANCE: float = 8.0
const LAND_DAMAGE: int = 15
const LAND_RADIUS: float = 1.0

var _last_jump_time_msec: int = -10000
var _jump_target: Vector3 = Vector3.ZERO

func _init() -> void:
	unlock_phase = 1
	is_big = false  # bypasses mutual exclusivity
	cooldowns_by_phase = {1: 0.5, 2: 0.5, 3: 0.5}  # check rate, not real cooldown
	windup_duration = 1.0
	execution_duration = 0.6

func tick(delta: float, current_phase: int) -> void:
	super.tick(delta, current_phase)
	# Trigger check independent of normal scheduler
	if _telegraph.state == BossTelegraph.State.IDLE and _cooldown_remaining <= 0.0:
		if _should_trigger():
			trigger(current_phase)
		else:
			_cooldown_remaining = 0.5  # re-check in 0.5s

func _should_trigger() -> bool:
	if _boss == null or not is_instance_valid(_boss):
		return false
	if Time.get_ticks_msec() - _last_jump_time_msec < int(MIN_GAP_S * 1000.0):
		return false
	if _boss.position_change_in_window() >= STATIONARY_THRESHOLD_M:
		return false
	if not _boss.damage_taken_within(STATIONARY_WINDOW_S):
		return false
	return true

func _on_windup_start() -> void:
	# Choose landing target
	var angle: float = randf() * TAU
	var dist: float = randf_range(MIN_HOP_DISTANCE, MAX_HOP_DISTANCE)
	_jump_target = _boss.global_position + Vector3(cos(angle) * dist, 0, sin(angle) * dist)

func _on_execution_start() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	_boss.global_position = _jump_target
	# Damage at landing
	var players: Array = get_tree().get_nodes_in_group("player")
	for p in players:
		if not is_instance_valid(p):
			continue
		if p.global_position.distance_to(_jump_target) <= LAND_RADIUS:
			if p.has_method("take_damage"):
				p.take_damage(LAND_DAMAGE)
	_last_jump_time_msec = Time.get_ticks_msec()
	ScreenShake.shake(0.04, 0.1)
```

- [ ] **Step 5: Register in boss_dragon**

```gdscript
const MechanicJump = preload("res://scripts/entities/boss_mechanics/mechanic_jump.gd")

# In _ready:
_register_mechanic(MechanicJump.new())
```

- [ ] **Step 6: Run tests to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_mechanic_jump.gd
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```
Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add scripts/entities/boss_mechanics/mechanic_jump.gd scripts/entities/boss_dragon.gd test/test_mechanic_jump.gd
git commit -m "feat: boss conditional jump (anti-DoT-park, triggered when stationary + taking damage)"
```

---

## Task 17: Wall break-through (boss walking damages walls)

**Files:**
- Modify: `scripts/entities/boss_dragon.gd`
- Test: `test/test_boss_wall_breakthrough.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_boss_wall_breakthrough.gd`:

```gdscript
extends GdUnitTestSuite

const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const WallScene: PackedScene = preload("res://scenes/effects/effect_bone_wall.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

var boss: CharacterBody3D
var wall: StaticBody3D
var player: CharacterBody3D

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	wall = auto_free(WallScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	add_child(wall); wall.global_position = Vector3(0, 0, 1.5)
	wall.configure(30, 10.0, 4.0)
	add_child(player); player.global_position = Vector3(0, 0, 5)
	await get_tree().process_frame

func test_walking_boss_damages_overlapping_wall() -> void:
	# Move boss into wall manually for several frames
	boss.global_position = Vector3(0, 0, 1.5)
	var initial_wall_hp: int = wall.hp
	for i in range(60):
		await get_tree().physics_frame
	if is_instance_valid(wall):
		assert_int(wall.hp).is_less(initial_wall_hp)
```

- [ ] **Step 2: Run to verify failure**

Expected: FAIL.

- [ ] **Step 3: Implement wall break-through in boss_dragon**

Modify `scripts/entities/boss_dragon.gd`. Add to `_physics_process` (after movement):

```gdscript
const WALL_CONTACT_DAMAGE_PER_SECOND: int = 10
const WALL_CONTACT_SLOW_PCT: float = 0.3

var _wall_contact_residual: float = 0.0

func _apply_wall_contact_damage(delta: float) -> void:
	var walls: Array = get_tree().get_nodes_in_group("bone_wall")
	var slowed: bool = false
	for w in walls:
		if not is_instance_valid(w):
			continue
		if global_position.distance_to(w.global_position) <= 1.0:
			# Walking through wall
			_wall_contact_residual += float(WALL_CONTACT_DAMAGE_PER_SECOND) * delta
			var integer_dmg: int = int(_wall_contact_residual)
			if integer_dmg > 0:
				_wall_contact_residual -= float(integer_dmg)
				if w.has_method("take_damage"):
					w.take_damage(integer_dmg)
			slowed = true
	# Apply walking slow if in contact
	if slowed:
		velocity.x *= (1.0 - WALL_CONTACT_SLOW_PCT)
		velocity.z *= (1.0 - WALL_CONTACT_SLOW_PCT)
```

Call `_apply_wall_contact_damage(delta)` in `_physics_process` just before `move_and_slide()`.

- [ ] **Step 4: Run tests to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_boss_wall_breakthrough.gd
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/entities/boss_dragon.gd test/test_boss_wall_breakthrough.gd
git commit -m "feat: walking boss damages overlapping walls + slows by 30% during contact"
```

---

## Task 18: Sweeping breath mechanic (P2 unlock)

**Files:**
- Create: `scripts/entities/boss_mechanics/mechanic_sweeping_breath.gd`
- Modify: `scripts/entities/boss_dragon.gd` (register)
- Test: `test/test_mechanic_sweeping_breath.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_mechanic_sweeping_breath.gd`:

```gdscript
extends GdUnitTestSuite

const SweepScript = preload("res://scripts/entities/boss_mechanics/mechanic_sweeping_breath.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

var boss: CharacterBody3D
var player: CharacterBody3D
var sweep: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	add_child(player); player.global_position = Vector3(0, 0, 3)
	await get_tree().process_frame
	sweep = SweepScript.new()
	boss._register_mechanic(sweep)
	await get_tree().process_frame

func test_timings() -> void:
	assert_float(sweep.windup_duration).is_equal_approx(0.8, 0.001)
	assert_float(sweep.execution_duration).is_equal_approx(2.0, 0.001)

func test_unlocked_phase_2() -> void:
	assert_int(sweep.unlock_phase).is_equal(2)
	assert_bool(sweep.is_ready(1)).is_false()

func test_sweep_damages_player_in_path() -> void:
	# Force phase 2 in boss for ready check
	boss._phase = 2
	var initial_hp: int = player.hp
	sweep.trigger(2)
	for i in range(180):  # ~3s
		await get_tree().physics_frame
	assert_int(player.hp).is_less(initial_hp)
```

- [ ] **Step 2: Run to verify failure**

Expected: FAIL.

- [ ] **Step 3: Implement sweeping breath**

Create `scripts/entities/boss_mechanics/mechanic_sweeping_breath.gd`:

```gdscript
extends BossMechanic

const BreathConeScene: PackedScene = preload("res://scenes/effects/effect_breath_cone.tscn")
const CONE_LENGTH: float = 5.0
const CONE_ANGLE_DEG: float = 60.0
const TICK_DAMAGE: int = 15
const SWEEP_TOTAL_DEG: float = 90.0

var _cone: Node3D = null
var _aim_dir: Vector3 = Vector3.FORWARD
var _sweep_dir_sign: float = 1.0  # +1 CW, -1 CCW
var _sweep_progress: float = 0.0  # 0..1 across execution

func _init() -> void:
	unlock_phase = 2
	is_big = true
	cooldowns_by_phase = {1: 999.0, 2: 12.0, 3: 8.0}
	windup_duration = 0.8
	execution_duration = 2.0

func _on_windup_start() -> void:
	# Lock initial aim toward player; pick random sweep direction
	var players: Array = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		var p: Node = players[0]
		var to_p: Vector3 = p.global_position - _boss.global_position
		to_p.y = 0.0
		if to_p.length() > 0.01:
			_aim_dir = to_p.normalized()
	# Start aim at -45° from player to sweep across through to +45°
	_sweep_dir_sign = 1.0 if randf() < 0.5 else -1.0
	_aim_dir = _aim_dir.rotated(Vector3.UP, deg_to_rad(SWEEP_TOTAL_DEG * 0.5 * -_sweep_dir_sign))
	_sweep_progress = 0.0

func _on_execution_start() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	_cone = BreathConeScene.instantiate()
	_boss.get_parent().add_child(_cone)
	_cone.configure(_boss.global_position, _aim_dir, CONE_LENGTH, CONE_ANGLE_DEG, execution_duration, TICK_DAMAGE)
	_cone.blocking_walls_check = func(target_pos: Vector3) -> bool:
		return _segment_blocked_by_wall(_boss.global_position, target_pos)
	_cone.blocking_clouds_check = func(target_pos: Vector3) -> bool:
		return _segment_blocked_by_cloud(_boss.global_position, target_pos)

func tick(delta: float, current_phase: int) -> void:
	super.tick(delta, current_phase)
	if is_in_execution() and _cone != null and is_instance_valid(_cone):
		_sweep_progress += delta / execution_duration
		var current_angle_offset: float = SWEEP_TOTAL_DEG * (_sweep_progress - 0.5) * _sweep_dir_sign
		var base_aim: Vector3 = _aim_dir.rotated(Vector3.UP, deg_to_rad(SWEEP_TOTAL_DEG * 0.5 * _sweep_dir_sign))
		var live_aim: Vector3 = base_aim.rotated(Vector3.UP, deg_to_rad(current_angle_offset))
		_cone.set_direction(live_aim)
		_cone.global_position = _boss.global_position

func _segment_blocked_by_wall(from: Vector3, to: Vector3) -> bool:
	var walls: Array = get_tree().get_nodes_in_group("bone_wall")
	for w in walls:
		if not is_instance_valid(w):
			continue
		if w.has_method("blocks_segment") and w.blocks_segment(from, to):
			if w.has_method("take_damage"):
				w.take_damage(1)
			return true
	return false

func _segment_blocked_by_cloud(from: Vector3, to: Vector3) -> bool:
	var clouds: Array = get_tree().get_nodes_in_group("damage_cloud")
	for c in clouds:
		if not is_instance_valid(c):
			continue
		if c.has_method("blocks_segment") and c.blocks_segment(from, to):
			return true
	return false

const CHILL_EXTEND_PER_STACK: float = 0.15

func on_chill_applied(stacks_added: int) -> void:
	if not is_in_windup():
		return
	if stacks_added <= 0:
		return
	extend_windup(CHILL_EXTEND_PER_STACK * float(stacks_added))

func on_pull_during_windup(pull_origin: Vector3, rotation_deg: float) -> void:
	if not is_in_windup():
		return
	if _boss == null or not is_instance_valid(_boss):
		return
	var to_pull: Vector3 = pull_origin - _boss.global_position
	to_pull.y = 0.0
	if to_pull.length() < 0.01:
		return
	var aim_2d: Vector2 = Vector2(_aim_dir.x, _aim_dir.z)
	var pull_2d: Vector2 = Vector2(to_pull.x, to_pull.z).normalized()
	var cross_z: float = aim_2d.cross(pull_2d)
	var sign: float = signf(cross_z) if absf(cross_z) > 0.001 else 1.0
	_aim_dir = _aim_dir.rotated(Vector3.UP, deg_to_rad(rotation_deg) * sign)
```

- [ ] **Step 4: Register in boss_dragon**

```gdscript
const MechanicSweepingBreath = preload("res://scripts/entities/boss_mechanics/mechanic_sweeping_breath.gd")

# In _ready:
_register_mechanic(MechanicSweepingBreath.new())
```

- [ ] **Step 5: Run tests to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_mechanic_sweeping_breath.gd
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```
Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/entities/boss_mechanics/mechanic_sweeping_breath.gd scripts/entities/boss_dragon.gd test/test_mechanic_sweeping_breath.gd
git commit -m "feat: boss sweeping breath mechanic (P2+, 90° arc, random CW/CCW direction)"
```

---

## Task 19: Armor wings mechanic (P2 unlock)

**Files:**
- Create: `scripts/entities/boss_mechanics/mechanic_armor_wings.gd`
- Modify: `scripts/entities/boss_dragon.gd` (register, integrate reduction in take_damage)
- Test: `test/test_mechanic_armor_wings.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_mechanic_armor_wings.gd`:

```gdscript
extends GdUnitTestSuite

const ArmorWingsScript = preload("res://scripts/entities/boss_mechanics/mechanic_armor_wings.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")

var boss: CharacterBody3D
var wings: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	add_child(boss)
	await get_tree().process_frame
	wings = ArmorWingsScript.new()
	boss._register_mechanic(wings)
	await get_tree().process_frame

func test_timings() -> void:
	assert_float(wings.windup_duration).is_equal_approx(0.5, 0.001)
	assert_float(wings.execution_duration).is_equal_approx(4.0, 0.001)

func test_unlocked_phase_2() -> void:
	assert_int(wings.unlock_phase).is_equal(2)

func test_active_reduction_starts_at_60_pct() -> void:
	wings.trigger(2)
	# Skip past windup
	for i in range(40):
		await get_tree().physics_frame
	assert_float(wings.current_reduction_pct()).is_equal_approx(0.6, 0.05)

func test_reduction_decays_to_zero() -> void:
	wings.trigger(2)
	# Skip past windup + execution
	for i in range(280):
		await get_tree().physics_frame
	assert_float(wings.current_reduction_pct()).is_equal_approx(0.0, 0.001)

func test_boss_take_damage_applies_reduction_during_active_window() -> void:
	wings.trigger(2)
	for i in range(40):
		await get_tree().physics_frame
	# Boss now has ~60% reduction. Try to deal 100 damage; should apply ~40 (subject to cap)
	var hp_before: int = boss.hp
	boss.take_damage(100)
	var dmg_taken: int = hp_before - boss.hp
	# Cap is 15 — so even after reduction (40), cap dominates
	assert_int(dmg_taken).is_less_equal(15)
```

- [ ] **Step 2: Run to verify failure**

Expected: FAIL.

- [ ] **Step 3: Implement armor wings**

Create `scripts/entities/boss_mechanics/mechanic_armor_wings.gd`:

```gdscript
extends BossMechanic

const REDUCTION_START: float = 0.6

var _active_remaining: float = 0.0
var _active_total: float = 0.0

func _init() -> void:
	unlock_phase = 2
	is_big = true
	cooldowns_by_phase = {1: 999.0, 2: 20.0, 3: 15.0}
	windup_duration = 0.5
	execution_duration = 4.0

func _on_execution_start() -> void:
	_active_remaining = execution_duration
	_active_total = execution_duration

func tick(delta: float, current_phase: int) -> void:
	super.tick(delta, current_phase)
	if _active_remaining > 0.0:
		_active_remaining = max(0.0, _active_remaining - delta)

func current_reduction_pct() -> float:
	if _active_remaining <= 0.0 or _active_total <= 0.0:
		return 0.0
	var t: float = _active_remaining / _active_total  # 1.0 → 0.0
	return REDUCTION_START * t

func is_active() -> bool:
	return _active_remaining > 0.0
```

- [ ] **Step 4: Integrate reduction in boss_dragon.take_damage**

Modify `scripts/entities/boss_dragon.gd` `take_damage`:

```gdscript
func take_damage(amount: int) -> void:
	if _is_dead:
		return
	# Apply armor wings reduction before cap
	var reduction: float = _armor_wings_reduction()
	if reduction > 0.0:
		amount = int(float(amount) * (1.0 - reduction))
	# Cap damage taken per DMG_TICK_INTERVAL
	var allowed: int = max(0, DMG_CAP_PER_TICK - _dmg_taken_this_tick)
	var actual: int = min(amount, allowed)
	_dmg_taken_this_tick += actual
	hp = max(0, hp - actual)
	_record_damage_taken(actual)
	_check_phase_transition()
	if hp == 0:
		_is_dead = true
		DamageMeter.dump_log()
		DamageMeter.stop()
		# ... existing death logic preserved ...

func _armor_wings_reduction() -> float:
	for m in _mechanics:
		if m.has_method("current_reduction_pct"):
			var r: float = m.current_reduction_pct()
			if r > 0.0:
				return r
	return 0.0
```

- [ ] **Step 5: Register in boss_dragon**

```gdscript
const MechanicArmorWings = preload("res://scripts/entities/boss_mechanics/mechanic_armor_wings.gd")

# In _ready:
_register_mechanic(MechanicArmorWings.new())
```

- [ ] **Step 6: Run tests to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_mechanic_armor_wings.gd
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```
Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add scripts/entities/boss_mechanics/mechanic_armor_wings.gd scripts/entities/boss_dragon.gd test/test_mechanic_armor_wings.gd
git commit -m "feat: boss armor wings (P2+, 60% reduction decaying to 0% over 4s)"
```

---

## Task 20: Red burn pierces armor wings

**Files:**
- Modify: `scripts/entities/boss_dragon.gd`
- Test: `test/test_burn_pierces_wings.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_burn_pierces_wings.gd`:

```gdscript
extends GdUnitTestSuite

const ArmorWingsScript = preload("res://scripts/entities/boss_mechanics/mechanic_armor_wings.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")

var boss: CharacterBody3D
var wings: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	add_child(boss)
	await get_tree().process_frame
	wings = ArmorWingsScript.new()
	boss._register_mechanic(wings)
	await get_tree().process_frame

func test_burn_damage_ignores_wing_reduction() -> void:
	# Apply burn from the source-tagged path that should pierce
	wings.trigger(2)
	for i in range(40):  # past windup, ~60% reduction active
		await get_tree().physics_frame
	var hp_before: int = boss.hp
	# Burn-tagged take_damage routes through pierce path
	boss.take_damage_with_source(10, "burn")
	# Expect ~10 actual (subject to cap, which is 15 per 0.5s — fits)
	assert_int(hp_before - boss.hp).is_equal(10)

func test_non_burn_damage_still_reduced() -> void:
	wings.trigger(2)
	for i in range(40):
		await get_tree().physics_frame
	var hp_before: int = boss.hp
	boss.take_damage_with_source(10, "fireball")
	# Reduction applied: 10 * 0.4 = 4 actual
	assert_int(hp_before - boss.hp).is_equal(4)
```

- [ ] **Step 2: Run to verify failure**

Expected: FAIL — `take_damage_with_source` not defined.

- [ ] **Step 3: Add source-aware take_damage**

Modify `scripts/entities/boss_dragon.gd`:

```gdscript
func take_damage(amount: int) -> void:
	take_damage_with_source(amount, "")

func take_damage_with_source(amount: int, source_tag: String) -> void:
	if _is_dead:
		return
	# Burn pierces armor wings reduction; everything else is reduced.
	var reduction: float = _armor_wings_reduction()
	if reduction > 0.0 and source_tag != "burn":
		amount = int(float(amount) * (1.0 - reduction))
	var allowed: int = max(0, DMG_CAP_PER_TICK - _dmg_taken_this_tick)
	var actual: int = min(amount, allowed)
	_dmg_taken_this_tick += actual
	hp = max(0, hp - actual)
	_record_damage_taken(actual)
	_check_phase_transition()
	if hp == 0:
		_is_dead = true
		DamageMeter.dump_log()
		DamageMeter.stop()
		# ... existing death logic
```

(Death-block content remains unchanged — only the entry function gates by source tag.)

Update the burn-tick block in `_tick_status_effects` to use the new function:

```gdscript
if burn_dmg > 0:
	_burn_residual -= float(burn_dmg)
	if not _is_dead:
		var hp_before: int = hp
		take_damage_with_source(burn_dmg, "burn")
		DamageMeter.record(self, burn_dmg, hp_before - hp, "burn")
```

- [ ] **Step 4: Update DamagePipeline to forward source_tag**

Modify `scripts/skills/damage_pipeline.gd`. Change the `target.take_damage(damage)` line to:

```gdscript
if target.has_method("take_damage_with_source"):
	target.take_damage_with_source(damage, meter_tag)
else:
	target.take_damage(damage)
```

- [ ] **Step 5: Run tests to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_burn_pierces_wings.gd
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```
Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/entities/boss_dragon.gd scripts/skills/damage_pipeline.gd test/test_burn_pierces_wings.gd
git commit -m "feat: red burn DoT pierces armor wings reduction (cap still applies)"
```

---

## Task 21: Charge mechanic (P3 unlock)

**Files:**
- Create: `scripts/entities/boss_mechanics/mechanic_charge.gd`
- Create: `scripts/effects/effect_charge_indicator.gd` + scene
- Modify: `scripts/entities/boss_dragon.gd` (register)
- Test: `test/test_mechanic_charge.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_mechanic_charge.gd`:

```gdscript
extends GdUnitTestSuite

const ChargeScript = preload("res://scripts/entities/boss_mechanics/mechanic_charge.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

var boss: CharacterBody3D
var player: CharacterBody3D
var charge: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	add_child(player); player.global_position = Vector3(0, 0, 5)
	await get_tree().process_frame
	charge = ChargeScript.new()
	boss._register_mechanic(charge)
	await get_tree().process_frame

func test_timings() -> void:
	assert_float(charge.windup_duration).is_equal_approx(1.4, 0.001)
	assert_float(charge.execution_duration).is_equal_approx(1.5, 0.001)

func test_unlocked_phase_3() -> void:
	assert_int(charge.unlock_phase).is_equal(3)

func test_charge_damages_player_in_path() -> void:
	boss._phase = 3
	var initial_hp: int = player.hp
	charge.trigger(3)
	for i in range(180):
		await get_tree().physics_frame
	assert_int(player.hp).is_less(initial_hp)

func test_charge_locks_direction_at_telegraph_start() -> void:
	boss._phase = 3
	charge.trigger(3)
	await get_tree().process_frame  # windup begins
	var initial_dir: Vector3 = charge._charge_dir
	# Move player; direction should not update
	player.global_position = Vector3(10, 0, 0)
	await get_tree().process_frame
	assert_vector(charge._charge_dir).is_equal_approx(initial_dir, Vector3.ONE * 0.001)
```

- [ ] **Step 2: Run to verify failure**

Expected: FAIL.

- [ ] **Step 3: Implement charge**

Create `scripts/entities/boss_mechanics/mechanic_charge.gd`:

```gdscript
extends BossMechanic

const CHARGE_DAMAGE: int = 60
const CHARGE_HIT_RADIUS: float = 1.5
const CHARGE_BASE_VELOCITY: float = 12.0  # m/s during execution
const CHARGE_DISTANCE: float = 12.0

var _charge_dir: Vector3 = Vector3.FORWARD
var _charge_origin: Vector3 = Vector3.ZERO
var _executed_distance: float = 0.0
var _hit_player_this_charge: bool = false
var _velocity_modifier: float = 1.0  # 1.0 = full speed; reduced by chill stacks
var _walls_in_path: Array[Node] = []
var _stunned_remaining: float = 0.0

func _init() -> void:
	unlock_phase = 3
	is_big = true
	cooldowns_by_phase = {1: 999.0, 2: 999.0, 3: 12.0}
	windup_duration = 1.4
	execution_duration = 1.5

func _on_windup_start() -> void:
	# Lock direction at telegraph start
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		_charge_dir = Vector3.FORWARD
		return
	var p: Node = players[0]
	var to_p: Vector3 = p.global_position - _boss.global_position
	to_p.y = 0.0
	if to_p.length() > 0.01:
		_charge_dir = to_p.normalized()
	_velocity_modifier = 1.0
	_hit_player_this_charge = false

func _on_execution_start() -> void:
	_charge_origin = _boss.global_position
	_executed_distance = 0.0
	_walls_in_path = []

func tick(delta: float, current_phase: int) -> void:
	super.tick(delta, current_phase)
	if not is_in_execution():
		return
	if _stunned_remaining > 0.0:
		_stunned_remaining = max(0.0, _stunned_remaining - delta)
		return
	# Move boss along charge direction
	var step: float = CHARGE_BASE_VELOCITY * _velocity_modifier * delta
	if _executed_distance + step > CHARGE_DISTANCE:
		step = CHARGE_DISTANCE - _executed_distance
	_executed_distance += step
	_boss.global_position += _charge_dir * step
	# Wall collision check
	_check_wall_collisions()
	# Player damage check
	_check_player_hit()
	# Stop if reached distance
	if _executed_distance >= CHARGE_DISTANCE:
		# Force telegraph to end early by ticking the timer remainder
		pass

func _check_wall_collisions() -> void:
	var walls: Array = get_tree().get_nodes_in_group("bone_wall")
	for w in walls:
		if not is_instance_valid(w):
			continue
		if w in _walls_in_path:
			continue
		if _boss.global_position.distance_to(w.global_position) <= 1.0:
			_walls_in_path.append(w)
			# 2+ walls = stop charge, stun 1s
			if _walls_in_path.size() >= 2:
				_velocity_modifier = 0.0
				_stunned_remaining = 1.0
				for ww in _walls_in_path:
					if is_instance_valid(ww) and ww.has_method("take_damage"):
						ww.take_damage(100)  # destroy
				_walls_in_path = []
			else:
				# 1 wall: slow charge by 50%, destroy wall
				_velocity_modifier *= 0.5
				if w.has_method("take_damage"):
					w.take_damage(100)

func _check_player_hit() -> void:
	if _hit_player_this_charge:
		return
	var players: Array = get_tree().get_nodes_in_group("player")
	for p in players:
		if not is_instance_valid(p):
			continue
		if _boss.global_position.distance_to(p.global_position) <= CHARGE_HIT_RADIUS:
			if p.has_method("take_damage"):
				p.take_damage(CHARGE_DAMAGE)
			_hit_player_this_charge = true
			ScreenShake.shake(0.1, 0.2)
			break

func on_chill_during_charge(stacks_added: int) -> void:
	# Each chill stack reduces velocity by 8%
	_velocity_modifier *= max(0.0, 1.0 - 0.08 * float(stacks_added))

func on_pull_during_charge(pull_origin: Vector3, magnitude: float) -> void:
	if not is_in_execution():
		return
	# Redirect: shift charge direction perpendicular by pull magnitude
	var to_pull: Vector3 = pull_origin - _boss.global_position
	to_pull.y = 0.0
	to_pull = to_pull.normalized()
	# Compute perpendicular component
	var perp: Vector3 = to_pull - to_pull.project(_charge_dir)
	if perp.length() > 0.01:
		_charge_dir = (_charge_dir + perp.normalized() * 0.3).normalized()
```

- [ ] **Step 4: Register in boss_dragon**

```gdscript
const MechanicCharge = preload("res://scripts/entities/boss_mechanics/mechanic_charge.gd")

# In _ready:
_register_mechanic(MechanicCharge.new())
```

- [ ] **Step 5: Run tests to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_mechanic_charge.gd
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```
Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/entities/boss_mechanics/mechanic_charge.gd scripts/entities/boss_dragon.gd test/test_mechanic_charge.gd
git commit -m "feat: boss charge mechanic (P3 unlock, 60 dmg, line, 1.4s windup, wall interactions)"
```

---

## Task 22: Charge color interactions (chill slow + pull redirect)

**Files:**
- Modify: `scripts/entities/boss_dragon.gd` (route chill/pull during charge to charge mechanic)
- Test: `test/test_charge_color_interactions.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_charge_color_interactions.gd`:

```gdscript
extends GdUnitTestSuite

const ChargeScript = preload("res://scripts/entities/boss_mechanics/mechanic_charge.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")

var boss: CharacterBody3D
var charge: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	await get_tree().process_frame
	charge = ChargeScript.new()
	boss._register_mechanic(charge)
	await get_tree().process_frame

func test_chill_during_charge_slows_velocity() -> void:
	boss._phase = 3
	charge.trigger(3)
	# Skip past windup
	for i in range(90):
		await get_tree().physics_frame
	# Now in execution; apply chill 4x
	boss.apply_chill(4)
	# Velocity modifier should be ≤ 0.74 (4 stacks × 8% = 32% reduction)
	assert_float(charge._velocity_modifier).is_less(0.75)

func test_pull_during_charge_redirects_trajectory() -> void:
	boss._phase = 3
	charge.trigger(3)
	for i in range(90):
		await get_tree().physics_frame
	var initial_dir: Vector3 = charge._charge_dir
	boss.apply_pull_toward(boss.global_position + Vector3(2, 0, 0), 1.0)
	assert_vector(charge._charge_dir).is_not_equal(initial_dir)
```

- [ ] **Step 2: Run to verify failure**

Expected: FAIL.

- [ ] **Step 3: Wire chill and pull forwarding in boss_dragon**

Modify `scripts/entities/boss_dragon.gd` `apply_chill`:

```gdscript
func apply_chill(stacks: int) -> void:
	var prior_stacks: int = _chill_stacks
	_chill_stacks = mini(_chill_stacks + stacks, FREEZE_THRESHOLD - 1)
	var added: int = _chill_stacks - prior_stacks
	apply_slow(SLOW_PER_CHILL_STACK * float(_chill_stacks), 1.0)
	for m in _mechanics:
		if m.has_method("on_chill_applied"):
			m.on_chill_applied(added)
		if m.has_method("on_chill_during_charge") and m.has_method("is_in_execution") and m.is_in_execution():
			m.on_chill_during_charge(added)
```

Modify `apply_pull_toward`:

```gdscript
func apply_pull_toward(target_pos: Vector3, impulse: float) -> void:
	var dir: Vector3 = target_pos - global_position
	dir.y = 0.0
	if dir.length() < 0.001:
		return
	for m in _mechanics:
		if m.has_method("on_pull_during_windup") and m.has_method("is_in_windup") and m.is_in_windup():
			m.on_pull_during_windup(target_pos, CONE_REDIRECT_PER_PULL_DEG)
		if m.has_method("on_pull_during_charge") and m.has_method("is_in_execution") and m.is_in_execution():
			m.on_pull_during_charge(target_pos, impulse)
	var effective_impulse: float = impulse / _mass()
	_knockback_velocity += dir.normalized() * effective_impulse
	_clamp_knockback_velocity()
```

- [ ] **Step 4: Run tests to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_charge_color_interactions.gd
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/entities/boss_dragon.gd test/test_charge_color_interactions.gd
git commit -m "feat: blue chill slows boss charge velocity + purple pull redirects charge trajectory"
```

---

## Task 23: Flying slam mechanic (P3 unlock)

**Files:**
- Create: `scripts/entities/boss_mechanics/mechanic_flying_slam.gd`
- Modify: `scripts/entities/boss_dragon.gd` (register, charge/flying-slam shared cooldown floor)
- Test: `test/test_mechanic_flying_slam.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_mechanic_flying_slam.gd`:

```gdscript
extends GdUnitTestSuite

const FlyingSlamScript = preload("res://scripts/entities/boss_mechanics/mechanic_flying_slam.gd")
const ChargeScript = preload("res://scripts/entities/boss_mechanics/mechanic_charge.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

var boss: CharacterBody3D
var player: CharacterBody3D
var slam: Node
var charge: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	add_child(player); player.global_position = Vector3(0, 0, 3)
	await get_tree().process_frame
	slam = FlyingSlamScript.new()
	charge = ChargeScript.new()
	boss._register_mechanic(slam)
	boss._register_mechanic(charge)
	await get_tree().process_frame

func test_timings() -> void:
	assert_float(slam.windup_duration).is_equal_approx(2.0, 0.001)
	assert_float(slam.execution_duration).is_equal_approx(0.4, 0.001)

func test_unlocked_phase_3() -> void:
	assert_int(slam.unlock_phase).is_equal(3)

func test_lands_at_locked_target_and_damages() -> void:
	boss._phase = 3
	var initial_hp: int = player.hp
	slam.trigger(3)
	for i in range(180):
		await get_tree().physics_frame
	assert_int(player.hp).is_less(initial_hp)

func test_charge_blocks_flying_slam_for_6s() -> void:
	boss._phase = 3
	charge.trigger(3)
	# Wait through full charge
	for i in range(180):
		await get_tree().physics_frame
	# Flying slam should not be ready (6s shared floor)
	assert_bool(slam.is_ready(3)).is_false()
```

- [ ] **Step 2: Run to verify failure**

Expected: FAIL.

- [ ] **Step 3: Implement flying slam**

Create `scripts/entities/boss_mechanics/mechanic_flying_slam.gd`:

```gdscript
extends BossMechanic

const SLAM_DAMAGE: int = 80
const SLAM_RADIUS: float = 3.0
const RED_BURN_PREP_MULT: float = 1.5

var _target_pos: Vector3 = Vector3.ZERO

func _init() -> void:
	unlock_phase = 3
	is_big = true
	cooldowns_by_phase = {1: 999.0, 2: 999.0, 3: 18.0}
	windup_duration = 2.0
	execution_duration = 0.4

func _on_windup_start() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	_target_pos = players[0].global_position

func _on_execution_start() -> void:
	# Land: damage player + walls in radius
	var players: Array = get_tree().get_nodes_in_group("player")
	for p in players:
		if not is_instance_valid(p):
			continue
		if p.global_position.distance_to(_target_pos) <= SLAM_RADIUS:
			# Wall absorb: any wall in landing zone takes the hit instead
			if not _wall_absorbs_landing():
				if p.has_method("take_damage"):
					p.take_damage(SLAM_DAMAGE)
	ScreenShake.shake(0.15, 0.3)

func _wall_absorbs_landing() -> bool:
	var walls: Array = get_tree().get_nodes_in_group("bone_wall")
	for w in walls:
		if not is_instance_valid(w):
			continue
		if w.global_position.distance_to(_target_pos) <= SLAM_RADIUS:
			if w.has_method("take_damage"):
				w.take_damage(SLAM_DAMAGE)
			return true
	return false

func is_in_prep() -> bool:
	return is_in_windup()

func burn_damage_multiplier() -> float:
	return RED_BURN_PREP_MULT
```

- [ ] **Step 4: Implement charge/flying-slam shared cooldown**

Modify `scripts/entities/boss_dragon.gd`. Add tracking variable and override is_ready:

```gdscript
const CHARGE_SLAM_SHARED_FLOOR_S: float = 6.0

var _last_charge_or_slam_msec: int = -10000

func _bump_shared_cooldown() -> void:
	_last_charge_or_slam_msec = Time.get_ticks_msec()

func is_charge_or_slam_locked() -> bool:
	return Time.get_ticks_msec() - _last_charge_or_slam_msec < int(CHARGE_SLAM_SHARED_FLOOR_S * 1000.0)
```

Update `_tick_mechanics` to apply the rule when picking from ready set:

```gdscript
func _tick_mechanics(delta: float) -> void:
	var phase: int = _phase
	for m in _mechanics:
		m.tick(delta, phase)
	if _any_mechanic_busy():
		return
	var ready: Array[Node] = []
	for m in _mechanics:
		if m.is_ready(phase):
			# Charge/Flying-slam mutual lock
			if (m.get_script() == load("res://scripts/entities/boss_mechanics/mechanic_charge.gd") or
				m.get_script() == load("res://scripts/entities/boss_mechanics/mechanic_flying_slam.gd")):
				if is_charge_or_slam_locked():
					continue
			ready.append(m)
	if ready.is_empty():
		return
	var pick: Node = ready[randi() % ready.size()]
	pick.trigger(phase)
	if pick.get_script() == load("res://scripts/entities/boss_mechanics/mechanic_charge.gd") or pick.get_script() == load("res://scripts/entities/boss_mechanics/mechanic_flying_slam.gd"):
		_bump_shared_cooldown()
```

Register flying slam:

```gdscript
const MechanicFlyingSlam = preload("res://scripts/entities/boss_mechanics/mechanic_flying_slam.gd")
# In _ready:
_register_mechanic(MechanicFlyingSlam.new())
```

- [ ] **Step 5: Run tests to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_mechanic_flying_slam.gd
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```
Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/entities/boss_mechanics/mechanic_flying_slam.gd scripts/entities/boss_dragon.gd test/test_mechanic_flying_slam.gd
git commit -m "feat: boss flying slam (P3, 80 dmg, 3m AoE) + charge/slam shared 6s cooldown floor"
```

---

## Task 24: Red burn 1.5× during flying slam prep

**Files:**
- Modify: `scripts/entities/boss_dragon.gd` (apply burn multiplier when slam in prep)
- Test: `test/test_burn_during_slam_prep.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_burn_during_slam_prep.gd`:

```gdscript
extends GdUnitTestSuite

const FlyingSlamScript = preload("res://scripts/entities/boss_mechanics/mechanic_flying_slam.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")

var boss: CharacterBody3D
var slam: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	add_child(boss)
	await get_tree().process_frame
	slam = FlyingSlamScript.new()
	boss._register_mechanic(slam)
	await get_tree().process_frame

func test_burn_does_15x_damage_during_slam_prep() -> void:
	# Apply burn before slam, then trigger slam windup
	boss.apply_burn(20.0, 5.0)  # 20 dps for 5s
	boss._phase = 3
	slam.trigger(3)
	# Skip 0.5s of physics — boss in windup, burn ticks
	var hp_before: int = boss.hp
	for i in range(30):  # 0.5s
		await get_tree().physics_frame
	var dmg_taken: int = hp_before - boss.hp
	# Without multiplier, 20 dps × 0.5s = 10 dmg
	# With 1.5x: ~15 dmg (cap allows it)
	assert_int(dmg_taken).is_greater(10)
```

- [ ] **Step 2: Run to verify failure**

Expected: FAIL.

- [ ] **Step 3: Multiply burn during slam prep**

Modify `scripts/entities/boss_dragon.gd` `_tick_status_effects` burn block:

```gdscript
if _burn_remaining > 0.0:
	var burn_dps_effective: float = _burn_dps
	# Red interaction: 1.5x burn during flying slam prep
	for m in _mechanics:
		if m.has_method("burn_damage_multiplier") and m.has_method("is_in_prep") and m.is_in_prep():
			burn_dps_effective *= m.burn_damage_multiplier()
			break
	_burn_residual += burn_dps_effective * delta
	var burn_dmg: int = int(_burn_residual)
	if burn_dmg > 0:
		_burn_residual -= float(burn_dmg)
		if not _is_dead:
			var hp_before: int = hp
			take_damage_with_source(burn_dmg, "burn")
			DamageMeter.record(self, burn_dmg, hp_before - hp, "burn")
	_burn_remaining = max(0.0, _burn_remaining - delta)
	if _burn_remaining == 0.0:
		_burn_residual = 0.0
```

- [ ] **Step 4: Run tests to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_burn_during_slam_prep.gd
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/entities/boss_dragon.gd test/test_burn_during_slam_prep.gd
git commit -m "feat: red burn deals 1.5x damage during boss flying slam prep window"
```

---

## Task 25: Mark cooldown phase scaling + summon retuning

**Files:**
- Modify: `scripts/entities/boss_dragon.gd` (existing summon intervals → spec values)
- Test: `test/test_boss_phase_intervals.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_boss_phase_intervals.gd`:

```gdscript
extends GdUnitTestSuite

const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")

var boss: CharacterBody3D

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	add_child(boss)
	await get_tree().process_frame

func test_phase_1_whelp_summon_interval() -> void:
	boss._phase = 1
	assert_float(boss._interval_for_phase()).is_equal(4.0)

func test_phase_2_whelp_summon_interval() -> void:
	boss._phase = 2
	assert_float(boss._interval_for_phase()).is_equal(2.5)

func test_phase_3_whelp_summon_interval() -> void:
	boss._phase = 3
	assert_float(boss._interval_for_phase()).is_equal(1.5)
```

- [ ] **Step 2: Run to verify failure**

Expected: FAIL or PASS depending on current values; may need adjustment.

- [ ] **Step 3: Update summon intervals**

Modify `scripts/entities/boss_dragon.gd`:

```gdscript
@export var phase_1_summon_interval: float = 4.0
@export var phase_2_summon_interval: float = 2.5
@export var phase_3_summon_interval: float = 1.5
```

(If `_interval_for_phase` is already implemented, no further change. Verify it returns these values.)

- [ ] **Step 4: Add dragon summon track**

Modify `scripts/entities/boss_dragon.gd`. Add:

```gdscript
const BOSS_DRAGON_SCENE: PackedScene = preload("res://scenes/entities/boss_dragon_minion.tscn")  # if doesn't exist, use existing dragon scene path
const PHASE_2_DRAGON_INTERVAL: float = 12.0
const PHASE_3_DRAGON_INTERVAL: float = 8.0

var _dragon_summon_timer: float = 0.0

func _maybe_summon_dragon(delta: float) -> void:
	if _phase < 2:
		return
	_dragon_summon_timer += delta
	var interval: float = PHASE_3_DRAGON_INTERVAL if _phase == 3 else PHASE_2_DRAGON_INTERVAL
	if _dragon_summon_timer >= interval:
		_dragon_summon_timer = 0.0
		_summon_dragon()

func _summon_dragon() -> void:
	# If a dragon scene exists, instantiate; else fallback to whelp
	# (This is a placeholder — actual dragon entity may differ)
	_summon_whelp()
```

Call `_maybe_summon_dragon(delta)` in `_physics_process` after the existing whelp summon block.

- [ ] **Step 5: Run tests to verify pass**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_boss_phase_intervals.gd
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```
Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/entities/boss_dragon.gd test/test_boss_phase_intervals.gd
git commit -m "feat: boss summon intervals retuned per spec (P1 4s, P2 2.5s, P3 1.5s) + dragon track P2+"
```

---

## Task 26: Final integration test (whole boss fight)

**Files:**
- Test: `test/test_boss_full_fight.gd`

- [ ] **Step 1: Write the integration test**

Create `test/test_boss_full_fight.gd`:

```gdscript
extends GdUnitTestSuite

const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

var boss: CharacterBody3D
var player: CharacterBody3D

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	add_child(player); player.global_position = Vector3(5, 0, 0)
	await get_tree().process_frame

func test_boss_has_all_8_mechanics_registered() -> void:
	assert_int(boss._mechanics.size()).is_equal(8)

func test_phase_2_unlocks_sweeping_breath_and_armor_wings() -> void:
	boss._phase = 2
	var unlocked_in_p2: int = 0
	for m in boss._mechanics:
		if m.is_ready(2):
			unlocked_in_p2 += 1
	# At least the P1 mechanics + P2 unlocks should be ready
	assert_int(unlocked_in_p2).is_greater(4)

func test_only_one_big_attack_at_a_time() -> void:
	boss._phase = 1
	# Force-trigger a big mechanic, then tick scheduler — no second should fire
	var slam: Node = boss._mechanics[0]
	slam.trigger(1)
	boss._tick_mechanics(0.1)
	var busy_count: int = 0
	for m in boss._mechanics:
		if m.is_busy():
			busy_count += 1
	assert_int(busy_count).is_equal(1)

func test_boss_dies_at_zero_hp() -> void:
	boss.hp = 1
	boss.take_damage(100)
	assert_int(boss.hp).is_equal(0)
	assert_bool(boss._is_dead).is_true()
```

- [ ] **Step 2: Run integration test**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/test_boss_full_fight.gd
```
Expected: 4/4 pass.

- [ ] **Step 3: Run full suite + verify zero error spam in test logs**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```
Expected: all passing.

- [ ] **Step 4: Manual playtest**

Launch the game, fight the boss with three different builds:
1. Pure red-base + red modifiers (heavy DPS, no color counters)
2. White-base + 2 white modifiers (defensive, multiple counters)
3. Blue+green hybrid (charge slow + breath block)

For each:
- Verify each phase's mechanics fire visibly
- Verify color interactions work (white wall stops charge, etc.)
- Note kill time
- Check `~/AppData/Roaming/Godot/app_userdata/New Chance/logs/godot.log` for DamageMeter output and any error spam
- Acceptable kill time range: 110–180 seconds

- [ ] **Step 5: Commit**

```bash
git add test/test_boss_full_fight.gd
git commit -m "test: full boss fight integration test with all 8 mechanics + phase scheduling"
```

---

## Task 27: Final pre-merge cleanup + tag preparation

- [ ] **Step 1: Run full test suite one more time**

```
./addons/gdUnit4/runtest.cmd --godot_binary "C:/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" -a test/
```
Expected: all passing.

- [ ] **Step 2: Verify Debug.FAST_TEST is false for ship**

Open `scripts/core/debug.gd` and confirm `const FAST_TEST: bool = false`.

- [ ] **Step 3: Code review pass**

Use `superpowers:requesting-code-review` to validate the whole branch before merge.

- [ ] **Step 4: User playtests + approves**

Final round of manual playtest. User verifies feel.

- [ ] **Step 5: Merge to master + tag v0.9-elements-balance**

```bash
git checkout master
git merge phase-9-elements-balance
git tag -a v0.9-elements-balance -m "Phase 9: balance + elements + boss mechanics + Tier 1 color interactions"
```

---

## Self-Review Notes

**Spec coverage check:**

| Spec § | Plan task |
|---|---|
| §1 boss phases | Tasks 5–25 (each mechanic registered with correct unlock_phase) |
| §2 telegraph timings | Tasks 6, 8, 14, 18, 19, 21, 23, 16 (each mechanic) |
| §2 damage values | same as above |
| §2 cooldowns by phase | Each mechanic's `cooldowns_by_phase` dict in tasks 6, 8, 14, 18, 19, 21, 23 + Task 25 (summons) |
| §3 mutual exclusivity | Task 5 (`_any_mechanic_busy`) + Task 23 (charge/slam shared floor) |
| §4 white wall blocks breath | Task 9 |
| §4 white wall absorbs mark | Task 15 |
| §4 white wall stops/slows charge | Task 21 |
| §4 white wall on flying slam landing | Task 23 |
| §4 walking boss break-through | Task 17 |
| §4 blue chill extends breath | Task 11 |
| §4 blue chill slows charge | Task 22 |
| §4 red burn pierces armor wings | Task 20 |
| §4 red burn 1.5× during slam prep | Task 24 |
| §4 green cloud blocks breath | Task 10 |
| §4 purple pull redirects breath | Task 12 |
| §4 purple pull redirects charge | Task 22 |
| §5 sword scaling | Task 1 |
| §5 wall concurrent cap | Task 2 |
| §5 boss CC immunity | Already locked (Phase 9), preserved by Task 11 going through `apply_chill` cap |
| §5 conditional jump trigger | Task 16 |
| §5 phase transitions | Existing logic preserved; no invuln window per spec |
| §5 DamageMeter source tags | Task 20 (forwards source_tag to take_damage_with_source) |
| §6 telegraph visuals | Tasks 7, 13 (cone scene + mark scene); other visuals are part of mechanic implementation |

All 16 color interactions and 8 mechanics traced to specific tasks. Sword scaling and wall cap covered as foundation.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-29-boss-mechanics-color-interactions.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using `executing-plans`, batch execution with checkpoints.

**Which approach?**
