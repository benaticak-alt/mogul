extends Node
## The economy. Cash, producers, upgrades, VIPs, the cash-out prestige and the
## legacy tree all live here, and the interface only reads from it.
##
## Run state is everything Cash Out wipes. Persistent state survives it.
## Anything that changes a multiplier flips `_dirty`; income and click value
## are recomputed once, on the next read, rather than on every purchase.

signal clicked(amount: float, manual: bool)
signal vip_spawned()
signal vip_resolved(kind: String, amount: float)
signal vip_missed()
signal producer_bought(id: String, n: int)
signal upgrade_bought(id: String)
signal cashed_out(gained: int)
signal node_bought(id: String)
signal tree_completed()
signal loaded(offline_cash: float, offline_secs: float)

const SAVE_PATH := "user://mogul_save.json"
const SAVE_VERSION := 1
var save_path_override := ""     ## the round-trip test writes somewhere else
const AUTOSAVE_EVERY := 30.0

# ------------------------------------------------------------ run state
var cash := 0.0
var earned_run := 0.0
var clicks_run := 0
var run_time := 0.0
var count: Dictionary = {}       ## producer id -> owned
var owned: Dictionary = {}       ## upgrade id -> true
var rush_left := 0.0
var vip_active := false
var vip_t := 0.0
var vip_life := 0.0
var _vip_next := 0.0

# ------------------------------------------------------------ persistent
var earned_all := 0.0            ## lifetime, every run, the number legacy is cut from
var legacy_level := 0            ## legacy ever earned; the passive bonus
var legacy := 0                  ## unspent
var tree: Dictionary = {}        ## node id -> true
var runs := 0
var best_run := 0.0
var clicks_all := 0
var play_time := 0.0
var vips_caught := 0
var last_save_unix := 0

# ------------------------------------------------------------ transient
var save_enabled := true
var _autoclick_acc := 0.0
var _save_acc := 0.0
var _income := 0.0               ## per second, before Rush Hour
var _click_flat := 0.0           ## the part of a sale that ignores income
var _click_pct := 0.0            ## the slice of income each sale adds
var _dirty := true
var _fx_cache: Dictionary = {}

func _ready() -> void:
	hard_reset()
	if not load_game():
		_vip_next = Balance.VIP_WARMUP

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_game()

func _process(dt: float) -> void:
	run_time += dt
	play_time += dt
	var inc := income()
	if inc > 0.0:
		_gain(inc * dt)
	if rush_left > 0.0:
		rush_left = maxf(0.0, rush_left - dt)

	var ac := tree_max("autoclick")
	if ac > 0.0:
		_autoclick_acc += ac * dt
		while _autoclick_acc >= 1.0:
			_autoclick_acc -= 1.0
			var v := click_value()
			_gain(v)
			clicked.emit(v, false)

	if vip_active:
		vip_t += dt
		if vip_t >= vip_life:
			vip_active = false
			_schedule_vip()
			vip_missed.emit()
	else:
		_vip_next -= dt
		if _vip_next <= 0.0:
			_spawn_vip()

	_save_acc += dt
	if _save_acc >= AUTOSAVE_EVERY:
		_save_acc = 0.0
		save_game()

func _gain(v: float) -> void:
	cash += v
	earned_run += v
	earned_all += v

# ------------------------------------------------------------ multipliers

func _recalc() -> void:
	_dirty = false
	_fx_cache.clear()
	var total := 0.0
	for p in Balance.PRODUCERS:
		var id := String(p[0])
		total += producer_income(id)
	_income = total
	# Click value: the base times every doubling, plus a slice of income.
	var mult := Balance.CLICK_BASE * tree_mult("click_mult")
	var pct := tree_sum("click_pct")
	for u in Balance.upgrades:
		if u["kind"] == "click" and owned.has(u["id"]):
			mult *= float(u["mult"])
			pct += float(u["pct"])
	_click_flat = mult
	_click_pct = pct

## Everything that scales every producer at once.
func global_mult() -> float:
	var m := tree_mult("income_mult")
	for u in Balance.upgrades:
		if u["kind"] == "brand" and owned.has(u["id"]):
			m *= 1.0 + float(u["bonus"])
	m *= 1.0 + float(legacy_level) * Balance.LEVEL_BONUS * tree_mult("level_bonus_mult")
	return m

func producer_mult(id: String) -> float:
	var m := 1.0
	for t in range(Balance.TIER_OWNED.size()):
		if owned.has("%s_%d" % [id, t]):
			m *= 2.0
	return m

