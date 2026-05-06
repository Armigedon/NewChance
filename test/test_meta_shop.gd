extends GdUnitTestSuite

func before_test() -> void:
	MetaShop.reset_for_test()

func test_starts_with_zero_currency() -> void:
	assert_int(MetaShop.minor_souls()).is_equal(0)
	assert_int(MetaShop.elder_currency()).is_equal(0)

func test_credit_minor_souls_adds() -> void:
	MetaShop.credit_minor_souls(15)
	assert_int(MetaShop.minor_souls()).is_equal(15)

func test_credit_elder_currency_adds() -> void:
	MetaShop.credit_elder_currency(3)
	assert_int(MetaShop.elder_currency()).is_equal(3)

func test_buy_stat_rank_consumes_minor_souls() -> void:
	MetaShop.credit_minor_souls(20)
	var ok: bool = MetaShop.buy_stat_rank("vitality")
	assert_bool(ok).is_true()
	assert_int(MetaShop.stat_rank("vitality")).is_equal(1)
	# Rank 1 cost is 5; remaining = 15.
	assert_int(MetaShop.minor_souls()).is_equal(15)

func test_buy_stat_rank_fails_when_insufficient_currency() -> void:
	MetaShop.credit_minor_souls(2)  # not enough for rank 1 (cost 5)
	var ok: bool = MetaShop.buy_stat_rank("vitality")
	assert_bool(ok).is_false()
	assert_int(MetaShop.stat_rank("vitality")).is_equal(0)

func test_buy_stat_rank_caps_at_5() -> void:
	MetaShop.credit_minor_souls(10000)
	for i in range(5):
		MetaShop.buy_stat_rank("vitality")
	# 6th attempt should fail.
	var ok: bool = MetaShop.buy_stat_rank("vitality")
	assert_bool(ok).is_false()
	assert_int(MetaShop.stat_rank("vitality")).is_equal(5)

func test_buy_structural_unlock_consumes_elder_currency() -> void:
	MetaShop.credit_elder_currency(10)
	var ok: bool = MetaShop.buy_structural("wand_choice")
	assert_bool(ok).is_true()
	assert_bool(MetaShop.has_structural("wand_choice")).is_true()
	# Wand Choice cost: 3.
	assert_int(MetaShop.elder_currency()).is_equal(7)

func test_buy_structural_unlock_fails_when_already_owned() -> void:
	MetaShop.credit_elder_currency(20)
	MetaShop.buy_structural("wand_choice")
	var ok: bool = MetaShop.buy_structural("wand_choice")
	assert_bool(ok).is_false()

func test_starting_wand_color_default_red() -> void:
	# Without Wand Choice unlocked, always red.
	assert_str(MetaShop.starting_wand_color()).is_equal("red")

func test_starting_wand_color_after_unlock() -> void:
	MetaShop.credit_elder_currency(10)
	MetaShop.buy_structural("wand_choice")
	MetaShop.set_chosen_wand_color("blue")
	assert_str(MetaShop.starting_wand_color()).is_equal("blue")
