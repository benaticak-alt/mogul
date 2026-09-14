extends PanelContainer
## The right-hand column: BUY, UPGRADES and STATS tabs.
##
## Rows are built once and their labels rewritten every frame; the upgrade
## list is rebuilt only when the set of available upgrades changes, since
## that is the one list that comes and goes.

const TAB_ACCENT := {"buy": Pal.CASH, "upgrades": Pal.AMBER, "stats": Pal.STEEL}

var _tab := "buy"
var _mult := 1                         ## 1, 10, 100 or 0 for max
var _tabs: Dictionary = {}
var _mult_btns: Dictionary = {}
var _mult_row: HBoxContainer
var _pages: Dictionary = {}
var _rows: Array = []                  ## per producer: {row, name, sub, count, cost}
var _teaser: Dictionary = {}
var _upg_box: VBoxContainer
var _upg_sig := ""
var _upg_rows: Dictionary = {}          ## id -> {row, cost}
var _upg_empty: Label
var _stats: Dictionary = {}

func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.stylebox(Pal.PANEL, Pal.LINE, 6, 1, 10))
	var v := UiKit.vbox(8)
	add_child(v)

	var tabs := UiKit.hbox(4)
	for id in ["buy", "upgrades", "stats"]:
		var b := UiKit.flat_button(id.to_upper(), 12)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_select_tab.bind(id))
		tabs.add_child(b)
		_tabs[id] = b
	v.add_child(tabs)

	_mult_row = UiKit.hbox(4)
	var lbl := UiKit.label("BUY", 11, Pal.DIM)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mult_row.add_child(lbl)
	for m in [1, 10, 100, 0]:
		var b := UiKit.flat_button("MAX" if m == 0 else "x%d" % m, 12)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_set_mult.bind(m))
		_mult_row.add_child(b)
		_mult_btns[m] = b
	v.add_child(_mult_row)

	var stack := VBoxContainer.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := UiKit.scroll(stack)
	v.add_child(scroll)

	_pages["buy"] = _build_buy()
	_pages["upgrades"] = _build_upgrades()
	_pages["stats"] = _build_stats()
	for p in _pages.values():
		stack.add_child(p)
	_select_tab("buy")
	_set_mult(1)

# ------------------------------------------------------------ tabs

func _select_tab(id: String) -> void:
	_tab = id
	for k in _tabs:
		UiKit.set_tab_selected(_tabs[k], k == id, TAB_ACCENT[k])
	for k in _pages:
		(_pages[k] as Control).visible = k == id
	_mult_row.visible = id == "buy"
	SFX.play("tab", 1.0, -16.0)

func select_tab(id: String) -> void:
	if _tab != id:
		_select_tab(id)

func _set_mult(m: int) -> void:
	_mult = m
	for k in _mult_btns:
		UiKit.set_tab_selected(_mult_btns[k], k == m, Pal.CASH)

func set_mult(m: int) -> void:
	_set_mult(m)

func cycle_mult() -> void:
	var order := [1, 10, 100, 0]
	_set_mult(order[(order.find(_mult) + 1) % order.size()])

# ------------------------------------------------------------ buy page

