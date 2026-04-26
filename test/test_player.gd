extends GdUnitTestSuite

const PlayerScript = preload("res://scripts/entities/player.gd")

var player: CharacterBody3D

func before_test() -> void:
	# Reset autoload state so the player constructor doesn't read pollution
	# from the user's real save (cantrip bonuses, retained skills, etc).
	MetaProgress._init_defaults()
	BossFlow.retained_skills.clear()
	player = auto_free(CharacterBody3D.new())
	player.set_script(PlayerScript)
	add_child(player)
	# let _ready run
	await get_tree().process_frame

func test_player_starts_with_full_hp() -> void:
	assert_that(player.hp).is_equal(100)

func test_take_damage_reduces_hp() -> void:
	player.take_damage(30)
	assert_that(player.hp).is_equal(70)

func test_take_damage_clamped_at_zero() -> void:
	player.take_damage(150)
	assert_that(player.hp).is_equal(0)

func test_died_signal_emits_at_zero_hp() -> void:
	var monitor := monitor_signals(player)
	player.take_damage(150)
	await assert_signal(player).is_emitted("died")

func test_died_signal_emits_only_once() -> void:
	player.take_damage(150)
	var monitor := monitor_signals(player)
	player.take_damage(10)
	await assert_signal(player).is_not_emitted("died")

func test_reset_restores_hp() -> void:
	player.take_damage(50)
	player.reset_run_state()
	assert_that(player.hp).is_equal(100)

func test_dash_starts_off_cooldown() -> void:
	assert_that(player.can_dash()).is_true()

func test_dash_triggers_cooldown() -> void:
	player.try_dash(Vector3(1, 0, 0))
	assert_that(player.can_dash()).is_false()

func test_dash_cooldown_expires() -> void:
	player.try_dash(Vector3(1, 0, 0))
	# Simulate 2 seconds passing
	player._dash_cooldown_remaining = 0.0
	assert_that(player.can_dash()).is_true()

func test_dash_returns_false_on_cooldown() -> void:
	player.try_dash(Vector3(1, 0, 0))
	assert_that(player.try_dash(Vector3(1, 0, 0))).is_false()

func test_dash_grants_iframes() -> void:
	player.try_dash(Vector3(1, 0, 0))
	assert_that(player.is_invincible()).is_true()

func test_take_damage_during_iframes_does_nothing() -> void:
	player.try_dash(Vector3(1, 0, 0))
	player.take_damage(50)
	assert_that(player.hp).is_equal(100)
