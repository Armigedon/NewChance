extends GdUnitTestSuite

const WelpScene: PackedScene = preload("res://scenes/entities/welp.tscn")

func before_test() -> void:
	# Clear any stale soul pickups from prior tests.
	for p in get_tree().get_nodes_in_group("soul_pickup"):
		p.queue_free()
	await get_tree().process_frame

func _spawn(tier: String, color: String) -> CharacterBody3D:
	var w: CharacterBody3D = auto_free(WelpScene.instantiate())
	w.tier = tier
	w.color = color
	add_child(w)
	w.global_position = Vector3.ZERO
	return w

func _count_pickups_in_scene() -> Dictionary:
	var counts: Dictionary = {"minor": 0, "elder": 0}
	for n in get_tree().get_root().get_children():
		_walk_count(n, counts)
	return counts

func _walk_count(node: Node, counts: Dictionary) -> void:
	if node.has_method("_on_body_entered") and "tier" in node:
		counts[String(node.tier)] = int(counts.get(String(node.tier), 0)) + 1
	for c in node.get_children():
		_walk_count(c, counts)

func test_whelp_drops_nothing() -> void:
	var w := _spawn("welp", "red")
	w.take_damage(w.max_hp + 100)
	await get_tree().process_frame
	var counts := _count_pickups_in_scene()
	assert_int(counts["minor"]).is_equal(0)
	assert_int(counts["elder"]).is_equal(0)

func test_dragon_drops_only_minor_souls() -> void:
	var w := _spawn("dragon", "blue")
	w.take_damage(w.max_hp + 100)
	await get_tree().process_frame
	var counts := _count_pickups_in_scene()
	assert_int(counts["minor"]).is_between(1, 2)
	assert_int(counts["elder"]).is_equal(0)

func test_elder_drops_only_elder_pickup() -> void:
	var w := _spawn("elder", "purple")
	w.take_damage(w.max_hp + 100)
	await get_tree().process_frame
	var counts := _count_pickups_in_scene()
	assert_int(counts["minor"]).is_equal(0)
	assert_int(counts["elder"]).is_equal(1)
