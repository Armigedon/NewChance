# New Chance — Design Document

**Date:** 2026-04-25
**Engine:** Godot 4.6.2 (.NET / Forward+ / Jolt 3D)
**Genre:** Top-down 3D dark-fantasy roguelike-survivor
**Status:** Spec draft pending implementation plan

---

## 1 — Vision & core loop

### Pitch
A top-down 3D dark-fantasy roguelike-survivor. The player is a risen skeleton in rusty knight armor, raised by a necromancer to slay dragons. The toolkit is an auto-swinging sword and one or more dragon-soul abilities assembled by hunting upstairs and banking downstairs. The deeper a build goes, the harder enemies hit — until even retreat costs the player. Light all 6 dragon pyres in the main hall, the necromancer reveals himself as the black dragon and steals the flames for a final fight. Survive and the basement opens to deeper post-game content.

### Core loop (per run)
1. Spawn in the main hall (downstairs hub) with no skills, full HP.
2. Climb the staircase up → emerge on upstairs castle walls (open arena, 6 corners, 6 dragon colors).
3. Auto-melee the rusty sword. First dragon soul = first skill. Stack minor souls (modifier accents) and elder souls (new skills).
4. Heat builds — per-corner from time-in-corner, plus globally from souls picked up. Late run, even retreating to the staircase becomes a fight.
5. Choose: extract (lose all skills, deposit unbanked souls into matching pyres) or push for one more elder soul (raise difficulty, raise reward).
6. Die anywhere upstairs = lose all unbanked souls + skills + run progress (pyre deposits from prior runs are safe). Necromancer taunts the player on every death.
7. Repeat until all 6 pyres lit → boss flow triggers.

### Win condition
Defeat the necromancer (revealed as the black dragon) in the courtyard. Hidden basement door opens, post-game content begins.

### Lose condition
No global lose state. Permadeath is per-run; meta-progress (pyre fills, slot unlocks) persists across deaths.

---

## 2 — World structure

### Spaces (top-down 3D)
- **Main Hall (hub)** — Always-safe. Houses 6 primary pyres (and 6 secondary post-MVP) ringing a central fireplace. Staircase up (always open), wall-hidden staircase down (revealed post-boss), door to courtyard (locked pre-boss). No combat ever.
- **Upstairs (castle walls)** — Hexagonal open arena. 6 corner sub-areas (Red / Blue / Green / Purple / Gold / White). Stone walls between corners give cover but do not block movement. Each corner = the spawn region of its color's dragons. Heat is per-corner. Single staircase down at center. **90% of MVP gameplay happens here.**
- **Courtyard (boss arena)** — Wide circular open space inside the castle walls. Sky visible. Stone perimeter blocks player exit during the fight (gate seals on entry). Floor mostly clear, a few cover obstacles (broken statues, low walls). The hidden basement door is set into one perimeter wall — visibly cracked, not yet broken. Locked until all 6 primary pyres at 100% trigger the cutscene.
- **Basement (post-MVP only)** — Vertical dungeon, 6 descending floors. One secondary color per floor. Floor unlock tied to lighting that color's secondary pyre to 25%. Detail design deferred to post-MVP.

### Camera
Fixed isometric-ish 3/4 angle, follows player with damped lag. Mild dynamic zoom-out during dense combat. Full pull-back framed on dragon + player during boss fight. No player camera control.

### Upstairs ward
A shadow ward seals the staircase up during boss flow (cutscene firing, boss active). Drops on boss-fight resolution (death OR victory).

| Game state | Upstairs ward | Courtyard door |
|---|---|---|
| Idle (pre-100%-pyres) | Open | Locked |
| Boss cutscene firing | UP | Opening |
| Boss active (in courtyard) | UP | Open (sealed behind player on entry) |
| Boss resolved — defeat | DROPS | Re-locked |
| Boss resolved — victory | DROPS | Open |
| Between retries | Open | Locked |

The boss arena gate also seals behind the player on courtyard entry — no retreat once committed in a given attempt.

---

## 3 — Combat & soul system

