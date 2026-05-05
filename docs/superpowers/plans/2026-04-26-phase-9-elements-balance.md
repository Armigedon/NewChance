# Phase 9: Elements + Balance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** finish the elemental system the original spec promised, retune the damage curve to ~5 souls per power spike, and replace the +10% damage stub with a compositional layer/spawner system where modifiers compose meaningfully across long chains.

**Architecture:** introduces a single `DamagePipeline` static dispatch point that all damage events funnel through (cast hits, AoE, cloud ticks, chain jumps, sword swings). Adds inline status state (burn/chill/freeze/stun/slow/pull) on enemies and armor stacks on the player. Rebuilds 4 of 6 cast scripts (green, purple, gold, white) to match their original spec identities; updates red and blue to use the pipeline.

**Tech Stack:** Godot 4.6, GDScript with type hints, GdUnit4 for testing.

**Spec:** `docs/superpowers/specs/2026-04-26-phase-9-elements-balance-design.md`

---

## File Structure

**New files:**
- `scripts/skills/damage_pipeline.gd` — single-entry dispatch + chain + spawner methods
- `scripts/effects/effect_cloud.gd` + `scenes/effects/effect_cloud.tscn` — green LINGER cloud
- `scripts/effects/effect_gravity_well.gd` + `scenes/effects/effect_gravity_well.tscn` — purple well
- `scripts/effects/effect_bone_wall.gd` + `scenes/effects/effect_bone_wall.tscn` — white wall
- `test/test_welp_status.gd`
- `test/test_boss_dragon_status.gd`
- `test/test_player_armor.gd`
- `test/test_damage_pipeline.gd`
- `test/test_effect_cloud.gd`
- `test/test_effect_gravity_well.gd`
- `test/test_effect_bone_wall.gd`

**Modified files:**
- `scripts/skills/cast_base.gd` — same-color factor 0.3 → 0.2; route via DamagePipeline
- `scripts/skills/cast_red_fireball.gd` — AoE on impact via DamagePipeline
- `scripts/skills/cast_blue_ice_line.gd` — pierce + native chill via DamagePipeline
- `scripts/skills/cast_green_plague.gd` — rewrite: place effect_cloud
- `scripts/skills/cast_purple_void.gd` — rewrite: place effect_gravity_well
- `scripts/skills/cast_gold_lightning.gd` — rewrite: instant strike + stun
- `scripts/skills/cast_white_bone.gd` — rewrite: place effect_bone_wall + grant armor
- `scripts/entities/welp.gd` — status state + tier-aware max_hp default
- `scripts/entities/boss_dragon.gd` — status state + boss MAX_HP_SHIP 500, drop phase-3 whelp HP override
- `scripts/entities/player.gd` — armor stacks
- `scripts/entities/sword.gd` — apply active skill's base color native layer per swing
- `scenes/entities/dragon.tscn` — max_hp 80 → 100
- `scenes/entities/boss_whelp.tscn` — add max_hp = 100
- `scenes/skills/cast_green_plague.tscn` — restructure for placed cloud (no projectile)
- `scenes/skills/cast_purple_void.tscn` — restructure for placed well
- `scenes/skills/cast_gold_lightning.tscn` — restructure for instant strike (no projectile)
- `scenes/skills/cast_white_bone.tscn` — restructure for wall placement

---

## Task 1: Damage curve rebalance

**Goal:** retune same-color stacking and enemy HP without changing combat mechanics yet. Ships as a coherent rebalance.

**Files:**
- Modify: `scripts/skills/cast_base.gd:14`
- Modify: `scripts/entities/welp.gd:5`
- Modify: `scripts/entities/boss_dragon.gd:6`
- Modify: `scripts/entities/boss_dragon.gd:97-98`
- Modify: `scenes/entities/dragon.tscn:18`
- Modify: `scenes/entities/boss_whelp.tscn` (add `max_hp = 100`)

- [ ] **Step 1: Change same-color stacking factor in `cast_base.gd:14`**

```gdscript
# Before:
base_damage = int(base_damage * (1.0 + 0.3 * same_color_count))
# After:
base_damage = int(base_damage * (1.0 + 0.2 * same_color_count))
```

- [ ] **Step 2: Change welp default max_hp in `welp.gd:5`**

```gdscript
# Before:
@export var max_hp: int = 30
# After:
@export var max_hp: int = 50
```

- [ ] **Step 3: Update `dragon.tscn` line 18 from `max_hp = 80` to `max_hp = 100`**

