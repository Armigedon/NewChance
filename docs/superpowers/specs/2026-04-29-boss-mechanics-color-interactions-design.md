# Boss Mechanics + Tier 1 Color Interactions Design

**Goal:** Make the v0.9 boss fight feel earned, not chesseable. Replace the current stat-sponge with 8 telegraphed mechanics across 3 phases, plus 16 color-specific counterplay interactions. Player's color choice meaningfully shapes how they engage the boss.

**Architecture:** Extends current `boss_dragon.gd` with a mechanic scheduler (per-mechanic cooldown timers + mutual-exclusivity guard) and a telegraph state machine per mechanic (IDLE → WINDUP → EXECUTION → COOLDOWN). New effect scenes: breath cone, mark zone. Color interactions hook through existing systems (bone wall collision, chill stacks, pull, burn DoT) wherever possible — no new global system needed.

**Tech Stack:** GDScript, Godot 4.6, existing damage pipeline + status-effect system.

---

## 1. Boss Mechanics by Phase

Phases activate at HP thresholds (existing rules: P2 at 66% / 1980 HP, P3 at 33% / 990 HP). New mechanics unlock at phase boundaries; existing mechanics keep firing at faster cooldowns. **Phases ADD; phases never REMOVE.**

| Mechanic | P1 unlock | P2 cooldown change | P3 cooldown change |
|---|---|---|---|
| Telegraphed slam | yes | faster | faster |
| Static breath | yes | faster | faster |
| Mark + delayed strike | yes | faster | faster |
| Conditional jump | yes (triggered) | same | same |
| Sweeping breath | — | unlocks | faster |
| Armor wings | — | unlocks | faster |
| Charge | — | — | unlocks |
| Flying slam | — | — | unlocks |

Whelp summons accelerate per phase (existing mechanic, retuned cadence). Dragon summons unlock in P2.

---

## 2. Telegraph Timings, Damage, Cooldowns

### Telegraph timings

| Mechanic | Wind-up | Execution | Notes |
|---|---|---|---|
| Slam | 0.6s | impact | basic, frequent threat |
| Static breath | 1.0s (+0.6s if blue chill applied during windup) | 0.8s cone | ticks 4× over 0.8s |
| Sweeping breath | 0.8s | 2.0s sweep | random direction (CW/CCW), ticks while overlapping player |
| Mark + delayed strike | mark instant | strike at 2.5s | floor ring grows during 2.5s window |
| Armor wings | 0.5s | 4s active (decaying) | linear 60% → 0% damage reduction |
| Charge | 1.4s | 1.5s charge | direction locked at telegraph start |
| Flying slam | 2.0s | 0.4s descent | landing target locked at telegraph start |
| Conditional jump | 1.0s crouch | 0.6s arc | triggered (see §4) |

### Damage values (player base HP = 100)

| Mechanic | Damage | AoE | % HP |
|---|---|---|---|
| Slam | 25 | 2m radius | 25% |
| Static breath | 10/tick × 4 ticks = 40 max | cone 5m × 60° | 40% full exposure, 10% graze |
| Sweeping breath | 15/tick (every 0.1s while overlapping) | rotating cone | 15–30% typical, 45% if tracking sweep stupidly |
| Mark + delayed strike | 30 | 2m radius | 30% |
| Armor wings | 0 (defensive) | — | — |
| Charge | 60 | line | 60% — crippling |
| Flying slam | 80 | 3m radius | 80% — near-lethal |
| Conditional jump (land) | 15 | 1m radius | 15% |
| Boss contact (existing) | 30 | melee | 30% |

### Cooldowns by phase (seconds)

| Mechanic | P1 | P2 | P3 |
|---|---|---|---|
| Slam | 5 | 4 | 3 |
| Static breath | 8 | 6 | 5 |
| Sweeping breath | — | 12 | 8 |
| Mark + delayed strike | 10 | 8 | 6 |
| Armor wings | — | 20 | 15 |
| Charge | — | — | 12 |
| Flying slam | — | — | 18 |
| Conditional jump | triggered (3s gap min) | same | same |
| Whelp summon | 4 | 2.5 | 1.5 |
| Dragon summon | — | 12 | 8 |

---

## 3. Mutual Exclusivity Rules

- **Only one "big" attack active at a time.** Big = slam, static breath, sweeping breath, mark, armor wings, charge, flying slam. While one is in WINDUP or EXECUTION state, no other big can start.
- **Walking, contact damage, summons layer freely** — they're not "big."
- **Conditional jump bypasses the rule.** It's a defensive escape; can fire even if a big attack is mid-execution. (The big attack is interrupted by the jump.)
- **Phase 3: charge & flying slam share a 6s post-execution cooldown floor.** After either fires, the other can't start for at least 6 seconds. Prevents double-lethal-burst.

