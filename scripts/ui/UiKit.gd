class_name UiKit
extends RefCounted
## Shared widget builders. The whole interface is constructed in code, so this
## is where the repeated styling lives instead of being copy-pasted into every
## panel.

static func label(text: String, size: int = 14, color: Color = Pal.INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

## Small all-caps header. Used on every panel so the eye can find them.
static func header(text: String, color: Color = Pal.DIM) -> Label:
	var l := label(text, 11, color)
	l.add_theme_constant_override("line_spacing", 0)
	return l

static func rich(text: String, size: int = 13, color: Color = Pal.DIM) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.text = text
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_color_override("default_color", color)
	return r

static func stylebox(bg: Color, border: Color = Pal.LINE, radius: int = 5,
		width: int = 1, pad: int = 9) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = maxi(2, pad - 3)
	sb.content_margin_bottom = maxi(2, pad - 3)
	return sb

static func panel(bg: Color = Pal.PANEL, border: Color = Pal.LINE, pad: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", stylebox(bg, border, 6, 1, pad))
	return p

## `quiet` suppresses the generic click tick for buttons that already make a
## louder sound of their own, so nothing ever double-ticks.
static func button(text: String, accent: Color = Pal.CASH, size: int = 13,
		quiet: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	# Keyboard focus would swallow SPACE, which is the sell key.
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Pal.INK)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Pal.FAINT)
	b.add_theme_stylebox_override("normal", stylebox(Pal.PANEL_2, accent.darkened(0.5)))
	b.add_theme_stylebox_override("hover", stylebox(Pal.RAISED, accent))
	b.add_theme_stylebox_override("pressed", stylebox(accent.darkened(0.68), accent))
	b.add_theme_stylebox_override("disabled", stylebox(Pal.PANEL.darkened(0.3), Pal.LINE.darkened(0.3)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	animate(b, quiet)
	return b

## A button with no chrome, for tabs and close boxes.
static func flat_button(text: String, size: int = 13) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Pal.DIM)
	b.add_theme_color_override("font_hover_color", Pal.INK)
	b.add_theme_color_override("font_pressed_color", Pal.INK)
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", stylebox(Pal.PANEL_2, Pal.LINE))
	b.add_theme_stylebox_override("pressed", stylebox(Pal.VOID, Pal.LINE))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	animate(b, true)
	return b

## A tab: flat, with an accent underline when selected.
static func set_tab_selected(b: Button, on: bool, accent: Color) -> void:
	if on:
		var sb := stylebox(Pal.PANEL_2, accent, 4, 0, 9)
		sb.border_width_bottom = 2
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_color_override("font_color", Pal.INK)
	else:
		b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("hover", stylebox(Pal.PANEL_2, Pal.LINE))
		b.add_theme_color_override("font_color", Pal.DIM)

## Hover lift, press squash, release settle, plus the UI ticks. Buttons here are
## persistent nodes, so the tween state can live on the node itself.
static func animate(b: Button, quiet: bool = false) -> void:
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.mouse_entered.connect(func() -> void:
		if b.disabled:
			return
		_scale_to(b, 1.03, 0.10)
		SFX.play("hover", randf_range(0.97, 1.05), -26.0))
	b.mouse_exited.connect(func() -> void: _scale_to(b, 1.0, 0.12))
	b.button_down.connect(func() -> void: _scale_to(b, 0.955, 0.05))
	b.button_up.connect(func() -> void: _scale_to(b, 1.0, 0.16, true))
	if not quiet:
		b.pressed.connect(func() -> void:
			SFX.play("click", randf_range(0.96, 1.06), -18.0))

## A one-shot bounce for the moment something becomes affordable. Without it a
## row going from disabled to ready only changes colour, and the player misses
## the moment entirely.
static func attention(b: Control) -> void:
	if not is_instance_valid(b):
		return
	b.pivot_offset = b.size * 0.5
	_kill_tween(b)
	var tw := b.create_tween()
	b.set_meta("ui_tw", tw)
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_BACK)
	tw.tween_property(b, "scale", Vector2(1.06, 1.06), 0.12)
	tw.tween_property(b, "scale", Vector2.ONE, 0.22)

static func _kill_tween(b: Control) -> void:
	if b.has_meta("ui_tw"):
		var prev = b.get_meta("ui_tw")
		if prev is Tween and (prev as Tween).is_valid():
			(prev as Tween).kill()

static func _scale_to(b: Control, target: float, time: float, bounce: bool = false) -> void:
	if not is_instance_valid(b):
		return
	b.pivot_offset = b.size * 0.5
	_kill_tween(b)
	var tw := b.create_tween()
	b.set_meta("ui_tw", tw)
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_BACK if bounce else Tween.TRANS_QUAD)
	tw.tween_property(b, "scale", Vector2(target, target), time)

