extends Node
## All tuning lives here.
##
## The producer ladder and its upgrade tiers are regular enough that the
## tables carry shape and flavour and everything else is derived at boot.
## Change a constant, then confirm the pacing with the in-engine bot rather
## than by eye:
##
##   Godot_v4.7.2-stable_win64.exe --headless --path . -- --autoplay 6
##
## There is deliberately no JSON and no Python step: the numbers the bot
## measures are the numbers the game ships with.

# ----------------------------------------------------------------- the deal
# A sale is a little timing game rather than a mash. The first click opens a
# deal and a marker starts running along a bar; a second click inside the
# green zone closes it for a multiple and extends your streak. Click early and
# you take the base. Sit on your hands and the customer walks.
#
# The cycle time is the real pacing lever here: it sets how often the player
# is asked to do anything at all, and a game that asks every 0.4s is a mash
# with extra steps.
const DEAL_TIME := 1.45        ## seconds for the marker to cross the bar
const DEAL_TIME_MIN := 0.60    ## however many speed upgrades, never under this
const ZONE_WIDTH := 0.17       ## the green zone, as a fraction of the bar
const ZONE_MIN := 0.40         ## placed somewhere in this span, so the timing
const ZONE_MAX := 0.86         ## is never quite the same twice
const PERFECT_MULT := 2.5      ## payout for closing inside the zone
const WALKED_MULT := 0.5       ## payout if the marker runs off the end
const COMBO_STEP := 0.15       ## payout bonus per consecutive clean close
const COMBO_CAP := 10
const COMBO_GRACE := 2.6       ## seconds idle before a streak lapses

# ----------------------------------------------------------------- shape
const COST_GROWTH := 1.15      ## producer price, per unit owned
const CLICK_BASE := 1.0        ## dollars per deal before anything
const LEGACY_BASE := 1.0e6     ## lifetime dollars behind the first legacy point
const LEGACY_POWER := 0.5        ## square root: doubling the level takes 4x the earnings
const LEVEL_BONUS := 0.02      ## income per legacy level, forever

# ----------------------------------------------------------------- producers
# id, name, base cost, base $/s, blurb. The cost ladder is the classic
# fifteen-to-fourteen-trillion one: it has been played for a decade and it is
# not the part of this game that needs to be clever.
const PRODUCERS := [
	["lemonade", "Lemonade Stand",  15.0,     0.1,       "Fifty cents a cup. Everyone starts somewhere."],
	["paper",    "Paper Route",     100.0,    1.0,       "Up before dawn, done before school."],
	["cart",     "Food Cart",       1100.0,   8.0,       "Hot dogs, onions, and a corner nobody else wanted."],
	["store",    "Corner Store",    12000.0,  47.0,      "Open late, sells everything, knows your name."],
	["carwash",  "Car Wash",        130000.0, 260.0,     "Hot wax extra. It is always extra."],
	["diner",    "Diner",           1.4e6,    1400.0,    "Coffee, pie, and a booth that has seen things."],
	["franchise","Franchise",       20.0e6,   7800.0,    "Same sign in every town. That is the point."],
	["shipping", "Shipping Line",   330.0e6,  44000.0,   "If it fits in a container, it is yours to move."],
	["startup",  "Tech Startup",    5.1e9,    260000.0,  "Pre-revenue, post-money, all upside."],
	["bank",     "Bank",            75.0e9,   1.6e6,     "Other people's money, at scale."],
	["fund",     "Hedge Fund",      1.0e12,   10.0e6,    "Two and twenty, and nobody asks how."],
	["orbital",  "Orbital Mining",  14.0e12,  65.0e6,    "The asteroid belt does not have a zoning board."],
]

## A producer shows in the shop once the run has earned this fraction of its
## price; the one after the last visible shows locked, so there is always a
## next thing to want.
const REVEAL_FRACTION := 0.2

