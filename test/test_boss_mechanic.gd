extends GdUnitTestSuite

const BossMechanic = preload("res://scripts/entities/boss_mechanic.gd")

func test_starts_ready_when_unlocked() -> void:
	var m: Node = BossMechanic.new()
	add_child(auto_free(m))
	m.unlock_phase = 1
	m.cooldowns_by_phase = {1: 5.0}
	assert_bool(m.is_ready(1)).is_true()
	assert_bool(m.is_ready(0)).is_false()  # phase 0 = not unlocked

func test_unlock_phase_gates_readiness() -> void:
	var m: Node = BossMechanic.new()
	add_child(auto_free(m))
	m.unlock_phase = 3
	m.cooldowns_by_phase = {1: 5.0, 2: 4.0, 3: 3.0}
	assert_bool(m.is_ready(1)).is_false()
	assert_bool(m.is_ready(2)).is_false()
	assert_bool(m.is_ready(3)).is_true()

func test_trigger_starts_telegraph_and_resets_cooldown() -> void:
	var m: Node = BossMechanic.new()
	add_child(auto_free(m))
	m.unlock_phase = 1
	m.cooldowns_by_phase = {1: 5.0}
	m.windup_duration = 0.5
	m.execution_duration = 0.2
	m.trigger(1)
	assert_bool(m.is_busy()).is_true()
	assert_bool(m.is_ready(1)).is_false()  # cooldown active

func test_lifecycle_states_advance_through_tick() -> void:
	# Smoke test: catches silent breakage of the _ready signal wiring.
	# If _ready ever stops connecting one of the three signals, this test fails.
	var m: Node = BossMechanic.new()
	add_child(auto_free(m))
	m.unlock_phase = 1
	m.cooldowns_by_phase = {1: 5.0}
	m.windup_duration = 0.1
	m.execution_duration = 0.1
	m.trigger(1)
	assert_bool(m.is_in_windup()).is_true()
	m.tick(0.15, 1)
	assert_bool(m.is_in_execution()).is_true()
	m.tick(0.15, 1)
	assert_bool(m.is_busy()).is_false()
