extends Control
## The street. Everything the player looks at that is not a number.
##
## Drawn every frame from Game state rather than kept as nodes: the HQ grows a
## floor per order of magnitude the run has earned, each owned producer gets
## a lot beside it that flies coins to the door, customers and cars thicken as
## income climbs, and a day cycle lights the windows. Clicking the HQ is a
## sale; clicking the gold VIP is the jackpot. Nothing here feeds back into
## the economy except those two clicks.

const GROUND_FRAC := 0.86
const HQ_W := 200.0
const FLOOR_H := 30.0
const HQ_CAP := 14            ## floors, so the sign never leaves the sky
const LOT_W_MAX := 80.0
const LOTS_PER_SIDE := 6
const DAY_CYCLE := 360.0      ## seconds for a full day
const MAX_COINS := 70
const CLICK_HINT_UNTIL := 25  ## manual sales before the SELL prompt goes

var _skyline: Array = []      ## [x_frac, w_frac, height, seed]
var _far: Array = []          ## a second, hazier row behind it
var _stars: PackedVector2Array = PackedVector2Array()
var _customers: Array = []
var _cars: Array = []
var _coins: Array = []        ## {a, b, t, dur, arc}
var _floats: Array = []       ## {pos, text, t, dur, color, size}
var _bursts: Array = []       ## {pos, vel, t}
var _puffs: Array = []        ## chimney smoke {pos, t}
var _lot_timer: Dictionary = {}
var _punch := 0.0
var _till_glow := 0.0
var _auto_acc := 0.0
var _auto_t := 0.0
var _vip_dir := 1.0
var _vip_hover := false
var _hq_hover := false
var _font: Font
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_font = ThemeDB.fallback_font
	_rng.seed = 7
	for i in range(44):
		_skyline.append([_rng.randf(), _rng.randf_range(0.025, 0.07),
			_rng.randf_range(60.0, 320.0), _rng.randi()])
	for i in range(34):
		_far.append([_rng.randf(), _rng.randf_range(0.03, 0.09),
			_rng.randf_range(90.0, 300.0), _rng.randi()])
	for i in range(80):
		_stars.append(Vector2(_rng.randf(), _rng.randf() * 0.6))
	Game.clicked.connect(_on_clicked)
	Game.vip_spawned.connect(_on_vip)
	Game.vip_resolved.connect(_on_vip_resolved)
	Game.vip_missed.connect(func() -> void: _vip_hover = false)
	Game.producer_bought.connect(_on_bought)
	Game.cashed_out.connect(func(_g: int) -> void:
		_coins.clear()
		_floats.clear()
		_customers.clear()
		_lot_timer.clear())

# ------------------------------------------------------------ geometry

func ground_y() -> float:
	return floorf(size.y * GROUND_FRAC)

func hq_floors() -> int:
	var e := maxf(1.0, Game.earned_run)
	return clampi(1 + int(floor(log(e) / log(10.0))), 1, HQ_CAP)

func hq_floor_h() -> float:
	var max_h := ground_y() - 96.0
	return minf(FLOOR_H, max_h / float(hq_floors()))

func hq_rect() -> Rect2:
	var h := float(hq_floors()) * hq_floor_h()
	return Rect2(size.x * 0.5 - HQ_W * 0.5, ground_y() - h, HQ_W, h)

func hq_door() -> Vector2:
	return Vector2(size.x * 0.5, ground_y() - 4.0)

func lot_w() -> float:
	var half := size.x * 0.5 - HQ_W * 0.5 - 26.0
	return clampf(half / float(LOTS_PER_SIDE), 40.0, LOT_W_MAX)

func lot_rect(i: int) -> Rect2:
	var side := 1.0 if i % 2 == 0 else -1.0
	var rank := i / 2
	var w := lot_w()
	var cx := size.x * 0.5 + side * (HQ_W * 0.5 + 16.0 + float(rank) * w + w * 0.5)
	var h := 46.0 + float(i) * 5.0
	var inner := w - 10.0
	return Rect2(cx - inner * 0.5, ground_y() - h, inner, h)

func vip_pos() -> Vector2:
	var p := Game.vip_progress()
	var x := lerpf(-30.0, size.x + 30.0, p if _vip_dir > 0.0 else 1.0 - p)
	return Vector2(x, ground_y() + 14.0)

