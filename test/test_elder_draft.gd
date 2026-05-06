extends GdUnitTestSuite

const DraftScene: PackedScene = preload("res://scenes/ui/elder_draft.tscn")

var draft: CanvasLayer
var player: CharacterBody3D

func before_test() -> void:
	player = auto_free(load("res://scenes/entities/player.tscn").instantiate())
	add_child(player)
	await get_tree().process_frame
	player.get_node("SkillSystem").start_default_wand("red")
	draft = auto_free(DraftScene.instantiate())
	add_child(draft)
	await get_tree().process_frame

func test_show_draft_displays_three_cards_for_red() -> void:
	draft.show_draft("red", player.get_node("SkillSystem"))
	await get_tree().process_frame
	var cards: int = draft.get_visible_card_count()
	assert_int(cards).is_between(1, 3)

func test_picking_card_applies_to_active_wand() -> void:
	var ss: SkillSystem = player.get_node("SkillSystem")
	draft.show_draft("red", ss)
	await get_tree().process_frame
	# Click the first card.
	draft.pick_card(0)
	await get_tree().process_frame
	assert_int(ss.active_skill().elder_modifier_count()).is_equal(1)
	assert_bool(draft.visible).is_false()

func test_draft_pauses_physics_while_visible() -> void:
	draft.show_draft("blue", player.get_node("SkillSystem"))
	await get_tree().process_frame
	assert_bool(get_tree().paused).is_true()
	draft.pick_card(0)
	await get_tree().process_frame
	assert_bool(get_tree().paused).is_false()
