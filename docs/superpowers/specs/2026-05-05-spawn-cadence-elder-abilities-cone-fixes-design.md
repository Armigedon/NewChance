# Spawn Cadence + Elder Abilities + Boss Cone Fixes Design

**Goal:** address the playtest pain points from subsystems B and C of the May 2026 gameplay revisit. Dragons and elders pile up too fast pre-descent, elders are flavorless stat-buffed welps, the boss cone is geometrically misaligned and gameplay-irrelevant, and stacking green clouds + purple wells trivializes the boss's breath attacks.

**Context:** Phase 10 reshaped the soul/skill economy to make the in-run wand grow slowly (whelps drop nothing, dragons drop minor souls, elders drop a drafted modifier). That redesign assumed elders would be 2-3 per run. Without spawn-cadence enforcement, a high-heat run can produce 5+ elders bunched together. Separately, the boss fight: the breath cone visually appears centered on the boss instead of with apex-at-boss, the cone is small enough that the player can sidestep without consequence, and stacking green clouds or purple wells fully shuts down breath cones (a hard counter that makes the fight binary). All three problems are localized — the systems are already in place, just under-tuned.

This spec is subsystem B + C from the May gameplay-revisit conversation, bundled because they're all combat tuning touching adjacent systems. Subsystem A shipped in Phase 10 + Phase 10 tuning.

---

## Locked decisions

- **Spawn cadence (B1):** dragons and elders share the existing per-spawner roll, but a global per-tier floor prevents stacking. Dragon floor: 20s. Elder floor: 45s. When a roll lands on a tier whose floor hasn't elapsed, the spawn downgrades to welp (the next tier down).
- **Elder personalities (B2):** one signature ability per color, mix of alive-time and death-time triggers. Six abilities. Each ability is themed to its color so the player can read the threat at a glance.
- **Cone geometry (C1):** length 7m → 12m, angle 75° → 100°. Verify the mesh transform puts the apex at the boss origin (current `top_radius=2.5, bottom_radius=0.1` with `(0, 0, -2.5)` mesh translation should already do this; if visual perception says otherwise, fix the .tscn).
- **Stacking cheese (C2):** burn-through model. Clouds take damage on each blocked breath tick (5 per tick). Wells lose 0.5s of remaining lifetime on each cone redirect. Stacking still buys time but degrades.

---

## §1 — Architecture & boundaries

Four structural changes:

1. **`Escalation` extended with global tier-spawn floor tracking.**
   - New state: `_last_dragon_spawn_msec`, `_last_elder_spawn_msec` (ints, default 0).
   - New methods: `record_tier_spawn(tier: String)`, `can_spawn_tier(tier: String) -> bool`.
   - New constants: `DRAGON_FLOOR_S = 20.0`, `ELDER_FLOOR_S = 45.0`.
   - `reset()` clears the timestamps.

2. **`corner_spawner.gd` checks the floor before committing a tier.**
   - After `Escalation.roll_tier(heat)` returns dragon/elder, check `Escalation.can_spawn_tier(tier)`. If false, downgrade to welp.
   - On successful spawn, call `Escalation.record_tier_spawn(tier)`.

3. **`welp.gd` extended with elder-tier color signature ability.**
   - Each elder welp checks its color on `_ready` and registers the appropriate ability hook (alive-tick, on-attack, on-death).
   - The hook fires from existing `_physics_process` (alive ticks) or `take_damage` (death) or `_attack_player` (on-attack).
   - Ability implementations live in a new `scripts/entities/elder_abilities/` directory, one file per color (six files), each extending a small `ElderAbility` base.

4. **Boss breath cone burn-through.**
   - `mechanic_static_breath.gd` and `mechanic_sweeping_breath.gd` `_segment_blocked_by_cloud` already iterates blocking clouds. When a block fires, additionally call `cloud.take_damage(CLOUD_BREATH_BLOCK_DAMAGE)` on the blocking cloud.
   - `effect_cloud.gd` gains a `take_damage(amount)` method that decrements an internal `hp` (default 30) and `queue_free`s on zero.
   - `boss_dragon.gd:apply_pull_toward` (which forwards pull to breath mechanics for redirect) gets a callback path so the well that triggered the redirect can be told to drain. Add `WellDrainHook` callable that the well sets on the boss when it pulls. Boss invokes it after redirect.
   - Cone size constants in static and sweeping breath: `CONE_LENGTH 7.0 → 12.0`, `CONE_ANGLE_DEG 75.0 → 100.0`.

**Boundaries kept clean:**
- `Escalation` — only knows about heat, tier floor timestamps, and whether a tier is spawnable. Doesn't know about the corner spawner.
- `corner_spawner.gd` — only knows about local roll + ask-the-floor. Doesn't know about the floor implementation.
- Each elder ability file — knows only about its color's behavior. Doesn't reach into other elders.
- `effect_cloud.gd` — gains a take_damage method; otherwise unchanged.
- Boss breath mechanics — the burn-through is a single line added in `_segment_blocked_by_cloud`.