# ------------------------------------------------------------ input

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var m := (ev as InputEventMouseMotion).position
		_vip_hover = Game.vip_active and _vip_hit(m)
		_hq_hover = hq_rect().grow(16.0).has_point(m)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if (_vip_hover or _hq_hover) else Control.CURSOR_ARROW
	elif ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if Game.vip_active and _vip_hit(mb.position):
				Game.click_vip()
			elif hq_rect().grow(16.0).has_point(mb.position):
				var v := Game.click()
				_sale_feedback(mb.position, v)
			accept_event()

func _vip_hit(m: Vector2) -> bool:
	var p := vip_pos()
	return Rect2(p.x - 22.0, p.y - 58.0, 44.0, 64.0).has_point(m)

## Keyboard sales land on the door.
func sell_from_key() -> void:
	var v := Game.click()
	_sale_feedback(hq_door() + Vector2(0, -30), v)

func _sale_feedback(at: Vector2, v: float) -> void:
	_punch = 1.0
	_till_glow = 1.0
	SFX.sale(-6.0)
	_float(at + Vector2(randf_range(-8, 8), -10), "+" + Fmt.cash(v), Pal.INK, 15)
	var n := 3 + mini(5, int(log(maxf(1.0, v)) / log(10.0)))
	for i in range(n):
		_bursts.append({"pos": at, "t": 0.0,
			"vel": Vector2(randf_range(-90, 90), randf_range(-240, -120))})

func _on_clicked(amount: float, manual: bool) -> void:
	if manual:
		return
	# Autodialer sales are folded into one float twice a second so ten a
	# second does not paper the door in text.
	_auto_acc += amount

func _on_vip() -> void:
	_vip_dir = 1.0 if randf() < 0.5 else -1.0
	SFX.play("vip", 1.0, -4.0)

func _on_vip_resolved(kind: String, amount: float) -> void:
	_vip_hover = false
	var p := vip_pos() + Vector2(0, -70)
	if kind == "rush":
		SFX.play("rush", 1.0, -2.0)
		_float(p, "RUSH HOUR  x%d" % int(amount), Pal.GOLD, 22, 2.0)
	else:
		SFX.play("windfall", 1.0, -2.0)
		_float(p, "WINDFALL  +" + Fmt.cash(amount), Pal.GOLD, 22, 2.0)
		for i in range(18):
			_bursts.append({"pos": vip_pos() + Vector2(0, -30), "t": 0.0,
				"vel": Vector2(randf_range(-160, 160), randf_range(-300, -120))})

func _on_bought(id: String, _n: int) -> void:
	var i := Balance.producer_index(id)
	var r := lot_rect(i)
	_float(Vector2(r.get_center().x, r.position.y - 14), Balance.producer_name(id), Pal.producer(i), 11, 1.2)
	for k in range(4):
		_bursts.append({"pos": r.get_center(), "t": 0.0,
			"vel": Vector2(randf_range(-70, 70), randf_range(-160, -80))})

func _float(pos: Vector2, text: String, color: Color, fsize: int = 14, dur: float = 0.95) -> void:
	_floats.append({"pos": pos, "text": text, "t": 0.0, "dur": dur, "color": color, "size": fsize})

# ------------------------------------------------------------ simulation

func _process(dt: float) -> void:
	_punch = maxf(0.0, _punch - dt * 5.0)
	_till_glow = maxf(0.0, _till_glow - dt * 2.2)

	_auto_t += dt
	if _auto_t >= 0.5:
		_auto_t = 0.0
		if _auto_acc > 0.0:
			_float(hq_door() + Vector2(randf_range(-30, 30), -26), "+" + Fmt.cash(_auto_acc), Pal.AMBER, 12, 0.8)
			_auto_acc = 0.0

	_tick_lots(dt)
	_tick_people(dt)
	_tick_cars(dt)

	for c in _coins:
		c["t"] += dt
	for i in range(_coins.size() - 1, -1, -1):
		if float(_coins[i]["t"]) >= float(_coins[i]["dur"]):
			_till_glow = minf(1.0, _till_glow + 0.25)
			_coins.remove_at(i)
	for f in _floats:
		f["t"] += dt
	_floats = _floats.filter(func(f: Dictionary) -> bool: return float(f["t"]) < float(f["dur"]))
	for b in _bursts:
		b["t"] += dt
		b["vel"] = (b["vel"] as Vector2) + Vector2(0, 620.0) * dt
		b["pos"] = (b["pos"] as Vector2) + (b["vel"] as Vector2) * dt
	_bursts = _bursts.filter(func(b: Dictionary) -> bool: return float(b["t"]) < 0.8)
	for p in _puffs:
		p["t"] += dt
		p["pos"] = (p["pos"] as Vector2) + Vector2(6.0, -14.0) * dt
	_puffs = _puffs.filter(func(p: Dictionary) -> bool: return float(p["t"]) < 2.4)
	queue_redraw()