### Scheduler algorithm

Each frame:
1. If a big attack is mid-WINDUP or mid-EXECUTION, hold.
2. Else, gather all mechanics whose cooldown ≤ 0 and which are unlocked in the current phase.
3. Filter by phase 3 charge/flying-slam exclusivity rule.
4. Random selection from the ready set, weighted by mechanic priority (phase-3 unlocks slightly favored over phase-1 to keep escalation feeling).
5. Trigger selected mechanic; reset its cooldown.

---

## 4. Color Interaction Map (Tier 1)

| Mechanic | White | Blue | Red | Green | Purple |
|---|---|---|---|---|---|
| Slam | — | — | — | — | — |
| Static breath | wall blocks | chill extends telegraph | — | cloud blocks | pull redirects cone |
| Sweeping breath | wall blocks (single arc) | chill extends telegraph | — | cloud blocks | pull redirects cone |
| Mark + delayed strike | wall absorbs | — | — | — | — |
| Armor wings | — | — | burn pierces | — | — |
| Charge | 2+ walls stop, 1 slows | chill slows velocity | — | — | pull redirects trajectory |
| Flying slam | wall on landing zone | — | burn during prep | — | — |
| Conditional jump | — | — | — | — | — (intentional, no counter) |

**Per-color tally:** White 5 / Blue 3 / Red 2 / Green 2 / Purple 3 / Gold 0 (Tier 2 deferred).

### Implementation per interaction

**White — bone wall:**
- *Blocks breath cones.* Wall's StaticBody3D collision occludes the cone. Breath damage check excludes any cone segment past the wall. Wall takes 1 HP damage per tick of breath contact.
- *Absorbs mark strike.* On strike impact, check for any wall whose collision overlaps the 2m mark zone. If yes, wall takes the mark's full 30 damage; player takes 0; wall almost certainly breaks.
- *On charge:* 1 wall in path → charge velocity × 0.5 + wall destroyed + charge continues. 2+ walls in path → charge stops at first wall, boss stunned 1s, all walls in path destroyed.
- *Walking boss break-through:* boss takes 0 damage but moves at 0.7× speed for 1s while breaking each wall. Wall takes 30 damage (one-shot break).
- *On flying slam landing:* if wall placed within 3m AoE before slam impact, wall absorbs slam's 80 damage (likely breaks); player takes 0.

**Blue — chill stacks:**
- *Extends breath telegraph.* Each chill stack applied to boss DURING breath windup adds 0.15s to the windup timer. Capped at 4 stacks (boss CC-immunity threshold from Phase 9). Max +0.6s window.
- *Slows charge velocity.* During charge execution, chill stacks reduce velocity by 8% per stack. Max 4 stacks = 32% reduction. Boss covers less ground.

**Red — burn DoT:**
- *Pierces armor wings.* While armor wings active, all damage receives the reduction EXCEPT burn DoT (`source == "burn"`), which applies at full value. Damage cap still applies to all sources (no cap-bypass).
- *Bonus damage during flying slam prep.* While boss is in flying slam windup (2s, stationary mid-air), burn DoT ticks deal **1.5×** damage. Rewards anticipating the move.

**Green — cloud:**
- *Blocks breath cones.* Cloud volume excludes breath damage in any segment of the cone passing through the cloud. Visual: breath fizzles where it intersects cloud. Cloud takes no damage from this interaction.

**Purple — pull:**
- *Redirects breath cone.* Each pull cast on boss DURING breath windup rotates the cone target direction by 15°. Cumulative; limited by windup duration and cast cooldown.
- *Redirects charge trajectory.* Pull cast on boss during charge execution shifts trajectory by a perpendicular vector proportional to pull magnitude. Boss continues charging at full speed but ends at an offset position. Multiple pulls stack offsets.

---

## 5. Other Locked Decisions

### Sword damage scaling (white modifier reward)

Sword damage in `sword.gd` becomes:

```gdscript
var n: int = white_count_in_modifier_stack
if active_skill.base_color == "white":
    n += 1
var multiplier: float = 1.0 + 1.0 * (1.0 - pow(0.7, n))
sword_dmg = int(base_damage * multiplier)
```

| n | Multiplier | sword_dmg (base 15) |
|---|---|---|
| 0 | 1.0 | 15 |
| 1 | 1.30 | 19 |
| 3 | 1.66 | 24 |
| 5 | 1.83 | 27 |
| ∞ | 2.0 | 30 |

Asymptotic cap at 2× base. Matches the diminishing-returns curve already used elsewhere in the game.

### Wall concurrent cap

