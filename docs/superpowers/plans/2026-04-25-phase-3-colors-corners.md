# Phase 3 — Colors + Corners + Tiers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal:** Expand from 2 colors / 1 enemy tier / 1 spawner to the full upstairs game world: **6 primary colors** with casts and welp variants, **6 corners** with stone walls between them and per-corner color identity, **per-corner heat** that ramps spawn intensity locally, **3 enemy tiers** (welp/dragon/elder dragon) with tier-appropriate drops, and a **time-alarm escalation** that eventually starts spawning enemies near the staircase to cut off retreat.

**Architecture:**
- 4 new color modules added to the existing per-color scene set (cast scene + welp variant + dictionary entries in player/sword/soul_pickup).
- Upstairs scene restructured: hexagonal arena with 6 corner sub-zones marked by Area3D triggers and visual stone walls.
- One spawner per corner, configured with its own color. Spawners replace the single global welp_spawner.
- New `Escalation` autoload-style service tracks per-corner heat (+5/sec inside, -2/sec outside, capped 0–100), global soul-pickup heat, and time-alarm curve.
- Spawn rate per corner = `base × heat_factor`. Heat factor = `1.0 + corner_heat / 50.0` (1.0 at 0 heat, 3.0 at 100).
- Tier roll: heat <30 → all welps; 30–70 → 75% welp / 25% dragon; 70+ → 50% welp / 35% dragon / 15% elder.
- Time-alarm: separate per-arena timer that ramps to spawn enemies *near the staircase* after ~5 minutes of upstairs presence.

**Tech Stack:** Godot 4.6.2, GDScript, GdUnit4. Same as Phase 1+2.

**Spec reference:** [`docs/superpowers/specs/2026-04-25-new-chance-design.md`](../specs/2026-04-25-new-chance-design.md) §3 Heat / escalation, §2 Upstairs layout.

**Phase 3 scope (vs full design):**
- ✅ All 6 primary colors with cast + welp variants
- ✅ 6 corner sub-zones with visual separation
- ✅ Per-corner heat mechanic
- ✅ Color-per-corner spawning
- ✅ 3 enemy tiers per color: welp / dragon / elder dragon
- ✅ Time-alarm: spawns "alarm welps" near staircase late in run
- ❌ In-run elder-soul scaling (Phase 4 — ties to active skill cap)
- ❌ Pyre milestones / hub features (Phase 4)
- ❌ Boss flow (Phase 5)
- ❌ Real elemental modifier effects (still placeholder; full effects = Phase 6)
- ❌ Polished enemy animations / models (Phase 6)

**Acceptance test for Phase 3:**
Player walks upstairs into a hexagonal arena with 6 distinct corner sub-zones (visual: red/blue/green/purple/gold/white-tinted floor tiles or wall accents). Each corner spawns only its color of dragons. Standing in one corner ramps heat — spawns get faster and tier mix shifts toward dragon/elder dragon. Moving out cools the heat. After ~5 minutes, alarm welps start spawning near the staircase even if no corner is hot. Killing a dragon yields 2–3 minor souls; killing an elder dragon yields 1 elder soul + 2–3 minor souls. SkillSystem unlocks Skill 1 from any first soul, additional minor souls modify it, elder unlocks new skill (with replace prompt at cap). All 6 cast types fire properly. Sword tints match the active skill's color across all 6 hues + bone-rusty default.

---

## File structure additions

**Created:**
```
scenes/skills/
├── cast_green_plague.tscn
├── cast_purple_void.tscn
├── cast_gold_lightning.tscn
└── cast_white_bone.tscn
scenes/entities/
├── welp_green.tscn
├── welp_purple.tscn
├── welp_gold.tscn
├── welp_white.tscn
├── dragon.tscn          # Mid-tier, color-parameterized
└── elder_dragon.tscn    # Top-tier, color-parameterized
scripts/skills/
├── cast_green_plague.gd
├── cast_purple_void.gd
├── cast_gold_lightning.gd
└── cast_white_bone.gd
scripts/entities/
├── dragon.gd            # Inherits welp.gd-like AI, more HP
└── elder_dragon.gd      # Same, much more HP, telegraphed presence
scripts/world/
├── corner_spawner.gd    # Replaces welp_spawner.gd — per-corner zone-aware
└── escalation.gd        # Autoload: heat tracking, spawn rate, tier roll, time-alarm
test/
└── test_escalation.gd   # Heat curve, tier roll, time-alarm
```

**Modified:**
- `scripts/entities/player.gd` — `_scene_for_color` match expanded to all 6 colors.
- `scripts/entities/sword.gd` — `COLOR_TINTS` expanded.
- `scripts/interactables/soul_pickup.gd` — `TINTS` expanded.
- `scripts/entities/welp.gd` — drop logic conditional on tier (welp drops 1 minor; dragon drops 2–3 minor; elder drops 1 elder + 2–3 minor).
- `scenes/world/upstairs.tscn` — replace single arena with 6-corner layout.
- `project.godot` — register `Escalation` autoload.

---

## Task 1: Cast scenes + scripts for green/purple/gold/white

Adds 4 cast types matching the spec mapping (Plague AoE / Void gravity well / Lightning bolt / Bone wall — Phase 3 stubs all behave like projectiles for simplicity; richer behaviors are Phase 6 polish).

**Files (per color, ×4):**
- Create: `scripts/skills/cast_<color>_<name>.gd` (extends CastBase)
- Create: `scenes/skills/cast_<color>_<name>.tscn`

### Step 1: Implement all four cast scripts

Each follows the same fireball-like template (projectile that flies, hits enemy, queue_frees on impact — except Bone which pierces). Pattern:

```gdscript
extends CastBase

const PROJECTILE_SPEED: float = 12.0  # tweak per color

@export var direction: Vector3 = Vector3.FORWARD

func _ready() -> void:
	var area: Area3D = $HitArea
	area.body_entered.connect(_on_body_entered)
	area.monitoring = true

func _physics_process(delta: float) -> void:
	global_position += direction.normalized() * PROJECTILE_SPEED * delta

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemy"):
		_on_hit_enemy(body)
		queue_free()
```

Per-color tuning:
- **Green (Plague):** speed 10, single-hit-then-queue-free. Visual: green emissive sphere.
- **Purple (Void):** speed 8, single-hit (Phase 6 will add gravity well). Visual: dark purple sphere.
- **Gold (Lightning):** speed 16 (fastest — instant feel). Visual: bright yellow sphere.
- **White (Bone):** speed 14, **pierces** like ice line (uses `_hit_enemies` set to dedupe). Visual: bone-white sphere.

Create four files with identical structure, only `PROJECTILE_SPEED`, scene path, and `queue_free` behavior differing.

For Bone (pierce):

```gdscript
extends CastBase
const PROJECTILE_SPEED: float = 14.0
@export var direction: Vector3 = Vector3.FORWARD
var _hit_enemies: Array[Node] = []

func _ready() -> void:
	var area: Area3D = $HitArea
	area.body_entered.connect(_on_body_entered)
	area.monitoring = true

func _physics_process(delta: float) -> void:
	global_position += direction.normalized() * PROJECTILE_SPEED * delta

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemy") and not (body in _hit_enemies):
		_hit_enemies.append(body)
		_on_hit_enemy(body)
```

### Step 2: Build all four cast scenes (`.tscn` text)

Each follows the fireball template (1 ext_resource for script, 4 sub_resources: SphereShape3D + SphereMesh + StandardMaterial3D, root Node3D with HitArea + Mesh children). Sphere radius 0.4 for collision, 0.3 for visual mesh. Use these material colors:

- Green: albedo `Color(0.3, 0.8, 0.3, 1)`, emission same, energy 4.0
- Purple: albedo `Color(0.5, 0.2, 0.7, 1)`, emission `Color(0.6, 0.3, 0.8, 1)`, energy 3.5
- Gold: albedo `Color(1, 0.9, 0.3, 1)`, emission same, energy 4.5
- White: albedo `Color(0.9, 0.9, 0.85, 1)`, emission same, energy 3.5

Reference structure (substitute color name and material values):

```
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://scripts/skills/cast_<color>_<name>.gd" id="1_cast"]

[sub_resource type="SphereShape3D" id="SphereShape3D_<color>"]
radius = 0.4

[sub_resource type="SphereMesh" id="SphereMesh_<color>"]
radius = 0.3
height = 0.6

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_<color>"]
albedo_color = Color(R, G, B, 1)
emission_enabled = true
emission = Color(R, G, B, 1)
emission_energy_multiplier = ENERGY

[node name="Cast<Color><Name>" type="Node3D"]
script = ExtResource("1_cast")

[node name="HitArea" type="Area3D" parent="."]
collision_layer = 0
collision_mask = 2

[node name="CollisionShape3D" type="CollisionShape3D" parent="HitArea"]
shape = SubResource("SphereShape3D_<color>")

[node name="Mesh" type="MeshInstance3D" parent="."]
mesh = SubResource("SphereMesh_<color>")
material_override = SubResource("StandardMaterial3D_<color>")
```

### Step 3: Update player.gd to know all 6 colors

Read `scripts/entities/player.gd`. Add 4 PackedScene preload constants near the existing CAST_RED_FIREBALL / CAST_BLUE_ICE_LINE:

```gdscript
const CAST_GREEN_PLAGUE: PackedScene = preload("res://scenes/skills/cast_green_plague.tscn")
const CAST_PURPLE_VOID: PackedScene = preload("res://scenes/skills/cast_purple_void.tscn")
const CAST_GOLD_LIGHTNING: PackedScene = preload("res://scenes/skills/cast_gold_lightning.tscn")
const CAST_WHITE_BONE: PackedScene = preload("res://scenes/skills/cast_white_bone.tscn")
```

Update `_scene_for_color`:

```gdscript
func _scene_for_color(color: String) -> PackedScene:
	match color:
		"red": return CAST_RED_FIREBALL
		"blue": return CAST_BLUE_ICE_LINE
		"green": return CAST_GREEN_PLAGUE
		"purple": return CAST_PURPLE_VOID
		"gold": return CAST_GOLD_LIGHTNING
		"white": return CAST_WHITE_BONE
		_: return null
```

### Step 4: Update sword.gd COLOR_TINTS

Replace the existing dictionary:

```gdscript
const COLOR_TINTS: Dictionary = {
	"": Color(0.55, 0.5, 0.42, 1),   # default rusty
	"red": Color(1, 0.3, 0.1, 1),
	"blue": Color(0.4, 0.7, 1, 1),
	"green": Color(0.3, 0.85, 0.3, 1),
	"purple": Color(0.6, 0.3, 0.8, 1),
	"gold": Color(1, 0.9, 0.3, 1),
	"white": Color(0.95, 0.95, 0.9, 1),
}
```

### Step 5: Update soul_pickup.gd TINTS

```gdscript
const TINTS: Dictionary = {
	"red": Color(1, 0.4, 0.2, 1),
	"blue": Color(0.4, 0.7, 1, 1),
	"green": Color(0.4, 0.9, 0.4, 1),
	"purple": Color(0.6, 0.3, 0.85, 1),
	"gold": Color(1, 0.9, 0.4, 1),
	"white": Color(0.95, 0.95, 0.9, 1),
}
```

