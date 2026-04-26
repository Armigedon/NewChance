extends GdUnitTestSuite

const VfxScript = preload("res://scripts/effects/vfx.gd")
const SpawnerScript = preload("res://scripts/world/corner_spawner.gd")

var spawner: Node3D

func before_test() -> void:
	spawner = auto_free(SpawnerScript.new())
	spawner.global_position = Vector3.ZERO
	add_child(spawner)
	# Disable autorun process so tests don't trigger _spawn().
	spawner.set_process(false)

func test_proximity_multiplier_close() -> void:
	# Player within 8m → 2.5x multiplier.
	var mult: float = spawner._compute_proximity_multiplier(Vector3(5, 0, 0))
	assert_that(mult).is_equal_approx(2.5, 0.001)

func test_proximity_multiplier_at_close_boundary() -> void:
	# Exactly 8m → still close (≤ 8 inclusive).
	var mult: float = spawner._compute_proximity_multiplier(Vector3(8, 0, 0))
	assert_that(mult).is_equal_approx(2.5, 0.001)

func test_proximity_multiplier_medium() -> void:
	# Between 8m and 16m → 1.0x.
	var mult: float = spawner._compute_proximity_multiplier(Vector3(12, 0, 0))
	assert_that(mult).is_equal_approx(1.0, 0.001)

func test_proximity_multiplier_at_far_boundary() -> void:
	# Exactly 16m → still medium (≤ 16 inclusive).
	var mult: float = spawner._compute_proximity_multiplier(Vector3(16, 0, 0))
	assert_that(mult).is_equal_approx(1.0, 0.001)

func test_proximity_multiplier_far() -> void:
	# Beyond 16m → 0.3x.
	var mult: float = spawner._compute_proximity_multiplier(Vector3(20, 0, 0))
	assert_that(mult).is_equal_approx(0.3, 0.001)

func test_proximity_multiplier_ignores_y() -> void:
	# Y axis must not affect distance (top-down 3D).
	var mult: float = spawner._compute_proximity_multiplier(Vector3(5, 100, 0))
	assert_that(mult).is_equal_approx(2.5, 0.001)

func test_proximity_multiplier_no_player_returns_one() -> void:
	# Sentinel: when player position is INF, treat as medium (no boost, no penalty).
	var mult: float = spawner._compute_proximity_multiplier(Vector3.INF)
	assert_that(mult).is_equal_approx(1.0, 0.001)

func test_is_close_for_burst_check() -> void:
	# _is_close returns true iff player within 8m XZ.
	assert_that(spawner._is_close(Vector3(5, 0, 0))).is_true()
	assert_that(spawner._is_close(Vector3(8, 0, 0))).is_true()
	assert_that(spawner._is_close(Vector3(8.1, 0, 0))).is_false()
	assert_that(spawner._is_close(Vector3(20, 0, 0))).is_false()
	assert_that(spawner._is_close(Vector3.INF)).is_false()

func test_is_far_check() -> void:
	# _is_far returns true iff player beyond 16m XZ.
	assert_that(spawner._is_far(Vector3(20, 0, 0))).is_true()
	assert_that(spawner._is_far(Vector3(16, 0, 0))).is_false()
	assert_that(spawner._is_far(Vector3(5, 0, 0))).is_false()
	assert_that(spawner._is_far(Vector3.INF)).is_false()
