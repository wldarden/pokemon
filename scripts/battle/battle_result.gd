class_name BattleResult
extends RefCounted
## Returned by the Battle scene via the battle_ended signal.

enum Outcome {
	WIN      = 0,
	LOSE     = 1,
	ESCAPED  = 2,  # Phase 3+ (running)
	CAUGHT   = 3,  # Phase 3+ (catching)
}

var outcome: int = Outcome.WIN
var xp_gained: int = 0
var money_gained: int = 0       # Phase 3+
var caught_species_dex: int = -1  # Phase 3+
