class_name GrowthCurve
extends RefCounted
## Gen-3 experience curves. One static function per growth rate (see
## Enums.GrowthRate) plus a dispatcher.
##
## Each curve returns the CUMULATIVE experience a Pokémon of that growth rate
## must have to BE at the given level. All formulas and piecewise boundaries
## are from Bulbapedia's "Experience" page:
##   https://bulbapedia.bulbagarden.net/wiki/Experience
##
## All curves clamp to max(0, …) because some (Medium Slow, Fluctuating) yield
## negative values at very low levels.

## Cumulative XP needed to reach `level` under the given growth rate.
static func total_exp_at(rate: int, level: int) -> int:
	if level <= 1:
		return 0
	if level > 100:
		level = 100
	match rate:
		Enums.GrowthRate.MEDIUM_FAST:  return _medium_fast(level)
		Enums.GrowthRate.MEDIUM_SLOW:  return _medium_slow(level)
		Enums.GrowthRate.FAST:         return _fast(level)
		Enums.GrowthRate.SLOW:         return _slow(level)
		Enums.GrowthRate.ERRATIC:      return _erratic(level)
		Enums.GrowthRate.FLUCTUATING:  return _fluctuating(level)
	# Default to Medium Fast if the rate isn't recognised.
	return _medium_fast(level)

## Given a total XP value, return the highest level whose threshold is
## ≤ total_exp. Primarily a test/sanity helper — the battle loop uses the
## explicit level field on PokemonInstance rather than recomputing from XP.
static func level_for_exp(rate: int, total_exp: int) -> int:
	var lv := 1
	while lv < 100 and total_exp_at(rate, lv + 1) <= total_exp:
		lv += 1
	return lv

# ---- Individual curves ---------------------------------------------------

static func _medium_fast(n: int) -> int:
	# n^3
	return int(max(0, n * n * n))

static func _medium_slow(n: int) -> int:
	# (6/5) n^3 - 15 n^2 + 100 n - 140
	var v: float = (6.0 / 5.0) * pow(n, 3) - 15.0 * pow(n, 2) + 100.0 * n - 140.0
	return int(max(0.0, v))

static func _fast(n: int) -> int:
	# (4/5) n^3
	var v: float = (4.0 / 5.0) * pow(n, 3)
	return int(max(0.0, v))

static func _slow(n: int) -> int:
	# (5/4) n^3
	var v: float = (5.0 / 4.0) * pow(n, 3)
	return int(max(0.0, v))

static func _erratic(n: int) -> int:
	# Piecewise (Bulbapedia "Erratic"):
	#   1  ≤ n ≤ 50:  n^3 * (100 - n)       / 50
	#   51 ≤ n ≤ 67:  n^3 * (150 - n)       / 100
	#   68 ≤ n ≤ 97:  n^3 * ((1911 - 10n)/3) / 500
	#   98 ≤ n ≤ 100: n^3 * (160 - n)       / 100
	var n3: float = pow(n, 3)
	var v: float
	if n <= 50:
		v = n3 * (100 - n) / 50.0
	elif n <= 67:
		v = n3 * (150 - n) / 100.0
	elif n <= 97:
		v = n3 * ((1911.0 - 10.0 * n) / 3.0) / 500.0
	else:
		v = n3 * (160 - n) / 100.0
	return int(max(0.0, v))

static func _fluctuating(n: int) -> int:
	# Piecewise (Bulbapedia "Fluctuating"):
	#   1  ≤ n ≤ 15:  n^3 * ((n + 1)/3 + 24) / 50
	#   15 ≤ n ≤ 36:  n^3 * (n + 14)         / 50
	#   36 ≤ n ≤ 100: n^3 * ((n / 2) + 32)   / 50
	var n3: float = pow(n, 3)
	var v: float
	if n <= 15:
		v = n3 * ((n + 1) / 3.0 + 24.0) / 50.0
	elif n <= 36:
		v = n3 * (n + 14) / 50.0
	else:
		v = n3 * ((n / 2.0) + 32.0) / 50.0
	return int(max(0.0, v))
