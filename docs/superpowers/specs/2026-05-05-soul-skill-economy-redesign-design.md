# Soul/Skill Economy Redesign Design

**Goal:** rework the soul economy and skill progression so the in-run wand grows slowly, deliberately, and with replayability. Whelps stop being free power. Elders become the in-run pivot point. Minor souls become the meta currency. Cross-run progression moves from auto-unlock to a player-driven shop with two distinct tracks.

**Context:** v0.9 playtest revealed that whelps drop minor souls, each pickup adds a modifier to the active wand, and players accumulate ~10-20 modifiers per run by farming whelps. By the time the boss is engaged, builds are already saturated. Elders today *replace* the active wand with a fresh one — locking the existing modifier stack — so spec'd power growth is interrupted by an effective power dump. Both effects pull the in-run progression curve in the wrong direction.

This redesign:
- **Sources:** whelps drop nothing; dragons drop minor souls only; elders drop a drafted modifier + elder currency.
- **In-run wand growth:** elder kills only. 2-3 elders per run. Each elder offers a 3-card draft from a color-themed pool of 8+ unique transformative modifiers. Repeats compound.
- **Meta progression:** minor souls feed a capped percentage stat-upgrade track; elder currency feeds a structural mechanic + mode unlock tree. Player drives spend; nothing auto-unlocks.

This phase is subsystem A from the May 2026 gameplay-revisit conversation. Subsystems B (spawn cadence + elder color personalities) and C (boss cone geometry + green/purple stacking cheese) get their own specs.

---

## Locked decisions

- **Whelps drop nothing.** No soul pickup, no in-run effect, no meta contribution.
- **Dragons drop minor souls only.** No elder currency from dragons. Source clarity per tier.
- **Elders drop a drafted modifier + 1 elder currency.** No minors from elders.
- **Elder modifier draft:** 3 cards drawn from a color-themed pool of 8+ per color. Player picks 1 to add to active wand. Same-modifier repeats compound (effect strength stacks).
- **In-run wand cap:** none. With 2-3 elders/run, you'll never see more than 3 elder modifiers stacked.
- **Banking:** minor souls + elder currency carry per-run; bank when the player triggers descent (existing `end_run(DESCENDED)` path that already calls `SoulEconomy.deposit_to_pyres`). Death = lose carried.
- **Pyres:** no longer auto-unlock features and no longer apply the per-color damage bonus / skill-cap bonus. They become pure visual displays of meta currency accumulated per color.
- **Active-wand "decline elder" path:** removed. Elder *is* a wand modifier, not a wand swap, so there is nothing to decline.
- **Meta shop tracks:** capped percentage stats (minors) + structural mechanic + mode unlocks (elders). Both tracks are player-driven; nothing auto-purchases.
- **Migration:** existing meta state (cantrips, hub features, pyre fills) converts cleanly into the new shop's currency + purchased state. No save reset. Detail in §3c.

---

## §1 — Architecture & boundaries

Five structural changes:

1. **Soul drop policy on `welp.gd`.** `_drop_souls()` becomes tier-aware:
   - `welp` tier → no drops
   - `dragon` tier → 1-2 minor pickups (currently 2-3)
   - `elder` tier → 1 elder pickup, no minor pickups (currently 1 elder + 2-3 minor)
   - `alarm` / `boss` tiers → unchanged (no drops)

2. **Pickup decoupled from skill modification.** `soul_pickup.gd._on_body_entered` today does two things: adds to `SoulEconomy.carry` *and* immediately calls `SkillSystem.add_minor/add_elder`. Split:
   - Minor pickup → `SoulEconomy.add_to_carry` only.
   - Elder pickup → `SoulEconomy.add_to_carry` *and* triggers an in-run `ElderDraft` flow (see §2).
   - The direct `SkillSystem.add_minor` call from minor pickups is removed.

3. **`SkillSystem` redesigned around modifier-only growth.**
   - `add_minor()` → removed (minors no longer modify the active wand).
   - `add_elder()` → renamed to `apply_elder_modifier(modifier_id, color)`; adds an entry to the active wand's modifier stack and bumps stack count if duplicate.
   - The "lock active skill, unlock new skill at cap, replace prompt" path is removed — elders no longer create new wands.
   - **Default starting wand:** every run begins with a red wand at zero modifiers. This replaces the old "first minor pickup unlocks the wand" path. The Wand Choice unlock in §3 lets the player pick a different starting color; without that unlock, every run starts red.

