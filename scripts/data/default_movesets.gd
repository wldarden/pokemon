class_name DefaultMovesets
extends RefCounted
## Phase 1 placeholder: hardcoded move lists per species since Species.learnset
## isn't populated yet (Phase 2 will fetch full learnsets from PokéAPI). Used
## when spawning wild Pokémon in EncounterZone.

const TACKLE    := preload("res://data/moves/tackle.tres")
const SCRATCH   := preload("res://data/moves/scratch.tres")
const VINE_WHIP := preload("res://data/moves/vine_whip.tres")
const EMBER     := preload("res://data/moves/ember.tres")

static func for_species(dex_number: int) -> Array[Move]:
	match dex_number:
		1:  return [TACKLE, VINE_WHIP]  # Bulbasaur
		4:  return [SCRATCH, EMBER]     # Charmander
		7:  return [TACKLE]             # Squirtle (no Bubble fetched yet)
	return [TACKLE]