### Input
- WASD = move
- Mouse cursor = aim
- Left-click = manual cast (currently active skill)
- Number keys 1–N = switch active skill (N = current active skill cap)
- **Space = dash/dodge** (~4m direction-of-movement, ~2s cooldown, brief i-frames)
- Right-click = reserved for future use
- Gamepad: left stick move, right stick aim, RT cast, LB/RB cycle skills, A button dash

### Sword (auto-melee)
Rusty sword auto-swings at nearest enemy in melee range (~2m). Base ~1 swing/sec, low base damage. **Inherits the active skill's element**: flaming, frosty, venomous, shadow, electric, or bone-armored. Visual + on-hit effect changes when player switches active skill.

### Manual cast = active skill
Each cast has its own cooldown (~3–5s base, color-dependent). Cast pattern is the **base color's shape** plus all stacked elemental modifiers from minor souls accumulated since this skill became active.

### The 6 colors

| Color | Cast shape (when base) | Modifier (when added) | Sword inheritance |
|---|---|---|---|
| **Red — Fire** | Fireball: aimed projectile, AoE explosion on impact | Burn DoT on the cast | Flaming, ignites on hit |
| **Blue — Frost** | Ice Spike Line: piercing, slows hit enemies | Chill stacks → freeze at max | Frosted, slow on hit |
| **Green — Plague** | Toxic Cloud: placed AoE, lingers, slow + DoT | Poison DoT, spreads on enemy death | Venomous, poison on hit |
| **Purple — Shadow / Void** | Gravity Well: placed singularity, pulls enemies, dark damage tick | Impact pulls enemies into hit zone | Shadow blade, mini-pull on hit |
| **Gold — Lightning** | Lightning Bolt: instant strike on cursor, brief stun | Chain to nearby enemies (3 jumps) | Electrified, chain on hit |
| **White — Bone / Bulwark** | Bone Wall: placed barrier, blocks projectiles, breakable | On cast, grants stacking armor for a few seconds | Bone-armored, gain armor stack on hit |

**No healing in MVP** — explicit anti-cheese rule. No life-leech, no healing motes, no sustain skills.

### Soul drops by enemy tier

| Tier | Drops | Spawn |
|---|---|---|
| Welp | 1 minor soul | Common, fast, low HP |
| Dragon | 2–3 minor souls | Uncommon, mid HP |
| Elder dragon | 1 elder soul + 2–3 minor souls | Rare, high HP, telegraphed entrance |

Soul color = color of dragon that dropped it. Souls are pickups that go into the player's carry pool.

### Soul progression rules

1. **First soul this run** (any tier, any color) → unlocks Skill 1 with that color as the base shape. Sword inherits its element.
2. **Minor soul (any color thereafter)** → adds that color's elemental modifier to the **currently active skill**. Modifiers stack. Same-color minor souls deepen the base damage / size.
3. **Elder soul (any color)** → unlocks a **new active skill** with that color's base shape. **Locks the prior skill's progression** (it stays at its current accumulated form, can still be used). New skill becomes the focus for further minor souls.
4. **Manual switch** between unlocked skills any time via number keys. Switching changes the sword's inherited element. New minor souls always target the *currently selected* skill.
5. **Active skill cap** limits how many skills can be unlocked at once. MVP starting cap: **3**. Permanent +1 each time a primary pyre fully fills (max +6 from primaries → cap of **9** in MVP endgame).

### Active skill cap behavior at limit
When at cap (e.g., 3) and player picks up an elder soul:
- Prompt appears: *"Replace [Skill 1] / [Skill 2] / [Skill 3]?"* or *"Decline elder soul."*
- Replacing destroys the chosen skill (and all its accumulated modifiers); the elder unlocks the new skill.
- Declining = the elder soul is converted to 3 minor souls of its color, applied to the currently active skill. Respects the kill effort and gives the player a meaningful out.

### In-run elder scaling (the soft difficulty bump)
Each elder soul accepted this run permanently bumps that run's enemy spawn intensity (e.g., +12% spawn rate / +8% enemy HP per elder, tunable). Stacks. Resets at run end. Makes "should I take this elder?" a real choice.

### Heat / escalation (upstairs only)

Three layers stacked:

- **Per-corner heat** — Each corner has a 0–100 heat value. Builds at ~+5/sec while the player is in it, decays at ~-2/sec when absent. Heat increases that corner's spawn rate, dragon tier mix, and elder-spawn chance. Move out to cool down.
- **Soul-pickup heat (global)** — Each soul collected adds +X global heat (welp = small, elder = big). Affects baseline spawn intensity across all corners.
- **Time-pressure escalation (global, slow)** — A separate global "alarm" curve ramps slowly with time spent upstairs. Late-run, this curve starts spawning enemies *near the staircase*, cutting off retreat. By minute 5–7 of a single visit, even running away becomes a fight. **The "intimate escalation that slowly outpaces" the player.**

**Heat reset.** All heat values (per-corner, soul-pickup, time-alarm) reset to 0 the moment the player leaves the upstairs arena — whether by descending the staircase or by dying. A fresh trip up always starts cold.

### Tuning philosophy
Game is hard. To compensate, in-run minor-soul accentuation curve is steep — fewer than 5 minor souls per noticeable level. Enemy density and tier scaling are aggressive — corner heat ramps fast. Net effect: a confident player builds a strong skill in 60–90 seconds, world starts pushing back hard at minute 2–3. Extraction window is short and intentional. Numbers are tunable.

### Death (upstairs or courtyard)
- Lose all unbanked souls.
- Lose all skills (and their accumulated modifiers) for this run.
- Lose all in-run elder scaling (resets, fresh start next run).
- Banked souls / pyre fills / active skill cap unlocks are safe (meta-progress is permanent).
- **Necromancer dialogue line plays** on every death — taunting/scolding. Pulled from a `DialoguePool` resource. Boss-fight death uses a distinct line pool.
- Respawn back in main hall, full HP, no skills.

---

## 4 — Meta-progression

### Pyre fill economy

- Each color's souls fill that color's pyre. **Pyre full at 250 fill units.**
- Welp soul (minor) = **1 unit**, Dragon-dropped minor = **1 unit each** (1/1 scaling), Elder soul = **10 units**.
- Per-kill totals: welp = 1 unit, dragon = 2–3 units, elder dragon = 12–13 units (10 from elder + 2–3 from accompanying minors).
- A long single run cannot density-fill a pyre alone. By design — slow meta-progression.

### Pyre milestones (tiered fill)