### Step 6: Verify import + tests

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . --import 2>&1 | grep -i error | head -5
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
```
Expected: no errors, 61 tests still pass.

### Step 7: Commit

```bash
git add scripts/skills/cast_*.gd scenes/skills/cast_*.tscn scripts/entities/player.gd scripts/entities/sword.gd scripts/interactables/soul_pickup.gd
git commit -m "feat(skills): add green/purple/gold/white casts + extend color dictionaries"
```

---

## Task 2: Welp variants for the 4 new colors

**Files (×4):**
- Create: `scenes/entities/welp_green.tscn`
- Create: `scenes/entities/welp_purple.tscn`
- Create: `scenes/entities/welp_gold.tscn`
- Create: `scenes/entities/welp_white.tscn`

### Step 1: Build each scene as text

Same template as `welp_blue.tscn`, override `color` and material albedo:

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/entities/welp.gd" id="1_welp"]

[sub_resource type="BoxShape3D" id="BoxShape3D_welp"]
size = Vector3(0.7, 0.7, 0.7)

[sub_resource type="BoxMesh" id="BoxMesh_welp"]
size = Vector3(0.7, 0.7, 0.7)

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_welp_<color>"]
albedo_color = Color(R, G, B, 1)

[node name="Welp" type="CharacterBody3D"]
script = ExtResource("1_welp")
color = "<color>"

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
shape = SubResource("BoxShape3D_welp")

[node name="Mesh" type="MeshInstance3D" parent="."]
mesh = SubResource("BoxMesh_welp")
material_override = SubResource("StandardMaterial3D_welp_<color>")
```

Albedo per color:
- Green: `Color(0.2, 0.6, 0.2, 1)`
- Purple: `Color(0.4, 0.2, 0.6, 1)`
- Gold: `Color(0.8, 0.7, 0.2, 1)`
- White: `Color(0.8, 0.8, 0.78, 1)`

### Step 2: Verify import + commit

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . --import 2>&1 | grep -i error | head -5
git add scenes/entities/welp_*.tscn
git commit -m "feat(welp): green/purple/gold/white welp variants"
```

---

## Task 3: Dragon + Elder Dragon tiers

**Files:**
- Create: `scripts/entities/dragon.gd` (extends welp.gd or shares AI; new HP/damage tunables)
- Create: `scripts/entities/elder_dragon.gd`
- Create: `scenes/entities/dragon.tscn`
- Create: `scenes/entities/elder_dragon.tscn`
- Modify: `scripts/entities/welp.gd` — drop logic now reads `tier` field

### Step 1: Refactor welp.gd to support tier-based drops

Read `scripts/entities/welp.gd`. Add:

```gdscript
@export var tier: String = "welp"  # "welp" | "dragon" | "elder"
```

Replace the death-time pickup logic in `take_damage`:

```gdscript
func take_damage(amount: int) -> void:
	if _is_dead:
		return
	hp = max(0, hp - amount)
	if hp == 0:
		_is_dead = true
		_drop_souls()
		died.emit(self, color)
		queue_free()

func _drop_souls() -> void:
	# welp: 1 minor; dragon: 2-3 minor; elder: 1 elder + 2-3 minor
	var minor_count: int = 1 if tier == "welp" else (2 + (1 if randf() < 0.5 else 0))
	for i in range(minor_count):
		_spawn_pickup("minor", _random_offset())
	if tier == "elder":
		_spawn_pickup("elder", _random_offset())

func _spawn_pickup(pickup_tier: String, offset: Vector3) -> void:
	var pickup: Area3D = SOUL_PICKUP_SCENE.instantiate()
	pickup.color = color
	pickup.tier = pickup_tier
	pickup.global_position = global_position + offset
	get_parent().add_child(pickup)

func _random_offset() -> Vector3:
	return Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
```

### Step 2: Tune welp/dragon/elder stats

Welp keeps current values (HP=30, MOVE_SPEED=3.6, ATTACK_DAMAGE=10).

Dragon = welp + bigger:
- MAX_HP=80, MOVE_SPEED=3.0, ATTACK_DAMAGE=18, ATTACK_INTERVAL=2.0, ATTACK_RANGE=1.2

Elder Dragon = much bigger:
- MAX_HP=200, MOVE_SPEED=2.5, ATTACK_DAMAGE=30, ATTACK_INTERVAL=2.5, ATTACK_RANGE=1.4

Approach: keep ALL tier-specific stat differences in script properties (`@export`), and in the .tscn override values per scene. Same script (`welp.gd`) is reused — the .tscn just sets different property defaults.

For dragon scene, use `welp.gd` script but override stats. Body size 1.0×1.2×1.0 (visibly bigger). For elder, body size 1.5×1.8×1.5.

### Step 3: Build dragon.tscn

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/entities/welp.gd" id="1_welp"]

[sub_resource type="BoxShape3D" id="BoxShape3D_dragon"]
size = Vector3(1.0, 1.2, 1.0)

[sub_resource type="BoxMesh" id="BoxMesh_dragon"]
size = Vector3(1.0, 1.2, 1.0)

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_dragon"]
albedo_color = Color(0.5, 0.1, 0.1, 1)

[node name="Dragon" type="CharacterBody3D"]
script = ExtResource("1_welp")
color = "red"
tier = "dragon"
move_speed = 3.0
attack_damage = 18
attack_range = 1.2
attack_interval = 2.0

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
shape = SubResource("BoxShape3D_dragon")

[node name="Mesh" type="MeshInstance3D" parent="."]
mesh = SubResource("BoxMesh_dragon")
material_override = SubResource("StandardMaterial3D_dragon")
```

