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
