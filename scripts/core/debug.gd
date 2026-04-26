extends Node

# Single source of truth for FAST-TEST vs SHIP value selection.
# Flip to false before any release build.
# NOTE: Change requires editor/game restart — downstream static var initializers
# bake this value at script parse time.
const FAST_TEST: bool = true
