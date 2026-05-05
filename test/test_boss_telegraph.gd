extends GdUnitTestSuite

const BossTelegraph = preload("res://scripts/entities/boss_telegraph.gd")

func test_starts_idle() -> void:
	var t: BossTelegraph = BossTelegraph.new()
	assert_int(t.state).is_equal(BossTelegraph.State.IDLE)
	assert_bool(t.is_busy()).is_false()

func test_start_windup_transitions_to_windup() -> void:
	var t: BossTelegraph = BossTelegraph.new()
	t.windup_duration = 1.0
	t.execution_duration = 0.5
	t.start_windup()
	assert_int(t.state).is_equal(BossTelegraph.State.WINDUP)
	assert_bool(t.is_busy()).is_true()

func test_windup_completes_to_execution() -> void:
	var t: BossTelegraph = BossTelegraph.new()
	t.windup_duration = 1.0
	t.execution_duration = 0.5
	t.start_windup()
	t.tick(1.1)  # exceed windup
	assert_int(t.state).is_equal(BossTelegraph.State.EXECUTION)
	assert_bool(t.is_busy()).is_true()

func test_execution_completes_to_idle() -> void:
	var t: BossTelegraph = BossTelegraph.new()
	t.windup_duration = 0.1
	t.execution_duration = 0.5
	t.start_windup()
	t.tick(0.2)  # past windup, now in EXECUTION
	t.tick(0.6)  # past execution
	assert_int(t.state).is_equal(BossTelegraph.State.IDLE)
	assert_bool(t.is_busy()).is_false()

func test_signals_fire_in_order() -> void:
	var t: BossTelegraph = BossTelegraph.new()
	t.windup_duration = 0.1
	t.execution_duration = 0.1
	var events: Array[String] = []
	t.windup_started.connect(func(): events.append("windup"))
	t.execution_started.connect(func(): events.append("execution"))
	t.execution_ended.connect(func(): events.append("end"))
	t.start_windup()
	t.tick(0.15)
	t.tick(0.15)
	assert_array(events).is_equal(["windup", "execution", "end"])

func test_extend_windup_during_windup_extends_timer() -> void:
	var t: BossTelegraph = BossTelegraph.new()
	t.windup_duration = 1.0
	t.execution_duration = 0.5
	t.start_windup()
	t.tick(0.5)  # 0.5s remaining in windup
	t.extend_windup(0.3)  # now 0.8s remaining
	t.tick(0.5)  # 0.3s remaining; still in WINDUP
	assert_int(t.state).is_equal(BossTelegraph.State.WINDUP)
	t.tick(0.4)  # past windup → EXECUTION
	assert_int(t.state).is_equal(BossTelegraph.State.EXECUTION)

func test_extend_windup_during_execution_is_noop() -> void:
	var t: BossTelegraph = BossTelegraph.new()
	t.windup_duration = 0.1
	t.execution_duration = 1.0
	t.start_windup()
	t.tick(0.15)  # past windup → EXECUTION, _timer ~ 0.95
	t.extend_windup(2.0)  # noop (not WINDUP)
	t.tick(0.96)  # should exhaust execution and return to IDLE
	assert_int(t.state).is_equal(BossTelegraph.State.IDLE)

func test_extend_windup_during_idle_is_noop() -> void:
	var t: BossTelegraph = BossTelegraph.new()
	t.windup_duration = 1.0
	t.execution_duration = 0.5
	# not started → IDLE
	t.extend_windup(2.0)  # noop
	t.start_windup()
	t.tick(1.05)  # exhaust standard 1.0s windup
	assert_int(t.state).is_equal(BossTelegraph.State.EXECUTION)

func test_overshoot_carries_into_execution() -> void:
	var t: BossTelegraph = BossTelegraph.new()
	t.windup_duration = 1.0
	t.execution_duration = 1.0
	t.start_windup()
	# Tick 1.4s: should exhaust windup (1.0s) AND consume 0.4s of execution
	t.tick(1.4)
	assert_int(t.state).is_equal(BossTelegraph.State.EXECUTION)
	# Now tick 0.7s — should exceed remaining 0.6s and finish execution → IDLE
	t.tick(0.7)
	assert_int(t.state).is_equal(BossTelegraph.State.IDLE)

func test_one_giant_tick_completes_full_cycle() -> void:
	var t: BossTelegraph = BossTelegraph.new()
	t.windup_duration = 0.1
	t.execution_duration = 0.1
	var events: Array[String] = []
	t.windup_started.connect(func(): events.append("windup"))
	t.execution_started.connect(func(): events.append("execution"))
	t.execution_ended.connect(func(): events.append("end"))
	t.start_windup()
	t.tick(5.0)  # vastly exceeds total cycle
	assert_int(t.state).is_equal(BossTelegraph.State.IDLE)
	assert_array(events).is_equal(["windup", "execution", "end"])