4. **`ElderDraft` UI flow.** New scene + controller. On elder pickup: pause physics, show 3 modifier cards drawn from the elder's color pool, player picks one, scene resumes. Cards display name, effect description, and stack count if duplicate (e.g., "Ignite — already on your wand (will become +5% chance)").

5. **`MetaShop` autoload + scene.** Replaces today's `meta_progress.gd` auto-unlock paths. Existing systems consolidate as follows:
   - **Cantrips today** (3 keys × 5 levels: max_hp, sword_damage, dash_cooldown) become 3 of the 5 stats in the upgrade track (renamed: Vitality, Power, Cast Speed). Pyre Cap and Soul Magnetism are new stats added alongside. Existing cantrip levels migrate 1:1 — a player at max_hp level 3 has Vitality at rank 3.
   - **Hub features today** (`_hub_features_unlocked` 0..4, currently auto-fired on first 50% milestone of each color) replaced by player-driven structural unlock tree. Existing unlocked count migrates as the first N "purchased" entries on the mechanic branch.
   - **Pyre milestones today** (25/50/75/100 thresholds drive per-color damage bonus + skill-cap bonus) — milestone system is removed. Damage bonus and skill-cap effects converted to "always on at base value 0"; the new meta shop is the only progression source.
   - **`_start_with_skill` today** (already supports start-with-color-of-choice) keeps its current name/API but is gated behind the "Wand Choice" structural unlock instead of always-available.
   - Two currency types: `minor_souls`, `elder_currency`. Both carried + banked via existing `deposit_to_pyres` path.
   - Two purchase tracks: `stat_upgrades` (minor-paid, capped ranks) and `structural_unlocks` (elder-paid, tree).
   - `pyre_filled` and `pyre_fill_changed` signals stay (used by visual pyres) but no longer trigger auto-unlocks.

6. **Remove dead code.** `SkillSystem.active_skill_cap_bonus` and the multi-wand cap path are removed since wands are now single per run. `MetaProgress.color_damage_bonus` is removed (replaced by Power stat upgrade applying flat bonus).

**Boundaries kept clean:**
- `welp.gd` — only knows about drop policy. Doesn't know about skills or shop.
- `soul_pickup.gd` — only knows about banking and elder draft trigger.
- `SkillSystem` — only knows about the active wand and its modifier stack. Multi-wand path removed.
- `ElderDraft` — only knows about presenting 3 cards and applying the chosen modifier.
- `SoulEconomy` — only knows about per-run carry → bank flow. Existing `deposit_to_pyres` reused; per-color carry stays.
- `MetaShop` (replaces `MetaProgress`) — only place that knows about meta currency spend, purchase state, and unlock effects.

**Out of scope** (separate specs):
- Spawn cadence + per-color elder enemy abilities (subsystem B).
- Boss cone geometry + green/purple stacking interactions (subsystem C).
- Audio for the elder draft flow (separate phase).

---

## §2 — Elder modifier pools

Each color owns a pool of 8+ uniquely-named transformative modifiers. The player sees 3 random cards from the elder's color pool on pickup and picks 1. Repeats compound numerically.

**Authoring directive:** modifiers should change *how* the wand behaves, not just numbers. "+10% damage" is a stat upgrade (meta shop). Elder modifiers are flags like "every hit ignites" or "casts pierce".

**Initial seed pools** (8 per color = 48 total at launch; pools may grow in later phases):

### Red — Fire
1. **Ignite All Hits** — every cast applies a 1s burn DoT. Stack: +0.5s duration per copy.
2. **Cinder Trail** — moving leaves a fire trail that burns enemies for 0.5s. Stack: +50% duration.
3. **Combust on Kill** — kills explode for 50% weapon damage in a 2m radius. Stack: +25% radius.
4. **Detonating Burns** — burning enemies that die explode for 100% remaining-burn-damage. Stack: +50% explosion radius.
5. **Ember Shield** — taking damage spawns a 1m fire ring that burns adjacent enemies for 1s. Stack: +1s ring duration.
6. **Pyromaniac** — gain +10% damage per actively-burning enemy nearby (max 5). Stack: +10% per copy (cap +50%).
7. **Phoenix Surge** — first death per run is prevented; revive with 25% HP and a 3m fire burst. Stack: extra revive (max 3 total).
8. **Red Mass** — burn damage scales with target's missing HP up to 2x at 50% HP. Stack: scales to 3x / 4x.

