extends RefCounted
## Headless verification bot.
##
## It drives the real Game autoload rather than a separate model of the
## economy, so what it measures is what ships. Balance changes are checked
## with:
##
##   Godot_v4.7.2-stable_win64.exe --headless --path . -- --autoplay 6 [--cps 3]
##
## The policy is deliberately plain - click at a steady rate, buy whatever
## pays back soonest counting the wait to afford it, catch most VIPs, cash
## out when the level would grow by a set fraction, and spend legacy
## cheapest-first. A patient player does better; a casual one does worse.

const DT := 0.25
const CLICK_RATE := 3.0        ## manual sales per second, sustained
const SHOP_EVERY := 4          ## steps between shopping trips - once a second
const VIP_CATCH := 0.75        ## how often the bot notices a VIP in time
const REPORT_EVERY := 600.0
const FIRST_CASHOUT := 3       ## legacy the first cash out must be worth
const CASHOUT_RATIO := 0.6     ## later ones must grow the level by this much
const MILESTONES := [1.0e3, 1.0e6, 1.0e9, 1.0e12, 1.0e15, 1.0e18]

var click_rate := CLICK_RATE

func run(max_hours: float) -> void:
	Game.set_process(false)
	Game.save_enabled = false
	Game.hard_reset()
	seed(4)
	var args := OS.get_cmdline_user_args()
	var at := args.find("--cps")
	if at >= 0 and at + 1 < args.size():
		click_rate = float(args[at + 1])
	_say(0.0, "policy: %.1f sales/s, catch %d%% of VIPs, cash out at +%d then +%d%% of level" % [
		click_rate, int(VIP_CATCH * 100.0), FIRST_CASHOUT, int(CASHOUT_RATIO * 100.0)])

	var limit := max_hours * 3600.0
	var t := 0.0
	var step := 0
	var click_acc := 0.0
	var vip_decided := false
	var next_report := REPORT_EVERY
	var ms_i := 0
	var mark := _mark(t)
	var run_lengths: Array[float] = []

	_say(t, "open for business")
	_header()
	while t < limit and not Game.tree_complete():
		click_acc += click_rate * DT
		while click_acc >= 1.0:
			click_acc -= 1.0
			Game.click()
		if step % SHOP_EVERY == 0:
			_shop()
		if Game.vip_active:
			if not vip_decided and Game.vip_t > 1.5:
				vip_decided = true
				if randf() < VIP_CATCH:
					Game.click_vip()
		else:
			vip_decided = false
		Game._process(DT)
		t += DT
		step += 1

		while ms_i < MILESTONES.size() and Game.earned_all >= float(MILESTONES[ms_i]):
			_say(t, "   first %s lifetime  (run %d, level %d)" % [Fmt.cash(float(MILESTONES[ms_i])), Game.runs + 1, Game.legacy_level])
			ms_i += 1

		var gain := Game.legacy_gain()
		var want := maxi(FIRST_CASHOUT, int(ceil(float(Game.legacy_level) * CASHOUT_RATIO)))
		if gain >= want:
			run_lengths.append(t - float(mark["t"]))
			_run_line(t, mark, gain)
			Game.cash_out()
			_spend(t)
			mark = _mark(t)

		if t >= next_report:
			next_report += REPORT_EVERY
			_say(t, "   ... run %-3d lv %-5d cash %-10s %-12s biz %-4d upg %-3d perks %d" % [
				Game.runs + 1, Game.legacy_level, Fmt.cash(Game.cash), Fmt.per_sec(Game.income()),
				Game.total_producers(), Game.owned_upgrades(), Game.tree_progress().x])

	if Game.tree_complete():
		_say(t, "*** TREE COMPLETE ***")
	else:
		_say(t, "!! out of time in run %d at level %d (%s lifetime)" % [Game.runs + 1, Game.legacy_level, Fmt.cash(Game.earned_all)])
	_summary(t, run_lengths)

# ------------------------------------------------------------ reporting

func _mark(t: float) -> Dictionary:
	return {"t": t, "earned": Game.earned_all, "level": Game.legacy_level}

func _header() -> void:
	_p("          run   length    earned         +legacy  level   income@end    biz   upg  perks")

