extends CharacterBody3D

@export var max_hp: int = 100

const CAST_RED_FIREBALL: PackedScene = preload("res://scenes/skills/cast_red_fireball.tscn")
const CAST_BLUE_ICE_LINE: PackedScene = preload("res://scenes/skills/cast_blue_ice_line.tscn")
const CAST_GREEN_PLAGUE: PackedScene = preload("res://scenes/skills/cast_green_plague.tscn")
const CAST_PURPLE_VOID: PackedScene = preload("res://scenes/skills/cast_purple_void.tscn")
const CAST_GOLD_LIGHTNING: PackedScene = preload("res://scenes/skills/cast_gold_lightning.tscn")
const CAST_WHITE_BONE: PackedScene = preload("res://scenes/skills/cast_white_bone.tscn")
const DamagePipeline = preload("res://scripts/skills/damage_pipeline.gd")

@export var move_speed: float = 5.0
@export var dash_distance: float = 4.0
@export var dash_duration: float = 0.15
@export var dash_cooldown: float = 2.0
@export var iframe_duration: float = 0.2
@export var cast_cooldown: float = 0.6

@onready var _skill_system: SkillSystem = $SkillSystem if has_node("SkillSystem") else null

signal died
signal hp_changed(new_hp: int)

func _ready() -> void:
	if _skill_system != null:
		_skill_system.active_skill_changed.connect(_on_active_skill_changed)
		_skill_system.elder_modifier_applied.connect(_on_elder_modifier_applied)
	GameState.run_ended.connect(_on_run_ended)
	# Boss-flow skill retention: if BossFlow has a snapshot, restore it.
	# With Wand Choice unlocked, the run starts with the chosen color.
	# Otherwise the run starts wandless; first minor pickup unlocks the wand
	# (see soul_pickup.gd → SkillSystem.unlock_first_wand).
	if not BossFlow.retained_skills.is_empty() and _skill_system != null:
		_skill_system.from_dict(BossFlow.retained_skills)
	elif _skill_system != null and MetaShop.has_structural("wand_choice"):
		_skill_system.start_default_wand(MetaShop.starting_wand_color())
	# Phase 9 redesign: stats now sourced from MetaShop (cantrips migrated in Task 12).
	max_hp = int(float(max_hp) * (1.0 + MetaShop.stat_value("vitality")))
	hp = max_hp
	dash_cooldown = max(0.2, dash_cooldown * (1.0 - MetaShop.stat_value("cast_speed")))
	# Seed elder modifier per-encounter state (e.g., Bone Shield charges).
	_seed_elder_modifier_state()

func _seed_elder_modifier_state() -> void:
	if _skill_system == null:
		return
	var active: Skill = _skill_system.active_skill()
	if active == null:
		return
	# Bone Shield seeds charges per stack count.
	var bs_stacks: int = active.elder_modifier_stack_count("bone_shield")
	if bs_stacks > 0:
		set_meta("bone_shield_charges", bs_stacks)

func _on_elder_modifier_applied(modifier_id: String, _new_stack: int) -> void:
	if modifier_id == "bone_shield":
		_seed_elder_modifier_state()

func _on_active_skill_changed(_index: int) -> void:
	if _skill_system == null:
		return
	var element: String = _skill_system.active_element()
	var white_count: int = 0
	var skill: Skill = _skill_system.active_skill()
	if skill != null:
		white_count = skill.modifier_count_for("white")
	if has_node("Sword"):
		$Sword.set_active_element(element, white_count)

func _on_run_ended(_outcome: int) -> void:
	if _skill_system != null:
		_skill_system.clear()
	# Any normal end-of-run also drops the boss-flow skill snapshot.
	BossFlow.clear_retained_skills()
	if has_node("Sword"):
		$Sword.set_active_element("", 0)

var hp: int = max_hp
var _is_dead: bool = false
var _dash_cooldown_remaining: float = 0.0
var _iframe_remaining: float = 0.0
var _dash_velocity: Vector3 = Vector3.ZERO
var _dash_time_remaining: float = 0.0
var _cast_cooldown_remaining: float = 0.0

# --- Armor stacks (Phase 9, white WARD layer) ---
const ARMOR_PER_STACK: int = 5
var _armor_stacks: int = 0
var _armor_remaining: float = 0.0

func _process(delta: float) -> void:
	if _cast_cooldown_remaining > 0.0:
		_cast_cooldown_remaining = max(0.0, _cast_cooldown_remaining - delta)
	if _dash_cooldown_remaining > 0.0:
		_dash_cooldown_remaining = max(0.0, _dash_cooldown_remaining - delta)
	if _iframe_remaining > 0.0:
		_iframe_remaining = max(0.0, _iframe_remaining - delta)
	if _dash_time_remaining > 0.0:
		_dash_time_remaining = max(0.0, _dash_time_remaining - delta)
	if _armor_remaining > 0.0:
		_armor_remaining = max(0.0, _armor_remaining - delta)
		if _armor_remaining == 0.0:
			_armor_stacks = 0
	if Input.is_action_just_pressed("dash"):
		var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		var dash_dir: Vector3 = Vector3(input_dir.x, 0, input_dir.y)
		if dash_dir.length() > 0.01:
			try_dash(dash_dir.normalized())
	if Input.is_action_pressed("cast"):
		_try_cast()

