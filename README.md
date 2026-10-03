# MOGUL

A money incremental for Godot 4. Close deals, buy the block, sell the company,
do it again richer. The street fills the window — your HQ grows a floor per
order of magnitude earned, and every business you own takes a lot beside it.
Everything else is summoned by a button. **Cash Out** is the prestige: it pays
**legacy**, which buys perks in a five-spoke tree that survive every reset.

Pacing is measured with the in-engine bot rather than guessed at — see
**Balance** below.

## Playing

```
Godot_v4.7.2-stable_win64.exe --path .
```

### The deal

A sale is a timing minigame, not a mash. **Click anywhere** (or press
**SPACE**) to open a deal: a marker starts running along the bar above your
HQ. **Click again inside the green** to close it.

| outcome | payout |
|---|---|
| closed in the green | **x2.5**, and your streak goes up |
| closed early | base, streak resets |
| marker runs off the end | **x0.5**, streak resets |

Every clean close in a row adds **+15%** up to x2.5 at a streak of ten. The
streak lapses after about two and a half seconds idle, so it rewards staying
in the rhythm rather than remembering to click once a minute.

Deal upgrades double the payout; some also widen the green or shorten the
cycle, so the minigame gets easier as well as richer. The **Autodialer** and
**Call Center** perks grind out flat base sales on their own — no streak, but
they never stop.

### Everything else

- **SHOP** (**S**) opens the drawer. Twelve businesses, Lemonade Stand to
  Orbital Mining, prices climbing 15% per unit. **TAB** cycles the batch size
  between x1 / x10 / x100 / MAX.
- **UPGRADES** — one-off doublings for each business at 1 / 10 / 25 / 50 /
  100 / 150 owned, deal upgrades, and brand upgrades that lift everything. The
  SHOP button shows how many you can afford right now.
- **1 / 2 / 3** jump straight to the Buy, Upgrades and Stats tabs.
- **A gold VIP** crosses the street every couple of minutes. Click them for a
  **Windfall** (a lump sum) or a **Rush Hour** (x7 income for 40 s). Miss them
  and they walk off. The VIP wins any overlap with a deal click.
- **CASH OUT** appears once it is worth a legacy point.
- **TREE** (**L**) is the legacy tree, **M** mutes, **ESC** backs out of
  whatever is open and then opens the menu.

The game autosaves every 30 s and on close, and pays 25% of income for up to
two hours while it is closed (Night Shift raises both to 50% and eight hours).

## The loop

1. **Close deals.** Worth real money in the first minutes of every run and
   fading after, which is where the VIPs take over as the active-play edge.
2. **Buy.** Producers pay per second. Each business's income share and payback
   time is in its tooltip; shop rows bounce when they become affordable.
3. **Cash Out.** Legacy is cut from **lifetime** earnings on a square-root
   curve: `legacy = sqrt(lifetime / $1M)`, less what you already hold. Every
   legacy level is **+2% income forever** (Conglomerate makes it +4%), so runs
   get shorter, not longer, as the levels stack.
4. **Spend.** Twenty-two perks on five spokes:
   - **Operations** — flat income multipliers, ending in the doubled level bonus.
   - **Salesmanship** — deal payout, a wider green, a faster cycle, then the
     Autodialer and Call Center that grind for you.
   - **Head Start** — seed cash, starting businesses, a cut of your best run,
     a shop discount.
   - **Fortune** — VIP frequency, longer rushes, double windfalls, x10 rush.
   - **Legacy** — more legacy per Cash Out, and Night Shift for offline pay.

## Balance

All tuning is in `scripts/autoload/Balance.gd`. There is no JSON and no
external script: the numbers the bot measures are the numbers that ship.

```
Godot_v4.7.2-stable_win64.exe --headless --path . -- --autoplay 12 [--acc 0.8]
```

The bot drives the real `Game` autoload and **plays the minigame** — it opens
a deal, commits to hitting or missing at the given accuracy, and closes
accordingly — so the deal cycle really does cap what clicking can contribute.
It buys whatever pays back soonest counting the wait to afford it, catches 75%
of VIPs, cashes out when the level would grow 60% (or by 3 for the first), and
buys perks cheapest-first.

