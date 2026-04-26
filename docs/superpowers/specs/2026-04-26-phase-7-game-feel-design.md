# Phase 7: Game-Feel Pass (Code-Only) — Design

**Date:** 2026-04-26
**Status:** Approved (pending user review of written spec)
**Predecessor:** Phase 6 (ship-ready) — shipped, tagged `v0.6-ship-ready`

---

## Goal

Make combat feel weighty and reactive. Currently every hit, kill, pickup, and dramatic moment is silent and stiff. Phase 7 adds visual feedback throughout: screen shake, hit-stop, hit flashes, particle bursts, knockback, player damage flash, and a boss-kill slow-mo. **No external assets** — every effect is code-driven.

Phase 7 does **not** include: SFX, music, voice, animation rigs, art replacement, damage numbers, soul-pickup sparkles, sword swing trails, cast projectile trails, or zoom-punch effects (deferred to later phases).

---

## Architecture

Two new autoloads (`ScreenShake`, `HitStop`), one new class-script with static helpers (`Vfx`), one new particle scene (`death_burst.tscn`), and small additions to existing entity/UI scripts. All behaviors trigger from existing damage/death code paths. No restructuring of existing files.

| File | Status | Responsibility |
|---|---|---|
| `scripts/world/screen_shake.gd` | **Create** | Autoload — shakes the active Camera3D for a duration |
| `scripts/world/hit_stop.gd` | **Create** | Autoload — freezes Engine.time_scale briefly |
| `scripts/effects/vfx.gd` | **Create** | Helper class with static `spawn_death_burst()` |
| `scenes/effects/death_burst.tscn` | **Create** | One-shot GPUParticles3D template, color-tintable |
| `project.godot` | Modify | Register `ScreenShake` and `HitStop` autoloads |
| `scripts/entities/welp.gd` | Modify | Add `flash_hit()` + `apply_knockback()`; trigger VFX from take_damage |
| `scripts/entities/boss_dragon.gd` | Modify | Same + boss-kill slow-mo + phase-transition shake |
| `scripts/entities/player.gd` | Modify | Trigger screen shake + damage flash on take_damage |
| `scripts/skills/sword.gd` | Modify | Trigger hit-stop + knockback + flash on enemy hit |
| `scripts/skills/cast_*.gd` | Modify | Trigger hit-stop + knockback + flash on skill hit |
| `scripts/ui/hud.gd` (or new) | Modify | Add `play_damage_flash()` |
| `scenes/ui/hud.tscn` | Modify | Add fullscreen `DamageFlash` ColorRect |

---

## Section 1: Screen Shake

### New autoload

`scripts/world/screen_shake.gd`:

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
    var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
    if cam == null:
        return
    if _camera != cam:
        # Restore prior camera if we were shaking a different one
        if _camera != null and is_instance_valid(_camera):
            _camera.global_position = _resting_origin
        _camera = cam
        _resting_origin = cam.global_position
    if duration > _remaining:
        _remaining = duration
    _intensity = max(_intensity, intensity)
```

Registered in `project.godot` autoload list.

### Trigger sites and parameters

| Event | Intensity | Duration |
|---|---|---|
| Player hit by enemy | 0.25 | 0.18s |
| Sword connects with enemy | 0.10 | 0.06s |
| Skill projectile hits enemy | 0.15 | 0.10s |
| Boss phase 2 transition | 0.5 | 0.4s |
| Boss phase 3 transition | 0.5 | 0.4s |
| Boss death | 0.7 | 0.6s |

### Acceptance

- Calling `ScreenShake.shake()` with no active camera does not crash.
- Two overlapping shakes use the larger intensity and remaining duration.
- After shake completes, camera origin is exactly restored (no drift).

---

## Section 2: Hit-Stop

### New autoload

`scripts/world/hit_stop.gd`:

```gdscript
extends Node

var _active_until: float = 0.0  # real-time deadline (Godot ticks)

