extends Control
## Dialogs and toasts. One backdrop, one card that is rebuilt per dialog,
## and a stack of short-lived notices along the bottom of the screen.

signal cash_out_confirmed()
signal wipe_confirmed()

var _backdrop: ColorRect
var _card: PanelContainer
var _body: VBoxContainer
var _toasts: VBoxContainer
var _open := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 150

	_backdrop = ColorRect.new()
	_backdrop.color = Color(Pal.VOID, 0.72)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.visible = false
	_backdrop.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and _open != "wipe":
			close())
	add_child(_backdrop)

	_card = UiKit.panel(Pal.PANEL, Pal.LINE, 18)
	_card.custom_minimum_size = Vector2(470, 0)
	_card.set_anchors_preset(Control.PRESET_CENTER)
	_card.visible = false
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_body = UiKit.vbox(10)
	_card.add_child(_body)
	add_child(_card)

	_toasts = UiKit.vbox(6)
	_toasts.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	add_child(_toasts)

func _process(_dt: float) -> void:
	if _card.visible:
		_card.position = (size - _card.size) * 0.5
	_toasts.position = Vector2(size.x * 0.5 - _toasts.size.x * 0.5, size.y - _toasts.size.y - 26.0)

func is_open() -> bool:
	return _open != ""

func close() -> void:
	_open = ""
	_backdrop.visible = false
	_card.visible = false
	for c in _body.get_children():
		c.queue_free()

func _show(kind: String, title: String, accent: Color) -> void:
	close()
	_open = kind
	_card.add_theme_stylebox_override("panel", UiKit.stylebox(Pal.PANEL, accent.darkened(0.35), 8, 1, 18))
	_body.add_child(UiKit.label(title, 20, accent))
	_backdrop.visible = true
	_card.visible = true
	_card.reset_size()

func _buttons(pairs: Array) -> void:
	_body.add_child(UiKit.hsep(4))
	var h := UiKit.hbox(8)
	h.alignment = BoxContainer.ALIGNMENT_END
	for p in pairs:
		var b := UiKit.button(String(p[0]), p[1], 13, bool(p[3]) if p.size() > 3 else false)
		b.pressed.connect(p[2])
		h.add_child(b)
	_body.add_child(h)

# ------------------------------------------------------------ dialogs

func confirm_cash_out() -> void:
	var gain := Game.legacy_gain()
	_show("cashout", "Sell the company?", Pal.GOLD)
	var r := UiKit.rich("You walk away with [b]+%d legacy[/b], landing at level [b]%d[/b] (+%s income, forever) with [b]%d[/b] points to spend in the tree.\n\nCash, businesses and upgrades are gone. Lifetime earnings, legacy and perks stay." % [
		gain, Game.legacy_level + gain,
		Fmt.pct_whole(float(Game.legacy_level + gain) * Balance.LEVEL_BONUS * Game.tree_mult("level_bonus_mult")),
		Game.legacy + gain], 13, Pal.INK)
	_body.add_child(r)
	var starts := PackedStringArray()
	var sc := Game.tree_sum("start_cash") + Game.best_run * Game.tree_sum("start_best_pct")
	if sc > 0.0:
		starts.append("start with " + Fmt.cash(maxf(sc, Game.earned_run * Game.tree_sum("start_best_pct"))))
	if Game.tree_has("contacts"):
		starts.append("10 Lemonade Stands and 5 Paper Routes")
	if not starts.is_empty():
		_body.add_child(_wrapped("Head start: " + ", ".join(starts) + ".", Pal.STEEL))
	_buttons([
		["KEEP GOING", Pal.LINE, func() -> void: close()],
		["CASH OUT", Pal.GOLD, func() -> void:
			close()
			cash_out_confirmed.emit(), true],
	])

func away(cash: float, secs: float) -> void:
	_show("away", "While you were away", Pal.CASH)
	var rate := Game.tree_max("offline_rate", Balance.OFFLINE_RATE)
	var cap := Game.tree_max("offline_cap", Balance.OFFLINE_CAP)
	var r := UiKit.rich("Gone [b]%s[/b]. The businesses ran at %s for up to %s and banked [b]%s[/b]." % [
		Fmt.time(secs), Fmt.pct(rate), Fmt.time(cap), Fmt.cash(cash)], 13, Pal.INK)
	_body.add_child(r)
	if not Game.tree_has("nightshift"):
		_body.add_child(_wrapped("Night Shift, in the Legacy tree, raises both.", Pal.DIM))
	_buttons([["BACK TO WORK", Pal.CASH, func() -> void: close()]])

func menu() -> void:
	_show("menu", "MOGUL", Pal.INK)
	_body.add_child(_wrapped("Click the HQ to sell. Buy businesses on the right. Catch the gold VIP. Cash out for legacy, spend it in the tree, go again.", Pal.DIM))
	var keys := UiKit.rich("[b]SPACE[/b] sell    [b]L[/b] legacy tree    [b]B / U / S[/b] shop tabs\n[b]TAB[/b] buy amount    [b]M[/b] mute    [b]ESC[/b] this menu", 12, Pal.DIM)
	_body.add_child(keys)
	_body.add_child(UiKit.hsep(2))
	var mute := UiKit.button("UNMUTE" if SFX.muted else "MUTE", Pal.STEEL, 13)
	mute.pressed.connect(func() -> void:
		SFX.muted = not SFX.muted
		mute.text = "UNMUTE" if SFX.muted else "MUTE")
	var save := UiKit.button("SAVE NOW", Pal.CASH, 13)
	save.pressed.connect(func() -> void:
		Game.save_game()
		toast("Saved.", Pal.CASH))
	var wipe := UiKit.button("WIPE SAVE", Pal.DANGER, 13)
	wipe.pressed.connect(func() -> void: confirm_wipe())
	var h := UiKit.hbox(8)
	h.add_child(mute)
	h.add_child(save)
	h.add_child(wipe)
	_body.add_child(h)
	_buttons([["CLOSE", Pal.LINE, func() -> void: close()]])

func confirm_wipe() -> void:
	_show("wipe", "Wipe everything?", Pal.DANGER)
	_body.add_child(_wrapped("Legacy, perks, lifetime stats - all of it. There is no undo.", Pal.INK, 13))
	_buttons([
		["KEEP IT", Pal.LINE, func() -> void: close()],
		["WIPE", Pal.DANGER, func() -> void:
			close()
			wipe_confirmed.emit()],
	])

func tree_complete() -> void:
	_show("complete", "Every perk. Every spoke.", Pal.GOLD)
	_body.add_child(UiKit.rich("The tree is finished at level [b]%d[/b], after [b]%d[/b] cash outs and [b]%s[/b] of play. The company is a monument now.\n\nThe street keeps running and legacy keeps paying, so nothing is stopping you. But you did the thing." % [
		Game.legacy_level, Game.runs, Fmt.time(Game.play_time)], 13, Pal.INK))
	_buttons([["KEEP BUILDING", Pal.GOLD, func() -> void: close()]])

func _wrapped(text: String, color: Color, size: int = 12) -> Label:
	var l := UiKit.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

# ------------------------------------------------------------ toasts

func toast(text: String, accent: Color = Pal.INK, seconds: float = 3.2) -> void:
	var p := UiKit.panel(Pal.PANEL.darkened(0.1), accent.darkened(0.3), 10)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label(text, 13, accent)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	_toasts.add_child(p)
	while _toasts.get_child_count() > 4:
		_toasts.get_child(0).free()
	var tw := p.create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)