## Each owned lot flies a coin to the door now and then; more of a producer
## means a faster trickle, but the trickle is capped so late game is a
## stream and not a wall.
func _tick_lots(dt: float) -> void:
	for i in range(Balance.PRODUCERS.size()):
		var id := String(Balance.PRODUCERS[i][0])
		var n := int(Game.count.get(id, 0))
		if n <= 0:
			continue
		var interval := clampf(2.6 / (1.0 + log(float(n) + 1.0)), 0.55, 2.6)
		var t := float(_lot_timer.get(id, randf() * interval)) - dt
		if t <= 0.0:
			t = interval * randf_range(0.8, 1.2)
			if _coins.size() < MAX_COINS:
				var r := lot_rect(i)
				var from := Vector2(r.get_center().x, r.position.y + 4.0)
				_coins.append({"a": from, "b": hq_door() + Vector2(randf_range(-14, 14), -10),
					"t": 0.0, "dur": randf_range(0.7, 0.95), "arc": randf_range(50.0, 110.0)})
			if i % 4 == 3 and randf() < 0.5:
				var rr := lot_rect(i)
				_puffs.append({"pos": Vector2(rr.end.x - 8.0, rr.position.y - 12.0), "t": 0.0})
		_lot_timer[id] = t

func _tick_people(dt: float) -> void:
	var want := clampi(2 + int(log(Game.base_income() + 1.0) / log(10.0) * 1.6), 2, 16)
	while _customers.size() < want:
		var dir := 1.0 if randf() < 0.5 else -1.0
		_customers.append({
			"x": randf() * size.x if _customers.size() < 2 else (-20.0 if dir > 0 else size.x + 20.0),
			"dir": dir, "speed": randf_range(22.0, 48.0), "phase": randf() * TAU,
			"shirt": Color.from_hsv(randf(), 0.35, randf_range(0.45, 0.75)),
			"skin": Color.from_hsv(0.08, randf_range(0.25, 0.55), randf_range(0.45, 0.9)),
			"hat": randf() < 0.3, "h": randf_range(0.85, 1.12),
		})
	while _customers.size() > want:
		_customers.pop_back()
	for c in _customers:
		c["x"] = float(c["x"]) + float(c["dir"]) * float(c["speed"]) * dt
		c["phase"] = float(c["phase"]) + dt * float(c["speed"]) * 0.28
		if float(c["x"]) < -30.0:
			c["x"] = size.x + 30.0
		elif float(c["x"]) > size.x + 30.0:
			c["x"] = -30.0

func _tick_cars(dt: float) -> void:
	var want := clampi(int(log(Game.base_income() + 1.0) / log(10.0) * 0.6), 0, 5)
	while _cars.size() < want:
		var dir := 1.0 if randf() < 0.5 else -1.0
		_cars.append({"x": randf() * size.x, "dir": dir, "speed": randf_range(70.0, 130.0),
			"len": randf_range(38.0, 60.0), "lane": randi() % 2,
			"color": Color.from_hsv(randf(), 0.3, randf_range(0.35, 0.7))})
	while _cars.size() > want:
		_cars.pop_back()
	for c in _cars:
		c["x"] = float(c["x"]) + float(c["dir"]) * float(c["speed"]) * dt
		if float(c["x"]) < -80.0:
			c["x"] = size.x + 80.0
		elif float(c["x"]) > size.x + 80.0:
			c["x"] = -80.0

# ------------------------------------------------------------ drawing

func _daylight() -> float:
	var t := fmod(Game.play_time, DAY_CYCLE) / DAY_CYCLE
	return 0.5 + 0.5 * cos(TAU * t)

func _night() -> float:
	return 1.0 - smoothstep(0.30, 0.62, _daylight())