func freeze(duration: float = 0.05) -> void:
    if duration <= 0.0:
        return
    var deadline: float = Time.get_ticks_msec() / 1000.0 + duration
    var was_active: bool = _active_until > Time.get_ticks_msec() / 1000.0
    _active_until = max(_active_until, deadline)
    if was_active:
        return  # extension only — already frozen, the active timer will catch the new deadline
    Engine.time_scale = 0.0
    _schedule_unfreeze()

func _schedule_unfreeze() -> void:
    var remaining: float = _active_until - Time.get_ticks_msec() / 1000.0
    if remaining <= 0.0:
        Engine.time_scale = 1.0
        return
    var t: SceneTreeTimer = get_tree().create_timer(remaining, true)  # ignore_time_scale=true
    t.timeout.connect(_on_freeze_done)

func _on_freeze_done() -> void:
    var now: float = Time.get_ticks_msec() / 1000.0
    if now < _active_until:
        # An extension came in mid-flight; reschedule.
        _schedule_unfreeze()
        return
    Engine.time_scale = 1.0
```

Use of `Time.get_ticks_msec()` (real time) avoids the time_scale=0 trap that would prevent timers from advancing.

### Trigger sites

| Event | Duration |
|---|---|
| Welp killed | 0.05s (50ms) |
| Dragon killed | 0.08s |
| Elder dragon killed | 0.12s |
| Boss killed | handled by Section 7 slow-mo (no separate hit-stop) |

### Acceptance

- Calling `freeze` twice rapidly with overlapping windows extends the freeze rather than cutting it off early.
- After `_on_freeze_done`, `Engine.time_scale == 1.0`.
- A test that calls `freeze(0.05)` then `freeze(0.10)` 1ms later sees `_active_until` matching the 0.10s window.

---

## Section 3: Enemy Hit Flash

Add `flash_hit()` to `scripts/entities/welp.gd` and `scripts/entities/boss_dragon.gd`.

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
```

Boss uses `flash_hit(0.18)` for slightly longer visibility. Welp/dragon use default 0.12s.

Called at the top of `take_damage`, before the `_is_dead` short-circuit (so a final hit still flashes briefly even while the death sequence runs).

### Acceptance

- Material is duplicated only on first flash (no per-flash GC churn after the first).
- Original color is captured before the white flash, restored exactly via the tween.
- Multiple flashes during a frame don't compound (last call wins, tween auto-restarts).

---

## Section 4: Particle Burst on Kill

### Particle scene

`scenes/effects/death_burst.tscn`: a single `GPUParticles3D` node with:
- `amount: 30`
- `lifetime: 0.5`
- `one_shot: true`
- `explosiveness: 0.95` (most particles emit in the first frame)
- A `ParticleProcessMaterial` with: gravity `Vector3(0, -2, 0)`, initial velocity range `[3.0, 6.0]`, spread `45°`, scale curve fading from 1.0 to 0.0 over lifetime.
- Default color: white (gets overridden per-spawn).

### Helper class

`scripts/effects/vfx.gd`:

```gdscript
class_name Vfx

const DEATH_BURST_SCENE: PackedScene = preload("res://scenes/effects/death_burst.tscn")

static func spawn_death_burst(pos: Vector3, color: Color, parent: Node) -> void:
    if parent == null or not is_instance_valid(parent):
        return
    var burst: GPUParticles3D = DEATH_BURST_SCENE.instantiate() as GPUParticles3D
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

### Trigger

Move the `COLOR_ALBEDO` dict from `corner_spawner.gd` into `Vfx` as a static const so both files share one source of truth:

```gdscript
# scripts/effects/vfx.gd
class_name Vfx

