extends RefCounted
## Headless verification bot.
##
## It drives the real Game autoload rather than a separate model of the
## economy, so what it measures is what ships. Balance changes are checked
## with:
##
##   Godot_v4.7.2-stable_win64.exe --headless --path . -- --autoplay 6 [--acc 0.8]
##
## The policy is deliberately plain - play the deal minigame at a fixed
## accuracy, buy whatever pays back soonest counting the wait to afford it,
## catch most VIPs, cash out when the level would grow by a set fraction, and
## spend legacy cheapest-first. A patient player does better; a casual one
## does worse.
##
## The bot plays the minigame rather than calling the payout directly, so the
## deal cycle time really does cap how much clicking can contribute - which is
## the whole point of making a sale take a second and a half.

const DT := 0.25
const DEAL_ACCURACY := 0.8     ## how often the bot lands inside the green
const SHOP_EVERY := 4          ## steps between shopping trips - once a second
const VIP_CATCH := 0.75        ## how often the bot notices a VIP in time
const REPORT_EVERY := 600.0
const FIRST_CASHOUT := 3       ## legacy the first cash out must be worth
const CASHOUT_RATIO := 0.6     ## later ones must grow the level by this much
const MILESTONES := [1.0e3, 1.0e6, 1.0e9, 1.0e12, 1.0e15, 1.0e18]

var accuracy := DEAL_ACCURACY
var deal_rate := 0.7           ## observed deals/sec, fed to the shopping score
var _deals := 0
var _perfects := 0

func run(max_hours: float) -> void:
	Game.set_process(false)
	Game.save_enabled = false
	Game.hard_reset()
	seed(4)
	var args := OS.get_cmdline_user_args()
	var at := args.find("--acc")
	if at >= 0 and at + 1 < args.size():
		accuracy = clampf(float(args[at + 1]), 0.0, 1.0)
	_say(0.0, "policy: deals at %d%% accuracy, catch %d%% of VIPs, cash out at +%d then +%d%% of level" % [
		int(accuracy * 100.0), int(VIP_CATCH * 100.0), FIRST_CASHOUT, int(CASHOUT_RATIO * 100.0)])

	var limit := max_hours * 3600.0
	var t := 0.0
	var step := 0
	var deal_decided := false
	var deal_will_hit := false
	var vip_decided := false
	var next_report := REPORT_EVERY
	var ms_i := 0
	var mark := _mark(t)
	var run_lengths: Array[float] = []

	_say(t, "open for business")
	_header()
	while t < limit and not Game.tree_complete():
		# The deal minigame. The bot commits to an outcome when a deal opens
		# and then acts on it, rather than being at the mercy of the step
		# size: a 0.25s step cannot reliably land inside a 0.25s window, and
		# what is being measured here is a player's accuracy, not the
		# simulation's resolution.
		if Game.deal_active:
			if not deal_decided:
				deal_decided = true
				deal_will_hit = randf() < accuracy
			if deal_will_hit:
				if Game.deal_t >= Game.deal_zone:
					Game.deal_t = Game.deal_zone + Game.zone_width() * 0.5
					_close_deal()
			elif Game.deal_t >= Game.deal_zone * 0.6:
				# Snap clear of the green before closing. Late in a run the
				# cycle is short and the zone is wide enough that a step can
				# land inside it by accident, which quietly turned the bot
				# into a better player than it was being asked to be.
				Game.deal_t = maxf(0.0, Game.deal_zone - 0.02)
				_close_deal()
		else:
			Game.tap()
			deal_decided = false
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
		deal_rate = float(_deals) / maxf(1.0, t)

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

## Counts what actually happened rather than what was intended, so the report
## can never flatter the policy.
func _close_deal() -> void:
	var hit := Game.in_zone()
	Game.tap()
	_deals += 1
	if hit:
		_perfects += 1

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
	_p("            top earner %s (%s of income)  -  global %s  -  deal %s" % [
		lead[0], Fmt.pct(float(lead[1])), Fmt.mult(Game.global_mult()), Fmt.cash(Game.click_value())])
	_p("            deals %-7s %.2f/s  perfect %-6s cycle %-7s zone %-6s best combo %d" % [
		Fmt.count(float(_deals)), deal_rate,
		Fmt.pct(float(_perfects) / maxf(1.0, float(_deals))),
		"%.2fs" % Game.deal_time(), Fmt.pct(Game.zone_width()), Game.best_combo])

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
	_p("deals: %s closed, %s inside the green, %.2f/s, best streak %d" % [
		Fmt.count(float(_deals)), Fmt.pct(float(_perfects) / maxf(1.0, float(_deals))),
		deal_rate, Game.best_combo])

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
	var inc := maxf(Game.income() + Game.click_value() * deal_rate, 0.001)
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
		var delta := Game.upgrade_value(u, deal_rate)
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
