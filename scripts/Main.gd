extends Control
## Assembles the interface and owns the keyboard.
##
## Everything here is layout and routing; the simulation is in the Game
## autoload and the drawing is in StreetView, so this file stays a wiring
## diagram.

const StreetViewScript := preload("res://scripts/StreetView.gd")
const TopBarScript := preload("res://scripts/ui/TopBar.gd")
const ShopPanelScript := preload("res://scripts/ui/ShopPanel.gd")
const LegacyTreeScript := preload("res://scripts/ui/LegacyTree.gd")
const OverlayScript := preload("res://scripts/ui/Overlay.gd")
const AutoplayScript := preload("res://scripts/Autoplay.gd")

const RIGHT_WIDTH := 392

var street: Control
var top: Control
var shop: Control
var tree_panel: Control
var overlay: Control
var tip: Tooltip

func _ready() -> void:
	# The bot never builds an interface; it drives Game directly and quits.
	var bot_hours := _autoplay_hours()
	if bot_hours > 0.0:
		set_process(false)
		_run_bot(bot_hours)
		return
	if _has_flag("--roundtrip"):
		set_process(false)
		_roundtrip()
		return

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_wire()

	# Screenshot mode is for checking layout without sitting through a run:
	#   Godot.exe --path . -- --shot out.png [--cash N] [--earned N] [--shop N] [--level N]
	#       [--tree] [--tab upgrades|stats] [--dialog cashout|menu|away|wipe] [--vip] [--rush] [--time S]
	var shot := _flag("--shot")
	if shot != "":
		_capture(shot)
		return

	if not Game.offline_report.is_empty():
		var r: Dictionary = Game.offline_report
		Game.offline_report = {}
		if float(r["cash"]) > 0.0:
			overlay.away(float(r["cash"]), float(r["secs"]))

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Pal.VOID
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)

	var col := UiKit.vbox(10)
	margin.add_child(col)

	top = TopBarScript.new()
	col.add_child(top)

	var row := UiKit.hbox(10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)

	var frame := UiKit.panel(Pal.PANEL, Pal.LINE, 0)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	street = StreetViewScript.new()
	street.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	street.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(street)
	row.add_child(frame)

	shop = ShopPanelScript.new()
	shop.custom_minimum_size = Vector2(RIGHT_WIDTH, 0)
	shop.size_flags_horizontal = Control.SIZE_SHRINK_END
	shop.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(shop)

	# Overlays, in the order they stack.
	tree_panel = LegacyTreeScript.new()
	add_child(tree_panel)
	overlay = OverlayScript.new()
	add_child(overlay)
	# The tooltip is built last so it paints over every panel that can raise it.
	tip = Tooltip.new()
	add_child(tip)

func _wire() -> void:
	top.open_tree.connect(func() -> void: tree_panel.show_tree())
	top.cash_out_requested.connect(func() -> void:
		if Game.can_cash_out():
			overlay.confirm_cash_out())
	top.open_menu.connect(func() -> void: overlay.menu())
	overlay.cash_out_confirmed.connect(func() -> void:
		var gain := Game.cash_out()
		SFX.play("cashout", 1.0, -2.0)
		SFX.play("legacy", 1.0, -6.0)
		overlay.toast("Cashed out for +%d legacy - level %d" % [gain, Game.legacy_level], Pal.GOLD, 4.5)
		tree_panel.show_tree())
	overlay.wipe_confirmed.connect(func() -> void:
		Game.wipe_save()
		overlay.toast("Wiped. Fresh start.", Pal.DANGER))
	Game.vip_spawned.connect(func() -> void: overlay.toast("A VIP is on the street!", Pal.GOLD, 2.5))
	Game.vip_resolved.connect(func(kind: String, amount: float) -> void:
		if kind == "rush":
			overlay.toast("Rush Hour - x%d income for %ds" % [int(amount), int(Balance.RUSH_DURATION * Game.tree_mult("rush_len"))], Pal.GOLD)
		else:
			overlay.toast("Windfall - " + Fmt.cash(amount), Pal.GOLD))
	Game.vip_missed.connect(func() -> void: overlay.toast("The VIP walked off.", Pal.DIM, 2.0))
	Game.node_bought.connect(func(id: String) -> void:
		overlay.toast("Perk: " + String(Balance.node(id)["name"]), Pal.MAUVE))
	Game.tree_completed.connect(func() -> void:
		SFX.play("legacy", 1.0, -2.0)
		overlay.tree_complete())
	Game.upgrade_bought.connect(func(id: String) -> void:
		overlay.toast(String(Balance.upgrade_by_id[id]["name"]), Pal.AMBER, 2.0))