**Out of scope:**
- Audio for elder abilities (separate phase).
- VFX polish on chill aura / poison trail (first-pass uses existing material patterns).
- Boss cone .tscn changes beyond what's needed for the apex-at-boss fix and the new size constants.
- Elder ability balance tuning beyond first-pass numbers (a tuning bake follows playtest).

---

## §2 — Elder color signature abilities

Each colored elder gets one signature ability themed to its color. All implementations extend a base `ElderAbility` (RefCounted) with three optional Callables: `on_alive_tick(elder, delta)`, `on_attack(elder, target)`, `on_death(elder)`.

The welp script (single file shared across tiers) checks `tier == "elder"` on `_ready` and looks up the ability via a small registry keyed by color. The registry is a Dictionary in a new autoload `ElderAbilityRegistry` (mirrors `ElderRegistry` from Phase 10).

### Red — Fire Pool on Death

- **Trigger:** `on_death`
- **Effect:** spawn a 2.5m radius fire pool at elder's death position; pool ticks 5 dmg/0.5s on player in radius for 3s.
- **Implementation:** instantiate `effect_cloud.tscn` (reuse existing scene) with `base_color = "red"`, `lifetime = 3.0`, `radius = 2.5`, `tick_damage = 5`. The cloud's existing damage tick path handles burn application. Fire pool *does not* block boss breath (only green clouds do that — see C2).

### Blue — Chill Aura

- **Trigger:** `on_alive_tick` (every 1.0s while alive and in 3m radius of player)
- **Effect:** apply 1 chill stack to player. Stacking aura ticks build toward freeze.
- **Implementation:** alive-tick hook checks distance to player; if ≤ 3m, calls `player.apply_chill(1)` once per second (timer state on the elder).

### Green — Poison Trail

- **Trigger:** `on_alive_tick` (per move-distance threshold)
- **Effect:** every 1m of movement, drop a 1.5m radius poison cloud at elder's position; cloud lifetime 2s, ticks 3 dmg.
- **Implementation:** alive-tick tracks last-drop position; when distance from last drop ≥ 1m, spawn `effect_cloud.tscn` with `base_color = "green"`, `lifetime = 2.0`, `radius = 1.5`, `tick_damage = 3`. Update last-drop position. Trail clouds *do* block boss breath (consistent with green-cloud rule from Phase 9).

### Purple — Pull on Hit

- **Trigger:** `on_attack` (when basic melee attack lands)
- **Effect:** pull the player 1m toward the elder.
- **Implementation:** in `_attack_player` after the existing `take_damage` call, also call `player.apply_pull_toward(elder.global_position, 1.0)`. Position-control mechanic: the player gets dragged into the elder's melee range.

### Gold — Chain on Hit

- **Trigger:** `on_attack`
- **Effect:** basic attack additionally zaps one other enemy within 4m for 50% of the elder's `attack_damage`.
- **Implementation:** in `_attack_player` after the player hit, find the nearest other enemy in the `enemy` group within 4m (excluding this elder); if found, call `target.take_damage(int(attack_damage * 0.5))`. Note: this is a *boon* to the player as much as a threat — gold elders self-thin nearby clusters. The mechanic is themed (chain lightning) and the trade-off (sometimes you want them to chain) is intentional.

### White — Bone Wall Near PC on Death

- **Trigger:** `on_death`
- **Effect:** spawn a 4m bone wall offset 2-3m from the player's current position, oriented to block the player's straight-line path to the corpse area.
- **Implementation:** instantiate `effect_bone_wall.tscn` (reuse existing scene). Pick a position 2.5m offset from the player along a random angle within 90° of the player→elder vector. Orient the wall perpendicular to the player→elder line. Wall lifetime: 3s. The wall is a movement obstacle, not a damage source.

---

## §3 — Spawn cadence

Two pieces.

### §3a — Global tier floor

`scripts/world/escalation.gd` gains:

```gdscript
const DRAGON_FLOOR_S: float = 20.0
const ELDER_FLOOR_S: float = 45.0

var _last_dragon_spawn_msec: int = 0
var _last_elder_spawn_msec: int = 0

func record_tier_spawn(tier: String) -> void:
    var now: int = Time.get_ticks_msec()
    if tier == "dragon":
        _last_dragon_spawn_msec = now
    elif tier == "elder":
        _last_elder_spawn_msec = now

func can_spawn_tier(tier: String) -> bool:
    var now: int = Time.get_ticks_msec()
    if tier == "dragon":
        return now - _last_dragon_spawn_msec >= int(DRAGON_FLOOR_S * 1000.0)
    if tier == "elder":
        return now - _last_elder_spawn_msec >= int(ELDER_FLOOR_S * 1000.0)
    return true  # welps and unknown tiers always spawn

# reset() clears timestamps so each new run starts with both floors expired.
func reset() -> void:
    # (existing reset body)
    _last_dragon_spawn_msec = 0
    _last_elder_spawn_msec = 0
```