| Fill % | Effect (per color) |
|---|---|
| **25%** | Small passive run-start bonus (e.g., +5% that color's modifier strength on every run going forward) |
| **50%** | Unlocks one **hub feature** (sequence determined by order pyres hit 50%, not by color) |
| **75%** | Stronger passive bonus (e.g., +1 starting in-run elder-soul tolerance for that color before scaling kicks in) |
| **100%** | **+1 active skill cap slot** (max +6 from primaries) AND counts toward boss unlock |

### Boss unlock condition
All 6 primary pyres at **100%**. The cutscene fires the next time the player descends the staircase with a deposit that completes the 6th pyre (handled in the descent prompt — see §5).

### Active skill cap progression
- MVP start: **3 slots** unlocked-at-once during a run.
- +1 per primary pyre at 100% → **9** at MVP endgame.
- Post-MVP: +1 per secondary pyre at 100%, +1 from Black soul → **13** maximum.

### Hub features (unlocked sequentially by 50% pyre milestones)

| Order | Feature | Function |
|---|---|---|
| 1st | **Soul Altar** | Drain X banked souls (from a pyre of choice) to start a run with that color's base skill already unlocked. Trade meta-progress for in-run head start. |
| 2nd | **Cantrip Stones** | Spend banked souls (any color) on permanent passive upgrades: max HP, sword damage, dash cooldown, soul carry capacity, etc. Roguelike meta-progression spine. |
| 3rd | **Sigil Forge** | Equip 1 active sigil per run. Sigils are run-shaping modifiers (e.g., "Elder souls drop one extra minor"). |
| 4th | **Trial Chamber** | Challenge runs with restricted skills/conditions for rare rewards. Optional content. |
| 5th | **TBD** | Placeholder: extra passive run-start bonus or v2 feature. |
| 6th | **TBD** | Placeholder: extra passive run-start bonus or v2 feature. |

### Run-start state
- Full HP.
- 0 skills (always start fresh — no loadouts).
- 0 souls in carry pool (cannot carry between runs).
- All meta upgrades active: Cantrip Stone bonuses, equipped sigil, active skill cap from pyre fills, pyre passive bonuses (25%/75% effects).

### Skill-strip ruleset (canonical)

**STRIPPED on:**
- Descending stairs from upstairs to main hall *with souls to deposit* (normal extraction). The standard rule.
- Death (anywhere — upstairs, courtyard, post-MVP basement).

**RETAINED on:**
- Going **up** the stairs (skills carry with whatever the player has — usually 0 if just respawned).
- The **boss-triggering descent** (only via the *Descend & fight* option in the descent prompt). Applies to first trigger and retries.
- **Boss victory** — flames return to pyres, dragon dissolves, player walks back to main hall with skills intact.

The only "skills survive a descent" event is the *Descend & fight* path. Every other descent strips. Every up-trip preserves whatever is currently held.

---

## 5 — Boss & endgame

### Trigger
Player descends the staircase with souls that fill the 6th primary pyre to 100%, OR (post-defeat) consumes 1 elder soul to re-trigger via the *Descend & fight* option in the descent prompt.

### Descent prompt logic

When the player approaches the staircase down, the prompt evaluates state and shows applicable options:

| State | Options shown |
|---|---|
| Normal (at least one pyre < 100%) | **Descend & deposit** (strip skills, deposit souls) |
| Final-pyre-filling deposit (this descent fills the 6th — and last — pyre to 100%; multiple pyres reaching 100% simultaneously on one deposit also qualifies) | **Descend & fight** (deposit, retain skills, trigger boss) |
| All 6 pyres at 100%, post-defeat, ≥1 elder soul carried | **Descend & deposit** (normal) **+ Descend & fight** (consume 1 elder soul, retain skills, re-trigger boss) |
| All 6 pyres at 100%, post-victory | **Descend & deposit** (normal) |

Skill retention is **always** tied to the *Descend & fight* option. The descent prompt is the singular boss-trigger interface — there is no separate ritual pyre object in the main hall.

### Cutscene (~15–20 seconds, skippable on retries)
1. Necromancer materializes near the central fireplace.
2. Raises both arms — pyre flames stream toward him, pulled into his body. Pyres go dark, ambient lighting drops to deep red/black.
3. Body engulfs in flame, transforms into the black dragon. Mid-transformation roar.
4. The locked courtyard door slams open. Camera pans to it.
5. Player regains control in the main hall, free to walk to the courtyard. (No forced entry — a final "are you ready" pause.)

### Boss kit — dragon-form necromancer (Black)
Single arena (courtyard), 3 phases by HP thresholds.

| Phase | HP | Mechanics |
|---|---|---|
| **1** | 100–66% | Roams the arena. Bites and tail-swipes (melee). Summons black whelps from 360° in trickles (~1 per 3s). Frontal flame cone every ~8s (telegraphed). |
| **2** | 66–33% | Adds: claw slam → ground shockwave AoE. Increases whelp summon rate (~1 per 2s). Brief flight-takeoff between attacks. **Flames begin leaking from his body** (visual + small contact damage). |
| **3** | 33–0% | Desperate. Whelp summons slow (he is losing focus) but each summon is an *elder* black whelp. Adds: ground-pillar attacks (telegraphed flame columns). Heavy flame leakage. Taunts/howls more frequently. |

### Whelp behavior
Boss-summoned whelps are melee-only swarm pressure. **They drop nothing on death** (constructs, not real soul-bearers). Player cannot level during the boss — they win or lose with what they brought.

### Death during boss fight
- All in-run state resets (skills, souls).
- Necromancer dialogue line plays from a boss-specific pool ("Did you really think this would be enough?", "Crawl back, little corpse.").
- Player respawns in the main hall. Pyres remain lit at 100%. Courtyard door re-locks.
- To retry: farm an elder soul upstairs, then use *Descend & fight* in the descent prompt (consumes 1 elder soul, retains skills carried at the time of descent, re-triggers cutscene).
- Cutscene becomes skippable on subsequent retries.

### Victory
1. Boss HP hits 0. Final roar.
2. **Flames burst out** of the dragon's body in a radial wave, streaming back into the 6 pyres in the main hall (visual: each flame finds its color's pyre).
3. Dragon body collapses, dissolves into dust.
4. The cracked basement-door wall **crumbles**, revealing the hidden staircase down.
5. Game state flips to `PostBoss`. Player returns to main hall (skills intact). All 6 pyres re-lit. Basement stair now navigable.
6. (One-time on first victory: brief end-of-act epilogue text or VO line, hinting at what's below.)

### Post-MVP: basement endgame structure (deferred design)
- **Floor 1** (always-open post-boss): Crimson dragons. Crimson souls fill a new Crimson pyre that appears in the main hall.
- **Floor 2** unlocks when Crimson pyre at 25%.
- Continue: Silver, Bronze, Teal, Amber, Magenta — each unlocked sequentially via the prior pyre at 25%.
- Each secondary pyre still has 25/50/75/100 milestones (+1 active skill cap per 100%, hub feature unlocks for 50% at TBD positions).
- After all 6 secondary pyres hit 100% and some additional gating: **Black soul condition**. True ending. Specifics deferred.

---

## 6 — Technical architecture (Godot 4.6)

### Project structure

```
new-chance/
├── project.godot                       # Forward+, Jolt 3D — pre-configured
├── scenes/
│   ├── world/
│   │   ├── main_hall.tscn              # Hub
│   │   ├── upstairs.tscn               # 6-corner arena
│   │   ├── courtyard.tscn              # Boss arena
│   │   └── basement_floor.tscn         # Post-MVP, parameterized per floor
│   ├── entities/
│   │   ├── player.tscn
│   │   ├── dragons/
│   │   │   ├── welp.tscn
│   │   │   ├── dragon.tscn
│   │   │   └── elder_dragon.tscn
│   │   └── boss_dragon.tscn
│   ├── interactables/
│   │   ├── pyre.tscn                   # Parameterized by color
│   │   ├── soul_pickup.tscn            # Minor & elder variants
│   │   └── descent_staircase.tscn      # Boss-trigger interface
│   └── ui/
│       ├── hud.tscn                    # HP, soul carry, skill icons, cooldowns
│       ├── descent_prompt.tscn
│       ├── elder_soul_replace_prompt.tscn
│       └── necromancer_dialogue.tscn
├── scripts/
│   ├── core/
│   │   ├── game_state.gd               # Autoload singleton (state machine)
│   │   ├── soul_economy.gd             # Pyre fill, drops, deposits
│   │   ├── skill_system.gd             # Active skills, soul stacking, switching
│   │   └── escalation.gd               # Heat, alarms, ramps
│   ├── entities/
│   │   ├── player.gd
│   │   ├── dragon_base.gd              # Shared dragon AI
│   │   ├── welp.gd / dragon.gd / elder.gd
│   │   └── boss_dragon.gd
│   ├── skills/
│   │   ├── skill_base.gd               # Cast resource, modifier stack
│   │   ├── cast_red.gd ... cast_white.gd
│   │   └── modifiers.gd                # Element modifier stacking logic
│   └── ui/
│       └── (HUD scripts)
├── resources/
│   ├── colors/
│   │   ├── red.tres ... white.tres     # ColorDef resources
│   │   └── black.tres                  # Post-MVP
│   ├── enemies/
│   │   └── (DragonStats resources per color × tier)
│   ├── dialogue/
│   │   └── necromancer_pool.tres       # DialoguePool resource
│   └── sigils/                         # Post-MVP
└── assets/
    ├── meshes/                         # Low-poly .glb files
    ├── materials/
    ├── sfx/                            # Placeholder MVP
    └── music/                          # Placeholder MVP
```

### Core systems

- **`GameState` autoload (singleton).** Holds persistent run-independent state: pyre fills (per color), unlocked hub features, active skill cap, cantrip upgrades, equipped sigil, post-boss flag. Save/load via Godot's `ResourceSaver` to a `user://` save file. Emits `pyre_filled`, `boss_triggered`, `boss_defeated` signals.

- **`SkillSystem` (per-run service, on Player node).** Holds active-skill list (max = current cap), each entry = `{base_color, modifier_stack[], locked: bool}`. Methods: `add_minor(color)`, `add_elder(color)` (with replace-prompt callback), `switch_active(index)`. Sword node subscribes to `active_skill_changed` to update visuals + on-hit effect. Reset on extraction or death.

- **`SoulEconomy`.** Tracks soul carry pool (color → count, broken by tier). Methods: `pickup(color, tier)`, `deposit_to_pyres()` (called on descent), `drain_for_altar(color, amount)`, `consume_elder_for_retry()`.

- **`Escalation` (per-arena instance).** Per-corner heat values, global alarm curve, soul-pickup heat additions. Drives spawn rates via signals to the Spawner. Resets on player leaving upstairs.

- **`Spawner` (per-arena, listens to Escalation).** Reads heat → emits enemy entities at corner spawn anchors. Color/tier picked from corner heat profile + global modifiers.

- **`DialoguePool` (Resource type).** Lines tagged by event (`death_normal`, `death_boss`, `flame_drain`, etc.). Necromancer node picks weighted-random line, displays via UI text or VO audio.

### Data resources (Godot `Resource` types)

- **`ColorDef`** — color name, RGB, base cast scene, modifier function, sword overlay. One per color.
- **`DragonStats`** — tier, color, HP, damage, soul drops, behavior tree key. One per color × tier.
- **`Sigil`** — name, description, run-modifier hooks. (Post-MVP content.)
- **`HubFeature`** — order index (which 50% milestone unlocks it), feature scene, description. List of 6.

### Camera
Single `Camera3D` autoloaded as `GameCamera`, follows player with damped lag. State-controlled overrides:
- `idle` (default follow)
- `dense_combat` (zoom out, listens to enemy count signal)
- `boss` (full pullback, framed on dragon + player)
- `cutscene` (manual keyframe)

### Save format
Single resource: `user://save.tres`. Persists pyre fills, hub-unlock state, active skill cap, cantrip-stone purchases, equipped sigil, post-boss flag. Versioned for future migrations.

### Testing strategy
GdUnit4 unit tests for:
- Soul stacking math (add minor / add elder / replace flow).
- Pyre fill economy (deposit math, threshold triggers).
- Game state transitions (idle → boss-pending → boss-active → resolved).
- Escalation curve calculations.

PlayGodot E2E tests deferred (custom Godot fork required).

---

## 7 — MVP scope cut & build order

### MVP definition
A complete loop from spawn → upstairs farming → soul stacking → descent extraction → meta-progression → all 6 pyres lit → boss fight → victory ending. Playable. Tunable. Not pretty.

### IN MVP scope

| Area | What's in |
|---|---|
| World | Main hall, upstairs (6 corners), courtyard. Basement geometry not built. |
| Player | Skeleton with rusty sword, auto-melee, WASD movement, dash (Space), manual cast (left-click), skill switch (1–N keys). |
| Colors | All 6 primary (Red, Blue, Green, Purple/Shadow, Gold/Lightning, White/Bone). Cast + modifier + sword overlay each. |
| Enemies | Welp, Dragon, Elder Dragon — 3 tiers × 6 colors = 18 variants (parameterized from `DragonStats` resources). Boss dragon. Black summoned whelps for boss. |
| Soul system | Stacking, cap with replace-prompt, in-run elder scaling, sword-element inheritance, manual switching. |
| Pyres | 6 primary pyres, milestones at 25/50/75/100, +1 cap per 100%, hub feature unlocks at 50%. |
| Hub features | 4 of 6: Soul Altar, Cantrip Stones, Sigil Forge, Trial Chamber. (5th and 6th 50%-milestone slots = placeholder passive bonus until v2.) |
| Sigils | 3–5 sigils for Sigil Forge to surface (placeholder breadth, real-content depth). |
| Trial Chamber | 2–3 trial conditions (placeholder content). |
| Escalation | Per-corner heat + soul-pickup heat + time alarm (retreat-cuts-off mechanic). |
| Descent prompt | Full logic: normal extract / final-pyre fight / retry fight (elder cost). |
| Cutscene | Cinematic flame-drain into necromancer + transformation. Mid-fidelity (camera + simple FX, not pre-rendered). |
| Boss fight | 3-phase dragon in courtyard, 360° whelp summons, telegraphed attacks. |
| Necromancer dialogue | Text-only with VO support hooks ready. ~20 death lines, ~10 boss-fight lines. |
| Save/load | Single save slot, `user://save.tres`. |
| Audio | Placeholder SFX (free pack), placeholder music (1–2 ambient loops). Real audio = post-MVP. |
| Tests | GdUnit4 unit tests for soul stacking, pyre economy, state transitions, escalation math. |

### DEFERRED post-MVP

- Basement floors 1–6 + secondary color content (Crimson, Silver, Bronze, Teal, Amber, Magenta) with placeholder kit identities.
- Black soul (13th), true ending, post-game arc.
- 5th and 6th hub features (full content).
- Custom audio (music + voiced dialogue).
- PlayGodot E2E tests (requires custom Godot fork).
- Web/desktop export pipeline + deployment.
- Steam achievements / leaderboards.
- Localization.

### Build order — vertical slice first, then breadth, then polish

| Phase | Goal | Est. effort |
|---|---|---|
| **1 — Vertical slice** | Player + ONE corner + ONE color (Red) + one pyre + descent loop. Prove the up/down/deposit loop is fun. | ~2 wk |
| **2 — Skill system** | Soul stacking math, replace prompt, sword-element inheritance, manual switch, cooldown casts. Active skill cap. Locked to 1–3 colors for now. | ~2 wk |
| **3 — Breadth: colors + corners** | All 6 colors, all 6 corners with corner-heat. Spawner, escalation, time-alarm, retreat-cutoff. | ~3 wk |
| **4 — Meta loop** | 6 pyres, milestones, hub feature scaffolding (4 features, minimal content), save/load, active-skill-cap progression. | ~2 wk |
| **5 — Boss + endgame** | Cutscene, courtyard, boss 3-phase kit, death dialogue, retry flow, victory animation. | ~2 wk |
| **6 — Polish + tuning** | Number-tuning pass, dialogue line writing, particle FX, HUD polish, audio integration (placeholder). | ~2 wk |

**~13 weeks total** at solo-developer pace. Will compress or expand based on actual velocity.

### Top risks (and mitigations)

1. **Skill stacking edge cases** — combinatorial modifier interactions. *Mitigation:* `ColorDef` resources keep modifier logic isolated per color; GdUnit4 tests cover each combination.
2. **Heat curve tuning** — the "retreat becomes a fight" feel is hard to balance. *Mitigation:* curve values in editable resource files; playtest at end of phase 3 and revisit.
3. **Boss-fight feel** — 3-phase boss is content-heavy. *Mitigation:* phase 5 starts with a stub boss (single-phase) and adds phases iteratively.
4. **Asset volume** — 18 dragon variants + boss + environment. *Mitigation:* parameterized scenes that swap mesh + material from `DragonStats` resources. One model per tier, recolored × 6.

### Acceptance criteria for "MVP shippable"

- [ ] Player can complete a full run (spawn → upstairs → die OR extract).
- [ ] Soul stacking works for all 6 colors with all combinations of modifiers.
- [ ] All 6 pyres can be filled to 100%.
- [ ] Boss fight is winnable by a confident player (playtested).
- [ ] Save persists across sessions; meta-progression survives quit.
- [ ] No crashes during a 30-minute play session.
- [ ] All death paths trigger appropriate dialogue.

---

## Appendix A — Open tuning numbers (not yet locked)

The following are starting values to be revisited during phase 6 polish:

- Pyre fill cap: 250 units
- Dash cooldown: 2.0s
- Dash distance: 4.0m
- Sword swing rate: 1/sec
- Cast cooldown range: 3–5s (per color)
- Per-corner heat ramp: +5/sec build, -2/sec decay
- Soul-pickup heat: welp = +1, dragon = +3, elder = +10
- In-run elder scaling: +12% spawn rate, +8% enemy HP per elder taken
- Time-alarm onset: full retreat-blocked threshold reached at ~minute 5–7

## Appendix B — Deferred post-MVP design surface

Items that need a separate design pass before implementation:

- 6 secondary color kit identities (cast shape + modifier each).
- 6 basement floor layouts.
- Black soul kit (13th color, necromancer's stolen abilities).
- True ending sequence and unlock condition.
- 5th and 6th hub feature definitions.
- Sigil content library (target: 15+ sigils for full release).
- Trial Chamber challenge library.
- Localization framework.
- Audio direction (composer brief, SFX library, VO casting).