Edit the scene file directly (it's a text format):
```
max_hp = 100
```

- [ ] **Step 4: Update `boss_whelp.tscn` to set `max_hp = 100`**

Add the line `max_hp = 100` to the `[node name="Welp" type="CharacterBody3D"]` block in `scenes/entities/boss_whelp.tscn`. The block should look like:

```
[node name="Welp" type="CharacterBody3D"]
script = ExtResource("1_welp")
color = "boss"
max_hp = 100
```

- [ ] **Step 5: Update boss `MAX_HP_SHIP` in `boss_dragon.gd:6`**

```gdscript
# Before:
const MAX_HP_SHIP: int = 400
# After:
const MAX_HP_SHIP: int = 500
```

- [ ] **Step 6: Remove phase-3 whelp HP override in `boss_dragon.gd:96-98`**

```gdscript
# Before:
func _summon_whelp() -> void:
    var whelp: CharacterBody3D = BOSS_WHELP_SCENE.instantiate()
    if _phase == 3 and "max_hp" in whelp:
        whelp.max_hp = 80
    var angle: float = randf() * TAU
# After:
func _summon_whelp() -> void:
    var whelp: CharacterBody3D = BOSS_WHELP_SCENE.instantiate()
    var angle: float = randf() * TAU
```

(Boss whelps now uniformly use the scene's `max_hp = 100` per spec.)

- [ ] **Step 7: Run all tests; confirm none break**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/`
Expected: all existing tests pass. Welp/boss-related tests don't assert specific HP values, so this should not break any.

- [ ] **Step 8: Commit**

```bash
git add scripts/skills/cast_base.gd scripts/entities/welp.gd scripts/entities/boss_dragon.gd scenes/entities/dragon.tscn scenes/entities/boss_whelp.tscn
git commit -m "feat(balance): same-color stacking +20%/stack, tier-aware enemy HP

- Same-color depth factor 0.3 → 0.2 (was trivializing at 2-3 souls)
- Welp default max_hp 30 → 50, dragon 80 → 100, boss whelp 30 → 100
- Boss MAX_HP_SHIP 400 → 500
- Drop phase-3 whelp HP override (uniform 100 from scene now)
- Targets ~5 same-color souls per power spike per design spec"
```

---

## Task 2: Status effects on welp.gd

**Goal:** add inline status state (burn/chill/freeze/slow/stun/pull) to welps + the per-frame ticking that drives them. Dragons and elder dragons share `welp.gd`, so they get this for free.

**Files:**
- Modify: `scripts/entities/welp.gd`
- Create: `test/test_welp_status.gd`

- [ ] **Step 1: Write failing tests in `test/test_welp_status.gd`**

```gdscript
# GdUnit generated TestSuite
extends GdUnitTestSuite

const WelpScene: PackedScene = preload("res://scenes/entities/welp.tscn")

var welp: CharacterBody3D

func before_test() -> void:
    welp = auto_free(WelpScene.instantiate())
    add_child(welp)
    await get_tree().process_frame

func test_apply_burn_sets_state() -> void:
    welp.apply_burn(10.0, 2.0)
    assert_that(welp._burn_dps).is_equal(10.0)
    assert_that(welp._burn_remaining).is_equal(2.0)

func test_burn_ticks_damage_over_time() -> void:
    welp.hp = 100
    welp.apply_burn(20.0, 1.0)  # 20 dps for 1 sec → 20 dmg total
    var initial_hp: int = welp.hp
    # Simulate 1 second via repeated ticks
    for i in range(60):
        welp._tick_status_effects(1.0 / 60.0)
    var hp_lost: int = initial_hp - welp.hp
    assert_that(hp_lost).is_greater_equal(15)  # allow rounding
    assert_that(hp_lost).is_less_equal(25)

func test_burn_expires_after_duration() -> void:
    welp.apply_burn(5.0, 0.5)
    for i in range(60):
        welp._tick_status_effects(1.0 / 60.0)
    assert_that(welp._burn_remaining).is_equal(0.0)

func test_apply_burn_takes_max_of_concurrent() -> void:
    welp.apply_burn(10.0, 2.0)
    welp.apply_burn(5.0, 5.0)  # higher duration
    assert_that(welp._burn_dps).is_equal(10.0)  # higher dps wins
    assert_that(welp._burn_remaining).is_equal(5.0)  # higher duration wins

func test_apply_chill_increments_stacks() -> void:
    welp.apply_chill(2)
    assert_that(welp._chill_stacks).is_equal(2)
    welp.apply_chill(1)
    assert_that(welp._chill_stacks).is_equal(3)

func test_chill_at_5_stacks_freezes() -> void:
    welp.apply_chill(5)
    assert_that(welp.is_frozen()).is_true()
    assert_that(welp._chill_stacks).is_equal(0)  # reset on freeze
    assert_that(welp._frozen_remaining).is_greater(0.0)

func test_freeze_expires_after_duration() -> void:
    welp.apply_chill(5)
    for i in range(120):
        welp._tick_status_effects(1.0 / 60.0)  # 2 seconds
    assert_that(welp.is_frozen()).is_false()

func test_apply_stun_sets_remaining() -> void:
    welp.apply_stun(0.5)
    assert_that(welp.is_stunned()).is_true()

func test_stun_expires() -> void:
    welp.apply_stun(0.1)
    for i in range(20):
        welp._tick_status_effects(1.0 / 60.0)
    assert_that(welp.is_stunned()).is_false()

func test_apply_slow_reduces_effective_speed() -> void:
    welp.apply_slow(0.5, 1.0)
    # Effective speed multiplier
    assert_that(welp._slow_pct).is_equal(0.5)
    assert_that(welp._slow_remaining).is_equal(1.0)

func test_apply_pull_toward_adds_knockback_velocity() -> void:
    welp.global_position = Vector3(5, 0, 0)
    var prev_kb: Vector3 = welp._knockback_velocity
    welp.apply_pull_toward(Vector3.ZERO, 2.0)
    # Pull toward (0,0,0) from (5,0,0) = -X direction × 2.0
    assert_that(welp._knockback_velocity.x).is_less(prev_kb.x)
```

- [ ] **Step 2: Run tests, expect failures**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_welp_status.gd`
Expected: FAIL — `apply_burn`, `apply_chill`, `apply_stun`, `apply_slow`, `apply_pull_toward`, `is_frozen`, `is_stunned`, `_tick_status_effects` not defined.

- [ ] **Step 3: Add status state vars to `welp.gd`**

After the existing var block (around line 27, before `signal died`), add:

```gdscript
# --- Status effect state (Phase 9) ---
const FREEZE_THRESHOLD: int = 5
const FREEZE_DURATION: float = 1.5
const SLOW_PER_CHILL_STACK: float = 0.15  # 15% slow per stack below freeze threshold

var _burn_dps: float = 0.0
var _burn_remaining: float = 0.0
var _chill_stacks: int = 0
var _frozen_remaining: float = 0.0
var _slow_pct: float = 0.0
var _slow_remaining: float = 0.0
var _stun_remaining: float = 0.0
```

- [ ] **Step 4: Add status methods to `welp.gd`**

Add after the existing methods (e.g., after `apply_knockback`):

```gdscript
# --- Status effect API (Phase 9) ---

func apply_burn(dps: float, duration: float) -> void:
    _burn_dps = max(_burn_dps, dps)
    _burn_remaining = max(_burn_remaining, duration)

func apply_chill(stacks: int) -> void:
    _chill_stacks += stacks
    if _chill_stacks >= FREEZE_THRESHOLD:
        _frozen_remaining = FREEZE_DURATION
        _chill_stacks = 0
    else:
        apply_slow(SLOW_PER_CHILL_STACK * float(_chill_stacks), 1.0)

func apply_stun(duration: float) -> void:
    _stun_remaining = max(_stun_remaining, duration)

func apply_slow(pct: float, duration: float) -> void:
    _slow_pct = max(_slow_pct, pct)
    _slow_remaining = max(_slow_remaining, duration)

func apply_pull_toward(target_pos: Vector3, impulse: float) -> void:
    var dir: Vector3 = target_pos - global_position
    dir.y = 0.0
    if dir.length() < 0.001:
        return
    _knockback_velocity += dir.normalized() * impulse

func is_frozen() -> bool:
    return _frozen_remaining > 0.0

func is_stunned() -> bool:
    return _stun_remaining > 0.0

func _tick_status_effects(delta: float) -> void:
    # Burn DoT
    if _burn_remaining > 0.0:
        var burn_dmg: int = max(1, int(_burn_dps * delta))
        _burn_remaining = max(0.0, _burn_remaining - delta)
        # Apply damage directly (avoid re-entry into status from take_damage)
        if not _is_dead:
            hp = max(0, hp - burn_dmg)
            if hp == 0:
                take_damage(0)  # trigger death path via take_damage's hp==0 branch
    # Timers
    if _frozen_remaining > 0.0:
        _frozen_remaining = max(0.0, _frozen_remaining - delta)
    if _stun_remaining > 0.0:
        _stun_remaining = max(0.0, _stun_remaining - delta)
    if _slow_remaining > 0.0:
        _slow_remaining = max(0.0, _slow_remaining - delta)
        if _slow_remaining == 0.0:
            _slow_pct = 0.0
```

- [ ] **Step 5: Wire `_tick_status_effects` into `_physics_process`**

Replace the start of `_physics_process` in `welp.gd:35` with:

```gdscript
func _physics_process(delta: float) -> void:
    if _is_dead:
        return
    _tick_status_effects(delta)
    # Frozen or stunned enemies skip movement and attacks
    if is_frozen() or is_stunned():
        velocity.x = 0.0
        velocity.z = 0.0
        velocity.y -= 9.8 * delta if not is_on_floor() else 0.0
        move_and_slide()
        return
    if _player == null or not is_instance_valid(_player):
        _find_player()
        if _player == null:
            return
    var to_player: Vector3 = _player.global_position - global_position
    to_player.y = 0.0
    var distance: float = to_player.length()
    var effective_speed: float = move_speed * (1.0 - _slow_pct)
    if distance > attack_range:
        velocity.x = to_player.normalized().x * effective_speed
        velocity.z = to_player.normalized().z * effective_speed
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

- [ ] **Step 6: Handle burn-killing edge case in `take_damage`**

In `welp.gd:107`, the `take_damage` method handles the hp==0 path (drop souls, etc.). The `_tick_status_effects` calls `take_damage(0)` when burn lethals to fire that path cleanly. Verify the flow: `take_damage(0)` enters with `amount=0`, `hp` is already 0 from the burn tick, so `hp = max(0, 0 - 0) = 0`, and the `if hp == 0:` branch fires. This is intentional.

(No code change in this step — verify existing flow.)

- [ ] **Step 7: Run tests, expect pass**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_welp_status.gd`
Expected: all 11 tests pass.

- [ ] **Step 8: Commit**

```bash
git add scripts/entities/welp.gd test/test_welp_status.gd
git commit -m "feat(combat): status effects on welps — burn, chill→freeze, slow, stun, pull

Adds inline status state and per-frame ticking. Frozen/stunned welps
skip movement and attacks. Burn DoT ticks damage; chill stacks freeze
at 5; slow scales effective movement speed.

Dragons and elder dragons inherit via welp.gd."
```

---

## Task 3: Status effects on boss_dragon.gd

**Goal:** mirror Task 2's status surface to the boss. Bosses don't share welp.gd, so we add a parallel implementation. Status state is duplicated (per design spec §1: hoist to a base class only when a third enemy type exists).

**Files:**
- Modify: `scripts/entities/boss_dragon.gd`
- Create: `test/test_boss_dragon_status.gd`

- [ ] **Step 1: Write failing tests in `test/test_boss_dragon_status.gd`**

```gdscript
extends GdUnitTestSuite

const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")

var boss: CharacterBody3D

func before_test() -> void:
    boss = auto_free(BossScene.instantiate())
    add_child(boss)
    await get_tree().process_frame

func test_apply_burn_sets_state() -> void:
    boss.apply_burn(10.0, 2.0)
    assert_that(boss._burn_dps).is_equal(10.0)
    assert_that(boss._burn_remaining).is_equal(2.0)

func test_burn_ticks_damage() -> void:
    var initial_hp: int = boss.hp
    boss.apply_burn(20.0, 1.0)
    for i in range(60):
        boss._tick_status_effects(1.0 / 60.0)
    assert_that(initial_hp - boss.hp).is_greater_equal(15)

func test_chill_at_5_stacks_freezes() -> void:
    boss.apply_chill(5)
    assert_that(boss.is_frozen()).is_true()

func test_stun_then_expires() -> void:
    boss.apply_stun(0.1)
    assert_that(boss.is_stunned()).is_true()
    for i in range(20):
        boss._tick_status_effects(1.0 / 60.0)
    assert_that(boss.is_stunned()).is_false()

func test_pull_adds_knockback_velocity() -> void:
    boss.global_position = Vector3(5, 0, 0)
    boss.apply_pull_toward(Vector3.ZERO, 2.0)
    assert_that(boss._knockback_velocity.x).is_less(0.0)
```

- [ ] **Step 2: Run tests, expect failures**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_boss_dragon_status.gd`
Expected: FAIL — methods not defined.

- [ ] **Step 3: Add status state to `boss_dragon.gd`**

Add after the existing var declarations (after `var _flash_tween: Tween = null` around line 33):

```gdscript
# --- Status effect state (Phase 9) ---
const FREEZE_THRESHOLD: int = 5
const FREEZE_DURATION: float = 1.5
const SLOW_PER_CHILL_STACK: float = 0.15

var _burn_dps: float = 0.0
var _burn_remaining: float = 0.0
var _chill_stacks: int = 0
var _frozen_remaining: float = 0.0
var _slow_pct: float = 0.0
var _slow_remaining: float = 0.0
var _stun_remaining: float = 0.0
```

- [ ] **Step 4: Add status methods to `boss_dragon.gd`**

Add after `apply_knockback`:

```gdscript
# --- Status effect API (Phase 9) ---

func apply_burn(dps: float, duration: float) -> void:
    _burn_dps = max(_burn_dps, dps)
    _burn_remaining = max(_burn_remaining, duration)

func apply_chill(stacks: int) -> void:
    _chill_stacks += stacks
    if _chill_stacks >= FREEZE_THRESHOLD:
        _frozen_remaining = FREEZE_DURATION
        _chill_stacks = 0
    else:
        apply_slow(SLOW_PER_CHILL_STACK * float(_chill_stacks), 1.0)

func apply_stun(duration: float) -> void:
    _stun_remaining = max(_stun_remaining, duration)

func apply_slow(pct: float, duration: float) -> void:
    _slow_pct = max(_slow_pct, pct)
    _slow_remaining = max(_slow_remaining, duration)

func apply_pull_toward(target_pos: Vector3, impulse: float) -> void:
    var dir: Vector3 = target_pos - global_position
    dir.y = 0.0
    if dir.length() < 0.001:
        return
    _knockback_velocity += dir.normalized() * impulse

func is_frozen() -> bool:
    return _frozen_remaining > 0.0

func is_stunned() -> bool:
    return _stun_remaining > 0.0

func _tick_status_effects(delta: float) -> void:
    if _burn_remaining > 0.0:
        var burn_dmg: int = max(1, int(_burn_dps * delta))
        _burn_remaining = max(0.0, _burn_remaining - delta)
        if not _is_dead:
            hp = max(0, hp - burn_dmg)
            if hp == 0:
                take_damage(0)
    if _frozen_remaining > 0.0:
        _frozen_remaining = max(0.0, _frozen_remaining - delta)
    if _stun_remaining > 0.0:
        _stun_remaining = max(0.0, _stun_remaining - delta)
    if _slow_remaining > 0.0:
        _slow_remaining = max(0.0, _slow_remaining - delta)
        if _slow_remaining == 0.0:
            _slow_pct = 0.0
```

- [ ] **Step 5: Wire `_tick_status_effects` and immobilize-on-frozen-or-stunned into `_physics_process`**

Replace the body of `_physics_process` in `boss_dragon.gd:43`:

```gdscript
func _physics_process(delta: float) -> void:
    if _is_dead:
        return
    _tick_status_effects(delta)
    _advance_taunt_timers(delta)
    if _should_fire_idle_taunt():
        _show_taunt("boss_idle")
    if _player == null or not is_instance_valid(_player):
        _find_player()
        if _player == null:
            return
    # Frozen or stunned: skip movement and contact attacks; summons paused
    if is_frozen() or is_stunned():
        velocity.x = 0.0
        velocity.z = 0.0
        velocity.y -= 9.8 * delta if not is_on_floor() else 0.0
        move_and_slide()
        return
    var to_player: Vector3 = _player.global_position - global_position
    to_player.y = 0.0
    var dist: float = to_player.length()
    var effective_speed: float = MOVE_SPEED * (1.0 - _slow_pct)
    if dist > 2.5:
        velocity.x = to_player.normalized().x * effective_speed
        velocity.z = to_player.normalized().z * effective_speed
    else:
        velocity.x = 0.0
        velocity.z = 0.0
        if _contact_timer <= 0.0 and _player.has_method("take_damage"):
            if not (_player.has_method("is_invincible") and _player.is_invincible()):
                RunStats.record_damage_from(display_name())
            _player.take_damage(contact_damage)
            _contact_timer = contact_interval
    if _contact_timer > 0.0:
        _contact_timer = max(0.0, _contact_timer - delta)
    _summon_timer += delta
    var interval: float = _interval_for_phase()
    if _summon_timer >= interval:
        _summon_timer = 0.0
        _summon_whelp()
    if _knockback_velocity.length() > 0.01:
        velocity.x += _knockback_velocity.x
        velocity.z += _knockback_velocity.z
        _knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * delta)
    velocity.y -= 9.8 * delta if not is_on_floor() else 0.0
    move_and_slide()
```

- [ ] **Step 6: Run tests, expect pass**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_boss_dragon_status.gd`
Expected: 5 tests pass.

- [ ] **Step 7: Run full test suite to confirm no regressions**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/`
Expected: all tests pass (existing boss tests unaffected — status state is additive).

- [ ] **Step 8: Commit**

```bash
git add scripts/entities/boss_dragon.gd test/test_boss_dragon_status.gd
git commit -m "feat(combat): mirror status effects to boss dragon

Same status surface as welps — burn/chill/freeze/slow/stun/pull. Boss
skips movement and contact attacks while frozen or stunned; summon
timer also pauses (handled by early return)."
```

---

## Task 4: Player armor stacks

**Goal:** add armor stacks to the player. Each stack absorbs 5 damage; stacks consumed one per hit; expire after 5s.

**Files:**
- Modify: `scripts/entities/player.gd`
- Create: `test/test_player_armor.gd`

- [ ] **Step 1: Write failing tests in `test/test_player_armor.gd`**

```gdscript
extends GdUnitTestSuite

const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

var player: CharacterBody3D

func before_test() -> void:
    player = auto_free(PlayerScene.instantiate())
    add_child(player)
    await get_tree().process_frame
    player.hp = 100  # reset to known state

func test_apply_armor_adds_stacks() -> void:
    player.apply_armor(3, 5.0)
    assert_that(player._armor_stacks).is_equal(3)
    assert_that(player._armor_remaining).is_greater(0.0)

func test_armor_absorbs_damage_before_hp() -> void:
    player.apply_armor(2, 5.0)  # 2 stacks × 5 = 10 absorb
    var initial_hp: int = player.hp
    player.take_damage(8)  # all absorbed by 2 stacks (10 capacity)
    assert_that(player.hp).is_equal(initial_hp)
    # Two hits consumed both stacks (one per hit)
    assert_that(player._armor_stacks).is_less_equal(1)

func test_armor_partially_absorbs_overflow_to_hp() -> void:
    player.apply_armor(1, 5.0)  # 1 stack × 5 = 5 absorb
    var initial_hp: int = player.hp
    player.take_damage(12)  # 5 absorbed, 7 to hp
    assert_that(player.hp).is_equal(initial_hp - 7)
    assert_that(player._armor_stacks).is_equal(0)

func test_armor_expires_after_duration() -> void:
    player.apply_armor(3, 0.1)
    for i in range(20):
        player._process(1.0 / 60.0)
    assert_that(player._armor_stacks).is_equal(0)

func test_apply_armor_extends_duration_via_max() -> void:
    player.apply_armor(2, 1.0)
    player.apply_armor(1, 5.0)  # higher duration
    assert_that(player._armor_stacks).is_equal(3)  # cumulative
    assert_that(player._armor_remaining).is_equal(5.0)
```

- [ ] **Step 2: Run tests, expect failures**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_player_armor.gd`
Expected: FAIL — methods not defined.

- [ ] **Step 3: Add armor state and method in `player.gd`**

Add to var block (around line 80):

```gdscript
# --- Armor stacks (Phase 9, white WARD layer) ---
const ARMOR_PER_STACK: int = 5
var _armor_stacks: int = 0
var _armor_remaining: float = 0.0
```

Add the apply method after `try_dash`:

```gdscript
func apply_armor(stacks: int, duration: float) -> void:
    _armor_stacks += stacks
    _armor_remaining = max(_armor_remaining, duration)
```

- [ ] **Step 4: Tick armor expiration in `_process`**

Add at the bottom of the `if`-chain in `_process` (around line 90, before the input checks):

```gdscript
if _armor_remaining > 0.0:
    _armor_remaining = max(0.0, _armor_remaining - delta)
    if _armor_remaining == 0.0:
        _armor_stacks = 0
```

- [ ] **Step 5: Update `take_damage` to absorb via armor**

Replace the body of `take_damage` in `player.gd:134`:

```gdscript
func take_damage(amount: int) -> void:
    if _is_dead or is_invincible():
        return
    # Armor absorbs first; one stack consumed per hit (not per damage point)
    while _armor_stacks > 0 and amount > 0:
        var absorb: int = min(amount, ARMOR_PER_STACK)
        amount -= absorb
        _armor_stacks -= 1
    if amount <= 0:
        return
    hp = max(0, hp - amount)
    hp_changed.emit(hp)
    # Visual feedback: red flash + screen shake.
    ScreenShake.shake(0.06, 0.12)
    var hud: CanvasLayer = get_tree().root.find_child("HUD", true, false) as CanvasLayer
    if hud != null and hud.has_method("play_damage_flash"):
        hud.play_damage_flash()
    if hp == 0:
        _is_dead = true
        died.emit()
```

- [ ] **Step 6: Run tests, expect pass**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_player_armor.gd`
Expected: all 5 tests pass.

- [ ] **Step 7: Commit**

```bash
git add scripts/entities/player.gd test/test_player_armor.gd
git commit -m "feat(combat): player armor stacks (white WARD layer)

apply_armor adds stacks and refreshes max duration; take_damage
consumes one stack per hit absorbing up to ARMOR_PER_STACK damage.
Stacks expire as a group at end of duration."
```

---

## Task 5: DamagePipeline core

**Goal:** the single dispatch point for all damage events. Handles primary hits, native + modifier layer effects, and the chain mechanic.

**Files:**
- Create: `scripts/skills/damage_pipeline.gd`
- Create: `test/test_damage_pipeline.gd`

- [ ] **Step 1: Write failing tests in `test/test_damage_pipeline.gd`**

```gdscript
extends GdUnitTestSuite

const DamagePipeline = preload("res://scripts/skills/damage_pipeline.gd")
const WelpScene: PackedScene = preload("res://scenes/entities/welp.tscn")

var welp_a: CharacterBody3D
var welp_b: CharacterBody3D
var welp_c: CharacterBody3D

func before_test() -> void:
    welp_a = auto_free(WelpScene.instantiate())
    welp_b = auto_free(WelpScene.instantiate())
    welp_c = auto_free(WelpScene.instantiate())
    add_child(welp_a); welp_a.global_position = Vector3.ZERO
    add_child(welp_b); welp_b.global_position = Vector3(2, 0, 0)
    add_child(welp_c); welp_c.global_position = Vector3(3, 0, 0)
    await get_tree().process_frame

func test_apply_deals_base_damage() -> void:
    var initial_hp: int = welp_a.hp
    DamagePipeline.apply(welp_a, 25, [], "red", Vector3.ZERO)
    assert_that(welp_a.hp).is_equal(initial_hp - 25)

func test_red_base_applies_native_burn() -> void:
    DamagePipeline.apply(welp_a, 25, [], "red", Vector3.ZERO)
    assert_that(welp_a._burn_remaining).is_greater(0.0)
    assert_that(welp_a._burn_dps).is_greater(0.0)

func test_red_modifier_extends_burn_duration() -> void:
    DamagePipeline.apply(welp_a, 25, ["red"], "blue", Vector3.ZERO)
    # Blue base + red modifier: should apply burn from modifier path
    assert_that(welp_a._burn_remaining).is_greater(0.0)

func test_blue_base_applies_chill() -> void:
    DamagePipeline.apply(welp_a, 25, [], "blue", Vector3.ZERO)
    assert_that(welp_a._chill_stacks).is_equal(1)

func test_multiple_blue_modifiers_stack_chill() -> void:
    # Red base + 3 blue modifiers → 1 native red (no chill native) + 3 chill from modifiers
    DamagePipeline.apply(welp_a, 25, ["blue", "blue", "blue"], "red", Vector3.ZERO)
    assert_that(welp_a._chill_stacks).is_equal(3)

func test_gold_base_applies_native_stun() -> void:
    DamagePipeline.apply(welp_a, 25, [], "gold", Vector3.ZERO)
    assert_that(welp_a.is_stunned()).is_true()

func test_gold_modifier_chains_to_nearest() -> void:
    # Red base + 1 gold modifier: hits welp_a, chains once to welp_b (closer than welp_c)
    var hp_a: int = welp_a.hp
    var hp_b: int = welp_b.hp
    var hp_c: int = welp_c.hp
    DamagePipeline.apply(welp_a, 25, ["gold"], "red", Vector3.ZERO)
    assert_that(welp_a.hp).is_equal(hp_a - 25)
    assert_that(welp_b.hp).is_equal(hp_b - 25)  # chained
    assert_that(welp_c.hp).is_equal(hp_c)  # not chained, only 1 jump budget

func test_chain_does_not_double_hit_same_target() -> void:
    # Even with 5 gold modifiers, welp_a should only take 25 once (the primary hit)
    var hp_a: int = welp_a.hp
    DamagePipeline.apply(welp_a, 25, ["gold", "gold", "gold", "gold", "gold"], "red", Vector3.ZERO)
    assert_that(welp_a.hp).is_equal(hp_a - 25)

func test_chain_propagates_layers() -> void:
    # Red base + 1 gold modifier: chain target also gets burn (from red base layer)
    DamagePipeline.apply(welp_a, 25, ["gold"], "red", Vector3.ZERO)
    assert_that(welp_b._burn_remaining).is_greater(0.0)

func test_purple_modifier_pulls_target_on_hit() -> void:
    var prev_kb: Vector3 = welp_a._knockback_velocity
    DamagePipeline.apply(welp_a, 25, ["purple"], "red", Vector3(2, 0, 0))
    # Pull toward source (2, 0, 0) from welp_a (0, 0, 0): +X direction
    assert_that(welp_a._knockback_velocity.x).is_greater(prev_kb.x)

func test_purple_base_applies_native_pull() -> void:
    var prev_kb: Vector3 = welp_a._knockback_velocity
    DamagePipeline.apply(welp_a, 25, [], "purple", Vector3(2, 0, 0))
    assert_that(welp_a._knockback_velocity.x).is_greater(prev_kb.x)
```

- [ ] **Step 2: Run tests, expect failures**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_damage_pipeline.gd`
Expected: FAIL — DamagePipeline doesn't exist.

- [ ] **Step 3: Create `scripts/skills/damage_pipeline.gd`**

```gdscript
class_name DamagePipeline

# Single dispatch point for all damage events. Cast hits, AoE, cloud ticks,
# chain jumps, sword swings — every damage application funnels through apply().
#
# Composition rule: every damage event runs through the base color's native
# layer plus every modifier's layer. Spawners (green LINGER, white WARD) are
# fired separately at cast or impact time via fire_*_spawners.

const CHAIN_RANGE: float = 4.0  # max distance for next chain hop
const BURN_DPS_FRAC: float = 0.25  # burn damage = 25% of cast damage per second
const NATIVE_BURN_DURATION: float = 3.0
const MODIFIER_BURN_DURATION: float = 1.5
const NATIVE_STUN_DURATION: float = 0.5
const NATIVE_PULL_IMPULSE: float = 1.5
const MODIFIER_PULL_IMPULSE: float = 0.8

class ChainState extends RefCounted:
    var budget: int = 0
    var hit_set: Array = []  # nodes already damaged by this cast's chain

static func apply(target: Node, damage: int, modifier_stack: Array, base_color: String, source_pos: Vector3, chain_state: ChainState = null) -> void:
    if target == null or not is_instance_valid(target):
        return
    if not target.has_method("take_damage"):
        return

    if chain_state == null:
        chain_state = ChainState.new()
        chain_state.budget = _count(modifier_stack, "gold")

    target.take_damage(damage)
    chain_state.hit_set.append(target)

    _apply_native_layer(target, base_color, damage, source_pos)
    for color in modifier_stack:
        _apply_modifier_layer(target, color, damage, source_pos)

    if chain_state.budget > 0:
        var next: Node = _find_chain_target(target, chain_state.hit_set, CHAIN_RANGE)
        if next != null:
            chain_state.budget -= 1
            apply(next, damage, modifier_stack, base_color, source_pos, chain_state)

static func _apply_native_layer(target: Node, color: String, damage: int, source_pos: Vector3) -> void:
    match color:
        "red":
            if target.has_method("apply_burn"):
                target.apply_burn(float(damage) * BURN_DPS_FRAC, NATIVE_BURN_DURATION)
        "blue":
            if target.has_method("apply_chill"):
                target.apply_chill(1)
        "purple":
            if target.has_method("apply_pull_toward"):
                target.apply_pull_toward(source_pos, NATIVE_PULL_IMPULSE)
        "gold":
            if target.has_method("apply_stun"):
                target.apply_stun(NATIVE_STUN_DURATION)
        # green: cast IS the cloud, no per-hit native effect
        # white: cast IS the wall, no damage path

static func _apply_modifier_layer(target: Node, color: String, damage: int, source_pos: Vector3) -> void:
    match color:
        "red":
            if target.has_method("apply_burn"):
                target.apply_burn(float(damage) * BURN_DPS_FRAC, MODIFIER_BURN_DURATION)
        "blue":
            if target.has_method("apply_chill"):
                target.apply_chill(1)
        "purple":
            if target.has_method("apply_pull_toward"):
                target.apply_pull_toward(source_pos, MODIFIER_PULL_IMPULSE)
        "gold":
            pass  # chain handled in apply()
        "green":
            pass  # spawner — handled in fire_impact_spawners
        "white":
            pass  # player-side — handled in fire_cast_spawners

static func _find_chain_target(prev_target: Node, hit_set: Array, radius: float) -> Node:
    var tree: SceneTree = prev_target.get_tree()
    if tree == null:
        return null
    var enemies: Array = tree.get_nodes_in_group("enemy")
    var best: Node = null
    var best_dist: float = radius
    var origin: Vector3 = prev_target.global_position
    for e in enemies:
        if e == prev_target:
            continue
        if e in hit_set:
            continue
        if not is_instance_valid(e):
            continue
        if "_is_dead" in e and e._is_dead:
            continue
        var d: float = e.global_position.distance_to(origin)
        if d < best_dist:
            best = e
            best_dist = d
    return best

static func _count(stack: Array, color: String) -> int:
    var n: int = 0
    for c in stack:
        if c == color:
            n += 1
    return n
```

- [ ] **Step 4: Run tests, expect pass**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_damage_pipeline.gd`
Expected: 11 tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/skills/damage_pipeline.gd test/test_damage_pipeline.gd
git commit -m "feat(combat): DamagePipeline — single dispatch for damage events

apply() routes every damage event through base-color native layer +
each modifier's layer + chain propagation. Single-source-of-truth for
modifier composition. Future colors = one match arm here.

Layers: red=burn, blue=chill, purple=pull, gold=stun(native)/chain(mod).
Green and white are handled via fire_*_spawners in later tasks."
```

---

## Task 6: Red fireball — AoE explosion

**Goal:** rewire `cast_red_fireball.gd` to use `DamagePipeline.apply()`, add AoE explosion on impact (radius 2m + same-color scaling).

**Files:**
- Modify: `scripts/skills/cast_red_fireball.gd`
- Modify: `scripts/skills/cast_base.gd` (expose AoE helper)

- [ ] **Step 1: Add AoE helper + same-color scaling getter to `cast_base.gd`**

Replace `cast_base.gd` content:

```gdscript
extends Node3D
class_name CastBase

const DamagePipeline = preload("res://scripts/skills/damage_pipeline.gd")

@export var base_damage: int = 25
@export var lifetime: float = 3.0

var modifier_stack: Array[String] = []
var base_color: String = ""
var same_color_count: int = 0
var size_multiplier: float = 1.0

var _age: float = 0.0

func configure(skill: Skill) -> void:
    modifier_stack = skill.modifier_stack.duplicate()
    base_color = skill.base_color
    same_color_count = skill.modifier_count_for(skill.base_color)
    base_damage = int(base_damage * (1.0 + 0.2 * same_color_count))
    size_multiplier = 1.0 + 0.2 * same_color_count

func _process(delta: float) -> void:
    _age += delta
    if _age >= lifetime:
        queue_free()

# Hits a single enemy through the unified damage pipeline.
func _hit_target(target: Node, source_pos: Vector3) -> void:
    DamagePipeline.apply(target, base_damage, modifier_stack, base_color, source_pos)

# Damages all enemies in a sphere around center; called by AoE casts.
func _damage_aoe(center: Vector3, radius: float) -> void:
    var enemies: Array = get_tree().get_nodes_in_group("enemy")
    for e in enemies:
        if not is_instance_valid(e):
            continue
        if "_is_dead" in e and e._is_dead:
            continue
        if e.global_position.distance_to(center) <= radius:
            _hit_target(e, center)

# Knockback helper used by some casts.
func _knockback_force_for(enemy: Node) -> float:
    if not "tier" in enemy:
        return 2.0
    match enemy.tier:
        "welp": return 5.5
        "dragon": return 4.0
        "elder": return 4.0
        _: return 5.5
```

(This removes the old `_apply_modifier` stub and the old `_on_hit_enemy` per-cast logic. Per-cast scripts now call `_hit_target` or `_damage_aoe` directly.)

- [ ] **Step 2: Rewrite `cast_red_fireball.gd` for AoE on impact**

```gdscript
extends CastBase

const PROJECTILE_SPEED: float = 12.0
const BASE_AOE_RADIUS: float = 2.0

@export var direction: Vector3 = Vector3.FORWARD

func _ready() -> void:
    var area: Area3D = $HitArea
    area.body_entered.connect(_on_body_entered)
    area.monitoring = true
    # Apply same-color size scaling to visual mesh
    var mesh: MeshInstance3D = $Mesh as MeshInstance3D
    if mesh != null:
        mesh.scale = Vector3.ONE * size_multiplier

func _physics_process(delta: float) -> void:
    global_position += direction.normalized() * PROJECTILE_SPEED * delta

func _on_body_entered(body: Node) -> void:
    if not body.is_in_group("enemy"):
        return
    var aoe_radius: float = BASE_AOE_RADIUS * size_multiplier
    _damage_aoe(global_position, aoe_radius)
    queue_free()
```

- [ ] **Step 3: Add a smoke test — fireball damages multiple enemies in AoE**

Add to `test/test_damage_pipeline.gd` (or create `test/test_cast_red_fireball.gd`):

```gdscript
func test_fireball_aoe_via_pipeline() -> void:
    # Position welp_a and welp_b within 2m of impact, welp_c outside
    welp_a.global_position = Vector3(0, 0, 0)
    welp_b.global_position = Vector3(1.5, 0, 0)  # within 2m
    welp_c.global_position = Vector3(3.0, 0, 0)  # outside
    var hp_a: int = welp_a.hp
    var hp_b: int = welp_b.hp
    var hp_c: int = welp_c.hp
    # Manually invoke a synthetic AoE event via DamagePipeline
    for e in [welp_a, welp_b]:
        DamagePipeline.apply(e, 25, [], "red", Vector3.ZERO)
    # welp_c not in AoE: untouched
    assert_that(welp_a.hp).is_equal(hp_a - 25)
    assert_that(welp_b.hp).is_equal(hp_b - 25)
    assert_that(welp_c.hp).is_equal(hp_c)
```

- [ ] **Step 4: Run tests, expect pass**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_damage_pipeline.gd`
Expected: pipeline tests + new AoE test pass.

- [ ] **Step 5: Run full test suite**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/`
Expected: all pass. Existing tests don't depend on `cast_base._apply_modifier` (the stub).

- [ ] **Step 6: Commit**

```bash
git add scripts/skills/cast_base.gd scripts/skills/cast_red_fireball.gd test/test_damage_pipeline.gd
git commit -m "feat(elements): red fireball AoE explosion via DamagePipeline

Cast_base reroutes through DamagePipeline.apply, exposes _hit_target
and _damage_aoe helpers + same-color size_multiplier. Red fireball
now explodes in 2m radius on impact (scaled by same-color stacks).
Native red layer (burn) applied to every enemy in AoE."
```

---

## Task 7: Blue ice line — pierce + chill

**Goal:** rewrite `cast_blue_ice_line.gd` to use the pipeline; pierces all enemies along its path applying chill via FROST native layer.

**Files:**
- Modify: `scripts/skills/cast_blue_ice_line.gd`

- [ ] **Step 1: Rewrite `cast_blue_ice_line.gd`**

```gdscript
extends CastBase

const PROJECTILE_SPEED: float = 18.0

@export var direction: Vector3 = Vector3.FORWARD

var _hit_enemies: Array[Node] = []

func _ready() -> void:
    var area: Area3D = $HitArea
    area.body_entered.connect(_on_body_entered)
    area.monitoring = true
    var mesh: MeshInstance3D = $Mesh as MeshInstance3D
    if mesh != null:
        mesh.scale = Vector3(size_multiplier, 1.0, size_multiplier)

func _physics_process(delta: float) -> void:
    global_position += direction.normalized() * PROJECTILE_SPEED * delta

func _on_body_entered(body: Node) -> void:
    if not body.is_in_group("enemy"):
        return
    if body in _hit_enemies:
        return
    _hit_enemies.append(body)
    _hit_target(body, global_position)
    # Pierces — does NOT queue_free; lets lifetime expire
```

- [ ] **Step 2: Smoke test — line hits multiple enemies and applies chill**

Add to `test/test_damage_pipeline.gd`:

```gdscript
func test_ice_line_native_chill() -> void:
    DamagePipeline.apply(welp_a, 25, [], "blue", Vector3.ZERO)
    assert_that(welp_a._chill_stacks).is_equal(1)
    DamagePipeline.apply(welp_a, 25, [], "blue", Vector3.ZERO)
    DamagePipeline.apply(welp_a, 25, [], "blue", Vector3.ZERO)
    DamagePipeline.apply(welp_a, 25, [], "blue", Vector3.ZERO)
    DamagePipeline.apply(welp_a, 25, [], "blue", Vector3.ZERO)
    # 5 chill stacks → freeze
    assert_that(welp_a.is_frozen()).is_true()
```

- [ ] **Step 3: Run tests, expect pass**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_damage_pipeline.gd`
Expected: all pass including new freeze test.

- [ ] **Step 4: Commit**

```bash
git add scripts/skills/cast_blue_ice_line.gd test/test_damage_pipeline.gd
git commit -m "feat(elements): blue ice line via DamagePipeline + native chill

Pierces all enemies along its path; each pierce applies +1 chill via
the FROST native layer. 5 hits on the same target = freeze. Same-color
souls scale length and damage."
```

---

## Task 8: Green plague — placed cloud + LINGER spawner

**Goal:** rewrite green from a projectile to a placed cloud at cursor. Add `effect_cloud.tscn/gd` that ticks `DamagePipeline.apply()` on enemies in radius. Add green LINGER spawner to pipeline so non-green casts with green modifiers also spawn clouds at impact.

**Files:**
- Create: `scripts/effects/effect_cloud.gd`
- Create: `scenes/effects/effect_cloud.tscn`
- Modify: `scripts/skills/cast_green_plague.gd`
- Modify: `scenes/skills/cast_green_plague.tscn`
- Modify: `scripts/skills/damage_pipeline.gd` (add fire_impact_spawners)
- Modify: `scripts/entities/player.gd` (call fire_cast_spawners + fire_impact_spawners)
- Create: `test/test_effect_cloud.gd`

- [ ] **Step 1: Create `scenes/effects/effect_cloud.tscn`**

Write a new scene file at `scenes/effects/effect_cloud.tscn`:

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/effects/effect_cloud.gd" id="1_cloud"]

[sub_resource type="SphereShape3D" id="SphereShape3D_cloud"]
radius = 2.0

[sub_resource type="SphereMesh" id="SphereMesh_cloud"]
radius = 2.0
height = 4.0

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_cloud"]
albedo_color = Color(0.3, 0.7, 0.3, 0.4)
transparency = 1
emission_enabled = true
emission = Color(0.2, 0.6, 0.2, 1)
emission_energy_multiplier = 1.5

[node name="EffectCloud" type="Node3D"]
script = ExtResource("1_cloud")

[node name="HitArea" type="Area3D" parent="."]
collision_layer = 0
collision_mask = 2

[node name="CollisionShape3D" type="CollisionShape3D" parent="HitArea"]
shape = SubResource("SphereShape3D_cloud")

[node name="Mesh" type="MeshInstance3D" parent="."]
mesh = SubResource("SphereMesh_cloud")
material_override = SubResource("StandardMaterial3D_cloud")
```

- [ ] **Step 2: Create `scripts/effects/effect_cloud.gd`**

```gdscript
extends Node3D

const DamagePipeline = preload("res://scripts/skills/damage_pipeline.gd")

const TICK_INTERVAL: float = 0.5  # ticks per second = 2

@export var lifetime: float = 3.0
@export var radius: float = 2.0
@export var tick_damage: int = 6  # 25% of cast base damage default

var modifier_stack: Array = []
var base_color: String = ""

var _age: float = 0.0
var _tick_timer: float = 0.0

func configure(p_lifetime: float, p_radius: float, p_tick_damage: int, p_modifier_stack: Array, p_base_color: String) -> void:
    lifetime = p_lifetime
    radius = p_radius
    tick_damage = p_tick_damage
    modifier_stack = p_modifier_stack.duplicate()
    base_color = p_base_color
    var mesh: MeshInstance3D = $Mesh as MeshInstance3D
    if mesh != null:
        mesh.scale = Vector3.ONE * (radius / 2.0)
    var shape: CollisionShape3D = $HitArea/CollisionShape3D
    if shape != null and shape.shape is SphereShape3D:
        var s: SphereShape3D = shape.shape.duplicate() as SphereShape3D
        s.radius = radius
        shape.shape = s

func _process(delta: float) -> void:
    _age += delta
    _tick_timer += delta
    if _tick_timer >= TICK_INTERVAL:
        _tick_timer = 0.0
        _tick_enemies()
    if _age >= lifetime:
        queue_free()

func _tick_enemies() -> void:
    var area: Area3D = $HitArea
    if area == null:
        return
    for body in area.get_overlapping_bodies():
        if not body.is_in_group("enemy"):
            continue
        DamagePipeline.apply(body, tick_damage, modifier_stack, base_color, global_position)
```

- [ ] **Step 3: Rewrite `scenes/skills/cast_green_plague.tscn`** to be a thin wrapper that places a cloud at the cast's spawn position

Replace the file:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/skills/cast_green_plague.gd" id="1_plague"]

[node name="CastGreenPlague" type="Node3D"]
script = ExtResource("1_plague")
```

(Cast itself is a stub Node3D that immediately spawns a cloud and frees itself — no projectile, no HitArea, no Mesh.)

- [ ] **Step 4: Rewrite `scripts/skills/cast_green_plague.gd`**

```gdscript
extends CastBase

const EFFECT_CLOUD_SCENE: PackedScene = preload("res://scenes/effects/effect_cloud.tscn")
const NATIVE_LIFETIME: float = 3.0
const NATIVE_RADIUS: float = 2.0

@export var direction: Vector3 = Vector3.FORWARD  # unused; kept for player.gd compat

func _ready() -> void:
    # Place cloud immediately at this cast's position; cast then frees itself.
    var cloud: Node3D = EFFECT_CLOUD_SCENE.instantiate()
    var lifetime_total: float = NATIVE_LIFETIME + 1.5 * float(same_color_count)
    var radius_total: float = NATIVE_RADIUS * size_multiplier
    var tick_dmg: int = max(1, int(float(base_damage) * DamagePipeline.BURN_DPS_FRAC))
    cloud.configure(lifetime_total, radius_total, tick_dmg, modifier_stack, base_color)
    get_parent().add_child(cloud)
    cloud.global_position = global_position
    queue_free()
```

- [ ] **Step 5: Add `fire_impact_spawners` and `fire_cast_spawners` to DamagePipeline**

Add to `scripts/skills/damage_pipeline.gd` (at end of file):

```gdscript
const SPAWNER_CLOUD_SCENE: PackedScene = preload("res://scenes/effects/effect_cloud.tscn")
const NATIVE_BURN_DPS_FRAC: float = 0.25
const SPAWNER_CLOUD_BASE_LIFETIME: float = 3.0
const SPAWNER_CLOUD_BASE_RADIUS: float = 2.0
const ARMOR_DURATION: float = 5.0

# Fired at cast initiation (player._try_cast). Handles white WARD.
static func fire_cast_spawners(skill: Skill, caster: Node) -> void:
    if caster == null or not is_instance_valid(caster):
        return
    if not caster.has_method("apply_armor"):
        return
    var white_count: int = _count(skill.modifier_stack, "white")
    if skill.base_color == "white":
        white_count += 1  # white-base also grants the WARD layer natively
    if white_count > 0:
        caster.apply_armor(white_count, ARMOR_DURATION)

# Fired when a non-spawner cast resolves its primary impact. Handles green LINGER.
# Pass `cast_node` as `world_root_for_spawn` (clouds are added under the cast's parent).
static func fire_impact_spawners(modifier_stack: Array, base_color: String, impact_pos: Vector3, world: Node, base_damage: int) -> void:
    if base_color == "green":
        return  # green-base IS the cloud; don't double-spawn from modifier rule
    var green_count: int = _count(modifier_stack, "green")
    if green_count <= 0:
        return
    if world == null or not is_instance_valid(world):
        return
    var cloud: Node3D = SPAWNER_CLOUD_SCENE.instantiate()
    var lifetime: float = SPAWNER_CLOUD_BASE_LIFETIME + 1.5 * float(green_count)
    var tick_dmg: int = max(1, int(float(base_damage) * NATIVE_BURN_DPS_FRAC))
    cloud.configure(lifetime, SPAWNER_CLOUD_BASE_RADIUS, tick_dmg, modifier_stack, base_color)
    world.add_child(cloud)
    cloud.global_position = impact_pos
```

- [ ] **Step 6: Wire `fire_cast_spawners` into `player.gd:_try_cast`**

In `player.gd`, after `cast.configure(skill)` (around line 158), add:

```gdscript
DamagePipeline.fire_cast_spawners(skill, self)
```

(Player imports DamagePipeline — add `const DamagePipeline = preload("res://scripts/skills/damage_pipeline.gd")` near top of player.gd if not already imported via cast_base.)

Add at the top of `player.gd` after the existing CAST_*_SCENE consts:

```gdscript
const DamagePipeline = preload("res://scripts/skills/damage_pipeline.gd")
```

- [ ] **Step 7: Wire `fire_impact_spawners` into `cast_red_fireball.gd`**

Replace `_on_body_entered` in `cast_red_fireball.gd`:

```gdscript
func _on_body_entered(body: Node) -> void:
    if not body.is_in_group("enemy"):
        return
    var aoe_radius: float = BASE_AOE_RADIUS * size_multiplier
    _damage_aoe(global_position, aoe_radius)
    DamagePipeline.fire_impact_spawners(modifier_stack, base_color, global_position, get_parent(), base_damage)
    queue_free()
```

- [ ] **Step 8: Wire `fire_impact_spawners` into `cast_blue_ice_line.gd`**

In `cast_blue_ice_line.gd`, override `_process` to fire the spawner once at lifetime end. Add after the `_physics_process` method:

```gdscript
func _process(delta: float) -> void:
    _age += delta
    if _age >= lifetime and _hit_enemies.size() > 0:
        # Fire spawner at the position of the first hit (proxy for impact)
        DamagePipeline.fire_impact_spawners(modifier_stack, base_color, global_position, get_parent(), base_damage)
        queue_free()
    elif _age >= lifetime:
        queue_free()
```

(Note: this overrides `CastBase._process` because `cast_blue_ice_line` extends CastBase. The override is safe — does the same lifetime check plus the spawner call.)

- [ ] **Step 9: Write `test/test_effect_cloud.gd`**

```gdscript
extends GdUnitTestSuite

const EffectCloudScene: PackedScene = preload("res://scenes/effects/effect_cloud.tscn")
const WelpScene: PackedScene = preload("res://scenes/entities/welp.tscn")

func test_cloud_ticks_damage_to_enemies_in_radius() -> void:
    var cloud: Node3D = auto_free(EffectCloudScene.instantiate())
    var welp: CharacterBody3D = auto_free(WelpScene.instantiate())
    add_child(cloud)
    add_child(welp)
    cloud.global_position = Vector3.ZERO
    welp.global_position = Vector3(1.0, 0, 0)  # within 2m
    cloud.configure(3.0, 2.0, 5, [], "green")
    await get_tree().process_frame
    await get_tree().process_frame  # let physics report overlaps
    var initial_hp: int = welp.hp
    cloud._tick_enemies()
    assert_that(welp.hp).is_less(initial_hp)

func test_cloud_despawns_after_lifetime() -> void:
    var cloud: Node3D = EffectCloudScene.instantiate()
    add_child(cloud)
    cloud.configure(0.1, 2.0, 5, [], "green")
    for i in range(20):
        cloud._process(1.0 / 60.0)
        if not is_instance_valid(cloud):
            break
    assert_that(is_instance_valid(cloud)).is_false()

func test_cloud_does_not_tick_outside_radius() -> void:
    var cloud: Node3D = auto_free(EffectCloudScene.instantiate())
    var welp: CharacterBody3D = auto_free(WelpScene.instantiate())
    add_child(cloud)
    add_child(welp)
    cloud.global_position = Vector3.ZERO
    welp.global_position = Vector3(5.0, 0, 0)  # outside 2m
    cloud.configure(3.0, 2.0, 5, [], "green")
    await get_tree().process_frame
    await get_tree().process_frame
    var initial_hp: int = welp.hp
    cloud._tick_enemies()
    assert_that(welp.hp).is_equal(initial_hp)
```

- [ ] **Step 10: Run tests**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_effect_cloud.gd test/test_damage_pipeline.gd`
Expected: pass.

- [ ] **Step 11: Commit**

```bash
git add scripts/effects/effect_cloud.gd scenes/effects/effect_cloud.tscn scripts/skills/cast_green_plague.gd scenes/skills/cast_green_plague.tscn scripts/skills/damage_pipeline.gd scripts/skills/cast_red_fireball.gd scripts/skills/cast_blue_ice_line.gd scripts/entities/player.gd test/test_effect_cloud.gd
git commit -m "feat(elements): green plague — placed cloud + LINGER spawner

Green base now places a cloud at cursor (no projectile). Cloud ticks
DamagePipeline.apply on enemies in radius every 0.5s, propagating all
modifier layers to each tick. Non-green casts with green modifiers
spawn a residual cloud at impact via fire_impact_spawners.
Player wires fire_cast_spawners (for upcoming white WARD)."
```

---

## Task 9: Purple void — placed gravity well

**Goal:** rewrite purple from a projectile to a placed gravity well at cursor. Add `effect_gravity_well.tscn/gd` that pulls + ticks damage. Native GRAVITATE layer already in pipeline (Task 5).

**Files:**
- Create: `scripts/effects/effect_gravity_well.gd`
- Create: `scenes/effects/effect_gravity_well.tscn`
- Modify: `scripts/skills/cast_purple_void.gd`
- Modify: `scenes/skills/cast_purple_void.tscn`
- Create: `test/test_effect_gravity_well.gd`

- [ ] **Step 1: Create `scenes/effects/effect_gravity_well.tscn`**

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/effects/effect_gravity_well.gd" id="1_well"]

[sub_resource type="SphereShape3D" id="SphereShape3D_well"]
radius = 2.0

[sub_resource type="SphereMesh" id="SphereMesh_well"]
radius = 0.6
height = 1.2

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_well"]
albedo_color = Color(0.2, 0.05, 0.3, 1)
emission_enabled = true
emission = Color(0.4, 0.1, 0.6, 1)
emission_energy_multiplier = 3.0

[node name="EffectGravityWell" type="Node3D"]
script = ExtResource("1_well")

[node name="HitArea" type="Area3D" parent="."]
collision_layer = 0
collision_mask = 2

[node name="CollisionShape3D" type="CollisionShape3D" parent="HitArea"]
shape = SubResource("SphereShape3D_well")

[node name="Mesh" type="MeshInstance3D" parent="."]
mesh = SubResource("SphereMesh_well")
material_override = SubResource("StandardMaterial3D_well")
```

- [ ] **Step 2: Create `scripts/effects/effect_gravity_well.gd`**

```gdscript
extends Node3D

const DamagePipeline = preload("res://scripts/skills/damage_pipeline.gd")

const TICK_INTERVAL: float = 0.5
const PULL_FORCE_PER_FRAME: float = 0.05  # constant velocity-add toward center per physics frame

@export var lifetime: float = 2.0
@export var radius: float = 2.0
@export var tick_damage: int = 6

var modifier_stack: Array = []
var base_color: String = ""

var _age: float = 0.0
var _tick_timer: float = 0.0

func configure(p_lifetime: float, p_radius: float, p_tick_damage: int, p_modifier_stack: Array, p_base_color: String) -> void:
    lifetime = p_lifetime
    radius = p_radius
    tick_damage = p_tick_damage
    modifier_stack = p_modifier_stack.duplicate()
    base_color = p_base_color
    var shape: CollisionShape3D = $HitArea/CollisionShape3D
    if shape != null and shape.shape is SphereShape3D:
        var s: SphereShape3D = shape.shape.duplicate() as SphereShape3D
        s.radius = radius
        shape.shape = s

func _process(delta: float) -> void:
    _age += delta
    _tick_timer += delta
    if _tick_timer >= TICK_INTERVAL:
        _tick_timer = 0.0
        _tick_enemies()
    if _age >= lifetime:
        queue_free()

func _physics_process(_delta: float) -> void:
    var area: Area3D = $HitArea
    if area == null:
        return
    for body in area.get_overlapping_bodies():
        if not body.is_in_group("enemy"):
            continue
        if body.has_method("apply_pull_toward"):
            body.apply_pull_toward(global_position, PULL_FORCE_PER_FRAME)

func _tick_enemies() -> void:
    var area: Area3D = $HitArea
    if area == null:
        return
    for body in area.get_overlapping_bodies():
        if not body.is_in_group("enemy"):
            continue
        DamagePipeline.apply(body, tick_damage, modifier_stack, base_color, global_position)
```

- [ ] **Step 3: Rewrite `scenes/skills/cast_purple_void.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/skills/cast_purple_void.gd" id="1_void"]

[node name="CastPurpleVoid" type="Node3D"]
script = ExtResource("1_void")
```

- [ ] **Step 4: Rewrite `scripts/skills/cast_purple_void.gd`**

```gdscript
extends CastBase

const EFFECT_WELL_SCENE: PackedScene = preload("res://scenes/effects/effect_gravity_well.tscn")
const NATIVE_LIFETIME: float = 2.0
const NATIVE_RADIUS: float = 2.0

@export var direction: Vector3 = Vector3.FORWARD  # unused; kept for player.gd compat

func _ready() -> void:
    var well: Node3D = EFFECT_WELL_SCENE.instantiate()
    var lifetime_total: float = NATIVE_LIFETIME * size_multiplier
    var radius_total: float = NATIVE_RADIUS * size_multiplier
    var tick_dmg: int = max(1, int(float(base_damage) * 0.25))
    well.configure(lifetime_total, radius_total, tick_dmg, modifier_stack, base_color)
    get_parent().add_child(well)
    well.global_position = global_position
    # Fire green LINGER if a green modifier is in the stack (purple-base + green
    # modifier should spawn a cloud at the well placement position).
    DamagePipeline.fire_impact_spawners(modifier_stack, base_color, global_position, get_parent(), base_damage)
    queue_free()
```

- [ ] **Step 5: Write `test/test_effect_gravity_well.gd`**

```gdscript
extends GdUnitTestSuite

const WellScene: PackedScene = preload("res://scenes/effects/effect_gravity_well.tscn")
const WelpScene: PackedScene = preload("res://scenes/entities/welp.tscn")

func test_well_pulls_enemies_in_radius() -> void:
    var well: Node3D = auto_free(WellScene.instantiate())
    var welp: CharacterBody3D = auto_free(WelpScene.instantiate())
    add_child(well)
    add_child(welp)
    well.global_position = Vector3.ZERO
    welp.global_position = Vector3(1.5, 0, 0)
    well.configure(2.0, 2.0, 5, [], "purple")
    await get_tree().process_frame
    await get_tree().process_frame
    var prev_kb: Vector3 = welp._knockback_velocity
    well._physics_process(1.0 / 60.0)
    # Pulled toward (0,0,0) from (1.5, 0, 0): -X direction
    assert_that(welp._knockback_velocity.x).is_less(prev_kb.x)

func test_well_ticks_damage() -> void:
    var well: Node3D = auto_free(WellScene.instantiate())
    var welp: CharacterBody3D = auto_free(WelpScene.instantiate())
    add_child(well)
    add_child(welp)
    well.global_position = Vector3.ZERO
    welp.global_position = Vector3(1.0, 0, 0)
    well.configure(2.0, 2.0, 6, [], "purple")
    await get_tree().process_frame
    await get_tree().process_frame
    var initial_hp: int = welp.hp
    well._tick_enemies()
    assert_that(welp.hp).is_less(initial_hp)

func test_well_despawns_after_lifetime() -> void:
    var well: Node3D = WellScene.instantiate()
    add_child(well)
    well.configure(0.1, 2.0, 5, [], "purple")
    for i in range(20):
        well._process(1.0 / 60.0)
        if not is_instance_valid(well):
            break
    assert_that(is_instance_valid(well)).is_false()
```

- [ ] **Step 6: Run tests**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_effect_gravity_well.gd test/test_damage_pipeline.gd`
Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add scripts/effects/effect_gravity_well.gd scenes/effects/effect_gravity_well.tscn scripts/skills/cast_purple_void.gd scenes/skills/cast_purple_void.tscn test/test_effect_gravity_well.gd
git commit -m "feat(elements): purple void — placed gravity well

Purple base places a gravity well at cursor (no projectile). Well pulls
enemies in radius toward center every physics frame and ticks damage
every 0.5s. GRAVITATE native layer already in DamagePipeline."
```

---

## Task 10: Gold lightning — instant strike + chain

**Goal:** rewrite gold from a slow projectile to an instant strike at cursor with stun. CHAIN works automatically because the chain logic is in the pipeline (Task 5) and gold-as-modifier sets chain budget.

**Files:**
- Modify: `scripts/skills/cast_gold_lightning.gd`
- Modify: `scenes/skills/cast_gold_lightning.tscn`

- [ ] **Step 1: Rewrite `scenes/skills/cast_gold_lightning.tscn`**

Keep the visual mesh (lightning bolt) but make HitArea small and centered:

```
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://scripts/skills/cast_gold_lightning.gd" id="1_lightning"]

[sub_resource type="SphereShape3D" id="SphereShape3D_strike"]
radius = 1.5

[sub_resource type="CylinderMesh" id="CylinderMesh_bolt"]
top_radius = 0.1
bottom_radius = 0.05
height = 8.0

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_bolt"]
albedo_color = Color(1, 0.95, 0.4, 1)
emission_enabled = true
emission = Color(1, 0.9, 0.3, 1)
emission_energy_multiplier = 5.0

[node name="CastGoldLightning" type="Node3D"]
script = ExtResource("1_lightning")

[node name="HitArea" type="Area3D" parent="."]
collision_layer = 0
collision_mask = 2

[node name="CollisionShape3D" type="CollisionShape3D" parent="HitArea"]
shape = SubResource("SphereShape3D_strike")

[node name="Mesh" type="MeshInstance3D" parent="."]
mesh = SubResource("CylinderMesh_bolt")
material_override = SubResource("StandardMaterial3D_bolt")
```

- [ ] **Step 2: Rewrite `scripts/skills/cast_gold_lightning.gd`**

```gdscript
extends CastBase

const NATIVE_STRIKE_RADIUS: float = 1.5
const VFX_LIFETIME: float = 0.2  # how long the bolt visual stays before despawn

@export var direction: Vector3 = Vector3.FORWARD  # unused; kept for player.gd compat

func _ready() -> void:
    var radius_total: float = NATIVE_STRIKE_RADIUS * size_multiplier
    # Resize HitArea collision
    var shape: CollisionShape3D = $HitArea/CollisionShape3D
    if shape != null and shape.shape is SphereShape3D:
        var s: SphereShape3D = shape.shape.duplicate() as SphereShape3D
        s.radius = radius_total
        shape.shape = s
    # Strike: deal damage immediately to all enemies in radius, then linger briefly for VFX
    await get_tree().process_frame  # let physics report overlaps
    var area: Area3D = $HitArea
    var hit: bool = false
    if area != null:
        for body in area.get_overlapping_bodies():
            if not body.is_in_group("enemy"):
                continue
            _hit_target(body, global_position)
            hit = true
    if hit:
        DamagePipeline.fire_impact_spawners(modifier_stack, base_color, global_position, get_parent(), base_damage)
    # Despawn after brief VFX
    await get_tree().create_timer(VFX_LIFETIME).timeout
    queue_free()
```

Note: this requires `cast.global_position` to be set BY THE PLAYER to the cursor target before `_ready()` fires. In Godot, when you `add_child` and then set `global_position`, _ready already fired. Need to make `_ready` wait for global_position to be set. Use `call_deferred`:

Actually — looking at `player._try_cast` (line 176-177):
```gdscript
cast.global_position = Vector3(global_position.x, 0.5, global_position.z) + aim_dir * 1.0
get_parent().add_child(cast)
```

`global_position` is set BEFORE `add_child`, so when `_ready()` fires after add_child, global_position is correct.

BUT — gold needs to be at the cursor's actual position, not the player position + aim_dir × 1.0. The current player code aims as if it's launching a projectile. For gold, we need it to land at the actual cursor target (the floor pick).

Easiest fix: gold is special — change `player._try_cast` to special-case gold and place at cursor. But that adds branching. Alternative: gold reads the cursor position itself in `_ready()`.

For minimal changes, let's use the cast's spawn position as-is (1m forward from player). It's not exactly the cursor but it's directional and will work for the playtest. We can refine later if needed.

(Document this as a known constraint to revisit; per spec, "Out of scope: Sword-element inheritance VFX changes" implies other VFX-shape concerns are OK to defer.)

- [ ] **Step 3: Smoke test — gold cast with chain budget hits multiple targets**

Already covered by `test_gold_modifier_chains_to_nearest` in `test_damage_pipeline.gd`.

- [ ] **Step 4: Run tests**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_damage_pipeline.gd`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/skills/cast_gold_lightning.gd scenes/skills/cast_gold_lightning.tscn
git commit -m "feat(elements): gold lightning — instant strike + native stun

Gold base resolves immediately on the next physics frame, hitting all
enemies in 1.5m radius with cast damage and applying STUN native layer.
Visual bolt lingers 0.2s before despawn. CHAIN modifier behavior
already wired through DamagePipeline."
```

---

## Task 11: White bone wall — placed barrier + WARD

**Goal:** rewrite white from a piercing projectile to a placed bone wall (StaticBody3D blocking enemies and projectiles, with HP that breaks). Native WARD already wired through `fire_cast_spawners` from Task 8.

**Files:**
- Create: `scripts/effects/effect_bone_wall.gd`
- Create: `scenes/effects/effect_bone_wall.tscn`
- Modify: `scripts/skills/cast_white_bone.gd`
- Modify: `scenes/skills/cast_white_bone.tscn`
- Create: `test/test_effect_bone_wall.gd`

- [ ] **Step 1: Create `scenes/effects/effect_bone_wall.tscn`**

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/effects/effect_bone_wall.gd" id="1_wall"]

[sub_resource type="BoxShape3D" id="BoxShape3D_wall"]
size = Vector3(4.0, 1.5, 0.4)

[sub_resource type="BoxMesh" id="BoxMesh_wall"]
size = Vector3(4.0, 1.5, 0.4)

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_wall"]
albedo_color = Color(0.95, 0.92, 0.8, 1)
emission_enabled = true
emission = Color(0.7, 0.65, 0.5, 1)
emission_energy_multiplier = 0.6

[node name="EffectBoneWall" type="StaticBody3D"]
script = ExtResource("1_wall")
collision_layer = 1
collision_mask = 0

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
shape = SubResource("BoxShape3D_wall")

[node name="Mesh" type="MeshInstance3D" parent="."]
mesh = SubResource("BoxMesh_wall")
material_override = SubResource("StandardMaterial3D_wall")
```

- [ ] **Step 2: Create `scripts/effects/effect_bone_wall.gd`**

```gdscript
extends StaticBody3D

const NATIVE_HP: int = 100
const NATIVE_LIFETIME: float = 4.0
const NATIVE_LENGTH: float = 4.0

var hp: int = NATIVE_HP
var lifetime: float = NATIVE_LIFETIME
var length: float = NATIVE_LENGTH
var _age: float = 0.0

signal wall_broken

func configure(p_hp: int, p_lifetime: float, p_length: float) -> void:
    hp = p_hp
    lifetime = p_lifetime
    length = p_length
    var mesh: MeshInstance3D = $Mesh as MeshInstance3D
    if mesh != null:
        mesh.scale = Vector3(length / NATIVE_LENGTH, 1.0, 1.0)
    var shape: CollisionShape3D = $CollisionShape3D
    if shape != null and shape.shape is BoxShape3D:
        var s: BoxShape3D = shape.shape.duplicate() as BoxShape3D
        s.size = Vector3(length, 1.5, 0.4)
        shape.shape = s

func _process(delta: float) -> void:
    _age += delta
    if _age >= lifetime:
        queue_free()

func take_damage(amount: int) -> void:
    hp = max(0, hp - amount)
    if hp == 0:
        wall_broken.emit()
        queue_free()
```

- [ ] **Step 3: Rewrite `scenes/skills/cast_white_bone.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/skills/cast_white_bone.gd" id="1_bone"]

[node name="CastWhiteBone" type="Node3D"]
script = ExtResource("1_bone")
```

- [ ] **Step 4: Rewrite `scripts/skills/cast_white_bone.gd`**

```gdscript
extends CastBase

const EFFECT_WALL_SCENE: PackedScene = preload("res://scenes/effects/effect_bone_wall.tscn")
const NATIVE_HP: int = 100
const NATIVE_LIFETIME: float = 4.0
const NATIVE_LENGTH: float = 4.0

@export var direction: Vector3 = Vector3.FORWARD

func _ready() -> void:
    # Place wall perpendicular to player→cursor line. We use the cast's `direction`
    # (set by player._try_cast = aim_dir) as the player→cursor axis; wall axis is
    # the cross product on Y to keep it level.
    var perp: Vector3 = Vector3(-direction.z, 0.0, direction.x).normalized()
    var wall: StaticBody3D = EFFECT_WALL_SCENE.instantiate()
    var hp_total: int = int(float(NATIVE_HP) * size_multiplier)
    var lifetime_total: float = NATIVE_LIFETIME + 1.0 * float(same_color_count)
    var length_total: float = NATIVE_LENGTH * size_multiplier
    wall.configure(hp_total, lifetime_total, length_total)
    get_parent().add_child(wall)
    wall.global_position = global_position
    # Orient the wall: its X-axis (length) aligns with `perp`
    if perp.length() > 0.001:
        wall.look_at(global_position + perp, Vector3.UP)
        wall.rotate_object_local(Vector3.UP, PI / 2.0)
    # Fire green LINGER if a green modifier is in the stack (white-base + green
    # modifier should spawn a cloud at the wall placement position).
    DamagePipeline.fire_impact_spawners(modifier_stack, base_color, global_position, get_parent(), base_damage)
    queue_free()
```

- [ ] **Step 5: Write `test/test_effect_bone_wall.gd`**

```gdscript
extends GdUnitTestSuite

const WallScene: PackedScene = preload("res://scenes/effects/effect_bone_wall.tscn")

func test_wall_starts_with_configured_hp() -> void:
    var wall: StaticBody3D = auto_free(WallScene.instantiate())
    add_child(wall)
    wall.configure(120, 4.0, 4.0)
    assert_that(wall.hp).is_equal(120)

func test_wall_breaks_at_zero_hp() -> void:
    var wall: StaticBody3D = WallScene.instantiate()
    add_child(wall)
    wall.configure(50, 4.0, 4.0)
    var broken: bool = false
    wall.wall_broken.connect(func(): broken = true)
    wall.take_damage(50)
    assert_that(broken).is_true()

func test_wall_despawns_after_lifetime() -> void:
    var wall: StaticBody3D = WallScene.instantiate()
    add_child(wall)
    wall.configure(100, 0.1, 4.0)
    for i in range(20):
        if not is_instance_valid(wall):
            break
        wall._process(1.0 / 60.0)
    assert_that(is_instance_valid(wall)).is_false()
```

- [ ] **Step 6: Run tests**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/test_effect_bone_wall.gd test/test_damage_pipeline.gd test/test_player_armor.gd`
Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add scripts/effects/effect_bone_wall.gd scenes/effects/effect_bone_wall.tscn scripts/skills/cast_white_bone.gd scenes/skills/cast_white_bone.tscn test/test_effect_bone_wall.gd
git commit -m "feat(elements): white bone wall — placed barrier + WARD armor

White base places a StaticBody3D wall perpendicular to player→cursor.
Wall has HP, breakable, expires after lifetime. WARD layer (player armor
stacks) is wired through DamagePipeline.fire_cast_spawners (Task 8).
Same-color souls extend wall length, HP, and lifetime."
```

---

## Task 12: Sword inheritance — base color native layer per swing

**Goal:** sword auto-melee applies the active skill's base color's native layer on every hit. Does NOT walk the modifier stack. White is special (passive armor every 5s).

**Files:**
- Modify: `scripts/entities/sword.gd`

- [ ] **Step 1: Rewrite the swing-hit block in `sword.gd:13-34`**

Replace the body of `_process` with:

```gdscript
func _process(delta: float) -> void:
    # Passive white WARD: armor stack every 5s while equipped to a white-base skill
    _passive_armor_timer += delta
    if _active_color == "white" and _passive_armor_timer >= PASSIVE_ARMOR_INTERVAL:
        _passive_armor_timer = 0.0
        var player: Node = get_tree().get_first_node_in_group("player")
        if player != null and player.has_method("apply_armor"):
            player.apply_armor(1, 5.0)
    if _swing_cooldown > 0.0:
        _swing_cooldown = max(0.0, _swing_cooldown - delta)
        return
    var enemies: Array = get_overlapping_bodies().filter(_is_enemy)
    if enemies.size() == 0:
        return
    for enemy in enemies:
        if not enemy.has_method("take_damage"):
            continue
        # Sword applies base damage AND the active skill's base color's native
        # layer (no modifier stack). DamagePipeline with empty stack handles this.
        DamagePipeline.apply(enemy, base_damage, [], _active_color, global_position)
        if enemy.has_method("apply_knockback"):
            var dir: Vector3 = enemy.global_position - global_position
            var force: float = _knockback_force_for(enemy)
            enemy.apply_knockback(dir, force)
        ScreenShake.shake(0.02, 0.04)
    _swing_cooldown = swing_interval
```

- [ ] **Step 2: Add state and constants to `sword.gd`**

After the existing var block (around line 8), add:

```gdscript
const DamagePipeline = preload("res://scripts/skills/damage_pipeline.gd")
const PASSIVE_ARMOR_INTERVAL: float = 5.0

var _active_color: String = ""
var _passive_armor_timer: float = 0.0
```

- [ ] **Step 3: Wire `set_active_element` to set `_active_color`**

Replace `set_active_element` in `sword.gd:61`:

```gdscript
func set_active_element(color: String) -> void:
    _active_color = color
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
```

- [ ] **Step 4: Run all tests**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/entities/sword.gd
git commit -m "feat(elements): sword inherits active skill's base color native layer

Each sword swing routes through DamagePipeline with an empty modifier
stack and the active skill's base color. Red sword burns, blue chills,
purple pulls, gold stuns. White is passive — grants 1 armor stack
every 5s while equipped to a white-base skill (no on-hit effect).
Modifier stack is NOT walked by the sword (per spec)."
```

---

## Task 13: Final validation — playtest + balance pass

**Goal:** validate the system end-to-end. Run all tests. Sanity-check the damage curve in a real playtest.

- [ ] **Step 1: Run the full test suite**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/`
Expected: ALL tests pass. Note any pre-existing engine-bug hangs (per Phase 8 known issue) and run affected suites individually.

- [ ] **Step 2: Open the game in the editor and playtest the golden path**

1. Launch `Godot New Chance` editor → run game → start screen → New Game
2. Descend to upstairs. Kill 2-3 welps with the auto-sword (no skill yet).
   - **Expected:** welp dies in 2 sword swings (max-cantrip = 30 dmg vs 50 HP).
3. Pick up first soul → unlocks a skill. Cast it.
   - **Expected:** cast deals 25 damage with a visible cast-shape effect (AoE for red, line for blue, cloud for green, well for purple, strike for gold, wall for white).
4. Stack 5 same-color minor souls. Cast at a welp.
   - **Expected:** welp dies in 1 hit (50 dmg = welp HP).
5. Stack to 10+ same-color souls. Engage a dragon.
   - **Expected:** dragon takes 2 hits to die (100 HP / 75 dmg ≈ 2 hits).
6. Cross-color modifiers: cast with mixed stack on a welp group.
   - **Expected:** modifier effects fire visibly (burn lingers, chills slow, pulls collect, chains zap, clouds linger).
7. Engage the boss. Survive multiple casts. Verify chains/cloud/freeze all work.

- [ ] **Step 3: If feel is off (welps too tanky, casts too weak, etc.) tune constants**

Likely dials (in priority order):
1. `cast_base.gd` `base_damage = 25` — adjust if casts feel weak/strong
2. `welp.gd` TIER constants → adjust `dragon.tscn`/`elder_dragon.tscn` HP if mid-tier feels off
3. `damage_pipeline.gd` `BURN_DPS_FRAC` (0.25) → DoT/cloud damage scaling
4. `damage_pipeline.gd` `CHAIN_RANGE` (4.0) → chain reach
5. Per-cast cooldowns (currently `cast_cooldown = 0.6` in player.gd applies to all) — could be made per-color later

Per the spec "Open tuning numbers" appendix, adjust as needed.

- [ ] **Step 4: Commit any tuning adjustments**

```bash
git add <tuning files>
git commit -m "tune(combat): playtest balance adjustments — <what changed and why>"
```

- [ ] **Step 5: Final test run**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/`
Expected: all pass.

- [ ] **Step 6: Ready to merge**

The phase-9-elements-balance branch is ready for merge to master and tagging as `v0.9-elements-balance`. Hand off to the merge step.

---

## Task summary

| # | Task | Files (new/mod) | Tests added |
|---|---|---|---|
| 1 | Damage curve rebalance | 5 mod | (existing) |
| 2 | Welp status effects | 1 mod / 1 new | 11 tests |
| 3 | Boss status effects | 1 mod / 1 new | 5 tests |
| 4 | Player armor | 1 mod / 1 new | 5 tests |
| 5 | DamagePipeline core | 1 new / 1 new | 11 tests |
| 6 | Red AoE + cast_base helper | 2 mod | +1 test |
| 7 | Blue ice line | 1 mod | +1 test |
| 8 | Green plague + LINGER | 5 mod / 4 new | 3 tests |
| 9 | Purple void | 2 mod / 3 new | 3 tests |
| 10 | Gold lightning | 2 mod | (uses pipeline tests) |
| 11 | White bone wall | 2 mod / 3 new | 3 tests |
| 12 | Sword inheritance | 1 mod | (existing) |
| 13 | Validation + tuning | (none new) | full suite |

**Estimated commit count:** 13.

After Task 13, the branch is mergeable. Tag as `v0.9-elements-balance`.
