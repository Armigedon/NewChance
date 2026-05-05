# Phase 9: Elements + Balance Design

**Goal:** finish the elemental system the original spec promised but the implementation stubbed, and retune the damage curve so souls feel meaningful without trivializing content.

**Context:** the [original game design doc](../specs/2026-04-25-new-chance-design.md) specified rich, distinct identities for all 6 colors (red fireball+AoE+burn, blue ice line+freeze, green toxic cloud, purple gravity well, gold lightning chain, white bone wall). The implementation reduced these to near-identical projectiles with a `# Phase 2 stub` `_apply_modifier` that just adds 10% damage regardless of color. Playtest of v0.8-ui-pass confirmed the symptoms: color choice feels arbitrary, white/blue piercing dominates, and 2-3 souls one-shots everything (including elder dragons and the boss). This phase implements the original designs and retunes the curve.

---

## Locked decisions

- **Color identities:** implement original spec verbatim. Adjust later via tuning if needed.
- **Damage curve target:** ~5 same-color souls per noticeable power spike (original spec intent). Spikes land at 5 (1-shot welps), 15 (1-shot dragons), 25+ (elder pressure). Boss is always a fight.
- **Modifier procs:** pure utility. No direct damage from cross-color modifier procs. Damage propagates through chain (gold) and cloud ticks (green) but the layers themselves (burn, chill, pull, stun, armor) don't add damage.
- **Modifier composition:** **layered, not additive**. Each modifier is a rule that operates on every damage event the cast generates, not an isolated proc. Long modifier chains compose naturally — a burning poison cloud whose ticks chain lightning to nearby enemies emerges from stacking red, green, gold modifiers in any order.

---

## §1 — Architecture & boundaries

Three structural changes plus tuning constants:

1. **Status-effect state on enemies.** Today, `welp.gd` and `boss_dragon.gd` only have `take_damage(amount)`. We add a small inline status system per enemy: member vars + methods for `apply_burn(dps, duration)`, `apply_slow(pct, duration)`, `apply_chill(stacks)` (with freeze threshold), `apply_stun(duration)`, `apply_pull_toward(pos, force)`. Ticked per frame. No new resource classes — keep it as member state on the enemy. Hoist to a shared base class only if a third enemy type appears.

2. **Per-color modifier dispatch.** A new `DamagePipeline` becomes the single point of entry for all damage events. The current stub `cast_base.gd:_apply_modifier(enemy, _color)` (which adds +10% damage) is removed.

3. **Per-color cast scenes rebuilt to match original spec.** Red gains AoE on impact, blue keeps piercing but applies chill, green becomes a placed cloud (not projectile), purple becomes a placed gravity well, gold becomes an instant strike at cursor with stun + chain, white becomes a placeable barrier wall (the *piercing white* from playtest leaves the game).

4. **Tuning constants retuned** to the ~5-souls-per-spike target.

**Boundaries kept clean:**
- `cast_base.gd` — orchestrator: same-color scaling math + entry to `DamagePipeline`
- `cast_<color>_*.gd` — each owns only its cast-shape behavior
- `DamagePipeline` — only place that knows about layer composition
- Enemies own their status state
- `meta_progress.gd` — pyre-damage-bonus structure unchanged (constants only if at all)

**Out of scope** (deferred to follow-ups):
- Spawn density / arena pacing
- Audio for new effects (separate phase)
- Sword-element inheritance VFX changes
- Tests for tuning-sensitive content (status effect content is tuning, not correctness)

---

## §2a — Same-color stacking ("what an extra soul means")

A same-color minor soul (modifier color matches base color) does **two things at once**:

1. **Deepens the base cast shape** — happens only when colors match.
2. **Counts as a modifier of that color**, so it applies the layer effect from §2b. Same mechanism as a cross-color modifier; the base-match is what unlocks the depth bonus on top.

