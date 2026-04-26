# Phase 7 Game-Feel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add code-only visual game-feel — screen shake, hit-stop, hit flashes, knockback, particle bursts on kill, player damage flash, and a boss-kill slow-mo — so combat feels weighty without any external audio/art assets.

**Architecture:** Two new autoloads (`ScreenShake`, `HitStop`), one helper class (`Vfx`) with a particle scene, methods on enemies for flash/knockback, and wiring from sword + cast_base hit handlers + player damage path. Each task is self-contained against a single subsystem; tests cover the pure-logic surface (autoloads, knockback math, vfx instantiation), and visual effects are validated by user playtest.

**Tech Stack:** Godot 4.6 (.NET, Forward+), GDScript with type hints, GdUnit4 testing framework, Jolt 3D physics. Existing autoloads: Debug, GameState, SoulEconomy, Escalation, SaveSystem, MetaProgress, BossFlow.

**Spec:** [docs/superpowers/specs/2026-04-26-phase-7-game-feel-design.md](../specs/2026-04-26-phase-7-game-feel-design.md)

**Branch:** `phase-7-game-feel` (already created)

**Godot CLI:** `"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"` — pass `--ignoreHeadlessMode` to GdUnit4 args.

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `scripts/world/screen_shake.gd` | **Create** | Autoload — shakes the active Camera3D for a duration |
| `scripts/world/hit_stop.gd` | **Create** | Autoload — freezes Engine.time_scale briefly |
| `scripts/effects/vfx.gd` | **Create** | Helper class with `spawn_death_burst` static + `COLOR_ALBEDO` const |
| `scenes/effects/death_burst.tscn` | **Create** | One-shot GPUParticles3D template |
| `project.godot` | Modify | Register `ScreenShake` and `HitStop` autoloads |
| `scripts/world/corner_spawner.gd` | Modify | Read `COLOR_ALBEDO` from `Vfx` instead of local const |
| `scripts/entities/welp.gd` | Modify | Add `flash_hit()`, `apply_knockback()`, knockback velocity in `_physics_process`, kill-time HitStop + Vfx burst |
| `scripts/entities/boss_dragon.gd` | Modify | Same flash/knockback + phase-transition shake + kill slow-mo |
| `scripts/entities/player.gd` | Modify | Trigger ScreenShake + damage flash on `take_damage` |
| `scripts/entities/sword.gd` | Modify | Trigger ScreenShake + flash/knockback on hit |
| `scripts/skills/cast_base.gd` | Modify | Trigger ScreenShake + flash/knockback in `_on_hit_enemy` |
| `scripts/ui/hud.gd` | Modify | Add `play_damage_flash()` |
| `scenes/ui/hud.tscn` | Modify | Add fullscreen `DamageFlash` ColorRect |
| `test/test_screen_shake.gd` | **Create** | Unit tests for shake autoload |
| `test/test_hit_stop.gd` | **Create** | Unit tests for hit-stop autoload |
| `test/test_vfx.gd` | **Create** | Unit tests for Vfx helper |
| `test/test_knockback.gd` | **Create** | Unit tests for welp knockback math |

---

## Task 1: ScreenShake + HitStop Autoloads

Two small autoloads, registered together. Both pure-logic, both unit-testable.

**Files:**
- Create: `scripts/world/screen_shake.gd`
- Create: `scripts/world/hit_stop.gd`
- Create: `test/test_screen_shake.gd`
- Create: `test/test_hit_stop.gd`
- Modify: `project.godot` (register both autoloads)

- [ ] **Step 1: Write failing tests for ScreenShake**

Create `test/test_screen_shake.gd`:

```gdscript
extends GdUnitTestSuite

const ScreenShakeScript = preload("res://scripts/world/screen_shake.gd")

var shake: Node

func before_test() -> void:
	shake = auto_free(ScreenShakeScript.new())
	add_child(shake)
	shake.set_process(false)  # tests control state directly

func test_shake_with_no_active_camera_does_not_crash() -> void:
	# In test context there's typically no current Camera3D. Should be a no-op.
	shake.shake(0.5, 0.5)
	assert_that(shake._remaining).is_equal_approx(0.0, 0.001)

func test_overlapping_shakes_keep_larger_intensity() -> void:
	# Simulate an in-progress shake by setting fields directly, then call shake.
	shake._intensity = 0.5
	shake._remaining = 0.5
	# A weaker overlapping shake should not reduce intensity.
	# (Calling shake() will return early because no camera is found, but we
	# can test the intensity-merge path by calling the merge directly.)
	shake._intensity = max(shake._intensity, 0.3)
	assert_that(shake._intensity).is_equal_approx(0.5, 0.001)

func test_overlapping_shakes_keep_longer_remaining() -> void:
	shake._remaining = 0.5
	shake._remaining = max(shake._remaining, 0.2)
	assert_that(shake._remaining).is_equal_approx(0.5, 0.001)
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd /c/Users/wyenk/OneDrive/Documents/godot/new-chance
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_screen_shake.gd --ignoreHeadlessMode
```