## What one unit of a producer pays, with every multiplier but Rush Hour.
func producer_each(id: String) -> float:
	return Balance.base_rate(id) * producer_mult(id) * global_mult()

func producer_income(id: String) -> float:
	return float(count.get(id, 0)) * producer_each(id)

func rush_mult() -> float:
	if rush_left <= 0.0:
		return 1.0
	return tree_max("rush_mult", Balance.RUSH_MULT)

func income() -> float:
	if _dirty:
		_recalc()
	return _income * rush_mult()

func base_income() -> float:
	if _dirty:
		_recalc()
	return _income

func click_value() -> float:
	if _dirty:
		_recalc()
	# The income slice of a sale rides the rush; the flat part does not.
	return _click_flat + _income * rush_mult() * _click_pct

# ------------------------------------------------------------ tree effects

func tree_has(id: String) -> bool:
	return tree.has(id)

func _fx_values(key: String) -> Array:
	if _fx_cache.has(key):
		return _fx_cache[key]
	var out: Array = []
	for n in Balance.TREE:
		if tree.has(n["id"]) and (n["fx"] as Dictionary).has(key):
			out.append(n["fx"][key])
	_fx_cache[key] = out
	return out

func tree_mult(key: String) -> float:
	var m := 1.0
	for v in _fx_values(key):
		m *= float(v)
	return m

func tree_sum(key: String) -> float:
	var s := 0.0
	for v in _fx_values(key):
		s += float(v)
	return s

func tree_max(key: String, floor_value: float = 0.0) -> float:
	var m := floor_value
	for v in _fx_values(key):
		m = maxf(m, float(v))
	return m

func discount() -> float:
	return 1.0 - tree_sum("discount")

# ------------------------------------------------------------ shop

func cost_of(id: String, k: int = 1) -> float:
	var n := int(count.get(id, 0))
	var g := Balance.COST_GROWTH
	var first := Balance.base_cost(id) * pow(g, float(n)) * discount()
	if k <= 1:
		return first
	return first * (pow(g, float(k)) - 1.0) / (g - 1.0)

func max_affordable(id: String) -> int:
	var first := cost_of(id, 1)
	if cash < first:
		return 0
	var g := Balance.COST_GROWTH
	var k := int(floor(log(cash * (g - 1.0) / first + 1.0) / log(g)))
	# Float error can land one unit either side of the true answer.
	while k > 0 and cost_of(id, k) > cash:
		k -= 1
	while cost_of(id, k + 1) <= cash:
		k += 1
	return k

func buy_producer(id: String, k: int = 1) -> bool:
	if k <= 0:
		return false
	var c := cost_of(id, k)
	if cash < c:
		return false
	cash -= c
	count[id] = int(count.get(id, 0)) + k
	_dirty = true
	producer_bought.emit(id, k)
	return true

## Producers the shop should show. Everything owned or nearly affordable,
## plus the next one as a locked teaser.
func producer_visible(i: int) -> bool:
	if i == 0:
		return true
	var id := String(Balance.PRODUCERS[i][0])
	if int(count.get(id, 0)) > 0:
		return true
	return earned_run >= Balance.base_cost(id) * Balance.REVEAL_FRACTION

func upgrade_unlocked(u: Dictionary) -> bool:
	match String(u["kind"]):
		"producer":
			return int(count.get(u["target"], 0)) >= int(Balance.TIER_OWNED[int(u["tier"])])
		"click":
			return earned_run >= float(u["cost"]) * Balance.CLICK_REVEAL
		"brand":
			return earned_run >= float(u["cost"]) * Balance.BRAND_REVEAL
	return false

func available_upgrades() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u in Balance.upgrades:
		if not owned.has(u["id"]) and upgrade_unlocked(u):
			out.append(u)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["cost"]) < float(b["cost"]))
	return out

func upgrade_cost(u: Dictionary) -> float:
	return float(u["cost"]) * discount()

func buy_upgrade(id: String) -> bool:
	var u: Dictionary = Balance.upgrade_by_id.get(id, {})
	if u.is_empty() or owned.has(id) or not upgrade_unlocked(u):
		return false
	var c := upgrade_cost(u)
	if cash < c:
		return false
	cash -= c
	owned[id] = true
	_dirty = true
	upgrade_bought.emit(id)
	return true