The user-visible "what does another soul give me?" answer is the union of both. For example: a same-color red soul gives you +20% damage + bigger fireball (from #1) AND +1.5s burn duration on every hit (from #2, because it's also a red modifier in the stack).

**Rule #1 — base-shape depth (same-color only):**

All colors gain +20% damage and +20% visual size per same-color stack. Plus one color-specific shape property:

| Color | Same-color shape deepening (in addition to +20% dmg/size) |
|---|---|
| **Red — Fire** | Bigger AoE explosion radius (the explosion grows visibly with stacks) |
| **Blue — Frost** | Longer ice line (range/length scales beyond visual size) |
| **Green — Plague** | Cloud radius and lifetime scale with stacks |
| **Purple — Void** | Well radius and lifetime scale with stacks |
| **Gold — Lightning** | Strike radius scales with stacks |
| **White — Bone Wall** | Wall length, HP, and lifetime scale with stacks |

**Rule #2 — modifier layer effect (any color):**

Per §2b, every modifier in the stack (same- or cross-color) adds its layer effect. This is what makes "another red soul = longer burn" or "another gold soul = +1 chain jump" actually fire — those scale via the modifier rule, not a separate same-color rule.

**Combined effect of an extra same-color soul** (the answer to "what does an extra red soul mean for a red-base cast?"):

| Color | Net effect of one extra same-color soul |
|---|---|
| **Red — Fire** | +20% dmg, bigger fireball, bigger AoE, +1.5s burn duration |
| **Blue — Frost** | +20% dmg, longer line, +1 chill stack/hit (freezes faster) |
| **Green — Plague** | +20% dmg, bigger cloud, +1.5s cloud lifetime |
| **Purple — Void** | +20% dmg, bigger well, +0.5m pull radius on hit |
| **Gold — Lightning** | +20% dmg, bigger strike, +1 chain jump |
| **White — Bone Wall** | +20% wall HP, longer wall, +1s wall lifetime, +1 armor stack on cast |

---

## §2b — Compositional modifier system ("layers + spawners")

**Three role categories:**

| Role | Colors | What they do |
|---|---|---|
| **Layer** (decorates every hit event) | Red, Blue, Purple, Gold | Adds an effect to **every damage event the cast produces** — initial hit, AoE, cloud ticks, chain hits |
| **Spawner** (creates new hit-sources) | Green | Generates a residual zone (cloud) that itself inherits every other layer |
| **Player buff** (off the damage path) | White | Affects the caster, not hit events; stacks armor on cast |

**Per-modifier specifics:**

| Color | Role | Per-stack scaling |
|---|---|---|
| **Red — IGNITE** | Layer | +1.5s burn duration per red modifier |
| **Blue — FROST** | Layer | +1 chill stack per hit per blue modifier (5 = freeze) |
| **Purple — GRAVITATE** | Layer | +0.5m pull radius per purple modifier |
| **Gold — CHAIN** | Layer | +1 chain jump per gold modifier |
| **Green — LINGER** | Spawner | +1.5s cloud lifetime per green modifier |
| **White — WARD** | Player buff | +1 armor stack per white modifier |

**Composition rule:** every damage event a cast generates runs through ALL layers in the stack. Spawners (green) add new damage sources, which themselves run through all layers. Player buffs (white) fire once at cast time on the caster.

**Walked example — Red base + Green + Gold:**
1. Fireball flies (red base = fireball + AoE + native ignite).
2. Fireball impacts → AoE damage event. Layer pass: burn (red native), 1 chain jump (gold). Chain target gets the same layer pass — burned and would chain again if more golds.
3. After AoE, green LINGER spawns a poison cloud at impact (lifetime 4.5s).
4. Cloud ticks every 0.5s on enemies in radius. Each tick is a damage event — applies burn, chains 1.

**Net feel:** "burning cloud of poison whose every tick chains lightning to nearby enemies, all of whom catch fire." Add a 4th color and it composes — every layer applies to every existing damage source and every newly-spawned one.

**The "god build" example — Red base + 5 of every other color:**
- Fireball base, scaled massive by 5 same-color souls (per §2a)
- Initial hit + AoE: burns (red×6 ≈ 12s burn), pulls (purple×5 = 4.5m radius), chills 6/hit (blue×5 = freezes in 1 hit), chains 5 jumps (gold×5)
- Each chain target: same effect cascade
- Green spawns persistent 11s cloud — every cloud tick burns, chills, pulls, chains 5 more times
- Player gets 5 armor stacks on cast (white)

Every additional modifier visibly extends the killzone. Color choice composes cleanly at any chain length.

---

## §2c — Damage curve numbers

**Damage scaling rules:**

| Constant | Value | Was |
|---|---|---|
| Cast base damage | **25** | 25 (unchanged) |
| Same-color stacking | **+20%/stack** to damage AND size | +30%/stack |
| Modifier proc damage | **0** (pure utility — chain & cloud propagate damage, layers don't add it) | +10%/proc |

**Enemy HP (the big retune):**

| Enemy | New HP | Old HP |
|---|---|---|
| Welp | **50** | 30 |
| Dragon (mid-tier) | **100** | 30 (inherited) |
| Elder | **200** | 30 (inherited) |
| Boss | **500** | 400 |
| Boss whelp | **100** | 80 |
| Player max_hp | **100** + cantrip | unchanged |

Note: dragon and elder were both inheriting the welp `@export var max_hp = 30` because no per-tier override existed. Adding tier-aware HP is part of this work.

**Power-spike validation:**

| Souls (same-color) | Cast dmg | Welp (50) | Dragon (100) | Elder (200) | Boss (500) |
|---|---|---|---|---|---|
| 0 | 25 | 2 hits | 4 hits | 8 hits | 20 hits |
| **5** | 50 | **1-shot ✓** | 2 hits | 4 hits | 10 hits |
| 10 | 75 | 1-shot | 2 hits | 3 hits | 7 hits |
| **15** | 100 | 1-shot | **1-shot ✓** | 2 hits | 5 hits |
| 20 | 125 | 1-shot | 1-shot | 2 hits | 4 hits |
| **25** | 150 | 1-shot | 1-shot | 2 hits | **4 hits** (with phases) |

**Status-effect tick rates** (anchored to cast base damage so they auto-scale):

| Effect | Damage formula |
|---|---|
| Red burn DoT | 25% of cast damage per second, 3s base + 1.5s per red modifier |
| Green cloud tick | 25% of cast damage every 0.5s (50% dmg/sec), 3s base + 1.5s per green modifier |
| Blue chill | 0 damage; freezes at 5 stacks (1.5s immobilize, chill resets on freeze break) |
| Purple gravitate | 0 damage on hit; pulls toward impact, 1m base radius + 0.5m per purple modifier |
| Gold chain | Full cast damage to N additional targets (N = gold modifier count) |
| White wall | 100 HP barrier, 4m wide, 4s base + 1s per white modifier (no damage either way) |
| White armor (modifier) | +1 stack per white modifier on cast, 5s lifetime, each absorbs 5 dmg |

**Sword (auto-melee):**
- Base damage: 15 + cantrip (3-30 range), unchanged
- Applies the active skill's **base color's native layer** on hit for damage colors (red sword burns, blue sword chills, etc.) — does NOT walk the modifier stack
- White is the exception: no on-hit effect; passive +1 armor stack every 5s while equipped (per §3)
- Green sword applies a small DoT tick (lighter than green-cast cloud)

**Pyre damage milestones:** unchanged (+5% at 25% pyre fill, +10% at 75%, applied to that color's cast damage). Cumulative across all 6 pyres in post-game.

---

## §3 — Per-color cast specs

Each color defines its **base shape**, its **native effect** (what the base does even with 0 modifiers), and its **modifier role** (per §2b composition).

**Red — Fire**
- **Base shape:** aimed projectile, AoE explosion on impact (or end of lifetime). Speed 12 m/s, max range 8m, AoE radius 2m.
- **Native effect (IGNITE):** every enemy in the AoE gets burn DoT — 25% of cast dmg/sec for 3s base.
- **As modifier:** each red modifier adds +1.5s burn duration to every hit event.
- **Cooldown:** 3s.

**Blue — Frost**
- **Base shape:** piercing line, hits every enemy in its path. Speed 18 m/s, length 8m, lifetime 0.6s.
- **Native effect (FROST):** every hit applies +1 chill stack. At 5 → freeze (1.5s immobilize, chill resets on freeze break).
- **As modifier:** each blue modifier adds +1 chill stack per hit event.
- **Cooldown:** 3s.

**Green — Plague**
- **Base shape:** placed cloud at cursor (instant, no projectile). Radius 2m, lifetime 3s, ticks every 0.5s for 25% of cast dmg.
- **Native effect:** the cloud IS the damage source — every tick is a damage event the layer system runs over.
- **As modifier (LINGER, spawner):** on a non-green cast, spawns a residual cloud at the impact point (3s base + 1.5s per green modifier). Cloud ticks inherit every other layer.
- **Cooldown:** 4s.

**Purple — Void**
- **Base shape:** placed gravity well at cursor (instant). Radius 2m, lifetime 2s, ticks every 0.5s for 25% of cast dmg.
- **Native effect (GRAVITATE):** continuously pulls enemies inside the radius toward center while alive.
- **As modifier:** each purple modifier adds +0.5m pull radius on every hit event (radial impulse on hit toward impact point). Pull strength fixed.
- **Cooldown:** 4s.

**Gold — Lightning**
- **Base shape:** instant strike at cursor (no flight time). Strike radius 1.5m.
- **Native effect:** 0.5s stun on every enemy in the strike radius.
- **As modifier (CHAIN):** each gold modifier adds 1 chain jump to every hit event. Chain target is the nearest non-already-chained enemy within 4m. Chained hit deals full cast damage and re-runs all layers.
- **Cooldown:** 3s.

**White — Bone Wall**
- **Base shape:** placed wall at cursor (perpendicular to player→cursor line). Length 4m, HP 100, lifetime 4s. Blocks enemy bodies and projectiles. Breakable. Does NOT deal damage.
- **Native effect (WARD):** on cast, player gets +1 armor stack (5s, each stack absorbs 5 incoming damage).
- **As modifier:** each white modifier adds +1 armor stack on cast. White is the only modifier that doesn't compose with damage events — it fires once at cast time.
- **Cooldown:** 5s.

**Sword inheritance** (active skill's base color only — modifier stack does NOT apply):
- Red sword: every swing applies 1s burn
- Blue sword: every swing applies 1 chill stack
- Green sword: every swing applies poison tick (small DoT)
- Purple sword: every swing applies tiny pull on hit
- Gold sword: every swing applies 0.2s mini-stun
- White sword: passive — grants 1 armor stack every 5s while equipped

---

## §4 — Implementation architecture

**The core abstraction: a unified damage pipeline.**

Every damage event in the game — primary cast hit, AoE explosion, cloud tick, chain jump, gravity-well tick, sword swing — flows through one function. That function applies damage, walks the layer stack, and recursively triggers chain events.

**`DamagePipeline` (new, static helper at `scripts/skills/damage_pipeline.gd`):**
```
apply(target, damage, modifier_stack, base_color, source_pos, chain_state)
  → target.take_damage(damage)
  → for each layer in [base_color] + modifier_stack:
       dispatch via match → enemy method (apply_burn / apply_chill / apply_pull / apply_stun)
  → if gold modifiers present and chain_state has budget:
       find nearest non-hit enemy, recurse with budget - 1
```

`chain_state` is a small struct (RefCounted) holding chain budget (initialized to gold-modifier-count) and an array of already-hit targets, to prevent double-hits and infinite loops within one cast.

**`DamagePipeline` is the ONE place that knows about the layer system.** Cast scripts, effect nodes, and sword swings all funnel through it.

**Files to add:**

| File | Purpose |
|---|---|
| `scripts/skills/damage_pipeline.gd` | Pipeline + per-color layer dispatch |
| `scripts/effects/effect_cloud.gd` + `scenes/effects/effect_cloud.tscn` | Green cloud — Area3D, ticks `DamagePipeline.apply()` on enemies in radius |
| `scripts/effects/effect_gravity_well.gd` + `scenes/effects/effect_gravity_well.tscn` | Purple well — applies pull velocity per frame, ticks damage |
| `scripts/effects/effect_bone_wall.gd` + `scenes/effects/effect_bone_wall.tscn` | White wall — StaticBody3D, blocks physics, has HP, breakable |

**Files to modify:**

| File | Change |
|---|---|
| `scripts/skills/cast_base.gd` | Replace direct damage with `DamagePipeline.apply()`. Remove `_apply_modifier` stub. Same-color depth scaling stays here. |
| `scripts/skills/cast_red_fireball.gd` | Add AoE explosion on impact (replaces single-target hit) |
| `scripts/skills/cast_blue_ice_line.gd` | Keep piercing; native chill via DamagePipeline |
| `scripts/skills/cast_green_plague.gd` | **Rewrite** — instantiate `effect_cloud.tscn` at cursor, no projectile |
| `scripts/skills/cast_purple_void.gd` | **Rewrite** — instantiate `effect_gravity_well.tscn` at cursor, no projectile |
| `scripts/skills/cast_gold_lightning.gd` | **Rewrite** — instant strike at cursor with stun, no projectile |
| `scripts/skills/cast_white_bone.gd` | **Rewrite** — place `effect_bone_wall.tscn`; grant player armor on cast |
| `scripts/entities/welp.gd` | Add status state (burn/chill/pull/stun/slow) + tier-aware `max_hp` |
| `scripts/entities/boss_dragon.gd` | Add status state |
| `scripts/entities/player.gd` | Add armor stacks state; `take_damage` consumes armor first |
| `scripts/entities/sword.gd` | Apply active skill's base-color native layer per swing via DamagePipeline |

**Status effects on enemies** (member state on `welp.gd` and `boss_dragon.gd`):

```gdscript
var _burn_dps: float = 0.0
var _burn_remaining: float = 0.0
var _chill_stacks: int = 0
var _frozen_remaining: float = 0.0
var _slow_pct: float = 0.0
var _slow_remaining: float = 0.0
var _stun_remaining: float = 0.0

func apply_burn(dps: float, duration: float): ...
func apply_chill(stacks: int): ...  # at 5 → trigger freeze
func apply_stun(duration: float): ...
func apply_slow(pct: float, duration: float): ...
func apply_pull_toward(pos: Vector3, impulse: float): ...

func _physics_process(delta):
    _tick_burn(delta)
    _tick_status_timers(delta)
    if _frozen_remaining > 0 or _stun_remaining > 0:
        return  # skip movement / attacks
```

**Player armor:**

```gdscript
# player.gd
var _armor_stacks: int = 0
var _armor_remaining: float = 0.0
const ARMOR_PER_STACK: int = 5

func apply_armor(stacks: int, duration: float): ...

func take_damage(amount: int):
    while _armor_stacks > 0 and amount > 0:
        var absorb = min(amount, ARMOR_PER_STACK)
        amount -= absorb
        _armor_stacks -= 1
    if amount > 0:
        # existing damage logic
```

**Tier-aware enemy HP** (welp.gd):

```gdscript
const TIER_HP: Dictionary = {"welp": 50, "dragon": 100, "elder": 200}

func _ready():
    max_hp = TIER_HP.get(tier, 50)
    hp = max_hp
    # ... existing code
```

**Why this shape:**
- `DamagePipeline.apply()` is the only place that knows about modifier composition. Adding a 7th color later = one match arm.
- Effect nodes (cloud, well, wall) are independent scenes — they don't know about each other or about cast scripts. They just call the pipeline.
- Status state lives on the enemy (locality, performance, self-contained `_physics_process`).
- Pipeline is a static helper, not an autoload, because it needs no state of its own.

---

## §5 — Testing strategy

**Test what's testable; playtest what's tunable.** The pipeline (does dispatch fire, do chains find targets, does freeze trigger at 5) is unit-testable. The *feel* (does 5 souls feel like a power spike) is playtest territory.

**New test suites:**

| File | Coverage |
|---|---|
| `test/test_damage_pipeline.gd` | Pipeline dispatch: base damage applied, layers walked per modifier, chain budget respected, no double-hits in chain, native base-color effect applied, white modifier targets player not enemy |
| `test/test_welp_status.gd` (or extend `test_welp.gd`) | `apply_burn` ticks DoT over duration; `apply_chill` at 5 stacks triggers freeze; `apply_stun` prevents AI; `apply_slow` reduces movement; `apply_pull_toward` displaces toward target; tier-aware `max_hp` honors `tier` |
| `test/test_boss_dragon_status.gd` (or extend `test_boss_dragon.gd`) | Same status surface as welp; verify boss can be burned/chilled/stunned/pulled/slowed |
| `test/test_player_armor.gd` (or extend `test_player.gd`) | Armor absorbs before HP; multiple stacks consume one per hit; armor expires after duration |
| `test/test_effect_cloud.gd` | Cloud ticks on enemies in radius; respects lifetime; doesn't tick on enemies outside radius |
| `test/test_effect_gravity_well.gd` | Well pulls enemies in radius; ticks damage; respects lifetime |
| `test/test_effect_bone_wall.gd` | Wall has correct HP; breaks at 0 HP; blocks enemy bodies; expires after lifetime |

**Existing tests that need updates** (HP changes break old assertions):
- `test_welp.gd` — adjust expected HP values if asserted
- `test_boss_dragon.gd` — adjust MAX_HP if asserted

**Not testing** (out of scope, deferred to playtest):
- End-to-end cast script integration (e.g., "cast fireball, enemy dies")
- VFX / feel
- Specific damage tuning numbers
- Sword inheritance visuals
- Color-specific tuning values past dispatch behavior

**Coverage target:** every public method on `DamagePipeline` and on enemy/player status APIs has at least one test. Effect-node lifecycles (spawn → tick → despawn) covered. Tuning values can change without breaking tests.

---

## Open tuning numbers (locked at first build, dialed in playtest)

These are educated guesses. Actual feel determines final values.

- Welp / dragon / elder / boss HP (above)
- Cast cooldowns (3-5s per color)
- Status effect durations (burn 3s base, freeze 1.5s, stun 0.5s, etc.)
- Pull radius and force values
- Cloud tick rate and damage fraction
- Wall HP and lifetime
- Armor per-stack absorption (5)
- Sword inheritance effect strengths (small, intentionally weak)

The architecture is correct; the constants are dials. After Phase 9 ships, a balance-only pass can dial without touching the dispatch code.
