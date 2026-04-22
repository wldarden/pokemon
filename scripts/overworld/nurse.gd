extends Area2D
## Phase 2d — Pokémon Center nurse. Interacted with via A press.
## Runs the canonical heal sequence: dialog, pause + heal, follow-up dialog.

## Cell position on the interior map. Queried by Player._try_interact.
## Set by PokemonCenter.tscn to (7, 3) — the counter tile directly in front
## of the nurse — so the player talks to her from one row below. The
## default here is a harmless fallback.
@export var cell: Vector2i = Vector2i(7, 3)

func _ready() -> void:
	add_to_group("blockers")

func on_interact() -> void:
	await DialogSequence.new() \
		.say("Welcome to the POKéMON CENTER!") \
		.say("We restore your POKéMON to full health.") \
		.wait(0.3) \
		.call_fn(GameState.heal_party) \
		.say("…Done! We hope to see you again!") \
		.run()