### Blue — Ice
1. **Chill All Hits** — every cast applies 1 chill stack (existing system).
2. **Glacial Path** — projectiles leave a slowing ice trail for 1s. Stack: +50% duration.
3. **Brittle** — hits against frozen enemies deal +100% damage and shatter the freeze. Stack: +50% damage bonus.
4. **Cold Snap** — freezing an enemy chills all enemies within 3m. Stack: +1m radius.
5. **Frostbite** — enemies below 50% HP take +25% damage. Stack: +10% per copy.
6. **Hailstrike** — every 5 casts, a chunk of ice falls on a random nearby enemy (50% weapon damage + 1 chill). Stack: every 4 / 3 casts.
7. **Crystallize** — frozen enemies that die release 3 ice shards in random directions. Stack: +1 shard.
8. **Permafrost** — chill stacks no longer decay. Stack: bonus +10% damage per applied chill stack.

### Green — Toxic
1. **Toxin All Hits** — every cast applies a 2s poison DoT (separate from burn). Stack: +1s.
2. **Spore Bloom** — kills release a 2m poison cloud for 2s. Stack: +1m radius.
3. **Lingering Mist** — green clouds last 50% longer. Stack: +25% per copy.
4. **Plague Bearer** — poison spreads to one nearest enemy on tick. Stack: spreads to 2 / 3 / 4.
5. **Toxic Bloom** — poisoned enemies that die spawn a Spore Bloom (chained). Stack: bigger bloom.
6. **Decay** — poisoned enemies move 30% slower. Stack: +10% slow per copy (cap 70%).
7. **Symbiosis** — gain +1 HP/sec for each poisoned enemy nearby. Stack: +1 HP/sec per copy.
8. **Necrotic** — poison damage scales with stacks; stacks no longer reset on reapply. Stack: +25% damage per stack.

### Purple — Gravity
1. **Pull on Hit** — every cast pulls the target 1m toward the player. Stack: +1m.
2. **Implode** — pulling enemies into each other deals 25% weapon damage. Stack: +25%.
3. **Gravity Anchor** — casts attach a 2s gravity well to the target. Stack: +1s.
4. **Crushing Mass** — pulled enemies take +30% damage for 1s. Stack: +15% per copy.
5. **Singularity** — every 4th cast spawns a 3m pull field. Stack: every 3rd / 2nd cast.
6. **Tidal Lock** — kills pull all corpses + remaining souls within 5m to player. Stack: +2m.
7. **Event Horizon** — enemies pulled past 1m of player take 50% weapon damage. Stack: +25%.
8. **Slipstream** — moving toward enemies grants +20% movement speed. Stack: +10% per copy.

### Gold — Lightning
1. **Chain on Hit** — casts chain to 1 nearby enemy. Stack: +1 chain target.
2. **Overcharge** — every 3rd cast deals double damage. Stack: every 2nd / every cast (caps at every cast = +100%).
3. **Surge** — chain damage equals base cast damage (no falloff). Stack: chains apply chill / burn / poison.
4. **Conduit** — chains apply the active wand's elder modifier effects. Stack: +1 chain target.
5. **Static Field** — taking damage releases a 3m chain that hits all enemies in range. Stack: +1m.
6. **Capacitor** — every 5 casts unleashes a free auto-cast at random target. Stack: every 4 / 3.
7. **Storm Caller** — kills have 25% chance to call lightning at a random nearby enemy. Stack: +10% per copy (cap 65%).
8. **Resonance** — chains amplify each subsequent jump (+25% per jump). Stack: +25% per copy.

