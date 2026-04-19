class_name Enums
extends RefCounted
## All shared enumerations for the Pokémon data model.
## Values are stable — do not reorder once referenced by .tres files.

enum Type {
	NORMAL    = 0,
	FIRE      = 1,
	WATER     = 2,
	GRASS     = 3,
	ELECTRIC  = 4,
	ICE       = 5,
	FIGHTING  = 6,
	POISON    = 7,
	GROUND    = 8,
	FLYING    = 9,
	PSYCHIC   = 10,
	BUG       = 11,
	ROCK      = 12,
	GHOST     = 13,
	DRAGON    = 14,
	DARK      = 15,  # Gen 2+
	STEEL     = 16,  # Gen 2+
	NONE      = 17,  # sentinel / no-type
	COUNT     = 18,
}

enum Category {
	PHYSICAL = 0,
	SPECIAL  = 1,
	STATUS   = 2,
}

enum StatKey {
	HP          = 0,
	ATTACK      = 1,
	DEFENSE     = 2,
	SP_ATTACK   = 3,
	SP_DEFENSE  = 4,
	SPEED       = 5,
}

enum StatusCondition {
	NONE       = 0,
	BURN       = 1,
	POISON     = 2,
	BAD_POISON = 3,
	PARALYSIS  = 4,
	SLEEP      = 5,
	FREEZE     = 6,
}

# Gen 3 natures — 25 total. Index 0 is Hardy (neutral).
# Each entry is (plus_stat, minus_stat) from StatKey. NONE for neutral.
enum Nature {
	HARDY   = 0,  # neutral
	LONELY  = 1,  # +Atk -Def
	BRAVE   = 2,  # +Atk -Spe
	ADAMANT = 3,  # +Atk -SpA
	NAUGHTY = 4,  # +Atk -SpD
	BOLD    = 5,  # +Def -Atk
	DOCILE  = 6,  # neutral
	RELAXED = 7,  # +Def -Spe
	IMPISH  = 8,  # +Def -SpA
	LAX     = 9,  # +Def -SpD
	TIMID   = 10, # +Spe -Atk
	HASTY   = 11, # +Spe -Def
	SERIOUS = 12, # neutral
	JOLLY   = 13, # +Spe -SpA
	NAIVE   = 14, # +Spe -SpD
	MODEST  = 15, # +SpA -Atk
	MILD    = 16, # +SpA -Def
	QUIET   = 17, # +SpA -Spe
	BASHFUL = 18, # neutral
	RASH    = 19, # +SpA -SpD
	CALM    = 20, # +SpD -Atk
	GENTLE  = 21, # +SpD -Def
	SASSY   = 22, # +SpD -Spe
	CAREFUL = 23, # +SpD -SpA
	QUIRKY  = 24, # neutral
}

enum GrowthRate {
	MEDIUM_FAST  = 0,  # exp = level^3
	ERRATIC      = 1,
	FLUCTUATING  = 2,
	MEDIUM_SLOW  = 3,  # exp = 6/5 n^3 - 15 n^2 + 100 n - 140
	FAST         = 4,  # exp = 4/5 n^3
	SLOW         = 5,  # exp = 5/4 n^3
}

# Returns (plus_stat, minus_stat). PlayerKey.HP is never modified; using HP
# as a sentinel here means "no change".
static func nature_effect(n: int) -> Array:
	match n:
		Nature.LONELY:   return [StatKey.ATTACK, StatKey.DEFENSE]
		Nature.BRAVE:    return [StatKey.ATTACK, StatKey.SPEED]
		Nature.ADAMANT:  return [StatKey.ATTACK, StatKey.SP_ATTACK]
		Nature.NAUGHTY:  return [StatKey.ATTACK, StatKey.SP_DEFENSE]
		Nature.BOLD:     return [StatKey.DEFENSE, StatKey.ATTACK]
		Nature.RELAXED:  return [StatKey.DEFENSE, StatKey.SPEED]
		Nature.IMPISH:   return [StatKey.DEFENSE, StatKey.SP_ATTACK]
		Nature.LAX:      return [StatKey.DEFENSE, StatKey.SP_DEFENSE]
		Nature.TIMID:    return [StatKey.SPEED, StatKey.ATTACK]
		Nature.HASTY:    return [StatKey.SPEED, StatKey.DEFENSE]
		Nature.JOLLY:    return [StatKey.SPEED, StatKey.SP_ATTACK]
		Nature.NAIVE:    return [StatKey.SPEED, StatKey.SP_DEFENSE]
		Nature.MODEST:   return [StatKey.SP_ATTACK, StatKey.ATTACK]
		Nature.MILD:     return [StatKey.SP_ATTACK, StatKey.DEFENSE]
		Nature.QUIET:    return [StatKey.SP_ATTACK, StatKey.SPEED]
		Nature.RASH:     return [StatKey.SP_ATTACK, StatKey.SP_DEFENSE]
		Nature.CALM:     return [StatKey.SP_DEFENSE, StatKey.ATTACK]
		Nature.GENTLE:   return [StatKey.SP_DEFENSE, StatKey.DEFENSE]
		Nature.SASSY:    return [StatKey.SP_DEFENSE, StatKey.SPEED]
		Nature.CAREFUL:  return [StatKey.SP_DEFENSE, StatKey.SP_ATTACK]
	# Neutral natures (Hardy, Docile, Serious, Bashful, Quirky).
	return [StatKey.HP, StatKey.HP]
