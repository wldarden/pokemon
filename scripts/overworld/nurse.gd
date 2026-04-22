extends Area2D
## Phase 2d — Pokémon Center nurse. Interacted with via A press.
## Runs the canonical heal sequence: dialog, pause + heal, follow-up dialog.

## Cell position on the interior map. Queried by Player._try_interact.
@export var cell: Vector2i = Vector2i(7, 2)

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