func _draw() -> void:
	var gy := ground_y()
	var day := _daylight()
	var sky: Color
	var horizon: Color
	if day > 0.5:
		sky = Pal.SKY_DUSK.lerp(Pal.SKY_DAY, (day - 0.5) * 2.0)
		horizon = Pal.HORIZON_DUSK.lerp(Pal.HORIZON_DAY, (day - 0.5) * 2.0)
	else:
		sky = Pal.SKY_NIGHT.lerp(Pal.SKY_DUSK, day * 2.0)
		horizon = Pal.HORIZON_NIGHT.lerp(Pal.HORIZON_DUSK, day * 2.0)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, gy), Vector2(0, gy)]),
		PackedColorArray([sky, sky, horizon, horizon]))

	var night := _night()
	if night > 0.01:
		for s in _stars:
			var tw := 0.5 + 0.5 * sin(Game.play_time * 1.7 + s.x * 40.0)
			draw_circle(Vector2(s.x * size.x, s.y * gy), 1.0, Color(1, 1, 1, night * (0.35 + 0.5 * tw)))
	_draw_sun_moon(gy)
	_draw_skyline(gy, night)
	_draw_street(gy)
	for i in range(Balance.PRODUCERS.size()):
		if int(Game.count.get(String(Balance.PRODUCERS[i][0]), 0)) > 0:
			_draw_lot(i, lot_rect(i), night)
	_draw_hq(night)
	for p in _puffs:
		var t := float(p["t"]) / 2.4
		draw_circle(p["pos"], 3.0 + t * 7.0, Color(0.7, 0.7, 0.72, 0.28 * (1.0 - t)))
	for c in _cars:
		_draw_car(c, gy)
	for c in _customers:
		_draw_person(Vector2(float(c["x"]), gy + 14.0), c)
	if Game.vip_active:
		_draw_vip()
	for c in _coins:
		_draw_coin(c)
	for b in _bursts:
		var a := 1.0 - float(b["t"]) / 0.8
		_draw_coin_at(b["pos"], 3.5, a)
	for f in _floats:
		var t := float(f["t"]) / float(f["dur"])
		var col: Color = f["color"]
		col.a = 1.0 - t * t
		var pos: Vector2 = (f["pos"] as Vector2) + Vector2(0, -46.0 * t)
		draw_string(_font, pos + Vector2(-100, 0), f["text"], HORIZONTAL_ALIGNMENT_CENTER, 200, int(f["size"]), col)
	_draw_overlays()

func _draw_sun_moon(gy: float) -> void:
	var t := fmod(Game.play_time, DAY_CYCLE) / DAY_CYCLE
	var s := fmod(t + 0.25, 1.0)      # 0 at sunrise, 0.5 at sunset
	var frac := fmod(s, 0.5) * 2.0
	var x := lerpf(size.x * 0.08, size.x * 0.92, frac)
	var y := gy - sin(PI * frac) * gy * 0.72
	if s < 0.5:
		draw_circle(Vector2(x, y), 22.0, Color(1.0, 0.93, 0.72, 0.9))
		draw_circle(Vector2(x, y), 34.0, Color(1.0, 0.9, 0.6, 0.12))
	else:
		draw_circle(Vector2(x, y), 16.0, Color(0.92, 0.93, 0.98, 0.95))
		draw_circle(Vector2(x + 6.0, y - 4.0), 13.0, Pal.SKY_NIGHT.lerp(Color(0.92, 0.93, 0.98), 0.15))

func _draw_skyline(gy: float, night: float) -> void:
	# The far row is hazed toward the horizon and carries no windows.
	var haze := Pal.SKYLINE.lerp(Pal.HORIZON_DAY, 0.55 * (1.0 - night)).lerp(Pal.HORIZON_NIGHT, 0.55 * night)
	for b in _far:
		var fx := float(b[0]) * size.x
		var fw := float(b[1]) * size.x
		var fh := float(b[2])
		draw_rect(Rect2(fx, gy - fh, fw, fh), haze)
	for b in _skyline:
		var x := float(b[0]) * size.x
		var w := float(b[1]) * size.x
		var h := float(b[2])
		var r := Rect2(x, gy - h, w, h)
		draw_rect(r, Pal.SKYLINE)
		draw_rect(Rect2(x, gy - h, w, 2.0), Pal.SKYLINE.lightened(0.08))
		if night > 0.02:
			var seed := int(b[3])
			var cols := maxi(1, int(w / 9.0))
			var rows := maxi(1, int(h / 12.0))
			for cy in range(rows):
				for cx in range(cols):
					var hsh := (seed * 31 + cx * 17 + cy * 101) % 100
					if hsh < 38:
						draw_rect(Rect2(x + 3.0 + cx * 9.0, gy - h + 5.0 + cy * 12.0, 4.0, 5.0),
							Color(Pal.WINDOW_LIT, night * (0.35 + 0.4 * float(hsh % 7) / 7.0)))