**Note:** the script's `MAX_HP` is a `const` not `@export`, so dragon spawns with HP=30 same as welp. **Migrate `MAX_HP` to `@export var max_hp` in welp.gd** so the .tscn can override it. Default 30 for welp; .tscn overrides for dragon (80) and elder (200).

In welp.gd: change `const MAX_HP: int = 30` to `@export var max_hp: int = 30`. Update all references from `MAX_HP` to `max_hp`. Update `var hp: int = MAX_HP` to a default + reset in `_ready`:

```gdscript
@export var max_hp: int = 30

var hp: int = max_hp

func _ready() -> void:
	hp = max_hp
	add_to_group("enemy")
	collision_layer = 2
	_find_player()
```

(The hp default initializer runs *before* `@export` is set from the .tscn, so we re-set hp in `_ready` to the @export value.)

Add `max_hp = 80` to dragon.tscn root and `max_hp = 200` to elder_dragon.tscn root.

### Step 4: Build elder_dragon.tscn

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/entities/welp.gd" id="1_welp"]

[sub_resource type="BoxShape3D" id="BoxShape3D_elder"]
size = Vector3(1.5, 1.8, 1.5)

[sub_resource type="BoxMesh" id="BoxMesh_elder"]
size = Vector3(1.5, 1.8, 1.5)

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_elder"]
albedo_color = Color(0.7, 0.1, 0.1, 1)
emission_enabled = true
emission = Color(0.4, 0.05, 0.05, 1)
emission_energy_multiplier = 1.0

[node name="ElderDragon" type="CharacterBody3D"]
script = ExtResource("1_welp")
color = "red"
tier = "elder"
max_hp = 200
move_speed = 2.5
attack_damage = 30
attack_range = 1.4
attack_interval = 2.5

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
shape = SubResource("BoxShape3D_elder")

[node name="Mesh" type="MeshInstance3D" parent="."]
mesh = SubResource("BoxMesh_elder")
material_override = SubResource("StandardMaterial3D_elder")
```

### Step 5: Verify tests + import

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . --import 2>&1 | grep -i error | head -10
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
```

Expected: no errors, 61 tests still pass. Welp tests use bare CharacterBody3D so the @export migration of max_hp shouldn't break them — but verify.

### Step 6: Commit

```bash
git add scripts/entities/welp.gd scenes/entities/dragon.tscn scenes/entities/elder_dragon.tscn
git commit -m "feat(enemies): dragon + elder dragon tiers via welp.gd parameterization, tier-based drops"
```

---

## Task 4: Escalation autoload — heat tracking + tier roll

**Files:**
- Create: `scripts/world/escalation.gd`
- Create: `test/test_escalation.gd`
- Modify: `project.godot` (register Escalation autoload)

### Step 1: Write failing tests

Create `test/test_escalation.gd`:

```gdscript
extends GdUnitTestSuite

const EscalationScript = preload("res://scripts/world/escalation.gd")

var esc: Node

func before_test() -> void:
	esc = auto_free(EscalationScript.new())
	add_child(esc)

func test_heat_starts_at_zero() -> void:
	assert_that(esc.corner_heat("red")).is_equal(0.0)

func test_heat_ramps_up_when_in_corner() -> void:
	esc.set_player_in_corner("red")
	esc.tick(1.0)  # 1 second
	assert_that(esc.corner_heat("red")).is_equal_approx(5.0, 0.01)

func test_heat_decays_when_player_leaves_corner() -> void:
	esc.set_player_in_corner("red")
	esc.tick(10.0)  # 50 heat
	esc.set_player_in_corner("")  # leave
	esc.tick(5.0)  # decay 10 (-2/s × 5s)
	assert_that(esc.corner_heat("red")).is_equal_approx(40.0, 0.01)

func test_heat_capped_at_100() -> void:
	esc.set_player_in_corner("red")
	esc.tick(60.0)  # would go 300 if uncapped
	assert_that(esc.corner_heat("red")).is_equal(100.0)

func test_heat_floor_at_zero() -> void:
	esc.tick(10.0)  # decay from 0
	assert_that(esc.corner_heat("red")).is_equal(0.0)

func test_spawn_rate_factor_scales_with_heat() -> void:
	# heat 0 → factor 1.0; heat 50 → 2.0; heat 100 → 3.0
	assert_that(esc.spawn_rate_factor(0.0)).is_equal_approx(1.0, 0.01)
	assert_that(esc.spawn_rate_factor(50.0)).is_equal_approx(2.0, 0.01)
	assert_that(esc.spawn_rate_factor(100.0)).is_equal_approx(3.0, 0.01)

func test_tier_roll_low_heat_only_welps() -> void:
	# heat <30 → always welp
	for i in range(20):
		assert_that(esc.roll_tier(20.0)).is_equal("welp")

func test_tier_roll_mid_heat_includes_dragons() -> void:
	# heat 30-70 → may roll dragon
	var has_dragon: bool = false
	var has_welp: bool = false
	for i in range(50):
		var t: String = esc.roll_tier(50.0)
		if t == "dragon":
			has_dragon = true
		elif t == "welp":
			has_welp = true
	assert_that(has_dragon).is_true()
	assert_that(has_welp).is_true()

func test_tier_roll_high_heat_includes_elders() -> void:
	var has_elder: bool = false
	for i in range(80):
		if esc.roll_tier(85.0) == "elder":
			has_elder = true
			break
	assert_that(has_elder).is_true()

func test_time_alarm_starts_at_zero() -> void:
	assert_that(esc.time_alarm_factor()).is_equal_approx(0.0, 0.01)

func test_time_alarm_ramps_with_upstairs_time() -> void:
	esc.set_player_upstairs(true)
	esc.tick(150.0)  # 2.5 minutes
	assert_that(esc.time_alarm_factor()).is_greater(0.0)
	assert_that(esc.time_alarm_factor()).is_less(1.0)

func test_time_alarm_reaches_full_after_5_minutes() -> void:
	esc.set_player_upstairs(true)
	esc.tick(300.0)  # 5 minutes
	assert_that(esc.time_alarm_factor()).is_equal_approx(1.0, 0.05)

func test_time_alarm_resets_on_leaving_upstairs() -> void:
	esc.set_player_upstairs(true)
	esc.tick(180.0)
	esc.set_player_upstairs(false)
	assert_that(esc.time_alarm_factor()).is_equal_approx(0.0, 0.01)

func test_reset_clears_all_state() -> void:
	esc.set_player_in_corner("red")
	esc.tick(10.0)
	esc.set_player_upstairs(true)
	esc.tick(60.0)
	esc.reset()
	assert_that(esc.corner_heat("red")).is_equal(0.0)
	assert_that(esc.time_alarm_factor()).is_equal(0.0)
```