func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not (ev as InputEventKey).pressed or (ev as InputEventKey).echo:
		return
	var k := (ev as InputEventKey).keycode
	match k:
		KEY_ESCAPE:
			if overlay.is_open():
				overlay.close()
			elif tree_panel.visible:
				tree_panel.hide_tree()
			else:
				overlay.menu()
		KEY_L:
			if tree_panel.visible:
				tree_panel.hide_tree()
			elif not overlay.is_open():
				tree_panel.show_tree()
		KEY_SPACE:
			if not tree_panel.visible and not overlay.is_open():
				street.sell_from_key()
		KEY_B:
			shop.select_tab("buy")
		KEY_U:
			shop.select_tab("upgrades")
		KEY_S:
			shop.select_tab("stats")
		KEY_TAB:
			shop.cycle_mult()
		KEY_M:
			SFX.muted = not SFX.muted
			overlay.toast("Muted" if SFX.muted else "Sound on", Pal.DIM, 1.5)
		_:
			return
	get_viewport().set_input_as_handled()

# ------------------------------------------------------------ flags

func _flag(name: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]
	return ""

func _has_flag(name: String) -> bool:
	return OS.get_cmdline_user_args().has(name)

func _autoplay_hours() -> float:
	var v := _flag("--autoplay")
	return float(v) if v != "" else (6.0 if _has_flag("--autoplay") else 0.0)

func _run_bot(hours: float) -> void:
	var bot = AutoplayScript.new()
	bot.run(hours)
	get_tree().quit()

## Save, wipe, load, compare. Run headless after touching persistence:
##   Godot.exe --headless --path . -- --roundtrip
func _roundtrip() -> void:
	Game.save_enabled = false
	Game.set_process(false)
	Game.hard_reset()
	Game.cash = 12345.0
	Game.count["lemonade"] = 7
	Game.count["cart"] = 2
	Game.owned["lemonade_0"] = true
	Game.owned["click_handshake"] = true
	Game.earned_run = 5.0e5
	Game.earned_all = 3.0e9
	Game.legacy_level = 40
	Game.legacy = 9
	Game.tree["lean"] = true
	Game.tree["seed"] = true
	Game.runs = 3
	Game.best_run = 2.0e9
	Game.clicks_all = 1234
	Game.play_time = 4321.0
	Game._dirty = true
	var before := _snapshot()
	Game.save_path_override = "user://mogul_roundtrip.json"
	Game.save_enabled = true
	Game.save_game()
	Game.hard_reset()
	var ok := Game.load_game()
	var after := _snapshot()
	var passed := ok
	for k in before:
		var same: bool = before[k] == after[k]
		if k == "cash":
			# Away earnings can land on cash during load; a drop is a fault.
			same = float(after[k]) >= float(before[k])
		print("%-7s %s  %s -> %s" % [k, "ok " if same else "BAD", str(before[k]), str(after[k])])
		passed = passed and same
	print("roundtrip " + ("PASS" if passed else "FAIL"))
	Game.wipe_save()
	get_tree().quit(0 if passed else 1)

func _snapshot() -> Dictionary:
	return {"cash": Game.cash, "income": Game.base_income(), "click": Game.click_value(),
		"gain": Game.legacy_gain(), "count": Game.count.duplicate(), "owned": Game.owned.keys(),
		"tree": Game.tree.keys(), "level": Game.legacy_level, "legacy": Game.legacy,
		"runs": Game.runs, "best": Game.best_run, "clicks": Game.clicks_all}

## Saves a frame to disk and quits. State can be staged with flags so a
## late-game screen can be checked without playing to it.
func _capture(path: String) -> void:
	Game.save_enabled = false
	Game.set_process(false)
	Game.hard_reset()
	var earned := _flag("--earned")
	if earned != "":
		Game.earned_run = float(earned)
		Game.earned_all = float(earned)
	var level := _flag("--level")
	if level != "":
		Game.legacy_level = int(level)
		Game.legacy = int(level)
	var shop_n := _flag("--shop")
	if shop_n != "":
		# Buy N of every producer, cheapest first, with money conjured for it.
		for i in range(Balance.PRODUCERS.size()):
			var id := String(Balance.PRODUCERS[i][0])
			var n := int(shop_n) - i * 3
			if n > 0:
				Game.cash = Game.cost_of(id, n)
				Game.buy_producer(id, n)
	var cash := _flag("--cash")
	if cash != "":
		Game.cash = float(cash)
	if _has_flag("--tree"):
		tree_panel.show_tree()
	var tab := _flag("--tab")
	if tab != "":
		shop.select_tab(tab)
	match _flag("--dialog"):
		"cashout":
			overlay.confirm_cash_out()
		"menu":
			overlay.menu()
		"away":
			overlay.away(12345.0, 5400.0)
		"wipe":
			overlay.confirm_wipe()
		"complete":
			overlay.tree_complete()
	if _has_flag("--toast"):
		overlay.toast("A VIP is on the street!", Pal.GOLD)
		overlay.toast("Perk: Lean Operations", Pal.MAUVE)
	if _has_flag("--vip"):
		Game._spawn_vip()
		Game.vip_t = Game.vip_life * 0.4
	if _has_flag("--rush"):
		Game.rush_left = 20.0
	Game.play_time = float(_flag("--time")) if _flag("--time") != "" else 0.0
	street.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path)
	get_tree().quit()