| milestone | 80% accuracy | 35% accuracy |
|---|---|---|
| first $1M | 20m | 17m |
| first $1B | 2h 25m | 2h 47m |
| **tree complete** | **4h 50m** | **4h 59m** |
| mean run length | 19m 22s | 19m 56s |
| deals closed | 19.2K at 1.10/s | 22.3K at 1.24/s |
| best streak | 32 | 7 |

Runs shorten from about 30 minutes to under 7 as legacy compounds. Playing the
minigame well is worth roughly 9 minutes over a five-hour game — deliberately
modest, because an incremental where clicking stays dominant is a chore. A
real player who opens deals in bursts and cashes out on feel should land
somewhere between six and ten hours to the last perk, less with offline time.

Things worth knowing before retuning:

- `LEGACY_POWER` is the shape of the whole endgame. Cube root was tried first
  and made runs *lengthen* every prestige (35 m → 1 h 37 m by run 7) with the
  tree hundreds of hours away. Square root is what makes runs shorten.
- `LEVEL_BONUS` at 1% was too weak to feel; 2% is what makes each Cash Out
  visibly faster than the last.
- `DEAL_TIME` is the real pacing lever on the minigame. It sets how often the
  player is asked to do anything at all, and a game that asks every 0.4 s is a
  mash with extra steps.
- The bot's misses must be forced clear of the green. Late in a run the cycle
  is short and the zone is wide enough that a simulation step can land inside
  it by accident, which quietly turned the bot into a better player than it
  was being asked to be — it reported an 86-deal streak at 80% accuracy before
  this was fixed.
- The producer cost ladder is Cookie Clicker's, unchanged. It is not the part
  of this game that needs to be clever.
- The bot writes no save. Run it as often as you like.

## Verifying

```
# save / load round trip - run after touching persistence
Godot_v4.7.2-stable_win64.exe --headless --path . -- --roundtrip

# screenshots with staged state, for checking layout without playing to it
Godot.exe --path . -- --shot out.png --earned 5e6 --shop 30 --cash 50000 --deal 0.56 --combo 7
Godot.exe --path . -- --shot out.png --drawer-closed --earned 3e11 --shop 40 --level 120 --time 200 --vip
Godot.exe --path . -- --shot out.png --level 40 --tree
Godot.exe --path . -- --shot out.png --tab upgrades --dialog cashout
```

`--time` is seconds into the six-minute day cycle (180 is midnight).
`--deal 0..1` stages a deal in progress with the green at 0.52, `--combo N`
sets the streak, `--drawer-closed` hides the shop.
`--dialog` takes `cashout`, `menu`, `away`, `wipe` or `complete`; `--tab`
takes `upgrades` or `stats`.

A fresh checkout needs one import pass before headless runs will resolve
`class_name` scripts:

```
Godot_v4.7.2-stable_win64.exe --headless --path . --import
```

## Layout

```
project.godot
scenes/Main.tscn              one Control with Main.gd on it
scripts/Main.gd               layout, keyboard, --autoplay / --shot / --roundtrip
scripts/StreetView.gd         the scene, the deal bar and the readouts
scripts/Autoplay.gd           the verification bot
scripts/autoload/Balance.gd   every number
scripts/autoload/Game.gd      the economy, the deal, prestige, tree, save/load
scripts/autoload/Pal.gd       palette
scripts/autoload/Fmt.gd       number formatting
scripts/autoload/SFX.gd       synthesised audio
scripts/ui/ShopPanel.gd       the shop drawer - BUY / UPGRADES / STATS
scripts/ui/LegacyTree.gd      the tree overlay
scripts/ui/Overlay.gd         dialogs and toasts
scripts/ui/UiKit.gd           widget builders
scripts/ui/Tooltip.gd         the one shared tooltip
```

The street is the window and everything else floats on top of it, so the
readouts are drawn into the scene over a scrim rather than boxed in a panel.
Everything is drawn or built in code; there is no asset folder.