func _draw_street(gy: float) -> void:
	draw_rect(Rect2(0, gy, size.x, 18.0), Pal.SIDEWALK)
	draw_rect(Rect2(0, gy + 17.0, size.x, 2.0), Pal.KERB)
	draw_rect(Rect2(0, gy + 19.0, size.x, size.y - gy - 19.0), Pal.ROAD)
	var mid := gy + 19.0 + (size.y - gy - 19.0) * 0.5
	var x := 0.0
	while x < size.x:
		draw_rect(Rect2(x, mid - 1.0, 22.0, 2.0), Pal.ROAD_LINE)
		x += 44.0

func _draw_hq(night: float) -> void:
	var r := hq_rect()
	var floors := hq_floors()
	var fh := hq_floor_h()
	var base := Vector2(r.get_center().x, r.end.y)
	# Squash on a sale, about the base of the building.
	var sc := Vector2(1.0 + 0.045 * _punch, 1.0 - 0.07 * _punch)
	draw_set_transform(base, 0.0, sc)
	var lr := Rect2(r.position - base, r.size)
	draw_rect(lr, Pal.HQ_WALL)
	draw_rect(Rect2(lr.position.x, lr.position.y, 3.0, lr.size.y), Pal.HQ_TRIM)
	draw_rect(Rect2(lr.end.x - 3.0, lr.position.y, 3.0, lr.size.y), Pal.HQ_TRIM)
	# Floors and windows.
	var cols := 6
	var wx := (lr.size.x - 24.0) / float(cols)
	for f in range(floors):
		var y := lr.end.y - float(f + 1) * fh
		draw_rect(Rect2(lr.position.x, y, lr.size.x, 1.0), Pal.HQ_TRIM.darkened(0.2))
		if f == 0:
			continue
		for c in range(cols):
			var hsh := (f * 13 + c * 7) % 10
			var slow := 0.5 + 0.5 * sin(Game.play_time * 0.15 + float(hsh))
			var lit := night * (0.55 + 0.45 * slow) if hsh < 7 else night * 0.15 * slow
			var glass := Pal.WINDOW_DARK.lerp(Color(0.5, 0.6, 0.7), 0.3 * (1.0 - night))
			var col := glass.lerp(Pal.WINDOW_LIT, lit)
			draw_rect(Rect2(lr.position.x + 12.0 + c * wx + 2.0, y + fh * 0.22, wx - 6.0, fh * 0.5), col)
	# Ground floor: awning, door, till glow.
	var gf := lr.end.y - fh
	draw_rect(Rect2(lr.position.x + 6.0, gf + 3.0, lr.size.x - 12.0, 5.0), Pal.CASH)
	var stripe := 0.0
	while stripe < lr.size.x - 12.0:
		draw_rect(Rect2(lr.position.x + 6.0 + stripe, gf + 3.0, 6.0, 5.0), Pal.CASH.darkened(0.35))
		stripe += 12.0
	var door := Rect2(-14.0, gf + 10.0, 28.0, fh - 10.0)
	draw_rect(door, Pal.WINDOW_DARK)
	if _till_glow > 0.0:
		draw_rect(door, Color(Pal.COIN, 0.55 * _till_glow))
	draw_rect(Rect2(lr.position.x + 14.0, gf + 9.0, 26.0, fh - 14.0), Pal.WINDOW_DARK.lerp(Pal.WINDOW_LIT, 0.35 + 0.4 * night))
	draw_rect(Rect2(lr.end.x - 40.0, gf + 9.0, 26.0, fh - 14.0), Pal.WINDOW_DARK.lerp(Pal.WINDOW_LIT, 0.35 + 0.4 * night))
	# Roof slab and sign.
	draw_rect(Rect2(lr.position.x - 4.0, lr.position.y - 4.0, lr.size.x + 8.0, 5.0), Pal.HQ_TRIM)
	var sign := Rect2(lr.position.x + 18.0, lr.position.y - 34.0, lr.size.x - 36.0, 26.0)
	draw_rect(sign, Pal.PANEL)
	draw_rect(sign, Pal.GOLD.darkened(0.2), false, 2.0)
	draw_string(_font, Vector2(sign.position.x, sign.position.y + 19.0), "MOGUL", HORIZONTAL_ALIGNMENT_CENTER, sign.size.x, 17, Pal.SIGN)
	if floors >= 8:
		var ax := lr.position.x + lr.size.x * 0.5 + 40.0
		draw_line(Vector2(ax, lr.position.y - 4.0), Vector2(ax, lr.position.y - 46.0), Pal.HQ_TRIM, 2.0)
		var blink := 0.5 + 0.5 * sin(Game.play_time * 4.0)
		draw_circle(Vector2(ax, lr.position.y - 48.0), 2.5, Color(1.0, 0.3, 0.25, 0.4 + 0.6 * blink))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Hover ring while it is the click target, and a prompt for the first few sales.
	if _hq_hover:
		draw_rect(r.grow(5.0), Color(Pal.CASH, 0.55), false, 2.0)
	if Game.clicks_all < CLICK_HINT_UNTIL:
		var pulse := 0.6 + 0.4 * sin(Game.play_time * 5.0)
		var p := Vector2(r.get_center().x, r.position.y - 44.0)
		draw_string(_font, p + Vector2(-80, 0), "CLICK TO SELL", HORIZONTAL_ALIGNMENT_CENTER, 160, 13, Color(Pal.INK, pulse))

