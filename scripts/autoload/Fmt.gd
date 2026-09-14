extends Node
## Number and time formatting. The cash readout is the whole game, so it gets
## one home and one consistent style everywhere.

const SUFFIX: PackedStringArray = [
	"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc",
	"UDc", "DDc", "TDc", "QaDc", "QiDc", "SxDc", "SpDc", "OcDc", "NoDc", "Vg",
]

## Compact readout: 1234567 -> "1.23M". Falls back to scientific past the
## suffix table so the display never breaks at the deep end of the game.
func num(v: float) -> String:
	if not is_finite(v):
		return "INF"
	if v < 0.0:
		return "-" + num(-v)
	if v < 1000.0:
		if v < 10.0 and v != floorf(v):
			return "%.2f" % v
		if v < 100.0 and v != floorf(v):
			return "%.1f" % v
		return "%d" % int(v)
	# Divide down rather than deriving the magnitude from a log: log10(1e12)
	# lands just under 12.0 in float and silently renders 1T as "1000.0B".
	var mag := 0
	var scaled := v
	while scaled >= 1000.0 and mag < SUFFIX.size() - 1:
		scaled /= 1000.0
		mag += 1
	if scaled >= 1000.0:
		var e := int(floor(log(v) / log(10.0)))
		return "%.2fe%d" % [v / pow(10.0, float(e)), e]
	if scaled >= 100.0:
		return "%.1f%s" % [scaled, SUFFIX[mag]]
	return "%.2f%s" % [scaled, SUFFIX[mag]]

## Money. Whole dollars once there are enough of them to stop caring about
## cents, cents while a lemonade is still a meaningful fraction of the bank.
func cash(v: float) -> String:
	if v < 0.0:
		return "-" + cash(-v)
	if v < 1000.0:
		if v < 100.0 and v != floorf(v):
			return "$%.2f" % v
		return "$%d" % int(v)
	return "$" + num(v)

## Whole-number readout for counts that should never show decimals.
func count(v: float) -> String:
	if v < 1000.0:
		return "%d" % int(v)
	return num(v)

func per_sec(v: float) -> String:
	return cash(v) + "/s"

func mult(v: float) -> String:
	if v < 10.0:
		return "x%.2f" % v
	return "x" + num(v)

func pct(v: float) -> String:
	if v < 0.1:
		return "%.2f%%" % (v * 100.0)
	return "%.1f%%" % (v * 100.0)

## Percent with no decimals unless there are some: 0 -> "0%", 2.5 -> "2.5%".
func pct_whole(v: float) -> String:
	var h := v * 100.0
	if absf(h - roundf(h)) < 0.05:
		return "%d%%" % int(roundf(h))
	return "%.1f%%" % h

func time(seconds: float) -> String:
	if seconds < 0.0:
		seconds = 0.0
	var s := int(seconds)
	var h := s / 3600
	var m := (s % 3600) / 60
	var sec := s % 60
	if h > 0:
		return "%dh %02dm" % [h, m]
	if m > 0:
		return "%dm %02ds" % [m, sec]
	return "%ds" % sec

## Short form for cooldown pips and other tight spaces.
func secs(seconds: float) -> String:
	return "%.0fs" % maxf(seconds, 0.0)

const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]

func roman(n: int) -> String:
	if n >= 1 and n <= ROMAN.size():
		return ROMAN[n - 1]
	return str(n)