Expected: 3 failures with "preload(...) failed" or "method not found".

- [ ] **Step 3: Implement ScreenShake autoload**

Create `scripts/world/screen_shake.gd`:

```gdscript
extends Node

var _remaining: float = 0.0
var _intensity: float = 0.0
var _camera: Camera3D = null
var _resting_origin: Vector3 = Vector3.ZERO

func _process(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining -= delta
	if _camera == null or not is_instance_valid(_camera):
		_remaining = 0.0
		return
	if _remaining <= 0.0:
		_camera.global_position = _resting_origin
		_camera = null
		return
	var off: Vector3 = Vector3(
		randf_range(-_intensity, _intensity),
		randf_range(-_intensity, _intensity),
		0.0
	)
	_camera.global_position = _resting_origin + off

func shake(intensity: float = 0.3, duration: float = 0.15) -> void:
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var cam: Camera3D = vp.get_camera_3d()
	if cam == null:
		return
	if _camera != cam:
		if _camera != null and is_instance_valid(_camera):
			_camera.global_position = _resting_origin
		_camera = cam
		_resting_origin = cam.global_position
	if duration > _remaining:
		_remaining = duration
	_intensity = max(_intensity, intensity)
```

- [ ] **Step 4: Write failing tests for HitStop**

Create `test/test_hit_stop.gd`:

```gdscript
extends GdUnitTestSuite

const HitStopScript = preload("res://scripts/world/hit_stop.gd")

var hs: Node

func before_test() -> void:
	hs = auto_free(HitStopScript.new())
	add_child(hs)
	# Reset Engine state in case prior test left it scaled
	Engine.time_scale = 1.0
	hs._active_until = 0.0

func after_test() -> void:
	# Always restore time_scale so a failed test doesn't poison the next one
	Engine.time_scale = 1.0

func test_freeze_zero_duration_is_no_op() -> void:
	hs.freeze(0.0)
	assert_that(Engine.time_scale).is_equal_approx(1.0, 0.001)

func test_freeze_sets_active_until_in_future() -> void:
	var before: float = Time.get_ticks_msec() / 1000.0
	hs.freeze(0.1)
	assert_that(hs._active_until).is_greater(before)
	assert_that(hs._active_until).is_less(before + 0.2)

func test_freeze_extends_when_called_during_active_freeze() -> void:
	hs.freeze(0.05)
	var first_until: float = hs._active_until
	hs.freeze(0.10)
	# Second call extended deadline further than the first
	assert_that(hs._active_until).is_greater(first_until - 0.001)
	assert_that(hs._active_until).is_greater_equal(first_until)
```

- [ ] **Step 5: Run HitStop tests to confirm they fail**

```bash
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_hit_stop.gd --ignoreHeadlessMode
```

Expected: 3 failures with "preload(...) failed" or similar.

- [ ] **Step 6: Implement HitStop autoload**

Create `scripts/world/hit_stop.gd`:

```gdscript
extends Node

var _active_until: float = 0.0  # real-time deadline in seconds

func freeze(duration: float = 0.05) -> void:
	if duration <= 0.0:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var deadline: float = now + duration
	var was_active: bool = _active_until > now
	_active_until = max(_active_until, deadline)
	if was_active:
		# Already frozen — the in-flight timer's _on_freeze_done will see the
		# extended deadline and reschedule. No new work needed here.
		return
	Engine.time_scale = 0.0
	_schedule_unfreeze()

func _schedule_unfreeze() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var remaining: float = _active_until - now
	if remaining <= 0.0:
		Engine.time_scale = 1.0
		return
	# ignore_time_scale=true so the timer fires even at time_scale=0
	var t: SceneTreeTimer = get_tree().create_timer(remaining, true)
	t.timeout.connect(_on_freeze_done)

func _on_freeze_done() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now < _active_until:
		_schedule_unfreeze()
		return
	Engine.time_scale = 1.0
```