func _build_buy() -> VBoxContainer:
	var page := UiKit.vbox(5)
	for i in range(Balance.PRODUCERS.size()):
		var p: Array = Balance.PRODUCERS[i]
		var id := String(p[0])
		var row := UiKit.panel(Pal.PANEL_2, Pal.LINE, 9)
		UiKit.clickable(row, Pal.producer(i))
		var h := UiKit.hbox(9)
		var sw := UiKit.swatch(Pal.producer(i), 12)
		h.add_child(sw)
		var mid := UiKit.vbox(1)
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name := UiKit.label(String(p[1]), 14, Pal.INK)
		var sub := UiKit.label("", 11, Pal.DIM)
		mid.add_child(name)
		mid.add_child(sub)
		h.add_child(mid)
		var right := UiKit.vbox(0)
		right.alignment = BoxContainer.ALIGNMENT_CENTER
		var cnt := UiKit.label("0", 20, Pal.INK)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var cost := UiKit.label("", 12, Pal.CASH)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(cnt)
		right.add_child(cost)
		h.add_child(right)
		row.add_child(h)
		UiKit.passthrough(h)
		row.connect("pressed", _buy_producer.bind(id))
		Tooltip.attach(row, _producer_tip.bind(i))
		page.add_child(row)
		_rows.append({"row": row, "name": name, "sub": sub, "count": cnt, "cost": cost, "id": id})
	# The locked teaser under the last visible producer.
	var t := UiKit.panel(Pal.PANEL.darkened(0.2), Pal.LINE.darkened(0.3), 9)
	var th := UiKit.hbox(9)
	th.add_child(UiKit.swatch(Pal.FAINT, 12))
	var tm := UiKit.vbox(1)
	tm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tn := UiKit.label("???", 14, Pal.FAINT)
	var ts := UiKit.label("", 11, Pal.FAINT)
	tm.add_child(tn)
	tm.add_child(ts)
	th.add_child(tm)
	t.add_child(th)
	page.add_child(t)
	_teaser = {"row": t, "sub": ts}
	return page

func _buy_producer(id: String) -> void:
	var k := _mult if _mult > 0 else Game.max_affordable(id)
	if Game.buy_producer(id, k):
		SFX.play("buy_big" if k >= 10 else "buy", 1.0 + 0.04 * float(Balance.producer_index(id)), -8.0)
	else:
		SFX.play("deny", 1.0, -14.0)

func _producer_tip(i: int) -> Dictionary:
	var p: Array = Balance.PRODUCERS[i]
	var id := String(p[0])
	var n := int(Game.count.get(id, 0))
	var each := Game.producer_each(id)
	var total := Game.producer_income(id)
	var share := total / maxf(0.0001, Game.base_income())
	var lines := PackedStringArray()
	lines.append("[i]%s[/i]" % String(p[4]))
	lines.append("")
	lines.append("Each: [b]%s[/b]" % Fmt.per_sec(each))
	if n > 0:
		lines.append("%d owned: [b]%s[/b]  (%s of income)" % [n, Fmt.per_sec(total), Fmt.pct(share)])
	var k := _mult if _mult > 0 else maxi(1, Game.max_affordable(id))
	var c := Game.cost_of(id, k)
	lines.append("Next %d: [b]%s[/b]  -  pays back in %s" % [k, Fmt.cash(c), Fmt.time(c / maxf(0.0001, each * float(k)))])
	var tiers := 0
	for t in range(Balance.TIER_OWNED.size()):
		if Game.owned.has("%s_%d" % [id, t]):
			tiers += 1
	return {"title": String(p[1]), "accent": Pal.producer(i), "body": "\n".join(lines),
		"foot": "%d of %d upgrades bought." % [tiers, Balance.TIER_OWNED.size()]}

# ------------------------------------------------------------ upgrades page

func _build_upgrades() -> VBoxContainer:
	var page := UiKit.vbox(5)
	_upg_empty = UiKit.label("Nothing for sale yet - own more businesses.", 12, Pal.FAINT)
	_upg_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_upg_empty)
	_upg_box = UiKit.vbox(5)
	page.add_child(_upg_box)
	return page

func _upgrade_accent(u: Dictionary) -> Color:
	match String(u["kind"]):
		"producer":
			return Pal.producer(Balance.producer_index(u["target"]))
		"click":
			return Pal.AMBER
	return Pal.CASH