func _run_line(t: float, mark: Dictionary, gain: int) -> void:
	var span := t - float(mark["t"])
	_p("[%s] %-4d  %-8s  %-13s  +%-6d  %-6d  %-12s  %-4d  %-3d  %d" % [
		Fmt.time(t).lpad(8), Game.runs + 1, Fmt.time(span), Fmt.cash(Game.earned_run), gain,
		Game.legacy_level + gain, Fmt.per_sec(Game.base_income()), Game.total_producers(),
		Game.owned_upgrades(), Game.tree_progress().x])
	var lead := _leader()
	_p("            top earner %s (%s of income)  -  global %s  -  sale %s" % [
		lead[0], Fmt.pct(float(lead[1])), Fmt.mult(Game.global_mult()), Fmt.cash(Game.click_value())])

func _leader() -> Array:
	var best := ""
	var share := 0.0
	var inc := maxf(0.0001, Game.base_income())
	for p in Balance.PRODUCERS:
		var s := Game.producer_income(String(p[0])) / inc
		if s > share:
			share = s
			best = String(p[1])
	return [best, share]

func _summary(t: float, runs: Array[float]) -> void:
	_p("")
	_p("total %s over %d cash outs, level %d, %s lifetime" % [
		Fmt.time(t), Game.runs, Game.legacy_level, Fmt.cash(Game.earned_all)])
	if not runs.is_empty():
		var lo := INF
		var hi := 0.0
		var sum := 0.0
		for r in runs:
			lo = minf(lo, r)
			hi = maxf(hi, r)
			sum += r
		_p("runs: shortest %s, longest %s, mean %s" % [Fmt.time(lo), Fmt.time(hi), Fmt.time(sum / float(runs.size()))])
	var perks := PackedStringArray()
	for n in Balance.TREE:
		if Game.tree_has(n["id"]):
			perks.append(String(n["name"]))
	_p("perks: " + (", ".join(perks) if not perks.is_empty() else "none"))

func _say(t: float, s: String) -> void:
	_p("[%s] %s" % [Fmt.time(t).lpad(8), s])

func _p(s: String) -> void:
	print(s)

# ------------------------------------------------------------ policy

## One purchase per trip at most, and only the best one. The score is the
## wait to afford it plus the payback once bought; if the best thing is
## still out of reach the bot saves for it rather than buying something
## worse that it can afford now.
func _shop() -> void:
	var inc := maxf(Game.income() + Game.click_value() * click_rate, 0.001)
	var best_score := INF
	var best_kind := ""
	var best_id := ""
	for p in Balance.PRODUCERS:
		var id := String(p[0])
		var cost := Game.cost_of(id, 1)
		var delta := Game.producer_each(id)
		var score := maxf(0.0, cost - Game.cash) / inc + cost / maxf(delta, 0.000001)
		if score < best_score:
			best_score = score
			best_kind = "producer"
			best_id = id
	for u in Game.available_upgrades():
		var cost := Game.upgrade_cost(u)
		var delta := Game.upgrade_value(u, click_rate)
		if delta <= 0.0:
			continue
		var score := maxf(0.0, cost - Game.cash) / inc + cost / delta
		if score < best_score:
			best_score = score
			best_kind = "upgrade"
			best_id = String(u["id"])
	if best_kind == "producer":
		if Game.cash >= Game.cost_of(best_id, 1):
			Game.buy_producer(best_id, 1)
	elif best_kind == "upgrade":
		var u: Dictionary = Balance.upgrade_by_id[best_id]
		if Game.cash >= Game.upgrade_cost(u):
			Game.buy_upgrade(best_id)

## Cheapest perk first. Costs climb along every spoke, so this walks all
## five in step and reaches the expensive ends about when a player would.
func _spend(t: float) -> void:
	while true:
		var cheapest := ""
		var best := 1 << 30
		for n in Balance.TREE:
			var id := String(n["id"])
			if Game.node_can_buy(id) and int(n["cost"]) < best:
				best = int(n["cost"])
				cheapest = id
		if cheapest == "":
			break
		Game.buy_node(cheapest)
		_say(t, "   perk: %s (%d)  -  %d left" % [String(Balance.node(cheapest)["name"]), best, Game.legacy])
