extends Control
## Assembles the interface and owns the keyboard.
##
## Everything here is layout and routing; the simulation is in the Game
## autoload and the drawing is in StreetView, so this file stays a wiring
## diagram.

const StreetViewScript := preload("res://scripts/StreetView.gd")
const ShopPanelScript := preload("res://scripts/ui/ShopPanel.gd")
const LegacyTreeScript := preload("res://scripts/ui/LegacyTree.gd")
const OverlayScript := preload("res://scripts/ui/Overlay.gd")
const AutoplayScript := preload("res://scripts/Autoplay.gd")

const DRAWER_W := 384
const MARGIN := 14

var street: Control
var shop: Control
var tree_panel: Control
var overlay: Control
var tip: Tooltip
var _btn_shop: Button
var _btn_tree: Button
var _btn_cash: Button
var _shop_open := true
var _last_gain := -1

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

## The street is the window. Everything else floats on top of it and is
## summoned by a button, which is the difference between a game and a
## dashboard with a picture in one of its panes.
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Pal.VOID
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	street = StreetViewScript.new()
	street.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(street)

	# The button cluster. A full-width row that ignores the mouse itself, so
	# only the buttons take clicks and the rest of the strip is still street.
	var row := UiKit.hbox(8)
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	row.offset_left = MARGIN
	row.offset_right = -MARGIN
	row.offset_top = MARGIN
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	_btn_cash = UiKit.button("CASH OUT", Pal.GOLD, 13, true)
	_btn_cash.pressed.connect(_ask_cash_out)
	_btn_cash.visible = false
	row.add_child(_btn_cash)

	_btn_tree = UiKit.button("TREE  [L]", Pal.MAUVE, 13)
	_btn_tree.pressed.connect(func() -> void: tree_panel.show_tree())
	row.add_child(_btn_tree)

	_btn_shop = UiKit.button("SHOP  [S]", Pal.CASH, 13)
	_btn_shop.pressed.connect(func() -> void: toggle_shop())
	row.add_child(_btn_shop)

	var menu := UiKit.button("MENU", Pal.LINE, 13)
	menu.pressed.connect(func() -> void: overlay.menu())
	row.add_child(menu)

	# The drawer, anchored to the right edge and clear of the buttons.
	shop = ShopPanelScript.new()
	shop.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	shop.offset_left = -(DRAWER_W + MARGIN)
	shop.offset_right = -MARGIN
	shop.offset_top = MARGIN + 46
	shop.offset_bottom = -MARGIN
	add_child(shop)
	shop.closed.connect(func() -> void: toggle_shop(false))
	street.right_inset = float(DRAWER_W + MARGIN * 2)

	# Overlays, in the order they stack.
	tree_panel = LegacyTreeScript.new()
	add_child(tree_panel)
	overlay = OverlayScript.new()
	add_child(overlay)
	# The tooltip is built last so it paints over every panel that can raise it.
	tip = Tooltip.new()
	add_child(tip)

## Slides the scene over rather than just hiding a box, so the HQ stays in the
## middle of whatever space is actually left.
func toggle_shop(force = null) -> void:
	var want: bool = (not _shop_open) if force == null else bool(force)
	if want == _shop_open:
		return
	_shop_open = want
	SFX.play("tab", 1.0, -14.0)
	shop.visible = true
	var inset := float(DRAWER_W + MARGIN * 2) if want else 0.0
	var tw := create_tween().set_parallel(true)
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(shop, "modulate:a", 1.0 if want else 0.0, 0.18)
	tw.tween_property(street, "right_inset", inset, 0.22)
	if not want:
		tw.chain().tween_callback(func() -> void:
			if not _shop_open:
				shop.visible = false)

func _ask_cash_out() -> void:
	if Game.can_cash_out():
		overlay.confirm_cash_out()

## The buttons carry the state the old top bar used to: how many upgrades are
## affordable, whether a perk is waiting, whether Cash Out is worth anything.
func _process(_dt: float) -> void:
	var gain := Game.legacy_gain()
	_btn_cash.visible = gain > 0
	_btn_cash.text = "CASH OUT  +%d" % gain
	if gain != _last_gain:
		if gain > 0 and _last_gain <= 0:
			UiKit.attention(_btn_cash)
		_last_gain = gain

	var afford := 0
	for u in Game.available_upgrades():
		if Game.cash >= Game.upgrade_cost(u):
			afford += 1
	_btn_shop.text = "SHOP  [S]" + ("   %d" % afford if afford > 0 else "")
	_btn_tree.text = "TREE  [L]" + ("   *" if _tree_waiting() else "")

func _tree_waiting() -> bool:
	if Game.legacy <= 0:
		return false
	for n in Balance.TREE:
		if Game.node_can_buy(n["id"]):
			return true
	return false

func _wire() -> void:
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
			elif _shop_open:
				toggle_shop(false)
			else:
				overlay.menu()
		KEY_L:
			if tree_panel.visible:
				tree_panel.hide_tree()
			elif not overlay.is_open():
				tree_panel.show_tree()
		KEY_SPACE:
			if not tree_panel.visible and not overlay.is_open():
				street.tap_from_key()
		KEY_S:
			toggle_shop()
		KEY_1:
			toggle_shop(true)
			shop.select_tab("buy")
		KEY_2:
			toggle_shop(true)
			shop.select_tab("upgrades")
		KEY_3:
			toggle_shop(true)
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
	if _has_flag("--drawer-closed"):
		_shop_open = false
		shop.visible = false
		street.right_inset = 0.0
	var deal := _flag("--deal")
	if deal != "":
		Game._open_deal()
		Game.deal_zone = 0.52
		Game.deal_t = float(deal)
		Game.combo = int(_flag("--combo")) if _flag("--combo") != "" else 0
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
	street.clear_effects()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path)
	get_tree().quit()