### Step 2: Run tests — verify failures

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_escalation.gd --ignoreHeadlessMode
```

### Step 3: Implement Escalation

Create `scripts/world/escalation.gd`:

```gdscript
extends Node

const COLORS: Array[String] = ["red", "blue", "green", "purple", "gold", "white"]
const HEAT_BUILD_PER_SEC: float = 5.0
const HEAT_DECAY_PER_SEC: float = 2.0
const HEAT_CAP: float = 100.0
const TIME_ALARM_FULL_SECONDS: float = 300.0  # 5 minutes

var _heat: Dictionary = {}  # color -> float
var _player_in_corner: String = ""
var _player_upstairs: bool = false
var _upstairs_time: float = 0.0

func _ready() -> void:
	reset()
	set_process(true)

func _process(delta: float) -> void:
	tick(delta)

func tick(delta: float) -> void:
	for color in COLORS:
		var h: float = _heat[color]
		if color == _player_in_corner:
			h = min(HEAT_CAP, h + HEAT_BUILD_PER_SEC * delta)
		else:
			h = max(0.0, h - HEAT_DECAY_PER_SEC * delta)
		_heat[color] = h
	if _player_upstairs:
		_upstairs_time += delta

func corner_heat(color: String) -> float:
	return _heat.get(color, 0.0)

func set_player_in_corner(color: String) -> void:
	_player_in_corner = color

func set_player_upstairs(value: bool) -> void:
	_player_upstairs = value
	if not value:
		_upstairs_time = 0.0

func spawn_rate_factor(heat: float) -> float:
	# heat 0 → 1.0; heat 100 → 3.0
	return 1.0 + (heat / HEAT_CAP) * 2.0

func roll_tier(heat: float) -> String:
	if heat < 30.0:
		return "welp"
	if heat < 70.0:
		# 75% welp / 25% dragon
		return "dragon" if randf() < 0.25 else "welp"
	# 50% welp / 35% dragon / 15% elder
	var r: float = randf()
	if r < 0.15:
		return "elder"
	if r < 0.50:
		return "dragon"
	return "welp"

func time_alarm_factor() -> float:
	return min(1.0, _upstairs_time / TIME_ALARM_FULL_SECONDS)

func reset() -> void:
	_heat.clear()
	for color in COLORS:
		_heat[color] = 0.0
	_player_in_corner = ""
	_player_upstairs = false
	_upstairs_time = 0.0
```

### Step 4: Run tests — verify pass

Same command as Step 2. Expected: 13 tests pass.

Then full suite:
```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
```

Expected: 74 tests pass (61 + 13).

### Step 5: Register Escalation as autoload

Add to project.godot `[autoload]` section:
```ini
Escalation="*res://scripts/world/escalation.gd"
```

### Step 6: Commit

```bash
git add scripts/world/escalation.gd test/test_escalation.gd project.godot
git commit -m "feat(escalation): heat tracking + tier roll + time-alarm autoload"
```

---

## Task 5: Per-corner spawner

**Files:**
- Create: `scripts/world/corner_spawner.gd`
- Modify: (Task 6 will instance multiple corner_spawners in upstairs.tscn)

### Step 1: Implement corner spawner

Create `scripts/world/corner_spawner.gd`:

```gdscript
extends Node3D

const WELP_SCENES: Dictionary = {
	"red": preload("res://scenes/entities/welp.tscn"),
	"blue": preload("res://scenes/entities/welp_blue.tscn"),
	"green": preload("res://scenes/entities/welp_green.tscn"),
	"purple": preload("res://scenes/entities/welp_purple.tscn"),
	"gold": preload("res://scenes/entities/welp_gold.tscn"),
	"white": preload("res://scenes/entities/welp_white.tscn"),
}
const DRAGON_SCENE: PackedScene = preload("res://scenes/entities/dragon.tscn")
const ELDER_DRAGON_SCENE: PackedScene = preload("res://scenes/entities/elder_dragon.tscn")

@export var color: String = "red"
@export var base_spawn_interval: float = 3.0  # seconds at heat 0
@export var max_alive: int = 4  # per corner; 6 corners × 4 = 24 max if all hot
@export var spawn_radius: float = 4.0
@export var min_dist_from_player: float = 5.0

var _timer: float = 0.0
var _alive_count: int = 0

func _process(delta: float) -> void:
	var heat: float = Escalation.corner_heat(color)
	var effective_interval: float = base_spawn_interval / Escalation.spawn_rate_factor(heat)
	_timer += delta
	if _timer >= effective_interval and _alive_count < max_alive:
		_timer = 0.0
		_spawn()