### White — Bone
1. **Bone Shield** — first hit per encounter is absorbed. Stack: +1 absorb per encounter.
2. **Marrow Pierce** — casts pierce through 1 enemy. Stack: +1 pierce.
3. **Calcify** — wall casts spawn 50% larger and 50% longer-lived. Stack: +25% per copy.
4. **Skeleton Crew** — kills 25% chance to summon a 5s bone-welp ally that mimics the player's last cast. Stack: +10% chance.
5. **Hardened** — wand modifiers apply to the sword's basic attacks. Stack: +25% sword damage per copy.
6. **Reaper** — sword kills restore 2% HP. Stack: +2% per copy.
7. **Bonelash** — a chain-arc 3m around the player damages enemies within for 25% weapon damage on dodge. Stack: +25%.
8. **Ossified** — taking damage 50% chance to spawn a defensive bone wall. Stack: +20% chance.

> Pool entries above are first-pass shapes for implementation. Numerical tuning lives in a follow-up balance pass; the spec locks the count, the names, and the layered mechanic, not the final coefficients.

---

## §3 — Meta shop

Two parallel purchase tracks. UI is one shop with a tab for each track.

### §3a — Stat upgrades (minor souls)

Five stats, each with five capped ranks. Costs grow per rank.

| Stat | Per-rank effect |
|---|---|
| **Vitality** | +10% / +20% / +35% / +50% / +75% max HP |
| **Power** | +5% / +10% / +20% / +35% / +50% wand + sword damage |
| **Cast Speed** | +5% / +10% / +15% / +20% / +25% cast cooldown reduction |
| **Pyre Cap** | +25 / +50 / +100 / +175 / +250 max pyre fill |
| **Soul Magnetism** | +1m / +2m / +4m / +6m / +10m soul vacuum range |

Costs in minor souls per rank: **5 / 15 / 50 / 150 / 400**. Rank 5 of all stats = 4,050 minor souls (a long grind, intentionally; gives meta currency permanent value through end-game).

### §3b — Structural unlocks (elder currency)

Tree of one-time purchases. Each is a true permanent capability gain.

**Mechanic branch:**
1. **Wand Choice** — start a run with your choice of base color (default: red only). Cost: 3.
2. **Second Elder Modifier Slot** — wands accept up to 2 distinct elder modifier slots before duplicates fold into compound stacks. Cost: 5.
3. **Pyre Expansion** — main hall today has only a Red pyre. Each rank of this unlock adds one more colored pyre (Blue, then Green, then Purple, then Gold, then White) so the player can bank that color's souls without traveling. Five ranks. Cost: 3 / 4 / 5 / 6 / 7.
4. **Replenish on Descent** — descending (banking via the descent prompt) restores 25% HP. Cost: 4.
5. **Elder Sense** — elder welps gain a tracked outline + minimap blip. Cost: 2.
6. **Modifier Reroll** — once per run, reroll the elder draft once. Cost: 6.
7. **Build Carry** — keep one elder modifier from the previous run on the next run's first wand. Cost: 8.

**Mode branch:**
1. **Hard Mode** — boss has 1.25x HP, 1.25x damage. Drops 2x meta currency. Cost: 5.
2. **Daily Seed** — one fixed seed per day, no bonus drops. Cost: 3.
3. **Boss Variant: Frost Dragon** — boss starts in P3 and uses blue-themed mechanics. Cost: 7.
4. **Boss Variant: Cinder Dragon** — boss starts in P3 and uses red-themed mechanics. Cost: 7.

> Cost numbers are first-pass; tuning bake locks them in implementation. Tree shape (mechanic vs. mode) is the locked decision.

### §3c — Migration

On first load after the upgrade, existing meta state migrates as follows:

- **Cantrips → stat ranks (1:1):** existing `max_hp` cantrip level → Vitality rank; `sword_damage` cantrip level → Power rank; `dash_cooldown` cantrip level → Cast Speed rank. `Pyre Cap` and `Soul Magnetism` stats start at rank 0.
- **Hub features → mechanic branch purchases:** existing `_hub_features_unlocked` count (0..4) becomes the first N purchases on the mechanic branch (in order: Wand Choice → Second Modifier Slot → Pyre Expansion rank 1 → Replenish on Descent). For example, a player with `_hub_features_unlocked = 2` starts the post-upgrade game with Wand Choice and Second Modifier Slot already purchased.
- **Pyre fills → minor soul currency:** existing per-color pyre fill values are summed and credited 1:1 as `minor_souls` (e.g., 50 fill across all colors → 50 minor_souls in the bank). Pyre fill state is then reset to 0 so the visual displays start fresh against the new accumulation.
- **Filled-pyre flags + pyre milestones:** existing `_filled_pyres` and `_pyre_milestones` are dropped — they drove the auto-unlock path that no longer exists.
- **`_start_with_skill`:** preserved as-is.
- **Mid-run upgrade:** if a player has a run in flight when the upgrade lands, their carry is preserved and treated as the new currency.