const COLOR_ALBEDO: Dictionary = {
    "red": Color(0.5, 0.1, 0.1, 1),
    "blue": Color(0.2, 0.4, 0.85, 1),
    "green": Color(0.2, 0.6, 0.2, 1),
    "purple": Color(0.4, 0.2, 0.6, 1),
    "gold": Color(0.8, 0.7, 0.2, 1),
    "white": Color(0.8, 0.8, 0.78, 1),
}
```

Then in `corner_spawner.gd`, replace its local `COLOR_ALBEDO` dict and references with `Vfx.COLOR_ALBEDO`. (This is a small refactor folded into Phase 7 because we're touching both files anyway.)

In `welp.take_damage` when hp drops to 0, BEFORE `queue_free()`:

```gdscript
var burst_color: Color = Vfx.COLOR_ALBEDO.get(color, Color(0.5, 0.5, 0.5, 1))
Vfx.spawn_death_burst(global_position + Vector3(0, 0.5, 0), burst_color, get_parent())
```

For the boss death burst, use a deep red `Color(0.6, 0.1, 0.1)` directly (boss isn't keyed by color).

### Acceptance

- `Vfx.spawn_death_burst` returns without crash when `parent` is null/invalid.
- Particle scene auto-frees within 0.6s of emission start.
- Per-spawn material duplication prevents color bleeding between simultaneous bursts.

---

## Section 5: Knockback

Add to `scripts/entities/welp.gd`:

```gdscript
const KNOCKBACK_DECAY: float = 12.0  # m/s² — how fast the knockback impulse decays

var _knockback_velocity: Vector3 = Vector3.ZERO

func apply_knockback(direction: Vector3, force: float) -> void:
    direction.y = 0.0
    if direction.length() < 0.001:
        return
    _knockback_velocity += direction.normalized() * force
```

In `_physics_process`, the knockback must be applied AFTER the existing tracking assignment to `velocity.x` / `velocity.z` (the assignment uses `=`, not `+=`, so it would clobber any earlier knockback contribution). Add this block AFTER the existing tracking-and-attack logic, BEFORE the gravity line and `move_and_slide`:

```gdscript
# existing tracking lines run as before (unchanged):
if distance > attack_range:
    velocity.x = to_player.normalized().x * move_speed
    velocity.z = to_player.normalized().z * move_speed
else:
    velocity.x = 0.0
    velocity.z = 0.0
    # ... existing attack logic unchanged ...

# NEW: apply knockback impulse on top of tracking velocity, then decay it.
if _knockback_velocity.length() > 0.01:
    velocity.x += _knockback_velocity.x
    velocity.z += _knockback_velocity.z
    _knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * delta)

# existing gravity + move_and_slide unchanged:
velocity.y -= 9.8 * delta if not is_on_floor() else 0.0
move_and_slide()
```

Same pattern for `boss_dragon.gd._physics_process` — knockback block goes after the tracking/contact-damage logic, before gravity.

### Force values

| Source | Target | Force |
|---|---|---|
| Sword | Welp | 4.0 |
| Sword | Dragon | 3.0 |
| Sword | Boss | 1.5 |
| Skill projectile | Welp | 5.5 |
| Skill projectile | Dragon | 4.0 |
| Skill projectile | Boss | 2.0 |

Direction = `(enemy.global_position - source.global_position).normalized()` — push away from attacker. Y component zeroed (we want horizontal pushback only, not lift).

### Acceptance

- `apply_knockback(Vector3.ZERO, 5.0)` is a no-op (zero direction guarded).
- After ~1 second with no further calls, `_knockback_velocity.length()` < 0.01 (decay floor).
- Two rapid knockbacks accumulate (both impulses sum into `_knockback_velocity`).

---

## Section 6: Player Damage Flash

### HUD scene change

In `scenes/ui/hud.tscn`, add a `ColorRect` child of the root (after existing HUD elements so it renders on top):
- Name: `DamageFlash`
- Anchors: full-rect (`anchor_left=0, anchor_top=0, anchor_right=1, anchor_bottom=1`, `offset_*=0`)
- `color = Color(0.8, 0.05, 0.05, 0)` — alpha 0 = invisible at rest
- `mouse_filter = MOUSE_FILTER_IGNORE` — don't block clicks

### Script change

In `scripts/ui/hud.gd` (or whichever script is attached to the HUD; create a minimal one if none):

```gdscript
@onready var _damage_flash: ColorRect = $DamageFlash

func play_damage_flash() -> void:
    if _damage_flash == null:
        return
    _damage_flash.color.a = 0.45
    var tw: Tween = create_tween()
    tw.tween_property(_damage_flash, "color:a", 0.0, 0.35)
