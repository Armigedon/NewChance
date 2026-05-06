# Spawn Cadence + Elder Abilities + Boss Cone Fixes Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** implement subsystems B and C from the May 2026 gameplay revisit per [the design spec](../specs/2026-05-05-spawn-cadence-elder-abilities-cone-fixes-design.md). Two phases, each landable independently.

**Architecture:** Phase A is foundational tuning — Escalation gets per-tier spawn floors, corner_spawner respects them, cones grow + clouds/wells degrade on use. Phase B adds six color-themed elder abilities via a small registry pattern (mirrors Phase 10's `ElderRegistry`). Both phases use TDD with GdUnit4.

**Tech Stack:** Godot 4.6, GDScript, GdUnit4 testing.

---

## File structure

**Phase A — Create:**
- `test/test_escalation_spawn_floor.gd`
- `test/test_corner_spawner_floor.gd`
- `test/test_cloud_burn_through.gd`
- `test/test_well_redirect_drain.gd`

**Phase A — Modify:**
- `scripts/world/escalation.gd` (tier floor tracking)
- `scripts/world/corner_spawner.gd` (respect floor)
- `scripts/entities/boss_mechanics/mechanic_static_breath.gd` (cone size constants)
- `scripts/entities/boss_mechanics/mechanic_sweeping_breath.gd` (cone size constants)
- `scripts/entities/boss_mechanic.gd` (`_segment_blocked_by_cloud` damages the cloud)
- `scripts/effects/effect_cloud.gd` (add `take_damage(amount)` + `hp` field)
- `scripts/effects/effect_gravity_well.gd` (add `consume_for_redirect()`)
- `scripts/entities/boss_dragon.gd` (`apply_pull_toward` accepts optional `source` Node, forwards to mechanics)
- `scripts/entities/boss_mechanics/mechanic_static_breath.gd` (`on_pull_during_windup` accepts source, calls `consume_for_redirect`)
- `scripts/entities/boss_mechanics/mechanic_sweeping_breath.gd` (same)
- `scenes/effects/effect_breath_cone.tscn` (cylinder height + mesh transform)

**Phase B — Create:**
- `scripts/entities/elder_abilities/elder_ability.gd` (base RefCounted)
- `scripts/entities/elder_abilities/elder_ability_registry.gd` (autoload)
- `scripts/entities/elder_abilities/elder_ability_red_fire_pool.gd`
- `scripts/entities/elder_abilities/elder_ability_blue_chill_aura.gd`
- `scripts/entities/elder_abilities/elder_ability_green_poison_trail.gd`
- `scripts/entities/elder_abilities/elder_ability_purple_pull_on_hit.gd`
- `scripts/entities/elder_abilities/elder_ability_gold_chain_on_hit.gd`
- `scripts/entities/elder_abilities/elder_ability_white_bone_wall.gd`
- `test/test_elder_abilities.gd`

**Phase B — Modify:**
- `scripts/entities/welp.gd` (alive-tick + attack + death hooks invoke registry-resolved ability)
- `project.godot` (register `ElderAbilityRegistry` autoload)

---

## Phase A — Spawn cadence + cone fixes + burn-through

### Task A1: Escalation tier-spawn floor tracking

**Files:**
- Modify: `scripts/world/escalation.gd`
- Test: `test/test_escalation_spawn_floor.gd` (new)

- [ ] **Step 1: Write the failing test**

Create `test/test_escalation_spawn_floor.gd`:

```gdscript
extends GdUnitTestSuite

func before_test() -> void:
	Escalation.reset()

func test_dragon_floor_blocks_second_dragon_within_window() -> void:
	assert_bool(Escalation.can_spawn_tier("dragon")).is_true()
	Escalation.record_tier_spawn("dragon")
	assert_bool(Escalation.can_spawn_tier("dragon")).is_false()

func test_elder_floor_blocks_second_elder_within_window() -> void:
	assert_bool(Escalation.can_spawn_tier("elder")).is_true()
	Escalation.record_tier_spawn("elder")
	assert_bool(Escalation.can_spawn_tier("elder")).is_false()

func test_dragon_floor_does_not_block_elder() -> void:
	Escalation.record_tier_spawn("dragon")
	assert_bool(Escalation.can_spawn_tier("elder")).is_true()

func test_elder_floor_does_not_block_dragon() -> void:
	Escalation.record_tier_spawn("elder")
	assert_bool(Escalation.can_spawn_tier("dragon")).is_true()

func test_welps_always_spawnable() -> void:
	Escalation.record_tier_spawn("dragon")
	Escalation.record_tier_spawn("elder")
	assert_bool(Escalation.can_spawn_tier("welp")).is_true()

func test_unknown_tier_always_spawnable() -> void:
	assert_bool(Escalation.can_spawn_tier("alarm")).is_true()

func test_reset_clears_floors() -> void:
	Escalation.record_tier_spawn("dragon")
	Escalation.record_tier_spawn("elder")
	Escalation.reset()
	assert_bool(Escalation.can_spawn_tier("dragon")).is_true()
	assert_bool(Escalation.can_spawn_tier("elder")).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_escalation_spawn_floor.gd --ignoreHeadlessMode
```
Expected: failures because `record_tier_spawn` and `can_spawn_tier` don't exist on Escalation.

- [ ] **Step 3: Add tier floor methods to `scripts/world/escalation.gd`**

Add at the top of the file, alongside existing constants:

```gdscript
const DRAGON_FLOOR_S: float = 20.0
const ELDER_FLOOR_S: float = 45.0
```

Add these fields next to the existing `_in_run_elders`:

```gdscript
var _last_dragon_spawn_msec: int = 0
var _last_elder_spawn_msec: int = 0
```

Add new methods, e.g., right after `roll_tier`:

```gdscript
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
	return true  # welps and unknown tiers always spawnable
```

Update `reset()` to clear the timestamps. Find:

```gdscript
func reset() -> void:
	_heat.clear()
	for color in COLORS:
		_heat[color] = 0.0
	_player_in_corner = ""
	_player_upstairs = false
	_upstairs_time = 0.0
	_in_run_elders = 0
```

Append two lines at the end:

```gdscript
	_last_dragon_spawn_msec = 0
	_last_elder_spawn_msec = 0
```

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: 7 PASSED.

- [ ] **Step 5: Run full suite to verify no regressions**

```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --continue --ignoreHeadlessMode 2>&1 | tail -3
```
Expected: 351+ tests passing (was 344 + 7 new).

- [ ] **Step 6: Commit**

```
git add scripts/world/escalation.gd test/test_escalation_spawn_floor.gd
git commit -m "feat(escalation): per-tier spawn floor tracking (dragon 20s, elder 45s)"
```

---

### Task A2: Corner spawner respects the tier floor

**Files:**
- Modify: `scripts/world/corner_spawner.gd:_spawn`
- Test: `test/test_corner_spawner_floor.gd` (new)

- [ ] **Step 1: Write the failing test**

Create `test/test_corner_spawner_floor.gd`:

```gdscript
extends GdUnitTestSuite

const SpawnerScene: PackedScene = preload("res://scenes/world/corner_spawner.tscn") if FileAccess.file_exists("res://scenes/world/corner_spawner.tscn") else null

# corner_spawner doesn't have its own .tscn — it's a Node3D added to the upstairs
# scene. We instantiate via script and add to the test tree to drive _spawn().

func before_test() -> void:
	Escalation.reset()
	for n in get_tree().get_nodes_in_group("enemy"):
		n.queue_free()
	await get_tree().process_frame

func test_spawn_records_tier_when_dragon_rolled() -> void:
	# Force a dragon roll by ensuring heat is high enough.
	Escalation._heat["red"] = 100.0  # max heat for red corner
	# Stub: directly call record_tier_spawn to simulate a successful spawn,
	# then verify the floor blocks the next attempt.
	Escalation.record_tier_spawn("dragon")
	assert_bool(Escalation.can_spawn_tier("dragon")).is_false()

func test_corner_spawner_downgrades_when_floor_active() -> void:
	# Set up: floor is active for dragon. The spawner's _spawn rolls dragon
	# but should downgrade to welp.
	var spawner = preload("res://scripts/world/corner_spawner.gd").new()
	spawner.color = "red"
	spawner.max_alive = 10
	add_child(spawner)
	spawner.global_position = Vector3.ZERO
	# Force heat high so roll_tier returns dragon-ish.
	Escalation._heat["red"] = 100.0
	# Mark dragon floor as recently used.
	Escalation.record_tier_spawn("dragon")
	# Drive _spawn 20 times. With dragon floor active, all spawns should be welps.
	# (heat 100 alone might still roll elder, so also block elder.)
	Escalation.record_tier_spawn("elder")
	var dragon_or_elder_count: int = 0
	for i in range(20):
		spawner._spawn()
	for n in get_tree().get_nodes_in_group("enemy"):
		if "tier" in n and (n.tier == "dragon" or n.tier == "elder"):
			dragon_or_elder_count += 1
	# All spawns should have downgraded to welp.
	assert_int(dragon_or_elder_count).is_equal(0)

func test_corner_spawner_records_tier_after_successful_spawn() -> void:
	var spawner = preload("res://scripts/world/corner_spawner.gd").new()
	spawner.color = "red"
	spawner.max_alive = 10
	add_child(spawner)
	spawner.global_position = Vector3.ZERO
	Escalation._heat["red"] = 100.0
	# At least one of 30 spawns should record a dragon or elder (since heat 100
	# rolls dragon ~35% / elder ~15%).
	for i in range(30):
		spawner._spawn()
	# After enough spawns, at least one of the tier timestamps should be non-zero.
	var any_recorded: bool = (
		Escalation._last_dragon_spawn_msec > 0
		or Escalation._last_elder_spawn_msec > 0
	)
	assert_bool(any_recorded).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_corner_spawner_floor.gd --ignoreHeadlessMode
```
Expected: `test_corner_spawner_downgrades_when_floor_active` fails (current `_spawn` doesn't check floor) and `test_corner_spawner_records_tier_after_successful_spawn` fails (current `_spawn` doesn't call record).

- [ ] **Step 3: Modify `scripts/world/corner_spawner.gd:_spawn`**

Find the existing function (lines 38-58):

```gdscript
func _spawn() -> void:
	var heat: float = Escalation.corner_heat(color)
	var player_pos: Vector3 = _get_player_pos()
	var tier: String = Escalation.roll_tier(heat)
	# Far corners only ever produce welps — no off-screen dragons/elders.
	if _is_far(player_pos):
		tier = "welp"
	var scene: PackedScene = _scene_for_tier(tier)
	if scene == null:
		return
	var enemy = scene.instantiate()
	if "max_hp" in enemy:
		enemy.max_hp = int(enemy.max_hp * Escalation.enemy_hp_factor())
	if tier in ["dragon", "elder"]:
		enemy.color = color
		_apply_color_tint(enemy, color)
	var spawn_pos: Vector3 = _pick_spawn_position()
	enemy.died.connect(_on_died)
	get_parent().add_child(enemy)
	enemy.global_position = spawn_pos
	_alive_count += 1
```

Replace with:

```gdscript
func _spawn() -> void:
	var heat: float = Escalation.corner_heat(color)
	var player_pos: Vector3 = _get_player_pos()
	var tier: String = Escalation.roll_tier(heat)
	# Far corners only ever produce welps — no off-screen dragons/elders.
	if _is_far(player_pos):
		tier = "welp"
	# Global tier floor: if a dragon or elder was recently spawned, downgrade
	# to welp so the floor is respected (subsystem B from May 2026 revisit).
	if not Escalation.can_spawn_tier(tier):
		tier = "welp"
	var scene: PackedScene = _scene_for_tier(tier)
	if scene == null:
		return
	var enemy = scene.instantiate()
	if "max_hp" in enemy:
		enemy.max_hp = int(enemy.max_hp * Escalation.enemy_hp_factor())
	if tier in ["dragon", "elder"]:
		enemy.color = color
		_apply_color_tint(enemy, color)
	var spawn_pos: Vector3 = _pick_spawn_position()
	enemy.died.connect(_on_died)
	get_parent().add_child(enemy)
	enemy.global_position = spawn_pos
	_alive_count += 1
	Escalation.record_tier_spawn(tier)
```

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: 3 PASSED.

- [ ] **Step 5: Run full suite to verify no regressions**

```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --continue --ignoreHeadlessMode 2>&1 | tail -3
```
Expected: 354+ tests passing.

- [ ] **Step 6: Commit**

```
git add scripts/world/corner_spawner.gd test/test_corner_spawner_floor.gd
git commit -m "feat(spawn): corner_spawner respects tier floor; downgrades to welp when active"
```

---

### Task A3: Cone size constants (static + sweeping breath)

**Files:**
- Modify: `scripts/entities/boss_mechanics/mechanic_static_breath.gd:4-5`
- Modify: `scripts/entities/boss_mechanics/mechanic_sweeping_breath.gd:4-5`
- Test: append to existing `test/test_mechanic_static_breath.gd` and `test/test_mechanic_sweeping_breath.gd`

- [ ] **Step 1: Write the failing test**

Append to `test/test_mechanic_static_breath.gd`:

```gdscript
func test_static_breath_cone_size_subsystem_c() -> void:
	# Subsystem C (May 2026 revisit): cone reach 12m, angle 100° so the
	# cone is gameplay-relevant and not just sidestep-able.
	var script = preload("res://scripts/entities/boss_mechanics/mechanic_static_breath.gd")
	assert_float(script.CONE_LENGTH).is_equal(12.0)
	assert_float(script.CONE_ANGLE_DEG).is_equal(100.0)
```

Append to `test/test_mechanic_sweeping_breath.gd`:

```gdscript
func test_sweeping_breath_cone_size_subsystem_c() -> void:
	# Subsystem C (May 2026 revisit): same cone size as static breath.
	var script = preload("res://scripts/entities/boss_mechanics/mechanic_sweeping_breath.gd")
	assert_float(script.CONE_LENGTH).is_equal(12.0)
	assert_float(script.CONE_ANGLE_DEG).is_equal(100.0)
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_mechanic_static_breath.gd -a res://test/test_mechanic_sweeping_breath.gd --ignoreHeadlessMode 2>&1 | tail -10
```
Expected: 2 FAILED (current values are 7.0 and 75.0).

- [ ] **Step 3: Update `scripts/entities/boss_mechanics/mechanic_static_breath.gd`**

Find:
```gdscript
const CONE_LENGTH: float = 7.0
const CONE_ANGLE_DEG: float = 75.0
```

Replace with:
```gdscript
const CONE_LENGTH: float = 12.0  # was 7.0; subsystem C bump
const CONE_ANGLE_DEG: float = 100.0  # was 75.0; subsystem C bump
```

Same change in `scripts/entities/boss_mechanics/mechanic_sweeping_breath.gd`.

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: 2 PASSED.

- [ ] **Step 5: Run full suite to verify no regressions**

Note: existing breath tests may have hardcoded the old size somewhere. If failures appear in `test_breath_*` files, find the hardcoded values and update them to match the new constants. Do NOT change tests that intentionally test edge-case geometry (e.g., a player exactly at 7m gets hit) — those tests are still valid with the new geometry.

```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --continue --ignoreHeadlessMode 2>&1 | tail -3
```
Expected: all tests passing. If a test fails, read its assertions: if it asserted on the cone hitting/missing a specific distance, update the distance to be inside/outside the new 12m reach.

- [ ] **Step 6: Commit**

```
git add scripts/entities/boss_mechanics/mechanic_static_breath.gd scripts/entities/boss_mechanics/mechanic_sweeping_breath.gd test/test_mechanic_static_breath.gd test/test_mechanic_sweeping_breath.gd
git commit -m "feat(boss): cone size 7m/75° -> 12m/100° (subsystem C)"
```

---

### Task A4: Cone visual mesh updated for new size

**Files:**
- Modify: `scenes/effects/effect_breath_cone.tscn`

- [ ] **Step 1: Read the current .tscn**

Open `scenes/effects/effect_breath_cone.tscn`. The current mesh is:
```
[sub_resource type="CylinderMesh" id="mesh_cone"]
top_radius = 2.5
bottom_radius = 0.1
height = 5.0
material = SubResource("mat_cone")
```

And the mesh transform:
```
[node name="Mesh" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 0, -1, 0, 1, 0, 0, 0, -2.5)
mesh = SubResource("mesh_cone")
```

The translation `-2.5` is half the cylinder height, pushing the mesh entirely behind the parent origin (so the narrow apex sits at the parent origin and the wide end extends away).

- [ ] **Step 2: Update cylinder height to match new cone length**

In the `[sub_resource type="CylinderMesh" id="mesh_cone"]` block, change `height = 5.0` to `height = 12.0`. Also widen the visual: change `top_radius = 2.5` to `top_radius = 5.0` so the wide end at 12m matches the new 100° angle (visually).

Keep `bottom_radius = 0.1` so the apex is a near-point at the boss origin.

- [ ] **Step 3: Update the mesh transform translation to half of new height**

Change:
```
transform = Transform3D(1, 0, 0, 0, 0, -1, 0, 1, 0, 0, 0, -2.5)
```

To:
```
transform = Transform3D(1, 0, 0, 0, 0, -1, 0, 1, 0, 0, 0, -6.0)
```

(Half of new height 12.0 = 6.0.)

- [ ] **Step 4: Run full suite to verify no test regressions**

```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --continue --ignoreHeadlessMode 2>&1 | tail -3
```

The mesh change is visual-only; tests don't read mesh geometry. Should pass without changes.

- [ ] **Step 5: Commit**

```
git add scenes/effects/effect_breath_cone.tscn
git commit -m "feat(boss): breath cone mesh height 5->12 + wide-end radius 2.5->5 (apex stays at boss)"
```

- [ ] **Step 6: Note for playtester**

This task includes a visual change. The implementer should open the editor and verify the cone mesh visually appears with the apex at the boss origin (narrow end touching the boss) and the wide end extending in the direction of the cone's facing. If the user's "centered on boss" perception persists, the fallback fix is to set `bottom_radius = 0.0` for a true point apex.

---

### Task A5: Cloud burn-through on boss breath block

**Files:**
- Modify: `scripts/effects/effect_cloud.gd` (add `take_damage` + `hp` field)
- Modify: `scripts/entities/boss_mechanic.gd:_segment_blocked_by_cloud` (damage cloud on block)
- Test: `test/test_cloud_burn_through.gd` (new)

- [ ] **Step 1: Write the failing test**

Create `test/test_cloud_burn_through.gd`:

```gdscript
extends GdUnitTestSuite

const CloudScene: PackedScene = preload("res://scenes/effects/effect_cloud.tscn")
const StaticBreathScript = preload("res://scripts/entities/boss_mechanics/mechanic_static_breath.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

func before_test() -> void:
	for c in get_tree().get_nodes_in_group("damage_cloud"):
		c.queue_free()
	await get_tree().process_frame

func test_cloud_has_hp_field_default_30() -> void:
	var cloud: Node3D = auto_free(CloudScene.instantiate())
	add_child(cloud)
	await get_tree().process_frame
	assert_int(cloud.hp).is_equal(30)

func test_cloud_take_damage_decrements_hp() -> void:
	var cloud: Node3D = auto_free(CloudScene.instantiate())
	add_child(cloud)
	await get_tree().process_frame
	cloud.take_damage(7)
	assert_int(cloud.hp).is_equal(23)

func test_cloud_freed_on_zero_hp() -> void:
	var cloud: Node3D = auto_free(CloudScene.instantiate())
	add_child(cloud)
	await get_tree().process_frame
	cloud.take_damage(30)
	await get_tree().process_frame
	assert_bool(is_instance_valid(cloud)).is_false()

func test_breath_block_damages_cloud() -> void:
	# Set up: boss + player on opposite sides of a green cloud. Drive a breath
	# tick and verify the cloud HP drops by CLOUD_BREATH_BLOCK_DAMAGE (5).
	var boss: CharacterBody3D = auto_free(BossScene.instantiate())
	var player: CharacterBody3D = auto_free(PlayerScene.instantiate())
	var cloud: Node3D = auto_free(CloudScene.instantiate())
	add_child(boss)
	boss.global_position = Vector3.ZERO
	add_child(player)
	player.global_position = Vector3(0, 0, 4)
	add_child(cloud)
	cloud.global_position = Vector3(0, 0, 2)
	cloud.configure(10.0, 2.0, 6, [], "green")
	await get_tree().process_frame
	for m in boss._mechanics.duplicate():
		m.queue_free()
	boss._mechanics.clear()
	var breath = StaticBreathScript.new()
	boss._register_mechanic(breath)
	breath._cooldown_remaining = 99.0
	await get_tree().process_frame
	cloud.global_position = Vector3(0, 0, 2)
	var initial_hp: int = cloud.hp
	breath.trigger(1)
	# Advance through windup; one tick of execution should block via cloud and damage it.
	var ticked: float = 0.0
	while ticked < 1.05:
		breath.tick(1.0 / 60.0, 1)
		ticked += 1.0 / 60.0
	for i in range(15):  # advance 15 frames of execution
		await get_tree().physics_frame
	# Expect cloud HP to have decreased.
	if is_instance_valid(cloud):
		assert_int(cloud.hp).is_less(initial_hp)
	else:
		# Cloud burned through to zero — also valid.
		assert_int(0).is_equal(0)
```

- [ ] **Step 2: Run test to verify it fails**

```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_cloud_burn_through.gd --ignoreHeadlessMode 2>&1 | tail -10
```
Expected: failures because `take_damage` and `hp` don't exist on cloud.

- [ ] **Step 3: Add `hp` + `take_damage` to `scripts/effects/effect_cloud.gd`**

Open `scripts/effects/effect_cloud.gd`. Find the existing fields. Add a constant and field at the top of the class:

```gdscript
const NATIVE_HP: int = 30
var hp: int = NATIVE_HP
```

Add the method (anywhere in the class body, e.g., after `_process`):

```gdscript
func take_damage(amount: int) -> void:
	# Subsystem C (May 2026 revisit): boss breath burns through clouds.
	# Each blocked breath tick deals damage; cloud frees on zero.
	hp = max(0, hp - amount)
	if hp == 0:
		queue_free()
```

- [ ] **Step 4: Modify `scripts/entities/boss_mechanic.gd:_segment_blocked_by_cloud`**

Open `scripts/entities/boss_mechanic.gd`. Find `_segment_blocked_by_cloud`. It currently looks like:

```gdscript
func _segment_blocked_by_cloud(from: Vector3, to: Vector3) -> bool:
	var clouds: Array = get_tree().get_nodes_in_group("damage_cloud")
	for c in clouds:
		if not is_instance_valid(c):
			continue
		# Spec §4: only green clouds block breath; other colors pass through.
		if c.get("base_color") != "green":
			continue
		if c.has_method("blocks_segment") and c.blocks_segment(from, to):
			return true
	return false
```

Replace with:

```gdscript
const CLOUD_BREATH_BLOCK_DAMAGE: int = 5

func _segment_blocked_by_cloud(from: Vector3, to: Vector3) -> bool:
	var clouds: Array = get_tree().get_nodes_in_group("damage_cloud")
	for c in clouds:
		if not is_instance_valid(c):
			continue
		# Spec §4: only green clouds block breath; other colors pass through.
		if c.get("base_color") != "green":
			continue
		if c.has_method("blocks_segment") and c.blocks_segment(from, to):
			# Burn-through: cloud takes damage on each blocked tick, eventually
			# clearing so stacking clouds doesn't fully cheese boss breath.
			if c.has_method("take_damage"):
				c.take_damage(CLOUD_BREATH_BLOCK_DAMAGE)
			return true
	return false
```

- [ ] **Step 5: Run tests to verify pass**

Same command as Step 2. Expected: 4 PASSED.

- [ ] **Step 6: Run full suite to verify no regressions**

```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --continue --ignoreHeadlessMode 2>&1 | tail -3
```
Expected: all tests passing.

- [ ] **Step 7: Commit**

```
git add scripts/effects/effect_cloud.gd scripts/entities/boss_mechanic.gd test/test_cloud_burn_through.gd
git commit -m "feat(boss): cloud burn-through (5 dmg per blocked breath tick; 30 HP cloud)"
```

---

### Task A6: Well drain on cone redirect

**Files:**
- Modify: `scripts/effects/effect_gravity_well.gd` (add `consume_for_redirect`)
- Modify: `scripts/entities/boss_dragon.gd:apply_pull_toward` (accepts optional `source` param, forwards to mechanics)
- Modify: `scripts/entities/boss_mechanics/mechanic_static_breath.gd:on_pull_during_windup` (accepts source, calls `consume_for_redirect`)
- Modify: `scripts/entities/boss_mechanics/mechanic_sweeping_breath.gd:on_pull_during_windup` (same)
- Test: `test/test_well_redirect_drain.gd` (new)

- [ ] **Step 1: Write the failing test**

Create `test/test_well_redirect_drain.gd`:

```gdscript
extends GdUnitTestSuite

const WellScene: PackedScene = preload("res://scenes/effects/effect_gravity_well.tscn")

func before_test() -> void:
	for n in get_tree().get_nodes_in_group("damage_cloud"):
		n.queue_free()
	await get_tree().process_frame

func test_well_consume_for_redirect_drains_lifetime() -> void:
	var well: Node3D = auto_free(WellScene.instantiate())
	add_child(well)
	await get_tree().process_frame
	well.configure(2.0, 2.0, 5, [], "purple")
	var initial_age: float = well._age
	well.consume_for_redirect()
	# Age should advance by REDIRECT_LIFETIME_DRAIN_S (0.5s).
	assert_float(well._age).is_equal_approx(initial_age + 0.5, 0.001)

func test_well_freed_when_remaining_drops_below_drain() -> void:
	var well: Node3D = auto_free(WellScene.instantiate())
	add_child(well)
	await get_tree().process_frame
	well.configure(2.0, 2.0, 5, [], "purple")
	# Manually advance age so only 0.4s remains; consume should free.
	well._age = 1.6
	well.consume_for_redirect()
	await get_tree().process_frame
	assert_bool(is_instance_valid(well)).is_false()
```

- [ ] **Step 2: Run test to verify it fails**

```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_well_redirect_drain.gd --ignoreHeadlessMode 2>&1 | tail -10
```
Expected: failures because `consume_for_redirect` doesn't exist.

- [ ] **Step 3: Add `consume_for_redirect` to `scripts/effects/effect_gravity_well.gd`**

Open the file. Add a constant near the top:

```gdscript
const REDIRECT_LIFETIME_DRAIN_S: float = 0.5
```

Add the method:

```gdscript
func consume_for_redirect() -> void:
	# Subsystem C (May 2026 revisit): each cone redirect drains lifetime so
	# stacking wells doesn't grant infinite redirects.
	var remaining_age: float = lifetime - _age
	if remaining_age <= REDIRECT_LIFETIME_DRAIN_S:
		queue_free()
		return
	_age += REDIRECT_LIFETIME_DRAIN_S
```

- [ ] **Step 4: Update `apply_pull_toward` to accept and forward `source`**

In `scripts/entities/boss_dragon.gd`, find the existing function:

```gdscript
func apply_pull_toward(target_pos: Vector3, impulse: float) -> void:
	var dir: Vector3 = target_pos - global_position
	dir.y = 0.0
	if dir.length() < 0.001:
		return
	# Forward to any breath mechanic in windup for cone redirect, and to charge
	# for trajectory deflection. Mechanics self-filter via is_in_windup() /
	# is_in_execution(); mutual exclusivity ensures at most one breath-style
	# mechanic is in windup at a time.
	for m in _mechanics:
		if m.has_method("on_pull_during_windup"):
			m.on_pull_during_windup(target_pos, CONE_REDIRECT_PER_PULL_DEG)
		if m.has_method("on_pull_during_charge"):
			m.on_pull_during_charge(target_pos, impulse)
	# Boss is CC immune ...
```

Replace with:

```gdscript
func apply_pull_toward(target_pos: Vector3, impulse: float, source: Node = null) -> void:
	var dir: Vector3 = target_pos - global_position
	dir.y = 0.0
	if dir.length() < 0.001:
		return
	# Forward to any breath mechanic in windup for cone redirect, and to charge
	# for trajectory deflection. The optional `source` is the gravity well that
	# triggered this pull — breath mechanics call source.consume_for_redirect()
	# after applying the redirect (subsystem C burn-through for wells).
	for m in _mechanics:
		if m.has_method("on_pull_during_windup"):
			m.on_pull_during_windup(target_pos, CONE_REDIRECT_PER_PULL_DEG, source)
		if m.has_method("on_pull_during_charge"):
			m.on_pull_during_charge(target_pos, impulse)
	# Boss is CC immune ...
```

(Keep the rest of the function body identical.)

- [ ] **Step 5: Update `effect_gravity_well.gd:_physics_process` to pass self as source**

Find the line that calls `apply_pull_toward`:

```gdscript
		if body.has_method("apply_pull_toward"):
			body.apply_pull_toward(global_position, PULL_FORCE_PER_FRAME)
```

Replace with:

```gdscript
		if body.has_method("apply_pull_toward"):
			body.apply_pull_toward(global_position, PULL_FORCE_PER_FRAME, self)
```

- [ ] **Step 6: Update breath mechanics' `on_pull_during_windup` to accept and consume source**

In `scripts/entities/boss_mechanics/mechanic_static_breath.gd`, find:

```gdscript
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
	if absf(cross_z) < 0.001:
		return
	set_aim(_aim_dir.rotated(Vector3.UP, deg_to_rad(rotation_deg) * signf(cross_z)))
```

Replace with:

```gdscript
func on_pull_during_windup(pull_origin: Vector3, rotation_deg: float, source: Node = null) -> void:
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
	if absf(cross_z) < 0.001:
		return
	set_aim(_aim_dir.rotated(Vector3.UP, deg_to_rad(rotation_deg) * signf(cross_z)))
	# Subsystem C burn-through: drain the well that triggered the redirect.
	if source != null and is_instance_valid(source) and source.has_method("consume_for_redirect"):
		source.consume_for_redirect()
```

Same change in `scripts/entities/boss_mechanics/mechanic_sweeping_breath.gd:on_pull_during_windup` — add the `source: Node = null` parameter and the trailing `consume_for_redirect` call. Find the existing function and apply the same pattern.

- [ ] **Step 7: Run tests to verify pass**

Same command as Step 2. Expected: 2 PASSED.

- [ ] **Step 8: Run full suite to verify no regressions**

```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --continue --ignoreHeadlessMode 2>&1 | tail -3
```
Expected: all tests passing. Tests like `test_breath_pull_redirect.gd` exercise `apply_pull_toward` — they should still work because the `source` parameter is optional with default `null`.

- [ ] **Step 9: Commit**

```
git add scripts/effects/effect_gravity_well.gd scripts/entities/boss_dragon.gd scripts/entities/boss_mechanics/mechanic_static_breath.gd scripts/entities/boss_mechanics/mechanic_sweeping_breath.gd test/test_well_redirect_drain.gd
git commit -m "feat(boss): well burn-through (0.5s lifetime drain per cone redirect)"
```

---

## Phase B — Elder color abilities

### Task B1: ElderAbility base + ElderAbilityRegistry autoload

**Files:**
- Create: `scripts/entities/elder_abilities/elder_ability.gd`
- Create: `scripts/entities/elder_abilities/elder_ability_registry.gd`
- Modify: `project.godot` (register autoload)
- Test: `test/test_elder_abilities.gd` (new — registry-only assertions for now)

- [ ] **Step 1: Create the base class**

Create `scripts/entities/elder_abilities/elder_ability.gd`:

```gdscript
extends RefCounted
class_name ElderAbility

# Base class for color-themed elder enemy abilities. Subclasses fill in any
# of the three optional Callable hooks. Each instance is one ability for
# one color; the registry maps color -> ElderAbility instance.
#
# Hooks (all optional):
# on_alive_tick(elder: Node, delta: float) -> void
#   Called from welp._physics_process each frame while elder is alive.
# on_attack(elder: Node, target: Node) -> void
#   Called from welp._attack_player after the player hit lands.
# on_death(elder: Node) -> void
#   Called from welp.take_damage just before queue_free.

var color: String

var on_alive_tick: Callable = Callable()
var on_attack: Callable = Callable()
var on_death: Callable = Callable()

func _init(p_color: String) -> void:
	color = p_color
```

- [ ] **Step 2: Create the registry autoload**

Create `scripts/entities/elder_abilities/elder_ability_registry.gd`:

```gdscript
extends Node
# Autoload — maps color -> ElderAbility instance. Loaded once at boot.
# Welp queries this on _ready when tier == "elder" to find the appropriate
# color-themed ability.

const ElderAbilityScript = preload("res://scripts/entities/elder_abilities/elder_ability.gd")

var _by_color: Dictionary = {}  # color -> ElderAbility

func _ready() -> void:
	_register_all()

func _register_all() -> void:
	# Subclasses are registered in Task B2; for now, the registry is empty.
	# Welp.gd queries get_for_color(); empty result means "no ability" and the
	# elder behaves as a stat-buffed welp (the pre-Phase-B behavior).
	pass

func _register(ability: ElderAbility) -> void:
	_by_color[ability.color] = ability

func get_for_color(color: String) -> ElderAbility:
	return _by_color.get(color, null)
```

- [ ] **Step 3: Register autoload in `project.godot`**

Open `project.godot`. Find the `[autoload]` section. Append (after `ElderRegistry`):

```
ElderAbilityRegistry="*res://scripts/entities/elder_abilities/elder_ability_registry.gd"
```

- [ ] **Step 4: Write the registry test**

Create `test/test_elder_abilities.gd`:

```gdscript
extends GdUnitTestSuite

func test_registry_returns_null_for_unknown_color() -> void:
	# Pre-Phase-B-2: registry is empty. All colors return null.
	assert_object(ElderAbilityRegistry.get_for_color("xyzzy")).is_null()

func test_elder_ability_instances_construct_with_color() -> void:
	var ability := ElderAbility.new("red")
	assert_str(ability.color).is_equal("red")
	# Hooks default unset.
	assert_bool(ability.on_alive_tick.is_null()).is_true()
	assert_bool(ability.on_attack.is_null()).is_true()
	assert_bool(ability.on_death.is_null()).is_true()
```

- [ ] **Step 5: Run tests to verify pass**

```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_elder_abilities.gd --ignoreHeadlessMode 2>&1 | tail -10
```
Expected: 2 PASSED.

- [ ] **Step 6: Commit**

```
git add scripts/entities/elder_abilities/ test/test_elder_abilities.gd project.godot
git commit -m "feat(elder): ElderAbility base class + registry autoload (Task B1)"
```

---

### Task B2: Six color-themed elder abilities

**Files:**
- Create: `scripts/entities/elder_abilities/elder_ability_red_fire_pool.gd`
- Create: `scripts/entities/elder_abilities/elder_ability_blue_chill_aura.gd`
- Create: `scripts/entities/elder_abilities/elder_ability_green_poison_trail.gd`
- Create: `scripts/entities/elder_abilities/elder_ability_purple_pull_on_hit.gd`
- Create: `scripts/entities/elder_abilities/elder_ability_gold_chain_on_hit.gd`
- Create: `scripts/entities/elder_abilities/elder_ability_white_bone_wall.gd`
- Modify: `scripts/entities/elder_abilities/elder_ability_registry.gd:_register_all` (register all six)

- [ ] **Step 1: Create Red — Fire Pool on Death**

Create `scripts/entities/elder_abilities/elder_ability_red_fire_pool.gd`:

```gdscript
extends ElderAbility
class_name ElderAbilityRedFirePool

const CloudScene: PackedScene = preload("res://scenes/effects/effect_cloud.tscn")
const POOL_RADIUS: float = 2.5
const POOL_LIFETIME: float = 3.0
const POOL_TICK_DAMAGE: int = 5

func _init() -> void:
	super._init("red")
	on_death = func(elder: Node) -> void:
		if not is_instance_valid(elder):
			return
		var pool: Node3D = CloudScene.instantiate()
		var parent: Node = elder.get_parent()
		if parent == null:
			return
		parent.add_child(pool)
		pool.global_position = elder.global_position
		pool.configure(POOL_LIFETIME, POOL_RADIUS, POOL_TICK_DAMAGE, [], "red")
```

- [ ] **Step 2: Create Blue — Chill Aura**

Create `scripts/entities/elder_abilities/elder_ability_blue_chill_aura.gd`:

```gdscript
extends ElderAbility
class_name ElderAbilityBlueChillAura

const AURA_RADIUS: float = 3.0
const AURA_TICK_INTERVAL: float = 1.0

func _init() -> void:
	super._init("blue")
	# State per elder is held in node meta — multiple blue elders can each track
	# their own aura tick independently.
	on_alive_tick = func(elder: Node, delta: float) -> void:
		if not is_instance_valid(elder):
			return
		var timer: float = float(elder.get_meta("blue_aura_timer", 0.0))
		timer += delta
		if timer < AURA_TICK_INTERVAL:
			elder.set_meta("blue_aura_timer", timer)
			return
		elder.set_meta("blue_aura_timer", 0.0)
		var players: Array = elder.get_tree().get_nodes_in_group("player")
		for p in players:
			if not is_instance_valid(p):
				continue
			var d: float = p.global_position.distance_to(elder.global_position)
			if d <= AURA_RADIUS and p.has_method("apply_chill"):
				p.apply_chill(1)
```

- [ ] **Step 3: Create Green — Poison Trail**

Create `scripts/entities/elder_abilities/elder_ability_green_poison_trail.gd`:

```gdscript
extends ElderAbility
class_name ElderAbilityGreenPoisonTrail

const CloudScene: PackedScene = preload("res://scenes/effects/effect_cloud.tscn")
const TRAIL_DROP_DISTANCE: float = 1.0
const TRAIL_LIFETIME: float = 2.0
const TRAIL_RADIUS: float = 1.5
const TRAIL_TICK_DAMAGE: int = 3

func _init() -> void:
	super._init("green")
	on_alive_tick = func(elder: Node, _delta: float) -> void:
		if not is_instance_valid(elder):
			return
		var last_pos: Vector3 = elder.get_meta("green_trail_last_pos", elder.global_position)
		var dist: float = elder.global_position.distance_to(last_pos)
		if dist < TRAIL_DROP_DISTANCE:
			return
		elder.set_meta("green_trail_last_pos", elder.global_position)
		var cloud: Node3D = CloudScene.instantiate()
		var parent: Node = elder.get_parent()
		if parent == null:
			return
		parent.add_child(cloud)
		cloud.global_position = elder.global_position
		cloud.configure(TRAIL_LIFETIME, TRAIL_RADIUS, TRAIL_TICK_DAMAGE, [], "green")
```

- [ ] **Step 4: Create Purple — Pull on Hit**

Create `scripts/entities/elder_abilities/elder_ability_purple_pull_on_hit.gd`:

```gdscript
extends ElderAbility
class_name ElderAbilityPurplePullOnHit

const PULL_IMPULSE: float = 1.0
const PULL_COOLDOWN_S: float = 1.5

func _init() -> void:
	super._init("purple")
	on_attack = func(elder: Node, target: Node) -> void:
		if not is_instance_valid(elder) or not is_instance_valid(target):
			return
		# Per-elder pull cooldown so successive pulls don't lock the player.
		var now_msec: int = Time.get_ticks_msec()
		var last_msec: int = int(elder.get_meta("purple_last_pull_msec", -10000))
		if now_msec - last_msec < int(PULL_COOLDOWN_S * 1000.0):
			return
		elder.set_meta("purple_last_pull_msec", now_msec)
		if target.has_method("apply_pull_toward"):
			target.apply_pull_toward(elder.global_position, PULL_IMPULSE)
```

- [ ] **Step 5: Create Gold — Chain on Hit**

Create `scripts/entities/elder_abilities/elder_ability_gold_chain_on_hit.gd`:

```gdscript
extends ElderAbility
class_name ElderAbilityGoldChainOnHit

const CHAIN_RANGE: float = 4.0
const CHAIN_DAMAGE_FRAC: float = 0.5

func _init() -> void:
	super._init("gold")
	on_attack = func(elder: Node, _target: Node) -> void:
		if not is_instance_valid(elder):
			return
		var nearest: Node = null
		var best_dist: float = CHAIN_RANGE
		for e in elder.get_tree().get_nodes_in_group("enemy"):
			if e == elder:
				continue
			if not is_instance_valid(e):
				continue
			if "_is_dead" in e and bool(e.get("_is_dead")):
				continue
			var d: float = e.global_position.distance_to(elder.global_position)
			if d < best_dist:
				nearest = e
				best_dist = d
		if nearest == null or not nearest.has_method("take_damage"):
			return
		var dmg: int = int(float(elder.attack_damage) * CHAIN_DAMAGE_FRAC) if "attack_damage" in elder else 5
		nearest.take_damage(max(1, dmg))
```

- [ ] **Step 6: Create White — Bone Wall Near PC on Death**

Create `scripts/entities/elder_abilities/elder_ability_white_bone_wall.gd`:

```gdscript
extends ElderAbility
class_name ElderAbilityWhiteBoneWall

const BoneWallScene: PackedScene = preload("res://scenes/effects/effect_bone_wall.tscn")
const WALL_OFFSET_M: float = 2.5
const WALL_LIFETIME: float = 3.0
const WALL_LENGTH: float = 4.0
const WALL_HP: int = 30

func _init() -> void:
	super._init("white")
	on_death = func(elder: Node) -> void:
		if not is_instance_valid(elder):
			return
		var players: Array = elder.get_tree().get_nodes_in_group("player")
		if players.is_empty():
			return
		var player: Node = players[0]
		if not is_instance_valid(player):
			return
		# Offset 2.5m from the player along a random angle within ±45° of the
		# player→elder vector, so the wall blocks an evasive line near the player.
		var to_elder: Vector3 = elder.global_position - player.global_position
		to_elder.y = 0.0
		if to_elder.length() < 0.01:
			to_elder = Vector3.FORWARD
		to_elder = to_elder.normalized()
		var jitter: float = randf_range(-PI / 4.0, PI / 4.0)
		var dir: Vector3 = to_elder.rotated(Vector3.UP, jitter)
		var wall_pos: Vector3 = player.global_position + dir * WALL_OFFSET_M
		var wall: StaticBody3D = BoneWallScene.instantiate()
		var parent: Node = elder.get_parent()
		if parent == null:
			return
		parent.add_child(wall)
		wall.global_position = Vector3(wall_pos.x, 0.5, wall_pos.z)
		# Orient wall perpendicular to the dir vector so it blocks the line.
		wall.look_at(wall.global_position + Vector3(dir.z, 0, -dir.x), Vector3.UP)
		if wall.has_method("configure"):
			wall.configure(WALL_HP, WALL_LIFETIME, WALL_LENGTH)
```

- [ ] **Step 7: Update registry to register all six**

Replace `scripts/entities/elder_abilities/elder_ability_registry.gd:_register_all`:

```gdscript
func _register_all() -> void:
	_register(ElderAbilityRedFirePool.new())
	_register(ElderAbilityBlueChillAura.new())
	_register(ElderAbilityGreenPoisonTrail.new())
	_register(ElderAbilityPurplePullOnHit.new())
	_register(ElderAbilityGoldChainOnHit.new())
	_register(ElderAbilityWhiteBoneWall.new())
```

- [ ] **Step 8: Update tests**

Append to `test/test_elder_abilities.gd`:

```gdscript
func test_registry_returns_red_fire_pool() -> void:
	var ability: ElderAbility = ElderAbilityRegistry.get_for_color("red")
	assert_object(ability).is_not_null()
	assert_str(ability.color).is_equal("red")
	assert_bool(ability.on_death.is_null()).is_false()

func test_registry_returns_blue_chill_aura() -> void:
	var ability: ElderAbility = ElderAbilityRegistry.get_for_color("blue")
	assert_object(ability).is_not_null()
	assert_bool(ability.on_alive_tick.is_null()).is_false()

func test_registry_returns_green_poison_trail() -> void:
	var ability: ElderAbility = ElderAbilityRegistry.get_for_color("green")
	assert_object(ability).is_not_null()
	assert_bool(ability.on_alive_tick.is_null()).is_false()

func test_registry_returns_purple_pull_on_hit() -> void:
	var ability: ElderAbility = ElderAbilityRegistry.get_for_color("purple")
	assert_object(ability).is_not_null()
	assert_bool(ability.on_attack.is_null()).is_false()

func test_registry_returns_gold_chain_on_hit() -> void:
	var ability: ElderAbility = ElderAbilityRegistry.get_for_color("gold")
	assert_object(ability).is_not_null()
	assert_bool(ability.on_attack.is_null()).is_false()

func test_registry_returns_white_bone_wall() -> void:
	var ability: ElderAbility = ElderAbilityRegistry.get_for_color("white")
	assert_object(ability).is_not_null()
	assert_bool(ability.on_death.is_null()).is_false()
```

Also remove or update the earlier `test_registry_returns_null_for_unknown_color` test — it should still pass since "xyzzy" is unknown.

- [ ] **Step 9: Run tests to verify pass**

```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_elder_abilities.gd --ignoreHeadlessMode 2>&1 | tail -10
```
Expected: 7+ PASSED.

- [ ] **Step 10: Commit**

```
git add scripts/entities/elder_abilities/ test/test_elder_abilities.gd
git commit -m "feat(elder): six color-themed elder abilities (Task B2)"
```

---

### Task B3: Welp integration (alive-tick + on-attack + on-death hooks)

**Files:**
- Modify: `scripts/entities/welp.gd` (resolve ability on _ready; fire hooks at right moments)
- Test: `test/test_elder_abilities.gd` (append behavioral tests)

- [ ] **Step 1: Add ability resolution + hook firing to welp.gd**

Open `scripts/entities/welp.gd`. Add a member variable near the top (alongside other state):

```gdscript
var _elder_ability: ElderAbility = null
```

In `_ready()`, after `add_to_group("enemy")`, add:

```gdscript
	if tier == "elder":
		_elder_ability = ElderAbilityRegistry.get_for_color(color)
```

In `_physics_process(delta: float)`, just before `move_and_slide()` (the last line), add the alive-tick hook fire:

```gdscript
	# Phase B: fire elder ability alive-tick hook (no-op if no ability or hook unset).
	if _elder_ability != null and not _elder_ability.on_alive_tick.is_null() and not _is_dead:
		_elder_ability.on_alive_tick.call(self, delta)
```

In `_attack_player()` after the existing `take_damage` call (around line 104), add the on-attack hook:

```gdscript
	# Phase B: fire elder ability on-attack hook.
	if _elder_ability != null and not _elder_ability.on_attack.is_null():
		_elder_ability.on_attack.call(self, _player)
```

In `take_damage(amount: int)`, find the `if hp == 0:` block. Just before `queue_free()`, add the on-death hook:

```gdscript
	if hp == 0:
		_is_dead = true
		_drop_souls()
		RunStats.record_kill()
		HitStop.freeze(_hit_stop_duration())
		var burst_color: Color = Vfx.COLOR_ALBEDO.get(color, Color(0.5, 0.5, 0.5, 1))
		Vfx.spawn_death_burst(global_position + Vector3(0, 0.5, 0), burst_color, get_parent())
		# Phase B: fire elder ability on-death hook before freeing the node.
		if _elder_ability != null and not _elder_ability.on_death.is_null():
			_elder_ability.on_death.call(self)
		died.emit(self, color)
		queue_free()
```

- [ ] **Step 2: Add behavioral tests**

Append to `test/test_elder_abilities.gd`:

```gdscript
const WelpScene: PackedScene = preload("res://scenes/entities/welp.tscn")

func _spawn_elder(color: String, position: Vector3 = Vector3.ZERO) -> CharacterBody3D:
	var w: CharacterBody3D = auto_free(WelpScene.instantiate())
	w.tier = "elder"
	w.color = color
	add_child(w)
	w.global_position = position
	return w

func test_red_elder_drops_fire_pool_on_death() -> void:
	for c in get_tree().get_nodes_in_group("damage_cloud"):
		c.queue_free()
	await get_tree().process_frame
	var elder := _spawn_elder("red")
	await get_tree().process_frame
	elder.take_damage(elder.max_hp + 100)
	await get_tree().process_frame
	var found_red_pool: bool = false
	for c in get_tree().get_nodes_in_group("damage_cloud"):
		if c.get("base_color") == "red":
			found_red_pool = true
			break
	assert_bool(found_red_pool).is_true()

func test_blue_elder_chill_aura_applies_chill_to_player() -> void:
	var elder := _spawn_elder("blue")
	var player: CharacterBody3D = auto_free(load("res://scenes/entities/player.tscn").instantiate())
	add_child(player)
	player.global_position = Vector3(2, 0, 0)  # within 3m
	await get_tree().process_frame
	# Drive enough alive-ticks to fire one aura tick (~1.0s).
	for i in range(70):
		await get_tree().physics_frame
	# Player should have at least 1 chill stack.
	assert_int(player._chill_stacks).is_greater_equal(1)

func test_green_elder_drops_poison_trail_on_movement() -> void:
	for c in get_tree().get_nodes_in_group("damage_cloud"):
		c.queue_free()
	await get_tree().process_frame
	var elder := _spawn_elder("green", Vector3.ZERO)
	await get_tree().process_frame
	# Move elder ~1.5m and tick.
	elder.global_position = Vector3(1.5, 0, 0)
	# Force-fire alive-tick once.
	if elder._elder_ability != null and not elder._elder_ability.on_alive_tick.is_null():
		elder._elder_ability.on_alive_tick.call(elder, 1.0 / 60.0)
	await get_tree().process_frame
	var found_green_cloud: bool = false
	for c in get_tree().get_nodes_in_group("damage_cloud"):
		if c.get("base_color") == "green":
			found_green_cloud = true
			break
	assert_bool(found_green_cloud).is_true()

func test_purple_elder_pulls_player_on_attack() -> void:
	var elder := _spawn_elder("purple", Vector3.ZERO)
	var player: CharacterBody3D = auto_free(load("res://scenes/entities/player.tscn").instantiate())
	add_child(player)
	player.global_position = Vector3(2, 0, 0)
	await get_tree().process_frame
	var prev_kb: Vector3 = player._knockback_velocity
	# Force-fire on_attack (purple's ability calls apply_pull_toward on the target).
	elder._elder_ability.on_attack.call(elder, player)
	# Knockback velocity x should have decreased (player pulled toward elder at origin).
	assert_bool(player._knockback_velocity.x < prev_kb.x).is_true()

func test_gold_elder_chain_zaps_other_enemy() -> void:
	var elder := _spawn_elder("gold", Vector3.ZERO)
	var other: CharacterBody3D = auto_free(WelpScene.instantiate())
	other.tier = "welp"
	other.color = "red"
	add_child(other)
	other.global_position = Vector3(2, 0, 0)
	await get_tree().process_frame
	var initial_hp: int = other.hp
	# Fire on_attack with player as the primary target (not really used by gold).
	elder._elder_ability.on_attack.call(elder, null)
	assert_int(other.hp).is_less(initial_hp)

func test_white_elder_spawns_bone_wall_near_pc_on_death() -> void:
	for w in get_tree().get_nodes_in_group("bone_wall"):
		w.queue_free()
	await get_tree().process_frame
	var elder := _spawn_elder("white", Vector3(8, 0, 0))
	var player: CharacterBody3D = auto_free(load("res://scenes/entities/player.tscn").instantiate())
	add_child(player)
	player.global_position = Vector3.ZERO
	await get_tree().process_frame
	elder.take_damage(elder.max_hp + 100)
	await get_tree().process_frame
	var found_wall: bool = false
	for w in get_tree().get_nodes_in_group("bone_wall"):
		if not is_instance_valid(w):
			continue
		var d: float = w.global_position.distance_to(player.global_position)
		# Wall should be 2-3m from the player.
		if d >= 1.5 and d <= 3.5:
			found_wall = true
			break
	assert_bool(found_wall).is_true()
```

- [ ] **Step 3: Run tests to verify pass**

```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/test_elder_abilities.gd --ignoreHeadlessMode 2>&1 | tail -10
```
Expected: all 13+ tests PASSED.

- [ ] **Step 4: Run full suite to verify no regressions**

```
"/c/Users/wyenk/OneDrive/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --continue --ignoreHeadlessMode 2>&1 | tail -3
```
Expected: all tests passing. The pre-existing `test_drop_policy.gd::test_elder_drops_only_elder_pickup` may now also see a side effect (e.g., elder spawns a bone wall on death). If so, the test should still pass because it asserts pickups, not bone walls — but verify.

- [ ] **Step 5: Commit**

```
git add scripts/entities/welp.gd test/test_elder_abilities.gd
git commit -m "feat(elder): wire elder abilities into welp.gd lifecycle (Task B3)"
```

---

## Self-review checklist

After implementing, verify:

- [ ] All Phase A tasks committed (A1-A6).
- [ ] All Phase B tasks committed (B1-B3).
- [ ] Full test suite passes; new test count is reasonable (~344 baseline + ~25 new).
- [ ] `Escalation.can_spawn_tier` works for dragon and elder; both reset on `Escalation.reset()`.
- [ ] `corner_spawner._spawn` downgrades to welp when floor is active.
- [ ] Cone constants are 12.0 and 100.0 in both static and sweeping breath.
- [ ] Cone .tscn mesh height is 12.0; mesh transform translation z is -6.0.
- [ ] `effect_cloud.gd` has `hp` field default 30 and `take_damage(amount)`.
- [ ] `boss_mechanic._segment_blocked_by_cloud` damages the cloud with `CLOUD_BREATH_BLOCK_DAMAGE = 5`.
- [ ] `effect_gravity_well.gd` has `consume_for_redirect` that drains 0.5s.
- [ ] Both breath mechanics' `on_pull_during_windup` accept `source: Node = null` and call `consume_for_redirect`.
- [ ] All 6 elder abilities exist in `scripts/entities/elder_abilities/` and register in `ElderAbilityRegistry`.
- [ ] Welp.gd resolves `_elder_ability` on `_ready` and fires hooks at the three lifecycle moments.

---

## Out of scope for this plan

- Per-color tunable spawn floors (currently global; could become per-color with more state).
- Audio + VFX polish on elder abilities.
- Boss-side counter-cleanup ability (a more aggressive solution to cloud/well stacking that destroys nearby player effects on a cooldown).
- Telegraphed elder casts (current spec keeps elder behavior to passive/reactive hooks only).
- Elder ability balance tuning beyond first-pass numbers.

---

## Self-review pass log

**Spec coverage:**
- B1 spawn floor (§3a): Task A1 ✓
- B1 spawner respects floor (§3b): Task A2 ✓
- B2 elder abilities (§2 — six specs): Tasks B1, B2, B3 ✓
- C1 cone size (§4a): Task A3 ✓
- C1 cone visual apex (§4b): Task A4 ✓
- C2 cloud burn-through (§4c): Task A5 ✓
- C2 well drain on redirect (§4d): Task A6 ✓
- Risks (§6) — pull-on-hit cooldown is in elder_ability_purple_pull_on_hit.gd ✓

**Placeholder scan:** none. All steps include code, exact paths, and run commands.

**Type consistency:** `ElderAbility.color` (String), `ElderAbility.on_alive_tick/on_attack/on_death` (Callable). Welp's `_elder_ability` is typed `ElderAbility`. Registry's `get_for_color` returns `ElderAbility`. Consistent.
