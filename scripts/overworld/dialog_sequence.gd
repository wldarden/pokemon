class_name DialogSequence
extends RefCounted
## Phase 2d — fluent builder for scripted overworld narration.
##
## Usage:
##   await DialogSequence.new() \
##       .say("Welcome!") \
##       .wait(0.3) \
##       .call_fn(func(): GameState.heal_party()) \
##       .say("Done.") \
##       .run()
##
## Each step is awaited in order. `say` delegates to the DialogBox autoload,
## which is added in task 2d.3. `run()` isn't exercised until then.

var _steps: Array = []

static func create() -> DialogSequence:
	return DialogSequence.new()

func say(text: String) -> DialogSequence:
	_steps.append({"kind": "say", "text": text})
	return self

func wait(seconds: float) -> DialogSequence:
	_steps.append({"kind": "wait", "seconds": seconds})
	return self

func call_fn(callable: Callable) -> DialogSequence:
	_steps.append({"kind": "call", "fn": callable})
	return self

func size() -> int:
	return _steps.size()

## Run the queued steps sequentially. Awaits DialogBox.queue for say lines,
## Timer for waits, and invokes callables synchronously. Returns when done.
func run() -> void:
	for step in _steps:
		match step["kind"]:
			"say":
				await DialogBox.queue([step["text"]])
			"wait":
				await Engine.get_main_loop().create_timer(step["seconds"]).timeout
			"call":
				var fn: Callable = step["fn"]
				fn.call()
