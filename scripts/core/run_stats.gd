extends Node

# Run-scoped metrics. Reset when player crosses the upstairs trigger
# (a new run begins); read by run_end_summary on death.

var run_start_time_ms: int = 0
var enemies_slain: int = 0
var last_damage_source_name: String = ""
# Phase 10 tuning: first whelp kill of the run drops 1 minor soul (so the
# player can unlock their first wand from sword-only). Tracked here because
# welp instances don't survive the kill, and run-scoped state belongs here.
var first_whelp_kill_completed: bool = false

func reset_run() -> void:
	run_start_time_ms = Time.get_ticks_msec()
	enemies_slain = 0
	last_damage_source_name = ""
	first_whelp_kill_completed = false

func record_kill() -> void:
	enemies_slain += 1

func record_damage_from(source_name: String) -> void:
	last_damage_source_name = source_name

func mark_first_whelp_kill() -> void:
	first_whelp_kill_completed = true

func elapsed_seconds() -> float:
	return (Time.get_ticks_msec() - run_start_time_ms) / 1000.0