func _spawn() -> void:
	var heat: float = Escalation.corner_heat(color)
	var tier: String = Escalation.roll_tier(heat)
	var scene: PackedScene = _scene_for_tier(tier)
	if scene == null:
		return
	var enemy = scene.instantiate()
	if tier in ["dragon", "elder"]:
		# These scenes hardcode color="red" in their .tscn — override with our color
		enemy.color = color
		# Recolor mesh too
		_apply_color_tint(enemy, color)
	enemy.global_position = _pick_spawn_position()
	enemy.died.connect(_on_died)
	get_parent().add_child(enemy)
	_alive_count += 1

func _scene_for_tier(tier: String) -> PackedScene:
	match tier:
		"welp": return WELP_SCENES.get(color, null)
		"dragon": return DRAGON_SCENE
		"elder": return ELDER_DRAGON_SCENE
		_: return null

const COLOR_ALBEDO: Dictionary = {
	"red": Color(0.5, 0.1, 0.1, 1),
	"blue": Color(0.2, 0.4, 0.85, 1),
	"green": Color(0.2, 0.6, 0.2, 1),
	"purple": Color(0.4, 0.2, 0.6, 1),
	"gold": Color(0.8, 0.7, 0.2, 1),
	"white": Color(0.8, 0.8, 0.78, 1),
}

func _apply_color_tint(enemy: Node, c: String) -> void:
	var mesh: MeshInstance3D = enemy.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return
	var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	mat = mat.duplicate() as StandardMaterial3D
	mesh.material_override = mat
	mat.albedo_color = COLOR_ALBEDO.get(c, COLOR_ALBEDO["red"])

func _pick_spawn_position() -> Vector3:
	var player_pos: Vector3 = _get_player_pos()
	for i in range(8):
		var angle: float = randf() * TAU
		var offset: Vector3 = Vector3(cos(angle) * spawn_radius, 1.0, sin(angle) * spawn_radius)
		var pos: Vector3 = global_position + offset
		if player_pos == Vector3.INF:
			return pos
		if pos.distance_to(player_pos) >= min_dist_from_player:
			return pos
	if player_pos == Vector3.INF:
		return global_position + Vector3(spawn_radius, 1.0, 0)
	var away: Vector3 = (global_position - player_pos)
	away.y = 0.0
	if away.length() < 0.001:
		away = Vector3.FORWARD
	return global_position + away.normalized() * spawn_radius + Vector3(0, 1.0, 0)

func _get_player_pos() -> Vector3:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return Vector3.INF
	return players[0].global_position

func _on_died(_enemy: Node, _color: String) -> void:
	_alive_count = max(0, _alive_count - 1)
```

### Step 2: Verify import + commit

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . --import 2>&1 | grep -i error | head -5
git add scripts/world/corner_spawner.gd
git commit -m "feat(spawner): per-corner color-aware spawner with tier roll from heat"
```

---

## Task 6: Restructure upstairs.tscn into 6 corners

**Files:**
- Modify: `scenes/world/upstairs.tscn` — replace single arena with 6-corner layout

The upstairs scene becomes a hexagonal arena. Each corner has:
- Position: hex points around center, radius ~14m
- Color marker: large floor-level disc with that color's tint (visible from above)
- Corner trigger: Area3D BoxShape3D ~12m wide, used to detect player presence
- Spawner: corner_spawner instance with that color set

### Step 1: Build the upstairs scene

Working with hex coords: 6 corners at 60° intervals, radius 14m from center:
- Red: angle 0° → (14, 0, 0)
- Blue: angle 60° → (7, 0, -12.12)
- Green: angle 120° → (-7, 0, -12.12)
- Purple: angle 180° → (-14, 0, 0)
- Gold: angle 240° → (-7, 0, 12.12)
- White: angle 300° → (7, 0, 12.12)

Read the current `scenes/world/upstairs.tscn` to preserve the descent staircase, prompt, player spawn, HUD, etc. Then refactor.

The new upstairs.tscn should have:
- Larger floor (50×0.5×50)
- Walls farther out (around hex perimeter)
- One CornerZone area per corner (Area3D + visual disc + corner_spawner instance)
- Existing DescentStaircase, HUD, DescentPrompt, ReplaceSkillPrompt, DeathHandler at center
- Player + Camera at center

This is a long .tscn — write it carefully. Reference structure (abbreviated for clarity, fill in all 6 corners):

