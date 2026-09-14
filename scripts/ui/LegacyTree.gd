extends Control
## The legacy tree, as a full-screen overlay. Five spokes off a hub, drawn
## every frame; the nodes are not controls, so hover and click are hit-tested
## by hand and the shared Tooltip is driven directly.

signal closed()

const NODE_R := 20.0
const HUB_R := 32.0
const RING_0 := 92.0
const RING_STEP := 72.0
const HEADER_H := 64.0

var _font: Font
var _hover := ""
var _pops: Dictionary = {}     ## node id -> seconds since bought, for the ring
var _title: Label
var _points: Label
var _level: Label

func _ready() -> void:
	visible = false
	z_index = 100
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font

	var head := UiKit.panel(Pal.PANEL, Pal.MAUVE.darkened(0.5), 12)
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	head.offset_left = 10
	head.offset_right = -10
	head.offset_top = 10
	var row := UiKit.hbox(16)
	var left := UiKit.vbox(0)
	_title = UiKit.label("LEGACY TREE", 18, Pal.MAUVE)
	left.add_child(_title)
	var sub := UiKit.label("Perks bought here survive every Cash Out.", 12, Pal.DIM)
	left.add_child(sub)
	row.add_child(left)
	row.add_child(UiKit.spacer())
	var mid := UiKit.vbox(0)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	_points = UiKit.label("", 16, Pal.GOLD)
	_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_level = UiKit.label("", 12, Pal.DIM)
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mid.add_child(_points)
	mid.add_child(_level)
	row.add_child(mid)
	var close := UiKit.button("CLOSE  [ESC]", Pal.MAUVE, 12)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void: hide_tree())
	row.add_child(close)
	head.add_child(row)
	add_child(head)

func show_tree() -> void:
	visible = true
	_hover = ""
	SFX.play("tab", 0.8, -10.0)

func hide_tree() -> void:
	visible = false
	if Tooltip.instance != null:
		Tooltip.instance.hide_tip()
	closed.emit()

# ------------------------------------------------------------ geometry

func _center() -> Vector2:
	return Vector2(size.x * 0.5, HEADER_H + (size.y - HEADER_H) * 0.5 + 12.0)

func node_pos(n: Dictionary) -> Vector2:
	var ang := deg_to_rad(float(Balance.BRANCHES[n["branch"]]["angle"]))
	var ring := int(n["ring"])
	var r := RING_0 + float(ring - 1) * RING_STEP
	var dir := Vector2(cos(ang), sin(ang))
	var perp := Vector2(-dir.y, dir.x)
	# A little lean per ring so the spokes read as grown, not ruled.
	return _center() + dir * r + perp * sin(float(ring) * 1.9 + ang) * 8.0

func _parent_pos(n: Dictionary) -> Vector2:
	var p := String(n["parent"])
	if p == "":
		return _center()
	return node_pos(Balance.node(p))

func _node_at(m: Vector2) -> String:
	for n in Balance.TREE:
		if node_pos(n).distance_to(m) <= NODE_R + 3.0:
			return String(n["id"])
	return ""

# ------------------------------------------------------------ input

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var id := _node_at((ev as InputEventMouseMotion).position)
		if id != _hover:
			_hover = id
			if id == "":
				Tooltip.instance.hide_tip()
			else:
				var d := _tip(id)
				Tooltip.instance.show_tip(d["title"], d["body"], d["foot"], d["accent"])
				SFX.play("hover", 1.0, -26.0)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if (id != "" and Game.node_can_buy(id)) else Control.CURSOR_ARROW
	elif ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var id := _node_at(mb.position)
			if id != "":
				if Game.buy_node(id):
					_pops[id] = 0.0
					SFX.play("node", 1.0, -4.0)
					var d := _tip(id)
					Tooltip.instance.show_tip(d["title"], d["body"], d["foot"], d["accent"])
				else:
					SFX.play("deny", 1.0, -14.0)
			accept_event()

func _tip(id: String) -> Dictionary:
	var n := Balance.node(id)
	var accent: Color = Pal.branch(n["branch"])
	var foot := ""
	if Game.node_owned(id):
		foot = "Owned."
	elif not Game.node_unlocked(id):
		foot = "Needs %s first." % String(Balance.node(n["parent"])["name"])
	elif Game.legacy < int(n["cost"]):
		foot = "Costs %d legacy - you have %d." % [int(n["cost"]), Game.legacy]
	else:
		foot = "Click to buy for %d legacy." % int(n["cost"])
	return {"title": String(n["name"]), "accent": accent,
		"body": "[color=#%s]%s[/color]\n\n%s" % [accent.darkened(0.15).to_html(false), Balance.branch_name(n["branch"]), String(n["desc"])],
		"foot": foot}

# ------------------------------------------------------------ drawing