## A whole panel that behaves like a button: hover lift, press squash, and a
## `pressed` user signal. The shop rows are these, because a row with three
## labels in it is not something a Button lays out on its own.
static func clickable(p: PanelContainer, accent: Color) -> PanelContainer:
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.add_user_signal("pressed")
	p.set_meta("accent", accent)
	p.set_meta("enabled", true)
	p.resized.connect(func() -> void: p.pivot_offset = p.size * 0.5)
	p.mouse_entered.connect(func() -> void:
		p.set_meta("hover", true)
		if bool(p.get_meta("enabled")):
			_scale_to(p, 1.015, 0.10)
			SFX.play("hover", randf_range(0.97, 1.05), -26.0)
		restyle_clickable(p))
	p.mouse_exited.connect(func() -> void:
		p.set_meta("hover", false)
		_scale_to(p, 1.0, 0.12)
		restyle_clickable(p))
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var mb := ev as InputEventMouseButton
			if mb.pressed:
				if bool(p.get_meta("enabled")):
					_scale_to(p, 0.97, 0.05)
			else:
				_scale_to(p, 1.0, 0.16, true)
				if bool(p.get_meta("enabled")):
					p.emit_signal("pressed")
				else:
					SFX.play("deny", 1.0, -14.0))
	restyle_clickable(p)
	return p

static func set_clickable_enabled(p: PanelContainer, on: bool) -> void:
	if bool(p.get_meta("enabled")) == on:
		return
	p.set_meta("enabled", on)
	if on:
		attention(p)
	restyle_clickable(p)

static func restyle_clickable(p: PanelContainer) -> void:
	var accent: Color = p.get_meta("accent")
	var on := bool(p.get_meta("enabled"))
	var hover := bool(p.get_meta("hover")) if p.has_meta("hover") else false
	var sb: StyleBoxFlat
	if not on:
		sb = stylebox(Pal.PANEL.darkened(0.25), Pal.LINE.darkened(0.35), 6, 1, 9)
	elif hover:
		sb = stylebox(Pal.RAISED, accent, 6, 1, 9)
	else:
		sb = stylebox(Pal.PANEL_2, accent.darkened(0.55), 6, 1, 9)
	p.add_theme_stylebox_override("panel", sb)

## A flat coloured bar. Godot's ProgressBar theming is more fight than it is
## worth here, and this keeps the fill colour under our control frame to frame.
static func bar(height: int = 10, fill: Color = Pal.CASH) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, height)
	p.max_value = 1.0
	p.step = 0.0001
	var bg := StyleBoxFlat.new()
	bg.bg_color = Pal.VOID
	bg.set_corner_radius_all(3)
	bg.border_color = Pal.LINE
	bg.set_border_width_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(3)
	p.add_theme_stylebox_override("background", bg)
	p.add_theme_stylebox_override("fill", fg)
	return p

## A label pair that reads as one line: dim name on the left, bright value hard
## against the right edge.
static func stat_row(name_text: String, value_text: String = "",
		value_color: Color = Pal.INK) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := label(name_text, 12, Pal.DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := label(value_text, 12, value_color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(l)
	h.add_child(v)
	h.set_meta("value", v)
	h.set_meta("name", l)
	return h

static func row_value(h: HBoxContainer) -> Label:
	return h.get_meta("value")

static func hsep(h: int = 6) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

static func rule(color: Color = Pal.LINE) -> Control:
	var c := ColorRect.new()
	c.color = color
	c.custom_minimum_size = Vector2(0, 1)
	return c

static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c

static func scroll(child: Control, horizontal: bool = false) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not horizontal:
		s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s

static func vbox(sep: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

static func hbox(sep: int = 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

## A small coloured chip, used for producer swatches and branch dots.
static func swatch(c: Color, size: int = 10) -> Control:
	var r := ColorRect.new()
	r.color = c
	r.custom_minimum_size = Vector2(size, size)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## Every child of a clickable panel must let the mouse through to it.
static func passthrough(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in c.get_children():
		if ch is Control:
			passthrough(ch)