func _rebuild_upgrades(list: Array[Dictionary]) -> void:
	for c in _upg_box.get_children():
		c.queue_free()
	_upg_rows.clear()
	for u in list:
		var accent := _upgrade_accent(u)
		var row := UiKit.panel(Pal.PANEL_2, Pal.LINE, 8)
		UiKit.clickable(row, accent)
		var h := UiKit.hbox(9)
		h.add_child(UiKit.swatch(accent, 12))
		var mid := UiKit.vbox(1)
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.add_child(UiKit.label(String(u["name"]), 13, Pal.INK))
		var eff := UiKit.label(_effect_line(u), 11, Pal.DIM)
		mid.add_child(eff)
		h.add_child(mid)
		var cost := UiKit.label(Fmt.cash(Game.upgrade_cost(u)), 12, Pal.CASH)
		cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(cost)
		row.add_child(h)
		UiKit.passthrough(h)
		var id := String(u["id"])
		row.connect("pressed", _buy_upgrade.bind(id))
		Tooltip.attach(row, _upgrade_tip.bind(u))
		_upg_box.add_child(row)
		_upg_rows[id] = {"row": row, "cost": cost, "u": u}
	_upg_empty.visible = list.is_empty()

func _effect_line(u: Dictionary) -> String:
	match String(u["kind"]):
		"producer":
			return "%s x2" % Balance.producer_name(u["target"])
		"click":
			if float(u["pct"]) > 0.0:
				return "Sales x%d, +%s of income per sale" % [int(u["mult"]), Fmt.pct_whole(float(u["pct"]))]
			return "Sales x%d" % int(u["mult"])
		"brand":
			return "All income +%s" % Fmt.pct_whole(float(u["bonus"]))
	return ""

func _upgrade_tip(u: Dictionary) -> Dictionary:
	var gain := Game.upgrade_value(u, 3.0)
	var body := "[i]%s[/i]\n\n%s" % [String(u["blurb"]), _effect_line(u)]
	if String(u["kind"]) == "click":
		body += "\nWorth about [b]%s[/b] at three sales a second." % Fmt.per_sec(gain)
	else:
		body += "\nWorth [b]%s[/b] right now." % Fmt.per_sec(gain)
	var foot := ""
	if u.has("need"):
		foot = String(u["need"]) + " " + Balance.producer_name(u["target"]) + "s."
	return {"title": String(u["name"]), "accent": _upgrade_accent(u), "body": body, "foot": foot}

func _buy_upgrade(id: String) -> void:
	if Game.buy_upgrade(id):
		SFX.play("upgrade", randf_range(0.97, 1.03), -6.0)
	else:
		SFX.play("deny", 1.0, -14.0)

# ------------------------------------------------------------ stats page

func _build_stats() -> VBoxContainer:
	var page := UiKit.vbox(4)
	var groups := [
		["THIS RUN", Pal.CASH, ["earned_run", "run_time", "clicks_run", "producers", "upgrades", "income"]],
		["ALL TIME", Pal.STEEL, ["earned_all", "play_time", "clicks_all", "vips", "runs", "best_run"]],
		["LEGACY", Pal.GOLD, ["level", "points", "perks", "next"]],
	]
	var names := {
		"earned_run": "Earned", "run_time": "Run time", "clicks_run": "Manual sales",
		"producers": "Businesses", "upgrades": "Upgrades", "income": "Income",
		"earned_all": "Earned", "play_time": "Play time", "clicks_all": "Manual sales",
		"vips": "VIPs caught", "runs": "Cash outs", "best_run": "Best run",
		"level": "Level", "points": "Unspent", "perks": "Perks", "next": "Next point at",
	}
	for g in groups:
		page.add_child(UiKit.hsep(4))
		page.add_child(UiKit.header(String(g[0]), g[1]))
		for k in (g[2] as Array):
			var r := UiKit.stat_row(names[k])
			page.add_child(r)
			_stats[k] = UiKit.row_value(r)
	return page