## One lot per producer. Four silhouettes cycle down the ladder and the
## colour does the rest.
func _draw_lot(i: int, r: Rect2, night: float) -> void:
	var c := Pal.producer(i)
	var wall := Pal.HQ_WALL.lerp(c, 0.18)
	match i % 4:
		0:   # stall: counter with a striped umbrella
			var counter := Rect2(r.position.x, r.end.y - r.size.y * 0.45, r.size.x, r.size.y * 0.45)
			draw_rect(counter, wall)
			draw_rect(Rect2(counter.position.x, counter.position.y, counter.size.x, 3.0), c.darkened(0.2))
			var pole := Vector2(r.get_center().x, counter.position.y)
			draw_line(pole, Vector2(pole.x, r.position.y + 8.0), Pal.HQ_TRIM, 2.0)
			var top := Vector2(pole.x, r.position.y)
			var l := Vector2(r.position.x - 4.0, r.position.y + 12.0)
			var rt := Vector2(r.end.x + 4.0, r.position.y + 12.0)
			draw_polygon(PackedVector2Array([top, rt, l]), PackedColorArray([c, c, c]))
			draw_polygon(PackedVector2Array([top, Vector2(lerpf(l.x, rt.x, 0.33), l.y), Vector2(lerpf(l.x, rt.x, 0.66), l.y)]),
				PackedColorArray([Pal.INK, Pal.INK, Pal.INK]))
		1:   # shop: awning, window, door
			draw_rect(r, wall)
			var aw := Rect2(r.position.x - 3.0, r.position.y + r.size.y * 0.35, r.size.x + 6.0, 6.0)
			draw_rect(aw, c)
			var s := 0.0
			while s < aw.size.x:
				draw_rect(Rect2(aw.position.x + s, aw.position.y, 5.0, 6.0), c.darkened(0.4))
				s += 10.0
			draw_rect(Rect2(r.position.x + 5.0, aw.end.y + 4.0, r.size.x * 0.45, r.size.y * 0.35), Pal.WINDOW_DARK.lerp(Pal.WINDOW_LIT, 0.3 + 0.5 * night))
			draw_rect(Rect2(r.end.x - 5.0 - r.size.x * 0.25, aw.end.y + 6.0, r.size.x * 0.25, r.end.y - aw.end.y - 6.0), Pal.WINDOW_DARK)
			draw_rect(Rect2(r.position.x, r.position.y, r.size.x, r.size.y * 0.3), wall.lightened(0.08))
			draw_string(_font, Vector2(r.position.x, r.position.y + r.size.y * 0.24), "SHOP", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 9, c.lightened(0.3))
		2:   # tower: narrow, windows, coloured cap
			var tw := r.size.x * 0.7
			var t := Rect2(r.get_center().x - tw * 0.5, r.position.y - 10.0, tw, r.size.y + 10.0)
			draw_rect(t, wall)
			draw_rect(Rect2(t.position.x, t.position.y, t.size.x, 4.0), c)
			var rows := int(t.size.y / 9.0)
			for row in range(1, rows):
				for col in range(3):
					var hsh := (i * 7 + row * 5 + col * 3) % 6
					draw_rect(Rect2(t.position.x + 4.0 + col * (t.size.x - 8.0) / 3.0, t.position.y + row * 9.0, (t.size.x - 8.0) / 3.0 - 3.0, 5.0),
						Pal.WINDOW_DARK.lerp(Pal.WINDOW_LIT, (0.25 if hsh < 4 else 0.0) + 0.6 * night * (1.0 if hsh < 4 else 0.2)))
		_:   # industrial: wide, coloured roof, chimney
			var b := Rect2(r.position.x - 4.0, r.position.y + 10.0, r.size.x + 8.0, r.size.y - 10.0)
			draw_rect(b, wall)
			draw_polygon(PackedVector2Array([Vector2(b.position.x, b.position.y), Vector2(b.get_center().x, r.position.y - 2.0), Vector2(b.end.x, b.position.y)]),
				PackedColorArray([c, c, c]))
			draw_rect(Rect2(b.end.x - 12.0, r.position.y - 12.0, 6.0, 24.0), Pal.HQ_TRIM)
			draw_rect(Rect2(b.position.x + 6.0, b.position.y + 8.0, b.size.x - 12.0, 6.0), Pal.WINDOW_DARK.lerp(Pal.WINDOW_LIT, 0.2 + 0.5 * night))
	var n := int(Game.count.get(String(Balance.PRODUCERS[i][0]), 0))
	var label_y := r.position.y - 18.0 if i % 4 != 2 else r.position.y - 28.0
	var txt := "x%d" % n
	var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 11).x
	var pill := Rect2(r.get_center().x - tw * 0.5 - 5.0, label_y - 11.0, tw + 10.0, 15.0)
	draw_rect(pill, Color(Pal.PANEL, 0.82))
	draw_rect(pill, Color(c, 0.6), false, 1.0)
	draw_string(_font, Vector2(r.get_center().x - 40.0, label_y), txt, HORIZONTAL_ALIGNMENT_CENTER, 80, 11, Pal.INK)