func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	if _dash_time_remaining > 0.0:
		velocity.x = _dash_velocity.x
		velocity.z = _dash_velocity.z
	else:
		var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		var direction: Vector3 = Vector3(input_dir.x, 0, input_dir.y)
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	velocity.y -= 9.8 * delta if not is_on_floor() else 0.0
	move_and_slide()

func can_dash() -> bool:
	return _dash_cooldown_remaining <= 0.0 and not _is_dead

func try_dash(direction: Vector3) -> bool:
	if not can_dash():
		return false
	_dash_velocity = direction * (dash_distance / dash_duration)
	_dash_time_remaining = dash_duration
	_dash_cooldown_remaining = dash_cooldown
	_iframe_remaining = iframe_duration
	return true

func apply_armor(stacks: int, duration: float) -> void:
	_armor_stacks += stacks
	_armor_remaining = max(_armor_remaining, duration)

func is_invincible() -> bool:
	return _iframe_remaining > 0.0

func take_damage(amount: int) -> void:
	if _is_dead or is_invincible():
		return
	# Armor absorbs first; stacks drain greedily until the hit is fully
	# absorbed (each stack absorbs up to ARMOR_PER_STACK damage).
	while _armor_stacks > 0 and amount > 0:
		var absorb: int = min(amount, ARMOR_PER_STACK)
		amount -= absorb
		_armor_stacks -= 1
	if amount <= 0:
		return
	# Fire elder modifier on_player_damaged hooks; if any sets up an absorb
	# (e.g., Bone Shield consumes a charge), check after.
	if _skill_system != null:
		var active: Skill = _skill_system.active_skill()
		if active != null:
			var bone_shield_charges_before: int = int(get_meta("bone_shield_charges", 0))
			for modifier_id in active.elder_modifier_stacks.keys():
				var em: ElderModifier = ElderRegistry.get_modifier(modifier_id)
				if em == null or em.on_player_damaged.is_null():
					continue
				var stack: int = active.elder_modifier_stack_count(modifier_id)
				em.on_player_damaged.call(self, amount, stack)
			# Bone Shield: if a charge was consumed by the hook, the hit is absorbed.
			var bone_shield_charges_after: int = int(get_meta("bone_shield_charges", 0))
			if bone_shield_charges_after < bone_shield_charges_before:
				return  # absorbed, no HP damage
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

func _try_cast() -> void:
	if _cast_cooldown_remaining > 0.0:
		return
	var skill: Skill = _skill_system.active_skill()
	if skill == null:
		return
	var cast_scene: PackedScene = _scene_for_color(skill.base_color)
	if cast_scene == null:
		return
	var cast = cast_scene.instantiate()
	cast.configure(skill)
	DamagePipeline.fire_cast_spawners(skill, self)
	# Fire elder modifier on_cast hooks for the active wand.
	for modifier_id in skill.elder_modifier_stacks.keys():
		var em: ElderModifier = ElderRegistry.get_modifier(modifier_id)
		if em == null or em.on_cast.is_null():
			continue
		var stack: int = skill.elder_modifier_stack_count(modifier_id)
		em.on_cast.call(self, skill.modifier_stack, skill.base_color, stack)
	# Aim direction: toward mouse cursor on the floor plane (y=1)
	var cam: Camera3D = get_viewport().get_camera_3d()
	var aim_dir: Vector3 = Vector3.FORWARD
	var hit_point: Vector3 = global_position  # fallback to player pos if no camera/ray
	if cam != null:
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		var ray_origin: Vector3 = cam.project_ray_origin(mouse_pos)
		var ray_dir: Vector3 = cam.project_ray_normal(mouse_pos)
		if absf(ray_dir.y) > 0.001:
			var t: float = (1.0 - ray_origin.y) / ray_dir.y
			hit_point = ray_origin + ray_dir * t
			var to_target: Vector3 = hit_point - global_position
			to_target.y = 0.0
			if to_target.length() > 0.01:
				aim_dir = to_target.normalized()
	cast.direction = aim_dir
	cast.target_pos = hit_point
	# Projectile casts read spawn_pos in _ready; placed casts use target_pos. Setting
	# global_position here directly errors because the cast isn't in the tree yet.
	cast.spawn_pos = Vector3(global_position.x, 0.5, global_position.z) + aim_dir * 1.0
	get_parent().add_child(cast)
	_cast_cooldown_remaining = cast_cooldown

func _scene_for_color(color: String) -> PackedScene:
	match color:
		"red": return CAST_RED_FIREBALL
		"blue": return CAST_BLUE_ICE_LINE
		"green": return CAST_GREEN_PLAGUE
		"purple": return CAST_PURPLE_VOID
		"gold": return CAST_GOLD_LIGHTNING
		"white": return CAST_WHITE_BONE
		_: return null

func reset_run_state() -> void:
	hp = max_hp
	_is_dead = false
	hp_changed.emit(hp)
