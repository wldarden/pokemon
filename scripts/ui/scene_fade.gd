extends CanvasLayer
## Phase 2d autoload singleton. Persistent black-rect overlay for fade
## transitions. Layer = 100 so it overlays everything including battle.

@onready var rect: ColorRect = $Rect

func _ready() -> void:
	rect.modulate.a = 0.0

## Fade the screen to black over `duration` seconds. Awaitable.
func fade_out(duration: float = 0.25) -> void:
	var tw := create_tween()
	tw.tween_property(rect, "modulate:a", 1.0, duration)
	await tw.finished

## Fade the screen from black back to transparent. Awaitable.
func fade_in(duration: float = 0.25) -> void:
	var tw := create_tween()
	tw.tween_property(rect, "modulate:a", 0.0, duration)
	await tw.finished