### §3b — Spawner respects the floor

`scripts/world/corner_spawner.gd:_spawn` after `var tier: String = Escalation.roll_tier(heat)`:

```gdscript
    var tier: String = Escalation.roll_tier(heat)
    # Far corners only ever produce welps — no off-screen dragons/elders.
    if _is_far(player_pos):
        tier = "welp"
    # Global tier floor: if a dragon or elder was spawned recently, downgrade
    # so we don't pile up multiple of the same tier.
    if not Escalation.can_spawn_tier(tier):
        tier = "welp"
    var scene: PackedScene = _scene_for_tier(tier)
    if scene == null:
        return
    # ... (existing spawn body)
    Escalation.record_tier_spawn(tier)
```

The `record_tier_spawn` call is a no-op for welps (tier check inside the method). Recording happens after the actual spawn, so a deferred / failed spawn doesn't burn the floor.

---

## §4 — Cone geometry + burn-through

### §4a — Cone size constants

`scripts/entities/boss_mechanics/mechanic_static_breath.gd` and `mechanic_sweeping_breath.gd`:

```gdscript
const CONE_LENGTH: float = 12.0  # was 7.0
const CONE_ANGLE_DEG: float = 100.0  # was 75.0
```

### §4b — Cone visual apex-at-boss

`scenes/effects/effect_breath_cone.tscn` mesh transform currently `(0, 0, -2.5)` — the half of the cylinder height. Cylinder height is 5.0 today.

If the new cone length is 12m, the cylinder height in the .tscn should also be 12.0 (so the visual matches the damage area). Update:
- `CylinderMesh.height = 12.0` (was 5.0)
- Mesh transform translation = `(0, 0, -6.0)` (was -2.5; new value is half of new height)
- Verify in editor that the apex (narrow end, `bottom_radius=0.1`) appears at the boss origin and the wide end (`top_radius=2.5`) extends in the boss's facing direction.

If the user perception of "centered on boss" turns out to be a real visual bug (not a perception artifact), the fix is here — the mesh translation magnitude must equal half the cylinder height, and the cylinder must be oriented so the wide end is along -Z (parent forward).

### §4c — Cloud burn-through on block

`scripts/effects/effect_cloud.gd` gains:

```gdscript
const NATIVE_HP: int = 30
var hp: int = NATIVE_HP

func take_damage(amount: int) -> void:
    hp = max(0, hp - amount)
    if hp == 0:
        queue_free()
```

The cloud's existing `_process` lifetime/age behavior stays — clouds expire on either HP zero or age >= lifetime, whichever first.

`scripts/entities/boss_mechanic.gd:_segment_blocked_by_cloud` (the shared helper lifted in Phase 9 followup) gains a damage call when blocking succeeds:

```gdscript
const CLOUD_BREATH_BLOCK_DAMAGE: int = 5

func _segment_blocked_by_cloud(from: Vector3, to: Vector3) -> bool:
    var clouds: Array = get_tree().get_nodes_in_group("damage_cloud")
    for c in clouds:
        if not is_instance_valid(c):
            continue
        if c.get("base_color") != "green":
            continue
        if c.has_method("blocks_segment") and c.blocks_segment(from, to):
            if c.has_method("take_damage"):
                c.take_damage(CLOUD_BREATH_BLOCK_DAMAGE)
            return true
    return false
```

### §4d — Well drain on redirect

`scripts/effects/effect_gravity_well.gd` gains:

```gdscript
const REDIRECT_LIFETIME_DRAIN_S: float = 0.5

func consume_for_redirect() -> void:
    # Each redirect drains lifetime so stacking wells doesn't grant infinite redirects.
    var remaining_age: float = lifetime - _age
    if remaining_age <= REDIRECT_LIFETIME_DRAIN_S:
        queue_free()
        return
    _age += REDIRECT_LIFETIME_DRAIN_S
```