```
[gd_scene load_steps=18 format=3]

[ext_resource type="PackedScene" path="res://scenes/interactables/descent_staircase.tscn" id="2_staircase"]
[ext_resource type="PackedScene" path="res://scenes/ui/descent_prompt.tscn" id="3_prompt"]
[ext_resource type="PackedScene" path="res://scenes/entities/player.tscn" id="4_player"]
[ext_resource type="PackedScene" path="res://scenes/ui/hud.tscn" id="5_hud"]
[ext_resource type="PackedScene" path="res://scenes/ui/replace_skill_prompt.tscn" id="6_replace"]
[ext_resource type="Script" path="res://scripts/world/death_handler.gd" id="7_death"]
[ext_resource type="Script" path="res://scripts/world/corner_spawner.gd" id="8_corner_spawner"]
[ext_resource type="Script" path="res://scripts/world/corner_zone.gd" id="9_corner_zone"]

[sub_resource type="BoxShape3D" id="floor_shape"]
size = Vector3(50, 0.5, 50)
[sub_resource type="BoxMesh" id="floor_mesh"]
size = Vector3(50, 0.5, 50)
[sub_resource type="StandardMaterial3D" id="floor_mat"]
albedo_color = Color(0.18, 0.16, 0.14, 1)

[sub_resource type="Environment" id="env"]
background_mode = 1
background_color = Color(0.02, 0.02, 0.04, 1)
ambient_light_source = 2
ambient_light_color = Color(0.3, 0.3, 0.4, 1)
ambient_light_energy = 0.3

# Corner zone collision shape (re-used for all 6)
[sub_resource type="BoxShape3D" id="zone_shape"]
size = Vector3(10, 6, 10)

# Per-color floor discs (visual markers)
[sub_resource type="CylinderMesh" id="disc_mesh"]
top_radius = 4.0
bottom_radius = 4.0
height = 0.05

[sub_resource type="StandardMaterial3D" id="mat_disc_red"]
albedo_color = Color(0.5, 0.15, 0.1, 0.6)
flags_transparent = true
[sub_resource type="StandardMaterial3D" id="mat_disc_blue"]
albedo_color = Color(0.2, 0.4, 0.7, 0.6)
flags_transparent = true
# ... and so on for green, purple, gold, white

[node name="Upstairs" type="Node3D"]

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("env")

[node name="DirectionalLight3D" type="DirectionalLight3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 0.7071, 0.7071, 0, -0.7071, 0.7071, 0, 8, 0)
light_color = Color(0.7, 0.7, 0.9, 1)
light_energy = 0.4

[node name="Floor" type="StaticBody3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.25, 0)
[node name="CollisionShape3D" type="CollisionShape3D" parent="Floor"]
shape = SubResource("floor_shape")
[node name="Mesh" type="MeshInstance3D" parent="Floor"]
mesh = SubResource("floor_mesh")
material_override = SubResource("floor_mat")

# Red corner (angle 0°, position 14, 0, 0)
[node name="RedCorner" type="Node3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 14, 0, 0)

[node name="Disc" type="MeshInstance3D" parent="RedCorner"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.1, 0)
mesh = SubResource("disc_mesh")
material_override = SubResource("mat_disc_red")

[node name="Zone" type="Area3D" parent="RedCorner"]
script = ExtResource("9_corner_zone")
zone_color = "red"
[node name="CollisionShape3D" type="CollisionShape3D" parent="RedCorner/Zone"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0)
shape = SubResource("zone_shape")

[node name="Spawner" type="Node3D" parent="RedCorner"]
script = ExtResource("8_corner_spawner")
color = "red"

# Blue corner (angle 60°, position 7, 0, -12.12)
[node name="BlueCorner" type="Node3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 7, 0, -12.12)
# ... (same structure as RedCorner with blue material + color="blue")

# Repeat for green, purple, gold, white at their hex positions

# Center / hub area (descent staircase + UI)
[node name="DescentStaircase" parent="." instance=ExtResource("2_staircase")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.1, 0)
prompt_path = NodePath("../DescentPrompt")

[node name="Camera3D" type="Camera3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 0.5736, 0.8192, 0, -0.8192, 0.5736, 0, 18, 12)

[node name="Player" parent="." instance=ExtResource("4_player")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 6)

[node name="HUD" parent="." instance=ExtResource("5_hud")]
[node name="DescentPrompt" parent="." instance=ExtResource("3_prompt")]
[node name="ReplaceSkillPrompt" parent="." instance=ExtResource("6_replace")]

[node name="DeathHandler" type="Node" parent="."]
script = ExtResource("7_death")
```

This is a sketch — fill in all 6 corners completely. Bump load_steps appropriately. The Camera transform has been pulled back since the arena is bigger (was at 12,8 with 50° pitch; now at 18,12 to see the full hex from above).

Implementation note: this scene is large and tedious to hand-write. Suggest building it in steps: write the floor + camera + UI, verify it loads, then add one corner at a time, verifying after each.

### Step 2: Implement corner_zone.gd

Create `scripts/world/corner_zone.gd`:

```gdscript
extends Area3D

@export var zone_color: String = ""

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		Escalation.set_player_in_corner(zone_color)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		# Only clear if the player was in THIS zone (avoids clobbering when moving zone-to-zone)
		if Escalation._player_in_corner == zone_color:
			Escalation.set_player_in_corner("")
```

(Accessing the `_player_in_corner` private var from outside is poor form — refactor: have Escalation expose a `current_corner()` getter.)

Refactor Escalation.gd to add:
```gdscript
func current_corner() -> String:
	return _player_in_corner
```

And update corner_zone.gd to use it.

### Step 3: Verify import + tests

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . --import 2>&1 | grep -i error | head -10
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
```

Expected: no errors, 74 tests still pass.

### Step 4: Commit

```bash
git add scenes/world/upstairs.tscn scripts/world/corner_zone.gd scripts/world/escalation.gd
git commit -m "feat(upstairs): hexagonal 6-corner arena with per-corner zones + spawners"
```

---

## Task 7: Wire upstairs entry/exit to Escalation

**Files:**
- Modify: `scripts/core/game_state.gd` (or upstairs scene) to set `Escalation.set_player_upstairs(true/false)` on transition

### Step 1: Hook end_run / scene transitions

Read `scripts/core/game_state.gd`. Modify `transition_to`:

```gdscript
func transition_to(location: Location) -> void:
	if location == current_location:
		return
	current_location = location
	location_changed.emit(location)
	# Notify Escalation about upstairs presence for time-alarm
	Escalation.set_player_upstairs(location == Location.UPSTAIRS)
	var path: String = scene_path_for(location)
	if path != "":
		get_tree().call_deferred("change_scene_to_file", path)
```

Also reset Escalation on run end:
```gdscript
func end_run(outcome: Outcome) -> void:
	if outcome == Outcome.DESCENDED:
		SoulEconomy.deposit_to_pyres()
	elif outcome == Outcome.DIED:
		SoulEconomy.clear_carry()
	run_ended.emit(outcome)
	Escalation.reset()
	transition_to(Location.MAIN_HALL)
