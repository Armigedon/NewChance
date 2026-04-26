extends GdUnitTestSuite

const BossScript = preload("res://scripts/entities/boss_dragon.gd")

var boss: CharacterBody3D

func before_test() -> void:
	boss = auto_free(BossScript.new())
	add_child(boss)

func test_idle_taunt_fires_when_timer_exceeds_threshold() -> void:
	# After accumulating > IDLE_TAUNT_INTERVAL of fight time, _should_fire_idle_taunt() returns true.
	boss._idle_taunt_timer = 18.5
	boss._taunt_cooldown = 0.0
	assert_that(boss._should_fire_idle_taunt()).is_true()

func test_idle_taunt_blocked_when_cooldown_active() -> void:
	# Even at the threshold, cooldown > 0 prevents firing.
	boss._idle_taunt_timer = 18.5
	boss._taunt_cooldown = 2.0
	assert_that(boss._should_fire_idle_taunt()).is_false()

func test_idle_taunt_blocked_below_threshold() -> void:
	boss._idle_taunt_timer = 5.0
	boss._taunt_cooldown = 0.0
	assert_that(boss._should_fire_idle_taunt()).is_false()

func test_record_taunt_resets_idle_timer_and_sets_cooldown() -> void:
	# Calling _record_taunt_fired() resets idle timer to 0 and arms 5s cooldown.
	boss._idle_taunt_timer = 18.5
	boss._taunt_cooldown = 0.0
	boss._record_taunt_fired()
	assert_that(boss._idle_taunt_timer).is_equal_approx(0.0, 0.001)
	assert_that(boss._taunt_cooldown).is_equal_approx(5.0, 0.001)

func test_advance_taunt_timers_increments_idle_and_decays_cooldown() -> void:
	boss._idle_taunt_timer = 0.0
	boss._taunt_cooldown = 3.0
	boss._advance_taunt_timers(1.0)
	assert_that(boss._idle_taunt_timer).is_equal_approx(1.0, 0.001)
	assert_that(boss._taunt_cooldown).is_equal_approx(2.0, 0.001)

func test_advance_taunt_timers_floors_cooldown_at_zero() -> void:
	boss._idle_taunt_timer = 0.0
	boss._taunt_cooldown = 0.5
	boss._advance_taunt_timers(2.0)
	assert_that(boss._taunt_cooldown).is_equal_approx(0.0, 0.001)