func _draw_person(feet: Vector2, c: Dictionary) -> void:
	var h := float(c["h"])
	var ph := float(c["phase"])
	var bob := absf(sin(ph)) * 1.5
	var body := Vector2(feet.x, feet.y - 17.0 * h - bob)
	var swing := sin(ph) * 5.0
	draw_line(feet + Vector2(-swing, 0), body + Vector2(0, 7), Pal.PANEL_2.lightened(0.15), 2.5)
	draw_line(feet + Vector2(swing, 0), body + Vector2(0, 7), Pal.PANEL_2.lightened(0.15), 2.5)
	draw_rect(Rect2(body.x - 5.0, body.y - 5.0, 10.0, 13.0), c["shirt"])
	draw_circle(body + Vector2(0, -10.0 * h), 5.0, c["skin"])
	if bool(c["hat"]):
		draw_rect(Rect2(body.x - 6.0, body.y - 10.0 * h - 6.0, 12.0, 3.0), Pal.PANEL_2)

func _draw_car(c: Dictionary, gy: float) -> void:
	var road_top := gy + 19.0
	var lane_y := road_top + 14.0 + float(int(c["lane"])) * 22.0
	var x := float(c["x"])
	var l := float(c["len"])
	var col: Color = c["color"]
	draw_rect(Rect2(x - l * 0.5, lane_y - 8.0, l, 10.0), col)
	draw_rect(Rect2(x - l * 0.3, lane_y - 15.0, l * 0.55, 8.0), col.darkened(0.15))
	draw_rect(Rect2(x - l * 0.26, lane_y - 14.0, l * 0.47, 5.0), Pal.WINDOW_DARK.lerp(Pal.INK, 0.3))
	draw_circle(Vector2(x - l * 0.32, lane_y + 2.0), 3.5, Pal.VOID)
	draw_circle(Vector2(x + l * 0.32, lane_y + 2.0), 3.5, Pal.VOID)
	var front := x + l * 0.5 * float(c["dir"])
	draw_circle(Vector2(front, lane_y - 4.0), 1.6, Color(1.0, 0.95, 0.75, 0.6 + 0.4 * _night()))