```

### Step 2: Run tests

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
```

Expected: 74 tests still pass. The test_game_state.gd's end_run tests don't check Escalation state, so they should pass without modification. If they fail because they don't have an Escalation autoload registered for the test environment, the autoload should be discoverable since it's registered in project.godot.

### Step 3: Commit

```bash
git add scripts/core/game_state.gd
git commit -m "feat(game-state): notify Escalation on upstairs entry/exit + run reset"
```

---

## Task 8: Time-alarm — spawn alarm welps near staircase

**Files:**
- Create: `scripts/world/alarm_spawner.gd`
- Modify: `scenes/world/upstairs.tscn` (add AlarmSpawner near DescentStaircase)

### Step 1: Implement alarm spawner

Create `scripts/world/alarm_spawner.gd`:

```gdscript
extends Node3D

# Spawns "alarm welps" — black variant with no soul drop — near the staircase
# as time_alarm_factor ramps up. By 5 minutes upstairs, alarm spawns are constant.

const WELP_SCENE: PackedScene = preload("res://scenes/entities/welp.tscn")

@export var max_alive: int = 6
@export var spawn_radius: float = 3.0
@export var base_interval: float = 8.0  # seconds at full alarm; higher when factor lower

var _timer: float = 0.0
var _alive_count: int = 0

func _process(delta: float) -> void:
	var f: float = Escalation.time_alarm_factor()
	if f < 0.2:  # don't spawn alarm welps until 20% of full alarm
		_timer = 0.0
		return
	_timer += delta
	# scale interval inversely with factor: 8s at 0.2 (just starting) → 2s at 1.0
	var interval: float = base_interval / (0.5 + f * 3.0)
	if _timer >= interval and _alive_count < max_alive:
		_timer = 0.0
		_spawn()

func _spawn() -> void:
	var welp: CharacterBody3D = WELP_SCENE.instantiate()
	welp.color = "alarm"  # not a real color — drops nothing (welp.gd's _drop_souls handles unknown colors gracefully)
	var angle: float = randf() * TAU
	welp.global_position = global_position + Vector3(cos(angle) * spawn_radius, 1.0, sin(angle) * spawn_radius)
	welp.died.connect(_on_died)
	get_parent().add_child(welp)
	_alive_count += 1

func _on_died(_welp: Node, _color: String) -> void:
	_alive_count = max(0, _alive_count - 1)
```

For the alarm welp's "no drops" semantic: in welp.gd `_drop_souls`, add a check at the top:
```gdscript
func _drop_souls() -> void:
	if color == "alarm":
		return  # alarm welps drop nothing
	# ... rest unchanged
```

### Step 2: Add AlarmSpawner to upstairs.tscn

Append to upstairs.tscn:

```
[node name="AlarmSpawner" type="Node3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 4)
script = ExtResource("8_corner_spawner")  # ← actually use alarm_spawner ext_resource
```

(Need a separate ext_resource for `alarm_spawner.gd`. Add it to the ext_resource block.)

Position the AlarmSpawner ~4m forward from DescentStaircase (which is at z=0, so spawner at z=4 spawns slightly behind the staircase from player's approach).

### Step 3: Verify + commit

```bash
"/c/Users/wyenk/OneDrive/Documents/godot/Godot_v4.6.2-stable_win64.exe" --headless --path . --import 2>&1 | grep -i error | head -5
git add scripts/world/alarm_spawner.gd scripts/entities/welp.gd scenes/world/upstairs.tscn
git commit -m "feat(escalation): time-alarm spawns alarm welps near staircase late game"
```

---

## Task 9: Acceptance playtest (USER ACTION)

After all 8 implementation tasks, run the game and verify:

- [ ] Upstairs spawns into hex arena with 6 colored corners visible
- [ ] Each corner spawns only its color of dragons
- [ ] Walking into a corner ramps spawn rate (visible: more enemies)
- [ ] Walking out of a corner cools it (eventually heat=0)
- [ ] After ~30s in a hot corner, dragons appear
- [ ] After 60-90s in a hot corner, occasionally an elder dragon appears
- [ ] Killing a dragon drops 2-3 minor souls
- [ ] Killing an elder dragon drops 1 elder soul + 2-3 minors
- [ ] Picking up an elder soul triggers the replace prompt at cap (or unlocks new skill if under cap)
- [ ] All 6 cast types fire and damage enemies
- [ ] Sword tints correctly across all 6 colors
- [ ] After ~5 minutes upstairs, dark "alarm" welps spawn near staircase
- [ ] Descend → all heat resets, alarm timer resets
- [ ] No crashes during 30-min play session

### Step 1: User runs the game and confirms

(Manual.)

### Step 2: Tag

```bash
git tag -a v0.3-colors-corners -m "Phase 3: 6 colors with casts, hex arena 6 corners, per-corner heat, dragon/elder dragon tiers, time-alarm escalation."
```

---

## Phase 3 → Phase 4 handoff

What Phase 3 leaves for Phase 4:
- Active skill cap is still hardcoded 3 — Phase 4 ties it to pyre milestones (+1 per pyre at 100%).
- In-run elder-soul scaling (each elder taken bumps difficulty) — Phase 4.
- Pyre milestone effects (25% passive bonus, 50% hub feature, 75% bigger bonus, 100% boss-counter) — Phase 4.
- Hub features: Soul Altar, Cantrip Stones, Sigil Forge, Trial Chamber — Phase 4.
- Save/load — Phase 4.

Phase 3 should deliver the upstairs combat experience; Phase 4 builds the meta-progression spine.
