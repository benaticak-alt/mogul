extends PanelContainer
## The strip across the top: the bank, the rate, legacy, and the three
## buttons that leave the main screen.

signal open_tree()
signal cash_out_requested()
signal open_menu()

var _cash: Label
var _rate: Label
var _click: Label
var _legacy_line: Label
var _points: Label
var _next: Label
var _next_bar: ProgressBar
var _cash_out_btn: Button
var _tree_btn: Button
var _last_gain := -1

func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.stylebox(Pal.PANEL, Pal.LINE, 6, 1, 14))
	var row := UiKit.hbox(18)
	add_child(row)

	# Bank.
	var bank := UiKit.vbox(0)
	bank.custom_minimum_size = Vector2(300, 0)
	bank.add_child(UiKit.header("CASH", Pal.CASH))
	_cash = UiKit.label("$0", 30, Pal.INK)
	bank.add_child(_cash)
	var sub := UiKit.hbox(12)
	_rate = UiKit.label("$0/s", 13, Pal.CASH)
	_click = UiKit.label("$1 per sale", 13, Pal.AMBER)
	sub.add_child(_rate)
	sub.add_child(_click)
	bank.add_child(sub)
	row.add_child(bank)
	Tooltip.attach(bank, _bank_tip)

	row.add_child(_vrule())

	# Legacy.
	var leg := UiKit.vbox(2)
	leg.custom_minimum_size = Vector2(290, 0)
	leg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	leg.add_child(UiKit.header("LEGACY", Pal.GOLD))
	_legacy_line = UiKit.label("Level 0", 15, Pal.INK)
	leg.add_child(_legacy_line)
	_points = UiKit.label("", 12, Pal.GOLD)
	leg.add_child(_points)
	_next = UiKit.label("", 11, Pal.DIM)
	leg.add_child(_next)
	_next_bar = UiKit.bar(5, Pal.GOLD)
	leg.add_child(_next_bar)
	row.add_child(leg)
	Tooltip.attach(leg, _legacy_tip)

	row.add_child(UiKit.spacer())

	# Actions.
	var actions := UiKit.hbox(8)
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tree_btn = UiKit.button("LEGACY TREE  [L]", Pal.MAUVE, 13)
	_tree_btn.pressed.connect(func() -> void: open_tree.emit())
	actions.add_child(_tree_btn)
	_cash_out_btn = UiKit.button("CASH OUT", Pal.GOLD, 13, true)
	_cash_out_btn.pressed.connect(func() -> void: cash_out_requested.emit())
	actions.add_child(_cash_out_btn)
	Tooltip.attach(_cash_out_btn, _cash_out_tip)
	var menu := UiKit.flat_button("MENU  [ESC]", 12)
	menu.pressed.connect(func() -> void: open_menu.emit())
	actions.add_child(menu)
	row.add_child(actions)

func _vrule() -> Control:
	var c := ColorRect.new()
	c.color = Pal.LINE
	c.custom_minimum_size = Vector2(1, 0)
	c.size_flags_vertical = Control.SIZE_FILL
	return c

func _process(_dt: float) -> void:
	_cash.text = Fmt.cash(Game.cash)
	var inc := Game.income()
	if Game.rush_left > 0.0:
		_rate.text = "%s  RUSH x%d" % [Fmt.per_sec(inc), int(Game.rush_mult())]
		_rate.add_theme_color_override("font_color", Pal.GOLD)
	else:
		_rate.text = Fmt.per_sec(inc)
		_rate.add_theme_color_override("font_color", Pal.CASH)
	_click.text = "%s per sale" % Fmt.cash(Game.click_value())

	var bonus := float(Game.legacy_level) * Balance.LEVEL_BONUS * Game.tree_mult("level_bonus_mult")
	_legacy_line.text = "Level %d   +%s income" % [Game.legacy_level, Fmt.pct_whole(bonus)]
	_points.text = "%d to spend" % Game.legacy if Game.legacy > 0 else "nothing to spend"
	_points.add_theme_color_override("font_color", Pal.GOLD if Game.legacy > 0 else Pal.FAINT)

	var gain := Game.legacy_gain()
	var nxt := Game.next_legacy_at()
	if gain > 0:
		_next.text = "Cash out now for +%d legacy" % gain
		_next.add_theme_color_override("font_color", Pal.GOLD)
	else:
		_next.text = "next point at %s lifetime" % Fmt.cash(nxt)
		_next.add_theme_color_override("font_color", Pal.DIM)
	# Progress toward the next point, on the square-root curve so the bar
	# moves at a steady visual pace.
	var lo := pow(float(Game.legacy_level) / (1.0 + Game.tree_sum("legacy_bonus")), 1.0 / Balance.LEGACY_POWER) * Balance.LEGACY_BASE
	_next_bar.value = clampf((Game.earned_all - lo) / maxf(1.0, nxt - lo), 0.0, 1.0) if gain == 0 else 1.0

	_cash_out_btn.text = "CASH OUT  +%d" % gain if gain > 0 else "CASH OUT"
	_cash_out_btn.disabled = gain <= 0
	if gain != _last_gain:
		if gain > 0 and _last_gain <= 0:
			UiKit.attention(_cash_out_btn)
		_last_gain = gain
	_tree_btn.text = "LEGACY TREE  [L]" + ("  *" if _tree_has_buyable() else "")

func _tree_has_buyable() -> bool:
	if Game.legacy <= 0:
		return false
	for n in Balance.TREE:
		if Game.node_can_buy(n["id"]):
			return true
	return false

func _bank_tip() -> Dictionary:
	var lines := PackedStringArray()
	lines.append("Earned this run: [b]%s[/b]" % Fmt.cash(Game.earned_run))
	lines.append("Earned all time: [b]%s[/b]" % Fmt.cash(Game.earned_all))
	lines.append("Global multiplier: [b]%s[/b]" % Fmt.mult(Game.global_mult()))
	var ac := Game.tree_max("autoclick")
	if ac > 0.0:
		lines.append("Auto-sales: [b]%d/s[/b]" % int(ac))
	return {"title": "The books", "accent": Pal.CASH, "body": "\n".join(lines),
		"foot": "Run %d  -  %s in" % [Game.runs + 1, Fmt.time(Game.run_time)]}

func _legacy_tip() -> Dictionary:
	return {"title": "Legacy", "accent": Pal.GOLD,
		"body": "Cash Out sells the company. Cash, businesses and upgrades go; you keep [b]legacy[/b], cut from lifetime earnings on a square-root curve.\n\nEvery level is [b]+%s income[/b] forever. Points are spent in the tree." % Fmt.pct_whole(Balance.LEVEL_BONUS * Game.tree_mult("level_bonus_mult")),
		"foot": "%d of %d perks owned." % [Game.tree_progress().x, Game.tree_progress().y]}

func _cash_out_tip() -> Dictionary:
	var gain := Game.legacy_gain()
	if gain <= 0:
		return {"title": "Cash Out", "accent": Pal.GOLD,
			"body": "Not yet. The next legacy point lands at [b]%s[/b] lifetime earnings." % Fmt.cash(Game.next_legacy_at())}
	return {"title": "Cash Out for +%d legacy" % gain, "accent": Pal.GOLD,
		"body": "Sells everything and starts over at level [b]%d[/b], with [b]%d[/b] points to spend in the tree." % [Game.legacy_level + gain, Game.legacy + gain],
		"foot": "Waiting longer earns more, but slower - the curve is a square root."}
