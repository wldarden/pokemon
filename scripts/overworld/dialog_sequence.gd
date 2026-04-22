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
##
## The DialogBox autoload is looked up by node path rather than identifier
## so this script compiles before the autoload is registered in 2d.3.
## Say steps become no-ops if DialogBox isn't registered yet.
func run() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var dialog_box: Node = tree.root.get_node_or_null("DialogBox")
	for step in _steps:
		match step["kind"]:
			"say":
				if dialog_box != null:
					await dialog_box.queue([step["text"]])
			"wait":
				await tree.create_timer(step["seconds"]).timeout
			"call":
				var fn: Callable = step["fn"]
				fn.call()