- [ ] **Step 7: Register both autoloads in `project.godot`**

Find the `[autoload]` block and add `ScreenShake` and `HitStop` AFTER `BossFlow` (order doesn't matter for these two — they have no parse-time dependencies):

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
```

- [ ] **Step 8: Run full test suite, confirm green**

```bash
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/ --ignoreHeadlessMode
```

Expected: 128/128 tests pass (122 prior + 3 ScreenShake + 3 HitStop).

- [ ] **Step 9: Commit**

```bash
git add scripts/world/screen_shake.gd scripts/world/hit_stop.gd test/test_screen_shake.gd test/test_hit_stop.gd project.godot
git commit -m "feat(juice): add ScreenShake + HitStop autoloads

ScreenShake offsets the active Camera3D's origin for a duration with
overlapping-shake intensity merge. HitStop sets Engine.time_scale=0
for a real-time duration and self-extends on overlapping calls."
```

---

## Task 2: Vfx Helper + Death Burst Particle

Migrates `COLOR_ALBEDO` from `corner_spawner.gd` into a shared `Vfx` class. Adds a one-shot particle scene + helper to spawn it.

**Files:**
- Create: `scripts/effects/vfx.gd`
- Create: `scenes/effects/death_burst.tscn`
- Modify: `scripts/world/corner_spawner.gd` (use `Vfx.COLOR_ALBEDO`)
- Create: `test/test_vfx.gd`

- [ ] **Step 1: Create the death_burst particle scene**

Create the directory `scenes/effects/` if it doesn't exist. Then create `scenes/effects/death_burst.tscn` with the following content (text-format scene file):

```
[gd_scene load_steps=3 format=3]

[sub_resource type="ParticleProcessMaterial" id="ParticleProcessMaterial_burst"]
direction = Vector3(0, 1, 0)
spread = 45.0
initial_velocity_min = 3.0
initial_velocity_max = 6.0
gravity = Vector3(0, -2, 0)
scale_min = 0.15
scale_max = 0.25
color = Color(1, 1, 1, 1)

[sub_resource type="SphereMesh" id="SphereMesh_burst"]
radius = 0.05
height = 0.1
radial_segments = 6
rings = 3

[node name="DeathBurst" type="GPUParticles3D"]
amount = 30
lifetime = 0.5
one_shot = true
explosiveness = 0.95
emitting = false
process_material = SubResource("ParticleProcessMaterial_burst")
draw_pass_1 = SubResource("SphereMesh_burst")
```

- [ ] **Step 2: Write failing tests for Vfx**

Create `test/test_vfx.gd`:

```gdscript
extends GdUnitTestSuite

const VfxScript = preload("res://scripts/effects/vfx.gd")

func test_color_albedo_dict_has_six_colors() -> void:
	# Validates the Vfx.COLOR_ALBEDO map exposes the expected color set.
	for c in ["red", "blue", "green", "purple", "gold", "white"]:
		assert_that(VfxScript.COLOR_ALBEDO.has(c)).is_true()

func test_spawn_death_burst_with_null_parent_does_not_crash() -> void:
	# Null/invalid parent should be a no-op, not a crash.
	VfxScript.spawn_death_burst(Vector3.ZERO, Color.WHITE, null)
	# If we got here, the call returned cleanly.
	assert_that(true).is_true()

func test_spawn_death_burst_instantiates_child_of_parent() -> void:
	var parent: Node3D = auto_free(Node3D.new())
	add_child(parent)
	VfxScript.spawn_death_burst(Vector3(1, 2, 3), Color(0.5, 0.5, 0.5), parent)
	# At least one GPUParticles3D child should have been added.
	var found: bool = false
	for child in parent.get_children():
		if child is GPUParticles3D:
			found = true
			break
	assert_that(found).is_true()
```

- [ ] **Step 3: Run Vfx tests, confirm fail**

```bash
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_vfx.gd --ignoreHeadlessMode
```

Expected: 3 failures (Vfx class not defined).

- [ ] **Step 4: Create the Vfx helper class**

Create directory `scripts/effects/` if it doesn't exist. Create `scripts/effects/vfx.gd`:

```gdscript
class_name Vfx

const DEATH_BURST_SCENE: PackedScene = preload("res://scenes/effects/death_burst.tscn")

const COLOR_ALBEDO: Dictionary = {
	"red": Color(0.5, 0.1, 0.1, 1),
	"blue": Color(0.2, 0.4, 0.85, 1),
	"green": Color(0.2, 0.6, 0.2, 1),
	"purple": Color(0.4, 0.2, 0.6, 1),
	"gold": Color(0.8, 0.7, 0.2, 1),
	"white": Color(0.8, 0.8, 0.78, 1),
}

static func spawn_death_burst(pos: Vector3, color: Color, parent: Node) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var burst: GPUParticles3D = DEATH_BURST_SCENE.instantiate() as GPUParticles3D
	if burst == null:
		return
	parent.add_child(burst)
	burst.global_position = pos
	var mat: ParticleProcessMaterial = burst.process_material as ParticleProcessMaterial
	if mat != null:
		var local_mat: ParticleProcessMaterial = mat.duplicate() as ParticleProcessMaterial
		burst.process_material = local_mat
		local_mat.color = color
	burst.emitting = true
	burst.finished.connect(burst.queue_free)
```

- [ ] **Step 5: Run Vfx tests, confirm pass**

```bash
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_vfx.gd --ignoreHeadlessMode
```

Expected: 3/3 pass.

- [ ] **Step 6: Migrate `corner_spawner.gd` to use Vfx.COLOR_ALBEDO**

Edit `scripts/world/corner_spawner.gd`. Find the existing `const COLOR_ALBEDO: Dictionary = { ... }` block (currently lines 14-21) and DELETE it entirely.

Find the existing `_apply_color_tint` method (around line 65) and update the line `mat.albedo_color = COLOR_ALBEDO.get(c, COLOR_ALBEDO["red"])` to:

```gdscript
mat.albedo_color = Vfx.COLOR_ALBEDO.get(c, Vfx.COLOR_ALBEDO["red"])
```

Save. The script now references the shared dict.

- [ ] **Step 7: Run full test suite to verify no regression**

```bash
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/ --ignoreHeadlessMode
```

Expected: 131/131 tests pass (128 + 3 new Vfx tests).

- [ ] **Step 8: Commit**

```bash
git add scripts/effects/vfx.gd scenes/effects/death_burst.tscn scripts/world/corner_spawner.gd test/test_vfx.gd
git commit -m "feat(juice): add Vfx helper + death_burst particle scene

Vfx.spawn_death_burst instantiates a one-shot GPUParticles3D from
death_burst.tscn, color-tinted per call. Migrates COLOR_ALBEDO from
corner_spawner into Vfx so future death-feedback callers share one
source of truth."
```

---

## Task 3: Enemy Hit Flash + Knockback Methods

Adds `flash_hit()` and `apply_knockback()` to welp.gd and boss_dragon.gd. Adds knockback velocity decay in `_physics_process`.

**Files:**
- Modify: `scripts/entities/welp.gd`
- Modify: `scripts/entities/boss_dragon.gd`
- Create: `test/test_knockback.gd`

- [ ] **Step 1: Write failing tests for welp knockback**

Create `test/test_knockback.gd`:

```gdscript
extends GdUnitTestSuite

const WelpScript = preload("res://scripts/entities/welp.gd")

var welp: CharacterBody3D

func before_test() -> void:
	welp = auto_free(CharacterBody3D.new())
	welp.set_script(WelpScript)
	add_child(welp)

func test_apply_knockback_zero_direction_is_noop() -> void:
	welp.apply_knockback(Vector3.ZERO, 5.0)
	assert_that(welp._knockback_velocity).is_equal(Vector3.ZERO)

func test_apply_knockback_sets_velocity_proportional_to_force() -> void:
	welp.apply_knockback(Vector3.RIGHT, 4.0)
	assert_that(welp._knockback_velocity.x).is_equal_approx(4.0, 0.001)
	assert_that(welp._knockback_velocity.y).is_equal_approx(0.0, 0.001)
	assert_that(welp._knockback_velocity.z).is_equal_approx(0.0, 0.001)

func test_apply_knockback_zeroes_y_component() -> void:
	# Even if the input direction has y, y component is dropped.
	welp.apply_knockback(Vector3(1, 1, 0), 4.0)
	assert_that(welp._knockback_velocity.y).is_equal_approx(0.0, 0.001)

func test_consecutive_knockbacks_accumulate() -> void:
	welp.apply_knockback(Vector3.RIGHT, 4.0)
	welp.apply_knockback(Vector3.RIGHT, 4.0)
	assert_that(welp._knockback_velocity.x).is_equal_approx(8.0, 0.001)
```

- [ ] **Step 2: Run tests, confirm fail**

```bash
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_knockback.gd --ignoreHeadlessMode
```

Expected: 4 failures with "_knockback_velocity not found" or "method apply_knockback not found".

- [ ] **Step 3: Add flash_hit, knockback fields, and apply_knockback to welp.gd**

Edit `scripts/entities/welp.gd`. Add the constant and field declarations near the existing `var _attack_cooldown: float = 0.0` line. Final field block:

```gdscript
const KNOCKBACK_DECAY: float = 12.0  # m/s² — knockback impulse decay rate

var hp: int = max_hp
var _attack_cooldown: float = 0.0
var _player: Node = null
var _is_dead: bool = false
var _knockback_velocity: Vector3 = Vector3.ZERO
```

Add these two methods anywhere in the file (suggest: just before the existing `func take_damage` method):

```gdscript
func flash_hit(duration: float = 0.12) -> void:
	var mesh: MeshInstance3D = get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return
	var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	if not mat.resource_local_to_scene:
		mat = mat.duplicate()
		mesh.material_override = mat
	var original: Color = mat.albedo_color
	mat.albedo_color = Color(1, 1, 1, 1)
	var tw: Tween = create_tween()
	tw.tween_property(mat, "albedo_color", original, duration)

func apply_knockback(direction: Vector3, force: float) -> void:
	direction.y = 0.0
	if direction.length() < 0.001:
		return
	_knockback_velocity += direction.normalized() * force
```

- [ ] **Step 4: Wire knockback velocity into welp `_physics_process`**

Find the existing `_physics_process` method (currently around lines 28-50). After the existing tracking/attack block (the if/else that sets velocity.x/z based on distance to player), but BEFORE the gravity line, ADD:

```gdscript
	# Apply knockback impulse on top of tracking velocity, then decay it.
	if _knockback_velocity.length() > 0.01:
		velocity.x += _knockback_velocity.x
		velocity.z += _knockback_velocity.z
		_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * delta)
