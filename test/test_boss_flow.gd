extends GdUnitTestSuite

const BossFlowScript = preload("res://scripts/core/boss_flow.gd")

var bf: Node

func before_test() -> void:
	bf = auto_free(BossFlowScript.new())
	add_child(bf)

func test_starts_idle() -> void:
	assert_that(bf.state).is_equal(BossFlowScript.State.IDLE)

func test_trigger_boss_moves_to_pending() -> void:
	bf.trigger_boss()
	assert_that(bf.state).is_equal(BossFlowScript.State.PENDING)

func test_enter_arena_moves_to_active() -> void:
	bf.trigger_boss()
	bf.enter_arena()
	assert_that(bf.state).is_equal(BossFlowScript.State.ACTIVE)

func test_boss_killed_moves_to_won() -> void:
	bf.trigger_boss()
	bf.enter_arena()
	bf.boss_killed()
	assert_that(bf.state).is_equal(BossFlowScript.State.WON)

func test_player_died_moves_to_lost() -> void:
	bf.trigger_boss()
	bf.enter_arena()
	bf.player_died_in_boss()
	assert_that(bf.state).is_equal(BossFlowScript.State.LOST)

func test_lost_can_retrigger() -> void:
	bf.trigger_boss()
	bf.enter_arena()
	bf.player_died_in_boss()
	bf.trigger_boss()
	assert_that(bf.state).is_equal(BossFlowScript.State.PENDING)

func test_won_stays_won() -> void:
	bf.trigger_boss()
	bf.enter_arena()
	bf.boss_killed()
	bf.trigger_boss()
	assert_that(bf.state).is_equal(BossFlowScript.State.WON)

func test_state_changed_signal() -> void:
	var monitor := monitor_signals(bf)
	bf.trigger_boss()
	await assert_signal(bf).is_emitted("state_changed", [BossFlowScript.State.PENDING])

func test_is_active_during_pending_or_active() -> void:
	assert_that(bf.is_active()).is_false()
	bf.trigger_boss()
	assert_that(bf.is_active()).is_true()
	bf.enter_arena()
	assert_that(bf.is_active()).is_true()
	bf.boss_killed()
	assert_that(bf.is_active()).is_false()

func test_reset_returns_to_idle_unless_won() -> void:
	bf.trigger_boss()
	bf.player_died_in_boss()
	bf.reset()
	assert_that(bf.state).is_equal(BossFlowScript.State.IDLE)

func test_reset_preserves_won() -> void:
	bf.trigger_boss()
	bf.enter_arena()
	bf.boss_killed()
	bf.reset()
	assert_that(bf.state).is_equal(BossFlowScript.State.WON)

func test_victory_line_flag_starts_false() -> void:
	assert_that(bf.has_shown_victory_line()).is_false()

func test_mark_victory_line_shown_flips_flag() -> void:
	bf.mark_victory_line_shown()
	assert_that(bf.has_shown_victory_line()).is_true()

func test_pending_banner_line_starts_empty() -> void:
	assert_that(bf.consume_pending_banner_line()).is_equal("")

func test_set_pending_banner_line_sets_value() -> void:
	bf.set_pending_banner_line("death_normal")
	assert_that(bf.consume_pending_banner_line()).is_equal("death_normal")

func test_consume_pending_banner_line_clears_value() -> void:
	bf.set_pending_banner_line("death_boss")
	bf.consume_pending_banner_line()
	# Subsequent consume returns empty.
	assert_that(bf.consume_pending_banner_line()).is_equal("")