A one-shot "Things have changed" splash on first launch post-upgrade lists the new economy: whelps no longer drop souls, dragons drop minors, elders drop drafted modifiers, meta currency is spent at the new shop.

---

## §4 — Implementation phasing

Three phases, each landable independently. Each phase ships with its own tests and merge.

**Phase 1 — Drop policy + pickup decoupling.** Smallest, riskiest behavioral change first. Whelps drop nothing; dragons drop only minors; elders drop only the elder pickup. The skill-modification path is *temporarily* removed (elders pickups bank but don't draft yet). Players see *no* in-run wand growth on this phase — that's expected; it lands first to validate the drop policy in isolation. Tests: drop counts per tier, no `add_minor` calls from pickups.

**Phase 2 — Elder draft + skill system rework.** Build the `ElderDraft` UI; remove `add_minor` and `add_elder` from `SkillSystem`; add `apply_elder_modifier`. Implement the 48 modifiers from §2. Tests: each modifier's effect, stack compound math, draft excludes nothing weird, scene flow.

**Phase 3 — Meta shop + migration.** Build the two-track shop UI; wire to `MetaShop` autoload; remove `pyre_filled → unlock_next_hub_feature`; implement migration. Tests: rank effects apply to gameplay, structural unlocks gate features, migration produces correct purchased state.

Each phase is reviewed and merged before the next begins. Failed reviews block the next phase. Phase 2 has the most code (48 modifiers); each modifier is a small file with a focused test.

---

## §5 — Risks

- **Phase 1 ships a temporarily worse game.** No in-run wand growth at all until Phase 2 lands. Document this in playtest notes; do not playtest Phase 1 in isolation.
- **48 elder modifiers is real authoring work.** The §2 pools are first-pass shapes. Some entries will need rework once they meet the actual damage pipeline. Allocate slack in Phase 2 estimates.
- **Compounding stacks may produce degenerate combos.** "Necrotic" + "Toxin All Hits" + "Plague Bearer" could exponentially scale poison. Tuning bake at end of Phase 2 with a cap-on-derived-coefficients safety net (e.g., per-tick damage ceiling the same way the boss has `DMG_CAP_PER_TICK`).
- **Migration of existing saves.** First run after upgrade should not surprise a player. Add a one-shot "Things have changed" splash that lists the new economy (whelps don't drop souls, etc.) on first launch post-upgrade.

---

## §6 — Tests

- **Phase 1**: drop policy unit tests, pickup banking only (no skill calls).
- **Phase 2**: each modifier in isolation; stack compound math; draft offers exactly 3 distinct cards; pick applies the chosen modifier and dismisses the prompt; UI scene flow with input simulation.
- **Phase 3**: stat upgrade purchase + effect; structural unlock purchase + effect gating; migration produces correct purchased state from synthetic saves.

Tests touching `add_minor` / `add_elder` / multi-wand will need updates as those code paths are removed (estimate: 30-50 tests in `test_skill_system.gd` and `test_soul_economy.gd` rewrite or retire). Non-economy tests stay green — no regressions in boss mechanics, color casts, status effects, etc.

---

## §7 — Out of scope (subsystem B and C)

This spec only addresses subsystem A. The following are deferred to their own specs:

- **Subsystem B — spawn cadence + elder personalities.** Dragons + elders share a spawn interval with an inter-spawn timer to prevent stacking. Each elder color has color-themed combat abilities (red elder casts a fire pool, blue elder applies chill on hit, etc.) instead of being a stat-buffed welp.
- **Subsystem C — boss cone geometry + green/purple stacking.** Cone apex sits at the boss (currently centered on the boss, so cones extend backward as well). Cone size tuning. Resolve the green/purple stacking cheese — likely via cooldown gating or cone-redirect immunity windows.