func _update_stats() -> void:
	_stats["earned_run"].text = Fmt.cash(Game.earned_run)
	_stats["run_time"].text = Fmt.time(Game.run_time)
	_stats["clicks_run"].text = Fmt.count(Game.clicks_run)
	_stats["producers"].text = Fmt.count(Game.total_producers())
	_stats["upgrades"].text = "%d / %d" % [Game.owned_upgrades(), Balance.upgrades.size()]
	_stats["income"].text = Fmt.per_sec(Game.income())
	_stats["earned_all"].text = Fmt.cash(Game.earned_all)
	_stats["play_time"].text = Fmt.time(Game.play_time)
	_stats["clicks_all"].text = Fmt.count(Game.clicks_all)
	_stats["vips"].text = Fmt.count(Game.vips_caught)
	_stats["runs"].text = Fmt.count(Game.runs)
	_stats["best_run"].text = Fmt.cash(Game.best_run)
	_stats["level"].text = "%d  (+%s)" % [Game.legacy_level, Fmt.pct_whole(float(Game.legacy_level) * Balance.LEVEL_BONUS * Game.tree_mult("level_bonus_mult"))]
	_stats["points"].text = Fmt.count(Game.legacy)
	_stats["perks"].text = "%d / %d" % [Game.tree_progress().x, Game.tree_progress().y]
	_stats["next"].text = Fmt.cash(Game.next_legacy_at())

# ------------------------------------------------------------ per frame

func _process(_dt: float) -> void:
	match _tab:
		"buy":
			_update_buy()
		"upgrades":
			_update_upgrades()
		"stats":
			_update_stats()
	# The tab label carries the count of upgrades waiting, so the player
	# sees one appear without having the tab open.
	var avail := Game.available_upgrades()
	var afford := 0
	for u in avail:
		if Game.cash >= Game.upgrade_cost(u):
			afford += 1
	_tabs["upgrades"].text = "UPGRADES" + ("  %d" % afford if afford > 0 else "")

func _update_buy() -> void:
	var teaser_i := -1
	for i in range(_rows.size()):
		var r: Dictionary = _rows[i]
		var id := String(r["id"])
		var vis := Game.producer_visible(i)
		(r["row"] as Control).visible = vis
		if not vis:
			if teaser_i < 0:
				teaser_i = i
			continue
		var n := int(Game.count.get(id, 0))
		var each := Game.producer_each(id)
		if n > 0:
			r["sub"].text = "%s each  -  %s" % [Fmt.per_sec(each), Fmt.per_sec(Game.producer_income(id))]
		else:
			r["sub"].text = "%s each" % Fmt.per_sec(each)
		r["count"].text = str(n)
		var k := _mult if _mult > 0 else Game.max_affordable(id)
		var shown_k := maxi(1, k)
		var c := Game.cost_of(id, shown_k)
		var ok := k > 0 and Game.cash >= c
		r["cost"].text = Fmt.cash(c) if shown_k == 1 else "%s  x%d" % [Fmt.cash(c), shown_k]
		r["cost"].add_theme_color_override("font_color", Pal.CASH if ok else Pal.DANGER.lerp(Pal.DIM, 0.4))
		UiKit.set_clickable_enabled(r["row"], ok)
	if teaser_i >= 0:
		(_teaser["row"] as Control).visible = true
		var need := Balance.base_cost(String(Balance.PRODUCERS[teaser_i][0])) * Balance.REVEAL_FRACTION
		_teaser["sub"].text = "Revealed at %s earned this run" % Fmt.cash(need)
	else:
		(_teaser["row"] as Control).visible = false

func _update_upgrades() -> void:
	var list := Game.available_upgrades()
	var ids := PackedStringArray()
	for u in list:
		ids.append(String(u["id"]))
	var sig := ",".join(ids)
	if sig != _upg_sig:
		_upg_sig = sig
		_rebuild_upgrades(list)
	for id in _upg_rows:
		var r: Dictionary = _upg_rows[id]
		var c := Game.upgrade_cost(r["u"])
		var ok := Game.cash >= c
		r["cost"].add_theme_color_override("font_color", Pal.CASH if ok else Pal.DANGER.lerp(Pal.DIM, 0.4))
		UiKit.set_clickable_enabled(r["row"], ok)
