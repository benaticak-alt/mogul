# MOGUL

A money incremental for Godot 4. Click the till, buy the block, sell the
company, do it again richer. The left of the screen is a street where your HQ
grows a floor per order of magnitude earned and every business you own takes
a lot beside it; the right is the shop. Cash Out is the prestige: it pays
**legacy**, which buys perks in a five-spoke tree that survive every reset.

Pacing is measured with the in-engine bot rather than guessed at - see
**Balance** below.

## Playing

```
Godot_v4.7.2-stable_win64.exe --path .
```

- **Click the HQ** (or press **SPACE**) to make a sale. That is the whole
  economy for the first minute.
- **BUY** tab: twelve businesses, Lemonade Stand to Orbital Mining. Prices
  climb 15% per unit. **x1 / x10 / x100 / MAX** sets the batch; **TAB** cycles it.
- **UPGRADES** tab: one-off doublings for each business at 1 / 10 / 25 / 50 /
  100 / 150 owned, sales upgrades, and brand upgrades that lift everything.
  The tab shows how many you can afford right now.
- **A gold VIP** crosses the street every couple of minutes. Click them for a
  **Windfall** (a lump sum) or a **Rush Hour** (x7 income for 40 s). Miss
  them and they walk off.
- **CASH OUT** when the button lights up. Cash, businesses and upgrades go;
  you keep legacy and open the tree.
- **L** opens the **Legacy Tree**, **B / U / S** switch shop tabs, **M**
  mutes, **ESC** is the menu.

The game autosaves every 30 s and on close, and pays 25% of income for up to
two hours while it is closed (Night Shift raises both to 50% and eight hours).

## The loop

1. **Sell.** Manual sales are worth $1, doubled by each sales upgrade, plus a
   slice of income once The Upsell is bought. They matter in the first minutes
   of every run and fade after; that is by design, and it is where the VIPs
   take over as the active-play edge.
2. **Buy.** Producers pay per second. Each business's income share and payback
   time is in its tooltip; the shop rows bounce when they become affordable.
3. **Cash Out.** Legacy is cut from **lifetime** earnings on a square-root
   curve: `legacy = sqrt(lifetime / $1M)`, less what you already hold. Every
   legacy level is **+2% income forever** (Conglomerate makes it +4%), so runs
   get shorter, not longer, as the levels stack.
4. **Spend.** Twenty-two perks on five spokes:
   - **Operations** - flat income multipliers, ending in the doubled level bonus.
   - **Salesmanship** - sale multipliers, income-per-sale, then the Autodialer
     and Call Center that click for you.
   - **Head Start** - seed cash, starting businesses, a cut of your best run,
     a shop discount.
   - **Fortune** - VIP frequency, longer rushes, double windfalls, x10 rush.
   - **Legacy** - more legacy per Cash Out, and Night Shift for offline pay.

## Balance

All tuning is in `scripts/autoload/Balance.gd`. There is no JSON and no
external script: the numbers the bot measures are the numbers that ship.

```
Godot_v4.7.2-stable_win64.exe --headless --path . -- --autoplay 12 [--cps 3]
```

The bot drives the real `Game` autoload: it clicks at a steady rate, buys
whatever pays back soonest counting the wait to afford it, catches 75% of
VIPs, cashes out when the level would grow 60% (or by 3 for the first), and
buys perks cheapest-first. Current numbers, 3 sales/s:

| milestone | time | run | level |
|---|---|---|---|
| first $1K | 2m 11s | 1 | 0 |
| first $1M | 22m | 1 | 0 |
| first Cash Out (+3) | 29m | 1 | 3 |
| first $1B | 2h 57m | 6 | 26 |
| first $1T | 5h 10m | 14 | 1148 |
| **tree complete** | **5h 18m** | 15 | 2944 |

Runs go 29 → 36 → 31 → 30 → 27 → 23 → 17 → 13 → 7 → 6 minutes as legacy
compounds. A lazy clicker (0.5/s) finishes six minutes later; the curve makes
flat multipliers cheap, so clicking is an on-ramp rather than an engine. A
real player who clicks in bursts and cashes out on feel should land somewhere
between six and ten hours to the last perk, less with offline time.

Things worth knowing before retuning:

- `LEGACY_POWER` is the shape of the whole endgame. Cube root was tried first
  and made runs lengthen every prestige (35 m → 1 h 37 m by run 7) with the
  tree hundreds of hours away. Square root is what makes runs shorten.
- `LEVEL_BONUS` at 1% was too weak to feel; 2% is what makes each Cash Out
  visibly faster than the last.
- The producer cost ladder is Cookie Clicker's, unchanged. It is not the part
  of this game that needs to be clever.
- The bot writes no save. Run it as often as you like.

## Verifying

```
# save / load round trip - run after touching persistence
Godot_v4.7.2-stable_win64.exe --headless --path . -- --roundtrip

# screenshots with staged state, for checking layout without playing to it
Godot_v4.7.2-stable_win64.exe --path . -- --shot out.png --earned 5e6 --shop 30 --cash 50000 --time 40
Godot_v4.7.2-stable_win64.exe --path . -- --shot out.png --earned 3e11 --shop 40 --level 120 --time 180 --vip --rush
Godot_v4.7.2-stable_win64.exe --path . -- --shot out.png --level 40 --tree
Godot_v4.7.2-stable_win64.exe --path . -- --shot out.png --tab upgrades --dialog cashout
```

`--time` is seconds into the six-minute day cycle (180 is midnight).
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
scripts/StreetView.gd         the street: HQ, lots, coins, people, cars, VIP, day cycle
scripts/Autoplay.gd           the verification bot
scripts/autoload/Balance.gd   every number
scripts/autoload/Game.gd      the economy, prestige, tree effects, save/load
scripts/autoload/Pal.gd       palette
scripts/autoload/Fmt.gd       number formatting
scripts/autoload/SFX.gd       synthesised audio
scripts/ui/TopBar.gd          cash, legacy, the three buttons
scripts/ui/ShopPanel.gd       BUY / UPGRADES / STATS
scripts/ui/LegacyTree.gd      the tree overlay
scripts/ui/Overlay.gd         dialogs and toasts
scripts/ui/UiKit.gd           widget builders
scripts/ui/Tooltip.gd         the one shared tooltip
```

Everything is drawn or built in code; there is no asset folder.
