extends Node
## Palette. One place, so the whole game stays in key.
##
## Money, but not casino money. Charcoal and slate for the chrome, cream for
## ink, a bill green for cash and an old brass for legacy. Accents are
## desaturated so a screen full of numbers still reads as a place and not as
## a spreadsheet with a glow filter on it.

const VOID    := Color("0d0f12")   ## deep charcoal-blue
const PANEL   := Color("15181d")
const PANEL_2 := Color("1d2127")
const RAISED  := Color("262b32")
const LINE    := Color("343a43")

const INK     := Color("e6dfd0")   ## cream
const DIM     := Color("9a958a")
const FAINT   := Color("5e5b55")

const CASH    := Color("8fbf7f")   ## bill green      - money, income
const GOLD    := Color("d4a94f")   ## old brass       - legacy, VIPs
const AMBER   := Color("d9a066")   ## amber           - clicks, salesmanship
const STEEL   := Color("7fa8c9")   ## steel blue      - head start
const MAUVE   := Color("b48ead")   ## dusty mauve     - legacy branch
const DANGER  := Color("c0604f")
const GOOD    := CASH

## Branch accents, keyed by the branch ids used in Balance.gd.
const BRANCH := {
	"operations": CASH,
	"sales": AMBER,
	"start": STEEL,
	"fortune": GOLD,
	"legacy": MAUVE,
}

func branch(id: String) -> Color:
	return BRANCH.get(id, CASH)

## One colour per producer, in shop order. Low saturation, spread across the
## wheel so the street reads as a row of different businesses.
const PRODUCER: Array[Color] = [
	Color("d8c26a"),   ## lemonade    - lemon
	Color("b8b0a0"),   ## paper route - newsprint
	Color("c98a5a"),   ## food cart   - grill
	Color("7fb08a"),   ## corner store- awning green
	Color("6fa3c0"),   ## car wash    - water
	Color("c96a6a"),   ## diner       - neon red
	Color("d4a94f"),   ## franchise   - arches
	Color("7c8fa6"),   ## shipping    - hull grey
	Color("9b86c9"),   ## startup     - violet
	Color("a6a08a"),   ## bank        - marble
	Color("5f8f7f"),   ## hedge fund  - ledger green
	Color("c7b6d9"),   ## orbital     - pale lilac
]

func producer(i: int) -> Color:
	return PRODUCER[clampi(i, 0, PRODUCER.size() - 1)]

# ------------------------------------------------------------------ street
const SKY_DAY   := Color("6f98b8")
const SKY_DUSK  := Color("b5735a")
const SKY_NIGHT := Color("121627")
const HORIZON_DAY   := Color("c9d3d6")
const HORIZON_DUSK  := Color("e0a06a")
const HORIZON_NIGHT := Color("232a44")
const SKYLINE   := Color("1a1f29")
const ROAD      := Color("1f2126")
const ROAD_LINE := Color("6a6238")
const SIDEWALK  := Color("3b3e44")
const KERB      := Color("50545b")
const HQ_WALL   := Color("3a3f4a")
const HQ_TRIM   := Color("5a606c")
const WINDOW_LIT := Color("e8c877")
const WINDOW_DARK := Color("1c2028")
const SIGN      := Color("e6dfd0")
const COIN      := Color("e2b849")
const COIN_DARK := Color("a5812a")
const RUSH_TINT := Color(0.83, 0.66, 0.31, 0.10)