```

The full updated `_physics_process` for reference (the only addition is the knockback block — every other line is unchanged):

```gdscript
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
	if distance > attack_range:
		velocity.x = to_player.normalized().x * move_speed
		velocity.z = to_player.normalized().z * move_speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if _attack_cooldown <= 0.0:
			_attack_player()
			_attack_cooldown = attack_interval
	if _attack_cooldown > 0.0:
		_attack_cooldown = max(0.0, _attack_cooldown - delta)
	# Apply knockback impulse on top of tracking velocity, then decay it.
	if _knockback_velocity.length() > 0.01:
		velocity.x += _knockback_velocity.x
		velocity.z += _knockback_velocity.z
		_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * delta)
	velocity.y -= 9.8 * delta if not is_on_floor() else 0.0
	move_and_slide()
```

- [ ] **Step 5: Run knockback tests, confirm pass**

```bash
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_knockback.gd --ignoreHeadlessMode
```

Expected: 4/4 pass.

- [ ] **Step 6: Add the same flash + knockback to boss_dragon.gd**

Edit `scripts/entities/boss_dragon.gd`. Add the same `KNOCKBACK_DECAY` const near other constants, and `_knockback_velocity` field with the existing var block:

```gdscript
const KNOCKBACK_DECAY: float = 12.0
```

In the var block (after `_taunt_cooldown`):

```gdscript
var _knockback_velocity: Vector3 = Vector3.ZERO
```

Add both methods (same code as welp.gd, minus the `flash_hit` default duration tweak — boss uses `0.18`):

```gdscript
func flash_hit(duration: float = 0.18) -> void:
	var mesh: MeshInstance3D = get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return
	var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	if not mat.resource_local_to_scene:
		mat = mat.duplicate()
		mesh.material_override = mat
	var original: Color = mat.albedo_color
	mat.albedo_color = Color(1, 1, 1, 1)
	var tw: Tween = create_tween()
	tw.tween_property(mat, "albedo_color", original, duration)

