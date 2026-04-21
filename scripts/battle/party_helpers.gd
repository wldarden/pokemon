class_name PartyHelpers
extends RefCounted
## Phase 2c: stateless party-inspection helpers used by Battle and PartyScreen.
## Pure functions — no state, no side effects. Unit-tested in test_party_switching.

## Index of the first non-fainted Pokémon in `party`, or -1 if the whole
## party is fainted (team-wipe signal).
static func first_non_fainted(party: Array) -> int:
	for i in party.size():
		var mon = party[i]
		if mon != null and not mon.is_fainted():
			return i
	return -1

## True iff every member of `party` is fainted (or the party is empty).
static func all_fainted(party: Array) -> bool:
	for mon in party:
		if mon != null and not mon.is_fainted():
			return false
	return true

## True iff the player could legally switch to slot `idx`:
##   - slot is occupied,
##   - mon is not fainted,
##   - slot is not the current active slot (can't swap with self).
static func can_switch_to(party: Array, idx: int, active_idx: int) -> bool:
	if idx == active_idx:
		return false
	if idx < 0 or idx >= party.size():
		return false
	var mon = party[idx]
	if mon == null or mon.is_fainted():
		return false
	return true