```

### Trigger

In `player.gd.take_damage`, after the existing damage-applies logic:

```gdscript
ScreenShake.shake(0.25, 0.18)
var hud: CanvasLayer = get_tree().root.find_child("HUD", true, false)
if hud != null and hud.has_method("play_damage_flash"):
    hud.play_damage_flash()
```

### Acceptance

- Damage flash visible for ~0.35s after every player hit.
- Doesn't fire if player is i-frame'd (existing iframe check guards `take_damage` early).
- HUD-not-found path doesn't crash player.

---

## Section 7: Boss-Kill Slow-Mo

Replace the existing boss `take_damage` `if hp == 0` block with a slow-mo sequence:

```gdscript
if hp == 0:
    _is_dead = true
    died.emit()
    BossFlow.boss_killed()
    ScreenShake.shake(0.7, 0.6)
    Vfx.spawn_death_burst(global_position + Vector3(0, 1, 0), Color(0.6, 0.1, 0.1), get_parent())
    var tw: Tween = create_tween()
    tw.set_ignore_time_scale(true)  # tween advances even at time_scale=0
    tw.tween_property(Engine, "time_scale", 0.3, 0.1)
    tw.tween_interval(0.3)
    tw.tween_property(Engine, "time_scale", 1.0, 0.2)
    tw.tween_callback(func():
        GameState.transition_to(GameState.Location.MAIN_HALL)
        queue_free()
    )
    return
```

Total duration: ~600ms (100ms ramp-down + 300ms hold at 0.3× + 200ms ramp-back-up). Then scene transition.

### Acceptance

- Player visibly experiences the death moment in slow-mo.
- After the sequence completes, `Engine.time_scale == 1.0` and the scene transitions.
- The boss `queue_free` happens AFTER `transition_to` so the boss visually persists during the slow-mo (it's the dramatic centerpiece).

---

## Section 8: Testing

Most game-feel is visual; tests cover the pure-logic surface only.

### New tests

`test/test_hit_stop.gd` — 3 tests:
- `freeze(0)` is a no-op (no time_scale change)
- `freeze(0.1)` sets `_active_until` ~0.1s in the future
- `freeze(0.05)` followed by `freeze(0.10)` extends `_active_until` to the 0.10 window

`test/test_screen_shake.gd` — 2 tests:
- `shake()` with no active camera is a no-op (no crash)
- `shake(0.5, 0.5)` followed by `shake(0.3, 0.2)` keeps the larger intensity (0.5) and longer duration (0.5)

`test/test_knockback.gd` — 3 tests (instantiating a welp directly):
- `apply_knockback(Vector3.ZERO, 5.0)` leaves `_knockback_velocity` zero
- `apply_knockback(Vector3.RIGHT, 4.0)` sets `_knockback_velocity = Vector3(4, 0, 0)`
- Two consecutive `apply_knockback(Vector3.RIGHT, 4.0)` calls produce `Vector3(8, 0, 0)`

`test/test_vfx.gd` — 2 tests:
- `Vfx.spawn_death_burst(pos, Color, null)` returns without crash (null parent guard)
- `Vfx.spawn_death_burst(pos, Color, parent)` instantiates a `GPUParticles3D` child of `parent`

Total: 10 new tests.

### Manual playtest

User validates visual feedback during normal gameplay:
- Hits feel impactful (shake + flash + knockback)
- Kills feel weighty (hit-stop + burst)
- Boss kill feels dramatic (slow-mo + screen shake + big burst)
- Player damage feels punishing (red flash + screen shake)

---

## Out of Scope

- SFX, music, voice
- Damage numbers, soul-pickup sparkle, sword swing trail, cast projectile trails
- Camera zoom-punch
- Animation rigs / model replacement
- Ranged enemies, new skills
- Network multiplayer (lol)

These are separate phases.

---

## Branch & Tag

- Branch: `phase-7-game-feel`
- Tag on merge: `v0.7-game-feel`