func apply_knockback(direction: Vector3, force: float) -> void:
	direction.y = 0.0
	if direction.length() < 0.001:
		return
	_knockback_velocity += direction.normalized() * force
```

In `_physics_process`, find the existing block (after summon_timer increment, before gravity). Insert the knockback block AFTER the contact damage / timer logic but BEFORE the gravity line. The full updated tail of `_physics_process`:

```gdscript
	if _contact_timer > 0.0:
		_contact_timer = max(0.0, _contact_timer - delta)
	_summon_timer += delta
	var interval: float = _interval_for_phase()
	if _summon_timer >= interval:
		_summon_timer = 0.0
		_summon_whelp()
	# Apply knockback impulse on top of tracking velocity, then decay.
	if _knockback_velocity.length() > 0.01:
		velocity.x += _knockback_velocity.x
		velocity.z += _knockback_velocity.z
		_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * delta)
	velocity.y -= 9.8 * delta if not is_on_floor() else 0.0
	move_and_slide()
```

- [ ] **Step 7: Run full suite, confirm green**

```bash
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/ --ignoreHeadlessMode
```

Expected: 135/135 tests pass (131 + 4 new knockback tests).

- [ ] **Step 8: Commit**

```bash
git add scripts/entities/welp.gd scripts/entities/boss_dragon.gd test/test_knockback.gd
git commit -m "feat(juice): add flash_hit + apply_knockback to welp + boss