# ----------------------------------------------------------------- upgrades
# Producer tiers: owning N of a producer unlocks a doubling for it, priced as
# a multiple of the producer's base cost.
const TIER_OWNED := [1, 10, 25, 50, 100, 150]
const TIER_COST := [10.0, 50.0, 500.0, 5000.0, 50000.0, 500000.0]
const TIER_NAMES := {
	"lemonade":  ["Fresh Lemons", "Bigger Pitcher", "Ice Machine", "Secret Recipe", "Lemonade Franchise", "Citrus Cartel"],
	"paper":     ["Faster Bike", "Second Route", "Sunday Edition", "Subscription Drive", "Delivery Fleet", "Print Empire"],
	"cart":      ["Better Grill", "Second Cart", "Late Night Hours", "Signature Sauce", "Food Truck Fleet", "Street Food Dynasty"],
	"store":     ["Longer Hours", "Lottery Tickets", "Self Checkout", "Second Location", "Loyalty Cards", "Neighborhood Chain"],
	"carwash":   ["Hot Wax", "Tunnel Wash", "Detailing Bay", "Monthly Pass", "Fleet Contracts", "Wash Nation"],
	"diner":     ["Bottomless Coffee", "Breakfast All Day", "Pie Case", "Jukebox", "Catering Wing", "Diner Chain"],
	"franchise": ["Drive-Thru", "Value Menu", "Regional Rollout", "Mascot", "Global Franchising", "Golden Standard"],
	"shipping":  ["Container Ships", "Port Authority", "Air Freight", "Overnight Guarantee", "Logistics Network", "Trade Winds"],
	"startup":   ["Series A", "The App", "Growth Hacking", "Unicorn Status", "Platform Play", "The IPO"],
	"bank":      ["Savings Accounts", "Credit Cards", "Mortgage Desk", "Investment Banking", "Central Bank Ties", "Too Big To Fail"],
	"fund":      ["Quant Desk", "Leverage", "Dark Pool", "Algorithmic Trading", "Sovereign Clients", "Market Maker"],
	"orbital":   ["Asteroid Claims", "Mass Driver", "Helium-3", "Lunar Refinery", "Belt Consortium", "Solar Monopoly"],
}

# Deals. id, name, cost, payout multiplier, fraction of income added per
# deal, extra green zone (fraction of the bar), cycle speed-up, blurb.
# Unlocked once the run has earned a quarter of the price, so they appear a
# little before they can be had.
#
# Every one of these doubles the payout - that is the part the balance rests
# on - and some also make the minigame itself kinder, so the tab has texture
# beyond a column of identical doublings.
const CLICK_UPGRADES := [
	["handshake", "Firm Handshake",     100.0,    2.0, 0.00, 0.00, 1.00, "People buy from people they like."],
	["pitch",     "Sales Pitch",        1000.0,   2.0, 0.00, 0.05, 1.00, "Thirty seconds, one hook, no pauses."],
	["upsell",    "The Upsell",         25000.0,  2.0, 0.02, 0.00, 0.90, "Would you like fries with that? You would."],
	["loyalty",   "Loyalty Program",    1.0e6,    2.0, 0.02, 0.04, 1.00, "Buy nine, the tenth is on us. Mostly."],
	["closer",    "Closing Bonus",      50.0e6,   2.0, 0.03, 0.00, 0.88, "Coffee is for closers."],
	["rolodex",   "Golden Rolodex",     5.0e9,    2.0, 0.03, 0.04, 1.00, "Every number that matters, and a few that should not."],
	["lunch",     "Power Lunch",        500.0e9,  2.0, 0.04, 0.05, 1.00, "The deal was done before the appetisers."],
	["boardroom", "Boardroom Presence", 100.0e12, 2.0, 0.05, 0.00, 0.86, "You do not raise your voice. You do not have to."],
]
const CLICK_REVEAL := 0.25

# Brand. id, name, cost, income bonus, blurb. Same reveal rule.
const BRAND_UPGRADES := [
	["cards",     "Business Cards", 5000.0,   0.05, "Heavy stock. Embossed. Tasteful."],
	["flyers",    "Local Ads",      100.0e3,  0.10, "Under every windscreen wiper in town."],
	["billboard", "Billboards",     5.0e6,    0.10, "Forty feet of your face on the interstate."],
	["tv",        "TV Spots",       250.0e6,  0.15, "A jingle nobody can get out of their head."],
	["biggame",   "Big Game Ad",    20.0e9,   0.15, "Thirty seconds. Nine figures. Worth it."],
	["global",    "Global Brand",   2.0e12,   0.20, "Recognised in languages you do not speak."],
	["household", "Household Name", 200.0e12, 0.25, "Your name is a verb now."],
	["icon",      "Cultural Icon",  20.0e15,  0.30, "There are documentaries. Several."],
]
const BRAND_REVEAL := 0.25

# ----------------------------------------------------------------- VIPs
# A gold customer crosses the street now and then. Click them for a windfall
# or a rush hour; miss them and they walk off.
const VIP_MIN := 75.0          ## seconds between VIPs, lower bound
const VIP_MAX := 170.0
const VIP_LINGER := 11.0       ## seconds on screen
const VIP_WARMUP := 60.0       ## no VIP in the first minute of a fresh save
const RUSH_MULT := 7.0
const RUSH_DURATION := 40.0
const WINDFALL_BANK := 0.20    ## fraction of the bank a windfall can pay...
const WINDFALL_CAP := 600.0    ## ...capped at this many seconds of income
const WINDFALL_FLOOR := 30.0   ## plus this many seconds of income regardless
const WINDFALL_MIN := 25.0     ## and never less than this many dollars