## Income an upgrade would add per second, given how often the player is
## clicking. Used by the shop tooltip and by the bot's shopping list.
func upgrade_value(u: Dictionary, clicks_per_sec: float = 0.0) -> float:
	match String(u["kind"]):
		"producer":
			return producer_income(u["target"]) * (float(u["mult"]) - 1.0)
		"click":
			var cv := click_value()
			return (cv * (float(u["mult"]) - 1.0) + base_income() * float(u["pct"])) * clicks_per_sec
		"brand":
			# The bonus multiplies the whole stack, so it is worth its share
			# of everything already being earned.
			return base_income() * float(u["bonus"]) / (1.0 + _brand_total())
	return 0.0

func _brand_total() -> float:
	var s := 0.0
	for u in Balance.upgrades:
		if u["kind"] == "brand" and owned.has(u["id"]):
			s += float(u["bonus"])
	return s

func owned_upgrades() -> int:
	return owned.size()

func total_producers() -> int:
	var n := 0
	for v in count.values():
		n += int(v)
	return n

# ------------------------------------------------------------ sales

func click() -> float:
	var v := click_value()
	_gain(v)
	clicks_run += 1
	clicks_all += 1
	clicked.emit(v, true)
	return v

# ------------------------------------------------------------ VIPs

func _spawn_vip() -> void:
	vip_active = true
	vip_t = 0.0
	vip_life = Balance.VIP_LINGER * tree_mult("vip_linger")
	vip_spawned.emit()

func _schedule_vip() -> void:
	_vip_next = randf_range(Balance.VIP_MIN, Balance.VIP_MAX) / tree_mult("vip_freq")

func vip_progress() -> float:
	return clampf(vip_t / maxf(0.001, vip_life), 0.0, 1.0)

func windfall_amount() -> float:
	var inc := base_income()
	var v := minf(cash * Balance.WINDFALL_BANK, inc * Balance.WINDFALL_CAP)
	v += inc * Balance.WINDFALL_FLOOR
	v = maxf(v, Balance.WINDFALL_MIN)
	return v * tree_mult("windfall_mult")

## The player caught the VIP. Half the time it is a lump sum, half the time
## it is a Rush Hour; a second VIP during a rush always pays cash so the
## effect does not just get re-rolled.
func click_vip() -> void:
	if not vip_active:
		return
	vip_active = false
	vips_caught += 1
	_schedule_vip()
	if rush_left <= 0.0 and randf() < 0.5:
		rush_left = Balance.RUSH_DURATION * tree_mult("rush_len")
		vip_resolved.emit("rush", rush_mult())
	else:
		var v := windfall_amount()
		_gain(v)
		vip_resolved.emit("windfall", v)

# ------------------------------------------------------------ cash out

## Legacy the lifetime earnings are worth in total.
func legacy_potential() -> int:
	var raw := pow(earned_all / Balance.LEGACY_BASE, Balance.LEGACY_POWER)
	return int(floor(raw * (1.0 + tree_sum("legacy_bonus"))))

func legacy_gain() -> int:
	return maxi(0, legacy_potential() - legacy_level)

func can_cash_out() -> bool:
	return legacy_gain() >= 1

## Dollars of lifetime earnings needed for the next legacy point.
func next_legacy_at() -> float:
	var target := float(legacy_level + 1) / (1.0 + tree_sum("legacy_bonus"))
	return pow(target, 1.0 / Balance.LEGACY_POWER) * Balance.LEGACY_BASE

func cash_out() -> int:
	var gain := legacy_gain()
	if gain < 1:
		return 0
	legacy += gain
	legacy_level += gain
	runs += 1
	best_run = maxf(best_run, earned_run)
	_reset_run()
	cashed_out.emit(gain)
	save_game()
	return gain

## Wipes the run and applies every Head Start perk.
func _reset_run() -> void:
	cash = tree_sum("start_cash") + best_run * tree_sum("start_best_pct")
	earned_run = 0.0
	clicks_run = 0
	run_time = 0.0
	count.clear()
	owned.clear()
	rush_left = 0.0
	vip_active = false
	_autoclick_acc = 0.0
	_schedule_vip()
	for n in Balance.TREE:
		if tree.has(n["id"]) and (n["fx"] as Dictionary).has("start_producers"):
			var sp: Dictionary = n["fx"]["start_producers"]
			for id in sp:
				count[id] = int(count.get(id, 0)) + int(sp[id])
	_dirty = true

# ------------------------------------------------------------ legacy tree

func node_owned(id: String) -> bool:
	return tree.has(id)

func node_unlocked(id: String) -> bool:
	var n := Balance.node(id)
	if n.is_empty():
		return false
	var parent := String(n["parent"])
	return parent == "" or tree.has(parent)