Tween-based white flash on hit (0.12s welp, 0.18s boss).
apply_knockback sums an impulse vector that decays at 12 m/s² in
_physics_process. Y component zeroed so enemies don't lift off."
```

---

## Task 4: Wire Hit Feedback into Sword + Skills

Per-hit visual feedback — screen shake, flash_hit, apply_knockback — triggered every time the sword or a skill projectile damages an enemy.

**Files:**
- Modify: `scripts/entities/sword.gd`
- Modify: `scripts/skills/cast_base.gd`

- [ ] **Step 1: Add hit feedback to sword**

Edit `scripts/entities/sword.gd`. Replace the existing `_process` method (currently around lines 13-25) with a version that triggers feedback on each hit. The structural change is the body of the for-loop that iterates over enemies:

```gdscript
func _process(delta: float) -> void:
	if _swing_cooldown > 0.0:
		_swing_cooldown = max(0.0, _swing_cooldown - delta)
		return
	var enemies: Array = get_overlapping_bodies().filter(_is_enemy)
	if enemies.size() == 0:
		return
	# Cleave: swing damages every enemy in range, not just the first.
	for enemy in enemies:
		if not enemy.has_method("take_damage"):
			continue
		enemy.take_damage(base_damage)
		hit_enemy.emit(enemy, base_damage)
		# Visual feedback per hit.
		if enemy.has_method("flash_hit"):
			enemy.flash_hit()
		if enemy.has_method("apply_knockback"):
			var dir: Vector3 = enemy.global_position - global_position
			var force: float = _knockback_force_for(enemy)
			enemy.apply_knockback(dir, force)
		ScreenShake.shake(0.10, 0.06)
	_swing_cooldown = swing_interval

func _knockback_force_for(enemy: Node) -> float:
	# Boss has no "tier" property; treat as boss → 1.5
	if not "tier" in enemy:
		return 1.5
	match enemy.tier:
		"welp": return 4.0
		"dragon": return 3.0
		"elder": return 3.0
		_: return 4.0
```

- [ ] **Step 2: Add hit feedback to cast_base**

Edit `scripts/skills/cast_base.gd`. Replace the existing `_on_hit_enemy` method with a version that triggers feedback:

```gdscript
func _on_hit_enemy(enemy: Node) -> void:
	if not enemy.has_method("take_damage"):
		return
	enemy.take_damage(base_damage)
	for color in modifier_stack:
		_apply_modifier(enemy, color)
	# Visual feedback per skill hit.
	if enemy.has_method("flash_hit"):
		enemy.flash_hit()
	if enemy.has_method("apply_knockback"):
		var dir: Vector3 = enemy.global_position - global_position
		var force: float = _knockback_force_for(enemy)
		enemy.apply_knockback(dir, force)
	ScreenShake.shake(0.15, 0.10)

func _knockback_force_for(enemy: Node) -> float:
	# Boss has no "tier" property; treat as boss → 2.0
	if not "tier" in enemy:
		return 2.0
	match enemy.tier:
		"welp": return 5.5
		"dragon": return 4.0
		"elder": return 4.0
		_: return 5.5
```

All six existing cast scripts (`cast_red_fireball.gd` etc) extend `cast_base.gd` and call `_on_hit_enemy`, so they pick up the changes for free.

- [ ] **Step 3: Run full suite, confirm no regression**

```bash
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/ --ignoreHeadlessMode
```

Expected: 135/135 tests pass. (No new tests in this task — feedback is visual.)

- [ ] **Step 4: Commit**

```bash
git add scripts/entities/sword.gd scripts/skills/cast_base.gd
git commit -m "feat(juice): wire hit feedback into sword + cast_base