Boss breath mechanics (`on_pull_during_windup` in static + sweeping) currently receive `pull_origin` and `rotation_deg` but no reference to the originating well. Extend the signature: `on_pull_during_windup(pull_origin: Vector3, rotation_deg: float, source: Node = null)`. Boss `apply_pull_toward` looks up the gravity well that triggered (the player's most recent purple cast) and passes it as `source`. After redirect, breath mechanics call `source.consume_for_redirect()` if source is a well.

The lookup approach: `apply_pull_toward` is called from `effect_gravity_well.gd:_physics_process` (the well calling boss). The well passes `self` as source. Boss forwards to mechanics. Clean.

---

## §5 — Implementation phasing

Two phases, each landable independently.

**Phase A — Spawn cadence + cone fixes.** Smallest, lowest-risk. Escalation floor tracking, corner_spawner adjustment, cone size constants, cone .tscn update, cloud burn-through, well drain. Tests: floor tracking behavior, downgrade when floor active, cone size assertion, cloud HP decrement on block, well lifetime drain on redirect.

**Phase B — Elder color abilities.** Six new ability files + ElderAbilityRegistry autoload + welp.gd integration. Tests: each ability fires at the right trigger, ability state cleans up on elder death, registry returns the right ability per color.

Each phase ships with its own merge. Phase A first because it's foundational and lower risk.

---

## §6 — Risks

- **Cone size at 12m × 100° may be too big.** The arena radius is 18m. A 12m cone covers most of the arena half. If playtest shows this is unfair, halve the angle bump (75° → 90°). Tuning bake at end of Phase A.
- **Elder spawn floor too restrictive.** With 45s elder floor and 2-min run target, a player could see only 2 elders — short of the 2-3 target. If undershoots in playtest, drop floor to 30-40s.
- **Burn-through still permits cheese with thick stacking.** Two 30 HP green clouds = 60 HP of breath-block, ~12 ticks ≈ 2.4s. Boss cone is 0.8s static / 2s sweeping. So even one cloud absorbs most of one cone. If still cheesable, raise CLOUD_BREATH_BLOCK_DAMAGE to 10 (3 ticks per cloud).
- **Elder ability "gold chain on hit" may underwhelm or overpower.** It hits one nearby other enemy for half-damage — not a pure threat to the player. If too weak, increase to 100% damage. If too strong (clears entire spawns), restrict to "next attack only".
- **Pull-on-hit (purple elder) compounds with melee range.** If the elder pulls the player and immediately melees again, the player can be locked in a 2-3 second pull → hit → pull cycle. Mitigate via per-elder pull cooldown (e.g., 2s minimum gap between pulls).

---

## §7 — Tests

**Phase A:**
- `test_escalation_dragon_floor`: spawning a dragon sets the timestamp; second dragon within 20s downgrades.
- `test_escalation_elder_floor`: same, with 45s.
- `test_escalation_reset_clears_floors`: `reset()` lets both tiers spawn again immediately.
- `test_corner_spawner_downgrades_when_floor_active`: when `can_spawn_tier(elder)` returns false, `_spawn` produces a welp instead.
- `test_cone_size_constants`: assert `CONE_LENGTH == 12.0` and `CONE_ANGLE_DEG == 100.0` in both static and sweeping breath.
- `test_cloud_takes_damage_on_block`: drive `_segment_blocked_by_cloud` with a green cloud; assert cloud HP drops by `CLOUD_BREATH_BLOCK_DAMAGE`.
- `test_cloud_freed_on_zero_hp`: cloud at 5 HP takes 5 damage → `is_instance_valid` returns false next frame.
- `test_well_drain_on_redirect`: well at 1.5s remaining lifetime takes a redirect → 1.0s remaining; another redirect → 0.5s; another → freed.

**Phase B:**
- `test_red_elder_drops_fire_pool_on_death`: kill red elder; assert a damage_cloud with `base_color = "red"` appears at death position.
- `test_blue_elder_chill_aura_applies_chill_to_player`: place player within 3m of blue elder; advance time 1s; assert player chill_stacks ≥ 1.
- `test_green_elder_drops_poison_trail_on_movement`: move green elder 1m; assert at least one new green cloud appeared.
- `test_purple_elder_pulls_player_on_attack`: trigger `_attack_player` on purple elder; assert player's `_knockback_velocity` updated toward elder.
- `test_gold_elder_chain_zaps_other_enemy`: spawn gold elder + 2 nearby welps; trigger attack; assert at least one welp took damage from chain.
- `test_white_elder_spawns_bone_wall_near_pc_on_death`: kill white elder; assert a bone_wall appeared within 2-3m of the player.

302+ existing tests stay green. Some boss breath tests may need the new cone size constants reflected if they hardcoded the old values.

---

## §8 — Out of scope (follow-ups)

- Boss-side abilities to clear/destroy player wells & clouds (a more aggressive cheese-counter than burn-through).
- Audio for elder abilities.
- VFX polish on poison trail (currently reuses cloud scene with green tint).
- Per-elder pull cooldown for purple elder (mentioned in risks; tune if playtest shows lock-cycle).
- Telegraphed elder casts (e.g., red elder windup + ranged fireball). Current spec keeps elder behavior simple — passive auras and on-event triggers only.
- Spawn cadence tuning per phase (currently floor is global; could scale with phase).