func node_can_buy(id: String) -> bool:
	return not tree.has(id) and node_unlocked(id) and legacy >= int(Balance.node(id)["cost"])

func buy_node(id: String) -> bool:
	if not node_can_buy(id):
		return false
	legacy -= int(Balance.node(id)["cost"])
	tree[id] = true
	_dirty = true
	node_bought.emit(id)
	if tree_complete():
		tree_completed.emit()
	save_game()
	return true

func tree_progress() -> Vector2i:
	return Vector2i(tree.size(), Balance.TREE.size())

func tree_complete() -> bool:
	return tree.size() >= Balance.TREE.size()

# ------------------------------------------------------------ persistence

func hard_reset() -> void:
	cash = 0.0
	earned_run = 0.0
	clicks_run = 0
	run_time = 0.0
	count.clear()
	owned.clear()
	rush_left = 0.0
	vip_active = false
	earned_all = 0.0
	legacy_level = 0
	legacy = 0
	tree.clear()
	runs = 0
	best_run = 0.0
	clicks_all = 0
	play_time = 0.0
	vips_caught = 0
	_vip_next = Balance.VIP_WARMUP
	_autoclick_acc = 0.0
	_dirty = true

func wipe_save() -> void:
	hard_reset()
	if FileAccess.file_exists(_save_path()):
		DirAccess.remove_absolute(_save_path())

func _save_path() -> String:
	return save_path_override if save_path_override != "" else SAVE_PATH

func save_game() -> void:
	if not save_enabled:
		return
	last_save_unix = int(Time.get_unix_time_from_system())
	var d := {
		"v": SAVE_VERSION,
		"cash": cash, "earned_run": earned_run, "clicks_run": clicks_run,
		"run_time": run_time, "count": count, "owned": owned.keys(),
		"rush_left": rush_left, "vip_next": _vip_next,
		"earned_all": earned_all, "legacy_level": legacy_level, "legacy": legacy,
		"tree": tree.keys(), "runs": runs, "best_run": best_run,
		"clicks_all": clicks_all, "play_time": play_time, "vips_caught": vips_caught,
		"saved": last_save_unix,
		"muted": SFX.muted,
	}
	var f := FileAccess.open(_save_path(), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(d))
	f.close()

func load_game() -> bool:
	if not FileAccess.file_exists(_save_path()):
		return false
	var f := FileAccess.open(_save_path(), FileAccess.READ)
	if f == null:
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary) or int(parsed.get("v", 0)) != SAVE_VERSION:
		return false
	var d: Dictionary = parsed
	hard_reset()
	cash = float(d.get("cash", 0.0))
	earned_run = float(d.get("earned_run", 0.0))
	clicks_run = int(d.get("clicks_run", 0))
	run_time = float(d.get("run_time", 0.0))
	for k in (d.get("count", {}) as Dictionary):
		count[String(k)] = int(d["count"][k])
	for k in (d.get("owned", []) as Array):
		owned[String(k)] = true
	rush_left = float(d.get("rush_left", 0.0))
	_vip_next = float(d.get("vip_next", Balance.VIP_WARMUP))
	earned_all = float(d.get("earned_all", 0.0))
	legacy_level = int(d.get("legacy_level", 0))
	legacy = int(d.get("legacy", 0))
	for k in (d.get("tree", []) as Array):
		tree[String(k)] = true
	runs = int(d.get("runs", 0))
	best_run = float(d.get("best_run", 0.0))
	clicks_all = int(d.get("clicks_all", 0))
	play_time = float(d.get("play_time", 0.0))
	vips_caught = int(d.get("vips_caught", 0))
	SFX.muted = bool(d.get("muted", false))
	_dirty = true

	# Away earnings. Rush Hour does not run while the game is closed.
	var saved := int(d.get("saved", 0))
	var away := float(int(Time.get_unix_time_from_system()) - saved)
	rush_left = 0.0
	if saved > 0 and away >= Balance.OFFLINE_MIN:
		var rate := tree_max("offline_rate", Balance.OFFLINE_RATE)
		var cap := tree_max("offline_cap", Balance.OFFLINE_CAP)
		var gain := base_income() * minf(away, cap) * rate
		if gain > 0.0:
			_gain(gain)
		# Autoloads are ready before the scene that shows the banner is, so
		# this is parked for Main to collect rather than only signalled.
		offline_report = {"cash": gain, "secs": away}
		loaded.emit(gain, away)
	return true

## Set by load_game when the player was away long enough to matter; Main
## reads and clears it once the interface exists.
var offline_report: Dictionary = {}