func _draw_vip() -> void:
	var p := vip_pos()
	var t := Game.play_time
	var bob := absf(sin(t * 9.0)) * 2.0
	var body := Vector2(p.x, p.y - 17.0 - bob)
	var pulse := 0.5 + 0.5 * sin(t * 6.0)
	draw_circle(body, 30.0 + 4.0 * pulse, Color(Pal.GOLD, 0.10 + 0.08 * pulse))
	draw_circle(body, 18.0, Color(Pal.GOLD, 0.16))
	var swing := sin(t * 9.0) * 5.0
	draw_line(p + Vector2(-swing, 0), body + Vector2(0, 7), Pal.GOLD.darkened(0.4), 2.5)
	draw_line(p + Vector2(swing, 0), body + Vector2(0, 7), Pal.GOLD.darkened(0.4), 2.5)
	draw_rect(Rect2(body.x - 5.0, body.y - 5.0, 10.0, 13.0), Pal.GOLD)
	draw_circle(body + Vector2(0, -10.0), 4.5, Color("e9cfa2"))
	draw_rect(Rect2(body.x - 6.5, body.y - 16.0, 13.0, 3.0), Pal.PANEL_2)
	draw_rect(Rect2(body.x - 4.0, body.y - 22.0, 8.0, 6.0), Pal.PANEL_2)
	# Briefcase, and a dollar sign floating over the head.
	draw_rect(Rect2(body.x + 6.0, body.y + 2.0, 7.0, 6.0), Pal.PANEL_2.lightened(0.1))
	draw_string(_font, body + Vector2(-20, -30.0 - 3.0 * pulse), "$", HORIZONTAL_ALIGNMENT_CENTER, 40, 20, Pal.GOLD)
	# Time left on the visit.
	var left := 1.0 - Game.vip_progress()
	draw_rect(Rect2(body.x - 16.0, p.y + 8.0, 32.0, 3.0), Pal.PANEL_2)
	draw_rect(Rect2(body.x - 16.0, p.y + 8.0, 32.0 * left, 3.0), Pal.GOLD)
	if _vip_hover:
		draw_rect(Rect2(p.x - 22.0, p.y - 58.0, 44.0, 64.0), Color(Pal.GOLD, 0.7), false, 1.5)

func _draw_coin(c: Dictionary) -> void:
	var t := clampf(float(c["t"]) / float(c["dur"]), 0.0, 1.0)
	var a: Vector2 = c["a"]
	var b: Vector2 = c["b"]
	var ctrl := (a + b) * 0.5 + Vector2(0, -float(c["arc"]))
	var pos := a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t)
	_draw_coin_at(pos, 4.0, 1.0, t)

func _draw_coin_at(pos: Vector2, r: float, alpha: float, spin: float = 0.0) -> void:
	var w := r * absf(cos(spin * TAU * 1.5 + pos.x * 0.05))
	draw_set_transform(pos, 0.0, Vector2(maxf(0.25, w / r), 1.0))
	draw_circle(Vector2.ZERO, r, Color(Pal.COIN_DARK, alpha))
	draw_circle(Vector2.ZERO, r - 1.2, Color(Pal.COIN, alpha))
	draw_circle(Vector2(-r * 0.3, -r * 0.3), r * 0.28, Color(1, 1, 0.85, alpha * 0.8))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_overlays() -> void:
	if Game.rush_left > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Pal.RUSH_TINT)
		var w := 240.0
		var r := Rect2(size.x * 0.5 - w * 0.5, 10.0, w, 34.0)
		draw_rect(r, Color(Pal.PANEL, 0.9))
		draw_rect(r, Pal.GOLD, false, 1.5)
		draw_string(_font, Vector2(r.position.x, r.position.y + 17.0), "RUSH HOUR  x%d" % int(Game.rush_mult()), HORIZONTAL_ALIGNMENT_CENTER, w, 14, Pal.GOLD)
		var total := Balance.RUSH_DURATION * Game.tree_mult("rush_len")
		draw_rect(Rect2(r.position.x + 8.0, r.end.y - 8.0, (w - 16.0) * clampf(Game.rush_left / total, 0.0, 1.0), 3.0), Pal.GOLD)
	if Game.vip_active:
		var pulse := 0.6 + 0.4 * sin(Game.play_time * 7.0)
		var y := 66.0 if Game.rush_left > 0.0 else 26.0
		draw_string(_font, Vector2(size.x * 0.5 - 140.0, y), "A VIP is on the street - click them", HORIZONTAL_ALIGNMENT_CENTER, 280, 13, Color(Pal.GOLD, pulse))