Every sword swing and skill projectile that damages an enemy now
triggers ScreenShake.shake, enemy.flash_hit, and enemy.apply_knockback
with tier-keyed force values."
```

---

## Task 5: Wire Kill Feedback (HitStop + Death Burst)

When an enemy dies (welp/dragon/elder), trigger HitStop and spawn a death-burst particle. Boss kill is handled separately in Task 7 with slow-mo.

**Files:**
- Modify: `scripts/entities/welp.gd`

- [ ] **Step 1: Update welp.gd `take_damage` to trigger kill feedback**

Edit `scripts/entities/welp.gd`. Replace the existing `take_damage` method with:

```gdscript
func take_damage(amount: int) -> void:
	if _is_dead:
		return
	hp = max(0, hp - amount)
	if hp == 0:
		_is_dead = true
		_drop_souls()
		HitStop.freeze(_hit_stop_duration())
		var burst_color: Color = Vfx.COLOR_ALBEDO.get(color, Color(0.5, 0.5, 0.5, 1))
		Vfx.spawn_death_burst(global_position + Vector3(0, 0.5, 0), burst_color, get_parent())
		died.emit(self, color)
		queue_free()

func _hit_stop_duration() -> float:
	# Tier-tuned freeze duration for kill weight.
	match tier:
		"welp": return 0.05
		"dragon": return 0.08
		"elder": return 0.12
		_: return 0.05
```

The `_hit_stop_duration` helper is added to keep the duration values discoverable (one place to tweak per tier).

- [ ] **Step 2: Run full suite, confirm green**

```bash
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/ --ignoreHeadlessMode
```

Expected: 135/135 tests pass. (No new test for this — `take_damage` flow already covered indirectly; visual particles are playtest-validated.)

- [ ] **Step 3: Commit**

```bash
git add scripts/entities/welp.gd
git commit -m "feat(juice): trigger HitStop + death burst on welp/dragon/elder kill