# ----------------------------------------------------------------- offline
const OFFLINE_RATE := 0.25
const OFFLINE_CAP := 2.0 * 3600.0
const OFFLINE_MIN := 60.0      ## shorter absences do not get a banner

# ----------------------------------------------------------------- legacy tree
# Five spokes off a hub. `ring` is the distance from the hub, `parent` the
# node that must be owned first. `fx` is read by Game through tree_mult /
# tree_sum / tree_max / tree_get, so a new effect is a new key here and one
# line where it is consumed.
const BRANCHES := {
	"operations": {"name": "Operations", "angle": 198.0},
	"sales":      {"name": "Salesmanship", "angle": -18.0},
	"start":      {"name": "Head Start", "angle": -90.0},
	"fortune":    {"name": "Fortune", "angle": 54.0},
	"legacy":     {"name": "Legacy", "angle": 126.0},
}

const TREE := [
	# operations - raw income
	{"id": "lean", "name": "Lean Operations", "branch": "operations", "ring": 1, "cost": 1, "parent": "",
		"desc": "All income +10%.", "fx": {"income_mult": 1.10}},
	{"id": "scale", "name": "Economies of Scale", "branch": "operations", "ring": 2, "cost": 5, "parent": "lean",
		"desc": "All income +25%.", "fx": {"income_mult": 1.25}},
	{"id": "vertical", "name": "Vertical Integration", "branch": "operations", "ring": 3, "cost": 25, "parent": "scale",
		"desc": "All income +50%.", "fx": {"income_mult": 1.50}},
	{"id": "monopoly", "name": "Monopoly", "branch": "operations", "ring": 4, "cost": 150, "parent": "vertical",
		"desc": "All income doubled.", "fx": {"income_mult": 2.0}},
	{"id": "conglomerate", "name": "Conglomerate", "branch": "operations", "ring": 5, "cost": 500, "parent": "monopoly",
		"desc": "Each legacy level pays +2% income instead of +1%.", "fx": {"level_bonus_mult": 2.0}},
	# sales - manual sales
	{"id": "tongue", "name": "Silver Tongue", "branch": "sales", "ring": 1, "cost": 1, "parent": "",
		"desc": "Deals pay double.", "fx": {"click_mult": 2.0}},
	{"id": "closer_t", "name": "Closer", "branch": "sales", "ring": 2, "cost": 8, "parent": "tongue",
		"desc": "Each deal also earns 1% of your income, and the green zone is half again as wide.",
		"fx": {"click_pct": 0.01, "zone_mult": 1.5}},
	{"id": "hardsell", "name": "Hard Sell", "branch": "sales", "ring": 3, "cost": 40, "parent": "closer_t",
		"desc": "Deals pay triple, and close a third faster.",
		"fx": {"click_mult": 3.0, "deal_speed": 0.67}},
	{"id": "autodialer", "name": "Autodialer", "branch": "sales", "ring": 4, "cost": 120, "parent": "hardsell",
		"desc": "Grinds out 2 base sales a second on its own - no streak, but it never stops.",
		"fx": {"autoclick": 2.0}},
	{"id": "callcenter", "name": "Call Center", "branch": "sales", "ring": 5, "cost": 400, "parent": "autodialer",
		"desc": "10 base sales a second, and every deal earns a further 3% of income.",
		"fx": {"autoclick": 10.0, "click_pct": 0.03}},
	# start - every new run
	{"id": "seed", "name": "Seed Money", "branch": "start", "ring": 1, "cost": 2, "parent": "",
		"desc": "Every run starts with $1,000.", "fx": {"start_cash": 1000.0}},
	{"id": "contacts", "name": "Old Contacts", "branch": "start", "ring": 2, "cost": 10, "parent": "seed",
		"desc": "Every run starts with 10 Lemonade Stands and 5 Paper Routes.",
		"fx": {"start_producers": {"lemonade": 10, "paper": 5}}},
	{"id": "angel", "name": "Angel Investor", "branch": "start", "ring": 3, "cost": 60, "parent": "contacts",
		"desc": "Every run starts with 0.1% of your best run.", "fx": {"start_best_pct": 0.001}},
	{"id": "bulk", "name": "Bulk Discount", "branch": "start", "ring": 4, "cost": 200, "parent": "angel",
		"desc": "Everything in the shop is 10% cheaper.", "fx": {"discount": 0.10}},
	# fortune - VIPs
	{"id": "mouth", "name": "Word of Mouth", "branch": "fortune", "ring": 1, "cost": 3, "parent": "",
		"desc": "VIPs show up twice as often.", "fx": {"vip_freq": 2.0}},
	{"id": "carpet", "name": "Red Carpet", "branch": "fortune", "ring": 2, "cost": 15, "parent": "mouth",
		"desc": "Rush Hour lasts 50% longer.", "fx": {"rush_len": 1.5}},
	{"id": "roller", "name": "High Roller", "branch": "fortune", "ring": 3, "cost": 80, "parent": "carpet",
		"desc": "Windfalls pay double.", "fx": {"windfall_mult": 2.0}},
	{"id": "whale", "name": "Whale Watching", "branch": "fortune", "ring": 4, "cost": 250, "parent": "roller",
		"desc": "VIPs linger twice as long, and Rush Hour is x10.", "fx": {"vip_linger": 2.0, "rush_mult": 10.0}},
	# legacy - the prestige itself
	{"id": "reputation", "name": "Reputation", "branch": "legacy", "ring": 1, "cost": 5, "parent": "",
		"desc": "Cashing out yields 10% more legacy.", "fx": {"legacy_bonus": 0.10}},
	{"id": "nightshift", "name": "Night Shift", "branch": "legacy", "ring": 2, "cost": 30, "parent": "reputation",
		"desc": "Earn 50% of income while away, for up to 8 hours.",
		"fx": {"offline_rate": 0.50, "offline_cap": 8.0 * 3600.0}},
	{"id": "dynasty", "name": "Dynasty", "branch": "legacy", "ring": 3, "cost": 50, "parent": "nightshift",
		"desc": "Cashing out yields 25% more legacy.", "fx": {"legacy_bonus": 0.25}},
	{"id": "empire", "name": "Empire", "branch": "legacy", "ring": 4, "cost": 300, "parent": "dynasty",
		"desc": "Cashing out yields 50% more legacy.", "fx": {"legacy_bonus": 0.50}},
]

