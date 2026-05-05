extends Node

# Debug instrument: logs damage events on a watched target so we can identify
# which sources are dealing the most DPS. Inactive by default — boss_dragon
# calls start_for_target(self) on _ready and dump_log() on death.
#
# Records both REQUESTED damage (what the source asked for) and ACTUAL damage
# (what landed after caps). The boss has DMG_CAP_PER_TICK; comparing the two
# columns shows when the cap is engaging.

const HEADER: String = "time   | requested | actual | source"
const SEPARATOR: String = "-------+-----------+--------+--------"

var _active: bool = false
var _t0_msec: int = 0
var _watch_target_id: int = 0  # 0 = no target; non-zero = only record events on this instance
var _events: Array[Dictionary] = []

func start_for_target(target: Node) -> void:
	_events.clear()
	_t0_msec = Time.get_ticks_msec()
	_watch_target_id = target.get_instance_id() if target != null else 0
	_active = true

func stop() -> void:
	_active = false

func is_active() -> bool:
	return _active

func record(target: Node, requested: int, actual: int, source: String) -> void:
	if not _active:
		return
	if target == null:
		return
	if _watch_target_id != 0 and target.get_instance_id() != _watch_target_id:
		return
	var t: float = float(Time.get_ticks_msec() - _t0_msec) / 1000.0
	_events.append({
		"t": t,
		"requested": requested,
		"actual": actual,
		"source": source,
	})

func dump_log() -> void:
	# Debug instrumentation — release builds shouldn't dump a multi-line log to
	# stdout on every boss kill. Editor / debug runs still get the full report.
	if not OS.is_debug_build():
		return
	print("\n=== DamageMeter Log ===")
	if _events.is_empty():
		print("(no events recorded)")
		print("=========================\n")
		return
	print(HEADER)
	print(SEPARATOR)
	var by_source_actual: Dictionary = {}
	var by_source_req: Dictionary = {}
	var by_source_count: Dictionary = {}
	var total_req: int = 0
	var total_actual: int = 0
	for e in _events:
		print("%-6.3f | %9d | %6d | %s" % [e.t, e.requested, e.actual, e.source])
		by_source_actual[e.source] = int(by_source_actual.get(e.source, 0)) + e.actual
		by_source_req[e.source] = int(by_source_req.get(e.source, 0)) + e.requested
		by_source_count[e.source] = int(by_source_count.get(e.source, 0)) + 1
		total_req += e.requested
		total_actual += e.actual
	print("--- Totals by source (sorted by actual damage) ---")
	var sources: Array = by_source_actual.keys()
	sources.sort_custom(func(a, b): return by_source_actual[a] > by_source_actual[b])
	for src in sources:
		print("  %-22s: %5d actual / %5d requested  (%d events)" % [src, by_source_actual[src], by_source_req[src], by_source_count[src]])
	var duration: float = float(_events[-1].t)
	print("--- Total: %d actual / %d requested over %.2fs ---" % [total_actual, total_req, duration])
	if duration > 0.0:
		print("--- Avg DPS: %.1f actual, %.1f requested ---" % [float(total_actual) / duration, float(total_req) / duration])
	print("=========================\n")