Player can have at most **2 active walls**. Casting a 3rd despawns the oldest (queue_free immediately, no graceful fade). Tracked via a `Walls` group or a world-level wall registry. Existing wall lifetime (3s asymptotic) and HP (30 flat) remain unchanged.

### Boss CC immunity (carryover from Phase 9)

- `apply_chill` caps stacks at FREEZE_THRESHOLD - 1 = 4. Never freezes boss.
- `apply_stun` is a no-op on boss.
- New rule: `apply_chill` during breath windup also extends the windup (see Blue interaction).

### Conditional jump trigger

Check every 0.5s during P1+:
1. Boss has moved < 1m over the past 2s.
2. Boss has taken damage in those 2s.
3. Last jump completed > 3s ago.

All three true → trigger jump. Land position: random valid (in-arena, not overlapping wall, ≥ 4m from current). Land deals 15 dmg in 1m AoE.

### Phase transitions

No invulnerability window. Existing ScreenShake + phase taunt remain. Boss continues mid-action if a big attack is in progress when HP threshold crosses; finishes the move, then any new mechanic can roll.

### DamageMeter integration

All new damage paths route through `DamagePipeline.apply` (most) or `boss_dragon.take_damage` (boss-state-affecting paths) with source tags:

- `slam`, `breath_static`, `breath_sweep`, `mark_strike`, `charge`, `flying_slam`, `boss_jump`, `boss_contact`
- Suffix `+armor_wing` when armor wings reduction was applied
- Suffix `+chain` when fired as a chain proc (existing)

---

## 6. Visual / Telegraph Treatment

- **Slam:** small red pulsing circle on floor at boss position, fills over 0.6s, impact.
- **Static breath:** red translucent cone shape from boss mouth, faint during windup, solid during execution. Edges glow brighter near impact.
- **Sweeping breath:** same cone visual, rotates during execution. Direction indicator during windup.
- **Mark + delayed strike:** white outline ring on floor at mark position, fills with red over 2.5s, flashes white at impact.
- **Armor wings:** boss raises wings VFX, persistent glow during 4s active period (intensity decays with reduction value).
- **Charge:** straight line indicator from boss to charge endpoint during 1.4s windup, brightens.
- **Flying slam:** boss leaps up (visible vertical motion), red shadow circle on landing zone, grows over 2s, impact.
- **Conditional jump:** boss crouches (animation), brief upward motion, lands at new position.

All telegraphs render in their own visual layer (suggest `boss_telegraph` group) so they're easy to tune as a group.

---

## 7. Out of Scope (Future)

- **Tier 2 color interactions** (deferred to v0.9.1):
  - Gold chain → stuns telegraph windups (needs design solution to avoid CC-bypass on boss).
  - Purple pull → flying-slam-air-interrupt (vetoed per timing window concerns; may revisit with longer windup or different mechanic).
  - Unique green expansion (currently green's strength is emergent — ticks during boss stationary windows; may add a defining mechanic later).
- **Phase transition cinematics** — currently just ScreenShake + taunt; add brief slow-mo + camera pull-out at boundaries in a polish pass.
- **Boss arena hazards** — environmental destructibles, falling rocks, etc. Not in this spec.
- **Boss death sequence** — already exists from Phase 9; no changes here.

---

## 8. Testing

Per-mechanic unit tests:
- Telegraph timing matches spec (windup duration, execution duration).
- Damage application matches spec.
- Cooldown reset works.
- Mutual exclusivity prevents concurrent big attacks.

Per-color-interaction unit tests:
- White wall blocks breath; wall takes damage from blocked breath.
- Blue chill extends breath telegraph by 0.15s/stack, capped at 4.
- Red burn pierces armor wings; non-burn damage gets reduced.
- Green cloud blocks breath segments.
- Purple pull rotates breath cone direction during windup.
- Conditional jump triggers when stationary + taking damage; doesn't trigger during chase.

Integration:
- Full boss fight with each base color (5 builds), verify kill time 110–180s range depending on build composition.
- DamageMeter log validates no path bypasses cap or wing reduction.
- Verify no error spam during boss fight (check player.gd:201 fix from Phase 9 still holds).

---

## 9. Definition of Done

- All 8 mechanics implemented with telegraphs, damage, cooldowns matching tables in §2.
- All 16 color interactions implemented per §4.
- Sword scaling per §5.
- Wall concurrent cap per §5.
- Conditional jump trigger per §5.
- DamageMeter source tags per §5.
- Test suite passes (existing 193 + new tests for each mechanic).
- Manual playtest: 3+ different builds, each kill time in 110–180s window, no error spam.
- Boss fight feels readable, not reflex-test; no "tank it" mechanics; every mechanic dodgeable or color-counterable.