# ----------------------------------------------------------------- derived
var upgrades: Array[Dictionary] = []      ## every one-off upgrade, shop order
var upgrade_by_id: Dictionary = {}
var producer_by_id: Dictionary = {}       ## id -> index
var node_by_id: Dictionary = {}
var tree_total_cost: int = 0

func _ready() -> void:
	for i in range(PRODUCERS.size()):
		producer_by_id[PRODUCERS[i][0]] = i
	for n in TREE:
		node_by_id[n["id"]] = n
		tree_total_cost += int(n["cost"])
	_build_upgrades()

func _build_upgrades() -> void:
	for i in range(PRODUCERS.size()):
		var p: Array = PRODUCERS[i]
		var pid := String(p[0])
		var names: Array = TIER_NAMES[pid]
		for t in range(TIER_OWNED.size()):
			upgrades.append({
				"id": "%s_%d" % [pid, t],
				"name": names[t],
				"kind": "producer",
				"target": pid,
				"tier": t,
				"cost": float(p[2]) * float(TIER_COST[t]),
				"mult": 2.0,
				"blurb": "%ss are twice as effective." % String(p[1]),
				"need": "Own %d" % int(TIER_OWNED[t]),
			})
	for c in CLICK_UPGRADES:
		upgrades.append({
			"id": "click_" + String(c[0]),
			"name": String(c[1]),
			"kind": "click",
			"cost": float(c[2]),
			"mult": float(c[3]),
			"pct": float(c[4]),
			"window": float(c[5]),
			"speed": float(c[6]),
			"blurb": String(c[7]),
		})
	for b in BRAND_UPGRADES:
		upgrades.append({
			"id": "brand_" + String(b[0]),
			"name": String(b[1]),
			"kind": "brand",
			"cost": float(b[2]),
			"bonus": float(b[3]),
			"blurb": String(b[4]),
		})
	for u in upgrades:
		upgrade_by_id[u["id"]] = u

func producer(i: int) -> Array:
	return PRODUCERS[i]

func producer_index(id: String) -> int:
	return int(producer_by_id.get(id, -1))

func producer_name(id: String) -> String:
	return String(PRODUCERS[producer_index(id)][1])

func base_cost(id: String) -> float:
	return float(PRODUCERS[producer_index(id)][2])

func base_rate(id: String) -> float:
	return float(PRODUCERS[producer_index(id)][3])

func node(id: String) -> Dictionary:
	return node_by_id.get(id, {})

func branch_name(id: String) -> String:
	return String(BRANCHES[id]["name"])