func _process(dt: float) -> void:
	if not visible:
		return
	for k in _pops.keys():
		_pops[k] = float(_pops[k]) + dt
		if float(_pops[k]) > 0.8:
			_pops.erase(k)
	_points.text = "%d legacy to spend" % Game.legacy
	var p := Game.tree_progress()
	_level.text = "level %d   -   %d of %d perks" % [Game.legacy_level, p.x, p.y]
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Pal.VOID, 0.94))
	var c := _center()
	var t := Game.play_time

	# Branch names at the end of each spoke.
	for bid in Balance.BRANCHES:
		var b: Dictionary = Balance.BRANCHES[bid]
		var rings := 0
		for n in Balance.TREE:
			if n["branch"] == bid:
				rings = maxi(rings, int(n["ring"]))
		var ang := deg_to_rad(float(b["angle"]))
		var p := c + Vector2(cos(ang), sin(ang)) * (RING_0 + float(rings - 1) * RING_STEP + NODE_R + 18.0)
		# Anchored on the side away from the hub, so the name never runs back
		# over the last node of its own spoke.
		var col := Color(Pal.branch(bid), 0.8)
		var txt := String(b["name"]).to_upper()
		if cos(ang) > 0.3:
			draw_string(_font, p + Vector2(0, 5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		elif cos(ang) < -0.3:
			draw_string(_font, p + Vector2(-200, 5), txt, HORIZONTAL_ALIGNMENT_RIGHT, 200, 11, col)
		else:
			draw_string(_font, p + Vector2(-80, 5), txt, HORIZONTAL_ALIGNMENT_CENTER, 160, 11, col)

	# Edges first, so the nodes sit on top of them.
	for n in Balance.TREE:
		var id := String(n["id"])
		var a := _parent_pos(n)
		var bpos := node_pos(n)
		var col: Color
		var w := 2.0
		if Game.node_owned(id):
			col = Pal.branch(n["branch"])
			w = 3.0
		elif Game.node_unlocked(id):
			col = Color(Pal.branch(n["branch"]), 0.45)
		else:
			col = Pal.LINE
		draw_line(a, bpos, col, w)

	# Hub.
	draw_circle(c, HUB_R + 6.0, Color(Pal.GOLD, 0.10))
	draw_circle(c, HUB_R, Pal.PANEL_2)
	draw_arc(c, HUB_R, 0.0, TAU, 48, Pal.GOLD, 2.0)
	draw_string(_font, c + Vector2(-40, 5), "MOGUL", HORIZONTAL_ALIGNMENT_CENTER, 80, 13, Pal.GOLD)

	for n in Balance.TREE:
		var id := String(n["id"])
		var p := node_pos(n)
		var accent: Color = Pal.branch(n["branch"])
		var owned := Game.node_owned(id)
		var unlocked := Game.node_unlocked(id)
		var can := Game.node_can_buy(id)
		if _pops.has(id):
			var k := float(_pops[id]) / 0.8
			draw_arc(p, NODE_R + 6.0 + k * 26.0, 0.0, TAU, 40, Color(accent, 1.0 - k), 2.0)
		if can:
			var pulse := 0.5 + 0.5 * sin(t * 4.0)
			draw_circle(p, NODE_R + 7.0 + pulse * 3.0, Color(accent, 0.12 + 0.1 * pulse))
		if owned:
			draw_circle(p, NODE_R, accent)
			draw_circle(p, NODE_R * 0.45, accent.darkened(0.45))
		else:
			draw_circle(p, NODE_R, Pal.PANEL_2 if unlocked else Pal.PANEL)
			var ring_col := accent if unlocked else Pal.LINE
			draw_arc(p, NODE_R, 0.0, TAU, 40, ring_col, 2.0 if unlocked else 1.0)
			var cost_col := Pal.INK if can else (Pal.DIM if unlocked else Pal.FAINT)
			draw_string(_font, p + Vector2(-30, 5), str(int(n["cost"])), HORIZONTAL_ALIGNMENT_CENTER, 60, 13, cost_col)
		if _hover == id:
			draw_arc(p, NODE_R + 4.0, 0.0, TAU, 40, Pal.INK, 1.5)
		var name_col := Pal.INK if (owned or unlocked) else Pal.FAINT
		draw_string(_font, p + Vector2(-70, NODE_R + 15.0), String(n["name"]), HORIZONTAL_ALIGNMENT_CENTER, 140, 10, name_col)

	# The legend, bottom left.
	var ly := size.y - 58.0
	draw_string(_font, Vector2(24, ly), "Legacy is cut from lifetime earnings on a square-root curve. Every level is +%s income; points are spent here." % Fmt.pct_whole(Balance.LEVEL_BONUS * Game.tree_mult("level_bonus_mult")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Pal.DIM)
	draw_string(_font, Vector2(24, ly + 18), "Lifetime earned %s  -  next point at %s" % [Fmt.cash(Game.earned_all), Fmt.cash(Game.next_legacy_at())], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Pal.FAINT)