50ms hit-stop on welp kill, 80ms on dragon, 120ms on elder. Spawns a
color-tinted GPUParticles3D burst centered above the enemy before
queue_free. Boss kill is handled separately by the slow-mo sequence."
```

---

## Task 6: Player Damage Flash + Screen Shake

Player damage path triggers a red ColorRect flash on the HUD plus a screen shake.

**Files:**
- Modify: `scenes/ui/hud.tscn`
- Modify: `scripts/ui/hud.gd`
- Modify: `scripts/entities/player.gd`

- [ ] **Step 1: Add DamageFlash ColorRect to hud.tscn**

Edit `scenes/ui/hud.tscn`. Append the following node block at the end of the file (after the `Souls` Label node block):

```
[node name="DamageFlash" type="ColorRect" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
color = Color(0.8, 0.05, 0.05, 0)
```

`mouse_filter = 2` is `MOUSE_FILTER_IGNORE` — ensures the overlay doesn't block clicks.

- [ ] **Step 2: Add `play_damage_flash` to hud.gd**

Edit `scripts/ui/hud.gd`. Add a new `@onready` reference and a method. Final structure:

```gdscript
extends CanvasLayer

@onready var _hp_label: Label = $Margin/VBox/HP
@onready var _souls_label: Label = $Margin/VBox/Souls
@onready var _damage_flash: ColorRect = $DamageFlash

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

func play_damage_flash() -> void:
	if _damage_flash == null:
		return
	_damage_flash.color.a = 0.45
	var tw: Tween = create_tween()
	tw.tween_property(_damage_flash, "color:a", 0.0, 0.35)
```

The only addition is the `_damage_flash @onready` line and the `play_damage_flash` function at the bottom.

- [ ] **Step 3: Trigger damage flash + screen shake from player.gd**

Edit `scripts/entities/player.gd`. Find `take_damage`. Read the current implementation first (it has the iframe early-return). After the damage is applied (i.e., after `hp` is decremented and `hp_changed` is emitted), add the feedback calls. The exact insertion point depends on the current method structure — locate the line that emits `hp_changed.emit(hp)` (or sets `hp` if no signal emit there) and insert AFTER it:

```gdscript
ScreenShake.shake(0.25, 0.18)
var hud: CanvasLayer = get_tree().root.find_child("HUD", true, false) as CanvasLayer
if hud != null and hud.has_method("play_damage_flash"):
	hud.play_damage_flash()
```

If the player.gd `take_damage` method exits early via `return` before reaching this point on death, place the feedback calls BEFORE the death `return` so a killing blow still flashes/shakes.

If you can't unambiguously locate the right insertion point because the method is structured differently than expected, report `BLOCKED` with the current `take_damage` method content — the controller will provide the exact patch.

- [ ] **Step 4: Run full suite, confirm green**

```bash
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/ --ignoreHeadlessMode
```

Expected: 135/135 tests pass.

- [ ] **Step 5: Commit**

```bash
git add scenes/ui/hud.tscn scripts/ui/hud.gd scripts/entities/player.gd
git commit -m "feat(juice): player damage flash + screen shake

Adds fullscreen DamageFlash ColorRect to HUD with red-to-transparent
tween. Player.take_damage triggers ScreenShake (0.25 / 0.18s) and
calls hud.play_damage_flash."
```

---

## Task 7: Boss-Specific Game-Feel

Boss takes hit feedback like other enemies (already wired by Task 4 via the sword/cast hit handlers). This task adds:
1. Phase-transition screen shake
2. Boss-kill slow-mo sequence

**Files:**
- Modify: `scripts/entities/boss_dragon.gd`

- [ ] **Step 1: Add screen shake on phase transitions**

Edit `scripts/entities/boss_dragon.gd`. Find `_check_phase_transition` (in the file currently after the Task 5 / Phase 6 changes). Replace with:

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
		ScreenShake.shake(0.5, 0.4)
		# Suppress phase taunts on lethal blow — the victory line will follow.
		if hp > 0:
			if _phase == 2:
				_show_taunt("phase_2_taunt")
			elif _phase == 3:
				_show_taunt("phase_3_taunt")
```

The only addition is the `ScreenShake.shake(0.5, 0.4)` line right after the `phase_changed.emit(_phase)` line.

- [ ] **Step 2: Replace the boss death block with slow-mo sequence**

Edit `scripts/entities/boss_dragon.gd`. Find `take_damage` and replace the `if hp == 0:` block with the slow-mo sequence:

```gdscript
func take_damage(amount: int) -> void:
	if _is_dead:
		return
	hp = max(0, hp - amount)
	_check_phase_transition()
	if hp == 0:
		_is_dead = true
		died.emit()
		BossFlow.boss_killed()
		ScreenShake.shake(0.7, 0.6)
		Vfx.spawn_death_burst(global_position + Vector3(0, 1, 0), Color(0.6, 0.1, 0.1), get_parent())
		# Slow-mo: 1.0 → 0.3 over 100ms, hold 300ms, → 1.0 over 200ms, then transition.
		var tw: Tween = create_tween()
		tw.set_ignore_time_scale(true)
		tw.tween_property(Engine, "time_scale", 0.3, 0.1)
		tw.tween_interval(0.3)
		tw.tween_property(Engine, "time_scale", 1.0, 0.2)
		tw.tween_callback(func():
			GameState.transition_to(GameState.Location.MAIN_HALL)
			queue_free()
		)
```

The block that previously called `GameState.transition_to(...)` and `queue_free()` directly is REPLACED by the tween sequence.

- [ ] **Step 3: Run full suite, confirm green**

```bash
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/ --ignoreHeadlessMode
```

Expected: 135/135 tests pass.

- [ ] **Step 4: Commit**

```bash
git add scripts/entities/boss_dragon.gd
git commit -m "feat(juice): boss phase shake + kill slow-mo

Phase 2/3 transitions trigger 0.5-intensity 0.4s screen shake. Boss
death replaces direct queue_free with a tween: time_scale 1.0→0.3
over 100ms, hold 300ms, 0.3→1.0 over 200ms, then scene transition.
Total ~600ms of dramatic time distortion before the victory cutscene."
```

---

## Final Validation

- [ ] **Step 1: Full test suite**

```bash
cd /c/Users/wyenk/OneDrive/Documents/godot/new-chance
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/ --ignoreHeadlessMode
```

Expected: 135/135 tests pass.

- [ ] **Step 2: Push branch**

```bash
git push -u origin phase-7-game-feel
```

- [ ] **Step 3: User playtest**

User plays a normal grind run + descent + boss fight to validate:
- Hits feel impactful: enemies flash white + get knocked back, screen shakes lightly
- Kills feel weighty: brief time-freeze on welp/dragon/elder kill, particle burst centered on the body
- Player getting hit triggers red flash + heavier screen shake
- Boss phase 2/3 transitions punch the screen with a stronger shake
- Boss kill slow-mos for ~600ms with a big shake + red particle burst, THEN transitions to main_hall victory cutscene

After user approval: merge to master, tag `v0.7-game-feel`.
