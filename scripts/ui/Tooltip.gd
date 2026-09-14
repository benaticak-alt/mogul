class_name Tooltip
extends PanelContainer
## One floating tooltip, shared by every panel that wants one.
##
## Godot's built-in hint tooltips arrive on a delay and cannot be styled
## without a custom scene per control. A single instance parked on top of
## the interface is simpler and instant.

static var instance: Tooltip

var _title: Label
var _body: RichTextLabel
var _foot: Label

func _init() -> void:
	instance = self

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = 200
	custom_minimum_size = Vector2(260, 0)
	add_theme_stylebox_override("panel", UiKit.stylebox(Pal.PANEL.darkened(0.15), Pal.LINE, 6, 1, 11))
	var v := UiKit.vbox(5)
	_title = UiKit.label("", 14, Pal.INK)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body = UiKit.rich("", 12, Pal.DIM)
	_foot = UiKit.label("", 11, Pal.FAINT)
	_foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_title)
	v.add_child(_body)
	v.add_child(_foot)
	add_child(v)

## Attaches hover behaviour to any control. `supplier` returns the current
## text each time the mouse enters, so tooltips always show live numbers.
static func attach(c: Control, supplier: Callable) -> void:
	c.mouse_entered.connect(func() -> void:
		if instance == null:
			return
		var d: Dictionary = supplier.call()
		instance.show_tip(d.get("title", ""), d.get("body", ""),
			d.get("foot", ""), d.get("accent", Pal.LINE)))
	c.mouse_exited.connect(func() -> void:
		if instance != null:
			instance.hide_tip())
	c.tree_exiting.connect(func() -> void:
		if instance != null:
			instance.hide_tip())

func show_tip(title: String, body: String, foot: String = "", accent: Color = Pal.LINE) -> void:
	_title.text = title
	_title.add_theme_color_override("font_color", accent)
	_body.text = body
	_body.visible = body != ""
	_foot.text = foot
	_foot.visible = foot != ""
	add_theme_stylebox_override("panel", UiKit.stylebox(Pal.PANEL.darkened(0.15), accent.darkened(0.4), 6, 1, 11))
	visible = true
	reset_size()
	_place()

func hide_tip() -> void:
	visible = false

func _process(_dt: float) -> void:
	if visible:
		_place()

## Sits beside the cursor and stays inside the window.
func _place() -> void:
	var vp := get_viewport_rect().size
	var m := get_viewport().get_mouse_position()
	var p := m + Vector2(16, 16)
	if p.x + size.x > vp.x - 8:
		p.x = m.x - size.x - 12
	if p.y + size.y > vp.y - 8:
		p.y = vp.y - size.y - 8
	position = p.max(Vector2(8, 8))
